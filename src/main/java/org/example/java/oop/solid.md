# SOLID Principles

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – SOLID là gì?

**SOLID** là tập hợp 5 nguyên lý thiết kế OOP do Robert C. Martin (Uncle Bob) đề xuất, giúp code dễ bảo trì, mở rộng, và test.

| Chữ | Nguyên lý | Ý nghĩa ngắn gọn |
|-----|----------|-----------------|
| **S** | Single Responsibility Principle | Mỗi class chỉ có 1 lý do để thay đổi |
| **O** | Open/Closed Principle | Mở để mở rộng, đóng để sửa đổi |
| **L** | Liskov Substitution Principle | Subtype phải thay thế được supertype |
| **I** | Interface Segregation Principle | Đừng ép implement interface không cần thiết |
| **D** | Dependency Inversion Principle | Phụ thuộc vào abstraction, không phải concretion |

---

## S – Single Responsibility Principle (SRP)

### What
> "A class should have only one reason to change."

Mỗi class chỉ nên chịu trách nhiệm cho **một aspect** của hệ thống. "Một lý do để thay đổi" = một **actor** (người/role yêu cầu thay đổi) duy nhất.

### How – Nhận biết vi phạm SRP

```java
// VI PHẠM SRP – class này thay đổi vì 3 lý do khác nhau:
// 1. Thay đổi business logic tính lương
// 2. Thay đổi cách format report
// 3. Thay đổi cách lưu dữ liệu
public class Employee {
    private String name;
    private double hourlyRate;
    private int hoursWorked;

    public double calculatePay() {         // Business: HR/Payroll
        return hourlyRate * hoursWorked;
    }

    public String generateReport() {       // Presentation: Reporting team
        return "Employee: " + name + "\nPay: " + calculatePay();
    }

    public void saveToDatabase() {         // Persistence: DB team
        // JDBC code...
    }
}
```

```java
// ĐÚNG – Tách theo responsibility
public class Employee {
    private String name;
    private double hourlyRate;
    private int hoursWorked;
    // getters/setters
}

public class PayrollCalculator {
    public double calculate(Employee e) {
        return e.getHourlyRate() * e.getHoursWorked();
    }
}

public class EmployeeReporter {
    private final PayrollCalculator calculator;
    public String generateReport(Employee e) {
        return "Employee: " + e.getName() + "\nPay: " + calculator.calculate(e);
    }
}

public class EmployeeRepository {
    public void save(Employee e) { /* persistence */ }
    public Employee findById(Long id) { /* query */ }
}
```

### How – Cohesion là thước đo

**High cohesion** = các method trong class đều liên quan chặt đến cùng mục đích.
**Low cohesion** = class "làm tất cả mọi thứ" → God Object anti-pattern.

> SRP không có nghĩa là "mỗi class chỉ có 1 method". Nghĩa là các method đều phục vụ cùng 1 mục đích.

### Real-world Usage
```java
// Spring: Tách rõ Controller (HTTP) – Service (Business) – Repository (Data)
@RestController
public class OrderController {
    private final OrderService service; // chỉ handle HTTP
    @PostMapping("/orders")
    public ResponseEntity<OrderDto> create(@RequestBody CreateOrderRequest req) {
        return ResponseEntity.ok(service.createOrder(req));
    }
}

@Service
public class OrderService {
    private final OrderRepository repo;
    private final InventoryService inventory; // chỉ handle business logic
    public OrderDto createOrder(CreateOrderRequest req) {
        inventory.reserve(req.items());
        Order order = Order.create(req);
        return OrderDto.from(repo.save(order));
    }
}
```

---

## O – Open/Closed Principle (OCP)

### What
> "Software entities should be open for extension, but closed for modification."

Khi cần thêm tính năng mới → **thêm code mới**, không **sửa code cũ** đang hoạt động.

### How – Vi phạm OCP

