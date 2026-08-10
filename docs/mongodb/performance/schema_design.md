---
title: "MongoDB Schema Design Patterns – Thiết kế theo access pattern"
topic: mongodb
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# MongoDB Schema Design Patterns – Thiết kế theo access pattern

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: biết **vì sao** chọn một data model, pattern đó tối ưu đường đọc/ghi nào, dữ liệu nào là nguồn sự thật và phải trả giá ở đâu.
>
> Phiên bản mục tiêu: **MongoDB 8.2**.

---

## 1. Schema trong MongoDB không chỉ là “shape của JSON”

MongoDB cho phép các document trong cùng collection có shape linh hoạt. Điều đó không có nghĩa là ứng dụng “không có schema”.

Một schema production là hợp đồng gồm:

- field và BSON type;
- quan hệ giữa các entity;
- invariant nghiệp vụ;
- dữ liệu nào đọc/ghi cùng nhau;
- cardinality hiện tại và tốc độ tăng trưởng;
- lifecycle, retention và quyền truy cập;
- nguồn sự thật, dữ liệu nhân bản và cách đồng bộ;
- index, shard key và atomic boundary.

Nguyên tắc thường dùng:

> Dữ liệu được truy cập cùng nhau nên được lưu gần nhau.

Đây là điểm bắt đầu, không phải luật tuyệt đối. Nếu một child có thể tăng không giới hạn, có lifecycle riêng hoặc thường được truy vấn độc lập thì việc embed tất cả vào parent sẽ tạo document phình to, hotspot và write amplification.

Schema Design Pattern là công cụ tối ưu data model theo access pattern. Các pattern **có thể kết hợp**; chúng không phải những lựa chọn loại trừ lẫn nhau.

---

## 2. Bắt đầu từ workload, không bắt đầu từ collection

Trước khi vẽ document, hãy lập bảng cho các operation quan trọng:

| Operation | Tần suất | SLA/ưu tiên | Filter + sort | Dữ liệu trả về | Ghi thế nào? |
|---|---:|---|---|---|---|
| Xem chi tiết sản phẩm | 8.000/s | P95 < 80 ms | `_id` | thông tin + 5 review mới | read |
| Phân trang review | 300/s | P95 < 150 ms | `productId`, `createdAt` | 20 review | read |
| Tạo review | 50/s | không mất dữ liệu | `reviewId` | review mới | insert + cập nhật summary |
| Sửa giá | 5/s | tức thời | `_id`, `version` | giá mới | conditional update |
| Báo cáo tháng | 2/ngày | chấp nhận 5 phút | thời gian, tenant | aggregate | batch read |

Với mỗi relationship, cần trả lời:

1. Cardinality là `one-to-one`, `one-to-few`, `one-to-many` hay `many-to-many`?
2. “Few” có giới hạn nghiệp vụ thật hay chỉ đang ít ở dữ liệu mẫu?
3. Parent và child có được đọc, ghi, xóa và archive cùng nhau không?
4. Dữ liệu có phải snapshot lịch sử hay phải phản ánh giá trị hiện tại?
5. Operation nào cần atomic? Atomic trong một document có đủ không?
6. Kích thước sau 1 năm, 3 năm và ở tenant lớn nhất là bao nhiêu?

Quy trình thực tế:

```text
workload
   ↓
relationship + cardinality + lifecycle
   ↓
embed / reference / duplicate có chủ đích
   ↓
áp dụng pattern để xử lý đường nóng và ngoại lệ
   ↓
validator + index
   ↓
đo với dữ liệu và concurrency gần production
```

MongoDB cũng mô tả quy trình schema design theo thứ tự: xác định workload, ánh xạ relationship, áp dụng pattern rồi tạo index.

---

## 3. Các guardrail phải kiểm tra trước

### 3.1. Trần BSON 16 MiB không phải mục tiêu thiết kế

Một BSON document có kích thước tối đa 16 MiB. Document chỉ 5–10 MiB vẫn có thể là thiết kế tệ nếu request thường xuyên phải đọc, decode hoặc cập nhật toàn bộ document đó.

Không nên hỏi:

> “Document đã chạm 16 MiB chưa?”

Nên hỏi:

> “Document có bounded không, hot query cần bao nhiêu byte và chi phí cập nhật tăng thế nào?”

### 3.2. Tránh unbounded array

```javascript
// Rủi ro: comments tăng theo toàn bộ tuổi đời của post.
{
  _id: postId,
  comments: [/* không có giới hạn nghiệp vụ */]
}
```

Unbounded array có thể:

