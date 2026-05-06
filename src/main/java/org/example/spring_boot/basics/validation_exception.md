# Validation & Exception Handling – Xử lý lỗi chuyên nghiệp

## What – Tại sao cần Validation & Exception Handling?

- **Validation**: đảm bảo dữ liệu đầu vào hợp lệ trước khi xử lý business logic
- **Exception Handling**: trả về error response nhất quán, thân thiện với client, không lộ internal details

---

## Bean Validation (Jakarta Validation)

### Dependency

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
```

### Các annotation validation phổ biến

```java
public record CreateUserRequest(

    @NotBlank(message = "Name is required")
    @Size(min = 2, max = 100, message = "Name must be 2-100 characters")
    String name,

    @NotBlank
    @Email(message = "Must be a valid email")
    String email,

    @NotNull
    @Size(min = 8, max = 100)
    @Pattern(regexp = "^(?=.*[A-Z])(?=.*[0-9]).+$",
             message = "Password must contain at least 1 uppercase letter and 1 digit")
    String password,

    @Min(value = 0, message = "Age must be non-negative")
    @Max(value = 150)
    Integer age,

    @NotNull
    @Past(message = "Birth date must be in the past")
    LocalDate birthDate,

    @NotEmpty(message = "At least one role required")
    List<@NotBlank String> roles,

    // Nested object validation
    @NotNull
    @Valid
    AddressRequest address
) {}

public record AddressRequest(
    @NotBlank String street,
    @NotBlank String city,
    @Pattern(regexp = "\\d{5}", message = "ZIP must be 5 digits") String zip
) {}
```

### Kích hoạt Validation tại Controller

```java
@RestController
@RequestMapping("/api/users")
@Validated  // cần cho @RequestParam, @PathVariable validation
public class UserController {

    @PostMapping
    public ResponseEntity<UserResponse> create(
        @Valid @RequestBody CreateUserRequest req) {  // @Valid triggers validation
        return ResponseEntity.status(201).body(userService.create(req));
    }

    @GetMapping
    public Page<UserResponse> list(
        @RequestParam @Min(0) int page,
        @RequestParam @Min(1) @Max(100) int size,
        @RequestParam @NotBlank String tenantId) {
        return userService.list(page, size, tenantId);
    }
}
```

---

## Custom Validators

```java
// 1. Define annotation
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = UniqueEmailValidator.class)
public @interface UniqueEmail {
    String message() default "Email already exists";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

// 2. Implement ConstraintValidator
@Component  // cần để inject Spring beans
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    @Autowired
    private UserRepository userRepo;

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (!StringUtils.hasText(email)) return true; // @NotBlank sẽ handle null/empty
        return !userRepo.existsByEmail(email);
    }
}

// 3. Cross-field validation (class-level)
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Constraint(validatedBy = PasswordMatchValidator.class)
public @interface PasswordMatch {
    String message() default "Passwords do not match";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

@Component
public class PasswordMatchValidator implements ConstraintValidator<PasswordMatch, Object> {
    @Override
    public boolean isValid(Object obj, ConstraintValidatorContext ctx) {
        if (obj instanceof ChangePasswordRequest req) {
            return req.newPassword().equals(req.confirmPassword());
        }
        return true;
    }
}

@PasswordMatch
public record ChangePasswordRequest(
    @NotBlank String currentPassword,
    @NotBlank @Size(min = 8) String newPassword,
    @NotBlank String confirmPassword
) {}
```

---

## Validation Groups – Khác nhau theo use case

```java
// Định nghĩa groups
public interface OnCreate {}
public interface OnUpdate {}

public class UserRequest {
    @Null(groups = OnCreate.class, message = "ID must be null on create")
    @NotNull(groups = OnUpdate.class, message = "ID required on update")
    private Long id;

    @NotBlank(groups = {OnCreate.class, OnUpdate.class})
    private String name;

