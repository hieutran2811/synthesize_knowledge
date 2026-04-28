# Inheritance (Kế Thừa)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Inheritance là gì?

**Inheritance** là cơ chế cho phép một class (**subclass/child**) tái sử dụng, mở rộng, và/hoặc override hành vi của class khác (**superclass/parent**).

Trong Java:
```java
class Dog extends Animal { ... }
```
- `Dog` **is-a** `Animal` → quan hệ "là một loại"
- `Dog` thừa hưởng tất cả **non-private** members của `Animal`
- Java chỉ hỗ trợ **single class inheritance** (1 class cha duy nhất)

---

## How – Cơ chế hoạt động

### 1. Constructor Chaining

Khi tạo object subclass, constructor cha **luôn được gọi trước** — tường minh (`super(...)`) hoặc ngầm định (compiler tự thêm `super()`):

```java
class Animal {
    String name;
    Animal(String name) {
        this.name = name;
        System.out.println("Animal created: " + name);
    }
}

class Dog extends Animal {
    String breed;

    Dog(String name, String breed) {
        super(name);          // BẮT BUỘC phải là lệnh đầu tiên nếu gọi tường minh
        this.breed = breed;
        System.out.println("Dog created: " + breed);
    }
}

new Dog("Rex", "Labrador");
// Output:
// Animal created: Rex
// Dog created: Labrador
```

> Nếu superclass không có no-arg constructor mà subclass không gọi `super(...)` tường minh → **compile error**.

---

### 2. `super` keyword

```java
class Animal {
    String name;
    void describe() { System.out.println("Animal: " + name); }
}

class Dog extends Animal {
    String breed;

    @Override
    void describe() {
        super.describe();           // gọi method của cha
        System.out.println("Breed: " + breed);
    }
}
```

`super` dùng để:
- Gọi constructor cha: `super(args)` — phải là lệnh đầu tiên
- Gọi method cha đã bị override: `super.methodName()`
- Truy cập field cha (khi bị shadow): `super.fieldName`

---

### 3. Method Resolution – Vtable (Virtual Method Table)

Java dùng **dynamic dispatch** — quyết định gọi method nào tại **runtime** dựa trên **kiểu thực sự** của object (không phải kiểu khai báo):

```java
Animal a = new Dog("Rex", "Lab"); // kiểu khai báo: Animal, kiểu thực: Dog
a.describe();   // gọi Dog.describe() → dynamic dispatch!
```

**Cơ chế nội bộ (vtable):**
- Mỗi class có một bảng ảo (vtable) chứa pointer đến các method
- `Dog`'s vtable: `describe` → `Dog.describe` (override), `eat` → `Animal.eat` (kế thừa)
- JVM tra vtable tại runtime để gọi đúng method

> Tất cả instance methods trong Java đều là **virtual** (trừ `private`, `static`, `final`).

---

### 4. Field Shadowing vs Method Overriding

```java
class Parent {
    String name = "Parent";
    void greet() { System.out.println("Hello from Parent"); }
}

class Child extends Parent {
    String name = "Child"; // SHADOW field, không override!

    @Override
    void greet() { System.out.println("Hello from Child"); } // Override method
}

Parent p = new Child();
System.out.println(p.name);  // "Parent" – field resolved at COMPILE TIME (kiểu khai báo)
p.greet();                   // "Hello from Child" – method resolved at RUNTIME (kiểu thực)
```

> **Field không có polymorphism** — luôn dùng theo kiểu khai báo. Đây là lý do không nên dùng public fields.

---

### 5. Covariant Return Type (Java 5+)

Override method được phép trả về **kiểu con** (subtype) của return type cha:

```java
class Animal {
    Animal create() { return new Animal(); }
}

class Dog extends Animal {
    @Override
    Dog create() { return new Dog(); } // Dog là subtype của Animal → OK
}
```

---

### 6. Quy tắc Override

Method trong subclass override method cha khi:
- **Cùng tên + cùng parameter types** (signature giống hệt)
- Return type: **giống hoặc là subtype** (covariant)
- Access modifier: **không được hẹp hơn** (có thể rộng hơn)
  - Cha `protected` → Con có thể `protected` hoặc `public`, không thể `private`
