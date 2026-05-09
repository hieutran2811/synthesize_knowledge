# Messaging – Spring Kafka & Spring AMQP

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Spring Kafka

### What – Spring Kafka là gì?
**Spring Kafka** là abstraction layer trên Kafka Java Client, cung cấp template-based producer, listener container, error handling, retry, và transaction support.

### How – Setup

```xml
<!-- pom.xml -->
<dependency>
    <groupId>org.springframework.kafka</groupId>
    <artifactId>spring-kafka</artifactId>
</dependency>
```

```yaml
# application.yaml
spring:
  kafka:
    bootstrap-servers: kafka1:9092,kafka2:9092,kafka3:9092
    # Producer config
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
      acks: all              # wait for all ISR to acknowledge
      retries: 3
      properties:
        enable.idempotence: true          # exactly-once producer
        max.in.flight.requests.per.connection: 5
        compression.type: snappy
        linger.ms: 5                      # batch messages (5ms delay)
        batch.size: 16384                 # 16KB batch
    # Consumer config
    consumer:
      group-id: order-service
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.ErrorHandlingDeserializer
      properties:
        spring.deserializer.value.delegate.class: org.springframework.kafka.support.serializer.JsonDeserializer
        spring.json.trusted.packages: com.example.events
      auto-offset-reset: earliest
      enable-auto-commit: false         # manual commit (safer)
      max-poll-records: 500
      isolation-level: read_committed   # read only committed records (transactions)
```

### How – Producer

```java
@Service
public class OrderEventProducer {
    private final KafkaTemplate<String, OrderEvent> kafkaTemplate;

    // Simple send
    public void sendOrderCreated(Order order) {
        OrderEvent event = new OrderEvent("ORDER_CREATED", order.getId(), order);
        kafkaTemplate.send("orders", order.getId().toString(), event);
    }

    // Send với callback
    public CompletableFuture<SendResult<String, OrderEvent>> sendAsync(Order order) {
        OrderEvent event = OrderEvent.ofCreated(order);
        return kafkaTemplate.send("orders", order.getId().toString(), event)
            .thenApply(result -> {
                log.info("Sent to partition={} offset={}",
                    result.getRecordMetadata().partition(),
                    result.getRecordMetadata().offset());
                return result;
            })
            .exceptionally(ex -> {
                log.error("Failed to send event for orderId={}", order.getId(), ex);
                // retry or publish to DLT
                throw new EventPublishException(ex);
            });
    }

    // Send to specific partition
    public void sendToPartition(Order order) {
        kafkaTemplate.send(new ProducerRecord<>(
            "orders",
            order.getUserId().intValue() % 10,  // partition by userId
            order.getId().toString(),
            OrderEvent.ofCreated(order)
        ));
    }
}
```

### How – Consumer

```java
@Component
public class OrderEventConsumer {
    @KafkaListener(
        topics = "orders",
        groupId = "order-processor",
        concurrency = "3"              // 3 concurrent consumer threads
    )
    public void consume(
            @Payload OrderEvent event,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            Acknowledgment ack) {
        log.info("Processing event: type={}, orderId={}, partition={}, offset={}",
            event.getType(), event.getOrderId(), partition, offset);
        try {
            processEvent(event);
            ack.acknowledge();         // manual commit sau khi xử lý thành công
        } catch (RecoverableException e) {
            // sẽ retry
            throw e;
        } catch (Exception e) {
            log.error("Failed to process event, sending to DLT", e);
            ack.acknowledge();         // commit để không process lại
            deadLetterPublisher.send("orders.DLT", event);
        }
    }

    // Batch consumer
    @KafkaListener(topics = "events", containerFactory = "batchFactory")
    public void consumeBatch(List<OrderEvent> events, Acknowledgment ack) {
        log.info("Processing batch of {} events", events.size());
        events.forEach(this::processEvent);
        ack.acknowledge();
    }
}
```

### How – Error Handling & Retry

```java
@Configuration
public class KafkaConfig {

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, OrderEvent> kafkaListenerContainerFactory(
            ConsumerFactory<String, OrderEvent> consumerFactory,
            KafkaTemplate<String, OrderEvent> template) {

        var factory = new ConcurrentKafkaListenerContainerFactory<String, OrderEvent>();
        factory.setConsumerFactory(consumerFactory);
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL);

        // Retry with backoff (3 attempts: 1s, 2s, 4s)
        DefaultErrorHandler errorHandler = new DefaultErrorHandler(
            new DeadLetterPublishingRecoverer(template,
                (record, ex) -> new TopicPartition(record.topic() + ".DLT", record.partition())),
            new FixedBackOff(1000L, 3)
        );

        // Don't retry these exceptions (permanent failures)
        errorHandler.addNotRetryableExceptions(
            JsonParseException.class,
            ValidationException.class
        );

        factory.setCommonErrorHandler(errorHandler);
        return factory;
    }

    // Batch factory
    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, OrderEvent> batchFactory(
            ConsumerFactory<String, OrderEvent> consumerFactory) {
        var factory = new ConcurrentKafkaListenerContainerFactory<String, OrderEvent>();
        factory.setConsumerFactory(consumerFactory);
        factory.setBatchListener(true);
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.BATCH);
        return factory;
    }
}
```

