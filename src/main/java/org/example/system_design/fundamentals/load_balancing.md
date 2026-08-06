# Load Balancing – Cân bằng tải

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Scalability](scalability.md). Đọc tiếp: [Caching](caching.md), [Networking & Protocols](networking_protocols.md).

---

## 1. Load balancer làm nhiều việc hơn "chia tải"

Tên gọi gây hiểu sai. Phân phối tải chỉ là một trong các chức năng; trong thực tế LB còn là:

| Chức năng | Vì sao quan trọng |
|---|---|
| Phân phối tải | Không node nào quá tải khi node khác rảnh |
| **Loại node lỗi khỏi pool** | Đây thường là giá trị lớn nhất — biến node chết thành chuyện vô hình với client |
| Điểm vào duy nhất | Client chỉ biết một địa chỉ, backend thay đổi tự do |
| TLS termination | Tập trung certificate, giảm CPU backend |
| Định tuyến theo nội dung (L7) | `/api/orders` → order service |
| Triển khai an toàn | Canary, blue-green, connection draining |
| Phòng thủ lớp đầu | Rate limit, chặn IP, hấp thụ một phần DDoS |

Nói cách khác: LB là nơi bạn thực hiện **mọi thay đổi về topology mà không client nào phải biết**. Đó là lý do nó nằm trong gần như mọi kiến trúc.

---

## 2. L4 vs L7

```text
L4 (transport): quyết định dựa trên IP + port. Không đọc nội dung.
   Client 203.0.113.10:52300 → LB:443 → chọn backend 10.0.0.5:8443 → chuyển tiếp gói

L7 (application): kết thúc kết nối, đọc HTTP (path, header, cookie), rồi mở kết nối mới tới backend
   GET /api/orders  Host: shop.example.com  → phân tích → order-service
```

| | L4 | L7 |
|---|---|---|
| Thấy được gì | IP, port | Path, header, cookie, method, body |
| Overhead | Rất thấp | Cao hơn (phải parse, đôi khi buffer) |
| Định tuyến theo nội dung | Không | Có |
| TLS | Passthrough hoặc terminate | Thường terminate |
| Giữ IP client | Dễ (hoặc dùng proxy protocol) | Cần `X-Forwarded-For` |
| Phù hợp | TCP thuần, database, gRPC ở mức kết nối, cần thông lượng tối đa | HTTP API, microservices, canary, auth offload |
| Công cụ | AWS NLB, HAProxy (tcp mode), nginx stream, Cilium/eBPF | AWS ALB, nginx, Envoy, Traefik, HAProxy (http mode) |

### 2.1 Cái bẫy L4 + gRPC/HTTP2

Đây là vấn đề thực tế rất hay gặp và khó chẩn đoán:

```text
gRPC/HTTP2 dùng MỘT kết nối TCP lâu dài, nhiều stream bên trong.

L4 LB cân bằng theo KẾT NỐI:
  client mở 1 kết nối → mọi request của client đó đi vào MỘT backend
  → 10 client, 10 backend, nhưng tải lệch hoàn toàn ngẫu nhiên
  → thêm backend không giúp gì cho client đang kết nối

Cách chữa:
  a. L7 LB hiểu HTTP/2 → cân bằng theo REQUEST (Envoy, ALB, nginx với grpc_pass)
  b. Client-side LB: client biết danh sách backend, tự phân phối (gRPC name resolver)
  c. Buộc kết nối sống có hạn: MAX_CONNECTION_AGE ở server → client kết nối lại định kỳ
```

Cách (c) đơn giản đến mức đáng làm ngay cả khi đã có (a) hoặc (b): nó đảm bảo backend mới được nhận tải mà không cần chờ client tự ngắt.

---

## 3. Thuật toán phân phối

| Thuật toán | Cơ chế | Mạnh | Yếu |
|---|---|---|---|
| **Round robin** | Lần lượt A→B→C | Đơn giản, công bằng về số request | Bỏ qua công suất và tải thực; rất kém với kết nối lâu dài |
| **Weighted RR** | Theo trọng số | Xử lý fleet không đồng nhất | Trọng số tĩnh, phải cập nhật tay |
| **Least connections** | Tới node ít kết nối đang mở nhất | Tốt cho request thời lượng khác nhau, kết nối lâu | Phải theo dõi trạng thái; "ít kết nối" ≠ "ít tải" |
| **Least response time** | Kết hợp latency và số kết nối | Phản ánh tải thật tốt nhất | Cần đo liên tục; dễ dao động |
| **Peak EWMA** | Latency trung bình trượt có trọng số + số request đang chờ | Phản ứng nhanh với node chậm | Phức tạp hơn; dùng trong Linkerd/Finagle |
| **Random + two choices (P2C)** | Lấy ngẫu nhiên 2 node, chọn node tải thấp hơn | Gần bằng least-connections nhưng **không cần trạng thái toàn cục** | Không tối ưu tuyệt đối |
| **IP hash** | `hash(client_ip)` → node | Session affinity đơn giản | Phân phối lệch (NAT/proxy doanh nghiệp), mất session khi node chết |
| **Consistent hashing** | Hash key lên ring | Thêm/bớt node chỉ ảnh hưởng ~1/N | Phức tạp hơn; cần virtual node |

