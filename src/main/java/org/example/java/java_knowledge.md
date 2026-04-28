# Tổng Hợp Kiến Thức Java

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Java Overview

### What – Java là gì?
Java là ngôn ngữ lập trình **hướng đối tượng**, **strongly typed**, **compiled + interpreted**, được Sun Microsystems phát triển năm 1995. Triết lý: **"Write Once, Run Anywhere" (WORA)**.

### How – Đặc điểm
- Strongly typed (kiểu tĩnh, kiểm tra tại compile-time)
- Garbage Collected (quản lý bộ nhớ tự động)
- Multi-threaded built-in
- Platform-independent qua JVM
- Hỗ trợ OOP, Generics, Lambda (Java 8+), Records (Java 16+)

### How – Hoạt động
```
Source code (.java)
    ↓ javac (compiler)
Bytecode (.class)
    ↓ JVM (Just-In-Time Compiler)
Machine code (native)
```

### Why – Tại sao dùng Java?
- Chạy trên mọi nền tảng có JVM
- Hệ sinh thái khổng lồ (Maven, Spring, Hibernate...)
- Quản lý bộ nhớ tự động, tránh memory leak thủ công
- Cộng đồng lớn, nhiều tài liệu

### Components – JDK / JRE / JVM

| Thành phần | Là gì | Chứa gì |
|-----------|-------|---------|
| **JVM** | Java Virtual Machine | Interpreter + JIT Compiler + GC + Runtime |
| **JRE** | Java Runtime Environment | JVM + Standard Libraries |
| **JDK** | Java Development Kit | JRE + Compiler (javac) + Tools (javadoc, jar...) |

> JDK ⊃ JRE ⊃ JVM

### Compare – Java vs các ngôn ngữ khác

| | Java | C++ | Python | Kotlin |
|--|------|-----|--------|--------|
| Quản lý bộ nhớ | GC | Thủ công | GC | GC |
| Performance | Cao | Rất cao | Trung bình | Cao |
| Cú pháp | Verbose | Phức tạp | Ngắn gọn | Ngắn gọn |
| Platform | JVM | Native | Interpreter | JVM |

### Trade-offs
- (+) Portability, mature ecosystem, strong typing
- (-) Verbose, JVM startup time, memory footprint lớn hơn native

### Real-world Usage
- Backend: Spring Boot, Quarkus, Micronaut
- Android (pre-Kotlin era)
- Big Data: Hadoop, Spark (viết bằng Java/Scala)
- Enterprise: Banking, Insurance systems

### Ghi chú – Chủ đề tiếp theo
> JVM internals, ClassLoader, JIT, Bytecode, GC algorithms

---

## 2. OOP

### What – OOP là gì?
OOP (Object-Oriented Programming) là mô hình lập trình tổ chức code xung quanh **đối tượng (object)** — thực thể kết hợp **dữ liệu (field)** và **hành vi (method)**.

### How – 4 Tính chất OOP

#### 1. Encapsulation (Đóng gói)
Ẩn nội bộ, chỉ lộ ra interface cần thiết qua `getter/setter` hoặc `public` methods.
```java
public class BankAccount {
    private double balance; // ẩn

    public double getBalance() { return balance; } // lộ
    public void deposit(double amount) {
        if (amount > 0) balance += amount;
    }
}
```

#### 2. Inheritance (Kế thừa)
Class con (`subclass`) tái sử dụng và mở rộng class cha (`superclass`).
```java
class Animal {
    void eat() { System.out.println("eating"); }
}
class Dog extends Animal {
    void bark() { System.out.println("woof"); }
}
```
> Java chỉ hỗ trợ **single inheritance** với class, nhưng **multiple inheritance** với interface.

#### 3. Polymorphism (Đa hình)
Cùng một method, hành vi khác nhau tùy đối tượng.

- **Compile-time** (Static): Method Overloading
```java
void print(int x) {}
void print(String s) {}
```
- **Runtime** (Dynamic): Method Overriding
```java
Animal a = new Dog();
a.sound(); // gọi Dog.sound(), không phải Animal.sound()
```

#### 4. Abstraction (Trừu tượng)
Ẩn chi tiết cài đặt, chỉ hiện ra "what to do", không "how to do".
- **Abstract class**: có thể có cả abstract và concrete method
- **Interface**: contract thuần túy (Java 8+ có `default` method)

```java
interface Shape {
    double area(); // abstract
    default void describe() { System.out.println("I am a shape"); }
}
```

