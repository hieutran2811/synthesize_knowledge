# Spring WebFlux – Lập trình Reactive

## What – WebFlux là gì?

**Spring WebFlux** là reactive web framework trong Spring 5+, chạy trên **non-blocking I/O** (Netty mặc định). Dựa trên **Project Reactor** (Mono/Flux).

```
Spring MVC (Servlet/Blocking):           Spring WebFlux (Reactive/Non-blocking):
Thread-per-request model                 Event-loop model

Request → Thread A (blocked waiting I/O) Request → Event Loop → callback on I/O complete
Request → Thread B (blocked waiting I/O)                     → Thread xử lý tiếp
Request → Thread C (waiting...)          → same threads handle many requests
N requests = N threads                   N requests = few threads
```

**Khi nào dùng WebFlux:**
- Streaming data (real-time feeds, SSE)
- High concurrent connections (chat, notifications)
- Call nhiều external services song song
- Microservices với nhiều I/O operations

**Khi nào tiếp tục dùng MVC:**
- JDBC/JPA blocking (R2DBC chưa mature với mọi DB)
- Team chưa quen Reactive programming
- Simple CRUD (không cần high throughput)

---

## Project Reactor – Mono và Flux

```java
// Mono: 0 hoặc 1 element
Mono<User> user = Mono.just(new User("Alice"));
Mono<User> empty = Mono.empty();
Mono<User> error = Mono.error(new ResourceNotFoundException("User", 1L));

// Flux: 0 hoặc N elements
Flux<User> users = Flux.just(user1, user2, user3);
Flux<Integer> range = Flux.range(1, 100);
Flux<String> fromList = Flux.fromIterable(List.of("a", "b", "c"));

// Từ CompletableFuture
Mono<User> fromFuture = Mono.fromFuture(() -> userService.findByIdAsync(id));

// Từ blocking call (wrap để không block event loop)
Mono<User> fromBlocking = Mono.fromCallable(() -> blockingRepo.findById(id))
    .subscribeOn(Schedulers.boundedElastic()); // run on separate thread pool
```

---

## WebFlux Controller

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    // Mono – single item
    @GetMapping("/{id}")
    public Mono<ResponseEntity<UserResponse>> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(user -> ResponseEntity.ok(userMapper.toResponse(user)))
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    // Flux – stream of items
    @GetMapping
    public Flux<UserResponse> listUsers(@RequestParam Long tenantId) {
        return userService.findByTenantId(tenantId)
            .map(userMapper::toResponse);
    }

    // Streaming (text/event-stream)
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<UserEvent> streamUserEvents() {
        return userEventService.getEventStream()
            .delayElements(Duration.ofMillis(100));
    }

    // POST với body
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserResponse> createUser(@Valid @RequestBody Mono<CreateUserRequest> bodyMono) {
        return bodyMono
            .flatMap(userService::create)
            .map(userMapper::toResponse);
    }

    // File upload (multipart)
    @PostMapping("/avatar")
    public Mono<String> uploadAvatar(@RequestPart("file") Mono<FilePart> filePart) {
        return filePart.flatMap(fp -> storageService.store(fp));
    }

    // Parallel calls (zip nhiều Mono)
    @GetMapping("/{id}/dashboard")
    public Mono<DashboardResponse> getDashboard(@PathVariable Long id) {
        Mono<User> userMono = userService.findById(id);
        Mono<List<Order>> ordersMono = orderService.findByUserId(id).collectList();
        Mono<Stats> statsMono = statsService.getUserStats(id);

        return Mono.zip(userMono, ordersMono, statsMono)
            .map(tuple -> new DashboardResponse(
                tuple.getT1(), tuple.getT2(), tuple.getT3()
            ));
    }
}
```

---

## Reactive Operators (Quan trọng nhất)

```java
// map – transform 1:1
Flux<String> names = userFlux.map(User::getName);

// flatMap – async transform (returns Mono/Flux), hợp nhất kết quả (concurrently)
Flux<Order> orders = userFlux.flatMap(u -> orderService.findByUserId(u.getId()));

// concatMap – như flatMap nhưng preserve order (sequential)
Flux<Order> ordersOrdered = userFlux.concatMap(u -> orderService.findByUserId(u.getId()));

// filter
Flux<User> activeUsers = userFlux.filter(u -> u.getStatus() == ACTIVE);

// take, skip
Flux<User> first10 = userFlux.take(10);
Flux<User> skip5 = userFlux.skip(5);

