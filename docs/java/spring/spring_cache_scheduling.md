---
title: "Spring Cache, Scheduling & Async (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Spring Cache, Scheduling & Async (Deep Dive)

> Thuật ngữ: [Glossary](../glossary.md).

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Ba tính năng "cross-cutting" của Spring

`@Cacheable`, `@Scheduled`, `@Async` đều là các tính năng **khai báo bằng annotation**, hiện thực qua **AOP proxy** (xem cơ chế proxy + JDK/CGLIB ở [[spring/spring_aop.md]]). Hiểu chung một cơ chế → tránh cùng một loại bug (đặc biệt **self-invocation**).

| Annotation | Giải quyết | Cơ chế |
|-----------|-----------|--------|
| `@Cacheable` | Tránh tính lại/đọc lại tốn kém | Proxy chặn method, tra cache trước |
| `@Scheduled` | Chạy tác vụ định kỳ | Scheduler gọi method theo lịch |
| `@Async` | Chạy method ở thread khác (non-blocking caller) | Proxy submit vào TaskExecutor |

---

## Phần 1 – Spring Cache Abstraction

## How – Bật & dùng

```java
@Configuration
@EnableCaching                 // bật proxy cache
class CacheConfig {}

@Service
class ProductService {
    @Cacheable(value = "products", key = "#id")
    public Product findById(Long id) {        // chạy DB chỉ lần đầu; lần sau lấy từ cache
        return repo.findById(id).orElseThrow();
    }

    @CachePut(value = "products", key = "#p.id")  // LUÔN chạy method + cập nhật cache
    public Product update(Product p) { return repo.save(p); }

    @CacheEvict(value = "products", key = "#id")  // xóa entry khi xóa/cập nhật
    public void delete(Long id) { repo.deleteById(id); }

    @CacheEvict(value = "products", allEntries = true) // xóa toàn bộ cache
    public void reload() {}
}
```

| Annotation | Hành vi |
|-----------|---------|
| `@Cacheable` | Có trong cache → trả luôn (không chạy method); không có → chạy + lưu |
| `@CachePut` | **Luôn** chạy method, rồi cập nhật cache (dùng cho update) |
| `@CacheEvict` | Xóa entry (hoặc `allEntries`) — đồng bộ cache với dữ liệu |
| `@Caching` | Gộp nhiều thao tác cache trên 1 method |
| `@CacheConfig` | Cấu hình chung cấp class (tên cache mặc định) |

## How – Key & điều kiện (SpEL)

```java
@Cacheable(value = "users",
    key = "#root.methodName + '-' + #email",   // SpEL custom key
    condition = "#email != null",               // chỉ cache khi điều kiện đúng (trước khi chạy)
    unless = "#result == null",                 // KHÔNG cache nếu (sau khi chạy)
    sync = true)                                // chống cache stampede (1 thread tính, còn lại chờ)
public User findByEmail(String email) { ... }
```
> Mặc định key sinh bởi `SimpleKeyGenerator` (gộp tất cả tham số). Object làm key phải có `equals`/`hashCode` đúng (xem [[core/object_methods.md]]).

## Components – CacheManager & nhà cung cấp

`Cache`/`CacheManager` là **trừu tượng** — Spring không tự cache, mà ủy quyền cho provider:

| Provider | Loại | Khi dùng |
|----------|------|----------|
| `ConcurrentMapCacheManager` | HashMap in-memory | **Chỉ dev/test** (không evict, không TTL) |
| **Caffeine** | In-memory cao cấp | 1 instance, cache nóng (maximumSize, TTL, eviction W-TinyLFU) |
| **Redis** | Phân tán | Nhiều instance dùng chung cache (xem [[redis/redis_fundamentals.md]] nếu có) |
| Ehcache/Hazelcast | In-memory/distributed | Tùy nhu cầu |

```java
// Caffeine
@Bean CacheManager caffeine() {
    var cm = new CaffeineCacheManager("products");
    cm.setCaffeine(Caffeine.newBuilder()
        .maximumSize(10_000)
        .expireAfterWrite(Duration.ofMinutes(10)));
    return cm;
}

// Redis – TTL riêng từng cache + serialization
@Bean CacheManager redis(RedisConnectionFactory cf) {
    var config = RedisCacheConfiguration.defaultCacheConfig()
        .entryTtl(Duration.ofMinutes(30))
        .serializeValuesWith(SerializationPair.fromSerializer(new GenericJackson2JsonRedisSerializer()));
    return RedisCacheManager.builder(cf).cacheDefaults(config).build();
}
```
> ⚠️ Redis cache lưu value đã serialize → **dùng JSON serializer** (Jackson), KHÔNG dùng JDK serialization (rủi ro RCE + version brittle, xem [[core/serialization.md]], [[core/json_jackson.md]]).

