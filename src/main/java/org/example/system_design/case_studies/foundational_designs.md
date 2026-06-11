# Case Studies – Foundational Designs (URL Shortener, Distributed ID, Rate Limiter)

> Áp dụng RESHADED ([../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md)). Mỗi bài: Requirements → Estimation → API → Data Model → Design → Deep Dive → Trade-offs.

---

# 1. Design a URL Shortener (TinyURL / bit.ly)

### Requirements
- **Functional**: rút gọn URL dài → short code; redirect short → long; (tùy chọn) analytics, custom alias, expiry.
- **Non-functional**: latency redirect < 100ms, HA 99.99%, **read-heavy** (100:1), short code không đoán được.

### Estimation
```
100M URL mới/ngày → write ~1,160 QPS; read 100:1 → ~116,000 QPS (đỉnh ~230K)
Storage: 100M × 500 bytes × 5 năm ≈ 90 TB → cần sharding/NoSQL
Short code: base62 (a-zA-Z0-9), 7 ký tự = 62^7 ≈ 3.5 nghìn tỷ → đủ
```

### API & Data Model
```
POST /shorten {longUrl, customAlias?, ttl?} → {shortUrl}
GET  /{shortCode} → 301/302 redirect

Bảng url_mapping: short_code (PK), long_url, created_at, expire_at, user_id
```

### How – Cách sinh short code
| Cách | Ưu | Nhược |
|------|----|----|
| **Hash (MD5/SHA) → base62, lấy 7 ký tự** | Đơn giản | Collision → phải xử lý (rehash/append) |
| **Counter + base62 encode** (distributed ID) | Không collision, ngắn | Đoán được tuần tự → cần xáo (xem bài 2) |
| **Pre-generated keys (KGS)** | Nhanh, không collision lúc request | Cần service sinh trước + storage |

### Design & Deep Dive
```
Client → CDN → LB → App → Cache (Redis: short→long) → DB (sharded by short_code)
Redirect path (đọc): Redis hit ~99% → trả ngay; miss → DB → set cache
Write path: sinh code (KGS/counter) → ghi DB → cache
```
- **301 vs 302**: 301 (permanent) → browser cache, giảm tải nhưng mất analytics & không đổi được; **302** (temporary) → mỗi lần qua server (analytics được, tải cao hơn). Thường chọn 302 nếu cần analytics.
- Cache short→long (read-heavy → cache là chìa khóa). Analytics: ghi async qua queue (Kafka) → không chặn redirect.
- Shard DB theo `short_code` (hash) → phân tán đều. Liên hệ [../fundamentals/databases_design.md](../fundamentals/databases_design.md), [../fundamentals/caching.md](../fundamentals/caching.md).

### Trade-offs
- Hash (dễ, có collision) vs counter (không collision, đoán được) vs KGS (nhanh, thêm service).
- 301 (cache, giảm tải) vs 302 (analytics, tải cao). Strong vs eventual cho analytics (eventual ok).

---

# 2. Design a Distributed Unique ID Generator (Snowflake)

### Requirements
- ID **duy nhất toàn cục**, **64-bit** (vừa BIGINT), **gần như tăng dần theo thời gian** (sortable, tốt cho index/B-tree), throughput cao, không phụ thuộc 1 điểm trung tâm.

### Compare – Các cách sinh ID
| Cách | Unique | Sortable | Vấn đề |
|------|--------|----------|--------|
| UUID v4 (random 128-bit) | ✅ | ❌ | To (128-bit), random → index fragmentation |
| Auto-increment DB | ✅ | ✅ | SPOF, không scale ghi, lộ số lượng |
| DB ticket server (Flickr) | ✅ | ✅ | SPOF (giảm bằng 2 server even/odd) |
| **Snowflake** (Twitter) | ✅ | ✅ (theo thời gian) | Phụ thuộc đồng hồ (clock skew) |
| UUID v7 (time-ordered) | ✅ | ✅ | 128-bit |

