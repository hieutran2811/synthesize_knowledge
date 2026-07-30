# Redis Design Patterns

> Pattern tốt không chỉ chạy đúng khi mọi thứ khỏe. Nó phải nói rõ dữ liệu nào có thẩm quyền, operation nào atomic, có thể mất/trùng/stale điều gì và recovery ra sao. Nội dung được chuẩn hóa theo Redis Open Source 8.8.

## 1. Chọn pattern từ invariant

Trước khi chọn data type hay command, trả lời:

1. Redis là cache có thể tái tạo hay source of truth?
2. Chấp nhận stale data trong bao lâu?
3. Message được phép mất, trùng hoặc xử lý lại không?
4. Side effect có idempotent không?
5. Atomic boundary nằm trong một Redis key/slot hay qua database khác?
6. Khi client timeout, làm sao biết operation đã chạy?
7. Dữ liệu được giữ bao lâu và ai dọn?

### 1.1 Bảng chọn nhanh

| Nhu cầu | Pattern bắt đầu | Guarantee chính | Điều phải tự xử lý |
|---|---|---|---|
| Giảm tải database | Cache-aside | Staleness bị chặn bởi TTL/invalidation | Stampede, race và miss fallback |
| Fan-out realtime cho client online | Pub/Sub | At-most-once | Disconnect là mất message |
| Event có replay/consumer group | Streams | Thường at-least-once | Idempotency, retry, retention, DLQ |
| Giới hạn request | `INCREX`, sliding window hoặc token bucket | Atomic trong một key/slot | Scope, clock, fail-open/closed |
| Session dùng chung nhiều app node | Hash/String + TTL | Trạng thái server-side có expiry | Security, durability, logout/index |
| Phối hợp công việc ngắn | Lease/lock | Mutual exclusion có thời hạn | Ownership, expiry, fencing |
| Xếp hạng realtime | Sorted Set | Update/rank atomic theo member | Tie, season, hot key, retention |
| Background jobs | Streams hoặc `BLMOVE` | At-least-once nếu thiết kế recovery | Visibility timeout, retry, DLQ |
| Chạy job vào tương lai | Sorted Set scheduler | Atomic claim cần script/function | Polling/wakeup, clock, retry |

Không có pattern nào tạo transaction nguyên tử giữa Redis và PostgreSQL/Kafka/HTTP chỉ bằng pipeline.

---

## 2. Caching patterns

### 2.1 Cache-aside

Cache-aside phù hợp khi database là source of truth:

```text
READ
App -> GET cache
  hit  -> trả dữ liệu
  miss -> đọc DB -> SET cache với TTL -> trả dữ liệu

WRITE
App -> commit DB -> xóa/invalidate cache
```

Ví dụ Java ở mức khái niệm:

```java
public Product getProduct(long id) {
    String key = "cache:product:" + id;
    String cached = redis.get(key);
    if (NOT_FOUND.equals(cached)) {
        return null;
    }
    if (cached != null) {
        return codec.decode(cached);
    }

    Product product = repository.findById(id);
    if (product == null) {
        redis.set(key, NOT_FOUND, SetArgs.Builder.ex(30));
        return null;
    }

    long ttlSeconds = 300 + ThreadLocalRandom.current().nextLong(60);
    redis.set(key, codec.encode(product), SetArgs.Builder.ex(ttlSeconds));
    return product;
}

public void updateProduct(Product product) {
    repository.updateAndCommit(product);
    redis.del("cache:product:" + product.id());
}
```

Ví dụ chỉ minh họa flow. Production cần timeout, tracing, fallback budget và chống stampede.

### 2.2 Invalidation vẫn có race

“Commit DB rồi `DEL` cache” là lựa chọn đơn giản, nhưng chưa phải strong consistency:

```text
T1: cache miss, đọc DB phiên bản cũ
T2: commit DB phiên bản mới
T2: DEL cache
T1: SET lại phiên bản cũ vào cache
```

Cách giảm rủi ro tùy SLO:

- TTL ngắn để chặn thời gian stale tối đa;
- version trong value/key và không cho version cũ ghi đè version mới;
- singleflight theo key để giảm nhiều loader đồng thời;
- transactional outbox/CDC phát invalidation sau DB commit;
- cache key theo version như `product:42:v17`;
- đọc source of truth cho operation cần consistency mạnh.

Không gọi pipeline Redis sau transaction DB là “atomic write-through”; hai hệ thống vẫn có failure window.

### 2.3 Negative caching

Request cho ID không tồn tại có thể xuyên qua cache và đánh DB liên tục. Lưu sentinel ngắn hạn:

```redis
SET cache:product:missing-id __NOT_FOUND__ EX 30 NX
```

Phải phân biệt:

