# MongoDB Data Model & BSON – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – MongoDB Data Model là gì?

MongoDB lưu data dưới dạng **documents** (BSON), tổ chức trong **collections**, không có fixed schema. Đây là điểm khác biệt căn bản so với RDBMS.

```
RDBMS:    Database → Tables → Rows → Columns (fixed schema)
MongoDB:  Database → Collections → Documents (flexible schema)

Document example:
{
  "_id": ObjectId("65a1b2c3d4e5f6789012345"),
  "name": "Nguyen Van A",
  "email": "nva@example.com",
  "age": 30,
  "address": {                    // embedded document
    "street": "123 Le Loi",
    "city": "Ho Chi Minh",
    "zipCode": "70000"
  },
  "orders": [                     // array of embedded documents
    {"orderId": "ORD-001", "amount": 150000, "status": "delivered"},
    {"orderId": "ORD-002", "amount": 75000,  "status": "pending"}
  ],
  "tags": ["vip", "active"],      // array of scalars
  "createdAt": ISODate("2026-01-15T08:00:00Z"),
  "metadata": null
}
```

---

## Components – BSON (Binary JSON)

### BSON Types

```javascript
// BSON là superset của JSON, thêm các types:
{
  // String
  name: "Nguyen Van A",

  // Integer (32-bit)
  age: NumberInt(30),      // BSON Int32

  // Long (64-bit)
  views: NumberLong("12345678901"),

  // Double (64-bit float)
  price: 99.99,

  // Decimal128 (high precision – dùng cho tiền tệ)
  amount: NumberDecimal("1234567.89"),

  // Boolean
  active: true,

  // Date
  createdAt: new Date(),
  // hoặc: ISODate("2026-01-15T08:00:00Z")

  // ObjectId (12 bytes = 4 timestamp + 5 random + 3 counter)
  _id: ObjectId("65a1b2c3d4e5f67890123456"),

  // Array
  tags: ["vip", "premium"],

  // Embedded document
  address: { city: "HCM", zip: "70000" },

  // Binary
  photo: BinData(0, "base64encodeddata"),

  // Regular expression
  pattern: /^VN-\d{6}$/,

  // Null
  deletedAt: null,

  // Timestamp (internal – dùng cho replication)
  ts: Timestamp(1735689600, 1),
}
```

### ObjectId Structure

```
ObjectId("65 a1 b2 c3  d4 e5 f6 78 90  12 34 56")
          ←4 bytes→  ←── 5 bytes ──→  ←3 bytes→
          Unix time  Random (unique     Counter
          (seconds)  per machine+pid)  (per process)

Ưu điểm:
- Tự generate tại client, không cần roundtrip
- Monotonically increasing theo thời gian → index friendly
- Encode timestamp → extract creation time:
  ObjectId("65a1b2c3d4e5f67890123456").getTimestamp()
```

---

## How – Collection & Database

```javascript
// Implicit creation (tạo khi insert lần đầu)
use mydb;                          // switch/create database
db.users.insertOne({name: "A"});   // tạo collection 'users'

// Explicit creation (với options)
db.createCollection("orders", {
  capped: false,                   // capped: fixed-size, FIFO
  validator: {                     // schema validation (MongoDB 3.6+)
    $jsonSchema: {
      bsonType: "object",
      required: ["customerId", "amount", "status"],
      properties: {
        customerId: { bsonType: "objectId" },
        amount: {
          bsonType: "decimal",
          minimum: 0,
          description: "Amount must be positive"
        },
        status: {
          bsonType: "string",
          enum: ["pending", "confirmed", "delivered", "cancelled"]
        }
      }
    }
  },
  validationLevel: "strict",       // strict (mọi insert/update) hoặc moderate
  validationAction: "error"        // error (reject) hoặc warn (log only)
});

// Xem schema validation
db.getCollectionInfos({name: "orders"})[0].options.validator;

// Capped collection (event log, circular buffer)
db.createCollection("eventLog", {
  capped: true,
  size: 104857600,  // 100MB
  max: 1000000      // max 1M documents
});
```

---

## How – Document Design: Embed vs Reference

### Embedding (Denormalization)

```javascript
// Dùng khi: dữ liệu luôn access cùng nhau, 1-to-few, không update độc lập

// User + addresses embedded
{
  _id: ObjectId("..."),
  name: "Nguyen Van A",
  addresses: [
    { type: "home",    street: "123 Le Loi", city: "HCM", default: true },
    { type: "office",  street: "456 Nguyen Hue", city: "HCM" }
  ]
}

// Blog post + comments embedded (đến giới hạn nhất định)
{
  _id: ObjectId("..."),
  title: "MongoDB Best Practices",
  content: "...",
  comments: [  // chỉ embed nếu comments không quá nhiều (<100)
    { author: "User1", text: "Great!", createdAt: ISODate("...") },
    { author: "User2", text: "Helpful", createdAt: ISODate("...") }
  ]
}
```

