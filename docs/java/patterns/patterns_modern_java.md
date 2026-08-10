---
title: "Design Patterns với Modern Java (Java 16–21)"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Design Patterns với Modern Java (Java 16–21)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

## Tại sao cần reimagine GoF với Modern Java?

GoF được viết năm 1994 — trước Lambda, Stream, Records, Sealed Classes. Nhiều pattern từng "boilerplate-heavy" nay có thể viết ngắn gọn, type-safe, và expressive hơn nhiều.

> 💡 **Giải thích dễ hiểu — hiện đại hóa cách viết, không xóa mục đích pattern:**
> Pattern gọi tên một vấn đề và trade-off, không bắt buộc một sơ đồ class cố định. Lambda có thể thay một Strategy class nhỏ, sealed switch có thể thay Visitor trong hierarchy đóng, nhưng class truyền thống vẫn hợp lý khi implementation cần state, lifecycle, dependency hoặc được mở rộng từ bên ngoài. Hãy giữ “ý định” của pattern rồi chọn công cụ Java ngắn và rõ nhất.

---

## 1. Strategy Pattern → Functional Interface

### Cách cũ (class hierarchy)
```java
interface SortStrategy { void sort(int[] arr); }
class BubbleSort implements SortStrategy { ... }
class QuickSort implements SortStrategy { ... }

class Sorter {
    private SortStrategy strategy;
    Sorter(SortStrategy s) { this.strategy = s; }
    void sort(int[] arr) { strategy.sort(arr); }
}
```

### Modern Java (Lambda / Method Reference)
```java
@FunctionalInterface
interface SortStrategy { void sort(int[] arr); }

class Sorter {
    private final SortStrategy strategy;
    Sorter(SortStrategy s) { this.strategy = s; }
    void sort(int[] arr) { strategy.sort(arr); }
}

// Usage — no class needed
Sorter s1 = new Sorter(Arrays::sort);                          // method ref
Sorter s2 = new Sorter(arr -> bubbleSort(arr));                // lambda
Sorter s3 = new Sorter(arr -> IntStream.range(0, arr.length)  // inline
    .boxed().sorted().mapToInt(i -> i).toArray());

// Store strategies in Map
Map<String, SortStrategy> strategies = Map.of(
    "bubble", MySort::bubble,
    "quick",  MySort::quick,
    "merge",  MySort::merge
);
strategies.get("quick").sort(data);
```

**Lợi ích:** Zero boilerplate class, strategies có thể compose:
```java
SortStrategy loggedSort = arr -> {
    log.info("Sorting {} elements", arr.length);
    Arrays.sort(arr);
    log.info("Sort complete");
};
```

> 💡 **Giải thích dễ hiểu — lambda phù hợp khi strategy chỉ là một hành vi:**
> Nếu biến thể chỉ cần “nhận input, trả output”, lambda giống tờ công thức đưa thẳng cho `Sorter`, không cần tạo cả class. Khi strategy có cấu hình phức tạp, metrics, nhiều method hoặc vòng đời riêng, named class vẫn dễ đọc, inject và test hơn. Functional interface giảm nghi thức chứ không làm biến mất Strategy Pattern.

---

## 2. Command Pattern → Records + Sealed Classes

### Cách cũ
```java
interface Command { void execute(); void undo(); }
class MoveCommand implements Command { ... }
class ResizeCommand implements Command { ... }
```

### Modern Java (Sealed + Records)
```java
// Commands as sealed hierarchy — exhaustive, immutable, no boilerplate
sealed interface Command permits Move, Resize, Rotate, Delete {}

record Move(int dx, int dy)         implements Command {}
record Resize(double factor)        implements Command {}
record Rotate(double angleDegrees)  implements Command {}
record Delete(String elementId)     implements Command {}

// Executor với pattern matching — không cần instanceof chains
class CommandExecutor {
    private final Deque<Command> history = new ArrayDeque<>();

    void execute(Command cmd) {
        switch (cmd) {
            case Move(int dx, int dy)       -> applyMove(dx, dy);
            case Resize(double f)           -> applyResize(f);
            case Rotate(double angle)       -> applyRotate(angle);
            case Delete(String id)          -> applyDelete(id);
        }
        history.push(cmd);
    }

    void undo() {
        if (history.isEmpty()) return;
        Command last = history.pop();
        switch (last) {
            case Move(int dx, int dy)    -> applyMove(-dx, -dy);
            case Resize(double f)        -> applyResize(1.0 / f);
            case Rotate(double angle)    -> applyRotate(-angle);
            case Delete(String id)       -> restore(id);
        }
    }
}
```

