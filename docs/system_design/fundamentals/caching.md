---
title: "Caching – Chiến lược cache"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 2
---
# Caching – Chiến lược cache

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Scalability](scalability.md), [Load Balancing](load_balancing.md). Đọc tiếp: [Databases Design](databases_design.md).

---

## 1. Cache đổi tính đúng đắn lấy tốc độ

Cache là bản sao dữ liệu ở nơi rẻ hơn để đọc. Mọi lợi ích của cache đến từ một sự thật: **bản sao đó có thể cũ**. Vì vậy câu hỏi thiết kế cache không phải "cache thế nào" mà là:

1. Dữ liệu này **được phép cũ bao lâu**? (đây là câu hỏi nghiệp vụ, không phải câu hỏi kỹ thuật)
2. Nếu cache **chết hoàn toàn**, hệ thống còn sống không?
3. Khi dữ liệu gốc đổi, cache được làm mới bằng cơ chế nào?

Đội nào trả lời được cả ba câu trước khi viết code thì hệ thống cache sẽ ổn định. Đội nào thêm cache để "cho nhanh" rồi mới xử lý ba câu đó sẽ gặp lỗi dữ liệu cũ khó tái hiện.

### 1.1 Phân cấp theo độ trễ

```text
Register CPU        < 1 ns
L1/L2/L3 cache      1–30 ns
RAM (in-process)    ~100 ns        ← Caffeine, HashMap
NVMe local          ~50–100 µs
Redis cùng AZ       0,3–2 ms       ← chi phí chính là network round-trip
CDN edge            5–50 ms
Database            5–100 ms
Object storage      50–200 ms
```

Con số quan trọng nhất: **cache trong process nhanh hơn Redis khoảng 1000 lần**, vì nó không có network. Đó là lý do cache nhiều tầng (mục 8) là kiến trúc mặc định cho đường đi cực nóng, chứ không phải sự phức tạp không cần thiết.

Và ngược lại: Redis không nhanh vì Redis nhanh, mà vì nó ở gần. Một Redis cùng AZ là ~0,5ms; Redis cross-region là 100ms — lúc đó nó **chậm hơn** database local.

---

## 2. Năm pattern cache

### 2.1 Cache-aside (lazy loading) – mặc định

```java
public User getUser(long id) {
    String key = "user:" + id;
    User cached = redis.get(key, User.class);
    if (cached != null) return cached;                 // hit

    User user = userRepo.findById(id).orElseThrow();   // miss → nguồn thật
    redis.setex(key, Duration.ofMinutes(10), user);    // TTL luôn có
    return user;
}

public void updateUser(User u) {
    userRepo.save(u);
    redis.del("user:" + u.getId());                    // XÓA, không phải cập nhật
}
```

| Được | Mất |
|---|---|
| Chỉ cache dữ liệu thực sự được đọc | Miss tốn 3 chặng (check → DB → set) |
| Cache chết thì hệ thống vẫn chạy (chỉ chậm) | Có cửa sổ dữ liệu cũ |
| Đơn giản, dễ suy luận | Logic cache rải trong code ứng dụng |

**Vì sao invalidate (xóa) tốt hơn update (ghi lại) khi dữ liệu đổi:** nếu hai request cùng ghi cache với hai phiên bản khác nhau, thứ tự ghi vào cache có thể ngược thứ tự ghi vào DB → cache giữ giá trị cũ vĩnh viễn. Xóa thì lần đọc sau luôn lấy từ nguồn thật.

### 2.2 Read-through

Cache tự nạp từ nguồn khi miss; ứng dụng chỉ nói chuyện với cache.

| Được | Mất |
|---|---|
| Code ứng dụng gọn | Cache layer phải biết cách truy vấn nguồn |
| Logic cache tập trung một chỗ | Cache thành dependency **bắt buộc**, không còn tùy chọn |

Điểm cần cân: với cache-aside, Redis chết = chậm. Với read-through, Redis chết = **hỏng**. Đó là đánh đổi thật về availability, không chỉ về code style.

### 2.3 Write-through

```text
App → ghi cache → ghi DB → trả về
```

Cache luôn khớp DB, không có dữ liệu cũ. Đổi lại: mỗi write chịu độ trễ của hai lần ghi, và cache đầy dữ liệu chưa chắc được đọc.

### 2.4 Write-behind (write-back)

```text
App → ghi cache → trả về NGAY
                → gom lô → ghi DB bất đồng bộ
```

