# Rate Limiting – giới hạn công bằng và bảo vệ công suất

> Rate limiting không chỉ là trả `429` sau N request. Một limiter production phải
> định nghĩa đúng identity, đơn vị chi phí, burst, phạm vi local/global, hành vi khi
> backend limiter lỗi và cách phối hợp với concurrency limit, queue và load shedding.

---

## 1. Rate limiting giải bài toán gì?

- ngăn một client/tenant chiếm hết tài nguyên;
- bảo vệ database, provider hoặc workload đắt tiền;
- thực thi entitlement theo plan;
- giảm brute-force/scraping và business abuse;
- tạo backpressure có kiểm soát;
- giữ headroom khi overload.

```text
Incoming traffic
      │
      ▼
Rate / concurrency / cost policy
  ├─ allow → application → downstream
  └─ deny  → 429 / queue / degrade
```

Rate limiter **không thay thế DDoS protection** ở network/edge. Nếu request đã tới
application và buộc gọi Redis cho từng packet, volumetric attack có thể đã thắng.

---

## 2. Phân biệt các cơ chế gần nhau

| Cơ chế | Kiểm soát |
|---|---|
| Rate limit | Số đơn vị trên thời gian |
| Quota | Tổng đơn vị trong chu kỳ/ngân sách |
| Concurrency limit | Số công việc đang chạy |
| Throttling | Làm chậm/điều tiết thay vì chỉ reject |
| Load shedding | Từ chối khi hệ thống quá tải |
| Circuit breaker | Ngừng gọi dependency đang lỗi |
| Backpressure | Truyền tín hiệu giảm tốc về upstream |
| Queue | Hấp thụ burst, không tạo thêm công suất |

Một API có thể đồng thời áp:

```text
100 request/s + burst 200
20 request đang chạy
1 triệu request/tháng
5 export đồng thời
```

---

## 3. Một policy đầy đủ

Không chỉ có `limit=100`:

```text
subject      = tenant:abc + user:123
operation    = POST /exports
resource     = analytics-cluster-eu
unit/cost    = estimated_rows
rate         = 10_000 units/minute
burst        = 2_000 units
concurrency  = 2
scope        = global
plan/version = enterprise/v4
failure_mode = fail-closed
```

Cần trả lời:

1. Ai bị giới hạn?
2. Thao tác/tài nguyên nào?
3. Đếm request, byte, row, token hay cost unit?
4. Cho burst bao nhiêu và trong bao lâu?
5. Limit áp trên một instance, region hay toàn cầu?
6. Khi limiter unavailable thì làm gì?
7. Policy thay đổi có hiệu lực khi nào?

---

## 4. Chọn identity/key đúng

Các dimension:

- tenant/account;
- user/service account;
- API key/client ID;
- operation/resource;
- IP/network;
- plan/entitlement;
- region/provider.

IP không phải identity đáng tin:

- nhiều user có thể chung NAT;
- attacker xoay IP;
- IPv6 có không gian lớn;
- proxy chain có thể giả `X-Forwarded-For`.

Chỉ tin client IP do trusted proxy/gateway chuẩn hóa. Với authenticated API, tenant
+ subject + operation thường công bằng hơn chỉ IP.

Key không chứa secret nguyên bản; hash/HMAC API key nếu cần.

---

## 5. Fixed Window Counter

Chia thời gian thành cửa sổ:

```text
limit = 100/minute

12:00:00–12:00:59 → counter
12:01:00–12:01:59 → counter mới
```

Ưu: đơn giản, O(1) memory/key. Nhược: boundary burst:

```text
100 request ở 12:00:59
100 request ở 12:01:00
→ 200 request gần như cùng lúc
```

Phù hợp quota thô hoặc nơi burst ở biên chấp nhận được. Capacity downstream phải
chịu được burst gần `2 × limit` quanh ranh giới.

---

## 6. Sliding Window Log

Lưu timestamp từng request trong khoảng:

```text
now = 12:01:30
window = (12:00:30, 12:01:30]
remove timestamp cũ → count → add now nếu allow
```

Ưu: chính xác. Nhược:

- O(number of requests) memory;
- cleanup và sorted-set operation;
- hot key tốn CPU/memory;
- retry check cũng tạo tải.

