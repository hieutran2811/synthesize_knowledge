# Spring Boot (Auto-configuration, Starters, Actuator)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Spring Boot là gì?

**Spring Boot** là opinionated framework xây dựng trên Spring, cung cấp:
1. **Auto-configuration**: tự động cấu hình dựa trên classpath
2. **Starter dependencies**: bundle dependencies phù hợp
3. **Embedded server**: Tomcat/Jetty/Undertow built-in (không cần WAR)
4. **Production-ready**: Actuator, metrics, health checks

```
Spring (Framework) + Convention over Configuration = Spring Boot
```

---

## How – @SpringBootApplication

```java
@SpringBootApplication
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}

// @SpringBootApplication = 3 annotations gộp lại:
@SpringBootConfiguration    // = @Configuration – class chứa @Bean
@EnableAutoConfiguration    // trigger auto-configuration
@ComponentScan              // scan package hiện tại và subpackages
```

---

## How – Auto-configuration (Cơ chế bên trong)

### Quá trình

```
1. Spring Boot khởi động
2. @EnableAutoConfiguration kích hoạt
3. Tìm file: META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
   (Spring Boot 3) hoặc META-INF/spring.factories (Spring Boot 2)
4. Load danh sách auto-configuration classes
5. Mỗi class được đánh giá bằng @Conditional*
6. Nếu điều kiện thỏa mãn → @Bean được đăng ký
```

### Ví dụ: DataSourceAutoConfiguration
```java
// Trong spring-boot-autoconfigure.jar
@AutoConfiguration
@ConditionalOnClass({ DataSource.class, EmbeddedDatabaseType.class })  // H2/HSQL/Derby có trên classpath
@ConditionalOnMissingBean(type = "io.r2dbc.spi.ConnectionFactory")
@EnableConfigurationProperties(DataSourceProperties.class)
public class DataSourceAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean   // chỉ tạo nếu bạn CHƯA định nghĩa DataSource
    @ConditionalOnSingleCandidate(DataSource.class)
    public DataSourceInitializerInvoker dataSourceInitializerInvoker(...) { ... }
}

// Ý nghĩa:
// - Nếu H2/HikariCP có trong classpath VÀ bạn chưa tạo DataSource → tự tạo DataSource
// - Bạn define @Bean DataSource → auto-config bị bypass (@ConditionalOnMissingBean)
```

### @Conditional* Annotations

| Annotation | Điều kiện |
|-----------|----------|
| `@ConditionalOnClass(Foo.class)` | Foo.class có trên classpath |
| `@ConditionalOnMissingClass` | Class KHÔNG có trên classpath |
| `@ConditionalOnBean` | Bean đã tồn tại |
| `@ConditionalOnMissingBean` | Bean CHƯA tồn tại (user chưa tự define) |
| `@ConditionalOnProperty("feature.x")` | Property được set |
| `@ConditionalOnWebApplication` | Là web application |
| `@ConditionalOnExpression("${...}")` | SpEL expression true |

---

## How – Starters

**Starter** = dependency POM kéo vào tất cả thư viện cần thiết + auto-configuration.

```xml
<!-- spring-boot-starter-web kéo vào: -->
<!-- Spring MVC + Tomcat + Jackson + Validation + Logging -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>

<!-- spring-boot-starter-data-jpa kéo vào: -->
<!-- Hibernate + Spring Data JPA + HikariCP + JDBC -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
```

### Common Starters

| Starter | Kéo vào |
|---------|--------|
| `spring-boot-starter` | Core + logging |
| `spring-boot-starter-web` | MVC + Tomcat + Jackson |
| `spring-boot-starter-webflux` | WebFlux + Netty |
| `spring-boot-starter-data-jpa` | JPA + Hibernate + HikariCP |
| `spring-boot-starter-security` | Spring Security |
| `spring-boot-starter-test` | JUnit 5 + Mockito + AssertJ |
| `spring-boot-starter-actuator` | Actuator endpoints |
| `spring-boot-starter-cache` | Spring Cache abstraction |

---

## How – Configuration Properties

### application.properties vs application.yml

```properties
# application.properties
server.port=8080
spring.datasource.url=jdbc:postgresql://localhost:5432/mydb
spring.datasource.username=myuser
spring.datasource.password=secret
spring.jpa.hibernate.ddl-auto=validate
spring.jpa.show-sql=false
logging.level.com.example=DEBUG
```

