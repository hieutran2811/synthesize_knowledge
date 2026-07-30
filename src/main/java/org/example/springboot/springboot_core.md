# Spring Boot Core *(phần lõi)* & Internals *(cơ chế bên trong)*

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Production – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)

---

## What – Spring Boot Core là gì?

**Spring Boot** là lớp công cụ có chủ kiến *(opinionated framework — framework cung cấp mặc định hợp lý)* xây trên Spring Framework. Nó ghép dependency *(thư viện phụ thuộc)*, **auto-configuration** *(tự động cấu hình theo classpath — tập class/library ứng dụng có thể nạp — và cấu hình ứng dụng)*, embedded server *(máy chủ nhúng)* và công cụ production để ứng dụng khởi động với ít cấu hình thủ công hơn.

Spring Boot không “viết thay” Spring. `ApplicationContext`, bean *(object do Spring quản lý)*, dependency injection *(tiêm phụ thuộc)*, AOP *(proxy áp dụng logic cắt ngang)* và transaction *(giao dịch nguyên tử)* vẫn là cơ chế của Spring Framework; Boot chủ yếu chọn mặc định và lùi lại *(back off)* khi ứng dụng khai báo bean riêng.

> 💡 **Giải thích dễ hiểu — Spring Boot là căn bếp đã chuẩn bị sẵn:**
> Spring Framework cung cấp bếp, nồi và nguyên liệu; Spring Boot sắp sẵn một bộ dụng cụ phù hợp với món bạn định nấu. Bạn vẫn có thể thay dụng cụ, nhưng không phải lắp cả căn bếp từ đầu.

## Why – Tại sao cần Spring Boot?

- Giảm cấu hình lặp lại nhờ starter *(gói dependency và mặc định theo chức năng)* và auto-configuration.
- Chuẩn hóa externalized configuration *(cấu hình tách khỏi mã nguồn)* theo môi trường.
- Có sẵn vòng đời, health/readiness *(sức khỏe/sẵn sàng nhận traffic)*, metrics *(số liệu đo lường)* và packaging *(đóng gói)* phục vụ vận hành.
- Vẫn cho phép override bean, condition hoặc loại bỏ auto-configuration khi mặc định không phù hợp.

Lợi ích lớn nhất là tốc độ và tính nhất quán giữa nhiều service, không phải “zero configuration”. Đội ngũ vẫn phải hiểu bean nào được tạo, property nào thắng và side effect nào cần transaction/outbox.

## Components – Bản đồ các cơ chế cốt lõi

| Cơ chế | Vai trò |
|---|---|
| Auto-configuration | Tạo bean theo condition *(điều kiện)* từ classpath, property và bean hiện có |
| Starter | Gom dependency tương thích cho một nhóm chức năng |
| `@ConfigurationProperties` | Bind cấu hình có kiểu, phân cấp và validation |
| Profiles *(hồ sơ cấu hình)* / Config Data *(cơ chế nạp dữ liệu cấu hình)* | Chọn biến thể cấu hình theo môi trường |
| Application lifecycle *(vòng đời ứng dụng)* | Phát event và runner trong quá trình khởi động/tắt |
| `Environment` / `PropertySource` *(nguồn property)* | Hợp nhất và phân thứ tự các nguồn cấu hình |
| Task execution *(thực thi tác vụ)* | Chạy `@Async`, executor và `CompletableFuture` |

> 💡 **Giải thích dễ hiểu — đây là bảng điện của một tòa nhà:**
> Starter mang thiết bị vào, auto-configuration tự nối dây khi đủ điều kiện, property là các công tắc, còn lifecycle cho biết lúc nào tòa nhà đã có điện và sẵn sàng đón người.

---

## How – 1. Auto-configuration Deep Dive

### 1.1 SPI Mechanism *(cơ chế phát hiện extension)* (Spring Boot 3/4)

```
Auto-configuration discovery flow:

1. Application starts with spring-boot-autoconfigure on the classpath
2. @SpringBootApplication → @EnableAutoConfiguration → AutoConfigurationImportSelector
3. Reads: META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
4. Each listed class = candidate auto-configuration
5. Spring orders candidates, then evaluates @Conditional* annotations
6. Passing candidates → their @Bean methods → registered in ApplicationContext
```

```text
# META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
# Spring Boot 3/4 format
# Các FQCN dưới đây là ví dụ dòng Boot 3; Boot 4 có thể đổi module/package.
org.springframework.boot.autoconfigure.data.redis.RedisAutoConfiguration
org.springframework.boot.autoconfigure.data.jpa.JpaRepositoriesAutoConfiguration
org.springframework.boot.autoconfigure.web.servlet.WebMvcAutoConfiguration
# ... danh sách thay đổi theo Spring Boot version/module

# Spring Boot 2 legacy used spring.factories for EnableAutoConfiguration:
# org.springframework.boot.autoconfigure.EnableAutoConfiguration=\
#   com.example.MyAutoConfiguration
```

Thứ tự auto-configuration chỉ quyết định lúc bean definition *(định nghĩa bean)* được đăng ký; thời điểm bean thực sự được tạo còn phụ thuộc dependency và `@DependsOn`. Với starter hiện đại, chỉ liệt kê top-level auto-configuration trong `AutoConfiguration.imports`; không dùng component scan để “quét rộng” package của thư viện. Khi nâng Spring Boot major, lấy FQCN từ artifact/version thực tế vì Boot 4 đã modular hóa và di chuyển một số package auto-configuration.

> 💡 **Giải thích dễ hiểu — auto-configuration giống nhân viên kiểm kê trước khi mở cửa:**
> Có driver database trên kệ, có URL cấu hình và chưa ai tự lắp `DataSource` thì Boot lắp bộ mặc định. Nếu ứng dụng đã đặt một bộ riêng, điều kiện `@ConditionalOnMissingBean` khiến Boot lùi lại.

### 1.2 @Conditional Chain

```java
// Tất cả @Conditional* annotations trong Spring Boot:

// Classpath conditions
@ConditionalOnClass(DataSource.class)         // DataSource present on classpath
@ConditionalOnMissingClass("com.some.Class")  // class NOT present

// Bean conditions (evaluation order matters: dựa trên definitions đã xử lý)
@ConditionalOnBean(DataSource.class)          // DataSource bean exists
@ConditionalOnMissingBean(CacheManager.class) // no CacheManager bean yet

// Property conditions
@ConditionalOnProperty(name = "my.feature.enabled", havingValue = "true", matchIfMissing = false)
@ConditionalOnProperty(name = "spring.datasource.url")  // property exists

// Resource conditions
@ConditionalOnResource(resources = "classpath:my-config.xml")

// Web conditions
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.SERVLET)
@ConditionalOnWebApplication(type = ConditionalOnWebApplication.Type.REACTIVE)
@ConditionalOnNotWebApplication

// Expression conditions
@ConditionalOnExpression("${feature.a.enabled:false} && ${feature.b.enabled:false}")

// Custom condition
@Conditional(MyCustomCondition.class)

// Example: Full auto-config class
@AutoConfiguration(after = DataSourceAutoConfiguration.class)  // ordering!
@ConditionalOnClass(JpaRepository.class)
@ConditionalOnBean(DataSource.class)
@ConditionalOnMissingBean({JpaRepositoryFactoryBean.class, JpaRepositoryConfigExtension.class})
@EnableConfigurationProperties(JpaProperties.class)
public class JpaRepositoriesAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean
    public EntityManagerFactoryBuilder entityManagerFactoryBuilder(
            JpaVendorAdapter jpaVendorAdapter,
            ObjectProvider<PersistenceUnitManager> persistenceUnitManager,
            ObjectProvider<EntityManagerFactoryBuilderCustomizer> customizers) {
        // ...
    }
}
```

