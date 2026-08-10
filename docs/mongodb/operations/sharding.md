---
title: "MongoDB Sharding – Chọn shard key và vận hành production"
topic: mongodb
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 14
---
# MongoDB Sharding – Chọn shard key và vận hành production

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: hiểu sharding phân phối dữ liệu như thế nào, chọn shard key từ workload thật, phân biệt targeted với broadcast query và xử lý hotspot, jumbo range, balancer, zone, resharding.
>
> Phiên bản mục tiêu: **MongoDB 8.2**.

---

## 1. Mental model: sharding là chia ownership

Sharding là horizontal scaling: một collection được chia thành các **range của shard key** và mỗi range do một shard sở hữu.

```text
Application / Driver
          │
          ▼
   ┌──────────────┐       metadata        ┌─────────────────┐
   │ mongos       │ ◀──────────────────── │ config servers  │
   │ query router │                       │ / config shard  │
   └──────┬───────┘                       └─────────────────┘
          │ route theo shard key
     ┌────┴──────────────┐
     ▼                   ▼
┌─────────────┐     ┌─────────────┐
│ Shard A     │     │ Shard B     │
│ replica set │     │ replica set │
└─────────────┘     └─────────────┘
```

Sharding có thể giải quyết:

- dataset hoặc working set vượt capacity thực tế của một replica set;
- write throughput hoặc IOPS bị giới hạn ở một primary;
- một nhóm tenant/range cần được phân bố sang nhiều failure domain;
- locality theo vùng địa lý bằng zones.

Sharding **không tự giải quyết**:

- query thiếu index;
- document/array tăng không giới hạn;
- một shard key có một giá trị quá nóng;
- latency WAN;
- backup, authorization hay encryption;
- read/write scale tuyến tính chỉ bằng cách thêm shard.

Câu hỏi đúng không phải “data đã chia đều chưa?” mà là:

1. mỗi hot operation được route tới bao nhiêu shard?
2. data, traffic, CPU, cache và I/O có lệch theo cùng một hướng không?
3. khi một shard hoặc zone mất, phần còn lại có đủ capacity không?
4. balancer hoặc resharding có đủ headroom để di chuyển dữ liệu không?

---

## 2. Các thành phần của sharded cluster

### 2.1. Shard

Mỗi shard production nên là một replica set có data-bearing member ở các failure domain phù hợp. Shard chịu trách nhiệm:

- lưu document và index thuộc các range nó sở hữu;
- nhận operation do `mongos` route đến;
- tham gia range migration, resharding và distributed transaction.

Ít nhất hai shard mới có thể thực sự phân phối dữ liệu. Arbiter không lưu data và không tăng durability; tránh dùng arbiter cho shard nếu chưa phân tích rõ majority write availability.

### 2.2. `mongos`

`mongos` là query router stateless:

- cache routing metadata từ config server;
- chọn shard cần nhận operation;
- merge kết quả khi operation chạy trên nhiều shard;
- không giữ application data.

Ứng dụng kết nối vào `mongos`, **không kết nối trực tiếp vào shard** để đọc/ghi business data. Kết nối trực tiếp có thể bỏ qua routing, tạo kết quả thiếu và phá vỡ abstraction của cluster.

Nên có nhiều `mongos` để tránh một endpoint đơn lẻ. Nếu đặt load balancer/proxy phía trước, phải tuân thủ yêu cầu client affinity của MongoDB. Quá nhiều `mongos` cũng làm tăng metadata load lên config servers, nên scale theo đo đạc thay vì nhân bản vô hạn.

### 2.3. Config servers và config shard

Config servers giữ authoritative metadata như:

- shard nào đang sở hữu range nào;
- database/collection metadata;
- zones;
- distributed locks và authentication configuration.

Hai kiểu triển khai:

| Kiểu | Đặc điểm | Khi phù hợp |
|---|---|---|
| Dedicated config server replica set | Chỉ giữ metadata hệ thống | Cách ly tốt; hợp cluster lớn hoặc workload yêu cầu HA/performance cao |
| Config shard | Config server đồng thời giữ application data | Có từ MongoDB 8.0; giảm topology cho cluster nhỏ |

Với self-managed production, config server replica set thường có ba member. Backup/restore sharded cluster phải giữ metadata này nhất quán với dữ liệu trên mọi shard.

---

## 3. Range, chunk và ownership

MongoDB chia toàn bộ không gian shard key thành các range:

