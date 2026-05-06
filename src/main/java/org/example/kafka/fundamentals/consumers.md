# Kafka Consumers & Consumer Groups – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka Consumer là gì?

**Kafka Consumer** là client đọc records từ Kafka topics. Consumer dùng **pull model** – chủ động poll broker, không bị broker push.

```
Kafka Consumer khác traditional MQ consumer:
  - Consumer tự quản lý offset (vị trí đọc)
  - Có thể seek đến bất kỳ offset nào
  - Có thể replay messages (không xóa sau khi đọc)
  - Consumer group = horizontal scaling + failover tự động
```

---

## Components – Consumer Group

```
Consumer Group: group of consumers sharing same group.id
  - Mỗi partition chỉ được assign cho 1 consumer trong group
  - 1 consumer có thể handle nhiều partitions
  - Nếu consumers > partitions: một số consumer idle
  - Different groups: mỗi group có offset riêng → fan-out pattern

Example (3 partitions, 3 consumers):
  Consumer-1 → Partition-0
  Consumer-2 → Partition-1
  Consumer-3 → Partition-2

Scale down (3 partitions, 2 consumers):
  Consumer-1 → Partition-0, Partition-1
  Consumer-2 → Partition-2

Scale up (3 partitions, 4 consumers):
  Consumer-1 → Partition-0
  Consumer-2 → Partition-1
  Consumer-3 → Partition-2
  Consumer-4 → IDLE (no partition assigned)

Ordering guarantee:
  - Within a partition: strict order
  - Across partitions: no global order
  - Same key → same partition → ordered processing
```

---

## How – Consumer Configuration

```java
Properties props = new Properties();
props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092,broker2:9092");
props.put(ConsumerConfig.GROUP_ID_CONFIG, "order-processor-group");
props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);

// Offset reset: what to do when no committed offset exists
props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");  // earliest | latest | none

// Commit
props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);  // manual commit (recommended)
// props.put(ConsumerConfig.AUTO_COMMIT_INTERVAL_MS_CONFIG, 5000);  // if auto commit

// Polling
props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 500);          // records per poll()
props.put(ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG, 300000);   // 5 min (time to process batch)
props.put(ConsumerConfig.FETCH_MIN_BYTES_CONFIG, 1);             // min bytes before returning
props.put(ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG, 500);         // max wait if < fetch.min.bytes
props.put(ConsumerConfig.FETCH_MAX_BYTES_CONFIG, 52428800);      // 50MB max per fetch

// Session & heartbeat (detect dead consumers)
props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 45000);      // no heartbeat = dead
props.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 3000);    // must be < session.timeout/3

KafkaConsumer<String, Order> consumer = new KafkaConsumer<>(props);
```

---

## How – Poll Loop

```java
consumer.subscribe(List.of("orders", "payments"));  // pattern: subscribe(Pattern.compile("order.*"))

// Manual partition assignment (no rebalancing)
// consumer.assign(List.of(new TopicPartition("orders", 0), new TopicPartition("orders", 1)));

try {
    while (running.get()) {
        ConsumerRecords<String, Order> records = consumer.poll(Duration.ofMillis(100));

        for (TopicPartition partition : records.partitions()) {
            List<ConsumerRecord<String, Order>> partitionRecords = records.records(partition);

            for (ConsumerRecord<String, Order> record : partitionRecords) {
                log.info("Received: topic={} partition={} offset={} key={} value={}",
                    record.topic(), record.partition(), record.offset(),
                    record.key(), record.value());

                processOrder(record.value());
            }

            // Commit per partition after processing all records in that partition
            long lastOffset = partitionRecords.get(partitionRecords.size() - 1).offset();
            consumer.commitSync(Map.of(
                partition, new OffsetAndMetadata(lastOffset + 1)  // next offset to read
            ));
        }
    }
} catch (WakeupException e) {
    // Expected: consumer.wakeup() called from shutdown hook
    if (running.get()) throw e;
} finally {
    consumer.commitSync();  // final commit
    consumer.close();
}

// Graceful shutdown
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    running.set(false);
    consumer.wakeup();  // interrupt poll()
}));
```

---

## How – Offset Management

```
Offset: position in partition (next record to read)
  committed offset: saved to __consumer_offsets topic
  current position: consumer's in-memory position

Commit strategies:
  1. Auto commit:       easy, at-least-once (may miss records if crash before commit)
  2. commitSync():      after-processing, blocks, at-least-once
  3. commitAsync():     non-blocking, may commit out-of-order on retry
  4. Hybrid:            commitAsync() in loop, commitSync() on shutdown/rebalance
```