    @NotBlank(groups = OnCreate.class)  // required only on create
    private String password;
}

// Controller dùng @Validated với group
@PostMapping
public ResponseEntity<?> create(@Validated(OnCreate.class) @RequestBody UserRequest req) {}

@PutMapping("/{id}")
public ResponseEntity<?> update(@Validated(OnUpdate.class) @RequestBody UserRequest req) {}
```

---

## @ControllerAdvice – Global Exception Handler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    // 1. Validation errors (400)
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> handleValidationErrors(
            MethodArgumentNotValidException ex, HttpServletRequest request) {

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, "Request validation failed"
        );
        problem.setTitle("Validation Error");
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("timestamp", Instant.now());

        List<FieldError> errors = ex.getBindingResult().getFieldErrors().stream()
            .map(fe -> new FieldError(fe.getField(), fe.getDefaultMessage()))
            .toList();
        problem.setProperty("errors", errors);

        return ResponseEntity.badRequest().body(problem);
    }

    // 2. Constraint violations (@Validated on @RequestParam)
    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ProblemDetail> handleConstraintViolation(
            ConstraintViolationException ex) {

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, "Constraint violation"
        );
        List<FieldError> errors = ex.getConstraintViolations().stream()
            .map(v -> new FieldError(v.getPropertyPath().toString(), v.getMessage()))
            .toList();
        problem.setProperty("errors", errors);

        return ResponseEntity.badRequest().body(problem);
    }

    // 3. Business exceptions (404, 409, etc.)
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ProblemDetail> handleNotFound(
            ResourceNotFoundException ex, HttpServletRequest request) {

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND, ex.getMessage()
        );
        problem.setTitle("Resource Not Found");
        problem.setInstance(URI.create(request.getRequestURI()));

        return ResponseEntity.status(404).body(problem);
    }

    @ExceptionHandler(DuplicateResourceException.class)
    public ResponseEntity<ProblemDetail> handleDuplicate(DuplicateResourceException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.CONFLICT, ex.getMessage()
        );
        return ResponseEntity.status(409).body(problem);
    }

    // 4. Security exceptions
    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ProblemDetail> handleAccessDenied(AccessDeniedException ex) {
        ProblemDetail problem = ProblemDetail.forStatus(HttpStatus.FORBIDDEN);
        problem.setDetail("You do not have permission to perform this action");
        return ResponseEntity.status(403).body(problem);
    }

    // 5. Rate limit
    @ExceptionHandler(RateLimitExceededException.class)
    public ResponseEntity<ProblemDetail> handleRateLimit(
            RateLimitExceededException ex, HttpServletResponse response) {

        response.setHeader("Retry-After", String.valueOf(ex.getRetryAfterSeconds()));
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.TOO_MANY_REQUESTS, ex.getMessage()
        );
        return ResponseEntity.status(429).body(problem);
    }

    // 6. Catch-all (500) – log đầy đủ, trả về ít info
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ProblemDetail> handleUnexpected(
            Exception ex, HttpServletRequest request) {

        String errorId = UUID.randomUUID().toString();
        log.error("Unexpected error [{}] at {}: {}", errorId, request.getRequestURI(), ex.getMessage(), ex);

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "An unexpected error occurred. Reference ID: " + errorId
        );
        return ResponseEntity.internalServerError().body(problem);
    }
}
```

---

## Problem Details (RFC 9457 / RFC 7807)

**Spring Boot 3.x** hỗ trợ `ProblemDetail` theo chuẩn RFC 9457:

```json
{
  "type": "https://api.example.com/errors/validation-error",
  "title": "Validation Error",
  "status": 400,
  "detail": "Request validation failed",
  "instance": "/api/users",
  "timestamp": "2024-01-15T10:30:00Z",
  "errors": [
    {
      "field": "email",
      "message": "Must be a valid email"
    },
    {
      "field": "password",
      "message": "Must contain at least 1 uppercase letter and 1 digit"
    }
  ]
}
```

```yaml
# application.yml
spring:
  mvc:
    problemdetails:
      enabled: true  # tự động dùng ProblemDetail cho Spring MVC errors
```

---

## Business Exception Hierarchy

```java
// Base exception
public abstract class ApplicationException extends RuntimeException {
    private final String errorCode;
    private final HttpStatus httpStatus;

    protected ApplicationException(String errorCode, String message, HttpStatus status) {
        super(message);
        this.errorCode = errorCode;
        this.httpStatus = status;
    }
}

// Specific exceptions
public class ResourceNotFoundException extends ApplicationException {
    public ResourceNotFoundException(String resource, Object id) {
        super("RESOURCE_NOT_FOUND",
              String.format("%s with id '%s' not found", resource, id),
              HttpStatus.NOT_FOUND);
    }
}

public class DuplicateResourceException extends ApplicationException {
    public DuplicateResourceException(String resource, String field, Object value) {
        super("DUPLICATE_RESOURCE",
              String.format("%s with %s '%s' already exists", resource, field, value),
              HttpStatus.CONFLICT);
    }
}

public class BusinessRuleException extends ApplicationException {
    public BusinessRuleException(String errorCode, String message) {
        super(errorCode, message, HttpStatus.UNPROCESSABLE_ENTITY);
    }
}

// Usage
public void createUser(CreateUserRequest req) {
    if (userRepo.existsByEmail(req.email())) {
        throw new DuplicateResourceException("User", "email", req.email());
    }
    // ...
}

public void cancelOrder(Long orderId) {
    Order order = orderRepo.findById(orderId)
        .orElseThrow(() -> new ResourceNotFoundException("Order", orderId));

    if (order.getStatus() == OrderStatus.SHIPPED) {
        throw new BusinessRuleException("ORDER_ALREADY_SHIPPED",
            "Cannot cancel an order that has already been shipped");
    }
}
```

---

## Filter vs Interceptor vs @ControllerAdvice

```
Request flow:
HTTP → Filter → DispatcherServlet → Interceptor → Controller → Interceptor → Filter → Response
                                                                     ↑
                                                          @ControllerAdvice (exception handling)
```

| | Filter | Interceptor | @ControllerAdvice |
|--|--------|-------------|-------------------|
| Level | Servlet | Spring MVC | Spring MVC |
| Exception handling | Raw HttpServletResponse | Can throw | Only for @Controller exceptions |
| Access to Spring beans | Via @Autowired | Yes | Yes |
| Request/Response modification | Yes | Yes (pre/post) | Response only |
| Use for | Auth, logging, CORS | Request context, auth check | Error handling, response modification |

---

## Trade-offs

| Global Exception Handling | Trade-off |
|---------------------------|-----------|
| Centralized error handling | All errors go through one place |
| Consistent error format | Must remember to handle new exception types |
| Hide internal details (500) | Harder to debug without error ID tracking |
| Problem Details RFC 9457 | Clients must understand the format |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `basics/testing.md` – Testing validation với @WebMvcTest và MockMvc
- `production/observability.md` – Logging exceptions với traceId, alerting
- **Keywords:** @ExceptionHandler, ResponseEntityExceptionHandler (extend thay vì @ControllerAdvice), @ResponseStatus, HandlerExceptionResolver, ErrorController (/error endpoint), Feign error decoder, validation cascade (@Valid vs @Validated), groups sequence (GroupSequence), @AssertTrue (method-level validation)
