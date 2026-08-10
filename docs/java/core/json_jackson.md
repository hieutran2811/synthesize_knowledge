---
title: "JSON Processing với Jackson (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: 2026-07-22
last_verified: null
version_scope: "unspecified"
source_count: 5
---
# JSON Processing với Jackson (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Jackson là gì?

**Jackson** là hệ sinh thái thư viện xử lý **JSON (JavaScript Object Notation)** *(định dạng văn bản biểu diễn dữ liệu có cấu trúc)* rất phổ biến trong Java. Khi Jackson có trên **classpath** *(danh sách thư viện JVM có thể nạp)* và được framework chọn làm JSON converter, Spring có thể dùng nó để chuyển đổi hai chiều giữa Java object và JSON qua **data binding** *(ánh xạ dữ liệu tự động giữa object và JSON)*.

JSON không mang sẵn hành vi Java như **native serialization** *(cơ chế tuần tự hóa object graph riêng của Java)*, nên thường phù hợp hơn cho API và giao tiếp liên hệ thống. Tuy nhiên, Jackson không mặc nhiên “an toàn”: cấu hình **polymorphic typing** *(ánh xạ đa hình dựa trên thông tin type)* quá rộng, **custom deserializer** *(bộ đọc JSON tự viết cho một type)* thiếu kiểm tra hoặc payload không giới hạn vẫn có thể tạo lỗ hổng. Đây cũng không phải thay thế tương thích trực tiếp cho mọi use case của Java native serialization (xem [serialization.md](serialization.md)).

> 💡 **Giải thích dễ hiểu:**
> Jackson giống một **phiên dịch viên giữa phiếu giao hàng và kho Java**: nó đọc tờ JSON rồi xếp dữ liệu vào đúng object, hoặc làm chiều ngược lại. Phiên dịch viên không mang cả “máy móc biết chạy” qua biên giới như native serialization, nhưng vẫn phải kiểm tra người gửi, loại hàng và kích thước kiện hàng.

> ℹ️ Các ví dụ API trong file chủ yếu dùng tên package của Jackson 2.x (`com.fasterxml.jackson...`). Jackson 3 thay đổi package/API cấu hình và làm mapper bất biến hơn; hãy dùng BOM hoặc dependency management của framework để giữ các module cùng dòng version, rồi xem migration guide trước khi nâng major version.

---

## Components – 3 module lõi

| Module | Vai trò |
|--------|---------|
| `jackson-core` | **Streaming API** *(API xử lý tuần tự từng token)*: `JsonParser` (đọc), `JsonGenerator` (ghi) – tầng thấp nhất |
| `jackson-databind` | `ObjectMapper` – data binding **POJO** *(Plain Old Java Object — object Java thông thường)* ↔ JSON, **tree model** *(mô hình cây JSON trong bộ nhớ)* bằng `JsonNode` |
| `jackson-annotations` | Các annotation `@JsonProperty`, `@JsonIgnore`... |

Trong Jackson 2.x, module mở rộng phổ biến gồm `jackson-datatype-jsr310` (Java Time), `jackson-module-parameter-names`, `jackson-datatype-jdk8` (`Optional`) và các dataformat cho XML/YAML/CSV. Thành phần/module có thể đổi giữa major version; không trộn tùy tiện các minor version của core và extension module.

---

## How – 3 cách xử lý JSON

### 1. Data Binding (phổ biến nhất) – POJO ↔ JSON
```java
ObjectMapper mapper = JsonMapper.builder().build();

// Serialize (Java → JSON)
String json = mapper.writeValueAsString(user);          // {"name":"An","age":30}

// Deserialize (JSON → Java)
User u = mapper.readValue(json, User.class);

// Generic type (List, Map) → TypeReference giữ thông tin type tại runtime
List<User> users = mapper.readValue(json, new TypeReference<List<User>>() {});
```