```java
// Recommended: async in loop + sync on close/rebalance
consumer.subscribe(topics, new ConsumerRebalanceListener() {
    @Override
    public void onPartitionsRevoked(Collection<TopicPartition> partitions) {
        // Commit current offsets before rebalance (don't lose progress)
        consumer.commitSync(currentOffsets);
    }

    @Override
    public void onPartitionsAssigned(Collection<TopicPartition> partitions) {
        // Optional: seek to specific offset
        // partitions.forEach(tp -> consumer.seek(tp, getLastProcessedOffset(tp)));
    }
});

Map<TopicPartition, OffsetAndMetadata> currentOffsets = new HashMap<>();

while (running.get()) {
    ConsumerRecords<String, Order> records = consumer.poll(Duration.ofMillis(100));

    for (ConsumerRecord<String, Order> record : records) {
        processOrder(record.value());
        currentOffsets.put(
            new TopicPartition(record.topic(), record.partition()),
            new OffsetAndMetadata(record.offset() + 1, "metadata")
        );
    }

    consumer.commitAsync(currentOffsets, (offsets, exception) -> {
        if (exception != null) {
            log.error("Commit failed for {}", offsets, exception);
        }
    });
}

// Final sync commit
consumer.commitSync(currentOffsets);
```

```bash
# CLI: manage consumer group offsets
# List consumer groups
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list

# Describe group (show lag)
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group order-processor-group
# GROUP               TOPIC  PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# order-processor     orders 0          1000            1050            50

# Reset offsets
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group order-processor-group \
  --topic orders \
  --reset-offsets --to-earliest --execute    # --to-latest, --to-offset 500, --to-datetime 2024-01-01T00:00:00.000
```

---

## How – Rebalancing Protocols

### Eager Rebalancing (Stop-the-World)

```
Eager (default until Kafka 2.4):
  1. All consumers revoke ALL partitions (stop processing)
  2. Group coordinator assigns partitions fresh
  3. All consumers start with new assignment
  
  Problem: brief stop-the-world for entire group
           even if only 1 consumer joins/leaves
```

### Cooperative Rebalancing (Incremental)

```
Cooperative Sticky (Kafka 2.4+):
  1. Coordinator signals which partitions need to move
  2. Only affected consumers revoke their partitions
  3. 2nd rebalance: reassign revoked partitions
  4. Other consumers continue uninterrupted

  Benefit: no global stop-the-world
           most partitions continue processing
```

```java
// Enable cooperative rebalancing
props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
    CooperativeStickyAssignor.class.getName());  // or list of strategies

// Multiple strategies (migration path from eager to cooperative)
props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
    List.of(CooperativeStickyAssignor.class, RangeAssignor.class));
```

### Static Group Membership

```java
// Static membership: skip rebalance for brief restarts
// Assign stable member ID to consumer → broker waits session.timeout before reassigning
props.put(ConsumerConfig.GROUP_INSTANCE_ID_CONFIG, "consumer-pod-1");  # unique per instance
props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 60000);  # give 60s for restart

// Use case: stateful consumers (Kafka Streams, local state stores)
// Benefit: restart consumer without triggering rebalance
```

---

## How – Exactly-Once Consumption

```
Delivery semantics:
  at-most-once:   commit before process → may lose messages (process crash after commit)
  at-least-once:  commit after process  → may duplicate (commit fail after process)
  exactly-once:   requires transactions + idempotent consumer logic

Strategies:
  1. Idempotent processing: check if already processed (DB dedup key)
  2. Transactional consume-process-produce (Kafka Streams)
  3. Exactly-once Semantics (EOS) with transactions
```

```java
// Strategy 1: Idempotent processing with external DB
void processWithIdempotency(ConsumerRecord<String, Order> record) {
    String dedupeKey = record.topic() + "-" + record.partition() + "-" + record.offset();
    
    try (Connection conn = dataSource.getConnection()) {
        conn.setAutoCommit(false);
        
        // Check if already processed
        if (isAlreadyProcessed(conn, dedupeKey)) {
            conn.commit();
            return;
        }
        
        // Process + mark as processed atomically
        processOrder(conn, record.value());
        markAsProcessed(conn, dedupeKey);
        conn.commit();
    }
}

// Strategy 2: Kafka Streams (built-in EOS)
props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.EXACTLY_ONCE_V2);
```

---

## How – Seek & Replay

```java
// Seek to beginning (replay all)
consumer.subscribe(List.of("orders"));
consumer.poll(Duration.ofMillis(0));  // trigger assignment
consumer.seekToBeginning(consumer.assignment());

// Seek to end (skip old messages)
consumer.seekToEnd(consumer.assignment());

// Seek to specific offset
TopicPartition tp = new TopicPartition("orders", 0);
consumer.seek(tp, 1000L);

// Seek to timestamp
Map<TopicPartition, Long> timestamps = new HashMap<>();
consumer.assignment().forEach(tp -> timestamps.put(tp, Instant.now().minus(Duration.ofHours(1)).toEpochMilli()));
Map<TopicPartition, OffsetAndTimestamp> offsets = consumer.offsetsForTimes(timestamps);
offsets.forEach((tp, offsetAndTimestamp) -> {
    if (offsetAndTimestamp != null) {
        consumer.seek(tp, offsetAndTimestamp.offset());
    }
});
```

