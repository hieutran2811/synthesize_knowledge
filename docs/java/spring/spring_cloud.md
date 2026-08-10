---
title: "Spring Cloud & Microservices (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 4
---
# Spring Cloud & Microservices (Deep Dive)

> Thuật ngữ: [Glossary](../glossary.md).

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Spring Cloud là gì?

**Spring Cloud** là bộ công cụ xây dựng trên Spring Boot, giải quyết các **vấn đề phổ biến của hệ phân tán/microservices**: cấu hình tập trung, service discovery, routing, load balancing, fault tolerance, distributed tracing. Nó hiện thực hóa các pattern kiến trúc (xem [[patterns/patterns_enterprise.md]]) thành thư viện dùng được ngay.

> Spring Cloud **không** dạy cách chia microservices — nó cung cấp "hệ thần kinh" để các service đã chia giao tiếp tin cậy.

---

## Why – Microservices đẻ ra vấn đề gì?

| Vấn đề monolith không có | Spring Cloud giải |
|--------------------------|-------------------|
| Service ở đâu? (IP/port động khi scale) | **Service Discovery** (Eureka/Consul) |
| Config nằm rải rác mỗi service | **Config Server** (tập trung, git) |
| Vào hệ thống qua đâu? | **API Gateway** (Spring Cloud Gateway) |
| Gọi instance nào? | **LoadBalancer** (client-side) |
| Gọi service khác sao cho gọn? | **OpenFeign** (declarative) |
| 1 service chết kéo sập dây chuyền | **Resilience4j** (Circuit Breaker, Bulkhead) |
| Request đi qua N service, debug kiểu gì? | **Distributed Tracing** (Micrometer + OTel) |

---

## Components – Bức tranh tổng thể

```
                    ┌──────────────┐
   Client  ───────► │ API Gateway  │ (routing, auth, rate limit)
                    └──────┬───────┘
                           │ hỏi "order-service ở đâu?"
                    ┌──────▼───────┐
                    │ Service      │◄──── các service tự đăng ký (register/heartbeat)
                    │ Discovery    │
                    │ (Eureka)     │
                    └──────┬───────┘
          ┌────────────────┼────────────────┐
   ┌──────▼─────┐   ┌──────▼─────┐   ┌───────▼──────┐
   │order-svc   │──►│payment-svc │──►│ inventory-svc│  (gọi nhau qua Feign + LB + Resilience4j)
   └────────────┘   └────────────┘   └──────────────┘
          ▲ tất cả lấy config từ ────► ┌──────────────┐
          └────────────────────────────│ Config Server│ (git backend)
                                        └──────────────┘
```

---

## How – Config Server (cấu hình tập trung)

12-factor: tách config khỏi code. Config Server đọc config từ **git/vault**, các service kéo về lúc khởi động.

```java
@SpringBootApplication
@EnableConfigServer           // server
public class ConfigServerApp { }
```
```yaml
# config-server application.yml
spring.cloud.config.server.git.uri: https://github.com/org/config-repo
# repo chứa: order-service.yml, order-service-prod.yml, application.yml (chung)
```
```yaml
# client (order-service) — Spring Boot 2.4+ dùng spring.config.import
spring.config.import: "optional:configserver:http://config-server:8888"
```

### Refresh config runtime (không cần restart)
```java
@RefreshScope                 // bean được tạo lại khi /actuator/refresh được gọi
@Component
class FeatureToggle {
    @Value("${feature.new-checkout:false}") boolean enabled;
}
```
> Đổi config trong git → POST `/actuator/refresh` (hoặc **Spring Cloud Bus** broadcast qua Kafka/RabbitMQ cho toàn cluster). Mã hóa secret: `{cipher}...` hoặc Vault. Liên hệ [[spring/spring_boot.md]] (`@ConfigurationProperties`, profiles).

---

## How – Service Discovery (Eureka)

Service tự **đăng ký** với registry; client **hỏi** registry để biết địa chỉ instance đang sống.

