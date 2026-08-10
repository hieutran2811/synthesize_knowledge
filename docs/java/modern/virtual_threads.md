---
title: "Virtual Threads – Project Loom (Java 21)"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 1
---
# Virtual Threads – Project Loom (Java 21)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Virtual Threads là gì?

**Virtual Threads** *(luồng ảo)* — chính thức từ Java 21, preview ở Java 19–20 — là **lightweight threads** *(luồng nhẹ)* được JVM lập lịch, thay vì gắn cố định mỗi Java thread với một OS thread *(luồng hệ điều hành)*. Nhờ chi phí thấp, một JVM có thể duy trì số lượng virtual thread rất lớn cho các tác vụ đồng thời thiên về I/O.

> 💡 **Giải thích dễ hiểu — nhiều khách, ít nhân viên phục vụ:**
> Platform thread giống mỗi khách phải giữ riêng một nhân viên kể cả lúc đang chờ bếp. Virtual thread giống phiếu yêu cầu của khách: khi một yêu cầu chờ database hoặc mạng, JVM cất trạng thái của nó và để số ít **carrier thread** *(luồng vận chuyển)* phục vụ yêu cầu khác. Virtual thread không làm CPU mạnh hơn; nó chủ yếu tránh lãng phí OS thread trong thời gian chờ I/O.

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

> 💡 **Giải thích dễ hiểu — M:N thay cho 1:1:**
> Nhiều virtual thread (M) được luân phiên chạy trên ít carrier/platform thread hơn (N). Carrier không phải “thread cha” sở hữu virtual thread; nó chỉ là chiếc xe tạm thời chở một virtual thread tới CPU. Sau mỗi lần unmount/remount, cùng một virtual thread có thể tiếp tục trên carrier khác.

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

> 💡 **Giải thích dễ hiểu — continuation là dấu trang có thể mang đi:**
> Khi gặp thao tác chờ hỗ trợ virtual thread, JVM chụp lại trạng thái thực thi thành **continuation** *(phần việc có thể tạm dừng rồi tiếp tục)*, giống kẹp dấu trang và cất cuốn sách lên kệ. Carrier rảnh để đọc cuốn khác; khi I/O xong, JVM lấy cuốn cũ xuống và đọc tiếp đúng dòng đang dở.

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

> 💡 **Giải thích dễ hiểu — một task, một virtual thread:**
> Với virtual thread, không cần pool nhỏ để hạn chế số thread như mô hình platform thread. Mỗi task có thể nhận một virtual thread mới; nếu cần bảo vệ database hoặc API khỏi quá tải, hãy giới hạn **tài nguyên đích** bằng connection pool, semaphore hoặc rate limiter, thay vì dùng thread pool như một van tiết lưu gián tiếp.

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

**Structured Concurrency** *(đồng thời có cấu trúc)*: ràng buộc vòng đời của subtask bên trong task cha → dễ chờ, hủy và lan truyền lỗi có kiểm soát.

> 💡 **Giải thích dễ hiểu — task con phải về nhà trước khi đóng cửa:**
> Scope giống một chuyến đi gia đình: cha có thể chia người đi lấy thông tin user, order và wallet cùng lúc, nhưng không ai được lang thang sau khi chuyến đi kết thúc. Khi một nhánh thất bại, policy của scope quyết định hủy các nhánh còn lại; log và stack trace cũng giữ được quan hệ cha–con thay vì tạo các `Future` sống rời rạc.

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

**Hành vi phụ thuộc phiên bản JDK:**
- **JDK 21–23**: blocking bên trong `synchronized` có thể pin virtual thread; native/foreign call cũng có thể pin.
- **JDK 24+**: [JEP 491](https://openjdk.org/jeps/491) cho phép virtual thread unmount khi đang giữ hoặc chờ monitor `synchronized`, loại bỏ gần như toàn bộ pinning do `synchronized`. Pinning vẫn có thể xảy ra khi chạy native method hoặc foreign function.

> 💡 **Giải thích dễ hiểu — pinning là giữ luôn chiếc xe khi đang chờ:**
> Bình thường virtual thread xuống khỏi carrier khi phải chờ để carrier chở việc khác. Khi bị pin, nó ngồi nguyên trên xe dù chưa làm gì, khiến cả virtual thread lẫn carrier cùng mắc kẹt. Một lần pin ngắn không đáng ngại; pin thường xuyên và lâu mới làm cạn carrier, giảm khả năng phục vụ đồng thời.

**Ví dụ tương thích JDK 21–23:**
```java
// Trên JDK 21–23, sleep/blocking trong synchronized có thể pin carrier.
synchronized void badMethod() {
    Thread.sleep(1000); // virtual thread bị pin, carrier thread bị block!
}

// Cách tránh trên JDK 21–23: thu hẹp critical section hoặc dùng ReentrantLock.
private final ReentrantLock lock = new ReentrantLock();
void goodMethod() {
    lock.lock();
    try {
        Thread.sleep(1000); // OK – virtual thread unmount được khi sleep
    } finally {
        lock.unlock();
    }
}

// JDK 24+: synchronized ở trên không còn pin do JEP 491.
// Native/foreign call vẫn cần được đánh giá riêng.
nativeBlockingCall();
```

**Phát hiện pinning trên JDK 21–23:**
```bash
-Djdk.tracePinnedThreads=full    # log khi pinning xảy ra
-Djdk.tracePinnedThreads=short   # log tóm tắt
```

> **JDK 24+**: JEP 491 đã loại bỏ system property `jdk.tracePinnedThreads`; đặt cờ này không còn tác dụng.

---

## How – ThreadLocal với Virtual Threads

**Vấn đề**: `ThreadLocal` vẫn hoạt động, nhưng với hàng triệu virtual threads → hàng triệu ThreadLocal instances → memory tăng đột biến.

> 💡 **Giải thích dễ hiểu — đồ trong ngăn riêng vẫn nhân theo số luồng:**
> Virtual thread rẻ không có nghĩa dữ liệu gắn vào từng thread cũng rẻ. Nếu mỗi khách được phát một vali `ThreadLocal` chứa connection hoặc cache lớn, một triệu khách vẫn tạo ra một triệu vali. `ScopedValue` phù hợp với dữ liệu chỉ đọc truyền theo phạm vi lời gọi, như user hiện tại hoặc trace ID, vì vòng đời và quyền thay đổi rõ ràng hơn.

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
| synchronized | OK | JDK 21–23 có thể pin; JDK 24+ không còn pin do monitor |
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
- Trên JDK 21–23: code blocking lâu bên trong `synchronized`
- Native/foreign call blocking lâu làm virtual thread bị pin
- Code nặng `ThreadLocal`

> 💡 **Giải thích dễ hiểu — concurrency không tạo thêm parallelism:**
> Virtual thread giúp rất nhiều công việc **cùng tồn tại** và thay nhau dùng CPU khi phần lớn thời gian là chờ. Nếu mọi task đều tính toán liên tục, chúng vẫn tranh cùng số core vật lý; tạo thêm virtual thread chỉ làm hàng chờ dài hơn. Với CPU-bound workload, pool platform thread xấp xỉ số core thường dễ kiểm soát hơn.

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
| Code đơn giản như sync | Native/foreign call vẫn có thể pin; JDK 21–23 còn pin trong `synchronized` |
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
