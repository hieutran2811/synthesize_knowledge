# Exception Handling (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Exception Handling là gì?

**Exception** là sự kiện bất thường xảy ra trong quá trình thực thi làm gián đoạn luồng bình thường. Java cung cấp cơ chế **throw/catch** để xử lý và phục hồi từ các tình huống lỗi.

---

## How – Exception Hierarchy

```
java.lang.Throwable
  ├── java.lang.Error (không nên bắt)
  │     ├── OutOfMemoryError
  │     ├── StackOverflowError
  │     ├── VirtualMachineError
  │     └── AssertionError
  └── java.lang.Exception
        ├── Checked Exceptions (bắt buộc handle)
        │     ├── IOException
        │     │     ├── FileNotFoundException
        │     │     └── SocketException
        │     ├── SQLException
        │     ├── ClassNotFoundException
        │     ├── CloneNotSupportedException
        │     └── InterruptedException
        └── RuntimeException (Unchecked – không bắt buộc)
              ├── NullPointerException
              ├── IllegalArgumentException
              ├── IllegalStateException
              ├── IndexOutOfBoundsException
              ├── ClassCastException
              ├── ArithmeticException
              ├── UnsupportedOperationException
              └── ConcurrentModificationException
```

---

## How – Checked vs Unchecked

### Checked Exception
- Compiler **bắt buộc** phải handle (try-catch hoặc khai báo `throws`)
- Dùng cho tình huống **có thể phục hồi** được mà caller cần biết
- Ví dụ: `IOException` (file không tìm thấy, mạng timeout → caller có thể retry)

```java
// Bắt buộc: phải declare throws hoặc try-catch
public void readFile(String path) throws IOException {
    Files.readString(Path.of(path)); // IOException là checked
}

// Hoặc:
public void readFile(String path) {
    try {
        Files.readString(Path.of(path));
    } catch (IOException e) {
        // handle
    }
}
```

### Unchecked Exception (RuntimeException)
- Compiler **không** bắt buộc handle
- Dùng cho **lỗi lập trình** (bug, logic sai), caller không thể/không nên recover
- Ví dụ: `NullPointerException` (lỗi của lập trình viên, không nên catch và bỏ qua)

```java
// Không cần declare hay catch
public void processUser(User user) {
    user.getName().toUpperCase(); // có thể NPE nếu user=null hoặc getName()=null
}
```

---

## How – Try-Catch-Finally

```java
try {
    // Code có thể throw exception
    riskyOperation();
} catch (FileNotFoundException e) {       // Catch cụ thể trước
    log.error("File not found: {}", e.getMessage(), e);
    throw new AppException("File missing", e); // re-throw
} catch (IOException e) {                  // Catch chung hơn sau
    log.error("IO error", e);
} catch (Exception e) {                    // Catch rộng nhất cuối cùng
    log.error("Unexpected error", e);
    throw new RuntimeException("Unexpected error", e);
} finally {
    cleanup(); // Luôn chạy dù có exception hay không
               // Chú ý: nếu finally throw exception → exception gốc bị nuốt!
}
```

**Quy tắc ordering**: catch từ **cụ thể → chung** (subclass trước superclass).

---

## How – Multi-catch (Java 7+)

```java
// Trước Java 7: phải catch từng loại riêng
try { ... }
catch (IOException e)  { handleBoth(e); }
catch (SQLException e) { handleBoth(e); }

// Java 7+: gộp nhiều exception (unrelated)
try { ... }
catch (IOException | SQLException e) {
    // e có type: IOException | SQLException (effective type: Exception)
    log.error("Data error: {}", e.getMessage(), e);
}
// Lưu ý: e là effectively final trong multi-catch
```

---

## How – Try-with-Resources (Java 7+)

Tự động gọi `close()` trên `AutoCloseable` object sau block — kể cả khi có exception.

```java
// Một resource
try (InputStream is = new FileInputStream("file.txt")) {
    byte[] data = is.readAllBytes();
} // is.close() tự động gọi ở đây

// Nhiều resource: đóng theo thứ tự ngược lại (LIFO)
try (Connection conn = dataSource.getConnection();
     PreparedStatement stmt = conn.prepareStatement(sql);
     ResultSet rs = stmt.executeQuery()) {
    while (rs.next()) { processRow(rs); }
} // rs.close() → stmt.close() → conn.close()

// Java 9+: biến effectively final có thể dùng trực tiếp
Connection conn = dataSource.getConnection();
try (conn) { // không cần khai báo lại
    // ...
}
```

### Suppressed Exceptions
Khi exception xảy ra trong try block VÀ `close()` cũng throw exception → exception từ `close()` bị **suppress**:

```java
// Cả try body và close() throw
try (BadResource r = new BadResource()) {
    throw new RuntimeException("from try");
    // r.close() cũng throw IOException
}
// Kết quả: RuntimeException được throw
//          IOException bị suppress (attached)

// Lấy suppressed:
try { ... }
catch (RuntimeException e) {
    Throwable[] suppressed = e.getSuppressed(); // [IOException]
}
```

