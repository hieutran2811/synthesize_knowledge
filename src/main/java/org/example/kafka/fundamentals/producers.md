# Kafka Producers – Config & Guarantees – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Kafka Producer là gì?

**Kafka Producer** *(client xuất bản record vào Kafka broker)* gửi **record** *(bản ghi gồm topic, key, value và metadata)* đến cluster. Producer chịu trách nhiệm:
- **Serialize** *(tuần tự hóa)* key/value thành bytes
- Chọn partition bằng **partitioning strategy** *(chiến lược phân vùng)*
- Buffer và batch record trước khi gửi
- Retry khi gặp lỗi có thể thử lại
- Cung cấp **delivery guarantee** *(cam kết giao nhận)* như at-most-once, at-least-once hoặc Kafka exactly-once trong phạm vi được cấu hình

```
Application → ProducerRecord → Serializer → Partitioner → RecordAccumulator (buffer)
                                                                    ↓
                                                              Sender Thread → Broker
```

> 💡 **Giải thích dễ hiểu:**
> Producer giống một **trung tâm gửi hàng**. Serializer đóng gói hàng, partitioner chọn kho đích, accumulator gom nhiều kiện thành một chuyến xe, còn sender thread là xe chạy nền. “Đã gửi” chỉ có ý nghĩa khi ta nói rõ đã giao tới đâu: rời trung tâm, tới leader, hay đã được đủ replica xác nhận.

---

## Components – Producer Internals

```
KafkaProducer (thread-safe sau khi cấu hình):
  Serializer:        convert key/value to bytes
  Partitioner:       chọn partition (key hash hoặc sticky khi không có key; tùy version/config)
  RecordAccumulator: in-memory buffer (deque of ProducerBatch per TopicPartition)
  Sender thread:     background thread drain buffer → NetworkClient → Broker
  Metadata:          cluster metadata (brokers, topics, partitions, leaders)

ProducerRecord:
  topic, partition (optional), timestamp (optional)
  key, value, headers
```

`KafkaProducer` có thể được gọi từ nhiều application thread sau khi khởi tạo; mỗi thread không cần tự tạo một producer. Tái sử dụng một producer giúp tận dụng connection, buffer và batch. Không chia sẻ một instance giữa các process khác nhau; mỗi process có lifecycle và identity riêng.

---

## How – Producer Configuration

```java
// Core producer config (giá trị ví dụ; kiểm tra default theo Kafka client đang pin)
Properties props = new Properties();
props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092,broker2:9092,broker3:9092");
props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, OrderSerializer.class); // custom Serializer<Order>; Spring Kafka có JsonSerializer riêng

// Reliability
props.put(ProducerConfig.ACKS_CONFIG, "all");          // 0, 1, all (-1)
// Thường để client hiện hành quản lý retries; delivery.timeout.ms là deadline tổng
props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 120000);  // 2 min, ví dụ
props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 30000);    // deadline cho một request

// Idempotence: chống duplicate do retry trong một producer session
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);     // yêu cầu acks=all, retries>0, max.in.flight<=5

// Performance
props.put(ProducerConfig.BATCH_SIZE_CONFIG, 65536);            // 64KB; chỉ là điểm bắt đầu để benchmark
props.put(ProducerConfig.LINGER_MS_CONFIG, 5);                 // wait up to 5ms; default thay đổi theo version
props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, 67108864);      // 64MB buffer (default 32MB)
props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4");      // none, gzip, snappy, lz4, zstd
props.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5); // idempotence giữ order với <=5
```

### Send – Fire and Forget / Callback / Synchronous