- làm document tiến gần 16 MiB;
- sinh nhiều multikey index entry;
- khiến mỗi lần đọc parent kéo theo dữ liệu lạnh;
- tạo contention trên một document nóng;
- làm migration và archive khó hơn.

Dùng reference, Subset, Bucket hoặc Outlier để đặt giới hạn rõ ràng.

### 3.3. Tối ưu working set, không chỉ tổng dung lượng

Working set là phần dữ liệu và index thường xuyên được truy cập. Một collection 2 TB vẫn có thể chạy tốt nếu hot working set vừa RAM; ngược lại, document lớn chứa cả dữ liệu nóng và lạnh có thể gây cache churn dù tổng dữ liệu nhỏ hơn nhiều.

### 3.4. Mọi dữ liệu nhân bản cần consistency contract

Với mỗi field bị duplicate, ghi rõ:

```text
owner/source of truth:
ý nghĩa: snapshot hay current value?
freshness cho phép:
cơ chế cập nhật:
cách retry/deduplicate:
cách reconciliation:
```

Nếu không có hợp đồng này, “denormalization để đọc nhanh” thường trở thành dữ liệu lệch mà không ai biết bản nào đúng.

---

## 4. Embedding, referencing và duplication

### 4.1. Khi nên embed

Embed phù hợp khi:

- dữ liệu luôn hoặc gần như luôn được đọc cùng parent;
- child thuộc sở hữu của parent và không có lifecycle riêng;
- cardinality có giới hạn nghiệp vụ;
- muốn cập nhật atomic trong một document;
- duplication nhỏ và update cùng nhau.

```javascript
{
  _id: "order-1001",
  status: "PAID",
  shippingAddress: {
    line1: "12 Nguyen Hue",
    city: "Ho Chi Minh City",
    country: "VN"
  },
  items: [
    { sku: "KB-01", quantity: 1, unitPrice: Decimal128("1200000") }
  ]
}
```

`shippingAddress` và `items` là snapshot của đơn hàng. Việc khách hàng đổi địa chỉ hoặc catalog đổi giá không được làm lịch sử đơn hàng thay đổi.

### 4.2. Khi nên reference

Reference phù hợp khi:

- child có thể tăng không giới hạn;
- entity được truy vấn/cập nhật độc lập;
- hai bên có lifecycle hoặc quyền truy cập khác nhau;
- quan hệ many-to-many;
- một entity được nhiều parent dùng chung.

```javascript
// products
{ _id: "P-01", name: "Keyboard", reviewCount: 842 }

// reviews
{
  _id: "R-9001",
  productId: "P-01",
  rating: 5,
  text: "Gõ tốt",
  createdAt: ISODate("2026-07-29T08:00:00Z")
}

db.reviews.createIndex({ productId: 1, createdAt: -1, _id: -1 });
```

Reference không có nghĩa mọi request phải chạy `$lookup`. Ứng dụng có thể thực hiện hai query có kiểm soát, cache, batch load hoặc duplicate đúng phần dữ liệu cần cho hot path.

### 4.3. So sánh thực tế

| Tiêu chí | Embed | Reference | Duplicate có chủ đích |
|---|---|---|---|
| Đọc cùng nhau | thường 1 read | thêm query/`$lookup` | thường 1 read |
| Atomicity | tự nhiên trong 1 document | nhiều document có thể cần transaction | phụ thuộc cách đồng bộ |
| Cardinality | phải bounded | phù hợp tập lớn | phần duplicate phải bounded |
| Update độc lập | kém phù hợp hơn | tốt | có write amplification |
| Lifecycle riêng | khó | tốt | phải xác định snapshot/current |
| Rủi ro chính | document phình/hotspot | fan-out, join, nhiều round trip | stale data |

Không có rule “luôn embed trước”. Hãy bắt đầu từ workload và giới hạn tăng trưởng.

---

## 5. Bucket Pattern – gom nhóm có giới hạn

### 5.1. Bài toán

Bucket gom nhiều record liên tiếp thành một document để:

- giảm số document/index entry;
- đọc một nhóm hoặc một trang hiệu quả;
- lưu summary như `count`, `sum`, `min`, `max`;
- đặt ranh giới rõ ràng cho tăng trưởng.

### 5.2. Với time-series, ưu tiên Time Series Collection

Với phần lớn dữ liệu measurement theo thời gian, hãy đánh giá Time Series Collection trước. MongoDB tự tổ chức measurement vào bucket nội bộ và tối ưu storage/index theo `timeField` và `metaField`.