```text
[MinKey, 1000)  → Shard A
[1000, 5000)    → Shard B
[5000, MaxKey)  → Shard C
```

Lower bound là inclusive, upper bound là exclusive. Tài liệu và lệnh quản trị vẫn thường dùng từ **chunk** cho một data range.

Một range:

- chỉ có một owner hợp lệ tại một thời điểm;
- chứa các document có shard key nằm trong bounds;
- có thể được balancer di chuyển sang shard khác;
- mặc định hướng tới kích thước range khoảng 128 MB, nhưng đây không phải SLA cứng cho từng range.

Từ MongoDB 6.0.3, automatic chunk splitting kiểu cũ không còn được thực hiện; các lệnh bật/tắt auto-split không còn điều khiển luồng như trước. Balancer có thể di chuyển hoặc xử lý range lớn theo chính sách hiện tại. Không xây runbook mới quanh vòng lặp `sh.splitAt()`.

### Một migration tạo ra tải gì?

Rút gọn:

```text
donor shard ── clone range ──▶ recipient shard
      │                            │
      └── catch up concurrent changes
                    │
             commit ownership
                    │
          donor range deletion sau đó
```

Migration tiêu thụ network, disk, cache và oplog headroom. Sau commit, bản cũ trên donor được range deleter dọn bất đồng bộ; không được coi mọi byte đã biến mất ngay.

---

## 4. Khi nào nên shard?

Không có một ngưỡng như “10 TB thì phải shard”. Quyết định nên xuất phát từ bottleneck đã đo và growth forecast.

### Dấu hiệu hợp lý

- primary liên tục gần giới hạn CPU, IOPS hoặc write throughput dù index/schema đã tối ưu;
- working set nóng không còn fit trong cache với latency mục tiêu;
- disk/capacity/rebuild time của một replica set vượt operational envelope;
- một collection lớn làm backup, restore, maintenance hoặc scale-up không còn đạt RTO;
- locality/zone là yêu cầu kiến trúc thực sự.

### Chưa đủ lý do

- query chậm nhưng `explain()` vẫn scan quá nhiều document;
- muốn “HA hơn”: replica set mới là primitive HA bên trong mỗi shard;
- muốn secondary read luôn mới nhất;
- muốn bỏ qua capacity planning;
- chỉ vì MongoDB hỗ trợ sharding.

Sharding nên bắt đầu **trước khi** replica set cũ chạm giới hạn, vì initial redistribution cần chính CPU, disk và network đang còn trống. Nhưng sharding quá sớm làm tăng topology, failure modes, backup và on-call cost.

---

## 5. Shard key là quyết định workload

Shard key quyết định đồng thời:

- document thuộc range nào;
- `mongos` có thể target shard nào;
- data có thể chia nhỏ đến mức nào;
- writes có hội tụ vào hot range không;
- zone bounds có thể biểu diễn bằng field nào;
- unique constraint nào có thể enforce trên toàn cluster.

### 5.1. Năm chiều phải đo

| Chiều | Câu hỏi |
|---|---|
| Query targeting | Hot query có equality/range trên shard key hoặc prefix của compound key không? |
| Cardinality | Có đủ nhiều giá trị distinct để tạo nhiều range hữu ích không? |
| Frequency/skew | Một vài giá trị có chứa phần lớn document hoặc traffic không? |
| Monotonicity | Insert mới có luôn đi vào range gần `MinKey`/`MaxKey` không? |
| Locality và change | Có cần gom tenant/region; shard key value có đổi thường xuyên không? |

High cardinality chưa chắc tốt nếu một tenant tạo 70% traffic. Data chia đều cũng chưa chắc tốt nếu mọi query đều broadcast.

### 5.2. Bắt đầu từ access-pattern inventory

Ví dụ:

| Operation | Filter/sort | Tần suất | SLA | Nhận xét |
|---|---|---:|---:|---|
| Get order | `tenantId + orderId` | 15k/s | 30 ms | Cần targeted |
| List recent | `tenantId`, sort `createdAt` | 2k/s | 100 ms | Cần locality + index |
| Update status | `tenantId + orderId` | 5k/s | 50 ms | Single-document write |
| Revenue report | time range mọi tenant | 10/hour | 60 s | Broadcast có thể chấp nhận |

Shard key được tối ưu cho hot path, không phải để mọi query chạm đúng một shard bằng mọi giá.

---