---

## How – Exception Chaining (Wrapping)

Giữ root cause khi translate exception giữa các layer:

```java
// Repository layer
public User findById(Long id) {
    try {
        return jdbcTemplate.queryForObject(sql, rowMapper, id);
    } catch (EmptyResultDataAccessException e) {
        // translate → domain exception, giữ cause
        throw new UserNotFoundException(id, e);
    } catch (DataAccessException e) {
        throw new RepositoryException("Database error finding user " + id, e);
    }
}

// Custom Exception với cause
public class UserNotFoundException extends RuntimeException {
    private final Long userId;
    public UserNotFoundException(Long userId) {
        super("User not found: " + userId);
        this.userId = userId;
    }
    public UserNotFoundException(Long userId, Throwable cause) {
        super("User not found: " + userId, cause); // giữ root cause!
        this.userId = userId;
    }
    public Long getUserId() { return userId; }
}
```

**Tại sao quan trọng?** Stack trace đầy đủ:
```
UserNotFoundException: User not found: 42
    at UserRepository.findById(UserRepository.java:35)
    at UserService.getUser(UserService.java:20)
Caused by: EmptyResultDataAccessException: Incorrect result size...
    at JdbcTemplate.queryForObject(JdbcTemplate.java:...)
```

---

## How – Custom Exception Best Practices

```java
// 1. Kế thừa đúng loại
public class ValidationException extends RuntimeException { // Unchecked: caller quyết định handle
    private final Map<String, String> violations;

    public ValidationException(Map<String, String> violations) {
        super("Validation failed: " + violations);
        this.violations = Collections.unmodifiableMap(violations);
    }

    public Map<String, String> getViolations() { return violations; }
}

// 2. Provide error code (machine-readable)
public class AppException extends RuntimeException {
    private final String errorCode;
    private final HttpStatus httpStatus;

    public AppException(String errorCode, String message, HttpStatus httpStatus) {
        super(message);
        this.errorCode = errorCode;
        this.httpStatus = httpStatus;
    }

    // Cause variant
    public AppException(String errorCode, String message, HttpStatus httpStatus, Throwable cause) {
        super(message, cause);
        this.errorCode = errorCode;
        this.httpStatus = httpStatus;
    }
}

// 3. Specific subclasses
public class NotFoundException extends AppException {
    public NotFoundException(String resource, Object id) {
        super("NOT_FOUND", resource + " not found with id: " + id, HttpStatus.NOT_FOUND);
    }
}

public class ConflictException extends AppException {
    public ConflictException(String resource, String field, Object value) {
        super("CONFLICT", resource + " with " + field + "=" + value + " already exists", HttpStatus.CONFLICT);
    }
}
```

---

## How – Exception trong Lambda & Stream

Lambda/Stream không thể throw checked exception trực tiếp:

```java
// COMPILE ERROR: IOException là checked
List<String> contents = paths.stream()
    .map(path -> Files.readString(path)) // IOException!
    .collect(Collectors.toList());

// Fix 1: Wrap thành unchecked
List<String> contents = paths.stream()
    .map(path -> {
        try { return Files.readString(path); }
        catch (IOException e) { throw new UncheckedIOException(e); }
    })
    .collect(Collectors.toList());

// Fix 2: Utility method
@FunctionalInterface
public interface ThrowingFunction<T, R> {
    R apply(T t) throws Exception;

    static <T, R> Function<T, R> wrap(ThrowingFunction<T, R> f) {
        return t -> {
            try { return f.apply(t); }
            catch (Exception e) { throw new RuntimeException(e); }
        };
    }
}

List<String> contents = paths.stream()
    .map(ThrowingFunction.wrap(Files::readString))
    .collect(Collectors.toList());
```

---

## Components – Anti-patterns

### 1. Exception Swallowing (Nuốt Exception)
```java
// NGUY HIỂM! Exception biến mất không dấu vết
try {
    processOrder(order);
} catch (Exception e) {
    // KHÔNG LÀM GÌ! Bug sẽ impossible to debug
}

// FIX: luôn log hoặc re-throw
} catch (Exception e) {
    log.error("Failed to process order {}: {}", order.getId(), e.getMessage(), e);
    throw new OrderProcessingException(order.getId(), e);
}
```

### 2. Pokemon Exception (Catch 'Em All)
```java
// TRÁNH: catch Exception hoặc Throwable quá rộng
try { ... }
catch (Exception e) { log.error(e); } // không biết cần retry? ignore? fail-fast?

// ĐÚNG: catch cụ thể từng loại
try { ... }
catch (TransientException e) { retry(); }
catch (PermanentException e) { failFast(e); }
catch (Exception e) { // unexpected
    log.error("Unexpected", e);
    throw new InternalServerException(e);
}
```

