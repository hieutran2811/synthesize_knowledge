# Garbage Collection (GC) – JVM Memory Management

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Garbage Collection là gì?

**Garbage Collection (GC)** là cơ chế tự động thu hồi bộ nhớ của các objects không còn được tham chiếu tới — giải phóng lập trình viên khỏi manual memory management (như `malloc/free` trong C).

```
Object sống → được tham chiếu từ GC Root (stack, static fields, JNI)
Object chết → không còn path nào từ GC Root tới nó → eligible for GC

GC Root là gì?
  - Local variables trong stack frames đang chạy
  - Static fields của classes đã load
  - JNI references
  - Active threads
  - Monitor objects (synchronized blocks)
```

---

## How – Heap Layout (HotSpot JVM)

### Java 8 và trước

```
Heap:
┌─────────────────────────────────────────────────────┐
│  Young Generation          │  Old Generation         │
│  ┌──────┬────────┬────────┐│                         │
│  │ Eden │Survivor│Survivor││                         │
│  │      │  S0    │  S1    ││                         │
│  └──────┴────────┴────────┘│                         │
└─────────────────────────────────────────────────────┘

Non-heap:
  PermGen (Java 7) / Metaspace (Java 8+) → class metadata
  Code Cache → JIT compiled native code
```

### Young Generation

```
Eden (80%) + Survivor 0 (10%) + Survivor 1 (10%)

Object allocation flow:
1. new Object() → allocate trong Eden (TLAB – Thread Local Allocation Buffer)
2. Eden đầy → Minor GC (Young GC) triggered
3. Live objects: Eden + S0 → copy sang S1 (Mark & Copy)
4. Swap S0↔S1 labels (S1 trở thành "from", S0 trở thành "to")
5. Age counter của object tăng +1 mỗi lần survive
6. Age >= tenuring_threshold (default 15) → promote sang Old Gen
```

```java
// TLAB (Thread Local Allocation Buffer):
// Mỗi thread có TLAB riêng trong Eden
// Allocation = pointer bump (cực nhanh, không cần synchronization)
// new Object() ≈ ++pointer (vài nanoseconds)
// Khi TLAB đầy → xin TLAB mới từ Eden
-XX:TLABSize=512k
-XX:+PrintTLAB  // xem TLAB stats
```

### Old Generation (Tenured)

```
Long-lived objects:
  - Promoted từ Young Gen (age >= threshold)
  - Large objects (lớn hơn threshold → allocate thẳng vào Old Gen)
    -XX:PretenureSizeThreshold=1048576  (1MB)

Major GC / Full GC: khi Old Gen đầy hoặc promotion fails
Major GC: chậm hơn Minor GC (large area, whole-heap scan)
Full GC: stop-the-world, GC cả Young + Old + Metaspace
```

---

## How – GC Algorithms (Cơ bản)

### 1. Mark-Sweep

```
Phase 1: MARK
  Traverse từ GC Roots → đánh dấu tất cả live objects

Phase 2: SWEEP
  Scan toàn bộ heap → thu hồi unmarked objects

Nhược điểm: fragmentation! Free space rải rác → khó allocate large object
```

### 2. Mark-Compact

```
Phase 1: MARK (giống trên)

Phase 2: COMPACT
  Di chuyển live objects về một phía của heap
  → Không fragmentation
  → Chậm hơn (cần update tất cả references)
```

### 3. Copying (Young Gen)

```
Chia heap làm 2 nửa (From-space / To-space)
Phase 1: Copy tất cả live objects từ From → To
Phase 2: Flip: To trở thành From (next allocation)

Ưu: Nhanh, không fragmentation, dead objects không cần xử lý
Nhược: Chỉ dùng được 50% heap tại một thời điểm
```

### 4. Generational GC (HotSpot default)

```
Giả thuyết "Weak Generational Hypothesis":
  Hầu hết objects die young (short-lived)
  → Tập trung GC vào Young Gen (nhỏ, fast)
  → Ít khi scan Old Gen (slow)

Eden + Survivors: Copying algorithm (fast Minor GC)
Old Gen: Mark-Compact (slow Major GC, nhưng ít khi xảy ra)
```

---

## How – Reference Types