Phù hợp limit nhỏ nhưng cần chính xác, ví dụ vài lần reset credential mỗi giờ; không
phù hợp hàng triệu request/s với log từng request.

---

## 7. Sliding Window Counter

Xấp xỉ bằng current + trọng số window trước:

```text
estimate = current_count
         + previous_count × remaining_fraction_of_previous
```

Ví dụ giữa window:

```text
previous = 80
current  = 30
elapsed  = 30%
estimate = 30 + 80 × 70% = 86
```

Ưu: O(1), mượt hơn fixed window. Nhược: xấp xỉ phân bố request trong window trước.
Phù hợp API general-purpose khi không cần chính xác tuyệt đối từng request.

---

## 8. Token Bucket

Bucket có:

- `capacity`: burst tối đa;
- `refill_rate`: tốc độ bền vững;
- mỗi request tiêu thụ `cost` token.

```text
capacity = 100
refill   = 10 token/s

bucket đầy → burst 100 request ngay
sau đó tốc độ bền vững ≈ 10 request/s
```

Cập nhật lazy:

```text
tokens = min(capacity,
             old_tokens + (now - last_refill) × refill_rate)

if tokens >= cost:
    tokens -= cost
    allow
else:
    deny và tính wait time
```

Đây là lựa chọn tốt cho API cần burst ngắn nhưng bảo vệ average rate. Burst
capacity phải dựa vào headroom downstream, không chọn tùy ý.

---

## 9. Leaky Bucket và GCRA

### Leaky bucket như queue

Request vào buffer, xử lý ở tốc độ cố định:

```text
bursty input → bounded queue → smooth output
```

Nếu queue đầy: reject. Nó làm mượt nhưng thêm queueing latency; request có thể hết
deadline trước khi tới lượt.

### GCRA

Generic Cell Rate Algorithm theo dõi “theoretical arrival time”, cần một timestamp
trên mỗi key và hỗ trợ burst bằng tolerance. Memory O(1), phù hợp distributed rate
limiter nhưng khó giải thích/debug hơn token bucket.

Nếu team chưa cần đặc tính cụ thể của GCRA, token bucket dễ vận hành hơn.

---

## 10. Concurrency limiter

Rate không bảo vệ workload chậm:

```text
10 request/s × mỗi request 30s
→ khoảng 300 request đồng thời
```

Concurrency limiter:

```text
acquire permit
  ├─ success → execute → release trong finally
  └─ fail    → reject/queue
```

Permit cần lease/timeout hoặc cleanup khi process crash. Với distributed permit,
fencing/owner token giúp tránh release nhầm permit của request khác.

Little’s Law:

```text
concurrency ≈ throughput × average latency
```

Giới hạn rate và concurrency cùng nhau: rate bảo vệ dòng vào, concurrency bảo vệ
thread/connection/memory trong thời gian xử lý.

---

## 11. Weighted/cost-based limiting

Một request không phải một đơn vị công bằng:

| Operation | Cost minh họa |
|---|---:|
| GET order by ID | 1 |
| Search page | 5 |
| Export 30 ngày | 500 |
| Generate AI 1K tokens | 1.000 token units |
| Upload 100 MB | 100 MB units |

Token bucket có thể tiêu thụ `cost` khác nhau. Cost nên:

- dựa trên input biết trước hoặc conservative estimate;
- có max cứng;
- reconcile với actual usage cho billing/quota nếu cần;
- version cùng policy;
- không để client tự khai báo;
- tách financial metering khỏi limiter real-time nếu yêu cầu kế toán khác.

Rate limiter là control, không phải hệ thống billing source of truth.

---

## 12. Hierarchical limit trong SaaS

Một request có thể phải qua nhiều bucket:

```text
Platform global safety
  → region/provider capacity
    → tenant plan
      → user/API key
        → operation
```

Ví dụ:

```text
global payment provider : 5.000/s
tenant enterprise A     : 500/s
user within A           : 50/s
POST /refunds           : 10/min
```

Request chỉ allow nếu **tất cả** policy đạt. Nếu consume bucket A rồi bucket B deny,
không rollback cẩn thận sẽ làm mất token ảo.

Giải pháp:

- evaluate/consume atomically nếu keys cùng store/shard;
- reservation hai bước chỉ khi thật sự cần;
- local coarse bucket trước, global bucket sau và chấp nhận sai số có budget;
- policy hierarchy ít tầng trên hot path.

