---
title: "MongoDB Data Model & BSON"
topic: mongodb
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 10
---
# MongoDB Data Model & BSON

> Thuật ngữ: [Glossary](../glossary.md).

> MongoDB có **flexible schema**, không phải “không có schema”. Schema vẫn tồn tại trong document, application, index, validator và kỳ vọng nghiệp vụ. Nội dung được chuẩn hóa theo MongoDB 8.2.

## 1. Mental model

MongoDB tổ chức dữ liệu theo:

```text
Deployment
└── Database
    └── Collection
        └── BSON Document
            ├── field: scalar
            ├── field: embedded document
            └── field: array
```

Ví dụ một document:

```javascript
{
  _id: ObjectId("687000000000000000000042"),
  schemaVersion: 2,
  customerId: ObjectId("687000000000000000000001"),
  status: "PAID",
  total: NumberDecimal("125000.00"),
  currency: "VND",
  shippingAddress: {
    city: "Ho Chi Minh",
    district: "1"
  },
  items: [
    {
      productId: ObjectId("687000000000000000000101"),
      nameSnapshot: "Bàn phím cơ",
      quantity: NumberInt(1),
      unitPrice: NumberDecimal("125000.00")
    }
  ],
  createdAt: ISODate("2026-07-29T08:00:00Z")
}
```

Document không chỉ là một row JSON:

- BSON có type cụ thể như Int32, Int64, Decimal128, Date, Binary và ObjectId;
- embedded document/array tạo atomic boundary tự nhiên;
- một document có thể lưu aggregate mà application thường đọc/ghi cùng nhau;
- index và shard key phụ thuộc trực tiếp vào shape của document.

### 1.1 Flexible schema nghĩa là gì?

Trong cùng collection, document có thể khác field hoặc type. Điều đó hữu ích cho:

- rollout schema theo từng bước;
- polymorphic data;
- optional field;
- dữ liệu từ nhiều nguồn.

Nhưng production vẫn cần quy ước:

```text
orders.status luôn là string enum
orders.total luôn là Decimal128
orders.createdAt luôn là BSON Date
orders.schemaVersion luôn là integer
```

Nếu cùng field lúc là string, lúc là number, query, sort, index và serialization đều khó dự đoán.

---

## 2. Thiết kế từ workload, không từ ERD

MongoDB schema nên bắt đầu từ cách application dùng dữ liệu.

### 2.1 Lập workload table

| Use case | Read/Write | Field cần trả/đổi | Tần suất | SLO | Cardinality/growth |
|---|---|---|---|---|---|
| Xem order detail | Read | order, items, address | Rất cao | p99 < 50 ms | Items bounded |
| Đổi trạng thái order | Write | status, version | Cao | Atomic | Một document |
| Liệt kê order của customer | Read | summary, createdAt | Cao | Page 20 | Tăng dài hạn |
| Thêm audit event | Write | event | Cao | Append | Không bounded |

Từ bảng này mới quyết định:

- field nào embed vì luôn đọc cùng;
- quan hệ nào reference vì tăng không giới hạn;
- dữ liệu nào duplicate làm snapshot;
- query nào cần index;
- operation nào phải atomic.

### 2.2 Ba câu hỏi quan trọng

1. **Đọc cùng nhau không?** Dữ liệu luôn được trả cùng thường là ứng viên embed.
2. **Thay đổi cùng nhau không?** Dữ liệu cần cập nhật atomic thường nên cùng document.
3. **Có tăng không giới hạn không?** Collection con không bounded thường phải tách/reference/bucket.

Không dùng luật cứng kiểu “dưới 100 phần tử thì embed”. Giới hạn phải dựa trên kích thước, tốc độ tăng, write contention, index fan-out và SLO.

---

## 3. BSON không phải JSON

BSON là binary serialization format có type phong phú hơn JSON.

### 3.1 Các type thường dùng

