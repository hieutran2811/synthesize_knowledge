# Rate Limiting – Giới hạn tốc độ trong SaaS

## What – Rate Limiting là gì?

**Rate Limiting** là cơ chế kiểm soát số lượng requests mà một client/tenant có thể thực hiện trong một khoảng thời gian nhất định. Bảo vệ hệ thống khỏi abuse, DDoS, và đảm bảo fair usage.

```
Without Rate Limiting:
Client A: 10,000 req/s → chokes server
Client B, C, D: starved → poor experience

With Rate Limiting:
Client A: 1,000 req/s → limited, 429 Too Many Requests
Client B, C, D: 1,000 req/s each → fair sharing
```

---

## Rate Limiting Algorithms

### 1. Fixed Window Counter

Chia thời gian thành các window cố định. Đếm requests trong mỗi window.

```
Window: 1 minute

00:00 - 01:00 | counter=0
01:00 - 02:00 | counter=0

User sends 100 req in 00:30 → counter=100 (limit hit)
User sends 100 req in 00:59 → blocked

00:59 → counter reset to 0
01:00 → User sends 100 req again → ALLOWED

Problem: Boundary attack!
00:59 → 100 requests (window 1 end)
01:00 → 100 requests (window 2 start)
→ 200 requests in 2 seconds! (limit = 100/min)
```

**Ưu:** Đơn giản, ít memory
**Nhược:** Boundary problem (2x requests at window edge)

### 2. Sliding Window Log

Lưu timestamp của mỗi request, check count trong sliding window.

```
Requests logged:
[09:00:01, 09:00:30, 09:00:45, 09:01:15, 09:01:30]

At 09:01:35, check 1-minute window: [09:00:35 - 09:01:35]
→ requests in window: [09:01:15, 09:01:30] = 2 requests
→ count < limit → allow
```

**Ưu:** Chính xác nhất, không có boundary problem
**Nhược:** Tốn memory (lưu tất cả timestamps)

### 3. Sliding Window Counter (Hybrid - Best Practice)

Chia window thành sub-windows, tính weighted count.

```
Current time: 01:30 (30% vào window hiện tại)
Previous window (00-01): 80 requests
Current window (01-02): 30 requests (30% elapsed)

Estimated count = prev_window × (1 - elapsed%) + current
               = 80 × 0.70 + 30
               = 56 + 30 = 86 requests

If limit = 100 → 86 < 100 → Allow
```

**Ưu:** Ít memory hơn Sliding Log, gần chính xác
**Nhược:** Chỉ là xấp xỉ (acceptable cho hầu hết use cases)

### 4. Token Bucket (Brust-friendly)

Bucket chứa tokens. Mỗi request consume 1 token. Tokens được refill theo rate.

```
Capacity: 100 tokens
Refill rate: 10 tokens/second

t=0:   bucket=100 (full)
t=0:   100 requests → bucket=0 (all consumed)
t=1:   10 tokens refilled → bucket=10
t=2:   20 requests → bucket=0 (10 allowed, 10 rejected)
t=10:  bucket=100 (full again)
```

**Ưu:** Cho phép burst (consume accumulated tokens); dễ implement
**Nhược:** Client có thể burst ngay đầu period

```java
// Google Guava RateLimiter (token bucket)
RateLimiter limiter = RateLimiter.create(10.0); // 10 permits per second

// Bursty: up to 100 permits at once, refill 10/sec
RateLimiter burstyLimiter = RateLimiter.create(10, 100, TimeUnit.SECONDS);

// Usage
if (limiter.tryAcquire()) {
    processRequest();
} else {
    return ResponseEntity.status(429).body("Rate limit exceeded");
}
```

### 5. Leaky Bucket (Smooth output)

Requests vào queue (bucket), process ở rate cố định. Overflow bị reject.

```
Incoming: bursty (100 req/s spike)
Bucket: queue capacity = 50
Output: 10 req/s (constant)

Spike 100: 50 vào queue, 50 rejected
Processing: 10/s from queue (smoothed output)
```

**Ưu:** Output rate ổn định, không spike xuống DB
**Nhược:** Không cho phép burst; queue delay
**Dùng cho:** Network traffic shaping, API gateway smoothing

---

## Redis Implementation

### Sliding Window Counter với Redis + Lua

