# Java Serialization & Insecure Deserialization (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Serialization là gì?

**Serialization** *(tuần tự hóa — biến object thành chuỗi byte)*: biến một object (và toàn bộ **object graph** *(đồ thị object — object cùng mọi object nó tham chiếu, nối nhau như mạng lưới)* nó tham chiếu) thành **chuỗi byte** để lưu xuống file/DB hoặc truyền qua mạng.
**Deserialization** *(giải tuần tự hóa — dựng lại object từ chuỗi byte)*: dựng lại object từ chuỗi byte đó.

Java có cơ chế serialization **built-in** *(tích hợp sẵn)* qua marker interface *(interface đánh dấu)* `java.io.Serializable`. Bản thân việc ghi object không phải lỗ hổng; rủi ro nghiêm trọng xuất hiện khi ứng dụng giải tuần tự dữ liệu mà bên không đáng tin có thể tạo hoặc sửa. OWASP xếp insecure deserialization vào nhóm A08:2021 – Software and Data Integrity Failures.

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

> 💡 **Giải thích dễ hiểu:**
> Serialization giống đóng băng cả một mô hình Lego thành kiện hàng byte; deserialization mở kiện và dựng lại các mảnh cùng liên kết. Nguy hiểm nằm ở chỗ một kiện hàng do người lạ chuẩn bị có thể yêu cầu hệ thống dựng cả những “mảnh máy” có hành vi ngoài dự kiến, không chỉ dữ liệu `User` mà lập trình viên mong đợi.

---

## How – Cơ chế hoạt động

### Object graph & rule lan truyền
- `writeObject` duyệt các non-static, non-transient field và ghi object **cùng các object reachable** *(có thể đi tới qua reference)*. Cơ chế **handle** *(mã nhận diện object trong stream)* giữ lại shared reference và xử lý vòng tham chiếu mà không ghi lặp vô hạn.
- Mọi object được chạm tới theo đường này cũng phải `Serializable`; nếu không, quá trình ghi ném `NotSerializableException`.
- Khi đọc, constructor của các class `Serializable` trong chuỗi kế thừa **không được gọi**. Tuy nhiên, constructor không tham số của superclass gần nhất **không** implement `Serializable` vẫn được gọi và phải truy cập được từ subclass.
- Vì constructor của class cần khôi phục bị bỏ qua, validation đặt duy nhất trong constructor có thể bị bypass *(đi vòng qua)*. Field được nạp từ stream phải được xem là input chưa tin cậy.

> 💡 **Giải thích dễ hiểu:**
> Object graph giống sơ đồ giao hàng: handle là mã kiện giúp hai địa chỉ cùng trỏ về đúng một kiện, thay vì sao chép thành hai kiện khác nhau. Khi mở hàng, Java dựng “tầng móng” không serializable bằng constructor, còn các tầng serializable phía trên được lắp từ dữ liệu stream nên cửa kiểm tra ở constructor của chúng không chạy.

### `transient` – loại field khỏi serialization
```java
class Session implements Serializable {
    String user;
    transient String password;        // KHÔNG serialize (giá trị → default null/0)
    transient Connection conn;         // resource không serialize được
}
```

`transient` chỉ loại field khỏi **default serialization** *(tuần tự hóa mặc định)*; custom `writeObject()` vẫn có thể chủ động ghi nó. Sau default deserialization, field transient mang default value (`null`, `0`, `false`...) cho đến khi code khôi phục lại.

### `serialVersionUID` – version của class
```java
class User implements Serializable {
    private static final long serialVersionUID = 1L; // KHAI BÁO TƯỜNG MINH
}
```
- Là "vân tay" version. Khi deserialize, nếu UID trong byte stream **khác** UID của class hiện tại → `InvalidClassException`.
- Nếu **không khai báo**, serialization runtime tự tính UID từ nhiều chi tiết cấu trúc class. Một thay đổi tưởng nhỏ như thêm method không private có thể làm UID đổi và **vỡ tương thích** với dữ liệu cũ.
- **Quy tắc:** với class Serializable thông thường có serial form cần duy trì, hãy khai báo tường minh `serialVersionUID`. Dùng `serialver` tool hoặc IDE để sinh. Record có quy tắc UID riêng như phần sau.

