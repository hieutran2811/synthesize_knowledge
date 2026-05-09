# Observability – Micrometer, Prometheus, OpenTelemetry

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Observability Overview

### What – Observability là gì?
**Observability** là khả năng hiểu trạng thái nội tại của hệ thống qua **external outputs**. Ba trụ cột:
- **Metrics** – số liệu định lượng theo thời gian (latency, error rate, throughput)
- **Logs** – events có cấu trúc với context (request details, errors)
- **Traces** – end-to-end request flow qua nhiều services

### How – Kiến trúc

```
Application
  ├── Micrometer (metrics facade)
  │     └── Prometheus registry → Prometheus → Grafana
  │     └── Datadog registry → Datadog
  │     └── CloudWatch registry → AWS CloudWatch
  │
  ├── OpenTelemetry SDK (traces + metrics + logs)
  │     └── OTLP exporter → OTel Collector → Jaeger / Tempo / Zipkin
  │
  └── SLF4J/Logback (logs)
        └── Loki / Elasticsearch
```

---

## 2. Micrometer – Metrics Facade

### What – Micrometer là gì?
**Micrometer** là vendor-neutral metrics facade cho JVM (như SLF4J nhưng cho metrics). Spring Boot Actuator tích hợp sẵn.

### How – Core Meter Types

```java
import io.micrometer.core.instrument.*;

@Service
public class OrderService {
    private final MeterRegistry registry;
    private final Counter orderCounter;
    private final Timer orderLatency;
    private final Gauge activeOrders;
    private final DistributionSummary orderAmountSummary;

    public OrderService(MeterRegistry registry) {
        this.registry = registry;

        // Counter – chỉ tăng (monotonic)
        this.orderCounter = Counter.builder("orders.created")
            .description("Total orders created")
            .tag("env", "prod")
            .register(registry);

        // Timer – latency measurement
        this.orderLatency = Timer.builder("orders.processing.duration")
            .description("Order processing time")
            .publishPercentiles(0.5, 0.95, 0.99)        // histogram percentiles
            .publishPercentileHistogram()                 // for Prometheus histogram_quantile
            .sla(Duration.ofMillis(100), Duration.ofMillis(500), Duration.ofSeconds(1))
            .register(registry);

        // Gauge – current value (can go up/down)
        List<Order> pendingOrders = new ArrayList<>();
        this.activeOrders = Gauge.builder("orders.pending.count",
                pendingOrders, List::size)
            .description("Currently pending orders")
            .register(registry);

        // DistributionSummary – arbitrary values (payment amounts, bytes)
        this.orderAmountSummary = DistributionSummary.builder("orders.amount")
            .description("Order amount distribution")
            .baseUnit("USD")
            .publishPercentiles(0.5, 0.9, 0.99)
            .register(registry);
    }

    public Order createOrder(CreateOrderRequest req) {
        return orderLatency.record(() -> {
            Order order = processOrder(req);
            orderCounter.increment(1.0);
            orderAmountSummary.record(order.getAmount().doubleValue());
            return order;
        });
    }
}
```

### How – Tags (Dimensions)

```java
// Tags là dimensions của metrics → filter/group trong Grafana
Counter.builder("http.requests")
    .tag("method", request.getMethod())
    .tag("uri", request.getRequestURI())   // CẢNH BÁO: high cardinality!
    .tag("status", String.valueOf(response.getStatus()))
    .register(registry)
    .increment();

// HIGH CARDINALITY → tránh dùng userId, orderId làm tag
// LOW CARDINALITY OK → status code, method, endpoint pattern, region

// Common tags (áp dụng cho tất cả metrics)
registry.config().commonTags(
    "application", "order-service",
    "version", "2.1.0",
    "region", System.getenv("AWS_REGION")
);
```

### How – Spring Boot Actuator Auto-configuration

```yaml
# application.yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics,env
      base-path: /actuator
  endpoint:
    health:
      show-details: always
      show-components: always
    prometheus:
      enabled: true
  metrics:
    export:
      prometheus:
        enabled: true
    distribution:
      percentiles-histogram:
        http.server.requests: true          # enable histograms for HTTP
      percentiles:
        http.server.requests: 0.5, 0.95, 0.99
      sla:
        http.server.requests: 100ms, 500ms, 1s
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active:default}
```