### How – Snowflake 64-bit layout
```
| 1 bit (0) | 41 bits timestamp (ms từ epoch) | 10 bits machine id | 12 bits sequence |
  unused      ~69 năm                            1024 máy            4096 id/ms/máy
→ mỗi máy sinh tới 4096 ID mỗi millisecond, không cần phối hợp → tăng dần đại thể theo thời gian
```
### Deep Dive – các vấn đề
- **Clock skew / NTP lùi giờ**: timestamp lùi → ID trùng/đảo. Giải: phát hiện clock đi lùi → chờ hoặc dùng last-timestamp; HLC (xem [../fundamentals/distributed_systems_theory.md](../fundamentals/distributed_systems_theory.md)).
- **Machine id assignment**: cấp qua ZooKeeper/etcd (consensus) hoặc config; tránh trùng machine id.
- **Sequence overflow** trong 1ms → chờ sang ms kế.
- Ứng dụng: short code (bài 1) có thể dùng counter/Snowflake rồi base62 + xáo để chống đoán.

### Trade-offs
- Snowflake: không coordination per-request, sortable, nhỏ — nhưng phụ thuộc clock & cần cấp machine id. UUID: zero-coordination nhưng to & không sortable (trừ v7).

---

# 3. Design a Distributed Rate Limiter

> Thuật toán chi tiết (token/leaky bucket, sliding window) đã có ở [../saas/rate_limiting.md](../saas/rate_limiting.md). Đây tập trung **góc thiết kế hệ thống**.

### Requirements
- Giới hạn N request/đơn vị thời gian theo key (user/IP/API key); **chính xác hợp lý**, **latency thấp** (nằm trên hot path), phân tán (nhiều API node), fail-open hay fail-closed?

### Estimation
```
1M user, 100 req/user/ngày, giới hạn 10 req/s → counter check trên MỖI request
→ rate limiter phải nhanh (< 1ms) & chịu QPS = tổng QPS hệ thống
```

### How – Đặt ở đâu & lưu state ở đâu
```
Client → API Gateway (rate limit ở đây, tập trung) → Services
hoặc:   mỗi service tự limit (middleware) — cần state CHIA SẺ
State: Redis (counter/token theo key) — atomic qua Lua script để tránh race
```
- **Thuật toán**: token bucket (cho burst), sliding window log/counter (chính xác hơn fixed window). Chi tiết: [../saas/rate_limiting.md](../saas/rate_limiting.md).
- **Distributed counter**: Redis INCR + EXPIRE (fixed window) hoặc sorted set (sliding window) — chạy bằng **Lua script** để atomic (đọc-tính-ghi 1 lần). Liên hệ [../../redis/redis_patterns.md](../../redis/redis_patterns.md).

### Deep Dive
- **Race condition**: nhiều node cùng INCR 1 key → dùng atomic op/Lua. 
- **Hot key**: 1 user/key tải cực cao → shard counter, hoặc local approximate + sync.
- **Latency vs chính xác**: kiểm tra Redis mỗi request (chính xác, +1 RTT) vs local token bucket đồng bộ định kỳ (nhanh, kém chính xác).
- **Fail-open vs fail-closed**: Redis chết → cho qua (fail-open, ưu tiên availability) hay chặn (fail-closed, ưu tiên bảo vệ)? Tùy nghiệp vụ.
- **Response**: HTTP 429 + header `Retry-After`, `X-RateLimit-Remaining`.

### Trade-offs
- Centralized (gateway + Redis): nhất quán, dễ quản nhưng +RTT & Redis là dependency nóng.
- Distributed local: nhanh nhưng kém chính xác (vượt giới hạn cục bộ).
- Fixed window (đơn giản, có burst ở biên) vs sliding window (mượt, tốn hơn).

---

## Ghi chú
**Sub-topic liên quan:**
- [realtime_scale_designs.md](realtime_scale_designs.md) – news feed, chat, proximity/geo
- [../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md) – RESHADED, estimation
- [../fundamentals/distributed_systems_theory.md](../fundamentals/distributed_systems_theory.md) – clock skew (Snowflake), atomic/consensus (machine id)
- [../saas/rate_limiting.md](../saas/rate_limiting.md), [../fundamentals/caching.md](../fundamentals/caching.md), [../fundamentals/databases_design.md](../fundamentals/databases_design.md)
- **Keywords:** base62, KGS (key generation service), 301 vs 302, Snowflake bits layout, clock skew, ticket server, UUID v7, Redis Lua atomic, token bucket, sliding window, fail-open/closed, HTTP 429.

*Cập nhật lần cuối: 2026-06-11*
