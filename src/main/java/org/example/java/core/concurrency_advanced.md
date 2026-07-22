# Concurrency Advanced – Fork/Join, Lock-free, Patterns

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Advanced Concurrency giải quyết điều gì?

Các công cụ **advanced concurrency** *(lập trình đồng thời nâng cao)* giải quyết ba nhóm vấn đề: chia công việc CPU để chạy song song, phối hợp nhiều luồng mà không tạo vòng chờ, và truyền hoặc công bố trạng thái giữa các luồng một cách an toàn. Không có công cụ “nhanh nhất” cho mọi tình huống; lựa chọn đúng phụ thuộc **workload** *(dạng tải thực tế)*, mức **contention** *(tranh chấp tài nguyên)* và yêu cầu về tính đúng đắn.

**Concurrency primitive** *(công cụ phối hợp đồng thời cấp thấp)* như CAS, barrier hay semaphore là các khối xây dựng. Pattern cấp cao như immutable state, thread confinement và asynchronous pipeline giúp ghép chúng thành thiết kế dễ kiểm soát hơn.

> 💡 **Giải thích dễ hiểu:**
> Đây là hộp dụng cụ điều phối một đội đông người: có dụng cụ chia việc, điểm danh ở từng chặng, giới hạn số người vào phòng và cách thay bảng thông báo mà người đọc không thấy bản dở dang. Chọn sai dụng cụ vẫn có thể làm hệ thống chậm hoặc sai dù code không báo lỗi.

## How – Fork/Join Framework (Java 7+)

**Fork/Join** là mô hình **divide-and-conquer parallelism** *(song song hóa bằng cách chia để trị)*. Bài toán lớn được chia thành các **sub-task** *(tác vụ con)*, chạy song song rồi hợp nhất kết quả.

> 💡 **Giải thích dễ hiểu:**
> Hãy hình dung một đơn hàng lớn được chia cho nhiều nhân viên đóng gói. Mỗi người xử lý một phần, sau đó các phần được gom lại thành đơn hoàn chỉnh. Fork là “chia việc”, join là “chờ và ghép kết quả”.

### Work-Stealing Algorithm *(thuật toán đánh cắp công việc)*

Mỗi worker duy trì một **deque** *(hàng đợi hai đầu)* riêng:

```
ForkJoinPool có N worker threads, mỗi thread có deque riêng:

Thread-1 deque: [task4][task3][task2][task1]  ← push/pop từ đầu (LIFO)
Thread-2 deque: []  ← idle → steal từ đuôi của Thread-1 (FIFO)

Tại sao LIFO + steal FIFO?
- LIFO (local): cache locality tốt (sub-task vừa fork còn warm trong cache)
- Steal FIFO: lấy task cũ nhất; với bài toán chia đệ quy, đây thường là task thô hơn và còn nhiều việc hơn
- Tránh contention: producer push từ đầu, stealer steal từ đuôi (ít contention hơn)
```

> 💡 **Giải thích dễ hiểu:**
> Mỗi worker có một chồng việc riêng và ưu tiên việc mới nhất để tận dụng dữ liệu còn “nóng” trong CPU cache. Worker hết việc sẽ lấy từ đầu kia của hàng đợi đồng nghiệp, giống nhân viên rảnh lấy một thùng hàng lớn chưa ai xử lý mà ít va chạm với người đang thêm việc.

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
try {
    int[] customSorted = customPool.invoke(new MergeSortTask(array, 0, array.length));
} finally {
    customPool.shutdown(); // pool tự tạo phải có lifecycle rõ ràng
}
```

### RecursiveAction (không có kết quả)

```java
// Parallel array fill
class FillAction extends RecursiveAction {
    private static final int THRESHOLD = 10_000;
    private final double[] data;
    private final int from, to;
    private final double value;

    FillAction(double[] data, int from, int to, double value) {
        this.data = data;
        this.from = from;
        this.to = to;
        this.value = value;
    }

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
        ); // lên lịch hai action và chờ cả hai hoàn thành
    }
}
```

### Parallel Stream dùng ForkJoinPool

```java
// Parallel stream dùng ForkJoinPool.commonPool() mặc định
list.parallelStream().map(this::process).toList();

