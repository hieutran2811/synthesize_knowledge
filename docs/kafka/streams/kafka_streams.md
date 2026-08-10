---
title: "Kafka Streams – Deep Dive"
topic: kafka
level: mixed
review_status: needs_review
content_updated: 2026-07-27
last_verified: null
version_scope: "unspecified"
source_count: 4
---
# Kafka Streams – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)
>
> Phạm vi đối chiếu chính: Apache Kafka Streams 4.3. Những cluster/client cũ hơn cần kiểm tra lại API, config và rebalance protocol.

---

## What – Kafka Streams là gì?

**Kafka Streams** là Java library cho **stream processing** *(xử lý luồng sự kiện)* trực tiếp trong Kafka – không cần cluster xử lý riêng như Flink/Spark. Ứng dụng là standard Java app với `KafkaStreams` embedded *(nhúng trong tiến trình ứng dụng)*.

```
Kafka Streams vs Other Stream Processors:
  Kafka Streams:   library (no separate cluster), easy ops, tightly coupled with Kafka
  Apache Flink:    thường cần cluster riêng, nhiều khả năng, vận hành phức tạp
  Apache Spark:    hệ sinh thái batch + streaming; latency phụ thuộc engine/configuration
  ksqlDB:          SQL interface on top of Kafka Streams

Use cases:
  - Real-time transformations (filter, map, enrich)
  - Aggregations with time windows (order counts per minute)
  - Join streams/tables (enrich events with reference data)
  - Stateful processing (running totals, sessionization)
  - Event-driven microservices (consume-process-produce)
```

Kafka Streams phù hợp khi dữ liệu đã ở Kafka và topology cần scale bằng group coordination tích hợp với broker. Flink/Spark có thể phù hợp hơn khi cần nhiều nguồn ngoài Kafka, batch lớn hoặc runtime quản lý tập trung. Không nên kết luận công cụ nào luôn có latency thấp/cao hơn; phải benchmark theo workload, state và topology thực tế.

> 💡 **Giải thích dễ hiểu:**
> Kafka Streams giống thư viện bếp đặt ngay trong từng cửa hàng; Flink/Spark giống thuê một bếp trung tâm riêng. Bếp tại cửa hàng giảm hạ tầng phải vận hành, còn bếp trung tâm có thể phục vụ nhiều loại nguyên liệu và quy trình hơn.

---

## Components – Core Abstractions

```
KStream:  unbounded stream *(luồng không có điểm kết thúc)* của records/events
  - Each record is independent
  - Immutable append-only log

KTable:   changelog stream *(luồng thay đổi)*, giữ latest value per key
  - Represents current state (like a database table)
  - Thường materialize vào state store (RocksDB hoặc store provider khác)
  - Updated on each record with same key

GlobalKTable: KTable replicated on ALL instances
  - Available for foreign key lookups across all tasks
  - Không chia theo partition → full data trên every instance
  - Use for small reference data (products, users)
  - vs KTable: KTable is partitioned (each instance has subset)

Processor Topology *(đồ thị xử lý)*:
  Source → Processor → Sink
  KStream/KTable operations build a DAG (topology)
  Topology compiled into **tasks** *(đơn vị xử lý gắn với partition)* → parallelized across partitions
```

Task không đồng nghĩa một thread hoặc một record: một task có thể sở hữu một hoặc nhiều input partition; Kafka Streams phân task active/standby lên các instance và stream thread. Tổng parallelism hữu ích bị giới hạn bởi số partition của input/source, không chỉ bởi số CPU.

> 💡 **Giải thích dễ hiểu:**
> Topology là sơ đồ dây chuyền, task là một ca làm việc được giao cho quầy cụ thể. Thêm người nhưng không thêm quầy (partition) không tạo thêm luồng hàng; mỗi người vẫn phải xử lý phần quầy mình được giao.

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

// SelectKey: change key; repartition chỉ được tạo khi downstream cần grouping/join theo key mới
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

`selectKey()` chỉ đổi key trong record và đánh dấu stream cần xem xét repartition. Khi một operation stateful *(có trạng thái)* như `groupByKey()`, `groupBy()` hoặc một số join cần dữ liệu co-partitioned, Kafka Streams mới chèn repartition topic (hoặc bạn gọi `.repartition()` tường minh). Repartition tạo network I/O và topic nội bộ, nên tránh đổi key lặp lại không cần thiết.

