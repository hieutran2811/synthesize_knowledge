---
title: "Spring Boot Production – Deep Dive"
topic: springboot
level: mixed
review_status: needs_review
content_updated: 2026-07-27
last_verified: null
version_scope: "Ví dụ mặc định nhắm tới Spring Boot 3"
source_count: 8
---
# Spring Boot Production – Deep Dive

Tài liệu này nối các mảnh ghép cần thiết để đưa một ứng dụng Spring Boot lên **production (môi trường thật)**: quan sát được, dừng an toàn, đóng gói hiệu quả và chịu tải có kiểm soát. Các con số cấu hình chỉ là điểm bắt đầu; kết luận cuối cùng phải dựa trên **SLO (Service Level Objective – mục tiêu mức dịch vụ)**, tải thực tế và giới hạn của hệ thống phụ thuộc.

> 💡 **Giải thích dễ hiểu:** Đưa ứng dụng lên production giống như vận hành một nhà hàng, không chỉ là nấu được món ăn. Actuator là bảng kiểm tra thiết bị, metric là đồng hồ đo, trace là camera lần theo một đơn hàng, còn probe và graceful shutdown giúp nhà hàng mở/đóng cửa mà không bỏ rơi khách.

> **Phạm vi phiên bản:** Ví dụ mặc định nhắm tới Spring Boot **3.5.x** trên Java 21. Các hộp “Boot 4.1” nêu khác biệt đáng chú ý khi nâng cấp. Luôn kiểm tra release notes và configuration metadata của đúng patch version đang chạy.

Xem thêm: [Thuật ngữ Spring Boot](glossary.md).

## Cách tư duy trước khi cấu hình

| Câu hỏi | Ý nghĩa trong production |
|---|---|
| **What** | Thành phần đang đo, bảo vệ hoặc tối ưu điều gì? |
| **How** | Luồng dữ liệu/tín hiệu đi qua những thành phần nào? |
| **Why** | Nó giảm rủi ro hay cải thiện SLO nào? |
| **When** | Khi nào nên dùng, và khi nào sự phức tạp chưa đáng? |
| **Trade-off** | Đổi lấy chi phí CPU, RAM, độ trễ, bảo mật hay vận hành nào? |

```text
Request → Spring Boot → DB/API/queue
   │            │
   ├─ log       ├─ health/readiness → Kubernetes
   ├─ metric    └─ trace → OTLP Collector
   └────────────────────→ Prometheus/Grafana/alert
```

## Mục lục