---

## Why – Pull vs Push Model

```
Kafka: Pull model
  Consumer controls when to fetch
  Consumer controls batch size (MAX_POLL_RECORDS)
  No backpressure needed (consumer just doesn't poll)
  Can process at own pace (fast consumer = low lag, slow consumer = lag builds)

RabbitMQ/ActiveMQ: Push model
  Broker pushes to consumer (prefetch count)
  Consumer must implement backpressure (prefetch limit)
  Broker must track per-consumer state

Why Kafka chose pull:
  ✅ Simple broker: no need to track per-consumer state
  ✅ Consumer controls throughput: no overwhelming slow consumers
  ✅ Efficient batching: consumer can request large batches
  ❌ Consumer must poll continuously (busy-wait if no data)
     → Solution: fetch.max.wait.ms (long polling)
```

---

## Trade-offs

```
Auto commit vs Manual commit:
  Auto:   simple, at-least-once (may reprocess after crash)
  Manual: control, at-least-once with intentional commit point
  → Production: always manual commit

max.poll.records:
  High:  better throughput per poll, but longer processing time
  Low:   faster heartbeat, less risk of exceeding max.poll.interval.ms
  → Tune with max.poll.interval.ms: ensure processing time < interval

Session timeout:
  Low (10-30s):  detect dead consumers fast, frequent false rebalances
  High (45-60s): tolerate GC pauses, slower failover
  → Default 45s usually fine; increase for GC-heavy workloads

Consumer lag:
  0 lag:        consumer is caught up (ideal)
  Growing lag:  consumer slower than producer (scale out consumers, optimize processing)
  
Consumer group size:
  > partitions: some consumers idle (wasted resources)
  < partitions: each consumer handles multiple partitions (OK, just fewer consumers)
  = partitions: maximum parallelism (ideal)
```

---

## Real-world

```java
// Production consumer wrapper with retry + DLQ
public class ResilientConsumer<K, V> {
    private final KafkaConsumer<K, V> consumer;
    private final KafkaProducer<K, V> dlqProducer;
    private final String dlqTopic;
    private final int maxRetries;

    public void run() {
        consumer.subscribe(topics, rebalanceListener);
        
        while (running.get()) {
            try {
                ConsumerRecords<K, V> records = consumer.poll(Duration.ofMillis(200));
                
                for (ConsumerRecord<K, V> record : records) {
                    processWithRetry(record);
                }
                consumer.commitAsync();
                
            } catch (WakeupException e) {
                if (!running.get()) break;
            } catch (KafkaException e) {
                log.error("Consumer error, restarting poll loop", e);
                // Don't commit; broker will re-deliver
            }
        }
        consumer.commitSync();
        consumer.close();
    }
    
    private void processWithRetry(ConsumerRecord<K, V> record) {
        int attempts = 0;
        while (attempts <= maxRetries) {
            try {
                processRecord(record);
                return;
            } catch (RetriableException e) {
                attempts++;
                if (attempts > maxRetries) {
                    sendToDLQ(record, e);
                }
                Uninterruptibles.sleepUninterruptibly(
                    (long) Math.pow(2, attempts) * 100, TimeUnit.MILLISECONDS);
            } catch (NonRetriableException e) {
                sendToDLQ(record, e);
                return;
            }
        }
    }
    
    private void sendToDLQ(ConsumerRecord<K, V> record, Exception cause) {
        Headers headers = new RecordHeaders()
            .add("original-topic", record.topic().getBytes())
            .add("original-partition", String.valueOf(record.partition()).getBytes())
            .add("original-offset", String.valueOf(record.offset()).getBytes())
            .add("error-message", cause.getMessage().getBytes());
        
        dlqProducer.send(new ProducerRecord<>(dlqTopic, null, record.key(), record.value(), headers));
        log.error("Sent to DLQ: {}-{}-{}", record.topic(), record.partition(), record.offset());
    }
}
```

```
Monitoring metrics:
  records-consumed-rate:     throughput
  fetch-latency-avg:         time to fetch from broker
  commit-latency-avg:        commit overhead
  Consumer lag (via JMX or Kafka metrics):
    kafka.consumer:type=consumer-fetch-manager-metrics,client-id=*,records-lag-max
  → Alert: lag > threshold (e.g., > 10k records and growing)
```

---

## Ghi chú – Chủ đề tiếp theo
> `storage.md`: Log segments, log compaction, retention policies (time/size/compaction), tiered storage, index files, consumer offset storage (__consumer_offsets)

---

*Cập nhật lần cuối: 2026-05-06*
