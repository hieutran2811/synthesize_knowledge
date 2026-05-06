# RabbitMQ Production & Operations

## 1. Clustering

### 1.1 How Clustering Works

```
RabbitMQ Cluster = nhiều Erlang nodes trong cùng một cluster

Shared across nodes:
  ✓ Exchanges (metadata only)
  ✓ Queue metadata (name, properties, bindings)
  ✓ Users, vhosts, permissions
  ✓ Policies

NOT shared by default:
  ✗ Queue contents (messages) — stored only on declaring node!
  → Use Quorum Queues for data replication

Node types:
  Disk node: persists metadata + data to disk (required ≥ 1)
  RAM node: metadata in RAM only (faster for metadata-heavy operations)
  → Keep at least 2 disk nodes in production!
```

### 1.2 Cluster Setup

```bash
# Example: 3-node cluster (rabbit1, rabbit2, rabbit3)

# Step 1: Same Erlang cookie on all nodes (authentication secret)
# Copy cookie from rabbit1 to other nodes
scp /var/lib/rabbitmq/.erlang.cookie rabbit2:/var/lib/rabbitmq/.erlang.cookie
scp /var/lib/rabbitmq/.erlang.cookie rabbit3:/var/lib/rabbitmq/.erlang.cookie
chmod 400 /var/lib/rabbitmq/.erlang.cookie
chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie

# Step 2: Start RabbitMQ on all nodes
systemctl start rabbitmq-server  # on each node

# Step 3: Join cluster (run on rabbit2 and rabbit3)
rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl join_cluster rabbit@rabbit1    # join as disk node
# or: rabbitmqctl join_cluster --ram rabbit@rabbit1  # RAM node
rabbitmqctl start_app

# Step 4: Verify
rabbitmqctl cluster_status
# Cluster name: rabbit@rabbit1
# Disk Nodes: [rabbit@rabbit1, rabbit@rabbit2, rabbit@rabbit3]
# Running Nodes: [rabbit@rabbit1, rabbit@rabbit2, rabbit@rabbit3]

# Remove a node from cluster
# On the node to remove:
rabbitmqctl stop_app
rabbitmqctl reset  # forget cluster, become standalone

# Or from another node:
rabbitmqctl forget_cluster_node rabbit@rabbit3  # remove offline node
```

### 1.3 Docker Compose Cluster

```yaml
# docker-compose.yml — 3-node RabbitMQ cluster
version: '3.8'

services:
  rabbit1:
    image: rabbitmq:3.13-management
    hostname: rabbit1
    environment:
      RABBITMQ_ERLANG_COOKIE: "SWQOKODSQALRPCLNMEQG"
      RABBITMQ_DEFAULT_USER: "admin"
      RABBITMQ_DEFAULT_PASS: "${RABBIT_PASSWORD}"
      RABBITMQ_DEFAULT_VHOST: "/"
    ports:
      - "5672:5672"
      - "15672:15672"
    volumes:
      - rabbit1_data:/var/lib/rabbitmq
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    networks:
      - rabbit_net
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_port_connectivity"]
      interval: 30s
      timeout: 10s
      retries: 5

  rabbit2:
    image: rabbitmq:3.13-management
    hostname: rabbit2
    environment:
      RABBITMQ_ERLANG_COOKIE: "SWQOKODSQALRPCLNMEQG"
      RABBITMQ_DEFAULT_USER: "admin"
      RABBITMQ_DEFAULT_PASS: "${RABBIT_PASSWORD}"
    depends_on:
      rabbit1:
        condition: service_healthy
    volumes:
      - rabbit2_data:/var/lib/rabbitmq
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    networks:
      - rabbit_net

  rabbit3:
    image: rabbitmq:3.13-management
    hostname: rabbit3
    environment:
      RABBITMQ_ERLANG_COOKIE: "SWQOKODSQALRPCLNMEQG"
      RABBITMQ_DEFAULT_USER: "admin"
      RABBITMQ_DEFAULT_PASS: "${RABBIT_PASSWORD}"
    depends_on:
      rabbit1:
        condition: service_healthy
    volumes:
      - rabbit3_data:/var/lib/rabbitmq
      - ./rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf
    networks:
      - rabbit_net

  # Cluster init: join rabbit2 and rabbit3 to rabbit1
  cluster-init:
    image: rabbitmq:3.13-management
    depends_on:
      - rabbit2
      - rabbit3
    networks:
      - rabbit_net
    entrypoint: >
      sh -c "
        sleep 20
        rabbitmqctl -n rabbit@rabbit2 stop_app
        rabbitmqctl -n rabbit@rabbit2 join_cluster rabbit@rabbit1
        rabbitmqctl -n rabbit@rabbit2 start_app
        rabbitmqctl -n rabbit@rabbit3 stop_app
        rabbitmqctl -n rabbit@rabbit3 join_cluster rabbit@rabbit1
        rabbitmqctl -n rabbit@rabbit3 start_app
        echo 'Cluster setup complete'
      "

  haproxy:
    image: haproxy:2.8-alpine
    ports:
      - "5670:5670"    # AMQP load balanced
      - "15670:15670"  # Management UI load balanced
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
    networks:
      - rabbit_net

volumes:
  rabbit1_data:
  rabbit2_data:
  rabbit3_data:

networks:
  rabbit_net:
```

