# Spring Boot Web Layer – REST, WebFlux, Security và Production

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Production – Ghi chú
>
> Tra cứu nhanh thuật ngữ tại [Spring Boot Glossary](glossary.md).

---

## What – Spring Boot Web Layer là gì?

**Web layer** *(tầng tiếp nhận và trả lời HTTP request)* là biên giới giữa client và business logic của ứng dụng. Với Spring Boot, tầng này thường dùng:

- **Spring MVC** *(web stack đồng bộ dựa trên Servlet)* cho ứng dụng imperative, JPA/JDBC và thư viện blocking;
- **Spring WebFlux** *(web stack reactive, hỗ trợ non-blocking I/O)* cho luồng I/O bất đồng bộ, streaming và concurrency cao;
- Spring Security cho authentication/authorization;
- `RestClient` hoặc `WebClient` để gọi HTTP service khác;
- Bean Validation, `ProblemDetail`, OpenAPI, CORS và rate limiting để hoàn thiện contract production.

**REST API** *(giao diện tài nguyên qua HTTP)* không chỉ là một controller trả JSON. Một API tốt phải có resource model, HTTP semantics, error contract, security, giới hạn tải, khả năng quan sát và chiến lược tiến hóa rõ ràng.

> 💡 **Giải thích dễ hiểu:**
> Web layer giống quầy lễ tân. Nó kiểm tra khách đưa đủ giấy tờ, chuyển yêu cầu tới đúng phòng, rồi trả kết quả theo một mẫu thống nhất. Lễ tân không nên tự làm toàn bộ nghiệp vụ của các phòng phía sau.

---

## Why – Vì sao phải thiết kế Web Layer có chủ đích?

- Contract ổn định giúp frontend, mobile và service khác phát triển độc lập.
- HTTP status, header và media type đúng giúp proxy/cache/client hoạt động chính xác.
- Validation sớm giảm dữ liệu sai đi sâu vào domain, nhưng không thay thế business rule.
- Error format chuẩn giúp client xử lý lỗi bằng máy thay vì đọc chuỗi message.
- Authentication/authorization ở framework giảm lỗi tự viết crypto hoặc filter.
- Timeout, retry và rate limit ngăn một dependency chậm gây hiệu ứng dây chuyền.
- OpenAPI và observability làm API kiểm thử, vận hành và điều tra được.

Web layer nên mỏng: chuyển HTTP input thành command/query, gọi application service, rồi ánh xạ kết quả trở lại HTTP. Transaction, invariant và orchestration nghiệp vụ không nên sống trong controller.

---

## Components – Request Lifecycle

```text
Client
  ↓
Reverse proxy / API gateway
  ↓
CORS + Spring Security FilterChain + correlation/observability filters
  ↓
DispatcherServlet (MVC) hoặc WebHandler (WebFlux)
  ↓
Routing → data binding → validation → controller/handler
  ↓
Application service → repository / downstream services
  ↓
HTTP response hoặc ProblemDetail
```

| Thành phần | Trách nhiệm chính |
|---|---|
| DTO | Contract request/response, tách khỏi persistence entity |
| Controller/handler | HTTP mapping và orchestration mỏng |
| Validation | Kiểm tra cấu trúc/ràng buộc input |
| Exception handler | Ánh xạ exception thành error contract |
| Security filter chain | Xác thực token, phân quyền endpoint |
| HTTP client | Gọi dependency với timeout/retry/telemetry |
| OpenAPI | Mô tả machine-readable của API |
| Gateway/filter | CORS, rate limit, routing, cross-cutting concerns |

> 💡 **Giải thích dễ hiểu:**
> Request đi qua nhiều cửa kiểm soát như hành khách ở sân bay: kiểm tra tuyến bay, giấy tờ, hành lý rồi mới lên máy bay. Mỗi cửa chỉ nên làm đúng một nhiệm vụ để lỗi dễ tìm và chính sách không bị trùng lặp.

---

## How – Thiết kế REST API

### Resource, method và status code

Ưu tiên noun cho resource và dùng HTTP method thể hiện hành động:

```text
POST   /api/orders          tạo order mới
GET    /api/orders/{id}     đọc một order
GET    /api/orders          tìm kiếm/phân trang
PUT    /api/orders/{id}     thay toàn bộ representation nếu contract định nghĩa vậy
PATCH  /api/orders/{id}     cập nhật một phần
DELETE /api/orders/{id}     xóa/hủy theo semantics đã công bố
```

Status code thường dùng:

