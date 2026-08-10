---
title: "Kafka Knowledge Roadmap"
topic: kafka
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
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

### Observability chuyên sâu

| # | Topic | File | Status |
|---|-------|------|--------|
| 13 | Messaging & Kafka Observability – producer/broker/consumer signals, lag theo thời gian, end-to-end freshness, tracing, retry/DLQ và incident workflow | [`messaging_kafka_observability.md`](../prometheus_grafana/observability/messaging_kafka_observability.md) | ✅ |

## Learning Path

```
Cơ bản:   architecture → producers → consumers
Trung cấp: storage → replication → connect → schema_registry
Nâng cao:  kafka_streams → ksqldb → event_driven_architecture → production → cluster_operations
Vận hành:  cluster_operations → messaging_kafka_observability
```

*Hoàn thành nền tảng (1–8): 2026-05-06; bổ sung (9–12): 2026-06-04; rà soát Storage, Replication, Streams, Connect, Production & Cluster Operations: 2026-07-27; bổ sung Observability: 2026-07-30*

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [ksqlDB & Stream Processing SQL – Deep Dive](ecosystem/ksqldb.md)
- [Schema Registry & Schema Evolution – Deep Dive](ecosystem/schema_registry.md)
- [Kafka Architecture & Core Concepts – Deep Dive](fundamentals/architecture.md)
- [Kafka Consumers & Consumer Groups – Deep Dive](fundamentals/consumers.md)
- [Kafka Producers – Config & Guarantees – Deep Dive](fundamentals/producers.md)
- [📖 Kafka Glossary – Bảng thuật ngữ Kafka](glossary.md)
- [Kafka Replication & Fault Tolerance – Deep Dive](internals/replication.md)
- [Kafka Storage – Log, Retention & Compaction – Deep Dive](internals/storage.md)
- [Tổng Hợp Kiến Thức Apache Kafka – Thực Chiến](kafka_knowledge.md)
- [Vận hành Kafka Cluster nâng cao (Day-2 Operations) – Deep Dive](operations/cluster_operations.md)
- [Kafka Production Operations – Performance, Monitoring & Security – Deep Dive](operations/production.md)
- [Event-Driven Architecture & Data Modeling (Kafka-native) – Deep Dive](patterns/event_driven_architecture.md)
- [Kafka Connect & CDC – Deep Dive](streams/connect.md)
- [Kafka Streams – Deep Dive](streams/kafka_streams.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
