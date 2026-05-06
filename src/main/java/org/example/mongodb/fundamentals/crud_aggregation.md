# MongoDB CRUD & Aggregation Pipeline – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – CRUD & Aggregation Pipeline là gì?

MongoDB cung cấp 2 query interfaces:
- **CRUD**: insert/find/update/delete documents đơn giản
- **Aggregation Pipeline**: xử lý data phức tạp theo pipeline stages (tương tự SQL SELECT với GROUP BY, JOIN, HAVING...)

---

## How – Create (Insert)

```javascript
// insertOne
db.orders.insertOne({
  customerId: ObjectId("65a1b2c3d4e5f67890123456"),
  items: [
    { productId: ObjectId("..."), name: "Laptop", qty: 1, price: 25000000 }
  ],
  total: 25000000,
  status: "pending",
  createdAt: new Date()
});

// insertMany (bulk insert)
db.products.insertMany([
  { name: "Laptop",  price: 25000000, category: "electronics", stock: 50 },
  { name: "Phone",   price: 12000000, category: "electronics", stock: 100 },
  { name: "T-Shirt", price: 150000,   category: "clothing",    stock: 200 }
], {
  ordered: false  // tiếp tục insert nếu 1 document fail (default: true = dừng khi fail)
});

// Bulk Write (mix operations)
db.products.bulkWrite([
  { insertOne: { document: { name: "Mouse", price: 500000 } } },
  { updateOne: { filter: { name: "Laptop" }, update: { $inc: { stock: -1 } } } },
  { deleteOne: { filter: { name: "OldProduct" } } }
], { ordered: true });
```

---

## How – Read (Find)

```javascript
// find: trả về cursor
db.orders.find(
  { status: "pending", total: { $gt: 1000000 } },  // filter
  { customerId: 1, total: 1, status: 1, _id: 0 }    // projection: 1=include, 0=exclude
);

// findOne: trả về document đầu tiên
db.orders.findOne({ _id: ObjectId("...") });

// Cursor methods
db.orders
  .find({ status: "pending" })
  .sort({ createdAt: -1 })   // -1 = DESC, 1 = ASC
  .skip(20)                  // pagination offset
  .limit(10)                 // page size
  .hint({ status: 1, createdAt: -1 })  // force index
  .comment("get pending orders page 3");

// Query Operators
db.products.find({
  price:    { $gte: 100000, $lte: 5000000 },  // range
  category: { $in: ["electronics", "gadgets"] },  // in list
  name:     { $regex: /laptop/i },             // regex
  deleted:  { $exists: false },                // field not exists
  tags:     { $elemMatch: { $eq: "sale" } },   // array element match
  "address.city": "Ho Chi Minh"                // nested field (dot notation)
});

// Logical operators
db.products.find({
  $or: [
    { price: { $lt: 200000 } },
    { category: "clearance" }
  ]
});

db.products.find({
  $and: [
    { price: { $gt: 0 } },
    { stock: { $gt: 0 } }
  ]
});

db.products.find({ price: { $not: { $gt: 1000000 } } });

// $expr: dùng aggregation expressions trong find
db.orders.find({
  $expr: { $gt: ["$total", { $multiply: ["$discount", 10] }] }
});

// Distinct values
db.products.distinct("category", { price: { $lt: 1000000 } });

// Count
db.orders.countDocuments({ status: "pending" });
db.orders.estimatedDocumentCount();  // nhanh hơn (dùng metadata)
```

---

## How – Update

```javascript
// updateOne / updateMany / replaceOne
db.orders.updateOne(
  { _id: ObjectId("...") },    // filter
  {
    $set:   { status: "confirmed", confirmedAt: new Date() },
    $unset: { tempField: "" },              // xóa field
    $inc:   { retryCount: 1 },              // tăng số
    $push:  { history: { event: "confirmed", at: new Date() } },  // append to array
    $pull:  { tags: "urgent" },             // xóa khỏi array
    $addToSet: { labels: "processed" }      // thêm vào array nếu chưa có (dedup)
  }
);

// upsert: insert nếu không tìm thấy
db.products.updateOne(
  { sku: "LAPTOP-001" },
  {
    $set: { price: 25000000, updatedAt: new Date() },
    $setOnInsert: { createdAt: new Date(), stock: 0 }  // chỉ set khi INSERT
  },
  { upsert: true }
);

// findOneAndUpdate: update + trả về document
const updated = db.orders.findOneAndUpdate(
  { status: "pending", assignedTo: { $exists: false } },
  { $set: { assignedTo: "worker-1", status: "processing" } },
  {
    returnDocument: "after",   // "before" hoặc "after"
    sort: { createdAt: 1 },    // lấy oldest pending order
    upsert: false
  }
);

// Array update operators
db.orders.updateOne(
  { _id: OrderId, "items.productId": productId },
  { $set: { "items.$.qty": 3 } }   // $ = matched element position
);

// Positional all: update all array elements
db.orders.updateMany(
  { "items.status": "pending" },
  { $set: { "items.$[].updatedAt": new Date() } }  // $[] = all elements
);

// Filtered positional: update specific array elements
db.orders.updateMany(
  {},
  { $set: { "items.$[item].discount": 0.1 } },
  { arrayFilters: [{ "item.price": { $gt: 1000000 } }] }
);
```

