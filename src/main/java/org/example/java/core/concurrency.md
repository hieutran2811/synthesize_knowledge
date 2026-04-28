# Concurrency & Multithreading (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Concurrency & Multithreading là gì?

- **Concurrency**: nhiều task được xử lý trong cùng khoảng thời gian (không nhất thiết đồng thời)
- **Parallelism**: nhiều task thực sự chạy đồng thời trên nhiều CPU core
- **Thread**: đơn vị thực thi nhỏ nhất trong JVM, chia sẻ heap memory nhưng có stack riêng

**Tại sao cần?**
- Tận dụng multi-core CPU
- Responsive UI (UI thread không bị block)
- IO-bound: trong lúc chờ IO, xử lý việc khác
- Throughput: xử lý nhiều request đồng thời

---

## How – Thread Lifecycle

```
NEW → RUNNABLE → BLOCKED → WAITING → TIMED_WAITING → TERMINATED
        ↓             ↑       ↑              ↑
     start()    synchronized  wait()      sleep(n)
                   lock      join()       wait(n)
                available    park()      join(n)
```

| State | Mô tả |
|-------|-------|
| `NEW` | Thread đã tạo nhưng chưa `start()` |
| `RUNNABLE` | Đang chạy hoặc ready chờ CPU scheduler |
| `BLOCKED` | Chờ acquire intrinsic lock (synchronized) |
| `WAITING` | Chờ vô thời hạn (`wait()`, `join()`, `park()`) |
| `TIMED_WAITING` | Chờ có timeout (`sleep(n)`, `wait(n)`, `join(n)`) |
| `TERMINATED` | `run()` đã kết thúc |

```java
Thread t = new Thread(() -> {
    try { Thread.sleep(1000); }
    catch (InterruptedException e) { Thread.currentThread().interrupt(); }
});
System.out.println(t.getState()); // NEW
t.start();
System.out.println(t.getState()); // RUNNABLE hoặc TIMED_WAITING
t.join();
System.out.println(t.getState()); // TERMINATED
```

---

## How – Tạo Thread

### Cách 1: extends Thread (hạn chế dùng)
```java
class MyThread extends Thread {
    @Override
    public void run() { System.out.println("Thread: " + getName()); }
}
new MyThread().start();
// Nhược điểm: không thể extend class khác
```

### Cách 2: implement Runnable (preferred đơn giản)
```java
Runnable task = () -> System.out.println("Running: " + Thread.currentThread().getName());
Thread t = new Thread(task, "my-thread");
t.start();
```

### Cách 3: Callable + Future (khi cần kết quả)
```java
Callable<Integer> callable = () -> {
    Thread.sleep(1000);
    return 42;
};

ExecutorService executor = Executors.newSingleThreadExecutor();
Future<Integer> future = executor.submit(callable);

// future.get() BLOCK cho đến khi xong
Integer result = future.get();         // block indefinitely
Integer result2 = future.get(5, TimeUnit.SECONDS); // block tối đa 5s
future.cancel(true);                   // interrupt nếu đang chạy
future.isDone();
future.isCancelled();
```

### Cách 4: ExecutorService (production standard)
```java
// Thread pool types
ExecutorService fixed   = Executors.newFixedThreadPool(4);        // 4 threads cố định
ExecutorService cached  = Executors.newCachedThreadPool();         // tạo thêm thread khi cần
ExecutorService single  = Executors.newSingleThreadExecutor();     // 1 thread tuần tự
ExecutorService workSt  = Executors.newWorkStealingPool();        // ForkJoinPool, Java 8+
ScheduledExecutorService sched = Executors.newScheduledThreadPool(2);

// Shutdown đúng cách
executor.shutdown();                        // không nhận task mới, chờ task cũ xong
boolean done = executor.awaitTermination(30, TimeUnit.SECONDS);
if (!done) executor.shutdownNow();          // interrupt tất cả
```

---

## How – Synchronization

### Intrinsic Lock (synchronized)

Mỗi Java object có 1 intrinsic lock (monitor). `synchronized` acquire lock trước khi vào block.

```java
public class Counter {
    private int count = 0;

    // Synchronized method: lock = this
    public synchronized void increment() { count++; }

    // Synchronized block: fine-grained (khuyến nghị)
    private final Object lock = new Object();
    public void decrement() {
        synchronized (lock) { count--; }
    }

    // Static synchronized: lock = Counter.class
    public static synchronized void staticOp() { ... }
}
```

