# Database Observability & Performance Engineering – Từ Workload đến Execution Plan

> Mục tiêu của bài này là xây cách quan sát database từ trải nghiệm của application
> xuống connection pool, SQL workload, transaction, lock, planner, buffer/cache,
> WAL/redo, replication và storage. PostgreSQL được dùng làm ví dụ sâu; MySQL và
> JDBC được đối chiếu ở những điểm khác biệt quan trọng.
>
> Baseline tham chiếu: **PostgreSQL 18**, **MySQL 8.4 LTS**, **Prometheus 3.13.x**,
> **Grafana 13.1.x**, **OpenTelemetry Semantic Conventions 1.43.x** và stack
> observability của dự án.
>
> Không chạy `EXPLAIN ANALYZE`, query catalog nặng, terminate session, rebuild index,
> `VACUUM FULL`, thay isolation hoặc reset statistics trên production nếu chưa hiểu
> tác động, lock và rollback.
>
> Nên đọc trước:
> [Metrics Design](metrics_design.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Continuous Profiling](continuous_profiling.md),
> [Incident Response with Observability](incident_response_observability.md) và
> [Telemetry Governance & FinOps](telemetry_governance_finops.md).

---

## 1. Vì sao database observability khó?

Một request chậm có thể chờ ở:

```text
application thread
  → connection pool
  → DNS/TCP/TLS
  → database admission
  → lock
  → CPU
  → buffer/cache
  → storage I/O
  → WAL/replication acknowledgement
  → result transfer
  → ORM mapping
```

“Database latency cao” không cho biết hop nào.

Database còn có:

- state bền vững;
- transaction/isolation;
- shared caches;
- query optimizer;
- long-lived connections;
- background maintenance;
- primary/replica;
- workload tương tác lẫn nhau.

Tuning một query có thể làm workload khác chậm hoặc tăng write cost.

---

## 2. Ba mục tiêu: correctness, performance và capacity

| Mục tiêu | Câu hỏi |
|---|---|
| Correctness | dữ liệu đọc/ghi có đúng, đủ, durable và consistent theo contract không? |
| Performance | request/query có hoàn tất trong latency target không? |
| Capacity | workload còn headroom khi spike, failover hoặc maintenance không? |

Không tối ưu performance bằng cách phá correctness.

Ví dụ:

```text
đọc replica lag 30 giây
  → query rất nhanh
  → nhưng user không thấy order vừa tạo
```

Đó là correctness failure nếu read-after-write là contract.

---

## 3. Mô hình nhiều lớp

```text
User SLI
  → application
  → ORM/driver
  → connection pool
  → network/proxy
  → database frontend
  → executor/planner/locks
  → buffer/WAL
  → OS/storage
  → replica/backup
```

Mỗi lớp cần:

- signal;
- owner;
- timeout;
- capacity;
- failure mode;
- correlation key.

Chỉ cài exporter ở database bỏ sót pool wait và ORM overhead. Chỉ trace application bỏ sót
vacuum, checkpoint, lock holder và storage.

---

## 4. Golden signals cho database

| Signal | Database interpretation |
|---|---|
| Traffic | transactions, statements, rows, bytes |
| Errors | SQLSTATE/error class, abort, deadlock, timeout |
| Latency | query, transaction, acquire connection, commit |
| Saturation | connections, CPU, I/O, locks, queues, memory |

Thêm:

- data freshness/correctness;
- replication lag;
- WAL/redo pressure;
- cache effectiveness;
- maintenance debt;
- backup/restore.

Đo cả client-observed và server-observed latency. Chênh lệch lớn chỉ ra pool/network/result
processing hoặc retries.

---

## 5. Database SLO

Không dùng “database uptime 99.99%” cho mọi use case.

Ví dụ capability:

| Capability | SLI |
|---|---|
| Checkout write | committed good transactions / attempts |
| Product read | successful reads dưới 100 ms |
| Read freshness | replica replay delay dưới contract |
| Connection | acquisition dưới 50 ms |
| Recovery | failover/restore đạt RTO/RPO |

Query latency SLO cần phân class:

- point read;
- transactional write;
- batch;
- analytics;
- maintenance.

Một report 20 phút không nên chung histogram với checkout 50 ms.

---

## 6. Workload inventory

Ghi:

```yaml
database: commerce
engine: postgresql
workload:
  type: oltp
  peak_transactions_per_second: 4200
  read_write_ratio: 7:3
  critical_operations:
    - place_order
    - reserve_inventory
  batch_windows:
    - reconciliation: "01:00-03:00 UTC"
consistency:
  checkout: read-your-writes
growth:
  data_per_day: 180GB
owners:
  application: team-commerce
  database: data-platform
```

Không thể đánh giá plan/capacity nếu không biết workload và data distribution.

---

## 7. OLTP, OLAP và mixed workload

| Workload | Đặc điểm |
|---|---|
| OLTP | query ngắn, concurrency cao, latency nghiêm |
| OLAP | scan/aggregate lớn, throughput quan trọng |
| Batch | burst theo lịch, có deadline |
| Mixed | interference giữa transactional và analytics |

