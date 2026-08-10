---
title: "Networking & Communication Protocols"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Networking & Communication Protocols

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Load Balancing](load_balancing.md), [Caching](caching.md). Đọc tiếp: `advanced/api_design.md`.

---

## 1. Vì sao protocol quan trọng trong system design

Mọi hệ phân tán giao tiếp qua mạng, nên lựa chọn protocol ảnh hưởng trực tiếp tới **độ trễ, thông lượng, khả năng real-time, và độ phức tạp vận hành**. Hiểu tầng này giúp trả lời được các câu hỏi kiểu:

- Vì sao API nội bộ chậm dù server rảnh? (thường là handshake và thiếu connection pool)
- Vì sao gRPC qua L4 LB làm lệch tải? ([load_balancing.md](load_balancing.md) mục 2.1)
- Vì sao chat cần WebSocket mà notification thì SSE là đủ?
- Vì sao đổi từ HTTP/1.1 sang HTTP/2 giúp nhiều với browser nhưng ít với service-to-service?

---

## 2. TCP và UDP

| | TCP | UDP |
|---|---|---|
| Kết nối | Có (3-way handshake) | Không |
| Tin cậy | Ack, retransmit, giữ thứ tự | Best-effort |
| Điều khiển tắc nghẽn | Có | Không (tự lo) |
| Overhead | Cao hơn | Thấp |
| Dùng ở | HTTP, database, hầu hết mọi thứ | DNS, voice/video, gaming, **QUIC/HTTP3** |

### 2.1 Chi phí thiết lập kết nối

```text
TCP handshake:        SYN → SYN-ACK → ACK           = 1 RTT trước khi gửi được dữ liệu
+ TLS 1.2 handshake:                                 = thêm 2 RTT
+ TLS 1.3 handshake:                                 = thêm 1 RTT (0-RTT khi resume)

Cùng DC (RTT 0,5ms):     kết nối mới ≈ 1–1,5ms      → chấp nhận được nhưng vẫn đáng tránh
Liên vùng (RTT 150ms):   kết nối mới ≈ 300–450ms    → THẢM HỌA nếu mỗi request một kết nối
```

Đây là lý do **connection pooling và keep-alive không phải tối ưu vi mô mà là yêu cầu cơ bản**. Một service gọi service khác mà không dùng pool sẽ trả giá handshake cho mọi request. Trong Java, đó là lý do phải cấu hình pool cho HTTP client (`HttpClient` với `HttpClient.Builder`, Apache HttpClient connection manager, hoặc OkHttp `ConnectionPool`) — mặc định của một số client không giữ kết nối như mong đợi.

### 2.2 Head-of-line blocking ở TCP

```text
TCP đảm bảo giữ thứ tự → nếu gói #5 mất, gói #6, #7 đã tới VẪN phải chờ #5 được gửi lại
→ mọi stream chia sẻ cùng kết nối TCP đều bị chặn
```

Đây chính là hạn chế mà HTTP/2 không giải quyết được (vì vẫn trên TCP) và là lý do HTTP/3 chuyển sang UDP.

### 2.3 Vài tham số TCP đáng biết

| Khái niệm | Ảnh hưởng thực tế |
|---|---|
| **Slow start** | Kết nối mới bắt đầu với cửa sổ nhỏ → kết nối mới luôn chậm hơn kết nối đã "nóng" |
| **Bandwidth-delay product** | Thông lượng tối đa = cửa sổ / RTT → RTT cao thì cần cửa sổ lớn, nếu không băng thông bị bỏ trống |
| **Nagle + delayed ACK** | Có thể gây trễ ~40ms cho request nhỏ; `TCP_NODELAY` thường nên bật cho RPC |
| **TIME_WAIT** | Kết nối đóng giữ port một khoảng → nhiều kết nối ngắn có thể cạn port |

`TCP_NODELAY` đáng nhắc riêng: nếu không bật, một request nhỏ có thể bị giữ lại chờ gom thêm dữ liệu, cộng thêm delayed ACK ở đầu kia, tạo ra độ trễ ~40ms không giải thích được. Phần lớn thư viện RPC hiện đại bật sẵn, nhưng code dùng socket trực tiếp thì cần kiểm tra.

---

## 3. HTTP/1.1 → HTTP/2 → HTTP/3

