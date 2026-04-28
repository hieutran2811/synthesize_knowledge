# Lambda & Functional Interface (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Lambda & Functional Interface là gì?

**Functional Interface**: interface có **đúng 1 abstract method** (SAM – Single Abstract Method). Có thể có nhiều `default` và `static` method.

**Lambda Expression**: cú pháp ngắn gọn để tạo **instance của Functional Interface** — một anonymous function.

```java
// Anonymous class (trước Java 8)
Runnable r1 = new Runnable() {
    @Override
    public void run() { System.out.println("Running"); }
};

// Lambda (Java 8+)
Runnable r2 = () -> System.out.println("Running");
```

---

## How – Cú pháp Lambda

```java
// Dạng đầy đủ
(String a, String b) -> { return a.compareTo(b); }

// Infer type (compiler tự suy)
(a, b) -> { return a.compareTo(b); }

// Expression body (không cần return nếu chỉ 1 expression)
(a, b) -> a.compareTo(b)

// 1 parameter: không cần ngoặc
name -> name.toUpperCase()

// 0 parameter
() -> System.out.println("hello")

// Nhiều dòng: dùng block body
(x, y) -> {
    int sum = x + y;
    System.out.println("Sum: " + sum);
    return sum;
}
```

---

## How – Method References (4 loại)

Method reference = cú pháp ngắn hơn khi lambda chỉ gọi 1 method.

### 1. Static Method Reference: `ClassName::staticMethod`
```java
// Lambda
Function<String, Integer> parse = s -> Integer.parseInt(s);
// Method reference
Function<String, Integer> parse = Integer::parseInt;

// Lambda
Predicate<String> isEmpty = s -> s.isEmpty();
// Static nếu có: StringUtils::isEmpty hoặc dùng instance method reference
```

### 2. Instance Method của Particular Object: `instance::method`
```java
String prefix = "Hello, ";
Function<String, String> greet = name -> prefix.concat(name);
// Method reference
Function<String, String> greet = prefix::concat;

// Thường dùng với this:
public class Printer {
    private String format;
    public String formatMessage(String msg) { return format + msg; }

    public void printAll(List<String> messages) {
        messages.forEach(this::formatMessage); // instance::method
    }
}
```

### 3. Instance Method của Arbitrary Object of Type: `ClassName::instanceMethod`
```java
// Lambda: đối số đầu tiên là "receiver" của method
Function<String, String> upper = s -> s.toUpperCase();
// Method reference: compiler hiểu s là receiver
Function<String, String> upper = String::toUpperCase;

// BiFunction: s1 là receiver, s2 là argument
BiFunction<String, String, Boolean> startsWith = (s1, s2) -> s1.startsWith(s2);
BiFunction<String, String, Boolean> startsWith = String::startsWith;

// Comparator
Comparator<String> comp = (a, b) -> a.compareTo(b);
Comparator<String> comp = String::compareTo;
```

### 4. Constructor Reference: `ClassName::new`
```java
// Lambda
Supplier<ArrayList<String>> listFactory = () -> new ArrayList<>();
// Constructor reference
Supplier<ArrayList<String>> listFactory = ArrayList::new;

// Với argument
Function<String, StringBuilder> sbFactory = s -> new StringBuilder(s);
Function<String, StringBuilder> sbFactory = StringBuilder::new;

// Dùng trong stream
List<String> names = List.of("Alice", "Bob");
List<StringBuilder> sbs = names.stream()
    .map(StringBuilder::new)
    .collect(Collectors.toList());
```

---

## How – Built-in Functional Interfaces (java.util.function)

### Core 4

```java
// Supplier<T>: () → T  (không nhận, trả về T)
Supplier<List<String>> listSupplier = ArrayList::new;
Supplier<LocalDate> today = LocalDate::now;

// Consumer<T>: T → void  (nhận T, không trả)
Consumer<String> print = System.out::println;
Consumer<User> saveUser = repo::save;

// Function<T, R>: T → R  (transform)
Function<String, Integer> length = String::length;
Function<User, UserDto> toDto = UserDto::from;

// Predicate<T>: T → boolean  (test/filter)
Predicate<String> isBlank = String::isBlank;
Predicate<Integer> isPositive = n -> n > 0;
```

### Variants