### Why – Tại sao dùng OOP?
- Code tái sử dụng (Inheritance, Composition)
- Dễ bảo trì (Encapsulation)
- Dễ mở rộng (Polymorphism, Open/Closed Principle)
- Model gần với thực tế

### Compare – Abstract Class vs Interface

| | Abstract Class | Interface |
|--|---------------|-----------|
| Kế thừa | `extends` (1 class) | `implements` (nhiều) |
| Constructor | Có | Không |
| Fields | Instance fields | `public static final` |
| Method | Abstract + Concrete | Abstract + `default` + `static` |
| Khi dùng | "Is-a" relationship | "Can-do" capability |

### Trade-offs
- (+) Tái sử dụng, mô hình hóa rõ ràng
- (-) Over-engineering với class hierarchy sâu; Inheritance làm tight coupling

### Real-world Usage
- Spring Bean: class implement interface `Service`
- Java Collections: `List` (interface) → `ArrayList`, `LinkedList` (implementation)

### Ghi chú – Chủ đề tiếp theo
> SOLID principles, Composition over Inheritance, Design Patterns

---

## 3. Data Types & Variables

### What
Java có **8 primitive types** và **Reference types** (Object, Array, String...).

### How – Primitive Types

| Type | Size | Default | Range |
|------|------|---------|-------|
| `byte` | 1 byte | 0 | -128 → 127 |
| `short` | 2 bytes | 0 | -32768 → 32767 |
| `int` | 4 bytes | 0 | -2^31 → 2^31-1 |
| `long` | 8 bytes | 0L | -2^63 → 2^63-1 |
| `float` | 4 bytes | 0.0f | IEEE 754 |
| `double` | 8 bytes | 0.0d | IEEE 754 |
| `char` | 2 bytes | '\u0000' | 0 → 65535 (Unicode) |
| `boolean` | ~1 bit | false | true/false |

### How – Variable Scopes
```java
class Foo {
    static int classVar;    // class-level (static)
    int instanceVar;        // instance-level

    void method() {
        int localVar = 10;  // method-level
        // localVar chỉ tồn tại trong method này
    }
}
```

### How – Autoboxing / Unboxing
Java tự động convert giữa primitive và Wrapper class:
```java
Integer x = 5;      // autoboxing: int → Integer
int y = x;          // unboxing: Integer → int
```
> **Cảnh báo**: So sánh `Integer` với `==` so sánh reference, dùng `.equals()`.
> `Integer.valueOf(127) == Integer.valueOf(127)` → true (cache -128..127)
> `Integer.valueOf(128) == Integer.valueOf(128)` → **false**

### Compare – `var` (Java 10+ Local Variable Type Inference)
```java
var list = new ArrayList<String>(); // compiler tự infer type
```
Chỉ dùng được cho **local variable**, không dùng cho field, parameter, return type.

### Trade-offs
- Primitive: nhanh hơn, không null
- Wrapper: có thể null, dùng được với Collections, Generics

### Real-world Usage
- Dùng `long` cho ID (tránh tràn với int), `BigDecimal` cho tiền tệ (tránh floating-point error)

---

## 4. Control Flow

### What
Điều khiển luồng thực thi chương trình.

### How – Câu lệnh điều kiện
```java
// if-else
if (x > 0) { ... } else if (x == 0) { ... } else { ... }

// switch (truyền thống)
switch (day) {
    case 1: System.out.println("Mon"); break;
    default: System.out.println("Other");
}

// switch expression (Java 14+)
String result = switch (day) {
    case 1 -> "Mon";
    case 2 -> "Tue";
    default -> "Other";
};
```

### How – Vòng lặp
```java
// for
for (int i = 0; i < 10; i++) { }

// for-each (enhanced for)
for (String item : list) { }

// while
while (condition) { }

// do-while (thực thi ít nhất 1 lần)
do { } while (condition);
```

### How – break, continue, return
- `break`: thoát vòng lặp/switch ngay lập tức
- `continue`: bỏ qua lần lặp hiện tại, sang lần tiếp theo
- `return`: thoát khỏi method

### Compare – Switch Expression vs Switch Statement
| | Statement | Expression (Java 14+) |
|--|-----------|----------------------|
| Giá trị | Không trả về | Trả về giá trị |
| Fall-through | Có (cần `break`) | Không (dùng `->`) |
| Exhaustiveness | Không bắt buộc | Bắt buộc với sealed types |

---

## 5. Arrays & Strings

### Arrays

