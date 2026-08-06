# PostgreSQL Performance & Autovacuum

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này không đưa ra một bộ tham số
> “tối ưu cho mọi server”. Mục tiêu là xây mental model, đo đúng bottleneck, thay đổi
> có giả thuyết và giữ VACUUM/ANALYZE theo kịp workload.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Architecture & Storage](../fundamentals/architecture_storage.md) ·
[Transactions, MVCC & Locking](../fundamentals/transactions_mvcc.md) ·
[Indexing & Query Planner](../fundamentals/indexing_planner.md) ·
[Advanced SQL](../fundamentals/advanced_sql.md).

---

## 1. Performance là budget, không phải một con số latency

Một database có thể nhanh ở tải thấp nhưng sụp khi concurrency tăng. Trước khi tune,
phải định nghĩa ít nhất:

- throughput mục tiêu: transaction/request mỗi giây;
- latency SLO theo percentile, ví dụ p50/p95/p99;
- concurrency và queue-depth ở peak;
- freshness/replication lag cho read replica;
- RPO/RTO và durability không được hy sinh;
- chi phí CPU, RAM, IOPS, storage và vận hành.

Latency trung bình không thể hiện tail latency. Một batch 30 giây có thể gần như không
đổi average nhưng vẫn làm request online vượt timeout.

```text
workload → queue → connection → lock/CPU/memory/I/O → response
             ↑                                  │
             └──────── backpressure ────────────┘
```

Tối ưu đúng nghĩa là đạt budget với headroom, không phải làm một query demo nhanh nhất.

---

## 2. Bắt đầu từ workload model

Ghi lại workload trước khi đổi cấu hình:

| Thuộc tính | Ví dụ cần biết |
|---|---|
| Query mix | 80% point read, 15% write, 5% report |
| Data shape | row count, width, skew, working set, growth/day |
| Concurrency | active, queued, pool size, background job |
| Transaction | statement/transaction, thời gian giữ lock |
| Access pattern | random/sequential, hot key, time range |
| Durability | synchronous commit, replica/backup requirement |
| Change event | deploy, migration, load, failover, statistics reset |

Cùng một cấu hình có thể tốt cho OLTP và tệ cho analytics. “Server có 64 GB RAM” chưa đủ
để chọn `shared_buffers` hay `work_mem` nếu chưa biết concurrency và plan shape.

---

## 3. Quy trình evidence-driven tuning

```text
1. Xác nhận triệu chứng và cửa sổ thời gian
2. So sánh baseline tốt với thời điểm xấu
3. Phân loại: queue/lock/CPU/memory/I/O/WAL/vacuum/plan
4. Tìm query/table/operation đóng góp lớn nhất
5. Đặt một giả thuyết có thể bác bỏ
6. Thử thay đổi nhỏ trong môi trường đại diện
7. Đo lại SLO, throughput, resource và side effect
8. Giữ hoặc rollback; ghi lại evidence
```

Không đổi đồng thời index, pool, memory và autovacuum rồi tuyên bố “đã nhanh”. Khi đó
không biết thay đổi nào có tác dụng hoặc tạo regression.

---

## 4. Counter tích lũy phải đọc theo delta

Nhiều view `pg_stat_*` là counter từ lần reset, không phải rate hiện tại. Luôn thu hai
snapshot và tính:

```text
rate = (counter_t2 - counter_t1) / (t2 - t1)
```

Kiểm tra mốc reset:

```sql
SELECT datname, stats_reset
FROM pg_stat_database
WHERE datname = current_database();

SELECT stats_reset FROM pg_stat_io LIMIT 1;
SELECT stats_reset FROM pg_stat_wal;
SELECT stats_reset FROM pg_stat_checkpointer;
```

Các view có thể có phạm vi khác nhau: database, cluster, table hoặc statement. Không chia
hai counter có cửa sổ reset khác nhau. Reset chỉ khi có runbook vì sẽ xóa baseline mà
đội vận hành đang cần.

---

## 5. Statistics có thể bị cache trong transaction

Tùy `stats_fetch_consistency`, lần đọc statistics đầu tiên có thể được cache tới cuối
transaction. Một dashboard query chạy trong transaction dài có thể tự nhìn dữ liệu cũ.

```sql
SHOW stats_fetch_consistency;
SELECT pg_stat_clear_snapshot();
```

Query chẩn đoán nên chạy trong transaction ngắn hoặc autocommit. `pg_stat_activity` có
một số trường trạng thái hiện tại, còn cumulative counters có độ trễ và tính xấp xỉ.

---

## 6. Baseline cấu hình phải ghi cả nguồn giá trị

```sql
SELECT
    name,
    setting,
    unit,
    source,
    sourcefile,
    sourceline,
    pending_restart
FROM pg_settings
WHERE name IN (
    'max_connections',
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'effective_cache_size',
    'max_wal_size',
    'checkpoint_timeout',
    'checkpoint_completion_target',
    'autovacuum_worker_slots',
    'autovacuum_max_workers',
    'autovacuum_naptime'
)
ORDER BY name;
```

`SHOW` chỉ cho biết effective value; `pg_settings` còn chỉ ra override đến từ file,
command line, database, role hay session và có cần restart không.

---

## 7. Connection pool là admission control

PostgreSQL dùng backend process cho mỗi connection. Quá nhiều connection đồng thời làm:

- tăng process/session memory;
- tăng context switching;
- nhiều query cùng tranh CPU/I/O/lock;
- tail latency tăng dù throughput không tăng;
- maintenance worker khó có headroom.

Đếm client backend:

```sql
SELECT
    datname,
    state,
    count(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY datname, state
ORDER BY datname, state;
```

Pool size không nên bằng `max_connections` cho mỗi application instance. Tổng pool của
tất cả instance mới là tải thật; chừa connection cho operator, migration, replication
và sự cố.

---

## 8. Active session lớn hơn CPU không tự tạo thêm CPU

