# JSON Processing với Jackson (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Jackson là gì?

**Jackson** là thư viện xử lý JSON **de facto** của hệ sinh thái Java (mặc định trong Spring Boot/Spring MVC). Nó chuyển đổi hai chiều giữa **Java object ↔ JSON** (data binding), và là giải pháp **an toàn** thay thế Java native serialization (xem [[core/serialization.md]]).

---

## Components – 3 module lõi

| Module | Vai trò |
|--------|---------|
| `jackson-core` | Streaming API: `JsonParser` (đọc), `JsonGenerator` (ghi) – tầng thấp nhất |
| `jackson-databind` | `ObjectMapper` – data binding POJO ↔ JSON, tree model `JsonNode` |
| `jackson-annotations` | Các annotation `@JsonProperty`, `@JsonIgnore`... |

Module mở rộng phổ biến: `jackson-datatype-jsr310` (Java Time), `jackson-module-parameter-names`, `jackson-datatype-jdk8` (Optional), `jackson-dataformat-xml`/`yaml`/`csv`.

---

## How – 3 cách xử lý JSON

### 1. Data Binding (phổ biến nhất) – POJO ↔ JSON
```java
ObjectMapper mapper = new ObjectMapper();

// Serialize (Java → JSON)
String json = mapper.writeValueAsString(user);          // {"name":"An","age":30}

// Deserialize (JSON → Java)
User u = mapper.readValue(json, User.class);

// Generic type (List, Map) → dùng TypeReference (giữ generic, tránh type erasure)
List<User> users = mapper.readValue(json, new TypeReference<List<User>>() {});
```

### 2. Tree Model – `JsonNode` (khi cấu trúc động/không biết trước)
```java
JsonNode root = mapper.readTree(json);
String name = root.path("user").path("name").asText();   // path() an toàn null
int age = root.get("age").asInt();
((ObjectNode) root).put("active", true);                  // chỉnh sửa cây
```

### 3. Streaming API – tốc độ & bộ nhớ tối đa (file JSON khổng lồ)
```java
try (JsonParser p = mapper.getFactory().createParser(file)) {
    while (p.nextToken() != null) {
        if ("email".equals(p.currentName())) { p.nextToken(); process(p.getText()); }
    }
}
```

> So sánh nhanh: Data binding (tiện) → Tree (linh hoạt) → Streaming (nhanh/ít RAM nhất, code nhiều).

---

## How – ObjectMapper: cấu hình & thread-safety

> ⚠️ **ObjectMapper là thread-safe SAU khi cấu hình xong** và **tốn chi phí khởi tạo**. → Tạo **một lần**, dùng lại (singleton/bean). KHÔNG `new ObjectMapper()` trong mỗi request (anti-pattern phổ biến gây chậm). Trong Spring, dùng bean `ObjectMapper` có sẵn.

```java
ObjectMapper mapper = JsonMapper.builder()
    // Deserialize: bỏ qua field JSON không có trong POJO (rất quan trọng cho API versioning)
    .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
    // Serialize: bỏ field null
    .serializationInclusion(JsonInclude.Include.NON_NULL)
    // Ngày: ghi dạng ISO-8601 string, KHÔNG ghi timestamp số
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
    // snake_case ↔ camelCase
    .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
    .addModule(new JavaTimeModule())            // Java Time support
    .build();

// Cho hot path: ObjectReader/ObjectWriter (đã bind sẵn type, immutable, thread-safe, nhanh hơn)
ObjectReader reader = mapper.readerFor(User.class);
ObjectWriter writer = mapper.writerFor(User.class);
```

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

    @JsonProperty(access = Access.WRITE_ONLY)  // chỉ nhận khi deserialize, không lộ khi serialize
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
| `@JsonCreator` + `@JsonProperty` | Constructor cho object **bất biến** (final field, record) |
| `@JsonValue` | Serialize cả object bằng 1 method (vd enum) |
| `@JsonFormat` | Định dạng ngày/số/enum |
| `@JsonNaming` | Naming strategy cấp class |
| `@JsonManagedReference`/`@JsonBackReference` | Phá vòng lặp tham chiếu 2 chiều |