#### What
Cấu trúc dữ liệu lưu trữ cố định nhiều phần tử **cùng kiểu** liên tiếp trong bộ nhớ.

```java
int[] arr = new int[5];
int[] arr2 = {1, 2, 3, 4, 5};
String[][] matrix = new String[3][3]; // 2D array
```

#### How
- Index từ 0, truy cập O(1)
- Length cố định sau khi tạo
- `Arrays.sort()`, `Arrays.copyOf()`, `Arrays.asList()`

### Strings

#### What
`String` là **immutable** object trong Java, lưu trong **String Pool** (Heap).

```java
String s1 = "hello";           // String Pool
String s2 = new String("hello"); // Heap (không dùng pool)
s1 == s2    // false (khác reference)
s1.equals(s2) // true (cùng nội dung)
```

#### How – String Pool
- Literal string được JVM cache trong pool → tiết kiệm bộ nhớ
- `intern()` method: đưa string vào pool

#### How – Immutability
```java
String s = "hello";
s.toUpperCase(); // trả về String mới, s vẫn là "hello"
s = s.toUpperCase(); // phải gán lại
```

#### Compare – String vs StringBuilder vs StringBuffer

| | String | StringBuilder | StringBuffer |
|--|--------|--------------|-------------|
| Mutable | Không | Có | Có |
| Thread-safe | Có | Không | Có |
| Performance | Chậm khi nối | Nhanh nhất | Chậm hơn StringBuilder |
| Dùng khi | Ít thay đổi | Nối chuỗi trong single-thread | Nối chuỗi multi-thread |

#### Trade-offs
- String immutability tốt cho security, hashing, thread-safety
- Nối string trong vòng lặp nên dùng `StringBuilder`

#### Real-world Usage
```java
// Anti-pattern (tạo N String objects trong loop)
String result = "";
for (String s : list) result += s;

// Best practice
StringBuilder sb = new StringBuilder();
for (String s : list) sb.append(s);
String result = sb.toString();
```

---

## 6. Collections Framework

### What
Tập hợp các interface và class cung cấp cấu trúc dữ liệu động: List, Set, Map, Queue...

### Components – Hierarchy

```
Iterable
  └── Collection
        ├── List
        │     ├── ArrayList
        │     ├── LinkedList
        │     └── Vector (legacy)
        ├── Set
        │     ├── HashSet
        │     ├── LinkedHashSet
        │     └── TreeSet
        └── Queue
              ├── LinkedList
              ├── PriorityQueue
              └── Deque → ArrayDeque

Map (không extends Collection)
  ├── HashMap
  ├── LinkedHashMap
  ├── TreeMap
  └── Hashtable (legacy)
```

### How – Các cấu trúc quan trọng

#### List – thứ tự, cho phép trùng

| | ArrayList | LinkedList |
|--|-----------|-----------|
| Get by index | O(1) | O(n) |
| Add/Remove giữa | O(n) | O(1) |
| Memory | Compact | Thêm overhead (node pointers) |
| Dùng khi | Truy cập ngẫu nhiên nhiều | Insert/Delete giữa nhiều |

#### Set – không trùng, thứ tự tùy

| | HashSet | LinkedHashSet | TreeSet |
|--|---------|--------------|---------|
| Thứ tự | Không | Insertion order | Sorted |
| Get/Add/Remove | O(1) avg | O(1) avg | O(log n) |
| Null | 1 null | 1 null | Không (nếu dùng Comparator không xử lý) |

#### Map – key-value, key không trùng

| | HashMap | LinkedHashMap | TreeMap |
|--|---------|--------------|---------|
| Thứ tự | Không | Insertion order | Sorted by key |
| Get/Put | O(1) avg | O(1) avg | O(log n) |
| Thread-safe | Không | Không | Không |

> Thread-safe alternatives: `ConcurrentHashMap`, `Collections.synchronizedMap()`

#### Queue / Deque
```java
Queue<Integer> queue = new LinkedList<>();
queue.offer(1); queue.poll(); // FIFO

Deque<Integer> stack = new ArrayDeque<>();
stack.push(1); stack.pop(); // LIFO
```

### Why
- Không cần tự cài đặt cấu trúc dữ liệu
- Tối ưu hóa hiệu suất theo use-case
- API thống nhất qua interface

### Trade-offs
- `HashMap` vs `TreeMap`: O(1) vs O(log n) nhưng TreeMap có thứ tự
- `ArrayList` vs `LinkedList`: truy cập nhanh vs insert nhanh
- Capacity & load factor của HashMap ảnh hưởng performance

