# JDBC & Connection Pooling

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – JDBC là gì?

**JDBC (Java Database Connectivity)** *(bộ API chuẩn để Java "nói chuyện" với database)* là API *(giao diện lập trình — tập hàm/lớp có sẵn để gọi)* chuẩn của Java để kết nối và tương tác với relational databases *(cơ sở dữ liệu quan hệ — dữ liệu lưu dạng bảng có quan hệ với nhau)*. JDBC cung cấp tầng abstraction *(lớp trừu tượng — che đi chi tiết bên dưới)* giữa Java code và database-specific drivers *(trình điều khiển riêng của từng loại database)*.

> 💡 **Giải thích dễ hiểu:**
> Mỗi loại database (MySQL, PostgreSQL, Oracle...) nói một "ngôn ngữ" giao tiếp riêng ở tầng thấp. Nếu code Java phải học riêng từng ngôn ngữ đó thì đổi database là phải viết lại hết.
> Ví von: JDBC giống như **ổ cắm điện chuẩn quốc gia**. Thiết bị (code Java) chỉ cần cắm vào ổ chuẩn; còn việc điện lấy từ thủy điện, nhiệt điện hay điện mặt trời (database nào) là do "dây nối phía sau" — chính là **driver** — lo. Đổi nhà cung cấp điện, bạn chỉ đổi dây phía sau, thiết bị giữ nguyên. Nhờ vậy đổi từ MySQL sang PostgreSQL, code JDBC gần như không phải sửa.

```
Java Application
      ↓
JDBC API (java.sql.*)
      ↓
JDBC Driver (database-specific: mysql-connector, postgresql-jdbc...)
      ↓
Database (MySQL, PostgreSQL, Oracle...)
```

**4 thành phần cốt lõi:**
1. **DriverManager** *(người quản lý các driver)* – quản lý drivers, tạo connections *(kết nối)*
2. **Connection** *(một phiên kết nối tới database)* – kết nối tới database
3. **Statement/PreparedStatement** *(câu lệnh SQL để thực thi)* – thực thi SQL
4. **ResultSet** *(tập kết quả trả về, duyệt theo từng dòng)* – kết quả trả về

> 💡 **Giải thích dễ hiểu — 4 thành phần này phối hợp thế nào:**
> Hình dung bạn gọi món ở nhà hàng: **DriverManager** là lễ tân sắp cho bạn một bàn (tạo **Connection**); **Connection** là chiếc bàn bạn ngồi để làm việc với bếp (database); **Statement/PreparedStatement** là tờ order ghi món (câu lệnh SQL) bạn đưa cho phục vụ; **ResultSet** là mâm đồ ăn bưng ra, bạn gắp từng đĩa một (duyệt từng dòng kết quả). Hiểu 4 vai này thì mọi đoạn code JDBC bên dưới đều dễ theo.

---

## How – JDBC Connection

### Kết nối cơ bản (không nên dùng trong production)

```java
// Không cần Class.forName() từ Java 6 (ServiceLoader tự load driver)
String url = "jdbc:postgresql://localhost:5432/mydb";
String user = "myuser";
String password = "secret";

try (Connection conn = DriverManager.getConnection(url, user, password)) {
    // Connection được tạo mới mỗi lần → tốn kém!
    // try-with-resources → auto close
    System.out.println("Connected: " + !conn.isClosed());
}
```

### JDBC URL format

```
jdbc:<subprotocol>://<host>:<port>/<database>[?params]

PostgreSQL: jdbc:postgresql://localhost:5432/mydb?sslmode=require
MySQL:      jdbc:mysql://localhost:3306/mydb?useSSL=false&serverTimezone=UTC
H2:         jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1
Oracle:     jdbc:oracle:thin:@localhost:1521:orcl
SQL Server: jdbc:sqlserver://localhost:1433;databaseName=mydb
```

---

## How – Statement vs PreparedStatement

### Statement – SQL injection vulnerability