- cache miss: Redis không có entry;
- negative hit: đã xác nhận “không tồn tại” tại một thời điểm;
- backend error: không được cache như “không tồn tại”.

TTL negative thường ngắn hơn TTL dữ liệu thật để object mới tạo không bị ẩn quá lâu.

### 2.4 Chống cache stampede

Khi hot key hết hạn, nhiều request cùng gọi source of truth. Có thể kết hợp:

| Kỹ thuật | Cách hoạt động | Đổi lại |
|---|---|---|
| TTL jitter | Phân tán thời điểm hết hạn | Không giải quyết một hot key riêng lẻ |
| Singleflight/mutex | Một worker refresh, worker khác đợi/dùng stale | Cần lease và safe release |
| Stale-while-revalidate | Trả value cũ trong khi một worker refresh | Chấp nhận stale có giới hạn |
| Probabilistic early refresh | Một số request refresh trước hard expiry | Logic/quan sát phức tạp hơn |
| Request coalescing tại app | Gộp miss cùng key trong một process | Không phối hợp giữa nhiều app node |

Singleflight tối thiểu:

```text
1. GET cache; nếu hit thì trả.
2. SET lock:<key> <unique-token> NX PX <lease>.
3. Nếu có lock: GET cache lần hai.
4. Nếu vẫn miss: load source, SET cache.
5. Release chỉ khi token còn thuộc mình.
6. Nếu không có lock: đợi bounded, đọc lại hoặc dùng stale/fallback.
```

Redis 8.4+ hỗ trợ safe release:

```redis
SET lock:cache:product:42 7f0c... NX PX 5000
DELEX lock:cache:product:42 IFEQ 7f0c...
```

Không dùng `DEL lock-key`: lease cũ có thể đã hết và key hiện thuộc worker khác.

Stale-while-revalidate thường lưu logical expiry trong value và hard TTL dài hơn:

```text
value = {
  payload,
  fresh_until,
  stale_until
}
```

- trước `fresh_until`: trả ngay;
- giữa hai mốc: có thể trả stale, một worker refresh;
- sau `stale_until`: không trả stale, fallback theo policy.

### 2.5 Cache avalanche, penetration và breakdown

| Sự cố | Mô tả | Biện pháp |
|---|---|---|
| Avalanche | Nhiều key hết hạn/cụm cache mất cùng lúc | TTL jitter, warmup, HA, source capacity |
| Penetration | Request cho key không tồn tại luôn xuống DB | Negative cache, validation, Bloom filter khi phù hợp |
| Breakdown/stampede | Một hot key hết hạn, nhiều loader đồng thời | Singleflight, stale-while-revalidate |

Bloom filter có false positive và lifecycle riêng; nó không thay negative cache/source validation một cách tự động.

### 2.6 Write-through và write-behind

#### Write-through

Application hoặc một abstraction ghi source of truth và cập nhật cache trên write. Vì DB và Redis không cùng transaction:

- DB thành công, Redis thất bại: cache cũ/miss;
- Redis thành công, DB rollback: cache sai;
- retry có thể lặp side effect.

Nếu DB là source of truth, cách an toàn phổ biến là commit DB rồi invalidate, kết hợp outbox/CDC nếu không muốn bỏ lỡ invalidation.

#### Write-behind

Write-behind trả thành công trước khi durable store hoàn tất. Khi đó Redis/queue nằm trên đường durability:

```text
Client -> durable event/command -> trả accepted
                    |
                    v
              worker ghi DB
```

Không dùng “dirty Set rồi đọc toàn bộ, xóa Set trước khi flush”. Crash giữa xóa và ghi DB sẽ mất update.

Thiết kế thực tế cần:

- Stream hoặc durable log có message ID;
- producer idempotency;
- consumer group, retry và DLQ;
- DB upsert/idempotency key;
- ordering/version cho nhiều update cùng entity;
- backpressure khi DB chậm;
- reconciliation giữa Redis và DB.

Nếu không chấp nhận mất acknowledged write, AOF/replication thôi vẫn chưa thay thế được thiết kế end-to-end.

### 2.7 Cache warming/prefetch

Chỉ warm dữ liệu có khả năng được đọc:

- top products/config/reference data;
- chạy bounded batch và backpressure;
- version key để chuyển dataset nguyên tử ở application;
- không scan/nạp toàn database theo phản xạ;
- đo hit rate sau warmup để biết lợi ích thật.

---

## 3. Pub/Sub và Streams

### 3.1 Pub/Sub: realtime, at-most-once

```redis
SUBSCRIBE realtime:price
PUBLISH realtime:price '{"symbol":"ABC","price":"42.10"}'
```

Redis Pub/Sub:

- chỉ gửi tới subscriber đang online;
- không persist/replay/ack;
- delivery là at-most-once;
- subscriber match cả channel và pattern có thể nhận cùng message nhiều lần;
- channel namespace không bị tách theo logical database.

Phù hợp cho presence, live UI hint, cache invalidation có cơ chế tự hồi phục và WebSocket fan-out không cần replay.

Trong Cluster, global Pub/Sub lan rộng qua cluster. Sharded Pub/Sub giới hạn propagation theo shard:

```redis
SSUBSCRIBE price:{asia}
SPUBLISH price:{asia} '{"symbol":"ABC","price":"42.10"}'
```

Client phải hỗ trợ sharded Pub/Sub và route theo channel slot.

### 3.2 Pub/Sub không thay transactional event

Flow sau có cửa sổ mất event:

```text
commit DB -> process crash -> chưa PUBLISH
```

Nếu event phải tương ứng với DB commit, dùng transactional outbox:

```text
DB transaction:
  update business row
  insert outbox row

Relay:
  đọc outbox -> publish/XADD -> đánh dấu sent
```

Relay có thể publish trùng khi crash sau publish trước khi đánh dấu; consumer vẫn cần idempotency.

### 3.3 Streams: durable log và consumer group

Tạo stream/group:

```redis
XGROUP CREATE events:orders billing 0 MKSTREAM

XADD events:orders * \
  event_id evt-20260729-001 \
  type OrderPaid \
  order_id 42 \
  version 7
```

Consumer:

```redis
XREADGROUP GROUP billing billing-1 \
  COUNT 20 BLOCK 5000 \
  STREAMS events:orders >
```

Message mới được giao vào Pending Entries List (PEL). Chỉ ack sau khi side effect đã hoàn tất bền vững:

```redis
XACK events:orders billing 1770000000000-0
```

Nếu consumer crash sau ghi DB nhưng trước `XACK`, message được xử lý lại. Đây là at-least-once; handler phải idempotent.

### 3.4 Producer idempotency từ Redis 8.6

`XADD IDMP` dùng producer ID và idempotency ID:

```redis
XADD events:orders \
  IDMP checkout-service evt-20260729-001 \
  * type OrderPaid order_id 42 version 7
```

Gửi lại cùng `(producer-id, idempotency-id)` trả về entry ID cũ thay vì append bản sao trong cửa sổ dedup được cấu hình.

`IDMPAUTO` tạo ID từ nội dung:

```redis
XADD events:orders \
  IDMPAUTO checkout-service \
  * type OrderPaid order_id 42 version 7
```

Điểm cần nhớ:

- producer phải giữ cùng producer ID sau restart;
- manual ID thường rõ semantics hơn content hash;
- dedup có duration/max-size, không vô hạn;
- đổi cấu hình IDMP có thể xóa map theo dõi;
- producer dedup không làm consumer side effect trở thành idempotent.

### 3.5 Recovery với `XAUTOCLAIM`

```redis
XAUTOCLAIM events:orders billing recovery-1 \
  60000 0-0 COUNT 100
```

Command claim các pending entry idle quá 60 giây sang consumer recovery. Visibility timeout phải lớn hơn thời gian xử lý hợp lệ hoặc có heartbeat/ownership token; nếu quá ngắn, hai worker có thể cùng tạo side effect.

Theo dõi:

```redis
XPENDING events:orders billing
XINFO GROUPS events:orders
XINFO CONSUMERS events:orders billing
```

### 3.6 `XNACK` trong Redis 8.8

Consumer có thể chủ động trả pending message về group:

```redis
# Lỗi hạ tầng của consumer; consumer khác có thể thử ngay.
XNACK events:orders billing FAIL \
  IDS 1 1770000000000-0

# Graceful shutdown; “hoàn tác” lần delivery này trong counter.
XNACK events:orders billing SILENT \
  IDS 1 1770000000000-1

# Poison message; đánh dấu delivery counter tối đa để recovery/DLQ xử lý.
XNACK events:orders billing FATAL \
  IDS 1 1770000000000-2
```

`XNACK` không xóa entry và không tự chuyển payload sang DLQ. Recovery worker vẫn phải phát hiện policy rồi:

1. ghi DLQ event kèm original ID, error, attempts;
2. bảo đảm DLQ write/idempotency;
3. `XACK` hoặc `XACKDEL` original theo retention policy.

### 3.7 Retention và nhiều consumer group

Trim gần đúng để tránh Stream tăng vô hạn:

```redis
XADD events:orders MAXLEN ~ 1000000 * type OrderCreated order_id 99
XTRIM events:orders MAXLEN ~ 1000000
```

Trim entry đang còn PEL có thể để reference mà payload không còn. Redis 8.2+ thêm:

- `KEEPREF`: giữ PEL reference, tương thích hành vi cũ;
- `DELREF`: xóa cả reference;
- `ACKED`: chỉ xóa khi mọi group đã ack;
- `XACKDEL`: ack và xóa có policy trong một command.

```redis
XACKDEL events:orders billing ACKED \
  IDS 1 1770000000000-0
```

Chọn retention theo replay/recovery window và group chậm nhất, không chỉ theo memory.

### 3.8 Pub/Sub hay Streams?

| Câu hỏi | Pub/Sub | Streams |
|---|---|---|
| Subscriber offline có nhận lại? | Không | Có, trong retention |
| Delivery | At-most-once | Thường at-least-once |
| Ack/PEL | Không | Có |
| Replay | Không | Có |
| Fan-out | Mọi subscriber online | Mỗi group nhận độc lập |
| Use case | Live signal | Event processing/job workflow |

---

## 4. Rate limiting

### 4.1 Xác định policy trước

Một limiter cần ghi rõ:

- identity: user, token, IP, tenant hay endpoint;
- scope: mỗi node, toàn region hay global;
- limit/burst/window;
- clock source;
- response: allowed, remaining, reset/retry-after;
- Redis lỗi thì fail-open hay fail-closed;
- key cardinality và retention.

Không đặt toàn bộ tenant vào một key nếu một hot counter sẽ nghẽn một Cluster slot.

### 4.2 Fixed window bằng `INCREX` — Redis 8.8

```redis
INCREX ratelimit:{tenant-42}:checkout \
  BYINT 1 \
  UBOUND 100 \
  EX 60 ENX
```

Kết quả gồm `[new_value, actual_increment]`:

- `actual_increment = 1`: request được tính và cho phép;
- `actual_increment = 0`: đã chạm upper bound, key/TTL không đổi.

`ENX` chỉ đặt expiry khi key chưa có TTL nên request sau không kéo dài cửa sổ. Một command thay cho `INCR` + `EXPIRE` + script.

Fixed window đơn giản nhưng có boundary burst: client có thể gửi gần 100 request cuối cửa sổ và 100 request đầu cửa sổ kế tiếp.

### 4.3 Sliding log bằng Sorted Set

Mỗi request là một member duy nhất, score là timestamp:

```text
atomic function/script:
  now = Redis server time
  ZREMRANGEBYSCORE key -inf (now - window)
  count = ZCARD key
  if count < limit:
      ZADD key now request_id
      EXPIRE key retention
      allow
  else:
      reject + retry_after từ entry cũ nhất
```

Phải chạy atomic; pipeline riêng lẻ có race. Cost memory tỷ lệ số request trong window. Trong Cluster, mọi key script chạm tới phải cùng hash slot.

### 4.4 Token bucket

State thường gồm:

```text
tokens
last_refill_time
```

Một Function/script:

1. lấy server time;
2. refill theo thời gian đã trôi qua;
3. cap ở capacity;
4. trừ token nếu đủ;
5. trả `allowed`, `remaining`, `retry_after`.

Token bucket cho burst có kiểm soát và throughput dài hạn mượt hơn fixed window. Dùng số nguyên theo đơn vị nhỏ để tránh sai số float nếu nghiệp vụ cần chính xác.

### 4.5 Failure semantics

| Hệ thống | Redis không reachable |
|---|---|
| Login/OTP chống abuse | Thường fail-closed hoặc local emergency limit |
| Public content không nhạy cảm | Có thể fail-open có circuit breaker |
| Internal batch | Có thể backoff/queue |

Global limiter qua nhiều region cần quyết định consistency/latency rõ ràng; một Redis Cluster trong một region không tự tạo globally strict counter.

---

## 5. Session store

### 5.1 Data model

Browser giữ opaque session ID; dữ liệu ở Redis:

```redis
MULTI
HSET session:7f0c... \
  user_id 42 \
  created_at 1785283200 \
  last_seen_at 1785283200 \
  absolute_expires_at 1785888000
EXPIRE session:7f0c... 1800
EXEC
```

Transaction tránh tạo session không TTL nếu process lỗi giữa `HSET` và `EXPIRE`.

Session nên nhỏ:

- user ID và security context tối thiểu;
- không lưu profile/cart lớn nếu có source riêng;
- không đặt secret/token thô không cần thiết;
- có schema version để rollout.

### 5.2 Sliding và absolute expiration

Sliding TTL giữ session sống khi người dùng hoạt động, nhưng phải có absolute deadline:

```text
new_ttl = min(idle_timeout, absolute_expires_at - now)
```

Nếu chỉ gọi `EXPIRE 30m` trên mọi request, một token bị đánh cắp có thể được kéo dài vô hạn.

