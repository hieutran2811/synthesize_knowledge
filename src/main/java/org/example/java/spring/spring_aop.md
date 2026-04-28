# Spring AOP (Aspect-Oriented Programming)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Spring AOP là gì?

**AOP (Aspect-Oriented Programming)** là paradigm tách **cross-cutting concerns** (logging, security, transaction, caching...) khỏi business logic chính.

**Cross-cutting concern**: logic không thuộc về một module cụ thể nhưng xuất hiện khắp mọi nơi.

```java
// KHÔNG có AOP – cross-cutting concerns rải khắp
@Service
public class OrderService {
    public Order placeOrder(Order order) {
        log.info("Placing order: {}", order.getId());           // logging
        securityService.checkPermission("PLACE_ORDER");         // security
        metricsService.startTimer("place_order");               // metrics
        try {
            Order result = doPlaceOrder(order);                 // business logic
            metricsService.stopTimer("place_order");
            log.info("Order placed: {}", result.getId());
            return result;
        } catch (Exception e) {
            metricsService.recordError("place_order");
            log.error("Failed to place order", e);
            throw e;
        }
    }
}

// VỚI AOP – business logic thuần túy
@Service
public class OrderService {
    @Logged      // AOP handle logging
    @Secured("PLACE_ORDER")  // AOP handle security
    @Timed("place_order")    // AOP handle metrics
    @Transactional           // AOP handle transaction
    public Order placeOrder(Order order) {
        return doPlaceOrder(order); // chỉ còn business logic
    }
}
```

---

## Components – Khái niệm AOP

| Term | Định nghĩa | Ví dụ |
|------|-----------|-------|
| **Aspect** | Module chứa cross-cutting concern | `LoggingAspect`, `SecurityAspect` |
| **Advice** | Hành động được thực thi | Log, check permission |
| **Pointcut** | Điều kiện: "áp dụng Advice ở đâu" | `execution(* com.example.service.*.*(..))` |
| **Join Point** | Điểm trong luồng thực thi | Method call, exception throw |
| **Target** | Object được áp dụng AOP | `OrderService` |
| **Proxy** | Object bao bọc Target | JDK Proxy hoặc CGLIB subclass |
| **Weaving** | Kết nối Aspect với Target | Spring: runtime weaving |

---

## How – Proxy-based AOP

Spring AOP dùng **proxy pattern** để intercept method calls:

```
Client → Proxy → Target.method()
              ↓
        [BeforeAdvice]
        [Target.method()]
        [AfterAdvice]
```

### JDK Dynamic Proxy vs CGLIB

```java
// JDK Dynamic Proxy: khi bean implement interface
@Service
public class UserServiceImpl implements UserService { ... }
// Spring tạo: Proxy.newProxyInstance(UserService.class) → implements same interface

// CGLIB: khi bean KHÔNG implement interface (hoặc Spring Boot default từ 2.x)
@Service
public class UserService { ... } // no interface
// Spring tạo subclass: class UserService$$EnhancerBySpringCGLIB extends UserService

// Kiểm tra
OrderService service = ctx.getBean(OrderService.class);
System.out.println(service.getClass()); // OrderService$$EnhancerBySpringCGLIB$$...
```

---

## How – @Aspect Syntax

### Khai báo Aspect
```java
@Aspect
@Component // phải là Spring bean
public class LoggingAspect {

    private static final Logger log = LoggerFactory.getLogger(LoggingAspect.class);

    // Pointcut expression – tái sử dụng
    @Pointcut("execution(* com.example.service.*.*(..))")
    public void serviceLayer() {} // method rỗng, chỉ là named pointcut

    @Pointcut("@annotation(com.example.annotation.Logged)")
    public void loggedAnnotation() {}
}
```

---

## How – Advice Types

### @Before – Chạy TRƯỚC method
```java
@Before("execution(* com.example.service.*.*(..))") // inline pointcut
public void logBefore(JoinPoint jp) {
    log.info("Calling: {}.{}({})",
        jp.getTarget().getClass().getSimpleName(),
        jp.getSignature().getName(),
        Arrays.toString(jp.getArgs()));
}
```

### @AfterReturning – Chạy SAU khi method trả về (không exception)
```java
@AfterReturning(
    pointcut = "execution(* com.example.service.*.*(..))",
    returning = "result"  // bind return value
)
public void logAfterReturning(JoinPoint jp, Object result) {
    log.info("Returned from {}: {}", jp.getSignature().getName(), result);
}
```

### @AfterThrowing – Chạy khi method throw exception
```java
@AfterThrowing(
    pointcut = "execution(* com.example.service.*.*(..))",
    throwing = "ex"   // bind exception
)
public void logException(JoinPoint jp, Exception ex) {
    log.error("Exception in {}: {}", jp.getSignature().getName(), ex.getMessage(), ex);
    alertService.sendAlert(jp.getSignature().getName(), ex);
}
```

