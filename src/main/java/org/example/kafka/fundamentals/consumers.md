# Kafka Consumers & Consumer Groups – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Kafka Consumer là gì?

**Kafka Consumer** *(client đọc bản ghi)* là client đọc records từ Kafka topics. Consumer dùng **pull model** *(mô hình kéo)* – chủ động `poll()` broker, không bị broker push trực tiếp.

```
Kafka Consumer khác traditional MQ consumer:
  - Consumer tự quản lý **offset** *(vị trí kế tiếp trong partition)*
  - Có thể seek đến bất kỳ offset nào
  - Có thể replay messages (không xóa sau khi đọc)
  - **Consumer group** *(nhóm consumer cùng chia việc)* = horizontal scaling *(mở rộng ngang)* + failover tự động
```

> 💡 **Giải thích dễ hiểu:**
> Kafka giống kho hàng cho phép nhân viên tự đến lấy lô hàng. Mỗi consumer tự ghi lại mình đã lấy tới kiện nào, nên có thể quay lại lấy lại (replay) hoặc để nhiều đội khác nhau đọc cùng một kho theo các `group.id` riêng.

---

## Components – Consumer Group *(nhóm consumer)*

```
Consumer Group: group of consumers sharing same group.id
  - Mỗi partition chỉ được assign cho 1 consumer trong group
  - 1 consumer có thể handle nhiều partitions
  - Nếu consumers > partitions: một số consumer idle
  - Different groups: mỗi group có offset riêng → **fan-out pattern** *(một bản ghi được nhiều nhóm đọc độc lập)*

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
  - Same non-null key + cùng partitioner → cùng partition → ordered processing
```

Assignment này là ràng buộc **trong từng group**. Hai group khác nhau vẫn có thể cùng đọc một partition. Kafka chỉ đảm bảo thứ tự theo offset trong một partition; nếu cần thứ tự theo entity, producer phải dùng key ổn định (và không đổi partition count một cách phá vỡ quy ước phân vùng).

> 💡 **Giải thích dễ hiểu:**
> Một quầy thu ngân (partition) chỉ có một nhân viên của cùng đội phụ trách tại một thời điểm, nhưng đội A và đội B có thể cùng xem bản sao sổ giao dịch. Tăng số nhân viên vượt số quầy không làm tốc độ tăng—người dư sẽ đứng idle.

---

## How – Consumer Configuration

```java
Properties props = new Properties();
props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker1:9092,broker2:9092");
props.put(ConsumerConfig.GROUP_ID_CONFIG, "order-processor-group");
props.put(ConsumerConfig.GROUP_PROTOCOL_CONFIG, "classic"); // ví dụ dùng classic protocol
props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);

// Offset reset: xử lý khi không có committed offset hợp lệ
props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");  // earliest | latest | none
// none: ném NoOffsetForPartitionException thay vì tự chọn vị trí

// Commit
props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);  // manual commit khi cần kiểm soát side effect
// props.put(ConsumerConfig.AUTO_COMMIT_INTERVAL_MS_CONFIG, 5000);  // if auto commit

// Polling
props.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 500);          // records per poll()
props.put(ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG, 300000);   // 5 min (time to process batch)
props.put(ConsumerConfig.FETCH_MIN_BYTES_CONFIG, 1);             // min bytes before returning
props.put(ConsumerConfig.FETCH_MAX_WAIT_MS_CONFIG, 500);         // max wait if < fetch.min.bytes
props.put(ConsumerConfig.FETCH_MAX_BYTES_CONFIG, 52428800);      // 50MB max per fetch

// Session & heartbeat của classic protocol (detect dead consumers)
props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 45000);      // no heartbeat = dead
props.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 3000);    // must be < session.timeout/3

KafkaConsumer<String, Order> consumer = new KafkaConsumer<>(props);
```