**DSL** *(API khai báo cấp cao)* là điểm bắt đầu phù hợp cho filter/map/join/aggregate thông thường. **Processor API** *(API cấp thấp)* cho phép tự nối processor, state store và punctuation khi DSL không biểu diễn đủ logic; đổi lại cần tự chịu trách nhiệm nhiều hơn về topology và lifecycle.

> 💡 **Giải thích dễ hiểu:**
> Đổi nhãn kiện hàng chưa cần chuyển kho ngay. Chỉ khi bước sau yêu cầu các kiện cùng khách nằm chung một kho, Kafka mới gom và chuyển chúng qua repartition topic—giống phân loại lại hàng trước khi đưa vào quầy tính tổng.

### SerDes & Schema

**Serde** *(Serializer + Deserializer)* phải nhất quán với kiểu key/value ở source, repartition topic, state store và sink. Default SerDe chỉ là fallback; boundary quan trọng nên khai báo `Consumed.with`, `Grouped.with`, `Joined.with` hoặc `Produced.with` rõ ràng.

Schema Registry/Avro/Protobuf/JSON Schema giúp quản lý evolution, nhưng compatibility policy không tự ngăn code phá invariant. Cần kiểm tra null/tombstone, version field, schema migration và lỗi deserialize; một record lỗi có thể làm task dừng tùy `default.deserialization.exception.handler`.

> 💡 **Giải thích dễ hiểu:**
> SerDe là bộ phận đóng và mở kiện hàng. Hai đầu dây chuyền phải dùng cùng nhãn và quy cách; đổi schema mà không có quy tắc tương thích giống đổi kích thước thùng giữa lúc xe đang chạy.

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

`KTable` phát ra cả **update** và có thể phát tombstone *(value `null` để xóa key)*. Khi materialize aggregation, state store giữ trạng thái local; nếu downstream cần mọi event thay vì trạng thái mới nhất, chuyển `KTable` qua `toStream()` và thiết kế output phù hợp.

---

## How – Windowing

```java
// Time window: fixed-size tumbling/hopping/sliding windows
// Timestamp đến từ record hoặc custom TimestampExtractor.

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

Kafka Streams dùng record timestamp để tiến **stream-time** *(thời gian suy ra từ dữ liệu đang xử lý)*. Stream-time tiến theo timestamp lớn nhất task đã thấy và không lùi lại. Với window có grace, record đến muộn vẫn được nhận khi `stream_time < window_end + grace`; sau mốc đó record bị coi là late và bỏ qua. `retention` của window store phải đủ chứa toàn bộ vòng đời window (`window size + grace`, cùng phần đệm cần thiết), không chỉ thời lượng window.

Với task có nhiều input partition, `max.task.idle.ms` cho phép chờ partition tạm chưa có record để giảm out-of-order khi join/merge. Chờ lâu hơn có thể cải thiện time ordering nhưng tăng latency; nó không sửa timestamp sai từ producer.

> 💡 **Giải thích dễ hiểu:**
> Window là một ca tính tiền kéo dài một giờ; grace là khoảng thời gian chờ hóa đơn đến trễ. Đóng sổ quá sớm thì đúng giờ nhưng thiếu hóa đơn, chờ quá lâu thì tốn chỗ lưu và kết quả xuất hiện muộn hơn.

### Phát kết quả cuối bằng `suppress()`

Windowed aggregation mặc định có thể phát nhiều update cho cùng key/window. Nếu downstream chỉ muốn kết quả sau khi window đã đóng:

```java
KTable<Windowed<String>, Long> finalOrdersPerMinute =
    ordersPerMinute.suppress(
        Suppressed.untilWindowCloses(
            Suppressed.BufferConfig
                .maxBytes(256L * 1024 * 1024)
                .shutDownWhenFull()
        ).withName("final-orders-per-minute")
    );

finalOrdersPerMinute.toStream()
    .to("final-windowed-order-counts");
