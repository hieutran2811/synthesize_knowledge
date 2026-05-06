# Kafka Production Operations – Performance, Monitoring & Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Production Operations

Kafka production operations bao gồm: OS + JVM tuning, broker configurations tối ưu cho throughput/latency, monitoring chiến lược với JMX/Prometheus, consumer lag alerting, security (SASL, TLS, ACLs), và disaster recovery.

```
Operations pillars:
  Performance:  broker/OS/JVM tuning, producer/consumer config
  Monitoring:   JMX metrics, Prometheus, Grafana dashboards
  Security:     Authentication (SASL), Encryption (TLS), Authorization (ACLs)
  DR:           MirrorMaker2, backup strategies
```

---

## How – OS & JVM Tuning

```bash
# OS settings (/etc/sysctl.conf)
net.core.wmem_default=131072
net.core.rmem_default=131072
net.core.wmem_max=2097152
net.core.rmem_max=2097152
net.ipv4.tcp_wmem=4096 65536 2048000
net.ipv4.tcp_rmem=4096 65536 2048000
vm.swappiness=1                          # near-disable swap (I/O latency)
vm.dirty_ratio=80                        # % RAM before force flush
vm.dirty_background_ratio=5             # % RAM before background flush

# Filesystem: XFS recommended (ext4 also fine)
# Mount options
/dev/sdb1 /data/kafka xfs defaults,noatime,nodiratime 0 2
# noatime: no access time updates (avoid extra writes)

# File descriptors (/etc/security/limits.conf)
kafka soft nofile 128000
kafka hard nofile 128000
kafka soft nproc 65536
kafka hard nproc 65536

# Disable transparent huge pages (latency spikes)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
```

```properties
# jvm.options (Kafka broker)
-Xms6g
-Xmx6g                                   # 6-12GB typical; not too large (GC pauses)
-XX:+UseG1GC
-XX:MaxGCPauseMillis=20                  # target max 20ms GC pause
-XX:InitiatingHeapOccupancyPercent=35
-XX:+ExplicitGCInvokesConcurrent
-XX:G1HeapRegionSize=16m
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/tmp/kafka-heap.hprof
-XX:+ExitOnOutOfMemoryError              # restart on OOM

# GC logging
-Xlog:gc*:file=/var/log/kafka/gc.log:time,tags:filecount=10,filesize=100m
```

---

## How – Broker Configuration (Performance)

```properties
# server.properties – performance tuning

# --- Network ---
num.network.threads=8              # threads for network I/O (tune to CPU cores)
num.io.threads=16                  # threads for disk I/O (tune to disk count * 2)
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600  # 100MB

# --- Log storage ---
log.dirs=/data/kafka1,/data/kafka2   # multiple dirs = multiple disks
num.recovery.threads.per.data.dir=2

# --- Replication ---
default.replication.factor=3
min.insync.replicas=2
unclean.leader.election.enable=false
auto.leader.rebalance.enable=true
leader.imbalance.check.interval.seconds=300
leader.imbalance.per.broker.percentage=10

# --- Topic defaults ---
num.partitions=6                   # default partitions for new topics
auto.create.topics.enable=false    # disable auto-creation (explicit control)
delete.topic.enable=true

# --- Retention ---
log.retention.hours=168            # 7 days
log.segment.bytes=1073741824       # 1GB segments
log.retention.check.interval.ms=300000

# --- Throughput optimization ---
log.flush.interval.messages=Long.MAX_VALUE   # rely on OS flush
log.flush.interval.ms=Long.MAX_VALUE
replica.fetch.max.bytes=10485760   # 10MB per fetch (match message.max.bytes)
message.max.bytes=10485760         # 10MB max message size

# --- Request handling ---
queued.max.requests=500
max.connections.per.ip=1000

# --- Compression ---
compression.type=producer          # keep producer compression (don't recompress)

# --- KRaft controller ---
controller.quorum.election.timeout.ms=1000
controller.quorum.election.backoff.max.ms=1000
controller.quorum.fetch.timeout.ms=2000
```

---

## How – Monitoring (JMX + Prometheus)