`max.poll.interval.ms` đo thời gian giữa **hai lần gọi `poll()`**, không phải thời gian broker chờ từng record. Nếu xử lý một batch quá lâu, consumer có thể bị coi là không tiến triển và bị rebalance dù heartbeat vẫn được gửi trong thời gian đó. `max.poll.records` phải được chọn sao cho thời gian xử lý worst-case của một batch nhỏ hơn interval với khoảng đệm.

Với `group.protocol=classic`, client cấu hình `heartbeat.interval.ms` và `session.timeout.ms`. Với Kafka Consumer Protocol (`group.protocol=consumer`, Kafka 4.x), heartbeat/session do broker quản lý và hai cấu hình client đó không còn là nơi điều chỉnh chính.

> 💡 **Giải thích dễ hiểu:**
> `poll()` giống việc nhân viên quẹt thẻ “tôi vẫn đang làm việc”. Heartbeat là tín hiệu sống nền, nhưng nếu quá lâu không quay lại quầy để nhận lô mới (`max.poll.interval.ms`), quản lý vẫn điều người khác thay ca vì tưởng nhân viên bị kẹt.

---

## How – Poll Loop

```java
consumer.subscribe(List.of("orders", "payments"));  // pattern: subscribe(Pattern.compile("order.*"))

// Manual partition assignment (no rebalancing)
// consumer.assign(List.of(new TopicPartition("orders", 0), new TopicPartition("orders", 1)));

Map<TopicPartition, OffsetAndMetadata> pendingOffsets = new HashMap<>();

// Đăng ký hook TRƯỚC khi vào vòng lặp; wakeup() là API thread-safe để ngắt poll().
Runtime.getRuntime().addShutdownHook(new Thread(() -> {
    running.set(false);
    consumer.wakeup();
}));

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
            pendingOffsets.put(
                partition, new OffsetAndMetadata(lastOffset + 1)  // next offset to read
            );
        }

        if (!pendingOffsets.isEmpty()) {
            consumer.commitSync(pendingOffsets); // chỉ commit partition đã xử lý xong
            pendingOffsets.clear();
        }
    }
} catch (WakeupException e) {
    // Expected: consumer.wakeup() called from shutdown hook
    if (running.get()) throw e;
} finally {
    try {
        if (!pendingOffsets.isEmpty()) {
            consumer.commitSync(pendingOffsets); // không dùng commitSync() theo current position
        }
    } catch (KafkaException e) {
        log.warn("Final offset commit failed; records may be delivered again", e);
    } finally {
        consumer.close(Duration.ofSeconds(10));
    }
}
```

`poll()` đã tăng current position tới sau batch vừa trả về. Vì vậy `commitSync()` không tham số trong `finally` có thể commit cả record chưa xử lý nếu exception xảy ra giữa batch. Ví dụ trên chỉ lưu `lastOffset + 1` sau khi **toàn bộ records của partition trong batch** đã thành công; crash trước commit gây đọc lại, không gây bỏ qua.

> 💡 **Giải thích dễ hiểu:**
> Offset commit giống đánh dấu trang “lần sau đọc từ đây”. Chỉ đánh dấu sau khi làm xong; nếu đánh dấu ngay khi vừa nhận xấp hồ sơ rồi mất điện, các hồ sơ chưa xử lý sẽ bị coi như đã xong.

---

## How – Offset Management

```
Offset: position in partition (next record to read)
  committed offset: saved to __consumer_offsets topic
  current position: consumer's in-memory position

Commit strategies:
  1. Auto commit:       easy, commit periodically khi poll; có thể duplicate hoặc mất record
  2. commitSync():      after-processing, blocks, at-least-once
  3. commitAsync():     non-blocking; callback có lỗi nhưng không tự retry
  4. Hybrid:            commitAsync() in loop, commitSync() on shutdown/rebalance
```