| Status | Khi dùng |
|---|---|
| `200 OK` | Đọc/cập nhật thành công có body |
| `201 Created` | Tạo thành công; nên trả `Location` |
| `204 No Content` | Thành công không có body |
| `400 Bad Request` | JSON, parameter hoặc validation request không hợp lệ |
| `401 Unauthorized` | Chưa/không xác thực được |
| `403 Forbidden` | Đã xác thực nhưng không có quyền |
| `404 Not Found` | Resource không tồn tại hoặc được che giấu theo policy |
| `409 Conflict` | Xung đột trạng thái/unique/version hiện tại |
| `422 Unprocessable Content` | Request đúng cú pháp nhưng vi phạm rule có semantics phù hợp |
| `429 Too Many Requests` | Vượt rate limit |

**Idempotency** *(gọi lặp lại vẫn cho hiệu ứng cuối giống một lần)* đặc biệt quan trọng với retry. `GET`, `PUT`, `DELETE` được thiết kế có tính idempotent theo HTTP semantics; `POST` tạo dữ liệu nên dùng idempotency key nếu client có thể retry.

```java
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
class OrderController {

    private final OrderApplicationService service;

    @PostMapping
    ResponseEntity<OrderResponse> create(
            @Valid @RequestBody CreateOrderRequest request) {
        OrderResponse created = service.create(request);
        URI location = URI.create("/api/orders/" + created.id());
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/{id}")
    OrderResponse get(@PathVariable @Positive long id) {
        return service.get(id);
    }
}
```

### DTO, pagination và entity boundary

**DTO** *(đối tượng truyền dữ liệu qua boundary)* giúp API không vô tình lộ column, lazy relation hoặc thay đổi persistence model. Dùng DTO riêng cho create/update/response thường dễ hiểu hơn một DTO với quá nhiều validation group.

```java
public record CreateOrderRequest(
    @NotNull Long customerId,
    @NotEmpty List<@Valid OrderLineRequest> lines,
    @Size(max = 500) String note
) {}

public record OrderLineRequest(
    @NotNull Long productId,
    @Positive int quantity
) {}

public record OrderResponse(
    long id,
    String status,
    BigDecimal total,
    Instant createdAt
) {}
```

API list cần giới hạn `size`, quy định sort field được phép và dùng cursor pagination khi dữ liệu thay đổi nhanh hoặc offset lớn. Không trả thẳng `Page<Entity>` nếu không muốn contract phụ thuộc cấu trúc nội bộ của framework.

---

## How – Error Contract với `ProblemDetail`

**Problem Details** *(định dạng lỗi HTTP chuẩn theo RFC 9457)* có các field `type`, `title`, `status`, `detail`, `instance`. Spring Framework cung cấp `ProblemDetail`, `ErrorResponse` và `ResponseEntityExceptionHandler` cho cả MVC/WebFlux.

```yaml
spring:
  mvc:
    problemdetails:
      enabled: true
```

Property trên giúp Spring Boot tự cấu hình Problem Details cho nhiều exception built-in của MVC. Business exception vẫn cần ánh xạ có chủ đích:

```java
@RestControllerAdvice
class ApiExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    ProblemDetail handleNotFound(ResourceNotFoundException ex,
                                 HttpServletRequest request) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Resource not found");
        problem.setType(URI.create("https://api.example.com/problems/not-found"));
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("code", ex.code());
        problem.setProperty("traceId", MDC.get("traceId"));
        return problem;
    }

    @ExceptionHandler(DuplicateResourceException.class)
    ProblemDetail handleConflict(DuplicateResourceException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.CONFLICT, ex.getMessage());
        problem.setTitle("Resource conflict");
        problem.setType(URI.create("https://api.example.com/problems/conflict"));
        problem.setProperty("code", ex.code());
        return problem;
    }
}
```

```json
{
  "type": "https://api.example.com/problems/validation",
  "title": "Request validation failed",
  "status": 400,
  "detail": "One or more fields are invalid",
  "instance": "/api/orders",
  "code": "VALIDATION_FAILED",
  "traceId": "01J...",
  "errors": [
    { "field": "lines[0].quantity", "message": "must be greater than 0" }
  ]
}
```

`type` nên là URI ổn định đại diện cho loại lỗi, không tạo một URI mới cho từng request. Extension field như `code`, `traceId`, `errors` được Spring/Jackson đưa ra top level. Không trả stack trace, SQL, token, PII hoặc `rejectedValue` nhạy cảm.

`ProblemDetail.status` quyết định HTTP status; tránh bọc nó trong một response luôn trả `200`. Với success response, có thể trả DTO trực tiếp hoặc wrapper có metadata, nhưng phải nhất quán toàn API.

> 💡 **Giải thích dễ hiểu:**
> `ProblemDetail` giống mẫu biên bản sự cố chung: luôn có loại sự cố, tiêu đề, mã trạng thái và nơi xảy ra. Mỗi đội có thể thêm mã nội bộ, nhưng client không phải học một mẫu lỗi hoàn toàn mới cho từng service.

### Business exception hierarchy