// Cách thường dùng trên OpenJDK để bao terminal operation trong custom pool
// Lưu ý: Stream API không có tham số pool riêng trong public contract
ForkJoinPool myPool = new ForkJoinPool(4);
List<Result> results;
try {
    results = myPool.submit(
        () -> list.parallelStream().map(this::process).toList()
    ).get();
} finally {
    myPool.shutdown();
}
```

Parallel stream phù hợp nhất với công việc **CPU-bound** *(bị giới hạn chủ yếu bởi năng lực CPU)*. Tác vụ blocking I/O kéo dài có thể giữ worker của pool và làm các tác vụ khác bị chậm. OpenJDK hiện thường thực thi terminal operation được bao như trên bằng pool bao quanh, nhưng Stream API không cam kết cách chọn pool. Nếu cần cô lập tài nguyên với contract rõ ràng, nên biểu diễn công việc trực tiếp bằng `ForkJoinTask` hoặc executor riêng.

> 💡 **Giải thích dễ hiểu:**
> `commonPool` giống một bếp chung của cả ứng dụng. Một món giữ đầu bếp để chờ mạng hoặc chờ đĩa sẽ khiến món của bộ phận khác bị xếp hàng; pool riêng tạo một nhóm nhân sự riêng, nhưng vẫn cần chọn đúng loại công việc cho nhóm đó.

---

## How – ThreadLocal (Deep Dive)

### Internals

```
ThreadLocal KHÔNG lưu value trong chính ThreadLocal object.
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

`ThreadLocal` cung cấp **thread confinement** *(giới hạn dữ liệu trong một thread)*: nhiều thread dùng cùng biến `ThreadLocal`, nhưng mỗi thread tra ra value riêng trong `ThreadLocalMap` của chính nó.

> 💡 **Giải thích dễ hiểu:**
> `ThreadLocal` giống dãy tủ cá nhân tại công ty. Tấm thẻ `ThreadLocal` giúp mỗi nhân viên mở đúng ngăn của mình; cùng một thẻ logic nhưng đồ trong từng ngăn không bị dùng chung.

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
// NGUY HIỂM: thread trong pool sống lâu → value có thể bị giữ lâu nếu không remove()!
ExecutorService pool = Executors.newFixedThreadPool(10);

ThreadLocal<byte[]> cache = new ThreadLocal<>();

pool.submit(() -> {
    cache.set(new byte[1024 * 1024]); // 1MB per thread
    doWork();
    // THIẾU: cache.remove() → 1MB tiếp tục bị giữ sau khi task đã xong!
});

// Pool 10 threads có thể giữ khoảng 10MB cho tới khi entry được dọn hoặc thread chết

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
// Nhưng VALUE là strong reference → value vẫn bị giữ khi entry chưa được dọn
// → Key trở thành null, entry trở thành stale entry (không phải phantom reference)
// Entry thường được dọn khi ThreadLocalMap thực hiện get/set/remove liên quan hoặc thread chết
```

> 💡 **Giải thích dễ hiểu:**
> Key yếu giống nhãn giấy có thể rơi khỏi ngăn tủ, nhưng đồ bên trong vẫn còn vì chiếc tủ (thread) vẫn tồn tại. `remove()` là thao tác chủ động dọn ngăn sau mỗi request, thay vì chờ một lần tra cứu tương lai tình cờ quét rác.

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

// Giải pháp thư viện: bọc task bằng TransmittableThreadLocal và luôn dọn context
// Ưu tiên đơn giản, rõ ownership: truyền context tường minh qua method parameters
```

`InheritableThreadLocal` sao chép entry tại thời điểm tạo child thread; mặc định parent và child vẫn tham chiếu cùng value object nếu value đó mutable. Nó không tự đồng bộ việc gán value khác về sau. Với thread pool, quan hệ “cha tạo con” không trùng với quan hệ “request gửi task”, nên context có thể thiếu hoặc thuộc request cũ.

