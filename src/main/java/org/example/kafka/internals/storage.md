# Kafka Storage – Log, Retention & Compaction – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka Storage Model

Kafka lưu data dưới dạng **commit log** – append-only, immutable, ordered sequence of records on disk. Đây là nền tảng của tất cả tính năng Kafka: replay, retention, compaction, tiered storage.

```
Kafka storage stack:
  Topic → Partition → Log (directory on disk) → Segments (files)

Physical layout:
  /data/kafka/
    orders-0/              # topic "orders", partition 0
      00000000000000000000.log    # segment file (records)
      00000000000000000000.index  # offset index
      00000000000000000000.timeindex  # timestamp index
      00000000000000001000.log    # next segment (after rollover)
      00000000000000001000.index
      leader-epoch-checkpoint     # leader epoch file
    orders-1/              # partition 1
    ...
```

---

## Components – Log Segments

```
Segment: unit of storage rotation
  Active segment: current segment being written to
  Closed segment: full/old segments (eligible for retention/compaction)

Segment rollover triggers:
  log.segment.bytes (default 1GB): size threshold
  log.roll.ms (default 7 days):    time threshold
  log.roll.hours: legacy alias for log.roll.ms

Segment naming: base offset of first record
  00000000000000000000.log = starts at offset 0
  00000000000000001000.log = starts at offset 1000
```

### Index Files

```
Offset Index (.index):
  Sparse index: relative offset → position in .log file
  Every ~4KB of log data → 1 index entry
  Binary search for offset → jump to position
  
Timestamp Index (.timeindex):
  timestamp → relative offset
  Used for time-based seek (consumer offsetsForTimes)
  
Transaction Index (.txnindex):
  tracks aborted transactions (for read_committed consumers)
```

---

## How – Write Path

```
Producer → Broker → Log
  1. Record arrives at leader partition
  2. Write to in-memory page cache (OS)
  3. Write to producer batch format
  4. Append to active segment .log file
  5. Update .index và .timeindex
  6. Flush to disk: per flush.messages or flush.ms (usually OS manages this)
  7. Replicate to followers (ISR)
  8. Return ACK to producer

Key: Kafka does NOT fsync per message (relies on OS page cache + replication for durability)
  → Much faster than traditional databases (no fsync overhead)
  → Durability comes from replication, not fsync
```

```properties
# Log configuration (server.properties)
log.dirs=/data/kafka                 # can be multiple: /data/kafka1,/data/kafka2
log.segment.bytes=1073741824         # 1GB per segment
log.roll.ms=604800000                # 7 days
log.flush.interval.messages=Long.MAX_VALUE  # rely on OS flush
log.flush.interval.ms=Long.MAX_VALUE        # rely on OS flush (default)
log.index.size.max.bytes=10485760    # 10MB max index size
log.index.interval.bytes=4096        # index every 4KB
```

---

## How – Retention Policies

```
Retention: when to delete old data

Types:
  1. Time-based:  delete segments older than retention.ms
  2. Size-based:  delete oldest segments when log > retention.bytes
  3. Compact:     only keep latest value per key (tombstone for deletes)
  4. Compact+Delete: compaction + time/size retention (hybrid)

Retention is per-segment (delete entire segments, not individual records)
Active segment never deleted (even if old)
```

```bash
# Default topic retention
log.retention.hours=168          # 7 days (default)
log.retention.bytes=-1           # unlimited by default
log.retention.check.interval.ms=300000  # check every 5 min

# Per-topic override
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders \
  --alter --add-config \
  retention.ms=86400000,\          # 24 hours
  retention.bytes=10737418240      # 10GB
  
# Unlimited retention (for audit, compliance)
kafka-configs.sh --alter --entity-type topics --entity-name audit-log \
  --add-config retention.ms=-1,retention.bytes=-1
```

---

## How – Log Compaction