```java
// 4 loại reference, quyết định GC behavior

// 1. Strong Reference (default) – GC KHÔNG thu hồi khi có strong ref
Object obj = new Object();         // strong reference
obj = null;                        // eligible for GC khi không còn strong ref

// 2. Soft Reference – GC thu hồi KHI JVM sắp OOM
SoftReference<byte[]> cache = new SoftReference<>(new byte[1024 * 1024]);
byte[] data = cache.get(); // null nếu đã bị GC
// Use case: memory-sensitive cache (GC chỉ clear khi thực sự cần memory)

// 3. Weak Reference – GC thu hồi ở NEXT GC cycle (dù còn memory)
WeakReference<User> userRef = new WeakReference<>(new User());
User user = userRef.get(); // null sau GC
// Use case: WeakHashMap (key tự remove khi key object bị GC)
WeakHashMap<Widget, BigData> cache = new WeakHashMap<>();
// Key Widget bị GC → entry tự động xóa!

// 4. Phantom Reference – GC thu hồi SAU khi finalized, TRƯỚC khi deallocate
ReferenceQueue<Object> queue = new ReferenceQueue<>();
PhantomReference<Object> phantom = new PhantomReference<>(new Object(), queue);
// phantom.get() LUÔN trả về null
// Dùng để: cleanup resources sau GC (thay thế finalize())

// ReferenceQueue: nhận thông báo khi reference bị cleared
Reference<?> ref;
while ((ref = queue.poll()) != null) {
    cleanup(ref); // perform cleanup
}
```

```java
// Finalization – DEPRECATED, AVOID!
@Override
protected void finalize() throws Throwable {
    // Vấn đề:
    // 1. GC không đảm bảo khi nào finalize() chạy
    // 2. Object có thể "resurrect" trong finalize()
    // 3. GC cần 2 cycles để thu hồi finalizable objects
    // 4. Finalizer thread có thể không theo kịp → memory leak
    super.finalize();
}

// Thay thế đúng: Cleaner API (Java 9+)
import java.lang.ref.Cleaner;
class Resource implements AutoCloseable {
    private static final Cleaner CLEANER = Cleaner.create();
    private final Cleaner.Cleanable cleanable;

    Resource() {
        cleanable = CLEANER.register(this, new CleanupAction());
    }

    @Override
    public void close() {
        cleanable.clean();
    }

    private static class CleanupAction implements Runnable {
        @Override
        public void run() {
            // native resource release – không cần reference to Resource
            System.out.println("Cleaning up native resource");
        }
    }
}
```

---

## How – GC Implementations

### Serial GC

```bash
-XX:+UseSerialGC
# Single-threaded → stop-the-world
# Young: Copying, Old: Mark-Compact
# Tốt cho: small heap, single-core, client apps
# Không phù hợp: server workloads
```

### Parallel GC (Throughput GC)

```bash
-XX:+UseParallelGC  # Java 8 default
# Multi-threaded → still stop-the-world (nhưng song song)
# Young: Parallel Copying, Old: Parallel Mark-Compact
# Tốt cho: batch processing, throughput-oriented
# Xấu cho: latency-sensitive apps (STW pauses có thể dài)

-XX:ParallelGCThreads=N   # số GC threads (default: CPU cores)
-XX:MaxGCPauseMillis=200  # soft goal cho pause time
-XX:GCTimeRatio=99        # 1% time spent in GC (99% application)
```

### G1 GC (Garbage First)

```bash
-XX:+UseG1GC  # Java 9+ default
# Heap chia thành nhiều regions (1-32MB mỗi region)
# Chọn regions có nhiều garbage nhất → "Garbage First"
# Target pause time: configurable

# Heap regions layout:
┌────┬────┬────┬────┬────┬────┬────┬────┐
│ E  │ S  │ E  │ O  │ O  │ H  │ E  │ O  │
└────┴────┴────┴────┴────┴────┴────┴────┘
E = Eden, S = Survivor, O = Old, H = Humongous (large objects)

# G1 phases:
# 1. Young-only: Minor GC (parallel STW)
# 2. Concurrent Marking: concurrent với application
# 3. Mixed GC: collect Young + some Old regions (STW nhưng có pause target)
# 4. Full GC: fallback nếu concurrent không kịp (slow, avoid!)
```

```bash
# G1 tuning
-XX:G1HeapRegionSize=16m          # region size (1, 2, 4, 8, 16, 32 MB)
-XX:MaxGCPauseMillis=200          # target pause time (default 200ms)
-XX:G1NewSizePercent=5            # min Young Gen size
-XX:G1MaxNewSizePercent=60        # max Young Gen size
-XX:G1MixedGCLiveThresholdPercent=85  # region thi nào garbage < 15% → include
-XX:InitiatingHeapOccupancyPercent=45  # khi nào start concurrent marking
```

### ZGC (Z Garbage Collector)

