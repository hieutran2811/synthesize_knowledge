# Kafka Producers – Config & Guarantees – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka Producer là gì?

**Kafka Producer** là client gửi records đến Kafka brokers. Producer chịu trách nhiệm:
- Serialize key/value
- Chọn partition (partitioning strategy)
- Buffer, batch records trước khi gửi
- Retry khi lỗi
- Đảm bảo delivery guarantees (at-least-once, exactly-once)

```
Application → ProducerRecord → Serializer → Partitioner → RecordAccumulator (buffer)
                                                                    ↓
                                                              Sender Thread → Broker
```

---

## Components – Producer Internals

```
KafkaProducer (thread-safe):
  Serializer:        convert key/value to bytes
  Partitioner:       chọn partition (default: sticky/round-robin/hash)
  RecordAccumulator: in-memory buffer (deque of ProducerBatch per TopicPartition)
  Sender thread:     background thread drain buffer → NetworkClient → Broker
  Metadata:          cluster metadata (brokers, topics, partitions, leaders)

ProducerRecord:
  topic, partition (optional), timestamp (optional)
  key, value, headers
```

---

## How – Producer Configuration

```java
// Core producer config
Properties props = new Properties();
props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092,broker2:9092,broker3:9092");
props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);  // hoặc Avro

// Reliability
props.put(ProducerConfig.ACKS_CONFIG, "all");          // 0, 1, all (-1)
props.put(ProducerConfig.RETRIES_CONFIG, Integer.MAX_VALUE);
props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 120000);  // 2 min

// Idempotence (exactly-once per partition, trong 1 session)
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);     // auto-sets acks=all, retries=MAX_INT

// Performance
props.put(ProducerConfig.BATCH_SIZE_CONFIG, 65536);            // 64KB (default 16KB)
props.put(ProducerConfig.LINGER_MS_CONFIG, 5);                 // wait up to 5ms to fill batch
props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, 67108864);      // 64MB buffer (default 32MB)
props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4");      // none, gzip, snappy, lz4, zstd
props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5); // idempotent: max 5
```

### Send – Fire and Forget / Callback / Synchronous

```java
KafkaProducer<String, Order> producer = new KafkaProducer<>(props);

// 1. Fire-and-forget (no acknowledgment)
producer.send(new ProducerRecord<>("orders", order.getId(), order));

// 2. Async with callback (recommended)
producer.send(
    new ProducerRecord<>("orders", order.getId(), order),
    (RecordMetadata metadata, Exception exception) -> {
        if (exception != null) {
            log.error("Send failed for order {}", order.getId(), exception);
            // handle error: dead letter queue, retry logic, alert
        } else {
            log.info("Sent to {}-{} at offset {}",
                metadata.topic(), metadata.partition(), metadata.offset());
        }
    }
);

// 3. Synchronous (blocking – use for guaranteed ordering in critical path)
try {
    RecordMetadata metadata = producer.send(
        new ProducerRecord<>("orders", order.getId(), order)
    ).get(30, TimeUnit.SECONDS);
    log.info("Offset: {}", metadata.offset());
} catch (ExecutionException e) {
    if (e.getCause() instanceof RetriableException) {
        // retry
    } else {
        throw e;  // non-retriable: don't retry
    }
}

// Always close producer gracefully
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    producer.flush();   // send all buffered records
    producer.close();
}));
```

---

## How – Acks & Delivery Guarantees

```
acks=0: Fire and forget
  - No wait for broker acknowledgment
  - Highest throughput, data loss possible
  - Use: metrics, non-critical telemetry

acks=1: Leader only
  - Wait for leader to write to local log
  - Message lost if leader fails before replication
  - Balance: throughput vs reliability

acks=all (= -1): All ISR
  - Wait for all in-sync replicas to acknowledge
  - No data loss if min.insync.replicas met
  - Lowest throughput, highest reliability
  - Use: financial transactions, critical events

min.insync.replicas (broker/topic config):
  Combined with acks=all: guarantees min N replicas confirmed
  Example: RF=3, min.insync.replicas=2
    → Leader + 1 follower must confirm
    → Tolerate 1 broker failure without data loss
    → If < 2 ISR available → NotEnoughReplicasException
```

```properties
# server.properties (broker default)
default.replication.factor=3
min.insync.replicas=2

# Per-topic override
kafka-configs.sh --alter --entity-type topics --entity-name orders \
  --add-config min.insync.replicas=2
```

---

## How – Idempotent Producer

