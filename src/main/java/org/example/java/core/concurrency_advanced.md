# Concurrency Advanced – Fork/Join, Lock-free, Patterns

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## How – Fork/Join Framework (Java 7+)

**Fork/Join** = divide-and-conquer parallelism. Chia bài toán lớn thành sub-tasks, chạy song song, merge kết quả.

### Work-Stealing Algorithm

```
ForkJoinPool có N worker threads, mỗi thread có deque riêng:

Thread-1 deque: [task4][task3][task2][task1]  ← push/pop từ đầu (LIFO)
Thread-2 deque: []  ← idle → steal từ đuôi của Thread-1 (FIFO)

Tại sao LIFO + steal FIFO?
- LIFO (local): cache locality tốt (sub-task vừa fork còn warm trong cache)
- Steal FIFO: steal task cũ nhất → task lớn nhất → nhiều công việc nhất
- Tránh contention: producer push từ đầu, stealer steal từ đuôi (ít contention hơn)
```

### RecursiveTask (có kết quả)

```java
// Parallel merge sort
class MergeSortTask extends RecursiveTask<int[]> {
    private static final int THRESHOLD = 256; // bên dưới ngưỡng → sequential
    private final int[] array;
    private final int from, to;

    MergeSortTask(int[] array, int from, int to) {
        this.array = array; this.from = from; this.to = to;
    }

    @Override
    protected int[] compute() {
        int length = to - from;
        if (length <= THRESHOLD) {
            // Base case: sequential sort
            int[] copy = Arrays.copyOfRange(array, from, to);
            Arrays.sort(copy);
            return copy;
        }

        int mid = from + length / 2;
        MergeSortTask left  = new MergeSortTask(array, from, mid);
        MergeSortTask right = new MergeSortTask(array, mid, to);

        left.fork();           // submit left async
        int[] rightResult = right.compute(); // compute right on current thread
        int[] leftResult  = left.join();     // wait for left

        return merge(leftResult, rightResult);
    }

    // Pattern: fork() one subtask, compute() the other → tiết kiệm thread
    // Không dùng: left.fork() + right.fork() + left.join() + right.join()
    // → vì compute() trên current thread hiệu quả hơn fork() rồi join ngay
}

// Chạy
ForkJoinPool pool = ForkJoinPool.commonPool(); // shared pool
int[] sorted = pool.invoke(new MergeSortTask(array, 0, array.length));

// Hoặc custom pool
ForkJoinPool customPool = new ForkJoinPool(
    Runtime.getRuntime().availableProcessors(),
    ForkJoinPool.defaultForkJoinWorkerThreadFactory,
    null,  // UncaughtExceptionHandler
    false  // asyncMode: false=LIFO (default), true=FIFO (for event-driven)
);
```

### RecursiveAction (không có kết quả)

```java
// Parallel array fill
class FillAction extends RecursiveAction {
    private static final int THRESHOLD = 10_000;
    private final double[] data;
    private final int from, to;
    private final double value;

    @Override
    protected void compute() {
        if (to - from <= THRESHOLD) {
            Arrays.fill(data, from, to, value);
            return;
        }
        int mid = (from + to) >>> 1;
        invokeAll(
            new FillAction(data, from, mid, value),
            new FillAction(data, mid, to, value)
        ); // invokeAll: fork cả 2, join cả 2
    }
}
```

### Parallel Stream dùng ForkJoinPool

```java
// Parallel stream dùng ForkJoinPool.commonPool() mặc định
list.parallelStream().map(this::process).toList();

// Chạy trong custom pool (tránh chiếm commonPool)
ForkJoinPool myPool = new ForkJoinPool(4);
List<Result> results = myPool.submit(
    () -> list.parallelStream().map(this::process).toList()
).get();
myPool.shutdown();
```

---

## How – ThreadLocal (Deep Dive)

### Internals

```
ThreadLocal KHÔNG lưu trữ trong ThreadLocal object.
Mỗi Thread object có field:
  Thread.threadLocals → ThreadLocalMap (custom HashMap)
  Key: WeakReference<ThreadLocal>  ← yếu, có thể GC
  Value: Object (giá trị thực sự)

get():
  1. Lấy current thread
  2. Lấy thread.threadLocals (ThreadLocalMap)
  3. Lookup bằng ThreadLocal instance làm key
  4. Trả về value

ThreadLocalMap:
  - Mảng Entry[] (open addressing, not linked list)
  - Entry extends WeakReference<ThreadLocal<?>>
  - Stale entries được lazy-clean khi probe
```

