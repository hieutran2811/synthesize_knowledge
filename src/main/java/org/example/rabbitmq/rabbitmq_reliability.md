# RabbitMQ Reliability & Guarantees

## 1. Message Durability

### 1.1 Ba cấp độ Durability

```
Để message không mất khi broker restart, cần đủ CẢ BA:

Level 1: Durable Exchange
channel.exchange_declare(exchange='my_exchange', durable=True)
↑ Exchange tồn tại sau restart

Level 2: Durable Queue
channel.queue_declare(queue='my_queue', durable=True)
↑ Queue tồn tại sau restart (với messages pending)

Level 3: Persistent Message
properties=pika.BasicProperties(delivery_mode=2)  # 1=transient, 2=persistent
↑ Message ghi xuống disk (không chỉ RAM)

Nếu thiếu bất kỳ cấp nào → messages sẽ mất!
```

```python
# Full durability setup
channel.exchange_declare(
    exchange='orders',
    exchange_type='topic',
    durable=True,           # ✓ Level 1
    auto_delete=False,
)

channel.queue_declare(
    queue='order_processing',
    durable=True,           # ✓ Level 2
    auto_delete=False,
    arguments={
        'x-dead-letter-exchange': 'orders.dlx',
        'x-message-ttl': 86400000,  # 24h TTL
    }
)

channel.basic_publish(
    exchange='orders',
    routing_key='order.created',
    body=json.dumps(order),
    properties=pika.BasicProperties(
        delivery_mode=2,    # ✓ Level 3: persistent
        content_type='application/json',
    )
)
```

### 1.2 Performance Impact of Persistence

```
Persistent messages → fsync to disk → slower than transient
Trade-off:
  Persistent: ~10,000-30,000 msg/s (depends on disk)
  Transient:  ~100,000+ msg/s (memory only)

Optimization options:
1. Lazy Queues (Classic): always store on disk, reduce RAM usage
   arguments={'x-queue-mode': 'lazy'}  # deprecated 3.12, use quorum

2. Quorum Queues: replicated on disk across nodes (better durability + HA)
   arguments={'x-queue-type': 'quorum'}

3. Publisher Confirms batch: batch ACKs instead of per-message
   (see Publisher Confirms section)
```

---

## 2. Publisher Confirms

### 2.1 What & Why

**Publisher Confirms** = broker xác nhận đã nhận và xử lý message (ghi vào queue/disk). Thay thế AMQP transactions (nhẹ hơn nhiều).

```
Without Confirms:
  Producer → basic_publish() → returns immediately
  → Producer không biết broker có nhận được không
  → Network failure → message lost silently

With Confirms:
  Producer → basic_publish() → broker processes → ack/nack
  → Producer knows message was accepted (or should retry)
```

```python
# Python: Publisher Confirms (pika)
import pika, json, threading
from collections import deque

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

# Enable confirms mode (per channel)
channel.confirm_delivery()

# Method 1: Synchronous confirm (simple but slow)
channel.queue_declare(queue='orders', durable=True)

for i in range(100):
    try:
        channel.basic_publish(
            exchange='',
            routing_key='orders',
            body=json.dumps({'order_id': i}),
            properties=pika.BasicProperties(delivery_mode=2),
            mandatory=True,  # return if unroutable
        )
        # Waits for broker ack — BLOCKS until confirmed
        print(f"Message {i} confirmed")
    except pika.exceptions.UnroutableError:
        print(f"Message {i} was returned (unroutable)!")
    except pika.exceptions.NackError:
        print(f"Message {i} was NACKed (broker internal error)")

# Method 2: Async batch confirms (much faster)
class PublisherWithConfirms:
    def __init__(self, channel):
        self.channel = channel
        self.channel.confirm_delivery()
        self.pending = {}  # delivery_tag → message
        self.lock = threading.Lock()
        
        # Set up ACK/NACK callbacks
        self.channel.add_on_return_callback(self._on_return)
    
    def publish(self, exchange, routing_key, body, properties=None):
        with self.lock:
            self.channel.basic_publish(
                exchange=exchange,
                routing_key=routing_key,
                body=body,
                properties=properties or pika.BasicProperties(delivery_mode=2),
                mandatory=True,
            )
            # Track by next_publish_seq_no
            seq = self.channel.get_next_publish_seq_no() - 1
            self.pending[seq] = {'body': body, 'routing_key': routing_key}
    
    def _on_ack(self, method_frame):
        delivery_tag = method_frame.method.delivery_tag
        multiple = method_frame.method.multiple
        with self.lock:
            if multiple:
                # Ack all up to delivery_tag
                to_remove = [tag for tag in self.pending if tag <= delivery_tag]
                for tag in to_remove:
                    del self.pending[tag]
            else:
                self.pending.pop(delivery_tag, None)
    
    def _on_nack(self, method_frame):
        delivery_tag = method_frame.method.delivery_tag
        with self.lock:
            msg = self.pending.pop(delivery_tag, None)
            if msg:
                print(f"NACK received, republishing: {msg['routing_key']}")
                self._republish(msg)
    
    def _on_return(self, channel, method, properties, body):
        print(f"Message RETURNED: {method.reply_text}")
        # Handle unroutable message (no matching queue)
    
    def _republish(self, msg):
        # Retry logic
        pass
```

