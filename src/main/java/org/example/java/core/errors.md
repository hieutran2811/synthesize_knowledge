# Java Error – Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Error là gì?

**Error** là subclass của `Throwable` đại diện cho các vấn đề **nghiêm trọng ở tầng JVM hoặc môi trường** mà ứng dụng thông thường **không thể và không nên** cố phục hồi. Khác với `Exception` (lỗi ở tầng ứng dụng, có thể handle), Error báo hiệu rằng JVM hoặc hệ thống đang ở trạng thái không đảm bảo tiếp tục chạy an toàn.

```java
// Throwable là gốc chung
Throwable
├── Error          ← JVM/system level — không nên catch
└── Exception      ← Application level — nên catch/handle
```

---

## How – Error Hierarchy (Chi tiết)

```
java.lang.Error
├── VirtualMachineError          ← JVM không còn đủ tài nguyên để hoạt động
│   ├── OutOfMemoryError         ← heap/metaspace/native memory cạn kiệt
│   ├── StackOverflowError       ← call stack vượt quá giới hạn
│   └── InternalError            ← lỗi nội bộ JVM (hiếm gặp)
│
├── AssertionError               ← assert statement bị vi phạm
│
├── LinkageError                 ← class không thể link đúng cách
│   ├── NoClassDefFoundError     ← class tồn tại lúc compile, mất lúc runtime
│   ├── ClassFormatError         ← bytecode không hợp lệ / class file bị hỏng
│   ├── UnsatisfiedLinkError     ← native library (.dll/.so) không tìm thấy
│   ├── ExceptionInInitializerError ← lỗi trong static initializer block
│   ├── IncompatibleClassChangeError ← class hierarchy thay đổi sau khi compile
│   │   ├── AbstractMethodError  ← gọi abstract method chưa được implement
│   │   ├── NoSuchMethodError    ← method tồn tại lúc compile, mất lúc runtime
│   │   ├── NoSuchFieldError     ← field tồn tại lúc compile, mất lúc runtime
│   │   └── IllegalAccessError  ← method/field không còn public lúc runtime
│   └── VerifyError              ← bytecode verification thất bại
│
├── ThreadDeath                  ← thread bị stop() (deprecated)
├── ServiceConfigurationError    ← ServiceLoader không load được provider
├── AssertionError               ← assert bị vi phạm
├── AWTError                     ← lỗi AWT toolkit (GUI)
└── IOError                      ← I/O failure nghiêm trọng không thể recover
```

---

## How – OutOfMemoryError (Chi tiết nhất)

OutOfMemoryError có **nhiều message khác nhau**, mỗi loại chỉ ra vùng memory cụ thể bị cạn.

### 1. `Java heap space`
```java
// Nguyên nhân: heap cạn kiệt, GC không thu hồi đủ
List<byte[]> list = new ArrayList<>();
while (true) {
    list.add(new byte[1024 * 1024]); // 1MB mỗi lần
}
// OutOfMemoryError: Java heap space

// Chẩn đoán:
// java -Xmx512m -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp/heap.hprof MyApp
// → Phân tích bằng Eclipse MAT: tìm object chiếm nhiều nhất (Dominator Tree)
```

### 2. `Metaspace` (Java 8+)
```java
// Nguyên nhân: quá nhiều class được load (classloader leak, CGLIB tạo proxy không giới hạn)
// Thường xảy ra trong môi trường hot-deploy hoặc code generation

// Dấu hiệu: số lượng class tăng liên tục
// jcmd <pid> VM.class_histogram | head -20

// Tuning:
// java -XX:MaxMetaspaceSize=256m MyApp  (không set → unbounded, có thể chiếm hết RAM)
```

### 3. `GC overhead limit exceeded`
```java
// JVM dành >98% thời gian GC nhưng thu hồi <2% heap (mặc định)
// Thường do object graph phức tạp, nhiều object tạm thời tích lũy

// Tắt limit (không khuyến khích):
// java -XX:-UseGCOverheadLimit MyApp

// Giải pháp thực sự: tìm memory leak, tăng heap, hoặc giảm allocation rate
```

