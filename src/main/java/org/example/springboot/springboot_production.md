# Spring Boot Production – Deep Dive

## Mục lục
1. [Actuator – Custom Endpoints & Health](#1-actuator--custom-endpoints--health)
2. [Micrometer + Prometheus](#2-micrometer--prometheus)
3. [OpenTelemetry Tracing](#3-opentelemetry-tracing)
4. [GraalVM Native Image](#4-graalvm-native-image)
5. [Docker Layered JARs](#5-docker-layered-jars)
6. [Kubernetes Probes & Graceful Shutdown](#6-kubernetes-probes--graceful-shutdown)
7. [Virtual Threads (Spring Boot 3.2+)](#7-virtual-threads-spring-boot-32)
8. [JVM & HikariCP Performance Tuning](#8-jvm--hikaricp-performance-tuning)

---

## 1. Actuator – Custom Endpoints & Health

### 1.1 Basic Setup

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health, info, metrics, prometheus, loggers, env, configprops
      base-path: /actuator
  endpoint:
    health:
      show-details: when-authorized   # never | always | when-authorized
      show-components: always
      probes:
        enabled: true   # /actuator/health/liveness, /actuator/health/readiness
    info:
      enabled: true
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true
    db:
      enabled: true
    redis:
      enabled: true
    kafka:
      enabled: true
  info:
    env:
      enabled: true
    git:
      enabled: true
      mode: full   # simple | full
    build:
      enabled: true
```

### 1.2 Custom Health Indicator

```java
// Custom health check
@Component
public class ExternalServiceHealthIndicator implements HealthIndicator {
    
    @Autowired
    private ExternalServiceClient client;
    
    @Override
    public Health health() {
        try {
            ExternalServiceStatus status = client.ping();
            if (status.isUp()) {
                return Health.up()
                    .withDetail("service", "external-payment")
                    .withDetail("latencyMs", status.getLatencyMs())
                    .withDetail("version", status.getVersion())
                    .build();
            } else {
                return Health.down()
                    .withDetail("service", "external-payment")
                    .withDetail("reason", status.getMessage())
                    .build();
            }
        } catch (Exception e) {
            return Health.down(e)
                .withDetail("service", "external-payment")
                .withDetail("error", e.getMessage())
                .build();
        }
    }
}

// Reactive health indicator
@Component
public class ReactiveDbHealthIndicator implements ReactiveHealthIndicator {
    
    @Autowired
    private DatabaseClient databaseClient;
    
    @Override
    public Mono<Health> health() {
        return databaseClient.sql("SELECT 1")
            .fetch()
            .one()
            .map(result -> Health.up().withDetail("db", "reactive-postgres").build())
            .onErrorReturn(Health.down().withDetail("error", "DB unreachable").build());
    }
}

// Custom readiness condition
@Component
public class DataLoadReadinessIndicator implements ApplicationListener<ApplicationReadyEvent> {
    
    @Autowired
    private ApplicationContext context;
    
    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        // Mark readiness after warm-up
        AvailabilityChangeEvent.publish(context, ReadinessState.ACCEPTING_TRAFFIC);
    }
    
    // Can also programmatically mark NOT ready during maintenance
    public void startMaintenance() {
        AvailabilityChangeEvent.publish(context, ReadinessState.REFUSING_TRAFFIC);
    }
}
```

### 1.3 Custom Actuator Endpoint

```java
@Component
@Endpoint(id = "featureflags")
public class FeatureFlagEndpoint {
    
    @Autowired
    private FeatureFlagService featureFlagService;
    
    @ReadOperation
    public Map<String, Boolean> getFlags() {
        return featureFlagService.getAllFlags();
    }
    
    @ReadOperation
    public Boolean getFlag(@Selector String flagName) {
        return featureFlagService.isEnabled(flagName);
    }
    
    @WriteOperation
    public void setFlag(@Selector String flagName, @Body FlagUpdateRequest request) {
        featureFlagService.setFlag(flagName, request.isEnabled());
    }
    
    @DeleteOperation
    public void resetFlag(@Selector String flagName) {
        featureFlagService.reset(flagName);
    }
    
    record FlagUpdateRequest(boolean enabled) {}
}

// Access:
// GET  /actuator/featureflags
// GET  /actuator/featureflags/dark-mode
// POST /actuator/featureflags/dark-mode  {"enabled": true}
```

### 1.4 Actuator Security

```java
@Configuration
public class ActuatorSecurityConfig {
    
    @Bean
    @Order(1)
    public SecurityFilterChain actuatorSecurityChain(HttpSecurity http) throws Exception {
        return http
            .securityMatcher(EndpointRequest.toAnyEndpoint())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(EndpointRequest.to(HealthEndpoint.class, InfoEndpoint.class)).permitAll()
                .requestMatchers(EndpointRequest.to(PrometheusEndpoint.class))
                    .hasRole("METRICS_READER")
                .requestMatchers(EndpointRequest.toAnyEndpoint()).hasRole("ACTUATOR_ADMIN")
                .anyRequest().denyAll()
            )
            .httpBasic(Customizer.withDefaults())
            .build();
    }
}
```

---

## 2. Micrometer + Prometheus

### 2.1 Dependencies

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

### 2.2 Custom Metrics

```java
@Service
public class OrderMetricsService {
    
    private final Counter orderCreatedCounter;
    private final Counter orderFailedCounter;
    private final Timer orderProcessingTimer;
    private final DistributionSummary orderAmountSummary;
    private final AtomicInteger pendingOrdersGauge;
    
    public OrderMetricsService(MeterRegistry registry) {
        this.orderCreatedCounter = Counter.builder("orders.created")
            .description("Total orders created")
            .tag("type", "business")
            .register(registry);
        
        this.orderFailedCounter = Counter.builder("orders.failed")
            .description("Total orders failed")
            .register(registry);
        
        this.orderProcessingTimer = Timer.builder("orders.processing.time")
            .description("Order processing duration")
            .publishPercentiles(0.5, 0.95, 0.99)   // p50, p95, p99
            .publishPercentileHistogram()
            .sla(Duration.ofMillis(100), Duration.ofMillis(500), Duration.ofSeconds(1))
            .register(registry);
        
        this.orderAmountSummary = DistributionSummary.builder("orders.amount")
            .description("Order amount distribution")
            .baseUnit("USD")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(registry);
        
        // Gauge — tracks current value
        this.pendingOrdersGauge = registry.gauge("orders.pending", 
            new AtomicInteger(0));
    }
    
    public Order processOrder(CreateOrderRequest req) {
        return orderProcessingTimer.record(() -> {
            try {
                Order order = doProcessOrder(req);
                orderCreatedCounter.increment();
                orderAmountSummary.record(order.getTotal().doubleValue());
                return order;
            } catch (Exception e) {
                orderFailedCounter.increment();
                throw e;
            }
        });
    }
    
    // Tag-based counters (dimensional metrics)
    public void recordOrderByStatus(OrderStatus status, String region) {
        Metrics.counter("orders.by.status",
            "status", status.name(),
            "region", region
        ).increment();
    }
}
```

### 2.3 @Timed / @Counted AOP-based

```java
// Enable Micrometer AOP
@Configuration
@EnableAspectJAutoProxy
public class MetricsConfig {
    @Bean
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }
    
    @Bean
    public CountedAspect countedAspect(MeterRegistry registry) {
        return new CountedAspect(registry);
    }
}

// Usage on methods
@Service
public class ProductService {
    
    @Timed(value = "product.find", description = "Time to find product",
           percentiles = {0.5, 0.95, 0.99}, histogram = true)
    public Product findById(Long id) { ... }
    
    @Counted(value = "product.create", description = "Products created")
    public Product create(Product product) { ... }
}
```

### 2.4 Prometheus + Grafana Setup

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'spring-boot-app'
    metrics_path: '/actuator/prometheus'
    scrape_interval: 15s
    static_configs:
      - targets: ['app:8080']
    basic_auth:
      username: 'prometheus'
      password: 'secret'
```

```yaml
# Grafana dashboard query examples (PromQL)
# Request rate per second
rate(http_server_requests_seconds_count{uri!~"/actuator.*"}[1m])

# P99 latency
histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m]))

# Error rate
rate(http_server_requests_seconds_count{status=~"5.."}[1m])
  / rate(http_server_requests_seconds_count[1m])

# JVM heap usage
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}

# HikariCP pool usage
hikaricp_connections_active / hikaricp_connections_max
```

### 2.5 Alerting Rules

```yaml
# alerting-rules.yml
groups:
  - name: spring-boot-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          rate(http_server_requests_seconds_count{status=~"5.."}[5m])
          / rate(http_server_requests_seconds_count[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Error rate {{ $value | humanizePercentage }} on {{ $labels.instance }}"
      
      - alert: SlowP99Latency
        expr: histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P99 latency {{ $value }}s — degraded performance"
      
      - alert: HikariPoolExhausted
        expr: hikaricp_connections_pending > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "HikariCP connection pool exhausted on {{ $labels.instance }}"
```

---

## 3. OpenTelemetry Tracing

### 3.1 Spring Boot 3 Auto-Config (No code changes needed)

```xml
<!-- Spring Boot 3.2+ built-in OTEL support -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

```yaml
management:
  tracing:
    enabled: true
    sampling:
      probability: 1.0   # 100% in dev, 0.1 in prod
  otlp:
    tracing:
      endpoint: http://jaeger:4318/v1/traces  # or Tempo

# Logs include trace ID automatically with Micrometer Tracing
logging:
  pattern:
    level: "%5p [${spring.application.name:},%X{traceId:-},%X{spanId:-}]"
```

### 3.2 Custom Spans

```java
@Service
public class OrderService {
    
    @Autowired
    private Tracer tracer;
    
    public Order processOrder(CreateOrderRequest req) {
        Span span = tracer.nextSpan().name("process-order");
        
        try (Tracer.SpanInScope scope = tracer.withSpan(span.start())) {
            span.tag("order.customer_id", req.getCustomerId().toString());
            span.tag("order.item_count", String.valueOf(req.getItems().size()));
            
            // Span events
            span.event("validation-started");
            validateOrder(req);
            span.event("validation-completed");
            
            Order order = orderRepository.save(Order.from(req));
            span.tag("order.id", order.getId().toString());
            
            return order;
        } catch (Exception e) {
            span.error(e);
            throw e;
        } finally {
            span.end();
        }
    }
    
    // Or use @NewSpan annotation
    @NewSpan("send-order-email")
    public void sendConfirmationEmail(@SpanTag("order.id") Long orderId) {
        emailService.sendOrderConfirmation(orderId);
    }
}
```

### 3.3 Context Propagation

```java
// Automatic: Spring WebMVC/WebFlux injects trace context into HTTP headers
// W3C TraceContext: traceparent: 00-{traceId}-{spanId}-{flags}
// B3 format also supported

// For async operations
@Async
public void processAsync(OrderEvent event) {
    // Micrometer Tracing propagates context automatically through @Async
    // Works with ThreadPoolTaskExecutor configured with Micrometer
}

// Manual propagation
@Bean
public Executor asyncExecutor(Tracer tracer) {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.initialize();
    // Wrap with context-propagating decorator
    return new ContextPropagatingExecutorServiceDecorator(executor.getThreadPoolExecutor());
}
```

---

## 4. GraalVM Native Image

### 4.1 What is Native Image?

```
Traditional JVM:     Source → .class → JVM interprets/JIT compiles → slow startup, high memory
GraalVM Native:      Source → AOT compiled → native binary → fast startup (<50ms), low memory

AOT = Ahead-Of-Time compilation (no JVM at runtime)
Limitation: No dynamic class loading, no reflection without hints
```

### 4.2 Build Setup

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
    <configuration>
        <imageName>my-app</imageName>
        <buildArgs>
            <arg>--no-fallback</arg>
            <arg>--initialize-at-build-time=org.slf4j</arg>
        </buildArgs>
    </configuration>
</plugin>
```

```bash
# Build native image
./mvnw -Pnative native:compile

# Build native container image (no GraalVM locally needed)
./mvnw -Pnative spring-boot:build-image

# Run
./target/my-app
# Starts in ~50ms vs ~3000ms for JVM
```

### 4.3 Reflection Hints

```java
// Spring Boot 3 AOT engine generates most hints automatically
// For custom reflection needs:
@Configuration
@ImportRuntimeHints(MyRuntimeHints.class)
public class AppConfig { }

public class MyRuntimeHints implements RuntimeHintsRegistrar {
    
    @Override
    public void registerHints(RuntimeHints hints, ClassLoader classLoader) {
        // Register class for reflection
        hints.reflection()
            .registerType(MyCustomClass.class, MemberCategory.INVOKE_DECLARED_CONSTRUCTORS,
                MemberCategory.INVOKE_PUBLIC_METHODS);
        
        // Register resources (templates, SQL files)
        hints.resources()
            .registerPattern("templates/*.html")
            .registerPattern("db/migration/*.sql");
        
        // Register serialization
        hints.serialization()
            .registerType(MySerializableClass.class);
        
        // Register proxies
        hints.proxies()
            .registerJdkProxy(MyInterface.class);
    }
}

// Or per-class annotation
@RegisterReflectionForBinding(OrderCreatedEvent.class)
public class OrderService { ... }
```

### 4.4 Native Image Testing

```java
// Test native hints before building (JVM mode with AOT processing)
@SpringBootTest
@ActiveProfiles("native-test")
class NativeCompatibilityTest {
    
    @Autowired
    private ApplicationContext ctx;
    
    @Test
    void allBeansLoad() {
        assertThat(ctx.getBeanDefinitionCount()).isGreaterThan(10);
    }
}

// Run with AOT processing
// ./mvnw -DspringAot=true test
```

### 4.5 Native vs JVM Comparison

| Aspect | JVM | Native |
|--------|-----|--------|
| Startup | 2-10s | 10-100ms |
| Memory | 256MB+ | 30-80MB |
| Peak throughput | Higher (JIT) | Slightly lower |
| Build time | 30s | 3-10min |
| Docker image | 200-500MB | 30-80MB |
| Debugging | Full tooling | Limited |
| Profiling | JProfiler/async-profiler | Very limited |
| Best for | Long-running services | Serverless, CLI tools, microservices |

---

## 5. Docker Layered JARs

### 5.1 Why Layered JARs?

```
Traditional fat JAR: All layers change on every build → large Docker cache invalidation
Layered JAR:
  Layer 1: dependencies (rarely change)     ← cached
  Layer 2: spring-boot-loader (rarely)       ← cached
  Layer 3: snapshot-dependencies (sometimes) ← cached
  Layer 4: application code (changes often)  ← always re-built (small)
```

### 5.2 Build Layered JAR

```xml
<!-- pom.xml — layered JARs are default in Spring Boot 2.3+ -->
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <configuration>
                <layers>
                    <enabled>true</enabled>
                </layers>
                <image>
                    <name>myapp:${project.version}</name>
                    <env>
                        <BP_JVM_VERSION>21</BP_JVM_VERSION>
                    </env>
                </image>
            </configuration>
        </plugin>
    </plugins>
</build>
```

### 5.3 Dockerfile

```dockerfile
# Stage 1: Extract layers
FROM eclipse-temurin:21-jre-alpine AS builder
WORKDIR /app
COPY target/*.jar app.jar
RUN java -Djarmode=layertools -jar app.jar extract

# Stage 2: Build final image
FROM eclipse-temurin:21-jre-alpine

# Security: non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

WORKDIR /app

# Copy layers in order (least-to-most frequently changing)
COPY --from=builder /app/dependencies/ ./
COPY --from=builder /app/spring-boot-loader/ ./
COPY --from=builder /app/snapshot-dependencies/ ./
COPY --from=builder /app/application/ ./

# JVM tuning for containers
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 \
               -XX:InitialRAMPercentage=50.0 \
               -XX:+UseContainerSupport \
               -XX:+ExitOnOutOfMemoryError \
               -Djava.security.egd=file:/dev/./urandom"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-cp", "BOOT-INF/lib/*:.", "org.springframework.boot.loader.JarLauncher"]
```

### 5.4 Docker Build Cache Optimization

```dockerfile
# Best practice: separate dependency resolution from code copy

# Copy only pom.xml first to resolve dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B  # cache dependencies separately

# Then copy source and build
COPY src ./src
RUN mvn package -DskipTests -B
```

---

## 6. Kubernetes Probes & Graceful Shutdown

### 6.1 Spring Boot K8s Probes

```yaml
# application.yml
management:
  endpoint:
    health:
      probes:
        enabled: true
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true

# K8s deployment.yaml
spec:
  template:
    spec:
      containers:
        - name: app
          image: myapp:1.0.0
          
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 30   # Wait for startup
            periodSeconds: 10
            failureThreshold: 3
            
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 5
            failureThreshold: 3
          
          startupProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 30   # Allow up to 150s startup
          
          # Resource limits
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "1000m"
          
          # Graceful shutdown: SIGTERM before SIGKILL
          lifecycle:
            preStop:
              exec:
                command: ["sleep", "15"]  # Allow in-flight requests to complete
          
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: "prod"
            - name: SERVER_SHUTDOWN
              value: "graceful"
```

### 6.2 Graceful Shutdown

```yaml
# application.yml
server:
  shutdown: graceful          # default: immediate
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s  # max time to wait for active requests
```

```java
// Detect SIGTERM and perform cleanup
@Component
public class GracefulShutdownHandler {
    
    @Autowired
    private ApplicationContext ctx;
    
    @PreDestroy
    public void onShutdown() {
        log.info("Starting graceful shutdown...");
        // Cleanup resources: close connections, flush buffers, etc.
    }
    
    // Or: ApplicationListener<ContextClosedEvent>
    @EventListener(ContextClosedEvent.class)
    public void onContextClosed() {
        // Signal external load balancer (via readiness probe)
        AvailabilityChangeEvent.publish(ctx, ReadinessState.REFUSING_TRAFFIC);
        
        // Wait for in-flight requests (spring.lifecycle.timeout-per-shutdown-phase handles this)
    }
}
```

---

## 7. Virtual Threads (Spring Boot 3.2+)

### 7.1 Enable Virtual Threads

```yaml
# application.yml — single property enables Virtual Threads globally
spring:
  threads:
    virtual:
      enabled: true  # Spring Boot 3.2+
      
# Effect:
# - Tomcat: uses Virtual Threads for HTTP request handling
# - @Async: executor uses Virtual Threads
# - @Scheduled: uses Virtual Threads
# - Spring Integration: uses Virtual Threads
```

### 7.2 What Changes with Virtual Threads

```java
// Before: Platform threads (1:1 OS thread, ~1MB stack each)
// After: Virtual threads (M:N, few carrier threads handle millions of virtual threads)

// The key benefit: blocking I/O no longer wastes OS threads
// Spring MVC + Virtual Threads can handle C10K+ concurrency without reactive code

// Traditional blocking code — now scales like reactive
@GetMapping("/users/{id}")
public UserResponse getUser(@PathVariable Long id) {
    // This blocks → with platform threads, wastes an OS thread
    // With virtual threads: the virtual thread parks, carrier thread handles other work
    User user = userRepository.findById(id).orElseThrow(); // JDBC blocking I/O
    return UserResponse.from(user);
}

// No need for this complexity with Virtual Threads:
@GetMapping("/users/{id}")
public Mono<UserResponse> getUserReactive(@PathVariable Long id) { ... }
```

### 7.3 Virtual Thread Configuration

```java
// Custom executor for fine-grained control
@Configuration
@ConditionalOnProperty("spring.threads.virtual.enabled", havingValue = "true")
public class VirtualThreadConfig {
    
    @Bean(name = "taskExecutor")
    @Primary
    public Executor virtualThreadExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }
    
    // For Spring MVC + Tomcat
    @Bean
    public TomcatProtocolHandlerCustomizer<?> virtualThreadProtocolHandlerCustomizer() {
        return protocolHandler -> 
            protocolHandler.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
    }
}
```

### 7.4 Pinning Issues (Virtual Thread Pitfalls)

```java
// AVOID: synchronized blocks pin virtual threads to carrier thread
// (defeats the purpose of virtual threads)
public synchronized void badMethod() {
    jdbcTemplate.query(...);  // virtual thread pinned during blocking!
}

// USE: ReentrantLock instead of synchronized
private final ReentrantLock lock = new ReentrantLock();

public void goodMethod() {
    lock.lock();
    try {
        jdbcTemplate.query(...);  // virtual thread can park, carrier is freed
    } finally {
        lock.unlock();
    }
}

// Detect pinning:
// -Djdk.tracePinnedThreads=short  (JVM flag for diagnosis)
```

### 7.5 Virtual Threads vs Reactive

| | Virtual Threads | Reactive (WebFlux) |
|--|----------------|-------------------|
| Programming model | Imperative (simple) | Functional/declarative (complex) |
| Debugging | Stack traces (normal) | Complex operator chains |
| Testing | JUnit standard | StepVerifier |
| Performance | Comparable | Slightly lower memory per connection |
| Backpressure | None | Built-in |
| Best for | CRUD services, I/O bound | Streaming, event-driven, backpressure needed |

---

## 8. JVM & HikariCP Performance Tuning

### 8.1 JVM Flags for Containers

```bash
# application.sh / Dockerfile ENV
JAVA_OPTS="
  # Container memory awareness (Java 8u191+, Java 10+)
  -XX:+UseContainerSupport
  -XX:MaxRAMPercentage=75.0      # Heap = 75% of container RAM
  -XX:InitialRAMPercentage=50.0
  
  # GC selection
  -XX:+UseG1GC                   # Default Java 9+, good for most apps
  # OR:
  -XX:+UseZGC                    # Low-latency, Java 15+, good for P99 latency
  # OR:
  -XX:+UseShenandoahGC           # Low-latency, OpenJDK
  
  # G1GC tuning
  -XX:MaxGCPauseMillis=200       # Target max pause
  -XX:G1HeapRegionSize=16m       # Region size (1-32MB, power of 2)
  -XX:ParallelGCThreads=4
  
  # OOM behavior
  -XX:+ExitOnOutOfMemoryError    # Fail fast — let K8s restart
  -XX:+HeapDumpOnOutOfMemoryError
  -XX:HeapDumpPath=/dumps/heapdump.hprof
  
  # Startup optimization
  -XX:TieredStopAtLevel=1        # JIT compile less at startup (trades peak perf)
  
  # DNS caching (important for cloud)
  -Dsun.net.inetaddr.ttl=30
  
  # Entropy for UUID generation
  -Djava.security.egd=file:/dev/./urandom
"
```

### 8.2 HikariCP Tuning

```yaml
spring:
  datasource:
    hikari:
      # Pool size: formula = (core_count * 2) + effective_spindle_count
      # For PostgreSQL: ~10-20 connections is usually optimal
      maximum-pool-size: 20
      minimum-idle: 5
      
      # Timeouts
      connection-timeout: 30000     # 30s — how long to wait for connection from pool
      idle-timeout: 600000          # 10min — when to remove idle connections
      max-lifetime: 1800000         # 30min — max connection lifetime (avoid firewall cuts)
      keepalive-time: 60000         # 1min — keepalive ping
      
      # Pool name (for JMX/metrics)
      pool-name: HikariCP-Primary
      
      # Validation
      connection-test-query: SELECT 1   # for old drivers
      # Modern drivers: spring uses JDBC4 isValid() instead
      
      # Leak detection (set in dev/staging)
      leak-detection-threshold: 10000   # 10s — log if connection held > 10s
```

### 8.3 HikariCP Metrics in Prometheus

```
# Key metrics to monitor
hikaricp_connections_active           # Currently in use
hikaricp_connections_idle             # Available
hikaricp_connections_pending          # Waiting for connection → alert if > 0
hikaricp_connections_acquire_seconds  # Time to acquire connection
hikaricp_connections_creation_seconds # Time to create new connection
hikaricp_connections_usage_seconds    # Time connection is used (checks for leaks)

# Alert rule: pool exhaustion
- alert: HikariPoolPending
  expr: hikaricp_connections_pending{pool="HikariCP-Primary"} > 0
  for: 30s
  annotations:
    summary: "HikariCP pool exhausted — requests queuing"
```

### 8.4 Spring Boot 3.3+ CDS (Class Data Sharing)

```bash
# CDS: pre-compute class metadata → faster startup (25-40% reduction)

# Step 1: Create AppCDS archive
java -Dspring.context.exit=onRefresh \
     -XX:ArchiveClassesAtExit=app.jsa \
     -jar app.jar

# Step 2: Use archive on startup
java -XX:SharedArchiveFile=app.jsa \
     -jar app.jar

# Spring Boot Maven plugin support
./mvnw spring-boot:process-aot  # generate AOT + CDS
```

### 8.5 Production Checklist

```markdown
## Spring Boot Production Readiness Checklist

### Observability
- [ ] Actuator endpoints exposed (health, info, metrics, prometheus)
- [ ] Health indicators for all external dependencies (DB, Redis, Kafka, external APIs)
- [ ] Custom business metrics (order rate, error rate, SLA)
- [ ] Structured logging with trace ID
- [ ] Distributed tracing configured (Jaeger/Tempo)
- [ ] Prometheus scrape configured
- [ ] Grafana dashboards: latency, error rate, saturation, traffic (RED method)
- [ ] Alerting rules for P99 latency, error rate, pool exhaustion

### Reliability
- [ ] Graceful shutdown configured (server.shutdown=graceful)
- [ ] K8s liveness/readiness/startup probes
- [ ] Circuit breaker for external calls (Resilience4j)
- [ ] Retry with exponential backoff for transient failures
- [ ] Timeout on all external calls
- [ ] Bulkhead / rate limiting
- [ ] Database connection pool tuned
- [ ] Connection pool leak detection enabled

### Security
- [ ] Actuator secured (not exposed publicly or basic-auth protected)
- [ ] Secrets in vault/K8s secrets (not in application.yml)
- [ ] HTTPS / TLS configured
- [ ] Security headers (HSTS, CSP, X-Frame-Options)
- [ ] Input validation on all user inputs
- [ ] SQL injection protected (parameterized queries / JPA)

### Performance
- [ ] DB indexes for all WHERE clauses and JOINs
- [ ] N+1 queries eliminated (@EntityGraph, JOIN FETCH)
- [ ] Cache for frequently read, rarely changed data
- [ ] Async for non-critical side effects (@Async)
- [ ] Pagination on all list endpoints
- [ ] Response compression enabled

### Deployment
- [ ] Docker layered JAR
- [ ] Non-root user in Docker
- [ ] Resource requests and limits in K8s
- [ ] Horizontal Pod Autoscaler configured
- [ ] Flyway/Liquibase migration tested
- [ ] Rollback plan documented
```

---

## Summary: Spring Boot Production Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                         K8s Pod                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Spring Boot App (Virtual Threads)           │   │
│  │                                                          │   │
│  │  HTTP/REST ──→ Controller ──→ Service ──→ Repository     │   │
│  │                  ↓              ↓            ↓           │   │
│  │             Validation      @Cacheable    HikariCP       │   │
│  │                  ↓              ↓            ↓           │   │
│  │          GlobalExHandler      Redis       PostgreSQL     │   │
│  │                                                          │   │
│  │  Micrometer ──→ /actuator/prometheus ──→ Prometheus     │   │
│  │  OTEL Traces ──→ Jaeger/Tempo                            │   │
│  │  Structured Logs ──→ Loki/ELK                            │   │
│  │  /health/liveness ──→ K8s liveness probe                 │   │
│  │  /health/readiness ──→ K8s readiness probe               │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                   │
│  Resources: 512MB-2GB RAM | 0.5-2 CPU | 20 HikariCP connections  │
└─────────────────────────────────────────────────────────────────┘
```
