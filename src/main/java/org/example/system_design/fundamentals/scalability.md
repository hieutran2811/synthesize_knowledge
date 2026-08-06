# Scalability – Mở rộng hệ thống

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Đọc tiếp: [Load Balancing](load_balancing.md), [Databases Design](databases_design.md).

---

## 1. Scalability không phải performance

Hai khái niệm bị dùng lẫn nhau nhưng trả lời hai câu hỏi khác nhau:

| | Câu hỏi | Đo bằng |
|---|---|---|
| **Performance** | Hệ thống nhanh thế nào ở **tải hiện tại**? | p50/p99 latency, throughput |
| **Scalability** | Khi tải tăng 10×, hệ thống có **giữ được** hiệu năng đó bằng cách thêm tài nguyên? | Đường cong latency/throughput theo tải |

Một hệ thống có thể nhanh mà không scale được (single node tối ưu cực tốt, hết giới hạn là hết), và ngược lại có thể scale tốt mà chậm (mỗi request đi qua 8 service, mỗi hop 5ms).

Câu hỏi thiết kế đúng luôn là: **thành phần nào sẽ đụng trần trước?** Trả lời được câu đó thì biết nên đầu tư vào đâu; không trả lời được thì mọi "tối ưu" đều là phỏng đoán.

### 1.1 Hai định luật quyết định trần scaling

**Amdahl's Law** — phần tuần tự giới hạn tăng tốc:

```text
Speedup(N) = 1 / (S + (1-S)/N)      S = tỉ lệ phần KHÔNG song song hóa được

S = 5%, N = ∞  → speedup tối đa 20×
```

Nói cách khác: nếu 5% công việc phải chạy tuần tự (một lock, một DB primary, một service điều phối), thêm bao nhiêu máy cũng không vượt được 20×. Đây là lý do "thêm node" ngừng hiệu quả ở một điểm.

**Universal Scalability Law (USL)** — bổ sung yếu tố **coherency** (chi phí phối hợp giữa các node) mà Amdahl bỏ qua:

```text
Throughput không chỉ chững lại — nó có thể GIẢM khi thêm node,
vì chi phí đồng bộ/tranh chấp tăng theo N².
```

Đây chính là hiện tượng "thêm pod mà latency tệ hơn": các node cạnh tranh cùng một DB, cùng một lock, cùng một cache. Bài học thực dụng: **giảm coordination quan trọng hơn thêm node**.

---

## 2. Vertical vs Horizontal

### 2.1 Vertical scaling (scale up)

Tăng tài nguyên một máy: 4 vCPU/16GB → 32 vCPU/256GB.

| Được | Mất |
|---|---|
| Không đổi kiến trúc, không đổi code | Có trần cứng (instance lớn nhất của nhà cung cấp) |
| Không có vấn đề phân tán (không network hop, không consistency) | SPOF: máy chết là hết |
| Đơn giản để suy luận và debug | Nâng cấp thường cần downtime |
| Thường là lựa chọn **rẻ nhất** ở quy mô nhỏ–vừa | Giá tăng phi tuyến ở đầu cao |

Vertical scaling bị coi rẻ một cách không công bằng. Trên phần cứng hiện nay, một máy 128 vCPU / 2TB RAM / NVMe xử lý được lượng tải mà phần lớn ứng dụng doanh nghiệp không bao giờ đạt tới. **Với database, vertical scaling vẫn luôn là bước đầu tiên nên thử** — vì sharding là quyết định gần như không thể lùi.

### 2.2 Horizontal scaling (scale out)

Thêm nhiều máy chạy cùng service, đứng sau load balancer.

| Được | Mất |
|---|---|
| Không trần lý thuyết | Ứng dụng phải **stateless** |
| Chịu lỗi: một node chết vẫn còn lại | Cần LB, service discovery, health check |
| Dùng được commodity hardware | Mọi vấn đề của hệ phân tán: consistency, partial failure, tracing |
| Deploy rolling/canary được | Chi phí coordination (xem USL ở mục 1.1) |

### 2.3 Quyết định thực dụng

```text
Tầng stateless (API, worker)   → horizontal, gần như luôn đúng
Tầng cache                     → horizontal (sharding theo key)
Tầng database                  → vertical TRƯỚC, rồi read replica, rồi mới sharding
Tầng có state đặc thù
   (WebSocket, game session)    → horizontal + routing theo session, cần backplane
```

Thứ tự cho database rất quan trọng và hay bị làm ngược: nhiều đội shard sớm vì "sẽ cần", rồi chịu vĩnh viễn chi phí cross-shard query và resharding cho một khối lượng dữ liệu mà một máy đơn xử lý thoải mái.

