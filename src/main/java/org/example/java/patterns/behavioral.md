# Design Patterns – Behavioral (Hành vi)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Behavioral Patterns là gì?

**Behavioral Patterns** tập trung vào **giao tiếp và phân công trách nhiệm** giữa các object — "ai làm gì và ai nói chuyện với ai".

**9 Behavioral Patterns (GoF):**
1. Strategy – hoán đổi algorithm
2. Observer – sự kiện/thông báo
3. Template Method – skeleton algorithm
4. Command – request thành object
5. Chain of Responsibility – chuỗi handler
6. State – FSM (máy trạng thái)
7. Visitor – thêm operation không sửa class
8. Mediator – trung gian giảm coupling
9. Iterator – duyệt collection

---

## 1. Strategy

### What
Định nghĩa họ algorithm, đóng gói từng cái, và cho phép hoán đổi nhau. Client chọn algorithm tại runtime mà không thay đổi code sử dụng.

### How

```java
// Strategy interface
@FunctionalInterface
public interface SortStrategy<T> {
    void sort(List<T> data);
}

// Concrete strategies
public class BubbleSortStrategy<T extends Comparable<T>> implements SortStrategy<T> {
    @Override
    public void sort(List<T> data) {
        int n = data.size();
        for (int i = 0; i < n - 1; i++)
            for (int j = 0; j < n - i - 1; j++)
                if (data.get(j).compareTo(data.get(j+1)) > 0)
                    Collections.swap(data, j, j+1);
    }
}

public class QuickSortStrategy<T extends Comparable<T>> implements SortStrategy<T> {
    @Override
    public void sort(List<T> data) {
        Collections.sort(data); // simplified
    }
}

// Context
public class DataSorter<T> {
    private SortStrategy<T> strategy;

    public DataSorter(SortStrategy<T> strategy) { this.strategy = strategy; }

    // Swap strategy tại runtime
    public void setStrategy(SortStrategy<T> strategy) { this.strategy = strategy; }

    public void sort(List<T> data) { strategy.sort(data); }
}

// Dùng
DataSorter<Integer> sorter = new DataSorter<>(new BubbleSortStrategy<>());
sorter.sort(smallData); // bubble sort

sorter.setStrategy(new QuickSortStrategy<>());
sorter.sort(largeData); // quick sort

// Với lambda (vì @FunctionalInterface):
sorter.setStrategy(list -> list.sort(Comparator.reverseOrder()));
```

### Real-world
- `Comparator` – Strategy cho sorting
- Spring Security: `AuthenticationStrategy`, `AccessDecisionStrategy`
- Spring MVC: `HandlerMapping` (nhiều strategy chọn handler)
- Payment processing: `PaymentStrategy` (thẻ, PayPal, crypto)

---

## 2. Observer

### What
Định nghĩa quan hệ **1-nhiều** giữa objects: khi Subject thay đổi state, tất cả Observer được thông báo và tự động cập nhật.

### How

```java
// Observer interface
public interface OrderObserver {
    void onOrderCreated(Order order);
    void onOrderShipped(Order order);
    void onOrderCancelled(Order order);
}

// Subject (Observable)
public class Order {
    private final Long id;
    private OrderStatus status;
    private final List<OrderObserver> observers = new CopyOnWriteArrayList<>();

    public void addObserver(OrderObserver observer) { observers.add(observer); }
    public void removeObserver(OrderObserver observer) { observers.remove(observer); }

    public void confirm() {
        this.status = OrderStatus.CONFIRMED;
        notifyCreated();
    }

    public void ship(String trackingNumber) {
        this.status = OrderStatus.SHIPPED;
        notifyShipped();
    }

    private void notifyCreated() {
        observers.forEach(o -> o.onOrderCreated(this));
    }
    private void notifyShipped() {
        observers.forEach(o -> o.onOrderShipped(this));
    }
}

// Concrete Observers
public class EmailNotificationObserver implements OrderObserver {
    @Override
    public void onOrderCreated(Order order) { emailService.sendConfirmation(order); }
    @Override
    public void onOrderShipped(Order order) { emailService.sendShippingUpdate(order); }
    @Override
    public void onOrderCancelled(Order order) { emailService.sendCancellation(order); }
}

public class InventoryObserver implements OrderObserver {
    @Override
    public void onOrderCreated(Order order) { inventory.reserve(order.getItems()); }
    @Override
    public void onOrderShipped(Order order) { inventory.deduct(order.getItems()); }
    @Override
    public void onOrderCancelled(Order order) { inventory.release(order.getItems()); }
}

// Dùng
Order order = new Order(id, items);
order.addObserver(new EmailNotificationObserver());
order.addObserver(new InventoryObserver());
order.addObserver(new AnalyticsObserver());
order.confirm(); // triggers all observers
```

