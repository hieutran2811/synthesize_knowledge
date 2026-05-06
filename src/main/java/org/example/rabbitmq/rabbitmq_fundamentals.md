# RabbitMQ Fundamentals

## 1. RabbitMQ là gì? (What)

**RabbitMQ** là một **message broker** mã nguồn mở, implement **AMQP 0-9-1** (Advanced Message Queuing Protocol). Nó đóng vai trò trung gian nhận, lưu trữ và chuyển tiếp messages giữa các producers và consumers.

```
Producer → [RabbitMQ Broker] → Consumer

Broker gồm:
├── Virtual Host (vhost): namespace cô lập (như database)
│   ├── Exchange: nhận messages từ producer, route đến queues
│   ├── Queue: buffer lưu messages chờ consumer
│   └── Binding: quy tắc liên kết exchange → queue
└── Connection → Channel (multiplexed connections)
```

---

## 2. Tại sao cần RabbitMQ? (Why)

```
Problems solved:

1. Temporal Decoupling:
   Producer và Consumer không cần online cùng lúc
   → Producer gửi message → RabbitMQ giữ → Consumer nhận khi sẵn sàng

2. Load Leveling:
   Traffic spike → Messages queue up → Consumers xử lý đều đặn
   → Không cần scale up consumer tức thì

3. Fanout / Pub-Sub:
   1 event → nhiều consumers xử lý độc lập
   → Order placed → notify email, update inventory, analytics (tất cả cùng lúc)

4. Work Distribution:
   N workers cùng consume từ 1 queue → tự động load balance
   → Round-robin mặc định

5. Protocol Flexibility:
   AMQP, MQTT (IoT), STOMP, HTTP (Management API)
   → Connect từ bất kỳ ngôn ngữ/platform

6. Complex Routing:
   Route theo routing key, pattern, headers
   → Không cần consumer biết ai gửi, chỉ cần biết mình nhận loại nào
```

---

## 3. AMQP 0-9-1 Protocol (How)

### 3.1 AMQP Model

```
AMQP 0-9-1 concepts:

Message:
├── Payload (body): actual data (binary, JSON, Protobuf, ...)
└── Properties (metadata):
    ├── content_type: "application/json"
    ├── content_encoding: "utf-8"
    ├── delivery_mode: 1=transient, 2=persistent
    ├── priority: 0-255
    ├── correlation_id: RPC response linking
    ├── reply_to: RPC callback queue
    ├── expiration: TTL in milliseconds (string)
    ├── message_id: unique ID
    ├── timestamp: Unix timestamp
    ├── type: message type hint
    ├── user_id: publishing user
    ├── app_id: application identifier
    └── headers: Map<String, Object> (custom)

Connection:
├── TCP connection to broker (expensive to create)
├── TLS negotiation
└── Channels: lightweight virtual connections (cheap, reusable)
    → Each thread should use its own channel
    → Max channels per connection: configurable (default 2047)
```

### 3.2 Connection & Channel

```python
# Python (pika)
import pika

# Connection (one per process, expensive)
connection_params = pika.ConnectionParameters(
    host='localhost',
    port=5672,
    virtual_host='/',
    credentials=pika.PlainCredentials('user', 'password'),
    heartbeat=600,          # keepalive interval (seconds)
    blocked_connection_timeout=300,
    connection_attempts=3,
    retry_delay=5,
)
connection = pika.BlockingConnection(connection_params)

# Channel (one per thread, lightweight)
channel = connection.channel()

# Always close properly
try:
    # ... do work ...
    pass
finally:
    channel.close()
    connection.close()
```

```java
// Java (Spring AMQP / RabbitMQ Java Client)
import com.rabbitmq.client.*;

ConnectionFactory factory = new ConnectionFactory();
factory.setHost("localhost");
factory.setPort(5672);
factory.setVirtualHost("/");
factory.setUsername("guest");
factory.setPassword("guest");
factory.setConnectionTimeout(30000);
factory.setRequestedHeartbeat(60);

// Connection pool (use one connection, multiple channels)
Connection connection = factory.newConnection();
Channel channel = connection.createChannel();
```

---

## 4. Exchanges (Components)

### 4.1 Default (Nameless) Exchange

```python
# Nameless exchange routes directly to queue by routing_key = queue_name
channel.queue_declare(queue='hello')

# Send to queue 'hello' via default exchange
channel.basic_publish(
    exchange='',           # empty string = default exchange
    routing_key='hello',   # must equal queue name
    body='Hello World!'
)
```

### 4.2 Direct Exchange

