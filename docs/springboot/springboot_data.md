---
title: "Spring Boot Data Layer – Deep Dive"
topic: springboot
level: mixed
review_status: needs_review
content_updated: 2026-07-27
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# Spring Boot Data Layer – Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Production – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)

## What – Data layer là gì?

**Data layer** *(tầng truy cập và lưu trữ dữ liệu)* là phần nối nghiệp vụ với database và **cache** *(bộ nhớ đệm)*. Trong Spring Boot, lớp này thường kết hợp **JPA** *(Jakarta Persistence API – chuẩn ánh xạ object–relational)*, Spring Data **repository** *(giao diện kho dữ liệu)*, **projection** *(hình chiếu chỉ lấy dữ liệu cần)*, truy vấn động, **schema migration** *(thay đổi cấu trúc database có version)* và có thể dùng **R2DBC** *(Reactive Relational Database Connectivity – truy cập SQL bất đồng bộ, không blocking)*.

> 💡 **Giải thích dễ hiểu:**
> Data layer giống quầy thủ thư: nghiệp vụ chỉ nêu cần cuốn nào, còn quầy biết tìm ở kệ/database, lấy bản tóm tắt/projection, dùng bản sao nhanh/cache và ghi sổ thay đổi schema. Quầy nhanh nhưng đưa sai sách hoặc dùng bản cũ thì toàn hệ thống vẫn sai.

## Why – Vì sao cần thiết kế riêng?

- Cô lập domain/service khỏi chi tiết SQL, driver và persistence provider.
- Kiểm soát số query, lượng cột/row, transaction boundary và consistency thay vì chỉ “repository chạy được”.
- Quản lý schema có version, tái lập được giữa local, CI và production.
- Chọn đúng mô hình blocking JDBC/JPA hoặc reactive R2DBC theo toàn bộ request path.

## Components – Các mảnh ghép chính

| Thành phần | Vai trò | Rủi ro chính |
|------------|---------|--------------|
| JPA/Hibernate | ORM *(ánh xạ object–relational)*, **persistence context** *(vùng quản lý entity)*, **dirty checking** *(tự phát hiện entity thay đổi)* | N+1, lazy loading ngoài transaction, query/flush ngoài dự kiến |
| Projection/Specification/Querydsl | Giới hạn dữ liệu và tạo truy vấn động | Mapping sai, join phình dữ liệu, count query đắt |
| Spring Cache | Abstraction cho cache provider | Stale data, cache stampede, key/serialization không ổn định |
| DataSource/transaction manager | Connection pool và transaction | Cạn pool, chọn nhầm datasource, transaction không nguyên tử qua hai DB |
| Flyway/Liquibase | Migration schema có lịch sử | Drift, sửa migration đã chạy, lock/deploy lỗi |
| R2DBC | SQL reactive qua `Publisher` | Blocking lẫn vào event loop, driver/tooling khác JPA |

## When – Chọn công cụ nào?

- Chọn JPA khi domain có aggregate/quan hệ rõ, CRUD nhiều và team cần persistence context/dirty checking.
- Chọn projection cho read model/list/report không cần sửa entity; chọn Specification cho bộ lọc vừa phải, Querydsl/custom repository cho query phức tạp cần type safety.
- Chỉ thêm cache khi đã đo bottleneck và chấp nhận được consistency/invalidations.
- Dùng nhiều datasource khi có ranh giới dữ liệu thật sự; không dùng chỉ để che một schema thiết kế kém.
- Chọn R2DBC khi toàn bộ stack reactive và workload có nhiều I/O đồng thời; không chọn vì giả định “reactive luôn nhanh hơn”.

## Mục lục

