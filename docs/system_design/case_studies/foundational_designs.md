---
title: "Case Studies – Foundational (URL Shortener, Distributed ID, Rate Limiter)"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 1
---
# Case Studies – Foundational (URL Shortener, Distributed ID, Rate Limiter)

> Áp dụng RESHADED ([../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md)). Tra cứu nhanh: [System Design Glossary](../glossary.md). Tiếp nối: [realtime_scale_designs.md](realtime_scale_designs.md), [platform_designs.md](platform_designs.md).

---

## 1. URL Shortener (TinyURL / bit.ly)

## 1.1 Requirements

**Functional (trong phạm vi)**
- Rút gọn URL dài thành short code; redirect short → long.
- Custom alias (tùy chọn), thời hạn hết hiệu lực.
- Analytics cơ bản: số lần click, theo thời gian.

**Ngoài phạm vi**: quản lý user/team, QR code, link preview.

**Non-functional**
- Redirect p99 < 100ms (đây là đường đi nóng, người dùng chờ trực tiếp).
- Availability 99,99% cho redirect — link chết là mất uy tín, tệ hơn không tạo được link mới.
- **Read-heavy**, khoảng 100:1.
- Short code không đoán được (không cho phép liệt kê link của người khác).

Điểm cần nói ra: **redirect và tạo link có yêu cầu availability khác nhau**. Tạo link lỗi thì người dùng thử lại; redirect lỗi thì mọi link đã phát hành đều hỏng. Vì vậy hai đường nên được tách và có mức đầu tư khác nhau.

## 1.2 Estimation

```text
Giả định: 100M link mới/ngày, đọc:ghi = 100:1, mỗi bản ghi ~500 B

Write QPS_avg = 100M / 10⁵ = 1.000  → đỉnh ×3 ≈ 3K QPS
Read  QPS_avg = 100.000              → đỉnh ×3 ≈ 300K QPS

Storage = 100M × 500 B = 50 GB/ngày → 5 năm ≈ 90 TB (chưa replication)
        → vượt một node → sharding hoặc NoSQL phân tán

Không gian short code: base62 (0-9a-zA-Z)
  6 ký tự = 62⁶ ≈ 57 tỉ
  7 ký tự = 62⁷ ≈ 3.500 tỉ    ← đủ cho 100M/ngày trong ~95 năm
  → chọn 7 ký tự

Cache: 20% link nóng của 30 ngày ≈ 100M × 30 × 0,2 × 500 B ≈ 300 GB
  → thực tế phân bố truy cập rất lệch (Zipf): 1% link chiếm >50% traffic
  → cache 20–50 GB đã đạt hit ratio rất cao
```

Nhận xét Zipf ở dòng cuối là điều đáng nói trong phỏng vấn: nó biến "cần 300GB cache" thành "vài chục GB là đủ", và cho thấy bạn hiểu phân bố truy cập thật.

## 1.3 API và data model

```text
POST /v1/links
  { "longUrl": "...", "customAlias": "...", "expiresAt": "..." }
  → 201 { "shortUrl": "https://sho.rt/aB3xK9p", "code": "aB3xK9p" }

GET /{code}
  → 302 Location: <longUrl>        (hoặc 404 / 410 nếu đã hết hạn)

GET /v1/links/{code}/stats
  → { "clicks": 12345, "byDay": [...] }
```

```text
Bảng links:
  code        VARCHAR(7)  PK        ← shard key
  long_url    TEXT
  owner_id    BIGINT NULL
  created_at  TIMESTAMP
  expires_at  TIMESTAMP NULL

Bảng click_events (append-only, ghi bất đồng bộ):
  code, ts, country, referrer, ua_hash    ← partition theo (code, ngày) hoặc đẩy sang OLAP
```

Điểm thiết kế: **tách analytics khỏi bảng links**. Nếu tăng một counter trong bảng links mỗi lần redirect, một link viral sẽ tạo hot row và làm chậm chính đường redirect.

## 1.4 Sinh short code – ba cách

| Cách | Cơ chế | Ưu | Nhược |
|---|---|---|---|
| **Hash rồi lấy 7 ký tự** | `base62(sha256(longUrl))[0..7]` | Không cần state; cùng URL → cùng code | Có collision → phải kiểm tra và thử lại |
| **Counter + base62** | ID tăng dần → encode | Không collision, code ngắn nhất | **Đoán được tuần tự** → phải làm nhiễu |
| **KGS (Key Generation Service)** | Sinh sẵn code vào bảng, cấp lô cho app | Nhanh nhất lúc request, không collision | Thêm một service + storage phải quản |