```
Compaction: keep only the latest record per key
  - Useful for: state snapshots, changelog topics, user profiles
  - Tombstone: record with value=null → mark key for deletion
    (retained for delete.retention.ms = 24h default, then removed)
  
  Before compaction:
    [k1:v1] [k2:v1] [k1:v2] [k3:v1] [k2:v2] [k1:v3]
  
  After compaction:
    [k1:v3] [k2:v2] [k3:v1]          # latest value per key retained
  
  Compaction guarantees:
    - Consumers always see latest value for each key
    - Order of latest values preserved
    - At-least-once delivery: consumer may see multiple values during compaction
    - Active segment never compacted

Compacted topic use cases:
  - Kafka Streams changelog (state store backup)
  - Event sourcing: current state of each entity
  - User settings, configurations
  - CDC final state
```

```bash
# Create compacted topic
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic user-profiles \
  --config cleanup.policy=compact \
  --config min.cleanable.dirty.ratio=0.5 \
  --config segment.ms=3600000  # rollover every hour (compact older segments faster)

# Compact + delete (hybrid)
kafka-configs.sh --alter --entity-type topics --entity-name user-activity \
  --add-config cleanup.policy=compact,delete,retention.ms=604800000
```

```properties
# Compaction configuration (server.properties)
log.cleanup.policy=delete                 # default
log.cleaner.enable=true                   # enable log cleaner threads
log.cleaner.threads=1                     # dedicated cleaner threads
log.cleaner.min.cleanable.ratio=0.5       # compact when dirty > 50% of log
log.cleaner.min.compaction.lag.ms=0       # min time before record can be compacted
log.cleaner.max.compaction.lag.ms=Long.MAX_VALUE  # max time record can stay uncompacted
delete.retention.ms=86400000              # how long to keep tombstones (1 day)
min.compaction.lag.ms=0                   # min age for compaction eligibility
```

---

## How – Compaction Internals

```
Log Cleaner architecture:
  CleanerThread: background thread per log.cleaner.threads
  OffsetMap: in-memory hash map (key → latest offset)
    Size: log.cleaner.dedupe.buffer.size (default 128MB)

Cleaning process:
  1. Select "dirtiest" partition (highest dirty ratio)
  2. Build OffsetMap: scan tail (dirty) portion, map key → latest offset
  3. Copy clean head + filtered dirty portion → new segment
  4. Replace old segments atomically

Log sections:
  Clean head: already compacted (no duplicates)
  Dirty tail: new records since last compaction
```

---

## How – Tiered Storage (Kafka 3.6+)

```
Tiered Storage: offload old log segments to remote storage (S3, GCS, Azure Blob)
  Local tier:  recent data (fast access, limited disk)
  Remote tier: historical data (cheap storage, higher latency)

Benefits:
  - Longer retention without large local disks
  - Independent scaling of storage vs compute
  - Cheaper long-term retention

Architecture:
  Broker: maintain local segments + upload to remote storage
  Consumer: transparent fetch (broker proxies from remote if needed)
  Remote Log Metadata Manager (RLMM): tracks segment locations
```

```properties
# server.properties (Tiered Storage)
remote.log.storage.system.enable=true
remote.log.manager.class.name=org.apache.kafka.server.log.remote.storage.RemoteLogManager
remote.log.storage.manager.class.name=io.confluent.kafka.tieredstorage.s3.S3RemoteStorageManager

# S3 configuration (example: Confluent S3 plugin)
remote.log.storage.manager.class.path=/opt/kafka/plugins/tiered-storage/*
s3.bucket.name=my-kafka-tiered-storage
s3.region=ap-southeast-1

# Per-topic: how long to keep locally
kafka-configs.sh --alter --entity-type topics --entity-name orders \
  --add-config remote.storage.enable=true,local.retention.ms=86400000  # 1 day local, rest remote
```

---

## Why – Kafka's Storage Design Choices

