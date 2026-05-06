# Tổng Hợp Kiến Thức Apache Kafka – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## Tổng Quan

**Apache Kafka** là distributed event streaming platform – lưu trữ, publish, subscribe, và xử lý event streams ở quy mô lớn với throughput cao, latency thấp.

```
Producer → Kafka Cluster (Topics/Partitions) → Consumer
                    ↓
           Kafka Streams / Kafka Connect / ksqlDB
```

---

## Danh Sách Sub-Topics

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

---

## Learning Path

```
Cơ bản:   architecture → producers → consumers
Trung cấp: storage → replication → connect
Nâng cao:  kafka_streams → production
```

---

*Cập nhật lần cuối: 2026-05-06*
