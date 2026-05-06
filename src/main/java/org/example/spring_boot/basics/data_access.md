# Spring Data JPA Nâng cao – Truy vấn dữ liệu chuyên nghiệp

## What – Spring Data JPA là gì?

**Spring Data JPA** là abstraction layer trên JPA/Hibernate, cung cấp repository pattern, giảm boilerplate và hỗ trợ nhiều kiểu query: derived queries, JPQL, Native SQL, Specifications, QueryDSL, Projections.

> Nền tảng JPA/Hibernate đã có tại `java/data/jpa_hibernate.md`. File này tập trung vào **Spring Data JPA patterns nâng cao**.

---

## Repository Hierarchy

```
Repository (marker)
  └── CrudRepository<T, ID>         – CRUD cơ bản
        └── PagingAndSortingRepository  – + pagination/sorting
              └── JpaRepository<T, ID>  – + flush, batch, JPA-specific (phổ biến nhất)
                    └── JpaSpecificationExecutor<T>  – + Specifications
```

---

## Query Methods (Derived Queries)

Spring Data tự generate SQL từ tên method:

```java
public interface UserRepository extends JpaRepository<User, Long> {

    // SELECT * FROM users WHERE email = ?
    Optional<User> findByEmail(String email);

    // SELECT * FROM users WHERE tenant_id = ? AND status = ?
    List<User> findByTenantIdAndStatus(Long tenantId, UserStatus status);

    // SELECT * FROM users WHERE created_at BETWEEN ? AND ?
    List<User> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);

    // SELECT * FROM users WHERE name LIKE '%?%'
    List<User> findByNameContainingIgnoreCase(String keyword);

    // SELECT * FROM users WHERE email IN (?)
    List<User> findByEmailIn(Collection<String> emails);

    // COUNT
    long countByTenantIdAndStatus(Long tenantId, UserStatus status);

    // EXISTS
    boolean existsByEmail(String email);

    // DELETE
    @Modifying
    @Transactional
    void deleteByTenantIdAndStatus(Long tenantId, UserStatus status);

    // TOP N
    List<User> findTop5ByTenantIdOrderByCreatedAtDesc(Long tenantId);

    // DISTINCT
    List<User> findDistinctByRolesName(String roleName);
}
```

**Từ khóa trong tên method:**
`find...By`, `count...By`, `exists...By`, `delete...By` + `And`, `Or`, `Is`, `Not`, `In`, `Between`, `LessThan`, `GreaterThan`, `Like`, `Containing`, `StartingWith`, `OrderBy`, `Top`, `First`, `Distinct`

---

## @Query – JPQL và Native SQL

```java
public interface OrderRepository extends JpaRepository<Order, Long> {

    // JPQL (entity names, not table names)
    @Query("SELECT o FROM Order o WHERE o.tenantId = :tenantId AND o.status = :status")
    List<Order> findByTenantAndStatus(
        @Param("tenantId") Long tenantId,
        @Param("status") OrderStatus status
    );

    // JPQL với JOIN FETCH (tránh N+1)
    @Query("SELECT DISTINCT o FROM Order o " +
           "LEFT JOIN FETCH o.items " +
           "LEFT JOIN FETCH o.user " +
           "WHERE o.id = :id")
    Optional<Order> findByIdWithDetails(@Param("id") Long id);

    // Native SQL (khi cần SQL-specific features)
    @Query(value = """
        SELECT o.*, u.name as user_name
        FROM orders o
        JOIN users u ON o.user_id = u.id
        WHERE o.tenant_id = :tenantId
          AND o.created_at > NOW() - INTERVAL '30 days'
        ORDER BY o.created_at DESC
        """, nativeQuery = true)
    List<Map<String, Object>> findRecentOrdersNative(@Param("tenantId") Long tenantId);

    // JPQL với Pagination
    @Query("SELECT o FROM Order o WHERE o.tenantId = :tenantId")
    Page<Order> findByTenantId(@Param("tenantId") Long tenantId, Pageable pageable);

    // Update (cần @Modifying + @Transactional)
    @Modifying
    @Transactional
    @Query("UPDATE Order o SET o.status = :status WHERE o.id = :id AND o.tenantId = :tenantId")
    int updateStatus(@Param("id") Long id,
                     @Param("tenantId") Long tenantId,
                     @Param("status") OrderStatus status);

    // Bulk delete
    @Modifying
    @Transactional
    @Query("DELETE FROM Order o WHERE o.tenantId = :tenantId AND o.status = 'CANCELLED'")
    int deleteOldCancelledOrders(@Param("tenantId") Long tenantId);
}
```

