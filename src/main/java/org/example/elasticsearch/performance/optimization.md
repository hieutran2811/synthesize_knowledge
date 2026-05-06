# Elasticsearch Performance & Optimization – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Performance Optimization

Elasticsearch performance tối ưu hóa ở 3 tầng: **Indexing** (write throughput), **Search** (query latency), và **Cluster** (resource efficiency). Mỗi tầng có các knobs riêng với trade-offs rõ ràng.

```
Performance pillars:
  Indexing:  throughput of document ingestion
  Search:    latency of queries and aggregations
  Storage:   disk I/O, segment management, heap usage
  Cluster:   node sizing, shard strategy, caching
```

---

## Components – Indexing Optimization

### Bulk Indexing

```bash
# Bulk API: always use for mass indexing
# Optimal: 5-15MB per request, 1000-5000 docs per batch
POST /_bulk
{ "index": { "_index": "orders" } }
{ "order_id": "1", "amount": 500000, "status": "pending" }
{ "index": { "_index": "orders" } }
{ "order_id": "2", "amount": 1200000, "status": "completed" }

# Python example: concurrent bulk with backpressure
# from elasticsearch.helpers import parallel_bulk
# actions = [{"_index": "orders", "_source": doc} for doc in docs]
# for success, info in parallel_bulk(es, actions, thread_count=4, chunk_size=1000):
#     if not success: print(f"Failed: {info}")
```

```bash
# Before bulk load: optimize for write
PUT /orders/_settings
{
  "index": {
    "refresh_interval": "-1",               # disable refresh (no real-time search needed)
    "number_of_replicas": 0,                # no replicas during load (add after)
    "translog.durability": "async",         # async translog fsync (faster, small risk)
    "translog.sync_interval": "60s"
  }
}

# After bulk load: restore
PUT /orders/_settings
{
  "index": {
    "refresh_interval": "1s",
    "number_of_replicas": 1,
    "translog.durability": "request"         # back to safe
  }
}

# Force merge after bulk load (optional, for read-only indices)
POST /orders/_forcemerge?max_num_segments=1
# ✅ Faster searches, less storage
# ❌ Very expensive, blocks shard, avoid on active indices
```

### Mapping Optimization for Indexing

```bash
# Disable features not needed
PUT /logs
{
  "mappings": {
    "_source": { "enabled": true },         # needed for reindex; disable if pure search
    "properties": {
      "message": {
        "type": "text",
        "norms": false,                      # no TF-IDF normalization (save memory)
        "index_options": "freqs"             # freq only; no positions (save space, no phrase queries)
      },
      "level": {
        "type": "keyword",
        "doc_values": true,
        "eager_global_ordinals": true        # pre-build ordinals at index time (faster first agg)
      },
      "metadata": {
        "type": "object",
        "enabled": false                     # stored in _source only, not indexed
      },
      "raw_log": {
        "type": "keyword",
        "index": false,                      # stored, not searchable
        "doc_values": false                  # not aggregatable
      }
    }
  }
}
```

---

## Components – Search Optimization

### Query Optimization

```bash
# BAD: wildcard leading star (full scan)
{ "query": { "wildcard": { "name": "*phone" } } }

# GOOD: use n-gram or completion for prefix search
# Or: prefix on keyword field (efficient with BKD index for numbers, not text)
{ "query": { "prefix": { "name.keyword": "iphone" } } }

# BAD: script in filter context (no caching)
{ "query": { "script": { "source": "doc['price'].value > 1000000" } } }

# GOOD: range query (cached, fast)
{ "query": { "range": { "price": { "gt": 1000000 } } } }

# BAD: expensive aggregation on analyzed text field
{ "aggs": { "names": { "terms": { "field": "name" } } } }  # mapping error: text not aggregatable

# GOOD: use keyword field for aggregations
{ "aggs": { "names": { "terms": { "field": "name.keyword" } } } }

# Profile API: diagnose slow queries
GET /orders/_search?human
{
  "profile": true,
  "query": {
    "bool": {
      "must": [{ "match": { "name": "iphone" } }],
      "filter": [{ "term": { "status": "active" } }]
    }
  }
}
# → Check: "time_in_nanos" per phase, "collector" breakdown
```