```java
KafkaProducer<String, Order> producer = new KafkaProducer<>(props);

// 1. Fire-and-forget (ứng dụng không quan sát kết quả)
producer.send(new ProducerRecord<>("orders", order.getId(), order));

// 2. Async with callback (recommended)
producer.send(
    new ProducerRecord<>("orders", order.getId(), order),
    (RecordMetadata metadata, Exception exception) -> {
        if (exception != null) {
            log.error("Send failed for order {}", order.getId(), exception);
            // Không chặn callback; đưa lỗi vào error topic/outbox hoặc retry worker
        } else {
            log.info("Sent to {}-{} at offset {}",
                metadata.topic(), metadata.partition(), metadata.offset());
        }
    }
);

// 3. Synchronous (blocking – chỉ dùng khi caller thật sự cần kết quả ngay)
try {
    RecordMetadata metadata = producer.send(
        new ProducerRecord<>("orders", order.getId(), order)
    ).get(30, TimeUnit.SECONDS);
    log.info("Offset: {}", metadata.offset());
} catch (ExecutionException e) {
    if (e.getCause() instanceof RetriableException) {
        // Chỉ retry có chủ đích; producer đã có retry nội bộ theo deadline
    } else {
        throw e;  // non-retriable: không retry mù
    }
}

// Always close producer gracefully
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    producer.flush();   // đẩy record đang buffer; vẫn có thể ném lỗi
    producer.close();
}));
```

`send()` bất đồng bộ vẫn có thể giữ thứ tự trong cùng partition nếu ứng dụng giữ cùng key/partition và cấu hình retry/idempotence phù hợp. Gọi `.get()` chỉ biến luồng gọi thành blocking để lấy `RecordMetadata`; nó không tự tạo ordering guarantee và làm giảm concurrency.

Callback thường chạy trên luồng I/O của producer. Không thực hiện HTTP call, retry vòng lặp, ghi DB hoặc chờ lâu trong callback; hãy chuyển công việc nặng sang executor/error topic/outbox. Nếu gửi vào dead-letter topic, việc gửi DLQ cũng có thể thất bại và cần metric, retry/backoff, idempotency key hoặc cơ chế lưu bền trước khi đánh dấu bản ghi đã xử lý.

> 💡 **Giải thích dễ hiểu — callback và retry:**
> Callback giống **nhân viên giao hàng gọi báo “đã giao/chưa giao”**. Nếu bắt nhân viên đứng đó gọi thêm nhiều nơi để giải quyết sự cố, mọi chuyến giao khác sẽ bị kẹt. Hãy ghi nhận lỗi nhanh rồi chuyển sang bàn xử lý riêng; DLQ là kho cách ly, không phải nơi tự động làm mất trách nhiệm retry và quan sát.

---

## How – Acks & Delivery Guarantees

```
acks=0: Fire and forget
  - No wait for broker acknowledgment
  - send() có thể hoàn tất trước khi broker nhận; metadata offset không có giá trị xác nhận
  - Use: metrics, non-critical telemetry

acks=1: Leader only
  - Wait for leader to write to local log
  - Message lost if leader fails before replication
  - Chỉ là trade-off latency/durability; at-least-once còn phụ thuộc retry và cách ứng dụng xử lý lỗi

acks=all (= -1): All ISR
  - Leader chờ toàn bộ ISR hiện tại xác nhận
  - `min.insync.replicas` đặt ngưỡng tối thiểu; nếu ISR thấp hơn ngưỡng, broker từ chối ghi
  - Không tự đảm bảo “bền vững tuyệt đối”: còn phụ thuộc replication factor, ISR thực tế, `unclean.leader.election` và các lỗi đồng thời
  - Thường phù hợp dữ liệu quan trọng, nhưng latency/availability phải đo theo SLA

min.insync.replicas (broker/topic config):
  Combined with acks=all: yêu cầu ít nhất N ISR xác nhận mỗi write thành công
  Example: RF=3, min.insync.replicas=2
    → Leader + 1 follower must confirm
    → Có thể tiếp tục ghi khi còn 2 ISR, nhưng chỉ trong giả định cluster không mất đồng thời quá ngưỡng và không dùng unclean election
    → If < 2 ISR available → NotEnoughReplicasException / NotEnoughReplicasAfterAppendException
```

