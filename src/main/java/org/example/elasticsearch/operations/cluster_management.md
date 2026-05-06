# Elasticsearch Cluster Management & Operations – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Cluster Management

Elasticsearch cluster management bao gồm: lifecycle của indices (ILM, snapshots), cluster health monitoring, rolling upgrades, troubleshooting, và cross-cluster replication.

```
Operations pillars:
  ILM:          automate index lifecycle (hot→warm→cold→delete)
  Snapshots:    backup & restore (disaster recovery)
  Monitoring:   cluster health, node metrics, slow queries
  Upgrades:     rolling upgrades (zero downtime)
  CCR:          Cross-Cluster Replication (geo-distribution, DR)
```

---

## How – Index Lifecycle Management (ILM)

```bash
# Define ILM policy (full production example)
PUT _ilm/policy/logs_policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50gb",
            "max_age": "1d",
            "max_docs": 200000000
          },
          "set_priority": { "priority": 100 },
          "forcemerge": {                        # optional: force merge in hot (not recommended)
            "max_num_segments": 4
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "allocate": {
            "require": { "data": "warm" },       # move to warm tier
            "number_of_replicas": 1
          },
          "forcemerge": { "max_num_segments": 1 },
          "shrink": { "number_of_shards": 1 },   # reduce shards
          "set_priority": { "priority": 50 },
          "readonly": {}                          # make read-only
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "allocate": {
            "require": { "data": "cold" },
            "number_of_replicas": 0              # drop replicas (cost saving)
          },
          "set_priority": { "priority": 0 }
        }
      },
      "frozen": {
        "min_age": "90d",
        "actions": {
          "searchable_snapshot": {
            "snapshot_repository": "s3_repository",
            "force_merge_index": true
          }
        }
      },
      "delete": {
        "min_age": "365d",
        "actions": { "delete": {} }
      }
    }
  }
}

# Index template with ILM
PUT _index_template/logs_template
{
  "index_patterns": ["logs-*"],
  "template": {
    "settings": {
      "index.lifecycle.name": "logs_policy",
      "index.lifecycle.rollover_alias": "logs",
      "index.routing.allocation.require.data": "hot"
    },
    "aliases": { "logs": { "is_write_index": true } }
  }
}

# Bootstrap first index
PUT logs-000001
{
  "aliases": { "logs": { "is_write_index": true } }
}

# Monitor ILM
GET logs-*/_ilm/explain
GET _ilm/status

# Retry failed ILM step
POST logs-000001/_ilm/retry

# Move to next step manually
POST _ilm/move/logs-000001
{
  "current_step": { "phase": "warm", "action": "forcemerge", "name": "forcemerge" },
  "next_step": { "phase": "warm", "action": "shrink", "name": "shrink" }
}
```

---

## How – Snapshots & Restore