### Routing Optimization

```bash
# Custom routing: queries only target 1 shard instead of all
# Index with routing
PUT /orders/_doc/1?routing=customer_VIP001
{ "customer_id": "VIP001", "amount": 5000000 }

# Search with routing (only hits 1 shard)
GET /orders/_search?routing=customer_VIP001
{ "query": { "term": { "customer_id": "VIP001" } } }

# Routing alias (enforce routing at index level)
POST /_aliases
{
  "actions": [{
    "add": {
      "index": "orders",
      "alias": "orders_by_customer",
      "routing": "customer_id",           # use customer_id field as routing
      "search_routing": "customer_id",
      "index_routing": "customer_id"
    }
  }]
}
```

---

## Components – Caching

```
Cache types:
  1. Node query cache (filter cache):
     - Caches filter context queries (term, range, bool.filter)
     - Per segment, up to indices.queries.cache.size (default 10% heap)
     - LRU eviction: evict least recently used
     - Key: query structure + segment combination
     - Very effective for repeated filter queries (dashboard refresh)

  2. Shard request cache:
     - Caches entire search response for size:0 (agg-only) queries
     - Invalidated on refresh (when segment changes)
     - Per shard, configurable per index
     - Key: full request JSON
     - Effective for: dashboard aggregations on static historical data

  3. Field data cache:
     - text fields sorted/aggregated → loaded into heap as fielddata
     - AVOID: very expensive, can cause OOM
     - Use doc_values (default) instead → stored on disk, not in heap
     - indices.fielddata.cache.size: limit fielddata heap usage

  4. OS page cache:
     - OS caches frequently accessed disk data
     - Lucene deliberately uses OS page cache (not JVM heap)
     - Keep heap ≤ 50% of RAM → leave rest for OS page cache
```

```bash
# Check cache stats
GET /_stats/query_cache,request_cache,fielddata

# Per-index: enable/disable request cache
PUT /orders/_settings
{
  "index.requests.cache.enable": true   # default true for size:0 queries
}

# Per-request: bypass cache
GET /orders/_search?request_cache=false
{ "size": 0, "aggs": { ... } }

# Clear caches
POST /orders/_cache/clear
POST /_cache/clear?query=true&fielddata=true&request=true

# Monitor: hit rates
GET /_nodes/stats/indices/query_cache
# → "hit_count", "miss_count", "memory_size_in_bytes"
# → Goal: hit rate > 80% for dashboard queries
```

---

## Components – Shard Strategy

```
Shard sizing rules:
  Hot data (active writes/searches):
    - 10-50GB per shard (sweet spot)
    - Max 200M documents per shard (performance degrades beyond)
    
  Warm/cold data:
    - Up to 50-100GB per shard
    - Fewer, larger shards = less overhead
    
  Shards per GB heap:
    - Keep total shards < 20 per GB of heap
    - 30GB heap → max ~600 shards
    - Excessive shards → slow cluster state operations

  Under-sharding problems:
    - 1 shard = no parallelism on that index
    - Can't parallelize across multiple nodes
    
  Over-sharding problems:
    - Too many small shards = overhead (memory, CPU, file handles)
    - Small segments = more merge work, more metadata
    - Cluster state size grows (mapped in heap)
```

