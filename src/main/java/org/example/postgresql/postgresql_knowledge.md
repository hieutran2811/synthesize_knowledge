# PostgreSQL – Tổng hợp kiến thức

> Trang này là bản đồ tra cứu nhanh. Lộ trình đầy đủ nằm tại
> [roadmap.md](roadmap.md).

**Phiên bản mục tiêu:** PostgreSQL 18.x

**Trạng thái chuẩn hóa:** 11/11 chủ đề – hoàn thành lộ trình (2026-07-31)

---

## 1. PostgreSQL trong một câu

PostgreSQL là relational database mã nguồn mở, dùng process-per-connection, MVCC
với nhiều tuple version và Write-Ahead Logging để cung cấp transaction, SQL phong
phú, extension framework và khả năng phục hồi.

```text
Client
  ↓ protocol + authentication
Backend process
  ↓ parse → rewrite → plan → execute
Shared buffers + lock/WAL state
  ↓
Heap/index pages + WAL
  ↓
checkpointer/vacuum/replication/backup
```

---

## 2. Bản đồ 11 chủ đề

| Lớp | Chủ đề | Câu hỏi chính |
|---|---|---|
| Nền tảng | [Architecture & Storage](fundamentals/architecture_storage.md) | Process, page, tuple, WAL và vacuum phối hợp thế nào? |
| Nền tảng | [Data Modeling & Types](fundamentals/data_modeling_types.md) | Type/constraint nào bảo vệ domain và schema tiến hóa ra sao? |
| Concurrency | [Transactions & MVCC](fundamentals/transactions_mvcc.md) | Snapshot nhìn thấy version nào và anomaly nào còn xảy ra? |
| Truy vấn | [Indexing & Planner](fundamentals/indexing_planner.md) | Planner chọn plan dựa vào statistics và index nào? |
| Truy vấn | [Advanced SQL](fundamentals/advanced_sql.md) | Diễn đạt bài toán set-based mà không thành N+1/cursor? |
| Hiệu năng | [Performance & Autovacuum](performance/tuning_autovacuum.md) | Bottleneck là connection, CPU, memory, I/O, lock hay vacuum? |
| Dữ liệu lớn | [Partitioning & Large Tables](performance/partitioning_large_tables.md) | Partition có thật sự giảm work và đơn giản lifecycle không? |
| Vận hành | [Replication & HA](operations/replication_ha.md) | Mất node thì promote copy nào và ngăn hai primary thế nào? |
| Vận hành | [Backup, PITR & Upgrade](operations/backup_pitr_upgrade.md) | Khôi phục được tới đâu, trong bao lâu và nâng major thế nào? |
| Bảo mật | [Security & RLS](operations/security_rls.md) | Ai kết nối, sở hữu object và thấy row nào? |
| Tích hợp | [JDBC & Spring](integration/jdbc_spring.md) | Pool, transaction, type mapping và retry từ Java thế nào? |

---

## 3. Năm mental model quan trọng

### 3.1 Database cluster không phải Kubernetes cluster

Trong PostgreSQL, một *database cluster* là một server instance/data directory
chứa nhiều database. Connection chỉ làm việc với một database trong một session.

### 3.2 UPDATE tạo version mới

PostgreSQL không thường ghi đè tuple tại chỗ. UPDATE tạo tuple version mới; version
cũ chỉ được tái sử dụng sau khi không còn snapshot nào cần và VACUUM xử lý.

### 3.3 WAL đi trước data page

Commit không chờ mọi data page xuống disk. WAL cần thiết được flush trước; crash
recovery replay WAL từ checkpoint.

### 3.4 Index không tự biết tuple còn visible

Index trỏ tới heap tuple. Index-only scan chỉ tránh heap visit khi visibility map
chứng minh page all-visible và query lấy đủ dữ liệu từ index.

### 3.5 Memory setting nhân theo concurrency

`work_mem` có thể dùng cho từng sort/hash operation, không phải một lần cho toàn
server hay mỗi query. Connection và parallel worker làm tổng memory tăng nhanh.

---

## 4. Tra cứu theo triệu chứng