```javascript
db.createCollection("temperature", {
  timeseries: {
    timeField: "ts",
    metaField: "meta",
    granularity: "minutes"
  },
  expireAfterSeconds: 60 * 60 * 24 * 365
});

db.temperature.insertOne({
  ts: ISODate("2026-07-29T08:05:00Z"),
  meta: { sensorId: "S1", siteId: "HCM-01" },
  value: 25.5
});
```

`metaField` nên ổn định và thường xuất hiện trong filter. Đừng đặt request ID hoặc dữ liệu thay đổi liên tục vào metadata vì cardinality cao tạo nhiều bucket thưa.

Manual Bucket vẫn hữu ích khi cần:

- bucket theo ranh giới nghiệp vụ riêng;
- phân trang bằng bucket;
- lưu một nhóm bounded không phải time series;
- kiểm soát document shape và summary theo ứng dụng.

### 5.3. Manual bucket theo khoảng thời gian cố định

```javascript
{
  _id: "S1:2026-07-29T08:00:00Z",
  sensorId: "S1",
  bucketStart: ISODate("2026-07-29T08:00:00Z"),
  count: 2,
  sumTemp: 50.8,
  minTemp: 25.3,
  maxTemp: 25.5,
  readings: [
    { ts: ISODate("2026-07-29T08:01:00Z"), temp: 25.3 },
    { ts: ISODate("2026-07-29T08:02:00Z"), temp: 25.5 }
  ],
  schemaVersion: 1
}
```

Tạo `bucketStart` ở application từ timestamp của measurement, không dùng giờ hiện tại nếu hệ thống nhận late event.

```javascript
const bucketStart = ISODate("2026-07-29T08:00:00Z");
const bucketId = `S1:${bucketStart.toISOString()}`;
const measurement = {
  ts: ISODate("2026-07-29T08:02:00Z"),
  temp: 25.5
};

db.temperatureBuckets.updateOne(
  { _id: bucketId },
  {
    $setOnInsert: {
      sensorId: "S1",
      bucketStart,
      schemaVersion: 1
    },
    $push: { readings: measurement },
    $inc: { count: 1, sumTemp: measurement.temp },
    $min: { minTemp: measurement.temp },
    $max: { maxTemp: measurement.temp }
  },
  { upsert: true }
);
```

`_id` xác định duy nhất sensor + time window. Nếu hai upsert đầu tiên cạnh tranh và một request nhận duplicate-key, client có thể retry cùng update. Measurement cũng cần `eventId`/deduplication nếu producer có thể gửi lại.

Không dùng filter kiểu `{ count: { $lt: 60 } }` cùng `upsert: true` mà không có bucket allocator. Khi bucket đã đầy, filter không match nhưng upsert vẫn cố tạo một document có cùng business key và có thể gây duplicate-key hoặc tạo bucket trùng.

### 5.4. Trade-off

- Bucket quá nhỏ: nhiều document và index entry.
- Bucket quá lớn: document nóng, read amplification và nguy cơ vượt giới hạn.
- Fixed-time bucket dễ route/query nhưng rate spike có thể làm document lớn bất thường.
- Count-based bucket cần cấp sequence/bucket number an toàn khi concurrent.
- Summary tăng tốc đọc nhưng phải có nguồn sự thật và job reconciliation.

Hãy đo kích thước ở rate cao nhất, kể cả retry và late event, thay vì chỉ dùng giá trị trung bình.

---

## 6. Outlier Pattern – giữ fast path gọn

### 6.1. Bài toán

Giả sử 99% bài viết có ít comment, nhưng một số bài viral có hàng trăm nghìn comment. Nếu reference tất cả, common case phải thêm query; nếu embed tất cả, outlier làm parent phình vô hạn.

Outlier Pattern giữ phần phổ biến trong parent và tách phần vượt ngưỡng:

```javascript
// posts
{
  _id: "POST-01",
  title: "MongoDB Schema",
  previewComments: [
    {
      commentId: "C-105",
      authorName: "An",
      text: "Rất dễ hiểu",
      createdAt: ISODate("2026-07-29T08:00:00Z")
    }
  ],
  commentCount: 105,
  hasCommentOverflow: true
}

// commentPages
{
  _id: "POST-01:0002",
  postId: "POST-01",
  page: 2,
  comments: [/* bounded page */]
}

db.commentPages.createIndex({ postId: 1, page: 1 }, { unique: true });
```

Ngưỡng phải xuất phát từ UI/query phổ biến, chẳng hạn “trang đầu có 20 comment”, không phải đợi đến gần 16 MiB.

### 6.2. Những điều phải thiết kế

