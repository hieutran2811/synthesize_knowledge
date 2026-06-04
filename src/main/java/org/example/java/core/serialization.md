# Java Serialization & Insecure Deserialization (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Serialization là gì?

**Serialization**: biến một object (và toàn bộ đồ thị object nó tham chiếu) thành **chuỗi byte** để lưu xuống file/DB hoặc truyền qua mạng.
**Deserialization**: dựng lại object từ chuỗi byte đó.

Java có cơ chế serialization **built-in** qua interface đánh dấu `java.io.Serializable`. Nghe tiện, nhưng đây là một trong những **lỗ hổng bảo mật nguy hiểm nhất** của Java (OWASP A08:2021 – Software and Data Integrity Failures).

```java
class User implements Serializable { String name; int age; }

// Serialize
try (var oos = new ObjectOutputStream(new FileOutputStream("user.ser"))) {
    oos.writeObject(new User());
}
// Deserialize
try (var ois = new ObjectInputStream(new FileInputStream("user.ser"))) {
    User u = (User) ois.readObject();  // ⚠️ điểm nguy hiểm
}
```

---

## How – Cơ chế hoạt động

### Object graph & rule lan truyền
- `writeObject` ghi object **và mọi object nó tham chiếu** (đệ quy, theo đồ thị) — xử lý cả vòng tham chiếu (cycle) bằng "handle".
- **Mọi field reference** cũng phải `Serializable`, nếu không → `NotSerializableException`.
- Deserialization **KHÔNG gọi constructor** của class Serializable — JVM cấp phát object bằng cơ chế riêng (`Unsafe.allocateInstance` đại ý) rồi đổ field vào. → bỏ qua mọi validation trong constructor (đây là gốc rễ của nhiều lỗ hổng).

### `transient` – loại field khỏi serialization
```java
class Session implements Serializable {
    String user;
    transient String password;        // KHÔNG serialize (giá trị → default null/0)
    transient Connection conn;         // resource không serialize được
}
```

### `serialVersionUID` – version của class
```java
class User implements Serializable {
    private static final long serialVersionUID = 1L; // KHAI BÁO TƯỜNG MINH
}
```
- Là "vân tay" version. Khi deserialize, nếu UID trong byte stream **khác** UID của class hiện tại → `InvalidClassException`.
- Nếu **không khai báo**, compiler tự sinh dựa trên cấu trúc class (tên, field, method...) → chỉ cần đổi nhỏ (thêm method) là UID đổi → **vỡ tương thích** dữ liệu cũ.
- **Quy tắc:** luôn khai báo tường minh `serialVersionUID` cho class Serializable. Dùng `serialver` tool hoặc IDE để sinh.

---

## How – Tùy biến quá trình serialization

### `writeObject` / `readObject` – hook tùy biến
```java
class CustomData implements Serializable {
    private transient int[] cache;       // không serialize trực tiếp
    private int seed;

    private void writeObject(ObjectOutputStream out) throws IOException {
        out.defaultWriteObject();        // ghi field non-transient
        out.writeInt(cache.length);      // tự ghi thêm
    }
    private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
        in.defaultReadObject();          // đọc field non-transient
        int len = in.readInt();
        this.cache = recompute(seed, len);
        validate();                      // ⚠️ NÊN validate ở đây (constructor bị bỏ qua!)
    }
}
```
> `readObject` là nơi **duy nhất** để chạy lại validation/invariant mà constructor đáng lẽ làm.

### `Externalizable` – kiểm soát hoàn toàn
```java
class FastData implements Externalizable {
    public FastData() {}                 // BẮT BUỘC có constructor public no-arg
    public void writeExternal(ObjectOutput out) throws IOException { /* tự ghi 100% */ }
    public void readExternal(ObjectInput in) throws IOException { /* tự đọc 100% */ }
}
```

| | `Serializable` | `Externalizable` |
|--|----------------|------------------|
| Cơ chế | Reflection tự động | Tự code 100% |
| Constructor khi deserialize | Không gọi | **Gọi** no-arg constructor |
| Hiệu năng | Chậm (reflection, metadata) | Nhanh hơn, gọn hơn |
| Công sức | Ít | Nhiều, dễ sai |

