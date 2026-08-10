---
title: "Records (Java 16)"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Records (Java 16)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Record là gì?

**Record** *(lớp biểu diễn dữ liệu cô đọng)* — chính thức từ Java 16, preview ở Java 14–15 — là một loại class đặc biệt được thiết kế làm **immutable data carrier** *(vật mang dữ liệu bất biến)*: ưu tiên mô tả dữ liệu và giá trị của nó thay vì viết nhiều code khuôn mẫu.

> 💡 **Giải thích dễ hiểu — record là “phiếu thông tin” có mẫu sẵn:**
> Với class thường, bạn phải tự in cả bộ mẫu gồm field, constructor, accessor, `equals`, `hashCode` và `toString`. Record chỉ yêu cầu khai báo các ô trên phiếu, ví dụ `Point(int x, int y)`; compiler tự in phần còn lại. Record vẫn là class thật, vẫn có constructor và method, chứ không phải một cấu trúc dữ liệu “nhẹ hơn JVM”.

```java
// Trước Records: ~50 dòng boilerplate
public final class Point {
    private final int x;
    private final int y;
    public Point(int x, int y) { this.x = x; this.y = y; }
    public int x() { return x; }
    public int y() { return y; }
    @Override public boolean equals(Object o) { ... }
    @Override public int hashCode() { ... }
    @Override public String toString() { ... }
}

// Với Record: 1 dòng
public record Point(int x, int y) {}
```

Compiler tự sinh:
- Constructor chuẩn (canonical constructor)
- Accessor methods: `x()`, `y()` (không phải `getX()`)
- `equals()` dựa trên tất cả components
- `hashCode()` dựa trên tất cả components
- `toString()`: `Point[x=1, y=2]`

> 💡 **Giải thích dễ hiểu — bất biến “nông”, không phải bất biến tuyệt đối:**
> Component của record là `final`, nghĩa là reference không thể trỏ sang object khác sau khi khởi tạo. Nhưng object được trỏ tới vẫn có thể mutable. Ví dụ `record Team(List<String> members)` không ngăn caller sửa chính `members`. Với collection, thường nên chuẩn hóa bằng `members = List.copyOf(members)` trong canonical constructor để record thực sự an toàn hơn.

---

## How – Cú pháp đầy đủ

### Khai báo cơ bản
```java
public record Person(String name, int age) {}

Person p = new Person("Alice", 30);
p.name();       // "Alice"  – accessor (không phải getName())
p.age();        // 30
p.toString();   // Person[name=Alice, age=30]

Person p2 = new Person("Alice", 30);
p.equals(p2);   // true  – structural equality
p.hashCode() == p2.hashCode(); // true
```

### Canonical Constructor – Validation
```java
public record Email(String value) {
    // Compact canonical constructor (Java 16+) – không cần parameter list
    public Email {
        Objects.requireNonNull(value, "Email must not be null");
        if (!value.matches("^[\\w.+-]+@[\\w-]+\\.[a-z]{2,}$"))
            throw new IllegalArgumentException("Invalid email: " + value);
        value = value.toLowerCase().trim(); // normalize trước khi assign
        // Compiler tự assign: this.value = value;
    }
}

// Explicit canonical constructor (alternative)
public record Range(int min, int max) {
    public Range(int min, int max) {
        if (min > max) throw new IllegalArgumentException("min > max");
        this.min = min;
        this.max = max;
    }
}
```

> 💡 **Giải thích dễ hiểu — canonical constructor là cổng kiểm soát duy nhất:**
> Mọi cách tạo record cuối cùng đều phải đi qua constructor có đủ component theo đúng thứ tự. Vì vậy đây là nơi thích hợp để kiểm tra invariant *(điều kiện luôn phải đúng)* và chuẩn hóa dữ liệu. Compact constructor cho phép kiểm tra tham số trước; compiler sẽ tự gán chúng vào field sau khi block kết thúc.

### Custom Constructor (Non-canonical)
```java
public record Point(double x, double y) {
    // Canonical constructor (auto-generated hoặc custom)
    public Point {
        if (Double.isNaN(x) || Double.isNaN(y))
            throw new IllegalArgumentException("NaN not allowed");
    }

    // Static factory (alternative constructor)
    public static Point origin() { return new Point(0, 0); }
    public static Point of(double x, double y) { return new Point(x, y); }

    // Non-canonical constructor PHẢI delegate đến canonical
    public Point(double angle, double radius, boolean polar) {
        this(radius * Math.cos(angle), radius * Math.sin(angle)); // delegate!
    }
}
```

### Custom Methods
```java
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("Negative amount");
    }

    // Instance methods
    public Money add(Money other) {
        assertSameCurrency(other);
        return new Money(this.amount.add(other.amount), this.currency);
    }

    public Money multiply(BigDecimal factor) {
        return new Money(this.amount.multiply(factor), this.currency);
    }

    public boolean isZero() { return amount.compareTo(BigDecimal.ZERO) == 0; }

    // Static methods
    public static Money zero(Currency currency) {
        return new Money(BigDecimal.ZERO, currency);
    }

    // Private helper
    private void assertSameCurrency(Money other) {
        if (!this.currency.equals(other.currency))
            throw new IllegalArgumentException("Currency mismatch");
    }

    // Override toString để format đẹp hơn
    @Override
    public String toString() {
        return amount.toPlainString() + " " + currency.getCode();
    }
}
```