| | HTTP/1.1 | HTTP/2 | HTTP/3 |
|---|---|---|---|
| Transport | TCP | TCP | **QUIC (UDP)** |
| Multiplexing | Không (một request/kết nối tại một thời điểm) | Có (nhiều stream/một kết nối) | Có |
| HOL blocking | Ở tầng ứng dụng | Ở tầng **TCP** (vẫn còn) | **Không** (stream độc lập) |
| Header | Text, lặp lại mỗi request | Binary + nén **HPACK** | Binary + **QPACK** |
| Handshake | TCP + TLS (2–3 RTT) | TCP + TLS | **0–1 RTT** (QUIC gộp transport + crypto) |
| Đổi mạng (wifi↔4G) | Mất kết nối | Mất kết nối | **Connection migration** — giữ kết nối |
| Server push | Không | Có (đã bị bỏ) | Không |

```text
HTTP/1.1: browser mở ~6 kết nối song song mỗi origin để bù việc không multiplex
HTTP/2:   1 kết nối, nhiều stream → giảm handshake và header, nhưng 1 gói TCP mất
          → CHẶN MỌI stream (TCP HOL)
HTTP/3:   QUIC trên UDP → mỗi stream độc lập; mất gói chỉ ảnh hưởng stream đó
          + 0-RTT resume + connection migration
```

### 3.1 Khi nào nâng cấp thực sự có lợi

| Ngữ cảnh | HTTP/2 giúp nhiều? | HTTP/3 giúp nhiều? |
|---|---|---|
| Browser tải trang nhiều tài nguyên | **Rất** (bớt 6 kết nối, nén header) | Có, nhất là mạng kém |
| Mobile, mạng chập chờn | Có | **Rất** (mất gói và đổi mạng) |
| Service-to-service trong DC | Vừa (gRPC dùng HTTP/2 cho streaming) | Ít (mạng DC ít mất gói) |
| API đơn giản, ít request | Ít | Ít |

Kết luận thực dụng: bật HTTP/2 (và HTTP/3 nếu CDN hỗ trợ) ở **edge cho client**; trong nội bộ DC, lợi ích chính của HTTP/2 là **streaming và multiplexing cho gRPC**, không phải hiệu năng thuần.

Một điều cần biết về HTTP/3: UDP đôi khi bị firewall/middlebox chặn, nên mọi triển khai đều phải **fallback về HTTP/2**. Và mã hóa của QUIC tốn CPU hơn ở tầng ứng dụng vì không thể offload xuống kernel/NIC dễ như TLS-over-TCP.

---

## 4. TLS trong thiết kế hệ thống

```text
TLS 1.3: 1 RTT handshake, 0-RTT khi resume (có rủi ro replay với 0-RTT → chỉ dùng cho request idempotent)
mTLS:    cả hai bên trình certificate → xác thực service-to-service không cần secret trong app
```

Ba quyết định thường gặp:

| Quyết định | Lựa chọn |
|---|---|
| Kết thúc TLS ở đâu | Edge/LB (đơn giản), hoặc tới tận backend (tuân thủ) — xem [load_balancing.md](load_balancing.md) mục 6 |
| Mã hóa nội bộ | mTLS qua service mesh là cách phổ biến nhất |
| Quản lý certificate | ACME/cert-manager tự động; certificate ngắn hạn tốt hơn dài hạn |

Cạm bẫy phổ biến nhất trong ứng dụng: **tin certificate mà không xác minh** (`trustServerCertificate=true`, `verify=false`, `InsecureSkipVerify`). Nó cho cảm giác an toàn vì "đã mã hóa" nhưng không chặn được kẻ đứng giữa. Xem [sqlserver/jdbc_java.md](../../sqlserver/integration/jdbc_java.md) mục 2.2 cho một ví dụ cụ thể, và [security/pki_tls.md](../../security/crypto/pki_tls.md) cho chi tiết PKI.

---

## 5. Server push – bốn cách và cách chọn

| Kỹ thuật | Cơ chế | Chiều | Chi phí kết nối | Phù hợp |
|---|---|---|---|---|
| **Short polling** | Client hỏi mỗi N giây | Client kéo | Nhiều request rỗng | Dữ liệu ít đổi, đơn giản nhất |
| **Long polling** | Client hỏi, server **giữ** đến khi có dữ liệu hoặc timeout | Client kéo, kéo dài | Một kết nối treo mỗi client | Tương thích rộng nhất, near-real-time |
| **SSE** | Một kết nối HTTP, server stream event | **Server→Client** | Một kết nối mỗi client | Feed, notification, tiến độ job, log |
| **WebSocket** | Nâng cấp HTTP → kết nối song công | **Hai chiều** | Một kết nối mỗi client, stateful | Chat, game, collaborative, trading |