Kafka lưu **offset kế tiếp cần đọc**, nên sau khi xử lý record offset `42` phải commit `43`. At-least-once chỉ đạt được khi commit sau side effect thành công; crash sau side effect nhưng trước commit sẽ tạo duplicate khi khởi động lại. Auto-commit không tự biết lúc business processing hoàn tất, nên không nên gắn cho nó bảo đảm at-least-once chung chung.

> 💡 **Giải thích dễ hiểu:**
> Current position là ngón tay đang trượt trên sách; committed offset là chiếc bookmark bền vững. Ngón tay có thể đi xa hơn phần đã hiểu, vì `poll()` đã giao cả batch. Chỉ bookmark phần thật sự xử lý xong.

```java
// Async trong loop + sync khi revoke/close
Map<TopicPartition, OffsetAndMetadata> currentOffsets = new HashMap<>();

consumer.subscribe(topics, new ConsumerRebalanceListener() {
    @Override
    public void onPartitionsRevoked(Collection<TopicPartition> partitions) {
        // Cooperative rebalance có thể chỉ revoke một phần assignment.
        Map<TopicPartition, OffsetAndMetadata> revokedOffsets = partitions.stream()
            .filter(currentOffsets::containsKey)
            .collect(Collectors.toMap(tp -> tp, currentOffsets::get));
        if (!revokedOffsets.isEmpty()) {
            consumer.commitSync(revokedOffsets);
        }
        partitions.forEach(currentOffsets::remove);
    }

    @Override
    public void onPartitionsAssigned(Collection<TopicPartition> partitions) {
        // Optional: seek to specific offset
        // partitions.forEach(tp -> consumer.seek(tp, getLastProcessedOffset(tp)));
    }

    @Override
    public void onPartitionsLost(Collection<TopicPartition> partitions) {
        // Ownership đã mất: không cố commit offset của partition này.
        partitions.forEach(currentOffsets::remove);
    }
});

while (running.get()) {
    ConsumerRecords<String, Order> records = consumer.poll(Duration.ofMillis(100));

    for (ConsumerRecord<String, Order> record : records) {
        processOrder(record.value());
        currentOffsets.put(
            new TopicPartition(record.topic(), record.partition()),
            new OffsetAndMetadata(record.offset() + 1, "metadata")
        );
    }

    consumer.commitAsync(new HashMap<>(currentOffsets), (offsets, exception) -> {
        if (exception != null) {
            log.error("Commit failed for {}", offsets, exception);
            // Không retry async commit cũ ở đây: có thể ghi đè offset mới hơn.
        }
    });
}

// Final sync commit
consumer.commitSync(currentOffsets);
```

Các callback rebalance chạy trên consumer thread trong lời gọi `poll()`, không phải song song tùy ý. `onPartitionsRevoked` vẫn còn cơ hội commit các partition bị thu hồi; `onPartitionsLost` báo rằng ownership có thể đã chuyển sang consumer khác, nên commit lúc đó không còn an toàn.

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

Trước khi reset offset, thường phải dừng group để tránh consumer đang chạy tiếp tục dùng current position hoặc commit đè kết quả reset. Luôn chạy thử với `--dry-run`, kiểm tra phạm vi topic/partition và dự đoán side effect khi replay.

---

## How – Rebalancing Protocols

### Classic/Eager Rebalancing *(thu hồi toàn bộ trước khi chia lại)*

```
Eager protocol:
  1. All consumers revoke ALL partitions (stop processing)
  2. Group coordinator assigns partitions fresh
  3. All consumers start with new assignment

  Problem: brief stop-the-world for entire group
           even if only 1 consumer joins/leaves
```

### Classic/Cooperative Rebalancing *(thu hồi tăng dần)*

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
// Trạng thái đích: TẤT CẢ member trong group dùng CooperativeStickyAssignor
props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
    CooperativeStickyAssignor.class.getName());

