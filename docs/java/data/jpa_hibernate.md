---
title: "JPA & Hibernate"
topic: java
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# JPA & Hibernate

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – JPA & Hibernate là gì?

**JPA (Jakarta Persistence API)** = specification *(bản đặc tả — quy định "phải làm được gì", không nói "làm thế nào")* (interface) định nghĩa cách ORM hoạt động trong Java EE/Jakarta EE.

**Hibernate** = implementation *(bản hiện thực cụ thể — viết code thật để làm đúng những gì đặc tả yêu cầu)* phổ biến nhất của JPA (cùng với EclipseLink, OpenJPA).

> 💡 **Giải thích dễ hiểu — JPA vs Hibernate:**
> Nhiều người mới hay lẫn hai khái niệm này. Ví von: **JPA là bản thiết kế/tiêu chuẩn của một ổ điện** (quy định lỗ cắm, điện áp), còn **Hibernate là một hãng cụ thể sản xuất ổ điện đúng chuẩn đó**. Bạn lập trình theo "chuẩn" JPA (các interface như `EntityManager`), nên sau này có thể thay Hibernate bằng hãng khác (EclipseLink) mà code ít phải sửa. Hibernate là hãng phổ biến nhất nên thực tế đa số dự án dùng nó.

```
JPA (Specification/Interface)
  └── Hibernate (Implementation)
        └── JDBC
              └── Database
```

**ORM (Object-Relational Mapping)** *(ánh xạ đối tượng – quan hệ: tự động chuyển đổi giữa object trong code và dòng dữ liệu trong bảng)*: map Java objects ↔ DB rows tự động.

> 💡 **Giải thích dễ hiểu — ORM:**
> Object trong Java (một `User` có tên, email...) và một dòng trong bảng `users` là hai thế giới khác nhau: một bên là object có kiểu, có phương thức; một bên là hàng cột phẳng. Bình thường bạn phải tự tay chép từng cột vào từng field.
> Ví von: ORM như một **phiên dịch viên song ngữ** đứng giữa "tiếng Java" và "tiếng SQL". Bạn nói bằng object, nó tự dịch sang câu SQL và ngược lại — chép kết quả từ bảng trở lại thành object — mà bạn không cần viết tay đoạn dịch đó nữa.

```java
// Không ORM: thủ công map
User user = new User();
user.setId(rs.getLong("id"));
user.setName(rs.getString("name"));
user.setEmail(rs.getString("email"));
user.setCreatedAt(rs.getTimestamp("created_at").toInstant());

// Với JPA: tự động map
@Entity
@Table(name = "users")
public class User {
    @Id @GeneratedValue(strategy = IDENTITY)
    private Long id;
    private String name;
    private String email;
    @Column(name = "created_at")
    private Instant createdAt;
}
// EntityManager.find(User.class, 1L) → tự tạo SQL + map kết quả
```

---

## How – Entity Lifecycle

**4 trạng thái của một entity** *(entity — đối tượng được map với một bảng; "vòng đời entity" là các giai đoạn nó đi qua khi làm việc với database)*:

> 💡 **Giải thích dễ hiểu — 4 trạng thái entity:**
> Hãy coi một entity như **một món hàng và mối quan hệ của nó với kho (persistence context)**:
> - **TRANSIENT** *(thoáng qua)*: món hàng bạn vừa `new` ra, kho chưa hề biết tới nó — chưa được ai theo dõi.
> - **MANAGED** *(đang được quản lý)*: bạn `persist()` món hàng vào kho. Từ giờ kho **giám sát mọi thay đổi** của nó; bạn sửa thuộc tính gì, đến lúc chốt sổ kho tự cập nhật xuống database — không cần bạn gọi lệnh "update".
> - **DETACHED** *(đã tách khỏi kho)*: đóng phiên làm việc, món hàng vẫn nằm trong tay bạn (còn trong bộ nhớ Java) nhưng kho **không theo dõi nữa** — sửa gì cũng không xuống database, trừ khi `merge()` lại.
> - **REMOVED** *(đánh dấu xóa)*: bạn bảo kho "bỏ món này đi", đến lúc chốt sổ nó sinh câu DELETE.
> Cụm từ khóa cần nhớ: chỉ khi entity ở trạng thái **MANAGED** thì thay đổi mới tự động đồng bộ xuống DB.