Rất nhanh cho ghi, và gom lô làm giảm tải DB đáng kể. Rủi ro: **cache chết trước khi flush là mất dữ liệu**.

Dùng đúng chỗ: bộ đếm view, số lượt like, metric — nơi mất vài giây dữ liệu là chấp nhận được. Không dùng cho dữ liệu tiền tệ hay đơn hàng.

### 2.5 Refresh-ahead / stale-while-revalidate

```text
TTL 60s, refresh-ahead ở 80%:
t=48s → có request → trả cache ngay + kích hoạt refresh ở background
t=60s → TTL hết nhưng dữ liệu đã được thay mới → không có ai gặp miss
```

Đây là pattern giá trị nhất cho dữ liệu đọc nhiều và tính đắt: **không ai phải chờ**, và nó đồng thời giải quyết cache stampede (mục 4.1).

### 2.6 So sánh

| Pattern | Tính nhất quán | Độ trễ ghi | Độ trễ đọc | Cache chết thì sao |
|---|---|---|---|---|
| Cache-aside | Eventual | Bình thường | Nhanh (khi hit) | Chậm, vẫn chạy |
| Read-through | Eventual | Bình thường | Nhanh | **Hỏng** |
| Write-through | Mạnh (cache↔DB) | Chậm hơn | Nhanh | Chậm |
| Write-behind | Eventual, có rủi ro mất | Nhanh nhất | Nhanh | **Mất dữ liệu chưa flush** |
| Refresh-ahead | Eventual | Bình thường | Nhanh, ổn định | Chậm |

---

## 3. Eviction và bộ nhớ

| Policy | Loại bỏ gì | Phù hợp |
|---|---|---|
| **LRU** | Ít được dùng gần đây nhất | Mặc định tốt cho phần lớn ca |
| **LFU** | Ít được dùng nhiều nhất (theo tần suất) | Có tập nóng ổn định lâu dài; chống "scan làm sạch cache" |
| **FIFO** | Vào trước ra trước | Dữ liệu theo thời gian |
| **TTL-only** | Theo hạn | Khi mọi entry có hạn rõ ràng |
| **Random** | Ngẫu nhiên | Khi phân bố truy cập đều |

Redis: `allkeys-lru` (loại bỏ bất kỳ key) vs `volatile-lru` (chỉ loại key có TTL). Chọn `volatile-*` khi Redis vừa làm cache vừa lưu dữ liệu không được mất — nhưng trộn hai vai trò trong một instance là thiết kế nên tránh.

**LFU chống được một tình huống LRU xử lý tệ**: một job quét toàn bộ dữ liệu (báo cáo, migration) đọc hàng triệu key một lần, đẩy hết tập nóng ra khỏi cache. LRU coi các key vừa quét là "mới dùng"; LFU thấy chúng chỉ được dùng một lần và giữ lại tập nóng thật. Redis có `allkeys-lfu` từ 4.0.

### 3.1 Nên cache gì

```text
Ưu tiên cache:  đọc nhiều × tính đắt × ít đổi × kích thước nhỏ
Không nên:      đọc một lần, đổi liên tục, kích thước lớn, dữ liệu riêng tư theo user
```

Sai lầm thường gặp: cache mọi thứ. Cache entry không bao giờ được đọc lại là chi phí thuần (RAM + một lần ghi), và nó chiếm chỗ của entry hữu ích. Đo `hit ratio` **theo từng loại key**, không phải tổng — hit ratio tổng 85% có thể che một loại key hit 5%.

Mục tiêu tham chiếu: hit ratio 80–95% cho cache đọc. Dưới 50% thì thường là chọn sai thứ để cache hoặc TTL quá ngắn.

---

## 4. Ba chế độ hỏng của cache

Đây là phần quan trọng nhất của chương, vì đây là nơi cache gây sự cố thật.

### 4.1 Cache stampede (thundering herd)

```text
Một key nóng hết hạn lúc t=0
→ 5.000 request đồng thời cùng miss
→ 5.000 truy vấn giống nhau đập vào DB cùng lúc
→ DB quá tải → timeout → cache không bao giờ được nạp lại → vòng lặp tử thần
```

Bốn cách chữa, nên kết hợp:

