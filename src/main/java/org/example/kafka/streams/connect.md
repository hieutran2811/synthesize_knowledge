# Kafka Connect & CDC – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka Connect là gì?

**Kafka Connect** là framework tích hợp dữ liệu trong/ngoài Kafka – không cần viết producer/consumer code. Hỗ trợ 200+ connectors (JDBC, S3, Elasticsearch, MongoDB, PostgreSQL CDC...).

```
Data integration patterns:
  Source connector: external system → Kafka topic
  Sink connector:   Kafka topic → external system

Without Connect: custom producer/consumer code (brittle, maintenance)
With Connect:    declarative config, distributed execution, monitoring

Architecture:
  External DB → Source Connector → Kafka Topic → Sink Connector → Elasticsearch
  
Kafka Connect cluster (Workers):
  Worker: JVM process running connectors + tasks
  Connector: logical job (config + task management)
  Task: actual work unit (can run in parallel, 1 task per partition typically)
```

---

## Components – Connect Architecture

```
Standalone mode:
  Single worker, config in file
  Use: development, simple single-worker setups

Distributed mode (production):
  Multiple workers, config via REST API
  Workers share load automatically
  Fault tolerant: worker failure → tasks redistributed
  
Internal topics:
  connect-configs:   connector configurations
  connect-offsets:   source connector offsets (progress tracking)
  connect-status:    connector/task status
```

---

## How – Distributed Mode Setup

```properties
# worker.properties
bootstrap.servers=broker1:9092,broker2:9092,broker3:9092
group.id=connect-cluster                        # all workers with same group = same cluster

# Internal topics
config.storage.topic=connect-configs
offset.storage.topic=connect-offsets
status.storage.topic=connect-status
config.storage.replication.factor=3
offset.storage.replication.factor=3
status.storage.replication.factor=3

# Converters (serialize messages to/from Kafka)
key.converter=io.confluent.connect.avro.AvroConverter
value.converter=io.confluent.connect.avro.AvroConverter
key.converter.schema.registry.url=http://schema-registry:8081
value.converter.schema.registry.url=http://schema-registry:8081
# Or JSON:
# key.converter=org.apache.kafka.connect.json.JsonConverter
# value.converter=org.apache.kafka.connect.json.JsonConverter
# key.converter.schemas.enable=false
# value.converter.schemas.enable=false

# REST API
rest.host.name=0.0.0.0
rest.port=8083
rest.advertised.host.name=connect-worker-1    # for inter-worker routing
rest.advertised.port=8083

# Plugin path
plugin.path=/opt/kafka/plugins

# Start worker
bin/connect-distributed.sh config/worker.properties
```

---

## How – JDBC Source Connector

```bash
# Create JDBC source connector
POST http://localhost:8083/connectors
Content-Type: application/json

{
  "name": "orders-jdbc-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "connection.url": "jdbc:postgresql://db:5432/mydb",
    "connection.user": "kafka_connect",
    "connection.password": "${file:/opt/secrets/db.properties:password}",  # externalize secrets
    
    "mode": "timestamp+incrementing",    # bulk | incrementing | timestamp | timestamp+incrementing
    "incrementing.column.name": "id",
    "timestamp.column.name": "updated_at",
    "timestamp.delay.interval.ms": 5000, # wait 5s before processing (for in-flight transactions)
    
    "table.whitelist": "orders,payments",
    "query": "",                         # or custom query instead of table.whitelist
    
    "topic.prefix": "db.",               # → topics: db.orders, db.payments
    "poll.interval.ms": 5000,
    "batch.max.rows": 1000,
    
    "numeric.mapping": "best_fit",       # map numeric types to specific Java types
    
    "transforms": "addTimestamp,maskPII",
    "transforms.addTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
    "transforms.addTimestamp.timestamp.field": "kafka_ingested_at",
    "transforms.maskPII.type": "org.apache.kafka.connect.transforms.MaskField$Value",
    "transforms.maskPII.fields": "credit_card,ssn",
    "transforms.maskPII.replacement": "***MASKED***"
  }
}
```