```java
// NGUY HIỂM: SQL Injection
String userInput = "'; DROP TABLE users; --";
String sql = "SELECT * FROM users WHERE name = '" + userInput + "'";
// SQL thực sự:
// SELECT * FROM users WHERE name = ''; DROP TABLE users; --'
// → XÓA TOÀN BỘ TABLE!

try (Statement stmt = conn.createStatement()) {
    ResultSet rs = stmt.executeQuery(sql); // Thảm họa!
}
```

### PreparedStatement – Chuẩn, an toàn, hiệu quả

```java
// AN TOÀN: parameterized query
String sql = "SELECT * FROM users WHERE email = ? AND status = ?";
try (PreparedStatement ps = conn.prepareStatement(sql)) {
    ps.setString(1, email);      // index bắt đầu từ 1 (không phải 0!)
    ps.setString(2, "ACTIVE");

    try (ResultSet rs = ps.executeQuery()) {
        while (rs.next()) {
            long id     = rs.getLong("id");
            String name = rs.getString("name");
            String mail = rs.getString("email");
            LocalDate dob = rs.getObject("date_of_birth", LocalDate.class); // Java 8+
            System.out.printf("User: %d, %s, %s%n", id, name, mail);
        }
    }
}

// INSERT với auto-generated key
String insertSql = "INSERT INTO users (name, email) VALUES (?, ?)";
try (PreparedStatement ps = conn.prepareStatement(insertSql,
                                Statement.RETURN_GENERATED_KEYS)) {
    ps.setString(1, "Alice");
    ps.setString(2, "alice@example.com");
    ps.executeUpdate();

    try (ResultSet keys = ps.getGeneratedKeys()) {
        if (keys.next()) {
            long generatedId = keys.getLong(1);
            System.out.println("Created with ID: " + generatedId);
        }
    }
}
```

### Tại sao PreparedStatement an toàn hơn?

> 💡 **Giải thích dễ hiểu — SQL Injection và cách PreparedStatement chặn:**
> **SQL Injection** *(tấn công tiêm mã SQL)* xảy ra khi bạn nối thẳng dữ liệu người dùng vào chuỗi SQL. Kẻ xấu nhập một đoạn "dữ liệu" thực ra là mã lệnh, và database vô tình chạy luôn mã đó.
> Ví von: giống như bạn đọc cho thư ký ghi một lá thư. Với **Statement** (nối chuỗi), bạn đọc liền một mạch — nếu người ta chèn câu "...và xé hết hồ sơ đi", thư ký nghe không phân biệt được đâu là nội dung thư đâu là mệnh lệnh, cứ thế làm theo.
> Với **PreparedStatement** *(câu lệnh biên dịch sẵn với chỗ trống)*, bạn đưa trước cho database một biểu mẫu có sẵn các ô trống `?` và nói rõ: "cấu trúc câu lệnh là đây, cố định rồi". Sau đó dữ liệu người dùng chỉ được **điền vào ô trống** như điền form — dù có viết gì trong ô đó cũng chỉ được coi là chữ trong ô, không bao giờ được đọc thành lệnh mới. Đó là lý do dữ liệu độc hại trở nên vô hại.

```
Database xử lý PreparedStatement:
1. PARSE phase: database parses SQL template (với ?)
2. Database biết: "?" là data, KHÔNG phải SQL code
3. BIND phase: giá trị được bind vào đúng vị trí
4. EXECUTE phase: chạy với data đã bind

→ Dù data chứa "'; DROP TABLE..." → vẫn là chuỗi thuần túy, không parse thêm
→ Statement cũ: concatenate vào SQL text → database parse cả "inject code"
```

**Lợi ích thêm của PreparedStatement:**
- **Hiệu suất**: database cache execution plan → re-use nếu gọi nhiều lần
- **Type safety**: `setInt/setString/setDate` → tránh lỗi type mismatch
- **Readable**: code rõ ràng, không concat string

---

## How – Batch Operations

