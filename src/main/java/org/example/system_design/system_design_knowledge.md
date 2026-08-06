# System Design – Tổng hợp kiến thức

> 📖 Tra cứu nhanh: [System Design Glossary](glossary.md) · Mục lục đầy đủ: [roadmap.md](roadmap.md)

---

## 1. System Design là gì

System Design là quá trình quyết định **kiến trúc, thành phần, giao diện và mô hình dữ liệu** của một hệ thống để thỏa mãn một tập yêu cầu — trong đó phần khó không phải "làm được" mà là **chọn đúng đánh đổi**.

Khác biệt cốt lõi so với coding:

| | Coding | System Design |
|---|---|---|
| Câu hỏi | Làm sao cho đúng? | Xây cái gì, cho bao nhiêu người, đánh đổi gì? |
| Có đáp án đúng duy nhất? | Thường có | Không |
| Kiểm chứng bằng | Test | Ước lượng, benchmark, và thực tế production |
| Sai thì | Sửa được nhanh | Có thể phải viết lại (đặc biệt tầng dữ liệu) |

Điều đó dẫn tới nguyên tắc trung tâm của toàn bộ tài liệu này: **mọi lựa chọn phải gắn với một yêu cầu cụ thể và nêu rõ cái mất**. "Dùng Kafka vì nó tốt" không phải một quyết định thiết kế; "dùng Kafka vì cần tách producer/consumer và chịu đột biến 10×, đổi lấy eventual consistency và một hệ thống phải vận hành" thì có.

---

## 2. Chín chiều đánh giá một hệ thống

```text
┌─────────────────────────────────────────────────────────┐
│  Scalability  ──  Availability  ──  Performance         │
│       │                 │                 │             │
│  Reliability  ──  Maintainability  ──  Security         │
│       │                 │                 │             │
│  Cost         ──  Observability  ──  Consistency        │
└─────────────────────────────────────────────────────────┘
```

Chín chiều này **xung đột với nhau**, và đó là lý do system design là bài toán đánh đổi:

| Muốn tăng | Thường phải giảm |
|---|---|
| Consistency | Latency và availability (PACELC) |
| Availability | Cost (dự phòng ×N) |
| Scalability | Maintainability (hệ phân tán phức tạp hơn) |
| Security | Performance và trải nghiệm (mã hóa, xác thực thêm hop) |
| Cost hiệu quả | Headroom cho đột biến |

---

## 3. Bản đồ 21 chủ đề

| Nhóm | Chủ đề | Trả lời câu hỏi |
|---|---|---|
| **Phương pháp** | [interview_framework_estimation](fundamentals/interview_framework_estimation.md) | Bắt đầu từ đâu? Quy mô thật là bao nhiêu? |
| **Mở rộng** | [scalability](fundamentals/scalability.md) | Tải tăng 10× thì làm gì? Cái gì sẽ đụng trần trước? |
| | [load_balancing](fundamentals/load_balancing.md) | Chia tải và loại node lỗi thế nào? |
| | [caching](fundamentals/caching.md) | Giảm tải tầng dưới; và cache hỏng thế nào? |
| | [databases_design](fundamentals/databases_design.md) | Chọn store nào? Khi nào shard? |
| **Nền tảng sâu** | [storage_retrieval](fundamentals/storage_retrieval.md) | Vì sao các database có đặc tính khác nhau? |
| | [distributed_systems_theory](fundamentals/distributed_systems_theory.md) | Nhiều node thì đảm bảo được gì? |
| | [networking_protocols](fundamentals/networking_protocols.md) | Các thành phần nói chuyện với nhau thế nào? |
| **Độ tin cậy** | [availability_reliability](fundamentals/availability_reliability.md) | Cái gì có thể sai, và khi sai thì sao? |
| **Kiến trúc** | [api_design](advanced/api_design.md) | Hợp đồng giữa các bên là gì? |
| | [microservices](advanced/microservices.md) | Chia service theo ranh giới nào? |
| | [event_driven_architecture](advanced/event_driven_architecture.md) | Khi nào bất đồng bộ? |
| | [distributed_transactions](advanced/distributed_transactions.md) | Transaction vượt ranh giới thì làm sao? |
| **SaaS** | [multi_tenancy](saas/multi_tenancy.md) | Nhiều khách hàng trên một hệ thống thế nào? |
| | [rate_limiting](saas/rate_limiting.md) | Bảo vệ khỏi lạm dụng ra sao? |
| | [feature_flags](saas/feature_flags.md) | Ra tính năng an toàn thế nào? |
| | [billing_metering](saas/billing_metering.md) | Đo và tính tiền ra sao? |
| | [observability_saas](saas/observability_saas.md) | Biết hệ thống đang thế nào bằng cách nào? |
| **Áp dụng** | [foundational_designs](case_studies/foundational_designs.md) | URL shortener, ID, rate limiter |
| | [realtime_scale_designs](case_studies/realtime_scale_designs.md) | Feed, chat, geo |
| | [platform_designs](case_studies/platform_designs.md) | Object storage, typeahead, payment, notification |

