# Kafka Architecture & Core Concepts – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka là gì?

**Apache Kafka** là distributed **event streaming platform** với 3 khả năng chính:
1. **Publish/Subscribe**: producer gửi events, consumer nhận events
2. **Store**: lưu trữ event streams bền vững, có thể replay
3. **Process**: xử lý event streams real-time (Kafka Streams)

```
Kafka không phải message queue thông thường:
- Data không bị xóa khi consumer đọc (có retention)
- Consumer có thể đọc lại từ bất kỳ offset nào
- Horizontal scale natively (partition-based)
- Throughput: hàng triệu msg/s trên 1 cluster
```

---

## Components

### Broker

```
Kafka Broker: 1 JVM process = 1 broker
Cluster: nhiều brokers (thường 3, 5, hoặc 7)
KRaft mode (Kafka 3.3+): không cần ZooKeeper
ZooKeeper mode (legacy): metadata stored in ZooKeeper

Broker roles:
  Regular broker: lưu data, serve clients
  Controller broker (1 trong cluster): quản lý partition leadership
    - KRaft: active controller + quorum of controllers
    - ZK mode: elected controller
```

### Topic & Partition

```
Topic: logical channel (ví dụ: "orders", "payments", "user-events")
  - Chỉ là metadata; data nằm trong partitions
  - Retention: theo time (7 days default) hoặc size

Partition: đơn vị parallelism và scalability
  - 1 topic → N partitions
  - Mỗi partition là 1 ordered, immutable sequence of records
  - Mỗi record có offset (monotonically increasing integer, per partition)
  - Partitions distributed across brokers

                  Partition 0: [0][1][2][3][4]... → Broker 1
Topic: orders  →  Partition 1: [0][1][2][3][4]... → Broker 2
                  Partition 2: [0][1][2][3][4]... → Broker 3

Replication: mỗi partition có 1 Leader + N-1 Followers
  Leader: serve reads + writes
  Followers: replicate từ leader (ISR)
```

### Record (Message)

```
Record structure:
  Key:       optional bytes (dùng cho partitioning + compaction)
  Value:     bytes (payload)
  Timestamp: producer hoặc broker time
  Headers:   optional key-value metadata (tracing, routing)
  Partition: assigned partition
  Offset:    position trong partition

Key = null → round-robin partitioning
Key != null → hash(key) % numPartitions → same partition (ordering guarantee)
```

---

## How – Topic Operations

```bash
# Tạo topic
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic orders \
  --partitions 12 \
  --replication-factor 3 \
  --config retention.ms=604800000 \    # 7 days
  --config min.insync.replicas=2

# List topics
kafka-topics.sh --bootstrap-server localhost:9092 --list

# Describe topic
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic orders
# Topic: orders  PartitionCount: 12  ReplicationFactor: 3
# Topic: orders  Partition: 0  Leader: 1  Replicas: 1,2,3  Isr: 1,2,3

# Alter partitions (chỉ tăng, không giảm)
kafka-topics.sh --bootstrap-server localhost:9092 \
  --alter --topic orders --partitions 24

# Xóa topic
kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic orders

# Config topic
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders \
  --alter --add-config retention.ms=86400000  # 1 day

# Describe config
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders --describe
```

---

## How – KRaft Mode (Kafka 3.3+ – ZooKeeper-free)

```yaml
# server.properties (KRaft mode)
# Node roles: broker, controller, hoặc broker,controller (combined)
process.roles=broker,controller  # combined mode (small cluster)
# hoặc:
process.roles=broker    # dedicated broker node
process.roles=controller  # dedicated controller node

node.id=1
controller.quorum.voters=1@controller1:9093,2@controller2:9093,3@controller3:9093

# Listeners
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
advertised.listeners=PLAINTEXT://broker1.example.com:9092
controller.listener.names=CONTROLLER

# Log directories
log.dirs=/data/kafka

# Format storage (chạy 1 lần khi setup)
# kafka-storage.sh format --config server.properties --cluster-id <uuid>
```

