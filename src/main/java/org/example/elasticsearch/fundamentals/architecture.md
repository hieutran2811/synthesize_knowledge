# Elasticsearch Architecture & Cluster – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Elasticsearch là gì?

**Elasticsearch** là distributed, RESTful search & analytics engine dựa trên **Apache Lucene**. Lưu trữ data dưới dạng JSON documents, cung cấp near real-time search với full-text capabilities.

```
Lucene: single-node search library (Java)
Elasticsearch: distributed layer on top of Lucene
  - REST API (JSON over HTTP)
  - Cluster management, replication, sharding
  - Near real-time indexing (NRT: default 1s refresh)
```

---

## Components – Cluster Architecture

```
Cluster: collection of nodes sharing same cluster.name
  
Node types:
  Master-eligible:  participate in master election, manage cluster state
  Master (active):  exactly 1, manages cluster: shard allocation, index creation
  Data:             store shards, execute queries
  Ingest:           pre-process documents (ingest pipeline)
  Coordinating:     route requests, merge results (every node is coordinating)
  Remote Cluster:   cross-cluster search/replication
  ML:               machine learning tasks (licensed)

Recommended production layout:
  3+ dedicated master nodes (odd number for quorum)
  N data nodes (tiered: hot/warm/cold)
  2+ coordinating/ingest nodes
```

### Cluster State

```json
// Cluster state: stored in master node, replicated to all nodes
// Includes: mappings, settings, shard allocation, index metadata
// Critical: large cluster state → slow operations

// Check cluster health
GET _cluster/health
{
  "cluster_name": "my-cluster",
  "status": "green",        // green=all shards assigned, yellow=replica missing, red=primary missing
  "number_of_nodes": 6,
  "number_of_data_nodes": 3,
  "active_primary_shards": 150,
  "active_shards": 300,
  "relocating_shards": 0,
  "initializing_shards": 0,
  "unassigned_shards": 0,
  "delayed_unassigned_shards": 0,
  "number_of_pending_tasks": 0,
  "active_shards_percent_as_number": 100.0
}

// Cluster state detail
GET _cluster/state/master_node,nodes,routing_table
```

---

## Components – Index, Shard & Segment

### Index & Shard

```
Index: logical namespace (giống "table" trong SQL)
  - Actual data stored in shards
  - Shard = 1 Lucene index instance

Primary shard: 1 copy of data
Replica shard: copies of primary (redundancy + read scaling)

index.number_of_shards:  fixed at creation (cannot change)
index.number_of_replicas: can change anytime

Routing formula: shard = hash(routing_value) % number_of_shards
  routing_value = document _id (default) hoặc custom routing
```

```bash
# Tạo index
PUT /orders
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "refresh_interval": "1s"
  },
  "mappings": { ... }
}

# Index stats
GET /orders/_stats
GET /_cat/indices/orders?v&h=index,health,status,pri,rep,docs.count,store.size

# Shard allocation
GET /_cat/shards/orders?v&h=index,shard,prirep,state,node
GET /_cluster/allocation/explain
```

### Lucene Segment

```
Lucene Index (per shard):
  Segment 1: immutable, compressed
  Segment 2: immutable
  ...
  In-memory buffer: recent docs (not yet written to disk)

Write path:
  Document → in-memory buffer → refresh (every 1s) → new segment → searchable
  Segments periodically merged (merge = optimize performance)

Refresh: flush in-memory buffer to new segment (making docs searchable)
  Default: 1s → "near real-time"
  Disable during bulk indexing: "refresh_interval": "-1"

Flush: write translog + fsync segments to disk
  Default: every 30min hoặc when translog is 512MB
  Ensures durability after fsync

Translog: write-ahead log (like WAL) between flushes
  Ensures durability for unflushed segments
  Cleared after flush

Force merge: merge all segments to 1 (for read-only historical indices)
  POST /logs-2025-01/_forcemerge?max_num_segments=1
  ✅ Faster searches, less storage
  ❌ Very resource intensive, don't use on active indices
```

---

## How – Node Topology