```java
// Custom health indicator
@Component
public class DatabaseHealthIndicator implements HealthIndicator {
    @Override
    public Health health() {
        try {
            long count = jdbcTemplate.queryForObject("SELECT 1", Long.class);
            return Health.up()
                .withDetail("database", "PostgreSQL")
                .withDetail("status", "Connected")
                .build();
        } catch (Exception e) {
            return Health.down()
                .withDetail("error", e.getMessage())
                .build();
        }
    }
}
```

---

## 3. Prometheus – Scraping & Alerting

### How – Prometheus Configuration

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:
  - job_name: "java-apps"
    metrics_path: "/actuator/prometheus"
    static_configs:
      - targets: ["order-service:8080", "payment-service:8080"]
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance

  # Kubernetes: auto-discover pods với annotation
  - job_name: "kubernetes-pods"
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
```

### How – PromQL (Prometheus Query Language)

```promql
# Request rate (per second, 5m window)
rate(http_server_requests_seconds_count{status="200"}[5m])

# Error rate percentage
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) /
sum(rate(http_server_requests_seconds_count[5m])) * 100

# 95th percentile latency
histogram_quantile(0.95,
  sum(rate(http_server_requests_seconds_bucket[5m])) by (le, uri))

# JVM heap usage percentage
jvm_memory_used_bytes{area="heap"} /
jvm_memory_max_bytes{area="heap"} * 100

# GC pause time rate
rate(jvm_gc_pause_seconds_sum[5m])

# Active DB connections
hikaricp_connections_active{pool="HikariPool-1"}

# Throughput (req/s)
sum(rate(http_server_requests_seconds_count[1m]))
```

### How – Alerting Rules

```yaml
# alerts/application.yml
groups:
  - name: application
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) /
          sum(rate(http_server_requests_seconds_count[5m])) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate: {{ $value | humanizePercentage }}"
          description: "Error rate is {{ $value | humanizePercentage }} on {{ $labels.application }}"

      - alert: SlowResponses
        expr: |
          histogram_quantile(0.95,
            sum(rate(http_server_requests_seconds_bucket[5m])) by (le)) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P95 latency > 1s: {{ $value }}s"

      - alert: JVMHeapHigh
        expr: |
          jvm_memory_used_bytes{area="heap"} /
          jvm_memory_max_bytes{area="heap"} > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "JVM heap usage {{ $value | humanizePercentage }}"
```

---

## 4. Distributed Tracing – OpenTelemetry

### What – Distributed Tracing là gì?
Theo dõi một **request end-to-end** qua nhiều services. Mỗi operation = **Span**, tập hợp spans liên quan = **Trace**.

```
Trace ID: abc123
  Span: api-gateway          (0ms - 250ms)
    ↳ Span: order-service    (10ms - 230ms)
        ↳ Span: db.query      (15ms - 45ms)    [SQL: SELECT FROM orders]
        ↳ Span: payment-svc  (50ms - 190ms)
            ↳ Span: db.query  (55ms - 80ms)
            ↳ Span: http.post (90ms - 180ms)   [Stripe API call]
```

### How – OpenTelemetry SDK

```xml
<!-- pom.xml -->
<dependencyManagement>
    <dependencies>
        <dependency>
            <groupId>io.opentelemetry</groupId>
            <artifactId>opentelemetry-bom</artifactId>
            <version>1.32.0</version>
            <type>pom</type>
            <scope>import</scope>
        </dependency>
    </dependencies>
</dependencyManagement>

<dependencies>
    <!-- Spring Boot 3.x: Micrometer Tracing (built on OTel) -->
    <dependency>
        <groupId>io.micrometer</groupId>
        <artifactId>micrometer-tracing-bridge-otel</artifactId>
    </dependency>
    <dependency>
        <groupId>io.opentelemetry</groupId>
        <artifactId>opentelemetry-exporter-otlp</artifactId>
    </dependency>
</dependencies>
```

```yaml
# application.yaml – Spring Boot 3.x Micrometer Tracing
management:
  tracing:
    sampling:
      probability: 1.0        # 100% in dev; 0.1 (10%) in prod
    propagation:
      type: w3c               # W3C Trace Context (standard)

spring:
  application:
    name: order-service

# OTel Collector endpoint
otel:
  exporter:
    otlp:
      endpoint: http://otel-collector:4318
  resource:
    attributes:
      service.name: ${spring.application.name}
      service.version: "2.1.0"
      deployment.environment: ${spring.profiles.active:prod}
```

### How – Custom Spans

```java
import io.micrometer.tracing.Tracer;
import io.micrometer.tracing.Span;