Một index tốt cho point lookup có thể:

- tăng write amplification;
- tăng vacuum/maintenance;
- không giúp scan lớn;
- chiếm cache.

Mixed workload thường cần:

- workload class;
- resource groups/limits;
- read replica/warehouse;
- query timeout khác;
- scheduling.

---

## 8. Baseline trước khi tuning

Baseline:

- traffic;
- latency percentiles;
- errors;
- pool utilization/wait;
- active sessions;
- wait events;
- top query fingerprints;
- CPU/I/O;
- cache;
- WAL/replication;
- table/index growth;
- maintenance.

Thu theo:

```text
normal day
peak
batch window
release
failover
month/quarter event
```

Một snapshot 5 phút không đại diện workload.

---

## 9. Observability cũng có overhead

Nguồn overhead:

- statistics tracking;
- query text capture;
- statement timing;
- auto explain;
- tracing;
- exporter catalog queries;
- high-frequency scrape;
- log every statement;
- lock graph;
- plan collection.

Trade-off:

```text
diagnostic value
  vs CPU/memory/I/O
  vs privacy/cardinality
```

Benchmark trước/sau và rollout canary. Không bật mọi statement log trên database bận chỉ để
“có observability”.

---

## 10. Security và privacy

SQL có thể chứa:

- email/user ID;
- tokens;
- payment data;
- search text;
- business secrets;
- table/schema topology.

Control:

- prepared statements;
- normalize/fingerprint;
- sanitize literals;
- truncate;
- least-privilege monitoring role;
- encrypt;
- restrict query text;
- retention/audit;
- no password in exporter URI.

Hash query text không tự loại sensitive literals nếu text gốc vẫn được thu ở signal khác.

---

## 11. Query fingerprint và query ID

Dynamic SQL:

```sql
SELECT * FROM orders WHERE customer_id = 123 AND status = 'PAID';
SELECT * FROM orders WHERE customer_id = 456 AND status = 'PAID';
```

Normalized concept:

```sql
SELECT * FROM orders WHERE customer_id = ? AND status = ?;
```

Fingerprint/query ID giúp:

- aggregate calls;
- compare latency;
- top total time;
- correlate plan;
- limit cardinality.

Query ID semantics có thể đổi theo engine/version/config. Không dùng nó làm business identifier
vĩnh viễn.

---

## 12. Application-side database metrics

Đo:

- logical operation count;
- success/error;
- duration;
- retries;
- rows returned/affected nếu bounded;
- timeout/cancellation;
- transaction duration;
- connection acquire duration.

Labels:

```text
service
db.system
db.namespace
operation
query.summary/fingerprint
outcome
```

Không label:

- raw SQL;
- customer ID;
- trace ID;
- host động nếu không cần;
- exception message.

Client metrics phản ánh experience application, kể cả database server cho rằng query đã nhanh.

---

## 13. Connection pool metrics

Với HikariCP hoặc pool tương tự:

- active;
- idle;
- total;
- pending/waiting;
- max/min;
- acquire time;
- usage time;
- creation time;
- timeout count.

Mẫu:

```text
pool utilization = active / max
queue pressure    = pending connections + acquire latency
```

Active 100% không luôn xấu nếu acquisition nhanh. Pending tăng và acquire p99 chạm timeout mới
chứng minh user-facing saturation.

---

## 14. Pool sizing

Pool lớn hơn không đồng nghĩa throughput cao hơn.

Quá nhỏ:

- application threads chờ;
- throughput bị giới hạn dù DB rảnh.

Quá lớn:

- context switching;
- memory per connection;
- lock contention;
- cache churn;
- DB overload;
- failover/reconnect storm.

Capacity constraint:

```text
sum(max pool của mọi replicas/services)
  <= database usable connections
  - admin/maintenance reserve
  - replication/background reserve
```

Tính cả autoscaling max, không chỉ replicas hiện tại.

---

## 15. Connection acquisition latency

Phân biệt:

```text
request starts
  → waits for pool
  → connection acquired
  → statement executes
  → result consumed
```

Nếu span database chỉ bao statement, pool wait bị vô hình.

Cần metric/span riêng:

- `db.connection_pool.acquire`;
- timeout reason;
- pool name;
- service instance;
- current utilization.

Pool wait tăng có thể do:

- slow queries;
- leaked connection;
- long transaction;
- pool quá nhỏ;
- database/network unavailable;
- thread surge.

---

## 16. Connection lifecycle và timeouts

Timeout hierarchy:

```text
request deadline
  > transaction/query timeout
  > network/socket timeout
  > connection acquire timeout
```

Không có một thứ tự tuyệt đối cho mọi hệ thống, nhưng inner work không nên tiếp tục vô nghĩa sau
khi caller đã bỏ cuộc.

Theo dõi:

- connection age;
- idle;
- validation failures;
- creation failures;
- closed/broken;
- max lifetime;
- keepalive;
- server idle/session limits.