```
  new User()          persist()          commit/flush
[TRANSIENT] ────────→ [MANAGED] ────────→ [DB UPDATED]
                          │                     │
              detach()    │   merge()           │
                          ↓ ←─────────────      │
                    [DETACHED]                  │
                                               │
                    remove() (on managed)      │
                          ↓                    │
                    [REMOVED] ─────────→ [DB DELETED]
```

```java
EntityManager em = emFactory.createEntityManager();
em.getTransaction().begin();

// 1. TRANSIENT: không liên kết với persistence context
User user = new User();
user.setName("Alice");
// → Chưa có trong DB, EM không biết đến object này

// 2. MANAGED: trong persistence context (first-level cache)
em.persist(user);
// → Sẽ INSERT khi flush/commit
// → Mọi thay đổi trên user object được track tự động (dirty checking)

// 3. Dirty checking – Hibernate theo dõi thay đổi
user.setEmail("alice@example.com"); // KHÔNG cần gọi em.update()!
// Hibernate so sánh current state với snapshot khi load
// → Tự động tạo UPDATE statement khi flush

em.getTransaction().commit(); // flush + commit

// 4. DETACHED: sau khi close EM hoặc gọi detach()
em.close();
// user vẫn tồn tại trong Java heap nhưng không còn được track
// Thay đổi user sau đây KHÔNG sync xuống DB

// 5. Merge DETACHED entity
EntityManager em2 = emFactory.createEntityManager();
em2.getTransaction().begin();
user.setPhone("0912345678"); // thay đổi khi detached
User managedUser = em2.merge(user); // MERGE: copy state vào managed entity
// managedUser (khác object với user) được track, sẽ UPDATE khi flush
em2.getTransaction().commit();

// 6. REMOVED
em2.remove(managedUser); // mark for deletion
em2.getTransaction().commit(); // DELETE statement
```

---

## How – Persistence Context (First-Level Cache)

Persistence context *(ngữ cảnh lưu trữ — vùng nhớ tạm theo dõi các entity trong một phiên/giao dịch)* = cache trong một EntityManager *(người quản lý entity, đại diện cho một phiên làm việc với DB)* (transaction scope):

> 💡 **Giải thích dễ hiểu — Persistence Context và First-Level Cache:**
> Trong một phiên làm việc (một `EntityManager`), JPA giữ một cuốn **sổ ghi nhớ tạm**. Lần đầu bạn `find(User, 1L)` nó chạy SQL lấy về rồi ghi vào sổ; những lần sau hỏi lại cùng id, nó **trả ngay từ sổ, không hỏi DB nữa** — đó là **first-level cache** *(bộ đệm cấp 1)*.
> Ví von: như bạn **hỏi thư ký về hồ sơ khách hàng số 1**. Lần đầu cô ấy xuống kho lấy (query DB); các lần sau trong cùng buổi làm việc, cô ấy nhớ và đưa ngay bản trên bàn — cùng một tờ giấy đó (nên `u1 == u2` là `true`, cùng một object). Sang buổi làm việc khác (EntityManager khác), sổ ghi nhớ mới toanh nên phải xuống kho lấy lại.
> Đây cũng là nền tảng của **dirty checking** *(tự dò thay đổi)*: vì giữ bản gốc trong sổ, đến lúc chốt sổ JPA so bản hiện tại với bản gốc, thấy khác ở đâu thì tự sinh UPDATE ở đó — nên bạn sửa field mà không cần gọi lệnh update.