```java
// VI PHẠM – mỗi lần thêm loại hình học mới phải sửa class này
public class AreaCalculator {
    public double calculateArea(Object shape) {
        if (shape instanceof Circle c) {
            return Math.PI * c.radius() * c.radius();
        } else if (shape instanceof Rectangle r) {
            return r.width() * r.height();
        } else if (shape instanceof Triangle t) { // thêm loại mới → SỬA method này!
            return 0.5 * t.base() * t.height();
        }
        throw new IllegalArgumentException("Unknown shape");
    }
}
```

```java
// ĐÚNG – thêm loại mới chỉ cần thêm class, không sửa AreaCalculator
public interface Shape {
    double area();
}

public record Circle(double radius) implements Shape {
    public double area() { return Math.PI * radius * radius; }
}

public record Rectangle(double width, double height) implements Shape {
    public double area() { return width * height; }
}

// Thêm Triangle: chỉ tạo class mới, KHÔNG sửa gì cũ
public record Triangle(double base, double height) implements Shape {
    public double area() { return 0.5 * base * height; }
}

public class AreaCalculator {
    public double calculateArea(Shape shape) {
        return shape.area(); // KHÔNG CẦN SỬA khi thêm loại mới
    }
}
```

### How – Cơ chế đạt OCP

1. **Polymorphism + Interface/Abstract class**: như ví dụ trên
2. **Strategy Pattern**: inject behavior thay vì hardcode
3. **Template Method**: define skeleton, để subclass fill in
4. **Decorator**: thêm behavior mà không sửa class gốc

### Real-world Usage
```java
// Discount strategies – thêm loại discount mới không sửa PricingEngine
public interface DiscountPolicy {
    BigDecimal apply(BigDecimal price, Order order);
}

@Component("SEASONAL")
public class SeasonalDiscount implements DiscountPolicy {
    public BigDecimal apply(BigDecimal price, Order order) {
        return price.multiply(new BigDecimal("0.8")); // 20% off
    }
}

@Component("LOYALTY")
public class LoyaltyDiscount implements DiscountPolicy {
    public BigDecimal apply(BigDecimal price, Order order) {
        int points = order.getCustomer().getLoyaltyPoints();
        return price.subtract(new BigDecimal(points / 100));
    }
}

// PricingEngine không thay đổi khi thêm discount mới
@Service
public class PricingEngine {
    private final Map<String, DiscountPolicy> policies;
    public BigDecimal calculate(Order order, String policyName) {
        return policies.get(policyName).apply(order.getBasePrice(), order);
    }
}
```

---

## L – Liskov Substitution Principle (LSP)

### What
> "Objects of a superclass should be replaceable with objects of a subclass without breaking the program."
> — Barbara Liskov, 1987

Nếu S là subtype của T, thì bất kỳ đâu dùng T, thay bằng S vẫn phải đúng về **behavior** (không chỉ về type).

### How – Vi phạm LSP nổi tiếng: Rectangle–Square

```java
class Rectangle {
    protected int width, height;
    void setWidth(int w)  { this.width = w; }
    void setHeight(int h) { this.height = h; }
    int area() { return width * height; }
}

class Square extends Rectangle {
    @Override
    void setWidth(int w)  { this.width = w; this.height = w; } // thay đổi behavior!
    @Override
    void setHeight(int h) { this.width = h; this.height = h; }
}

// Code dùng Rectangle
void stretchWidth(Rectangle r) {
    int originalHeight = r.height;
    r.setWidth(r.width * 2);
    assert r.height == originalHeight; // THẤT BẠI nếu r là Square!
}

stretchWidth(new Rectangle()); // OK
stretchWidth(new Square());    // BREAKS LSP!
```

**Fix**: không dùng inheritance. Dùng interface chung:
```java
interface Shape { int area(); }
record Rectangle(int width, int height) implements Shape {
    public int area() { return width * height; }
}
record Square(int side) implements Shape {
    public int area() { return side * side; }
}
```