// Bước rolling migration: giữ assignor eager hiện tại đứng trước trong danh sách.
// Sau khi mọi member đã hiểu CooperativeStickyAssignor, rollout lần nữa và bỏ RangeAssignor.
props.put(ConsumerConfig.PARTITION_ASSIGNMENT_STRATEGY_CONFIG,
    List.of(RangeAssignor.class.getName(), CooperativeStickyAssignor.class.getName()));
```

Cooperative rebalance không có nghĩa “không dừng bao giờ”: partition cần chuyển vẫn phải được revoke trước khi owner mới nhận, và quá trình có thể cần nhiều vòng rebalance. Lợi ích là những partition không bị ảnh hưởng tiếp tục chạy.

> 💡 **Giải thích dễ hiểu:**
> Eager giống đóng toàn bộ siêu thị để chia lại quầy cho nhân viên. Cooperative chỉ đóng các quầy cần đổi người; các quầy khác tiếp tục bán, nhưng việc bàn giao có thể cần hai lượt để chắc chắn không có hai người cùng giữ một quầy.

### Kafka Consumer Group Protocol (Kafka 4.x)

Kafka 4.x bổ sung `group.protocol=consumer`: heartbeat và partition assignment được điều phối theo protocol mới, assignor nằm phía broker. Nó không đồng nghĩa với `CooperativeStickyAssignor` của classic protocol. Các ví dụ `heartbeat.interval.ms`, `session.timeout.ms` và `partition.assignment.strategy` trong file này đang mô tả `group.protocol=classic`; khi chuyển protocol cần dùng cấu hình broker/group tương ứng.

### Static Group Membership

```java
// Static membership: skip rebalance for brief restarts
// Assign stable member ID to consumer → broker waits session.timeout before reassigning
props.put(ConsumerConfig.GROUP_INSTANCE_ID_CONFIG, "consumer-pod-1");  // unique per instance
props.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 60000);  // give 60s for restart

// Use case: stateful consumers (Kafka Streams, local state stores)
// Benefit: restart consumer without triggering rebalance
```

`group.instance.id` phải duy nhất cho từng instance đang chạy; trùng ID dẫn tới **fencing** *(broker loại member cũ/trùng danh tính)*. Static membership giảm rebalance khi restart ngắn, nhưng đổi lại partition có thể nằm chờ đến session timeout trước khi failover. Khi vượt `max.poll.interval.ms`, static member dừng heartbeat và partition chỉ được giao lại sau session timeout thay vì ngay lập tức.

> 💡 **Giải thích dễ hiểu:**
> Static member giống nhân viên có tủ đồ mang tên cố định: nghỉ giải lao ngắn vẫn giữ ca, tránh chia lại quầy. Nhưng nếu họ mất tích thật, quản lý phải chờ hết thời hạn giữ chỗ nên việc thay người chậm hơn.

---

## How – Exactly-Once Consumption

```
Delivery semantics:
  at-most-once:   commit before process → may lose messages (process crash after commit)
  at-least-once:  commit after process  → may duplicate (commit fail after process)
  exactly-once:   Kafka read-process-write dùng transaction; external side effect cần thiết kế riêng

Strategies:
  1. Idempotent processing: check business event ID / DB dedup key
  2. Transactional consume-process-produce + sendOffsetsToTransaction()
  3. Kafka Streams Exactly-once Semantics (EOS)
```

Kafka transaction có thể atomically ghi output Kafka và consumer offsets, nhưng không tự gộp transaction của database hay HTTP API bên ngoài. Với side effect ngoài Kafka, thường dùng **idempotent consumer** *(xử lý lặp không đổi kết quả)*, dedup table hoặc outbox/inbox; `topic-partition-offset` chống xử lý lại cùng một Kafka record, còn business event ID chống producer gửi lại cùng sự kiện ở offset khác.

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

// Consumer đọc output transactional: ẩn record thuộc transaction đã abort
props.put(ConsumerConfig.ISOLATION_LEVEL_CONFIG, "read_committed");
```