---

## 4. Mười lăm điều quan trọng nhất

Nếu chỉ nhớ được một danh sách, đây là danh sách đó — mỗi điều kèm nơi đọc chi tiết.

1. **Ước lượng trước khi thiết kế.** Không biết QPS và dung lượng thì không biết có cần cache hay sharding. → [interview_framework_estimation](fundamentals/interview_framework_estimation.md) mục 3
2. **Kiệt trục X (nhân bản) trước khi sang Y (chia service) hoặc Z (chia dữ liệu).** → [scalability](fundamentals/scalability.md) mục 5
3. **Access pattern trước, công nghệ sau.** → [databases_design](fundamentals/databases_design.md) mục 1
4. **Sharding là quyết định gần như không thể lùi** — loại trừ index, vertical, replica, cache, functional partitioning trước. → [databases_design](fundamentals/databases_design.md) mục 4.1
5. **Mọi lời gọi ngoài phải có timeout, và deadline phải được truyền xuống.** → [availability_reliability](fundamentals/availability_reliability.md) mục 5.1
6. **Mọi retry phải có jitter, chỉ ở một tầng, và có budget.** → [availability_reliability](fundamentals/availability_reliability.md) mục 5.2
7. **Mọi cache key phải có TTL**, kể cả khi đã có invalidation chủ động. → [caching](fundamentals/caching.md) mục 5.2
8. **Cache có ba chế độ hỏng** (stampede, penetration, avalanche) — phải xử lý cả ba trước khi lên production. → [caching](fundamentals/caching.md) mục 4
9. **Liveness không được phụ thuộc dependency ngoài** — nếu không, một sự cố database thành sự cố toàn hệ thống. → [load_balancing](fundamentals/load_balancing.md) mục 4.2
10. **Node chậm nguy hiểm hơn node chết** — vì nó vẫn nhận traffic và làm cạn thread pool của caller. → [availability_reliability](fundamentals/availability_reliability.md) mục 4
11. **Exactly-once luôn có phạm vi** — transaction của broker không tự bao phủ email, HTTP hay payment; hãy thiết kế side effect idempotent. → [event_driven_architecture](advanced/event_driven_architecture.md) mục 6–7
12. **Cách xử lý xung đột tốt nhất là thiết kế để không có xung đột** (single-writer theo khóa). → [distributed_systems_theory](fundamentals/distributed_systems_theory.md) mục 5
13. **Distributed lock chỉ đúng khi resource kiểm tra fencing token.** → [distributed_systems_theory](fundamentals/distributed_systems_theory.md) mục 7.1
14. **Từ chối 10% request gọn gàng tốt hơn để 100% timeout.** → [availability_reliability](fundamentals/availability_reliability.md) mục 5.5
15. **Availability bảo vệ khỏi mất hạ tầng; backup bảo vệ khỏi mất dữ liệu — cần cả hai.** → [availability_reliability](fundamentals/availability_reliability.md) mục 1

---

## 5. Bảng tra: triệu chứng → chương cần đọc