> 💡 **Giải thích dễ hiểu — `acks` và ISR:**
> Hãy coi leader là **thủ kho** và ISR là các kho dự phòng đang bắt kịp sổ. `acks=1` chỉ cần thủ kho ký; `acks=all` yêu cầu mọi kho đang “đồng bộ” ký. `min.insync.replicas=2` là quy định “ít nhất hai chữ ký mới được xuất hàng”. Nếu chỉ còn một kho, hệ thống từ chối nhận để không tạo cảm giác an toàn giả.

> `acks=all` không đồng nghĩa với backup bất tử. Muốn diễn giải “đã bền” phải kiểm tra đồng thời RF, ISR, chính sách leader election, disk/cluster failure model và khả năng khôi phục. Đây là guarantee có điều kiện, không phải cam kết không thể mất dữ liệu trong mọi thảm họa.

```properties
# server.properties (broker default)
default.replication.factor=3
min.insync.replicas=2

# Per-topic override
kafka-configs.sh --alter --entity-type topics --entity-name orders \
  --add-config min.insync.replicas=2
```

---

## How – Retry và các timeout liên quan

Ba đồng hồ sau giải quyết ba việc khác nhau:

- **`request.timeout.ms`** *(timeout chờ một request)*: thời gian client chờ broker trả lời một request. Hết thời gian, request có thể được retry nếu lỗi được xem là transient.
- **`delivery.timeout.ms`** *(deadline giao record)*: giới hạn tổng thời gian từ lúc `send()` nhận record đến khi producer báo thành công/thất bại, bao gồm chờ batch, acknowledgment và retry. Theo tài liệu client, nên đặt lớn hơn hoặc bằng `request.timeout.ms + linger.ms`.
- **`max.block.ms`** *(timeout chặn phía caller)*: giới hạn thời gian `send()` chờ metadata hoặc chỗ trong buffer; không phải deadline broker ack.

Để tránh retry kéo dài vô hạn hoặc hết deadline trước khi retry hữu ích, thường để client hiện hành quản lý `retries` và dùng `delivery.timeout.ms` làm deadline tổng. Tăng `request.timeout.ms` quá cao có thể làm phát hiện lỗi chậm; đặt thấp hơn thời gian broker/replica lag hợp lý có thể tạo retry dư thừa.

> 💡 **Giải thích dễ hiểu — ba chiếc đồng hồ:**
> Một chuyến xe có đồng hồ chờ **trạm giao** (`request.timeout`), đồng hồ chờ **toàn bộ hành trình** (`delivery.timeout`) và đồng hồ chờ **bãi xếp hàng** (`max.block`). Tăng một đồng hồ không tự làm hai đồng hồ kia dài ra; cấu hình lệch khiến xe báo lỗi sớm hoặc đứng chờ quá lâu.

---

## How – Idempotent Producer

```
Problem: producer retry → duplicate messages (network timeout, leader failover)

Solution: Idempotent Producer (Kafka 0.11+)
  - Broker assigns PID (Producer ID) to each producer session
  - Each record has sequence number (per partition)
  - Broker deduplicates: rejects records with seq ≤ last committed seq
  - Guarantee: broker-side exactly-once append per partition trong producer session

Limitation:
  - Exactly-once within 1 producer instance (PID resets on restart)
  - Application tự gửi lại cùng business event sau lỗi có thể tạo bản ghi khác (không cùng sequence)
  - Does NOT guarantee exactly-once across multiple producers, database hoặc external side effects
  - For atomic cross-topic writes/offsets → need Transactions
```

Idempotence và ordering liên quan chặt với `retries` và `max.in.flight.requests.per.connection`. Khi idempotence bật, Kafka yêu cầu `acks=all`, `retries>0` và `max.in.flight<=5`; trong giới hạn đó retry vẫn giữ thứ tự cho một partition. Khi idempotence tắt nhưng vừa retry vừa cho phép nhiều request in-flight, batch sau có thể được ghi trước batch trước nếu batch trước thất bại rồi retry.

