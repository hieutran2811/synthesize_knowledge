# Composition over Inheritance

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Composition over Inheritance là gì?

**"Favor composition over inheritance"** — nguyên lý từ Gang of Four (Design Patterns, 1994).

- **Inheritance**: class con *là một loại* của class cha (`Dog extends Animal` → Dog IS-A Animal)
- **Composition**: class chứa instance của class khác (`Car has-a Engine` → Car HAS-A Engine)

Nguyên lý khuyến khích dùng **composition** (kết hợp object) thay vì **inheritance** (kế thừa class) để tái sử dụng hành vi — trừ khi IS-A thực sự rõ ràng và LSP được thỏa mãn.

> 💡 **Giải thích dễ hiểu — thuê dịch vụ thay vì biến mình thành nhà cung cấp:**
> `Car` cần `Engine` để chạy nhưng Car không phải là một loại Engine. Car giữ một Engine và giao việc cho nó; đó là composition. Quan hệ này cho phép thay động cơ mà không đổi danh tính chiếc xe. Inheritance phù hợp khi class con thật sự là subtype và phải giữ toàn bộ contract của class cha, không chỉ vì muốn mượn vài method.

---

## Why – Tại sao nên prefer Composition?

### 1. Fragile Base Class Problem

> 💡 **Giải thích dễ hiểu — dùng chung ruột máy khiến thay đổi nội bộ lan sang con:**
> Subclass override một method có thể vô tình bị superclass gọi từ method khác. Khi tác giả superclass refactor thứ tự gọi nội bộ, subclass đổi hành vi dù public API không đổi. Giống độ thêm linh kiện trực tiếp vào bộ máy của nhà sản xuất: bản nâng cấp tưởng vô hại có thể làm phần độ hoạt động hai lần hoặc không hoạt động.

```java
class Base {
    int count = 0;
    void add(Object o) { count++; }
    void addAll(Collection<?> c) {
        for (Object o : c) add(o); // gọi add() nội bộ
    }
}

class CountingList extends Base {
    @Override
    void add(Object o) { count++; super.add(o); } // đếm thêm 1
    @Override
    void addAll(Collection<?> c) {
        count += c.size(); super.addAll(c); // đếm thêm size
    }
}

// Sau khi Base thay đổi addAll() để không gọi add() nữa
// → CountingList bị double-count mà không hay biết!
```

### 2. Tight Coupling với Superclass
- Subclass biết chi tiết nội bộ của superclass → vi phạm encapsulation
- Mọi thay đổi trong superclass có thể phá vỡ subclass

### 3. Cố định tại Compile-time
Inheritance tạo quan hệ tĩnh, không thay đổi được tại runtime:
```java
class Logger extends FileWriter { } // chỉ log ra file, không thể đổi sang console tại runtime
```

### 4. Khó Test
Mock/stub superclass phức tạp hơn mock interface.

---

## How – Delegation: Nền tảng của Composition

**Delegation**: thay vì kế thừa hành vi, **chuyển giao (delegate)** công việc cho object khác:

> 💡 **Giải thích dễ hiểu — composition tạo đội, delegation giao nhiệm vụ:**
> Việc `OrderService` có một `PaymentGateway` là composition; khi `placeOrder` gọi `gateway.pay()`, đó là delegation. Object bao ngoài kiểm soát contract, có thể thêm kiểm tra hoặc metrics rồi chuyển việc cho dependency. Nó chỉ phụ thuộc vào API công khai, không phụ thuộc chuỗi lời gọi nội bộ như subclass.

```java
// INHERITANCE – Vấn đề kinh điển từ Effective Java
class InstrumentedSet<E> extends HashSet<E> {
    int addCount = 0;

    @Override public boolean add(E e)                { addCount++; return super.add(e); }
    @Override public boolean addAll(Collection<? extends E> c) {
        addCount += c.size(); return super.addAll(c);
        // BUG! AbstractCollection.addAll() gọi add() cho từng phần tử
        // → dispatch vào overridden add() → addCount bị tăng gấp đôi
    }
}

// COMPOSITION – Đúng (Forwarding/Delegation)
class InstrumentedSet<E> implements Set<E> {
    private final Set<E> set;   // HAS-A, không IS-A
    int addCount = 0;

    InstrumentedSet(Set<E> set) { this.set = set; }

    @Override public boolean add(E e) {
        addCount++;
        return set.add(e);    // delegate → không phụ thuộc lời gọi nội bộ
    }

    @Override public boolean addAll(Collection<? extends E> c) {
        addCount += c.size();
        return set.addAll(c); // gọi thẳng object được bọc, không gọi add() của wrapper
    }

    // Forwarding tất cả methods khác
    @Override public int size() { return set.size(); }
    @Override public boolean isEmpty() { return set.isEmpty(); }
    // ... (Lombok @Delegate có thể tự sinh)
}

// Dùng:
Set<String> instrumented = new InstrumentedSet<>(new HashSet<>());
// Có thể swap sang TreeSet, LinkedHashSet, ConcurrentHashMap.newKeySet()...!
```