```sql
SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions
FROM pg_stat_activity
WHERE state = 'active'
  AND pid <> pg_backend_pid()
GROUP BY wait_event_type, wait_event
ORDER BY sessions DESC;
```

Diễn giải:

- `wait_event` null: backend có thể đang chạy CPU, nhưng cần đối chiếu OS;
- `Lock`: contention logic/transaction;
- `IO`: chờ storage hoặc cache miss;
- `Client`: thường chờ client gửi/nhận, không đồng nghĩa database bận CPU;
- nhiều active session cùng lúc: có thể là queue đã tràn vào database.

PostgreSQL view không thay OS telemetry. CPU run queue, memory pressure, swap, disk
latency/queue và network vẫn phải đo tại host/cloud layer.

---

## 9. Tìm query/transaction giữ tài nguyên lâu

```sql
SELECT
    pid,
    usename,
    application_name,
    state,
    wait_event_type,
    wait_event,
    clock_timestamp() - xact_start AS xact_age,
    clock_timestamp() - query_start AS query_age,
    left(query, 160) AS query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND (xact_start IS NOT NULL OR state = 'active')
ORDER BY xact_start NULLS LAST, query_start;
```

`query_start` của session `idle in transaction` không phải thời điểm transaction bắt đầu;
hãy đọc `xact_start`. Transaction lâu vừa giữ lock/snapshot vừa cản vacuum cleanup.

---

## 10. Timeout là resource boundary

Các server-side boundary phổ biến:

```sql
SHOW statement_timeout;
SHOW lock_timeout;
SHOW idle_in_transaction_session_timeout;
SHOW transaction_timeout;
```

`connect_timeout` là connection parameter phía client, không phải server GUC; hãy kiểm tra
datasource/connection string. Bốn GUC phía trên có thể đặt theo role/database/session.

Không đặt `statement_timeout` thấp hơn latency hợp lệ của migration/batch cho mọi role.
Dùng role riêng và override có chủ đích; timeout phải đi cùng retry/idempotency phù hợp.

---

## 11. Cài `pg_stat_statements` đúng hai lớp

Module cần shared memory lúc server start:

```conf
shared_preload_libraries = 'pg_stat_statements'
compute_query_id = on
```

Sau restart, tạo extension trong từng database cần truy vấn view:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

Module track toàn cluster, nhưng object extension/view cần có trong database đang kết
nối. Chỉ superuser hoặc role có `pg_read_all_stats` mới xem đầy đủ query text/query ID của
user khác.

---

## 12. Query đứng đầu theo tổng tải khác query chậm nhất

Top tổng execution time:

```sql
SELECT
    queryid,
    calls,
    round(total_exec_time::numeric, 1) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    round((total_exec_time / sum(total_exec_time) OVER () * 100)::numeric, 1)
        AS pct_exec_time,
    rows,
    left(query, 180) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY total_exec_time DESC
LIMIT 20;
```

Một query 5 ms chạy một triệu lần có thể đáng tối ưu hơn query report 20 giây chạy mỗi
tuần. Xếp hạng ít nhất theo `total_exec_time`, `calls`, `mean/max`, rows, I/O, temp và WAL.

---

## 13. `pg_stat_statements` chuẩn hóa literal nhưng không phải tracing

Một entry được phân biệt theo database, user, query ID và top-level state; literal thường
được chuẩn hóa. Hệ quả:

- không thấy từng parameter value chậm;
- mean/stddev không thay percentile distribution;
- không biết request/trace nào gọi query;
- query ID có thể đổi sau major upgrade hoặc thay đổi parse tree;
- statement ít chạy có thể bị evict khi vượt `pg_stat_statements.max`.

Theo dõi eviction:

```sql
SELECT dealloc, stats_reset
FROM pg_stat_statements_info;
```

Nếu `dealloc` tăng nhanh, xem lại cardinality statement, query generation và
`pg_stat_statements.max`; tăng max dùng thêm shared memory.

---

## 14. Tách planning time và execution time

`pg_stat_statements.track_planning` mặc định tắt vì có overhead, nhất là nhiều session
cùng cập nhật entry giống nhau. Khi có bằng chứng planning là vấn đề, bật có giới hạn rồi
đọc:

```sql
SELECT
    queryid,
    plans,
    calls,
    round(total_plan_time::numeric, 1) AS plan_ms,
    round(total_exec_time::numeric, 1) AS exec_ms,
    left(query, 160) AS query
FROM pg_stat_statements
WHERE total_plan_time > 0
ORDER BY total_plan_time DESC
LIMIT 20;
```

Planning cao có thể đến từ query quá phức tạp, quá nhiều partition, prepared-statement
behavior hoặc churn của connection không tái sử dụng plan.

---

## 15. Đọc I/O, temp và WAL theo statement

```sql
SELECT
    queryid,
    calls,
    shared_blks_hit,
    shared_blks_read,
    temp_blks_read,
    temp_blks_written,
    pg_size_pretty(wal_bytes) AS wal_generated,
    round(total_exec_time::numeric, 1) AS total_ms,
    left(query, 160) AS query
FROM pg_stat_statements
ORDER BY temp_blks_written DESC, shared_blks_read DESC
LIMIT 20;
```

Block hit không có nghĩa CPU miễn phí; scan hàng triệu cached block vẫn tốn CPU và làm
cache churn. `wal_bytes` giúp tìm write amplification. Temp block chỉ ra spill, nhưng
không chứng minh tăng global `work_mem` là lời giải an toàn.

---

## 16. Slow-query logging phải kiểm soát volume và secret

Ví dụ baseline, giá trị thật phải theo SLO:

```conf
log_min_duration_statement = '1s'
log_min_duration_sample = '250ms'
log_statement_sample_rate = 0.1
log_parameter_max_length = 256
log_temp_files = '64MB'
log_lock_waits = on
deadlock_timeout = '1s'
```

`log_min_duration_statement` luôn log statement vượt ngưỡng của nó; ngưỡng sample thấp
hơn chỉ log theo tỷ lệ. Parameter có thể chứa PII/secret, log volume có thể tự tạo I/O
incident. Thiết kế redaction, retention và quyền đọc log trước khi bật rộng.