Đồng bộ lifetime với proxy/load balancer/database để tránh stale connection hàng loạt.

---

## 17. Connection leak

Dấu hiệu:

```text
active → max
pending → tăng
database active queries → không tương ứng
usage duration → rất dài
```

Nguyên nhân:

- thiếu `close`;
- transaction không kết thúc;
- stream/result set chưa consume/close;
- exception path;
- thread bị block;
- ORM session scope quá rộng.

Leak detector có overhead và false positives nếu threshold thấp hơn transaction hợp lệ.

Fix ownership/lifecycle; tăng pool chỉ trì hoãn outage.

---

## 18. OpenTelemetry database spans

Database client span thường:

- kind `CLIENT`;
- bao logical operation nhìn từ caller;
- có `db.system.name`;
- `db.namespace`;
- `db.operation.name`;
- `db.collection.name` khi sẵn có;
- `db.query.summary`;
- server address/port;
- error type/status.

Span duration nên bao retries nội bộ của logical call nếu client API thực hiện chúng.

Không tạo span name bằng raw SQL/literals. Span name cardinality phải hữu hạn.

---

## 19. Semantic conventions và migration

Database semantic conventions có mixed stability ở một số nhóm, còn database client spans cốt
lõi đã stable.

Khi instrumentation cũ chuyển convention:

```text
old attributes
  → dual emission có thời hạn
  → dashboards/rules update
  → compare
  → stop old
```

Không dual emit vĩnh viễn vì:

- tăng cost;
- duplicate dimensions;
- query phức tạp;
- consumers không migrate.

Pin SDK/agent và ghi semantic convention version.

---

## 20. `db.query.text` và sanitization

OpenTelemetry khuyến nghị chỉ collect query text mặc định khi có sanitization loại dữ liệu
nhạy cảm.

Policy:

| Field | Default |
|---|---|
| `db.query.summary` | thu nếu low-cardinality |
| `db.operation.name` | thu |
| `db.collection.name` | thu khi an toàn |
| `db.query.text` | off hoặc sanitized/truncated |
| parameters/bind values | không thu |

Sanitizer phải hiểu dialect đủ tốt. Regex đơn giản dễ bỏ sót literal/comment/escaping.

---

## 21. Query summary

Summary tốt:

```text
SELECT orders
UPDATE inventory
CALL reserve_stock
```

Summary không nên:

```text
SELECT order_918273
SELECT ... WHERE email='...'
full 300-line SQL
```

Mục tiêu:

- span name;
- grouping;
- dashboard;
- sampling;
- alert triage.

Chi tiết sâu dùng query ID/fingerprint qua secure workflow.

---

## 22. Context propagation qua SQL commenter

Có thể inject comment:

```sql
SELECT ... /*traceparent='...'*/
```

Nhưng không bật mặc định mù quáng:

- plan/prepared statement cache có thể bị ảnh hưởng;
- query text cardinality tăng;
- logs/audit có trace context;
- comment length/driver/dialect;
- security boundary.

Ưu tiên correlation bằng client spans/query fingerprint. SQL commenter chỉ opt-in sau benchmark
và privacy review.

---

## 23. Exporter design

Exporter cần monitoring role tối thiểu:

- đọc statistics cần thiết;
- không superuser nếu tránh được;
- no business table reads;
- secret file/workload identity;
- TLS verify;
- query timeout;
- bounded collectors;
- scrape self-metrics.

Theo dõi exporter:

- scrape duration;
- scrape errors;
- last success;
- collector duration;
- connection failures;
- output series.

Exporter up không chứng minh database workload healthy.

---

## 24. PostgreSQL statistics system

PostgreSQL cung cấp:

- current activity;
- cumulative database/table/index stats;
- I/O;
- WAL/checkpoint;
- replication;
- progress views;
- extension `pg_stat_statements`.

Lưu ý:

- cumulative stats có độ trễ;
- statistics có thể được cache trong transaction;
- unclean shutdown/PITR có thể reset counters;
- một số dữ liệu bị giới hạn theo quyền;
- monitoring cũng có overhead.

Ghi `stats_reset` và server start để diễn giải counter.

---

## 25. `pg_stat_activity`

Query an toàn, bounded:

```sql
SELECT
    datname,
    application_name,
    state,
    wait_event_type,
    wait_event,
    count(*) AS sessions
FROM pg_stat_activity
WHERE datname IS NOT NULL
GROUP BY 1, 2, 3, 4, 5
ORDER BY sessions DESC;
```

Quan sát:

- active/idle;
- idle in transaction;
- query/transaction age;
- wait events;
- application name;
- client;
- query ID.

`state='active'` và wait event khác null nghĩa query đang execute nhưng bị block/chờ ở đâu đó.

---

## 26. Wait events

Nhóm:

- `Lock`;
- `LWLock`;
- `IO`;
- `Client`;
- `IPC`;
- `BufferPin`;
- `Timeout`;
- `Activity`.

Phân tích:

```text
latency tăng
  + Lock waits tăng     → contention/blocker
  + IO waits tăng       → storage/cache/scan
  + ClientWrite tăng    → client/network consume chậm
  + ClientRead nhiều    → sessions idle chờ client
```

Wait event là state sampling/current view, không luôn là cumulative time đầy đủ.

---

## 27. `pg_stat_database`

Theo database:

- transactions commit/rollback;
- blocks read/hit;
- tuples returned/fetched/inserted/updated/deleted;
- conflicts;
- temp files/bytes;
- deadlocks;
- checksum failures;
- session time;
- active/idle-in-transaction time.

Rates:

```promql
rate(pg_stat_database_xact_commit[5m])
rate(pg_stat_database_deadlocks[5m])
rate(pg_stat_database_temp_bytes[5m])
```

Counter reset cần được xử lý bằng `rate`/`increase` và `stats_reset` context.

---

## 28. Table và index statistics

`pg_stat_user_tables`:

- sequential/index scans;
- tuples;
- live/dead tuples;
- modifications;
- vacuum/analyze timestamps/counts.

`pg_stat_user_indexes`:

- index scans;
- tuples read/fetched.

Không kết luận index không dùng chỉ từ `idx_scan=0` nếu:

- stats vừa reset;
- workload theo tháng;
- replica khác phục vụ reads;
- constraint index;
- query planner dùng cho rare critical path.

Index removal cần workload window và rollback plan.

---

## 29. `pg_stat_io`

PostgreSQL 18 theo dõi I/O theo:

- backend type;
- object;
- context;
- reads/writes/extends/fsync;
- bytes;
- timing khi tracking bật.

Kết hợp OS:

- device latency/queue;
- throughput;
- IOPS;
- filesystem;
- page cache;
- CPU iowait.

PostgreSQL I/O stats không luôn phân biệt đọc thật từ disk với dữ liệu đã ở kernel page cache.

Database và node/storage telemetry phải được correlate.

---

## 30. `pg_stat_statements`

Extension aggregate planning/execution statistics theo normalized statement/query ID.

Cần:

- `shared_preload_libraries`;
- restart để add/remove;
- query ID;
- sizing;
- monitoring role;
- privacy.

Các field hữu ích:

- calls;
- total/mean/min/max execution time;
- rows;
- shared/local/temp blocks;
- WAL records/bytes;
- planning stats nếu bật;
- JIT.

Rank theo total time để tìm workload cost, không chỉ mean latency.

---

## 31. Top queries và heavy hitters

Ví dụ:

```sql
SELECT
    queryid,
    calls,
    total_exec_time,
    mean_exec_time,
    rows,
    shared_blks_read,
    shared_blks_hit,
    temp_blks_written,
    wal_bytes
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

Dimensions:

```text
frequency × latency × resources × business criticality
```

Một query 10 giây chạy mỗi tháng khác query 20 ms chạy 100 nghìn lần/giây.

---

## 32. Query statistics limitations

Lưu ý:

- entries hữu hạn, có thể evict;
- stats reset;
- normalized queries có thể gộp patterns;
- prepared/ORM queries;
- extension overhead;
- query text truncation;
- replica/primary khác workload;
- total time không gồm mọi client-side time.

Theo dõi:

- deallocation/eviction;
- stats reset time;
- extension configuration;
- coverage ratio.

Không dùng `pg_stat_statements_reset()` trong incident nếu chưa lưu baseline và được phê duyệt.

---

## 33. Slow-query logging

Ưu điểm:

- chi tiết theo occurrence;
- duration;
- error/context;
- plan nếu auto-explain phù hợp.

Rủi ro:

- volume/I/O;
- SQL/parameters nhạy cảm;
- log contention;
- multiline parsing;
- duplicate với audit;
- high-cardinality.

Sampling/filter:

- duration threshold;
- sample rate;
- database/user/application;
- error class;
- temporary incident window.

Slow threshold phải theo workload class.

---

## 34. `EXPLAIN`

`EXPLAIN` ước tính plan, không thực thi query.

Xem:

- scan type;
- join order/algorithm;
- estimated rows;
- cost;
- width;
- sort/aggregate;
- parallelism;
- filters;
- index conditions.

```sql
EXPLAIN (FORMAT JSON)
SELECT ...
```

JSON dễ lưu/diff tự động.

Planner cost là đơn vị tương đối, không phải milliseconds.

---

## 35. `EXPLAIN ANALYZE` và safety

`EXPLAIN ANALYZE` **thực thi query**.

Rủi ro:

- `UPDATE/DELETE/INSERT` thay data;
- query nặng gây impact;
- lock;
- cache warming đổi kết quả;
- output verbose chứa data;
- production workload khác.

Với write:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, WAL, FORMAT JSON)
UPDATE ...;
ROLLBACK;
```

Vẫn có lock, trigger, side effects ngoài transaction hoặc sequence advance. Dùng staging/replica
an toàn khi có thể.

---

## 36. Actual vs estimated rows

Dấu hiệu:

```text
estimated rows = 100
actual rows    = 1,000,000
```