### Push vs Pull Model

**Push**: Subject đẩy data vào Observer (ví dụ trên)
- Ưu: Observer không cần biết Subject
- Nhược: Subject biết Observer cần gì

**Pull**: Subject chỉ notify, Observer tự lấy data
```java
interface Observer { void update(Observable source); }
class ConcreteObserver implements Observer {
    public void update(Observable source) {
        Order order = (Order) source; // phải cast
        process(order.getStatus()); // tự pull data
    }
}
```

### Modern: Spring ApplicationEvent
```java
// Spring Event (built-in Observer)
public record OrderCreatedEvent(Order order) {}

@Service
public class OrderService {
    private final ApplicationEventPublisher publisher;

    public Order createOrder(CreateOrderRequest req) {
        Order order = orderRepo.save(Order.create(req));
        publisher.publishEvent(new OrderCreatedEvent(order)); // notify
        return order;
    }
}

@EventListener
@Async // xử lý bất đồng bộ
public void handleOrderCreated(OrderCreatedEvent event) {
    emailService.sendConfirmation(event.order());
}

@EventListener
@TransactionalEventListener(phase = AFTER_COMMIT)
public void updateInventory(OrderCreatedEvent event) {
    inventoryService.reserve(event.order());
}
```

---

## 3. Template Method

### What
Định nghĩa **skeleton của một algorithm** trong superclass, để subclass override các bước cụ thể mà không thay đổi cấu trúc tổng thể.

### How

```java
public abstract class ReportGenerator {

    // Template method – FINAL: không cho override structure
    public final Report generate(ReportRequest request) {
        validateRequest(request);          // concrete – dùng chung
        List<Object> data = fetchData(request);  // abstract
        List<Object> processed = processData(data); // abstract
        Report report = formatReport(processed);     // abstract
        postProcess(report);               // hook – optional override
        return report;
    }

    // Concrete step – chung cho tất cả
    private void validateRequest(ReportRequest request) {
        Objects.requireNonNull(request.getStartDate());
        Objects.requireNonNull(request.getEndDate());
    }

    // Abstract steps – subclass phải implement
    protected abstract List<Object> fetchData(ReportRequest request);
    protected abstract List<Object> processData(List<Object> rawData);
    protected abstract Report formatReport(List<Object> data);

    // Hook – subclass có thể override nếu cần, mặc định không làm gì
    protected void postProcess(Report report) { }
}

// Concrete implementations
public class SalesReportGenerator extends ReportGenerator {
    @Override
    protected List<Object> fetchData(ReportRequest req) {
        return salesRepo.findByDateRange(req.getStartDate(), req.getEndDate());
    }
    @Override
    protected List<Object> processData(List<Object> data) {
        return aggregateByProduct(data);
    }
    @Override
    protected Report formatReport(List<Object> data) {
        return new SalesReport(data);
    }
    @Override
    protected void postProcess(Report report) {
        cacheService.cache("sales-report", report); // override hook
    }
}

public class InventoryReportGenerator extends ReportGenerator {
    @Override
    protected List<Object> fetchData(ReportRequest req) {
        return inventoryRepo.findLowStock();
    }
    @Override
    protected List<Object> processData(List<Object> data) {
        return sortByStockLevel(data);
    }
    @Override
    protected Report formatReport(List<Object> data) {
        return new InventoryReport(data);
    }
    // postProcess không override – dùng mặc định (no-op)
}
```