Condition là cổng kiểm tra, không phải guarantee rằng dependency bên ngoài đang hoạt động. `@ConditionalOnClass` chỉ thấy class trên classpath; nó không kiểm tra database có kết nối được hay credential có đúng.

### 1.3 Debugging Auto-configuration

```bash
# Run with --debug flag to see auto-config report
java -jar app.jar --debug

# Or in application.properties:
debug=true

# Output: AUTO-CONFIGURATION REPORT
# Positive matches (applied):
#   DataSourceAutoConfiguration matched:
#     - @ConditionalOnClass found required classes 'javax.sql.DataSource'
# Negative matches (not applied):
#   MongoAutoConfiguration:
#     Did not match: @ConditionalOnClass did not find required class 'com.mongodb.MongoClient'
```

```java
// Programmatic check
@Component
public class AutoConfigDebugger implements CommandLineRunner {
    @Autowired
    private ApplicationContext context;

    @Override
    public void run(String... args) {
        Arrays.stream(context.getBeanDefinitionNames())
            .filter(name -> name.contains("AutoConfiguration"))
            .forEach(System.out::println);
    }
}
```

Ngoài `--debug`, có thể dùng Actuator endpoint `conditions` trong môi trường được bảo vệ. Không expose rộng endpoint chẩn đoán vì report có thể tiết lộ class, property và cấu trúc nội bộ.

---

## How/Components – 2. Custom Starter *(gói dependency và auto-configuration tái sử dụng)*

### 2.1 Starter Structure

```
my-spring-boot-starter/
├── my-autoconfigure/                    ← auto-configuration module
│   ├── pom.xml
│   └── src/main/java/com/example/
│       ├── MyServiceProperties.java
│       ├── MyService.java
│       └── MyAutoConfiguration.java
│   └── src/main/resources/
│       └── META-INF/spring/
│           └── org.springframework.boot.autoconfigure.AutoConfiguration.imports
└── my-spring-boot-starter/             ← starter module (just pom.xml with deps)
    └── pom.xml
```

```xml
<!-- my-spring-boot-starter/pom.xml -->
<dependencies>
    <!-- Only dependency management - no code -->
    <dependency>
        <groupId>com.example</groupId>
        <artifactId>my-autoconfigure</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter</artifactId>
    </dependency>
</dependencies>
```

```java
// MyServiceProperties.java - type-safe config
@ConfigurationProperties(prefix = "my.service")
@Validated  // enable Jakarta Bean Validation (cần validation provider trên classpath)
public class MyServiceProperties {

    @NotBlank
    private String apiUrl;

    @Min(1) @Max(100)
    private int maxRetries = 3;

    @DurationUnit(ChronoUnit.MILLIS)
    private Duration timeout = Duration.ofSeconds(30);

    @NestedConfigurationProperty
    private ConnectionPool pool = new ConnectionPool();

    @Getter @Setter
    public static class ConnectionPool {
        private int maxSize = 10;
        private int minIdle = 2;
    }

    // getters/setters (or use @Data with Lombok)
}

// MyService.java
public class MyService {
    private final MyServiceProperties properties;

    public MyService(MyServiceProperties properties) {
        this.properties = properties;
    }

    public String call(String endpoint) {
        // use properties.getApiUrl(), properties.getTimeout(), etc.
        return "result";
    }
}

// MyAutoConfiguration.java
@AutoConfiguration
@ConditionalOnProperty(prefix = "my.service", name = "enabled", matchIfMissing = true)
@EnableConfigurationProperties(MyServiceProperties.class)
public class MyAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean  // let user override
    public MyService myService(MyServiceProperties properties) {
        return new MyService(properties);
    }

    // Isolate optional types in a nested configuration so the JVM does not
    // resolve MeterRegistry when Micrometer is absent.
    @Configuration(proxyBeanMethods = false)
    @ConditionalOnClass(MeterRegistry.class)
    static class MetricsConfiguration {
        @Bean
        @ConditionalOnBean(MyService.class)
        MyServiceMetrics myServiceMetrics(MyService service, MeterRegistry registry) {
            return new MyServiceMetrics(service, registry);
        }
    }
}
```

Hai module không phải yêu cầu bắt buộc. Tách `autoconfigure` và `starter` hữu ích khi thư viện có dependency tùy chọn; starter đơn giản có thể gộp một module. Dùng namespace property do tổ chức sở hữu, tránh chiếm `spring.*`, `server.*` hoặc `management.*`.

`@ConditionalOnMissingBean` tạo extension point *(điểm cho ứng dụng thay thế mặc định)*. Auto-configuration nên khai báo bean rõ ràng và dùng `@Import`, không component-scan package tùy ý vì có thể kéo vào bean ngoài ý muốn.

Không đặt `@ConditionalOnClass(MyService.class)` nếu `MyService` nằm ngay trong cùng artifact và luôn có mặt; condition nên kiểm tra dependency tùy chọn thật sự. Khi method signature tham chiếu class tùy chọn, cô lập nó trong nested configuration có condition để tránh lỗi class loading.

> 💡 **Giải thích dễ hiểu — starter là một bộ kit có hướng dẫn lắp:**
> POM mang đúng linh kiện vào; auto-configuration chỉ lắp linh kiện khi đủ điều kiện. Ứng dụng có thể thay một linh kiện bằng bản riêng mà không phải tháo toàn bộ bộ kit.

```
# META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
com.example.MyAutoConfiguration
```

```java
// META-INF/spring-configuration-metadata.json (generate with spring-boot-configuration-processor)
// Add to pom.xml:
// <dependency>
//   <groupId>org.springframework.boot</groupId>
//   <artifactId>spring-boot-configuration-processor</artifactId>
//   <optional>true</optional>
// </dependency>
// → generates hints for IDE autocomplete on application.properties
```

Nên kiểm thử starter bằng `ApplicationContextRunner` với nhiều tổ hợp classpath/property/user bean. Một test “context starts” duy nhất không chứng minh các nhánh condition và cơ chế back-off hoạt động đúng.

---

## How – 3. `@ConfigurationProperties` Deep

