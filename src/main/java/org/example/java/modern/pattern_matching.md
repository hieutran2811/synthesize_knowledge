# Pattern Matching (Java 16 → 21)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Pattern Matching là gì?

**Pattern Matching** cho phép kiểm tra cấu trúc của một giá trị và **extract** các thành phần từ nó trong một bước duy nhất — thay thế chuỗi `instanceof + cast + access`.

Java đã mở rộng dần qua nhiều phiên bản:

| Java | Tính năng |
|------|----------|
| 14 (preview) | Switch Expression (standard) |
| 16 | `instanceof` Pattern (standard) |
| 17 | Sealed Classes (standard) |
| 21 | Switch Pattern Matching (standard), Record Deconstruction, Guarded Patterns, Null in Switch |

---

## How – instanceof Pattern (Java 16)

### Trước Java 16
```java
Object obj = "Hello";

// 3 bước: test → cast → use
if (obj instanceof String) {
    String s = (String) obj; // explicit cast
    System.out.println(s.length());
}
```

### Java 16+: Pattern Variable
```java
// 1 bước: test + bind
if (obj instanceof String s) {
    System.out.println(s.length()); // s trong scope của if-block
}

// Kết hợp với điều kiện
if (obj instanceof String s && s.length() > 5) {
    System.out.println("Long string: " + s);
}

// Negation – s KHÔNG trong scope
if (!(obj instanceof String s)) {
    System.out.println("Not a string");
} else {
    System.out.println(s.toUpperCase()); // s có scope ở đây
}
```

### Scope của Pattern Variable
```java
// Scope flow-sensitive
Object o = ...;
if (o instanceof Integer i && i > 0) {
    // i trong scope (short-circuit: nếu instanceof false, i không được bind)
}

if (o instanceof Integer i || i > 0) { // COMPILE ERROR – i có thể không được bind
}

// Pattern variable che giấu field cùng tên
class Foo {
    String name = "field";
    void test(Object o) {
        if (o instanceof String name) {
            System.out.println(name); // pattern variable, không phải this.name!
        }
    }
}
```

---

## How – Switch Expression (Java 14 standard)

### Arrow syntax – không fall-through
```java
// Trước: switch statement có fall-through
int day = 3;
String name;
switch (day) {
    case 1: name = "Mon"; break;
    case 2: name = "Tue"; break;
    // quên break → fall-through!
    default: name = "Other";
}

// Java 14: switch expression với arrow
String name = switch (day) {
    case 1 -> "Mon";
    case 2 -> "Tue";
    case 3 -> "Wed";
    case 4, 5 -> "Thu or Fri"; // multiple labels
    default -> "Other";
};

// Với block body → dùng yield
int result = switch (day) {
    case 1, 7 -> 0; // weekend
    default -> {
        int workHours = calculateHours(day);
        yield workHours * 8; // yield thay vì return
    }
};
```

---

## How – Switch Pattern Matching (Java 21)

### Type Patterns trong Switch
```java
sealed interface Shape permits Circle, Rectangle, Triangle {}
record Circle(double radius) implements Shape {}
record Rectangle(double w, double h) implements Shape {}
record Triangle(double base, double height) implements Shape {}

// Switch với type patterns
double area(Shape shape) {
    return switch (shape) {
        case Circle c    -> Math.PI * c.radius() * c.radius();
        case Rectangle r -> r.w() * r.h();
        case Triangle t  -> 0.5 * t.base() * t.height();
        // Không cần default – sealed là exhaustive
    };
}

// Switch với non-sealed hierarchy – cần default
double describe(Object obj) {
    return switch (obj) {
        case Integer i -> i * 1.0;
        case Double d  -> d;
        case String s  -> Double.parseDouble(s);
        case null      -> 0.0;   // null handling (Java 21)
        default        -> throw new IllegalArgumentException("Unsupported: " + obj.getClass());
    };
}
```

### Guarded Patterns (when clause)
```java
String classify(Object obj) {
    return switch (obj) {
        case Integer i when i < 0   -> "Negative int";
        case Integer i when i == 0  -> "Zero";
        case Integer i              -> "Positive int: " + i;
        case String s when s.isEmpty() -> "Empty string";
        case String s               -> "String: " + s;
        case null                   -> "null";
        default                     -> "Other: " + obj.getClass().getSimpleName();
    };
}
```

### Ordering của Patterns
```java
// Patterns được match theo thứ tự TỪ TRÊN XUỐNG
// Specific phải đứng TRƯỚC general
switch (shape) {
    case Circle c when c.radius() > 100 -> "Giant";  // specific first
    case Circle c when c.radius() > 10  -> "Large";
    case Circle c                        -> "Small";  // general last
    case Rectangle r                     -> "Rect";
}

// COMPILE ERROR: dominance – general trước specific
switch (shape) {
    case Circle c        -> "Circle";     // catches all circles
    case Circle c when c.radius() > 10 -> "Large"; // unreachable! ERROR
}
```

