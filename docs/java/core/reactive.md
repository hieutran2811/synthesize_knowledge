---
title: "Reactive Programming – Project Reactor & Spring WebFlux"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 1
---
# Reactive Programming – Project Reactor & Spring WebFlux

> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

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

Trong mô hình truyền thống, mỗi request đến được giao cho **một thread** *(luồng)* riêng lo từ đầu đến cuối. Khi thread đó gọi **Blocking I/O** *(tác vụ vào/ra chặn luồng — đọc DB, gọi HTTP...)*, nó phải **đứng chờ** cho tới khi có kết quả, không làm được việc gì khác. Đó chính là mô hình **thread-per-request** *(mỗi request một luồng)*.

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

> 💡 **Giải thích dễ hiểu — vì sao "chặn luồng" lại tốn kém, và reactive cứu thế nào:**
> Hình dung mỗi thread là một **nhân viên phục vụ** trong nhà hàng. Mô hình chặn luồng giống như: nhân viên nhận đơn của bàn A, rồi **đứng luôn trong bếp chờ món nấu xong** mới quay ra — trong lúc chờ, anh ta không phục vụ bàn nào khác. Muốn phục vụ 1000 bàn cùng lúc thì phải thuê 1000 nhân viên, mà mỗi nhân viên "chiếm chỗ" ~1MB RAM (stack) và việc điều phối qua lại giữa họ (**context switching** *(chuyển ngữ cảnh — CPU đổi từ luồng này sang luồng khác)*) cũng tốn công.
> Mô hình **non-blocking I/O** *(vào/ra không chặn luồng)* thì khác: nhân viên đặt đơn vào bếp rồi **quay ra phục vụ bàn khác ngay**; khi món xong, bếp "réo lên" (event) và nhân viên rảnh bất kỳ sẽ mang ra. Nhờ vậy **một vài nhân viên (thread) phục vụ được hàng nghìn bàn** — đó là **event loop** *(vòng lặp sự kiện — một luồng liên tục nhặt và xử lý các sự kiện đã sẵn sàng)*. **Virtual Threads** *(luồng ảo — Java 21)* giải bài toán này theo hướng khác: vẫn viết code kiểu chặn quen thuộc nhưng luồng "ảo" siêu nhẹ, còn Reactive giải bằng cách phi chặn triệt để.

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

> 💡 **Giải thích dễ hiểu — bộ tứ Publisher / Subscriber / Subscription / backpressure:**
> **Reactive Streams** *(chuẩn API cho luồng dữ liệu bất đồng bộ)* định nghĩa một "giao kèo" giữa bên phát và bên nhận, giống quan hệ **tòa soạn báo và độc giả đặt dài hạn**:
> - **Publisher** *(bên phát — nguồn tạo ra dữ liệu)*: như tòa soạn in báo. Nhưng nó **chưa in gì** cho tới khi có người đăng ký.
> - **Subscriber** *(bên nhận — người tiêu thụ dữ liệu)*: như độc giả đăng ký nhận báo.
> - **Subscription** *(hợp đồng đăng ký nối hai bên)*: tờ hợp đồng ràng buộc giữa hai bên; qua nó độc giả nói "tháng này tôi chỉ nhận nổi 5 số thôi".
> - **backpressure** *(cơ chế điều tiết ngược khi bên nhận xử lý chậm hơn bên gửi)*: chính là việc độc giả **chủ động yêu cầu số lượng** vừa sức mình, thay vì bị tòa soạn dội báo ngập nhà. Đây là điểm cốt lõi phân biệt Reactive Streams với luồng dữ liệu thường: **người nhận nắm quyền kiểm soát tốc độ**, không phải người gửi.

---

## 2. Project Reactor – Mono & Flux

### 2.1 Mono<T> – 0 or 1 element

**Mono<T>** *(Publisher phát ra tối đa 1 phần tử — 0 hoặc 1)* là kiểu Publisher của Project Reactor dùng cho kết quả "một hoặc không có" (ví dụ: tìm 1 user theo id, hoặc rỗng nếu không thấy).

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

