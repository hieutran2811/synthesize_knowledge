# Java Memory Model (JMM)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Java Memory Model là gì?

**Java Memory Model (JMM)** định nghĩa **quy tắc** về cách JVM và CPU có thể **sắp xếp lại** (reorder) các thao tác đọc/ghi bộ nhớ, và đảm bảo **visibility** (khả năng nhìn thấy thay đổi) giữa các threads.

**Vấn đề cốt lõi**: CPU hiện đại có nhiều levels of cache (L1/L2/L3). Mỗi core có cache riêng. Write của một thread có thể nằm trong cache và **chưa visible** với thread khác trên core khác.

```
Thread A (Core 1)          Thread B (Core 2)
  L1 Cache                   L1 Cache
    x = 1 (only in cache)      read x → sees 0 (stale!)
       ↕                          ↕
  L2/L3 Cache (shared)
       ↕
  Main Memory (x = 0)

→ CPU cache coherency không đảm bảo immediate visibility across cores!
→ JMM định nghĩa KHAI BÁO ĐẢM BẢO nào tồn tại
```

---

## How – Happens-Before (HB) Relationship

**Happens-before** là mối quan hệ đảm bảo: nếu action A happens-before action B, thì **tất cả effects của A visible với B**.

### Happens-Before Rules (JSR-133)

```
1. Program Order Rule:
   Trong cùng 1 thread, statement trước HB statement sau.

2. Monitor Lock Rule:
   unlock(m) HB lock(m) tiếp theo trên cùng monitor m
   → synchronized đảm bảo visibility

3. Volatile Variable Rule:
   write(v) HB read(v) tiếp theo của volatile variable v
   → volatile write flush tới memory, volatile read load từ memory

4. Thread Start Rule:
   Thread.start() HB mọi action trong thread đó

5. Thread Termination Rule:
   Mọi action trong thread HB Thread.join() trả về

6. Transitivity:
   Nếu A HB B và B HB C thì A HB C

7. Interruption Rule:
   Thread.interrupt() HB code phát hiện interruption

8. Finalizer Rule:
   Constructor completion HB finalize() bắt đầu

9. Object Initialization:
   Static initializer HB bất kỳ action nào sau class load
```

---

## How – Visibility Problem

```java
// BROKEN: không có synchronization
public class VisibilityBug {
    boolean ready = false;   // non-volatile
    int number = 0;          // non-volatile

    // Thread 1 (writer)
    public void writer() {
        number = 42;
        ready = true;
    }

    // Thread 2 (reader) – chạy song song với writer
    public void reader() {
        while (!ready) { /* spin */ }
        // KHÔNG ĐẢM BẢO thấy number = 42!
        // Lý do 1: CPU cache – write của Thread 1 chưa flush về main memory
        // Lý do 2: Reordering – compiler/CPU có thể reorder: ready=true trước number=42
        System.out.println(number); // Có thể in 0!
    }
}
```

---

## How – volatile

`volatile` đảm bảo 2 điều:
1. **Visibility**: mọi write flush về main memory ngay lập tức; mọi read load từ main memory
2. **Ordering**: không reorder write/read của volatile với các operations xung quanh (memory barrier)

```java
public class VolatileDemo {
    volatile boolean ready = false;
    int number = 0;

    // Thread 1 (writer)
    public void writer() {
        number = 42;        // write trước
        ready = true;       // volatile write → memory barrier HERE
        // Memory barrier đảm bảo: number=42 visible TRƯỚC ready=true
        // JMM: write ready=true HB read ready=true
        // Và theo transitivity: write number=42 HB read number
    }

    // Thread 2 (reader)
    public void reader() {
        while (!ready) { /* spin */ }  // volatile read → memory barrier
        // Tại đây: đảm bảo thấy number = 42
        System.out.println(number); // LUÔN in 42
    }
}
```

### volatile KHÔNG đảm bảo atomicity

```java
volatile int counter = 0;

// Thread 1         Thread 2
counter++;          counter++;
// counter++ = READ + INCREMENT + WRITE (3 steps, không atomic!)

// Cả 2 thread cùng read 0 → cả 2 write 1 → kết quả 1 thay vì 2
// Fix: AtomicInteger.incrementAndGet() hoặc synchronized

// volatile CHỈ atomic cho:
// - 64-bit read/write (long/double): JVM đảm bảo atomic nếu volatile
// - reference read/write: always atomic (32/64 bit pointer)
```

### Khi nào volatile đủ?

```java
// volatile ĐỦ khi:
// - Chỉ 1 thread write, nhiều thread read
// - Value không phụ thuộc vào previous value (không có read-modify-write)

volatile boolean shutdownRequested = false;

// Thread pool:
public void shutdown() {
    shutdownRequested = true; // single write
}

// Worker threads:
while (!shutdownRequested) {
    doWork();
}
// OK! Chỉ 1 writer, nhiều readers, không cần previous value
```