---

## How – Delete

```javascript
// deleteOne / deleteMany
db.sessions.deleteOne({ _id: sessionId });
db.sessions.deleteMany({ expiresAt: { $lt: new Date() } });

// findOneAndDelete: delete + trả về document đã xóa
const deleted = db.jobs.findOneAndDelete(
  { status: "failed", retries: { $gte: 3 } },
  { sort: { createdAt: 1 } }
);

// Soft delete pattern
db.users.updateOne(
  { _id: userId },
  { $set: { deletedAt: new Date(), deletedBy: adminId } }
);
// Query exclude soft-deleted:
db.users.find({ deletedAt: { $exists: false } });
```

---

## How – Aggregation Pipeline

Aggregation Pipeline là chuỗi **stages**, mỗi stage transform data và pass cho stage tiếp theo.

```javascript
// Cú pháp: db.collection.aggregate([stage1, stage2, ...])

// Ví dụ: doanh thu theo tháng, top 5 sản phẩm
db.orders.aggregate([
  // Stage 1: filter
  { $match: {
    status: "delivered",
    createdAt: { $gte: ISODate("2026-01-01"), $lt: ISODate("2027-01-01") }
  }},

  // Stage 2: unwind array (1 doc per item)
  { $unwind: "$items" },

  // Stage 3: group + aggregate
  { $group: {
    _id: {
      month:     { $month: "$createdAt" },
      productId: "$items.productId",
      name:      "$items.name"
    },
    totalRevenue: { $sum: { $multiply: ["$items.price", "$items.qty"] } },
    totalQty:     { $sum: "$items.qty" },
    orderCount:   { $sum: 1 }
  }},

  // Stage 4: sort
  { $sort: { totalRevenue: -1 } },

  // Stage 5: group again - top 5 per month
  { $group: {
    _id: "$_id.month",
    topProducts: { $push: { name: "$_id.name", revenue: "$totalRevenue" } }
  }},

  // Stage 6: project (reshape output)
  { $project: {
    month: "$_id",
    topProducts: { $slice: ["$topProducts", 5] },  // first 5
    _id: 0
  }},

  // Stage 7: sort output
  { $sort: { month: 1 } }
]);
```

### Quan Trọng: Pipeline Stages

```javascript
// $match: filter (đặt sớm nhất có thể để reduce data)
{ $match: { status: "active", age: { $gte: 18 } } }

// $project: reshape (include/exclude/transform fields)
{ $project: {
  fullName: { $concat: ["$firstName", " ", "$lastName"] },
  ageGroup: { $switch: {
    branches: [
      { case: { $lt: ["$age", 18] }, then: "minor" },
      { case: { $lt: ["$age", 65] }, then: "adult" }
    ],
    default: "senior"
  }},
  _id: 0
}}

// $group: aggregate
{ $group: {
  _id: "$category",
  count:   { $sum: 1 },
  total:   { $sum: "$price" },
  avg:     { $avg: "$price" },
  min:     { $min: "$price" },
  max:     { $max: "$price" },
  items:   { $push: "$name" },       // collect all values
  unique:  { $addToSet: "$brand" }   // unique values
}}

// $unwind: flatten array
{ $unwind: { path: "$tags", preserveNullAndEmpty: true } }

// $lookup: LEFT JOIN
{ $lookup: {
  from: "customers",
  localField: "customerId",
  foreignField: "_id",
  as: "customer",
  // pipeline lookup (complex join, SQL Server 2019+)
  pipeline: [
    { $match: { $expr: { $eq: ["$$localVar", "$_id"] } } },
    { $project: { name: 1, email: 1 } }
  ],
  let: { localVar: "$customerId" }
}}

// $addFields / $set: add/update fields (non-destructive vs $project)
{ $addFields: {
  totalWithTax: { $multiply: ["$total", 1.1] },
  isExpensive: { $gt: ["$price", 1000000] }
}}

// $bucket: phân loại vào buckets (histogram)
{ $bucket: {
  groupBy: "$price",
  boundaries: [0, 100000, 500000, 1000000, 5000000, Infinity],
  default: "Other",
  output: { count: { $sum: 1 }, avgPrice: { $avg: "$price" } }
}}

// $facet: multiple pipelines in parallel (faceted search)
{ $facet: {
  byCategory: [
    { $group: { _id: "$category", count: { $sum: 1 } } }
  ],
  byPriceRange: [
    { $bucket: { groupBy: "$price", boundaries: [0,100000,500000,1000000] } }
  ],
  total: [
    { $count: "count" }
  ]
}}

// $sortByCount: shorthand for $group + $sort by count
{ $sortByCount: "$category" }

// $limit, $skip (pagination)
{ $skip: 20 }, { $limit: 10 }

// $count
{ $count: "totalDocuments" }

// $out: write results to new collection
{ $out: "monthly_revenue_2026" }

// $merge: merge results into existing collection
{ $merge: {
  into: "summary",
  on: "_id",
  whenMatched: "merge",
  whenNotMatched: "insert"
}}

// Window functions (MongoDB 5.0+)
{ $setWindowFields: {
  partitionBy: "$customerId",
  sortBy: { orderDate: 1 },
  output: {
    runningTotal: {
      $sum: "$amount",
      window: { documents: ["unbounded", "current"] }
    },
    rank: {
      $rank: {}
    }
  }
}}
```