```yaml
# docker-compose.yml – Prometheus JMX Exporter
kafka:
  image: confluentinc/cp-kafka:7.5.0
  environment:
    KAFKA_JMX_PORT: 9999
    KAFKA_JMX_HOSTNAME: kafka
    EXTRA_ARGS: "-javaagent:/opt/prometheus/jmx_prometheus_javaagent.jar=9090:/opt/prometheus/kafka.yml"

# kafka.yml (JMX Exporter config)
hostPort: kafka:9999
rules:
  - pattern: kafka.server<type=BrokerTopicMetrics, name=MessagesInPerSec><>OneMinuteRate
    name: kafka_server_brokertopicmetrics_messagesin_rate
    labels:
      topic: "$1"
```

### Critical Broker Metrics

```
JMX Metrics (kafka.server domain):

CLUSTER HEALTH:
  kafka.controller:type=KafkaController,name=ActiveControllerCount
    → Must be exactly 1 cluster-wide
    → 0: no controller → critical
    → > 1: split-brain → critical

  kafka.controller:type=KafkaController,name=OfflinePartitionsCount
    → 0: all good
    → > 0: partitions unavailable (CRITICAL ALERT)

  kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions
    → 0: all replicas in sync
    → > 0: replica lag or failure (WARNING → investigate)

  kafka.server:type=ReplicaManager,name=UnderMinIsrPartitionCount
    → > 0: writes may fail with NotEnoughReplicas (WARNING)

THROUGHPUT:
  kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec
  kafka.server:type=BrokerTopicMetrics,name=BytesOutPerSec
  kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec
  kafka.server:type=BrokerTopicMetrics,name=TotalProduceRequestsPerSec
  kafka.server:type=BrokerTopicMetrics,name=TotalFetchRequestsPerSec

LATENCY:
  kafka.network:type=RequestMetrics,name=RequestsPerSec,request=Produce
  kafka.network:type=RequestMetrics,name=TotalTimeMs,request=Produce
  kafka.network:type=RequestMetrics,name=TotalTimeMs,request=FetchConsumer

RESOURCE:
  kafka.server:type=KafkaRequestHandlerPool,name=RequestHandlerAvgIdlePercent
    → < 30%: broker overloaded
  java.lang:type=Memory,HeapMemoryUsage (used/max)
  kafka.log:type=LogFlushStats,name=LogFlushRateAndTimeMs
```

### Consumer Lag Monitoring

```bash
# CLI: lag check
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group order-processor-group
# GROUP              TOPIC  PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# order-processor    orders 0          10000           10050           50

# Prometheus: consumer lag via kafka-exporter or Burrow
# kafka_consumergroup_lag{consumergroup="order-processor", topic="orders", partition="0"}
# kafka_consumergroup_lag_sum{consumergroup="order-processor", topic="orders"}

# Alerting rule (Prometheus):
groups:
  - name: kafka_alerts
    rules:
      - alert: KafkaConsumerGroupLagHigh
        expr: sum(kafka_consumergroup_lag) by (consumergroup, topic) > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Consumer group {{ $labels.consumergroup }} lag is {{ $value }}"
          
      - alert: KafkaConsumerGroupLagGrowing
        expr: increase(kafka_consumergroup_lag[10m]) > 5000
        labels:
          severity: critical
        annotations:
          summary: "Consumer lag growing rapidly"

      - alert: KafkaOfflinePartitions
        expr: kafka_controller_kafkacontroller_offlinepartitionscount > 0
        for: 0m
        labels:
          severity: critical

      - alert: KafkaUnderReplicatedPartitions
        expr: kafka_server_replicamanager_underreplicatedpartitions > 0
        for: 5m
        labels:
          severity: warning
```

---

## How – Security (TLS + SASL)

### TLS Setup

```bash
# Generate CA and broker certs (production)
# 1. Generate CA
openssl req -new -x509 -keyout ca-key.pem -out ca-cert.pem \
  -days 3650 -subj "/CN=Kafka CA/O=MyOrg"

# 2. Generate broker keystore
keytool -keystore kafka.broker.keystore.jks -alias broker \
  -validity 365 -keyalg RSA -genkey \
  -dname "CN=broker1.kafka.example.com,O=MyOrg"

# 3. Sign with CA
keytool -keystore kafka.broker.keystore.jks -alias broker -certreq \
  -file broker-cert-request.pem
openssl x509 -req -CA ca-cert.pem -CAkey ca-key.pem \
  -in broker-cert-request.pem -out broker-signed-cert.pem -days 365

# 4. Import to keystore
keytool -keystore kafka.broker.keystore.jks -alias CARoot \
  -import -file ca-cert.pem
keytool -keystore kafka.broker.keystore.jks -alias broker \
  -import -file broker-signed-cert.pem

# 5. Create truststore
keytool -keystore kafka.broker.truststore.jks -alias CARoot \
  -import -file ca-cert.pem
```

