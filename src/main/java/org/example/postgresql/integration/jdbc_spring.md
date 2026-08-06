# PostgreSQL từ Java và Spring

> Mục tiêu: kết nối Java/Spring với PostgreSQL 18 theo cách đúng về transaction,
> connection budget, type mapping, hiệu năng và khả năng phục hồi. Bài này giả định
> người đọc đã biết JDBC/JPA cơ bản; trọng tâm là những hành vi riêng của PostgreSQL
> và các lỗi chỉ xuất hiện khi lên production.

---

## 1. Một request đi qua nhiều lớp hơn ta tưởng

```text
HTTP request / message
        │
        ▼
Spring service + @Transactional proxy
        │
        ├── JdbcTemplate / Spring Data / EntityManager
        ▼
HikariCP: mượn một JDBC Connection
        │
        ├── tùy chọn: PgBouncer
        ▼
pgJDBC: PostgreSQL wire protocol + TLS + type conversion
        │
        ▼
PostgreSQL backend process → transaction → SQL plan → storage/WAL
```

Mỗi lớp có lifecycle và timeout riêng. Khi request báo “database chậm”, nguyên nhân có
thể là chờ connection trong Hikari, chờ server connection trong PgBouncer, chờ lock,
query chạy lâu, socket đứt hoặc transaction đã commit nhưng response mất trên mạng.

**Mental model:** `DataSource` không phải database, pool không phải transaction, JPA
không thay SQL và retry connection không đồng nghĩa retry business operation.

---

## 2. Chọn abstraction theo workload

| Abstraction | Hợp với | Trade-off |
|---|---|---|
| JDBC/`JdbcTemplate`/`JdbcClient` | SQL giàu tính PostgreSQL, report, batch, kiểm soát plan | Tự map row và quản lý SQL |
| Spring Data JDBC | Aggregate đơn giản, ít magic hơn ORM | Ít identity map/lazy loading hơn JPA |
| JPA/Hibernate | Domain graph, unit of work, dirty checking | Dễ N+1, flush bất ngờ, SQL/lock bị che |
| jOOQ hoặc SQL DSL | Query type-safe, schema-first | Code generation/tooling và dependency riêng |
| `CopyManager` | Import/export khối lượng lớn | API riêng pgJDBC, validation/error handling khác DML |

Một service có thể dùng JPA cho aggregate transaction và `JdbcTemplate` cho report/bulk
operation. Điều kiện là chúng dùng đúng `DataSource`/transaction manager để cùng tham gia
transaction khi business contract yêu cầu.

Không dùng ORM chỉ để tránh học SQL. Index, isolation, lock, row count và plan vẫn do
PostgreSQL quyết định.

---

## 3. Dependency và version ownership

Với Spring Boot, ưu tiên để BOM của Boot quản lý phiên bản tương thích:

```kotlin
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-jdbc")
    // Hoặc starter-data-jpa nếu dùng JPA/Hibernate.
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    runtimeOnly("org.postgresql:postgresql")
}
```

Không cần `Class.forName("org.postgresql.Driver")`; pgJDBC dùng Java Service Provider.

Production cần inventory độc lập cho:

- JDK;
- Spring Boot/Spring Framework;
- pgJDBC;
- Hibernate nếu có;
- PgBouncer/proxy;
- PostgreSQL server major/minor.

“Server còn hỗ trợ client cũ” không có nghĩa client cũ còn được vá CVE. Upgrade driver
phải test authentication/TLS, type mapping, prepared statement, failover và pooler mode.

---

## 4. JDBC URL production: xác minh server, không nhúng secret

Ví dụ một primary endpoint:

```yaml
spring:
  datasource:
    url: "jdbc:postgresql://pg-primary.internal:5432/orders?sslmode=verify-full&sslrootcert=/run/secrets/postgres-ca.pem&ApplicationName=orders-api"
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}
```

`sslmode=verify-full` xác minh certificate chain và hostname. `sslmode=require` chủ yếu
yêu cầu encryption và không diễn đạt rõ endpoint verification. Secret nên được inject từ
secret manager/file/identity provider; không đặt password trong URL, Git, image hoặc log.

Nếu dùng client certificate, bảo vệ key file và drill rotation. Với proxy, kiểm tra hai
hop độc lập: application → proxy và proxy → PostgreSQL.

Đặt `ApplicationName` ổn định theo service/deployment để `pg_stat_activity` phân biệt
workload. Không nhét user ID, token hoặc trace ID có cardinality cao vào đó.

---

## 5. Multi-host URL giúp chọn host, không tiếp tục transaction bị đứt

```text
jdbc:postgresql://pg-a:5432,pg-b:5432/orders
  ?targetServerType=primary
  &hostRecheckSeconds=10
  &sslmode=verify-full
```

pgJDBC có thể thử nhiều host và chọn server đúng `targetServerType`. Tuy nhiên:

- driver không promote standby và không fence primary cũ;
- connection đang dùng không tự “nhảy” sang host khác;
- transaction đứt giữa chừng phải bỏ connection và chạy lại toàn transaction nếu an toàn;
- mất response lúc `COMMIT` tạo kết quả mơ hồ: có thể database đã commit;
- DNS/service discovery/proxy timeout vẫn phải khớp request deadline.

HA control plane vẫn cần quyết định primary duy nhất. Multi-host URL chỉ là một phần của
client reconnect path.

---

## 6. Timeout là một chuỗi ngân sách

| Timeout | Chặn điều gì? | Khi hết hạn |
|---|---|---|
| Hikari `connectionTimeout` | Chờ mượn connection từ app pool | SQLException tại application |
| pgJDBC `connectTimeout` | Mở TCP/TLS/auth tới server | connection attempt fail |
| pgJDBC `socketTimeout` | Không nhận dữ liệu trên socket quá lâu | đóng/đánh hỏng connection |
| JDBC query timeout | Statement chạy quá lâu | gửi cancel, nhận SQLSTATE cancel |
| PostgreSQL `statement_timeout` | Statement phía server quá lâu | server hủy statement |
| PostgreSQL `lock_timeout` | Chờ lock quá lâu | chỉ hủy statement đang chờ lock |
| Spring transaction timeout | Transaction theo policy Spring | phụ thuộc transaction manager/statement |
| HTTP/message deadline | Toàn operation | caller có thể bỏ request |

Thiết kế từ ngoài vào trong:

```text
request deadline
  > transaction budget
      > statement/lock/acquire budget
```

Nếu HTTP timeout 3 giây nhưng pool chờ 30 giây, caller đã bỏ đi còn server vẫn giữ thread.
Ngược lại, `socketTimeout` quá ngắn có thể giết query hợp lệ hoặc COPY lớn. Mọi con số phải
được đo theo SLO, không sao chép nguyên từ ví dụ.

---

## 7. HikariCP là admission control, không phải máy tạo throughput

Một connection PostgreSQL tương ứng một backend process và có thể giữ memory, lock,
snapshot. Tăng pool làm nhiều work vào database cùng lúc; nếu database đã bão hòa, điều
này thường tăng queue trong DB và tail latency.