// collectList – Flux → Mono<List>
Mono<List<User>> userList = userFlux.collectList();

// reduce – aggregate
Mono<BigDecimal> total = orderFlux.reduce(BigDecimal.ZERO,
    (acc, order) -> acc.add(order.getTotal()));

// zip – combine multiple publishers
Mono.zip(mono1, mono2, mono3).map(tuple -> combine(tuple.getT1(), tuple.getT2(), tuple.getT3()));

// merge – merge multiple Flux (interleaved)
Flux<Event> allEvents = Flux.merge(eventSourceA, eventSourceB, eventSourceC);

// onErrorReturn / onErrorResume – error handling
Mono<User> withFallback = userMono
    .onErrorReturn(new User("default"))
    .onErrorResume(NotFoundException.class, e -> fallbackService.getUser());

// retry / retryWhen
Mono<User> withRetry = externalApiCall()
    .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
        .filter(e -> e instanceof TransientException));

// timeout
Mono<User> withTimeout = externalApiCall()
    .timeout(Duration.ofSeconds(5))
    .onErrorResume(TimeoutException.class, e -> Mono.just(cachedUser));

// doOnNext, doOnError, doOnComplete – side effects (logging, metrics)
Flux<User> withLogging = userFlux
    .doOnNext(u -> log.debug("Processing user: {}", u.getId()))
    .doOnError(e -> log.error("Error: {}", e.getMessage()))
    .doFinally(signal -> metrics.recordCompletion(signal));
```

---

## Backpressure

**Problem:** Producer nhanh hơn consumer → OOM hoặc mất data.

```java
// Flux với backpressure strategy
Flux.range(1, 1_000_000)
    .onBackpressureBuffer(1000)       // buffer 1000, drop khi đầy
    .onBackpressureDrop(dropped ->    // hoặc drop và callback
        log.warn("Dropped: {}", dropped))
    .onBackpressureLatest()           // chỉ giữ item mới nhất
    .subscribe(item -> slowProcess(item));

// WebFlux tự handle backpressure với HTTP (slow client → server slows down)
// SSE: client đọc chậm → server buffer/drop
```

---

## R2DBC – Reactive Database Access

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-r2dbc</artifactId>
</dependency>
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>r2dbc-postgresql</artifactId>
</dependency>
```

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb
    username: user
    password: pass
  data:
    r2dbc:
      repositories:
        enabled: true
```

```java
// R2DBC Repository (reactive, không dùng JPA)
public interface UserR2dbcRepository extends ReactiveCrudRepository<User, Long> {

    Flux<User> findByTenantId(Long tenantId);

    Mono<User> findByEmail(String email);

    @Query("SELECT * FROM users WHERE tenant_id = :tenantId AND status = :status LIMIT :limit")
    Flux<User> findActiveByTenant(Long tenantId, String status, int limit);
}

// Entity cho R2DBC (không dùng @Entity JPA)
@Table("users")
public class User {
    @Id
    private Long id;
    private String name;
    private String email;
    @Column("tenant_id")
    private Long tenantId;
}

// Service
@Service
@RequiredArgsConstructor
public class UserService {
    private final UserR2dbcRepository userRepo;

    public Flux<User> findByTenantId(Long tenantId) {
        return userRepo.findByTenantId(tenantId);
    }

    @Transactional  // Spring @Transactional hoạt động với R2DBC
    public Mono<User> createUser(CreateUserRequest req) {
        return userRepo.findByEmail(req.email())
            .flatMap(existing -> Mono.<User>error(new DuplicateResourceException("User", "email", req.email())))
            .switchIfEmpty(Mono.defer(() -> {
                User user = User.fromRequest(req);
                return userRepo.save(user);
            }));
    }
}
```

---

## Server-Sent Events (SSE)

```java
@RestController
public class NotificationController {

    private final NotificationService notificationService;

    // Client nhận real-time notifications
    @GetMapping(value = "/notifications/{userId}",
                produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<NotificationDTO>> streamNotifications(
            @PathVariable String userId) {

        return notificationService.getNotificationStream(userId)
            .map(notification -> ServerSentEvent.<NotificationDTO>builder()
                .id(notification.getId())
                .event(notification.getType())
                .data(notificationMapper.toDTO(notification))
                .retry(Duration.ofSeconds(3))
                .build())
            .doOnCancel(() -> log.info("Client {} disconnected", userId));
    }
}

// Service dùng Sinks để push events
@Service
public class NotificationService {