```
Why append-only log?
  Sequential writes: ~600MB/s vs ~100MB/s random writes (HDD)
  SSD: sequential still faster + preserves write endurance
  Simplicity: no update-in-place → no fragmentation → no compaction complexity

Why rely on OS page cache?
  Kafka doesn't manage its own cache (unlike most DBs)
  OS page cache: shared between producer writes + consumer reads
  Producer writes → page cache → consumer reads same page cache (zero-copy!)
  JVM heap pressure avoided: data lives in OS memory, not JVM

Why zero-copy?
  Normal: disk → kernel buffer → user space → kernel buffer → socket
  Zero-copy (sendfile): disk → kernel buffer → socket (skip user space copy)
  → 60% improvement in throughput for consumer reads
  → Linux sendfile() syscall via Java NIO FileChannel.transferTo()

Why separate index files?
  Offset lookup without scanning entire log
  Sparse index: good balance between memory and lookup speed
  Binary search on sparse index: O(log n) entries, then O(1) scan to record
```

---

## Trade-offs

```
Segment size:
  Small:   faster retention (more precise), more files, more overhead
  Large:   fewer files, slower retention, large single files
  → Default 1GB usually fine; smaller for high-throughput topics

Compaction vs Delete:
  Delete:   simple, predictable size
  Compact:  always retain latest, unbounded size (unless + delete)
  → Compact for entity state; delete for time-series events; hybrid for both

Flush interval:
  Per-message fsync: safest, but 100x slower (disk latency per record)
  OS-managed:        fastest, relies on replication for durability
  → Kafka default: OS-managed (correct: replication is the safety net)

Cleaner buffer (log.cleaner.dedupe.buffer.size):
  Too small: multi-pass compaction → slower
  Too large: OOM risk
  → Monitor cleaner stats: kafka.log.LogCleaner:type=LogCleaner

Tiered storage:
  ✅ Cheap long-term retention (S3 << local disk)
  ❌ Higher fetch latency for historical data
  ❌ Additional operational complexity
  → Good for: log analytics, audit, compliance with long retention
```

---

## Real-world

```bash
# Monitor log compaction
kafka-log-dirs.sh --bootstrap-server localhost:9092 \
  --topic-list user-profiles --describe
# Shows: size, offsetLag, isFuture, isValid per segment

# Check cleaner stats (JMX)
# kafka.log:type=LogCleanerManager,name=max-dirty-percent
# kafka.log:type=LogCleaner,name=cleaner-recopy-percent
# → Alert: cleaner falling behind (dirty ratio consistently high)

# Force compaction (testing/emergency)
# No CLI command; change min.cleanable.dirty.ratio temporarily to trigger faster

# Segment inspection tool
kafka-dump-log.sh --files /data/kafka/orders-0/00000000000000000000.log \
  --print-data-log

# Check offset and timestamp indexes
kafka-dump-log.sh --files /data/kafka/orders-0/00000000000000000000.index \
  --index-sanity-check
kafka-dump-log.sh --files /data/kafka/orders-0/00000000000000000000.timeindex
```

```
Production retention strategy:
  Transactional events (orders, payments):
    retention.ms=604800000 (7 days), cleanup.policy=delete
    Downstream systems should have their own persistence
  
  User state (profiles, settings):
    cleanup.policy=compact
    No size/time delete (always keep latest state)
  
  Application logs:
    retention.ms=86400000 (1 day), cleanup.policy=delete
    Short retention: Elasticsearch/Splunk as long-term store
  
  Audit trail:
    retention.ms=-1 (unlimited) hoặc tiered storage
    Regulatory requirement: 7 years in some industries
  
  Kafka Streams changelog topics:
    cleanup.policy=compact (auto-managed by Kafka Streams)
    retention.ms=Long.MAX_VALUE (Streams sets this automatically)
```

---

## Ghi chú – Chủ đề tiếp theo
> `replication.md`: Leader election, ISR (In-Sync Replicas), acks & min.insync.replicas, unclean leader election, replica lag monitoring, preferred replica election, partition leadership rebalancing

---

*Cập nhật lần cuối: 2026-05-06*
