# Polymorphism (Đa Hình)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Polymorphism là gì?

**Polymorphism** (đa hình) là khả năng một entity (method, object) thể hiện **nhiều hình thái khác nhau** tùy theo ngữ cảnh.

Trong Java có 2 loại polymorphism:

| Loại | Tên khác | Thời điểm quyết định | Cơ chế |
|------|---------|----------------------|--------|
| **Compile-time** | Static / Early binding | Compile | Method Overloading |
| **Runtime** | Dynamic / Late binding | Runtime | Method Overriding + Dynamic Dispatch |

---

## How – Compile-time Polymorphism: Method Overloading

### Định nghĩa
Nhiều method **cùng tên** trong cùng class, khác nhau về **parameter list** (số lượng, kiểu, thứ tự).

```java
public class Calculator {
    int add(int a, int b)          { return a + b; }
    double add(double a, double b) { return a + b; }
    int add(int a, int b, int c)   { return a + b + c; }
    String add(String a, String b) { return a + b; }
}
```

### Quy tắc Overloading – Compiler chọn method nào?

Compiler tìm method phù hợp theo thứ tự ưu tiên:
1. **Exact match** (khớp chính xác)
2. **Widening primitive** (`int` → `long` → `float` → `double`)
3. **Autoboxing** (`int` → `Integer`)
4. **Varargs** (`int...`)

```java
void test(int x)     { System.out.println("int"); }
void test(long x)    { System.out.println("long"); }
void test(Integer x) { System.out.println("Integer"); }
void test(int... x)  { System.out.println("varargs"); }

test(5);      // "int"       – exact match
test(5L);     // "long"      – exact match
// Nếu xóa test(int), test(5) sẽ gọi test(long) – widening
// Autoboxing ưu tiên thấp hơn widening!
```

**Không thể overload chỉ bằng return type:**
```java
int getValue() { return 1; }
// double getValue() { return 1.0; } // COMPILE ERROR
```

**Varargs và Overloading – dễ nhầm lẫn:**
```java
void print(String s)      { System.out.println("String"); }
void print(String... ss)  { System.out.println("Varargs"); }

print("hello");    // "String" – exact match ưu tiên hơn varargs
print("a", "b");   // "Varargs"
```

**Ảnh hưởng của Type Erasure với Generics:**
```java
// Không thể overload vì erasure xóa type parameter → cùng signature sau erasure!
void process(List<String> list) { ... }
// void process(List<Integer> list) { ... } // COMPILE ERROR
```

---

## How – Runtime Polymorphism: Method Overriding

### Định nghĩa
Subclass cung cấp **cài đặt cụ thể** cho method đã khai báo trong superclass/interface.

```java
class Shape {
    double area() { return 0; }
    void draw() { System.out.println("Drawing shape"); }
}

class Circle extends Shape {
    double radius;
    Circle(double r) { this.radius = r; }

    @Override
    double area() { return Math.PI * radius * radius; }

    @Override
    void draw() { System.out.println("Drawing circle r=" + radius); }
}

class Rectangle extends Shape {
    double w, h;
    Rectangle(double w, double h) { this.w = w; this.h = h; }

    @Override
    double area() { return w * h; }
}
```

### Dynamic Dispatch – Cơ chế runtime

```java
Shape s1 = new Circle(5);
Shape s2 = new Rectangle(4, 6);

// JVM quyết định tại RUNTIME dựa trên kiểu thực của object
s1.area(); // Circle.area() = 78.54...
s2.area(); // Rectangle.area() = 24.0
```

**Cách JVM thực hiện (Vtable):**
```
Circle vtable:
  area()  → Circle.area()
  draw()  → Circle.draw()
  equals() → Object.equals() (kế thừa)
  hashCode() → Object.hashCode()

Rectangle vtable:
  area()  → Rectangle.area()
  draw()  → Shape.draw() (kế thừa, không override)
```

---

### Toàn bộ Quy tắc Overriding

| Điều kiện | Quy tắc |
|----------|---------|
| Tên + Parameters | Phải giống hệt (same signature) |
| Return type | Giống hoặc **subtype** (covariant return) |
| Access modifier | Không được **hẹp hơn** cha |
| Exception (checked) | Không được **rộng hơn** cha |
| `static` method | Không override được – **hiding** (khác khái niệm) |
| `private` method | Không override được – không visible |
| `final` method | Không override được |
| Constructor | Không override được |

