# MongoDB Replica Set – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Replica Set là gì?

**Replica Set** là nhóm MongoDB instances duy trì cùng một dataset. Cung cấp **redundancy** (fault tolerance) và **high availability** (automatic failover).

```
Replica Set (3 members):
  Primary (1): nhận tất cả writes
  Secondary (2+): replicate từ primary, có thể serve reads
  Arbiter (optional): tham gia election, không lưu data

Primary ──oplog──→ Secondary-1
        ──oplog──→ Secondary-2

Failover:
  Primary down → election → 1 secondary trở thành primary
  Tự động trong ~10-30 seconds
```

---

## Components – Oplog

```javascript
// Oplog (operations log): capped collection trong local database
// Ghi lại tất cả write operations (insert, update, delete)
// Secondary pull operations từ primary's oplog và apply

// Xem oplog
use local;
db.oplog.rs.find().sort({ $natural: -1 }).limit(5);

// Oplog entry structure:
{
  ts: Timestamp(1735689600, 1),  // timestamp + incrementing ordinal
  t: 1,                          // term (election term)
  h: NumberLong("..."),          // unique hash
  v: 2,                          // version
  op: "i",                       // "i"=insert, "u"=update, "d"=delete, "c"=command, "n"=no-op
  ns: "mydb.orders",             // namespace
  ui: UUID("..."),               // collection UUID
  o: { _id: ObjectId("..."), ... }  // operation data
}

// Oplog size
rs.printReplicationInfo();
// configured oplog size: 5120MB
// log length start to end: 6.5 hrs

// Tăng oplog size (chạy trên primary)
db.adminCommand({ replSetResizeOplog: 1, size: 51200 });  // 50GB MB

// Oplog window:
// Nếu secondary bị tách > oplog window → "RECOVERING" state
// Cần initial sync (full resync) → tốn thời gian
// → Oplog đủ lớn để handle maintenance windows + slowdowns
```

---

## How – Replica Set Setup

```javascript
// 1. Khởi động 3 mongod instances với replicaSet option
// mongod.conf:
// replication:
//   replSetName: "rs0"
//   oplogSizeMB: 51200

// 2. Khởi tạo replica set
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo1:27017", priority: 2 },  // higher priority → preferred primary
    { _id: 1, host: "mongo2:27017", priority: 1 },
    { _id: 2, host: "mongo3:27017", priority: 1,
      hidden: false,   // hidden member: không nhận client connections
      votes: 1
    }
  ]
});

// Thêm member
rs.add("mongo4:27017");

// Thêm arbiter (chỉ vote, không data)
rs.addArb("mongo-arbiter:27017");

// Xem status
rs.status();
rs.conf();

// Xem replication lag
rs.printSecondaryReplicationInfo();
// source: mongo2:27017
// syncedTo: ... (X seconds ago = lag)

// Step down primary (maintenance)
rs.stepDown(60);  // 60s timeout: không re-elect trong 60s
```

---

## How – Election Algorithm

```javascript
// Election triggered khi:
// - Primary không send heartbeat trong 10s (electionTimeoutMillis)
// - Primary manually stepped down
// - Replica set initiated

// Election Protocol (Raft-based):
// 1. Secondary detects primary down → starts election timer (random delay: 10-30s)
// 2. Requests votes from other members
// 3. Other members: vote YES if candidate has most up-to-date oplog
// 4. Candidate needs majority of votes → becomes primary
// 5. Updates term number

// Priority: higher priority → preferred as primary
// priority: 0 → không bao giờ là primary (hidden/delayed secondary)

// Vote weight:
// votes: 1 (default) → participates in election
// votes: 0 → không vote (non-voting member, có thể serve reads)
// Maximum 7 voting members per replica set

// Hidden member: không visible trong isMaster, không nhận client reads
// Dùng cho: dedicated analytics, backup
rs.reconf({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo1:27017" },
    { _id: 1, host: "mongo2:27017" },
    { _id: 2, host: "mongo3:27017", hidden: true, priority: 0, votes: 0 }
  ]
});

// Delayed secondary: replication delay (disaster recovery)
// Thấy data từ N hours ago → protection against data corruption
{ _id: 3, host: "mongo-delayed:27017", priority: 0, hidden: true,
  secondaryDelaySecs: 3600 }  // 1 hour delay
```

---

## How – Read Preferences

```javascript
// Read preference: quyết định reads đến đâu

// primary (default): tất cả reads đến primary → strong consistency
// primaryPreferred: primary nếu available, else secondary
// secondary: chỉ secondary (eventual consistency)
// secondaryPreferred: secondary nếu available, else primary
// nearest: member có lowest latency

// Connection string
mongodb://mongo1,mongo2,mongo3/?replicaSet=rs0&readPreference=secondaryPreferred

// Driver level
const client = new MongoClient(uri, {
  readPreference: ReadPreference.SECONDARY_PREFERRED
});

// Collection level
db.collection("reports").find({}).withReadPreference("secondary");

// Với tag sets (route to specific secondary, e.g., analytics node)
// mongod.conf:
// replication:
//   replSetName: rs0
// setParameter:
//   configureFailPoint: { "... }
// Hoặc: rs.reconf() với tags

const analyticsPreference = new ReadPreference("secondary", [{ dc: "analytics" }]);

// Read preference trong transactions: PHẢI là primary
// Multi-document transactions không support non-primary reads
```

