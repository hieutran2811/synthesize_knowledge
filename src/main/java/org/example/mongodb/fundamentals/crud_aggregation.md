# MongoDB CRUD & Aggregation Pipeline

> Mục tiêu phiên bản: **MongoDB 8.2**. Bài viết dùng `mongosh` để minh họa ý tưởng; khi viết ứng dụng, hãy dùng API tương đương của driver và kiểm tra kết quả trả về.
>
> Nên đọc trước: [Data Model & BSON](data_model.md). Tra cứu nhanh: [MongoDB Glossary](../glossary.md).

---

## 1. Bức tranh tổng thể

MongoDB có hai nhóm thao tác thường gặp:

- **CRUD** đọc hoặc thay đổi document: `insert`, `find`, `update`, `delete`.
- **Aggregation Pipeline** đưa document qua nhiều stage để lọc, biến đổi, nhóm, join hoặc tính toán.

Một request an toàn không chỉ có câu query. Nó cần trả lời đủ năm câu hỏi:

1. **Filter** nào xác định đúng document?
2. **Projection** nào giới hạn dữ liệu trả về?
3. Nếu lấy nhiều document, **sort order** có ổn định không?
4. Write thành công một phần hay toàn bộ, và ứng dụng kiểm tra **result** thế nào?
5. Nếu timeout hoặc mất mạng, retry có làm nghiệp vụ chạy hai lần không?

```text
Client
  │
  ├─ gửi filter + options + write/pipeline
  ▼
MongoDB query engine
  ├─ chọn execution plan và index
  ├─ đọc/biến đổi document
  └─ trả cursor hoặc write result
       │
       └─ ứng dụng phải consume/đóng cursor và kiểm tra result
```

### Ví dụ dữ liệu xuyên suốt

```javascript
db.orders.insertMany([
  {
    _id: ObjectId("66b000000000000000000001"),
    orderNo: "ORD-1001",
    customerId: ObjectId("65a000000000000000000001"),
    status: "PAID",
    createdAt: ISODate("2026-07-20T08:30:00Z"),
    version: 1,
    items: [
      { productId: "P01", name: "Keyboard", quantity: 2, unitPrice: Decimal128("49.90") },
      { productId: "P02", name: "Mouse", quantity: 1, unitPrice: Decimal128("19.50") }
    ],
    shipping: { city: "Da Nang", method: "EXPRESS" }
  },
  {
    _id: ObjectId("66b000000000000000000002"),
    orderNo: "ORD-1002",
    customerId: ObjectId("65a000000000000000000002"),
    status: "PENDING",
    createdAt: ISODate("2026-07-20T09:10:00Z"),
    version: 1,
    items: [
      { productId: "P01", name: "Keyboard", quantity: 1, unitPrice: Decimal128("49.90") }
    ],
    shipping: { city: "Ha Noi", method: "STANDARD" }
  }
]);
```

Trong production, `orderNo` là business key nên thường cần unique index:

```javascript
db.orders.createIndex({ orderNo: 1 }, { unique: true });
```

Unique index không chỉ tăng tốc lookup. Nó còn biến invariant “không có hai đơn cùng mã” thành một ràng buộc tại database.

---

## 2. Create: thêm document có kiểm soát

### 2.1 `insertOne()`

```javascript
const result = db.orders.insertOne({
  orderNo: "ORD-1003",
  customerId: ObjectId("65a000000000000000000003"),
  status: "PENDING",
  createdAt: new Date(),
  version: 1,
  items: []
});

print(result.acknowledged);
print(result.insertedId);
```

Nếu không truyền `_id`, driver thường tạo `ObjectId` trước khi gửi. Nhờ đó ứng dụng có thể giữ một ID ổn định khi cần retry.

Không nên hiểu `acknowledged: true` là “mọi replica đã lưu dữ liệu”. Ý nghĩa durability còn phụ thuộc **write concern**, được giải thích sâu hơn trong [Transactions](transactions.md) và [Replication](../operations/replication.md).

### 2.2 `insertMany()`: ordered và unordered

```javascript
db.orders.insertMany(
  [
    { orderNo: "ORD-1004", status: "PENDING", createdAt: new Date(), items: [] },
    { orderNo: "ORD-1005", status: "PENDING", createdAt: new Date(), items: [] }
  ],
  { ordered: false }
);
```

| Chế độ | Khi một phần tử lỗi | Khi phù hợp |
|---|---|---|
| `ordered: true` | Dừng tại lỗi đầu tiên | Các operation phụ thuộc thứ tự |
| `ordered: false` | Tiếp tục những phần tử có thể chạy | Import/batch độc lập, muốn throughput tốt hơn |

Điểm quan trọng: **unordered không có nghĩa là transaction**. Một số document có thể insert thành công trong khi số khác thất bại. Code phải đọc `writeErrors`, các counter và danh sách ID đã xử lý thay vì retry mù cả batch.

### 2.3 `bulkWrite()`: giảm round trip, không tự thêm tính nguyên tử