### How – Kafka Transactions (Exactly Once)

```java
@Configuration
public class KafkaTransactionConfig {
    @Bean
    public KafkaTemplate<String, Object> transactionalTemplate(ProducerFactory<String, Object> pf) {
        pf.setTransactionIdPrefix("order-svc-");
        return new KafkaTemplate<>(pf);
    }
}

@Service
public class OrderProcessor {
    @Transactional
    public void processOrder(OrderCommand cmd) {
        // DB operation
        Order order = orderRepository.save(new Order(cmd));

        // Kafka send trong cùng transaction
        // Cả DB save và Kafka send commit/rollback cùng nhau
        kafkaTemplate.send("orders", order.getId().toString(), OrderEvent.ofCreated(order));

        // Nếu exception xảy ra: cả DB và Kafka rollback
    }
}
```

---

## 2. Spring AMQP (RabbitMQ)

### How – Setup

```yaml
spring:
  rabbitmq:
    host: rabbitmq
    port: 5672
    username: ${RABBITMQ_USER}
    password: ${RABBITMQ_PASS}
    virtual-host: /
    listener:
      simple:
        acknowledge-mode: manual
        prefetch: 10               # max unacked messages per consumer
        concurrency: 2
        max-concurrency: 5
    template:
      retry:
        enabled: true
        initial-interval: 1000ms
        max-attempts: 3
        multiplier: 2.0
```

### How – Config (Exchange, Queue, Binding)

```java
@Configuration
public class RabbitMQConfig {

    @Bean
    public TopicExchange orderExchange() {
        return ExchangeBuilder.topicExchange("orders")
            .durable(true)
            .build();
    }

    @Bean
    public Queue orderCreatedQueue() {
        return QueueBuilder.durable("order.created")
            .withArgument("x-dead-letter-exchange", "orders.dlx")
            .withArgument("x-dead-letter-routing-key", "order.created.dlq")
            .withArgument("x-message-ttl", 60000)  // 1 minute TTL
            .build();
    }

    @Bean
    public Queue orderCreatedDLQ() {
        return QueueBuilder.durable("order.created.dlq").build();
    }

    @Bean
    public Binding orderCreatedBinding(Queue orderCreatedQueue, TopicExchange orderExchange) {
        return BindingBuilder.bind(orderCreatedQueue)
            .to(orderExchange)
            .with("order.created.#");
    }

    @Bean
    public MessageConverter jsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }

    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory cf) {
        RabbitTemplate template = new RabbitTemplate(cf);
        template.setMessageConverter(jsonMessageConverter());
        template.setMandatory(true);              // fail if no route
        template.setConfirmCallback((correlation, ack, cause) -> {
            if (!ack) log.error("Message not confirmed: {}", cause);
        });
        template.setReturnsCallback(returned -> {
            log.error("Message returned: routingKey={}", returned.getRoutingKey());
        });
        return template;
    }
}
```

### How – Producer & Consumer

```java
@Service
public class OrderEventPublisher {
    private final RabbitTemplate rabbitTemplate;

    public void publishOrderCreated(Order order) {
        OrderCreatedEvent event = new OrderCreatedEvent(order);
        rabbitTemplate.convertAndSend("orders", "order.created.v1", event,
            message -> {
                message.getMessageProperties().setContentType("application/json");
                message.getMessageProperties().setMessageId(UUID.randomUUID().toString());
                message.getMessageProperties().setTimestamp(new Date());
                message.getMessageProperties().setHeader("eventVersion", "1.0");
                return message;
            });
    }
}

@Component
public class OrderCreatedListener {
    @RabbitListener(queues = "order.created")
    public void handleOrderCreated(
            OrderCreatedEvent event,
            @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
            Channel channel) throws IOException {
        try {
            log.info("Processing order: {}", event.getOrderId());
            processOrder(event);
            channel.basicAck(deliveryTag, false);  // ack single message
        } catch (BusinessException e) {
            log.warn("Business error, sending to DLQ: {}", e.getMessage());
            channel.basicNack(deliveryTag, false, false);  // reject, no requeue → DLQ
        } catch (TransientException e) {
            log.warn("Transient error, requeueing: {}", e.getMessage());
            channel.basicNack(deliveryTag, false, true);   // reject, requeue
        }
    }
}
```

---

## 3. Transactional Outbox Pattern

### What – Outbox Pattern là gì?
Giải quyết **dual-write problem**: khi cần cả save DB và publish message cùng lúc mà không có distributed transaction.

