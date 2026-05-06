# MongoDB Indexing – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – MongoDB Index là gì?

**Index** trong MongoDB là cấu trúc B-tree lưu trữ một phần nhỏ data theo thứ tự, giúp tránh collection scan. Mặc định chỉ có `_id` index. Mọi query không dùng được index → COLLSCAN (full collection scan).

---

## How – Index Types

### Single Field Index

```javascript
// Tạo index
db.users.createIndex({ email: 1 });          // ascending
db.users.createIndex({ age: -1 });           // descending (ít quan trọng hơn)

// Với options
db.users.createIndex(
  { email: 1 },
  {
    unique: true,            // unique constraint
    sparse: true,            // chỉ index docs có field này (bỏ qua null/missing)
    background: false,       // deprecated MongoDB 4.2+ (luôn chạy background)
    name: "idx_email_unique",
    expireAfterSeconds: 3600 // TTL index: tự xóa docs sau 3600s
  }
);

// TTL Index: tự xóa documents hết hạn
db.sessions.createIndex(
  { createdAt: 1 },
  { expireAfterSeconds: 86400 }  // xóa sau 24h
);
// MongoDB chạy TTL monitor mỗi 60s → không real-time

// Partial Index: chỉ index subset (tiết kiệm space, nhanh hơn)
db.orders.createIndex(
  { customerId: 1, orderDate: -1 },
  { partialFilterExpression: { status: "active" } }
);
// Chỉ có ích khi query cũng filter { status: "active" }
```

### Compound Index

```javascript
// Compound: nhiều fields trong 1 index
db.orders.createIndex({ customerId: 1, orderDate: -1, status: 1 });

// Index prefix: compound (a, b, c) covers queries on:
//   (a), (a, b), (a, b, c) ← supported
//   (b), (c), (b, c)       ← NOT supported (no index)

// ESR Rule (tương tự SQL Server):
// E = Equality fields first
// S = Sort fields second
// R = Range fields last
// Query: { customerId: 5, status: {$in:["active","pending"]} } sort by orderDate
// Index: { customerId: 1, orderDate: 1, status: 1 }  ← ESR

// Sort direction với compound index:
// Index:  { a: 1, b: -1 }
// Supports: sort({ a: 1, b: -1 }) AND sort({ a: -1, b: 1 })  (reverse is ok)
// NOT:      sort({ a: 1, b: 1 })   ← khác direction
```

### Multikey Index (Array)

```javascript
// MongoDB tự động tạo multikey index khi field là array
db.products.createIndex({ tags: 1 });
// tags: ["electronics", "laptop", "sale"]
// → index entry cho mỗi element trong array

// Query: trả về docs có tags = "electronics"
db.products.find({ tags: "electronics" });

// Multikey compound: chỉ 1 field trong compound có thể là array
db.products.createIndex({ category: 1, tags: 1 });  // OK nếu category không phải array
// KHÔNG thể: 2 array fields trong 1 compound index

// Embedded document indexing
db.users.createIndex({ "address.city": 1 });
db.users.find({ "address.city": "Ho Chi Minh" });
```

### Text Index (Full-text Search)

```javascript
// Text index: tokenize, stem, stopwords removal
db.articles.createIndex({
  title: "text",
  content: "text",
  tags: "text"
}, {
  weights: { title: 10, content: 5, tags: 1 },  // relevance scoring
  default_language: "english",
  name: "article_text_idx"
});

// Chỉ được có 1 text index per collection

// Query
db.articles.find(
  { $text: { $search: "mongodb performance" } },
  { score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } });

// $search: từ nào cũng match → OR
// "\"mongodb performance\"" → exact phrase
// "mongodb -slow" → exclude "slow"

// Giới hạn: không hỗ trợ nhiều ngôn ngữ trong 1 index
// Thay thế cho production: Elasticsearch / MongoDB Atlas Search
```

### Geospatial Index