```java
public abstract class ApplicationException extends RuntimeException {
    private final String code;

    protected ApplicationException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() { return code; }
}

public final class OrderAlreadyShippedException extends ApplicationException {
    public OrderAlreadyShippedException(long orderId) {
        super("ORDER_ALREADY_SHIPPED",
              "Order " + orderId + " has already been shipped");
    }
}
```

Không nhất thiết cho domain exception biết `HttpStatus`; một mapper ở web layer có thể chuyển domain error sang HTTP. Cách này giữ domain dùng được ở Kafka listener, batch job hoặc CLI mà không phụ thuộc web framework.

---

## How – Validation đúng ranh giới

**Bean Validation** *(cơ chế kiểm tra constraint khai báo bằng annotation)* phù hợp với shape/range/format của request:

```java
public record CreateUserRequest(
    @NotBlank @Email String email,
    @NotBlank @Size(min = 12, max = 100) String password,
    @NotBlank @Size(max = 100) String displayName,
    @Min(0) @Max(150) Integer age
) {}
```

Controller có thể phát sinh cả `MethodArgumentNotValidException` khi validate request body và `HandlerMethodValidationException` khi constraint đặt trực tiếp trên method parameter. Error handler production cần test cả hai dạng.

Phân chia trách nhiệm:

- DTO validation: null, size, format, nested shape;
- application/domain: trạng thái chuyển đổi, quyền nghiệp vụ, tổng tiền, inventory;
- database: unique constraint, foreign key và concurrency invariant cuối cùng.

Custom validator gọi repository để kiểm tra email tồn tại có thể tạo thêm I/O, khó batch và vẫn gặp **race condition** *(hai request cùng vượt kiểm tra trước khi commit)*. Có thể dùng nó để báo lỗi sớm, nhưng database unique constraint vẫn là hàng rào bắt buộc và phải map violation thành `409 Conflict`.

> 💡 **Giải thích dễ hiểu:**
> Validation ở cửa kiểm tra xem mẫu đơn có điền đủ và đúng định dạng. Business rule là phòng chuyên môn quyết định đơn có được duyệt không. Unique constraint là khóa két cuối cùng, ngăn hai người cùng lấy một số tài khoản dù họ đến cửa gần như đồng thời.

---

## How – Filter, Interceptor và `@ControllerAdvice`

| Cơ chế | Phạm vi | Dùng tốt cho | Không nên dùng cho |
|---|---|---|---|
| Servlet `Filter` | Trước/sau `DispatcherServlet` | Security chain, CORS, correlation ID, raw request/response | Business rule |
| MVC `HandlerInterceptor` | Quanh handler MVC | Request context, audit metadata, timing theo handler | JWT parsing thay Spring Security |
| `@ControllerAdvice` | Exception/data binding của MVC controller | Chuẩn hóa `ProblemDetail`, binder chung | Exception xảy ra trước MVC trong security filter |
| WebFlux `WebFilter` | Reactive web chain | Cross-cutting concern non-blocking | Servlet API/blocking I/O |

```text
HTTP → Filter/Security → DispatcherServlet → Interceptor.preHandle
     → Controller → Interceptor.afterCompletion → Filter → HTTP response
                              ↓ MVC exception
                    HandlerExceptionResolver/@ControllerAdvice
```

`AuthenticationException` và `AccessDeniedException` trong Spring Security filter chain được xử lý bằng `AuthenticationEntryPoint` và `AccessDeniedHandler`, không trông chờ `@ControllerAdvice`. Nếu cần error contract thống nhất, cấu hình hai handler này trả `application/problem+json`.

---

## How – API Versioning

Chỉ tạo version mới khi có breaking contract; thay đổi additive tương thích không nhất thiết cần version.

| Strategy | Ví dụ | Điểm mạnh | Chi phí |
|---|---|---|---|
| URI | `/api/v2/orders` | Dễ nhìn, route/cache/document rõ | URL thay đổi |
| Header | `API-Version: 2` | URI tài nguyên ổn định | Khó thử bằng browser/cache key phải đúng |
| Media type | `Accept: application/vnd.acme.v2+json` | Gắn version với representation | Phức tạp cho client/tooling |
| Query parameter | `/orders?version=2` | Dễ triển khai | Dễ lẫn với query nghiệp vụ |

Mỗi version cần deprecation policy, sunset date, usage metrics và migration guide. Không copy toàn bộ controller nếu chỉ khác mapping DTO; tách application service dùng chung.

---

## How – Spring MVC hay WebFlux?

**Spring MVC** dùng mô hình request-per-thread và chấp nhận blocking. **WebFlux** dùng **event loop** *(một nhóm nhỏ thread xử lý nhiều I/O event)*, Reactor và Reactive Streams **backpressure** *(consumer điều tiết tốc độ producer)*.

