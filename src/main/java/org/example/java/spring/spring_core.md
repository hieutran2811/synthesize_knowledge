# Spring Core – IoC & Dependency Injection

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Spring Core là gì?

**Spring Core** là nền tảng của toàn bộ Spring Framework, xoay quanh 2 khái niệm:

- **IoC (Inversion of Control)**: đảo ngược quyền kiểm soát — thay vì code tạo dependency, **container** tạo và inject
- **DI (Dependency Injection)**: cách cụ thể để thực hiện IoC — inject dependency qua constructor/setter/field

```java
// Không có IoC: code tự tạo dependency (tight coupling)
public class OrderService {
    private OrderRepository repo = new JpaOrderRepository(); // hard-coded!
    private EmailService email   = new SmtpEmailService();   // hard-coded!
}

// Với IoC/DI: Spring inject dependency
@Service
public class OrderService {
    private final OrderRepository repo;
    private final EmailService email;

    @Autowired // Spring inject
    public OrderService(OrderRepository repo, EmailService email) {
        this.repo = repo;
        this.email = email;
    }
}
```

---

## How – IoC Container

### ApplicationContext vs BeanFactory

```
BeanFactory (interface)
  └── ApplicationContext (interface, extends BeanFactory)
        ├── AnnotationConfigApplicationContext  ← Java config (hiện đại)
        ├── ClassPathXmlApplicationContext      ← XML config (cũ)
        └── WebApplicationContext               ← Web apps
              └── AnnotationConfigWebApplicationContext
```

```java
// Standalone (non-Spring Boot)
ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
OrderService service = ctx.getBean(OrderService.class);
OrderService service2 = ctx.getBean("orderService", OrderService.class);

// Spring Boot: tự tạo ApplicationContext
@SpringBootApplication
public class App { public static void main(String[] args) { SpringApplication.run(App.class, args); } }
```

| | `BeanFactory` | `ApplicationContext` |
|--|--------------|---------------------|
| Lazy loading | Có (default) | Eager (singleton beans) |
| Event publishing | Không | Có |
| i18n | Không | Có |
| AOP | Giới hạn | Đầy đủ |
| Spring Boot dùng | Không | Có |

---

## How – Bean Lifecycle

```
1. Instantiation       → Spring tạo object (constructor)
2. Property Population → Inject dependencies (@Autowired fields/setters)
3. Aware Callbacks     → setBeanName(), setApplicationContext()...
4. BeanPostProcessor   → postProcessBeforeInitialization()
5. Init Methods        → @PostConstruct, afterPropertiesSet(), init-method
6. BeanPostProcessor   → postProcessAfterInitialization()  ← AOP proxy tạo ở đây!
7. Ready to Use        → Bean sẵn sàng
8. Destroy Methods     → @PreDestroy, destroy(), destroy-method (khi container đóng)
```

```java
@Component
public class DatabaseConnectionPool implements InitializingBean, DisposableBean {
    private DataSource dataSource;

    // Step 2: field injection (hoặc constructor)
    @Autowired
    public void setDataSource(DataSource ds) { this.dataSource = ds; }

    // Step 3: Aware
    @Override
    public void setBeanName(String name) { log.info("Bean name: {}", name); }

    // Step 5: @PostConstruct (preferred)
    @PostConstruct
    public void init() {
        log.info("Initializing connection pool");
        pool.initialize();
    }

    // Alternative step 5: afterPropertiesSet (InitializingBean)
    @Override
    public void afterPropertiesSet() { /* same as @PostConstruct */ }

    // Step 8: @PreDestroy (preferred)
    @PreDestroy
    public void shutdown() {
        log.info("Closing connection pool");
        pool.close();
    }
}
```

---

## How – Bean Definition (3 cách)

### Cách 1: @Component Scan (hiện đại, phổ biến nhất)
```java
@Component          // generic component
@Service            // service layer (semantic)
@Repository         // data access layer (+ exception translation)
@Controller         // MVC controller
@RestController     // REST controller (@Controller + @ResponseBody)
@Configuration      // configuration class

// Spring Boot: @SpringBootApplication tự scan package hiện tại
@Service
public class UserService { ... }

@Repository
public class UserRepository { ... }
```

### Cách 2: @Bean trong @Configuration (explicit, full control)
```java
@Configuration
public class AppConfig {

    @Bean // method name = bean name
    public ObjectMapper objectMapper() {
        return new ObjectMapper()
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false)
            .registerModule(new JavaTimeModule());
    }

    @Bean("primaryDataSource") // custom name
    @Primary // ưu tiên khi có nhiều DataSource
    public DataSource dataSource(DataSourceProperties props) {
        return props.initializeDataSourceBuilder().build();
    }

    @Bean
    @Profile("test") // chỉ tạo khi profile = test
    public DataSource h2DataSource() {
        return new EmbeddedDatabaseBuilder().setType(H2).build();
    }
}
```

