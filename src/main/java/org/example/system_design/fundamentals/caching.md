# Caching – Chiến lược Cache hệ thống

## What – Cache là gì?

**Cache** là lớp lưu trữ tạm thời, nhanh hơn storage gốc, giúp giảm latency và giảm tải cho DB/backend. Cache lưu kết quả của computations tốn kém hoặc data được truy cập thường xuyên.

```
Without cache:         With cache:
User → DB             User → Cache (1ms) → HIT → return
       (10-50ms)                         → MISS → DB (50ms) → cache → return
```

---

## Hierarchy of Caches

```
CPU Register (< 1ns)
     ↓
L1/L2/L3 CPU Cache (1-10ns)
     ↓
RAM (100ns)
     ↓
Local Disk Cache (100μs)
     ↓
Distributed Cache - Redis (0.5-2ms network)
     ↓
CDN Edge Cache (5-50ms)
     ↓
Database (10-100ms)
     ↓
Object Storage - S3 (50-200ms)
```

---

## Cache Strategies (Patterns)

### 1. Cache-Aside (Lazy Loading)
App tự quản lý cache. Cache chỉ lưu data được request.

```
Read:
  1. App check cache
  2. MISS → App query DB
  3. App write result to cache
  4. Return to client

Write:
  1. App write to DB
  2. App invalidate cache entry
```

```java
public User getUser(Long id) {
    String key = "user:" + id;
    User cached = redis.get(key);
    if (cached != null) return cached;
    
    User user = userRepo.findById(id).orElseThrow();
    redis.setex(key, 3600, user);  // TTL 1 hour
    return user;
}

public void updateUser(User user) {
    userRepo.save(user);
    redis.del("user:" + user.getId());  // Invalidate
}
```

**Ưu:** Chỉ cache data thực sự được dùng; cache miss không ảnh hưởng (chỉ chậm hơn)
**Nhược:** Cache miss dẫn đến 3 trips (check cache → DB → write cache); cache có thể stale nếu quên invalidate

### 2. Read-Through
Cache tự fetch từ DB khi miss (app không cần biết).

```
App → Cache → MISS → Cache auto-fetch from DB → populate → return
App → Cache → HIT → return directly
```

**Tools:** Redis với read-through plugins, NCache, Ehcache với CacheLoader

**Ưu:** App code đơn giản hơn
**Nhược:** First request luôn bị cache miss (cold start); cache layer phải biết cách query DB

### 3. Write-Through
Mỗi write vào DB cũng write vào cache đồng thời.

```
Write:
App → Cache (write) → DB (write) → confirm
     ← ←  consistent read ← ←
```

**Ưu:** Cache luôn có data mới nhất; không có stale reads
**Nhược:** Write latency tăng (2 writes); cache chứa nhiều cold data (never read)

### 4. Write-Behind (Write-Back)
App write vào cache, cache async write vào DB sau.

```
App → Cache (write) → return immediately
                    → async batch write → DB
```

**Ưu:** Write latency cực thấp; batch writes hiệu quả
**Nhược:** Risk data loss nếu cache crash trước khi sync DB; eventual consistency

**Dùng khi:** High-write workload, analytics counters, view counts

### 5. Refresh-Ahead
Proactively refresh cache trước khi TTL hết, với data được dự báo sẽ cần.

```
TTL 60s:
At t=50s → background refresh bắt đầu (còn 10s)
At t=60s → TTL hết, nhưng cache đã được refresh sẵn → no miss
```

**Dùng khi:** Predictable access patterns, data thay đổi có schedule

---

## Eviction Policies (Khi cache đầy)

| Policy | Algorithm | Dùng khi |
|--------|-----------|----------|
| **LRU** (Least Recently Used) | Remove item ít được dùng nhất gần đây | General purpose ✅ |
| **LFU** (Least Frequently Used) | Remove item có số lần access thấp nhất | Long-lived hot data |
| **FIFO** | Remove item cũ nhất (vào trước ra trước) | Time-ordered data |
| **TTL** | Remove sau khi hết thời gian | Data có expiry rõ ràng |
| **Random** | Remove ngẫu nhiên | Đơn giản, khi data đồng đều |

**Redis default:** `allkeys-lru` hoặc `volatile-lru`

---

## Cache Invalidation – Vấn đề khó nhất

> "There are only two hard things in Computer Science: cache invalidation and naming things." — Phil Karlton

### Chiến lược Invalidation

**1. TTL-based (Time-to-Live)**
```
redis.setex("product:123", 300, product)  // expire sau 5 phút
```
Simple nhưng stale window = TTL.

**2. Event-based Invalidation**
```
DB update → publish event → consumer invalidates cache

User updates profile → Kafka event → cache-invalidation-service → DELETE user:123
```

**3. Cache Tags / Dependency Invalidation**
```
Product P123 → tagged ["product", "category:electronics", "brand:apple"]
Update brand Apple → invalidate all "brand:apple" tagged keys
```

**4. Versioned Keys**
```
cache_key = f"user:{id}:v{version}"
Update user → increment version → old key becomes orphan → TTL cleanup
```

### Cache Stampede (Thundering Herd)

**Problem:** TTL hết → 1000 requests hit DB cùng lúc.

```
t=0: 1000 concurrent requests
     Cache miss (TTL expired)
     → 1000 queries hit DB simultaneously → DB overload
```