---

## How – Mixin qua Interface Default Method (Java 8+)

Mixin = "trộn" nhiều behavior vào một class mà không cần đa kế thừa:

> 💡 **Giải thích dễ hiểu — mixin là bộ kỹ năng dùng kèm, không phải state dùng chung:**
> Default method cho class nhận thêm hành vi nhỏ như `validate()` hoặc `logCreated()` từ nhiều interface. Nó phù hợp với behavior độc lập và ít state; nếu mixin cần nhiều dependency, thứ tự thực thi hoặc state mutable dùng chung, composition bằng object riêng thường rõ ràng và dễ test hơn.

```java
// Mixin interfaces
public interface Auditable {
    default void logCreated(String actor) {
        System.out.println(getClass().getSimpleName() + " created by " + actor);
    }
    default void logUpdated(String actor) {
        System.out.println(getClass().getSimpleName() + " updated by " + actor);
    }
}

public interface Validatable {
    boolean isValid();
    default void validate() {
        if (!isValid()) throw new IllegalStateException(getClass().getSimpleName() + " is invalid");
    }
}

public interface Exportable {
    default String toJson() {
        // simple json export
        return "{}";
    }
}

// Class "trộn" nhiều behavior
public class Order implements Auditable, Validatable, Exportable {
    private List<Item> items;

    @Override
    public boolean isValid() { return items != null && !items.isEmpty(); }

    // Tự động có: logCreated(), logUpdated(), validate(), toJson()
}
```

---

## How – Dependency Injection là Composition

DI (Dependency Injection) bản chất là **composition tại runtime** — inject behavior/dependency từ ngoài:

> 💡 **Giải thích dễ hiểu — constructor là ổ cắm lắp ráp object graph:**
> `OrderService` không tự xây repository hay gateway; nó công bố các “ổ cắm” qua constructor. Composition root hoặc Spring chọn implementation và cắm chúng vào lúc khởi động. DI không tự tạo abstraction tốt, nhưng nó làm quan hệ composition tường minh và cho phép test truyền fake/mock dễ dàng.

```java
// Thay vì kế thừa Logger, inject nó vào
public class OrderService {
    private final OrderRepository repository;    // composited
    private final PaymentGateway payment;        // composited
    private final NotificationService notifier;  // composited
    private final AuditLogger logger;            // composited

    // Tất cả đều có thể swap tại runtime qua DI container
    public OrderService(OrderRepository repo, PaymentGateway payment,
                        NotificationService notifier, AuditLogger logger) {
        this.repository = repo;
        this.payment = payment;
        this.notifier = notifier;
        this.logger = logger;
    }
}
```

---

## How – Strategy Pattern = Composition of Behavior

> 💡 **Giải thích dễ hiểu — biến thuật toán thành một linh kiện thay được:**
> Thay vì tạo `AscendingSorter`, `DescendingSorter` bằng inheritance, `Sorter` giữ một `Comparator` mô tả phần hành vi thay đổi. Chuyển strategy giống thay đầu mũi khoan trên cùng một máy: workflow chung giữ nguyên, thuật toán cụ thể có thể chọn ở runtime.

```java
// Behavior (strategy) là object → có thể swap tại runtime
public class Sorter<T> {
    private Comparator<T> strategy; // composited behavior

    public Sorter(Comparator<T> strategy) { this.strategy = strategy; }

    // Đổi strategy tại runtime
    public void setStrategy(Comparator<T> strategy) { this.strategy = strategy; }

    public List<T> sort(List<T> items) {
        List<T> sorted = new ArrayList<>(items);
        sorted.sort(strategy);
        return sorted;
    }
}

// Dùng
Sorter<String> sorter = new Sorter<>(String::compareTo);
sorter.sort(names);

sorter.setStrategy(Comparator.reverseOrder()); // swap tại runtime!
sorter.sort(names);
```

---

## Components – Khi nào THỰC SỰ nên dùng Inheritance?

Inheritance đúng chỗ khi thỏa mãn **cả 3 điều kiện**:

1. **IS-A thực sự**: `Dog` IS-A `Animal` (không phải giả)
2. **LSP thỏa mãn**: subclass thay thế được superclass không phá vỡ program
3. **Subclass KHÔNG cần ẩn method của superclass**: không throw `UnsupportedOperationException`

> 💡 **Giải thích dễ hiểu — “favor” không có nghĩa “cấm”:**
> Inheritance vẫn tốt cho hierarchy có contract ổn định như exception, framework template hoặc sealed domain type. Dấu hiệu xấu là subclass chỉ muốn vài method, phải vô hiệu hóa method cha, hoặc cần thay superclass theo cấu hình. Khi đó HAS-A và delegation thường mô tả quan hệ trung thực hơn.

```java
// ĐÚNG – inheritance hợp lý
abstract class HttpMessageConverter<T> {
    abstract boolean canRead(Class<?> clazz, MediaType mediaType);
    abstract T read(Class<T> clazz, HttpInputMessage inputMessage);
    // common logic...
}
class MappingJackson2HttpMessageConverter extends HttpMessageConverter<Object> { ... }
class StringHttpMessageConverter extends HttpMessageConverter<String> { ... }
```

---

## Compare – Inheritance vs Composition

| Tiêu chí | Inheritance | Composition |
|---------|------------|------------|
| Quan hệ | IS-A | HAS-A |
| Coupling | Chặt | Lỏng |
| Flexibility | Compile-time (cố định) | Runtime (có thể swap) |
| Test | Khó mock superclass | Dễ mock dependency |
| Code reuse | Tự động (implicit) | Explicit delegation |
| Encapsulation | Subclass biết nội bộ cha | Không biết nội bộ |
| Fragile Base Class | Có nguy cơ | Không |
| Multiple behavior | Hạn chế (single inheritance) | Tự do (nhiều object) |

---

## Trade-offs

| Composition | Inheritance |
|------------|------------|
| (+) Loose coupling | (+) Ít boilerplate (method tự kế thừa) |
| (+) Dễ test | (+) IS-A rõ ràng, dễ đọc |
| (+) Flexible tại runtime | (+) Polymorphism mạnh |
| (-) Nhiều delegation code hơn | (-) Fragile Base Class |
| (-) Boilerplate forwarding method | (-) Tight coupling |
| (-) Phức tạp hơn khi đọc flow | (-) Khó thay đổi hierarchy |

---

## Real-world Usage (Production)

### 1. Java I/O – Composition (Decorator Pattern)

> 💡 **Giải thích dễ hiểu — bọc thêm năng lực từng lớp:**
> `FileInputStream` cung cấp byte từ file, `InputStreamReader` giải mã byte thành ký tự, `BufferedReader` thêm buffer. Mỗi wrapper giữ cùng contract cần thiết và bọc object bên trong, nên các năng lực được xếp như nhiều lớp áo. Đây là composition kết hợp Decorator: mở rộng hành vi mà không sửa hoặc tạo cây subclass cho mọi tổ hợp.
```java
// BufferedReader WRAPS FileReader, không EXTENDS
BufferedReader reader = new BufferedReader(
    new InputStreamReader(
        new FileInputStream("file.txt"), StandardCharsets.UTF_8
    )
);
// Có thể thay bằng socket stream, string stream... – flexible!
```

### 2. Spring Security – Filter Chain (Composition)
```java
// Mỗi filter là 1 class độc lập, chained thay vì hierarchy
http
    .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
    .addFilterAfter(auditFilter, JwtFilter.class);
// Thêm/bỏ filter không ảnh hưởng filter khác
```

### 3. Effective Java – Wrapper Class Pattern
```java
// Joshua Bloch khuyến nghị: dùng ForwardingSet thay vì extends HashSet
public class ForwardingSet<E> implements Set<E> {
    private final Set<E> s;
    public ForwardingSet(Set<E> s) { this.s = s; }
    public boolean add(E e) { return s.add(e); }
    public boolean addAll(Collection<? extends E> c) { return s.addAll(c); }
    // ... forward tất cả
}

public class InstrumentedSet<E> extends ForwardingSet<E> {
    private int addCount = 0;
    @Override public boolean add(E e) { addCount++; return super.add(e); }
    @Override public boolean addAll(Collection<? extends E> c) {
        addCount += c.size(); return super.addAll(c);
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Collections Framework** (deep dive)
>
> Keyword: ArrayList internals (dynamic array, capacity, growth factor), LinkedList (doubly-linked, Node), HashMap internals (hash function, bucket, collision resolution, treeify threshold Java 8), TreeMap (Red-Black tree), ConcurrentHashMap, Fail-fast vs Fail-safe iterator, Comparable vs Comparator, Collections utility class
