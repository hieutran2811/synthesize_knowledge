# Abstraction (Trừu Tượng)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Abstraction là gì?

**Abstraction** *(trừu tượng hóa — chỉ phơi bày "làm gì", giấu đi "làm thế nào")* là quá trình ẩn đi **chi tiết cài đặt (implementation details)** *(chi tiết cách viết code bên trong)*, chỉ để lộ ra **hành vi cần thiết (what to do)** — không phải cách làm (how to do).

Mục tiêu: tạo ra **ngưỡng giữa "điều client cần biết"** *(client — bên gọi/sử dụng, không nhất thiết là trình duyệt)* và **"chi tiết bên trong"**.

**2 cơ chế abstraction trong Java:**
1. **Abstract Class** *(lớp trừu tượng)* – lớp trừu tượng
2. **Interface** *(giao diện — bản hợp đồng khai báo "phải làm được gì")* – hợp đồng/giao thức

> 💡 **Giải thích dễ hiểu:**
> Abstraction giống việc bạn **lái ô tô mà không cần biết động cơ hoạt động thế nào**. Nhà sản xuất chỉ "phơi ra" cho bạn vô-lăng, chân ga, chân phanh (hành vi cần thiết) và giấu đi toàn bộ chuyện xăng nổ, pít-tông chạy ra sao (chi tiết cài đặt). Bạn — "client" — chỉ cần biết *đạp ga thì xe đi*, không cần biết *bằng cách nào*. Nhờ vậy hãng xe có thể thay động cơ xăng bằng động cơ điện mà bạn vẫn lái y như cũ. Abstraction trong code cũng vậy: che phần phức tạp, chỉ chừa ra "các nút bấm" cần thiết.

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

> 💡 **Giải thích dễ hiểu — Abstract Class:**
> Lớp trừu tượng giống một **bản thiết kế nhà chưa hoàn chỉnh**: đã vẽ sẵn phần khung, móng, hệ thống chung (concrete method — phương thức đã có sẵn thân hàm), nhưng chừa trống vài chỗ ghi "chủ nhà tự quyết" như màu sơn, kiểu cửa (abstract method — phương thức chỉ khai tên, chưa có thân). Vì bản vẽ còn chỗ trống nên **không thể xây trực tiếp** từ nó (`new Animal()` báo lỗi) — bạn phải tạo một bản vẽ con hoàn thiện nốt các chỗ trống (lớp `Dog` điền `makeSound()`) rồi mới xây được.

**Quy tắc:**
- Không thể **instantiate** *(tạo thể hiện — tạo object bằng `new`)*: `new Animal()` → **compile error** *(lỗi lúc biên dịch)*
- Có thể có **constructor** *(hàm khởi tạo)* (gọi qua `super()` trong **subclass** *(lớp con)*)
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

**Template Method** *(mẫu phương thức khuôn mẫu)* là mẫu thiết kế trong đó lớp cha định nghĩa sẵn **bộ khung các bước** (thứ tự cố định), còn để lớp con điền chi tiết từng bước.

> 💡 **Giải thích dễ hiểu — Template Method:**
> Giống **công thức làm bánh in sẵn trên bao bì**: các bước và thứ tự đã cố định (trộn bột → thêm nhân → nướng → để nguội), lớp cha "khóa" trình tự này lại bằng `final` để không ai đảo lộn. Nhưng vài bước để trống cho bạn tùy biến: "chọn loại nhân tùy khẩu vị" (`fetchData`, `process`, `write` — abstract, lớp con bắt buộc điền). Ngoài ra có bước tùy chọn như "trang trí nếu thích" (`cleanup` — hook method, lớp con muốn thì override, không thì thôi). Nhờ đó khung xử lý dùng chung một lần, mỗi biến thể (CSV, JSON...) chỉ khác ở vài chỗ được chừa trống.

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
| Java 8 | + `default` methods *(phương thức mặc định — có sẵn thân, lớp con không bắt buộc viết lại)*, + `static` methods |
| Java 9 | + `private` methods, + `private static` methods |