---

## How – Record Deconstruction Pattern (Java 21)

```java
record Point(int x, int y) {}
record Line(Point start, Point end) {}

Object obj = new Point(3, 4);

// Record deconstruction: extract components trực tiếp
if (obj instanceof Point(int x, int y)) {
    System.out.println("x=" + x + ", y=" + y); // x, y bound trực tiếp
}

// Trong switch
String describe(Object obj) {
    return switch (obj) {
        case Point(int x, int y) when x == 0 && y == 0 -> "Origin";
        case Point(int x, int y) when x == 0           -> "Y-axis, y=" + y;
        case Point(int x, int y) when y == 0            -> "X-axis, x=" + x;
        case Point(int x, int y)                        -> "Point(" + x + "," + y + ")";
        default -> "Unknown";
    };
}

// Nested deconstruction
String describeLine(Object obj) {
    return switch (obj) {
        case Line(Point(int x1, int y1), Point(int x2, int y2)) ->
            "Line from (" + x1 + "," + y1 + ") to (" + x2 + "," + y2 + ")";
        default -> "Not a line";
    };
}
```

### Deconstruction với var
```java
// var để tránh lặp type
switch (shape) {
    case Circle(var r)       -> Math.PI * r * r;
    case Rectangle(var w, var h) -> w * h;
}
```

---

## How – Null Handling trong Switch (Java 21)

Trước Java 21: switch với null → `NullPointerException`.

```java
// Trước Java 21:
String process(String s) {
    if (s == null) return "null";
    return switch (s) { // NullPointerException nếu s=null!
        case "hello" -> "greeting";
        default -> "other";
    };
}

// Java 21: null case trong switch
String process(String s) {
    return switch (s) {
        case null    -> "null";      // handle null tường minh
        case "hello" -> "greeting";
        default      -> "other";
    };
}

// null + default cùng case
return switch (s) {
    case null, "UNKNOWN" -> "missing";
    default -> s.toUpperCase();
};
```

---

## How – Unnamed Pattern `_` (Java 22 preview)

```java
// Khi không cần binding variable, dùng _ (unnamed)
switch (shape) {
    case Circle _    -> "It's a circle";
    case Rectangle _ -> "It's a rectangle";
}

// Deconstruction: bỏ qua một số components
switch (point) {
    case Point(_, int y) when y > 0 -> "Above x-axis"; // x không cần
    case Point(int x, _) when x > 0 -> "Right of y-axis";
    default -> "Other";
}
```

---

## Components – Pattern Types Tóm tắt

| Pattern | Syntax | Mô tả |
|---------|--------|-------|
| Type pattern | `case Integer i` | Test type + bind |
| Guarded pattern | `case Integer i when i > 0` | Type + điều kiện |
| Record deconstruction | `case Point(int x, int y)` | Unpack record |
| Nested deconstruction | `case Line(Point(int x, _), _)` | Unpack nested |
| Null pattern | `case null` | Handle null |
| Unnamed pattern | `case Circle _` | Match không bind |

---

## Why – Tại sao Pattern Matching quan trọng?

**Trước:**
```java
// Verbose, dễ quên cast hoặc null check
void process(Object obj) {
    if (obj instanceof String) {
        String s = (String) obj;
        if (s.length() > 5) { doSomething(s); }
    } else if (obj instanceof Integer) {
        Integer i = (Integer) obj;
        if (i > 0) { doSomethingElse(i); }
    } else if (obj == null) { handleNull(); }
    else { handleOther(); }
}
```

**Sau:**
```java
void process(Object obj) {
    switch (obj) {
        case String s when s.length() > 5  -> doSomething(s);
        case String s                       -> doShort(s);
        case Integer i when i > 0           -> doSomethingElse(i);
        case null                           -> handleNull();
        default                             -> handleOther();
    }
}
```

Lợi ích:
1. **Ít code hơn, ít lỗi hơn** (không quên cast, null check)
2. **Exhaustiveness** với sealed → compiler check
3. **Deconstruction** lấy data trực tiếp, không qua getter
4. **Readable** hơn if-else chain

---

## When – Khi nào dùng Pattern Matching?

| Tình huống | Giải pháp |
|-----------|----------|
| Xử lý nhiều kiểu object khác nhau | Switch pattern |
| Domain model có hierarchy rõ ràng | Sealed + switch |
| Extract data từ record/object | Deconstruction |
| Validate + access cùng lúc | Guarded pattern |
| Thay thế Visitor Pattern | Switch expression |
| AST traversal | Nested deconstruction |

---

## Compare – Pattern Matching vs Visitor Pattern