### How – Quy tắc LSP (Contract)

| Điều kiện | Quy tắc |
|----------|---------|
| Preconditions (điều kiện đầu vào) | Subclass không được **strengthen** (chặt hơn cha) |
| Postconditions (điều kiện đầu ra) | Subclass không được **weaken** (yếu hơn cha) |
| Invariants | Subclass phải **duy trì** invariant của cha |
| History constraint | Subclass không được thêm state mà cha không cho phép modify |

```java
// Vi phạm: tăng precondition (cha chấp nhận mọi số dương, con từ chối < 100)
class PremiumAccount extends BankAccount {
    @Override
    public void deposit(double amount) {
        if (amount < 100) throw new IllegalArgumentException("Min deposit 100"); // STRICTER!
        super.deposit(amount);
    }
}

// Vi phạm: throw exception mới (cha không khai báo)
class ReadOnlyList<E> extends ArrayList<E> {
    @Override
    public boolean add(E e) {
        throw new UnsupportedOperationException(); // cha không throw này → break LSP!
    }
}
// Fix: đừng extends ArrayList, implement List interface và thực sự là read-only
```

### How – Test LSP
> "Nếu viết unit test cho superclass, tất cả test đó phải pass với subclass."

---

## I – Interface Segregation Principle (ISP)

### What
> "Clients should not be forced to depend on interfaces they do not use."

Tạo nhiều interface nhỏ, chuyên biệt thay vì 1 interface lớn (fat interface).

### How – Vi phạm ISP

```java
// Fat interface – vi phạm ISP
public interface Worker {
    void work();
    void eat();
    void sleep();
    void attendMeeting();
}

// Robot cũng implements Worker nhưng không eat/sleep!
public class Robot implements Worker {
    public void work() { /* OK */ }
    public void eat()  { throw new UnsupportedOperationException(); } // vô nghĩa!
    public void sleep(){ throw new UnsupportedOperationException(); }
    public void attendMeeting() { /* OK */ }
}
```

```java
// ĐÚNG – Interface nhỏ, chuyên biệt
public interface Workable  { void work(); }
public interface Eatable   { void eat(); void sleep(); }
public interface Meetable  { void attendMeeting(); }

public class HumanWorker implements Workable, Eatable, Meetable {
    public void work() { /* ... */ }
    public void eat()  { /* ... */ }
    public void sleep(){ /* ... */ }
    public void attendMeeting() { /* ... */ }
}

public class Robot implements Workable, Meetable { // không cần Eatable
    public void work() { /* ... */ }
    public void attendMeeting() { /* ... */ }
}
```

### How – Role Interface

Thay vì 1 interface lớn, tạo nhiều **role interface** nhỏ:

```java
// Thay vì:
interface UserRepository {
    User findById(Long id);
    List<User> findAll();
    User save(User user);
    void delete(Long id);
    List<User> searchByName(String name);
    List<User> findByStatus(UserStatus status);
    long countByStatus(UserStatus status);
}

// Tách thành role interfaces:
interface UserReader {
    Optional<User> findById(Long id);
    List<User> findAll();
}

interface UserWriter {
    User save(User user);
    void delete(Long id);
}

interface UserSearcher {
    List<User> searchByName(String name);
    List<User> findByStatus(UserStatus status);
}

// Service chỉ phụ thuộc vào interface cần dùng
public class UserProfileService {
    private final UserReader reader; // không cần biết về write hay search
    // ...
}
```

### Real-world Usage
- `Comparable<T>` – chỉ `compareTo()`, không lẫn với sort logic
- `Runnable` – chỉ `run()`, không phải toàn bộ Thread
- `AutoCloseable` – chỉ `close()`
- Spring: `ApplicationEventPublisher`, `MessageSource`... tách nhỏ từ `ApplicationContext`

---