```yaml
# application.yml (hierarchical – dễ đọc hơn)
server:
  port: 8080

spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
    username: myuser
    password: secret
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: false

logging:
  level:
    com.example: DEBUG
```

### @ConfigurationProperties – Strongly typed config

```java
@ConfigurationProperties(prefix = "app.payment")
@Validated // trigger Bean Validation
public class PaymentProperties {
    @NotBlank private String apiKey;
    @NotBlank private String webhookSecret;
    @Min(1) @Max(10) private int maxRetries = 3;
    @DurationUnit(ChronoUnit.SECONDS) private Duration timeout = Duration.ofSeconds(30);
    private Map<String, String> endpoints = new HashMap<>();

    // getters/setters (hoặc dùng Record từ Spring Boot 3)
}

// Đăng ký
@SpringBootApplication
@EnableConfigurationProperties(PaymentProperties.class) // hoặc thêm @ConfigurationPropertiesScan
public class App {}

// Dùng
@Service
public class PaymentService {
    private final PaymentProperties props;

    public PaymentService(PaymentProperties props) { this.props = props; }

    public void charge(BigDecimal amount) {
        String url = props.getEndpoints().get("charge");
        int retries = props.getMaxRetries();
        // ...
    }
}
```

```yaml
# application.yml
app:
  payment:
    api-key: sk_live_xxx
    webhook-secret: whsec_xxx
    max-retries: 5
    timeout: 30s
    endpoints:
      charge: https://api.stripe.com/v1/charges
      refund: https://api.stripe.com/v1/refunds
```

---

## How – Profiles

```yaml
# application.yml (shared config)
app:
  name: MyApp

---
# Profile: development
spring:
  config:
    activate:
      on-profile: dev
  datasource:
    url: jdbc:h2:mem:testdb
  jpa:
    show-sql: true

---
# Profile: production
spring:
  config:
    activate:
      on-profile: prod
  datasource:
    url: jdbc:postgresql://${DB_HOST}:5432/mydb
    username: ${DB_USER}
    password: ${DB_PASSWORD}
```

```bash
# Activate profile
java -jar app.jar --spring.profiles.active=prod
# hoặc
SPRING_PROFILES_ACTIVE=prod java -jar app.jar
```

```java
// Profile-specific beans
@Configuration
@Profile("dev")
public class DevConfig {
    @Bean
    public DataSource devDataSource() { return new EmbeddedDatabaseBuilder().setType(H2).build(); }
}

// Multiple profiles
@Component
@Profile({"dev", "test"})
public class MockEmailService implements EmailService {
    public void send(Email email) { log.info("MOCK: {}", email); }
}
```

---

## How – Externalized Configuration (Priority Order)

Spring Boot đọc config theo thứ tự ưu tiên (cao nhất trước):

```
1. Command line args:          --server.port=9090
2. OS environment variables:   SERVER_PORT=9090
3. application-{profile}.properties (ngoài JAR)
4. application.properties (ngoài JAR)
5. application-{profile}.properties (trong JAR)
6. application.properties (trong JAR)
7. @PropertySource trong @Configuration
8. Default values
```

```bash
# Production: override config không cần rebuild JAR
java -jar app.jar \
  --spring.profiles.active=prod \
  --server.port=8443 \
  --spring.datasource.password=secret123
```

---

## How – Spring Boot Actuator

Endpoint cung cấp **production-ready** monitoring và management.

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,loggers,env,beans
  endpoint:
    health:
      show-details: when_authorized
```

### Built-in Endpoints

| Endpoint | URL | Mô tả |
|----------|-----|-------|
| `/actuator/health` | GET | Health status (UP/DOWN) |
| `/actuator/info` | GET | App info (version, git commit) |
| `/actuator/metrics` | GET | Micrometer metrics |
| `/actuator/loggers` | GET/POST | Log levels (có thể thay đổi runtime) |
| `/actuator/env` | GET | Environment properties |
| `/actuator/beans` | GET | Tất cả Spring beans |
| `/actuator/mappings` | GET | Tất cả URL mappings |
| `/actuator/threaddump` | GET | Thread dump |
| `/actuator/heapdump` | GET | Heap dump (download) |
| `/actuator/shutdown` | POST | Shutdown app (disabled by default) |

### Custom Health Indicator
```java
@Component
public class ExternalApiHealthIndicator implements HealthIndicator {
    private final ExternalApiClient client;

