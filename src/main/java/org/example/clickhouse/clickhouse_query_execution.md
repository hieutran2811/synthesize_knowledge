# ClickHouse Query Execution Internals & Troubleshooting

> Bổ trợ cho [clickhouse_performance.md](clickhouse_performance.md) (index/MV/projection/profiling — KHÔNG lặp lại ở đây), [clickhouse_operations.md](clickhouse_operations.md) (replication) và [clickhouse_sql.md](clickhouse_sql.md) (JOIN/FINAL cú pháp). Theo phương pháp What/How/Why/Compare/Trade-offs.

## Mục lục
1. [Query pipeline & Vectorized Execution (How)](#1-query-pipeline--vectorized-execution)
2. [PREWHERE – lọc trước khi đọc cột](#2-prewhere)
3. [EXPLAIN – đọc kế hoạch & pipeline](#3-explain)
4. [JOIN algorithms](#4-join-algorithms)
5. [Distributed query: GLOBAL IN / GLOBAL JOIN](#5-distributed-query)
6. [External aggregation/sort & memory settings](#6-external-aggregation--memory)
7. [Query cache](#7-query-cache)
8. [Troubleshooting & Anti-patterns](#8-troubleshooting--anti-patterns)
9. [System tables để chẩn đoán](#9-system-tables-chẩn-đoán)
10. [Trade-offs](#10-trade-offs)

---

## 1. Query pipeline & Vectorized Execution

### What – mô hình xử lý theo block, vectorized
ClickHouse **không** xử lý từng dòng (row-at-a-time như OLTP). Nó xử lý theo **block** (mặc định ~65536 dòng/block) của **các cột** → vòng lặp chặt trên mảng liên tục → tận dụng **SIMD**, cache CPU, ít nhánh rẽ → throughput cực cao.

```
Row-at-a-time (Postgres):  for each row { eval expr }      → nhiều function call, cache miss
Vectorized (ClickHouse):   for each block { eval expr trên cả mảng cột }  → SIMD, cache-friendly
```

### How – Processors pipeline (DAG)
Query được dịch thành đồ thị **Processors** (source → transform → sink) chạy song song qua nhiều **stream** (số stream ≈ `max_threads`). Mỗi stream xử lý một phần granule/part độc lập rồi gộp.

```
Parts → [Read streams ×N] → [Filter] → [Aggregate (partial)] → [Merge partial] → Result
         (song song theo max_threads, mỗi stream 1 tập granule)
```
> Số luồng/đọc song song & memory: xem "Memory & Parallelism Settings" ở [clickhouse_performance.md](clickhouse_performance.md). `optimize_read_in_order` cho phép đọc theo thứ tự sort key → tránh sort lại.

---

## 2. PREWHERE

### What & Why
`PREWHERE` đọc **chỉ các cột trong điều kiện lọc trước**, loại bỏ granule/dòng không khớp, **rồi mới** đọc các cột còn lại cho dòng sống sót → giảm I/O đọc cột lớn.

```sql
-- ClickHouse tự động chuyển WHERE → PREWHERE cho cột rẻ (optimize_move_to_prewhere=1)
SELECT huge_json, payload          -- cột lớn, chỉ đọc cho dòng khớp
FROM events
PREWHERE event_type = 'error'      -- đọc cột nhỏ trước, lọc sớm
WHERE user_id > 1000;
```
```
WHERE-only:  đọc TẤT CẢ cột của granule → rồi lọc → lãng phí I/O cột lớn
PREWHERE:    đọc cột lọc (nhỏ) → loại granule/dòng → đọc cột lớn CHỈ cho dòng còn lại
```
- Thường để ClickHouse tự động (`optimize_move_to_prewhere`); đặt PREWHERE thủ công khi cần kiểm soát (cột lọc rẻ + selective cao).
- Khác **primary index** (loại nguyên granule theo sort key) — PREWHERE lọc trong granule đã chọn. Bổ sung cho index, không thay thế. Xem index ở [clickhouse_performance.md](clickhouse_performance.md).

---

## 3. EXPLAIN

```sql
EXPLAIN PLAN SELECT ...;                  -- kế hoạch logic (các bước)
EXPLAIN PLAN indexes = 1 SELECT ...;      -- granule/part bị loại bởi index (cực hữu ích)
EXPLAIN PIPELINE SELECT ...;              -- pipeline Processors thực thi (số stream song song)
EXPLAIN ESTIMATE SELECT ...;             -- ước lượng rows/marks/parts sẽ đọc
EXPLAIN AST SELECT ...;                   -- cây cú pháp
EXPLAIN SYNTAX SELECT ...;                -- query sau khi rewrite/optimize
```
```sql
-- Kiểm tra index có "ăn" không: so sánh parts/granules trước-sau filter
EXPLAIN indexes = 1
SELECT count() FROM events WHERE event_date = '2026-06-01';
-- Output cho biết: "Granules: 12/4096" → index loại bỏ phần lớn → tốt
```
> Dùng `EXPLAIN indexes=1` để xác nhận primary key/partition pruning hoạt động; `EXPLAIN ESTIMATE` để đoán chi phí; `EXPLAIN PIPELINE` xem mức song song. Profiling chi tiết (system.query_log, ProfileEvents): [clickhouse_performance.md](clickhouse_performance.md).

---

## 4. JOIN algorithms

ClickHouse hỗ trợ nhiều thuật toán JOIN; chọn qua `join_algorithm` (mặc định `direct,hash`).

| Algorithm | Cơ chế | Khi tốt | Lưu ý |
|-----------|--------|---------|-------|
| `hash` | Build hash table từ **bảng phải** trong RAM | Right table vừa RAM | **Right table phải nhỏ hơn** |
| `parallel_hash` | Hash song song nhiều thread | Right table lớn vừa RAM, máy nhiều core | Nhanh hơn hash |
| `grace_hash` | Hash chia partition, spill đĩa | Right table **không vừa RAM** | Tránh OOM, chậm hơn |
| `full_sorting_merge` | Sort cả 2 rồi merge | Cả 2 lớn, có thể sort | Không cần build hash |
| `partial_merge` | Merge join tiết kiệm RAM | RAM hạn chế | Chậm |
| `direct` | Tra cứu trực tiếp (Dictionary/KV right) | Right là dictionary/KV table | Nhanh nhất khi áp dụng được |
| `auto` | Tự chọn theo dữ liệu | Mặc định linh hoạt | – |

### ⚠️ Quy tắc sống còn: bảng NHỎ bên PHẢI
ClickHouse **build hash table từ bảng bên phải** (right) trong RAM. Đặt bảng lớn bên trái, bảng nhỏ bên phải. Ngược lại → OOM.
```sql
-- ✅ events (tỷ dòng) LEFT, dim_users (nhỏ) RIGHT
SELECT e.*, u.name FROM events e JOIN dim_users u ON e.uid = u.id
SETTINGS join_algorithm = 'parallel_hash';

-- Dùng dictionary thay JOIN cho bảng tra cứu nhỏ → direct, nhanh & ít RAM (xem engines.md)
SELECT dictGet('users_dict', 'name', uid) FROM events;
```
> JOIN trong ClickHouse "đắt" hơn DB OLTP truyền thống → ưu tiên **denormalize** (wide table) hoặc **dictionary** cho dim nhỏ. Cú pháp JOIN/ASOF JOIN: [clickhouse_sql.md](clickhouse_sql.md).

---

## 5. Distributed query: GLOBAL IN / GLOBAL JOIN

Trên cluster sharded (Distributed table), JOIN/IN với subquery có thể gây **fan-out bùng nổ** nếu không dùng `GLOBAL`.

```sql
-- ❌ IN/JOIN thường: mỗi shard tự chạy subquery cục bộ → kết quả SAI (thiếu dữ liệu shard khác)
SELECT * FROM distributed_events WHERE uid IN (SELECT uid FROM distributed_vip);

-- ✅ GLOBAL IN: initiator chạy subquery 1 lần, BROADCAST kết quả tới mọi shard → đúng
SELECT * FROM distributed_events WHERE uid GLOBAL IN (SELECT uid FROM distributed_vip);
SELECT ... FROM dist_a GLOBAL JOIN dist_b ON ...;
```
```
Không GLOBAL:  mỗi shard chạy subquery trên dữ liệu CỤC BỘ → sót/sai khi data nằm shard khác
GLOBAL:        initiator tính 1 lần → gửi tạm tới mọi shard → đúng (nhưng tốn mạng nếu set lớn)
```
- `distributed_product_mode` kiểm soát hành vi (deny/local/global/allow).
- GLOBAL set lớn → tốn băng thông broadcast → cân nhắc. Liên hệ Distributed table/sharding ở [clickhouse_operations.md](clickhouse_operations.md).

---

## 6. External aggregation & memory

GROUP BY/ORDER BY/DISTINCT trên cardinality lớn dễ vượt RAM → cho phép **spill ra đĩa**.

```sql
SET max_memory_usage = 20000000000;                 -- trần RAM/query
SET max_bytes_before_external_group_by = 10000000000;  -- GROUP BY spill đĩa khi vượt
SET max_bytes_before_external_sort = 10000000000;      -- ORDER BY spill đĩa
SET distributed_aggregation_memory_efficient = 1;      -- gộp aggregate tiết kiệm RAM trên cluster
```
- Giảm RAM còn bằng: `LowCardinality` cho cột group, `uniqCombined` thay `uniqExact`, lọc sớm (PREWHERE), `optimize_aggregation_in_order`.
- Liên hệ aggregate xấp xỉ ở [clickhouse_functions.md](clickhouse_functions.md), settings ở [clickhouse_performance.md](clickhouse_performance.md).

---

## 7. Query cache

Cache **kết quả** query (không phải dữ liệu) cho query lặp lại giống hệt.
```sql
SET use_query_cache = 1;
SELECT count() FROM events WHERE day = today() SETTINGS use_query_cache = 1, query_cache_ttl = 60;
```
- Hợp cho dashboard query lặp lại; cấu hình TTL, max entries. Xem `system.query_cache`.
- ⚠️ Không hợp dữ liệu thay đổi liên tục (kết quả cũ). Cân nhắc với MV (tiền tổng hợp) thay vì cache.

---

## 8. Troubleshooting & Anti-patterns

| Triệu chứng | Nguyên nhân | Khắc phục |
|-------------|-------------|-----------|
| `Too many parts (300)` | Insert nhỏ/nhiều quá | Batch lớn, **async_insert**, Buffer; giảm số partition (xem [ingestion](clickhouse_ingestion_formats.md)) |
| `Memory limit exceeded` | GROUP BY/JOIN/DISTINCT cardinality lớn | External group by/sort, `uniqCombined`, LowCardinality, bảng nhỏ bên phải JOIN |
| Merge backlog, đĩa phình | Merge không kịp insert | Giảm tần suất insert, tăng `background_pool_size`, ít partition hơn |
| Replication lag | `system.replication_queue` dài | Kiểm tra Keeper, mạng, merge nặng; xem [operations](clickhouse_operations.md) |
| Query chậm, đọc full table | Index không "ăn" | `EXPLAIN indexes=1`, sửa ORDER BY/primary key, thêm skip index ([performance](clickhouse_performance.md)) |
| `FINAL` quá chậm | Gộp dedup lúc đọc | Hạn chế FINAL; dùng ReplacingMergeTree + dedup ở tầng query, hoặc `do_not_merge_across_partitions_select_final` |

### Anti-patterns (ClickHouse KHÔNG phải OLTP)
- **Point query / KV lookup** (`WHERE id = 123` trả 1 dòng): ClickHouse quét granule, không phải KV store → dùng dictionary hoặc DB khác cho KV.
- **SELECT \***: columnar → đọc thừa cột. **Chỉ select cột cần.**
- **Mutations** (`ALTER TABLE UPDATE/DELETE`): **ghi lại cả part** (rất nặng, bất đồng bộ qua `system.mutations`). Dùng **lightweight DELETE** (`DELETE FROM`) hoặc thiết kế bằng ReplacingMergeTree/TTL thay vì update thường xuyên.
- **OPTIMIZE TABLE ... FINAL** định kỳ để "dọn": tốn I/O khổng lồ, thường không cần (merge tự chạy). Tránh lạm dụng.
- **Insert từng dòng** từ app: → too many parts (xem [ingestion](clickhouse_ingestion_formats.md)).
- **JOIN bảng lớn bên phải**: OOM (mục 4).
- **Nhiều partition nhỏ** (partition theo ngày + key cardinality cao): quá nhiều part → chậm. Partition thô (theo tháng) thường đủ.

---

## 9. System tables chẩn đoán

```sql
-- Query đang chạy / đã chạy
SELECT query, elapsed, memory_usage FROM system.processes ORDER BY elapsed DESC;
SELECT query, query_duration_ms, read_rows, memory_usage, exception
FROM system.query_log WHERE type='ExceptionWhileProcessing' AND event_time > now()-3600 ORDER BY event_time DESC;

-- Parts & merges
SELECT table, count() parts, sum(rows) FROM system.parts WHERE active GROUP BY table ORDER BY parts DESC;
SELECT * FROM system.merges;                 -- merge đang chạy
SELECT * FROM system.mutations WHERE is_done = 0;   -- mutation chưa xong (nặng)

-- Replication & lỗi
SELECT database, table, type, num_tries, last_exception FROM system.replication_queue;
SELECT * FROM system.errors ORDER BY value DESC LIMIT 20;     -- lỗi tích lũy
SELECT metric, value FROM system.asynchronous_metrics WHERE metric LIKE '%Memory%';
```
> `system.query_log` + `ProfileEvents` (chi tiết I/O/CPU/merge) đã có ở [clickhouse_performance.md](clickhouse_performance.md); monitoring/alert (Prometheus/Grafana) ở [clickhouse_operations.md](clickhouse_operations.md).

---

## 10. Trade-offs

- (+) Vectorized + parallel pipeline → quét hàng tỷ dòng/giây; PREWHERE + index giảm I/O mạnh; nhiều JOIN algorithm linh hoạt; spill đĩa tránh OOM.
- (−) JOIN đắt & build right table trong RAM → cần denormalize/dictionary; point query/update không phải sở trường (không thay OLTP).
- (−) Mutations/FINAL nặng → thiết kế tránh update; quá nhiều tuning knob (settings) → dễ cấu hình sai.
- (−) Distributed cần hiểu GLOBAL IN/JOIN nếu không kết quả sai/tốn mạng.
- Triết lý: **thiết kế schema & ingestion đúng** (wide table, batch, partition thô, sort key hợp query) quan trọng hơn tinh chỉnh query sau.

---

## Ghi chú – Keywords tiếp theo

- Liên quan: [clickhouse_performance.md](clickhouse_performance.md) (index/skip index/MV/projection/profiling/memory settings), [clickhouse_operations.md](clickhouse_operations.md) (replication queue, Distributed, monitoring), [clickhouse_sql.md](clickhouse_sql.md) (JOIN/ASOF/FINAL/SAMPLE), [clickhouse_functions.md](clickhouse_functions.md) (uniqCombined/quantile giảm RAM), [clickhouse_ingestion_formats.md](clickhouse_ingestion_formats.md) (too many parts).
- **Keywords**: `optimize_move_to_prewhere`, `optimize_read_in_order`, `max_threads`/`max_final_threads`, `join_algorithm`, `max_rows_in_join`/`join_overflow_mode`, `distributed_product_mode`, `prefer_localhost_replica`, `do_not_merge_across_partitions_select_final`, `lightweight_deletes_sync`, `system.query_thread_log`, `system.opentelemetry_span_log`, `send_logs_level`, `query_plan_*` optimizations, `allow_experimental_analyzer` (new analyzer).

*Cập nhật lần cuối: 2026-06-04*