---

## How – Lock-Free Programming *(lập trình không dùng khóa loại trừ)*

### CAS (Compare-And-Swap – so sánh và hoán đổi) Pattern

```java
// CAS = thao tác nguyên tử read-compare-write, không dùng explicit lock
// JVM thường ánh xạ xuống lệnh phần cứng phù hợp, ví dụ CMPXCHG trên x86

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

CAS chỉ ghi khi giá trị hiện tại vẫn bằng giá trị kỳ vọng. Nếu thread khác đã chen vào thay đổi dữ liệu, thao tác thất bại và vòng lặp tính lại; vì vậy không bị blocking do chờ lock, nhưng có thể tốn CPU khi tranh chấp cao.

> 💡 **Giải thích dễ hiểu:**
> CAS giống quầy đổi giá có điều kiện: “chỉ đổi nhãn 100 thành 101 nếu nhãn vẫn đang là 100”. Nếu người khác đã đổi trước, bạn đọc nhãn mới rồi thử lại thay vì đứng giữ chìa khóa khóa cả quầy.

### ABA Problem *(vấn đề trạng thái đổi rồi quay lại giá trị cũ)*

```java
// ABA: giá trị thay đổi A → B → A, CAS không phát hiện!
// Thread 1: đọc A, chuẩn bị CAS A → C
// Thread 2: đổi A → B → A (trong khi Thread 1 đang chuẩn bị)
// Thread 1: CAS thành công vì chỉ so sánh A, dù trạng thái đã trải qua thay đổi

// Classic example: lock-free stack
AtomicReference<Node> head = new AtomicReference<>(nodeA);
// Thread 1 muốn pop nodeA, đọc head = nodeA, next = nodeB
// Thread 2: pop nodeA, pop nodeB, push nodeA lại
// head = nodeA (same ref!) nhưng nodeA.next = null (nodeB đã bị pop)
// Thread 1: CAS head: nodeA → nodeB? Thành công!
// nodeB vẫn là object hợp lệ nhờ GC, nhưng đã bị loại khỏi stack về mặt logic
// → nodeB có thể bị đưa trở lại stack và làm sai lịch sử cập nhật

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

> 💡 **Giải thích dễ hiểu:**
> ABA giống nhân viên kiểm tra thấy con dấu “A” trước và sau giờ nghỉ nên tưởng hồ sơ chưa bị động tới, dù giữa hai lần kiểm tra hồ sơ đã qua B rồi quay lại A. Stamp đóng vai trò số phiên bản: cùng chữ A nhưng phiên bản khác thì CAS phải từ chối.

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

`Phaser` là **barrier linh hoạt** *(điểm đồng bộ nơi các thread chờ nhau)*, kết hợp ý tưởng của `CountDownLatch` và `CyclicBarrier`, đồng thời hỗ trợ nhiều phase và đăng ký/deregister party động.

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
    try {
        executor.submit(() -> {
            try {
                doWork();
            } finally {
                dynamicPhaser.arriveAndDeregister();
            }
        });
    } catch (RejectedExecutionException e) {
        dynamicPhaser.arriveAndDeregister(); // hoàn tác register nếu submit thất bại
        throw e;
    }
}
dynamicPhaser.arriveAndAwaitAdvance(); // main chờ tất cả

// Tiered Phaser (tree structure cho nhiều threads)
Phaser root = new Phaser();
Phaser child1 = new Phaser(root, 100); // 100 threads trong group 1
Phaser child2 = new Phaser(root, 100); // 100 threads trong group 2
// child advances → khi cả child1 và child2 advance → root advances
```

> 💡 **Giải thích dễ hiểu:**
> Phaser giống một chuyến tham quan có nhiều chặng. Cả nhóm phải tập hợp đủ ở mỗi trạm mới đi tiếp, nhưng thành viên có thể đăng ký tham gia hoặc rời đoàn ở các chặng hợp lệ.

---

## How – Exchanger

`Exchanger` là điểm hẹn để đúng hai thread trao đổi object; mỗi bên chờ cho đến khi bên còn lại cũng gọi `exchange()`.

```java
Exchanger<DataBuffer> exchanger = new Exchanger<>();