---

## Projections – Chỉ lấy columns cần thiết

### Interface Projection (Closed)

```java
// Chỉ cần id + name + email, không cần load cả User entity (100 columns)
public interface UserSummary {
    Long getId();
    String getName();
    String getEmail();
    
    // Nested projection
    RoleSummary getRole();
    
    interface RoleSummary {
        String getName();
    }
    
    // SpEL computed field
    @Value("#{target.firstName + ' ' + target.lastName}")
    String getFullName();
}

// Repository
List<UserSummary> findByTenantId(Long tenantId);

// Spring Data tự tạo proxy, chỉ SELECT id, name, email FROM users WHERE tenant_id = ?
```

### Class-based Projection (DTO Projection)

```java
// Constructor-based DTO
public record OrderSummaryDTO(Long id, String status, BigDecimal total, String userName) {}

// JPQL constructor expression
@Query("SELECT new com.example.dto.OrderSummaryDTO(o.id, o.status, o.total, u.name) " +
       "FROM Order o JOIN o.user u WHERE o.tenantId = :tenantId")
List<OrderSummaryDTO> findOrderSummaries(@Param("tenantId") Long tenantId);
```

### Dynamic Projection (Generic Return Type)

```java
// Một method, nhiều projection types
<T> List<T> findByTenantId(Long tenantId, Class<T> type);

// Gọi:
List<UserSummary> summaries = repo.findByTenantId(tenantId, UserSummary.class);
List<User> full = repo.findByTenantId(tenantId, User.class);
```

---

## Specifications – Dynamic Queries

**Khi nào dùng:** Query có nhiều filter tùy chọn (search forms, API filters).

```java
// UserSpec.java
public class UserSpec {

    public static Specification<User> hasTenant(Long tenantId) {
        return (root, query, cb) ->
            cb.equal(root.get("tenantId"), tenantId);
    }

    public static Specification<User> hasStatus(UserStatus status) {
        return (root, query, cb) ->
            status == null ? cb.conjunction() :  // no-op if null
            cb.equal(root.get("status"), status);
    }

    public static Specification<User> nameContains(String keyword) {
        return (root, query, cb) ->
            !StringUtils.hasText(keyword) ? cb.conjunction() :
            cb.like(cb.lower(root.get("name")), "%" + keyword.toLowerCase() + "%");
    }

    public static Specification<User> createdAfter(LocalDateTime date) {
        return (root, query, cb) ->
            date == null ? cb.conjunction() :
            cb.greaterThanOrEqualTo(root.get("createdAt"), date);
    }

    // JOIN spec
    public static Specification<User> hasRole(String roleName) {
        return (root, query, cb) -> {
            query.distinct(true);
            Join<User, Role> roleJoin = root.join("roles", JoinType.LEFT);
            return cb.equal(roleJoin.get("name"), roleName);
        };
    }
}

// Repository phải extend JpaSpecificationExecutor
public interface UserRepository extends JpaRepository<User, Long>,
                                         JpaSpecificationExecutor<User> {}

// Service – compose specifications
public Page<User> searchUsers(UserSearchRequest req, Pageable pageable) {
    Specification<User> spec = Specification
        .where(UserSpec.hasTenant(req.getTenantId()))
        .and(UserSpec.hasStatus(req.getStatus()))
        .and(UserSpec.nameContains(req.getKeyword()))
        .and(UserSpec.createdAfter(req.getCreatedAfter()));

    return userRepo.findAll(spec, pageable);
}
```

---

## Pagination & Sorting

```java
// Controller
@GetMapping("/users")
public Page<UserSummary> getUsers(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(defaultValue = "createdAt") String sortBy,
        @RequestParam(defaultValue = "desc") String direction) {

    // Validate sortBy để tránh injection
    Set<String> allowedSortFields = Set.of("createdAt", "name", "email");
    if (!allowedSortFields.contains(sortBy)) {
        throw new IllegalArgumentException("Invalid sort field: " + sortBy);
    }

    Sort.Direction dir = "asc".equalsIgnoreCase(direction) ? ASC : DESC;
    Pageable pageable = PageRequest.of(page, Math.min(size, 100), Sort.by(dir, sortBy));

    return userRepo.findByTenantId(tenantId, pageable).map(userMapper::toSummary);
}

// Response wrapper
public record PageResponse<T>(
    List<T> content,
    int page,
    int size,
    long totalElements,
    int totalPages,
    boolean last
) {
    public static <T> PageResponse<T> from(Page<T> page) {
        return new PageResponse<>(
            page.getContent(), page.getNumber(), page.getSize(),
            page.getTotalElements(), page.getTotalPages(), page.isLast()
        );
    }
}
```

