---
title: "Object Contract Methods: equals / hashCode / Comparable / clone (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Object Contract Methods: equals / hashCode / Comparable / clone (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – "Contract methods" là gì?

Mọi class trong Java kế thừa `java.lang.Object`, cung cấp các method mà **toàn bộ ecosystem** *(hệ sinh thái — các thư viện/thành phần xoay quanh)* **dựa vào**: **Collections** *(các cấu trúc chứa dữ liệu như HashMap, TreeSet)*, **serialization** *(tuần tự hóa — chuyển object thành chuỗi byte để lưu/truyền)*, debug... **Override** *(ghi đè — viết lại method của lớp cha)* sai các method này gây bug **ngầm và khó tìm** (mất phần tử trong Set, không tìm thấy key trong Map). Đây là các **"contract"** *(giao kèo — bộ quy tắc bắt buộc phải tuân thủ)* có quy tắc toán học bắt buộc.

> 💡 **Giải thích dễ hiểu — vì sao gọi là "contract" (giao kèo)?**
> Hãy hình dung Java Collections như một **hệ thống bưu điện khổng lồ**. Bạn đưa object cho nó cất giữ (bỏ vào HashMap, HashSet, TreeSet). Bưu điện chỉ hoạt động đúng nếu mọi bưu kiện tuân theo **quy chuẩn đóng gói chung** — ví dụ "hai bưu kiện giống hệt nhau thì phải có cùng mã vạch". Các method `equals`/`hashCode`/`compareTo` chính là quy chuẩn đó. Nếu bạn tự viết lại (override) mà làm sai quy chuẩn, bưu điện vẫn nhận hàng nhưng sẽ **giao nhầm, làm mất kiện** — mà không báo lỗi gì cả. Đó là loại bug "ngầm" đáng sợ nhất: code chạy, không crash, nhưng kết quả sai.
> Từ "contract" nhấn mạnh: đây không phải gợi ý, mà là **giao kèo ràng buộc** — vi phạm thì cả hệ thống hành xử sai.

`Object` có 11 method; nhóm quan trọng nhất để override đúng:
- `equals(Object)` + `hashCode()` – định nghĩa "bằng nhau"
- `toString()` – biểu diễn chuỗi
- `compareTo()` (qua `Comparable`) / `Comparator` – định nghĩa "thứ tự"
- `clone()` (qua `Cloneable`) – sao chép

> Bổ trợ cho [[oop/inheritance.md]] (đã giới thiệu equals/hashCode trong ngữ cảnh kế thừa); ở đây đi sâu vào **contract** và pitfall.

---

## How – `equals()` Contract (5 quy tắc)

`equals` mặc định ở `Object` là so sánh **identity** *(danh tính — có phải cùng một object trong bộ nhớ không)* (`==`, cùng địa chỉ). Khi override phải giữ 5 tính chất:

> 💡 **Giải thích dễ hiểu — 5 quy tắc của `equals`:**
> Mặc định, `equals` hỏi "có phải cùng **một** vật thể không?" — như hỏi hai người có phải cùng một người không (cùng chứng minh thư). Nhưng thường ta muốn hỏi "hai vật này có **giống nhau về nội dung** không?" — như hai tờ 50k tuy là hai tờ khác nhau nhưng giá trị như nhau. Đó là lý do phải override `equals`.
> Năm quy tắc chỉ là các đòi hỏi của lẽ thường về "bằng nhau", diễn đạt bằng ngôn ngữ toán:
> - **Reflexive** *(phản xạ)*: mọi vật luôn bằng chính nó (A = A).
> - **Symmetric** *(đối xứng)*: nếu A giống B thì B cũng phải giống A — không thể một chiều.
> - **Transitive** *(bắc cầu)*: A giống B, B giống C thì A giống C — như quan hệ họ hàng.
> - **Consistent** *(nhất quán)*: hỏi bao nhiêu lần cũng ra cùng đáp án (nếu object không đổi).
> - **Non-null**: so với `null` luôn trả `false`, không được ném lỗi.
> Nghe hiển nhiên, nhưng khi có kế thừa thì rất dễ vô tình phá vỡ (xem bẫy symmetry ngay dưới).

| Tính chất | Ý nghĩa |
|-----------|---------|
| **Reflexive** | `x.equals(x)` luôn `true` |
| **Symmetric** | `x.equals(y)` ⟺ `y.equals(x)` |
| **Transitive** | `x=y` và `y=z` ⟹ `x=z` |
| **Consistent** | Gọi nhiều lần kết quả không đổi (nếu object không đổi) |
| **Non-null** | `x.equals(null)` luôn `false` (không ném NPE) |

### Template chuẩn
```java
@Override
public boolean equals(Object o) {
    if (this == o) return true;                  // tối ưu identity
    if (o == null || getClass() != o.getClass()) return false; // xem mục dưới
    Point p = (Point) o;
    return x == p.x && y == p.y;                 // so sánh field "định danh"
}
```

