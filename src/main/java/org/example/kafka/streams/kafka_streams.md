# Kafka Streams – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka Streams là gì?

**Kafka Streams** là Java library cho stream processing trực tiếp trong Kafka – không cần cluster riêng (như Flink/Spark). Ứng dụng là standard Java app với KafkaStreams embedded.

```
Kafka Streams vs Other Stream Processors:
  Kafka Streams:   library (no separate cluster), easy ops, tightly coupled with Kafka
  Apache Flink:    separate cluster, very powerful, complex ops, lower latency
  Apache Spark:    micro-batch, high latency, good for batch+streaming
  ksqlDB:          SQL interface on top of Kafka Streams

Use cases:
  - Real-time transformations (filter, map, enrich)
  - Aggregations with time windows (order counts per minute)
  - Join streams/tables (enrich events with reference data)
  - Stateful processing (running totals, sessionization)
  - Event-driven microservices (consume-process-produce)
```

---

## Components – Core Abstractions

```
KStream:  unbounded stream of records (events)
  - Each record is independent
  - Immutable append-only log

KTable:   changelog stream (latest value per key)
  - Represents current state (like a database table)
  - Backed by state store (RocksDB)
  - Updated on each record with same key

GlobalKTable: KTable replicated on ALL instances
  - Available for foreign key lookups across all tasks
  - No partitioning → full data on every instance
  - Use for small reference data (products, users)
  - vs KTable: KTable is partitioned (each instance has subset)

Processor Topology:
  Source → Processor → Sink
  KStream/KTable operations build a DAG (topology)
  Topology compiled into tasks → parallelized across partitions
```

---

## How – Topology Builder (DSL)

```java
// Build topology
StreamsBuilder builder = new StreamsBuilder();

// Source: read from topic
KStream<String, Order> orders = builder.stream(
    "orders",
    Consumed.with(Serdes.String(), new OrderSerde())
        .withOffsetResetPolicy(Topology.AutoOffsetReset.EARLIEST)
);

// --- Stateless operations ---

// Filter: keep completed orders
KStream<String, Order> completedOrders = orders
    .filter((key, order) -> "COMPLETED".equals(order.getStatus()));

// Map: transform key/value
KStream<String, OrderEvent> events = completedOrders
    .map((key, order) -> KeyValue.pair(
        order.getCustomerId(),           // new key: route by customer
        OrderEvent.fromOrder(order)       // new value: transformed type
    ));

// FlatMap: 1 record → multiple records
KStream<String, LineItem> lineItems = orders
    .flatMap((key, order) ->
        order.getItems().stream()
            .map(item -> KeyValue.pair(item.getProductId(), item))
            .collect(Collectors.toList())
    );

// MapValues: transform value only (key unchanged)
KStream<String, String> orderSummaries = orders
    .mapValues(order -> order.getId() + ":" + order.getAmount());

// SelectKey: change key (triggers repartitioning!)
KStream<String, Order> byCustomer = orders
    .selectKey((key, order) -> order.getCustomerId());

// Branch: split stream by condition
Map<String, KStream<String, Order>> branches = orders
    .split(Named.as("branch-"))
    .branch((key, order) -> order.getAmount() > 1000000, Branched.as("high-value"))
    .branch((key, order) -> order.getAmount() > 100000, Branched.as("medium-value"))
    .defaultBranch(Branched.as("low-value"));

KStream<String, Order> highValue = branches.get("branch-high-value");

// Peek: debug without modifying
orders.peek((key, order) -> log.info("Processing order: {}", key));

// Sink: write to topic
events.to("order-events", Produced.with(Serdes.String(), new OrderEventSerde()));
```

---

## How – KTable & Aggregations

```java
// KTable: read as changelog (latest value per key)
KTable<String, Product> products = builder.table(
    "products",
    Consumed.with(Serdes.String(), new ProductSerde()),
    Materialized.as("products-store")  // named state store
);

// Aggregations: must use groupBy first
KGroupedStream<String, Order> groupedByCustomer = completedOrders
    .groupBy(
        (key, order) -> order.getCustomerId(),
        Grouped.with(Serdes.String(), new OrderSerde())
    );

// Count per customer
KTable<String, Long> orderCountByCustomer = groupedByCustomer.count(
    Materialized.<String, Long, KeyValueStore<Bytes, byte[]>>as("order-counts")
        .withKeySerde(Serdes.String())
        .withValueSerde(Serdes.Long())
);

// Aggregate: custom aggregation (running total revenue)
KTable<String, Double> revenueByCustomer = groupedByCustomer.aggregate(
    () -> 0.0,                              // initializer
    (customerId, order, currentRevenue) ->  // aggregator
        currentRevenue + order.getAmount(),
    Materialized.<String, Double, KeyValueStore<Bytes, byte[]>>as("customer-revenue")
        .withValueSerde(Serdes.Double())
);

// Reduce: combine same type
KTable<String, Order> latestOrderByCustomer = groupedByCustomer.reduce(
    (oldOrder, newOrder) ->
        newOrder.getTimestamp() > oldOrder.getTimestamp() ? newOrder : oldOrder
);
```