```java
// Tạo và dùng ThreadLocal
ThreadLocal<SimpleDateFormat> dateFormat = ThreadLocal.withInitial(
    () -> new SimpleDateFormat("yyyy-MM-dd")
);

// Mỗi thread có instance riêng → thread-safe dù SimpleDateFormat không phải!
String formatted = dateFormat.get().format(new Date());

// PHẢI remove() sau khi dùng trong thread pool!
dateFormat.remove();

// ThreadLocal với initial value
ThreadLocal<User> currentUser = new ThreadLocal<>();
// hoặc
ThreadLocal<Integer> requestId = ThreadLocal.withInitial(
    () -> generateRequestId()
);
```

### Memory Leak Trong Thread Pool

```java
// NGUY HIỂM: Thread pool thread KHÔNG chết → ThreadLocal không được GC!
ExecutorService pool = Executors.newFixedThreadPool(10);

ThreadLocal<byte[]> cache = new ThreadLocal<>();

pool.submit(() -> {
    cache.set(new byte[1024 * 1024]); // 1MB per thread
    doWork();
    // THIẾU: cache.remove() → 1MB bị giữ mãi trong thread pool thread!
});

// Thread pool với 10 threads × 1MB = 10MB leak không bao giờ được giải phóng

// FIX: LUÔN remove() trong finally
pool.submit(() -> {
    cache.set(new byte[1024 * 1024]);
    try {
        doWork();
    } finally {
        cache.remove(); // Bắt buộc!
    }
});

// Key trong ThreadLocalMap là WeakReference → key bị GC khi ThreadLocal bị GC
// Nhưng VALUE là strong reference → value KHÔNG bị GC dù key bị!
// → Key là null (phantom), Value còn sống → stale entry leak
// Chỉ được clean khi ThreadLocalMap probe lần sau hoặc thread chết
```

### InheritableThreadLocal

```java
// InheritableThreadLocal: child thread kế thừa value từ parent
InheritableThreadLocal<String> requestContext = new InheritableThreadLocal<>();

// Parent thread
requestContext.set("request-123");

// Child thread (tạo từ parent thread)
Thread child = new Thread(() -> {
    System.out.println(requestContext.get()); // "request-123" (inherited!)
});
child.start();

// Vấn đề với thread pool: thread được tạo trước khi có context!
// Thread pool reuse thread → không phải "child" của request thread
// → InheritableThreadLocal không hoạt động đúng với thread pools

// Fix: TransmittableThreadLocal (Alibaba open source library)
// Hoặc: pass context explicitly qua method parameters
```

---

## How – Lock-Free Programming

### CAS (Compare-And-Swap) Pattern

```java
// CAS = atomic: read-compare-write, không cần lock
// Hardware instruction: CMPXCHG (x86)

AtomicInteger counter = new AtomicInteger(0);

// Manual CAS loop (low-level, educational)
int currentValue, newValue;
do {
    currentValue = counter.get();          // read
    newValue = currentValue + 1;           // compute
} while (!counter.compareAndSet(currentValue, newValue)); // CAS: retry nếu giá trị thay đổi

// Tương đương với:
counter.incrementAndGet();

// CAS trong Java 9+ (VarHandle):
VarHandle COUNT;
// ...
int current;
do {
    current = (int) COUNT.getVolatile(this);
} while (!COUNT.compareAndSet(this, current, current + 1));
```

### ABA Problem