```bash
-XX:+UseZGC  # Java 15+ production, Java 11+ experimental
# Throughput: tương đương G1
# Pause: <1ms (sub-millisecond!) ngay cả với heap TB
# Scale: 8MB tới 16TB heap

# Cơ chế:
# Load barriers: JIT-inserted code kiểm tra reference khi đọc
# Colored pointers: 64-bit pointer encode GC metadata (mark/relocate/remapped bits)
# Concurrent: marking, relocation, reference processing đều concurrent

# Java 21: Generational ZGC (cải thiện throughput)
-XX:+UseZGC -XX:+ZGenerational  # Java 21+

# Khi nào dùng ZGC?
# - Latency critical (trading, gaming, real-time)
# - Heap lớn (>32GB) mà G1 pause quá dài
# - Java 21+ với Generational ZGC
```

### Shenandoah GC

```bash
-XX:+UseShenandoahGC  # OpenJDK, không có trong Oracle JDK
# Concurrent compaction (unique feature!)
# Pause < 10ms, nhưng higher CPU overhead
# Không scale tốt như ZGC trên multi-core

# So sánh ZGC vs Shenandoah:
# ZGC: better pause time, better scalability
# Shenandoah: mature, available in more JDK distributions
```

---

## How – GC Monitoring & Tuning

### GC Log

```bash
# Java 11+
-Xlog:gc*:file=/logs/gc.log:time,level,tags:filecount=5,filesize=20m

# Java 8
-XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:/logs/gc.log
-XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=20m
```

```
# G1 GC log example:
[2024-01-15T10:00:01.234+0000][info][gc,start] GC(42) Pause Young (Normal) (G1 Evacuation Pause)
[2024-01-15T10:00:01.256+0000][info][gc     ] GC(42) Pause Young (Normal) (G1 Evacuation Pause) 512M->128M(1024M) 22.345ms
↑ timestamp                                    ↑ type                         ↑ before→after(total heap) ↑ pause time

# Điểm cần chú ý:
# - Pause time > MaxGCPauseMillis → cần tune
# - Heap không giảm sau GC → memory leak
# - Nhiều Full GC → heap quá nhỏ hoặc memory leak
# - Allocation rate cao → TLAB contention
```

### Heap Sizing

```bash
# Basic sizing
-Xms2g        # initial heap size
-Xmx8g        # maximum heap size
# Best practice: Xms = Xmx (tránh resize overhead)

# Young Gen sizing (với G1: dùng G1NewSizePercent thay thế)
-XX:NewRatio=2       # Old:Young = 2:1 → Young = 1/3 heap
-XX:NewSize=512m     # fixed Young Gen size
-XX:MaxNewSize=2g

# Metaspace
-XX:MetaspaceSize=256m      # initial Metaspace size
-XX:MaxMetaspaceSize=512m   # max Metaspace (default: unlimited!)
```

### GC Tuning Process

```
1. Đo trước khi tune: jstat, GC log, JFR
2. Xác định vấn đề:
   - Pause quá dài? → tuning pause time
   - Throughput thấp? → tăng heap, giảm GC frequency
   - OOM? → memory leak hunt
3. Chọn GC phù hợp:
   - Latency < 10ms → ZGC/Shenandoah
   - Balanced → G1GC
   - Throughput → ParallelGC
4. Tune từng bước, đo lại sau mỗi thay đổi

# jstat: real-time GC monitoring
jstat -gcutil <pid> 1s  # in GC stats mỗi giây
```

```
Output jstat -gcutil:
  S0     S1     E      O      M     CCS    YGC     YGCT    FGC    FGCT     GCT
  0.00  84.23  29.51  56.78  95.02  90.82    742    7.234     3    0.567    7.801

S0/S1: Survivor space %
E: Eden %
O: Old Gen %
M: Metaspace %
YGC/YGCT: Young GC count/time
FGC/FGCT: Full GC count/time
```

---

## How – Memory Leak Patterns

```java
// 1. Static collection accumulating objects
public class LeakExample {
    private static final List<Object> CACHE = new ArrayList<>();

    public void doWork(Object data) {
        CACHE.add(data);   // NEVER removed → memory leak!
        // Fix: dùng bounded cache (LRU), WeakReference, hoặc explicit remove
    }
}

// 2. Listener không unregister
class EventBus {
    private final List<Listener> listeners = new ArrayList<>();
    public void register(Listener l) { listeners.add(l); }
    // MISSING: unregister() → listener leak
}

// Fix: dùng WeakReference
class SafeEventBus {
    private final List<WeakReference<Listener>> listeners = new ArrayList<>();
    // Listeners tự GC khi không còn strong reference
}

// 3. ThreadLocal không remove
ThreadLocal<Connection> connLocal = new ThreadLocal<>();

// Thread pool: thread KHÔNG chết → ThreadLocal tồn tại mãi!
connLocal.set(getConnection());
try {
    doWork();
} finally {
    connLocal.remove(); // PHẢI remove! Đặc biệt trong thread pools
}

// 4. Inner class giữ reference tới outer class
class Outer {
    private byte[] largeData = new byte[1024 * 1024];

    class Inner {
        // Inner class tự động giữ reference tới Outer instance!
        // Nếu Inner object sống lâu → Outer không thể GC
    }

    // Fix: dùng static inner class (không giữ ref tới Outer)
    static class StaticInner { ... }
}

// 5. Interned Strings trước Java 7
// Java 7-: String.intern() lưu trong PermGen → OOM nếu intern quá nhiều
// Java 7+: String pool trong Heap → OK hơn

// 6. Unclosed streams / connections
// try-with-resources LUÔN sử dụng để đảm bảo close
try (InputStream is = new FileInputStream("file.txt")) {
    // auto close kể cả khi exception
}
```