Với `isolation.level=read_committed`, `poll()` trả record non-transactional và record của transaction đã commit, nhưng giữ lại phần sau **last stable offset (LSO)** khi còn transaction mở. Vì vậy consumer có thể tạm thời không đọc tới high watermark và lag quan sát được cần diễn giải cùng trạng thái transaction.

> 💡 **Giải thích dễ hiểu:**
> Transaction Kafka giống phong bì niêm phong gồm cả kết quả mới và bookmark offset: hoặc cả hai được công bố, hoặc cả hai bị hủy. `read_committed` chỉ mở phong bì đã đóng dấu; nó không thể rollback một email hay giao dịch ở hệ thống bên ngoài.

---

## How – Seek & Replay

```java
// Seek to beginning (replay all)
consumer.subscribe(List.of("orders"));
while (consumer.assignment().isEmpty()) {
    consumer.poll(Duration.ofMillis(100)); // poll cho tới khi group assignment hoàn tất
}
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

`seek()` chỉ đổi current position của partition đang được assign; nó không tự đổi committed offset. Nếu muốn lần khởi động sau cũng bắt đầu từ vị trí replay, cần chủ động commit vị trí phù hợp sau khi xử lý, và cân nhắc duplicate side effect.

---

## Why – Pull vs Push Model

```
Kafka: Pull model
  Consumer controls when to fetch
  Consumer controls batch size (MAX_POLL_RECORDS)
  Consumer vẫn cần backpressure khi downstream chậm
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

Không nên “ngừng poll” để tạo **backpressure** *(điều tiết khi downstream chậm)* vì có thể vượt `max.poll.interval.ms`. Hãy `pause()` các partition, tiếp tục `poll()` để duy trì group/rebalance, rồi `resume()` khi hàng đợi xử lý đã hạ xuống; đồng thời đặt queue có giới hạn thay vì buffer vô hạn.

```java
Set<TopicPartition> assigned = consumer.assignment();
consumer.pause(assigned);

while (downstreamQueueIsFull()) {
    consumer.poll(Duration.ofMillis(100)); // duy trì consumer, không nhận record từ partition paused
}

consumer.resume(consumer.paused()); // lấy assignment hiện tại sau mọi rebalance
```

> 💡 **Giải thích dễ hiểu:**
> `pause()` giống treo biển “tạm ngừng nhận hàng” nhưng nhân viên vẫn gọi về trung tâm để giữ ca. Bỏ luôn `poll()` giống tắt điện thoại; quá hạn, Kafka giao quầy cho người khác và rebalance.

---

## Trade-offs

```
Auto commit vs Manual commit:
  Auto:   simple, không gắn với lúc business processing hoàn tất → có thể mất hoặc lặp
  Manual: control, at-least-once with intentional commit point
  → Production side effect quan trọng: thường dùng manual commit hoặc framework ack phù hợp

max.poll.records:
  High:  better throughput per poll, but longer processing time
  Low:   quay lại poll sớm hơn, giảm risk vượt max.poll.interval.ms
  → Tune theo thời gian xử lý worst-case của cả batch, không chỉ average

Session timeout:
  Low (10-30s):  detect dead consumers fast, frequent false rebalances
  High (45-60s): tolerate GC pauses, slower failover
  → Với consumer protocol mới, broker quản lý session timeout

Consumer lag:
  0 lag:        committed/current offset đã bắt kịp log end theo metric đang dùng
  Growing lag:  consumer slower than producer (scale out consumers, optimize processing)

Consumer group size:
  > partitions: some consumers idle (wasted resources)
  < partitions: each consumer handles multiple partitions (OK, just fewer consumers)
  = partitions: parallelism tối đa của group cho topic đó, chưa chắc tối ưu chi phí
```