```
# haproxy.cfg
global
  maxconn 4096

defaults
  timeout connect 5s
  timeout client 30s
  timeout server 30s

frontend amqp
  bind *:5670
  default_backend rabbitmq_nodes

backend rabbitmq_nodes
  balance roundrobin
  option tcp-check
  server rabbit1 rabbit1:5672 check inter 5s rise 2 fall 3
  server rabbit2 rabbit2:5672 check inter 5s rise 2 fall 3
  server rabbit3 rabbit3:5672 check inter 5s rise 2 fall 3
```

---

## 2. Quorum Queues

### 2.1 What & Why

**Quorum Queue** = queue được replicate trên N nodes dùng Raft consensus algorithm. Thay thế Classic Mirrored Queues (deprecated từ 3.12).

```
Classic Queue:              Quorum Queue:
- Single node storage       - Raft-based replication (majority)
- Optional mirroring        - Automatic leader election
  (synchronous, expensive)  - Data on majority = survives minority failure
- Can lose data on          - Guaranteed consistency
  master failure            - Configurable replication factor

Quorum Queue layout (3 nodes, quorum-size=3):
  rabbit1: queue leader (handles all read/write)
  rabbit2: queue follower (has replica)
  rabbit3: queue follower (has replica)

  Leader fails → election → one follower becomes leader
  Data safe if ≥ 2 nodes running (majority of 3)
```

### 2.2 Declaring Quorum Queues

```python
# Declare quorum queue
channel.queue_declare(
    queue='orders_quorum',
    durable=True,              # required for quorum queues
    arguments={
        'x-queue-type': 'quorum',              # MUST be durable
        'x-quorum-initial-group-size': 3,      # initial replica count
        # 'x-delivery-limit': 3,              # max delivery attempts (poison message)
        # 'x-dead-letter-exchange': 'dlx',
        # 'x-dead-letter-strategy': 'at-least-once',  # or 'at-most-once'
    }
)
```

```bash
# Management: create via CLI
rabbitmqctl declare_queue \
    name=orders_quorum \
    durable=true \
    arguments='{"x-queue-type": "quorum"}'

# Check quorum status
rabbitmqctl list_quorum_queues
rabbitmqctl quorum_queue_status orders_quorum
# leader, members, online members

# Grow/shrink replica set
rabbitmqctl grow_queue_member_where orders_quorum extra
rabbitmqctl shrink_queue_member_where orders_quorum orders_quorum rabbit@rabbit3
```

### 2.3 Quorum Queues vs Classic Mirrored

