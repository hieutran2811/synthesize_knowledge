# MongoDB Indexing – thiết kế từ query pattern

> Mục tiêu phiên bản: **MongoDB 8.2**. Bài viết dùng `mongosh` để minh họa; hãy kiểm tra API tương ứng của driver đang dùng.
>
> Nên đọc trước: [CRUD & Aggregation Pipeline](crud_aggregation.md). Tra cứu nhanh: [MongoDB Glossary](../glossary.md).

---

## 1. Index giải quyết vấn đề gì?

Không có index phù hợp, MongoDB có thể phải đọc nhiều hoặc toàn bộ document trong collection để tìm kết quả. Index lưu các key đã sắp xếp trong cấu trúc B-tree, nhờ đó query engine có thể:

- seek đến một equality/range hẹp;
- đọc dữ liệu theo đúng thứ tự sort;
- đôi khi trả kết quả trực tiếp từ index mà không fetch document;
- thực thi ràng buộc như `unique`;
- hỗ trợ workload chuyên biệt như TTL, geospatial, text hoặc hashed sharding.

```text
Không có index phù hợp
query → COLLSCAN → đọc nhiều document → filter → trả kết quả

Có index phù hợp
query → seek/index scan → fetch ít document → trả kết quả

Covered query
query → index scan → trả kết quả ngay từ index
```

MongoDB tạo unique index cho `_id` trên collection thông thường. Các index còn lại phải xuất phát từ workload, không phải từ danh sách field trong schema.

### Index không miễn phí

Mỗi secondary index làm tăng:

- disk và cache pressure;
- chi phí insert;
- chi phí update khi indexed field thay đổi;
- replication work trên secondary;
- thời gian backup/restore và maintenance;
- không gian tạm, I/O và rủi ro vận hành khi build.

Mục tiêu không phải “index mọi field”, mà là **bộ index nhỏ nhất phục vụ các query shape quan trọng trong SLA**.

---

## 2. Bắt đầu từ query shape, không bắt đầu từ field

Giả sử API có query:

```javascript
db.orders.find(
  {
    tenantId: "tenant-a",
    status: "PAID",
    createdAt: {
      $gte: ISODate("2026-07-01T00:00:00Z"),
      $lt: ISODate("2026-08-01T00:00:00Z")
    }
  },
  {
    _id: 0,
    orderNo: 1,
    customerId: 1,
    createdAt: 1
  }
)
.sort({ createdAt: -1 })
.limit(50);
```

Query shape gồm:

| Thành phần | Ví dụ | Ảnh hưởng index |
|---|---|---|
| Equality | `tenantId`, `status` | Thường đặt đầu compound index |
| Sort | `createdAt: -1` | Đặt tiếp nếu muốn tránh blocking sort |
| Range | khoảng `createdAt` | Scan một đoạn index |
| Projection | `orderNo`, `customerId`, `createdAt` | Có thể thêm để tạo covered query nếu đáng |
| Limit | `50` | Có thể dừng scan sớm |
| Cardinality/selectivity | số tenant, phân bố status/thời gian | Quyết định scan hẹp đến đâu |

Một index khởi đầu hợp lý:

```javascript
db.orders.createIndex(
  { tenantId: 1, status: 1, createdAt: -1 },
  { name: "orders_tenant_status_createdAt" }
);
```

Nhưng chưa thể kết luận index này tốt chỉ từ syntax. Cần trả lời:

1. Query có chạy thường xuyên và có SLA nào?
2. Mỗi tenant có bao nhiêu order?
3. `PAID` chiếm 1% hay 95% dữ liệu?
4. Query cần sort hay có thể bỏ?
5. Write rate và kích thước index có chấp nhận được?
6. `explain("executionStats")` trên dữ liệu đại diện cho thấy gì?

---

## 3. Compound index và ESR/ERS

### 3.1 Equality đứng trước

Với query:

```javascript
db.orders.find({
  tenantId: "tenant-a",
  customerId: ObjectId("65a000000000000000000001")
});
```

Index:

```javascript
db.orders.createIndex({
  tenantId: 1,
  customerId: 1
});
```

Các equality field thường đứng đầu. Query engine có thể thu hẹp đến đúng nhánh của B-tree trước khi xử lý sort/range.

Khi nhiều field đều là equality, thứ tự giữa chính các equality field thường không quan trọng đối với ESR; điều quan trọng là chúng đứng trước sort/range. Tuy nhiên prefix reuse, các query shape khác và shard key vẫn có thể khiến thứ tự đó quan trọng ở cấp thiết kế tổng thể.

