# Kafka Knowledge Roadmap

> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)

| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Architecture & Core Concepts | `fundamentals/architecture.md` | ✅ |
| 2 | Producers – Config & Guarantees | `fundamentals/producers.md` | ✅ |
| 3 | Consumers & Consumer Groups | `fundamentals/consumers.md` | ✅ |
| 4 | Storage: Log segments, Retention, Compaction, Tiered Storage & `__consumer_offsets` | `internals/storage.md` | ✅ |
| 5 | Replication & Fault Tolerance – ISR/HWM, ELR, clean/unclean election, rack awareness & KRaft quorum | `internals/replication.md` | ✅ |
| 6 | Kafka Streams – DSL, windows/joins, suppression, state stores, EOS & Streams Rebalance Protocol | `streams/kafka_streams.md` | ✅ |
| 7 | Kafka Connect & CDC – distributed workers/internal topics, plugin isolation, REST offset management, delivery semantics, JDBC/SMT, Debezium snapshot/WAL/slot/publication & MM2 | `streams/connect.md` | ✅ |
| 8 | Production Operations – OS/JVM/broker tuning, request-latency triage, SLO/error budget alerts, TLS/SASL/ACL, dynamic config/certificate rotation, runbook & MM2 DR | `operations/production.md` | ✅ |

### Bổ sung 2026-06 – Lấp gap chuyên gia (4 cụm)

| # | Topic | File | Status |
|---|-------|------|--------|
| 9 | Schema Registry & Schema Evolution – Confluent/Apicurio, Avro/Protobuf/JSON Schema, wire format (magic+id), subject naming strategies, **compatibility modes** (BACKWARD/FORWARD/FULL/transitive) + luật tiến hóa, schema references, serdes config | `ecosystem/schema_registry.md` | ✅ |
| 10 | ksqlDB & Stream Processing SQL – streams vs tables, **push vs pull query**, CSAS/CTAS persistent query, windowing/aggregation/joins, UDF/UDAF, connector qua SQL, so sánh Kafka Streams/Flink | `ecosystem/ksqldb.md` | ✅ |
| 11 | Event-Driven Architecture & Data Modeling (Kafka-native) – topic design/naming, **partition & key strategy** (ordering/throughput/hot partition), event design (notification/state-transfer/sourcing), delivery semantics + **idempotent consumer**, patterns (CQRS/Outbox/Saga/DLQ-retry topics/compacted table), anti-patterns | `patterns/event_driven_architecture.md` | ✅ |
| 12 | Cluster Operations Advanced (Day-2) – reassignment/dual throttle, broker cordon/drain, dynamic KRaft quorum, Cruise Control, client quota, rack-aware fetching, 4.3 rolling upgrade/finalization, recovery capacity & multi-cluster | `operations/cluster_operations.md` | ✅ |

## Learning Path

```
Cơ bản:   architecture → producers → consumers
Trung cấp: storage → replication → connect → schema_registry
Nâng cao:  kafka_streams → ksqldb → event_driven_architecture → production → cluster_operations
```

*Hoàn thành nền tảng (1–8): 2026-05-06; bổ sung (9–12): 2026-06-04; rà soát Storage, Replication, Streams, Connect, Production & Cluster Operations: 2026-07-27*
