# Spring Data JPA

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Spring Data JPA là gì?

**Spring Data JPA** là abstraction layer trên JPA, cung cấp:
1. **Repository interfaces**: CRUD operations không cần implement
2. **Query derivation**: tự tạo query từ method name
3. **@Query**: custom JPQL/native queries
4. **Specification**: type-safe dynamic queries
5. **Pagination & Sorting**: built-in Pageable support
6. **Auditing**: tự động set created/modified timestamps

```
Developer viết Interface → Spring Data JPA generate Implementation → JPA → DB
```

---

## How – Repository Hierarchy

```
Repository<T, ID> (marker interface)
  └── CrudRepository<T, ID>
        ├── save(), saveAll(), findById(), findAll(), delete(), count()
        └── PagingAndSortingRepository<T, ID>
              ├── findAll(Sort), findAll(Pageable)
              └── JpaRepository<T, ID> ← Dùng phổ biến nhất
                    ├── flush(), saveAndFlush(), deleteAllInBatch()
                    ├── findAll(Example), findAll(Specification) [với JpaSpecificationExecutor]
                    └── getReferenceById() (lazy proxy, không load nếu không cần)
```

```java
// Đơn giản nhất: extend JpaRepository
public interface UserRepository extends JpaRepository<User, Long> {
    // Tự có: save, findById, findAll, delete, count, existsById...
}

// Thêm Specification support
public interface OrderRepository
        extends JpaRepository<Order, Long>,
                JpaSpecificationExecutor<Order> { // thêm findAll(Specification)
}
```

---

## How – Query Derivation (Method Name Queries)

Spring Data parse method name → tạo JPQL tự động:

```java
public interface UserRepository extends JpaRepository<User, Long> {

    // findBy + field name
    Optional<User> findByEmail(String email);
    // → SELECT u FROM User u WHERE u.email = ?1

    List<User> findByStatus(UserStatus status);
    // → SELECT u FROM User u WHERE u.status = ?1

    // AND / OR
    List<User> findByFirstNameAndLastName(String firstName, String lastName);
    // → WHERE u.firstName = ?1 AND u.lastName = ?2

    Optional<User> findByEmailOrPhone(String email, String phone);
    // → WHERE u.email = ?1 OR u.phone = ?2

    // Comparison operators
    List<User> findByAgeLessThan(int age);               // age < ?
    List<User> findByAgeGreaterThanEqual(int age);       // age >= ?
    List<User> findByAgeBetween(int min, int max);       // age BETWEEN ? AND ?
    List<User> findByCreatedAtAfter(Instant date);       // created_at > ?
    List<User> findByCreatedAtBefore(Instant date);      // created_at < ?

    // LIKE / Contains / StartsWith / EndsWith
    List<User> findByNameLike(String pattern);           // name LIKE ?
    List<User> findByNameContaining(String substring);   // name LIKE %?%
    List<User> findByNameStartingWith(String prefix);    // name LIKE ?%
    List<User> findByNameEndingWith(String suffix);      // name LIKE %?
    List<User> findByNameContainingIgnoreCase(String s); // UPPER(name) LIKE UPPER(%?%)

    // Null checks
    List<User> findByDeletedAtIsNull();                  // deleted_at IS NULL
    List<User> findByDeletedAtIsNotNull();               // deleted_at IS NOT NULL

    // IN
    List<User> findByStatusIn(Collection<UserStatus> statuses); // status IN (...)
    List<User> findByIdNotIn(List<Long> ids);

    // Boolean
    List<User> findByActiveTrue();   // active = true
    List<User> findByActiveFalse();  // active = false

    // Nested properties (traverse associations)
    List<User> findByAddressCity(String city);     // JOIN address WHERE city=?
    List<Order> findByCustomerEmail(String email); // JOIN customer WHERE email=?

    // Limiting results
    Optional<User> findFirstByOrderByCreatedAtDesc();   // LIMIT 1 + ORDER BY
    List<User> findTop10ByStatusOrderByCreatedAtDesc(UserStatus status); // LIMIT 10

    // Counting / Existence
    long countByStatus(UserStatus status);
    boolean existsByEmail(String email);

    // Delete (must be in @Transactional)
    @Transactional
    void deleteByEmail(String email);
    @Transactional
    long deleteByStatusAndCreatedAtBefore(UserStatus status, Instant cutoff);

    // Sorting
    List<User> findByStatus(UserStatus status, Sort sort);
    // call: repo.findByStatus(status, Sort.by(Sort.Direction.DESC, "createdAt"))
}
```

