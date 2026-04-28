# Abstraction (Trừu Tượng)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Abstraction là gì?

**Abstraction** là quá trình ẩn đi **chi tiết cài đặt (implementation details)**, chỉ để lộ ra **hành vi cần thiết (what to do)** — không phải cách làm (how to do).

Mục tiêu: tạo ra **ngưỡng giữa "điều client cần biết"** và **"chi tiết bên trong"**.

**2 cơ chế abstraction trong Java:**
1. **Abstract Class** – lớp trừu tượng
2. **Interface** – hợp đồng/giao thức

---

## How – Abstract Class

### Đặc điểm cốt lõi

```java
public abstract class Animal {
    private String name; // field bình thường

    // Constructor – vẫn có, nhưng chỉ gọi qua super() từ subclass
    public Animal(String name) { this.name = name; }

    // Concrete method – có implementation
    public String getName() { return name; }

    public void breathe() { System.out.println(name + " is breathing"); }

    // Abstract method – BUỘC subclass phải implement
    public abstract void makeSound();

    // Abstract method với return type
    public abstract double metabolicRate();
}
```

**Quy tắc:**
- Không thể instantiate: `new Animal()` → **compile error**
- Có thể có constructor (gọi qua `super()` trong subclass)
- Có thể có cả abstract và concrete method
- Có thể có fields (instance + static)
- Nếu subclass không implement tất cả abstract method → subclass cũng phải `abstract`

```java
public class Dog extends Animal {
    private String breed;

    public Dog(String name, String breed) {
        super(name); // gọi Animal constructor
        this.breed = breed;
    }

    @Override
    public void makeSound() { System.out.println(getName() + " barks: Woof!"); }

    @Override
    public double metabolicRate() { return 70 * Math.pow(4.5, 0.75); } // Kleiber's law
}
```

### Template Method Pattern – Dùng tự nhiên với Abstract Class

```java
public abstract class DataExporter {

    // Template method – định nghĩa skeleton, gọi các bước theo thứ tự
    // final: không cho subclass thay đổi skeleton
    public final void export(String destination) {
        List<Object> data = fetchData();         // abstract – subclass implement
        List<Object> processed = process(data);  // abstract
        validate(processed);                     // concrete – dùng chung
        write(processed, destination);           // abstract
        cleanup();                               // hook – có thể override hoặc không
    }

    protected abstract List<Object> fetchData();
    protected abstract List<Object> process(List<Object> data);
    protected abstract void write(List<Object> data, String destination);

    // Concrete method – logic chung
    private void validate(List<Object> data) {
        if (data == null || data.isEmpty())
            throw new IllegalStateException("No data to export");
    }

    // Hook method – subclass có thể override nếu cần, mặc định không làm gì
    protected void cleanup() {}
}

// Subclass chỉ cần điền phần khác biệt
public class CsvExporter extends DataExporter {
    @Override
    protected List<Object> fetchData() { return database.query("SELECT * FROM orders"); }

    @Override
    protected List<Object> process(List<Object> data) { return transform(data); }

    @Override
    protected void write(List<Object> data, String dest) { writeCsv(data, dest); }

    @Override
    protected void cleanup() { tempFiles.forEach(File::delete); } // override hook
}
```

---

## How – Interface

### Evolution qua các phiên bản Java

| Java version | Interface features |
|-------------|-------------------|
| Java ≤ 7 | `public abstract` methods, `public static final` constants |
| Java 8 | + `default` methods, + `static` methods |
| Java 9 | + `private` methods, + `private static` methods |

```java
public interface PaymentGateway {
    // --- Java ≤ 7 ---
    // Hằng số – ngầm định public static final
    int MAX_RETRY = 3;

    // Abstract method – ngầm định public abstract
    boolean charge(String customerId, BigDecimal amount);
    void refund(String transactionId);
    TransactionStatus getStatus(String transactionId);

    // --- Java 8 ---
    // default method – có implementation, subclass có thể override
    default boolean chargeWithRetry(String customerId, BigDecimal amount) {
        for (int i = 0; i < MAX_RETRY; i++) {
            if (charge(customerId, amount)) return true;
        }
        return false;
    }

    // static method – utility liên quan đến interface, không kế thừa
    static PaymentGateway noOp() {
        return new PaymentGateway() {
            public boolean charge(String c, BigDecimal a) { return true; }
            public void refund(String t) {}
            public TransactionStatus getStatus(String t) { return TransactionStatus.SUCCESS; }
        };
    }

    // --- Java 9 ---
    // private method – tái sử dụng logic giữa default methods
    private void logAttempt(int attempt, String customerId) {
        System.out.println("Attempt " + attempt + " for customer " + customerId);
    }
}
```

---

### Diamond Problem với Default Methods