    // Sinks.Many là hot publisher (emit bất cứ lúc nào)
    private final Map<String, Sinks.Many<Notification>> userSinks = new ConcurrentHashMap<>();

    public Flux<Notification> getNotificationStream(String userId) {
        Sinks.Many<Notification> sink = userSinks.computeIfAbsent(userId,
            k -> Sinks.many().multicast().onBackpressureBuffer());

        return sink.asFlux()
            .doFinally(signal -> userSinks.remove(userId));
    }

    public void sendNotification(String userId, Notification notification) {
        Sinks.Many<Notification> sink = userSinks.get(userId);
        if (sink != null) {
            sink.tryEmitNext(notification);
        }
    }
}
```

---

## WebClient – Reactive HTTP Client

```java
@Bean
public WebClient webClient(WebClient.Builder builder) {
    return builder
        .baseUrl("https://api.example.com")
        .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
        .codecs(config -> config.defaultCodecs().maxInMemorySize(10 * 1024 * 1024)) // 10MB
        .filter(ExchangeFilterFunctions.basicAuthentication("user", "pass"))
        .build();
}

@Service
@RequiredArgsConstructor
public class ExternalApiService {

    private final WebClient webClient;

    public Mono<ProductResponse> getProduct(String productId) {
        return webClient.get()
            .uri("/products/{id}", productId)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError,
                response -> response.bodyToMono(String.class)
                    .flatMap(body -> Mono.error(new ApiException(body))))
            .onStatus(HttpStatusCode::is5xxServerError,
                response -> Mono.error(new ServiceUnavailableException()))
            .bodyToMono(ProductResponse.class)
            .retryWhen(Retry.backoff(3, Duration.ofMillis(100)))
            .timeout(Duration.ofSeconds(5));
    }

    // Parallel calls
    public Mono<EnrichedOrder> enrich(Order order) {
        Mono<User> user = webClient.get()
            .uri("/users/{id}", order.getUserId())
            .retrieve().bodyToMono(User.class);

        Mono<List<Product>> products = Flux.fromIterable(order.getProductIds())
            .flatMap(id -> webClient.get().uri("/products/{id}", id)
                .retrieve().bodyToMono(Product.class))
            .collectList();

        return Mono.zip(user, products)
            .map(t -> new EnrichedOrder(order, t.getT1(), t.getT2()));
    }
}
```

---

## Testing WebFlux

```java
@WebFluxTest(UserController.class)
class UserControllerTest {

    @Autowired
    private WebTestClient webTestClient;

    @MockBean
    private UserService userService;

    @Test
    void getUser_exists_returns200() {
        UserResponse response = new UserResponse(1L, "Alice", "alice@example.com");
        when(userService.findById(1L)).thenReturn(Mono.just(response));

        webTestClient.get()
            .uri("/api/users/1")
            .headers(h -> h.setBearerAuth(testToken))
            .exchange()
            .expectStatus().isOk()
            .expectBody(UserResponse.class)
            .value(u -> assertThat(u.getName()).isEqualTo("Alice"));
    }

    @Test
    void streamNotifications_emitsEvents() {
        Flux<Notification> events = Flux.just(
            new Notification("n1", "ORDER_CREATED"),
            new Notification("n2", "PAYMENT_RECEIVED")
        );
        when(userService.getNotificationStream("user-1")).thenReturn(events);

        webTestClient.get()
            .uri("/notifications/user-1")
            .accept(MediaType.TEXT_EVENT_STREAM)
            .exchange()
            .expectStatus().isOk()
            .expectBodyList(Notification.class)
            .hasSize(2);
    }
}
```

---

## Trade-offs

| | Spring MVC | Spring WebFlux |
|--|-----------|---------------|
| Threading | Thread per request | Event loop |
| Throughput | Good | Higher (same hardware) |
| Latency | Low | Low (non-blocking) |
| DB Support | JPA, JDBC (mature) | R2DBC (less mature) |
| Learning curve | Low | High (Reactor, async) |
| Debugging | Easy (thread dumps) | Harder |
| Ecosystem | Vast | Growing |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `advanced/messaging.md` – Spring Kafka reactive (Reactor Kafka)
- `production/performance_tuning.md` – Virtual Threads vs Reactive
- **Keywords:** Project Reactor, Hot vs Cold publisher, Schedulers (boundedElastic, parallel, single), StepVerifier (test Reactor), Reactor Context (như ThreadLocal), Reactor Netty, reactive security (SecurityWebFilterChain), R2DBC limitations (no lazy loading, no JPQL), reactor-extra, resilience4j-reactor