Lag thường là chênh lệch giữa log-end offset và committed offset, nên commit thưa có thể làm lag nhìn cao dù app đã xử lý. Ngược lại, commit quá sớm làm lag nhìn đẹp nhưng dữ liệu có thể chưa hoàn tất. Cần theo dõi cả lag, processing latency, error/retry rate và tốc độ tăng lag.

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

        Map<TopicPartition, OffsetAndMetadata> processedOffsets = new HashMap<>();
        try {
            while (running.get()) {
                try {
                    ConsumerRecords<K, V> records = consumer.poll(Duration.ofMillis(200));

                    for (ConsumerRecord<K, V> record : records) {
                        processWithRetry(record);
                        // Chỉ tiến offset sau khi process hoặc gửi DLT đã được xác nhận.
                        processedOffsets.put(
                            new TopicPartition(record.topic(), record.partition()),
                            new OffsetAndMetadata(record.offset() + 1)
                        );
                    }
                    if (!processedOffsets.isEmpty()) {
                        consumer.commitAsync(new HashMap<>(processedOffsets), (offsets, error) -> {
                            if (error != null) log.error("Commit failed for {}", offsets, error);
                        });
                    }

                } catch (WakeupException e) {
                    if (!running.get()) break;
                    throw e;
                } catch (KafkaException e) {
                    log.error("Consumer error; stop without committing current position", e);
                    running.set(false); // không tiếp tục poll rồi vô tình commit qua record lỗi
                    throw e;
                }
            }
        } finally {
            try {
                if (!processedOffsets.isEmpty()) {
                    consumer.commitSync(processedOffsets);
                }
            } catch (KafkaException e) {
                log.warn("Final offset commit failed; records may be delivered again", e);
            } finally {
                consumer.close(Duration.ofSeconds(10));
            }
        }
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
                    return;
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
            .add("original-topic", record.topic().getBytes(StandardCharsets.UTF_8))
            .add("original-partition", String.valueOf(record.partition()).getBytes(StandardCharsets.UTF_8))
            .add("original-offset", String.valueOf(record.offset()).getBytes(StandardCharsets.UTF_8))
            .add("error-message", String.valueOf(cause.getMessage()).getBytes(StandardCharsets.UTF_8));

        try {
            dlqProducer.send(new ProducerRecord<>(dlqTopic, null, record.key(), record.value(), headers)).get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new KafkaException("Interrupted while writing DLT", e);
        } catch (ExecutionException e) {
            throw new KafkaException("DLT publish failed", e.getCause());
        }
        log.error("Sent to DLQ: {}-{}-{}", record.topic(), record.partition(), record.offset());
    }
}
```

Retry và backoff chạy trên poll thread trong ví dụ này, nên tổng thời gian của một batch phải nằm dưới `max.poll.interval.ms`; workload retry dài nên tách worker pool, `pause()` partition và vẫn gọi `poll()`. **Poison message** *(bản ghi luôn lỗi)* không được retry vô hạn: sau số lần giới hạn, gửi **DLT/DLQ** *(dead-letter topic/queue — nơi giữ bản ghi lỗi)* và chỉ commit offset sau khi producer nhận được acknowledgement.

> 💡 **Giải thích dễ hiểu:**
> Một kiện hàng hỏng không nên chặn cả dây chuyền mãi. DLT là khu vực cách ly để nhân viên xử lý sau; nhưng chỉ được xóa dấu “còn phải giao” sau khi kiện đã thật sự vào khu cách ly, không phải ngay lúc vừa bấm nút gửi.

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
> [storage.md](../internals/storage.md): Log segments, log compaction, retention policies (time/size/compaction), tiered storage, index files, consumer offset storage (`__consumer_offsets`)
>
> Tài liệu API nên đối chiếu: [KafkaConsumer](https://kafka.apache.org/41/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html), [Consumer Configs](https://kafka.apache.org/41/configuration/consumer-configs/) và [ConsumerRebalanceListener](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/ConsumerRebalanceListener.html).

---

*Cập nhật lần cuối: 2026-07-22*