### Real-world Usage
- `HashMap` cho cache, lookup table
- `LinkedHashMap` cho LRU Cache implementation
- `TreeMap` cho sorted leaderboard
- `PriorityQueue` cho task scheduling

### Ghi chú – Chủ đề tiếp theo
> HashMap internal (hash, bucket, collision), ConcurrentHashMap, Fail-fast vs Fail-safe iterators

---

## 7. Exception Handling

### What
Cơ chế xử lý lỗi runtime bằng cách **ném (throw)** và **bắt (catch)** exception.

### Components – Hierarchy

```
Throwable
  ├── Error (không nên catch: OutOfMemoryError, StackOverflowError)
  └── Exception
        ├── Checked Exception (bắt buộc handle: IOException, SQLException)
        └── RuntimeException (Unchecked: NullPointerException, ArrayIndexOutOfBoundsException)
```

### How – Cú pháp
```java
try {
    riskyOperation();
} catch (IOException e) {
    log.error("IO error", e);
} catch (Exception e) {
    // bắt chung (catch cụ thể trước, chung sau)
} finally {
    // luôn chạy, dùng để đóng resource
    connection.close();
}

// Multi-catch (Java 7+)
catch (IOException | SQLException e) { ... }

// try-with-resources (Java 7+) – tự động close AutoCloseable
try (InputStream is = new FileInputStream("file.txt")) {
    // is tự đóng sau block
}
```

### How – Custom Exception
```java
public class InsufficientFundsException extends RuntimeException {
    private final double amount;

    public InsufficientFundsException(double amount) {
        super("Insufficient funds: need " + amount);
        this.amount = amount;
    }
}
```

### Compare – Checked vs Unchecked

| | Checked | Unchecked (RuntimeException) |
|--|---------|------------------------------|
| Bắt buộc handle | Có | Không |
| Ví dụ | IOException, SQLException | NPE, IllegalArgumentException |
| Khi dùng | Lỗi có thể recover được | Lỗi lập trình, không nên xảy ra |

### Trade-offs
- Checked exception đảm bảo caller xử lý, nhưng làm verbose code
- Nhiều framework (Spring) wrap thành unchecked exception để giảm boilerplate
- Đừng catch `Exception` chung chung rồi bỏ qua → "exception swallowing"

### Real-world Usage
```java
// Anti-pattern
try { ... } catch (Exception e) {} // nuốt exception!

// Best practice
try { ... } catch (Exception e) {
    log.error("Unexpected error", e);
    throw new RuntimeException("Operation failed", e); // wrap
}
```

---

## 8. Generics

### What
Generics cho phép viết code **type-safe** mà không cần biết type cụ thể tại compile-time.

### How
```java
// Generic class
public class Box<T> {
    private T value;
    public Box(T value) { this.value = value; }
    public T get() { return value; }
}

Box<String> strBox = new Box<>("hello");
Box<Integer> intBox = new Box<>(42);

// Generic method
public <T extends Comparable<T>> T max(T a, T b) {
    return a.compareTo(b) > 0 ? a : b;
}
```

### How – Wildcard
```java
// Unbounded wildcard
List<?> list = new ArrayList<String>();

// Upper bounded (Producer): đọc được, không ghi được
List<? extends Number> nums = new ArrayList<Integer>();

// Lower bounded (Consumer): ghi được
List<? super Integer> nums = new ArrayList<Number>();
```
> Quy tắc **PECS**: **P**roducer `extends`, **C**onsumer `super`

### How – Type Erasure
Generics chỉ tồn tại ở compile-time. Tại runtime, tất cả type parameter bị xóa (`erased`):
```java
List<String> và List<Integer> → cùng là List tại runtime
```
→ Không thể `instanceof List<String>`, không thể tạo `new T()`

### Why
- Phát hiện lỗi type tại compile-time thay vì runtime
- Tái sử dụng code mà không cần cast thủ công

### Trade-offs
- Type erasure hạn chế runtime type information
- Không dùng được với primitive types (dùng `List<Integer>` không phải `List<int>`)

### Real-world Usage
- Collections Framework toàn bộ dùng Generics
- Repository pattern: `JpaRepository<Entity, ID>`

---

## 9. Lambda & Functional Interface

### What
Lambda là **anonymous function** (hàm vô danh), giúp viết code ngắn gọn theo phong cách **functional programming**.