| Triệu chứng | Nghi phạm đầu tiên | Đọc |
|---|---|---|
| Thêm pod mà latency tệ hơn | Nghẽn ở tầng dưới (DB/cache); coordination cost | [scalability](fundamentals/scalability.md) mục 1.1, 4.2 |
| Một dependency chậm làm sập cả service | Thiếu timeout/bulkhead | [availability_reliability](fundamentals/availability_reliability.md) mục 5 |
| Deploy nào cũng có lỗi 502 vài giây | Draining và xử lý SIGTERM sai | [load_balancing](fundamentals/load_balancing.md) mục 7.1 |
| Pod bị restart hàng loạt khi DB chậm | Liveness probe kiểm tra dependency ngoài | [load_balancing](fundamentals/load_balancing.md) mục 4.2 |
| gRPC: thêm backend mà tải không đều | L4 LB cân bằng theo kết nối | [load_balancing](fundamentals/load_balancing.md) mục 2.1 |
| DB sập ngay sau khi cache restart | Cache avalanche; cache là dependency bắt buộc | [caching](fundamentals/caching.md) mục 4.3 |
| Dữ liệu sai mà restart thì hết | Cache key không có TTL + bỏ sót đường ghi | [caching](fundamentals/caching.md) mục 5.2 |
| Một key chiếm phần lớn tải | Hot key; consistent hashing không giúp | [caching](fundamentals/caching.md) mục 6 |
| User cập nhật rồi tải lại thấy dữ liệu cũ | Replication lag, thiếu read-your-writes | [databases_design](fundamentals/databases_design.md) mục 3.3 |
| Auto-scaling app làm DB sập | `maxReplicas × poolSize` vượt giới hạn kết nối | [databases_design](fundamentals/databases_design.md) mục 6 |
| Báo cáo làm chậm cả hệ thống | OLAP chạy trên DB OLTP | [databases_design](fundamentals/databases_design.md) mục 8 |
| Ghi nhanh nhưng p99 đọc thỉnh thoảng vọt | LSM compaction | [storage_retrieval](fundamentals/storage_retrieval.md) mục 4 |
| Index phình, ghi chậm dần | Primary key random (UUID v4) → page split | [storage_retrieval](fundamentals/storage_retrieval.md) mục 3.1 |
| Service cũ lỗi khi service mới deploy | Schema evolution không tương thích | [storage_retrieval](fundamentals/storage_retrieval.md) mục 7 |
| Cụm 2 node không failover được | Không có quorum, không phân biệt được chết vs mất mạng | [distributed_systems_theory](fundamentals/distributed_systems_theory.md) mục 3.3 |
| Hai worker cùng xử lý một việc | Lock không có fencing token | [distributed_systems_theory](fundamentals/distributed_systems_theory.md) mục 7 |
| Dữ liệu biến mất sau khi hai node cùng ghi | LWW hòa giải xung đột | [distributed_systems_theory](fundamentals/distributed_systems_theory.md) mục 5 |
| p99 tệ dù mọi service đều nhanh | Tail latency amplification do fan-out | [interview_framework_estimation](fundamentals/interview_framework_estimation.md) mục 4.3 |
| API nội bộ chậm dù server rảnh | Không có connection pool/keep-alive | [networking_protocols](fundamentals/networking_protocols.md) mục 2.1 |
| Failover DNS xong mà app Java vẫn gọi IP cũ | JVM DNS cache | [networking_protocols](fundamentals/networking_protocols.md) mục 6.1 |
| WebSocket khó deploy, mất kết nối hàng loạt | Bản chất stateful, thiếu drain và jitter | [networking_protocols](fundamentals/networking_protocols.md) mục 5.2 |
| Deploy một feature phải release hàng loạt service | Distributed monolith, boundary hoặc contract sai | [microservices](advanced/microservices.md) mục 3, 11 |
| Consumer xử lý trùng hoặc lag tăng mãi | Thiếu idempotency/công suất; queue chỉ che nghẽn | [event_driven_architecture](advanced/event_driven_architecture.md) mục 7, 9 |
| DB có order nhưng broker thiếu event | Dual-write không atomic | [event_driven_architecture](advanced/event_driven_architecture.md) mục 11 |
| Payment timeout, không biết đã trừ tiền chưa | Unknown outcome; retry mù | [distributed_transactions](advanced/distributed_transactions.md) mục 3, 20 |
| Hai client cùng sửa và ghi đè dữ liệu | Thiếu optimistic concurrency/ETag | [api_design](advanced/api_design.md) mục 9 |
| API tạo duplicate sau khi client retry | Mutation không có idempotency contract | [api_design](advanced/api_design.md) mục 8 |
| User tenant A đọc được dữ liệu tenant B | Tenant context/key/query không được scope end-to-end | [multi_tenancy](saas/multi_tenancy.md) mục 6–15 |
| Tenant lớn làm tenant nhỏ chậm | Noisy neighbor, thiếu fair rate/concurrency/queue | [multi_tenancy](saas/multi_tenancy.md) mục 16; [rate_limiting](saas/rate_limiting.md) mục 10–13, 21 |
| Scale thêm gateway làm tổng quota tăng | Đang dùng local limit nhưng tưởng global | [rate_limiting](saas/rate_limiting.md) mục 13 |
| Invoice tính trùng usage sau khi consumer retry | Usage event thiếu idempotency/immutable ledger | [billing_metering](saas/billing_metering.md) mục 5–8 |
| Hóa đơn cũ đổi khi cập nhật bảng giá | Catalog không version theo effective time | [billing_metering](saas/billing_metering.md) mục 11–15 |
| User lúc thấy v1, lúc thấy v2 | Percentage rollout dùng random/session key | [feature_flags](saas/feature_flags.md) mục 9 |
| Flag service lỗi kéo sập mọi request | Remote evaluation trên hot path, thiếu last-known-good | [feature_flags](saas/feature_flags.md) mục 5, 12–13 |
| Thanh toán bị trừ hai lần | Thiếu idempotency key đúng cách | [platform_designs](case_studies/platform_designs.md) mục 3.2 |
| Người dùng nhận thông báo trùng | Thiếu dedup ở một trong ba tầng | [platform_designs](case_studies/platform_designs.md) mục 4.4 |
| OTP đến sau 40 phút | Không tách hàng đợi transactional và campaign | [platform_designs](case_studies/platform_designs.md) mục 4.4 |