```java
// ABA: giá trị thay đổi A → B → A, CAS không phát hiện!
// Thread 1: đọc A, chuẩn bị CAS A → C
// Thread 2: đổi A → B → A (trong khi Thread 1 đang chuẩn bị)
// Thread 1: CAS thành công (thấy A), nhưng A là "khác" A

// Classic example: lock-free stack
AtomicReference<Node> head = new AtomicReference<>(nodeA);
// Thread 1 muốn pop nodeA, đọc head = nodeA, next = nodeB
// Thread 2: pop nodeA, pop nodeB, push nodeA lại
// head = nodeA (same ref!) nhưng nodeA.next = null (nodeB đã bị pop)
// Thread 1: CAS head: nodeA → nodeB? Thành công! Nhưng nodeB đã bị pop → dangling pointer!

// FIX: AtomicStampedReference (thêm version/stamp)
AtomicStampedReference<Node> stampedHead =
    new AtomicStampedReference<>(nodeA, 0); // (ref, stamp)

int[] stampHolder = new int[1];
Node current = stampedHead.get(stampHolder); // lấy ref + stamp
int currentStamp = stampHolder[0];

// CAS chỉ thành công nếu cả ref VÀ stamp khớp
boolean success = stampedHead.compareAndSet(
    current, newNode,           // expected ref, new ref
    currentStamp, currentStamp + 1  // expected stamp, new stamp
);
// Thread 2 đã increment stamp → Thread 1's CAS thất bại!

// AtomicMarkableReference: 1 bit boolean thay vì int stamp
AtomicMarkableReference<Node> markableRef =
    new AtomicMarkableReference<>(node, false);
```

### Lock-Free Stack Implementation

```java
public class LockFreeStack<T> {
    private final AtomicReference<Node<T>> top = new AtomicReference<>(null);

    record Node<T>(T value, Node<T> next) {}

    public void push(T value) {
        Node<T> newNode;
        Node<T> current;
        do {
            current = top.get();
            newNode = new Node<>(value, current);
        } while (!top.compareAndSet(current, newNode));
    }

    public T pop() {
        Node<T> current;
        Node<T> next;
        do {
            current = top.get();
            if (current == null) return null; // empty
            next = current.next();
        } while (!top.compareAndSet(current, next));
        return current.value();
    }

    // ABA safe vì mỗi push tạo Node mới (không tái dùng)
}
```

---

## How – Phaser (Java 7+)

`Phaser` = flexible barrier, combines CountDownLatch + CyclicBarrier + thêm nhiều tính năng.

```java
// 3 threads chạy qua 3 phases, barrier sau mỗi phase
Phaser phaser = new Phaser(3); // 3 parties

Runnable worker = () -> {
    // Phase 1: data loading
    loadData();
    phaser.arriveAndAwaitAdvance(); // barrier phase 0 → 1

    // Phase 2: processing
    processData();
    phaser.arriveAndAwaitAdvance(); // barrier phase 1 → 2

    // Phase 3: saving
    saveResults();
    phaser.arriveAndDeregister();  // deregister khi xong
};

// Dynamic registration
Phaser dynamicPhaser = new Phaser(1); // chỉ main
for (int i = 0; i < n; i++) {
    dynamicPhaser.register(); // thêm party động
    executor.submit(() -> {
        doWork();
        dynamicPhaser.arriveAndDeregister();
    });
}
dynamicPhaser.arriveAndAwaitAdvance(); // main chờ tất cả

// Tiered Phaser (tree structure cho nhiều threads)
Phaser root = new Phaser();
Phaser child1 = new Phaser(root, 100); // 100 threads trong group 1
Phaser child2 = new Phaser(root, 100); // 100 threads trong group 2
// child advances → khi cả child1 và child2 advance → root advances
```

---

## How – Exchanger

`Exchanger` = hai thread trao đổi object tại điểm gặp nhau.

```java
Exchanger<DataBuffer> exchanger = new Exchanger<>();

// Producer thread: fill buffer rồi đổi lấy empty buffer
Thread producer = new Thread(() -> {
    DataBuffer filledBuffer = new DataBuffer();
    while (true) {
        fillBuffer(filledBuffer);
        DataBuffer emptyBuffer = exchanger.exchange(filledBuffer); // exchange!
        filledBuffer = emptyBuffer; // dùng lại empty buffer
    }
});

// Consumer thread: lấy filled buffer, đổi lại empty buffer
Thread consumer = new Thread(() -> {
    DataBuffer emptyBuffer = new DataBuffer();
    while (true) {
        DataBuffer filledBuffer = exchanger.exchange(emptyBuffer); // exchange!
        consume(filledBuffer);
        emptyBuffer = filledBuffer; // recycle
    }
});

// Dùng khi: double buffering, pipeline handoff giữa 2 threads
```

