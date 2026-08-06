# Interview Framework & Capacity Estimation – Phương pháp giải bài

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Áp dụng vào bài cụ thể: [foundational_designs.md](../case_studies/foundational_designs.md), [realtime_scale_designs.md](../case_studies/realtime_scale_designs.md), [platform_designs.md](../case_studies/platform_designs.md).

---

## 1. Vì sao cần một quy trình

Bài system design là **mở**: không có đáp án đúng duy nhất. Người phỏng vấn (và trong công việc thật, đồng nghiệp) đánh giá:

| Được đánh giá | Không được đánh giá |
|---|---|
| Bạn làm rõ yêu cầu thế nào | Có nhớ đúng kiến trúc của Twitter không |
| Bạn ước lượng và dùng con số ra sao | Có kể được nhiều công nghệ không |
| Bạn nêu trade-off và gắn với yêu cầu | Vẽ có đẹp không |
| Bạn đào sâu khi được yêu cầu | Có nhắc đủ mọi buzzword không |

Điều tương tự đúng trong công việc: một design doc tốt khác một design doc tệ chủ yếu ở chỗ **có nêu rõ giả định, con số, và cái mình đánh đổi**.

---

## 2. RESHADED

```text
R – Requirements       Functional + Non-functional + phạm vi (chốt giả định)
E – Estimation         QPS, dung lượng, băng thông, bộ nhớ, số server
S – Storage / Schema   Mô hình dữ liệu, chọn store, shard key
H – High-level design  Boxes & arrows: tách rõ read path và write path
A – APIs               Các endpoint chính
D – Data flow          Request đi qua đâu, ai gọi ai
E – Evaluate           Bottleneck, SPOF, trade-off
D – Deep dive          Đào 1–2 thành phần theo gợi ý người phỏng vấn
```

Phân bổ thời gian cho một buổi 45 phút — quan trọng hơn bản thân framework:

```text
0–7 phút    Requirements (đừng tiếc thời gian ở đây)
7–12 phút   Estimation
12–17 phút  API + data model + shard key
17–27 phút  High-level design (vừa vẽ vừa nói)
27–40 phút  Deep dive (phần chiếm điểm nhiều nhất)
40–45 phút  Bottleneck, trade-off, "nếu có thêm thời gian tôi sẽ..."
```

### 2.1 Bước 1 – Requirements: nơi bài thi được quyết định

Sai lầm phổ biến nhất là nhảy vào vẽ ngay. Câu hỏi cần đặt:

| Nhóm | Câu hỏi |
|---|---|
| Phạm vi | Tính năng nào **trong** và **ngoài** phạm vi? (chốt 3–4 tính năng cốt lõi) |
| Quy mô | DAU/MAU? Tỉ lệ đọc:ghi? Tăng trưởng dự kiến? |
| Độ trễ | p99 mục tiêu cho đường đi chính? |
| Nhất quán | Dữ liệu được phép cũ bao lâu? Có phần nào cần strong consistency? |
| Dữ liệu | Kích thước mỗi bản ghi? Retention? Có cần xóa theo yêu cầu người dùng? |
| Phạm vi địa lý | Một region hay toàn cầu? Có ràng buộc lưu trữ dữ liệu theo vùng? |
| Ai dùng | Người dùng cuối, hay service khác (ảnh hưởng chọn REST/gRPC)? |

Sau đó **viết ra giả định** để người phỏng vấn có cơ hội điều chỉnh:

```text
"Tôi sẽ giả định: 200M DAU, đọc:ghi = 100:1, p99 < 200ms cho đường đọc,
 feed trễ vài giây là chấp nhận được, một region trước rồi mở rộng sau.
 Anh/chị muốn điều chỉnh gì không?"
```

Một câu như trên tiết kiệm 20 phút thiết kế sai hướng.

### 2.2 Functional vs non-functional

| Functional (hệ thống **làm gì**) | Non-functional (làm **tốt thế nào**) |
|---|---|
| Rút gọn URL, redirect | Latency, availability, consistency |
| Post bài, xem feed, follow | Scalability, durability |
| Gửi/nhận tin nhắn, presence | Cost, security, khả năng vận hành |

