# RabbitMQ Messaging Patterns

## 1. Work Queue (Task Queue)

### 1.1 What & How

**Work Queue** = nhiều consumer cùng nhận từ 1 queue để xử lý song song. Mỗi message chỉ đến 1 consumer (round-robin mặc định, hoặc fair dispatch với prefetch).

```
Producer → [task_queue] → Consumer 1 (message 1, 3, 5, ...)
                        → Consumer 2 (message 2, 4, 6, ...)
```

```python
# producer.py — gửi nhiều tasks
import pika, json, time

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()
channel.queue_declare(queue='task_queue', durable=True)

tasks = [
    {'id': 1, 'type': 'resize_image', 'url': 'https://example.com/img1.jpg'},
    {'id': 2, 'type': 'send_email',   'to': 'user@example.com'},
    {'id': 3, 'type': 'resize_image', 'url': 'https://example.com/img2.jpg'},
]

for task in tasks:
    channel.basic_publish(
        exchange='',
        routing_key='task_queue',
        body=json.dumps(task),
        properties=pika.BasicProperties(delivery_mode=2),  # persistent
    )
    print(f"[x] Sent task {task['id']}")

connection.close()
```

```python
# worker.py — múltiple workers compete for tasks
import pika, json, time

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()
channel.queue_declare(queue='task_queue', durable=True)

# CRITICAL: prefetch=1 → worker nhận task mới chỉ khi ack task cũ
# Without this: round-robin assigns tasks even to busy workers
channel.basic_qos(prefetch_count=1)

def process_task(ch, method, properties, body):
    task = json.loads(body)
    print(f"[x] Processing task {task['id']}: {task['type']}")
    
    try:
        if task['type'] == 'resize_image':
            time.sleep(2)  # simulate heavy work
        elif task['type'] == 'send_email':
            time.sleep(0.5)
        
        # Manual ACK: confirm message processed
        ch.basic_ack(delivery_tag=method.delivery_tag)
        print(f"[✓] Done task {task['id']}")
    
    except Exception as e:
        # NACK + requeue=False → send to DLX if configured
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
        print(f"[✗] Failed task {task['id']}: {e}")

channel.basic_consume(queue='task_queue', on_message_callback=process_task, auto_ack=False)
channel.start_consuming()
```

### 1.2 Fair Dispatch vs Round-Robin

```
Round-Robin (default, no prefetch):
  Task 1 → Worker 1 (even if Worker 1 is busy with heavy task)
  Task 2 → Worker 2
  Task 3 → Worker 1 (still busy!)
  Problem: load imbalance

Fair Dispatch (prefetch_count=1):
  Task 1 → Worker 1 (starts processing)
  Task 2 → Worker 2 (starts processing)
  Task 3 → Worker 2 (Worker 2 finished first → gets next task)
  Result: even load based on capacity
```

---

## 2. Publish/Subscribe (Fanout)

```python
# publisher.py — broadcast events
connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()
channel.exchange_declare(exchange='events', exchange_type='fanout', durable=True)

event = {'type': 'user.registered', 'user_id': 123, 'email': 'alice@example.com'}
channel.basic_publish(
    exchange='events',
    routing_key='',     # fanout ignores routing_key
    body=json.dumps(event),
    properties=pika.BasicProperties(
        delivery_mode=2,
        content_type='application/json',
    )
)
```

```python
# subscriber_email.py — one of many subscribers
connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()
channel.exchange_declare(exchange='events', exchange_type='fanout', durable=True)

# Exclusive queue: auto-name, deleted when connection closes
# Each subscriber gets its OWN queue bound to exchange
result = channel.queue_declare(queue='', exclusive=True)
queue_name = result.method.queue  # e.g., 'amq.gen-XNpRDt1f...'

channel.queue_bind(exchange='events', queue=queue_name)

def on_event(ch, method, properties, body):
    event = json.loads(body)
    print(f"[Email] Send welcome email to {event['email']}")
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_consume(queue=queue_name, on_message_callback=on_event)
channel.start_consuming()

# subscriber_analytics.py — another subscriber, same exchange
# ... same setup but different queue_name
# → Both receive ALL events from the exchange
```

---

## 3. Topic Routing