```text
request threads ──wait──► Hikari permits ──► PostgreSQL concurrency
                              ▲
                              └─ maximumPoolSize là giới hạn admission
```

Pool đủ lớn để giữ database bận, nhưng đủ nhỏ để overload xuất hiện dưới dạng queue có
giới hạn ở application thay vì hàng trăm backend cùng tranh CPU/I/O/lock.

Không có công thức phổ quát kiểu “CPU × 2” áp dụng cho mọi workload. Query CPU-bound,
I/O-bound, lock-bound, transaction duration và số service cùng dùng cluster đều khác.

---

## 8. Connection budget phải tính toàn fleet

```text
Σ(application replicas × pool max mỗi replica)
+ batch workers
+ migration/backup/monitoring connections
+ PgBouncer server pools theo database/user
+ admin và failover headroom
< PostgreSQL usable connection budget
```

Ví dụ 20 pod × pool 20 không phải “pool 20”; đó là tối đa 400 client connection cho riêng
một service. Autoscaling pod cũng autoscale tổng connection.

Đo:

- active/idle/pending connection mỗi pool;
- thời gian giữ connection và transaction duration;
- throughput/tail latency khi tăng concurrency;
- `pg_stat_activity`, wait event, CPU, I/O và lock;
- connection của các workload khác cùng cluster.

Dùng load test để tìm **knee point**: sau mốc nào concurrency tăng nhưng throughput không
tăng, còn latency/error tăng mạnh. Chọn budget trước mốc đó và giữ headroom.

---

## 9. Baseline HikariCP có chủ đích

```yaml
spring:
  datasource:
    hikari:
      pool-name: orders-primary
      maximum-pool-size: 12       # Ví dụ khởi đầu, phải load test toàn fleet.
      connection-timeout: 2000    # Chờ pool tối đa 2 giây.
      validation-timeout: 1000
      max-lifetime: 1740000       # 29 phút nếu hạ tầng cắt ở 30 phút.
      keepalive-time: 120000
      data-source-properties:
        tcpKeepAlive: true
        reWriteBatchedInserts: true
```

Các quan hệ quan trọng:

- `validationTimeout < connectionTimeout`;
- `keepaliveTime < maxLifetime` và keepalive chỉ ping idle connection;
- `maxLifetime` ngắn hơn giới hạn database/network vài giây, không bằng đúng giới hạn;
- in-use connection không bị Hikari cưỡng bức retire giữa transaction chỉ vì hết lifetime;
- nếu không đặt `minimumIdle`, Hikari mặc định bằng `maximumPoolSize`, tạo fixed-size pool;
- `idleTimeout` chỉ có tác dụng khi `minimumIdle < maximumPoolSize`.

pgJDBC hỗ trợ JDBC4 `Connection.isValid()`, vì vậy thường không cần
`connection-test-query: SELECT 1`.

---

## 10. `maxLifetime`, keepalive và TCP keepalive giải quyết khác nhau

- `maxLifetime`: chủ động thay connection cũ trước khi hạ tầng cắt nó.
- Hikari `keepaliveTime`: mượn một **idle** connection ra ping định kỳ.
- pgJDBC `tcpKeepAlive=true`: bật TCP keepalive; chu kỳ chi tiết thường do OS quyết định.
- query/validation: kiểm tra PostgreSQL phản hồi ở application protocol.

Keepalive không làm một transaction bị treo trở nên an toàn và không thay query timeout.
Đặt keepalive quá dày trên hàng nghìn connection tạo noise. Đồng hồ hệ thống cũng phải
đồng bộ vì Hikari dựa vào timer chính xác.

`leakDetectionThreshold` là công cụ chẩn đoán connection bị giữ lâu, không chứng minh
leak: một query hợp lệ dài hơn threshold cũng bị báo. Bật tạm với ngưỡng lớn hơn transaction
bình thường và so cả log “leaked”/“unleaked”.

---

## 11. Session state là món nợ khi trả connection về pool

Một physical connection có thể giữ:

- transaction chưa commit/rollback;
- `search_path`, timezone, role, custom GUC;
- temporary table;
- advisory lock cấp session;
- LISTEN registration;
- prepared statement và plan cache.

Spring/Hikari reset các thuộc tính JDBC chuẩn nhất định khi connection được trả về, nhưng
không thể hiểu mọi câu `SET` hoặc object PostgreSQL mà application tạo.

Nguyên tắc:

- dùng `SET LOCAL`/`set_config(..., true)` trong transaction;
- đóng `ResultSet`, `Statement`, stream và trả connection trong `finally`/try-with-resources;
- không đổi role/search path session-wide cho một request;
- không dựa vào `connectionInitSql` cho tenant context: nó chạy khi physical connection
  được tạo, không phải mỗi lần checkout;
- test tái sử dụng cùng connection qua request A → B và exception path.

---

## 12. Connection, Statement và ResultSet không phải object dùng chung giữa thread

Mỗi request mượn connection, làm việc rồi `close()` để trả về pool. Không cache
`Connection`/`PreparedStatement` trong singleton và không chuyển chúng sang `@Async`.

```java
try (Connection connection = dataSource.getConnection();
     PreparedStatement statement = connection.prepareStatement(SQL)) {
    statement.setObject(1, orderId);
    try (ResultSet result = statement.executeQuery()) {
        // đọc kết quả trong scope này
    }
}
```

Trong code Spring transaction, ưu tiên `JdbcTemplate` hoặc `DataSourceUtils` để lấy
transaction-bound connection. Gọi `dataSource.getConnection()` rồi tự commit trong method
`@Transactional` có thể tạo transaction khác ngoài ý muốn tùy DataSource/proxy.

---

## 13. `JdbcTemplate` và `JdbcClient` giữ SQL rõ mà bỏ boilerplate

`JdbcTemplate` quản lý resource, tham gia Spring transaction và dịch `SQLException` sang
`DataAccessException`. Application vẫn sở hữu SQL và row mapping.

```java
record OrderView(UUID id, UUID tenantId, BigDecimal total, Instant createdAt) {}

private static final RowMapper<OrderView> ORDER_MAPPER = (rs, rowNum) ->
    new OrderView(
        rs.getObject("order_id", UUID.class),
        rs.getObject("tenant_id", UUID.class),
        rs.getBigDecimal("total"),
        rs.getObject("created_at", OffsetDateTime.class).toInstant()
    );

Optional<OrderView> findById(UUID tenantId, UUID orderId) {
    return jdbc.query("""
            SELECT order_id, tenant_id, total, created_at
            FROM orders.purchase_order
            WHERE tenant_id = ? AND order_id = ?
            """, ORDER_MAPPER, tenantId, orderId)
        .stream()
        .findFirst();
}
```

Không dùng `queryForObject` nếu “không có row” là kết quả bình thường mà không muốn xử lý
exception. Luôn ghi tên cột thay vì `SELECT *` để contract và cached plan ổn định hơn.

---