### 2. Tree Model – `JsonNode` (khi cấu trúc động/không biết trước)
```java
JsonNode root = mapper.readTree(json);
String name = root.path("user").path("name").asText(null);
int age = root.path("age").asInt(0);

if (root instanceof ObjectNode object) {
    object.put("active", true);                           // chỉ object node mới put được field
}
```

`path()` trả `MissingNode` khi không tìm thấy nên có thể nối nhiều bước mà không ném `NullPointerException`; tham số của `asText(null)`/`asInt(0)` là giá trị mặc định. Ngược lại, `get()` có thể trả Java `null`, vì vậy phải kiểm tra trước khi gọi tiếp. Giá trị mặc định cũng có thể che mất dữ liệu bắt buộc, nên hãy validate DTO/schema thay vì coi `0` hay `null` luôn hợp lệ.

### 3. Streaming API – kiểm soát token và dùng ít bộ nhớ (file JSON lớn)
```java
try (JsonParser p = mapper.getFactory().createParser(file)) {
    while (p.nextToken() != null) {
        if (p.currentToken() == JsonToken.FIELD_NAME && "email".equals(p.currentName())) {
            JsonToken valueToken = p.nextToken();
            if (valueToken == JsonToken.VALUE_STRING) {
                process(p.getText());
            }
        }
    }
}
```

> So sánh nhanh: Data binding ưu tiên tiện lợi; Tree ưu tiên cấu trúc động/chỉnh sửa; Streaming ưu tiên kiểm soát và không giữ cả document trong RAM. Hiệu năng thực tế vẫn phải đo theo payload và logic xử lý.

> 💡 **Giải thích dễ hiểu — ba mô hình:**
> Data binding giống nhận **nguyên kiện hàng đã phân loại** thành `User`; Tree giống mở kiện rồi giữ toàn bộ sơ đồ ngăn hộp để sửa linh hoạt; Streaming giống đứng bên băng chuyền, đọc từng món rồi xử lý ngay. Streaming thường dùng ít bộ nhớ nhất vì không cần giữ cả cây/object graph, nhưng code phải tự quản token và trạng thái cẩn thận hơn.

---

## How – ObjectMapper: cấu hình & thread-safety

Với Jackson 2.x, `ObjectMapper` có thể dùng đồng thời giữa nhiều thread nếu toàn bộ cấu hình hoàn tất **trước lần đọc/ghi đầu tiên** và không bị thay đổi trong lúc chạy. Mapper còn giữ cache serializer/deserializer, vì vậy thông thường nên tạo một instance đã cấu hình cho mỗi bộ quy tắc JSON và tái sử dụng qua **dependency injection** *(truyền dependency đã cấu hình từ bên ngoài)*. Không `new ObjectMapper()` trong mỗi request.

Jackson 3 xây mapper theo builder và làm mapper bất biến; chi tiết API khác 2.x. Dù ở major version nào, tránh lấy một mapper đang phục vụ request rồi gọi `registerModule()`, `enable()` hoặc `disable()` động.

> 💡 **Giải thích dễ hiểu — cấu hình rồi mới dùng:**
> `ObjectMapper` giống **bộ quy chuẩn đóng gói của một kho hàng**. Hãy thống nhất nhãn, đơn vị đo và cách ghi ngày trước khi mở cửa kho. Nếu vừa giao hàng cho nhiều xe vừa thay quy chuẩn, mỗi xe có thể nhận kết quả khác nhau. `ObjectReader`/`ObjectWriter` là những “phiếu hướng dẫn đã chốt” cho từng loại hàng.

```java
ObjectMapper mapper = JsonMapper.builder()
    // Serialize: bỏ field null
    .serializationInclusion(JsonInclude.Include.NON_NULL)
    // Ngày: ghi dạng ISO-8601 string, KHÔNG ghi timestamp số
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
    // snake_case ↔ camelCase
    .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
    .addModule(new JavaTimeModule())            // Java Time support
    .build();

// Reader/Writer là immutable, reusable và có cấu hình riêng theo type/use case
ObjectReader reader = mapper.readerFor(User.class);
ObjectWriter writer = mapper.writerFor(User.class);

// Chỉ nới lỏng ở boundary cần tương thích với response của upstream
ObjectReader tolerantReader = mapper.readerFor(UpstreamUser.class)
    .without(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
```

