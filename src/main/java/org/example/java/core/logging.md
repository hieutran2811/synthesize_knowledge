# Logging – Java/Spring

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Logging Architecture Overview

### What – Logging Facade vs Implementation
Java logging có 2 tầng: **facade** (API mà code gọi) và **implementation** (thực thi thực tế). Tách rời để library/app không bị lock-in vào một framework logging cụ thể.

### How – Ecosystem

```
Facades (API):
  SLF4J (Simple Logging Facade for Java) – de facto standard
  Commons Logging (JCL)                  – legacy

Implementations:
  Logback      – native SLF4J, created by SLF4J author (Ceki Gülcü)
  Log4j 2      – Apache, high-performance (async), rich features
  java.util.logging (JUL) – JDK built-in, rarely used in production

SLF4J binding:
  Code → SLF4J API → binding jar → Implementation
  Code → SLF4J API → logback-classic.jar → Logback
  Code → SLF4J API → log4j-slf4j-impl.jar → Log4j 2
```

### Why – Tại sao dùng Facade?
- Libraries (Hibernate, Spring...) dùng SLF4J → không ép app phải dùng Logback hay Log4j
- Đổi implementation không cần sửa code
- Tránh "logging conflicts" khi nhiều library dùng implementations khác nhau

---

## 2. SLF4J – API

### How – Sử dụng

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class UserService {
    // Logger per class (pattern chuẩn)
    private static final Logger log = LoggerFactory.getLogger(UserService.class);

    public User findById(Long id) {
        log.debug("Looking up user id={}", id);          // lazy string construction
        User user = repo.findById(id).orElse(null);

        if (user == null) {
            log.warn("User not found: id={}", id);
            return null;
        }

        log.info("User retrieved: id={}, name={}", id, user.getName());
        return user;
    }

    public void processPayment(Payment p) {
        try {
            paymentGateway.charge(p);
        } catch (PaymentException e) {
            log.error("Payment failed: orderId={}, amount={}", p.getOrderId(), p.getAmount(), e);
            // ↑ exception như argument cuối cùng → in stack trace
        }
    }
}
```

### How – Log Levels (thứ tự tăng dần)

```
TRACE  – rất chi tiết, chỉ dev debugging (loop iterations, SQL params)
DEBUG  – debugging info (method entry/exit, variable values)
INFO   – business events (user login, order created, service started)
WARN   – potential issue nhưng recoverable (retry, fallback, deprecation)
ERROR  – error cần attention (exception, failed operation, data inconsistency)
```

```java
// Level guard (tránh string construction khi level tắt)
if (log.isDebugEnabled()) {
    log.debug("Heavy computation result: {}", expensiveMethod());
}

// Với SLF4J parameterized logging, không cần guard cho {} syntax
log.debug("User: {}", user.toString()); // toString() chỉ gọi nếu DEBUG enabled
```

---

## 3. Logback – Configuration

### How – logback-spring.xml (Spring Boot)

```xml
<!-- src/main/resources/logback-spring.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- Spring Boot properties integration -->
    <springProperty scope="context" name="APP_NAME" source="spring.application.name"/>
    <springProperty scope="context" name="LOG_LEVEL" source="logging.level.root" defaultValue="INFO"/>

    <!-- Properties -->
    <property name="LOG_DIR" value="${LOG_PATH:-/var/log/app}"/>
    <property name="LOG_FILE" value="${LOG_DIR}/${APP_NAME}"/>

    <!-- Console appender -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="ch.qos.logback.classic.encoder.PatternLayoutEncoder">
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
            <charset>UTF-8</charset>
        </encoder>
    </appender>

    <!-- Async Console (production: reduces I/O blocking) -->
    <appender name="ASYNC_CONSOLE" class="ch.qos.logback.classic.AsyncAppender">
        <queueSize>512</queueSize>
        <discardingThreshold>0</discardingThreshold>  <!-- 0 = never discard -->
        <appender-ref ref="CONSOLE"/>
    </appender>

    <!-- Rolling file appender -->
    <appender name="FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>${LOG_FILE}.log</file>
        <encoder class="ch.qos.logback.classic.encoder.PatternLayoutEncoder">
            <pattern>%d{ISO8601} [%thread] %-5level %logger{36} [%X{traceId},%X{spanId}] - %msg%n</pattern>
        </encoder>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>${LOG_FILE}.%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>30</maxHistory>    <!-- 30 days -->
            <totalSizeCap>3GB</totalSizeCap>
        </rollingPolicy>
    </appender>

    <!-- JSON appender (structured logging) -->
    <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
        <encoder class="net.logstash.logback.encoder.LogstashEncoder">
            <includeMdc>true</includeMdc>
            <includeContext>true</includeContext>
            <fieldNames>
                <timestamp>@timestamp</timestamp>
                <message>message</message>
                <logger>logger</logger>
                <thread>thread</thread>
                <level>level</level>
            </fieldNames>
            <customFields>{"app":"${APP_NAME}","env":"${SPRING_PROFILES_ACTIVE:-default}"}</customFields>
        </encoder>
    </appender>

    <!-- Spring profile-based config -->
    <springProfile name="local,dev">
        <root level="DEBUG">
            <appender-ref ref="CONSOLE"/>
        </root>
    </springProfile>

    <springProfile name="prod">
        <logger name="com.example" level="INFO"/>
        <logger name="org.springframework" level="WARN"/>
        <logger name="org.hibernate.SQL" level="WARN"/>
        <root level="WARN">
            <appender-ref ref="JSON"/>
            <appender-ref ref="FILE"/>
        </root>
    </springProfile>