```java
// Batch INSERT: thay vì N queries → 1 batch
String sql = "INSERT INTO products (name, price, stock) VALUES (?, ?, ?)";
try (PreparedStatement ps = conn.prepareStatement(sql)) {
    conn.setAutoCommit(false); // QUAN TRỌNG: tắt auto-commit cho batch

    for (Product p : products) {
        ps.setString(1, p.getName());
        ps.setBigDecimal(2, p.getPrice());
        ps.setInt(3, p.getStock());
        ps.addBatch(); // thêm vào batch, chưa execute

        if (i % 1000 == 0) {  // flush mỗi 1000 records
            ps.executeBatch(); // gửi batch tới DB
            conn.commit();
            ps.clearBatch();
        }
    }
    ps.executeBatch(); // flush remaining
    conn.commit();
} catch (SQLException e) {
    conn.rollback(); // rollback nếu lỗi
    throw e;
}

// Kết quả executeBatch(): int[] với số rows affected mỗi statement
// Statement.SUCCESS_NO_INFO (-2): thành công nhưng không biết số rows
// Statement.EXECUTE_FAILED (-3): statement này fail
```

---

## How – Transaction Management

```java
// Manual transaction
Connection conn = dataSource.getConnection();
try {
    conn.setAutoCommit(false);
    conn.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);

    // Thực hiện nhiều operations
    debit(conn, fromAccount, amount);
    credit(conn, toAccount, amount);
    logTransaction(conn, fromAccount, toAccount, amount);

    conn.commit(); // Tất cả thành công
} catch (Exception e) {
    conn.rollback(); // Bất kỳ lỗi nào → rollback toàn bộ
    throw new RuntimeException("Transaction failed", e);
} finally {
    conn.setAutoCommit(true);
    conn.close(); // Trả về pool
}

// Savepoint (partial rollback)
Savepoint sp = conn.setSavepoint("before_bonus");
try {
    insertBonus(conn, employeeId, bonus);
    // Nếu lỗi riêng bonus, rollback về savepoint thôi
} catch (SQLException e) {
    conn.rollback(sp); // Không rollback toàn bộ transaction
}
```

---

## How – ResultSet Navigation

```java
try (PreparedStatement ps = conn.prepareStatement(
        "SELECT * FROM orders",
        ResultSet.TYPE_SCROLL_INSENSITIVE,  // có thể scroll
        ResultSet.CONCUR_READ_ONLY)) {

    ResultSet rs = ps.executeQuery();

    rs.last();
    int totalRows = rs.getRow();  // lấy tổng số rows

    rs.beforeFirst();  // về đầu
    while (rs.next()) {
        // ...
    }

    rs.absolute(5);  // nhảy đến row 5
    rs.relative(-2); // di chuyển ngược lại 2 rows
}

// ResultSet types:
// TYPE_FORWARD_ONLY (default): chỉ đi tiến, hiệu quả nhất
// TYPE_SCROLL_INSENSITIVE: scroll nhưng không thấy DB changes
// TYPE_SCROLL_SENSITIVE: scroll và thấy DB changes (chậm, ít dùng)

// ResultSet metadata
ResultSetMetaData meta = rs.getMetaData();
int cols = meta.getColumnCount();
for (int i = 1; i <= cols; i++) {
    System.out.printf("%s (%s)%n",
        meta.getColumnName(i),
        meta.getColumnTypeName(i));
}
```

---

## How – Connection Pooling

**Vấn đề với DriverManager.getConnection():**
- Tạo connection tốn kém: TCP handshake *(bắt tay ba bước để mở kết nối mạng)* + DB authentication *(xác thực đăng nhập database)* + session setup ≈ 50–100ms
- Mỗi request tạo/đóng connection → bottleneck *(nút thắt cổ chai — điểm làm chậm cả hệ thống)* nghiêm trọng

**Connection Pool** *(bể chứa sẵn các kết nối để tái sử dụng)* = pool của connections được tái sử dụng:

> 💡 **Giải thích dễ hiểu — vì sao cần Connection Pool:**
> Mở một kết nối database mất 50–100ms vì phải bắt tay mạng, đăng nhập, thiết lập phiên — rất tốn so với bản thân câu query chỉ mất vài ms. Nếu mỗi request đều mở rồi đóng kết nối, phần lớn thời gian bị đốt vào việc "mở cửa" chứ không phải làm việc.
> Ví von: giống một **hãng taxi**. Nếu mỗi lần có khách mới đi tuyển tài xế, mua xe, đăng ký biển số rồi xong chuyến lại bán xe đi thì quá phí. Thay vào đó hãng **nuôi sẵn một đội xe (pool)**: khách cần thì điều một xe đang rảnh, đi xong xe quay về bãi chờ khách tiếp theo. **Connection Pool** chính là đội xe kết nối luôn sẵn sàng — mượn cực nhanh (~0.1ms), dùng xong trả lại chứ không hủy. Khi hết xe rảnh, khách mới phải xếp hàng chờ (WAIT).

```
Application Request 1 ──→ [Pool] ──→ Connection A (in use)
Application Request 2 ──→ [Pool] ──→ Connection B (in use)
Application Request 3 ──→ [Pool] ──→ Connection C (in use)
Application Request 4 ──→ [Pool] ──→ WAIT (pool full)

Request 1 done → Connection A trả về Pool
Application Request 4 ──→ Connection A (reused!)
```

---

## How – HikariCP (Industry Standard Pool)

**HikariCP** là connection pool nhanh nhất cho Java, được Spring Boot dùng mặc định.

```java
// Manual config
HikariConfig config = new HikariConfig();
config.setJdbcUrl("jdbc:postgresql://localhost:5432/mydb");
config.setUsername("user");
config.setPassword("password");
config.setDriverClassName("org.postgresql.Driver");

// Pool sizing
config.setMaximumPoolSize(10);       // max connections (default 10)
config.setMinimumIdle(5);            // min connections duy trì khi idle
config.setConnectionTimeout(30000);  // ms chờ lấy connection từ pool
config.setIdleTimeout(600000);       // ms connection được idle trước khi close
config.setMaxLifetime(1800000);      // ms connection sống tối đa (< DB timeout)
config.setKeepaliveTime(60000);      // ms gửi keepalive query

// Connection validation
config.setConnectionTestQuery("SELECT 1"); // query test connection (PostgreSQL không cần)
config.setValidationTimeout(5000);

// Performance tuning
config.addDataSourceProperty("cachePrepStmts", "true");
config.addDataSourceProperty("prepStmtCacheSize", "250");
config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");
config.addDataSourceProperty("useServerPrepStmts", "true");

HikariDataSource dataSource = new HikariDataSource(config);
```

```yaml
# Spring Boot application.yml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/mydb
    username: myuser
    password: ${DB_PASSWORD}
    driver-class-name: org.postgresql.Driver
    hikari:
      maximum-pool-size: 10
      minimum-idle: 5
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
      pool-name: MyApp-Pool
```

### HikariCP Pool Sizing Formula

> 💡 **Giải thích dễ hiểu — vì sao pool to hơn chưa chắc nhanh hơn:**
> Trực giác thường nghĩ "cứ tăng số kết nối là chạy nhanh hơn". Sai. Database chỉ có ngần ấy CPU core và ổ đĩa; số việc chạy song song thực sự bị giới hạn ở đó.
> Ví von: một **quầy thu ngân siêu thị**. Mở thêm quầy giúp bớt xếp hàng — nhưng chỉ tới khi hết nhân viên. Nếu cố ép 50 khách chen vào 8 quầy thật, họ giẫm chân nhau, nhân viên loay hoay chuyển qua chuyển lại (DB context switching) và mọi người còn chậm hơn. Vì thế công thức khuyến nghị pool nhỏ gọn quanh `số core × 2 + số đĩa` chứ không phải càng nhiều càng tốt.

```
Pool Size = Tn × (Cm - 1) + 1  (Little's Law biến thể)

Tn = số threads đồng thời tối đa
Cm = số DB calls một transaction cần

Thực tế: ((core_count × 2) + effective_spindle_count)
SSD: effective_spindle_count = 1
HDD: effective_spindle_count = thực tế

Ví dụ: 8 cores, SSD → pool size ≈ (8×2) + 1 = 17

⚠️ Pool quá lớn có thể CHẬM hơn: DB context switching + memory pressure
```

