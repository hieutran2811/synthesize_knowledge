# Sealed Classes & Interfaces (Java 17)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Sealed Class là gì?

**Sealed class/interface** (Java 17, preview Java 15–16) là class/interface **giới hạn tập subtype được phép**.

Thay vì ai cũng có thể extends/implements → bạn kiểm soát chính xác ai được phép.

```java
// Sealed: chỉ Circle, Rectangle, Triangle được phép implement
public sealed interface Shape permits Circle, Rectangle, Triangle {}

// Subtype PHẢI là một trong: final, sealed, non-sealed
public record Circle(double radius) implements Shape {}           // final (record ngầm là final)
public record Rectangle(double width, double height) implements Shape {}
public record Triangle(double base, double height) implements Shape {}
```

---

## How – 3 từ khóa

### `sealed` – class/interface giới hạn subtype
```java
// Sealed class
public sealed class Vehicle permits Car, Truck, Motorcycle {}

// Sealed interface
public sealed interface Result<T> permits Result.Success, Result.Failure {}
```

### `permits` – danh sách subtype được phép
```java
// Subtype phải nằm trong cùng module (Java 9+) hoặc cùng package
// Nếu subtype nằm cùng file → có thể bỏ qua permits (compiler tự infer)
public sealed class Expr {
    // Subtype ở cùng file → không cần permits
    record Num(double value) extends Expr {}
    record Add(Expr left, Expr right) extends Expr {}
    record Mul(Expr left, Expr right) extends Expr {}
}
```

### Subtype phải chọn 1 trong 3
```java
public sealed class Animal permits Dog, Cat, ExoticAnimal {}

// 1. final – không có subtype nào thêm được
public final class Dog extends Animal {}

// 2. sealed – tiếp tục giới hạn subtype
public sealed class Cat extends Animal permits PersianCat, SiameseCat {}
public final class PersianCat extends Cat {}
public final class SiameseCat extends Cat {}

// 3. non-sealed – mở lại hoàn toàn (bất kỳ ai có thể extends)
public non-sealed class ExoticAnimal extends Animal {}
public class Lizard extends ExoticAnimal {}  // OK
public class Parrot extends ExoticAnimal {}  // OK
```

---

## How – Algebraic Data Types (ADT)

Sealed classes + Records = **Algebraic Data Types** trong Java — đặc biệt là **Sum Type** (A hoặc B hoặc C):

```java
// Result type: Success hoặc Failure
public sealed interface Result<T> permits Result.Success, Result.Failure {

    record Success<T>(T value) implements Result<T> {}
    record Failure<T>(String errorCode, String message, Throwable cause) implements Result<T> {
        public Failure(String errorCode, String message) {
            this(errorCode, message, null);
        }
    }

    // Utility methods trên interface
    static <T> Result<T> ok(T value) { return new Success<>(value); }
    static <T> Result<T> fail(String code, String message) { return new Failure<>(code, message); }

    default boolean isSuccess() { return this instanceof Success<T>; }
    default boolean isFailure() { return this instanceof Failure<T>; }

    default T getOrThrow() {
        return switch (this) {
            case Success<T> s -> s.value();
            case Failure<T> f -> throw new RuntimeException(f.errorCode() + ": " + f.message());
        };
    }

    default T getOrElse(T defaultValue) {
        return switch (this) {
            case Success<T> s -> s.value();
            case Failure<T> f -> defaultValue;
        };
    }

    default <R> Result<R> map(Function<T, R> mapper) {
        return switch (this) {
            case Success<T> s -> Result.ok(mapper.apply(s.value()));
            case Failure<T> f -> Result.fail(f.errorCode(), f.message());
        };
    }

    default <R> Result<R> flatMap(Function<T, Result<R>> mapper) {
        return switch (this) {
            case Success<T> s -> mapper.apply(s.value());
            case Failure<T> f -> Result.fail(f.errorCode(), f.message());
        };
    }
}

// Dùng
Result<User> result = userService.findById(id);
String name = result
    .map(User::getName)
    .getOrElse("Unknown");

// Exhaustive switch – compiler đảm bảo handle tất cả case
switch (result) {
    case Result.Success<User> s -> renderUser(s.value());
    case Result.Failure<User> f -> renderError(f.message());
    // Không cần default! Compiler biết chỉ có 2 case
}
```

### Payment Domain Example
```java
public sealed interface PaymentResult permits
    PaymentResult.Approved, PaymentResult.Declined, PaymentResult.Pending {

    record Approved(String transactionId, BigDecimal amount, Instant processedAt)
        implements PaymentResult {}

    record Declined(String reason, String declineCode)
        implements PaymentResult {}

    record Pending(String referenceId, Duration estimatedTime)
        implements PaymentResult {}
}

// Xử lý exhaustive – compiler kiểm tra
String handlePayment(PaymentResult result) {
    return switch (result) {
        case PaymentResult.Approved(var txId, var amount, var time) ->
            "Approved: " + txId + " for " + amount;
        case PaymentResult.Declined(var reason, var code) ->
            "Declined (" + code + "): " + reason;
        case PaymentResult.Pending(var refId, var eta) ->
            "Pending: ref=" + refId + ", ETA=" + eta;
        // Không cần default
    };
}
```

