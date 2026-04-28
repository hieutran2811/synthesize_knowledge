# Encapsulation (Đóng Gói)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Encapsulation là gì?

**Encapsulation** là tính chất gói gọn **dữ liệu (state)** và **hành vi (behavior)** vào trong một đơn vị duy nhất (class), đồng thời **kiểm soát quyền truy cập** từ bên ngoài.

Hai khái niệm thường bị nhầm lẫn nhưng không đồng nhất:
- **Information Hiding**: ẩn chi tiết nội bộ — cái *mục tiêu*
- **Encapsulation**: cơ chế gói state + behavior — cái *phương tiện*

> Encapsulation là phương tiện để đạt Information Hiding, nhưng setter/getter nếu dùng bừa bãi không phải encapsulation thực sự.

---

## How – Access Modifiers

Java có 4 mức kiểm soát truy cập:

| Modifier | Cùng class | Cùng package | Subclass (package khác) | Ngoài package |
|----------|:----------:|:------------:|:-----------------------:|:-------------:|
| `private` | ✅ | ❌ | ❌ | ❌ |
| *(default/package-private)* | ✅ | ✅ | ❌ | ❌ |
| `protected` | ✅ | ✅ | ✅ | ❌ |
| `public` | ✅ | ✅ | ✅ | ✅ |

> Không có keyword `package-private` — bỏ modifier = package-private.

### Quy tắc thực tế
- **Field**: luôn `private`
- **Method nội bộ**: `private`
- **Method dành cho subclass override**: `protected`
- **API public**: `public`
- **Utility class nội bộ package**: không modifier (package-private)

---

## How – Các cấp độ Encapsulation

### Cấp 1: Che giấu field bằng `private`
```java
// Sai – field public, ai cũng thay đổi được
public class BankAccount {
    public double balance; // NGUY HIỂM!
}

// Đúng – kiểm soát qua method
public class BankAccount {
    private double balance;

    public void deposit(double amount) {
        if (amount <= 0) throw new IllegalArgumentException("Amount must be positive");
        this.balance += amount;
    }

    public void withdraw(double amount) {
        if (amount > balance) throw new InsufficientFundsException(amount);
        this.balance -= amount;
    }

    public double getBalance() { return balance; }
}
```
→ Logic kiểm tra tập trung tại 1 chỗ, không bị bypass.

---

### Cấp 2: Tránh trả về reference của mutable object

Đây là lỗi encapsulation phổ biến nhất dù field đã `private`:

```java
// Sai – trả về reference của list nội bộ
public class Order {
    private List<Item> items = new ArrayList<>();

    public List<Item> getItems() {
        return items; // caller có thể items.clear(), items.add(...)!
    }
}

// Đúng – trả về defensive copy (hoặc unmodifiable view)
public List<Item> getItems() {
    return Collections.unmodifiableList(items); // read-only view
    // hoặc: return new ArrayList<>(items); // defensive copy
}
```

---

### Cấp 3: Immutable Object (Bất biến hoàn toàn)

Immutable object là đỉnh cao của encapsulation — state không thể thay đổi sau khi tạo.

**Cách tạo immutable class:**
1. Declare class `final` (tránh subclass phá vỡ tính bất biến)
2. Tất cả fields `private final`
3. Không có setter
4. Constructor khởi tạo đầy đủ
5. Với mutable fields: **defensive copy** khi nhận vào và trả ra

```java
public final class Money {
    private final BigDecimal amount;
    private final Currency currency;

    public Money(BigDecimal amount, Currency currency) {
        // defensive copy với BigDecimal là immutable nên không cần
        // nhưng nếu field là Date/List thì phải copy
        this.amount = Objects.requireNonNull(amount, "amount must not be null");
        this.currency = Objects.requireNonNull(currency);
    }

    public BigDecimal getAmount() { return amount; }
    public Currency getCurrency() { return currency; }

    // Mọi "thay đổi" tạo object mới
    public Money add(Money other) {
        if (!this.currency.equals(other.currency))
            throw new IllegalArgumentException("Currency mismatch");
        return new Money(this.amount.add(other.amount), this.currency);
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Money m)) return false;
        return amount.compareTo(m.amount) == 0 && currency.equals(m.currency);
    }

    @Override
    public int hashCode() { return Objects.hash(amount, currency); }

    @Override
    public String toString() { return amount + " " + currency; }
}
```

---

### Cấp 4: Records (Java 16+) — Immutable Value Object ngắn gọn

```java
// Thay thế toàn bộ boilerplate bằng
public record Money(BigDecimal amount, Currency currency) {
    // Compact canonical constructor để validate
    public Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.compareTo(BigDecimal.ZERO) < 0)
            throw new IllegalArgumentException("Negative amount");
    }

    public Money add(Money other) {
        return new Money(this.amount.add(other.amount), this.currency);
    }
}
// Record tự sinh: constructor, getters (amount(), currency()), equals, hashCode, toString
```

