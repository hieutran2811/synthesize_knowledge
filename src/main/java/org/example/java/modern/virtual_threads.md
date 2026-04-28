# Virtual Threads – Project Loom (Java 21)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Virtual Threads là gì?

**Virtual Threads** (Java 21, preview Java 19–20) là **lightweight threads** được JVM quản lý — không phải OS threads. Một JVM có thể chạy **hàng triệu** virtual threads đồng thời mà trước đây chỉ có thể làm được với Reactive Programming.

**Bài toán cốt lõi**: Traditional thread model không scale cho IO-bound applications.

```
Platform Thread (cũ):
  1 Java thread = 1 OS thread
  OS thread tốn: ~1MB stack memory + overhead scheduling
  → Server 8GB RAM ≈ ~8,000 threads tối đa
  → Thread pool cố định: blocking IO = waste CPU

Virtual Thread (mới):
  1 Virtual Thread ≠ 1 OS thread
  JVM quản lý scheduling, mount/unmount trên carrier thread
  → Hàng triệu virtual threads với ít OS threads
  → Blocking IO = unmount virtual thread, carrier thread free để làm việc khác
```

---

## How – Kiến trúc Virtual Thread

### Platform Thread vs Virtual Thread

```
Platform Thread:
  Java Thread → OS Thread → CPU Core
  (1-1 mapping, OS scheduler)

Virtual Thread:
  Virtual Thread → Carrier Thread → OS Thread → CPU Core
  (M-N mapping, JVM scheduler = ForkJoinPool)
```

### Cơ chế Mount/Unmount (Continuation)

```
Virtual Thread "Alice" đang chạy:
  1. Mounted on Carrier Thread #1
  2. Gọi InputStream.read() → blocking IO

Khi blocking IO bắt đầu:
  3. Virtual Thread "Alice" unmounted khỏi Carrier Thread #1
  4. Continuation (stack state) lưu vào Heap (không phải OS thread stack!)
  5. Carrier Thread #1 free → mount Virtual Thread "Bob"

Khi IO hoàn thành:
  6. Virtual Thread "Alice" remount lên bất kỳ carrier thread nào free
  7. Tiếp tục từ điểm dừng (seamless cho code)
```

**Từ góc nhìn lập trình viên**: hoàn toàn transparent — code blocking thông thường, JVM tự xử lý mounting.

---

## How – Tạo Virtual Thread

### Cách 1: Thread.ofVirtual()
```java
// Tạo và start
Thread vt = Thread.ofVirtual()
    .name("my-virtual-thread")
    .start(() -> System.out.println("Hello from virtual thread: "
        + Thread.currentThread().isVirtual())); // true

// Chờ kết thúc
vt.join();

// Factory
Thread.Builder.OfVirtual factory = Thread.ofVirtual().name("worker-", 0);
Thread t1 = factory.start(task1); // worker-0
Thread t2 = factory.start(task2); // worker-1
```

### Cách 2: Executors.newVirtualThreadPerTaskExecutor() (Recommended)
```java
// Mỗi task chạy trên 1 virtual thread mới (tạo mới rất rẻ)
try (ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor()) {
    List<Future<String>> futures = new ArrayList<>();
    for (int i = 0; i < 10_000; i++) {
        futures.add(executor.submit(() -> fetchFromDatabase(id)));
    }
    // 10,000 virtual threads đồng thời – OK!
    for (Future<String> f : futures) {
        System.out.println(f.get());
    }
} // executor.close() = awaitTermination
```

### Cách 3: Trong Spring Boot (Automatic từ Spring 6.1 / Boot 3.2)
```java
// application.properties
spring.threads.virtual.enabled=true
// Tomcat tự dùng virtual thread per request

// Hoặc config manual:
@Bean
public TomcatProtocolHandlerCustomizer<?> protocolHandlerVirtualThreadExecutorCustomizer() {
    return protocolHandler ->
        protocolHandler.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
}
```

---

## How – Blocking là OK với Virtual Threads