Với Redis Cluster, multi-key script cần keys cùng hash slot; thiết kế hash tag phải
cân bằng atomicity với hot shard.

---

## 13. Local, global và hybrid

### Local limiter

Mỗi process/proxy có bucket riêng:

```text
10 instances × local limit 100/s
→ effective fleet limit có thể 1.000/s
```

Ưu: rất nhanh, sống khi network/store lỗi. Nhược: không chính xác global, autoscale
làm thay đổi tổng limit, load không đều gây fairness kém.

### Global limiter

Mọi instance hỏi shared rate-limit service/store. Chính xác/fair hơn nhưng thêm
network hop, latency và dependency trên request path.

### Hybrid

```text
local token bucket chặn burst lớn
        ↓
global quota/limiter enforce entitlement
```

Hoặc global service cấp token lease/chunk cho local instance:

```text
global budget 10.000
→ instance A lease 500
→ instance B lease 500
```

Giảm call global nhưng có overshoot bằng tổng lease chưa dùng khi instance lỗi.
Đặt error budget cho độ chính xác.

---

## 14. Distributed correctness và clock

Race:

```text
Instance A read tokens=1
Instance B read tokens=1
A allow, B allow → double-spend
```

Read–decide–write phải atomic bằng:

- Lua/Redis Function;
- transaction/compare-and-set;
- single-writer actor;
- datastore atomic primitive.

Clock:

- fixed/sliding/token algorithms phụ thuộc thời gian;
- client clock lệch có thể refill sai;
- ưu tiên clock của authoritative store;
- clamp negative elapsed;
- monotonic clock cho local limiter;
- không dùng timestamp do untrusted client gửi.

Cross-region strict global limit phải trả coordination latency hoặc chấp nhận
overshoot. Không có “chính xác tuyệt đối, zero latency, luôn available”.

---

## 15. Token Bucket với Redis atomic script

Ví dụ dùng clock Redis và cập nhật trong một script:

```lua
-- KEYS[1] = bucket key
-- ARGV: capacity, refill_tokens_per_ms, requested_cost, ttl_ms
local capacity = tonumber(ARGV[1])
local refill = tonumber(ARGV[2])
local cost = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])

local time = redis.call('TIME')
local now = time[1] * 1000 + math.floor(time[2] / 1000)

local state = redis.call('HMGET', KEYS[1], 'tokens', 'updated_at')
local tokens = tonumber(state[1]) or capacity
local updated = tonumber(state[2]) or now
local elapsed = math.max(0, now - updated)

tokens = math.min(capacity, tokens + elapsed * refill)

local allowed = 0
local retry_after_ms = 0
if tokens >= cost then
  tokens = tokens - cost
  allowed = 1
else
  retry_after_ms = math.ceil((cost - tokens) / refill)
end

redis.call('HSET', KEYS[1], 'tokens', tokens, 'updated_at', now)
redis.call('PEXPIRE', KEYS[1], ttl)

return {allowed, math.floor(tokens), retry_after_ms}
```

Production considerations:

- `refill > 0`, cost/capacity/TTL được validate;
- key gồm trusted subject + normalized operation + policy version;
- TTL đủ để bucket đầy rồi tự xóa;
- script/function được version và load trước;
- timeout ngắn vì limiter nằm trên hot path;
- hot tenant có thể thành hot Redis key;
- benchmark script, replication và failover;
- response retry time là gợi ý, client vẫn thêm jitter.

Floating point có thể gây sai số nhỏ; nếu cần accounting chính xác, dùng integer
micro-token và integer time unit.

---

## 16. Key design và cardinality

```text
rl:{policyVersion}:{tenantHash}:{subjectHash}:{operation}
```

Tránh:

- raw URL có ID → một key/request;
- raw API key/PII trong Redis/log;
- key không TTL;
- policy đổi nhưng dùng state cũ không tương thích;
- operation name không normalized;
- tenant-controlled string làm Redis key không giới hạn.

Estimate memory:

```text
active subjects × active policies × bytes/key
```

Một triệu user × 20 operation có thể thành hàng chục triệu key. Chỉ tạo bucket cho
policy cần, dùng TTL và phân cấp hợp lý.