Có thể do:

- stale statistics;
- correlated columns;
- skew;
- expressions;
- parameter sensitivity;
- missing extended stats;
- generic prepared plan.

Đừng ép index trước khi hiểu misestimate.

Actions:

- `ANALYZE`;
- statistics target;
- extended statistics;
- query rewrite;
- index;
- validate distribution.

---

## 37. Planner statistics

PostgreSQL planner dùng samples/statistics, không đọc toàn bộ table cho mỗi plan.

Theo dõi:

- last analyze/autoanalyze;
- modifications since analyze;
- estimate error;
- column statistics target;
- extended stats;
- plan regression sau data growth.

Over-tuning statistics target tăng:

- analyze time;
- catalog size;
- planning cost.

Chỉ tăng cho columns/query patterns có evidence.

---

## 38. Index observability

Index giúp reads nhưng tốn:

- disk;
- cache;
- WAL;
- insert/update/delete;
- vacuum;
- backup/restore;
- build/rebuild.

Đo:

- size;
- scans;
- selectivity;
- bloat;
- write overhead;
- build progress;
- duplicate/overlap;
- query plans.

Index-only scan còn phụ thuộc visibility map và vacuum.

Không tạo index từ một slow query log mà bỏ qua write volume và existing indexes.

---

## 39. Sequential scan

Sequential scan không mặc định xấu:

- table nhỏ;
- query đọc phần lớn rows;
- cache-friendly;
- batch/analytics;
- parallel scan.

Xấu khi:

- point lookup trên table lớn;
- estimate sai;
- repeated scan cao;
- I/O/temp tăng;
- latency/SLO bị ảnh hưởng.

Tỷ lệ scan cần kết hợp table size, rows returned và query fingerprint.

---

## 40. Table bloat và dead tuples

MVCC tạo old row versions.

Dấu hiệu:

- `n_dead_tup`;
- table/index size tăng;
- vacuum lag;
- scan/I/O tăng;
- transaction rất lâu giữ xmin;
- replication slot giữ WAL.

Estimate bloat không hoàn hảo. Xác nhận bằng nhiều nguồn trước disruptive maintenance.

`VACUUM FULL` rewrite table và cần lock mạnh; không dùng như phản xạ đầu tiên.

---

## 41. Vacuum và autovacuum

Vacuum cần để:

- reclaim reusable space;
- update visibility map;
- tránh transaction ID wraparound;
- hỗ trợ planner cùng analyze;
- giữ performance.

Theo dõi:

- last vacuum/autovacuum;
- dead tuples;
- vacuum progress;
- autovacuum workers;
- table thresholds;
- wraparound age;
- cost delay;
- I/O impact.

Tuning theo table churn/size; một config global không phù hợp mọi table.

---

## 42. Long transactions và `idle in transaction`

Long transaction có thể:

- giữ locks;
- giữ old snapshots;
- chặn vacuum cleanup;
- tăng bloat;
- giữ connections;
- tăng replica conflicts;
- tạo rollback lớn.

Query:

```sql
SELECT
    pid,
    application_name,
    state,
    now() - xact_start AS transaction_age,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
```

Redact query/client fields theo quyền.

---

## 43. Transactions

Đo:

- begin/commit/rollback rate;
- duration;
- statements per transaction;
- rows changed;
- retries;
- serialization failures;
- deadlocks;
- lock wait;
- idle time.

Transaction boundary nên theo business invariant, nhưng giữ càng ngắn càng tốt trong giới hạn
correctness.

Không gọi external API chậm trong lúc giữ database lock nếu có pattern an toàn khác.

---

## 44. Locks và blockers

PostgreSQL:

- `pg_locks`;
- `pg_stat_activity`;
- `pg_blocking_pids(pid)`.

Query:

```sql
SELECT
    a.pid AS blocked_pid,
    a.application_name,
    a.wait_event_type,
    a.wait_event,
    pg_blocking_pids(a.pid) AS blocking_pids,
    now() - a.query_start AS wait_age
FROM pg_stat_activity a
WHERE cardinality(pg_blocking_pids(a.pid)) > 0
ORDER BY wait_age DESC;
```

Tìm root blocker, không kill mọi waiter.

---

## 45. Deadlocks

Deadlock:

```text
transaction A holds X, waits Y
transaction B holds Y, waits X
```

Database phát hiện và abort một transaction.

Theo dõi:

- deadlock rate;
- involved operations/tables;
- transaction ordering;
- retry behavior;
- user impact.

Fix:

- consistent lock order;
- shorter transactions;
- proper indexes;
- smaller batches;
- retry bounded/idempotent.

Tăng deadlock timeout không giải quyết cycle.

---

## 46. Isolation, MVCC và anomalies

Isolation trade-off:

- consistency;
- concurrency;
- retries;
- lock/snapshot behavior.

Quan sát:

- serialization failures;
- lock waits;
- transaction retries;
- stale reads;
- replica routing;
- long snapshots.