### 2.2 Java: Publisher Confirms (Spring AMQP)

```java
// Spring AMQP: Publisher Confirms via CorrelationData
@Configuration
public class RabbitConfig {
    
    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        
        // Enable publisher confirms
        template.setConfirmCallback((correlationData, ack, cause) -> {
            String messageId = correlationData != null ? correlationData.getId() : "unknown";
            if (ack) {
                log.info("Message {} confirmed by broker", messageId);
                // Mark message as confirmed in DB
            } else {
                log.error("Message {} NACKED by broker: {}", messageId, cause);
                // Retry or alert
            }
        });
        
        // Enable returns for unroutable messages
        template.setReturnsCallback(returned -> {
            log.error("Message returned! Exchange: {}, RoutingKey: {}, Reply: {}",
                returned.getExchange(), returned.getRoutingKey(), returned.getReplyText());
            // Handle unroutable: re-route or alert
        });
        
        template.setMandatory(true);  // enable returns
        return template;
    }
}

// application.yml
// spring:
//   rabbitmq:
//     publisher-confirm-type: correlated  # NONE, SIMPLE, CORRELATED
//     publisher-returns: true

@Service
public class OrderPublisher {
    
    @Autowired
    private RabbitTemplate rabbitTemplate;
    
    public void publishOrder(Order order) {
        // CorrelationData links confirm callback to this publish
        CorrelationData correlationData = new CorrelationData(order.getId().toString());
        
        // Store message for potential retry
        correlationData.setFuture(new CompletableFuture<>());
        
        rabbitTemplate.convertAndSend(
            "orders",
            "order.created",
            order,
            correlationData
        );
        
        // Optionally wait for confirm
        try {
            CorrelationData.Confirm confirm = correlationData.getFuture().get(5, TimeUnit.SECONDS);
            if (!confirm.isAck()) {
                throw new RuntimeException("Broker NACKed: " + confirm.getReason());
            }
        } catch (TimeoutException e) {
            throw new RuntimeException("Confirm timeout - broker may be down");
        }
    }
}
```

### 2.3 Outbox Pattern (Guaranteed Publishing)

```java
// Problem: Publish message + update DB atomically
// Anti-pattern:
//   db.save(order);          // succeeds
//   rabbit.publish(order);   // fails → message lost, DB has order but no event

// Solution: Transactional Outbox Pattern
@Entity
@Table(name = "outbox_messages")
public class OutboxMessage {
    @Id UUID id;
    String exchange;
    String routingKey;
    String payload;
    String status; // PENDING, SENT, FAILED
    LocalDateTime createdAt;
    LocalDateTime sentAt;
    int retryCount;
}

@Service
@Transactional
public class OrderService {
    
    @Autowired private OrderRepository orderRepo;
    @Autowired private OutboxRepository outboxRepo;
    
    public Order createOrder(CreateOrderRequest req) {
        // Same DB transaction: save order + outbox message
        Order order = orderRepo.save(new Order(req));
        
        outboxRepo.save(OutboxMessage.builder()
            .id(UUID.randomUUID())
            .exchange("orders")
            .routingKey("order.created")
            .payload(objectMapper.writeValueAsString(order))
            .status("PENDING")
            .build());
        
        return order;  // commit both atomically
    }
}

// Background publisher: reads outbox, publishes, marks SENT
@Scheduled(fixedDelay = 1000)
@Transactional
public void publishOutboxMessages() {
    List<OutboxMessage> pending = outboxRepo.findByStatusOrderByCreatedAt("PENDING", limit=100);
    
    for (OutboxMessage msg : pending) {
        try {
            rabbitTemplate.convertAndSend(msg.getExchange(), msg.getRoutingKey(), msg.getPayload());
            msg.setStatus("SENT");
            msg.setSentAt(LocalDateTime.now());
        } catch (Exception e) {
            msg.setRetryCount(msg.getRetryCount() + 1);
            if (msg.getRetryCount() >= 5) {
                msg.setStatus("FAILED");
            }
        }
        outboxRepo.save(msg);
    }
}
```

