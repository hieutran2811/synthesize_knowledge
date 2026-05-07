# ClickHouse Production Patterns

## Mục lục
1. [Schema Design – Wide Table vs Star Schema](#1-schema-design--wide-table-vs-star-schema)
2. [Deduplication Strategies](#2-deduplication-strategies)
3. [Kafka → ClickHouse Pipeline](#3-kafka--clickhouse-pipeline)
4. [S3 Tiered Storage & Data Lake](#4-s3-tiered-storage--data-lake)
5. [Integration – dbt, Superset, Spark](#5-integration--dbt-superset-spark)
6. [Multi-tenancy Patterns](#6-multi-tenancy-patterns)
7. [Cost Optimization](#7-cost-optimization)
8. [Real-world Use Cases](#8-real-world-use-cases)

---

## 1. Schema Design – Wide Table vs Star Schema

### 1.1 Wide (Denormalized) Table – ClickHouse Best Practice

```sql
-- ClickHouse khuyến nghị: DENORMALIZE data trước khi load
-- Avoid JOINs at query time → pre-join at ingestion

-- ❌ Normalized (PostgreSQL-style):
-- events(event_id, user_id, event_type_id, session_id, created_at)
-- users(user_id, email, name, country, tier, created_at)
-- event_types(event_type_id, name, category)
-- sessions(session_id, device, browser, os)
-- → JOINs at query time → slow on 1B+ rows

-- ✅ Wide table (ClickHouse-style):
CREATE TABLE events_wide (
    -- Event dimensions
    event_id        UInt64,
    event_time      DateTime,
    event_type      LowCardinality(String),
    event_category  LowCardinality(String),

    -- User dimensions (denormalized from users table)
    user_id         UInt64,
    user_email      String,
    user_country    LowCardinality(String),
    user_tier       LowCardinality(String),
    user_created_at Date,

    -- Session dimensions (denormalized)
    session_id      String,
    device_type     LowCardinality(String),
    browser         LowCardinality(String),
    os              LowCardinality(String),

    -- Metrics
    revenue         Decimal(18, 4),
    latency_ms      UInt32,

    -- Tenant
    tenant_id       UInt32
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events_wide',
    '{replica}'
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_type, event_time, user_id)
TTL event_time + INTERVAL 2 YEAR DELETE;
```

### 1.2 Star Schema (when JOINs are acceptable)

```sql
-- Use star schema when:
-- 1. Dimension tables change frequently (e.g., user tier updates)
-- 2. Dimension data is too large to denormalize (e.g., full user profile)
-- 3. Using dictionaries for O(1) dimension lookups

-- Fact table (narrow, fast inserts):
CREATE TABLE fact_events (
    event_id    UInt64,
    event_time  DateTime,
    event_type  LowCardinality(String),
    user_id     UInt64,
    tenant_id   UInt32,
    revenue     Decimal(18, 4)
)
ENGINE = ReplicatedMergeTree(...)
ORDER BY (tenant_id, event_type, event_time);

-- Dimension: via Dictionary (O(1) lookup, cached in memory)
CREATE DICTIONARY dim_users (
    user_id  UInt64,
    country  LowCardinality(String),
    tier     LowCardinality(String)
)
PRIMARY KEY user_id
SOURCE(CLICKHOUSE(TABLE 'users_snapshot' DB 'analytics'))
LAYOUT(HASHED())
LIFETIME(300);  -- refresh every 5 minutes

-- Query: dictGet instead of JOIN
SELECT
    event_type,
    dictGet('dim_users', 'country', user_id) AS country,
    dictGet('dim_users', 'tier', user_id)    AS tier,
    count()    AS events,
    sum(revenue) AS revenue
FROM fact_events
WHERE tenant_id = 1 AND event_time >= today() - 30
GROUP BY event_type, country, tier;
-- dictGet: ~100ns per lookup vs JOIN: 100ms+
```

### 1.3 Column Design Best Practices

```sql
-- ① Use LowCardinality for strings with < 10k distinct values
event_type    LowCardinality(String)   -- ✅
country       LowCardinality(String)   -- ✅ 200 countries
user_id       UInt64                   -- ❌ LowCardinality (millions unique)
email         String                   -- ❌ LowCardinality (millions unique)

-- ② CODEC per column for optimal compression
CREATE TABLE events_optimized (
    event_id    UInt64             CODEC(Delta(8), ZSTD(3)),   -- sequential IDs → delta
    event_time  DateTime           CODEC(Delta(4), ZSTD(3)),   -- timestamps → delta
    user_id     UInt64             CODEC(ZSTD(3)),
    revenue     Decimal(18,4)      CODEC(Gorilla, ZSTD(3)),    -- float-like → Gorilla
    latency_ms  UInt32             CODEC(T64, ZSTD(3)),        -- small ints → T64
    event_type  LowCardinality(String),                         -- inherits LZ4 default
    payload     String             CODEC(ZSTD(9))              -- high compression for blobs
)
ENGINE = MergeTree() ORDER BY (event_time, user_id);

-- ③ Avoid storing redundant data
-- ❌ Store both event_time (DateTime) and date (Date) — compute at query time
-- date Date,                    -- redundant
-- event_time DateTime,
-- ✅ Just store DateTime, use toDate() at query time:
-- toDate(event_time) → free computation

-- ④ Use appropriate integer sizes
ip_address  UInt32    -- IPv4 fits in 4 bytes (vs String = 15+ bytes)
http_status UInt16    -- 0-65535 is enough for status codes
is_mobile   UInt8     -- boolean as 0/1
year        UInt16    -- 1900-2155 fits in UInt16
```

---

## 2. Deduplication Strategies

### 2.1 Exactly-once Ingestion

```sql
-- Problem: Kafka at-least-once → possible duplicate events

-- Strategy 1: INSERT DEDUP via settings
INSERT INTO events_raw
SETTINGS deduplicate_blocks_in_dependent_materialized_views = 1
VALUES (...);
-- ClickHouse deduplicates INSERTs by block checksum (within ~100 most recent blocks)
-- Inserting same data twice → second insert ignored
-- Works well with idempotent producers

-- Strategy 2: ReplacingMergeTree with deduplicate queries
CREATE TABLE events_dedup (
    event_id   String,    -- client-generated UUID
    event_time DateTime,
    event_type LowCardinality(String),
    user_id    UInt64,
    revenue    Decimal(18,4),
    -- version for replacing:
    ingest_time DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(ingest_time)
ORDER BY (event_id);  -- deduplicate by event_id

-- Query (with FINAL for consistency):
SELECT event_id, event_type, revenue
FROM events_dedup FINAL
WHERE event_time >= today() - 7;

-- Or without FINAL (approximate, faster):
SELECT event_id, argMax(revenue, ingest_time) AS revenue
FROM events_dedup
WHERE event_time >= today() - 7
GROUP BY event_id;
```

### 2.2 Pre-deduplication in Pipeline

```sql
-- Best: deduplicate BEFORE inserting into ClickHouse
-- Use Kafka Streams / Flink to deduplicate in streaming layer

-- Or: two-stage dedup with staging table
CREATE TABLE events_staging (
    event_id   String,
    event_time DateTime,
    payload    String
) ENGINE = MergeTree()
  ORDER BY (event_id, event_time)
  TTL event_time + INTERVAL 1 HOUR DELETE;  -- auto-cleanup staging

-- Dedup pipeline (batch job every minute):
INSERT INTO events_production
SELECT DISTINCT ON (event_id)  -- ClickHouse 23.1+
    event_id, event_time, payload
FROM events_staging
WHERE event_time >= now() - INTERVAL 2 MINUTE
  AND event_id NOT IN (
      SELECT event_id FROM events_production
      WHERE event_time >= now() - INTERVAL 2 MINUTE
  );
```

---

## 3. Kafka → ClickHouse Pipeline

### 3.1 Production Architecture

```
Kafka (events topic)
    │
    ▼
ClickHouse Kafka Engine Table (queue)
    │ (Materialized View trigger)
    ▼
events_raw (ReplicatedMergeTree) ← main storage
    │
    ├── events_hourly_mv (MV → AggregatingMergeTree)  ← dashboard
    ├── events_error_mv  (MV → MergeTree, errors only) ← alerting
    └── events_daily_mv  (MV → AggregatingMergeTree)   ← reports
```

### 3.2 Production Kafka Integration

```sql
-- 1. Kafka Consumer Table (one per topic, acts as queue)
CREATE TABLE kafka_events_queue ON CLUSTER production_cluster
(
    -- Match Kafka message schema EXACTLY
    event_id    String,
    tenant_id   UInt32,
    user_id     Int64,         -- may be -1 for anonymous
    event_type  String,
    event_time  Int64,         -- unix millis from Kafka
    properties  String         -- JSON
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list       = 'kafka1:9092,kafka2:9092,kafka3:9092',
    kafka_topic_list        = 'user-events-v2',
    kafka_group_name        = 'clickhouse-ingestion-v1',
    kafka_format            = 'JSONEachRow',
    kafka_num_consumers     = 4,
    kafka_max_block_size    = 65536,
    kafka_skip_broken_messages = 100,
    kafka_commit_every_batch = 0;  -- commit only after successful MV write

-- 2. Target Storage Table
CREATE TABLE events_raw ON CLUSTER production_cluster
(
    event_id    String,
    tenant_id   UInt32,
    user_id     UInt64,
    event_type  LowCardinality(String),
    event_time  DateTime64(3),     -- millisecond precision
    country     LowCardinality(String),
    browser     LowCardinality(String),
    revenue     Decimal(18, 4),
    is_error    UInt8,
    properties  Map(String, String)
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events_raw',
    '{replica}'
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_type, event_time, user_id)
TTL toDateTime(event_time) + INTERVAL 2 YEAR DELETE;

-- 3. Materialized View: Kafka → events_raw (with transformation)
CREATE MATERIALIZED VIEW kafka_events_mv ON CLUSTER production_cluster
TO events_raw
AS SELECT
    event_id,
    tenant_id,
    toUInt64(greatest(user_id, 0))          AS user_id,
    lower(event_type)                        AS event_type,
    toDateTime64(event_time / 1000, 3)       AS event_time,
    JSONExtractString(properties, 'country') AS country,
    JSONExtractString(properties, 'browser') AS browser,
    toDecimal64(JSONExtractFloat(properties, 'revenue'), 4) AS revenue,
    JSONExtractBool(properties, 'is_error')  AS is_error,
    CAST(properties, 'Map(String, String)')  AS properties
FROM kafka_events_queue
WHERE event_id != ''              -- filter invalid events
  AND tenant_id > 0;

-- 4. Monitor Kafka consumer lag:
SELECT
    topic,
    partition,
    consumer_group_member,
    consumer_lag
FROM system.kafka_consumers
WHERE table = 'kafka_events_queue';
```

### 3.3 Error Handling

```sql
-- Dead Letter Queue for failed messages:
CREATE TABLE kafka_dlq (
    raw_message  String,
    error        String,
    ts           DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY ts
TTL ts + INTERVAL 7 DAY DELETE;

-- Alternative: use kafka_skip_broken_messages + monitor broken_messages metric
SELECT
    event_time,
    error,
    broken_messages
FROM system.kafka_consumers
WHERE broken_messages > 0;

-- Replay from specific Kafka offset (restart consumer):
-- 1. Stop MV (detach):
DETACH TABLE kafka_events_mv;
-- 2. Reset consumer group offset (via Kafka CLI):
--    kafka-consumer-groups.sh --reset-offsets --to-datetime 2024-01-01T10:00:00
-- 3. Reattach MV:
ATTACH TABLE kafka_events_mv;
```

---

## 4. S3 Tiered Storage & Data Lake

### 4.1 Hot-Cold-Archive Tiering

```xml
<!-- storage_configuration in config.xml -->
<storage_configuration>
  <disks>
    <!-- Hot: local NVMe SSD -->
    <hot>
      <type>local</type>
      <path>/mnt/nvme/clickhouse/</path>
    </hot>
    <!-- Warm: S3 Standard -->
    <s3_warm>
      <type>s3</type>
      <endpoint>https://s3.ap-southeast-1.amazonaws.com/my-ch-bucket/warm/</endpoint>
      <access_key_id>ACCESS_KEY</access_key_id>
      <secret_access_key>SECRET_KEY</secret_access_key>
      <cache_enabled>true</cache_enabled>
      <cache_path>/mnt/ssd/s3_cache/</cache_path>
      <cache_max_size>107374182400</cache_max_size>  <!-- 100GB cache -->
    </s3_warm>
    <!-- Cold: S3 Glacier Instant -->
    <s3_cold>
      <type>s3</type>
      <endpoint>https://s3.ap-southeast-1.amazonaws.com/my-ch-bucket/cold/</endpoint>
      <access_key_id>ACCESS_KEY</access_key_id>
      <secret_access_key>SECRET_KEY</secret_access_key>
      <cache_enabled>false</cache_enabled>
    </s3_cold>
  </disks>

  <policies>
    <hot_warm_cold>
      <volumes>
        <hot_vol>
          <disk>hot</disk>
          <max_data_part_size_bytes>1073741824</max_data_part_size_bytes>  <!-- 1GB -->
        </hot_vol>
        <warm_vol>
          <disk>s3_warm</disk>
        </warm_vol>
        <cold_vol>
          <disk>s3_cold</disk>
        </cold_vol>
      </volumes>
      <!-- Move to next volume when current is 80% full -->
      <move_factor>0.2</move_factor>
    </hot_warm_cold>
  </policies>
</storage_configuration>
```

```sql
-- Table using tiered storage + TTL:
CREATE TABLE events_tiered (...)
ENGINE = ReplicatedMergeTree(...)
ORDER BY (tenant_id, event_time)
SETTINGS storage_policy = 'hot_warm_cold'
TTL event_time + INTERVAL 7 DAY    TO DISK 's3_warm',   -- move to S3 warm after 7 days
    event_time + INTERVAL 90 DAY   TO DISK 's3_cold',   -- move to S3 cold after 90 days
    event_time + INTERVAL 3 YEAR   DELETE;               -- delete after 3 years

-- Manual move:
ALTER TABLE events_tiered MOVE PARTITION '202401' TO DISK 's3_warm';
```

### 4.2 S3 as Data Lake (external tables)

```sql
-- Query Parquet files in S3 directly (no import needed):
SELECT
    event_type,
    count()       AS cnt,
    sum(revenue)  AS total_revenue
FROM s3(
    'https://s3.amazonaws.com/data-lake/events/year=2024/month=01/*.parquet',
    'ACCESS_KEY', 'SECRET_KEY',
    'Parquet'
)
WHERE event_type != ''
GROUP BY event_type;

-- Hive-partitioned S3:
SELECT count()
FROM s3(
    'https://s3.amazonaws.com/data-lake/events/year={2023..2024}/month={01..12}/*.parquet',
    'ACCESS_KEY', 'SECRET_KEY',
    'Parquet'
)
WHERE toYear(event_time) = 2024;

-- S3Queue Engine (ClickHouse 23.3+): auto-ingest files as they arrive
CREATE TABLE s3_auto_ingest (...)
ENGINE = S3Queue(
    'https://s3.amazonaws.com/landing-zone/events/*.jsonl',
    'ACCESS_KEY', 'SECRET_KEY',
    'JSONEachRow'
)
SETTINGS
    mode = 'ordered',              -- process files in order
    s3queue_loading_retries = 3,
    s3queue_processing_threads_num = 4;

CREATE MATERIALIZED VIEW s3_to_events_mv
TO events_raw
AS SELECT * FROM s3_auto_ingest;
```

---

## 5. Integration – dbt, Superset, Spark

### 5.1 dbt + ClickHouse

```yaml
# profiles.yml
clickhouse_prod:
  target: prod
  outputs:
    prod:
      type: clickhouse
      schema: analytics_dbt
      host: ch.internal
      port: 8123
      user: dbt_user
      password: "{{ env_var('CH_PASSWORD') }}"
      secure: false
      cluster: production_cluster
      on_cluster_include_policies: true
```

```sql
-- models/events_hourly.sql
{{ config(
    materialized='incremental',
    engine='ReplicatedAggregatingMergeTree',
    order_by='(tenant_id, hour, event_type)',
    partition_by='toYYYYMM(hour)',
    on_cluster='production_cluster',
    unique_key='(tenant_id, hour, event_type)'
) }}

SELECT
    tenant_id,
    toStartOfHour(event_time)    AS hour,
    event_type,
    countState()                 AS total_events,
    uniqState(user_id)           AS unique_users,
    sumState(revenue)            AS total_revenue
FROM {{ ref('events_raw') }}
{% if is_incremental() %}
    WHERE event_time >= (SELECT max(hour) - INTERVAL 2 HOUR FROM {{ this }})
{% endif %}
GROUP BY tenant_id, hour, event_type
```

### 5.2 Apache Superset

```python
# Superset: add ClickHouse datasource via SQLAlchemy URI
# clickhouse+http://user:password@host:8123/database
# OR for TLS:
# clickhouse+https://user:password@host:8443/database

# Install:
# pip install clickhouse-sqlalchemy

# Sample Superset chart SQL:
"""
SELECT
    toDate(event_time)  AS date,
    event_type,
    sum(revenue)        AS revenue
FROM events_wide
WHERE event_time >= {{ from_dttm }} AND event_time < {{ to_dttm }}
  AND tenant_id = {{ filter_values('tenant_id')|join(',') }}
GROUP BY date, event_type
ORDER BY date
"""
```

### 5.3 Spark + ClickHouse

```python
# spark-clickhouse-connector (Yandex/ClickHouse)
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .config("spark.jars.packages", "com.clickhouse:clickhouse-jdbc:0.4.6") \
    .getOrCreate()

# Read from ClickHouse:
df = spark.read \
    .format("jdbc") \
    .option("url", "jdbc:clickhouse://ch.internal:8123/analytics") \
    .option("dbtable", "(SELECT * FROM events_raw WHERE event_time >= now() - INTERVAL 1 DAY) t") \
    .option("driver", "com.clickhouse.jdbc.ClickHouseDriver") \
    .option("user", "spark_user") \
    .option("password", "password") \
    .load()

# Write to ClickHouse:
df.write \
    .format("jdbc") \
    .option("url", "jdbc:clickhouse://ch.internal:8123/analytics") \
    .option("dbtable", "events_processed") \
    .option("batchsize", "100000") \
    .mode("append") \
    .save()
```

---

## 6. Multi-tenancy Patterns

### 6.1 Schema-per-Tenant vs Shared Table

```sql
-- Pattern 1: Shared table with tenant_id column (recommended)
-- Pro: single schema, easy maintenance
-- Con: tenant can query other tenant's data if ACL weak

CREATE TABLE events (
    tenant_id  UInt32,   -- partition/filter by this
    ...
)
ENGINE = ReplicatedMergeTree(...)
ORDER BY (tenant_id, event_time);

-- Row-level security via user-level settings:
-- In user config or via SQL:
CREATE ROW POLICY tenant_policy ON analytics.events
    AS RESTRICTIVE FOR SELECT
    USING tenant_id = currentSetting('custom.tenant_id')::UInt32
    TO tenant_role;

-- Set at session level:
SET custom.tenant_id = '123';
SELECT count() FROM events;  -- only sees tenant 123

-- Pattern 2: Database-per-tenant (strong isolation)
-- Pro: complete isolation, easy DROP DATABASE
-- Con: schema changes require ON CLUSTER × N tenants
CREATE DATABASE tenant_123;
CREATE TABLE tenant_123.events (...);

-- Pattern 3: Cluster-per-tenant (enterprise)
-- Pro: hardware isolation, custom settings per tenant
-- Con: expensive, operational overhead
```

### 6.2 Quota & Resource Limits

```xml
<!-- users.xml: per-tenant resource limits -->
<quotas>
  <tenant_quota>
    <interval>
      <duration>3600</duration>         <!-- per hour -->
      <queries>1000</queries>           <!-- max 1000 queries/hour -->
      <errors>100</errors>
      <result_rows>1000000000</result_rows>  <!-- max 1B rows returned -->
      <read_rows>10000000000</read_rows>     <!-- max 10B rows read -->
      <execution_time>300</execution_time>   <!-- max 300s total -->
    </interval>
  </tenant_quota>
</quotas>

<profiles>
  <tenant_profile>
    <max_memory_usage>10000000000</max_memory_usage>  <!-- 10GB per query -->
    <max_execution_time>60</max_execution_time>       <!-- 60s max -->
    <max_rows_to_read>1000000000</max_rows_to_read>   <!-- 1B rows -->
    <max_concurrent_queries_for_user>5</max_concurrent_queries_for_user>
    <priority>10</priority>                            <!-- lower = higher priority -->
  </tenant_profile>
</profiles>
```

---

## 7. Cost Optimization

### 7.1 Storage Optimization

```sql
-- 1. Choose right CODEC per column (can reduce 5-10x):
-- event_time: Delta + ZSTD → timestamps compress well
-- user_id: ZSTD → random UInt64, standard compression
-- event_type: LowCardinality → 10-100x compression vs String

-- 2. Right-size data types:
-- UInt8 for booleans, UInt16 for HTTP status, UInt32 for IPv4
-- Date instead of DateTime if time not needed
-- Int32 instead of Int64 if values fit

-- 3. TTL to remove old data:
TTL event_time + INTERVAL 1 YEAR DELETE;

-- 4. Cold storage on S3 (10x cheaper than SSD):
TTL event_time + INTERVAL 30 DAY TO DISK 's3_cold';

-- 5. Check what's taking space:
SELECT
    database, table, column,
    formatReadableSize(sum(data_compressed_bytes)) AS compressed
FROM system.parts_columns
WHERE active = 1
GROUP BY database, table, column
ORDER BY sum(data_compressed_bytes) DESC
LIMIT 20;
```

### 7.2 Compute Optimization

```sql
-- 1. Materialized views reduce query compute:
-- Instead of GROUP BY 1B rows → query 1M pre-aggregated rows
-- 1000x less CPU per dashboard refresh

-- 2. Projections for common query patterns:
-- No need to full-scan for frequent queries

-- 3. Query resource limits to prevent runaway:
SET max_execution_time = 30;        -- 30s hard limit
SET max_memory_usage = 5000000000;  -- 5GB limit
SET max_rows_to_read = 500000000;   -- 500M rows limit

-- 4. Async inserts to reduce write overhead:
SET async_insert = 1;
-- Batches small inserts → fewer parts → fewer merges → less CPU

-- 5. Sampling for approximate analytics:
SELECT
    event_type,
    count() * 100 AS approx_count,   -- multiply by 1/sample_rate
    uniq(user_id) * 100 AS approx_users
FROM events SAMPLE 0.01               -- read only 1% of data
GROUP BY event_type;
-- 100x faster, ~1% error (acceptable for dashboards)

-- 6. Use uniq() instead of uniqExact() for cardinality:
-- uniq(): HyperLogLog, ~1% error, much faster
-- uniqExact(): exact, requires all values in memory

-- 7. Partition-aware queries:
-- Always include partition key in WHERE → skip irrelevant months
WHERE event_time BETWEEN '2024-01-01' AND '2024-01-31'  -- ✅ reads only 202401
WHERE user_id = 12345                                    -- ❌ scans ALL partitions
```

---

## 8. Real-world Use Cases

### 8.1 Web Analytics (Yandex.Metrica-style)

```sql
-- Design: one wide table per event type or universal event table
CREATE TABLE page_views (
    session_id    String,
    visitor_id    UInt64,        -- cookied user
    user_id       Nullable(UInt64), -- logged-in user
    site_id       UInt32,
    page_url      String,
    referrer      String,
    view_time     DateTime64(3),
    duration_ms   UInt32,
    country       LowCardinality(String),
    city          LowCardinality(String),
    device_type   LowCardinality(String),   -- desktop/mobile/tablet
    browser       LowCardinality(String),
    os            LowCardinality(String),
    viewport_w    UInt16,
    viewport_h    UInt16,
    is_bounce     UInt8
)
ENGINE = ReplicatedMergeTree(...)
PARTITION BY toYYYYMM(view_time)
ORDER BY (site_id, toDate(view_time), visitor_id);

-- Dashboard queries:
-- Unique visitors per day:
SELECT toDate(view_time) AS day, uniq(visitor_id) AS visitors
FROM page_views WHERE site_id = 1 AND view_time >= today() - 30
GROUP BY day ORDER BY day;

-- Bounce rate:
SELECT
    page_url,
    count() AS views,
    countIf(is_bounce = 1) AS bounces,
    round(countIf(is_bounce = 1) / count() * 100, 1) AS bounce_rate
FROM page_views
WHERE site_id = 1 AND view_time >= today() - 7
GROUP BY page_url
ORDER BY views DESC LIMIT 20;
```

### 8.2 Log Analytics (Elasticsearch Alternative)

```sql
-- ClickHouse can replace Elasticsearch for log aggregations
-- (not full-text search, but much faster for aggregations)

CREATE TABLE application_logs (
    ts          DateTime64(3),
    level       LowCardinality(String),
    service     LowCardinality(String),
    instance    LowCardinality(String),
    trace_id    String,
    span_id     String,
    message     String,
    extra       Map(String, String),
    INDEX idx_message (message) TYPE tokenbf_v1(65536, 3, 0) GRANULARITY 1,
    INDEX idx_trace   (trace_id) TYPE bloom_filter(0.01)    GRANULARITY 1
)
ENGINE = ReplicatedMergeTree(...)
PARTITION BY toDate(ts)
ORDER BY (service, level, ts)
TTL ts + INTERVAL 30 DAY DELETE;

-- Full-text-like search:
SELECT ts, service, level, message
FROM application_logs
WHERE service = 'api-gateway'
  AND ts >= now() - INTERVAL 1 HOUR
  AND message LIKE '%connection timeout%'
ORDER BY ts DESC LIMIT 100;

-- Error rate per service:
SELECT
    toStartOfMinute(ts)    AS minute,
    service,
    countIf(level = 'ERROR') AS errors,
    count()                AS total,
    errors / total * 100   AS error_rate
FROM application_logs
WHERE ts >= now() - INTERVAL 1 HOUR
GROUP BY minute, service
ORDER BY minute, error_rate DESC;
```

### 8.3 Time-series Metrics

```sql
-- Store Prometheus-style metrics:
CREATE TABLE metrics (
    ts          DateTime64(3),
    metric_name LowCardinality(String),
    labels      Map(String, String),    -- {host='server1', env='prod'}
    value       Float64
)
ENGINE = ReplicatedMergeTree(...)
PARTITION BY toYYYYMMDD(ts)
ORDER BY (metric_name, toUnixTimestamp(ts))
TTL ts + INTERVAL 90 DAY
    TO DISK 's3_cold',
    ts + INTERVAL 1 YEAR
    DELETE;

-- Prometheus-style queries via ClickHouse:
-- Rate (change per second):
SELECT
    ts,
    metric_name,
    (value - lagInFrame(value, 1, value) OVER w)
    / (toUnixTimestamp(ts) - toUnixTimestamp(lagInFrame(ts, 1, ts) OVER w)) AS rate_per_sec
FROM metrics
WHERE metric_name = 'http_requests_total'
  AND labels['env'] = 'prod'
  AND ts >= now() - INTERVAL 1 HOUR
WINDOW w AS (PARTITION BY metric_name, labels ORDER BY ts)
ORDER BY ts;

-- Downsampling (1s → 1m):
SELECT
    toStartOfMinute(ts) AS minute,
    metric_name,
    labels,
    avg(value) AS avg_val,
    max(value) AS max_val,
    min(value) AS min_val
FROM metrics
WHERE metric_name IN ('cpu_usage', 'memory_usage')
  AND ts >= now() - INTERVAL 24 HOUR
GROUP BY minute, metric_name, labels
ORDER BY minute;
```

### 8.4 Fraud Detection

```sql
-- Real-time fraud signals:
CREATE TABLE transaction_events (
    tx_id       String,
    user_id     UInt64,
    ts          DateTime64(3),
    amount      Decimal(18, 4),
    merchant_id UInt32,
    country     LowCardinality(String),
    device_fp   String,             -- device fingerprint
    ip          IPv4,
    is_fraud    UInt8 DEFAULT 0
)
ENGINE = ReplicatedMergeTree(...)
ORDER BY (user_id, ts);

-- Fraud detection queries:
-- Velocity: too many transactions in short window
SELECT user_id, count() AS tx_count, sum(amount) AS total
FROM transaction_events
WHERE ts >= now() - INTERVAL 1 HOUR
GROUP BY user_id
HAVING tx_count > 10 OR total > 10000;

-- Same device, multiple users (account sharing/takeover):
SELECT device_fp, uniq(user_id) AS users
FROM transaction_events
WHERE ts >= today()
GROUP BY device_fp
HAVING users > 3;

-- Geographic anomaly: login from unusual country:
SELECT
    user_id,
    groupArray(country)    AS countries,
    uniq(country)          AS unique_countries
FROM transaction_events
WHERE ts >= today() - 7
GROUP BY user_id
HAVING unique_countries >= 3;
```

---

## Trade-offs Summary

| Pattern | Performance | Consistency | Complexity | Use when |
|---------|-------------|-------------|-----------|----------|
| Wide denormalized table | ⭐⭐⭐⭐⭐ | Manual sync | Low | Most analytics |
| Star schema + dictionaries | ⭐⭐⭐⭐ | Auto via dict refresh | Medium | Changing dimensions |
| ReplacingMergeTree + FINAL | ⭐⭐⭐ | Strong | Low | CDC upserts |
| ReplacingMergeTree + argMax | ⭐⭐⭐⭐ | Strong | Medium | High-perf upserts |
| Kafka Materialized View | ⭐⭐⭐⭐⭐ | At-least-once | Medium | Real-time streaming |
| S3 tiered storage | ⭐⭐⭐ (cold slower) | Strong | Medium | Cost optimization |
| Projections | ⭐⭐⭐⭐ | Automatic | Low | Multiple query patterns |
| Chained MVs | ⭐⭐⭐⭐⭐ | Eventual | High | Multi-granularity aggregation |

---

## Ghi chú – Keywords

- **ClickHouse Cloud**: managed ClickHouse, serverless tier, object storage by default
- **Altinity.Cloud**: managed ClickHouse on AWS/GCP/Azure
- **clickhouse-local**: local file processing with ClickHouse SQL (no server needed)
- **ClickHouse Playground**: https://play.clickhouse.com
- **Keywords**: Keeper consensus, ReplicatedAggregatingMergeTree, dictGet O(1) lookup, async_insert batching, insert_deduplicate, lightweight delete, PREWHERE optimization, S3Queue auto-ingest, S3 cache, dbt-clickhouse adapter, clickhouse-jdbc, ClickHouse HTTP interface, Native TCP protocol, RowBinary format for bulk inserts, FORMAT Parquet/ORC/Arrow, system.query_log profiling, EXPLAIN PIPELINE, ProfileEvents counters