### Real-world
- Spring `JdbcTemplate`: execute (template) → callback (concrete step)
- `AbstractList`, `AbstractMap`: implements common ops, delegate primitives
- `HttpServlet.service()` → `doGet()`, `doPost()`, `doPut()`
- JUnit: test lifecycle (`@BeforeEach`, test, `@AfterEach`)

---

## 4. Command

### What
Đóng gói một **request** thành object — cho phép parameterize methods với requests, queue/log requests, và hỗ trợ undo.

### How

```java
// Command interface
public interface Command {
    void execute();
    void undo();
}

// Receiver
public class TextEditor {
    private StringBuilder text = new StringBuilder();
    private int cursorPos = 0;

    public void insertText(String str, int pos) {
        text.insert(pos, str);
        cursorPos = pos + str.length();
    }
    public void deleteText(int pos, int length) {
        text.delete(pos, pos + length);
        cursorPos = pos;
    }
    public String getText() { return text.toString(); }
}

// Concrete Commands
public class InsertCommand implements Command {
    private final TextEditor editor;
    private final String text;
    private final int position;

    public InsertCommand(TextEditor editor, String text, int position) {
        this.editor = editor; this.text = text; this.position = position;
    }
    @Override public void execute() { editor.insertText(text, position); }
    @Override public void undo()    { editor.deleteText(position, text.length()); }
}

// Invoker với Undo/Redo stack
public class CommandHistory {
    private final Deque<Command> history = new ArrayDeque<>();
    private final Deque<Command> redoStack = new ArrayDeque<>();

    public void execute(Command cmd) {
        cmd.execute();
        history.push(cmd);
        redoStack.clear(); // clear redo khi có action mới
    }

    public void undo() {
        if (!history.isEmpty()) {
            Command cmd = history.pop();
            cmd.undo();
            redoStack.push(cmd);
        }
    }

    public void redo() {
        if (!redoStack.isEmpty()) {
            Command cmd = redoStack.pop();
            cmd.execute();
            history.push(cmd);
        }
    }
}

// Dùng
TextEditor editor = new TextEditor();
CommandHistory history = new CommandHistory();

history.execute(new InsertCommand(editor, "Hello", 0));
history.execute(new InsertCommand(editor, " World", 5));
System.out.println(editor.getText()); // "Hello World"

history.undo();
System.out.println(editor.getText()); // "Hello"

history.redo();
System.out.println(editor.getText()); // "Hello World"
```

### Real-world
- Java `Runnable` – command pattern đơn giản
- Spring `@Transactional` – execute command trong transaction, rollback = undo
- CQRS (Command Query Responsibility Segregation)
- Job queues: `RabbitMQ`, `Kafka` message = Command
- Database migrations (Flyway, Liquibase): migration = Command

---

## 5. Chain of Responsibility

### What
Tạo chuỗi handlers. Request được truyền dọc chuỗi cho đến khi một handler xử lý nó — hoặc tất cả đều xử lý.

### How

```java
// Handler interface
public abstract class RequestHandler {
    protected RequestHandler next;

    public RequestHandler setNext(RequestHandler handler) {
        this.next = handler;
        return handler; // fluent chaining
    }

    public abstract void handle(HttpRequest request);

    protected void passToNext(HttpRequest request) {
        if (next != null) next.handle(request);
    }
}

// Concrete handlers
public class AuthenticationHandler extends RequestHandler {
    @Override
    public void handle(HttpRequest request) {
        String token = request.getHeader("Authorization");
        if (token == null || !tokenService.isValid(token)) {
            throw new UnauthorizedException("Invalid token");
        }
        request.setUser(tokenService.extractUser(token));
        passToNext(request); // authenticated → next handler
    }
}

public class AuthorizationHandler extends RequestHandler {
    @Override
    public void handle(HttpRequest request) {
        if (!request.getUser().hasRole(request.getRequiredRole())) {
            throw new ForbiddenException("Insufficient permissions");
        }
        passToNext(request);
    }
}

public class RateLimitHandler extends RequestHandler {
    @Override
    public void handle(HttpRequest request) {
        String userId = request.getUser().getId();
        if (rateLimiter.isExceeded(userId)) {
            throw new TooManyRequestsException("Rate limit exceeded");
        }
        rateLimiter.increment(userId);
        passToNext(request);
    }
}

public class LoggingHandler extends RequestHandler {
    @Override
    public void handle(HttpRequest request) {
        log.info("Request: {} {}", request.getMethod(), request.getPath());
        passToNext(request);
        log.info("Response: {}", request.getResponseStatus());
    }
}

// Setup chain
RequestHandler chain = new AuthenticationHandler();
chain.setNext(new AuthorizationHandler())
     .setNext(new RateLimitHandler())
     .setNext(new LoggingHandler());

chain.handle(request);
```