### Unknown field: strict hay tolerant?

- **Strict** *(nghiêm ngặt)*: giữ `FAIL_ON_UNKNOWN_PROPERTIES` để phát hiện client gõ sai field hoặc contract bị lệch. Thường phù hợp với command/request nội bộ cần kiểm soát chặt.
- **Tolerant reader** *(bộ đọc dung sai)*: bỏ qua field lạ khi đọc response từ dịch vụ bên ngoài có thể bổ sung field theo thời gian. Nên giới hạn ở DTO/boundary cụ thể thay vì tắt toàn cục không suy nghĩ.

> 💡 **Giải thích dễ hiểu — field lạ:**
> Chế độ strict giống **nhân viên nhập kho đối chiếu đủ từng dòng trên hóa đơn**: thấy món không có trong hợp đồng thì dừng lại. Chế độ tolerant giống kho nhận hàng từ đối tác lâu dài: món mới chưa dùng thì tạm bỏ qua để chuyến hàng cũ vẫn chạy. Một chính sách áp cho mọi cửa kho sẽ hoặc quá cứng, hoặc che mất lỗi chính tả nguy hiểm.

---

## How – Các annotation cốt lõi

```java
public class User {
    @JsonProperty("user_name")            // đổi tên field trong JSON
    private String name;

    @JsonIgnore                            // không serialize/deserialize field này
    private String password;

    @JsonFormat(pattern = "yyyy-MM-dd")    // định dạng ngày
    private LocalDate birthday;

    @JsonInclude(JsonInclude.Include.NON_EMPTY)  // bỏ nếu rỗng
    private List<String> roles;

    @JsonAlias({"email", "e_mail"})        // chấp nhận nhiều tên khi đọc
    private String emailAddress;

    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) // nhận khi đọc, không ghi ra JSON
    private String secret;
}

@JsonIgnoreProperties(ignoreUnknown = true)   // cấp class: bỏ qua field lạ
public class ApiResponse { ... }
```

| Annotation | Mục đích |
|-----------|---------|
| `@JsonProperty` | Đổi tên / quyền truy cập (READ_ONLY/WRITE_ONLY) |
| `@JsonIgnore` / `@JsonIgnoreProperties` | Loại field |
| `@JsonInclude` | Điều kiện include (NON_NULL/NON_EMPTY/NON_DEFAULT) |
| `@JsonCreator` + `@JsonProperty` | Chỉ rõ constructor/factory và tên tham số cho object bất biến thông thường |
| `@JsonValue` | Serialize cả object bằng 1 method (vd enum) |
| `@JsonFormat` | Định dạng ngày/số/enum |
| `@JsonNaming` | Naming strategy cấp class |
| `@JsonManagedReference`/`@JsonBackReference` | Biểu diễn quan hệ cha–con hai chiều và không serialize chiều back-reference |

### Object bất biến / Record
```java
public record CreateUserRequest(
    @JsonProperty("user_name") String userName,
    String email
) {}  // Jackson 2.12+ có hỗ trợ trực tiếp canonical constructor của record
```

Jackson 2.12+ có hỗ trợ record trực tiếp và dùng **canonical constructor** *(constructor nhận đủ record component theo đúng thứ tự)*; record đơn giản không cần `ParameterNamesModule` chỉ để nhận ra tên component. `@JsonProperty` vẫn hữu ích khi tên JSON khác tên component. Với class bất biến không phải record, `@JsonCreator` và `@JsonProperty` hoặc module/metadata tên tham số có thể vẫn cần tùy thiết kế và version.

