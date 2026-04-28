# Spring MVC & Spring Transaction

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

# PHẦN 1: Spring MVC

## What – Spring MVC là gì?

**Spring MVC** (Model-View-Controller) là web framework của Spring xử lý HTTP requests theo pattern MVC, với **DispatcherServlet** làm trung tâm điều phối.

---

## How – Request Lifecycle (DispatcherServlet)

```
HTTP Request
    ↓
DispatcherServlet (Front Controller)
    ↓
HandlerMapping       → tìm handler (controller method) phù hợp
    ↓
HandlerAdapter       → gọi handler
    ↓
    [Filter chain]   → trước/sau handler
    [Interceptor]    → preHandle → handler → postHandle → afterCompletion
    ↓
Controller Method    → xử lý business logic
    ↓
ModelAndView / @ResponseBody → kết quả
    ↓
ViewResolver (nếu có template)  hoặc  HttpMessageConverter (REST)
    ↓
HTTP Response
```

---

## How – Controller

### @RestController
```java
@RestController
@RequestMapping("/api/v1/users")  // base path
public class UserController {

    private final UserService userService;

    // Constructor injection (no @Autowired needed, single constructor)
    public UserController(UserService userService) { this.userService = userService; }

    // GET /api/v1/users
    @GetMapping
    public Page<UserDto> listUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) String search) {
        return userService.findAll(page, size, search);
    }

    // GET /api/v1/users/42
    @GetMapping("/{id}")
    public ResponseEntity<UserDto> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    // POST /api/v1/users
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED) // 201
    public UserDto createUser(@Valid @RequestBody CreateUserRequest request) {
        return userService.create(request);
    }

    // PUT /api/v1/users/42
    @PutMapping("/{id}")
    public UserDto updateUser(@PathVariable Long id,
                              @Valid @RequestBody UpdateUserRequest request) {
        return userService.update(id, request);
    }

    // PATCH /api/v1/users/42
    @PatchMapping("/{id}/status")
    public ResponseEntity<Void> updateStatus(@PathVariable Long id,
                                              @RequestParam UserStatus status) {
        userService.updateStatus(id, status);
        return ResponseEntity.noContent().build(); // 204
    }

    // DELETE /api/v1/users/42
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteUser(@PathVariable Long id) {
        userService.delete(id);
    }
}
```

### Request Binding Annotations

```java
@GetMapping("/search")
public List<UserDto> search(
    @RequestParam("q") String query,                    // ?q=alice
    @RequestParam(value="page", defaultValue="0") int page,
    @RequestParam(required = false) List<String> tags,  // ?tags=a&tags=b
    @RequestHeader("X-Request-Id") String requestId,    // Header
    @CookieValue(value="token", required=false) String token // Cookie
) { ... }

@PostMapping("/{categoryId}/items")
public ItemDto createItem(
    @PathVariable Long categoryId,                      // /123/items
    @RequestBody @Valid CreateItemRequest body,          // JSON body
    @RequestAttribute("currentUser") User user          // request attribute (từ Filter/Interceptor)
) { ... }

// Multipart file upload
@PostMapping("/avatar")
public ResponseEntity<String> uploadAvatar(
    @RequestPart("file") MultipartFile file,
    @RequestPart("metadata") UserMetadata metadata
) { ... }
```

---

## How – ResponseEntity

```java
// ResponseEntity cho full control: status + headers + body
return ResponseEntity
    .status(HttpStatus.CREATED)                              // 201
    .header("Location", "/users/" + user.getId())
    .header("X-Request-Id", requestId)
    .contentType(MediaType.APPLICATION_JSON)
    .body(UserDto.from(user));

// Helpers
ResponseEntity.ok(body);                  // 200 + body
ResponseEntity.noContent().build();       // 204, no body
ResponseEntity.notFound().build();        // 404, no body
ResponseEntity.badRequest().body(error);  // 400 + body
ResponseEntity.created(location).body(dto); // 201 + Location header
```

---

## How – @ControllerAdvice (Global Exception Handling)