### Object bất biến / Record
```java
public record CreateUserRequest(
    @JsonProperty("user_name") String userName,
    String email
) {}  // Jackson 2.12+ tự dùng canonical constructor của record (kèm parameter-names module)
```

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
        String[] parts = p.getText().split(" ");
        return new Money(Long.parseLong(parts[0]), parts[1]);
    }
}
// Đăng ký qua module hoặc annotation @JsonSerialize(using = MoneySerializer.class)
SimpleModule m = new SimpleModule();
m.addSerializer(Money.class, new MoneySerializer());
m.addDeserializer(Money.class, new MoneyDeserializer());
mapper.registerModule(m);
```

---

## How – Polymorphic Typing (và rủi ro bảo mật)

Khi cần serialize/deserialize **cây kế thừa** (interface/abstract → impl), Jackson cần biết "type thật":
```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")  // ghi field "type" vào JSON
@JsonSubTypes({
    @JsonSubTypes.Type(value = Dog.class, name = "dog"),
    @JsonSubTypes.Type(value = Cat.class, name = "cat")
})
public sealed interface Animal permits Dog, Cat {}
// JSON: {"type":"dog","name":"Rex"}
```
> Dùng `Id.NAME` + `@JsonSubTypes` (allowlist tường minh) — **an toàn**. Liên hệ sealed class: [[modern/sealed_classes.md]].

### ⚠️ Default Typing – lỗ hổng RCE
```java
// ❌ TUYỆT ĐỐI KHÔNG bật với dữ liệu không tin cậy
mapper.activateDefaultTyping(LaissezFaireSubTypeValidator.instance, ...);
mapper.enableDefaultTyping(); // (deprecated, càng nguy hiểm)
```
- Default typing ghi **tên class đầy đủ** vào JSON (`@class`) và cho phép Jackson **khởi tạo class tùy ý** khi đọc → tương tự gadget chain của Java serialization → **RCE** (nhiều CVE "Jackson deserialization", "polymorphic typing").
- **Phòng thủ:** không bật default typing; nếu buộc phải polymorphic → dùng `@JsonTypeInfo(use = Id.NAME)` với `@JsonSubTypes` allowlist, hoặc `PolymorphicTypeValidator` giới hạn base type. Liên hệ [[core/serialization.md]].

---

## How – Java Time & Optional (bẫy thường gặp)

```java
// Thiếu JavaTimeModule → lỗi "Java 8 date/time type not supported" hoặc ghi ra mảng số xấu xí
mapper.registerModule(new JavaTimeModule());
mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS); // → "2026-06-04T10:00:00Z"
```
> Spring Boot **tự động** đăng ký JavaTimeModule + cấu hình hợp lý qua `Jackson2ObjectMapperBuilder`. Tùy chỉnh qua `application.yml` (`spring.jackson.*`) hoặc bean `Jackson2ObjectMapperBuilderCustomizer`. Liên hệ [[core/datetime.md]], [[spring/spring_boot.md]].

---

## Compare – Jackson vs các thư viện khác

| | Jackson | Gson | JSON-B (Yasson) | org.json |
|--|---------|------|------------------|----------|
| Nhà phát triển | FasterXML | Google | Jakarta EE chuẩn | – |
| Hiệu năng | Cao nhất (streaming) | Trung bình | Trung bình | Thấp |
| Tính năng | Rất phong phú | Vừa đủ, đơn giản | Chuẩn hóa | Cơ bản |
| Tích hợp Spring | **Mặc định** | Cần cấu hình | Cần cấu hình | – |
| Streaming API | Có | Hạn chế | Có | Không |
| Hệ sinh thái module | Lớn (XML/YAML/CSV/...) | Nhỏ | Nhỏ | – |

> Trong Spring → mặc định Jackson. Android nhẹ → Gson. Tuân thủ chuẩn Jakarta → JSON-B.

---

## When – Chọn cách xử lý nào?

| Tình huống | Cách dùng |
|-----------|----------|
| REST API thông thường (POJO/DTO) | Data binding + annotation |
| Cấu trúc JSON động, không có schema | Tree model `JsonNode` |
| File JSON GB-scale, ETL | Streaming `JsonParser` |
| Object bất biến/record | `@JsonCreator` / record + parameter-names |
| Type đặc biệt (Money, custom) | Custom (de)serializer + module |
| Đa hình | `@JsonTypeInfo(Id.NAME)` + allowlist |

---

## Trade-offs

- (+) Nhanh, đầy đủ tính năng, an toàn hơn Java serialization, tích hợp Spring sẵn, schema linh hoạt (bỏ qua field lạ).
- (−) Cấu hình nhiều, học đường cong dốc; **default typing là cạm bẫy RCE**.
- (−) Reflection-based → khởi tạo ObjectMapper tốn kém (phải reuse); với GraalVM Native cần khai báo reflection hints (xem [[modern/graalvm_native.md]]).
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

// DTO chuẩn cho API: bất biến, bỏ field lạ, ẩn field nhạy cảm
@JsonIgnoreProperties(ignoreUnknown = true)
public record UserDto(
    @JsonProperty("user_name") String userName,
    @JsonProperty(access = Access.WRITE_ONLY) String password   // nhận vào, không trả ra
) {}
```
- Anti-pattern: serialize trực tiếp JPA Entity ra API → lộ field, lazy-loading lỗi, vòng lặp quan hệ. **Best practice:** map sang DTO. Liên hệ [[data/jpa_hibernate.md]], [[patterns/antipatterns.md]].
- Kafka/messaging dùng Jackson serializer cho JSON payload. Liên hệ [[core/messaging.md]].

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[core/serialization.md]] (Jackson là thay thế an toàn; default typing RCE), [[modern/records.md]] (record + Jackson), [[modern/sealed_classes.md]] (polymorphic typing), [[spring/spring_boot.md]] (auto-config Jackson), [[core/datetime.md]] (JavaTimeModule), [[modern/graalvm_native.md]] (reflection hints).
>
> Keyword cho topic kế: **Bean Validation** – `@Valid`/`@Validated`, `@NotNull`/`@Size`, custom `ConstraintValidator`, validation groups.

*Cập nhật lần cuối: 2026-06-04*