```java
// (a) Single-flight / mutex: chỉ một request đi lấy dữ liệu, số còn lại chờ kết quả đó
private final ConcurrentMap<String, CompletableFuture<User>> inFlight = new ConcurrentHashMap<>();

User getUser(long id) {
    String key = "user:" + id;
    User cached = redis.get(key, User.class);
    if (cached != null) return cached;

    return inFlight.computeIfAbsent(key, k -> CompletableFuture.supplyAsync(() -> {
        User u = userRepo.findById(id).orElseThrow();
        redis.setex(k, Duration.ofMinutes(10), u);
        return u;
    })).whenComplete((r, e) -> inFlight.remove(key)).join();
}
```

```text
(b) TTL có jitter: TTL = base ± random(0..20%)
    → các key không hết hạn cùng lúc (đặc biệt quan trọng khi cache được nạp hàng loạt)

(c) Probabilistic early expiration (XFetch):
    refresh sớm với xác suất tăng dần khi gần hết TTL → phân tán các lần nạp lại

(d) Stale-while-revalidate: trả bản cũ ngay + refresh nền
    → không ai chờ, DB chỉ nhận một truy vấn
```

Điểm (b) đáng nhấn: khi warm cache lúc khởi động hoặc sau khi flush, mọi entry có cùng TTL → sau đúng TTL giây, **toàn bộ** cache hết hạn cùng lúc. Jitter là bắt buộc, không phải tinh chỉnh.

### 4.2 Cache penetration – truy vấn thứ không tồn tại

```text
Kẻ tấn công (hoặc bug) hỏi user id = -1, -2, -3, ... liên tục
→ luôn miss cache (vì không có gì để cache)
→ mọi request đều xuống DB
```

Cách chữa:

| Cách | Cơ chế |
|---|---|
| **Cache negative result** | Cache cả "không tồn tại" với TTL ngắn (30–60s) |
| **Bloom filter** | Kiểm tra nhanh "key này chắc chắn không có" trước khi xuống DB |
| **Validate đầu vào** | Từ chối id không hợp lệ ngay ở tầng ngoài |

Bloom filter đáng dùng khi không gian key rất lớn và tỉ lệ truy vấn key không tồn tại cao (ví dụ kiểm tra username đã dùng chưa): nó cho phép sai dương (nói "có thể có" khi không có) nhưng **không bao giờ sai âm**, nên an toàn để dùng làm cửa chặn.

### 4.3 Cache avalanche – cache chết hoặc rỗng đồng thời

```text
Redis restart / mất cache / vừa deploy với cache rỗng
→ 100% request xuống DB → DB không chịu được tải chưa từng có
```

Đây là chế độ hỏng nghiêm trọng nhất, vì hệ thống đã được "thiết kế" dựa trên giả định cache hit 90%. Cách phòng:

| Biện pháp | Chi tiết |
|---|---|
| **Cache warming** | Nạp trước tập nóng khi khởi động, trước khi nhận traffic (readiness chỉ OK sau warm) |
| **Cache nhiều tầng** | L1 trong process vẫn còn khi L2 chết → hấp thụ một phần |
| **Circuit breaker + load shedding trước DB** | Thà từ chối 30% request còn hơn sập DB |
| **Redis HA** | Sentinel/Cluster, replica; nhưng đừng coi HA là lý do bỏ qua các mục trên |
| **Rate limit ở tầng cache-miss** | Giới hạn số truy vấn xuống DB mỗi giây |

Bài kiểm tra đơn giản và nên làm định kỳ: **flush cache trên staging với tải production và xem hệ thống có sống không**. Nếu không, cache đang là dependency bắt buộc chứ không phải lớp tối ưu — và đó là rủi ro cần biết trước.

---

## 5. Invalidation – vấn đề khó nhất

> "Chỉ có hai việc khó trong khoa học máy tính: cache invalidation và đặt tên." — Phil Karlton

### 5.1 Bốn chiến lược

| Chiến lược | Cơ chế | Cửa sổ dữ liệu cũ | Phù hợp |
|---|---|---|---|
| **TTL** | Hết hạn tự động | Bằng TTL | Mặc định; luôn nên có kể cả khi dùng cách khác |
| **Xóa chủ động khi ghi** | Ghi DB xong thì xóa key | Rất nhỏ | Khi biết chính xác key nào bị ảnh hưởng |
| **Event-based** | DB đổi → phát event → consumer xóa cache | Vài chục ms–giây | Nhiều service cùng cache; xem `advanced/event_driven_architecture.md` |
| **Versioned key** | Đưa version vào key | Bằng 0 | Khi cần chuyển đổi tức thời, không cần xóa |