| Triệu chứng | Đọc trước | Điểm kiểm tra |
|---|---|---|
| Nhiều connection làm RAM/process tăng | [Architecture §3–4](fundamentals/architecture_storage.md) | Process-per-connection, pool và session state |
| UPDATE nhiều làm bảng phình | [Architecture §10–17](fundamentals/architecture_storage.md) | Dead tuple, HOT, long snapshot và autovacuum |
| Index-only scan vẫn đọc heap | [Architecture §13](fundamentals/architecture_storage.md) | Visibility map/all-visible và vacuum |
| WAL/disk tăng đột biến | [Architecture §14–16](fundamentals/architecture_storage.md) | Write volume, full-page image, checkpoint và slot/archive |
| `VACUUM FULL` làm application đứng | [Architecture §17](fundamentals/architecture_storage.md) | ACCESS EXCLUSIVE, rewrite và disk copy |
| Autovacuum chạy gấp chống wraparound | [Architecture §18](fundamentals/architecture_storage.md) | XID age, long/prepared transaction và vacuum progress |
| Query “idle in transaction” lâu | [Architecture §19](fundamentals/architecture_storage.md) | Old snapshot giữ dead tuple và lock |
| Commit chậm | [Architecture §14–15](fundamentals/architecture_storage.md) | WAL flush/fsync, synchronous commit, storage latency |
| Restart sau crash lâu | [Architecture §16](fundamentals/architecture_storage.md) | WAL cần replay, checkpoint distance và I/O |
| Duplicate xuất hiện dù dùng surrogate ID | [Data Modeling §6](fundamentals/data_modeling_types.md) | Thiếu unique business key và idempotency contract |
| Tiền lệch vài đơn vị nhỏ | [Data Modeling §10–11](fundamentals/data_modeling_types.md) | Floating point, scale hoặc rounding rule không thống nhất |
| Timestamp hiển thị lệch theo session | [Data Modeling §14](fundamentals/data_modeling_types.md) | `timestamptz`, session timezone và zone gốc |
| Xóa parent scan/lock child lâu | [Data Modeling §19](fundamentals/data_modeling_types.md) | Child foreign key thiếu index hoặc cascade quá rộng |
| Hai booking cùng vượt qua bước kiểm tra | [Data Modeling §21](fundamentals/data_modeling_types.md) | Check-then-insert race; cần exclusion constraint |
| JSONB query chậm dù có GIN | [Data Modeling §27–28](fundamentals/data_modeling_types.md) | Operator/query shape không khớp operator class/index |
| Migration constraint khóa table lâu | [Data Modeling §31–34](fundamentals/data_modeling_types.md) | Lock acquisition, scan cũ, `NOT VALID`/concurrent index |
| Số dư/stock bị mất cập nhật | [Transactions §11–13](fundamentals/transactions_mvcc.md) | Read–compute–write; dùng atomic update, row lock hoặc version |
| Hai transaction cùng vượt business check | [Transactions §19–21](fundamentals/transactions_mvcc.md) | Write skew; cần Serializable hoặc coordination row |
| Nhiều lỗi `40001` | [Transactions §18, §20–24](fundamentals/transactions_mvcc.md) | SSI/concurrent update, retry toàn transaction và contention |
| Worker queue đứng hoặc xử lý trùng | [Transactions §15–16](fundamentals/transactions_mvcc.md) | `SKIP LOCKED`, lease, retry và idempotent handler |
| DDL nhỏ làm request xếp hàng | [Transactions §28–29](fundamentals/transactions_mvcc.md) | `ACCESS EXCLUSIVE`, long transaction và lock queue |
| Lỗi deadlock `40P01` | [Transactions §30–31](fundamentals/transactions_mvcc.md) | Lock order không nhất quán; retry toàn transaction |
| Không biết session nào đang block | [Transactions §37–41](fundamentals/transactions_mvcc.md) | `pg_stat_activity`, `pg_blocking_pids()` và root blocker |
| Có index nhưng planner vẫn Seq Scan | [Indexing §4–7](fundamentals/indexing_planner.md) | Selectivity cao, table nhỏ hoặc random heap access đắt |
| Index ghép không phục vụ query | [Indexing §9–11](fundamentals/indexing_planner.md) | Leading prefix, equality/range/order và skip scan |
| Index Only Scan vẫn đọc heap | [Indexing §12–13](fundamentals/indexing_planner.md) | Visibility map, table churn và `Heap Fetches` |
| Partial index không dùng với prepared query | [Indexing §15](fundamentals/indexing_planner.md) | Planner không chứng minh được predicate từ generic parameter |
| JSONB/array index write chậm | [Indexing §20–21](fundamentals/indexing_planner.md) | GIN pending list, operator class, width và update rate |
| Plan đổi xấu sau data growth/load | [Indexing §31–36](fundamentals/indexing_planner.md) | Stale statistics, skew, correlation và cost assumptions |
| Nested loop chạy inner node quá nhiều | [Indexing §37, §40–41](fundamentals/indexing_planner.md) | Cardinality underestimate; đọc `actual rows × loops` |
| Concurrent index build fail | [Indexing §28–30](fundamentals/indexing_planner.md) | Invalid index, build phase, disk/WAL và recovery runbook |
| `LEFT JOIN` làm mất row phía trái | [Advanced SQL §3](fundamentals/advanced_sql.md) | Predicate của bảng phải đặt ở `ON` hay `WHERE` |
| Anti-join trả về rỗng khi subquery có `NULL` | [Advanced SQL §4–5](fundamentals/advanced_sql.md) | Bẫy `NOT IN`; ưu tiên `NOT EXISTS` với điều kiện tương quan |
| Latest/top N mỗi group sai hoặc chậm | [Advanced SQL §9–18](fundamentals/advanced_sql.md) | Tie-breaker, `DISTINCT ON`, window hay `LATERAL` |
| Running total hoặc `last_value` cho kết quả lạ | [Advanced SQL §12–15](fundamentals/advanced_sql.md) | Window frame mặc định và peer rows |
| CTE làm plan xấu sau khi tái sử dụng nhiều lần | [Advanced SQL §20–22](fundamentals/advanced_sql.md) | Fold/materialize, predicate pushdown và computation lặp |
| Recursive query lặp vô hạn hoặc ngốn tài nguyên | [Advanced SQL §23–27](fundamentals/advanced_sql.md) | Termination, `CYCLE`, depth/row/statement boundary |
| Pagination sâu chậm hoặc bị lặp/mất row | [Advanced SQL §32–33](fundamentals/advanced_sql.md) | Composite cursor và deterministic keyset order |
| Upsert/MERGE cập nhật nhầm hoặc gặp conflict | [Advanced SQL §34–39](fundamentals/advanced_sql.md) | Unique arbiter, source uniqueness, concurrency và `RETURNING` |
| Pool đầy nhưng tăng connection càng chậm | [Performance §7–10, §52](performance/tuning_autovacuum.md) | Admission control, active waits và capacity knee point |
| Không biết query nào tiêu tốn database nhất | [Performance §11–17](performance/tuning_autovacuum.md) | Top total time/calls, I/O/temp/WAL và slow-plan evidence |
| Temp file hoặc RAM tăng mạnh | [Performance §21–25](performance/tuning_autovacuum.md) | Spill source và memory theo node × worker × concurrency |
| Checkpoint/WAL tạo I/O burst | [Performance §28–30](performance/tuning_autovacuum.md) | Requested/timed checkpoint, WAL rate, FPI và archive/slot |
| Dead tuple tăng nhanh dù autovacuum bật | [Performance §31–40, §54](performance/tuning_autovacuum.md) | Trigger, worker/cost, old snapshot và cleanup backlog |
| XID/MultiXact age gần giới hạn | [Performance §40–42](performance/tuning_autovacuum.md) | Wraparound worker, oldest relation và transaction giữ xmin |
| Disk tăng nhưng chưa biết do table hay WAL | [Performance §43–48, §55](performance/tuning_autovacuum.md) | Heap/index/TOAST, bloat, WAL/temp/log và maintenance boundary |
| Query partitioned table vẫn scan nhiều leaf | [Partitioning §20–29](performance/partitioning_large_tables.md) | Predicate/key không tương thích, runtime pruning và planning cost |
| Insert lỗi “no partition found” tại boundary | [Partitioning §15–16, §43](performance/partitioning_large_tables.md) | Future coverage, default partition và pre-create automation |
| Thêm partition làm table/default bị scan và khóa | [Partitioning §37–39](performance/partitioning_large_tables.md) | Exact CHECK trên staging và exclusion CHECK trên default |
| Không tạo được unique/PK trên partitioned parent | [Partitioning §30–36](performance/partitioning_large_tables.md) | Global index không tồn tại; key phải chứa toàn partition key |
| Planning time/RAM tăng theo số partition | [Partitioning §24–29](performance/partitioning_large_tables.md) | Leaf còn lại sau pruning, lock/metadata và session memory |
| Retention DELETE tạo nhiều WAL/dead tuple | [Partitioning §40–42, §49](performance/partitioning_large_tables.md) | Detach–archive–drop nếu retention trùng boundary |
| Migrate table lớn bằng rename nhưng FK/view trỏ sai | [Partitioning §51–54](performance/partitioning_large_tables.md) | Shadow migration, concurrent writes và dependency theo OID |
| Plan sai sau load/rollover partition | [Partitioning §43–47, §57](performance/partitioning_large_tables.md) | ANALYZE parent/leaf, per-leaf vacuum và index/policy drift |
| Standby vẫn streaming nhưng RPO không rõ | [Replication & HA §5–18](operations/replication_ha.md) | sent/write/flush/replay LSN, byte lag, reply time và peak WAL rate |
| `pg_wal` tăng nhanh do replica/subscriber mất kết nối | [Replication & HA §19–23](operations/replication_ha.md) | slot owner, `wal_status`, `safe_wal_size`, retention limit và disk headroom |
| Commit treo khi một standby hỏng | [Replication & HA §25–29](operations/replication_ha.md) | synchronous quorum thiếu, WAL flush latency và policy giảm durability |
| Query read replica stale hoặc hay bị cancel | [Replication & HA §30–35](operations/replication_ha.md) | replay lag, recovery conflict, delay budget và `hot_standby_feedback` |
| Failover xong primary cũ không thể join lại | [Replication & HA §36–47](operations/replication_ha.md) | fencing, timeline divergence, `pg_rewind` prerequisite hoặc fresh rebuild |
| Logical replication dừng sau migration | [Replication & HA §49–60](operations/replication_ha.md) | replica identity, schema/DDL, sequence, constraint, conflict và table sync |
| Logical subscriber không chạy sau publisher failover | [Replication & HA §61–63](operations/replication_ha.md) | failover slot sync, `synchronized_standby_slots` và `failover_ready` |
| Backup job xanh nhưng chưa biết restore được không | [Backup & PITR §1–8, §28–30](operations/backup_pitr_upgrade.md) | manifest/checksum, key, dependency và restore drill end-to-end |
| Logical restore lỗi owner/role/tablespace | [Backup & PITR §9–22](operations/backup_pitr_upgrade.md) | `pg_dumpall --globals-only`, restore order, option ownership/grant |
| Incremental backup còn đủ file nhưng không combine được | [Backup & PITR §31–37](operations/backup_pitr_upgrade.md) | WAL summary, parent chain, checksum state và dependency-aware retention |
| Archive job hỏng làm `pg_wal` tăng | [Backup & PITR §38–45](operations/backup_pitr_upgrade.md) | durable archive contract, `pg_stat_archiver`, backlog và time-to-full |
| PITR dừng sai phía của bad transaction | [Backup & PITR §46–56](operations/backup_pitr_upgrade.md) | timezone, inclusive/action, base end time, timeline và isolated validation |
| Có backup nhưng RTO restore quá dài | [Backup & PITR §57–61](operations/backup_pitr_upgrade.md) | download/decrypt/combine/replay/analyze throughput và backup catalog |
| Major upgrade cần downtime ngắn nhưng rollback chưa rõ | [Backup & PITR §62–76](operations/backup_pitr_upgrade.md) | `pg_upgrade` transfer mode, rehearsal, logical blue-green và write reconciliation |
| Client báo HBA reject hoặc dùng nhầm auth method | [Security & RLS §7–10](operations/security_rls.md) | First-match rule, source IP sau proxy/NAT, TLS path, membership và parser error |
| TLS có mã hóa nhưng chưa chắc nối đúng server | [Security & RLS §4–6](operations/security_rls.md) | `verify-full`, CA/SAN và `pg_stat_ssl` trên từng network hop |
| Runtime đọc/sửa quá nhiều dù GRANT trông có vẻ hẹp | [Security & RLS §13–22](operations/security_rls.md) | Membership graph, ownership, `PUBLIC`, default privilege và definer function |
| Tenant thấy row tenant khác khi connection được tái sử dụng | [Security & RLS §24–36](operations/security_rls.md) | Owner bypass, `WITH CHECK`, custom GUC và transaction-local pool context |
| Đổi password nhưng session cũ vẫn hoạt động | [Security & RLS §37–39](operations/security_rls.md) | Blue/green login, `NOLOGIN` không terminate backend và incident containment |
| Audit log tăng mạnh hoặc chứa PII/secret | [Security & RLS §40–46](operations/security_rls.md) | Event scope, parameter logging, pgAudit, sink/retention và tamper boundary |
| Hikari pending/acquire timeout tăng dù database còn sống | [JDBC & Spring §7–12, §47](integration/jdbc_spring.md) | Pool toàn fleet, connection hold time, DB wait và transaction boundary |
| Java OOM khi export hoặc batch dữ liệu lớn | [JDBC & Spring §18–21](integration/jdbc_spring.md) | Cursor fetch cần transaction, consumer bounded, chunk và COPY staging |
| Query dùng prepared statement nhưng plan/cache có vấn đề | [JDBC & Spring §16–17, §42–43](integration/jdbc_spring.md) | Parameter binding khác server prepare; cache per connection và PgBouncer tracking |
| Timestamp lệch giờ hoặc tiền sai precision | [JDBC & Spring §22–26](integration/jdbc_spring.md) | `OffsetDateTime`/instant, `BigDecimal`, UUID, JSONB và custom type contract |
| Retry vẫn lỗi “transaction is aborted” hoặc tạo duplicate | [JDBC & Spring §28–36](integration/jdbc_spring.md) | Proxy boundary, rollback rule, transaction mới, SQLSTATE và unknown commit outcome |
| JPA sinh N+1 hoặc lỗi constraint chỉ xuất hiện khi commit | [JDBC & Spring §37–40](integration/jdbc_spring.md) | Persistence context, flush, sequence batching, fetch plan và lock strategy |
| Failover xong Java vẫn nối nhầm host hoặc retry write sai | [JDBC & Spring §5, §45–49](integration/jdbc_spring.md) | Primary selection, read consistency, broken connection và idempotent recovery |