> 💡 **Giải thích dễ hiểu — vì sao interface tiến hóa qua các đời Java:**
> Ban đầu interface giống một **bản hợp đồng thuần túy**: chỉ liệt kê "bên ký phải làm được A, B, C" chứ không cho sẵn cách làm. Nhưng vấn đề nảy sinh: khi một interface đã có hàng nghìn lớp implement mà nay muốn thêm một phương thức mới, thì cả nghìn lớp đó đồng loạt vỡ (vì chưa lớp nào viết phương thức mới). Java 8 thêm **`default` method** để cứu: interface được kèm luôn "cách làm mặc định", ai không thích thì override, ai kệ thì dùng bản mặc định — nhờ vậy thêm phương thức mới mà không phá vỡ code cũ. Giống hợp đồng bổ sung điều khoản mới nhưng ghi kèm "nếu không thỏa thuận khác thì áp dụng mức mặc định này".

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

> 💡 **Giải thích dễ hiểu — Diamond Problem:**
> **Diamond Problem** *(vấn đề kim cương)* xảy ra khi lớp `D` thừa hưởng cùng một phương thức `hello()` qua hai đường khác nhau (B và C, cả hai lại cùng từ A) — vẽ ra thành hình thoi/kim cương. Câu hỏi: `D.hello()` nên chạy bản của B hay của C? Máy không tự đoán được.
> Ví von: bạn hỏi đường tới cùng một đích nhưng **hai người chỉ hai lối khác nhau** — bạn buộc phải tự chọn nghe ai. Java bắt lớp `D` phải nói rõ chọn ai bằng cú pháp `B.super.hello()`, nếu im lặng thì báo lỗi ngay lúc biên dịch (an toàn hơn C++ vốn để tình trạng nhập nhằng âm thầm).

**Quy tắc ưu tiên khi conflict:**
1. **Class/superclass wins** *(lớp cụ thể thắng)* – concrete method trong class luôn thắng
2. **More specific interface wins** *(interface cụ thể hơn thắng)* – B extends A → B.hello() thắng A.hello()
3. **Nếu vẫn ambiguous** *(vẫn nhập nhằng)* – phải override tường minh

---

### Marker Interface vs Annotation

**Marker Interface** *(interface đánh dấu — không có method, chỉ để "dán nhãn" cho class)*: interface không có method, chỉ đánh dấu:
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

**Functional Interface** *(interface hàm — chỉ có đúng 1 phương thức trừu tượng)* có **đúng 1 abstract method** — có thể dùng với **lambda** *(biểu thức hàm ngắn gọn viết thay cho cả một class)*:

> 💡 **Giải thích dễ hiểu — Functional Interface & lambda:**
> Vì interface chỉ có đúng một việc chưa làm, nên khi bạn đưa cho nó một đoạn code, không có gì phải nhập nhằng "đoạn này ứng với method nào" — chắc chắn là method duy nhất đó. Nhờ vậy Java cho phép viết cực gọn bằng lambda thay vì tạo cả một class. Ví von: một cái **remote chỉ có đúng một nút** — bạn không cần dán nhãn nút nào làm gì, bấm là biết ngay nó làm việc gì. `@FunctionalInterface` là dòng nhắc compiler kiểm tra hộ "interface này đúng là chỉ có một nút".

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

1. **Giảm complexity** *(giảm độ phức tạp)*: client chỉ cần biết "gọi `pay(amount)`", không cần biết gateway dùng HTTP hay gRPC
2. **Loose coupling** *(kết nối lỏng — các thành phần ít phụ thuộc nhau)*: thay `StripeGateway` bằng `PayPalGateway` mà không sửa **caller** *(bên gọi)*
3. **Testability** *(dễ kiểm thử)*: inject **mock/stub** *(đối tượng giả dùng để test)* thay vì real implementation
4. **Separation of concerns** *(tách bạch mối quan tâm)*: "what" tách khỏi "how"
5. **Extensibility** *(khả năng mở rộng)*: thêm implementation mới không ảnh hưởng code cũ

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