```java
class Parent {
    protected IOException riskyOp() throws IOException { return null; }
}

class Child extends Parent {
    @Override
    public FileNotFoundException riskyOp() throws FileNotFoundException { // VALID
    //  ↑ public (rộng hơn protected)
    //                 ↑ FileNotFoundException (subtype của IOException)
        return null;
    }
}
```

---

### Static Method Hiding – Khác với Overriding!

```java
class Parent {
    static void staticMethod() { System.out.println("Parent.static"); }
    void instanceMethod() { System.out.println("Parent.instance"); }
}

class Child extends Parent {
    static void staticMethod() { System.out.println("Child.static"); } // HIDING
    @Override
    void instanceMethod() { System.out.println("Child.instance"); }   // OVERRIDING
}

Parent p = new Child();
p.staticMethod();   // "Parent.static" – compile-time decision (kiểu khai báo)!
p.instanceMethod(); // "Child.instance" – runtime decision (kiểu thực)!
```

> `static` method KHÔNG có polymorphism. Gọi theo kiểu khai báo, không phải kiểu thực.

---

## How – Upcasting & Downcasting

### Upcasting (ngầm định, luôn an toàn)
```java
Dog dog = new Dog("Rex");
Animal animal = dog;          // upcasting – implicit
Object obj = dog;             // upcasting lên Object – implicit
```

### Downcasting (tường minh, có thể ném ClassCastException)
```java
Animal a = new Dog("Rex");
Dog d = (Dog) a;              // OK – a thực sự là Dog
d.bark();

Animal a2 = new Cat("Kitty");
Dog d2 = (Dog) a2;            // ClassCastException tại RUNTIME!
```

### instanceof – Kiểm tra trước khi cast

**Cách cũ (Java < 16):**
```java
if (animal instanceof Dog) {
    Dog d = (Dog) animal; // 2 bước
    d.bark();
}
```

**Pattern Matching instanceof (Java 16+):**
```java
if (animal instanceof Dog d) { // cast + bind trong 1 bước
    d.bark();
}

// Kết hợp điều kiện
if (animal instanceof Dog d && d.getBreed().equals("Labrador")) {
    d.fetch();
}
```

**Switch Pattern Matching (Java 21):**
```java
String describe(Animal a) {
    return switch (a) {
        case Dog d when d.isGoodBoy() -> "Good dog: " + d.getName();
        case Dog d                    -> "Dog: " + d.getName();
        case Cat c                    -> "Cat: " + c.getName();
        case null                     -> "null animal";
        default                       -> "Unknown animal";
    };
}
```

---

## Components – Polymorphism với Interface

Interface là nền tảng mạnh nhất cho polymorphism trong Java thực tế:

```java
interface PaymentMethod {
    boolean pay(BigDecimal amount);
    default String getDescription() { return "Payment: " + getClass().getSimpleName(); }
}

class CreditCard implements PaymentMethod {
    @Override
    public boolean pay(BigDecimal amount) {
        System.out.println("Charging card: " + amount);
        return true;
    }
}

class PayPal implements PaymentMethod {
    @Override
    public boolean pay(BigDecimal amount) {
        System.out.println("PayPal transfer: " + amount);
        return true;
    }
}

class BankTransfer implements PaymentMethod {
    @Override
    public boolean pay(BigDecimal amount) {
        System.out.println("Bank transfer: " + amount);
        return true;
    }
}

// Polymorphism – xử lý đồng nhất mọi PaymentMethod
class Checkout {
    void processPayment(PaymentMethod method, BigDecimal amount) {
        if (!method.pay(amount)) throw new PaymentException("Payment failed");
    }
}

// Runtime – có thể swap implementation
Checkout checkout = new Checkout();
checkout.processPayment(new CreditCard(), new BigDecimal("99.99"));
checkout.processPayment(new PayPal(), new BigDecimal("49.99"));
```

---

## Components – Sealed Classes (Java 17) + Polymorphism

**Sealed class** giới hạn tập subclass được phép → exhaustive pattern matching:

```java
public sealed interface Shape permits Circle, Rectangle, Triangle {}

record Circle(double radius) implements Shape {}
record Rectangle(double width, double height) implements Shape {}
record Triangle(double base, double height) implements Shape {}

// Compiler biết tất cả case → không cần default
double area(Shape shape) {
    return switch (shape) {
        case Circle c      -> Math.PI * c.radius() * c.radius();
        case Rectangle r   -> r.width() * r.height();
        case Triangle t    -> 0.5 * t.base() * t.height();
        // Không cần default! Compiler kiểm tra exhaustiveness
    };
}
```

