# Spring Boot Messaging *(nhắn tin bất đồng bộ)* – Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Production – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)

---

## What – Messaging trong Spring Boot là gì?

Messaging là cách producer *(bên phát thông điệp)* gửi event/command qua broker *(hệ thống trung gian)* để consumer *(bên nhận)* xử lý độc lập. Spring Boot auto-configure client và listener container *(bộ máy nhận message và gọi handler)* cho Spring Kafka/RabbitMQ; Spring Framework còn có application event *(sự kiện nội bộ ứng dụng)* để giao tiếp bên trong một process.

Application event không phải message broker: mặc định nó chạy đồng bộ, không có durable storage *(lưu bền vững)*, consumer group hay replay. Kafka phù hợp log sự kiện có partition/replay; RabbitMQ phù hợp queue, routing và request/reply; lựa chọn còn phụ thuộc ordering, retention, throughput và failure model.

> 💡 **Giải thích dễ hiểu — ba loại đường chuyển thư:**
> Application event là chuyển giấy giữa các phòng trong cùng tòa nhà; RabbitMQ là bưu cục định tuyến kiện tới quầy; Kafka là cuộn nhật ký nhiều đội có thể đọc lại. Dùng nhầm loại đường sẽ tạo kỳ vọng sai về độ bền và giao nhận.

## Why – Tại sao cần messaging?

- Tách vòng đời producer/consumer và hấp thụ tải đột biến.
- Cho phép retry, fan-out *(một sự kiện tới nhiều nhóm nhận)* và scale consumer độc lập.
- Lưu dấu vết/replay với Kafka hoặc định tuyến queue linh hoạt với AMQP.
- Hỗ trợ Transactional Outbox *(ghi event cùng transaction dữ liệu)* và Saga *(chuỗi giao dịch cục bộ có hành động bù)* khi một nghiệp vụ trải qua nhiều service.

Messaging đổi coupling đồng bộ thành các bài toán mới: duplicate, ordering cục bộ, schema evolution, eventual consistency *(nhất quán cuối cùng)* và observability. Vì vậy delivery guarantee phải được thiết kế end-to-end, không chỉ bật một property client.

## Components – Bản đồ cơ chế

| Thành phần | Vai trò |
|---|---|
| `KafkaTemplate` / `RabbitTemplate` | Publish record/message |
| `@KafkaListener` / `@RabbitListener` | Tạo endpoint nhận message qua listener container |
| Error handler + DLT/DLQ *(topic/queue cách ly message lỗi)* | Retry có giới hạn và cách ly message lỗi |
| Application event | Giao tiếp nội bộ trong một `ApplicationContext` |
| `@TransactionalEventListener` | Gắn listener vào phase của transaction hiện tại |
| Transactional Outbox | Ghi business data và event trong cùng DB transaction |
| Saga | Chuỗi local transaction và hành động bù giữa nhiều service |