```javascript
// 2dsphere: geographic coordinates (lat/long), GeoJSON
db.places.createIndex({ location: "2dsphere" });

// Documents:
db.places.insertOne({
  name: "Saigon Center",
  location: {
    type: "Point",
    coordinates: [106.6981, 10.7769]  // [longitude, latitude]
  }
});

// Query: find places within 1km
db.places.find({
  location: {
    $near: {
      $geometry: { type: "Point", coordinates: [106.6981, 10.7769] },
      $maxDistance: 1000  // meters
    }
  }
});

// Query: find places within polygon
db.places.find({
  location: {
    $geoWithin: {
      $geometry: {
        type: "Polygon",
        coordinates: [[
          [106.6, 10.7], [106.7, 10.7],
          [106.7, 10.8], [106.6, 10.8],
          [106.6, 10.7]
        ]]
      }
    }
  }
});
```

### Wildcard Index

```javascript
// Index tất cả fields trong document hoặc subdocument
// Dùng cho dynamic schema (không biết trước field names)

db.products.createIndex({ "$**": 1 });  // all fields

// Specific subdocument
db.products.createIndex({ "attributes.$**": 1 });

// Attributes có thể là: { color: "red", size: "L", material: "cotton" }
// Wildcard index mỗi key trong attributes

// Giới hạn: không cover compound queries (mỗi field riêng biệt)
```

### Hashed Index

```javascript
// Hashed: dùng cho sharding (hash-based shard key)
db.users.createIndex({ userId: "hashed" });

// Phân phối đều data qua shards
// Không support range queries, chỉ equality
```

---

## How – Index Management

```javascript
// Xem indexes
db.orders.getIndexes();
db.orders.indexStats().forEach(stat => {
  print(`${stat.name}: seeks=${stat.accesses.ops}, ` +
        `since=${stat.accesses.since}`);
});

// Xóa index
db.orders.dropIndex("idx_customer_date");
db.orders.dropIndex({ customerId: 1, orderDate: -1 });

// Rebuild (MongoDB 4.4+ implicit, explicit rebuild ít cần)
db.orders.reIndex();  // rebuild all indexes (locks collection)

// Hide index (MongoDB 4.4+): test trước khi xóa
db.orders.hideIndex("idx_old");   // hide: optimizer không dùng
// Test performance → nếu không thay đổi → safe to drop
db.orders.dropIndex("idx_old");

// createIndex với background (deprecated 4.2+):
// MongoDB 4.2+ dùng concurrent background build tự động
// Không block reads/writes trong quá trình build

// Xem progress khi build index
db.currentOp({ "command.createIndexes": { $exists: true } });
```

---

## How – explain() & Query Analysis

```javascript
// Xem execution plan
db.orders.find({ status: "pending" }).explain("executionStats");

// Kết quả quan trọng:
{
  "queryPlanner": {
    "winningPlan": {
      "stage": "FETCH",         // FETCH = fetch doc từ index
      "inputStage": {
        "stage": "IXSCAN",      // Index Scan (tốt)
        "indexName": "idx_status",
        "isMultiKey": false
      }
    },
    "rejectedPlans": []
  },
  "executionStats": {
    "executionSuccess": true,
    "nReturned": 150,           // số docs trả về
    "executionTimeMillis": 2,
    "totalKeysExamined": 150,   // index keys scanned
    "totalDocsExamined": 150    // docs fetched
  }
}

// BAD: COLLSCAN
{ "stage": "COLLSCAN", "nReturned": 150, "totalDocsExamined": 100000 }
// totalDocsExamined >> nReturned → cần index

// Stages:
// COLLSCAN: full collection scan (cần index)
// IXSCAN:   index scan (tốt)
// FETCH:    fetch doc từ disk (sau IXSCAN)
// SORT:     in-memory sort (cần index nếu chậm)
// LIMIT:    limit stage
// PROJECTION: project fields

// Force index
db.orders.find({ status: "pending" }).hint({ status: 1 });
db.orders.find({ status: "pending" }).hint("idx_status");

// Disable all indexes (để test COLLSCAN performance)
db.orders.find({ status: "pending" }).hint({ $natural: 1 });

// Aggregation explain
db.orders.aggregate([...]).explain("executionStats");
```