**Lợi ích:**
- Records đảm bảo immutability — command history an toàn
- Sealed ensures exhaustive switch — compiler báo lỗi khi thêm command mới mà quên handle
- Deconstruction patterns trực tiếp destructure fields

> 💡 **Giải thích dễ hiểu — command trở thành dữ liệu có thể lưu và phát lại:**
> Record mô tả “đã yêu cầu việc gì” như một phiếu lệnh bất biến, còn executor diễn giải phiếu đó. Sealed hierarchy giúp compiler kiểm tra mọi loại lệnh. Tuy nhiên undo thực tế thường phải lưu **state trước khi thực thi** hoặc một compensating command; chỉ đảo dấu `dx` hay `angle` không đủ cho mọi thao tác như xóa dữ liệu.

---

## 3. Visitor Pattern → Sealed Classes + Pattern Matching

### Cách cũ (double dispatch — verbose)
```java
interface Shape { <T> T accept(ShapeVisitor<T> v); }
class Circle implements Shape { public <T> T accept(ShapeVisitor<T> v) { return v.visit(this); } }
class Rectangle implements Shape { public <T> T accept(ShapeVisitor<T> v) { return v.visit(this); } }

interface ShapeVisitor<T> {
    T visit(Circle c);
    T visit(Rectangle r);
}
class AreaVisitor implements ShapeVisitor<Double> { ... }
class PerimeterVisitor implements ShapeVisitor<Double> { ... }
```

### Modern Java (Sealed + switch expression)
```java
sealed interface Shape permits Circle, Rectangle, Triangle {}
record Circle(double radius)                    implements Shape {}
record Rectangle(double width, double height)   implements Shape {}
record Triangle(double a, double b, double c)   implements Shape {}

// "Visitor" = just a function using switch — no visitor interface needed
static double area(Shape s) {
    return switch (s) {
        case Circle(double r)               -> Math.PI * r * r;
        case Rectangle(double w, double h)  -> w * h;
        case Triangle(double a, double b, double c) -> {
            double p = (a + b + c) / 2;
            yield Math.sqrt(p * (p-a) * (p-b) * (p-c)); // Heron's formula
        }
    };
}

static String describe(Shape s) {
    return switch (s) {
        case Circle c when c.radius() > 100  -> "Large circle";
        case Circle c                         -> "Small circle r=" + c.radius();
        case Rectangle(double w, double h) when w == h -> "Square " + w;
        case Rectangle r                      -> "Rectangle %sx%s".formatted(r.width(), r.height());
        case Triangle t                       -> "Triangle";
    };
}

// Adding new "visitor" = thêm 1 method — không cần sửa class hierarchy
static double perimeter(Shape s) {
    return switch (s) {
        case Circle(double r)               -> 2 * Math.PI * r;
        case Rectangle(double w, double h)  -> 2 * (w + h);
        case Triangle(double a, double b, double c) -> a + b + c;
    };
}
```

**Trade-off:** Closed hierarchy (phải dùng `permits`). Thêm shape mới = compile error ở tất cả switch → đây là **feature**, không phải bug.

> 💡 **Giải thích dễ hiểu — sealed switch đổi trục mở rộng:**
> Cách này làm việc thêm operation mới rất rẻ: chỉ thêm một function `area`, `print`, `serialize`. Nhưng thêm subtype mới buộc sửa mọi exhaustive switch. Visitor cổ điển có trade-off tương tự theo cách tổ chức khác và vẫn hữu ích khi hierarchy không thể sửa hoặc operation cần object/lifecycle riêng.

---

## 4. Builder Pattern → Records + wither methods