```
Problem: producer retry → duplicate messages (network timeout, leader failover)

Solution: Idempotent Producer (Kafka 0.11+)
  - Broker assigns PID (Producer ID) to each producer session
  - Each record has sequence number (per partition)
  - Broker deduplicates: rejects records with seq ≤ last committed seq
  - Guarantee: exactly-once per partition per producer session

Limitation:
  - Exactly-once within 1 producer instance (PID resets on restart)
  - Does NOT guarantee exactly-once across multiple producers
  - For cross-topic exactly-once → need Transactions
```

```java
// Enable idempotence (auto-configures acks=all, retries=MAX_INT, max.in.flight=5)
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);

// Verify: check producer metrics
producer.metrics().forEach((name, metric) -> {
    if (name.name().contains("record-error-rate") || name.name().contains("record-retry-rate")) {
        System.out.println(name + ": " + metric.metricValue());
    }
});
```

---

## How – Transactions (Exactly-Once Semantics)

```
Transactional Producer: atomic write across multiple partitions/topics
  - All records in transaction either all committed or all aborted
  - Consumers with isolation.level=read_committed skip aborted transactions
  - Use case: consume-process-produce (Kafka Streams, stream processing)

transactional.id: unique per producer instance (survives restarts)
  - Broker fences zombie producers (same transactional.id, old epoch)
```

```java
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, "order-processor-1");  // unique per instance

KafkaProducer<String, String> producer = new KafkaProducer<>(props);
producer.initTransactions();  // register with broker, get epoch

try {
    producer.beginTransaction();

    // Write to multiple topics atomically
    producer.send(new ProducerRecord<>("orders-processed", key, value));
    producer.send(new ProducerRecord<>("order-events", key, event));

    // Commit consumer offsets as part of transaction (consume-process-produce)
    Map<TopicPartition, OffsetAndMetadata> offsets = getConsumedOffsets();
    producer.sendOffsetsToTransaction(offsets, consumerGroupMetadata);

    producer.commitTransaction();

} catch (ProducerFencedException | OutOfOrderSequenceException e) {
    // Fatal: producer fenced by newer instance → close and restart
    producer.close();
} catch (KafkaException e) {
    // Transient: abort and retry
    producer.abortTransaction();
    throw e;
}
```

---

## How – Partitioning Strategies

```java
// Default Partitioner (Kafka 3.x): UniformStickyPartitioner
// - key != null → hash(key) % numPartitions (murmur2 hash)
// - key == null → sticky to one partition until batch full, then rotate
//   (reduces small batches, improves throughput vs old round-robin)

// Custom Partitioner: implement Partitioner interface
public class CustomerPartitioner implements Partitioner {
    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
        int numPartitions = partitions.size();

        if (keyBytes == null) {
            throw new InvalidRecordException("Orders must have a customer ID key");
        }

        // VIP customers → partition 0 (dedicated)
        if (((String) key).startsWith("VIP-")) {
            return 0;
        }
        // Others → partitions 1..N
        return Math.abs(Utils.murmur2(keyBytes)) % (numPartitions - 1) + 1;
    }

    @Override public void close() {}
    @Override public void configure(Map<String, ?> configs) {}
}

// Register
props.put(ProducerConfig.PARTITIONER_CLASS_CONFIG, CustomerPartitioner.class);
```

---

## How – Compression

```
Compression: applied at batch level (not per record)
  Producer compresses batch → sends to broker → broker stores compressed
  Consumer decompresses after receiving

Types:
  none:   no compression (default)
  gzip:   highest compression ratio, CPU intensive
  snappy: balance compression/speed (Google)
  lz4:    fastest decompression, good compression (recommended)
  zstd:   best ratio + speed (Kafka 2.1+, recommended for new setups)

Benchmark (approximate):
  Throughput: lz4 ≈ snappy >> zstd > gzip
  Ratio:      zstd > gzip > snappy > lz4
  CPU:        lz4 < snappy < zstd < gzip
```

```properties
# Producer config
compression.type=lz4

# Broker can also compress/recompromise:
compression.type=producer  # keep producer compression (default, recommended)
compression.type=lz4       # broker recompress regardless
```

---

## How – Batching & Throughput Tuning