```java
// Code này HOÀN TOÀN OK với virtual threads – không block platform thread
try (ExecutorService exec = Executors.newVirtualThreadPerTaskExecutor()) {
    IntStream.range(0, 100_000).forEach(i ->
        exec.submit(() -> {
            // Tất cả calls blocking IO bên dưới đều được JVM handle
            String data = jdbcTemplate.queryForObject(sql, String.class);  // DB query
            String result = restTemplate.getForObject(url, String.class);   // HTTP call
            Thread.sleep(Duration.ofMillis(100));                            // Sleep
            Files.readString(Path.of("file.txt"));                          // File IO
            return data + result;
        })
    );
}
// 100,000 concurrent tasks với code đơn giản, blocking – JVM handle hiệu quả
```

---

## How – Structured Concurrency (Java 21 Preview)

**Structured Concurrency**: đảm bảo lifetime của subtask không vượt quá task cha → dễ quản lý, cancel, propagate error.

```java
// StructuredTaskScope: tất cả subtask phải hoàn thành trước khi scope đóng
try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
    // Fork 3 concurrent tasks
    Subtask<User>    userTask    = scope.fork(() -> userService.findById(userId));
    Subtask<List<Order>> ordersTask = scope.fork(() -> orderService.findByUser(userId));
    Subtask<Wallet>  walletTask  = scope.fork(() -> walletService.findByUser(userId));

    scope.join()            // chờ tất cả hoàn thành
         .throwIfFailed();  // nếu bất kỳ task nào fail → throw exception

    // Lấy kết quả
    return new Dashboard(
        userTask.get(),    // guaranteed complete at this point
        ordersTask.get(),
        walletTask.get()
    );
} // scope.close() = cancel mọi task chưa xong (resource cleanup)
```

### ShutdownOnSuccess – Lấy kết quả đầu tiên
```java
// Gọi 2 service song song, lấy cái nào trả về trước
try (var scope = new StructuredTaskScope.ShutdownOnSuccess<String>()) {
    scope.fork(() -> primaryService.fetchData(id));    // nhanh hơn
    scope.fork(() -> fallbackService.fetchData(id));   // backup

    scope.join();
    return scope.result(); // kết quả của task đầu tiên hoàn thành
}
// Task còn lại tự động bị cancel!
```

---

## How – Pinning: Vấn đề cần biết

**Pinned virtual thread** = virtual thread bị "ghim" vào carrier thread, không thể unmount khi blocking — làm mất lợi thế.

**2 nguyên nhân pinning:**
```java
// 1. synchronized block/method (PINNING!)
synchronized void badMethod() {
    Thread.sleep(1000); // virtual thread bị pin, carrier thread bị block!
}

// 2. Native method (JNI) trong blocking call
nativeBlockingCall(); // pin nếu native code giữ monitor

// FIX: thay synchronized bằng ReentrantLock
private final ReentrantLock lock = new ReentrantLock();
void goodMethod() {
    lock.lock();
    try {
        Thread.sleep(1000); // OK – virtual thread unmount được khi sleep
    } finally {
        lock.unlock();
    }
}
```

**Phát hiện pinning:**
```bash
-Djdk.tracePinnedThreads=full    # log khi pinning xảy ra
-Djdk.tracePinnedThreads=short   # log tóm tắt
```

> **Java 24 update**: `synchronized` sẽ không còn pin virtual thread — đang được fix trong Project Loom.

---

## How – ThreadLocal với Virtual Threads

**Vấn đề**: `ThreadLocal` vẫn hoạt động, nhưng với hàng triệu virtual threads → hàng triệu ThreadLocal instances → memory tăng đột biến.

```java
// Vấn đề: ThreadLocal với nhiều virtual threads
ThreadLocal<Connection> connectionLocal = new ThreadLocal<>();
// 1,000,000 virtual threads = 1,000,000 Connection objects trong ThreadLocal!

// Giải pháp: ScopedValue (Java 21 preview) – immutable, scope-based
ScopedValue<User> CURRENT_USER = ScopedValue.newInstance();

// Set value cho scope
ScopedValue.where(CURRENT_USER, user).run(() -> {
    // Trong scope này và tất cả subtask có thể đọc CURRENT_USER
    processRequest();
});

// Read
User user = CURRENT_USER.get();
// Không thể set lại (immutable) – tránh mutation bugs
```

