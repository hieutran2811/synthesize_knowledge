# Nested & Inner Classes (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Nested Class là gì?

**Nested class** là class được khai báo **bên trong** một class/interface khác. Java có **4 loại** nested class, chia theo việc có `static` hay không và nơi khai báo:

```
Nested Class
├── Static Nested Class      (static, khai báo ở class level)
└── Inner Class (non-static)
      ├── Member Inner Class  (khai báo ở class level, không static)
      ├── Local Inner Class   (khai báo bên trong method/block)
      └── Anonymous Inner Class (không có tên, vừa khai báo vừa khởi tạo)
```

> **Thuật ngữ chuẩn (JLS):** "Inner class" = nested class **không static**. "Nested class" là tên gọi chung cho cả 4. Nhiều người gọi nhầm tất cả là "inner class".

---

## How – 4 loại chi tiết

### 1. Static Nested Class

Là class `static` lồng trong class khác. **Không** giữ tham chiếu tới instance của outer class → hoạt động như một top-level class bình thường, chỉ khác về **namespace** và **quyền truy cập** (truy cập được `private static` member của outer).

```java
public class Outer {
    private static int staticField = 1;
    private int instanceField = 2;

    static class Nested {
        void show() {
            System.out.println(staticField);   // OK – truy cập static của outer
            // System.out.println(instanceField); // LỖI! không có outer instance
        }
    }
}

// Khởi tạo: KHÔNG cần outer instance
Outer.Nested nested = new Outer.Nested();
```

### 2. Member Inner Class (non-static)

Mỗi instance inner class **gắn liền** với một instance outer class. Truy cập được **tất cả** member của outer (kể cả `private` instance field).

```java
public class Outer {
    private int value = 10;

    class Inner {
        void show() {
            System.out.println(value);          // truy cập trực tiếp
            System.out.println(Outer.this.value); // tường minh: Outer.this
        }
    }
}

// Khởi tạo: BẮT BUỘC có outer instance trước
Outer outer = new Outer();
Outer.Inner inner = outer.new Inner();   // cú pháp đặc biệt: outer.new
```

> Inner class **không thể** có `static` member (trừ `static final` hằng số compile-time), vì nó gắn với instance, không thuộc về class.

### 3. Local Inner Class

Khai báo bên trong một **method/constructor/block**. Scope chỉ trong block đó. Truy cập được biến local **effectively final**.

```java
public class Outer {
    void process(int param) {  // param phải effectively final để dùng trong local class
        int local = 5;
        class LocalProcessor {
            void run() {
                System.out.println(param + local);  // capture biến local
            }
        }
        new LocalProcessor().run();
    }
}
```

### 4. Anonymous Inner Class

Class **không tên**, vừa định nghĩa vừa khởi tạo cùng lúc. Dùng để override/implement nhanh một class/interface.

```java
// Implement interface
Runnable r = new Runnable() {
    @Override public void run() { System.out.println("run"); }
};

// Extends class + override
ArrayList<String> list = new ArrayList<>() {  // diamond Java 9+
    { add("init"); }   // instance initializer block
};

// Phổ biến nhất trước Java 8: Comparator, listener
Collections.sort(names, new Comparator<String>() {
    @Override public int compare(String a, String b) { return a.length() - b.length(); }
});
```

---

## How – Cơ chế hoạt động (Compiler & Bytecode)

### Synthetic field `this$0`

Khi compile inner class non-static, compiler **tự sinh** một field ẩn trỏ về outer instance:

```java
// Bạn viết:
class Outer { class Inner {} }

// Compiler sinh ra (đại ý):
class Outer$Inner {
    final Outer this$0;                       // synthetic reference tới outer
    Outer$Inner(Outer outer) { this$0 = outer; }
}
```

→ File `.class` sinh ra: `Outer.class`, `Outer$Inner.class`, `Outer$1.class` (anonymous được đánh số).

### Capture biến local – tại sao phải "effectively final"?

Local/anonymous class **copy** giá trị biến local vào synthetic field (vì biến local nằm trên **stack**, sẽ biến mất khi method kết thúc, còn object sống trên **heap**). Nếu biến thay đổi sau khi capture, bản copy và bản gốc lệch nhau → Java cấm bằng cách yêu cầu **effectively final**.

```java
void m() {
    int x = 1;
    Runnable r = () -> System.out.println(x);  // capture COPY của x
    // x = 2;  // LỖI: x không còn effectively final
}
```

> Muốn "thay đổi" biến captured: dùng mảng 1 phần tử `int[] holder = {0};` hoặc `AtomicInteger` (capture reference, sửa nội dung). Đây là workaround, không khuyến khích.

### Truy cập private – bridge/synthetic accessor (trước Java 11)

Inner class và outer class là 2 file `.class` khác nhau, nhưng lại truy cập `private` member của nhau. Trước Java 11, compiler sinh **synthetic accessor method** (`access$000`) để lách giới hạn JVM. Từ **Java 11 (JEP 181 – Nestmates)**, JVM hỗ trợ khái niệm **nest** (`NestHost`/`NestMembers` attribute) → truy cập private trực tiếp, không cần bridge method nữa (an toàn hơn, ít bytecode hơn).

---

## How – Memory Leak kinh điển từ Inner Class

Inner class non-static **giữ reference ngầm** tới outer instance → nếu inner class sống lâu hơn outer dự kiến, outer **không được GC**.

```java
public class LeakyService {
    private byte[] hugeData = new byte[100 * 1024 * 1024]; // 100MB

    // ❌ Inner class non-static giữ this$0 → giữ luôn hugeData
    public Runnable createTask() {
        return new Runnable() {           // anonymous = non-static
            @Override public void run() { doSomethingTrivial(); }
        };
        // Task này được submit vào executor sống mãi → leak 100MB
    }

    // ✅ Static nested + truyền data tối thiểu
    public Runnable createTaskSafe() {
        return new TrivialTask();
    }
    private static class TrivialTask implements Runnable {
        @Override public void run() { /* không giữ outer */ }
    }
}
```

