# ClickHouse Table Engines

## Mục lục
1. [MergeTree – Base Engine](#1-mergetree--base-engine)
2. [ReplacingMergeTree – Deduplication](#2-replacingmergetree--deduplication)
3. [SummingMergeTree – Pre-aggregation](#3-summingmergetree--pre-aggregation)
4. [AggregatingMergeTree – Custom Aggregation](#4-aggregatingmergetree--custom-aggregation)
5. [CollapsingMergeTree & VersionedCollapsingMergeTree](#5-collapsingmergetree--versionedcollapsingmergetree)
6. [Log Engines – Lightweight Tables](#6-log-engines--lightweight-tables)
7. [Integration Engines](#7-integration-engines)
8. [Special Engines](#8-special-engines)
9. [So sánh & Trade-offs](#9-so-sánh--trade-offs)

---

## 1. MergeTree – Base Engine

```sql
-- Full syntax với tất cả options
CREATE TABLE user_events
(
    -- Columns
    tenant_id     UInt32,
    user_id       UInt64,
    event_type    LowCardinality(String),
    event_time    DateTime,
    session_id    String,
    page_url      String,
    properties    Map(String, String),
    revenue       Decimal(18, 4) DEFAULT 0,
    created_at    DateTime DEFAULT now()
)
ENGINE = MergeTree()
-- Partition key: split data into directories
PARTITION BY toYYYYMM(event_time)
-- Sorting key: physical order + primary index
ORDER BY (tenant_id, event_type, event_time, user_id)
-- Primary key (optional, defaults to ORDER BY)
PRIMARY KEY (tenant_id, event_type, event_time)
-- Sample key for approximate queries
SAMPLE BY intHash32(user_id)
-- TTL: expire old data
TTL event_time + INTERVAL 1 YEAR DELETE,
    event_time + INTERVAL 90 DAY TO DISK 'cold_storage'
-- Table settings
SETTINGS
    index_granularity = 8192,           -- rows per granule (default)
    index_granularity_bytes = '10Mi',   -- adaptive granularity
    merge_max_block_size = 8192,
    storage_policy = 'hot_cold';        -- tiered storage

-- Thêm skip index sau khi tạo bảng
ALTER TABLE user_events
    ADD INDEX idx_session_id (session_id) TYPE bloom_filter(0.01) GRANULARITY 4;

ALTER TABLE user_events
    ADD INDEX idx_revenue (revenue) TYPE minmax GRANULARITY 8;
```

---

## 2. ReplacingMergeTree – Deduplication

### 2.1 Concept

```
Problem: INSERT same row multiple times (e.g., CDC upsert)
  Khi có cùng ORDER BY key → keep only latest version

How it works:
  - During merge: rows với cùng ORDER BY key → keep row với max(ver)
  - KHÔNG xóa duplicates ngay khi INSERT → chỉ xóa trong background merge
  - Phải dùng FINAL hoặc deduplication query để đọc unique

Use cases:
  - CDC (Change Data Capture) từ OLTP
  - Upsert patterns
  - Slowly Changing Dimensions (SCD Type 1)
```

```sql
CREATE TABLE users
(
    user_id       UInt64,
    email         String,
    name          String,
    status        LowCardinality(String),
    updated_at    DateTime,
    -- version column: higher = newer
    version       UInt64
)
ENGINE = ReplacingMergeTree(version)  -- version column
ORDER BY user_id;

-- Insert initial state
INSERT INTO users VALUES (1, 'alice@example.com', 'Alice', 'active', now(), 1);

-- "Update": insert new version
INSERT INTO users VALUES (1, 'alice@new.com', 'Alice Updated', 'active', now(), 2);

-- Without dedup (may see duplicates before merge):
SELECT * FROM users WHERE user_id = 1;
-- Result: both rows (before merge completes)

-- With FINAL keyword: force dedup at query time (slower)
SELECT * FROM users FINAL WHERE user_id = 1;
-- Result: one row (version=2)

-- Better approach: use argMax to avoid FINAL
SELECT
    user_id,
    argMax(email, version)      AS email,
    argMax(name, version)       AS name,
    argMax(status, version)     AS status,
    max(version)                AS version
FROM users
WHERE user_id = 1
GROUP BY user_id;
```

### 2.2 FINAL vs argMax trade-offs

```sql
-- FINAL:
--   Pro: syntactically simple
--   Con: single-threaded scan, slow on large tables
--        skips parallel processing
--        may still return duplicates if merge not done

-- argMax pattern:
--   Pro: parallel execution, more flexible
--   Con: verbose, must group by ALL non-aggregated columns

-- Optimize FINAL (ClickHouse v22.8+):
SELECT * FROM users FINAL
SETTINGS
    max_threads = 8,
    do_not_merge_across_partitions_select_final = 1; -- parallel per partition

-- Check for duplicates:
SELECT user_id, count() AS cnt
FROM users
GROUP BY user_id
HAVING cnt > 1;
-- If > 0: merge not completed yet, or version logic issue

-- Force merge (dev/testing only):
OPTIMIZE TABLE users FINAL;
```

---

## 3. SummingMergeTree – Pre-aggregation

```sql
-- Use case: real-time counters (page views, revenue per day)
-- Merges rows with same ORDER BY key by summing numeric columns

CREATE TABLE daily_stats
(
    tenant_id   UInt32,
    date        Date,
    event_type  LowCardinality(String),
    -- These columns get summed during merge:
    views       UInt64,
    clicks      UInt64,
    revenue     Decimal(18, 4),
    -- Non-numeric columns: keep value from first row
    last_update DateTime
)
ENGINE = SummingMergeTree((views, clicks, revenue))
-- Explicit columns to sum (optional; default: all numeric)
PARTITION BY toYYYYMM(date)
ORDER BY (tenant_id, date, event_type);

-- Insert incremental updates throughout the day
INSERT INTO daily_stats VALUES (1, '2024-01-01', 'page_view', 100, 10, 0, now());
INSERT INTO daily_stats VALUES (1, '2024-01-01', 'page_view', 200, 20, 5.50, now());
INSERT INTO daily_stats VALUES (1, '2024-01-01', 'page_view', 50,  5,  1.25, now());

-- Query: sum at query time to handle pre-merge state
SELECT
    tenant_id,
    date,
    event_type,
    sum(views)   AS total_views,   -- sum again at query time!
    sum(clicks)  AS total_clicks,
    sum(revenue) AS total_revenue
FROM daily_stats
WHERE date = '2024-01-01'
GROUP BY tenant_id, date, event_type;
-- Result: views=350, clicks=35, revenue=6.75

-- After merge: same query gives same result
-- (rows merged to: 1, 2024-01-01, page_view, 350, 35, 6.75)

-- IMPORTANT: always GROUP BY + sum() at query time
-- Don't rely on single-row result without GROUP BY
```

---

## 4. AggregatingMergeTree – Custom Aggregation

### 4.1 Concept

```
More powerful than SummingMergeTree:
  - Store partial aggregation states (not final values)
  - Any aggregate function: uniq, quantile, topK, etc.
  - Merged during background merge
  - Final computation at query time with -Merge suffix functions
  
Use case: materialized views for pre-computed analytics
```

```sql
-- Raw events table
CREATE TABLE events_raw
(
    tenant_id  UInt32,
    event_time DateTime,
    event_type LowCardinality(String),
    user_id    UInt64,
    revenue    Decimal(18, 4)
)
ENGINE = MergeTree()
ORDER BY (tenant_id, event_time, event_type);

-- Aggregating table (stores partial states)
CREATE TABLE events_agg
(
    tenant_id         UInt32,
    hour              DateTime,
    event_type        LowCardinality(String),
    -- AggregateFunction stores internal state (not final value)
    total_events      AggregateFunction(count),
    unique_users      AggregateFunction(uniq, UInt64),
    total_revenue     AggregateFunction(sum, Decimal(18, 4)),
    p95_response      AggregateFunction(quantile(0.95), Float32)
)
ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (tenant_id, hour, event_type);

-- Materialized view to auto-populate:
CREATE MATERIALIZED VIEW events_agg_mv
TO events_agg
AS SELECT
    tenant_id,
    toStartOfHour(event_time)   AS hour,
    event_type,
    countState()                AS total_events,    -- State suffix!
    uniqState(user_id)          AS unique_users,
    sumState(revenue)           AS total_revenue,
    quantileState(0.95)(0.0)    AS p95_response    -- placeholder
FROM events_raw
GROUP BY tenant_id, hour, event_type;

-- Query with -Merge suffix to finalize aggregation:
SELECT
    tenant_id,
    hour,
    event_type,
    countMerge(total_events)    AS events,
    uniqMerge(unique_users)     AS users,
    sumMerge(total_revenue)     AS revenue
FROM events_agg
WHERE hour >= toStartOfHour(now() - INTERVAL 24 HOUR)
GROUP BY tenant_id, hour, event_type
ORDER BY hour, events DESC;
```

### 4.2 SimpleAggregateFunction – Lighter Weight

```sql
-- For simple aggregations (min/max/sum/any):
-- Stores FINAL value, not state → cheaper than AggregateFunction

CREATE TABLE events_simple_agg
(
    tenant_id     UInt32,
    date          Date,
    event_type    LowCardinality(String),
    total_events  SimpleAggregateFunction(sum, UInt64),
    max_revenue   SimpleAggregateFunction(max, Decimal(18, 4)),
    last_seen     SimpleAggregateFunction(max, DateTime)
)
ENGINE = AggregatingMergeTree()
ORDER BY (tenant_id, date, event_type);

-- Insert: use -SimpleState (or direct value)
INSERT INTO events_simple_agg
SELECT
    tenant_id,
    toDate(event_time)  AS date,
    event_type,
    count()             AS total_events,
    max(revenue)        AS max_revenue,
    max(event_time)     AS last_seen
FROM events_raw
GROUP BY tenant_id, date, event_type;

-- Query: no -Merge needed (already final values, just sum for multi-part)
SELECT
    tenant_id,
    date,
    event_type,
    sum(total_events)   AS events,   -- still sum in case of multiple parts
    max(max_revenue)    AS revenue,
    max(last_seen)      AS last_seen
FROM events_simple_agg
GROUP BY tenant_id, date, event_type;
```

---

## 5. CollapsingMergeTree & VersionedCollapsingMergeTree

### 5.1 CollapsingMergeTree

```sql
-- Use case: mutable rows with sign column (+1 = insert, -1 = delete)
-- Pattern: to "update" a row, insert -1 cancel + +1 new

CREATE TABLE user_sessions
(
    user_id       UInt64,
    session_id    String,
    duration_sec  UInt32,
    pages_viewed  UInt16,
    sign          Int8    -- +1: valid row, -1: cancellation
)
ENGINE = CollapsingMergeTree(sign)
ORDER BY (user_id, session_id);

-- Insert initial state
INSERT INTO user_sessions VALUES (1, 'sess_abc', 120, 5, 1);

-- Update: cancel old + insert new
INSERT INTO user_sessions VALUES
    (1, 'sess_abc', 120, 5, -1),   -- cancel old
    (1, 'sess_abc', 180, 8, 1);    -- new values

-- Query: must apply sign at query time (before merge)
SELECT
    user_id,
    session_id,
    sum(duration_sec * sign) AS duration,
    sum(pages_viewed * sign) AS pages
FROM user_sessions
GROUP BY user_id, session_id
HAVING sum(sign) > 0;  -- filter out cancelled rows

-- Caveat: inserts must arrive in order (cancel before new)
-- Use VersionedCollapsingMergeTree for out-of-order
```

### 5.2 VersionedCollapsingMergeTree

```sql
-- Solves CollapsingMergeTree's ordering constraint
-- Cancel pair matched by: same ORDER BY key + same version

CREATE TABLE user_sessions_v
(
    user_id       UInt64,
    session_id    String,
    duration_sec  UInt32,
    pages_viewed  UInt16,
    sign          Int8,
    version       UInt64   -- monotonically increasing
)
ENGINE = VersionedCollapsingMergeTree(sign, version)
ORDER BY (user_id, session_id);

-- Insert state v1
INSERT INTO user_sessions_v VALUES (1, 'sess_abc', 120, 5, 1, 1);

-- Update (cancel v1 + insert v2, can arrive in any order)
INSERT INTO user_sessions_v VALUES
    (1, 'sess_abc', 120, 5, -1, 1),   -- cancel version 1
    (1, 'sess_abc', 180, 8, 1,  2);   -- new version 2

-- Query same as CollapsingMergeTree
```

---

## 6. Log Engines – Lightweight Tables

```sql
-- Log engines: no primary index, no ordering, append-only
-- Use for: small lookup tables, temporary data, system logs

-- TinyLog: one file per column, no marks — smallest overhead
-- Max ~1M rows, no concurrency
CREATE TABLE config_log (
    ts      DateTime,
    key     String,
    value   String
) ENGINE = TinyLog;

-- Log: similar to TinyLog but has marks for seek (faster for larger)
CREATE TABLE app_logs (
    ts      DateTime,
    level   LowCardinality(String),
    message String
) ENGINE = Log;

-- StripeLog: one stripe.bin for all columns + marks
-- Better for concurrent inserts than Log
CREATE TABLE access_log (
    ts         DateTime,
    client_ip  String,
    request    String,
    status     UInt16,
    bytes      UInt64
) ENGINE = StripeLog;

-- When to use Log engines:
-- ✅ Temporary staging tables
-- ✅ Small dimension tables (< 1M rows)
-- ✅ System-level logging
-- ❌ Production analytics (use MergeTree)
-- ❌ Large datasets
```

---

## 7. Integration Engines

### 7.1 Kafka Engine

```sql
-- Read from Kafka topic as a stream
CREATE TABLE kafka_events_queue
(
    event_id    String,
    user_id     UInt64,
    event_type  String,
    event_time  Int64,    -- unix timestamp from Kafka
    payload     String    -- JSON string
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka1:9092,kafka2:9092',
    kafka_topic_list = 'user-events',
    kafka_group_name = 'clickhouse-consumer-v1',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 4,        -- parallel consumers
    kafka_max_block_size = 65536,
    kafka_skip_broken_messages = 10; -- skip malformed messages

-- Materialized view to pipe Kafka → MergeTree
CREATE MATERIALIZED VIEW kafka_events_mv
TO events_raw
AS SELECT
    toUUID(event_id)                          AS event_id,
    user_id,
    event_type,
    toDateTime(event_time)                    AS event_time,
    JSONExtractString(payload, 'session_id')  AS session_id,
    JSONExtractFloat(payload, 'revenue')      AS revenue
FROM kafka_events_queue;

-- Check consumer lag:
SELECT *
FROM system.kafka_consumers
WHERE table = 'kafka_events_queue';
```

### 7.2 S3 Engine

```sql
-- Read/write directly from S3 (or S3-compatible: MinIO, GCS, Azure)
CREATE TABLE s3_events
(
    event_id   String,
    event_type String,
    event_time DateTime,
    user_id    UInt64
)
ENGINE = S3(
    'https://s3.amazonaws.com/my-bucket/events/*.parquet',
    'ACCESS_KEY_ID',
    'SECRET_ACCESS_KEY',
    'Parquet'           -- format: Parquet, ORC, CSV, JSONEachRow, etc.
);

-- Use S3 as cold storage (tiered storage):
CREATE TABLE events_tiered (...)
ENGINE = MergeTree()
TTL event_time + INTERVAL 30 DAY TO DISK 's3_cold'   -- move old data to S3
    event_time + INTERVAL 1 YEAR DELETE;               -- delete after 1 year

-- S3 disk config in storage_configuration.xml:
-- <disks><s3_cold><type>s3</type><endpoint>https://...</endpoint></s3_cold></disks>

-- S3 Table Function (ad-hoc queries):
SELECT count(), event_type
FROM s3('s3://my-bucket/events/2024-01-*.parquet', 'Parquet')
GROUP BY event_type;
```

### 7.3 PostgreSQL Engine

```sql
-- Read/write from PostgreSQL (live data)
CREATE TABLE pg_users
(
    id       UInt64,
    email    String,
    name     String,
    status   String
)
ENGINE = PostgreSQL(
    'host=pg.internal port=5432 dbname=myapp',
    'users',            -- table name
    'clickhouse_user',
    'password'
);

-- Join ClickHouse analytics with PostgreSQL dimensions:
SELECT
    e.event_type,
    u.name,
    count()     AS events
FROM events_raw e
JOIN pg_users u ON e.user_id = u.id
WHERE e.event_time >= today() - 7
GROUP BY e.event_type, u.name;

-- MaterializedPostgreSQL engine: replicate entire PG schema
CREATE DATABASE pg_replica
ENGINE = MaterializedPostgreSQL(
    'host=pg.internal port=5432 dbname=myapp',
    'replication_user', 'password'
)
SETTINGS
    materialized_postgresql_tables_list = 'users,orders,products';
-- Keeps in sync via logical replication (pg_publication)
```

### 7.4 JDBC / MySQL Engine

```sql
-- MySQL engine (native protocol)
CREATE TABLE mysql_orders
(
    order_id    UInt64,
    customer_id UInt64,
    total       Decimal(10, 2),
    status      String,
    created_at  DateTime
)
ENGINE = MySQL(
    'mysql.internal:3306',
    'ecommerce',     -- database
    'orders',        -- table
    'clickhouse',    -- user
    'password'
);

-- JDBC (requires clickhouse-jdbc-bridge):
CREATE TABLE jdbc_data (...)
ENGINE = JDBC('jdbc:oracle:thin:@host:1521:SID', 'schema', 'table');
```

---

## 8. Special Engines

### 8.1 Dictionary Engine

```sql
-- Fast in-memory key-value lookup
-- Load from external source, update periodically

CREATE DICTIONARY user_dict
(
    user_id     UInt64,
    name        String,
    country     LowCardinality(String),
    tier        LowCardinality(String)
)
PRIMARY KEY user_id
SOURCE(CLICKHOUSE(
    TABLE 'users_dim'
    DB 'analytics'
))
LAYOUT(HASHED())            -- hash map for O(1) lookup
LIFETIME(MIN 300 MAX 600);  -- refresh every 5-10 minutes

-- Use in query (much faster than JOIN):
SELECT
    event_type,
    dictGet('user_dict', 'country', user_id) AS country,
    dictGet('user_dict', 'tier', user_id)    AS tier,
    count()                                   AS events
FROM events_raw
GROUP BY event_type, country, tier;

-- Dictionary layouts:
-- FLAT:          array, fastest, only for small dicts (< 500k keys)
-- HASHED:        hash map, O(1), good for medium dicts
-- CACHE(SIZE_IN_CELLS 10000): LRU cache, for very large external dicts
-- RANGE_HASHED:  for time-ranged data (e.g., price history)
-- IP_TRIE:       for IP address → geo lookup
-- POLYGON:       for geo polygon → region lookup
```

### 8.2 Buffer Engine

```sql
-- Buffer writes in memory, flush to target table
-- Reduces write amplification for high-frequency small inserts

CREATE TABLE events_buffer AS events_raw
ENGINE = Buffer(
    currentDatabase(),   -- target database
    'events_raw',        -- target table
    16,                  -- num_layers (parallelism)
    10,                  -- min_time (seconds before flush)
    100,                 -- max_time (seconds, force flush)
    10000,               -- min_rows
    1000000,             -- max_rows
    10000000,            -- min_bytes (10MB)
    100000000            -- max_bytes (100MB)
);

-- Write to buffer:
INSERT INTO events_buffer VALUES (...);
-- Flushes to events_raw when: time OR rows OR bytes threshold reached

-- Caveat: data in buffer is LOST on server restart
-- Caveat: no deduplication, no consistency guarantees
```

### 8.3 Null Engine

```sql
-- Accepts any writes, stores nothing
-- Use: trigger materialized views without storing raw data

CREATE TABLE events_null (...)
ENGINE = Null;

CREATE MATERIALIZED VIEW events_hourly_mv TO events_hourly AS
SELECT
    toStartOfHour(event_time) AS hour,
    event_type,
    count() AS events
FROM events_null
GROUP BY hour, event_type;

-- Write to null table → only MV gets populated
INSERT INTO events_null VALUES (...);
```

---

## 9. So sánh & Trade-offs

| Engine | Dedup | Pre-agg | Use case | Query complexity |
|--------|-------|---------|----------|-----------------|
| MergeTree | ❌ | ❌ | Raw data, analytics | Simple |
| ReplacingMergeTree | ✅ (version) | ❌ | CDC upserts, dim tables | FINAL or argMax |
| SummingMergeTree | ❌ | SUM only | Simple counters | GROUP BY + sum() |
| AggregatingMergeTree | ❌ | Any function | Complex pre-aggregation | -Merge functions |
| CollapsingMergeTree | sign-based | ❌ | Mutable fact rows | sign in WHERE |
| VersionedCollapsing | sign+version | ❌ | Out-of-order mutable | sign in WHERE |
| Kafka | stream | ❌ | Real-time ingestion | MV required |
| S3 | ❌ | ❌ | Cold storage / data lake | Ad-hoc queries |

---

## Ghi chú – Keywords tiếp theo

- **clickhouse_sql.md**: Arrays, Tuples, Maps, Nested, LowCardinality, JSONExtract, window functions, ASOF JOIN, JOIN algorithms, GROUP BY ROLLUP/CUBE, SAMPLE, DISTINCT vs GROUP BY
- **Keywords**: ReplicatedMergeTree (replication), ON CLUSTER (distributed DDL), materialized view trigger, -State/-Merge function pairs, argMax pattern, SimpleAggregateFunction, dictGet, CODEC compression