| BSON type | `mongosh` minh họa | Dùng khi | Bẫy thường gặp |
|---|---|---|---|
| String | `"PAID"` | Text/enum | Số lưu dạng string sort sai kiểu số |
| Int32 | `NumberInt(42)` | Counter nhỏ | Có giới hạn 32-bit |
| Int64 | `NumberLong("9007199254740993")` | ID/counter lớn | JavaScript Number không biểu diễn chính xác mọi Int64 |
| Double | `19.99` | Đo lường chấp nhận floating error | Không phù hợp tiền cần exact decimal |
| Decimal128 | `NumberDecimal("19.99")` | Tiền, decimal chính xác | Driver phải map đúng `BigDecimal`/Decimal128 |
| Boolean | `true` | Cờ nhị phân | Nhiều boolean có thể che state machine |
| Date | `ISODate("2026-07-29T08:00:00Z")` | Instant theo UTC | Không giữ timezone gốc |
| Timestamp | `Timestamp(t, i)` | Nội bộ replication/change ordering | Không thay BSON Date cho business time |
| ObjectId | `ObjectId("...")` | `_id` mặc định | Chỉ xấp xỉ theo creation time |
| Binary/UUID | `UUID("...")` | UUID, byte payload nhỏ | Phải thống nhất UUID representation |
| Array | `["a", "b"]` | Danh sách bounded/ordered | Array tăng vô hạn làm document/index phình |
| Embedded document | `{city: "HCM"}` | Aggregate/sub-object | Nesting quá sâu khó query/evolve |
| Null | `null` | Có field nhưng chưa có value | Khác semantic với field không tồn tại |

`mongosh` syntax như `ISODate`, `NumberLong` và `ObjectId` là helper, không phải JSON chuẩn.

### 3.2 Date và timezone

BSON Date lưu số millisecond từ Unix epoch UTC. Nó không lưu:

- timezone ban đầu;
- locale;
- format hiển thị;
- ý nghĩa “ngày địa phương”.

Model đúng tùy nghiệp vụ:

```javascript
{
  occurredAt: ISODate("2026-07-29T08:00:00Z"),
  sourceTimeZone: "Asia/Bangkok"
}
```

Với ngày không phải instant, như ngày sinh hoặc ngày chốt sổ địa phương, cần contract rõ thay vì tự động đổi qua UTC rồi làm lệch ngày.

### 3.3 Tiền tệ

```javascript
{
  amount: NumberDecimal("125000.00"),
  currency: "VND"
}
```

Không chỉ lưu `double` nếu nghiệp vụ cần phép tính decimal chính xác. Luôn giữ currency và quy tắc scale/rounding ở schema/application contract.

### 3.4 `null`, missing và field rỗng

Ba trạng thái có thể khác nhau:

```javascript
{ middleName: null }  // field tồn tại nhưng chưa/không có giá trị
{}                    // field không tồn tại
{ middleName: "" }    // string rỗng
```

Query `{middleName: null}` có semantics liên quan cả `null` và missing. Khi chỉ cần BSON Null, kiểm tra type:

```javascript
db.customers.find({
  middleName: {$type: 10}
})
```

Contract phải nói rõ trạng thái nào được phép; đừng để từng service tự diễn giải.

### 3.5 Extended JSON

Khi truyền BSON qua JSON-only system, Extended JSON giữ type:

```json
{
  "_id": {"$oid": "687000000000000000000042"},
  "total": {"$numberDecimal": "125000.00"},
  "createdAt": {"$date": "2026-07-29T08:00:00Z"}
}
```

Canonical mode ưu tiên bảo toàn type; relaxed mode dễ đọc hơn. Producer/consumer phải thống nhất mode và driver mapping.

---

## 4. `_id` và ObjectId

Mỗi document trong standard collection cần `_id` duy nhất. Nếu client không cung cấp, driver thường tạo ObjectId.

### 4.1 Cấu trúc ObjectId

ObjectId dài 12 byte:

```text
4 byte timestamp (seconds)
5 byte random value theo process/machine
3 byte counter khởi tạo ngẫu nhiên
```

```javascript
const id = ObjectId()
id.getTimestamp()
```

ObjectId:

- có thể tạo ở client mà không round trip;
- thường phân bố gần theo thời gian tạo;
- chứa timestamp độ phân giải một giây.

ObjectId **không monotonic tuyệt đối**:

- nhiều ID trong cùng giây không bảo đảm thứ tự creation toàn cục;
- ID do các client có clock khác nhau tạo;
- retry/import có thể làm thứ tự càng khác.

Không dùng sort `_id` thay cho business ordering quan trọng. Lưu `createdAt` và tie-breaker rõ ràng:

```javascript
db.orders.find().sort({createdAt: -1, _id: -1})
```

### 4.2 Custom `_id`

Có thể dùng UUID, string hoặc natural key, nhưng cân nhắc:

- kích thước index;
- locality và insert pattern;
- khả năng đổi business key;
- driver serialization;
- shard key/routing;
- dữ liệu lộ ra ngoài API.

`_id` immutable. Business identifier có khả năng đổi không nên làm `_id` chỉ để “tiện”.

---

## 5. Document boundary và giới hạn

### 5.1 Giới hạn kỹ thuật

- BSON document tối đa **16 MiB**;
- nesting tối đa **100 level**;
- standard collection bắt buộc `_id` duy nhất;
- BSON document có field order, nhưng application không nên dựa vào order vì query/projection có thể reorder.

16 MiB là trần lỗi, không phải target thiết kế. Document vài MiB đã có thể:

- tăng network/serialization latency;
- làm working set khó vừa RAM;
- làm update copy nhiều byte;
- làm index/replication/backup nặng hơn.

`GridFS` chia file lớn thành chunk khi cần lưu trong MongoDB. Với ảnh/video/object lớn, cũng phải so sánh object storage về cost, CDN, lifecycle và backup.

### 5.2 Atomicity theo document

Một write vào một document là atomic, kể cả cập nhật nhiều embedded field:

```javascript
db.inventory.updateOne(
  {
    _id: ObjectId("687000000000000000000042"),
    available: {$gte: 2}
  },
  {
    $inc: {available: -2, reserved: 2},
    $set: {updatedAt: new Date()}
  }
)
```

Filter và update chạy như một atomic operation trên document. Đây thường tốt hơn:

```text
GET document
modify trong application
replace document
```

vì read-modify-replace dễ ghi đè concurrent update.

Multi-document transaction tồn tại, nhưng không nên dùng transaction để bù cho schema không khớp aggregate boundary.

---

## 6. Embedding hay referencing?

### 6.1 Embedding

```javascript
{
  _id: ObjectId("687000000000000000000042"),
  customerId: ObjectId("687000000000000000000001"),
  shippingAddressSnapshot: {
    receiver: "An",
    city: "Ho Chi Minh",
    district: "1"
  },
  items: [
    {
      productId: ObjectId("687000000000000000000101"),
      nameSnapshot: "Bàn phím cơ",
      quantity: 1,
      unitPrice: NumberDecimal("125000.00")
    }
  ]
}
```

Order lưu snapshot tên/giá/address vì lịch sử order không nên đổi khi catalog/customer profile thay đổi.

Ưu điểm:

- đọc aggregate bằng một query;
- single-document atomic update;
- ít round trip/`$lookup`;
- dữ liệu đặt gần nhau.

Chi phí:

- duplication;
- update fan-out nếu bản sao phải luôn mới;
- document/array growth;
- write contention vào cùng document.

### 6.2 Referencing

```javascript
// orders
{
  _id: ObjectId("687000000000000000000042"),
  customerId: ObjectId("687000000000000000000001")
}

// customers
{
  _id: ObjectId("687000000000000000000001"),
  name: "An"
}
```

Ưu tiên reference khi:

- child tăng không bounded;
- entity có lifecycle/quyền truy cập riêng;
- many-to-many phức tạp;
- duplicated field đổi thường xuyên;
- hai phía thường được đọc độc lập;
- document sẽ bloated nếu embed.

Đổi lại application cần query khác hoặc `$lookup`, và atomicity có thể chuyển sang transaction/protocol ứng dụng.

### 6.3 Decision matrix

