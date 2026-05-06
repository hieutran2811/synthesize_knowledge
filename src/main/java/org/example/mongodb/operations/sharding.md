# MongoDB Sharding – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Sharding là gì?

**Sharding** là kỹ thuật **horizontal scaling** – chia data thành nhiều phần (shards), mỗi shard là 1 replica set. Dùng khi single replica set không đủ capacity (storage, throughput, RAM).

```
Client → mongos (router) → config servers (cluster metadata)
                         ↓ route by shard key
              Shard 1 (RS: rs1) → { customerId: 1..100000 }
              Shard 2 (RS: rs2) → { customerId: 100001..200000 }
              Shard 3 (RS: rs3) → { customerId: 200001..300000 }
```

---

## Components – Sharded Cluster

```
mongos: stateless router, no data
  - Receives client connections
  - Routes queries to appropriate shards
  - Merges results
  - Multiple mongos for HA

Config Servers (3-node replica set):
  - Cluster metadata (shard key ranges → shards)
  - Each mongos caches this config
  - Must be 3-node RS (majority for consistency)

Shards (each is a Replica Set):
  - Stores actual data
  - Shard 1: RS rs0 {mongo1, mongo2, mongo3}
  - Shard 2: RS rs1 {mongo4, mongo5, mongo6}
  - Minimum 2 shards to be useful
```

---

## How – Shard Key

```javascript
// Shard key: field(s) used to distribute data across shards
// MOST IMPORTANT DECISION: affects performance, scalability, manageability

// Enable sharding on database
sh.enableSharding("mydb");

// Shard a collection
sh.shardCollection("mydb.orders", { customerId: 1 });             // ranged sharding
sh.shardCollection("mydb.events", { userId: "hashed" });          // hashed sharding
sh.shardCollection("mydb.timeseries", { region: 1, date: 1 });    // compound shard key

// Shard key rules:
// - Immutable after creation (cannot change without resharding 5.0+)
// - Must exist in every document
// - Must be indexed (unique index = unique shard key)
// - For time-based: include another field to avoid monotonic key problem
```

### Ranged Sharding

```javascript
// Data phân phối theo ranges của shard key
// Shard 1: { customerId: 1 } đến { customerId: 100000 }
// Shard 2: { customerId: 100001 } đến { customerId: 200000 }

// Pros: range queries efficient (stay on 1 shard)
// Cons: monotonically increasing key → hotspot (all writes to last shard)
// Example hotspot: { _id: ObjectId } → always newest shard gets writes

// BAD shard keys (ranged):
// { _id: 1 }       → monotonic ObjectId → hotspot
// { timestamp: 1 } → time-based → hotspot
// { status: 1 }    → low cardinality → few chunks, bad distribution

// GOOD shard keys (ranged):
// { customerId: 1 }              → random enough distribution
// { userId: 1, createdAt: 1 }    → compound, query-friendly
// { category: 1, productId: 1 }  → good if queries filter by category
```

### Hashed Sharding

```javascript
// Hash shard key → uniform distribution
// Pros: even write distribution (no hotspot)
// Cons: range queries go to ALL shards (scatter-gather)

sh.shardCollection("mydb.logs", { userId: "hashed" });

// Best for:
// - High-throughput write workloads
// - No range queries needed
// - Insert-heavy (logs, events, metrics)

// Hashed compound shard key (MongoDB 4.4+):
sh.shardCollection("mydb.orders", { customerId: "hashed", _id: 1 });
// Hash customerId cho distribution + _id for uniqueness
```

### Zone Sharding (Tag-Based)

```javascript
// Route data to specific shards (geo, compliance, tiering)

// Assign shards to zones
sh.addShardToZone("rs0", "US-EAST");
sh.addShardToZone("rs1", "EU-WEST");
sh.addShardToZone("rs2", "APAC");

// Define zone ranges
sh.updateZoneKeyRange(
  "mydb.users",
  { region: "US" },    // min
  { region: "US￿" },  // max (all US-* values)
  "US-EAST"
);

sh.updateZoneKeyRange("mydb.users", { region: "EU" }, { region: "EU￿" }, "EU-WEST");
sh.updateZoneKeyRange("mydb.users", { region: "AP" }, { region: "AP￿" }, "APAC");

// Users với region: "US-..." → stored on US-EAST shard
// Compliance: EU data stays in EU-WEST
```

---

## How – Chunks & Balancing

```javascript
// Chunk: contiguous range of shard key values (default: 128MB)
// balancer: background process di chuyển chunks giữa shards để cân bằng

// Xem chunk distribution
db.getSiblingDB("config").chunks.aggregate([
  { $group: { _id: "$shard", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
]);

// Xem balancer status
sh.getBalancerState();  // true/false
sh.isBalancerRunning();
sh.status();

// Pause balancer (maintenance window)
sh.stopBalancer();   // hoặc sh.setBalancerState(false)

// Resume balancer
sh.startBalancer();

// Check balancer window (business hours only)
use config;
db.settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "23:00", stop: "06:00" } } },
  { upsert: true }
);

// Split chunk manually
sh.splitAt("mydb.orders", { customerId: 50000 });

// Move chunk manually
db.adminCommand({
  moveChunk: "mydb.orders",
  find: { customerId: 50000 },
  to: "rs1"
});

// Pre-split chunks (avoid hotspot on initial load)
// Create empty sharded collection với pre-split chunks
for (let i = 0; i < 100000; i += 10000) {
  sh.splitAt("mydb.orders", { customerId: i });
}
```