```yaml
# elasticsearch.yml – Master-eligible node
node.roles: [ master ]
cluster.name: production-cluster
node.name: master-1
network.host: 10.0.1.1
http.port: 9200
transport.port: 9300

# Discovery (seed hosts for bootstrapping)
discovery.seed_hosts: ["master-1:9300", "master-2:9300", "master-3:9300"]
cluster.initial_master_nodes: ["master-1", "master-2", "master-3"]  # only for new cluster!

# Data node (hot tier)
node.roles: [ data_hot, ingest ]
node.attr.data: hot   # custom attribute for tier routing

# Data node (warm tier)
node.roles: [ data_warm ]
node.attr.data: warm

# Data node (cold tier)
node.roles: [ data_cold ]
node.attr.data: cold
```

### ILM Tier Routing

```json
// Index Lifecycle Management: move data through hot → warm → cold → frozen → delete
PUT _ilm/policy/logs_policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": { "max_primary_shard_size": "50gb", "max_age": "1d" },
          "set_priority": { "priority": 100 }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "allocate": { "require": { "data": "warm" } },
          "forcemerge": { "max_num_segments": 1 },
          "shrink": { "number_of_shards": 1 },
          "set_priority": { "priority": 50 }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "allocate": { "require": { "data": "cold" }, "number_of_replicas": 0 },
          "set_priority": { "priority": 0 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": { "delete": {} }
      }
    }
  }
}
```

---

## How – Document Routing

```bash
# Default routing: hash(_id) → consistent shard assignment
# Custom routing: send related docs to same shard (co-location)

# Index with routing
PUT /orders/_doc/1?routing=customer_123
{ "customerId": "customer_123", "amount": 500000 }

# Search with routing (only queries 1 shard)
GET /orders/_search?routing=customer_123
{ "query": { "term": { "customerId": "customer_123" } } }

# Routing alias: enforce routing at index level
PUT /orders/_alias/orders_by_customer
{
  "routing": "customer_id",       # always use customer_id as routing
  "is_write_index": true
}
```

---

## Why – Elasticsearch vs Alternatives

```
ES vs Solr (also Lucene-based):
  Solr: older, XML-heavy config, SolrCloud for distributed
  ES: better REST API, easier setup, better ecosystem (Kibana)

ES vs OpenSearch (AWS fork):
  OpenSearch: fork after Elastic changed license (7.10.2)
  Mostly API compatible, separate roadmaps now

ES vs Splunk:
  Splunk: enterprise log management, expensive
  ES + Kibana: open source, more setup work

ES vs MongoDB Atlas Search:
  Atlas Search: built into MongoDB, Lucene-based
  ES: standalone, more features, more mature

ES vs Typesense/Meilisearch:
  Typesense/Meili: simple search, fast, developer-friendly
  ES: complex, powerful analytics, large scale
```

---

## Trade-offs

```
Shards:
More shards:
✅ More parallelism (faster for large datasets)
❌ Overhead per shard (heap, file handles, segment metadata)
❌ Slow cluster operations with many indices/shards (cluster state size)
→ Rule: 10-50GB per shard (hot data), 50GB for warm/cold
→ Total shards: keep under 20 per GB of heap

Replicas:
More replicas:
✅ Better read throughput, higher availability
❌ More storage, more indexing overhead
→ Production: 1 replica minimum (green cluster)
→ Read-heavy: 2-3 replicas

Refresh interval:
1s (default):   near real-time search, more small segments, more merge work
30s or -1:      better indexing throughput (bulk load)
→ During bulk indexing: set -1, then restore to 1s
```

---

## Real-world – JVM & System Config

```yaml
# jvm.options
-Xms16g
-Xmx16g    # Heap: same for Xms và Xmx (no GC resize)
           # Max: 50% of RAM, but NEVER > 31GB (compressed OOPs threshold)
           # Leave ≥ 50% for OS file cache (Lucene heavily uses OS cache)

# G1GC (default ES 7+)
-XX:+UseG1GC
-XX:G1HeapRegionSize=16m
-XX:InitiatingHeapOccupancyPercent=30

# system settings (/etc/sysctl.conf)
vm.max_map_count=262144  # for Lucene mmap
vm.swappiness=1          # almost disable swap (OOM better than swapping)

# File descriptors (/etc/security/limits.conf)
elasticsearch soft nofile 65536
elasticsearch hard nofile 65536
elasticsearch memlock unlimited  # disable swap
```

---

## Ghi chú – Chủ đề tiếp theo
> `indexing_mapping.md`: Index mapping types, analyzers, tokenizers, field types, dynamic mapping, ingest pipeline

---

*Cập nhật lần cuối: 2026-05-06*