**Giải pháp 1: Mutex/Lock**
```java
String lockKey = "lock:product:" + id;
if (redis.setnx(lockKey, "1", 10s)) {  // chỉ 1 thread lấy lock
    try {
        data = db.fetch(id);
        redis.set(cacheKey, data);
    } finally {
        redis.del(lockKey);
    }
} else {
    // Chờ và retry
    Thread.sleep(100);
    return getFromCache(id);
}
```

**Giải pháp 2: Probabilistic Early Expiration**
```
Randomly expire cache early khi gần TTL (jitter)
TTL 60s → at 55s có 10% chance refresh → spread misses
```

**Giải pháp 3: Stale-While-Revalidate**
```
Return stale data ngay lập tức + async refresh in background
Client không phải chờ
```

---

## CDN (Content Delivery Network)

### What
Mạng lưới servers phân tán toàn cầu, cache content gần user.

```
User (Vietnam) → CDN PoP (Singapore) → Cache hit → 5ms response
                                      → Cache miss → Origin (US) → 200ms
```

### Cache-Control Headers

```http
# Cache 1 năm, immutable (cho versioned assets)
Cache-Control: public, max-age=31536000, immutable

# Không cache (sensitive data)
Cache-Control: no-store

# Validate với server trước khi dùng cache
Cache-Control: no-cache

# Stale-while-revalidate: dùng stale trong 60s, revalidate trong 1 ngày
Cache-Control: max-age=60, stale-while-revalidate=86400
```

### CDN Invalidation
```bash
# Cloudflare purge
curl -X POST "https://api.cloudflare.com/client/v4/zones/{zone_id}/purge_cache" \
  -H "Authorization: Bearer {token}" \
  -d '{"files":["https://example.com/style.css"]}'

# AWS CloudFront invalidation
aws cloudfront create-invalidation \
  --distribution-id ABCDE12345 \
  --paths "/images/*" "/css/*"
```

---

## Redis Patterns cho System Design

### Distributed Lock
```java
// SET key value NX PX 30000
// NX: chỉ set nếu key chưa tồn tại
// PX: TTL milliseconds
boolean locked = redis.set("lock:order:" + orderId, clientId, 
    SetArgs.Builder.nx().px(30000)) != null;
```

### Rate Limiting (sliding window counter)
```lua
-- Lua script để atomic
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])

local current = redis.call('INCR', key)
if current == 1 then
    redis.call('EXPIRE', key, window)
end
return current <= limit
```

### Session Store
```java
// Spring Session with Redis
@EnableRedisHttpSession(maxInactiveIntervalInSeconds = 1800)
public class SessionConfig {}
// HTTP sessions tự động lưu Redis → stateless app servers
```

### Pub/Sub cho Cache Invalidation
```java
// Publisher (khi data thay đổi)
redis.publish("cache-invalidation", "product:123");

// Subscriber (tất cả app nodes lắng nghe)
redis.subscribe(new JedisPubSub() {
    @Override
    public void onMessage(String channel, String message) {
        localCache.evict(message);  // Clear local L1 cache
    }
}, "cache-invalidation");
```

---

## Multi-Level Caching (L1 + L2)

```
Request → L1 (Caffeine, in-process, <1ms)
        → MISS → L2 (Redis, distributed, 1-2ms)
               → MISS → DB (50ms)
               → populate L2
        → populate L1
```

```java
// Caffeine (local cache)
Cache<String, User> l1 = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(30, SECONDS)
    .build();

public User getUser(Long id) {
    String key = "user:" + id;
    // L1 check
    return l1.get(key, k -> {
        // L1 miss → L2 (Redis) check
        User fromRedis = redis.get(key);
        if (fromRedis != null) return fromRedis;
        
        // L2 miss → DB
        User fromDB = userRepo.findById(id).orElseThrow();
        redis.setex(key, 3600, fromDB);
        return fromDB;
    });
}
```

---

## Trade-offs

| Pattern | Consistency | Complexity | Write Perf | Read Perf |
|---------|-------------|------------|------------|-----------|
| Cache-Aside | Eventually | Low | Normal | High |
| Read-Through | Eventually | Medium | Normal | High |
| Write-Through | Strong | Medium | Lower | High |
| Write-Behind | Eventual | High | Highest | High |

| Cache Size | Trade-off |
|-----------|-----------|
| Too small | High miss rate, DB overload |
| Too large | Memory cost, cold data takes space |
| Optimal | ~80-90% hit rate (measure with cache_hit_ratio) |

---

## Real-world Production

### Twitter Timeline Cache
- Redis để cache precomputed timelines
- Write Fan-out: tweet mới → push vào cache của tất cả followers
- Cache miss với celebs (100M followers → không cache fan-out)

### Facebook TAO (The Associations and Objects)
- Distributed cache layer riêng cho social graph
- Read-through cache với write-invalidation
- ~1 billion QPS

### Stack Overflow
- 1 server Redis, 99.99% cache hit rate
- Dumb simple caching (không over-engineer)

---

## Ghi chú

**Sub-topic tiếp theo:**
- `databases_design.md` – SQL vs NoSQL, Sharding, Replication
- `advanced/event_driven_architecture.md` – Cache invalidation via events
- **Keywords:** Write-coalescing, Cache coherence, Hot key problem, Cache warming, Consistent hashing cho cache, Redis Cluster vs Redis Sentinel, Memcached vs Redis