```python
# Microservice event routing with topic exchange

EXCHANGE = 'microservices'

# Setup
channel.exchange_declare(exchange=EXCHANGE, exchange_type='topic', durable=True)

# Service: Order Service — interested in all order events
channel.queue_declare(queue='order-service', durable=True)
channel.queue_bind(exchange=EXCHANGE, queue='order-service', routing_key='order.#')

# Service: Payment Service — interested in payment events
channel.queue_declare(queue='payment-service', durable=True)
channel.queue_bind(exchange=EXCHANGE, queue='payment-service', routing_key='order.payment.*')

# Service: Notification Service — all critical events
channel.queue_declare(queue='notification-service', durable=True)
channel.queue_bind(exchange=EXCHANGE, queue='notification-service', routing_key='*.critical')
channel.queue_bind(exchange=EXCHANGE, queue='notification-service', routing_key='user.*')

# Service: Audit Log — everything
channel.queue_declare(queue='audit-log', durable=True)
channel.queue_bind(exchange=EXCHANGE, queue='audit-log', routing_key='#')

# Events published by various services:
events = [
    ('order.created',           {'order_id': 1}),       # → order-service, audit-log
    ('order.payment.completed', {'order_id': 1}),       # → order-service, payment-service, audit-log
    ('order.payment.failed',    {'order_id': 1}),       # → order-service, payment-service, audit-log
    ('order.critical',          {'order_id': 1}),       # → order-service, notification-service, audit-log
    ('user.registered',         {'user_id': 2}),        # → notification-service, audit-log
    ('inventory.updated',       {'product_id': 5}),     # → audit-log only
]

for routing_key, payload in events:
    channel.basic_publish(
        exchange=EXCHANGE,
        routing_key=routing_key,
        body=json.dumps(payload),
        properties=pika.BasicProperties(delivery_mode=2)
    )
```

---

## 4. Dead Letter Exchange (DLX)

### 4.1 What & Why

**Dead Letter** = message không thể xử lý thành công vì:
- Consumer reject/nack với `requeue=False`
- Message vượt quá TTL trong queue
- Queue đạt `x-max-length` → message bị drop (nếu `x-overflow=reject-publish-dlx`)

**DLX** = exchange nhận dead letters → route đến dead letter queue để:
- Inspect failed messages
- Manual retry / alert
- Không mất message

```
Normal Flow:
Producer → [task_queue] → Consumer (fails) → nack(requeue=False)
                                            ↓
                               Dead Letter Exchange
                                            ↓
                              [task_queue.dlq] → Admin/Retry Worker
```

### 4.2 Implementation

```python
import pika, json

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()

# Step 1: Setup Dead Letter Exchange
channel.exchange_declare(
    exchange='dlx',
    exchange_type='direct',
    durable=True,
)

# Step 2: Setup Dead Letter Queue
channel.queue_declare(
    queue='task_queue.dlq',
    durable=True,
    arguments={
        # DLQ messages can also expire/be re-dead-lettered
        'x-message-ttl': 86400000,  # keep for 24 hours
    }
)
channel.queue_bind(
    exchange='dlx',
    queue='task_queue.dlq',
    routing_key='task_queue.failed'  # routing key for DLX
)

# Step 3: Main queue with DLX configured
channel.queue_declare(
    queue='task_queue',
    durable=True,
    arguments={
        'x-dead-letter-exchange': 'dlx',
        'x-dead-letter-routing-key': 'task_queue.failed',
        'x-message-ttl': 30000,   # messages expire after 30s → also dead-lettered
        'x-max-length': 10000,
    }
)

# Consumer — NACK moves message to DLX
def on_message(ch, method, properties, body):
    task = json.loads(body)
    
    # Track retry count using custom header
    headers = properties.headers or {}
    retry_count = headers.get('x-retry-count', 0)
    
    try:
        process_task(task)
        ch.basic_ack(delivery_tag=method.delivery_tag)
    
    except TemporaryError as e:
        if retry_count < 3:
            # Requeue with incremented retry count
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
            # Re-publish with updated header (simple retry logic)
            channel.basic_publish(
                exchange='',
                routing_key='task_queue',
                body=body,
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    headers={'x-retry-count': retry_count + 1},
                )
            )
        else:
            # Max retries → dead letter (nack without requeue)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
    
    except PermanentError:
        # Immediately dead letter
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

# DLQ Consumer — manual inspection / alerting
def on_dead_letter(ch, method, properties, body):
    headers = properties.headers or {}
    print(f"[DLQ] Dead message received:")
    print(f"  Original routing key: {headers.get('x-first-death-routing-key')}")
    print(f"  Reason: {headers.get('x-first-death-reason')}")  # expired/rejected/maxlen
    print(f"  Queue: {headers.get('x-first-death-queue')}")
    print(f"  Body: {body}")
    # Send alert, store in database, etc.
    ch.basic_ack(delivery_tag=method.delivery_tag)
```

