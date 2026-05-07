# Roadmap Tổng Hợp Kiến Thức ClickHouse – Cơ Bản đến Nâng Cao

## Cấu trúc thư mục
```
clickhouse/
├── roadmap.md                        ← file này
├── clickhouse_fundamentals.md        ← Architecture, Columnar Storage, OLAP vs OLTP, MergeTree internals
├── clickhouse_engines.md             ← MergeTree family, Log engines, Integration engines, Special engines
├── clickhouse_sql.md                 ← SQL dialect, Arrays, Maps, JSON, Window functions, CTEs, ASOF JOIN
├── clickhouse_performance.md         ← Primary index, Skip indexes, Partitioning, Materialized Views, Projections
├── clickhouse_operations.md          ← Replication, Sharding, Distributed tables, Backup, Monitoring
└── clickhouse_production.md          ← Schema design, Query optimization, Integration (Kafka/S3/Spark), Use cases
```

> **Prerequisite**: Hiểu SQL cơ bản, RDBMS, distributed systems basics

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Fundamentals – What/Why ClickHouse, Columnar vs Row storage, OLAP vs OLTP, Architecture (shards/replicas/ZooKeeper/ClickHouse Keeper), MergeTree storage engine internals (parts, granules, marks), Read/Write path | clickhouse_fundamentals.md | ✅ |
| 2 | Table Engines – MergeTree family (MergeTree/ReplacingMergeTree/SummingMergeTree/AggregatingMergeTree/CollapsingMergeTree/VersionedCollapsingMergeTree/GraphiteMergeTree), Log engines, Integration engines (Kafka/S3/JDBC/PostgreSQL), Dictionary engine, Buffer, Null, MaterializedView | clickhouse_engines.md | ✅ |
| 3 | SQL & Data Types – Arrays (arrayJoin/groupArray), Tuples, Maps, Nested, JSON (JSONExtract), LowCardinality, Nullable, UUID, Window functions, CTEs, ASOF JOIN, JOIN algorithms, SAMPLE, FINAL, GROUP BY ROLLUP/CUBE/GROUPING SETS | clickhouse_sql.md | ✅ |
| 4 | Performance – Primary key & sparse index (granules/marks), Skip indexes (minmax/bloom_filter/set/tokenbf), Partitioning strategy, Materialized Views (incremental aggregation), Projections (alternative sort orders), Query profiling (system.query_log/EXPLAIN) | clickhouse_performance.md | ✅ |
| 5 | Operations – ReplicatedMergeTree + ZooKeeper/Keeper, Distributed table (sharding key/replication factor), ClickHouse Keeper vs ZooKeeper, Backup (clickhouse-backup/FREEZE/S3), ALTER mutations, TTL, System tables, Monitoring (Prometheus/Grafana) | clickhouse_operations.md | ✅ |
| 6 | Production – Schema design (wide vs narrow, star schema), Deduplication strategies, Kafka→ClickHouse pipeline, S3 as cold storage, Integration with dbt/Spark/Superset, Multi-tenancy, Cost optimization, Real-world use cases | clickhouse_production.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Quick Reference: ClickHouse vs Alternatives

| | ClickHouse | PostgreSQL | BigQuery | Apache Druid | TimescaleDB |
|--|-----------|-----------|---------|-------------|------------|
| **Storage** | Columnar | Row | Columnar | Columnar | Row + chunks |
| **Workload** | OLAP | OLTP/OLAP | OLAP | OLAP/real-time | Time-series |
| **Latency** | Milliseconds | Milliseconds | Seconds | Milliseconds | Milliseconds |
| **Scale** | Petabytes | Terabytes | Petabytes | Petabytes | Terabytes |
| **Ingestion** | High (1M rows/s) | Low | Batch | High (Kafka) | Medium |
| **SQL** | Full dialect | Full SQL | Full SQL | Partial | Full SQL |
| **Self-hosted** | ✅ | ✅ | ❌ Cloud | ✅ | ✅ |
| **Best for** | Analytics, logs | Transactions | Serverless analytics | Event streams | IoT, metrics |

---

## ClickHouse Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        ClickHouse Cluster                               │
│                                                                         │
│  ┌─────────────┐    ┌─────────────────────────────────────────────┐    │
│  │  Client     │    │              Shard 1                         │    │
│  │  (HTTP/TCP) │───►│  ┌──────────────┐  ┌──────────────────────┐│    │
│  └─────────────┘    │  │  Replica 1   │  │  Replica 2           ││    │
│                     │  │  (Leader)    │  │  (Follower)          ││    │
│  ┌─────────────┐    │  └──────┬───────┘  └──────────┬───────────┘│    │
│  │  Distributed│    │         │                      │            │    │
│  │  Table      │    │  ┌──────▼──────────────────────▼──────────┐│    │
│  │  (routing)  │    │  │  ClickHouse Keeper (Consensus)         ││    │
│  └─────────────┘    │  └─────────────────────────────────────────┘│    │
│                     └─────────────────────────────────────────────┘    │
│                                                                         │
│                     ┌─────────────────────────────────────────────┐    │
│                     │              Shard 2                         │    │
│                     │  ┌──────────────┐  ┌──────────────────────┐│    │
│                     │  │  Replica 1   │  │  Replica 2           ││    │
│                     │  └──────────────┘  └──────────────────────┘│    │
│                     └─────────────────────────────────────────────┘    │
│                                                                         │
│  Storage Layer:                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  MergeTree Parts (immutable data parts on disk)                  │  │
│  │  Column files (.bin) + Marks (.mrk) + Primary index (.idx)       │  │
│  │  + Skip indexes + Partition key directories                       │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## MergeTree Engine Family

```
MergeTree (base)
├── ReplicatedMergeTree          ← HA replication via Keeper
├── ReplacingMergeTree           ← Deduplication by version
├── SummingMergeTree             ← Pre-aggregate SUM
├── AggregatingMergeTree         ← Pre-aggregate any function
├── CollapsingMergeTree          ← Sign-based row cancellation
├── VersionedCollapsingMergeTree ← CollapsingMergeTree + version
└── GraphiteMergeTree            ← Graphite metrics rollup
```