### 4. `unable to create native thread`
```java
// Nguyên nhân: quá nhiều thread → OS không tạo thêm được
// Linux: /proc/sys/kernel/threads-max, /proc/sys/vm/max_map_count
// Thường xảy ra khi không dùng thread pool, cứ new Thread() mỗi request

// ANTI-PATTERN
for (Request req : requests) {
    new Thread(() -> handle(req)).start(); // Tạo không giới hạn thread!
}

// FIX: Dùng thread pool
ExecutorService pool = Executors.newFixedThreadPool(50);
for (Request req : requests) {
    pool.submit(() -> handle(req));
}
```

### 5. `Direct buffer memory`
```java
// NIO ByteBuffer.allocateDirect() chiếm off-heap memory
// Giới hạn bởi -XX:MaxDirectMemorySize (mặc định = -Xmx)
ByteBuffer buf = ByteBuffer.allocateDirect(500 * 1024 * 1024); // 500MB off-heap
// OutOfMemoryError: Direct buffer memory nếu vượt giới hạn

// Kiểm tra:
// jcmd <pid> VM.native_memory detail | grep -A 5 "Internal"
```

---

## How – StackOverflowError

```java
// Nguyên nhân 1: Đệ quy vô tận
void infiniteRecursion() {
    infiniteRecursion(); // StackOverflowError sau vài nghìn lần
}

// Nguyên nhân 2: Đệ quy hợp lệ nhưng quá sâu
int fibonacci(int n) {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2); // StackOverflow với n > ~10000
}

// FIX: Dùng iteration hoặc tail recursion (Java không optimize TCO, phải tự convert)
int fibIterative(int n) {
    if (n <= 1) return n;
    int prev = 0, curr = 1;
    for (int i = 2; i <= n; i++) {
        int next = prev + curr;
        prev = curr;
        curr = next;
    }
    return curr;
}

// Nguyên nhân 3: toString() → equals() gọi lẫn nhau (circular reference)
class A {
    B b;
    public String toString() { return "A{b=" + b + "}"; } // gọi B.toString()
}
class B {
    A a;
    public String toString() { return "B{a=" + a + "}"; } // gọi A.toString() → StackOverflow!
}

// Tuning stack size (mỗi thread dùng nhiều RAM hơn):
// java -Xss4m MyApp  (mặc định: 512KB - 1MB tùy platform)
```

**Cách đọc stack trace để tìm vòng lặp:**
```
java.lang.StackOverflowError
    at com.example.A.toString(A.java:5)
    at com.example.B.toString(B.java:5)
    at com.example.A.toString(A.java:5)   ← lặp lại → đây là vòng tròn
    at com.example.B.toString(B.java:5)
    ... (lặp nghìn lần)
```

---

## How – NoClassDefFoundError vs ClassNotFoundException

Đây là cặp hay nhầm lẫn nhất:

```java
// ClassNotFoundException: Checked exception
// Xảy ra khi dùng reflection, ClassLoader.loadClass() không tìm thấy class
try {
    Class<?> clazz = Class.forName("com.example.MyPlugin");  // checked exception
} catch (ClassNotFoundException e) {
    // class không có trong classpath → có thể xử lý gracefully
}

// NoClassDefFoundError: Error (Unchecked)
// Class TỒN TẠI lúc compile, nhưng MẤT lúc runtime
MyClass obj = new MyClass(); // NoClassDefFoundError nếu MyClass.class bị thiếu

// Cũng xảy ra khi static initializer của class đã throw exception trước đó:
class Broken {
    static { throw new RuntimeException("init failed"); }
}
// Lần đầu: ExceptionInInitializerError
// Lần sau: NoClassDefFoundError (JVM đánh dấu class là "erroneous")
```