```text
Short poll:  [req][resp] ...chờ... [req][resp]           nhiều request không có dữ liệu
Long poll:   [req.........giữ.........resp][req...       server giữ tới khi có dữ liệu
SSE:         [req] → stream: data:...\n\n data:...\n\n   một chiều, qua HTTP thường
WebSocket:   [Upgrade] ⇄ frame hai chiều + ping/pong     kết nối riêng, có heartbeat
```

### 5.1 SSE bị đánh giá thấp

Với phần lớn nhu cầu "server đẩy dữ liệu xuống client", SSE là lựa chọn đúng mà ít được chọn:

| Ưu điểm SSE | Chi tiết |
|---|---|
| Chạy trên HTTP thường | Qua proxy, CDN, LB L7 không cần cấu hình đặc biệt |
| Tự động reconnect | Trình duyệt tự thử lại, kèm `Last-Event-ID` để tiếp tục từ chỗ dừng |
| Đơn giản ở cả hai đầu | Không cần thư viện, không cần protocol riêng |
| Text-based, dễ debug | Xem được bằng `curl` |

Hạn chế: một chiều, và với HTTP/1.1 có giới hạn số kết nối mỗi origin của browser (HTTP/2 giải quyết).

Câu hỏi chọn giữa SSE và WebSocket rất đơn giản: **client có cần gửi dữ liệu liên tục lên server không?** Nếu không (notification, live dashboard, tiến độ) → SSE. Nếu có (chat, game, collaborative editing) → WebSocket.

### 5.2 Cái giá của WebSocket ở quy mô

```text
WebSocket là STATEFUL → mọi vấn đề của state quay lại:
  • Kết nối gắn với một node cụ thể → cần routing/sticky
  • Node restart = mọi client của nó mất kết nối → cần reconnect với backoff + jitter
  • Muốn gửi tin cho user X: phải biết X đang ở node nào → registry (Redis) + pub/sub backplane
  • 1M kết nối đồng thời = bài toán file descriptor, memory per connection, ulimit
  • Rolling deploy làm ngắt hàng loạt → cần drain có kiểm soát
```

Vì vậy quyết định dùng WebSocket là quyết định kiến trúc, không chỉ chọn API. Chi tiết cách xử lý: [realtime_scale_designs.md](../case_studies/realtime_scale_designs.md) mục 2 và [websocket package](../../websocket/roadmap.md).

---

## 6. DNS

```text
Resolution: cache browser → cache OS → resolver (ISP/công ty)
            → root → TLD (.com) → authoritative NS → IP
            (mỗi tầng có TTL riêng)
```

| Record | Dùng để |
|---|---|
| A / AAAA | Tên → IPv4 / IPv6 |
| CNAME | Alias tới tên khác (không dùng được ở zone apex) |
| ALIAS/ANAME | Như CNAME nhưng dùng được ở apex (tùy nhà cung cấp) |
| SRV | Tên → host + port (service discovery) |
| TXT | Xác thực domain, SPF/DKIM |
| NS / SOA | Uỷ quyền zone |

### 6.1 DNS là công cụ phân phối tốt, công cụ failover kém

| Kiểu routing | Cơ chế |
|---|---|
| Round robin | Trả nhiều A record, client chọn |
| GeoDNS | Trả IP theo vị trí địa lý của resolver |
| Latency-based | Trả IP theo độ trễ đo được |
| Weighted | Chia tỉ lệ (dùng cho migration dần) |
| Failover | Health check → bỏ IP không khỏe khỏi câu trả lời |

Vấn đề: **TTL là gợi ý, không phải cam kết**. Resolver có thể giữ lâu hơn; và nghiêm trọng hơn, **thư viện client có cache riêng**:

```text
JVM: networkaddress.cache.ttl — trong một số cấu hình mặc định là cache VĨNH VIỄN
     → ứng dụng Java không bao giờ thấy IP mới sau failover cho tới khi restart
     → phải đặt tường minh: -Dnetworkaddress.cache.ttl=30
```

Đây là lỗi vận hành thực tế rất hay gặp: DNS đã trỏ đúng, load balancer đã khỏe, nhưng một service Java vẫn gọi vào IP cũ. Kết luận: nếu cần RTO tính bằng giây, dùng anycast hoặc health-check-driven routing ở tầng thấp hơn, không dựa vào DNS.