## 6. Ranged, hashed và compound shard key

### 6.1. Ranged sharding

```javascript
{ tenantId: 1, orderId: 1 }
```

Ưu điểm:

- equality/range trên prefix có locality tốt;
- range query theo shard key tự nhiên;
- biểu diễn zone bounds dễ.

Rủi ro:

- `{ createdAt: 1 }`, sequence tăng dần hoặc ranged ObjectId dễ tạo hot max-key range;
- `{ status: 1 }` có cardinality thấp;
- một “whale tenant” có thể nóng dù data tổng thể khá đều.

### 6.2. Hashed sharding

```javascript
{ eventId: "hashed" }
```

Ưu điểm:

- biến key tăng tuần tự thành hash space phân bố rộng hơn;
- thường phân tán insert tốt hơn ranged monotonic key.

Đổi lại:

- range query theo giá trị gốc không còn giữ locality tự nhiên;
- hashing không sửa được frequency skew nếu nhiều document có cùng shard key value;
- unique hashed index không được hỗ trợ;
- query thiếu key vẫn broadcast.

### 6.3. Compound hashed key

Ví dụ geo locality kết hợp phân phối trong vùng:

```javascript
{ region: 1, customerId: "hashed" }
```

- `region` là prefix để định nghĩa zone;
- hashed `customerId` giúp phân tán trong các shard thuộc zone;
- query có `region + customerId` có thể target tốt;
- query chỉ có `region` có thể chạm nhiều shard trong zone.

Compound key luôn là trade-off. Thêm field suffix để tăng cardinality không đồng nghĩa mọi query theo prefix chỉ chạm một shard.

### 6.4. Time series

Time-series shard key chỉ dùng `metaField`, subfield của `metaField`, và trong một số cấu hình có thể dùng `timeField`. `timeField` phải là ranged và ở cuối key; từ MongoDB 8.0, shard key chứa `timeField` đã deprecated.

Ưu tiên metadata có cardinality/distribution phù hợp, ví dụ:

```javascript
{ "meta.tenantId": "hashed" }
```

Zone sharding không hỗ trợ time-series collection trong MongoDB 8.2.

---

## 7. Đo candidate key bằng Shard Key Analyzer

Từ MongoDB 7.0, `analyzeShardKey` giúp đo:

- `keyCharacteristics`: cardinality, frequency, monotonicity;
- `readWriteDistribution`: routing và phân phối read/write từ sampled queries.

Một workflow production:

```javascript
use sales

// Bật sampling với rate có kiểm soát.
db.orders.configureQueryAnalyzer({
  mode: "full",
  samplesPerSecond: 20
});

// Chờ đủ chu kỳ đại diện: peak, off-peak, batch/reporting.
db.orders.analyzeShardKey(
  { tenantId: 1, orderId: 1 }
);

// Tắt khi đã thu đủ mẫu.
db.orders.configureQueryAnalyzer({ mode: "off" });
```

Không chọn key chỉ từ một giờ traffic:

1. thu query shapes và sampled read/write qua nhiều chu kỳ;
2. đánh giá vài candidate key;
3. replay workload production-like với data distribution thật;
4. đo targeted/broadcast ratio, P95/P99, CPU/I/O từng shard;
5. mô phỏng whale tenant, growth và một shard unavailable;
6. viết migration + rollback/abort criteria trước khi đổi production.

Sampling có overhead và sampled data có vòng đời; đặt rate theo capacity, không mặc định dùng rate cao nhất.

---

## 8. Tạo sharded collection

Shard key phải được hỗ trợ bởi index phù hợp.

```javascript
use sales

db.orders.createIndex({ tenantId: 1, orderId: 1 });

// MongoDB 6.0+ không bắt buộc gọi sh.enableSharding() trước.
sh.shardCollection(
  "sales.orders",
  { tenantId: 1, orderId: 1 }
);
```

Từ MongoDB 8.0, khi deployment có đủ resource, MongoDB khuyến nghị `sh.shardAndDistributeCollection()` để shard và ngay lập tức redistribute nhanh hơn:

```javascript
db.events.createIndex({ eventId: "hashed" });

sh.shardAndDistributeCollection(
  "sales.events",
  { eventId: "hashed" }
);
```

Method này tương đương chạy `shardCollection` rồi reshard về cùng key, nên nó cần đáng kể disk, I/O và network headroom. Với collection đang có dữ liệu, phải load test và lập capacity budget trước.