`@JsonManagedReference`/`@JsonBackReference` phù hợp một số quan hệ cha–con, nhưng không phải giải pháp tổng quát cho mọi object graph. Với API, DTO phẳng thường rõ contract hơn; nếu cần giữ identity trong graph, cân nhắc `@JsonIdentityInfo` sau khi đánh giá định dạng JSON tạo ra.

> 💡 **Giải thích dễ hiểu — record và vòng tham chiếu:**
> Record giống **mẫu đơn có sẵn danh sách ô bắt buộc**, nên Jackson biết phải đưa từng giá trị vào canonical constructor nào. Quan hệ hai chiều lại giống hai tấm danh thiếp cùng chỉ vào nhau: nếu cứ chụp tiếp danh thiếp được trỏ tới, việc serialize không bao giờ dừng. Back-reference bảo Jackson “chiều quay về này chỉ là liên kết, đừng chụp lại”.

---

## How – Custom Serializer / Deserializer

Khi cần kiểm soát hoàn toàn cách map một type:
```java
public class MoneySerializer extends StdSerializer<Money> {
    public MoneySerializer() { super(Money.class); }
    @Override public void serialize(Money m, JsonGenerator gen, SerializerProvider sp) throws IOException {
        gen.writeString(m.amount() + " " + m.currency());   // "100 USD"
    }
}
public class MoneyDeserializer extends StdDeserializer<Money> {
    public MoneyDeserializer() { super(Money.class); }
    @Override public Money deserialize(JsonParser p, DeserializationContext ctx) throws IOException {
        if (!p.hasToken(JsonToken.VALUE_STRING)) {
            throw JsonMappingException.from(p, "Money phải là chuỗi '<amount> <currency>'");
        }

        String raw = p.getText().trim();
        String[] parts = raw.split("\\s+", 2);
        if (parts.length != 2 || !parts[1].matches("[A-Z]{3}")) {
            throw JsonMappingException.from(p, "Money không đúng định dạng '<amount> <ISO currency>'");
        }

        try {
            return new Money(Long.parseLong(parts[0]), parts[1]);
        } catch (NumberFormatException ex) {
            throw JsonMappingException.from(p, "Money amount không phải số nguyên hợp lệ", ex);
        }
    }
}
// Đăng ký module trước khi mapper được dùng
SimpleModule m = new SimpleModule();
m.addSerializer(Money.class, new MoneySerializer());
m.addDeserializer(Money.class, new MoneyDeserializer());
ObjectMapper moneyMapper = JsonMapper.builder().addModule(m).build();
```

Ví dụ trên giả định `amount` là số nguyên theo domain (chẳng hạn minor unit); hệ thống dùng số thập phân phải chọn `BigDecimal`, scale và rounding rule rõ ràng. Deserializer cần kiểm tra token, shape, độ dài, miền giá trị và currency hợp lệ; parse được cú pháp chưa có nghĩa dữ liệu hợp lệ về nghiệp vụ.

> 💡 **Giải thích dễ hiểu — custom deserializer:**
> Custom deserializer giống **nhân viên hải quan tự viết quy trình nhập một loại hàng đặc biệt**. Nếu chỉ tách chuỗi rồi tin ngay, kiện hàng sai nhãn hoặc quá khổ sẽ lọt vào kho. Cần kiểm tra cả hình thức (`"100 USD"`) lẫn quy tắc nghiệp vụ (currency được hỗ trợ, amount trong giới hạn).

---

## How – Polymorphic Typing (và rủi ro bảo mật)

Khi thuộc tính khai báo bằng interface/abstract class nhưng JSON phải tạo đúng subtype, Jackson cần **type metadata** *(thông tin nhận diện kiểu cụ thể)*:
```java
@JsonTypeInfo(
    use = JsonTypeInfo.Id.NAME,
    include = JsonTypeInfo.As.PROPERTY,
    property = "type"
)
@JsonSubTypes({
    @JsonSubTypes.Type(value = Dog.class, name = "dog"),
    @JsonSubTypes.Type(value = Cat.class, name = "cat")
})
public sealed interface Animal permits Dog, Cat {}
// JSON: {"type":"dog","name":"Rex"}
```
`Id.NAME` dùng logical name như `dog`, không nhận trực tiếp tên class Java từ payload. `@JsonSubTypes` tạo **allowlist** *(danh sách subtype được phép)* tường minh; sealed hierarchy giúp compiler giới hạn subtype trong code nhưng không tự thay thế cấu hình type id của Jackson ở mọi version.