### ⚠️ `getClass()` vs `instanceof` – bẫy đối xứng (symmetry)
```java
// Dùng instanceof → vi phạm symmetry khi có kế thừa
if (!(o instanceof Point)) return false; // ColorPoint instanceof Point = true
// Point.equals(ColorPoint) có thể true, nhưng ColorPoint.equals(Point) false → ASYMMETRIC!
```
- `getClass()`: nghiêm ngặt, đối xứng, nhưng **subclass không bao giờ bằng superclass** (vi phạm LSP nhẹ).
- `instanceof`: cho phép so giữa các class trong hệ thống kế thừa, nhưng dễ phá symmetry/transitivity.

> **Giải pháp tốt nhất (Effective Java – Item 10):** "Favor composition over inheritance" — không kế thừa class có state để thêm field định danh. Hoặc dùng **Record** (Java 16+) sinh `equals` đúng tự động. Xem [[modern/records.md]].

---

## How – `hashCode()` Contract (3 quy tắc)

| Quy tắc | Ý nghĩa |
|---------|---------|
| **Nhất quán** | Object không đổi → hashCode không đổi giữa các lần gọi |
| **equals ⟹ same hash** | `a.equals(b)` ⟹ `a.hashCode() == b.hashCode()` (**BẮT BUỘC**) |
| **(không bắt buộc)** | `!a.equals(b)` **không** yêu cầu khác hash (nhưng nên khác để giảm collision) |

> **Quy tắc sống còn:** Override `equals` thì **PHẢI** override `hashCode`. Nếu không → object "bằng nhau" lại có hash khác → `HashMap`/`HashSet` đặt vào bucket khác → **mất phần tử**.

```java
// ❌ Override equals mà quên hashCode
Map<Point, String> map = new HashMap<>();
map.put(new Point(1,2), "A");
map.get(new Point(1,2)); // null! (equals true nhưng hashCode khác → sai bucket)

// ✅ Override cả hai
@Override public int hashCode() { return Objects.hash(x, y); }
```

### Cách tính hashCode tốt
```java
// Cách hiện đại (gọn, hơi chậm do varargs/autoboxing)
@Override public int hashCode() { return Objects.hash(x, y, name); }

// Cách thủ công (nhanh, hot path) – thuật toán 31*h+field (Effective Java)
@Override public int hashCode() {
    int result = Integer.hashCode(x);
    result = 31 * result + Integer.hashCode(y);
    result = 31 * result + Objects.hashCode(name);
    return result;
}
```
> Số **31** được chọn vì là số nguyên tố lẻ, `31*i == (i<<5) - i` (JIT tối ưu thành shift). Chỉ đưa field tham gia `equals` vào `hashCode`. Liên hệ HashMap treeify/bucket: [[core/collections.md]].

---

## How – `Comparable` vs `Comparator`

| | `Comparable<T>` | `Comparator<T>` |
|--|-----------------|-----------------|
| Method | `int compareTo(T o)` | `int compare(T a, T b)` |
| Vị trí | **Bên trong** class (natural ordering) | **Bên ngoài** class |
| Số lượng thứ tự | 1 (thứ tự tự nhiên duy nhất) | Nhiều (tùy chiến lược) |
| Sửa class gốc | Có | Không (dùng cho class không sửa được) |

```java
// Comparable – thứ tự tự nhiên
class Person implements Comparable<Person> {
    int age;
    public int compareTo(Person o) { return Integer.compare(age, o.age); }
}

// Comparator – linh hoạt, dùng combinator (Java 8+)
Comparator<Person> byNameThenAge = Comparator
    .comparing(Person::getName)
    .thenComparing(Person::getAge)
    .reversed();

list.sort(byNameThenAge);
list.sort(Comparator.comparingInt(Person::getAge)); // tránh autoboxing
list.sort(Comparator.comparing(Person::getName, Comparator.nullsLast(naturalOrder())));
```

### ⚠️ Quy ước trả về & bẫy tràn số
```
compareTo trả về:  âm (this < o), 0 (bằng), dương (this > o)
```
```java
// ❌ Trừ trực tiếp → tràn int với số lớn/âm
return this.value - o.value;  // Integer.MIN_VALUE - 1 → tràn, sai thứ tự!
// ✅ Dùng Integer.compare
return Integer.compare(this.value, o.value);
```

### ⚠️ Consistency với equals
Khuyến nghị: `compareTo` **nhất quán** với `equals` (`compareTo==0` ⟺ `equals==true`). Nếu không, `TreeSet`/`TreeMap` (dùng compareTo) hành xử khác `HashSet` (dùng equals):
```java
// BigDecimal vi phạm: new BigDecimal("1.0").compareTo(new BigDecimal("1.00")) == 0
//                     nhưng .equals(...) == false (khác scale)
TreeSet<BigDecimal> ts = new TreeSet<>();  // coi 1.0 và 1.00 là TRÙNG
HashSet<BigDecimal> hs = new HashSet<>();  // coi 1.0 và 1.00 là KHÁC
```

---

## How – `clone()` & `Cloneable` (và vì sao nên tránh)