---

## How – Covered Query

```javascript
// Covered query: tất cả fields cần thiết có trong index → không cần fetch document

// Index: { status: 1, customerId: 1, orderDate: -1 }
// Query:
db.orders.find(
  { status: "active" },                          // filter từ index
  { customerId: 1, orderDate: 1, _id: 0 }       // project chỉ indexed fields
);
// Nếu _id: 0 (exclude _id) → covered (không fetch document)
// Nếu _id không exclude → FETCH stage (vì _id không trong index)

// explain() covered query:
{ "stage": "IXSCAN" }  // không có FETCH stage → covered
```

---

## How – Index Intersection

```javascript
// MongoDB có thể combine 2 single-field indexes
// (ít hơn SQL Server, compound index vẫn preferred)

// Index A: { status: 1 }
// Index B: { customerId: 1 }
// Query: { status: "active", customerId: 5 }
// → MongoDB có thể dùng cả 2 (AND_HASH stage)

// Nhưng: 1 compound index { status: 1, customerId: 1 } vẫn tốt hơn intersection
// → Prefer compound over multiple single-field

// Khi index intersection có ích:
// Queries có patterns khác nhau → khó tạo compound phù hợp tất cả
```

---

## Compare – MongoDB vs SQL Server Indexing

| Feature | MongoDB | SQL Server |
|---------|---------|-----------|
| Clustered | No concept (always _id B-tree) | Yes (1 per table) |
| Non-clustered | Index (separate B-tree) | Non-clustered index |
| Covering | Included fields trong projection | INCLUDE columns |
| Partial | partialFilterExpression | Filtered index |
| Columnstore | Atlas Search (different) | Columnstore index |
| Full-text | Text index / Atlas Search | Full-text catalog |
| Array | Multikey index (automatic) | No native |
| Geospatial | 2dsphere, 2d | Spatial index |
| Wildcard | Yes | No (computed columns workaround) |

---

## Trade-offs

```
Index nhiều:
✅ Queries nhanh
❌ Write overhead (maintain B-tree mỗi insert/update)
❌ Storage tăng
❌ Replica set: secondary phải sync index changes

Compound vs Multiple Single:
✅ Compound: 1 index lookup, prefix support, covered queries
❌ Compound: ít flexible (query không match prefix → không dùng được)
→ Analyze query patterns trước khi design indexes

Multikey Index:
❌ Cannot combine 2 array fields in 1 compound index
❌ Index entries = total elements in all arrays → large index
→ Limit array size nếu field là indexed

Text Index:
✅ Basic full-text search built-in
❌ Chỉ 1 per collection, không support regex highlight, facets
→ Production: dùng Atlas Search hoặc Elasticsearch
```

---

## Real-world – Index Monitoring

```javascript
// Index usage stats (từ replica set secondary preferred)
db.orders.aggregate([{ $indexStats: {} }]);
// Output: {name, key, host, accesses: {ops, since}}

// Find unused indexes
db.orders.aggregate([
  { $indexStats: {} },
  { $match: { "accesses.ops": { $lt: 100 } } }
]);

// Slow query log (profile level)
db.setProfilingLevel(1, { slowms: 100 });  // log queries > 100ms
db.system.profile.find({}).sort({ ts: -1 }).limit(10);

// Atlas: Performance Advisor automatically suggests indexes
// Xem query patterns → suggest indexes

// Check index size
db.orders.stats().indexSizes;

// Production checklist:
// □ Run explain("executionStats") cho mọi query production
// □ Check nReturned vs totalDocsExamined ratio (should be close to 1)
// □ Monitor index build progress (blocking operations)
// □ Set read concern / read preference cho indexStats
// □ Test index với representative data volume (không phải test data nhỏ)
```

---

## Ghi chú – Chủ đề tiếp theo
> `transactions.md`: ACID trong MongoDB, multi-document transactions, read/write concerns, causal consistency

---

*Cập nhật lần cuối: 2026-05-06*
