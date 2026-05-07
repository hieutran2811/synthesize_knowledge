# ClickHouse Fundamentals

## Mục lục
1. [What – ClickHouse là gì?](#1-what--clickhouse-là-gì)
2. [Why – Tại sao cần ClickHouse?](#2-why--tại-sao-cần-clickhouse)
3. [Columnar Storage vs Row Storage](#3-columnar-storage-vs-row-storage)
4. [OLAP vs OLTP](#4-olap-vs-oltp)
5. [Architecture – Thành phần hệ thống](#5-architecture--thành-phần-hệ-thống)
6. [MergeTree Internals – Cơ chế lưu trữ](#6-mergetree-internals--cơ-chế-lưu-trữ)
7. [Read & Write Path](#7-read--write-path)

---

## 1. What – ClickHouse là gì?

**ClickHouse** là open-source **columnar OLAP database management system** được phát triển bởi Yandex (2016), tối ưu cho **analytical workloads** với tốc độ query cực nhanh trên dữ liệu lớn.

```
Định nghĩa ngắn:
  ClickHouse = Column-oriented + OLAP + Real-time + High-throughput ingestion
  
Khả năng:
  - Query tốc độ: 100 tỷ rows/giây trên một server
  - Ingestion:    1–10 triệu rows/giây
  - Compression:  3–10x so với raw data (LZ4/ZSTD theo column)
  - Scale:        Petabytes trên commodity hardware
  
Không phải:
  - Không phải general-purpose database (kém OLTP)
  - Không hỗ trợ transactions (ACID limited)
  - Không tốt cho point lookups (single row by PK)
  - Không hỗ trợ UPDATE/DELETE theo cách truyền thống (mutations, async)
```

---

## 2. Why – Tại sao cần ClickHouse?

### 2.1 Vấn đề với RDBMS cho Analytics

```sql
-- Trên PostgreSQL: query trên 10 tỷ rows events
SELECT
    toStartOfDay(event_time) AS day,
    event_type,
    count()                  AS cnt,
    uniq(user_id)            AS users
FROM events
WHERE event_time >= '2024-01-01'
GROUP BY day, event_type
ORDER BY day, cnt DESC;

-- PostgreSQL: ~120s (full table scan, row-by-row)
-- ClickHouse: ~0.3s (columnar scan, vectorized execution)

-- Lý do:
-- PostgreSQL đọc toàn bộ row (kể cả columns không cần)
-- ClickHouse chỉ đọc 3 columns: event_time, event_type, user_id
-- + SIMD vectorized processing (AVX-512)
-- + Parallel execution trên tất cả CPU cores
```

### 2.2 Use cases điển hình

```
✅ Web analytics (Yandex.Metrica: 25 tỷ events/ngày)
✅ Application performance monitoring (APM)
✅ Log analytics (replace Elasticsearch cho aggregations)
✅ Business intelligence / dashboards (Superset, Grafana)
✅ Ad tech (impression/click tracking)
✅ IoT / time-series analytics
✅ Security analytics (SIEM)
✅ Real-time fraud detection
✅ Product analytics (Mixpanel-style)

❌ Online transaction processing (banking, e-commerce orders)
❌ Low-latency point queries (< 1ms lookup by PK)
❌ Frequent small updates
❌ Complex JOIN-heavy workloads (normalized schemas)
```

---

## 3. Columnar Storage vs Row Storage

### 3.1 Row Storage (PostgreSQL, MySQL)

```
Table: events (event_id, user_id, event_type, event_time, properties)

Row 1: [1, 1001, 'page_view', '2024-01-01 10:00', '{...}']
Row 2: [2, 1002, 'click',     '2024-01-01 10:01', '{...}']
Row 3: [3, 1001, 'purchase',  '2024-01-01 10:02', '{...}']
...

Disk layout (one block = multiple rows):
┌──────────────────────────────────────────────────────┐
│ 1│1001│page_view│2024-01-01 10:00│{...}│ 2│1002│... │
└──────────────────────────────────────────────────────┘

Query: SELECT count(), event_type FROM events GROUP BY event_type
→ Must read ALL columns per row (even unused ones)
→ Poor cache utilization for analytics
→ Good for: SELECT * WHERE id = 123 (single row fetch)
```

### 3.2 Columnar Storage (ClickHouse)

```
Same table stored column-by-column:

event_id.bin:    [1, 2, 3, 4, 5, 6, ...]
user_id.bin:     [1001, 1002, 1001, 1003, ...]
event_type.bin:  [page_view, click, purchase, page_view, ...]  ← LowCardinality compressed
event_time.bin:  [1704067200, 1704067260, ...]                 ← delta + LZ4
properties.bin:  [{...}, {...}, ...]                           ← ZSTD

Query: SELECT count(), event_type FROM events GROUP BY event_type
→ Only reads: event_type.bin (maybe event_id.bin for count)
→ Reads 10–100x LESS data vs row store
→ Column data is homogeneous → better compression
→ SIMD vectorized: process 256/512 values per CPU instruction

Compression example (event_type = repeated strings):
  Row store:   'page_view' × 1B = 9 bytes × 1B = 9GB
  Columnar:    Dictionary encode → 1 byte × 1B + dict = ~1GB (9x compression)
               LowCardinality → even better
```

### 3.3 Compression Deep Dive

```sql
-- ClickHouse compression per column
CREATE TABLE events (
    event_id    UInt64,
    user_id     UInt32,
    event_type  LowCardinality(String),   -- dictionary encoding, ~1 byte/value
    event_time  DateTime,                  -- delta encoding (differences)
    session_id  FixedString(36),           -- UUID string
    revenue     Decimal(18, 4)             -- precise numeric
)
ENGINE = MergeTree()
ORDER BY (event_type, event_time, user_id)
-- Default codec: LZ4 (fast) per column
-- Override per column:
-- event_time DateTime CODEC(Delta, ZSTD(3))  -- delta then compress
-- revenue Decimal CODEC(Gorilla, ZSTD)       -- floating point delta

-- Check compression ratio:
SELECT
    name,
    formatReadableSize(data_compressed_bytes)   AS compressed,
    formatReadableSize(data_uncompressed_bytes) AS uncompressed,
    round(data_uncompressed_bytes / data_compressed_bytes, 2) AS ratio
FROM system.columns
WHERE table = 'events' AND database = currentDatabase();
```

---

## 4. OLAP vs OLTP

| Dimension | OLTP (PostgreSQL, MySQL) | OLAP (ClickHouse, BigQuery) |
|-----------|-------------------------|---------------------------|
| **Workload** | Many small transactions | Few large analytical queries |
| **Operations** | INSERT/UPDATE/DELETE/SELECT | Mostly SELECT (aggregations) |
| **Query shape** | Point lookup, small result | Full scan, group by, aggregation |
| **Data freshness** | Real-time | Near real-time (seconds–minutes) |
| **Schema** | Normalized (3NF), many JOINs | Denormalized, wide tables |
| **Row count** | Millions | Billions–Trillions |
| **Response time** | < 10ms | Milliseconds–seconds |
| **Concurrency** | Thousands of connections | Tens–hundreds |
| **Storage** | Row-oriented | Column-oriented |
| **Index type** | B-Tree, Hash | Sparse index, Skip indexes |
| **UPDATE/DELETE** | Efficient | Expensive (mutations, async) |

```
Lambda Architecture với ClickHouse:
  
  Real-time data → Kafka → ClickHouse (hot data, last 30 days)
  Batch data    → S3     → ClickHouse (cold data, MergeTree TTL move)
  OLTP writes   → PostgreSQL → Debezium CDC → ClickHouse (read replica)
```

---

## 5. Architecture – Thành phần hệ thống

### 5.1 Single Node Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    ClickHouse Server                         │
│                                                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  │
│  │  HTTP Server  │  │  TCP Server   │  │  MySQL Port   │  │
│  │  (port 8123)  │  │  (port 9000)  │  │  (port 9004)  │  │
│  └───────┬───────┘  └───────┬───────┘  └───────┬───────┘  │
│          └──────────────────┼──────────────────┘           │
│                             ▼                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Query Interpreter                       │   │
│  │  Parser → Analyzer → Optimizer → Executor           │   │
│  └─────────────────────────┬───────────────────────────┘   │
│                             ▼                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Storage Engine (MergeTree)                 │   │
│  │  Buffer → Parts → Merges → Disk/S3                  │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Cluster Architecture

```xml
<!-- /etc/clickhouse-server/config.xml -->
<clickhouse>
  <remote_servers>
    <production_cluster>
      <!-- Shard 1 -->
      <shard>
        <weight>1</weight>
        <internal_replication>true</internal_replication>
        <replica>
          <host>ch-shard1-replica1.internal</host>
          <port>9000</port>
        </replica>
        <replica>
          <host>ch-shard1-replica2.internal</host>
          <port>9000</port>
        </replica>
      </shard>
      <!-- Shard 2 -->
      <shard>
        <weight>1</weight>
        <internal_replication>true</internal_replication>
        <replica>
          <host>ch-shard2-replica1.internal</host>
          <port>9000</port>
        </replica>
        <replica>
          <host>ch-shard2-replica2.internal</host>
          <port>9000</port>
        </replica>
      </shard>
    </production_cluster>
  </remote_servers>

  <!-- ClickHouse Keeper (replaces ZooKeeper, built-in) -->
  <zookeeper>
    <node>
      <host>ch-keeper1.internal</host>
      <port>9181</port>
    </node>
    <node>
      <host>ch-keeper2.internal</host>
      <port>9181</port>
    </node>
    <node>
      <host>ch-keeper3.internal</host>
      <port>9181</port>
    </node>
  </zookeeper>

  <!-- Macros: per-server variables for ReplicatedMergeTree paths -->
  <macros>
    <shard>01</shard>
    <replica>ch-shard1-replica1</replica>
    <cluster>production_cluster</cluster>
  </macros>
</clickhouse>
```

### 5.3 ClickHouse Keeper

```
ClickHouse Keeper (built since v22.4):
  - Replaces Apache ZooKeeper
  - Raft consensus algorithm (không phải ZAB như ZooKeeper)
  - Built-in trong ClickHouse server process
  - Lưu: replica metadata, part lists, distributed DDL queue

Dùng Keeper cho:
  - ReplicatedMergeTree: log của parts giữa replicas
  - Distributed DDL: ON CLUSTER queries
  - ClickHouse coordination

Cấu hình Keeper (standalone mode):
```

```xml
<!-- keeper_config.xml -->
<clickhouse>
  <keeper_server>
    <tcp_port>9181</tcp_port>
    <server_id>1</server_id>           <!-- unique per keeper node -->
    <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
    <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
    <coordination_settings>
      <operation_timeout_ms>10000</operation_timeout_ms>
      <session_timeout_ms>30000</session_timeout_ms>
      <raft_logs_level>warning</raft_logs_level>
    </coordination_settings>
    <raft_configuration>
      <server>
        <id>1</id>
        <hostname>ch-keeper1.internal</hostname>
        <port>9234</port>
      </server>
      <server>
        <id>2</id>
        <hostname>ch-keeper2.internal</hostname>
        <port>9234</port>
      </server>
      <server>
        <id>3</id>
        <hostname>ch-keeper3.internal</hostname>
        <port>9234</port>
      </server>
    </raft_configuration>
  </keeper_server>
</clickhouse>
```

---

## 6. MergeTree Internals – Cơ chế lưu trữ

### 6.1 Parts – Đơn vị lưu trữ cơ bản

```
Khi INSERT vào MergeTree:
  1. Data ghi vào memory buffer
  2. Flush thành một "part" (immutable directory on disk)
  3. Background merge: nhỏ parts → lớn parts (LSM-tree concept)
  4. Merged part xóa các parts cũ

Part structure:
/var/lib/clickhouse/data/{database}/{table}/
├── 20240101_1_1_0/          ← part name: {partition}_{min_block}_{max_block}_{level}
│   ├── primary.idx          ← sparse primary index
│   ├── event_id.bin         ← column data (compressed)
│   ├── event_id.mrk3        ← marks: offset trong .bin file
│   ├── event_type.bin
│   ├── event_type.mrk3
│   ├── event_time.bin
│   ├── event_time.mrk3
│   ├── count.bin
│   ├── count.mrk3
│   ├── columns.txt          ← column list
│   ├── checksums.txt        ← data integrity
│   └── minmax_event_time.idx ← partition key min/max
└── 20240102_2_2_0/

-- Check parts:
SELECT
    partition,
    name,
    rows,
    formatReadableSize(bytes_on_disk) AS size,
    marks,
    level
FROM system.parts
WHERE table = 'events' AND active = 1
ORDER BY partition, min_block_number;
```

### 6.2 Granules – Đơn vị đọc tối thiểu

```
Granule = 8192 rows (default index_granularity)

Tại sao 8192?
  - SIMD registers: 256/512 bits → process 4–16 UInt64 per cycle
  - 8192 × 8 bytes (UInt64) = 64KB ≈ L1/L2 cache line size
  - Tradeoff: large → fewer index entries → less precise pruning
              small → more index entries → more memory

primary.idx:
  Granule 0: [event_time = 2024-01-01 00:00:00]  (row 0)
  Granule 1: [event_time = 2024-01-01 02:16:32]  (row 8192)
  Granule 2: [event_time = 2024-01-01 04:33:04]  (row 16384)
  ...

event_time.mrk3 (marks file):
  Mark 0: offset_in_compressed=0,     offset_in_decompressed=0
  Mark 1: offset_in_compressed=4096,  offset_in_decompressed=0
  Mark 2: offset_in_compressed=8192,  offset_in_decompressed=0
  ...

Query: WHERE event_time BETWEEN '2024-01-01 10:00' AND '2024-01-01 11:00'
  → Binary search primary.idx → find granule range [G5, G7]
  → Read marks M5, M6, M7 → seek to offsets in .bin files
  → Decompress only those blocks
  → Filter rows within granules
```

### 6.3 Primary Key vs Sorting Key

```sql
-- Sorting key (ORDER BY) = physical sort order of data
-- Primary key = subset used for index (default = ORDER BY)

CREATE TABLE events (
    tenant_id   UInt32,
    event_type  LowCardinality(String),
    event_time  DateTime,
    user_id     UInt64,
    properties  String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)         -- split into monthly parts
ORDER BY (tenant_id, event_type, event_time)  -- sorting + primary key
PRIMARY KEY (tenant_id, event_type)       -- index only on first 2 columns
                                          -- event_time not in PK → less memory
-- Rule: PRIMARY KEY must be prefix of ORDER BY
-- ORDER BY: determines physical sort (for range scans)
-- PRIMARY KEY: determines what's in sparse index file

-- Good primary key design:
-- 1. High-cardinality columns at END (user_id → last)
-- 2. Columns used in WHERE at BEGINNING
-- 3. Columns used in GROUP BY after WHERE columns
-- ORDER BY (tenant_id, event_type, event_time, user_id)
--           ^filter    ^filter    ^range      ^high-card
```

---

## 7. Read & Write Path

### 7.1 Write Path

```
INSERT INTO events VALUES (...)
        │
        ▼
  ┌─────────────────────────────────────────────────────┐
  │  1. Parse & validate                                 │
  │  2. Sort data by ORDER BY key (within insert batch) │
  │  3. Split by PARTITION key                          │
  │  4. Write columnar files to new part directory      │
  │  5. Write primary.idx (every 8192 rows)             │
  │  6. Atomic rename → part is visible                 │
  │  7. Return success to client                        │
  └─────────────────┬───────────────────────────────────┘
                    │  async
                    ▼
  ┌─────────────────────────────────────────────────────┐
  │  Background Merge Process                           │
  │  - Select small adjacent parts                     │
  │  - Merge-sort them                                  │
  │  - Apply ReplacingMergeTree / SummingMergeTree etc │
  │  - Write merged part                               │
  │  - Delete old parts (after merge settles)          │
  └─────────────────────────────────────────────────────┘

-- Too many parts warning:
-- ClickHouse throws: "Too many parts (300)" if inserts too fast
-- Solution: batch inserts (1000–100000 rows per INSERT)
-- Or: use Buffer engine, async_insert mode
```

### 7.2 Async Insert (v22.5+)

```sql
-- Problem: many small inserts from application → too many parts
-- Solution: async_insert → server buffers and batches

-- Per-session:
SET async_insert = 1;
SET wait_for_async_insert = 1;   -- wait for flush (default: 0)
SET async_insert_max_data_size = '10Mi';   -- flush when buffer > 10MB
SET async_insert_busy_timeout_ms = 200;    -- flush after 200ms

-- Per-query:
INSERT INTO events SETTINGS async_insert=1, wait_for_async_insert=0
VALUES (...);

-- Or via user profile (config.xml):
-- <async_insert>1</async_insert>
-- <async_insert_max_data_size>10485760</async_insert_max_data_size>
```

### 7.3 Read Path

```
SELECT event_type, count() FROM events
WHERE event_time >= '2024-01-01'
GROUP BY event_type

        │
        ▼
  ┌─────────────────────────────────────────────────────┐
  │  Query Analysis & Planning                          │
  │  1. Parse SQL → AST                                 │
  │  2. Analyze: resolve columns, types                 │
  │  3. Optimize: push WHERE to storage                 │
  │     predicate pushdown, column pruning              │
  └─────────────────┬───────────────────────────────────┘
                    │
                    ▼
  ┌─────────────────────────────────────────────────────┐
  │  Storage Layer                                      │
  │  1. Partition pruning: skip non-matching months     │
  │  2. Primary index scan: find granule range          │
  │  3. Skip index check: bloom filter / minmax         │
  │  4. Read marks for relevant columns only            │
  │     (event_time + event_type only, not user_id)     │
  │  5. Decompress column blocks in parallel            │
  └─────────────────┬───────────────────────────────────┘
                    │
                    ▼
  ┌─────────────────────────────────────────────────────┐
  │  Execution                                          │
  │  1. Filter rows (event_time predicate)              │
  │  2. Vectorized GROUP BY aggregation (HashTable)     │
  │  3. Return result                                   │
  └─────────────────────────────────────────────────────┘

-- EXPLAIN query plan:
EXPLAIN PIPELINE
SELECT event_type, count()
FROM events
WHERE event_time >= '2024-01-01'
GROUP BY event_type;
```

---

## Ghi chú – Keywords tiếp theo

- **clickhouse_engines.md**: MergeTree family (ReplacingMergeTree/SummingMergeTree/AggregatingMergeTree/Collapsing), Log engines, Integration engines (Kafka/S3/PostgreSQL/JDBC), Buffer, Null, MaterializedView
- **Keywords**: LSM-tree, columnar compression, SIMD vectorization, sparse index, granule, mark file, part merge, ZooKeeper/Keeper, async_insert, mutation, TTL, LowCardinality, CODEC