- `previewComments` là comment mới nhất, nhiều tương tác nhất hay trang đầu cố định?
- Khi comment bị sửa/xóa, bản preview được cập nhật thế nào?
- Transition từ normal sang outlier có cần transaction không?
- Overflow được chia page/bucket ra sao để vẫn bounded?
- Query full history dùng sort key nào và có index nào?

Nếu UI sort newest-first, không nên coi `page: 2` là một trang vật lý phải dịch chuyển sau mỗi insert. Hãy dùng bucket sequence bất biến hoặc lưu từng comment riêng rồi keyset-pagination; `previewComments` chỉ là subset duplicate cho fast path.

Outlier Pattern chấp nhận đường hiếm phức tạp hơn để đường phổ biến nhỏ và ổn định.

---

## 7. Computed Pattern – đổi chi phí đọc thành chi phí ghi

### 7.1. Khi phù hợp

Computed Pattern lưu sẵn kết quả đắt tiền khi:

- cùng một phép tính được đọc rất nhiều lần;
- dữ liệu nguồn thay đổi ít hơn số lần đọc;
- ứng dụng xác định được độ trễ chấp nhận được.

```javascript
{
  _id: "MOVIE-01",
  title: "Example",
  ratingSummary: {
    sum: Decimal128("5799.2"),
    count: 1234,
    average: Decimal128("4.6995"),
    computedAt: ISODate("2026-07-29T08:00:00Z")
  }
}
```

Không lưu mỗi `average`; giữ `sum` và `count` để cập nhật đúng. Không “tính trung bình của các trung bình” nếu các nhóm có kích thước khác nhau.

### 7.2. Chọn consistency contract

| Yêu cầu | Cách triển khai |
|---|---|
| Chính xác ngay sau write | cập nhật source + summary trong cùng document, hoặc transaction nếu khác document |
| Trễ vài giây/phút | outbox/change stream/queue và consumer idempotent |
| Báo cáo định kỳ | aggregation + `$merge` theo lịch |
| Ước lượng đủ dùng | Approximation Pattern, kèm sai số/freshness rõ ràng |

Nếu review nằm ở collection `reviews` còn summary nằm trong `movies`, hai write không tự atomic. Với rating hiển thị có thể chấp nhận eventual consistency; với số dư hoặc tồn kho thì thường không được phép suy diễn như vậy.

### 7.3. Cập nhật tăng dần và reconciliation

```javascript
const newRating = Decimal128("5.0");

db.movies.updateOne(
  { _id: "MOVIE-01" },
  [{
    $set: {
      "ratingSummary.sum": {
        $add: [
          { $ifNull: ["$ratingSummary.sum", Decimal128("0")] },
          newRating
        ]
      },
      "ratingSummary.count": {
        $add: [
          { $ifNull: ["$ratingSummary.count", 0] },
          1
        ]
      },
      "ratingSummary.computedAt": "$$NOW"
    }
  }, {
    $set: {
      "ratingSummary.average": {
        $divide: [
          "$ratingSummary.sum",
          "$ratingSummary.count"
        ]
      }
    }
  }]
);
```

Trong production, event cập nhật phải có ID để chống cộng hai lần khi retry. Ngoài incremental update, nên có job định kỳ tính lại từ source of truth và cảnh báo nếu sai lệch.

```javascript
db.reviews.aggregate([
  {
    $group: {
      _id: "$movieId",
      sum: { $sum: "$rating" },
      count: { $sum: 1 },
      average: { $avg: "$rating" }
    }
  },
  {
    $project: {
      ratingSummary: {
        sum: "$sum",
        count: "$count",
        average: "$average",
        computedAt: "$$NOW"
      }
    }
  },
  {
    $merge: {
      into: "movies",
      on: "_id",
      whenMatched: "merge",
      whenNotMatched: "discard"
    }
  }
]);
```

---

## 8. Subset Pattern – tách phần nóng khỏi phần đầy đủ

Subset Pattern duplicate một phần nhỏ, bounded, thường dùng vào hot document; dữ liệu đầy đủ vẫn ở collection riêng.

```javascript
// products: hot path
{
  _id: "P-01",
  name: "Keyboard",
  price: Decimal128("1200000"),
  recentReviews: [/* tối đa 5 phần tử */],
  reviewCount: 842,
  averageRating: 4.7
}

// reviews: source đầy đủ
{
  _id: "R-842",
  productId: "P-01",
  rating: 5,
  text: "Gõ tốt",
  createdAt: ISODate("2026-07-29T08:00:00Z")
}
```

Giữ array bounded ngay trong update:

```javascript
db.products.updateOne(
  { _id: "P-01" },
  {
    $push: {
      recentReviews: {
        $each: [{
          reviewId: "R-842",
          rating: 5,
          text: "Gõ tốt",
          createdAt: ISODate("2026-07-29T08:00:00Z")
        }],
        $position: 0,
        $slice: 5
      }
    },
    $inc: { reviewCount: 1 }
  }
);
```

Insert vào `reviews` và cập nhật `products` là hai document. Chọn một trong hai:

- transaction nếu cả hai bắt buộc cùng thành công;
- outbox/event + idempotency nếu cho phép eventual consistency;
- `reviews` là source of truth và job reconciliation sửa lại subset/counter.

Subset khác projection: projection giảm field trả về, còn Subset thay đổi cách lưu để hot document thực sự nhỏ hơn.

---

## 9. Extended Reference Pattern – reference kèm dữ liệu hay đọc

Extended Reference giữ ID của entity gốc và duplicate một số field thường cần:

```javascript
{
  _id: "ORDER-1001",
  customerId: "CUS-01",
  customerSnapshot: {
    name: "Nguyen Van A",
    email: "a@example.com"
  },
  total: Decimal128("1500000"),
  orderedAt: ISODate("2026-07-29T08:00:00Z")
}
```

Có hai semantics rất khác nhau:

### Snapshot lịch sử

`customerSnapshot` là thông tin tại thời điểm đặt hàng. Khách đổi tên/email **không** làm order cũ thay đổi. Đây không phải stale data; đây là lịch sử đúng.

### Bản sao của current value

Nếu trang tìm kiếm order phải luôn hiển thị tên hiện tại, `customerName` là cache/duplicate cần đồng bộ. Phải định nghĩa:

- `customers` là source of truth;
- độ trễ cho phép;
- background fan-out hay tính lúc đọc;
- cách retry và reconciliation.

Không nên trộn hai ý nghĩa trong cùng một field. Dùng tên như `customerSnapshot` và `currentCustomerSummary` để contract tự mô tả.

---

## 10. Polymorphic Pattern – nhiều subtype, một access path

Polymorphic Pattern lưu các subtype trong cùng collection khi chúng:

- thường được query chung;
- chia sẻ các field filter/sort quan trọng;
- có lifecycle, security và scale tương tự.

```javascript
db.content.insertMany([
  {
    _id: "A-01",
    type: "article",
    title: "MongoDB Tips",
    authorId: "U-01",
    createdAt: ISODate("2026-07-29T08:00:00Z"),
    body: "...",
    wordCount: 1200,
    schemaVersion: 1
  },
  {
    _id: "V-01",
    type: "video",
    title: "MongoDB Tutorial",
    authorId: "U-01",
    createdAt: ISODate("2026-07-29T07:00:00Z"),
    videoUrl: "https://example.com/video",
    durationSeconds: 900,
    schemaVersion: 1
  }
]);

db.content.createIndex({ authorId: 1, createdAt: -1, _id: -1 });
db.content.createIndex(
  { durationSeconds: 1 },
  { partialFilterExpression: { type: "video" } }
);
```

`type` là discriminator, không phải field trang trí. Validator nên enforce common fields và rule riêng theo subtype.

```javascript
db.runCommand({
  collMod: "content",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["type", "title", "authorId", "createdAt", "schemaVersion"],
      oneOf: [
        {
          properties: { type: { enum: ["article"] } },
          required: ["body", "wordCount"]
        },
        {
          properties: { type: { enum: ["video"] } },
          required: ["videoUrl", "durationSeconds"]
        }
      ]
    }
  },
  validationAction: "error"
});
```

Nên tách collection nếu subtype có query, index, retention, shard key, security hoặc tốc độ tăng trưởng rất khác nhau. “Có vài field chung” chưa đủ để gộp.

---

## 11. Attribute Pattern – chuẩn hóa nhóm field động

Một catalog có thể sinh hàng trăm field như `height_cm`, `height_inch`, `volume_ml`. Attribute Pattern gom các thuộc tính cùng bản chất thành array key-value:

```javascript
{
  _id: "P-01",
  category: "bottle",
  specs: [
    { key: "volume", value: Decimal128("500"), unit: "ml" },
    { key: "height", value: Decimal128("20"), unit: "cm" },
    { key: "material", value: "steel" }
  ]
}
```

Query nhiều điều kiện trên **cùng một phần tử** phải dùng `$elemMatch`:

```javascript
db.products.find({
  specs: {
    $elemMatch: {
      key: "volume",
      value: { $gte: Decimal128("500") },
      unit: "ml"
    }
  }
});
```

Pattern này giảm việc tạo một index cho mỗi tên field động, nhưng có trade-off:

- `value` nhiều type làm query/range/validation phức tạp;
- array vẫn phải bounded;
- multikey index có thể sinh nhiều entry;
- field hot, ổn định thường vẫn nên là field top-level với targeted index;
- wildcard index là lựa chọn khác cho field name thật sự khó đoán, không phải mặc định.

---

## 12. Tree Pattern – chọn theo operation trên cây

Không có một model cây tốt nhất cho mọi operation.

### 12.1. Parent Reference

```javascript
db.categories.insertMany([
  { _id: "electronics", parentId: null, name: "Electronics" },
  { _id: "computers", parentId: "electronics", name: "Computers" },
  { _id: "laptops", parentId: "computers", name: "Laptops" }
]);

db.categories.createIndex({ parentId: 1 });

// Con trực tiếp
db.categories.find({ parentId: "electronics" });
```

Lấy subtree bằng `$graphLookup`:

```javascript
db.categories.aggregate([
  { $match: { _id: "electronics" } },
  {
    $graphLookup: {
      from: "categories",
      startWith: "$_id",
      connectFromField: "_id",
      connectToField: "parentId",
      as: "descendants",
      maxDepth: 10,
      depthField: "depth"
    }
  }
]);
```

Đặt `maxDepth` và bảo vệ cycle ở application/validation workflow.

### 12.2. Array of Ancestors

```javascript
{
  _id: "gaming-laptops",
  parentId: "laptops",
  ancestors: ["electronics", "computers", "laptops"],
  name: "Gaming Laptops"
}

db.categories.createIndex({ ancestors: 1 });
db.categories.find({ ancestors: "electronics" });
```

Đọc subtree nhanh, nhưng khi chuyển một node sang parent khác phải cập nhật `ancestors` của toàn bộ descendant. Đó là write amplification và migration cần retry/idempotency.

### 12.3. Child Reference

```javascript
{
  _id: "electronics",
  children: ["computers", "phones"]
}
```

Đọc con trực tiếp nhanh, nhưng `children` trở thành unbounded array nếu fan-out lớn. Pattern này cũng không thuận tiện cho subtree traversal.

### 12.4. Bảng chọn nhanh

| Nhu cầu chính | Model thường phù hợp | Chi phí cần chấp nhận |
|---|---|---|
| parent/con trực tiếp, cây hay di chuyển | Parent Reference | subtree cần `$graphLookup` |
| đọc subtree rất nhiều, cây ít di chuyển | Ancestors/Materialized Path | move phải cập nhật descendant |
| đọc danh sách con, fan-out bounded | Child Reference | parent document nóng/phình |
| cây nhỏ, luôn đọc toàn bộ | embed bounded tree | update/size của một document |

Nếu category name có thể chứa ký tự đặc biệt, array ID thường an toàn hơn materialized path string + regex. Nếu dùng path string, cần encoding và query/index strategy rõ ràng.

---

## 13. Schema Versioning – tiến hóa không downtime

`schemaVersion` cho reader biết document đang dùng shape nào:

```javascript
// v1
{
  _id: "CUS-01",
  schemaVersion: 1,
  homePhone: "028...",
  email: "a@example.com"
}

// v2
{
  _id: "CUS-02",
  schemaVersion: 2,
  contacts: [
    { type: "phone", value: "028..." },
    { type: "email", value: "b@example.com" }
  ]
}
```

Phân biệt ba khái niệm:

| Field/Pattern | Mục đích |
|---|---|
| `schemaVersion` | shape của document |
| Document Versioning | lưu lịch sử các trạng thái nghiệp vụ |
| optimistic `version` | phát hiện concurrent update conflict |

### 13.1. Expand-and-contract

Một migration online thường đi theo các bước:

1. **Expand reader**: code mới đọc được cả v1 và v2.
2. **Expand writer**: writer mới ghi v2; nếu cần rollback thì dual-write có thời hạn.
3. **Backfill**: chuyển v1 theo batch nhỏ, idempotent và có checkpoint.
4. **Reconcile**: đếm, sample và so invariant.
5. **Tighten validator**: chuyển từ `warn`/`moderate` sang rule chặt khi dữ liệu đã sạch.
6. **Contract**: xóa nhánh đọc cũ và index cũ sau observation window.

Không nên đổi validator sang chỉ chấp nhận v2 trước khi deploy reader/writer tương thích. Backfill lớn cần kiểm soát replication lag, cache pressure và write contention.

