---
title: "Enums Deep Dive"
topic: java
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Enums Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Enum là gì?

**Enum** *(enumeration — kiểu liệt kê)* là một kiểu dữ liệu đặc biệt biểu diễn một **tập hợp hằng số cố định, hữu hạn** (vd: ngày trong tuần, trạng thái đơn hàng). Java 5 (2004) đưa enum thành **first-class type** *(kiểu hạng nhất — được ngôn ngữ hỗ trợ đầy đủ như một class thực thụ)* thay cho `public static final int` constants.

Bản chất: mỗi enum là một **class** kế thừa ngầm `java.lang.Enum<E>`, và mỗi hằng số là một **instance singleton** *(thể hiện duy nhất — chỉ tồn tại đúng một bản trong JVM)* `public static final` của class đó.

> 💡 **Giải thích dễ hiểu:**
> Enum giống như một **bộ tem có sẵn, đóng khung**. Thay vì để lập trình viên tùy tiện viết `0, 1, 2` hay chuỗi `"NEW", "new", "New"` (dễ gõ sai, dễ truyền nhầm), enum in sẵn một bộ tem cố định `NEW / PAID / SHIPPED`. Bạn chỉ được chọn trong bộ đó, không tự chế thêm. Mỗi con tem là **duy nhất** (singleton) — cả chương trình chỉ có đúng một `Status.PAID`, nên so sánh chúng nhanh và chắc chắn như đối chiếu chính con tem đó với bản thân nó.

```java
public enum Day { MON, TUE, WED, THU, FRI, SAT, SUN }
```

---

## How – Compiler biến enum thành gì?

```java
// Bạn viết:
public enum Color { RED, GREEN, BLUE }

// Compiler sinh ra (đại ý):
public final class Color extends Enum<Color> {
    public static final Color RED   = new Color("RED", 0);
    public static final Color GREEN = new Color("GREEN", 1);
    public static final Color BLUE  = new Color("BLUE", 2);

    private static final Color[] $VALUES = { RED, GREEN, BLUE };

    private Color(String name, int ordinal) { super(name, ordinal); } // private!

    public static Color[] values() { return $VALUES.clone(); } // clone → bất biến
    public static Color valueOf(String n) { return Enum.valueOf(Color.class, n); }
}
```

**Hệ quả quan trọng:**
- Constructor *(hàm khởi tạo)* enum **luôn private** → không thể `new` từ ngoài → số instance cố định.
- Mỗi constant là **singleton** do JVM khởi tạo khi class load *(nạp class)* (thread-safe by JVM).
- `final` → không kế thừa được enum.
- `values()` trả về **bản clone** *(bản sao)* mỗi lần gọi → đừng gọi trong vòng lặp nóng.

> 💡 **Giải thích dễ hiểu — vì sao "không new được"?**
> Khi bạn viết `enum Color { RED, GREEN, BLUE }`, compiler âm thầm dịch nó thành một class với 3 biến `public static final` đã `new` sẵn, và **khóa constructor lại (private)**. Ví von: enum như một **quán chỉ bán đúng 3 món set menu đã nấu sẵn** — khách không được vào bếp tự chế món mới. Chính vì "bếp bị khóa" nên bạn chắc chắn cả hệ thống chỉ có đúng 3 màu, không ai lén tạo `RED` thứ hai. Đó cũng là lý do `RED == Color.RED` luôn đúng.

---

## How – Các method kế thừa từ `Enum`

| Method | Ý nghĩa |
|--------|---------|
| `name()` | Tên hằng số đúng như khai báo (`"RED"`) – **final**, không override được |
| `ordinal()` | Vị trí (0-based) theo thứ tự khai báo |
| `valueOf(String)` | Parse từ tên → instance (sai tên → `IllegalArgumentException`) |
| `values()` | Mảng tất cả constant (do compiler sinh, không phải từ `Enum`) |
| `compareTo()` | So sánh theo `ordinal` (đã implement `Comparable`) |
| `getDeclaringClass()` | Trả về Class của enum (khác `getClass()` với constant body) |
| `equals()`/`hashCode()` | `final`, dựa trên **identity** (so sánh `==` được) |

```java
Color c = Color.valueOf("GREEN");
c.name();        // "GREEN"
c.ordinal();     // 1
Color.values();  // [RED, GREEN, BLUE]
c == Color.GREEN // true – an toàn dùng == với enum
```

