# GraalVM Native Image – Java

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. GraalVM & Native Image Overview

### What – GraalVM Native Image là gì?
**GraalVM Native Image** là công nghệ AOT (Ahead-of-Time) compilation: biên dịch Java bytecode thành **native executable** tại build time, không cần JVM lúc runtime. Kết quả là binary chạy ngay lập tức, tiêu tốn ít RAM hơn nhiều so với JVM.

### How – Kiến trúc

```
Traditional JVM flow:
  Java source → javac → bytecode (.class) → JVM loads → JIT compiles → native code
  Runtime: JVM startup ~500ms-2s, JIT warmup ~minutes

Native Image flow:
  Java source → javac → bytecode → native-image (GraalVM) → native binary
  Build time: 2-10 minutes (static analysis + AOT compilation)
  Runtime: startup ~10-100ms, no JVM needed
```

```
native-image analysis phases:
  1. Points-to analysis   – determine what code is reachable
  2. Heap snapshotting    – capture initialized objects
  3. AOT compilation      – compile reachable code to machine code
  4. Image linking        – produce self-contained executable
```

### Why – Khi nào cần Native Image?
- **Serverless/FaaS**: cold start < 100ms thay vì 2-5s với JVM
- **CLI tools**: graalvm native-image tạo single binary (như `go build`)
- **Containers**: image size giảm từ 400MB → 50MB (no JDK)
- **Memory-constrained**: Kubernetes pods với 128MB limit

---

## 2. Setup & Build

### How – Installation

```bash
# Option 1: SDKMAN (recommended)
sdk install java 21.0.2-graal
sdk use java 21.0.2-graal

# Verify
java -version    # → GraalVM CE 21.0.2
native-image --version

# Option 2: Docker build (không cần install local)
docker run --rm -v "$(pwd)":/app -w /app \
  ghcr.io/graalvm/native-image-community:21 \
  native-image -jar target/app.jar
```

### How – Maven/Gradle Config

```xml
<!-- pom.xml – Native Maven Plugin -->
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
    <version>0.10.1</version>
    <extensions>true</extensions>
    <configuration>
        <imageName>order-service</imageName>
        <mainClass>com.example.OrderApplication</mainClass>
        <buildArgs>
            <!-- reduce image size by excluding debug info -->
            <buildArg>-O2</buildArg>
            <!-- static linking for scratch container -->
            <buildArg>--static</buildArg>
            <buildArg>--libc=musl</buildArg>
            <!-- quick build for dev (no optimization) -->
            <!-- <buildArg>-Ob</buildArg> -->
        </buildArgs>
        <metadataRepository>
            <enabled>true</enabled>   <!-- GraalVM metadata repo for popular libs -->
        </metadataRepository>
    </configuration>
</plugin>
```

```bash
# Build native image
./mvnw -Pnative native:compile

# Build + run tests as native
./mvnw -Pnative test

# Spring Boot: build OCI native image
./mvnw -Pnative spring-boot:build-image
# → Docker image: order-service:latest (~80MB vs ~400MB JVM)
```

---

## 3. Reflection & Dynamic Features

### What – Vấn đề với AOT

Native Image dùng **closed-world assumption**: chỉ include code reachable tại build time. Reflection, dynamic proxies, serialization, và resource loading phá vỡ assumption này.

```java
// Các feature cần config thêm:
Class.forName("com.example.OrderService")       // reflection
Method.invoke(...)                               // reflection
Proxy.newProxyInstance(...)                      // dynamic proxy
objectMapper.readValue(json, Order.class)        // Jackson reflection
@Transactional, @Cacheable (Spring AOP proxies)  // CGLIB proxy
getClass().getResourceAsStream("/config.yml")    // resource access
```

### How – Reflection Configuration

```json
// src/main/resources/META-INF/native-image/reflect-config.json
[
  {
    "name": "com.example.order.Order",
    "allDeclaredFields": true,
    "allDeclaredMethods": true,
    "allDeclaredConstructors": true
  },
  {
    "name": "com.example.order.OrderStatus",
    "allDeclaredFields": true,
    "allDeclaredMethods": true
  },
  {
    "name": "com.example.order.CreateOrderRequest",
    "allPublicConstructors": true,
    "allPublicFields": true,
    "allPublicMethods": true
  }
]
```

```json
// resource-config.json
{
  "resources": {
    "includes": [
      {"pattern": "application.yaml"},
      {"pattern": "db/migration/.*\\.sql"},
      {"pattern": "static/.*"}
    ]
  },
  "bundles": [
    {"name": "messages"}
  ]
}
```