Ghi chú:

- empty hashed collection có thể được tạo nhiều initial range và phân phối sớm;
- populated collection bắt đầu từ một large initial range nếu dùng flow thông thường, sau đó balancer mới phân phối;
- collection có default collation cần index/simple-collation option đúng quy tắc;
- đừng hard-code `numInitialChunks` từ công thức cũ; MongoDB 8.2 bỏ qua option này khi reshard với hashed prefix và chia hash space theo cách deterministic.

---

## 9. Query routing: targeted không chỉ là “có shard key”

### 9.1. Targeted operation

`mongos` có thể route tới một shard hoặc một subset shard khi filter đủ thông tin:

```javascript
db.orders.find({
  tenantId: "t-42",
  orderId: "o-9001"
});
```

### 9.2. Broadcast / scatter-gather

Khi không suy ra được target:

```javascript
db.orders.find({ status: "PENDING" });
```

`mongos` gửi query tới mọi shard liên quan rồi merge. Chi phí thường tăng theo số shard, số result, sort/group và network.

Tuy vậy broadcast không phải lúc nào cũng sai. Một analytical aggregation hiếm, xử lý dữ liệu lớn có thể hưởng lợi từ chạy song song trên các shard. Mục tiêu là tránh broadcast trên latency-sensitive hot path.

### 9.3. Luôn xác nhận bằng `explain()`

```javascript
db.orders
  .find({ tenantId: "t-42", orderId: "o-9001" })
  .explain("executionStats");

db.orders.explain("executionStats").aggregate([
  { $match: { tenantId: "t-42" } },
  { $sort: { createdAt: -1 } },
  { $limit: 50 }
]);
```

Với aggregation, đọc:

- `shards`: shard nào thực sự làm việc;
- `splitPipeline`: stage nào chạy tại shard và stage nào merge;
- `mergeType`/`mergeShard`: merge ở router hay một shard;
- `totalKeysExamined`, `totalDocsExamined`, returned rows và latency.

Có shard key trong filter vẫn có thể chạm nhiều shard tùy operator, selectivity và current distribution. Query theo prefix của compound key có thể target một subset, không bảo đảm đúng một shard.

### 9.4. Write cần routing rõ

`updateMany()`/`deleteMany()` có thể broadcast nếu filter không target được. Với single-document update/delete, tuân thủ điều kiện routing của đúng method và ưu tiên equality trên full shard key:

```javascript
db.orders.updateOne(
  { tenantId: "t-42", orderId: "o-9001" },
  { $set: { status: "PAID" } }
);
```

Đừng dựa vào `_id` duy nhất để giả định router luôn biết shard chứa document nếu `_id` không nằm trong shard key.

---

## 10. Shard key, missing field và uniqueness

### 10.1. Missing shard key field

Document có thể thiếu một field của shard key. Theo mặc định, missing key được đặt trong cùng range với shard key `null`.

Điều này không có nghĩa schema nên cho phép missing tùy ý:

- missing/`null` có thể tạo frequency skew;
- query equality với `null` có semantics dễ nhầm;
- backfill sang non-null có thể làm document đổi shard.

Enforce required fields bằng application validation và schema validator khi business invariant yêu cầu.

### 10.2. Shard key value có thể đổi

Shard key không hoàn toàn immutable. Có thể update shard key value nếu field không phải immutable `_id`, nhưng:

- operation phải đi qua `mongos`;
- phải đáp ứng routing/transaction hoặc retryable-write requirements;
- nếu range mới thuộc shard khác, document phải được chuyển;
- cập nhật thường xuyên tạo thêm chi phí và thường là dấu hiệu key không ổn định.

### 10.3. Unique index trong sharded collection

MongoDB chỉ enforce unique index trên toàn cluster khi **full shard key là prefix** của unique index.

```javascript
// Shard key: { tenantId: 1 }
db.users.createIndex(
  { tenantId: 1, email: 1 },
  { unique: true }
);
```

Constraint này bảo đảm unique cho cặp `(tenantId, email)`, không bảo đảm `email` global unique giữa mọi tenant.

Nếu `_id` không phải shard key hoặc prefix phù hợp, `_id` index chỉ enforce uniqueness cục bộ trên mỗi shard. Dùng ObjectId/UUID sinh toàn cục hoặc một registry riêng nếu application cần global uniqueness.

---

## 11. Balancer: cân data range, không cân mọi loại load