### How – Cú pháp
```java
// Trước Java 8 (Anonymous class)
Comparator<String> comp = new Comparator<String>() {
    @Override
    public int compare(String a, String b) { return a.compareTo(b); }
};

// Lambda (Java 8+)
Comparator<String> comp = (a, b) -> a.compareTo(b);

// Method reference
Comparator<String> comp = String::compareTo;
```

### How – Functional Interface
Interface chỉ có **1 abstract method** (có thể có nhiều default/static method). Annotation `@FunctionalInterface`.

| Interface | Signature | Ví dụ |
|-----------|-----------|-------|
| `Supplier<T>` | `() → T` | `() -> new ArrayList<>()` |
| `Consumer<T>` | `T → void` | `s -> System.out.println(s)` |
| `Function<T,R>` | `T → R` | `s -> s.length()` |
| `Predicate<T>` | `T → boolean` | `s -> s.isEmpty()` |
| `BiFunction<T,U,R>` | `(T,U) → R` | `(a,b) -> a+b` |
| `UnaryOperator<T>` | `T → T` | `s -> s.toUpperCase()` |
| `Runnable` | `() → void` | `() -> doWork()` |

### How – Closure & Effectively Final
Lambda có thể capture biến ngoài scope, nhưng biến đó phải là **effectively final** (không bị reassign):
```java
int x = 10; // effectively final
Supplier<Integer> s = () -> x + 1; // OK
x = 20; // Lỗi! x không còn effectively final
```

### Why
- Code ngắn hơn, dễ đọc
- Cho phép truyền behavior như data (Strategy pattern đơn giản hơn)
- Nền tảng của Stream API

### Trade-offs
- Lambda khó debug (stack trace không rõ ràng)
- Overuse làm code khó đọc nếu logic phức tạp

---

## 10. Stream API

### What
Stream API (Java 8+) cho phép xử lý collection theo phong cách **declarative** và **functional**, hỗ trợ **lazy evaluation** và **parallelism**.

### How – Pipeline
```
Source → Intermediate Operations (lazy) → Terminal Operation (trigger)
```

```java
List<String> result = names.stream()          // Source
    .filter(s -> s.startsWith("A"))           // Intermediate (lazy)
    .map(String::toUpperCase)                 // Intermediate (lazy)
    .sorted()                                 // Intermediate (lazy)
    .collect(Collectors.toList());            // Terminal (trigger)
```

### How – Các operation quan trọng

**Intermediate (trả về Stream):**
| Method | Mục đích |
|--------|---------|
| `filter(Predicate)` | Lọc phần tử |
| `map(Function)` | Biến đổi phần tử |
| `flatMap(Function)` | Flatten nested stream |
| `sorted()` / `sorted(Comparator)` | Sắp xếp |
| `distinct()` | Loại trùng |
| `limit(n)` | Lấy tối đa n phần tử |
| `peek(Consumer)` | Debug (không thay đổi) |

**Terminal (trigger pipeline, trả về kết quả):**
| Method | Mục đích |
|--------|---------|
| `collect(Collector)` | Thu thập vào collection |
| `forEach(Consumer)` | Duyệt qua |
| `count()` | Đếm |
| `findFirst()` / `findAny()` | Tìm phần tử → `Optional<T>` |
| `anyMatch()` / `allMatch()` / `noneMatch()` | Kiểm tra điều kiện |
| `reduce(identity, accumulator)` | Gộp thành 1 giá trị |
| `min()` / `max()` | Tìm min/max → `Optional<T>` |

### How – Collectors
```java
// Nhóm theo
Map<String, List<Person>> byCity =
    persons.stream().collect(Collectors.groupingBy(Person::getCity));

// Đếm theo nhóm
Map<String, Long> countByCity =
    persons.stream().collect(Collectors.groupingBy(Person::getCity, Collectors.counting()));

// Nối chuỗi
String names = persons.stream()
    .map(Person::getName)
    .collect(Collectors.joining(", ", "[", "]"));
```

### How – Optional
`Optional<T>` tránh `NullPointerException`, buộc caller xử lý case null:
```java
Optional<String> opt = Optional.of("hello");
opt.isPresent();           // true
opt.get();                 // "hello"
opt.orElse("default");     // trả về "hello" hoặc "default"
opt.map(String::length);   // Optional<Integer>
opt.ifPresent(System.out::println);
```

### How – Parallel Stream
```java
list.parallelStream()
    .filter(...)
    .collect(Collectors.toList());
```
> Dùng ForkJoinPool. Không phải lúc nào cũng nhanh hơn do overhead của splitting và merging.