---

## 5. Nguyên tắc production

1. Dùng transaction ngắn và đặt timeout cho `idle in transaction`.
2. Giữ autovacuum bật; tune theo table churn, không theo một lịch ban đêm duy nhất.
3. Không dùng `VACUUM FULL` như bảo trì định kỳ.
4. Đo connection và memory ở peak concurrency.
5. Không tắt `fsync`/`full_page_writes` trên dữ liệu cần durability.
6. Theo dõi WAL, archive và replication slot trước khi disk đầy.
7. Backup phải được restore drill; replica không phải backup.
8. Đặt invariant ổn định bằng type/constraint; validation ở application dùng để
   trả lỗi thân thiện, không thay thế database contract.
9. Schema lớn tiến hóa theo expand–migrate–contract; rehearsal lock, backfill,
   WAL và replica lag trước production.
10. Retry `40001`/`40P01` phải chạy lại toàn transaction; external side effect
    cần idempotency/outbox.
11. Khóa nhiều object theo cùng thứ tự và không giữ transaction khi chờ
    user/network.
12. Thiết kế index từ query shape và distribution; không ép dùng index khi
    sequential scan có ít work hơn.
13. Khi plan sai, tìm cardinality estimate đầu tiên lệch trước khi đổi planner
    toggle hoặc cost constants.