---

## How – Windowing

```java
// Time window: fixed-size tumbling/hopping/sliding windows
// Requires records to have timestamps (EventTimeExtractor or log append time)

// Tumbling window: non-overlapping, fixed size
KTable<Windowed<String>, Long> ordersPerMinute = groupedByCustomer
    .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(1)))
    .count(Materialized.as("orders-per-minute"));

// Hopping window: overlapping windows
KTable<Windowed<String>, Long> ordersPer5MinHopping = groupedByCustomer
    .windowedBy(TimeWindows
        .ofSizeAndGrace(Duration.ofMinutes(5), Duration.ofSeconds(30))
        .advanceBy(Duration.ofMinutes(1)))  // new window every 1 min
    .count();

// Sliding window: continuous window based on record timestamps
KTable<Windowed<String>, Long> ordersSlidingWindow = groupedByCustomer
    .windowedBy(SlidingWindows.ofTimeDifferenceWithNoGrace(Duration.ofMinutes(5)))
    .count();

// Session window: activity-based (group bursts of events)
KTable<Windowed<String>, Long> sessionizedOrders = groupedByCustomer
    .windowedBy(SessionWindows.ofInactivityGapWithNoGrace(Duration.ofMinutes(30)))
    .count();

// Access windowed results
ordersPerMinute.toStream()
    .map((windowedKey, count) -> {
        String customerId = windowedKey.key();
        long windowStart = windowedKey.window().start();
        long windowEnd = windowedKey.window().end();
        return KeyValue.pair(customerId, new WindowedCount(windowStart, windowEnd, count));
    })
    .to("windowed-order-counts");
```

---

## How – Joins

```java
// KStream-KStream join: join events within a time window
KStream<String, Payment> payments = builder.stream("payments");
KStream<String, Order> orders = builder.stream("orders");

KStream<String, OrderWithPayment> paidOrders = orders.join(
    payments,
    (order, payment) -> new OrderWithPayment(order, payment),
    JoinWindows.ofTimeDifferenceWithNoGrace(Duration.ofMinutes(5)),
    StreamJoined.with(Serdes.String(), new OrderSerde(), new PaymentSerde())
);

// KStream-KTable join: enrich stream with table lookup (no window needed)
KTable<String, Customer> customers = builder.table("customers");

KStream<String, EnrichedOrder> enrichedOrders = orders.join(
    customers,
    (order, customer) -> new EnrichedOrder(order, customer),
    Joined.with(Serdes.String(), new OrderSerde(), new CustomerSerde())
);

// Left join: keep orders even if no matching customer
KStream<String, EnrichedOrder> allOrders = orders.leftJoin(
    customers,
    (order, customer) -> customer != null
        ? new EnrichedOrder(order, customer)
        : new EnrichedOrder(order, null),
    Joined.with(Serdes.String(), new OrderSerde(), new CustomerSerde())
);

// KStream-GlobalKTable join: foreign key lookup (no repartitioning)
GlobalKTable<String, Product> productTable = builder.globalTable("products");

KStream<String, LineItem> enrichedItems = lineItems.join(
    productTable,
    (itemKey, lineItem) -> lineItem.getProductId(),  // key extractor (foreign key)
    (lineItem, product) -> new EnrichedLineItem(lineItem, product)
);
```

---

## How – State Stores

```java
// State stores: where KTable data lives
// Default: RocksDB (persistent, efficient, stored on disk + in-memory cache)
// Option: In-memory (fast, lost on restart → needs compacted topic for restore)

// Custom state store in processor API
builder.addStateStore(
    Stores.keyValueStoreBuilder(
        Stores.persistentKeyValueStore("my-store"),
        Serdes.String(),
        Serdes.Long()
    )
);

// Access state store from Processor
class OrderCountProcessor implements Processor<String, Order, String, Long> {
    private KeyValueStore<String, Long> countStore;

    @Override
    public void init(ProcessorContext<String, Long> context) {
        this.countStore = context.getStateStore("my-store");
    }

    @Override
    public void process(Record<String, Order> record) {
        String customerId = record.key();
        Long currentCount = countStore.get(customerId);
        long newCount = (currentCount == null ? 0 : currentCount) + 1;
        countStore.put(customerId, newCount);
        context().forward(record.withValue(newCount));
    }
}

// Interactive queries: expose state store as REST service
KafkaStreams streams = new KafkaStreams(topology, config);
streams.start();

// Query local state store
ReadOnlyKeyValueStore<String, Long> store =
    streams.store(StoreQueryParameters.fromNameAndType("order-counts", QueryableStoreTypes.keyValueStore()));
Long count = store.get("customer-123");

// In production: expose HTTP endpoint for inter-instance state queries
// Use metadata to route to correct instance
KeyQueryMetadata metadata = streams.queryMetadataForKey("order-counts", "customer-123", Serdes.String().serializer());
HostInfo hostInfo = metadata.activeHost();
// → redirect to hostInfo.host():hostInfo.port()
```