**Reentrant**: cùng thread có thể acquire lock nhiều lần (không tự deadlock):
```java
synchronized void outer() {
    synchronized (this) { // reentrant – cùng thread, OK
        inner();
    }
}
synchronized void inner() { /* ... */ }
```

### volatile – Visibility Guarantee

`volatile` đảm bảo:
1. **Visibility**: write tới volatile variable visible ngay với tất cả thread
2. **Ordering**: không reorder xung quanh volatile access

**KHÔNG đảm bảo atomicity** cho compound operations (`i++` = read + add + write):

```java
public class StopFlag {
    private volatile boolean running = true; // visibility

    public void stop() { running = false; }  // write visible immediately

    public void run() {
        while (running) { doWork(); }        // đọc fresh value mỗi lần
    }
}

// SAIT: volatile không đủ cho i++
volatile int count = 0;
count++; // NOT ATOMIC! race condition vẫn có thể xảy ra
```

### Atomic Classes (java.util.concurrent.atomic)

CAS (Compare-And-Swap) – lock-free thread safety:

```java
// AtomicInteger, AtomicLong, AtomicBoolean, AtomicReference
AtomicInteger counter = new AtomicInteger(0);
counter.incrementAndGet();           // i++ atomic
counter.getAndAdd(5);                // get rồi add
counter.compareAndSet(10, 20);       // CAS: nếu value==10 thì set=20, return true/false

AtomicReference<Node> head = new AtomicReference<>(null);
head.compareAndSet(null, newNode);   // lock-free linked list

// LongAdder – high contention counter (Java 8+, nhanh hơn AtomicLong)
LongAdder adder = new LongAdder();
adder.increment(); // nhiều thread cộng vào cell riêng, tổng khi cần
adder.sum();
```

---

## How – Locks (java.util.concurrent.locks)

### ReentrantLock – Linh hoạt hơn synchronized

```java
ReentrantLock lock = new ReentrantLock(true); // fair=true: FIFO order

lock.lock(); // block cho đến khi acquire
try {
    criticalSection();
} finally {
    lock.unlock(); // PHẢI unlock trong finally!
}

// tryLock – không block
if (lock.tryLock()) {
    try { criticalSection(); }
    finally { lock.unlock(); }
} else {
    // thực hiện việc khác
}

// tryLock với timeout
if (lock.tryLock(5, TimeUnit.SECONDS)) { ... }

// Condition variable (thay thế wait/notify)
Condition notEmpty = lock.newCondition();
Condition notFull = lock.newCondition();

// Producer:
lock.lock();
try {
    while (isFull()) notFull.await(); // release lock và chờ
    add(item);
    notEmpty.signal();
} finally { lock.unlock(); }
```

### ReadWriteLock – Tối ưu read-heavy

```java
ReadWriteLock rwLock = new ReentrantReadWriteLock();
Lock readLock  = rwLock.readLock();
Lock writeLock = rwLock.writeLock();

// Nhiều thread đọc đồng thời (read không block read)
readLock.lock();
try { return data.get(key); }
finally { readLock.unlock(); }

// Chỉ 1 thread ghi (write block cả read và write)
writeLock.lock();
try { data.put(key, value); }
finally { writeLock.unlock(); }
```

### StampedLock (Java 8+) – Optimistic Reading

```java
StampedLock sl = new StampedLock();

// Optimistic read (không acquire lock)
long stamp = sl.tryOptimisticRead();
double x = this.x;
double y = this.y;
if (!sl.validate(stamp)) { // kiểm tra có write xảy ra không
    stamp = sl.readLock(); // fallback to read lock
    try { x = this.x; y = this.y; }
    finally { sl.unlockRead(stamp); }
}
```

---

## How – CompletableFuture (Java 8+)

Async pipeline không cần block:

```java
// Tạo
CompletableFuture<String> cf1 = CompletableFuture.supplyAsync(() -> fetchUser(id));
CompletableFuture<Void> cf2 = CompletableFuture.runAsync(() -> sendNotification());

// Transform (thenApply = map, không block)
CompletableFuture<Integer> length = cf1.thenApply(String::length);

// Side-effect (thenAccept = forEach)
cf1.thenAccept(user -> System.out.println("Got: " + user));

// Chain (thenCompose = flatMap)
CompletableFuture<Order> order = cf1
    .thenCompose(user -> fetchOrder(user.getId()));

// Combine 2 futures
CompletableFuture<String> combined = cf1
    .thenCombine(fetchAddress(id), (user, addr) -> user + " lives at " + addr);

// Chạy song song, chờ tất cả
CompletableFuture.allOf(cf1, cf2, cf3).thenRun(() -> System.out.println("All done"));

// Lấy kết quả đầu tiên
CompletableFuture.anyOf(cf1, cf2).thenAccept(result -> use(result));

// Exception handling
cf1.exceptionally(ex -> "default-user")
   .handle((result, ex) -> ex != null ? "error" : result)
   .whenComplete((result, ex) -> log(result, ex)); // luôn chạy

// Specify executor
cf1.thenApplyAsync(String::length, customExecutor);
```