| Tiêu chí | Spring MVC | Spring WebFlux |
|---|---|---|
| Mô hình | Imperative, blocking được | Reactive, non-blocking end-to-end |
| Data access phù hợp | JPA/JDBC | R2DBC/reactive driver |
| HTTP client tự nhiên | `RestClient` | `WebClient` |
| Streaming | Có async support nhưng không phải trọng tâm | SSE/streaming/backpressure là thế mạnh |
| Debug/learning curve | Dễ hơn | Operator chain/context phức tạp hơn |
| Tải phù hợp | CRUD và phần lớn business API | Nhiều slow I/O/concurrent connection |

`Mono<T>` biểu diễn 0..1 phần tử; `Flux<T>` biểu diễn 0..N. Trả `Mono` không làm một hàm blocking trở thành non-blocking. Gọi JPA/JDBC hoặc `.block()` trên event-loop thread có thể làm nhiều request cùng đứng.

```java
@RestController
@RequestMapping("/reactive/users")
@RequiredArgsConstructor
class ReactiveUserController {

    private final ReactiveUserService service;

    @GetMapping("/{id}")
    Mono<ResponseEntity<UserResponse>> get(@PathVariable long id) {
        return service.findById(id)
            .map(UserResponse::from)
            .map(ResponseEntity::ok)
            .switchIfEmpty(Mono.just(ResponseEntity.notFound().build()));
    }

    @GetMapping(value = "/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    Flux<ServerSentEvent<UserEvent>> events() {
        return service.events()
            .map(event -> ServerSentEvent.builder(event)
                .event("user-updated")
                .id(event.id().toString())
                .build());
    }
}
```

**Server-Sent Events (SSE)** *(server đẩy chuỗi event một chiều qua HTTP)* phù hợp với notification/status stream; WebSocket phù hợp hơn khi cần giao tiếp hai chiều.

```java
Mono<UserProfile> profile(long userId) {
    Mono<User> user = users.findById(userId);
    Mono<List<Order>> orders = ordersByUser(userId).collectList();
    Mono<Address> address = addresses.findByUserId(userId);

    return Mono.zip(user, orders, address)
        .map(t -> new UserProfile(t.getT1(), t.getT2(), t.getT3()));
}
```

`zip` subscribe các nguồn async và chờ đủ kết quả; lợi ích concurrency chỉ xuất hiện nếu các nguồn thực sự non-blocking hoặc được schedule đúng. Luôn đặt timeout, giới hạn concurrency/buffer và quy định behavior khi một nguồn lỗi/rỗng.

> 💡 **Giải thích dễ hiểu:**
> MVC giống mỗi bàn có một nhân viên phục vụ đứng chờ bếp. WebFlux giống ít nhân viên nhận nhiều bàn rồi quay lại khi bếp rung chuông. Nếu nhân viên WebFlux vẫn đứng chắn trước bếp bằng một cuộc gọi JDBC blocking, lợi thế phục vụ nhiều bàn biến mất.

### Functional endpoint trong WebFlux

```java
@Bean
RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
    return RouterFunctions.route()
        .GET("/functional/users/{id}", handler::get)
        .POST("/functional/users", handler::create)
        .build();
}

Mono<ServerResponse> get(ServerRequest request) {
    long id = Long.parseLong(request.pathVariable("id"));
    return service.findById(id)
        .flatMap(user -> ServerResponse.ok().bodyValue(UserResponse.from(user)))
        .switchIfEmpty(ServerResponse.notFound().build());
}
```

Functional routing cho quyền kiểm soát pipeline rõ nhưng validation/error mapping phải được tổ chức nhất quán, không rải manual code ở từng handler.

---

## How – Gọi HTTP bằng `RestClient` và `WebClient`

### `RestClient` – synchronous

**RestClient** *(HTTP client đồng bộ với fluent API)* phù hợp Spring MVC/imperative service. Trong Spring Framework mới, đây là lựa chọn hiện đại thay cho phát triển mới với `RestTemplate`.

```java
@Bean
RestClient inventoryClient(RestClient.Builder builder,
                           @Value("${clients.inventory.base-url}") String baseUrl) {
    return builder
        .baseUrl(baseUrl)
        .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
        .defaultStatusHandler(HttpStatusCode::is5xxServerError, (request, response) -> {
            throw new InventoryUnavailableException(response.getStatusCode());
        })
        .build();
}

InventoryResponse getInventory(RestClient client, long productId) {
    return client.get()
        .uri("/inventory/{id}", productId)
        .retrieve()
        .onStatus(status -> status.value() == 404, (request, response) -> {
            throw new InventoryNotFoundException(productId);
        })
        .body(InventoryResponse.class);
}
```

### `WebClient` – reactive/non-blocking

**WebClient** *(HTTP client reactive, non-blocking)* phù hợp WebFlux, streaming hoặc fan-out nhiều remote call.

