# Redis Fundamentals

> Tài liệu lấy **Redis Open Source 8.8** làm mốc. Những tính năng chỉ có từ Redis 8.x được ghi rõ để tránh nhầm khi làm việc với hệ thống 6.x/7.x.
>
> Mục tiêu của bài là xây mental model đúng: Redis lưu gì, command thực thi thế nào, chọn data type nào, TTL hoạt động ra sao và persistence bảo vệ được đến đâu.

## 1. Redis là gì?

Redis là một **in-memory data structure server**. Có thể hình dung Redis như một bảng ánh xạ rất lớn:

```text
key (chuỗi byte)  ──>  value có kiểu dữ liệu

session:8f21      ──>  String
user:42           ──>  Hash
online-users      ──>  Set
game:leaderboard  ──>  Sorted Set
orders:events     ──>  Stream
```

Điểm khác biệt quan trọng so với một key-value store chỉ lưu chuỗi là Redis hiểu cấu trúc của value. Vì vậy ứng dụng có thể yêu cầu Redis:

- tăng counter mà không cần `GET` rồi `SET`;
- thêm member duy nhất vào Set;
- lấy top 10 từ Sorted Set;
- cập nhật một field trong Hash;
- giao entry mới cho consumer group của Stream.

Các operation này được xử lý ở phía server, giảm round trip và tránh nhiều race condition phổ biến.

### 1.1 Redis có thể đóng vai trò gì?

| Vai trò | Ví dụ | Điều kiện |
|---|---|---|
| **Cache** | Cache product, permission, query result | Chấp nhận cache miss và có nguồn dữ liệu gốc |
| **Ephemeral store** | Session, OTP, idempotency key | TTL, memory limit và failure semantics rõ ràng |
| **Data structure server** | Counter, leaderboard, rate limiter | Chọn đúng data type và command atomic |
| **Streaming/messaging** | Event log bằng Stream | Có retention, consumer group, ack và recovery |
| **Primary data store** | Trạng thái realtime cần latency thấp | Phải thiết kế persistence, replication, backup và DR |
| **Search/vector/time-series** | Search document, metric, embedding | Dùng capability Redis 8 phù hợp và sizing theo memory |

Redis không tự động là lựa chọn đúng chỉ vì “nhanh”. Nếu dữ liệu cần join phức tạp, transaction nhiều bảng, lịch sử lâu dài hoặc vượt xa dung lượng RAM, một database khác có thể phù hợp hơn.

### 1.2 Phiên bản và giấy phép

Từ Redis 8, Redis Community Edition được gọi là **Redis Open Source**. Redis 8 tích hợp JSON, Search, Time Series, probabilistic data structures và các capability trước đây thường được cài như module riêng.

Redis 8 trở lên cung cấp ba lựa chọn giấy phép: AGPLv3, SSPLv1 hoặc RSALv2. Khi nhúng, phân phối lại hoặc cung cấp Redis như dịch vụ, cần để bộ phận pháp lý kiểm tra lựa chọn giấy phép phù hợp; tài liệu kỹ thuật này không thay thế tư vấn pháp lý.

---

## 2. Khi nào nên và không nên dùng Redis?

### 2.1 Nên cân nhắc Redis khi

- cần latency thấp và dữ liệu làm việc vừa trong memory budget;
- có access pattern theo key rõ ràng;
- cần TTL tự động;
- cần counter, set membership hoặc ranking atomic;
- cần chia sẻ session/state giữa nhiều instance;
- cần cache để giảm tải database/downstream;
- cần event stream nhỏ hoặc vừa với consumer group;
- cần thao tác server-side trên JSON, time series hoặc vector.

### 2.2 Không nên mặc định dùng Redis khi

- dữ liệu lớn nhưng ít được truy cập và chi phí RAM không hợp lý;
- cần relational constraint, join hoặc ad-hoc query phức tạp;
- cần transaction ACID xuyên nhiều entity/shard;
- cần event log có retention dài và replay ở quy mô rất lớn;
- không chấp nhận mất dữ liệu nhưng chưa có persistence, backup và HA;
- workload có command O(N) trên collection rất lớn;
- một key duy nhất trở thành hot key không thể phân tán.

### 2.3 Ba câu hỏi phải trả lời trước

1. **Redis là cache hay source of truth?**
2. **Mất instance gần nhất có thể mất bao nhiêu dữ liệu?**
3. **Khi memory đầy, được phép evict key hay phải từ chối write?**