Non-functional là nơi kiến trúc thực sự được quyết định. "Đọc:ghi = 100:1" dẫn tới cache + read replica. "p99 < 50ms toàn cầu" dẫn tới edge/CDN. "Không được mất dữ liệu" dẫn tới replication đồng bộ. Ngược lại, danh sách functional dài chỉ dẫn tới nhiều box hơn trên bảng.

---

## 3. Capacity estimation

### 3.1 Quy trình năm bước

```text
1. Traffic    : DAU → hành động/user/ngày → QPS trung bình → QPS đỉnh
2. Storage    : bản ghi/ngày × bytes/bản ghi × retention × replication factor
3. Bandwidth  : QPS × payload (tách vào và ra)
4. Memory     : working set cần cache (thường 20% dữ liệu nóng)
5. Servers    : QPS đỉnh ÷ công suất một node
```

### 3.2 Mẹo làm tròn

```text
1 ngày ≈ 86.400 s ≈ 10⁵ s     → chia cho 100.000 (nhớ là kết quả HƠI thấp, ~15%)
1 tháng ≈ 2,6 × 10⁶ s
1 năm  ≈ 3,2 × 10⁷ s

2¹⁰ ≈ 1 nghìn (KB)   2²⁰ ≈ 1 triệu (MB)   2³⁰ ≈ 1 tỉ (GB)   2⁴⁰ ≈ 1 nghìn tỉ (TB)

Kích thước tham chiếu:
  char ASCII 1 B · UUID 16 B · timestamp 8 B · int64 8 B
  một tweet/comment ~300 B · một bản ghi metadata ~500 B–1 KB
  ảnh thumbnail ~20 KB · ảnh full ~500 KB–2 MB · 1 phút video 1080p ~50 MB
```

Peak factor: 2–3× cho lưu lượng đều theo ngày, 5–10× cho hệ có sự kiện (mở bán, livestream, thông báo đẩy hàng loạt).

### 3.3 Ví dụ trình bày mẫu – hệ thống kiểu Twitter

```text
Giả định: 200M DAU · đọc 50 timeline/ngày · post 2 tweet/ngày · tweet 300 B

Traffic
  Read  QPS_avg = 200M × 50 / 10⁵ = 100.000 → đỉnh ×3 ≈ 300K QPS
  Write QPS_avg = 200M × 2  / 10⁵ = 4.000   → đỉnh ×3 ≈ 12K QPS
  → đọc:ghi = 25:1 → READ-HEAVY → precompute + cache là trục thiết kế

Storage
  Tweet/ngày = 200M × 2 = 400M bản ghi × 300 B = 120 GB/ngày
  5 năm × replication 3 = 120 GB × 1825 × 3 ≈ 650 TB
  → vượt xa một node → SHARDING; và metadata tách khỏi media

Bandwidth
  In  = 12K QPS × 300 B ≈ 3,6 MB/s        (nhỏ)
  Out = 300K QPS × 20 tweet × 300 B ≈ 1,8 GB/s   (lớn → CDN + cache)

Memory (cache)
  Hot set 20% của 1 ngày ≈ 24 GB/ngày; giữ 3 ngày ≈ 72 GB
  → cụm Redis vài node, không phải một node

Servers
  Giả sử một app node xử lý 5K QPS → 300K / 5K = 60 node cho đường đọc
```

Điều làm ví dụ này tốt không phải các con số, mà là **dòng kết luận sau mỗi khối**: read-heavy → cache; 650 TB → sharding; 1,8 GB/s out → CDN. Ước lượng mà không dẫn tới kết luận kiến trúc là ước lượng vô ích.

### 3.4 Công suất tham chiếu một node

Dùng để bước 5 không phải đoán. Đây là **bậc độ lớn**, không phải cam kết:

| Thành phần | Thông lượng tham chiếu |
|---|---|
| App node (JVM, request nhẹ) | 1.000–10.000 QPS |
| PostgreSQL/MySQL (query đơn giản, có index) | 3.000–20.000 QPS đọc; 1.000–5.000 TPS ghi |
| Redis (một instance) | 50.000–150.000 QPS |
| Cassandra (một node) | 10.000–50.000 ghi/s |
| Kafka (một broker) | hàng trăm MB/s, hàng trăm nghìn msg/s |
| Nginx/Envoy | 50.000–200.000 req/s (tùy TLS, keepalive) |
| NVMe | 100.000–1.000.000 IOPS |
| Network 10 Gbps | ~1,2 GB/s |

Khi trình bày, nói rõ đây là bậc độ lớn và bạn sẽ benchmark: "tôi giả định một node PostgreSQL chịu ~10K QPS đọc với query có index; nếu thực tế thấp hơn thì cần thêm read replica hoặc cache sâu hơn".

---

## 4. Latency numbers và percentile

### 4.1 Bảng latency

| Thao tác | Thời gian | So với L1 |
|---|---|---|
| L1 cache | 0,5 ns | 1× |
| L2 cache | 7 ns | 14× |
| Mutex lock/unlock | 25 ns | 50× |
| Truy cập RAM | 100 ns | 200× |
| Nén 1 KB | ~3 µs | |
| Đọc 1 MB tuần tự từ RAM | ~3 µs | |
| SSD/NVMe random read | 16–100 µs | |
| Đọc 1 MB tuần tự từ NVMe | ~50–100 µs | |
| Round-trip trong cùng DC | ~0,5 ms | 1.000.000× |
| Đọc 1 MB qua mạng 1 Gbps | ~10 ms | |
| Disk seek (HDD) | ~10 ms | |
| RTT liên vùng (VN↔EU) | 150–250 ms | |

Ba tỉ lệ đáng nhớ hơn cả bảng:

```text
RAM nhanh hơn SSD  ~1.000×
SSD nhanh hơn HDD  ~100×
Trong DC nhanh hơn liên vùng  ~100–500×
```

Từ đó suy ra ba nguyên tắc: **cache trong RAM** khi được, **tránh random disk I/O**, và **đưa dữ liệu gần người dùng** (CDN/edge/multi-region) khi latency quan trọng.

### 4.2 Percentile – vì sao không dùng trung bình

```text
1000 request: 990 request 10ms, 10 request 5.000ms
  avg = (990×10 + 10×5000) / 1000 = 59,9 ms   ← nghe ổn
  p99 = 5.000 ms                              ← 1% người dùng đang có trải nghiệm rất tệ
```

Trung bình che tail. Vì vậy SLO luôn định nghĩa theo p99 hoặc p999, không theo avg.

Một điều nữa về percentile mà hay bị làm sai: **không thể lấy trung bình các p99**. p99 của cả hệ thống không phải trung bình p99 của các instance. Muốn đúng, phải tổng hợp từ histogram (Prometheus `histogram_quantile` trên các bucket đã cộng lại), không phải tính trung bình các giá trị p99 đã tính sẵn.

### 4.3 Tail latency amplification

```text
Một request fan-out tới N service song song, mỗi service p99 = 10ms.
Request chỉ xong khi service CHẬM NHẤT xong.

P(mọi service đều nhanh) = 0,99^N
  N=1   → 99%   chậm 1%
  N=10  → 90%   → 10% request gặp ít nhất một service ở tail
  N=100 → 37%   → 63% request gặp tail!
```

Đây là kết quả quan trọng nhất của mục này: **fan-out rộng khiến p99 của service con trở thành p50 của request cha**. Hệ quả thiết kế:

| Biện pháp | Cơ chế |
|---|---|
| **Giảm fan-out** | Gộp nhiều lời gọi thành một; denormalize dữ liệu |
| **Hedged request** | Gửi request thứ hai tới replica khác nếu chưa có kết quả sau p95; lấy cái về trước |
| **Timeout + fallback** | Không chờ service chậm; trả kết quả thiếu một phần |
| **Trả kết quả một phần** | 9/10 kết quả trong 50ms tốt hơn 10/10 trong 2s |
| **Giảm tail của service con** | Nguồn tail: GC pause, queueing, cache miss, contention, retransmit |

Hedged request đáng chú ý vì nó đổi một lượng nhỏ tài nguyên thừa (thường ~5% request bị gửi hai lần) lấy cải thiện p99 rất lớn.

