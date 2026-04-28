# Composition over Inheritance

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Composition over Inheritance là gì?

**"Favor composition over inheritance"** — nguyên lý từ Gang of Four (Design Patterns, 1994).

- **Inheritance**: class con *là một loại* của class cha (`Dog extends Animal` → Dog IS-A Animal)
- **Composition**: class chứa instance của class khác (`Car has-a Engine` → Car HAS-A Engine)

Nguyên lý khuyến khích dùng **composition** (kết hợp object) thay vì **inheritance** (kế thừa class) để tái sử dụng hành vi — trừ khi IS-A thực sự rõ ràng và LSP được thỏa mãn.

---

## Why – Tại sao nên prefer Composition?

### 1. Fragile Base Class Problem

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

```java
// INHERITANCE – Vấn đề
class InstrumentedList<E> extends ArrayList<E> {
    int addCount = 0;

    @Override public boolean add(E e)                { addCount++; return super.add(e); }
    @Override public boolean addAll(Collection<? extends E> c) {
        addCount += c.size(); return super.addAll(c);
        // BUG! ArrayList.addAll() gọi add() nội bộ → addCount bị tăng gấp đôi
    }
}

// COMPOSITION – Đúng (Forwarding/Delegation)
class InstrumentedList<E> implements List<E> {
    private final List<E> list;   // HAS-A, không IS-A
    int addCount = 0;

    InstrumentedList(List<E> list) { this.list = list; }

    @Override public boolean add(E e) {
        addCount++;
        return list.add(e);    // delegate → không quan tâm ArrayList làm gì nội bộ
    }

    @Override public boolean addAll(Collection<? extends E> c) {
        addCount += c.size();
        return list.addAll(c); // delegate, không gọi add() của mình → đúng!
    }

    // Forwarding tất cả methods khác
    @Override public int size() { return list.size(); }
    @Override public boolean isEmpty() { return list.isEmpty(); }
    // ... (Lombok @Delegate có thể tự sinh)
}

// Dùng:
List<String> instrumented = new InstrumentedList<>(new ArrayList<>());
// Có thể swap sang LinkedList, CopyOnWriteArrayList... tại runtime!
```

---

## How – Mixin qua Interface Default Method (Java 8+)

Mixin = "trộn" nhiều behavior vào một class mà không cần đa kế thừa:

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