> So sánh enum **luôn dùng `==`** (không null-safe issue, nhanh, compile-time check), không cần `.equals()`.

---

## How – Enum với field, constructor, method

Enum không chỉ là hằng số — nó có thể mang **dữ liệu** và **hành vi**:

```java
public enum Planet {
    MERCURY(3.303e+23, 2.4397e6),
    EARTH  (5.976e+24, 6.37814e6),
    JUPITER(1.9e+27,   7.1492e7);

    private final double mass;     // field nên final (immutable)
    private final double radius;

    Planet(double mass, double radius) {  // constructor (implicit private)
        this.mass = mass; this.radius = radius;
    }

    public double surfaceGravity() {
        return 6.67300E-11 * mass / (radius * radius);
    }
}

double g = Planet.EARTH.surfaceGravity();
```

---

## How – Constant-Specific Body (mỗi constant là anonymous subclass)

Mỗi hằng số có thể **override method** *(ghi đè — định nghĩa lại cách chạy của một method)* riêng → tạo ra **anonymous subclass** *(lớp con vô danh — class con không tên do compiler sinh ngầm)* của enum (liên hệ [[core/nested_classes.md]]). Đây là nền tảng của **Strategy Enum** *(enum kiểu chiến lược — mỗi hằng mang một cách hành xử riêng)*.

> 💡 **Giải thích dễ hiểu — mỗi constant "tự làm việc của mình":**
> Bình thường các hằng chỉ khác nhau ở **tên/giá trị**. Nhưng ở đây mỗi hằng còn khác nhau ở **hành vi**. Ví von: `Operation` như một **hộp dụng cụ**, mỗi món (`PLUS`, `MINUS`, `TIMES`) biết tự làm phép tính của nó. Khi gọi `PLUS.apply(2,3)`, chính con tem `PLUS` chạy đoạn code cộng riêng của nó — không cần một cái `switch` khổng lồ ở chỗ khác. Lợi thế lớn: **thêm phép toán mới mà quên viết `apply()` sẽ báo lỗi ngay lúc compile**, không thể sót — trong khi `switch` thì bạn dễ quên thêm `case`.

```java
public enum Operation {
    PLUS  ("+") { public double apply(double a, double b) { return a + b; } },
    MINUS ("-") { public double apply(double a, double b) { return a - b; } },
    TIMES ("*") { public double apply(double a, double b) { return a * b; } },
    DIVIDE("/") { public double apply(double a, double b) { return a / b; } };

    private final String symbol;
    Operation(String symbol) { this.symbol = symbol; }

    public abstract double apply(double a, double b);  // mỗi constant phải impl
}

double r = Operation.PLUS.apply(2, 3); // 5.0
```

> `Operation.PLUS.getClass()` trả về `Operation$1` (anonymous subclass), còn `getDeclaringClass()` trả về `Operation`. Đây là lý do `getDeclaringClass()` tồn tại.

**So với switch:** Strategy enum buộc mỗi constant tự định nghĩa hành vi → thêm constant mới mà quên impl sẽ **lỗi compile**. Switch thì không, dễ sót case.

---

## How – Enum implements Interface

Enum không extends class khác được (đã extends `Enum`), nhưng **implements interface** được → cho phép enum tham gia polymorphism, mở rộng "họ thao tác".

```java
public interface Operation { double apply(double a, double b); }

public enum BasicOp implements Operation {
    PLUS { public double apply(double a, double b) { return a + b; } },
    MINUS{ public double apply(double a, double b) { return a - b; } };
}
public enum ExtendedOp implements Operation {
    EXP { public double apply(double a, double b) { return Math.pow(a, b); } };
}
// Cả 2 enum đều là Operation → dùng chung được, "mở rộng" tập thao tác
```

---

## Components – EnumSet & EnumMap (cực kỳ hiệu quả)

### EnumSet – Set của enum, cài đặt bằng bit vector

```java
EnumSet<Day> weekend = EnumSet.of(Day.SAT, Day.SUN);
EnumSet<Day> workdays = EnumSet.complementOf(weekend);
EnumSet<Day> all = EnumSet.allOf(Day.class);
EnumSet<Day> none = EnumSet.noneOf(Day.class);
```