```

“Final” ở đây nghĩa stream-time đã vượt `window end + grace`; record tới sau grace vẫn bị bỏ. `suppress()` giữ buffer trong memory, không chuyển sang RocksDB. Bounded strict buffer chọn tính đúng bằng cách shutdown khi đầy thay vì âm thầm phát sớm; vì vậy phải sizing, giữ changelog mặc định hoặc cấu hình logging có chủ đích, monitor memory và kiểm thử restore. `unbounded()` dễ dùng nhưng có nguy cơ OOM nếu stream-time không tiến hoặc cardinality/window quá lớn.

> 💡 **Giải thích dễ hiểu:**
> Aggregation mặc định giống bảng điểm cập nhật sau mỗi lượt. `suppress()` che bảng cho tới khi hết giờ khiếu nại rồi mới công bố một kết quả cuối; nếu phòng chờ kết quả đầy, hệ thống phải dừng thay vì lén công bố bản chưa chốt.

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

KStream-KStream join cần hai phía cùng key và cửa sổ thời gian; Kafka Streams thường tạo state store để giữ dữ liệu trong khoảng đó. KStream-KTable join tra trạng thái table theo stream key và không cần window, nhưng stream/table phải **co-partitioned** *(cùng quy tắc partition)*. Nếu key khác nhau, hãy đổi key/repartition trước join. GlobalKTable bỏ yêu cầu repartition cho stream vì toàn bộ table được nạp trên mỗi instance, nhưng chi phí lưu trữ và restore tăng theo kích thước table.

> 💡 **Giải thích dễ hiểu:**
> Join hai stream giống ghép hai đoàn tàu theo cùng mã vé và trong khoảng giờ cho phép. KTable là sổ tra cứu tại quầy; GlobalKTable là photo toàn bộ sổ ở mọi quầy—tra nhanh hơn nhưng mỗi quầy phải giữ cả cuốn.

---

## How – State Stores

```java
// State stores: nơi giữ trạng thái cục bộ của KTable/processor
// Persistent store thường dùng RocksDB (disk + native memory/cache)
// Option: in-memory (nhanh nhưng mất khi restart; cần changelog để restore)

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
    private ProcessorContext<String, Long> context;

    @Override
    public void init(ProcessorContext<String, Long> context) {
        this.context = context;
        this.countStore = context.getStateStore("my-store");
    }

    @Override
    public void process(Record<String, Order> record) {
        String customerId = record.key();
        Long currentCount = countStore.get(customerId);
        long newCount = (currentCount == null ? 0 : currentCount) + 1;
        countStore.put(customerId, newCount);
        context.forward(record.withValue(newCount));
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

State store là local view của task, không phải database phân tán tự động. Changelog topic ghi các thay đổi để restore khi task chuyển instance; **standby replica** *(bản sao dự phòng)* có thể rút ngắn thời gian phục hồi nhưng tốn disk, network và broker throughput. Nếu tắt logging của store, state không còn fault-tolerant và không có standby cho store đó.

Interactive Queries chỉ đọc state local mà instance đang sở hữu; `activeHost()` có thể chưa sẵn sàng trong lúc rebalance/restore, và dữ liệu standby (nếu cho phép query) có thể stale. Production cần `application.server` duy nhất cho từng instance, metadata routing, health check và xử lý `NOT_AVAILABLE`/host không tồn tại.

> 💡 **Giải thích dễ hiểu:**
> State store là sổ tay của từng quầy, changelog là bản photocopy gửi về kho trung tâm, còn standby là sổ dự phòng ở quầy kế bên. Interactive Query phải tìm đúng quầy đang giữ khách hàng; hỏi nhầm quầy sẽ trả “chưa có” hoặc dữ liệu cũ.

---

## How – Configuration & Startup

```java
Properties props = new Properties();
props.put(StreamsConfig.APPLICATION_ID_CONFIG, "order-processor"); // group identity + prefix internal topics
props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092");
props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass());

// Parallelism
props.put(StreamsConfig.NUM_STREAM_THREADS_CONFIG, 4);    // threads per instance
// Active tasks bị giới hạn bởi số partition của source; không đơn giản là threads * instances

// State store
props.put(StreamsConfig.STATE_DIR_CONFIG, "/var/kafka-streams"); // mỗi instance trên cùng host cần thư mục riêng
props.put(StreamsConfig.STATESTORE_CACHE_MAX_BYTES_CONFIG, 10 * 1024 * 1024L);  // 10MB; cache không phải nguồn dữ liệu bền vững
props.put(StreamsConfig.NUM_STANDBY_REPLICAS_CONFIG, 1); // chỉ áp dụng classic protocol
props.put(StreamsConfig.APPLICATION_SERVER_CONFIG, "streams-1:8080"); // unique host:port cho Interactive Queries
props.put(StreamsConfig.MAX_TASK_IDLE_MS_CONFIG, 1000L); // đánh đổi 1s latency để chờ input khác

// Bật sau khi đã đặt Named/Materialized/Repartitioned cho MỌI internal resource:
// props.put("ensure.explicit.internal.resource.naming", true);

// Reliability
props.put(StreamsConfig.PROCESSING_GUARANTEE_CONFIG, StreamsConfig.EXACTLY_ONCE_V2);
// EXACTLY_ONCE_V2: requires broker 2.5+, uses Kafka transactions; overhead tùy workload
// AT_LEAST_ONCE: default, faster, may reprocess on failure

// Commit interval (flush state stores + commit offsets/transaction)
props.put(StreamsConfig.COMMIT_INTERVAL_MS_CONFIG, 100);  // 100ms explicit; EOS default 100, ALOS default thường 30s

// Replication for internal topics (changelog, repartition)
props.put(StreamsConfig.REPLICATION_FACTOR_CONFIG, 3);

// Startup
KafkaStreams streams = new KafkaStreams(builder.build(), props);

streams.setUncaughtExceptionHandler(exception ->
    StreamThreadExceptionResponse.REPLACE_THREAD);  // chỉ replace lỗi có thể retry; phân loại fatal trước

streams.setStateListener((newState, oldState) ->
    log.info("Streams state: {} → {}", oldState, newState));

streams.start();
Runtime.getRuntime().addShutdownHook(
    new Thread(() -> streams.close(Duration.ofSeconds(30)))
);
```

`REPLACE_THREAD` chỉ phù hợp lỗi có thể khôi phục và không làm mất invariant/state; deserialization schema lỗi, topology bug hoặc transaction/configuration fatal nên chuyển sang `SHUTDOWN_CLIENT`/`SHUTDOWN_APPLICATION` và alert. Graceful shutdown cần timeout đủ để commit transaction, flush state và hoàn tất rebalance handoff.

Kafka Streams 4.3 có nhiều error boundary:

| Boundary | Cấu hình/hook | Câu hỏi cần quyết định |
|---|---|---|
| Đọc bytes thành object | `deserialization.exception.handler` | Fail hay bỏ record không giải mã được |
| Code processor/DSL ném lỗi | `processing.exception.handler` | Fail hay tiếp tục với record lỗi |
| Ghi output/internal topic lỗi | `production.exception.handler` | Retry/fail hay bỏ output |
| Lỗi thoát khỏi stream thread | `StreamsUncaughtExceptionHandler` | Replace thread, shutdown client hay shutdown toàn application |

Handler kiểu “log and continue” có thể biến lỗi thành data loss im lặng. Chỉ skip khi có metric, DLT/audit phù hợp, ownership và quy trình replay; global KTable/store còn có giới hạn xử lý exception khác regular task theo version.

`ensure.explicit.internal.resource.naming=true` làm ứng dụng từ chối start nếu topology còn state store/repartition/changelog resource dùng tên tự sinh. Đây là fail-fast hữu ích: thêm một operator ở giữa topology có thể đổi tên auto-generated và khiến rolling upgrade hiểu nhầm resource cũ/mới.

### Streams Rebalance Protocol (Kafka 4.2+)

Kafka 4.2 bổ sung protocol dành riêng cho Streams, nơi broker liên tục tính task assignment. Feature này được bật mặc định trên cluster mới từ 4.2, nhưng **client vẫn mặc định `classic`** cho tới khi cấu hình:

```java
props.put("group.protocol", "streams");
```

| Tiêu chí | `classic` | `streams` |
|---|---|---|
| Nơi tính task assignment | Client leader của group | Group coordinator trên broker |
| Group type/tooling | Consumer group | Streams group, `kafka-streams-groups.sh` |
| Rebalance | Có global synchronization point | Broker-driven, incremental reconciliation |
| Standby/session/heartbeat config | Chủ yếu trên client | Group-level config trên broker |
| Migration | Protocol cũ hiện hành | Chỉ offline migration trong Kafka 4.3 |

Cả broker và client phải từ Kafka 4.2 trở lên. Với cluster đã nâng cấp, kiểm tra/bật feature:

```bash
kafka-features.sh --bootstrap-server localhost:9092 \
  upgrade --feature streams.version=1

# Client đã group.protocol=streams: đặt config theo application.id ở cấp group.
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --entity-type groups --entity-name order-processor \
  --add-config streams.num.standby.replicas=1

kafka-streams-groups.sh --bootstrap-server localhost:9092 \
  --describe --group order-processor
```

Khi dùng `streams`, các client config như `num.standby.replicas`, `session.timeout.ms`, `heartbeat.interval.ms`, `task.assignor.class` và một số warmup/rack-aware option bị bỏ qua; dùng group-level/broker config tương ứng. Không copy nguyên tuning của classic protocol rồi giả định đã có hiệu lực.

Migration hiện là **offline**: dừng toàn bộ instance, chờ group empty/explicit leave, đổi `group.protocol`, rồi khởi động lại. Committed offsets và internal topics vẫn còn, còn group assignment metadata được dựng lại. Dùng maintenance window và xác minh state restore/readiness trước khi mở traffic.

Với protocol mới, theo dõi broker metric `streams-group-count` theo state và `streams-group-rebalance-rate/count`; trạng thái `NOT_READY`/`RECONCILING` kéo dài cần được điều tra cùng restore lag và broker coordinator health.

> 💡 **Giải thích dễ hiểu:**
> Classic protocol giống các chi nhánh tự họp để chia ca; Streams protocol giống phòng điều phối trung tâm liên tục cập nhật lịch. Đổi cơ chế khi mọi người vẫn đang làm sẽ tạo hai cách chia ca cùng lúc, nên Kafka 4.3 yêu cầu đóng ca rồi mới chuyển.

### Topology Test & Deployment

```java
// Unit/integration test không cần broker thật
try (TopologyTestDriver driver = new TopologyTestDriver(topology, props)) {
    TestInputTopic<String, Order> input = driver.createInputTopic(
        "orders", new StringSerializer(), new OrderSerializer());
    TestOutputTopic<String, OrderEvent> output = driver.createOutputTopic(
        "order-events", new StringDeserializer(), new OrderEventDeserializer());

    input.pipeInput("order-1", order, Instant.parse("2026-07-22T00:00:00Z"));
    assertThat(output.readKeyValue()).isEqualTo(/* expected event */);
}
```

Topology test nên kiểm tra key/partition, repartition, tombstone, late event/grace, SerDe lỗi và commit/output mong đợi. Khi deploy, mọi instance của cùng application dùng cùng `application.id` để chia task; `state.dir` phải riêng trên cùng host, `application.server` phải unique nếu dùng Interactive Queries. Rolling upgrade cần kiểm tra compatibility của serialized state/changelog và protocol; rebalance/restore có thể làm instance chưa `RUNNING` ngay cả khi process đã start.

> 💡 **Giải thích dễ hiểu:**
> `TopologyTestDriver` giống mô hình thu nhỏ của dây chuyền: đưa vài kiện mẫu vào rồi kiểm tra từng đầu ra mà không cần dựng cả nhà máy Kafka. Khi triển khai thật, application ID là tên đội, còn state directory là tủ riêng của từng nhân viên—trùng tủ sẽ làm họ giẫm lên dữ liệu của nhau.

---

## Why – Kafka Streams Design Choices

```
Why no separate cluster?
  Library approach: embed in your Java app
  → No infrastructure to manage (vs Flink: JobManager, TaskManagers)
  → Scale by adding app instances (same app.id = same consumer group)
  → Deploy like any microservice (K8s, ECS)

Why RocksDB for state stores?
  RocksDB: embedded key-value store (LSM tree), mặc định phổ biến cho persistent store
  ✅ High write throughput (LSM: sequential writes)
  ✅ Efficient range scans (sorted keys)
  ✅ Persistent (survives app restart, changelog topic for recovery)
  ✅ State lớn hơn JVM heap có thể nằm trên local disk/native memory

Why changelog topics?
  State store backup: state store được logging thường có changelog topic tương ứng
  On restart: restore state from changelog (compact topic → latest per key với store phù hợp)
  → Fast recovery without full reprocessing
  → Trade-off: replication lag → recovery time for large state stores
```

Changelog là cơ chế phục hồi, không phải backup thay thế việc quản lý retention/replication. Window/session store còn cần giữ dữ liệu theo vòng đời window và grace; compacted topic không biến mọi state thành “chỉ còn một record mỗi key” theo cách đơn giản như KTable.

> 💡 **Giải thích dễ hiểu:**
> RocksDB là sổ cái đặt tại quầy để tra nhanh; changelog là nhật ký gửi về kho. Khi quầy hỏng, Kafka dựng lại sổ từ nhật ký. Nhật ký phải đủ lâu và đủ bản sao—nếu cắt mất phần cần cho window, khôi phục không thể tái tạo đúng lịch sử.

---

## Trade-offs

```
EXACTLY_ONCE_V2 vs AT_LEAST_ONCE:
  EOS_V2:   dùng transactions/idempotent writes; có overhead tùy workload
  ALOS:     default, faster, may duplicate on failure (handle in downstream)
  → Kafka read-process-write cần atomic: EOS_V2
  → Analytics, aggregations: ALOS (with idempotent downstream)

EOS_V2 chỉ bao phủ dữ liệu Kafka trong topology. Gọi REST, ghi database hoặc gửi email bên ngoài vẫn cần outbox/idempotency; không nên quảng cáo “exactly once toàn hệ thống”.

KTable vs GlobalKTable:
  KTable:       partitioned, each instance has subset, co-partitioned joins
  GlobalKTable: all data on all instances, foreign key joins
  → Small lookup tables (products, config): GlobalKTable
  → Large tables: KTable (partition to distribute)

Window grace period:
  No grace (ofSizeWithNoGrace): discard late records
  Grace period: allow late records, keep window open longer
  → Higher grace = state giữ lâu hơn, có thể đúng hơn với late event nhưng phát kết quả muộn hơn
  → Tune based on expected out-of-order latency

State store size:
  Large state: more RocksDB I/O, slower recovery
  → Tune STATESTORE_CACHE_MAX_BYTES_CONFIG (more cache = fewer RocksDB reads)
  → Configure window/session retention to expire state after its lifecycle

Standby/cache:
  Standby replicas: phục hồi nhanh hơn, đổi lại tốn storage/network và cần restore lag thấp
  Record cache: gộp/collapse update trước khi flush, giảm I/O; không phải source of truth
  Interactive Queries: chỉ local/định tuyến theo metadata; cần xử lý stale/unavailable trong rebalance
```

Các con số throughput/overhead phải được đo với topology, SerDe, state size, broker và workload thật. Tuning cache hoặc EOS không thay thế việc quan sát processing latency, restore lag và rebalance time.

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
      poll-latency-avg:         time spent polling input

    kafka.streams:type=stream-thread-metrics
      commit-total:             total commits
      poll-records-avg:         avg records per poll

    kafka.streams:type=stream-task-metrics
      restore-latency/rate:     state recovery progress
      records-lag-max:          input lag of assigned tasks
      dropped-records-total:    records dropped by configured handler/condition; inspect cause

  Key alerts:
    rebalancing state (REBALANCING): brief is ok, prolonged → issue
    ERROR state: topology failure → alert immediately
    process-rate dropping: slowdown → investigate
    commit-latency spike: state store performance issue
    restore lag growing: standby/active recovery may delay readiness
```

Metrics names and scopes vary by Kafka version and client; alert on trends and correlate lag with processing, restore, rebalance and broker metrics instead of relying on one threshold.

---

## Ghi chú – Chủ đề tiếp theo
> [connect.md](connect.md): Kafka Connect architecture, source/sink connectors, SMTs (Single Message Transforms), Debezium CDC, MirrorMaker2 cross-cluster replication, connector management API
>
> Tài liệu Apache Kafka nên đối chiếu: [Streams Developer Guide](https://kafka.apache.org/43/streams/developer-guide/), [Configuring a Streams Application](https://kafka.apache.org/43/streams/developer-guide/config-streams/), [Kafka Streams Configs](https://kafka.apache.org/43/configuration/kafka-streams-configs/) và [Streams Rebalance Protocol](https://kafka.apache.org/43/streams/developer-guide/streams-rebalance-protocol/).

---

*Cập nhật lần cuối: 2026-07-27*