// Producer thread: fill buffer rồi đổi lấy empty buffer
Thread producer = new Thread(() -> {
    DataBuffer filledBuffer = new DataBuffer();
    try {
        while (!Thread.currentThread().isInterrupted()) {
            fillBuffer(filledBuffer);
            filledBuffer = exchanger.exchange(filledBuffer); // nhận buffer rỗng
        }
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
    }
});

// Consumer thread: lấy filled buffer, đổi lại empty buffer
Thread consumer = new Thread(() -> {
    DataBuffer emptyBuffer = new DataBuffer();
    try {
        while (!Thread.currentThread().isInterrupted()) {
            DataBuffer filledBuffer = exchanger.exchange(emptyBuffer);
            consume(filledBuffer);
            emptyBuffer = filledBuffer; // trả buffer này ở vòng sau
        }
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
    }
});

producer.start();
consumer.start();

// Dùng khi: double buffering, pipeline handoff giữa 2 threads
```

> 💡 **Giải thích dễ hiểu:**
> Hai thread giống hai người gặp nhau giữa cầu để đổi giỏ: producer đưa giỏ đầy và nhận giỏ rỗng; consumer làm ngược lại. Nếu một người không tới, người kia phải chờ hoặc dùng overload có timeout.

---

## How – Advanced CompletableFuture

```java
// Timeout (Java 9+)
CompletableFuture<String> future = fetchDataAsync()
    .orTimeout(5, TimeUnit.SECONDS); // throw TimeoutException sau 5s

CompletableFuture<String> withDefault = fetchDataAsync()
    .completeOnTimeout("default-value", 5, TimeUnit.SECONDS); // trả về default nếu timeout

// Delay (Java 9+)
Executor delayedExecutor = CompletableFuture.delayedExecutor(1, TimeUnit.SECONDS);
CompletableFuture<String> delayed =
    CompletableFuture.supplyAsync(() -> "result", delayedExecutor); // bắt đầu sau 1s

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

`orTimeout()` và `completeOnTimeout()` hoàn tất chính `CompletableFuture` theo hai cách khác nhau, nhưng không đảm bảo hủy computation hoặc I/O đang chạy bên dưới. Muốn giải phóng tài nguyên thật sự, tác vụ cần hỗ trợ cancellation, deadline hoặc timeout ở HTTP/database client.

> 💡 **Giải thích dễ hiểu:**
> Timeout của future giống việc khách ngừng chờ và nhận thông báo “quá giờ”; điều đó không có nghĩa nhà bếp đã tự dừng nấu. Cần truyền timeout xuống nơi thực hiện công việc nếu muốn ngừng tiêu tốn tài nguyên.

---

## How – Flow API (Reactive Streams, Java 9+)

