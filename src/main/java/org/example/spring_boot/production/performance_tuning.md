# Performance Tuning – Tối ưu hiệu năng Spring Boot

## What – Performance Tuning là gì?

Quá trình tối ưu hóa ứng dụng để đạt **throughput cao, latency thấp, memory hiệu quả** trong production. Áp dụng theo thứ tự: measure → identify bottleneck → optimize → measure again.

```
Golden Rule: "Don't optimize without profiling."
Tool: JFR (Java Flight Recorder), Async Profiler, YourKit, JVisualVM
```

---

## HikariCP – Connection Pool Tuning

HikariCP là default connection pool của Spring Boot. Sai cấu hình → DB bottleneck.

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20         # Tối đa 20 connections
      minimum-idle: 5               # Giữ ít nhất 5 idle connections
      connection-timeout: 30000     # 30s chờ lấy connection, sau đó throw exception
      idle-timeout: 600000          # Remove idle connection sau 10 phút
      max-lifetime: 1800000         # Retire connection sau 30 phút (tránh stale)
      keepalive-time: 60000         # Ping DB mỗi 60s (giữ connection alive)
      pool-name: HikariPool-orders
      data-source-properties:
        cachePrepStmts: true
        prepStmtCacheSize: 250
        prepStmtCacheSqlLimit: 2048
        useServerPrepStmts: true    # PostgreSQL: server-side prepared statements
```

### Connection Pool Sizing Formula

```
Pool size = Nthreads × (Cwait / Cservice) + 1

Nthreads = max concurrent threads (tomcat max-threads)
Cwait/Cservice = ratio of I/O wait to actual processing time

Ví dụ:
  Tomcat: 200 threads
  DB query: 90% time waiting, 10% processing → Cwait/Cservice = 9
  Pool size = 200 × 9 + 1 = 1801 connections → WAY TOO HIGH

Thực tế: fewer connections = better (context switch, lock contention)
PostgreSQL khuyến nghị: 100 connections max per instance
→ Dùng PgBouncer (connection pooler) trước PostgreSQL

Pragmatic: start with pool-size = CPU cores × 2 + disk spindles
```

### Monitor HikariCP

```promql
# Pool utilization (should be < 80%)
hikaricp_connections_active / hikaricp_connections_max

# Waiting for connection (should be 0)
hikaricp_connections_pending > 0

# Connection timeout rate
rate(hikaricp_connections_timeout_total[5m]) > 0
```

---

## Thread Pool Tuning

### Tomcat (MVC)

```yaml
server:
  tomcat:
    threads:
      max: 200          # Default: 200. Tăng nếu nhiều concurrent requests
      min-spare: 10     # Keep alive threads
    max-connections: 8192
    accept-count: 100   # Queue size khi tất cả threads bận
    connection-timeout: 20000
```

### Virtual Threads (Java 21) – Thay thế thread pool

```yaml
spring:
  threads:
    virtual:
      enabled: true   # Tomcat dùng virtual threads – hầu hết không cần tune thread pool
```

### @Async Thread Pool

```java
@Bean(name = "taskExecutor")
public ThreadPoolTaskExecutor taskExecutor() {
    int cpuCores = Runtime.getRuntime().availableProcessors();
    
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(cpuCores * 2);        // IO-bound: 2x CPU cores
    executor.setMaxPoolSize(cpuCores * 4);         // max burst
    executor.setQueueCapacity(500);                 // queue buffer
    executor.setKeepAliveSeconds(60);
    executor.setRejectedExecutionHandler(
        new ThreadPoolExecutor.CallerRunsPolicy()   // backpressure: caller runs if full
    );
    return executor;
}
```

---

## JVM Tuning

### Garbage Collection

```bash
# G1GC (default Java 9+, good general-purpose)
java -XX:+UseG1GC \
     -Xms512m \                    # Initial heap (same as Xmx to avoid resize)
     -Xmx2g \                      # Max heap
     -XX:MaxGCPauseMillis=200 \    # Target max pause 200ms
     -XX:G1HeapRegionSize=16m \    # G1 region size (16MB for large heap)
     -XX:InitiatingHeapOccupancyPercent=45 \
     -jar app.jar

# ZGC (Java 15+, ultra-low pause < 1ms, good for latency-sensitive)
java -XX:+UseZGC \
     -XX:SoftMaxHeapSize=2g \      # Soft limit, ZGC can go above if needed
     -XX:ZUncommitDelay=300 \
     -jar app.jar

# Shenandoah (Red Hat, similar to ZGC)
java -XX:+UseShenandoahGC -jar app.jar
```

### JVM Flags cho Production

```bash
java \
  # Heap
  -Xms1g -Xmx2g \
  
  # GC Logging
  -Xlog:gc*:file=/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=50m \
  
  # OOM Actions
  -XX:+HeapDumpOnOutOfMemoryError \
  -XX:HeapDumpPath=/dumps/heap-dump.hprof \
  -XX:+ExitOnOutOfMemoryError \          # restart pod on OOM
  
  # JIT
  -XX:+OptimizeStringConcat \
  -XX:+UseCompressedOops \              # 32-bit object refs trong 64-bit JVM (heap < 32GB)
  
  # JFR (Java Flight Recorder) - low overhead profiling
  -XX:+FlightRecorder \
  -XX:StartFlightRecording=duration=60s,filename=/tmp/app.jfr \
  
  # Container awareness (Java 8u191+, Java 11+)
  -XX:+UseContainerSupport \            # read CPU/memory limits from cgroup
  -XX:MaxRAMPercentage=75.0 \           # use 75% of container memory as max heap
  
  -jar app.jar