```bash
# Shrink index: reduce shard count (warm/cold optimization)
# Prerequisites: all shards on 1 node, index read-only
PUT /orders-2024-01/_settings
{
  "index.routing.allocation.require._name": "warm-node-1",
  "index.blocks.write": true
}

POST /orders-2024-01/_shrink/orders-2024-01-shrunk
{
  "settings": {
    "index.number_of_shards": 1,
    "index.number_of_replicas": 1,
    "index.codec": "best_compression"  # DEFLATE (higher compression for cold data)
  },
  "aliases": { "orders-historical": {} }
}

# Split index: increase shard count (cannot add shards to existing index)
POST /orders/_split/orders-v2
{
  "settings": { "index.number_of_shards": 6 }  # must be multiple of current
}

# Rollover: create new index when current too large
POST /orders/_rollover
{
  "conditions": {
    "max_age": "7d",
    "max_primary_shard_size": "50gb",
    "max_docs": 200000000
  }
}
```

---

## How – JVM & Memory Tuning

```yaml
# jvm.options
-Xms31g
-Xmx31g    # 31GB: just below compressed OOPs threshold (32GB)
           # Always equal Xms = Xmx (no resize GC pressure)
           # Never > 50% of RAM (rest for OS page cache)

# G1GC (default ES 8+)
-XX:+UseG1GC
-XX:G1HeapRegionSize=32m           # 32m for 31GB heap
-XX:InitiatingHeapOccupancyPercent=30
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/tmp/elasticsearch.hprof
-XX:ErrorFile=/var/log/elasticsearch/hs_err.log
-XX:+ExitOnOutOfMemoryError        # restart JVM on OOM (don't limp)

# Compressed OOPs (object pointer compression)
# Heap ≤ ~32GB: 32-bit pointers → more objects per cache line
# Heap > 32GB: 64-bit pointers → ~50% more memory per reference
# → Heap 30GB often faster than 34GB!
```

```bash
# Check JVM heap usage
GET /_nodes/stats/jvm
# → "heap_used_percent": keep < 75% (GC pressure above)
# → "gc.collectors.old.collection_time_in_millis": high = GC issue

# Heap breakdown
GET /_cat/nodes?v&h=name,heap.percent,ram.percent,cpu,load_1m,node.role
```

---

## How – Index-level Optimizations

```bash
# Codec: trade CPU for disk space
PUT /logs-cold
{
  "settings": {
    "codec": "best_compression"    # DEFLATE: slower writes, ~30% smaller
    # "codec": "default"           # LZ4: faster writes (default)
  }
}

# Disable _source for pure analytics (cannot update/reindex!)
PUT /analytics
{
  "mappings": {
    "_source": {
      "enabled": false,
      "includes": ["timestamp", "user_id"],  # keep only needed fields
      "excludes": ["raw_data", "debug_info"]
    }
  }
}

# Lazy loading fielddata (expensive, use doc_values instead)
PUT /products/_mapping
{
  "properties": {
    "description": {
      "type": "text",
      "fielddata": false           # default false for text; keep it false
    }
  }
}

# Index sorting (optimize sort + range queries)
PUT /orders
{
  "settings": {
    "index": {
      "sort.field": ["order_date", "customer_id"],
      "sort.order": ["desc", "asc"]
    }
  }
}
# Benefit: early termination on sorted queries (skip full scan)
# Cost: slower indexing (must maintain sort order during merge)
```

---

## How – Slow Log & Diagnostics

```yaml
# elasticsearch.yml
index.search.slowlog.threshold.query.warn: 10s
index.search.slowlog.threshold.query.info: 5s
index.search.slowlog.threshold.fetch.warn: 1s
index.indexing.slowlog.threshold.index.warn: 10s

# Or per-index
PUT /orders/_settings
{
  "index.search.slowlog.threshold.query.warn": "5s",
  "index.search.slowlog.threshold.query.info": "1s",
  "index.indexing.slowlog.threshold.index.warn": "5s"
}
```