### Record implement Interface
```java
public interface Shape {
    double area();
    double perimeter();
}

public record Circle(double radius) implements Shape {
    public Circle {
        if (radius <= 0) throw new IllegalArgumentException("Radius must be positive");
    }
    @Override public double area() { return Math.PI * radius * radius; }
    @Override public double perimeter() { return 2 * Math.PI * radius; }
}

public record Rectangle(double width, double height) implements Shape {
    @Override public double area() { return width * height; }
    @Override public double perimeter() { return 2 * (width + height); }
}
```

### Generic Record
```java
public record Pair<A, B>(A first, B second) {
    public static <A, B> Pair<A, B> of(A first, B second) {
        return new Pair<>(first, second);
    }

    public Pair<B, A> swap() { return new Pair<>(second, first); }

    public <C> Pair<A, C> mapSecond(Function<B, C> mapper) {
        return new Pair<>(first, mapper.apply(second));
    }
}

Pair<String, Integer> p = Pair.of("hello", 5);
Pair<Integer, String> swapped = p.swap(); // (5, "hello")
```

---

## How – Giới hạn của Record

> 💡 **Giải thích dễ hiểu — record đổi sự linh hoạt lấy một hợp đồng rõ ràng:**
> Record tuyên bố “trạng thái của tôi chính là danh sách component trên header”. Vì thế nó không cho thêm instance field ẩn, không cho kế thừa class khác và bản thân luôn `final`. Nếu object cần thay đổi trạng thái qua thời gian, cần proxy kế thừa hoặc có nhiều field nội bộ không thuộc danh tính giá trị, class thường phù hợp hơn.

```java
// 1. KHÔNG thể extends class (implicit extends java.lang.Record)
public record Bad() extends SomeClass {} // COMPILE ERROR

// 2. KHÔNG thể có instance fields ngoài components
public record Bad(int x) {
    private int cache; // COMPILE ERROR – chỉ static fields được phép
    private static final int STATIC_OK = 0; // OK
}

// 3. Components luôn final – không thể reassign
public record Bad(int x) {
    void mutate() { this.x = 10; } // COMPILE ERROR
}

// 4. KHÔNG thể abstract
public abstract record Bad(int x) {} // COMPILE ERROR

// 5. Record ngầm là final – không thể extends record khác
public record Child(int x) extends Parent {} // COMPILE ERROR (nếu Parent là record)

// 6. KHÔNG thể dùng làm inner class (non-static)
class Outer {
    record Inner(int x) {} // OK – record luôn là static ngầm định
    // non-static inner record: COMPILE ERROR
}
```

---

## How – Record và Serialization

```java
// Record implement Serializable
public record UserDto(Long id, String name) implements Serializable {
    @Serial private static final long serialVersionUID = 1L;
}

// Record không dùng readObject/writeObject thông thường
// Deserialization gọi canonical constructor → validation được giữ nguyên!
// Đây là ưu điểm lớn hơn class thông thường (class thường có thể bypass constructor khi deserialize)
```

---

## How – Record với Pattern Matching (Java 21)

> 💡 **Giải thích dễ hiểu — đóng gói bằng record, mở gói bằng pattern:**
> Constructor gom nhiều giá trị thành một record; record pattern làm chiều ngược lại, lấy các component ra và đặt tên ngay tại chỗ kiểm tra kiểu. Giống đóng hàng vào hộp có nhãn rồi mở đúng từng ngăn mà không phải gọi `point.x()` và `point.y()` thủ công.

```java
// Deconstruction pattern (Java 21)
Object obj = new Point(3, 4);

if (obj instanceof Point(int x, int y)) { // deconstruct record!
    System.out.println("x=" + x + ", y=" + y);
}

// Switch với record pattern
String describe(Shape shape) {
    return switch (shape) {
        case Circle(double r) when r > 10 -> "Large circle r=" + r;
        case Circle(double r)              -> "Circle r=" + r;
        case Rectangle(double w, double h) -> "Rectangle " + w + "x" + h;
    };
}
```

---

## Why – Tại sao cần Record?

| Bài toán | Record giải quyết |
|---------|-----------------|
| Boilerplate (constructor, equals, hashCode, toString) | Compiler tự sinh |
| Vô tình mutate DTO | Components là `final` |
| Anemic domain model với quá nhiều getter/setter | Value Object rõ ràng |
| Validation bị bypass | Canonical constructor đảm bảo invariant |

---

## When – Khi nào dùng Record?

