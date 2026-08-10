---
title: "Bean Validation / Hibernate Validator (Deep Dive)"
topic: java
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Bean Validation / Hibernate Validator (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Bean Validation là gì?

**Jakarta Bean Validation** (trước là JSR 303/349/380) là **chuẩn** *(specification — bản đặc tả quy chuẩn)* cho phép khai báo ràng buộc dữ liệu bằng **annotation** *(chú thích gắn trên code, dạng `@...`)* ngay trên field/method, thay vì viết `if` kiểm tra thủ công rải rác. **Hibernate Validator** là **implementation tham chiếu** *(reference implementation — bản cài đặt gốc, chuẩn mực để đối chiếu)* (mặc định trong Spring Boot qua `spring-boot-starter-validation`).

> 💡 **Giải thích dễ hiểu:**
> Hãy tưởng tượng bạn là **bảo vệ ở cổng một tòa nhà**. Cách cũ (`if` thủ công) là mỗi lần có khách, bạn tự nhớ trong đầu một loạt quy tắc rồi kiểm tra — mỗi cổng một kiểu, dễ quên, dễ làm khác nhau. Bean Validation giống như **dán sẵn bảng nội quy ngay trên cửa** (annotation trên field): "phải đeo thẻ", "tuổi từ 18". Ai đi qua thì hệ thống tự đối chiếu bảng nội quy đó. Quy tắc đi liền với cửa (dữ liệu), dùng lại được ở mọi cổng.

```java
public class RegisterRequest {
    @NotBlank @Size(min = 3, max = 20)
    private String username;

    @Email @NotNull
    private String email;

    @Min(18) @Max(120)
    private int age;
}
```

> Triết lý: **declarative** (khai báo "cái gì hợp lệ") thay vì **imperative** (viết "kiểm tra như thế nào"). Ràng buộc đi cùng dữ liệu, tái sử dụng ở mọi tầng.

---

## Components – Kiến trúc

| Thành phần | Vai trò |
|-----------|---------|
| `jakarta.validation-api` | API chuẩn: annotation, `Validator`, `ConstraintViolation` |
| **Hibernate Validator** | Implementation (engine thực thi) |
| `Validator` | Đối tượng chạy validation *(quá trình kiểm tra hợp lệ)*: `validate(bean)` |
| `ConstraintValidator<A, T>` | Logic kiểm tra cho mỗi constraint *(ràng buộc — điều kiện dữ liệu phải thỏa)* |
| `ConstraintViolation` | Một lỗi vi phạm *(violation)* (path, message, invalid value) |
| `ValidationMessages.properties` | Thông điệp lỗi (i18n — *đa ngôn ngữ*) |

---

## How – Các constraint built-in

| Annotation | Áp dụng | Ý nghĩa |
|-----------|---------|---------|
| `@NotNull` | mọi type | khác null |
| `@NotEmpty` | String/Collection/Map/Array | khác null **và** size > 0 |
| `@NotBlank` | String | khác null **và** trim ≠ rỗng |
| `@Size(min,max)` | String/Collection... | độ dài/số phần tử trong khoảng |
| `@Min/@Max`, `@Positive/@Negative`, `@PositiveOrZero` | số | giới hạn giá trị |
| `@DecimalMin/@DecimalMax`, `@Digits(integer,fraction)` | số | dùng cho BigDecimal/tiền tệ |
| `@Email` | String | định dạng email |
| `@Pattern(regexp)` | String | khớp regex |
| `@Past/@Future`, `@PastOrPresent` | ngày giờ | mốc thời gian |
| `@AssertTrue/@AssertFalse` | boolean | giá trị boolean |

### ⚠️ Phân biệt `@NotNull` vs `@NotEmpty` vs `@NotBlank` (hay nhầm)
```java
@NotNull  String a;   // ""     hợp lệ, " " hợp lệ, null KHÔNG
@NotEmpty String b;   // ""     KHÔNG, " " hợp lệ, null KHÔNG
@NotBlank String c;   // ""     KHÔNG, " " KHÔNG (trim rỗng), null KHÔNG
```
> Với chuỗi đầu vào người dùng → thường dùng `@NotBlank`. Với collection *(tập hợp phần tử: List, Set...)* → `@NotEmpty`.

> 💡 **Giải thích dễ hiểu — 3 mức "rỗng":**
> Ba annotation này giống 3 mức kiểm tra một **cái hộp**:
> - `@NotNull`: chỉ cần **có cái hộp** (không phải chỗ trống). Hộp rỗng hay trong hộp chỉ có khoảng trắng đều được, miễn là hộp tồn tại.
> - `@NotEmpty`: hộp phải **có ít nhất 1 món** bên trong. Chuỗi `""` là hộp rỗng → trượt; nhưng `" "` (một dấu cách) tính là "có 1 ký tự" → đậu.
> - `@NotBlank`: khó tính nhất, hộp phải có **món thật sự** — sau khi bỏ hết giấy đệm (khoảng trắng) ra vẫn còn nội dung. Nên `" "` bị coi là rỗng → trượt.
> Vì người dùng hay gõ toàn dấu cách cho có, ô nhập chữ nên dùng `@NotBlank` để chặn.

---

## How – Chạy validation thủ công (không cần Spring)

```java
ValidatorFactory factory = Validation.buildDefaultValidatorFactory();
Validator validator = factory.getValidator();

Set<ConstraintViolation<RegisterRequest>> violations = validator.validate(request);
for (ConstraintViolation<?> v : violations) {
    System.out.println(v.getPropertyPath() + ": " + v.getMessage());
    // vd: "username: size must be between 3 and 20"
}
if (!violations.isEmpty()) throw new ConstraintViolationException(violations);
```
> `Validator` thread-safe, tốn chi phí tạo → reuse (Spring quản lý sẵn bean này).

---

## How – `@Valid` (cascade) vs `@Validated` (Spring + groups)

> 💡 **Giải thích dễ hiểu — "cascade" là gì?**
> **cascade** *(đổ dây chuyền — kiểm tra lan sâu vào object con)* giống việc **kiểm tra hành lý ở sân bay**. Bạn có một vali lớn (`Order`), bên trong có túi nhỏ (`Customer`), trong túi lại có ví (`OrderLine`). Nếu chỉ soi lớp ngoài, bạn bỏ sót đồ cấm nằm trong túi con. Đánh dấu `@Valid` lên field con nghĩa là "mở túi này ra soi tiếp" — máy soi đi xuyên qua từng lớp. Thiếu `@Valid` thì máy chỉ soi vali ngoài, mọi ràng buộc bên trong `Customer` bị bỏ qua.

| | `@Valid` (Jakarta chuẩn) | `@Validated` (Spring) |
|--|--------------------------|------------------------|
| Nguồn | `jakarta.validation` | `org.springframework` |
| Cascade vào object con | **Có** (đệ quy) | Không trực tiếp |
| Validation groups | Không | **Có** |
| Method-level validation | Không | **Có** (đặt trên class) |

### Cascade với `@Valid`
```java
public class Order {
    @NotNull private String id;
    @Valid                              // BẮT BUỘC để validate sâu vào customer
    private Customer customer;           // nếu thiếu @Valid → ràng buộc trong Customer bị bỏ qua
    @Valid
    private List<@Valid OrderLine> lines;
}
```

### Validation Groups – ràng buộc khác nhau theo ngữ cảnh

> 💡 **Giải thích dễ hiểu — "validation groups":**
> **Validation groups** *(nhóm ràng buộc theo tình huống)* giải quyết chuyện "cùng một tờ khai nhưng quy tắc khác nhau tùy lúc". Ví von như **mẫu đơn ở bệnh viện**: khi *đăng ký khám lần đầu* (OnCreate) thì ô "mã bệnh nhân" phải để trống (chưa có); khi *tái khám* (OnUpdate) thì ô đó bắt buộc điền. Vẫn là một tờ đơn `UserDto`, nhưng bạn bảo hệ thống "lần này áp bộ quy tắc nào" bằng cách chọn group.
```java
public interface OnCreate {}
public interface OnUpdate {}

public class UserDto {
    @Null(groups = OnCreate.class)        // tạo mới: id phải null
    @NotNull(groups = OnUpdate.class)     // cập nhật: id bắt buộc
    private Long id;

    @NotBlank(groups = {OnCreate.class, OnUpdate.class})
    private String name;
}

// Controller chọn group
@PostMapping void create(@Validated(OnCreate.class) @RequestBody UserDto dto) {}
@PutMapping  void update(@Validated(OnUpdate.class) @RequestBody UserDto dto) {}
```

---

## How – Custom Constraint

Khi constraint built-in không đủ (vd: số điện thoại VN, mã hợp lệ):
```java
// 1. Định nghĩa annotation
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = PhoneVnValidator.class)
public @interface PhoneVn {
    String message() default "{validation.phone.invalid}"; // key i18n
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

// 2. Viết validator
public class PhoneVnValidator implements ConstraintValidator<PhoneVn, String> {
    private static final Pattern P = Pattern.compile("^(0|\\+84)(3|5|7|8|9)\\d{8}$");
    @Override public boolean isValid(String value, ConstraintValidatorContext ctx) {
        if (value == null) return true;   // để @NotNull lo phần null (tách trách nhiệm)
        return P.matcher(value).matches();
    }
}

// 3. Dùng
public class Contact { @PhoneVn @NotBlank String phone; }
```

### Cross-field validation (ràng buộc cấp class)

> 💡 **Giải thích dễ hiểu — "cross-field validation":**
> Constraint thường chỉ soi **một field** (email đúng định dạng chưa?). Nhưng có luật cần nhìn **nhiều field cùng lúc** — gọi là **cross-field validation** *(ràng buộc liên trường)*. Ví dụ "mật khẩu và xác nhận mật khẩu phải giống nhau" — không field nào tự đúng/sai một mình được, phải so đôi. Vì thế ta đặt ràng buộc ở **cấp class** (`@Target(ElementType.TYPE)`) — như một giám khảo đứng lùi ra nhìn toàn bộ tờ khai thay vì soi từng ô.
```java
@Target(ElementType.TYPE)               // áp dụng cho cả class
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = PasswordMatchValidator.class)
public @interface PasswordMatch { String message() default "Passwords don't match"; ... }

public class PasswordMatchValidator implements ConstraintValidator<PasswordMatch, SignupForm> {
    @Override public boolean isValid(SignupForm f, ConstraintValidatorContext ctx) {
        boolean ok = Objects.equals(f.getPassword(), f.getConfirmPassword());
        if (!ok) {
            ctx.disableDefaultConstraintViolation();
            ctx.buildConstraintViolationWithTemplate("Passwords don't match")
               .addPropertyNode("confirmPassword").addConstraintViolation(); // gắn lỗi vào field cụ thể
        }
        return ok;
    }
}
```

---

## How – Method Validation (validate tham số/return)

Đặt `@Validated` trên class Spring bean để validate trực tiếp tham số method (không cần là controller):
```java
@Service
@Validated
public class OrderService {
    public Order find(@NotNull @Positive Long id) { ... }       // ném ConstraintViolationException

    @NotNull                                                     // validate return value
    public Order create(@Valid OrderRequest req) { ... }
}
```

---

## How – Container element & cascading (Bean Validation 2.0+)

```java
private List<@NotBlank String> tags;          // validate từng phần tử
private Map<@Email String, @Valid Address> map;
private Optional<@Past LocalDate> date;        // validate giá trị trong Optional
```

---

## How – Tích hợp Spring & xử lý lỗi

```java
@RestController
@RequiredArgsConstructor
public class UserController {
    @PostMapping("/users")
    public User create(@Valid @RequestBody RegisterRequest req) { ... }
    // Lỗi @RequestBody → MethodArgumentNotValidException
    // Lỗi @RequestParam/@PathVariable (cần @Validated trên class) → ConstraintViolationException
}

@RestControllerAdvice
public class ValidationExceptionHandler {
    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public Map<String, String> handle(MethodArgumentNotValidException ex) {
        Map<String, String> errors = new HashMap<>();
        ex.getBindingResult().getFieldErrors()
          .forEach(e -> errors.put(e.getField(), e.getDefaultMessage()));
        return errors;   // {"username":"size must be between 3 and 20"}
    }
}
```
> Liên hệ [[spring/spring_mvc_transaction.md]] (`@ControllerAdvice`, request binding).

---

## How – i18n message & interpolation

```properties
# ValidationMessages.properties (và ValidationMessages_vi.properties)
validation.phone.invalid=Số điện thoại không hợp lệ
```
```java
@Size(min = 3, max = 20, message = "Tên dài {min}-{max} ký tự, đang là ${validatedValue.length()}")
// {min}/{max}: tham số constraint;  ${...}: biểu thức EL
```
> Spring Boot mặc định resolve message qua `MessageSource` → hỗ trợ đa ngôn ngữ. Liên hệ i18n.

---

## When – Validation đặt ở tầng nào?

| Tầng | Validation |
|------|-----------|
| Controller/API (DTO) | Bean Validation (`@Valid`) – chặn input bẩn sớm |
| Service | Method validation cho invariant nghiệp vụ + logic phức tạp (gọi DB) thì viết tay |
| Domain/Entity | Constraint cơ bản; **không thay thế** ràng buộc DB |
| DB | Constraint cuối cùng (NOT NULL, UNIQUE, CHECK) – nguồn chân lý |

> Bean Validation hợp cho ràng buộc **cú pháp/định dạng**. Ràng buộc **nghiệp vụ phức tạp** (vd "email chưa tồn tại") cần truy vấn → viết trong service, không nhét vào ConstraintValidator (trừ khi inject được, và cẩn thận hiệu năng).

---

## Compare – Declarative (Bean Validation) vs Imperative (if thủ công)

| | Bean Validation | If thủ công |
|--|-----------------|-------------|
| Vị trí | Cùng chỗ với dữ liệu (annotation) | Rải rác trong code |
| Tái sử dụng | Cao (1 DTO dùng nhiều nơi) | Thấp |
| Gộp lỗi | Trả về **tất cả** vi phạm 1 lần | Phải tự gom |
| i18n | Built-in | Tự làm |
| Logic động/phụ thuộc DB | Hạn chế | Linh hoạt |

---

## Trade-offs

- (+) Khai báo gọn, tập trung, trả nhiều lỗi cùng lúc, i18n sẵn, chuẩn hóa, tích hợp Spring/JPA.
- (−) Khó với ràng buộc phụ thuộc trạng thái runtime/DB; ConstraintValidator inject bean được nhưng dễ tạo side-effect.
- (−) Lạm dụng group/custom → khó đọc; validation logic nghiệp vụ phức tạp không nên ép vào annotation.
- (−) Hibernate Validator dùng reflection/EL → cần cấu hình hint cho GraalVM Native (xem [[modern/graalvm_native.md]]).

---

## Real-world Usage

```java
// DTO API chuẩn: gộp Bean Validation + Jackson + Record
public record CreateProductRequest(
    @NotBlank @Size(max = 100) String name,
    @NotNull @DecimalMin("0.0") @Digits(integer = 10, fraction = 2) BigDecimal price,
    @NotEmpty List<@NotBlank String> categories
) {}
```
- JPA Hibernate tự chạy Bean Validation trước khi `INSERT/UPDATE` (pre-persist/pre-update) → ràng buộc thực thi cả khi không qua controller. Liên hệ [[data/jpa_hibernate.md]].
- Kết hợp với Jackson: deserialize JSON → DTO, rồi `@Valid` kiểm tra. Liên hệ [[core/json_jackson.md]].

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[core/json_jackson.md]] (DTO + deserialize), [[spring/spring_mvc_transaction.md]] (`@Valid` controller, `@ControllerAdvice`), [[data/jpa_hibernate.md]] (validation pre-persist), [[modern/records.md]] (record DTO), [[modern/graalvm_native.md]] (reflection hints).
>
> Keyword cho topic kế: **Networking & HTTP Client** – Socket, `java.net.http.HttpClient` (HTTP/2, async, WebSocket), so sánh RestTemplate/WebClient/Feign.

*Cập nhật lần cuối: 2026-06-04*