---

## How – Elasticsearch Sink Connector

```bash
POST http://localhost:8083/connectors
{
  "name": "orders-elasticsearch-sink",
  "config": {
    "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
    "tasks.max": "3",
    
    "topics": "db.orders,db.payments",
    "connection.url": "https://elasticsearch:9200",
    "connection.username": "elastic",
    "connection.password": "${file:/opt/secrets/es.properties:password}",
    
    "type.name": "_doc",
    "key.ignore": false,                 # use Kafka key as document ID
    "schema.ignore": false,
    
    "index.name": "${topic}",            # use topic name as index name
    # Or: custom index per topic:
    # "topic.index.map": "db.orders:orders,db.payments:payments",
    
    "batch.size": 1000,
    "linger.ms": 1000,                   # wait 1s to batch
    "max.retries": 10,
    "retry.backoff.ms": 100,
    
    "behavior.on.null.values": "delete", # null value → delete document (tombstone)
    "behavior.on.malformed.documents": "warn",
    
    "transforms": "routeToIndex",
    "transforms.routeToIndex.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
    "transforms.routeToIndex.exclude": "internal_field,debug_data"
  }
}
```

---

## How – SMT (Single Message Transforms)

```bash
# SMTs: lightweight, stateless record transformations in connector pipeline
# Applied BEFORE writing to Kafka (source) or AFTER reading from Kafka (sink)

# Built-in SMTs:
# InsertField:    add field (timestamp, offset, partition)
# ReplaceField:   include/exclude/rename fields
# MaskField:      mask sensitive fields
# ValueToKey:     promote value field to record key
# ExtractField:   extract nested field
# Cast:           type conversion
# TimestampConverter: convert timestamp formats
# Filter:         drop records matching condition
# RerouteFields:  dynamic topic/index routing

# Example: ValueToKey + ExtractField for proper Kafka keying
"transforms": "extractKey,addSource",
"transforms.extractKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
"transforms.extractKey.fields": "order_id",
"transforms.addSource.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.addSource.static.field": "source_system",
"transforms.addSource.static.value": "postgres-orders",

# TimestampConverter: ISO string → epoch millis
"transforms": "tsConvert",
"transforms.tsConvert.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
"transforms.tsConvert.field": "created_at",
"transforms.tsConvert.target.type": "unix",
"transforms.tsConvert.format": "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

# Filter: drop records with null value (or specific condition)
"transforms": "filter",
"transforms.filter.type": "org.apache.kafka.connect.transforms.Filter",
"transforms.filter.condition": "value.status == 'INTERNAL_TEST'"
```

---

## How – Debezium CDC (Change Data Capture)

```
Debezium: open-source CDC platform, reads database WAL/binlog
  Postgres:    reads replication slot (WAL)
  MySQL:       reads binlog (binary log)
  MongoDB:     reads oplog
  SQL Server:  reads CDC tables
  Oracle:      reads LogMiner

CDC events:
  c (create):  new row inserted
  u (update):  row updated (before + after image)
  d (delete):  row deleted (before image + null after)
  r (read):    snapshot event (initial load)
```

```bash
# Debezium PostgreSQL Source Connector
POST http://localhost:8083/connectors
{
  "name": "postgres-cdc-orders",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",                    # CDC connectors: 1 task (single WAL stream)
    
    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "${file:/opt/secrets/pg.properties:password}",
    "database.dbname": "mydb",
    "database.server.name": "mydb",      # logical server name (used in topic names)
    
    # Topic naming: {server.name}.{schema}.{table}
    # → mydb.public.orders, mydb.public.payments
    
    "slot.name": "debezium_orders_slot", # unique replication slot per connector
    "plugin.name": "pgoutput",           # pgoutput (PG 10+) | decoderbufs | wal2json
    
    # Tables to capture
    "table.include.list": "public.orders,public.payments,public.customers",
    
    # Schema history (track DDL changes)
    "schema.history.internal.kafka.topic": "schema-history-mydb",
    "schema.history.internal.kafka.bootstrap.servers": "broker1:9092",
    
    # Initial snapshot
    "snapshot.mode": "initial",          # initial | always | never | when_needed
    "snapshot.isolation.mode": "repeatable_read",
    
    # Output format
    "decimal.handling.mode": "double",
    "time.precision.mode": "connect",
    "tombstones.on.delete": "true",      # send tombstone after delete for compaction
    
    # Transforms: extract just the after-state value
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false",
    "transforms.unwrap.delete.handling.mode": "rewrite",
    "transforms.unwrap.add.fields": "op,table,lsn,ts_ms",
    "transforms.unwrap.add.headers": "db,table"
  }
}
```