> 💡 **Giải thích dễ hiểu — vì sao "không subscribe thì không có gì xảy ra":**
> Một Mono/Flux khi mới khai báo chỉ là **công thức nấu ăn viết trên giấy**, chứ chưa phải món ăn. Bạn viết `Mono.just(...).map(...).filter(...)` giống như liệt kê các bước trong công thức — bếp vẫn nguội, chưa ai nấu. Chỉ khi có người gọi **`subscribe()`** (thực khách đặt món) thì công thức mới được đem đi thực thi từ đầu. Vì thế người ta gọi đây là **cold publisher** *(nguồn "lạnh" — chỉ chạy khi có người đăng ký, và mỗi người đăng ký được nấu một suất riêng từ đầu)*. Quên gọi `subscribe()` là lỗi kinh điển của người mới: code "chạy" nhưng chẳng thấy gì xảy ra, vì công thức chưa bao giờ được bật bếp.

### 2.2 Flux<T> – 0 to N elements

**Flux<T>** *(Publisher phát ra dãy 0 tới N phần tử, có thể vô hạn)* dùng cho luồng nhiều phần tử: danh sách kết quả, dòng sự kiện, stream vô tận từ Kafka...

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

> 💡 **Giải thích dễ hiểu — Mono hay Flux, chọn cái nào?**
> Rất đơn giản: nếu kết quả **chắc chắn tối đa một cái** (một bản ghi, một phản hồi HTTP, hoặc rỗng) → dùng **Mono**. Nếu là **một dãy nhiều cái** (danh sách, dòng sự kiện liên tục) → dùng **Flux**. Ví von: Mono là **một lá thư** trong hộp thư, còn Flux là **cả một băng chuyền bưu kiện** có thể chạy mãi không dứt. Hai kiểu chuyển đổi qua lại được: `flux.collectList()` gom cả băng chuyền thành một danh sách (Mono), còn `mono.flux()` biến lá thư đơn thành băng chuyền một món.

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

> 💡 **Giải thích dễ hiểu — hot stream vs cold stream:**
> - **Cold stream** *(luồng "lạnh" — phát lại từ đầu cho mỗi người đăng ký)* giống **dịch vụ xem phim theo yêu cầu (Netflix)**: ai bấm play cũng được xem bộ phim từ giây thứ 0, độc lập với người khác. Vì thế trong ví dụ, hai lần `subscribe` đều nhận đủ `1 2 3 4 5`.
> - **Hot stream** *(luồng "nóng" — phát trực tiếp, ai vào sau lỡ mất phần đầu)* giống **truyền hình trực tiếp bóng đá**: trận đấu vẫn diễn ra dù có ai xem hay không; bạn bật TV lúc phút 30 thì lỡ mất 30 phút đầu. `Sub2` join muộn nên mất 2 tick đầu là vì vậy.
> - `share()`, `publish()`, `replay(n)` là các cách "hâm nóng" một cold stream thành hot: `replay(n)` còn tử tế cho người vào muộn xem lại `n` sự kiện gần nhất, như kênh có tính năng "tua lại vài phút trước".

---

## 3. Operators – Transform & Combine

**Operator** *(toán tử — một bước biến đổi trên luồng, ví dụ `map`, `filter`, `flatMap`)* nối lại thành một chuỗi xử lý. Điều quan trọng cần nhớ: mỗi operator **không chạy ngay lúc bạn viết ra nó**.

> 💡 **Giải thích dễ hiểu — assembly-time vs subscription-time (vì sao operator "lười"):**
> Việc dựng chuỗi operator xảy ra ở hai thời điểm khác nhau, dễ gây bối rối cho người mới:
> - **assembly-time** *(lúc lắp ráp — khi bạn gõ `.map().filter()...` để dựng pipeline)*: giai đoạn này chỉ **vẽ sơ đồ dây chuyền**, chưa có dữ liệu nào chảy qua. Giống như lắp đặt các máy trên một **dây chuyền sản xuất** khi nhà máy còn tắt điện.
> - **subscription-time** *(lúc đăng ký — khi `subscribe()` được gọi)*: mới **bật điện**, nguyên liệu bắt đầu chạy từ đầu dây chuyền qua từng máy.
> Vì operator "lười" (lazy) như vậy, một tác dụng phụ hay bẫy là: code trong `map(x -> sideEffect(x))` sẽ **không chạy** nếu chưa ai subscribe. Ngược lại, cái gì viết **bên ngoài** operator (ví dụ gọi `expensiveCall()` trực tiếp thay vì bọc trong `Mono.defer`) lại chạy ngay ở assembly-time — đó là lý do có `defer`/`fromCallable` để "hoãn" việc thực thi tới lúc subscribe.

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