---

## 17. HTTP response và client contract

Khi vượt limit:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 5
Content-Type: application/problem+json

{
  "type": "https://api.example.com/problems/rate-limit-exceeded",
  "title": "Rate limit exceeded",
  "status": 429,
  "limitPolicy": "orders-write-v4",
  "retryAfterSeconds": 5
}
```

RFC 6585 định nghĩa `429`; response có thể kèm `Retry-After`. Đừng công bố header
`X-RateLimit-*` như chuẩn chung nếu ecosystem chưa thống nhất — document contract
cụ thể của API.

Client:

- tôn trọng `Retry-After`;
- exponential backoff + jitter;
- không để mọi worker retry cùng millisecond;
- ưu tiên queue/coalesce request;
- không retry thao tác non-idempotent nếu outcome không rõ;
- giảm concurrency khi liên tục nhận `429`.

---

## 18. `429`, `503` hay queue?

| Tình huống | Phản hồi |
|---|---|
| Client vượt entitlement/fair-use | `429` |
| Toàn service tạm unavailable/overload | `503` + có thể `Retry-After` |
| Async work chấp nhận xử lý sau | `202` + job/status resource |
| Queue đầy hoặc deadline không đủ | Reject sớm |
| Optional feature quá tải | Degrade/fallback |

Không queue request đồng bộ vô hạn. Queue làm latency tăng và giữ memory; nếu wait
time > deadline, reject sớm tốt hơn.

---

## 19. Fail-open hay fail-closed

Rate-limit store/service lỗi:

### Fail-open

Cho request qua.

- phù hợp read/low-risk, ưu tiên availability;
- nguy cơ overload và vượt quota/cost.

### Fail-closed

Từ chối.

- phù hợp login/payment/expensive provider hoặc compliance;
- limiter lỗi biến thành outage.

### Degraded mode

- local emergency bucket;
- cached policy + conservative limit;
- chỉ cho operation critical;
- reject workload đắt, cho health/read nhẹ;
- circuit breaker với limiter backend.

Chọn theo operation, không một policy cho toàn API. Alert rõ khi degraded vì lúc đó
guarantee đã thay đổi.

---

## 20. Entitlement và plan

Policy không nên hard-code rải trong service:

```text
Plan catalog → tenant entitlement snapshot → rate-limit policy
```

Cần:

- version/effective time;
- upgrade có hiệu lực nhanh;
- downgrade không cắt job đang chạy tùy contract;
- override có expiry/approval;
- default an toàn khi entitlement thiếu;
- cache invalidation;
- audit ai đổi limit;
- tách soft limit cảnh báo và hard limit chặn.

Billing cycle quota cần durable usage ledger/metering, không chỉ Redis counter có
TTL. Đọc [Billing & Metering](billing_metering.md).

---

## 21. Fairness và noisy neighbor

Global FIFO không bảo đảm fairness:

```text
Tenant A enqueue 1.000.000 jobs
Tenant B enqueue 1 job
→ B chờ sau A
```

Pattern:

- per-tenant queue + weighted fair scheduler;
- deficit round robin;
- per-tenant concurrency;
- plan weight nhưng có minimum share;
- separate transactional vs bulk;
- whale tenant dedicated worker/pool;
- max backlog và age SLO.

Rate limit ingress mà worker vẫn consume không công bằng thì noisy neighbor vẫn còn.
Đọc [Multi-tenancy](multi_tenancy.md) mục 16.

---

## 22. Bảo vệ downstream và third-party quota

Limiter nên đặt gần tài nguyên cần bảo vệ:

```text
Gateway limit tenant entitlement
Service limit expensive operation
Client library limit provider quota
DB pool/concurrency limit connection
```

Nếu provider cho 1.000 request/s:

- giữ safety margin;
- trừ traffic retry;
- chia budget theo region/tenant;
- đo response `429`/quota của provider;
- adaptive reduce khi provider chậm;
- queue chỉ nếu công việc còn giá trị khi trễ;
- không cho mỗi app instance tự tin rằng mình sở hữu toàn quota.

---

## 23. Adaptive rate/concurrency limit

Static limit không phản ứng với dependency chậm. Adaptive limiter có thể dùng:

- latency gradient;
- queue depth;
- saturation;
- error/timeout;
- outstanding request.

Ví dụ:

```text
p90 latency tăng + queue tăng
→ giảm concurrency limit
ổn định một thời gian
→ tăng từ từ
```

Nguy cơ:

- oscillation;
- metric delay/noise;
- giảm quá mức khi lỗi không do tải;
- các instance cùng phản ứng tạo herd.

Cần min/max, smoothing, cooldown và canary. Adaptive control bổ sung, không thay
hard safety limit.

---

## 24. Security và chống bypass

- limiter chạy sau khi xác thực khi cần tenant/user identity, nhưng edge limiter
  vẫn chặn anonymous burst trước auth;
- chỉ tin proxy chain đã cấu hình;
- normalize path/method trước chọn policy;
- query/body variation không được tạo route key mới tùy ý;
- WebSocket/GraphQL batch cần limit message/operation/cost bên trong connection/request;
- login/password reset limit theo account + IP/device/risk, tránh khóa nạn nhân chỉ
  bằng IP;
- response không tiết lộ quota tenant khác;
- operator bypass có scope, expiry và audit;
- rate limit không phải authorization.

Attacker có thể phân tán qua nhiều account/IP; sensitive business flow cần fraud/
abuse detection ngoài counter đơn giản.

---

## 25. Rollout policy an toàn

Không bật hard enforcement ngay:

```text
1. Observe: tính decision nhưng không chặn
2. Report: dashboard tenant/client sẽ bị ảnh hưởng
3. Soft limit: warning/header/log
4. Partial canary: một route/tenant/stamp
5. Enforce
6. Review false positive và capacity
```

Policy-as-code:

- schema validation;
- unit test boundary/burst;
- simulation từ traffic history;
- owner/reviewer;
- version và rollback;
- propagation status;
- tránh config thắt nhầm toàn fleet.

---

## 26. Capacity planning

Limiter cũng là một hệ thống phải scale:

```text
limiter QPS ≈ protected request QPS × policy checks/request
```

Nếu một request kiểm 5 bucket, 200K request/s tạo tới 1M logical checks/s nếu không
batch/atomic.

Đánh giá:

- hot key/hot shard;
- store CPU/memory/network;
- replication/failover;
- p99 latency budget;
- timeout/circuit breaker;
- number of active keys + TTL;
- policy cache;
- multi-region coordination;
- overload của limiter chính nó.

Local pre-limit giúp limiter global không trở thành điểm nghẽn đầu tiên khi attack.

---

## 27. Observability

Metric:

- allowed/denied/shadow-denied theo policy, operation, plan;
- `429`/`503`;
- limiter decision latency/error/timeout;
- remaining token distribution;
- hot key/shard;
- fail-open/fail-closed/degraded count;
- concurrent permits/queue age;
- provider quota remaining/error;
- policy version propagation.

Cardinality:

- không label mọi `tenant_id` nếu số lượng lớn;
- dùng plan/stamp/policy/operation;
- top-K heavy hitter;
- log/trace có tenant cụ thể;
- usage pipeline riêng cho billing.

Alert theo tác động: tỷ lệ deny đột biến, limiter backend lỗi, fail-open kéo dài,
downstream saturation dù limiter vẫn allow.

---

## 28. Ví dụ: API export báo cáo

Yêu cầu:

- Free: 2 export/ngày, 1 job đồng thời, tối đa 30 ngày dữ liệu.
- Pro: 50/ngày, 3 đồng thời, tối đa 1 năm.
- Global warehouse: tối đa 20 job nặng đồng thời.

Luồng:

```text
POST /exports
  1. auth + tenant membership
  2. validate range theo plan
  3. idempotency check
  4. consume daily quota durable
  5. acquire tenant concurrency permit
  6. enqueue fair per-tenant queue
  7. worker acquire global warehouse permit
  8. run; release permit trong finally/lease expiry
  9. record actual usage/result