> **Ví dụ thực tế:** `Handler` trong Android, listener không hủy đăng ký, `TimerTask` non-static. Quy tắc: nếu inner class **không cần** outer → khai báo `static`.

---

## Compare – So sánh 4 loại

| Tiêu chí | Static Nested | Member Inner | Local Inner | Anonymous |
|----------|--------------|--------------|-------------|-----------|
| `static`? | Có | Không | Không | Không |
| Giữ outer instance (`this$0`) | Không | Có | Có | Có |
| Cần outer instance để tạo | Không | Có (`outer.new`) | N/A (trong method) | N/A |
| Có tên | Có | Có | Có | Không |
| Truy cập outer instance field | Chỉ static | Tất cả | Tất cả | Tất cả |
| Có `static` member riêng | Có | Không¹ | Không¹ | Không¹ |
| Số lần tái sử dụng | Nhiều nơi | Nhiều nơi | Trong 1 method | 1 lần |

> ¹ Từ **Java 16**, inner class được phép khai báo static member (JEP 395 nới lỏng). Trước đó chỉ `static final` constant.

---

## Compare – Anonymous Class vs Lambda

Java 8 Lambda thay thế phần lớn anonymous class, nhưng **không tương đương hoàn toàn**:

| | Anonymous Class | Lambda |
|--|-----------------|--------|
| Áp dụng cho | Bất kỳ interface/class | Chỉ **functional interface** (1 abstract method) |
| `this` | Trỏ tới **anonymous instance** | Trỏ tới **enclosing instance** (outer) |
| State (field) | Có field riêng | Không có field |
| Compile thành | File `.class` riêng (`Outer$1`) | `invokedynamic` + method (không sinh class) |
| Khởi tạo | `new` mỗi lần (object mới) | JVM có thể cache, nhẹ hơn |
| Override nhiều method | Được | Không (chỉ 1) |

```java
Runnable anon = new Runnable() {
    @Override public void run() { System.out.println(this); } // this = anonymous obj
};
Runnable lambda = () -> System.out.println(this); // this = enclosing class instance!
```

> Đây là khác biệt **dễ gây bug** nhất: `this` trong lambda KHÔNG phải là chính nó.

---

## When – Khi nào dùng loại nào?

| Tình huống | Loại nên dùng |
|-----------|---------------|
| Helper class chỉ liên quan logic outer, không cần outer instance | **Static nested** (mặc định ưu tiên) |
| Cần truy cập state instance của outer (vd: Iterator của collection) | **Member inner** |
| Logic dùng 1 lần trong method, cần đặt tên cho rõ | **Local inner** |
| Implement interface đơn giản, 1 lần, nhiều method | **Anonymous** (hoặc lambda nếu 1 method) |
| Functional interface 1 method | **Lambda** (ưu tiên hơn anonymous) |

> **Quy tắc vàng (Effective Java – Item 24):** Nếu nested class không cần truy cập instance của outer → **luôn khai báo `static`**. Member inner class mặc định tạo coupling và nguy cơ leak.

---

## Real-world Usage

### Iterator – ví dụ kinh điển của member inner class
```java
public class MyList<E> {
    private Object[] data; private int size;

    // Inner class cần truy cập data/size của outer instance
    private class Itr implements Iterator<E> {
        int cursor = 0;
        public boolean hasNext() { return cursor < size; }
        @SuppressWarnings("unchecked")
        public E next() { return (E) data[cursor++]; }
    }
    public Iterator<E> iterator() { return new Itr(); }
}
```
> `ArrayList`, `HashMap`... đều dùng inner class cho Iterator/EntrySet/KeySet.

### Builder – static nested class
```java
public class Pizza {
    private final List<String> toppings;
    private Pizza(Builder b) { this.toppings = b.toppings; }

    public static class Builder {           // static! không cần Pizza instance
        private final List<String> toppings = new ArrayList<>();
        public Builder add(String t) { toppings.add(t); return this; }
        public Pizza build() { return new Pizza(this); }
    }
}
Pizza p = new Pizza.Builder().add("cheese").build();
```

### Anonymous – callback/listener (legacy & framework)
```java
button.addActionListener(new ActionListener() {
    @Override public void actionPerformed(ActionEvent e) { handleClick(); }
});
// Spring: anonymous TransactionCallback, ResultSetExtractor...
```

---

## Trade-offs

- (+) **Static nested**: đóng gói logic phụ trợ gần nơi dùng, không overhead, không leak.
- (+) **Inner class**: truy cập state outer tự nhiên (Iterator pattern), code gọn.
- (−) **Inner class non-static**: giữ `this$0` → **memory leak** tiềm ẩn, serialize phức tạp (kéo theo outer), khó test độc lập.
- (−) **Anonymous**: không tái sử dụng, không tên → stack trace khó đọc (`Outer$1`), không thể có constructor.
- (−) Quá nhiều nested class làm file dài, giảm tính dễ đọc → cân nhắc tách ra top-level.

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[core/lambda.md]] (lambda vs anonymous, capture), [[core/collections.md]] (Iterator inner class), [[patterns/creational.md]] (Builder static nested), [[jvm/gc.md]] (memory leak từ this$0).
>
> Keyword cho topic kế: **Enums** (enum là static nested ngầm khi khai báo trong class; enum body = anonymous class cho mỗi constant có method riêng), `EnumSet`/`EnumMap`, strategy enum, ordinal pitfalls.

*Cập nhật lần cuối: 2026-06-04*