```java
@SpringBootApplication
@EnableEurekaServer            // registry server
public class DiscoveryServerApp { }
```
```yaml
# client service
eureka.client.service-url.defaultZone: http://discovery:8761/eureka/
spring.application.name: order-service     # tên đăng ký
```
- **Heartbeat**: instance gửi nhịp định kỳ (mặc định 30s); registry xóa instance "chết" sau khi quá hạn (self-preservation mode tránh xóa nhầm khi mạng chập chờn).
- **Client-side discovery**: client lấy danh sách instance rồi tự chọn (kết hợp LoadBalancer). Khác **server-side discovery** (gateway/LB chọn hộ).

> Alternatives: **Consul** (kèm KV store + health check + DNS), **Kubernetes** (dùng Service/DNS sẵn → thường KHÔNG cần Eureka khi đã ở K8s; xem [[kubernetes/networking/networking_deep.md]] nếu có).

---

## How – Spring Cloud LoadBalancer (client-side LB)

Thay thế Netflix Ribbon (đã ngừng). Client tự cân bằng tải giữa các instance lấy từ discovery.

```java
@Bean
@LoadBalanced                 // RestClient/RestTemplate hiểu tên service thay vì host
RestClient.Builder restClientBuilder() { return RestClient.builder(); }

// Gọi bằng TÊN service, LB tự đổi thành host:port của 1 instance
User u = restClient.get().uri("http://order-service/orders/{id}", id).retrieve().body(User.class);
```
> Chiến lược mặc định: round-robin (có thể đổi sang random, weighted). Liên hệ client HTTP ở [[core/networking_http.md]].

---

## How – OpenFeign (declarative HTTP client)

Khai báo interface, Feign sinh implementation tự gọi HTTP, **tích hợp sẵn discovery + LoadBalancer + Resilience4j**.

```java
@EnableFeignClients
@SpringBootApplication
public class App {}

@FeignClient(name = "payment-service")          // name = tên trong discovery
public interface PaymentClient {
    @PostMapping("/payments")
    PaymentResult charge(@RequestBody ChargeRequest req);

    @GetMapping("/payments/{id}")
    Payment get(@PathVariable Long id);
}

// Dùng như bean bình thường
@Service @RequiredArgsConstructor
class OrderService {
    private final PaymentClient paymentClient;
    void pay(Order o) { paymentClient.charge(new ChargeRequest(o)); }
}
```
> Feign tự load-balance qua tên `payment-service`. So sánh Feign vs WebClient vs RestClient: [[core/networking_http.md]].

---

## How – Resilience4j (Fault Tolerance)

Thư viện nhẹ thay thế Netflix Hystrix (đã ngừng). Hiện thực các pattern chịu lỗi. Khái niệm pattern ở [[patterns/patterns_enterprise.md]]; đây là cách dùng thực tế.

### Circuit Breaker – 3 trạng thái
```
CLOSED  ──(tỉ lệ lỗi vượt ngưỡng)──►  OPEN  ──(sau waitDuration)──►  HALF_OPEN
  ▲                                                                      │
  └──────────────(thử thành công đủ số lần)─────────────────────────────┘
                  (thử thất bại → quay lại OPEN)
```
- **CLOSED**: cho request đi qua, đếm tỉ lệ lỗi.
- **OPEN**: chặn ngay (fail-fast), trả fallback, không gọi downstream đang chết → tránh sập dây chuyền (cascading failure) và cho downstream thời gian hồi phục.
- **HALF_OPEN**: cho một ít request thử để dò downstream đã sống lại chưa.

