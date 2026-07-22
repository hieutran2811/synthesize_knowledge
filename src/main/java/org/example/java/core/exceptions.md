# Exception Handling (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Exception Handling là gì?

**Exception** *(ngoại lệ)* là một object biểu diễn tình huống bất thường xảy ra trong lúc thực thi. Khi exception được `throw`, luồng điều khiển bình thường bị ngắt và JVM tìm `catch` phù hợp dọc theo call stack. Nếu không tìm thấy, thread hiện tại kết thúc và uncaught-exception handler được thông báo.

> 💡 **Giải thích dễ hiểu — exception là phiếu báo sự cố đi ngược dây chuyền:**
> Một công đoạn không xử lý được sẽ gửi phiếu lên công đoạn đã gọi nó. Mỗi tầng có thể xử lý, chuyển đổi phiếu sang ngôn ngữ của mình hoặc chuyển tiếp lên trên. Nếu không tầng nào nhận, dây chuyền của thread đó dừng; exception không mặc nhiên làm toàn bộ JVM tắt.

---

## How – Exception Hierarchy

```text
java.lang.Throwable
  ├── java.lang.Error (thường không nên bắt để tiếp tục như bình thường)
  │     ├── OutOfMemoryError
  │     ├── StackOverflowError
  │     ├── VirtualMachineError
  │     └── AssertionError
  └── java.lang.Exception
        ├── Checked Exceptions (compiler bắt buộc catch hoặc declare)
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

`Throwable` là gốc của cả `Exception` và `Error`. Phần lớn `Error` báo vấn đề nghiêm trọng từ JVM hoặc môi trường mà ứng dụng thông thường không thể khôi phục an toàn. Không nên `catch (Throwable)` hay `catch (Error)` rộng để tiếp tục xử lý; cleanup bằng `finally`/try-with-resources và logging tại ranh giới giám sát là mục đích khác với “nuốt lỗi”.

> 💡 **Giải thích dễ hiểu — hierarchy là hệ thống phân loại phiếu sự cố:**
> `Exception` thường là sự cố ứng dụng có thể mô tả hoặc chuyển tiếp. `Error` giống cảnh báo tòa nhà mất kết cấu: bắt tờ cảnh báo rồi tiếp tục phục vụ khách thường không làm tòa nhà an toàn hơn. Loại cụ thể giúp caller biết hành động nào hợp lý thay vì xử lý mọi sự cố giống nhau.

---

## How – Checked vs Unchecked

### Checked Exception *(ngoại lệ được compiler kiểm tra)*
- Compiler bắt buộc caller phải `catch` hoặc tiếp tục khai báo bằng `throws`; khai báo `throws` là chuyển trách nhiệm, chưa phải xử lý.
- Thường dùng khi caller có hành động phục hồi hợp lý và API muốn buộc caller cân nhắc failure.
- Ví dụ: `IOException`; tùy nguyên nhân và ngữ cảnh, caller có thể chọn file khác, báo người dùng hoặc retry có kiểm soát.

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

### Unchecked Exception *(ngoại lệ không bị compiler bắt buộc xử lý)* (`RuntimeException`)
- Compiler không bắt buộc `catch` hoặc khai báo.
- Thường dùng cho lỗi vi phạm precondition, trạng thái bất hợp lệ, bug, hoặc failure mà phần lớn caller không thể xử lý có ý nghĩa.
- Ví dụ: `NullPointerException` thường chỉ ra contract null bị vi phạm; catch rồi bỏ qua sẽ che nguyên nhân thay vì sửa contract hoặc dữ liệu.

```java
// Không cần declare hay catch
public void processUser(User user) {
    user.getName().toUpperCase(); // có thể NPE nếu user=null hoặc getName()=null
}
```

Checked/unchecked là quyết định thiết kế API, không phải phép phân loại hoàn hảo “phục hồi được” và “không phục hồi được”. Cùng một lỗi I/O có thể được retry ở batch job nhưng phải fail request ngay trong luồng khác.

> 💡 **Giải thích dễ hiểu — checked là phiếu bắt buộc ký nhận:**
> Compiler buộc người nhận ghi rõ “tôi xử lý” hoặc “tôi chuyển tiếp”. Unchecked vẫn có thể xảy ra nhưng không cần chữ ký ở mọi tầng. Chọn loại nào phụ thuộc việc buộc mọi caller xử lý có tạo ra hành động hữu ích hay chỉ sinh ra các `catch` hình thức.

---

## How – Try-Catch-Finally

```java
try {
    // Code có thể throw exception
    riskyOperation();
} catch (FileNotFoundException e) {       // Catch cụ thể trước
    throw new UncheckedIOException("File missing", e); // wrap và giữ cause
} catch (IOException e) {                  // Catch chung hơn sau
    throw new UncheckedIOException("I/O operation failed", e);
} finally {
    cleanup(); // Thông thường chạy cả khi thành công, throw hoặc return.
               // Nếu cleanup throw, exception gốc có thể bị che mất.
}
```

**Quy tắc ordering**: catch từ **cụ thể → chung** (subclass trước superclass).

`finally` không được bảo đảm trong mọi tình huống: `Runtime.halt()`, JVM/process bị kill hoặc crash, mất điện, hay code không bao giờ thoát khỏi `try` đều có thể ngăn nó chạy. Không nên đặt `return` hoặc tùy tiện throw exception mới trong `finally`.

> 💡 **Giải thích dễ hiểu — catch là trạm nhận sự cố, finally là ca dọn bàn:**
> Trạm chuyên môn nhận phiếu cụ thể trước; trạm tổng quát đứng sau, nếu không nhánh cụ thể sẽ không bao giờ tới lượt. Ca dọn bàn thường diễn ra dù phục vụ thành công hay lỗi, nhưng không phải “bất tử” khi cả nhà hàng bị cắt điện. Với resource chuẩn, try-with-resources an toàn hơn tự gọi cleanup.

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
    // Compiler suy ra common supertype cho các member được phép gọi trên e.
    log.error("Data error: {}", e.getMessage(), e);
}
// Lưu ý: e là implicitly final trong multi-catch, không thể gán e = ...
```