```java
EntityManager em = emFactory.createEntityManager();

// First-level cache demo
User u1 = em.find(User.class, 1L); // SQL: SELECT * FROM users WHERE id=1
User u2 = em.find(User.class, 1L); // NO SQL! Trả về từ cache
User u3 = em.find(User.class, 1L); // NO SQL!

System.out.println(u1 == u2); // true! Cùng object reference
System.out.println(u1 == u3); // true!

// Mỗi EntityManager có cache riêng biệt
EntityManager em2 = emFactory.createEntityManager();
User u4 = em2.find(User.class, 1L); // SQL: SELECT lại (khác EM = khác cache)
System.out.println(u1 == u4); // false! Khác object

// Second-level cache (optional, shared across EMs):
// Ehcache, Caffeine, Hazelcast (configure separately)
```

### Flush Modes

```java
// FlushModeType.AUTO (default):
// Hibernate flush TRƯỚC khi execute JPQL query để đảm bảo consistency
em.setFlushMode(FlushModeType.AUTO);

// FlushModeType.COMMIT:
// Chỉ flush khi commit transaction
// Ít SQL hơn nhưng JPQL query có thể thấy stale data
em.setFlushMode(FlushModeType.COMMIT);

// Manual flush
em.flush(); // Sync tất cả pending changes xuống DB (nhưng chưa commit)
em.clear(); // Xóa persistence context cache (detach all entities)
em.detach(user); // Detach 1 entity cụ thể
```

---

## How – Entity Mapping

### Basic Mapping

```java
@Entity
@Table(name = "orders",
    indexes = {
        @Index(name = "idx_orders_customer", columnList = "customer_id"),
        @Index(name = "idx_orders_created", columnList = "created_at DESC")
    },
    uniqueConstraints = @UniqueConstraint(columnNames = {"order_number"})
)
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY) // DB auto-increment
    // Alternatives:
    // SEQUENCE: dùng DB sequence (PostgreSQL default, hiệu quả hơn IDENTITY)
    // UUID: @GeneratedValue(generator = "uuid2")
    // TABLE: portable nhưng chậm (lock table để generate)
    private Long id;

    @Column(name = "order_number", nullable = false, length = 50)
    private String orderNumber;

    @Column(name = "total_amount", precision = 19, scale = 4)
    private BigDecimal totalAmount;

    @Enumerated(EnumType.STRING) // "PENDING", "CONFIRMED", "SHIPPED"
    // Tránh EnumType.ORDINAL (0,1,2): nếu thêm enum value ở giữa → sai data!
    private OrderStatus status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at")
    private Instant updatedAt;

    @PrePersist // Lifecycle callback
    public void prePersist() {
        createdAt = Instant.now();
        updatedAt = Instant.now();
    }

    @PreUpdate
    public void preUpdate() {
        updatedAt = Instant.now();
    }

    // Embedded value object
    @Embedded
    private Address shippingAddress;
}

@Embeddable
public class Address {
    private String street;
    private String city;
    @Column(name = "postal_code")
    private String postalCode;
    private String country;
}
```

### Relationships

> 💡 **Giải thích dễ hiểu — "owning side" và mappedBy:**
> Quan hệ hai chiều (đơn hàng biết các item, item biết đơn hàng của mình) trong database chỉ thể hiện bằng **một cột khóa ngoại** (foreign key, ví dụ `order_id` nằm trong bảng `order_items`). Bên nào chứa cột khóa ngoại đó gọi là **owning side** *(phía sở hữu — phía "cầm" khóa ngoại, quyết định lưu quan hệ)*; phía còn lại chỉ là "phản chiếu" và khai báo `mappedBy` để trỏ về phía sở hữu.
> Ví von: hai vợ chồng đều biết mình đã kết hôn, nhưng **tờ giấy đăng ký kết hôn chỉ có một bản** do một bên giữ. Hibernate nhìn vào "bản giấy" (owning side) để biết cập nhật quan hệ; nếu bạn chỉ sửa phía `mappedBy` mà quên set phía owning, database sẽ không lưu gì cả. Vì thế mới cần helper `addItem()` set **cả hai chiều**.

