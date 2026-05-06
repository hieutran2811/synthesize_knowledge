# MongoDB Schema Design Patterns – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Schema Design Patterns là gì?

MongoDB schema design là về việc chọn **cách tổ chức data** trong documents để **tối ưu query patterns**. Không có "one size fits all" – thiết kế phải theo access patterns của application.

```
Nguyên tắc cốt lõi:
  "Data that is accessed together should be stored together"
  → Embed data nếu luôn đọc cùng nhau
  → Reference nếu đọc độc lập hoặc 1-to-many lớn
```

---

## How – Pattern 1: Bucket Pattern

```javascript
// Vấn đề: IoT/time-series có millions of events
// Anti-pattern: 1 document per event → too many small documents

// BAD: 1 document per sensor reading
db.temperature.insertMany([
  { sensorId: "S1", ts: ISODate("2026-01-01T00:00:00"), temp: 25.1 },
  { sensorId: "S1", ts: ISODate("2026-01-01T00:01:00"), temp: 25.3 },
  // ... millions of documents
]);

// GOOD: Bucket pattern - nhóm N events vào 1 document
db.temperature.insertOne({
  sensorId: "S1",
  bucket: ISODate("2026-01-01T00:00:00"),  // bucket start time
  count: 60,                                // 60 readings per bucket
  sumTemp: 1512.6,
  minTemp: 24.8,
  maxTemp: 25.9,
  readings: [
    { ts: ISODate("2026-01-01T00:00:00"), temp: 25.1 },
    { ts: ISODate("2026-01-01T00:01:00"), temp: 25.3 },
    // ... 60 readings
  ]
});

// Insert/update pattern: increment counter, push to array
db.temperature.updateOne(
  {
    sensorId: "S1",
    bucket: ISODate("2026-01-01T00:00:00"),
    count: { $lt: 60 }   // not full yet
  },
  {
    $push: { readings: { ts: new Date(), temp: 25.5 } },
    $inc: { count: 1, sumTemp: 25.5 },
    $min: { minTemp: 25.5 },
    $max: { maxTemp: 25.5 }
  },
  { upsert: true }
);

// Benefits:
// - Ít documents → nhỏ hơn index, cache hit tốt hơn
// - Pre-aggregated fields (sum, min, max) → analytics nhanh
// - Working set smaller
```

---

## How – Pattern 2: Outlier Pattern

```javascript
// Vấn đề: hầu hết documents nhỏ, nhưng 1 số "outliers" rất lớn
// Ví dụ: blog post comments (99% có < 100 comments, 1% có > 10,000)

// Tất cả comments embedded → outliers vượt 16MB limit
// Tất cả references → N+1 query cho phần lớn posts (chậm)

// SOLUTION: Outlier Pattern
// Blog post document:
{
  _id: postId,
  title: "MongoDB Tips",
  content: "...",
  comments: [              // embed first N comments (most common case)
    { author: "A", text: "Great!" },
    // ... up to 100 comments
  ],
  commentCount: 15423,
  hasExtraComments: true   // flag khi overflow
}

// Extra comments trong separate collection
db.extraComments.insertOne({
  postId: postId,
  comments: [/* overflow comments */],
  page: 2
});

// Query: first page → no extra lookup needed (fast path)
// Query: full comments → additional lookup (rare, outlier path)
```

---

## How – Pattern 3: Computed Pattern