---

## 3. Stateless design – điều kiện của horizontal scaling

```text
Stateful (không scale được):
  User A → Node 1 (session của A nằm trong RAM Node 1)   → OK
  User A → Node 2 (không có session)                      → 401

Stateless:
  User A → bất kỳ node → xác thực token / đọc state từ store dùng chung → OK
```

State không biến mất, nó chỉ **chuyển chỗ** — từ trong process ra một store dùng chung:

| Loại state | Chuyển đi đâu | Lưu ý |
|---|---|---|
| HTTP session | Redis session store, hoặc JWT tự chứa | JWT khó thu hồi trước hạn; Redis thêm một dependency nóng |
| Cache trong process | Redis/Memcached; hoặc giữ L1 local + pub/sub invalidation | Local cache vẫn rất giá trị, xem [caching.md](caching.md) mục 8 |
| File upload | Object storage (S3/MinIO) | Không bao giờ ghi lên disk local của pod |
| Kết nối WebSocket | Bản chất stateful → routing + pub/sub backplane | Xem [networking_protocols.md](networking_protocols.md) mục 5 |
| Job đang xử lý | Message queue với ack/visibility timeout | Node chết → message được giao lại |
| Counter/sequence | Redis atomic, hoặc ID sinh phân tán | Xem [foundational_designs.md](../case_studies/foundational_designs.md) mục 2 |

Điểm quan trọng về JWT vs session store — đây là đánh đổi thật, không có đáp án mặc định:

| | JWT tự chứa | Session store (Redis) |
|---|---|---|
| Mỗi request cần gọi store? | Không | Có (thêm ~1ms) |
| Thu hồi ngay lập tức | Khó (cần blacklist → mất tính tự chứa) | Dễ (xóa key) |
| Kích thước request | Lớn hơn (token trong header mỗi request) | Nhỏ |
| Điểm phụ thuộc | Không | Redis là dependency nóng |

Với hệ cần logout tức thời hoặc thu hồi quyền ngay (ngân hàng, nội bộ doanh nghiệp), session store thường đúng hơn dù nghe "kém hiện đại".

---

## 4. Auto-scaling

### 4.1 Bốn kiểu, bốn bài toán

| Kiểu | Trigger | Phù hợp |
|---|---|---|
| **Reactive** | CPU, memory, RPS, custom metric | Tải khó đoán |
| **Scheduled** | Cron | Biết trước đỉnh (mở bán, cuối tháng, Black Friday) |
| **Predictive** | Mô hình dự báo từ lịch sử | Có mùa vụ rõ và lịch sử đủ dài |
| **Event-driven (KEDA)** | Độ sâu queue, Kafka consumer lag | Worker xử lý theo hàng đợi |

```yaml
# HPA: kết hợp CPU và một external metric nghiệp vụ
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: order-api }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: order-api }
  minReplicas: 3            # ≥ 3 để chịu được mất 1 pod mà không quá tải
  maxReplicas: 40
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 65 } }
    - type: External
      external:
        metric: { name: kafka_consumer_lag }
        target: { type: AverageValue, averageValue: "1000" }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies: [{ type: Percent, value: 100, periodSeconds: 30 }]   # tối đa gấp đôi mỗi 30s
    scaleDown:
      stabilizationWindowSeconds: 300                                 # xuống chậm, tránh flapping
      policies: [{ type: Percent, value: 20, periodSeconds: 60 }]
```

### 4.2 Bốn cái bẫy của auto-scaling

| Bẫy | Vì sao | Cách xử lý |
|---|---|---|
| **Scale không kịp đỉnh** | Đo metric → quyết định → pull image → khởi động JVM → warm-up: có thể 60–180 giây | Pre-scale theo lịch, giữ pool nóng, giảm thời gian khởi động (CDS/AOT/native) |
| **Flapping** | Scale up rồi down liên tục quanh ngưỡng | `stabilizationWindowSeconds` bất đối xứng (lên nhanh, xuống chậm) |
| **Scale app nhưng nghẽn ở DB** | Thêm 40 pod = 400 connection tới DB → DB sập | Giới hạn pool size, dùng PgBouncer/ProxySQL, đặt `maxReplicas` theo trần DB |
| **Metric sai** | CPU thấp nhưng đang chờ I/O → không scale dù đã tắc | Scale theo metric nghiệp vụ (RPS, queue depth, p99) thay vì chỉ CPU |