### 3.1 "Power of two choices" – lựa chọn mặc định tốt

P2C là kết quả đáng chú ý: chọn ngẫu nhiên 2 node rồi lấy node tải nhẹ hơn cho kết quả **gần bằng** least-connections toàn cục, mà không cần bất kỳ trạng thái chia sẻ nào.

```text
Random thuần:      độ lệch tải ~ O(log N)
P2C:               độ lệch tải ~ O(log log N)   ← cải thiện rất lớn với chi phí gần bằng 0
Least-connections: tối ưu nhưng cần trạng thái toàn cục
```

Vì vậy P2C là mặc định trong nhiều service mesh và client-side LB hiện đại. Với LB phân tán (nhiều LB instance), nó còn tránh được vấn đề "mọi LB cùng thấy một node là nhẹ nhất rồi cùng dồn vào đó".

### 3.2 Consistent hashing

```text
Ring 0 → 2³²
Node A băm về 100, B về 200, C về 300
key "user:123" băm về 150 → đi theo chiều kim đồng hồ → node B

Thêm node D ở 250:  chỉ các key trong (200, 250] chuyển từ C sang D
                    → ~1/N key bị di chuyển, không phải toàn bộ như modulo
```

Vấn đề của bản đơn giản và cách chữa:

| Vấn đề | Cách chữa |
|---|---|
| Phân bố lệch (node ít may mắn nhận ít key) | **Virtual node**: mỗi node vật lý có 100–200 điểm trên ring |
| Hot key vẫn dồn vào một node | Replicate hot key sang node kế tiếp; hoặc thêm hậu tố ngẫu nhiên |
| Một node quá tải kéo theo node kế tiếp | **Bounded-load consistent hashing**: nếu node đích đã vượt ngưỡng, chuyển sang node tiếp theo |

Consistent hashing dùng ở: sharding cache (Redis Cluster dùng hash slot — biến thể cố định 16384 slot), định tuyến CDN, sharding database, session affinity bền hơn IP hash.

### 3.3 Chọn thuật toán theo tình huống

```text
HTTP request ngắn, backend đồng nhất        → round robin hoặc P2C
Request thời lượng rất khác nhau            → least connections / peak EWMA
Kết nối lâu dài (WebSocket, gRPC stream)    → least connections (bắt buộc)
Cần cache locality theo key                 → consistent hashing
Có state trong process theo user            → consistent hashing (không dùng IP hash)
Fleet không đồng nhất                       → weighted + least connections
```

Lưu ý về round robin với kết nối lâu dài: nó gần như luôn sai. Round robin cân bằng số **kết nối mới**; nếu kết nối sống hàng giờ, một node vừa restart sẽ có 0 kết nối trong khi các node khác đầy — và round robin không sửa được điều đó.

---

## 4. Health check

### 4.1 Passive vs active

| | Passive (outlier detection) | Active (probe) |
|---|---|---|
| Cơ chế | Quan sát phản hồi của request thật | LB tự gửi request thăm dò |
| Phát hiện | Nhanh, dựa trên dữ liệu thật | Theo chu kỳ probe |
| Chi phí | Bằng 0 | Có (mỗi node × mỗi LB × mỗi chu kỳ) |
| Nhược | Một số request thật đã lỗi | Node có thể "khỏe" với probe nhưng lỗi với request thật |

Nên có **cả hai**: active để đưa node mới vào pool và phát hiện node chết, passive để bắt suy giảm mà probe không thấy.

### 4.2 Ba loại endpoint, ba mục đích khác nhau

Đây là điểm bị làm sai nhiều nhất, và làm sai gây ra sự cố dây chuyền:

```text
/health/live      (liveness)  → "process này còn sống?"      → sai thì RESTART
/health/ready     (readiness) → "sẵn sàng nhận traffic?"     → sai thì RÚT KHỎI POOL
/health/startup   (startup)   → "đã khởi động xong chưa?"    → chưa thì chờ, chưa restart
```