### Query Derivation Keywords Reference

| Keyword | SQL equivalent |
|---------|---------------|
| `And` | `AND` |
| `Or` | `OR` |
| `Is`, `Equals` | `=` |
| `Between` | `BETWEEN ? AND ?` |
| `LessThan` | `<` |
| `GreaterThanEqual` | `>=` |
| `After` | `>` (dates) |
| `Before` | `<` (dates) |
| `IsNull` | `IS NULL` |
| `IsNotNull` | `IS NOT NULL` |
| `Like` | `LIKE` |
| `NotLike` | `NOT LIKE` |
| `Containing` | `LIKE %?%` |
| `Not` | `!=` |
| `In` | `IN (...)` |
| `NotIn` | `NOT IN (...)` |
| `True` | `= true` |
| `False` | `= false` |
| `IgnoreCase` | `UPPER(x) = UPPER(?)` |

---

## How – @Query (Custom Queries)

```java
public interface OrderRepository extends JpaRepository<Order, Long> {

    // JPQL query (entity/field names, not table/column names)
    @Query("SELECT o FROM Order o WHERE o.status = :status AND o.totalAmount > :minAmount " +
           "ORDER BY o.createdAt DESC")
    List<Order> findExpensiveOrders(
        @Param("status") OrderStatus status,
        @Param("minAmount") BigDecimal minAmount);

    // JOIN FETCH để tránh N+1
    @Query("SELECT DISTINCT o FROM Order o " +
           "LEFT JOIN FETCH o.items i " +
           "LEFT JOIN FETCH i.product " +
           "WHERE o.customer.id = :customerId")
    List<Order> findWithItemsByCustomerId(@Param("customerId") Long customerId);

    // COUNT query tách riêng cho pagination (tránh JOIN trong COUNT)
    @Query(
        value = "SELECT o FROM Order o LEFT JOIN FETCH o.items WHERE o.status = :status",
        countQuery = "SELECT COUNT(o) FROM Order o WHERE o.status = :status"
    )
    Page<Order> findByStatusWithItems(@Param("status") OrderStatus status, Pageable pageable);

    // Native SQL (khi cần DB-specific features)
    @Query(
        value = "SELECT u.id, u.name, COUNT(o.id) as order_count " +
                "FROM users u LEFT JOIN orders o ON o.user_id = u.id " +
                "WHERE u.status = :status " +
                "GROUP BY u.id, u.name " +
                "ORDER BY order_count DESC " +
                "LIMIT :limit",
        nativeQuery = true
    )
    List<Object[]> findTopUsersByOrderCount(
        @Param("status") String status,
        @Param("limit") int limit);

    // Modifying query (UPDATE/DELETE)
    @Modifying
    @Transactional
    @Query("UPDATE Order o SET o.status = :newStatus WHERE o.status = :oldStatus AND o.createdAt < :cutoff")
    int bulkUpdateStatus(
        @Param("newStatus") OrderStatus newStatus,
        @Param("oldStatus") OrderStatus oldStatus,
        @Param("cutoff") Instant cutoff);
    // Trả về số rows affected

    // Modifying với clearAutomatically (tránh stale cache sau bulk update)
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Transactional
    @Query("DELETE FROM Order o WHERE o.status = 'CANCELLED' AND o.createdAt < :cutoff")
    int deleteCancelledOrders(@Param("cutoff") Instant cutoff);
}
```

---

## How – Pagination & Sorting

