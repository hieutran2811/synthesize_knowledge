# JIT Compiler & JVM Performance (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – JIT Compiler là gì?

**JIT (Just-In-Time) Compiler** là thành phần của JVM biên dịch **bytecode → native machine code** tại runtime — khi phát hiện code được chạy nhiều lần (hot code).

```
Source (.java)
    ↓ javac (AOT compile)
Bytecode (.class)
    ↓ JVM starts
Interpreter: chạy bytecode từng dòng (chậm)
    ↓ JVM phát hiện "hot" method (>= threshold)
JIT Compiler: compile bytecode → native code (nhanh!)
    ↓
Native machine code: chạy trực tiếp trên CPU
```

---

## How – Tiered Compilation (Java 7+)

JVM dùng **5 tier** từ chậm→nhanh tùy mức độ "nóng" của code:

```
Tier 0: Interpreter (không compile)
  └── Profiling: đếm invocation, branch stats

Tier 1: C1 – Simple compile (không optimize)
  └── Khi method được gọi >invocation_threshold lần

Tier 2: C1 – Limited profiling
  └── Thêm profiling counters trong compiled code

Tier 3: C1 – Full profiling (default cho hầu hết method)
  └── Đầy đủ profiling data để C2 optimize

Tier 4: C2 – Aggressively optimized (ultimate performance)
  └── Khi profiling data đủ
  └── Slow compile, fast execute
```

```java
// JVM flags
-XX:+TieredCompilation         // ON by default (Java 8+)
-XX:TieredStopAtLevel=1        // chỉ dùng C1 (nhanh startup, kém throughput)
-XX:TieredStopAtLevel=4        // full C2 (mặc định)
-XX:-TieredCompilation         // chỉ dùng C2 (chậm warmup, peak performance)

// Xem compilation:
-XX:+PrintCompilation
// Output:
// 67   !   4    com.example.HotMethod::compute (42 bytes)
// ↑    ↑   ↑    ↑
// id   flag tier method
// Flag: ! = OSR, % = deoptimized
```

---

## How – Thresholds

```java
// Khi nào method "nóng"?
-XX:CompileThreshold=10000      // Java 8: số lần gọi trước khi compile (không tiered)
-XX:Tier3InvocationThreshold=200  // C1 compilation
-XX:Tier4InvocationThreshold=5000 // C2 compilation

// Server vs Client JVM:
// Client (-client): optimize startup time
// Server (-server): optimize peak throughput (default 64-bit)
```

---

## How – JIT Optimizations

### 1. Method Inlining (Quan trọng nhất)
Thay thế method call bằng body của method → loại bỏ overhead của stack frame:

```java
// Source code
public int add(int a, int b) { return a + b; }
public void compute() {
    int result = add(x, y); // method call overhead
}

// Sau inlining (compiler thấy trong native code):
public void compute() {
    int result = x + y; // không còn method call!
}
```

```java
// JVM flags
-XX:+PrintInlining                  // xem inlining decisions
-XX:MaxInlineSize=35                 // max bytecode size để inline (default 35 bytes)
-XX:FreqInlineSize=325               // inline hot method lớn hơn

// Tại sao quan trọng?
// 1. Loại bỏ stack frame overhead
// 2. Cho phép optimizations khác (escape analysis, constant folding)
// 3. Getters/setters thường được inline → truy cập field hiệu quả như trực tiếp
```

### 2. Escape Analysis
Phân tích xem object có "thoát ra" khỏi method không:

```java
// Code gốc
public Point sum(Point a, Point b) {
    return new Point(a.x + b.x, a.y + b.y); // Point có escape không?
}

// Nếu caller dùng:
void caller() {
    Point result = sum(p1, p2);
    System.out.println(result.x + result.y); // result không escape ra ngoài method!
}

// Sau Escape Analysis:
// Object Point không cần allocate trên Heap!
// JIT có thể: Stack Allocation hoặc Scalar Replacement
void caller() {
    int x = p1.x + p2.x; // scalar replacement – không tạo Point object!
    int y = p1.y + p2.y;
    System.out.println(x + y);
}
```

```java
-XX:+DoEscapeAnalysis    // ON by default
-XX:+EliminateAllocations // stack/scalar allocation
```

**Hệ quả**: nhiều short-lived objects thực tế không được allocate trên heap → GC pressure giảm.

### 3. Loop Optimizations

**Loop Unrolling**:
```java
// Trước:
for (int i = 0; i < 8; i++) { process(arr[i]); }

// Sau unrolling (giảm branch overhead):
process(arr[0]); process(arr[1]); process(arr[2]); process(arr[3]);
process(arr[4]); process(arr[5]); process(arr[6]); process(arr[7]);
```