| Câu hỏi | Nghiêng về embed | Nghiêng về reference |
|---|---|---|
| Luôn đọc cùng nhau? | Có | Không |
| Cần update atomic cùng nhau? | Có | Không |
| Child cardinality bounded? | Có | Không |
| Child có lifecycle riêng? | Không | Có |
| Dữ liệu duplicate đổi thường xuyên? | Không | Có |
| Quan hệ many-to-many? | Hiếm | Thường |
| Parent có nguy cơ hot/write contention? | Thấp | Cao |

Không phải chọn một phía tuyệt đối. Pattern phổ biến là **subset**:

```javascript
// products: chỉ embed 3 review gần nhất để render trang đầu
{
  _id: ObjectId("..."),
  name: "Bàn phím cơ",
  reviewSummary: {count: 12540, average: 4.7},
  recentReviews: [
    {reviewId: ObjectId("..."), rating: 5, excerpt: "Tốt"},
    {reviewId: ObjectId("..."), rating: 4, excerpt: "Ổn"}
  ]
}

// reviews: toàn bộ lịch sử, mỗi review là document riêng
```

---

## 7. Tránh unbounded array và bloated document

### 7.1 Unbounded array

Không embed mọi event/comment/log:

```javascript
// Anti-pattern
{
  _id: "order-42",
  events: [
    // tăng mãi...
  ]
}
```

Tác hại đến trước giới hạn 16 MiB:

- update document ngày càng tốn;
- multikey index có nhiều entry;
- response/projection dễ quá lớn;
- một parent trở thành write hotspot;
- migration/replication nặng.

Cách thay:

- child collection với `parentId`;
- subset gần nhất + full collection;
- bucket theo time/count;
- Stream/event system chuyên dụng nếu cần delivery/replay.

### 7.2 Bloated document

Nếu list page chỉ cần `_id`, `name`, `thumbnail`, không nên luôn kéo description lớn, raw history và binary.

Giải pháp tùy access pattern:

- projection;
- tách cold/large field sang collection khác;
- subset/extended reference;
- object storage cho asset;
- archive dữ liệu cũ.

Projection giảm bytes trả về nhưng document lớn vẫn ảnh hưởng working set/storage. Phải sửa model nếu bloating là cấu trúc.

---

## 8. Schema validation

Flexible schema và validator bổ sung cho nhau.

### 8.1 Tạo collection có validator

```javascript
db.createCollection("orders", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "_id",
        "schemaVersion",
        "customerId",
        "status",
        "total",
        "currency",
        "createdAt"
      ],
      properties: {
        _id: {
          bsonType: "objectId"
        },
        schemaVersion: {
          bsonType: "int",
          minimum: 1
        },
        customerId: {
          bsonType: "objectId"
        },
        status: {
          enum: ["PENDING", "PAID", "SHIPPED", "CANCELLED"]
        },
        total: {
          bsonType: "decimal",
          minimum: NumberDecimal("0")
        },
        currency: {
          bsonType: "string",
          pattern: "^[A-Z]{3}$"
        },
        createdAt: {
          bsonType: "date"
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
})
```

MongoDB dùng `$jsonSchema` với BSON-aware keyword như `bsonType`; không giả định mọi tính năng của một JSON Schema dialect bên ngoài đều giống hệt.

### 8.2 Level và action

| Setting | Ý nghĩa |
|---|---|
| `validationLevel: "strict"` | Kiểm tra mọi insert và update |
| `validationLevel: "moderate"` | Không buộc update của document cũ vốn đã invalid phải hợp lệ ngay |
| `validationAction: "error"` | Reject write tạo document invalid |
| `validationAction: "warn"` | Cho write đi qua nhưng ghi warning |

Validator không tự sửa dữ liệu cũ. Rollout an toàn:

1. inventory type/shape hiện có;
2. thêm validator ở `warn` hoặc mức phù hợp;
3. đo vi phạm theo producer;
4. sửa writer và backfill dữ liệu;
5. chuyển sang `error`;
6. test rollback/compatibility.

Application validation vẫn cần cho message thân thiện và business rule; database validation là hàng rào cuối cho mọi writer.

### 8.3 Thay validator

```javascript
db.runCommand({
  collMod: "orders",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "schemaVersion", "status"],
      properties: {
        _id: {bsonType: "objectId"},
        schemaVersion: {bsonType: "int"},
        status: {
          enum: ["PENDING", "PAID", "SHIPPED", "CANCELLED", "REFUNDED"]
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
})
```