## 14. `INSERT ... RETURNING` là đường đi tự nhiên của PostgreSQL

```java
OrderView insert(NewOrder command) {
    return jdbc.queryForObject("""
        INSERT INTO orders.purchase_order
            (tenant_id, order_id, total, created_at)
        VALUES (?, ?, ?, clock_timestamp())
        RETURNING order_id, tenant_id, total, created_at
        """, ORDER_MAPPER,
        command.tenantId(), command.orderId(), command.total());
}
```

`RETURNING` lấy default/generated value trong cùng statement, rõ hơn việc đoán sequence
hoặc query lại. Nó cũng dùng được với UPDATE/DELETE/MERGE.

Nếu business cần idempotency, đặt unique key như `(tenant_id, idempotency_key)` và dùng
`ON CONFLICT` có semantics rõ. Không coi duplicate request là lỗi network có thể retry mù.

---

## 15. Parameter binding ngăn injection cho **giá trị**, không cho identifier

Đúng:

```java
jdbc.query("SELECT order_id FROM orders.purchase_order WHERE status = ?",
           mapper, requestedStatus);
```

Sai:

```java
String sql = "SELECT * FROM orders.purchase_order ORDER BY " + request.sortField();
```

Placeholder không đại diện cho table, column, keyword hoặc sort direction. Dynamic
identifier phải map qua allowlist:

```java
String orderBy = switch (sortField) {
    case "createdAt" -> "created_at";
    case "total" -> "total";
    default -> throw new IllegalArgumentException("Unsupported sort field");
};
String direction = descending ? "DESC" : "ASC";
```

Sau đó ghép **chỉ** token do server chọn, không ghép raw input. Với danh sách giá trị,
dùng `NamedParameterJdbcTemplate`, array parameter hoặc temporary/staging strategy thay
vì tự nối dấu phẩy.

---

## 16. JDBC `PreparedStatement` và server-prepared statement là hai khái niệm

`PreparedStatement` luôn tách SQL structure khỏi parameter, nên cần dùng để chống injection.
pgJDBC ban đầu có thể dùng extended protocol với unnamed statement; sau khi cùng statement
đạt `prepareThreshold` mặc định, driver chuyển sang named server-prepared statement.

Lợi ích server prepare:

- giảm parse/metadata trên lần dùng lại;
- có thể tái sử dụng plan;
- cho phép binary transfer với một số type.

Trade-off:

- cache theo **mỗi physical connection**;
- giữ memory phía client/server;
- generic plan có thể kém khi parameter distribution lệch;
- DDL đổi result type có thể gây `cached plan must not change result type`;
- pooler phải hỗ trợ protocol-level prepared statement đúng cách.

`prepareThreshold=0` tắt server prepare nhưng **không** biến parameter thành string nối và
không mất lợi ích chống injection của JDBC `PreparedStatement`.

---

## 17. Đừng tune prepare cache trước khi đo

Các knob pgJDBC gồm:

- `prepareThreshold`;
- `preparedStatementCacheQueries`;
- `preparedStatementCacheSizeMiB`;
- `preferQueryMode`;
- binary-transfer allow/deny list.

Defaults thường là điểm bắt đầu tốt. Cache 256 query trên 100 connection không phải 256
entry toàn service mà có thể tới 25.600 entry client-side, chưa tính server object.

Khi plan thay đổi theo parameter skew, kiểm tra `EXPLAIN`, `pg_stat_statements` và generic
vs custom plan trước khi tắt prepare toàn hệ thống. Dynamic SQL tạo text khác nhau liên tục
sẽ phá locality của cache.

Tránh `SELECT *`; schema migration đổi column list/type là corner case điển hình của cached
plan. Rolling deploy phải test old code + new schema và new code + compatible schema.

---

## 18. Streaming ResultSet cần transaction và tiêu thụ tuần tự

Mặc định fetch size `0` có thể buffer toàn kết quả phía client. Để pgJDBC dùng cursor fetch:

- autocommit phải tắt, thường bằng Spring transaction;
- `ResultSet` forward-only;
- query là một statement;
- `fetchSize > 0`;
- consumer không gom lại toàn bộ vào một `List`.

```java
@Transactional(readOnly = true)
public void exportOrders(Consumer<OrderView> consumer) {
    jdbc.query(connection -> {
        PreparedStatement ps = connection.prepareStatement("""
            SELECT order_id, tenant_id, total, created_at
            FROM orders.purchase_order
            ORDER BY tenant_id, order_id
            "", ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY);
        ps.setFetchSize(500);
        return ps;
    }, rs -> consumer.accept(ORDER_MAPPER.mapRow(rs, rs.getRow())));
}
```

Cursor giữ transaction/snapshot và connection suốt thời gian stream. Nếu consumer ghi file
hoặc gọi network chậm, transaction cũng dài. Với export rất lớn, chia theo keyset/checkpoint,
dùng COPY TO hoặc job riêng có timeout và resource budget.

---

## 19. Pagination: keyset tốt hơn OFFSET sâu

```sql
SELECT order_id, created_at, total
FROM orders.purchase_order
WHERE tenant_id = ?
  AND (created_at, order_id) < (?, ?)
ORDER BY created_at DESC, order_id DESC
LIMIT ?;
```

Cursor API phải mang cả `created_at` và unique tie-breaker `order_id`. Bind đúng type;
không encode cursor bằng chuỗi có thể bị sửa mà không ký/xác thực.

`OFFSET 100000` buộc database bỏ qua nhiều row và kết quả dễ dịch chuyển khi concurrent
insert/delete. JPA `Page` còn có thể chạy thêm `COUNT(*)`; dùng `Slice` nếu không cần tổng.

---

## 20. JDBC batch giảm round trip, không tự định nghĩa transaction boundary

```java
int[][] counts = jdbc.batchUpdate("""
        INSERT INTO orders.order_line
            (tenant_id, order_id, line_no, sku, quantity)
        VALUES (?, ?, ?, ?, ?)
        """,
    lines,
    500,
    (ps, line) -> {
        ps.setObject(1, line.tenantId());
        ps.setObject(2, line.orderId());
        ps.setInt(3, line.lineNo());
        ps.setString(4, line.sku());
        ps.setInt(5, line.quantity());
    });
```

`reWriteBatchedInserts=true` có thể rewrite batch INSERT tương thích để giảm protocol work.
Benchmark với constraint, trigger, WAL và replica thật.

Chọn batch size theo:

- packet/memory và parameter count;
- transaction/WAL/lock duration;
- failure granularity;
- idempotency/checkpoint.

Đừng `commit()` mỗi 500 row bên trong một business operation vốn cần atomicity. Nếu import
được phép commit theo chunk, checkpoint và duplicate handling phải là contract rõ ràng.

---

## 21. COPY cho bulk path, không thay request CRUD