## ⚠️ Pitfalls Cache

- **Self-invocation**: gọi `this.findById()` trong cùng class → **bỏ qua proxy → cache KHÔNG hoạt động** (giống `@Transactional`). Phải gọi qua bean khác hoặc self-inject. Xem [[spring/spring_aop.md]].
- **Cache null/exception**: mặc định không cache null nếu dùng `unless="#result==null"`. Method ném exception → không cache (đúng).
- **Cache stampede** (nhiều request cùng miss 1 key, cùng tính): dùng `sync=true` (in-memory) hoặc lock phân tán (Redis).
- **Stale data**: cache + update không đồng bộ → dùng `@CachePut`/`@CacheEvict` đúng chỗ; đặt TTL hợp lý.
- **Key collision/quá rộng**: object key sai `equals/hashCode` → trả nhầm dữ liệu.

---

## Phần 2 – Scheduling

## How – `@Scheduled`

```java
@Configuration @EnableScheduling
class SchedulingConfig {}

@Component
class Jobs {
    @Scheduled(fixedRate = 5000)              // 5s/lần TÍNH TỪ LÚC BẮT ĐẦU lần trước
    void poll() {}

    @Scheduled(fixedDelay = 5000)             // 5s SAU KHI lần trước KẾT THÚC
    void process() {}

    @Scheduled(cron = "0 0 2 * * *", zone = "Asia/Ho_Chi_Minh")  // 2h sáng hằng ngày
    void nightlyReport() {}

    @Scheduled(initialDelay = 10000, fixedRate = 60000)  // hoãn 10s rồi mỗi 60s
    void delayedStart() {}
}
```

### fixedRate vs fixedDelay
```
fixedRate=5s:  |--run(3s)--|..2s..|--run(3s)--|   (đếm từ lúc bắt đầu; nếu run > rate → chạy ngay nối tiếp)
fixedDelay=5s: |--run(3s)--|....5s....|--run(3s)--|  (đếm từ lúc kết thúc)
```

### Cron 6 trường (Spring): `giây phút giờ ngày tháng thứ`
```
0 0 2 * * *      → 02:00 mỗi ngày
0 */15 * * * *   → mỗi 15 phút
0 0 9 * * MON-FRI→ 09:00 các ngày làm việc
```

## ⚠️ Pitfall: pool mặc định CHỈ 1 THREAD
Mặc định mọi `@Scheduled` chạy trên **1 thread duy nhất** → 1 job chậm/treo làm **kẹt toàn bộ** job khác.
```java
@Bean ThreadPoolTaskScheduler taskScheduler() {
    var s = new ThreadPoolTaskScheduler();
    s.setPoolSize(5);                          // tách job ra nhiều thread
    s.setThreadNamePrefix("sched-");
    return s;
}
```

## ⚠️ Pitfall lớn nhất: chạy nhiều instance → job chạy TRÙNG
Khi service scale N instance, **mỗi instance đều chạy** `@Scheduled` → job duplicate (gửi email 3 lần, tính lương 3 lần!).

**Giải pháp:**
- **ShedLock**: lock phân tán (DB/Redis) đảm bảo chỉ 1 instance chạy mỗi lần.
  ```java
  @Scheduled(cron = "0 0 2 * * *")
  @SchedulerLock(name = "nightlyReport", lockAtMostFor = "10m", lockAtLeastFor = "1m")
  void nightlyReport() {}
  ```
- **Quartz** cluster mode (lưu lịch vào DB, điều phối cluster).
- Tách scheduler ra service riêng chỉ chạy 1 replica.

---

## Phần 3 – Async (`@Async`)

## How – Bật & dùng

```java
@Configuration @EnableAsync
class AsyncConfig implements AsyncConfigurer {
    @Override public Executor getAsyncExecutor() {
        var ex = new ThreadPoolTaskExecutor();
        ex.setCorePoolSize(4);
        ex.setMaxPoolSize(16);
        ex.setQueueCapacity(100);
        ex.setThreadNamePrefix("async-");
        ex.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        ex.initialize();
        return ex;
    }
    // Xử lý exception cho @Async trả về void (không có Future để .get())
    @Override public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
        return (ex, method, params) -> log.error("Async error in {}", method, ex);
    }
}

@Service
class NotificationService {
    @Async
    public void sendEmail(String to) { /* chạy ở thread async, caller không chờ */ }

    @Async
    public CompletableFuture<Report> generate() {       // trả CompletableFuture để lấy kết quả/lỗi
        return CompletableFuture.completedFuture(buildReport());
    }
}
```