```javascript
const result = db.orders.bulkWrite(
  [
    {
      insertOne: {
        document: {
          orderNo: "ORD-1006",
          status: "PENDING",
          createdAt: new Date(),
          version: 1,
          items: []
        }
      }
    },
    {
      updateOne: {
        filter: { orderNo: "ORD-1002", status: "PENDING" },
        update: { $set: { status: "PAID", paidAt: new Date() } }
      }
    },
    {
      deleteOne: {
        filter: { orderNo: "ORD-CANCELLED-DRAFT" }
      }
    }
  ],
  { ordered: false }
);

printjson(result);
```

`db.collection.bulkWrite()` thao tác trên một collection. Từ MongoDB 8.0, `Mongo.bulkWrite()` có thể gom write trên nhiều database/collection vào một call, nhưng **một call nhiều namespace vẫn không đồng nghĩa với transaction**.

Batching giúp giảm network round trip. Nó không loại bỏ:

- partial success;
- duplicate key;
- schema validation error;
- write concern error;
- nhu cầu retry/idempotency.

---

## 3. Read: filter đúng, trả vừa đủ

### 3.1 Filter là một phần của business rule

```javascript
db.orders.find({
  status: "PAID",
  createdAt: {
    $gte: ISODate("2026-07-01T00:00:00Z"),
    $lt: ISODate("2026-08-01T00:00:00Z")
  },
  "shipping.city": { $in: ["Da Nang", "Hue"] }
});
```

Một số operator hay dùng:

| Nhóm | Operator |
|---|---|
| So sánh | `$eq`, `$ne`, `$gt`, `$gte`, `$lt`, `$lte`, `$in`, `$nin` |
| Logic | `$and`, `$or`, `$nor`, `$not` |
| Field/type | `$exists`, `$type` |
| Array | `$all`, `$size`, `$elemMatch` |
| Expression | `$expr` |

#### `null` không giống missing

```javascript
// Match cả field có giá trị null và field không tồn tại.
db.orders.find({ cancelledAt: null });

// Chỉ match field thực sự tồn tại và có giá trị null.
db.orders.find({
  cancelledAt: { $eq: null, $exists: true }
});

// Chỉ match field không tồn tại.
db.orders.find({ cancelledAt: { $exists: false } });
```

#### Dùng `$elemMatch` khi các điều kiện phải đúng trên cùng một phần tử

```javascript
db.orders.find({
  items: {
    $elemMatch: {
      productId: "P01",
      quantity: { $gte: 2 }
    }
  }
});
```

Nếu viết hai điều kiện rời trên `items.productId` và `items.quantity`, mỗi điều kiện có thể match một phần tử khác nhau trong array.

### 3.2 Projection: chỉ lấy field cần dùng

```javascript
db.orders.find(
  { status: "PAID" },
  {
    _id: 0,
    orderNo: 1,
    customerId: 1,
    createdAt: 1,
    "shipping.city": 1
  }
);
```

Quy tắc thực dụng:

- Không trộn include (`1`) và exclude (`0`) trong cùng projection, ngoại trừ `_id`.
- Projection giảm network, deserialize và rò rỉ field không cần thiết.
- Projection không tự sửa một document quá lớn hoặc data model không phù hợp.
- Query chỉ đọc field trong index có thể trở thành **covered query**; phần này được giải thích tại [Indexing](indexing.md).

### 3.3 Cursor không phải một mảng đã tải sẵn

```javascript
const cursor = db.orders
  .find({ status: "PAID" })
  .sort({ createdAt: -1, _id: -1 })
  .limit(50)
  .batchSize(100)
  .maxTimeMS(2_000);

for (const order of cursor) {
  // Xử lý từng document; đừng gom vô hạn vào RAM của ứng dụng.
  print(order.orderNo);
}
```

`find()` trả cursor. Driver lấy dữ liệu theo batch và thường quản lý việc đóng cursor, nhưng ứng dụng vẫn nên:

- consume theo stream/iterator nếu tập kết quả lớn;
- đóng sớm khi dừng giữa chừng;
- đặt timeout phù hợp với SLA;
- tránh `toArray()` cho query không có bound;
- thêm `comment`/metadata truy vết nếu hệ thống observability sử dụng.

`maxTimeMS` là giới hạn phía server, không thay toàn bộ timeout budget phía client.

### 3.4 Sort phải deterministic

```javascript
db.orders
  .find({ status: "PAID" })
  .sort({ createdAt: -1, _id: -1 })
  .limit(20);
```

Nhiều đơn có thể cùng `createdAt`. Thêm `_id` làm tie-breaker để thứ tự ổn định. Index phục vụ query này thường bắt đầu từ filter/sort pattern tương ứng; không nên tạo index theo ví dụ một cách máy móc.

### 3.5 Pagination: `skip()` dễ viết, range/keyset bền hơn

Offset pagination:

```javascript
db.orders
  .find({ status: "PAID" })
  .sort({ createdAt: -1, _id: -1 })
  .skip(20_000)
  .limit(20);
```

Server vẫn phải đi qua các kết quả trước offset. Page càng sâu càng chậm; dữ liệu được insert/delete giữa hai request còn có thể làm trùng hoặc bỏ sót item.

Với keyset pagination, client giữ cặp `(createdAt, _id)` cuối trang trước:

```javascript
const lastCreatedAt = ISODate("2026-07-20T08:30:00Z");
const lastId = ObjectId("66b000000000000000000000");

db.orders
  .find({
    status: "PAID",
    $or: [
      { createdAt: { $lt: lastCreatedAt } },
      { createdAt: lastCreatedAt, _id: { $lt: lastId } }
    ]
  })
  .sort({ createdAt: -1, _id: -1 })
  .limit(20);
```

Index thường được cân nhắc:

```javascript
db.orders.createIndex({ status: 1, createdAt: -1, _id: -1 });
```

| Offset pagination | Keyset pagination |
|---|---|
| Dễ nhảy đến page N | Đi tiếp từ cursor/token |
| Chi phí tăng theo offset | Có thể seek bằng range trên index |
| Dễ xê dịch khi dữ liệu đổi | Ổn định hơn với sort key duy nhất |
| Hợp tập nhỏ/admin UI | Hợp feed/API có page sâu |

### 3.6 Đếm document

```javascript
// Đếm chính xác các document thỏa filter.
db.orders.countDocuments({ status: "PAID" });

// Ước lượng nhanh tổng collection dựa trên metadata.
db.orders.estimatedDocumentCount();
```

Đừng dùng `estimatedDocumentCount()` khi business cần số lượng chính xác theo filter. Ngược lại, đừng bắt database scan/count chính xác chỉ để hiển thị một con số không quan trọng.

---

## 4. Update: tận dụng atomicity của một document

### 4.1 Update operator tốt hơn read-modify-write

```javascript
const result = db.orders.updateOne(
  { orderNo: "ORD-1002", status: "PENDING" },
  {
    $set: {
      status: "PAID",
      paidAt: new Date()
    },
    $inc: { version: 1 }
  }
);

printjson({
  acknowledged: result.acknowledged,
  matchedCount: result.matchedCount,
  modifiedCount: result.modifiedCount,
  upsertedId: result.upsertedId
});
```

`matchedCount` và `modifiedCount` trả lời hai câu khác nhau:

- `matchedCount: 0`: filter không match; có thể không tồn tại hoặc trạng thái/version đã đổi.
- `matchedCount: 1`, `modifiedCount: 0`: document match nhưng write có thể không thay đổi giá trị.

Các operator thường dùng:

| Operator | Ý nghĩa |
|---|---|
| `$set`, `$unset` | Gán hoặc xóa field |
| `$inc`, `$mul` | Thay đổi số dựa trên giá trị hiện tại |
| `$min`, `$max` | Chỉ cập nhật khi giá trị nhỏ/lớn hơn |
| `$currentDate` | Gán thời điểm hiện tại phía server |
| `$push`, `$addToSet`, `$pull`, `$pop` | Thay đổi array |
| `$setOnInsert` | Chỉ gán khi upsert tạo document mới |

Một update trên **một document** là atomic. Vì vậy `$inc` an toàn hơn mô hình:

```text
đọc quantity = 10
quantity = quantity + 1 ở application
ghi lại 11
```

Hai request cùng đọc `10` có thể cùng ghi `11` và làm mất một lần tăng.

### 4.2 Optimistic concurrency bằng version

```javascript
const result = db.orders.updateOne(
  {
    _id: ObjectId("66b000000000000000000000"),
    version: 7,
    status: "PENDING"
  },
  {
    $set: { status: "PAID", paidAt: new Date() },
    $inc: { version: 1 }
  }
);

if (result.matchedCount !== 1) {
  throw new Error("Order đã bị thay đổi hoặc không còn ở trạng thái PENDING");
}
```

Version phải nằm trong filter và được tăng trong cùng update. Chỉ đọc version trước rồi update bằng `_id` là chưa chống conflict.

### 4.3 `findOneAndUpdate()`: claim công việc không tạo race

```javascript
const job = db.jobs.findOneAndUpdate(
  {
    status: "READY",
    availableAt: { $lte: new Date() }
  },
  {
    $set: {
      status: "RUNNING",
      workerId: "worker-07",
      startedAt: new Date()
    },
    $inc: { attempts: 1 }
  },
  {
    sort: { priority: -1, availableAt: 1, _id: 1 },
    returnDocument: "after"
  }
);
```

Việc tìm và update một document diễn ra atomically. Filter phải chứa trạng thái có thể claim; sort cần tie-breaker ổn định. Đây là pattern hữu ích cho lightweight work claiming, nhưng MongoDB collection không tự có đủ semantics của message broker như delivery, visibility timeout hay dead-letter queue.

### 4.4 Upsert cần unique index