---

## 3. Consumer Acknowledgements

### 3.1 Ack / Nack / Reject

```python
# auto_ack=True: broker removes message immediately on delivery (UNSAFE)
# Risk: consumer crashes before processing → message lost

# auto_ack=False: manual acknowledgement

def on_message(ch, method, properties, body):
    delivery_tag = method.delivery_tag
    
    try:
        data = json.loads(body)
        result = process(data)
        
        # ACK: message successfully processed
        ch.basic_ack(delivery_tag=delivery_tag)
        # multiple=True: ack all messages up to delivery_tag (batch ack)
        # ch.basic_ack(delivery_tag=delivery_tag, multiple=True)
    
    except TemporaryError as e:
        # NACK with requeue=True: put back in queue (at HEAD, not tail!)
        # Warning: can cause infinite loop if error is permanent!
        ch.basic_nack(delivery_tag=delivery_tag, requeue=True)
    
    except PermanentError as e:
        # NACK with requeue=False: dead letter or discard
        ch.basic_nack(delivery_tag=delivery_tag, requeue=False)
        # If DLX configured → message goes to DLQ
    
    # REJECT = same as NACK but only single message (no multiple flag)
    # ch.basic_reject(delivery_tag=delivery_tag, requeue=False)
```

### 3.2 Ack States & "Unacked" Messages

```
Queue states:
├── Ready: available to be delivered
├── Unacked: delivered to consumer, awaiting ack
└── Total = Ready + Unacked

Unacked leak:
  - Consumer receives messages but never acks
  - Messages stay "Unacked" forever (held in memory)
  - When consumer disconnects → messages requeue to "Ready"
  - Check: rabbitmqctl list_queues name messages_ready messages_unacknowledged

Monitoring:
rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers
```

### 3.3 Consumer Timeout

```bash
# RabbitMQ 3.8.15+: consumer_timeout
# If consumer holds ack for > timeout → channel closed with error

# rabbitmq.conf
consumer_timeout = 1800000  # 30 minutes (milliseconds)

# Disable per queue
rabbitmqctl set_policy consumer-timeout "^long_running_queue$" \
    '{"consumer-timeout": false}' --apply-to queues

# Or set custom timeout per queue
channel.queue_declare(queue='long_tasks', durable=True,
    arguments={'x-consumer-timeout': 7200000})  # 2 hours
```

---

## 4. QoS & Prefetch

### 4.1 Prefetch Count

```python
# prefetch_count: max number of unacknowledged messages per consumer
# Without prefetch: consumer can receive thousands of messages before processing

# prefetch_count=1: strictest fair dispatch
# - Consumer gets 1 message at a time
# - Gets next only after ack
# - Best for: variable processing time, fair load distribution

# prefetch_count=10-100: good balance
# - Consumer buffers N messages (reduces round-trips)
# - Better throughput than prefetch=1
# - Risk: one slow consumer holds more messages

# prefetch_count=0: unlimited (DANGEROUS - disable entirely)
# - Consumer gets all available messages
# - Good only for: pure in-memory, very fast processing

channel.basic_qos(
    prefetch_size=0,    # size in bytes (0 = unlimited, most brokers ignore)
    prefetch_count=10,  # messages count
    global_qos=False,   # False = per consumer, True = per channel (avoid)
)
```

### 4.2 Prefetch Tuning