```java
// @ManyToOne: owning side (có FK trong table)
@Entity
public class OrderItem {
    @Id @GeneratedValue(strategy = IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY) // LUÔN LAZY cho @ManyToOne
    @JoinColumn(name = "order_id", nullable = false)
    private Order order;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "product_id")
    private Product product;

    private int quantity;
    private BigDecimal unitPrice;
}

// @OneToMany: non-owning side (mappedBy = field name ở owning side)
@Entity
public class Order {
    // ...

    @OneToMany(
        mappedBy = "order",          // field name trong OrderItem
        cascade = CascadeType.ALL,   // persist/merge/remove cascade sang items
        orphanRemoval = true,        // xóa item không thuộc order nào
        fetch = FetchType.LAZY       // LUÔN LAZY cho @OneToMany
    )
    private List<OrderItem> items = new ArrayList<>();

    // Helper methods để maintain bidirectional relationship
    public void addItem(OrderItem item) {
        items.add(item);
        item.setOrder(this); // PHẢI set cả hai chiều!
    }

    public void removeItem(OrderItem item) {
        items.remove(item);
        item.setOrder(null);
    }
}

// @ManyToMany: join table
@Entity
public class Student {
    @Id @GeneratedValue(strategy = IDENTITY)
    private Long id;

    @ManyToMany
    @JoinTable(
        name = "student_course",         // join table name
        joinColumns = @JoinColumn(name = "student_id"),
        inverseJoinColumns = @JoinColumn(name = "course_id")
    )
    private Set<Course> courses = new HashSet<>();
}

@Entity
public class Course {
    @ManyToMany(mappedBy = "courses") // non-owning side
    private Set<Student> students = new HashSet<>();
}
```

---

## How – N+1 Problem (Quan trọng nhất!)

**N+1 problem** *(lỗi N+1 truy vấn — một trong những lỗi hiệu năng phổ biến nhất của ORM)*: load 1 list (1 query) → với mỗi item load related data *(dữ liệu liên quan)* (N queries) → N+1 total.

> 💡 **Giải thích dễ hiểu — N+1 query:**
> Bạn lấy về 100 đơn hàng bằng 1 câu query. Sau đó, mỗi lần đụng vào danh sách sản phẩm của một đơn, JPA lại âm thầm chạy thêm 1 query để lấy — 100 đơn thành 100 query phụ. Tổng cộng 1 + 100 = 101 query, thay vì đáng lẽ chỉ cần vài query.
> Ví von: bạn ra chợ mua đồ cho 100 món ăn. Cách N+1 giống như **mỗi nguyên liệu lại chạy về chợ một chuyến riêng**: 1 chuyến xem thực đơn + 100 chuyến mua lẻ. Cách đúng (JOIN FETCH / batch) là **cầm một danh sách rồi mua gộp trong 1–2 chuyến**. Số chuyến đi chợ chính là số lần "đi mạng" tới database — thứ đắt đỏ nhất, nên gộp lại là thắng lớn.
> Thủ phạm gốc là **lazy loading** *(nạp lười — chỉ nạp dữ liệu liên quan khi thực sự đụng tới)*: tiện vì không nạp thừa, nhưng nếu vô tình đụng trong vòng lặp thì mỗi lần đụng là một query mới.

```java
// N+1 Example – ANTI-PATTERN
List<Order> orders = em.createQuery("SELECT o FROM Order o", Order.class)
                       .getResultList(); // Query 1: SELECT * FROM orders

for (Order order : orders) {
    // Lazy loading trigger mỗi lần truy cập items!
    for (OrderItem item : order.getItems()) { // Query 2..N+1: SELECT * FROM order_items WHERE order_id=?
        System.out.println(item.getProduct().getName()); // Có thể thêm N query nữa cho product!
    }
}
// 100 orders → 101 queries minimum, có thể lên đến 10,001 queries!
```

### Fix 1: JOIN FETCH (JPQL)

```java
// Fetch orders kèm items trong 1 query (LEFT JOIN)
List<Order> orders = em.createQuery(
    "SELECT DISTINCT o FROM Order o " +
    "LEFT JOIN FETCH o.items i " +
    "LEFT JOIN FETCH i.product " +
    "WHERE o.status = :status",
    Order.class)
    .setParameter("status", OrderStatus.PENDING)
    .getResultList(); // 1 query với JOIN

// Chú ý: DISTINCT ngăn duplicate orders do Cartesian product
// Hibernate 6+: dùng HQL DISTINCT (không cần thêm vào SQL)
```