### Memory Leak Analysis

```bash
# Heap dump khi OOM
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/dumps/heap.hprof

# Manual heap dump
jmap -dump:live,format=b,file=heap.hprof <pid>

# Phân tích heap dump
# Eclipse MAT (Memory Analyzer Tool) – phổ biến nhất
# VisualVM / JProfiler / YourKit

# jcmd – modern tool
jcmd <pid> VM.info
jcmd <pid> GC.heap_info
jcmd <pid> GC.run         # trigger GC manually
jcmd <pid> GC.heap_dump /tmp/heap.hprof
jcmd <pid> Thread.print   # thread dump
```

---

## Components – GC Comparison

| GC | Pause | Throughput | Heap | Concurrent | Java |
|----|-------|-----------|------|-----------|------|
| Serial | Long STW | Low | Small | No | All |
| Parallel | STW (parallel) | Highest | Medium | No | All |
| G1 | Predictable (200ms target) | Good | Medium-Large | Partial | 9+ default |
| ZGC | <1ms | Good | Any (to 16TB) | Full | 15+ (GA) |
| Shenandoah | <10ms | Good | Medium-Large | Full | OpenJDK |

---

## Why – Tại sao hiểu GC quan trọng?

```
Symptoms mà hiểu GC giúp giải quyết:
  - Application "freezes" định kỳ → GC STW pauses
  - Memory tăng dần rồi OOM → memory leak
  - Slow startup → GC warmup
  - High CPU với low throughput → GC overhead (>5% là vấn đề)
  - Response time spikes → GC pauses
```

---

## Trade-offs

| Yếu tố | Low Latency | High Throughput | Low Memory |
|--------|-------------|----------------|------------|
| GC chọn | ZGC | ParallelGC | SerialGC |
| Heap | Lớn (ít GC) | Moderate | Nhỏ |
| Tuning | Pause target | GC time ratio | Heap size |
| CPU | Higher (concurrent) | Lower (STW efficient) | Lowest |

---

## Real-world Usage (Production)

### 1. G1GC Config (Spring Boot production)

```bash
java -jar app.jar \
  -Xms4g -Xmx4g \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -XX:G1HeapRegionSize=16m \
  -XX:+G1UseAdaptiveIHOP \
  -XX:InitiatingHeapOccupancyPercent=35 \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/dumps/ \
  -Xlog:gc*:file=/logs/gc.log:time,uptime,level:filecount=10,filesize=10m
```

### 2. ZGC Config (latency-critical)

```bash
java -jar trading-app.jar \
  -Xms16g -Xmx16g \
  -XX:+UseZGC \
  -XX:+ZGenerational \           # Java 21+
  -XX:SoftMaxHeapSize=14g \     # soft target (ZGC uses remaining for GC headroom)
  -XX:ConcGCThreads=4 \
  -Xlog:gc*:file=/logs/gc.log:time
```

### 3. GC Overhead Alert

```java
// Prometheus / Micrometer – monitor GC
@Component
public class GcMonitor {
    public GcMonitor(MeterRegistry registry) {
        // Micrometer tự expose jvm.gc.pause, jvm.gc.memory.promoted...
        // Thêm custom alert:
        Gauge.builder("jvm.gc.overhead", this, m -> getGcOverhead())
            .description("GC time %")
            .register(registry);
    }

    private double getGcOverhead() {
        // Tính % thời gian spend trong GC
        // Alert nếu > 5%
        return ManagementFactory.getGarbageCollectorMXBeans()
            .stream()
            .mapToLong(GarbageCollectorMXBean::getCollectionTime)
            .sum() / (double) ManagementFactory.getRuntimeMXBean().getUptime() * 100;
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Java Memory Model (JMM)**
>
> Keyword: happens-before relationship, memory barriers (read/write fence), visibility problem (cache coherence), volatile (visibility + ordering, NOT atomicity), synchronized (mutual exclusion + visibility), final field guarantee, safe publication patterns, double-checked locking (broken without volatile), out-of-order execution (CPU reordering vs compiler reordering)