---

## Components – Virtual Thread vs Platform Thread

| Khía cạnh | Platform Thread | Virtual Thread |
|----------|----------------|---------------|
| Mapping | 1 Java = 1 OS thread | M Java = N OS threads |
| Stack size | ~1MB (OS-managed, fixed) | ~KB ban đầu (JVM-managed, growable) |
| Tạo mới | Tốn kém (~1ms, ~1MB) | Rất rẻ (~µs, ~100 bytes) |
| Max concurrent | ~Vài nghìn | Hàng triệu |
| Blocking IO | Block OS thread | Unmount, carrier thread free |
| Scheduler | OS scheduler | JVM ForkJoinPool |
| ThreadLocal | OK | Cẩn thận (nhiều instances) |
| synchronized | OK | Có thể pin (avoid hoặc dùng Lock) |
| Debug | Dễ (thread name, stack) | Giống platform (Java 21 cải thiện) |

---

## Why – Tại sao Virtual Threads thay đổi Java?

### Vấn đề với Thread-per-request
```
Truyền thống:
  1 request → 1 platform thread (expensive!)
  Request: [compute 1ms] [DB query 50ms] [HTTP call 100ms] [compute 1ms]
  Thread bị chiếm 152ms dù chỉ work 2ms

Hệ quả:
  Thread pool = 200 threads
  50ms/request average → 200/0.05 = 4,000 req/s max throughput
  Mọi request đều phải chờ thread free → latency tăng khi tải cao
```

### Giải pháp cũ: Reactive Programming
```java
// Reactive (Project Reactor): non-blocking nhưng phức tạp
Mono<Response> handle(Request req) {
    return userRepository.findById(req.userId())     // Mono<User>
        .flatMap(user -> orderRepository.findByUser(user))  // Mono<List<Order>>
        .flatMap(orders -> walletRepository.findByUser(...)) // Mono<Wallet>
        .map(wallet -> new Response(user, orders, wallet))
        // Stack trace phức tạp, debug khó, callback hell
}
```

### Giải pháp mới: Virtual Threads
```java
// Virtual Thread: blocking code đơn giản, NHƯNG không block OS thread
Response handle(Request req) {
    User user     = userRepository.findById(req.userId());    // blocking OK!
    List<Order> orders = orderRepository.findByUser(user);    // blocking OK!
    Wallet wallet = walletRepository.findByUser(user);        // blocking OK!
    return new Response(user, orders, wallet);
    // JVM tự unmount khi blocking, carrier thread free
}
// Code đơn giản như sync, performance như async!
```

---

## When – Khi nào Virtual Thread phù hợp?

**Phù hợp:**
- **IO-bound** workloads: web server, database, HTTP calls, file IO
- **High concurrency**: hàng nghìn/triệu concurrent connections
- **Thread-per-request** model (Spring MVC, Servlet)
- Thay thế thread pool với bounded size

**Không phù hợp:**
- **CPU-bound** tasks: virtual thread không giúp ích (vẫn cần CPU, không unmount khi tính toán)
  → Dùng platform thread pool với số lượng = CPU cores
- Code dùng nhiều `synchronized` (pinning)
- Code nặng `ThreadLocal`

```java
// CPU-bound: virtual thread không lợi
try (var exec = Executors.newVirtualThreadPerTaskExecutor()) {
    // tính toán nặng – virtual thread vẫn chiếm carrier thread
    // không có benefit so với platform thread pool
    exec.submit(() -> computeHeavyMath(data));
}

// CPU-bound đúng cách: fixed platform thread pool = CPU cores
var cpuPool = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors());
cpuPool.submit(() -> computeHeavyMath(data));
```

---

## Compare – Virtual Threads vs Reactive