---

## 5. Từ high-level tới deep dive

### 5.1 Sơ đồ khung, và cách vẽ

```text
Client → DNS → CDN → LB → API Gateway → Service ─→ Cache
                                              │        ↓
                                              │      Database (primary + replica)
                                              └─→ Message Queue → Workers
                                                                    ↓
                                                              Store/Search/Warehouse
```

Vẽ **tách read path và write path** ngay từ đầu. Đây là mẹo có giá trị nhất khi trình bày: nó cho thấy bạn hiểu rằng hai đường có yêu cầu khác nhau (đọc cần cache và replica; ghi cần durability và thứ tự), và nó tự nhiên dẫn tới các câu hỏi đúng.

### 5.2 Evaluate – bottleneck và SPOF theo tầng

| Tầng | Bottleneck | SPOF | Giải |
|---|---|---|---|
| DNS | TTL làm failover chậm | Nhà cung cấp DNS | Anycast, nhiều nhà cung cấp |
| CDN | Hit ratio thấp | Một nhà cung cấp | TTL/immutable URL; multi-CDN nếu cần |
| LB | Kết nối đồng thời, TLS CPU | Bản thân LB | Nhiều AZ, dự phòng ([load_balancing.md](load_balancing.md) mục 9) |
| App | CPU, thread pool | – (stateless) | Horizontal scale |
| Cache | Hot key, RAM | Cluster cache | L1 local, replicate hot key |
| DB đọc | Read QPS | – | Replica + cache |
| DB ghi | Write QPS, IOPS | **Primary** | Batch/queue → cuối cùng sharding |
| Queue | Consumer lag | Broker cluster | Thêm partition + consumer |
| Dịch vụ ngoài | Rate limit của đối tác | Nhà cung cấp | Cache, backpressure, fallback |

### 5.3 Xử lý hot key và hot partition

Đây là câu hỏi deep-dive gần như luôn được hỏi:

```text
Vấn đề: một khóa (sản phẩm sale, bài viral, tenant lớn) chiếm phần lớn tải
        → sharding/consistent hashing KHÔNG giúp: khóa đó vẫn về một node

Giải, theo thứ tự nên thử:
1. L1 cache trong process, TTL rất ngắn (1–5s) → giảm 99% tải xuống tầng dưới
2. Nhân bản khóa: key#1..key#N, client chọn ngẫu nhiên
3. Request coalescing / single-flight
4. Tách riêng: tenant/khóa lớn được cấp shard riêng
5. Nếu là ghi: gom lô, hoặc chuyển sang counter phân tán (CRDT/sharded counter)
```

---

## 6. Cách nói trade-off

Đây là phần phân biệt câu trả lời tốt với câu trả lời trung bình. Mẫu câu:

```text
"Tôi chọn X VÌ [yêu cầu cụ thể].
 Đánh đổi là [nhược điểm cụ thể].
 Nếu [điều kiện khác] thì tôi sẽ chọn Y."
```

Ví dụ cụ thể:

> "Tôi chọn fan-out on write vì đọc:ghi là 25:1, nên trả tiền một lần lúc ghi rẻ hơn nhiều lần lúc đọc. Đánh đổi là celebrity với 50M follower sẽ tạo 50M lượt ghi cho một post — nên tôi xử lý riêng bằng pull cho nhóm đó. Nếu tỉ lệ đọc:ghi là 2:1 thì fan-out on write không còn hợp lý."

Ba yếu tố làm câu này tốt: gắn với **con số** đã ước lượng, nêu rõ **cái mất**, và có **điều kiện đảo ngược quyết định**.

---

## 7. Lỗi thường gặp