---

## How – Try-with-Resources (Java 7+)

**Try-with-resources** *(khối tự đóng tài nguyên)* tự động gọi `close()` trên object triển khai `AutoCloseable` khi rời block, kể cả khi thân `try` throw exception.

```java
// Một resource
try (InputStream is = new FileInputStream("file.txt")) {
    byte[] data = is.readAllBytes();
} // is.close() tự động gọi ở đây

// Nhiều resource: các resource đã khởi tạo thành công đóng theo thứ tự ngược (LIFO)
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

Nếu khởi tạo một resource ở giữa danh sách thất bại, chỉ những resource đã khởi tạo thành công trước đó được đóng. Không phải mọi `AutoCloseable` đều hỗ trợ gọi `close()` nhiều lần; tuân theo contract của loại resource cụ thể.

> 💡 **Giải thích dễ hiểu — try-with-resources là khay mượn đồ tự hoàn trả:**
> Mượn `conn`, rồi `stmt`, rồi `rs` giống xếp ba món lên chồng; khi xong sẽ trả từ món trên cùng: `rs → stmt → conn`. Nếu mượn món thứ ba thất bại, hai món đã mượn vẫn được trả, nhờ đó ít rò rỉ tài nguyên hơn cleanup viết tay.

### Suppressed Exceptions *(ngoại lệ bị đính kèm)*
Khi thân `try` throw exception và `close()` cũng throw, exception từ thân `try` được giữ làm exception chính. Exception khi đóng resource bị **suppressed** *(đính kèm thay vì che lỗi chính)* và có thể đọc bằng `getSuppressed()`:

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

Nếu thân `try` không throw nhưng `close()` throw, lỗi từ `close()` được truyền ra bình thường. Khi nhiều `close()` cùng lỗi, lỗi đóng đầu tiên theo thứ tự đóng trở thành exception chính hoặc suppressed tùy việc đã có exception chính trước đó; các lỗi đóng sau được đính kèm tiếp.

> 💡 **Giải thích dễ hiểu — giữ biên bản sự cố chính và ghim các sự cố lúc khóa cửa:**
> Nếu máy hỏng trong ca làm rồi chìa khóa cũng kẹt lúc đóng cửa, báo cáo “máy hỏng” vẫn là nguyên nhân chính; “kẹt khóa” được ghim kèm để không mất dấu. Cleanup viết tay dễ vô tình thay toàn bộ báo cáo bằng lỗi cuối cùng.

---

## How – Exception Chaining (Wrapping)

**Exception chaining** *(nối chuỗi ngoại lệ)* giữ **root cause** *(nguyên nhân gốc)* khi translate exception giữa các layer. Tầng trên nhận được loại exception phù hợp với abstraction của nó nhưng stack trace vẫn chứa lỗi ban đầu để điều tra:

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

> 💡 **Giải thích dễ hiểu — wrapping là đổi nhãn thùng nhưng giữ phiếu nguồn:**
> Kho dữ liệu báo “không có row”; tầng nghiệp vụ đổi thành “không tìm thấy user” để caller không phụ thuộc thuật ngữ JDBC. `cause` giống phiếu xuất kho còn nằm trong thùng: người vận hành vẫn lần ngược được nguồn lỗi. Nếu chỉ tạo exception mới mà không truyền `e`, dấu vết quan trọng sẽ bị cắt.

---

## How – Custom Exception Best Practices

```java
// 1. Kế thừa đúng loại
public class ValidationException extends RuntimeException { // Unchecked: caller quyết định handle
    private final Map<String, String> violations;