### 3.2 ESR: Equality → Sort → Range

Query vừa lọc vừa sort:

```javascript
db.orders
  .find({
    tenantId: "tenant-a",
    status: "PAID",
    createdAt: { $gte: ISODate("2026-07-01T00:00:00Z") }
  })
  .sort({ createdAt: -1 })
  .limit(50);
```

Index theo ESR:

```javascript
{ tenantId: 1, status: 1, createdAt: -1 }
```

Ở đây `createdAt` vừa là sort vừa là range. Index vẫn có thể đi đúng thứ tự và scan từ boundary phù hợp.

Một ví dụ tách riêng sort và range:

```javascript
db.products
  .find({
    tenantId: "tenant-a",
    category: "keyboard",
    price: { $gte: Decimal128("40.00") }
  })
  .sort({ rating: -1, _id: 1 });
```

ESR ưu tiên tránh in-memory sort:

```javascript
{
  tenantId: 1,
  category: 1,
  rating: -1,
  _id: 1,
  price: 1
}
```

### 3.3 ERS khi range rất selective

Nếu range `price` chỉ giữ lại một phần cực nhỏ dữ liệu, đặt range trước sort có thể giảm số key phải scan:

```javascript
{
  tenantId: 1,
  category: 1,
  price: 1,
  rating: -1,
  _id: 1
}
```

Đổi lại, MongoDB có thể phải sort kết quả sau range. Chọn ESR hay ERS bằng số đo:

| Ưu tiên | Thứ tự thường thử |
|---|---|
| Tránh blocking sort, pagination ổn định | ESR |
| Range loại bỏ gần hết dữ liệu | ERS |

ESR là guideline, không phải định luật thay `explain()` và benchmark.

### 3.4 Index prefix: “có thể dùng” khác “dùng hiệu quả”

Với index:

```javascript
{ tenantId: 1, status: 1, createdAt: -1 }
```

Các prefix là:

```text
{ tenantId }
{ tenantId, status }
{ tenantId, status, createdAt }
```

Query chỉ theo `status` có thể khiến planner bỏ index hoặc phải scan rất rộng vì thiếu leading field `tenantId`. Đừng ghi nhớ máy móc rằng non-prefix “không bao giờ dùng được”; hãy hiểu rằng nó thường không tạo bounds đủ tốt.

Nếu compound index và index prefix của nó có cùng collation/property, prefix index riêng có thể dư thừa:

```text
Có: { tenantId: 1, status: 1 }
Và: { tenantId: 1 }
```

Index dài thường hỗ trợ query chỉ theo `tenantId`. Nhưng không được drop index ngắn nếu khác `unique`, `sparse`, `partial`, `collation` hoặc có query plan thực tế tốt hơn mà chưa đo.

### 3.5 Sort direction

Index:

```javascript
{ tenantId: 1, createdAt: -1, _id: -1 }
```

Khi `tenantId` equality, index hỗ trợ:

```javascript
sort({ createdAt: -1, _id: -1 }); // cùng chiều
sort({ createdAt: 1, _id: 1 });   // đảo toàn bộ chiều
```

Nó không trực tiếp hỗ trợ mixed direction sau:

```javascript
sort({ createdAt: -1, _id: 1 });
```

Hãy thêm unique tie-breaker như `_id` cho pagination ổn định và giữ direction khớp index.

---

## 4. Selectivity: index low-cardinality có thể không đáng

Giả sử 95% order có `status: "PAID"`:

```javascript
db.orders.createIndex({ status: 1 });
```

Query `status: "PAID"` vẫn phải đọc phần lớn index và fetch phần lớn collection. Planner có thể chọn collection scan vì index không giảm đủ công việc.

Selectivity cao nghĩa là predicate match ít document:

```text
email = "a@example.com"      → thường rất selective
tenantId + orderNo           → thường selective
status = "PAID"              → có thể low-selectivity
isDeleted = false            → thường low-selectivity
```

Đừng đánh giá selectivity chỉ bằng số giá trị distinct. Cần xem phân bố:

```javascript
db.orders.aggregate([
  {
    $group: {
      _id: "$status",
      count: { $count: {} }
    }
  },
  { $sort: { count: -1 } }
]);
```

Với subset nhỏ và ổn định, partial index thường tốt hơn index boolean/status toàn collection.

---

## 5. Partial, sparse và unique index

### 5.1 Partial index: chỉ index subset có ý nghĩa

