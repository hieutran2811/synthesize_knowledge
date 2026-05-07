# Spring Boot Core & Internals

## 1. Auto-configuration Deep Dive

### 1.1 SPI Mechanism (Spring Boot 3)

```
Auto-configuration discovery flow:

1. JVM loads spring-boot-autoconfigure.jar
2. @EnableAutoConfiguration → AutoConfigurationImportSelector
3. Reads: META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
4. Each listed class = candidate auto-configuration
5. Spring evaluates @Conditional* annotations (in dependency order)
6. Passing candidates → their @Bean methods → registered in ApplicationContext
```

```java
// META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
// (Spring Boot 3 - replaces spring.factories)
org.springframework.boot.autoconfigure.data.redis.RedisAutoConfiguration
org.springframework.boot.autoconfigure.data.jpa.JpaRepositoriesAutoConfiguration
org.springframework.boot.autoconfigure.web.servlet.WebMvcAutoConfiguration
// ... ~170 entries in spring-boot-autoconfigure

// Spring Boot 2 used spring.factories:
// org.springframework.boot.autoconfigure.EnableAutoConfiguration=\
//   com.example.MyAutoConfiguration
```

### 1.2 @Conditional Chain

```java
// Tất cả @Conditional* annotations trong Spring Boot:

// Classpath conditions
@ConditionalOnClass(DataSource.class)         // DataSource present on classpath
@ConditionalOnMissingClass("com.some.Class")  // class NOT present

// Bean conditions (evaluation order matters!)
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

---

## 2. Custom Starter

### 2.1 Starter Structure

```
my-spring-boot-starter/
├── my-autoconfigure/                    ← auto-configuration module
│   ├── pom.xml
│   └── src/main/java/com/example/
│       ├── MyProperties.java
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
// MyProperties.java - type-safe config
@ConfigurationProperties(prefix = "my.service")
@Validated  // enable JSR-303 on properties
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
@ConditionalOnClass(MyService.class)
@ConditionalOnProperty(prefix = "my.service", name = "enabled", matchIfMissing = true)
@EnableConfigurationProperties(MyServiceProperties.class)
public class MyAutoConfiguration {
    
    @Bean
    @ConditionalOnMissingBean  // let user override
    public MyService myService(MyServiceProperties properties) {
        return new MyService(properties);
    }
    
    // Additional beans that depend on MyService
    @Bean
    @ConditionalOnBean(MyService.class)
    @ConditionalOnClass(MeterRegistry.class)  // only if Micrometer present
    public MyServiceMetrics myServiceMetrics(MyService service, MeterRegistry registry) {
        return new MyServiceMetrics(service, registry);
    }
}
```

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

---

## 3. @ConfigurationProperties Deep

### 3.1 Type-safe Binding

```java
@ConfigurationProperties(prefix = "app")
@Validated
public class AppProperties {
    
    // Relaxed binding: app.api-url = app.apiUrl = app.api_url = APP_API_URL (env var)
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

### 3.2 @Value vs @ConfigurationProperties

```java
// @Value: simple, per-property injection
@Value("${app.api-url}")
private String apiUrl;

@Value("${app.max-retries:3}")  // default value
private int maxRetries;

@Value("#{${app.headers}}")    // SpEL for Map injection
private Map<String, String> headers;

// Limitations: cannot be used in @Bean methods (only after construction)
// Cannot be used on @Configuration classes with static @Bean

// @ConfigurationProperties: recommended for groups of related properties
// ✓ Type-safe
// ✓ Hierarchical / nested
// ✓ Validation support
// ✓ IDE autocomplete
// ✓ Relaxed binding
// ✓ Can use Duration, DataSize, Period types
// ✓ Works in @Bean methods
```

### 3.3 Immutable ConfigurationProperties (Spring Boot 2.2+)

```java
// Constructor binding - immutable properties
@ConfigurationProperties(prefix = "app.database")
public record DatabaseProperties(
    String url,
    String username,
    int poolSize,
    Duration connectionTimeout
) {}

// Or with @ConstructorBinding (pre-3.x)
@ConfigurationProperties(prefix = "app.database")
@ConstructorBinding
public class DatabaseProperties {
    private final String url;
    private final int poolSize;
    
    public DatabaseProperties(String url, int poolSize) {
        this.url = url;
        this.poolSize = poolSize;
    }
    // only getters, no setters
}
```

---

## 4. Profiles

### 4.1 Profile Configuration

```yaml
# application.yml (shared config)
spring:
  application:
    name: my-app
  profiles:
    active: ${SPRING_PROFILES_ACTIVE:local}
    group:
      production: prod-db, prod-redis, prod-logging
      staging: staging-db, staging-redis

---
# application-local.yml
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
# application-prod.yml
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

---

## 5. Application Lifecycle & Events

### 5.1 Lifecycle Order

```
1. SpringApplication.run() called
2. SpringApplicationRunListeners.starting()
3. Environment prepared → ApplicationEnvironmentPreparedEvent
4. ApplicationContext created
5. Beans loaded, @Configuration processed
6. ApplicationContext refreshed → ApplicationStartedEvent
7. ApplicationRunner / CommandLineRunner executed
8. ApplicationReadyEvent (app is ready to serve requests)

Shutdown:
1. SIGTERM received
2. Graceful shutdown: drain in-flight requests (server.shutdown=graceful)
3. @PreDestroy methods called
4. ApplicationContext closed → ContextClosedEvent
5. DisposableBean.destroy() called
6. JVM shutdown
```

```java
// Listen to lifecycle events
@Component
public class AppLifecycleListener {
    