```javascript
// Vấn đề: expensive aggregation chạy lại nhiều lần
// Ví dụ: movie rating tính trung bình từ millions of reviews

// Anti-pattern: compute mỗi lần query
db.reviews.aggregate([
  { $match: { movieId: movieId } },
  { $group: { _id: null, avgRating: { $avg: "$rating" }, count: { $sum: 1 } } }
]);
// → scan millions of documents mỗi query

// GOOD: Computed pattern - store computed values trong parent document
// movies collection:
{
  _id: movieId,
  title: "The Matrix",
  rating: 4.7,              // pre-computed average
  ratingCount: 1234567,     // pre-computed count
  lastRatingUpdate: ISODate("2026-01-15")
}

// Cập nhật computed values khi có review mới
db.movies.updateOne(
  { _id: movieId },
  {
    $set: {
      rating: newAvgRating,     // tính ở application layer
      lastRatingUpdate: new Date()
    },
    $inc: { ratingCount: 1 }
  }
);

// Hoặc: dùng aggregation pipeline update (MongoDB 4.2+) để tính inline
db.movies.updateOne(
  { _id: movieId },
  [{
    $set: {
      rating: {
        $divide: [
          { $add: ["$ratingSum", newRating] },
          { $add: ["$ratingCount", 1] }
        ]
      },
      ratingSum: { $add: ["$ratingSum", newRating] },
      ratingCount: { $add: ["$ratingCount", 1] }
    }
  }]
);

// Periodic batch recompute (để ensure accuracy)
db.reviews.aggregate([
  { $group: { _id: "$movieId", avgRating: { $avg: "$rating" }, count: { $sum: 1 } } },
  { $merge: { into: "movies", on: "_id", whenMatched: "merge" } }
]);
```

---

## How – Pattern 4: Polymorphic Pattern

```javascript
// Vấn đề: nhiều entity types với shared + specific fields
// Ví dụ: CMS với Article, Video, Podcast

// RDBMS: cần multiple tables hoặc single table inheritance
// MongoDB: 1 collection, discriminator field

db.content.insertMany([
  {
    _id: ObjectId("..."),
    type: "article",
    title: "MongoDB Tips",
    body: "...",
    authorId: ObjectId("..."),
    readingTime: 5,         // article-specific
    wordCount: 1000
  },
  {
    _id: ObjectId("..."),
    type: "video",
    title: "MongoDB Tutorial",
    videoUrl: "https://...",
    authorId: ObjectId("..."),
    duration: 1200,         // video-specific
    resolution: "1080p"
  },
  {
    _id: ObjectId("..."),
    type: "podcast",
    title: "MongoDB Podcast",
    audioUrl: "https://...",
    authorId: ObjectId("..."),
    duration: 3600,
    transcript: "..."       // podcast-specific
  }
]);

// Query all content regardless of type
db.content.find({ authorId: authorId }).sort({ createdAt: -1 });

// Query specific type
db.content.find({ type: "video", duration: { $gt: 600 } });

// Index on type + shared fields
db.content.createIndex({ type: 1, authorId: 1, createdAt: -1 });
```

---

## How – Pattern 5: Tree Pattern (Hierarchy)

```javascript
// Hierarchy: categories, org charts, file systems

// Option A: Parent Reference (simple, unlimited depth)
db.categories.insertMany([
  { _id: 1, name: "Electronics", parent: null },
  { _id: 2, name: "Computers", parent: 1 },
  { _id: 3, name: "Laptops", parent: 2 },
  { _id: 4, name: "Gaming Laptops", parent: 3 }
]);

// Get direct children
db.categories.find({ parent: 1 });

// Get all ancestors (recursive → $graphLookup)
db.categories.aggregate([
  { $match: { _id: 4 } },
  { $graphLookup: {
    from: "categories",
    startWith: "$parent",
    connectFromField: "parent",
    connectToField: "_id",
    as: "ancestors",
    maxDepth: 10
  }}
]);

// Option B: Materialized Path (fast subtree queries)
db.categories.insertMany([
  { _id: 1, name: "Electronics", path: ",1," },
  { _id: 2, name: "Computers",   path: ",1,2," },
  { _id: 3, name: "Laptops",     path: ",1,2,3," },
  { _id: 4, name: "Gaming",      path: ",1,2,3,4," }
]);
db.categories.createIndex({ path: 1 });

// Get all descendants of Electronics (id=1)
db.categories.find({ path: /,1,/ });  // regex match

// Option C: Nested Sets (fast reads, slow writes)
// Option D: Array of Ancestors (fast, denormalized)
{ _id: 4, name: "Gaming Laptops", ancestors: [1, 2, 3] }
db.categories.find({ ancestors: 1 });  // all descendants of Electronics
```

---

## How – Pattern 6: Extended Reference Pattern

