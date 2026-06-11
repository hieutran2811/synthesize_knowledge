# Networking & Communication Protocols – Nền tảng giao tiếp

> Bổ trợ cho [load_balancing.md](load_balancing.md) (L4/L7), [caching.md](caching.md) (CDN), [../advanced/api_design.md](../advanced/api_design.md) (REST/gRPC). File này đi sâu protocol: TCP/UDP, HTTP/1-2-3, real-time push, DNS, CDN, proxy.

## What – Vì sao protocol quan trọng?

Mọi hệ phân tán giao tiếp qua mạng → chọn protocol ảnh hưởng **latency, throughput, real-time, độ phức tạp**. Hiểu protocol giúp giải thích bottleneck (HOL blocking, RTT, connection overhead) và chọn đúng (REST vs gRPC vs WebSocket).

---

## How – TCP vs UDP

| | TCP | UDP |
|--|-----|-----|
| Kết nối | Có (3-way handshake) | Không (connectionless) |
| Tin cậy | Đảm bảo (ack, retransmit, ordering) | Không (best-effort) |
| Thứ tự | Giữ thứ tự | Không |
| Tốc độ | Chậm hơn (overhead) | Nhanh (ít overhead) |
| Dùng | HTTP, DB, hầu hết | DNS, video/voice, gaming, **QUIC/HTTP3** |

```
TCP 3-way handshake:  SYN → SYN-ACK → ACK  (1 RTT trước khi gửi data)
+ TLS handshake:      thêm 1–2 RTT (TLS 1.3 = 1 RTT, 0-RTT resume)
→ kết nối mới "đắt" → connection pooling / keep-alive quan trọng
```
- **TCP Head-of-Line (HOL) blocking**: 1 packet mất → mọi packet sau phải chờ retransmit (ảnh hưởng HTTP/2). UDP không có → QUIC tận dụng.
- **Congestion control** (slow start, AIMD): TCP tự điều tiết tốc độ theo mạng.

---

## How – HTTP Evolution

| | HTTP/1.1 | HTTP/2 | HTTP/3 |
|--|----------|--------|--------|
| Transport | TCP | TCP | **QUIC (UDP)** |
| Multiplexing | Không (1 request/connection tại 1 thời điểm) | **Có** (nhiều stream/1 connection) | Có (không TCP HOL) |
| HOL blocking | Application-level (pipelining hỏng) | TCP-level (vẫn còn ở TCP) | **Không** (per-stream độc lập) |
| Header | Text, lặp lại | Binary + nén **HPACK** | Binary + QPACK |
| Handshake | TCP + TLS (2–3 RTT) | TCP + TLS | **0–1 RTT** (QUIC gộp) |
| Server push | Không | Có (đã deprecated) | Không |

```
HTTP/1.1: trình duyệt mở 6 connection song song (vì 1 request/conn) → tốn
HTTP/2:   1 connection, nhiều stream song song (multiplexing) → nhưng 1 packet TCP mất
          → block MỌI stream (TCP HOL)
HTTP/3:   QUIC trên UDP → mỗi stream độc lập, mất packet chỉ ảnh hưởng stream đó
          + 0-RTT resume, connection migration (đổi mạng wifi↔4G không mất kết nối)
```
> HTTPS/TLS: mã hóa + xác thực; TLS 1.3 nhanh hơn (1-RTT). Chi tiết PKI/TLS: [../../security/crypto/pki_tls.md](../../security/crypto/pki_tls.md).

---

## How – Real-time / Server Push

Khi server cần **đẩy** dữ liệu tới client (chat, notification, live feed):

| Kỹ thuật | Cơ chế | Chiều | Khi dùng |
|----------|--------|-------|----------|
| **Short polling** | Client hỏi định kỳ (mỗi N giây) | Client→Server lặp | Đơn giản, dữ liệu ít đổi; lãng phí request |
| **Long polling** | Client hỏi, server **giữ** đến khi có data hoặc timeout | Pull kéo dài | Tương thích rộng, near-real-time |
| **SSE (Server-Sent Events)** | 1 kết nối HTTP, server stream events (text/event-stream) | **Server→Client** (1 chiều) | Feed, notification, stock ticker; tự reconnect |
| **WebSocket** | Nâng cấp HTTP → kết nối **song công** (full-duplex) bền | **2 chiều** | Chat, game, collaborative, trading |

```
Short poll:  [req][resp]...wait...[req][resp]   (nhiều request rỗng)
Long poll:   [req........(hold).....resp][req...   (server giữ tới khi có data)
SSE:         [req] → stream: event\n event\n...   (1 chiều, qua HTTP)
WebSocket:   [handshake Upgrade] ⇄ frames 2 chiều  (TCP riêng, có heartbeat/ping-pong)
```
> SSE 1 chiều + chạy trên HTTP (qua proxy/CDN dễ) → đủ cho hầu hết "server đẩy". WebSocket 2 chiều nhưng tốn kết nối stateful (khó scale, cần sticky/pub-sub backplane). Liên hệ package `websocket/` của dự án.

---

