---
title: "Database Design – Chọn và mở rộng tầng dữ liệu"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Database Design – Chọn và mở rộng tầng dữ liệu

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Caching](caching.md). Đọc tiếp: [Storage & Retrieval](storage_retrieval.md), [Distributed Systems Theory](distributed_systems_theory.md).

---

## 1. Đây là quyết định khó lùi nhất

Tầng dữ liệu khác mọi tầng khác ở một điểm: **đổi nó rất đắt**. Thay load balancer là chuyện một buổi chiều; thay database hoặc đổi shard key của một hệ thống đang chạy là dự án nhiều tháng.

Vì vậy thứ tự suy nghĩ đúng là **access pattern trước, công nghệ sau**:

```text
1. Dữ liệu được ĐỌC như thế nào?  (theo key? theo dải? full-text? aggregate? graph traversal?)
2. Dữ liệu được GHI như thế nào?  (append? update tại chỗ? tần suất? kích thước?)
3. Cần đảm bảo gì?               (transaction nhiều bản ghi? đọc thấy ghi ngay? mất được không?)
4. Quy mô thật là bao nhiêu?      (ước lượng — xem interview_framework_estimation.md)
5. → CHỌN công nghệ khớp với 1–4
```

Làm ngược lại ("dùng MongoDB vì linh hoạt", "dùng Cassandra vì scale") là nguồn của phần lớn hệ thống dữ liệu phải viết lại.

---

## 2. SQL vs NoSQL – câu hỏi đúng là gì

Sự phân đôi "SQL vs NoSQL" không còn hữu ích lắm: PostgreSQL có JSONB và chạy tốt ở quy mô lớn; MongoDB có transaction nhiều document; nhiều hệ NewSQL có cả hai. Câu hỏi hữu ích hơn:

| Câu hỏi | Nếu "có" thì nghiêng về |
|---|---|
| Cần transaction nhiều bản ghi, nhiều bảng? | Quan hệ (hoặc NewSQL) |
| Truy vấn ad-hoc, chưa biết trước? | Quan hệ (SQL linh hoạt truy vấn) |
| Access pattern **cố định và biết trước**, chỉ theo key? | Key-value / wide-column |
| Ghi rất nhiều, chủ yếu append theo thời gian? | Wide-column / time-series (LSM) |
| Cần join nhiều bảng thường xuyên? | Quan hệ |
| Truy vấn kiểu "đường đi trong đồ thị nhiều bậc"? | Graph |
| Full-text search, ranking, fuzzy? | Search engine (không phải database chính) |
| Aggregate trên hàng tỉ dòng? | Columnar/OLAP |

### 2.1 Bốn họ NoSQL

| Họ | Mô hình | Ví dụ | Mạnh ở | Kém ở |
|---|---|---|---|---|
| **Key-value** | key → blob | Redis, DynamoDB | Lookup theo key cực nhanh | Truy vấn theo thuộc tính |
| **Document** | JSON lồng nhau | MongoDB, Firestore | Aggregate tự nhiên, schema linh hoạt | Join, transaction xuyên document |
| **Wide-column** | (partition key, clustering key) → cột | Cassandra, HBase, ScyllaDB | Ghi rất nhiều, dải theo thời gian | Truy vấn không theo partition key |
| **Graph** | node + edge | Neo4j, Neptune | Traversal nhiều bậc | Aggregate lớn, ghi khối lượng lớn |

Điểm quan trọng về wide-column mà hay bị bỏ qua: **mô hình dữ liệu Cassandra được thiết kế từ truy vấn, không từ thực thể**. Bạn viết một bảng cho mỗi query pattern và chấp nhận trùng lặp dữ liệu. Ai mang tư duy chuẩn hóa quan hệ vào Cassandra sẽ tạo ra thiết kế không chạy được ở quy mô.

### 2.2 Polyglot persistence và giá của nó

Dùng đúng công cụ cho từng việc là lời khuyên đúng, nhưng mỗi datastore thêm vào là:

- một hệ thống phải backup, monitor, patch, và có người biết vận hành;
- một mô hình lỗi mới;
- một bài toán nhất quán mới (dữ liệu ở A và B lệch nhau thì sao?).

Quy tắc thực dụng: **PostgreSQL cho tới khi có lý do đo được để thêm cái khác**. PostgreSQL làm được quan hệ, JSON, full-text ở mức khá, geo, và time-series (TimescaleDB) — đủ cho phần lớn hệ thống, với một hệ vận hành duy nhất.