```java
@RestControllerAdvice // = @ControllerAdvice + @ResponseBody
public class GlobalExceptionHandler {

    @ExceptionHandler(NotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ErrorResponse handleNotFound(NotFoundException ex) {
        return new ErrorResponse("NOT_FOUND", ex.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ValidationErrorResponse handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> violations = ex.getBindingResult()
            .getFieldErrors().stream()
            .collect(Collectors.toMap(
                FieldError::getField,
                fe -> fe.getDefaultMessage() != null ? fe.getDefaultMessage() : "Invalid"
            ));
        return new ValidationErrorResponse("VALIDATION_FAILED", violations);
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ErrorResponse handleGeneral(Exception ex, HttpServletRequest request) {
        log.error("Unhandled exception on {}", request.getRequestURI(), ex);
        return new ErrorResponse("INTERNAL_ERROR", "An unexpected error occurred");
    }
}

record ErrorResponse(String code, String message) {}
record ValidationErrorResponse(String code, Map<String, String> violations) {}
```

---

## How – Filter vs Interceptor vs AOP

```
Request → [Filter 1] → [Filter 2] → DispatcherServlet → [Interceptor 1] → Controller → AOP
```

| | Filter | Interceptor | AOP |
|--|--------|------------|-----|
| Level | Servlet | Spring MVC | Spring |
| Scope | All requests | MVC requests | Spring beans |
| Access | HttpServletRequest/Response | HandlerMethod | Joinpoint |
| Order | `@Order` | `addInterceptors()` order | `@Order` |
| Dùng cho | CORS, auth token, logging | Auth, locale, performance | Caching, transaction, retry |

```java
// Filter
@Component
@Order(1)
public class RequestLoggingFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res,
                                    FilterChain chain) throws IOException, ServletException {
        String requestId = UUID.randomUUID().toString();
        MDC.put("requestId", requestId);
        res.setHeader("X-Request-Id", requestId);
        try {
            chain.doFilter(req, res);
        } finally {
            MDC.clear();
        }
    }
}

// Interceptor
@Component
public class AuthInterceptor implements HandlerInterceptor {
    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse res, Object handler) {
        String token = req.getHeader("Authorization");
        if (token == null || !tokenService.isValid(token)) {
            res.setStatus(401);
            return false; // stop processing
        }
        req.setAttribute("currentUser", tokenService.extractUser(token));
        return true; // continue
    }

    @Override
    public void afterCompletion(HttpServletRequest req, HttpServletResponse res,
                                Object handler, Exception ex) {
        // cleanup
    }
}

// Register interceptor
@Configuration
public class WebConfig implements WebMvcConfigurer {
    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(authInterceptor)
            .addPathPatterns("/api/**")
            .excludePathPatterns("/api/auth/**", "/api/public/**");
    }
}
```

---

# PHẦN 2: Spring Transaction

## What – @Transactional là gì?

**@Transactional** là annotation AOP proxy wraps method trong transaction: begin → execute → commit/rollback.

---

## How – Propagation (Lan truyền Transaction)

| Propagation | Hành vi |
|-----------|---------|
| `REQUIRED` (default) | Dùng tx hiện có, tạo mới nếu chưa có |
| `REQUIRES_NEW` | Luôn tạo tx mới, suspend tx hiện có |
| `NESTED` | Tạo savepoint bên trong tx hiện có |
| `SUPPORTS` | Dùng tx nếu có, không có thì chạy không có tx |
| `NOT_SUPPORTED` | Suspend tx hiện có, chạy không có tx |
| `MANDATORY` | Phải có tx, ném exception nếu không |
| `NEVER` | Không được có tx, ném exception nếu có |

```java
@Service
public class OrderService {

    @Transactional // REQUIRED – join existing or create new
    public Order placeOrder(OrderRequest req) {
        Order order = orderRepo.save(Order.create(req));
        paymentService.charge(order); // nếu throw → rollback cả order
        auditService.logOrder(order); // gọi REQUIRES_NEW → tx riêng
        return order;
    }
}

@Service
public class AuditService {
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void logOrder(Order order) {
        // Tx riêng biệt – commit ngay cả khi placeOrder() rollback sau đó
        // Dùng cho: audit log, notification – phải lưu dù transaction chính fail
        auditRepo.save(AuditLog.from(order));
    }
}

@Service
public class InventoryService {
    @Transactional(propagation = Propagation.NESTED)
    public void reserveItems(List<Item> items) {
        // Savepoint – nếu reserve fail → rollback về savepoint, không rollback toàn bộ tx cha
        // Chỉ hỗ trợ bởi JDBC (không phải JPA native)
        items.forEach(item -> {
            if (!stockRepo.reserve(item)) throw new OutOfStockException(item);
        });
    }
}
```