    @Override
    public Health health() {
        try {
            boolean alive = client.ping();
            return alive
                ? Health.up().withDetail("response", "OK").build()
                : Health.down().withDetail("response", "TIMEOUT").build();
        } catch (Exception e) {
            return Health.down(e).build();
        }
    }
}
```

### Custom Info Endpoint
```yaml
info:
  app:
    name: '@project.name@'
    version: '@project.version@'
    description: '@project.description@'
  git:
    commit: '@git.commit.id.abbrev@'
    branch: '@git.branch@'
```

```java
@Component
public class DatabaseInfoContributor implements InfoContributor {
    @Override
    public void contribute(Info.Builder builder) {
        builder.withDetail("database", Map.of(
            "type", "PostgreSQL",
            "version", jdbcTemplate.queryForObject("SELECT version()", String.class)
        ));
    }
}
```

---

## How – SpringApplication Customization

```java
@SpringBootApplication
public class App {
    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(App.class);

        // Banner
        app.setBannerMode(Banner.Mode.CONSOLE);

        // Listeners
        app.addListeners(new ApplicationPidFileWriter());

        // Fail fast on missing properties
        app.setDefaultProperties(Map.of("spring.main.fail-on-empty-description", "true"));

        ConfigurableApplicationContext ctx = app.run(args);
    }
}

// ApplicationRunner – chạy sau khi context khởi động
@Component
public class StartupRunner implements ApplicationRunner {
    @Override
    public void run(ApplicationArguments args) {
        log.info("Application started with args: {}", args.getOptionNames());
        dataInitializationService.initializeIfNeeded();
    }
}
```

---

## Why – Tại sao Spring Boot?

| Vấn đề Spring thuần | Spring Boot giải quyết |
|--------------------|----------------------|
| XML config dài dòng | Convention over configuration |
| Quản lý version dependencies phức tạp | BOM (Bill of Materials) |
| Deploy WAR lên app server | Embedded Tomcat, executable JAR |
| Setup DataSource, EntityManager... thủ công | Auto-configuration |
| Monitoring/health thủ công | Actuator |

---

## Compare – Spring Boot 2 vs 3

| | Spring Boot 2.x | Spring Boot 3.x |
|--|----------------|----------------|
| Java minimum | Java 8 | Java 17 |
| Spring Framework | 5.x | 6.x |
| Jakarta EE | javax.* | jakarta.* |
| Auto-config location | spring.factories | AutoConfiguration.imports |
| Native support | Experimental | GA (GraalVM) |
| Observability | Micrometer | Micrometer + OpenTelemetry |
| Virtual Threads | Không | Có (Java 21) |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Setup nhanh, ít config | "Magic" – khó hiểu khi sai |
| Embedded server – dễ deploy | JAR size lớn hơn |
| Auto-config chuẩn | Cần hiểu để customize đúng |
| Actuator out-of-the-box | Expose endpoints cần security |
| BOM quản lý versions | Ít control hơn full Spring |

---

## Real-world Usage (Production)

### 1. Graceful Shutdown
```yaml
server:
  shutdown: graceful  # default: immediate

spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s  # chờ requests hiện tại xong
```

### 2. Custom Starter (Library)
```java
// Tạo starter cho công ty
@AutoConfiguration
@ConditionalOnClass(AuditService.class)
@EnableConfigurationProperties(AuditProperties.class)
public class AuditAutoConfiguration {
    @Bean
    @ConditionalOnMissingBean
    public AuditService auditService(AuditProperties props) {
        return new DefaultAuditService(props);
    }
}

// META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports:
// com.company.audit.AuditAutoConfiguration
```

### 3. Build Info trong CI/CD
```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
            <executions>
                <execution>
                    <goals><goal>build-info</goal></goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```
→ `/actuator/info` tự động có `build.version`, `build.time`, `build.artifact`

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Spring MVC & Spring Transaction**
>
> Keyword Spring MVC: DispatcherServlet request flow, HandlerMapping, HandlerAdapter, @RequestMapping variants, @PathVariable/@RequestParam/@RequestBody, @ResponseBody, ResponseEntity, @ControllerAdvice, Filter vs Interceptor vs AOP, HttpMessageConverter, Content Negotiation
>
> Keyword Transaction: @Transactional propagation (REQUIRED/REQUIRES_NEW/NESTED/SUPPORTS...), isolation levels (READ_UNCOMMITTED → SERIALIZABLE), rollback rules (rollbackFor/noRollbackFor), readOnly optimization, distributed transaction (2PC), @TransactionalEventListener