```text
Versioned key — mẫu rất hữu ích và ít dùng:
   key = "product:123:v" + productVersion
   Đổi sản phẩm → tăng productVersion → mọi key cũ trở thành rác, TTL tự dọn
   → không cần biết đã tạo bao nhiêu key phái sinh (list, search result, aggregate)
```

Versioned key giải quyết đúng bài toán khó nhất của invalidation: **một thay đổi ảnh hưởng nhiều key mà bạn không liệt kê được**. Đổi tên một danh mục có thể làm cũ hàng nghìn key kết quả tìm kiếm; xóa từng cái là bất khả thi, tăng version thì xong.

### 5.2 TTL luôn phải có

Ngay cả khi có invalidation chủ động hoàn hảo, TTL vẫn là lưới an toàn:

```text
Không có TTL + bỏ sót một đường ghi = dữ liệu cũ VĨNH VIỄN
Có TTL                              = dữ liệu cũ tối đa TTL giây
```

Sự cố "dữ liệu sai mà không ai giải thích được, restart thì hết" gần như luôn là một key cache không có TTL với một đường ghi bị bỏ sót.

### 5.3 Thứ tự ghi DB và xóa cache

```text
✗ Xóa cache → ghi DB:
   giữa hai bước có request đọc → nạp lại GIÁ TRỊ CŨ vào cache → cũ cho đến hết TTL

✓ Ghi DB → xóa cache:
   cửa sổ lỗi nhỏ hơn nhiều, và request đọc sau đó lấy giá trị mới

✓✓ Ghi DB → xóa cache → (delay ngắn) → xóa lần hai (delayed double delete)
   xử lý ca replica lag: request đọc trong lúc replica chưa có dữ liệu mới
```

Delayed double delete cần thiết khi đọc từ read replica: sau khi xóa cache, một request đọc có thể lấy dữ liệu từ replica chưa kịp cập nhật và nạp lại giá trị cũ. Xóa lần hai sau vài trăm ms dọn được ca đó.

---

## 6. Hot key

```text
Một key chiếm 40% tổng lưu lượng cache (sản phẩm đang sale, bài viết viral)
→ shard chứa nó quá tải, trong khi các shard khác rảnh
→ consistent hashing KHÔNG giúp gì: hot key vẫn băm về một node
```

| Cách chữa | Cơ chế | Đánh đổi |
|---|---|---|
| **L1 local cache** | Mỗi app node giữ bản sao trong process | Mỗi node có thể thấy giá trị hơi khác nhau |
| **Nhân bản key** | `key#1..key#N`, client chọn ngẫu nhiên | Ghi phải cập nhật N bản |
| **Request coalescing** | Gộp các request giống nhau thành một | Thêm độ trễ nhỏ |
| **Client-side batching** | Gom nhiều key vào một MGET | Giảm số round-trip, không giảm tải node |

Cách hiệu quả nhất cho hot key hầu như luôn là **L1 local cache với TTL rất ngắn** (1–5 giây): một key được đọc 50.000 lần/giây sẽ chỉ tạo ra vài request tới Redis mỗi giây, và độ cũ 5 giây là chấp nhận được với đúng loại dữ liệu gây ra hot key (sản phẩm, bài viết, cấu hình).

Phát hiện hot key: `redis-cli --hotkeys`, hoặc lấy mẫu từ `MONITOR` (cẩn thận, `MONITOR` rất nặng), hoặc đo ở tầng client.

---

## 7. CDN – cache ở tầng gần người dùng

```text
User → CDN edge (gần nhất) ──hit──► trả ngay (5–50ms)
                            ──miss─► origin → cache lại → trả
```

CDN giải quyết ba việc cùng lúc: giảm độ trễ (edge gần), giảm tải origin, và hấp thụ một phần DDoS.

### 7.1 Cache-Control – ngôn ngữ điều khiển

```http
# Asset có hash trong tên file → bất biến, cache thật lâu
Cache-Control: public, max-age=31536000, immutable

# HTML/API: cho phép dùng bản cũ trong lúc làm mới ở background
Cache-Control: public, max-age=60, stale-while-revalidate=600, stale-if-error=86400

# Dữ liệu riêng theo user: chỉ browser cache, CDN không được cache
Cache-Control: private, max-age=30

# Không bao giờ lưu (dữ liệu nhạy cảm)
Cache-Control: no-store
```