### `writeReplace` / `readResolve` – tráo object
```java
// readResolve: bảo toàn singleton khi deserialize (nếu không sẽ tạo instance MỚI!)
class Singleton implements Serializable {
    static final Singleton INSTANCE = new Singleton();
    private Object readResolve() { return INSTANCE; }  // trả về instance gốc
}
```
> Đây là lý do **enum singleton** an toàn hơn (xem [[core/enums.md]]): enum được serialize bằng `name`, deserialize map về constant có sẵn, không tạo instance mới.

---

## How – Record serialization (Java 16+)

Record có cơ chế serialization **an toàn hơn hẳn**:
- Serialize dựa trên **các component** (không phải field reflection).
- Deserialize **gọi canonical constructor** → mọi validation trong compact constructor được chạy → không bypass invariant.
- `readObject`/`writeObject`/`readResolve` của record bị **bỏ qua** (không cho phép tùy biến nguy hiểm).

```java
record Range(int lo, int hi) implements Serializable {
    Range {  // compact constructor – validation NÀY được chạy cả khi deserialize
        if (lo > hi) throw new IllegalArgumentException("lo > hi");
    }
}
```
> Liên hệ [[modern/records.md]]. Đây là một lý do nữa để ưu tiên record cho value object.

---

## ⚠️ Insecure Deserialization – Lỗ hổng RCE nghiêm trọng

### Vì sao deserialize dữ liệu không tin cậy = RCE?

`ObjectInputStream.readObject()` sẽ **khởi tạo object của BẤT KỲ class nào** có trong classpath dựa theo byte stream, và **chạy `readObject`/`readResolve`/`finally`...** của chúng. Kẻ tấn công không cần class của bạn — họ ghép các class có sẵn trong thư viện (gọi là **gadget**) thành một **gadget chain**: chuỗi lời gọi method được kích hoạt **trong lúc deserialize**, cuối cùng dẫn tới `Runtime.exec()`.

```
Bytes độc hại → readObject() → kích hoạt gadget chain → Runtime.getRuntime().exec("rm -rf /")
                                (KHÔNG cần cast, RCE xảy ra TRƯỚC dòng (User) cast)
```

### Gadget chain kinh điển
- **Apache Commons Collections** (`InvokerTransformer`, `ChainedTransformer`) – CVE nổi tiếng nhất (2015), hạ gục WebLogic, JBoss, Jenkins, WebSphere.
- Spring, Groovy, Hibernate, BeanShell... đều từng có gadget.
- Công cụ tạo payload: **ysoserial**.

```java
// ❌ CỰC KỲ NGUY HIỂM: deserialize dữ liệu từ user/network/cache
public Object handle(byte[] untrustedBytes) throws Exception {
    var ois = new ObjectInputStream(new ByteArrayInputStream(untrustedBytes));
    return ois.readObject();   // RCE nếu classpath có gadget
}
```

### Nơi lỗ hổng hay ẩn náu
RMI, JMX, một số cấu hình cache phân tán (cũ), HTTP session lưu serialized object, message queue truyền Java object, `T3`/IIOP protocol, viewstate.

---

## How – Phòng thủ Insecure Deserialization

### 1. Tốt nhất: KHÔNG deserialize dữ liệu không tin cậy
Dùng định dạng dữ liệu **không thực thi code**: JSON (Jackson), Protobuf. Xem [[core/json_jackson.md]].

### 2. JEP 290 – Serialization Filter (Java 9+, backport 8u121+)
Whitelist/blacklist class được phép deserialize, giới hạn độ sâu/số lượng object.
```java
// Filter theo pattern (allowlist là an toàn nhất)
var filter = ObjectInputFilter.Config.createFilter(
    "com.myapp.dto.*;java.base/*;!*"   // chỉ cho phép DTO của mình + JDK base; cấm còn lại
);
ObjectInputStream ois = new ObjectInputStream(in);
ois.setObjectInputFilter(filter);

// Hoặc filter toàn JVM
// -Djdk.serialFilter=com.myapp.*;!*
```
> **JEP 415 (Java 17):** context-specific filter factory — đặt filter theo từng luồng/ngữ cảnh.