    public ValidationException(Map<String, String> violations) {
        super("Validation failed: " + violations);
        this.violations = Map.copyOf(violations); // defensive immutable snapshot
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

    public String getErrorCode() { return errorCode; }
    public HttpStatus getHttpStatus() { return httpStatus; }
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

`Collections.unmodifiableMap(violations)` chỉ tạo read-only view; code đang giữ reference gốc vẫn có thể sửa map phía sau. `Map.copyOf()` tạo immutable snapshot và fail fast nếu có key/value null. Với project chưa dùng Java 10, có thể copy trước rồi bọc: `Collections.unmodifiableMap(new HashMap<>(violations))`.

Gắn `HttpStatus` trực tiếp vào exception là lựa chọn tiện cho application/web layer nhưng làm domain phụ thuộc HTTP. Trong kiến trúc tách lớp nghiêm ngặt, domain exception chỉ nên mang code và dữ liệu nghiệp vụ; global handler ánh xạ nó sang HTTP status ở boundary.

> 💡 **Giải thích dễ hiểu — custom exception là mẫu phiếu có mã máy đọc được:**
> Message dành cho người vận hành, còn `errorCode` giúp client và monitoring xử lý ổn định mà không phải phân tích câu chữ. Dữ liệu đính kèm nên là snapshot để người khác không sửa “biên bản lỗi” sau khi nó đã được lập.

---

## How – Exception trong Lambda & Stream

Lambda có thể throw checked exception chỉ khi target functional interface khai báo loại đó. Các interface chuẩn như `Function<T, R>` không khai báo `throws`, nên lambda dùng trong phần lớn Stream operation không thể truyền `IOException` trực tiếp:

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
            catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("Operation interrupted", e);
            }
            catch (IOException e) { throw new UncheckedIOException(e); }
            catch (RuntimeException e) { throw e; }
            catch (Exception e) { throw new RuntimeException(e); }
        };
    }
}