```java
// Enable idempotence (client hiện hành tự áp điều kiện acks/retries/in-flight phù hợp)
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);

// Verify: check producer metrics
producer.metrics().forEach((name, metric) -> {
    if (name.name().contains("record-error-rate") || name.name().contains("record-retry-rate")) {
        System.out.println(name + ": " + metric.metricValue());
    }
});
```

> 💡 **Giải thích dễ hiểu — PID và sequence:**
> Mỗi producer session giống một **cuốn sổ có số seri**. Nếu xe vận chuyển báo timeout rồi gửi lại kiện số 42, broker nhận ra cùng PID + sequence và không nhập kho lần hai. Khi ứng dụng tự tạo một kiện mới sau khi không biết kết quả của kiện cũ, nó có số seri khác; idempotence không thể đoán đó là cùng một business event.

---

## How – Transactions (Exactly-Once Semantics)

```
Transactional Producer: atomic write across multiple partitions/topics và offset transaction
  - Các record/offset Kafka trong một transaction cùng commit hoặc cùng abort
  - Consumers with isolation.level=read_committed skip aborted transactions
  - Use case: consume-process-produce (Kafka Streams, stream processing)
  - Không tự làm DB call, HTTP call hoặc side effect ngoài Kafka trở thành atomic

transactional.id: ổn định cho một logical producer instance (survives restarts), nhưng khác nhau giữa các instance chạy song song
  - Broker fences zombie producers (same transactional.id, old epoch)
```

Để đạt **EOS (Exactly-Once Semantics)** *(ngữ nghĩa xử lý đúng một lần trong phạm vi Kafka)* ở mô hình consume-process-produce, producer phải đưa offset consumer vào transaction bằng `sendOffsetsToTransaction`, consumer phải dùng `isolation.level=read_committed`, và ứng dụng không được tạo side effect ngoài transaction mà không có outbox/idempotency riêng. Transaction timeout, transaction state log và `min.insync.replicas` cũng cần được đặt phù hợp với cluster.

```java
// transactional.id tự bật các điều kiện idempotence trong client hỗ trợ transactions
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
    // Lỗi có thể phục hồi: abort rồi retry transaction theo backoff/deadline
    producer.abortTransaction();
    throw e;
}
```

> 💡 **Giải thích dễ hiểu — transaction:**
> Transaction giống **phiếu xuất kho có hai món và một dòng cập nhật sổ**: hoặc cả ba cùng đóng dấu, hoặc không món nào được coi là đã xuất. Con dấu đó chỉ áp dụng cho Kafka; nếu nhân viên còn gọi ngân hàng bên ngoài, giao dịch ngân hàng vẫn cần cơ chế idempotency/outbox riêng.

---

## How – Partitioning Strategies

```java
// Default partitioning logic (kiểm tra theo Kafka client version đang dùng)
// - partition chỉ định trong ProducerRecord → dùng partition đó
// - key != null → hash(key) chọn partition, giữ key affinity
// - không có key → sticky vào một partition cho tới khi batch đạt ngưỡng rồi đổi
// `partitioner.ignore.keys=true` có thể bỏ qua key; custom partitioner thay đổi toàn bộ quy tắc.

// Custom Partitioner: implement Partitioner interface
public class CustomerPartitioner implements Partitioner {
    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        List<PartitionInfo> partitions = cluster.partitionsForTopic(topic);
        int numPartitions = partitions.size();

        if (keyBytes == null || !(key instanceof String)) {
            throw new InvalidRecordException("Orders must have a customer ID key");
        }

        if (numPartitions <= 1) {
            return 0;
        }

        // VIP customers → partition 0 (dedicated)
        if (((String) key).startsWith("VIP-")) {
            return 0;
        }
        // Others → partitions 1..N
        return Math.floorMod(Utils.murmur2(keyBytes), numPartitions - 1) + 1;
    }

    @Override public void close() {}
    @Override public void configure(Map<String, ?> configs) {}
}

// Register
props.put(ProducerConfig.PARTITIONER_CLASS_CONFIG, CustomerPartitioner.class);
```