### Fix 2: @EntityGraph

```java
// Định nghĩa named graph
@Entity
@NamedEntityGraph(
    name = "Order.withItemsAndProducts",
    attributeNodes = {
        @NamedAttributeNode(value = "items",
            subgraph = "items-subgraph")
    },
    subgraphs = @NamedSubgraph(
        name = "items-subgraph",
        attributeNodes = @NamedAttributeNode("product")
    )
)
public class Order { ... }

// Dùng trong query
EntityGraph<?> graph = em.getEntityGraph("Order.withItemsAndProducts");
List<Order> orders = em.createQuery("SELECT o FROM Order o", Order.class)
    .setHint("jakarta.persistence.fetchgraph", graph)  // chỉ fetch graph attributes
    // hoặc "jakarta.persistence.loadgraph" → fetch graph + EAGER defaults
    .getResultList();

// Với Spring Data JPA
@EntityGraph(attributePaths = {"items", "items.product"})
List<Order> findByStatus(OrderStatus status);
```

### Fix 3: @BatchSize (Hibernate)

```java
// Load N items cùng lúc thay vì 1
@Entity
public class Order {
    @OneToMany(mappedBy = "order", fetch = LAZY)
    @BatchSize(size = 50)  // Hibernate load 50 orders' items cùng 1 lúc
    private List<OrderItem> items;
}
// 100 orders → 3 queries (1 + 2 batches of 50) thay vì 101 queries

// Global setting (application.properties)
// spring.jpa.properties.hibernate.default_batch_fetch_size=50
```

### Fix 4: DTO Projection (tốt nhất cho reporting)

```java
// Chỉ SELECT dữ liệu cần thiết, tránh load toàn bộ entity
record OrderSummary(Long id, String number, BigDecimal total, int itemCount) {}

List<OrderSummary> summaries = em.createQuery(
    "SELECT new com.example.dto.OrderSummary(" +
    "  o.id, o.orderNumber, o.totalAmount, SIZE(o.items)" +
    ") FROM Order o WHERE o.status = :status",
    OrderSummary.class)
    .setParameter("status", OrderStatus.PENDING)
    .getResultList();
// Chỉ SELECT 4 columns, không load items collection
```

---

## How – JPQL vs Criteria API vs Native SQL

### JPQL (Java Persistence Query Language)

```java
// JPQL: dùng entity names/fields (không phải table/column names)
List<User> users = em.createQuery(
    "SELECT u FROM User u " +
    "WHERE u.email LIKE :pattern " +
    "AND u.createdAt > :since " +
    "ORDER BY u.name ASC",
    User.class)
    .setParameter("pattern", "%@example.com")
    .setParameter("since", Instant.now().minus(30, DAYS))
    .setMaxResults(100)
    .setFirstResult(0)  // offset (pagination)
    .getResultList();

// Aggregate functions
Long count = em.createQuery(
    "SELECT COUNT(u) FROM User u WHERE u.status = 'ACTIVE'",
    Long.class).getSingleResult();

// GROUP BY + HAVING
List<Object[]> result = em.createQuery(
    "SELECT u.department, COUNT(u), AVG(u.salary) " +
    "FROM User u " +
    "GROUP BY u.department " +
    "HAVING COUNT(u) > 5")
    .getResultList();

// Named Query (pre-compiled, validated at startup)
@Entity
@NamedQuery(
    name = "User.findByEmail",
    query = "SELECT u FROM User u WHERE u.email = :email"
)
public class User { ... }

User user = em.createNamedQuery("User.findByEmail", User.class)
    .setParameter("email", "alice@example.com")
    .getSingleResult();
```

### Criteria API (Type-safe, dynamic queries)

