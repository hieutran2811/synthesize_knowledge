---
title: "Concurrency & Multithreading (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Concurrency & Multithreading (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Concurrency & Multithreading là gì?

- **Concurrency** *(tính đồng thời)*: nhiều task cùng tiến triển trong một khoảng thời gian, nhưng không nhất thiết chạy đúng cùng một thời điểm.
- **Parallelism** *(tính song song)*: nhiều task thực sự chạy cùng lúc, thường trên nhiều CPU core.
- **Thread** *(luồng thực thi)*: một đường thực thi trong chương trình Java. Các thread trong cùng process chia sẻ heap nhưng mỗi thread có stack và trạng thái thực thi riêng.

> 💡 **Giải thích dễ hiểu — concurrency là xoay việc, parallelism là thêm người:**
> Một đầu bếp có thể luân phiên nấu ba món trong lúc chờ nước sôi: đó là concurrency. Ba đầu bếp cùng nấu ba món tại một thời điểm là parallelism. Multithreading tạo ra nhiều “đầu bếp”, còn phần cứng và bộ lập lịch quyết định bao nhiêu người thật sự làm việc song song.

**Tại sao cần?**
- Tận dụng multi-core CPU
- Responsive UI: giữ UI thread không bị chặn lâu.
- I/O-bound *(tác vụ dành phần lớn thời gian chờ vào/ra)*: trong lúc chờ mạng, đĩa hoặc database, tài nguyên thực thi có thể xử lý việc khác.
- Throughput *(thông lượng)*: xử lý được nhiều request hơn trong một đơn vị thời gian.

---

## How – Thread Lifecycle

```text
NEW --start()----------------------------------------------------> RUNNABLE
RUNNABLE --chờ lấy monitor--> BLOCKED --lấy được monitor--------> RUNNABLE
RUNNABLE --wait/join/park----> WAITING --notify/unpark/task xong-> RUNNABLE
RUNNABLE --sleep/wait(n)-----> TIMED_WAITING --timeout/sự kiện---> RUNNABLE
RUNNABLE --run() kết thúc----------------------------------------> TERMINATED
```

Các trạng thái không tạo thành một chuỗi bắt buộc. Thread có thể chuyển qua lại nhiều lần giữa `RUNNABLE` và các trạng thái chờ trước khi kết thúc.

| State | Mô tả |
|-------|-------|
| `NEW` | Thread đã tạo nhưng chưa `start()` |
| `RUNNABLE` | Đang chạy hoặc ready chờ CPU scheduler |
| `BLOCKED` | Chờ acquire intrinsic lock (synchronized) |
| `WAITING` | Chờ vô thời hạn (`wait()`, `join()`, `park()`) |
| `TIMED_WAITING` | Chờ có timeout (`sleep(n)`, `wait(n)`, `join(n)`) |
| `TERMINATED` | `run()` đã kết thúc |

> 💡 **Giải thích dễ hiểu — trạng thái thread giống trạng thái của một nhân viên:**
> `RUNNABLE` gồm cả lúc đang được CPU phục vụ và lúc đã sẵn sàng nhưng còn xếp hàng. `BLOCKED` chỉ là đang chờ cửa có monitor của `synchronized`; chờ một `ReentrantLock` không nhất thiết được JVM báo là `BLOCKED`. Vì trạng thái có thể đổi ngay sau khi quan sát, `getState()` phù hợp cho chẩn đoán hơn là điều phối logic nghiệp vụ.

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

### Cách 3: Callable *(tác vụ trả kết quả)* + Future *(kết quả sẽ có)*
```java
Callable<Integer> callable = () -> {
    Thread.sleep(1000);
    return 42;
};

ExecutorService executor = Executors.newSingleThreadExecutor();
Future<Integer> future = executor.submit(callable);

// future.get() BLOCK cho đến khi xong
try {
    Integer result = future.get(5, TimeUnit.SECONDS); // chờ tối đa 5 giây
    use(result);
} catch (TimeoutException e) {
    boolean cancellationRequested = future.cancel(true);
    // true: yêu cầu cancel đã được chấp nhận; task phải hợp tác với interrupt.
}
future.isDone();
future.isCancelled();

executor.shutdown();
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
if (!done) {
    List<Runnable> neverStarted = executor.shutdownNow();
    // Cố gắng interrupt task đang chạy và trả về task chưa bắt đầu.
}
```