---

## How – Aggregation Expressions

```javascript
// Arithmetic
{ $add: ["$price", "$tax"] }
{ $subtract: ["$total", "$discount"] }
{ $multiply: ["$qty", "$price"] }
{ $divide: ["$revenue", "$orderCount"] }
{ $mod: ["$quantity", 10] }
{ $round: ["$price", 2] }

// String
{ $concat: ["$firstName", " ", "$lastName"] }
{ $toUpper: "$city" }
{ $substr: ["$sku", 0, 3] }
{ $split: ["$fullAddress", ","] }
{ $trim: { input: "$name" } }

// Array
{ $size: "$tags" }
{ $slice: ["$items", 0, 5] }
{ $arrayElemAt: ["$items", 0] }  // first element
{ $indexOfArray: ["$tags", "vip"] }
{ $filter: { input: "$items", cond: { $gt: ["$$this.price", 100000] } } }
{ $map: { input: "$items", as: "item", in: { $multiply: ["$$item.price", "$$item.qty"] } } }
{ $reduce: { input: "$amounts", initialValue: 0, in: { $add: ["$$value", "$$this"] } } }

// Date
{ $year: "$createdAt" }
{ $month: "$createdAt" }
{ $dayOfWeek: "$createdAt" }
{ $dateToString: { format: "%Y-%m-%d", date: "$createdAt" } }
{ $dateDiff: { startDate: "$startDate", endDate: "$$NOW", unit: "day" } }

// Conditional
{ $cond: { if: { $gt: ["$score", 80] }, then: "pass", else: "fail" } }
{ $ifNull: ["$discount", 0] }   // default if null/missing
{ $switch: { branches: [...], default: "other" } }

// Type conversion
{ $toInt: "$strNumber" }
{ $toString: "$number" }
{ $toDate: "$timestamp" }
{ $toDecimal: "$price" }
```

---

## How – explain() & Performance

```javascript
// Xem execution plan
db.orders.find({ status: "pending" }).explain("executionStats");

// Output quan trọng:
// executionStats.nReturned:      số docs trả về
// executionStats.totalDocsExamined: số docs scan
// executionStats.totalKeysExamined: số index keys scan
// executionStats.executionTimeMillis

// nReturned << totalDocsExamined → cần index
// COLLSCAN → full collection scan (không có index)
// IXSCAN   → index scan (tốt)
// FETCH    → fetch documents từ index

db.orders.aggregate([...]).explain("executionStats");

// allowDiskUse: cho phép spill to disk khi data > 100MB
db.orders.aggregate([...], { allowDiskUse: true });
```

---

## Compare – Aggregation Pipeline vs Map-Reduce vs SQL

| | Aggregation Pipeline | Map-Reduce | SQL |
|--|---------------------|-----------|-----|
| Syntax | Stage-based | JavaScript | Set-based |
| Performance | Fast (C++) | Slow (JS engine) | Fast |
| Flexibility | High | Very High | High |
| Streaming | Yes | No | Depends |
| Out-of-memory | allowDiskUse | Slower | TempDB |
| Learning curve | Medium | Hard | Low (familiar) |

Map-Reduce deprecated trong MongoDB 5.0, dùng Aggregation Pipeline thay thế.

---

## Trade-offs

```
Aggregation Pipeline:
✅ Rất mạnh, gần bằng SQL cho analytics
✅ Streaming: mỗi stage xử lý theo batch → memory efficient
✅ Index optimization: $match + $sort ở đầu dùng được index
❌ Verbose hơn SQL cho queries phức tạp
❌ $lookup (JOIN) không efficient như RDBMS JOIN
❌ Transactions qua nhiều collections tốn kém hơn RDBMS

Tip: push $match sớm nhất có thể, $sort trước $group nếu có index
```

---

## Ghi chú – Chủ đề tiếp theo
> `indexing.md`: Index types (single, compound, multikey, text, geospatial, wildcard), index strategies, ESR rule

---

*Cập nhật lần cuối: 2026-05-06*