---

## 3. Replication

### 3.1 Ba mô hình

| Mô hình | Cơ chế | Vấn đề chính |
|---|---|---|
| **Single-leader** | Ghi vào leader, replicate sang follower | Replication lag; failover cần bầu leader mới |
| **Multi-leader** | Nhiều node nhận ghi, đồng bộ với nhau | **Xung đột ghi** — phần khó nhất |
| **Leaderless (quorum)** | Client ghi vào N replica, chờ W ack | Cần hòa giải xung đột; đọc phải quorum |

Single-leader là mặc định đúng cho phần lớn hệ thống. Multi-leader chỉ hợp lý khi có yêu cầu rõ (multi-region ghi được, offline-first) và khi đã có chiến lược hòa giải — xem [distributed_systems_theory.md](distributed_systems_theory.md) mục 4.

### 3.2 Đồng bộ vs bất đồng bộ

```text
Đồng bộ:      client → leader → chờ follower ack → trả OK
              RPO = 0, nhưng độ trễ ghi = độ trễ mạng tới follower chậm nhất
              Nếu follower chết → leader phải chọn: dừng nhận ghi, hay bỏ đảm bảo?

Bất đồng bộ:  client → leader → trả OK ngay → replicate sau
              Ghi nhanh, nhưng leader chết = mất phần chưa replicate

Semi-sync:    chờ ÍT NHẤT MỘT follower ack (thỏa hiệp phổ biến nhất)
```

### 3.3 Replication lag – ba vấn đề và cách chữa

Đây là phần gây bug thật nhiều nhất khi thêm read replica.

| Vấn đề | Biểu hiện | Cách chữa |
|---|---|---|
| **Read-your-writes** | User cập nhật profile, tải lại thấy dữ liệu cũ | Đọc từ leader trong N giây sau khi ghi; hoặc đọc từ leader cho dữ liệu của chính user |
| **Monotonic reads** | Tải lại trang thấy dữ liệu **lùi về quá khứ** (do đọc từ hai replica khác nhau) | Ghim một user vào một replica (hash user id) |
| **Consistent prefix reads** | Thấy câu trả lời trước câu hỏi | Ghi các sự kiện có quan hệ nhân quả vào cùng partition |

```java
// Mẫu read-your-writes thực dụng: đánh dấu thời điểm ghi trong session
void updateProfile(long userId, Profile p) {
    writeRepo.save(p);
    session.setAttribute("lastWriteAt:" + userId, Instant.now());
}

Profile getProfile(long userId) {
    Instant lastWrite = (Instant) session.getAttribute("lastWriteAt:" + userId);
    boolean recentWrite = lastWrite != null &&
                          Duration.between(lastWrite, Instant.now()).getSeconds() < 10;
    return recentWrite ? leaderRepo.find(userId)     // đọc leader
                       : replicaRepo.find(userId);   // đọc replica
}
```

Cách này đơn giản và hiệu quả hơn nhiều so với chờ replication hoặc dùng LSN/GTID — và nó bao đúng ca gây khiếu nại của người dùng.

### 3.4 Giám sát lag

```sql
-- PostgreSQL: lag tính theo thời gian, không chỉ theo byte
SELECT client_addr, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;
```

Lag tính theo byte gây hiểu sai: 10MB lag trên hệ ghi ít là hàng phút, trên hệ ghi nhiều là mili giây. **Luôn alert theo thời gian**, không theo byte.

---

## 4. Sharding

### 4.1 Trước khi shard, hãy loại trừ mọi lựa chọn khác

Sharding là quyết định gần như không thể lùi. Trước nó, theo thứ tự:

```text
1. Index và query đã tối ưu?          (thường thu được nhiều nhất, rẻ nhất)
2. Vertical scaling đã hết đường?     (máy hiện nay rất lớn)
3. Read replica đã dùng?              (nếu nghẽn là đọc)
4. Cache đã dùng đúng?                (xem caching.md)
5. Dữ liệu lạnh đã tách/archive?      (partitioning trong một node)
6. Đã tách theo chức năng (functional partitioning)? — mỗi domain một database
7. → chỉ khi đó mới sharding theo dữ liệu
```