```java
// Flow.Publisher, Flow.Subscriber, Flow.Subscription, Flow.Processor

// Publisher tối giản để học protocol; phát đồng bộ, không dành cho production
public class RangePublisher implements Flow.Publisher<Integer> {
    private final int from, to;
    RangePublisher(int from, int to) { this.from = from; this.to = to; }

    @Override
    public void subscribe(Flow.Subscriber<? super Integer> subscriber) {
        subscriber.onSubscribe(new Flow.Subscription() {
            private int current = from;
            private boolean cancelled;
            private boolean done;

            @Override
            public synchronized void request(long n) {
                if (cancelled || done) return;
                if (n <= 0) {
                    done = true;
                    subscriber.onError(new IllegalArgumentException("n must be > 0"));
                    return;
                }
                for (long i = 0; i < n && current < to && !cancelled && !done; i++) {
                    subscriber.onNext(current++);
                }
                if (current >= to && !cancelled && !done) {
                    done = true;
                    subscriber.onComplete();
                }
            }

            @Override
            public synchronized void cancel() { cancelled = true; }
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

**Backpressure** *(điều tiết tốc độ từ bên nhận)* nằm ở `Subscription.request(n)`: subscriber chỉ cấp “hạn mức” số item publisher được phép gửi. Publisher production còn phải xử lý request đồng thời hoặc reentrant, nhu cầu cộng dồn, overflow, exception và quy tắc phát signal tuần tự; thường nên dùng thư viện Reactive Streams thay vì tự cài đặt.

> 💡 **Giải thích dễ hiểu:**
> Subscriber giống kho hàng báo “tôi còn chỗ cho một kiện”. Publisher chỉ giao đúng số kiện đã được yêu cầu, nhờ vậy kho chậm không bị xe tải đổ hàng vô hạn trước cửa.

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

// Stack confinement: reference cục bộ không escape khỏi method/thread hiện tại
public void doWork() {
    List<String> localList = new ArrayList<>(); // object thường ở heap, nhưng không bị chia sẻ
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

> 💡 **Giải thích dễ hiểu:**
> Dữ liệu không được chia sẻ thì không cần tranh khóa. Nó giống một bản nháp chỉ nằm trên bàn của một nhân viên; chỉ khi chuyền bản nháp cho người khác mới phải đặt quy tắc phối hợp.

### 3. Safe Publication Patterns

```java
// Bốn mục dưới đây là các cách publication độc lập, không bắt buộc kết hợp.
// 1. Static initializer (JVM thread-safe)
public static final Singleton INSTANCE = new Singleton();

// 2. volatile: publish bằng volatile write, đọc bằng volatile read
private volatile Config config;

// 3. final field + immutable object, khởi tạo đầy đủ trong constructor
final class Holder {
    private final Map<String, String> data;

    Holder(Map<String, String> source) {
        this.data = Map.copyOf(source);
    }
}

// 4. synchronized publication
private Config synchronizedConfig;
private synchronized void setConfig(Config c) { this.synchronizedConfig = c; }
private synchronized Config getConfig() { return this.synchronizedConfig; }
```

`final` bảo đảm reference không bị gán lại và có ngữ nghĩa khởi tạo an toàn cho final field; nó không tự làm object được tham chiếu trở thành immutable. Vì vậy ví dụ dùng `Map.copyOf()` để không công bố một `Map` mutable ra ngoài.

### 4. Immutable Object + Volatile Reference Pattern

```java
// Copy-on-write immutable config (common in Spring, Guava)
public class ConfigManager {
    private volatile Config current = Config.defaults(); // immutable object

    public Config getConfig() {
        return current; // safe: volatile read, Config is immutable
    }