---

## How – Synchronization Utilities

### CountDownLatch – Một chiều, không reset
```java
// Main thread chờ N worker hoàn thành
CountDownLatch latch = new CountDownLatch(3);

for (int i = 0; i < 3; i++) {
    executor.submit(() -> {
        try { doWork(); }
        finally { latch.countDown(); } // giảm count
    });
}

latch.await();          // block cho đến count = 0
latch.await(10, TimeUnit.SECONDS); // với timeout
```

### CyclicBarrier – Tất cả chờ nhau tại barrier point
```java
// N thread chờ nhau tại checkpoint
CyclicBarrier barrier = new CyclicBarrier(3, () -> System.out.println("All arrived!"));

Runnable worker = () -> {
    phase1();
    barrier.await(); // chờ 2 thread kia đến đây
    phase2();        // tất cả bắt đầu phase2 cùng lúc
};
// Reusable: sau khi tất cả qua, barrier reset
```

### Semaphore – Giới hạn concurrent access
```java
// Chỉ cho phép 5 thread đồng thời vào database connection pool
Semaphore permits = new Semaphore(5);

permits.acquire();       // block nếu không còn permit
try { useDatabase(); }
finally { permits.release(); }

permits.tryAcquire();                   // non-blocking
permits.tryAcquire(2, TimeUnit.SECONDS); // với timeout
```

---

## How – Concurrent Collections

```java
// ConcurrentHashMap – thread-safe HashMap với fine-grained locking
ConcurrentHashMap<String, Integer> map = new ConcurrentHashMap<>();
map.putIfAbsent("key", 1);
map.computeIfAbsent("key", k -> computeExpensive(k));
map.merge("count", 1, Integer::sum); // atomic increment

// CopyOnWriteArrayList – thread-safe, copy-on-write
CopyOnWriteArrayList<String> list = new CopyOnWriteArrayList<>();
list.add("a"); // tạo copy mới
// Iterator an toàn – iterate trên snapshot

// BlockingQueue implementations
BlockingQueue<Task> queue = new ArrayBlockingQueue<>(100);  // bounded
BlockingQueue<Task> queue2 = new LinkedBlockingQueue<>();    // unbounded
BlockingQueue<Task> queue3 = new PriorityBlockingQueue<>();  // priority-based

queue.put(task);    // block nếu đầy
queue.take();       // block nếu trống
queue.offer(task, 1, TimeUnit.SECONDS); // với timeout

// ConcurrentLinkedQueue – lock-free FIFO
ConcurrentLinkedQueue<Task> clq = new ConcurrentLinkedQueue<>();
```

---

## Components – Race Conditions & Pitfalls

### Race Condition
```java
// Đọc-sửa-ghi: KHÔNG atomic dù chỉ 1 dòng
class BadCounter {
    private int count = 0;
    public void increment() { count++; } // read(count) + add(1) + write → 3 ops!
}

// Fix 1: synchronized
public synchronized void increment() { count++; }

// Fix 2: AtomicInteger
private AtomicInteger count = new AtomicInteger(0);
public void increment() { count.incrementAndGet(); }
```

### Deadlock
```java
// Thread A: lock1 → chờ lock2
// Thread B: lock2 → chờ lock1 → DEADLOCK!
Object lock1 = new Object(), lock2 = new Object();

Thread a = new Thread(() -> {
    synchronized (lock1) {
        Thread.sleep(100); // giả lập work
        synchronized (lock2) { /* ... */ }
    }
});
Thread b = new Thread(() -> {
    synchronized (lock2) {
        Thread.sleep(100);
        synchronized (lock1) { /* ... */ } // deadlock!
    }
});

// Giải pháp:
// 1. Luôn acquire lock theo CÙNG THỨ TỰ
// 2. Dùng tryLock() với timeout
// 3. Lock ordering: lock với ID nhỏ hơn trước
```