Kiểm tra bằng public admin surface:

```javascript
sh.status();
sh.getBalancerState();
sh.isBalancerRunning();
sh.balancerCollectionStatus("sales.orders");
db.getSiblingDB("sales").orders.getShardDistribution();
```

Không xây dashboard mới bằng cách phụ thuộc schema nội bộ của `config.chunks`; schema metadata có thể thay đổi giữa phiên bản.

Balancer cố sửa range imbalance và tôn trọng zones. Nó không biết business SLA và không tự bảo đảm:

- CPU từng shard bằng nhau;
- hot tenant được chia đều;
- cache hit ratio giống nhau;
- query broadcast trở thành targeted.

### 11.1. Có nên dùng balancing window?

Mặc định hãy để balancer chạy. Chỉ đặt window nếu migration đã được chứng minh gây ảnh hưởng và window đủ dài để xử lý lượng data phát sinh:

```javascript
use config

db.settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "23:00", stop: "06:00" } } },
  { upsert: true }
);
```

Self-managed dùng timezone của config server primary; Atlas dùng UTC. Window quá ngắn làm debt tích lũy và hôm sau càng khó cân bằng.

Tạm dừng cho maintenance:

```javascript
sh.stopBalancer();
sh.getBalancerState();

// Sau maintenance:
sh.startBalancer();
```

Migration đang chạy có thể hoàn tất trước khi balancer dừng. Từ MongoDB 7.0, dừng balancer cũng dừng AutoMerger; phải có owner và deadline bật lại.

---

## 12. Zones: placement policy, không phải compliance trọn gói

Ví dụ shard key:

```javascript
{ region: 1, tenantId: 1 }
```

Gán shard vào zone:

```javascript
sh.addShardToZone("eu-rs-01", "EU");
sh.addShardToZone("eu-rs-02", "EU");
sh.addShardToZone("us-rs-01", "US");
```

Định nghĩa range bằng đúng shard-key shape:

```javascript
sh.updateZoneKeyRange(
  "app.users",
  { region: "EU", tenantId: MinKey() },
  { region: "EU", tenantId: MaxKey() },
  "EU"
);
```

Zone range dùng lower inclusive, upper exclusive. Field địa lý thường phải là prefix của compound shard key. Với hashed field, bounds là hashed value chứ không phải giá trị business ban đầu.

Checklist zone:

- ít nhất hai shard/capacity domain trong zone nếu cần HA và scale;
- không để gap/overlap ngoài ý muốn;
- kiểm tra `sh.balancerCollectionStatus(namespace)`;
- dự trù capacity khi một shard trong zone mất;
- xác minh backup, logs, keys, analytics và support access cũng tuân thủ residency.

Zone chỉ điều khiển placement do balancer thực hiện. Nó không tự biến toàn hệ thống thành compliant.

---

## 13. Jumbo / indivisible range

Range lớn nhưng không thể split thường xuất hiện khi một shard key value lặp lại quá nhiều:

```text
Shard key = { tenantId: 1 }
tenantId = "whale" chiếm 40% collection
```

Một unique shard key value không thể nằm đồng thời trong hai range, nên thêm shard không chia được chính giá trị `"whale"`.

Runbook:

1. xác nhận đây là size imbalance hay traffic hotspot;
2. đo frequency/cardinality và tìm hot key;
3. xem range có bị zone/capacity constraint không;
4. chọn refine key hoặc reshard;
5. chỉ manual move/force-jumbo khi có maintenance plan và hiểu write-block risk;
6. kiểm tra lại routing và load sau thay đổi.

Không xóa cờ jumbo chỉ để dashboard “xanh”. Nếu root cause còn nguyên, range lại lớn hoặc migration lại thất bại.

---

## 14. Refine, reshard, update key hay unshard?

| Nhu cầu | Công cụ | Điểm cần nhớ |
|---|---|---|
| Thêm suffix, giữ prefix hiện tại | `refineCollectionShardKey` | Metadata đổi; data không tự redistrib ngay |
| Đổi hẳn key/distribution | `reshardCollection` | Clone song song, oplog catch-up, commit có write block ngắn |
| Sửa key của một document | `updateOne`/transaction hoặc retryable write | Có thể chuyển document sang shard khác |
| Bỏ sharding, gom về một shard | `unshardCollection` | Có từ 8.0; resource-intensive và cần bỏ zones trước |
| Chuyển unsharded collection | `moveCollection` | Có từ 8.0; không biến collection thành sharded |