---

## 17. `auto_explain` là công cụ có overhead

`auto_explain` bắt plan của query chậm mà không cần tái hiện thủ công:

```conf
session_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '2s'
auto_explain.log_analyze = on
auto_explain.log_buffers = on
auto_explain.log_timing = off
auto_explain.sample_rate = 0.1
```

Khi `log_analyze=on`, instrumentation xảy ra cho mọi statement trong session đã load module,
kể cả statement cuối cùng không vượt ngưỡng để được log; per-node timing có thể rất đắt.
Bắt đầu bằng sample nhỏ, `log_timing=off`, giới hạn môi trường/session và đo overhead. Plan
log cũng có thể lộ SQL/parameter.

---

## 18. Cache hit ratio không phải KPI độc lập

```sql
SELECT
    datname,
    blks_hit,
    blks_read,
    round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS hit_pct
FROM pg_stat_database
WHERE datname = current_database();
```

Tỷ lệ này chỉ nói shared-buffer hit, không biết read có chạm physical disk hay được OS
page cache phục vụ. Analytics sequential scan có hit ratio thấp nhưng vẫn đúng; OLTP point
lookup giảm hit đột ngột mới đáng điều tra. Luôn dùng delta và đối chiếu latency/bytes I/O.

---

## 19. PostgreSQL 18 `pg_stat_io` cho biết byte và nơi phát I/O

```sql
SELECT
    backend_type,
    object,
    context,
    pg_size_pretty(sum(read_bytes)) AS read_bytes,
    pg_size_pretty(sum(write_bytes)) AS write_bytes,
    pg_size_pretty(sum(extend_bytes)) AS extend_bytes,
    sum(evictions) AS evictions,
    sum(fsyncs) AS fsyncs
FROM pg_stat_io
GROUP BY backend_type, object, context
ORDER BY sum(coalesce(read_bytes, 0) + coalesce(write_bytes, 0)) DESC;
```

PostgreSQL 18 thêm `read_bytes`, `write_bytes`, `extend_bytes` và các row I/O cho WAL.
Context `normal`, `bulkread`, `bulkwrite`, `vacuum`, `init` giúp phân biệt nguồn tải.
Nhiều client-backend write/fsync có thể cho thấy checkpointer/shared-buffer behavior cần
điều tra, nhưng phải xem delta và OS storage cùng lúc.

---

## 20. I/O timing mặc định có thể bằng zero

```sql
SHOW track_io_timing;
SHOW track_wal_io_timing;
```

`read_time`, `write_time`, `fsync_time` chỉ có ý nghĩa khi tracking tương ứng đã bật trong
toàn cửa sổ đo. Bật timing có overhead phụ thuộc platform; benchmark trước. Counter bytes
và operations vẫn hữu ích khi timing tắt.

Đừng tính latency bằng cumulative time/cumulative operations nếu hai counter có `NULL`,
reset khác thời điểm hoặc workload trộn nhiều loại I/O.

---

## 21. Temp file là tín hiệu, không phải mệnh lệnh tăng RAM

```sql
SELECT datname, temp_files, pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();
```

Temp I/O có thể đến từ sort, hash, materialize hoặc query khác. Quy trình:

1. dùng `pg_stat_statements`/`log_temp_files` tìm query;
2. đọc `EXPLAIN (ANALYZE, BUFFERS)` để biết node spill;
3. giảm row/width, sửa join/cardinality/index trước;
4. chỉ tăng memory cục bộ cho workload đã đo.

Một temp file lớn cho batch hợp lệ có thể tốt hơn hàng trăm query đồng thời giữ nhiều RAM.

---

## 22. `work_mem` nhân theo node, worker và concurrency

Mental budget:

```text
peak query memory ≈ active sessions
                  × concurrent memory-heavy nodes
                  × workers per query
                  × work_mem
                  × hash_mem_multiplier khi là hash
```

Đây là upper-bound mental model, không phải công thức allocator chính xác. Ví dụ đặt
`work_mem=256MB` global có thể gây OOM trước khi mọi query dùng đủ giá trị đó.

Ưu tiên override theo transaction/job:

```sql
BEGIN;
SET LOCAL work_mem = '128MB';
-- report đã benchmark
COMMIT;
```

`SET LOCAL` tự hết khi transaction kết thúc, giảm rủi ro session pool giữ cấu hình.

---

## 23. `shared_buffers` phối hợp với OS cache

PostgreSQL dùng shared buffers nhưng cũng dựa vào page cache của hệ điều hành. Tài liệu
đưa 25% RAM làm điểm bắt đầu thường gặp cho dedicated server lớn hơn 1 GB, không phải
giá trị tối ưu phổ quát; trên khoảng 40% thường khó tốt hơn cấu hình nhỏ hơn.

Khi đổi `shared_buffers`, phải đo lại:

- OS free/cache và swap;
- eviction, client-backend read/write;
- checkpoint/WAL và `max_wal_size`;
- working-set hit, p95/p99;
- memory cho connection, maintenance và kernel.

Setting này cần restart. Không lấy “cache hit 99%” làm bằng chứng duy nhất để tăng tiếp.

---

## 24. `effective_cache_size` không cấp phát memory

`effective_cache_size` là ước lượng cache mà một query có thể hưởng từ PostgreSQL và OS,
dùng trong cost model. Nó không reserve RAM và không phải giới hạn.

```sql
SHOW effective_cache_size;
```

Đặt quá thấp có thể khiến planner đánh giá index access đắt; quá cao có thể khiến planner
tin random access được cache nhiều hơn thực tế. Chọn từ memory budget và working set, rồi
xác minh bằng plan/production evidence.

---

## 25. `maintenance_work_mem` cũng có concurrency

Setting này phục vụ VACUUM, CREATE INDEX, ALTER TABLE ADD FOREIGN KEY và maintenance
khác. Autovacuum worker có thể dùng `autovacuum_work_mem` riêng.