`Object.clone()` tạo bản sao field-by-field, nhưng cơ chế **đầy lỗi thiết kế**:
- `Cloneable` là **marker interface rỗng** (không có method `clone`) → "ma thuật" bật cờ cho `Object.clone()`.
- `clone()` là `protected` trong `Object` → phải override thành `public`.
- Không gọi constructor → bỏ qua logic khởi tạo/validation.
- Mặc định là **shallow copy** → object con vẫn share reference.

```java
class Stack implements Cloneable {
    private Object[] elements; private int size;

    @Override public Stack clone() {
        try {
            Stack result = (Stack) super.clone();      // shallow copy
            result.elements = elements.clone();        // PHẢI deep-copy mảng thủ công
            return result;
        } catch (CloneNotSupportedException e) { throw new AssertionError(); }
    }
}
```

### ✅ Thay thế clone bằng Copy Constructor / Copy Factory (Effective Java – Item 13)
```java
public Stack(Stack original) {                 // copy constructor
    this.elements = original.elements.clone();
    this.size = original.size;
}
public static Stack newInstance(Stack s) { ... } // copy factory
```
> Ưu điểm: không cần `Cloneable`, không ném checked exception, không cast, hoạt động với `final` field, có thể nhận interface (`new ArrayList<>(collection)`).

---

## How – `toString()`

Mặc định: `ClassName@hexHashCode` (vô dụng khi debug/log). Nên override để trả về thông tin **có ý nghĩa**:
```java
@Override public String toString() {
    return "Person{name=%s, age=%d}".formatted(name, age);
}
```
> Record (Java 16+) sinh `toString`/`equals`/`hashCode` tự động. Đừng đưa thông tin nhạy cảm (password, token) vào `toString` — dễ lộ qua log. Liên hệ [[core/logging.md]].

---

## When – Khi nào tự override vs để công cụ sinh?

| Tình huống | Giải pháp |
|-----------|-----------|
| Value object bất biến (DTO, key) | **Record** (Java 16+) – sinh equals/hashCode/toString chuẩn |
| Entity JPA | Cẩn thận: chỉ dùng **business key** ổn định, KHÔNG dùng `id` auto-gen (null trước persist) |
| Class mutable phức tạp | Lombok `@EqualsAndHashCode`/`@ToString` hoặc IDE generate |
| Cần thứ tự tự nhiên | `Comparable` |
| Cần nhiều cách sắp xếp | `Comparator` combinators |
| Cần sao chép object | Copy constructor (KHÔNG `clone()`) |

### ⚠️ Bẫy equals/hashCode trong JPA Entity
```java
@Entity class User {
    @Id @GeneratedValue Long id;  // null cho tới khi persist
    // ❌ equals/hashCode dựa trên id: trước persist id=null → 2 entity "bằng" nhau
    // ❌ Lombok @Data trên Entity: kéo lazy field → N+1, hoặc StackOverflow với quan hệ 2 chiều
    // ✅ Dùng business key (email/UUID gán lúc tạo) hoặc chỉ so theo id khi != null
}
```
Liên hệ [[data/jpa_hibernate.md]].

---

## Compare – `==` vs `equals()` vs `Objects.equals()`

| | `==` | `equals()` | `Objects.equals(a,b)` |
|--|------|-----------|------------------------|
| So sánh | Reference (primitive: giá trị) | Logic (nếu override) | Null-safe equals |
| Null | An toàn | NPE nếu `a` null | An toàn (cả 2 null → true) |
| Enum | Nên dùng | OK (final, = identity) | OK |

```java
Objects.equals(null, null);  // true
Objects.equals("a", null);   // false – không NPE
```

---

## Trade-offs

- (+) Override đúng → object hoạt động chuẩn với toàn bộ Collections, sort, dedup.
- (−) equals/hashCode dễ sai khi có kế thừa (symmetry/transitivity) → ưu tiên Record/composition.
- (−) `clone()` thiết kế lỗi → luôn dùng copy constructor.
- (−) `compareTo` không nhất quán equals → hành vi khác nhau giữa TreeSet và HashSet.
- (−) Mutable key trong HashMap: nếu sửa field sau khi put → hashCode đổi → mất key vĩnh viễn. **Key nên immutable.**

---

## Real-world Usage

```java
// Record: cách hiện đại cho value object/key – tự động đúng contract
record Money(long amount, String currency) implements Comparable<Money> {
    public int compareTo(Money o) { return Long.compare(amount, o.amount); }
}
Set<Money> set = new HashSet<>();  // equals/hashCode đã đúng, an toàn

// Comparator chaining cho sort phức tạp (báo cáo, leaderboard)
employees.sort(
    Comparator.comparing(Employee::getDept)
              .thenComparing(Employee::getSalary, Comparator.reverseOrder())
              .thenComparing(Employee::getName));
```

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[oop/inheritance.md]] (equals/hashCode trong kế thừa), [[modern/records.md]] (tự sinh contract), [[core/collections.md]] (hashCode → bucket; TreeMap dùng compareTo), [[core/enums.md]] (equals/compareTo final), [[data/jpa_hibernate.md]] (equals cho Entity).
>
> Keyword cho topic kế: **Serialization** – `Serializable`, `serialVersionUID`, `transient`, `Externalizable`, insecure deserialization.

*Cập nhật lần cuối: 2026-06-04*