```java
// Criteria API: build query programmatically (type-safe, no string SQL)
CriteriaBuilder cb = em.getCriteriaBuilder();
CriteriaQuery<User> query = cb.createQuery(User.class);
Root<User> user = query.from(User.class);

// Dynamic predicates
List<Predicate> predicates = new ArrayList<>();
if (name != null) {
    predicates.add(cb.like(user.get("name"), "%" + name + "%"));
}
if (status != null) {
    predicates.add(cb.equal(user.get("status"), status));
}
if (createdAfter != null) {
    predicates.add(cb.greaterThan(user.get("createdAt"), createdAfter));
}

query.where(predicates.toArray(new Predicate[0]));
query.orderBy(cb.desc(user.get("createdAt")));

List<User> users = em.createQuery(query)
    .setMaxResults(pageSize)
    .setFirstResult(page * pageSize)
    .getResultList();

// Metamodel API (generated, truly type-safe):
// predicates.add(cb.like(user.get(User_.name), "%" + name + "%")); // User_ = generated
```

### Native SQL (khi JPQL không đủ)

```java
// Native SQL: khi cần DB-specific features
List<Object[]> result = em.createNativeQuery(
    "SELECT u.id, u.name, COUNT(o.id) AS order_count " +
    "FROM users u " +
    "LEFT JOIN orders o ON o.user_id = u.id AND o.created_at > NOW() - INTERVAL '30 days' " +
    "GROUP BY u.id, u.name " +
    "HAVING COUNT(o.id) > :minOrders " +
    "ORDER BY order_count DESC " +
    "LIMIT :limit")
    .setParameter("minOrders", 5)
    .setParameter("limit", 100)
    .getResultList();

// Map native query result → @SqlResultSetMapping
@SqlResultSetMapping(
    name = "UserOrderCountMapping",
    classes = @ConstructorResult(
        targetClass = UserOrderCount.class,
        columns = {
            @ColumnResult(name = "id", type = Long.class),
            @ColumnResult(name = "name"),
            @ColumnResult(name = "order_count", type = Long.class)
        }
    )
)
@Entity
public class User { ... }

List<UserOrderCount> result = em.createNativeQuery(sql, "UserOrderCountMapping")
    .getResultList();
```

---

## How – Optimistic vs Pessimistic Locking

> 💡 **Giải thích dễ hiểu — Optimistic vs Pessimistic:**
> Cả hai đều nhằm tránh hai người cùng sửa một dữ liệu rồi đè lên nhau.
> - **Optimistic Locking** *(khóa lạc quan)*: "cứ tin là hiếm khi đụng nhau". Không khóa gì cả, chỉ gắn cho bản ghi một số phiên bản (`@Version`). Lúc lưu mới kiểm tra: nếu số phiên bản đã bị người khác đổi nghĩa là có xung đột → báo lỗi, bảo thử lại.
>   Ví von: **sửa chung một tài liệu Google Docs offline**. Ai cũng chép về sửa; lúc nộp lên, nếu phát hiện bản gốc đã bị người khác đổi thì phải làm lại — hợp khi ít khi trùng giờ.
> - **Pessimistic Locking** *(khóa bi quan)*: "chắc chắn sẽ có người tranh nên khóa trước cho yên tâm". Vừa đọc đã khóa luôn dòng đó (`SELECT ... FOR UPDATE`), người khác phải chờ tới lượt.
>   Ví von: **mượn chìa khóa phòng họp**. Ai vào trước cầm chìa khóa, người sau đứng ngoài đợi — chắc chắn không đụng nhau nhưng phải xếp hàng.
> Chọn optimistic khi đọc nhiều/ghi ít/ít đụng độ (CRUD người dùng); chọn pessimistic khi ghi nhiều, đụng độ cao, cần chắc chắn (ngân hàng, trừ tồn kho).

### Optimistic Locking (@Version)