```java
// Readiness: kiểm tra dependency BẮT BUỘC cho việc phục vụ
@GetMapping("/health/ready")
public ResponseEntity<Map<String,String>> ready() {
    Map<String,String> checks = new LinkedHashMap<>();
    checks.put("db",    check(() -> jdbc.queryForObject("SELECT 1", Integer.class)));
    checks.put("cache", check(redis::ping));           // nếu cache là bắt buộc
    boolean up = checks.values().stream().allMatch("UP"::equals);
    return up ? ResponseEntity.ok(checks) : ResponseEntity.status(503).body(checks);
}

// Liveness: KHÔNG kiểm tra dependency ngoài — chỉ kiểm tra process
@GetMapping("/health/live")
public String live() { return "OK"; }
```

Nguyên tắc sống còn: **liveness không được phụ thuộc vào dependency ngoài**. Nếu liveness kiểm tra database và database chậm 30 giây, orchestrator sẽ restart **toàn bộ** pod — biến một sự cố database thành sự cố toàn hệ thống, đúng lúc tệ nhất.

Ngược lại, readiness **nên** kiểm tra dependency bắt buộc — nhưng phải cẩn thận: nếu mọi pod đồng thời báo not-ready vì database chậm, pool trở thành rỗng và không còn ai phục vụ ngay cả những request không cần database. Cách xử lý: readiness chỉ fail khi node đó **thực sự** không phục vụ được, kèm cân nhắc "fail static" (giữ trạng thái ready cuối cùng khi không xác định được).

### 4.3 Tham số cần đặt tường minh

```nginx
upstream api {
    least_conn;
    keepalive 64;                    # pool kết nối tới backend — thiếu cái này là lỗi phổ biến

    server app1:8080 max_fails=3 fail_timeout=10s;
    server app2:8080 max_fails=3 fail_timeout=10s;
    server app3:8080 backup;         # chỉ dùng khi các node trên đều chết
}

server {
    listen 443 ssl http2;
    ssl_certificate     /etc/ssl/cert.pem;
    ssl_certificate_key /etc/ssl/key.pem;

    location /api/ {
        proxy_pass http://api;
        proxy_http_version 1.1;
        proxy_set_header Connection "";           # bắt buộc để keepalive hoạt động
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 3s;
        proxy_send_timeout    30s;
        proxy_read_timeout    30s;

        proxy_next_upstream error timeout http_502 http_503;
        proxy_next_upstream_tries 2;              # giới hạn retry để tránh amplification
    }
}
```

Hai dòng đáng chú ý: `keepalive` + `proxy_set_header Connection ""` — không có chúng, nginx mở kết nối TCP mới cho **mỗi** request tới backend, thêm một handshake vào mọi request và làm cạn port ở tải cao.

---

## 5. Session affinity (sticky session)

| Cách | Cơ chế | Nhược |
|---|---|---|
| IP hash | `hash(client_ip)` | Lệch vì NAT; đổi IP (mobile) là mất session |
| Cookie do LB đặt | LB gắn cookie chứa id backend | Cần L7; client phải nhận cookie |
| Consistent hashing theo user id | Hash một header/token | Cần L7 đọc được id; bền hơn IP hash |

Nhưng câu hỏi đúng hơn là: **có thực sự cần sticky không?** Sticky session tạo ra ba vấn đề:

1. Node chết → mất state của mọi user gắn với nó.
2. Tải lệch — không thể cân bằng lại mà không phá session.
3. Rolling deployment làm mất session hàng loạt.

Với HTTP API, câu trả lời gần như luôn là **không cần** — chuyển state ra store dùng chung ([scalability.md](scalability.md) mục 3). Sticky chỉ thực sự cần cho kết nối vốn dĩ stateful (WebSocket) hoặc cache locality quan trọng, và khi đó nên dùng consistent hashing thay vì IP hash.

---

## 6. TLS: terminate, passthrough hay re-encrypt

```text
Terminate:   Client ══TLS══► LB ──HTTP──► Backend
             + Backend nhẹ CPU, LB làm được routing L7, quản certificate tập trung
             − Traffic nội bộ là plaintext

Passthrough: Client ══════TLS══════► Backend  (LB chỉ chuyển gói ở L4)
             + E2E encryption, backend thấy certificate/mTLS của client
             − LB không đọc được HTTP → mất routing L7, mất cache, mất WAF

Re-encrypt:  Client ══TLS══► LB ══TLS══► Backend
             + Vừa có L7 routing vừa mã hóa nội bộ
             − Hai lần encrypt/decrypt; phải quản hai lớp certificate
```