| Feature | Classic Mirrored | Quorum Queue |
|---------|----------------|--------------|
| Replication | Async + sync mirrors | Raft consensus |
| Data safety | Can lose data on failover | Strong consistency |
| Performance | Variable (sync mirrors slow) | Predictable |
| Poison message | No built-in | x-delivery-limit |
| Lazy mode | Supported | Default behavior |
| Priority | Supported | Not supported |
| Transactions | Supported | Not supported |
| Max length | Supported | Supported |
| Status | Deprecated (3.12) | Recommended |

---

## 3. Policies

### 3.1 What & How

**Policy** = configuration áp dụng tự động cho queues/exchanges matching pattern. Không cần redeclare.

```bash
# Set policy syntax:
rabbitmqctl set_policy <name> <pattern> <definition> [options]

# HA policy (Quorum queue via policy - không nên dùng cách này, khai báo trực tiếp tốt hơn)
rabbitmqctl set_policy ha-all "^ha\." \
    '{"queue-mode":"lazy","max-length":100000}' \
    --apply-to queues \
    --priority 1 \
    -p /

# Dead Letter Exchange policy (apply to queues matching "tasks.")
rabbitmqctl set_policy dlx-policy "^tasks\." \
    '{"dead-letter-exchange":"dlx","message-ttl":86400000}' \
    --apply-to queues \
    --priority 2

# Message TTL policy
rabbitmqctl set_policy ttl-1hour "^ephemeral\." \
    '{"message-ttl":3600000}' \
    --apply-to queues

# Max length policy  
rabbitmqctl set_policy max-1000 "^bounded\." \
    '{"max-length":1000,"overflow":"reject-publish-dlx"}' \
    --apply-to queues

# List policies
rabbitmqctl list_policies
rabbitmqctl list_policies -p production

# Clear policy
rabbitmqctl clear_policy ha-all

# Operator policies (cannot be overridden by user policies)
rabbitmqctl set_operator_policy max-msg-ttl ".*" \
    '{"message-ttl":86400000}' \
    --apply-to queues
```

### 3.2 Policy via Management API

```python
import requests

RABBIT_API = 'http://localhost:15672/api'
AUTH = ('guest', 'guest')

def set_policy(vhost: str, name: str, pattern: str, definition: dict, apply_to: str = 'queues', priority: int = 0):
    url = f"{RABBIT_API}/policies/{vhost}/{name}"
    payload = {
        'pattern': pattern,
        'definition': definition,
        'apply-to': apply_to,
        'priority': priority,
    }
    r = requests.put(url, json=payload, auth=AUTH)
    r.raise_for_status()
    print(f"Policy '{name}' set: {r.status_code}")

# Apply quorum + DLX + TTL to all production queues
set_policy('/', 'prod-defaults', '^prod\.', {
    'x-queue-type': 'quorum',
    'x-dead-letter-exchange': 'dlx',
    'message-ttl': 86400000,
    'max-length': 100000,
    'overflow': 'reject-publish-dlx',
})
```

---

## 4. Federation & Shovel

### 4.1 Federation (Cross-Datacenter Pub/Sub)

```
Federation: link exchanges/queues across independent clusters
Use case: DC1 publishes → DC2 consumers receive

                DC1 (US)                    DC2 (EU)
  Producer → [upstream_exchange] ──────→ [federated_exchange] → Consumer
                                    └→ [federated_exchange] → Consumer
                                              (EU federation)

Setup (on DC2 - downstream):
```

```bash
# Enable plugin
rabbitmq-plugins enable rabbitmq_federation rabbitmq_federation_management

# Define upstream (DC1 connection)
rabbitmqctl set_parameter federation-upstream us-datacenter \
    '{"uri": "amqp://admin:password@rabbit-dc1.example.com:5672",
      "prefetch-count": 1000,
      "reconnect-delay": 5,
      "ack-mode": "on-confirm",
      "trust-user-id": false}'

# Create federation policy (DC2 exchanges that pull from upstream)
rabbitmqctl set_policy federate-exchanges "^federated\." \
    '{"federation-upstream": "us-datacenter"}' \
    --apply-to exchanges

# Check federation status
rabbitmqctl eval 'rabbit_federation_status:status().'
# Management UI: Admin → Federation Status
```