### HikariCP Lifecycle

```
1. Pool khởi tạo → tạo minimumIdle connections
2. Request lấy connection:
   a. Có connection idle → trả ngay (< connectionTimeout ms)
   b. Pool chưa full → tạo connection mới
   c. Pool full, tất cả in-use → WAIT (connectionTimeout ms)
   d. Timeout → SQLTimeoutException
3. Connection trả về pool:
   a. Không đóng thực sự, chỉ reset state (autoCommit, isolation level)
   b. Kiểm tra validity → nếu stale → đóng và tạo mới
4. Background:
   a. keepaliveTime → gửi heartbeat để giữ connection sống
   b. maxLifetime → định kỳ thay thế connection cũ bằng mới
   c. idleTimeout → đóng connection idle quá lâu (pool > minimumIdle)
```

---

## How – JdbcTemplate (Spring)

JdbcTemplate wrap *(bọc lại)* JDBC boilerplate *(đoạn code lặp đi lặp lại nhàm chán — mở/đóng kết nối, bắt exception)* (open/close connection, handle exceptions):

> 💡 **Giải thích dễ hiểu:**
> Viết JDBC "trần" phải lặp lại hoài mấy bước: xin connection → tạo statement → chạy → duyệt kết quả → nhớ đóng mọi thứ → bắt `SQLException`. Đoạn khung này (boilerplate) chiếm phần lớn code và rất dễ quên đóng gây rò rỉ.
> Ví von: **JdbcTemplate** như một **bộ đồ nấu ăn có sẵn nồi, bếp, và tự rửa dọn**. Bạn chỉ cần đưa "công thức" (câu SQL) và cách bày món ra đĩa (RowMapper — hàm biến một dòng kết quả thành object), còn mọi việc bật bếp, tắt bếp, lau dọn (mở/đóng connection, xử lý lỗi) nó lo hết.

```java
@Repository
public class UserRepository {
    private final JdbcTemplate jdbc;

    public UserRepository(DataSource dataSource) {
        this.jdbc = new JdbcTemplate(dataSource);
    }

    // Query single value
    public long countActive() {
        return jdbc.queryForObject(
            "SELECT COUNT(*) FROM users WHERE status = ?",
            Long.class, "ACTIVE");
    }

    // Query single row → object
    public Optional<User> findById(long id) {
        try {
            User user = jdbc.queryForObject(
                "SELECT id, name, email, created_at FROM users WHERE id = ?",
                (rs, rowNum) -> new User(     // RowMapper
                    rs.getLong("id"),
                    rs.getString("name"),
                    rs.getString("email"),
                    rs.getTimestamp("created_at").toInstant()
                ),
                id);
            return Optional.of(user);
        } catch (EmptyResultDataAccessException e) {
            return Optional.empty(); // không ném exception nếu không tìm thấy
        }
    }

    // Query list
    public List<User> findByStatus(String status) {
        return jdbc.query(
            "SELECT * FROM users WHERE status = ? ORDER BY created_at DESC",
            this::mapRow,     // method reference tới RowMapper
            status);
    }

    // RowMapper tách riêng
    private User mapRow(ResultSet rs, int rowNum) throws SQLException {
        return new User(
            rs.getLong("id"),
            rs.getString("name"),
            rs.getString("email"),
            rs.getTimestamp("created_at").toInstant()
        );
    }

    // Update (INSERT/UPDATE/DELETE)
    public int save(User user) {
        return jdbc.update(
            "INSERT INTO users (name, email, status) VALUES (?, ?, ?)",
            user.getName(), user.getEmail(), "ACTIVE");
    }

    // KeyHolder: lấy auto-generated key sau INSERT
    public long insert(User user) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbc.update(conn -> {
            PreparedStatement ps = conn.prepareStatement(
                "INSERT INTO users (name, email) VALUES (?, ?)",
                Statement.RETURN_GENERATED_KEYS);
            ps.setString(1, user.getName());
            ps.setString(2, user.getEmail());
            return ps;
        }, keyHolder);
        return keyHolder.getKey().longValue();
    }

    // Batch update
    public int[] batchInsert(List<User> users) {
        return jdbc.batchUpdate(
            "INSERT INTO users (name, email) VALUES (?, ?)",
            users,
            100,  // batch size
            (ps, user) -> {
                ps.setString(1, user.getName());
                ps.setString(2, user.getEmail());
            });
    }

    // Named parameters với NamedParameterJdbcTemplate
    // (chuyển ? → :paramName để code dễ đọc hơn)
}
```

