# Java Performance Tuning & Profiling

## Mục lục
1. [JVM Tuning – Key Flags](#1-jvm-tuning--key-flags)
2. [GC Tuning – Garbage Collector Selection](#2-gc-tuning--garbage-collector-selection)
3. [JFR & JMC – Java Flight Recorder](#3-jfr--jmc--java-flight-recorder)
4. [async-profiler – CPU & Memory Profiling](#4-async-profiler--cpu--memory-profiling)
5. [JMH – Microbenchmarking](#5-jmh--microbenchmarking)
6. [Common Performance Anti-patterns](#6-common-performance-anti-patterns)
7. [HikariCP & Database Performance](#7-hikaricp--database-performance)
8. [Memory Optimization Patterns](#8-memory-optimization-patterns)

---

## 1. JVM Tuning – Key Flags

### 1.1 Memory Flags

```bash
# ── Heap ──────────────────────────────────────────────────────────────────
-Xms2g                          # initial heap size (set = Xmx to avoid resize)
-Xmx4g                          # max heap size
-XX:MaxRAMPercentage=75.0       # heap = 75% of container RAM (Docker-friendly)
-XX:InitialRAMPercentage=50.0   # initial heap = 50% of RAM
-XX:UseContainerSupport         # use container memory limits (default: true since Java 10)

# ── Stack ──────────────────────────────────────────────────────────────────
-Xss512k                        # thread stack size (default 512k-1m)
                                 # reduce for apps with many threads

# ── Metaspace ─────────────────────────────────────────────────────────────
-XX:MetaspaceSize=256m          # initial metaspace (trigger first GC)
-XX:MaxMetaspaceSize=512m       # cap metaspace (avoid runaway growth)
                                 # default: unlimited (can OOM system)

# ── Compressed OOPs (pointers) ────────────────────────────────────────────
# Auto-enabled for heap < 32GB:
-XX:+UseCompressedOops          # 4-byte object pointers vs 8-byte (saves ~30% heap)
-XX:+UseCompressedClassPointers # 4-byte class pointers

# ── Large Pages ───────────────────────────────────────────────────────────
-XX:+UseLargePages              # 2MB pages instead of 4KB (reduces TLB misses)
-XX:LargePageSizeInBytes=2m
```

### 1.2 Diagnostic Flags

```bash
# ── GC Logging (Java 9+) ─────────────────────────────────────────────────
-Xlog:gc*:file=gc.log:time,uptime,level,tags:filecount=5,filesize=20m
# Output: [2024-01-01T10:00:00][0.123s][info][gc] GC(0) Pause Young...

# Simpler:
-Xlog:gc:stdout                 # log to stdout
-Xlog:gc+heap:file=gc.log       # gc + heap size info

# ── OOM Heap Dump ─────────────────────────────────────────────────────────
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/dumps/heap.hprof
-XX:+ExitOnOutOfMemoryError     # kill process on OOM (let orchestrator restart)

# ── JIT compilation ───────────────────────────────────────────────────────
-XX:+PrintCompilation           # print JIT compiled methods (verbose)
-XX:CompileThreshold=1000       # calls before JIT compile (default 10000)
-XX:+TieredCompilation          # tiered C1+C2 (default true)

# ── Class Loading ──────────────────────────────────────────────────────────
-verbose:class                  # print class loading events
-XX:+TraceClassLoading
```

### 1.3 Production-Recommended JVM Flags

```bash
# Java 21 production configuration:
java \
  -Xms2g -Xmx2g \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+UseZGC \                          # or G1GC for Java 17+
  -XX:MaxMetaspaceSize=256m \
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/dumps/heap.hprof \
  -XX:+ExitOnOutOfMemoryError \
  -Xlog:gc*:file=/logs/gc.log:time,uptime:filecount=5,filesize=20m \
  -Dfile.encoding=UTF-8 \
  -Djava.security.egd=file:/dev/./urandom \  # faster SecureRandom on Linux
  -Djdk.nio.maxCachedBufferSize=262144 \     # limit NIO buffer cache
  --enable-preview \                          # for preview features
  -jar app.jar
```

---

## 2. GC Tuning – Garbage Collector Selection

### 2.1 GC Selection Guide

```
G1GC (default Java 9+):
  Good for: most applications, heap 4GB–32GB
  Latency:  ~10-200ms pauses
  -XX:+UseG1GC
  -XX:MaxGCPauseMillis=200      # target pause (G1 tries to meet this)
  -XX:G1HeapRegionSize=16m      # region size (1m-32m, power of 2)
  -XX:G1NewSizePercent=20       # young gen min %
  -XX:G1MaxNewSizePercent=40    # young gen max %
  -XX:InitiatingHeapOccupancyPercent=45  # trigger concurrent mark

ZGC (Java 15+ production, Java 21 generational ZGC):
  Good for: low-latency, large heaps (>32GB), cloud-native
  Latency:  <1ms pauses (sub-millisecond)
  -XX:+UseZGC
  -XX:+ZGenerational            # Java 21: generational ZGC (faster)
  -XX:SoftMaxHeapSize=3g        # soft limit (GC more aggressive near limit)

Shenandoah GC (JDK 12+):
  Good for: low-latency alternative to ZGC
  Latency:  <10ms pauses
  -XX:+UseShenandoahGC
  -XX:ShenandoahGCHeuristics=adaptive

Serial GC:
  Good for: CLI tools, small apps, single-core containers
  -XX:+UseSerialGC

Parallel GC (Java 8 default):
  Good for: batch processing, throughput-focused
  -XX:+UseParallelGC
  -XX:ParallelGCThreads=4
```

### 2.2 GC Tuning Workflow

```bash
# Step 1: Identify GC issues
# Parse gc.log with GCEasy (online tool) or gcviewer

# Common GC problems:
# ① High pause frequency → reduce allocation rate
# ② Long pauses → increase heap or switch GC
# ③ Frequent Full GC → memory leak or insufficient heap
# ④ Humongous allocations in G1 → avoid large object allocations

# Step 2: jstat for live monitoring
jstat -gc <pid> 1000           # GC stats every 1 second
jstat -gcutil <pid> 1000       # GC percentage utilization
# Output: S0C S1C S0U S1U EC EU OC OU MC MU YGC YGCT FGC FGCT GCT

# Step 3: Heap analysis
jmap -heap <pid>               # heap summary
jmap -histo <pid> | head -30   # object histogram (top 30 by count)
jmap -dump:format=b,file=heap.hprof <pid>  # full heap dump

# Analyze heap dump with Eclipse MAT or VisualVM:
# Look for: dominator tree, shortest GC roots path, leak suspects
```

---

## 3. JFR & JMC – Java Flight Recorder

### 3.1 Java Flight Recorder

```bash
# JFR: low-overhead profiler built into JVM (< 1-2% overhead)
# Records: GC, CPU, heap, threads, I/O, JIT, network, locks, exceptions

# ── Start recording with JVM flags ───────────────────────────────────────
java \
  -XX:StartFlightRecording=duration=60s,filename=recording.jfr,settings=profile \
  -jar app.jar

# ── Start recording on running process (jcmd) ─────────────────────────────
jcmd <pid> JFR.start name=myrecording settings=profile maxsize=100m
jcmd <pid> JFR.dump name=myrecording filename=recording.jfr
jcmd <pid> JFR.stop name=myrecording

# ── Continuous recording (for production) ─────────────────────────────────
jcmd <pid> JFR.start \
  name=continuous \
  settings=default \
  maxage=5m \           # keep last 5 minutes in ring buffer
  maxsize=128m          # max ring buffer size

# Dump when incident occurs:
jcmd <pid> JFR.dump name=continuous filename=incident-$(date +%s).jfr

# ── Settings profiles ─────────────────────────────────────────────────────
# default: minimal overhead, suitable for production
# profile: detailed profiling, ~2% overhead
# Custom: create .jfc file in JMC
```

### 3.2 Analyzing JFR with jcmd/code

```java
// Parse JFR programmatically (Java 14+):
Path recording = Path.of("recording.jfr");

try (RecordingFile rf = new RecordingFile(recording)) {
    while (rf.hasMoreEvents()) {
        RecordedEvent event = rf.readEvent();
        if (event.getEventType().getName().equals("jdk.GarbageCollection")) {
            Duration pause = event.getDuration("pauseTime");
            System.out.printf("GC pause: %dms%n", pause.toMillis());
        }
    }
}

// Filter specific event types:
List<RecordedEvent> gcEvents = RecordingFile.readAllEvents(recording).stream()
    .filter(e -> e.getEventType().getName().contains("GC"))
    .filter(e -> e.getDuration().toMillis() > 100)
    .toList();
```

---

## 4. async-profiler – CPU & Memory Profiling

```bash
# async-profiler: low-overhead sampling profiler using AsyncGetCallTrace
# Avoids safe-point bias (unlike JVM built-in sampling)

# Install:
wget https://github.com/async-profiler/async-profiler/releases/download/v3.0/async-profiler-3.0-linux-x64.tar.gz
tar xzf async-profiler-3.0-linux-x64.tar.gz

# ── CPU profiling ─────────────────────────────────────────────────────────
./asprof -d 30 -f cpu.html <pid>           # 30s CPU profile → flamegraph HTML
./asprof -e cpu -d 30 <pid>               # explicit cpu event

# ── Memory allocation profiling ───────────────────────────────────────────
./asprof -e alloc -d 30 -f alloc.html <pid>   # allocation flamegraph

# ── Lock contention profiling ─────────────────────────────────────────────
./asprof -e lock -d 30 -f lock.html <pid>

# ── Wall-clock profiling (includes blocking time) ─────────────────────────
./asprof -e wall -d 30 -f wall.html <pid>

# ── Output formats ────────────────────────────────────────────────────────
-f profile.html      # interactive flamegraph (most useful)
-f profile.svg       # SVG flamegraph
-o collapsed         # collapsed text format (for other tools)

# ── Profile from start ────────────────────────────────────────────────────
java -agentpath:/path/to/libasyncProfiler.so=start,event=cpu,file=profile.html -jar app.jar

# Reading flamegraph:
# X-axis: time (wider = more CPU)
# Y-axis: call stack depth (bottom = main, top = leaf methods)
# Colors: meaningless (random for readability)
# Look for: wide plateaus at top = hot methods
```

### 4.2 jcmd – JVM Diagnostics

```bash
# List all JVM processes:
jcmd                           # or: jps -l

# Available commands for process:
jcmd <pid> help

# Thread dump:
jcmd <pid> Thread.print        # text thread dump
jcmd <pid> Thread.print -l     # with locks

# Heap info:
jcmd <pid> VM.native_memory    # native memory usage (NMT)
jcmd <pid> GC.heap_info        # heap usage summary
jcmd <pid> GC.heap_dump /tmp/heap.hprof

# JVM flags:
jcmd <pid> VM.flags            # all JVM flags (default + set)
jcmd <pid> VM.command_line     # original command line

# System properties:
jcmd <pid> VM.system_properties

# Class histogram:
jcmd <pid> GC.class_histogram | head -30

# Force GC (use carefully in production):
jcmd <pid> GC.run
```

---

## 5. JMH – Microbenchmarking

### 5.1 Setup & Basic Benchmark

```java
/* pom.xml:
<dependency>
  <groupId>org.openjdk.jmh</groupId>
  <artifactId>jmh-core</artifactId>
  <version>1.37</version>
</dependency>
<dependency>
  <groupId>org.openjdk.jmh</groupId>
  <artifactId>jmh-generator-annprocess</artifactId>
  <version>1.37</version>
  <scope>provided</scope>
</dependency>
*/

@BenchmarkMode(Mode.AverageTime)        // average time per operation
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Benchmark)                 // one instance per benchmark run
@Fork(value = 2)                        // run in 2 separate JVM forks (avoid JIT bias)
@Warmup(iterations = 3, time = 1)       // 3 warmup iterations × 1 second each
@Measurement(iterations = 5, time = 1) // 5 measurement iterations × 1 second each
public class StringBenchmark {

    private String input;
    private List<String> words;

    @Setup(Level.Iteration)            // run before each iteration
    public void setup() {
        input = "The quick brown fox jumps over the lazy dog";
        words = Arrays.asList(input.split(" "));
    }

    // ── Benchmark methods ─────────────────────────────────────────────────
    @Benchmark
    public String concatWithPlus() {
        String result = "";
        for (String word : words) result += word + " ";
        return result;
    }

    @Benchmark
    public String concatWithBuilder() {
        var sb = new StringBuilder();
        for (String word : words) sb.append(word).append(' ');
        return sb.toString();
    }

    @Benchmark
    public String joinWithStream() {
        return String.join(" ", words);
    }

    // Prevent JIT from optimizing away dead code:
    @Benchmark
    public int hashCode_withBlackhole(Blackhole bh) {
        int hash = 0;
        for (String word : words) hash += word.hashCode();
        bh.consume(hash);  // prevent elimination
        return hash;
    }
}

// Run: mvn package -DskipTests && java -jar target/benchmarks.jar
// Or programmatically:
public static void main(String[] args) throws RunnerException {
    Options opt = new OptionsBuilder()
        .include(StringBenchmark.class.getSimpleName())
        .build();
    new Runner(opt).run();
}
```

### 5.2 Benchmark Modes

```java
@BenchmarkMode(Mode.Throughput)          // ops/second (higher = better)
@BenchmarkMode(Mode.AverageTime)         // average time per op (lower = better)
@BenchmarkMode(Mode.SampleTime)          // distribution of time per op
@BenchmarkMode(Mode.SingleShotTime)      // single invocation (cold code)
@BenchmarkMode({Mode.Throughput, Mode.AverageTime}) // multiple modes

// State scopes:
@State(Scope.Benchmark) // shared across all threads in benchmark
@State(Scope.Thread)    // per-thread state (default for parallel)
@State(Scope.Group)     // per group of threads

// Parameterized benchmarks:
@Param({"100", "1000", "10000"})
private int size;

@Param({"HashMap", "TreeMap", "LinkedHashMap"})
private String mapType;

// Result: separate benchmark for each combination of params
```

### 5.3 JMH Pitfalls

```java
// ❌ Dead code elimination: JIT may eliminate benchmark body
@Benchmark
public void badBenchmark() {
    int unused = computeExpensiveResult(); // JIT eliminates: result never used!
}

// ✅ Return result or use Blackhole:
@Benchmark
public int goodBenchmark() {
    return computeExpensiveResult(); // JMH uses return value
}

@Benchmark
public void goodWithBlackhole(Blackhole bh) {
    bh.consume(computeExpensiveResult());
}

// ❌ Constant folding: JIT precomputes constant expressions
@Benchmark
public int constantFolding() {
    return 2 + 2; // JIT replaces with return 4 at compile time!
}

// ✅ Use @State fields:
@State(Scope.Benchmark)
public class BenchState {
    int x = 2, y = 2;
}

@Benchmark
public int noFolding(BenchState state) {
    return state.x + state.y;
}

// ❌ False sharing: adjacent fields on same cache line
@State(Scope.Thread)
public class BadState {
    long field1;   // same cache line as field2!
    long field2;
}

// ✅ Pad fields to separate cache lines:
@State(Scope.Thread)
public class GoodState {
    @sun.misc.Contended  // Java 8+: pad to separate cache line
    long field1;
    @sun.misc.Contended
    long field2;
}
```

---

## 6. Common Performance Anti-patterns

### 6.1 Memory Allocation

```java
// ❌ String concatenation in loop (creates N intermediate Strings):
String result = "";
for (String s : list) result += s;  // O(n²) allocations

// ✅ StringBuilder:
var sb = new StringBuilder(list.stream().mapToInt(String::length).sum());
list.forEach(sb::append);
return sb.toString();

// ❌ Boxing/unboxing in hot path:
Map<String, Integer> counter = new HashMap<>();
counter.put(key, counter.getOrDefault(key, 0) + 1);  // Integer boxing

// ✅ Primitive maps (Eclipse Collections or avoiding boxing):
var counter = new HashMap<String, int[]>();  // int[] as mutable counter
counter.computeIfAbsent(key, k -> new int[1])[0]++;

// ❌ Creating objects in tight loops:
for (long i = 0; i < 1_000_000; i++) {
    var date = new Date(timestamp);  // allocation in loop
    process(date);
}

// ✅ Reuse objects:
var calendar = Calendar.getInstance();  // reuse outside loop
for (long i = 0; i < 1_000_000; i++) {
    calendar.setTimeInMillis(timestamp);
    process(calendar);
}

// ❌ Using Stream for tiny collections (overhead > benefit):
List.of(1, 2, 3).stream().filter(x -> x > 1).findFirst();

// ✅ Simple loop for small collections:
for (int x : List.of(1, 2, 3)) { if (x > 1) return x; }
```

### 6.2 Collection Usage

```java
// ❌ Wrong initial capacity (resize = rehash = O(n)):
Map<String, User> users = new HashMap<>();  // default capacity 16

// ✅ Pre-size when count known:
Map<String, User> users = new HashMap<>(expectedCount * 4 / 3 + 1);
// or: HashMap.newHashMap(expectedCount) — Java 19+

// ❌ LinkedList for indexed access (O(n) get):
List<String> list = new LinkedList<>();
String item = list.get(500);  // O(n) traversal!

// ✅ ArrayList for indexed access, LinkedList only for deque operations

// ❌ contains() on List (O(n)):
List<String> items = List.of("a", "b", "c", ...); // large list
if (items.contains(target)) { ... }

// ✅ HashSet for contains (O(1)):
Set<String> items = new HashSet<>(originalList);
if (items.contains(target)) { ... }

// ❌ toArray() + Arrays.sort + binarySearch on every call:
// ✅ Cache sorted array or use TreeSet/NavigableSet

// ❌ Stream.collect(toList()) inside loop (N² allocations):
for (Item item : items) {
    List<Tag> tags = item.getTags().stream().collect(toList());
    ...
}
// ✅ Use item.getTags() directly if it returns List already
```

### 6.3 Synchronization

```java
// ❌ synchronized on expensive method with fine-grained data:
synchronized Map<String, Order> orders = new HashMap<>();
// Single lock for all keys → contention

// ✅ ConcurrentHashMap (fine-grained lock per segment):
ConcurrentHashMap<String, Order> orders = new ConcurrentHashMap<>();

// ❌ Lock held during I/O:
synchronized (lock) {
    String data = httpClient.get(url); // holds lock during network!
}

// ✅ Fetch outside lock:
String data = httpClient.get(url);  // no lock
synchronized (lock) { cache.put(url, data); }

// ❌ Double-checked locking without volatile:
if (instance == null) {
    synchronized (this) {
        if (instance == null) {
            instance = new Singleton(); // reorder risk without volatile!
        }
    }
}

// ✅ volatile guarantees visibility:
private volatile Singleton instance;
```

---

## 7. HikariCP & Database Performance

```java
// Connection pool tuning (most impactful DB performance lever):
spring:
  datasource:
    hikari:
      # Pool size: Deadpool formula → pool_size = (cpu_cores * 2) + effective_spindle_count
      maximum-pool-size: 10        # Don't set too large! HikariCP recommends < 20
      minimum-idle: 5
      connection-timeout: 30000    # 30s wait for connection (throw if exceeded)
      idle-timeout: 600000         # 10min: remove idle connections
      max-lifetime: 1800000        # 30min: max connection lifetime (rotate before DB timeout)
      keepalive-time: 30000        # 30s: keepalive to prevent firewall closing idle
      validation-timeout: 5000     # 5s: connection validation timeout
      leak-detection-threshold: 60000  # log if connection held > 60s (debug leak)

// Pool size anti-patterns:
// ❌ max-pool-size: 100 for 10-core server → context switching overhead
// ✅ 10 threads × full CPU core = better than 100 threads × context switches

// Monitor pool usage:
HikariDataSource ds = (HikariDataSource) dataSource;
HikariPoolMXBean pool = ds.getHikariPoolMXBean();
int active = pool.getActiveConnections();   // currently in use
int idle = pool.getIdleConnections();       // available
int waiting = pool.getThreadsAwaitingConnection(); // waiting for connection
// Alert if waiting > 0 for extended period → increase pool size or optimize queries
```

---

## 8. Memory Optimization Patterns

```java
// ── Object Pooling (for expensive-to-create objects) ─────────────────────
// Use for: ByteBuffer, SSL engines, parsers, not for simple objects

// Apache Commons Pool2:
GenericObjectPool<Connection> pool = new GenericObjectPool<>(
    new BasePooledObjectFactory<Connection>() {
        @Override public Connection create() { return new Connection(host); }
        @Override public PooledObject<Connection> wrap(Connection conn) {
            return new DefaultPooledObject<>(conn);
        }
        @Override public boolean validateObject(PooledObject<Connection> p) {
            return p.getObject().isAlive();
        }
    },
    new GenericObjectPoolConfig<>() {{
        setMaxTotal(20);
        setMinIdle(5);
        setTestOnBorrow(true);
    }}
);

// ── String Interning ──────────────────────────────────────────────────────
// ✅ Use for: repeated strings from external sources (CSV, DB results)
// String.intern() puts in String Pool (native memory, not heap)
String country = record.getCountry().intern();  // deduplicate

// Java 21: StringDeduplication (G1GC):
-XX:+UseG1GC -XX:+UseStringDeduplication
// G1 deduplicates heap Strings (background thread, only live objects)

// ── Off-heap Memory ───────────────────────────────────────────────────────
// For large datasets not subject to GC:
ByteBuffer buffer = ByteBuffer.allocateDirect(1024 * 1024 * 100); // 100MB off-heap
// Access via buffer.get/put, not GC-managed

// Java 21 Foreign Memory API:
try (Arena arena = Arena.ofConfined()) {
    MemorySegment segment = arena.allocate(1024 * 1024 * 100); // 100MB
    // segment.set(ValueLayout.JAVA_INT, 0, 42);
    // Automatically freed when Arena is closed
}

// ── Weak/Soft References ──────────────────────────────────────────────────
// WeakReference: cleared on next GC (use for caches keyed by object identity)
WeakHashMap<Widget, WidgetCache> cache = new WeakHashMap<>();
// When Widget is GC'd, entry auto-removed from map

// SoftReference: cleared only when OOM (use for size-bounded caches)
SoftReference<byte[]> largeData = new SoftReference<>(loadData());
byte[] data = largeData.get(); // may return null if GC'd
if (data == null) data = loadData(); // reload if GC'd
```

---

## Ghi chú – Keywords

- **Keywords**: JVM ergonomics, -XX:MaxRAMPercentage (containers), G1GC MaxGCPauseMillis, ZGC generational, JFR (Java Flight Recorder), JMC (Java Mission Control), async-profiler flamegraph, safepoint bias, jcmd diagnostics, JMH Blackhole dead code elimination, HikariCP pool sizing formula, String.intern() deduplication, ByteBuffer.allocateDirect(), Foreign Memory API (Project Panama), MemorySegment Arena, @Contended false sharing, ConcurrentHashMap vs synchronizedMap, connection leak detection