> 💡 **Giải thích dễ hiểu — hãy giao việc cho pool, đừng tự tuyển thread cho từng đơn hàng:**
> `ExecutorService` tách “việc cần làm” khỏi “thread nào làm việc đó”, giống quầy điều phối phân đơn cho một nhóm nhân viên dùng lại. Pool vẫn phải có giới hạn và chính sách từ chối phù hợp; nếu hàng đợi hoặc số thread tăng vô hạn, hệ thống chỉ dời điểm nghẽn sang bộ nhớ và scheduler. Capacity hữu hạn còn tạo **backpressure** *(phản áp, buộc bên gửi chậm lại khi bên nhận quá tải)*.

### Interruption *(ngắt có hợp tác)* – Yêu cầu dừng

`interrupt()` không cưỡng bức giết thread. Nó đặt interruption flag; một số lệnh chờ như `sleep()`, `wait()`, `join()` và nhiều API blocking sẽ ném `InterruptedException` rồi xóa flag. Code không thể xử lý interruption tại tầng hiện tại thường phải truyền exception lên hoặc khôi phục cờ:

```java
try {
    blockingQueue.take();
} catch (InterruptedException e) {
    Thread.currentThread().interrupt(); // bảo toàn yêu cầu dừng
    return;
}
```

> 💡 **Giải thích dễ hiểu — interrupt là chuông báo đóng cửa, không phải kéo nhân viên ra ngoài:**
> Người quản lý phát tín hiệu “hãy dừng ở điểm an toàn”; worker phải nghe tín hiệu, dọn dẹp rồi thoát. Nếu task nuốt `InterruptedException` hoặc chạy vòng CPU mà không kiểm tra flag, `cancel(true)` và `shutdownNow()` cũng không bảo đảm nó dừng ngay.

---

## How – Synchronization

### Intrinsic Lock *(khóa nội tại)* (`synchronized`)

Mỗi Java object gắn với một intrinsic lock, còn gọi là **monitor** *(bộ giám sát khóa)*. Thread phải chiếm được monitor trước khi vào vùng `synchronized`; khi rời vùng này, lock được nhả kể cả khi có exception.

```java
public class Counter {
    private int count = 0;

    // Synchronized method: lock = this
    public synchronized void increment() { count++; }

    // Synchronized block: chỉ khóa đúng vùng dữ liệu cần bảo vệ
    private final Object lock = new Object();
    public void decrement() {
        synchronized (lock) { count--; }
    }

    // Static synchronized: lock = Counter.class
    public static synchronized void staticOp() { ... }
}
```

**Reentrant** *(tái nhập)*: cùng thread có thể acquire cùng lock nhiều lần mà không tự **deadlock** *(bế tắc do chờ tài nguyên vòng tròn)*:
```java
synchronized void outer() {
    synchronized (this) { // reentrant – cùng thread, OK
        inner();
    }
}
synchronized void inner() { /* ... */ }
```

> 💡 **Giải thích dễ hiểu — lock là chìa khóa phòng hồ sơ:**
> Nhiều nhân viên có thể làm việc bên ngoài, nhưng chỉ người giữ chìa khóa mới sửa hồ sơ dùng chung. `synchronized` không tự biết biến nào cần bảo vệ: mọi thao tác trên cùng một invariant phải thống nhất dùng đúng chiếc khóa, nếu không vẫn có **race condition** *(điều kiện tranh chấp do thứ tự chạy)*.

### volatile – Visibility Guarantee

`volatile` tạo quan hệ **happens-before** *(thứ tự bảo đảm quan sát trong Java Memory Model)*: một lần ghi vào biến `volatile` xảy ra trước các lần đọc biến đó về sau. Nhờ vậy:

1. **Visibility** *(khả năng nhìn thấy)*: thread đọc nhận được giá trị đã được publish, thay vì giữ một bản cũ không giới hạn.
2. **Ordering** *(thứ tự bộ nhớ)*: compiler và CPU bị hạn chế reorder các thao tác qua ranh giới đọc/ghi `volatile` theo quy tắc của Java Memory Model.

**KHÔNG đảm bảo atomicity** *(tính nguyên tử, không thể bị xen ngang)* cho compound operations (`i++` = read + add + write):

```java
public class StopFlag {
    private volatile boolean running = true; // visibility

    public void stop() { running = false; }  // write visible immediately

    public void run() {
        while (running) { doWork(); }        // đọc fresh value mỗi lần
    }
}

// SAI: volatile không đủ cho i++
volatile int count = 0;
count++; // NOT ATOMIC! race condition vẫn có thể xảy ra
```

> 💡 **Giải thích dễ hiểu — volatile là bảng thông báo, không phải quầy giao dịch:**
> Mọi người đều nhìn thấy thông báo mới nhất, nhưng hai người vẫn có thể cùng đọc “còn 1 vé” rồi đều bán vé đó. Dùng `volatile` cho cờ trạng thái độc lập là hợp lý; với đọc–sửa–ghi hoặc invariant gồm nhiều biến, cần atomic class hoặc lock.

### Atomic Classes (java.util.concurrent.atomic)

**CAS (Compare-And-Set/Swap)** *(so sánh rồi cập nhật có điều kiện)* cho phép cập nhật nguyên tử mà không giữ lock trong một số thuật toán:

```java
// AtomicInteger, AtomicLong, AtomicBoolean, AtomicReference
AtomicInteger counter = new AtomicInteger(0);
counter.incrementAndGet();           // i++ atomic
counter.getAndAdd(5);                // get rồi add
counter.compareAndSet(10, 20);       // CAS: nếu value==10 thì set=20, return true/false

AtomicReference<Node> head = new AtomicReference<>(null);
head.compareAndSet(null, newNode);   // lock-free linked list

// LongAdder – tối ưu cho counter có contention cao (Java 8+)
LongAdder adder = new LongAdder();
adder.increment(); // nhiều thread cộng vào cell riêng, tổng khi cần
long approximateSnapshot = adder.sum();
```

`LongAdder` thường có throughput ghi tốt hơn `AtomicLong` khi nhiều thread cạnh tranh, đổi lại `sum()` không phải một snapshot nguyên tử đối với các cập nhật đang diễn ra. CAS cũng chỉ làm nguyên tử thao tác trên giá trị đích; invariant trải trên nhiều biến vẫn cần thiết kế đồng bộ ở mức cao hơn.

> 💡 **Giải thích dễ hiểu — CAS giống sửa hồ sơ khi phiên bản chưa đổi:**
> Thread nói: “Nếu giá trị vẫn là 10 như lúc tôi đọc thì đổi thành 20”. Nếu người khác đã sửa trước, thao tác thất bại và thread có thể đọc lại rồi thử tiếp. Cách này tránh xếp hàng giữ chìa khóa, nhưng khi tranh chấp quá cao, việc thử lại cũng tiêu tốn CPU.

---

## How – Locks (java.util.concurrent.locks)

### ReentrantLock – Linh hoạt hơn synchronized