---

## How – Advanced CompletableFuture

```java
// Timeout (Java 9+)
CompletableFuture<String> future = fetchDataAsync()
    .orTimeout(5, TimeUnit.SECONDS); // throw TimeoutException sau 5s

CompletableFuture<String> withDefault = fetchDataAsync()
    .completeOnTimeout("default-value", 5, TimeUnit.SECONDS); // trả về default nếu timeout

// Delay (Java 9+)
CompletableFuture<String> delayed = CompletableFuture
    .supplyAsync(() -> "result")
    .thenComposeAsync(result ->
        CompletableFuture.completedFuture(result)
            .completeOnTimeout(result, 0, TimeUnit.MILLISECONDS),
        CompletableFuture.delayedExecutor(1, TimeUnit.SECONDS)); // delay 1s

// Error recovery chain
CompletableFuture<String> resilient = fetchFromPrimary()
    .exceptionallyCompose(ex -> {               // Java 12+: compose on exception
        log.warn("Primary failed, trying backup", ex);
        return fetchFromBackup();
    })
    .exceptionallyCompose(ex -> {
        log.error("Backup also failed", ex);
        return CompletableFuture.completedFuture("cached-fallback");
    });

// Combine many futures efficiently
List<CompletableFuture<Result>> futures = items.stream()
    .map(item -> CompletableFuture.supplyAsync(() -> process(item), executor))
    .toList();

CompletableFuture<List<Result>> all = CompletableFuture
    .allOf(futures.toArray(new CompletableFuture[0]))
    .thenApply(v -> futures.stream()
        .map(CompletableFuture::join) // safe: all complete here
        .toList());

// Chú ý: join() trong thenApply() là safe vì allOf đảm bảo tất cả done
// Không dùng get() (throws checked exception)

// Fan-out + fan-in pattern
CompletableFuture<Report> report = CompletableFuture
    .supplyAsync(this::fetchUsers)
    .thenCompose(users -> {
        // Fan-out: mỗi user process song song
        List<CompletableFuture<UserReport>> userReports = users.stream()
            .map(u -> CompletableFuture.supplyAsync(() -> processUser(u), executor))
            .toList();
        // Fan-in: tổng hợp
        return CompletableFuture
            .allOf(userReports.toArray(new CompletableFuture[0]))
            .thenApply(v -> userReports.stream()
                .map(CompletableFuture::join)
                .toList());
    })
    .thenApply(this::aggregateReports);
```

---

## How – Flow API (Reactive Streams, Java 9+)

```java
// Flow.Publisher, Flow.Subscriber, Flow.Subscription, Flow.Processor

// Custom Publisher (simple)
public class RangePublisher implements Flow.Publisher<Integer> {
    private final int from, to;
    RangePublisher(int from, int to) { this.from = from; this.to = to; }

    @Override
    public void subscribe(Flow.Subscriber<? super Integer> subscriber) {
        subscriber.onSubscribe(new Flow.Subscription() {
            private int current = from;
            private boolean cancelled = false;

            @Override
            public void request(long n) {
                for (long i = 0; i < n && current < to && !cancelled; i++) {
                    subscriber.onNext(current++);
                }
                if (current >= to && !cancelled) {
                    subscriber.onComplete();
                }
            }

            @Override
            public void cancel() { cancelled = true; }
        });
    }
}

// SubmissionPublisher (built-in publisher)
SubmissionPublisher<String> publisher = new SubmissionPublisher<>();

// Subscriber
publisher.subscribe(new Flow.Subscriber<>() {
    private Flow.Subscription subscription;

    @Override
    public void onSubscribe(Flow.Subscription s) {
        this.subscription = s;
        s.request(1); // backpressure: xin 1 item
    }

    @Override
    public void onNext(String item) {
        System.out.println("Received: " + item);
        subscription.request(1); // xin thêm 1 item
    }

    @Override
    public void onError(Throwable t) { t.printStackTrace(); }

    @Override
    public void onComplete() { System.out.println("Done"); }
});

publisher.submit("item1");
publisher.submit("item2");
publisher.close(); // onComplete
```

---

## How – Thread Safety Patterns