Lựa chọn thực tế: **terminate ở edge + mTLS bên trong qua service mesh** là mô hình phổ biến nhất hiện nay — LB làm routing và WAF, còn traffic service-to-service được mã hóa và xác thực bởi mesh. Xem `advanced/microservices.md` phần service mesh.

Nếu phải chọn giữa terminate và passthrough mà không có mesh: terminate cho HTTP API công khai, passthrough khi có yêu cầu tuân thủ E2E hoặc cần mTLS tới tận backend.

---

## 7. Triển khai an toàn qua LB

### 7.1 Connection draining

```text
Rút node khỏi pool:
1. Đánh dấu node "draining" → LB ngừng gửi request MỚI
2. Chờ request đang xử lý hoàn tất (deregistration delay, ví dụ 30–300s)
3. Đóng kết nối còn lại
4. Tắt process
```

Phía ứng dụng phải phối hợp, nếu không draining vô nghĩa:

```text
Nhận SIGTERM
  → readiness trả 503 NGAY (để LB rút khỏi pool)
  → nhưng VẪN xử lý request đang có
  → chờ tối thiểu vài giây (LB cần thời gian nhận biết) rồi mới dừng nhận
  → xử lý xong → thoát
```

Bước "chờ vài giây" hay bị bỏ: nếu process thoát ngay khi nhận SIGTERM, sẽ có một khoảng LB vẫn gửi request tới một địa chỉ đã chết → lỗi 502 trong mỗi lần deploy. Với Kubernetes, `terminationGracePeriodSeconds` phải lớn hơn `preStop delay + thời gian xử lý request dài nhất`.

### 7.2 Canary và blue-green

```text
Canary (theo trọng số):
  99% → target group v1
   1% → target group v2   → quan sát error rate, p99 → tăng dần 1% → 5% → 25% → 100%

Blue-green:
  100% → blue (v1);  chuẩn bị green (v2) đầy đủ;  chuyển 100% một lần;  giữ blue để lùi

Định tuyến theo header/cookie (L7):
  header "x-canary: true" → v2    → nội bộ test trên production thật trước khi mở cho user
```

Canary chỉ có ý nghĩa khi có **metric để so sánh giữa hai nhóm** — error rate, p99, và một chỉ số nghiệp vụ. Canary không có quan sát chỉ là "deploy chậm hơn".

---

## 8. Global load balancing

| Cơ chế | Cách hoạt động | Thời gian failover | Ghi chú |
|---|---|---|---|
| **DNS round robin** | Trả nhiều A record | Chậm (TTL + cache của client) | Client có thể cache lâu hơn TTL |
| **GeoDNS / latency-based** | Trả IP theo vị trí/độ trễ | Chậm như trên | Đủ tốt cho phân phối, kém cho failover |
| **Anycast** | Cùng một IP announce từ nhiều PoP, BGP chọn đường | Nhanh (thay đổi routing) | Dùng cho CDN, DNS resolver |
| **Global accelerator** | Anycast IP + backbone riêng của nhà cung cấp | Nhanh, không phụ thuộc DNS TTL | Tốn phí, phụ thuộc một nhà cung cấp |

Điểm quan trọng về DNS: **TTL là gợi ý, không phải cam kết**. Resolver và thư viện client (đặc biệt JVM với cache DNS mặc định) có thể giữ bản ghi lâu hơn nhiều. Vì vậy DNS là công cụ **phân phối** tốt nhưng công cụ **failover** kém — nếu cần RTO tính bằng giây, phải dùng anycast hoặc health-check-driven routing ở tầng thấp hơn.

Với JVM, cần biết `networkaddress.cache.ttl` — mặc định trong một số cấu hình là cache vĩnh viễn, nghĩa là ứng dụng Java sẽ không bao giờ thấy IP mới sau failover DNS cho tới khi restart.

---

## 9. Bản thân LB cũng là SPOF

Câu hỏi ít được đặt: nếu LB chết thì sao?

| Mô hình | Cách làm |
|---|---|
| LB dự phòng + VIP | Hai LB, một VIP nổi qua VRRP/keepalived |
| LB do nhà cung cấp quản lý | ALB/NLB đã dự phòng nhiều AZ sẵn |
| Anycast nhiều PoP | Mất một PoP thì BGP chuyển đường |
| Client-side LB | Không có LB trung tâm — client biết danh sách backend (gRPC, service mesh) |