Schema change là deployment change: validator, indexes, readers và writers phải rollout theo thứ tự tương thích.

---

## 9. Array và concurrent update

Ưu tiên atomic update operator:

```javascript
db.orders.updateOne(
  {
    _id: ObjectId("687000000000000000000042"),
    "items.productId": {$ne: ObjectId("687000000000000000000101")}
  },
  {
    $push: {
      items: {
        productId: ObjectId("687000000000000000000101"),
        quantity: 1
      }
    },
    $inc: {itemCount: 1}
  }
)
```

Update phần tử khớp:

```javascript
db.orders.updateOne(
  {
    _id: ObjectId("687000000000000000000042"),
    "items.productId": ObjectId("687000000000000000000101")
  },
  {
    $inc: {"items.$.quantity": 1}
  }
)
```

Điểm cần kiểm soát:

- array có maximum business size;
- index trên array trở thành multikey index;
- compound multikey index có constraint riêng;
- query phải dùng đúng `$elemMatch` khi nhiều condition cần cùng một element;
- retry/update phải idempotent hoặc có version.

---

## 10. Schema evolution

### 10.1 Schema Versioning Pattern

```javascript
// Version 1
{
  _id: ObjectId("..."),
  schemaVersion: 1,
  homePhone: "028...",
  workPhone: "028..."
}

// Version 2
{
  _id: ObjectId("..."),
  schemaVersion: 2,
  contacts: [
    {type: "mobile", value: "090..."},
    {type: "email", value: "an@example.com"}
  ]
}
```

Rollout expand-and-contract:

```text
1. Reader hiểu v1 và v2.
2. Writer bắt đầu ghi v2.
3. Backfill v1 -> v2 theo batch có checkpoint.
4. Xây/đổi index và validator tương thích.
5. Đo còn bao nhiêu v1.
6. Bỏ code v1 khi không còn dependency.
```

Không backfill toàn collection trong một lệnh lớn mà không đo replication lag, oplog window, lock/yield, disk và rollback.

### 10.2 Schema version khác document history

- **Schema version**: shape dữ liệu thuộc phiên bản nào.
- **Document version/history**: lưu các trạng thái nghiệp vụ cũ.
- **Optimistic version**: counter để phát hiện concurrent update.

Không dùng một field `version` mơ hồ cho cả ba.

### 10.3 Tolerant reader có giới hạn

Reader nên:

- chấp nhận optional field mới;
- default có chủ đích;
- reject type sai thay vì âm thầm coerce;
- metric schema version/unknown field;
- không giữ compatibility vô hạn.

---

## 11. Các schema pattern cần biết

| Pattern | Ý tưởng | Khi hữu ích |
|---|---|---|
| Subset | Embed phần hot/nhỏ, reference phần đầy đủ | Product + review gần nhất |
| Extended Reference | Duplicate vài field từ entity được reference | Order lưu customer name snapshot |
| Bucket | Gom event theo time/count thành document bounded | Measurements, logs |
| Outlier | Tách trường hợp cực lớn khỏi model thông thường | Một số customer có hàng triệu relationship |
| Computed | Lưu kết quả aggregate đã tính | Rating average, order count |
| Polymorphic | Nhiều subtype chung collection | Product nhiều category |
| Schema Versioning | Cùng collection chứa shape v1/v2 khi migrate | Zero-downtime evolution |
| Archive | Chuyển dữ liệu lạnh khỏi working set chính | Order/audit cũ |

Pattern không phải template copy-paste. Chỉ áp dụng sau khi workload và trade-off đã rõ; bài [Schema Design Patterns](../performance/schema_design.md) đi sâu hơn.

---

## 12. Time series, capped collection và event

### 12.1 Time series collection

Metric có timestamp + metadata ổn định nên cân nhắc time series collection:

```javascript
db.createCollection("temperature", {
  timeseries: {
    timeField: "measuredAt",
    metaField: "sensor",
    granularity: "minutes"
  },
  expireAfterSeconds: 2592000
})
```