List<String> contents = paths.stream()
    .map(ThrowingFunction.wrap(Files::readString))
    .collect(Collectors.toList());
```

Wrapper tổng quát làm API tiện hơn nhưng có thể che loại failure và khiến xử lý từng phần khó đọc. Nếu mỗi phần tử cần retry, thu thập cả success/failure hoặc tiếp tục sau lỗi, vòng lặp tường minh hay result type thường rõ hơn Stream fail-fast.

> 💡 **Giải thích dễ hiểu — Stream dùng đường ống có đầu nối chuẩn:**
> `Function` chuẩn không có khe để chuyển checked exception ra ngoài, nên phải đổi nó thành “kiện hàng” unchecked vừa đầu nối. Khi đổi nhãn vẫn phải giữ cause; riêng interruption phải dựng lại cờ báo, nếu không tín hiệu yêu cầu dừng bị thất lạc giữa dây chuyền.

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

// FIX: xử lý có chủ đích hoặc re-throw và giữ cause
try {
    processOrder(order);
} catch (OrderValidationException e) {
    throw new OrderProcessingException(order.getId(), e);
}
```

Không phải mọi exception đều bắt buộc log tại chỗ. Điều bắt buộc là có quyết định rõ ràng: phục hồi, chuyển đổi/chuyển tiếp, hoặc cố ý bỏ qua với lý do được ghi chú và metric phù hợp. Log rồi tiếp tục với state không hợp lệ cũng nguy hiểm như nuốt lỗi.

> 💡 **Giải thích dễ hiểu — nuốt exception là xé phiếu báo cháy:**
> Không có tiếng chuông không có nghĩa là không có cháy. Nhưng phát chuông ở mọi tầng cũng tạo hàng chục báo động cho cùng một đám cháy. Hãy giữ cause khi chuyển phiếu và log một lần tại nơi có đủ ngữ cảnh để quyết định.

### 2. Pokemon Exception (Catch 'Em All)
```java
// TRÁNH: catch Exception hoặc Throwable quá rộng
try { ... }
catch (Exception e) { log.error("Operation failed", e); } // retry, ignore hay fail-fast?

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
    User user = legacyRepo.findById(id);
    if (user == null) return null; // caller phải nhớ null check!
    return user;
}

// ĐÚNG: Optional hoặc throw
public Optional<User> findUser(Long id) {
    return Optional.ofNullable(legacyRepo.findById(id));
}
// hoặc:
public User getUser(Long id) {
    return findUser(id)
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

// ĐÚNG: wrap ở tầng có abstraction phù hợp nhưng chưa log
try {
    repositoryOperation();
} catch (DataAccessException e) {
    throw new RepositoryException("DB error", e); // KHÔNG log ở đây
}
// Log một lần ở @ControllerAdvice, ErrorController, message-consumer boundary...
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
// Result: "from finally"; nếu try throw thì return này còn nuốt exception đó.
// Không bao giờ dùng return trong finally!
```

---

## When – Checked hay Unchecked?

**Dùng Checked khi:**
- Caller trực tiếp có thể và nên thực hiện hành động phục hồi cụ thể.
- Việc buộc caller xác nhận failure là một phần có giá trị của API contract.
- Ví dụ: `FileNotFoundException` trong ứng dụng desktop có thể cho phép người dùng chọn file khác.

**Dùng Unchecked khi:**
- Vi phạm precondition hoặc invariant — `NullPointerException`, `IllegalArgumentException`.
- Phần lớn caller không thể recover có ý nghĩa tại chỗ.
- Failure phải đi qua nhiều layer và không muốn làm rò rỉ dependency-specific exception trong mọi method signature.
- Ép khai báo checked chỉ tạo `catch` rồi wrap/ignore máy móc, không tạo thêm phương án xử lý.