---

## How – synchronized (Monitor Lock)

`synchronized` đảm bảo:
1. **Mutual exclusion**: chỉ 1 thread trong block tại một thời điểm
2. **Visibility**: khi thread release lock, tất cả writes **flush về main memory**; khi acquire lock, đọc lại từ main memory

```java
public class Counter {
    private int value = 0;         // không cần volatile khi có synchronized

    public synchronized void increment() {
        value++;  // atomic under lock
        // Khi release lock → value flush về main memory
    }

    public synchronized int get() {
        // Khi acquire lock → read value từ main memory
        return value;
    }
}

// Lock semantics:
// unlock HB (happens-before) lock tiếp theo trên cùng object
// → visibility đảm bảo giữa các synchronized blocks trên cùng monitor
```

---

## How – Reordering: Compiler + CPU

```java
// Source code (program order):
int a = 1;
int b = 2;
int c = a + b;

// Compiler/CPU có thể reorder thành:
int b = 2;    // swap order (không ảnh hưởng single-thread behavior)
int a = 1;
int c = a + b;

// Trong single thread: KHÔNG thành vấn đề (kết quả giống nhau)
// Trong multi-thread: CÓ THỂ gây bug nếu thread khác thấy intermediate state

// CPU cũng có "store buffer" và "invalid queue":
// - Store buffer: pending writes chưa commit
// - Invalid queue: pending cache line invalidations
// → Gây ra visibility lag giữa threads
```

### Memory Barriers (Fences)

```java
// JVM insert memory barriers khi cần:
// StoreStore barrier: đảm bảo stores trước barrier visible trước stores sau
// LoadLoad barrier: đảm bảo loads trước thực hiện trước loads sau
// StoreLoad barrier: đảm bảo store trước visible trước load sau (đắt nhất)
// LoadStore barrier: đảm bảo load trước xong trước store sau

// volatile write: insert [StoreStore] trước + [StoreLoad] sau
// volatile read: insert [LoadLoad] sau + [LoadStore] sau
// synchronized enter: insert [LoadLoad] + [LoadStore] sau acquire
// synchronized exit: insert [StoreStore] + [StoreLoad] trước release

// Programmatic fence (Java 9+):
VarHandle.fullFence();   // StoreLoad
VarHandle.acquireFence(); // LoadLoad + LoadStore
VarHandle.releaseFence(); // StoreStore + LoadStore
```

---

## How – Safe Publication

**Safe publication**: làm cho object được chia sẻ với thread khác một cách an toàn (không thấy partially-constructed state).

```java
// UNSAFE publication: thread có thể thấy object chưa hoàn toàn khởi tạo
public class UnsafePublication {
    public static Object instance;  // non-volatile, non-synchronized

    public void publish() {
        instance = new Object(); // UNSAFE!
        // JMM: write đến fields của Object và write đến instance pointer
        // có thể bị reorder → another thread thấy instance != null
        // nhưng nội dung object chưa hoàn toàn initialized!
    }
}
```

### 5 Cách Safe Publication

```java
// 1. Static initializer (thread-safe by JLS)
public class SafeStatic {
    public static final Object instance = new Object(); // JVM đảm bảo safe init
    // static initializer chạy trong synchronized block (class loading lock)
}

// 2. volatile field
public class SafeVolatile {
    private volatile Object instance;
    public void publish(Object obj) { instance = obj; }
    public Object read() { return instance; } // always sees complete object
}

// 3. synchronized setter/getter
public class SafeSynchronized {
    private Object instance;
    public synchronized void publish(Object obj) { instance = obj; }
    public synchronized Object read() { return instance; }
}

// 4. AtomicReference
public class SafeAtomic {
    private final AtomicReference<Object> ref = new AtomicReference<>();
    public void publish(Object obj) { ref.set(obj); }
    public Object read() { return ref.get(); }
}

// 5. Concurrent collections (thread-safe by design)
ConcurrentHashMap<String, Object> map = new ConcurrentHashMap<>();
map.put("key", new Object()); // safe publication via concurrent collection
// Thread đọc từ map đảm bảo thấy fully initialized object
```

---

## How – Double-Checked Locking (DCL)

Classic Singleton với DCL — **cần `volatile`**:

```java
// BROKEN (trước Java 5 / không có volatile)
public class BrokenSingleton {
    private static BrokenSingleton instance;

    public static BrokenSingleton getInstance() {
        if (instance == null) {                  // Check 1
            synchronized (BrokenSingleton.class) {
                if (instance == null) {           // Check 2
                    instance = new BrokenSingleton(); // UNSAFE!
                    // Constructor = 3 steps:
                    // 1. Allocate memory
                    // 2. Initialize fields (write to allocated memory)
                    // 3. Assign to instance pointer
                    // CPU có thể reorder: 1 → 3 → 2
                    // → Thread B thấy instance != null nhưng object chưa init!
                }
            }
        }
        return instance;
    }
}

// CORRECT: volatile prevents reordering
public class CorrectSingleton {
    private static volatile CorrectSingleton instance; // volatile!

    public static CorrectSingleton getInstance() {
        if (instance == null) {                   // Check 1 (no lock)
            synchronized (CorrectSingleton.class) {
                if (instance == null) {            // Check 2 (with lock)
                    instance = new CorrectSingleton();
                    // volatile write: StoreStore barrier ensures object fully
                    // initialized before reference is published
                }
            }
        }
        return instance; // volatile read
    }
}

// BEST: Initialization-on-demand Holder (no volatile needed!)
public class HolderSingleton {
    private HolderSingleton() {}

    private static class Holder {
        // JVM: class initialization is synchronized
        // Holder loaded lazily (only when getInstance() first called)
        static final HolderSingleton INSTANCE = new HolderSingleton();
    }

    public static HolderSingleton getInstance() {
        return Holder.INSTANCE; // safe: class init HB static field read
    }
}
```

---

## How – Final Fields

`final` fields có đặc biệt trong JMM: **đảm bảo visibility sau constructor** mà không cần synchronized:

```java
public class FinalFieldSafety {
    private final int x;
    private final List<String> list;

    public FinalFieldSafety(int x) {
        this.x = x;
        this.list = new ArrayList<>();
        list.add("hello");
        // Constructor exit: JVM insert freeze action (write barrier)
        // → tất cả final field writes flush và visible TRƯỚC reference published
    }
}

// Thread A:
FinalFieldSafety obj = new FinalFieldSafety(42);
sharedRef = obj; // publish

// Thread B (sau khi thấy sharedRef != null):
System.out.println(sharedRef.x);    // GUARANTEED to see 42
System.out.println(sharedRef.list); // GUARANTEED to see initialized list
// Và cả nội dung list: list[0] = "hello" → guaranteed!

// LƯU Ý: guarantee chỉ cho final fields và reachable objects qua final fields
// Non-final fields trong constructor: KHÔNG đảm bảo!

// TRAP: Leaking 'this' trong constructor phá vỡ final guarantee
public class LeakThis {
    private final int value;
    public LeakThis(EventBus bus) {
        bus.publish(this); // BUG: 'this' escapes TRƯỚC constructor hoàn thành!
        this.value = 42;   // final field chưa assign!
        // Thread khác nhận event → thấy value = 0 (default)
    }
}
```

---

## How – VarHandle (Java 9+)

`VarHandle` thay thế `Unsafe` cho low-level memory operations với type safety:

```java
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

public class VarHandleDemo {
    private int value = 0;

    // VarHandle cho field "value"
    private static final VarHandle VALUE_HANDLE;
    static {
        try {
            VALUE_HANDLE = MethodHandles.lookup()
                .findVarHandle(VarHandleDemo.class, "value", int.class);
        } catch (ReflectiveOperationException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    // Plain read/write (like non-volatile)
    public int getPlain() { return (int) VALUE_HANDLE.get(this); }
    public void setPlain(int v) { VALUE_HANDLE.set(this, v); }

    // Volatile semantics
    public int getVolatile() { return (int) VALUE_HANDLE.getVolatile(this); }
    public void setVolatile(int v) { VALUE_HANDLE.setVolatile(this, v); }

    // Acquire/Release (weaker than volatile, stronger than plain)
    // Useful for lock-free data structures
    public int getAcquire() { return (int) VALUE_HANDLE.getAcquire(this); }
    public void setRelease(int v) { VALUE_HANDLE.setRelease(this, v); }

    // Atomic CAS (Compare-And-Set)
    public boolean cas(int expected, int update) {
        return VALUE_HANDLE.compareAndSet(this, expected, update);
    }

    // Atomic Get-And-Add
    public int getAndAdd(int delta) {
        return (int) VALUE_HANDLE.getAndAdd(this, delta);
    }
}

// Access modes comparison:
// plain: no ordering guarantees (fastest)
// opaque: no reordering, no visibility guarantee
// acquire/release: one-sided barrier (for custom synchronization)
// volatile: full barrier (visibility + ordering)
```

---

## Components – Concurrency Primitives và JMM

