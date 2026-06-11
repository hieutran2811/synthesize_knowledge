# Interview Framework & Capacity Estimation – Phương pháp giải bài

> Bổ trợ cho [../system_design_knowledge.md](../system_design_knowledge.md) (RESHADED + latency numbers ở mức tổng quan). File này đi sâu: quy trình, ước lượng back-of-envelope, percentiles, bottleneck.

## What – Vì sao cần framework?

Bài System Design **mở** (vô số đáp án) → cần **quy trình** để: làm rõ phạm vi, ước lượng quy mô, thiết kế có cơ sở, và **trình bày trade-off**. Người phỏng vấn đánh giá **cách tư duy & giao tiếp**, không phải "đáp án đúng".

---

## How – RESHADED Framework (chi tiết)

```
R – Requirements      Functional + Non-functional + scope (làm rõ, chốt giả định)
E – Estimation        Traffic (QPS), Storage, Bandwidth, Memory, #servers
S – Storage/Schema    Data model, chọn SQL/NoSQL, sharding key
H – High-level Design  Boxes & arrows: client → LB → service → cache → DB
A – APIs              Endpoint/signature chính (REST/gRPC)
D – Data Flow         Request đi qua đâu (read path vs write path)
E – Evaluate          Bottleneck, single point of failure, trade-off
D – Deep Dive         Đào 1-2 component quan trọng (theo gợi ý interviewer)
```

### Bước 1 – Requirements (đừng bỏ qua!)
| Functional | Non-functional |
|-----------|----------------|
| Hệ thống **làm gì** (shorten URL, post tweet, gửi message) | Scalability, **latency** (p99), **availability** (9s), consistency, durability, cost |
- Hỏi để **thu hẹp scope**: bao nhiêu user (DAU)? read:write ratio? real-time hay eventual ok? region? data retention?
- Chốt giả định ra giấy (interviewer điều chỉnh) → tránh thiết kế sai hướng.

---

## How – Capacity Estimation (back-of-envelope)

### Quy trình chuẩn
```
1. Traffic:   DAU → requests/user/day → QPS trung bình → QPS đỉnh (×2–10)
2. Storage:   records/day × bytes/record × retention × replication factor
3. Bandwidth: QPS × payload size (in & out)
4. Memory:    working set cache (thường 20% dữ liệu nóng – quy tắc 80/20)
5. Servers:   QPS_đỉnh / (capacity 1 server)
```

### Công thức tiện dùng
```
QPS trung bình = số request/ngày ÷ 86,400 (≈ 100,000 giây/ngày làm tròn)
QPS đỉnh       = QPS trung bình × peak factor (2–10, tùy burstiness)
1 ngày ≈ 86,400s ≈ 10^5 s   (mẹo: chia cho 100,000)
```

### Worked example – Twitter-like (đọc kỹ cách trình bày)
```
Giả định: 200M DAU, mỗi user đọc 50 timeline/ngày, post 2 tweet/ngày, tweet 300 bytes
Read QPS  = 200M × 50 / 86400 ≈ 115,000 QPS (trung bình) → đỉnh ~230K
Write QPS = 200M × 2  / 86400 ≈ 4,600 QPS  → đỉnh ~10K       (read:write ≈ 25:1 → read-heavy → cache nặng)
Storage/ngày = 200M × 2 × 300B = 120 GB/ngày → ×5 năm ×3 (replication) ≈ 650 TB
Bandwidth in = 10K × 300B ≈ 3 MB/s; out = 230K × (50 tweet × 300B)... → CDN/cache giảm tải
Cache (20% nóng) = 120GB × 0.2 ≈ 24GB/ngày hot set → cụm Redis
```
> Mẹo: làm tròn mạnh (200M ≈ 2×10^8), nói rõ giả định, kết luận **ý nghĩa kiến trúc** (read-heavy → cache + read replica; 650TB → sharding).

### Bảng đơn vị nhanh
| Powers of 2 | ≈ | | Data |
|-------------|---|--|------|
| 2^10 | ~1 nghìn (KB) | | char ASCII = 1 byte |
| 2^20 | ~1 triệu (MB) | | UUID = 16 bytes |
| 2^30 | ~1 tỷ (GB) | | timestamp = 8 bytes |
| 2^40 | ~1 nghìn tỷ (TB) | | tweet ~300 bytes |

---

## How – Latency Numbers & Percentiles

