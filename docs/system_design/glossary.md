---
title: "System Design Glossary"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# System Design Glossary

> Bảng tra cứu nhanh thuật ngữ dùng trong learning path System Design. Ưu tiên cách hiểu thực hành.
>
> Quay lại [roadmap](roadmap.md).

| Thuật ngữ | Nghĩa ngắn gọn | Điểm cần nhớ |
|---|---|---|
| **Amdahl's Law** | Phần tuần tự giới hạn tăng tốc khi thêm node | S = 5% → speedup tối đa 20× dù thêm bao nhiêu máy |
| **Anycast** | Cùng một IP announce từ nhiều PoP, BGP chọn đường gần nhất | Failover nhanh hơn DNS vì không phụ thuộc TTL |
| **Availability** | `Uptime / (Uptime + Downtime)` | Nhân lên qua chuỗi phụ thuộc; dự phòng phá vỡ phép nhân |
| **Backpressure** | Báo ngược lên producer để nó chậm lại | Khác load shedding (từ chối); dùng khi kiểm soát được producer |
| **Bloom filter** | Cấu trúc xác suất kiểm tra "chắc chắn không có" | Có sai dương, **không** sai âm → an toàn làm cửa chặn |
| **Bulkhead** | Cách ly tài nguyên (thread/connection pool riêng theo dependency) | Biến "sập cả service" thành "một tính năng suy giảm" |
| **CAP theorem** | Khi partition, chọn Consistency hay Availability | Không phải "2 trong 3"; P không phải lựa chọn; áp dụng theo từng operation |
| **Cell-based architecture** | Nhiều bản sao stack độc lập, mỗi cell phục vụ một tập khách hàng | Giới hạn blast radius; đổi lấy chi phí × N |
| **Circuit breaker** | Fail fast khi dependency lỗi, cho nó thời gian hồi phục | Phải có `minimumNumberOfCalls` và ngưỡng gọi **chậm** |
| **Consistent hashing** | Hash key lên ring; thêm/bớt node chỉ dịch ~1/N key | Cần virtual node để phân bố đều; không giải quyết hot key |
| **CQRS** | Tách model đọc và model ghi | Cho scale độc lập; đổi lấy eventual consistency giữa hai bên |
| **CRDT** | Cấu trúc dữ liệu tự hội tụ khi merge | Đảm bảo hội tụ, **không** đảm bảo ràng buộc nghiệp vụ (số dư có thể âm) |
| **Deadline propagation** | Truyền thời gian còn lại xuống các hop sau | Không có nó, hop cuối làm việc vô ích cho request đã bị hủy |
| **Durability** | Xác suất không mất dữ liệu đã ghi | Khác availability và khác fault tolerance |
| **Erasure coding** | Chia dữ liệu thành k phần + m parity | Overhead ~50% thay vì 200% của replication; sửa lỗi đắt hơn |
| **Error budget** | `(1 - SLO) × cửa sổ thời gian` | Công cụ quản trị: hết budget → đóng băng feature |
| **Eventual consistency** | Ngừng ghi thì cuối cùng mọi replica giống nhau | Cần "vá" bằng client-centric guarantee cho UX chấp nhận được |
| **Failure domain** | Phạm vi cùng chết với nhau (đĩa, node, rack, AZ) | Replica phải nằm ở các failure domain khác nhau |
| **Fan-out on write / read** | Precompute lúc ghi vs tính lúc đọc | Chọn theo tỉ lệ đọc:ghi; hybrid cho celebrity |
| **Fencing token** | Số đơn điệu cấp cùng lock; resource từ chối token cũ | **Điều kiện để distributed lock thực sự đúng** |
| **FLP impossibility** | Hệ bất đồng bộ hoàn toàn không thể có consensus vừa safe vừa live | Vì vậy mọi hệ thật đều dùng timeout (partial synchrony) |
| **Gossip protocol** | Node trao đổi trạng thái với vài node ngẫu nhiên | Hội tụ O(log N); dùng cho membership, failure detection |
| **Gray failure** | Suy giảm một phần nhưng monitoring vẫn xanh | Chống bằng đo từ góc nhìn người dùng (synthetic probe) |
| **Graceful degradation** | Tắt tính năng bổ trợ để giữ tính năng thiết yếu | Phân lớp tính năng **trước** khi có sự cố |
| **Hedged request** | Gửi request thứ hai tới replica khác nếu chậm | Đổi ~5% tài nguyên thừa lấy cải thiện p99 lớn |
| **Hot key / hot partition** | Một khóa chiếm phần lớn tải | Consistent hashing **không** giúp; dùng L1 cache TTL ngắn |
| **HOL blocking** | Một gói/request chặn những cái sau | TCP-level (HTTP/2 vẫn có), giải bằng QUIC/HTTP3 |
| **Idempotency key** | Khóa client sinh, gửi kèm mọi lần thử của cùng ý định | Cần cả `request_hash` và trạng thái `IN_PROGRESS` mới đúng |
| **Leaderless replication** | Client ghi vào N replica, không có leader | Dùng quorum R+W>N; cần hòa giải xung đột |
| **Linearizability** | Mọi thao tác như xảy ra tức thời theo thứ tự thời gian thật | Khác serializability (thuộc tính của transaction) |
| **Little's Law** | `L = λW` — số việc trong hệ = tốc độ đến × thời gian ở lại | Cơ sở cho việc latency tăng dốc khi utilization > 70% |
| **Load shedding** | Từ chối một phần request ngay ở cửa khi quá tải | Từ chối 10% gọn gàng tốt hơn 100% timeout |
| **LSM-tree** | Ghi vào memtable → flush thành SSTable bất biến → compaction | Ghi rất nhanh, nén tốt; đọc phải xem nhiều SSTable |
| **LWW (Last Write Wins)** | Giữ bản có timestamp lớn hơn | Mất dữ liệu âm thầm; phụ thuộc đồng hồ |
| **mTLS** | Cả hai bên trình certificate | Xác thực service-to-service không cần secret trong app |
| **Multi-leader** | Nhiều node nhận ghi | Xung đột ghi là phần khó nhất; tránh bằng phân vùng theo khóa |
| **P2C (power of two choices)** | Lấy ngẫu nhiên 2 node, chọn node tải nhẹ hơn | Gần bằng least-connections mà **không cần trạng thái toàn cục** |
| **PACELC** | Khi Partition chọn A/C; **khi bình thường** chọn Latency/Consistency | Hữu ích hơn CAP vì phần lớn thời gian không có partition |
| **Percentile (p99/p999)** | Ngưỡng mà 99%/99,9% request nhanh hơn | **Không thể lấy trung bình các p99** — phải tổng hợp từ histogram |
| **Quorum (R+W>N)** | Vùng đọc và vùng ghi giao nhau | **Không** cho linearizability, chỉ cho vùng giao |
| **Raft** | Thuật toán consensus có leader mạnh | Dùng số node **lẻ**; throughput bị chặn bởi leader |
| **Read-your-writes** | Đọc thấy ghi của chính mình | Cách thực dụng: đọc từ leader trong N giây sau khi ghi |
| **Reliability** | Xác suất hoạt động **đúng** trong một khoảng thời gian | Khác availability (trả lời được ≠ trả lời đúng) |
| **RPO / RTO** | Lượng dữ liệu / thời gian tối đa được phép mất | RPO → tần suất backup; RTO → chiến lược restore |
| **RUM conjecture** | Read–Update–Memory: chỉ tối ưu được 2 trong 3 | Khung để hiểu vì sao không có engine "tốt nhất" |
| **Saga** | Chuỗi transaction cục bộ + bước bù trừ | Thay cho 2PC khi vượt ranh giới service |
| **Scale cube (X/Y/Z)** | Nhân bản / chia chức năng / chia dữ liệu | **Kiệt trục X trước** khi sang Y hoặc Z |
| **Serializability** | Kết quả tương đương một thứ tự tuần tự nào đó | Thuộc tính của transaction, không phải của thao tác đơn |
| **Service mesh** | Sidecar proxy xử lý mTLS, retry, observability | Thêm ~1ms mỗi hop + độ phức tạp vận hành |
| **Sharding** | Chia dữ liệu ngang thành nhiều shard | Quyết định gần như **không thể lùi**; loại trừ mọi cách khác trước |
| **Shard key** | Khóa quyết định bản ghi thuộc shard nào | Cardinality cao, phân bố đều, có trong hầu hết query, bất biến |
| **SLI / SLO / SLA** | Số đo / mục tiêu nội bộ / cam kết có chế tài | SLO nghiêm ngặt hơn SLA; SLI đo từ góc nhìn người dùng |
| **Single-flight** | Chỉ một request đi lấy dữ liệu, số còn lại chờ kết quả | Chống cache stampede |
| **Split-brain** | Hai nửa cluster cùng tưởng mình là bên sống | Chống bằng quorum số lẻ, witness, hoặc fencing |
| **SSE (Server-Sent Events)** | Một chiều server→client qua HTTP thường | **Mặc định nên xét trước WebSocket** khi chỉ cần đẩy xuống |
| **Stale-while-revalidate** | Trả bản cũ ngay + làm mới ở background | Không ai phải chờ; đồng thời chống stampede |
| **Stale-if-error** | CDN tiếp tục trả bản cũ khi origin lỗi | Biện pháp resilience rẻ nhất cho nội dung đọc |
| **Stateless** | Node không giữ state riêng cho request | Điều kiện của horizontal scaling; state chuyển ra store dùng chung |
| **Sticky session** | Ghim client vào một node | Nên tránh; nếu cần thì dùng consistent hashing, không IP hash |
| **Tail latency amplification** | Fan-out N service làm p99 con thành p50 cha | N=100, p99 con 1% → 63% request cha gặp tail |
| **Thundering herd** | Nhiều client cùng hành động một lúc | Chống bằng jitter ở mọi chỗ: TTL, retry, reconnect |
| **Trie** | Cây theo ký tự cho prefix lookup | Dùng cho typeahead; hash map prefix→top-K thường đơn giản hơn và đủ |
| **Two Generals** | Không thể biết chắc bên kia đã nhận | Vì vậy **exactly-once delivery không tồn tại**; chỉ có at-least-once + idempotency |
| **USL (Universal Scalability Law)** | Bổ sung chi phí coherency vào Amdahl | Giải thích vì sao thêm node có thể làm **giảm** throughput |
| **Vector clock** | Theo dõi nhân quả, phát hiện thao tác đồng thời | Kích thước O(số node); Lamport clock không phát hiện được đồng thời |
| **Versioned key** | Đưa version vào cache key | Giải quyết "một thay đổi ảnh hưởng nhiều key không liệt kê được" |
| **WAL (Write-Ahead Log)** | Ghi log tuần tự trước khi sửa dữ liệu | Durability đến từ log, **không** từ data file |
| **WebSocket** | Kết nối song công bền | Stateful: cần registry, backplane, heartbeat, kế hoạch drain |
| **Write amplification** | Một byte logic → nhiều byte thật xuống disk | Một trong ba amplification (write/read/space) của LSM |
| **Zipf distribution** | Truy cập rất lệch: 1% khóa chiếm >50% lưu lượng | Vì sao cache nhỏ vẫn đạt hit ratio cao |