Application phải biết retry entire transaction khi engine yêu cầu; retry một statement có thể
phá invariant.

Không hạ isolation chỉ để giảm latency mà không review correctness.

---

## 47. WAL và checkpoints

Theo dõi:

- WAL bytes/records;
- write/fsync timing;
- checkpoint requested/timed;
- checkpoint duration;
- buffers written;
- archive failures;
- disk usage;
- full-page writes.

Spike WAL có thể đến từ:

- bulk write;
- index creation;
- vacuum/rewrite;
- checkpoint behavior;
- full-page images;
- logical decoding.

WAL throughput là input capacity cho disk, network, replication, archive và restore.

---

## 48. Replication lag

Lag không phải một số duy nhất:

```text
write/flush/replay position lag
time since replay
apply queue
network
replica query conflicts
```

User-facing concern:

- stale read;
- failover data risk;
- replica unavailable;
- backup/CDC delay.

Byte lag có ý nghĩa khác ở workload WAL 1 MB/s và 1 GB/s.

Theo dõi both bytes và estimated catch-up time.

---

## 49. Replication slots

Slot giữ WAL cho consumer/replica.

Consumer chết:

```text
slot retained WAL tăng
  → disk đầy
  → primary outage
```

Theo dõi:

- active;
- retained bytes;
- restart/confirmed flush LSN;
- invalidation;
- consumer lag;
- disk headroom.

Không drop slot production chỉ vì disk pressure nếu chưa hiểu consumer và data-loss boundary.

---

## 50. Read replicas và routing

Đo:

- routing correctness;
- replica availability;
- lag/freshness;
- query latency;
- conflicts/cancellations;
- workload distribution;
- promotion readiness.

Contract:

```text
strong/read-your-writes
  → primary hoặc session-aware route

eventual reads
  → replica với freshness bound
```

Một endpoint “read-only” không tự đảm bảo application không gửi write hoặc cần fresh data.

---

## 51. Database proxy và pooler

PgBouncer/proxy tạo thêm layer:

- client connections;
- server connections;
- waiting clients;
- pool mode;
- transaction/session affinity;
- auth;
- routing;
- failover.

Theo dõi:

- utilization;
- wait time;
- transaction rate;
- bytes;
- reset errors;
- backend connect failures.

Transaction pooling có thể không tương thích session state, temp tables, prepared statements
hoặc advisory locks tùy cách dùng.

---

## 52. Memory

Không cộng cấu hình memory đơn giản rồi coi là usage thực.

Nguồn:

- shared buffer/cache;
- per-query sort/hash/work memory;
- maintenance;
- connection/session;
- OS page cache;
- extensions;
- replication.

Worst case:

```text
per-operation memory
× concurrent operations
× parallel workers
```

Theo dõi:

- RSS;
- memory pressure/OOM;
- temp spill;
- cache hit;
- concurrent sorts/hashes;
- connection count.

---

## 53. CPU

CPU cao có thể là:

- workload tăng;
- inefficient plan;
- parsing/planning;
- decompression/encryption;
- vacuum;
- spin/lock;
- context switching;
- extension/function.

Correlation:

```text
CPU by node/process
  ↔ top total-time queries
  ↔ query calls
  ↔ execution plans
  ↔ profiles
```

Scale CPU không sửa lock wait hoặc storage latency.

---

## 54. Storage I/O

Đo:

- latency;
- IOPS;
- throughput;
- queue depth;
- fsync;
- read/write mix;
- disk capacity;
- burst credits/throttling;
- filesystem errors.

Database view + OS/cloud storage:

```text
PostgreSQL DataFileRead wait tăng
  + device latency tăng
  + cache miss tăng
  → storage/read pressure có evidence
```

Không dùng CPU iowait đơn lẻ làm nguyên nhân.

---

## 55. Temporary files và spills

Spill do:

- sort/hash vượt memory;
- aggregate/join lớn;
- query plan;
- workload concurrency;
- temp table.

Theo dõi:

- temp files/bytes;
- query fingerprints;
- plan nodes;
- storage latency/capacity.

Tăng work memory toàn cluster có thể gây OOM khi concurrency cao.

Ưu tiên query/index/stats và workload-specific setting có kiểm soát.

---

## 56. Capacity planning

Model:

```text
transactions/s
× statements/transaction
× CPU/I/O/WAL per statement
× growth
× peak factor
× failover headroom
```

Theo dõi:

- data/index growth;
- connection demand;
- CPU/I/O headroom;
- WAL/archive;
- replication catch-up;
- vacuum window;
- backup/restore duration;
- storage expansion lead time.

Capacity không chỉ “disk còn bao nhiêu ngày”; maintenance và recovery có thể vi phạm trước khi
disk đầy.

---

## 57. High availability và failover

SLO cần:

- detection;
- promotion time;
- DNS/proxy route;
- client reconnect;
- transaction outcome ambiguity;
- replica freshness;
- old primary fencing;
- application recovery;
- failback.

Pool/driver behavior:

- stale connections;
- DNS caching;
- retries;
- connection storm;
- read-only errors.