```javascript
db.dailyCounters.createIndex(
  { tenantId: 1, day: 1 },
  { unique: true }
);

const result = db.dailyCounters.updateOne(
  {
    tenantId: "tenant-a",
    day: ISODate("2026-07-29T00:00:00Z")
  },
  {
    $inc: { orderCount: 1 },
    $setOnInsert: { createdAt: new Date() }
  },
  { upsert: true }
);
```

Upsert nghĩa là “update nếu match, nếu không thì insert”. Nếu business key không có unique index, hai request cạnh tranh có thể tạo hai document logic giống nhau. `upsertedId` cho biết operation đã tạo document mới.

### 4.5 Update array có chủ đích

```javascript
db.orders.updateOne(
  {
    orderNo: "ORD-1001",
    "items.productId": "P01"
  },
  {
    $inc: { "items.$.quantity": 1 }
  }
);
```

Nhiều phần tử:

```javascript
db.orders.updateOne(
  { orderNo: "ORD-1001" },
  {
    $set: { "items.$[expensive].reviewRequired": true }
  },
  {
    arrayFilters: [
      { "expensive.unitPrice": { $gte: Decimal128("40.00") } }
    ]
  }
);
```

Array phát triển không giới hạn sẽ làm document và multikey index phình ra. Khi cardinality không bounded, hãy quay lại quyết định embed/reference trong [Data Model & BSON](data_model.md).

### 4.6 Update bằng aggregation pipeline

Update pipeline phù hợp khi giá trị mới phụ thuộc nhiều field hiện tại:

```javascript
db.orders.updateMany(
  { subtotal: { $exists: true }, tax: { $exists: true } },
  [
    {
      $set: {
        total: { $add: ["$subtotal", "$tax"] },
        recalculatedAt: "$$NOW"
      }
    },
    {
      $unset: ["legacyTotal"]
    }
  ]
);
```

Không phải mọi aggregation stage đều được phép trong update pipeline. Hãy xem đây là một update có biểu thức tính toán, không phải pipeline tùy ý có `$group` hay `$lookup`.

---

## 5. Delete và vòng đời dữ liệu

```javascript
const result = db.orders.deleteOne({
  orderNo: "ORD-DRAFT-01",
  status: "DRAFT"
});

if (result.deletedCount !== 1) {
  print("Không xóa: document không tồn tại hoặc status đã đổi");
}
```

Filter của delete là hàng rào an toàn. Tránh chạy `deleteMany({})` hoặc filter được build động mà không kiểm tra input, quyền và môi trường.

### 5.1 Soft delete không miễn phí

```javascript
db.orders.updateOne(
  { _id: ObjectId("66b000000000000000000000"), deletedAt: { $exists: false } },
  {
    $set: {
      deletedAt: new Date(),
      deletedBy: "user-42",
      active: false
    },
    $inc: { version: 1 }
  }
);
```

Soft delete giữ audit/khôi phục thuận tiện, nhưng kéo theo:

- mọi read path phải loại document đã xóa;
- unique constraint có thể cần partial unique index;
- index và working set vẫn chứa dữ liệu;
- phải có retention/archive/purge rõ ràng;
- dữ liệu nhạy cảm có thể vẫn phải hard delete theo chính sách.

Ví dụ unique email chỉ áp dụng cho account chưa bị xóa:

```javascript
db.accounts.createIndex(
  { tenantId: 1, email: 1 },
  {
    unique: true,
    partialFilterExpression: { active: true }
  }
);
```

Mẫu này yêu cầu mọi account đang hoạt động có `active: true`; hãy backfill và validate field trước khi dựa vào index.

TTL index phù hợp với dữ liệu hết hạn theo thời gian như session/log tạm, nhưng deletion chạy nền và không đảm bảo xóa đúng từng millisecond. Đừng dùng TTL như một scheduler chính xác.

---

## 6. Retry, timeout và “không biết write đã chạy chưa”

Mất kết nối sau khi server nhận write tạo ra tình huống khó:

```text
Client gửi write
  ├─ server chưa chạy     → retry có thể cần thiết
  └─ server đã chạy xong
       └─ response bị mất → client vẫn thấy timeout
```

Official driver hiện đại bật **retryable writes** mặc định cho topology và operation được hỗ trợ. Driver có thể retry write đủ điều kiện khi gặp lỗi mạng hoặc election; điều này không có nghĩa mọi command đều retry được.

Các nguyên tắc cần giữ:

- Dùng `_id`/business key ổn định và unique constraint.
- Ưu tiên `updateOne`, `replaceOne`, `deleteOne` với filter rõ ràng.
- `updateMany`, `deleteMany` và write bên trong transaction có semantics retry khác.
- Không retry toàn bộ unordered batch mà bỏ qua partial result.
- Timeout phải đi cùng error classification và reconciliation.
- Database retry không thể hoàn tác side effect ngoài MongoDB, ví dụ đã gửi email hoặc gọi payment API.

Ví dụ tạo order idempotent:

```javascript
db.orders.updateOne(
  { orderNo: "ORD-1007" },
  {
    $setOnInsert: {
      status: "PENDING",
      createdAt: new Date(),
      version: 1,
      items: []
    }
  },
  { upsert: true }
);
```

Pattern này chỉ đúng khi `orderNo` có unique index và payload lặp lại thực sự đại diện cùng một request nghiệp vụ.

---

## 7. Aggregation Pipeline: document đi qua từng stage

Mỗi stage nhận một luồng document và trả luồng document mới:

```text
orders
  → $match       giảm số document
  → $unwind      một order thành nhiều item
  → $group       gom theo product
  → $sort        xếp theo revenue
  → $limit       chỉ giữ top N
  → $project     tạo response shape
```

Một số stage **streaming** có thể phát kết quả dần. Một số stage **blocking** như `$sort` không có index hỗ trợ, `$group`, `$bucket` hoặc `$setWindowFields` có thể phải giữ nhiều state trong RAM trước khi trả kết quả.

### 7.1 Ví dụ: top sản phẩm theo doanh thu

```javascript
db.orders.aggregate([
  {
    $match: {
      status: "PAID",
      createdAt: {
        $gte: ISODate("2026-07-01T00:00:00Z"),
        $lt: ISODate("2026-08-01T00:00:00Z")
      }
    }
  },
  { $unwind: "$items" },
  {
    $group: {
      _id: "$items.productId",
      productName: { $first: "$items.name" },
      units: { $sum: "$items.quantity" },
      revenue: {
        $sum: {
          $multiply: ["$items.quantity", "$items.unitPrice"]
        }
      }
    }
  },
  { $sort: { revenue: -1, _id: 1 } },
  { $limit: 10 },
  {
    $project: {
      _id: 0,
      productId: "$_id",
      productName: 1,
      units: 1,
      revenue: 1
    }
  }
], {
  maxTimeMS: 5_000,
  comment: "monthly-top-products"
});
```

Đọc pipeline từ trái sang phải:

1. `$match` giảm dữ liệu theo status và thời gian.
2. `$unwind` biến mỗi item thành một document logic.
3. `$group` gom item cùng `productId`.
4. `$sort` xếp revenue, `_id` làm tie-breaker.
5. `$limit` chặn cardinality kết quả.
6. `$project` tạo đúng response contract.

Giá dùng `Decimal128`, vì vậy kết quả phép nhân/cộng cũng giữ decimal semantics phù hợp hơn `double` cho tiền.

### 7.2 Stage quan trọng

| Stage | Dùng để | Rủi ro chính |
|---|---|---|
| `$match` | Lọc document | Filter muộn làm nhiều dữ liệu đi qua pipeline |
| `$project` | Chọn/đổi shape field | Expression sai type; projection sớm thường không cần thiết |
| `$set` / `$addFields` | Thêm hoặc tính field | Tăng kích thước document trung gian |
| `$unset` | Bỏ field | Bỏ field cần cho stage sau |
| `$unwind` | Tách array thành nhiều row logic | Cardinality bùng nổ |
| `$group` | Gom nhóm và accumulator | Blocking, dùng nhiều memory |
| `$sort` | Sắp xếp | Blocking nếu index không hỗ trợ |
| `$limit` / `$skip` | Giới hạn/bỏ qua | `$skip` sâu vẫn đắt |
| `$lookup` | Left outer join collection khác | Join fan-out, thiếu index phía foreign |
| `$facet` | Chạy nhiều sub-pipeline trên cùng input | 100 MB riêng, output document dễ quá lớn |
| `$setWindowFields` | Rank, running total, moving average | Partition/sort lớn, memory/disk |
| `$bucket` / `$bucketAuto` | Chia dữ liệu theo khoảng | Blocking và boundary không phù hợp |
| `$count` | Đếm kết quả pipeline | Vẫn phải xử lý toàn bộ input cần đếm |
| `$merge` / `$out` | Ghi kết quả ra collection | Có side effect, quyền và retry phức tạp |

### 7.3 Expression và accumulator không phải stage

```javascript
db.orders.aggregate([
  {
    $set: {
      ageInDays: {
        $dateDiff: {
          startDate: "$createdAt",
          endDate: "$$NOW",
          unit: "day"
        }
      },
      customerLabel: {
        $concat: ["customer:", { $toString: "$customerId" }]
      }
    }
  }
]);
```

- `$set` là **stage**.
- `$dateDiff`, `$concat`, `$toString` là **expression**.
- `$sum`, `$avg`, `$first`, `$push` có thể là **accumulator** trong các context như `$group` hoặc window.

Phân biệt ba lớp này giúp đọc lỗi cú pháp nhanh hơn.

---

## 8. `$lookup`: tránh N+1 nhưng không phải join miễn phí