```
Direct Exchange: route nếu routing_key khớp chính xác với binding key

Producer → Direct Exchange → Queue A (if routing_key = "error")
                           → Queue B (if routing_key = "warning")
                           → Queue C (if routing_key = "info")
```

```python
# Declare direct exchange
channel.exchange_declare(
    exchange='logs_direct',
    exchange_type='direct',
    durable=True,
)

# Bind queue to exchange with routing key
channel.queue_bind(
    exchange='logs_direct',
    queue='error_logs',
    routing_key='error'
)
channel.queue_bind(
    exchange='logs_direct',
    queue='all_logs',
    routing_key='error'    # Multiple queues can share same routing key
)
channel.queue_bind(
    exchange='logs_direct',
    queue='all_logs',
    routing_key='warning'  # Same queue, multiple binding keys
)

# Publish with routing key
channel.basic_publish(
    exchange='logs_direct',
    routing_key='error',
    body='Disk full!',
    properties=pika.BasicProperties(
        delivery_mode=pika.spec.PERSISTENT_DELIVERY_MODE,  # 2 = persistent
        content_type='text/plain',
    )
)
```

### 4.3 Fanout Exchange

```
Fanout Exchange: broadcast đến TẤT CẢ queues bound, bỏ qua routing_key

Producer → Fanout Exchange → Queue 1 (mobile notifications)
                           → Queue 2 (email notifications)
                           → Queue 3 (analytics)
```

```python
channel.exchange_declare(exchange='notifications', exchange_type='fanout', durable=True)

# Subscriber creates temporary queue and binds to fanout
result = channel.queue_declare(queue='', exclusive=True)  # auto-named, auto-deleted
queue_name = result.method.queue

channel.queue_bind(exchange='notifications', queue=queue_name)

# Publish (routing_key ignored)
channel.basic_publish(exchange='notifications', routing_key='', body='New user signed up!')
```

### 4.4 Topic Exchange

```
Topic Exchange: route theo pattern matching với routing_key

Routing key format: word1.word2.word3 (dot-separated words)
Binding pattern:
  * = exactly one word
  # = zero or more words

Examples:
  "kern.critical" matches binding "kern.*" ✓
  "kern.critical" matches binding "*.critical" ✓
  "kern.critical" matches binding "#" ✓
  "kern.critical.alert" does NOT match "kern.*" ✗ (only 1 word after kern)
  "kern.critical.alert" matches "kern.#" ✓
```

```python
channel.exchange_declare(exchange='topic_logs', exchange_type='topic', durable=True)

# Bindings for different subscribers:
# Receive all kernel messages:
channel.queue_bind(exchange='topic_logs', queue='kernel_queue', routing_key='kern.#')

# Receive all critical messages regardless of source:
channel.queue_bind(exchange='topic_logs', queue='critical_queue', routing_key='*.critical')

# Receive everything:
channel.queue_bind(exchange='topic_logs', queue='all_queue', routing_key='#')

# Publish microservice events
channel.basic_publish(
    exchange='topic_logs',
    routing_key='order.created',   # → received by "order.#" and "#"
    body='{"order_id": 123}'
)
channel.basic_publish(
    exchange='topic_logs',
    routing_key='order.payment.failed',  # → "order.#" and "#"
    body='{"order_id": 123, "reason": "card_declined"}'
)
channel.basic_publish(
    exchange='topic_logs',
    routing_key='user.registered',  # → "user.*" and "#"
    body='{"user_id": 456}'
)
```

### 4.5 Headers Exchange

```python
# Route based on message headers, NOT routing key
channel.exchange_declare(exchange='header_exchange', exchange_type='headers', durable=True)

# Bind with header matching
# x-match: 'all' = all headers must match (AND)
# x-match: 'any' = any header must match (OR)
channel.queue_bind(
    exchange='header_exchange',
    queue='pdf_reports',
    arguments={
        'x-match': 'all',
        'format': 'pdf',
        'type': 'report',
    }
)
channel.queue_bind(
    exchange='header_exchange',
    queue='urgent_any',
    arguments={
        'x-match': 'any',
        'priority': 'urgent',
        'format': 'pdf',
    }
)

# Publish with headers
channel.basic_publish(
    exchange='header_exchange',
    routing_key='',  # ignored
    body='PDF report content',
    properties=pika.BasicProperties(
        headers={
            'format': 'pdf',
            'type': 'report',
        }
    )
)
```

---

## 5. Queues (Components)

### 5.1 Queue Properties