Cách phổ biến trong thực tế là counter + làm nhiễu:

```text
1. Lấy ID từ Snowflake hoặc từ bộ cấp phát lô (mỗi app node xin trước 10.000 id)
2. Làm nhiễu để không đoán được tuần tự:
   - XOR/hoán vị bit với một khóa bí mật, hoặc
   - Feistel network / block cipher trên số nguyên (bijective → không collision)
3. base62 encode → 7 ký tự
```

Điểm quan trọng: dùng phép biến đổi **song ánh (bijective)** thay vì hash. Song ánh giữ được tính "không collision" của counter đồng thời phá tính tuần tự — có được cả hai ưu điểm mà không cần kiểm tra trùng.

Với custom alias, xử lý riêng: kiểm tra `INSERT ... IF NOT EXISTS` để tránh race, và giữ danh sách từ khóa bị chặn (`api`, `admin`, `login`...).

## 1.5 Design

```text
GHI (3K QPS đỉnh — không phải bài toán khó):
Client → LB → Link Service → sinh code → INSERT DB → ghi cache → trả

ĐỌC (300K QPS đỉnh — đây là bài toán):
Client → CDN/edge → LB → Redirect Service
                            → L1 cache (in-process, TTL 60s)
                            → L2 Redis (code → longUrl)
                            → DB (sharded theo code)
                          → 302 + ghi click event vào Kafka (bất đồng bộ, fire-and-forget)
                                                    → consumer → OLAP store
```

## 1.6 Deep dive

**301 vs 302** — quyết định có hệ quả lớn:

| | 301 Moved Permanently | 302 Found |
|---|---|---|
| Browser cache | Có, rất lâu (khó xóa) | Không (hoặc theo Cache-Control) |
| Tải lên server | Giảm mạnh sau lần đầu | Mỗi lần click đều tới server |
| Analytics | **Mất** các lần click đã cache | Đầy đủ |
| Đổi đích sau này | Gần như không thể | Được |

Với dịch vụ có analytics và cho phép sửa link, **302 là lựa chọn đúng** dù tốn tài nguyên hơn. Nếu chỉ cần redirect thuần và muốn giảm tải tối đa thì 301 với `Cache-Control: max-age=86400`.

**Link đã hết hạn**: trả `410 Gone` thay vì `404` — phân biệt "chưa từng có" và "đã từng có nhưng hết hạn", hữu ích cho debug và cho SEO.

**Chống lạm dụng**: URL shortener là công cụ ưa thích của phishing. Cần: kiểm tra URL đích với danh sách đen (Safe Browsing API), rate limit theo IP/account khi tạo link, và trang cảnh báo trung gian cho domain đáng ngờ.

**Cache miss storm**: một link viral vừa hết TTL → xem [caching.md](../fundamentals/caching.md) mục 4.1 (single-flight + TTL jitter).

## 1.7 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Hash vs counter vs KGS | Đơn giản ↔ không collision ↔ nhanh nhất nhưng thêm service |
| 301 vs 302 | Tải server ↔ analytics và khả năng sửa link |
| Analytics đồng bộ vs bất đồng bộ | Chính xác tuyệt đối ↔ độ trễ redirect (chọn bất đồng bộ) |
| 6 vs 7 ký tự | URL ngắn hơn ↔ không gian và khả năng đoán |
| Cache TTL dài | Hit ratio cao ↔ link đã sửa/xóa vẫn hoạt động một thời gian |

---

## 2. Distributed Unique ID Generator

## 2.1 Requirements

- **Duy nhất toàn cục**, không cần phối hợp mỗi request.
- **64-bit** (vừa `BIGINT`/`long`) — quan trọng vì 128-bit làm index to gấp đôi.
- **Gần như tăng dần theo thời gian** (k-sorted) → tốt cho B-tree index, xem [storage_retrieval.md](../fundamentals/storage_retrieval.md) mục 3.1.
- Throughput cao (hàng chục nghìn ID/giây/node).
- Không có SPOF.

## 2.2 So sánh các cách