`@ConfigurationProperties` bind *(ánh xạ)* một nhóm property từ `Environment` vào object Java có kiểu. Nó phù hợp cho cấu hình phân cấp và giúp lỗi kiểu/validation xuất hiện sớm khi khởi động.

### 3.1 Type-safe Binding

```java
@ConfigurationProperties(prefix = "app")
@Validated
public class AppProperties {

    // Relaxed binding in files: app.api-url / app.apiUrl / app.api_url
    // Canonical env-var form: APP_APIURL (replace "." with "_", remove "-", uppercase)
    private String apiUrl;

    // Lists
    private List<String> allowedOrigins = new ArrayList<>();

    // Maps
    private Map<String, String> headers = new HashMap<>();

    // Nested
    @NestedConfigurationProperty
    private Security security = new Security();

    // Duration (with unit suffix: 30s, 5m, 2h)
    private Duration sessionTimeout = Duration.ofMinutes(30);

    // DataSize (with unit: 10MB, 1GB)
    private DataSize maxFileSize = DataSize.ofMegabytes(10);

    @Getter @Setter
    public static class Security {
        private String secret;

        @DurationUnit(ChronoUnit.HOURS)
        private Duration jwtExpiry = Duration.ofHours(24);
    }
}

// application.yml
// app:
//   api-url: https://api.example.com
//   allowed-origins:
//     - https://frontend.example.com
//     - https://admin.example.com
//   headers:
//     X-Api-Version: "2"
//   session-timeout: 45m
//   max-file-size: 50MB
//   security:
//     secret: ${APP_SECRET}
//     jwt-expiry: 12h
```

Không đặt secret mặc định trong class hoặc metadata. `@Validated` chỉ fail fast khi có Jakarta Validation provider và constraint phù hợp; giá trị default trong field/constructor không tự xuất hiện thành property trong `Environment`.

> 💡 **Giải thích dễ hiểu — `@ConfigurationProperties` là tờ khai có khuôn:**
> Thay vì phát từng mảnh giấy `@Value` cho nhiều field, ta có một biểu mẫu biết trường nào là thời lượng, dung lượng hay danh sách. Điền sai `45x` vào ô thời lượng thì ứng dụng báo ngay lúc mở cửa.

### 3.2 @Value vs @ConfigurationProperties

```java
// @Value: simple, per-property injection
@Value("${app.api-url}")
private String apiUrl;

@Value("${app.max-retries:3}")  // default value
private int maxRetries;

@Value("#{${app.headers}}")    // chỉ phù hợp nếu value có cú pháp SpEL map tương ứng
private Map<String, String> headers;

// @Value có thể dùng trên field/constructor/method parameter, kể cả @Bean parameter.
// Hạn chế chính: cấu hình rải rác, metadata/validation kém hơn và SpEL dễ làm phức tạp.

// @ConfigurationProperties: recommended for groups of related properties
// ✓ Type-safe
// ✓ Hierarchical / nested
// ✓ Validation support
// ✓ IDE autocomplete
// ✓ Relaxed binding
// ✓ Can use Duration, DataSize, Period types
// ✓ Works in @Bean methods
```

### Compare – `@Value` và `@ConfigurationProperties`

| Tiêu chí | `@Value` | `@ConfigurationProperties` |
|---|---|---|
| Phạm vi | Một vài giá trị đơn lẻ | Một nhóm cấu hình có cấu trúc |
| Binding | Placeholder, có thể dùng SpEL | Relaxed binding, list/map/nested object |
| Validation | Tự kiểm tra hoặc ghép annotation | Tích hợp `@Validated` |
| Metadata IDE | Hạn chế | Có configuration processor |
| Khả năng test/refactor | Dễ rải rác | Gom thành dependency có kiểu |

Chọn `@Value` cho một giá trị cục bộ đơn giản; chọn `@ConfigurationProperties` cho contract cấu hình của module/starter. Không dùng SpEL chỉ để né việc mô hình hóa cấu hình.

### 3.3 Immutable ConfigurationProperties *(cấu hình bất biến)*

```java
// Constructor binding - immutable properties
@ConfigurationProperties(prefix = "app.database")
public record DatabaseProperties(
    String url,
    String username,
    int poolSize,
    Duration connectionTimeout
) {}

// Spring Boot hiện đại: một parameterized constructor duy nhất được bind ngầm.
// Nếu có nhiều constructor, đặt @ConstructorBinding trên constructor cần dùng.
@ConfigurationProperties(prefix = "app.database")
public class DatabaseProperties {
    private final String url;
    private final int poolSize;

    @ConstructorBinding
    public DatabaseProperties(String url, int poolSize) {
        this.url = url;
        this.poolSize = poolSize;
    }
    // only getters, no setters
}
```

Record một constructor không cần `@ConstructorBinding`. Constructor binding phải được đăng ký qua `@EnableConfigurationProperties` hoặc `@ConfigurationPropertiesScan`, không áp dụng cho object được tạo như bean `@Component`/`@Bean` thông thường; build cũng cần giữ tên parameter (`-parameters`).

---

## How/When – 4. Profiles *(nhóm cấu hình theo môi trường)*

Profile dùng để kích hoạt một tập bean hoặc config document cho môi trường như local/prod. Không nên dùng profile làm feature flag thay đổi thường xuyên; tổ hợp profile tăng nhanh sẽ khó kiểm thử và khó biết cấu hình cuối cùng.

### 4.1 Profile Configuration

```yaml
# application.yml (multi-document)
spring:
  application:
    name: my-app
  profiles:
    group:
      production: prod, prod-db, prod-redis, prod-logging
      staging: staging-db, staging-redis

---
# local document
spring:
  config:
    activate:
      on-profile: local
  datasource:
    url: jdbc:h2:mem:testdb

server:
  port: 8080

logging:
  level:
    com.example: DEBUG

---
# prod document
spring:
  config:
    activate:
      on-profile: prod
  datasource:
    url: ${DB_URL}
    username: ${DB_USER}
    password: ${DB_PASS}
    hikari:
      maximum-pool-size: 20

server:
  port: 8080

logging:
  level:
    root: WARN
    com.example: INFO
```

```java
// Profile-specific beans
@Configuration
public class DataSourceConfig {

    @Bean
    @Profile("local | test")    // EL: local OR test
    public DataSource h2DataSource() {
        return new EmbeddedDatabaseBuilder()
            .setType(EmbeddedDatabaseType.H2)
            .build();
    }

    @Bean
    @Profile("prod & !readonly")  // EL: prod AND NOT readonly
    public DataSource prodDataSource(DataSourceProperties props) {
        HikariConfig config = new HikariConfig();
        config.setJdbcUrl(props.getUrl());
        // ...
        return new HikariDataSource(config);
    }
}

// Activate profiles programmatically
SpringApplication app = new SpringApplication(MyApp.class);
app.setAdditionalProfiles("cloud");
app.run(args);

// Via environment variable: SPRING_PROFILES_ACTIVE=prod,cloud
// Via JVM arg: -Dspring.profiles.active=prod,cloud
// Via Maven: mvn spring-boot:run -Dspring-boot.run.profiles=prod
```