Nếu chưa trả lời được ba câu này, chưa nên chọn persistence và eviction policy.

---

## 3. Redis xử lý command như thế nào?

### 3.1 Đường đi của một request

```text
Application
    │  RESP request qua TCP/TLS
    ▼
Redis network I/O
    │
    ▼
Parse command → kiểm tra quyền/type → thực thi trên keyspace → tạo response
    │
    ▼
Application nhận RESP response
```

Client thường giữ connection sống lâu. Mở connection mới cho từng command vừa tốn TCP/TLS handshake, vừa làm tăng file descriptor và latency.

### 3.2 “Single-threaded” cần hiểu đúng

Cách nói “Redis là single-threaded” chỉ đúng một phần:

- command truy cập keyspace truyền thống được sắp thứ tự và thực thi theo semantics không xen ngang trên một shard;
- Redis có thread cho network I/O và nhiều công việc nền;
- RDB/AOF rewrite thường dùng child process;
- lazy free có thể giải phóng object trên background thread;
- Search và một số capability Redis 8 có worker riêng.

Điều quan trọng với developer là: **một command chậm có thể làm tăng latency của nhiều client dùng cùng shard**. Redis nhanh không có nghĩa mọi command đều O(1).

Ví dụ nguy hiểm:

```text
KEYS *
HGETALL một-hash-rất-lớn
SMEMBERS một-set-rất-lớn
LRANGE một-list-rất-lớn 0 -1
Lua/Function chạy vòng lặp lâu
```

### 3.3 Atomic command nghĩa là gì?

Một command như:

```bash
INCR inventory:reserved
```

không bị command khác chen vào giữa phần đọc và phần ghi của chính operation đó. Đây là atomicity ở phạm vi command.

Nó **không có nghĩa**:

- dữ liệu đã `fsync` xuống disk;
- replica đã nhận write;
- nhiều command gửi riêng lẻ tạo thành transaction;
- logic xuyên Redis và database khác là atomic;
- retry command sẽ không tạo side effect lặp.

Hãy dùng command nguyên tử có sẵn thay vì tự ghép `GET` → tính toán → `SET`.

### 3.4 Latency không chỉ đến từ Redis

```text
latency tổng
= network
+ connection/TLS
+ queueing
+ command execution
+ serialization/deserialization
+ client thread scheduling
```

Vì vậy không dùng một con số “ops/second” chung cho mọi hệ thống. Benchmark phải có payload, data type, persistence, pipeline, TLS và topology giống production.

---

## 4. Keyspace và cách đặt key

### 4.1 Key là binary-safe nhưng nên dễ quan sát

Redis chấp nhận chuỗi byte làm key, nhưng production nên dùng convention đọc được:

```text
<service>:<environment>:<entity>:<id>[:<attribute>]

catalog:prod:product:42
identity:prod:session:8f21
checkout:prod:idempotency:request-123
```

Lợi ích:

- tránh collision giữa service/môi trường;
- dễ tìm bằng `SCAN MATCH`;
- dễ phân quyền bằng ACL pattern;
- dễ đọc trong metrics, logs và Redis Insight.

Key quá dài làm tốn memory vì tên key cũng được giữ trong RAM. Key quá ngắn và mơ hồ lại khó vận hành. Chọn mức chi tiết vừa đủ.

### 4.2 Một key chỉ có một data type tại một thời điểm

```bash
SET user:42 "Alice"
HSET user:42 name "Alice"
# (error) WRONGTYPE ...
```

Kiểm tra type:

```bash
TYPE user:42
OBJECT ENCODING user:42
```

Application nên coi data type là một phần của schema. Đừng để hai phiên bản service dùng cùng key nhưng khai báo hai kiểu khác nhau.

### 4.3 Logical database không phải security boundary

Standalone Redis thường có nhiều logical database (`SELECT 0`, `SELECT 1`...), nhưng:

- chúng dùng chung process, memory và persistence;
- không cung cấp isolation tài nguyên;
- Redis Cluster chỉ hỗ trợ database 0;
- key có thể trùng tên giữa logical database làm vận hành khó hiểu.

Production thường dùng database 0 và prefix key rõ ràng. Khi cần security/resource isolation, dùng instance/cluster riêng hoặc kiến trúc multi-tenant được hỗ trợ.

### 4.4 Big key và hot key