### 4.2 Shovel (Message Transfer)

```bash
# Shovel: move/copy messages from source queue to destination exchange/queue
# Use case: migrate data, bridge clusters, dead-letter processing

rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management

# Static shovel (in rabbitmq.conf)
# loopback_users.guest = false
# shovel.my_shovel.source.protocol = amqp091
# shovel.my_shovel.source.uris = amqp://rabbit1:5672
# shovel.my_shovel.source.queue = source_queue
# shovel.my_shovel.destination.protocol = amqp091
# shovel.my_shovel.destination.uris = amqp://rabbit2:5672
# shovel.my_shovel.destination.exchange = dest_exchange
# shovel.my_shovel.destination.exchange_key = routing_key

# Dynamic shovel (via management API / CLI)
rabbitmqctl set_parameter shovel dlq-to-retry \
    '{
      "src-protocol": "amqp091",
      "src-uri": "amqp://",
      "src-queue": "task_queue.dlq",
      "dest-protocol": "amqp091",
      "dest-uri": "amqp://",
      "dest-exchange": "",
      "dest-exchange-key": "task_queue",
      "src-prefetch-count": 100,
      "ack-mode": "on-confirm"
    }'

# Shovel status
rabbitmqctl shovel_status
```

---

## 5. Spring AMQP (Java)

### 5.1 Configuration

```xml
<!-- pom.xml -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-amqp</artifactId>
</dependency>
```

```yaml
# application.yml
spring:
  rabbitmq:
    host: ${RABBIT_HOST:localhost}
    port: 5672
    username: ${RABBIT_USER:guest}
    password: ${RABBIT_PASS:guest}
    virtual-host: /
    connection-timeout: 10000
    requested-heartbeat: 60
    publisher-confirm-type: correlated    # NONE | SIMPLE | CORRELATED
    publisher-returns: true
    listener:
      simple:
        acknowledge-mode: manual           # NONE | AUTO | MANUAL
        prefetch: 10
        concurrency: 3
        max-concurrency: 10
        default-requeue-rejected: false    # NACK → DLX, not requeue
        retry:
          enabled: true
          max-attempts: 3
          initial-interval: 1000
          multiplier: 2
          max-interval: 10000
    template:
      reply-timeout: 5000               # RPC timeout
      mandatory: true
```

### 5.2 Queue & Exchange Declarations