Hai directive đáng dùng hơn mức phổ biến:

- **`stale-while-revalidate`**: người dùng luôn được trả ngay, việc làm mới diễn ra ở background. Đây là stale-while-revalidate của mục 2.5 nhưng miễn phí ở tầng CDN.
- **`stale-if-error`**: khi origin lỗi, CDN tiếp tục trả bản cũ thay vì trả lỗi. Một dòng header này biến sự cố origin thành chuyện vô hình với người dùng cho nội dung đọc — đây là biện pháp resilience rẻ nhất trong toàn bộ tài liệu này.

Phân biệt hai directive hay bị nhầm: `no-cache` nghĩa là "phải xác thực lại với server trước khi dùng" (vẫn được lưu); `no-store` nghĩa là "không được lưu ở bất cứ đâu".

### 7.2 Invalidation ở CDN

```bash
# Cloudflare
curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE/purge_cache" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  --data '{"files":["https://example.com/app.css"]}'

# CloudFront
aws cloudfront create-invalidation --distribution-id $DIST --paths "/images/*"
```

Purge chậm (giây đến phút) và thường bị giới hạn số lượng. Vì vậy chiến lược tốt hơn là **không cần purge**: đặt hash nội dung vào tên file (`app.7f3a9c.css`) và cache vĩnh viễn. Nội dung mới = URL mới = không có gì phải invalidate.

Với API response cache tại edge, `Cache-Tag` (Cloudflare) hoặc surrogate key (Fastly) cho phép purge theo nhóm — hữu ích khi một thay đổi ảnh hưởng nhiều URL.

---

## 8. Cache nhiều tầng

```text
Request → L1 (Caffeine, in-process, ~100ns, TTL ngắn)
        → miss → L2 (Redis, ~0,5ms, TTL dài hơn)
                → miss → nguồn thật (DB, ~20ms)
                → nạp L2
        → nạp L1
```

```java
// L1: nhỏ, TTL ngắn — chấp nhận độ cũ để đổi lấy độ trễ và giảm tải L2
private final Cache<String, User> l1 = Caffeine.newBuilder()
        .maximumSize(50_000)
        .expireAfterWrite(Duration.ofSeconds(5))
        .recordStats()
        .build();

public User getUser(long id) {
    String key = "user:" + id;
    return l1.get(key, k -> {
        User fromRedis = redis.get(k, User.class);
        if (fromRedis != null) return fromRedis;

        User fromDb = userRepo.findById(id).orElseThrow();
        redis.setex(k, Duration.ofMinutes(10), fromDb);
        return fromDb;
    });
}
```

Vấn đề cốt lõi của L1: **không có cách xóa nó từ xa**. Mỗi app node có bản sao riêng. Hai cách xử lý:

| Cách | Cơ chế | Phù hợp |
|---|---|---|
| **TTL rất ngắn** | 1–10 giây | Đơn giản nhất, đủ cho phần lớn ca |
| **Pub/sub invalidation** | Ghi → publish → mọi node xóa L1 | Khi cần độ mới cao hơn |

```java
// Pub/sub invalidation cho L1
redis.publish("cache:invalidate", "user:" + id);      // phía ghi

// phía mọi app node
redis.subscribe((channel, message) -> l1.invalidate(message), "cache:invalidate");
```

Cần biết giới hạn: pub/sub của Redis là **at-most-once** — node đang restart hoặc mất kết nối sẽ không nhận message và giữ dữ liệu cũ. Vì vậy pub/sub invalidation **vẫn phải đi kèm TTL** làm lưới an toàn. Redis 6+ có client-side caching (RESP3 tracking) giải quyết bài toán này chặt chẽ hơn.

Khi nào L1 xứng đáng: đường đi rất nóng (>5000 req/s/node), dữ liệu chịu được cũ vài giây, và L2 đang là điểm nghẽn hoặc hot key. Khi không thỏa, L1 chỉ thêm một lớp phải suy luận.

---