### Real-world
- Java Servlet `FilterChain` – `doFilter()` truyền request qua chain
- Spring Security Filter Chain
- Spring MVC Interceptors
- Logging framework: Logger → Handler → Appender

---

## 6. State

### What
Cho phép object thay đổi **hành vi** khi **state** thay đổi — giống như object thay đổi class.

**Giải quyết**: Thay thế if/switch khổng lồ kiểm tra state bằng State objects.

### How

```java
// State interface
public interface OrderState {
    void confirm(Order order);
    void ship(Order order);
    void deliver(Order order);
    void cancel(Order order);
    String getStateName();
}

// Concrete States
public class PendingState implements OrderState {
    @Override public void confirm(Order order) {
        order.setState(new ConfirmedState());
        order.notifyObservers("Order confirmed");
    }
    @Override public void ship(Order order) {
        throw new IllegalStateException("Cannot ship pending order");
    }
    @Override public void deliver(Order order) {
        throw new IllegalStateException("Cannot deliver pending order");
    }
    @Override public void cancel(Order order) {
        order.setState(new CancelledState());
    }
    @Override public String getStateName() { return "PENDING"; }
}

public class ConfirmedState implements OrderState {
    @Override public void confirm(Order order) {
        throw new IllegalStateException("Order already confirmed");
    }
    @Override public void ship(Order order) {
        order.setState(new ShippedState());
        order.notifyObservers("Order shipped");
    }
    @Override public void deliver(Order order) {
        throw new IllegalStateException("Cannot deliver unshipped order");
    }
    @Override public void cancel(Order order) {
        order.setState(new CancelledState());
        order.refund();
    }
    @Override public String getStateName() { return "CONFIRMED"; }
}

// Context
public class Order {
    private OrderState state = new PendingState(); // initial state
    private Long id;

    public void setState(OrderState state) { this.state = state; }

    // Delegate tất cả actions cho state
    public void confirm() { state.confirm(this); }
    public void ship()    { state.ship(this); }
    public void deliver() { state.deliver(this); }
    public void cancel()  { state.cancel(this); }

    public String getStatus() { return state.getStateName(); }
}

// Dùng
Order order = new Order(id, items);
System.out.println(order.getStatus()); // PENDING
order.confirm();
System.out.println(order.getStatus()); // CONFIRMED
order.ship();
System.out.println(order.getStatus()); // SHIPPED
// order.confirm(); // throws IllegalStateException
```

### Real-world
- Spring `AbstractStateMachine` (Spring State Machine)
- Thread states (NEW, RUNNABLE, BLOCKED, TERMINATED)
- HTTP Connection: Connecting → Connected → Disconnected
- Circuit Breaker (Resilience4j): CLOSED → OPEN → HALF_OPEN

---

## 7. Visitor

### What
Tách **operation** khỏi **object structure**. Thêm operation mới mà không sửa class của element.

**Double dispatch**: method được gọi phụ thuộc cả element type lẫn visitor type.

### How