> 💡 **Giải thích dễ hiểu — `EnumSet` nhanh nhờ "bảng đèn":**
> `EnumSet` *(tập hợp các enum)* không dùng cách băm nặng nề như `HashSet`. Nó dùng **bit vector** *(dãy bit — chuỗi các ô 0/1)*. Ví von: hình dung một **bảng công tắc đèn**, mỗi enum là một công tắc. "Có phần tử này trong tập" = bật đèn tương ứng. Với ≤ 64 enum, cả bảng gói gọn trong **một số `long` 64 bit**. Kiểm tra "có chứa SAT không?" chỉ là xem **một bóng đèn sáng hay tắt** — nhanh tức thì (một phép toán bit), thay vì phải băm rồi dò. Hợp nhất, gộp tập cũng chỉ là phép AND/OR trên các bit.

**Internals:** EnumSet không dùng hash *(băm — biến key thành con số để tra nhanh)*. Mỗi enum ánh xạ tới 1 **bit** theo `ordinal` *(số thứ tự khai báo, bắt đầu từ 0)*:
- `RegularEnumSet`: ≤ 64 constant → 1 biến `long` (bit vector). Mọi thao tác là phép bit → **O(1) cực nhanh**.
- `JumboEnumSet`: > 64 constant → mảng `long[]`.

```
EnumSet.of(SAT, SUN) với Day có ordinal SAT=5, SUN=6:
long elements = 0b1100000  (bit 5 và 6 bật)
contains(SAT) → (elements & (1L << 5)) != 0
```

### EnumMap – Map có key là enum, cài đặt bằng mảng

```java
EnumMap<Day, String> tasks = new EnumMap<>(Day.class);
tasks.put(Day.MON, "Meeting");
tasks.put(Day.FRI, "Review");
```

**Internals:** EnumMap dùng **mảng `Object[]`** index theo `ordinal()` của key → không hash, không collision, **O(1)**, thứ tự = thứ tự khai báo enum. Nhanh và gọn hơn `HashMap` nhiều khi key là enum.

> Liên hệ [[core/collections_internals.md]]. **Quy tắc:** key/element là enum → luôn ưu tiên `EnumMap`/`EnumSet` thay vì `HashMap`/`HashSet`.

---

## How – Singleton bằng Enum (Effective Java – Item 3)

Cách **an toàn nhất** để tạo singleton: chống **reflection** *(cơ chế soi/gọi ngược vào code lúc chạy)*, chống **serialization** *(chuyển object thành chuỗi byte để lưu/gửi)* phá vỡ, thread-safe sẵn.

> 💡 **Giải thích dễ hiểu — vì sao enum là singleton "bất khả xâm phạm"?**
> Một singleton tự viết bằng `private static` vẫn có hai "cửa hậu" phá được tính duy nhất: (1) reflection lách vào gọi constructor để tạo bản thứ hai; (2) deserialization đọc lại từ file tạo ra một object mới. Enum bịt cả hai: JVM **cấm** reflection tạo instance enum, và khi lưu/đọc enum nó chỉ ghi lại **cái tên** rồi ánh xạ về đúng con tem có sẵn. Ví von: các singleton thường như **chìa khóa nhà bạn tự làm** — thợ khéo vẫn đánh trộm được bản sao; còn singleton enum như **con dấu quốc huy** — luật (JVM) cấm sao chép, mọi bản đối chiếu đều quy về đúng một bản gốc.

```java
public enum DatabaseConnection {
    INSTANCE;

    private final Connection conn;
    DatabaseConnection() { this.conn = createConnection(); }
    public Connection get() { return conn; }
}
DatabaseConnection.INSTANCE.get();
```

> Vì sao tốt hơn `private static` singleton? Enum chống được: (1) reflection gọi constructor (JVM cấm `newInstance` trên enum), (2) deserialization tạo instance mới (enum serialize bằng `name`, deserialize map về constant có sẵn). Xem [[patterns/creational.md]] và [[core/serialization.md]].

---

## Compare – Enum vs int/String constants (kiểu cũ)

| | `public static final int` | Enum |
|--|---------------------------|------|
| Type-safety | Không (truyền nhầm int bất kỳ) | Có (compiler check) |
| Namespace | Phải tự prefix (`STATUS_NEW`) | Có sẵn (`Status.NEW`) |
| In ra tên | In số `0`, vô nghĩa | In `"NEW"` |
| Dùng trong `switch` | Có | Có (gọn hơn, exhaustive) |
| Gắn data/method | Không | Có |
| Tập hợp/Map | Phải tự code | `EnumSet`/`EnumMap` |

