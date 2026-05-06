# Spring Messaging – Kafka & RabbitMQ Integration

## What – Messaging trong Spring Boot?

Spring Boot tích hợp sẵn với message brokers qua **Spring Kafka** (`spring-kafka`) và **Spring AMQP** (`spring-rabbit`), cung cấp abstraction lên Kafka Producer/Consumer và AMQP Publisher/Subscriber.

---

## Spring Kafka

### Dependency & Config

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
      acks: all
      retries: 3
      properties:
        enable.idempotence: true
        max.in.flight.requests.per.connection: 5
    consumer:
      group-id: order-service
      auto-offset-reset: earliest
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.JsonDeserializer
      properties:
        spring.json.trusted.packages: "com.example.events"
    listener:
      ack-mode: MANUAL_IMMEDIATE  # Tắt auto-commit, tự commit sau xử lý thành công
```

### Producer

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderEventProducer {

    private final KafkaTemplate<String, OrderEvent> kafkaTemplate;

    public void publishOrderCreated(Order order) {
        OrderCreatedEvent event = OrderCreatedEvent.from(order);

        // Key = orderId → đảm bảo cùng order vào cùng partition (ordering)
        ProducerRecord<String, OrderEvent> record = new ProducerRecord<>(
            "order-events",
            order.getId().toString(),
            event
        );
        record.headers().add("eventType", "OrderCreated".getBytes());
        record.headers().add("tenantId", order.getTenantId().getBytes());

        CompletableFuture<SendResult<String, OrderEvent>> future =
            kafkaTemplate.send(record);

        future.whenComplete((result, ex) -> {
            if (ex != null) {
                log.error("Failed to publish OrderCreated for order {}: {}", order.getId(), ex.getMessage());
                // Outbox pattern: retry sẽ handle
            } else {
                log.info("Published OrderCreated for order {} to partition {} offset {}",
                    order.getId(),
                    result.getRecordMetadata().partition(),
                    result.getRecordMetadata().offset());
            }
        });
    }

    // Transactional producer (exactly-once với Kafka Streams)
    @Transactional("kafkaTransactionManager")
    public void publishInTransaction(List<OrderEvent> events) {
        events.forEach(event ->
            kafkaTemplate.send("order-events", event.getOrderId(), event)
        );
    }
}
```

### Consumer

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class InventoryEventConsumer {

    private final InventoryService inventoryService;
    private final OrderRepository orderRepo;

    @KafkaListener(
        topics = "order-events",
        groupId = "inventory-service",
        containerFactory = "kafkaListenerContainerFactory"
    )
    public void handleOrderCreated(
            @Payload OrderCreatedEvent event,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.OFFSET) long offset,
            Acknowledgment ack) {

        String idempotencyKey = "inventory:" + event.getOrderId();

        try {
            if (processedEventRepo.existsByKey(idempotencyKey)) {
                log.info("Skipping already processed event: {}", event.getOrderId());
                ack.acknowledge();
                return;
            }

            inventoryService.reserve(event.getOrderId(), event.getItems());
            processedEventRepo.save(new ProcessedEvent(idempotencyKey));

            ack.acknowledge();
            log.info("Reserved inventory for order {} (partition={}, offset={})",
                event.getOrderId(), partition, offset);

        } catch (InsufficientStockException e) {
            log.warn("Insufficient stock for order {}: {}", event.getOrderId(), e.getMessage());
            // Publish compensation event
            publisher.publishInventoryReservationFailed(event.getOrderId(), e.getReason());
            ack.acknowledge(); // Ack anyway – not retryable

        } catch (Exception e) {
            log.error("Failed to process event for order {}", event.getOrderId(), e);
            // Do NOT ack → will be redelivered
            // Hoặc gửi vào Dead Letter Topic sau N retries
            throw e;
        }
    }

    // Batch consumer
    @KafkaListener(
        topics = "analytics-events",
        groupId = "analytics-processor",
        containerFactory = "batchKafkaListenerContainerFactory"
    )
    public void handleBatch(
            List<ConsumerRecord<String, AnalyticsEvent>> records,
            Acknowledgment ack) {

        log.info("Processing batch of {} events", records.size());

        List<AnalyticsEntry> entries = records.stream()
            .map(r -> AnalyticsEntry.from(r.value()))
            .toList();

        analyticsRepo.saveAll(entries);
        ack.acknowledge();
    }
}
```

### Dead Letter Topic (DLT)

```java
@Configuration
public class KafkaConfig {

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object> kafkaListenerContainerFactory(
            ConsumerFactory<String, Object> consumerFactory,
            KafkaTemplate<String, Object> kafkaTemplate) {

        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory);
        factory.getContainerProperties().setAckMode(AckMode.MANUAL_IMMEDIATE);

        // Dead Letter Topic after 3 retries
        DefaultErrorHandler errorHandler = new DefaultErrorHandler(
            new DeadLetterPublishingRecoverer(kafkaTemplate,
                (record, ex) -> new TopicPartition(record.topic() + ".DLT", record.partition())
            ),
            new FixedBackOff(1000L, 3L) // 3 retries, 1s interval
        );

        // Không retry cho non-retryable exceptions
        errorHandler.addNotRetryableExceptions(
            InsufficientStockException.class,
            DuplicateResourceException.class
        );

        factory.setCommonErrorHandler(errorHandler);
        return factory;
    }
}