| Cách | Unique | Sortable | Kích thước | Vấn đề |
|---|---|---|---|---|
| **UUID v4** | ✅ (xác suất) | ❌ | 128-bit | Random → page split, index phình ([storage_retrieval.md](../fundamentals/storage_retrieval.md) mục 3.1) |
| **UUID v7** | ✅ | ✅ (theo ms) | 128-bit | Vẫn 128-bit, nhưng đã giải quyết tính tuần tự |
| **DB auto-increment** | ✅ | ✅ | 64-bit | SPOF, không scale ghi, tiết lộ khối lượng nghiệp vụ |
| **DB ticket server (Flickr)** | ✅ | ✅ | 64-bit | SPOF (giảm bằng 2 server chẵn/lẻ), thêm round-trip |
| **Bộ cấp phát lô (segment)** | ✅ | ✅ đại thể | 64-bit | Mất lô khi restart (khoảng trống); vẫn cần store |
| **Snowflake** | ✅ | ✅ | 64-bit | Phụ thuộc đồng hồ; cần cấp machine id |

## 2.3 Snowflake

```text
 1 bit  │ 41 bits              │ 10 bits      │ 12 bits
 unused │ timestamp (ms)       │ machine id   │ sequence
 (dấu)  │ ~69 năm từ epoch     │ 1.024 node   │ 4.096 id/ms/node

→ mỗi node sinh tới 4,096 triệu ID/giây mà KHÔNG cần phối hợp với node khác
→ ID tăng dần đại thể theo thời gian (giữa các node có thể lệch trong cùng ms)
```

```java
public synchronized long nextId() {
    long now = clock.millis();

    if (now < lastTimestamp) {                    // ĐỒNG HỒ ĐI LÙI
        long drift = lastTimestamp - now;
        if (drift > MAX_TOLERATED_DRIFT_MS) {     // lùi nhiều → không thể chờ
            throw new IllegalStateException("Clock moved backwards by " + drift + "ms");
        }
        busyWaitUntil(lastTimestamp);             // lùi ít → chờ cho tới khi đuổi lại
        now = clock.millis();
    }

    if (now == lastTimestamp) {
        sequence = (sequence + 1) & SEQUENCE_MASK;
        if (sequence == 0) now = waitNextMillis(lastTimestamp);   // hết sequence trong ms này
    } else {
        sequence = 0;
    }

    lastTimestamp = now;
    return ((now - EPOCH) << 22) | (machineId << 12) | sequence;
}
```

## 2.4 Deep dive – bốn vấn đề thật

| Vấn đề | Nguyên nhân | Xử lý |
|---|---|---|
| **Đồng hồ đi lùi** | NTP điều chỉnh giật | Phát hiện và chờ (code trên); dùng monotonic clock nội bộ; NTP với slew thay vì step |
| **Cấp machine id** | Hai node cùng id → **ID trùng** | ZooKeeper/etcd ephemeral sequential; hoặc StatefulSet ordinal trong K8s; hoặc lease có gia hạn |
| **Hết sequence trong 1ms** | Burst > 4096 id/ms | Chờ sang ms kế (code trên); hoặc mở rộng bit sequence, thu bit machine |
| **Rò rỉ thông tin** | ID chứa timestamp → suy ra thời điểm và tốc độ tạo | Không dùng ID này làm token công khai; làm nhiễu nếu cần (mục 1.4) |

Vấn đề cấp machine id là vấn đề nghiêm trọng nhất vì hậu quả (ID trùng) âm thầm và khó phát hiện. Trong Kubernetes, **StatefulSet ordinal** là giải pháp gọn: pod `id-gen-3` luôn có machine id 3, và K8s đảm bảo không có hai pod cùng ordinal.

## 2.5 Chọn cách nào

```text
Có sẵn PostgreSQL, throughput vừa phải        → sequence với CACHE (đơn giản nhất, đủ tốt)
Cần ID cho bảng lớn, ghi nhiều, phân tán      → Snowflake
Không muốn vận hành gì thêm, chấp nhận 128-bit → UUID v7
Cần ID ngắn cho người dùng thấy               → counter + song ánh + base62 (mục 1.4)
Cần ID không suy ra được thông tin gì         → random 128-bit (UUID v4) làm token, ID nội bộ riêng
```

Hàng cuối là mẫu tốt: **tách ID nội bộ (tăng dần, để index) và ID công khai (random, để an toàn)**. Nó cho cả hiệu năng và bảo mật, chỉ tốn một cột.

