# ClickHouse Operations

## Mục lục
1. [Replication – ReplicatedMergeTree](#1-replication--replicatedmergetree)
2. [Sharding & Distributed Tables](#2-sharding--distributed-tables)
3. [ON CLUSTER – Distributed DDL](#3-on-cluster--distributed-ddl)
4. [Backup & Recovery](#4-backup--recovery)
5. [ALTER & Mutations](#5-alter--mutations)
6. [System Tables – Observability](#6-system-tables--observability)
7. [Monitoring – Prometheus & Grafana](#7-monitoring--prometheus--grafana)

---

## 1. Replication – ReplicatedMergeTree

### 1.1 How Replication Works

```
ReplicatedMergeTree replication mechanism:
  1. Replica 1 (leader) receives INSERT → writes local part
  2. Notifies ZooKeeper/Keeper: "part 202401_1_1_0 is ready"
  3. Replica 2 (follower) polls Keeper → sees new part notification
  4. Fetches part from Replica 1 via HTTP
  5. Both replicas now have the same part

Key insight:
  - NOT leader-based replication (any replica can receive writes)
  - Each replica independently decides to merge (but coordinates via Keeper)
  - Merge result must be identical (deterministic sort + merge algorithm)
  - Keeper stores: part list, merge queue, DDL log, mutations log
```

### 1.2 ReplicatedMergeTree Setup

```sql
-- Table creation (must have same path+table for replicas of same shard)
CREATE TABLE events_replicated ON CLUSTER production_cluster
(
    tenant_id   UInt32,
    event_time  DateTime,
    event_type  LowCardinality(String),
    user_id     UInt64,
    revenue     Decimal(18, 4)
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events_replicated',  -- Keeper path
    '{replica}'                                       -- replica identifier
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_type, event_time, user_id);

-- {shard} and {replica} are macros defined in config.xml:
-- <macros><shard>01</shard><replica>ch-shard1-replica1</replica></macros>

-- Different replicas of same shard share ZK path:
-- Replica 1: path='/clickhouse/tables/01/events', replica='ch-s1-r1'
-- Replica 2: path='/clickhouse/tables/01/events', replica='ch-s1-r2'
-- → Both are replicas of shard 01

-- Different shards use different paths:
-- Shard 01 Replica 1: path='/clickhouse/tables/01/events', replica='ch-s1-r1'
-- Shard 02 Replica 1: path='/clickhouse/tables/02/events', replica='ch-s2-r1'
```

### 1.3 Replication Status & Lag

```sql
-- Check replication queue (pending operations):
SELECT
    database,
    table,
    replica_name,
    num_tries,
    last_exception,
    create_time,
    type,
    new_part_name
FROM system.replication_queue
WHERE last_exception != ''
ORDER BY create_time;

-- Check replica health:
SELECT
    database,
    table,
    is_leader,
    can_become_leader,
    is_readonly,
    is_session_expired,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    log_max_index,
    log_pointer,
    log_max_index - log_pointer AS replication_lag,  -- entries behind
    total_replicas,
    active_replicas
FROM system.replicas
WHERE database = 'analytics'
ORDER BY replication_lag DESC;

-- Replication lag in seconds (from data):
SELECT
    hostName()                     AS replica,
    max(event_time)                AS last_event_time,
    now() - max(event_time)        AS lag_seconds
FROM events_replicated
SETTINGS max_replica_delay_for_distributed_queries = 0;  -- read from all replicas

-- Force sync replica (dangerous, blocks):
SYSTEM SYNC REPLICA events_replicated;

-- Check Keeper connection:
SELECT * FROM system.zookeeper WHERE path = '/clickhouse/tables/01/events_replicated/replicas';
```

### 1.4 Handling Readonly Mode

```sql
-- Replica goes readonly when:
--   - Keeper session expires
--   - Cannot connect to Keeper
--   - Too many parts (> 300 → readonly to prevent data loss)

-- Check readonly:
SELECT is_readonly, is_session_expired FROM system.replicas WHERE table = 'events_replicated';

-- Fix: restart Keeper connection
SYSTEM RESTART REPLICA events_replicated;
-- or
SYSTEM DROP REPLICA 'stale-replica-name' FROM TABLE events_replicated;

-- Too many parts fix: stop inserts, wait for merges, or force merge:
OPTIMIZE TABLE events_replicated PARTITION '202401' FINAL;
-- Then increase parts_to_delay_insert limit if needed:
ALTER TABLE events_replicated MODIFY SETTING parts_to_delay_insert = 600;
```

---

## 2. Sharding & Distributed Tables

### 2.1 Distributed Engine

```sql
-- Distributed table: proxy that routes to underlying tables on each shard
-- Does NOT store data itself

-- Step 1: Create ReplicatedMergeTree on each shard (ON CLUSTER)
CREATE TABLE events_local ON CLUSTER production_cluster
(
    tenant_id   UInt32,
    event_time  DateTime,
    event_type  LowCardinality(String),
    user_id     UInt64,
    revenue     Decimal(18, 4)
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/events_local',
    '{replica}'
)
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_type, event_time, user_id);

-- Step 2: Create Distributed table (on all nodes)
CREATE TABLE events ON CLUSTER production_cluster
(
    tenant_id   UInt32,
    event_time  DateTime,
    event_type  LowCardinality(String),
    user_id     UInt64,
    revenue     Decimal(18, 4)
)
ENGINE = Distributed(
    'production_cluster',   -- cluster name from config
    'analytics',            -- database
    'events_local',         -- local table name
    rand()                  -- sharding key: rand() = round-robin
    -- OR: cityHash64(tenant_id) % 2    → shard by tenant
    -- OR: intHash64(user_id)           → shard by user
    -- OR: cityHash64(user_id)          → consistent hash
);

-- INSERT into Distributed → sharded to local tables:
INSERT INTO events VALUES (...);
-- Data sent to one shard based on sharding_key

-- SELECT from Distributed → gathers from all shards:
SELECT event_type, count() FROM events GROUP BY event_type;
-- Executed on each shard → results merged on coordinator
```

### 2.2 Sharding Key Design

```sql
-- Sharding key considerations:
-- 1. Evenly distribute data (avoid hot shards)
-- 2. Minimize cross-shard queries (co-locate related data)
-- 3. Avoid skew (don't shard by low-cardinality key)

-- ✅ Random (round-robin): simple, even distribution
ENGINE = Distributed(cluster, db, table, rand());

-- ✅ By tenant_id: all data for one tenant on same shard
--   → tenant-scoped queries → no cross-shard JOIN
ENGINE = Distributed(cluster, db, table, cityHash64(tenant_id));

-- ✅ By user_id: all events for one user on same shard
ENGINE = Distributed(cluster, db, table, intHash64(user_id));

-- ❌ By country (skewed): US has 100x more traffic than small countries
ENGINE = Distributed(cluster, db, table, country);  -- WRONG

-- ❌ By time: all new data on one shard while others idle
ENGINE = Distributed(cluster, db, table, toYYYYMM(event_time));  -- WRONG

-- Check shard distribution:
SELECT
    shard_num,
    count()                              AS rows,
    formatReadableSize(sum(bytes))       AS size
FROM system.parts
WHERE table = 'events_local' AND active = 1
-- Run on each shard separately and compare
GROUP BY shard_num;
```

### 2.3 INSERT behavior

```sql
-- INSERT mode 1: immediate (default)
-- Distributed table sends data directly to target shard
SET insert_distributed_sync = 1;  -- wait for ack from shard (slower but safer)
SET insert_distributed_sync = 0;  -- async (faster, may lose on coordinator crash)

-- INSERT mode 2: via Distributed insert queue
-- Data written to coordinator disk first, then async forwarded
-- Survives coordinator restart
SET distributed_directory_monitor_sleep_time_ms = 100;
SET distributed_directory_monitor_max_sleep_time_ms = 30000;

-- Monitor pending sends:
SELECT * FROM system.distribution_queue
WHERE table = 'events'
AND error_count > 0;
```

---

## 3. ON CLUSTER – Distributed DDL

```sql
-- ON CLUSTER: execute DDL on all nodes simultaneously
-- Stores in Keeper → applied to all nodes even if some are down

-- Create table on all nodes:
CREATE TABLE events_local ON CLUSTER production_cluster (...)
ENGINE = ReplicatedMergeTree(...);

-- Alter on all nodes:
ALTER TABLE events_local ON CLUSTER production_cluster
    ADD COLUMN new_col String DEFAULT '';

ALTER TABLE events_local ON CLUSTER production_cluster
    ADD INDEX idx_col (new_col) TYPE bloom_filter(0.01) GRANULARITY 1;

ALTER TABLE events_local ON CLUSTER production_cluster
    MATERIALIZE INDEX idx_col;

-- Drop:
DROP TABLE IF EXISTS events_local ON CLUSTER production_cluster;

-- Monitor distributed DDL:
SELECT *
FROM system.distributed_ddl_queue
WHERE cluster = 'production_cluster'
ORDER BY entry_time DESC
LIMIT 20;

-- Failed DDL tasks:
SELECT *
FROM system.distributed_ddl_queue
WHERE status = 'ERROR'
ORDER BY entry_time DESC;
```

---

## 4. Backup & Recovery

### 4.1 BACKUP / RESTORE (v22.4+)

```sql
-- Native backup to S3:
BACKUP TABLE analytics.events_local
TO S3('https://s3.amazonaws.com/my-backup-bucket/clickhouse/20240101/', 'KEY', 'SECRET')
SETTINGS
    base_backup = S3('https://s3.amazonaws.com/my-backup-bucket/clickhouse/20231201/', 'KEY', 'SECRET');
-- Incremental backup: only changed parts since base_backup

-- Restore:
RESTORE TABLE analytics.events_local AS analytics.events_restored
FROM S3('https://s3.amazonaws.com/my-backup-bucket/clickhouse/20240101/', 'KEY', 'SECRET')
SETTINGS allow_non_empty_tables = false;

-- Backup entire database:
BACKUP DATABASE analytics
TO S3('s3://my-backup/clickhouse/full/', 'KEY', 'SECRET');

-- Backup on cluster:
BACKUP TABLE analytics.events_local ON CLUSTER production_cluster
TO S3('s3://my-backup/clickhouse/', 'KEY', 'SECRET')
SETTINGS distributed_ddl_task_timeout = 300;

-- Check backup status:
SELECT * FROM system.backups ORDER BY start_time DESC;
```

### 4.2 FREEZE – Hardlink Snapshot

```sql
-- FREEZE: creates hardlinks to part files → instant snapshot (no copy!)
-- Files in /var/lib/clickhouse/shadow/{N}/data/{db}/{table}/

ALTER TABLE events_local FREEZE PARTITION '202401';
-- Freezes only January 2024 partition

ALTER TABLE events_local FREEZE;
-- Freezes all partitions

-- Copy frozen parts to backup storage (not ClickHouse-managed):
-- $ cp -r /var/lib/clickhouse/shadow/1/ s3://backup/
-- $ rclone sync /var/lib/clickhouse/shadow/1/ s3://backup/

-- Restore from freeze:
-- 1. Copy parts to: /var/lib/clickhouse/data/{db}/{table}/detached/
-- 2. ALTER TABLE events_local ATTACH PARTITION '202401';

-- Remove old freeze shadows:
ALTER TABLE events_local UNFREEZE WITH NAME 'shadow_name';
-- Or manually: rm -rf /var/lib/clickhouse/shadow/1/
```

### 4.3 clickhouse-backup Tool

```bash
# clickhouse-backup: community tool for automated backups
# https://github.com/Altinity/clickhouse-backup

# Install
docker run altinity/clickhouse-backup

# Config: /etc/clickhouse-backup/config.yml
# s3:
#   bucket: my-backup
#   path: clickhouse/
#   region: ap-southeast-1

# Create backup:
clickhouse-backup create 2024-01-01-daily

# Upload to remote:
clickhouse-backup upload 2024-01-01-daily

# List backups:
clickhouse-backup list

# Restore:
clickhouse-backup download 2024-01-01-daily
clickhouse-backup restore 2024-01-01-daily

# Scheduled backup (cron):
# 0 2 * * * clickhouse-backup create-and-upload $(date +\%Y-\%m-\%d-daily)
```

---

## 5. ALTER & Mutations

### 5.1 Schema Changes

```sql
-- ClickHouse ALTER is generally instant (metadata change only):

-- Add column (instant):
ALTER TABLE events_local
    ADD COLUMN user_agent String DEFAULT ''
    AFTER revenue;

-- Drop column (instant metadata, async file cleanup):
ALTER TABLE events_local
    DROP COLUMN user_agent;

-- Modify column type (requires mutation → heavy!):
ALTER TABLE events_local
    MODIFY COLUMN revenue Float64;
-- This rewrites all column data → very heavy, avoid on huge tables

-- Rename column (instant):
ALTER TABLE events_local
    RENAME COLUMN revenue TO revenue_usd;

-- Change default:
ALTER TABLE events_local
    MODIFY COLUMN status DEFAULT 'active';

-- Add ON CLUSTER:
ALTER TABLE events_local ON CLUSTER production_cluster
    ADD COLUMN country LowCardinality(String) DEFAULT '';
```

### 5.2 Mutations – UPDATE/DELETE

```sql
-- ClickHouse doesn't have traditional UPDATE/DELETE
-- Mutations: async rewrites of parts

-- DELETE (mutation):
ALTER TABLE events_local
    DELETE WHERE user_id = 12345;
-- Marks rows in all parts → background process rewrites parts

-- UPDATE (mutation):
ALTER TABLE events_local
    UPDATE status = 'inactive'
    WHERE event_time < '2023-01-01' AND status = 'active';

-- Update multiple columns:
ALTER TABLE events_local
    UPDATE
        status = 'archived',
        country = 'UNKNOWN'
    WHERE event_time < '2022-01-01';

-- Monitor mutations:
SELECT
    table,
    mutation_id,
    command,
    create_time,
    parts_to_do,
    is_done,
    latest_fail_reason
FROM system.mutations
WHERE database = 'analytics'
ORDER BY create_time DESC;

-- Wait for mutation to complete:
-- Watch is_done = 1 in system.mutations

-- Kill stuck mutation:
KILL MUTATION WHERE database = 'analytics' AND table = 'events_local'
    AND mutation_id = '0000000001';

-- Lightweight DELETE (v22.8+): faster than mutation for recent data
DELETE FROM events_local WHERE event_time = '2024-01-15';
-- Uses mark-and-cleanup instead of full rewrite
-- Requires: allow_experimental_lightweight_delete = 1
```

### 5.3 Column Codec Changes

```sql
-- Change compression codec (requires mutation):
ALTER TABLE events_local
    MODIFY COLUMN event_time DateTime CODEC(Delta(4), ZSTD(3));

-- Check current codec:
SELECT name, compression_codec
FROM system.columns
WHERE table = 'events_local' AND database = 'analytics';
```

---

## 6. System Tables – Observability

```sql
-- ── Parts and Merge Health ────────────────────────────────────────────────
SELECT
    database,
    table,
    sum(rows)                              AS total_rows,
    count()                                AS parts_count,
    formatReadableSize(sum(bytes_on_disk)) AS disk_size,
    formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed,
    max(bytes_on_disk) / sum(bytes_on_disk) AS largest_part_ratio
FROM system.parts
WHERE active = 1
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC;

-- ── Active Queries ────────────────────────────────────────────────────────
SELECT
    query_id,
    user,
    elapsed,
    formatReadableSize(memory_usage) AS memory,
    read_rows,
    read_bytes,
    query
FROM system.processes
ORDER BY elapsed DESC;

-- Kill long-running query:
KILL QUERY WHERE query_id = 'abc123' SYNC;

-- ── Query Log ─────────────────────────────────────────────────────────────
SELECT
    toStartOfMinute(query_start_time)  AS minute,
    count()                            AS queries,
    avg(query_duration_ms)             AS avg_ms,
    quantile(0.95)(query_duration_ms)  AS p95_ms,
    sum(read_rows)                     AS total_rows_read
FROM system.query_log
WHERE type = 'QueryFinish' AND query_start_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute;

-- ── Merges ────────────────────────────────────────────────────────────────
SELECT
    database,
    table,
    round(progress * 100, 1)         AS progress_pct,
    formatReadableSize(total_size_bytes_compressed) AS size,
    elapsed,
    estimated_completion
FROM system.merges
ORDER BY elapsed DESC;

-- ── Disk Usage ────────────────────────────────────────────────────────────
SELECT
    name,
    path,
    formatReadableSize(free_space)  AS free,
    formatReadableSize(total_space) AS total,
    round((1 - free_space/total_space) * 100) AS used_pct
FROM system.disks;

-- ── Memory Usage ─────────────────────────────────────────────────────────
SELECT
    event_time,
    formatReadableSize(CurrentMetric_MemoryTracking) AS tracking,
    formatReadableSize(value)                         AS rss
FROM system.metric_log
WHERE metric = 'MemoryTracking'
ORDER BY event_time DESC
LIMIT 60;

-- ── Errors ────────────────────────────────────────────────────────────────
SELECT
    event_time,
    user,
    query_id,
    exception_code,
    exception,
    query
FROM system.query_log
WHERE type = 'ExceptionAfterStart' OR type = 'ExceptionBeforeStart'
ORDER BY event_time DESC
LIMIT 50;
```

---

## 7. Monitoring – Prometheus & Grafana

### 7.1 Prometheus Exporter

```xml
<!-- config.xml: enable built-in Prometheus exporter -->
<prometheus>
    <endpoint>/metrics</endpoint>
    <port>9363</port>
    <metrics>true</metrics>
    <events>true</events>
    <asynchronous_metrics>true</asynchronous_metrics>
    <errors>true</errors>
</prometheus>
```

```yaml
# prometheus.yml scrape config
scrape_configs:
  - job_name: clickhouse
    static_configs:
      - targets:
          - 'ch-shard1-r1.internal:9363'
          - 'ch-shard1-r2.internal:9363'
          - 'ch-shard2-r1.internal:9363'
          - 'ch-shard2-r2.internal:9363'
    metrics_path: /metrics
    scrape_interval: 15s
```

### 7.2 Key Metrics to Alert On

```yaml
# Grafana alert rules

# 1. High memory usage
- alert: ClickHouseHighMemoryUsage
  expr: ClickHouseMetrics_MemoryTracking / ClickHouseAsyncMetrics_TotalBytesOfMemory > 0.85
  for: 5m
  labels:
    severity: warning

# 2. Replication lag
- alert: ClickHouseReplicationLag
  expr: ClickHouseMetrics_ReplicatedChecks > 100
  for: 10m
  labels:
    severity: critical

# 3. Too many parts
- alert: ClickHouseTooManyParts
  expr: ClickHouseMetrics_PartsActive > 300
  for: 5m
  labels:
    severity: warning

# 4. Failed merges
- alert: ClickHouseFailedMerges
  expr: increase(ClickHouseProfileEvents_FailedInsertQueryCount[5m]) > 10
  labels:
    severity: critical

# 5. Slow queries
- alert: ClickHouseSlowQueries
  expr: rate(ClickHouseProfileEvents_SlowSelectQueryCount[5m]) > 0.1
  labels:
    severity: warning

# 6. Disk usage
- alert: ClickHouseDiskUsage
  expr: (ClickHouseAsyncMetrics_DiskUsed_default / 
         (ClickHouseAsyncMetrics_DiskUsed_default + ClickHouseAsyncMetrics_DiskAvailable_default)) > 0.8
  labels:
    severity: warning
```

### 7.3 Useful Queries for Dashboard

```sql
-- Ingestion rate (rows/second):
SELECT
    toStartOfMinute(event_time) AS minute,
    count() / 60                AS rows_per_second
FROM system.part_log
WHERE event_type = 'NewPart' AND event_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute;

-- Query throughput:
SELECT
    toStartOfMinute(query_start_time) AS minute,
    countIf(type = 'QueryFinish')     AS successful,
    countIf(type != 'QueryFinish')    AS failed,
    avg(query_duration_ms)            AS avg_duration_ms
FROM system.query_log
WHERE query_start_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute;

-- Top tables by size:
SELECT
    database,
    table,
    formatReadableSize(sum(bytes_on_disk)) AS size,
    sum(rows)                              AS rows,
    count()                                AS parts
FROM system.parts
WHERE active = 1
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 20;
```

---

## Ghi chú – Keywords tiếp theo

- **clickhouse_production.md**: Schema design (wide table vs star schema), deduplication strategies, Kafka→ClickHouse pipeline architecture, S3 cold storage tiering, dbt + ClickHouse, Superset integration, multi-tenancy isolation, cost optimization, real-world use cases
- **Keywords**: ReplicatedMergeTree Keeper path, distributed_ddl_queue, system.mutations, LIGHTWEIGHT DELETE, FREEZE hardlink, clickhouse-backup, Altinity, system.replication_queue, is_readonly repair, background merge settings, insert_distributed_sync, sharding key consistency