**Loop Vectorization (SIMD)**:
```java
// JIT có thể dùng CPU SIMD instructions
for (int i = 0; i < n; i++) { result[i] = a[i] + b[i]; }
// → xử lý 4-8 phần tử cùng lúc với AVX/SSE instructions
```

**Loop Hoisting**:
```java
// Trước:
for (int i = 0; i < arr.length; i++) { // arr.length trong loop condition
    process(arr[i]);
}
// Sau: JIT biết arr.length không đổi → hoist ra ngoài loop
int len = arr.length;
for (int i = 0; i < len; i++) { process(arr[i]); }
```

### 4. Constant Folding & Propagation
```java
// Source
final int X = 10, Y = 20;
int result = X + Y; // compile time: JIT biết X+Y=30

// Compiled thành:
int result = 30; // constant folding
```

### 5. Dead Code Elimination
```java
if (false) { expensiveOperation(); } // JIT loại bỏ hoàn toàn

// Thực tế hơn:
boolean DEBUG = false; // effectively constant sau profiling
if (DEBUG) { log.debug("..."); } // eliminated!
```

### 6. On-Stack Replacement (OSR)
Thay thế đang-chạy method bằng compiled version **tại điểm giữa** (trong vòng lặp):
```java
// Long-running loop – JIT không đợi method kết thúc để compile
for (int i = 0; i < 1_000_000; i++) {
    // JVM phát hiện loop "hot" → compile → replace ngay tại loop iteration hiện tại
    heavyWork(i);
}
// Ký hiệu: %! trong -XX:+PrintCompilation output
```

### 7. Devirtualization
Biến virtual method call (tốn kém – cần vtable lookup) thành direct call hoặc inline:
```java
// Nếu JVM profiling thấy chỉ có 1 concrete type
interface Animal { void sound(); }
// Profile: 99% calls là Dog

// JVM generates:
if (animal instanceof Dog) {
    ((Dog) animal).sound(); // direct call, có thể inline
} else {
    animal.sound();         // fallback vtable
}
// → Bimorphic/Monomorphic inline cache
```

---

## How – Deoptimization

Khi JIT compile dựa trên assumption sau đó sai → **deoptimize** (quay về interpreter):

```java
// JIT: chỉ thấy Dog calls → devirtualize tới Dog.sound()
// Sau đó: Cat object được truyền vào
// JIT: deoptimize → quay interpreter → re-profile → compile lại với cả 2 type

// Dấu hiệu: % trong PrintCompilation output
// Performance: deopt là tốn kém, tránh type instability
```

---

## Components – GraalVM

**GraalVM** = JVM thế hệ tiếp theo, JIT compiler viết bằng Java:

```
HotSpot JVM:
  C1 (Java) + C2 (C++) → native code

GraalVM JIT:
  Graal Compiler (Java) thay thế C2 → native code
  → Tốt hơn cho inlining phức tạp, Partial Escape Analysis

GraalVM Native Image (AOT):
  Compile Java thành standalone executable
  → Không cần JVM tại runtime
  → Startup: ms thay vì giây (tốt cho containers, serverless)
  → Nhược: không có JIT optimizations tại runtime, reflection bị giới hạn
```

```bash
# Compile native image
native-image -jar myapp.jar myapp
./myapp  # chạy không cần JVM!

# JVM flags để dùng Graal JIT (trên HotSpot Java 11+)
-XX:+UnlockExperimentalVMOptions -XX:+UseJVMCICompiler
```

---

## How – JVM Profiling Tools

### Java Flight Recorder (JFR)
```java
// Profiling với JFR – low overhead (<2%)
-XX:+FlightRecorder -XX:StartFlightRecording=duration=60s,filename=profile.jfr

// Programmatic:
try (Recording recording = new Recording()) {
    recording.enable("jdk.CPUSample").withPeriod(Duration.ofMillis(10));
    recording.enable("jdk.GarbageCollection");
    recording.start();
    // do work
    recording.dump(Path.of("profile.jfr"));
}
// Open với: Java Mission Control (JMC)
```

### Async-Profiler
```bash
# CPU profiling, allocation profiling – sinh flame graph
./profiler.sh -d 30 -o flamegraph -f cpu-flame.html <PID>
./profiler.sh -e alloc -d 30 -o flamegraph -f alloc-flame.html <PID>
```

### JVM Diagnostic Flags
```bash
# Print JIT compilation
-XX:+PrintCompilation

# Print inlining decisions
-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining

# Print assembly (native code)
-XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly

# Disable biased locking (nếu app tạo nhiều thread)
-XX:-UseBiasedLocking

# Enable string dedup (Java 8u20+)
-XX:+UseStringDeduplication
```