14. Top N và pagination phải có total order ổn định; luôn thêm unique tie-breaker vào
    `ORDER BY` và cursor.
15. Gộp N+1 thành set-based/batch query, nhưng vẫn đo cardinality, memory và plan thay vì
    mặc định một statement lớn luôn tốt hơn.
16. Đọc cumulative counter theo delta cùng mốc reset; giữ baseline trước khi thay đổi hoặc
    xử lý sự cố.
17. Giữ autovacuum bật và tune theo từng table để cleanup rate theo kịp churn; manual vacuum
    không thay cho việc sửa threshold, blocker và worker capacity.
18. Connection, memory, parallelism và maintenance đều cần admission budget ở peak; tối ưu
    một query không được đổi lấy OOM hoặc tail latency của toàn hệ thống.
19. Chỉ partition khi typical query prune còn ít leaf hoặc lifecycle có thể xử lý nguyên
    partition; kích thước bảng một mình không phải lý do.
20. Partition boundary dùng `[start, end)`, được pre-create và kiểm tra từ catalog; default
    partition nếu có phải được alert và drain.
21. ATTACH/DETACH, recursive DDL và repartition migration phải rehearsal lock, dependency,
    WAL, replica và rollback trên hierarchy cùng scale production.
22. Failover chỉ được promote sau khi primary cũ đã bị fence; health check thất bại không phải bằng
    chứng rằng node cũ đã mất quyền ghi.