```javascript
db.orders.createIndex(
  { tenantId: 1, createdAt: -1, _id: -1 },
  {
    name: "orders_open_by_tenant",
    partialFilterExpression: {
      status: { $in: ["PENDING", "PROCESSING"] }
    }
  }
);
```

Query phải chứa điều kiện bảo đảm kết quả nằm trong subset của partial filter:

```javascript
db.orders
  .find({
    tenantId: "tenant-a",
    status: "PENDING"
  })
  .sort({ createdAt: -1, _id: -1 });
```

Query chỉ có `tenantId` không thể an toàn dùng index trên vì index thiếu order đã `PAID`, `CANCELLED`...

Partial index giúp:

- giảm index size và cache pressure;
- giảm write amplification cho document ngoài subset;
- tạo unique constraint chỉ trên một phần dữ liệu;
- mô hình hóa active/archive hoặc trạng thái hot.

### 5.2 Sparse index: chỉ dựa vào field tồn tại

```javascript
db.users.createIndex(
  { legacyExternalId: 1 },
  { sparse: true }
);
```

Sparse index bỏ qua document **không có field**. Nếu field tồn tại với giá trị `null`, document vẫn có thể được index. Vì partial index diễn đạt rõ hơn và linh hoạt hơn, tài liệu MongoDB khuyến nghị ưu tiên partial index cho thiết kế mới.

### 5.3 Unique index bảo vệ invariant

```javascript
db.orders.createIndex(
  { tenantId: 1, orderNo: 1 },
  {
    unique: true,
    name: "orders_unique_number_per_tenant"
  }
);
```

Unique index là correctness boundary tại database cho mọi writer. Application validation trước đó vẫn hữu ích để trả lỗi thân thiện.

Soft delete thường cần partial unique index:

```javascript
db.accounts.createIndex(
  { tenantId: 1, normalizedEmail: 1 },
  {
    unique: true,
    partialFilterExpression: {
      active: true
    },
    name: "active_account_email_unique"
  }
);
```

Lưu ý:

- normalize email/business key trước khi ghi;
- mọi document active phải có `active: true`, được backfill và validation bảo vệ;
- collation phải khớp semantics case/accent mong muốn;
- build unique index sẽ thất bại nếu dữ liệu hiện tại hoặc concurrent write vi phạm;
- `unique` áp trên indexed key, không tự hiểu business equivalence.

---

## 6. Covered query: nhanh hơn nhưng index rộng hơn

Index:

```javascript
db.orders.createIndex({
  tenantId: 1,
  status: 1,
  createdAt: -1,
  orderNo: 1,
  customerId: 1
});
```

Query:

```javascript
db.orders.find(
  {
    tenantId: "tenant-a",
    status: "PAID"
  },
  {
    _id: 0,
    orderNo: 1,
    customerId: 1,
    createdAt: 1
  }
)
.sort({ createdAt: -1 })
.limit(50);
```

Nếu query được trả hoàn toàn từ index, execution plan không cần fetch document. Lợi ích:

- ít document read;
- ít I/O;
- latency ổn định hơn khi document lớn.

Đổi lại:

- index lớn hơn;
- write phải duy trì nhiều key hơn;
- working set index có thể không còn vừa RAM;
- MongoDB không có `INCLUDE` column tách khỏi key như một số relational database; field thêm vào vẫn là phần của index key.

Chỉ mở rộng index để cover một hot query khi số đo chứng minh lợi ích lớn hơn write/storage cost.

---

## 7. Multikey index cho array

MongoDB tự biến index thành multikey khi indexed path chứa array:

```javascript
db.products.createIndex({
  tenantId: 1,
  tags: 1
});
```

Document:

```javascript
{
  tenantId: "tenant-a",
  sku: "KB-01",
  tags: ["keyboard", "wireless", "sale"]
}
```

Mỗi phần tử array sinh index key tương ứng.

```javascript
db.products.find({
  tenantId: "tenant-a",
  tags: "wireless"
});
```

### Compound multikey constraint

Trong mỗi indexed document, tối đa một indexed field của compound index được là array:

```javascript
db.products.createIndex({
  tags: 1,
  availableRegions: 1
});
```

Nếu một document có cả `tags` và `availableRegions` là array, index build hoặc write có thể thất bại. Đây là constraint theo dữ liệu từng document, không đơn giản là “compound index chỉ được khai báo một array field”.

### `$elemMatch` và index bounds

Với array embedded document:

```javascript
db.orders.createIndex({
  "items.productId": 1,
  "items.quantity": 1
});
```

Query cần các điều kiện đúng trên cùng item:

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

`$elemMatch` vừa diễn đạt đúng semantics vừa có thể giúp MongoDB kết hợp index bounds trên cùng array path.

### Chi phí

Array dài tạo nhiều index entry:

```text
1 document × 1.000 tags ≈ rất nhiều index keys
```

Unbounded array + multikey index thường là dấu hiệu cần đổi data model bằng reference, subset hoặc bucket. Multikey index có thể cover query trong một số điều kiện, nhưng không cover khi projection trả chính array field và có các hạn chế với `$elemMatch`.

---

## 8. TTL index: retention nền, không phải scheduler

Xóa session sau thời điểm `expiresAt`:

```javascript
db.sessions.createIndex(
  { expiresAt: 1 },
  {
    expireAfterSeconds: 0,
    name: "sessions_expire_at"
  }
);
```

Document:

```javascript
{
  _id: "session-123",
  userId: "user-42",
  expiresAt: ISODate("2026-07-29T12:00:00Z")
}
```

Hoặc giữ document một khoảng sau `createdAt`:

```javascript
db.auditBuffer.createIndex(
  { createdAt: 1 },
  { expireAfterSeconds: 86_400 }
);
```

Điểm cần nhớ:

- TTL index thông thường phải là single-field index;
- `_id` không thể là TTL index;
- field phải chứa BSON Date hoặc array của Date;
- TTL monitor xóa nền, nên document có thể tồn tại quá hạn một khoảng;
- delete vẫn tiêu tốn I/O và replication;
- giảm mạnh `expireAfterSeconds` có thể tạo delete storm;
- TTL không bảo đảm callback hay business action chạy đúng thời điểm.

Nếu cần gửi thông báo, thu tiền hoặc chuyển trạng thái đúng giờ, dùng scheduler/queue có idempotency; TTL chỉ xử lý retention.

---

## 9. Wildcard index cho field động

Khi tên thuộc tính thực sự không biết trước:

```javascript
{
  sku: "LAPTOP-01",
  tenantId: "tenant-a",
  attributes: {
    color: "silver",
    ramGb: 32,
    keyboardLayout: "US"
  }
}
```

Index các subfield động:

```javascript
db.products.createIndex({
  "attributes.$**": 1
});
```

Từ MongoDB 7.0, compound wildcard index có thể kết hợp field ổn định với một wildcard term:

```javascript
db.products.createIndex({
  tenantId: 1,
  "attributes.$**": 1
});
```

Hoặc giới hạn field được index:

```javascript
db.products.createIndex(
  { "$**": 1 },
  {
    wildcardProjection: {
      "attributes.color": 1,
      "attributes.ramGb": 1
    }
  }
);
```

Wildcard index là fallback cho schema field động, không thay targeted index:

- wildcard term chỉ hỗ trợ một query predicate tại một thời điểm;
- khả năng sort/covered query có điều kiện chặt;
- không hỗ trợ `unique`, TTL, text, hashed hoặc geospatial property;
- `_id` bị loại mặc định;
- index có thể lớn nếu wildcard scope quá rộng;
- exact equality trên cả object/array không được hỗ trợ như scalar field.

Nếu một nhóm field trở thành hot và ổn định, tạo targeted compound index hoặc chuẩn hóa schema cho query đó.

---

## 10. Text, geospatial, hashed và clustered index

### 10.1 Text index và MongoDB Search

Text index cổ điển hỗ trợ `$text`:

```javascript
db.articles.createIndex(
  {
    title: "text",
    content: "text"
  },
  {
    weights: {
      title: 10,
      content: 1
    },
    default_language: "english",
    name: "articles_text"
  }
);

db.articles.find(
  {
    $text: {
      $search: "\"index design\" -legacy"
    }
  },
  {
    title: 1,
    score: { $meta: "textScore" }
  }
)
.sort({
  score: { $meta: "textScore" }
});
```

Một collection chỉ có một text index, dù index đó có thể chứa nhiều field. Text index:

- luôn sparse theo semantics riêng;
- không cover query;
- có write/RAM cost lớn theo số token;
- có hạn chế với compound key, sort và `hint()`.

MongoDB 8.2 khuyến nghị **MongoDB Search**/`$search` cho full-text search giàu tính năng và MongoDB Vector Search cho semantic/vector use case. Đừng mặc định thêm một hệ thống Elasticsearch nếu MongoDB Search đáp ứng yêu cầu; cũng đừng chọn text index chỉ vì nó dễ tạo mà chưa so feature, deployment và SLA.