Cách này giảm mạnh rủi ro class injection so với `Id.CLASS`/default typing, nhưng không tạo bảo đảm an toàn tuyệt đối. Vẫn phải validate field của subtype, giữ subtype không có side effect nguy hiểm khi khởi tạo và giới hạn tài nguyên parser.

> 💡 **Giải thích dễ hiểu — type id:**
> Interface `Animal` giống nhãn chung **“động vật” trên thùng vận chuyển**; chỉ nhãn đó chưa cho kho biết phải chuẩn bị chuồng chó hay mèo. Field `type: "dog"` là mã hàng ngắn, còn allowlist là bảng tra chỉ chấp nhận các mã kho đã đăng ký. Cho người gửi ghi thẳng tên class giống cho họ tự điền địa chỉ bất kỳ trong toàn bộ nhà kho.

### ⚠️ Default Typing – lỗ hổng RCE
```java
// ❌ Jackson 2.x: validator này cho phép quá rộng; không dùng với dữ liệu không tin cậy
mapper.activateDefaultTyping(
    LaissezFaireSubTypeValidator.instance,
    ObjectMapper.DefaultTyping.NON_FINAL
);
```

Rủi ro **RCE (Remote Code Execution)** *(thực thi mã từ xa)* không xuất hiện chỉ vì gọi `readValue()`. Kịch bản nguy hiểm thường cần đồng thời: dữ liệu do attacker kiểm soát, type id dựa trên tên class, validator/cấu hình cho phép quá rộng, và một **gadget class** *(class có chuỗi hành vi bị lợi dụng khi khởi tạo/gán thuộc tính)* phù hợp trên classpath. API `enableDefaultTyping()` cũ đã bị deprecate trong Jackson 2.x và không nên dùng làm mẫu mới.

Phòng thủ theo nhiều lớp:

- Không bật default typing cho payload không tin cậy; tránh `Id.CLASS`/`Id.MINIMAL_CLASS` ở public API.
- Ưu tiên `Id.NAME` với tập subtype nhỏ, base type cụ thể và type id ổn định theo contract.
- Nếu use case nội bộ thực sự cần default typing, dùng `PolymorphicTypeValidator` chỉ cho phép type/package tối thiểu cần thiết; không dùng validator laissez-faire.
- Cập nhật đồng bộ các Jackson component, validate dữ liệu sau binding và giới hạn kích thước/độ sâu đầu vào. Liên hệ [serialization.md](serialization.md).

> 💡 **Giải thích dễ hiểu — default typing:**
> Default typing rộng giống trao cho người gửi **chìa khóa chọn bất kỳ phòng nào theo tên đầy đủ**. Chỉ khi kho có một căn phòng nguy hiểm và hệ thống thực sự mở theo nhãn giả thì sự cố mới xảy ra, nhưng hậu quả có thể rất lớn. Allowlist hẹp giống quầy lễ tân chỉ phát vé cho vài phòng đã duyệt.

## How – Giới hạn tài nguyên khi đọc JSON không tin cậy

Với Jackson 2.15+ trong dòng 2.x, `StreamReadConstraints` cho phép đặt giới hạn phù hợp với contract thay vì dựa hoàn toàn vào default thay đổi theo version:

```java
StreamReadConstraints limits = StreamReadConstraints.builder()
    .maxNestingDepth(100)
    .maxStringLength(1_000_000)
    .maxNumberLength(1_000)
    .build();

JsonFactory factory = JsonFactory.builder()
    .streamReadConstraints(limits)
    .build();

ObjectMapper boundedMapper = JsonMapper.builder(factory)
    .addModule(new JavaTimeModule())
    .build();
```