Không nhất thiết refresh TTL mỗi request; có thể refresh khi TTL còn dưới threshold để giảm write amplification.

### 5.3 Security và lifecycle

- session ID ngẫu nhiên đủ entropy và rotate sau login/privilege change;
- cookie dùng `HttpOnly`, `Secure` và `SameSite` phù hợp;
- logout xóa server session và cookie;
- logout-all cần index `user -> session IDs` có cleanup;
- không log session ID đầy đủ;
- ACL chỉ cho service chạm namespace session;
- xác định behavior khi Redis unavailable;
- session thường không được phép eviction tùy ý như cache.

Redis Cluster yêu cầu thiết kế hash tag nếu cần atomically cập nhật session và index liên quan. Gom mọi session một user vào cùng slot cũng có thể tạo hot slot.

### 5.4 Durability

Mất session có tác động kinh doanh/security khác cache miss. Chọn:

- persistence và HA;
- RPO/RTO;
- `maxmemory-policy`;
- khả năng re-authenticate an toàn;
- revoke list hoặc external identity provider.

Spring Session Data Redis là lựa chọn phổ biến trong Java; vẫn phải cấu hình cookie, TTL, serializer, namespace và topology-aware connection đúng SLO.

---

## 6. Distributed lock thực chất là lease

### 6.1 Trước hết, có thật sự cần lock?

Thường an toàn hơn:

- unique constraint trong source database;
- idempotency key;
- optimistic concurrency/version;
- partition công việc theo owner;
- queue bảo đảm một consumer group phân phối;
- state machine có compare-and-set.

Lock không biến external side effect thành transaction và không sửa được operation không idempotent.

### 6.2 Single-instance lease đúng ownership

Acquire:

```redis
SET lock:invoice:42 7f0c-unique-token NX PX 30000
```

Release trên Redis 8.4+:

```redis
DELEX lock:invoice:42 IFEQ 7f0c-unique-token
```

Các invariant:

- token duy nhất cho mỗi lần acquire;
- TTL lớn hơn thời gian công việc dự kiến cộng margin;
- chỉ owner hiện tại được release/renew;
- retry acquire có backoff và jitter;
- công việc phải dừng hoặc bị downstream từ chối khi mất lease.

### 6.3 Pause dài hơn TTL

```text
Client A có lease
Client A pause 40s
Lease hết sau 30s
Client B acquire và ghi
Client A tỉnh lại và cũng ghi
```

Safe release không ngăn Client A tạo side effect muộn. Với tài nguyên quan trọng, dùng **fencing token** tăng đơn điệu:

```text
lease A -> fence 101
lease B -> fence 102

downstream chỉ chấp nhận token > token đã thấy gần nhất
```

Downstream storage phải thực sự kiểm tra token. Counter fencing cũng phải durable/monotonic qua failover; nếu nguồn token có thể quay lùi, guarantee bị phá.

### 6.4 Failover và Redlock

Lock ghi vào primary có thể chưa replicate trước failover:

```text
A acquire -> primary chết trước replication
replica promote -> B acquire cùng lock
```

Nếu duplicate holder thỉnh thoảng chấp nhận được, single Redis/Sentinel lease có thể đủ. Nếu mutual exclusion là safety-critical, cần đánh giá kỹ:

- Redlock trên các primary độc lập, majority và clock-drift assumption;
- fencing ở downstream;
- consensus/coordination system hoặc database lock có semantics phù hợp hơn;
- thư viện đã được review thay vì tự triển khai.

Redlock không tự giải quyết stale holder sau pause và không tạo transaction với external system. Hãy viết threat/failure model trước khi chọn.

---

## 7. Leaderboard bằng Sorted Set

### 7.1 Operations cơ bản

```redis
ZADD leaderboard:2026:s29 1250 user:42
ZINCRBY leaderboard:2026:s29 25 user:42

# Top 10, score cao trước.
ZRANGE leaderboard:2026:s29 0 9 REV WITHSCORES

# Rank bắt đầu từ 0.
ZREVRANK leaderboard:2026:s29 user:42 WITHSCORE
```

Update score/member là atomic. Metadata người dùng nên nằm ở Hash/JSON khác; tránh nhét JSON vào member vì đổi profile sẽ đổi identity leaderboard.

### 7.2 Tie và pagination

Các member cùng score được sắp theo member lexicographic. Product phải định nghĩa tie-break:

- chấp nhận cùng điểm và thứ tự member;
- lưu timestamp/secondary rank ở data model khác;
- tạo composite score chỉ khi hiểu giới hạn precision của double;
- dùng snapshot/version nếu pagination phải ổn định khi score thay đổi liên tục.

Để hiển thị quanh người dùng:

1. lấy `ZREVRANK`;
2. tính range `[rank - k, rank + k]`;
3. `ZRANGE ... REV WITHSCORES`.

Hai command có thể thấy hai thời điểm khác nhau; dùng Function/script nếu cần một snapshot atomic ngắn.

### 7.3 Season, retention và Cluster

Version key theo season:

```text
leaderboard:{game-7}:2026-s29
leaderboard:{game-7}:2026-s30
```

Sau khi đóng season:

- đặt TTL/archive theo yêu cầu;
- không `DEL` big Sorted Set đồng bộ, ưu tiên `UNLINK`;
- trim nếu chỉ cần top N, nhưng xác nhận không cần rank người ngoài top.

Một leaderboard là một key/slot nên có thể thành hot key. Thêm shard không chia một Sorted Set; cần partition theo region/league rồi aggregate, chấp nhận consistency và ranking semantics phức tạp hơn.

Redis 8.8 thêm `COUNT` aggregator cho các command union/intersection Sorted Set, hữu ích khi cần đếm số tập mà member xuất hiện; kiểm tra semantics trước khi dùng thay score aggregation hiện có.

---

## 8. Job queue và scheduler

### 8.1 Chọn primitive

| Primitive | Phù hợp | Hạn chế |
|---|---|---|
| Pub/Sub | Trigger có thể mất | Không queue/retry |
| List + `BLMOVE` | FIFO work queue đơn giản | Tự xây metadata, visibility, retry, DLQ |
| Streams | Consumer group, replay, PEL | Vận hành retention/recovery phức tạp hơn |
| Sorted Set | Delayed/scheduled job | Cần atomic claim và polling/wakeup |

### 8.2 Reliable List queue

Producer chỉ đẩy job ID duy nhất:

```redis
MULTI
HSET queue:{email}:job:job-123 \
  payload '{"template":"welcome","userId":42}' \
  attempts 0 \
  status pending
LPUSH queue:{email}:pending job-123
EXEC
```

Worker atomically chuyển pending sang processing:

```redis
BLMOVE queue:{email}:pending queue:{email}:processing \
  RIGHT LEFT 5
```

Sau khi side effect thành công, Function/script kiểm tra claim token rồi:

- xóa job ID khỏi processing;
- đánh dấu completed;
- ghi completion event nếu cần audit.

Watchdog đưa job quá visibility timeout về pending hoặc DLQ. Không chỉ lưu payload giống nhau trong List rồi `LREM 1 payload`, vì duplicate payload có thể xóa nhầm attempt.

`BRPOPLPUSH` đã deprecated; dùng `BLMOVE`.

### 8.3 Stream queue

Streams thường tốt hơn khi cần:

- nhiều consumer;
- pending state và delivery count;
- replay/audit;
- recovery bằng `XAUTOCLAIM`;
- release nhanh bằng `XNACK`;
- producer dedup với `XADD IDMP`.

Queue library/framework đã battle-tested thường an toàn hơn tự ghép command, đặc biệt với delayed retry, heartbeat và cleanup.

### 8.4 Delayed queue bằng Sorted Set

```redis
ZADD queue:{email}:scheduled 1785286800000 job-123
```

Scheduler không được làm riêng:

```text
ZRANGE due -> ZREM -> LPUSH
```

Hai worker có thể lấy cùng job hoặc crash giữa các bước. Dùng Function/script atomic:

```text
claim_due(now, limit):
  đọc tối đa limit member có score <= now
  remove khỏi scheduled
  push vào pending/stream
  return IDs
```

Các key phải cùng hash slot trong Cluster. Worker cần sleep bounded hoặc signal đánh thức khi có job sớm hơn; luôn có periodic poll để tự hồi phục nếu signal Pub/Sub bị mất.

### 8.5 Retry và DLQ

```text
delay = min(base * 2^attempt, max_delay) + jitter
```

Retry chỉ cho lỗi transient. Permanent validation error đi thẳng DLQ. Mỗi job cần:

- stable job/idempotency ID;
- attempt count;
- claimed/next-run timestamp;
- last error class, không lưu secret;
- max attempts;
- owner/claim token;
- original payload/version;
- DLQ và replay audit.

Timeout external API tạo unknown outcome; truyền idempotency key tới API/DB nếu hỗ trợ.

---

## 9. Idempotency và “exactly once”

### 9.1 Idempotency record

Một request ID có state:

```text
ABSENT
  -> PROCESSING(owner_token, lease_until)
  -> COMPLETED(response_digest/result, expires_at)
  -> FAILED_RETRYABLE hoặc FAILED_FINAL
```

`SET idempotency:<id> ... NX PX ...` chỉ là bước đầu. Cần:

- ownership token khi complete;
- lease/recovery nếu worker chết;
- lưu result để duplicate nhận cùng response;
- TTL dài hơn retry window;
- payload hash để cùng ID không dùng cho request khác;
- atomic transition bằng conditional command/Function.

### 9.2 Exactly-once end-to-end thường là ảo tưởng

Redis có thể dedup producer append, Stream có thể track delivery, DB có thể unique request ID. Nhưng crash luôn có thể xảy ra giữa hai hệ thống.

Thiết kế thực tế:

```text
at-least-once delivery
+ idempotent consumer
+ dedup window
+ transactional outbox/inbox
+ reconciliation
= hiệu ứng nghiệp vụ “như một lần” trong phạm vi đã định nghĩa
```

Phải ghi rõ phạm vi: một Redis key, một DB transaction hay cả external payment API.

---

## 10. Key design cho pattern

### 10.1 Namespace

```text
<environment>:<service>:<pattern>:<entity>:<id>:<version>

prod:catalog:cache:product:42:v7
prod:billing:idem:evt-001
prod:email:queue:{email}:pending
```

Không nhất thiết nhét mọi thành phần vào key; tên quá dài cũng tốn memory. Mục tiêu là tránh collision, quan sát được và có lifecycle rõ.

### 10.2 Cluster hash tag

Function/transaction/multi-key operation thường cần cùng slot:

```text
queue:{email}:pending
queue:{email}:processing
queue:{email}:scheduled
```

Hash tag gom atomic boundary nhưng cũng gom tải. Chọn tag theo đơn vị cần atomic, không theo toàn hệ thống.

### 10.3 Retention

Mỗi namespace phải có:

- TTL hay explicit retention;
- owner chịu trách nhiệm cleanup;
- big-key limit;
- cardinality budget;
- migration/version strategy;
- dữ liệu nào được backup.

---

## 11. Observability theo pattern

| Pattern | Metrics quan trọng |
|---|---|
| Cache | hit/miss theo use case, stale served, loader latency, stampede wait, eviction |
| Pub/Sub | publish rate, subscriber count, reconnect, dropped/processing error phía client |
| Streams | append rate, group lag, PEL, idle age, delivery count, claim/NACK/DLQ |
| Rate limit | allowed/rejected, Redis error, fail-open/closed, cardinality |
| Session | active sessions, expiry/logout, read/write latency, forced re-auth |
| Lock | acquire success/wait, lease expiry, renew failure, stale fence reject |
| Leaderboard | update/read latency, cardinality, hot-key QPS, season size |
| Queue | pending/processing/delayed/DLQ, oldest age, attempts, throughput |

Không dùng Redis key scan làm dashboard liên tục. Duy trì counter/metric riêng hoặc exporter có sampling/throttle.

### 11.1 Runbook ngắn

#### Cache source bị quá tải

1. kiểm tra hit rate theo endpoint/key class;
2. tìm TTL avalanche/hot key;
3. bật/điều chỉnh singleflight hoặc stale serving trong policy;
4. giới hạn concurrent fallback;
5. không tăng TTL vô hạn nếu dữ liệu cần freshness.

#### Stream lag tăng

1. so append và consume rate;
2. xem PEL/oldest idle/delivery count;
3. phân biệt poison message với consumer thiếu capacity;
4. claim/NACK/DLQ theo policy;
5. kiểm tra retention còn đủ recovery window.

#### Lock contention tăng

1. kiểm tra critical section có quá dài không;
2. đo expiry/renew failure;
3. tìm client retry không jitter;
4. xác nhận downstream fencing;
5. cân nhắc partition ownership/queue thay lock.

#### Queue backlog tăng

1. xem oldest job age, không chỉ queue length;
2. phân loại transient/permanent error;
3. kiểm tra downstream saturation;
4. scale consumer có giới hạn;
5. giữ backpressure, không retry storm.

---

## 12. Những ngộ nhận cần tránh