### Records với compact canonical constructor
```java
record ServerConfig(
    String host,
    int port,
    int timeoutMs,
    boolean ssl,
    int maxConnections
) {
    // Compact canonical — validation
    ServerConfig {
        Objects.requireNonNull(host, "host required");
        if (port < 1 || port > 65535) throw new IllegalArgumentException("Invalid port: " + port);
        if (timeoutMs < 0) throw new IllegalArgumentException("Negative timeout");
        if (maxConnections < 1) throw new IllegalArgumentException("At least 1 connection");
    }

    // Wither methods — return new record with one field changed
    ServerConfig withHost(String host) { return new ServerConfig(host, port, timeoutMs, ssl, maxConnections); }
    ServerConfig withPort(int port) { return new ServerConfig(host, port, timeoutMs, ssl, maxConnections); }
    ServerConfig withSsl(boolean ssl) { return new ServerConfig(host, port, timeoutMs, ssl, maxConnections); }
    ServerConfig withTimeout(int ms) { return new ServerConfig(host, port, ms, ssl, maxConnections); }
    ServerConfig withMaxConnections(int max) { return new ServerConfig(host, port, timeoutMs, ssl, max); }

    // Factory for defaults
    static ServerConfig defaultConfig() {
        return new ServerConfig("localhost", 8080, 30_000, false, 10);
    }
}

// Usage — fluent, immutable
ServerConfig prod = ServerConfig.defaultConfig()
    .withHost("api.example.com")
    .withPort(443)
    .withSsl(true)
    .withTimeout(5_000)
    .withMaxConnections(100);
```

### Khi nào vẫn dùng Builder class?
- Nhiều hơn ~6 fields
- Fields có complex dependencies (nếu A thì B required)
- Gradual construction across multiple steps
- Public API cần stability khi thêm fields

> 💡 **Giải thích dễ hiểu — wither tốt cho vài nút, Builder tốt cho bảng điều khiển lớn:**
> Wither tạo bản record mới bằng cách đổi một component, gọn với value object nhỏ và immutable. Khi có nhiều field tùy chọn, thứ tự xây dựng nhiều bước hoặc quy tắc phụ thuộc chéo, Builder giúp đặt tên từng lựa chọn và chỉ validate một lần ở `build()`. Chuỗi wither dài tạo nhiều object trung gian và dễ quên cung cấp method cho component mới.

---

## 5. State Pattern → Sealed Classes

### Modern Java FSM

> 💡 **Giải thích dễ hiểu — state là một giá trị có kiểu, không phải chuỗi:**
> `"SHIPPED"` chỉ cho biết tên trạng thái; record `Shipped(shippedAt, trackingCode)` còn buộc dữ liệu hợp lệ đi kèm trạng thái đó. Sealed switch biến bảng chuyển trạng thái thành code được compiler kiểm tra, làm các trạng thái bất khả thi như “Pending nhưng có tracking code” khó biểu diễn hơn.
```java
sealed interface OrderState permits Pending, Paid, Shipped, Delivered, Cancelled {}

record Pending(Instant createdAt)       implements OrderState {}
record Paid(Instant paidAt, String txId) implements OrderState {}
record Shipped(Instant shippedAt, String trackingCode) implements OrderState {}
record Delivered(Instant deliveredAt)   implements OrderState {}
record Cancelled(Instant cancelledAt, String reason) implements OrderState {}

class Order {
    private OrderState state;

    Order() { this.state = new Pending(Instant.now()); }

    // Transitions — return new state or throw
    void pay(String transactionId) {
        state = switch (state) {
            case Pending p   -> new Paid(Instant.now(), transactionId);
            case Paid p      -> throw new IllegalStateException("Already paid");
            case Shipped s   -> throw new IllegalStateException("Already shipped");
            case Delivered d -> throw new IllegalStateException("Already delivered");
            case Cancelled c -> throw new IllegalStateException("Order cancelled");
        };
    }

    void ship(String trackingCode) {
        state = switch (state) {
            case Paid p   -> new Shipped(Instant.now(), trackingCode);
            default       -> throw new IllegalStateException("Cannot ship from state: " + state);
        };
    }

    void deliver() {
        if (state instanceof Shipped(Instant shippedAt, String code)) {
            state = new Delivered(Instant.now());
        } else {
            throw new IllegalStateException("Order not shipped");
        }
    }

    void cancel(String reason) {
        state = switch (state) {
            case Pending p  -> new Cancelled(Instant.now(), reason);
            case Paid p     -> new Cancelled(Instant.now(), reason);  // refund logic elsewhere
            case Shipped s  -> throw new IllegalStateException("Cannot cancel shipped order");
            case Delivered d -> throw new IllegalStateException("Already delivered");
            case Cancelled c -> throw new IllegalStateException("Already cancelled");
        };
    }

    // Query state data via pattern matching
    Optional<String> getTrackingCode() {
        return state instanceof Shipped(_, String code) ? Optional.of(code) : Optional.empty();
    }
}
```

---

## 6. Observer Pattern → Functional + Reactive

### Cách cũ
```java
interface Observer { void update(Event e); }
class EventBus {
    private Map<Class<?>, List<Observer>> listeners = new HashMap<>();
    void subscribe(Class<?> type, Observer o) { ... }
    void publish(Event e) { ... }
}
```