| Lỗi | Vì sao tệ | Sửa |
|---|---|---|
| Nhảy vào vẽ ngay | Thiết kế sai hướng, mất thời gian | Dành 5–7 phút cho requirements |
| Không ước lượng | Không biết có cần sharding/cache không | Luôn làm bước E |
| Over-engineering | Kafka + microservices cho 1.000 user | Bắt đầu đơn giản, nêu điều kiện để phức tạp hóa |
| Kể tên công nghệ mà không lý do | Không thể hiện tư duy | Mỗi lựa chọn gắn một yêu cầu |
| Im lặng khi suy nghĩ | Người phỏng vấn không thấy tư duy | Nói ra cả hướng đang loại bỏ |
| Bỏ qua SPOF và failure mode | Thiết kế chỉ chạy khi mọi thứ ổn | Tự hỏi "nếu cái này chết thì sao" ở mỗi box |
| Không nhắc consistency | Bỏ mất trục quan trọng nhất | Nói rõ chỗ nào eventual, chỗ nào strong |
| Đào sâu cái mình thích | Không trả lời câu được hỏi | Theo gợi ý người phỏng vấn |
| Bảo vệ đến cùng lựa chọn của mình | Mất điểm về hợp tác | Nghe gợi ý, điều chỉnh, giải thích lại |

Về over-engineering, một cách nói ghi điểm: *"Ở quy mô này một PostgreSQL với read replica là đủ. Tôi sẽ thêm sharding khi dung lượng vượt ~2TB hoặc write QPS vượt ~5K, và đây là dấu hiệu tôi sẽ theo dõi."* — nó cho thấy bạn biết cả kiến trúc phức tạp **và** biết khi nào chưa cần nó.

---

## 8. Trade-offs của bản thân framework

| | Được | Mất |
|---|---|---|
| Có quy trình | Không bỏ sót, dễ giao tiếp, ước lượng dẫn dắt kiến trúc | Máy móc nếu đi theo cứng nhắc |
| Ước lượng chi tiết | Quyết định có cơ sở | Tốn thời gian nếu quy mô nhỏ và rõ ràng |
| Vẽ đầy đủ mọi tầng | Thể hiện bao quát | Loãng, hết thời gian cho deep dive |

Cách dùng đúng: framework là **danh sách kiểm tra để không bỏ sót**, không phải trình tự bắt buộc. Nếu người phỏng vấn muốn đào sâu vào cache ở phút thứ 10, hãy theo họ — rồi quay lại phần còn thiếu sau.

---

## 9. Danh sách bài tập theo mức

| Mức | Bài | Trọng tâm | Tài liệu |
|---|---|---|---|
| Nền tảng | URL shortener | Cache, sinh ID, read-heavy | [foundational_designs.md](../case_studies/foundational_designs.md) |
| Nền tảng | Distributed ID | Clock skew, coordination | như trên |
| Nền tảng | Rate limiter | Atomic, hot key, fail-open/closed | như trên |
| Trung cấp | News feed | Fan-out, celebrity, precompute | [realtime_scale_designs.md](../case_studies/realtime_scale_designs.md) |
| Trung cấp | Chat | WebSocket, ordering, presence | như trên |
| Trung cấp | Proximity/geo | Geohash/quadtree/S2 | như trên |
| Nâng cao | Object storage (S3) | Metadata vs data, durability, erasure coding | [platform_designs.md](../case_studies/platform_designs.md) |
| Nâng cao | Typeahead/search | Trie, precompute, ranking | như trên |
| Nâng cao | Payment/ledger | Idempotency, exactly-once, đối soát | như trên |
| Nâng cao | Notification | Fan-out, retry, dedup, đa kênh | như trên |

---

## 10. Ghi chú – chủ đề tiếp theo

- [../case_studies/foundational_designs.md](../case_studies/foundational_designs.md): áp dụng framework từ đầu đến cuối.
- [scalability.md](scalability.md), [load_balancing.md](load_balancing.md), [caching.md](caching.md), [databases_design.md](databases_design.md): công cụ mở rộng từng tầng.
- [availability_reliability.md](availability_reliability.md): SLO, p99, resilience.
- [distributed_systems_theory.md](distributed_systems_theory.md): nền lý thuyết cho phần consistency.

Từ khóa mở rộng: peak factor, working set, quy tắc 80/20 cho dữ liệu nóng, hedged request, tail tolerance, `histogram_quantile`, back-of-envelope, Little's Law, capacity headroom, error budget khi trình bày SLO.

---

*Cập nhật lần cuối: 2026-07-30*