**Vấn đề:**
```
// BROKEN: race condition
orderRepository.save(order);     // DB OK
kafkaTemplate.send(event);       // Kafka FAIL → event mất!
// hoặc
kafkaTemplate.send(event);       // Kafka OK
orderRepository.save(order);     // DB FAIL → duplicate event!
```

**Giải pháp – Outbox:**
```
Trong cùng DB transaction:
  1. INSERT INTO orders (...)
  2. INSERT INTO outbox_events (type, payload, status='PENDING')

Separate poller/CDC:
  3. SELECT FROM outbox_events WHERE status='PENDING'
  4. Publish to Kafka/RabbitMQ
  5. UPDATE outbox_events SET status='SENT'
```

### How – Implementation

```java
@Entity
@Table(name = "outbox_events")
public class OutboxEvent {
    @Id private UUID id;
    private String aggregateType;      // "Order"
    private String aggregateId;        // orderId
    private String eventType;          // "OrderCreated"
    private String payload;            // JSON
    @Enumerated(EnumType.STRING)
    private EventStatus status;        // PENDING, SENT, FAILED
    private Instant createdAt;
    private Instant processedAt;
    private int retryCount;
}
```

```java
@Service
@Transactional
public class OrderService {
    public Order createOrder(CreateOrderRequest req) {
        // 1. Save order
        Order order = orderRepository.save(new Order(req));

        // 2. Save outbox event (trong cùng transaction!)
        OutboxEvent event = OutboxEvent.builder()
            .id(UUID.randomUUID())
            .aggregateType("Order")
            .aggregateId(order.getId().toString())
            .eventType("OrderCreated")
            .payload(objectMapper.writeValueAsString(OrderCreatedEvent.from(order)))
            .status(EventStatus.PENDING)
            .createdAt(Instant.now())
            .build();
        outboxRepository.save(event);

        return order;
        // Cả order VÀ outbox event committed hoặc rolled back cùng nhau
    }
}
```

```java
// Outbox Poller
@Component
public class OutboxEventPublisher {
    @Scheduled(fixedDelay = 1000)  // mỗi 1 giây
    @Transactional
    public void publishPendingEvents() {
        List<OutboxEvent> events = outboxRepository
            .findTop100ByStatusOrderByCreatedAt(EventStatus.PENDING);

        for (OutboxEvent event : events) {
            try {
                kafkaTemplate.send(
                    event.getAggregateType().toLowerCase() + "s",
                    event.getAggregateId(),
                    event.getPayload()
                ).get(5, TimeUnit.SECONDS);  // sync wait

                event.setStatus(EventStatus.SENT);
                event.setProcessedAt(Instant.now());
            } catch (Exception e) {
                event.setRetryCount(event.getRetryCount() + 1);
                if (event.getRetryCount() >= 5) {
                    event.setStatus(EventStatus.FAILED);
                }
                log.error("Failed to publish event id={}", event.getId(), e);
            }
        }
    }
}
```

### How – Debezium CDC (Production-grade Outbox)

```yaml
# Debezium Kafka Connect config
{
  "name": "outbox-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres",
    "database.dbname": "orderdb",
    "table.include.list": "public.outbox_events",
    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.table.field.event.id": "id",
    "transforms.outbox.table.field.event.type": "event_type",
    "transforms.outbox.table.field.event.payload": "payload",
    "transforms.outbox.route.by.field": "aggregate_type"
  }
}
```

---

## 4. Compare & Trade-offs

### Compare – Kafka vs RabbitMQ

| | Kafka | RabbitMQ |
|--|-------|---------|
| Model | Log-based (pull, durable) | Queue-based (push) |
| Message ordering | Per partition | Per queue |
| Replay | Có (offset rewind) | Không (once consumed) |
| Throughput | Rất cao (millions/s) | Cao (hundreds k/s) |
| Consumer groups | Yes (offset tracking) | Yes (competing consumers) |
| Routing | Topic/partition | Exchange/binding (flexible) |
| Retention | Long (days/weeks) | Short (until consumed) |
| Khi dùng | Event streaming, audit log, high throughput | Task queue, RPC, routing |

### Trade-offs – Messaging Patterns

- **At-least-once delivery**: dễ implement nhưng consumer phải idempotent
- **Exactly-once Kafka**: performance overhead (transactions); thực tế at-least-once + idempotent đủ cho hầu hết cases
- **Outbox pattern**: đảm bảo consistency nhưng thêm latency (polling interval); CDC giải quyết latency
- **Saga vs 2PC**: Saga dùng messaging = loosely coupled nhưng complex; 2PC = simple nhưng không scale

---

### Ghi chú – Chủ đề tiếp theo
> **19.4 gRPC & Protobuf**: code generation, service definitions, streaming types, interceptors, deadline/retry