### Modern: Type-safe event bus với generics + lambdas
```java
class TypedEventBus {
    private final Map<Class<?>, List<Consumer<?>>> handlers = new ConcurrentHashMap<>();

    @SuppressWarnings("unchecked")
    <T> void subscribe(Class<T> type, Consumer<T> handler) {
        handlers.computeIfAbsent(type, k -> new CopyOnWriteArrayList<>()).add(handler);
    }

    @SuppressWarnings("unchecked")
    <T> void publish(T event) {
        List<Consumer<?>> list = handlers.getOrDefault(event.getClass(), List.of());
        for (Consumer<?> h : list) ((Consumer<T>) h).accept(event);
    }
}

// Events as records
record UserRegistered(String userId, String email, Instant at) {}
record OrderPlaced(String orderId, String userId, BigDecimal amount) {}

// Subscriptions — lambda
bus.subscribe(UserRegistered.class, e -> emailService.sendWelcome(e.email()));
bus.subscribe(UserRegistered.class, e -> analyticsService.track("signup", e.userId()));
bus.subscribe(OrderPlaced.class, e -> paymentService.charge(e.orderId(), e.amount()));

// Publish
bus.publish(new UserRegistered("u-123", "alice@example.com", Instant.now()));
```

### Reactive với Flow API
```java
class PricePublisher extends SubmissionPublisher<BigDecimal> {
    void updatePrice(BigDecimal price) { submit(price); }
}

class PriceAlert implements Flow.Subscriber<BigDecimal> {
    private Flow.Subscription subscription;
    private final BigDecimal threshold;

    PriceAlert(BigDecimal threshold) { this.threshold = threshold; }

    @Override public void onSubscribe(Flow.Subscription s) {
        this.subscription = s;
        s.request(1);  // yêu cầu từng phần tử để minh họa backpressure
    }

    @Override public void onNext(BigDecimal price) {
        if (price.compareTo(threshold) > 0) {
            System.out.println("ALERT: Price " + price + " exceeds " + threshold);
        }
        subscription.request(1);  // or use request(1) in onSubscribe for pull-based
    }

    @Override public void onError(Throwable t) { t.printStackTrace(); }
    @Override public void onComplete() { System.out.println("Stream complete"); }
}
```

> 💡 **Giải thích dễ hiểu — callback ngắn chưa đồng nghĩa reactive:**
> Event bus dùng `Consumer<T>` giúp đăng ký handler gọn, nhưng ví dụ `publish()` vẫn gọi handler đồng bộ trên thread của publisher. Flow API bổ sung protocol `request(n)` để subscriber báo sức chứa (*backpressure*). Muốn production-ready còn phải quyết định scheduler, xử lý handler lỗi, thứ tự sự kiện và chính sách khi consumer chậm.

---

## 7. Prototype Pattern → Records và phương thức tạo bản sao

Records có structural equality và component `final`, nên có thể thay Prototype trong nhiều trường hợp value object; record **không tự deep-copy** object graph:

> 💡 **Giải thích dễ hiểu — record sao chép chiếc hộp, không nhân bản mọi thứ trong hộp:**
> `withSubject()` tạo record mới nhưng component không đổi như `List<String> cc` có thể vẫn là cùng reference. Muốn snapshot độc lập, canonical constructor phải dùng `List.copyOf`, hoặc code phải deep-copy từng phần tử mutable. Record hỗ trợ bất biến nông và value semantics; nó không biến clone nông thành clone sâu tự động.

```java
// Không cần clone() cho các component value bất biến;
// nested mutable object vẫn phải được copy tường minh.
record Point(double x, double y) {
    Point translate(double dx, double dy) { return new Point(x + dx, y + dy); }
    Point scale(double factor) { return new Point(x * factor, y * factor); }
    Point reflect() { return new Point(-x, -y); }
}

// Configuration template (Prototype intent)
record EmailTemplate(String subject, String body, List<String> cc) {
    // wither creates "prototype copy with changes"
    EmailTemplate withSubject(String s) { return new EmailTemplate(s, body, cc); }
    EmailTemplate withCc(String... addresses) {
        return new EmailTemplate(subject, body, List.of(addresses));
    }
}

EmailTemplate base = new EmailTemplate("Welcome", "Hello {name}!", List.of("admin@co.com"));
EmailTemplate vip  = base.withSubject("VIP Welcome").withCc("vip@co.com", "admin@co.com");
EmailTemplate trial = base.withSubject("Trial Welcome");
```