| Primitive | Visibility | Atomicity | Ordering | Use case |
|-----------|-----------|-----------|---------|----------|
| `volatile` | ✅ | ✅ (single read/write) | ✅ | Flag, status, reference publish |
| `synchronized` | ✅ | ✅ | ✅ | Compound actions, critical section |
| `AtomicXxx` | ✅ | ✅ | ✅ | CAS-based counter, reference |
| `final` | ✅ (after constructor) | N/A | ✅ | Immutable object publication |
| Non-volatile field | ❌ | ❌ (long/double) | ❌ | Single-threaded only |

---

## Why – Tại sao JMM phức tạp?

```
Performance vs Correctness trade-off:

Strict memory model (all reads/writes go to main memory):
  → 100% visibility, no reordering
  → Extreme performance cost (cache = useless)
  → Cache coherency protocol runs for every operation

Relaxed memory model (JMM):
  → JVM/CPU free to optimize (cache, reorder)
  → Higher performance
  → Developer MUST use synchronization primitives correctly
  → Happens-before = contract between developer and JVM

x86 has stronger memory model (TSO - Total Store Order):
  → Fewer barriers needed on x86
  → Same Java code may work on x86 but FAIL on ARM/POWER (weaker memory model)
  → Write once, run correctly everywhere = use JMM primitives properly
```

---

## Trade-offs

| | volatile | synchronized | AtomicXxx | Lock-free (VarHandle) |
|--|---------|-------------|-----------|----------------------|
| Performance | Fast (no mutex) | Slower (OS mutex) | Fast (CAS) | Fastest (custom) |
| Complexity | Low | Low | Low | High |
| Compound ops | No | Yes | Yes (getAndSet) | Yes |
| Fairness | N/A | Optional | Optional | Manual |
| Blocking | No | Yes | No | No |

---

## Real-world Usage (Production)

### 1. Safe Flag với volatile

```java
@Service
public class JobScheduler {
    private volatile boolean running = false;

    public void start() {
        running = true;
        executorService.submit(this::runLoop);
    }

    public void stop() {
        running = false; // single writer → volatile đủ
    }

    private void runLoop() {
        while (running) { // volatile read → sees updates from stop()
            processNextJob();
        }
    }
}
```

### 2. Publication với AtomicReference

```java
public class ConfigManager {
    // Atomic reference để safe publication của mutable config
    private final AtomicReference<AppConfig> configRef =
        new AtomicReference<>(AppConfig.defaults());

    // Called when config file changes
    public void reload(Path configFile) {
        AppConfig newConfig = ConfigParser.parse(configFile);
        configRef.set(newConfig); // atomic set, safe publication
    }

    // Many threads read
    public String getSetting(String key) {
        return configRef.get().get(key); // atomic get, always sees full AppConfig
    }
}
```

### 3. Custom ReadWrite Lock Pattern

```java
// StampedLock: optimistic reading (Java 8)
public class DataCache {
    private final StampedLock lock = new StampedLock();
    private volatile Map<String, String> cache = new HashMap<>();

    public String get(String key) {
        long stamp = lock.tryOptimisticRead(); // no lock!
        String value = cache.get(key);
        if (!lock.validate(stamp)) {           // was there a write?
            stamp = lock.readLock();           // fall back to read lock
            try {
                value = cache.get(key);
            } finally {
                lock.unlockRead(stamp);
            }
        }
        return value;
    }

    public void put(String key, String value) {
        long stamp = lock.writeLock();
        try {
            Map<String, String> newCache = new HashMap<>(cache);
            newCache.put(key, value);
            cache = newCache; // volatile write → safe publication
        } finally {
            lock.unlockWrite(stamp);
        }
    }
}
```

### 4. Testing Concurrency (tricky!)

```java
// ConcurrencyTest: dùng nhiều thread và nhiều iterations
@Test
public void testCounterThreadSafety() throws InterruptedException {
    int threadCount = 100;
    int incrementsPerThread = 1000;
    AtomicInteger counter = new AtomicInteger(0);

    CountDownLatch latch = new CountDownLatch(threadCount);
    ExecutorService exec = Executors.newFixedThreadPool(threadCount);

    for (int i = 0; i < threadCount; i++) {
        exec.submit(() -> {
            for (int j = 0; j < incrementsPerThread; j++) {
                counter.incrementAndGet();
            }
            latch.countDown();
        });
    }

    latch.await(10, TimeUnit.SECONDS);
    exec.shutdown();

    assertEquals(threadCount * incrementsPerThread, counter.get());
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **JVM Runtime Data Areas & Bytecode**
>
> Keyword: JVM specification runtime areas (Method Area/Metaspace, Heap, Java Stack, PC Register, Native Method Stack), Stack Frame (local variables array, operand stack, constant pool reference), bytecode instructions (iload/istore/invokevirtual/invokeinterface/invokestatic/invokedynamic), constant pool, class file structure (magic number, access flags, field/method descriptors)