```
Debezium event structure (without ExtractNewRecordState):
{
  "before": { ... },     # row state before change (null for inserts)
  "after":  { ... },     # row state after change (null for deletes)
  "source": {
    "connector": "postgresql",
    "db": "mydb",
    "table": "orders",
    "lsn": 12345678,      # PostgreSQL WAL LSN
    "ts_ms": 1704067200000
  },
  "op": "c",             # c|u|d|r
  "ts_ms": 1704067200100
}

After ExtractNewRecordState (unwrap):
  → Just the "after" fields + added metadata (op, table, ts_ms)
  → Much simpler for downstream consumers
```

---

## How – MirrorMaker2 (Cross-Cluster Replication)

```
MirrorMaker2: replicate topics between Kafka clusters
  Uses Kafka Connect framework internally
  Supports: active-active, active-passive, hub-spoke topologies
  
Replicated topics naming:
  source.cluster.topic-name (namespaced to avoid conflicts)
  Can be remapped with custom rules
```

```properties
# mm2.properties (MirrorMaker2 config)
clusters = us-east, eu-west

us-east.bootstrap.servers = us-east-broker:9092
eu-west.bootstrap.servers = eu-west-broker:9092

# What to replicate
us-east->eu-west.enabled = true
us-east->eu-west.topics = orders, payments, user-events
us-east->eu-west.topics.blacklist = internal-*, .*_changelog

# Replication factor for mirrored topics in eu-west
us-east->eu-west.replication.factor = 3

# Offset sync: keep consumer group offsets in sync
us-east->eu-west.sync.group.offsets.enabled = true
us-east->eu-west.sync.group.offsets.interval.seconds = 60

# Heartbeat interval (check connector health)
us-east->eu-west.heartbeat.interval.seconds = 10

# Consumer group replication
us-east->eu-west.groups = order-processor, payment-processor
us-east->eu-west.groups.blacklist = console-consumer-*

# Replication lag threshold before alerting
us-east->eu-west.replication.latency.threshold.ms = 30000

# Start MirrorMaker2
bin/connect-mirror-maker.sh mm2.properties

# Monitor MirrorMaker2 via Connect REST API
GET http://localhost:8083/connectors
GET http://localhost:8083/connectors/MirrorSourceConnector/status
GET http://localhost:8083/connectors/MirrorCheckpointConnector/status
```

---

## How – Connect REST API

```bash
# List connectors
GET http://localhost:8083/connectors
GET http://localhost:8083/connectors?expand=status&expand=info

# Get connector status
GET http://localhost:8083/connectors/orders-jdbc-source/status

# Pause/resume connector
PUT http://localhost:8083/connectors/orders-jdbc-source/pause
PUT http://localhost:8083/connectors/orders-jdbc-source/resume

# Restart connector or task
POST http://localhost:8083/connectors/orders-jdbc-source/restart?includeTasks=true&onlyFailed=true
POST http://localhost:8083/connectors/orders-jdbc-source/tasks/0/restart

# Update config
PUT http://localhost:8083/connectors/orders-jdbc-source/config
{ ... new config ... }

# Delete connector
DELETE http://localhost:8083/connectors/orders-jdbc-source

# List plugins
GET http://localhost:8083/connector-plugins

# Validate connector config
PUT http://localhost:8083/connector-plugins/JdbcSourceConnector/config/validate
{ ... config ... }

# Worker info
GET http://localhost:8083/
GET http://localhost:8083/worker-id
```