Không đóng gói mặc định `local` theo cách khiến production im lặng chạy H2 khi quên biến môi trường. Hãy khai báo profile triển khai rõ ràng, fail fast với property bắt buộc và nhớ rằng profile sau có thể override profile trước theo thứ tự kích hoạt.

> 💡 **Giải thích dễ hiểu — profile là bộ chìa khóa theo địa điểm:**
> Chìa khóa `local` mở kho thử nghiệm, còn `production` mở các phòng prod, database và logging tương ứng. Đeo quá nhiều chùm chìa khóa hoặc đặt chìa local làm mặc định ở nhà máy thật rất dễ mở nhầm cửa.

---

## Compare – Spring Framework và Spring Boot

| Khía cạnh | Spring Framework | Spring Boot |
|---|---|---|
| Vai trò | Container, DI, AOP, MVC, transaction và các abstraction | Auto-configure, starter, packaging và production conventions trên Spring |
| Cấu hình | Tự ghép component chi tiết | Mặc định có điều kiện, cho phép back-off/override |
| Dependency | Tự chọn/phối version | BOM/starter quản lý tập dependency tương thích |
| Runtime | Không bắt buộc embedded server | Thường chạy executable JAR với server nhúng |
| Khi phù hợp | Cần kiểm soát framework rất thấp hoặc không dùng Boot conventions | Phần lớn service/app Spring cần khởi động và vận hành nhất quán |

Spring Boot không phải đối thủ thay thế Spring Framework; nó là cách lắp và vận hành Spring có chủ kiến. “Dùng Boot” vẫn đòi hỏi hiểu proxy, bean lifecycle, transaction và thread model của Spring.

---

## How – 5. Application Lifecycle *(vòng đời ứng dụng)* & Events

### 5.1 Lifecycle Order

```
1. SpringApplication.run() called → ApplicationStartingEvent
2. Environment prepared → ApplicationEnvironmentPreparedEvent
3. ApplicationContext initialized → ApplicationContextInitializedEvent
4. Bean definitions loaded → ApplicationPreparedEvent
5. Context refreshed → ApplicationStartedEvent
6. LivenessState.CORRECT
7. ApplicationRunner / CommandLineRunner executed
8. ApplicationReadyEvent → ReadinessState.ACCEPTING_TRAFFIC

Shutdown:
1. SIGTERM received
2. JVM shutdown hook closes ApplicationContext
3. ContextClosedEvent/lifecycle stop begins
4. Graceful web shutdown stops accepting new requests and drains in-flight work
5. Bean destroy callbacks: @PreDestroy / DisposableBean.destroy()
6. JVM exits after configured shutdown timeout or completed cleanup
```

`ApplicationStartedEvent` xảy ra trước runner; `ApplicationReadyEvent` xảy ra sau runner. Readiness/liveness là tín hiệu cho nền tảng điều phối traffic, không nên suy ra chỉ từ việc process còn sống.

> 💡 **Giải thích dễ hiểu — lifecycle giống quy trình mở nhà hàng:**
> Có điện chưa có nghĩa là đã nhận khách. Bếp phải nạp thực đơn, runner chuẩn bị dữ liệu, rồi readiness mới bật biển “đang mở”. Khi đóng cửa, nhà hàng ngừng nhận bàn mới, phục vụ nốt bàn đang ăn rồi mới tắt bếp.

```java
// Listen to lifecycle events
@Component
public class AppLifecycleListener {

    @EventListener(ApplicationReadyEvent.class)
    public void onReady(ApplicationReadyEvent event) {
        log.info("Application is ready on port {}",
            event.getApplicationContext()
                .getEnvironment()
                .getProperty("local.server.port",
                    event.getApplicationContext().getEnvironment().getProperty("server.port")));
        // Chỉ làm tín hiệu nhẹ; startup task dài nên dùng Runner/executor có kiểm soát.
    }

    @EventListener(ContextClosedEvent.class)
    public void onShutdown(ContextClosedEvent event) {
        log.info("Application shutting down, releasing resources");
        // Good for: close external connections, flush buffers
    }

    @EventListener(ApplicationFailedEvent.class)
    public void onFailure(ApplicationFailedEvent event) {
        log.error("Startup failed", event.getException());
    }
}

// ApplicationRunner: after context refresh, receives ApplicationArguments
@Component
@Order(1)
public class DataInitializer implements ApplicationRunner {

    @Override
    public void run(ApplicationArguments args) throws Exception {
        if (args.containsOption("init-data")) {
            initializeMasterData();
        }
    }
}

// CommandLineRunner: simpler, receives raw String[]
@Component
@Order(2)
public class CacheWarmer implements CommandLineRunner {

    @Autowired
    private ProductService productService;

    @Override
    public void run(String... args) {
        log.info("Warming up product cache...");
        productService.warmUpCache();
    }
}
```

Các event trước khi `ApplicationContext` được tạo không thể bắt bằng listener khai báo như một `@Bean`; đăng ký chúng qua `SpringApplication.addListeners(...)` hoặc cơ chế bootstrap tương ứng.

### 5.2 Custom Application Events

```java
// Define event. Spring hiện đại cũng cho phép publish POJO/record không extends ApplicationEvent.
public class OrderCreatedEvent extends ApplicationEvent {
    private final Order order;

    public OrderCreatedEvent(Object source, Order order) {
        super(source);
        this.order = order;
    }

    public Order getOrder() { return order; }
}

// Publish event
@Service
public class OrderService {
    @Autowired
    private ApplicationEventPublisher eventPublisher;

    @Transactional
    public Order createOrder(CreateOrderRequest req) {
        Order order = orderRepository.save(new Order(req));

        // Synchronous: listeners called in same thread/transaction
        eventPublisher.publishEvent(new OrderCreatedEvent(this, order));

        return order;
    }
}

// Listen to event
@Component
public class OrderNotificationListener {

    // Same thread, same transaction (default)
    @EventListener
    public void handleOrderCreated(OrderCreatedEvent event) {
        emailService.sendConfirmation(event.getOrder());
    }

    // Async listener - different thread
    @Async
    @EventListener
    public void handleOrderCreatedAsync(OrderCreatedEvent event) {
        // Cần @EnableAsync và executor phù hợp.
        analyticsService.track(event.getOrder());
    }

    // Conditional listening
    @EventListener(condition = "#event.order.totalAmount > 1000")
    public void handleHighValueOrder(OrderCreatedEvent event) {
        fraudService.check(event.getOrder());
    }

    // Chỉ chạy sau khi transaction commit thành công.
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleOrderAfterCommit(OrderCreatedEvent event) {
        // Tránh phát trước commit, nhưng KHÔNG đảm bảo giao external message:
        // process vẫn có thể crash sau DB commit và trước convertAndSend.
        rabbitTemplate.convertAndSend("order.created", event.getOrder());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_ROLLBACK)
    public void handleOrderRollback(OrderCreatedEvent event) {
        log.warn("Order creation rolled back: {}", event.getOrder().getId());
    }
}
```