```java
@Service
class InventoryService {
    @CircuitBreaker(name = "inventory", fallbackMethod = "fallback")
    @Retry(name = "inventory")
    @Bulkhead(name = "inventory")
    @TimeLimiter(name = "inventory")        // cần trả CompletableFuture
    public Stock check(Long sku) { return inventoryClient.get(sku); }

    // fallback PHẢI cùng signature + tham số Throwable cuối
    private Stock fallback(Long sku, Throwable t) {
        return Stock.unknown();             // degrade gracefully
    }
}
```
```yaml
resilience4j.circuitbreaker.instances.inventory:
  sliding-window-size: 10
  failure-rate-threshold: 50        # >50% lỗi trong 10 request gần nhất → OPEN
  wait-duration-in-open-state: 10s
  permitted-number-of-calls-in-half-open-state: 3
resilience4j.retry.instances.inventory:
  max-attempts: 3
  wait-duration: 500ms
  enable-exponential-backoff: true
```

### Các module Resilience4j

| Module | Bảo vệ khỏi | Cơ chế |
|--------|-------------|--------|
| **CircuitBreaker** | downstream chết kéo sập | fail-fast khi lỗi nhiều |
| **Retry** | lỗi tạm thời (network blip) | thử lại + backoff |
| **RateLimiter** | quá tải / lạm dụng | giới hạn số call/giây |
| **Bulkhead** | 1 dependency chậm ăn hết thread | cô lập pool/semaphore riêng |
| **TimeLimiter** | call treo vô hạn | timeout cho CompletableFuture |

> ⚠️ **Thứ tự kết hợp** quan trọng: Retry **bọc ngoài** CircuitBreaker (mặc định) → retry trước khi mở mạch. Cẩn thận retry + circuit breaker khuếch đại tải nếu cấu hình sai. Luôn kèm **TimeLimiter** (xem timeout ở [[core/networking_http.md]]).

---

## How – Spring Cloud Gateway (API Gateway)

Cửa ngõ duy nhất vào hệ thống: routing, cross-cutting (auth, rate limit, CORS). Reactive (trên Reactor Netty), thay thế Zuul 1 (blocking).

```yaml
spring.cloud.gateway.routes:
  - id: order-route
    uri: lb://order-service           # lb:// = qua LoadBalancer + discovery
    predicates:
      - Path=/api/orders/**
    filters:
      - StripPrefix=1
      - name: CircuitBreaker
        args: { name: orderCB, fallbackUri: forward:/fallback/orders }
      - name: RequestRateLimiter
        args: { redis-rate-limiter.replenishRate: 10, redis-rate-limiter.burstCapacity: 20 }
```
- **Predicate**: điều kiện match route (Path, Method, Header, Host, time...).
- **Filter**: biến đổi request/response (thêm header, strip prefix, rate limit, circuit breaker, rewrite).
- Đặt **authentication/JWT validation** tại gateway → service nội bộ tin tưởng (kết hợp [[spring/spring_security.md]]).
> Gateway reactive → liên hệ [[core/reactive.md]]. Rate limiter dùng Redis → liên hệ [[redis/redis_patterns.md]] nếu có.

---

## How – Distributed Tracing

Một request đi qua nhiều service → cần **trace id** xuyên suốt để debug. **Micrometer Tracing** (thay Spring Cloud Sleuth) + **OpenTelemetry** export sang Zipkin/Jaeger/Tempo.
- Mỗi request có `traceId` (toàn hành trình) + `spanId` (mỗi chặng); tự truyền qua header `traceparent`.
- Tự động gắn vào log qua MDC (xem [[core/logging.md]]).
> Chi tiết metrics/tracing: [[core/observability.md]].

---

## How – Spring Cloud Stream (event-driven, tóm tắt)

Trừu tượng hóa messaging (Kafka/RabbitMQ) qua `Supplier`/`Function`/`Consumer` + binder, tách code khỏi broker cụ thể. Chi tiết messaging/Outbox/DLT: [[core/messaging.md]].

---

## Compare – Spring Cloud vs Service Mesh (Istio)