> 💡 **Giải thích dễ hiểu:**
> `serialVersionUID` giống số phiên bản trên khuôn lắp ráp. Nếu kiện hàng nói “khuôn 1” nhưng nhà máy chỉ còn “khuôn 2”, Java từ chối thay vì cố ghép sai. Giữ nguyên UID chỉ cho phép Java thử đọc; nó không tự biến mọi thay đổi schema thành tương thích.

---

## How – Tùy biến quá trình serialization

### `writeObject` / `readObject` – hook tùy biến
```java
class CustomData implements Serializable {
    private static final long serialVersionUID = 1L;
    private transient int[] cache;       // không serialize trực tiếp
    private int seed;

    private void writeObject(ObjectOutputStream out) throws IOException {
        out.defaultWriteObject();        // ghi field non-transient
        out.writeInt(cache == null ? 0 : cache.length); // tự ghi thêm
    }
    private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
        in.defaultReadObject();          // đọc field non-transient
        int len = in.readInt();
        if (len < 0 || len > 10_000) {    // chặn allocation/CPU quá mức trước khi dùng len
            throw new InvalidObjectException("invalid cache length: " + len);
        }
        this.cache = recompute(seed, len);
        validate();                      // kiểm tra invariant sau khi khôi phục
    }
}
```

`readObject` là hook chính để kiểm tra lại **invariant** *(điều kiện luôn phải đúng của object)* khi dùng default serial form. Ngoài ra còn có serialization proxy, `readResolve()` và `ObjectInputValidation`; vì vậy đây không phải “nơi duy nhất”. Quan trọng nhất là kiểm tra kích thước và giá trị **trước** khi allocation hoặc thực hiện công việc tốn kém.

> 💡 **Giải thích dễ hiểu:**
> `readObject` giống quầy kiểm hàng nhập khẩu. Không chỉ kiểm tra món hàng sau khi đã đưa vào kho; số lượng khai báo phải được chặn trước, nếu không kẻ xấu có thể ghi “một tỷ món” để buộc ứng dụng cấp phát bộ nhớ rồi mới báo sai.

### `Externalizable` – kiểm soát hoàn toàn
```java
class FastData implements Externalizable {
    private static final long serialVersionUID = 1L;

    public FastData() {}                 // BẮT BUỘC có constructor public no-arg
    @Override
    public void writeExternal(ObjectOutput out) throws IOException { /* tự ghi 100% */ }
    @Override
    public void readExternal(ObjectInput in) throws IOException, ClassNotFoundException {
        /* tự đọc 100%, kiểm tra trước khi cấp phát */
    }
}
```

| | `Serializable` | `Externalizable` |
|--|----------------|------------------|
| Cơ chế | Reflection tự động | Tự code 100% |
| Constructor khi deserialize | Constructor của class Serializable bị bỏ qua; constructor superclass không Serializable vẫn chạy | **Gọi** public no-arg constructor |
| Hiệu năng/kích thước | Có metadata; phụ thuộc object graph | Có thể tối ưu hơn, nhưng không được bảo đảm |
| Công sức | Ít | Nhiều, dễ sai |

`Externalizable` không tự ghi field nào: thứ tự, versioning, validation và giới hạn tài nguyên đều do ứng dụng chịu trách nhiệm. Public no-arg constructor cũng chạy trước `readExternal()`, nên không đặt side effect nguy hiểm trong constructor đó.

### `writeReplace` / `readResolve` – tráo object
```java
// readResolve: bảo toàn singleton khi deserialize (nếu không sẽ tạo instance MỚI!)
class Singleton implements Serializable {
    private static final long serialVersionUID = 1L;
    static final Singleton INSTANCE = new Singleton();
    private Singleton() {}
    private Object readResolve() { return INSTANCE; }  // trả về instance gốc
}
```