---

## Auditing (@CreatedDate, @LastModifiedDate)

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
public abstract class AuditableEntity {

    @CreatedDate
    @Column(updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    private LocalDateTime updatedAt;

    @CreatedBy
    @Column(updatable = false)
    private String createdBy;

    @LastModifiedBy
    private String updatedBy;
}

// Config: cung cấp current user
@Bean
public AuditorAware<String> auditorProvider() {
    return () -> Optional.ofNullable(SecurityContextHolder.getContext().getAuthentication())
        .filter(Authentication::isAuthenticated)
        .map(Authentication::getName);
}

@SpringBootApplication
@EnableJpaAuditing
public class App {}
```

---

## N+1 Problem & Solutions

```java
// ❌ N+1: Order.getItems() gọi N query thêm
List<Order> orders = orderRepo.findAll();
orders.forEach(o -> o.getItems().size()); // N queries!

// ✅ Fix 1: JOIN FETCH trong @Query
@Query("SELECT DISTINCT o FROM Order o LEFT JOIN FETCH o.items WHERE o.tenantId = :tenantId")
List<Order> findAllWithItems(@Param("tenantId") Long tenantId);

// ✅ Fix 2: @EntityGraph (declarative)
@EntityGraph(attributePaths = {"items", "user"})
List<Order> findByTenantId(Long tenantId);

// ✅ Fix 3: Batch Size (Hibernate)
@OneToMany(mappedBy = "order", fetch = FetchType.LAZY)
@BatchSize(size = 50)  // load 50 collections in 1 query với IN clause
private List<OrderItem> items;

// application.yml
spring:
  jpa:
    properties:
      hibernate:
        default_batch_fetch_size: 50
```

---

## Bulk Operations

```java
// ❌ Chậm: lặp qua từng entity
orders.forEach(o -> { o.setStatus(ARCHIVED); orderRepo.save(o); }); // N queries

// ✅ Bulk update (1 query)
@Modifying
@Transactional
@Query("UPDATE Order o SET o.status = 'ARCHIVED' WHERE o.createdAt < :cutoff")
int archiveOldOrders(@Param("cutoff") LocalDateTime cutoff);

// Bulk insert với saveAll (batching cần cấu hình Hibernate)
spring:
  jpa:
    properties:
      hibernate:
        jdbc:
          batch_size: 50
        order_inserts: true
        order_updates: true

// Dùng SEQUENCE ID generator (không phải IDENTITY) để batching hoạt động
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
```

---

## Soft Delete Pattern

```java
@Entity
@SQLDelete(sql = "UPDATE orders SET deleted_at = NOW() WHERE id = ?")
@FilterDef(name = "notDeleted")
@Filter(name = "notDeleted", condition = "deleted_at IS NULL")
public class Order {
    // ...
    private LocalDateTime deletedAt;  // null = active
}

// Bật filter (phải bật thủ công mỗi session)
@Aspect
@Component
public class SoftDeleteFilterAspect {
    @Autowired private EntityManager em;

    @Before("within(@org.springframework.stereotype.Repository *)")
    public void enableFilter(JoinPoint jp) {
        em.unwrap(Session.class).enableFilter("notDeleted");
    }
}
```

---

## Trade-offs

| Approach | Use Case | Downside |
|----------|----------|----------|
| Derived query | Simple conditions | Method name becomes long |
| @Query JPQL | Complex logic, type-safe | Not portable (JPQL dialect) |
| Native SQL | DB-specific features, performance | Not portable, no type safety |
| Specifications | Dynamic multi-filter | Verbose boilerplate |
| QueryDSL | Complex dynamic + type-safe | Extra codegen setup |
| Projections | Read performance | No entity management |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `basics/validation_exception.md` – Bean Validation, @ControllerAdvice, Problem Details RFC 9457
- `basics/testing.md` – @DataJpaTest, Testcontainers, repository testing
- **Keywords:** QueryDSL (Q-classes), Blaze Persistence (CTE, window functions), Spring Data JDBC (simpler alternative), JdbcTemplate, NamedParameterJdbcTemplate, Optimistic locking (@Version), Pessimistic locking (LockModeType), Read-only transaction optimization, Connection pool sizing formula (Nthreads * (Cwait/Cservice) + 1)