```java
// Pageable: interface chứa page number, size, sort
Pageable pageable = PageRequest.of(
    page,                         // page index (0-based)
    size,                         // page size
    Sort.by("createdAt").descending()  // sort
        .and(Sort.by("id").ascending()) // tiebreaker
);

// Page: kết quả kèm metadata
Page<Order> page = orderRepository.findByStatus(OrderStatus.PENDING, pageable);

// Metadata
page.getTotalElements();  // tổng số records
page.getTotalPages();     // tổng số pages
page.getNumber();         // page hiện tại (0-based)
page.getSize();           // page size
page.hasNext();           // còn trang tiếp không
page.hasPrevious();
page.getContent();        // List<Order> trên page này
page.isFirst();
page.isLast();

// Slice: nhẹ hơn Page (không có COUNT query)
// Chỉ biết hasNext, không biết totalElements
Slice<Order> slice = orderRepository.findByCustomerId(customerId, pageable);
slice.hasNext(); // check còn data không (for infinite scroll)

// REST Controller example
@GetMapping("/orders")
public Page<OrderDto> getOrders(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(defaultValue = "createdAt") String sortBy,
        @RequestParam(defaultValue = "DESC") Sort.Direction direction) {

    Pageable pageable = PageRequest.of(page, size, Sort.by(direction, sortBy));
    return orderRepository.findAll(pageable)
        .map(OrderDto::from); // map entity → DTO
}
```

---

## How – Specification (Dynamic Queries)

**Specification pattern**: type-safe predicate builder cho dynamic queries.

```java
// Repository phải extend JpaSpecificationExecutor
public interface UserRepository extends JpaRepository<User, Long>,
                                         JpaSpecificationExecutor<User> {}

// Specification = Predicate builder
public class UserSpecifications {

    public static Specification<User> hasStatus(UserStatus status) {
        return (root, query, cb) ->
            status == null ? cb.conjunction()  // no-op predicate (1=1)
                           : cb.equal(root.get("status"), status);
    }

    public static Specification<User> createdAfter(Instant date) {
        return (root, query, cb) ->
            date == null ? cb.conjunction()
                         : cb.greaterThan(root.get("createdAt"), date);
    }

    public static Specification<User> nameLike(String name) {
        return (root, query, cb) ->
            name == null ? cb.conjunction()
                         : cb.like(cb.lower(root.get("name")), "%" + name.toLowerCase() + "%");
    }

    public static Specification<User> hasRole(String role) {
        return (root, query, cb) -> {
            // Join để filter qua association
            Join<User, Role> roles = root.join("roles", JoinType.LEFT);
            return cb.equal(roles.get("name"), role);
        };
    }
}

// Service: compose specifications
@Service
public class UserService {
    public Page<User> search(UserSearchRequest req, Pageable pageable) {
        Specification<User> spec = Specification
            .where(UserSpecifications.hasStatus(req.status()))
            .and(UserSpecifications.createdAfter(req.createdAfter()))
            .and(UserSpecifications.nameLike(req.name()))
            .and(req.role() != null ? UserSpecifications.hasRole(req.role()) : null);

        return userRepository.findAll(spec, pageable);
    }
}
```

---

## How – Projections (Partial Data Loading)

### Interface Projection (closed)

```java
// Chỉ load subset của entity columns
public interface UserSummary {
    Long getId();
    String getName();
    String getEmail();
    // Không load password, address, orders...

    // Computed property (SpEL expression)
    @Value("#{target.firstName + ' ' + target.lastName}")
    String getFullName();
}

// Spring Data tự tạo proxy
List<UserSummary> findByStatus(UserStatus status);
// → SELECT id, name, email FROM users WHERE status=?
// (không SELECT password, address...)
```

### DTO Projection (record/class)

```java
// DTO record
public record UserDto(Long id, String name, String email) {}

// Phải dùng @Query (query derivation không hỗ trợ DTO)
@Query("SELECT new com.example.dto.UserDto(u.id, u.name, u.email) " +
       "FROM User u WHERE u.status = :status")
List<UserDto> findUserDtosByStatus(@Param("status") UserStatus status);
```

### Dynamic Projection

```java
// Cùng method, trả về projection type khác nhau
<T> List<T> findByStatus(UserStatus status, Class<T> type);

// Gọi:
List<UserSummary> summaries = repo.findByStatus(ACTIVE, UserSummary.class);
List<User> entities = repo.findByStatus(ACTIVE, User.class);
List<UserDto> dtos = repo.findByStatus(ACTIVE, UserDto.class);
```

---

## How – Auditing