| Interface | Signature | Ví dụ dùng |
|-----------|----------|-----------|
| `BiFunction<T,U,R>` | `(T,U) → R` | `(firstName, lastName) -> firstName + " " + lastName` |
| `BiConsumer<T,U>` | `(T,U) → void` | `map.forEach(BiConsumer)` |
| `BiPredicate<T,U>` | `(T,U) → boolean` | `String::startsWith` |
| `UnaryOperator<T>` | `T → T` | `String::toUpperCase` |
| `BinaryOperator<T>` | `(T,T) → T` | `Integer::sum`, `String::concat` |
| `IntSupplier` | `() → int` | tránh boxing |
| `IntFunction<R>` | `int → R` | `size -> new int[size]` |
| `ToIntFunction<T>` | `T → int` | `String::length` |

---

## How – Composing Functions

### Function Composition
```java
Function<String, String> trim = String::trim;
Function<String, String> upper = String::toUpperCase;
Function<String, Integer> length = String::length;

// andThen: f.andThen(g) = g(f(x))
Function<String, String> trimThenUpper = trim.andThen(upper);
trimThenUpper.apply("  hello  "); // "HELLO"

// compose: f.compose(g) = f(g(x)) (ngược với andThen)
Function<String, Integer> trimThenLength = length.compose(trim);
trimThenLength.apply("  hi  "); // 2
```

### Predicate Composition
```java
Predicate<String> notEmpty = s -> !s.isEmpty();
Predicate<String> notBlank = s -> !s.isBlank();
Predicate<String> longEnough = s -> s.length() >= 3;

// and, or, negate
Predicate<String> valid = notEmpty.and(notBlank).and(longEnough);
Predicate<String> invalid = valid.negate();
Predicate<String> emailOrPhone = isEmail.or(isPhone);

// Dùng với stream
users.stream()
    .filter(notEmpty.and(longEnough))
    .collect(Collectors.toList());
```

### Consumer Chaining
```java
Consumer<String> log = s -> System.out.println("LOG: " + s);
Consumer<String> audit = s -> auditService.record(s);
Consumer<String> notify = s -> notificationService.send(s);

// andThen: thực hiện tuần tự
Consumer<String> pipeline = log.andThen(audit).andThen(notify);
pipeline.accept("Order placed");
```

---

## How – Lambda vs Anonymous Class

| Khía cạnh | Lambda | Anonymous Class |
|----------|--------|----------------|
| Syntax | Ngắn gọn | Verbose |
| `this` | Refer đến **enclosing class** | Refer đến **anonymous class itself** |
| Scope | Không tạo scope mới | Tạo scope mới |
| Type | Functional Interface | Bất kỳ interface/class |
| Capture | Effectively final | Effectively final |
| State | Stateless (best practice) | Có thể có state |
| Compile | Invokedynamic | Bytecode class file |

```java
public class Outer {
    String name = "Outer";

    void demo() {
        // Anonymous class: this = anonymous instance
        Runnable anon = new Runnable() {
            String name = "Anonymous";
            @Override
            public void run() {
                System.out.println(this.name);    // "Anonymous"
                System.out.println(Outer.this.name); // "Outer"
            }
        };

        // Lambda: không có this riêng → this = Outer instance
        Runnable lambda = () -> {
            System.out.println(this.name); // "Outer"
            // Không có this.name của lambda riêng
        };
    }
}
```

---

## How – Closure & Effectively Final

Lambda có thể **capture** biến từ enclosing scope, nhưng biến đó phải **effectively final** (không được reassign sau khi khai báo):

```java
void example() {
    String prefix = "Hello"; // effectively final
    int count = 10;          // effectively final

    Function<String, String> greet = name -> prefix + ", " + name;
    // prefix = "Hi"; // LỖI! Phá vỡ effectively final, lambda bị invalid

    // Workaround với counter (dùng array hoặc AtomicInteger)
    int[] counter = {0}; // array là effectively final (reference), content thay đổi được
    Runnable r = () -> counter[0]++; // OK
    // Nhưng KHÔNG thread-safe!

    AtomicInteger atomicCounter = new AtomicInteger(0); // thread-safe
    Runnable safe = () -> atomicCounter.incrementAndGet();
}
```

**Tại sao cần effectively final?**
- Lambda có thể sống lâu hơn method stack frame
- Nếu biến thay đổi sau khi lambda được tạo → hành vi không xác định (giống bug trong closures của ngôn ngữ khác)
- Java chọn "effectively final" để tránh vấn đề này mà không cần từ khóa `final` tường minh

---

## How – Currying & Partial Application

