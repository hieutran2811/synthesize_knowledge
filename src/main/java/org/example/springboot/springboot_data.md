# Spring Boot Data Layer – Deep Dive

## Mục lục
1. [JPA N+1 Problem & Solutions](#1-jpa-n1-problem--solutions)
2. [Projections – Interface, DTO, Dynamic](#2-projections)
3. [Specifications & Querydsl](#3-specifications--querydsl)
4. [Spring Cache Deep Dive](#4-spring-cache-deep-dive)
5. [Multiple Datasources](#5-multiple-datasources)
6. [Flyway & Liquibase](#6-flyway--liquibase)
7. [R2DBC Reactive Data](#7-r2dbc-reactive-data)

---

## 1. JPA N+1 Problem & Solutions

### 1.1 Reproduce N+1

```java
// Entity
@Entity
public class Order {
    @Id @GeneratedValue
    private Long id;
    private String status;

    @ManyToOne(fetch = FetchType.LAZY)  // LAZY = default for @ManyToOne
    @JoinColumn(name = "customer_id")
    private Customer customer;

    @OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
    private List<OrderItem> items = new ArrayList<>();
}

// Repository
List<Order> orders = orderRepository.findAll(); // 1 query

for (Order o : orders) {
    System.out.println(o.getCustomer().getName()); // N queries for customer
    System.out.println(o.getItems().size());        // N queries for items
    // Total = 1 + N + N = 2N+1 queries
}
```

### 1.2 Solution 1: JOIN FETCH (JPQL)

```java
// Repository method
@Query("SELECT DISTINCT o FROM Order o " +
       "JOIN FETCH o.customer " +
       "JOIN FETCH o.items " +
       "WHERE o.status = :status")
List<Order> findWithCustomerAndItems(@Param("status") String status);

// Limitation: Cannot use Pageable with JOIN FETCH on collection
// HibernateException: "cannot simultaneously fetch multiple bags"
// Fix: Use Set instead of List, or separate queries
```

**JOIN FETCH + Pagination workaround:**

```java
// Step 1: fetch IDs with pagination
@Query(value = "SELECT o.id FROM Order o WHERE o.status = :status",
       countQuery = "SELECT count(o) FROM Order o WHERE o.status = :status")
Page<Long> findIdsByStatus(@Param("status") String status, Pageable pageable);

// Step 2: fetch entities by IDs
@Query("SELECT DISTINCT o FROM Order o JOIN FETCH o.items WHERE o.id IN :ids")
List<Order> findByIdsWithItems(@Param("ids") List<Long> ids);

// Service
public Page<Order> getOrders(String status, Pageable pageable) {
    Page<Long> idPage = orderRepository.findIdsByStatus(status, pageable);
    List<Order> orders = orderRepository.findByIdsWithItems(idPage.getContent());
    return new PageImpl<>(orders, pageable, idPage.getTotalElements());
}
```

### 1.3 Solution 2: @EntityGraph

```java
// Named EntityGraph on entity
@Entity
@NamedEntityGraph(
    name = "Order.withCustomerAndItems",
    attributeNodes = {
        @NamedAttributeNode("customer"),
        @NamedAttributeNode(value = "items", subgraph = "items.product")
    },
    subgraphs = @NamedSubgraph(
        name = "items.product",
        attributeNodes = @NamedAttributeNode("product")
    )
)
public class Order { ... }

// Repository
@EntityGraph("Order.withCustomerAndItems")
Optional<Order> findById(Long id);

// Ad-hoc EntityGraph (no @NamedEntityGraph needed)
@EntityGraph(attributePaths = {"customer", "items", "items.product"})
List<Order> findByStatus(String status);
```

### 1.4 Solution 3: Batch Fetching (Hibernate)

```java
// application.yml — global batch size
spring:
  jpa:
    properties:
      hibernate:
        default_batch_fetch_size: 100
        # Hibernate will batch IN clause: WHERE id IN (?, ?, ... 100 items)

// Or per-entity/collection
@Entity
public class Customer {
    @BatchSize(size = 50)
    @OneToMany(mappedBy = "customer")
    private List<Order> orders;
}
```

### 1.5 Solution 4: @Fetch(FetchMode.SUBSELECT)

```java
@Entity
public class Customer {
    @Fetch(FetchMode.SUBSELECT)
    @OneToMany(mappedBy = "customer")
    private List<Order> orders;
    // SQL: SELECT * FROM orders WHERE customer_id IN (SELECT id FROM customers WHERE ...)
}
```

### 1.6 Hibernate Statistics (Diagnose)

```yaml
spring:
  jpa:
    properties:
      hibernate:
        generate_statistics: true
        session:
          events:
            log:
              LOG_QUERIES_SLOWER_THAN_MS: 5
logging:
  level:
    org.hibernate.stat: DEBUG
    org.hibernate.SQL: DEBUG
    org.hibernate.type.descriptor.sql.BasicBinder: TRACE
```

```java
// Programmatic stats
@Autowired
private EntityManagerFactory emf;

public void printStats() {
    Statistics stats = emf.unwrap(SessionFactory.class).getStatistics();
    System.out.println("Query count: " + stats.getQueryExecutionCount());
    System.out.println("Entity load: " + stats.getEntityLoadCount());
    System.out.println("2nd level cache hit: " + stats.getSecondLevelCacheHitCount());
}
```

---

## 2. Projections

### 2.1 Interface Projection (Closed)

```java
// Only fetch needed columns → SELECT id, first_name, last_name FROM users
public interface UserSummary {
    Long getId();
    String getFirstName();
    String getLastName();
    
    // Computed property with SpEL
    @Value("#{target.firstName + ' ' + target.lastName}")
    String getFullName();
}

// Repository
List<UserSummary> findByActive(boolean active);
Optional<UserSummary> findById(Long id, Class<UserSummary> type);
```

### 2.2 Interface Projection (Open) – Dynamic SpEL

```java
public interface UserView {
    @Value("#{target.firstName + ' ' + target.lastName}")
    String getFullName();
    
    // Access nested
    @Value("#{target.address.city}")
    String getCity();
}
```

### 2.3 DTO Projection (Class-based)

```java
// DTO record
public record UserDto(Long id, String firstName, String email) {}

// JPQL constructor expression
@Query("SELECT new org.example.dto.UserDto(u.id, u.firstName, u.email) " +
       "FROM User u WHERE u.active = true")
List<UserDto> findActiveUserDtos();

// Or Spring Data auto-mapping (column name must match constructor param names)
List<UserDto> findByActive(boolean active);
```

### 2.4 Dynamic Projection

```java
// Single repository method, caller decides projection type
<T> List<T> findByDepartment(String department, Class<T> type);

// Usage
List<UserSummary> summaries = repo.findByDepartment("IT", UserSummary.class);
List<UserDto> dtos = repo.findByDepartment("IT", UserDto.class);
List<User> entities = repo.findByDepartment("IT", User.class); // full entity
```

### 2.5 Native Query + Projection

```java
public interface OrderStatsProjection {
    String getStatus();
    Long getCount();
    BigDecimal getTotalAmount();
}

@Query(value = """
    SELECT o.status, COUNT(*) as count, SUM(o.total_amount) as total_amount
    FROM orders o
    GROUP BY o.status
    """, nativeQuery = true)
List<OrderStatsProjection> getOrderStats();
```

---

## 3. Specifications & Querydsl

### 3.1 Specification Pattern (Type-safe dynamic queries)

```java
// Dependencies
// spring-boot-starter-data-jpa already includes Criteria API

// Repository must extend JpaSpecificationExecutor
public interface UserRepository extends JpaRepository<User, Long>,
    JpaSpecificationExecutor<User> {}

// Specification factory (static factory methods)
public class UserSpecs {
    
    public static Specification<User> hasFirstName(String firstName) {
        return (root, query, cb) -> firstName == null ? null :
            cb.like(cb.lower(root.get("firstName")), "%" + firstName.toLowerCase() + "%");
    }
    
    public static Specification<User> hasEmail(String email) {
        return (root, query, cb) -> email == null ? null :
            cb.equal(root.get("email"), email);
    }
    
    public static Specification<User> isActive() {
        return (root, query, cb) -> cb.isTrue(root.get("active"));
    }
    
    public static Specification<User> createdAfter(LocalDate date) {
        return (root, query, cb) -> date == null ? null :
            cb.greaterThanOrEqualTo(root.get("createdAt"), date.atStartOfDay());
    }
    
    // Join
    public static Specification<User> inDepartment(String dept) {
        return (root, query, cb) -> {
            Join<User, Department> join = root.join("department", JoinType.INNER);
            return cb.equal(join.get("name"), dept);
        };
    }
    
    // Distinct (important with joins)
    public static Specification<User> withDistinct() {
        return (root, query, cb) -> {
            query.distinct(true);
            return null;
        };
    }
}

// Service usage
public Page<User> searchUsers(UserSearchRequest req, Pageable pageable) {
    Specification<User> spec = Specification
        .where(UserSpecs.isActive())
        .and(UserSpecs.hasFirstName(req.getFirstName()))
        .and(UserSpecs.hasEmail(req.getEmail()))
        .and(UserSpecs.createdAfter(req.getCreatedAfter()))
        .and(UserSpecs.withDistinct());
    
    return userRepository.findAll(spec, pageable);
}
```

### 3.2 Querydsl (More powerful, compile-time safe)

```xml
<!-- pom.xml -->
<dependency>
    <groupId>com.querydsl</groupId>
    <artifactId>querydsl-jpa</artifactId>
    <classifier>jakarta</classifier>
</dependency>

<!-- APT plugin to generate Q-classes -->
<plugin>
    <groupId>com.mysema.maven</groupId>
    <artifactId>apt-maven-plugin</artifactId>
    <version>1.1.3</version>
    <executions>
        <execution>
            <goals><goal>process</goal></goals>
            <configuration>
                <outputDirectory>target/generated-sources/java</outputDirectory>
                <processor>com.querydsl.apt.jpa.JPAAnnotationProcessor</processor>
            </configuration>
        </execution>
    </executions>
</plugin>
```

```java
// Repository
public interface UserRepository extends JpaRepository<User, Long>,
    QuerydslPredicateExecutor<User> {}

// Service
public Page<User> search(UserSearchRequest req, Pageable pageable) {
    QUser u = QUser.user;
    
    BooleanBuilder predicate = new BooleanBuilder();
    if (req.getFirstName() != null)
        predicate.and(u.firstName.containsIgnoreCase(req.getFirstName()));
    if (req.getEmail() != null)
        predicate.and(u.email.eq(req.getEmail()));
    if (req.getActive() != null)
        predicate.and(u.active.eq(req.getActive()));
    if (req.getMinAge() != null)
        predicate.and(u.age.goe(req.getMinAge()));
    
    return userRepository.findAll(predicate, pageable);
}

// Complex join query with JPAQueryFactory
@Service
public class UserQueryService {
    @PersistenceContext
    private EntityManager em;
    
    public List<UserOrderSummary> findUsersWithOrderCount() {
        JPAQueryFactory qf = new JPAQueryFactory(em);
        QUser u = QUser.user;
        QOrder o = QOrder.order;
        
        return qf
            .select(Projections.constructor(UserOrderSummary.class,
                u.id, u.firstName, o.count()))
            .from(u)
            .leftJoin(o).on(o.customer.id.eq(u.id))
            .groupBy(u.id, u.firstName)
            .orderBy(o.count().desc())
            .fetch();
    }
}
```

---

## 4. Spring Cache Deep Dive

### 4.1 Basic Setup

```yaml
# application.yml
spring:
  cache:
    type: redis  # none | simple | redis | caffeine | jcache | hazelcast
  data:
    redis:
      host: localhost
      port: 6379
```

```java
@SpringBootApplication
@EnableCaching
public class Application {}
```

### 4.2 Cache Annotations

```java
@Service
public class ProductService {

    // Cache result — key = "products::123"
    @Cacheable(value = "products", key = "#id")
    public Product findById(Long id) {
        return productRepository.findById(id).orElseThrow();
    }
    
    // Conditional cache
    @Cacheable(value = "products", key = "#id",
               condition = "#id > 0",
               unless = "#result.price == 0")  // unless uses result
    public Product findByIdConditional(Long id) { ... }
    
    // Update cache on save
    @CachePut(value = "products", key = "#product.id")
    public Product save(Product product) {
        return productRepository.save(product);
    }
    
    // Evict single entry
    @CacheEvict(value = "products", key = "#id")
    public void deleteById(Long id) {
        productRepository.deleteById(id);
    }
    
    // Evict all entries in cache
    @CacheEvict(value = "products", allEntries = true)
    public void evictAll() {}
    
    // Evict before method runs
    @CacheEvict(value = "products", key = "#id", beforeInvocation = true)
    public void deleteByIdForced(Long id) { ... }
    
    // Multiple cache operations
    @Caching(
        put = { @CachePut(value = "products", key = "#result.id") },
        evict = { @CacheEvict(value = "productList", allEntries = true) }
    )
    public Product update(Product product) { ... }
}
```

### 4.3 Redis Cache Configuration (TTL per cache)

```java
@Configuration
public class CacheConfig {

    @Bean
    public RedisCacheManagerBuilderCustomizer redisCacheManagerBuilderCustomizer() {
        return builder -> builder
            .withCacheConfiguration("products",
                RedisCacheConfiguration.defaultCacheConfig()
                    .entryTtl(Duration.ofMinutes(30))
                    .serializeValuesWith(
                        RedisSerializationContext.SerializationPair.fromSerializer(
                            new GenericJackson2JsonRedisSerializer())))
            .withCacheConfiguration("users",
                RedisCacheConfiguration.defaultCacheConfig()
                    .entryTtl(Duration.ofHours(1)))
            .withCacheConfiguration("config",
                RedisCacheConfiguration.defaultCacheConfig()
                    .entryTtl(Duration.ofDays(1)));
    }
    
    @Bean
    public RedisCacheConfiguration defaultCacheConfig() {
        return RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(10))
            .disableCachingNullValues()  // don't cache null → will always call DB
            .computePrefixWith(name -> name + "::");
    }
}
```

### 4.4 Multi-Level Cache (L1 Caffeine + L2 Redis)

```xml
<dependency>
    <groupId>com.github.ben-manes.caffeine</groupId>
    <artifactId>caffeine</artifactId>
</dependency>
```

```java
@Configuration
public class MultiLevelCacheConfig {

    @Bean
    public CacheManager cacheManager(RedisConnectionFactory redisConnectionFactory) {
        // L1 - Local Caffeine
        CaffeineCacheManager l1 = new CaffeineCacheManager();
        l1.setCaffeine(Caffeine.newBuilder()
            .maximumSize(1000)
            .expireAfterWrite(Duration.ofMinutes(5))
            .recordStats());
        
        // L2 - Redis
        RedisCacheManager l2 = RedisCacheManager.builder(redisConnectionFactory)
            .cacheDefaults(RedisCacheConfiguration.defaultCacheConfig()
                .entryTtl(Duration.ofMinutes(30)))
            .build();
        
        return new MultiLevelCacheManager(l1, l2);
    }
}

// Custom multi-level cache manager
public class MultiLevelCacheManager implements CacheManager {
    private final CacheManager l1;
    private final CacheManager l2;
    
    @Override
    public Cache getCache(String name) {
        return new MultiLevelCache(l1.getCache(name), l2.getCache(name));
    }
    
    @Override
    public Collection<String> getCacheNames() {
        return l2.getCacheNames();
    }
}

public class MultiLevelCache implements Cache {
    private final Cache l1;  // Caffeine
    private final Cache l2;  // Redis
    
    @Override
    public ValueWrapper get(Object key) {
        // Try L1 first
        ValueWrapper v = l1.get(key);
        if (v != null) return v;
        
        // Fallback to L2
        v = l2.get(key);
        if (v != null) {
            l1.put(key, v.get()); // populate L1
        }
        return v;
    }
    
    @Override
    public void put(Object key, Object value) {
        l1.put(key, value);
        l2.put(key, value);
    }
    
    @Override
    public void evict(Object key) {
        l1.evict(key);
        l2.evict(key);
    }
    // ... other methods
}
```

### 4.5 Cache Key Generation

```java
// Custom KeyGenerator
@Component("tenantAwareKeyGenerator")
public class TenantAwareKeyGenerator implements KeyGenerator {
    @Override
    public Object generate(Object target, Method method, Object... params) {
        String tenantId = TenantContext.getCurrentTenant();
        return tenantId + ":" + target.getClass().getSimpleName() + 
               ":" + method.getName() + ":" + Arrays.toString(params);
    }
}

// Usage
@Cacheable(value = "products", keyGenerator = "tenantAwareKeyGenerator")
public List<Product> findAll() { ... }
```

### 4.6 Cache Serialization & Null Safety

```java
// Avoid ClassCastException with proper Jackson config
@Bean
public RedisSerializer<Object> redisSerializer() {
    ObjectMapper mapper = new ObjectMapper();
    mapper.setVisibility(PropertyAccessor.ALL, JsonAutoDetect.Visibility.ANY);
    mapper.activateDefaultTyping(
        mapper.getPolymorphicTypeValidator(),
        ObjectMapper.DefaultTyping.NON_FINAL,  // store class name in JSON
        JsonTypeInfo.As.PROPERTY
    );
    mapper.registerModule(new JavaTimeModule());
    return new GenericJackson2JsonRedisSerializer(mapper);
}
```

---

## 5. Multiple Datasources

### 5.1 Two DataSources Configuration

```yaml
# application.yml
spring:
  datasource:
    primary:
      url: jdbc:postgresql://localhost:5432/primary_db
      username: user
      password: pass
      driver-class-name: org.postgresql.Driver
      hikari:
        maximum-pool-size: 20
        connection-timeout: 30000
    secondary:
      url: jdbc:mysql://localhost:3306/analytics_db
      username: user
      password: pass
      driver-class-name: com.mysql.cj.jdbc.Driver
      hikari:
        maximum-pool-size: 10
```

```java
// Primary datasource config
@Configuration
@EnableTransactionManagement
@EnableJpaRepositories(
    basePackages = "org.example.repository.primary",
    entityManagerFactoryRef = "primaryEntityManagerFactory",
    transactionManagerRef = "primaryTransactionManager"
)
public class PrimaryDataSourceConfig {

    @Bean
    @Primary
    @ConfigurationProperties("spring.datasource.primary")
    public DataSource primaryDataSource() {
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }

    @Bean
    @Primary
    public LocalContainerEntityManagerFactoryBean primaryEntityManagerFactory(
            @Qualifier("primaryDataSource") DataSource dataSource,
            JpaProperties jpaProperties) {
        
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(dataSource);
        factory.setPackagesToScan("org.example.domain.primary");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        
        Map<String, Object> props = new HashMap<>(jpaProperties.getProperties());
        props.put("hibernate.hbm2ddl.auto", "validate");
        props.put("hibernate.dialect", "org.hibernate.dialect.PostgreSQLDialect");
        factory.setJpaPropertyMap(props);
        
        return factory;
    }

    @Bean
    @Primary
    public PlatformTransactionManager primaryTransactionManager(
            @Qualifier("primaryEntityManagerFactory") EntityManagerFactory emf) {
        return new JpaTransactionManager(emf);
    }
}

// Secondary datasource config (similar, without @Primary)
@Configuration
@EnableJpaRepositories(
    basePackages = "org.example.repository.secondary",
    entityManagerFactoryRef = "secondaryEntityManagerFactory",
    transactionManagerRef = "secondaryTransactionManager"
)
public class SecondaryDataSourceConfig {

    @Bean
    @ConfigurationProperties("spring.datasource.secondary")
    public DataSource secondaryDataSource() {
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }
    
    @Bean
    public LocalContainerEntityManagerFactoryBean secondaryEntityManagerFactory(
            @Qualifier("secondaryDataSource") DataSource dataSource) {
        // ... similar config with MySQL dialect
    }
    
    @Bean
    public PlatformTransactionManager secondaryTransactionManager(
            @Qualifier("secondaryEntityManagerFactory") EntityManagerFactory emf) {
        return new JpaTransactionManager(emf);
    }
}
```

### 5.2 Routing DataSource (Read/Write Splitting)

```java
// Routing key
public enum DataSourceType { MASTER, REPLICA }

// Thread-local holder
public class DataSourceContextHolder {
    private static final ThreadLocal<DataSourceType> context = new ThreadLocal<>();
    
    public static void setDataSource(DataSourceType type) { context.set(type); }
    public static DataSourceType getDataSource() { 
        return context.get() == null ? DataSourceType.MASTER : context.get(); 
    }
    public static void clear() { context.remove(); }
}

// Routing datasource
public class RoutingDataSource extends AbstractRoutingDataSource {
    @Override
    protected Object determineCurrentLookupKey() {
        return DataSourceContextHolder.getDataSource();
    }
}

// Config
@Bean
public DataSource routingDataSource(
        @Qualifier("masterDataSource") DataSource master,
        @Qualifier("replicaDataSource") DataSource replica) {
    Map<Object, Object> targetDataSources = Map.of(
        DataSourceType.MASTER, master,
        DataSourceType.REPLICA, replica
    );
    RoutingDataSource routing = new RoutingDataSource();
    routing.setTargetDataSources(targetDataSources);
    routing.setDefaultTargetDataSource(master);
    return routing;
}

// AOP: @ReadOnly → route to replica
@Aspect
@Component
public class DataSourceRoutingAspect {
    
    @Around("@annotation(readOnly)")
    public Object route(ProceedingJoinPoint pjp, ReadOnly readOnly) throws Throwable {
        DataSourceContextHolder.setDataSource(DataSourceType.REPLICA);
        try {
            return pjp.proceed();
        } finally {
            DataSourceContextHolder.clear();
        }
    }
}

@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface ReadOnly {}

// Usage
@ReadOnly
@Transactional(readOnly = true)
public List<Product> findAll() { ... }
```

---

## 6. Flyway & Liquibase

### 6.1 Flyway

```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
</dependency>
```

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true    # for existing DB
    baseline-version: 0
    validate-on-migrate: true
    out-of-order: false          # strict ordering
    table: flyway_schema_history
    schemas: public
```

```
resources/db/migration/
├── V1__init_schema.sql
├── V2__add_user_table.sql
├── V2.1__add_user_index.sql
├── V3__add_order_table.sql
├── R__refresh_views.sql         ← Repeatable: runs when checksum changes
└── U3__undo_add_order_table.sql ← Undo (Flyway Pro)
```

```sql
-- V1__init_schema.sql
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name  VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_active ON users(active) WHERE active = TRUE;

-- V2__add_department.sql
ALTER TABLE users ADD COLUMN department_id BIGINT;
ALTER TABLE users ADD CONSTRAINT fk_users_dept
    FOREIGN KEY (department_id) REFERENCES departments(id);
```

```java
// Java-based migration
@Component
public class V4__seed_data extends BaseJavaMigration {
    
    @Override
    public void migrate(Context context) throws Exception {
        try (Statement stmt = context.getConnection().createStatement()) {
            stmt.execute("INSERT INTO config (key, value) VALUES " +
                         "('APP_VERSION', '1.0'), ('FEATURE_X', 'true')");
        }
    }
}
```

### 6.2 Liquibase

```xml
<dependency>
    <groupId>org.liquibase</groupId>
    <artifactId>liquibase-core</artifactId>
</dependency>
```

```yaml
spring:
  liquibase:
    change-log: classpath:db/changelog/db.changelog-master.yaml
    enabled: true
    default-schema: public
```

```yaml
# db/changelog/db.changelog-master.yaml
databaseChangeLog:
  - includeAll:
      path: db/changelog/changes/
      
# db/changelog/changes/0001-create-users.yaml
databaseChangeLog:
  - changeSet:
      id: 0001
      author: dev
      changes:
        - createTable:
            tableName: users
            columns:
              - column:
                  name: id
                  type: BIGINT
                  autoIncrement: true
                  constraints:
                    primaryKey: true
              - column:
                  name: email
                  type: VARCHAR(255)
                  constraints:
                    nullable: false
                    unique: true
              - column:
                  name: created_at
                  type: TIMESTAMP
                  defaultValueComputed: CURRENT_TIMESTAMP
      rollback:
        - dropTable:
            tableName: users
```

```xml
<!-- XML format with preconditions -->
<databaseChangeLog xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
    http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.20.xsd">

    <changeSet id="0002" author="dev">
        <preConditions onFail="MARK_RAN">
            <not>
                <columnExists tableName="users" columnName="phone"/>
            </not>
        </preConditions>
        <addColumn tableName="users">
            <column name="phone" type="VARCHAR(20)"/>
        </addColumn>
        <rollback>
            <dropColumn tableName="users" columnName="phone"/>
        </rollback>
    </changeSet>
</databaseChangeLog>
```

**Flyway vs Liquibase:**

| Feature | Flyway | Liquibase |
|---------|--------|-----------|
| Format | SQL/Java | SQL/XML/YAML/JSON |
| Versioning | Filename (V1__) | ChangeSet ID |
| Rollback | Pro only | Built-in (rollback tag) |
| Preconditions | Limited | Rich |
| Diff generation | No | Yes (generateChangeLog) |
| Learning curve | Low | Higher |
| Best for | Simple, SQL-focused | Complex, multi-format |

---

## 7. R2DBC Reactive Data

### 7.1 Setup

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-r2dbc</artifactId>
</dependency>
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>r2dbc-postgresql</artifactId>
</dependency>
```

```yaml
spring:
  r2dbc:
    url: r2dbc:postgresql://localhost:5432/mydb
    username: user
    password: pass
    pool:
      initial-size: 5
      max-size: 20
      max-idle-time: 30m
```

### 7.2 Entity & Repository

```java
// R2DBC entity — no @OneToMany, no lazy loading
@Table("products")
public class Product {
    @Id
    private Long id;
    private String name;
    private BigDecimal price;
    
    @Column("category_id")
    private Long categoryId;  // foreign key as ID only
}

// Repository — returns Mono/Flux
public interface ProductRepository extends ReactiveCrudRepository<Product, Long>,
    ReactiveSortingRepository<Product, Long> {
    
    Flux<Product> findByPriceGreaterThan(BigDecimal price);
    Mono<Product> findByName(String name);
    
    @Query("SELECT * FROM products WHERE category_id = :categoryId AND price < :maxPrice")
    Flux<Product> findByCategoryAndPriceBelow(
        @Param("categoryId") Long categoryId,
        @Param("maxPrice") BigDecimal maxPrice
    );
}
```

### 7.3 R2dbcEntityTemplate (Complex queries)

```java
@Service
public class ProductService {
    
    @Autowired
    private R2dbcEntityTemplate template;
    
    public Flux<Product> search(String name, BigDecimal minPrice) {
        return template.select(Product.class)
            .matching(Query.query(
                Criteria.where("name").like("%" + name + "%")
                    .and("price").greaterThan(minPrice)
            ).sort(Sort.by("price").ascending())
             .limit(50))
            .all();
    }
    
    public Mono<Product> upsert(Product product) {
        return template.upsert(product);
    }
}
```

### 7.4 Reactive Transaction

```java
@Service
public class OrderService {
    
    @Autowired
    private TransactionalOperator transactionalOperator;
    @Autowired
    private OrderRepository orderRepository;
    @Autowired
    private InventoryRepository inventoryRepository;
    
    // Declarative
    @Transactional
    public Mono<Order> placeOrder(CreateOrderRequest req) {
        return inventoryRepository.decrementStock(req.getProductId(), req.getQuantity())
            .flatMap(updated -> {
                if (!updated) return Mono.error(new InsufficientStockException());
                Order order = Order.from(req);
                return orderRepository.save(order);
            });
    }
    
    // Programmatic
    public Mono<Order> placeOrderProgrammatic(CreateOrderRequest req) {
        Mono<Order> operation = inventoryRepository
            .decrementStock(req.getProductId(), req.getQuantity())
            .flatMap(updated -> {
                if (!updated) return Mono.error(new InsufficientStockException());
                return orderRepository.save(Order.from(req));
            });
        
        return transactionalOperator.transactional(operation);
    }
}
```

### 7.5 Handling Relations in R2DBC

```java
// R2DBC doesn't support JPA-style joins — handle in service layer
@Service
public class ProductDetailService {
    
    @Autowired private ProductRepository productRepo;
    @Autowired private CategoryRepository categoryRepo;
    @Autowired private ReviewRepository reviewRepo;
    
    public Mono<ProductDetailDto> getProductDetail(Long productId) {
        return productRepo.findById(productId)
            .flatMap(product ->
                Mono.zip(
                    categoryRepo.findById(product.getCategoryId()),
                    reviewRepo.findByProductId(productId).collectList()
                ).map(tuple -> ProductDetailDto.builder()
                    .product(product)
                    .category(tuple.getT1())
                    .reviews(tuple.getT2())
                    .build())
            );
    }
    
    // Bulk fetch to avoid N+1 (manual batch)
    public Flux<ProductWithCategory> findAllWithCategory() {
        return productRepo.findAll()
            .collectList()
            .flatMapMany(products -> {
                Set<Long> categoryIds = products.stream()
                    .map(Product::getCategoryId)
                    .collect(Collectors.toSet());
                
                return categoryRepo.findAllById(categoryIds)
                    .collectMap(Category::getId)
                    .flatMapMany(categoryMap ->
                        Flux.fromIterable(products)
                            .map(p -> new ProductWithCategory(p, categoryMap.get(p.getCategoryId())))
                    );
            });
    }
}
```

---

## Summary: JPA Best Practices

| Problem | Solution | When to Use |
|---------|----------|-------------|
| N+1 on single entity | @EntityGraph / JOIN FETCH | Complex object graph, single result |
| N+1 on list + pagination | ID-first pagination + secondary fetch | Collection + paging |
| Global N+1 mitigation | `default_batch_fetch_size: 100` | All collections globally |
| Dynamic queries | Specification / Querydsl | Search/filter APIs |
| Partial data fetch | Interface/DTO Projections | List views, reporting |
| Multi-tenant routing | Routing DataSource + AOP | SaaS, read/write split |
| Schema migration | Flyway (simple) / Liquibase (complex) | All production apps |
| Reactive stack | R2DBC + ReactiveCrudRepository | High concurrency, WebFlux apps |