### 14.1. Refine shard key

Từ:

```javascript
{ tenantId: 1 }
```

thành:

```javascript
{ tenantId: 1, orderId: 1 }
```

```javascript
db.orders.createIndex({ tenantId: 1, orderId: 1 });

db.adminCommand({
  refineCollectionShardKey: "sales.orders",
  key: { tenantId: 1, orderId: 1 }
});
```

Refine chỉ thêm suffix, không bỏ hoặc đổi prefix. Supporting index phải đáp ứng yêu cầu về partial/sparse/collation; unique shard-key index cũ cần xử lý riêng theo quy tắc unique. Quan trọng nhất: refine metadata **không lập tức di chuyển data**, nên tiếp tục theo dõi balancer/ranges.

### 14.2. Reshard collection

```javascript
db.adminCommand({
  reshardCollection: "sales.orders",
  key: { region: 1, customerId: "hashed" }
});
```

Resharding:

1. chọn donor và recipient;
2. recipient clone dữ liệu theo key mới;
3. catch up concurrent writes;
4. vào critical section ngắn để commit metadata;
5. cleanup state cũ sau đó.

Trước khi chạy:

- estimate extra disk trên mọi donor/recipient;
- bảo đảm oplog, network, CPU, cache và IOPS headroom;
- kiểm tra supporting indexes và free space;
- tạm hoãn index builds cùng collection;
- xác minh ảnh hưởng search index/change stream/client timeout;
- đặt abort threshold theo replication lag, latency và disk;
- diễn tập backup/restore và rollback ở staging.

Có thể abort trước commit; khi đã vào commit phase thì không coi abort là rollback plan. Trong MongoDB 8.2, `numInitialChunks` bị bỏ qua khi key có hashed prefix.

---

## 15. Unsharded collection vẫn có placement

Trong sharded database, unsharded collection vẫn nằm trên một shard. Trước MongoDB 8.0, khái niệm primary shard của database đặc biệt quan trọng cho placement này.

MongoDB 8.0+ có:

```javascript
use admin

sh.moveCollection("sales.countries", "shard02");
sh.unshardCollection("sales.small_orders", "shard02");
```

Dùng đúng primitive:

- `moveCollection`: di chuyển một unsharded collection;
- `unshardCollection`: gom sharded collection và bỏ shard key;
- `movePrimary`: thay primary shard của database, không phải shortcut an toàn để chuyển mọi collection.

Các thao tác topology này cạnh tranh disk/network với workload và thường không chạy đồng thời được với resharding/remove-shard khác. Đọc đúng compatibility/limitations của minor version trước change window.

---

## 16. Transactions, `$lookup` và change streams

### 16.1. Distributed transaction

Transaction có write trên nhiều shard cần coordination và two-phase commit. Vì vậy:

- latency và failure surface lớn hơn single-shard transaction;
- transaction dài giữ snapshot/history và làm migration khó hơn;
- participant càng nhiều, commit càng đắt;
- shard key tốt và data model tốt vẫn là cách giảm distributed work chính.

MongoDB hỗ trợ distributed transaction; “được hỗ trợ” không đồng nghĩa nên dùng làm default cho mọi workflow. Giữ transaction ngắn, targeted và retry đúng error labels như bài [Transactions](../fundamentals/transactions.md).

### 16.2. `$lookup`

Từ MongoDB 5.1, `from` collection có thể là sharded. Chi phí thực tế phụ thuộc:

- input cardinality;
- join-key index;
- shard key/routing của foreign side;
- pipeline placement và merge point.

Không nên kết luận mọi `$lookup` sharded đều fan-out theo cùng một cách. Dùng aggregation `explain()` để xem `shards`, `splitPipeline` và `mergeType`; cân nhắc embedding/materialized view nếu hot path join nhiều và fan-out lớn.

### 16.3. Change streams

Change stream trên cluster phải merge event từ các shard. Consumer vẫn cần resume token, idempotency và oplog window đủ dài. Khi thêm/remove shard hoặc reshard, diễn tập consumer recovery thay vì giả định stream không bị ảnh hưởng vận hành.

---

## 17. Monitoring production

### 17.1. Bốn lớp signal