    @EventListener(ApplicationReadyEvent.class)
    public void onReady(ApplicationReadyEvent event) {
        log.info("Application is ready on port {}",
            event.getApplicationContext()
                .getEnvironment()
                .getProperty("server.port"));
        // Good for: start background jobs, warm up caches
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

### 5.2 Custom Application Events

```java
// Define event
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
        analyticsService.track(event.getOrder());
    }
    
    // Conditional listening
    @EventListener(condition = "#event.order.totalAmount > 1000")
    public void handleHighValueOrder(OrderCreatedEvent event) {
        fraudService.check(event.getOrder());
    }
    
    // @TransactionalEventListener: fires AFTER transaction commits
    // Critical: ensures DB is committed before sending notification
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleOrderAfterCommit(OrderCreatedEvent event) {
        // Safe to publish external events here (DB is committed)
        rabbitTemplate.convertAndSend("order.created", event.getOrder());
    }
    
    @TransactionalEventListener(phase = TransactionPhase.AFTER_ROLLBACK)
    public void handleOrderRollback(OrderCreatedEvent event) {
        log.warn("Order creation rolled back: {}", event.getOrder().getId());
    }
}
```

---

## 6. Externalized Configuration

### 6.1 PropertySource Priority (highest to lowest)

```
1.  Command-line arguments: --server.port=9090
2.  SPRING_APPLICATION_JSON (env var or system property)
3.  ServletConfig/ServletContext init params
4.  JNDI attributes
5.  Java System properties: -Dserver.port=9090
6.  OS environment variables: SERVER_PORT=9090
7.  Profile-specific: application-{profile}.properties
8.  application.properties/yaml (inside jar)
9.  @PropertySource annotations
10. Default properties (SpringApplication.setDefaultProperties)
```

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

# bootstrap.yml (old way, Spring Boot 2)
spring:
  application:
    name: order-service     # used to fetch config from server
  cloud:
    config:
      uri: http://config-server:8888
```

```java
// Refresh config at runtime (no restart)
// @RefreshScope: bean recreated on /actuator/refresh call
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

// Or: @ConfigurationProperties beans auto-refreshed without @RefreshScope
```

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
        role: order-service-db-role          # dynamic DB credentials, auto-rotate
        backend: database
```

```bash
# Static secrets (KV v2)
vault kv put secret/order-service \
  stripe-api-key=sk_live_xxx \
  jwt-secret=super-secret-key

# Dynamic DB credentials — Vault rotates every 1h automatically
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
# Secret (base64 — use External Secrets Operator or Vault for true security)
apiVersion: v1
kind: Secret
metadata:
  name: order-service-secrets
type: Opaque
stringData:                          # auto base64 encode
  DATABASE_PASSWORD: my-db-pass
  JWT_SECRET: super-secret-key

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
# External Secrets Operator — sync Vault → K8s Secret automatically
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
    <version>3.0.5</version>
</dependency>
```

```yaml
# application.yml — encrypt sensitive values, commit safely
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

### 6.6 Secrets Management: Trade-offs

| Approach | Security | Complexity | Auto-rotation | Best for |
|----------|----------|------------|---------------|----------|
| Env vars | Medium | Low | Manual | Simple apps, Docker Compose |
| K8s Secrets | Medium | Medium | Manual | K8s without Vault |
| Vault (Spring Cloud) | High | High | Automatic | Enterprise, high security |
| External Secrets Operator | High | Medium | Via ESO | K8s + external secret stores |
| Jasypt | Low | Low | Manual | Legacy, simple encryption |
| Spring Cloud Config | Medium | Medium | Via /refresh | Multi-service config |

```
Priority order (highest → lowest):
1. Command-line args (--prop=value) — dev/test only
2. OS Environment Variables         — production standard
3. Vault dynamic secrets            — enterprise, auto-rotate
4. Kubernetes Secrets               — K8s-managed static
5. Spring Cloud Config Server       — multi-service centralized
6. application-{profile}.yml        — profile-specific defaults
7. application.yml                  — base defaults (no secrets here!)
```

---

## 7. Startup Optimization

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

// 2. Exclude unused auto-configurations
@SpringBootApplication(exclude = {
    DataSourceAutoConfiguration.class,
    SecurityAutoConfiguration.class,  // if using custom security
    FlywayAutoConfiguration.class,    // manage manually
})
public class MyApp { ... }

// 3. Class Data Sharing (CDS) - Spring Boot 3.3+
// Training run: generates classes.jsa archive
// java -Dspring.context.exit=onRefresh -jar app.jar
// Next runs use the archive: -XX:SharedArchiveFile=app.jsa

// 4. Spring Boot 3.2+ Virtual Thread Tomcat (no blocking overhead)
// spring.threads.virtual.enabled=true

// 5. AOT (Ahead of Time) processing - for native image or faster startup
// mvn spring-boot:process-aot
// → Generates reflection hints, proxy classes at build time
// → JVM can skip reflection scanning at runtime
```

---

## 8. PropertySources & Environment

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

// Register in spring.factories or application.yml:
// context.initializer.classes=com.example.VaultPropertySourceInitializer

// Access Environment programmatically
@Component
public class ConfigInspector {
    @Autowired
    private Environment env;
    
    public void inspect() {
        String profile = env.getActiveProfiles()[0];
        String port = env.getProperty("server.port", "8080");
        boolean hasRedis = env.getProperty("spring.data.redis.host") != null;
    }
}
```

---

## 9. @Async & CompletableFuture

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

### 9.3 Custom Thread Pool (Production Required)

```java
// Default @Async uses SimpleAsyncTaskExecutor — creates new thread per call!
// Always configure a proper pool.

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

// ✅ Fix: inject self via @Lazy
@Service
public class OrderService {
    @Autowired @Lazy
    private OrderService self;

    public void regularMethod() {
        self.asyncMethod();  // goes through proxy → async
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

// SecurityContext also does NOT propagate automatically — use TaskDecorator:
@Bean(name = "securityAwareExecutor")
public ThreadPoolTaskExecutor securityAwareExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(10);
    executor.setTaskDecorator(runnable -> {
        SecurityContext ctx = SecurityContextHolder.getContext();
        return () -> {
            try {
                SecurityContextHolder.setContext(ctx);
                runnable.run();
            } finally {
                SecurityContextHolder.clearContext();
            }
        };
    });
    executor.initialize();
    return executor;
}
```

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
            .supplyAsync(() -> orderService.create(req))
            .thenApplyAsync(order -> enrichmentService.enrich(order))   // transform
            .thenComposeAsync(order -> paymentService.chargeAsync(order)) // flatMap (returns CF)
            .exceptionally(ex -> {
                log.error("Order processing failed", ex);
                throw new OrderProcessingException(ex);
            });
    }

    // Timeout with fallback
    public CompletableFuture<Product> getProductWithTimeout(Long id) {
        return CompletableFuture.supplyAsync(() -> productService.find(id))
            .orTimeout(5, TimeUnit.SECONDS)
            .exceptionally(ex -> ex instanceof TimeoutException
                ? productService.getCachedFallback(id)
                : null);
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

---

## 10. Ghi chú – Topics tiếp theo

- **REST API deep**: exception handler, validation, OpenAPI → `springboot_web.md`
- **WebFlux / Reactive**: Mono/Flux, WebClient → `springboot_web.md`
- **Spring Security**: JWT, OAuth2 → `springboot_web.md`
- **JPA N+1**: EntityGraph, Projections, Specifications → `springboot_data.md`
- **Spring Cache**: @Cacheable, Redis integration → `springboot_data.md`
- **Spring Kafka**: @KafkaListener, error handling → `springboot_messaging.md`
- **@TransactionalEventListener**: reliable event patterns → `springboot_messaging.md`
- **@Scheduled / Spring Batch**: scheduling, job processing → `springboot_scheduling.md`
- **Actuator**: custom health indicators, metrics → `springboot_production.md`
- **GraalVM native image**: AOT, hints → `springboot_production.md`