---

## Bảng số liệu tham chiếu

### Latency

| Thao tác | Thời gian |
|---|---|
| L1 cache | 0,5 ns |
| RAM | 100 ns |
| NVMe random read | 16–100 µs |
| Round-trip cùng DC | ~0,5 ms |
| Redis cùng AZ | 0,3–2 ms |
| Query DB có index | 1–10 ms |
| Disk seek (HDD) | ~10 ms |
| RTT liên vùng (VN↔EU) | 150–250 ms |

**Tỉ lệ cần nhớ**: RAM nhanh hơn SSD ~1.000×; SSD nhanh hơn HDD ~100×; trong DC nhanh hơn liên vùng ~100–500×.

### Thông lượng một node (bậc độ lớn)

| Thành phần | Tham chiếu |
|---|---|
| App node (JVM) | 1K–10K QPS |
| PostgreSQL/MySQL | 3K–20K QPS đọc; 1K–5K TPS ghi |
| Redis | 50K–150K QPS |
| Cassandra | 10K–50K ghi/s |
| Kafka broker | hàng trăm nghìn msg/s |
| Nginx/Envoy | 50K–200K req/s |
| Network 10 Gbps | ~1,2 GB/s |

### Availability

| SLO | Downtime/tháng |
|---|---|
| 99% | 7,2 giờ |
| 99,9% | 43,8 phút |
| 99,95% | 21,9 phút |
| 99,99% | 4,38 phút |
| 99,999% | 26,3 giây |