```java
// ❌ int constant pattern (anti-pattern)
public static final int STATUS_NEW = 0, STATUS_PAID = 1;
void process(int status) { ... } // gọi process(999) vẫn compile!

// ✅ enum
void process(Status status) { ... } // chỉ nhận Status hợp lệ
```

---

## Trade-offs & Pitfalls

### ⚠️ KHÔNG bao giờ persist `ordinal()`
`ordinal` thay đổi khi bạn **thêm/sắp xếp lại** constant → dữ liệu cũ hỏng.

> 💡 **Giải thích dễ hiểu — vì sao đừng lưu số thứ tự?**
> `ordinal()` là **vị trí chỗ ngồi** của enum trong danh sách khai báo, không phải danh tính của nó. Nếu bạn lưu số 1 vào DB cho `PAID`, rồi mai chèn thêm `DRAFT` lên đầu, mọi enum bị **dịch ghế**: `PAID` giờ là số 2, còn số 1 trong DB cũ bỗng bị đọc thành `DRAFT`. Ví von: như đánh số ghế trong rạp rồi kê thêm một hàng ghế đầu — vé cũ ghi "ghế số 5" giờ dẫn bạn tới nhầm chỗ. Hãy lưu `name()` (`"PAID"`) — cái tên đi theo nó dù xáo trộn thế nào.

```java
// ❌ Lưu ordinal vào DB
order.setStatus(status.ordinal());  // PAID=1, mai thêm DRAFT vào đầu → PAID=2, sai hết!

// ✅ Lưu name() hoặc một mã code riêng ổn định
@Enumerated(EnumType.STRING)  // JPA: lưu "PAID", KHÔNG dùng EnumType.ORDINAL
private Status status;
```

### ⚠️ `valueOf` ném exception với input lạ
```java
Status.valueOf("paid"); // IllegalArgumentException (phân biệt hoa thường)
// ✅ Parser an toàn:
public static Optional<Status> from(String s) {
    return Arrays.stream(values()).filter(v -> v.name().equalsIgnoreCase(s)).findFirst();
}
```

### Trade-offs tổng quát
- (+) Type-safe, đọc dễ, gắn được data/behavior, `EnumSet`/`EnumMap` siêu hiệu quả, singleton chuẩn.
- (−) Enum được load eager khi class init (mọi constant tạo ngay) – không lazy.
- (−) Không kế thừa được enum khác (chỉ implement interface để "mở rộng").
- (−) Thêm constant = thay đổi code (không cấu hình động được) → không hợp cho tập "thường xuyên đổi từ data" (vd: danh mục sản phẩm).

---

## Real-world Usage

### State Machine với enum
```java
public enum OrderState {
    NEW      { public OrderState next() { return PAID; } },
    PAID     { public OrderState next() { return SHIPPED; } },
    SHIPPED  { public OrderState next() { return DELIVERED; } },
    DELIVERED{ public OrderState next() { return this; } };  // terminal
    public abstract OrderState next();
}
```

### Strategy/lookup table
```java
public enum HttpMethod {
    GET(false), POST(true), PUT(true), DELETE(false);
    private final boolean hasBody;
    HttpMethod(boolean b) { this.hasBody = b; }
    public boolean hasBody() { return hasBody; }
}
```

- JPA: `@Enumerated(EnumType.STRING)` map enum ↔ cột DB.
- Jackson: serialize enum ra JSON string (xem [[core/json_jackson.md]]).
- Spring: `@RequestParam Status status` tự convert String → enum.

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[core/nested_classes.md]] (constant body = anonymous subclass), [[core/collections_internals.md]] (EnumSet/EnumMap), [[patterns/creational.md]] (enum singleton), [[core/serialization.md]] (enum serialize bằng name), [[core/object_methods.md]] (enum equals/compareTo final).
>
> Keyword cho topic kế: **Object methods** – `equals`/`hashCode` contract, `Comparable` vs `Comparator`, `clone`/`Cloneable`, `toString`.

*Cập nhật lần cuối: 2026-06-04*
