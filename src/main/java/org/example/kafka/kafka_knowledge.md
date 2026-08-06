# Tổng Hợp Kiến Thức Apache Kafka – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu nhanh: [Kafka Glossary](glossary.md) · [Roadmap chi tiết](roadmap.md)

---

## Tổng Quan

**Apache Kafka** là **distributed event streaming platform** *(nền tảng luồng sự kiện phân tán)*. Kafka nhận event từ producer, lưu chúng trong topic/partition có thể đọc lại, rồi phân phối cho nhiều consumer hoặc hệ thống xử lý luồng độc lập.

```text
Producer → Kafka cluster (topic/partition) → Consumer group
                    │
                    ├─ Kafka Streams / ksqlDB: xử lý dữ liệu
                    └─ Kafka Connect: tích hợp hệ thống ngoài
```

> 💡 **Giải thích dễ hiểu:**
> Kafka giống một hệ thống băng chuyền có kho lưu lịch sử. Producer đặt kiện hàng lên từng làn *(partition)*, consumer group chia nhau nhận hàng, còn offset là số thứ tự giúp mỗi nhóm nhớ đã xử lý đến đâu.

Kafka mạnh ở throughput, khả năng replay và fan-out. Tuy nhiên, Kafka không tự giải quyết schema kém, key phân vùng sai, xử lý nghiệp vụ không idempotent hoặc quy trình vận hành thiếu monitoring.

---

## Danh Sách Sub-Topics

| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Architecture & Core Concepts | [architecture.md](fundamentals/architecture.md) | ✅ |
| 2 | Producers – Config & Guarantees | [producers.md](fundamentals/producers.md) | ✅ |
| 3 | Consumers & Consumer Groups | [consumers.md](fundamentals/consumers.md) | ✅ |
| 4 | Storage: Log, Retention & Compaction | [storage.md](internals/storage.md) | ✅ |
| 5 | Replication & Fault Tolerance | [replication.md](internals/replication.md) | ✅ |
| 6 | Kafka Streams | [kafka_streams.md](streams/kafka_streams.md) | ✅ |
| 7 | Kafka Connect & CDC | [connect.md](streams/connect.md) | ✅ |
| 8 | Performance, Monitoring & Security | [production.md](operations/production.md) | ✅ |
| 9 | Schema Registry & Schema Evolution | [schema_registry.md](ecosystem/schema_registry.md) | ✅ |
| 10 | ksqlDB & Stream Processing SQL | [ksqldb.md](ecosystem/ksqldb.md) | ✅ |
| 11 | Event-Driven Architecture & Data Modeling | [event_driven_architecture.md](patterns/event_driven_architecture.md) | ✅ |
| 12 | Cluster Operations Advanced (Day-2) | [cluster_operations.md](operations/cluster_operations.md) | ✅ |
| 13 | Messaging & Kafka Observability | [messaging_kafka_observability.md](../prometheus_grafana/observability/messaging_kafka_observability.md) | ✅ |

---

## Learning Path

### 1. Nền tảng

[Architecture](fundamentals/architecture.md) → [Producer](fundamentals/producers.md) → [Consumer](fundamentals/consumers.md)

Mục tiêu: hiểu topic, partition, offset, broker, replication và consumer group trước khi chỉnh cấu hình.

### 2. Độ bền và tích hợp

[Storage](internals/storage.md) → [Replication](internals/replication.md) → [Kafka Connect](streams/connect.md) → [Schema Registry](ecosystem/schema_registry.md)

Mục tiêu: giải thích được dữ liệu được lưu, nhân bản, di chuyển và tiến hóa schema như thế nào.

### 3. Xử lý luồng và thiết kế hệ thống

[Kafka Streams](streams/kafka_streams.md) → [ksqlDB](ecosystem/ksqldb.md) → [Event-Driven Architecture](patterns/event_driven_architecture.md)

Mục tiêu: thiết kế key/partition, state store, window, join, retry, Outbox, Saga và idempotent consumer đúng phạm vi.

### 4. Production và Day-2

[Production Operations](operations/production.md) → [Cluster Operations](operations/cluster_operations.md) → [Messaging & Kafka Observability](../prometheus_grafana/observability/messaging_kafka_observability.md)

Mục tiêu: biết monitoring, security, quota, reassignment, rolling upgrade, capacity planning và disaster recovery.

---

## Chọn bài theo vấn đề thực tế

| Khi gặp vấn đề | Đọc trước |
|----------------|-----------|
| Duplicate, mất thứ tự hoặc producer timeout | [Producer](fundamentals/producers.md), [Consumer](fundamentals/consumers.md) |
| Consumer lag tăng hoặc rebalance liên tục | [Consumer](fundamentals/consumers.md), [Production Operations](operations/production.md) |
| Disk đầy, retention/compaction khó hiểu | [Storage](internals/storage.md) |
| ISR giảm, partition offline hoặc broker lỗi | [Replication](internals/replication.md), [Cluster Operations](operations/cluster_operations.md) |
| Đồng bộ database với Kafka | [Kafka Connect & CDC](streams/connect.md) |
| Schema thay đổi làm consumer lỗi | [Schema Registry](ecosystem/schema_registry.md) |
| Aggregate, join hoặc xử lý theo thời gian | [Kafka Streams](streams/kafka_streams.md), [ksqlDB](ecosystem/ksqldb.md) |
| Thiết kế Outbox, Saga, retry/DLQ | [Event-Driven Architecture](patterns/event_driven_architecture.md) |
| Cần nối producer, broker, consumer lag với freshness và business outcome | [Messaging & Kafka Observability](../prometheus_grafana/observability/messaging_kafka_observability.md) |

---

*Cập nhật lần cuối: 2026-07-30*