## Mục lục
1. [Spring Kafka Deep](#1-spring-kafka-deep)
2. [Spring AMQP Deep](#2-spring-amqp-deep)
3. [@EventListener & @TransactionalEventListener](#3-eventlistener--transactionaleventlistener)
4. [Saga Pattern](#4-saga-pattern)
5. [Outbox Pattern](#5-outbox-pattern)

---

<a id="1-spring-kafka-deep"></a>
## How – 1. Spring Kafka Deep

### 1.1 Dependencies & Config

```xml
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka</artifactId>
</dependency>
```

```yaml
spring:
  kafka:
    bootstrap-servers: localhost:9092
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      acks: all                  # leader + all ISR acks
      retries: 3
      properties:
        enable.idempotence: true        # chống duplicate do producer retry; chưa phải EOS pipeline
        max.in.flight.requests.per.connection: 5
        delivery.timeout.ms: 120000
        linger.ms: 5                    # batch small messages
        batch.size: 65536               # 64KB batch
        compression.type: snappy
    consumer:
      group-id: my-service
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      auto-offset-reset: earliest
      enable-auto-commit: false        # container/ack mode quản lý offset
      properties:
        spring.json.trusted.packages: "org.example.events"
        max.poll.records: 100
        max.poll.interval.ms: 300000
        session.timeout.ms: 30000
        fetch.min.bytes: 1024
        fetch.max.wait.ms: 500
    listener:
      ack-mode: MANUAL_IMMEDIATE       # commit after processing
      concurrency: 3                   # 3 consumer threads
      type: SINGLE                     # record listener mặc định
```

`acks=all` và idempotence *(chống ghi lặp do retry của producer)* tăng độ bền của lần publish, nhưng không tạo exactly-once cho side effect database/email. Kafka EOS *(Exactly-Once Semantics — xử lý đúng một lần trong Kafka)* cần transaction cho chuỗi consume–process–produce và consumer downstream đọc `read_committed`.

`MANUAL_IMMEDIATE` commit khi gọi `acknowledge()` trên consumer thread; ack sai chỗ có thể bỏ qua record lỗi. `concurrency=3` chỉ tạo tối đa ba consumer thread hữu ích khi topic/group có đủ partition.

> 💡 **Giải thích dễ hiểu — idempotent producer là bưu cục chống dán cùng tem hai lần:**
> Nó xử lý việc xe giao lại cùng kiện do mất xác nhận. Nếu người nhận đã trừ tiền rồi lại nhận kiện từ một lần xử lý khác, bưu cục không thể tự hoàn tác database; consumer vẫn cần idempotency.

### 1.2 Producer

```java
@Component
public class OrderEventPublisher {

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;

    // Simple send
    public CompletableFuture<SendResult<String, Object>> sendOrderCreated(OrderCreatedEvent event) {
        return kafkaTemplate.send("orders", event.getOrderId().toString(), event);
    }

    // Send with callback
    public CompletableFuture<SendResult<String, Object>> sendWithCallback(
            String topic, String key, Object payload) {

        return kafkaTemplate.send(topic, key, payload)
            .whenComplete((result, ex) -> {
                if (ex != null) {
                    log.error("Failed to send message to {}: {}", topic, ex.getMessage());
                    // retry or dead-letter
                } else {
                    RecordMetadata metadata = result.getRecordMetadata();
                    log.info("Sent to {}:{} offset={}",
                        metadata.topic(), metadata.partition(), metadata.offset());
                }
            });
    }

    // Send with headers
    public void sendWithHeaders(OrderEvent event) {
        ProducerRecord<String, Object> record = new ProducerRecord<>(
            "orders", null, event.getOrderId().toString(), event,
            new RecordHeaders()
                .add("eventType", event.getClass().getSimpleName().getBytes())
                .add("correlationId", UUID.randomUUID().toString().getBytes())
        );
        kafkaTemplate.send(record);
    }

    // Kafka transaction: atomic across Kafka records/offsets, not with an arbitrary DB
    @Transactional("kafkaTransactionManager")
    public void sendTransactional(List<OrderEvent> events) {
        events.forEach(e -> kafkaTemplate.send("orders", e.getOrderId().toString(), e));
    }
}
```

`KafkaTemplate.send()` bất đồng bộ; bỏ qua future có thể làm ứng dụng tưởng đã gửi dù broker trả lỗi sau đó. Kafka transaction cần producer transaction-id prefix/transaction manager được cấu hình và chỉ atomic trong tài nguyên Kafka; để phối hợp DB + broker, dùng Outbox hoặc chiến lược transaction được phân tích rõ failure window.

### 1.3 Consumer

```java
@Component
@Slf4j
public class OrderEventConsumer {

    // Single record
    @KafkaListener(topics = "orders", groupId = "order-processor")
    public void handleOrderCreated(
            @Payload OrderCreatedEvent event,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            Acknowledgment ack) {

        try {
            processOrder(event);
            ack.acknowledge();
        } catch (RetryableException e) {
            // Let DefaultErrorHandler apply retry/backoff.
            throw e;
        } catch (Exception e) {
            log.error("Failed to process order {}", event.getOrderId(), e);
            // Do NOT ack and swallow if you expect the error handler/DLT to run.
            throw e instanceof RuntimeException re ? re : new RuntimeException(e);
        }
    }

    // Batch consumer
    @KafkaListener(topics = "orders", groupId = "order-batch",
                   batch = "true")
    public void handleBatch(
            List<ConsumerRecord<String, OrderCreatedEvent>> records,
            Acknowledgment ack) {

        log.info("Processing batch of {}", records.size());
        List<OrderCreatedEvent> events = records.stream()
            .map(ConsumerRecord::value)
            .collect(Collectors.toList());

        orderService.processBatch(events);
        ack.acknowledge(); // commit after entire batch
    }

    // Multiple topics / regex
    @KafkaListener(topicPattern = "order-.*")
    public void handleAllOrderTopics(ConsumerRecord<String, Object> record) { ... }

    // Specific partitions
    @KafkaListener(topicPartitions = {
        @TopicPartition(topic = "orders", partitions = {"0", "1"}),
        @TopicPartition(topic = "orders-priority", partitionOffsets =
            @PartitionOffset(partition = "0", initialOffset = "0"))
    })
    public void handleSpecificPartitions(OrderCreatedEvent event) { ... }
}
```

Listener chỉ nên ack sau khi business side effect đã thành công hoặc có idempotency/outbox bảo vệ. Nếu catch rồi `ack` và không throw, container coi record đã xử lý nên `DefaultErrorHandler` không thể publish DLT. `batch = "true"` ghi đè chế độ record của factory cho endpoint này. Batch listener cần chỉ ra record lỗi bằng `BatchListenerFailedException` nếu muốn recover từng record; nếu không, framework có thể retry cả batch.

> 💡 **Giải thích dễ hiểu — ack là ký “đã nhận xong”:**
> Ký vào phiếu rồi mới báo kiện hỏng khiến bưu cục bỏ hồ sơ khỏi hàng chờ và quầy DLT không bao giờ thấy nó. Hãy để error handler quyết định retry/cách ly, hoặc chỉ ký sau khi công việc đã hoàn tất an toàn.

### 1.4 Error Handling & Dead Letter Topic

```java
@Configuration
public class KafkaConsumerConfig {

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object> kafkaListenerContainerFactory(
            ConsumerFactory<String, Object> consumerFactory,
            DefaultErrorHandler errorHandler) {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory);
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL_IMMEDIATE);
        factory.setConcurrency(3);

        factory.setCommonErrorHandler(errorHandler);

        return factory;
    }

    // Exponential backoff retry
    @Bean
    public DefaultErrorHandler errorHandler(KafkaTemplate<String, Object> kafkaTemplate) {
        ExponentialBackOffWithMaxRetries backOff = new ExponentialBackOffWithMaxRetries(5);
        backOff.setInitialInterval(500L);
        backOff.setMultiplier(2.0);
        backOff.setMaxInterval(30_000L);

        DefaultErrorHandler handler = new DefaultErrorHandler(
            new DeadLetterPublishingRecoverer(kafkaTemplate,
                (rec, ex) -> new TopicPartition(rec.topic() + ".DLT", rec.partition())),
            backOff);

        // Skip specific exceptions (don't retry)
        handler.addNotRetryableExceptions(
            InvalidMessageException.class,
            DeserializationException.class
        );

        return handler;
    }
}

// DLT Consumer
@Component
public class DltConsumer {

    @KafkaListener(topics = "orders.DLT")
    public void handleDlt(
            ConsumerRecord<String, Object> record,
            @Header(value = KafkaHeaders.DLT_EXCEPTION_CAUSE_FQCN, required = false)
            String exceptionClass,
            @Header(value = KafkaHeaders.DLT_EXCEPTION_MESSAGE, required = false)
            String exceptionMessage) {

        log.error("DLT message: topic={}, partition={}, offset={}, cause={}",
            record.topic(), record.partition(), record.offset(), exceptionMessage);

        // Store in DB for manual review / alerting
        deadLetterService.store(record, exceptionClass, exceptionMessage);
    }
}
```

`ExponentialBackOffWithMaxRetries(5)` nghĩa là tối đa năm lần retry ngoài lần xử lý đầu. DLT resolver giữ nguyên partition, nên topic `.DLT` phải có ít nhất số partition tương ứng. Nếu publish DLT thất bại, recoverer phải fail để record còn được retry; không coi log DLT là thành công.

Deserialization có thể lỗi trước khi listener nhận record. Dùng `ErrorHandlingDeserializer`/serializer phù hợp và kiểm tra header nếu muốn error handler đưa raw payload sang DLT. Không để retry dài bằng cách sleep vượt `max.poll.interval.ms`; cân nhắc container-pausing backoff hoặc non-blocking retry topic.

### 1.5 Consumer Group Rebalancing & Partitioning

```java
// Custom partitioner
public class OrderPartitioner implements Partitioner {

    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        int numPartitions = cluster.partitionCountForTopic(topic);
        if (key instanceof String orderId) {
            // Same orderId → same partition while partition count/algorithm stay unchanged
            return Math.floorMod(orderId.hashCode(), numPartitions);
        }
        return 0;
    }

    @Override
    public void close() {}
    @Override
    public void configure(Map<String, ?> configs) {}
}

// Consumer group offset management
@Component
public class KafkaOffsetManager {

    @Autowired
    private KafkaAdmin kafkaAdmin;

    public void seekToBeginning(String groupId, String topic) {
        try (AdminClient admin = AdminClient.create(kafkaAdmin.getConfigurationProperties())) {
            ListConsumerGroupOffsetsResult offsets = admin.listConsumerGroupOffsets(groupId);
            // Manage offset programmatically
        }
    }
}
```

Ordering chỉ được đảm bảo trong một partition. Tăng partition hoặc đổi partitioner có thể chuyển cùng key sang partition mới, làm lịch sử cũ/mới không còn một total order. Method `seekToBeginning` minh họa phía trên chưa thực sự seek listener đang chạy; sửa offset bằng Admin API cần quy trình dừng/điều phối consumer group để tránh race.

### 1.6 Kafka Streams (within Spring Boot)

```java
@Configuration
@EnableKafkaStreams
public class KafkaStreamsConfig {

    @Bean(name = KafkaStreamsDefaultConfiguration.DEFAULT_STREAMS_CONFIG_BEAN_NAME)
    public KafkaStreamsConfiguration streamsConfig() {
        return new KafkaStreamsConfiguration(Map.of(
            StreamsConfig.APPLICATION_ID_CONFIG, "order-aggregator",
            StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092",
            StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass(),
            StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, Serdes.String().getClass()
        ));
    }
}

@Component
public class OrderAggregationTopology {

    @Autowired
    void buildPipeline(StreamsBuilder sb) {
        KStream<String, OrderEvent> orders = sb.stream("orders",
            Consumed.with(Serdes.String(), new JsonSerde<>(OrderEvent.class)));

        // Aggregate order count per customer per minute
        orders
            .groupBy((key, event) -> event.getCustomerId().toString(),
                Grouped.with(Serdes.String(), new JsonSerde<>(OrderEvent.class)))
            .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(1)))
            .count(Materialized.as("order-count-store"))
            .toStream()
            .to("order-counts", Produced.with(
                WindowedSerdes.timeWindowedSerdeFrom(String.class, 60_000),
                Serdes.Long()
            ));
    }
}
```

Kafka Streams giữ state local và changelog trong Kafka. `TimeWindows.ofSizeWithNoGrace` không nhận record đến muộn sau khi window đóng; chỉ dùng khi nghiệp vụ chấp nhận late event bị loại, nếu không hãy cấu hình grace và theo dõi state-store/changelog lag.

> 💡 **Giải thích dễ hiểu — partition là làn đường, key là biển số xe:**
> Cùng biển số đi cùng làn nên giữ thứ tự. Mở thêm làn hoặc đổi cách phân làn giữa chuyến có thể khiến xe cũ và xe mới của cùng khách nằm ở hai hàng khác nhau.

---

<a id="2-spring-amqp-deep"></a>
## How – 2. Spring AMQP Deep

**AMQP (Advanced Message Queuing Protocol)** *(giao thức hàng đợi thông điệp)* trong phần này dùng RabbitMQ. Exchange *(bộ định tuyến)* nhận message, routing key chọn binding *(quy tắc nối)* và queue giữ message cho competing consumer.

### 2.1 Full Configuration

```yaml
spring:
  rabbitmq:
    publisher-confirm-type: correlated
    publisher-returns: true
```

```java
@Configuration
public class RabbitConfig {

    @Bean
    public TopicExchange orderExchange() {
        return ExchangeBuilder.topicExchange("order.exchange").durable(true).build();
    }

    @Bean
    public TopicExchange dlxExchange() {
        return ExchangeBuilder.topicExchange("order.dlx").durable(true).build();
    }

    @Bean
    public Queue orderQueue() {
        return QueueBuilder.durable("order.queue")
            .withArgument("x-dead-letter-exchange", "order.dlx")
            .withArgument("x-dead-letter-routing-key", "order.dead")
            .withArgument("x-message-ttl", 300_000)  // 5 minutes
            .quorum()  // Quorum queue
            .build();
    }

    @Bean
    public Queue deadLetterQueue() {
        return QueueBuilder.durable("order.dlq").build();
    }

    @Bean
    public Binding orderBinding() {
        return BindingBuilder.bind(orderQueue())
            .to(orderExchange())
            .with("order.#");
    }

    @Bean
    public Binding dlqBinding() {
        return BindingBuilder.bind(deadLetterQueue())
            .to(dlxExchange())
            .with("order.dead");
    }

    // Message converter — JSON
    @Bean
    public MessageConverter jsonMessageConverter() {
        ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
        return new Jackson2JsonMessageConverter(mapper);
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory cf) {
        RabbitTemplate template = new RabbitTemplate(cf);
        template.setMessageConverter(jsonMessageConverter());
        template.setConfirmCallback((correlationData, ack, cause) -> {
            if (!ack) {
                log.error("Message nacked: {}, cause={}",
                    correlationData != null ? correlationData.getId() : "unknown", cause);
            }
        });
        template.setReturnsCallback(returned -> {
            log.error("Message returned: replyCode={}, replyText={}, exchange={}, routingKey={}",
                returned.getReplyCode(), returned.getReplyText(),
                returned.getExchange(), returned.getRoutingKey());
        });
        template.setMandatory(true); // trigger returns callback
        return template;
    }

    @Bean
    public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
            ConnectionFactory cf) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(cf);
        factory.setMessageConverter(jsonMessageConverter());
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setPrefetchCount(10);
        factory.setConcurrentConsumers(3);
        factory.setMaxConcurrentConsumers(10);
        factory.setDefaultRequeueRejected(false);  // don't requeue on rejection
        return factory;
    }
}
```

Để callback confirm/return hoạt động, connection factory phải bật publisher confirm kiểu `correlated` và publisher returns (ví dụ các property Spring Boot tương ứng). Confirm chỉ chứng minh broker nhận publish ở mức exchange; return báo message mandatory không route được. Cả hai không chứng minh consumer đã xử lý.

TTL `x-message-ttl` trên `order.queue` làm message quá hạn bị dead-letter sau năm phút; nó không tự tạo lịch retry. Tách retry queue/delay policy khỏi main queue nếu không muốn message hợp lệ hết hạn chỉ vì backlog.

> 💡 **Giải thích dễ hiểu — RabbitMQ là bưu cục có quầy phân loại:**
> Confirm là dấu “bưu cục đã nhận kiện”, return là “không tìm thấy tuyến giao”. Chưa dấu nào chứng minh người nhận cuối đã mở và xử lý kiện.

### 2.2 Consumer Patterns

```java
@Component
@Slf4j
@RequiredArgsConstructor
public class OrderConsumer {

    private final RabbitTemplate rabbitTemplate;

    // Basic with manual ack
    @RabbitListener(queues = "order.queue")
    public void handleOrder(
            @Payload OrderCreatedEvent event,
            @Headers Map<String, Object> headers,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long tag) throws IOException {

        try {
            orderService.process(event);
            channel.basicAck(tag, false);
        } catch (RetryableException e) {
            channel.basicNack(tag, false, true);  // requeue
        } catch (Exception e) {
            log.error("Processing failed for order {}", event.getOrderId(), e);
            channel.basicNack(tag, false, false); // send to DLX
        }
    }

    // Retry with x-retry-count header
    @RabbitListener(queues = "order.queue")
    public void handleWithRetry(
            @Payload OrderCreatedEvent event,
            @Header(value = "x-retry-count", defaultValue = "0") int retryCount,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long tag) throws Exception {

        try {
            orderService.process(event);
            channel.basicAck(tag, false);
        } catch (Exception e) {
            if (retryCount < 3) {
                CorrelationData cd = new CorrelationData(UUID.randomUUID().toString());
                rabbitTemplate.convertAndSend("order.exchange", "order.created",
                    event, msg -> {
                        msg.getMessageProperties().getHeaders()
                           .put("x-retry-count", retryCount + 1);
                        return msg;
                    }, cd);
                CorrelationData.Confirm confirm =
                    cd.getFuture().get(5, TimeUnit.SECONDS);
                if (!confirm.isAck() || cd.getReturned() != null) {
                    throw new AmqpException("Retry publish was nacked or returned");
                }
            } else {
                CorrelationData cd = new CorrelationData(UUID.randomUUID().toString());
                rabbitTemplate.convertAndSend("order.dlx", "order.dead", event, cd);
                CorrelationData.Confirm confirm =
                    cd.getFuture().get(5, TimeUnit.SECONDS);
                if (!confirm.isAck() || cd.getReturned() != null) {
                    throw new AmqpException("DLQ publish was nacked or returned");
                }
            }
            channel.basicAck(tag, false); // ack original only after replacement is confirmed
        }
    }

    // Batch consumer
    @RabbitListener(queues = "order.queue",
                    containerFactory = "batchContainerFactory")
    public void handleBatch(
            List<OrderCreatedEvent> events,
            Channel channel,
            @Header(AmqpHeaders.DELIVERY_TAG) long tag) throws IOException {

        log.info("Processing batch of {}", events.size());
        events.forEach(orderService::process);
        channel.basicAck(tag, true); // ack all in batch
    }

    // Route PRIORITY messages to a dedicated queue through exchange/binding rules.
    // @RabbitListener does not have an EventListener-style condition attribute.
    @RabbitListener(queues = "order.priority.queue")
    public void handlePriorityOrder(OrderCreatedEvent event) { ... }
}
```

Các listener trên cùng `order.queue` trong ví dụ là các phương án thay thế, không phải fan-out: nếu bật đồng thời, chúng cạnh tranh và mỗi message chỉ tới một consumer. Muốn nhiều nghiệp vụ cùng nhận, tạo queue riêng và bind cùng exchange.

`basicNack(..., requeue=true)` không có giới hạn có thể tạo poison-message hot loop. Republish retry phải confirm message thay thế trước khi ack bản gốc; nếu cần quy trình hoàn chỉnh, dùng Spring Retry/container advice hoặc retry queue + DLX thay vì tự ghép rời rạc.

Trong batch listener, `basicAck(tag, true)` xác nhận mọi delivery tag chưa ack đến `tag` trên cùng channel, không chỉ những phần tử nhìn thấy trong `List`. Chỉ dùng khi container bảo đảm batch/channel boundary phù hợp; nếu một phần tử lỗi, cần xác định rõ cả batch được retry, tách record lỗi hay để container quản lý ack.

### 2.3 Publisher Confirms Deep

```java
@Service
public class OrderPublisher {

    @Autowired
    private RabbitTemplate rabbitTemplate;

    // Synchronous confirm (blocks)
    public boolean sendWithConfirm(String exchange, String routingKey, Object payload) {
        CorrelationData correlationData = new CorrelationData(UUID.randomUUID().toString());
        rabbitTemplate.convertAndSend(exchange, routingKey, payload, correlationData);

        try {
            CorrelationData.Confirm confirm = correlationData.getFuture().get(5, TimeUnit.SECONDS);
            return confirm.isAck() && correlationData.getReturned() == null;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("Interrupted while waiting for confirm {}", correlationData.getId(), e);
            return false;
        } catch (ExecutionException | TimeoutException e) {
            log.error("Confirm failed for message {}", correlationData.getId(), e);
            return false;
        }
    }

    // Async confirm
    public void sendAsync(OrderCreatedEvent event) {
        CorrelationData cd = new CorrelationData(event.getOrderId().toString());
        cd.getFuture().whenComplete((confirm, ex) -> {
            if (ex != null) {
                log.error("Confirm failed for {}", event.getOrderId(), ex);
            } else {
                if (confirm.isAck() && cd.getReturned() == null) {
                    log.debug("Message {} confirmed", event.getOrderId());
                } else {
                    log.error("Message {} nacked/returned: {}",
                        event.getOrderId(), confirm.getReason());
                    // retry / store for retry
                }
            }
        });

        rabbitTemplate.convertAndSend("order.exchange", "order.created", event, cd);
    }
}
```

Synchronous `get()` dễ làm nghẽn request/consumer thread; async confirm cần lưu correlation với trạng thái publish để có thể retry sau crash. Ack publisher là xác nhận của broker, không phải exactly-once và không thay thế Outbox cho DB + RabbitMQ.

---

<a id="3-eventlistener--transactionaleventlistener"></a>
## How/Components – 3. `@EventListener` & `@TransactionalEventListener`

### 3.1 Application Events

Application event *(sự kiện nội bộ ứng dụng)* dùng `ApplicationEventPublisher`; POJO/record đều có thể là payload. Mặc định multicaster gọi listener đồng bộ trên thread của publisher, nên exception/latency của listener có thể ảnh hưởng transaction gọi.

```java
// Custom event
public record OrderPlacedEvent(Long orderId, Long customerId, BigDecimal total) {}

// Publisher
@Service
public class OrderService {

    @Autowired
    private ApplicationEventPublisher eventPublisher;

    @Transactional
    public Order placeOrder(CreateOrderRequest req) {
        Order order = orderRepository.save(Order.from(req));

        // Publish event — by default synchronous within same thread
        eventPublisher.publishEvent(new OrderPlacedEvent(
            order.getId(), req.getCustomerId(), order.getTotal()
        ));

        return order;
    }
}
```

Event nên là snapshot bất biến chứa ID/dữ liệu cần thiết, không truyền JPA entity lazy sang async listener. Application event chỉ sống trong process; restart không replay lại event đã mất.

### 3.2 @EventListener Variants

```java
@Component
public class OrderEventHandlers {

    // Basic — runs synchronously in publisher's thread/transaction
    @EventListener
    public void onOrderPlaced(OrderPlacedEvent event) {
        emailService.sendConfirmation(event.customerId(), event.orderId());
    }

    // Async — different thread, no transaction
    @Async
    @EventListener
    public void onOrderPlacedAsync(OrderPlacedEvent event) {
        analyticsService.track("ORDER_PLACED", event);
    }

    // Conditional
    @EventListener(condition = "#event.total > 1000")
    public void onHighValueOrder(OrderPlacedEvent event) {
        notificationService.alertVip(event.customerId());
    }

    // Multiple event types
    @EventListener({OrderPlacedEvent.class, OrderUpdatedEvent.class})
    public void onOrderChange(Object event) {
        cacheService.evict("order-list");
    }

    // Return value → publishes another event
    @EventListener
    public OrderConfirmedEvent processAndConfirm(OrderPlacedEvent event) {
        inventoryService.reserve(event.orderId());
        return new OrderConfirmedEvent(event.orderId());
    }
}
```

Listener đồng bộ trả object sẽ publish object đó thành event tiếp theo. `@Async` cần `@EnableAsync` và executor có giới hạn; async listener không thể publish event tiếp theo bằng return value mà phải gọi `ApplicationEventPublisher`. Return-value publication không được dùng như chuỗi bảo đảm bền vững.

> 💡 **Giải thích dễ hiểu — ApplicationEvent là chuông nội bộ:**
> Chuông giúp các phòng không gọi trực tiếp nhau, nhưng nếu tòa nhà mất điện thì tiếng chuông không được lưu để phát lại. Công việc không được phép mất phải ghi vào Outbox hoặc broker.

### 3.3 @TransactionalEventListener — Key Mechanics

```java
@Component
@Slf4j
public class TransactionalOrderEventHandler {

    // AFTER_COMMIT: fires only if transaction commits successfully
    // Default phase — most common usage
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderCommitted(OrderPlacedEvent event) {
        // DB đã commit, nhưng external calls vẫn có thể fail hoặc mất nếu process crash.
        emailService.sendOrderConfirmation(event.orderId());
        inventoryService.reserveStock(event.orderId());
    }

    // AFTER_ROLLBACK: audit / compensate
    @TransactionalEventListener(phase = TransactionPhase.AFTER_ROLLBACK)
    public void onOrderRollback(OrderPlacedEvent event) {
        auditService.logRollback(event.orderId());
    }

    // BEFORE_COMMIT: still in transaction — can do DB ops
    @TransactionalEventListener(phase = TransactionPhase.BEFORE_COMMIT)
    public void beforeCommit(OrderPlacedEvent event) {
        // This runs inside original transaction
        auditLogRepository.save(new AuditLog("ORDER_CREATED", event.orderId()));
    }

    // AFTER_COMPLETION: after commit OR rollback (cleanup)
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMPLETION)
    public void cleanup(OrderPlacedEvent event) {
        cache.evict("pending-orders");
    }
}
```

Nếu không có transaction đang chạy, `@TransactionalEventListener` mặc định không được gọi; chỉ bật `fallbackExecution=true` khi chấp nhận semantics đó. Sau `AFTER_COMMIT`, resource transaction có thể còn accessible nhưng write mới sẽ không tự commit vào transaction đã kết thúc; dùng `REQUIRES_NEW` khi cần DB transaction mới.

`AFTER_COMMIT` ngăn side effect chạy trước DB commit nhưng không đảm bảo delivery: crash giữa DB commit và email/broker publish vẫn làm mất việc. Outbox hoặc event publication registry bền vững giải quyết failure window này. Với reactive transaction, context nằm trong Reactor context và phải được truyền theo cơ chế Spring hỗ trợ.

**Critical: @TransactionalEventListener with @Async:**

```java
// AFTER_COMMIT: mở transaction mới nếu async handler cần DB write

@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
@Async
@Transactional(propagation = Propagation.REQUIRES_NEW)  // open new tx
public void handleAfterCommitWithDb(OrderPlacedEvent event) {
    // Now we can safely query/update DB in new transaction
    Order order = orderRepository.findById(event.orderId()).orElseThrow();
    order.setEmailSent(true);
    orderRepository.save(order);
}
```

Kết hợp `@Async` và `REQUIRES_NEW` tạo transaction ở thread executor, nhưng task vẫn nằm trong memory và có thể mất khi process chết. Tách handler sang bean riêng giúp proxy boundary rõ ràng; không coi mẫu này là Outbox.

> 💡 **Giải thích dễ hiểu — AFTER_COMMIT là đợi hóa đơn đóng dấu rồi mới gọi điện:**
> Nó tránh gọi trước khi đơn hàng chắc chắn tồn tại. Nhưng điện thoại có thể mất sóng ngay sau khi đóng dấu; muốn ca sau gọi tiếp phải có phiếu Outbox lưu trong sổ.

### 3.4 Ordered Event Handlers

```java
@Component
@Order(1)
public class FirstHandler {
    @EventListener
    public void handle(OrderPlacedEvent e) { /* runs first */ }
}

@Component
@Order(2)
public class SecondHandler {
    @EventListener
    public void handle(OrderPlacedEvent e) { /* runs second */ }
}
```

`@Order` chỉ hữu ích cho listener đồng bộ trong cùng multicaster; async execution không cung cấp thứ tự hoàn tất. Nếu correctness phụ thuộc handler A luôn xong trước B, hãy mô hình hóa một workflow rõ ràng thay vì dựa vào annotation order.

---

<a id="4-saga-pattern"></a>
## How/Components – 4. Saga Pattern *(chuỗi giao dịch phân tán có hành động bù)*

### 4.1 Choreography Saga

```
Order Service → publishes OrderCreated
  ↓
Payment Service → listens, processes payment → publishes PaymentProcessed (or PaymentFailed)
  ↓
Inventory Service → listens PaymentProcessed → reserves stock → publishes StockReserved (or StockFailed)
  ↓
Shipping Service → listens StockReserved → creates shipment → publishes ShipmentCreated
```

```java
// Order Service
@Service
public class OrderService {

    @Transactional
    public Order createOrder(CreateOrderRequest req) {
        Order order = Order.builder()
            .customerId(req.getCustomerId())
            .items(req.getItems())
            .status(OrderStatus.PENDING)
            .build();
        order = orderRepository.save(order);

        // Cross-service event must be externalized durably; local ApplicationEvent is insufficient.
        outboxService.saveEvent("Order", order.getId().toString(), "order.created.v1",
            new OrderCreatedEvent(
                order.getId(), req.getCustomerId(), order.getTotal(), req.getItems()
            ));
        return order;
    }

    // PaymentFailed comes from Kafka, not from local ApplicationEventPublisher.
    @KafkaListener(topics = "payment-events", groupId = "order-saga")
    @Transactional
    public void onPaymentFailed(PaymentFailedEvent event) {
        orderRepository.findById(event.getOrderId()).ifPresent(order -> {
            order.setStatus(OrderStatus.PAYMENT_FAILED);
            orderRepository.save(order);
        });
    }
}

// Payment Service
@Component
public class PaymentSagaHandler {

    @KafkaListener(topics = "order-events", groupId = "payment-saga")
    public void handleOrderCreated(OrderCreatedEvent event) {
        try {
            Payment payment = paymentService.charge(event.customerId(), event.total());
            kafkaTemplate.send("payment-events",
                new PaymentProcessedEvent(event.orderId(), payment.getId()));
        } catch (PaymentException e) {
            kafkaTemplate.send("payment-events",
                new PaymentFailedEvent(event.orderId(), e.getMessage()));
        }
    }

    // Compensating
    @KafkaListener(topics = "inventory-events", groupId = "payment-saga")
    public void handleStockFailed(StockFailedEvent event) {
        paymentService.refund(event.getOrderId());
        kafkaTemplate.send("payment-events", new PaymentRefundedEvent(event.getOrderId()));
    }
}
```

Choreography *(các service tự phản ứng với event)* giảm điểm điều phối trung tâm nhưng luồng khó quan sát khi nhiều bước. Mỗi handler phải idempotent theo `eventId`/business operation, chịu duplicate và không giả định event từ topic khác có global order. Payment charge/refund cần idempotency key để retry không thu/hoàn tiền hai lần.

Trong ví dụ Payment Service, `charge()` và `kafkaTemplate.send()` vẫn là dual write. Production nên lưu kết quả payment + Outbox trong cùng local transaction hoặc có state machine/reconciliation; chỉ gọi `send()` không đảm bảo event đã được broker nhận.

> 💡 **Giải thích dễ hiểu — Saga là chuyến tour nhiều nhà cung cấp:**
> Không có nút rollback đưa mọi thứ quay về quá khứ. Nếu khách sạn thất bại sau khi đã mua vé, hệ thống phải phát lệnh hoàn vé; lệnh bù cũng có thể lỗi và cần mã để thử lại an toàn.

### 4.2 Orchestration Saga (Saga Orchestrator)

```java
// Saga state
@Entity
public class OrderSaga {
    @Id
    private Long orderId;

    @Enumerated(EnumType.STRING)
    private SagaState state;

    private String paymentId;
    private String reservationId;
    private int retryCount;

    public enum SagaState {
        STARTED,
        PAYMENT_PENDING, PAYMENT_DONE, PAYMENT_FAILED,
        STOCK_PENDING, STOCK_RESERVED, STOCK_FAILED,
        SHIPPING_PENDING, COMPLETED,
        COMPENSATING, FAILED
    }
}

// Saga orchestrator
@Service
@Slf4j
public class OrderSagaOrchestrator {

    @Autowired private OrderSagaRepository sagaRepo;
    @Autowired private KafkaTemplate<String, Object> kafka;

    @Transactional
    public void startSaga(Order order) {
        OrderSaga saga = new OrderSaga(order.getId(), SagaState.STARTED);
        sagaRepo.save(saga);

        // Step 1: Request payment
        kafka.send("payment-commands", new ProcessPaymentCommand(
            order.getId(), order.getCustomerId(), order.getTotal()
        ));
        saga.setState(SagaState.PAYMENT_PENDING);
        sagaRepo.save(saga);
    }

    @KafkaListener(topics = "saga-replies", groupId = "saga-orchestrator")
    @Transactional
    public void handleReply(SagaReply reply) {
        OrderSaga saga = sagaRepo.findById(reply.getOrderId()).orElseThrow();

        switch (saga.getState()) {
            case PAYMENT_PENDING -> handlePaymentReply(saga, reply);
            case STOCK_PENDING -> handleStockReply(saga, reply);
            case SHIPPING_PENDING -> handleShippingReply(saga, reply);
            default -> log.warn("Unexpected reply in state {}", saga.getState());
        }
    }

    private void handlePaymentReply(OrderSaga saga, SagaReply reply) {
        if (reply.isSuccess()) {
            saga.setPaymentId(reply.getResourceId());
            saga.setState(SagaState.STOCK_PENDING);
            sagaRepo.save(saga);

            // Step 2: Reserve stock
            kafka.send("inventory-commands", new ReserveStockCommand(
                saga.getOrderId(), reply.getItems()
            ));
        } else {
            // Compensate
            saga.setState(SagaState.FAILED);
            sagaRepo.save(saga);
            kafka.send("order-events", new OrderFailedEvent(saga.getOrderId(), "Payment failed"));
        }
    }

    private void handleStockReply(OrderSaga saga, SagaReply reply) {
        if (reply.isSuccess()) {
            saga.setReservationId(reply.getResourceId());
            saga.setState(SagaState.SHIPPING_PENDING);
            sagaRepo.save(saga);

            kafka.send("shipping-commands", new CreateShipmentCommand(saga.getOrderId()));
        } else {
            // Compensate: refund payment
            saga.setState(SagaState.COMPENSATING);
            sagaRepo.save(saga);
            kafka.send("payment-commands", new RefundPaymentCommand(
                saga.getOrderId(), saga.getPaymentId()
            ));
        }
    }

    private void handleShippingReply(OrderSaga saga, SagaReply reply) {
        if (reply.isSuccess()) {
            saga.setState(SagaState.COMPLETED);
            sagaRepo.save(saga);
            kafka.send("order-events", new OrderCompletedEvent(saga.getOrderId()));
        } else {
            // Compensate: refund + release stock
            saga.setState(SagaState.COMPENSATING);
            sagaRepo.save(saga);
            kafka.send("inventory-commands", new ReleaseStockCommand(saga.getReservationId()));
            kafka.send("payment-commands", new RefundPaymentCommand(saga.getOrderId(), saga.getPaymentId()));
        }
    }
}
```

Orchestration *(một bộ điều phối giữ state Saga)* dễ nhìn timeout/trạng thái hơn nhưng orchestrator trở thành thành phần quan trọng phải scale và phục hồi. Các cặp `sagaRepo.save()` + `kafka.send()` trong snippet chỉ là mô hình khái niệm và vẫn có dual-write window; production nên ghi command vào Outbox cùng state transition.

Orchestrator cần optimistic locking/version, event ID, kiểm tra transition hợp lệ, timeout cho bước không trả lời và inbox/dedup. Reply trùng hoặc đến muộn không được làm Saga đã `COMPLETED` quay ngược về state cũ; compensation thất bại phải có retry/cảnh báo/reconciliation.

---

<a id="5-outbox-pattern"></a>
## How/Components – 5. Transactional Outbox *(hộp thư đi trong cùng DB transaction)*

### 5.1 Problem & Solution

```
Problem: Service updates DB + publishes Kafka/RabbitMQ in same request.
Risk: DB commits but broker publish fails → lost event.
     Or: Broker publishes but DB rolls back → ghost event.

Solution: Transactional Outbox
- Write event to outbox table in SAME transaction as business data
- Background process reads outbox and publishes to broker
- Mark as published only after broker confirms (duplicates vẫn có thể xảy ra)
```

Outbox loại bỏ tình huống business row commit mà không có bản ghi event. Nó cung cấp at-least-once khi relay retry: crash sau broker confirm nhưng trước khi đánh dấu `PUBLISHED` sẽ phát lại event, nên consumer phải idempotent.

> 💡 **Giải thích dễ hiểu — Outbox là sổ phiếu gửi cạnh sổ bán hàng:**
> Đơn hàng và phiếu giao được ghi trong cùng lần đóng sổ nên không quên phiếu. Nhân viên có thể gửi lại nếu mất điện trước khi gạch “đã gửi”; người nhận dùng `eventId` để nhận ra bản trùng.

### 5.2 Outbox Table

```sql
CREATE TABLE outbox_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(100) NOT NULL,
    event_type      VARCHAR(200) NOT NULL,
    event_version   INT          NOT NULL DEFAULT 1,
    payload         JSONB        NOT NULL,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMP,
    status          VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    retry_count     INT          NOT NULL DEFAULT 0,
    error_message   TEXT
);

CREATE INDEX idx_outbox_status_created ON outbox_events(status, created_at)
    WHERE status = 'PENDING';
```

`event_type` nên là contract name ổn định, không phụ thuộc Java FQCN có thể đổi khi refactor. Payload cần schema/version và chính sách chứa PII. Với nhiều publisher instance, cần cơ chế claim/lease hoặc `FOR UPDATE SKIP LOCKED` để tránh cùng chọn một hàng.

### 5.3 Implementation

```java
// Outbox entity
@Entity
@Table(name = "outbox_events")
public class OutboxEvent {
    @Id
    private UUID id = UUID.randomUUID();
    private String aggregateType;
    private String aggregateId;
    private String eventType;
    private int eventVersion = 1;

    @Column(columnDefinition = "jsonb")
    private String payload;

    private LocalDateTime createdAt = LocalDateTime.now();
    private LocalDateTime publishedAt;

    @Enumerated(EnumType.STRING)
    private OutboxStatus status = OutboxStatus.PENDING;

    private int retryCount = 0;
    private String errorMessage;

    public enum OutboxStatus { PENDING, PUBLISHED, FAILED }
}

// Outbox service helper
@Service
public class OutboxService {

    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private OutboxEventRepository outboxRepository;

    public void saveEvent(
            String aggregateType, String aggregateId, String eventType, Object event) {
        try {
            OutboxEvent outbox = new OutboxEvent();
            outbox.setAggregateType(aggregateType);
            outbox.setAggregateId(aggregateId);
            outbox.setEventType(eventType);
            outbox.setPayload(objectMapper.writeValueAsString(event));
            outboxRepository.save(outbox);
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Cannot serialize event", e);
        }
    }
}

// Business service — atomic write
@Service
public class OrderService {

    @Autowired private OrderRepository orderRepository;
    @Autowired private OutboxService outboxService;

    @Transactional  // Both order + outbox in SAME transaction
    public Order placeOrder(CreateOrderRequest req) {
        Order order = orderRepository.save(Order.from(req));

        // Write to outbox in same transaction — atomic
        outboxService.saveEvent("Order", order.getId().toString(), "order.created.v1",
            new OrderCreatedEvent(order.getId(), req.getCustomerId(), order.getTotal()));

        return order;
    }
}

// Outbox publisher — polling approach
@Component
@Slf4j
public class OutboxPublisher {

    @Autowired private OutboxEventRepository outboxRepository;
    @Autowired private KafkaTemplate<String, String> kafkaTemplate;
    @Autowired private ObjectMapper objectMapper;

    @Scheduled(fixedDelay = 1000)  // Poll every 1 second
    @Transactional
    public void publishPendingEvents() {
        List<OutboxEvent> pending = outboxRepository
            .findTop100ByStatusOrderByCreatedAtAsc(OutboxStatus.PENDING);

        for (OutboxEvent event : pending) {
            try {
                String topic = resolveTopicName(event.getEventType());
                ProducerRecord<String, String> record = new ProducerRecord<>(
                    topic, event.getAggregateId(), event.getPayload());
                record.headers()
                    .add("eventId", event.getId().toString().getBytes(StandardCharsets.UTF_8))
                    .add("eventType", event.getEventType().getBytes(StandardCharsets.UTF_8))
                    .add("eventVersion",
                        Integer.toString(event.getEventVersion()).getBytes(StandardCharsets.UTF_8));

                kafkaTemplate.send(record)
                    .get(5, TimeUnit.SECONDS); // sync wait

                event.setStatus(OutboxStatus.PUBLISHED);
                event.setPublishedAt(LocalDateTime.now());
                outboxRepository.save(event);

            } catch (Exception e) {
                log.error("Failed to publish outbox event {}: {}", event.getId(), e.getMessage());
                event.setRetryCount(event.getRetryCount() + 1);
                event.setErrorMessage(e.getMessage());
                if (event.getRetryCount() >= 5) {
                    event.setStatus(OutboxStatus.FAILED);
                }
                outboxRepository.save(event);
            }
        }
    }

    private String resolveTopicName(String eventType) {
        return switch (eventType) {
            case "order.created.v1" -> "order-events";
            default -> throw new IllegalArgumentException("Unknown event type: " + eventType);
        };
    }
}
```

Publisher đang giữ DB transaction trong lúc chờ Kafka tối đa năm giây, làm lock/connection sống lâu. Production thường claim batch ngắn, publish ngoài transaction claim rồi cập nhật kết quả bằng transaction khác, hoặc dùng CDC; mỗi lựa chọn vẫn phải xử lý lease hết hạn, duplicate và ordering.

Failure window quan trọng: broker đã confirm nhưng process chết trước DB commit `PUBLISHED` → record được gửi lại. Vì vậy `event.id` phải đi theo message, consumer dùng inbox/dedup, và cleanup/retention Outbox chỉ xóa sau khoảng replay/audit đã định.

### 5.4 Debezium CDC Approach (Production)

```jsonc
// Better than polling: Debezium reads Postgres WAL (change data capture)
// config/debezium-connector.json
{
  "name": "outbox-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "localhost",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "${file:/opt/secrets/db.properties:password}",
    "database.dbname": "mydb",
    "topic.prefix": "orders-db",
    "slot.name": "orders_outbox_slot",
    "table.include.list": "public.outbox_events",
    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.table.field.event.id": "id",
    "transforms.outbox.table.field.event.key": "aggregate_id",
    "transforms.outbox.table.field.event.type": "event_type",
    "transforms.outbox.table.field.event.payload": "payload",
    "transforms.outbox.route.by.field": "aggregate_type",
    "transforms.outbox.route.topic.replacement": "outbox.event.${routedByValue}",
    "transforms.outbox.table.fields.additional.placement":
      "event_version:header:eventVersion"
  }
}
```

JSON thật không chấp nhận comment `#`; ví dụ là `jsonc` minh họa và secret phải lấy từ secret provider. Debezium CDC *(Change Data Capture — đọc thay đổi từ WAL)* thường at-least-once; restart/recovery có thể phát duplicate. Với EventRouter, table Outbox thường append-only rồi cleanup theo retention thay vì trông chờ cột `published_at` được Debezium cập nhật.

---

## Compare – Messaging Patterns

| Pattern | Delivery | Ordering | Failure handling |
|---------|----------|----------|-----------------|
| Choreography Saga | Eventual | Per-partition | Each service compensates |
| Orchestration Saga | Eventual | State machine kiểm soát transition | Orchestrator phát hành động bù |
| Transactional Outbox (polling) | At-least-once | Chỉ giữ nếu claim/publish được serialize đúng | Retry, lease, dedup, DLQ |
| Outbox + CDC (Debezium) | At-least-once thông thường | Theo partition/key; không global | WAL/slot monitoring, dedup/replay |

| Spring Component | Best for |
|------------------|----------|
| `@EventListener` | Đồng bộ trong process, side effect ngắn |
| `@Async @EventListener` | Việc best-effort trong process, chấp nhận mất khi crash |
| `@TransactionalEventListener` | Gắn xử lý vào phase transaction; không tự durable |
| `@KafkaListener` | Log/replay, throughput cao, ordering theo partition |
| `@RabbitListener` | Work queue, routing, request/reply |

Kafka giữ record theo retention và cho nhiều consumer group replay độc lập; RabbitMQ thường xóa message sau ack và mạnh về exchange/queue routing. Không có lựa chọn tốt tuyệt đối: throughput, replay, latency, ordering, vận hành và skill của đội mới quyết định.

---

## When – Khi nào dùng cơ chế nào?

| Nhu cầu | Lựa chọn khởi đầu |
|---|---|
| Tách module trong cùng process, không cần replay | Application event |
| Event log, replay, nhiều consumer group | Kafka |
| Task queue, routing key, request/reply | RabbitMQ |
| DB update và broker event phải không bị quên | Transactional Outbox |
| Workflow nhiều service có bước bù | Saga + Outbox/inbox/idempotency |
| Stream aggregate/window/state | Kafka Streams |

> 💡 **Giải thích dễ hiểu — chọn phương tiện theo hành trình:**
> Gửi giấy sang phòng bên không cần xe tải; giao nhiều kho cần bưu cục; còn lịch sử phải đọc lại cần cuộn sổ Kafka. Đơn hàng quan trọng luôn cần phiếu Outbox, bất kể xe giao là Kafka hay RabbitMQ.

---

## Trade-offs

- Manual ack cho quyền kiểm soát nhưng tăng nguy cơ ack sai hoặc giữ record quá lâu; container-managed mode thường đơn giản hơn.
- Retry blocking giữ thứ tự nhưng chiếm consumer thread; retry topic/queue giải phóng luồng chính nhưng có thể reorder.
- DLT/DLQ giữ poison message khỏi chặn luồng, nhưng chỉ có giá trị khi có alert, ownership, replay tool và retention.
- Kafka transaction cho EOS trong consume–process–produce Kafka; không làm DB/email/RabbitMQ side effect exactly-once.
- Saga tăng khả năng phục hồi nhưng chấp nhận eventual consistency và compensation phức tạp.
- Outbox tránh lost-event dual write nhưng tạo duplicate, cleanup, lag và vận hành relay/CDC.

---

## Production – Checklist

- Chuẩn hóa event envelope: `eventId`, type/version, aggregate ID, occurred-at, correlation/causation ID và schema compatibility.
- Dùng idempotency/inbox cho consumer; theo dõi duplicate và lỗi business, không dedup chỉ bằng log text.
- Giám sát consumer lag, rebalance, retry/DLT/DLQ rate, oldest-message age, publisher confirm/nack/return và Outbox/CDC lag.
- Đặt timeout, bounded concurrency, max attempts và backoff có jitter; tránh poison hot loop.
- Provision DLT partition/routing/retention, phân quyền payload/header vì có thể chứa PII.
- Với Saga: persist state, optimistic locking, timeout, idempotent compensation và reconciliation dashboard.
- Với Outbox: claim/lease, cleanup, replay, stable event contract, replication-slot/WAL capacity và runbook khi relay dừng.
- Test failure window: crash trước/sau DB commit, trước/sau broker confirm, duplicate, out-of-order và broker unavailable.

> 💡 **Giải thích dễ hiểu — production cần theo dõi cả dây chuyền thư:**
> Không chỉ nhìn bưu cục còn sáng đèn; phải biết thư lâu nhất đang nằm đâu, quầy lỗi có đầy không, phiếu nào bị gửi lại và ca sau có thể tiếp tục từ sổ nào.

---

## Ghi chú – Chủ đề tiếp theo

- Kafka transaction, non-blocking retry và schema evolution.
- RabbitMQ retry queue, delayed exchange, quorum queue và publisher confirm tuning.
- Inbox pattern, idempotency key và event envelope/versioning.
- Spring Modulith Event Publication Registry và externalization.
- Saga timeout, reconciliation, workflow engine và observability.
- Debezium Outbox Event Router, replication-slot/WAL operations.

---

*Cập nhật lần cuối: 2026-07-27*