---

## Why – Tại sao Polymorphism quan trọng?

1. **Open/Closed Principle**: thêm loại mới (Cat) mà không sửa code hiện có (Checkout)
2. **Giảm if-else**: thay `if (type == "CARD") ... else if (type == "PAYPAL")...` bằng dispatch tự động
3. **Dependency Inversion**: code tầng cao phụ thuộc vào interface, không phải implementation
4. **Testability**: dễ inject mock/stub qua interface

---

## When – Khi nào dùng loại nào?

| Tình huống | Dùng |
|-----------|------|
| Cùng tên, khác tham số (utility) | Overloading |
| Hành vi khác nhau theo loại object | Overriding |
| Thêm loại mới mà không sửa code cũ | Interface + Overriding |
| Tập subclass cố định, cần exhaustive check | Sealed class + Pattern Matching |
| Thay đổi behavior tại runtime | Interface + Dependency Injection |

---

## Compare – Overloading vs Overriding

| | Overloading | Overriding |
|--|-------------|-----------|
| Binding | Compile-time | Runtime |
| Signature | Khác parameter | Giống hệt (same) |
| Return type | Bất kỳ | Giống hoặc subtype |
| Access modifier | Bất kỳ | Không hẹp hơn cha |
| `static` | Có thể | Không (hidden, không override) |
| `@Override` | Không dùng | Luôn dùng |
| Phạm vi | Cùng class | Subclass – Superclass |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Mở rộng không sửa code cũ (OCP) | Overloading phức tạp → khó đọc nếu nhiều overload |
| Giảm if-else, tăng tính rõ ràng | Dynamic dispatch tốn chi phí vtable lookup (micro, ít ảnh hưởng thực tế) |
| Dễ test qua interface | Downcasting nguy hiểm nếu không kiểm tra instanceof |
| Sealed class: type-safe exhaustive | Sealed class hạn chế extensibility từ bên ngoài |

---

## Real-world Usage (Production)

### 1. Spring MVC – Handler Polymorphism
```java
// DispatcherServlet gọi handleRequest() mà không cần biết implementation cụ thể
public interface HandlerAdapter {
    boolean supports(Object handler);
    ModelAndView handle(HttpServletRequest req, HttpServletResponse res, Object handler);
}

// Spring có nhiều implementation:
// RequestMappingHandlerAdapter, HttpRequestHandlerAdapter, SimpleControllerHandlerAdapter...
```

### 2. Strategy Pattern với Lambda
```java
@FunctionalInterface
interface DiscountStrategy {
    BigDecimal apply(BigDecimal price);
}

class PricingService {
    BigDecimal calculatePrice(BigDecimal basePrice, DiscountStrategy strategy) {
        return strategy.apply(basePrice);
    }
}

// Runtime polymorphism qua lambda
pricingService.calculatePrice(price, p -> p.multiply(new BigDecimal("0.9")));  // 10% off
pricingService.calculatePrice(price, p -> p.subtract(new BigDecimal("50")));   // $50 off
pricingService.calculatePrice(price, p -> p);                                   // no discount
```

### 3. Jackson Deserialization – Polymorphism
```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes({
    @JsonSubTypes.Type(value = CreditCard.class, name = "CARD"),
    @JsonSubTypes.Type(value = PayPal.class, name = "PAYPAL")
})
public abstract class Payment { }
```

### 4. Visitor Pattern – Double Dispatch
```java
// Khi cần thêm operation mà không sửa class
interface ShapeVisitor {
    void visit(Circle c);
    void visit(Rectangle r);
}

interface Shape {
    void accept(ShapeVisitor visitor);
}

class Circle implements Shape {
    public void accept(ShapeVisitor v) { v.visit(this); } // runtime dispatch lần 1
}

class AreaCalculator implements ShapeVisitor {
    public void visit(Circle c) { /* tính area */ }      // runtime dispatch lần 2
    public void visit(Rectangle r) { /* tính area */ }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo đi sâu vào: **Abstraction** (Trừu tượng)
>
> Keyword cần tổng hợp: `abstract` class (khi nào constructor được gọi, abstract method), `interface` (evolution qua Java 7/8/9), `default` method và diamond problem với interface, `static` method trong interface, `private` method trong interface (Java 9), Marker interface vs Annotation, Functional interface, Abstract class vs Interface decision matrix, Template Method pattern (abstract class), Strategy pattern (interface)