@Service
public class PaymentService {
    private final Tracer tracer;
    private final RestTemplate restTemplate;

    public PaymentResult processPayment(PaymentRequest req) {
        // Tạo custom span
        Span span = tracer.nextSpan()
            .name("payment.process")
            .tag("payment.method", req.getMethod())
            .tag("currency", req.getCurrency())
            .start();

        try (Tracer.SpanInScope ws = tracer.withSpan(span)) {
            // Tất cả operations trong scope này sẽ là child của span này
            validatePayment(req);
            ChargeResult result = chargeGateway(req);

            span.tag("payment.status", result.getStatus());
            return new PaymentResult(result);
        } catch (PaymentException e) {
            span.error(e);
            throw e;
        } finally {
            span.end();
        }
    }
}
```

### How – Trace Context Propagation

```java
// W3C traceparent header tự động propagate qua:
// - RestTemplate (với Spring Boot auto-config)
// - WebClient
// - Kafka headers
// - gRPC metadata

// Manual propagation cho custom HTTP client
Map<String, String> headers = new HashMap<>();
tracer.currentSpanCustomizer().tag("custom", "value");
// OTel propagator tự inject headers

// Kafka: trace context trong headers
@KafkaListener(topics = "orders")
public void consume(ConsumerRecord<String, OrderEvent> record, @Header KafkaHeaders headers) {
    // Micrometer tự động extract trace context từ Kafka headers
}
```

---

## 5. Grafana – Dashboards

### How – Grafana + Prometheus + Tempo

```
Grafana Dashboard:
├── Row: Application Metrics
│   ├── Panel: Request Rate (graph)
│   ├── Panel: Error Rate % (stat)
│   ├── Panel: P95/P99 Latency (graph)
│   └── Panel: Active Connections (gauge)
├── Row: JVM
│   ├── Panel: Heap Usage % (graph)
│   ├── Panel: GC Pause Time (graph)
│   ├── Panel: Thread Count (graph)
│   └── Panel: CPU Usage (graph)
└── Row: Infrastructure
    ├── Panel: Pod CPU (graph)
    └── Panel: Pod Memory (graph)
```

```json
// Grafana dashboard JSON snippet (Exemplars: link metrics → traces)
{
  "type": "graph",
  "title": "HTTP Request Latency",
  "targets": [{
    "expr": "histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (le))",
    "exemplarConfig": {
      "datasourceUid": "tempo",
      "color": "red",
      "labelMatchers": "traceID=$__value.labels.traceID"
    }
  }]
}
```

---

## 6. Compare & Trade-offs

### Compare – Tracing Backends

| | Jaeger | Zipkin | Tempo | Datadog APM |
|--|-------|--------|-------|-------------|
| Protocol | Jaeger/OTel | Zipkin/OTel | OTel | OTel/Datadog |
| Storage | Cassandra/ES/memory | ES/Cassandra/memory | Object storage (S3) | Managed |
| UI | Good | Basic | Grafana | Excellent |
| Cost | Open source | Open source | Open source | Expensive |
| Scalability | Good | OK | Excellent (cheap storage) | Excellent |

### Compare – Metrics Solutions

| | Prometheus + Grafana | Datadog | New Relic | CloudWatch |
|--|---------------------|---------|-----------|-----------|
| Cost | Open source (infra cost) | Expensive | Expensive | Per metric |
| Alerting | AlertManager | Built-in | Built-in | Built-in |
| Storage | Local TSDB (limited) | Managed | Managed | Managed |
| Learning curve | Medium | Low | Low | Low |
| Khi dùng | Self-hosted control | Enterprise budget | Enterprise | AWS-native |

### Trade-offs
- **Sampling rate**: 100% traces = costly; dùng head-based sampling (random %) hoặc tail-based (giữ error traces)
- **Cardinality**: nhiều tag dimensions → expensive storage/query; avoid user-specific tags trong metrics
- **OTel vs vendor SDK**: OTel = vendor-neutral nhưng setup phức tạp hơn; vendor SDK = easier nhưng lock-in
- **Push vs Pull**: Prometheus pull (scrape) = simpler cho infra; push (StatsD, InfluxDB) tốt hơn khi target không exposable

---

### Ghi chú – Chủ đề tiếp theo
> **19.3 Messaging**: Spring Kafka (producer/consumer/error handling), Spring AMQP, transactional outbox pattern