```java
// Optimistic: không lock, chỉ check version khi UPDATE
@Entity
public class Product {
    @Id @GeneratedValue(strategy = IDENTITY)
    private Long id;

    private String name;
    private int stock;

    @Version  // Hibernate tự quản lý: tăng lên mỗi UPDATE
    private Long version;
}

// Kịch bản:
// User A đọc Product{id=1, stock=100, version=5}
// User B đọc Product{id=1, stock=100, version=5}
// User A update: stock=90, version tăng lên 6
// User B update: WHERE id=1 AND version=5 → 0 rows affected!
// → OptimisticLockException (Hibernate tự throw)

// Hibernate SQL tạo ra:
// UPDATE products SET stock=?, version=? WHERE id=? AND version=?
//                                                  ↑ check version cũ
// Nếu version không khớp → 0 rows → OptimisticLockException

// Handle conflict
@Transactional
public void deductStock(Long productId, int quantity) {
    try {
        Product p = em.find(Product.class, productId);
        if (p.getStock() < quantity) throw new InsufficientStockException();
        p.setStock(p.getStock() - quantity);
        // commit → OptimisticLockException nếu conflict
    } catch (OptimisticLockException e) {
        // Retry logic hoặc inform user
        throw new ConcurrentUpdateException("Product was modified, please retry");
    }
}
```

### Pessimistic Locking

```java
// Pessimistic: lock DB row ngay khi đọc (SELECT ... FOR UPDATE)

// Pessimistic WRITE: ngăn đọc và ghi
Product product = em.find(Product.class, id,
    LockModeType.PESSIMISTIC_WRITE);
// SQL: SELECT * FROM products WHERE id=? FOR UPDATE

// Pessimistic READ: ngăn ghi (shared lock)
Product product = em.find(Product.class, id,
    LockModeType.PESSIMISTIC_READ);
// SQL: SELECT * FROM products WHERE id=? FOR SHARE (PostgreSQL)

// Timeout để tránh deadlock
Map<String, Object> hints = Map.of(
    "jakarta.persistence.lock.timeout", 5000L); // 5 seconds
Product product = em.find(Product.class, id,
    LockModeType.PESSIMISTIC_WRITE, hints);
// Ném LockTimeoutException nếu chờ quá 5 giây

// Khi nào dùng:
// Optimistic: đọc nhiều, write ít, conflict rate thấp (user-facing CRUD)
// Pessimistic: write nhiều, conflict rate cao, cần guarantee (banking, inventory)
```

---

## How – Inheritance Mapping

```java
// 3 strategies:

// 1. SINGLE_TABLE (default, fastest queries, nullable columns)
@Entity
@Inheritance(strategy = InheritanceType.SINGLE_TABLE)
@DiscriminatorColumn(name = "type", discriminatorType = DiscriminatorType.STRING)
public abstract class Payment {
    @Id @GeneratedValue private Long id;
    protected BigDecimal amount;
}

@Entity @DiscriminatorValue("CARD")
public class CardPayment extends Payment {
    private String cardNumber; // nullable trong DB (chỉ có khi type=CARD)
    private String cvv;
}

@Entity @DiscriminatorValue("BANK")
public class BankTransfer extends Payment {
    private String bankAccount; // nullable (chỉ có khi type=BANK)
    private String routingNumber;
}

// → 1 table payments với tất cả columns
// Query: SELECT * FROM payments WHERE type = 'CARD'

// 2. TABLE_PER_CLASS (no joins, duplicate columns, no polymorphic query)
@Entity
@Inheritance(strategy = InheritanceType.TABLE_PER_CLASS)
public abstract class Payment { ... }
// → table card_payment (có id, amount, card_number, cvv)
// → table bank_transfer (có id, amount, bank_account, routing_number)

// 3. JOINED (normalized, joins required)
@Entity
@Inheritance(strategy = InheritanceType.JOINED)
public abstract class Payment { ... }
// → table payments (id, amount)
// → table card_payment (id FK, card_number, cvv)
// → table bank_transfer (id FK, bank_account, routing_number)
// Query: SELECT ... FROM payments JOIN card_payment ON ...
```

---

## Why – Tại sao JPA/Hibernate?