**Cách chẩn đoán NoClassDefFoundError:**
```bash
# Kiểm tra class có trong runtime classpath không
java -verbose:class com.example.Main 2>&1 | grep "MyClass"

# Với fat JAR: kiểm tra shading conflict
jar tf app.jar | grep "MyClass.class"

# Module system (Java 9+): kiểm tra exports
# module-info.java cần: exports com.example.pkg
```

---

## How – ExceptionInInitializerError

```java
// Xảy ra khi exception được throw trong static initializer hoặc static field init

// Static field initialization
class Config {
    // NumberFormatException → wrapped thành ExceptionInInitializerError
    static final int MAX_RETRY = Integer.parseInt("not_a_number");
}

// Static initializer block
class DatabasePool {
    static final DataSource DATA_SOURCE;
    static {
        try {
            DATA_SOURCE = createDataSource(); // có thể throw
        } catch (Exception e) {
            throw new ExceptionInInitializerError(e); // explicit wrap
        }
    }
}

// Đọc stack trace:
// ExceptionInInitializerError
//     at Config.<clinit>(Config.java:3)          ← static init thất bại
// Caused by: NumberFormatException: For input string: "not_a_number"
//     at Integer.parseInt(Integer.java:...)
//
// Lần sau khi dùng Config: NoClassDefFoundError: Could not initialize class Config

// FIX: Lazy initialization thay vì static init
class Config {
    private static volatile int maxRetry = -1;

    public static int getMaxRetry() {
        if (maxRetry < 0) {
            maxRetry = Integer.parseInt(System.getProperty("max.retry", "3"));
        }
        return maxRetry;
    }
}
```

---

## How – LinkageError subtypes

```java
// AbstractMethodError: class A implements interface I,
// interface I thêm method mới, A được compile trước khi interface thay đổi
interface PaymentGateway {
    void charge(Amount amount);
    void refund(Amount amount); // thêm sau → AbstractMethodError nếu implementation cũ
}

// NoSuchMethodError / NoSuchFieldError:
// Thường do version conflict trong dependency (JAR hell)
// Ví dụ: compile với guava 31, runtime có guava 20 (method bị xóa)

// IllegalAccessError:
// Method được công khai lúc compile, sau đó thay thành private/package-private
// Hoặc module system (Java 9+): package không được opens/exports

// IncompatibleClassChangeError:
// Class compile là interface, sau đó đổi thành abstract class (hoặc ngược lại)
// → Cần recompile toàn bộ code phụ thuộc

// Chẩn đoán chung: kiểm tra version conflict
// mvn dependency:tree | grep "version conflict"
// gradle dependencies --configuration runtimeClasspath
```

---

## How – AssertionError

```java
// assert bị vi phạm, chỉ active khi chạy với flag -ea (enable assertions)
public void setAge(int age) {
    assert age >= 0 && age <= 150 : "Invalid age: " + age;
    this.age = age;
}

// Chạy bình thường (không có -ea): assert bị bỏ qua hoàn toàn (no-op)
// Chạy với -ea: throw AssertionError nếu điều kiện false

// KHÔNG dùng assert cho:
// - Input validation từ user/external API (dùng throw IllegalArgumentException)
// - Side effects (assert list.remove(item) — có thể bị bỏ qua!)

// DÙNG assert cho:
// - Kiểm tra invariant nội bộ (điều kiện LUÔN đúng trong code đúng đắn)
// - Class invariant sau constructor
// - Post-condition sau complex algorithm
private int binarySearch(int[] arr, int target) {
    // ... search logic ...
    assert result == -1 || arr[result] == target : "Invariant violated";
    return result;
}
```

---

## How – Error trong môi trường Concurrent