```java
@Transactional
public long copyToStaging(Reader csv) throws SQLException, IOException {
    Connection connection = DataSourceUtils.getConnection(dataSource);
    try {
        PGConnection pg = connection.unwrap(PGConnection.class);
        return pg.getCopyAPI().copyIn("""
            COPY staging.order_import
                (tenant_id, order_id, total, created_at)
            FROM STDIN WITH (FORMAT csv, HEADER true)
            """, csv);
    } finally {
        DataSourceUtils.releaseConnection(connection, dataSource);
    }
}
```

`COPY ... STDIN` truyền dữ liệu từ application; khác `COPY FROM '/server/file'` đọc file
trên host database và cần capability nguy hiểm hơn.

Production pattern:

1. COPY vào staging table.
2. Validate type/domain/duplicate và ghi reject có giới hạn.
3. Merge set-based vào target trong transaction/chunk contract.
4. Reconcile row count/checksum.
5. Cleanup staging và theo dõi `pg_stat_progress_copy`.

PostgreSQL 18 chưa hỗ trợ `COPY FROM` trực tiếp vào table có RLS; dùng INSERT tương đương
hoặc staging + trusted merge có tenant validation. `ON_ERROR=ignore` phải đi cùng
`REJECT_LIMIT`/reconciliation, nếu không “job xanh” có thể âm thầm mất phần lớn dữ liệu.

---

## 22. Type mapping nền tảng

| PostgreSQL | JDBC/Java phù hợp | Lưu ý |
|---|---|---|
| `smallint`/`integer`/`bigint` | `short`/`int`/`long` hoặc wrapper | primitive không biểu diễn NULL |
| `numeric` | `BigDecimal` | đặt precision/scale và rounding rule |
| `boolean` | `boolean`/`Boolean` | dùng wrapper nếu nullable |
| `text`/`varchar` | `String` | length business nên là constraint rõ |
| `uuid` | `UUID` | dùng `setObject/getObject(UUID.class)` |
| `date` | `LocalDate` | không gắn timezone |
| `time` | `LocalTime` | thường thiếu business zone/context |
| `timestamp` | `LocalDateTime` | wall-clock không có zone/instant |
| `timestamptz` | `OffsetDateTime` trong pgJDBC | backend lưu instant, không giữ zone gốc |
| `bytea` | `byte[]`/stream | tránh load blob lớn vào heap |
| `jsonb` | `PGobject`, String hoặc ORM JSON mapping | vẫn validate schema/domain |
| array | `java.sql.Array`/driver support | query/index/operator phải thiết kế riêng |

Luôn test NULL, infinity, DST, precision, empty array/JSON và unknown enum value. Type mapping
đúng happy path chưa đủ cho schema evolution.

---

## 23. Thời gian: `timestamptz` là instant, không phải timezone của người dùng

pgJDBC JDBC 4.2 map:

```text
date                    ↔ LocalDate
time                    ↔ LocalTime
timestamp               ↔ LocalDateTime
timestamp with time zone↔ OffsetDateTime
```

```java
OffsetDateTime stored = rs.getObject("occurred_at", OffsetDateTime.class);
Instant instant = stored.toInstant();

ps.setObject(1, OffsetDateTime.ofInstant(command.occurredAt(), ZoneOffset.UTC));
```

pgJDBC không trực tiếp hỗ trợ mọi `Instant`/`ZonedDateTime` qua `getObject` như bảng JDBC
4.2 trên. ORM có thể hỗ trợ thêm, nhưng phải integration test đúng version.

PostgreSQL `timestamptz` chuẩn hóa instant và không lưu zone ID như `Asia/Bangkok`. Nếu
business cần “09:00 theo Europe/Paris”, lưu thêm zone ID và rule riêng. Không dùng
`LocalDateTime` cho event xuyên múi giờ; DST có giờ lặp hoặc không tồn tại.

---

## 24. UUID, money và floating point

```java
ps.setObject(1, orderId);
UUID id = rs.getObject("order_id", UUID.class);

ps.setBigDecimal(2, amount.setScale(2, RoundingMode.UNNECESSARY));
```

- UUID có support native; không đổi sang text rồi cast mọi query.
- Tiền dùng `numeric` + `BigDecimal`, không dùng `double`.
- Xác định scale và rounding ở domain boundary; database constraint bảo vệ range/scale.
- `BigDecimal.equals()` xét cả scale, còn `compareTo()` so giá trị số; test domain rõ.
- Sequence/identity gap là bình thường sau rollback/cache/crash, không dùng ID để suy ra count.

---

## 25. JSONB: bind đúng type và giữ invariant quan trọng ở cột thật

JDBC thuần:

```java
PGobject json = new PGobject();
json.setType("jsonb");
json.setValue(objectMapper.writeValueAsString(metadata));
ps.setObject(1, json);
```

Hibernate hiện đại có JSON mapping riêng, ví dụ `@JdbcTypeCode(SqlTypes.JSON)`, nhưng
annotation/behavior phụ thuộc Hibernate version và JSON library. Test schema migration,
dirty checking, null và equality trước khi dùng entity mutable.

Các field dùng để join, unique, foreign key, tenant boundary, status transition hoặc range
query ổn định nên là typed column. JSONB phù hợp metadata linh hoạt, không phải lý do bỏ
schema. GIN index chỉ hữu ích khi operator/query shape khớp.

Không log nguyên JSON request nếu nó có PII/token; parameterized query ngăn injection nhưng
không tự ngăn data leak qua log.

---

## 26. Array, enum, range và custom type

```java
Array tags = connection.createArrayOf("text", new String[] {"priority", "gift"});
try {
    ps.setArray(1, tags);
    ps.executeUpdate();
} finally {
    tags.free();
}
```

Guideline:

- array hợp danh sách nhỏ cùng row; quan hệ cần FK/query phức tạp thường nên thành child table;
- `@Enumerated(EnumType.STRING)` thường map text/varchar, không tự map native PostgreSQL enum;
- native enum cần driver/ORM mapping và rollout value mới theo thứ tự compatible;
- không dùng ordinal vì thêm/reorder Java enum sẽ đổi nghĩa dữ liệu;
- range/multirange thường cần `PGobject`, custom JDBC type hoặc library; test bound inclusive,
  exclusive, empty và infinity;
- custom type làm coupling với driver/ORM mạnh hơn, nên có contract test.

---

## 27. Binary data: `bytea`, Large Object hay object storage?

| Lựa chọn | Hợp với | Rủi ro |
|---|---|---|
| `bytea` | object vừa/nhỏ, atomic cùng row | heap/network/WAL nếu đọc toàn bộ |
| PostgreSQL Large Object | stream object lớn cần DB lifecycle | transaction/ACL/cleanup orphan phức tạp |
| Object storage + metadata DB | file lớn, CDN, lifecycle riêng | consistency hai hệ thống, cần outbox/compensation |

Đừng gọi `rs.getBytes()` cho payload hàng trăm MB rồi ngạc nhiên vì OOM. Dùng stream và
giới hạn kích thước từ ingress. Nếu lưu ngoài DB, ghi trạng thái upload/finalization bằng
workflow idempotent; transaction PostgreSQL không bao trùm object storage.

---

## 28. Spring transaction là proxy bao quanh method