MongoDB quản lý bucket nội bộ. Chọn `metaField`, granularity, retention và shard strategy theo query/ingestion thật.

### 12.2 Capped collection

Capped collection có fixed size và giữ insertion order, nhưng không phải lựa chọn mặc định cho business event:

- dữ liệu cũ tự bị ghi đè theo capacity;
- hạn chế operation;
- không cung cấp consumer acknowledgment/retry;
- không thay Kafka/RabbitMQ/Redis Streams.

Oplog là use case hệ thống đặc biệt. Với event nghiệp vụ, chọn regular/time-series collection hoặc messaging system theo delivery semantics.

---

## 13. Java type mapping

Mapping cần explicit:

| Java | BSON thường dùng | Ghi chú |
|---|---|---|
| `String` | String | Enum cần validation |
| `int`/`Integer` | Int32 | Tránh đổi type giữa document |
| `long`/`Long` | Int64 | Kiểm tra client ngoài Java |
| `BigDecimal` | Decimal128 | Codec/framework phải cấu hình đúng |
| `Instant` | Date | UTC instant, không timezone |
| `LocalDate` | String/document/custom mapping | Không tự coi là UTC instant |
| `UUID` | Binary UUID | Thống nhất representation |
| `ObjectId` | ObjectId | Có thể expose API dưới string nhưng storage type nhất quán |
| `List<T>` | Array | Chỉ cho bounded collection |
| POJO/record | Embedded document | Field rename cần migration/annotation |

Checklist cho Java:

- không dùng `double` cho tiền;
- không biến missing và `null` thành cùng default vô thức;
- codec test round-trip cho Decimal128, UUID và date;
- record/entity có `schemaVersion`;
- optimistic update dùng version trong filter;
- projection DTO theo use case, không load document lớn mặc định;
- migration test với document cũ thật.

Ví dụ optimistic update:

```javascript
db.orders.updateOne(
  {
    _id: ObjectId("687000000000000000000042"),
    optimisticVersion: 7
  },
  {
    $set: {
      status: "SHIPPED",
      updatedAt: new Date()
    },
    $inc: {optimisticVersion: 1}
  }
)
```

Application phải kiểm tra `matchedCount`; bằng `0` nghĩa là conflict hoặc document không tồn tại, không phải update thành công.

---

## 14. MongoDB và relational model

| Câu hỏi | MongoDB document model | Relational model |
|---|---|---|
| Đơn vị chính | Aggregate/document | Row/table |
| Quan hệ | Embed hoặc reference | Foreign key/join |
| Schema | Flexible + validator | DDL constraint mạnh |
| Atomicity tự nhiên | Single document | Transaction nhiều row/table |
| Denormalization | Thường dùng theo access pattern | Thường normalize trước |
| Join | `$lookup`, thường cân nhắc cost | Thành phần cốt lõi của query |
| Scale data | Replica/sharding | Tùy RDBMS, thường scale-up/read replica trước |

Không chọn MongoDB chỉ vì “JSON dễ dùng”, và không chọn SQL chỉ vì “dữ liệu có quan hệ”. Hãy so:

- invariant/transaction;
- query/ad-hoc analytics;
- access pattern;
- growth và shard key;
- operational skill;
- ecosystem/tooling;
- cost migration và lock-in.

---

## 15. Anti-patterns

| Anti-pattern | Hậu quả | Hướng sửa |
|---|---|---|
| Gọi MongoDB “schema-less” | Type/shape trôi tự do | Contract + validator + version |
| Unbounded array | Document/index phình, hotspot | Reference, subset, bucket |
| Bloated document | Working set/network lớn | Projection, split hot/cold |
| Cùng field nhiều type tùy ý | Query/sort/index bất ngờ | Normalize + validation |
| Lưu số/ngày dưới string | Sort/range sai, parse ở app | BSON type đúng |
| Embed dữ liệu đổi liên tục ở nhiều nơi | Update fan-out/stale copy | Reference hoặc sync protocol |
| Reference mọi thứ như SQL | Nhiều round trip/`$lookup` | Embed theo aggregate |
| Dựa `_id` để sort business time | Thứ tự không tuyệt đối | Explicit timestamp + tie-breaker |
| Dùng transaction cho mọi write | Latency/complexity tăng | Thiết kế document atomic boundary |
| Collection theo từng customer tùy ý | Catalog/index/operation overhead | Shared collection + tenant key |
| Dynamic field name cho user input | Index/query khó kiểm soát | Array `{key, value}` hoặc map bounded |
| File lớn trong một document | Chạm 16 MiB, network nặng | GridFS/object storage |