```java
// Error trong thread pool worker bị nuốt silently!
ExecutorService pool = Executors.newFixedThreadPool(4);

Future<?> future = pool.submit(() -> {
    throw new StackOverflowError(); // Không ai biết!
});

// Cách 1: Luôn gọi future.get() để detect
try {
    future.get(); // ném ExecutionException wrapping Error
} catch (ExecutionException e) {
    if (e.getCause() instanceof Error err) {
        log.error("Worker died with JVM error", err);
        throw err; // re-throw — không tiếp tục
    }
}

// Cách 2: UncaughtExceptionHandler cho toàn bộ thread pool
ThreadFactory factory = r -> {
    Thread t = new Thread(r);
    t.setUncaughtExceptionHandler((thread, throwable) -> {
        if (throwable instanceof Error) {
            log.error("Thread {} died with JVM Error — shutting down", thread.getName(), throwable);
            System.exit(1); // fail fast
        } else {
            log.error("Thread {} threw uncaught exception", thread.getName(), throwable);
        }
    });
    return t;
};
ExecutorService safePool = Executors.newFixedThreadPool(4, factory);

// Cách 3: CompletableFuture — exceptionally() bắt được cả Error
CompletableFuture.supplyAsync(() -> riskyOperation())
    .exceptionally(throwable -> {
        if (throwable instanceof OutOfMemoryError oom) {
            log.error("OOM in async task", oom);
            return fallbackValue();
        }
        throw new CompletionException(throwable);
    });
```

---

## Why – Tại sao phân biệt Error và Exception?

1. **Semantics rõ ràng**: Error = JVM/system không ổn định → không nên tiếp tục; Exception = ứng dụng gặp vấn đề có thể xử lý
2. **API contract**: Checked exception buộc caller xử lý; Error không buộc → code sạch hơn cho happy path
3. **Recovery policy**: Exception → retry, fallback, user message; Error → log + fail fast (trạng thái JVM không đảm bảo)
4. **Debugging**: Khi thấy Error trong log, biết ngay cần nhìn vào JVM metrics / heap / classpath chứ không phải business logic

---

## Components – Bảng tổng hợp

| Error | Package | Nguyên nhân chính | Recover? |
|-------|---------|-------------------|----------|
| `OutOfMemoryError: Java heap space` | java.lang | Memory leak, object quá lớn | Không |
| `OutOfMemoryError: Metaspace` | java.lang | ClassLoader leak, code gen | Không |
| `OutOfMemoryError: GC overhead` | java.lang | Allocation rate quá cao | Không |
| `OutOfMemoryError: unable to create thread` | java.lang | Thread pool không giới hạn | Không |
| `StackOverflowError` | java.lang | Đệ quy vô tận, circular ref | Không |
| `NoClassDefFoundError` | java.lang | JAR thiếu lúc runtime | Không |
| `ExceptionInInitializerError` | java.lang | Exception trong static init | Không |
| `ClassFormatError` | java.lang | Bytecode corrupt / version mismatch | Không |
| `UnsatisfiedLinkError` | java.lang | Native library (.dll/.so) thiếu | Không |
| `AbstractMethodError` | java.lang | Binary incompatibility | Không |
| `NoSuchMethodError` | java.lang | Dependency version conflict | Không |
| `IllegalAccessError` | java.lang | Module encapsulation bị vi phạm | Không |
| `AssertionError` | java.lang | assert vi phạm | Hiếm |
| `InternalError` | java.lang | JVM bug | Không |

---

## When – Khi nào được phép catch Error?

### Nên làm: Top-level handler để log trước khi JVM tắt
```java
public static void main(String[] args) {
    try {
        startApplication(args);
    } catch (Error e) {
        // Chỉ log — KHÔNG cố phục hồi
        System.err.println("FATAL JVM ERROR: " + e.getMessage());
        e.printStackTrace();
        System.exit(1);
    }
}
```