```lua
-- rate_limit.lua
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])  -- seconds
local now = tonumber(ARGV[3])

-- Increment current window counter
local current = redis.call('INCR', key)
if current == 1 then
    redis.call('EXPIRE', key, window)
end

-- Return: current count, allowed?
if current > limit then
    return {current, 0}  -- 0 = denied
else
    return {current, 1}  -- 1 = allowed
end
```

```java
@Service
public class RateLimiterService {
    
    private final RedisTemplate<String, Long> redis;
    private final DefaultRedisScript<List> rateLimitScript;
    
    public RateLimitResult checkLimit(String tenantId, String endpoint, 
                                      int limit, int windowSeconds) {
        String key = String.format("rate:%s:%s:%d", 
            tenantId, endpoint, Instant.now().getEpochSecond() / windowSeconds);
        
        List result = redis.execute(rateLimitScript,
            List.of(key),
            String.valueOf(limit),
            String.valueOf(windowSeconds),
            String.valueOf(Instant.now().getEpochSecond())
        );
        
        long count = ((Number) result.get(0)).longValue();
        boolean allowed = ((Number) result.get(1)).longValue() == 1;
        
        return new RateLimitResult(allowed, count, limit, 
            calculateRetryAfter(count, limit, windowSeconds));
    }
}
```

### Token Bucket với Redis

```lua
-- token_bucket.lua
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])  -- tokens per second
local now = tonumber(ARGV[3])
local requested = tonumber(ARGV[4])

local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1]) or capacity
local last_refill = tonumber(bucket[2]) or now

-- Calculate tokens to add since last check
local elapsed = now - last_refill
local new_tokens = math.min(capacity, tokens + elapsed * refill_rate)

if new_tokens >= requested then
    -- Allow: consume tokens
    redis.call('HMSET', key, 'tokens', new_tokens - requested, 'last_refill', now)
    redis.call('EXPIRE', key, math.ceil(capacity / refill_rate) * 2)
    return {1, math.floor(new_tokens - requested)}  -- allowed, remaining
else
    -- Deny
    redis.call('HMSET', key, 'tokens', new_tokens, 'last_refill', now)
    return {0, math.floor(new_tokens)}  -- denied, remaining
end
```

---

## Multi-Level Rate Limiting (SaaS)

SaaS cần nhiều tầng limit:

```
Level 1: IP-based (DDoS protection)
  - 1000 req/min per IP (before auth)
  
Level 2: API Key / Token (authentication)
  - 100 req/min per API key (dev/test keys)
  
Level 3: Tenant-level (fair usage)
  - Free: 1,000 req/hour
  - Pro: 10,000 req/hour
  - Enterprise: Unlimited (or custom)
  
Level 4: Endpoint-specific (protect expensive operations)
  - POST /orders: 100/min (write operations)
  - GET /reports: 10/min (expensive queries)
  
Level 5: User-level (within tenant)
  - Per-user limit within tenant quota
```

```java
@Component
public class MultiLevelRateLimiter {
    
    public void checkAll(HttpServletRequest request, String tenantId, String userId) {
        String ip = getClientIP(request);
        String endpoint = request.getRequestURI();
        
        // Level 1: IP (lightweight check first)
        checkLimit("ip:" + ip, 1000, 60, "IP rate limit exceeded");
        
        // Level 2: Tenant
        TenantPlan plan = planService.getPlan(tenantId);
        checkLimit("tenant:" + tenantId, plan.getHourlyLimit(), 3600, 
            "Tenant rate limit exceeded. Upgrade your plan.");
        
        // Level 3: Endpoint-specific
        EndpointLimit endpointLimit = endpointLimitConfig.get(endpoint);
        if (endpointLimit != null) {
            checkLimit("endpoint:" + tenantId + ":" + endpoint,
                endpointLimit.getLimit(), endpointLimit.getWindow(),
                "Endpoint rate limit exceeded");
        }
    }
    
    private void checkLimit(String key, int limit, int window, String message) {
        RateLimitResult result = rateLimiterService.checkLimit(key, limit, window);
        if (!result.isAllowed()) {
            throw new RateLimitExceededException(message, result.getRetryAfterSeconds());
        }
    }
}
```

---

## Rate Limit Headers (Best Practice)

