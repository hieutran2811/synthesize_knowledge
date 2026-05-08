# Reactive Programming – Project Reactor & Spring WebFlux

## Mục lục
1. [What & Why – Reactive Programming](#1-what--why--reactive-programming)
2. [Project Reactor – Mono & Flux](#2-project-reactor--mono--flux)
3. [Operators – Transform & Combine](#3-operators--transform--combine)
4. [Error Handling](#4-error-handling)
5. [Schedulers & Threading](#5-schedulers--threading)
6. [Backpressure](#6-backpressure)
7. [Spring WebFlux](#7-spring-webflux)
8. [R2DBC – Reactive Database](#8-r2dbc--reactive-database)
9. [Testing Reactive Code](#9-testing-reactive-code)

---

## 1. What & Why – Reactive Programming

### 1.1 Problems with Blocking I/O

```
Traditional thread-per-request model:
  Thread 1: Request → DB query (wait 50ms) → HTTP call (wait 100ms) → Response
  Thread 2: Request → DB query (wait 50ms) → ...
  ...
  Thread N: BLOCKED (all threads waiting on I/O)

Problem: 1000 concurrent requests → 1000 threads
  Each Java thread: ~1MB stack → 1GB RAM just for thread stacks!
  Thread context switching overhead
  Limited by OS thread limits (~10,000 threads typically)

With Virtual Threads (Java 21): somewhat solves this...
With Reactive (Reactor/RxJava): solves differently — non-blocking I/O

Reactive model:
  Thread 1: Request → submit DB query (non-blocking) → return thread to pool
  Thread 1: (later) DB result arrives → continue processing → submit HTTP call → return
  Thread 1: (later) HTTP result arrives → send response
  → 1 thread handles thousands of requests (event loop pattern)
```

### 1.2 Reactive Streams Specification

```
Reactive Streams (JSR-166): standard API for async streaming
  Publisher<T>: produces items
  Subscriber<T>: consumes items
  Subscription: backpressure contract between Publisher and Subscriber
  Processor<T,R>: both Publisher and Subscriber

Implementations:
  Project Reactor (Spring):  Mono<T>, Flux<T>
  RxJava 3:                  Single<T>, Observable<T>, Flowable<T>
  Mutiny (Quarkus):          Uni<T>, Multi<T>
  JDK 9 Flow API:            Publisher/Subscriber/Processor interfaces

Key properties (Reactive Manifesto):
  Responsive:  respond quickly
  Resilient:   recover from failure
  Elastic:     scale under load
  Message-driven: async, non-blocking
```

---

## 2. Project Reactor – Mono & Flux

### 2.1 Mono<T> – 0 or 1 element

```java
import reactor.core.publisher.Mono;

// ── Creating Mono ─────────────────────────────────────────────────────────
Mono<String> just    = Mono.just("hello");                 // emit one value
Mono<String> empty   = Mono.empty();                       // emit nothing (complete)
Mono<String> error   = Mono.error(new RuntimeException()); // emit error
Mono<String> never   = Mono.never();                       // never completes
Mono<String> defer   = Mono.defer(() -> Mono.just(expensiveCall())); // lazy
Mono<String> fromCallable = Mono.fromCallable(() -> blockingMethod()); // wrap blocking

// ── Subscribing ───────────────────────────────────────────────────────────
// NOTHING happens until subscribe() is called (cold publisher)
mono.subscribe();                                          // fire and forget
mono.subscribe(value -> log.info("Value: {}", value));     // onNext
mono.subscribe(
    value   -> log.info("Got: {}", value),  // onNext
    error   -> log.error("Error", error),   // onError
    ()      -> log.info("Done")             // onComplete
);

// block(): convert to synchronous (AVOID in WebFlux, ok in tests)
String result = mono.block();
String result = mono.blockOptional().orElse("default");
```

### 2.2 Flux<T> – 0 to N elements

```java
import reactor.core.publisher.Flux;

// ── Creating Flux ─────────────────────────────────────────────────────────
Flux<Integer> fromList   = Flux.fromIterable(List.of(1, 2, 3, 4, 5));
Flux<Integer> fromArray  = Flux.fromArray(new Integer[]{1, 2, 3});
Flux<Integer> fromStream = Flux.fromStream(() -> IntStream.range(1, 100).boxed());
Flux<Integer> range      = Flux.range(1, 10);          // 1 to 10
Flux<Long>    interval   = Flux.interval(Duration.ofSeconds(1)); // tick every 1s
Flux<String>  just       = Flux.just("a", "b", "c");
Flux<Integer> defer      = Flux.defer(() -> Flux.fromIterable(dao.findAll()));

// Generating programmatically:
Flux<Integer> generate = Flux.generate(
    () -> 0,                                  // initial state
    (state, sink) -> {
        sink.next(state);                     // emit value
        if (state == 10) sink.complete();     // signal completion
        return state + 1;                     // next state
    }
);

Flux<String> create = Flux.create(sink -> {
    // Integrate with callback-based APIs
    kafkaConsumer.subscribe(record -> sink.next(record.value()));
    kafkaConsumer.onComplete(() -> sink.complete());
    kafkaConsumer.onError(e -> sink.error(e));
    sink.onDispose(() -> kafkaConsumer.unsubscribe()); // cleanup
});
```

### 2.3 Hot vs Cold Publishers

```java
// COLD: each subscriber gets independent stream from beginning
Flux<Integer> cold = Flux.range(1, 5);
cold.subscribe(i -> System.out.print(i + " "));  // 1 2 3 4 5
cold.subscribe(i -> System.out.print(i + " "));  // 1 2 3 4 5 (new stream!)

// HOT: shared stream, subscribers join in-flight
// ConnectableFlux:
var hot = Flux.interval(Duration.ofSeconds(1))
    .publish();         // make it hot (ConnectableFlux)
hot.subscribe(t -> System.out.println("Sub1: " + t));
hot.connect();          // start producing
Thread.sleep(2500);
hot.subscribe(t -> System.out.println("Sub2: " + t)); // joins late, misses first 2

// Share: auto-connect when first subscriber arrives:
Flux<Long> shared = Flux.interval(Duration.ofSeconds(1)).share();

// Replay: buffer events for late subscribers:
Flux<Long> replay = Flux.interval(Duration.ofSeconds(1))
    .replay(3)          // buffer last 3 events
    .autoConnect();
```

---

## 3. Operators – Transform & Combine

### 3.1 Transform Operators

```java
// ── map: synchronous 1-to-1 transform ────────────────────────────────────
Flux.range(1, 5)
    .map(i -> i * 2)               // [2, 4, 6, 8, 10]
    .map(String::valueOf)          // ["2", "4", "6", "8", "10"]

// ── flatMap: async 1-to-N transform (merges inner publishers, unordered) ──
Flux.range(1, 3)
    .flatMap(id -> fetchUserAsync(id))  // concurrent HTTP calls (unordered results)
    .subscribe(user -> log.info("{}", user));

// ── concatMap: async sequential (ordered, slower than flatMap) ────────────
Flux.range(1, 3)
    .concatMap(id -> fetchUserAsync(id))  // sequential, ordered results

// ── flatMapSequential: concurrent fetch but ordered output ────────────────
Flux.range(1, 3)
    .flatMapSequential(id -> fetchUserAsync(id), 4)  // 4 concurrent, ordered output

// ── switchMap: cancel previous if new arrives (typeahead search) ──────────
searchInput.switchMap(query -> searchService.search(query));
// If user types fast, old searches cancelled

// ── filter ────────────────────────────────────────────────────────────────
Flux.range(1, 10)
    .filter(i -> i % 2 == 0)      // [2, 4, 6, 8, 10]

// ── take / skip / limitRequest ────────────────────────────────────────────
Flux.range(1, 100)
    .skip(10)                      // skip first 10
    .take(5)                       // take only 5: [11, 12, 13, 14, 15]
    .limitRate(10);                // request 10 at a time from upstream (backpressure)

// ── distinct / distinctUntilChanged ──────────────────────────────────────
Flux.just(1, 1, 2, 2, 3, 1)
    .distinct()                    // [1, 2, 3] (all unique)
    .subscribe();

Flux.just(1, 1, 2, 2, 3, 3)
    .distinctUntilChanged()        // [1, 2, 3] (remove consecutive duplicates)

// ── buffer / window ───────────────────────────────────────────────────────
Flux.range(1, 10)
    .buffer(3)                     // List groups: [1,2,3], [4,5,6], [7,8,9], [10]
    .subscribe(batch -> log.info("Batch: {}", batch));

Flux.range(1, 10)
    .window(3)                     // Flux groups (non-blocking windowing)
    .flatMap(window -> window.collectList())
    .subscribe();
```

### 3.2 Combine Operators

```java
// ── zip: combine N publishers element-by-element ─────────────────────────
Mono.zip(
    fetchUser(userId),
    fetchOrders(userId),
    fetchPreferences(userId)
).map(tuple -> new UserProfile(
    tuple.getT1(),   // User
    tuple.getT2(),   // List<Order>
    tuple.getT3()    // Preferences
));

// ── merge: interleave multiple streams ───────────────────────────────────
Flux.merge(
    Flux.interval(Duration.ofMillis(100)).map(i -> "A" + i),
    Flux.interval(Duration.ofMillis(150)).map(i -> "B" + i)
);  // A0, B0, A1, A2, B1, ...

// ── concat: one after another (sequential) ────────────────────────────────
Flux.concat(
    fetchPage(1),
    fetchPage(2),
    fetchPage(3)
);  // page1 items, then page2 items, then page3 items

// ── combineLatest: whenever ANY emits, combine with latest of others ──────
Flux.combineLatest(
    priceStream,
    quantityStream,
    (price, qty) -> price.multiply(BigDecimal.valueOf(qty))
);

// ── switchOnFirst: optimize based on first element ───────────────────────
flux.switchOnFirst((signal, flux) -> {
    if (signal.hasValue() && signal.get().isPriority()) {
        return flux.subscribeOn(Schedulers.boundedElastic()); // different scheduler
    }
    return flux;
});
```

### 3.3 Aggregation Operators

```java
// ── collectList / collectMap ──────────────────────────────────────────────
Mono<List<User>> users = userFlux.collectList();
Mono<Map<Long, User>> userMap = userFlux.collectMap(User::id);

// ── reduce / scan ─────────────────────────────────────────────────────────
Mono<Integer> sum = Flux.range(1, 10).reduce(0, Integer::sum);  // 55
Flux<Integer> runningSum = Flux.range(1, 5).scan(0, Integer::sum);  // 0,1,3,6,10,15

// ── count ─────────────────────────────────────────────────────────────────
Mono<Long> count = userFlux.count();

// ── groupBy ───────────────────────────────────────────────────────────────
userFlux
    .groupBy(User::department)
    .flatMap(group -> group
        .collectList()
        .map(users -> Map.entry(group.key(), users))
    );
```

---

## 4. Error Handling

```java
// ── onErrorReturn: fallback value ─────────────────────────────────────────
userService.findById(userId)
    .onErrorReturn(UserNotFoundException.class, User.ANONYMOUS)
    .onErrorReturn(new User("default"));  // for any error

// ── onErrorResume: fallback publisher ────────────────────────────────────
userService.findById(userId)
    .onErrorResume(UserNotFoundException.class, ex ->
        cacheService.getUser(userId))     // try cache on not found
    .onErrorResume(ex -> {
        log.error("Failed to fetch user", ex);
        return Mono.just(User.ANONYMOUS);
    });

// ── onErrorMap: transform exception type ─────────────────────────────────
repository.save(entity)
    .onErrorMap(DataIntegrityViolationException.class,
        ex -> new DuplicateResourceException(ex.getMessage()));

// ── retry ────────────────────────────────────────────────────────────────
httpClient.get()
    .retry(3)                                    // retry up to 3 times
    .retry(ex -> ex instanceof IOException);     // conditional retry

// Exponential backoff retry:
httpClient.get()
    .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
        .maxBackoff(Duration.ofSeconds(30))
        .jitter(0.5)                             // randomize delay
        .filter(ex -> ex instanceof WebClientResponseException)
        .onRetryExhaustedThrow((spec, signal) ->
            new ServiceUnavailableException("Max retries reached", signal.failure()))
    );

// ── doOnError: side effect without handling ───────────────────────────────
mono.doOnError(ex -> metrics.incrementErrorCount(ex.getClass().getSimpleName()))
    .doOnError(DatabaseException.class, ex -> alertService.send(ex));

// ── timeout ───────────────────────────────────────────────────────────────
mono.timeout(Duration.ofSeconds(5))
    .onErrorReturn(TimeoutException.class, defaultValue);

// ── Propagate context (MDC logging) ──────────────────────────────────────
Mono.deferContextual(ctx -> {
    MDC.put("traceId", ctx.getOrDefault("traceId", "unknown"));
    return actualMono.doFinally(s -> MDC.remove("traceId"));
});
```

---

## 5. Schedulers & Threading

```java
// ── subscribeOn: where subscription (upstream) runs ──────────────────────
// Use for wrapping blocking calls
Mono.fromCallable(() -> blockingDatabaseCall())       // blocking
    .subscribeOn(Schedulers.boundedElastic())          // run on dedicated pool

// ── publishOn: where downstream operators run ────────────────────────────
Flux.fromIterable(items)
    .publishOn(Schedulers.parallel())                  // switch to parallel pool
    .map(item -> process(item))                        // runs on parallel
    .publishOn(Schedulers.single())                    // switch to single thread
    .doOnNext(item -> log.info("{}", item));           // runs on single

// ── Scheduler types ───────────────────────────────────────────────────────
Schedulers.immediate()         // current thread (no switch)
Schedulers.single()            // single reusable thread
Schedulers.parallel()          // fixed pool = cpu cores (for CPU work)
Schedulers.boundedElastic()    // elastic pool (for blocking I/O, grows/shrinks)
                                // max: 10 × CPU cores, keep-alive 60s
Schedulers.newBoundedElastic(
    20,                        // max threads
    1000,                      // max queue
    "my-pool",                 // name prefix
    60                         // keep-alive seconds
)
Schedulers.fromExecutor(myExecutor)  // custom ExecutorService

// ── IMPORTANT: Never block on Reactor threads ─────────────────────────────
// ❌ Will cause reactor.blockhound.BlockingOperationError:
.flatMap(item -> {
    Thread.sleep(100);          // ❌ blocking call on reactor thread
    return Mono.just(result);
})

// ✅ Wrap blocking code:
.flatMap(item -> Mono
    .fromCallable(() -> blockingProcess(item))
    .subscribeOn(Schedulers.boundedElastic())
)

// BlockHound: detect blocking calls in non-blocking context
// In test setup:
BlockHound.install();
```

---

## 6. Backpressure

```java
// Backpressure: consumer controls how fast producer sends
// Reactive Streams: subscriber requests N items via Subscription.request(n)

// ── BaseSubscriber: manual backpressure ───────────────────────────────────
Flux.range(1, 1000).subscribe(new BaseSubscriber<Integer>() {
    @Override
    protected void hookOnSubscribe(Subscription subscription) {
        request(5);  // request only 5 initially
    }

    @Override
    protected void hookOnNext(Integer value) {
        process(value);
        if (shouldContinue()) request(1);  // request one more after processing
        else cancel();
    }
});

// ── Overflow strategies ───────────────────────────────────────────────────
Flux.interval(Duration.ofMillis(1))     // fast producer: 1000/s
    .onBackpressureDrop(dropped ->      // drop items when buffer full
        log.warn("Dropped: {}", dropped))
    .subscribe(item -> {
        Thread.sleep(10);               // slow consumer: 100/s
    });

Flux.interval(Duration.ofMillis(1))
    .onBackpressureBuffer(1000,         // buffer up to 1000
        dropped -> log.warn("Buffer overflow"),
        BufferOverflowStrategy.DROP_OLDEST)
    .subscribe(...);

Flux.interval(Duration.ofMillis(1))
    .onBackpressureLatest()             // keep only latest value
    .subscribe(...);

Flux.interval(Duration.ofMillis(1))
    .onBackpressureError()              // throw OverflowException
    .subscribe(...);

// ── limitRate: request upstream in batches ────────────────────────────────
Flux.range(1, 1_000_000)
    .limitRate(100)           // request 100 at a time, refill at 75%
    .flatMap(i -> process(i))
    .subscribe();
```

---

## 7. Spring WebFlux

### 7.1 Annotated Controller (same as MVC)

```java
@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
public class OrderController {

    private final OrderService orderService;

    @GetMapping("/{id}")
    public Mono<ResponseEntity<OrderResponse>> getOrder(@PathVariable Long id) {
        return orderService.findById(id)
            .map(order -> ResponseEntity.ok(OrderResponse.from(order)))
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @GetMapping
    public Flux<OrderResponse> getOrders(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return orderService.findAll(PageRequest.of(page, size))
            .map(OrderResponse::from);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<OrderResponse> createOrder(
            @Valid @RequestBody Mono<CreateOrderRequest> requestMono,
            @AuthenticationPrincipal UserDetails user) {
        return requestMono
            .flatMap(req -> orderService.create(req, user.getUsername()))
            .map(OrderResponse::from);
    }

    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<OrderResponse> streamOrders() {
        return orderService.getOrderStream()  // infinite Flux from Kafka
            .map(OrderResponse::from);
    }
}
```

### 7.2 Functional Router (WebFlux-native)

```java
@Configuration
public class OrderRouter {

    @Bean
    public RouterFunction<ServerResponse> orderRoutes(OrderHandler handler) {
        return RouterFunctions.route()
            .GET("/api/orders/{id}", handler::getOrder)
            .GET("/api/orders",      handler::listOrders)
            .POST("/api/orders",     handler::createOrder)
            .PUT("/api/orders/{id}", handler::updateOrder)
            .DELETE("/api/orders/{id}", RequestPredicates.accept(APPLICATION_JSON), handler::deleteOrder)
            .filter(handler::authenticate)  // filter applied to all routes
            .build();
    }
}

@Component
@RequiredArgsConstructor
public class OrderHandler {

    private final OrderService orderService;

    public Mono<ServerResponse> getOrder(ServerRequest request) {
        var id = Long.parseLong(request.pathVariable("id"));
        return orderService.findById(id)
            .flatMap(order -> ServerResponse.ok()
                .contentType(APPLICATION_JSON)
                .bodyValue(order))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> createOrder(ServerRequest request) {
        return request.bodyToMono(CreateOrderRequest.class)
            .flatMap(req -> orderService.create(req))
            .flatMap(order -> ServerResponse.created(
                    URI.create("/api/orders/" + order.id()))
                .bodyValue(order));
    }

    Mono<ServerResponse> authenticate(ServerRequest req, HandlerFunction<ServerResponse> next) {
        if (!req.headers().firstHeader("Authorization").startsWith("Bearer ")) {
            return ServerResponse.status(HttpStatus.UNAUTHORIZED).build();
        }
        return next.handle(req);
    }
}
```

### 7.3 WebClient – Reactive HTTP Client

```java
@Service
@RequiredArgsConstructor
public class InventoryClient {

    private final WebClient webClient;

    @Bean
    public WebClient webClient() {
        return WebClient.builder()
            .baseUrl("https://inventory.internal")
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .filter(ExchangeFilterFunction.ofRequestProcessor(req -> {
                log.debug("Request: {} {}", req.method(), req.url());
                return Mono.just(req);
            }))
            .codecs(c -> c.defaultCodecs().maxInMemorySize(1 * 1024 * 1024))  // 1MB
            .build();
    }

    public Mono<InventoryItem> getItem(String sku) {
        return webClient.get()
            .uri("/items/{sku}", sku)
            .header("X-API-Key", apiKey)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError,
                res -> res.bodyToMono(ErrorResponse.class)
                    .flatMap(err -> Mono.error(new InventoryException(err.message()))))
            .onStatus(HttpStatusCode::is5xxServerError,
                res -> Mono.error(new ServiceUnavailableException("Inventory service down")))
            .bodyToMono(InventoryItem.class)
            .retryWhen(Retry.backoff(2, Duration.ofMillis(500)));
    }

    public Flux<InventoryItem> getLowStockItems() {
        return webClient.get()
            .uri("/items/low-stock")
            .retrieve()
            .bodyToFlux(InventoryItem.class);  // stream response
    }

    // Parallel calls:
    public Mono<ProductDetail> getProductDetail(String sku) {
        return Mono.zip(
            getItem(sku),
            priceService.getPrice(sku),
            reviewService.getSummary(sku)
        ).map(tuple -> new ProductDetail(tuple.getT1(), tuple.getT2(), tuple.getT3()));
    }
}
```

---

## 8. R2DBC – Reactive Database

```java
// R2DBC: non-blocking database driver (alternative to JDBC)
// Supported: PostgreSQL, MySQL, H2, Oracle, SQL Server

// Dependencies:
// spring-boot-starter-data-r2dbc
// io.r2dbc:r2dbc-postgresql

@Repository
public interface OrderRepository extends ReactiveCrudRepository<Order, Long> {

    Flux<Order> findByCustomerIdAndStatus(Long customerId, OrderStatus status);

    @Query("SELECT * FROM orders WHERE total > :minAmount ORDER BY created_at DESC LIMIT :limit")
    Flux<Order> findLargeOrders(@Param("minAmount") BigDecimal minAmount, @Param("limit") int limit);

    Mono<Long> countByStatus(OrderStatus status);

    @Modifying
    @Query("UPDATE orders SET status = :status WHERE id = :id AND status = :currentStatus")
    Mono<Integer> compareAndSetStatus(Long id, OrderStatus currentStatus, OrderStatus status);
}

// R2dbcEntityTemplate for complex queries:
@Service
@RequiredArgsConstructor
public class OrderQueryService {

    private final R2dbcEntityTemplate template;

    public Flux<Order> searchOrders(OrderSearchCriteria criteria) {
        var query = Query.query(
            where("tenant_id").is(criteria.tenantId())
                .and("status").in(criteria.statuses())
                .and("created_at").greaterThan(criteria.fromDate())
        ).offset(criteria.offset()).limit(criteria.limit());

        return template.select(Order.class)
            .matching(query)
            .all();
    }
}

// R2DBC Transaction:
@Service
@RequiredArgsConstructor
public class OrderService {

    private final TransactionalOperator txOperator;
    private final OrderRepository orderRepo;
    private final StockRepository stockRepo;

    public Mono<Order> createOrder(CreateOrderRequest req) {
        return Mono.zip(
                orderRepo.save(Order.from(req)),
                stockRepo.decrementStock(req.sku(), req.quantity())
            )
            .map(tuple -> tuple.getT1())
            .as(txOperator::transactional);  // wrap in transaction
    }
}
```

---

## 9. Testing Reactive Code

```java
import reactor.test.StepVerifier;

class OrderServiceReactiveTest {

    // ── StepVerifier: main testing tool for reactive ──────────────────────
    @Test
    void findById_existingOrder_returnsOrder() {
        when(orderRepository.findById(1L))
            .thenReturn(Mono.just(testOrder));

        StepVerifier.create(orderService.findById(1L))
            .expectNextMatches(order ->
                order.id().equals(1L) && order.status() == PENDING)
            .verifyComplete();
    }

    @Test
    void findAll_returnsMultipleOrders() {
        when(orderRepository.findAll())
            .thenReturn(Flux.just(order1, order2, order3));

        StepVerifier.create(orderService.findAll())
            .expectNext(order1)
            .expectNext(order2)
            .expectNext(order3)
            .verifyComplete();
    }

    @Test
    void findById_notFound_completesEmpty() {
        when(orderRepository.findById(999L))
            .thenReturn(Mono.empty());

        StepVerifier.create(orderService.findById(999L))
            .verifyComplete();  // no items, no error
    }

    @Test
    void createOrder_dbError_propagatesError() {
        when(orderRepository.save(any()))
            .thenReturn(Mono.error(new DataAccessException("DB down") {}));

        StepVerifier.create(orderService.create(validRequest))
            .verifyError(ServiceException.class);
    }

    // ── Testing time-based operators ──────────────────────────────────────
    @Test
    void processWithDelay() {
        StepVerifier.withVirtualTime(() ->
            Flux.interval(Duration.ofSeconds(10)).take(3)
        )
        .expectSubscription()
        .thenAwait(Duration.ofSeconds(30))   // advance virtual time
        .expectNextCount(3)
        .verifyComplete();
    }

    // ── WebTestClient for WebFlux endpoints ──────────────────────────────
    @WebFluxTest(OrderController.class)
    class OrderControllerTest {

        @Autowired
        WebTestClient webTestClient;

        @MockBean
        OrderService orderService;

        @Test
        void getOrder_returns200() {
            when(orderService.findById(1L)).thenReturn(Mono.just(testOrder));

            webTestClient.get().uri("/api/orders/1")
                .accept(MediaType.APPLICATION_JSON)
                .exchange()
                .expectStatus().isOk()
                .expectBody(OrderResponse.class)
                .value(res -> assertThat(res.id()).isEqualTo(1L));
        }

        @Test
        void streamOrders_returnsSSE() {
            when(orderService.getOrderStream())
                .thenReturn(Flux.just(order1, order2).delayElements(Duration.ofMillis(100)));

            webTestClient.get().uri("/api/orders/stream")
                .accept(MediaType.TEXT_EVENT_STREAM)
                .exchange()
                .expectStatus().isOk()
                .expectBodyList(OrderResponse.class)
                .hasSize(2);
        }
    }
}
```

---

## Trade-offs: Reactive vs Imperative vs Virtual Threads

| | Imperative + Threads | Virtual Threads (Java 21) | Reactive (WebFlux) |
|--|---------------------|--------------------------|-------------------|
| **Learning curve** | Low | Low | High |
| **Debugging** | Easy (stack traces) | Easy | Hard (reactor stack) |
| **I/O Performance** | Medium | High (like reactive) | High |
| **CPU Performance** | Good | Good | Good |
| **Code readability** | High | High | Medium |
| **Error handling** | try/catch (familiar) | try/catch | onErrorResume chains |
| **Database** | JDBC (blocking) | JDBC (OS thread freed) | R2DBC required |
| **Memory** | 1MB/thread | ~few KB/vthread | Minimal threads |
| **Backpressure** | Manual / BlockingQueue | Manual | Built-in |
| **When to use** | Most applications | High-concurrency + familiar | Streaming, high-perf I/O |

---

## Ghi chú – Keywords

- **Keywords**: Reactive Streams, Publisher/Subscriber/Subscription, Project Reactor, Mono/Flux, StepVerifier, WebFlux, RouterFunction, WebClient, R2DBC, TransactionalOperator, subscribeOn/publishOn, Schedulers.boundedElastic, BlockHound, backpressure strategies (DROP/BUFFER/LATEST/ERROR), switchMap vs flatMap vs concatMap, Context propagation, Micrometer observation with Reactor