```bash
# Register snapshot repository
PUT _snapshot/s3_repository
{
  "type": "s3",
  "settings": {
    "bucket": "my-es-backups",
    "region": "ap-southeast-1",
    "base_path": "elasticsearch/snapshots",
    "compress": true,
    "chunk_size": "1gb",
    "max_snapshot_bytes_per_sec": "100mb",
    "max_restore_bytes_per_sec": "500mb"
  }
}

# For GCS:
PUT _snapshot/gcs_repository
{
  "type": "gcs",
  "settings": {
    "bucket": "my-es-backups",
    "base_path": "snapshots"
  }
}

# Verify repository
POST _snapshot/s3_repository/_verify

# Create snapshot (incremental: only changed segments)
PUT _snapshot/s3_repository/snapshot_2024_01_15
{
  "indices": "logs-*,orders-*",           # specific patterns
  "ignore_unavailable": true,
  "include_global_state": false,           # don't snapshot cluster settings/templates
  "partial": false,                        # fail if any shard unavailable
  "metadata": {
    "taken_by": "admin",
    "reason": "daily backup"
  }
}

# Check snapshot status
GET _snapshot/s3_repository/snapshot_2024_01_15
GET _snapshot/s3_repository/_current         # currently running snapshot

# List snapshots
GET _snapshot/s3_repository/_all
GET _snapshot/s3_repository/snapshot_2024_*  # pattern

# Restore snapshot
POST _snapshot/s3_repository/snapshot_2024_01_15/_restore
{
  "indices": "orders-*",
  "ignore_unavailable": true,
  "include_global_state": false,
  "rename_pattern": "orders-(.+)",           # rename: orders-2024 → restored-orders-2024
  "rename_replacement": "restored-orders-$1",
  "index_settings": {
    "index.number_of_replicas": 0            # restore without replicas (faster)
  },
  "ignore_index_settings": ["index.refresh_interval"]
}

# Snapshot lifecycle policy (SLM)
PUT _slm/policy/daily_snapshots
{
  "schedule": "0 30 1 * * ?",            # cron: 1:30 AM daily
  "name": "<daily-snap-{now/d}>",         # date-based name
  "repository": "s3_repository",
  "config": {
    "indices": ["logs-*", "orders-*"],
    "include_global_state": false
  },
  "retention": {
    "expire_after": "30d",               # keep 30 days of snapshots
    "min_count": 5,
    "max_count": 50
  }
}

# Execute SLM policy now
POST _slm/policy/daily_snapshots/_execute
GET _slm/policy/daily_snapshots          # check status
```

---

## How – Rolling Upgrades

```
Rolling upgrade: upgrade nodes one at a time (zero downtime)
  Order: dedicated master nodes first → data nodes → coordinating nodes
  
Steps for each node:
  1. Disable shard allocation (prevent unnecessary shard movement)
  2. Stop node gracefully (flush buffers, commit offsets)
  3. Upgrade Elasticsearch binary
  4. Start node
  5. Wait for node to join cluster
  6. Re-enable shard allocation
  7. Wait for cluster to turn green
  8. Repeat for next node
```

```bash
# 1. Disable shard allocation
PUT _cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.enable": "primaries"  # allow only primary recovery
    # "none" = completely disable, but primaries may not recover
  }
}

# 2. Flush (for older ES) or sync flush
POST _flush/synced    # ES 7.x (deprecated in 8.x)
POST /_flush          # ES 8.x

# 3. Stop node gracefully
# systemctl stop elasticsearch

# 4. Upgrade, then start
# systemctl start elasticsearch

# 5. Wait for node to join
GET _cat/nodes?v

# 6. Re-enable allocation
PUT _cluster/settings
{
  "persistent": {
    "cluster.routing.allocation.enable": null  # reset to default (all)
  }
}

# 7. Wait for green
GET _cluster/health?wait_for_status=green&timeout=300s

# Repeat for next node
```

---

## How – Cluster Monitoring

```bash
# Cluster health (quick overview)
GET _cluster/health
GET _cluster/health?level=indices    # per-index health
GET _cluster/health?level=shards     # per-shard health
GET _cluster/health?wait_for_status=green&timeout=30s

# Cluster stats
GET _cluster/stats?human

# Nodes overview
GET _cat/nodes?v&h=name,ip,heap.percent,ram.percent,cpu,load_1m,node.role,master
GET _nodes/stats                             # detailed stats per node
GET _nodes/stats/jvm,os,indices,process      # specific stat groups

# Indices overview
GET _cat/indices?v&h=index,health,status,pri,rep,docs.count,store.size&s=store.size:desc
GET _cat/shards?v&h=index,shard,prirep,state,docs,store,node&s=index

# Index stats
GET orders/_stats
GET _stats/store,indexing,search,merge,refresh,flush

# Pending cluster tasks
GET _cluster/pending_tasks

# Shard allocation explain (why shard unassigned)
GET _cluster/allocation/explain
{
  "index": "orders",
  "shard": 0,
  "primary": true
}

# Hot threads (CPU diagnosis)
GET _nodes/hot_threads?threads=5

# Task management
GET _tasks?actions=*search*&detailed=true
GET _tasks?actions=*reindex*
DELETE _tasks/{task_id}  # cancel task

# Cat API collection
GET _cat/health?v
GET _cat/master?v
GET _cat/allocation?v                # disk usage per node
GET _cat/segments?v                  # segment info
GET _cat/recovery?v                  # shard recovery status
GET _cat/fielddata?v&fields=*        # fielddata memory usage
GET _cat/thread_pool?v               # thread pool stats
```