---

## 16. Production checklist

### Workload

- [ ] Có bảng read/write/query frequency/SLO/growth.
- [ ] Document boundary khớp aggregate và atomic update.
- [ ] Query quan trọng có projection/index plan dự kiến.
- [ ] Cardinality và growth được ước lượng theo thời gian.

### BSON

- [ ] Money dùng Decimal128 và có currency/rounding contract.
- [ ] Business time dùng Date + timezone metadata khi cần.
- [ ] `null`, missing và empty có semantics rõ.
- [ ] UUID/ObjectId/Int64 mapping nhất quán giữa mọi client.

### Shape

- [ ] Không có unbounded array.
- [ ] Document size p50/p95/p99 được theo dõi, không chỉ max 16 MiB.
- [ ] Embed/reference được chọn theo workload, lifecycle và update rate.
- [ ] Dữ liệu duplicate có owner và sync strategy.

### Safety

- [ ] Có schema validation và kế hoạch rollout.
- [ ] Atomic operator thay read-modify-replace khi có thể.
- [ ] Optimistic update kiểm tra `matchedCount`.
- [ ] Schema migration có version, batch, checkpoint và rollback.

### Operations

- [ ] Working set gồm data + indexes được capacity plan.
- [ ] Retention/archive/TTL rõ cho từng collection.
- [ ] Shard key tương lai đã được cân nhắc với key/cardinality.
- [ ] Backup/restore và compatibility được test với BSON type thật.

---

## 17. Tóm tắt

- MongoDB có flexible schema, nhưng production vẫn cần schema contract và validation.
- Thiết kế document bắt đầu từ workload, dữ liệu đọc/ghi cùng và growth.
- BSON giữ type giàu hơn JSON; Date, Timestamp, Decimal128, Int64 và `null` không thể dùng lẫn tùy ý.
- ObjectId chỉ xấp xỉ theo thời gian tạo, không phải business ordering tuyệt đối.
- Single-document write là atomic; embedding có thể biến aggregate thành atomic boundary tự nhiên.
- Không embed collection tăng vô hạn; dùng reference, subset hoặc bucket.
- Schema evolution cần version, tolerant reader, backfill có kiểm soát và validator rollout.
- 16 MiB là trần kỹ thuật, không phải kích thước document mục tiêu.

## Tài liệu chính thức

- [MongoDB 8.2 release notes](https://www.mongodb.com/docs/manual/release-notes/8.2/)
- [Documents](https://www.mongodb.com/docs/manual/core/document/)
- [BSON types](https://www.mongodb.com/docs/manual/reference/bson-types/)
- [MongoDB limits and thresholds](https://www.mongodb.com/docs/manual/reference/limits/)
- [Designing your schema](https://www.mongodb.com/docs/manual/data-modeling/schema-design-process/)
- [Embedded data](https://www.mongodb.com/docs/manual/data-modeling/embedding/)
- [Referenced data](https://www.mongodb.com/docs/manual/data-modeling/referencing/)
- [Schema validation](https://www.mongodb.com/docs/manual/core/schema-validation/)
- [Avoid unbounded arrays](https://www.mongodb.com/docs/manual/data-modeling/design-antipatterns/unbounded-arrays/)
- [Schema design patterns](https://www.mongodb.com/docs/manual/data-modeling/design-patterns/)

## Đọc tiếp

- [CRUD & Aggregation Pipeline](crud_aggregation.md)
- [Indexing](indexing.md)
- [Transactions](transactions.md)
- [Schema Design Patterns](../performance/schema_design.md)
- [MongoDB Glossary](../glossary.md)
- [MongoDB Roadmap](../roadmap.md)

*Cập nhật lần cuối: 2026-07-29*