```python
# Optimal prefetch depends on:
# - Message processing time
# - Number of consumers
# - Network latency

# Rule of thumb:
# - Fast consumers (< 1ms): prefetch = 100-500
# - Normal consumers (1-100ms): prefetch = 10-50
# - Slow consumers (> 100ms): prefetch = 1-5

# Real-world tuning example for Java batch processing:
# @RabbitListener(queues = "orders", concurrency = "3-10", containerFactory = "batchFactory")
# + batch size 10, prefetch 20 → 200 messages in-flight per consumer instance

# Spring AMQP
@Bean
public SimpleRabbitListenerContainerFactory listenerFactory(ConnectionFactory cf) {
    SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
    factory.setConnectionFactory(cf);
    factory.setPrefetchCount(10);           // prefetch per consumer
    factory.setConcurrentConsumers(3);      // min 3 consumer threads
    factory.setMaxConcurrentConsumers(10);  // scale up to 10
    factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
    factory.setDefaultRequeueRejected(false); // nack goes to DLX
    return factory;
}
```

---

## 5. Transactions (AMQP tx)

```python
# AMQP Transactions: heavyweight, avoid in production
# tx.select → publish/ack → tx.commit
# → Throughput: ~1/10 of confirms approach

# Only use when: need to consume AND publish atomically in same transaction

channel.tx_select()  # start transaction
try:
    # Consume a message (ack)
    channel.basic_ack(delivery_tag)
    # Publish a new message
    channel.basic_publish(exchange='', routing_key='result_queue', body='result')
    channel.tx_commit()  # atomic commit
except Exception:
    channel.tx_rollback()  # rollback both ack and publish

# RECOMMENDATION: Use Publisher Confirms instead of transactions for publishing
# Use careful ack/nack logic instead of transactions for consuming
```

---

## 6. Flow Control

### 6.1 Credit-Based Flow Control (Internal)

```
RabbitMQ credit-based flow:
- Each connection/channel has a credit limit
- Publisher sends messages → credits decrease
- Broker drains (processes) messages → credits replenish
- Credit = 0 → publisher is blocked (back-pressure)

Blocked connections:
rabbitmqctl list_connections name state blocked_by
# state: running, blocked, blocking

# Connection.Blocked / Connection.Unblocked notifications
# pika: channel._connection.params.blocked_connection_timeout
```

### 6.2 Memory and Disk Alarms

```bash
# Memory alarm: when memory usage > vm_memory_high_watermark
# rabbitmq.conf
vm_memory_high_watermark.relative = 0.4    # 40% of available RAM
vm_memory_high_watermark.absolute = 2GB    # or absolute value

# Disk alarm: when free disk < disk_free_limit
disk_free_limit.relative = 1.0   # min free disk = 1x RAM size
disk_free_limit.absolute = 2GB

# When alarm triggers:
# - All publishing connections blocked
# - Consuming continues (to drain messages)
# - LOG: "alarm is set for memory"

# Monitor alarms
rabbitmq-diagnostics alarms
curl -u guest:guest http://localhost:15672/api/alarms
```

---

## 7. Poison Message Handling

### 7.1 Detecting Poison Messages

```python
# Poison message: message that consistently fails processing
# Without handling: NACK + requeue → infinite loop → CPU spike

# Strategy 1: Track retry count in headers
def on_message(ch, method, properties, body):
    headers = properties.headers or {}
    retry_count = headers.get('x-retry-count', 0)
    
    try:
        process(body)
        ch.basic_ack(delivery_tag=method.delivery_tag)
    
    except Exception as e:
        if retry_count < 3:
            # Re-publish with incremented counter (with delay)
            new_headers = dict(headers)
            new_headers['x-retry-count'] = retry_count + 1
            new_headers['x-last-error'] = str(e)
            
            # Use delayed exchange for backoff
            delay_ms = (2 ** retry_count) * 1000  # 1s, 2s, 4s
            ch.basic_publish(
                exchange='delayed',
                routing_key='task_queue',
                body=body,
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    headers={**new_headers, 'x-delay': delay_ms},
                )
            )
            ch.basic_ack(delivery_tag=method.delivery_tag)  # ack original
        else:
            # Dead letter
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

# Strategy 2: x-death header (auto-added by broker on dead-lettering)
def check_death_count(properties) -> int:
    headers = properties.headers or {}
    x_death = headers.get('x-death', [])
    if x_death:
        return x_death[0].get('count', 0)  # how many times dead-lettered
    return 0
```

### 7.2 Idempotency