### 4.3 Retry Pattern với Delay (Using DLX + TTL)

```python
# Delayed retry: requeue after N seconds using DLX trick
# Queue A (main) → NACK → DLX → Wait Queue (x-message-ttl=5000) → DLX → Queue A

def setup_retry_queues(channel, queue_name, retry_delays_ms: list):
    """
    Create retry queues with exponential backoff:
    retry_delays_ms = [5000, 30000, 300000] = 5s, 30s, 5min
    """
    main_exchange = f"{queue_name}.retry.fanout"
    channel.exchange_declare(exchange=main_exchange, exchange_type='fanout', durable=True)
    
    for i, delay_ms in enumerate(retry_delays_ms):
        wait_queue = f"{queue_name}.retry.{i}"
        channel.queue_declare(
            queue=wait_queue,
            durable=True,
            arguments={
                'x-message-ttl': delay_ms,              # expire after delay
                'x-dead-letter-exchange': main_exchange, # expired → back to main
                'x-dead-letter-routing-key': queue_name,
            }
        )
    
    # Main queue receives from the retry exchange too
    channel.queue_bind(exchange=main_exchange, queue=queue_name)

def publish_with_retry(channel, queue_name, body, retry_count=0, max_retries=3):
    retry_delays = [5000, 30000, 300000]  # 5s, 30s, 5min
    
    if retry_count < max_retries:
        wait_queue = f"{queue_name}.retry.{retry_count}"
        channel.basic_publish(
            exchange='',
            routing_key=wait_queue,
            body=body,
            properties=pika.BasicProperties(
                delivery_mode=2,
                headers={'x-retry-count': retry_count + 1},
            )
        )
    else:
        # Send to DLQ
        channel.basic_publish(exchange='dlx', routing_key=f"{queue_name}.failed", body=body)
```

---

## 5. RPC Pattern

### 5.1 What & How

**RPC over RabbitMQ** = request/response pattern. Client gửi request → Server xử lý → trả response về client queue.

```
Client                        Server
  │                             │
  │── request ──────────────>   │
  │   (reply_to=callback_queue) │
  │   (correlation_id=123)      │
  │                             │ process
  │<── response ──────────────  │
  │   (correlation_id=123)      │
  │
  │ Match correlation_id to pending request
```

```python
# rpc_server.py
import pika, json

connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
channel = connection.channel()
channel.queue_declare(queue='rpc_queue', durable=True)
channel.basic_qos(prefetch_count=1)

def fibonacci(n):
    if n < 0:
        raise ValueError("Fibonacci must be non-negative")
    if n == 0: return 0
    if n == 1: return 1
    return fibonacci(n-1) + fibonacci(n-2)

def on_request(ch, method, props, body):
    request = json.loads(body)
    print(f"[RPC] Request: {request}")
    
    try:
        result = fibonacci(request['n'])
        response = {'result': result, 'error': None}
    except Exception as e:
        response = {'result': None, 'error': str(e)}
    
    # Send response to reply_to queue with matching correlation_id
    ch.basic_publish(
        exchange='',
        routing_key=props.reply_to,          # client's callback queue
        body=json.dumps(response),
        properties=pika.BasicProperties(
            correlation_id=props.correlation_id,  # echo back for matching
        )
    )
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_consume(queue='rpc_queue', on_message_callback=on_request)
channel.start_consuming()
```