**Khi vẫn cần Prototype:** Mutable objects với deep object graph (game entities, document cloning).

---

## 8. Decorator Pattern → Functional Composition

### Traditional Decorator (I/O streams style)

> 💡 **Giải thích dễ hiểu — function composition là decorator không cần lớp vỏ:**
> Mỗi `Function<String, String>` nhận và trả cùng một contract, nên `andThen` có thể xếp trim → remove HTML → uppercase như chuỗi decorator. Cách này hợp với phép biến đổi thuần, không state. Nếu decorator cần identity, nhiều method, resource lifecycle hoặc framework proxying, object decorator truyền thống vẫn rõ hơn.
```java
interface TextProcessor { String process(String text); }

// Composition via lambdas — không cần class per decorator
TextProcessor uppercase = String::toUpperCase;
TextProcessor trim      = String::strip;
TextProcessor removeHtml = s -> s.replaceAll("<[^>]+>", "");

// Compose (right to left like Function.compose, left to right like andThen)
TextProcessor pipeline = ((Function<String, String>) String::strip)
    .andThen(s -> s.replaceAll("<[^>]+>", ""))
    .andThen(String::toUpperCase)::apply;

String result = pipeline.process("  <b>Hello World</b>  ");
// → "HELLO WORLD"
```

### Generic Decorator với functional interface
```java
static <T> UnaryOperator<T> loggingDecorator(UnaryOperator<T> op, String name) {
    return t -> {
        log.debug("Before {}: {}", name, t);
        T result = op.apply(t);
        log.debug("After {}: {}", name, result);
        return result;
    };
}

static <T> UnaryOperator<T> retryDecorator(UnaryOperator<T> op, int maxRetries) {
    return t -> {
        for (int i = 0; i < maxRetries; i++) {
            try { return op.apply(t); }
            catch (RuntimeException e) {
                if (i == maxRetries - 1) throw e;
                log.warn("Retry {}/{}", i + 1, maxRetries);
            }
        }
        throw new IllegalStateException("unreachable");
    };
}

// Wrap any operation
UnaryOperator<String> callApi = url -> httpClient.get(url);
UnaryOperator<String> withLog   = loggingDecorator(callApi, "API_CALL");
UnaryOperator<String> withRetry = retryDecorator(withLog, 3);
```

---

## 9. Singleton → Holder Pattern + Enum

```java
// Best practice: Holder (Initialization-on-demand)
class DatabasePool {
    private DatabasePool() { /* expensive init */ }

    private static final class Holder {
        static final DatabasePool INSTANCE = new DatabasePool();
    }

    public static DatabasePool getInstance() { return Holder.INSTANCE; }
}

// Enum Singleton — serialization-safe, reflection-safe
enum AppConfig {
    INSTANCE;

    private final Properties props;
    AppConfig() {
        props = new Properties();
        // load config
    }
    public String get(String key) { return props.getProperty(key); }
}
AppConfig.INSTANCE.get("db.url");
```

### Spring context: Singleton là mặc định
```java
@Configuration
class AppConfig {
    @Bean  // Singleton scope by default
    DataSource dataSource() { return new HikariDataSource(config()); }

    @Bean @Scope("prototype")  // Mỗi lần inject = instance mới
    HttpClient httpClient() { return HttpClient.newHttpClient(); }
}
```

---

## 10. Template Method → Default Methods + Functional

### Interface với default methods (partial template)
```java
interface DataMigration {
    // Template method
    default void migrate() {
        List<Record> data = extract();
        List<Record> transformed = transform(data);
        load(transformed);
        verify(transformed.size());
    }

    List<Record> extract();  // abstract steps
    List<Record> transform(List<Record> data);
    void load(List<Record> data);

    default void verify(int count) {  // optional hook with default
        log.info("Migrated {} records", count);
    }
}

// Lambda-based template (higher-order functions)
class DataPipeline {
    static <T, R> void run(
        Supplier<List<T>> extractor,
        Function<List<T>, List<R>> transformer,
        Consumer<List<R>> loader
    ) {
        List<T> raw = extractor.get();
        List<R> processed = transformer.apply(raw);
        loader.accept(processed);
    }
}

// Usage — no class needed
DataPipeline.run(
    () -> db.query("SELECT * FROM legacy"),
    records -> records.stream().map(LegacyMapper::toNew).toList(),
    newRecords -> newRepo.saveAll(newRecords)
);
```

---