</configuration>
```

---

## 4. MDC – Mapped Diagnostic Context

### What – MDC là gì?
**MDC (Mapped Diagnostic Context)** là thread-local key-value store. Values tự động xuất hiện trong log output, không cần pass qua mọi method call. Dùng để correlate logs trong một request.

### How – MDC với Spring

```java
// Filter để set MDC cho mỗi request
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class MdcRequestFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req,
                                    HttpServletResponse res,
                                    FilterChain chain) throws IOException, ServletException {
        try {
            String traceId = Optional
                .ofNullable(req.getHeader("X-Trace-Id"))
                .orElse(UUID.randomUUID().toString().replace("-", ""));
            String requestId = UUID.randomUUID().toString().substring(0, 8);
            String userId = extractUserId(req);  // từ JWT/session

            MDC.put("traceId", traceId);
            MDC.put("requestId", requestId);
            MDC.put("userId", userId);
            MDC.put("uri", req.getRequestURI());
            MDC.put("method", req.getMethod());

            // Propagate traceId to response
            res.setHeader("X-Trace-Id", traceId);

            chain.doFilter(req, res);
        } finally {
            MDC.clear();  // PHẢI clear sau request (thread pool reuse!)
        }
    }
}
```

```xml
<!-- logback pattern dùng MDC -->
<pattern>%d{ISO8601} [%thread] %-5level %logger{36}
    traceId=%X{traceId} userId=%X{userId} - %msg%n</pattern>
```

### How – MDC trong Async/Virtual Threads

```java
// MDC là ThreadLocal → mất khi chuyển thread
// Fix: copy MDC vào new thread

// Spring @Async
@Async
public CompletableFuture<Result> processAsync(String input) {
    // MDC đã mất ở đây (different thread)
    // Fix: dùng TaskDecorator
    return CompletableFuture.completedFuture(process(input));
}

// TaskDecorator để propagate MDC
@Configuration
@EnableAsync
public class AsyncConfig {
    @Bean
    public Executor asyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setTaskDecorator(runnable -> {
            Map<String, String> contextCopy = MDC.getCopyOfContextMap();
            return () -> {
                try {
                    if (contextCopy != null) MDC.setContextMap(contextCopy);
                    runnable.run();
                } finally {
                    MDC.clear();
                }
            };
        });
        executor.initialize();
        return executor;
    }
}

// Virtual Threads (Java 21): dùng ScopedValue thay MDC
ScopedValue<String> TRACE_ID = ScopedValue.newInstance();
ScopedValue.where(TRACE_ID, traceId).run(() -> {
    // TRACE_ID.get() available trong scope
});
```

---

## 5. Structured Logging (JSON)

### What – Structured Logging là gì?
Thay vì log text tự do, log **key-value pairs dạng JSON**. Log aggregation systems (ELK, Loki, Datadog) parse và index dễ dàng hơn.

### How – Logstash Encoder (Spring Boot)

```xml
<!-- pom.xml -->
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
```

```java
// Thêm structured fields vào log event
import net.logstash.logback.argument.StructuredArguments;
import static net.logstash.logback.argument.StructuredArguments.*;

log.info("Order created",
    keyValue("orderId", order.getId()),
    keyValue("userId", order.getUserId()),
    keyValue("amount", order.getAmount()),
    keyValue("currency", order.getCurrency())
);
// Output JSON:
// {"@timestamp":"...","level":"INFO","message":"Order created",
//  "orderId":12345,"userId":67890,"amount":99.99,"currency":"USD"}

// Array/Object fields
log.info("Batch processed",
    keyValue("batchId", batchId),
    array("itemIds", itemIds),
    entries(Map.of("success", 95, "failed", 5))
);
```

### How – Spring Boot application.yaml

```yaml
# Spring Boot 3.x: structured logging built-in
logging:
  structured:
    format:
      console: ecs  # Elastic Common Schema (ECS format)
      file: logstash
  level:
    root: INFO
    com.example: DEBUG
    org.springframework.web: INFO
    org.hibernate.SQL: DEBUG
    org.hibernate.type.descriptor.sql: TRACE  # show bind parameters
  file:
    name: /var/log/app/application.log
  logback:
    rollingpolicy:
      max-file-size: 100MB
      max-history: 30
      total-size-cap: 3GB