```python
# rpc_client.py
import pika, json, uuid, threading

class RpcClient:
    def __init__(self):
        self.connection = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
        self.channel = self.connection.channel()
        
        # Exclusive callback queue for this client
        result = self.channel.queue_declare(queue='', exclusive=True)
        self.callback_queue = result.method.queue
        
        self.pending = {}  # correlation_id → threading.Event + result
        
        # Start consuming responses
        self.channel.basic_consume(
            queue=self.callback_queue,
            on_message_callback=self._on_response,
            auto_ack=True,
        )
        
        # Non-blocking consume in background thread
        self._thread = threading.Thread(target=self._consume_loop, daemon=True)
        self._thread.start()
    
    def _consume_loop(self):
        self.connection.process_data_events(time_limit=None)
    
    def _on_response(self, ch, method, props, body):
        corr_id = props.correlation_id
        if corr_id in self.pending:
            event, container = self.pending[corr_id]
            container['response'] = json.loads(body)
            event.set()
    
    def call(self, payload: dict, timeout: float = 30.0) -> dict:
        corr_id = str(uuid.uuid4())
        event = threading.Event()
        container = {}
        self.pending[corr_id] = (event, container)
        
        self.channel.basic_publish(
            exchange='',
            routing_key='rpc_queue',
            body=json.dumps(payload),
            properties=pika.BasicProperties(
                reply_to=self.callback_queue,
                correlation_id=corr_id,
                expiration='30000',  # request TTL
            )
        )
        
        if not event.wait(timeout):
            del self.pending[corr_id]
            raise TimeoutError(f"RPC timeout after {timeout}s")
        
        del self.pending[corr_id]
        return container['response']

# Usage
client = RpcClient()
response = client.call({'n': 30})
print(f"Fibonacci(30) = {response['result']}")  # 832040
```

### 5.2 Java RPC (Spring AMQP)

```java
// RPC Server
@Component
public class FibonacciServer {
    
    @RabbitListener(queues = "rpc_queue")
    public String fibonacci(@Payload String requestJson,
                             @Header(AmqpHeaders.CORRELATION_ID) String correlationId,
                             @Header(AmqpHeaders.REPLY_TO) String replyTo) {
        
        Map<String, Object> request = objectMapper.readValue(requestJson, Map.class);
        int n = (Integer) request.get("n");
        
        Map<String, Object> response = new HashMap<>();
        response.put("result", fib(n));
        response.put("correlationId", correlationId);
        
        return objectMapper.writeValueAsString(response);
    }
    
    private long fib(int n) {
        if (n <= 1) return n;
        return fib(n-1) + fib(n-2);
    }
}

// RPC Client
@Service
public class FibonacciClient {
    
    @Autowired
    private RabbitTemplate rabbitTemplate;
    
    public Long fibonacci(int n) {
        Map<String, Object> request = Map.of("n", n);
        
        // RabbitTemplate.convertSendAndReceive = publish + wait for reply
        Object result = rabbitTemplate.convertSendAndReceive(
            "rpc_queue",
            objectMapper.writeValueAsString(request)
        );  // blocks up to replyTimeout (default 5s)
        
        Map<String, Object> response = objectMapper.readValue(
            (String) result, Map.class
        );
        return Long.valueOf(response.get("result").toString());
    }
}
```

---

## 6. Priority Queue

```python
# Priority Queue: higher priority messages delivered first
channel.queue_declare(
    queue='priority_tasks',
    durable=True,
    arguments={
        'x-max-priority': 10,  # max priority level (0-10)
        # Keep small: each priority level = separate data structure
    }
)

# Publish with priority
def publish_priority(channel, task: dict, priority: int):
    channel.basic_publish(
        exchange='',
        routing_key='priority_tasks',
        body=json.dumps(task),
        properties=pika.BasicProperties(
            delivery_mode=2,
            priority=priority,  # 0 = lowest, 10 = highest
        )
    )

# Publish various priority tasks
publish_priority(channel, {'type': 'batch_report', 'id': 1}, priority=1)    # low
publish_priority(channel, {'type': 'email_send', 'id': 2}, priority=5)      # medium
publish_priority(channel, {'type': 'payment_process', 'id': 3}, priority=9) # high
publish_priority(channel, {'type': 'fraud_check', 'id': 4}, priority=10)    # critical

# Consumer receives in priority order: fraud_check → payment → email → report
# NOTE: Priority only works when messages are QUEUED (not if consumed immediately)
# Set prefetch_count > 1 for priority to be effective
channel.basic_qos(prefetch_count=10)
```

---

## 7. Consistent Hashing Exchange