---

## How – Exhaustive Pattern Matching

Sức mạnh chính của Sealed: **compiler kiểm tra exhaustiveness** trong switch:

```java
public sealed interface Notification permits EmailNotification, SMSNotification, PushNotification {}
record EmailNotification(String to, String subject, String body) implements Notification {}
record SMSNotification(String phone, String text) implements Notification {}
record PushNotification(String deviceToken, String title, String body) implements Notification {}

// COMPILE ERROR nếu thiếu case
void send(Notification n) {
    switch (n) {
        case EmailNotification e -> emailService.send(e.to(), e.subject(), e.body());
        case SMSNotification s -> smsService.send(s.phone(), s.text());
        // COMPILE ERROR: PushNotification not covered!
    }
}

// Đầy đủ – compile OK
void send(Notification n) {
    switch (n) {
        case EmailNotification e  -> emailService.send(e.to(), e.subject(), e.body());
        case SMSNotification s    -> smsService.send(s.phone(), s.text());
        case PushNotification p   -> pushService.send(p.deviceToken(), p.title(), p.body());
    }
}

// Thêm SlackNotification vào sealed → tất cả switch cần update → compiler CHỈ RA ngay!
```

---

## How – Guarded Patterns (Java 21)

```java
sealed interface Shape permits Circle, Rectangle {}
record Circle(double radius) implements Shape {}
record Rectangle(double w, double h) implements Shape {}

String classify(Shape shape) {
    return switch (shape) {
        case Circle c when c.radius() > 100  -> "Giant circle";
        case Circle c when c.radius() > 10   -> "Large circle";
        case Circle c                         -> "Small circle";
        case Rectangle r when r.w() == r.h() -> "Square";
        case Rectangle r                      -> "Rectangle";
    };
}
```

---

## How – Sealed với Visitor Pattern (hiện đại hơn)

Trước Sealed: Visitor Pattern phức tạp để add operations không sửa class.
Với Sealed: dùng switch expression đơn giản hơn nhiều.

```java
// Biểu thức toán học
public sealed interface Expr permits Expr.Num, Expr.Add, Expr.Mul, Expr.Neg {
    record Num(double value) implements Expr {}
    record Add(Expr left, Expr right) implements Expr {}
    record Mul(Expr left, Expr right) implements Expr {}
    record Neg(Expr expr) implements Expr {}
}

// "Visitor" không cần class, chỉ cần method với switch
double evaluate(Expr expr) {
    return switch (expr) {
        case Expr.Num(double v)          -> v;
        case Expr.Add(var l, var r)      -> evaluate(l) + evaluate(r);
        case Expr.Mul(var l, var r)      -> evaluate(l) * evaluate(r);
        case Expr.Neg(var e)             -> -evaluate(e);
    };
}

String print(Expr expr) {
    return switch (expr) {
        case Expr.Num(double v)         -> String.valueOf(v);
        case Expr.Add(var l, var r)     -> "(" + print(l) + " + " + print(r) + ")";
        case Expr.Mul(var l, var r)     -> "(" + print(l) + " * " + print(r) + ")";
        case Expr.Neg(var e)            -> "-" + print(e);
    };
}

// (2 + 3) * -4
Expr expr = new Expr.Mul(
    new Expr.Add(new Expr.Num(2), new Expr.Num(3)),
    new Expr.Neg(new Expr.Num(4))
);
System.out.println(print(expr));    // ((2.0 + 3.0) * -4.0)
System.out.println(evaluate(expr)); // -20.0
```

---

## Why – Tại sao cần Sealed?

| Bài toán | Sealed giải quyết |
|---------|-----------------|
| Extensibility không kiểm soát | Giới hạn chính xác subtype cho phép |
| Switch/if không exhaustive | Compiler kiểm tra tất cả case |
| Visitor Pattern phức tạp | Switch expression trực tiếp |
| `else` / `default` che giấu bug | Không cần default khi exhaustive |
| Domain model không rõ ràng | ADT = model rõ ràng (Success/Failure, State...) |

---

## When – Khi nào dùng Sealed?

**Nên dùng:**
- **Domain state machines**: `OrderStatus`, `PaymentState`
- **Result/Error types**: `Success<T>` / `Failure<T>`
- **AST, DSL**: compiler, query builder
- **API response**: typed response model
- **Event hierarchy**: khi cần biết chính xác tất cả event types
- Khi cần exhaustive pattern matching

**Không nên dùng:**
- Khi cần extensibility từ bên ngoài (library/framework)
- Khi số subtype có thể tăng không giới hạn
- Khi subtype cần ở nhiều module/package khác nhau (Java 9+ modules)