```text
caller → Spring proxy
           ├─ acquire/bind connection
           ├─ BEGIN
           ├─ gọi service method
           ├─ COMMIT hoặc ROLLBACK
           └─ release connection
```

```java
@Service
public class OrderApplicationService {
    @Transactional
    public OrderId place(PlaceOrder command) {
        // Mọi repository dùng cùng transaction manager/DataSource sẽ tham gia tx.
        return createAndReserve(command);
    }
}
```

Transaction imperative thường gắn với thread qua `PlatformTransactionManager`; nó không
tự đi sang thread mới, `@Async`, executor hoặc remote service. Reactive transaction dùng
Reactor context và `ReactiveTransactionManager`, không dùng mental model ThreadLocal này.

---

## 29. Self-invocation bỏ qua proxy

```java
@Service
class ImportService {
    public void importAll() {
        importChunk(); // this.importChunk(): không đi qua proxy
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void importChunk() { /* ... */ }
}
```

`REQUIRES_NEW` phía trên không có hiệu lực khi gọi nội bộ. Sửa bằng cách:

- tách transaction boundary sang bean khác;
- dùng `TransactionTemplate` cho boundary lập trình;
- chỉ dùng AspectJ weaving khi đội ngũ thật sự chấp nhận complexity.

Đặt `@Transactional` ở concrete service method rõ ràng. Private method, constructor,
`@PostConstruct` hoặc object tự `new` không phải Spring bean proxy đáng tin cậy.

---

## 30. Rollback rule và transaction đã “poisoned”

Mặc định Spring rollback với `RuntimeException` và `Error`, không tự rollback mọi checked
exception. Nếu checked business exception phải rollback:

```java
@Transactional(rollbackFor = FulfillmentException.class)
public void fulfill(OrderId id) throws FulfillmentException { /* ... */ }
```

Sau một SQL error, PostgreSQL transaction thường ở trạng thái aborted cho tới rollback
hoặc rollback savepoint. Catch exception rồi tiếp tục query trong cùng transaction không
“chữa” được nó.

Nếu inner REQUIRED method đánh dấu rollback-only nhưng outer nuốt exception và cố commit,
caller có thể nhận `UnexpectedRollbackException`. Đừng catch `DataAccessException` chỉ để
log rồi trả success.

Constraint/deadlock/serialization error có thể xuất hiện lúc flush hoặc commit, không nhất
thiết ngay tại `repository.save()`.

---

## 31. Propagation đổi cả connection demand

| Propagation | Physical behavior khái quát | Rủi ro |
|---|---|---|
| `REQUIRED` | join transaction hiện có hoặc tạo mới | inner rollback-only ảnh hưởng outer |
| `REQUIRES_NEW` | suspend outer, lấy transaction/connection khác | pool exhaustion/deadlock khi concurrency cao |
| `NESTED` | một transaction với JDBC savepoint | support phụ thuộc transaction manager |
| `SUPPORTS` | có tx thì join, không thì chạy ngoài tx | behavior thay theo caller |

Nếu N thread đều giữ outer connection rồi cùng chờ một `REQUIRES_NEW` connection, pool bằng
N có thể deadlock ở tầng ứng dụng. Budget phải tính số connection đồng thời trên **mỗi call
stack**, không chỉ thread count.

`NESTED` phù hợp `DataSourceTransactionManager` savepoint; đừng giả định JPA transaction
manager/native JPA hỗ trợ mọi trường hợp giống nhau. Audit/outbox quan trọng thường cần
thiết kế business rõ hơn việc rải `REQUIRES_NEW`.

---

## 32. Isolation của PostgreSQL khác bảng ANSI đơn giản

| Spring/JDBC request | PostgreSQL thực tế |
|---|---|
| `READ_UNCOMMITTED` | được xử lý như `READ_COMMITTED` |
| `READ_COMMITTED` | snapshot mới cho mỗi statement |
| `REPEATABLE_READ` | snapshot transaction, PostgreSQL ngăn phantom theo nghĩa thông thường; có thể abort concurrent update |
| `SERIALIZABLE` | SSI phát hiện dependency nguy hiểm; có thể abort `40001` |

Isolation cao không nghĩa “không bao giờ lỗi”; nó chuyển anomaly thành transaction abort,
application phải retry toàn transaction.

```java
@Transactional(isolation = Isolation.SERIALIZABLE)
public void allocateCredit(CustomerId id, Money amount) { /* ... */ }
```

Chọn isolation từ invariant và conflict pattern. Atomic UPDATE, unique/exclusion constraint,
row lock hoặc coordination row thường đơn giản hơn việc nâng mọi request lên Serializable.

---

## 33. `readOnly=true` không tự route replica

Spring ghi rõ read-only là **hint** cho transaction subsystem. Với pgJDBC mặc định
`readOnlyMode=transaction`, khi autocommit false và connection read-only, driver có thể mở
`BEGIN READ ONLY`. Điều này giúp database từ chối một số write, nhưng:

- không tự chọn replica;
- không bảo đảm ORM không dirty-check theo mọi version/config;
- không làm query miễn lock/I/O/CPU;
- không giải quyết replica staleness.

```java
@Transactional(readOnly = true)
public OrderView get(OrderId id) { /* vẫn có thể chạy trên primary */ }
```

Replica routing cần DataSource/router riêng, topology health và consistency contract.
Đừng viết tài liệu rằng `readOnly=true` “skip row lock” hoặc “tự route read traffic”.

---

## 34. Transaction ngắn, không ôm remote I/O

Sai:

```java
@Transactional
public void checkout(Command command) {
    reserveRows(command);          // giữ connection/lock
    paymentClient.charge(command); // network có thể treo
    markPaid(command);
}
```

Một local ACID transaction không thể rollback side effect đã gửi tới payment service.
Thường dùng:

- state machine + idempotency key;
- transactional outbox;
- orchestration/saga và compensation;
- transaction ngắn quanh mỗi state transition;
- timeout/deadline cho remote call.

Không tách I/O ra ngoài một cách máy móc nếu sẽ tạo invariant gap; thiết kế workflow rõ
thay vì giả vờ HTTP call nằm trong PostgreSQL transaction.

---

## 35. Retry phải bao ngoài một transaction mới

Retryable phổ biến:

- `40001`: serialization failure;
- `40P01`: deadlock detected;
- đôi khi `55P03`: lock not available, nếu operation contract cho phép.

Không retry mù:

- `23505`: unique violation thường là domain conflict/idempotency outcome;
- `57014`: canceled do timeout/caller, retry ngay dễ lặp overload;
- validation/permission/syntax error;
- optimistic conflict mà không reload/recompute.

Mẫu rõ với `TransactionTemplate`:

```java
public Receipt executeWithRetry(Command command) {
    for (int attempt = 1; attempt <= 3; attempt++) {
        try {
            return transactionTemplate.execute(status -> executeOnce(command));
        } catch (DataAccessException failure) {
            String sqlState = findSqlState(failure);
            boolean retryable = "40001".equals(sqlState) || "40P01".equals(sqlState);
            if (!retryable || attempt == 3) throw failure;
            sleepWithExponentialJitter(attempt); // transaction đã kết thúc trước khi ngủ
        }
    }
    throw new IllegalStateException("unreachable");
}
```