Bước 6 đáng nhấn: tách "database orders" khỏi "database analytics" đơn giản hơn nhiều so với shard bảng orders, và thường đủ.

### 4.2 Bốn chiến lược

| Chiến lược | Cơ chế | Mạnh | Yếu |
|---|---|---|---|
| **Range** | shard theo khoảng giá trị | Range query hiệu quả | Hotspot (shard mới nhất nhận hết ghi) |
| **Hash** | `hash(key) % N` | Phân phối đều | Range query kém; **resharding đau** (đổi N là remap gần hết) |
| **Consistent hashing** | Hash lên ring, virtual node | Thêm/bớt shard chỉ dịch ~1/N | Phức tạp hơn |
| **Directory** | Bảng tra cứu key → shard | Linh hoạt nhất, migrate từng key được | Lookup là bottleneck và SPOF; phải cache |

Trong thực tế, cách phổ biến nhất là biến thể **hash slot cố định**: chia thành số slot lớn cố định (Redis Cluster: 16384) rồi map slot → node. Thêm node = chuyển một số slot, không đổi hàm băm. Điều này có ưu điểm của consistent hashing với mô hình đơn giản hơn.

### 4.3 Chọn shard key – quyết định quan trọng nhất

| Tiêu chí | Vì sao |
|---|---|
| **Cardinality cao** | Ít giá trị phân biệt = không chia đều được |
| **Phân bố đều** | Tránh hotspot |
| **Có trong hầu hết truy vấn** | Nếu không, mọi query phải scatter-gather tới mọi shard |
| **Không thay đổi** | Đổi shard key = di chuyển bản ghi giữa shard |
| **Gom được dữ liệu liên quan vào một shard** | Để tránh cross-shard transaction/join |

Tiêu chí cuối là quan trọng nhất và hay bị bỏ. Với SaaS, `tenant_id` thường là shard key tốt vì gần như mọi truy vấn có nó và dữ liệu của một tenant nằm cùng shard → không có cross-shard query. Với `user_id` trong hệ mạng xã hội thì ngược lại: quan hệ giữa các user vốn dĩ xuyên shard.

Anti-pattern kinh điển: shard theo timestamp hoặc theo id tăng dần → toàn bộ ghi mới dồn vào một shard.

### 4.4 Bốn vấn đề sau khi shard

| Vấn đề | Cách xử lý |
|---|---|
| **Cross-shard join** | Denormalize; hoặc join ở tầng ứng dụng; hoặc duy trì bảng tra cứu nhân bản |
| **Cross-shard transaction** | Tránh bằng thiết kế shard key; nếu buộc phải thì Saga — xem `advanced/distributed_transactions.md` |
| **Resharding** | Consistent hashing/slot; migration theo pha với double-write rồi cutover |
| **Hot shard** | Sub-shard khóa nóng (thêm hậu tố), tách tenant lớn ra shard riêng |
| **Aggregate toàn cục** | Duy trì bảng tổng hợp riêng; hoặc đẩy sang OLAP |

Quy trình resharding không downtime, dạng chuẩn:

```text
1. Thêm shard mới, chưa nhận traffic
2. Bật DOUBLE WRITE: ghi vào shard cũ và shard mới
3. Backfill dữ liệu lịch sử sang shard mới
4. Đối chiếu (row count, checksum theo dải)
5. Chuyển ĐỌC sang shard mới, vẫn double write
6. Quan sát; nếu ổn → ngừng ghi shard cũ
7. Dọn dữ liệu ở shard cũ
```

Mỗi bước có thể lùi được — đó là lý do quy trình có 7 bước thay vì 2.

### 4.5 Sharding trong thực tế

| Hệ thống | Cách làm |
|---|---|
| **Vitess (YouTube)** | Lớp sharding cho MySQL: ứng dụng thấy một database logic, Vitess route tới shard; hỗ trợ resharding trực tuyến |
| **MongoDB** | `mongos` router + config server giữ shard map; chunk tự cân bằng theo balancer |
| **Citus (PostgreSQL)** | Phân tán bảng theo distribution column; coordinator điều phối |
| **Shopify** | Shard theo shop, nhiều shop trên một pod (bin packing) — shard key trùng ranh giới nghiệp vụ |
| **Instagram** | Shard theo user id ngay từ sớm; id chứa luôn shard id → không cần lookup |