```java
// Visitor Pattern (truyền thống)
interface ShapeVisitor<T> {
    T visitCircle(Circle c);
    T visitRectangle(Rectangle r);
}
class AreaCalculator implements ShapeVisitor<Double> {
    public Double visitCircle(Circle c) { return Math.PI * c.radius() * c.radius(); }
    public Double visitRectangle(Rectangle r) { return r.w() * r.h(); }
}

// Pattern Matching (modern)
double area(Shape shape) {
    return switch (shape) {
        case Circle c    -> Math.PI * c.radius() * c.radius();
        case Rectangle r -> r.w() * r.h();
    };
}
```

| | Visitor Pattern | Pattern Matching |
|--|----------------|-----------------|
| Thêm operation | Thêm Visitor class | Thêm method |
| Thêm subtype | Sửa mọi Visitor | Compiler báo lỗi (sealed) |
| Code | Nhiều boilerplate | Ngắn gọn |
| Type safety | Có | Có (+ compiler check) |
| Nested structure | Phức tạp | Elegant |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Ngắn gọn, ít cast | Yêu cầu Java 21+ cho đầy đủ tính năng |
| Compiler exhaustiveness check | Không quen với OOP thuần túy |
| Deconstruction tiện lợi | Guard conditions có thể phức tạp |
| Null safety tường minh | Learning curve nếu migrate codebase cũ |

---

## Real-world Usage (Production)

### 1. Domain Event Processing
```java
sealed interface DomainEvent permits UserRegistered, OrderPlaced, PaymentProcessed {}
record UserRegistered(String userId, String email) implements DomainEvent {}
record OrderPlaced(String orderId, String userId, BigDecimal amount) implements DomainEvent {}
record PaymentProcessed(String paymentId, String orderId, boolean success) implements DomainEvent {}

@EventListener
void handleEvent(DomainEvent event) {
    switch (event) {
        case UserRegistered(var id, var email) -> {
            emailService.sendWelcome(email);
            analyticsService.trackRegistration(id);
        }
        case OrderPlaced(var orderId, var userId, var amount) when amount.compareTo(BigDecimal.valueOf(1000)) > 0 -> {
            notificationService.alertHighValueOrder(orderId, amount);
            orderService.process(orderId);
        }
        case OrderPlaced(var orderId, _, _) -> orderService.process(orderId);
        case PaymentProcessed(_, var orderId, true) -> orderService.confirm(orderId);
        case PaymentProcessed(var paymentId, var orderId, false) -> {
            orderService.cancel(orderId, "Payment failed");
            paymentService.refund(paymentId);
        }
    }
}
```

### 2. JSON/Config Parsing
```java
sealed interface JsonValue permits JsonObject, JsonArray, JsonString, JsonNumber, JsonBool, JsonNull {}
record JsonObject(Map<String, JsonValue> fields) implements JsonValue {}
record JsonArray(List<JsonValue> elements) implements JsonValue {}
record JsonString(String value) implements JsonValue {}
record JsonNumber(double value) implements JsonValue {}
record JsonBool(boolean value) implements JsonValue {}
record JsonNull() implements JsonValue {}

String toJavaString(JsonValue json) {
    return switch (json) {
        case JsonString(var s) -> "\"" + s + "\"";
        case JsonNumber(var n) -> n % 1 == 0 ? String.valueOf((long)n) : String.valueOf(n);
        case JsonBool(var b)   -> String.valueOf(b);
        case JsonNull ignored  -> "null";
        case JsonArray(var els) ->
            "[" + els.stream().map(this::toJavaString).collect(joining(", ")) + "]";
        case JsonObject(var fields) ->
            "{" + fields.entrySet().stream()
                .map(e -> "\"" + e.getKey() + "\": " + toJavaString(e.getValue()))
                .collect(joining(", ")) + "}";
    };
}
```

### 3. Error Handling Pipeline
```java
sealed interface AppError permits NotFoundError, ValidationError, AuthError, SystemError {}
record NotFoundError(String resource, String id) implements AppError {}
record ValidationError(Map<String, String> violations) implements AppError {}
record AuthError(String message) implements AppError {}
record SystemError(String message, Throwable cause) implements AppError {}

ResponseEntity<?> toHttpResponse(AppError error) {
    return switch (error) {
        case NotFoundError(var res, var id) ->
            ResponseEntity.status(404).body(Map.of("error", res + " not found: " + id));
        case ValidationError(var violations) ->
            ResponseEntity.status(400).body(Map.of("violations", violations));
        case AuthError(var msg) ->
            ResponseEntity.status(401).body(Map.of("error", msg));
        case SystemError(var msg, _) -> {
            log.error("System error: {}", msg, error.cause());
            yield ResponseEntity.status(500).body(Map.of("error", "Internal server error"));
        }
    };
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Virtual Threads (Java 21 – Project Loom)**
>
> Keyword: Platform thread vs Virtual thread, carrier thread, continuation, ForkJoinPool scheduler, thread-per-request vs reactive, structured concurrency (`StructuredTaskScope`), pinning (synchronized block trong virtual thread), `Thread.ofVirtual()`, `Executors.newVirtualThreadPerTaskExecutor()`