```java
ReentrantLock lock = new ReentrantLock(true); // fair=true: ưu tiên thread chờ lâu

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
if (lock.tryLock(5, TimeUnit.SECONDS)) {
    try { criticalSection(); }
    finally { lock.unlock(); }
}

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

Fair lock giảm nguy cơ một thread bị bỏ đói nhưng không bảo đảm lịch CPU FIFO tuyệt đối; nó cũng thường làm giảm throughput. Đặc biệt, `tryLock()` không timeout vẫn có thể giành lock ngay cả khi thread khác đang chờ.

> 💡 **Giải thích dễ hiểu — ReentrantLock là cửa có thêm chế độ vận hành:**
> `synchronized` giống cửa tự khóa/mở khi ra vào. `ReentrantLock` cho phép thử cửa, chờ có thời hạn, chia nhiều hàng chờ bằng `Condition` và bật fairness, nhưng người dùng phải luôn trả chìa khóa trong `finally`.

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

`ReadWriteLock` phù hợp khi đọc nhiều, ghi ít và vùng xử lý đủ lớn để lợi ích đọc song song bù được chi phí quản lý lock. Với critical section rất ngắn hoặc tần suất ghi đáng kể, `synchronized`/`ReentrantLock` đơn giản có thể nhanh hơn.

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

Phải đọc đủ các field trước rồi mới `validate(stamp)`; nếu validation thất bại, đọc lại toàn bộ dưới read lock. `StampedLock` không reentrant, stamp phải được mở khóa đúng mode và optimistic read chỉ an toàn khi caller không để dữ liệu tạm thời chưa nhất quán thoát ra ngoài.

> 💡 **Giải thích dễ hiểu — optimistic read là đọc nhanh rồi kiểm tra con dấu:**
> Bạn chép thông tin mà chưa khóa tủ, sau đó nhìn con dấu để biết có ai sửa tủ trong lúc mình chép hay không. Nếu con dấu đổi, phải khóa tủ và chép lại. Cách này có lợi khi ghi rất hiếm; nếu ghi liên tục, lần đọc nhanh thường xuyên bị làm lại.

---

## How – CompletableFuture (Java 8+)

`CompletableFuture` mô hình hóa một kết quả có thể xuất hiện trong tương lai và cho phép ghép **asynchronous pipeline** *(chuỗi xử lý bất đồng bộ)* mà không phải chặn thread điều phối ở từng bước:

```java
// Tạo
CompletableFuture<String> cf1 = CompletableFuture.supplyAsync(() -> fetchUser(id));
CompletableFuture<Void> cf2 = CompletableFuture.runAsync(() -> sendNotification());

// Transform (thenApply = map; stage có thể chạy trên thread hoàn tất cf1)
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

Các method không có hậu tố `Async` thường chạy action trên thread hoàn tất stage trước (hoặc thread gọi nếu stage đã hoàn tất). Biến thể `Async` không truyền executor thường dùng `ForkJoinPool.commonPool()`. Không nên đưa I/O chặn lâu vào common pool dùng chung; hãy truyền executor phù hợp. `join()` và `get()` vẫn chặn caller khi kết quả chưa sẵn sàng.

> 💡 **Giải thích dễ hiểu — CompletableFuture là dây chuyền phiếu hẹn:**
> Thay vì đứng tại quầy chờ hồ sơ, ta nhận phiếu và đăng ký “có hồ sơ thì kiểm tra, rồi gửi thông báo”. `thenCompose` nối một công việc bất đồng bộ phụ thuộc vào kết quả trước; `thenCombine` ghép hai nhánh độc lập. Dây chuyền chỉ thật sự không chặn khi bên trong các stage cũng không gọi chờ đồng bộ một cách tùy tiện.

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

boolean completed = latch.await(10, TimeUnit.SECONDS); // false nếu timeout
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

> 💡 **Giải thích dễ hiểu — latch là đồng hồ đếm ngược, barrier là điểm tập kết:**
> Với `CountDownLatch`, người chờ đi tiếp khi đủ N tín hiệu và đồng hồ không dùng lại được. Với `CyclicBarrier`, chính N worker phải gặp nhau ở từng checkpoint rồi cùng qua vòng tiếp theo; một worker timeout hoặc lỗi có thể làm barrier bị broken cho các worker còn lại.

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

Semaphore quản lý permit chứ không gắn quyền sở hữu permit với thread như lock. Vì vậy code phải chỉ `release()` sau khi `acquire()` thành công, nếu không có thể vô tình làm tăng sức chứa.

> 💡 **Giải thích dễ hiểu — semaphore là hộp vé vào cửa:**
> Database chỉ chịu được năm thao tác đồng thời thì phát năm vé. Có vé mới được vào và lúc ra phải trả vé. Nó giới hạn concurrency tại một tài nguyên; nếu mục tiêu là giới hạn số request theo thời gian, cần rate limiter có khái niệm thời gian chứ không chỉ semaphore.

---