Kỹ thuật của Instagram đáng học: **nhúng shard id vào primary key**. Từ id có thể suy ra shard mà không cần bảng tra cứu — loại bỏ hoàn toàn lớp directory và SPOF của nó.

---

## 5. Index – nơi thu được nhiều nhất với ít công nhất

Trước khi bàn sharding hay caching, kiểm tra index. Một index đúng thường cải thiện nhiều hơn cả một tầng cache.

```sql
-- Composite index: thứ tự cột quyết định mọi thứ
CREATE INDEX idx_orders_tenant_created ON orders (tenant_id, created_at DESC);

-- ✓ dùng được đầy đủ
SELECT * FROM orders WHERE tenant_id = 7 AND created_at >= '2026-07-01' ORDER BY created_at DESC;
-- ✓ dùng được prefix
SELECT * FROM orders WHERE tenant_id = 7;
-- ✗ KHÔNG dùng được index này (thiếu cột đầu)
SELECT * FROM orders WHERE created_at >= '2026-07-01';
```

**Leftmost prefix rule**: index `(A, B, C)` phục vụ được truy vấn trên `A`, `(A,B)`, `(A,B,C)` — không phục vụ truy vấn chỉ có `B` hoặc `C`.

Quy tắc thứ tự cột (ESR): **Equality → Sort → Range**. Xem giải thích chi tiết và lý do ở [sqlserver/indexing.md](../../sqlserver/fundamentals/indexing.md) mục 2.1 — nguyên lý giống nhau ở mọi engine dùng B-tree.

| Loại index | Dùng để | Ghi chú |
|---|---|---|
| **Covering** | Trả kết quả không cần đọc bảng | Thêm cột vào index (`INCLUDE`) |
| **Partial/filtered** | Chỉ index tập con | Rất nhỏ; query phải khớp điều kiện |
| **Expression** | Index trên biểu thức | Cho phép `WHERE lower(email) = ?` seek được |
| **GIN/GiST (PostgreSQL)** | JSONB, full-text, geo, array | Ghi chậm hơn B-tree |
| **Hash** | Chỉ equality | Ít dùng; B-tree thường đủ |

Chi phí của index (thường bị bỏ qua khi thêm): mỗi index làm mọi `INSERT` chậm hơn, mọi `UPDATE` chạm cột được index chậm hơn, tốn dung lượng và buffer pool, và làm backup/restore lâu hơn. Vì vậy **kiểm toán index không dùng** là việc nên làm định kỳ.

---

## 6. Connection pooling

```text
Không có pool:  30 app pod × 100 thread = 3.000 kết nối → PostgreSQL sập
Có pool:        30 pod × 10 kết nối     = 300 kết nối    → vẫn quá nhiều với PG
Có pool + PgBouncer transaction mode:   300 → ~40 kết nối thật tới PG  ✓
```

PostgreSQL tạo một process cho mỗi kết nối, nên vài trăm kết nối đã tốn đáng kể RAM và context switch. Đây là lý do PgBouncer gần như bắt buộc cho kiến trúc nhiều pod.

```java
HikariConfig cfg = new HikariConfig();
cfg.setMaximumPoolSize(10);              // per pod; tính tổng với maxReplicas!
cfg.setMinimumIdle(5);
cfg.setConnectionTimeout(5_000);         // chờ lấy kết nối từ pool
cfg.setIdleTimeout(300_000);
cfg.setMaxLifetime(900_000);             // PHẢI nhỏ hơn timeout của firewall/LB
cfg.setLeakDetectionThreshold(20_000);   // cảnh báo khi giữ kết nối quá lâu
cfg.setValidationTimeout(3_000);
```

| PgBouncer mode | Cơ chế | Đánh đổi |
|---|---|---|
| **Session** | Một kết nối client = một kết nối PG suốt session | An toàn nhất, tiết kiệm ít nhất |
| **Transaction** | Kết nối PG chỉ giữ trong transaction | Hiệu quả nhất; **không dùng được** session state (temp table, advisory lock, prepared statement server-side) |
| **Statement** | Mỗi câu lệnh một kết nối | Không hỗ trợ transaction nhiều câu |

Transaction mode là lựa chọn phổ biến cho microservices, nhưng cần kiểm tra ứng dụng không dựa vào session state. Với Hibernate, cần tắt prepared statement caching phía server hoặc dùng chế độ tương thích.