### 10.2 `2dsphere` cho GeoJSON trên bề mặt cầu

```javascript
db.places.createIndex({
  location: "2dsphere"
});

db.places.insertOne({
  name: "Saigon Centre",
  location: {
    type: "Point",
    coordinates: [106.7009, 10.7736]
  }
});
```

Thứ tự GeoJSON là `[longitude, latitude]`, không phải `[latitude, longitude]`.

```javascript
db.places.find({
  location: {
    $near: {
      $geometry: {
        type: "Point",
        coordinates: [106.7009, 10.7736]
      },
      $maxDistance: 1_000
    }
  }
});
```

`$near`, `$nearSphere` và `$geoNear` cần geospatial index. Dữ liệu sai geometry có thể làm index build/write thất bại; geospatial index không cover query và không làm shard key.

### 10.3 Hashed index

```javascript
db.events.createIndex({
  tenantId: "hashed"
});
```

Hashed index lưu hash của giá trị, chủ yếu phục vụ hashed sharding và equality lookup:

- phân phối key tuần tự tốt hơn ranged shard key;
- không giữ natural order nên không phục vụ range/sort trên giá trị gốc;
- không thể là multikey;
- không dùng `unique`;
- cần chú ý cách số floating-point lớn được hash.

Thiết kế shard key được trình bày sâu hơn trong [Sharding](../operations/sharding.md).

### 10.4 Clustered collection

Collection thông thường lưu document tách khỏi secondary index. Clustered collection lưu document theo clustered index:

```javascript
db.createCollection("eventArchive", {
  clusteredIndex: {
    key: { _id: 1 },
    unique: true,
    name: "event_archive_clustered"
  }
});
```

Trong MongoDB 8.2:

- clustered index key phải là `{ _id: 1 }`;
- chỉ khai báo khi tạo collection;
- chỉ có một clustered index;
- vẫn có thể tạo secondary index;
- không thể hide clustered index;
- muốn đổi collection thường ↔ clustered phải migrate sang collection khác.

Clustered collection hữu ích cho range trên clustered key và retention/time-oriented workload, nhưng không phải lựa chọn mặc định cho mọi collection.

---

## 11. Collation và case-insensitive index

Muốn email không phân biệt hoa/thường:

```javascript
db.users.createIndex(
  { tenantId: 1, email: 1 },
  {
    unique: true,
    collation: {
      locale: "en",
      strength: 2
    },
    name: "users_email_ci"
  }
);
```

Query phải dùng collation tương thích để dùng index:

```javascript
db.users.find({
  tenantId: "tenant-a",
  email: "Alice@example.com"
})
.collation({
  locale: "en",
  strength: 2
});
```

Collation ảnh hưởng so sánh và sort theo locale/case/diacritic. Với identifier như email, một `normalizedEmail` được normalize nhất quán trong application thường dễ kiểm soát hơn collation phức tạp—nhưng normalization phải có contract rõ và backfill dữ liệu cũ.

---

## 12. `explain()`: đọc công việc, không chỉ đọc tên stage

```javascript
db.orders
  .find({
    tenantId: "tenant-a",
    status: "PAID"
  })
  .sort({
    createdAt: -1,
    _id: -1
  })
  .limit(50)
  .explain("executionStats");
```

Ba verbosity:

| Chế độ | Dùng khi |
|---|---|
| `queryPlanner` | Xem winning/rejected plan mà không cần execution metrics |
| `executionStats` | Thực thi winning plan và đo keys/docs/rows |
| `allPlansExecution` | Xem thêm trial metrics của candidate plans |

Các metric quan trọng:

| Metric/dấu hiệu | Ý nghĩa thực hành |
|---|---|
| `nReturned` | Số document trả cho consumer |
| `totalKeysExamined` | Số index key đã scan |
| `totalDocsExamined` | Số document đã fetch/scan |
| `IXSCAN` hoặc index name | Có index access path |
| `COLLSCAN` | Scan collection |
| `FETCH` | Phải đọc document sau index |
| `SORT`/blocking sort | Index không cung cấp đầy đủ sort order |
| bounds | Đoạn index thực sự được scan |
| rejected plans | Các plan đã được cân nhắc nhưng không thắng |

Stage name có thể khác theo classic engine, slot-based engine và fast path của phiên bản. Đừng viết alert cứng rằng chỉ `IXSCAN` mới tốt. Hãy hỏi:

```text
keys examined / returned có hợp lý với query không?
docs examined / returned có hợp lý với projection/filter không?
sort có dùng index hay spill?
latency có ổn với dữ liệu và concurrency đại diện?
```

`totalDocsExamined` gần `nReturned` thường tốt, nhưng không phải invariant. Range query có thể cần scan nhiều key; query trả 0 kết quả vẫn có overhead; `$or`, multikey và shard routing làm plan phức tạp hơn.

### Covered query trong explain

Khi `totalDocsExamined: 0` và plan chỉ cần index/projection, query thường đã covered. Xác nhận bằng plan thực tế thay vì đoán từ projection.

### `COLLSCAN` không luôn là bug

Collection nhỏ, query trả phần lớn dữ liệu hoặc maintenance scan có thể chạy tốt hơn bằng collection scan. Vấn đề là scan ngoài dự kiến trên collection lớn/hot path.

### `hint()` chỉ là công cụ kiểm thử

```javascript
db.orders
  .find({
    tenantId: "tenant-a",
    status: "PAID"
  })
  .hint("orders_tenant_status_createdAt")
  .explain("executionStats");
```

Dùng `hint()` để so candidate index trong môi trường đo. Ép index trong application có thể giữ một plan xấu khi data distribution hoặc phiên bản thay đổi.

---

## 13. Index intersection: có thể xảy ra, không nên đặt cược

Giả sử có:

```javascript
{ tenantId: 1 }
{ status: 1 }
```

Query:

```javascript
{ tenantId: "tenant-a", status: "PAID" }
```

Planner có thể cân nhắc kết hợp nhiều index trong một số trường hợp. Nhưng compound index:

```javascript
{ tenantId: 1, status: 1 }
```

thường cho bounds/order/coverage dự đoán được hơn với hot query shape.

Không nên:

- tạo single-field index cho mọi field rồi giả định planner sẽ ghép tối ưu;
- phụ thuộc stage name intersection cụ thể;
- giữ hàng loạt index chỉ vì một lần explain từng chọn chúng.

Đo candidate compound index và toàn bộ write/storage cost.

---

## 14. Index build trong production

```javascript
db.orders.createIndex(
  {
    tenantId: 1,
    status: 1,
    createdAt: -1,
    _id: -1
  },
  {
    name: "orders_tenant_status_createdAt_id"
  }
);
```

MongoDB hiện dùng optimized index build. Option `background` bị bỏ qua; không cần thêm `background: true`.

Index build:

- giữ exclusive collection lock ngắn ở đầu/cuối;
- cho phép phần lớn read/write xen kẽ trong giai đoạn build;
- tiêu tốn CPU, RAM, disk I/O và temporary disk;
- theo dõi concurrent writes để đưa vào index;
- kiểm tra constraint như duplicate key trước khi commit;
- build đồng thời trên data-bearing replica set members;
- dùng commit quorum trước khi primary đánh dấu index sẵn sàng.

### Trước khi build

- đo collection/index size và free disk trên mọi member;
- tìm duplicate/invalid geometry nếu index có constraint;
- thử trên dữ liệu gần production;
- chọn maintenance window nếu workload nhạy cảm;
- xác định rollback nếu latency/replication lag tăng;
- theo dõi cả primary lẫn secondary, không chỉ client command.

### Theo dõi

```javascript
db.currentOp({
  "command.createIndexes": {
    $exists: true
  }
});
```

Không dùng `killOp` tùy tiện để dừng replicated index build. Theo tài liệu vận hành, `dropIndex()`/`dropIndexes()` là cơ chế dừng build được hỗ trợ cho trường hợp tương ứng.

---

## 15. Hide trước khi drop

```javascript
db.orders.hideIndex(
  "orders_old_index"
);
```

Hidden index:

- không được query planner dùng;
- vẫn được duy trì trên mọi write;
- vẫn chiếm disk/RAM;
- unique constraint vẫn có hiệu lực;
- TTL index vẫn tiếp tục xóa document;
- có thể unhide nhanh nếu workload xấu đi.

Quy trình:

```text
1. Ghi nhận index definition, size, usage và query shapes
2. Hide index
3. Quan sát đủ chu kỳ workload: peak, batch, report, cuối tháng
4. Nếu có regression → unhide
5. Nếu an toàn → drop trong change window
```

```javascript
db.orders.unhideIndex(
  "orders_old_index"
);

db.orders.dropIndex(
  "orders_old_index"
);
```