---

## Why – Kafka Connect vs Custom Code

```
Custom producer/consumer:
  ✅ Full control
  ❌ Boilerplate: offset management, error handling, retries, schema evolution
  ❌ Each integration = new codebase to maintain
  ❌ No built-in exactly-once, dead-letter queue, monitoring

Kafka Connect:
  ✅ Declarative: JSON config, no code
  ✅ 200+ community connectors (Confluent Hub)
  ✅ Built-in: exactly-once (with compatible connectors), DLQ, metrics
  ✅ Horizontal scaling: add workers, tasks auto-distributed
  ✅ Schema evolution with Schema Registry
  ❌ Less flexible for complex transformations (use Kafka Streams for that)
  ❌ Connector quality varies (community vs enterprise)

Rule:
  Simple data movement: Kafka Connect
  Complex stream processing: Kafka Streams or Flink
  Both: Connect for ingestion, Streams for processing
```

---

## Trade-offs

```
JDBC polling vs CDC (Debezium):
  JDBC:   simple, no DB changes needed, poll interval latency (seconds)
          cannot detect deletes without soft-delete column
          higher DB load (full/incremental scan)
  CDC:    real-time (<1s latency), captures all changes (insert/update/delete)
          requires WAL access (replication slot), more complex setup
  → CDC for real-time sync, JDBC for batch/periodic sync

Standalone vs Distributed Connect:
  Standalone: simple, no fault tolerance (single point of failure)
  Distributed: fault tolerant, scalable, REST API management
  → Always distributed in production

Converter: JSON vs Avro:
  JSON:  human-readable, no schema registry, larger size
  Avro:  compact, schema-enforced, schema evolution support, needs Schema Registry
  → Avro for production (schema evolution, compatibility, smaller payloads)

tasks.max:
  Higher: more parallelism (multiple partitions or tables)
  CDC connectors: always 1 (single WAL stream per DB)
  JDBC: 1 per table (if table.whitelist), or more for large tables with partitioning
```

---

## Real-world

```bash
# Monitor connector health (production checklist)
# 1. All connectors RUNNING (not FAILED/PAUSED)
for connector in $(curl -s localhost:8083/connectors | jq -r '.[]'); do
  status=$(curl -s localhost:8083/connectors/$connector/status | jq -r '.connector.state')
  echo "$connector: $status"
done

# 2. Debezium slot lag (PostgreSQL)
SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as lag_bytes
FROM pg_replication_slots;
# → Alert: lag > 1GB (risk of disk full, WAL accumulation)

# 3. Consumer lag for connector group
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group connect-orders-jdbc-source

# Dead Letter Queue (DLQ): handle connector errors
"errors.tolerance": "all",              # skip errors (log + continue)
"errors.deadletterqueue.topic.name": "dlq-orders-jdbc-source",
"errors.deadletterqueue.topic.replication.factor": 3,
"errors.deadletterqueue.context.headers.enable": true,  # include error context in headers
"errors.log.enable": true,
"errors.log.include.messages": true

# Secret management
# Option 1: ExternalSecretProvider
"config.providers": "file",
"config.providers.file.class": "org.apache.kafka.common.config.provider.FileConfigProvider"
# Then use: "${file:/opt/secrets/passwords.properties:db.password}"

# Option 2: Vault Secret Provider (Confluent)
"config.providers": "vault",
"config.providers.vault.class": "io.confluent.connect.secretregistry.rbac.config.provider.VaultConfigProvider"
```

---

## Ghi chú – Chủ đề tiếp theo
> `production.md`: Kafka production operations – JVM tuning, OS config, broker configs for throughput/latency, monitoring (JMX metrics, Prometheus JMX Exporter), consumer lag alerting, security (SASL, TLS, ACLs), MirrorMaker2 DR setup

---

*Cập nhật lần cuối: 2026-05-06*