| Ngộ nhận | Thực tế |
|---|---|
| Commit DB rồi update Redis luôn nhất quán | Hai hệ thống không cùng transaction, vẫn có failure/race window |
| Pipeline DB + Redis làm write-through atomic | Pipeline chỉ áp dụng command trên Redis connection |
| AOF làm write-behind không mất dữ liệu | Guarantee end-to-end còn replication, ack, DB idempotency và recovery |
| Pub/Sub là message queue | Subscriber offline mất message; không ack/replay |
| Stream consumer group là exactly-once | Crash trước/sau ack tạo redelivery hoặc mất side effect nếu ack sai |
| `XADD IDMP` làm toàn pipeline exactly-once | Nó chỉ dedup producer append trong phạm vi cấu hình |
| `XNACK FATAL` tự đưa message vào DLQ | Nó đánh dấu delivery state; application vẫn phải ghi DLQ |
| `INCR` rồi `EXPIRE` luôn tạo limiter đúng | Crash/race giữa lệnh; dùng `INCREX` 8.8 hoặc atomic function |
| `DEL` là cách release lock | Có thể xóa lease của owner mới; phải compare token |
| Có TTL là lock an toàn tuyệt đối | Client cũ vẫn có thể ghi sau khi lease hết; cần fencing khi quan trọng |
| Redlock giải quyết mọi distributed lock | Vẫn có clock/failure assumptions và không thay downstream fencing |
| `BRPOP` là reliable queue | Crash sau pop trước xử lý làm mất job; dùng `BLMOVE`/Streams |
| Thêm Cluster shard chia một leaderboard | Một Sorted Set vẫn thuộc một slot |

---

## 13. Production checklist

### Semantics

- [ ] Source of truth và staleness window được ghi rõ.
- [ ] Delivery là at-most-once hay at-least-once được ghi rõ.
- [ ] Unknown outcome và duplicate side effect có chiến lược.
- [ ] Atomic boundary không vượt Redis slot/hệ thống mà không có protocol bổ sung.

### Lifecycle

- [ ] Mọi cache/session/idempotency key có TTL phù hợp.
- [ ] Stream/queue/leaderboard có retention và big-key budget.
- [ ] Retry có max attempts, backoff, jitter và DLQ.
- [ ] Có recovery cho worker chết, consumer lag và Redis failover.

### Safety

- [ ] Cache stampede có singleflight/stale/fallback budget.
- [ ] Stream consumer chỉ ack sau durable side effect.
- [ ] Lock release/renew kiểm tra token; critical resource có fencing.
- [ ] Rate limiter có quyết định fail-open/closed.
- [ ] Session có secure cookie, rotation và absolute expiry.

### Cluster/HA

- [ ] Multi-key operation dùng hash tag đúng atomic boundary.
- [ ] Đã kiểm tra hot key/hot slot.
- [ ] Client hiểu Cluster/Sentinel và reconnect.
- [ ] Pattern được test khi failover, timeout và network partition.

### Observability

- [ ] Có metric business và technical theo từng pattern.
- [ ] Alert dựa trên oldest age/lag/error, không chỉ key count.
- [ ] DLQ/replay có audit và quyền truy cập.
- [ ] Fault injection đã kiểm chứng guarantee thực tế.

---

## 14. Tóm tắt

- Cache-aside đơn giản nhưng vẫn cần TTL, invalidation race và stampede strategy.
- Pub/Sub là at-most-once realtime fan-out; Streams dành cho persistence, replay và consumer group.
- Redis 8.8 thêm `INCREX` cho fixed-window limiter và `XNACK` cho consumer chủ động release pending message.
- Stream processing thực tế thường at-least-once; idempotency quyết định độ đúng của side effect.
- Session cần absolute expiry, security và durability khác cache thông thường.
- Distributed lock là lease; safe release chưa đủ nếu không chống stale holder bằng fencing.
- List queue cần `BLMOVE` và recovery; Streams phù hợp hơn khi workflow phức tạp.
- “Exactly once” chỉ có ý nghĩa khi định nghĩa rõ phạm vi và phối hợp mọi hệ thống liên quan.

## Tài liệu chính thức

- [Redis cache-aside](https://redis.io/docs/latest/develop/use-cases/cache-aside/)
- [Redis Pub/Sub](https://redis.io/docs/latest/develop/pubsub/)
- [Redis Streams](https://redis.io/docs/latest/develop/data-types/streams/)
- [Idempotent message production with Streams](https://redis.io/docs/latest/develop/data-types/streams/idempotency/)
- [`XNACK`](https://redis.io/docs/latest/commands/xnack/)
- [`INCREX`](https://redis.io/docs/latest/commands/increx/)
- [Distributed locks with Redis](https://redis.io/docs/latest/develop/clients/patterns/distributed-locks/)
- [`BLMOVE`](https://redis.io/docs/latest/commands/blmove/)
- [Redis session store](https://redis.io/docs/latest/develop/use-cases/session-store/)
- [Redis Sorted Sets](https://redis.io/docs/latest/develop/data-types/sorted-sets/)
- [Redis Open Source 8.8](https://redis.io/docs/latest/develop/whats-new/8-8/)

## Đọc tiếp

- [Redis Fundamentals](redis_fundamentals.md)
- [Redis High Availability](redis_ha.md)
- [Redis Performance & Internals](redis_performance.md)
- [Redis Glossary](glossary.md)
- [Redis Roadmap](roadmap.md)

*Cập nhật lần cuối: 2026-07-29*