```python
# Ensure same message processed only once (at-least-once delivery → exactly-once behavior)

import redis

r = redis.Redis()

def idempotent_process(message_id: str, body: bytes, process_fn) -> bool:
    """Returns True if processed, False if duplicate"""
    key = f"processed:{message_id}"
    
    # Atomic check-and-set
    # SET key 1 NX EX 86400 → only succeeds if key doesn't exist
    if not r.set(key, '1', nx=True, ex=86400):
        return False  # Already processed (duplicate)
    
    try:
        process_fn(body)
        return True
    except Exception:
        # Processing failed → remove idempotency key so it can be retried
        r.delete(key)
        raise

def on_message(ch, method, properties, body):
    message_id = properties.message_id or str(method.delivery_tag)
    
    try:
        processed = idempotent_process(
            message_id=message_id,
            body=body,
            process_fn=lambda b: handle_order(json.loads(b))
        )
        if not processed:
            print(f"Duplicate message {message_id}, skipping")
        ch.basic_ack(delivery_tag=method.delivery_tag)
    
    except Exception as e:
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
```

---

## 8. Message Ordering Guarantees

```
RabbitMQ ordering guarantees:

1. Per queue, per channel:
   - Messages published on SAME channel → delivered in order
   - Messages from DIFFERENT channels → no order guarantee

2. With multiple consumers:
   - No ordering across consumers
   - Each consumer sees messages in queue order, but processes independently

3. Requeue breaks ordering:
   - NACK + requeue=True → message goes to HEAD of queue
   - Can arrive before other pending messages

Patterns for strict ordering:
1. Single consumer per queue (no parallelism)
2. Consistent hashing exchange + single consumer per queue
3. Message sequence numbers + resequencing buffer in consumer
4. Partitioned queues (one per entity, e.g., user_id % N)
```

```python
# Strict ordering: dedicated queue per entity
class OrderedProcessor:
    def __init__(self, channel, entity_count: int = 10):
        self.channel = channel
        self.entity_count = entity_count
        
        # Create N queues, each handles 1/N of entities
        for i in range(entity_count):
            channel.queue_declare(queue=f'orders_shard_{i}', durable=True)
            channel.basic_qos(prefetch_count=1)  # single consumer per shard
    
    def publish(self, order: dict):
        # Route to shard based on entity ID
        shard = hash(order['user_id']) % self.entity_count
        queue = f'orders_shard_{shard}'
        
        self.channel.basic_publish(
            exchange='',
            routing_key=queue,
            body=json.dumps(order),
            properties=pika.BasicProperties(delivery_mode=2)
        )
    
    def start_consumers(self):
        for i in range(self.entity_count):
            self.channel.basic_consume(
                queue=f'orders_shard_{i}',
                on_message_callback=self.process_ordered,
            )
        self.channel.start_consuming()
```

---

## 9. Reliability Checklist

```
Publisher side:
□ Exchange declared durable=True
□ Queue declared durable=True
□ Messages published with delivery_mode=2 (persistent)
□ Publisher Confirms enabled
□ Return handler for unroutable messages (mandatory=True)
□ Outbox pattern for DB+publish atomicity

Consumer side:
□ auto_ack=False (manual acknowledgement)
□ prefetch_count set appropriately (not 0)
□ NACK with requeue=False for permanent errors
□ DLX configured for failed messages
□ Retry logic with exponential backoff
□ Idempotency check for at-least-once delivery

Infrastructure:
□ Durable queues with persistent messages
□ Quorum queues for HA (not classic mirrored)
□ Multiple nodes (cluster)
□ Disk alarm thresholds configured
□ Memory alarm thresholds configured
□ Connection heartbeat enabled
□ Consumer timeout configured
```

## Ghi chú – Topics tiếp theo

- **Clustering**: Erlang cluster setup → `rabbitmq_production.md`
- **Quorum Queues**: Raft consensus, leader election → `rabbitmq_production.md`
- **Policies**: HA policy, TTL policy via rabbitmqctl → `rabbitmq_production.md`
- **Federation & Shovel**: cross-datacenter messaging → `rabbitmq_production.md`
- **Spring AMQP deep dive**: @RabbitListener, error handlers, batch → `rabbitmq_production.md`
- **Monitoring**: Prometheus metrics, Grafana dashboards → `rabbitmq_production.md`