### Nên làm: Isolate tenant/request trong framework/server
```java
// Server cần ngăn lỗi của 1 request làm sập cả process
@Override
public void service(HttpServletRequest req, HttpServletResponse res) {
    try {
        doHandle(req, res);
    } catch (Throwable t) { // bắt cả Error
        log.error("Fatal error handling request {}", req.getRequestURI(), t);
        if (!res.isCommitted()) {
            res.sendError(500, "Internal server error");
        }
        // KHÔNG re-throw — thread trở về pool
        // NHƯNG: nếu là OOM → nên xem xét restart
    }
}
```

### KHÔNG làm: Nuốt Error và tiếp tục
```java
// NGUY HIỂM: Trạng thái JVM sau OOM không đảm bảo
try {
    processHugeData();
} catch (OutOfMemoryError e) {
    // "Thử lại sau" — SAI! Heap vẫn cạn, invariant có thể bị phá vỡ
    return processSmallData();
}
```

### KHÔNG làm: Catch Error ở business logic layer
```java
// NGUY HIỂM: Che giấu vấn đề nghiêm trọng
@Service
public class OrderService {
    public Order createOrder(OrderRequest req) {
        try {
            return orderRepo.save(buildOrder(req));
        } catch (Error e) { // SAI hoàn toàn
            return null;
        }
    }
}
```

---

## Compare – Error vs Exception

| Tiêu chí | `Error` | `Exception` |
|----------|---------|-------------|
| **Tầng** | JVM / OS / Environment | Application code |
| **Recover** | Không (trạng thái JVM unsafe) | Có thể |
| **Checked** | Không | Có (checked) hoặc không (unchecked) |
| **Nên catch?** | Hiếm, chỉ ở top-level | Thường xuyên |
| **Nguyên nhân** | Resource exhaustion, binary incompatibility | Bug, invalid input, external failure |
| **Hành động** | Log + fail fast + alert ops | Handle, retry, fallback, user message |

## Compare – NoClassDefFoundError vs ClassNotFoundException

| | `NoClassDefFoundError` | `ClassNotFoundException` |
|--|----------------------|------------------------|
| **Loại** | Error (unchecked) | Exception (checked) |
| **Khi nào** | JVM tự load class (new, method call) | Explicit: `Class.forName()`, `loadClass()` |
| **Nguyên nhân** | JAR thiếu runtime, static init lỗi | ClassLoader không tìm thấy |
| **Handle được?** | Không | Có — fallback gracefully |
| **Debug** | Kiểm tra classpath/module | Kiểm tra class name có đúng không |

---

## Trade-offs

| Ưu điểm (của cơ chế Error) | Nhược điểm |
|---------------------------|-----------|
| Phân biệt rõ lỗi JVM vs lỗi ứng dụng | Khó catch đúng chỗ (dễ bị nuốt trong thread pool) |
| Không cần declare `throws Error` → code sạch | Một số framework catch Throwable → Error bị "xử lý" sai |
| Compiler không yêu cầu handle → không verbose | OOM có thể khiến recovery code cũng fail (không đủ memory) |
| Fail-fast rõ ràng khi JVM không ổn định | Error message không luôn đủ thông tin (cần heap dump) |

---

## Real-world Usage (Production)

### 1. Cấu hình JVM cho production — phòng ngừa OOM
```bash
# Heap + automatic heap dump khi OOM
java \
  -Xms2g -Xmx2g \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/var/log/app/heapdump-$(date +%Y%m%d%H%M%S).hprof \
  -XX:+ExitOnOutOfMemoryError \        # Tắt process ngay (tránh zombie state)
  -XX:MaxMetaspaceSize=256m \
  -XX:MaxDirectMemorySize=512m \
  -Xss512k \                           # Stack mỗi thread (giảm từ 1MB xuống)
  -jar app.jar
```