```java
// 1. Enable auditing
@SpringBootApplication
@EnableJpaAuditing(auditorAwareRef = "auditorProvider")
public class App {}

// 2. Provide current user
@Bean
public AuditorAware<String> auditorProvider() {
    return () -> Optional.ofNullable(SecurityContextHolder.getContext())
        .map(SecurityContext::getAuthentication)
        .filter(Authentication::isAuthenticated)
        .map(Authentication::getName);
}

// 3. Base entity (extend để tái sử dụng)
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class) // PHẢI có để auditing work
public abstract class BaseEntity {

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    @Column(nullable = false)
    private Instant updatedAt;

    @CreatedBy
    @Column(nullable = false, updatable = false, length = 100)
    private String createdBy;

    @LastModifiedBy
    @Column(nullable = false, length = 100)
    private String updatedBy;
}

// 4. Entity kế thừa
@Entity
@Table(name = "products")
public class Product extends BaseEntity {
    @Id @GeneratedValue(strategy = IDENTITY)
    private Long id;
    private String name;
    private BigDecimal price;
}

// Spring tự động set createdAt, updatedAt, createdBy, updatedBy khi save/update
```

---

## How – Custom Repository Implementation

```java
// Khi query derivation và @Query không đủ
// Bước 1: tạo interface custom
public interface OrderRepositoryCustom {
    List<Order> findComplexOrders(ComplexSearchCriteria criteria);
    Map<OrderStatus, Long> countByStatusGrouped();
}

// Bước 2: implement
@Repository
public class OrderRepositoryCustomImpl implements OrderRepositoryCustom {
    private final EntityManager em;

    @Override
    public List<Order> findComplexOrders(ComplexSearchCriteria criteria) {
        // Dùng Criteria API hoặc native SQL tùy ý
        CriteriaBuilder cb = em.getCriteriaBuilder();
        CriteriaQuery<Order> query = cb.createQuery(Order.class);
        // ... complex dynamic query
        return em.createQuery(query).getResultList();
    }

    @Override
    public Map<OrderStatus, Long> countByStatusGrouped() {
        return em.createQuery(
                "SELECT o.status, COUNT(o) FROM Order o GROUP BY o.status",
                Object[].class)
            .getResultStream()
            .collect(Collectors.toMap(
                row -> (OrderStatus) row[0],
                row -> (Long) row[1]));
    }
}

// Bước 3: Repository extend cả hai
public interface OrderRepository
        extends JpaRepository<Order, Long>,
                JpaSpecificationExecutor<Order>,
                OrderRepositoryCustom { // Spring tự detect và wire Impl
}
```

---

## How – Optimistic Lock với Spring Data JPA

```java
@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {

    // @Lock annotation cho query-level locking
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT p FROM Product p WHERE p.id = :id")
    Optional<Product> findByIdWithLock(@Param("id") Long id);

    // Optimistic lock via @Version (entity-level, tự động)
    // Nếu conflict → OptimisticLockingFailureException (Spring wrap)
}

// Service với retry
@Service
public class InventoryService {

    @Retryable(
        retryFor = OptimisticLockingFailureException.class,
        maxAttempts = 3,
        backoff = @Backoff(delay = 100, multiplier = 2)
    )
    @Transactional
    public void reserveStock(Long productId, int quantity) {
        Product product = productRepository.findById(productId)
            .orElseThrow(() -> new ProductNotFoundException(productId));

        if (product.getStock() < quantity) {
            throw new InsufficientStockException();
        }

        product.setStock(product.getStock() - quantity);
        productRepository.save(product);
        // OptimisticLockingFailureException nếu concurrent update
        // @Retryable sẽ retry tối đa 3 lần
    }
}
```

---

## Components – Repository Interface Comparison

| Interface | Kế thừa | Thêm gì |
|-----------|---------|---------|
| `Repository` | – | Marker only |
| `CrudRepository` | Repository | save/findById/findAll/delete/count |
| `PagingAndSortingRepository` | CrudRepository | findAll(Sort)/findAll(Pageable) |
| `JpaRepository` | PagingAndSortingRepository | flush/saveAndFlush/deleteAllInBatch/getReferenceById |
| `JpaSpecificationExecutor` | – | findAll(Spec)/findOne(Spec)/count(Spec) |

---

## Why – Tại sao Spring Data JPA?