## How – Concurrent Collections

```java
// ConcurrentHashMap – Map hỗ trợ truy cập đồng thời
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
BlockingQueue<Task> queue2 = new LinkedBlockingQueue<>(100); // nên đặt capacity
BlockingQueue<Task> queue3 = new PriorityBlockingQueue<>();  // priority, không giới hạn

queue.put(task);    // block nếu đầy
queue.take();       // block nếu trống
queue.offer(task, 1, TimeUnit.SECONDS); // với timeout

// ConcurrentLinkedQueue – lock-free FIFO
ConcurrentLinkedQueue<Task> clq = new ConcurrentLinkedQueue<>();
```

`ConcurrentHashMap` làm nguyên tử từng operation như `putIfAbsent`, `compute` và `merge`, nhưng một chuỗi nhiều lệnh riêng lẻ không tự trở thành transaction. `CopyOnWriteArrayList` phù hợp khi đọc rất nhiều, ghi rất ít vì mỗi lần sửa phải sao chép mảng.

Constructor `new LinkedBlockingQueue<>()` mặc định dùng capacity `Integer.MAX_VALUE`, nên về thực tế không tạo backpressure trước khi bộ nhớ cạn. `PriorityBlockingQueue` cũng là queue không giới hạn: `put()` không chờ “đầy”; từ “blocking” ở đây chủ yếu có ý nghĩa đối với consumer gọi `take()` khi queue rỗng.

> 💡 **Giải thích dễ hiểu — concurrent collection bảo vệ từng giao dịch tại quầy:**
> `map.merge()` giống một giao dịch “đọc rồi cộng” được quầy xử lý trọn gói. Nhưng gọi `containsKey()` rồi `put()` là hai lượt riêng, nên người khác có thể chen vào giữa. Với queue, capacity hữu hạn là phòng chờ có số ghế rõ ràng; queue gần như vô hạn chỉ che giấu quá tải cho đến khi hết RAM.

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

> 💡 **Giải thích dễ hiểu — một dòng code chưa chắc là một bước nguyên tử:**
> Hai thu ngân cùng đọc doanh số 10, mỗi người cộng 1 rồi cùng ghi 11; kết quả đúng phải là 12 nhưng một cập nhật đã mất. Cần bảo vệ toàn bộ chuỗi đọc–sửa–ghi bằng cùng lock hoặc thay bằng operation nguyên tử phù hợp.

### Deadlock
```java
// Thread A: lock1 → chờ lock2
// Thread B: lock2 → chờ lock1 → DEADLOCK!
Object lock1 = new Object(), lock2 = new Object();

Runnable pause = () -> {
    try {
        Thread.sleep(100);
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
    }
};

Thread a = new Thread(() -> {
    synchronized (lock1) {
        pause.run(); // giả lập work
        synchronized (lock2) { /* ... */ }
    }
});
Thread b = new Thread(() -> {
    synchronized (lock2) {
        pause.run();
        synchronized (lock1) { /* ... */ } // deadlock!
    }
});

// Giải pháp:
// 1. Luôn acquire lock theo CÙNG THỨ TỰ
// 2. Dùng tryLock() với timeout
// 3. Lock ordering: lock với ID nhỏ hơn trước
```

> 💡 **Giải thích dễ hiểu — deadlock là hai người giữ nửa bộ chìa khóa:**
> A giữ khóa kho và chờ khóa xe; B giữ khóa xe và chờ khóa kho. Không ai chịu thả khóa đang giữ nên hệ thống đứng yên. Quy ước mọi nơi lấy khóa theo cùng thứ tự sẽ phá vòng chờ này.

### Livelock
```java
// Thread A và B đều nhường nhau liên tục → không ai tiến được
// (giống 2 người tránh nhau trong hành lang mãi không đi được)
// Fix: random backoff trước khi retry
```

### Starvation
```java
// Một thread liên tục thua khi tranh tài nguyên nên rất lâu không tiến triển.
// Fair lock có thể giảm starvation do tranh lock, nhưng không bảo đảm lịch CPU.
```

---

## When – Chọn công cụ nào?