### @After – Chạy SAU method (dù có exception hay không) = finally
```java
@After("serviceLayer()")
public void cleanup(JoinPoint jp) {
    MDC.clear(); // cleanup Mapped Diagnostic Context sau mỗi call
}
```

### @Around – Bao bọc hoàn toàn (mạnh nhất)
```java
@Around("@annotation(com.example.annotation.Timed)")
public Object measureTime(ProceedingJoinPoint pjp) throws Throwable {
    String methodName = pjp.getSignature().getName();
    Timer.Sample sample = Timer.start(meterRegistry);
    try {
        Object result = pjp.proceed(); // GỌI method thực sự – PHẢI gọi!
        sample.stop(meterRegistry.timer("method.duration",
            "method", methodName, "status", "success"));
        return result;
    } catch (Throwable t) {
        sample.stop(meterRegistry.timer("method.duration",
            "method", methodName, "status", "error"));
        throw t; // re-throw
    }
}

// @Around có thể:
// - Không gọi pjp.proceed() → block method hoàn toàn
// - Thay đổi arguments: pjp.proceed(newArgs)
// - Thay đổi return value: return modifiedResult
// - Retry: gọi pjp.proceed() nhiều lần
```

---

## How – Pointcut Expressions (AspectJ syntax)

### `execution` – khớp method signature
```java
// execution(modifier? returnType declaringType? methodName(params) throws?)

execution(* *(..))                          // mọi method
execution(public * *(..))                   // public methods
execution(* com.example..*.*(..))           // mọi method trong package và subpackage
execution(* com.example.service.*.*(..))    // service package
execution(* com.example.service.*Service.*(..)) // class tên kết thúc Service
execution(* com.example..*.get*(..))        // method bắt đầu get
execution(* com.example.*.*(String, ..))    // param đầu là String
execution(public void com.example.service.OrderService.placeOrder(Order)) // exact
```

### `@annotation` – khớp annotation
```java
@Pointcut("@annotation(org.springframework.transaction.annotation.Transactional)")
public void transactionalMethods() {}

// Với binding: lấy annotation instance
@Around("@annotation(cached)")
public Object handleCache(ProceedingJoinPoint pjp, Cacheable cached) throws Throwable {
    String key = cached.value();
    // ...
}
// @Cacheable trong method signature phải match tên parameter
```

### `within` – khớp class/package
```java
within(com.example.service.*)         // class trong package
within(com.example.service..*)        // bao gồm subpackage
@within(org.springframework.stereotype.Service) // class có @Service
```

### `bean` – khớp bean name (Spring-specific)
```java
bean(orderService)      // bean tên "orderService"
bean(*Service)          // bean tên kết thúc "Service"
bean(*Repository)       // bean tên kết thúc "Repository"
```

### Kết hợp expressions
```java
@Pointcut("execution(* com.example.service.*.*(..)) && !execution(* com.example.service.*.get*(..))")
public void serviceWriteOps() {} // write ops (không phải getters)

@Pointcut("within(com.example.service..*) || within(com.example.web..*)")
public void applicationLayer() {}
```

---

## How – Self-invocation Problem

**Vấn đề quan trọng nhất về Spring AOP:**

```java
@Service
public class OrderService {
    @Transactional
    public void placeOrder(Order order) {
        validateOrder(order);
        saveOrder(order);
    }

    @Transactional(propagation = REQUIRES_NEW)
    public void validateOrder(Order order) {
        // KHÔNG được wrap trong transaction mới!
        // Tại sao?
    }
}

// Khi gọi từ ngoài:
// Client → [Proxy] → OrderService.placeOrder()   ← PROXY intercepts
// Inside placeOrder(): this.validateOrder()       ← GỌI TRỰC TIẾP, KHÔNG QUA PROXY!
// → @Transactional của validateOrder bị bỏ qua!
```

```
Đúng:
Client → Proxy → Target.placeOrder() ← AOP works
Sai (self-invocation):
Target.placeOrder() → this.validateOrder() ← bypass proxy, AOP doesn't work!
```

**Fix:**
```java
// Fix 1: Inject self
@Service
public class OrderService {
    @Autowired
    private OrderService self; // inject proxy của chính mình

    public void placeOrder(Order order) {
        self.validateOrder(order); // gọi qua proxy → AOP hoạt động
    }

    @Transactional(propagation = REQUIRES_NEW)
    public void validateOrder(Order order) { ... }
}

// Fix 2: Extract sang service khác (design tốt hơn)
@Service
public class OrderValidationService {
    @Transactional(propagation = REQUIRES_NEW)
    public void validate(Order order) { ... }
}

@Service
public class OrderService {
    private final OrderValidationService validator;

    public void placeOrder(Order order) {
        validator.validate(order); // gọi qua proxy → AOP hoạt động
    }
}
```

---

## How – Custom Annotations với AOP