```java
// Element interface
public interface Expression {
    <T> T accept(ExpressionVisitor<T> visitor);
}

// Concrete Elements
public record NumberLiteral(double value) implements Expression {
    public <T> T accept(ExpressionVisitor<T> visitor) {
        return visitor.visitNumber(this);
    }
}
public record Addition(Expression left, Expression right) implements Expression {
    public <T> T accept(ExpressionVisitor<T> visitor) {
        return visitor.visitAddition(this);
    }
}
public record Multiplication(Expression left, Expression right) implements Expression {
    public <T> T accept(ExpressionVisitor<T> visitor) {
        return visitor.visitMultiplication(this);
    }
}

// Visitor interface – 1 method cho mỗi element type
public interface ExpressionVisitor<T> {
    T visitNumber(NumberLiteral number);
    T visitAddition(Addition add);
    T visitMultiplication(Multiplication mul);
}

// Concrete Visitors – thêm operation mà không sửa Expression classes
public class EvaluateVisitor implements ExpressionVisitor<Double> {
    @Override public Double visitNumber(NumberLiteral n) { return n.value(); }
    @Override public Double visitAddition(Addition a) {
        return a.left().accept(this) + a.right().accept(this);
    }
    @Override public Double visitMultiplication(Multiplication m) {
        return m.left().accept(this) * m.right().accept(this);
    }
}

public class PrintVisitor implements ExpressionVisitor<String> {
    @Override public String visitNumber(NumberLiteral n) { return String.valueOf(n.value()); }
    @Override public String visitAddition(Addition a) {
        return "(" + a.left().accept(this) + " + " + a.right().accept(this) + ")";
    }
    @Override public String visitMultiplication(Multiplication m) {
        return "(" + m.left().accept(this) + " * " + m.right().accept(this) + ")";
    }
}

// (2 + 3) * 4
Expression expr = new Multiplication(
    new Addition(new NumberLiteral(2), new NumberLiteral(3)),
    new NumberLiteral(4)
);

System.out.println(expr.accept(new PrintVisitor()));    // ((2.0 + 3.0) * 4.0)
System.out.println(expr.accept(new EvaluateVisitor())); // 20.0
// Thêm operation mới: chỉ tạo Visitor mới, không sửa Expression!
```

### Real-world
- Java Compiler AST traversal
- Jackson: `JsonNode.accept(JsonNodeVisitor)`
- Spring: `BeanDefinitionVisitor`
- IDE refactoring tools

---

## 8. Mediator

### What
Giảm dependencies hỗn loạn giữa nhiều objects bằng cách buộc chúng giao tiếp **qua mediator** thay vì trực tiếp.

```
Không có Mediator: A ↔ B ↔ C ↔ D (mesh, n*(n-1)/2 connections)
Với Mediator:      A → M ← B (hub, n connections)
                       ↕
                   C → M ← D
```

### How

```java
// Mediator interface
public interface ChatMediator {
    void sendMessage(String message, User sender);
    void addUser(User user);
}

// Participant
public abstract class User {
    protected final ChatMediator mediator;
    protected final String name;

    public User(ChatMediator mediator, String name) {
        this.mediator = mediator;
        this.name = name;
    }

    public abstract void send(String message);
    public abstract void receive(String message, String from);
}

// Concrete Mediator
public class ChatRoom implements ChatMediator {
    private final List<User> users = new ArrayList<>();

    @Override
    public void addUser(User user) { users.add(user); }

    @Override
    public void sendMessage(String message, User sender) {
        users.stream()
            .filter(u -> u != sender) // broadcast trừ sender
            .forEach(u -> u.receive(message, sender.name));
    }
}

// Concrete Participant
public class ChatUser extends User {
    public ChatUser(ChatMediator mediator, String name) { super(mediator, name); }

    @Override
    public void send(String message) {
        System.out.println(name + " sends: " + message);
        mediator.sendMessage(message, this); // thông qua mediator
    }

    @Override
    public void receive(String message, String from) {
        System.out.println(name + " received from " + from + ": " + message);
    }
}

// Dùng
ChatMediator room = new ChatRoom();
User alice = new ChatUser(room, "Alice");
User bob = new ChatUser(room, "Bob");
User charlie = new ChatUser(room, "Charlie");
room.addUser(alice); room.addUser(bob); room.addUser(charlie);

alice.send("Hello everyone!");
// Bob received from Alice: Hello everyone!
// Charlie received from Alice: Hello everyone!
```