---

## 7. CDN

```text
User → CDN edge gần nhất ──hit──► trả ngay (5–50ms)
                          ──miss─► origin (có thể qua mid-tier cache) → cache → trả
```

| | Pull CDN | Push CDN |
|---|---|---|
| Cơ chế | Edge tự fetch khi miss | Chủ động đẩy nội dung lên edge |
| Phù hợp | Đa số trường hợp; nội dung nhiều, truy cập không đều | File lớn, ít đổi, biết trước sẽ được truy cập |
| Chi phí | Miss đầu tiên chậm | Trả tiền storage ở mọi edge |

Ba giá trị của CDN, xếp theo mức bị đánh giá thấp:

1. **Giảm độ trễ** (được biết nhiều nhất).
2. **Giảm tải origin** — với hit ratio 95%, origin chỉ thấy 5% lưu lượng.
3. **Lá chắn khả dụng** — `stale-if-error` cho phép CDN tiếp tục phục vụ khi origin chết. Đây là biện pháp resilience rẻ nhất có thể triển khai; xem [caching.md](caching.md) mục 7.1.

Về invalidation: chiến lược tốt nhất là **không cần invalidate** — đặt hash nội dung vào tên file và cache vĩnh viễn. Với API response, dùng cache tag/surrogate key để purge theo nhóm.

CDN cũng cache được **API response** và chạy được logic ở edge (edge function). Điều này hữu ích cho nội dung công khai ít đổi — nhưng phải rất cẩn thận với `Cache-Control: private` cho dữ liệu theo user; lộ response của user A cho user B là một trong những sự cố bảo mật kinh điển của CDN.

---

## 8. Proxy và gateway

| | Forward proxy | Reverse proxy | API gateway |
|---|---|---|---|
| Đại diện cho | **Client** | **Server** | Server + cross-cutting concern |
| Client có biết? | Có (được cấu hình) | Không | Không |
| Chức năng chính | Lọc ra ngoài, cache outbound, ẩn client | LB, TLS termination, cache, nén | Routing + auth + rate limit + tổng hợp + versioning |
| Ví dụ | Squid, proxy doanh nghiệp | Nginx, HAProxy, Envoy | Kong, Spring Cloud Gateway, AWS API Gateway |

Ranh giới giữa reverse proxy và API gateway là mờ và mang tính chức năng: gateway là reverse proxy có thêm hiểu biết về API (xác thực token, giới hạn theo tenant, tổng hợp nhiều lời gọi, quản version). Chi tiết: `advanced/api_design.md` và `advanced/microservices.md`.

---

## 9. Chọn kiểu giao tiếp

| | REST (HTTP/JSON) | gRPC (HTTP/2 + Protobuf) | GraphQL | WebSocket | Message queue |
|---|---|---|---|---|---|
| Mô hình | Request/response | RPC + streaming | Query linh hoạt | Song công | Bất đồng bộ, tách rời |
| Payload | JSON (text) | Protobuf (binary, nhỏ) | JSON | Tùy | Tùy |
| Streaming | Hạn chế (SSE) | 4 kiểu (unary, server, client, bidi) | Subscription | Native | N/A |
| Hợp đồng | OpenAPI (tùy chọn) | `.proto` (bắt buộc) | Schema (bắt buộc) | Tự định nghĩa | Schema registry |
| Debug bằng mắt | **Dễ** | Khó (cần tool) | Vừa | Khó | Vừa |
| Qua browser | Native | Cần gRPC-Web | Native | Native | Không trực tiếp |
| Phù hợp nhất | API công khai, CRUD | **Service-to-service** nội bộ, độ trễ thấp | Client cần shape dữ liệu linh hoạt, mobile | Real-time hai chiều | Tách rời, chịu tải đột biến, fan-out |

Cách chọn thực dụng:

```text
API cho bên ngoài / đối tác        → REST + OpenAPI (dễ dùng, dễ tài liệu)
Service-to-service nội bộ          → gRPC (nhỏ, nhanh, có hợp đồng, streaming)
Mobile/web cần nhiều nguồn dữ liệu → GraphQL (hoặc BFF với REST)
Real-time hai chiều                → WebSocket
Việc không cần trả lời ngay        → message queue (KHÔNG phải RPC đồng bộ)
```