- **Big key**: một key chiếm nhiều memory hoặc chứa collection quá lớn.
- **Hot key**: một key nhận tỷ lệ traffic quá cao.

Một key có thể nhỏ nhưng rất hot, hoặc lớn nhưng ít truy cập. Cả hai đều có thể làm một shard mất cân bằng.

Không có ngưỡng “big” đúng cho mọi hệ thống. Hãy đánh giá theo:

- bytes của key/value;
- số phần tử;
- độ phức tạp command;
- thời gian serialize/network;
- tần suất truy cập;
- thời gian xóa/expire.

---

## 5. Chọn data type

| Nhu cầu | Data type thường phù hợp | Ví dụ |
|---|---|---|
| Giá trị đơn, counter, lock token | String | session token, feature flag |
| Object phẳng, cập nhật từng field | Hash | user profile, cart summary |
| Object lồng nhau | JSON | product document |
| Queue/stack/deque đơn giản | List | recent items, buffer ngắn |
| Tập unique, membership | Set | roles, tags, online users |
| Ranking/range theo score | Sorted Set | leaderboard, delayed item |
| Append-only log, nhiều consumer | Stream | domain event, worker group |
| Random access theo integer index | Array, từ Redis 8.8 | sparse series, ring buffer |
| Bit theo offset | Bitmap/Bitfield trên String | daily active user |
| Đếm unique xấp xỉ | HyperLogLog | unique visitor |
| Tọa độ và khoảng cách | Geospatial | cửa hàng gần nhất |
| Metric theo thời gian | Time Series | CPU, temperature |
| Membership/frequency xấp xỉ | Probabilistic | Bloom, Cuckoo, Top-K |
| Vector similarity | Vector Set | semantic search, recommendation |

Chọn data type theo operation cần chạy, không chỉ theo hình dạng dữ liệu.

---

## 6. Các data type nền tảng

### 6.1 String

String là chuỗi byte, dùng cho text, JSON tự serialize, binary, số nguyên, số thực và bitmap.

```bash
# Ghi và đọc
SET catalog:product:42 '{"name":"Keyboard","price":50}' EX 300
GET catalog:product:42

# Chỉ tạo nếu chưa tồn tại
SET checkout:idempotency:req-123 processing NX EX 60

# Chỉ cập nhật nếu đã tồn tại
SET feature:new-checkout enabled XX KEEPTTL

# Counter atomic
INCR metrics:login:success
INCRBY inventory:reserved 5

# Nhiều key string trong một round trip
MGET feature:a feature:b feature:c
MSET feature:a on feature:b off
```

`SET` thông thường overwrite value và xóa TTL cũ. Dùng `KEEPTTL` nếu thật sự muốn giữ thời hạn.

Redis 8.4 bổ sung điều kiện compare-and-set cho `SET` như `IFEQ`; chúng hữu ích khi cập nhật value chỉ nếu phiên bản cũ vẫn đúng. Với hệ thống cũ hơn, dùng `WATCH`/`MULTI`/`EXEC` hoặc Lua/Function theo use case.

**Dùng String khi:**

- đọc/ghi toàn bộ object là đủ;
- cần counter atomic;
- value là opaque blob do ứng dụng quản lý.

**Không nên dùng một JSON string lớn khi** thường xuyên chỉ sửa một field; Hash hoặc JSON native phù hợp hơn.

### 6.2 Hash

Hash lưu các cặp field-value bên trong một key:

```bash
HSET identity:user:42 name "An" age 28 plan "pro"
HGET identity:user:42 name
HMGET identity:user:42 name plan
HINCRBY identity:user:42 login_count 1
HDEL identity:user:42 legacy_field
HLEN identity:user:42
```

Hash phù hợp object phẳng. Field value vẫn là string; Hash không tạo object lồng nhau như JSON.

Với hash lớn:

```bash
HSCAN identity:user:42 0 MATCH "pref:*" COUNT 100
```

Không mặc định dùng `HGETALL` nếu số field không bị giới hạn.

Redis hiện đại hỗ trợ TTL cho từng hash field:

```bash
HSET identity:user:42 otp "184205"
HEXPIRE identity:user:42 300 FIELDS 1 otp
```

TTL của field và TTL của cả key là hai lớp khác nhau. Hãy kiểm tra client library/version trước khi dùng tính năng mới này.

### 6.3 List

List là sequence có thứ tự, tối ưu thao tác ở hai đầu:

```bash
RPUSH notifications:user:42 n1 n2 n3
LPOP notifications:user:42
LRANGE notifications:user:42 0 9
LLEN notifications:user:42
LTRIM notifications:user:42 0 99

# Chờ phần tử mới
BLPOP jobs:thumbnail 5
```

Các operation theo index giữa list có thể là O(N):

```bash
LINDEX my-list 500000
LINSERT my-list BEFORE pivot value
```

List phù hợp queue/stack đơn giản và recent-items buffer. Nếu cần consumer group, acknowledgement, pending list, replay hoặc retention rõ ràng, dùng Stream thay vì tự xây protocol phức tạp trên List.

### 6.4 Set

Set chứa member duy nhất, không bảo đảm thứ tự:

```bash
SADD auth:user:42:roles admin editor
SISMEMBER auth:user:42:roles admin
SMISMEMBER auth:user:42:roles admin viewer
SREM auth:user:42:roles editor
SCARD auth:user:42:roles

SINTER project:1:members project:2:members
SUNION team:a team:b
SDIFF all-users blocked-users
```

Set phù hợp:

- membership;
- tag;
- quan hệ many-to-many đơn giản;
- union/intersection/difference.

Set operation trên collection lớn vẫn tốn CPU và có thể tạo response lớn. Khi chỉ cần cardinality giao nhau, ưu tiên command trả count thay vì tải toàn bộ member về client.

### 6.5 Sorted Set

Sorted Set chứa member duy nhất cùng score:

```bash
ZADD game:leaderboard 1200 alice 980 bob 1450 carol
ZINCRBY game:leaderboard 25 alice

# Top 10, cao xuống thấp
ZRANGE game:leaderboard 0 9 REV WITHSCORES

# Theo khoảng score
ZRANGE game:leaderboard 1000 2000 BYSCORE WITHSCORES

ZRANK game:leaderboard alice
ZSCORE game:leaderboard alice
ZREM game:leaderboard bob
```

Use case:

- leaderboard;
- priority queue;
- schedule/delayed item với score là timestamp;
- sliding-window rate limit;
- index theo thời gian.

Nếu nhiều member có cùng score, Redis dùng thứ tự từ điển của member để phân định. Score là số floating-point; không nhét timestamp/sequence vượt độ chính xác an toàn rồi kỳ vọng ordering tuyệt đối.

### 6.6 Stream

Stream là append-only log. Mỗi entry có ID và nhiều field-value:

```bash
XADD orders:events MAXLEN ~ 1000000 * \
  event_id evt-101 \
  type order.created \
  order_id 42

XRANGE orders:events - + COUNT 10
XREAD COUNT 10 BLOCK 5000 STREAMS orders:events $
```

`MAXLEN ~` dùng approximate trimming, thường hiệu quả hơn trim chính xác.

#### Consumer group mental model

```text
Stream
  ├── Group billing
  │     ├── consumer-1
  │     └── consumer-2
  └── Group analytics
        ├── consumer-a
        └── consumer-b
```

Mỗi group có vị trí đọc và Pending Entries List (PEL) riêng. Trong một group, entry mới được phân phối cho một consumer; các group khác nhau có thể cùng đọc entry đó.

```bash
# Tạo group và stream nếu chưa có
XGROUP CREATE orders:events billing 0 MKSTREAM

# Đọc entry chưa từng giao cho group
XREADGROUP GROUP billing consumer-1 \
  COUNT 10 BLOCK 5000 \
  STREAMS orders:events >

# Chỉ ack sau khi xử lý thành công
XACK orders:events billing 1735000000000-0

# Quan sát pending
XPENDING orders:events billing

# Consumer khác nhận lại entry bị bỏ quên
XAUTOCLAIM orders:events billing consumer-2 60000 0-0 COUNT 10
```

Consumer phải idempotent vì entry có thể được giao lại. `XACK` chỉ xóa entry khỏi PEL của group; nó không tự xóa entry khỏi Stream. Retention/trimming cần được thiết kế riêng và không được xóa entry mà group khác vẫn cần.

Redis 8.2 bổ sung `XACKDEL`/`XDELEX` để kiểm soát việc ack/xóa khi có nhiều group; Redis 8.8 bổ sung `XNACK` để consumer chủ động nhả pending entry. Chỉ dùng khi client và server đã hỗ trợ đúng phiên bản.

### 6.7 JSON

Từ Redis 8, JSON là một phần của Redis Open Source:

```bash
JSON.SET catalog:product:42 $ \
  '{"name":"Keyboard","price":50,"tags":["input","usb"]}'

JSON.GET catalog:product:42 $.name $.price
JSON.NUMINCRBY catalog:product:42 $.price 5
JSON.ARRAPPEND catalog:product:42 $.tags '"wireless"'
```

Chọn JSON khi:

- object lồng nhau;
- cần đọc/sửa theo JSONPath;
- cần index/query document bằng Redis Search.

JSON linh hoạt hơn Hash nhưng thường tốn nhiều memory/CPU hơn. Nếu object chỉ có vài field phẳng, Hash thường đơn giản hơn.

### 6.8 Array — Redis 8.8

Array là data type mới trong Redis 8.8, ánh xạ integer index tới string value. Array có thể sparse: ghi index rất lớn không cần cấp phát toàn bộ khoảng trống.

```bash
ARSET events:user:42 0 login click purchase
ARGET events:user:42 1

ARMSET samples:device:7 0 19.2 60 20.1 3600 21.0
ARMGET samples:device:7 0 60 3600

ARLEN samples:device:7
ARCOUNT samples:device:7
ARSCAN samples:device:7 0 4000
```

- `ARLEN`: index lớn nhất + 1.
- `ARCOUNT`: số slot thực sự có value.

Array phù hợp random access theo index, sparse sequence, ring buffer và aggregate theo range. List phù hợp hơn khi chỉ push/pop hai đầu; Stream phù hợp hơn khi cần consumer group và event ID.

---

## 7. Các data type chuyên biệt

### 7.1 Bitmap và Bitfield

Bitmap thực chất là String được thao tác theo bit:

```bash
# user 42 active ngày hôm nay
SETBIT activity:2026-07-29 42 1

GETBIT activity:2026-07-29 42
BITCOUNT activity:2026-07-29

# Active cả hai ngày
BITOP AND activity:both \
  activity:2026-07-28 activity:2026-07-29
```

Rất tiết kiệm khi ID là số nguyên dày. Nếu offset cực lớn nhưng dữ liệu thưa, String vẫn phải mở rộng đến offset đó; Set hoặc Array sparse có thể hợp lý hơn.

### 7.2 HyperLogLog

HyperLogLog ước tính số phần tử unique với memory nhỏ:

```bash
PFADD visitors:2026-07-29 user-1 user-2 user-3
PFCOUNT visitors:2026-07-29
PFMERGE visitors:this-week visitors:day-1 visitors:day-2
```

Kết quả là xấp xỉ, không dùng khi cần danh sách member hoặc con số tuyệt đối chính xác.

### 7.3 Geospatial

Geo index được xây trên Sorted Set:

```bash
GEOADD stores 106.7009 10.7769 store:hcm-1
GEOADD stores 105.8342 21.0278 store:hn-1

GEOSEARCH stores \
  FROMLONLAT 106.70 10.77 \
  BYRADIUS 10 km \
  ASC COUNT 20
```

Phù hợp tìm điểm gần trong bán kính/box. Redis Geo dùng kinh độ trước, vĩ độ sau; đảo thứ tự là lỗi rất phổ biến.

### 7.4 Probabilistic data structures

Redis 8 tích hợp:

| Cấu trúc | Trả lời câu hỏi |
|---|---|
| Bloom Filter | Item có thể đã xuất hiện chưa? |
| Cuckoo Filter | Membership xấp xỉ và hỗ trợ xóa |
| Count-Min Sketch | Item xuất hiện khoảng bao nhiêu lần? |
| Top-K | Những item thường gặp nhất là gì? |
| t-digest | Percentile xấp xỉ là bao nhiêu? |
| HyperLogLog | Có khoảng bao nhiêu item unique? |

Đổi lại hiệu quả memory cao là false positive hoặc sai số. Luôn ghi rõ error rate/capacity khi tạo cấu trúc.

### 7.5 Time Series

```bash
TS.CREATE metrics:cpu:node-1 \
  RETENTION 86400000 \
  LABELS host node-1 region ap-southeast

TS.ADD metrics:cpu:node-1 * 72.5
TS.RANGE metrics:cpu:node-1 - + \
  AGGREGATION avg 60000
```

Time Series phù hợp metric timestamp-value, retention và downsampling. Không nên mô phỏng mọi time series bằng Sorted Set nếu đã cần label query, aggregation và compaction.

### 7.6 Vector Set