```java
@RestControllerAdvice
public class RateLimitExceptionHandler {
    
    @ExceptionHandler(RateLimitExceededException.class)
    public ResponseEntity<ErrorResponse> handleRateLimit(RateLimitExceededException ex) {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
            .header("X-RateLimit-Limit", String.valueOf(ex.getLimit()))
            .header("X-RateLimit-Remaining", "0")
            .header("X-RateLimit-Reset", String.valueOf(ex.getResetEpochSeconds()))
            .header("Retry-After", String.valueOf(ex.getRetryAfterSeconds()))
            .body(new ErrorResponse("RATE_LIMIT_EXCEEDED", ex.getMessage()));
    }
}

// Every successful response cũng nên trả về
@Component
public class RateLimitResponseFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(...) throws ... {
        chain.doFilter(request, response);
        
        RateLimitResult result = RateLimitContext.getResult();
        if (result != null) {
            response.setHeader("X-RateLimit-Limit", String.valueOf(result.getLimit()));
            response.setHeader("X-RateLimit-Remaining", String.valueOf(result.getRemaining()));
            response.setHeader("X-RateLimit-Reset", String.valueOf(result.getResetTime()));
        }
    }
}
```

---

## Rate Limiting at API Gateway

Không cần implement ở mỗi service – thực hiện ở Gateway.

**Kong Rate Limiting Plugin:**
```yaml
plugins:
- name: rate-limiting
  config:
    minute: 1000           # Per minute
    hour: 10000            # Per hour
    policy: redis          # Use Redis for distributed state
    redis_host: redis
    hide_client_headers: false
    limit_by: consumer     # or ip, credential, header
```

**Spring Cloud Gateway:**
```yaml
spring:
  cloud:
    gateway:
      routes:
      - id: order-service
        uri: lb://order-service
        filters:
        - name: RequestRateLimiter
          args:
            redis-rate-limiter.replenishRate: 100   # tokens per second
            redis-rate-limiter.burstCapacity: 200   # max burst
            key-resolver: "#{@tenantKeyResolver}"   # custom key
```

```java
@Bean
public KeyResolver tenantKeyResolver() {
    return exchange -> {
        String tenantId = exchange.getRequest().getHeaders()
            .getFirst("X-Tenant-ID");
        return Mono.just(tenantId != null ? tenantId : "anonymous");
    };
}
```

---

## Throttling vs Rate Limiting

| | Rate Limiting | Throttling |
|--|--------------|------------|
| **Response** | 429 immediately | Slow down (queue/delay) |
| **User experience** | Hard block | Degraded but working |
| **Use case** | API protection | Bandwidth control |

**Throttling example:**
```java
// Delay response instead of rejecting
public CompletableFuture<Response> handleWithThrottle(Request req) {
    double waitSeconds = rateLimiter.acquire(); // blocks if rate exceeded
    
    if (waitSeconds > MAX_ACCEPTABLE_WAIT) {
        return CompletableFuture.failedFuture(
            new RateLimitExceededException("Queue full")
        );
    }
    
    return CompletableFuture.supplyAsync(() -> processRequest(req));
}
```

---

## Trade-offs

| Algorithm | Accuracy | Memory | Burst | Complexity |
|-----------|----------|--------|-------|------------|
| Fixed Window | Low (boundary) | Low | Allowed | Very low |
| Sliding Window Log | Highest | High | No | Medium |
| Sliding Window Counter | High | Low | Partial | Medium |
| Token Bucket | Good | Low | Yes ✅ | Medium |
| Leaky Bucket | Good | Low | No (smooth) | Medium |

---

## Real-world Production

### GitHub API
```
Rate limit: 5,000 req/hour (authenticated)
           60 req/hour (unauthenticated)
Headers: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
Secondary limits: 100 concurrent requests, 900 req/min to content APIs
```

### Stripe API
```
Live mode: 100 read, 100 write per second
Test mode: 25 operations per second
Idempotency retry: safe (same result)
```

### Twitter/X API
```
Per endpoint limits:
  Search: 450 req/15min
  Timeline: 1500 req/15min
  Post tweet: 300/3h (free tier)
```

---

## Ghi chú

**Sub-topic tiếp theo:**
- `feature_flags.md` – Feature gates per plan tier, A/B testing
- `observability_saas.md` – Monitoring rate limit metrics per tenant
- **Keywords:** Throttling, Quota management, Burst allowance, Rate limit bypass (API keys with higher limits), Distributed rate limiting, Redis Cluster rate limiting, GCRA (Generic Cell Rate Algorithm), Adaptive rate limiting, DDoS protection vs rate limiting, Backpressure, Semaphore-based limiting, Bulkhead pattern