```sql
SHOW maintenance_work_mem;
SHOW autovacuum_work_mem;
SHOW autovacuum_max_workers;
```

Không nhân mù `maintenance_work_mem × workers` như allocation chắc chắn, nhưng phải giữ
budget cho nhiều maintenance process đồng thời. Một manual index build lớn và nhiều
autovacuum worker có thể tranh RAM/I/O với traffic online.

---

## 26. Huge pages và Transparent Huge Pages là hai chuyện khác

```sql
SHOW huge_pages;
SHOW huge_pages_status;
SHOW shared_memory_size;
SHOW shared_memory_size_in_huge_pages;
```

Explicit huge pages có thể giảm page-table/TLB overhead cho shared memory trên platform hỗ
trợ. `huge_pages=on` làm server không start nếu không cấp được; `try` có fallback.

Không đồng nhất với Transparent Huge Pages của Linux, vốn có behavior/overhead riêng.
Thay đổi kernel phải được benchmark và có cách rollback, không sao chép tuning guide cũ.

---

## 27. Parallel query bị giới hạn bởi worker budget

PostgreSQL có thể plan nhiều worker nhưng launch ít hơn:

```sql
SELECT
    datname,
    parallel_workers_to_launch,
    parallel_workers_launched
FROM pg_stat_database
WHERE datname = current_database();
```

Đối chiếu:

```sql
SHOW max_worker_processes;
SHOW max_parallel_workers;
SHOW max_parallel_workers_per_gather;
SHOW max_parallel_maintenance_workers;
```

Parallelism tăng throughput một query nhưng có thể giảm throughput toàn hệ thống khi nhiều
query tranh CPU/I/O. `Workers Planned` khác `Workers Launched`; đọc cả hai trong plan.

---

## 28. Checkpoint quá dày tạo I/O burst và full-page images

PostgreSQL 18 tách statistic checkpointer:

```sql
SELECT
    num_timed,
    num_requested,
    num_done,
    write_time,
    sync_time,
    buffers_written,
    stats_reset
FROM pg_stat_checkpointer;
```

Dùng delta. `num_requested` tăng nhanh so với timed checkpoint thường gợi ý workload lấp
WAL trước timeout. Server log `checkpoints are occurring too frequently` là evidence xem
lại `max_wal_size`, không phải lý do tăng vô hạn.

---

## 29. Ba knob checkpoint phải nhìn cùng nhau

```sql
SHOW checkpoint_timeout;
SHOW checkpoint_completion_target;
SHOW max_wal_size;
```

- `checkpoint_timeout`: khoảng tối đa giữa automatic checkpoints;
- `max_wal_size`: soft limit kích hoạt checkpoint theo WAL volume;
- `checkpoint_completion_target`: trải write trên phần lớn interval, mặc định 0.9.

Tăng timeout/max WAL có thể giảm checkpoint frequency nhưng tăng disk footprint và crash
recovery time. Giảm completion target thường gom I/O nhanh hơn và tạo burst. Bảo đảm archive
và replication slot không phải nguyên nhân giữ WAL trước khi chỉ tăng disk/config.

---

## 30. WAL rate là capacity signal

```sql
SELECT
    wal_records,
    wal_fpi,
    pg_size_pretty(wal_bytes) AS wal_bytes,
    wal_buffers_full,
    stats_reset
FROM pg_stat_wal;
```

Lấy hai snapshot để tính WAL bytes/second và bytes/transaction. WAL tăng có thể đến từ:

- bulk write/update/delete;
- quá nhiều index;
- full-page image sau checkpoint;
- non-HOT update;
- maintenance/rewrite;
- logical decoding/replication workload.

PostgreSQL 18 chuyển WAL write/sync timing sang `pg_stat_io`; đừng dùng tên cột
`wal_write_time` cũ trong `pg_stat_wal`.

---

## 31. VACUUM không phải DELETE và không phải shrink mặc định

Plain `VACUUM`:

- dọn row version không còn cần;
- dọn index entry tương ứng;
- cập nhật visibility map/free-space map;
- freeze tuple để chống XID wraparound;
- làm space tái sử dụng trong relation.

Thông thường nó không trả file space về OS. `VACUUM FULL` rewrite relation, cần extra disk
và `ACCESS EXCLUSIVE`; autovacuum không bao giờ tự chạy `VACUUM FULL`.

Mục tiêu là vacuum thường xuyên để relation đạt steady state, không giữ file nhỏ tuyệt đối.

---

## 32. Công thức trigger autovacuum cho UPDATE/DELETE

PostgreSQL 18 dùng:

```text
vacuum threshold = min(
    autovacuum_vacuum_max_threshold,
    autovacuum_vacuum_threshold
      + autovacuum_vacuum_scale_factor × reltuples
)
```

Autovacuum so estimated obsolete tuples từ cumulative statistics với threshold này.
Table 500 triệu row với scale factor 20% có thể chờ quá lâu; tune per table. PostgreSQL 18
có max threshold để đặt trần số row thay đổi trước trigger.

Giá trị `autovacuum_vacuum_max_threshold = -1` có nghĩa không áp dụng nhánh max; lúc đó
threshold chỉ còn base cộng scale factor.

Counter và `reltuples` đều xấp xỉ/eventually consistent; công thức là scheduling model,
không phải guarantee vacuum bắt đầu chính xác tại một row.

---

## 33. Insert-only table vẫn cần vacuum

Insert trigger:

```text
insert threshold = autovacuum_vacuum_insert_threshold
                 + autovacuum_vacuum_insert_scale_factor
                 × reltuples
                 × percent pages not frozen
```

Insert-only table gần như không có dead tuple nhưng vẫn cần:

- freeze tuple chống wraparound;
- cập nhật visibility map để index-only scan hiệu quả;
- giảm work của vacuum tương lai.

Với append-only table, có thể cân nhắc giảm `autovacuum_freeze_min_age` per table sau khi
đo workload; freeze sớm cũng tạo work/WAL nên không đặt bằng cảm tính.