---

## When – Hiểu JIT để viết code hiệu quả hơn

### Warmup Time
```java
// JVM cần warmup trước khi JIT compile
// Benchmark: luôn warmup trước khi đo
@Benchmark // JMH framework
@Warmup(iterations = 5) // chạy 5 lần để warm up
@Measurement(iterations = 10)
public int myBenchmark() {
    return Integer.parseInt("12345");
}
```

### Giữ Monomorphic Call Sites
```java
// Tốt cho JIT: luôn dùng cùng 1 concrete type
void process(List<String> list) { // chỉ ArrayList được truyền vào
    list.forEach(this::handle);
}

// Kém hơn cho JIT: nhiều concrete type → megamorphic → khó devirtualize
void process(Collection<String> col) {
    col.forEach(this::handle); // ArrayList, LinkedList, TreeSet... → polymorphic
}
```

### Small Methods = Dễ Inline
```java
// JIT ưu tiên inline method nhỏ (≤35 bytes bytecode)
// Getter/setter thường được inline
public int getCount() { return count; } // 3 bytes bytecode → luôn inline

// Method lớn → không inline → overhead mỗi call
public void doEverything() { /* 200+ bytecode instructions */ } // không inline
```

---

## Compare – Interpreter vs JIT vs AOT

| | Interpreter | JIT | AOT (GraalVM Native) |
|--|-------------|-----|---------------------|
| Startup | Nhanh | Chậm (warmup) | Rất nhanh |
| Peak performance | Thấp | Rất cao | Trung bình-Cao |
| Memory | Thấp | Cao (JVM + code cache) | Thấp |
| Profiling-based | Không | Có (adaptive) | Không |
| Dynamic features | Có | Có | Hạn chế |
| Use case | Script, startup | Long-running server | Serverless, container |

---

## Trade-offs

| JIT | Ưu | Nhược |
|----|-----|-------|
| Adaptive optimization | Optimize dựa trên actual runtime behavior | Warmup time |
| Devirtualization | Loại bỏ overhead vtable | Deoptimization khi assumption sai |
| Escape Analysis | Giảm GC pressure | Phức tạp, không phải lúc nào cũng kích hoạt |
| Code cache | Compiled code lưu trong memory | `-XX:ReservedCodeCacheSize` cần đủ lớn |

---

## Real-world Usage (Production)

### 1. JVM Tuning cho Low-latency
```bash
# Minimize JIT compilation pauses
-XX:+TieredCompilation
-XX:ReservedCodeCacheSize=512m   # đủ space cho compiled code
-XX:InitialCodeCacheSize=256m

# GraalVM JIT cho better peak performance
-XX:+UnlockExperimentalVMOptions -XX:+UseJVMCICompiler

# Disable tiered để reach C4 faster (trade startup for throughput)
-XX:TieredStopAtLevel=4
```

### 2. JMH Microbenchmark (đúng cách)
```java
@State(Scope.Benchmark)
public class StringBenchmark {
    private String str = "hello world";

    @Benchmark
    @BenchmarkMode(Mode.AverageTime)
    @OutputTimeUnit(TimeUnit.NANOSECONDS)
    public int stringLength() {
        return str.length(); // JIT sẽ inline String.length() → field access
    }

    @Benchmark
    public String stringUpperCase() {
        return str.toUpperCase(); // tạo object mới mỗi lần → GC pressure
    }
}
// Chạy: java -jar benchmarks.jar StringBenchmark
```

### 3. Code Cache Exhaustion Warning
```bash
# Nếu thấy: "CodeCache is full. Compiler has been disabled."
# Fix:
-XX:ReservedCodeCacheSize=256m  # tăng code cache
-XX:+UseCodeCacheFlushing        # enable flushing khi đầy (trade performance)
```

---

## Ghi chú – Chủ đề tiếp theo

> Hoàn thành: JVM Internals (ClassLoader + JIT)
>
> Chủ đề pending trong roadmap:
> - **Spring Framework**: IoC Container, DI, AOP, Spring Boot auto-configuration
> - **JDBC & JPA / Hibernate**: N+1 problem, lazy/eager loading, transaction management
> - **Java Modules (JPMS)**: module-info.java, exports, requires, opens
> - **Modern Java (16-21)**: Records, Sealed Classes, Pattern Matching, Virtual Threads (Project Loom)
> - **Reactive Programming**: Project Reactor (Mono, Flux), WebFlux, backpressure