```java
@Configuration
public class RabbitMQConfig {
    
    public static final String ORDER_EXCHANGE = "orders";
    public static final String ORDER_QUEUE = "order.processing";
    public static final String ORDER_ROUTING_KEY = "order.created";
    public static final String DLX_EXCHANGE = "orders.dlx";
    public static final String DLQ_QUEUE = "order.processing.dlq";
    
    // Dead Letter Exchange
    @Bean
    public DirectExchange deadLetterExchange() {
        return ExchangeBuilder.directExchange(DLX_EXCHANGE)
            .durable(true)
            .build();
    }
    
    // Dead Letter Queue
    @Bean
    public Queue deadLetterQueue() {
        return QueueBuilder.durable(DLQ_QUEUE)
            .withArgument("x-message-ttl", 86400000L)
            .build();
    }
    
    @Bean
    public Binding dlqBinding() {
        return BindingBuilder.bind(deadLetterQueue())
            .to(deadLetterExchange())
            .with("order.failed");
    }
    
    // Main Exchange (Topic)
    @Bean
    public TopicExchange orderExchange() {
        return ExchangeBuilder.topicExchange(ORDER_EXCHANGE)
            .durable(true)
            .build();
    }
    
    // Main Queue (Quorum)
    @Bean
    public Queue orderQueue() {
        return QueueBuilder.durable(ORDER_QUEUE)
            .quorum()                                          // Quorum Queue!
            .withArgument("x-dead-letter-exchange", DLX_EXCHANGE)
            .withArgument("x-dead-letter-routing-key", "order.failed")
            .withArgument("x-delivery-limit", 3)              // Quorum: max 3 deliveries
            .build();
    }
    
    @Bean
    public Binding orderBinding() {
        return BindingBuilder.bind(orderQueue())
            .to(orderExchange())
            .with(ORDER_ROUTING_KEY);
    }
    
    // Message Converter: JSON
    @Bean
    public MessageConverter jsonMessageConverter() {
        Jackson2JsonMessageConverter converter = new Jackson2JsonMessageConverter();
        converter.setCreateMessageIds(true);  // auto-generate message_id
        return converter;
    }
    
    // RabbitTemplate
    @Bean
    public RabbitTemplate rabbitTemplate(ConnectionFactory connectionFactory) {
        RabbitTemplate template = new RabbitTemplate(connectionFactory);
        template.setMessageConverter(jsonMessageConverter());
        template.setMandatory(true);
        
        template.setConfirmCallback((correlation, ack, reason) -> {
            if (!ack) {
                log.error("Publisher NACK: {}", reason);
            }
        });
        
        template.setReturnsCallback(returned -> {
            log.error("Message returned from exchange {}: {}",
                returned.getExchange(), returned.getReplyText());
        });
        
        return template;
    }
}
```

### 5.3 Consumer with @RabbitListener

```java
@Service
@Slf4j
public class OrderConsumer {
    
    @Autowired
    private OrderService orderService;
    
    // Basic listener
    @RabbitListener(
        queues = RabbitMQConfig.ORDER_QUEUE,
        containerFactory = "rabbitListenerContainerFactory"
    )
    public void processOrder(
        @Payload Order order,
        @Header(AmqpHeaders.DELIVERY_TAG) long deliveryTag,
        @Header(AmqpHeaders.MESSAGE_ID) String messageId,
        Channel channel
    ) throws IOException {
        log.info("Processing order: {} (messageId={})", order.getId(), messageId);
        
        try {
            orderService.process(order);
            channel.basicAck(deliveryTag, false);
            log.info("Order {} processed successfully", order.getId());
        } catch (RetryableException e) {
            // Negative ack, requeue=false → DLX (with x-delivery-limit for quorum)
            channel.basicNack(deliveryTag, false, false);
            log.warn("Order {} failed (retryable): {}", order.getId(), e.getMessage());
        } catch (PermanentException e) {
            // Dead letter immediately
            channel.basicNack(deliveryTag, false, false);
            log.error("Order {} permanently failed: {}", order.getId(), e.getMessage());
        }
    }
    
    // Batch listener
    @RabbitListener(queues = "batch_orders", containerFactory = "batchListenerFactory")
    public void processBatch(List<Message> messages, Channel channel) throws IOException {
        log.info("Processing batch of {} orders", messages.size());
        
        long lastDeliveryTag = 0;
        List<Long> failed = new ArrayList<>();
        
        for (Message message : messages) {
            long deliveryTag = (long) message.getMessageProperties().getDeliveryTag();
            try {
                Order order = objectMapper.readValue(message.getBody(), Order.class);
                orderService.process(order);
                lastDeliveryTag = deliveryTag;
            } catch (Exception e) {
                failed.add(deliveryTag);
            }
        }
        
        // Batch ack all successful
        if (lastDeliveryTag > 0) {
            channel.basicAck(lastDeliveryTag, true);  // multiple=true
        }
        // Nack failed individually
        for (long failedTag : failed) {
            channel.basicNack(failedTag, false, false);
        }
    }
}

// Batch container factory
@Bean
public SimpleRabbitListenerContainerFactory batchListenerFactory(ConnectionFactory cf) {
    SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
    factory.setConnectionFactory(cf);
    factory.setBatchListener(true);
    factory.setConsumerBatchEnabled(true);
    factory.setBatchSize(50);
    factory.setReceiveTimeout(2000L);   // wait up to 2s to fill batch
    factory.setPrefetchCount(100);
    factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
    factory.setMessageConverter(new SimpleMessageConverter());
    return factory;
}
```