Custom partitioner phải cân bằng giữa key affinity, phân bố tải, partition đang khả dụng và khả năng thêm/bớt partition. Hard-code một partition cho VIP có thể tạo hot partition; khi đổi số partition, hash mapping cũng có thể thay đổi. `Math.abs(int)` không an toàn với `Integer.MIN_VALUE`, nên dùng `Math.floorMod`/hàm chuyển số dương phù hợp.

> 💡 **Giải thích dễ hiểu — partitioner:**
> Partitioner giống **quầy phân loại bưu kiện**. Mã khách hàng là địa chỉ để các kiện cùng khách đi cùng quầy; sticky không có key giống việc tiếp tục chất hàng vào một xe cho đầy trước khi chuyển sang xe khác. Tự ưu tiên VIP một quầy có thể khiến quầy đó tắc nghẽn dù các quầy khác còn rảnh.

---

## How – Compression

```
Compression: applied at batch level (not per record)
  Producer compresses batch → sends to broker → broker stores compressed
  Consumer decompresses after receiving

Types:
  none:   không nén (default theo producer config hiện hành)
  gzip:   thường ưu tiên ratio hơn CPU
  snappy: codec cân bằng theo workload
  lz4:    thường giải nén nhanh, ratio/CPU cần benchmark
  zstd:   thường cho ratio tốt với tốc độ cạnh tranh trên workload phù hợp
```

Không nên dùng bảng xếp hạng throughput/ratio cố định: payload lặp hay ngẫu nhiên, batch size, CPU, network và version codec đều làm kết quả đổi. Đo cả producer CPU, broker disk/network, consumer CPU và end-to-end latency trước khi chọn codec.

```properties
# Producer config
compression.type=lz4

# Broker can also compress/recompromise:
compression.type=producer  # giữ codec do producer gửi (thường là default)
compression.type=lz4       # broker nén lại về codec này
```

`compression.type` ở broker có thể giữ codec producer (`producer`) hoặc yêu cầu broker recompress. Nén hiệu quả hơn khi batch đủ lớn; vì vậy `batch.size`/`linger.ms` cũng ảnh hưởng ratio. Nén giảm network/storage nhưng đổi lấy CPU và latency nén/giải nén.

> 💡 **Giải thích dễ hiểu — compression:**
> Nén ở cấp batch giống **đóng nhiều món vào một thùng rồi hút bớt khoảng trống**, thay vì bọc từng món riêng lẻ. Một thùng đủ nhiều món tương tự thường nén tốt hơn, nhưng người đóng và mở thùng đều phải tốn công CPU.

---

## How – Batching & Throughput Tuning

```
RecordAccumulator: buffer records per TopicPartition in ProducerBatch

batch.size (default 16384 = 16KB):
  Ngưỡng bytes producer dành cho mỗi ProducerBatch của từng TopicPartition
  Batch lớn hơn có thể giảm số request nhưng tăng memory/latency; không có một giá trị đúng cho mọi workload

linger.ms (Kafka 4.x default 5; các dòng cũ thường default 0):
  Thời gian tối đa chờ record khác để lấp batch chưa đầy
  Batch đạt batch.size sẽ được gửi ngay; linger không phải thời gian chờ cứng trong mọi tình huống

buffer.memory (default 33554432 = 32MB):
  Total memory for all buffered records
  Nếu buffer đầy → send() block tối đa max.block.ms rồi ném lỗi phù hợp
  Đây là ngân sách buffer gần đúng, không phải hard cap cho toàn bộ heap producer

max.block.ms (default 60000):
  Time to block send() when buffer full or metadata unavailable

max.request.size (default 1048576 = 1MB):
  Cap phía producer cho request/record batch chưa nén
  Broker còn có giới hạn riêng (`message.max.bytes`/record batch); payload sau cùng phải vừa cả hai phía, không nhất thiết hai config bằng nhau
```