`@EventListener` mặc định đồng bộ, cùng thread; exception của listener có thể quay lại caller. Với `AFTER_COMMIT`, transaction đã hoàn tất nhưng resource có thể vẫn còn bind với thread; thao tác ghi DB mới cần transaction mới nếu muốn commit. Muốn đảm bảo nhất quán DB–broker, dùng transactional outbox thay vì coi `AFTER_COMMIT` là message delivery guarantee.

Event đưa sang async/thread khác nên là snapshot bất biến (ID và dữ liệu cần thiết), không truyền JPA entity còn lazy-loading phụ thuộc session.

> 💡 **Giải thích dễ hiểu — event nội bộ là chuông trong cùng tòa nhà:**
> Chuông sau commit chỉ reo khi sổ đã ký, nhưng nếu điện mất ngay sau khi ký thì loa ngoài tòa nhà vẫn có thể chưa phát. Outbox giống phiếu phát thanh đã được ghi cùng sổ để ca sau tiếp tục gửi.

---

## How/Components – 6. Externalized Configuration *(cấu hình nằm ngoài mã nguồn)*

### 6.1 PropertySource Priority *(độ ưu tiên nguồn property, cao xuống thấp)*

```
1.  Test/devtools overrides (chỉ khi các cơ chế này đang bật)
2.  Command-line arguments: --server.port=9090
3.  SPRING_APPLICATION_JSON
4.  ServletConfig / ServletContext / JNDI (môi trường servlet truyền thống)
5.  Java System properties: -Dserver.port=9090
6.  OS environment variables: SERVER_PORT=9090
7.  RandomValuePropertySource (chỉ random.*)
8.  Config Data:
      external application-{profile} > external application
      > packaged application-{profile} > packaged application
9.  @PropertySource annotations
10. Default properties (SpringApplication.setDefaultProperties)
```

Danh sách trên rút gọn cho runtime thông thường; Spring Boot có thêm lớp override dành cho test. Trong tài liệu chính thức, nguồn được liệt kê từ thấp đến cao và nguồn xuất hiện sau override nguồn trước. `@PropertySource` được thêm khá muộn, nên không phù hợp để đổi `logging.*` hoặc `spring.main.*` đã được đọc trước context refresh.

Config Data còn có `spring.config.import`, `configtree:` và location group; khi debug giá trị “tại sao property này thắng”, dùng Actuator `env`/`configprops` đã được bảo vệ và kiểm tra origin thay vì chỉ nhìn một file.

> 💡 **Giải thích dễ hiểu — PropertySource là chồng giấy trong suốt:**
> Tờ ở trên che giá trị cùng tên của tờ dưới. File trong JAR là mặc định; file ngoài JAR, biến môi trường hay command line có thể ghi đè. Muốn biết màu cuối cùng từ đâu, phải xem cả chồng và thứ tự tờ.

### 6.2 Spring Cloud Config Server Integration

```yaml
# application.yml - connect to config server
spring:
  config:
    import: "optional:configserver:http://config-server:8888"
  cloud:
    config:
      label: main           # git branch
      fail-fast: false      # don't fail if config server unavailable

# bootstrap.yml (Spring Cloud legacy bootstrap processing, không phải mặc định hiện đại)
spring:
  application:
    name: order-service     # used to fetch config from server
  cloud:
    config:
      uri: http://config-server:8888
```

```java
// Refresh config at runtime without restarting the whole process.
// @RefreshScope target is recreated lazily after /actuator/refresh invalidates it.
@RestController
@RefreshScope
public class FeatureController {
    @Value("${feature.new-checkout: false}")
    private boolean newCheckoutEnabled;

    // When /actuator/refresh is called:
    // 1. Config server fetched again
    // 2. @RefreshScope beans destroyed and recreated
    // 3. New property values injected
}

// EnvironmentChangeEvent can rebind eligible @ConfigurationProperties beans.
```

`/actuator/refresh` không được expose công khai mặc định; nếu bật phải xác thực, phân quyền và audit vì nó thay đổi hành vi runtime. Xóa một key khỏi nguồn không phải lúc nào cũng làm giá trị hiện tại biến mất sau refresh. Refresh scope không được hỗ trợ cho native image/AOT theo cùng cách, nên hãy kiểm tra Spring Cloud release train tương thích với Spring Boot đang dùng.

> 💡 **Giải thích dễ hiểu — refresh giống thay bảng giá khi cửa hàng đang mở:**
> Xóa cache khiến quầy đọc bảng mới ở lần dùng tiếp theo, nhưng không có nghĩa mọi nhân viên và mọi vật thể cũ đồng loạt đổi ngay. Vì vậy nút refresh phải được khóa và quan sát như một thao tác vận hành.

### 6.3 HashiCorp Vault – Dynamic Secrets

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-vault-config</artifactId>
</dependency>
```

```yaml
spring:
  cloud:
    vault:
      uri: https://vault.example.com
      authentication: KUBERNETES      # TOKEN | AWS_EC2 | APPROLE | KUBERNETES
      kubernetes:
        role: order-service
        service-account-token-file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kv:
        enabled: true
        backend: secret
        default-context: order-service       # reads secret/data/order-service
      database:
        enabled: true
        role: order-service-db-role          # dynamic DB credentials; rotation phụ thuộc lease/renewal
        backend: database
```

```bash
# Static secrets (KV v2)
vault kv put secret/order-service \
  stripe-api-key=sk_live_xxx \
  jwt-secret=super-secret-key

# Dynamic DB credentials — Vault issues leased credentials; client phải renew/reload đúng cách
vault write database/roles/order-service-db-role \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  default_ttl="1h" max_ttl="24h"
```

```java
// Vault Transit — Encryption as a Service
@Service
public class EncryptionService {

    private final VaultOperations vaultOps;

    public String encrypt(String plaintext) {
        return vaultOps.opsForTransit().encrypt("my-key",
            plaintext.getBytes(), VaultTransitContext.empty());
        // Returns: vault:v1:abc123...
    }

    public String decrypt(String ciphertext) {
        byte[] result = vaultOps.opsForTransit().decrypt("my-key", ciphertext,
            VaultTransitContext.empty());
        return new String(result);
    }
}
```

### 6.4 Kubernetes ConfigMap & Secret

```yaml
# ConfigMap (non-sensitive)
apiVersion: v1
kind: ConfigMap
metadata:
  name: order-service-config
data:
  REDIS_HOST: redis-service
  KAFKA_BOOTSTRAP: kafka:9092

---
# Secret: base64 chỉ là encoding, không phải encryption.
# Production cần RBAC, encryption at rest và/hoặc external secret manager.
apiVersion: v1
kind: Secret
metadata:
  name: order-service-secrets
type: Opaque
stringData:                          # auto base64 encode
  DATABASE_PASSWORD: example-only-do-not-commit-real-secret
  JWT_SECRET: example-only-do-not-commit-real-secret