---

## How – Write Concerns Production

```javascript
// w: "majority" → wait for majority of voting members to acknowledge
// Ensures: sau khi primary fail, newly elected primary đã có write
// Quan trọng: luôn dùng w:majority cho critical data

// j: true → write flushed to journal trước khi acknowledge
// Ensures: write survives mongod crash (không chỉ memory crash)

// Connection string: w=majority&journal=true
mongodb://mongo1,mongo2,mongo3/mydb?replicaSet=rs0&w=majority&journal=true

// Driver
const collection = db.collection("orders");
await collection.insertOne(doc, {
  writeConcern: { w: "majority", j: true, wtimeout: 5000 }
});

// wtimeout: nếu majority không acknowledge trong 5s → error (không rollback!)
// Phải handle timeout: retry write (idempotent) hoặc read-after-write check

// w: 0 (fire and forget) - chỉ cho non-critical:
await metrics.insertOne(eventDoc, { writeConcern: { w: 0 } });

// Monitoring write concern failures
db.serverStatus().opcounters;
db.getReplicationInfo();
```

---

## How – Replication Lag Monitoring

```javascript
// Replication lag: delay giữa primary write và secondary apply
// Causes: network latency, secondary overloaded, large oplog entries

// Xem lag
rs.printSecondaryReplicationInfo();

// Programmatic check
const status = rs.status();
status.members.forEach(m => {
  if (m.stateStr === "SECONDARY") {
    const lagSeconds = (m.lastHeartbeatMessage ? 0 :
      (new Date() - m.lastHeartbeat) / 1000);
    print(`${m.name}: lag = ${lagSeconds}s`);
  }
});

// Prometheus metrics (với mongodb-exporter):
// mongodb_mongod_replset_member_replication_lag_seconds
// Alert: lag > 60s → warning, lag > 300s → critical

// Causes & fixes:
// Network bandwidth: increase → dedicated replication network
// Secondary CPU/IO bottleneck: upgrade hardware, reduce load
// Large documents: MongoDB applies sequentially, large docs block
// Chunk migrations (sharded): pause chunk balancer during business hours

// Read-your-writes consistency:
// Sau khi write với w:majority, đọc từ secondary có thể thấy stale data
// Solution 1: readPreference=primary (no stale reads)
// Solution 2: afterClusterTime (causal consistency)
const session = client.startSession({ causalConsistency: true });
// All reads trong session guaranteed to see writes from same session
```

---

## Compare – HA Approaches

| | Replica Set | AlwaysOn AG (SQL) | MySQL Group Replication |
|--|------------|------------------|------------------------|
| Failover | Auto (~10-30s) | Auto (~15-30s) | Auto (~5-10s) |
| Setup | Simple | Complex | Complex |
| Max replicas | 50 (7 voting) | 9 (AG) | 9 |
| Read scaling | Secondary reads | Secondary reads | Secondary reads |
| Multi-master | No | No (1 primary per AG) | Yes (MGR) |
| Geo distribution | Yes (priority) | Yes (sync/async) | Limited |
| Monitoring | rs.status() | SSMS/DMVs | sys.gr_member_routing_info |

---

## Trade-offs

```
3 members:
✅ Tolerate 1 failure, still have majority (2/3)
✅ Simple setup

5 members:
✅ Tolerate 2 failures (3/5 = majority)
✅ More read scaling
❌ More complex, more cost

Arbiter (2 data + 1 arbiter):
✅ Cost-effective (arbiter cheap)
❌ Tolerate only 1 data member failure
❌ No read scaling from arbiter
❌ MongoDB official guidance: avoid in sharded clusters

Priority & Votes:
High priority primary: ensures strong secondary becomes primary
Hidden 0-priority: dedicated analytics/reporting without client impact
Delayed secondary: protection against data corruption (rollback window)
```

---

## Real-world – Replica Set Checklist

```
Setup:
□ Minimum 3 members (odd number for elections)
□ Members spread across availability zones/data centers
□ Sufficient oplog size (>= maintenance window + expected lag)
□ Pre-allocated oplog (avoid runtime reallocation)
□ keyFile hoặc x.509 authentication between members
□ Monitor replication lag (alert > 60s)
□ Test failover (rs.stepDown()) in staging

Connection string:
□ All members listed: mongo1,mongo2,mongo3
□ w=majority, journal=true cho critical data
□ connectTimeoutMS, serverSelectionTimeoutMS set
□ retryWrites=true (auto retry idempotent writes on transient network)
□ retryReads=true

mongodb://user:pass@mongo1:27017,mongo2:27017,mongo3:27017/mydb
  ?replicaSet=rs0
  &w=majority
  &journal=true
  &retryWrites=true
  &retryReads=true
  &readPreference=primaryPreferred
  &authSource=admin
  &tls=true
```

---

## Ghi chú – Chủ đề tiếp theo
> `operations/sharding.md`: Sharding architecture, shard keys, balancing, mongos routing, zone sharding

---

*Cập nhật lần cuối: 2026-05-06*