// DLT Consumer – xử lý failed messages
@KafkaListener(topics = "order-events.DLT", groupId = "dlt-processor")
public void handleDlt(
        @Payload OrderCreatedEvent event,
        @Header(KafkaHeaders.EXCEPTION_CAUSE_FQCN) String exceptionCause) {

    log.error("DLT: Failed event for order {} caused by {}", event.getOrderId(), exceptionCause);
    alertService.sendAlert("Failed Kafka event: " + event.getOrderId());
    // Có thể: store to error DB, manual review, re-queue sau fix
}
```

---

## Outbox Pattern với Spring Kafka

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepo;
    private final OutboxRepository outboxRepo;

    @Transactional  // DB transaction
    public Order createOrder(CreateOrderRequest req) {
        Order order = orderRepo.save(Order.from(req));

        // Ghi outbox trong cùng transaction → guaranteed delivery
        outboxRepo.save(OutboxEvent.builder()
            .aggregateType("Order")
            .aggregateId(order.getId().toString())
            .eventType("OrderCreated")
            .payload(toJson(OrderCreatedEvent.from(order)))
            .build());

        return order;
    }
}

// Outbox Relay (polling hoặc Debezium CDC)
@Scheduled(fixedDelay = 100)
@Transactional
public void relayOutboxEvents() {
    List<OutboxEvent> events = outboxRepo.findTop100ByPublishedFalseOrderByCreatedAt();
    events.forEach(event -> {
        kafkaTemplate.send(event.getTopic(), event.getAggregateId(), event.getPayload());
        event.setPublished(true);
    });
    outboxRepo.saveAll(events);
}
```

---

## Spring AMQP (RabbitMQ)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-amqp</artifactId>
</dependency>
```

```yaml
spring:
  rabbitmq:
    host: localhost
    port: 5672
    username: guest
    password: guest
    listener:
      simple:
        prefetch: 10          # Consumer prefetch count
        acknowledge-mode: manual
        retry:
          enabled: true
          max-attempts: 3
          initial-interval: 1000
          multiplier: 2
```

```java
@Configuration
public class RabbitMQConfig {

    // Exchange + Queue + Binding
    @Bean
    public TopicExchange orderExchange() {
        return ExchangeBuilder.topicExchange("order.exchange").durable(true).build();
    }

    @Bean
    public Queue orderCreatedQueue() {
        return QueueBuilder.durable("order.created")
            .withArgument("x-dead-letter-exchange", "dlx.exchange")
            .withArgument("x-dead-letter-routing-key", "dlq.order.created")
            .withArgument("x-message-ttl", 3600000)  // 1 hour TTL
            .build();
    }

    @Bean
    public Binding orderCreatedBinding() {
        return BindingBuilder.bind(orderCreatedQueue())
            .to(orderExchange())
            .with("order.created.#");
    }

    // Dead Letter Exchange
    @Bean
    public DirectExchange dlxExchange() {
        return ExchangeBuilder.directExchange("dlx.exchange").durable(true).build();
    }

    @Bean
    public Queue dlqOrderCreated() {
        return QueueBuilder.durable("dlq.order.created").build();
    }

    @Bean
    public Binding dlqBinding() {
        return BindingBuilder.bind(dlqOrderCreated())
            .to(dlxExchange())
            .with("dlq.order.created");
    }

    // Message converter (JSON)
    @Bean
    public MessageConverter messageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}

// Publisher
@Service
@RequiredArgsConstructor
public class OrderEventPublisher {

    private final RabbitTemplate rabbitTemplate;

    public void publishOrderCreated(Order order) {
        OrderCreatedEvent event = OrderCreatedEvent.from(order);
        rabbitTemplate.convertAndSend("order.exchange", "order.created." + order.getType(), event,
            message -> {
                message.getMessageProperties().setMessageId(UUID.randomUUID().toString());
                message.getMessageProperties().setCorrelationId(MDC.get("traceId"));
                return message;
            });
    }
}

// Consumer
@Component
@RabbitListener(queues = "order.created")
@RequiredArgsConstructor
public class InventoryRabbitConsumer {

    @RabbitHandler
    public void handle(OrderCreatedEvent event, Message message, Channel channel) throws Exception {
        long deliveryTag = message.getMessageProperties().getDeliveryTag();
        try {
            inventoryService.reserve(event.getOrderId(), event.getItems());
            channel.basicAck(deliveryTag, false); // ACK
        } catch (InsufficientStockException e) {
            channel.basicNack(deliveryTag, false, false); // NACK, không requeue → DLQ
        } catch (Exception e) {
            channel.basicNack(deliveryTag, false, true); // NACK, requeue = true (retry)
        }
    }
}
```

---

## Kafka vs RabbitMQ – Khi nào dùng gì?

| | Kafka | RabbitMQ (AMQP) |
|--|-------|-----------------|
| **Model** | Log-based (pull) | Queue-based (push) |
| **Retention** | Days to forever | Until consumed |
| **Replay** | Yes ✅ | No (consumed = gone) |
| **Throughput** | 1M+ msg/s | ~50K msg/s |
| **Routing** | Topic/Partition | Exchange/Queue (flexible) |
| **Ordering** | Per partition | Per queue |
| **Use case** | Event streaming, audit, replay | Task queue, RPC, complex routing |
| **Ops complexity** | High | Medium |

**Dùng Kafka khi:** Event sourcing, audit log, high throughput, cần replay
**Dùng RabbitMQ khi:** Task queues, complex routing, simpler ops, lower throughput

---

## Ghi chú

**Sub-topic tiếp theo:**
- `advanced/cache.md` – @Cacheable với Redis
- `production/observability.md` – Consumer lag monitoring, dead letter monitoring
- **Keywords:** Kafka Streams (trong Spring Boot), Spring Cloud Stream (abstraction over Kafka/RabbitMQ), @SendTo (routing reply), ChainedKafkaTransactionManager, Saga with Kafka, Consumer group rebalancing, Exactly-once semantics, Transactional outbox với Debezium, AMQP RPC pattern
