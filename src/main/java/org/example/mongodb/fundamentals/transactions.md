# MongoDB Transactions – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Transactions trong MongoDB

MongoDB hỗ trợ **ACID transactions** từ phiên bản:
- **4.0**: Multi-document transactions trên **Replica Set**
- **4.2**: Multi-document transactions trên **Sharded Cluster**
- Single-document operations luôn là atomic (ngay cả khi update nhiều fields)

```
Single-document atomic (luôn atomic, không cần transaction):
  db.orders.updateOne(
    { _id: orderId },
    { $set: { status: "confirmed" }, $push: { history: {...} } }
  )

Multi-document transaction (cần khi update nhiều collections):
  BEGIN → debit account A, credit account B, insert transaction log → COMMIT
```

---

## How – Multi-Document Transactions

```javascript
// Java Driver (Spring Data MongoDB)
// Pattern 1: executeInTransaction callback
mongoTemplate.execute(db -> {
    ClientSession session = db.client().startSession();
    session.startTransaction();
    try {
        // Debit
        db.getCollection("accounts").updateOne(session,
            Filters.eq("_id", fromAccountId),
            Updates.inc("balance", -amount)
        );

        // Credit
        db.getCollection("accounts").updateOne(session,
            Filters.eq("_id", toAccountId),
            Updates.inc("balance", amount)
        );

        // Insert transaction log
        Document txLog = new Document("fromId", fromAccountId)
            .append("toId", toAccountId)
            .append("amount", amount)
            .append("timestamp", new Date());
        db.getCollection("transactions").insertOne(session, txLog);

        session.commitTransaction();
    } catch (Exception e) {
        session.abortTransaction();
        throw e;
    } finally {
        session.close();
    }
    return null;
});
```

```javascript
// mongosh / Node.js Driver
const session = client.startSession();
session.startTransaction({
  readConcern: { level: "snapshot" },
  writeConcern: { w: "majority" },
  readPreference: "primary",
  maxCommitTimeMS: 5000  // timeout cho commit
});

try {
  // Debit account A
  await db.collection("accounts").updateOne(
    { _id: fromAccountId },
    { $inc: { balance: -amount } },
    { session }
  );

  // Validate sufficient balance
  const account = await db.collection("accounts").findOne(
    { _id: fromAccountId },
    { session }
  );
  if (account.balance < 0) {
    throw new Error("Insufficient balance");
  }

  // Credit account B
  await db.collection("accounts").updateOne(
    { _id: toAccountId },
    { $inc: { balance: amount } },
    { session }
  );

  await session.commitTransaction();
  console.log("Transaction committed");

} catch (error) {
  await session.abortTransaction();
  console.error("Transaction aborted:", error);
  throw error;

} finally {
  await session.endSession();
}
```

---

## How – Read & Write Concerns

### Write Concern

```javascript
// Write concern: chỉ định acknowledgment level cho write operations

// w: 0 → fire-and-forget (không acknowledge)
// w: 1 → primary acknowledges (default)
// w: "majority" → majority of replica set acknowledges (strongest)
// w: 2 → 2 members acknowledge

// j: true → WAL (journal) flush trước khi acknowledge
// wtimeout: timeout (ms) cho write concern

db.orders.insertOne(
  { customerId: userId, items: [...] },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
);

// Collection level (thường set khi tạo)
db.createCollection("financial_transactions", {
  writeConcern: { w: "majority", j: true }
});

// Connection string level
mongodb://host:27017/db?w=majority&journal=true&wTimeoutMS=5000

// Tradeoffs:
// w:1, j:false → fastest, data có thể mất khi crash
// w:1, j:true  → slower, crash-safe on primary
// w:majority   → slowest, crash-safe + tolerates primary failure
```

### Read Concern

```javascript
// Read concern: chỉ định consistency level cho read operations

// "local" (default): dữ liệu có thể chưa replicate
// "available": như local nhưng không guarantee causal consistency (sharded cluster)
// "majority": đọc data đã được majority acknowledge (strong consistency)
// "linearizable": strongest, single document only
// "snapshot": snapshot của committed data (dùng trong transactions)

db.orders.find({ status: "active" }).readConcern("majority");

// Trong transaction: luôn dùng "snapshot"
session.startTransaction({
  readConcern: { level: "snapshot" },
  writeConcern: { w: "majority" }
});
```

---

## How – Causal Consistency

```javascript
// Causal consistency: sau khi write, subsequent reads thấy write đó
// (ngay cả khi đọc từ secondary)

// Dùng causally consistent session
const session = client.startSession({ causalConsistency: true });

// Write
await db.collection("settings").updateOne(
  { key: "featureFlag" },
  { $set: { value: true } },
  { session }
);

// Read sau write: đảm bảo thấy update trên
// (MongoDB sẽ đọc từ member đã apply write, hoặc đợi)
const setting = await db.collection("settings")
  .findOne({ key: "featureFlag" }, { session });

console.log(setting.value); // true (guaranteed)

session.endSession();
```

---

## How – Optimistic Concurrency (Thay Transaction)