```python
channel.queue_declare(
    queue='task_queue',
    durable=True,         # survive broker restart
    exclusive=False,      # only 1 connection can use (auto-delete on disconnect)
    auto_delete=False,    # delete when no consumers
    arguments={
        # Message TTL (all messages in queue)
        'x-message-ttl': 60000,       # 60 seconds in ms

        # Queue TTL (auto-delete if unused)
        'x-expires': 1800000,         # 30 minutes

        # Max length (drop oldest when full)
        'x-max-length': 10000,
        'x-overflow': 'drop-head',    # or 'reject-publish', 'reject-publish-dlx'

        # Max size in bytes
        'x-max-length-bytes': 104857600,  # 100MB

        # Dead Letter Exchange
        'x-dead-letter-exchange': 'dlx',
        'x-dead-letter-routing-key': 'failed',

        # Priority queue
        'x-max-priority': 10,         # 0-255, but keep small (0-10)

        # Lazy queue (messages stored on disk immediately)
        'x-queue-mode': 'lazy',       # deprecated in 3.12+

        # Queue type
        'x-queue-type': 'quorum',     # 'classic', 'quorum', 'stream'

        # Leader locator (for quorum queues)
        'x-queue-leader-locator': 'balanced',
    }
)
```

### 5.2 Queue Types

```
Classic Queue:
├── Default type (FIFO)
├── Optional mirroring (deprecated - use Quorum)
└── Good for: low message count, temporary queues

Quorum Queue (recommended for HA):
├── Raft-based consensus replication
├── Data replicated on majority of nodes
├── Automatic leader election on failure
└── Good for: production workloads, critical data

Stream Queue (RabbitMQ 3.9+):
├── Append-only log (like Kafka topics)
├── Consumers can replay from any offset
├── High throughput
└── Good for: event sourcing, fan-out at scale
```

---

## 6. Virtual Hosts

```bash
# VHost = logical separation (like database schema)
# Default vhost: /
# Each vhost has its own: exchanges, queues, bindings, permissions

# rabbitmqctl
rabbitmqctl add_vhost production
rabbitmqctl add_vhost staging
rabbitmqctl add_vhost development

# Permissions: configure | write | read
rabbitmqctl set_permissions -p production myapp ".*" ".*" ".*"
# myapp user: configure anything, write anything, read anything in /production

# List vhosts
rabbitmqctl list_vhosts

# Connect to specific vhost
connection_params = pika.ConnectionParameters(
    virtual_host='/production',  # or just 'production'
    ...
)
```

---

## 7. Management UI & CLI

### 7.1 Management Plugin

```bash
# Enable management plugin
rabbitmq-plugins enable rabbitmq_management

# Access: http://localhost:15672
# Default credentials: guest/guest (only from localhost!)

# Management UI features:
# - Overview: connections, channels, queues, exchanges
# - Exchanges: declare, delete, publish test messages
# - Queues: declare, purge, delete, get messages
# - Connections: list, close
# - Channels: list
# - Admin: users, vhosts, permissions, policies
# - Nodes: cluster members

# Management REST API
curl -u guest:guest http://localhost:15672/api/overview | python3 -m json.tool
curl -u guest:guest http://localhost:15672/api/queues
curl -u guest:guest http://localhost:15672/api/queues/%2F/task_queue  # %2F = /
curl -u guest:guest -X DELETE http://localhost:15672/api/queues/%2F/old_queue
```

### 7.2 rabbitmqctl CLI

```bash
# Status
rabbitmqctl status
rabbitmqctl cluster_status
rabbitmqctl node_health_check

# Queues
rabbitmqctl list_queues name messages consumers durable auto_delete
rabbitmqctl list_queues -p /production name messages

# Exchanges
rabbitmqctl list_exchanges name type durable auto_delete
rabbitmqctl list_bindings

# Users
rabbitmqctl list_users
rabbitmqctl add_user myuser mypassword
rabbitmqctl set_user_tags myuser administrator
rabbitmqctl delete_user guest              # Remove default guest user!
rabbitmqctl change_password myuser newpass

# Permissions
rabbitmqctl set_permissions -p / myuser ".*" ".*" ".*"
rabbitmqctl list_permissions -p /

# Purge queue (delete all messages)
rabbitmqctl purge_queue task_queue

# Policy
rabbitmqctl set_policy ha-all "^ha\." '{"ha-mode":"all"}' --apply-to queues

# Reset node
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl start_app

# rabbitmq-diagnostics (newer commands)
rabbitmq-diagnostics status
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_port_connectivity
rabbitmq-diagnostics memory_breakdown
```

---

## 8. Basic Publish/Consume Pattern

### 8.1 Python (pika)