```java
// NamedParameterJdbcTemplate: dùng :name thay vì ?
@Repository
public class ProductRepository {
    private final NamedParameterJdbcTemplate namedJdbc;

    public List<Product> findByIds(List<Long> ids) {
        MapSqlParameterSource params = new MapSqlParameterSource();
        params.addValue("ids", ids);

        return namedJdbc.query(
            "SELECT * FROM products WHERE id IN (:ids)",
            params,
            (rs, row) -> new Product(rs.getLong("id"), rs.getString("name")));
    }

    public void update(Product p) {
        SqlParameterSource params = new BeanPropertySqlParameterSource(p); // map từ bean properties
        namedJdbc.update(
            "UPDATE products SET name = :name, price = :price WHERE id = :id",
            params);
    }
}
```

---

## How – DataSource Exception Hierarchy

```
SQLException (checked, java.sql)
  ├── SQLTransientException
  │     ├── SQLTransientConnectionException (connection issues, retry-able)
  │     ├── SQLTransactionRollbackException (deadlock, retry-able)
  │     └── SQLTimeoutException
  ├── SQLNonTransientException
  │     ├── SQLDataException (data error: wrong type, constraint)
  │     ├── SQLFeatureNotSupportedException
  │     └── SQLSyntaxErrorException
  └── SQLRecoverableException (reconnect may help)

Spring chuyển → DataAccessException (unchecked):
  ├── TransientDataAccessException (retry có thể giúp)
  │     ├── QueryTimeoutException
  │     └── TransactionException
  ├── NonTransientDataAccessException
  │     ├── DataIntegrityViolationException (duplicate key, FK violation)
  │     ├── EmptyResultDataAccessException (expected 1 row, got 0)
  │     └── IncorrectResultSizeDataAccessException
  └── RecoverableDataAccessException
```

---

## Components – So sánh JDBC APIs

| | Statement | PreparedStatement | CallableStatement |
|--|-----------|-------------------|-------------------|
| SQL | Dynamic | Parameterized | Stored procedure |
| SQL Injection | Vulnerable | Safe | Safe |
| Performance | No cache | Plan cache | Pre-compiled |
| Use case | DDL | DML (CRUD) | Stored procedures |
| Batch | Có | Có (efficient) | Có |

---

## Why – Tại sao cần Connection Pool?

```
Không có pool (mỗi request tạo connection mới):
  Request → createConnection(~100ms) → query(~5ms) → closeConnection(~5ms)
  1000 req/s → 100,000ms overhead PER SECOND cho connection creation!

Với HikariCP:
  Request → getFromPool(~0.1ms) → query(~5ms) → returnToPool(~0.1ms)
  1000 req/s → 100ms overhead total (connections pre-created)
  → 1000x improvement!
```

---

## When – Khi nào dùng JDBC trực tiếp?

**Nên dùng JDBC/JdbcTemplate:**
- Cần full SQL control (complex queries, DB-specific features)
- Performance-critical: bulk operations, stored procedures
- Reporting queries (aggregate, joins phức tạp)
- Không cần ORM overhead
- Greenfield projects chọn simplicity over abstraction

**Nên dùng JPA/Hibernate:**
- CRUD đơn giản trên domain objects
- Cần lazy loading, caching, entity lifecycle
- Team quen ORM patterns
- Domain model phức tạp với relationships

---

## Trade-offs