### 5.4 Publisher Service

```java
@Service
@Slf4j
public class OrderPublisher {
    
    @Autowired
    private RabbitTemplate rabbitTemplate;
    
    @Autowired
    private OutboxRepository outboxRepository;
    
    // Simple publish
    public void publishOrderCreated(Order order) {
        CorrelationData correlation = new CorrelationData(order.getId().toString());
        
        rabbitTemplate.convertAndSend(
            RabbitMQConfig.ORDER_EXCHANGE,
            "order.created",
            order,
            message -> {
                message.getMessageProperties().setContentType("application/json");
                message.getMessageProperties().setMessageId(order.getId().toString());
                return message;
            },
            correlation
        );
    }
    
    // Reliable publish via Outbox
    @Transactional
    public void publishReliably(Order order) {
        // Save outbox record in same TX as order
        outboxRepository.save(OutboxMessage.builder()
            .messageId(UUID.randomUUID().toString())
            .exchange(RabbitMQConfig.ORDER_EXCHANGE)
            .routingKey("order.created")
            .payload(objectMapper.writeValueAsString(order))
            .status(OutboxStatus.PENDING)
            .build());
    }
    
    // Background outbox publisher
    @Scheduled(fixedDelay = 500)
    @Transactional
    public void flushOutbox() {
        List<OutboxMessage> pending = outboxRepository
            .findTop100ByStatusOrderByCreatedAtAsc(OutboxStatus.PENDING);
        
        pending.forEach(msg -> {
            try {
                CorrelationData cd = new CorrelationData(msg.getMessageId());
                rabbitTemplate.convertAndSend(msg.getExchange(), msg.getRoutingKey(),
                    msg.getPayload(), cd);
                msg.setStatus(OutboxStatus.SENT);
            } catch (Exception e) {
                msg.incrementRetry();
                if (msg.getRetryCount() >= 5) msg.setStatus(OutboxStatus.FAILED);
                log.error("Failed to publish outbox message {}: {}", msg.getMessageId(), e.getMessage());
            }
        });
        outboxRepository.saveAll(pending);
    }
}
```

---

## 6. Kubernetes Deployment

```yaml
# rabbitmq-cluster.yaml using RabbitMQ Cluster Operator
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rabbitmq
  namespace: messaging
spec:
  replicas: 3
  image: rabbitmq:3.13-management
  service:
    type: ClusterIP
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 2Gi
  rabbitmq:
    additionalConfig: |
      vm_memory_high_watermark.relative = 0.5
      disk_free_limit.absolute = 2GB
      consumer_timeout = 1800000
      log.console = true
      log.console.level = info
    additionalPlugins:
      - rabbitmq_management
      - rabbitmq_peer_discovery_k8s
      - rabbitmq_prometheus
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: rabbitmq
          topologyKey: kubernetes.io/hostname
  persistence:
    storageClassName: fast-ssd
    storage: 20Gi
  tls:
    secretName: rabbitmq-tls
    caSecretName: rabbitmq-ca
---
# Service Monitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq
  endpoints:
    - port: prometheus
      interval: 30s
      path: /metrics
```

```yaml
# rabbitmq.conf via ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: rabbitmq-config
data:
  rabbitmq.conf: |
    ## Cluster Formation
    cluster_formation.peer_discovery_backend = rabbit_peer_discovery_k8s
    cluster_formation.k8s.host = kubernetes.default.svc.cluster.local
    cluster_formation.k8s.address_type = hostname
    cluster_formation.node_cleanup.only_log_warning = true
    cluster_partition_handling = pause_minority
    
    ## Memory
    vm_memory_high_watermark.relative = 0.5
    
    ## Disk
    disk_free_limit.absolute = 2GB
    
    ## Defaults
    default_vhost = /
    default_user = admin
    loopback_users.guest = false
    
    ## Heartbeat
    heartbeat = 60
    
    ## Management
    management.tcp.port = 15672
    management.load_definitions = /etc/rabbitmq/definitions.json
```