```
Throughput optimization checklist:
  ✅ Đo baseline: p95/p99 latency, record size, batch-size-avg, CPU, network và error rate
  ✅ Chọn batch.size/linger.ms theo latency SLA và tốc độ record thực tế
  ✅ Benchmark none/lz4/zstd (hoặc codec được cluster hỗ trợ)
  ✅ Với dữ liệu quan trọng: idempotence + acks=all + ISR/min.insync phù hợp
  ✅ Tăng buffer.memory chỉ khi quan sát buffer exhaustion/backpressure và có heap budget
  ✅ max.in.flight<=5 khi bật idempotence; nếu tắt idempotence, đánh giá rủi ro reorder khi retry
```

> 💡 **Giải thích dễ hiểu — batch, linger và buffer:**
> Batch size là **sức chứa một xe**, linger là thời gian xe đứng chờ thêm hàng, còn buffer memory là số hàng có thể xếp ở bãi chờ. Xe quá nhỏ thì chạy nhiều chuyến; xe quá lớn hoặc đứng quá lâu thì khách chờ. Bãi quá nhỏ khiến quầy nhận hàng phải dừng, nhưng mở bãi vô hạn chỉ che vấn đề downstream.

---

## Why – Producer Design Choices

```
Why batch before send?
  Network round trips are expensive
  Batching amortizes request overhead, nhưng lợi ích phụ thuộc record size/arrival rate
  1 request chứa nhiều record thường giảm request count so với 1 request/record; hãy đo latency và CPU

Why sticky partitioning for unkeyed records?
  Gửi lần lượt sang nhiều partition có thể tạo batch nhỏ ở từng partition
  Sticky giữ lựa chọn trong một khoảng để batch có cơ hội đầy hơn; hành vi/default có thể đổi theo Kafka client version

Why idempotence?
  Retries (for network failures) cause duplicates without idempotence
  PID + sequence number → broker can detect and drop duplicates
  Cost/trade-off: sequence tracking và yêu cầu acks/retry/in-flight phù hợp; không bao phủ application resend hoặc external side effect
```

Thứ tự Kafka chỉ có ý nghĩa **trong một partition**. Muốn các event của cùng aggregate đi theo thứ tự, dùng key ổn định để chúng vào cùng partition và không để retry không-idempotent reorder batch. Không thể dùng số throughput cố định để suy ra thứ tự hay latency; quan sát `batch-size-avg`, `record-queue-time-avg` và p95/p99 thực tế.

---

## Trade-offs

```
acks=all + retries:
  ✅ Durability mạnh hơn khi RF/ISR/min.insync/leader-election được vận hành đúng
  ❌ Có thể tăng latency và từ chối ghi khi ISR dưới ngưỡng
  → Use for financial data, critical events

acks=1:
  ✅ Balance latency vs durability
  ❌ Có thể mất data nếu leader lỗi trước replication; retry cũng cần cấu hình
  → Use for telemetry/logs nếu business chấp nhận loss

Idempotence vs Transactions:
  Idempotence: chống duplicate broker-side trong một producer session/partition
  Transactions: atomic Kafka records + offsets across partitions/topics → complex, overhead
  → Use transactions only when needed (consume-process-produce)

Large batches (high linger.ms, large batch.size):
  ✅ Higher throughput
  ❌ Higher latency (wait to fill batch)
  → Tune based on latency SLA

Compression:
  ✅ Less network bandwidth, less broker storage
  ❌ CPU overhead at producer and consumer
  → Chọn codec sau benchmark; lz4/zstd chỉ là candidate, không phải mặc định tối ưu

Retry/DLQ:
  ✅ Retry transient errors với delivery deadline và backoff phù hợp
  ❌ Retry application-level có thể duplicate/reorder nếu không có idempotency
  → DLQ/error topic phải có retention, ACL, replay procedure và monitor; gửi DLQ cũng có thể thất bại

Exactly-once:
  ✅ Kafka transaction có thể commit records + consumed offsets atomically
  ❌ Không mở rộng atomicity sang DB/API/side effect bên ngoài Kafka
  → Dùng read_committed + offset transaction + outbox/idempotency cho hệ thống liên kết ngoài
```

---

## Real-world