| Ưu | Nhược |
|----|-------|
| Full SQL control | Boilerplate code (không có JdbcTemplate) |
| Hiệu suất cao (no ORM overhead) | Thủ công map ResultSet → Object |
| Dễ debug (SQL rõ ràng) | Không có lazy loading / caching |
| Tương thích mọi DB feature | Không có entity lifecycle management |
| Không magic | Phải viết migration scripts |

---

## Real-world Usage (Production)

### 1. Multi-tenant với Schema-per-tenant

```java
@Configuration
public class MultiTenantDataSource extends AbstractRoutingDataSource {

    private static final ThreadLocal<String> CURRENT_TENANT = new ThreadLocal<>();

    public static void setTenant(String tenant) { CURRENT_TENANT.set(tenant); }
    public static String getTenant() { return CURRENT_TENANT.get(); }

    @Override
    protected Object determineCurrentLookupKey() {
        return CURRENT_TENANT.get(); // routing key
    }
}

// Interceptor set tenant từ request header/JWT
@Component
public class TenantInterceptor implements HandlerInterceptor {
    @Override
    public boolean preHandle(HttpServletRequest req, ...) {
        String tenant = req.getHeader("X-Tenant-ID");
        MultiTenantDataSource.setTenant(tenant);
        return true;
    }

    @Override
    public void afterCompletion(...) {
        MultiTenantDataSource.setTenant(null); // cleanup
    }
}
```

### 2. Read/Write Splitting

```java
@Configuration
public class DataSourceConfig {
    @Bean @Primary
    @ConfigurationProperties("spring.datasource.write")
    public DataSource writeDataSource() { return DataSourceBuilder.create().build(); }

    @Bean
    @ConfigurationProperties("spring.datasource.read")
    public DataSource readDataSource() { return DataSourceBuilder.create().build(); }

    @Bean
    public DataSource routingDataSource(
            @Qualifier("writeDataSource") DataSource write,
            @Qualifier("readDataSource") DataSource read) {
        ReadWriteRoutingDataSource routing = new ReadWriteRoutingDataSource();
        routing.setDefaultTargetDataSource(write);
        routing.setTargetDataSources(Map.of("read", read, "write", write));
        routing.afterPropertiesSet();
        return routing;
    }
}

// Routing dựa trên @Transactional(readOnly=true)
public class ReadWriteRoutingDataSource extends AbstractRoutingDataSource {
    @Override
    protected Object determineCurrentLookupKey() {
        return TransactionSynchronizationManager.isCurrentTransactionReadOnly()
            ? "read" : "write";
    }
}
```

### 3. Monitoring HikariCP với Actuator

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,metrics
  metrics:
    tags:
      application: myapp

# Metrics available:
# hikaricp.connections.active
# hikaricp.connections.idle
# hikaricp.connections.pending (waiting for connection)
# hikaricp.connections.timeout (connection timeout count)
```

```java
@Component
@Slf4j
public class ConnectionPoolMonitor {
    private final HikariDataSource dataSource;

    @Scheduled(fixedDelay = 60000)
    public void logPoolStats() {
        HikariPoolMXBean pool = dataSource.getHikariPoolMXBean();
        log.info("Pool stats - active: {}, idle: {}, waiting: {}, total: {}",
            pool.getActiveConnections(),
            pool.getIdleConnections(),
            pool.getThreadsAwaitingConnection(),
            pool.getTotalConnections());

        if (pool.getThreadsAwaitingConnection() > 0) {
            log.warn("Connection pool pressure detected!");
        }
    }
}
```

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: **JPA & Hibernate**
>
> Keyword: Entity lifecycle (Transient→Persistent→Detached→Removed), EntityManager methods (persist/merge/remove/find/detach), persistence context = first-level cache, flush modes, JPQL vs Criteria API vs native SQL, N+1 problem (LazyInitializationException, JOIN FETCH, @BatchSize, @EntityGraph), lazy vs eager loading, @OneToMany/@ManyToMany mappings (owning side/mappedBy, CascadeType, orphanRemoval), Optimistic locking (@Version), Pessimistic locking (LockModeType)