    public synchronized void updateConfig(String key, String value) {
        // Create new immutable config with change
        Config newConfig = current.withChange(key, value); // returns new Config
        current = newConfig; // volatile write
        // Reader không cần lock; synchronized tránh lost update giữa nhiều writer
    }
}
```

> 💡 **Giải thích dễ hiểu:**
> `volatile` giống bảng thông báo được thay nguyên tờ: người đọc luôn thấy tờ cũ hoặc tờ mới hoàn chỉnh. Nhưng hai người cùng sửa từ một bản cũ có thể dán đè nhau, nên writer phải khóa hoặc cập nhật bằng CAS.

---

## How – Deadlock Prevention Strategies

```java
// 1. Lock Ordering (canonical order)
// Luôn acquire lock theo một ID duy nhất và ổn định
public void transfer(Account from, Account to, BigDecimal amount) {
    if (from == to) return;
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
public boolean transfer(Account from, Account to, BigDecimal amount)
        throws InterruptedException {
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
        Thread.sleep(ThreadLocalRandom.current().nextLong(1, 10)); // backoff có jitter
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

Lock ordering chỉ an toàn khi khóa có khóa sắp xếp duy nhất; dùng `hashCode()` có thể đụng độ và ID trùng nhau cũng cần tie-breaker. `tryLock()` giúp thoát khi không lấy đủ lock, nhưng retry đồng nhịp vẫn có thể gây **livelock** *(các thread vẫn chạy nhưng liên tục nhường nhau nên không tiến triển)*; backoff có jitter giúp giảm rủi ro này.

> 💡 **Giải thích dễ hiểu:**
> Nếu mọi người luôn lấy chìa khóa phòng A trước phòng B thì không tạo vòng chờ A↔B. Khi không lấy đủ chìa khóa, họ trả lại và thử sau; nên chờ lệch nhau một chút để tránh cả hai cứ cùng lấy rồi cùng trả mãi.

---

## Components – Concurrency Tools Summary

| Tool | Use case | Key feature |
|------|---------|-------------|
| `synchronized` | Simple critical section | Reentrant, JVM native |
| `ReentrantLock` | Advanced locking (timeout, fair) | Condition variables |
| `ReadWriteLock` | Read-heavy, write-rare | Multiple concurrent readers |
| `StampedLock` | Optimistic read | Có thể giảm chi phí ở tải read-mostly; phải validate |
| `AtomicXxx` | Atomic update cho một trạng thái nhỏ | CAS, không dùng explicit lock |
| `LongAdder` | High-contention counter | Stripe-based, low contention |
| `ThreadLocal` | Per-thread state | No sharing needed |
| `ForkJoinPool` | CPU-bound divide-conquer | Work-stealing |
| `CompletableFuture` | Async pipelines | Composition không bắt buộc block; task vẫn có thể block |
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
| Coarse lock | Thường thấp khi contention cao | Có thể cao | Low | Giảm song song; vẫn có thể deadlock với lock khác |
| Fine-grained lock | Có thể cao | Thường thấp hơn | High | Deadlock, livelock |
| Lock-free (CAS) | Cao khi retry ít | Thấp khi contention thấp | Very high | ABA, starvation, retry storm |
| STM (via libraries) | Medium | Medium | Medium | Not JDK built-in |
| Actor model | High | Medium | Medium | Library needed |

Các mức throughput và latency chỉ mang tính định hướng. Kết quả thực tế phụ thuộc contention, kích thước critical section, số core, allocation và workload; lock-free không mặc nhiên nhanh hơn lock.

---

## Real-world Usage (Production)

### 1. ForkJoin: Parallel Report Generation

```java
@Service
public class ReportService {
    private final ForkJoinPool reportPool = new ForkJoinPool(
        Math.max(1, Runtime.getRuntime().availableProcessors() / 2)
        // Giới hạn độ song song của report; không "giữ riêng" core vật lý
    );

    @PreDestroy
    void shutdownPool() {
        reportPool.shutdown();
    }

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
    // Bucket đơn giản: cấp tối đa 100 token sau mỗi nhịp 1 giây
    private final Semaphore rateBucket = new Semaphore(100);

    @Scheduled(fixedRate = 1000)
    public synchronized void refillBucket() { // tránh hai lần refill chạy chồng nhau
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

Đây là bộ giới hạn theo nhịp refill đơn giản, gần **token bucket** *(xô token)* hơn leaky bucket. Nó cho phép burst và có thể chấp nhận gần 200 request trong một khoảng rất ngắn nằm hai phía của thời điểm refill; nếu cần rolling-window chính xác hoặc chạy nhiều instance, nên dùng rate limiter chuyên dụng với kho trạng thái dùng chung.

> 💡 **Giải thích dễ hiểu:**
> Mỗi request phải lấy một vé trong hộp 100 vé, hết vé thì chờ hoặc bị từ chối. Mỗi giây hộp được bù đầy; vì vậy khách đến sát trước và sát sau lúc bù vé có thể tạo một đợt đông ngắn.

---

## Ghi chú – Chủ đề liên quan

> Xem thêm:
> - **java_memory_model.md**: happens-before, volatile, safe publication (nền tảng lý thuyết)
> - **virtual_threads.md**: Project Loom thay thế thread pool cho IO-bound
> - **collections_internals.md**: ConcurrentHashMap, BlockingQueue internals