---

## Compare – Sealed vs Enum vs Abstract Class

| | `sealed` | `enum` | `abstract class` |
|--|---------|--------|-----------------|
| Số instance | Nhiều (mỗi subtype) | Cố định (singleton) | Nhiều |
| State | Mỗi subtype có state riêng | Hạn chế | Có |
| Exhaustive switch | Có (compiler check) | Có | Không |
| Extensible | Không (giới hạn) | Không | Có |
| Generics | Có | Không | Có |
| Pattern matching | Có (Java 21) | Có | Không tốt |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Compiler exhaustiveness check | Không thể extend từ ngoài module |
| ADT rõ ràng | Cần Java 17+ |
| Loại bỏ default trong switch | Thêm class/file |
| Tích hợp tốt với pattern matching | Không quen với OOP thuần |

---

## Real-world Usage (Production)

### 1. HTTP Response Model
```java
public sealed interface ApiResponse<T> permits ApiResponse.Ok, ApiResponse.Error {
    record Ok<T>(T data, int statusCode) implements ApiResponse<T> {
        public Ok(T data) { this(data, 200); }
    }
    record Error<T>(String errorCode, String message, int statusCode) implements ApiResponse<T> {
        public Error(String errorCode, String message) { this(errorCode, message, 400); }
    }

    static <T> ApiResponse<T> ok(T data) { return new Ok<>(data); }
    static <T> ApiResponse<T> notFound(String resource) {
        return new Error<>("NOT_FOUND", resource + " not found", 404);
    }
}

// Controller trả về sealed type → service layer tường minh
ApiResponse<UserDto> response = userService.findById(id);
return switch (response) {
    case ApiResponse.Ok<UserDto> ok -> ResponseEntity.ok(ok.data());
    case ApiResponse.Error<UserDto> err ->
        ResponseEntity.status(err.statusCode()).body(err);
};
```

### 2. Order State Machine
```java
public sealed interface OrderState permits
    OrderState.Pending, OrderState.Confirmed, OrderState.Shipped,
    OrderState.Delivered, OrderState.Cancelled {

    record Pending(Instant createdAt) implements OrderState {}
    record Confirmed(Instant confirmedAt, String confirmationId) implements OrderState {}
    record Shipped(Instant shippedAt, String trackingNumber) implements OrderState {}
    record Delivered(Instant deliveredAt) implements OrderState {}
    record Cancelled(Instant cancelledAt, String reason) implements OrderState {}
}

// State transition
OrderState transition(OrderState current, OrderEvent event) {
    return switch (current) {
        case OrderState.Pending p -> switch (event) {
            case ConfirmEvent e -> new OrderState.Confirmed(Instant.now(), e.confirmationId());
            case CancelEvent e  -> new OrderState.Cancelled(Instant.now(), e.reason());
            default -> throw new IllegalStateException("Invalid transition");
        };
        case OrderState.Confirmed c -> switch (event) {
            case ShipEvent e -> new OrderState.Shipped(Instant.now(), e.trackingNumber());
            case CancelEvent e -> new OrderState.Cancelled(Instant.now(), e.reason());
            default -> throw new IllegalStateException();
        };
        case OrderState.Shipped s -> switch (event) {
            case DeliverEvent e -> new OrderState.Delivered(Instant.now());
            default -> throw new IllegalStateException();
        };
        case OrderState.Delivered d -> throw new IllegalStateException("Order already delivered");
        case OrderState.Cancelled c -> throw new IllegalStateException("Order already cancelled");
    };
}
```

### 3. Validation Result
```java
public sealed interface ValidationResult permits ValidationResult.Valid, ValidationResult.Invalid {
    record Valid() implements ValidationResult {}
    record Invalid(List<String> errors) implements ValidationResult {
        public Invalid { errors = List.copyOf(errors); }
        public Invalid(String... errors) { this(List.of(errors)); }
    }

    static ValidationResult valid() { return new Valid(); }
    static ValidationResult invalid(String... errors) { return new Invalid(errors); }

    default boolean isValid() { return this instanceof Valid; }

    default ValidationResult and(ValidationResult other) {
        return switch (this) {
            case Valid ignored -> other;
            case Invalid(var errs1) -> switch (other) {
                case Valid ignored -> this;
                case Invalid(var errs2) -> {
                    var combined = new ArrayList<>(errs1);
                    combined.addAll(errs2);
                    yield new Invalid(combined);
                }
            };
        };
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Pattern Matching** (toàn bộ evolution: instanceof → switch → deconstruction)
>
> Keyword: `instanceof` pattern (Java 16), switch expression (Java 14), switch pattern matching (Java 21), guarded patterns (`when`), record deconstruction pattern, nested patterns, null handling trong switch (Java 21), `_` unnamed pattern (Java 22)