---

## How – Isolation Levels

Giải quyết các vấn đề đọc dữ liệu trong môi trường concurrent:

| Isolation Level | Dirty Read | Non-repeatable Read | Phantom Read | Performance |
|----------------|:----------:|:-------------------:|:------------:|:-----------:|
| `READ_UNCOMMITTED` | Có | Có | Có | Nhất |
| `READ_COMMITTED` (default PG) | Không | Có | Có | Cao |
| `REPEATABLE_READ` (default MySQL) | Không | Không | Có | Trung bình |
| `SERIALIZABLE` | Không | Không | Không | Thấp nhất |

```
Dirty Read:           Tx A đọc data Tx B chưa commit → B rollback → A đọc data sai
Non-repeatable Read:  Tx A đọc 2 lần → giữa đó Tx B UPDATE commit → A thấy kết quả khác nhau
Phantom Read:         Tx A đọc 2 lần (với condition) → giữa đó Tx B INSERT commit → A thấy row mới
```

```java
@Transactional(isolation = Isolation.READ_COMMITTED) // thường dùng nhất
public Order findOrder(Long id) { ... }

@Transactional(isolation = Isolation.SERIALIZABLE)
public void transferMoney(Long fromId, Long toId, BigDecimal amount) {
    // Tuyệt đối không có concurrent anomaly – dùng cho financial
}

@Transactional(isolation = Isolation.REPEATABLE_READ)
public void processReport(Long reportId) {
    // Đảm bảo data nhất quán trong suốt transaction
}
```

---

## How – Rollback Rules

```java
// Default: rollback với RuntimeException và Error, KHÔNG rollback với checked Exception
@Transactional
public void defaultBehavior() throws IOException {
    repo.save(entity);
    throw new IOException("checked"); // KHÔNG rollback! (default)
    throw new RuntimeException();     // Rollback (default)
}

// Custom rollback rules
@Transactional(rollbackFor = { IOException.class, BusinessException.class })
public void customRollback() throws IOException { ... }

@Transactional(noRollbackFor = OptimisticLockingFailureException.class)
public void noRollbackForOptimistic() { ... }

// Programmatic rollback
@Transactional
public void programmaticRollback() {
    if (someCondition) {
        TransactionAspectSupport.currentTransactionStatus().setRollbackOnly();
        // Đánh dấu rollback nhưng tiếp tục code (không throw exception)
    }
}
```

---

## How – readOnly Optimization

```java
@Transactional(readOnly = true)
public List<UserDto> findAllUsers() {
    // readOnly hints:
    // - Hibernate: skip dirty checking (flush mode = NEVER)
    // - JDBC driver: routing read traffic to replica
    // - Database: skip row lock acquisition
    return userRepo.findAll().stream().map(UserDto::from).toList();
}

// Annotate cả class và override method cụ thể
@Service
@Transactional(readOnly = true)  // default read-only cho toàn service
public class UserQueryService {
    public List<UserDto> findAll() { ... }     // readOnly = true
    public UserDto findById(Long id) { ... }   // readOnly = true

    @Transactional // override: không readonly khi cần write
    public User save(User user) { ... }
}
```

---

## How – @TransactionalEventListener

```java
// Đảm bảo event chỉ xử lý sau khi transaction COMMIT thành công
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
@Async
public void sendOrderConfirmation(OrderPlacedEvent event) {
    // Chỉ gọi sau khi order đã commit vào DB
    // Nếu gọi @EventListener thông thường: event fire trước commit → email sent nhưng DB rollback!
    emailService.sendConfirmation(event.order());
}

@TransactionalEventListener(phase = TransactionPhase.AFTER_ROLLBACK)
public void handleFailedOrder(OrderPlacedEvent event) {
    alertService.notifyAdmin("Order failed: " + event.order().getId());
}

// Fallback nếu không có transaction active
@TransactionalEventListener(fallbackExecution = true)
public void alwaysHandle(SomeEvent event) { ... }
```