### Why
- Code ngắn gọn, dễ đọc
- Lazy evaluation: chỉ xử lý đúng lượng cần
- Built-in parallelism

### Compare – Stream vs Loop

| | Stream | For Loop |
|--|--------|---------|
| Phong cách | Declarative | Imperative |
| Debug | Khó hơn | Dễ hơn |
| Parallel | Built-in | Phức tạp hơn |
| Performance | Tương đương/nhỉnh hơn | Đơn giản hơn với dữ liệu nhỏ |

### Trade-offs
- Stream không reusable (dùng 1 lần, phải tạo lại)
- Parallel stream có thể gây race condition nếu có side effects
- Debug khó hơn vì lazy evaluation

---

## 11. Concurrency & Multithreading

### What
Concurrency là khả năng xử lý nhiều tác vụ đồng thời (không nhất thiết song song). Multithreading là dùng nhiều thread trong 1 process để đạt concurrency/parallelism.

### How – Tạo Thread

```java
// Cách 1: extends Thread
class MyThread extends Thread {
    public void run() { System.out.println("Running"); }
}
new MyThread().start();

// Cách 2: implement Runnable (preferred)
Thread t = new Thread(() -> System.out.println("Running"));
t.start();

// Cách 3: ExecutorService (best practice)
ExecutorService executor = Executors.newFixedThreadPool(4);
executor.submit(() -> doWork());
executor.shutdown();
```

### How – Thread States
```
NEW → RUNNABLE → BLOCKED/WAITING/TIMED_WAITING → TERMINATED
```

### How – Synchronization

#### `synchronized` keyword
```java
// synchronized method
public synchronized void increment() { count++; }

// synchronized block (fine-grained)
synchronized (this) { count++; }
```

#### `volatile` keyword
Đảm bảo visibility – mọi thread đọc giá trị mới nhất từ main memory, không từ CPU cache:
```java
private volatile boolean running = true;
```
> `volatile` không đảm bảo atomicity (compound operations như `i++` vẫn không an toàn)

#### `java.util.concurrent.atomic`
```java
AtomicInteger counter = new AtomicInteger(0);
counter.incrementAndGet(); // atomic, thread-safe
```

### How – Locks (java.util.concurrent.locks)
```java
ReentrantLock lock = new ReentrantLock();
lock.lock();
try { criticalSection(); }
finally { lock.unlock(); } // luôn unlock trong finally
```

### How – Executor Framework
```java
// Thread pools
Executors.newFixedThreadPool(n)       // n threads cố định
Executors.newCachedThreadPool()       // tạo thread khi cần, tái dùng
Executors.newSingleThreadExecutor()   // 1 thread tuần tự
Executors.newScheduledThreadPool(n)   // scheduled tasks

// Future & Callable
Future<Integer> future = executor.submit(() -> computeHeavyTask());
Integer result = future.get(); // block cho đến khi xong

// CompletableFuture (Java 8+)
CompletableFuture.supplyAsync(() -> fetchData())
    .thenApply(data -> process(data))
    .thenAccept(result -> save(result));
```

### How – Concurrent Collections
- `ConcurrentHashMap`: thread-safe HashMap (segment lock)
- `CopyOnWriteArrayList`: thread-safe, copy khi write (đọc nhiều hơn ghi)
- `BlockingQueue`: `ArrayBlockingQueue`, `LinkedBlockingQueue` – producer-consumer pattern

### Components – Race Condition & Deadlock

**Race Condition**: 2 thread cùng đọc-sửa-ghi biến → kết quả không xác định.
```java
// Không an toàn
count++; // read, increment, write – 3 bước!

// An toàn
AtomicInteger count = new AtomicInteger();
count.incrementAndGet();
```

**Deadlock**: Thread A giữ lock1, chờ lock2. Thread B giữ lock2, chờ lock1 → stuck mãi mãi.
> Giải pháp: luôn lấy lock theo **cùng thứ tự**, dùng `tryLock()` với timeout.

### Trade-offs
- Multithreading tăng throughput nhưng tăng complexity, bug khó reproduce
- `synchronized` đơn giản nhưng coarse-grained (chậm hơn)
- `ReentrantLock` linh hoạt hơn (tryLock, fairness) nhưng cần unlock thủ công

### Real-world Usage
- Web server: mỗi request 1 thread (Tomcat thread pool)
- Background jobs: `@Async` trong Spring, `ScheduledExecutorService`
- Producer-consumer: `BlockingQueue`