> 💡 **Giải thích dễ hiểu:**
> `writeReplace` đổi kiện hàng trước khi gửi; `readResolve` đổi vật vừa mở thành instance chuẩn trước khi giao cho caller. Với singleton, nó giống quầy nhận bản sao rồi trả lại đúng chiếc chìa khóa duy nhất của tòa nhà.

Đây là một lý do **enum singleton** ít lỗi hơn (xem [enums.md](enums.md)): enum được ghi bằng `name` và ánh xạ về constant có sẵn khi đọc, thay vì tạo instance enum mới.

### Serialization Proxy Pattern – buộc dữ liệu đi qua constructor

```java
final class RangeValue implements Serializable {
    private static final long serialVersionUID = 1L;
    private final int lo;
    private final int hi;

    RangeValue(int lo, int hi) {
        if (lo > hi) throw new IllegalArgumentException("lo > hi");
        this.lo = lo;
        this.hi = hi;
    }

    private Object writeReplace() {
        return new SerializationProxy(this);
    }

    // Từ chối stream cố dựng thẳng RangeValue để bypass proxy
    private void readObject(ObjectInputStream in) throws InvalidObjectException {
        throw new InvalidObjectException("proxy required");
    }

    private static final class SerializationProxy implements Serializable {
        private static final long serialVersionUID = 1L;
        private final int lo;
        private final int hi;

        SerializationProxy(RangeValue value) {
            this.lo = value.lo;
            this.hi = value.hi;
        }

        private Object readResolve() {
            return new RangeValue(lo, hi); // chạy lại validation trong constructor
        }
    }
}
```

**Serialization Proxy Pattern** *(mẫu object đại diện cho dạng tuần tự)* tách serial form khỏi internal field layout. Khi đọc, proxy gọi public/domain constructor để tái lập invariant; đổi lại pattern này thêm code và không phù hợp với class được thiết kế cho inheritance tùy ý.

---

## How – Record serialization (Java 16+)

Record có cơ chế serialization giúp bảo vệ invariant tốt hơn class Serializable thông thường:
- Serialize dựa trên **các component** (không phải field reflection).
- Deserialize **gọi canonical constructor** → mọi validation trong compact constructor được chạy → không bypass invariant.
- Các hook `writeObject`, `readObject`, `readObjectNoData`, `writeExternal` và `readExternal` bị bỏ qua.
- `writeReplace` và `readResolve` **vẫn có thể được áp dụng** để thay object. Với record, yêu cầu UID ở hai phía phải khớp cũng được miễn.

```java
record Range(int lo, int hi) implements Serializable {
    Range {  // compact constructor – validation NÀY được chạy cả khi deserialize
        if (lo > hi) throw new IllegalArgumentException("lo > hi");
    }
}
```

Record không biến native deserialization thành an toàn tuyệt đối: component của nó vẫn có thể kéo theo object nguy hiểm, và filter vẫn cần thiết tại **trust boundary** *(ranh giới giữa nguồn đáng tin và không đáng tin)*. Ngoài ra, vòng tham chiếu trong đó một component trỏ ngược trực tiếp hoặc gián tiếp về chính record không được bảo toàn do component phải được đọc trước khi canonical constructor chạy.

> 💡 **Giải thích dễ hiểu:**
> Record giống mẫu đơn bắt buộc đi qua quầy kiểm tra chính thức (canonical constructor) khi được dựng lại, nên khó lách quy tắc `lo <= hi`. Nhưng các món đính kèm trong hồ sơ vẫn phải soi; một phong bì hợp lệ không làm nội dung bên trong tự động đáng tin.