## Pattern Combinations trong Modern Java

### Result<T> Monad (Sealed + Records)

> 💡 **Giải thích dễ hiểu — lỗi trở thành một nhánh dữ liệu phải xử lý:**
> Thay vì exception nhảy khỏi luồng điều khiển, `Result<T>` biểu diễn rõ `Ok` hoặc `Err`. `map` chỉ biến đổi giá trị thành công và cho lỗi đi xuyên qua; `flatMap` nối operation cũng có thể thất bại. Cách này phù hợp với lỗi nghiệp vụ dự kiến, nhưng không nên nuốt lỗi lập trình nghiêm trọng hoặc mất stack trace cần chẩn đoán.
```java
sealed interface Result<T> permits Result.Ok, Result.Err {
    record Ok<T>(T value) implements Result<T> {}
    record Err<T>(String message, Throwable cause) implements Result<T> {
        Err(String message) { this(message, null); }
    }

    static <T> Result<T> ok(T value) { return new Ok<>(value); }
    static <T> Result<T> err(String msg) { return new Err<>(msg); }
    static <T> Result<T> of(Supplier<T> supplier) {
        try { return ok(supplier.get()); }
        catch (Exception e) { return err(e.getMessage()); }
    }

    default <U> Result<U> map(Function<T, U> f) {
        return switch (this) {
            case Ok<T>(T v)          -> Result.of(() -> f.apply(v));
            case Err<T>(var m, var c) -> new Err<>(m, c);
        };
    }

    default <U> Result<U> flatMap(Function<T, Result<U>> f) {
        return switch (this) {
            case Ok<T>(T v)           -> f.apply(v);
            case Err<T>(var m, var c) -> new Err<>(m, c);
        };
    }

    default T getOrElse(T defaultValue) {
        return switch (this) {
            case Ok<T>(T v)  -> v;
            case Err<T> err  -> defaultValue;
        };
    }

    default boolean isOk() { return this instanceof Ok; }
}

// Usage — chain without try-catch
Result<User> result = Result.of(() -> db.findUser(id))
    .flatMap(u -> Result.of(() -> enrichWithProfile(u)))
    .map(u -> sanitize(u));

switch (result) {
    case Result.Ok(User u)     -> response.ok(u);
    case Result.Err(String m, _) -> response.error(m);
}
```

### Event Sourcing với Sealed Events
```java
sealed interface AccountEvent permits
    AccountOpened, MoneyDeposited, MoneyWithdrawn, AccountClosed {}

record AccountOpened(String accountId, BigDecimal initialBalance, Instant at) implements AccountEvent {}
record MoneyDeposited(String accountId, BigDecimal amount, Instant at) implements AccountEvent {}
record MoneyWithdrawn(String accountId, BigDecimal amount, Instant at) implements AccountEvent {}
record AccountClosed(String accountId, String reason, Instant at) implements AccountEvent {}

// State reconstruction — fold over events
record AccountState(String id, BigDecimal balance, boolean closed) {
    static AccountState EMPTY = new AccountState(null, BigDecimal.ZERO, false);

    AccountState apply(AccountEvent event) {
        return switch (event) {
            case AccountOpened(var id, var bal, _) -> new AccountState(id, bal, false);
            case MoneyDeposited(_, var amt, _)      -> new AccountState(id, balance.add(amt), closed);
            case MoneyWithdrawn(_, var amt, _)      -> new AccountState(id, balance.subtract(amt), closed);
            case AccountClosed(_, _, _)             -> new AccountState(id, balance, true);
        };
    }
}

AccountState state = events.stream()
    .reduce(AccountState.EMPTY, AccountState::apply, (a, b) -> b);
```

---

## Ghi chú

**Tóm tắt hiệu quả Modern Java vs GoF classic:**

| GoF Pattern | Cách thể hiện Modern Java thường gặp |
|-------------|------------------------|
| Strategy | `@FunctionalInterface` + Lambda |
| Command | `sealed interface` + `record` |
| Visitor | `sealed` + `switch` expression |
| State | `sealed interface` + deconstruction |
| Observer | `Consumer<T>` + `SubmissionPublisher` |
| Prototype | `record` wither methods |
| Decorator | `Function.andThen()` chaining |
| Template Method | `default` interface methods |
| Builder | `record` + wither (small objects) |
| Singleton | Holder class hoặc `enum` |

**Tiếp theo:** `patterns/patterns_enterprise.md` — Repository, CQRS, Event Sourcing, Saga, Outbox, Circuit Breaker