### 2. Phân tích OOM Heap Dump với Eclipse MAT
```
1. Mở Eclipse MAT → File → Open Heap Dump → .hprof
2. Chạy "Leak Suspects Report" → tự động tìm nghi phạm
3. Xem "Dominator Tree" → object nào chiếm nhiều retained heap nhất
4. Xem "Histogram" → class nào có nhiều instance nhất
5. Path to GC Roots → trace ngược lại xem ai giữ object không cho GC

Ví dụ kết quả:
Problem Suspect 1:
  com.example.UserCache → 1.2GB retained
  → Tìm: UserCache không có eviction policy → memory leak
```

### 3. Monitoring Error trong production (Micrometer + Spring Boot)
```java
@Component
public class JvmErrorMetrics {

    private final MeterRegistry registry;
    private final AtomicLong oomCount = new AtomicLong(0);

    public JvmErrorMetrics(MeterRegistry registry) {
        this.registry = registry;
        // Register custom counter
        Gauge.builder("jvm.errors.oom", oomCount, AtomicLong::doubleValue)
             .description("OutOfMemoryError occurrences")
             .register(registry);
    }

    // Gọi từ UncaughtExceptionHandler
    public void recordOOM() {
        oomCount.incrementAndGet();
        // Alert ngay lập tức
    }
}

// Global UncaughtExceptionHandler
Thread.setDefaultUncaughtExceptionHandler((thread, throwable) -> {
    if (throwable instanceof OutOfMemoryError) {
        jvmErrorMetrics.recordOOM();
        log.error("OutOfMemoryError in thread {}", thread.getName(), throwable);
        // Trigger graceful shutdown sau khi log
        SpringApplication.exit(applicationContext, () -> 1);
    }
});
```

### 4. Diagnosing StackOverflowError trong production
```java
// Bắt và log để tìm nguyên nhân, KHÔNG tiếp tục
try {
    callBusinessLogic();
} catch (StackOverflowError e) {
    // Lấy top 20 frame để tìm vòng lặp
    StackTraceElement[] trace = e.getStackTrace();
    int limit = Math.min(trace.length, 20);
    StringBuilder sb = new StringBuilder("StackOverflow top frames:\n");
    for (int i = 0; i < limit; i++) {
        sb.append("  at ").append(trace[i]).append("\n");
    }
    log.error(sb.toString());
    throw e; // re-throw — không tiếp tục
}
```

### 5. NoSuchMethodError — phát hiện JAR conflict khi startup
```java
@Component
public class DependencyVersionChecker implements ApplicationListener<ApplicationStartedEvent> {

    private static final Logger log = LoggerFactory.getLogger(DependencyVersionChecker.class);

    @Override
    public void onApplicationEvent(ApplicationStartedEvent event) {
        try {
            // Probe method có thể bị conflict
            // Ví dụ: kiểm tra guava version có method cần dùng
            com.google.common.collect.ImmutableList.copyOf(List.of());
            log.info("Dependency check passed");
        } catch (NoSuchMethodError e) {
            log.error("Dependency version conflict detected: {}", e.getMessage());
            // Fail fast — tốt hơn là crash lúc xử lý request
            throw new IllegalStateException("Critical dependency conflict", e);
        }
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Đã thêm vào Java Core:
> - `exceptions.md` – Exception hierarchy, checked/unchecked, try-with-resources, anti-patterns
> - `errors.md` – Error hierarchy, OOM subtypes, StackOverflow, LinkageError, diagnosis, JVM tuning
>
> Liên quan:
> - `jvm/gc.md` – Chi tiết GC algorithm, heap regions, reference types ảnh hưởng đến OOM
> - `jvm/runtime_data_areas.md` – Stack frame, Metaspace layout giải thích StackOverflow và Metaspace OOM
> - `jvm/classloader.md` – Class loading phases, parent delegation liên quan đến NoClassDefFoundError
> - `core/concurrency.md` – ThreadPoolExecutor, UncaughtExceptionHandler, Future.get()
>
> Tiếp theo: **Spring Security** – Authentication (JWT/Session), Authorization, CSRF, CORS