### 1. Immutable Object (safest)

```java
// Tất cả fields final, không có setter, defensive copy
@Value // Lombok tạo immutable class
public final class Money {
    private final BigDecimal amount;
    private final Currency currency;

    // Không cần synchronization: immutable objects thread-safe by definition
    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) throw new IllegalArgumentException();
        return new Money(this.amount.add(other.amount), this.currency); // tạo mới
    }
}
```

### 2. Thread Confinement

```java
// Thread confinement: object chỉ được access từ 1 thread → không cần sync

// Stack confinement: local variable không escape
public void doWork() {
    List<String> localList = new ArrayList<>(); // thread-confined (trên stack)
    localList.add("a");
    // localList không được chia sẻ → thread-safe tự nhiên
}

// ThreadLocal confinement: mỗi thread có copy riêng
ThreadLocal<Connection> threadLocalConn = ThreadLocal.withInitial(() -> openConnection());

// Ad-hoc confinement: documented, enforced bởi convention
// @GuardedBy("this") → phải hold lock khi access
@GuardedBy("this")
private int counter = 0;
```

### 3. Safe Publication Patterns

```java
// 1. Static initializer (JVM thread-safe)
public static final Singleton INSTANCE = new Singleton();

// 2. volatile (JMM guarantee)
private volatile Config config;

// 3. final (immutable guarantee after constructor)
private final Map<String, String> data;

// 4. synchronized publication
private synchronized void setConfig(Config c) { this.config = c; }
private synchronized Config getConfig() { return this.config; }
```

### 4. Immutable Object + Volatile Reference Pattern

```java
// Copy-on-write immutable config (common in Spring, Guava)
public class ConfigManager {
    private volatile Config current; // volatile reference to immutable object

    public Config getConfig() {
        return current; // safe: volatile read, Config is immutable
    }

    public void updateConfig(String key, String value) {
        // Create new immutable config with change
        Config newConfig = current.withChange(key, value); // returns new Config
        current = newConfig; // volatile write
        // No lock needed! Reads see either old or new Config (both valid)
    }
}
```

---

## How – Deadlock Prevention Strategies

```java
// 1. Lock Ordering (canonical order)
// Luôn acquire lock theo thứ tự hash/id
public void transfer(Account from, Account to, BigDecimal amount) {
    Account first  = from.getId() < to.getId() ? from : to;
    Account second = from.getId() < to.getId() ? to : from;

    synchronized (first) {
        synchronized (second) {
            from.debit(amount);
            to.credit(amount);
        }
    }
}

// 2. tryLock with timeout
public boolean transfer(Account from, Account to, BigDecimal amount) {
    long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
    while (true) {
        if (from.lock.tryLock()) {
            try {
                if (to.lock.tryLock()) {
                    try {
                        from.debit(amount);
                        to.credit(amount);
                        return true;
                    } finally { to.lock.unlock(); }
                }
            } finally { from.lock.unlock(); }
        }
        if (System.nanoTime() >= deadline) return false; // timeout
        Thread.sleep(1); // backoff
    }
}

// 3. Coarse-grained single lock (simplest, least concurrent)
private static final ReentrantLock GLOBAL_LOCK = new ReentrantLock();
GLOBAL_LOCK.lock();
try {
    from.debit(amount);
    to.credit(amount);
} finally { GLOBAL_LOCK.unlock(); }
```

---

## Components – Concurrency Tools Summary

| Tool | Use case | Key feature |
|------|---------|-------------|
| `synchronized` | Simple critical section | Reentrant, JVM native |
| `ReentrantLock` | Advanced locking (timeout, fair) | Condition variables |
| `ReadWriteLock` | Read-heavy, write-rare | Multiple concurrent readers |
| `StampedLock` | Optimistic read | Fastest for read-mostly |
| `AtomicXxx` | Single variable, no lock | CAS hardware instruction |
| `LongAdder` | High-contention counter | Stripe-based, low contention |
| `ThreadLocal` | Per-thread state | No sharing needed |
| `ForkJoinPool` | CPU-bound divide-conquer | Work-stealing |
| `CompletableFuture` | Async pipelines | Non-blocking composition |
| `CountDownLatch` | One-time barrier | Main waits workers |
| `CyclicBarrier` | Reusable barrier | N threads sync at checkpoints |
| `Phaser` | Multi-phase, dynamic | Register/deregister parties |
| `Semaphore` | Resource pool | N concurrent permits |
| `Exchanger` | Two-thread handoff | Buffer swapping |
| `Flow` | Reactive streams | Backpressure built-in |