## ⚠️ Pitfalls Async

- **Self-invocation**: gọi `this.sendEmail()` nội bộ → chạy **đồng bộ** (bỏ proxy). Xem [[spring/spring_aop.md]].
- **Return type**: `void` → không bắt được exception (phải dùng `AsyncUncaughtExceptionHandler`); `Future`/`CompletableFuture` → lỗi nằm trong future.
- **Mất context**: `@Async` chạy thread mới → mất `SecurityContext`, `MDC` (log mất traceId), `RequestContext`, transaction. Phải truyền thủ công:
  ```java
  // Security: DelegatingSecurityContextAsyncTaskExecutor
  // MDC/log: copy MDC context map sang thread async (xem [[core/logging.md]])
  ```
- **Pool mặc định**: nếu không cấu hình executor, Spring Boot dùng `SimpleAsyncTaskExecutor` (tạo thread mới mỗi lần — **không pool**, nguy hiểm). Luôn định nghĩa executor.
- `@Async` + `@Transactional`: transaction **không** propagate sang thread async → mở transaction mới trong method async nếu cần.

## Virtual Threads (Spring Boot 3.2+, Java 21)
```yaml
spring.threads.virtual.enabled: true   # @Async, web request, scheduler dùng virtual thread
```
> Async I/O-bound trên virtual thread = nhẹ, scale cao, không cần tinh chỉnh pool size phức tạp. Liên hệ [[modern/virtual_threads.md]].

---

## Compare – @Async vs Message Queue vs Reactive

| | `@Async` | Message Queue (Kafka/RabbitMQ) | Reactive (WebFlux) |
|--|----------|-------------------------------|---------------------|
| Phạm vi | Trong 1 JVM | Liên service, bền vững | Trong 1 JVM, non-blocking |
| Mất việc khi crash | Có (in-memory) | Không (persistent) | Có |
| Khi dùng | Fire-and-forget nhẹ (gửi mail) | Tác vụ quan trọng, retry, decouple | Stream/backpressure, IO cao |

> Việc **quan trọng không được mất** → dùng message queue ([[core/messaging.md]]), không dùng `@Async`.

---

## Trade-offs

- (+) Khai báo gọn, tách mối quan tâm, không xâm lấn business logic.
- (−) Cơ chế proxy ⇒ **self-invocation không hoạt động** (cache/async/transaction) — bug kinh điển.
- (−) Cache: rủi ro stale data, cache stampede, serialization (Redis); Scheduling: trùng job khi scale; Async: mất context + nuốt exception.
- (−) "Ẩn" độ phức tạp → khó debug nếu không hiểu cơ chế bên dưới.

---

## Real-world Usage

```java
// Cache read-heavy + evict khi ghi (đồng bộ)
@Cacheable(value="catalog", key="#id", unless="#result == null")
public Product get(Long id) { ... }
@CacheEvict(value="catalog", key="#p.id")
public void save(Product p) { repo.save(p); }

// Scheduled job an toàn cho multi-instance
@Scheduled(cron="0 */10 * * * *")
@SchedulerLock(name="syncInventory", lockAtMostFor="5m")
public void syncInventory() { ... }

// Async fire-and-forget có xử lý lỗi
@Async public void auditLog(Event e) { auditRepo.save(e); } // lỗi → AsyncUncaughtExceptionHandler
```

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[spring/spring_aop.md]] (proxy, self-invocation, JDK/CGLIB), [[spring/spring_core.md]] (bean, `@EnableXxx`), [[core/object_methods.md]] (equals/hashCode cho cache key), [[core/serialization.md]] + [[core/json_jackson.md]] (serializer cho Redis cache), [[core/messaging.md]] (async bền vững), [[modern/virtual_threads.md]] (virtual thread cho async), [[core/logging.md]] (MDC trong async), [[redis/redis_fundamentals.md]] (Redis cache backend).
>
> Keyword cho topic kế: **Build tools** – Maven (lifecycle, dependency scope, BOM, multi-module), Gradle (DSL, configurations, build cache).

*Cập nhật lần cuối: 2026-06-04*