```java
// Currying: biến đổi f(a,b) thành f(a)(b)
Function<Integer, Function<Integer, Integer>> add = a -> b -> a + b;
Function<Integer, Integer> add5 = add.apply(5);
int result = add5.apply(3); // 8

// Partial Application: cố định một số argument
BiFunction<String, Integer, String> repeat = (s, n) -> s.repeat(n);
Function<Integer, String> repeatHello = n -> repeat.apply("Hello", n);
repeatHello.apply(3); // "HelloHelloHello"

// Dùng trong pipeline
List<String> words = List.of("apple", "banana", "cherry");
words.stream()
    .map(add.apply("Fruit: ")::concat) // partial application
    .forEach(System.out::println);
```

---

## Why – Tại sao dùng Lambda & Functional Interface?

1. **Ngắn gọn**: giảm boilerplate của anonymous class
2. **Behavior as data**: truyền behavior như tham số (Strategy pattern đơn giản)
3. **Lazy evaluation**: lambda chỉ execute khi được gọi → tối ưu performance
4. **Composability**: tạo pipeline xử lý từ các function nhỏ
5. **Stream API**: nền tảng của toàn bộ Stream API

---

## When – Khi nào dùng lambda, khi nào dùng anonymous class?

| Tình huống | Dùng |
|-----------|------|
| Functional Interface, logic đơn giản | Lambda |
| Cần `this` refer đến instance của class | Anonymous class |
| Functional Interface, nhiều dòng | Lambda với block body |
| Non-functional interface (nhiều abstract method) | Anonymous class |
| Cần state nội bộ (field) | Anonymous class hoặc class riêng |
| Method reference đủ ngắn | Method reference |

---

## Real-world Usage (Production)

### 1. Event Handling (Spring)
```java
@EventListener
public Consumer<OrderCreatedEvent> handleOrderCreated() {
    return event -> {
        notificationService.notifyCustomer(event.getOrder());
        inventoryService.reserve(event.getOrder().getItems());
    };
}
```

### 2. Retry Logic với Function composition
```java
public class RetryPolicy {
    public static <T> Supplier<T> withRetry(Supplier<T> operation, int maxRetries) {
        return () -> {
            Exception lastException = null;
            for (int i = 0; i < maxRetries; i++) {
                try { return operation.get(); }
                catch (Exception e) { lastException = e; }
            }
            throw new RuntimeException("All retries failed", lastException);
        };
    }
}

Supplier<User> fetchUser = RetryPolicy.withRetry(
    () -> userService.findById(userId),
    3
);
User user = fetchUser.get();
```

### 3. Validation Chain
```java
public class Validator<T> {
    private final List<Predicate<T>> rules = new ArrayList<>();
    private final List<String> messages = new ArrayList<>();

    public Validator<T> addRule(Predicate<T> rule, String message) {
        rules.add(rule);
        messages.add(message);
        return this;
    }

    public List<String> validate(T value) {
        List<String> errors = new ArrayList<>();
        for (int i = 0; i < rules.size(); i++) {
            if (!rules.get(i).test(value)) errors.add(messages.get(i));
        }
        return errors;
    }
}

Validator<String> emailValidator = new Validator<String>()
    .addRule(s -> s != null, "Email must not be null")
    .addRule(s -> !s.isBlank(), "Email must not be blank")
    .addRule(s -> s.contains("@"), "Email must contain @")
    .addRule(s -> s.length() <= 255, "Email too long");

List<String> errors = emailValidator.validate("invalid-email");
```

### 4. Configuration với Consumer
```java
// Builder-like API sử dụng Consumer
public class HttpClientConfig {
    private int timeout = 30;
    private int maxConnections = 100;
    private boolean followRedirects = true;

    public static HttpClient create(Consumer<HttpClientConfig> configurer) {
        HttpClientConfig config = new HttpClientConfig();
        configurer.accept(config);
        return new HttpClient(config);
    }
}

HttpClient client = HttpClientConfig.create(config -> {
    config.timeout = 60;
    config.maxConnections = 200;
});
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Stream API** (deep dive)
>
> Keyword: Stream pipeline (source → intermediate → terminal), lazy evaluation cơ chế, short-circuit operations, stateful vs stateless intermediate ops, spliterator, parallel stream (ForkJoinPool, work stealing, splittability), Collectors (groupingBy, partitioningBy, teeing Java 12), Optional API, primitive streams (IntStream, LongStream, DoubleStream)
