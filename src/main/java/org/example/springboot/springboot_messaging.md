# Spring Boot Messaging – Deep Dive

## Mục lục
1. [Spring Kafka Deep](#1-spring-kafka-deep)
2. [Spring AMQP Deep](#2-spring-amqp-deep)
3. [@EventListener & @TransactionalEventListener](#3-eventlistener--transactionaleventlistener)
4. [Saga Pattern](#4-saga-pattern)
5. [Outbox Pattern](#5-outbox-pattern)

---

## 1. Spring Kafka Deep

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
        enable.idempotence: true        # exactly-once producer
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
      enable-auto-commit: false        # manual commit for reliability
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
      type: BATCH                      # batch mode
```

### 1.2 Producer

```java
@Component
public class OrderEventPublisher {

    @Autowired
    private KafkaTemplate<String, Object> kafkaTemplate;
    
    // Simple send
    public void sendOrderCreated(OrderCreatedEvent event) {
        kafkaTemplate.send("orders", event.getOrderId().toString(), event);
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
    
    // Transactional producer (exactly-once with transactions)
    @Transactional("kafkaTransactionManager")
    public void sendTransactional(List<OrderEvent> events) {
        events.forEach(e -> kafkaTemplate.send("orders", e.getOrderId().toString(), e));
    }
}
```

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
            // Don't ack — will be redelivered
            throw e;
        } catch (Exception e) {
            log.error("Failed to process order {}", event.getOrderId(), e);
            ack.acknowledge(); // ack to skip, rely on DLT
        }
    }
    
    // Batch consumer
    @KafkaListener(topics = "orders", groupId = "order-batch",
                   containerFactory = "batchFactory")
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

### 1.4 Error Handling & Dead Letter Topic

```java
@Configuration
public class KafkaConsumerConfig {

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, Object> kafkaListenerContainerFactory(
            ConsumerFactory<String, Object> consumerFactory,
            KafkaTemplate<String, Object> kafkaTemplate) {
        
        ConcurrentKafkaListenerContainerFactory<String, Object> factory =
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory);
        factory.getContainerProperties().setAckMode(ContainerProperties.AckMode.MANUAL_IMMEDIATE);
        factory.setConcurrency(3);
        
        // Retry + DLT
        factory.setCommonErrorHandler(new DefaultErrorHandler(
            new DeadLetterPublishingRecoverer(kafkaTemplate,
                (rec, ex) -> new TopicPartition(rec.topic() + ".DLT", rec.partition())),
            new FixedBackOff(1000L, 3L) // 3 retries, 1s apart
        ));
        
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
            new DeadLetterPublishingRecoverer(kafkaTemplate), backOff);
        
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
            @Header(KafkaHeaders.EXCEPTION_CAUSE_FQCN) String exceptionClass,
            @Header(KafkaHeaders.EXCEPTION_MESSAGE) String exceptionMessage) {
        
        log.error("DLT message: topic={}, partition={}, offset={}, cause={}",
            record.topic(), record.partition(), record.offset(), exceptionMessage);
        
        // Store in DB for manual review / alerting
        deadLetterService.store(record, exceptionClass, exceptionMessage);
    }
}
```

### 1.5 Consumer Group Rebalancing & Partitioning

```java
// Custom partitioner
public class OrderPartitioner implements Partitioner {
    
    @Override
    public int partition(String topic, Object key, byte[] keyBytes,
                         Object value, byte[] valueBytes, Cluster cluster) {
        int numPartitions = cluster.partitionCountForTopic(topic);
        if (key instanceof String orderId) {
            // Consistent hashing — same orderId → same partition
            return Math.abs(orderId.hashCode()) % numPartitions;
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

---

## 2. Spring AMQP Deep

### 2.1 Full Configuration

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

### 2.2 Consumer Patterns

```java
@Component
@Slf4j
public class OrderConsumer {

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
            @Header(AmqpHeaders.DELIVERY_TAG) long tag,
            @Autowired RabbitTemplate rabbitTemplate) throws IOException {
        
        try {
            orderService.process(event);
            channel.basicAck(tag, false);
        } catch (Exception e) {
            channel.basicAck(tag, false); // ack original
            if (retryCount < 3) {
                // Re-publish with incremented counter
                rabbitTemplate.convertAndSend("order.exchange", "order.created",
                    event, msg -> {
                        msg.getMessageProperties().getHeaders()
                           .put("x-retry-count", retryCount + 1);
                        return msg;
                    });
            } else {
                // Max retries exceeded — publish to DLQ manually
                rabbitTemplate.convertAndSend("order.dlx", "order.dead", event);
            }
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
    
    // With SpEL condition
    @RabbitListener(queues = "order.queue",
                    condition = "headers['orderType'] == 'PRIORITY'")
    public void handlePriorityOrder(OrderCreatedEvent event) { ... }
}
```

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
            return confirm.isAck();
        } catch (TimeoutException e) {
            log.error("Confirm timeout for message {}", correlationData.getId());
            return false;
        }
    }
    
    // Async confirm
    public void sendAsync(OrderCreatedEvent event) {
        CorrelationData cd = new CorrelationData(event.getOrderId().toString());
        cd.getFuture().addCallback(
            confirm -> {
                if (confirm.isAck()) {
                    log.debug("Message {} confirmed", event.getOrderId());
                } else {
                    log.error("Message {} nacked: {}", event.getOrderId(), confirm.getReason());
                    // retry / store for retry
                }
            },
            ex -> log.error("Confirm failed for {}", event.getOrderId(), ex)
        );
        
        rabbitTemplate.convertAndSend("order.exchange", "order.created", event, cd);
    }
}
```

---

## 3. @EventListener & @TransactionalEventListener

### 3.1 Application Events

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

### 3.3 @TransactionalEventListener — Key Mechanics

```java
@Component
@Slf4j
public class TransactionalOrderEventHandler {

    // AFTER_COMMIT: fires only if transaction commits successfully
    // Default phase — most common usage
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderCommitted(OrderPlacedEvent event) {
        // Safe to call external systems — order is definitely saved
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

**Critical: @TransactionalEventListener with @Async:**

```java
// Problem: AFTER_COMMIT listener loses transaction context
// Solution: wrap in new @Transactional if you need DB access

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

---

## 4. Saga Pattern

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
        
        eventPublisher.publishEvent(new OrderCreatedEvent(
            order.getId(), req.getCustomerId(), order.getTotal(), req.getItems()
        ));
        return order;
    }
    
    // Compensating transaction
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Async
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

---

## 5. Outbox Pattern

### 5.1 Problem & Solution

```
Problem: Service updates DB + publishes Kafka/RabbitMQ in same request.
Risk: DB commits but broker publish fails → lost event.
     Or: Broker publishes but DB rolls back → ghost event.

Solution: Transactional Outbox
- Write event to outbox table in SAME transaction as business data
- Background process reads outbox and publishes to broker
- Mark as published only after broker confirms
```

### 5.2 Outbox Table

```sql
CREATE TABLE outbox_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(100) NOT NULL,
    event_type      VARCHAR(200) NOT NULL,
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
    
    public void saveEvent(String aggregateType, String aggregateId, Object event) {
        try {
            OutboxEvent outbox = new OutboxEvent();
            outbox.setAggregateType(aggregateType);
            outbox.setAggregateId(aggregateId);
            outbox.setEventType(event.getClass().getName());
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
        outboxService.saveEvent("Order", order.getId().toString(),
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
                kafkaTemplate.send(topic, event.getAggregateId(), event.getPayload())
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
        // e.g., "org.example.events.OrderCreatedEvent" → "order-events"
        String simpleName = eventType.substring(eventType.lastIndexOf('.') + 1);
        return simpleName.replaceAll("([A-Z])", "-$1").toLowerCase().substring(1)
                         .replace("-event", "-events");
    }
}
```

### 5.4 Debezium CDC Approach (Production)

```yaml
# Better than polling: Debezium reads Postgres WAL (change data capture)
# config/debezium-connector.json
{
  "name": "outbox-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "localhost",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "debezium",
    "database.dbname": "mydb",
    "table.include.list": "public.outbox_events",
    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.table.field.event.id": "id",
    "transforms.outbox.table.field.event.key": "aggregate_id",
    "transforms.outbox.table.field.event.type": "event_type",
    "transforms.outbox.table.field.event.payload": "payload",
    "transforms.outbox.table.fields.additional.placement": "aggregate_type:envelope"
  }
}
```

---

## Summary: Messaging Patterns Comparison

| Pattern | Delivery | Ordering | Failure handling |
|---------|----------|----------|-----------------|
| Choreography Saga | Eventual | Per-partition | Each service compensates |
| Orchestration Saga | Eventual | Via orchestrator | Central rollback logic |
| Transactional Outbox (polling) | At-least-once | FIFO per aggregate | Retry with backoff, DLQ |
| Outbox + CDC (Debezium) | Exactly-once semantics | Per-table order | WAL-based, no data loss |

| Spring Component | Best for |
|------------------|----------|
| @EventListener | Sync in-process events, simple side effects |
| @Async @EventListener | Fire-and-forget side effects (email, audit) |
| @TransactionalEventListener | Post-commit actions (notify external after DB commit) |
| @KafkaListener | High-throughput async, stream processing |
| @RabbitListener | Request/reply, task queues, complex routing |