> 💡 **Giải thích dễ hiểu — map vs flatMap vs concatMap vs switchMap:**
> Bốn "họ hàng" này hay bị nhầm. Hình dung bạn có một dãy mã đơn hàng và với mỗi mã cần gọi API lấy chi tiết:
> - **map**: biến đổi **đồng bộ 1→1**, không gọi ra ngoài — như dán nhãn lại từng gói hàng ngay tại chỗ.
> - **flatMap**: với mỗi phần tử mở một tác vụ bất đồng bộ và **gộp kết quả về, không đảm bảo thứ tự** — như phát cho nhiều nhân viên chạy đi lấy hàng cùng lúc, ai về trước giao trước (nhanh nhất nhưng đảo thứ tự).
> - **concatMap**: cũng bất đồng bộ nhưng **làm tuần tự, giữ đúng thứ tự** — một nhân viên lấy xong món này mới đi món kế (chậm hơn, thứ tự chuẩn).
> - **switchMap**: khi phần tử mới đến thì **hủy luôn tác vụ đang chạy dở** của phần tử cũ — đúng cho ô tìm kiếm gõ phím: người dùng gõ tiếp thì kết quả tìm cũ vứt đi, chỉ giữ lần gõ mới nhất.

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

**Schedulers** *(bộ điều phối — quyết định code chạy trên nhóm luồng nào)* cho phép bạn chỉ định phần nào của pipeline chạy ở đâu, thông qua hai operator `subscribeOn` và `publishOn`.

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

> 💡 **Giải thích dễ hiểu — subscribeOn, publishOn và "cấm chặn luồng":**
> Hình dung pipeline như một **dây chuyền chuyển bưu kiện** đi qua nhiều trạm, mỗi trạm do một tổ công nhân (nhóm luồng) đảm nhận:
> - **subscribeOn** *(chọn nhóm luồng cho phần nguồn/thượng nguồn)*: quyết định **nơi khởi phát** dây chuyền chạy — đặt ở đâu trong chuỗi cũng ảnh hưởng từ gốc. Dùng khi cần bọc một lời gọi chặn (đọc DB kiểu cũ) để nó chạy ở tổ riêng, không làm nghẽn dây chuyền chính.
> - **publishOn** *(chọn nhóm luồng cho phần hạ nguồn)*: từ điểm này trở đi, **bàn giao hàng cho tổ công nhân khác**. Đặt nhiều `publishOn` là chuyền qua nhiều tổ.
> - Vì sao **tuyệt đối không được `Thread.sleep()` hay gọi chặn trên luồng reactor?** Vì cả nghìn request dùng chung vài luồng event loop; một luồng bị "ngủ" thì hàng loạt request khác đứng hình theo — như một băng chuyền chung mà một công nhân ngủ gật giữa dây chuyền, cả dây tắc. Giải pháp: bọc việc chặn trong `subscribeOn(Schedulers.boundedElastic())` — đẩy sang **tổ luồng co giãn chuyên trị việc chờ đợi**. `BlockHound` là "camera giám sát" phát hiện ai lỡ gọi chặn nhầm chỗ.

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

> 💡 **Giải thích dễ hiểu — backpressure và bốn cách xử lý khi "quá tải":**
> Backpressure giải quyết cảnh **bên phát nhanh hơn bên nhận** — như một vòi nước xả mạnh vào cái xô nhỏ đang được múc ra chậm. Nếu không kiểm soát, xô tràn (tràn bộ nhớ). Reactive cho bên nhận **chủ động "gọi" đúng lượng nó xử lý nổi** (`request(n)`), như bảo vòi "cho tôi đúng 5 lít thôi". Khi nguồn không thể chậm lại (ví dụ tick thời gian, sự kiện thị trường), ta chọn một **chiến lược xử lý tràn**:
> - **onBackpressureBuffer**: hứng tạm vào một bể chứa (buffer) — an toàn nhưng bể đầy vẫn vỡ.
> - **onBackpressureDrop**: bỏ luôn phần thừa — như tổng đài quá tải thì bỏ cuộc gọi mới.
> - **onBackpressureLatest**: chỉ giữ giá trị **mới nhất**, cũ vứt — hợp cho giá cổ phiếu (chỉ cần giá hiện tại).
> - **onBackpressureError**: báo lỗi ngay khi tràn — "thà dừng còn hơn âm thầm sai".

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