Bẫy thứ ba là sự cố kinh điển và phản trực giác: **auto-scaling có thể là nguyên nhân của sự cố**, khi tầng dưới không scale theo. Luôn tính `maxReplicas × pool_size_per_pod ≤ giới hạn kết nối của DB`.

---

## 5. Scale Cube – ba trục mở rộng

```text
        Z: chia theo dữ liệu / khách hàng (shard, cell)
        │
        │      Y: chia theo chức năng (microservices)
        │     /
        │    /
        └───────────── X: nhân bản (thêm node giống nhau)
```

| Trục | Nghĩa | Chi phí phức tạp | Khi nào |
|---|---|---|---|
| **X – nhân bản** | Nhiều instance giống nhau sau LB | Thấp | Luôn làm trước |
| **Y – chia chức năng** | Tách service theo bounded context | Cao | Khi tổ chức lớn, cần deploy độc lập |
| **Z – chia dữ liệu** | Sharding, cell-based | Cao nhất | Khi X và Y không đủ |

Thứ tự này là lời khuyên quan trọng nhất của mô hình: **kiệt trục X trước khi sang Y hoặc Z**. Tách microservices để "scale tốt hơn" khi vấn đề thật chỉ là thiếu index hay thiếu cache là cách chắc chắn nhất để làm hệ thống chậm hơn và khó vận hành hơn.

---

## 6. Cell-based architecture

Chia hệ thống thành nhiều "cell" độc lập, mỗi cell là một bản sao đầy đủ của stack phục vụ một tập khách hàng.

```text
            ┌── Cell 1: LB → App → Cache → DB   (tenant 1–1000)
Router ─────┼── Cell 2: LB → App → Cache → DB   (tenant 1001–2000)
(thin)      └── Cell 3: LB → App → Cache → DB   (tenant 2001–3000)

Cell 2 sập → chỉ 1/3 khách hàng bị ảnh hưởng, không phải toàn bộ.
```

| Được | Mất |
|---|---|
| **Blast radius giới hạn** — đây là lý do chính | Chi phí hạ tầng nhân theo số cell |
| Triển khai theo cell: canary ở cell nhỏ trước | Router phải cực đơn giản và cực bền (nó là SPOF duy nhất) |
| Trần scaling rõ ràng và đo được cho mỗi cell | Vận hành N bản sao: migration, monitoring, on-call phức tạp hơn |
| Cô lập hiệu năng: tenant ồn ào không ảnh hưởng cell khác | Cân bằng lại tenant giữa các cell là việc khó |

Cell-based là mô hình đúng khi **availability quan trọng hơn chi phí** và khi bạn đã có nhiều khách hàng. Nó liên quan chặt tới mô hình multi-tenancy (silo/pool/bridge) — xem `saas/multi_tenancy.md`.

---

## 7. Nhận diện điểm nghẽn theo tầng

| Tầng | Trần điển hình | Dấu hiệu | Hướng giải |
|---|---|---|---|
| CDN/edge | Cache hit ratio thấp | Origin nhận nhiều request tĩnh | TTL, versioned URL — [caching.md](caching.md) |
| LB | Số kết nối đồng thời, SSL CPU | Kết nối bị từ chối | Scale LB, offload TLS — [load_balancing.md](load_balancing.md) |
| App | CPU, thread pool, GC | CPU cao hoặc thread chờ | Horizontal scale, giảm blocking |
| Cache | RAM, hot key | Một key chiếm phần lớn tải | Shard key, replicate hot key, L1 local |
| DB đọc | Read QPS, IOPS | Replica lag, query chậm | Read replica, cache, index |
| DB ghi | Write QPS, kích thước | Lock, log I/O | Batch, queue, cuối cùng là sharding |
| Queue | Consumer lag | Lag tăng đơn điệu | Thêm consumer, tăng partition |
| Dịch vụ ngoài | Rate limit của đối tác | 429, timeout | Backpressure, cache, hợp đồng lại |

Nguyên tắc: **điểm nghẽn luôn di chuyển**. Sửa được DB thì nghẽn sang cache, sửa cache thì sang network. Vì vậy tối ưu phải theo vòng lặp đo → sửa → đo lại, không phải một đợt "tối ưu toàn diện".

---