```java
Mono<OrderResponse> getOrder(WebClient client, long id) {
    return client.get()
        .uri("/orders/{id}", id)
        .retrieve()
        .onStatus(status -> status.value() == 404,
            response -> Mono.error(new OrderNotFoundException(id)))
        .onStatus(HttpStatusCode::is5xxServerError,
            response -> response.createException()
                .flatMap(ex -> Mono.error(new OrderServiceUnavailableException(ex))))
        .bodyToMono(OrderResponse.class)
        .timeout(Duration.ofSeconds(3))
        .retryWhen(Retry.backoff(2, Duration.ofMillis(200))
            .filter(OrderServiceUnavailableException.class::isInstance));
}
```

Production client cần cấu hình connect/read/response timeout ở HTTP connector, connection pool, TLS, max response size và observability. Reactor `.timeout()` bảo vệ pipeline tổng thể nhưng không thay mọi network timeout của client implementation.

Chỉ retry lỗi transient và operation an toàn/idempotent. Không retry mọi `4xx`, validation error hoặc `POST` tạo tài nguyên nếu không có idempotency key. Thêm exponential backoff + jitter và **circuit breaker** *(ngắt gọi tạm thời khi dependency lỗi liên tục)* để tránh retry storm.

> 💡 **Giải thích dễ hiểu:**
> Timeout là giới hạn thời gian chờ tổng đài; retry là gọi lại; circuit breaker là tạm ngừng gọi khi tổng đài đang hỏng. Nếu hàng nghìn khách đều gọi lại ngay lập tức, hệ thống hỏng càng khó hồi phục, nên cần backoff và giới hạn số lần.

Spring cũng hỗ trợ **HTTP Service Clients** *(Java interface có annotation được tạo proxy)* trên nền `RestClient` hoặc `WebClient`, hữu ích khi nhiều endpoint cùng một service cần contract typed.

---

## How – JWT và OAuth 2.0 Resource Server

**OAuth 2.0 Resource Server** *(API nhận và kiểm tra access token)* nên dùng support có sẵn của Spring Security thay vì tự viết `OncePerRequestFilter` parse JWT.

**JWT** *(JSON Web Token có chữ ký)* là một loại bearer token self-contained. Resource Server dùng `JwtDecoder` để xác minh chữ ký và validate claim như `exp`, `nbf`, `iss`; production thường phải validate thêm `aud`.

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://idp.example.com/issuer
          audiences: https://orders-api.example.com
```

Với `issuer-uri`, Spring Security có thể discovery **JWK Set** *(tập public key dùng kiểm chữ ký)* và tự xử lý key rotation. Nếu authorization server không có metadata endpoint hoặc cần chỉ định trực tiếp, cấu hình thêm `jwk-set-uri` nhưng vẫn giữ issuer validation theo hướng dẫn phiên bản.

```java
@Configuration
@EnableMethodSecurity
class SecurityConfig {

    @Bean
    SecurityFilterChain apiSecurity(HttpSecurity http) throws Exception {
        return http
            .csrf(csrf -> csrf.disable()) // Chỉ hợp lý cho stateless bearer-token API
            .cors(Customizer.withDefaults())
            .sessionManagement(sm ->
                sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health/readiness").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/catalog/**").permitAll()
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(authoritiesConverter())))
            .build();
    }

    JwtAuthenticationConverter authoritiesConverter() {
        JwtGrantedAuthoritiesConverter grants = new JwtGrantedAuthoritiesConverter();
        grants.setAuthoritiesClaimName("roles");
        grants.setAuthorityPrefix("ROLE_");

        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(grants);
        return converter;
    }
}
```

```java
@PreAuthorize("hasAuthority('order:write')")
public OrderResponse createOrder(CreateOrderCommand command) { ... }

@PreAuthorize("hasRole('ADMIN') or #userId == authentication.name")
public List<OrderResponse> ordersOf(String userId) { ... }
```

Authentication trả lời “ai đang gọi”; authorization trả lời “người đó được làm gì”. Không tin roles chỉ vì claim tồn tại: phải tin đúng issuer/audience/signature và map claim theo contract của Identity Provider.

JWT khó revoke tức thời vì resource server có thể validate offline. Dùng access token ngắn hạn, rotate key/refresh token phù hợp, hoặc opaque token introspection khi cần trạng thái thu hồi tập trung. Không log bearer token.

**CSRF** *(giả mạo request dùng credential tự động của browser)* không tự biến mất vì API trả JSON. Disable CSRF thường hợp lý cho API stateless chỉ nhận bearer token qua `Authorization` header; nếu dùng session cookie/cookie credential, cần giữ CSRF protection.

> 💡 **Giải thích dễ hiểu:**
> JWT giống thẻ ra vào có chữ ký của ban quản lý. Bảo vệ cửa không tự in thẻ rồi đoán chữ ký; họ kiểm nơi phát hành, hạn dùng, tòa nhà được phép vào và quyền ghi trên thẻ. Thẻ hợp lệ cũng không có nghĩa được mở mọi phòng.

---

## How – OpenAPI và API Documentation

**OpenAPI** *(đặc tả machine-readable của HTTP API)* có thể được sinh từ annotation bằng `springdoc-openapi`. Đây là thư viện ngoài Spring Framework; chọn major/version tương thích với dòng Spring Boot đang dùng thay vì copy một version cũ.

```xml
<dependency>
    <groupId>org.springdoc</groupId>
    <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
    <version>${springdoc.version}</version>