---

## How – Cross-Cluster Replication (CCR)

```bash
# CCR: replicate indices from leader cluster to follower cluster
# Use cases: geo-distribution, DR, centralized reporting

# On follower cluster: add remote cluster connection
PUT _cluster/settings
{
  "persistent": {
    "cluster.remote.leader_cluster.seeds": ["leader-es-1:9300", "leader-es-2:9300"],
    "cluster.remote.leader_cluster.transport.ping_schedule": "30s"
  }
}

# Or via REST API (preferred):
PUT _remote_clusters/leader_cluster
{
  "seeds": ["leader-es-1:9300"],
  "transport.ping_schedule": "30s"
}

# Create follower index (replicate from leader)
PUT /orders-follower/_ccr/follow
{
  "remote_cluster": "leader_cluster",
  "leader_index": "orders",
  "max_read_request_operation_count": 5120,
  "max_outstanding_read_requests": 12,
  "max_read_request_size": "32mb",
  "max_write_request_operation_count": 5120,
  "max_write_request_size": "9223372036854775807b",
  "max_outstanding_write_requests": 9,
  "max_write_buffer_count": 2147483647,
  "max_write_buffer_size": "512mb",
  "max_retry_delay": "500ms",
  "read_poll_timeout": "1m"
}

# Auto-follow: automatically follow new indices matching pattern
PUT _ccr/auto_follow/logs_auto_follow
{
  "remote_cluster": "leader_cluster",
  "leader_index_patterns": ["logs-*"],
  "follow_index_pattern": "{{leader_index}}-replica"
}

# Monitor CCR
GET /orders-follower/_ccr/stats
GET _ccr/stats
GET _ccr/auto_follow/logs_auto_follow

# Pause/resume replication
POST /orders-follower/_ccr/pause_follow
POST /orders-follower/_ccr/resume_follow

# Unfollow (promote to regular index)
POST /orders-follower/_ccr/unfollow
```

---

## How – Cluster Settings & Troubleshooting

```bash
# Cluster-wide settings
GET _cluster/settings?include_defaults=true

# Common settings to tune
PUT _cluster/settings
{
  "persistent": {
    # Shard rebalancing
    "cluster.routing.rebalance.enable": "all",       # all | primaries | replicas | none
    "cluster.routing.allocation.balance.shard": 0.45,
    "cluster.routing.allocation.balance.index": 0.55,
    
    # Recovery throttle (don't overwhelm during node add/remove)
    "indices.recovery.max_bytes_per_sec": "200mb",
    
    # Awareness: spread shards across AZs
    "cluster.routing.allocation.awareness.attributes": "zone",
    "cluster.routing.allocation.awareness.force.zone.values": "az-a,az-b,az-c",
    
    # Watermarks: disk-based allocation
    "cluster.routing.allocation.disk.watermark.low": "85%",
    "cluster.routing.allocation.disk.watermark.high": "90%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "95%",
    
    # Circuit breaker (prevent OOM)
    "indices.breaker.total.limit": "95%",
    "indices.breaker.request.limit": "60%",
    "indices.breaker.fielddata.limit": "40%"
  }
}

# Reroute: manually assign/cancel shard
POST _cluster/reroute
{
  "commands": [
    {
      "allocate_stale_primary": {        # force-assign stale primary (data loss!)
        "index": "orders", "shard": 0,
        "node": "data-node-1",
        "accept_data_loss": true
      }
    },
    {
      "move": {
        "index": "orders", "shard": 1,
        "from_node": "data-node-1",
        "to_node": "data-node-2"
      }
    },
    {
      "cancel": {
        "index": "orders", "shard": 2,
        "node": "data-node-1"
      }
    }
  ]
}

# Flush + close index (free heap/disk without deleting)
POST /old-logs-2023/_flush
POST /old-logs-2023/_close
# Re-open
POST /old-logs-2023/_open
```