---

## 7. Monitoring

### 7.1 Prometheus & Grafana

```bash
# Enable Prometheus plugin
rabbitmq-plugins enable rabbitmq_prometheus

# Metrics endpoint
curl http://localhost:15692/metrics

# Key metrics to monitor:
# rabbitmq_queue_messages_ready          - messages waiting to be consumed
# rabbitmq_queue_messages_unacked        - delivered but not acked
# rabbitmq_queue_consumers               - number of consumers
# rabbitmq_queue_messages_published_total - publish rate
# rabbitmq_queue_messages_delivered_total - delivery rate
# rabbitmq_connections                   - total connections
# rabbitmq_channels                      - total channels
# rabbitmq_node_mem_used                 - memory used
# rabbitmq_node_disk_free                - free disk space
# rabbitmq_node_proc_used               - Erlang process count
```

```yaml
# Prometheus alerting rules
groups:
  - name: rabbitmq
    rules:
      - alert: RabbitmqDown
        expr: rabbitmq_identity_info == 0
        for: 1m
        annotations:
          summary: "RabbitMQ node is down"

      - alert: QueueDepthHigh
        expr: rabbitmq_queue_messages_ready > 10000
        for: 5m
        annotations:
          summary: "Queue {{ $labels.queue }} has {{ $value }} messages"

      - alert: ConsumerAbsent
        expr: rabbitmq_queue_consumers{queue!~".*dlq.*"} == 0
        for: 2m
        annotations:
          summary: "No consumers on queue {{ $labels.queue }}"

      - alert: HighUnackedMessages
        expr: rabbitmq_queue_messages_unacked > 1000
        for: 5m
        annotations:
          summary: "High unacked messages on {{ $labels.queue }}"

      - alert: MemoryAlarm
        expr: rabbitmq_alarms_memory_used_watermark > 0
        annotations:
          summary: "RabbitMQ memory alarm triggered - publishing blocked"

      - alert: DiskAlarm
        expr: rabbitmq_alarms_free_disk_space_watermark > 0
        annotations:
          summary: "RabbitMQ disk alarm triggered"

      - alert: NodeNotClusterd
        expr: rabbitmq_cluster_nodes < 3
        annotations:
          summary: "RabbitMQ cluster has only {{ $value }} nodes"
```

### 7.2 Health Checks

```bash
# HTTP health checks (for load balancer/K8s)
# Basic alive check
curl -f http://localhost:15672/api/healthchecks/node
# → {"status":"ok"}

# Check specific vhost
curl -u admin:pass http://localhost:15672/api/healthchecks/virtual-hosts
curl -u admin:pass "http://localhost:15672/api/healthchecks/alarms"
curl -u admin:pass "http://localhost:15672/api/healthchecks/protocol-listener/amqp091"

# CLI diagnostics
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_local_alarms
rabbitmq-diagnostics check_port_connectivity

# K8s liveness/readiness probes
# livenessProbe:
#   exec:
#     command: ["rabbitmq-diagnostics", "check_running"]
#   initialDelaySeconds: 60
#   periodSeconds: 30

# readinessProbe:
#   exec:
#     command: ["rabbitmq-diagnostics", "check_port_connectivity"]
#   initialDelaySeconds: 20
#   periodSeconds: 10
```

---

## 8. Security