| Lớp | Signal cần theo dõi |
|---|---|
| Routing | targeted/broadcast ratio, shards per query, slow query shapes |
| Distribution | data/range count, bytes, read/write ops, hot keys theo shard |
| Movement | migration rate/failure, balancer status, range deletion, reshard progress |
| Topology | replica health/lag/elections, config server health, `mongos` errors/version |

Thêm resource metrics:

- CPU, disk latency/queue, IOPS, network;
- WiredTiger cache pressure và eviction;
- connection/session/transaction count;
- oplog window và replication lag từng shard;
- free disk cho migration, index build và resharding.

Đừng chỉ alert “chunk count lệch”. Hai shard có cùng số range nhưng một shard có thể giữ whale tenant và 90% QPS.

### 17.2. Kiểm tra định kỳ

```javascript
sh.status();
sh.balancerCollectionStatus("sales.orders");
db.getSiblingDB("sales").orders.getShardDistribution();

db.getSiblingDB("sales").runCommand({
  checkMetadataConsistency: 1,
  checkIndexes: true
});
```

`checkMetadataConsistency` hữu ích sau topology/index change; vẫn phải đọc output và xử lý theo loại inconsistency, không tự động “fix all”.

---

## 18. Runbook sự cố

### 18.1. Một shard nóng

1. so CPU/I/O/cache/QPS giữa shards;
2. lấy top slow/query shapes và số shard mỗi operation chạm;
3. phân biệt hot key, monotonic inserts, index thiếu hay range imbalance;
4. xem zone có khóa range trong một capacity pool nhỏ không;
5. giảm traffic/batch/reporting nếu đang nguy hiểm;
6. xử lý gốc bằng index, rate limit, refine hoặc reshard;
7. thêm shard chỉ khi key thực sự cho phép phân phối thêm.

### 18.2. Broadcast tăng đột biến

1. xác định deploy/query shape nào thay đổi;
2. chạy `explain()` với representative parameters;
3. kiểm tra filter có mất shard-key equality/prefix không;
4. kiểm tra type/collation và pipeline stage order;
5. rollback query regression hoặc thêm lookup path có target;
6. chỉ reshard sau khi chứng minh access pattern đã thay đổi bền vững.

### 18.3. Migration chậm hoặc thất bại

1. kiểm tra donor/recipient replica health và lag;
2. kiểm tra disk, network, cache, active transaction/index build;
3. xác nhận balancer/zone/maintenance state;
4. tìm jumbo/indivisible range;
5. không restart hàng loạt hay force move khi chưa biết phase;
6. giảm competing workload rồi retry theo public admin command.

### 18.4. Gỡ một shard

`removeShard` là drain workflow, không phải tắt node:

1. bảo đảm balancer đang bật và cluster còn đủ capacity;
2. bắt đầu remove/drain;
3. theo dõi remaining ranges;
4. chuyển unsharded collections còn nằm trên shard bằng `moveCollection`;
5. xử lý jumbo/zone constraints;
6. chỉ decommission khi command báo hoàn tất;
7. nếu re-add về sau, tuân thủ yêu cầu clean data path.

### 18.5. Config server hoặc `mongos` có vấn đề

- ứng dụng còn `mongos` endpoint khỏe không?
- config server replica set còn majority và disk ổn không?
- có version skew hoặc DNS/TLS/auth regression không?
- có metadata refresh/stale routing error tăng không?
- đừng trực tiếp sửa collection trong `config` để “chữa nhanh”.

---

## 19. Anti-patterns

### “Mọi query bắt buộc chứa shard key”

Quá tuyệt đối. Hot OLTP path nên targeted; analytical scatter-gather có thể hợp lý nếu có budget và isolation.

### “Hashed key luôn chia đều”

Hash giảm monotonicity nhưng không sửa một giá trị lặp lại quá nhiều, traffic skew hoặc query không có key.

### “Thêm shard sẽ chữa hot tenant”

Sai nếu toàn bộ tenant vẫn là một indivisible shard-key value.

### “Data bytes đều nghĩa là load đều”

Traffic, working set, index size, document shape và transaction participants mới quyết định load thật.

### “Tắt balancer để cluster ổn định”

Tắt lâu làm migration debt và imbalance tăng. Chỉ dừng có thời hạn, có owner và tiêu chí bật lại.

### “Shard key không bao giờ đổi được”

MongoDB hiện hỗ trợ refine, reshard và update shard-key value với điều kiện cụ thể. Nhưng thay đổi vẫn là operation đắt và phải chuẩn bị như production migration.