```bash
# Plugin: rabbitmq_consistent_hash_exchange
# Route messages consistently based on routing key hash
# Useful for: ensure related messages go to same queue (ordering per entity)

rabbitmq-plugins enable rabbitmq_consistent_hash_exchange

# Declare exchange
channel.exchange_declare(
    exchange='consistent_hash',
    exchange_type='x-consistent-hash',
    durable=True,
)

# Bind queues with weight (higher weight = more messages)
# Weight is the routing_key of the binding (not of the message!)
channel.queue_bind(exchange='consistent_hash', queue='queue1', routing_key='1')  # weight 1
channel.queue_bind(exchange='consistent_hash', queue='queue2', routing_key='2')  # weight 2 (2x more)
channel.queue_bind(exchange='consistent_hash', queue='queue3', routing_key='1')  # weight 1

# Messages with same routing_key ALWAYS go to same queue
# Good for: user-specific ordering (all events for user:123 → same queue)
channel.basic_publish(
    exchange='consistent_hash',
    routing_key='user:123',  # always same queue
    body=json.dumps({'action': 'purchase', 'user_id': 123})
)
```

---

## 8. Delayed Messaging Plugin

```bash
# Plugin: rabbitmq_delayed_message_exchange
rabbitmq-plugins enable rabbitmq_delayed_message_exchange
```

```python
# Send message with a delay
channel.exchange_declare(
    exchange='delayed',
    exchange_type='x-delayed-message',
    durable=True,
    arguments={'x-delayed-type': 'direct'}  # underlying routing
)

channel.queue_declare(queue='scheduled_tasks', durable=True)
channel.queue_bind(exchange='delayed', queue='scheduled_tasks', routing_key='scheduled')

# Publish with delay header
def publish_delayed(channel, body: dict, delay_ms: int):
    channel.basic_publish(
        exchange='delayed',
        routing_key='scheduled',
        body=json.dumps(body),
        properties=pika.BasicProperties(
            delivery_mode=2,
            headers={'x-delay': delay_ms},  # delay in milliseconds
        )
    )

# Schedule for later
publish_delayed(channel, {'type': 'reminder', 'user_id': 123}, delay_ms=3600000)  # 1 hour
publish_delayed(channel, {'type': 'trial_expire', 'user_id': 456}, delay_ms=86400000)  # 24h
```

---

## 9. Alternate Exchange

```python
# Alternate Exchange: catch unroutable messages
# When a message has no matching queue binding → sent to alternate exchange

channel.exchange_declare(exchange='main', exchange_type='direct', durable=True,
    arguments={'alternate-exchange': 'unrouted'})

channel.exchange_declare(exchange='unrouted', exchange_type='fanout', durable=True)

channel.queue_declare(queue='main_queue', durable=True)
channel.queue_bind(exchange='main', queue='main_queue', routing_key='known_key')

channel.queue_declare(queue='catch_all', durable=True)
channel.queue_bind(exchange='unrouted', queue='catch_all')

# Message with unknown routing key → goes to 'catch_all' via 'unrouted' exchange
channel.basic_publish(exchange='main', routing_key='unknown_key', body='test')
```

---

## 10. Exchange-to-Exchange Binding

```python
# E2E binding: chain exchanges for complex routing

# Source exchange: receives all events
channel.exchange_declare(exchange='all_events', exchange_type='topic', durable=True)

# Sub-exchange: only payment events
channel.exchange_declare(exchange='payment_events', exchange_type='fanout', durable=True)

# Bind exchange to exchange!
channel.exchange_bind(
    destination='payment_events',
    source='all_events',
    routing_key='payment.*',  # filter
)

# Queues bound to sub-exchange
channel.queue_bind(exchange='payment_events', queue='payment_service')
channel.queue_bind(exchange='payment_events', queue='payment_analytics')

# Publisher sends to source exchange
channel.basic_publish(exchange='all_events', routing_key='payment.completed', body='...')
# → matches 'payment.*' → routed to payment_events → fanout → both queues
```

---

## Ghi chú – Topics tiếp theo

- **Publisher Confirms**: guarantee messages reach broker → `rabbitmq_reliability.md`
- **Consumer Acks**: guarantee processing → `rabbitmq_reliability.md`
- **Message durability**: survive restarts → `rabbitmq_reliability.md`
- **Prefetch & QoS**: flow control → `rabbitmq_reliability.md`
- **Transactions (AMQP tx)**: → `rabbitmq_reliability.md`
- **Clustering**: → `rabbitmq_production.md`
- **Quorum Queues**: Raft replication → `rabbitmq_production.md`
- **Spring AMQP deep dive**: @RabbitListener, error handlers → `rabbitmq_production.md`