Các con số trên chỉ minh họa; phải chọn từ kích thước payload hợp lệ của hệ thống. Parser limits cần đi cùng giới hạn HTTP/message size, timeout, authentication/authorization và validation nghiệp vụ. Chúng giúp giảm **DoS (Denial of Service)** *(từ chối dịch vụ do làm cạn CPU/bộ nhớ)* từ chuỗi cực dài, số khổng lồ hoặc JSON lồng quá sâu, nhưng không thay thế các lớp bảo vệ khác.

---

## How – Java Time & Optional (bẫy thường gặp)

```java
// Jackson 2.x: đăng ký module trước khi build/use mapper
ObjectMapper javaTypesMapper = JsonMapper.builder()
    .addModule(new JavaTimeModule()) // Instant, LocalDate, OffsetDateTime...
    .addModule(new Jdk8Module())     // Optional và các JDK 8 types liên quan
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
    .build();
```

Trong Jackson 2.x, thiếu module tương ứng có thể khiến Java Time/`Optional` bị từ chối hoặc biểu diễn ngoài mong đợi. Jackson 3 tích hợp một số hỗ trợ JDK trước đây nằm ở module riêng, nên hãy theo migration guide của major version đang dùng.

Spring Boot thường auto-configure các Jackson module được hỗ trợ khi chúng có trên classpath. Nên tùy chỉnh mapper do framework quản lý qua `spring.jackson.*` hoặc cơ chế customizer phù hợp với phiên bản, thay vì tạo mapper thứ hai làm REST API dùng cấu hình khác. `Optional` thích hợp cho return type nhưng trong DTO field có thể làm mờ khác biệt giữa field bị thiếu và field có giá trị `null`; hãy định nghĩa contract rõ ràng. Liên hệ [datetime.md](datetime.md), [spring_boot.md](../spring/spring_boot.md).

---

## Compare – Jackson vs các thư viện khác

| | Jackson | Gson | JSON-B (Yasson) | org.json |
|--|---------|------|------------------|----------|
| Nhà phát triển | FasterXML | Google | Jakarta EE chuẩn | – |
| Hiệu năng | Có data binding/tree/streaming; cần benchmark theo workload | Có object mapping và `JsonReader`/`JsonWriter` streaming | Phụ thuộc implementation/provider | Chủ yếu tree API; giữ cấu trúc trong bộ nhớ |
| Tính năng | Rất phong phú | Vừa đủ, đơn giản | Chuẩn hóa | Cơ bản |
| Tích hợp Spring | Thường được auto-configure khi có trên classpath | Cần chọn converter/cấu hình | Cần chọn provider/converter | Không phải lựa chọn tích hợp chính |
| Streaming API | `JsonParser`/`JsonGenerator` | `JsonReader`/`JsonWriter` | JSON-B tập trung binding; dùng JSON-P cho streaming | Không có streaming API tương đương |
| Hệ sinh thái module | Lớn (XML/YAML/CSV/...) | Nhỏ | Nhỏ | – |

> Không có thư viện “nhanh nhất” cho mọi payload. Kết quả phụ thuộc kích thước dữ liệu, allocation, adapter/module, chế độ streaming/data binding và JVM; hãy benchmark với dữ liệu thật. Trong Spring, ưu tiên converter mà framework đang quản lý nếu không có yêu cầu khác. Với Jakarta, JSON-B cung cấp API chuẩn nhưng hành vi/hiệu năng còn phụ thuộc provider.

---

## When – Chọn cách xử lý nào?

| Tình huống | Cách dùng |
|-----------|----------|
| REST API thông thường (POJO/DTO) | Data binding + annotation |
| Cấu trúc JSON động, không có schema | Tree model `JsonNode` |
| File JSON GB-scale, ETL | Streaming `JsonParser` |
| Object bất biến/record | Record support; class thường dùng `@JsonCreator`/`@JsonProperty` khi cần |
| Type đặc biệt (Money, custom) | Custom (de)serializer + module |
| Đa hình | `@JsonTypeInfo(Id.NAME)` + allowlist |