Hàng cuối là lời khuyên có giá trị nhất: rất nhiều lời gọi đồng bộ giữa các service **không cần** đồng bộ. Gửi email, cập nhật analytics, đánh index search — tất cả nên là event. Mỗi lời gọi đồng bộ bỏ đi là một điểm phụ thuộc bỏ đi khỏi phép nhân availability ([availability_reliability.md](availability_reliability.md) mục 2.1).

---

## 10. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| TCP | Tin cậy, giữ thứ tự | Handshake, HOL blocking | Mặc định |
| UDP/QUIC | Không HOL, 0-RTT, đổi mạng được | Tự lo reliability; firewall có thể chặn | Client mobile, edge |
| HTTP/2 | Multiplexing, nén header | Vẫn TCP HOL | Edge cho browser; gRPC nội bộ |
| HTTP/3 | Giải HOL, connection migration | CPU cao hơn, cần fallback | Edge, mạng kém |
| Long polling | Tương thích rộng nhất | Nhiều kết nối treo | Khi không thể dùng SSE/WS |
| SSE | Đơn giản, qua proxy dễ, tự reconnect | Một chiều | **Mặc định cho server push** |
| WebSocket | Hai chiều, độ trễ thấp | Stateful: routing, backplane, deploy khó | Thật cần hai chiều |
| REST | Phổ biến, dễ debug, cache HTTP | Payload lớn, không streaming | API công khai |
| gRPC | Nhỏ, nhanh, có hợp đồng, streaming | Khó debug, cần gRPC-Web cho browser, lệch tải qua L4 LB | Nội bộ |
| GraphQL | Client kiểm soát dữ liệu | Query phức tạp khó giới hạn (N+1, độ sâu), cache HTTP khó | BFF, mobile |
| Message queue | Tách rời, chịu đột biến, fan-out | Eventual consistency, khó trace | Việc không cần trả lời ngay |
| CDN | Độ trễ, tải origin, khả dụng | Invalidation, rủi ro cache dữ liệu riêng tư | Nội dung công khai |
| DNS-based failover | Đơn giản | TTL không đáng tin, client cache | Phân phối, không phải failover nhanh |

---

## 11. Checklist

```text
Kết nối
□ Connection pool / keep-alive cho MỌI HTTP client (không mở kết nối mỗi request)
□ TCP_NODELAY cho RPC latency thấp
□ Timeout: connect và read đặt tường minh ở mọi lời gọi
□ maxLifetime của pool < timeout của firewall/LB

TLS
□ Xác minh certificate (không dùng skip-verify trên production)
□ TLS 1.2/1.3, đã tắt phiên bản cũ
□ Certificate tự động gia hạn (ACME/cert-manager)
□ mTLS cho service-to-service nếu có mesh

HTTP
□ HTTP/2 bật ở edge; cân nhắc HTTP/3 nếu CDN hỗ trợ
□ Nén (gzip/brotli) cho response text
□ Cache-Control đúng cho từng loại nội dung; private/no-store cho dữ liệu theo user
□ stale-if-error đã bật cho nội dung đọc

Real-time
□ Đã cân nhắc SSE trước khi chọn WebSocket
□ Nếu WebSocket: có registry user→node, pub/sub backplane, heartbeat, reconnect có jitter
□ Kế hoạch drain kết nối khi deploy

DNS
□ networkaddress.cache.ttl đặt tường minh trong JVM
□ Không dựa vào DNS cho failover cần RTO tính bằng giây
□ TTL phù hợp với tần suất thay đổi
```

---

## 12. Ghi chú – chủ đề tiếp theo

- [load_balancing.md](load_balancing.md): L4/L7, gRPC qua LB, TLS termination, anycast.
- [caching.md](caching.md): CDN, Cache-Control, stale-while-revalidate.
- `advanced/api_design.md`: REST/GraphQL/gRPC chi tiết, versioning, gateway.
- [realtime_scale_designs.md](../case_studies/realtime_scale_designs.md): WebSocket ở quy mô lớn.
- [websocket package](../../websocket/roadmap.md), [security/pki_tls.md](../../security/crypto/pki_tls.md).

Từ khóa mở rộng: bandwidth-delay product, BBR vs CUBIC congestion control, TCP Fast Open, 0-RTT replay, ALPN, HPACK/QPACK, connection coalescing, anycast + BGP, ECMP, MTU/MSS và path MTU discovery, SO_REUSEPORT, C10K/C1M problem, `Last-Event-ID` của SSE, gRPC keepalive và `MAX_CONNECTION_AGE`.

---

*Cập nhật lần cuối: 2026-07-30*
