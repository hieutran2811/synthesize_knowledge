# ClickHouse Performance Optimization

## Mục lục
1. [Primary Index – Sparse Index Mechanics](#1-primary-index--sparse-index-mechanics)
2. [Skip Indexes – Secondary Indexes](#2-skip-indexes--secondary-indexes)
3. [Partitioning Strategy](#3-partitioning-strategy)
4. [Materialized Views – Incremental Aggregation](#4-materialized-views--incremental-aggregation)
5. [Projections – Alternative Sort Orders](#5-projections--alternative-sort-orders)
6. [Query Profiling & Optimization](#6-query-profiling--optimization)
7. [Memory & Parallelism Settings](#7-memory--parallelism-settings)

---

## 1. Primary Index – Sparse Index Mechanics

### 1.1 Cơ chế Sparse Index

```
Dense index (B-Tree, PostgreSQL):
  One index entry per row → index size = O(n)
  
Sparse index (ClickHouse):
  One index entry per GRANULE (default 8192 rows)
  → index size = O(n/8192) → ~10,000x smaller
  → Fits in memory even for trillion-row tables
  → Tradeoff: less precise (may read extra granules)

primary.idx file:
  Row 0:     [tenant_id=1, event_type='click',    event_time=2024-01-01 00:00:00]
  Row 8192:  [tenant_id=1, event_type='click',    event_time=2024-01-01 02:16:32]
  Row 16384: [tenant_id=1, event_type='page_view', event_time=2024-01-01 04:00:00]
  Row 24576: [tenant_id=1, event_type='purchase', event_time=2024-01-01 06:33:04]

Query: WHERE tenant_id = 1 AND event_type = 'click' AND event_time = '2024-01-01 01:00:00'
  Binary search → granule range [G0, G1] (rows 0 to 16383)
  Read only those 2 granules (16384 rows) instead of entire table
```

### 1.2 Primary Key Design Rules

```sql
-- Rule 1: Columns most used in WHERE go first (high selectivity)
-- Rule 2: Low-cardinality before high-cardinality (for better pruning)
-- Rule 3: ORDER BY = PARTITION BY + primary key columns + high-cardinality

-- ❌ BAD: high-cardinality user_id first
CREATE TABLE events_bad (
    user_id    UInt64,        -- millions of unique values
    event_type LowCardinality(String),
    event_time DateTime
)
ENGINE = MergeTree()
ORDER BY (user_id, event_type, event_time);
-- Query: WHERE event_type = 'purchase' → cannot prune (user_id scattered)

-- ✅ GOOD: filter columns first, then high-cardinality last
CREATE TABLE events_good (
    tenant_id  UInt32,
    event_type LowCardinality(String),
    event_time DateTime,
    user_id    UInt64
)
ENGINE = MergeTree()
ORDER BY (tenant_id, event_type, event_time, user_id);
-- Query: WHERE tenant_id = 1 AND event_type = 'purchase' → excellent pruning
-- Query: WHERE tenant_id = 1 AND event_time > ... → good pruning (tenant prunes)
-- Query: WHERE user_id = 12345 → NO pruning (last in key) → use skip index

-- Check how many granules a query reads:
EXPLAIN indexes = 1
SELECT count() FROM events_good
WHERE tenant_id = 1 AND event_type = 'purchase';
-- Look for: "Parts: N/M, Granules: N/M" → want low ratio
```

### 1.3 Primary Key vs Sorting Key

```sql
-- PRIMARY KEY = subset of ORDER BY stored in sparse index
-- ORDER BY = physical sort order (determines clustering)

-- Use case: save memory on primary index
CREATE TABLE logs (
    service_name LowCardinality(String),
    log_level    LowCardinality(String),
    log_time     DateTime,
    trace_id     String,          -- high cardinality, not in primary key
    message      String
)
ENGINE = MergeTree()
ORDER BY (service_name, log_level, log_time, trace_id)
PRIMARY KEY (service_name, log_level, log_time);
-- Primary index has 3 columns (smaller, fits in memory)
-- Data sorted by 4 columns (trace_id clustering within same second)

-- Check primary key memory usage:
SELECT
    table,
    formatReadableSize(primary_key_bytes_in_memory) AS pk_memory
FROM system.tables
WHERE database = currentDatabase();
```

---

## 2. Skip Indexes – Secondary Indexes

### 2.1 Concept

```
Skip index: per-granule metadata to skip granules at read time
  - NOT a B-Tree (no per-row entries)
  - Stored per GRANULARITY granules (e.g., 4 → every 4×8192 = 32768 rows)
  - Answers: "does ANY row in granules [G0..G3] match the predicate?"
  - If NO → skip entire block without reading column data

Types:
  minmax:       min/max value per block    → range queries
  set(N):       set of unique values       → equality, IN
  bloom_filter: probabilistic membership  → equality, IN, LIKE
  tokenbf_v1:   token-based bloom filter  → LIKE, full-text search
  ngrambf_v1:   n-gram bloom filter       → substring search
```

### 2.2 minmax Index

```sql
-- Best for: numeric/date range queries on non-PK columns
CREATE TABLE metrics (
    service      LowCardinality(String),
    metric_name  LowCardinality(String),
    ts           DateTime,
    value        Float64,
    host         String,
    datacenter   LowCardinality(String),
    INDEX idx_value (value) TYPE minmax GRANULARITY 4
    -- GRANULARITY 4: one index entry per 4 granules (32768 rows)
)
ENGINE = MergeTree()
ORDER BY (service, metric_name, ts);

-- Query benefits from minmax:
SELECT avg(value) FROM metrics
WHERE service = 'api' AND value > 1000;  -- minmax skips blocks where max(value) <= 1000

-- Check if index is used:
EXPLAIN indexes = 1
SELECT avg(value) FROM metrics WHERE value > 1000;
-- Look for: "Indexes: skip, minmax" section
```

### 2.3 set Index

```sql
-- Best for: low-cardinality columns, exact equality / IN queries
CREATE TABLE events (
    event_id   UInt64,
    event_time DateTime,
    status     LowCardinality(String),   -- 'success', 'error', 'timeout'
    region     LowCardinality(String),
    user_id    UInt64,
    INDEX idx_status (status) TYPE set(10) GRANULARITY 8,
    -- set(10): store up to 10 unique values per block
    -- If block has > 10 unique values → index disabled for that block
    INDEX idx_region (region) TYPE set(50) GRANULARITY 4
)
ENGINE = MergeTree()
ORDER BY (event_time, user_id);

-- Effective for:
SELECT * FROM events WHERE status = 'error';   -- ✅ skip non-error blocks
SELECT * FROM events WHERE region IN ('VN', 'SG', 'TH');  -- ✅ skip irrelevant regions
```

### 2.4 bloom_filter Index

```sql
-- Best for: high-cardinality string equality (email, session_id, trace_id)
-- Probabilistic: may have false positives, never false negatives
-- FPP (false positive probability): lower = more accurate but larger index

CREATE TABLE requests (
    request_id  String,          -- UUID
    trace_id    String,          -- distributed trace
    user_agent  String,
    email       String,
    ts          DateTime,
    INDEX idx_trace_id  (trace_id) TYPE bloom_filter(0.01)  GRANULARITY 1,
    -- 0.01 = 1% FPP → 1% chance of reading a granule that doesn't match
    INDEX idx_email     (email)    TYPE bloom_filter(0.001) GRANULARITY 2
    -- 0.001 = 0.1% FPP → more accurate, larger index
)
ENGINE = MergeTree()
ORDER BY ts;

-- Effective for:
SELECT * FROM requests WHERE trace_id = 'abc123...';   -- ✅ usually skips 99% of granules
SELECT * FROM requests WHERE email = 'alice@example.com'; -- ✅

-- Less effective:
SELECT * FROM requests WHERE email LIKE '%@gmail.com'; -- ❌ bloom filter is exact match only
-- → Use tokenbf_v1 or ngrambf_v1 for LIKE
```

### 2.5 tokenbf_v1 & ngrambf_v1

```sql
-- tokenbf_v1: bloom filter on tokens (words split by non-alphanumeric chars)
-- ngrambf_v1: bloom filter on n-grams (substrings of length n)

CREATE TABLE log_messages (
    ts       DateTime,
    level    LowCardinality(String),
    message  String,   -- 'Error connecting to database: timeout'
    INDEX idx_tokens (message) TYPE tokenbf_v1(
        32768,    -- bloom filter size in bytes
        3,        -- hash functions
        0         -- reserved
    ) GRANULARITY 1,
    INDEX idx_ngram (message) TYPE ngrambf_v1(
        4,        -- n-gram size (4 chars)
        32768,    -- bloom filter size in bytes
        3,        -- hash functions
        0
    ) GRANULARITY 1
)
ENGINE = MergeTree()
ORDER BY ts;

-- tokenbf_v1 effective for:
SELECT * FROM log_messages WHERE message LIKE '%database%';   -- ✅ token 'database'
SELECT * FROM log_messages WHERE hasToken(message, 'timeout'); -- ✅

-- ngrambf_v1 effective for:
SELECT * FROM log_messages WHERE message LIKE '%atabase%';     -- ✅ n-grams overlap
SELECT * FROM log_messages WHERE message LIKE '%sql_inj%';     -- ✅

-- Add index to existing table:
ALTER TABLE log_messages ADD INDEX idx_tokens (message) TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1;
ALTER TABLE log_messages MATERIALIZE INDEX idx_tokens;  -- build index for existing data
```

---

## 3. Partitioning Strategy

### 3.1 Partition Design

```sql
-- Partitioning splits data into separate directories on disk
-- Benefits: partition pruning (skip entire months/days)
-- Costs: too many partitions → merge overhead

-- ✅ Monthly partitioning (most common):
CREATE TABLE events_monthly (...)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time);
-- Creates: 202401/, 202402/, ...

-- ✅ Daily for high-volume tables:
CREATE TABLE events_daily (...)
ENGINE = MergeTree()
PARTITION BY toDate(event_time);

-- ✅ Multi-column partition:
CREATE TABLE tenant_events (
    tenant_id   UInt32,
    event_time  DateTime,
    ...
)
ENGINE = MergeTree()
PARTITION BY (tenant_id, toYYYYMM(event_time));
-- Creates: (1, 202401)/, (1, 202402)/, (2, 202401)/, ...

-- ❌ BAD: too granular (hourly on high-volume → thousands of parts)
PARTITION BY toStartOfHour(event_time);  -- ❌ for tables > 1B rows/day

-- ❌ BAD: no partitioning (all data in one partition → slow DROP/DETACH)
-- Missing PARTITION BY → all data in tuple()/ directory

-- Check partition sizes:
SELECT
    partition,
    count()                                AS parts,
    sum(rows)                              AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    min(min_date)                          AS min_date,
    max(max_date)                          AS max_date
FROM system.parts
WHERE table = 'events_monthly' AND active = 1
GROUP BY partition
ORDER BY partition;
```

### 3.2 Partition Operations

```sql
-- Drop partition (instant delete):
ALTER TABLE events_monthly DROP PARTITION '202401';

-- Detach partition (offline but keep data):
ALTER TABLE events_monthly DETACH PARTITION '202401';
-- Files moved to detached/ subdirectory

-- Reattach:
ALTER TABLE events_monthly ATTACH PARTITION '202401';

-- Move partition between tables (must have identical structure):
ALTER TABLE events_monthly MOVE PARTITION '202401' TO TABLE events_archive;

-- Copy partition between shards:
ALTER TABLE events_monthly FETCH PARTITION '202401'
FROM 'zookeeper-path/tables/shard2/events_monthly';

-- Partition pruning in action:
SELECT count() FROM events_monthly
WHERE event_time >= '2024-01-01' AND event_time < '2024-02-01';
-- Only reads partition 202401 → skips 11 months

EXPLAIN partitions = 1
SELECT count() FROM events_monthly
WHERE event_time BETWEEN '2024-01-01' AND '2024-01-31';
```

### 3.3 TTL – Data Lifecycle

```sql
CREATE TABLE events_ttl (
    tenant_id   UInt32,
    event_time  DateTime,
    event_type  LowCardinality(String),
    payload     String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_time)
-- Column-level TTL: zero out specific columns (save space, keep row)
TTL event_time + INTERVAL 90 DAY
    TO DISK 's3_warm',                -- move to S3-warm after 90 days
    event_time + INTERVAL 1 YEAR
    TO DISK 's3_cold',                -- move to S3-cold after 1 year
    event_time + INTERVAL 3 YEAR
    DELETE                            -- delete after 3 years
SETTINGS merge_with_ttl_timeout = 14400;  -- run TTL every 4 hours

-- Column-level TTL (keep row but clear column):
CREATE TABLE events_col_ttl (
    event_time  DateTime,
    user_id     UInt64,
    payload     String TTL event_time + INTERVAL 30 DAY  -- clear after 30 days
)
ENGINE = MergeTree()
ORDER BY event_time;

-- Manually trigger TTL:
ALTER TABLE events_ttl MATERIALIZE TTL;

-- Check TTL:
SELECT name, engine_full FROM system.tables WHERE name = 'events_ttl';
```

---

## 4. Materialized Views – Incremental Aggregation

### 4.1 Concept & Architecture

```
Materialized View in ClickHouse:
  - Trigger: fires on INSERT to source table
  - Processes: only new data (NOT full recomputation)
  - Stores: in target table (MergeTree, AggregatingMergeTree)
  - NOT a snapshot: continuously updated

Architecture:
  INSERT → source_table → MV trigger → SELECT (new rows) → INSERT → target_table

Use case:
  events_raw (billions of rows)
    → events_hourly_agg (millions of rows)
      → dashboard queries: ~100x faster
```

### 4.2 MV with AggregatingMergeTree

```sql
-- Source: raw events
CREATE TABLE events_raw (
    event_id    UInt64,
    tenant_id   UInt32,
    event_time  DateTime,
    event_type  LowCardinality(String),
    user_id     UInt64,
    revenue     Decimal(18, 4),
    latency_ms  UInt32
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_type, event_time, user_id);

-- Target: pre-aggregated table
CREATE TABLE events_hourly (
    tenant_id     UInt32,
    hour          DateTime,
    event_type    LowCardinality(String),
    total_events  AggregateFunction(count),
    unique_users  AggregateFunction(uniq, UInt64),
    total_revenue AggregateFunction(sum, Decimal(18, 4)),
    p95_latency   AggregateFunction(quantile(0.95), UInt32)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (tenant_id, hour, event_type);

-- Materialized View
CREATE MATERIALIZED VIEW events_hourly_mv
TO events_hourly
AS SELECT
    tenant_id,
    toStartOfHour(event_time)    AS hour,
    event_type,
    countState()                 AS total_events,
    uniqState(user_id)           AS unique_users,
    sumState(revenue)            AS total_revenue,
    quantileState(0.95)(latency_ms) AS p95_latency
FROM events_raw
GROUP BY tenant_id, hour, event_type;

-- Backfill MV for existing data:
INSERT INTO events_hourly
SELECT
    tenant_id,
    toStartOfHour(event_time) AS hour,
    event_type,
    countState(),
    uniqState(user_id),
    sumState(revenue),
    quantileState(0.95)(latency_ms)
FROM events_raw
GROUP BY tenant_id, hour, event_type;

-- Query the aggregated view:
SELECT
    tenant_id,
    hour,
    event_type,
    countMerge(total_events)    AS events,
    uniqMerge(unique_users)     AS users,
    sumMerge(total_revenue)     AS revenue,
    quantileMerge(0.95)(p95_latency) AS p95_ms
FROM events_hourly
WHERE tenant_id = 1 AND hour >= now() - INTERVAL 24 HOUR
GROUP BY tenant_id, hour, event_type
ORDER BY hour, events DESC;
-- Performance: query 24 hourly buckets vs 86.4M raw rows → 10000x faster
```

### 4.3 Chained Materialized Views

```sql
-- Chain: raw → hourly → daily → monthly
-- Each level pre-aggregates further

-- Daily (reads from hourly):
CREATE TABLE events_daily (
    tenant_id     UInt32,
    day           Date,
    event_type    LowCardinality(String),
    total_events  AggregateFunction(count),
    unique_users  AggregateFunction(uniq, UInt64),
    total_revenue AggregateFunction(sum, Decimal(18, 4))
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(day)
ORDER BY (tenant_id, day, event_type);

-- WARNING: Chain MVs from raw, not from other MVs
-- MV on MV: SELECT from target table of first MV → triggers second MV on INSERT to first target
-- This works but creates coupling; prefer separate MVs from raw

CREATE MATERIALIZED VIEW events_daily_mv
TO events_daily
AS SELECT
    tenant_id,
    toDate(event_time)  AS day,
    event_type,
    countState(),
    uniqState(user_id),
    sumState(revenue)
FROM events_raw   -- always from raw source!
GROUP BY tenant_id, day, event_type;
```

### 4.4 MV Caveats

```sql
-- Caveat 1: MV doesn't backfill historical data automatically
-- → Must INSERT INTO target manually for existing data

-- Caveat 2: MV fires per INSERT block, not per row
-- → GROUP BY in MV aggregates within each block
-- → AggregatingMergeTree merges across blocks via background merge

-- Caveat 3: MV is not atomic with source INSERT
-- → If MV write fails, source INSERT already committed
-- → Consider: source table as Null engine + MV as the real storage

-- Best practice: Null engine source
CREATE TABLE events_incoming (   -- no storage!
    event_id   UInt64,
    event_time DateTime,
    ...
) ENGINE = Null;

CREATE MATERIALIZED VIEW events_raw_mv   TO events_raw   AS SELECT * FROM events_incoming;
CREATE MATERIALIZED VIEW events_hourly_mv TO events_hourly AS SELECT ... FROM events_incoming;
-- One INSERT → multiple MVs fire → each gets its own target
```

---

## 5. Projections – Alternative Sort Orders

### 5.1 Concept

```
Projection: pre-computed alternative view of data within a part
  - Same data, different ORDER BY (or aggregated)
  - Automatically maintained on INSERT
  - Query planner chooses projection OR base table automatically
  - No need to manually rewrite queries (unlike MV)

vs Materialized View:
  MV: separate table, must query explicitly (or via view)
  Projection: embedded in table, query optimizer picks automatically
```

### 5.2 Aggregate Projection

```sql
CREATE TABLE events_with_projection (
    tenant_id  UInt32,
    event_time DateTime,
    event_type LowCardinality(String),
    user_id    UInt64,
    revenue    Decimal(18, 4),
    country    LowCardinality(String),

    -- Aggregate projection for common dashboard query
    PROJECTION proj_hourly_revenue (
        SELECT
            tenant_id,
            toStartOfHour(event_time) AS hour,
            event_type,
            country,
            count()       AS cnt,
            uniqExact(user_id) AS users,
            sum(revenue)  AS total_rev
        GROUP BY tenant_id, hour, event_type, country
    ),

    -- Normal projection for different sort order
    PROJECTION proj_by_user (
        SELECT * ORDER BY (user_id, event_time)
        -- enables fast single-user queries without full scan
    )
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_type, event_time, user_id);

-- Materialize projections for existing data:
ALTER TABLE events_with_projection MATERIALIZE PROJECTION proj_hourly_revenue;
ALTER TABLE events_with_projection MATERIALIZE PROJECTION proj_by_user;

-- Query: optimizer automatically uses projection if beneficial
SELECT tenant_id, toStartOfHour(event_time), count()
FROM events_with_projection
WHERE tenant_id = 1
GROUP BY tenant_id, toStartOfHour(event_time);
-- ClickHouse may use proj_hourly_revenue automatically

-- Force projection (debugging):
SELECT count() FROM events_with_projection
WHERE user_id = 12345    -- uses proj_by_user (sorted by user_id)
SETTINGS optimize_use_projections = 1;

-- Check if projection was used:
EXPLAIN indexes = 1
SELECT ...;
-- Look for: "Projection: proj_hourly_revenue"
```

---

## 6. Query Profiling & Optimization

### 6.1 EXPLAIN

```sql
-- EXPLAIN SYNTAX: show normalized SQL
EXPLAIN SYNTAX
SELECT * FROM events WHERE toDate(event_time) = today();
-- Output: normalized form (ClickHouse may rewrite predicates)

-- EXPLAIN AST: abstract syntax tree
EXPLAIN AST SELECT count() FROM events WHERE tenant_id = 1;

-- EXPLAIN PLAN: logical query plan
EXPLAIN PLAN
SELECT tenant_id, count()
FROM events
WHERE tenant_id = 1 AND event_time >= today() - 7
GROUP BY tenant_id;

-- EXPLAIN indexes=1: show index usage
EXPLAIN indexes = 1
SELECT count() FROM events
WHERE tenant_id = 1 AND event_type = 'purchase';
-- Output shows: parts read, granules read, skip indexes applied

-- EXPLAIN PIPELINE: physical execution pipeline
EXPLAIN PIPELINE
SELECT event_type, count()
FROM events
GROUP BY event_type
SETTINGS max_threads = 8;
-- Shows parallel execution plan
```

### 6.2 system.query_log

```sql
-- All executed queries are logged here
SELECT
    query_id,
    user,
    query_start_time,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes)      AS read_data,
    formatReadableSize(memory_usage)    AS memory,
    result_rows,
    exception,
    ProfileEvents['DiskReadElapsedMicroseconds'] / 1000 AS disk_ms,
    ProfileEvents['NetworkReceiveElapsedMicroseconds'] / 1000 AS net_ms,
    -- How much data was actually scanned vs needed:
    read_rows / result_rows             AS selectivity_ratio
FROM system.query_log
WHERE
    type = 'QueryFinish'
    AND query_start_time >= now() - INTERVAL 1 HOUR
    AND query_duration_ms > 1000   -- slow queries (> 1s)
ORDER BY query_duration_ms DESC
LIMIT 20;

-- Find full table scans (no index used):
SELECT query, read_rows, query_duration_ms
FROM system.query_log
WHERE
    type = 'QueryFinish'
    AND read_rows > 100_000_000   -- read > 100M rows
    AND query_start_time >= today()
ORDER BY read_rows DESC;

-- Memory-heavy queries:
SELECT query, formatReadableSize(memory_usage), query_duration_ms
FROM system.query_log
WHERE type = 'QueryFinish' AND memory_usage > 1e9
ORDER BY memory_usage DESC LIMIT 10;
```

### 6.3 system.parts & system.part_log

```sql
-- Check merge health:
SELECT
    table,
    count()                               AS parts_count,
    sum(rows)                             AS total_rows,
    formatReadableSize(sum(bytes_on_disk)) AS total_size,
    max(level)                            AS max_level
FROM system.parts
WHERE active = 1 AND database = 'analytics'
GROUP BY table
ORDER BY parts_count DESC;
-- Warning: parts_count > 300 → too many small parts → batch your inserts

-- Recent merges:
SELECT
    table,
    event_type,
    duration_ms,
    formatReadableSize(size_in_bytes) AS merged_size,
    rows
FROM system.part_log
WHERE event_time >= now() - INTERVAL 1 HOUR
ORDER BY event_time DESC;

-- Check column compression:
SELECT
    column,
    formatReadableSize(data_compressed_bytes)   AS compressed,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed,
    round(data_uncompressed_bytes / data_compressed_bytes, 2) AS ratio
FROM system.columns
WHERE table = 'events_raw' AND database = 'analytics'
ORDER BY data_compressed_bytes DESC;
```

### 6.4 Performance Optimization Checklist

```sql
-- ① Check if query uses primary index:
EXPLAIN indexes = 1 SELECT ...;
-- If Granules: 10000/10000 → no pruning → review ORDER BY

-- ② Check partition pruning:
EXPLAIN partitions = 1 SELECT ...;
-- If many partitions read → add partition filter to WHERE

-- ③ Check column pruning:
-- ClickHouse reads only needed columns → use SELECT only required columns
SELECT event_type, count()      -- ✅ reads 2 columns
FROM events;
SELECT *                        -- ❌ reads ALL columns (expensive)
FROM events;

-- ④ Avoid functions on indexed columns in WHERE:
WHERE toDate(event_time) = '2024-01-01'   -- ❌ function prevents index use
WHERE event_time >= '2024-01-01' AND event_time < '2024-01-02'  -- ✅

-- ⑤ Use PREWHERE for heavy filters:
SELECT * FROM events
PREWHERE event_type = 'purchase'  -- pre-filter with lightweight check
WHERE revenue > 1000;             -- full filter after pre-filter
-- PREWHERE: reads only filter column first → skip rows early

-- ⑥ Avoid ORDER BY + LIMIT on large datasets:
SELECT * FROM events ORDER BY revenue DESC LIMIT 10;  -- may sort billions!
-- Better: add index on revenue OR use TopK aggregation
SELECT topK(10)(revenue, event_id) FROM events;   -- approximate top 10

-- ⑦ JOIN: put smaller table on the right
SELECT l.*, r.name
FROM large_fact l           -- left: large
JOIN small_dim r ON ...;    -- right: small (built into hash table)
```

---

## 7. Memory & Parallelism Settings

```sql
-- Per-query settings:
SELECT ... FROM large_table
SETTINGS
    max_threads = 16,                     -- parallel threads (default: num CPUs)
    max_memory_usage = 20000000000,       -- 20GB per query
    max_bytes_before_external_sort = 1e10, -- spill sort to disk after 10GB
    max_bytes_before_external_group_by = 1e10, -- spill GROUP BY to disk
    group_by_two_level_threshold = 100000, -- switch to 2-level hash for large GROUP BY
    join_algorithm = 'parallel_hash',
    optimize_read_in_order = 1,           -- optimize ORDER BY using sort key
    read_in_order_two_level_merge_threshold = 100; -- for merge step

-- Profile current query resource usage:
SELECT
    query_id,
    ProfileEvents['RealTimeMicroseconds'] / 1e6  AS real_s,
    ProfileEvents['UserTimeMicroseconds'] / 1e6  AS cpu_s,
    ProfileEvents['ReadBufferFromFileDescriptorReadBytes'] / 1e6 AS io_mb,
    ProfileEvents['MergedRows']                  AS merged_rows
FROM system.query_log
WHERE query_id = 'your-query-id';

-- Server-wide settings (config.xml):
-- <max_server_memory_usage_to_ram_ratio>0.8</max_server_memory_usage_to_ram_ratio>
-- <background_pool_size>16</background_pool_size>
-- <background_merges_mutations_concurrency_ratio>2</background_merges_mutations_concurrency_ratio>
```

---

## Ghi chú – Keywords tiếp theo

- **clickhouse_operations.md**: ReplicatedMergeTree + Keeper, Distributed table, sharding key, ON CLUSTER DDL, clickhouse-backup, FREEZE, ALTER mutations, system.mutations, Prometheus exporter, Grafana dashboards
- **Keywords**: sparse index granule, PREWHERE optimization, adaptive granularity, projection vs materialized view, skip index false positive, bloom_filter FPP, tokenbf token split, ngrambf n-gram, TTL move disk, partition detach/attach, clickhouse-local