---

## Trade-offs

| Pattern | Throughput | Latency | Complexity | Risk |
|---------|-----------|---------|-----------|------|
| Coarse lock | Low | High | Low | Deadlock possible |
| Fine-grained lock | High | Low | High | Deadlock, livelock |
| Lock-free (CAS) | Highest | Lowest | Very high | ABA problem |
| STM (via libraries) | Medium | Medium | Medium | Not JDK built-in |
| Actor model | High | Medium | Medium | Library needed |

---

## Real-world Usage (Production)

### 1. ForkJoin: Parallel Report Generation

```java
@Service
public class ReportService {
    private final ForkJoinPool reportPool = new ForkJoinPool(
        Math.max(2, Runtime.getRuntime().availableProcessors() / 2)
        // Dùng nửa core cho report, để nửa còn lại cho HTTP requests
    );

    public Report generateReport(List<Department> departments) {
        return reportPool.invoke(new DepartmentReportTask(departments, 0, departments.size()));
    }

    class DepartmentReportTask extends RecursiveTask<Report> {
        private static final int THRESHOLD = 5;
        // ...
        @Override
        protected Report compute() {
            if (to - from <= THRESHOLD) {
                return departments.subList(from, to).stream()
                    .map(reportGenerator::generate)
                    .reduce(Report.empty(), Report::merge);
            }
            int mid = (from + to) / 2;
            DepartmentReportTask left  = new DepartmentReportTask(departments, from, mid);
            DepartmentReportTask right = new DepartmentReportTask(departments, mid, to);
            left.fork();
            Report rightResult = right.compute();
            Report leftResult  = left.join();
            return leftResult.merge(rightResult);
        }
    }
}
```

### 2. ThreadLocal cho Request Context

```java
@Component
public class RequestContext {
    private static final ThreadLocal<RequestMetadata> CONTEXT = new ThreadLocal<>();

    public static void set(RequestMetadata meta) { CONTEXT.set(meta); }
    public static RequestMetadata get() { return CONTEXT.get(); }
    public static void clear() { CONTEXT.remove(); }
}

// Filter set/clear
@Component
public class RequestContextFilter implements Filter {
    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {
        try {
            RequestContext.set(extractMetadata(req));
            chain.doFilter(req, res);
        } finally {
            RequestContext.clear(); // PHẢI clear để tránh leak trong thread pool
        }
    }
}

// Service dùng
@Service
public class AuditService {
    public void log(String action) {
        RequestMetadata meta = RequestContext.get(); // không cần truyền qua params
        audit(meta.getUserId(), meta.getRequestId(), action);
    }
}
```

### 3. Rate Limiter với Semaphore

```java
@Component
public class ExternalApiClient {
    // Cho phép tối đa 10 concurrent calls tới external API
    private final Semaphore concurrencyLimit = new Semaphore(10);
    // Leaky bucket: tối đa 100 calls/giây
    private final Semaphore rateBucket = new Semaphore(100);

    @Scheduled(fixedRate = 1000)
    public void refillBucket() {
        int deficit = 100 - rateBucket.availablePermits();
        if (deficit > 0) rateBucket.release(deficit);
    }

    public Response callApi(Request req) throws InterruptedException {
        if (!rateBucket.tryAcquire(1, 1, TimeUnit.SECONDS)) {
            throw new RateLimitExceededException("Rate limit: 100 req/s");
        }
        concurrencyLimit.acquire();
        try {
            return httpClient.send(req);
        } finally {
            concurrencyLimit.release();
        }
    }
}
```

---

## Ghi chú – Chủ đề liên quan

> Xem thêm:
> - **java_memory_model.md**: happens-before, volatile, safe publication (nền tảng lý thuyết)
> - **virtual_threads.md**: Project Loom thay thế thread pool cho IO-bound
> - **collections_internals.md**: ConcurrentHashMap, BlockingQueue internals