1. [JPA N+1 Problem & Solutions](#1-jpa-n1-problem--solutions)
2. [Projections – Interface, DTO, Dynamic](#2-projections)
3. [Specifications & Querydsl](#3-specifications--querydsl)
4. [Spring Cache Deep Dive](#4-spring-cache-deep-dive)
5. [Multiple Datasources](#5-multiple-datasources)
6. [Flyway & Liquibase](#6-flyway--liquibase)
7. [R2DBC Reactive Data](#7-r2dbc-reactive-data)
8. [Compare & Trade-offs](#compare--trade-offs)
9. [Production Checklist](#production--checklist)
10. [Ghi chú](#ghi-chú--chủ-đề-tiếp-theo)

---

## 1. JPA N+1 Problem & Solutions

**N+1 problem** *(một query lấy danh sách rồi phát sinh thêm N query theo từng phần tử)* xuất hiện khi association chưa được tải nhưng code lần lượt truy cập nó. `LAZY` không tự gây N+1; vấn đề là fetch plan không khớp use case và việc duyệt object graph kích hoạt nhiều round-trip.

> 💡 **Giải thích dễ hiểu:**
> Thay vì đưa thủ thư một danh sách 100 cuốn để lấy trong một lượt, ứng dụng hỏi danh sách trước rồi quay lại hỏi từng cuốn 100 lần. Dữ liệu vẫn đúng nhưng thời gian chờ và tải database tăng mạnh.

### 1.1 Reproduce N+1

```java
// Entity
@Entity
public class Order {
    @Id @GeneratedValue
    private Long id;
    private String status;

    // @ManyToOne mặc định là EAGER theo Jakarta Persistence; khai LAZY có chủ đích.
    @ManyToOne(fetch = FetchType.LAZY)
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

// Lưu ý 1: collection fetch join + Pageable có thể bị paginate trong memory, rất tốn RAM/CPU.
// Bật hibernate.query.fail_on_pagination_over_collection_fetch=true để fail fast.
// Lưu ý 2: fetch song song nhiều collection dạng bag/List có thể ném
// MultipleBagFetchException và luôn có nguy cơ Cartesian product.
// Đổi List thành Set không xóa chi phí Cartesian; thường tách query/batch fetch tốt hơn.
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
    if (idPage.isEmpty()) return Page.empty(pageable);

    List<Order> fetched = orderRepository.findByIdsWithItems(idPage.getContent());
    Map<Long, Order> byId = fetched.stream()
        .collect(Collectors.toMap(Order::getId, Function.identity()));

    // IN (...) không bảo đảm giữ thứ tự của trang ID.
    List<Order> ordered = idPage.getContent().stream()
        .map(byId::get)
        .filter(Objects::nonNull)
        .toList();
    return new PageImpl<>(ordered, pageable, idPage.getTotalElements());
}
```

Hai bước giữ pagination ở database và fetch collection theo đúng ID của trang. Luôn có `ORDER BY` ổn định (thường thêm ID làm tie-breaker), xử lý trang rỗng và khôi phục thứ tự vì SQL `IN` không cam kết thứ tự.

```yaml
spring:
  jpa:
    properties:
      hibernate:
        query:
          fail_on_pagination_over_collection_fetch: true
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

`@EntityGraph` tách fetch plan khỏi JPQL và phù hợp khi cùng entity cần nhiều “góc nhìn” tải dữ liệu. Với fetch graph, attribute trong graph được tải eagerly cho query đó; vẫn phải đo SQL thực tế và tránh fetch nhiều collection song song.

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

Batch fetching không biến N query thành đúng 1 query; nó gom nhiều ID vào một số ít câu `IN (...)`. Batch quá lớn có thể chạm giới hạn parameter/query plan của database, vì vậy 50/100 chỉ là điểm benchmark.

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

`SUBSELECT` là extension của Hibernate cho collection: khi một collection được khởi tạo, Hibernate có thể tải collection cùng role của các owner trong persistence context bằng một secondary select. Nó hữu ích cho một trang owner nhưng có thể kéo nhiều dữ liệu ngoài dự kiến nếu persistence context quá lớn.

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
    org.hibernate.orm.jdbc.bind: TRACE  # Hibernate 6+; kiểm tra logger theo version
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

Statistics và bind-value logging hữu ích ở test/staging nhưng có overhead, tạo log lớn và có thể lộ dữ liệu nhạy cảm. Production nên ưu tiên Micrometer/APM, slow-query log đã che dữ liệu và integration test đếm statement cho các endpoint quan trọng.

---

## 2. Projections

Projection tạo read model chỉ gồm dữ liệu caller cần. Interface projection thường được Spring Data dựng bằng proxy từ `Tuple`; class/record projection dùng constructor. Nó giảm cột và tránh serialize entity graph, nhưng nested property vẫn có thể tạo join và materialize toàn bộ association.

> 💡 **Giải thích dễ hiểu:**
> Entity giống hồ sơ đầy đủ trong kho; projection giống bản trích lục chỉ có tên và email. Bản trích lục nhẹ hơn, nhưng nếu yêu cầu “địa chỉ.thành phố”, hệ thống vẫn phải mở ngăn địa chỉ liên quan.

### 2.1 Interface Projection (Closed)

```java
// Only fetch needed columns → SELECT id, first_name, last_name FROM users
public interface UserSummary {
    Long getId();
    String getFirstName();
    String getLastName();

    // Default method chỉ dùng accessor của projection nên vẫn là closed projection.
    default String getFullName() {
        return getFirstName() + " " + getLastName();
    }
}

// Repository
List<UserSummary> findByActive(boolean active);
<T> Optional<T> findProjectedById(Long id, Class<T> type);
```

### 2.2 Interface Projection (Open) – Dynamic SpEL

```java
public interface UserView {
    @Value("#{target.firstName + ' ' + target.lastName}")
    String getFullName();

    // Access nested
    @Value("#{target.address?.city}")
    String getCity();
}
```

Có `@Value`/SpEL thì đây là **open projection**: Spring Data không thể chắc chắn toàn bộ field cần thiết để tối ưu select như closed projection. Expression phức tạp nên chuyển sang DTO/query rõ ràng hoặc gọi một Spring bean có test.

### 2.3 DTO Projection (Class-based)

```java
// DTO record
public record UserDto(Long id, String firstName, String email) {}

// JPQL constructor expression
@Query("SELECT new org.example.dto.UserDto(u.id, u.firstName, u.email) " +
       "FROM User u WHERE u.active = true")
List<UserDto> findActiveUserDtos();

// Derived query/DTO rewriting có thể map constructor khi property và tham số khớp.
// DTO cần một constructor rõ ràng (hoặc đánh dấu @PersistenceCreator khi có nhiều constructor).
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
    SELECT o.status, COUNT(*) AS count, SUM(o.total_amount) AS totalAmount
    FROM orders o
    GROUP BY o.status
    """, nativeQuery = true)
List<OrderStatsProjection> getOrderStats();
```

Với JPQL DTO, constructor expression dùng fully qualified class name; Spring Data có thể rewrite một số query nhưng sẽ không rewrite nếu query đã có constructor expression. Native query phụ thuộc alias/case conversion của database/provider; alias theo đúng accessor hoặc dùng `@SqlResultSetMapping` khi type/thứ tự không khớp.

---

## 3. Specifications & Querydsl

**Specification** *(đặc tả điều kiện truy vấn có thể ghép)* bọc JPA Criteria predicate để tái sử dụng filter. Querydsl tạo Q-type lúc compile và cho fluent API type-safe hơn chuỗi property, đổi lại build/codegen phức tạp hơn.

> 💡 **Giải thích dễ hiểu:**
> Mỗi Specification giống một tấm lọc: “đang active”, “email bằng…”, “tạo sau ngày…”. Có thể ghép các tấm lọc mà không viết một repository method cho mọi tổ hợp.

### 3.1 Specification Pattern (Composable dynamic queries)

```java
// Dependencies
// spring-boot-starter-data-jpa already includes Criteria API

// Repository must extend JpaSpecificationExecutor
public interface UserRepository extends JpaRepository<User, Long>,
    JpaSpecificationExecutor<User> {}

// Specification factory (static factory methods)
public class UserSpecs {

    public static Specification<User> hasFirstName(String firstName) {
        if (firstName == null || firstName.isBlank()) return Specification.unrestricted();
        return (root, query, cb) -> cb.like(
            cb.lower(root.get("firstName")),
            "%" + firstName.toLowerCase(Locale.ROOT) + "%");
    }

    public static Specification<User> hasEmail(String email) {
        if (email == null) return Specification.unrestricted();
        return (root, query, cb) -> cb.equal(root.get("email"), email);
    }

    public static Specification<User> isActive() {
        return (root, query, cb) -> cb.isTrue(root.get("active"));
    }

    public static Specification<User> createdAfter(LocalDate date) {
        if (date == null) return Specification.unrestricted();
        return (root, query, cb) ->
            cb.greaterThanOrEqualTo(root.get("createdAt"), date.atStartOfDay());
    }

    // Join
    public static Specification<User> inDepartment(String dept) {
        if (dept == null) return Specification.unrestricted();
        return (root, query, cb) -> {
            Join<User, Department> join = root.join("department", JoinType.INNER);
            return cb.equal(join.get("name"), dept);
        };
    }

    // Distinct (important with joins)
    public static Specification<User> withDistinct() {
        return (root, query, cb) -> {
            query.distinct(true);
            return cb.conjunction();
        };
    }
}

// Service usage
public Page<User> searchUsers(UserSearchRequest req, Pageable pageable) {
    Specification<User> spec = Specification.allOf(
        UserSpecs.isActive(),
        UserSpecs.hasFirstName(req.getFirstName()),
        UserSpecs.hasEmail(req.getEmail()),
        UserSpecs.createdAfter(req.getCreatedAfter()),
        UserSpecs.withDistinct());

    return userRepository.findAll(spec, pageable);
}
```

`Specification.unrestricted()`/`allOf(...)` là API của Spring Data JPA hiện hành; với nhánh cũ hơn, dùng helper non-null tương đương. Tránh trả `null` vì hỗ trợ nullable Specification đang bị loại dần. Join to-many + `distinct` có thể làm count query đắt hoặc sai kỳ vọng; query phức tạp nên tách content/count trong custom repository và kiểm thử cả pagination.

### 3.2 Querydsl (More powerful, compile-time safe)

```xml
<!-- pom.xml; khóa querydsl.version tương thích với Spring Boot/Jakarta của dự án -->
<dependency>
    <groupId>com.querydsl</groupId>
    <artifactId>querydsl-jpa</artifactId>
    <version>${querydsl.version}</version>
    <classifier>jakarta</classifier>
</dependency>
<dependency>
    <groupId>com.querydsl</groupId>
    <artifactId>querydsl-apt</artifactId>
    <version>${querydsl.version}</version>
    <classifier>jakarta</classifier>
    <scope>provided</scope>
</dependency>

<!-- Dùng annotation processor của compiler; tránh apt-maven-plugin cũ. -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <annotationProcessorPaths>
            <path>
                <groupId>com.querydsl</groupId>
                <artifactId>querydsl-apt</artifactId>
                <version>${querydsl.version}</version>
                <classifier>jakarta</classifier>
            </path>
            <path>
                <groupId>jakarta.persistence</groupId>
                <artifactId>jakarta.persistence-api</artifactId>
                <version>${jakarta-persistence.version}</version>
            </path>
        </annotationProcessorPaths>
    </configuration>
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

Querydsl upstream có tốc độ bảo trì chậm và cộng đồng có fork OpenFeign; Spring Data hỗ trợ fork ở mức best-effort. Chốt tọa độ/version trong dependency management và CI kiểm tra Q-class. Không expose `QuerydslPredicateExecutor` trực tiếp cho input HTTP không giới hạn: whitelist field/operator, giới hạn sort/page size và tránh cho client dựng query quá đắt.

---

## 4. Spring Cache Deep Dive

Spring Cache là **abstraction** *(lớp giao diện thống nhất)*, không phải cache store. `CacheManager` kết nối annotation với Redis, Caffeine hoặc provider khác. Thiết kế phải xác định key, TTL, invalidation, consistency, serialization và hành vi khi cache lỗi.

> 💡 **Giải thích dễ hiểu:**
> Cache giống quầy hàng nhanh đặt trước kho chính: đọc nhanh hơn nhưng phải thay hàng khi kho cập nhật. Không có quy tắc thay/thu hồi, quầy sẽ bán thông tin cũ dù database hoàn toàn đúng.

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
               unless = "#result?.price == null || #result.price.signum() == 0")
    public Product findByIdConditional(Long id) { ... }

    // Update cache on save
    @CachePut(value = "products", key = "#result.id")
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

Cache annotation mặc định chạy qua Spring AOP proxy: **self-invocation** *(method trong cùng object gọi method được cache)* không đi qua proxy nên cache không hoạt động. `@Cacheable` có thể bỏ qua method khi hit; `@CachePut` luôn chạy method rồi ghi; `@CacheEvict` mặc định chỉ evict sau khi method thành công. Cache operation cũng không tự nguyên tử với transaction database.

Với hot key, cân nhắc `@Cacheable(sync = true)` nếu provider hỗ trợ để giảm cache stampede trong một instance; nhiều instance vẫn cần distributed lock/single-flight hoặc TTL jitter phù hợp.

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

    public MultiLevelCacheManager(CacheManager l1, CacheManager l2) {
        this.l1 = l1;
        this.l2 = l2;
    }

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

    public MultiLevelCache(Cache l1, Cache l2) {
        this.l1 = Objects.requireNonNull(l1);
        this.l2 = Objects.requireNonNull(l2);
    }

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

`MultiLevelCacheManager`/`MultiLevelCache` ở trên là code custom minh họa, không phải implementation Spring cung cấp hoàn chỉnh. Trong cluster, mỗi instance có L1 riêng: một node update Redis/L2 nhưng L1 node khác vẫn stale. Production cần pub/sub invalidation, versioned key hoặc TTL L1 ngắn; xác định thứ tự write/evict, lỗi một tầng và race giữa read–populate–update trước khi dùng.

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
    PolymorphicTypeValidator allowedTypes = BasicPolymorphicTypeValidator.builder()
        .allowIfSubType("org.example.api.cache.")
        .build();
    mapper.setVisibility(PropertyAccessor.ALL, JsonAutoDetect.Visibility.ANY);
    mapper.activateDefaultTyping(
        allowedTypes,
        ObjectMapper.DefaultTyping.NON_FINAL,  // store class name in JSON
        JsonTypeInfo.As.PROPERTY
    );
    mapper.registerModule(new JavaTimeModule());
    return new GenericJackson2JsonRedisSerializer(mapper);
}
```

Polymorphic default typing ghi type metadata vào JSON và có lịch sử rủi ro gadget deserialization nếu cache/input không tin cậy. Dùng allow-list `PolymorphicTypeValidator`, Redis ACL/TLS và DTO cache có schema/version ổn định; tránh cache JPA entity/proxy lazy. Khi đổi class/package, chuẩn bị chiến lược tương thích hoặc đổi prefix/version key.

> 💡 **Giải thích dễ hiểu:**
> Cache key và payload là “mã kệ + nhãn hộp”. Đổi tên class hoặc quên tenant trong key có thể khiến app mở nhầm hộp. Versioned key giúp đặt lô hộp mới bên cạnh lô cũ rồi để TTL dọn dần.

---

## 5. Multiple Datasources

Mỗi JDBC datasource có connection pool, `EntityManagerFactory` và transaction manager riêng. Spring Boot tự cấu hình tốt nhất cho một datasource; từ datasource thứ hai, ứng dụng phải đặt tên bean/qualifier và repository package rõ ràng.

> 💡 **Giải thích dễ hiểu:**
> Hai datasource giống hai ngân hàng có hai sổ cái. Ghi thành công ở ngân hàng A không tự rollback khi ngân hàng B lỗi; `@Transactional` chỉ biết transaction manager được chọn.

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
      configuration:
        maximum-pool-size: 20
        connection-timeout: 30000
    secondary:
      url: jdbc:mysql://localhost:3306/analytics_db
      username: user
      password: pass
      driver-class-name: com.mysql.cj.jdbc.Driver
      configuration:
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
    public DataSourceProperties primaryDataSourceProperties() {
        return new DataSourceProperties();
    }

    @Bean
    @Primary
    @ConfigurationProperties("spring.datasource.primary.configuration")
    public HikariDataSource primaryDataSource(
            @Qualifier("primaryDataSourceProperties") DataSourceProperties properties) {
        // DataSourceProperties chuyển `url` thành `jdbcUrl` đúng cho Hikari.
        return properties.initializeDataSourceBuilder()
            .type(HikariDataSource.class)
            .build();
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
    public DataSourceProperties secondaryDataSourceProperties() {
        return new DataSourceProperties();
    }

    @Bean
    @ConfigurationProperties("spring.datasource.secondary.configuration")
    public HikariDataSource secondaryDataSource(
            @Qualifier("secondaryDataSourceProperties") DataSourceProperties properties) {
        return properties.initializeDataSourceBuilder()
            .type(HikariDataSource.class)
            .build();
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

Mỗi datasource cần migration, health check, metric pool và connection budget riêng. Hai `JpaTransactionManager` tạo hai local transaction độc lập; nếu một nghiệp vụ ghi cả hai DB, dùng outbox/saga/idempotency hoặc JTA/XA khi thật sự cần atomicity và chấp nhận chi phí.

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
@Order(Ordered.HIGHEST_PRECEDENCE) // route trước khi transaction lấy Connection
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

`@Transactional(readOnly = true)` là optimization hint, không tự route sang replica. Aspect phải chạy trước transaction interceptor; replica có replication lag nên read-after-write có thể đọc dữ liệu cũ. Route về primary trong một khoảng consistency window hoặc khi nghiệp vụ cần strong consistency.

`ThreadLocal` chỉ an toàn trong cùng thread và phải `clear()` ở `finally`; không dùng mẫu này cho Reactor, coroutine/thread hop hoặc `@Async`. Với reactive stack, truyền routing context qua Reactor Context và dùng `ConnectionFactory` phù hợp.

---

## 6. Flyway & Liquibase

Flyway và Liquibase là **schema migration tools** *(công cụ quản lý thay đổi cấu trúc database có lịch sử)*. Chọn một cơ chế làm source of truth; Spring Boot không khuyến nghị trộn Flyway/Liquibase với `schema.sql`, `data.sql` hoặc `ddl-auto=update` để cùng tạo schema production.

> 💡 **Giải thích dễ hiểu:**
> Migration giống sổ công trình có đánh số: mỗi môi trường thi công cùng bản vẽ theo cùng thứ tự. Sửa lén bản vẽ đã thi công làm checksum/lịch sử không còn đáng tin; hãy thêm bản sửa mới.

### 6.1 Flyway

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-flyway</artifactId>
</dependency>
<!-- Với database không nằm trong flyway-core, thêm module tương ứng. -->
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
```

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false   # mặc định an toàn; chỉ bật có kiểm soát cho DB có sẵn
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
├── V2_1__add_user_index.sql
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

`baseline-on-migrate=true` bỏ safety check khi schema không rỗng nhưng chưa có history table; chỉ dùng cho lần onboarding database hiện hữu sau khi xác minh URL/schema và backup. Không sửa versioned migration đã chạy ở môi trường dùng chung; thêm migration mới. Repeatable migration chạy lại khi checksum đổi nên phải idempotent theo semantics của object.

### 6.2 Liquibase

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-liquibase</artifactId>
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

`onFail="MARK_RAN"` đánh dấu changeSet đã chạy dù DDL không thực thi; dùng sai có thể che schema drift. Chỉ dùng khi trạng thái “đã tồn tại” thật sự tương đương mục tiêu và có test trên snapshot giống production.

**Flyway vs Liquibase:**

| Feature | Flyway | Liquibase |
|---------|--------|-----------|
| Format | SQL/Java | SQL/XML/YAML/JSON |
| Versioning | Filename (`V1__`) | ChangeSet ID + author + path |
| Rollback | Undo migration tùy edition; thường ưu tiên forward fix | Có rollback command nhưng cần inverse tự sinh được hoặc khai báo rollback đúng |
| Preconditions | Ít biểu đạt hơn | Phong phú; phải tránh `MARK_RAN` che drift |
| Diff/changelog generation | Không phải trọng tâm Community workflow | Có công cụ diff/generate, nhưng output vẫn phải review |
| Learning curve | Thấp hơn, SQL-first | Cao hơn, metadata/changelog nhiều hơn |
| Best for | Team muốn SQL rõ ràng, forward migration | Nhiều DB/format, precondition và rollback metadata phức tạp |

Production nên dùng chiến lược **expand–migrate–contract** *(mở rộng schema, chuyển dữ liệu/code, rồi thu hẹp)* để deploy zero/low-downtime: thêm column/table tương thích trước, backfill theo batch, chuyển traffic, sau cùng mới drop/rename. Rollback ứng dụng không đồng nghĩa rollback schema an toàn.

---

## 7. R2DBC Reactive Data

R2DBC cung cấp driver relational theo Reactive Streams, giúp thread không bị giữ trong lúc chờ I/O. Spring Data R2DBC có repository và `R2dbcEntityTemplate`, nhưng không có JPA persistence context, dirty checking, lazy-loading association hoặc fetch graph.

> 💡 **Giải thích dễ hiểu:**
> JDBC thường giống nhân viên đứng chờ tại quầy cho tới khi database trả lời. R2DBC giống lấy số rồi làm việc khác; khi có kết quả mới quay lại. Nếu giữa đường vẫn gọi JDBC/blocking API thì nhân viên lại đứng chờ và lợi ích reactive biến mất.

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

`upsert(entity)` chỉ dùng được khi dialect hỗ trợ single-statement upsert, entity đã có identifier và phiên bản Spring Data Relational cung cấp API này; upsert hiện không hỗ trợ optimistic locking. Nếu cần portability, dùng insert/update có điều kiện rõ ràng và xử lý race ở database constraint.

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

Reactive transaction chỉ có hiệu lực khi Spring chọn `ReactiveTransactionManager`/`R2dbcTransactionManager` và method trả về `Publisher`; transaction context đi theo Reactor Context, không theo `ThreadLocal`. Không gọi `block()`, JPA/JDBC hoặc SDK blocking trong pipeline/event-loop; nếu bắt buộc, cô lập trên bounded scheduler và hiểu rằng nó không tham gia cùng R2DBC transaction.

### 7.5 Handling Relations in R2DBC

```java
// Spring Data R2DBC không map association/lazy loading kiểu JPA.
// SQL JOIN vẫn dùng được qua @Query/DatabaseClient và map thẳng DTO.
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
    // Chỉ minh họa tập dữ liệu đã được giới hạn/paginate.
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

`collectList()` trên `findAll()` sẽ giữ toàn bộ bảng trong memory. Production phải phân trang/chunk ID, giới hạn concurrency và quan sát backpressure. Nếu category không tồn tại, `Mono.zip` hoàn tất rỗng; quyết định rõ trả 404, category nullable hay dữ liệu lỗi. Với read model phức tạp, một SQL JOIN map thẳng DTO thường ít round-trip hơn ghép thủ công.

---

## Compare & Trade-offs

| Lựa chọn | Điểm mạnh | Đánh đổi / khi tránh |
|----------|-----------|----------------------|
| JPA/Hibernate + JDBC | ORM, association, dirty checking, ecosystem trưởng thành | Blocking thread; fetch plan/flush khó đoán nếu thiếu kỷ luật |
| Spring Data JDBC | Aggregate mapping đơn giản, SQL/lifecycle rõ hơn JPA | Không persistence context/lazy loading; aggregate save có semantics riêng |
| R2DBC | Non-blocking I/O, hợp WebFlux end-to-end | Không JPA feature; reactive debugging/driver/tooling phức tạp; không tự nhanh hơn JDBC |
| Interface projection | Khai báo nhanh, nested projection | Proxy/SpEL và join có thể khó đoán; open projection ít tối ưu hơn |
| DTO/record projection | Contract read model rõ, serialization ổn định | Constructor/alias mapping phải chính xác, không được managed để update |
| Specification | Ghép filter tái sử dụng, chuẩn JPA | String path/Criteria verbose; join/count phức tạp cần custom query |
| Querydsl | Fluent type-safe, refactor tốt | APT/Q-class và dependency/fork maintenance |
| Local cache (Caffeine) | Rất nhanh, không network | Mỗi instance một bản; invalidation phân tán khó |
| Distributed cache (Redis) | Chia sẻ giữa instance | Network/serialization/availability và consistency trade-off |

> 💡 **Giải thích dễ hiểu:**
> Không có một “dao đa năng” tốt nhất: JPA giống xe số tự động nhiều tiện nghi, JDBC là xe số tay dễ thấy cơ chế, R2DBC là hệ thống điều phối không chặn. Chọn theo đường đi của toàn ứng dụng, không theo tên công nghệ đang phổ biến.

---

## Production – Checklist

- Đặt transaction boundary ở service; tắt/đánh giá `OpenEntityManagerInView` để không phát sinh lazy query trong controller/serializer.
- Với endpoint quan trọng, kiểm thử số statement và dùng `EXPLAIN (ANALYZE, BUFFERS)`/execution plan trên dữ liệu gần production; tạo index theo predicate/join/order, không theo cảm giác.
- Giới hạn page size, sort/filter whitelist, query timeout và database statement timeout; không trả entity trực tiếp qua API.
- Tính connection-pool budget theo tổng replica ứng dụng × pool size, giữ headroom cho migration/admin và theo dõi acquire timeout.
- Cache có owner, TTL/invalidation, tenant-aware key, schema version, stampede policy và fallback khi provider lỗi.
- Migration chạy một lần trong deployment stage/leader có kiểm soát; backup, lock timeout, expand–contract và test rollback/forward-fix trên snapshot.
- Với nhiều datasource, monitor/migrate từng nguồn; ghi chéo DB cần saga/outbox/XA đã được quyết định rõ.
- Với R2DBC, dùng BlockHound/test hoặc observability để phát hiện blocking; đặt timeout/retry có giới hạn và không retry mù transaction không idempotent.
- Ghi metric query latency/error, pool saturation, cache hit/miss/eviction, migration duration, replica lag và reactive scheduler.
- Externalize credential, TLS database/Redis, least privilege DB user và không log bind value chứa PII/secrets.

### Bảng quyết định nhanh

| Problem | Solution | When to Use |
|---------|----------|-------------|
| N+1 một object graph | `@EntityGraph` / `JOIN FETCH` | Fetch plan cụ thể, tập kết quả hữu hạn |
| N+1 list + pagination | ID-first pagination + secondary fetch | Collection + paging, cần giữ order |
| Gom lazy association | `default_batch_fetch_size` / `@BatchSize` | Đã đo batch size và giới hạn query parameter |
| Dynamic queries | Specification / Querydsl / custom repository | Search/filter APIs có giới hạn |
| Partial data fetch | Interface/DTO projections | List/read model/reporting |
| Read/write routing | Routing DataSource + AOP trước transaction | Chấp nhận replica lag hoặc có consistency policy |
| Schema migration | Chọn Flyway **hoặc** Liquibase | Mọi ứng dụng production dùng relational DB |
| Reactive stack | R2DBC + reactive repository/template | Toàn request path non-blocking, nhiều I/O đồng thời |

---

## Ghi chú – Chủ đề tiếp theo

> Chủ đề nên đào sâu tiếp: persistence context/flush, optimistic & pessimistic locking, transaction isolation, OSIV, keyset pagination, outbox, cache stampede/invalidation, datasource pool sizing, zero-downtime migration, R2DBC backpressure và reactive observability.

> Tài liệu chính thức: [Spring Data JPA projections](https://docs.spring.io/spring-data/jpa/reference/repositories/projections.html), [Specifications](https://docs.spring.io/spring-data/jpa/reference/jpa/specifications.html), [Spring Cache annotations](https://docs.spring.io/spring-framework/reference/integration/cache/annotations.html), [Spring Boot multiple data access](https://docs.spring.io/spring-boot/how-to/data-access.html), [database initialization/migration](https://docs.spring.io/spring-boot/how-to/data-initialization.html), [Spring Data R2DBC](https://docs.spring.io/spring-data/relational/reference/r2dbc.html), [Hibernate fetching](https://docs.hibernate.org/stable/orm/userguide/html_single/).

---

*Cập nhật lần cuối: 2026-07-27*