Vector Set lưu member cùng embedding và tìm item tương tự:

```bash
VADD products:embeddings VALUES 3 0.1 0.2 0.3 product:42
VADD products:embeddings VALUES 3 0.2 0.1 0.4 product:43

VSIM products:embeddings VALUES 3 0.11 0.19 0.31 COUNT 5
```

Phù hợp semantic search/recommendation đơn giản. Vector index có memory cost đáng kể; phải đo dimension, số vector, quantization, recall và query latency.

---

## 8. TTL và expiration

### 8.1 Đặt TTL cùng lúc với value

Ưu tiên một command:

```bash
SET identity:session:8f21 user-42 EX 1800
```

Thay vì:

```bash
SET identity:session:8f21 user-42
EXPIRE identity:session:8f21 1800
```

Nếu process chết giữa hai command ở cách thứ hai, key có thể tồn tại vĩnh viễn.

### 8.2 Các command quan trọng

```bash
EXPIRE key 60
PEXPIRE key 1500
EXPIREAT key 1785283200

TTL key
PTTL key
EXPIRETIME key

PERSIST key
```

Ý nghĩa `TTL`:

| Kết quả | Ý nghĩa |
|---:|---|
| `>= 0` | Số giây còn lại |
| `-1` | Key tồn tại nhưng không có TTL |
| `-2` | Key không tồn tại |

### 8.3 Update nào giữ TTL?

- `INCR`, `LPUSH`, `HSET` cập nhật bên trong value và thường giữ TTL của key.
- `SET` overwrite toàn bộ value nên xóa TTL, trừ khi dùng `KEEPTTL`.
- `RENAME` chuyển TTL cùng key.
- `PERSIST` chủ động gỡ TTL.

TTL là một phần của schema. Test cả value lẫn TTL sau mỗi code path update.

### 8.4 Expiration khác eviction

- **Expiration**: key hết thời gian sống do TTL.
- **Eviction**: Redis chủ động loại key khi vượt `maxmemory` theo eviction policy.

Một key không có TTL vẫn có thể bị evict với policy `allkeys-*`. Một key đã có TTL vẫn có thể bị evict trước hạn. Nếu Redis là source of truth, policy cho phép evict dữ liệu là quyết định rất nguy hiểm.

---

## 9. Atomicity, transaction và server-side logic

### 9.1 Pipeline không phải transaction

Pipeline gửi nhiều command mà không chờ từng response:

```text
Không pipeline: request → response → request → response
Pipeline:       request + request + request → response + response + response
```

Pipeline giảm network round trip nhưng command của client khác vẫn có thể xen giữa. Nó không tạo atomicity.

### 9.2 MULTI/EXEC

```bash
MULTI
DECRBY inventory:sku-42 1
INCRBY orders:reserved 1
EXEC
```

Redis queue command sau `MULTI` và chạy chúng tuần tự khi `EXEC`. Nhưng:

- không có rollback kiểu relational database;
- runtime error của một command không tự đảo command trước;
- transaction không bao gồm database bên ngoài;
- trong Redis Cluster, multi-key operation thường cần các key cùng hash slot.

### 9.3 WATCH — optimistic locking

```bash
WATCH account:42
GET account:42

# Application tính value mới

MULTI
SET account:42 new-value
EXEC
```

Nếu key bị client khác sửa sau `WATCH`, `EXEC` không thực hiện transaction; application phải quyết định retry.

### 9.4 Lua script và Redis Function

Server-side logic giúp gộp read-modify-write phức tạp thành một operation atomic. Tuy nhiên:

- script/function chạy lâu chặn command khác trên shard;
- phải giới hạn input và vòng lặp;
- không gọi network/database bên ngoài từ logic atomic;
- cần version, test và quan sát latency;
- ưu tiên command built-in nếu đã có.

---

## 10. Persistence: RDB và AOF

Persistence là cách Redis ghi dữ liệu xuống durable storage để có thể nạp lại sau restart. Nó không tự động thay thế replication hoặc backup.

### 10.1 Bốn lựa chọn

| Chế độ | Cách hoạt động | Trade-off chính |
|---|---|---|
| Không persistence | Chỉ giữ trong memory | Restart mất dữ liệu; phù hợp pure cache |
| RDB | Snapshot point-in-time | Gọn, restore nhanh; có thể mất dữ liệu từ snapshot gần nhất |
| AOF | Ghi lại write command | RPO thấp hơn; tốn I/O và cần rewrite |
| RDB + AOF | Dùng cả hai | Nhiều lựa chọn recovery/backup hơn; vận hành phức tạp hơn |