---

### Cấp 5: Package-Private như công cụ thiết kế

```
com.example.payment
├── PaymentService.java       (public – API ra ngoài)
├── PaymentValidator.java     (package-private – nội bộ module)
├── PaymentRepository.java    (package-private – nội bộ module)
└── model/
    └── Payment.java          (public – shared model)
```
→ `PaymentValidator` không thể bị code ngoài package gọi trực tiếp — module boundary rõ ràng.

---

## Why – Tại sao cần Encapsulation?

1. **Bảo vệ tính nhất quán (invariant)**: `balance` không bao giờ âm nếu kiểm soát qua method
2. **Giảm coupling**: caller không phụ thuộc vào cấu trúc nội bộ → thay đổi internal không phá vỡ external
3. **Dễ maintain**: logic nghiệp vụ tập trung, không rải rác
4. **Thread safety**: immutable object tự nhiên thread-safe
5. **Hỗ trợ caching/lazy init**: `getExpensiveValue()` có thể cache kết quả mà không ai biết

---

## When – Khi nào cần áp dụng chặt hơn?

| Tình huống | Mức độ encapsulation |
|-----------|---------------------|
| Domain model (DDD Entity, Value Object) | Chặt nhất – không bao giờ expose mutable state |
| DTO (Data Transfer Object) | Lỏng hơn – có thể dùng public fields hoặc record |
| Internal implementation class | Package-private |
| Utility/Helper class | Static methods, constructor private |
| Configuration object | Có thể dùng Builder + immutable |

---

## Compare – Getter/Setter vs Tell, Don't Ask

**Anti-pattern: Anemic Domain Model**
```java
// Caller lấy data ra, tự xử lý → logic nằm ngoài object
double balance = account.getBalance();
if (balance >= amount) {
    account.setBalance(balance - amount);
}
```

**Đúng: Tell, Don't Ask**
```java
// Object tự biết cách làm
account.withdraw(amount); // object tự kiểm tra và xử lý
```

---

## Compare – Encapsulation trong Java vs Ngôn ngữ khác

| | Java | Kotlin | Python | C++ |
|--|------|--------|--------|-----|
| Cơ chế | Access modifiers | Access modifiers | Convention (`_`, `__`) | Access specifiers |
| Default | Package-private | `public` | Public | Private (class) |
| Property | Getter/Setter method | `var`/`val` properties | `@property` decorator | Không built-in |
| Immutable | `final` + discipline | `val` (compiler enforced) | Convention | `const` |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Bảo vệ invariant | Boilerplate getter/setter (giảm nhờ Lombok, Records) |
| Loose coupling | Defensive copy tốn bộ nhớ |
| Thread-safe (immutable) | Immutable object tạo nhiều garbage → GC pressure |
| Dễ thay đổi internal | Over-encapsulation gây khó test nếu không có dependency injection |

---

## Real-world Usage (Production)

### 1. Lombok giảm boilerplate
```java
@Getter
@Setter  // chỉ dùng khi thực sự cần mutability
@Builder
@EqualsAndHashCode
@ToString
public class UserProfile {
    private final Long id;
    private String displayName;
    private String email;
}
```

### 2. DDD Value Object
```java
// Email là Value Object – immutable, tự validate
public record Email(String value) {
    public Email {
        if (!value.matches("^[\\w.-]+@[\\w.-]+\\.[a-z]{2,}$"))
            throw new IllegalArgumentException("Invalid email: " + value);
        value = value.toLowerCase(); // normalize
    }
}
```

### 3. Spring – encapsulation ở tầng Service
```java
@Service
public class OrderService {
    private final OrderRepository repo; // không ai ngoài service được gọi repo trực tiếp

    // Chỉ expose use-case methods
    public OrderDto placeOrder(PlaceOrderCommand cmd) { ... }
    public void cancelOrder(Long orderId) { ... }

    // Method nội bộ
    private void validateStock(Order order) { ... }
}
```

### 4. Pitfall: Date/Collection leak
```java
// Nguy hiểm – Date là mutable!
public class Event {
    private Date startTime;
    public Date getStartTime() { return startTime; } // caller có thể sửa!
}

// Fix: trả về copy, hoặc dùng Instant (immutable)
public class Event {
    private Instant startTime; // Instant là immutable
    public Instant getStartTime() { return startTime; } // safe
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo đi sâu vào: **Inheritance** (Kế thừa)
>
> Keyword cần tổng hợp: `extends`, `super`, constructor chaining, method resolution order, vtable, `final` class/method, covariant return type, `Object` class (equals/hashCode/toString), Diamond Problem, Fragile Base Class, `instanceof` + pattern matching (Java 16+)