Client-side LB đáng chú ý vì nó **loại bỏ một hop và một SPOF**, đồng thời giải quyết luôn vấn đề gRPC ở mục 2.1. Đánh đổi: logic LB nằm trong mọi client (khó cập nhật), và client cần service discovery. Service mesh với sidecar là cách dung hòa: LB nằm trong sidecar (như client-side) nhưng được quản lý tập trung bởi control plane.

---

## 10. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| L4 | Thông lượng cao, protocol-agnostic | Không routing theo nội dung; lệch tải với HTTP/2 | TCP thuần, cần hiệu năng tối đa |
| L7 | Routing, canary, WAF, cân bằng theo request | Overhead, phải parse | HTTP API, microservices |
| Round robin | Đơn giản | Bỏ qua tải thực; sai với kết nối lâu | Backend đồng nhất, request ngắn |
| Least connections | Phản ánh tải tốt | Cần trạng thái | Request thời lượng khác nhau |
| P2C | Gần tối ưu, không cần trạng thái toàn cục | Không tối ưu tuyệt đối | Mặc định tốt cho LB phân tán |
| Consistent hashing | Cache locality, ít dịch chuyển key | Phức tạp, cần virtual node | Sharding cache/DB, affinity theo key |
| Sticky session | Giữ state trong process | Node chết mất session, tải lệch, khó deploy | Chỉ khi thật cần (WebSocket) |
| TLS terminate | Backend nhẹ, routing L7 | Nội bộ plaintext | Có mesh mTLS hoặc mạng nội bộ tin cậy |
| TLS passthrough | E2E, mTLS tới backend | Mất L7 | Yêu cầu tuân thủ |
| DNS-based GLB | Đơn giản, không SPOF trung tâm | Failover chậm, client cache | Phân phối theo vùng |
| Anycast | Failover nhanh | Cần BGP/nhà cung cấp | CDN, DNS, edge |
| Client-side LB | Bớt một hop và một SPOF | Logic ở client, cần discovery | gRPC nội bộ, service mesh |

---

## 11. Checklist

```text
Chọn đúng
□ HTTP/2, gRPC: KHÔNG dùng L4 round robin (xem mục 2.1)
□ Kết nối lâu dài: least connections, không round robin
□ Cần affinity: consistent hashing, không IP hash
□ Đã xét lại xem có thật cần sticky session không

Health check
□ Tách liveness / readiness / startup
□ Liveness KHÔNG phụ thuộc dependency ngoài
□ Readiness kiểm tra dependency bắt buộc, nhưng không làm rỗng cả pool
□ Có cả active probe và passive outlier detection

Kết nối
□ keepalive tới backend đã bật (và header Connection đã xử lý)
□ connect/read timeout đặt tường minh
□ Giới hạn số lần thử node kế tiếp (tránh retry amplification)
□ X-Forwarded-For / proxy protocol để backend thấy IP thật

Triển khai
□ Connection draining bật, và ứng dụng xử lý SIGTERM đúng (readiness 503 trước, chờ, rồi thoát)
□ terminationGracePeriodSeconds > preStop delay + request dài nhất
□ Canary có metric so sánh (error rate, p99, chỉ số nghiệp vụ)

Độ tin cậy
□ LB không phải SPOF (dự phòng, nhiều AZ, hoặc anycast)
□ Biết TTL DNS thực tế mà client tôn trọng; JVM đã cấu hình networkaddress.cache.ttl
□ Đã diễn tập mất một node và mất một AZ
```

---

## 12. Ghi chú – chủ đề tiếp theo

- [caching.md](caching.md): CDN ở tầng trước LB, cache tại edge.
- [networking_protocols.md](networking_protocols.md): TCP/TLS handshake, HTTP/2 và HTTP/3, DNS.
- [availability_reliability.md](availability_reliability.md): health check trong bức tranh resilience.
- `advanced/microservices.md`: service mesh, sidecar, service discovery.
- `advanced/api_design.md`: API gateway so với LB thuần.

Từ khóa mở rộng: maglev hashing, bounded-load consistent hashing, eBPF/XDP load balancing (Cilium), Direct Server Return (DSR), proxy protocol v2, VRRP/keepalived, outlier ejection của Envoy, GSLB, `SO_REUSEPORT`, slow start khi node mới vào pool.

Một chi tiết dễ bỏ khi thêm node mới: node vừa khởi động có cache lạnh và JIT chưa nóng, nên nhận đủ tải ngay sẽ có p99 rất tệ. Cả nginx (`slow_start`) và Envoy (slow start mode) đều hỗ trợ tăng dần trọng số cho node mới — nên bật.

---

*Cập nhật lần cuối: 2026-07-30*