---

## 34. ANALYZE có trigger và mục tiêu khác VACUUM

```text
analyze threshold = autovacuum_analyze_threshold
                  + autovacuum_analyze_scale_factor × reltuples
```

Nó so với tổng row insert/update/delete từ lần analyze. `ANALYZE` lấy sample và cập nhật
planner statistics; nó không dọn dead tuple.

Sau bulk load hoặc distribution shift lớn:

```sql
ANALYZE VERBOSE app.orders;
```

PostgreSQL 18 bổ sung CPU, WAL và average-read information trong `ANALYZE VERBOSE`, hữu
ích để phân biệt sampling work với I/O bottleneck.

---

## 35. Tune per table trước khi thay global

Ví dụ cho table rất lớn và churn cao; số thật phải tính từ write rate/SLO:

```sql
ALTER TABLE app.orders SET (
    autovacuum_vacuum_threshold = 1000,
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_max_threshold = 200000,
    autovacuum_analyze_threshold = 1000,
    autovacuum_analyze_scale_factor = 0.005
);
```

Xem storage parameters:

```sql
SELECT relname, reloptions
FROM pg_class
WHERE oid = 'app.orders'::regclass;
```

Per-table setting cô lập rủi ro và phản ánh churn khác nhau. Reset về global bằng
`ALTER TABLE ... RESET (parameter_name)`.

---

## 36. Worker đủ số lượng nhưng còn phải đủ tốc độ

```sql
SHOW autovacuum_worker_slots;
SHOW autovacuum_max_workers;
SHOW autovacuum_naptime;
SHOW autovacuum_vacuum_cost_delay;
SHOW autovacuum_vacuum_cost_limit;
SHOW autovacuum_work_mem;
```

Nhiều table lớn cùng eligible có thể chiếm hết workers, khiến table nhỏ nóng phải chờ.
Tăng worker mà giữ tổng I/O budget có thể cải thiện fairness nhưng không tự tạo thêm IOPS.

PostgreSQL 18 tách `autovacuum_worker_slots` làm số slot dự trữ lúc server start;
`autovacuum_max_workers` có thể điều chỉnh trong giới hạn đó mà không cần restart. Đặt max
cao hơn slots không tạo thêm worker.

Cost limit/delay được cân bằng giữa worker dùng global setting. Worker có per-table cost
setting không tham gia balancing theo cách đó. Theo dõi backlog trước và sau thay đổi.

---

## 37. PostgreSQL 18 hiển thị vacuum/analyze time rõ hơn

```sql
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    last_autovacuum,
    last_autoanalyze,
    total_autovacuum_time,
    total_autoanalyze_time
FROM pg_stat_user_tables
ORDER BY total_autovacuum_time DESC NULLS LAST
LIMIT 30;
```

Các cột total time mới của PostgreSQL 18 bao gồm cả thời gian ngủ do cost delay. Vì vậy
“vacuum mất lâu” có thể là throttling có chủ đích, I/O chậm, index cleanup lớn hoặc bị
gián đoạn; không suy luận từ duration đơn lẻ.

---

## 38. `track_cost_delay_timing` giải thích vacuum bị throttle

```sql
SHOW track_cost_delay_timing;
```

Khi bật, PostgreSQL 18 báo `delay_time` trong progress view, verbose output và autovacuum
log. Tracking có overhead nên bật theo nhu cầu và benchmark.

```sql
SELECT
    pid,
    relid::regclass AS relation,
    phase,
    heap_blks_total,
    heap_blks_scanned,
    heap_blks_vacuumed,
    indexes_total,
    indexes_processed,
    delay_time
FROM pg_stat_progress_vacuum;
```

Progress là snapshot theo phase; phần trăm heap scan không đại diện toàn bộ thời gian index
cleanup/truncation.

---

## 39. Log autovacuum để biết nó chạy, skip hay bị chậm

```conf
log_autovacuum_min_duration = '1s'
```

`0` log mọi action, `-1` tắt. Chọn threshold để đủ evidence mà không ngập log. Log có thể
cho thấy tuples removed/remain, pages, index scan, read/write rate, WAL, freeze age và lý
do skip lock.

PostgreSQL 18 bổ sung delay time và WAL-buffer-full detail trong verbose/autovacuum output.
Parse log theo version; đừng xây parser dựa vào một chuỗi text bất biến mãi mãi.

---

## 40. Autovacuum thường nhường DDL, wraparound vacuum thì không

Autovacuum giữ `SHARE UPDATE EXCLUSIVE`. Khi command cần lock xung đột, autovacuum bình
thường có thể bị interrupt để nhường. Nhưng worker có query suffix
`(to prevent wraparound)` không tự bị interrupt như vậy.

```sql
SELECT pid, query, wait_event_type, wait_event
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker';
```

DDL/ANALYZE xung đột lặp lại có thể khiến autovacuum không bao giờ hoàn thành. Nếu đã vào
wraparound emergency, ưu tiên bảo toàn database hơn lịch deploy.

---

## 41. Theo dõi XID và MultiXact age trước khi thành sự cố

Database age:

```sql
SELECT
    datname,
    age(datfrozenxid) AS xid_age,
    mxid_age(datminmxid) AS multixact_age
FROM pg_database
ORDER BY xid_age DESC;
```

Table age:

```sql
SELECT
    c.oid::regclass AS relation,
    greatest(age(c.relfrozenxid), age(t.relfrozenxid)) AS xid_age,
    greatest(mxid_age(c.relminmxid), mxid_age(t.relminmxid)) AS multixact_age,
    pg_total_relation_size(c.oid) AS total_bytes
FROM pg_class AS c
LEFT JOIN pg_class AS t ON t.oid = c.reltoastrelid
WHERE c.relkind IN ('r', 'm')
ORDER BY xid_age DESC
LIMIT 30;
```

Alert theo tỷ lệ so với freeze limits và time-to-exhaustion dựa trên transaction rate,
không chỉ một threshold age tĩnh. Query lấy tuổi lớn hơn giữa main relation và TOAST;
MultiXact liên quan row locks cũng có lifecycle riêng.