- Exception: chỉ được throw **unchecked** hoặc **checked hẹp hơn/bằng** cha
  - Cha throws `IOException` → Con có thể throws `FileNotFoundException` (subtype của IOException)

```java
class Parent {
    protected Number compute() throws IOException { ... }
}

class Child extends Parent {
    @Override
    public Integer compute() throws FileNotFoundException { ... } // VALID
    //     ↑ rộng hơn   ↑ subtype       ↑ hẹp hơn (subtype)
}
```

> **Luôn dùng `@Override`** — compiler báo lỗi nếu signature sai (tránh bug tưởng đang override mà thật ra là overload).

---

### 7. `final` trong Inheritance

```java
// final class: không thể extends
public final class String { ... } // String trong JDK là final!

// final method: không thể override
public class Animal {
    public final void breathe() { ... } // Dog không thể override breathe()
}
```

---

### 8. `Object` class – Gốc của mọi class

Mọi class trong Java đều ngầm kế thừa `java.lang.Object`. Các method quan trọng cần biết override:

#### `equals()` và `hashCode()`

**Contract bắt buộc**: Nếu `a.equals(b) == true` thì `a.hashCode() == b.hashCode()`.
Phá vỡ contract → HashMap, HashSet hoạt động sai.

```java
public class Point {
    private final int x, y;

    public Point(int x, int y) { this.x = x; this.y = y; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Point p)) return false; // pattern matching Java 16+
        return x == p.x && y == p.y;
    }

    @Override
    public int hashCode() {
        return Objects.hash(x, y); // dùng Objects.hash, không tự tính
    }
}
```

**Pitfall phổ biến:**
```java
Point p1 = new Point(1, 2);
Point p2 = new Point(1, 2);

Set<Point> set = new HashSet<>();
set.add(p1);
set.contains(p2); // false nếu không override equals/hashCode!
```

#### `toString()`
```java
@Override
public String toString() {
    return "Point{x=" + x + ", y=" + y + "}";
}
// hoặc dùng Lombok @ToString, record tự sinh
```

#### `clone()` – Ít dùng, nhiều bẫy
`Object.clone()` tạo **shallow copy**. Để deep copy cần override và copy từng mutable field.
> Thực tế: dùng copy constructor hoặc Builder thay vì `clone()`.

---

### 9. Instanceof và Casting

```java
Animal a = new Dog("Rex", "Lab");

// Upcasting – ngầm định, luôn an toàn
Animal a = new Dog(); // Dog IS-A Animal

// Downcasting – tường minh, có thể ném ClassCastException
Dog d = (Dog) a;      // safe vì a thực sự là Dog

// Kiểm tra trước khi cast (cũ)
if (a instanceof Dog) {
    Dog d = (Dog) a;
    d.bark();
}

// Pattern matching instanceof (Java 16+) – ngắn gọn và an toàn hơn
if (a instanceof Dog d) { // cast + assign trong 1 bước
    d.bark();
}
```

---

### 10. Diamond Problem & Tại sao Java không có Multiple Class Inheritance

```
        Animal
       /      \
    Dog        Cat
       \      /
        ??? (DogCat)
```
Nếu `Dog.eat()` và `Cat.eat()` khác nhau, `DogCat.eat()` gọi cái nào? → **Ambiguous**.

Java giải quyết bằng cách **chỉ cho phép single class inheritance**. Multiple inheritance đạt được qua **interface** (xem bài Abstraction để biết cách Java 8+ xử lý diamond với `default` methods).

---

### 11. Fragile Base Class Problem

Khi superclass thay đổi implementation → subclass bị phá vỡ dù không thay đổi code:

```java
class Base {
    void methodA() { methodB(); } // gọi methodB nội bộ

    void methodB() { System.out.println("B"); }
}

class Child extends Base {
    @Override
    void methodB() { System.out.println("Child B"); super.methodB(); }
}

new Child().methodA();
// "Child B" rồi "B" — Child.methodB() bị gọi từ Base.methodA()
// Nếu Base thay đổi: methodA() không gọi methodB() nữa → Child bị break!
```

> Đây là một trong những lý do **prefer Composition over Inheritance**.

---

## Why – Tại sao dùng Inheritance?