| Tình huống | Dùng |
|-----------|------|
| Đơn giản, 1-2 thread | `synchronized` |
| Cần tryLock, fairness | `ReentrantLock` |
| Read nhiều, write ít | `ReadWriteLock` |
| Counter contention cao, chủ yếu lấy tổng thống kê | `LongAdder` |
| Counter cần giá trị cập nhật nguyên tử chính xác | `AtomicLong` |
| Task đơn giản async | `CompletableFuture` |
| I/O-bound tasks | Pool có giới hạn được đo theo tải, hoặc virtual-thread-per-task trên JDK phù hợp |
| CPU-bound tasks | `ForkJoinPool`, parallel stream |
| Producer-consumer | `BlockingQueue` |
| Chờ N task hoàn thành | `CountDownLatch` |
| N thread chờ nhau | `CyclicBarrier` |
| Giới hạn số thao tác đồng thời | `Semaphore` |

> 💡 **Giải thích dễ hiểu — chọn giới hạn theo tài nguyên khan hiếm:**
> CPU-bound thường giới hạn gần số core; I/O-bound có thể cho nhiều task hơn vì phần lớn thời gian là chờ, nhưng vẫn phải xét connection pool, RAM và downstream. `newCachedThreadPool()` có thể tạo thread gần như không giới hạn, nên không phải mặc định an toàn cho mọi workload I/O.

---

## Compare – Synchronization Approaches

Không có lựa chọn “nhanh nhất” độc lập với tỷ lệ đọc/ghi, mức contention, kích thước critical section và phiên bản JVM. Hãy benchmark bằng workload gần production.

| Approach | Phù hợp khi | Giới hạn chính |
|----------|--------------|----------------|
| `synchronized` | Vùng critical đơn giản, cần tự động nhả lock | Không có timeout hay nhiều condition |
| `volatile` | Publish cờ/trạng thái độc lập | Không bảo vệ compound operation |
| `AtomicXxx` | Cập nhật nguyên tử trên một giá trị | Retry CAS có thể tốn CPU khi contention cao |
| `ReentrantLock` | Cần timeout, interruptible lock hoặc `Condition` | Phải tự `unlock()` đúng cách |
| `ReadWriteLock` | Đọc nhiều, ghi ít, critical section đủ lớn | Quản lý phức tạp; ghi có thể làm giảm lợi ích |
| `StampedLock` | Optimistic read có xác suất validate thành công cao | Không reentrant, dễ dùng sai stamp/invariant |
| `ConcurrentHashMap` | Nhiều thread chia sẻ map | Nhiều method liên tiếp không tự thành transaction |

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

Với `ThreadPoolExecutor`, khi số core thread đã bận, task thường vào queue trước; pool chỉ tăng tới `maximumPoolSize` khi queue không nhận thêm. Queue hữu hạn kết hợp `CallerRunsPolicy` có thể tạo backpressure bằng cách bắt caller chậm lại, nhưng cần tránh chạy tác vụ dài trên thread nhạy cảm như UI/event loop.

> 💡 **Giải thích dễ hiểu — pool và queue là bếp cùng kệ đơn:**
> Bốn đầu bếp chính xử lý đơn; kệ chứa tối đa 100 đơn. Khi kệ đầy, bếp có thể gọi thêm người tới giới hạn tám. Nếu vẫn quá tải, `CallerRunsPolicy` buộc người nhận đơn tự nấu, làm tốc độ nhận đơn chậm lại thay vì chất đơn vô hạn.

### 2. Async Service với CompletableFuture
```java
@Service
public class DashboardService {
    private final Executor io;

    public DashboardService(Executor io) {
        this.io = io; // executor do application quản lý lifecycle và cấu hình
    }

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
            .orTimeout(10, TimeUnit.SECONDS)
            .join();
    }
}
```

`orTimeout()` làm future tổng hoàn tất với `TimeoutException`, nhưng không tự hủy các tác vụ con đang chạy. Production code còn phải quy định cancellation, retry và fallback theo idempotency của từng lời gọi; `join()` bọc lỗi trong `CompletionException` để tầng trên xử lý.

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