| | Spring Cloud (library) | Service Mesh (Istio/Linkerd) |
|--|------------------------|------------------------------|
| Nơi xử lý | **Trong app** (dependency Java) | **Sidecar proxy** (Envoy), ngoài app |
| Ngôn ngữ | Chỉ JVM | Mọi ngôn ngữ (polyglot) |
| Discovery/LB/retry/mTLS | Code/cấu hình trong service | Hạ tầng lo, app "không biết" |
| Khi dùng | Toàn JVM, kiểm soát trong code | Đa ngôn ngữ, đã chạy trên K8s |
| Nâng cấp logic resilience | Đổi code + redeploy | Đổi cấu hình mesh |

> **Xu hướng:** khi đã ở Kubernetes → nhiều việc của Spring Cloud (discovery qua K8s DNS, LB qua Service, retry/mTLS qua mesh) được hạ tầng đảm nhận → giữ Spring Cloud cho phần app-level (Resilience4j business fallback, Config). Liên hệ [[kubernetes/kubernetes_knowledge.md]] nếu có.

---

## When – Khi nào cần Spring Cloud?

| Tình huống | Khuyến nghị |
|-----------|-------------|
| Monolith / vài service | **Chưa cần** — đừng "microservice hóa" sớm (xem [[patterns/antipatterns.md]]) |
| Nhiều service JVM, chưa dùng K8s | Spring Cloud đầy đủ (Eureka + Config + Gateway + Resilience4j) |
| Đã chạy K8s | Dùng K8s discovery/LB; giữ Config + Resilience4j (business fallback) |
| Đa ngôn ngữ | Cân nhắc Service Mesh thay vì Spring Cloud |

---

## Trade-offs

- (+) Giải quyết bài toán phân tán nhanh, tích hợp chặt Spring Boot, pattern đã kiểm chứng.
- (−) **Phức tạp vận hành**: thêm Eureka/Config/Gateway = thêm thành phần phải HA, monitor.
- (−) Coupling vào JVM; trùng lặp với khả năng của K8s/Service Mesh nếu không cẩn thận.
- (−) Resilience4j cấu hình sai (retry storm, circuit breaker quá nhạy) → tệ hơn không có.
- (−) Phân tán làm debug khó hơn → **bắt buộc** có distributed tracing + centralized logging.

---

## Real-world Usage

```java
// Pattern điển hình: Feign + Resilience4j + fallback degrade
@FeignClient(name = "pricing-service")
public interface PricingClient {
    @GetMapping("/price/{sku}") BigDecimal price(@PathVariable String sku);
}

@Service @RequiredArgsConstructor
class CheckoutService {
    private final PricingClient pricing;

    @CircuitBreaker(name = "pricing", fallbackMethod = "cachedPrice")
    @TimeLimiter(name = "pricing")
    public CompletableFuture<BigDecimal> getPrice(String sku) {
        return CompletableFuture.supplyAsync(() -> pricing.price(sku));
    }
    private CompletableFuture<BigDecimal> cachedPrice(String sku, Throwable t) {
        return CompletableFuture.completedFuture(priceCache.getOrDefault(sku, DEFAULT)); // degrade
    }
}
```
- Stack phổ biến: Gateway (auth + rate limit) → service (Feign call nhau, bọc Resilience4j) → Config Server (git) → Eureka/K8s discovery → Micrometer Tracing → Prometheus/Grafana (xem [[core/observability.md]]).
- Saga/Outbox cho transaction phân tán: [[patterns/patterns_enterprise.md]], [[core/messaging.md]].

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[patterns/patterns_enterprise.md]] (Circuit Breaker/Bulkhead/Saga/Outbox khái niệm), [[core/networking_http.md]] (Feign/WebClient/RestClient), [[core/observability.md]] (tracing/metrics), [[core/messaging.md]] (Kafka/RabbitMQ, Cloud Stream), [[spring/spring_boot.md]] (config, profiles), [[spring/spring_security.md]] (auth tại gateway), [[core/reactive.md]] (Gateway reactive).
>
> Keyword cho topic kế: **Spring Cache & Scheduling/Async** – `@Cacheable`, CacheManager (Caffeine/Redis), `@Scheduled`, `@Async`, ShedLock.

*Cập nhật lần cuối: 2026-06-04*