```

Nếu daily quota hết: `429`. Nếu warehouse overload nhưng request hợp lệ: `202` và
queue bounded nếu deadline sản phẩm cho phép. Nếu queue đầy: reject/defer rõ, không
nhận rồi để job chờ vô hạn.

---

## 29. Failure modes thường gặp

| Sự cố | Hậu quả | Phòng vệ |
|---|---|---|
| Local limit nhưng tưởng global | Scale pod làm tăng quota | Global/hybrid hoặc chia budget |
| Chỉ limit theo IP | NAT phạt oan, attacker xoay IP | Auth identity + risk signals |
| Fixed window không tính burst | Downstream bị spike 2× | Token/sliding + capacity headroom |
| Read rồi write counter | Race cho vượt limit | Atomic primitive/script |
| Dùng clock client | Refill sai | Store/monotonic clock |
| Multi-bucket consume không atomic | Mất token ảo | Same-slot atomic hoặc thiết kế hierarchy |
| Redis lỗi luôn fail-open | Downstream sập/chi phí tăng | Policy theo operation + local emergency |
| Redis lỗi luôn fail-closed | Limiter thành outage | Degraded mode |
| Key không TTL/cardinality vô hạn | Memory bùng nổ | Normalized key + TTL + estimate |
| Retry không jitter | Thundering herd đúng lúc reset | Retry-After + backoff+jitter |
| Chỉ limit request count | Query/export đắt bypass | Weighted cost + concurrency |
| Queue không fairness | Noisy neighbor | Per-tenant fair scheduling |
| Limiter global không tự được bảo vệ | Attack hạ limiter | Edge/local pre-limit + capacity |

---

## 30. Decision checklist

- [ ] Mục tiêu là fairness, entitlement, abuse hay overload được viết rõ.
- [ ] Identity/key derive từ nguồn tin cậy và được normalize.
- [ ] Đơn vị là request/byte/token/cost phù hợp workload.
- [ ] Sustainable rate và burst capacity bám downstream headroom.
- [ ] Đã chọn fixed/sliding/token/GCRA theo độ chính xác cần thiết.
- [ ] Workload chậm có concurrency limit.
- [ ] Local/global/hybrid semantics được ghi rõ khi autoscale.
- [ ] Read–decide–write atomic; clock authoritative.
- [ ] Hierarchical bucket không double-spend/mất token ngoài ý muốn.
- [ ] Key có TTL, policy version và cardinality estimate.
- [ ] `429`/`503`/`202`, `Retry-After` và client retry contract rõ.
- [ ] Fail-open/closed/degraded được quyết định theo operation.
- [ ] Queue có bound, age SLO và fairness.
- [ ] Policy rollout có shadow mode, version và rollback.
- [ ] Limiter backend có SLO/capacity/observability riêng.

---

## 31. Câu hỏi phỏng vấn thường gặp

1. Rate limit, quota và concurrency limit khác nhau thế nào?
2. Fixed window có boundary burst ra sao?
3. Token bucket quyết định burst và sustainable rate thế nào?
4. Leaky bucket khác token bucket ở đâu?
5. Vì sao local limit thay đổi khi autoscale?
6. Làm atomic token consumption trong distributed system thế nào?
7. Clock skew ảnh hưởng limiter ra sao?
8. Hierarchical limit có vấn đề double-consumption gì?
9. Khi Redis lỗi nên fail-open hay fail-closed?
10. Vì sao `429` khác `503`?
11. Làm sao giới hạn GraphQL/export theo cost thay vì request count?
12. Rate-limit ingress có đủ chống noisy neighbor trong queue không?

---

## 32. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [RFC 6585 – 429 Too Many Requests](https://www.rfc-editor.org/rfc/rfc6585.html)
- [RFC 9110 – Retry-After](https://www.rfc-editor.org/rfc/rfc9110.html#name-retry-after)
- [Redis – Rate limiter](https://redis.io/docs/latest/develop/use-cases/rate-limiter/)
- [Redis – INCR rate limiter pattern](https://redis.io/docs/latest/commands/incr/)
- [Envoy – Global rate limiting](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/other_features/global_rate_limiting)

Đọc tiếp:

- [Multi-tenancy](multi_tenancy.md) – tenant identity, noisy neighbor và tier.
- [Billing & Metering](billing_metering.md) – quota chu kỳ và usage ledger.
- [API Design](../advanced/api_design.md) – HTTP error/idempotency contract.
- [Availability & Reliability](../fundamentals/availability_reliability.md) –
  load shedding, retry và circuit breaker.
- [Redis roadmap](../../redis/roadmap.md) – atomic script, cluster và persistence.

---

*Cập nhật lần cuối: 2026-07-31*
