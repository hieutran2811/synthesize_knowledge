# Observability – Giám sát Spring Boot Production

## What – Observability trong Spring Boot

Spring Boot 3+ tích hợp sẵn **Micrometer** (metrics), **OpenTelemetry** (tracing), và **Logback/Log4j2** (logging) — ba trụ cột của observability.

---

## Micrometer – Metrics

### Setup

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<!-- Prometheus exporter -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus,loggers
  endpoint:
    health:
      show-details: always
      probes:
        enabled: true      # /actuator/health/liveness, /actuator/health/readiness
  metrics:
    export:
      prometheus:
        enabled: true
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active:local}
    distribution:
      percentiles-histogram:
        http.server.requests: true   # enable histograms for P95/P99
      percentiles:
        http.server.requests: 0.5,0.95,0.99
      slo:
        http.server.requests: 100ms,500ms,1s,2s
```

### Custom Metrics

```java
@Component
@RequiredArgsConstructor
public class OrderMetrics {

    private final MeterRegistry registry;

    // Counter
    private Counter ordersCreated;
    private Counter ordersFailed;

    @PostConstruct
    public void init() {
        ordersCreated = Counter.builder("orders.created.total")
            .description("Total orders created successfully")
            .tag("service", "order-service")
            .register(registry);

        ordersFailed = Counter.builder("orders.failed.total")
            .description("Total failed order creations")
            .register(registry);

        // Gauge: current value
        Gauge.builder("orders.pending.count", orderRepository,
                OrderRepository::countByStatus)
            .tag("status", "PENDING")
            .register(registry);
    }

    // Timer: measure duration
    public Order measureOrderCreation(Supplier<Order> supplier) {
        return Timer.builder("orders.creation.duration")
            .description("Time to create an order")
            .publishPercentileHistogram()
            .register(registry)
            .record(supplier);
    }

    // DistributionSummary: measure values (order amounts)
    public void recordOrderAmount(BigDecimal amount, String tenantId) {
        DistributionSummary.builder("orders.amount")
            .tag("tenant_id", tenantId)
            .register(registry)
            .record(amount.doubleValue());
    }

    public void incrementOrderCreated(String tenantId, String plan) {
        registry.counter("orders.created.total",
            "tenant_id", tenantId,
            "plan", plan
        ).increment();
    }

    public void incrementOrderFailed(String reason) {
        registry.counter("orders.failed.total",
            "reason", reason
        ).increment();
    }
}
```

### AOP-based Metrics (tự động)

```java
@Aspect
@Component
@RequiredArgsConstructor
public class ServiceMetricsAspect {

    private final MeterRegistry registry;

    @Around("@annotation(timed)")
    public Object measureTime(ProceedingJoinPoint pjp, Timed timed) throws Throwable {
        String name = timed.value().isEmpty()
            ? pjp.getSignature().toShortString()
            : timed.value();

        Timer.Sample sample = Timer.start(registry);
        String status = "success";
        try {
            return pjp.proceed();
        } catch (Exception e) {
            status = "error";
            throw e;
        } finally {
            sample.stop(Timer.builder(name)
                .tag("status", status)
                .tag("class", pjp.getTarget().getClass().getSimpleName())
                .register(registry));
        }
    }
}

// Sử dụng
@Service
public class OrderService {

    @Timed("order.service.create")  // auto-record timing
    public Order createOrder(CreateOrderRequest req) { ... }
}
```

---

## Distributed Tracing – OpenTelemetry

### Setup (Spring Boot 3 + Micrometer Tracing)

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-spring-boot-starter</artifactId>
</dependency>
<!-- Exporter to Jaeger/Zipkin/OTLP -->
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

```yaml
management:
  tracing:
    sampling:
      probability: 1.0    # 100% sampling (dev), 0.1 (production 10%)
    propagation:
      type: w3c           # hoặc b3 (Zipkin)

otel:
  exporter:
    otlp:
      endpoint: http://jaeger:4318
  resource:
    attributes:
      service.name: ${spring.application.name}
      service.version: ${app.version:unknown}
      deployment.environment: ${spring.profiles.active:local}