---

## 14. Archive Pattern – đưa dữ liệu lạnh khỏi hot path

Archive Pattern phù hợp khi dữ liệu cũ ít đọc nhưng vẫn phải giữ vì audit, pháp lý hoặc phân tích.

Có thể chuyển dữ liệu sang:

- object storage;
- cluster rẻ hơn;
- collection riêng;
- dịch vụ archive được quản lý.

Archived document thường nên self-contained/embedded để khi đọc lại, mọi thành phần phản ánh cùng một thời điểm lịch sử.

Một quy trình archive an toàn cần:

```text
chọn theo một age/retention field rõ ràng
→ copy idempotent với cùng business ID
→ verify count/hash/invariant
→ chỉ xóa nguồn sau khi đích durable
→ ghi audit/checkpoint
→ thử restore và đường query hợp nhất
```

Cần xử lý riêng:

- legal hold hoặc record “keep forever”;
- record bị cập nhật trong lúc archive;
- retry sau khi copy thành công nhưng trước khi xóa;
- retention ở cả active và archive;
- encryption, access control và data residency;
- thời gian/chi phí restore.

TTL không thay Archive Pattern: TTL xóa bất đồng bộ sau khi hết hạn; nó không tự tạo bản archive hay quy trình verify/restore.

---

## 15. Các pattern kết hợp trong một hệ thống

Ví dụ e-commerce có thể dùng:

```text
orders
├── Extended Reference: customerSnapshot
├── Computed: total, tax, itemCount
├── Schema Versioning: schemaVersion
└── Archive: chuyển order cũ khỏi cluster nóng

products
├── Subset: 5 recentReviews
├── Computed: ratingSummary
├── Attribute: specs động
└── Reference: full reviews

reviews/comments
├── Bucket: page hoặc time window bounded
└── Outlier: tách trường hợp viral khỏi common shape
```

Điểm quan trọng không phải số pattern, mà là mỗi bản duplicate/bucket/summary đều có owner, bound, consistency và recovery path.

---

## 16. Anti-pattern thường gặp

### 16.1. Copy schema quan hệ từng bảng một

Mỗi entity thành một collection và mọi màn hình dùng nhiều `$lookup` có thể bỏ lỡ lợi thế document model. Hãy xem lại dữ liệu nào thực sự được đọc cùng nhau.

### 16.2. Embed vì dữ liệu hiện tại còn ít

“Hiện chỉ có 20 phần tử” không phải bound. Cần một invariant như “chỉ lưu 20 bản ghi gần nhất” và enforce bằng `$slice`.

### 16.3. Duplicate nhưng không có owner

Hai collection cùng có `status` nhưng writer nào cũng có quyền sửa sẽ tạo split-brain ở tầng dữ liệu.

### 16.4. Computed field không có freshness

Một con số không có `computedAt`, source version hoặc reconciliation khiến client không biết nó chính xác đến thời điểm nào.

### 16.5. Polymorphic collection thành “sọt rác”

Subtype có lifecycle và index hoàn toàn khác nhau nhưng vẫn bị gộp chỉ vì cùng có `name`.

### 16.6. Bucket không có identity deterministic

Concurrent writer tự tìm “bucket chưa đầy” rồi upsert có thể tạo bucket trùng, duplicate event hoặc hotspot khó kiểm soát.

### 16.7. Tạo index trước khi biết query

Index phải xuất phát từ filter, sort, projection, cardinality và data distribution. Một model đẹp nhưng không có access path phù hợp vẫn chậm.

---

## 17. Validation và kiểm chứng

### 17.1. Validator là hàng rào cuối

Validator nên bảo vệ:

- required field và BSON type;
- discriminator/schema version hợp lệ;
- array/object shape;
- những bound có thể biểu diễn;
- invariant đơn giản mà mọi writer phải tuân thủ.

Application validation vẫn cần cho business rule và thông báo lỗi thân thiện.

### 17.2. Kiểm tra bằng dữ liệu giống production

Với mỗi hot query/write:

```javascript
db.collection.find(filter).sort(sort).explain("executionStats");
```

Theo dõi:

- `totalKeysExamined`, `totalDocsExamined`, `nReturned`;
- blocking sort và spill;
- document size phân vị P50/P95/P99/max;
- array length và tốc độ tăng;
- read/write latency dưới concurrency;
- cache eviction, disk I/O và replication lag;
- số bản duplicate lệch qua reconciliation;
- write amplification khi thêm index/pattern.