| Vấn đề thuần JDBC | JPA giải quyết |
|------------------|----------------|
| Manual map ResultSet → Object | @Entity tự map |
| Quản lý state thủ công | Entity lifecycle, dirty checking |
| Không có lazy loading | @OneToMany(fetch=LAZY) |
| Không có cache | First/Second level cache |
| Viết lại SQL cho mỗi DB | JPQL portable (Hibernate generate SQL theo dialect) |
| Không có relationship management | Cascade, orphanRemoval |

---

## Compare – JPQL vs Criteria API vs Native SQL

| | JPQL | Criteria API | Native SQL |
|--|------|-------------|-----------|
| Type-safe | Không (string) | Có (compile check) | Không |
| Dynamic query | Khó (string concat) | Dễ | Khó |
| Readable | Cao | Thấp (verbose) | Cao |
| DB-specific features | Không | Không | Có |
| Performance | Tốt | Tốt | Tốt nhất |
| Use case | Static queries | Dynamic filter/search | Complex reporting |

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Productivity cao | N+1 problem nếu không cẩn thận |
| Portable qua databases | Learning curve cao |
| Cache tích hợp | Magic SQL có thể không optimal |
| Relationship management | Lazy loading exception ngoài session |
| Dirty checking tự động | Config phức tạp (cascade, fetch type) |

---

## Real-world Usage (Production)

### 1. Avoid LazyInitializationException

```java
// PROBLEM: Entity detached khi truy cập lazy collection
@RestController
public class OrderController {
    @GetMapping("/orders/{id}")
    public OrderDto getOrder(@PathVariable Long id) {
        Order order = orderService.findById(id); // transaction kết thúc ở đây!
        order.getItems().size(); // LazyInitializationException! Session đã đóng
    }
}

// FIX 1: Fetch trong transaction
@Service
@Transactional(readOnly = true) // transaction còn sống trong service
public class OrderService {
    public OrderDto getOrderWithItems(Long id) {
        Order order = repo.findByIdWithItems(id); // JOIN FETCH
        return OrderDto.from(order); // convert trong transaction
    }
}

// FIX 2: DTO projection (không cần load entity)
@Query("SELECT new com.example.dto.OrderDto(o.id, o.number, o.total) FROM Order o WHERE o.id = :id")
Optional<OrderDto> findOrderDtoById(@Param("id") Long id);

// FIX 3: Open Session in View (ANTI-PATTERN! Tránh dùng)
// spring.jpa.open-in-view=false (luôn tắt trong production)
```

### 2. Hibernate Statistics (Debug N+1)

```yaml
spring:
  jpa:
    properties:
      hibernate:
        generate_statistics: true
        format_sql: true
      logging:
        level:
          org.hibernate.stat: DEBUG
          org.hibernate.SQL: DEBUG
          org.hibernate.orm.jdbc.bind: TRACE
```

```java
// Programmatic check trong tests
Statistics stats = sessionFactory.getStatistics();
stats.clear();

// ... run code ...

System.out.println("Queries: " + stats.getQueryExecutionCount());
// Nếu > expected → N+1 problem!
```

### 3. Soft Delete với @SQLDelete

```java
@Entity
@SQLDelete(sql = "UPDATE users SET deleted_at = NOW() WHERE id = ?")
@Where(clause = "deleted_at IS NULL") // Hibernate tự động thêm vào mọi query
public class User {
    @Id private Long id;
    @Column(name = "deleted_at")
    private Instant deletedAt;
}

// em.remove(user) → UPDATE users SET deleted_at = NOW() (không DELETE thực)
// em.find(User.class, id) → SELECT ... WHERE id=? AND deleted_at IS NULL
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **Spring Data JPA**
>
> Keyword: Repository interfaces (CrudRepository/JpaRepository/PagingAndSortingRepository), query derivation method names (findBy.../countBy.../existsBy..../deleteBy...), @Query annotation (JPQL/native/modifying), Specification pattern (dynamic queries), Pageable + Page + Slice (pagination), @CreatedDate/@LastModifiedDate/@EntityListeners(AuditingEntityListener), projections (interface/DTO/dynamic), custom repository implementation