Failover thành công khi critical transactions phục hồi đúng, không chỉ replica được promote.

---

## 58. Backup, restore và PITR

Theo dõi:

- backup success/duration/size;
- base backup age;
- WAL/binlog archive;
- encryption/key access;
- restore tests;
- recovery point/time;
- integrity validation.

```text
backup completed
  ≠ restore works
  ≠ RTO/RPO achieved
```

Restore drill:

1. isolated environment;
2. restore selected point;
3. validate schema/data;
4. run synthetic transactions;
5. measure RTO/RPO;
6. record evidence.

---

## 59. MySQL Performance Schema

MySQL Performance Schema quan sát:

- statements;
- stages;
- waits;
- transactions;
- connections;
- locks;
- memory;
- replication;
- status/config.

Instrumentation/consumers có overhead và cấu hình.

Top statement digest tương đương ý tưởng query fingerprint:

- count;
- total/avg latency;
- rows examined/sent;
- errors;
- temp tables;
- sort;
- lock time.

Không export raw digest text không sanitize vào high-cardinality labels.

---

## 60. MySQL `sys` schema và EXPLAIN

`sys` schema cung cấp views dễ đọc trên Performance Schema.

Use cases:

- statement analysis;
- I/O;
- memory;
- schema/index;
- host/user;
- InnoDB lock waits.

MySQL `EXPLAIN`, `EXPLAIN ANALYZE` và format JSON/TREE cần được dùng theo version/statement và
safety tương tự PostgreSQL: actual execution có side effects/cost.

Không port query catalog PostgreSQL sang MySQL theo tên giống nhau; semantics khác.

---

## 61. MySQL InnoDB locks và redo

Theo dõi:

- lock waits;
- blocking transactions;
- deadlocks;
- row/table locks;
- history list/MVCC pressure;
- buffer pool;
- redo log;
- flushing/checkpoint;
- pending I/O.

`sys.innodb_lock_waits` giúp tóm tắt waiter/blocker.

`SHOW ENGINE INNODB STATUS` hữu ích snapshot nhưng khó làm time series; kết hợp Performance
Schema/exporter.

Không tự động kill blocker chỉ vì transaction lâu; nó có thể là critical migration.

---

## 62. Alerts và dashboards

Page:

- user-facing DB operation SLO burn;
- connection acquisition failures;
- data corruption/checksum;
- replication/failover risk;
- disk/WAL critical;
- deadlock/lock impact;
- backup/restore critical failure.

Ticket/warning:

- unused/duplicate indexes;
- table growth;
- vacuum/analyze debt;
- capacity forecast;
- query regression.

Dashboard flow:

```text
application DB SLI
  → pool
  → server workload/waits
  → top query
  → locks
  → CPU/memory/I/O
  → WAL/replication/maintenance
```

---

## 63. Performance tuning workflow

```text
1. Define user-visible problem
2. Measure baseline
3. Isolate cohort/workload
4. Find dominant wait/resource/query
5. Form hypothesis
6. Predict measurable change
7. Test safely
8. Roll out canary
9. Compare before/after
10. Check side effects
11. Keep or rollback
12. Document/regression-test
```

Tuning examples:

- query rewrite;
- index;
- statistics;
- transaction scope;
- batching;
- pool;
- caching;
- partitioning;
- hardware.

Chọn theo evidence, không theo checklist internet.

---

## 64. Incident workshop, anti-patterns, checklist và câu hỏi

### Workshop: checkout DB latency

Symptom:

```text
checkout p99: 200 ms → 4 s
DB client spans: 150 ms → 3.8 s
pool acquire: stable 5 ms
```

Investigation:

1. `pg_stat_activity` cho thấy nhiều `Lock` waits.
2. `pg_blocking_pids` trỏ tới một migration transaction.
3. Migration tạo index không dùng phương thức online/concurrent phù hợp.
4. Rollback migration giải phóng lock.
5. SLI phục hồi, queue drain.
6. Plan mới dùng safer migration, lock timeout, canary và maintenance guardrail.

### Anti-patterns

- Alert chỉ dựa CPU > 80%.
- Tăng pool khi query chậm.
- Log mọi SQL và parameters.
- Raw SQL là metric label/span name.
- `EXPLAIN ANALYZE` write trực tiếp production.
- Kill mọi long transaction.
- Tạo index cho mỗi slow query.
- Xóa index chỉ vì scan count bằng zero sau reset.
- Dùng cache-hit ratio như health score duy nhất.
- Tăng memory global để sửa spill.
- Reset stats trong incident.
- Xóa replication slot để giải phóng disk mà không hiểu consumer.
- Backup success được coi là restore proof.
- Replica lag chỉ đo seconds/bytes một chiều.
- Dashboard trộn OLTP và batch.

### Production checklist