```java
interface A {
    default void hello() { System.out.println("A"); }
}

interface B extends A {
    default void hello() { System.out.println("B"); }
}

interface C extends A {
    default void hello() { System.out.println("C"); }
}

class D implements B, C {
    // COMPILE ERROR nếu không override – ambiguous!

    @Override
    public void hello() {
        B.super.hello(); // tường minh chọn B.hello()
    }
}
```

**Quy tắc ưu tiên khi conflict:**
1. **Class/superclass wins** – concrete method trong class luôn thắng
2. **More specific interface wins** – B extends A → B.hello() thắng A.hello()
3. **Nếu vẫn ambiguous** – phải override tường minh

---

### Marker Interface vs Annotation

**Marker Interface**: interface không có method, chỉ đánh dấu:
```java
// JDK built-in markers
public interface Serializable {}   // đánh dấu có thể serialize
public interface Cloneable {}      // đánh dấu Object.clone() hợp lệ
public interface RandomAccess {}   // đánh dấu List hỗ trợ random access O(1)

// Kiểm tra: instanceof
if (obj instanceof Serializable) { serialize(obj); }
```

**Annotation**: thay thế hiện đại cho marker interface – mang thêm metadata:
```java
@interface Auditable { String auditLevel() default "INFO"; }

// Annotation có thể mang thông tin; marker interface chỉ yes/no
@Auditable(auditLevel = "WARN")
class SensitiveOperation { }
```

| | Marker Interface | Annotation |
|--|-----------------|-----------|
| Kiểm tra | `instanceof` | Reflection |
| Metadata | Không | Có |
| Compile check | Có (type system) | Giới hạn |
| Dùng với generics | Có: `<T extends Serializable>` | Không |
| Modern trend | Legacy | Preferred |

---

### Functional Interface

Interface có **đúng 1 abstract method** — có thể dùng với lambda:

```java
@FunctionalInterface  // annotation tùy chọn, nhưng nên dùng để compiler kiểm tra
public interface Transformer<T, R> {
    R transform(T input);

    // default và static methods không vi phạm @FunctionalInterface
    default <V> Transformer<T, V> andThen(Transformer<R, V> after) {
        return input -> after.transform(this.transform(input));
    }
}

// Dùng với lambda
Transformer<String, Integer> length = String::length;
Transformer<String, String> upper = String::toUpperCase;

Transformer<String, Integer> upperLength = upper.andThen(length);
System.out.println(upperLength.transform("hello")); // 5
```

---

## Components – Abstract Class vs Interface: Decision Matrix

| Tiêu chí | Abstract Class | Interface |
|---------|---------------|-----------|
| Kế thừa | `extends` (1 class) | `implements` (nhiều interface) |
| Quan hệ | "is-a" | "can-do" / "has capability" |
| Constructor | Có | Không |
| Instance fields | Có (bất kỳ modifier) | Không (chỉ `public static final`) |
| Method | Abstract + Concrete | Abstract + `default` + `static` + `private` (Java 9) |
| State (trạng thái) | Có thể lưu state | Không lưu state (stateless) |
| Access modifier method | Bất kỳ | `public` (ngầm định) |
| Sử dụng | Chia sẻ code, skeleton | Định nghĩa contract, capability |

### Khi nào chọn cái nào?

**Dùng Abstract Class khi:**
- Muốn chia sẻ code giữa các class liên quan chặt chẽ (closely related)
- Cần fields hoặc state chung
- Muốn định nghĩa template method (skeleton algorithm)
- Muốn dùng `protected` / `package-private` methods
- Các subclass có quan hệ "là một loại" rõ ràng

**Dùng Interface khi:**
- Muốn định nghĩa contract không quan tâm đến implementation
- Class cần "implement" nhiều khả năng (multiple capabilities)
- Muốn loose coupling tối đa (dependency injection)
- Tạo functional interface để dùng với lambda
- Class từ các hierarchy khác nhau cần chung hành vi

---

## Why – Tại sao cần Abstraction?

1. **Giảm complexity**: client chỉ cần biết "gọi `pay(amount)`", không cần biết gateway dùng HTTP hay gRPC
2. **Loose coupling**: thay `StripeGateway` bằng `PayPalGateway` mà không sửa caller
3. **Testability**: inject mock/stub thay vì real implementation
4. **Separation of concerns**: "what" tách khỏi "how"
5. **Extensibility**: thêm implementation mới không ảnh hưởng code cũ

---

## When – Khi nào thiết kế abstraction?

**Nên tạo abstraction khi:**
- Có ≥ 2 implementation khác nhau của cùng hành vi
- Cần test qua mock/stub
- Muốn swap implementation tại runtime (DI container)
- Public API cần stable mà internal có thể thay đổi