```

### Container Memory Settings

```yaml
# Kubernetes: set resource limits
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "1000m"

# JVM: -XX:MaxRAMPercentage=75 → heap = 768Mi
# Remaining 256Mi for: Metaspace, code cache, thread stacks, off-heap

# Metaspace (PermGen replacement)
-XX:MetaspaceSize=128m          # initial
-XX:MaxMetaspaceSize=256m       # max (prevent unlimited growth)
```

---

## GraalVM Native Image

Compile Spring Boot app thành **native binary** – cực nhanh startup, ít memory, phù hợp serverless.

```xml
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
</plugin>
```

```bash
# Build native image (cần GraalVM JDK)
./mvnw -Pnative native:compile

# Hoặc Docker build (không cần GraalVM locally)
./mvnw spring-boot:build-image -Pnative

# So sánh
JVM startup: 3-5 seconds, 512MB RAM
Native startup: 50-100ms, 50-100MB RAM
```

### Native Image Limitations

```
❌ Reflection phải khai báo trước (native-image.properties)
❌ Dynamic class loading không hỗ trợ
❌ Build time chậm (5-10 phút vs 30s JVM)
❌ Không hỗ trợ tất cả libraries (check GraalVM compatibility)
✅ Spring Boot 3.x có native image support built-in
✅ Hầu hết Spring libraries đã thêm GraalVM metadata
```

```java
// Nếu dùng reflection, khai báo hint
@Configuration
@ImportRuntimeHints(OrderRuntimeHints.class)
public class OrderConfig {}

public class OrderRuntimeHints implements RuntimeHintsRegistrar {
    @Override
    public void registerHints(RuntimeHints hints, ClassLoader classLoader) {
        hints.reflection().registerType(OrderEvent.class,
            MemberCategory.INVOKE_PUBLIC_CONSTRUCTORS,
            MemberCategory.INVOKE_PUBLIC_METHODS);
        hints.resources().registerPattern("templates/*.html");
    }
}
```

---

## Query Optimization

```java
// 1. Read-only transactions (hint to Hibernate: flush = never, optimization)
@Transactional(readOnly = true)
public List<Order> getOrders(Long tenantId) {
    return orderRepo.findByTenantId(tenantId);
}

// 2. Projections thay vì full entity
// ❌ Load 50 columns để hiển thị 3 columns
List<Order> allColumns = orderRepo.findAll();

// ✅ Chỉ load columns cần
List<OrderSummary> summaries = orderRepo.findSummariesByTenantId(tenantId);

// 3. Batch fetch (tránh N+1)
spring:
  jpa:
    properties:
      hibernate:
        default_batch_fetch_size: 50

// 4. Second-level cache (Hibernate L2)
@Entity
@Cache(usage = CacheConcurrencyStrategy.READ_WRITE)
public class Product {}

spring:
  jpa:
    properties:
      hibernate:
        cache:
          use_second_level_cache: true
          region.factory_class: org.hibernate.cache.jcache.JCacheRegionFactory
```

---

## HTTP Performance

```yaml
server:
  # Compression
  compression:
    enabled: true
    mime-types: application/json,application/xml,text/html,text/plain
    min-response-size: 1024  # chỉ compress response > 1KB

  # HTTP/2
  http2:
    enabled: true

  # Keep-alive
  tomcat:
    keep-alive-timeout: 20000
    max-keep-alive-requests: 1000
```

```java
// Response caching headers
@GetMapping("/products/{id}")
public ResponseEntity<Product> getProduct(@PathVariable Long id) {
    Product product = productService.getProduct(id);
    return ResponseEntity.ok()
        .cacheControl(CacheControl.maxAge(30, TimeUnit.MINUTES)
            .cachePublic()
            .mustRevalidate())
        .eTag(String.valueOf(product.getVersion()))
        .body(product);
}
```

---

## Profiling & Benchmarking

```bash
# Java Flight Recorder (zero overhead profiling)
jcmd <pid> JFR.start duration=60s filename=app.jfr
# Analyze với JDK Mission Control (JMC)

# Async Profiler (flame graphs)
./profiler.sh -d 60 -f flame.html <pid>

# JMH (Java Microbenchmark Harness)
@Benchmark
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
public void benchmarkOrderCreation() {
    orderService.createOrder(testRequest);
}
```

---

## Trade-offs

| Optimization | Gain | Cost |
|-------------|------|------|
| Virtual Threads | High throughput | Java 21 required, pinning risk |
| GraalVM Native | Fast startup, low memory | Build time, reflection limits |
| Read-only TX | Hibernate optimization | No writes allowed |
| Second-level cache | Fewer DB queries | Stale data risk, complexity |
| Compression | Bandwidth reduction | CPU overhead |
| Connection pool increase | More concurrency | DB connection limit |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `production/production_patterns.md` – Graceful shutdown, health checks, deployment
- **Keywords:** Async Profiler, JFR (Java Flight Recorder), JMC (JDK Mission Control), JMH, Flame graph, Off-heap memory (Direct ByteBuffer), GC tuning G1 vs ZGC vs Shenandoah, CDS (Class Data Sharing), Spring AOT (Ahead-of-Time compilation), Layered JARs, BuildPacks, Class loader optimization