```javascript
// Vấn đề: reference đến another document, luôn cần vài fields từ document đó
// Tránh $lookup khi chỉ cần 1-2 fields

// orders collection với extended customer reference
{
  _id: ObjectId("..."),
  customerId: ObjectId("..."),          // full reference
  customer: {                           // extended reference: subset of customer fields
    name: "Nguyen Van A",
    email: "nva@example.com"
    // chỉ fields cần cho order processing/display
  },
  items: [...],
  total: 1500000
}

// Không cần $lookup chỉ để hiển thị tên customer!
// Nhưng: khi customer đổi tên → orders cũ vẫn giữ tên cũ
// → OK cho historical data (orders should record info at time of order)
// → Update: background job sync nếu cần consistency
```

---

## How – Pattern 7: Subset Pattern

```javascript
// Vấn đề: working set > RAM → cache eviction → slow
// Document lớn nhưng chỉ cần 1 phần trong hot path

// E-commerce: product với 1000 reviews
// 99% requests chỉ cần top 10 reviews

// products collection (frequently accessed):
{
  _id: productId,
  name: "Laptop",
  price: 25000000,
  topReviews: [   // subset: top 10 reviews
    { author: "A", rating: 5, text: "...", helpful: 234 },
    // ...
  ],
  reviewCount: 1247,
  avgRating: 4.6
}

// reviews collection (less frequently accessed):
{
  _id: reviewId,
  productId: productId,
  author: "...", rating: 5, text: "..."
}

// Hot path: query products (small, fast)
// All reviews: separate query to reviews collection (when needed)
```

---

## How – Embedding vs Referencing Decision Matrix

```
                    EMBED                    REFERENCE
Data size          Small-medium              Large or unbounded
Relationship       One-to-one, one-to-few    One-to-many, many-to-many
Update frequency   Rarely changes together   Changes independently
Query pattern      Always accessed together  Sometimes accessed separately
Consistency        Strong (single doc)       Eventual (application manages)
Max doc size       < 16MB after growth       No limit
Duplication        Acceptable               Avoid if many copies

Examples:
  User + addresses:       EMBED   (address always loaded with user)
  Blog post + comments:   EMBED few, REFERENCE when many
  Order + customer:       Extended REFERENCE (historical data)
  Products + categories:  REFERENCE (M2M, categories managed separately)
  User + permissions:     EMBED (queried together, small set)
```

---

## Compare – Schema Design Approaches

| Approach | Query Perf | Write Perf | Storage | Consistency |
|----------|-----------|-----------|---------|-------------|
| Full embed | Best (1 read) | OK | More (duplication) | Strong |
| Full reference | N queries | OK | Less | Eventual |
| Hybrid (partial embed) | Good | Good | Medium | Mixed |
| Computed fields | Best (pre-computed) | Slower | More | Near-real-time |
| Bucket | Good (few large docs) | OK | Less | Strong per bucket |

---

## Trade-offs

```
Embedding:
✅ Atomic writes on single document
✅ No joins (better read performance)
❌ Document grows → potential 16MB limit
❌ If embedded data changes → update all parents (duplication)
❌ Cannot easily query embedded sub-documents independently

Referencing:
✅ Independent updates
✅ No duplication
✅ Unlimited cardinality
❌ $lookup required (slower than embedding)
❌ No cross-collection atomic operations without transactions

Rule: Start with embedding, refactor to reference when:
  - Document approaching 16MB
  - Array is unbounded (grow indefinitely)
  - Sub-document queried independently often
  - Sub-document changes frequently (high write amplification)
```

---

## Real-world – Schema Review Checklist

```
□ Identify all query patterns first (write down every query app makes)
□ Check working set estimate (data accessed in typical window)
□ Avoid unbounded arrays → use Bucket or reference
□ Identify hot vs cold paths → Subset pattern for hot
□ Consider write:read ratio → high write → lighter embedding
□ Test with production-like data volume (not 100 docs)
□ Run explain("executionStats") on all critical queries
□ Check document size: db.stats() và db.collection.stats()
□ Ensure indexes cover query patterns
□ Plan for schema evolution (schemaVersion field)
```

---

## Ghi chú – Chủ đề tiếp theo
> `operations/replication.md`: Replica Set architecture, election algorithm, oplog, read preferences, write concerns production

---

*Cập nhật lần cuối: 2026-05-06*