Công thức đặt pool size phải nhớ: **`maxReplicas × maximumPoolSize ≤ giới hạn kết nối của DB`**. Auto-scaling app mà quên công thức này là cách tự gây sự cố ([scalability.md](scalability.md) mục 4.2).

---

## 7. Read replica vs cache – chọn cái nào

| | Read replica | Cache (Redis) |
|---|---|---|
| Độ mới | Lag mili giây–giây | Theo TTL/invalidation |
| Truy vấn | SQL đầy đủ, ad-hoc | Theo key |
| Cần đổi code? | Ít (chỉ routing read/write) | Có (logic cache) |
| Chi phí | Bằng một DB node | RAM rẻ hơn |
| Chịu tải đọc | Cao | Rất cao |
| Phù hợp | Báo cáo, truy vấn phức tạp, giảm tải chung | Key nóng, kết quả tính đắt |

Chúng không loại trừ nhau, và mẫu kết hợp thường dùng:

```text
Key nóng, đọc theo id       → Redis
Truy vấn phức tạp, báo cáo  → read replica
Aggregate trên dữ liệu lớn  → data warehouse / OLAP
Ghi và đọc nhất quán mạnh   → leader
```

---

## 8. OLTP vs OLAP – hai thế giới, đừng trộn

| | OLTP | OLAP |
|---|---|---|
| Mục đích | Giao dịch nghiệp vụ | Phân tích |
| Truy vấn | Nhiều, nhỏ, theo index | Ít, lớn, quét nhiều |
| Dữ liệu chạm mỗi query | Vài bản ghi | Hàng triệu–tỉ |
| Lưu trữ | Theo hàng (row) | Theo cột (columnar) |
| Chuẩn hóa | 3NF | Denormalized, star schema |
| Công nghệ | PostgreSQL, MySQL, SQL Server | ClickHouse, BigQuery, Snowflake, Redshift |

Sai lầm tốn kém nhất ở tầng dữ liệu: **chạy báo cáo phân tích trên database OLTP production**. Một query quét toàn bảng để tính doanh thu tháng sẽ đẩy tập nóng ra khỏi buffer pool và làm chậm mọi giao dịch. Cách chữa, theo thứ tự chi phí:

```text
1. Read replica riêng cho báo cáo (rẻ nhất, hiệu quả ngay)
2. Bảng tổng hợp cập nhật định kỳ (materialized view)
3. Columnar index/engine trong cùng DB (columnstore của SQL Server, Citus columnar)
4. Data warehouse riêng + pipeline ETL/CDC
```

Chi tiết engine columnar: [clickhouse package](../../clickhouse/roadmap.md). Chi tiết CDC để đưa dữ liệu sang: [sqlserver/data_movement.md](../../sqlserver/integration/data_movement.md).

---

## 9. Migration schema không downtime

Đây là kỹ năng vận hành dữ liệu quan trọng nhất mà ít tài liệu system design đề cập.

**Expand–contract (parallel change)** — mọi thay đổi schema đều nên theo mẫu này:

```text
Đổi tên cột user_name → full_name, không downtime:

Expand:
  1. Thêm cột full_name (nullable) — an toàn, không phá code cũ
  2. Deploy code GHI vào cả hai cột, ĐỌC từ user_name
  3. Backfill full_name theo lô cho dữ liệu cũ
  4. Deploy code ĐỌC từ full_name (vẫn ghi cả hai)

Contract:
  5. Deploy code chỉ dùng full_name
  6. Xóa cột user_name
```

Nguyên tắc bất biến: **mỗi bước phải tương thích với phiên bản code trước và sau nó**, để rollback luôn khả thi. Điều này bắt buộc vì trong lúc rolling deploy, hai phiên bản code chạy đồng thời trên cùng schema.

Các thao tác cần đặc biệt cẩn thận:

| Thao tác | Rủi ro | Cách an toàn |
|---|---|---|
| Thêm cột `NOT NULL` có default | Rewrite cả bảng (tùy engine/version) | Thêm nullable → backfill → set NOT NULL |
| Thêm index trên bảng lớn | Lock ghi | `CREATE INDEX CONCURRENTLY` (PG), `ONLINE = ON` (SQL Server) |
| Xóa cột | Code cũ vẫn `SELECT *` | Ngừng dùng ở code trước, xóa sau ít nhất một chu kỳ deploy |
| Đổi kiểu dữ liệu | Rewrite bảng, có thể mất dữ liệu | Cột mới + backfill + cutover |
| Backfill hàng loạt | Lock lâu, log phình | Chia lô nhỏ, có nghỉ giữa lô |