### 3. Return null thay vì throw
```java
// TRÁNH
public User findUser(Long id) {
    User user = repo.findById(id);
    if (user == null) return null; // caller phải nhớ null check!
    return user;
}

// ĐÚNG: Optional hoặc throw
public Optional<User> findUser(Long id) {
    return repo.findById(id);
}
// hoặc:
public User getUser(Long id) {
    return repo.findById(id)
        .orElseThrow(() -> new NotFoundException("User", id));
}
```

### 4. Log và Re-throw (Double logging)
```java
// TRÁNH: log ở mọi layer → duplicate log entries
try { ... }
catch (Exception e) {
    log.error("Error in repository", e);  // logged here
    throw e;                              // logged again at service layer!
}

// ĐÚNG: chỉ log ở layer cuối cùng (global exception handler)
// hoặc chỉ log khi wrap
catch (Exception e) {
    throw new RepositoryException("DB error", e); // KHÔNG log ở đây
}
// Chỉ log ở @ControllerAdvice hoặc ErrorController
```

### 5. finally và Return
```java
// NGUY HIỂM: return trong finally override return trong try!
String riskyMethod() {
    try {
        return "from try";
    } finally {
        return "from finally"; // "from try" bị mất!
    }
}
// Result: "from finally" – không bao giờ dùng return trong finally!
```

---

## When – Checked hay Unchecked?

**Dùng Checked khi:**
- Caller **có thể và nên** handle exception
- Caller cần biết về failure để recovery
- Ví dụ: `FileNotFoundException` → caller có thể chọn file khác

**Dùng Unchecked khi:**
- Lỗi lập trình (bug) — `NullPointerException`, `IllegalArgumentException`
- Caller không thể recover có ý nghĩa
- Framework boundaries (Spring, Hibernate dùng unchecked)
- Checked exception trong API sẽ làm API khó dùng

> **Xu hướng hiện đại**: nhiều framework (Spring, Hibernate) wrap checked thành unchecked để API gọn hơn. Clean Code và Effective Java cũng recommend unchecked cho hầu hết custom exceptions.

---

## Compare – finally vs try-with-resources

| | `finally` | try-with-resources |
|--|-----------|-------------------|
| AutoClose | Thủ công | Tự động |
| Suppressed Exception | Mất (override) | Giữ lại |
| Code | Verbose | Ngắn gọn |
| Multiple resource | Phức tạp | Đơn giản (LIFO order) |
| Dùng khi | Logic cleanup phức tạp | AutoCloseable resource |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Tách error handling khỏi business logic | Overhead (tạo stack trace tốn CPU) |
| Forced handling với checked exception | Checked exception gây verbose code |
| Exception chaining giữ root cause | Exception hierarchy phức tạp |
| try-with-resources tránh resource leak | Lambda không support checked exception trực tiếp |

---

## Real-world Usage (Production)

### 1. Global Exception Handler (Spring)
```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(NotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse(e.getErrorCode(), e.getMessage()));
    }

    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<ErrorResponse> handleValidation(ValidationException e) {
        return ResponseEntity.badRequest()
            .body(new ErrorResponse("VALIDATION_ERROR", e.getViolations()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneral(Exception e) {
        log.error("Unhandled exception", e); // chỉ log ở đây
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse("INTERNAL_ERROR", "An unexpected error occurred"));
    }
}
```

### 2. Resilient Service với Retry
```java
@Service
public class PaymentService {
    @Retryable(
        value = {TransientPaymentException.class},
        maxAttempts = 3,
        backoff = @Backoff(delay = 1000, multiplier = 2)
    )
    public PaymentResult charge(PaymentRequest request) {
        try {
            return gateway.charge(request);
        } catch (GatewayTimeoutException e) {
            throw new TransientPaymentException("Gateway timeout", e);
        } catch (InsufficientFundsException e) {
            throw new PermanentPaymentException("Insufficient funds", e);
        }
    }

    @Recover
    public PaymentResult recover(TransientPaymentException e, PaymentRequest request) {
        log.error("Payment failed after retries for request {}", request.getId(), e);
        throw new PaymentException("Payment service temporarily unavailable", e);
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Concurrency & Multithreading** (deep dive)
>
> Keyword: Thread lifecycle (NEW/RUNNABLE/BLOCKED/WAITING/TIMED_WAITING/TERMINATED), Thread vs Runnable vs Callable, synchronized (object lock, class lock), volatile (visibility guarantee, not atomicity), java.util.concurrent.atomic (CAS), ReentrantLock (tryLock, fairness), ReadWriteLock, StampedLock, ExecutorService (thread pool internals), Future & CompletableFuture chain, ForkJoinPool (work stealing), CountDownLatch, CyclicBarrier, Semaphore, race condition, deadlock, livelock, starvation