```properties
# server.properties – TLS configuration
listeners=PLAINTEXT://0.0.0.0:9092,SSL://0.0.0.0:9093,SASL_SSL://0.0.0.0:9094
advertised.listeners=PLAINTEXT://broker1:9092,SSL://broker1:9093,SASL_SSL://broker1:9094

# SSL/TLS
ssl.keystore.location=/etc/kafka/certs/kafka.broker.keystore.jks
ssl.keystore.password=keystore_password
ssl.key.password=key_password
ssl.truststore.location=/etc/kafka/certs/kafka.broker.truststore.jks
ssl.truststore.password=truststore_password
ssl.client.auth=required              # required | requested | none
ssl.protocol=TLSv1.3
ssl.enabled.protocols=TLSv1.3,TLSv1.2
ssl.cipher.suites=TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384
```

### SASL Authentication

```properties
# SASL/PLAIN (simple, credentials in config – use with TLS)
sasl.enabled.mechanisms=PLAIN
sasl.mechanism.inter.broker.protocol=PLAIN
inter.broker.listener.name=SASL_SSL

# JAAS config
listener.name.sasl_ssl.plain.sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  username="admin" \
  password="admin_password" \
  user_admin="admin_password" \
  user_app_service="app_password";

# SASL/SCRAM (better: credentials stored in ZooKeeper/KRaft)
sasl.enabled.mechanisms=SCRAM-SHA-512
kafka-configs.sh --zookeeper zk:2181 --alter --entity-type users \
  --entity-name app_service --add-config 'SCRAM-SHA-512=[password=secure_pass]'

# SASL/GSSAPI (Kerberos) – enterprise environments
sasl.enabled.mechanisms=GSSAPI
sasl.kerberos.service.name=kafka
# KafkaServer {
#   com.sun.security.auth.module.Krb5LoginModule required
#   useKeyTab=true
#   storeKey=true
#   keyTab="/etc/kafka/kafka.keytab"
#   principal="kafka/broker1.example.com@EXAMPLE.COM";
# };

# OAUTHBEARER (JWT tokens) – modern SSO
sasl.enabled.mechanisms=OAUTHBEARER
sasl.oauthbearer.jwks.endpoint.url=https://sso.example.com/.well-known/jwks.json
sasl.oauthbearer.expected.audience=kafka-cluster
```

### ACLs (Authorization)

```bash
# Enable ACLs
# server.properties
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
allow.everyone.if.no.acl.found=false      # deny by default
super.users=User:admin;User:kafka_internal

# Create ACLs
kafka-acls.sh --bootstrap-server localhost:9092 \
  --command-config admin.properties \
  --add \
  --allow-principal User:app_service \
  --operation Read \
  --operation Write \
  --topic orders

# Allow consumer group access
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add \
  --allow-principal User:app_service \
  --operation Read \
  --group order-processor-group

# Allow prefix pattern
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add \
  --allow-principal User:logs_service \
  --operation Write \
  --topic logs- \
  --resource-pattern-type prefixed

# Read-only access to topic
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add \
  --allow-principal User:analytics_user \
  --operation Describe \
  --operation Read \
  --topic orders \
  --group analytics-group

# List ACLs
kafka-acls.sh --bootstrap-server localhost:9092 --list --topic orders

# Remove ACL
kafka-acls.sh --bootstrap-server localhost:9092 \
  --remove --allow-principal User:old_service --operation Read --topic orders
```

---

## How – Operational Runbooks