### Cách 3: XML (legacy, ít dùng)
```xml
<bean id="userService" class="com.example.UserServiceImpl">
    <constructor-arg ref="userRepository"/>
</bean>
```

---

## How – Bean Scopes

| Scope | Mô tả | Dùng khi |
|-------|-------|---------|
| `singleton` | 1 instance/ApplicationContext (default) | Stateless services, repositories |
| `prototype` | 1 instance mới mỗi lần `getBean()` | Stateful objects, cần isolate |
| `request` | 1 instance/HTTP request (web only) | Request-scoped data |
| `session` | 1 instance/HTTP session (web only) | User session data |
| `application` | 1 instance/ServletContext | App-level shared data |

```java
@Component
@Scope("prototype")
public class ReportBuilder { /* stateful, mỗi lần inject = instance mới */ }

@Component
@RequestScope
public class RequestContext {
    private String requestId = UUID.randomUUID().toString();
}

// Inject prototype vào singleton: cần proxy!
@Component
public class ReportService {
    @Autowired
    @Lazy // hoặc dùng ObjectProvider
    private ReportBuilder builder; // SẼ KHÔNG HOẠT ĐỘNG ĐÚNG (singleton inject prototype)

    // Đúng cách 1: @Scope với proxyMode
    // @Scope(value="prototype", proxyMode=ScopedProxyMode.TARGET_CLASS)
    // Đúng cách 2: ApplicationContext.getBean()
    // Đúng cách 3: ObjectProvider
}

@Component
@Scope(value = ConfigurableBeanFactory.SCOPE_PROTOTYPE, proxyMode = ScopedProxyMode.TARGET_CLASS)
public class ReportBuilder { ... }
```

---

## How – Dependency Injection (3 loại)

### Constructor Injection (Recommended)
```java
@Service
public class OrderService {
    private final OrderRepository repo;     // final!
    private final PaymentService payment;
    private final NotificationService notifier;

    // @Autowired có thể bỏ qua nếu chỉ có 1 constructor (Spring 4.3+)
    public OrderService(OrderRepository repo, PaymentService payment,
                        NotificationService notifier) {
        this.repo = repo;
        this.payment = payment;
        this.notifier = notifier;
    }
}
```

**Ưu điểm:**
- Fields là `final` → immutable → thread-safe
- Dễ test (tạo object thủ công, không cần Spring)
- Circular dependency bị phát hiện ngay khi start
- Explicit dependencies (không ẩn)

### Setter Injection (Optional dependencies)
```java
@Service
public class ReportService {
    private EmailSender emailSender;

    @Autowired(required = false) // optional
    public void setEmailSender(EmailSender sender) {
        this.emailSender = sender;
    }
}
```

### Field Injection (Không khuyến nghị)
```java
@Service
public class BadService {
    @Autowired
    private UserRepository repo; // Anti-pattern!
    // - Không test được không có Spring
    // - Không final
    // - Che giấu dependency
    // - Circular dependency khó phát hiện
}
```

---

## How – @Autowired Resolution

Khi Spring inject, tìm bean theo thứ tự:
```
1. By Type      → tìm bean có type khớp
2. By Qualifier → nếu nhiều bean cùng type, dùng @Qualifier("name")
3. By Name      → nếu không có @Qualifier, match tên parameter/field với bean name
```

```java
// Nhiều bean cùng type
@Bean public PaymentGateway stripeGateway() { return new StripeGateway(); }
@Bean public PaymentGateway paypalGateway() { return new PayPalGateway(); }

// Inject đúng bean
@Autowired
@Qualifier("stripeGateway")
private PaymentGateway gateway;

// @Primary: bean mặc định khi không có @Qualifier
@Bean @Primary
public PaymentGateway defaultGateway() { return new StripeGateway(); }

// Inject tất cả implementations
@Autowired
private List<PaymentGateway> allGateways; // inject cả Stripe và PayPal

@Autowired
private Map<String, PaymentGateway> gatewayMap; // key = bean name
```

---

## How – @Conditional & @Profile

```java
// @Profile: bean chỉ active khi profile match
@Bean @Profile("production")
public DataSource prodDataSource() { return hikariDataSource(); }

@Bean @Profile("test")
public DataSource testDataSource() { return h2DataSource(); }

// Activate: spring.profiles.active=production
// hoặc: SpringApplication.run(App.class, "--spring.profiles.active=production")

// @ConditionalOnProperty
@Bean
@ConditionalOnProperty(name = "feature.email.enabled", havingValue = "true")
public EmailService emailService() { return new SmtpEmailService(); }

// @ConditionalOnMissingBean
@Bean
@ConditionalOnMissingBean(EmailService.class)
public EmailService defaultEmailService() { return new NoOpEmailService(); }

// Custom Condition
public class OnLinuxCondition implements Condition {
    @Override
    public boolean matches(ConditionContext ctx, AnnotatedTypeMetadata metadata) {
        return ctx.getEnvironment().getProperty("os.name", "").contains("Linux");
    }
}

@Bean
@Conditional(OnLinuxCondition.class)
public FileWatcher fileWatcher() { return new InotifyFileWatcher(); }
```