### Mẹo ước lượng

```text
1 ngày ≈ 86.400 s ≈ 10⁵ s   (chia cho 100.000; kết quả hơi thấp ~15%)
2¹⁰ ≈ 1K · 2²⁰ ≈ 1M · 2³⁰ ≈ 1G · 2⁴⁰ ≈ 1T
Peak factor: 2–3× thường; 5–10× nếu có sự kiện
Hot data: quy tắc 80/20, thực tế thường lệch hơn (Zipf)
Chuỗi availability: A_total = A₁ × A₂ × ... ;  dự phòng: 1 - (1-A)ⁿ
Queueing: thời gian chờ ~ 1/(1-ρ) → ρ=0,9 thì chờ gấp 10× thời gian phục vụ
```

---

## Nguyên tắc xuyên suốt

```text
1. Access pattern TRƯỚC, công nghệ SAU
2. Kiệt trục X (nhân bản) trước khi sang Y (chia chức năng) hoặc Z (chia dữ liệu)
3. Mọi lời gọi ngoài phải có timeout; mọi retry phải có jitter
4. Mọi cache key phải có TTL, kể cả khi đã có invalidation chủ động
5. Từ chối một phần gọn gàng tốt hơn timeout toàn bộ
6. Exactly-once không tồn tại ở tầng vận chuyển → at-least-once + idempotency
7. Cách xử lý xung đột tốt nhất là thiết kế để không có xung đột (single-writer)
8. Đo trước, sửa sau; sửa một thứ mỗi lần
9. Availability bảo vệ khỏi mất hạ tầng; backup bảo vệ khỏi mất dữ liệu — cần cả hai
10. Mọi biện pháp tạm (force plan, hint, fallback cứng) phải có ngày review
```

---

*Cập nhật lần cuối: 2026-07-30*