```bash
# 1. Leader rebalance (after broker restart)
kafka-leader-election.sh --bootstrap-server localhost:9092 \
  --election-type preferred --all-topic-partitions

# 2. Increase topic partitions
kafka-topics.sh --bootstrap-server localhost:9092 \
  --alter --topic orders --partitions 24
# WARNING: existing keyed messages lose ordering guarantees!
# → Create new topic with desired partitions and migrate consumers

# 3. Move partition to specific broker (overloaded broker)
# Generate reassignment plan
cat > topics.json << EOF
{"topics": [{"topic": "orders"}], "version": 1}
EOF
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --topics-to-move-json-file topics.json --broker-list "1,2,3,4" --generate \
  > reassignment_plan.json

# Execute with throttle
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment_plan.json \
  --execute --throttle 50000000  # 50MB/s

# Verify
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment_plan.json --verify

# Remove throttle after done
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type brokers --entity-default \
  --alter --delete-config leader.replication.throttled.rate,follower.replication.throttled.rate

# 4. Drain broker before maintenance
# Reassign all partitions off the broker
# Set replica.lag.time.max.ms to low value to force ISR shrink
# Then restart broker
```

---

## How – Disaster Recovery (MirrorMaker2)

```bash
# Active-passive DR setup
# Primary cluster: us-east (active)
# DR cluster: us-west (passive, warm standby)

# MirrorMaker2 on DR cluster
cat > mm2.properties << EOF
clusters = primary, dr

primary.bootstrap.servers = us-east-broker1:9092,us-east-broker2:9092
dr.bootstrap.servers = us-west-broker1:9092,us-west-broker2:9092

primary->dr.enabled = true
primary->dr.topics = orders,payments,user-events
primary->dr.replication.factor = 3

# Sync consumer offsets for quick failover
primary->dr.sync.group.offsets.enabled = true
primary->dr.sync.group.offsets.interval.seconds = 60

# Heartbeat for lag monitoring
heartbeats.topic.replication.factor = 3
checkpoints.topic.replication.factor = 3
EOF

bin/connect-mirror-maker.sh mm2.properties

# Failover procedure:
# 1. Stop producers writing to primary
# 2. Wait for MirrorMaker2 lag to reach 0
# 3. Translate consumer offsets
kafka-consumer-groups.sh --bootstrap-server us-west-broker:9092 \
  --group order-processor --reset-offsets \
  --to-latest --topic primary.orders --execute
# 4. Restart consumers pointing to DR cluster with translated offsets
# 5. Update DNS/load balancer to DR cluster

# Monitor lag
kafka-consumer-groups.sh --bootstrap-server us-west-broker:9092 \
  --describe --group primary.order-processor  # MirrorMaker2 group
```

---

## Trade-offs

```
TLS overhead:
  ✅ Encryption in transit (required for compliance)
  ❌ ~5-10% throughput reduction (CPU for encryption)
  ❌ Increased latency (handshake)
  → TLSv1.3 + hardware AES: minimal overhead

SASL/PLAIN vs SASL/SCRAM:
  PLAIN:  credentials in config file (less secure, simple)
  SCRAM:  credentials in ZK/KRaft (can rotate without restart), more secure
  GSSAPI: enterprise Kerberos (most secure, complex setup)
  → SCRAM-SHA-512 for most production; GSSAPI for Kerberos environments

ACL granularity:
  Broad ACLs:  easier management, less secure
  Granular:    secure, hard to manage (many rules)
  → Prefix-based ACLs for topic families (logs-*, orders-*)

MirrorMaker2 vs manual DR:
  MM2:    automated, near real-time, managed failover
  Manual: simpler, less infra, but slow RTO
  → MM2 for RPO < 1h; snapshots for RPO > 1h
```

---

## Real-world Production Checklist

```
Pre-production checklist:
  ✅ OS: swappiness=1, noatime, XFS
  ✅ JVM: G1GC, 6-12GB heap, ExitOnOutOfMemoryError
  ✅ Broker: RF=3, min.insync.replicas=2, acks=all for producers
  ✅ TLS: enabled for both listeners + inter-broker
  ✅ SASL: SCRAM or GSSAPI (not PLAIN in production)
  ✅ ACLs: enabled, deny-all default, explicit allow per service
  ✅ Monitoring: Prometheus JMX exporter + Grafana dashboards
  ✅ Alerts: OfflinePartitions, UnderReplicated, ConsumerLag, ActiveController
  ✅ DR: MirrorMaker2 to DR cluster
  ✅ Testing: chaos tests (kill broker, network partition)

Monitoring dashboard must-haves:
  Broker: throughput in/out, request rate, handler idle %
  Topics: messages in/out per topic, bytes in/out
  Consumers: lag per consumer group + topic + partition
  Replication: under-replicated partitions, ISR changes
  JVM: heap usage, GC time
```

---

*Cập nhật lần cuối: 2026-05-06*