Không thể hide `_id` index hoặc clustered index. Drop là thay đổi khó hoàn tác nhanh vì rebuild trên collection lớn có thể đắt.

---

## 16. Theo dõi index usage đúng cách

### Liệt kê definition và size

```javascript
db.orders.getIndexes();

db.orders.stats({
  indexDetails: true
});
```

### `$indexStats`

```javascript
db.orders.aggregate([
  { $indexStats: {} },
  {
    $project: {
      name: 1,
      key: 1,
      host: 1,
      accesses: 1
    }
  },
  {
    $sort: {
      "accesses.ops": 1
    }
  }
]);
```

Không kết luận “unused” chỉ vì `accesses.ops` thấp:

- số liệu chỉ thuộc node đang chạy stage;
- reset sau `mongod` restart hoặc drop/recreate;
- hide/unhide cũng reset usage stats;
- rare but critical query có thể chỉ chạy cuối tháng;
- TTL/internal operations không phản ánh như user query;
- một index có thể tồn tại để enforce unique constraint.

Kết hợp:

- slow query/profiler hoặc Query Profiler;
- application telemetry và query comments;
- Atlas Performance Advisor nếu dùng Atlas;
- `$queryStats`/query insights phù hợp deployment;
- `explain()` với data distribution đại diện;
- lịch business của batch/report.

---

## 17. Java driver: index như code có version

```java
import com.mongodb.client.model.IndexOptions;
import com.mongodb.client.model.Indexes;

String indexName = orders.createIndex(
    Indexes.compoundIndex(
        Indexes.ascending("tenantId"),
        Indexes.ascending("status"),
        Indexes.descending("createdAt"),
        Indexes.descending("_id")
    ),
    new IndexOptions()
        .name("orders_tenant_status_createdAt_id")
);
```

Partial unique index:

```java
import static com.mongodb.client.model.Filters.eq;
import static com.mongodb.client.model.Indexes.ascending;
import static com.mongodb.client.model.Indexes.compoundIndex;

orders.createIndex(
    compoundIndex(
        ascending("tenantId"),
        ascending("orderNo")
    ),
    new IndexOptions()
        .name("active_order_number_unique")
        .unique(true)
        .partialFilterExpression(
            eq("active", true)
        )
);
```

Trong dự án thực tế:

- khai báo index trong migration/versioned infrastructure;
- đặt tên ổn định;
- tránh để nhiều application instance cùng tự build index nặng lúc startup;
- so sánh desired index với `getIndexes()`;
- deploy index trước code dùng query mới;
- chỉ drop index cũ sau khi code cũ đã rút và quan sát đủ lâu.

---

## 18. So sánh nhanh với relational indexing

| Khái niệm | MongoDB | Relational database thường gặp |
|---|---|---|
| Secondary index | B-tree riêng trên field/path | Non-clustered/secondary index |
| Covering | Mọi field cần nằm trong index key | Có hệ hỗ trợ key + included columns |
| Filtered subset | Partial index | Filtered/partial index |
| Array | Multikey index tự động | Thường cần bảng con/junction table |
| Dynamic fields | Wildcard index | JSON/expression/specialized index tùy hệ |
| Physical order | Clustered collection `{_id: 1}` | Clustered/organized table tùy hệ |
| Full text | Text index hoặc MongoDB Search | Full-text engine/index riêng |
| Geo | `2dsphere`, `2d` | Spatial index |

Không chuyển nguyên xi quy tắc SQL sang MongoDB. Document shape, embedded array, query predicate và absence/null semantics làm index behavior khác đáng kể.

---

## 19. Anti-pattern thường gặp

| Anti-pattern | Vấn đề | Hướng sửa |
|---|---|---|
| Index mọi field | Write/storage/cache cost tăng | Xuất phát từ query shape và SLA |
| Single-field index cho từng predicate | Hy vọng intersection tự tối ưu | Đo compound index theo hot query |
| Chỉ nhìn `IXSCAN` | Index scan vẫn có thể rất rộng | Đọc keys/docs examined, bounds, sort |
| Chỉ nhìn tỷ lệ 1:1 | Bỏ qua range, multikey, zero-result | Đánh giá công việc theo semantics |
| `status`/boolean index toàn collection | Selectivity thấp | Compound hoặc partial index |
| Đặt range trước sort theo thói quen | Mất index-provided sort | So ESR với ERS bằng benchmark |
| Thêm field để cover mọi query | Index phình, write chậm | Chỉ cover hot path có lợi ích đo được |
| Sparse để bỏ cả `null` | Sparse vẫn index field tồn tại với null | Partial filter diễn đạt rõ |
| Wildcard thay schema design | Index lớn, query support hạn chế | Targeted index/chuẩn hóa hot fields |
| TTL như scheduler chính xác | Xóa nền có delay, không callback | Scheduler/queue + idempotency |
| `background: true` | Option hiện bị bỏ qua | Lập kế hoạch optimized index build |
| Drop index ngay khi stats bằng 0 | Stats theo node/reset/rare workload | Hide, quan sát đủ chu kỳ, rồi drop |
| Dùng `hint()` vĩnh viễn | Data/planner đổi làm plan bị ép xấu | Dùng để thử nghiệm có kiểm soát |