---

## 3. Distributed Rate Limiter

> Thuật toán chi tiết ở `saas/rate_limiting.md`. Ở đây tập trung góc thiết kế hệ thống.

## 3.1 Requirements

- Giới hạn N request/khoảng theo key (user, IP, API key, tenant).
- Nằm trên **đường đi nóng** → phải rất nhanh (< 1–2ms) và không được là SPOF.
- Chịu QPS bằng **tổng QPS của toàn hệ thống**.
- Chính xác hợp lý (không cần tuyệt đối), công bằng giữa các key.
- Quyết định trước: khi bộ đếm không truy cập được thì **fail-open hay fail-closed**?

## 3.2 Estimation

```text
Hệ thống 300K QPS đỉnh → rate limiter cũng phải chịu 300K QPS
Mỗi lần kiểm tra: 1 round-trip Redis ≈ 0,3–1ms

Nếu kiểm tra Redis cho MỌI request:
  300K QPS trên một Redis instance → vượt ngưỡng (~100K QPS/instance)
  → phải shard theo key, hoặc giảm số lần gọi (mục 3.5)

State mỗi key: token bucket cần ~2 field (tokens, lastRefill) ≈ 100 B
  10M key hoạt động → ~1 GB → vừa RAM
```

## 3.3 Đặt ở đâu

```text
Phương án A — tập trung ở gateway:
  Client → API Gateway (kiểm tra) → Services
  + Một chỗ quản lý, chính sách nhất quán, service không phải biết gì
  − Thêm một hop; gateway thành điểm nóng

Phương án B — mỗi service tự làm (middleware):
  + Không thêm hop; giới hạn riêng theo từng service
  − State phải chia sẻ; chính sách rải rác

Phương án C — hai tầng:
  Edge/CDN: chặn thô theo IP (chống DDoS, rất rẻ)
  Gateway:  giới hạn theo API key/tenant (chính xác)
  Service:  bảo vệ tài nguyên riêng (ví dụ endpoint export nặng)
```

Phương án C là mô hình thực tế: **mỗi tầng chặn cái nó chặn hiệu quả nhất**. Chặn DDoS ở gateway là quá muộn và quá đắt; chặn theo tenant ở edge thì edge không biết tenant.

## 3.4 State và tính atomic

Vấn đề cốt lõi: nhiều node cùng đọc-tính-ghi một bộ đếm → race condition.

```lua
-- Token bucket atomic bằng Lua (đọc-tính-ghi trong một lần thực thi)
-- KEYS[1] = bucket key
-- ARGV: 1=capacity, 2=refillPerSec, 3=nowMs, 4=requested
local capacity  = tonumber(ARGV[1])
local refill    = tonumber(ARGV[2])
local now       = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

local data   = redis.call('HMGET', KEYS[1], 'tokens', 'ts')
local tokens = tonumber(data[1]) or capacity
local ts     = tonumber(data[2]) or now

-- nạp lại token theo thời gian đã trôi
local delta = math.max(0, now - ts) / 1000.0
tokens = math.min(capacity, tokens + delta * refill)

local allowed = tokens >= requested
if allowed then tokens = tokens - requested end

redis.call('HMSET', KEYS[1], 'tokens', tokens, 'ts', now)
redis.call('PEXPIRE', KEYS[1], math.ceil(capacity / refill * 1000) + 1000)

return { allowed and 1 or 0, math.floor(tokens) }
```

Ba chi tiết trong script này đáng chú ý:

1. **Nạp lại theo thời gian trôi (lazy refill)**, không cần job nền — bucket tự đúng khi được truy cập.
2. **`PEXPIRE`** để key không hoạt động tự dọn — không có nó, Redis sẽ phình theo số key từng xuất hiện.
3. **Trả về số token còn lại** để đặt header `X-RateLimit-Remaining` cho client.

## 3.5 Deep dive

**Giảm số lần gọi Redis** — quan trọng khi QPS rất cao:

```text
Local token bucket + đồng bộ định kỳ:
  Mỗi node được cấp trước một phần quota (ví dụ limit/số_node × 1,2)
  Tiêu thụ cục bộ, không gọi Redis
  Đồng bộ với Redis mỗi 100–500ms để hiệu chỉnh

+ Gần như không có độ trễ thêm; chịu được Redis chết
− Kém chính xác ở biên (có thể vượt giới hạn tổng một chút)
→ Đánh đổi rất tốt cho rate limit chống lạm dụng; KHÔNG dùng cho quota tính tiền
```