## 9. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Cache-aside | Đơn giản, cache là tùy chọn | Miss tốn 3 chặng | Mặc định |
| Read-through | Code gọn | Cache thành dependency bắt buộc | Có nhiều consumer, cache layer chín |
| Write-through | Cache luôn khớp DB | Ghi chậm hơn | Dữ liệu đọc ngay sau khi ghi |
| Write-behind | Ghi rất nhanh, gom lô | Mất dữ liệu nếu cache chết | Counter, metric |
| Stale-while-revalidate | Không ai chờ; chống stampede | Luôn có độ cũ nhỏ | Dữ liệu đọc nhiều, tính đắt |
| TTL dài | Hit ratio cao, tải DB thấp | Dữ liệu cũ lâu | Dữ liệu ít đổi |
| TTL ngắn | Dữ liệu mới | Nhiều miss, tải DB cao | Dữ liệu đổi thường |
| L1 + L2 | Độ trễ thấp nhất, chống hot key | Không xóa L1 từ xa được | Đường đi rất nóng |
| Cache negative result | Chống penetration | Có thể trả "không tồn tại" sau khi đã tạo | Không gian key mở cho client |
| CDN cho API response | Giảm tải và độ trễ rất nhiều | Invalidation phức tạp; rủi ro lộ dữ liệu riêng tư | Nội dung công khai, ít đổi |

---

## 10. Checklist

```text
Thiết kế
□ Trả lời được: dữ liệu này được phép cũ bao lâu? (câu hỏi nghiệp vụ)
□ MỌI key có TTL — kể cả khi đã có invalidation chủ động
□ TTL có jitter
□ Thứ tự: ghi DB → xóa cache (không phải ngược lại)
□ Xóa key khi dữ liệu đổi, không ghi lại giá trị mới
□ Đã cân nhắc versioned key cho thay đổi ảnh hưởng nhiều key

Chống ba chế độ hỏng
□ Stampede: single-flight hoặc stale-while-revalidate
□ Penetration: cache negative result và/hoặc bloom filter
□ Avalanche: cache warming, có circuit breaker/shedding trước DB
□ ĐÃ THỬ: flush cache dưới tải production trên staging — hệ thống còn sống?

Vận hành
□ Hit ratio đo theo TỪNG loại key, không chỉ tổng
□ Có alert cho hit ratio sụt đột ngột (dấu hiệu bug invalidation hoặc cache chết)
□ Hot key được phát hiện và xử lý (L1 hoặc nhân bản key)
□ Eviction policy phù hợp (lfu nếu có job quét toàn bộ dữ liệu)
□ Redis không trộn vai trò cache và store bền trong cùng instance

CDN
□ Asset tĩnh: hash trong tên file + immutable, không cần purge
□ stale-if-error đã bật cho nội dung đọc
□ Cache-Control: private/no-store cho dữ liệu theo user
□ Đã kiểm tra không có response riêng tư nào bị cache ở edge
```

---

## 11. Real-world

| Ví dụ | Điểm đáng học |
|---|---|
| **Facebook TAO** | Lớp cache riêng cho social graph, read-through + write-invalidation, quy mô ~1 tỉ QPS. Bài học: khi truy cập đủ đặc thù, một cache layer chuyên biệt thắng cache tổng quát |
| **Twitter timeline** | Precompute timeline vào Redis; **không** fan-out cho celebrity — xem [realtime_scale_designs.md](../case_studies/realtime_scale_designs.md) |
| **Stack Overflow** | Quy mô rất lớn với hạ tầng cache đơn giản, hit ratio rất cao. Bài học: cache đúng chỗ quan trọng hơn cache phức tạp |
| **Netflix EVCache** | Memcached nhiều bản sao trên nhiều AZ; ghi vào tất cả, đọc từ AZ gần → chịu được mất một AZ |

---

## 12. Ghi chú – chủ đề tiếp theo

- [databases_design.md](databases_design.md): read replica so với cache, khi nào chọn cái nào.
- [networking_protocols.md](networking_protocols.md): CDN, DNS, HTTP caching semantics.
- [availability_reliability.md](availability_reliability.md): cache như lớp phòng thủ, load shedding.
- [storage_retrieval.md](storage_retrieval.md): vì sao đọc từ disk đắt, buffer pool.
- `advanced/event_driven_architecture.md`: invalidation qua event.
- [redis package](../../redis/roadmap.md): chi tiết Redis (cluster, persistence, pattern).

Từ khóa mở rộng: XFetch (probabilistic early expiration), Redis client-side caching RESP3, cache coherence, write coalescing, negative caching, bloom/cuckoo filter, surrogate key purge, Caffeine `refreshAfterWrite`, Little's Law áp dụng cho cache miss.

---

*Cập nhật lần cuối: 2026-07-30*