---

## How – Pitfalls & Anti-patterns

### 1. Self-invocation (AOP proxy problem)
```java
@Service
public class OrderService {
    @Transactional
    public void outer() {
        inner(); // KHÔNG có transaction mới dù inner() có @Transactional(REQUIRES_NEW)!
    }

    @Transactional(propagation = REQUIRES_NEW)
    public void inner() { ... } // self-invocation = bypass proxy!
}
```

### 2. Transaction không active vì method private
```java
@Transactional
private void doWork() { ... } // KHÔNG có effect! AOP không proxy private methods
```

### 3. Exception bị catch làm mất rollback
```java
@Transactional
public void badMethod() {
    try {
        riskyOperation(); // throw RuntimeException
    } catch (RuntimeException e) {
        log.error(e.getMessage()); // exception bị nuốt → KHÔNG rollback!
    }
}

// Fix: rethrow hoặc setRollbackOnly
@Transactional
public void goodMethod() {
    try {
        riskyOperation();
    } catch (RuntimeException e) {
        log.error(e.getMessage());
        throw e; // rethrow để trigger rollback
    }
}
```

### 4. @Transactional trên @Bean method trong @Configuration
```java
@Configuration
public class Config {
    @Bean
    @Transactional // KHÔNG có effect! Bean initialization không trong application context yet
    public SomeBean someBean() { return new SomeBean(); }
}
```

### 5. Long transaction với external calls
```java
@Transactional // TRÁNH: giữ DB connection/lock trong khi gọi HTTP!
public void badLongTransaction(Long orderId) {
    Order order = orderRepo.findById(orderId); // open transaction
    String result = httpClient.callExternalApi(); // có thể 5-10s!
    order.updateWith(result);
    orderRepo.save(order);                        // close transaction
}

// Fix: tách IO ra ngoài transaction
public void goodPattern(Long orderId) {
    String result = httpClient.callExternalApi(); // IO trước, không có transaction
    updateOrder(orderId, result);
}

@Transactional
private void updateOrder(Long orderId, String result) {
    Order order = orderRepo.findById(orderId);
    order.updateWith(result);
    orderRepo.save(order);
}
```

---

## Real-world Usage (Production)

### 1. Service Layer với Transaction Strategy
```java
@Service
@Transactional(readOnly = true)     // default read-only
public class OrderService {
    private final OrderRepository orderRepo;
    private final InventoryService inventoryService;
    private final ApplicationEventPublisher publisher;

    @Transactional                  // write operation
    public Order placeOrder(PlaceOrderCommand cmd) {
        Order order = Order.create(cmd);
        inventoryService.reserve(order.getItems()); // REQUIRED – trong cùng tx
        Order saved = orderRepo.save(order);
        publisher.publishEvent(new OrderPlacedEvent(saved)); // async sau commit
        return saved;
    }

    public Optional<Order> findById(Long id) { // readOnly inherited
        return orderRepo.findById(id);
    }

    public Page<OrderSummary> findByCustomer(Long customerId, Pageable page) {
        return orderRepo.findSummariesByCustomerId(customerId, page);
    }
}
```

### 2. CORS Configuration
```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
            .allowedOrigins("https://app.example.com")
            .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS")
            .allowedHeaders("*")
            .allowCredentials(true)
            .maxAge(3600);
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Hoàn thành Spring Framework.
> Tiếp theo: **Data Access** (JDBC → JPA/Hibernate → Spring Data JPA)
>
> Keyword JDBC: Connection, PreparedStatement (vs Statement – SQL injection), ResultSet, Connection Pool (HikariCP), JdbcTemplate
>
> Keyword JPA/Hibernate: Entity lifecycle (Transient→Persistent→Detached→Removed), EntityManager, persistence context (first-level cache), JPQL vs Criteria API, N+1 problem + fix (JOIN FETCH / @BatchSize / EntityGraph), lazy vs eager loading, @OneToMany/@ManyToMany mappings, Optimistic vs Pessimistic locking