| Vấn đề thuần JPA | Spring Data JPA giải quyết |
|-----------------|--------------------------|
| Viết CRUD boilerplate cho mỗi entity | JpaRepository built-in |
| Build JPQL string by hand | Query derivation tự generate |
| Dynamic query phức tạp | Specification pattern |
| Pagination thủ công (LIMIT/OFFSET) | Pageable/Page tích hợp |
| Manual auditing (set timestamps) | @CreatedDate/@LastModifiedDate |
| Transaction management thủ công | @Transactional tích hợp |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Productivity cực cao | Query derivation dài → khó đọc |
| Ít code boilerplate | Ẩn SQL → khó debug performance |
| Pagination built-in | Specification verbose |
| Auditing tự động | Magic: khó hiểu khi sai |
| Dễ test với @DataJpaTest | Vẫn cần hiểu JPA để dùng đúng |

---

## Real-world Usage (Production)

### 1. Efficient Pagination với Cursor-based (vs Offset)

```java
// Offset-based: chậm khi page lớn (DB scan toàownId rows)
// SELECT * FROM orders ORDER BY id LIMIT 20 OFFSET 100000 → scan 100020 rows!

// Cursor-based: nhanh hơn nhiều
@Query("SELECT o FROM Order o WHERE o.id > :lastId AND o.status = :status " +
       "ORDER BY o.id ASC")
List<Order> findNextPage(
    @Param("lastId") Long lastId,
    @Param("status") OrderStatus status,
    Pageable pageable);  // chỉ dùng pageSize từ Pageable, ignore page number

// Client giữ lastId của item cuối cùng
// → Luôn index scan nhanh, không phụ thuộc page number
```

### 2. @DataJpaTest – Integration Test với In-memory DB

```java
@DataJpaTest  // chỉ load JPA components + H2 in-memory DB
@ActiveProfiles("test")
class UserRepositoryTest {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private TestEntityManager em; // helper để setup test data

    @Test
    void findByEmail_returnsUser() {
        // Given
        User user = em.persist(new User("Alice", "alice@example.com"));
        em.flush(); // đảm bảo data vào DB

        // When
        Optional<User> found = userRepository.findByEmail("alice@example.com");

        // Then
        assertThat(found).isPresent();
        assertThat(found.get().getName()).isEqualTo("Alice");
    }

    @Test
    void findByStatus_withPagination() {
        // Setup nhiều users
        IntStream.range(0, 25).forEach(i ->
            em.persist(new User("User" + i, "user" + i + "@test.com", UserStatus.ACTIVE)));
        em.flush();

        // Query first page
        Page<User> page = userRepository.findByStatus(
            UserStatus.ACTIVE,
            PageRequest.of(0, 10, Sort.by("name")));

        assertThat(page.getTotalElements()).isEqualTo(25);
        assertThat(page.getTotalPages()).isEqualTo(3);
        assertThat(page.getContent()).hasSize(10);
    }
}
```

### 3. Bulk Operations với @Modifying

```java
// Tránh: load từng entity rồi delete (N+1 + overhead)
List<Order> cancelled = repo.findByStatus(CANCELLED);
cancelled.forEach(repo::delete); // N DELETE queries!

// Nên: bulk delete trong 1 query
@Modifying
@Transactional
@Query("DELETE FROM Order o WHERE o.status = 'CANCELLED' AND o.createdAt < :cutoff")
int deleteCancelledBefore(@Param("cutoff") Instant cutoff);
// 1 DELETE query với WHERE clause!

// Với @Modifying(clearAutomatically = true):
// Spring clear persistence context sau bulk operation
// Tránh stale data nếu load lại entities trong cùng transaction
```

---

## Ghi chú – Chủ đề tiếp theo

> Hoàn thành **Data Access** (JDBC → JPA/Hibernate → Spring Data JPA).
>
> Tiếp theo (tùy chọn theo roadmap):
> - **Spring Security**: Authentication (UsernamePasswordAuthenticationFilter, UserDetailsService, JWT), Authorization (@PreAuthorize, method security, role hierarchy), CSRF, CORS
> - **Testing**: JUnit 5 (@Test/@ParameterizedTest/@TestFactory), Mockito (mock/spy/verify/ArgumentCaptor), @SpringBootTest vs @WebMvcTest vs @DataJpaTest, Testcontainers
> - **Reactive Programming**: Project Reactor (Mono/Flux), WebFlux, backpressure, Schedulers
> - **Java Modules (JPMS)**: module-info.java, requires/exports/opens, migration