- [ ] Database capabilities có SLO theo workload.
- [ ] Application và server latency được đo riêng.
- [ ] Connection pool có active/idle/pending/acquire metrics.
- [ ] Tổng pool max tính cả autoscaling và reserve.
- [ ] Query summaries/fingerprints bounded.
- [ ] SQL text/parameters có privacy policy.
- [ ] OTel database convention version được ghi.
- [ ] Exporter dùng least privilege/TLS/secret file.
- [ ] PostgreSQL stats reset được theo dõi.
- [ ] `pg_stat_activity`/waits/locks có dashboard.
- [ ] `pg_stat_statements` sizing/eviction/overhead được theo dõi.
- [ ] Slow-query logging có threshold/sampling/retention.
- [ ] `EXPLAIN ANALYZE` có safety workflow.
- [ ] Planner estimate error được xem trước khi index.
- [ ] Index cost bao gồm writes/WAL/storage.
- [ ] Autovacuum/analyze/wraparound được theo dõi.
- [ ] Long/idle transactions có owner/alert.
- [ ] Root blocker được tìm trước khi terminate.
- [ ] Deadlock retries idempotent/bounded.
- [ ] WAL/checkpoint/archive có capacity alerts.
- [ ] Replication lag gắn freshness/failover.
- [ ] Slots có retained-WAL guardrail.
- [ ] DB/proxy/pool/client timeouts được phối hợp.
- [ ] CPU/memory/I/O được correlate với workload.
- [ ] Backup được restore test theo RTO/RPO.
- [ ] Performance changes có canary và before/after.

### Câu hỏi tự kiểm tra

1. Vì sao client và server latency khác nhau?
2. Database SLO cần tách workload classes thế nào?
3. Pool active 100% có luôn là incident không?
4. Pool quá lớn gây tác động gì?
5. Connection leak khác slow query thế nào?
6. OTel database span nên đặt tên bằng gì?
7. Vì sao raw SQL không nên là metric label/span name?
8. `db.query.summary` khác `db.query.text` thế nào?
9. SQL commenter có trade-off gì?
10. PostgreSQL cumulative stats có freshness/reset caveat nào?
11. `pg_stat_activity.state` và `wait_event` liên hệ ra sao?
12. `pg_stat_io` cần kết hợp OS telemetry vì sao?
13. Top total query time khác top mean time thế nào?
14. `pg_stat_statements` có coverage limitation gì?
15. `EXPLAIN ANALYZE` nguy hiểm ở đâu?
16. Estimated/actual rows lệch chỉ ra vấn đề gì?
17. Sequential scan khi nào hợp lý?
18. Index tăng write cost thế nào?
19. Long transaction ảnh hưởng vacuum ra sao?
20. Vì sao phải tìm root blocker?
21. Deadlock nên fix bằng ordering/retry thế nào?
22. WAL volume ảnh hưởng những subsystem nào?
23. Replication lag nên đo theo những chiều nào?
24. Slot inactive có thể làm primary đầy disk ra sao?
25. Backup success chưa chứng minh điều gì?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### PostgreSQL 18

- [PostgreSQL monitoring statistics](https://www.postgresql.org/docs/current/monitoring-stats.html)
- [PostgreSQL `pg_stat_statements`](https://www.postgresql.org/docs/current/pgstatstatements.html)
- [PostgreSQL viewing locks](https://www.postgresql.org/docs/current/monitoring-locks.html)
- [PostgreSQL using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)
- [PostgreSQL routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)
- [PostgreSQL monitoring disk usage](https://www.postgresql.org/docs/current/diskusage.html)
- [PostgreSQL high availability, load balancing and replication](https://www.postgresql.org/docs/current/high-availability.html)

### MySQL 8.4 LTS

- [MySQL Performance Schema](https://dev.mysql.com/doc/refman/8.4/en/performance-schema.html)
- [MySQL sys schema](https://dev.mysql.com/doc/refman/8.4/en/sys-schema.html)
- [MySQL execution plans](https://dev.mysql.com/doc/refman/8.4/en/execution-plan-information.html)
- [MySQL `sys.innodb_lock_waits`](https://dev.mysql.com/doc/refman/8.4/en/sys-innodb-lock-waits.html)
- [MySQL InnoDB monitors](https://dev.mysql.com/doc/refman/8.4/en/innodb-monitors.html)

### OpenTelemetry, exporters và connection pool

- [OpenTelemetry database semantic conventions](https://opentelemetry.io/docs/specs/semconv/db/)
- [OpenTelemetry database client spans](https://opentelemetry.io/docs/specs/semconv/db/database-spans/)
- [Prometheus PostgreSQL exporter](https://github.com/prometheus-community/postgres_exporter)
- [Prometheus MySQL exporter](https://github.com/prometheus/mysqld_exporter)
- [HikariCP](https://github.com/brettwooldridge/HikariCP)

### Chủ đề tiếp theo

Sau Database Observability & Performance Engineering, chủ đề mở rộng tiếp theo là:

> [**Redis & Cache Observability**](redis_cache_observability.md) – hit ratio, latency,
> evictions, hot keys, memory fragmentation, replication, persistence và cache failure modes.

---

*Cập nhật lần cuối: 2026-07-30*