---

## How – mongos Routing

```javascript
// mongos route queries dựa trên shard key

// 1. Targeted query (shard key in filter): 1 shard only (fast)
db.orders.find({ customerId: 12345 });   // → goes to 1 shard

// 2. Scatter-gather (no shard key): all shards (slow, avoid!)
db.orders.find({ status: "pending" });   // → all shards → merge
db.orders.find({ amount: { $gt: 1000000 } });  // → all shards

// 3. Aggregation routing
db.orders.aggregate([
  { $match: { customerId: 12345 } },  // targeted if shard key in $match
  { $group: { ... } }
]);

// Avoid scatter-gather:
// - Always include shard key in queries
// - Or use compound shard key that matches common query patterns

// explain() shows shards used
db.orders.find({ customerId: 12345 }).explain();
// "shards": { "rs0": {...} }  → only 1 shard

db.orders.find({ status: "pending" }).explain();
// "shards": { "rs0": {...}, "rs1": {...}, "rs2": {...} }  → all shards

// $lookup cross-shard: each shard fans out lookup to all shards
// → Very expensive for sharded collections
// → Embed data or use same shard key for joined collections
```

---

## How – Resharding (MongoDB 5.0+)

```javascript
// Trước 5.0: không thể đổi shard key → phải dump/reload
// MongoDB 5.0+: online resharding

db.adminCommand({
  reshardCollection: "mydb.orders",
  key: { region: 1, customerId: 1 },   // new shard key
  numInitialChunks: 10,
  collation: { locale: "simple" }
});

// Monitor resharding progress
db.getSiblingDB("admin").currentOp({
  type: "op",
  "command.reshardCollection": { $exists: true }
});

// Resharding process:
// 1. Copy data to new shard key distribution
// 2. Apply ongoing writes to both
// 3. Commit: switch to new distribution
// Duration: depends on data size (hours for large collections)
// Can abort if needed: db.adminCommand({ abortReshardCollection: "mydb.orders" })
```

---

## Compare – When to Shard

```
Indicators to shard:
- Working set > available RAM → cache eviction → slow
- Single replica set at max write throughput
- Storage > practical single server limit (e.g., > 10TB)
- Need geographic distribution

DON'T shard prematurely:
- Replica set handles reads via secondaries
- Vertical scaling (more RAM, faster SSD) often cheaper
- Sharding adds significant operational complexity
- $lookup and transactions across shards are expensive

Rule: Exhaust vertical scaling and replica set options first
```

| Approach | Scale | Complexity | Read Scaling | Write Scaling |
|----------|-------|-----------|-------------|---------------|
| Single Replica Set | Limited | Low | Secondary reads | One primary |
| Sharded Cluster (2 shards) | Medium | High | All shards | All shards |
| Sharded Cluster (N shards) | Unlimited | Very High | N × secondaries | N primaries |

---

## Trade-offs

```
Sharding benefits:
✅ Horizontal scale-out (write throughput)
✅ Unlimited storage
✅ Geographic distribution (zone sharding)

Sharding costs:
❌ Scatter-gather queries: queries without shard key → all shards (slow)
❌ Transactions: multi-shard transactions expensive (network round-trips)
❌ $lookup: expensive cross-shard joins
❌ Operational complexity: more components, more monitoring
❌ Backups more complex (coordinate across shards)
❌ Chunk migrations can impact performance (use balancer window)

Shard key choice is permanent (before 5.0):
→ Bad shard key → permanently bad performance
→ Must analyze query patterns BEFORE sharding
→ Common mistake: shard key too low cardinality (status, boolean)
```

---

## Real-world – Sharding Checklist

```
Planning:
□ Document all query patterns (find, aggregate, update, delete)
□ Identify high-cardinality field for shard key
□ Avoid monotonically increasing keys (use hash or compound)
□ Test shard key with production-like data
□ Plan for balancer windows (off business hours)

Setup:
□ Config server RS: 3 members minimum
□ Each shard: 3-member RS with w:majority
□ Minimum 2 mongos (HA)
□ Use connection string with all mongos hosts
□ Pre-split chunks before bulk load

Monitoring:
□ Chunk distribution balance (sh.status())
□ Jumbo chunks (too large to split/move)
□ Scatter-gather query ratio (minimize)
□ Balancer migrations per hour
□ Shard primary elections
□ Config server health
```

---

## Ghi chú – Chủ đề tiếp theo
> `operations/backup_security.md`: MongoDB backup strategies, RBAC, TLS/encryption at rest, auditing

---

*Cập nhật lần cuối: 2026-05-06*