## How – DNS

```
Resolution: browser cache → OS cache → resolver (ISP) → root → TLD (.com) → authoritative NS → IP
            (mỗi cấp có TTL caching)
```
- **Record types**: A (IPv4), AAAA (IPv6), CNAME (alias), MX (mail), TXT, NS, SRV.
- **GeoDNS / latency-based routing**: trả IP gần user nhất (Route53, Cloudflare) → giảm RTT, nền của global LB. Liên hệ Global LB ở [load_balancing.md](load_balancing.md).
- TTL thấp → đổi nhanh (failover) nhưng nhiều query; TTL cao → cache tốt nhưng đổi chậm.
- DNS là **first hop latency** → cân nhắc DNS prefetch, anycast DNS.

---

## How – CDN (Content Delivery Network)

```
User → CDN edge (gần nhất) ──cache hit──► trả ngay (giảm RTT, giảm tải origin)
                            ──cache miss──► fetch từ origin → cache → trả
```
- **Pull CDN**: edge tự fetch từ origin khi miss (lazy, phổ biến). **Push CDN**: chủ động đẩy content lên edge (kiểm soát, cho file lớn/ít đổi).
- Cache static (ảnh, JS, CSS, video) + có thể cache API response (TTL/edge compute).
- **Invalidation**: TTL, versioned URL (hash trong filename → immutable cache), purge API. Liên hệ caching/invalidation ở [caching.md](caching.md).
- Lợi ích: giảm latency (edge gần user), giảm tải origin/bandwidth, chống DDoS (hấp thụ ở edge).

---

## How – Proxies & API Gateway

| | Forward Proxy | Reverse Proxy | API Gateway |
|--|---------------|---------------|-------------|
| Đại diện cho | **Client** (ẩn client) | **Server** (ẩn backend) | Server + cross-cutting |
| Ví dụ | Corporate proxy, VPN | Nginx, HAProxy | Kong, Spring Cloud Gateway |
| Chức năng | Filter, cache outbound, anonymity | LB, TLS termination, cache, compression | Routing + auth + rate limit + aggregation |

- **Reverse proxy**: TLS termination, nén, cache, LB (L4/L7 — xem [load_balancing.md](load_balancing.md)), che backend.
- **API Gateway**: cửa ngõ microservices (auth, rate limit, routing, request aggregation). Liên hệ [../advanced/microservices.md](../advanced/microservices.md), [../advanced/api_design.md](../advanced/api_design.md), [../../java/spring/spring_cloud.md](../../java/spring/spring_cloud.md).

---

## Compare – RPC styles & khi nào dùng

| | REST (HTTP/JSON) | gRPC (HTTP/2 + Protobuf) | GraphQL | WebSocket |
|--|------------------|---------------------------|---------|-----------|
| Kiểu | Request/response | RPC, streaming | Query linh hoạt | Full-duplex |
| Payload | JSON (text) | Protobuf (binary, nhỏ) | JSON | Tùy |
| Streaming | Hạn chế (SSE) | **4 kiểu streaming** | Subscription | Native |
| Dùng | Public API, CRUD | **Service-to-service** nội bộ, low-latency | Client cần data linh hoạt, mobile | Real-time 2 chiều |
> Chi tiết REST/GraphQL/gRPC: [../advanced/api_design.md](../advanced/api_design.md); gRPC streaming/Protobuf: [../../java/core/grpc_protobuf.md](../../java/core/grpc_protobuf.md).

---

## Trade-offs

- **TCP** tin cậy nhưng HOL blocking + handshake cost; **UDP** nhanh nhưng tự lo reliability (QUIC giải quyết).
- **HTTP/2** multiplexing tốt nhưng vẫn TCP HOL; **HTTP/3 (QUIC)** giải HOL + 0-RTT nhưng UDP đôi khi bị firewall chặn, CPU encrypt cao hơn.
- **WebSocket** real-time mạnh nhưng stateful → khó scale (sticky session/pub-sub backplane), tốn tài nguyên kết nối; **SSE** đơn giản hơn nếu chỉ cần 1 chiều.
- **CDN** giảm latency/tải nhưng thêm tầng cache → invalidation phức tạp, cost.
- **gRPC** hiệu năng cao nhưng binary khó debug, khó qua browser (cần gRPC-Web).

---

## Ghi chú
**Sub-topic liên quan:**
- [load_balancing.md](load_balancing.md) – L4/L7, Global LB, consistent hashing
- [caching.md](caching.md) – CDN, cache invalidation
- [../advanced/api_design.md](../advanced/api_design.md) – REST/GraphQL/gRPC, gateway
- [../../security/crypto/pki_tls.md](../../security/crypto/pki_tls.md) – TLS handshake, certificate
- **Keywords:** 3-way handshake, TCP HOL blocking, HPACK/QPACK, QUIC 0-RTT, connection migration, keep-alive, connection pooling, SSE vs WebSocket, long polling, GeoDNS/anycast, pull vs push CDN, TLS termination, sticky session, gRPC-Web.

*Cập nhật lần cuối: 2026-06-11*