```json
// proxy-config.json
[
  {
    "interfaces": [
      "com.example.order.OrderRepository",
      "org.springframework.data.jpa.repository.JpaRepository"
    ]
  }
]
```

### How – Native Hints (Spring AOT)

```java
// Spring 6+ / Spring Boot 3+ dùng AOT processing tự động
// Nhưng có thể thêm hints thủ công:

@Configuration
@ImportRuntimeHints(OrderApplication.OrderHints.class)
public class OrderApplication {

    static class OrderHints implements RuntimeHintsRegistrar {
        @Override
        public void registerHints(RuntimeHints hints, ClassLoader classLoader) {
            // Register reflection
            hints.reflection().registerType(Order.class,
                MemberCategory.INVOKE_DECLARED_CONSTRUCTORS,
                MemberCategory.INVOKE_PUBLIC_METHODS,
                MemberCategory.DECLARED_FIELDS);

            // Register resources
            hints.resources().registerPattern("data/*.json");

            // Register serialization
            hints.serialization().registerType(OrderEvent.class);

            // Register proxies
            hints.proxies().registerJdkProxy(OrderRepository.class);
        }
    }
}
```

```java
// Annotation-based hints
@RegisterReflectionForBinding({Order.class, OrderItem.class, OrderEvent.class})
@RegisterReflection(
    targets = {PaymentService.class},
    memberCategories = {MemberCategory.INVOKE_DECLARED_METHODS}
)
@SpringBootApplication
public class OrderApplication {
    public static void main(String[] args) {
        SpringApplication.run(OrderApplication.class, args);
    }
}
```

---

## 4. Tracing Agent – Auto-generate Config

### How – Java Agent tự động detect reflection calls

```bash
# Chạy app với tracing agent để generate config tự động
java -agentlib:native-image-agent=config-output-dir=src/main/resources/META-INF/native-image \
     -jar target/app.jar

# Chạy test suite để cover tất cả code paths
./run-integration-tests.sh

# Config tự động generated:
# META-INF/native-image/
#   reflect-config.json
#   proxy-config.json
#   resource-config.json
#   serialization-config.json
#   jni-config.json
```

```bash
# Merge với existing config
java -agentlib:native-image-agent=config-merge-dir=src/main/resources/META-INF/native-image \
     -jar target/app.jar
```

---

## 5. Spring Boot Native

### How – Spring AOT Processing

```xml
<!-- pom.xml – Spring Boot Native -->
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.2.0</version>
</parent>

<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
</dependencies>

<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <configuration>
                <image>
                    <name>order-service:native</name>
                    <builder>paketobuildpacks/builder-jammy-tiny</builder>
                    <env>
                        <BP_NATIVE_IMAGE>true</BP_NATIVE_IMAGE>
                        <BP_NATIVE_IMAGE_BUILD_ARGUMENTS>-O2</BP_NATIVE_IMAGE_BUILD_ARGUMENTS>
                    </env>
                </image>
            </configuration>
        </plugin>
        <plugin>
            <groupId>org.graalvm.buildtools</groupId>
            <artifactId>native-maven-plugin</artifactId>
        </plugin>
    </plugins>
</build>
```

```yaml
# application.yaml – Native-specific config
spring:
  aot:
    enabled: true    # Spring AOT processing (auto with native profile)
  datasource:
    url: jdbc:postgresql://db:5432/orders
    # Hibernate with native: dùng ddl-auto=none + Flyway/Liquibase
  jpa:
    hibernate:
      ddl-auto: none   # Schema migration không thể dùng auto-create với native
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
```

### How – Native-specific Limitations

```java
// 1. CGLIB proxies hạn chế → dùng interface-based proxy
// BAD: @Transactional trên class không có interface
@Service
public class OrderService {  // CGLIB proxy cần reflect config
    @Transactional
    public Order create(...) { ... }
}

// GOOD: implement interface
@Service
public class OrderServiceImpl implements OrderService {
    @Transactional
    public Order create(...) { ... }
}

// 2. Dynamic class loading không hoạt động
// BAD:
Class<?> clazz = Class.forName("com.example." + className);  // className runtime-dynamic

// GOOD: switch/map với known types
Map<String, Class<?>> registry = Map.of(
    "Order", Order.class,
    "Payment", Payment.class
);

// 3. Runtime bytecode generation (Mockito, some AOP) không hoạt động
// → Dùng Mockito 5+ với native support, hoặc @MockitoSettings
```

---

## 6. Dockerfile – Native Image Containers