| | Virtual Threads | Reactive (WebFlux) |
|--|----------------|-------------------|
| Code style | Blocking (đơn giản) | Non-blocking (phức tạp) |
| Learning curve | Thấp | Cao |
| Debug | Dễ (stack trace linear) | Khó (async stack) |
| IO-bound | Excellent | Excellent |
| CPU-bound | Không tốt | Không tốt |
| Backpressure | Không built-in | Có (Reactor) |
| Streaming data | Không tốt | Rất tốt |
| Migration | Ít thay đổi code | Rewrite hoàn toàn |
| Throughput | Tương đương | Tương đương |
| Memory | Thấp hơn (JVM-managed) | Thấp |

> **Kết luận**: Virtual Threads thay thế Reactive cho hầu hết IO-bound use cases với code đơn giản hơn nhiều. Reactive vẫn tốt hơn cho streaming data và backpressure.

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Code đơn giản như sync | `synchronized` có thể pin (dùng Lock) |
| Hàng triệu concurrent threads | ThreadLocal cần cẩn thận |
| Không cần reactive framework | CPU-bound không benefit |
| Tương thích với code hiện có | Java 21+ |
| Debug dễ | ScopedValue còn preview |

---

## Real-world Usage (Production)

### 1. Spring Boot 3.2+ với Virtual Threads
```yaml
# application.yml
spring:
  threads:
    virtual:
      enabled: true
```

```java
// Hoặc config manual
@Configuration
public class ThreadConfig {
    @Bean
    public AsyncTaskExecutor applicationTaskExecutor() {
        return new TaskExecutorAdapter(Executors.newVirtualThreadPerTaskExecutor());
    }

    @Bean
    public TomcatProtocolHandlerCustomizer<?> protocolHandlerCustomizer() {
        return handler -> handler.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
    }
}
```

### 2. Concurrent API Calls
```java
@Service
public class DashboardService {
    public DashboardDto getDashboard(Long userId) throws Exception {
        try (var scope = new StructuredTaskScope.ShutdownOnFailure()) {
            var profileTask = scope.fork(() -> profileClient.get(userId));
            var ordersTask  = scope.fork(() -> orderClient.getRecent(userId));
            var walletTask  = scope.fork(() -> walletClient.get(userId));

            scope.join().throwIfFailed();

            return new DashboardDto(
                profileTask.get(),
                ordersTask.get(),
                walletTask.get()
            );
        }
    }
}
// Ba HTTP calls chạy song song, code linear, không cần CompletableFuture chain!
```

### 3. High-throughput Job Processor
```java
public void processJobs(List<Job> jobs) throws InterruptedException {
    try (ExecutorService exec = Executors.newVirtualThreadPerTaskExecutor()) {
        List<Future<Result>> futures = jobs.stream()
            .map(job -> exec.submit(() -> {
                // Mỗi job có thể blocking IO
                Result input = fetchInput(job);      // DB
                Result result = callApi(job, input); // HTTP
                saveResult(result);                   // DB
                return result;
            }))
            .toList();

        for (Future<Result> f : futures) {
            try { handleResult(f.get()); }
            catch (ExecutionException e) { handleError(e.getCause()); }
        }
    }
    // 10,000 jobs, mỗi job blocking IO → chạy đồng thời mà không tốn 10,000 OS threads
}
```

### 4. Migration từ Platform Thread Pool
```java
// Trước: fixed thread pool
ExecutorService executor = Executors.newFixedThreadPool(200);

// Sau: virtual thread (1 dòng thay đổi!)
ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();
// Tất cả code submit/get/Future vẫn hoạt động nguyên vẹn
```

---

## Ghi chú – Chủ đề tiếp theo

> Hoàn thành Modern Java (16–21).
>
> Tiếp theo: **Spring Framework**
> Thứ tự: Spring Core (IoC/DI) → Spring AOP → Spring Boot → Spring MVC → Spring Transaction
>
> Keyword Spring Core: ApplicationContext, BeanFactory, Bean lifecycle (instantiate → populate → aware callbacks → init → use → destroy), Bean scope (singleton/prototype/request/session), DI types (constructor/setter/field), @Autowired resolution order, @Qualifier, @Primary, @Conditional, @Profile, circular dependency