```javascript
db.orders.aggregate([
  { $match: { status: "PAID" } },
  {
    $lookup: {
      from: "customers",
      localField: "customerId",
      foreignField: "_id",
      pipeline: [
        { $project: { _id: 1, name: 1, tier: 1 } }
      ],
      as: "customer"
    }
  },
  {
    $set: {
      customer: { $first: "$customer" }
    }
  }
]);
```

Equality lookup chạy tốt hơn khi `foreignField` có index. `_id` đã có unique index mặc định; với field khác, cần đánh giá index riêng.

Trước khi dùng `$lookup`, hỏi:

- Local query đã giảm đủ input chưa?
- Mỗi local document match bao nhiêu foreign document?
- Foreign join key có index không?
- Dữ liệu có thường được đọc cùng và đủ bounded để embed không?
- Response có thể vượt 16 MiB sau fan-out không?

`$lookup` có thể thay nhiều round trip N+1 bằng một pipeline, nhưng join cardinality xấu vẫn tạo workload xấu.

---

## 9. Window function: tính trên hàng lân cận mà không gom mất chi tiết

Ví dụ xếp hạng order theo giá trị trong từng khách hàng:

```javascript
db.orders.aggregate([
  { $match: { status: "PAID" } },
  {
    $set: {
      total: {
        $reduce: {
          input: "$items",
          initialValue: Decimal128("0"),
          in: {
            $add: [
              "$$value",
              { $multiply: ["$$this.quantity", "$$this.unitPrice"] }
            ]
          }
        }
      }
    }
  },
  {
    $setWindowFields: {
      partitionBy: "$customerId",
      sortBy: { total: -1 },
      output: {
        orderRank: { $rank: {} },
        customerRunningSpend: {
          $sum: "$total",
          window: { documents: ["unbounded", "current"] }
        }
      }
    }
  },
  {
    $project: {
      orderNo: 1,
      customerId: 1,
      total: 1,
      orderRank: 1,
      customerRunningSpend: 1
    }
  }
]);
```

Khác `$group`, window function vẫn giữ từng order trong output. Hãy theo dõi partition lớn, sort và spill; đôi khi pre-aggregate hoặc materialized summary phù hợp hơn.

---

## 10. `$facet`: tiện nhưng có giới hạn riêng

Ví dụ lấy page đầu và tổng count trong cùng pipeline:

```javascript
db.orders.aggregate([
  { $match: { status: "PAID" } },
  { $sort: { createdAt: -1, _id: -1 } },
  {
    $facet: {
      items: [
        { $limit: 20 },
        { $project: { orderNo: 1, createdAt: 1, customerId: 1 } }
      ],
      metadata: [
        { $count: "total" }
      ]
    }
  }
]);
```

`$facet` đưa output của mỗi sub-pipeline vào một array trong **một document**:

- mỗi facet stage bị giới hạn 100 MB;
- `$facet` không spill ra disk, nên `allowDiskUse` không gỡ giới hạn này;
- document kết quả cuối vẫn bị giới hạn 16 MiB.

Với tập lớn hoặc API page sâu, hai query độc lập—một query items và một query count khi thật sự cần—thường dễ kiểm soát latency hơn.

---

## 11. `$merge` và `$out`: pipeline có side effect

Tạo collection tổng hợp:

```javascript
db.orders.aggregate([
  { $match: { status: "PAID" } },
  { $unwind: "$items" },
  {
    $group: {
      _id: {
        day: {
          $dateTrunc: {
            date: "$createdAt",
            unit: "day",
            timezone: "Asia/Ho_Chi_Minh"
          }
        },
        productId: "$items.productId"
      },
      units: { $sum: "$items.quantity" },
      revenue: {
        $sum: {
          $multiply: ["$items.quantity", "$items.unitPrice"]
        }
      }
    }
  },
  {
    $merge: {
      into: "daily_product_sales",
      on: "_id",
      whenMatched: "replace",
      whenNotMatched: "insert"
    }
  }
]);
```

- `$merge` có thể insert/merge/replace document vào collection đích.
- `$out` thay thế nội dung collection đích bằng toàn bộ output mới.
- Pipeline có `$merge`/`$out` là write workload: cần quyền write, capacity, idempotency và error handling.
- Retryable read không áp dụng cho pipeline có write stage.

Materialized summary tăng tốc read nhưng phải có owner, lịch refresh, cách backfill và reconciliation khi dữ liệu nguồn sửa muộn.

---

## 12. Tối ưu pipeline bằng cardinality và index

Đừng chỉ hỏi “stage nào nhanh?”. Hãy theo dõi số document và kích thước document sau từng stage:

```text
1.000.000 orders
   │ $match theo tháng + status
   ▼
  40.000 orders
   │ $unwind trung bình 5 items/order
   ▼
 200.000 rows logic
   │ $group theo productId
   ▼
   3.000 groups
   │ $sort + $limit 10
   ▼
      10 results
```

Nguyên tắc:

1. Lọc sớm bằng predicate có thể dùng index.
2. Cho `$sort` dùng index khi filter/sort pattern cho phép.
3. Giảm fan-out trước `$unwind`/`$lookup` nếu đúng semantics.
4. Đặt `$limit` sớm nhất có thể nhưng không làm đổi ý nghĩa kết quả.
5. Đừng thêm `$project` đầu pipeline chỉ để “giảm field” theo thói quen; optimizer có thể tự loại field không cần.
6. Không phụ thuộc cứng vào thứ tự internal sau tối ưu; optimizer có thể đẩy `$match` hoặc gộp stage giữa các phiên bản.

MongoDB giới hạn một pipeline ở 1.000 stage. Một số blocking stage dùng hơn 100 MB có thể spill ra disk tùy `allowDiskUseByDefault` hoặc option `allowDiskUse`. Spill giúp operation hoàn tất, nhưng thường chậm hơn và tạo I/O; nó là tín hiệu cần quan sát, không phải nút “tăng tốc”.

Mỗi document kết quả vẫn bị giới hạn BSON 16 MiB, dù document trung gian có thể tạm lớn hơn.

Map-reduce đã deprecated từ MongoDB 5.0. Với workload mới, dùng Aggregation Pipeline và các stage như `$group`, `$merge`.

---

## 13. `explain()`: đo plan thay vì đoán

Query:

```javascript
db.orders
  .find({
    status: "PAID",
    createdAt: { $gte: ISODate("2026-07-01T00:00:00Z") }
  })
  .sort({ createdAt: -1, _id: -1 })
  .explain("executionStats");
```

Aggregation:

```javascript
db.orders.explain("executionStats").aggregate([
  {
    $match: {
      status: "PAID",
      createdAt: { $gte: ISODate("2026-07-01T00:00:00Z") }
    }
  },
  { $sort: { createdAt: -1, _id: -1 } },
  { $limit: 20 }
]);
```

Các dấu hiệu cần đọc:

| Dấu hiệu | Câu hỏi |
|---|---|
| `IXSCAN` | Index có khớp filter/sort và bounds có hẹp không? |
| `COLLSCAN` | Scan toàn collection là có chủ đích hay thiếu index? |
| `totalDocsExamined` | Đọc bao nhiêu document để trả `nReturned`? |
| `totalKeysExamined` | Index scan có quá rộng không? |
| `nReturned` | Có trả đúng cardinality mong đợi không? |
| sort/spill/`usedDisk` | Blocking stage có vượt memory và ghi file tạm không? |
| `executionTimeMillis` | Chỉ là một lần đo hay phản ánh workload đại diện? |

`hint()` hữu ích để chẩn đoán hoặc khóa plan trong tình huống đã đo kỹ. Đừng dùng `hint()` mặc định để che một index/query design chưa hiểu rõ; plan tối ưu có thể đổi theo dữ liệu và phiên bản.

Không chạy `executionStats` bừa bãi với query nặng trên production: explain ở chế độ này thực sự thực thi plan.

---

## 14. Java driver: kiểm tra result trong code

Ví dụ optimistic update với Java Sync Driver:

```java
import com.mongodb.client.result.UpdateResult;
import java.util.ConcurrentModificationException;
import java.util.Date;

import static com.mongodb.client.model.Filters.and;
import static com.mongodb.client.model.Filters.eq;
import static com.mongodb.client.model.Updates.combine;
import static com.mongodb.client.model.Updates.inc;
import static com.mongodb.client.model.Updates.set;

UpdateResult result = orders.updateOne(
    and(
        eq("_id", orderId),
        eq("version", expectedVersion),
        eq("status", "PENDING")
    ),
    combine(
        set("status", "PAID"),
        set("paidAt", new Date()),
        inc("version", 1)
    )
);

if (result.getMatchedCount() != 1) {
    throw new ConcurrentModificationException(
        "Order đã đổi version hoặc không còn PENDING"
    );
}
```

Điểm chính không nằm ở syntax builder mà ở contract:

- filter chứa invariant và expected state;
- update dùng operator atomic;
- code kiểm tra `matchedCount`;
- exception được map thành conflict nghiệp vụ phù hợp.

Với cursor:

```java
import com.mongodb.client.MongoCursor;
import com.mongodb.client.model.Projections;
import com.mongodb.client.model.Sorts;
import org.bson.Document;

try (MongoCursor<Document> cursor = orders
        .find(eq("status", "PAID"))
        .projection(Projections.include("orderNo", "createdAt"))
        .sort(Sorts.orderBy(
            Sorts.descending("createdAt"),
            Sorts.descending("_id")
        ))
        .limit(50)
        .iterator()) {

    while (cursor.hasNext()) {
        process(cursor.next());
    }
}
```

Tên class/option có thể thay đổi theo driver version; kiểm tra tài liệu driver đang dùng và thống nhất BSON-to-domain mapping trong dự án.

---

## 15. Anti-pattern thường gặp