---

## 42. Long transaction là kẻ giữ chân cleanup

Tìm backend có snapshot/transaction cũ:

```sql
SELECT
    pid,
    usename,
    application_name,
    state,
    backend_xmin,
    clock_timestamp() - xact_start AS xact_age,
    left(query, 160) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
```

Ngoài client transaction, kiểm tra prepared transaction, replication slot và standby
feedback khi xmin bị giữ. Không terminate session chỉ vì nó “lâu”; xác định owner, impact,
rollback cost và idempotency trước.

---

## 43. `n_dead_tup` là estimate, không phải phép đo bloat

```sql
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    n_mod_since_analyze,
    n_ins_since_vacuum,
    last_autovacuum,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 30;
```

`n_dead_tup` giúp ưu tiên điều tra nhưng:

- là estimate;
- dead tuple chưa đồng nghĩa file space lãng phí không tái dùng được;
- bloat có thể nằm ở heap, index hoặc TOAST;
- table có free space lớn nhưng sắp tái sử dụng không nhất thiết cần shrink.

Bloat là vấn đề khi gây scan/cache/I/O cost hoặc disk risk, không chỉ vì một tỷ lệ đẹp xấu.

---

## 44. Đo kích thước theo heap, index và TOAST

```sql
SELECT
    c.oid::regclass AS relation,
    pg_size_pretty(pg_relation_size(c.oid)) AS heap,
    pg_size_pretty(pg_indexes_size(c.oid)) AS indexes,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'app'
  AND c.relkind IN ('r', 'm')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 30;
```

`pg_total_relation_size` gồm index và TOAST liên quan. So delta theo ngày/tuần với row
count/write volume. Kích thước tăng cùng business data không phải bloat.

---

## 45. `pgstattuple` cho phép kiểm tra sâu có chủ đích

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;

SELECT *
FROM pgstattuple_approx('app.orders'::regclass);
```

`pgstattuple_approx` giảm chi phí cho table hỗ trợ approximation; `pgstattuple` scan đầy
đủ và có thể tốn I/O. Với B-tree:

```sql
SELECT *
FROM pgstatindex('app.orders_customer_created_idx'::regclass);
```

Extension có yêu cầu quyền; chạy trên object được chọn, ngoài peak và đo impact. Không scan
toàn cluster mỗi phút chỉ để vẽ dashboard bloat.

---

## 46. HOT và fillfactor là trade-off write/read/storage

Theo dõi HOT ratio bằng delta:

```sql
SELECT
    relname,
    n_tup_upd,
    n_tup_hot_upd,
    round(100.0 * n_tup_hot_upd / nullif(n_tup_upd, 0), 2) AS hot_pct