```java
// Production-grade producer setup
public KafkaProducer<String, Order> buildProducer(KafkaConfig config) {
    Properties props = new Properties();
    // Connectivity
    props.put(BOOTSTRAP_SERVERS_CONFIG, config.getBootstrapServers());
    props.put(SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
    props.put(SASL_MECHANISM_CONFIG, "PLAIN");
    props.put(SASL_JAAS_CONFIG, config.getJaasConfig());

    // Serializers
    props.put(KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
    props.put(VALUE_SERIALIZER_CLASS_CONFIG, OrderSerializer.class); // JSON/Avro/Protobuf tùy contract

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
    props.put(INTERCEPTOR_CLASSES_CONFIG, List.of( // optional, nếu đã có dependency interceptor
        "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor"
    ));

    return new KafkaProducer<>(props);
}
```

Production checklist cho serializer/schema/security:

- Serializer phải deterministic, giới hạn kích thước và ném lỗi rõ ràng khi dữ liệu không hợp lệ; lỗi serialization thường không phải lỗi transient để retry mù.
- Nếu dùng JSON, version DTO và quy tắc backward/forward compatibility phải được review. Với Avro/Protobuf/JSON Schema, dùng schema registry hoặc cơ chế phát hành schema có kiểm soát; producer/consumer phải thống nhất subject, compatibility mode và cách xử lý unknown field.
- Không serialize secret/PII vào payload hoặc log callback. `SASL_SSL` bảo vệ đường truyền khi cấu hình đúng; credential nên lấy từ secret manager, ACL chỉ cấp quyền topic/group cần thiết. `PLAIN` chỉ nên dùng trên TLS và theo chính sách cluster.
- `client.id`, topic, partition, key và correlation/idempotency key nên được đưa vào log/trace có chọn lọc để điều tra mà không lộ payload nhạy cảm.

> 💡 **Giải thích dễ hiểu — serializer và schema:**
> Serializer là **quy cách đóng gói**, schema là **mẫu hóa đơn mà bên nhận hiểu được**. Đổi tên cột mà không có quy tắc tương thích giống gửi kiện hàng bằng mẫu mới cho kho cũ: xe vẫn chạy nhưng hàng có thể bị từ chối hoặc hiểu sai. Schema registry/contract test là cuốn sổ mẫu chung, không phải phép màu thay cho validation.

```
Monitoring metrics (JMX):
  record-send-rate:         records/sec sent
  record-error-rate:        delivery failures (alert theo ngưỡng/SLO, không phải mọi giá trị > 0)
  record-retry-rate:        retries occurring (investigate sustained spikes)
  request-latency-avg:      avg broker response time
  request-latency-max:      tail latency / timeout clue
  record-queue-time-avg:    time waiting in producer before send
  batch-size-avg:           check if batching is working
  compression-rate-avg:     actual compression achieved
  buffer-available-bytes:   watch for buffer exhaustion
  bufferpool-wait-time:     producer threads waiting for buffer
  produce-throttle-time-avg: broker throttling producer
```

Theo dõi cùng callback error, retry/DLQ rate, `TimeoutException`, `RecordTooLargeException`, `NotEnoughReplicas*`, serializer error và broker throttle. Đặt alert theo error budget/SLO và xu hướng, không chỉ theo một sample metric; metric names/default labels có thể thay đổi theo Kafka client/monitoring exporter.

---

## Ghi chú – Chủ đề tiếp theo
> [consumers.md](consumers.md): Consumer groups, offset management, rebalancing protocols (eager/cooperative), commit strategies, exactly-once consumption, consumer configs, lag monitoring

### Tài liệu Apache Kafka chính thức

- [Producer configuration (Kafka 4.1)](https://kafka.apache.org/41/configuration/producer-configs/)
- [KafkaProducer Java API](https://kafka.apache.org/41/javadoc/org/apache/kafka/clients/producer/KafkaProducer.html)
- [Partitioner Java API](https://kafka.apache.org/41/javadoc/org/apache/kafka/clients/producer/Partitioner.html)

---

*Cập nhật lần cuối: 2026-07-22*