**Không nên tạo abstraction sớm:**
- Rule of Three: chỉ extract abstraction khi đã có 3+ case tương tự
- YAGNI (You Aren't Gonna Need It): đừng abstraction cho tương lai giả định
- 1 class + 1 interface không có thêm implementation = over-engineering

---

## Compare – Abstraction Levels

### Level 1: Interface Contract
```java
interface Repository<T, ID> {
    Optional<T> findById(ID id);
    List<T> findAll();
    T save(T entity);
    void delete(ID id);
}
```

### Level 2: Abstract Base + Interface
```java
abstract class AbstractRepository<T, ID> implements Repository<T, ID> {
    // Concrete shared logic
    protected final EntityManager em;

    AbstractRepository(EntityManager em) { this.em = em; }

    @Override
    public void delete(ID id) {
        findById(id).ifPresent(em::remove); // dùng findById abstract
    }
}
```

### Level 3: Concrete Implementation
```java
@Repository
class UserRepository extends AbstractRepository<User, Long> {
    @Override
    public Optional<User> findById(Long id) { return Optional.ofNullable(em.find(User.class, id)); }

    @Override
    public List<User> findAll() { return em.createQuery("SELECT u FROM User u", User.class).getResultList(); }

    @Override
    public User save(User user) { return em.merge(user); }
}
```

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Giảm coupling | Thêm tầng indirection → khó trace code |
| Dễ test | Over-abstraction → class/interface không cần thiết |
| Swap implementation dễ | Giảm performance (vtable lookup, interface dispatch) |
| Ổn định API | Thay đổi interface → break tất cả implementors |
| Multiple interface OK | `default` method conflict cần giải quyết thủ công |

---

## Real-world Usage (Production)

### 1. Repository Pattern (Spring Data)
```java
// Interface – abstraction cho data access
public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);
    List<User> findByStatus(UserStatus status);
}

// Spring Data tự generate implementation → không cần viết code
// Test: dùng @DataJpaTest hoặc mock UserRepository
```

### 2. Service Layer Abstract + Concrete
```java
// Abstract base cung cấp audit logging, transaction, metrics chung
public abstract class BaseService {
    private final AuditLogger auditLogger;
    private final MeterRegistry meterRegistry;

    protected <T> T executeWithAudit(String operation, Supplier<T> action) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            T result = action.get();
            auditLogger.log(operation, "SUCCESS");
            return result;
        } catch (Exception e) {
            auditLogger.log(operation, "FAILURE: " + e.getMessage());
            throw e;
        } finally {
            sample.stop(meterRegistry.timer("service.operation", "name", operation));
        }
    }
}

@Service
public class PaymentService extends BaseService {
    public PaymentResult processPayment(PaymentRequest req) {
        return executeWithAudit("PROCESS_PAYMENT", () -> {
            // business logic
            return gateway.charge(req);
        });
    }
}
```

### 3. Plugin Architecture với Interface
```java
// Core module định nghĩa contract
public interface NotificationChannel {
    void send(Notification notification);
    boolean supports(NotificationType type);
}

// Plugin modules implement:
@Component
class EmailChannel implements NotificationChannel {
    public void send(Notification n) { emailService.send(n); }
    public boolean supports(NotificationType t) { return t == EMAIL; }
}

@Component
class SlackChannel implements NotificationChannel {
    public void send(Notification n) { slackClient.post(n); }
    public boolean supports(NotificationType t) { return t == SLACK; }
}

// Core chọn channel đúng mà không biết implementation
@Service
class NotificationService {
    private final List<NotificationChannel> channels;

    void send(Notification notification) {
        channels.stream()
            .filter(c -> c.supports(notification.getType()))
            .forEach(c -> c.send(notification));
    }
}
```

### 4. Abstract Class cho HTTP Client Retry
```java
public abstract class RetryableHttpClient {
    private final int maxRetries = 3;
    private final Duration backoff = Duration.ofSeconds(1);

    // Template method
    public final <T> T get(String url, Class<T> responseType) {
        for (int attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                return doGet(url, responseType); // abstract
            } catch (TransientException e) {
                if (attempt == maxRetries) throw e;
                sleep(backoff.multipliedBy(attempt));
            }
        }
        throw new IllegalStateException("unreachable");
    }

    protected abstract <T> T doGet(String url, Class<T> type) throws TransientException;
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Kết thúc 4 tính chất OOP. Chủ đề kế tiếp trong OOP nâng cao:
>
> **SOLID Principles** – 5 nguyên lý thiết kế OOP:
> - **S**ingle Responsibility Principle
> - **O**pen/Closed Principle
> - **L**iskov Substitution Principle (liên quan chặt đến Inheritance)
> - **I**nterface Segregation Principle (liên quan chặt đến Abstraction)
> - **D**ependency Inversion Principle (liên quan chặt đến Interface)
>
> Sau đó: **Composition over Inheritance**, **Design Patterns** (GoF 23 patterns nhóm theo Creational/Structural/Behavioral)