### Livelock
```java
// Thread A và B đều nhường nhau liên tục → không ai tiến được
// (giống 2 người tránh nhau trong hành lang mãi không đi được)
// Fix: random backoff trước khi retry
```

### Starvation
```java
// Thread có priority thấp không bao giờ được chạy vì high-priority threads chiếm lock
// Fix: fair lock (new ReentrantLock(true))
```

---

## When – Chọn công cụ nào?

| Tình huống | Dùng |
|-----------|------|
| Đơn giản, 1-2 thread | `synchronized` |
| Cần tryLock, fairness | `ReentrantLock` |
| Read nhiều, write ít | `ReadWriteLock` |
| Counter high-contention | `LongAdder`, `AtomicLong` |
| Task đơn giản async | `CompletableFuture` |
| IO-bound tasks | `ExecutorService` với cached pool |
| CPU-bound tasks | `ForkJoinPool`, parallel stream |
| Producer-consumer | `BlockingQueue` |
| Chờ N task hoàn thành | `CountDownLatch` |
| N thread chờ nhau | `CyclicBarrier` |
| Rate limiting | `Semaphore` |

---

## Compare – Synchronization Approaches

| Approach | Performance | Linh hoạt | Khó dùng |
|----------|-----------|-----------|---------|
| `synchronized` | Trung bình | Thấp | Thấp |
| `volatile` | Cao | Rất thấp | Thấp |
| `AtomicXxx` | Cao | Trung bình | Trung bình |
| `ReentrantLock` | Trung bình-Cao | Cao | Trung bình |
| `StampedLock` | Cao nhất | Cao | Cao |
| `ConcurrentHashMap` | Cao | N/A | Thấp |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Tận dụng multi-core | Race condition, deadlock khó debug |
| Tăng throughput | Overhead context switching |
| Non-blocking operations | Memory model phức tạp |
| CompletableFuture composable | Stack trace khó đọc với async |

---

## Real-world Usage (Production)

### 1. ThreadPoolExecutor tùy chỉnh
```java
// Tùy chỉnh hoàn toàn thread pool
ExecutorService executor = new ThreadPoolExecutor(
    4,                          // corePoolSize
    8,                          // maximumPoolSize
    60L, TimeUnit.SECONDS,      // keepAliveTime cho idle thread
    new ArrayBlockingQueue<>(100), // task queue (bounded!)
    new ThreadFactory() {
        AtomicInteger count = new AtomicInteger();
        public Thread newThread(Runnable r) {
            Thread t = new Thread(r, "order-processor-" + count.incrementAndGet());
            t.setDaemon(false);
            return t;
        }
    },
    new ThreadPoolExecutor.CallerRunsPolicy() // rejection policy: caller tự chạy
    // Alternatives: AbortPolicy (throw), DiscardPolicy (discard), DiscardOldestPolicy
);
```

### 2. Async Service với CompletableFuture
```java
@Service
public class DashboardService {
    private final ExecutorService io = Executors.newFixedThreadPool(10);

    public DashboardData getDashboard(Long userId) {
        CompletableFuture<UserProfile> profileFuture =
            CompletableFuture.supplyAsync(() -> profileService.get(userId), io);
        CompletableFuture<List<Order>> ordersFuture =
            CompletableFuture.supplyAsync(() -> orderService.getRecent(userId), io);
        CompletableFuture<Wallet> walletFuture =
            CompletableFuture.supplyAsync(() -> walletService.get(userId), io);

        return CompletableFuture.allOf(profileFuture, ordersFuture, walletFuture)
            .thenApply(v -> DashboardData.builder()
                .profile(profileFuture.join())
                .orders(ordersFuture.join())
                .wallet(walletFuture.join())
                .build())
            .get(10, TimeUnit.SECONDS);
    }
}
```

### 3. Phát hiện Deadlock tại runtime
```java
ThreadMXBean tmxBean = ManagementFactory.getThreadMXBean();
long[] deadlockedThreads = tmxBean.findDeadlockedThreads();
if (deadlockedThreads != null) {
    ThreadInfo[] infos = tmxBean.getThreadInfo(deadlockedThreads, true, true);
    // log stack traces, alert
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Java I/O & NIO** (deep dive)
>
> Keyword: InputStream/OutputStream hierarchy, Reader/Writer, Buffering, NIO channels (FileChannel, SocketChannel), ByteBuffer (flip, clear, compact), Selector (non-blocking IO multiplexing), NIO.2 (Path, Files, WatchService), AsynchronousFileChannel, Memory-mapped files