Phân biệt này quan trọng: **rate limit để bảo vệ hệ thống** thì gần đúng là đủ; **quota để tính tiền** thì phải chính xác và nên đo bằng đường riêng (metering, xem `saas/billing_metering.md`).

**Hot key**: một tenant lớn hoặc một IP bị tấn công tạo ra một key cực nóng. Xử lý: shard bộ đếm của key đó (`key:shard0..shardN`, mỗi shard giới hạn `limit/N`), hoặc chuyển key đó sang local bucket.

**Fail-open vs fail-closed**:

| | Fail-open (cho qua) | Fail-closed (chặn) |
|---|---|---|
| Ưu tiên | Availability | Bảo vệ |
| Rủi ro | Bị lạm dụng trong lúc Redis chết | Toàn bộ hệ thống dừng khi Redis chết |
| Phù hợp | Rate limit chống lạm dụng thông thường | Bảo vệ tài nguyên đắt/nguy hiểm, chống gian lận |

Mặc định nên là **fail-open cho rate limit chung** (Redis chết không nên làm sập cả API) nhưng **fail-closed cho các endpoint đặc biệt nhạy cảm** (gửi OTP, giao dịch). Đây là quyết định phải viết ra, không để mặc định thư viện quyết.

**Phản hồi đúng chuẩn**:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 12
RateLimit-Limit: 1000
RateLimit-Remaining: 0
RateLimit-Reset: 12
```

Trả `Retry-After` không phải chuyện lễ nghi: nó cho client biết chờ bao lâu, thay vì để client retry ngay và làm tình hình tệ hơn.

## 3.6 So sánh thuật toán

| Thuật toán | Cho burst? | Chính xác | Bộ nhớ | Vấn đề |
|---|---|---|---|---|
| **Fixed window counter** | Có (ở biên) | Thấp | Rất nhỏ | Cho phép 2× limit quanh biên cửa sổ |
| **Sliding window log** | Không | Cao nhất | Lớn (lưu mọi timestamp) | Tốn RAM với key nóng |
| **Sliding window counter** | Ít | Tốt | Nhỏ | Xấp xỉ, đủ dùng |
| **Token bucket** | **Có, kiểm soát được** | Tốt | Nhỏ | Cần hiểu capacity vs refill rate |
| **Leaky bucket** | Không (làm mượt) | Tốt | Nhỏ | Không cho burst — có thể không mong muốn |

Token bucket thường là lựa chọn đúng vì nó mô hình hóa được đúng nhu cầu thật: *"trung bình 100 req/s, nhưng cho phép dồn 500 request một lúc"* — điều mà fixed window không diễn đạt được và leaky bucket không cho phép.

## 3.7 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Tập trung (gateway + Redis) | Nhất quán, dễ quản ↔ thêm hop, Redis thành dependency nóng |
| Local bucket + đồng bộ | Rất nhanh, chịu Redis chết ↔ kém chính xác ở biên |
| Fail-open | Availability ↔ có cửa sổ bị lạm dụng |
| Fail-closed | Bảo vệ ↔ Redis chết là sập API |
| Sliding window log | Chính xác nhất ↔ tốn RAM |
| Token bucket | Cho burst có kiểm soát ↔ cần tinh chỉnh hai tham số |

---

## Ghi chú – chủ đề tiếp theo

- [realtime_scale_designs.md](realtime_scale_designs.md): news feed, chat, proximity/geo.
- [platform_designs.md](platform_designs.md): object storage, typeahead, payment, notification.
- [../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md): framework và estimation.
- [../fundamentals/caching.md](../fundamentals/caching.md): cache stampede, hot key.
- [../fundamentals/storage_retrieval.md](../fundamentals/storage_retrieval.md): vì sao ID tăng dần quan trọng cho index.
- `saas/rate_limiting.md`: thuật toán rate limit chi tiết.

Từ khóa mở rộng: base62, Feistel network cho song ánh, Zipf distribution, KGS, 301 vs 302, Safe Browsing API, Snowflake bit layout, monotonic clock, NTP slew vs step, StatefulSet ordinal, lazy refill, `RateLimit-*` header (RFC draft), sharded counter.

---

*Cập nhật lần cuối: 2026-07-30*