Retry loop phải ở ngoài `@Transactional` boundary; nếu cùng transaction đã aborted thì
chạy lại statement không có ý nghĩa. Giới hạn attempt và tổng deadline, thêm jitter, metric
theo SQLSTATE và không ngủ khi còn giữ connection.

---

## 36. Connection loss lúc commit tạo “unknown outcome”

Nếu client gửi COMMIT rồi socket đứt trước response, hai khả năng đều tồn tại:

```text
COMMIT chưa tới server  → transaction rollback khi connection mất
COMMIT đã durable       → transaction thành công nhưng client không biết
```

Retry INSERT bằng ID mới có thể tạo duplicate. Thiết kế:

- idempotency key unique theo tenant/operation;
- client-generated stable operation ID;
- response có thể được truy vấn lại theo operation ID;
- outbox event unique/deduplicated;
- reconciliation cho payment/external side effect.

SQLSTATE class `08` báo connection exception nhưng không chứng minh transaction chưa commit.
Đây là bài toán protocol/business, không thể sửa chỉ bằng `@Retryable`.

---

## 37. JPA persistence context là unit of work, không phải ảnh realtime

Trong một `EntityManager`, entity đã load được cache cấp một. Query khác hoặc database update
từ session khác không tự làm object managed hiện tại mới lại.

Hibernate có thể flush:

- trước commit;
- trước query cần nhìn pending change;
- khi gọi `flush()`;
- theo flush mode/provider behavior.

Do đó exception constraint có thể đến muộn. Nếu cần gắn lỗi với một bước:

```java
repository.save(order);
entityManager.flush(); // gửi SQL, nhưng transaction vẫn chưa commit
```

`flush()` không phải commit. Sau exception, transaction thường phải rollback. Không gọi
`clear()` như cách “sửa” transaction aborted.

Với REST API, map entity sang DTO trong service transaction và thường đặt:

```yaml
spring:
  jpa:
    open-in-view: false
```

Điều này tránh lazy query bất ngờ trong controller/serializer và giữ transaction boundary rõ.

---

## 38. Sequence hợp PostgreSQL và giữ được insert batching

`GenerationType.IDENTITY` thường buộc Hibernate INSERT sớm để lấy ID và cản JDBC insert
batching. PostgreSQL sequence cho phép cấp ID trước:

```java
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
@SequenceGenerator(
    name = "order_seq",
    sequenceName = "orders.order_id_seq",
    allocationSize = 50
)
private Long id;
```

```yaml
spring:
  jpa:
    properties:
      hibernate.jdbc.batch_size: 50
      hibernate.order_inserts: true
      hibernate.order_updates: true
```

`allocationSize`, sequence increment/cache và ORM version phải được migration/integration
test. Gaps là bình thường; không dùng sequence làm invoice number liên tục.

Batch entity lớn cần định kỳ `flush()` + `clear()` để persistence context không giữ hàng
trăm nghìn object, nhưng chunk commit phải theo business atomicity.

---

## 39. N+1 là query-shape bug

```text
1 query lấy 100 orders
+ 100 lazy query lấy customer/items
= 101 round trips
```

Công cụ:

- projection DTO chỉ lấy cột cần;
- `JOIN FETCH` cho quan hệ phù hợp;
- entity graph;
- batch fetching;
- query set-based/JdbcTemplate cho read model.

Không đổi mọi relation sang EAGER; nó chỉ chuyển N+1 thành over-fetch hoặc graph khổng lồ.

Fetch join collection cùng pagination dễ tạo duplicate/cartesian explosion hoặc pagination
trong memory. Mẫu hai bước:

1. keyset/page query chỉ lấy parent IDs theo total order;
2. query thứ hai fetch graph cho tập ID đó;
3. khôi phục thứ tự theo danh sách ID.

Ghi query count và plan trong integration test cho endpoint quan trọng.

---

## 40. Optimistic và pessimistic locking

Optimistic:

```java
@Version
private long version;
```

Hibernate thêm version vào WHERE của UPDATE. Affected rows bằng 0 tạo optimistic-lock
exception. Caller phải reload/recompute hoặc trả conflict; retry cùng detached state không
tự đúng.

Pessimistic:

```java
@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("select o from Order o where o.id = :id")
Optional<Order> lockById(@Param("id") UUID id);
```

Nó thường dẫn tới `SELECT ... FOR UPDATE`. Khóa object theo thứ tự nhất quán, đặt lock
timeout và giữ transaction ngắn. `SKIP LOCKED` phù hợp worker queue, không phù hợp mọi
business read vì nó cố ý bỏ qua row đang bận.

---

## 41. Schema migration có một nguồn chân lý

Production baseline:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate
```

Dùng Flyway/Liquibase hoặc migration system duy nhất để tạo schema. Tránh
`ddl-auto=update` production vì:

- DDL/lock/duration không được review rõ;
- nhiều pod có thể cạnh tranh startup migration;
- không diễn đạt backfill/expand-contract phức tạp;
- rollback và owner/GRANT/RLS dễ drift.

Migration job dùng role riêng có `SET ROLE` owner; runtime không có DDL. Rolling deploy theo:

```text
expand schema → deploy code đọc/ghi tương thích → backfill → chuyển read path → contract
```

Test cả old application với expanded schema và new application trước khi contract.

---

## 42. PgBouncer có ba pooling mode với semantics khác

| Feature | Session pooling | Transaction pooling |
|---|---:|---:|
| Session `SET/RESET` tùy ý | Có | Không |
| `LISTEN` | Có | Không |
| SQL `PREPARE/DEALLOCATE` | Có | Không |
| Protocol-level prepared statement | Có | Có nếu cấu hình tracking |
| Cursor `WITH HOLD` | Có | Không |
| Session advisory lock | Có | Không |
| Transaction advisory lock | Có | Có |
| Temp table `ON COMMIT DROP` | Có | Có |
| Temp table giữ qua transaction | Có | Không |

Session pooling gán một server connection suốt client session. Transaction pooling chỉ
gán server connection trong transaction rồi trả lại pool. Statement pooling còn nghiêm hơn
và không cho multi-statement transaction, hiếm phù hợp Spring/JPA.

Chọn mode từ feature contract, không chỉ từ connection count.

---

## 43. pgJDBC server prepare qua PgBouncer: kiểm tra version và config

PgBouncer hiện hỗ trợ protocol-level named prepared statement trong transaction pooling khi
`max_prepared_statements` khác 0. PgBouncer map query string sang prepared statement trên
server connection phù hợp.

Điều này khác SQL command `PREPARE/EXECUTE/DEALLOCATE`, vẫn không tương thích transaction
pooling. PgBouncer trước 1.21 cũng chưa có tracking này.

Checklist:

- inventory PgBouncer version và `max_prepared_statements`;
- tính memory theo unique query × server connection;
- load test pgJDBC `prepareThreshold`/cache qua pooler;
- test rolling DDL và plan invalidation;
- không gửi `DEALLOCATE ALL`/`DISCARD ALL` tùy tiện;
- chỉ đặt `prepareThreshold=0` khi có bằng chứng incompatibility, không theo folklore cũ.

Hikari trước PgBouncer vẫn có ích để giới hạn application threads, nhưng tổng Hikari client
pool và PgBouncer server pool phải được budget cùng nhau.

---

## 44. RLS tenant context phải đặt trên cùng transaction/connection

Với shared database login sau trusted backend:

```java
@Service
public class TenantOrderService {
    private final EntityManager entityManager;
    private final OrderRepository orders;