</dependency>
```

WebFlux dùng starter `springdoc-openapi-starter-webflux-ui` tương ứng.

```java
@Operation(summary = "Get order by id")
@ApiResponses({
    @ApiResponse(responseCode = "200", description = "Order found"),
    @ApiResponse(responseCode = "404", description = "Order not found",
        content = @Content(schema = @Schema(implementation = ProblemDetail.class))),
    @ApiResponse(responseCode = "401", description = "Authentication required"),
    @ApiResponse(responseCode = "403", description = "Insufficient permission"))
})
@GetMapping("/{id}")
OrderResponse get(@PathVariable long id) { ... }
```

```yaml
springdoc:
  api-docs:
    path: /api-docs
  swagger-ui:
    path: /swagger-ui.html
  show-actuator: false
```

OpenAPI phải mô tả cả security scheme, pagination, headers, `ProblemDetail` và example. Trong CI, export spec, lint và kiểm breaking change. Swagger UI là interactive client có thể gọi production API, nên hạn chế quyền truy cập hoặc tắt ở môi trường không cần thiết.

---

## How – CORS đúng với Spring Security

**CORS** *(chính sách browser cho request khác origin)* cho phép server công bố origin/method/header nào được browser gọi. **Preflight** *(request `OPTIONS` hỏi quyền trước request thật)* thường không mang cookie; vì vậy CORS phải được xử lý trước Spring Security.

```java
@Bean
UrlBasedCorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOrigins(List.of("https://app.example.com"));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE"));
    config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Idempotency-Key"));
    config.setExposedHeaders(List.of("Location", "Retry-After"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}

// SecurityFilterChain:
// .cors(Customizer.withDefaults())
```

Khi `allowCredentials=true`, không dùng wildcard `*` cho `allowedOrigins`; dùng origin cụ thể hoặc `allowedOriginPatterns` có kiểm soát. Hạn chế methods/headers theo nhu cầu production.

CORS không phải authentication, authorization hay firewall. Nó chủ yếu được browser thực thi; `curl` hoặc service-to-service client không bị CORS ngăn. CORS cũng không thay CSRF protection.

> 💡 **Giải thích dễ hiểu:**
> CORS giống danh sách website được phép gọi từ trình duyệt, không phải khóa cửa server. Người dùng công cụ ngoài trình duyệt vẫn có thể gửi request, nên cửa thật vẫn phải có authentication và authorization.

---

## How – Rate Limiting

**Rate limiting** *(giới hạn số request theo thời gian)* bảo vệ capacity và chống abuse. **Token bucket** *(xô token được nạp dần)* cho phép một lượng burst ngắn nhưng giữ tốc độ trung bình.

Nên áp nhiều lớp:

1. gateway/edge limit theo API key, tenant hoặc authenticated principal;
2. service limit cho operation đắt tiền như OTP, export hoặc search;
3. downstream concurrency limit để bảo vệ database/dependency.

Spring Cloud Gateway có `RequestRateLimiter`; WebFlux gateway thường dùng Redis token bucket. Spring Cloud Gateway Server MVC có Bucket4j rate limiter. Khi vượt giới hạn, mặc định phù hợp là `429 Too Many Requests`, kèm `Retry-After` và error body thống nhất.

```java
// Ý tưởng ở application filter; bucketStore phải là distributed store trong multi-instance.
ConsumptionProbe probe = bucketStore.forKey(rateLimitKey(request))
    .tryConsumeAndReturnRemaining(1);

if (!probe.isConsumed()) {
    long nanos = probe.getNanosToWaitForRefill();
    long retryAfterSeconds = Math.max(1, (nanos + 999_999_999L) / 1_000_000_000L);
    response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
    response.setHeader(HttpHeaders.RETRY_AFTER, String.valueOf(retryAfterSeconds));
    writeProblemDetail(response, "RATE_LIMIT_EXCEEDED");
    return;
}
chain.doFilter(request, response);
```

`ConcurrentHashMap<String, Bucket>` chỉ phù hợp demo/single instance: limit không chia sẻ giữa replicas, mất khi restart và map có thể tăng vô hạn. Với cluster, dùng Redis/Hazelcast/JCache hoặc gateway-managed distributed state.

Không tin trực tiếp `X-Forwarded-For`; chỉ dùng forwarded header do reverse proxy tin cậy đã ghi đè/chuẩn hóa. Principal/API key thường là key công bằng hơn IP vì nhiều người có thể chung NAT và attacker có thể xoay IP.

> 💡 **Giải thích dễ hiểu:**
> Token bucket giống bãi xe phát một số vé mỗi phút. Có thể dùng vé tích lại cho giờ cao điểm ngắn, nhưng khi hết vé phải chờ. Nếu mỗi cổng giữ sổ vé riêng trong RAM, người lái chỉ cần đổi cổng để vượt giới hạn; vì vậy nhiều instance phải dùng chung sổ.

---

## How – HTTP Compression, HTTP/2 và Transport

```yaml
server:
  compression:
    enabled: true
    mime-types: application/json,application/problem+json,text/html,text/plain
    min-response-size: 2KB
  http2:
    enabled: true
```

**HTTP compression** *(nén response để giảm băng thông)* đổi CPU lấy network; benchmark với payload thật và tránh nén các response chứa secret bị phản chiếu trong bối cảnh có rủi ro side-channel. **HTTP/2** *(nhiều stream trên một connection)* cần server/runtime hoặc reverse proxy hỗ trợ; TLS có thể terminate ở load balancer thay vì trong ứng dụng.

Ngoài ra cần giới hạn request/header/upload size, connection/idle timeout, graceful shutdown và forwarded-header trust. Không bật một config rồi giả định CDN, ingress và embedded server đều có cùng behavior.

---

## When – Chọn công cụ nào?

| Tình huống | Lựa chọn khuyến nghị |
|---|---|
| CRUD + JPA/JDBC, team imperative | Spring MVC + `RestClient` |
| Nhiều remote I/O non-blocking, SSE/streaming | WebFlux + `WebClient` |
| MVC nhưng cần fan-out HTTP async | Có thể dùng `WebClient`; đo lợi ích trước khi đổi cả stack |
| API nhận JWT từ IdP | OAuth2 Resource Server + `issuer-uri`/audience |
| Cần revoke token gần tức thời | Cân nhắc opaque token introspection hoặc token lifetime ngắn |
| Rate limit toàn hệ thống nhiều instance | Gateway + distributed store |
| Giới hạn operation nghiệp vụ riêng | Service-level limiter theo principal/tenant |
| Public/partner API | OpenAPI, version/deprecation policy, quota và contract test bắt buộc |

Nếu Spring MVC đang đáp ứng SLO, không chuyển sang WebFlux chỉ vì “reactive nhanh hơn”. Lợi ích WebFlux chủ yếu là scale concurrency với ít thread hơn khi pipeline non-blocking và có nhiều I/O latency.

---

## Compare – Các lựa chọn dễ nhầm

### Success wrapper và `ProblemDetail`

| Cách | Ưu điểm | Nhược điểm |
|---|---|---|
| Trả DTO trực tiếp, lỗi dùng `ProblemDetail` | Theo HTTP tự nhiên, ít nesting | Metadata success phải qua header hoặc DTO riêng |
| Wrapper cho success, lỗi dùng `ProblemDetail` | Success metadata thống nhất | Client có hai shape |
| Wrapper cho mọi response | Một shape bề ngoài | Dễ trả `200` cho lỗi, bỏ phí media type/status chuẩn |

### JWT và opaque token

| | JWT | Opaque token |
|---|---|---|
| Validation | Local bằng chữ ký/JWK | Gọi introspection server hoặc cache |
| Latency/dependency | Thấp, ít phụ thuộc IdP runtime | Phụ thuộc introspection availability |
| Revocation | Khó tức thời | Quản lý tập trung dễ hơn |
| Dữ liệu token | Claim nhìn thấy được, không phải mã hóa mặc định | Client không biết nội dung |

### `RestClient` và `WebClient`

| | `RestClient` | `WebClient` |
|---|---|---|
| API | Synchronous/fluent | Reactive/non-blocking |
| Stack hợp | MVC/imperative | WebFlux/reactive/streaming |
| Dùng sai phổ biến | Thiếu network timeout | Gọi `.block()` trên event loop |

---

## Trade-offs

- Chuẩn hóa `ProblemDetail` giảm client-specific error handling nhưng cần governance cho type URI/error code.
- Validation annotation tiện, nhưng validation group/custom validator I/O quá nhiều làm contract khó hiểu và chậm.
- WebFlux tiết kiệm thread dưới I/O concurrency cao, đổi lại debugging, context propagation và reactive composition khó hơn.
- JWT giảm dependency runtime vào IdP nhưng revocation và claim lifecycle phức tạp.
- OpenAPI code-first giảm viết tay nhưng annotation có thể lệch behavior nếu CI không kiểm spec.
- CORS/rate limit ở app linh hoạt nhưng có thể trùng gateway; cần một source of truth cho policy.
- Retry tăng khả năng chịu lỗi transient nhưng có thể nhân tải và tạo duplicate nếu operation không idempotent.

---

## Production – Checklist triển khai

### API contract

- Dùng DTO, status/header đúng và giới hạn pagination.
- Error theo RFC 9457; không lộ stack trace/PII/secret.
- Có version/deprecation policy và contract test.
- OpenAPI được lint, diff breaking change và publish đúng version.

### Security

- Dùng Spring Security Resource Server; validate signature, issuer, audience, expiry/not-before.
- Phân biệt `401` và `403`; method security cho rule cần defense-in-depth.
- Chỉ disable CSRF cho đúng kiến trúc stateless bearer API.
- CORS allowlist nhỏ; Swagger/Actuator không public ngoài ý muốn.
- Không log token/password; secret/key lấy từ secret manager và có rotation.

### Resilience và outbound HTTP

- Connect/read/response timeout, bounded connection pool và response-size limit.
- Retry có backoff/jitter chỉ cho transient + idempotent request.
- Circuit breaker, bulkhead/concurrency limit và fallback có semantics rõ.
- Propagate trace context; không propagate toàn bộ inbound header mù quáng.

### Rate limit và proxy

- Distributed limit cho nhiều instance; key theo tenant/principal/API key.
- `429` + `Retry-After`; metrics cho allowed/denied/latency.
- Chỉ tin forwarded headers từ proxy đã cấu hình trust boundary.

### Observability và test

- Access log có method, route template, status, latency, trace ID; tránh raw sensitive URL/body.
- Metrics theo route/status, active request, pool saturation, downstream latency/error.
- Test `@WebMvcTest`/`WebTestClient`, security, validation, ProblemDetail, CORS preflight và rate limit.
- Load test cả dependency chậm, retry storm, large payload và graceful shutdown.

> 💡 **Giải thích dễ hiểu:**
> Production checklist giống kiểm tra máy bay trước khi cất cánh. Unit test chứng minh từng bộ phận chạy; checklist còn xác nhận nhiên liệu, tải trọng, liên lạc, thời tiết và phương án khi một động cơ gặp sự cố.

---

## Nguồn chính thức

- [Spring Framework – RFC 9457 Error Responses](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-ann-rest-exceptions.html)
- [Spring Framework – MVC Validation](https://docs.spring.io/spring-framework/reference/web/webmvc/mvc-controller/ann-validation.html)
- [Spring Framework – WebFlux overview và lựa chọn MVC/WebFlux](https://docs.spring.io/spring-framework/reference/web/webflux/new-framework.html)
- [Spring Framework – REST Clients](https://docs.spring.io/spring-framework/reference/integration/rest-clients.html)
- [Spring Security – OAuth2 Resource Server JWT](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
- [Spring Security – CORS](https://docs.spring.io/spring-security/reference/servlet/integrations/cors.html)
- [Spring Security – CSRF](https://docs.spring.io/spring-security/reference/servlet/exploits/csrf.html)
- [Spring Cloud Gateway – RequestRateLimiter](https://docs.spring.io/spring-cloud-gateway/reference/spring-cloud-gateway-server-webflux/gatewayfilter-factories/requestratelimiter-factory.html)
- [springdoc-openapi – Getting Started](https://springdoc.org/getting-started.html)
- [RFC Editor – RFC 9457 Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457)

---

## Ghi chú – Chủ đề tiếp theo

- Persistence, transaction và N+1: [Spring Boot Data](springboot_data.md).
- Spring Kafka, reliable events: [Spring Boot Messaging](springboot_messaging.md).
- Controller/slice/integration test: [Spring Boot Testing](springboot_testing.md).
- Actuator, metrics, logging và deployment: [Spring Boot Production](springboot_production.md).
- Dependency injection, configuration và lifecycle: [Spring Boot Core](springboot_core.md).

> Keywords: REST semantics, idempotency key, DTO mapping, RFC 9457, `ProblemDetail`, `ErrorResponse`, `ResponseEntityExceptionHandler`, `HandlerMethodValidationException`, Spring MVC, WebFlux, Reactor, backpressure, SSE, functional endpoint, `RestClient`, `WebClient`, HTTP Service Client, OAuth2 Resource Server, JWT, JWK rotation, audience validation, CSRF, CORS preflight, OpenAPI, Bucket4j, token bucket, `429 Too Many Requests`, retry/backoff/jitter, circuit breaker, HTTP/2.

---

*Cập nhật lần cuối: 2026-07-27*