### “Sửa trực tiếp `config.chunks` hoặc force move là runbook”

Metadata là phần lõi consistency. Ưu tiên public commands và support procedure; thao tác nội bộ tùy tiện có thể làm hỏng cluster.

---

## 20. Production checklist

### Trước khi shard

- [ ] Bottleneck và growth forecast đã được đo.
- [ ] Index/schema/query đã tối ưu trước.
- [ ] Có access-pattern inventory kèm QPS, SLA và payload.
- [ ] Candidate key được đánh giá cardinality, frequency, monotonicity và routing.
- [ ] Đã dùng `analyzeShardKey`/query sampling hoặc workload replay tương đương.
- [ ] Unique, missing/null và update-key semantics đã được chấp nhận.
- [ ] Đã test whale tenant, peak traffic và failure capacity.

### Triển khai

- [ ] Mỗi shard replica set và config server có failure-domain design đúng.
- [ ] Ứng dụng chỉ kết nối qua nhiều `mongos`.
- [ ] TLS, authentication, authorization và secrets đã sẵn sàng.
- [ ] Index hỗ trợ shard key đã tồn tại và nhất quán.
- [ ] Disk/network/oplog/cache headroom đủ cho initial redistribution.
- [ ] Zones có bounds, redundancy và capacity đúng.
- [ ] Có abort criteria, maintenance owner và communication plan.

### Sau triển khai

- [ ] `explain()` xác nhận hot paths target đúng số shard.
- [ ] Data, QPS, CPU, I/O và cache được so giữa các shard.
- [ ] Balancer, migration, range deletion và jumbo được alert.
- [ ] Replica lag/oplog window được theo dõi cho từng shard.
- [ ] Backup nhất quán toàn cluster và restore drill đã chạy.
- [ ] Runbook add/remove shard, reshard và config-server incident đã diễn tập.

---

## 21. Tóm tắt

1. Sharding chia ownership theo shard-key ranges; nó không thay index/schema design.
2. Shard key tốt phải cân bằng routing, cardinality, frequency, monotonicity và locality.
3. Đo candidate bằng workload thật và `analyzeShardKey`, không chọn theo trực giác.
4. Targeted query là mục tiêu của hot path; broadcast analytics có thể có chủ đích.
5. Balancer cân ranges, không tự cân hot tenant, CPU hay cache.
6. Refine thêm suffix; reshard đổi distribution; cả hai cần capacity/runbook.
7. Zone là placement policy, không phải toàn bộ compliance solution.
8. Backup, security và restore nhất quán càng quan trọng khi topology có nhiều shard.

---

## Tài liệu chính thức

- [Sharding](https://www.mongodb.com/docs/v8.2/sharding/)
- [Sharded Cluster Components](https://www.mongodb.com/docs/v8.2/core/sharded-cluster-components/)
- [Config Shard](https://www.mongodb.com/docs/v8.2/core/config-shard/)
- [Choose a Shard Key](https://www.mongodb.com/docs/v8.2/core/sharding-choose-a-shard-key/)
- [`analyzeShardKey`](https://www.mongodb.com/docs/v8.2/reference/method/db.collection.analyzeshardkey/)
- [Routing with mongos](https://www.mongodb.com/docs/v8.2/core/sharded-cluster-query-router/)
- [Data Partitioning with Chunks](https://www.mongodb.com/docs/v8.2/core/sharding-data-partitioning/)
- [Zones](https://www.mongodb.com/docs/v8.2/core/zone-sharding/)
- [Refine a Shard Key](https://www.mongodb.com/docs/v8.2/core/sharding-refine-a-shard-key/)
- [`reshardCollection`](https://www.mongodb.com/docs/v8.2/reference/command/reshardcollection/)
- [Moveable Collections](https://www.mongodb.com/docs/v8.2/core/moveable-collections/)
- [`unshardCollection`](https://www.mongodb.com/docs/v8.2/reference/command/unshardcollection/)
- [Manage the Balancer](https://www.mongodb.com/docs/v8.2/tutorial/manage-sharded-cluster-balancer/)
- [Operational Restrictions in Sharded Clusters](https://www.mongodb.com/docs/v8.2/core/sharded-cluster-requirements/)

---

## Đọc tiếp

> [Backup & Security](backup_security.md): backup nhất quán cho replica set/sharded cluster, PITR, restore drill, RBAC, TLS, encryption và auditing.

*Cập nhật lần cuối: 2026-07-29*