Không chọn unchecked chỉ để API “trông sạch”. Dù compiler không bắt buộc, public API vẫn nên document failure quan trọng và cung cấp error code/cause đủ ổn định.

> 💡 **Giải thích dễ hiểu — hỏi caller có nút bấm hữu ích hay không:**
> Nếu nhận lỗi mà caller có thể bấm “chọn file khác”, checked contract có ích. Nếu mọi tầng chỉ có thể chuyển lỗi lên global handler, bắt từng tầng ký nhận tạo thủ tục nhưng không tạo giải pháp. Đây là heuristic thiết kế, không phải luật tự nhiên cho mọi exception class.

---

## Compare – finally vs try-with-resources

| | `finally` | try-with-resources |
|--|-----------|-------------------|
| AutoClose | Thủ công | Tự động |
| Suppressed exception | Phải cài thủ công, dễ che lỗi gốc | Tự giữ lỗi `close()` bằng suppressed list |
| Code | Verbose | Ngắn gọn |
| Multiple resource | Phức tạp | Đơn giản (LIFO order) |
| Dùng khi | Logic cleanup phức tạp | AutoCloseable resource |

---

## Trade-offs

| Ưu điểm | Nhược điểm |
|---------|-----------|
| Tách error handling khỏi business logic | Khi tạo/throw exception, thu stack trace có thể tốn CPU |
| Forced handling với checked exception | Checked exception gây verbose code |
| Exception chaining giữ root cause | Exception hierarchy phức tạp |
| try-with-resources tránh resource leak | Functional interface chuẩn thường không khai báo checked exception |

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

Global handler là ranh giới chuyển exception nội bộ thành contract bên ngoài. Response nên có error code ổn định, correlation/trace ID và thông điệp an toàn; không trả stack trace, SQL, đường dẫn hệ thống hoặc secret cho client. Lỗi bất ngờ được log một lần tại đây với toàn bộ cause chain.

> 💡 **Giải thích dễ hiểu — global handler là quầy phiên dịch cuối:**
> Bên trong hệ thống có thể nói bằng ngôn ngữ JDBC, domain hoặc framework; quầy cuối đổi chúng thành mẫu phản hồi thống nhất cho khách. Khách nhận mã tra cứu và lời giải thích an toàn, còn hồ sơ kỹ thuật chi tiết chỉ nằm trong log có trace ID.

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
        metrics.counter("payment.retry.exhausted").increment();
        throw new PaymentException("Payment service temporarily unavailable", e);
    }
}
```

Chỉ retry failure tạm thời và nên dùng exponential backoff có jitter để nhiều instance không thử lại cùng lúc. `@Retryable` hoạt động qua Spring proxy nên self-invocation có thể bỏ qua interceptor. Timeout, retry và circuit breaker phải có budget thống nhất, nếu không latency tổng có thể tăng ngoài dự kiến.

Đặc biệt, retry thao tác thanh toán chỉ an toàn khi gateway hỗ trợ idempotency key hoặc hệ thống có cơ chế chống thực thi trùng. Timeout có nghĩa là “chưa biết kết quả”, không đồng nghĩa giao dịch chắc chắn thất bại.

> 💡 **Giải thích dễ hiểu — retry là gọi lại quầy khi đường dây chập chờn:**
> Nếu cuộc gọi mất tín hiệu sau khi nhân viên đã trừ tiền, gọi lại có thể trừ lần hai. Idempotency key giống mã giao dịch duy nhất: quầy nhận lại cùng mã sẽ trả kết quả cũ thay vì thu tiền lần nữa. Backoff và jitter còn tránh cảnh cả đám đông cùng gọi lại đúng một giây.

---

## Ghi chú – Chủ đề liên quan

> Đọc tiếp: [errors.md](errors.md) để phân biệt `Error` và `Exception`, [concurrency.md](concurrency.md) để xử lý interruption/failure giữa các thread, và [testing.md](testing.md) để kiểm thử failure path.