---
# Deployment: inject as env vars
containers:
- name: order-service
  envFrom:
  - configMapRef:
      name: order-service-config
  - secretRef:
      name: order-service-secrets
  # Or individual env vars from secrets:
  env:
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: order-service-secrets
        key: DATABASE_PASSWORD
```

```yaml
# External Secrets Operator — sync Vault → K8s Secret; apiVersion phải khớp CRD đã cài
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: order-service-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: order-service-k8s-secret
  data:
  - secretKey: DATABASE_PASSWORD
    remoteRef:
      key: secret/order-service
      property: db-password
```

### 6.5 Jasypt – Inline Property Encryption

```xml
<dependency>
    <groupId>com.github.ulisesbocchio</groupId>
    <artifactId>jasypt-spring-boot-starter</artifactId>
        <version>${jasypt.version.approved-by-team}</version>
</dependency>
```

```yaml
# application.yml — ciphertext có thể commit nếu master key được quản lý tách biệt
spring:
  datasource:
    password: ENC(abc123encryptedvalue)   # jasypt decrypts at startup
jasypt:
  encryptor:
    password: ${JASYPT_ENCRYPTOR_PASSWORD}  # key from env var, never commit
```

```bash
# Generate encrypted value
mvn jasypt:encrypt-value -Djasypt.encryptor.password=my-master-key \
    -Djasypt.plugin.value=my-db-password
# → ENC(abc123encryptedvalue)
```

Jasypt là thư viện bên thứ ba, không phải secret manager của Spring Boot. Nó chỉ chuyển bài toán sang bảo vệ master key và không tự cung cấp rotation, audit hay lease. Với Kubernetes, mount secret thành file/config tree thường giảm một số rủi ro lộ qua process environment, nhưng vẫn phải giới hạn quyền đọc.

### 6.6 Secrets Management: Trade-offs

| Approach | Kiểm soát/rủi ro chính | Complexity | Rotation | Phù hợp |
|----------|------------------------|------------|----------|----------|
| Env vars | Có thể lộ qua process/debug/dump | Low | Manual | App đơn giản, secret ngắn hạn |
| K8s Secrets | Cần RBAC + encryption at rest | Medium | Phụ thuộc controller/quy trình | Workload Kubernetes |
| Vault (Spring Cloud) | Policy, lease, audit; vận hành phức tạp | High | Có với secret engine phù hợp | Secret động, yêu cầu audit |
| External Secrets Operator | Đồng bộ về K8s Secret, kế thừa rủi ro đích | Medium | Theo refresh policy | K8s + external secret store |
| Jasypt | Phụ thuộc bảo vệ master key | Low | Manual | Legacy, ciphertext trong config |
| Spring Cloud Config | Central config, không tự là secret manager | Medium | Refresh/redeploy tùy client | Config nhiều service |

```
Practical preference (không phải PropertySource precedence):
1. External secret manager / Vault  — secret động, lease, audit nếu vận hành đúng
2. K8s Secret + configtree/ESO       — phù hợp K8s, vẫn cần RBAC/encryption at rest
3. OS environment variables         — đơn giản nhưng có rủi ro lộ qua process/dump
4. Spring Cloud Config Server        — config dùng chung; secret cần backend/bảo vệ riêng
5. application-{profile}.yml         — defaults theo profile, không chứa secret thật
6. application.yml                   — base defaults, không chứa secret thật
Command-line override                — tiện cho dev/incident, dễ lộ trong process history
```

Không có lựa chọn “High security” chỉ nhờ tên công cụ. Security phụ thuộc identity, policy, TLS, audit, rotation, cách ứng dụng reload và khả năng thu hồi credential.

> 💡 **Giải thích dễ hiểu — secret manager là két có sổ mượn chìa khóa:**
> Base64 chỉ giống gói mật khẩu trong phong bì trong suốt. Vault/ESO có thể cấp chìa theo thời hạn và ghi ai đã lấy, nhưng nếu ứng dụng không đổi chìa khi lease hết thì cơ chế rotation vẫn thất bại.

---

## Trade-offs – 7. Startup Optimization *(tối ưu thời gian khởi động)*

```java
// 1. Lazy initialization (Spring Boot 2.2+)
@SpringBootApplication
public class MyApp {
    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(MyApp.class);
        app.setLazyInitialization(true);  // beans created on first use
        app.run(args);
    }
}

// Or in application.yml:
// spring.main.lazy-initialization: true

// 2. Exclude an auto-configuration only after reading the condition report
@SpringBootApplication(exclude = {
    DataSourceAutoConfiguration.class,
    SecurityAutoConfiguration.class,  // only if Boot security auto-config is truly unwanted
    FlywayAutoConfiguration.class,    // manage manually
})
public class MyApp { ... }

// 3. CDS for JDK < 25: must run an extracted executable jar
// java -Djarmode=tools -jar app.jar extract --destination application
// cd application
// java -XX:ArchiveClassesAtExit=application.jsa \
//      -Dspring.context.exit=onRefresh -jar app.jar
// java -XX:SharedArchiveFile=application.jsa -jar app.jar
// JDK 25+: prefer AOT Cache (-XX:AOTCacheOutput / -XX:AOTCache).

// 4. Spring Boot 3.2+ virtual threads (requires Java 21+)
// spring.threads.virtual.enabled=true
// Virtual threads reduce thread-per-request cost; they do not remove DB/socket limits,
// pinning risk or the need for backpressure.

// 5. AOT (Ahead of Time) processing - native image or AOT-processed JVM mode
// Build must include generated AOT code; JVM run uses:
// java -Dspring.aot.enabled=true -jar app.jar
// AOT fixes the classpath/bean model at build time and limits dynamic conditions/profiles.
```

Lazy initialization đổi startup nhanh lấy lỗi xuất hiện muộn ở request đầu tiên và có thể làm sai heap sizing nếu chỉ đo lúc vừa khởi động. Exclude auto-configuration giảm việc làm nhưng tăng trách nhiệm cấu hình/vận hành. AOT/native/CDS/AOT Cache giải các lớp khác nhau và phải benchmark trên artifact, JDK và workload thật.

> 💡 **Giải thích dễ hiểu — tối ưu startup giống chuẩn bị nhà hàng:**
> Lazy init là chưa nấu món cho tới khi khách gọi: mở cửa nhanh nhưng lỗi nguyên liệu xuất hiện muộn. AOT/CDS giống chuẩn bị sơ đồ bếp trước; nhanh hơn nhưng khó đổi cách bố trí sau khi đã đóng gói.

---

## How – 8. PropertySources & Environment

```java
// Custom PropertySource
@Component
public class VaultPropertySourceInitializer implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    @Override
    public void initialize(ConfigurableApplicationContext context) {
        ConfigurableEnvironment env = context.getEnvironment();

        // Add custom property source at highest priority
        Map<String, Object> secrets = fetchFromVault();  // load from Vault

        MapPropertySource vaultSource = new MapPropertySource("vault", secrets);
        env.getPropertySources().addFirst(vaultSource);
    }

    private Map<String, Object> fetchFromVault() {
        // ... call Vault API
        return Map.of("db.password", "secret123");
    }
}