### Ghi chú – Chủ đề tiếp theo
> Java Memory Model (happens-before), Virtual Threads (Java 21), Reactive Programming

---

## 12. I/O & NIO

### What
Java I/O là API đọc/ghi dữ liệu từ file, network, stdin/stdout. NIO (New I/O, Java 4) và NIO.2 (Java 7) cải tiến với non-blocking I/O và better file API.

### How – I/O Streams

**Byte Stream** (InputStream/OutputStream) – đọc/ghi binary:
```java
try (InputStream is = new FileInputStream("file.bin");
     OutputStream os = new FileOutputStream("out.bin")) {
    is.transferTo(os); // Java 9+
}
```

**Character Stream** (Reader/Writer) – đọc/ghi text (có charset):
```java
try (BufferedReader reader = new BufferedReader(new FileReader("file.txt"))) {
    String line;
    while ((line = reader.readLine()) != null) {
        System.out.println(line);
    }
}
```

### How – NIO.2 (java.nio.file) – Java 7+
```java
Path path = Path.of("data/file.txt");

// Đọc file
List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
String content = Files.readString(path); // Java 11+

// Ghi file
Files.writeString(path, "content", StandardOpenOption.CREATE);

// Copy, Move, Delete
Files.copy(source, target, StandardCopyOption.REPLACE_EXISTING);
Files.move(source, target);
Files.delete(path);

// Walk directory
Files.walk(Path.of("src"))
    .filter(p -> p.toString().endsWith(".java"))
    .forEach(System.out::println);
```

### Compare – I/O vs NIO

| | I/O (java.io) | NIO (java.nio) |
|--|---------------|----------------|
| Model | Blocking | Non-blocking (Channels + Selectors) |
| Abstraction | Stream | Buffer + Channel |
| Scalability | Thread-per-connection | 1 thread nhiều connections |
| Dùng khi | File I/O đơn giản | Network server, high concurrency |

### Trade-offs
- I/O: đơn giản hơn nhưng blocking
- NIO: phức tạp hơn nhưng scalable; với Java 21 Virtual Threads, blocking I/O cũng scalable

---

## 13. Design Patterns

### What
Design Pattern là **giải pháp tái sử dụng** cho các vấn đề lập trình phổ biến. Được chia làm 3 nhóm: **Creational, Structural, Behavioral**.

### How – Creational (Tạo đối tượng)

#### Singleton
Đảm bảo chỉ có 1 instance duy nhất.
```java
public class Singleton {
    private static volatile Singleton instance;
    private Singleton() {}

    public static Singleton getInstance() {
        if (instance == null) {
            synchronized (Singleton.class) {
                if (instance == null) { // double-checked locking
                    instance = new Singleton();
                }
            }
        }
        return instance;
    }
}
```

#### Builder
Xây dựng object phức tạp từng bước.
```java
Person person = new Person.Builder()
    .name("Alice")
    .age(30)
    .email("alice@example.com")
    .build();
```

#### Factory Method / Abstract Factory
Tạo object mà không specify class cụ thể.
```java
interface Animal { void speak(); }
class Dog implements Animal { public void speak() { System.out.println("Woof"); } }
class Cat implements Animal { public void speak() { System.out.println("Meow"); } }

class AnimalFactory {
    public static Animal create(String type) {
        return switch (type) {
            case "dog" -> new Dog();
            case "cat" -> new Cat();
            default -> throw new IllegalArgumentException();
        };
    }
}
```

### How – Structural (Cấu trúc)

#### Adapter
Convert interface của class này thành interface khác.
```java
// LegacyLogger dùng print(), nhưng code mới dùng log()
class LoggerAdapter implements NewLogger {
    private LegacyLogger legacy;
    public void log(String msg) { legacy.print(msg); }
}
```

#### Decorator
Thêm hành vi động mà không sửa class gốc.
```java
// Java I/O là ví dụ điển hình:
InputStream is = new BufferedInputStream(new FileInputStream("file.txt"));
// BufferedInputStream "wrap" FileInputStream để thêm buffering
```

#### Proxy
Kiểm soát truy cập vào object thật (lazy init, logging, security...).
> Spring AOP sử dụng Dynamic Proxy.

### How – Behavioral (Hành vi)