```dockerfile
# Multi-stage: build với GraalVM, run với distroless/scratch
FROM ghcr.io/graalvm/native-image-community:21 AS builder
WORKDIR /app
COPY . .
RUN ./mvnw -Pnative -DskipTests native:compile

# Distroless base (no shell, minimal attack surface)
FROM gcr.io/distroless/base-debian12
COPY --from=builder /app/target/order-service /order-service
EXPOSE 8080
ENTRYPOINT ["/order-service"]
```

```dockerfile
# Với musl libc → scratch container (smallest possible)
FROM ghcr.io/graalvm/native-image-community:21 AS builder
RUN microdnf install -y musl-toolchain
WORKDIR /app
COPY . .
RUN ./mvnw -Pnative -DskipTests native:compile \
    -Dquarkus.native.additional-build-args="--static --libc=musl"

FROM scratch
COPY --from=builder /app/target/order-service /order-service
EXPOSE 8080
ENTRYPOINT ["/order-service"]
# Final image: ~20-30MB (vs 400MB JVM image)
```

---

## 7. Performance Characteristics

### How – Startup & Memory Comparison

```
Benchmark: Spring Boot Order Service (REST + JPA + Kafka)

                     JVM (OpenJDK 21)    Native Image
Startup time:        2.3s                0.08s   (29x faster)
RSS memory (idle):   280MB               45MB    (6x less)
RSS memory (load):   450MB               180MB   (2.5x less)
Throughput (req/s):  12,000              9,500   (JVM wins after warmup)
P99 latency (warm):  8ms                 12ms    (JVM JIT wins)
Image size:          350MB (JDK+app)     78MB    (native binary)
Build time:          45s                 4m30s

→ Native wins: startup, memory, image size
→ JVM wins: peak throughput, latency after warmup, build iteration speed
```

### How – Memory Footprint Breakdown

```
JVM process:
  JVM overhead:    ~100MB (code cache, metaspace, JIT compiler)
  Heap:            configurable, default up to 25% RAM
  GC overhead:     stop-the-world pauses

Native process:
  No JVM:          0MB
  No metaspace:    0MB
  No JIT cache:    0MB
  Heap:            smaller (pre-initialized objects in image heap)
  GC:              Serial GC by default (G1/Epsilon available with flag)
```

---

## 8. Compare & Trade-offs

### Compare – GraalVM Native vs JVM vs jlink

| | JVM | jlink (custom JRE) | GraalVM Native |
|--|-----|-------------------|----------------|
| Startup | 500ms-3s | 300ms-2s | 10-100ms |
| Memory | High | Medium | Low |
| Peak throughput | Excellent (JIT) | Excellent (JIT) | Good (no JIT) |
| Image size | ~350MB | ~80-150MB | ~20-80MB |
| Build time | Fast | Medium | Slow (2-10min) |
| Reflection | Full | Full | Limited (config needed) |
| Debugging | Easy | Easy | Hard (no JVM tools) |
| Profiling | JFR, async-profiler | JFR | perf, Valgrind |
| Khi dùng | Long-running, high-load | Moderate | Serverless, CLI, low memory |

### Compare – Quarkus vs Spring Native vs Micronaut

| | Spring Boot Native | Quarkus Native | Micronaut Native |
|--|-------------------|---------------|-----------------|
| Maturity | Good (Spring 6+) | Excellent | Good |
| AOT support | Spring AOT | Full native-first | Full native-first |
| Reflection | Still needed | Minimal | Minimal (compile-time DI) |
| Dev mode | JVM fallback | Dev mode hot reload | JVM fallback |
| Ecosystem | Largest | Medium | Medium |
| Khi dùng | Existing Spring apps | Greenfield native-first | Greenfield |

### Trade-offs

- **Build time**: 4-10 phút mỗi build → slow iteration; dùng JVM mode cho dev, native chỉ cho CI/CD
- **Reflection limitation**: libraries dùng reflection nhiều (Hibernate, Jackson, Spring AOP) cần explicit config; tracing agent giúp nhưng không cover 100%
- **No JIT**: throughput thấp hơn JVM sau warmup 5-15%; acceptable cho stateless microservices
- **Debugging**: không có JFR, JVM heap dump, jstack; dùng `-H:+DashboardAll` và perf tools thay thế
- **GC options**: Serial GC default → pauses; G1 experimental; Epsilon (no GC) cho serverless
- **Profile-Guided Optimization (PGO)**: native-image hỗ trợ PGO để recover throughput, nhưng thêm complexity

---

### Ghi chú – Chủ đề tiếp theo
> **Docker Production**: Compose health checks, blue-green deployment với Traefik, secrets management