// Register programmatically:
// SpringApplication app = new SpringApplication(MyApp.class);
// app.addInitializers(new VaultPropertySourceInitializer());
// app.run(args);
// Library/bootstrap integration can also register an ApplicationContextInitializer
// through the supported metadata mechanism for the target Spring Boot version.

// Access Environment programmatically
@Component
public class ConfigInspector {
    @Autowired
    private Environment env;

    public void inspect() {
        String[] profiles = env.getActiveProfiles(); // có thể rỗng; đừng index [0] trực tiếp
        String port = env.getProperty("server.port", "8080");
        boolean hasRedis = env.getProperty("spring.data.redis.host") != null;
    }
}
```

Initializer chạy rất sớm, nên network call tới Vault có thể kéo dài hoặc làm fail toàn bộ startup; secret cũng tồn tại dạng plaintext trong process memory. Với external config provider, ưu tiên integration `ConfigData`/Spring Cloud được hỗ trợ, có timeout, retry, authentication và rotation rõ ràng hơn custom `MapPropertySource`.

`addFirst` đặt nguồn Vault lên trên mọi `PropertySource` đang có, kể cả command-line; đó là quyết định precedence của ứng dụng, không phải mặc định Spring Boot. Chọn `addBefore`/`addAfter` theo policy nếu vẫn phải hỗ trợ override có kiểm soát.

---

## How/Trade-offs – 9. `@Async` & `CompletableFuture`

`@Async` *(chạy method trên executor khác)* là cơ chế proxy của Spring. Nó phù hợp cho công việc cục bộ, ngắn và chấp nhận mất khi process chết; không thay thế message broker/job store khi cần durable retry hoặc guarantee xử lý.

### 9.1 Setup

```java
@SpringBootApplication
@EnableAsync   // bắt buộc
public class App {}
```

### 9.2 Basic @Async

```java
@Service
public class EmailService {

    // Fire-and-forget
    @Async
    public void sendWelcomeEmail(String email) {
        emailProvider.send(email, "Welcome!", buildTemplate());
    }

    // Return value — caller can await
    @Async
    public CompletableFuture<Boolean> sendAndTrack(String email) {
        try {
            emailProvider.send(email, "Hi");
            return CompletableFuture.completedFuture(true);
        } catch (Exception e) {
            return CompletableFuture.failedFuture(e);
        }
    }
}
```

### 9.3 Custom Thread Pool *(pool thread tùy chỉnh)*

```java
// Spring Boot auto-configures AsyncTaskExecutor if no Executor exists:
// - Java 21+ và spring.threads.virtual.enabled=true: virtual-thread SimpleAsyncTaskExecutor
// - otherwise: ThreadPoolTaskExecutor with Boot defaults.
// Define/tune your own executor when workload needs explicit isolation/backpressure.

@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {

    @Override
    public Executor getAsyncExecutor() {
        return taskExecutor();
    }

    @Bean(name = "taskExecutor")
    public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        executor.setMaxPoolSize(50);
        executor.setQueueCapacity(1000);
        executor.setKeepAliveSeconds(60);
        executor.setThreadNamePrefix("async-");
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }

    // Dedicated executor for heavy tasks
    @Bean(name = "reportExecutor")
    public ThreadPoolTaskExecutor reportExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(5);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("report-");
        executor.initialize();
        return executor;
    }

    @Override
    public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
        return (ex, method, params) ->
            log.error("Async exception in {}: {}", method.getName(), ex.getMessage(), ex);
    }
}

// Use named executor
@Async("reportExecutor")
public CompletableFuture<Report> generateLargeReport(ReportRequest req) { ... }
```

Với `ThreadPoolTaskExecutor`, queue lớn thường được lấp trước khi pool tăng từ core lên max; `maxPoolSize=50` không có nghĩa 50 thread luôn hoạt động. `CallerRunsPolicy` tạo backpressure bằng cách bắt caller tự chạy task, nhưng có thể làm chậm request thread. Kích thước pool phải dựa trên CPU/blocking ratio, downstream limits, latency SLO và đo queue/rejection.

Khi Boot auto-configure virtual-thread executor, các thuộc tính pool truyền thống không có cùng ý nghĩa vì virtual thread không được quản lý như một fixed platform-thread pool. Vẫn phải giới hạn concurrency ở database/HTTP client/semaphore để không dồn tải xuống downstream.

> 💡 **Giải thích dễ hiểu — executor là quầy nhận việc có phòng chờ:**
> Core pool là nhân viên thường trực, queue là ghế chờ, max pool là người tăng cường. Nếu đặt nghìn ghế, khách sẽ ngồi chờ lâu trước khi gọi thêm nhân viên; nếu đầy, `CallerRunsPolicy` bắt người giao việc tự phục vụ.

### 9.4 @Async Caveats

```java
// ❌ Self-invocation bypasses AOP proxy — @Async does nothing
@Service
public class OrderService {
    @Async
    public void asyncMethod() { ... }

    public void regularMethod() {
        asyncMethod();  // called on 'this', not proxy → synchronous!
    }
}

// ✅ Preferred fix: move async boundary to another bean so call goes through proxy
@Service
public class AsyncOrderWorker {
    @Async("taskExecutor")
    public void asyncMethod() { ... }
}

@Service
public class OrderService {
    private final AsyncOrderWorker worker;

    public OrderService(AsyncOrderWorker worker) {
        this.worker = worker;
    }

    public void regularMethod() {
        worker.asyncMethod();
    }
}

// ❌ @Transactional + @Async: transaction does NOT propagate to async thread
// ✅ Use @TransactionalEventListener(AFTER_COMMIT) + @Async instead
@Component
public class OrderEventHandler {
    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onOrderCreated(OrderCreatedEvent event) {
        notificationService.sendConfirmation(event.getOrder());
    }
}

// SecurityContext does NOT propagate automatically.
// Prefer Spring Security's delegating executor wrapper (cần Spring Security):
@Bean(name = "securityAwareExecutor")
public AsyncTaskExecutor securityAwareExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(10);
    executor.initialize();
    return new DelegatingSecurityContextAsyncTaskExecutor(executor);
}
```

Transaction, MDC, tracing context và request-scoped state không tự đi sang thread mới. Chỉ propagate dữ liệu thật sự cần, xóa context sau task và không truyền JPA entity/session. `void @Async` gửi exception tới `AsyncUncaughtExceptionHandler`; method trả `CompletableFuture` phải để caller quan sát failure.

`@TransactionalEventListener(AFTER_COMMIT) + @Async` tránh chạy trước commit nhưng không tạo durable delivery. Nếu process chết trước khi task được executor nhận/xử lý, công việc vẫn mất; dùng outbox/queue khi cần phục hồi.

> 💡 **Giải thích dễ hiểu — gọi `@Async` nội bộ giống tự gọi số máy lẻ của mình:**
> Cuộc gọi không đi qua tổng đài proxy nên không được chuyển sang nhân viên khác. Tách worker thành bean riêng buộc cuộc gọi qua tổng đài; nhưng phiếu chỉ nằm trong phòng chờ RAM vẫn có thể mất khi tòa nhà mất điện.

### 9.5 CompletableFuture Patterns

```java
@Service
public class DashboardService {