```bash
# 1. Remove default guest user
rabbitmqctl delete_user guest

# 2. Create admin user
rabbitmqctl add_user admin $(openssl rand -base64 32)
rabbitmqctl set_user_tags admin administrator
rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

# 3. App user with minimal permissions
rabbitmqctl add_user app_user "strongpassword"
rabbitmqctl set_permissions -p production app_user \
    "^(orders|notifications)\." \   # configure: can declare/delete matching
    "^orders\." \                   # write: can publish to matching
    "^(orders|notifications)\."     # read: can consume from matching

# 4. TLS for AMQP
# rabbitmq.conf
# listeners.ssl.default = 5671
# ssl_options.cacertfile = /etc/rabbitmq/certs/ca.pem
# ssl_options.certfile   = /etc/rabbitmq/certs/server.pem
# ssl_options.keyfile    = /etc/rabbitmq/certs/server.key
# ssl_options.verify     = verify_peer
# ssl_options.fail_if_no_peer_cert = true

# 5. Network isolation
# Only expose AMQP port internally
# Management UI behind VPN or basic-auth proxy

# 6. Vhost isolation per environment
rabbitmqctl add_vhost production
rabbitmqctl add_vhost staging
rabbitmqctl set_permissions -p production prod_user ".*" ".*" ".*"
rabbitmqctl set_permissions -p staging staging_user ".*" ".*" ".*"
# → prod_user cannot access staging vhost
```

---

## 9. Performance Tuning

```bash
# rabbitmq.conf production tuning

## Erlang VM settings
RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS="+P 1048576 +Q 65536"
# +P: max processes (default 1048576)
# +Q: max ports

## Memory
vm_memory_high_watermark.relative = 0.4   # warn at 40% RAM
vm_memory_high_watermark_paging_ratio = 0.5  # start paging at 50% of watermark

## Disk
disk_free_limit.relative = 1.5

## Channel/Connection limits
channel_max = 2047
connection_max = infinity  # or specific number
max_message_size = 134217728  # 128MB

## Collect statistics less frequently under load
collect_statistics_interval = 60000  # 60s (default 5s)

## File descriptors (OS level)
# ulimit -n 65536
# /etc/security/limits.conf:
# rabbitmq soft nofile 65536
# rabbitmq hard nofile 65536

## Network
tcp_listen_options.backlog = 4096
tcp_listen_options.sndbuf = 131072  # 128KB
tcp_listen_options.recbuf = 131072

## Quorum Queue options
quorum_commands_soft_limit = 32    # commands in-flight limit
```

---

## 10. Production Checklist

```
Architecture:
□ 3+ node cluster (odd number for quorum)
□ Quorum Queues (not Classic mirrored)
□ HAProxy/NLB in front of cluster
□ Separate vhosts per environment

Reliability:
□ Durable exchanges + queues + persistent messages
□ Publisher Confirms enabled
□ Consumer manual ack (auto_ack=False)
□ DLX configured for all critical queues
□ x-delivery-limit on Quorum Queues (poison message protection)
□ Outbox pattern for atomic DB+publish
□ Consumer idempotency

Security:
□ guest user deleted
□ TLS on AMQP (port 5671)
□ TLS on Management UI (port 15671)
□ Per-vhost user permissions (minimal access)
□ Management UI not exposed publicly

Operations:
□ Erlang cookie secret managed securely
□ Policy for TTL, max-length, overflow
□ Prometheus metrics enabled
□ Grafana dashboards deployed
□ Alerts for: queue depth, no consumers, memory/disk alarms
□ Health check endpoints for K8s probes
□ Backup strategy (definitions export)

Performance:
□ prefetch_count tuned per consumer type
□ file descriptor limit (ulimit -n) set high
□ vm_memory_high_watermark configured
□ disk_free_limit configured
□ Lazy queues for large backlogs
```

---

## Ghi chú – Topics tiếp theo

- **Stream Queue deep dive**: replay from offset, consumer groups → extension
- **OAuth2 / JWT auth plugin**: modern auth → extension
- **MQTT plugin**: IoT devices connecting via MQTT → extension
- **WebSTOMP**: browser WebSocket clients → extension
- **Tracing**: rabbitmq_tracing plugin, firehose → debugging
