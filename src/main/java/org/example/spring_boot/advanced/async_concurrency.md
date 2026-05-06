# Async & Concurrency – Lập trình bất đồng bộ trong Spring Boot

## What – Async Processing là gì?

**Asynchronous processing** cho phép tasks chạy trên thread riêng, không block thread hiện tại. Spring Boot hỗ trợ qua `@Async`, `CompletableFuture`, và Java 21 **Virtual Threads**.

---

## @Async – Async Method Execution

### Setup

```java
@SpringBootApplication
@EnableAsync  // Bắt buộc
public class App {}
```

### Cơ bản

```java
@Service
public class EmailService {

    // Void async: fire-and-forget
    @Async
    public void sendWelcomeEmail(String email) {
        // Chạy trên thread pool riêng, không block caller
        emailProvider.send(email, "Welcome!", buildWelcomeTemplate());
    }

    // Return Future: có thể get result sau
    @Async
    public CompletableFuture<Boolean> sendAndTrack(String email, String content) {
        try {
            emailProvider.send(email, content);
            return CompletableFuture.completedFuture(true);
        } catch (Exception e) {
            return CompletableFuture.failedFuture(e);
        }
    }
}

// Caller
@Service
public class UserService {

    public void createUser(CreateUserRequest req) {
        User user = userRepo.save(User.from(req));
        emailService.sendWelcomeEmail(user.getEmail()); // không block
        log.info("User created: {}", user.getId());     // return ngay
    }
}
```

### Custom Thread Pool (Quan trọng!)

```java
// Mặc định @Async dùng SimpleAsyncTaskExecutor – tạo thread mới mỗi lần!
// → Phải configure thread pool production-grade

@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {

    @Override
    public Executor getAsyncExecutor() {
        return taskExecutor();
    }

    @Bean(name = "taskExecutor")
    public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);           // thread luôn sẵn
        executor.setMaxPoolSize(50);            // max threads
        executor.setQueueCapacity(1000);        // queue khi max pool đạt
        executor.setKeepAliveSeconds(60);       // idle thread timeout
        executor.setThreadNamePrefix("async-");
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }

    // Separate executor for heavy operations
    @Bean(name = "reportExecutor")
    public ThreadPoolTaskExecutor reportExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(5);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("report-");
        executor.initialize();
        return executor;
    }

    @Override
    public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
        return (ex, method, params) -> {
            log.error("Async exception in {}: {}", method.getName(), ex.getMessage(), ex);
            // Alert, DLQ, retry queue...
        };
    }
}

// Chỉ định executor cụ thể
@Async("reportExecutor")
public CompletableFuture<Report> generateLargeReport(ReportRequest req) { ... }
```

### @Async Caveats

```java
// ❌ Self-invocation: KHÔNG hoạt động (AOP proxy bypass)
@Service
public class OrderService {
    @Async
    public void asyncMethod() { ... }

    public void regularMethod() {
        asyncMethod(); // Gọi trực tiếp → không async! (self-invocation)
    }
}

// ✅ Fix: inject self hoặc tách class
@Service
public class OrderService {
    @Autowired
    @Lazy
    private OrderService self; // inject proxy của chính mình

    public void regularMethod() {
        self.asyncMethod(); // gọi qua proxy → async hoạt động
    }
}
```

---

## CompletableFuture – Non-blocking Composition

```java
@Service
@RequiredArgsConstructor
public class DashboardService {

    private final UserService userService;
    private final OrderService orderService;
    private final InventoryService inventoryService;

    // Parallel async calls
    public DashboardData getDashboard(Long tenantId) throws Exception {
        CompletableFuture<List<User>> usersFuture =
            CompletableFuture.supplyAsync(() -> userService.findByTenant(tenantId), taskExecutor);

        CompletableFuture<List<Order>> ordersFuture =
            CompletableFuture.supplyAsync(() -> orderService.findByTenant(tenantId), taskExecutor);

        CompletableFuture<InventoryStats> inventoryFuture =
            CompletableFuture.supplyAsync(() -> inventoryService.getStats(tenantId), taskExecutor);

        // Đợi tất cả hoàn thành (parallel, không sequential)
        CompletableFuture.allOf(usersFuture, ordersFuture, inventoryFuture).join();

        return new DashboardData(
            usersFuture.get(),
            ordersFuture.get(),
            inventoryFuture.get()
        );
    }

    // Chain: result của step 1 là input của step 2
    public CompletableFuture<EnrichedOrder> processOrder(CreateOrderRequest req) {
        return CompletableFuture
            .supplyAsync(() -> orderService.create(req))          // Step 1: create order
            .thenApplyAsync(order -> enrichmentService.enrich(order))  // Step 2: enrich (async)
            .thenComposeAsync(order -> paymentService.chargeAsync(order)) // Step 3: charge (returns CF)
            .thenApply(payment -> new EnrichedOrder(payment))     // Step 4: map result
            .exceptionally(ex -> {                                 // Error handling
                log.error("Order processing failed", ex);
                throw new OrderProcessingException(ex);
            });
    }

    // Timeout
    public CompletableFuture<Product> getProductWithTimeout(Long id) {
        return CompletableFuture
            .supplyAsync(() -> productService.find(id))
            .orTimeout(5, TimeUnit.SECONDS)
            .exceptionally(ex -> {
                if (ex instanceof TimeoutException) {
                    return productService.getCachedFallback(id);
                }
                throw (RuntimeException) ex;
            });
    }

    // anyOf: lấy kết quả nhanh nhất
    public CompletableFuture<String> getFromFastestSource(String key) {
        CompletableFuture<String> fromCache = cacheService.getAsync(key);
        CompletableFuture<String> fromDb = dbService.getAsync(key);

        return CompletableFuture.anyOf(fromCache, fromDb)
            .thenApply(result -> (String) result);
    }
}
```