    // Parallel calls — all run concurrently, wait for all
    public DashboardData getDashboard(Long tenantId) throws Exception {
        CompletableFuture<List<User>> usersFuture =
            CompletableFuture.supplyAsync(() -> userService.findByTenant(tenantId), taskExecutor);
        CompletableFuture<List<Order>> ordersFuture =
            CompletableFuture.supplyAsync(() -> orderService.findByTenant(tenantId), taskExecutor);
        CompletableFuture<InventoryStats> inventoryFuture =
            CompletableFuture.supplyAsync(() -> inventoryService.getStats(tenantId), taskExecutor);

        CompletableFuture.allOf(usersFuture, ordersFuture, inventoryFuture).join();

        return new DashboardData(usersFuture.get(), ordersFuture.get(), inventoryFuture.get());
    }

    // Chain: thenApply (sync transform) vs thenCompose (async flatMap)
    public CompletableFuture<EnrichedOrder> processOrder(CreateOrderRequest req) {
        return CompletableFuture
            .supplyAsync(() -> orderService.create(req), taskExecutor)
            .thenApplyAsync(order -> enrichmentService.enrich(order), taskExecutor)
            .thenComposeAsync(order -> paymentService.chargeAsync(order), taskExecutor)
            .exceptionally(ex -> {
                log.error("Order processing failed", ex);
                throw new OrderProcessingException(ex);
            });
    }

    // Timeout with fallback
    public CompletableFuture<Product> getProductWithTimeout(Long id) {
        return CompletableFuture.supplyAsync(() -> productService.find(id), taskExecutor)
            .orTimeout(5, TimeUnit.SECONDS)
            .exceptionally(ex -> {
                Throwable cause = ex instanceof CompletionException && ex.getCause() != null
                    ? ex.getCause() : ex;
                if (cause instanceof TimeoutException) {
                    return productService.getCachedFallback(id);
                }
                throw new CompletionException(cause);
            });
    }

    // anyOf: take result from fastest source
    public CompletableFuture<String> getFromFastest(String key) {
        return CompletableFuture.anyOf(
            cacheService.getAsync(key),
            dbService.getAsync(key)
        ).thenApply(result -> (String) result);
    }
}
```

Nếu bỏ executor trong `supplyAsync`/`thenApplyAsync`, Java thường dùng `ForkJoinPool.commonPool`, khiến workload của ứng dụng tranh tài nguyên với code khác. `orTimeout` hoàn tất future bằng lỗi nhưng không bảo đảm I/O nền đã bị hủy; HTTP/DB client vẫn cần connect/read/query timeout và cancellation phù hợp. Tránh fallback `null` làm mất nguyên nhân lỗi.

---

## When – Chọn cơ chế nào?

| Nhu cầu | Cơ chế ưu tiên |
|---|---|
| Thư viện tự bật khi có dependency/property | Auto-configuration + condition + starter |
| Nhóm config có kiểu và validation | `@ConfigurationProperties` |
| Khác biệt deploy tương đối ổn định | Profile/Config Data; feature động dùng feature flag riêng |
| Việc khởi động bắt buộc trước readiness | `ApplicationRunner`/`CommandLineRunner` có timeout |
| Thông báo nội bộ trong cùng process | Application event |
| Việc nền ngắn, chấp nhận mất khi restart | `@Async` với executor có giới hạn |
| Việc cần retry bền vững/không được mất | Queue, outbox, scheduler/job store |
| Secret có rotation/audit | External secret manager và integration được hỗ trợ |

> 💡 **Giải thích dễ hiểu — chọn công cụ theo độ bền của phiếu việc:**
> Việc nhắc nhanh trong văn phòng có thể gọi điện (`@Async`); đơn hàng không được mất phải ghi vào sổ hoặc hàng đợi bền vững. Dùng điện thoại cho mọi việc nhanh lúc đầu nhưng không thể phục hồi sau mất điện.

---

## Production – Checklist vận hành

- Pin Spring Boot/Spring Cloud release train, JDK và dependency bằng BOM; kiểm tra migration guide trước khi nâng cấp major.
- Bật Actuator có chọn lọc; bảo vệ `env`, `configprops`, `conditions`, `refresh` và sanitize secret.
- Cấu hình liveness/readiness, graceful shutdown timeout và thời gian nền tảng chờ pod/process kết thúc.
- Theo dõi startup time, failed condition, config origin, executor active/queue/rejection, async failure và downstream timeout.
- Fail fast với property bắt buộc; không ghi secret hoặc toàn bộ `Environment` vào log.
- Test auto-configuration bằng `ApplicationContextRunner`, test profile/property precedence và shutdown/restart.
- Với external side effect, dùng idempotency/outbox; không coi event nội bộ hay `@Async` là durable message bus.
- Benchmark lazy init, virtual thread, AOT/CDS/AOT Cache trên đúng JDK/container/workload trước khi chuẩn hóa.

> 💡 **Giải thích dễ hiểu — production không chỉ là ứng dụng “đã chạy”:**
> Nhà máy cần biết cửa nào đang mở, hàng đợi nào sắp đầy, chìa khóa nào sắp hết hạn và mất điện thì phiếu việc nào còn phục hồi được. Một dòng log “Started” chưa trả lời các câu hỏi đó.

---

## Ghi chú – Chủ đề tiếp theo

- **REST API deep**: exception handler, validation, OpenAPI → [springboot_web.md](springboot_web.md)
- **WebFlux / Reactive**: Mono/Flux, WebClient → [springboot_web.md](springboot_web.md)
- **Spring Security**: JWT, OAuth2 → [springboot_web.md](springboot_web.md)
- **JPA N+1**: EntityGraph, Projections, Specifications → [springboot_data.md](springboot_data.md)
- **Spring Cache**: `@Cacheable`, Redis integration → [springboot_data.md](springboot_data.md)
- **Spring Kafka**: `@KafkaListener`, error handling → [springboot_messaging.md](springboot_messaging.md)
- **`@TransactionalEventListener`**: reliable event patterns → [springboot_messaging.md](springboot_messaging.md)
- **`@Scheduled` / Spring Batch**: scheduling, job processing → [springboot_scheduling.md](springboot_scheduling.md)
- **Actuator**: custom health indicators, metrics → [springboot_production.md](springboot_production.md)
- **GraalVM native image**: AOT, hints → [springboot_production.md](springboot_production.md)

---

*Cập nhật lần cuối: 2026-07-27*