### Latency numbers (mọi engineer nên nhớ — dùng để ước lượng)
| Thao tác | Thời gian | Bội số so với L1 |
|----------|-----------|------------------|
| L1 cache | 0.5 ns | 1× |
| Branch mispredict | 5 ns | |
| L2 cache | 7 ns | 14× |
| Mutex lock/unlock | 25 ns | |
| RAM access | 100 ns | 200× |
| Compress 1KB | 3 μs | |
| SSD random read | 16–100 μs | |
| Đọc 1MB tuần tự (RAM) | 3 μs | |
| Đọc 1MB tuần tự (SSD) | 50–100 μs | |
| Round trip same DC | 0.5 ms | |
| Đọc 1MB (network 1Gbps) | 10 ms | |
| Disk seek (HDD) | 10 ms | |
| RTT cross-region (US↔EU) | 30–150 ms | |
> Insight: RAM nhanh hơn SSD ~1000×, SSD nhanh hơn HDD ~100×; cross-region RTT giết latency → CDN/edge/multi-region.

### Percentiles & Tail Latency
```
Đừng dùng AVERAGE (trung bình che giấu tail).
p50 (median): 50% request nhanh hơn  |  p99: 1% chậm nhất  |  p999: 0.1% chậm nhất
SLA thường định nghĩa theo p99/p999, không phải avg.
```
- **Tail amplification**: 1 request fan-out tới 100 service; mỗi service p99=10ms → xác suất ≥1 service chậm rất cao → **request p99 ≈ tệ hơn nhiều**. Càng nhiều fan-out, tail càng tệ → cần hedged requests, timeout, giảm fan-out.
- Nguồn tail: GC pause, queueing, cache miss, contention, slow disk, network retransmit.

---

## How – High-level Design → Deep Dive → Bottleneck

```
Client → DNS → CDN → Load Balancer → API Gateway → Services → Cache → DB
                                                       ↓
                                                  Message Queue → Workers
```
### Quy trình từ high-level đến deep-dive
1. Vẽ box & arrow (read path vs write path tách rõ).
2. Định nghĩa API chính + data model + sharding key.
3. **Evaluate**: chỉ ra bottleneck & SPOF từng tầng.
4. **Deep dive** component interviewer quan tâm (thường: DB scaling, cache, hot key, consistency).

### Mở rộng từng tầng (scaling each layer)
| Tầng | Bottleneck | Cách giải |
|------|-----------|-----------|
| App | CPU/stateless | Horizontal scale + LB (xem [scalability.md](scalability.md), [load_balancing.md](load_balancing.md)) |
| DB read | Read QPS | Read replica + cache (xem [caching.md](caching.md)) |
| DB write | Write QPS/size | Sharding (xem [databases_design.md](databases_design.md)) |
| Hot key | 1 key chiếm tải | Replicate hot key, local cache, request coalescing |
| Cross-service | Đồng bộ chậm | Async + message queue (xem [../advanced/event_driven_architecture.md](../advanced/event_driven_architecture.md)) |

---

## Trade-offs & Communication

### Cách trình bày trade-off (điểm cộng lớn)
"Tôi chọn X **vì** [yêu cầu]; đánh đổi là [nhược điểm]; nếu [điều kiện khác] tôi sẽ chọn Y." — luôn gắn lựa chọn với requirement, nêu rõ cái mất.

### Common mistakes
- Nhảy vào vẽ ngay, bỏ qua requirements/estimation.
- Over-engineering (microservices/Kafka cho bài 1000 user).
- Không nói giả định; im lặng (interviewer cần nghe tư duy).
- Quên SPOF, không nhắc consistency/availability trade-off (CAP).
- Không ước lượng → không biết cần sharding hay không.

### Trade-offs của chính framework
- (+) Có cấu trúc, không bỏ sót, dễ giao tiếp, ước lượng định hướng kiến trúc.
- (−) Máy móc theo bước → cứng nhắc; cần linh hoạt theo gợi ý interviewer (đào sâu cái họ muốn).

---

## Ghi chú
**Sub-topic liên quan:**
- [../system_design_knowledge.md](../system_design_knowledge.md) – RESHADED, latency table tổng quan
- [scalability.md](scalability.md), [load_balancing.md](load_balancing.md), [caching.md](caching.md), [databases_design.md](databases_design.md) – scaling từng tầng
- [../case_studies/foundational_designs.md](../case_studies/foundational_designs.md), [../case_studies/realtime_scale_designs.md](../case_studies/realtime_scale_designs.md) – áp dụng framework vào bài cụ thể
- **Keywords:** functional vs non-functional, peak factor, 80/20 hot data, p99/p999, tail latency amplification, hedged request, SPOF, read:write ratio, sharding key, RESHADED, working set.

*Cập nhật lần cuối: 2026-06-11*