```
KRaft benefits vs ZooKeeper:
✅ Simpler: không cần maintain ZooKeeper cluster riêng
✅ Faster metadata operations (fewer round trips)
✅ Supports larger clusters (millions of partitions)
✅ Faster controlled shutdown, faster leader election
✅ Single security model
```

---

## How – Partition Assignment & Balancing

```bash
# Xem partition assignment
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic orders

# Reassign partitions (load balancing)
# 1. Tạo reassignment plan
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --topics-to-move-json-file topics.json \
  --broker-list "1,2,3,4" \
  --generate

# 2. Execute reassignment
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment.json \
  --execute \
  --throttle 50000000  # 50MB/s throttle (không ảnh hưởng production)

# 3. Verify
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment.json \
  --verify
```

---

## Why – Kafka vs Alternatives

```
Kafka vs Traditional MQ (RabbitMQ, ActiveMQ):
  MQ:    message deleted after consume → no replay
  Kafka: message retained → replay, multiple consumers, rewind

Kafka vs Database:
  DB:    optimized for random access, not streaming
  Kafka: optimized for sequential write/read → much faster

Kafka vs Kinesis/Pulsar:
  Kinesis: AWS-managed, 7 day retention (enhanced: 1 year), less flexible
  Pulsar:  multi-tenancy, geo-replication built-in, tiered storage native
  Kafka:   largest ecosystem, battle-tested, more control
```

---

## Compare – Kafka vs RabbitMQ

| Feature | Kafka | RabbitMQ |
|---------|-------|---------|
| Model | Log-based, pull | Queue-based, push |
| Replay | Yes (retention) | No |
| Throughput | Very high (millions/s) | High (100k+/s) |
| Ordering | Per partition | Per queue |
| Consumer groups | Yes (parallel) | Competing consumers |
| Protocols | Custom binary | AMQP, MQTT, STOMP |
| Message routing | Topic + partition | Exchange + routing key |
| Backpressure | Consumer controls offset | Broker pushes |
| Use case | Event streaming, log | Task queue, RPC |
| Persistence | Always (log) | Configurable |

---

## Trade-offs

```
Nhiều partitions:
✅ Higher throughput (more parallelism)
✅ More consumers in group
❌ More file handles, more memory (leader election slower)
❌ Cannot reduce partitions
→ Rule: 1-3 partitions per broker per topic as starting point
   Scale up as needed

Replication factor:
RF=1: fast, no redundancy → data loss on broker failure
RF=3: standard, tolerate 1 broker failure
RF=5: tolerate 2 broker failures, overhead
→ Production: RF=3 minimum

Retention:
High: more replay capability, more disk
Low: less disk, cannot replay old data
→ Size-based + time-based hybrid retention
```

---

## Real-world

```
Partition sizing rule of thumb:
  Target throughput / throughput per partition = numPartitions
  Producer: ~10MB/s per partition (sequential write)
  Consumer: ~50MB/s per partition (sequential read)

  If target = 1GB/s producer → ~100 partitions
  If have 10 consumers → at least 10 partitions

Cluster sizing:
  1 broker: max ~1-2GB/s throughput (disk I/O bound)
  Production: 3+ brokers minimum (RF=3)
  Large: 10-50+ brokers

Monitoring (Critical metrics):
  UnderReplicatedPartitions: > 0 → problem!
  ActiveControllerCount: must be exactly 1
  OfflinePartitionsCount: > 0 → messages unavailable!
  RequestHandlerAvgIdlePercent: < 30% → broker overloaded
  consumer group lag: growing → consumer falling behind
```

---

## Ghi chú – Chủ đề tiếp theo
> `producers.md`: Producer configs, acks, idempotence, transactions, partitioning strategies, compression, batching

---

*Cập nhật lần cuối: 2026-05-06*