---

## How – Circular Dependency

```java
// A cần B, B cần A → circular!
@Service class A {
    @Autowired B b; // Spring không thể tạo A trước khi B sẵn sàng
}
@Service class B {
    @Autowired A a;
}
// Spring Boot 2.6+: ném BeanCurrentlyInCreationException (mặc định)

// Fix 1: @Lazy (inject proxy, tạo lazy)
@Service class A {
    @Autowired @Lazy B b;
}

// Fix 2: Setter injection (Spring tạo A trước, sau đó inject B qua setter)
@Service class A {
    private B b;
    @Autowired public void setB(B b) { this.b = b; }
}

// Fix 3 (tốt nhất): Refactor – circular dependency là design smell
// Extract common logic vào service C
@Service class C { /* shared logic */ }
@Service class A { @Autowired C c; }
@Service class B { @Autowired C c; }
```

---

## How – ApplicationEvent (Observer Pattern)

```java
// Custom event
public record UserCreatedEvent(User user) {}

// Publisher
@Service
public class UserService {
    private final ApplicationEventPublisher publisher;

    public User createUser(CreateUserRequest req) {
        User user = userRepo.save(User.create(req));
        publisher.publishEvent(new UserCreatedEvent(user));
        return user;
    }
}

// Listener
@Component
public class UserEventListener {
    @EventListener
    public void handleUserCreated(UserCreatedEvent event) {
        emailService.sendWelcome(event.user().getEmail());
    }

    @EventListener
    @Async // xử lý bất đồng bộ
    public void logUserCreated(UserCreatedEvent event) {
        auditService.log("USER_CREATED", event.user().getId());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void syncToSearchIndex(UserCreatedEvent event) {
        searchIndexer.index(event.user()); // chỉ chạy sau khi transaction commit thành công
    }
}
```

---

## Why – Tại sao IoC/DI quan trọng?

| Bài toán | IoC/DI giải quyết |
|---------|-----------------|
| Tight coupling | Loose coupling qua interfaces |
| Hard-coded dependency | Swap implementation qua config |
| Khó test | Mock/stub dễ qua constructor injection |
| Lifecycle management | Spring quản lý @PostConstruct, @PreDestroy |
| Cross-cutting concerns | AOP dễ dàng (xem Spring AOP) |

---

## Compare – Spring IoC vs Manual DI vs Service Locator

| | Manual DI | Service Locator | Spring IoC |
|--|-----------|----------------|-----------|
| Coupling | Lỏng | Chặt (dep on locator) | Lỏng nhất |
| Testability | Tốt | Kém | Tốt nhất |
| Transparency | Rõ | Ẩn | Rõ (constructor) |
| Framework dep | Không | Có | Có (Spring) |
| Boilerplate | Nhiều (wiring manual) | Ít | Ít (annotation) |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Loose coupling | Magic/ẩn: khó trace luồng |
| Dễ test | Runtime error (missing bean) thay vì compile error |
| Bean lifecycle quản lý | ApplicationContext startup time |
| Declarative config | Over-engineering cho app nhỏ |

---

## Real-world Usage (Production)

### 1. Multi-datasource Configuration
```java
@Configuration
public class DataSourceConfig {
    @Bean @Primary
    @ConfigurationProperties("spring.datasource.primary")
    public DataSource primaryDataSource() {
        return DataSourceBuilder.create().build();
    }

    @Bean
    @ConfigurationProperties("spring.datasource.replica")
    public DataSource replicaDataSource() {
        return DataSourceBuilder.create().build();
    }
}

@Repository
public class UserRepository {
    private final JdbcTemplate primary;
    private final JdbcTemplate replica;

    public UserRepository(
        @Qualifier("primaryDataSource") DataSource primary,
        @Qualifier("replicaDataSource") DataSource replica) {
        this.primary = new JdbcTemplate(primary);
        this.replica = new JdbcTemplate(replica);
    }

    public void save(User user) { primary.update(INSERT_SQL, ...); }
    public Optional<User> findById(Long id) { return replica.query(SELECT_SQL, ...); }
}
```

### 2. Feature Toggle với @ConditionalOnProperty
```java
@ConditionalOnProperty("feature.new-pricing.enabled")
@Service @Primary
public class NewPricingService implements PricingService { ... }

@Service // fallback khi feature disabled
public class LegacyPricingService implements PricingService { ... }
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Spring AOP**
>
> Keyword: Aspect, Joinpoint, Pointcut, Advice (Before/After/Around/AfterReturning/AfterThrowing), JDK Dynamic Proxy vs CGLIB, @Aspect, AspectJ pointcut expressions (execution, @annotation, within, bean), self-invocation problem, @Transactional là AOP proxy