---

## Why – Operations Best Practices

```
Why dedicated master nodes?
  Master manages cluster state: adds/removes nodes, allocates shards
  Combined master+data: data node GC pause → master unresponsive → split-brain risk
  Dedicated masters: small heap (4-8GB), no data → stable, fast
  3 dedicated masters (odd number): prevents split-brain (quorum = 2/3)

Why ILM over manual management?
  Manual: cron jobs, scripts, human error, inconsistent
  ILM: declarative, automatic, auditable, integrated with rollover
  → Set and forget; ILM handles rotation, tiering, deletion

Why SLM over manual snapshots?
  SLM: scheduled, consistent naming, automatic retention
  Manual: forget to run, inconsistent, no automatic cleanup
  → RPO compliance: SLM ensures snapshots happen on schedule

Why zone awareness?
  Without: 2 replicas may land on same AZ → AZ failure = data unavailable
  With: force primary + replica on different AZs → AZ failure tolerated
```

---

## Trade-offs

```
ILM shrink in warm:
  ✅ Fewer shards = less overhead, cheaper queries
  ❌ Read-only during shrink, node affinity required
  → Essential for time-series: daily rollover → 1 shard in warm

Searchable snapshots (frozen tier):
  ✅ Very cheap storage (S3 cost), very low RAM
  ❌ High query latency (partial caching, fetch from S3)
  → Use for compliance/archival; not for active analytics

CCR vs Snapshot restore for DR:
  CCR: near real-time replication, lower RPO (<1 min), higher cost (double storage+write)
  Snapshots: periodic (RPO = snapshot interval), lower cost
  → Critical data (financial): CCR; logs/analytics: snapshots

Rolling upgrade timing:
  One node at a time: safest, slowest
  Multiple nodes at once (if cluster can handle): faster, riskier
  → Never remove > 50% of data nodes simultaneously
```

---

## Real-world Runbook

```bash
# 1. Yellow cluster: missing replicas
GET _cluster/health
GET _cat/shards?v&h=index,shard,prirep,state,node
# → UNASSIGNED replicas: check disk space, allocation settings
GET _cluster/allocation/explain

# 2. Red cluster: missing primaries
# → Critical: data may be unavailable
GET _cat/shards?v&h=index,shard,prirep,state
# Check if node is just restarting (wait 5-10 min)
GET _cat/nodes?v
# If node lost: check if replica can be promoted
# Last resort: allocate_stale_primary (data loss!)

# 3. High heap usage (> 80%)
GET _nodes/stats/jvm
GET _cat/fielddata?v  # check fielddata usage
POST /heavy-index/_cache/clear?fielddata=true
# Consider: forcemerge to reduce segment count, reduce shard count

# 4. Unassigned shards after disk full
# Free disk space, then:
PUT _cluster/settings
{ "transient": { "cluster.routing.allocation.enable": "all" } }

# 5. Slow searches
GET _nodes/hot_threads
# Check slow log
GET /orders/_settings?filter_path=*.settings.index.search.slowlog*
# Profile query
GET /orders/_search { "profile": true, "query": {...} }
```

---

## Ghi chú – Chủ đề tiếp theo
> `security.md`: TLS/SSL setup (inter-node, client), user authentication (native, LDAP, SAML, OIDC), RBAC (roles, privileges, field/document-level security), audit logging, API keys, Kibana security

---

*Cập nhật lần cuối: 2026-05-06*