---

## 6. Bốn anti-pattern phổ biến nhất

| Anti-pattern | Biểu hiện | Vì sao xảy ra | Thay bằng |
|---|---|---|---|
| **Over-engineering** | Microservices + Kafka + K8s cho 5.000 user | Sao chép kiến trúc của công ty lớn mà không có bài toán của họ | Bắt đầu đơn giản; viết ra **dấu hiệu** để biết khi nào cần phức tạp hơn |
| **Sharding sớm** | Shard vì "sẽ cần" | Sợ phải làm lại sau | Vertical + replica + cache; ghi lại ngưỡng sẽ shard |
| **Đồng bộ mọi thứ** | Mọi service gọi nhau bằng RPC đồng bộ | Dễ suy luận hơn lúc viết | Việc không cần trả lời ngay → event; giảm phép nhân availability |
| **Cache như phương án cứu cánh** | Thêm cache khi chậm, không xử lý ba chế độ hỏng | Cache cho kết quả nhanh và rõ | Sửa gốc (index/query) trước; nếu cache thì làm đủ mục 4 của [caching](fundamentals/caching.md) |

Về over-engineering, cách nói vừa thể hiện năng lực vừa thể hiện chừng mực: *"Ở quy mô này, một PostgreSQL với read replica và Redis là đủ. Tôi sẽ tách service khi có 3 team cần deploy độc lập, và shard khi dung lượng vượt ~2TB hoặc write QPS vượt ~5K."* — nó cho thấy bạn biết cả kiến trúc lớn và biết khi nào chưa cần nó.

---

## 7. Kiến trúc tham chiếu theo quy mô

| Quy mô | Kiến trúc | Việc đáng làm tiếp |
|---|---|---|
| 0–1K user | Một máy, một DB | Backup có kiểm chứng, monitoring cơ bản, CI/CD |
| 1K–100K | LB + vài app node + read replica + Redis + CDN cho static | Đặt SLO, tách analytics khỏi OLTP, alert cơ bản |
| 100K–1M | Cache nhiều tầng, queue cho việc nền, multi-AZ | Tách service theo domain **nếu tổ chức cần**, không vì hiệu năng |
| 1M–100M | Nhiều service, Kafka, sharding, multi-AZ đầy đủ | Cell-based, chuẩn bị multi-region cho DR |
| 100M+ | Cell-based, phân phối toàn cầu, hạ tầng riêng | Tối ưu chi phí trở thành ưu tiên hàng đầu |

Bảng này để tránh over-engineering, không phải công thức. Rất nhiều hệ thống 100K user chạy tốt trên cột "1K–100K" nếu dữ liệu và truy vấn được thiết kế tử tế — xem ví dụ Stack Overflow ở [scalability](fundamentals/scalability.md) mục 10.

---

## 8. Ba nguyên tắc phương pháp

1. **Đo trước, sửa sau.** Ghi lại con số trước và sau mỗi thay đổi. "Nhanh hơn" không phải kết luận kiểm chứng được.
2. **Sửa một thứ mỗi lần.** Bật ba thứ cùng lúc rồi thấy hiệu năng đổi thì không biết cái nào có tác dụng.
3. **Mọi biện pháp tạm phải có ngày review.** Force plan, hint, fallback cứng, feature flag "tạm thời" — nếu không ai biết vì sao chúng ở đó thì sau hai năm không ai dám bỏ.

---

## 9. Ghi chú

Thứ tự học và lối đi theo vai: xem [roadmap.md](roadmap.md) mục Learning path.

**Trạng thái chuẩn hóa (2026-07-31)**: đã hoàn thành 20/21 chủ đề — `fundamentals/` (9/9), `advanced/` (4/4), `case_studies/` (3/3) và `saas/` (4/5). Còn `observability_saas.md`; bài này được giữ lại để tôn trọng ưu tiên tạm giảm các chủ đề gần Prometheus/Grafana.

Từ khóa mở rộng cần đào tiếp: cell-based routing, multi-region data residency, capacity planning và FinOps, platform engineering, chaos engineering có kỷ luật, security architecture (zero trust, secret management, authZ ở quy mô), data mesh, batch vs stream processing.

---

*Cập nhật lần cuối: 2026-07-31*