```javascript
// Với single-document: dùng findOneAndUpdate với version check
// Tránh transaction overhead

// Pattern: version field
const result = await db.collection("products").findOneAndUpdate(
  {
    _id: productId,
    version: currentVersion  // optimistic lock
  },
  {
    $inc: { stock: -qty },
    $inc: { version: 1 }
  },
  { returnDocument: "after" }
);

if (!result) {
  // Version mismatch: concurrent update, retry
  throw new ConcurrentModificationError();
}

// Pattern: compareAndSwap với $where (deprecated) hoặc aggregation pipeline update
// MongoDB 4.2+: dùng aggregation pipeline trong update
db.products.updateOne(
  { _id: productId, stock: { $gte: qty } },  // atomic check + update
  [{ $set: { stock: { $subtract: ["$stock", qty] } } }]
);
// Nếu stock < qty → không update (0 docs matched)
```

---

## How – Transaction Pitfalls

```javascript
// 1. Transaction timeout (default: 60 seconds)
// Phải commit/abort trước khi hết thời gian

// Tăng timeout (operator level)
db.adminCommand({ setParameter: 1, transactionLifetimeLimitSeconds: 120 });

// 2. Không tạo index trong transaction
// DDL operations không allowed trong transactions

// 3. Snapshot read concern: đọc snapshot tại thời điểm first read
// Data thay đổi sau đó không thấy → phù hợp cho atomic read-modify-write

// 4. Write-write conflict: 2 transactions cùng update 1 document
// → 1 transaction fail với WriteConflict error → phải retry

// Retry transaction
async function transferWithRetry(fromId, toId, amount, maxRetries = 3) {
  let attempts = 0;
  while (attempts < maxRetries) {
    const session = client.startSession();
    try {
      session.startTransaction({ writeConcern: { w: "majority" } });
      await performTransfer(session, fromId, toId, amount);
      await session.commitTransaction();
      return; // success
    } catch (err) {
      await session.abortTransaction();
      if (err.errorLabels?.includes("TransientTransactionError") && attempts < maxRetries - 1) {
        attempts++;
        await new Promise(r => setTimeout(r, 100 * attempts)); // backoff
        continue;
      }
      if (err.errorLabels?.includes("UnknownTransactionCommitResult")) {
        // Commit result unknown → check if committed
        // (safe to retry commit)
      }
      throw err;
    } finally {
      session.endSession();
    }
  }
}

// 5. Transaction không support cross-database operations trong sharded cluster
//    (chỉ support single shard hoặc cross-shard MongoDB 4.2+)

// 6. Large transactions: tránh transactions qua nhiều documents/collections
//    MongoDB khuyến nghị < 1000 writes per transaction
```

---

## How – Avoiding Transactions (Better Patterns)

```javascript
// MongoDB transactions có overhead. Các patterns tránh transaction:

// 1. Two-phase commit pattern (application-level)
//    state: "pending" → "committed" → done
db.transfers.insertOne({
  from: fromId, to: toId, amount,
  state: "pending"  // 1. create transfer record
});

// 2. Apply transfer (idempotent, retry-safe)
db.accounts.updateOne(
  { _id: fromId, "pendingDebits.transferId": { $ne: transferId } },
  { $inc: { balance: -amount }, $push: { pendingDebits: { transferId } } }
);

// 3. Mark committed
db.transfers.updateOne(
  { _id: transferId, state: "pending" },
  { $set: { state: "committed" } }
);

// 2. Saga pattern với compensation
//    Service A: commit, emit event
//    Service B: if fail → compensate A

// 3. Event Sourcing
//    Append-only event log, derive state from events
//    No need for transactions if each event is single-document insert
```

---

## Compare – Transaction Support

| | MongoDB 4.0+ | MongoDB 3.x | PostgreSQL | MySQL |
|--|-------------|-------------|-----------|-------|
| Single-doc atomic | Always | Always | Always | Always |
| Multi-doc ACID | Yes (RS) | No | Yes | Yes |
| Multi-shard ACID | 4.2+ | No | With 2PC | With 2PC |
| Isolation | Snapshot | N/A | RC/RR/S | RC/RR/S |
| Deadlock detection | No (write conflict) | N/A | Yes | Yes |
| Performance overhead | High | N/A | Low | Low |

---

## Trade-offs

```
Multi-document transactions:
✅ True ACID guarantee
✅ Đơn giản hóa application logic
❌ 2-3x overhead so với non-transactional ops
❌ Kéo dài document retention trong oplog
❌ Risk: write-write conflict → retry needed
❌ Không scale well khi transaction span nhiều shards

Best practices:
□ Thiết kế schema để minimize need for transactions
□ Dùng embedding để single-document atomic operations
□ Nếu phải dùng transaction: keep short, small (<1000 docs)
□ Always implement retry logic (TransientTransactionError)
□ Monitor: transaction duration, abort rate
□ Tránh user interaction trong transaction
```

---

## Real-world – Transaction Monitoring

```javascript
// Xem active transactions
db.adminCommand({ currentOp: true, active: true, "transaction.state": { $exists: true } });

// Atlas: transaction metrics dashboard
// db.serverStatus().transactions

db.adminCommand({ serverStatus: 1 }).transactions;
// currentActive: số transactions đang active
// totalCommitted: total committed
// totalAborted: total aborted
// totalContactedParticipants: cho sharded transactions

// Alert khi abort rate cao (> 10%)
// → có thể do write conflicts, timeout, or application bugs
```

---

## Ghi chú – Chủ đề tiếp theo
> `performance/schema_design.md`: Schema design patterns (Bucket, Outlier, Computed, Polymorphic, Tree), embedding vs referencing tradeoffs sâu hơn

---

*Cập nhật lần cuối: 2026-05-06*