```python
# producer.py
import pika
import json
import uuid
from datetime import datetime

def get_connection():
    params = pika.ConnectionParameters(
        host='localhost',
        credentials=pika.PlainCredentials('guest', 'guest'),
        heartbeat=600,
    )
    return pika.BlockingConnection(params)

def publish_task(task_data: dict):
    connection = get_connection()
    channel = connection.channel()
    
    channel.queue_declare(queue='task_queue', durable=True)
    
    message = json.dumps({
        'id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        **task_data
    })
    
    channel.basic_publish(
        exchange='',
        routing_key='task_queue',
        body=message,
        properties=pika.BasicProperties(
            delivery_mode=pika.spec.PERSISTENT_DELIVERY_MODE,  # persist to disk
            content_type='application/json',
            message_id=str(uuid.uuid4()),
        )
    )
    print(f"[x] Sent: {message}")
    
    connection.close()

# consumer.py
def start_consumer():
    connection = get_connection()
    channel = connection.channel()
    
    channel.queue_declare(queue='task_queue', durable=True)
    
    # QoS: process only 1 message at a time (fair dispatch)
    channel.basic_qos(prefetch_count=1)
    
    def on_message(ch, method, properties, body):
        data = json.loads(body)
        print(f"[x] Received: {data}")
        
        try:
            process_task(data)
            # Acknowledge: tell broker this message is done
            ch.basic_ack(delivery_tag=method.delivery_tag)
        except Exception as e:
            print(f"[!] Failed: {e}")
            # Reject and requeue (or send to DLX)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
    
    channel.basic_consume(
        queue='task_queue',
        on_message_callback=on_message,
        auto_ack=False,  # manual ack required
    )
    
    print('[*] Waiting for messages. CTRL+C to exit')
    channel.start_consuming()
```

### 8.2 Java (RabbitMQ Client)

```java
// Producer
public class MessageProducer {
    private final ConnectionFactory factory;
    
    public MessageProducer() {
        factory = new ConnectionFactory();
        factory.setHost("localhost");
        factory.setUsername("guest");
        factory.setPassword("guest");
    }
    
    public void publish(String queueName, String message) throws Exception {
        try (Connection connection = factory.newConnection();
             Channel channel = connection.createChannel()) {
            
            channel.queueDeclare(queueName, true, false, false, null);
            
            AMQP.BasicProperties props = new AMQP.BasicProperties.Builder()
                .deliveryMode(2)           // persistent
                .contentType("application/json")
                .messageId(UUID.randomUUID().toString())
                .timestamp(new Date())
                .build();
            
            channel.basicPublish("", queueName, props, message.getBytes(StandardCharsets.UTF_8));
            System.out.println("Sent: " + message);
        }
    }
}

// Consumer
public class MessageConsumer {
    public void startConsuming(String queueName) throws Exception {
        Connection connection = factory.newConnection();
        Channel channel = connection.createChannel();
        
        channel.queueDeclare(queueName, true, false, false, null);
        channel.basicQos(1);  // prefetch count
        
        DeliverCallback callback = (consumerTag, delivery) -> {
            String message = new String(delivery.getBody(), StandardCharsets.UTF_8);
            try {
                processMessage(message);
                channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
            } catch (Exception e) {
                channel.basicNack(delivery.getEnvelope().getDeliveryTag(), false, false);
            }
        };
        
        channel.basicConsume(queueName, false, callback, consumerTag -> {});
    }
}
```

---

## 9. Message Lifecycle

```
Producer → Exchange → (routing decision) → Queue → Consumer

Routing failures:
├── No matching queue: message dropped (or returned if mandatory=true)
└── mandatory=true + no route: broker returns message to producer (via Return callback)

In Queue:
├── Ready: waiting to be consumed
├── Unacked: delivered to consumer, waiting for ack
└── Dead-lettered: rejected/expired → sent to DLX if configured

Consumer receives:
├── Basic.Deliver (push, basic_consume)
└── Basic.Get.Ok (pull, basic_get - inefficient, avoid)
```

---

## 10. Ghi chú – Topics tiếp theo

- **Work Queue pattern**: fair dispatch, prefetch → `rabbitmq_patterns.md`
- **Dead Letter Exchange**: rejection, expiry → `rabbitmq_patterns.md`
- **RPC pattern**: reply_to, correlation_id → `rabbitmq_patterns.md`
- **Publisher Confirms**: broker acknowledgement → `rabbitmq_reliability.md`
- **Consumer Acks**: ack/nack/reject → `rabbitmq_reliability.md`
- **Durability**: durable exchange + queue + persistent messages → `rabbitmq_reliability.md`
- **Clustering**: Erlang cluster, quorum queues → `rabbitmq_production.md`
- **Policies**: HA policy, TTL policy, DLX policy → `rabbitmq_production.md`
- **Spring AMQP**: @RabbitListener, RabbitTemplate → `rabbitmq_production.md`