| Anti-pattern | Vì sao nguy hiểm | Hướng sửa |
|---|---|---|
| `find({})` rồi `toArray()` | RAM/network không bounded | Filter, projection, limit và stream cursor |
| Sort field không unique | Page có thể trùng/bỏ sót | Thêm `_id` làm tie-breaker |
| `skip()` cho page rất sâu | Scan bỏ qua càng ngày càng nhiều | Keyset/range pagination |
| Read-modify-write counter | Lost update | `$inc` trong một atomic update |
| Upsert không có unique index | Có thể sinh duplicate logic | Unique index trên business key |
| Không kiểm tra write result | Conflict bị coi là thành công | Kiểm tra matched/modified/deleted/upserted |
| Retry toàn batch sau timeout | Lặp write đã thành công một phần | Stable ID, partial result, reconciliation |
| `$unwind` trước khi lọc | Cardinality bùng nổ | `$match` sớm nếu không đổi semantics |
| `$lookup` không index foreign key | Join scan lớn | Index và kiểm soát fan-out |
| `$facet` cho dữ liệu rất lớn | Chạm 100 MB/16 MiB | Tách query hoặc đổi response model |
| Bật `allowDiskUse` rồi bỏ qua | Spill làm I/O/latency tăng | Đo cardinality, index và stage order |
| Dùng `hint()` theo cảm tính | Ép plan xấu khi dữ liệu đổi | Dựa trên `explain` và benchmark |

---

## 16. Checklist review query/write

### CRUD

- [ ] Filter có chứa tenant/business state cần bảo vệ?
- [ ] Projection chỉ trả field consumer cần?
- [ ] Sort có tie-breaker duy nhất?
- [ ] Pagination sâu dùng keyset thay vì offset?
- [ ] Cursor, batch size và timeout có bound?
- [ ] Update dùng atomic operator thay read-modify-write?
- [ ] Upsert có unique index trên business key?
- [ ] Code kiểm tra write result và partial failure?
- [ ] Retry có idempotency key/stable ID và reconciliation?
- [ ] Soft delete có retention, index và uniqueness strategy?

### Aggregation

- [ ] `$match` đầu pipeline có thể dùng index?
- [ ] Cardinality trước/sau `$unwind`, `$lookup`, `$group` là bao nhiêu?
- [ ] Sort/group/window có thể spill không?
- [ ] `$lookup` foreign field có index và fan-out bounded?
- [ ] `$facet` có nguy cơ vượt 100 MB hoặc 16 MiB?
- [ ] `$merge`/`$out` có quyền, capacity và retry strategy?
- [ ] `explain("executionStats")` cho thấy docs/keys examined hợp lý?
- [ ] Query đã được thử với dữ liệu và phân bố gần production?

---

## 17. Tóm tắt

- CRUD tốt bắt đầu từ **filter đúng**, **result được kiểm tra** và **retry có chủ đích**.
- Single-document update là atomic; dùng `$inc`, conditional filter và version để tránh race.
- `insertMany()`/`bulkWrite()` có thể thành công một phần; unordered không phải transaction.
- Sort ổn định cần tie-breaker; keyset pagination phù hợp hơn `skip()` ở page sâu.
- Aggregation là dataflow: luôn theo dõi cardinality, blocking stage, memory và index.
- `$lookup`, `$facet`, window function và disk spill đều hữu ích nhưng có chi phí rõ ràng.
- `explain()` và số đo trên workload đại diện đáng tin hơn mẹo tối ưu truyền miệng.

## 18. Đọc tiếp

- [Indexing](indexing.md) – chọn index từ filter, sort và projection.
- [Transactions](transactions.md) – khi invariant vượt quá một document.
- [Schema Design Patterns](../performance/schema_design.md) – giảm join và giữ working set bounded.
- [MongoDB Glossary](../glossary.md) – tra cứu thuật ngữ.

## Tài liệu chính thức

- [MongoDB CRUD Operations](https://www.mongodb.com/docs/v8.2/crud/)
- [Bulk Write Operations](https://www.mongodb.com/docs/v8.2/core/bulk-write-operations/)
- [`cursor.skip()` và range pagination](https://www.mongodb.com/docs/v8.2/reference/method/cursor.skip/)
- [Retryable Writes](https://www.mongodb.com/docs/v8.2/core/retryable-writes/)
- [Aggregation Pipeline](https://www.mongodb.com/docs/v8.2/core/aggregation-pipeline/)
- [Aggregation Pipeline Optimization](https://www.mongodb.com/docs/v8.2/core/aggregation-pipeline-optimization/)
- [Aggregation Pipeline Limits](https://www.mongodb.com/docs/v8.2/core/aggregation-pipeline-limits/)
- [`$facet`](https://www.mongodb.com/docs/v8.2/reference/operator/aggregation/facet/)
- [`$lookup`](https://www.mongodb.com/docs/v8.2/reference/operator/aggregation/lookup/)
- [Map-Reduce (deprecated)](https://www.mongodb.com/docs/v8.2/core/map-reduce/)

---

*Cập nhật lần cuối: 2026-07-29 – MongoDB 8.2*
