---
title: "Roadmap Tổng Hợp Kiến Thức RabbitMQ"
topic: rabbitmq
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Roadmap Tổng Hợp Kiến Thức RabbitMQ

> 📖 Tra cứu nhanh thuật ngữ: [RabbitMQ Glossary](glossary.md)
>
> Tài liệu áp dụng cho RabbitMQ 4.x, hiện lấy 4.3 làm mốc; các điểm khác biệt quan trọng với version cũ được ghi rõ tại từng bài.

## Cấu trúc thư mục
```
rabbitmq/
├── roadmap.md                       ← file này
├── glossary.md                      ← thuật ngữ RabbitMQ tra cứu nhanh
├── rabbitmq_fundamentals.md        ← What/Why/How, AMQP, Exchanges, Queues, Bindings, CLI
├── rabbitmq_patterns.md            ← Messaging Patterns: Direct/Fanout/Topic/Headers, RPC, Dead Letter, Priority
├── rabbitmq_reliability.md         ← Durability, Publisher Confirms, Consumer Acks, QoS/Prefetch, Transactions
└── rabbitmq_production.md          ← Cluster 4.3, Khepri, Quorum, K8s, Monitoring, Security, DR, Upgrade, Runbook
```

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | RabbitMQ Fundamentals – mental model, AMQP 0-9-1, exchange/binding, queue types, connection/channel, ack/prefetch, vhost và CLI | [rabbitmq_fundamentals.md](rabbitmq_fundamentals.md) | ✅ |
| 2 | Messaging Patterns – Work Queue/SAC, Pub/Sub, Topic routing, delayed retry 4.3, DLX/DLQ, Priority, Hash Exchange, RPC, Alternate/E2E Exchange | [rabbitmq_patterns.md](rabbitmq_patterns.md) | ✅ |
| 3 | Reliability & Guarantees – delivery semantics, durability/quorum, async confirms, mandatory returns, Outbox/Inbox, acknowledgements, timeout, flow control và ordering | [rabbitmq_reliability.md](rabbitmq_reliability.md) | ✅ |
| 4 | Production & Operations – cluster/Khepri, quorum membership, policy, Kubernetes Operator, monitoring, capacity, security, DR, upgrade, Spring AMQP và runbook | [rabbitmq_production.md](rabbitmq_production.md) | ✅ |

---

## Trạng thái learning path

Learning path RabbitMQ cốt lõi đã hoàn thành: từ mental model và routing, đến reliability, rồi production operations. Các hướng mở rộng tiếp theo nên được tách thành chuyên đề riêng khi có nhu cầu thực tế:

- RabbitMQ Streams và Super Streams chuyên sâu;
- benchmark/capacity lab bằng PerfTest;
- observability lab với Prometheus, Grafana và alert rules;
- disaster-recovery game day;
- migration playbook từ RabbitMQ 3.x lên 4.x.

---

## Chú thích trạng thái
- ✅ Hoàn thành
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Quick Reference: Exchange Types

| Exchange Type | Routing Logic | Use Case |
|--------------|---------------|---------|
| **Direct** | Exact routing key match | Task queues, point-to-point |
| **Fanout** | Broadcast to ALL bound queues | Pub/Sub, event broadcasting |
| **Topic** | Pattern match (*, #) | Category routing, microservices events |
| **Headers** | Match on message headers (x-match: all/any) | Complex filtering without routing key |
| **Default** (nameless) | Route to queue with name = routing key | Simple direct messaging |

## Quick Reference: RabbitMQ vs Kafka vs Redis Streams

| Feature | RabbitMQ | Kafka | Redis Streams |
|---------|---------|-------|---------------|
| Model | Push-based | Pull-based | Pull-based |
| Message retention | Until consumed/TTL | Time-based (log) | Size/time-based |
| Ordering | Per queue | Per partition | Per stream |
| Throughput | Phụ thuộc queue type, confirms, payload và topology | Phụ thuộc partition, replication, batching và payload | Phụ thuộc persistence, consumer và payload |
| Routing | Rich (4 exchange types) | Topic only | N/A |
| Replay | No (by default) | Yes (always) | Yes (from ID) |
| Protocol | AMQP, MQTT, STOMP | Custom/TCP | RESP |
| Best for | Complex routing, RPC, task queues | High-throughput event log | Simple streams, Redis ecosystem |

> Không dùng các con số throughput chung để chọn công nghệ. Hãy benchmark bằng payload, durability, replication và failure mode giống production.

*Cập nhật lần cuối: 2026-07-29*

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [RabbitMQ Glossary](glossary.md)
- [RabbitMQ Fundamentals](rabbitmq_fundamentals.md)
- [RabbitMQ Messaging Patterns](rabbitmq_patterns.md)
- [RabbitMQ Production & Operations](rabbitmq_production.md)
- [RabbitMQ Reliability & Guarantees](rabbitmq_reliability.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