#### Strategy
Định nghĩa họ thuật toán, đóng gói từng cái, có thể hoán đổi nhau.
```java
interface SortStrategy { void sort(int[] arr); }
class BubbleSort implements SortStrategy { ... }
class QuickSort implements SortStrategy { ... }

class Sorter {
    private SortStrategy strategy;
    Sorter(SortStrategy strategy) { this.strategy = strategy; }
    void sort(int[] arr) { strategy.sort(arr); }
}
```

#### Observer
Object (Subject) thông báo cho danh sách Observers khi state thay đổi. Nền tảng của Event System.
```java
// Java built-in: java.util.Observer (deprecated)
// Modern: dùng EventListener, Spring ApplicationEvent, RxJava
```

#### Template Method
Định nghĩa skeleton của algorithm, để subclass override các bước cụ thể.
```java
abstract class DataProcessor {
    final void process() {    // template method (final!)
        readData();
        processData();        // subclass override
        writeData();
    }
    abstract void processData();
}
```

### Real-world Usage
- Singleton: Spring Beans (mặc định singleton scope)
- Builder: `StringBuilder`, `Lombok @Builder`, `HttpRequest.Builder`
- Factory: `Calendar.getInstance()`, `Connection.getConnection()`
- Decorator: Java I/O streams, Spring Security filter chain
- Observer: Spring Events, Java Swing Listeners
- Strategy: `Comparator`, Spring `HandlerMapping`

---

## 14. Java Memory Model & Garbage Collection

### What
**JMM (Java Memory Model)** định nghĩa cách threads tương tác qua shared memory.
**GC (Garbage Collector)** tự động thu hồi bộ nhớ không còn được tham chiếu.

### How – JVM Memory Areas

```
JVM Memory
├── Heap (shared, GC-managed)
│     ├── Young Generation
│     │     ├── Eden Space
│     │     └── Survivor Spaces (S0, S1)
│     └── Old Generation (Tenured)
├── Metaspace (class metadata, ngoài Heap – Java 8+)
├── Stack (per-thread: method frames, local variables)
├── PC Register (per-thread: instruction pointer)
└── Native Method Stack
```

### How – Garbage Collection Process

**Minor GC**: Thu hồi Young Generation
1. Object mới tạo vào Eden
2. Eden đầy → Minor GC → survivors vào S0
3. Tiếp tục → S0↔S1, tăng age
4. Age đủ threshold → **Promotion** sang Old Gen

**Major/Full GC**: Thu hồi Old Generation – chậm hơn, gây "Stop-the-World"

### How – GC Algorithms (Java 11-21)

| GC | Đặc điểm | Dùng khi |
|----|----------|---------|
| **G1 GC** (default Java 9+) | Region-based, cân bằng throughput/latency | Heap lớn, general purpose |
| **ZGC** (Java 15+ stable) | Pause < 1ms, scalable đến TB | Low-latency critical |
| **Shenandoah** | Concurrent compaction, low pause | Low-latency |
| **Parallel GC** | Max throughput, high pause | Batch processing |
| **Serial GC** | Single-threaded | Embedded, very small heap |

### How – Memory Leaks trong Java
Dù có GC, vẫn có thể "leak" nếu object vẫn được tham chiếu nhưng không còn dùng:
```java
// Ví dụ: static collection giữ reference mãi mãi
static List<byte[]> cache = new ArrayList<>();
void addToCache() { cache.add(new byte[1024 * 1024]); } // OOM!

// Giải pháp: WeakReference, SoftReference, hoặc dùng proper cache (Caffeine, Guava)
```

### How – JMM & Happens-Before
**Happens-before**: đảm bảo write của thread A visible với thread B.
- `synchronized` block/method
- `volatile` write happens-before volatile read
- `Thread.start()` happens-before bất kỳ action nào trong thread đó

### Trade-offs
- GC giảm manual memory management, nhưng gây pause (Stop-the-World)
- Heap lớn hơn → GC pause dài hơn (với G1, ZGC giảm thiểu vấn đề này)
- Metaspace có thể OOM nếu load quá nhiều class (dynamic class generation)

### Real-world Usage
- JVM flags: `-Xmx4g -Xms4g -XX:+UseG1GC -XX:MaxGCPauseMillis=200`
- Monitor GC: GC logs, JVM metrics (Micrometer + Prometheus), Java Mission Control
- Profiling memory leaks: VisualVM, Eclipse MAT, YourKit

### Ghi chú – Chủ đề tiếp theo
> Virtual Threads (Java 21 – Project Loom), Structured Concurrency, GraalVM Native Image

---

*Cập nhật lần cuối: 2026-04-28*