---

## Trade-offs

- (+) Nhiều mô hình xử lý, hệ annotation/module phong phú, tích hợp tốt với nhiều framework và không buộc payload mang object graph Java như native serialization.
- (−) Nhiều tùy chọn làm contract khó đoán nếu mỗi service cấu hình khác nhau; polymorphic typing rộng là bề mặt tấn công đáng chú ý.
- (−) Data binding thường dùng introspection/reflection và cache metadata; nên tái sử dụng mapper. Với GraalVM Native, framework hoặc ứng dụng có thể cần reflection metadata/hints phù hợp (xem [graalvm_native.md](../modern/graalvm_native.md)).
- (−) Đa hình + generic + lazy (Hibernate proxy) dễ phát sinh lỗi serialize (LazyInitializationException, vòng lặp) → dùng DTO thay vì serialize Entity trực tiếp.

---

## Real-world Usage

```java
// Spring: dùng bean ObjectMapper có sẵn, KHÔNG tự new
@Service
class UserService {
    private final ObjectMapper mapper;          // inject bean cấu hình sẵn
    UserService(ObjectMapper mapper) { this.mapper = mapper; }
}

// Request DTO: giữ unknown-field policy nghiêm ngặt, không serialize password
public record CreateUserRequest(
    @JsonProperty("user_name") String userName,
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String password
) {}

// DTO đọc response của đối tác: chủ động dung sai khi đối tác thêm field
@JsonIgnoreProperties(ignoreUnknown = true)
public record PartnerUserResponse(String id, String displayName) {}
```
- Anti-pattern: serialize trực tiếp JPA Entity ra API → lộ field, lazy-loading lỗi, vòng lặp quan hệ. **Best practice:** map sang DTO. Liên hệ [jpa_hibernate.md](../data/jpa_hibernate.md), [antipatterns.md](../patterns/antipatterns.md).
- `WRITE_ONLY` chỉ ngăn Jackson ghi property đó ra JSON; nó không che dữ liệu khỏi `toString()`, debugger, log, metrics hoặc exception message. Không log toàn bộ request chứa credential và không tái sử dụng request DTO làm response DTO.
- Kafka/messaging dùng Jackson serializer cho JSON payload. Liên hệ [messaging.md](messaging.md).

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [serialization.md](serialization.md) (so sánh JSON với Java native serialization; rủi ro type metadata), [records.md](../modern/records.md) (record + Jackson), [sealed_classes.md](../modern/sealed_classes.md) (polymorphic typing), [spring_boot.md](../spring/spring_boot.md) (auto-config Jackson), [datetime.md](datetime.md) (JavaTimeModule), [graalvm_native.md](../modern/graalvm_native.md) (reflection hints).
>
> Keyword cho topic kế: **Bean Validation** – `@Valid`/`@Validated`, `@NotNull`/`@Size`, custom `ConstraintValidator`, validation groups.

### Tài liệu chính thức để kiểm tra theo major/minor version

- [FasterXML Jackson Databind](https://github.com/FasterXML/jackson-databind)
- [Jackson 3 migration guide](https://github.com/FasterXML/jackson/blob/main/jackson3/MIGRATING_TO_JACKSON_3.md)
- [Jackson polymorphic type handling](https://github.com/FasterXML/jackson-docs/wiki/JacksonPolymorphicDeserialization)
- [Jackson polymorphic deserialization CVE criteria](https://github.com/FasterXML/jackson/wiki/Jackson-Polymorphic-Deserialization-CVE-Criteria)
- [Jackson 2.15 processing limits](https://github.com/FasterXML/jackson/wiki/Jackson-Release-2.15)

*Cập nhật lần cuối: 2026-07-22*