```
RecordAccumulator: buffer records per TopicPartition in ProducerBatch

batch.size (default 16384 = 16KB):
  Max bytes per batch before sending
  Increase for higher throughput: 64KB-512KB for bulk

linger.ms (default 0):
  Wait time before sending incomplete batch
  0 = send immediately (low latency)
  5-100ms = wait to fill batch (higher throughput)

buffer.memory (default 33554432 = 32MB):
  Total memory for all buffered records
  If buffer full → block for max.block.ms → BufferExhaustedException

max.block.ms (default 60000):
  Time to block send() when buffer full or metadata unavailable

max.request.size (default 1048576 = 1MB):
  Max size of a single request (includes batch)
  Must match broker message.max.bytes
```

```
Throughput optimization checklist:
  ✅ compression.type=lz4 hoặc zstd
  ✅ batch.size=131072 (128KB) hoặc lớn hơn
  ✅ linger.ms=10-50
  ✅ buffer.memory=67108864 (64MB)
  ✅ acks=1 (nếu chấp nhận at-least-once với lower latency)
  ✅ max.in.flight.requests.per.connection=5 (với idempotence)
```

---

## Why – Producer Design Choices

```
Why batch before send?
  Network round trips are expensive
  Batching: amortize latency, improve throughput dramatically
  1 request với 1000 records >> 1000 requests mỗi 1 record

Why sticky partitioner (Kafka 3.x)?
  Old round-robin: mỗi record → different partition → nhỏ batch → nhiều requests
  Sticky: fill 1 partition batch trước → gửi 1 lần → ít requests hơn
  Benchmark: ~50% reduction in latency for unkeyed messages

Why idempotence?
  Retries (for network failures) cause duplicates without idempotence
  PID + sequence number → broker can detect and drop duplicates
  Cost: minimal (sequence tracking per producer per partition)
```

---

## Trade-offs

```
acks=all + retries:
  ✅ Highest durability (no data loss)
  ❌ Higher latency (wait for all ISR)
  ❌ Lower throughput
  → Use for financial data, critical events

acks=1:
  ✅ Balance latency vs durability
  ❌ Data loss if leader fails before replication
  → Use for logs, metrics (loss acceptable)

Idempotence vs Transactions:
  Idempotence: within 1 producer session, 1 partition → simple, fast
  Transactions: across partitions/topics → complex, overhead
  → Use transactions only when needed (consume-process-produce)

Large batches (high linger.ms, large batch.size):
  ✅ Higher throughput
  ❌ Higher latency (wait to fill batch)
  → Tune based on latency SLA

Compression:
  ✅ Less network bandwidth, less broker storage
  ❌ CPU overhead at producer and consumer
  → Almost always worth it; use lz4/zstd
```

---

## Real-world

```java
// Production-grade producer setup
public KafkaProducer<String, byte[]> buildProducer(KafkaConfig config) {
    Properties props = new Properties();
    // Connectivity
    props.put(BOOTSTRAP_SERVERS_CONFIG, config.getBootstrapServers());
    props.put(SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
    props.put(SASL_MECHANISM_CONFIG, "PLAIN");
    props.put(SASL_JAAS_CONFIG, config.getJaasConfig());

    // Serializers
    props.put(KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
    props.put(VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class);

    // Reliability
    props.put(ACKS_CONFIG, "all");
    props.put(ENABLE_IDEMPOTENCE_CONFIG, true);
    props.put(DELIVERY_TIMEOUT_MS_CONFIG, 120000);
    props.put(REQUEST_TIMEOUT_MS_CONFIG, 30000);

    // Performance
    props.put(BATCH_SIZE_CONFIG, 131072);       // 128KB
    props.put(LINGER_MS_CONFIG, 10);
    props.put(BUFFER_MEMORY_CONFIG, 67108864);  // 64MB
    props.put(COMPRESSION_TYPE_CONFIG, "lz4");
    props.put(MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);

    // Monitoring
    props.put(INTERCEPTOR_CLASSES_CONFIG, List.of(
        "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor"
    ));

    return new KafkaProducer<>(props);
}
```

```
Monitoring metrics (JMX):
  record-send-rate:         records/sec sent
  record-error-rate:        > 0 → delivery failures (alert!)
  record-retry-rate:        retries occurring (investigate)
  request-latency-avg:      avg broker response time
  batch-size-avg:           check if batching is working
  compression-rate-avg:     actual compression achieved
  buffer-available-bytes:   watch for buffer exhaustion
  produce-throttle-time-avg: broker throttling producer
```

---

## Ghi chú – Chủ đề tiếp theo
> `consumers.md`: Consumer groups, offset management, rebalancing protocols (eager/cooperative), commit strategies, exactly-once consumption, consumer configs, lag monitoring

---

*Cập nhật lần cuối: 2026-05-06*