---

## How – Configuration & Startup

```java
Properties props = new Properties();
props.put(StreamsConfig.APPLICATION_ID_CONFIG, "order-processor");     # consumer group ID
props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092");
props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());

// Parallelism
props.put(StreamsConfig.NUM_STREAM_THREADS_CONFIG, 4);    # threads per instance
// Parallelism = threads * instances; max = num_partitions of input topic

// State store
props.put(StreamsConfig.STATE_DIR_CONFIG, "/var/kafka-streams");
props.put(StreamsConfig.STATESTORE_CACHE_MAX_BYTES_CONFIG, 10 * 1024 * 1024L);  # 10MB

// Reliability
props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.EXACTLY_ONCE_V2);
// EXACTLY_ONCE_V2: requires Kafka 2.5+, uses transactions, ~20% slower
// AT_LEAST_ONCE: default, faster, may reprocess on failure

// Commit interval (flush state stores + commit offsets)
props.put(StreamsConfig.COMMIT_INTERVAL_MS_CONFIG, 100);  # 100ms (default)

// Replication for internal topics (changelog, repartition)
props.put(StreamsConfig.REPLICATION_FACTOR_CONFIG, 3);

// Startup
KafkaStreams streams = new KafkaStreams(builder.build(), props);

streams.setUncaughtExceptionHandler(exception ->
    StreamThreadExceptionResponse.REPLACE_THREAD);  # restart thread on uncaught exception

streams.setStateListener((newState, oldState) ->
    log.info("Streams state: {} → {}", oldState, newState));

streams.start();
Runtime.getRuntime().addShutdownHook(new Thread(streams::close));
```

---

## Why – Kafka Streams Design Choices

```
Why no separate cluster?
  Library approach: embed in your Java app
  → No infrastructure to manage (vs Flink: JobManager, TaskManagers)
  → Scale by adding app instances (same app.id = same consumer group)
  → Deploy like any microservice (K8s, ECS)

Why RocksDB for state stores?
  RocksDB: embedded key-value store (LSM tree)
  ✅ High write throughput (LSM: sequential writes)
  ✅ Efficient range scans (sorted keys)
  ✅ Persistent (survives app restart, changelog topic for recovery)
  ✅ Large state (off-heap, not JVM heap)

Why changelog topics?
  State store backup: every state store has a corresponding changelog topic
  On restart: restore state from changelog (compact topic → latest per key)
  → Fast recovery without full reprocessing
  → Trade-off: replication lag → recovery time for large state stores
```

---

## Trade-offs

```
EXACTLY_ONCE_V2 vs AT_LEAST_ONCE:
  EOS_V2:   ~20-30% slower, uses transactions, idempotent writes
  ALOS:     default, faster, may duplicate on failure (handle in downstream)
  → Financial transactions: EOS_V2
  → Analytics, aggregations: ALOS (with idempotent downstream)

KTable vs GlobalKTable:
  KTable:       partitioned, each instance has subset, co-partitioned joins
  GlobalKTable: all data on all instances, foreign key joins
  → Small lookup tables (products, config): GlobalKTable
  → Large tables: KTable (partition to distribute)

Window grace period:
  No grace (ofSizeWithNoGrace): discard late records
  Grace period: allow late records, keep window open longer
  → Higher grace = more memory, more correct
  → Tune based on expected out-of-order latency

State store size:
  Large state: more RocksDB I/O, slower recovery
  → Tune STATESTORE_CACHE_MAX_BYTES_CONFIG (more cache = fewer RocksDB reads)
  → Consider: TTL on windowed stores to expire old state
```

---

## Real-world

```
Topology description (debugging):
  System.out.println(builder.build().describe());
  → Prints topology as text tree

Monitoring Kafka Streams:
  JMX metrics:
    kafka.streams:type=stream-metrics,client-id=*
      commit-latency-avg:       commit overhead
      process-rate:             records/sec processed
      process-latency-avg:      processing latency
      
    kafka.streams:type=stream-thread-metrics
      commit-total:             total commits
      poll-records-avg:         avg records per poll
      
    kafka.streams:type=stream-task-metrics
      dropped-records-total:    serialization errors, null keys in joins
      
  Key alerts:
    rebalancing state (REBALANCING): brief is ok, prolonged → issue
    ERROR state: topology failure → alert immediately
    process-rate dropping: slowdown → investigate
    commit-latency spike: state store performance issue
```

---

## Ghi chú – Chủ đề tiếp theo
> `connect.md`: Kafka Connect architecture, source/sink connectors, SMTs (Single Message Transforms), Debezium CDC, MirrorMaker2 cross-cluster replication, connector management API

---

*Cập nhật lần cuối: 2026-05-06*
