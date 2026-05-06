# Roadmap Tổng Hợp Kiến Thức RabbitMQ

## Cấu trúc thư mục
```
rabbitmq/
├── roadmap.md                       ← file này
├── rabbitmq_fundamentals.md        ← What/Why/How, AMQP, Exchanges, Queues, Bindings, CLI
├── rabbitmq_patterns.md            ← Messaging Patterns: Direct/Fanout/Topic/Headers, RPC, Dead Letter, Priority
├── rabbitmq_reliability.md         ← Durability, Publisher Confirms, Consumer Acks, QoS/Prefetch, Transactions
└── rabbitmq_production.md          ← Clustering, Quorum Queues, Federation/Shovel, Policies, Monitoring, Spring Boot
```

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | RabbitMQ Fundamentals – What/Why, AMQP 0-9-1 protocol, Broker architecture, Exchange types, Queue properties, Binding, Virtual Hosts, CLI/Management UI | rabbitmq_fundamentals.md | ✅ |
| 2 | Messaging Patterns – Work Queue, Pub/Sub (Fanout), Topic routing, Headers exchange, RPC pattern, Dead Letter Exchange, Priority Queue, Delayed messaging | rabbitmq_patterns.md | ✅ |
| 3 | Reliability & Guarantees – Message durability, Publisher Confirms, Consumer Acknowledgements, QoS/Prefetch, Transactions, Poison message handling, Idempotency | rabbitmq_reliability.md | ✅ |
| 4 | Production & Operations – Clustering (Erlang clusters), Quorum Queues (Raft), Classic Mirrored Queues, Federation & Shovel, Policies, Monitoring (Prometheus), Spring AMQP, Docker/K8s | rabbitmq_production.md | ✅ |

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
| Throughput | High (50k msg/s) | Very high (1M+ msg/s) | High |
| Routing | Rich (4 exchange types) | Topic only | N/A |
| Replay | No (by default) | Yes (always) | Yes (from ID) |
| Protocol | AMQP, MQTT, STOMP | Custom/TCP | RESP |
| Best for | Complex routing, RPC, task queues | High-throughput event log | Simple streams, Redis ecosystem |