```

---

## 6. Async Appender – Performance

### How – Async Logging

```xml
<!-- Async appender wraps synchronous appenders -->
<appender name="ASYNC_FILE" class="ch.qos.logback.classic.AsyncAppender">
    <!-- Queue capacity (default 256) -->
    <queueSize>1024</queueSize>

    <!-- Discard TRACE/DEBUG/INFO when queue is 80% full (default 20) -->
    <!-- 0 = never discard -->
    <discardingThreshold>0</discardingThreshold>

    <!-- Include caller data (expensive! disable for perf) -->
    <includeCallerData>false</includeCallerData>

    <!-- Max time to wait for queue on shutdown (ms) -->
    <maxFlushTime>5000</maxFlushTime>

    <!-- Block when queue full (default: false = drop message) -->
    <neverBlock>false</neverBlock>

    <appender-ref ref="FILE"/>
</appender>
```

```
# Performance impact của logging:
# Synchronous file logging:   ~2-5μs per log call (I/O wait)
# Async logging (queue):      ~0.1-0.5μs (enqueue only)
# JSON encoding overhead:     ~1-2μs extra
# MDC lookup:                 ~0.05μs (HashMap lookup)
```

---

## 7. Log Aggregation – ELK / Loki

### How – ELK Stack

```
Application → Logback/Log4j2
     ↓ (file or stdout)
Filebeat / Fluentbit (log shipper)
     ↓ (push)
Logstash (parsing, enrichment) hoặc direct to ES
     ↓
Elasticsearch (storage, indexing)
     ↓
Kibana (visualization, search)
```

```yaml
# docker-compose: Filebeat config
filebeat.inputs:
  - type: container
    paths:
      - '/var/lib/docker/containers/*/*.log'
    processors:
      - add_docker_metadata:
          host: "unix:///var/run/docker.sock"
      - decode_json_fields:
          fields: ["message"]
          target: ""
          overwrite_keys: true

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "app-logs-%{+yyyy.MM.dd}"
```

### How – Loki + Grafana (lightweight alternative)

```yaml
# promtail config (log shipper cho Loki)
scrape_configs:
  - job_name: java-app
    static_configs:
      - targets: [localhost]
        labels:
          job: myapp
          env: prod
          __path__: /var/log/app/*.log
    pipeline_stages:
      - json:
          expressions:
            level: level
            traceId: traceId
            message: message
      - labels:
          level:
          traceId:
      - timestamp:
          source: '@timestamp'
          format: RFC3339
```

---

## 8. Real-world Best Practices

```java
// 1. Log tại boundaries (service entry/exit, không log trong private methods)
@Service
public class OrderService {
    public OrderDto createOrder(CreateOrderRequest req) {
        log.info("Creating order: userId={}, items={}", req.getUserId(), req.getItems().size());
        try {
            Order order = processOrder(req);  // internal methods: no logging needed
            log.info("Order created: orderId={}, total={}", order.getId(), order.getTotal());
            return mapper.toDto(order);
        } catch (InsufficientStockException e) {
            log.warn("Insufficient stock: productId={}", e.getProductId());
            throw e;
        }
    }
}

// 2. KHÔNG log sensitive data
log.info("User login: username={}", user.getUsername());  // OK
// log.info("Login: username={}, password={}", ...);      // NEVER!
// log.debug("JWT: {}", jwtToken);                        // NEVER!

// 3. Log exceptions đúng cách
try {
    ...
} catch (Exception e) {
    log.error("Failed to process payment: orderId={}", orderId, e);  // e là argument cuối
    // KHÔNG: log.error("Failed: " + e.getMessage());  // mất stack trace
}

// 4. Use log.atLevel() (SLF4J 2.0+) cho fluent API
log.atInfo()
   .addKeyValue("orderId", orderId)
   .addKeyValue("status", "created")
   .log("Order processed");
```

### Compare – Logback vs Log4j 2

| | Logback | Log4j 2 |
|--|---------|---------|
| Performance | Tốt | Rất tốt (async by default) |
| Async | Cần AsyncAppender | Built-in async loggers |
| Config format | XML/Groovy | XML/JSON/YAML/Properties |
| Garbage-free | Không | Có (Java 9+) |
| Default Spring Boot | ✅ | Cần loại trừ Logback |
| CVE History | Ít | Log4Shell (2021) CVE-2021-44228 |
| Khi dùng | Spring Boot default | High-throughput apps |

### Trade-offs
- **Async logging**: tăng throughput nhưng có thể mất log khi JVM crash đột ngột (queue chưa flush)
- **Structured JSON logging**: dễ parse nhưng khó đọc bằng mắt; dùng console pattern cho local dev
- **MDC**: tiện nhưng memory leak nếu không clear (thread pool); luôn clear trong finally
- **Verbose logging**: dễ debug nhưng tăng I/O, storage cost, và có thể leak sensitive data

---

### Ghi chú – Chủ đề tiếp theo
> **19.2 Observability**: Micrometer, Prometheus metrics, distributed tracing với OpenTelemetry, Zipkin/Jaeger