23. Mọi replication slot phải có owner, retention budget và alert; slot bảo vệ consumer bằng cách giữ
    tài nguyên trên primary nên có thể làm đầy `pg_wal`.
24. Read replica là eventually consistent trừ khi có contract mạnh hơn; routing phải nêu freshness SLA
    và xử lý read-your-writes rõ ràng.
25. Physical/logical replica không thay backup; backup, WAL archive và restore/PITR drill phải nằm trong
    failure model độc lập.
26. Backup chỉ được coi là recoverable sau khi manifest/integrity pass, server đã start trong môi trường
    cô lập và business invariant được kiểm tra trong RPO/RTO.
27. WAL archive phải idempotent, durable và từ chối overwrite file cùng tên khác nội dung; success trước
    durability có thể tạo khoảng trống PITR không thể bù.
28. Incremental backup là dependency graph: chỉ expire parent khi không còn child cần nó và đã bảo toàn
    WAL coverage, manifest, key cùng restore path.
29. Recovery target phải ghi timezone, inclusive/action và timeline rõ ràng; ưu tiên pause rồi xác minh
    trước khi promote hoặc sửa production.
30. Major upgrade chỉ hoàn tất khi extension, statistics/plan, HA, archive và backup baseline của major mới
    đều sẵn sàng; khả năng start primary mới chưa đủ.