```

### Custom Spans

```java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final Tracer tracer;
    private final OrderRepository orderRepo;

    public Order createOrder(CreateOrderRequest req) {
        Span span = tracer.nextSpan()
            .name("order.create")
            .tag("tenant.id", TenantContext.getCurrentTenant())
            .tag("items.count", String.valueOf(req.getItems().size()))
            .start();

        try (Tracer.SpanInScope ws = tracer.withSpan(span)) {
            Order order = orderRepo.save(Order.from(req));
            span.tag("order.id", order.getId().toString());
            span.event("order-saved");
            return order;
        } catch (Exception e) {
            span.error(e);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

### Propagate Trace Context (MDC + HTTP Headers)

```java
// Spring Boot tự inject traceId vào MDC → tự động in log
// log pattern với traceId:
logging:
  pattern:
    console: "%d{HH:mm:ss.SSS} [%thread] %-5level [%X{traceId},%X{spanId}] %logger{36} - %msg%n"

// Output:
// 10:30:15.123 [async-1] INFO  [abc123def456,fedcba654321] OrderService - Order created: 1

// HTTP: trace context tự động propagate qua headers
// traceparent: 00-abc123-fedcba-01 (W3C Trace Context)
// X-B3-TraceId: abc123 (B3 format)
```

---

## Logging Best Practices

### Structured Logging (JSON)

```xml
<!-- logback-spring.xml -->
<configuration>
    <springProfile name="prod">
        <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <includeMdcKeyName>traceId</includeMdcKeyName>
                <includeMdcKeyName>spanId</includeMdcKeyName>
                <includeMdcKeyName>tenant_id</includeMdcKeyName>
                <includeMdcKeyName>user_id</includeMdcKeyName>
                <includeMdcKeyName>request_id</includeMdcKeyName>
                <customFields>{"app":"order-service","env":"prod"}</customFields>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="JSON"/>
        </root>
    </springProfile>
</configuration>
```

### Logging Level Runtime Update

```bash
# Thay đổi log level không cần restart
curl -X POST http://localhost:8080/actuator/loggers/com.example.service \
  -H "Content-Type: application/json" \
  -d '{"configuredLevel":"DEBUG"}'

# Xem level hiện tại
curl http://localhost:8080/actuator/loggers/com.example
```

### Log Categories cho Production

```yaml
logging:
  level:
    root: WARN
    com.example: INFO
    com.example.service.PaymentService: DEBUG  # Debug specific service
    org.springframework.security: WARN
    org.hibernate.SQL: WARN           # tắt SQL log ở prod
    org.hibernate.orm.jdbc.bind: WARN # tắt parameter log
    io.lettuce.core: WARN
```

---

## Custom Health Indicators

```java
@Component("database")
public class DatabaseHealthIndicator extends AbstractHealthIndicator {

    private final DataSource dataSource;

    @Override
    protected void doHealthCheck(Health.Builder builder) throws Exception {
        try (Connection conn = dataSource.getConnection()) {
            boolean valid = conn.isValid(2); // 2 second timeout
            if (valid) {
                builder.up()
                    .withDetail("database", conn.getMetaData().getDatabaseProductName())
                    .withDetail("url", conn.getMetaData().getURL());
            } else {
                builder.down().withDetail("error", "Connection validation failed");
            }
        }
    }
}

@Component("kafka")
public class KafkaHealthIndicator extends AbstractHealthIndicator {

    private final KafkaAdmin kafkaAdmin;

    @Override
    protected void doHealthCheck(Health.Builder builder) {
        try {
            Map<String, Object> brokerInfo = kafkaAdmin.describeTopics("__consumer_offsets");
            builder.up().withDetail("brokers", kafkaAdmin.getConfigurationProperties().get("bootstrap.servers"));
        } catch (Exception e) {
            builder.down(e);
        }
    }
}
```

---

## Prometheus + Grafana Dashboard

### Prometheus scrape config

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'spring-boot-app'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['app:8080']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
```

### Key PromQL Queries

```promql
# HTTP request rate per endpoint
sum(rate(http_server_requests_seconds_count[5m])) by (uri, method, status)

# P99 latency
histogram_quantile(0.99, 
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le, uri))

# Error rate
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))
/ sum(rate(http_server_requests_seconds_count[5m]))

# JVM memory
jvm_memory_used_bytes{area="heap"}
jvm_memory_max_bytes{area="heap"}

# Thread pool utilization
executor_active_threads{name="taskExecutor"} / executor_pool_max_threads{name="taskExecutor"}

# HikariCP connection pool
hikaricp_connections_active / hikaricp_connections_max
hikaricp_connections_pending  # waiting for connection (should be 0)

# GC pressure
rate(jvm_gc_pause_seconds_sum[5m])
```

---

## Trade-offs

| Metric Type | Use for |
|-------------|---------|
| Counter | Total counts (requests, errors, orders) |
| Gauge | Current value (active users, queue size) |
| Timer | Latency (request duration, DB query time) |
| DistributionSummary | Value distribution (order amounts, file sizes) |

| Sampling Rate | Trade-off |
|--------------|-----------|
| 100% | Full visibility, high storage/CPU |
| 10-20% | Balance for production |
| 1% | Minimal overhead, low visibility |
| Adaptive | Best: increase on errors |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `production/configuration_secrets.md` – Externalized config, Vault
- `production/performance_tuning.md` – JVM metrics, GC tuning
- **Keywords:** Micrometer Observation API (mới nhất), @Observed annotation, ObservationRegistry, Loki (log aggregation), OpenTelemetry Collector, Jaeger vs Zipkin vs Tempo, Spring Boot Admin, Actuator security (securing /actuator endpoints), ELK Stack (Elasticsearch-Logstash-Kibana), Correlation ID, W3C Trace Context header