---

## Virtual Threads (Java 21 + Spring Boot 3.2)

Virtual threads là **lightweight threads** của JVM (Project Loom), cho phép dùng thread-per-request model với chi phí cực thấp.

### Tại sao Virtual Threads quan trọng?

```
Platform Thread (OS thread):
- ~1MB stack memory per thread
- OS context switch overhead
- Thực tế: limit ~1000-2000 concurrent threads

Virtual Thread:
- ~few KB memory per thread
- JVM manages scheduling (no OS context switch)
- Có thể có HÀNG TRIỆU virtual threads concurrent
```

### Enable Virtual Threads trong Spring Boot 3.2+

```yaml
spring:
  threads:
    virtual:
      enabled: true  # Tomcat, Netty, @Async, Kafka listeners dùng virtual threads
```

```java
// Hoặc explicit config
@Bean
public TomcatProtocolHandlerCustomizer<?> protocolHandlerVirtualThreadExecutorCustomizer() {
    return protocolHandler -> {
        protocolHandler.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
    };
}

// @Async với virtual threads
@Bean(name = "virtualThreadExecutor")
public Executor virtualThreadExecutor() {
    return Executors.newVirtualThreadPerTaskExecutor();
}

@Async("virtualThreadExecutor")
public CompletableFuture<Report> generateReport(ReportRequest req) { ... }
```

### Virtual Threads vs Reactive (WebFlux)

```
Virtual Threads + Spring MVC (blocking I/O):
  Request → Virtual Thread → DB query (blocks VT, not OS thread) → Response

WebFlux + Reactor (non-blocking I/O):
  Request → Event Loop → callback on DB response → Response

Virtual Thread: dễ code (blocking style), JVM mount/unmount tự động
WebFlux: phức tạp hơn (Mono/Flux), ít memory per connection
```

| | Virtual Threads | WebFlux |
|--|-----------------|---------|
| Code style | Blocking (đơn giản) | Reactive (phức tạp) |
| Throughput | High | Very High |
| Latency | Low | Low |
| CPU bound | ❌ No benefit | ❌ No benefit |
| I/O bound | ✅ Excellent | ✅ Excellent |
| JPA/JDBC | ✅ Works fine | ❌ Needs R2DBC |
| Pinning risk | Yes (synchronized) | N/A |

### Virtual Thread Pinning (Cẩn thận!)

**Pinning** xảy ra khi virtual thread bị gắn vào platform thread (không unmount được):

```java
// ❌ Pinning: synchronized block blocks underlying platform thread
synchronized(lock) {
    Thread.sleep(1000); // virtual thread bị pinned → kéo theo OS thread
}

// ✅ Dùng ReentrantLock thay synchronized
ReentrantLock lock = new ReentrantLock();
lock.lock();
try {
    Thread.sleep(1000); // virtual thread unmount khi sleep
} finally {
    lock.unlock();
}
```

**Check pinning:**
```bash
# JVM flag để detect pinning
java -Djdk.tracePinnedThreads=full -jar app.jar
```

---

## SecurityContext với @Async

```java
// @Async chạy trên thread khác → SecurityContext bị mất
// Cần propagate explicitly

@Configuration
public class SecurityContextAsyncConfig {

    @Bean
    public SecurityContextRepository securityContextRepository() {
        return new HttpSessionSecurityContextRepository();
    }

    // Task decorator để copy SecurityContext sang async thread
    @Bean(name = "securityAwareExecutor")
    public ThreadPoolTaskExecutor securityAwareExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        executor.setTaskDecorator(runnable -> {
            // Capture security context ở calling thread
            SecurityContext context = SecurityContextHolder.getContext();
            return () -> {
                try {
                    SecurityContextHolder.setContext(context); // set ở async thread
                    runnable.run();
                } finally {
                    SecurityContextHolder.clearContext();
                }
            };
        });
        executor.initialize();
        return executor;
    }
}
```

---

## Transaction với @Async

```java
// @Transactional + @Async: transaction KHÔNG propagate sang async thread

@Transactional
public void createOrderWithAsyncNotification(CreateOrderRequest req) {
    Order order = orderRepo.save(Order.from(req));
    notificationService.sendAsync(order); // chạy sau transaction commit
}

// ❌ Sai: async method trong transaction – async thread không share transaction
@Async
@Transactional
public void processAsync() { ... } // transaction bắt đầu trên async thread riêng

// ✅ Đúng: dùng @TransactionalEventListener để đảm bảo send sau commit
@Service
public class OrderService {
    @Transactional
    public Order createOrder(CreateOrderRequest req) {
        Order order = orderRepo.save(Order.from(req));
        eventPublisher.publishEvent(new OrderCreatedEvent(order));
        return order;
    }
}

@Component
public class OrderEventListener {
    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderCreated(OrderCreatedEvent event) {
        // Chạy sau khi transaction commit thành công → order đã trong DB
        notificationService.sendConfirmation(event.getOrder());
    }
}
```

---

## Ghi chú

**Sub-topic tiếp theo:**
- `production/performance_tuning.md` – Thread pool sizing, JVM tuning, Virtual Thread config
- `production/observability.md` – @Async metrics, thread pool monitoring
- **Keywords:** CompletableFuture.thenCompose vs thenApply, ForkJoinPool, Structured concurrency (Java 21), StructuredTaskScope, ScopedValue (alternative to ThreadLocal), Virtual Thread pinning detection, @EnableAsync proxyTargetClass, Callable vs Runnable vs Supplier, ListenableFuture (deprecated → CompletableFuture), @Async với Reactor Scheduler