```java
// 1. Định nghĩa annotation
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RateLimit {
    int requestsPerMinute() default 60;
    String key() default ""; // SpEL expression
}

// 2. Tạo Aspect xử lý
@Aspect
@Component
public class RateLimitAspect {
    private final RateLimiterRegistry registry;

    @Around("@annotation(rateLimit)")
    public Object enforceRateLimit(ProceedingJoinPoint pjp, RateLimit rateLimit) throws Throwable {
        String key = resolveKey(rateLimit.key(), pjp);
        RateLimiter limiter = registry.rateLimiter(key,
            RateLimiterConfig.custom()
                .limitForPeriod(rateLimit.requestsPerMinute())
                .build());

        if (!limiter.acquirePermission()) {
            throw new TooManyRequestsException("Rate limit exceeded for: " + key);
        }
        return pjp.proceed();
    }
}

// 3. Dùng
@RateLimit(requestsPerMinute = 10, key = "#userId")
public void sendNotification(String userId, String message) { ... }
```

---

## How – Advice Ordering

Khi nhiều Aspects áp dụng cùng method:

```java
@Aspect @Order(1) // số nhỏ hơn = priority cao hơn (outer = first)
@Component
public class SecurityAspect { ... }

@Aspect @Order(2)
@Component
public class LoggingAspect { ... }

@Aspect @Order(3)
@Component
public class MetricsAspect { ... }

// Execution order:
// Before: Security(1) → Logging(2) → Metrics(3) → method
// After:  method → Metrics(3) → Logging(2) → Security(1)
```

---

## Why – Tại sao dùng AOP?

| Cross-cutting concern | Không AOP | Với AOP |
|----------------------|-----------|---------|
| Logging | Thêm log vào mọi method | @Logged annotation |
| Transaction | try-catch-commit/rollback mọi nơi | @Transactional |
| Security | if(!hasPermission) throw... mọi nơi | @PreAuthorize |
| Caching | Check cache, miss→load, put... mọi nơi | @Cacheable |
| Retry | while(retry) try... mọi nơi | @Retryable |
| Rate limiting | Check rate mọi nơi | @RateLimit |

---

## When – Khi nào dùng AOP?

**Nên dùng:**
- Logic lặp lại giữa nhiều class không liên quan (cross-cutting)
- Không muốn thay đổi business code để thêm concern
- Concern có thể bật/tắt qua config

**Không nên dùng:**
- Logic đặc thù cho 1 class (dùng method thông thường)
- Complex business rule (khó debug)
- Khi self-invocation là pattern phổ biến trong code

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Tách biệt concerns | Self-invocation problem |
| Code business logic sạch | Debug phức tạp (proxy layers) |
| Bật/tắt cross-cutting dễ | Stack trace dài với nhiều aspects |
| Không sửa code cũ | Chỉ work với Spring-managed beans |
| @Transactional, @Cacheable tích hợp sẵn | Không work với private/static method |

---

## Real-world Usage (Production)

### 1. Audit Logging
```java
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Audited {
    String action();
}

@Aspect @Component
public class AuditAspect {
    @AfterReturning("@annotation(audited)")
    public void audit(JoinPoint jp, Audited audited) {
        String userId = SecurityContextHolder.getContext().getAuthentication().getName();
        auditRepository.save(AuditLog.builder()
            .userId(userId)
            .action(audited.action())
            .method(jp.getSignature().toShortString())
            .args(serialize(jp.getArgs()))
            .timestamp(Instant.now())
            .build());
    }
}

@Service
public class UserService {
    @Audited(action = "DELETE_USER")
    public void deleteUser(Long id) { ... }

    @Audited(action = "UPDATE_ROLE")
    public void updateRole(Long id, String role) { ... }
}
```

### 2. Retry với Exponential Backoff
```java
@Aspect @Component
public class RetryAspect {
    @Around("@annotation(retryable)")
    public Object retry(ProceedingJoinPoint pjp, Retryable retryable) throws Throwable {
        int maxAttempts = retryable.maxAttempts();
        long delay = retryable.initialDelayMs();
        Throwable lastEx = null;

        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                return pjp.proceed();
            } catch (Exception e) {
                if (!isRetryable(e, retryable.retryOn())) throw e;
                lastEx = e;
                if (attempt < maxAttempts) {
                    log.warn("Attempt {}/{} failed, retrying in {}ms", attempt, maxAttempts, delay);
                    Thread.sleep(delay);
                    delay *= retryable.multiplier(); // exponential backoff
                }
            }
        }
        throw lastEx;
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Spring Boot** (auto-configuration, starters, properties, actuator)
>
> Keyword: @SpringBootApplication = @EnableAutoConfiguration + @ComponentScan + @Configuration, spring.factories / AutoConfiguration.imports (Spring Boot 3), @ConditionalOn*, @ConfigurationProperties, application.properties vs YAML, profiles, Spring Boot Actuator (health, metrics, info)