## D – Dependency Inversion Principle (DIP)

### What
> "High-level modules should not depend on low-level modules. Both should depend on abstractions."
> "Abstractions should not depend on details. Details should depend on abstractions."

### How – Vi phạm DIP

```java
// High-level module phụ thuộc vào low-level module cụ thể
public class OrderService {
    private MySQLOrderRepository repo = new MySQLOrderRepository(); // TIGHT COUPLING!
    private SMTPEmailService emailService = new SMTPEmailService();  // TIGHT COUPLING!

    public void placeOrder(Order order) {
        repo.save(order);            // nếu đổi sang PostgreSQL → SỬA OrderService
        emailService.sendConfirmation(order); // nếu đổi sang SendGrid → SỬA OrderService
    }
}
```

```java
// ĐÚNG – phụ thuộc vào abstraction
public interface OrderRepository {
    Order save(Order order);
    Optional<Order> findById(Long id);
}

public interface NotificationService {
    void sendOrderConfirmation(Order order);
}

public class OrderService {
    private final OrderRepository repo;           // abstraction
    private final NotificationService notifier;   // abstraction

    // Constructor injection – dependency được inject từ ngoài
    public OrderService(OrderRepository repo, NotificationService notifier) {
        this.repo = repo;
        this.notifier = notifier;
    }

    public Order placeOrder(Order order) {
        Order saved = repo.save(order);
        notifier.sendOrderConfirmation(saved);
        return saved;
    }
}

// Low-level implementations – có thể swap tự do
@Repository
public class JpaOrderRepository implements OrderRepository { ... }

@Service
public class SendGridNotificationService implements NotificationService { ... }

// Test dễ dàng với mock
@Test
void placeOrder_savesAndNotifies() {
    OrderRepository mockRepo = mock(OrderRepository.class);
    NotificationService mockNotifier = mock(NotificationService.class);
    OrderService service = new OrderService(mockRepo, mockNotifier);
    // ...
}
```

### How – IoC Container (Spring)
DIP là nền tảng của **Inversion of Control (IoC)** và **Dependency Injection (DI)**:

```java
@Service
public class OrderService {
    private final OrderRepository repo;
    private final NotificationService notifier;

    // Spring inject implementation phù hợp tự động
    @Autowired
    public OrderService(OrderRepository repo, NotificationService notifier) {
        this.repo = repo;
        this.notifier = notifier;
    }
}
```

---

## Why – Tại sao cần SOLID?

| Vấn đề không có SOLID | Giải pháp SOLID |
|----------------------|----------------|
| God class – làm mọi thứ | SRP – tách nhỏ |
| Sửa 1 chỗ, vỡ chỗ khác | OCP – extend không modify |
| Subclass break contract cha | LSP – giữ đúng behavior |
| Phụ thuộc method không cần | ISP – interface nhỏ |
| Khó test, khó swap | DIP – depend on abstraction |

---

## Compare – SOLID áp dụng theo mức độ

| Dự án | Áp dụng SOLID mạnh | Chú ý |
|-------|-------------------|-------|
| Enterprise (Spring, JPA) | Rất cần | SRP + DIP qua DI container |
| Library/SDK | Rất cần | OCP + ISP để extensible |
| Script/Tool nhỏ | Ít cần | Over-engineering |
| Microservice | Cần | Mỗi service = 1 responsibility |
| Prototype/PoC | Không cần | Speed > design |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Dễ test (mock interface) | Nhiều class/interface hơn |
| Dễ thay đổi implementation | Có thể over-engineer |
| Loose coupling | Khó trace flow (nhiều indirection) |
| Mỗi class làm 1 việc rõ ràng | Tốn thời gian thiết kế ban đầu |

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Composition over Inheritance**
>
> Keyword: Delegation, Mixin, Decorator pattern, Favor composition, Dependency injection as composition, Trait (Kotlin/Scala), Interface default method as mixin