### 3. Look-ahead deserialization (cũ, trước JEP 290)
Override `resolveClass` để chặn class không cho phép (Apache Commons IO `ValidatingObjectInputStream`).

### 4. Phòng thủ chiều sâu
- Cập nhật thư viện (loại gadget đã biết), chạy `dependency-check`.
- Ký + mã hóa dữ liệu serialized (chống sửa đổi) — xem [[security/crypto/crypto_fundamentals.md]] nếu có.
- Chạy với quyền tối thiểu, network egress filtering.

---

## When – Khi nào dùng Java Serialization?

| Tình huống | Khuyến nghị |
|-----------|-------------|
| API mới, dữ liệu qua mạng/lưu trữ | ❌ **Tránh** → dùng JSON/Protobuf |
| Trao đổi với hệ thống Java legacy bắt buộc | Dùng, **có filter JEP 290** + chỉ trong mạng tin cậy |
| Cache nội bộ, RMI nội bộ | Cân nhắc thay bằng định dạng khác |
| Deep copy object trong bộ nhớ | Dùng copy constructor (xem [[core/object_methods.md]]), không serialize |

> **Effective Java – Item 85:** "Prefer alternatives to Java serialization." Item 86–90: nếu buộc phải dùng, hãy cực kỳ cẩn thận.

---

## Compare – Java Serialization vs các định dạng khác

| | Java Serialization | JSON (Jackson) | Protobuf | Avro |
|--|--------------------|----------------|----------|------|
| Cross-language | Không (chỉ Java) | Có | Có | Có |
| Bảo mật deserialize | ❌ RCE risk | An toàn hơn (vẫn cần cẩn thận polymorphic) | An toàn | An toàn |
| Kích thước | Lớn (metadata) | Trung bình (text) | Nhỏ (binary) | Nhỏ |
| Human-readable | Không | Có | Không | Không |
| Schema evolution | Khó (serialVersionUID) | Linh hoạt | Tốt (field number) | Tốt nhất |
| Hiệu năng | Chậm | Trung bình | Nhanh | Nhanh |

---

## Trade-offs

- (+) Java Serialization: tích hợp sẵn, giữ được đồ thị object phức tạp, ít code.
- (−) **Bề mặt tấn công khổng lồ** (RCE), khớp version mong manh (serialVersionUID), chỉ Java, chậm, lộ chi tiết class private (encapsulation leak).
- (+) JEP 290 filter giảm rủi ro nhưng **không loại bỏ hoàn toàn** — vẫn cần allowlist chặt.
- Kết luận chuyên gia: **mặc định không dùng** Java native serialization cho dữ liệu vượt ranh giới tin cậy.

---

## Real-world Usage

```java
// Pattern an toàn cho DTO nội bộ buộc phải serialize:
public final class CommandDto implements Serializable {
    private static final long serialVersionUID = 1L;
    private final String action;
    private CommandDto(String a) { this.action = Objects.requireNonNull(a); }

    private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
        in.defaultReadObject();
        if (action == null) throw new InvalidObjectException("action required"); // re-validate
    }
}
// Phía đọc: luôn set filter
ois.setObjectInputFilter(ObjectInputFilter.Config.createFilter("com.myapp.dto.*;!*"));
```

- Spring Session lưu HttpSession (cấu hình dùng JSON serializer thay vì JDK serializer để an toàn).
- Kafka: dùng JSON/Avro/Protobuf serializer, **không** dùng `JavaSerializer` cho dữ liệu ngoài. Xem [[core/messaging.md]].

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[core/json_jackson.md]] (giải pháp thay thế an toàn), [[core/enums.md]] (enum singleton & serialization), [[modern/records.md]] (record serialization an toàn), [[core/object_methods.md]] (deep copy thay clone), [[security/web/owasp_top10.md]] (A08 – nếu có), [[core/messaging.md]] (serializer cho Kafka).
>
> Keyword cho topic kế: **Jackson/JSON** – ObjectMapper, `@JsonProperty`, custom serializer/deserializer, polymorphic typing, default typing RCE.

*Cập nhật lần cuối: 2026-06-04*