Xem thêm [records.md](../modern/records.md) và [Java Object Serialization Specification của Oracle](https://docs.oracle.com/en/java/javase/21/docs/specs/serialization/).

---

## ⚠️ Insecure Deserialization – Rủi ro dẫn tới RCE nghiêm trọng

### Vì sao deserialize dữ liệu không tin cậy = RCE?

`ObjectInputStream.readObject()` để nội dung stream quyết định các serializable class/proxy có sẵn trên classpath cần được resolve và các object nào được dựng. Trong quá trình đó, callback như `readObject`, `readResolve`, `readExternal`, public no-arg constructor của `Externalizable`, constructor của superclass không Serializable hoặc hành vi khi khôi phục collection có thể chạy **trước khi caller nhận kết quả**.

Kẻ tấn công có thể ghép các class sẵn có thành **gadget** *(mảnh code có hành vi hữu ích cho tấn công)* và nối chúng thành **gadget chain** *(chuỗi gadget)*. Nếu classpath và điều kiện phù hợp, chuỗi này có thể dẫn tới **RCE** *(thực thi mã từ xa)* hoặc các tác động khác như đọc file, gọi mạng và **denial of service (DoS)** *(từ chối dịch vụ)*.

```
Bytes độc hại → readObject() → kích hoạt gadget chain → Runtime.getRuntime().exec("rm -rf /")
                                (KHÔNG cần cast, RCE xảy ra TRƯỚC dòng (User) cast)
```

> 💡 **Giải thích dễ hiểu:**
> Cast `(User)` giống nhân viên kiểm tên người nhận ở cửa ra. Gadget đã chạy trong kho trước khi kiện hàng tới cửa đó, nên kiểm kiểu sau `readObject()` không phải hàng rào bảo mật.

### Gadget chain kinh điển
- **Apache Commons Collections** (`InvokerTransformer`, `ChainedTransformer`) – họ gadget nổi tiếng được công bố rộng rãi năm 2015 và ảnh hưởng nhiều sản phẩm Java khi endpoint deserialization có thể bị tiếp cận.
- Spring, Groovy, Hibernate, BeanShell... đều từng có gadget.
- Công cụ tạo payload: **ysoserial**.

```java
// ❌ CỰC KỲ NGUY HIỂM: deserialize dữ liệu từ user/network/cache
public Object handle(byte[] untrustedBytes) throws Exception {
    try (var ois = new ObjectInputStream(new ByteArrayInputStream(untrustedBytes))) {
        return ois.readObject(); // có thể bị khai thác nếu classpath chứa gadget phù hợp
    }
}
```

### Nơi lỗ hổng hay ẩn náu
Endpoint RMI/JMX hoặc `T3`/IIOP cũ hay cấu hình sai, cache phân tán legacy, HTTP session lưu serialized object, message queue truyền Java object và viewstate là các vị trí cần kiểm kê. “Nội bộ” không đồng nghĩa “đáng tin”: SSRF, máy đã bị chiếm quyền hoặc quyền ghi vào cache vẫn có thể đưa payload tới điểm đọc.

---

## How – Phòng thủ Insecure Deserialization

### 1. Tốt nhất: KHÔNG deserialize dữ liệu không tin cậy
Dùng schema/DTO nhỏ với JSON, Protobuf hoặc định dạng dữ liệu phù hợp thay vì khôi phục một object graph Java tùy ý. Các định dạng này giảm bề mặt gadget, nhưng parser vẫn phải giới hạn kích thước/độ sâu; với Jackson cần tránh **polymorphic typing** *(chọn subtype dựa trên dữ liệu đầu vào)* quá rộng và chỉ cho phép subtype dự kiến. Xem [json_jackson.md](json_jackson.md).

### 2. JEP 290 – Serialization Filter (Java 9+, backport 8u121+)

[JEP 290](https://openjdk.org/jeps/290) cung cấp `ObjectInputFilter` để tạo **allowlist** *(danh sách class được phép)* hoặc **reject-list** *(danh sách class bị cấm)*, đồng thời giới hạn độ sâu, số reference, byte đã đọc và kích thước array. Filter **không được bật sẵn**; ứng dụng phải cấu hình theo stream hoặc toàn JVM trước khi gọi `readObject()`.

```java
// Ví dụ DTO chỉ chứa dữ liệu đơn giản: allowlist tối thiểu + giới hạn tài nguyên
var filter = ObjectInputFilter.Config.createFilter(
    "maxdepth=10;maxrefs=1000;maxbytes=1048576;maxarray=10000;" +
    "com.myapp.dto.CommandDto;java.base/java.lang.String;!*"
);
try (ObjectInputStream ois = new ObjectInputStream(in)) {
    ois.setObjectInputFilter(filter);   // phải set trước lần readObject đầu tiên
    CommandDto command = (CommandDto) ois.readObject();
}

// Hoặc filter toàn JVM
// -Djdk.serialFilter="maxdepth=10;maxrefs=1000;com.myapp.dto.CommandDto;!*"
```

Pattern được xét từ trái sang phải; whitespace có ý nghĩa. Filter class không kiểm tra invariant của field, vì vậy vẫn phải validate dữ liệu sau khi đọc. Cũng không nên allow toàn bộ `java.base/*` nếu use case chỉ cần vài type cụ thể.

> 💡 **Giải thích dễ hiểu:**
> Filter vừa là danh sách khách mời, vừa là giới hạn sức chứa tòa nhà. Allowlist chặn người lạ; `maxdepth`, `maxrefs` và `maxarray` chặn khách hợp lệ mang theo một đoàn hoặc kiện hàng khổng lồ để làm cạn tài nguyên.

**[JEP 415](https://openjdk.org/jeps/415) (Java 17)** bổ sung filter factory toàn JVM để chọn hoặc kết hợp filter theo từng ngữ cảnh deserialization. Điều này hữu ích khi thư viện tạo `ObjectInputStream` bên trong và ứng dụng không trực tiếp gọi `setObjectInputFilter()`.

### 3. Look-ahead deserialization *(kiểm tra class trước khi dựng — giải pháp cũ)*
Override `resolveClass` để chặn class không cho phép, hoặc dùng Apache Commons IO `ValidatingObjectInputStream`. Cách này không cung cấp đầy đủ metric về graph/array như `ObjectInputFilter`, cần xử lý proxy class riêng và không nên là lựa chọn mới mặc định.

### 4. Phòng thủ chiều sâu
- Cập nhật thư viện (loại gadget đã biết), chạy `dependency-check`.
- Xác thực **trước khi deserialize** bằng chữ ký/MAC hoặc authenticated encryption *(mã hóa có xác thực)* khi có mô hình quản lý khóa đáng tin. Biện pháp này chứng minh nguồn và tính toàn vẹn, nhưng không làm payload từ một producer bị xâm nhập trở nên an toàn; filter vẫn cần thiết. Xem [crypto_fundamentals.md](../../security/crypto/crypto_fundamentals.md).
- Chạy với quyền tối thiểu, network egress filtering.

---

## When – Khi nào dùng Java Serialization?

| Tình huống | Khuyến nghị |
|-----------|-------------|
| API mới, dữ liệu qua mạng/lưu trữ | ❌ **Tránh** → dùng JSON/Protobuf |
| Trao đổi với hệ thống Java legacy bắt buộc | Xác thực nguồn, có filter JEP 290/415 và giới hạn tài nguyên |
| Cache nội bộ, RMI nội bộ | Cân nhắc thay bằng định dạng khác |
| Deep copy object trong bộ nhớ | Dùng copy constructor (xem [object_methods.md](object_methods.md)), không serialize |

> **Effective Java – Item 85:** "Prefer alternatives to Java serialization." Item 86–90: nếu buộc phải dùng, hãy cực kỳ cẩn thận.

---

## Compare – Java Serialization vs các định dạng khác

| | Java Serialization | JSON (Jackson) | Protobuf | Avro |
|--|--------------------|----------------|----------|------|
| Cross-language | Không (chỉ Java) | Có | Có | Có |
| Bề mặt deserialization | Cao: dựng object graph Java + callback | Thấp hơn nếu bind DTO; polymorphic config vẫn rủi ro | Thấp hơn nhờ schema; vẫn phải giới hạn input | Thấp hơn nhờ schema; vẫn phải giới hạn input |
| Kích thước | Thường lớn do metadata | Thường trung bình do text | Thường nhỏ nhờ binary schema | Thường nhỏ nhờ binary schema |
| Human-readable | Không | Có | Không | Không |
| Schema evolution | Mong manh, cần quản lý serial form/UID | Linh hoạt nhưng cần contract | Tốt nếu giữ field number đúng quy tắc | Tốt với writer/reader schema |
| Hiệu năng | Phụ thuộc graph/metadata | Phụ thuộc parser và payload text | Thường gọn/nhanh | Thường gọn/nhanh |

Các nhận xét kích thước và hiệu năng là xu hướng, không phải bảo đảm. Cần benchmark với schema, payload, thư viện và cấu hình thật; chọn định dạng trước hết theo contract, khả năng evolution và trust boundary.

> 💡 **Giải thích dễ hiểu:**
> Java Serialization gửi cả “bản thiết kế nhà Java”, còn JSON gửi văn bản và Protobuf/Avro gửi dữ liệu theo mẫu đã thống nhất. Mẫu càng chặt thì bên nhận càng ít phải đoán, nhưng bất kỳ xe hàng nào cũng cần giới hạn kích thước để tránh làm đầy kho.

---

## Trade-offs

- (+) Java Serialization: tích hợp sẵn, giữ được đồ thị object phức tạp, ít code.
- (−) **Bề mặt tấn công lớn** (có thể dẫn tới RCE), khớp version mong manh (`serialVersionUID`), chỉ Java và làm lộ chi tiết triển khai qua serial form; chi phí metadata/duyệt graph cần được đo trên payload thực tế.
- (+) JEP 290 filter giảm rủi ro nhưng **không loại bỏ hoàn toàn** — vẫn cần allowlist chặt.
- Kết luận chuyên gia: **mặc định không dùng** Java native serialization cho dữ liệu vượt ranh giới tin cậy.

---

## Real-world Usage

```java
// DTO legacy buộc phải dùng native serialization; đây chỉ là một lớp phòng thủ
public final class CommandDto implements Serializable {
    private static final long serialVersionUID = 1L;
    private static final Set<String> ALLOWED_ACTIONS = Set.of("START", "STOP");
    private final String action;
    private CommandDto(String a) { this.action = Objects.requireNonNull(a); }

    private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
        in.defaultReadObject();
        if (action == null || !ALLOWED_ACTIONS.contains(action)) {
            throw new InvalidObjectException("unsupported action"); // re-validate
        }
    }
}

static CommandDto readCommand(InputStream in) throws IOException, ClassNotFoundException {
    var filter = ObjectInputFilter.Config.createFilter(
        "maxdepth=5;maxrefs=50;maxbytes=65536;maxarray=1000;" +
        "com.myapp.dto.CommandDto;java.base/java.lang.String;!*"
    );
    try (var ois = new ObjectInputStream(in)) {
        ois.setObjectInputFilter(filter);
        return (CommandDto) ois.readObject();
    }
}
```

Filter giới hạn loại/cấu trúc, còn `readObject()` giới hạn giá trị nghiệp vụ. Hai lớp giải quyết hai câu hỏi khác nhau và không thay thế xác thực nguồn dữ liệu.

- Với Spring Session, có thể cấu hình JSON serializer để tránh phụ thuộc JDK serial form; vẫn phải khóa chặt polymorphic type và giới hạn dữ liệu đầu vào.
- Kafka: dùng JSON/Avro/Protobuf serializer có contract, không tự xây serializer bằng `ObjectOutputStream` cho message vượt trust boundary. Xem [messaging.md](messaging.md).

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [json_jackson.md](json_jackson.md) (giải pháp thay thế), [enums.md](enums.md) (enum singleton và serialization), [records.md](../modern/records.md) (record serialization), [object_methods.md](object_methods.md) (deep copy), [owasp_top10.md](../../security/web/owasp_top10.md) (A08), [messaging.md](messaging.md) (serializer cho Kafka).
>
> Keyword cho topic kế: **Jackson/JSON** – ObjectMapper, `@JsonProperty`, custom serializer/deserializer, polymorphic typing, default typing RCE.

*Cập nhật lần cuối: 2026-07-22*