## 8. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Vertical scaling | Đơn giản, không vấn đề phân tán | Trần cứng, SPOF | Database; giai đoạn đầu; luôn thử trước |
| Horizontal scaling | Không trần, chịu lỗi | Phải stateless, phức tạp phân tán | Tầng stateless |
| Stateless + JWT | Không phụ thuộc store | Khó thu hồi token | Hệ công khai, quy mô lớn |
| Stateless + session store | Thu hồi ngay | Thêm dependency nóng | Cần logout/thu hồi tức thời |
| Auto-scaling reactive | Tiết kiệm chi phí | Phản ứng chậm với đỉnh dốc | Tải biến động vừa phải |
| Pre-scale theo lịch | Sẵn sàng cho đỉnh | Trả tiền cho công suất không dùng | Biết trước sự kiện |
| Sharding sớm | Chuẩn bị cho tương lai | Chi phí vĩnh viễn: cross-shard, resharding | Chỉ khi đã chứng minh cần |
| Cell-based | Blast radius nhỏ, cô lập hiệu năng | Chi phí × N, vận hành phức tạp | Nhiều khách hàng, SLA cao |
| Microservices để scale | Scale từng phần độc lập | Network hop, eventual consistency, vận hành | Khi tổ chức lớn, không phải vì hiệu năng |

---

## 9. Bảng tham chiếu: kiến trúc theo quy mô

| Quy mô | Kiến trúc điển hình | Điều đáng làm tiếp |
|---|---|---|
| 0–1K user | Một máy, một DB, không LB | Backup, monitoring cơ bản |
| 1K–100K | LB + 2–5 app node + read replica + cache | Tách static ra CDN, đặt SLO |
| 100K–1M | CDN + cache nhiều tầng + read replica + queue async | Bắt đầu tách service theo domain nếu tổ chức cần |
| 1M–100M | Nhiều service, Kafka, sharding, multi-AZ | Cell-based, multi-region cho DR |
| 100M+ | Cell-based, phân phối toàn cầu, hạ tầng riêng | Tối ưu chi phí trở thành ưu tiên hàng đầu |

Bảng này là điểm khởi đầu để tránh over-engineering, không phải công thức. Rất nhiều hệ thống 100K user chạy tốt trên kiến trúc của cột "1K–100K" nếu dữ liệu và truy vấn được thiết kế tử tế.

---

## 10. Real-world

| Tổ chức | Cách làm đáng học |
|---|---|
| **Shopify** | Shard theo shop (pod), nhiều shop trên một pod, Vitess quản shard. Ranh giới shard = ranh giới nghiệp vụ tự nhiên → gần như không có cross-shard query |
| **Netflix** | Cell-based + active-active nhiều region; Chaos Engineering để kiểm chứng thay vì giả định |
| **Discord** | Chuyển service nóng sang Rust để một node chịu tải cực lớn — chứng minh vertical/tối ưu vẫn hiệu quả ở quy mô lớn |
| **Stack Overflow** | Quy mô rất lớn trên số máy rất ít, nhờ cache tốt và SQL được tối ưu — bằng chứng mạnh nhất chống over-engineering |
| **Amazon** | Two-pizza team: ranh giới service theo ranh giới tổ chức (Conway's Law) |

Điểm chung của các ví dụ tốt: **ranh giới chia (shard key, service boundary, cell) trùng với ranh giới nghiệp vụ tự nhiên**. Khi chia theo ranh giới kỹ thuật thuần túy, chi phí cross-boundary sẽ đuổi theo mãi.

---

## 11. Ghi chú – chủ đề tiếp theo

- [load_balancing.md](load_balancing.md): phân phối tải, consistent hashing, health check.
- [caching.md](caching.md): giảm tải tầng dưới, cache nhiều tầng.
- [databases_design.md](databases_design.md): read replica, sharding chi tiết.
- [availability_reliability.md](availability_reliability.md): SLO, error budget, resilience pattern.
- [interview_framework_estimation.md](interview_framework_estimation.md): ước lượng để biết có cần scale hay không.

Từ khóa mở rộng: Little's Law (`L = λW`), queueing theory và vì sao latency tăng dốc khi utilization > 70%, backpressure, load shedding, bin packing tenant vào cell, warm pool, Conway's Law, scale-to-zero.

Một quan hệ định lượng nên nhớ khi đặt ngưỡng auto-scaling: theo lý thuyết hàng đợi, thời gian chờ tăng theo `1/(1-ρ)` với `ρ` là mức sử dụng. Ở `ρ = 0.5` latency gấp 2 lần thời gian phục vụ; ở `ρ = 0.9` là 10 lần; ở `ρ = 0.95` là 20 lần. Đó là lý do ngưỡng CPU 65–70% (không phải 90%) là lựa chọn hợp lý.

---

*Cập nhật lần cuối: 2026-07-30*