31. Mọi production hop dùng TLS `verify-full`; HBA áp dụng first-match nên rule hẹp phải đứng trước và
    phải test cả allow lẫn deny case từ đúng network path.
32. Tách owner `NOLOGIN`, migrator và runtime role; review effective privilege qua membership, ownership,
    `PUBLIC`, default privilege và `SECURITY DEFINER`, không chỉ ACL trực tiếp.
33. RLS tenant cần `ENABLE` + `FORCE`, đủ `USING`/`WITH CHECK`, tenant-aware PK/FK/unique và test bằng
    runtime role; superuser, `BYPASSRLS` cùng owner thông thường không phải test identity hợp lệ.
34. Shared-login tenant context chỉ là authorization context sau trusted backend, không phải credential;
    đặt transaction-local và kiểm thử tái sử dụng connection A → B qua cả exception/retry.
35. Pool size là admission budget của toàn fleet; tính pod autoscaling, nested transaction, batch/job và
    headroom thay vì áp dụng một công thức cố định cho từng instance.
36. Acquire, connect, socket, statement, lock, transaction và request timeout phải tạo một chuỗi ngân sách;
    timeout ngoài ngắn hơn timeout trong làm work tiếp tục sau khi caller đã bỏ đi.
37. Retry `40001`/`40P01` bao ngoài một transaction mới, có jitter/deadline và idempotency; mất response lúc
    COMMIT là outcome mơ hồ, không được retry INSERT bằng ID mới một cách mù quáng.
38. `@Transactional(readOnly = true)` là hint, không tự route replica; freshness/read-your-writes và
    failover vẫn là contract riêng của routing layer.
39. Test JDBC/JPA/RLS/lock/retry/PgBouncer với PostgreSQL 18 thật và runtime role thật; H2 không chứng minh
    PostgreSQL semantics hoặc commit-time behavior.

---

*Cập nhật lần cuối: 2026-07-31.*