### Real-world
- Spring `ApplicationEventPublisher` – mediator giữa components
- MVC Controller – mediator giữa Model và View
- Air Traffic Control – tất cả máy bay liên lạc qua ATC
- Chat server, Message Broker (RabbitMQ, Kafka)

---

## 9. Iterator

### What
Cung cấp cách **duyệt qua** các phần tử của collection mà không expose cấu trúc nội bộ.

### How

```java
// Java built-in Iterator
public interface Iterator<T> {
    boolean hasNext();
    T next();
    default void remove() { throw new UnsupportedOperationException(); }
}

// Custom Iterable
public class NumberRange implements Iterable<Integer> {
    private final int start, end, step;

    public NumberRange(int start, int end, int step) {
        this.start = start; this.end = end; this.step = step;
    }

    @Override
    public Iterator<Integer> iterator() {
        return new Iterator<>() {
            private int current = start;

            @Override
            public boolean hasNext() { return current <= end; }

            @Override
            public Integer next() {
                if (!hasNext()) throw new NoSuchElementException();
                int val = current;
                current += step;
                return val;
            }
        };
    }
}

// Dùng
for (int n : new NumberRange(0, 10, 2)) {
    System.out.print(n + " "); // 0 2 4 6 8 10
}

// Modern: Stream thay thế nhiều Iterator use case
IntStream.iterate(0, n -> n <= 10, n -> n + 2).forEach(System.out::println);
```

---

## Compare – Behavioral Patterns

| Pattern | Giải quyết | Keyword |
|---------|-----------|---------|
| Strategy | Hoán đổi algorithm | "Chọn algorithm tại runtime" |
| Observer | Thông báo thay đổi | "1 → nhiều, sự kiện" |
| Template Method | Skeleton + hooks | "Subclass điền bước cụ thể" |
| Command | Request = object | "Queue, undo, log request" |
| Chain of Responsibility | Pipeline handler | "Handler chain, filter" |
| State | Behavior theo state | "FSM, trạng thái" |
| Visitor | Thêm operation | "Double dispatch, AST" |
| Mediator | Giảm coupling | "Hub, broadcast" |
| Iterator | Duyệt collection | "Encapsulate traversal" |

---

## Real-world Production Summary

```java
// Strategy: Spring Validator
@Component
public class OrderValidator implements Validator {
    @Override public boolean supports(Class<?> clazz) { return Order.class.isAssignableFrom(clazz); }
    @Override public void validate(Object target, Errors errors) {
        Order order = (Order) target;
        if (order.getItems().isEmpty()) errors.reject("items", "Order must have items");
    }
}

// Observer: Spring Event
publisher.publishEvent(new OrderShippedEvent(order));

// Template Method: Spring Batch ItemProcessor
public abstract class BaseItemProcessor<I, O> implements ItemProcessor<I, O> {
    @Override public final O process(I item) {
        validate(item); O result = doProcess(item); postProcess(result); return result;
    }
    protected abstract void validate(I item);
    protected abstract O doProcess(I item);
    protected void postProcess(O result) {} // hook
}

// Chain of Responsibility: Spring Security Filter
http.addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);

// State: Resilience4j Circuit Breaker
CircuitBreaker cb = CircuitBreaker.ofDefaults("payment");
// States: CLOSED → OPEN → HALF_OPEN → CLOSED
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **JVM Internals – ClassLoader** & **JIT Compiler**
>
> Keyword: Bootstrap/Platform/Application ClassLoader, parent delegation model, class loading phases (Loading, Linking: verify+prepare+resolve, Initialization), ClassLoader isolation, OSGi, hot reload, custom ClassLoader. JIT: interpreted vs compiled, tiered compilation (C1/C2), JVM flags, inlining, escape analysis, loop unrolling, GraalVM