### Referencing (Normalization)

```javascript
// Dùng khi: data lớn/nhiều, update độc lập, many-to-many, share giữa nhiều entities

// Order references Customer (không embed toàn bộ customer info)
// orders collection:
{
  _id: ObjectId("..."),
  customerId: ObjectId("65a1b2c3d4e5f67890123456"),  // reference
  items: [
    { productId: ObjectId("..."), qty: 2, price: 50000 }
  ],
  total: 100000
}

// customers collection:
{
  _id: ObjectId("65a1b2c3d4e5f67890123456"),
  name: "Nguyen Van A",
  email: "nva@example.com"
}

// $lookup để join (Aggregation Pipeline)
db.orders.aggregate([
  { $lookup: {
    from: "customers",
    localField: "customerId",
    foreignField: "_id",
    as: "customer"
  }},
  { $unwind: "$customer" }
]);
```

---

## How – Document Size & Limits

```javascript
// Document size limit: 16MB (BSON limit)
// Nếu cần > 16MB: dùng GridFS (chunks 255KB mỗi chunk)

// GridFS: lưu files lớn (images, videos, documents)
const bucket = new GridFSBucket(db, { bucketName: 'uploads' });
// Upload
const uploadStream = bucket.openUploadStream('video.mp4', {
  metadata: { contentType: 'video/mp4', uploadedBy: userId }
});
fs.createReadStream('./video.mp4').pipe(uploadStream);

// Array size: không có hard limit nhưng
// - Large arrays gây full-document scan khi update
// - Arrays > 1000 elements nên xem xét tách collection
// → Anti-pattern: unbounded arrays

// Key names:
// - Không được bắt đầu bằng $
// - Không chứa . (dot notation reserved)
// - Case-sensitive: "name" ≠ "Name"
```

---

## Why – Khi Nào Dùng Document Model?

```
Phù hợp:
✅ Schema thay đổi thường xuyên (rapid development)
✅ Data có hierarchy tự nhiên (user+addresses+orders)
✅ Read-heavy với full document access patterns
✅ Horizontal scaling cần thiết
✅ JSON API (document = API response)
✅ Content management, catalogs, user profiles
✅ Event logging, IoT sensor data

Không phù hợp:
❌ Complex multi-table JOINs với nhiều relationships
❌ Strong ACID transactions trên nhiều collections (dùng RDBMS)
❌ Reporting/BI với complex aggregations → data warehouse hơn
❌ Financial ledger (mỗi line item cần ACID guarantee)
```

---

## Compare – MongoDB vs SQL

| Concept | SQL | MongoDB |
|---------|-----|---------|
| Database | Database | Database |
| Table | Collection | Collection |
| Row | Document | Document |
| Column | Field | Field |
| Primary Key | PRIMARY KEY | _id |
| Foreign Key | FOREIGN KEY | Manual reference |
| JOIN | JOIN | $lookup (aggregation) |
| Index | INDEX | Index |
| Schema | Fixed | Flexible |
| Normalization | Normal forms | Embed vs Reference |
| Transaction | ACID (native) | ACID (4.0+ replica set) |

---

## Trade-offs

```
Document model:
✅ Flexible schema: thêm field không cần ALTER TABLE
✅ Colocation: related data trong 1 document → 1 read
✅ Native JSON: dễ work với REST APIs
❌ Data duplication khi embed (size vs join cost tradeoff)
❌ 16MB limit per document
❌ Denormalization → update anomaly nếu không cẩn thận
❌ Không enforce FK integrity natively (application responsibility)

BSON vs JSON:
✅ Binary format → faster parse, smaller size
✅ More types (Date, ObjectId, Decimal128, Binary)
❌ Không human-readable khi trên disk
```

---

## Real-world – Schema Versioning

```javascript
// Khi schema cần thay đổi, dùng schema versioning pattern
// Không cần migration ngay lập tức

// Version 1 (old):
{ _id: ObjectId(), name: "Nguyen Van A", phone: "0901234567" }

// Version 2 (new): tách phone thành object
{ _id: ObjectId(), name: "Nguyen Van A",
  phone: { number: "0901234567", verified: true },
  schemaVersion: 2 }

// Application code: handle cả 2 versions
function getPhone(user) {
  if (user.schemaVersion === 2) return user.phone.number;
  return user.phone; // backward compat
}

// Migrate lazily (on read) hoặc batch migration script
db.users.find({ schemaVersion: { $exists: false } })
  .forEach(doc => {
    db.users.updateOne(
      { _id: doc._id },
      {
        $set: {
          phone: { number: doc.phone, verified: false },
          schemaVersion: 2
        }
      }
    );
  });
```

---

## Ghi chú – Chủ đề tiếp theo
> `crud_aggregation.md`: CRUD operations chi tiết, Aggregation Pipeline stages, operators, window functions

---

*Cập nhật lần cuối: 2026-05-06*
