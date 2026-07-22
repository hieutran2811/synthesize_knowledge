# Kafka Knowledge Roadmap

> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)

| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Architecture & Core Concepts | `fundamentals/architecture.md` | ✅ |
| 2 | Producers – Config & Guarantees | `fundamentals/producers.md` | ✅ |
| 3 | Consumers & Consumer Groups | `fundamentals/consumers.md` | ✅ |
| 4 | Storage: Log, Retention & Compaction | `internals/storage.md` | ✅ |
| 5 | Replication & Fault Tolerance | `internals/replication.md` | ✅ |
| 6 | Kafka Streams | `streams/kafka_streams.md` | ✅ |
| 7 | Kafka Connect & CDC | `streams/connect.md` | ✅ |
| 8 | Performance, Monitoring & Security | `operations/production.md` | ✅ |

### Bổ sung 2026-06 – Lấp gap chuyên gia (4 cụm)

| # | Topic | File | Status |
|---|-------|------|--------|
| 9 | Schema Registry & Schema Evolution – Confluent/Apicurio, Avro/Protobuf/JSON Schema, wire format (magic+id), subject naming strategies, **compatibility modes** (BACKWARD/FORWARD/FULL/transitive) + luật tiến hóa, schema references, serdes config | `ecosystem/schema_registry.md` | ✅ |
| 10 | ksqlDB & Stream Processing SQL – streams vs tables, **push vs pull query**, CSAS/CTAS persistent query, windowing/aggregation/joins, UDF/UDAF, connector qua SQL, so sánh Kafka Streams/Flink | `ecosystem/ksqldb.md` | ✅ |
| 11 | Event-Driven Architecture & Data Modeling (Kafka-native) – topic design/naming, **partition & key strategy** (ordering/throughput/hot partition), event design (notification/state-transfer/sourcing), delivery semantics + **idempotent consumer**, patterns (CQRS/Outbox/Saga/DLQ-retry topics/compacted table), anti-patterns | `patterns/event_driven_architecture.md` | ✅ |
| 12 | Cluster Operations Advanced (Day-2) – **partition reassignment** (throttle), scaling broker, **Cruise Control** (auto-balance/self-heal), **client quotas**, rack awareness (AZ fault tolerance + KIP-392 fetching), **rolling upgrade**, capacity planning, multi-cluster (MM2 vs Cluster Linking vs stretch) | `operations/cluster_operations.md` | ✅ |

## Learning Path

```
Cơ bản:   architecture → producers → consumers
Trung cấp: storage → replication → connect → schema_registry
Nâng cao:  kafka_streams → ksqldb → event_driven_architecture → production → cluster_operations
```

*Hoàn thành nền tảng (1–8): 2026-05-06; bổ sung (9–12): 2026-06-04*