**Nên dùng:**
- **DTO (Data Transfer Object)**: request/response body
- **Value Object** trong DDD: `Money`, `Email`, `Address`
- **Tuple / Pair**: trả về nhiều giá trị từ method
- **Event**: `OrderCreatedEvent`, `UserRegisteredEvent`
- **Configuration data**: immutable config object
- **Query result / Projection**: kết quả JOIN phức tạp

**Không nên dùng:**
- Entity JPA (cần mutable, no-arg constructor, ID quản lý bởi Hibernate)
- Class cần extend class khác
- Class có state mutable theo business logic
- Class cần nhiều custom behavior phức tạp (dùng class thường)

> 💡 **Giải thích dễ hiểu — DTO tốt, JPA Entity thường không:**
> DTO giống ảnh chụp dữ liệu tại một thời điểm nên rất hợp với record. JPA Entity lại giống hồ sơ đang được ORM theo dõi: ID và quan hệ có thể được gán muộn, lazy-loading có thể cần proxy, trạng thái thay đổi trong persistence context. Những yêu cầu đó xung đột với tính `final` và constructor đầy đủ của record.

---

## Compare – Record vs Class vs Lombok

| | Regular Class | Record | Lombok @Value |
|--|-------------|--------|--------------|
| Immutable | Thủ công | Tự động | Tự động |
| Boilerplate | Nhiều | Không | Không |
| Extends | Có | Không | Có |
| Extra fields | Có | Không (chỉ static) | Có |
| Validation | Constructor | Compact constructor | Constructor |
| Pattern matching | Không | Có (Java 21) | Không |
| Serialization | Có thể bypass constructor | Constructor được gọi | Có thể bypass |
| JDK built-in | Không | Có | Không (cần dependency) |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Loại bỏ boilerplate | Không thể extend class |
| Immutable by design | Không có extra instance fields |
| Validation trong constructor | Accessor là `x()` không phải `getX()` (break JavaBeans convention) |
| Serialization an toàn | Không dùng được làm JPA Entity |
| Pattern matching (Java 21) | Chỉ tốt cho "data classes", không phải mọi class |

---

## Real-world Usage (Production)

### 1. Request/Response DTO
```java
// Spring MVC
public record CreateUserRequest(
    @NotBlank String name,
    @Email String email,
    @Min(0) @Max(150) int age
) {}

public record UserResponse(Long id, String name, String email, LocalDateTime createdAt) {
    public static UserResponse from(User user) {
        return new UserResponse(user.getId(), user.getName(),
            user.getEmail(), user.getCreatedAt());
    }
}

@PostMapping("/users")
public ResponseEntity<UserResponse> create(@Valid @RequestBody CreateUserRequest req) {
    User user = userService.create(req);
    return ResponseEntity.status(201).body(UserResponse.from(user));
}
```

### 2. Domain Value Object
```java
public record CustomerId(UUID value) {
    public CustomerId {
        Objects.requireNonNull(value);
    }
    public static CustomerId generate() { return new CustomerId(UUID.randomUUID()); }
    public static CustomerId of(String uuidStr) { return new CustomerId(UUID.fromString(uuidStr)); }
    @Override public String toString() { return value.toString(); }
}

// Dùng: type-safe, không thể nhầm customerId với orderId
void processOrder(CustomerId customerId, OrderId orderId) { ... }
// processOrder(orderId, customerId); // COMPILE ERROR – type-safe!
```

### 3. Event (Domain Event / Spring Event)
```java
public record OrderPlacedEvent(
    OrderId orderId,
    CustomerId customerId,
    List<OrderItem> items,
    Money totalAmount,
    Instant occurredAt
) {
    public OrderPlacedEvent(OrderId orderId, CustomerId customerId,
                             List<OrderItem> items, Money totalAmount) {
        this(orderId, customerId, List.copyOf(items), totalAmount, Instant.now());
    }
}
```

### 4. Projection (Spring Data JPA)
```java
// Interface projection
interface UserSummary {
    Long getId();
    String getName();
}

// Record projection (Spring Data 3.x+)
public record UserSummary(Long id, String name) {}

@Query("SELECT new com.example.UserSummary(u.id, u.name) FROM User u WHERE u.active = true")
List<UserSummary> findActiveSummaries();
```

### 5. Kết hợp với Stream
```java
record ProductSales(String productId, String name, BigDecimal revenue) {}

List<ProductSales> topProducts = orders.stream()
    .flatMap(o -> o.getItems().stream())
    .collect(Collectors.groupingBy(
        OrderItem::getProductId,
        Collectors.reducing(BigDecimal.ZERO, OrderItem::getSubtotal, BigDecimal::add)
    ))
    .entrySet().stream()
    .map(e -> new ProductSales(e.getKey(), productCache.getName(e.getKey()), e.getValue()))
    .sorted(Comparator.comparing(ProductSales::revenue).reversed())
    .limit(10)
    .toList();
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Sealed Classes (Java 17)**
>
> Keyword: `sealed` + `permits`, `non-sealed`, `final` subtype, exhaustive switch, algebraic data types (ADT), sealed interface + record (sum type), pattern matching với sealed hierarchy