---

## 10. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Một PostgreSQL cho mọi thứ | Vận hành đơn giản, transaction đầy đủ | Không tối ưu cho mọi workload | Mặc định; cho tới khi đo được giới hạn |
| Polyglot persistence | Đúng công cụ cho từng việc | ×N chi phí vận hành và bài toán nhất quán | Khi có workload thật khác biệt rõ |
| Read replica | Giảm tải đọc, ít đổi code | Replication lag → ba vấn đề ở mục 3.3 | Nghẽn đọc |
| Sharding | Vượt trần một node | Cross-shard, resharding, mãi mãi | Sau khi loại trừ mọi lựa chọn khác |
| Replication đồng bộ | RPO = 0 | Ghi chậm; follower chết ảnh hưởng ghi | Dữ liệu không được mất, cùng region |
| Multi-leader | Ghi được ở nhiều nơi | Xung đột ghi — phần khó nhất | Multi-region ghi, offline-first |
| Thêm index | Đọc nhanh hơn nhiều | Ghi chậm hơn, tốn dung lượng | Có bằng chứng từ query thật |
| PgBouncer transaction mode | Tiết kiệm kết nối rất nhiều | Không dùng được session state | Nhiều pod, PostgreSQL |
| Denormalize | Đọc nhanh, tránh join | Trùng lặp, phải đồng bộ | Đọc nhiều hơn ghi rất nhiều |
| Warehouse riêng cho analytics | Không ảnh hưởng OLTP | Pipeline, độ trễ dữ liệu | Báo cáo nặng, dữ liệu lớn |

---

## 11. Checklist

```text
Chọn công nghệ
□ Đã viết ra access pattern (đọc gì, ghi gì, tần suất) TRƯỚC khi chọn
□ Đã ước lượng dung lượng và QPS (không đoán)
□ Đã biện luận vì sao KHÔNG dùng một database quan hệ duy nhất
□ Mỗi datastore thêm vào có người biết vận hành và có backup

Trước khi shard
□ Index đã tối ưu (kiểm tra execution plan của top query)
□ Vertical scaling đã cân nhắc
□ Read replica / cache đã dùng
□ Đã cân nhắc functional partitioning (tách theo domain)
□ Shard key: cardinality cao, phân bố đều, có trong hầu hết query, bất biến, gom được dữ liệu liên quan

Replication
□ Alert lag theo THỜI GIAN, không theo byte
□ Đã xử lý read-your-writes cho các đường đi người dùng nhìn thấy
□ Failover đã được diễn tập, có ghi RTO thực đo

Kết nối
□ maxReplicas × poolSize ≤ giới hạn kết nối DB
□ maxLifetime < timeout của firewall/LB
□ Có connection pooler (PgBouncer/ProxySQL) nếu nhiều pod

Vận hành
□ Analytics KHÔNG chạy trên DB OLTP production
□ Mọi migration theo expand–contract, mỗi bước rollback được
□ Backfill chia lô, không một transaction lớn
□ Index không dùng được kiểm toán định kỳ
```

---

## 12. Ghi chú – chủ đề tiếp theo

- [storage_retrieval.md](storage_retrieval.md): B-tree vs LSM — vì sao Cassandra ghi nhanh, vì sao PostgreSQL đọc tốt.
- [distributed_systems_theory.md](distributed_systems_theory.md): quorum, consistency model, xung đột ghi.
- [caching.md](caching.md): cache so với read replica.
- `advanced/distributed_transactions.md`: Saga khi transaction vượt ranh giới shard/service.
- [sqlserver package](../../sqlserver/roadmap.md), [mongodb package](../../mongodb/roadmap.md), [clickhouse package](../../clickhouse/roadmap.md): chi tiết từng engine.

Từ khóa mở rộng: NewSQL (Spanner, CockroachDB, TiDB), HTAP, materialized view, table partitioning trong một node, pg_partman, GTID/LSN để chờ replication, ProxySQL read/write splitting, ghost/gh-ost cho migration MySQL, embedded shard id trong primary key.

---

*Cập nhật lần cuối: 2026-07-30*