- **Tái sử dụng code**: method và field không cần viết lại
- **Polymorphism**: xử lý đa dạng object qua interface chung
- **Mở rộng**: thêm hành vi mà không sửa class cha
- **Phân cấp tự nhiên**: `Animal → Dog → Labrador`

---

## When – Khi nào NÊN dùng Inheritance?

Dùng khi thỏa mãn **Liskov Substitution Principle (LSP)**:
> "Nếu S là subtype của T, thì object của T có thể được thay bằng object của S mà không làm thay đổi tính đúng đắn của chương trình."

**Test đơn giản**: thay thế `Dog` bằng `Animal` có hợp lý không? Nếu có → inheritance đúng.

```java
// ĐÚNG: Dog IS-A Animal, thay thế được
void feedAnimal(Animal a) { a.eat(); }
feedAnimal(new Dog()); // OK

// SAI: Square IS-A Rectangle trên lý thuyết, nhưng vi phạm LSP
class Rectangle { void setWidth(int w); void setHeight(int h); }
class Square extends Rectangle {
    void setWidth(int w) { super.setWidth(w); super.setHeight(w); } // BREAK expectations!
}
```

---

## Compare – Inheritance vs Composition

| | Inheritance | Composition |
|--|-------------|-------------|
| Quan hệ | "is-a" | "has-a" |
| Coupling | Chặt (tight) | Lỏng (loose) |
| Flexibility | Cố định tại compile-time | Thay đổi được tại runtime |
| Test | Khó mock superclass | Dễ mock dependency |
| Fragile Base Class | Có nguy cơ | Không |
| Code reuse | Cao (tự động) | Cao (explicit delegation) |
| Dùng khi | IS-A thực sự, LSP thỏa mãn | Còn lại |

```java
// Composition thay vì Inheritance
class Logger {
    void log(String msg) { System.out.println(msg); }
}

class OrderService {
    private final Logger logger = new Logger(); // HAS-A, không IS-A

    void placeOrder(Order o) {
        logger.log("Placing order: " + o.getId());
        // ...
    }
}
```

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Tái sử dụng code tự nhiên | Tight coupling với superclass |
| Polymorphism mạnh | Fragile Base Class Problem |
| Phân cấp dễ hiểu | Khó thay đổi hierarchy sau khi thiết kế |
| Override để custom | Deep hierarchy → khó debug |

---

## Real-world Usage (Production)

### 1. Abstract Template (Spring / JPA)
```java
// Spring Data JPA
@Entity
@Inheritance(strategy = InheritanceType.JOINED)
@DiscriminatorColumn(name = "payment_type")
public abstract class Payment {
    @Id @GeneratedValue
    private Long id;
    private BigDecimal amount;
}

@Entity
@DiscriminatorValue("CARD")
public class CardPayment extends Payment {
    private String cardNumber;
    private String cvv;
}

@Entity
@DiscriminatorValue("BANK")
public class BankTransfer extends Payment {
    private String accountNumber;
}
```

### 2. Exception Hierarchy
```java
// Custom exception hierarchy
public class AppException extends RuntimeException {
    private final String errorCode;
    public AppException(String errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }
}

public class ValidationException extends AppException {
    private final List<String> violations;
    public ValidationException(List<String> violations) {
        super("VALIDATION_ERROR", "Validation failed");
        this.violations = violations;
    }
}

public class NotFoundException extends AppException {
    public NotFoundException(String resource, Long id) {
        super("NOT_FOUND", resource + " not found with id: " + id);
    }
}
```

### 3. equals/hashCode trong Entity
```java
@Entity
public class User {
    @Id
    private Long id;

    // Cho Entity JPA: chỉ so sánh theo ID (business identity)
    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof User u)) return false;
        return id != null && id.equals(u.id);
    }

    @Override
    public int hashCode() {
        return getClass().hashCode(); // không dùng id vì có thể null trước khi persist
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo đi sâu vào: **Polymorphism** (Đa hình)
>
> Keyword cần tổng hợp: static dispatch vs dynamic dispatch, method overloading rules (không phải return type), method overriding rules, virtual method, `@Override`, covariant return type, varargs trong overloading, type erasure ảnh hưởng overloading, upcasting/downcasting, ClassCastException, `instanceof` pattern matching (Java 16+), Sealed classes (Java 17)