1. [Actuator – Endpoint và Health](#1-actuator--endpoint-và-health)
2. [Micrometer và Prometheus](#2-micrometer-và-prometheus)
3. [OpenTelemetry Tracing](#3-opentelemetry-tracing)
4. [GraalVM Native Image](#4-graalvm-native-image)
5. [Docker Layered JAR](#5-docker-layered-jar)
6. [Kubernetes Probe và Graceful Shutdown](#6-kubernetes-probe-và-graceful-shutdown)
7. [Virtual Thread](#7-virtual-thread-spring-boot-32)
8. [Tuning JVM và HikariCP](#8-tuning-jvm-và-hikaricp)

---

## 1. Actuator – Endpoint và Health

**Spring Boot Actuator (bộ endpoint vận hành)** cung cấp trạng thái sức khỏe, thông tin build, metric và các thao tác quản trị. Nó trả lời “ứng dụng còn sống không?” và “ứng dụng đã sẵn sàng nhận traffic chưa?”, nhưng không thay thế hệ thống monitoring.

### What / How / Why / Components

- `HealthIndicator` đóng góp trạng thái cho `/actuator/health`.
- **Liveness (khả năng còn sống)** cho biết tiến trình có mắc lỗi nội bộ không thể tự phục hồi hay không.
- **Readiness (khả năng sẵn sàng)** cho biết instance có nên nhận request mới hay không.
- Endpoint quản trị có thể đọc hoặc thay đổi trạng thái runtime, vì vậy phải coi nó như một control plane nhạy cảm.

> 💡 **Giải thích dễ hiểu:** Liveness giống nhịp tim: mất nhịp thì cần cấp cứu/restart. Readiness giống biển “đang phục vụ”: bếp vẫn hoạt động nhưng có thể tạm ngừng nhận khách khi nguyên liệu chưa sẵn sàng.

### 1.1 Cấu hình nền tảng

```yaml
management:
  endpoints:
    web:
      exposure:
        # Least privilege: chỉ mở endpoint thật sự cần.
        include: health, info, prometheus
      base-path: /actuator
  endpoint:
    health:
      show-details: when-authorized   # never | always | when-authorized
      show-components: when-authorized
      roles: ACTUATOR_ADMIN
      probes:
        enabled: true   # /actuator/health/liveness, /actuator/health/readiness
        add-additional-paths: true    # /livez và /readyz trên cổng ứng dụng
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
      mode: simple
    build:
      enabled: true
```

`/env`, `/configprops`, `/loggers`, heap dump và endpoint có thao tác ghi không nên được mở chỉ vì “tiện debug”. Nếu buộc phải dùng, hãy đặt management server sau mạng quản trị riêng, xác thực chặt và ghi audit.

> **Ghi chú Boot 3.5/4.1:** Cả hai dòng đều quản lý `LivenessState`/`ReadinessState` và hỗ trợ `management.endpoint.health.probes.add-additional-paths=true`. Cấu hình này đặc biệt quan trọng khi management server dùng cổng riêng: probe trên cổng quản trị có thể vẫn xanh trong khi cổng phục vụ request đã hỏng.

### 1.2 Health Indicator tùy chỉnh

```java
// Custom health check
@Component
public class ExternalServiceHealthIndicator implements HealthIndicator {

    private final ExternalServiceClient client;

    ExternalServiceHealthIndicator(ExternalServiceClient client) {
        this.client = client;
    }

    @Override
    public Health health() {
        try {
            // ExternalServiceClient phải có connect/read timeout ngắn.
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
                    .withDetail("reason", "dependency-not-ready")
                    .build();
            }
        } catch (Exception e) {
            return Health.down()
                .withDetail("service", "external-payment")
                .withDetail("error", e.getClass().getSimpleName())
                .build();
        }
    }
}

// Reactive health indicator
@Component
public class ReactiveDbHealthIndicator implements ReactiveHealthIndicator {

    private final DatabaseClient databaseClient;

    ReactiveDbHealthIndicator(DatabaseClient databaseClient) {
        this.databaseClient = databaseClient;
    }

    @Override
    public Mono<Health> health() {
        return databaseClient.sql("SELECT 1")
            .fetch()
            .one()
            .timeout(Duration.ofSeconds(2))
            .map(result -> Health.up().withDetail("db", "reactive-postgres").build())
            .onErrorReturn(Health.down().withDetail("error", "DB unreachable").build());
    }
}

// Boot tự chuyển sang ACCEPTING_TRAFFIC sau khi runner hoàn tất.
// Chỉ cần publish thủ công cho trạng thái nghiệp vụ như maintenance.
@Component
public class MaintenanceAvailability {

    private final ApplicationContext context;

    MaintenanceAvailability(ApplicationContext context) {
        this.context = context;
    }

    public void startMaintenance() {
        AvailabilityChangeEvent.publish(context, ReadinessState.REFUSING_TRAFFIC);
    }

    public void finishMaintenance() {
        AvailabilityChangeEvent.publish(context, ReadinessState.ACCEPTING_TRAFFIC);
    }
}
```

### Khi dùng và quy tắc thiết kế health check

- Không đưa DB, Redis, Kafka hay API ngoài vào **liveness**. Một dependency chung bị lỗi có thể khiến Kubernetes restart đồng loạt mọi pod và tạo cascading failure.
- Readiness có thể kiểm tra dependency thiết yếu, nhưng phải có timeout ngắn, bulkhead/circuit breaker và tốt nhất là cache kết quả. Health endpoint không được trở thành nguồn tải mới lên dependency đang yếu.
- Không trả stack trace, URL nội bộ, credential hoặc message lỗi thô trong health detail.
- Boot mặc định không tự thêm mọi indicator vào nhóm readiness/liveness. Hãy include có chủ đích, ví dụ `readinessState,externalService`.

**Khi dùng:** health check phù hợp để quyết định routing hoặc hỗ trợ vận hành. **Không dùng:** nó không phải truy vấn chẩn đoán sâu, synthetic test toàn hệ thống hay bằng chứng rằng mọi nghiệp vụ đều đúng.

### 1.3 Endpoint Actuator tùy chỉnh

```java
@Component
@Endpoint(id = "featureflags")
public class FeatureFlagEndpoint {

    private final FeatureFlagService featureFlagService;

    FeatureFlagEndpoint(FeatureFlagService featureFlagService) {
        this.featureFlagService = featureFlagService;
    }

    @ReadOperation
    public Map<String, Boolean> getFlags() {
        return featureFlagService.getAllFlags();
    }

    @WriteOperation
    public void setFlag(@Selector String flagName, boolean enabled) {
        featureFlagService.setFlag(flagName, enabled);
    }

    @DeleteOperation
    public void resetFlag(@Selector String flagName) {
        featureFlagService.reset(flagName);
    }
}

// Access:
// GET  /actuator/featureflags
// POST /actuator/featureflags/dark-mode  {"enabled": true}
// DELETE /actuator/featureflags/dark-mode
```

Mỗi endpoint chỉ nên có một operation cho mỗi loại read/write/delete. Một endpoint thay đổi feature flag là thao tác production có ảnh hưởng thật: yêu cầu phân quyền, audit, idempotency và quy trình rollback; thường một hệ thống feature-flag chuyên dụng phù hợp hơn.

Muốn gọi endpoint trên qua HTTP phải thêm `featureflags` vào exposure include. Chỉ làm vậy trên management network đã bảo vệ; định nghĩa `@Endpoint` không đồng nghĩa endpoint tự động được public.

### 1.4 Bảo mật Actuator

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

Đừng nhầm `permitAll()` cho health với việc công khai health detail. `show-details: when-authorized` và `roles` vẫn phải được cấu hình đúng. Nếu dùng cookie/session, xử lý CSRF cho endpoint ghi một cách có chủ đích; không tắt CSRF cho toàn ứng dụng chỉ để POST vào Actuator.

### So sánh và trade-off

| Lựa chọn | Ưu điểm | Rủi ro / chi phí |
|---|---|---|
| Health tối giản | Nhanh, ổn định, ít side effect | Ít thông tin chẩn đoán |
| Readiness kiểm tra dependency | Ngừng nhận traffic khi không thể phục vụ | Có thể loại toàn bộ pod nếu dependency chung hỏng |
| Management cùng cổng | Đơn giản, probe đúng web stack chính | Cần chặn endpoint nhạy cảm trên ingress |
| Management cổng riêng | Tách mạng/quyền truy cập | Probe có thể xanh giả; nên thêm `/livez`, `/readyz` ở cổng chính |

### Production note

Mục tiêu của health endpoint là quyết định tự động thật nhanh và ổn định. Chẩn đoán sâu nên đi qua metric, trace, log và runbook có quyền truy cập phù hợp.

---

## 2. Micrometer và Prometheus

**Micrometer (lớp facade cho metric)** chuẩn hóa cách ứng dụng tạo counter, gauge, timer; **Prometheus (hệ thống time-series pull-based)** định kỳ scrape các mẫu đó. Metric trả lời “hệ thống đang có xu hướng gì?”, không kể lại toàn bộ một request như trace.

### What / How / Why / Components

```text
Business code / Spring instrumentation
          ↓ record
      MeterRegistry
          ↓ expose
 /actuator/prometheus ← scrape ← Prometheus ← query/alert ← Grafana
```

> 💡 **Giải thích dễ hiểu:** Metric giống bảng đồng hồ ô tô: biết tốc độ, nhiệt độ và mức nhiên liệu với chi phí thấp. Nó không ghi lại video của từng chuyến đi, nên muốn điều tra một request cụ thể phải dùng trace/log.

### 2.1 Dependency

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

### 2.2 Metric nghiệp vụ tùy chỉnh

```java
@Service
public class OrderMetricsService {

    private final Counter orderCreatedCounter;
    private final Counter orderFailedCounter;
    private final Timer orderProcessingTimer;
    private final DistributionSummary orderAmountSummary;
    private final AtomicInteger pendingOrdersGauge;
    private final MeterRegistry registry;

    public OrderMetricsService(MeterRegistry registry) {
        this.registry = registry;
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
            .serviceLevelObjectives(
                Duration.ofMillis(100),
                Duration.ofMillis(500),
                Duration.ofSeconds(1))
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
        registry.counter("orders.by.status",
            "status", status.name(),
            "region", region
        ).increment();
    }
}
```

**Cardinality (số lượng tổ hợp nhãn)** phải hữu hạn. `status` và danh sách `region` kiểm soát được là tag tốt; `userId`, `orderId`, email, exception message hay URL thô là tag xấu vì có thể tạo hàng triệu time series và làm Prometheus quá tải. Giữ strong reference cho object đứng sau gauge; field `pendingOrdersGauge` ở trên làm đúng điều đó.

### 2.3 `@Timed` / `@Counted` qua AOP

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

**AOP (Aspect-Oriented Programming – lập trình hướng khía cạnh)** ở đây dựa trên Spring proxy: self-invocation trong cùng bean không đi qua proxy, và annotate controller/repository vốn đã được Spring instrument có thể sinh metric trùng. Với observability mới, có thể ưu tiên `@Observed` và bật `management.observations.annotations.enabled=true`.

> **Ghi chú Boot 3.5/4.1:** Boot 3.5 thường dùng `spring-boot-starter-aop`; tài liệu Boot 4.1 dùng `spring-boot-starter-aspectj`. Tên starter và auto-configuration là điểm cần kiểm tra khi nâng major version.

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

```promql
# Grafana dashboard query examples (PromQL)
# Request rate per second
sum(rate(http_server_requests_seconds_count{
  job="spring-boot-app", uri!~"/actuator.*"
}[5m]))

# P99 toàn service; giữ le khi aggregate bucket
histogram_quantile(
  0.99,
  sum by (le) (rate(http_server_requests_seconds_bucket{
    job="spring-boot-app", uri!~"/actuator.*"
  }[5m]))
)

# Tỷ lệ lỗi; clamp_min tránh chia cho 0 khi không có traffic
sum(rate(http_server_requests_seconds_count{
  job="spring-boot-app", uri!~"/actuator.*", status=~"5.."
}[5m]))
  / clamp_min(sum(rate(http_server_requests_seconds_count{
      job="spring-boot-app", uri!~"/actuator.*"
    }[5m])), 1e-9)

# JVM heap usage
sum(jvm_memory_used_bytes{job="spring-boot-app", area="heap"})
  / clamp_min(sum(jvm_memory_max_bytes{job="spring-boot-app", area="heap"}), 1)

# HikariCP pool usage theo instance/pool
max by (instance, pool) (
  hikaricp_connections_active{job="spring-boot-app"}
)
  / clamp_min(max by (instance, pool) (
      hikaricp_connections_max{job="spring-boot-app"}
    ), 1)
```

### 2.5 Alerting Rules

```yaml
# alerting-rules.yml
groups:
  - name: spring-boot-alerts
    rules:
      - alert: HighErrorRate
        expr: |
          sum(rate(http_server_requests_seconds_count{
            job="spring-boot-app", uri!~"/actuator.*", status=~"5.."
          }[5m]))
          / clamp_min(sum(rate(http_server_requests_seconds_count{
              job="spring-boot-app", uri!~"/actuator.*"
            }[5m])), 1e-9) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Error rate {{ $value | humanizePercentage }} on {{ $labels.instance }}"

      - alert: SlowP99Latency
        expr: |
          histogram_quantile(
            0.99,
            sum by (le) (rate(http_server_requests_seconds_bucket{
              job="spring-boot-app", uri!~"/actuator.*"
            }[5m]))
          ) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P99 latency {{ $value }}s — degraded performance"

      - alert: HikariPoolExhausted
        expr: |
          max by (instance, pool) (
            hikaricp_connections_pending{job="spring-boot-app"}
          ) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "HikariCP connection pool exhausted on {{ $labels.instance }}"
```

### Khi dùng, so sánh và trade-off

| Cơ chế | Tốt cho | Không tốt cho | Chi phí chính |
|---|---|---|---|
| Counter | Tổng số event tăng dần; dùng `rate()` | Giá trị có thể tăng/giảm | Thấp |
| Gauge | Trạng thái tức thời như queue depth | Đếm event bị bỏ lỡ giữa hai lần scrape | Thấp |
| Histogram/Timer | Phân phối latency, percentile gộp nhiều instance | Tag cardinality cao | Nhiều time series theo bucket |
| Client-side percentile | Xem percentile của từng instance | Không aggregate chính xác giữa instance | CPU/RAM tại app |

### Production note

Ngưỡng `5%`, `2s` và khoảng `[5m]` ở trên chỉ minh họa. Production nên alert theo SLO/error budget, có `for` đủ dài để tránh nhiễu, và thử alert trong staging. Tên metric có thể thay đổi theo Micrometer/Prometheus client; luôn đối chiếu dữ liệu thật tại `/actuator/prometheus`.

---

## 3. OpenTelemetry Tracing

**Distributed tracing (truy vết phân tán)** nối các **span (chặng xử lý)** của cùng một request thành trace xuyên qua nhiều service. Spring Boot dùng Micrometer Observation/Tracing làm API chính; OpenTelemetry là một implementation/export path, còn **OTLP (OpenTelemetry Protocol – giao thức xuất telemetry)** chuyển dữ liệu tới collector/backend.

### What / How / Why / Components

```text
HTTP request → server span → service span → HTTP/DB/message span
                    │ traceId chung
                    └→ OTLP Collector → Tempo/Jaeger/vendor backend
```

> 💡 **Giải thích dễ hiểu:** Trace giống mã vận đơn. Mỗi kho ghi lại một chặng bằng `span`, còn `traceId` giúp ghép tất cả chặng thành hành trình của đúng kiện hàng.

### 3.1 Auto-configuration trên Spring Boot 3.5

```xml
<!-- Cần thêm spring-boot-starter-actuator nếu dự án chưa có -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
<!-- Chỉ cần khi dùng annotation như @NewSpan/@Observed ở ví dụ dưới -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
</dependency>
```

```yaml
management:
  observations:
    annotations:
      enabled: true
  tracing:
    enabled: true
    sampling:
      probability: ${TRACING_PROBABILITY:0.1}
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces

# Boot tự thêm correlation ID; mẫu này chỉ dùng khi muốn tùy biến.
logging:
  pattern:
    correlation: "[${spring.application.name:},%X{traceId:-},%X{spanId:-}] "
  include-application-name: false
```

`1.0` hữu ích khi debug môi trường ít tải, nhưng có thể quá đắt trong production. Chọn sampling theo lưu lượng, chi phí backend và khả năng điều tra SLO; cân nhắc tail-based sampling tại collector nếu cần giữ lỗi/trace chậm.

> **Ghi chú Boot 4.1:** Cách tiếp cận vẫn là Micrometer Tracing + OpenTelemetry, nhưng namespace OTLP trace đổi sang `management.opentelemetry.tracing.export.otlp.*`, ví dụ `management.opentelemetry.tracing.export.otlp.endpoint`. Boot 4.1 map một tập biến `OTEL_*` sang property Spring; không giả định mọi biến OTEL SDK đều được hỗ trợ. Khi nâng major version, không copy nguyên `management.otlp.tracing.*` của 3.5.

### 3.2 Span tùy chỉnh

```java
@Service
public class OrderService {

    private final Tracer tracer;

    OrderService(Tracer tracer) {
        this.tracer = tracer;
    }

    public Order processOrder(CreateOrderRequest req) {
        Span span = tracer.nextSpan().name("process-order");

        try (Tracer.SpanInScope scope = tracer.withSpan(span.start())) {
            span.tag("order.channel", req.getChannel().name()); // tập giá trị hữu hạn

            // Span events
            span.event("validation-started");
            validateOrder(req);
            span.event("validation-completed");

            Order order = orderRepository.save(Order.from(req));
            span.tag("order.result", "created");

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
    public void sendConfirmationEmail(Long orderId) {
        emailService.sendOrderConfirmation(orderId);
    }
}
```

Không đưa email, token, payload, `customerId` hoặc `orderId` vào attribute chỉ vì trace “không phải metric”. Đây vẫn là dữ liệu có thể nhạy cảm và cardinality cao. Cũng không tạo span thủ công quanh controller/repository đã được instrument, nếu không sẽ có span trùng và trace khó đọc. Với logic nghiệp vụ muốn sinh cả metric lẫn trace, ưu tiên `ObservationRegistry`; dùng `Tracer` thấp hơn khi chỉ cần span.

### 3.3 Context propagation

```java
// Boot 3.5: đăng ký decorator cho AsyncTaskExecutor/@Async.
@Bean
ContextPropagatingTaskDecorator contextPropagatingTaskDecorator() {
    return new ContextPropagatingTaskDecorator();
}
```

- Dùng `RestTemplateBuilder`, `RestClient.Builder` hoặc `WebClient.Builder` do Boot auto-configure; tự `new` client có thể làm mất instrumentation và trace header.
- `@Async`/executor không tự bảo toàn context trong mọi cấu hình. Boot 3.5 yêu cầu `ContextPropagatingTaskDecorator`; Boot 4.1 còn có `spring.task.execution.propagate-context=true`, nhưng hãy kiểm chứng executor tùy chỉnh.
- Với Reactor, Boot 3.5/4.1 hỗ trợ `spring.reactor.context-propagation=auto`. `ThreadLocal` không tự xuất hiện lại qua mọi operator nếu chưa bật cơ chế này.
- W3C Trace Context thường là lựa chọn liên thông tốt. Chỉ bật B3 hoặc baggage khi hệ sinh thái yêu cầu; baggage đi qua mạng nên phải nhỏ, hữu hạn và không chứa secret.

### So sánh, khi dùng và trade-off

| Cách | Ưu điểm | Trade-off |
|---|---|---|
| Micrometer + OTEL bridge | Tích hợp tự nhiên với Spring Observation | Semantic convention theo Spring/Micrometer |
| OTEL Java Agent | Nhanh có coverage mà ít sửa code | Khó kiểm soát hơn, cần quản lý agent/version |
| OTEL community starter | Bám hệ sinh thái OTEL | Khác auto-config/convention chính thức của Spring |
| Span thủ công | Diễn tả bước nghiệp vụ quan trọng | Dễ trùng span, lộ dữ liệu, tăng chi phí |

### Production note

Production nên export qua collector thay vì để mọi service phụ thuộc trực tiếp một vendor backend. Đặt timeout/queue giới hạn cho exporter và theo dõi dropped spans; telemetry không được làm request nghiệp vụ thất bại.

---

## 4. GraalVM Native Image

**GraalVM Native Image (ảnh thực thi native)** phân tích ứng dụng theo **closed-world assumption (giả định thế giới đóng)** và biên dịch trước thành executable cho một OS/architecture cụ thể. Spring AOT tạo code/hint để giảm những hành vi động mà native-image không thể tự suy ra.

> 💡 **Giải thích dễ hiểu:** JVM giống bếp có đầu bếp tối ưu món trong lúc nhà hàng chạy; native image giống suất ăn đã chuẩn bị và đóng hộp sẵn. Mở hộp rất nhanh, nhưng đổi nguyên liệu/quy trình vào phút chót khó hơn.

### 4.1 What / How / Why / Components

```
JVM:    source → bytecode → JVM → interpreter/JIT → machine code lúc chạy
Native: source → bytecode → Spring AOT + GraalVM analysis → native executable

AOT = Ahead-Of-Time (biên dịch/xử lý trước lúc chạy)
Điểm khó = reflection, resource, proxy, serialization và dynamic class loading phải nhìn thấy lúc build
```

Native image thường khởi động nhanh và giảm memory footprint, nhưng mức cải thiện phụ thuộc ứng dụng, GraalVM/JDK, traffic và container limit. Không cam kết các con số mili-giây/MB trước khi benchmark artifact thật.

### 4.2 Build setup

```xml
<!-- pom.xml -->
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
    <configuration>
        <imageName>my-app</imageName>
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
```

Ưu tiên profile `native` do Spring Boot parent cung cấp hoặc Cloud Native Buildpacks. Không thêm đại trà `--initialize-at-build-time` cho thư viện: khởi tạo class sai thời điểm có thể đóng băng state môi trường/build vào executable hoặc gây lỗi khó đoán. Chỉ thêm build arg khi đã hiểu lỗi và có test bảo vệ.

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

### 4.4 Kiểm thử native image

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

// Đây vẫn là smoke test trên JVM, chưa chứng minh executable native hoạt động.
```

```bash
# 1. Build JAR có AOT assets, rồi chạy AOT mode trên JVM để phản hồi nhanh
./mvnw -Pnative package
java -Dspring.aot.enabled=true -jar target/my-app.jar

# 2. Chạy test thực sự bên trong native image (phù hợp CI định kỳ)
./mvnw -PnativeTest test
```

Native test tốn thời gian nhưng mới bắt được vấn đề reachability/reflection/resource thực tế. Ưu tiên test đường đi có JSON binding, proxy, security, database driver, migration, template, TLS và serialization.

### 4.5 Native so với JVM: so sánh và trade-off

| Aspect | JVM | Native |
|--------|-----|--------|
| Startup | Có warm-up; thường chậm hơn | Thường nhanh hơn |
| Memory footprint | Thường cao hơn lúc idle | Thường thấp hơn, phải đo RSS |
| Peak throughput | JIT có thể tối ưu tốt khi chạy lâu | Có thể thấp hoặc cao hơn tùy workload |
| Build | Nhanh, portable bytecode | Chậm hơn, theo OS/architecture |
| Dynamic features | Linh hoạt | Cần AOT hint/reachability metadata |
| Tooling | Profiling/debugging trưởng thành | Hạn chế hơn nhưng đang cải thiện |
| Phù hợp | Service chạy lâu, cần peak throughput/tooling | Serverless, scale-to-zero, CLI, mật độ instance cao |

### Khi dùng và production note

- Chọn native khi startup time hoặc memory density là ràng buộc có số đo, không chỉ vì “microservice nên native”.
- Chọn JVM khi cần dynamic plugin/class loading, profiling sâu, build nhanh hoặc peak throughput sau warm-up.
- Benchmark cả startup, RSS, CPU, p95/p99 và throughput dưới cùng workload. Tính cả build time, CI cache và thời gian xử lý hint.
- Test executable native trên cùng base image/libc và architecture production. Native image không cross-compile tùy ý.

> **Ghi chú Boot 3.5/4.1:** Cả hai dùng Spring AOT, GraalVM Native Build Tools và buildpacks. Lệnh `-Pnative`/`-PnativeTest` là luồng chuẩn khi dùng Spring Boot parent. Boot 4.1 có dependency/plugin baseline mới; hãy tái tạo hint và native test thay vì tái dùng binary hoặc metadata cũ.

---

## 5. Docker Layered JAR

**Layered JAR (JAR có chỉ mục lớp)** tách dependency ổn định khỏi application code thường đổi. Mục tiêu chính là tái sử dụng cache của OCI image và chỉ push/pull lớp nhỏ khi sửa code.

> 💡 **Giải thích dễ hiểu:** Thay vì đóng cả tủ quần áo vào một thùng mỗi lần đổi áo, layered JAR chia thành nhiều ngăn. Đổi áo chỉ cần đóng lại ngăn áo, không phải vận chuyển lại mọi thứ.

### 5.1 What / How / Why / Components

```
Traditional fat JAR: All layers change on every build → large Docker cache invalidation
Layered JAR:
  Layer 1: dependencies (rarely change)     ← cached
  Layer 2: spring-boot-loader (rarely)       ← cached
  Layer 3: snapshot-dependencies (sometimes) ← cached
  Layer 4: application code (changes often)  ← always re-built (small)
```

Layer mặc định được sắp từ ít đổi tới hay đổi: `dependencies`, `spring-boot-loader`, `snapshot-dependencies`, `application`. Layering cải thiện build/pull cache; nó không tự làm code chạy nhanh hơn sau warm-up.

### 5.2 Build layered JAR

```xml
<!-- pom.xml — repackaged archive có layers.idx mặc định ở Boot 3.5/4.1 -->
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

Nếu không cần Dockerfile tùy chỉnh, `./mvnw spring-boot:build-image` dùng Cloud Native Buildpacks để tạo OCI image có layer và mặc định vận hành non-root. Dockerfile thủ công phù hợp khi tổ chức cần base image, CA certificate hoặc hardening riêng.

### 5.3 Dockerfile

```dockerfile
# Stage 1: Extract Boot layers bằng jarmode=tools (Boot 3.3+)
FROM eclipse-temurin:21-jre-jammy AS builder
WORKDIR /builder
ARG JAR_FILE=target/*.jar
COPY ${JAR_FILE} application.jar
RUN java -Djarmode=tools -jar application.jar \
    extract --layers --destination extracted

# Stage 2: Build final image
FROM eclipse-temurin:21-jre-jammy

# Security: non-root user
RUN groupadd --system appgroup \
    && useradd --system --gid appgroup --create-home appuser

WORKDIR /application

# Copy layers in order (least-to-most frequently changing)
COPY --from=builder /builder/extracted/dependencies/ ./
COPY --from=builder /builder/extracted/spring-boot-loader/ ./
COPY --from=builder /builder/extracted/snapshot-dependencies/ ./
COPY --from=builder /builder/extracted/application/ ./

# JVM tự đọc JAVA_TOOL_OPTIONS; JSON ENTRYPOINT không expansion JAVA_OPTS.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=60.0 -XX:+ExitOnOutOfMemoryError"

EXPOSE 8080
USER appuser

ENTRYPOINT ["java", "-jar", "application.jar"]
```

Base image Alpine dùng musl và nhỏ, nhưng một số native library/agent mong glibc. Chọn base image theo compatibility và quy định vá CVE, không chỉ theo kích thước. Trong Kubernetes thường bỏ Docker `HEALTHCHECK` để tránh hai cơ chế health khác nhau và việc image tối giản thiếu `curl/wget`.

`jarmode=tools` không dùng được với fully executable JAR đã prepend launch script. Với artifact dành cho container extraction, không bật launch script của Spring Boot Maven/Gradle plugin.

### 5.4 Cache build và supply-chain

- Pin image bằng digest trong pipeline production; quét CVE và sinh SBOM.
- Tách dependency resolution khỏi source code hoặc dùng BuildKit cache cho Maven repository.
- Không bake secret, token Maven hay private key vào image/layer; dùng secret mount của CI.
- Dùng `.dockerignore` để loại `.git`, log, dump và artifact không cần.
- Giữ runtime image chỉ có JRE và artifact; compiler/build tool ở builder stage.

### So sánh và trade-off

| Cách đóng gói | Ưu điểm | Trade-off |
|---|---|---|
| `java -jar` một fat JAR | Rất đơn giản | Cache kém nếu copy nguyên JAR |
| JAR extract theo layer | Cache/pull tốt, dễ tùy biến image | Dockerfile phụ thuộc layout/tool đúng version |
| Buildpacks | Ít boilerplate, layer/non-root/SBOM tốt | Ít kiểm soát chi tiết hơn |
| Native image | Startup/memory có thể tốt | Build chậm, cần native compatibility test |

### Khi dùng và production note

Chọn Buildpacks khi cần mặc định an toàn và pipeline đơn giản; chọn Dockerfile layer khi cần kiểm soát base image/hardening. Dù chọn cách nào, hãy đo cache hit, image pull time, startup, kích thước và tần suất vá base image trong CI/CD thật.

> **Ghi chú Boot 3.5/4.1:** Dùng `-Djarmode=tools`, không dùng ví dụ cũ `-Djarmode=layertools`. Lệnh `extract --layers` tạo layout có `application.jar`, vì vậy chạy `java -jar application.jar`; không hard-code class `JarLauncher`, package của launcher đã thay đổi qua các phiên bản.

---

## 6. Kubernetes Probe và Graceful Shutdown

**Kubernetes probe (phép thăm dò container)** và **graceful shutdown (dừng mềm)** điều khiển hai đầu vòng đời: chỉ route traffic khi app đã sẵn sàng, rồi ngừng nhận request mới trước khi kết thúc tiến trình.

> 💡 **Giải thích dễ hiểu:** Startup probe là kiểm tra cửa hàng đã mở xong chưa; readiness là biển “nhận khách”; liveness là kiểm tra cửa hàng còn vận hành được không. Khi đóng cửa, graceful shutdown lật biển trước rồi phục vụ nốt khách đang ở trong.

### 6.1 What / How / Why / Components

| Probe | Câu hỏi | Kubernetes làm gì khi fail? |
|---|---|---|
| `startupProbe` | Ứng dụng đã khởi động xong chưa? | Chưa chạy liveness/readiness; restart nếu vượt ngưỡng |
| `readinessProbe` | Pod có nên nhận traffic mới không? | Gỡ pod khỏi Service endpoints, không restart |
| `livenessProbe` | Tiến trình có tự phục hồi được không? | Restart container |

```text
Starting ──startup OK──→ Ready/Serving ──SIGTERM──→ Refusing traffic
   │                         │                         │
 startup fail            liveness fail          finish in-flight
   └─ restart                └─ restart               └─ exit
```

### 6.2 Cấu hình probe

```yaml
# application.yml
management:
  endpoint:
    health:
      probes:
        enabled: true
        add-additional-paths: true  # /livez và /readyz trên main port
  health:
    livenessstate:
      enabled: true
    readinessstate:
      enabled: true

```

```yaml
# K8s deployment.yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 45
      containers:
        - name: app
          image: myapp:1.0.0

          livenessProbe:
            httpGet:
              path: /livez
              port: 8080
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3

          startupProbe:
            httpGet:
              path: /livez
              port: 8080
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

          # Kubernetes 1.32+: cho endpoint/load balancer thời gian đồng bộ.
          lifecycle:
            preStop:
              sleep:
                seconds: 10
```

Các giá trị startup, CPU và memory ở trên chỉ minh họa. Đo phân phối startup và peak RSS/CPU rồi đặt request/limit có headroom. Nếu management server ở cổng khác, `/livez` và `/readyz` trên main port còn kiểm tra được chính web stack phục vụ user.

### 6.3 Graceful shutdown

```yaml
# application.yml
server:
  shutdown: graceful  # mặc định ở Boot 3.5/4.1; ghi rõ để thể hiện chủ đích
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

```java
// Cleanup tài nguyên riêng của ứng dụng; phải idempotent và có timeout.
@Component
public class GracefulShutdownHandler {

    @PreDestroy
    public void onShutdown() {
        log.info("Starting graceful shutdown...");
        // Flush bounded buffer / stop custom consumer nếu lifecycle của nó
        // chưa được Spring quản lý. Không sleep tùy ý tại đây.
    }
}
```

Boot hiện bật graceful shutdown mặc định cho Tomcat, Jetty, Reactor Netty và Undertow: khi context đóng, readiness chuyển sang `REFUSING_TRAFFIC`, request mới bị từ chối và request đang chạy có một grace period. Vì vậy không cần tự publish readiness trong `ContextClosedEvent`; callback đó còn có thể quá muộn hoặc lặp logic framework.

`preStop` sleep xử lý khoảng đua giữa việc pod bị terminate và endpoint/load balancer ngừng route. Thời gian cần thiết phụ thuộc hạ tầng. `terminationGracePeriodSeconds` phải lớn hơn `preStop` + shutdown timeout + biên an toàn; nếu hết hạn, Kubernetes gửi `SIGKILL` và mọi cleanup dừng ngay. Trên Kubernetes cũ hơn 1.32 có thể dùng exec sleep nếu image thực sự có shell/binary; distroless image thường không có.

### Khi dùng, lỗi thường gặp, trade-off và production note

- Luôn dùng startup probe khi startup có thể dài/dao động; nó giữ liveness khỏi giết app trong lúc khởi động.
- Không check dependency ngoài trong liveness. Readiness cũng chỉ include dependency nếu app thực sự không thể phục vụ khi dependency đó lỗi.
- Timeout probe phải ngắn và handler không block. Probe “thông minh” quá mức thường kém tin cậy.
- Grace period dài cứu request chậm nhưng kéo dài rollout và giữ tài nguyên; grace period ngắn rollout nhanh nhưng có thể cắt request.
- Retry từ client vẫn cần thiết: graceful shutdown giảm chứ không loại bỏ mọi lỗi trong hệ phân tán.

> **Ghi chú Boot 3.5/4.1:** Cả hai bật graceful shutdown mặc định. Những hướng dẫn cũ ghi `server.shutdown` mặc định là `immediate` không còn đúng với hai phiên bản này.

---

## 7. Virtual Thread (Spring Boot 3.2+)

**Virtual thread (luồng ảo)** là `Thread` nhẹ do JVM quản lý và multiplex lên một số platform/carrier thread. Khi virtual thread chờ I/O được JVM hỗ trợ, nó thường unmount để carrier chạy việc khác. Nó tăng khả năng phục vụ nhiều tác vụ chờ đồng thời, không làm CPU hoặc từng câu SQL chạy nhanh hơn.

> 💡 **Giải thích dễ hiểu:** Platform thread giống mỗi cuộc gọi phải giữ riêng một tổng đài viên kể cả lúc khách đang chờ. Virtual thread cho phép tổng đài viên tạm phục vụ cuộc khác trong thời gian cuộc đầu đang chờ dữ liệu.

### 7.1 What / How / Why: bật virtual thread

```yaml
# application.yml — yêu cầu Java 21+
spring:
  threads:
    virtual:
      enabled: true
  main:
    # Virtual thread là daemon; giữ JVM sống cả khi không còn non-daemon thread.
    keep-alive: true
```

Khi không có executor tùy chỉnh, Boot auto-configure `AsyncTaskExecutor` và scheduler dùng virtual thread; các integration như `@Async`, Spring MVC async và WebSocket có thể dùng executor đó. Pool-size property của executor/scheduler không còn tác dụng khi virtual thread bật. Web server được hỗ trợ cũng dùng threading mode tương ứng; hãy xác nhận bằng thread dump/benchmark thay vì suy ra rằng mọi thư viện trong app đã tự chuyển đổi.

### 7.2 Cách blocking I/O thay đổi

```java
// Code imperative vẫn giữ stack trace và mô hình thread-per-request dễ đọc.
@GetMapping("/users/{id}")
public UserResponse getUser(@PathVariable Long id) {
    User user = userRepository.findById(id).orElseThrow(); // JDBC blocking I/O
    return UserResponse.from(user);
}
```

Một virtual thread chờ connection pool vẫn giữ request và memory liên quan. HikariCP 20 connection chỉ cho tối đa khoảng 20 query DB chạy đồng thời dù có 20.000 virtual thread; phần còn lại chờ pool. Vì vậy phải giữ timeout, rate limit, bulkhead và admission control.

### 7.3 Components và giới hạn cần giữ

- **I/O-bound (bị giới hạn bởi thời gian chờ I/O):** HTTP/JDBC/file call đồng thời cao thường hưởng lợi.
- **CPU-bound (bị giới hạn bởi CPU):** virtual thread không tạo thêm core; dùng concurrency giới hạn quanh tác vụ CPU nặng.
- DB pool, HTTP client pool, broker quota, file descriptor, heap và downstream capacity vẫn là giới hạn thật.
- `ThreadLocal` vẫn hoạt động nhưng số virtual thread có thể rất lớn; tránh object nặng và bảo đảm clear context.
- Đừng tự định nghĩa cả `taskExecutor` lẫn Tomcat customizer nếu property của Boot đã đáp ứng. Bean tùy chỉnh có thể vô hiệu auto-configuration, context propagation hoặc lifecycle management.

### 7.4 Pinning theo phiên bản JDK

```java
// Java 21–23: I/O dài và thường xuyên khi giữ monitor có thể pin carrier.
public synchronized void badMethod() {
    jdbcTemplate.query(...);
}

// Chỉ thay lock sau khi JFR chứng minh đây là bottleneck trên JDK cũ.
private final ReentrantLock lock = new ReentrantLock();

public void goodMethod() {
    lock.lock();
    try {
        jdbcTemplate.query(...);  // virtual thread can park, carrier is freed
    } finally {
        lock.unlock();
    }
}
```

Trên Java 21–23, dùng JFR event `jdk.VirtualThreadPinned` hoặc tạm dùng `-Djdk.tracePinnedThreads=short` để chẩn đoán. Từ Java 24, JEP 491 loại gần hết pinning do `synchronized`; flag trên không còn cần thiết/có hiệu lực. Native/foreign-function callback và một số JVM operation vẫn có thể pin, nên tiếp tục quan sát bằng JFR. Không máy móc đổi mọi `synchronized` sang `ReentrantLock`.

> **Ghi chú Boot 3.5/4.1:** Cả hai yêu cầu tối thiểu Java 21 cho virtual thread và tài liệu hiện khuyến nghị Java 24+ để có trải nghiệm tốt hơn. Property chính vẫn là `spring.threads.virtual.enabled=true`.

### 7.5 Virtual thread so với Reactive: so sánh và trade-off

| | Virtual Threads | Reactive (WebFlux) |
|--|----------------|-------------------|
| Mô hình | Imperative, thread-per-task | Non-blocking pipeline |
| Blocking library | Tự nhiên | Phải cô lập khỏi event loop |
| Backpressure luồng dữ liệu | Không tự có | Là phần cốt lõi của Reactive Streams |
| Debug/test | Stack trace/JUnit quen thuộc | Cần hiểu operator, scheduler, `StepVerifier` |
| Phù hợp | Request/response I/O-bound, code JDBC hiện có | Streaming, composition async, end-to-end backpressure |
| Hiệu năng | Phải benchmark | Phải benchmark |

### Khi dùng và production note

Thử virtual thread khi thread pool platform đang là bottleneck và workload chủ yếu chờ I/O. Không bật chỉ để giảm latency; virtual thread nhắm tới throughput/concurrency. Chạy load test có cùng DB pool/downstream limit, theo dõi carrier pinning, queue/wait time, RSS, CPU và timeout. Một hệ thống không có admission control có thể nhận nhiều việc hơn khả năng downstream rồi sụp theo kiểu load collapse.

---

## 8. Tuning JVM và HikariCP

**JVM tuning (tinh chỉnh máy ảo Java)** và **HikariCP (connection pool JDBC)** phải bắt đầu từ phép đo. JVM quản lý heap, JIT, GC và native memory; HikariCP giới hạn số kết nối DB chạy đồng thời. Tăng một giới hạn có thể chỉ đẩy nghẽn sang nơi khác.

> 💡 **Giải thích dễ hiểu:** Heap là kho hàng, GC là đội dọn kho, còn connection pool là số quầy thu ngân nối tới database. Mở thêm vô hạn quầy không giúp nếu database chỉ xử lý được một lượng khách hữu hạn.

### 8.1 What / How / Why: JVM trong container

```bash
# Baseline minh họa; JVM tự đọc biến này cả với JSON ENTRYPOINT.
JAVA_TOOL_OPTIONS="
  -XX:MaxRAMPercentage=60.0
  -XX:+ExitOnOutOfMemoryError
  -XX:+HeapDumpOnOutOfMemoryError
  -XX:HeapDumpPath=/dumps/heapdump.hprof
  -Xlog:gc*,safepoint:stdout:time,level,tags
"
```

Trên JDK hiện đại, container awareness đã bật mặc định. `MaxRAMPercentage=60` cũng không phải đáp án chung: phần RAM còn lại phải đủ cho metaspace, code cache, direct buffer, native library, thread stack và sidecar. Heap dump có thể chứa secret/PII, rất lớn và làm đầy disk; mount volume có quyền đúng, mã hóa và kiểm soát retention.

Chỉ chọn G1/ZGC/Shenandoah sau benchmark. `MaxGCPauseMillis` là mục tiêu mềm, không phải cam kết pause tối đa. Tránh ép `G1HeapRegionSize`, GC thread count hoặc DNS/entropy flag cũ khi chưa có bằng chứng. `-XX:TieredStopAtLevel=1` giảm startup nhưng hy sinh peak performance, nên chỉ dùng cho profile ưu tiên startup đã được đo.

### 8.2 Components: tuning HikariCP

```yaml
spring:
  datasource:
    hikari:
      # Điểm bắt đầu, đưa ra biến môi trường để tune theo từng deployment.
      maximum-pool-size: ${DB_POOL_SIZE:10}

      # Fail đủ sớm để còn ngân sách trả response/retry có kiểm soát.
      connection-timeout: 2000      # millisecond = 2 giây
      validation-timeout: 1000      # millisecond = 1 giây

      # Phải ngắn hơn timeout của DB/proxy/network; giữ keepalive < max-lifetime.
      max-lifetime: 1500000         # 25 phút
      keepalive-time: 120000        # 2 phút

      pool-name: HikariCP-Primary
```

Không có công thức `(core × 2) + spindle` đúng cho mọi hệ thống và “10–20 connection” không phải định luật. Ràng buộc quan trọng là:

```text
replica_count × maximum_pool_size
  + migration/admin/background connections
  ≤ connection budget mà database/proxy chịu được
```

Sau đó tune theo concurrent DB work, query latency, transaction length và acquire timeout. Bỏ `minimum-idle` làm Hikari mặc định giữ fixed-size pool bằng `maximum-pool-size`, phù hợp khi cần phản ứng ổn định với spike nhưng giữ nhiều connection idle hơn. Nếu đặt `minimum-idle < maximum-pool-size`, `idle-timeout` mới có ý nghĩa rõ và pool co giãn nhưng spike có thể phải chờ tạo connection.

Driver JDBC4 hiện đại dùng `Connection.isValid()`; chỉ cấu hình `connection-test-query` nếu driver thực sự không hỗ trợ. Leak detection có overhead và false positive với transaction dài, nên bật tạm để chẩn đoán dev/staging hoặc incident thay vì checkbox production mặc định.

### 8.3 Metric HikariCP trong Prometheus

```promql
# Key metrics to monitor
hikaricp_connections_active           # Currently in use
hikaricp_connections_idle             # Available
hikaricp_connections_pending          # Waiting for connection
hikaricp_connections_acquire_seconds  # Time to acquire connection
hikaricp_connections_creation_seconds # Time to create new connection
hikaricp_connections_usage_seconds    # Time connection is held

# Alert minh họa: pending kéo dài trong lúc active chạm max
- alert: HikariPoolSaturated
  expr: |
    max by (instance, pool) (hikaricp_connections_pending) > 0
    and on (instance, pool)
    max by (instance, pool) (hikaricp_connections_active)
      >= max by (instance, pool) (hikaricp_connections_max)
  for: 2m
  annotations:
    summary: "HikariCP pool saturated — requests are waiting"
```

Một pending connection thoáng qua chưa chắc là sự cố. Kết hợp pending kéo dài, active/max, acquire latency, timeout/error rate và DB utilization. Tên/suffix metric có thể khác theo Micrometer registry version; xác minh trực tiếp trên endpoint Prometheus của artifact đang deploy.

### 8.4 CDS và AOT Cache trên JVM

```bash
# 0. Extract layout ổn định, thân thiện với CDS/AOT cache
java -Djarmode=tools -jar app.jar extract --destination app

# 1. Java 21–23: tạo CDS archive bằng training startup
java -Dspring.context.exit=onRefresh \
     -XX:ArchiveClassesAtExit=app.jsa \
     -jar app/app.jar

# 2. Chạy đúng artifact/classpath đã dùng để train
java -XX:SharedArchiveFile=app.jsa \
     -jar app/app.jar

# Java 25+: ưu tiên AOT cache của JVM
java -XX:AOTCacheOutput=app.aot \
     -Dspring.context.exit=onRefresh \
     -jar app/app.jar
java -XX:AOTCache=app.aot -jar app/app.jar
```

**CDS (Class Data Sharing – chia sẻ metadata/lớp đã xử lý)** và AOT cache của JVM có thể giảm startup/warm-up nhưng không phải Spring native image. Archive/cache phải được tạo lại khi JDK, dependency, classpath hoặc artifact đổi. Lệnh `spring-boot:process-aot` sinh Spring AOT assets; nó không tự tạo CDS archive như một số ví dụ cũ mô tả.

Đo startup/RSS trước và sau. Từ Java 25, tài liệu Spring Boot khuyên ưu tiên AOT cache thay cho CDS; với Boot 3.5 trên Java 21, CDS vẫn là lựa chọn hợp lý.

### 8.5 Khi dùng, so sánh và trade-off

| Quyết định | Tăng | Có thể làm xấu |
|---|---|---|
| Heap lớn hơn | Headroom, ít allocation pressure | RSS, thời gian một số GC cycle, pod density |
| Pool DB lớn hơn | Concurrent query nếu DB còn capacity | DB contention, memory, connection budget |
| Acquire timeout dài | Cơ hội chờ qua spike | Tail latency và request pile-up |
| Low-pause GC | Predictability pause | CPU/throughput tùy workload |
| CDS/AOT cache | Startup/warm-up | Build complexity, cache invalidation |

### 8.6 Production checklist / Ghi chú vận hành

#### Observability

- [ ] Chỉ expose Actuator endpoint cần thiết; endpoint nhạy cảm nằm sau mạng/quyền quản trị.
- [ ] Liveness chỉ phản ánh lỗi nội bộ; readiness include dependency có timeout và chủ đích.
- [ ] Business metric có tên/đơn vị rõ và tag cardinality hữu hạn.
- [ ] Structured log có correlation ID nhưng không log secret/PII.
- [ ] Trace export qua collector, sampling và retention theo chi phí/SLO.
- [ ] Dashboard theo RED (Rate, Errors, Duration) và saturation của dependency.
- [ ] Alert dựa trên SLO/error budget, đã test route và runbook.

#### Reliability

- [ ] Startup/liveness/readiness probe đã thử cả startup chậm và dependency outage.
- [ ] Graceful shutdown, `preStop` và termination grace có tổng ngân sách thời gian nhất quán.
- [ ] Mọi network call có timeout; retry chỉ cho lỗi transient/idempotent với backoff + jitter.
- [ ] Circuit breaker, bulkhead và rate limit đặt theo failure mode thực tế.
- [ ] Tổng connection pool của mọi replica không vượt budget DB.
- [ ] Side effect cần độ bền dùng queue/outbox; `@Async` một mình không bảo đảm giao việc.

#### Security

- [ ] Secret đến từ secret manager/Kubernetes Secret, không nằm trong image hoặc Git.
- [ ] TLS, authentication/authorization và security header được kiểm thử.
- [ ] Input validation và query parameter hóa; dependency/image được quét CVE.
- [ ] Health detail, heap dump, trace attribute và log có data classification/retention.

#### Performance

- [ ] Index dựa trên query plan và workload, không tạo “cho mọi `WHERE`”.
- [ ] N+1, pagination và payload size được kiểm tra trên data volume thật.
- [ ] Cache có mục tiêu hit rate, TTL, invalidation và consistency rõ ràng.
- [ ] Virtual thread/reactive, GC, heap và HikariCP được load test cùng downstream limit.
- [ ] Có regression budget cho p50/p95/p99, throughput, CPU và RSS.

#### Deployment

- [ ] Image theo layer hoặc buildpack, non-root, pin base image và có SBOM.
- [ ] Resource request/limit dựa trên đo đạc và còn headroom.
- [ ] HPA dùng metric phản ánh saturation; thử scale-up/down và cold start.
- [ ] Migration Flyway/Liquibase an toàn khi nhiều replica khởi động.
- [ ] Rollout/rollback đã thử; schema và message tương thích ít nhất một phiên bản trước.

Checklist là câu hỏi xác minh, không phải yêu cầu bật mọi tính năng. Ví dụ cache, native image, virtual thread, leak detection và HPA đều có trường hợp không cần.

---

## Summary: Spring Boot Production Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                         K8s Pod                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │          Spring Boot App (platform/virtual threads)      │   │
│  │                                                          │   │
│  │  HTTP/REST ──→ Controller ──→ Service ──→ Repository     │   │
│  │                  ↓              ↓            ↓           │   │
│  │             Validation      @Cacheable    HikariCP       │   │
│  │                  ↓              ↓            ↓           │   │
│  │          GlobalExHandler      Redis       PostgreSQL     │   │
│  │                                                          │   │
│  │  Micrometer ──→ /actuator/prometheus ──→ Prometheus     │   │
│  │  OTEL Traces ──→ OTLP Collector ──→ Jaeger/Tempo         │   │
│  │  Structured Logs ──→ Loki/ELK                            │   │
│  │  /livez ──→ K8s liveness | /readyz ──→ readiness        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Resource/pool/sampling/timeout đều lấy từ SLO + load test      │
└─────────────────────────────────────────────────────────────────┘
```

## Ghi chú phiên bản và nguồn kiểm chứng

| Chủ đề | Boot 3.5.x | Boot 4.1.x |
|---|---|---|
| OTLP trace property | `management.otlp.tracing.*` | `management.opentelemetry.tracing.export.otlp.*` |
| Context qua task | `ContextPropagatingTaskDecorator` | Có thêm `spring.task.execution.propagate-context` |
| Layer extraction | `jarmode=tools` | `jarmode=tools` |
| Graceful shutdown | Bật mặc định | Bật mặc định |
| Virtual thread | Java 21+, khuyên Java 24+ | Java 21+, khuyên Java 24+ |
| JVM startup cache | CDS phù hợp Java 21 | Java 25+ ưu tiên AOT cache |

Tài liệu chính thức nên đối chiếu khi nâng phiên bản:

- [Spring Boot 3.5 – Observability](https://docs.spring.io/spring-boot/3.5/reference/actuator/observability.html)
- [Spring Boot 4.1 – Observability](https://docs.spring.io/spring-boot/reference/actuator/observability.html)
- [Spring Boot – Kubernetes Probes](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes)
- [Spring Boot – Native Image Testing](https://docs.spring.io/spring-boot/how-to/native-image/testing-native-applications.html)
- [Spring Boot – Dockerfiles và layer](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html)
- [Spring Boot – Virtual Thread](https://docs.spring.io/spring-boot/reference/features/spring-application.html#features.spring-application.virtual-threads)
- [OpenJDK JEP 491 – Synchronize Virtual Threads without Pinning](https://openjdk.org/jeps/491)

> **Cập nhật lần cuối:** 2026-07-27.