Không benchmark chỉ với 100 document hoặc dữ liệu phân bố đều nếu production có tenant/outlier rất lệch.

---

## 18. Checklist review schema

### Workload

- [ ] Đã liệt kê query/write theo tần suất, SLA và mức ưu tiên.
- [ ] Đã xác định filter, sort, projection và page size.
- [ ] Đã tách hot path, cold path và outlier path.

### Growth và lifecycle

- [ ] Mỗi array có bound nghiệp vụ được enforce.
- [ ] Đã ước lượng P99/max document sau nhiều năm.
- [ ] Parent/child có lifecycle, retention và quyền truy cập tương thích.
- [ ] Có archive/restore plan cho dữ liệu lạnh.

### Consistency

- [ ] Mỗi field duplicate có source of truth.
- [ ] Đã phân biệt snapshot và current value.
- [ ] Có freshness SLA, retry, idempotency và reconciliation.
- [ ] Chỉ dùng transaction khi invariant thực sự vượt một document.

### Pattern và migration

- [ ] Time-series đã đánh giá Time Series Collection trước manual Bucket.
- [ ] Computed field có `computedAt` và cách rebuild.
- [ ] Polymorphic subtype có discriminator/validation.
- [ ] Schema migration theo expand-and-contract và rollback window.

### Performance

- [ ] Index xuất phát từ query shape và distribution.
- [ ] Đã chạy `explain("executionStats")` cho critical query.
- [ ] Đã test concurrent write, retry, late event và outlier.
- [ ] Đã đo working set và write amplification.

---

## 19. Tóm tắt

```text
Embed
  → đọc/ghi cùng nhau, cùng lifecycle, cardinality bounded

Reference
  → entity độc lập, many-to-many hoặc tăng không giới hạn

Bucket
  → gom nhóm bounded; time-series nên đánh giá collection chuyên dụng trước

Outlier
  → giữ common document nhỏ, tách trường hợp cực lớn

Computed
  → trả thêm chi phí ghi/đồng bộ để giảm phép tính lặp khi đọc

Subset
  → giữ phần hot bounded cạnh parent, full data ở nguồn riêng

Extended Reference
  → duplicate field hay đọc; phân biệt snapshot với current value

Polymorphic
  → subtype được query chung và có lifecycle/index tương đồng

Attribute
  → gom nhóm field động cùng bản chất

Tree
  → chọn representation theo parent/child/subtree/move workload

Schema Versioning
  → cho nhiều shape cùng tồn tại trong migration online

Archive
  → chuyển cold data khỏi working set nhưng vẫn verify/restore được
```

Thiết kế tốt không phải document ít nhất hay collection ít nhất. Thiết kế tốt làm đường quan trọng dự đoán được, đặt giới hạn tăng trưởng rõ ràng và mô tả chính xác cách hệ thống giữ dữ liệu nhất quán.

---

## 20. Đọc tiếp

- [Data Model & BSON](../fundamentals/data_model.md)
- [CRUD & Aggregation Pipeline](../fundamentals/crud_aggregation.md)
- [Indexing](../fundamentals/indexing.md)
- [Transactions](../fundamentals/transactions.md)
- [MongoDB Glossary](../glossary.md)
- Chủ đề tiếp theo: [Replica Set](../operations/replication.md)

## Tài liệu chính thức

- [Designing Your Schema](https://www.mongodb.com/docs/v8.2/data-modeling/schema-design-process/)
- [Schema Design Patterns](https://www.mongodb.com/docs/v8.2/data-modeling/design-patterns/)
- [Apply Design Patterns](https://www.mongodb.com/docs/v8.2/data-modeling/schema-design-process/apply-patterns/)
- [Best Practices for Data Modeling](https://www.mongodb.com/docs/v8.2/data-modeling/best-practices/)
- [Avoid Unbounded Arrays](https://www.mongodb.com/docs/v8.2/data-modeling/design-antipatterns/unbounded-arrays/)
- [Time Series Collections Considerations](https://www.mongodb.com/docs/v8.2/core/timeseries/timeseries-considerations/)
- [Group Data with Schema Design Patterns](https://www.mongodb.com/docs/v8.2/data-modeling/design-patterns/group-data/)
- [Document and Schema Versioning](https://www.mongodb.com/docs/v8.2/data-modeling/design-patterns/data-versioning/)
- [Archive Pattern](https://www.mongodb.com/docs/v8.2/data-modeling/design-patterns/archive/)
- [Model Tree Structures](https://www.mongodb.com/docs/v8.2/applications/data-models-tree-structures/)

---

*Cập nhật lần cuối: 2026-07-29*