---

## 20. Checklist thiết kế và vận hành

### Trước khi tạo

- [ ] Query shape gồm equality, sort, range và projection nào?
- [ ] Cardinality và data distribution gần production ra sao?
- [ ] ESR hay ERS phù hợp hơn với SLA?
- [ ] Sort có unique tie-breaker?
- [ ] Partial index có giảm đáng kể subset không?
- [ ] Array có làm index thành multikey hoặc sinh quá nhiều key?
- [ ] Index có trùng prefix với index hiện tại?
- [ ] Unique/collation có đúng business semantics?
- [ ] Covered query có đáng đổi lấy index rộng hơn?

### Trước khi build production

- [ ] Đã kiểm tra duplicate/invalid data?
- [ ] Mọi replica set member có đủ disk?
- [ ] Đã đo CPU, I/O, replication lag và backup window?
- [ ] Có maintenance/rollback/monitoring plan?
- [ ] Index được deploy trước application query mới?

### Khi review hoặc xóa

- [ ] Đã xem `$indexStats` trên đúng node và đủ thời gian?
- [ ] Đã kiểm tra rare query, batch và constraint?
- [ ] Đã hide và quan sát peak workload?
- [ ] Đã lưu definition để khôi phục?
- [ ] Đã xác nhận không phải shard-key/unique/TTL dependency?

---

## 21. Tóm tắt

- Thiết kế index từ **query shape + data distribution + SLA**, không từ danh sách field.
- Equality đứng trước; chọn ESR hay ERS tùy ưu tiên sort và độ selective của range.
- Compound prefix có thể tái sử dụng, nhưng “planner dùng index” chưa chắc “index hiệu quả”.
- Partial index thường rõ và linh hoạt hơn sparse index.
- Multikey, TTL, wildcard, text, geo, hashed và clustered index có constraint riêng.
- Đọc `explain()` qua lượng công việc thực tế, không chỉ stage name.
- Index build là production change tiêu tốn tài nguyên và có commit quorum.
- Hide trước khi drop; usage stats bằng 0 không đủ chứng minh index vô dụng.

## 22. Đọc tiếp

- [Transactions](transactions.md) – invariant vượt quá một document, read/write concern và retry.
- [Schema Design Patterns](../performance/schema_design.md) – thiết kế document để giảm join và index bloat.
- [Replication](../operations/replication.md) – ảnh hưởng của index/write lên replica set.
- [Sharding](../operations/sharding.md) – shard key và index routing.
- [MongoDB Glossary](../glossary.md) – tra cứu thuật ngữ.

## Tài liệu chính thức

- [MongoDB Indexes](https://www.mongodb.com/docs/v8.2/indexes/)
- [Index Types](https://www.mongodb.com/docs/v8.2/core/indexes/index-types/)
- [ESR Guideline](https://www.mongodb.com/docs/v8.2/tutorial/equality-sort-range-guideline/)
- [Partial Indexes](https://www.mongodb.com/docs/v8.2/core/index-partial/)
- [Multikey Indexes](https://www.mongodb.com/docs/v8.2/core/indexes/index-types/index-multikey/)
- [Wildcard Indexes](https://www.mongodb.com/docs/v8.2/core/indexes/index-types/index-wildcard/)
- [TTL Indexes](https://www.mongodb.com/docs/v8.2/core/index-ttl/)
- [Hidden Indexes](https://www.mongodb.com/docs/v8.2/core/index-hidden/)
- [Index Builds on Populated Collections](https://www.mongodb.com/docs/v8.2/core/index-creation/)
- [`explain` Results](https://www.mongodb.com/docs/v8.2/reference/explain-results/)

---

*Cập nhật lần cuối: 2026-07-29 – MongoDB 8.2*