```bash
# Hot threads: find CPU-intensive threads
GET /_nodes/hot_threads?threads=5&type=cpu&interval=1s

# Task management: find slow/stuck tasks
GET /_tasks?actions=*search*&detailed=true&human=true
GET /_tasks/{task_id}
POST /_tasks/{task_id}/_cancel  # cancel runaway task

# Explain why shard unassigned
GET /_cluster/allocation/explain
{
  "index": "orders",
  "shard": 0,
  "primary": true
}
```

---

## Why – Design Decisions

```
Why doc_values over fielddata?
  fielddata: loaded into JVM heap on-demand (expensive, OOM risk)
    → heap = limited (≤31GB); fielddata competes with query cache
  doc_values: column-store on disk (SSI format)
    → Backed by OS page cache (not JVM heap)
    → Default for all non-text fields since ES 2.0
    → Cost: slightly larger disk footprint

Why filter cache (not query cache)?
  filter context (term, range) → deterministic, same result regardless of scoring
  → Safe to cache across different queries sharing same filter
  query context (match) → result depends on score → hard to cache (query varies)
  → Filters cached per segment; invalidated when segment merged

Why not sort by _score for dashboards?
  _score: relevance sorting (text search)
    → Different for each query, not cacheable
    → CPU cost: BM25 per document
  Filter + sort by field:
    → No score computation (filter context)
    → Sort on doc_values (fast column-store)
    → Result cacheable in request cache
  → Dashboards: always use filter + field sort, never relevance sort
```

---

## Trade-offs

```
refresh_interval:
  1s:   near real-time, more small segments, more merge overhead
  30s:  less segments, better throughput
  -1:   best throughput (manual refresh)
  → Balance: 5s for most write-heavy indices

Number of replicas during bulk:
  0:    2x faster (no replication)
  1:    safer (one failure tolerated), 50% slower
  → Bulk: 0 replicas, then add after; always restore before going live

Forcemerge:
  ✅ Fewer segments → faster searches
  ❌ CPU/I/O intensive, blocks shard
  → Only for read-only/closed indices (daily log indices after rollover)

Compression (best_compression vs default):
  default (LZ4):           fast write, larger size
  best_compression:        ~30% smaller, slower write/read
  → Warm/cold: best_compression; hot: default

Mapping enabled=false vs index=false:
  enabled=false (object):  field not indexed or stored in doc_values
                           still in _source (no query on this field)
  index=false (field):     stored in doc_values, not indexed (aggregatable, not searchable)
  store=true:              store field outside _source (for partial source retrieval)
```

---

## Real-world Checklist

```
Indexing performance checklist:
  ✅ Use Bulk API (never single-doc indexing for high volumes)
  ✅ Disable refresh during bulk: refresh_interval=-1
  ✅ Set replicas=0 during initial load
  ✅ Use multiple parallel bulk clients (match to CPU cores)
  ✅ Monitor: indexing rate, bulk rejections, merge rate
  ✅ Tune JVM heap (≤31GB), leave RAM for OS page cache

Search performance checklist:
  ✅ Use filter context for non-scoring conditions
  ✅ Avoid wildcards with leading *
  ✅ Use keyword fields for aggregations (not analyzed text)
  ✅ Use doc_values (default) — avoid fielddata
  ✅ Set size=0 for aggregation-only queries
  ✅ Enable request cache for dashboards
  ✅ Use routing for high-cardinality tenant data
  ✅ Profile slow queries with _profile API

Shard strategy checklist:
  ✅ 10-50GB per shard for hot data
  ✅ < 20 shards per GB of heap
  ✅ Use ILM: rollover → shrink on warm tier
  ✅ Force merge read-only indices to 1 segment
  ✅ Monitor: UnassignedShards, search latency p99, indexing rate
```

---

## Ghi chú – Chủ đề tiếp theo
> `cluster_management.md`: Rolling upgrades, index lifecycle management (ILM), snapshot & restore, cross-cluster replication (CCR), cluster monitoring (cat APIs, _nodes, _cluster/stats), troubleshooting playbook

---

*Cập nhật lần cuối: 2026-05-06*