FROM pg_stat_user_tables
WHERE n_tup_upd > 0
ORDER BY n_tup_upd DESC;
```

Để HOT xảy ra, indexed columns liên quan không đổi và page cần chỗ. Giảm `fillfactor` có
thể để lại room cho update, giảm index churn/WAL nhưng tăng heap size/read. Chỉ tune table
update-heavy sau khi xem update columns và page behavior.

---

## 47. Manual VACUUM là can thiệp, không phải thay autovacuum

```sql
VACUUM (ANALYZE, VERBOSE) app.orders;
```

Plain VACUUM hoạt động cùng read/write thông thường nhưng vẫn dùng I/O/CPU và có lock
interaction. Nó không chạy trong transaction block. Khi chạy incident:

- xác nhận blocker/old snapshot;
- kiểm tra free disk và WAL/archive/replica;
- theo dõi progress/log;
- không chạy đồng loạt toàn cluster nếu storage đã saturated;
- sửa threshold/worker/root cause sau khi backlog giảm.

Manual vacuum chữa backlog hiện tại; autovacuum tuning ngăn backlog quay lại.

---

## 48. `VACUUM FULL` và REINDEX cần maintenance plan

`VACUUM FULL` rewrite table, trả space về OS nhưng cần `ACCESS EXCLUSIVE`, extra disk và
rebuild index. Không dùng theo lịch định kỳ.

Index bloat/corruption case có thể cân nhắc:

```sql
REINDEX INDEX CONCURRENTLY app.orders_customer_created_idx;
```

Concurrent reindex giảm blocking nhưng lâu hơn, dùng thêm disk/WAL và vẫn có các lock phase.
Trước rewrite/reindex cần:

- chứng minh ROI;
- dự toán peak disk/WAL/replica lag;
- rehearsal thời gian và lock;
- kiểm tra invalid object sau failure;
- có rollback/runbook.

Nếu workload tiếp tục tạo bloat, rebuild chỉ reset đồng hồ.

---

## 49. Partitioned parent và temporary table cần ANALYZE riêng

Partition là table bình thường nên autovacuum xử lý từng partition. Nhưng partitioned parent
không chứa tuple, autovacuum không tự `ANALYZE` parent; planner có thể thiếu inherited
statistics sau load/distribution shift.

```sql
ANALYZE app.orders_partitioned;
```

Temporary table chỉ session sở hữu truy cập được nên autovacuum không xử lý. Session tạo và
load temp table phải tự `ANALYZE` nếu query phức tạp cần statistics, và VACUUM nếu lifecycle
dài/churn cao.

---

## 50. Bulk load cần boundary cho WAL, statistics và traffic

Một runbook bulk load thường gồm:

1. staging/validate input và free-space budget;
2. dùng `COPY`/batch hợp lý thay row-by-row;
3. giới hạn transaction size theo atomicity, WAL và rollback cost;
4. tránh index/constraint vô ích nhưng không bỏ invariant không có bước kiểm lại;
5. `ANALYZE` sau distribution thay đổi lớn;
6. kiểm tra WAL/archive/slot/replica lag;
7. rate-limit để giữ SLO online.

Một transaction khổng lồ giảm commit overhead nhưng giữ snapshot/lock lâu, tạo WAL burst và
rollback rất đắt. Chọn chunk từ failure boundary, không chỉ throughput benchmark.

---

## 51. Benchmark phải đại diện và có warm-up

Với `pgbench`, scale khởi tạo phải đủ lớn để không chỉ benchmark cache nhỏ:

```bash
pgbench -i -s 100 appdb
pgbench -c 32 -j 8 -T 300 -P 10 appdb
```

Đây chỉ là ví dụ cú pháp, không phải workload application. Benchmark tốt cần:

- schema/data distribution/index giống production;
- query mix và think time hợp lý;
- warm-up tách khỏi measurement;
- nhiều lần chạy, cùng environment;
- ghi p50/p95/p99, throughput, error và resource;
- kiểm tra saturation khi tăng concurrency;
- không tắt durability/autovacuum để lấy số đẹp.

So sánh cold-cache và steady-state riêng nếu cả hai là requirement.

---

## 52. Capacity test tìm knee point, không chỉ max TPS

Tăng concurrency theo bậc và vẽ:

```text
concurrency ↑
throughput  ↑ đến knee point rồi phẳng
latency     ổn định rồi tăng nhanh
errors      xuất hiện khi queue/timeout tràn
```

Operating point nên nằm trước knee point với headroom cho failover, maintenance và burst.
Nếu pool cho phép tải vượt xa điểm này, database biến thành queue đắt tiền. Admission control
và backpressure thường hiệu quả hơn thêm connection.

---

## 53. Runbook: latency tăng đột ngột

### Bước 1 – Giữ evidence

- thời điểm, SLO, deploy/migration/job gần nhất;
- active/queued connection và application error;
- snapshot `pg_stat_activity`, wait events, blockers;
- delta CPU, memory, I/O, WAL, checkpoint;
- top `pg_stat_statements` trong cửa sổ phù hợp.

### Bước 2 – Phân nhánh

| Evidence | Hướng điều tra |
|---|---|
| Lock waits | root blocker, transaction age, lock order |
| CPU saturated | high-call query, bad plan, row explosion, JIT |
| Read I/O tăng | cache churn, seq scan, statistics/index regression |
| Write/fsync tăng | checkpoint, WAL burst, bulk write, storage |
| Temp tăng | sort/hash spill, cardinality, `work_mem` cục bộ |
| Autovacuum backlog | worker/cost, old snapshot, hot tables |

### Bước 3 – Giảm tác động

Rate-limit batch/traffic, rollback deploy an toàn hoặc cancel đúng query sau khi xác định
owner. Không restart database chỉ để xóa triệu chứng trước khi giữ evidence.

---

## 54. Runbook: dead tuple tăng nhanh

1. Xác nhận write rate và table nào tăng `n_dead_tup`.
2. Kiểm tra long transaction, prepared transaction, slot/standby xmin.
3. Xem autovacuum worker/progress/log có chạy, bị cancel hay throttle.
4. Tính threshold hiện tại từ reltuples và table options.
5. Kiểm tra workers có bị table lớn khác chiếm hết.
6. Chạy manual VACUUM có kiểm soát nếu backlog đe dọa SLO/disk.
7. Tune threshold/cost/worker per table và sửa update/index/HOT root cause.
8. Chỉ shrink/rewrite khi space/scan impact chứng minh cần thiết.

Kết thúc incident khi backlog ổn định dưới write rate, không phải khi một lần VACUUM vừa
xong.

---

## 55. Runbook: disk tăng nhanh

Phân loại trước khi xóa gì:

```text
data relation / index / TOAST
WAL hiện hành / archive backlog / replication slot
temporary files
log
backup hoặc file ngoài PostgreSQL
```

Kiểm tra relation sizes, `pg_stat_wal`, archive/slot, temp delta và filesystem. Không xóa
file trực tiếp trong data directory hoặc `pg_wal`.

Mitigation tùy nguồn: dừng/rate-limit producer, sửa archive/consumer slot, cancel spill query,
tăng disk có kiểm soát hoặc maintenance rewrite. Sau đó sửa retention/capacity alert.

---

## 56. Failure modes thường gặp

### 56.1 Tăng mọi memory setting

Một query nhanh hơn nhưng peak concurrency OOM. Memory phải tính toàn hệ thống.

### 56.2 Tăng `max_connections` khi pool đầy

Chuyển queue vào PostgreSQL và tăng tail latency; chưa sửa capacity/root cause.

### 56.3 Dùng cache hit ratio làm mục tiêu 100%

Bỏ qua CPU, OS cache, sequential workload và query làm quá nhiều cached work.

### 56.4 Reset statistics ngay khi có incident

Mất baseline/counter cần để xác định nguồn tải.

### 56.5 Tắt autovacuum vì nó dùng I/O

Dead tuple/statistics/freeze debt tăng, incident lớn hơn bị dời về sau.

### 56.6 Chạy `VACUUM FULL` hằng đêm

Tạo rewrite, lock, disk/WAL mà không sửa churn; production dễ bị block.

### 56.7 Dùng `n_dead_tup / n_live_tup` như bloat chính xác

Hai giá trị là estimate và không đo vị trí/free-space reuse/index/TOAST.

### 56.8 Tăng worker mà storage đã saturated

Backlog có thể tranh I/O mạnh hơn với request online.

### 56.9 Benchmark với durability bị tắt

Kết quả không đại diện contract production và có nguy cơ mất/corrupt dữ liệu.

### 56.10 Tối ưu query trung bình thay vì top load/tail

Mất thời gian vào query ít ảnh hưởng trong khi high-call query vẫn chiếm capacity.

---

## 57. Decision matrix

| Triệu chứng | Evidence đầu tiên | Không làm vội | Thay đổi ứng viên |
|---|---|---|---|
| Pool chờ, DB CPU thấp | active/waits, pool metrics | tăng max connection | tìm blocker/network/pool leak |
| CPU cao | top total time/calls, plan | tăng RAM | query/index/cardinality/admission |
| Read latency cao | pg_stat_io + OS disk | ép index | plan, working set, storage |
| Temp spill cao | PGSS/log temp/plan | tăng global work_mem | query shape, local memory |
| Checkpoint dày | checkpointer/WAL delta | force checkpoint | max WAL, write rate, archive |
| Dead tuple backlog | table stats/progress/xmin | VACUUM FULL | unblock cleanup, tune per table |
| XID age cao | database/table age | cancel wraparound vacuum | remove blocker, vacuum/freeze |
| Disk tăng | relation/WAL/temp/log breakdown | xóa `pg_wal` | fix producer/retention/slot |
| Plan regression | estimate/statistics/settings | disable planner node global | ANALYZE, stats, index/query |

---

## 58. Checklist production

### Workload và SLO

- [ ] Có throughput, p50/p95/p99, error và headroom target?
- [ ] Query mix, data distribution và peak concurrency được ghi lại?
- [ ] Capacity test đã tìm knee point?
- [ ] Benchmark giữ nguyên durability/constraint contract?

### Observability

- [ ] Counter được thu theo delta cùng `stats_reset`?
- [ ] Có `pg_stat_statements` và kiểm soát eviction/quyền?
- [ ] Slow log/auto_explain có sample, redaction và retention?
- [ ] `pg_stat_activity`, wait, blocker, OS CPU/I/O được tương quan?
- [ ] PostgreSQL 18 `pg_stat_io`, checkpointer, WAL được baseline?

### Memory và connection

- [ ] Tổng pool của mọi instance nằm trong admission budget?
- [ ] `work_mem` tính theo node × worker × concurrency?
- [ ] Có override cục bộ cho report/batch thay global quá lớn?
- [ ] Shared buffers chừa memory cho OS/session/maintenance?
- [ ] Parallel workers có capacity và launch ratio hợp lý?

### Vacuum và statistics

- [ ] Table lớn/hot có threshold per table từ write rate?
- [ ] Worker/cost đủ để cleanup rate vượt creation rate?
- [ ] Long transaction/prepared xact/slot xmin có alert?
- [ ] XID/MultiXact age có time-to-limit alert?
- [ ] Partitioned parent/temp table có manual ANALYZE workflow?
- [ ] Log/progress vacuum và delay time được dùng khi sự cố?

### Disk, WAL và maintenance

- [ ] Checkpoint frequency, WAL rate, FPI và buffer-full có baseline?
- [ ] Disk alert phân biệt relation/WAL/temp/log/archive?
- [ ] Không ai xóa trực tiếp file trong data directory/`pg_wal`?
- [ ] Rewrite/reindex có lock, disk, WAL, replica và rollback rehearsal?
- [ ] Restore/replication/durability không bị đổi chỉ để benchmark đẹp?

---

## 59. Câu hỏi phỏng vấn

1. Vì sao average latency không đủ cho performance SLO?
2. Counter `pg_stat_*` phải biến thành rate thế nào?
3. `pg_stat_activity` khác `pg_stat_statements` ở điểm nào?
4. Top total time khác top mean time ra sao?
5. Hạn chế của normalized query/query ID là gì?
6. Vì sao cache hit ratio không cho biết physical-disk hit?
7. PostgreSQL 18 thêm gì vào `pg_stat_io`?
8. Vì sao temp spill không đồng nghĩa phải tăng global `work_mem`?
9. Memory của `work_mem` nhân theo những chiều nào?
10. `effective_cache_size` có cấp phát RAM không?
11. Checkpoint requested tăng nhanh gợi ý điều gì?
12. `max_wal_size` là hard limit không?
13. Plain VACUUM làm gì và không làm gì?
14. Công thức trigger vacuum/analyze khác nhau ra sao?
15. Vì sao insert-only table vẫn cần vacuum?
16. Khi nào nên tune autovacuum per table?
17. Cost-delay balancing giữa autovacuum workers hoạt động thế nào?
18. `delay_time` của PostgreSQL 18 giúp chẩn đoán gì?
19. Wraparound autovacuum khác worker thường về lock conflict thế nào?
20. Long transaction cản cleanup bằng cơ chế gì?
21. Vì sao `n_dead_tup` không phải bloat measurement chính xác?
22. Khi nào dùng `pgstattuple_approx`?
23. HOT và fillfactor đánh đổi điều gì?
24. Vì sao `VACUUM FULL` không phải routine maintenance?
25. Partitioned parent và temp table cần ANALYZE ra sao?
26. Capacity knee point dùng để đặt pool/admission thế nào?

---

## 60. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [Performance tips và EXPLAIN](https://www.postgresql.org/docs/18/performance-tips.html)
- [Cumulative statistics system](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [Runtime statistics settings](https://www.postgresql.org/docs/18/runtime-config-statistics.html)
- [`pg_stat_statements`](https://www.postgresql.org/docs/18/pgstatstatements.html)
- [`auto_explain`](https://www.postgresql.org/docs/18/auto-explain.html)
- [Resource consumption](https://www.postgresql.org/docs/18/runtime-config-resource.html)
- [WAL và checkpoint settings](https://www.postgresql.org/docs/18/runtime-config-wal.html)
- [Routine vacuuming](https://www.postgresql.org/docs/18/routine-vacuuming.html)
- [Vacuum settings](https://www.postgresql.org/docs/18/runtime-config-vacuum.html)
- [`VACUUM`](https://www.postgresql.org/docs/18/sql-vacuum.html)
- [Progress reporting](https://www.postgresql.org/docs/18/progress-reporting.html)
- [`pgstattuple`](https://www.postgresql.org/docs/18/pgstattuple.html)
- [`pgbench`](https://www.postgresql.org/docs/18/pgbench.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

Học tiếp:

1. [Partitioning & Large Tables](partitioning_large_tables.md).
2. [Replication & High Availability](../operations/replication_ha.md).
3. [Backup, PITR & Upgrade](../operations/backup_pitr_upgrade.md).

---

*Cập nhật lần cuối: 2026-07-31.*