    @Transactional
    public OrderView get(UUID authenticatedTenantId, UUID orderId) {
        entityManager.createNativeQuery("""
                SELECT set_config('app.tenant_id', CAST(:tenantId AS text), true)
                """)
            .setParameter("tenantId", authenticatedTenantId)
            .getSingleResult(); // phải là DB operation đầu tiên

        return orders.findViewById(orderId).orElseThrow();
    }
}
```

`true` làm context transaction-local, phù hợp PgBouncer transaction pooling. Contract:

1. Tenant ID lấy từ authentication server-side, không từ query parameter chưa xác minh.
2. Bắt đầu transaction.
3. Đặt context là DB operation đầu tiên, trước mọi JPA flush/query.
4. Query/mutation trong cùng transaction.
5. Commit/rollback xóa context.
6. Test connection reuse A → B qua exception và retry.

Custom GUC không phải credential; client có SQL access có thể tự đặt. `connectionInitSql`
không phù hợp vì không chạy mỗi checkout. Xem thêm [Security & RLS](../operations/security_rls.md).

---

## 45. Read/write routing phải nêu consistency contract

Một router có thể chọn DataSource dựa trên transaction read-only, nhưng annotation chỉ là
input cho router, không phải replication guarantee.

```text
write request → primary → commit LSN
read request  → replica  → có thể chưa replay tới LSN đó
```

Các strategy:

- mọi read cần read-your-writes đi primary;
- sticky-primary một khoảng sau write;
- truyền LSN/freshness token và chờ replica replay có deadline;
- replica chỉ cho report/eventually-consistent endpoint;
- fallback primary khi replica lag vượt SLA.

`AbstractRoutingDataSource` thường cần lazy connection acquisition để routing decision xảy
ra sau khi transaction metadata đã được đặt. Connection lấy quá sớm có thể “dính” primary
hoặc replica trước khi `@Transactional(readOnly=...)` có hiệu lực.

Không retry write sang replica/primary khác như load balancing thông thường.

---

## 46. Observability nối application pool với database backend

Application metrics:

- Hikari active, idle, total, pending;
- connection acquire duration/timeout;
- connection usage/transaction duration;
- query latency/error theo operation, không theo raw SQL/user ID;
- retry count theo SQLSTATE và final outcome;
- batch/COPY rows, bytes, rejects.

Database evidence:

```sql
SELECT pid,
       usename,
       application_name,
       client_addr,
       state,
       xact_start,
       query_start,
       wait_event_type,
       wait_event,
       backend_xid,
       backend_xmin
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY xact_start NULLS LAST;
```

Correlation phải tránh secret/PII. `application_name` nhận diện workload; trace/span có thể
gắn ở application telemetry và sanitized query observation. SQL comment thay đổi liên tục
có thể làm query text/cache/cardinality khó quản lý.

Pool pending tăng không tự chứng minh cần tăng pool; phải xem active connection đang CPU,
I/O, lock hay “idle in transaction”.

---

## 47. Runbook: Hikari pool exhausted

Triệu chứng: active gần max, idle bằng 0, pending/acquire timeout tăng.

1. Xác nhận một pod hay toàn fleet; kiểm tra autoscaling/deploy vừa xảy ra.
2. So acquire time với query/transaction time; tìm request giữ connection lâu.
3. Kiểm tra `pg_stat_activity`: active query, lock wait, idle in transaction, old snapshot.
4. Tìm root blocker bằng `pg_blocking_pids()` và wait event.
5. Kiểm tra database CPU/I/O/WAL/replica sync, không chỉ pool metric.
6. Kiểm tra external I/O nằm trong transaction, streaming/export và `REQUIRES_NEW` nesting.
7. Cancel/terminate theo incident policy, bảo toàn evidence.
8. Sửa query/lock/boundary/leak hoặc admission; chỉ tăng pool sau load test và connection budget.

Tăng pool tức thì có thể đổi queue 20 request ở application thành 200 backend tranh nhau,
làm outage nặng hơn.

---

## 48. Runbook: failover làm Java error hàng loạt

1. Xác nhận control plane đã fence old primary và primary mới writable.
2. Kiểm tra DNS/proxy/multi-host URL và `targetServerType=primary` từ đúng network path.
3. Phân loại lỗi: acquire timeout, connect/auth/TLS, socket reset hay SQLSTATE transaction.
4. Loại connection hỏng khỏi pool; Hikari/driver sẽ tạo connection mới, không cứu transaction cũ.
5. Retry có giới hạn chỉ operation idempotent/retriable; xử lý commit outcome mơ hồ.
6. Theo dõi login storm; nhiều pod cùng reconnect có thể overload primary mới.
7. Kiểm tra sequence/cache, migration state, replica routing và RLS context sau reconnect.
8. Reconcile operation đang ở trạng thái unknown bằng idempotency/business key.

Đừng restart toàn fleet đồng thời nếu sẽ tạo thundering herd. Backoff và rollout có kiểm soát.

---

## 49. Test bằng PostgreSQL thật, không lấy H2 làm bằng chứng tương thích

H2 không mô phỏng đầy đủ PostgreSQL type, MVCC, lock, SQLSTATE, RLS, JSONB, array, planner,
`ON CONFLICT`, COPY hay transaction abort semantics.

Testcontainers baseline:

```java
@Testcontainers
class OrderRepositoryIT {
    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>(DockerImageName.parse("postgres:18"))
            .withDatabaseName("orders")
            .withUsername("test_owner")
            .withPassword("test-secret");

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }
}
```

CI reproducible nên pin patch/digest theo update policy thay vì tag trôi. Chạy migration
production thật trong container.

Test riêng:

- runtime role không phải owner/superuser và RLS cross-tenant deny;
- commit-time constraint và after-commit behavior;
- concurrent lost update/deadlock/Serializable retry;
- pool reuse/session reset;
- PgBouncer transaction mode nếu production dùng;
- failover/connection kill và unknown outcome;
- timezone/DST/JSON/array/null/precision.

Test method `@Transactional` tự rollback có thể che commit-time error và cleanup thực tế;
ít nhất một nhóm test phải commit thật rồi xác minh từ transaction mới.

---

## 50. Production checklist

### Driver, TLS và connection

- [ ] Spring BOM/driver/JDK/PostgreSQL/PgBouncer version có owner và upgrade test.
- [ ] JDBC dùng TLS `verify-full`; secret không nằm trong URL/Git/log.
- [ ] `ApplicationName` ổn định, multi-host/primary selection được failover drill.
- [ ] Acquire/connect/socket/statement/lock/request timeout tạo ngân sách nhất quán.
- [ ] Không có session state request-scoped bị rò qua pool.

### Pool và transaction

- [ ] Tổng pool toàn fleet + job + admin nằm trong connection budget có headroom.
- [ ] Pool size được load test tại knee point, không lấy công thức cố định.
- [ ] `maxLifetime` ngắn hơn hạ tầng; keepalive/TCP keepalive có chủ đích.
- [ ] `@Transactional` boundary đi qua proxy, không self-invocation/private method.
- [ ] Không giữ transaction qua remote I/O/user think time.
- [ ] `REQUIRES_NEW` demand và savepoint support được tính/test.
- [ ] Retry bao ngoài transaction mới, có jitter/deadline/idempotency.

### SQL và mapping

- [ ] PreparedStatement dùng cho value; identifier động qua allowlist.
- [ ] Streaming có fetch size, transaction và consumer bounded.
- [ ] Batch/COPY có chunk, reconciliation và failure contract.
- [ ] UUID/numeric/time/JSON/array/enum mapping đã test edge case.
- [ ] Query quan trọng có deterministic order, keyset và plan evidence.

### JPA, pooler và operations

- [ ] `ddl-auto=validate`; migration tool/owner role là nguồn schema duy nhất.
- [ ] Sequence/batching, N+1, flush và optimistic/pessimistic conflict đã test.
- [ ] `open-in-view=false` cho API trừ ngoại lệ có lý do.
- [ ] PgBouncer mode/feature matrix và prepared-statement tracking khớp client.
- [ ] RLS context transaction-local, là statement đầu tiên và test A → B.
- [ ] Pool/SQLSTATE/retry/failover/COPY metrics cùng incident runbook sẵn sàng.

---

## 51. Anti-pattern và cách sửa

### “Pool 100 để request khỏi chờ”

Queue chuyển vào PostgreSQL và tail latency tăng. Budget toàn fleet, đo knee point và fail
fast/admission ở application.

### “`readOnly=true` nghĩa query chạy replica”

Không. Nó là transaction hint; routing và freshness là thiết kế riêng.

### “PreparedStatement luôn có server plan cache”

Không ngay lập tức. Parameter binding và server prepare là hai tầng; pgJDBC chuyển theo
threshold/cache trên từng physical connection.

### “PgBouncer transaction mode không bao giờ dùng prepared statement”

Folklore này đã cũ với protocol-level prepared statements nếu PgBouncer/config hỗ trợ.
SQL PREPARE và session features vẫn không dùng được.

### “Catch SQL exception rồi tiếp tục transaction”

PostgreSQL thường đánh dấu transaction aborted. Rollback toàn transaction hoặc savepoint
đã thiết kế từ trước.

### “Retry annotation đặt ngay trên method transactional là đủ”

Thứ tự advice có thể làm retry chạy trong transaction đã hỏng. Dùng boundary rõ để mỗi
attempt tạo transaction mới và operation idempotent.

### “Test H2 xanh nên PostgreSQL production an toàn”

H2 không chứng minh PostgreSQL semantics. Dùng PostgreSQL 18 thật và runtime role thật.

---

## 52. Câu hỏi phỏng vấn và tự kiểm tra

### Vì sao tăng Hikari pool có thể làm database chậm hơn?

Pool max là concurrency admission. Quá nhiều backend cùng tranh CPU/I/O/lock làm queue và
context switching tăng trong khi throughput không tăng.

### `connectionTimeout` và `statement_timeout` khác gì?

Một cái giới hạn thời gian chờ mượn connection từ app pool; một cái giới hạn statement
đang chạy phía PostgreSQL.

### `PreparedStatement` có luôn là server-prepared statement không?

Không. Nó luôn bind parameter an toàn; pgJDBC chỉ chuyển sang named server prepare sau
ngưỡng/cấu hình phù hợp.

### Vì sao fetch size không hoạt động khi autocommit bật?

PostgreSQL cursor đóng ở cuối transaction; autocommit kết thúc transaction ngay statement,
nên pgJDBC cần autocommit off và forward-only ResultSet để fetch theo cursor.

### `REQUIRES_NEW` ảnh hưởng pool thế nào?

Outer transaction thường vẫn giữ connection trong khi inner lấy connection khác. N thread
lồng nhau có thể làm pool cạn hoặc deadlock nếu không budget.

### Retry deadlock ở đâu?

Bao ngoài toàn transaction để mỗi attempt có snapshot/connection/transaction mới; không
retry statement bên trong transaction đã aborted.

### Tại sao mất connection lúc COMMIT nguy hiểm?

Client không biết COMMIT đã durable hay chưa. Retry không idempotent có thể tạo duplicate.

### PgBouncer transaction pooling có giữ tenant `SET LOCAL` không?

Có trong chính transaction. Context mất khi transaction kết thúc; đó là behavior mong muốn.
Session `SET` ngoài transaction không phải contract an toàn.

---

## 53. Nguồn chính thức và hoàn thành lộ trình

- [pgJDBC documentation](https://jdbc.postgresql.org/documentation/)
- [pgJDBC connection properties](https://jdbc.postgresql.org/documentation/use/)
- [pgJDBC server prepared statements](https://jdbc.postgresql.org/documentation/server-prepare/)
- [pgJDBC query, fetch size và Java time](https://jdbc.postgresql.org/documentation/query/)
- [pgJDBC `CopyManager`](https://jdbc.postgresql.org/documentation/publicapi/org/postgresql/copy/CopyManager.html)
- [HikariCP configuration](https://github.com/brettwooldridge/HikariCP)
- [Spring transaction management](https://docs.spring.io/spring-framework/reference/data-access/transaction.html)
- [Spring declarative transaction](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative.html)
- [Spring JDBC](https://docs.spring.io/spring-framework/reference/data-access/jdbc.html)
- [Hibernate ORM User Guide](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html)
- [PgBouncer feature matrix](https://www.pgbouncer.org/features.html)
- [PgBouncer configuration](https://www.pgbouncer.org/config.html)
- [PostgreSQL 18 `COPY`](https://www.postgresql.org/docs/18/sql-copy.html)
- [PostgreSQL 18 transaction isolation](https://www.postgresql.org/docs/18/transaction-iso.html)
- [Testcontainers PostgreSQL module](https://java.testcontainers.org/modules/databases/postgres/)

Đã hoàn thành 11 chủ đề trong [PostgreSQL roadmap](../roadmap.md). Khi áp dụng vào dự án,
bước tiếp theo nên là tạo một service mẫu nhỏ chạy PostgreSQL 18 thật, migration, runtime
role/RLS, Hikari metrics và failover/retry integration test thay vì thêm cấu hình trên giấy.

---

*Cập nhật lần cuối: 2026-07-31.*