### 10.2 RDB

```bash
# Chạy nền, phù hợp hơn cho production
BGSAVE

# Trạng thái
INFO persistence
LASTSAVE
```

Cấu hình ví dụ:

```text
save 3600 1
save 300 100
save 60 10000
dbfilename dump.rdb
dir /var/lib/redis
```

Redis fork child process để tạo snapshot. Parent vẫn phục vụ request, nhưng:

- `fork()` có thể gây latency;
- copy-on-write làm tăng memory khi write nhiều trong lúc snapshot;
- disk I/O có thể cạnh tranh với workload;
- container phải có memory headroom, nếu không dễ OOM kill.

`SAVE` chạy đồng bộ và chặn server; tránh dùng tùy tiện trên production.

### 10.3 AOF

```text
appendonly yes
appendfsync everysec
aof-use-rdb-preamble yes
```

`appendfsync everysec` thường có thể mất khoảng một giây write khi sự cố nghiêm trọng. `always` bền hơn nhưng latency/I/O cao hơn; `no` giao việc flush cho OS và có RPO kém hơn.

Từ Redis 7, AOF là **multi-part AOF**:

```text
appendonlydir/
├── base file
├── incremental AOF file(s)
└── manifest
```

`BGREWRITEAOF` tạo base mới gọn hơn trong khi Redis vẫn nhận write. Backup AOF phải copy cả directory nhất quán và tránh thời điểm rewrite theo hướng dẫn chính thức.

### 10.4 Khi bật cả RDB và AOF

Khi restart, Redis ưu tiên AOF vì thường chứa dataset đầy đủ hơn. Không được giả định Redis sẽ chọn RDB chỉ vì file RDB mới tồn tại.

### 10.5 Persistence không phải backup

```text
Client chạy DEL nhầm
        │
        ├── AOF ghi lại DEL
        └── replica cũng nhận DEL
```

Replication và AOF có thể nhân bản/lưu cả sai sót. Backup cần:

- bản snapshot/AOF độc lập khỏi máy Redis;
- retention nhiều phiên bản;
- mã hóa và kiểm tra checksum;
- restore test định kỳ;
- RPO/RTO rõ ràng.

Nếu Redis là primary store, persistence, replication, backup và disaster recovery phải được thiết kế cùng nhau.

---

## 11. Command an toàn trong production

### 11.1 Dùng SCAN thay KEYS

```bash
SCAN 0 MATCH "catalog:prod:product:*" COUNT 100 TYPE hash
```

`COUNT` là hint, không bảo đảm số item mỗi lần trả về. Lặp đến khi cursor trở lại `0`.

`SCAN` không phải snapshot nhất quán: key thêm/xóa trong lúc scan có thể ảnh hưởng kết quả và một số item có thể lặp. Consumer của scan phải chịu duplicate.

### 11.2 Xóa big key bằng UNLINK

```bash
UNLINK cache:huge-object
```

`UNLINK` gỡ key khỏi keyspace nhanh rồi giải phóng memory ở background. `DEL` có thể chặn lâu khi object chứa rất nhiều allocation.

### 11.3 Tránh response không giới hạn

| Rủi ro | Cách an toàn hơn |
|---|---|
| `HGETALL` hash lớn | `HSCAN` hoặc chỉ `HMGET` field cần |
| `SMEMBERS` set lớn | `SSCAN` |
| `LRANGE 0 -1` list lớn | Page/range có giới hạn |
| `ZRANGE 0 -1` zset lớn | Range/limit theo use case |
| `XRANGE - +` stream lớn | `COUNT` và cursor ID |
| `KEYS *` | `SCAN` |

### 11.4 Command quản trị nguy hiểm

`FLUSHDB`, `FLUSHALL`, `CONFIG`, `DEBUG`, `MODULE`, `MONITOR` không nên cấp cho application user. Dùng ACL để tách quyền và chặn command/category không cần thiết.

---

## 12. Lab tối thiểu

Chạy Redis 8.8 local chỉ trên loopback:

```bash
docker run --name redis-8-lab \
  -p 127.0.0.1:6379:6379 \
  -d redis:8.8
```

Kết nối:

```bash
docker exec -it redis-8-lab redis-cli
```

Thử mental model:

```bash
SET greeting "xin chao" EX 60
GET greeting
TTL greeting
TYPE greeting

HSET user:42 name "An" level 3
HINCRBY user:42 level 1
HGETALL user:42

ZADD leaderboard 100 alice 120 bob
ZRANGE leaderboard 0 -1 REV WITHSCORES

XADD events * type login user_id 42
XRANGE events - +

INFO memory
INFO persistence
```

Container trên chỉ dùng cho lab:

- không authentication/TLS;
- không mount durable volume;
- không cấu hình memory limit;
- không backup hoặc HA.

Không dùng nguyên mẫu này cho production.

---

## 13. Những hiểu lầm phổ biến

### “Redis luôn có latency dưới 1 ms”

Không có bảo đảm chung. Big key, O(N) command, fork, disk, network, TLS, queueing và client GC đều có thể tăng latency.

### “Redis single-thread nên không có race condition”

Một command có semantics atomic, nhưng chuỗi nhiều command của application vẫn có race nếu không dùng command atomic, transaction, CAS hoặc function phù hợp.

### “Bật replica là không mất dữ liệu”

Replication mặc định là bất đồng bộ. Failover có thể mất write chưa tới replica; thao tác xóa nhầm cũng được replicate.

### “Bật AOF là đã có backup”

AOF là persistence log của instance, không phải lịch sử backup độc lập.

### “Có TTL thì memory không bao giờ đầy”

TTL không bảo đảm traffic tạo key chậm hơn tốc độ expire. Big value, TTL quá dài, key không TTL và fragmentation đều có thể làm cạn memory.

### “List là job queue đáng tin cậy”

List phù hợp queue đơn giản. Khi cần ack, pending recovery, nhiều consumer group và replay, Stream cung cấp primitive rõ ràng hơn.

### “SCAN trả mỗi key đúng một lần”

SCAN có thể trả duplicate và không tạo snapshot nhất quán. Luồng xử lý phải idempotent.

---

## 14. Checklist sau bài Fundamentals

- [ ] Giải thích được Redis là key → typed value, không chỉ là cache.
- [ ] Phân biệt atomic command, pipeline và transaction.
- [ ] Chọn được String, Hash, List, Set, Sorted Set hoặc Stream theo operation.
- [ ] Biết JSON, Array, Time Series, Probabilistic và Vector Set giải quyết gì.
- [ ] Đặt TTL atomic cùng write và hiểu `TTL = -1/-2`.
- [ ] Phân biệt expiration với eviction.
- [ ] Phân biệt persistence, replication và backup.
- [ ] Hiểu RDB fork/COW và multi-part AOF.
- [ ] Tránh `KEYS`, response không giới hạn và `DEL` big key.
- [ ] Nhận diện big key, hot key và command O(N).

---

## 15. Đọc tiếp

1. [Redis High Availability](redis_ha.md) — replication, Sentinel và Cluster.
2. [Redis Performance & Internals](redis_performance.md) — memory, eviction, pipeline, transaction, scripting và monitoring.
3. [Redis Design Patterns](redis_patterns.md) — cache, rate limit, distributed lock, Stream và leaderboard.
4. [Redis Glossary](glossary.md) — tra cứu nhanh thuật ngữ.

## Tài liệu chính thức

- [Redis Open Source documentation](https://redis.io/docs/latest/)
- [Redis 8.8](https://redis.io/docs/latest/develop/whats-new/8-8/)
- [Redis data types](https://redis.io/docs/latest/develop/data-types/)
- [Compare data types](https://redis.io/docs/latest/develop/data-types/compare-data-types/)
- [Redis persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)
- [Transactions](https://redis.io/docs/latest/develop/using-commands/transactions/)
- [Key expiration](https://redis.io/docs/latest/commands/expire/)
- [Redis licenses](https://redis.io/legal/licenses/)

---

## Tổng kết

Mental model ngắn gọn:

```text
Redis = keyspace trong memory
      + value có kiểu dữ liệu
      + command server-side có semantics atomic
      + TTL/eviction để quản lý vòng đời
      + persistence/replication tùy cấu hình
```

Chọn data type theo operation, kiểm soát kích thước key/value, tránh command có chi phí không giới hạn và xác định Redis là cache hay source of truth trước khi chọn persistence. Đây là nền móng để học HA, performance và các design pattern mà không dựa vào những “best practice” thiếu ngữ cảnh.

*Cập nhật lần cuối: 2026-07-29*
