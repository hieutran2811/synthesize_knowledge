---
title: "SQL Server từ Java: JDBC, Spring Boot & JPA"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022/2025 với mssql-jdbc 12"
source_count: 0
---
# SQL Server từ Java: JDBC, Spring Boot & JPA

> Mục tiêu phiên bản: **SQL Server 2022/2025** với **mssql-jdbc 12.x** và **Spring Boot 3.5 / 4.1**. Driver 12.x đổi mặc định `encrypt` sang `true` — điểm gây lỗi nâng cấp phổ biến nhất.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Indexing](../fundamentals/indexing.md), [Transactions](../fundamentals/transactions.md). Liên quan: [springboot package](../../springboot/roadmap.md).

---

## 1. Vì sao cần một chương riêng cho Java

Phần lớn sự cố hiệu năng SQL Server trong ứng dụng Java **không nằm ở SQL**, mà nằm ở tầng driver và ORM: kiểu tham số sai làm mất index seek, fetch size mặc định gây `ASYNC_NETWORK_IO`, isolation level không khớp, hoặc Hibernate sinh N+1 query. Những vấn đề này không thấy được khi chỉ đọc T-SQL.

Bốn nguyên nhân hàng đầu, theo tần suất gặp trong thực tế:

| Nguyên nhân | Triệu chứng ở phía database | Mục |
|---|---|---|
| `sendStringParametersAsUnicode` mặc định `true` gặp cột `VARCHAR` | Implicit conversion, index scan thay vì seek | 3 |
| Không tham số hóa (nối chuỗi) | Plan cache phình, single-use plan | 4 |
| Fetch size mặc định + xử lý từng row | `ASYNC_NETWORK_IO` cao | 5 |
| Hibernate N+1 | Rất nhiều query nhỏ, CPU cao, `TotalSec` lớn | 8 |

---

## 2. Connection string

### 2.1 Cấu hình đầy đủ cho production

```properties
spring.datasource.url=jdbc:sqlserver://sales-listener:1433;\
  databaseName=SalesDB;\
  encrypt=true;\
  trustServerCertificate=false;\
  hostNameInCertificate=*.corp.local;\
  sendStringParametersAsUnicode=false;\
  applicationName=sales-api;\
  loginTimeout=15;\
  socketTimeout=60000;\
  multiSubnetFailover=true;\
  applicationIntent=ReadWrite;\
  statementPoolingCacheSize=200;\
  disableStatementPooling=false
```

| Tham số | Vì sao đặt |
|---|---|
| `encrypt=true` + `trustServerCertificate=false` | Mã hóa **và** xác minh danh tính server. Đây là cấu hình duy nhất chống được MITM ([security.md](../administration/security.md) mục 4) |
| `sendStringParametersAsUnicode=false` | Nếu schema dùng `VARCHAR`, đây là thay đổi có tác động hiệu năng lớn nhất trong toàn bộ danh sách (mục 3) |
| `applicationName` | Hiện trong `sys.dm_exec_sessions.program_name` — không có nó, DBA không biết query đến từ service nào |
| `socketTimeout` | Không có nó, một query treo giữ connection vô hạn và làm cạn pool |
| `multiSubnetFailover=true` | Bắt buộc khi listener Always On có nhiều IP ([ha_dr.md](../administration/ha_dr.md) mục 8) |
| `applicationIntent=ReadOnly` | Cho datasource chỉ đọc, để routing sang secondary |
| `statementPoolingCacheSize` | Bật prepared statement pooling ở phía driver |

`applicationName` là tham số rẻ nhất và hữu ích nhất trong danh sách: nó biến việc "truy query này của service nào" từ một cuộc điều tra thành một câu `SELECT`.

### 2.2 Nâng cấp lên driver 12.x

Từ mssql-jdbc 10.2, mặc định `encrypt` chuyển từ `false` sang `true`, và driver bắt đầu xác minh certificate. Kết quả điển hình khi nâng version:

```text
com.microsoft.sqlserver.jdbc.SQLServerException:
  The driver could not establish a secure connection to SQL Server by using
  Secure Sockets Layer (SSL) encryption. Error: "PKIX path building failed..."
```

Ba cách xử lý, xếp theo mức đúng đắn:

```properties
# 1. ĐÚNG: cài certificate của server (hoặc CA của nó) vào truststore
#    -Djavax.net.ssl.trustStore=/etc/ssl/java/truststore.jks
encrypt=true;trustServerCertificate=false;hostNameInCertificate=sql1.corp.local

# 2. Tạm được cho môi trường nội bộ có kiểm soát: truststore riêng cho ứng dụng
encrypt=true;trustServerCertificate=false;\
  trustStore=/app/config/mssql-truststore.jks;trustStorePassword=${TS_PW}

# 3. CHỈ dev/test: bỏ xác minh — không dùng trên production
encrypt=true;trustServerCertificate=true
```

---

## 3. Kiểu dữ liệu: nguyên nhân số một của "có index mà vẫn scan"

Mặc định, driver gửi `String` dưới dạng `NVARCHAR`. Nếu cột là `VARCHAR`, SQL Server phải convert **cột** sang `NVARCHAR` để so sánh (vì `NVARCHAR` có độ ưu tiên kiểu cao hơn) — và điều đó vô hiệu hóa index seek trên cột đó.

```text
Cột : CustomerCode VARCHAR(20), có index
Driver gửi: N'ABC123'
Plan: Index Scan + CONVERT_IMPLICIT(nvarchar, CustomerCode)
      → đọc toàn bộ index thay vì seek
```

```properties
# Cách sửa toàn cục nếu schema dùng VARCHAR
sendStringParametersAsUnicode=false
```

Nếu schema có **cả** `VARCHAR` và `NVARCHAR`, đặt toàn cục sẽ chuyển vấn đề sang phía `NVARCHAR`. Khi đó chỉ định kiểu ở từng tham số:

```java
// Chỉ định tường minh cho tham số cụ thể
ps.setObject(1, code, java.sql.Types.VARCHAR);      // gửi như VARCHAR
ps.setObject(2, name, java.sql.Types.NVARCHAR);     // gửi như NVARCHAR

// Hoặc dùng API riêng của driver
((SQLServerPreparedStatement) ps).setString(1, code, false);   // false = không unicode
```

Với Hibernate, khai báo kiểu ở entity để tránh phải nhớ ở từng chỗ:

```java
@Column(name = "CustomerCode", columnDefinition = "varchar(20)")
@JdbcTypeCode(SqlTypes.VARCHAR)      // Hibernate 6+
private String customerCode;
```

Cách phát hiện vấn đề này trên database:

```sql
SELECT TOP 20 qs.execution_count,
       qs.total_worker_time / qs.execution_count AS AvgCpuUs,
       SUBSTRING(st.text, 1, 300) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%'
ORDER BY qs.total_worker_time DESC;
```

### 3.1 Bảng ánh xạ kiểu

| SQL Server | Java | Ghi chú |
|---|---|---|
| `INT` / `BIGINT` | `Integer` / `Long` | – |
| `DECIMAL(p,s)` | `BigDecimal` | **Không dùng `double`** cho tiền |
| `VARCHAR(n)` | `String` | Cần `sendStringParametersAsUnicode=false` hoặc chỉ định kiểu |
| `NVARCHAR(n)` | `String` | Mặc định của driver |
| `DATETIME2(p)` | `LocalDateTime` | Ưu tiên cho thiết kế mới |
| `DATETIMEOFFSET` | `OffsetDateTime` | Khi cần giữ offset múi giờ |
| `DATE` / `TIME` | `LocalDate` / `LocalTime` | – |
| `BIT` | `Boolean` | – |
| `UNIQUEIDENTIFIER` | `UUID` (qua `String` ở driver cũ) | Chú ý thứ tự byte khi so sánh |
| `ROWVERSION` | `byte[]` | Dùng với `@Version` (mục 7) |
| `VARBINARY(MAX)` | `byte[]` / `Blob` | Cân nhắc lưu ngoài database nếu lớn |
| `json` (2025) | `String` | Xem [sqlserver_2025.md](../modern/sqlserver_2025.md) |

Về `DATETIMEOFFSET` và `OffsetDateTime`: đây là lựa chọn đúng cho hệ thống đa múi giờ, nhưng cần nhất quán — trộn `DATETIME2` (không offset) và `DATETIMEOFFSET` trong cùng schema là nguồn lỗi lệch giờ rất khó tìm.

---

## 4. PreparedStatement và plan reuse

```java
// ✓ Tham số hóa: một plan dùng lại cho mọi giá trị
String sql = """
    SELECT OrderID, CustomerID, TotalAmount
    FROM Sales.Orders
    WHERE TenantID = ? AND Status = ? AND OrderDate >= ?
    """;
try (PreparedStatement ps = conn.prepareStatement(sql)) {
    ps.setInt(1, tenantId);
    ps.setObject(2, status, Types.VARCHAR);
    ps.setObject(3, from, Types.TIMESTAMP);
    try (ResultSet rs = ps.executeQuery()) { /* ... */ }
}

// ✗ Nối chuỗi: mỗi giá trị một plan mới, và mở lỗ SQL injection
String bad = "SELECT ... WHERE TenantID = " + tenantId;
```

### 4.1 `prepareMethod`: `prepexec` vs `sp_prepare`

Driver có hai cách chuẩn bị statement:

| `prepareMethod` | Cơ chế | Phù hợp |
|---|---|---|
| `prepexec` (mặc định) | `sp_prepexec`: chuẩn bị và thực thi trong một round-trip | Statement chạy ít lần |
| `sp_prepare` | Chuẩn bị riêng, thực thi nhiều lần bằng handle | Statement chạy rất nhiều lần |

```properties
# Bật statement pooling để tận dụng handle
statementPoolingCacheSize=200
disableStatementPooling=false
enablePrepareOnFirstPreparedStatementCall=false   # mặc định: lần đầu dùng prepexec
serverPreparedStatementDiscardThreshold=10
```

`enablePrepareOnFirstPreparedStatementCall=false` là mặc định hợp lý: nếu một statement chỉ chạy một lần, việc chuẩn bị riêng là round-trip thừa.

### 4.2 Truyền danh sách tham số (IN clause)

Vấn đề: `WHERE Id IN (?, ?, ?)` với số lượng thay đổi tạo ra một query shape khác cho mỗi số lượng → nhiều plan.

```java
// Cách tốt: Table-Valued Parameter — một query shape duy nhất
SQLServerDataTable idTable = new SQLServerDataTable();
idTable.addColumnMetadata("Id", java.sql.Types.BIGINT);
for (Long id : ids) idTable.addRow(id);

String sql = "SELECT o.* FROM Sales.Orders o JOIN @ids i ON o.OrderID = i.Id";
try (SQLServerPreparedStatement ps = (SQLServerPreparedStatement) conn.prepareStatement(sql)) {
    ps.setStructured(1, "dbo.IdList", idTable);
    // ...
}
```

```sql
-- Kiểu bảng phía database
CREATE TYPE dbo.IdList AS TABLE (Id BIGINT NOT NULL PRIMARY KEY);
```

Cách thay thế đơn giản hơn khi không muốn tạo TVP: truyền một chuỗi JSON và dùng `OPENJSON`.

```java
ps.setString(1, objectMapper.writeValueAsString(ids));
```

```sql
SELECT o.* FROM Sales.Orders o
JOIN OPENJSON(@ids) WITH (Id BIGINT '$') i ON o.OrderID = i.Id;
```

Cả hai cách đều tốt hơn hẳn việc sinh `IN (?, ?, ..., ?)` động — và tốt hơn rất nhiều so với nối chuỗi id vào SQL.

---

## 5. Fetch size và `ASYNC_NETWORK_IO`

Mặc định của driver là gửi dữ liệu theo cách mà client phải đọc hết; nếu ứng dụng xử lý chậm từng row, SQL Server chờ và tích lũy wait `ASYNC_NETWORK_IO`.

```java
// Đọc streaming cho tập lớn: không tải hết vào bộ nhớ, và đọc theo lô
try (PreparedStatement ps = conn.prepareStatement(sql,
        ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY)) {
    ps.setFetchSize(1000);          // lấy 1000 row mỗi lần
    try (ResultSet rs = ps.executeQuery()) {
        while (rs.next()) { process(rs); }
    }
}
```

```properties
# Với Spring Data JPA
spring.jpa.properties.hibernate.jdbc.fetch_size=200
```

Nguyên tắc thực dụng:

| Tình huống | Fetch size |
|---|---|
| Query trả về vài row (API lookup) | Mặc định |
| Báo cáo/export hàng trăm nghìn row | 500–2000 |
| Xử lý từng row có logic nặng | Vẫn đặt fetch size, nhưng **cân nhắc tách batch phía SQL** |

Điều quan trọng hơn cả fetch size: **đừng kéo dữ liệu về Java để xử lý những gì SQL làm tốt hơn**. Một vòng lặp Java đọc 2 triệu row rồi tính tổng nên là một câu `SUM()`. Wait `ASYNC_NETWORK_IO` cao thường là dấu hiệu của kiến trúc này, không phải của cấu hình driver.

---

## 6. Connection pool (HikariCP)

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      connection-timeout: 10000       # chờ lấy connection từ pool
      validation-timeout: 3000
      idle-timeout: 300000
      max-lifetime: 900000            # < timeout của firewall/load balancer
      keepalive-time: 120000
      leak-detection-threshold: 60000  # log stack trace nếu giữ connection > 60s
      connection-test-query: SELECT 1  # mssql-jdbc hỗ trợ isValid(); thường không cần
      data-source-properties:
        applicationName: sales-api
        socketTimeout: 60000
        cancelQueryTimeout: 5
```

### 6.1 Chọn `maximum-pool-size`

Sai lầm thường gặp là đặt pool size lớn với suy nghĩ "nhiều connection = nhiều throughput". Thực tế ngược lại: mỗi connection đang chạy query đều cạnh tranh CPU, memory grant và lock trên cùng một instance.

```text
Điểm khởi đầu:  pool_size ≈ (số core của DB server × 2) + số spindle/đường I/O hiệu dụng
Thực tế:        thường 10–30 cho một service; TĂNG chỉ khi đo được connection-wait
                và database CHƯA bị nghẽn
```

Nếu tăng pool size mà latency tệ hơn, nghĩa là database đã là điểm nghẽn — và câu trả lời là tuning query, không phải thêm connection.

```sql
-- Nhìn từ phía database: mỗi ứng dụng đang mở bao nhiêu connection
SELECT program_name, host_name, login_name,
       COUNT(*) AS Connections,
       SUM(CASE WHEN status = 'running'  THEN 1 ELSE 0 END) AS Running,
       SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END) AS Sleeping
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY program_name, host_name, login_name
ORDER BY Connections DESC;
```

`Sleeping` cao kèm transaction mở là dấu hiệu ứng dụng giữ transaction qua ranh giới request — vấn đề đã mô tả ở [transactions.md](../fundamentals/transactions.md) mục 2.2.

### 6.2 `max-lifetime` và timeout của tầng mạng

Nếu firewall/NLB đóng kết nối idle sau 15 phút mà pool vẫn giữ, ứng dụng sẽ gặp lỗi "connection reset" ngẫu nhiên. Quy tắc: `max-lifetime` phải **nhỏ hơn** timeout ngắn nhất của mọi thiết bị trên đường đi.

### 6.3 Datasource riêng cho read-only

```java
@Bean
@ConfigurationProperties("app.datasource.write")
public DataSource writeDataSource() { return DataSourceBuilder.create().build(); }

@Bean
@ConfigurationProperties("app.datasource.read")
public DataSource readDataSource() { return DataSourceBuilder.create().build(); }
```

```properties
app.datasource.write.url=jdbc:sqlserver://sales-listener:1433;databaseName=SalesDB;applicationIntent=ReadWrite;...
app.datasource.read.url=jdbc:sqlserver://sales-listener:1433;databaseName=SalesDB;applicationIntent=ReadOnly;...
```

Kết hợp với `@Transactional(readOnly = true)` và một `AbstractRoutingDataSource`, workload đọc được đẩy sang readable secondary của Always On. Lưu ý ràng buộc đã nêu ở [ha_dr.md](../administration/ha_dr.md) mục 2.4: dữ liệu trên secondary tụt hậu theo redo queue, nên chỉ dùng cho nghiệp vụ chấp nhận được điều đó.

---

## 7. Transaction và concurrency từ Java

### 7.1 Isolation level

```java
@Transactional(isolation = Isolation.READ_COMMITTED, timeout = 10)
public void payOrder(long orderId) { /* ... */ }
```

Điều quan trọng: nếu database đã bật **RCSI** ([transactions.md](../fundamentals/transactions.md) mục 4.3), `READ_COMMITTED` từ Java tự động được thực hiện bằng row versioning — **không cần sửa code ứng dụng**. Đây là lý do bật RCSI là biện pháp có tỷ lệ lợi ích/công sức cao nhất cho ứng dụng Java đang bị blocking.

`Isolation.READ_UNCOMMITTED` từ Java tương đương `NOLOCK` và mang đúng những rủi ro đã nêu (đọc trùng row, mất row, lỗi 601). Không dùng nó như biện pháp chống blocking.

### 7.2 Optimistic locking với `ROWVERSION`

```java
@Entity
@Table(name = "Products", schema = "Catalog")
public class Product {
    @Id private Integer productId;
    private String name;
    private Integer stock;

    @Version
    @Column(name = "RowVer", insertable = false, updatable = false)
    private byte[] rowVer;      // ROWVERSION: engine tự tăng
}
```

Hibernate sinh `UPDATE ... WHERE ProductID = ? AND RowVer = ?`, và ném `OptimisticLockException` nếu không có row nào bị ảnh hưởng. Ứng dụng xử lý bằng reload + retry hoặc báo người dùng.

```java
@Retryable(retryFor = ObjectOptimisticLockingFailureException.class,
           maxAttempts = 3, backoff = @Backoff(delay = 50, multiplier = 2, random = true))
@Transactional
public void decreaseStock(int productId, int qty) { /* ... */ }
```

### 7.3 Retry cho deadlock và lock timeout

```java
private static final Set<Integer> RETRIABLE = Set.of(
    1205,   // deadlock victim
    1222,   // lock request timeout
    3960,   // snapshot update conflict
    41302, 41305, 41325, 41301   // In-Memory OLTP validation
);

public <T> T withRetry(Supplier<T> work) {
    int attempt = 0;
    while (true) {
        try {
            return work.get();
        } catch (DataAccessException e) {
            Integer code = sqlErrorCode(e);
            if (code == null || !RETRIABLE.contains(code) || ++attempt >= 3) throw e;
            sleepWithJitter(attempt);       // backoff CÓ jitter
        }
    }
}

private Integer sqlErrorCode(DataAccessException e) {
    Throwable t = e.getMostSpecificCause();
    return (t instanceof SQLServerException sse) ? sse.getErrorCode() : null;
}
```

Jitter là chi tiết bắt buộc, không phải tinh chỉnh: nếu hai transaction deadlock rồi cùng retry sau đúng 50ms, chúng tái tạo lại đúng deadlock đó. Với Spring Retry, `@Backoff(random = true)`.

### 7.4 Timeout ba tầng

Ba loại timeout khác nhau, cần đặt cả ba:

| Tầng | Cấu hình | Tác dụng |
|---|---|---|
| Query | `@Transactional(timeout = 10)` hoặc `Statement.setQueryTimeout(10)` | Driver gửi lệnh hủy tới server |
| Socket | `socketTimeout=60000` | Chặn treo vô hạn khi mạng đứt |
| Lock (phía DB) | `SET LOCK_TIMEOUT 5000` | Lỗi 1222 thay vì chờ mãi |

```properties
# Rất quan trọng khi có queryTimeout: cho phép việc hủy cũng có timeout
cancelQueryTimeout=5
```

Không có `cancelQueryTimeout`, một lệnh hủy có thể tự treo và giữ connection.

---

## 8. Hibernate/JPA với SQL Server

### 8.1 Cấu hình

```yaml
spring:
  jpa:
    database-platform: org.hibernate.dialect.SQLServerDialect
    open-in-view: false                 # tắt: tránh giữ session/connection suốt request
    properties:
      hibernate:
        jdbc:
          batch_size: 50
          fetch_size: 200
          time_zone: UTC
        order_inserts: true             # bắt buộc để batch hoạt động thật
        order_updates: true
        batch_versioned_data: true
        query:
          in_clause_parameter_padding: true   # giảm số query shape cho IN clause
        generate_statistics: false      # bật khi cần điều tra, tắt trên production
```

Hai cấu hình đáng chú ý:

- `open-in-view: false` — mặc định `true` của Spring Boot giữ `EntityManager` (và có thể cả connection) suốt vòng đời request, làm pool cạn dưới tải cao và ẩn các truy vấn lazy loading ngoài tầm kiểm soát.
- `in_clause_parameter_padding: true` — Hibernate làm tròn số tham số `IN` lên lũy thừa 2, giảm số query shape khác nhau từ hàng trăm xuống vài chục, giúp plan cache không phình (liên quan mục 4.2).

### 8.2 Chiến lược sinh ID

```java
// ✓ Tốt nhất cho SQL Server: SEQUENCE cho phép Hibernate batch insert
@Id
@GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_seq")
@SequenceGenerator(name = "order_seq", sequenceName = "Sales.OrderSeq",
                   allocationSize = 50)
private Long orderId;

// ✗ IDENTITY: Hibernate PHẢI insert từng row để lấy id → batch insert không hoạt động
@Id @GeneratedValue(strategy = GenerationType.IDENTITY)
private Long orderId;
```

```sql
CREATE SEQUENCE Sales.OrderSeq AS BIGINT START WITH 1 INCREMENT BY 50 CACHE 100;
```

Đây là một trong những khác biệt hiệu năng lớn nhất và ít được biết nhất: với `IDENTITY`, Hibernate không thể gom `INSERT` thành batch vì cần id trả về ngay sau mỗi row. Với `SEQUENCE` và `allocationSize` khớp `INCREMENT BY`, một batch 50 insert là một round-trip.

### 8.3 N+1 query

```java
// ✗ N+1: một query lấy orders, rồi N query lấy items
List<Order> orders = orderRepository.findByTenantId(tenantId);
orders.forEach(o -> o.getItems().size());

// ✓ JOIN FETCH
@Query("SELECT DISTINCT o FROM Order o LEFT JOIN FETCH o.items WHERE o.tenantId = :tenantId")
List<Order> findWithItems(@Param("tenantId") int tenantId);

// ✓ EntityGraph
@EntityGraph(attributePaths = {"items", "customer"})
List<Order> findByTenantId(int tenantId);

// ✓ Batch fetch cho collection: giảm N query thành N/size query
@BatchSize(size = 50)
@OneToMany(mappedBy = "order")
private List<OrderItem> items;
```

Cách phát hiện N+1 từ phía database — nó rất dễ nhận ra khi biết tìm gì:

```sql
-- Query giống nhau, chạy hàng nghìn lần, mỗi lần rất nhanh
SELECT TOP 20 qs.execution_count,
       qs.total_elapsed_time / qs.execution_count / 1000.0 AS AvgMs,
       qs.total_elapsed_time / 1000.0 AS TotalMs,
       SUBSTRING(st.text, 1, 200) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.execution_count > 1000
ORDER BY qs.execution_count DESC;
```

Dấu hiệu: `AvgMs` rất nhỏ (1–3ms) nhưng `execution_count` khổng lồ và `TotalMs` lớn. Đây chính là lý do mục 10 của [query_optimization.md](../performance/query_optimization.md) nhấn mạnh xếp theo tổng thời gian, không theo thời gian trung bình.

### 8.4 Khi nào bỏ ORM

| Tình huống | Nên dùng |
|---|---|
| CRUD theo aggregate | JPA/Hibernate |
| Query phức tạp nhiều join, cần kiểm soát plan | JdbcTemplate hoặc native query |
| Báo cáo, aggregate lớn | Native SQL, hoặc view/procedure phía database |
| Bulk insert/update hàng trăm nghìn row | `SQLServerBulkCopy` ([data_movement.md](data_movement.md) mục 2.4) |
| Cần hint SQL Server (`OPTION (...)`) | Native query, hoặc **Query Store hints** để không sửa code ([query_optimization.md](../performance/query_optimization.md) mục 4.5) |

Điểm cuối rất hữu ích: khi Hibernate sinh SQL không thể thêm hint, bạn vẫn áp được hint từ phía database bằng Query Store hints — không cần đổi một dòng code Java.

---

## 9. Gọi stored procedure

```java
// Với Spring: SimpleJdbcCall
SimpleJdbcCall call = new SimpleJdbcCall(jdbcTemplate)
        .withSchemaName("Sales")
        .withProcedureName("usp_CancelOrder")
        .declareParameters(new SqlParameter("OrderID", Types.BIGINT));
call.execute(Map.of("OrderID", orderId));

// JDBC thuần với output parameter
try (CallableStatement cs = conn.prepareCall("{call Sales.usp_CreateOrder(?, ?, ?)}")) {
    cs.setInt(1, tenantId);
    cs.setBigDecimal(2, amount);
    cs.registerOutParameter(3, Types.BIGINT);
    cs.execute();
    long newId = cs.getLong(3);
}
```

Hai lưu ý khi gọi procedure từ Java:

```sql
-- Trong procedure, LUÔN có SET NOCOUNT ON:
-- không có nó, mỗi statement gửi về một "rows affected" message,
-- driver phải xử lý và có thể nhầm là result set.
CREATE OR ALTER PROCEDURE Sales.usp_CreateOrder @TenantID INT, @Amount DECIMAL(19,4), @OrderID BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    INSERT INTO Sales.Orders (TenantID, TotalAmount, OrderDate, Status)
    VALUES (@TenantID, @Amount, SYSUTCDATETIME(), 'PENDING');
    SET @OrderID = SCOPE_IDENTITY();
END
```

Và: procedure ném lỗi bằng `THROW` với severity ≥ 11 mới được driver dịch thành `SQLException`. Lỗi severity thấp hơn chỉ là thông báo và ứng dụng sẽ **không** thấy — nguồn của lỗi "procedure báo lỗi mà Java không biết".

---

## 10. Multi-tenant với RLS và session context

Nếu database dùng Row-Level Security ([security.md](../administration/security.md) mục 5), ứng dụng phải đặt session context sau khi lấy connection từ pool — và **connection pool khiến việc này phải cẩn thận**: một connection trả về pool vẫn giữ context của tenant trước.

```java
public class TenantAwareDataSource extends DelegatingDataSource {

    @Override
    public Connection getConnection() throws SQLException {
        Connection conn = super.getConnection();
        applyTenantContext(conn);
        return conn;
    }

    private void applyTenantContext(Connection conn) throws SQLException {
        Integer tenantId = TenantContext.current();
        if (tenantId == null) throw new IllegalStateException("No tenant in context");

        try (CallableStatement cs = conn.prepareCall(
                "{call sys.sp_set_session_context(N'TenantID', ?, 1)}")) {   // 1 = read_only
            cs.setInt(1, tenantId);
            cs.execute();
        }
    }
}
```

Vì `@read_only = 1` khiến không thể đặt lại giá trị trên cùng connection, mẫu đúng là **reset context khi trả connection về pool** (HikariCP `connectionInitSql` không đủ vì nó chỉ chạy lúc tạo connection). Hai cách khả thi:

1. Không dùng `@read_only = 1`, đặt lại context ở mỗi lần lấy connection — đơn giản hơn nhưng yếu hơn về bảo mật.
2. Dùng pool riêng theo tenant nếu số tenant nhỏ, hoặc `SET CONTEXT_INFO` với kiểm tra chặt ở predicate.

Đây là một đánh đổi thật giữa bảo mật và độ phức tạp, và cần quyết định có ý thức thay vì để mặc định.

---

## 11. Always Encrypted từ Java

```properties
jdbc:sqlserver://sql1:1433;databaseName=SalesDB;encrypt=true;
  columnEncryptionSetting=Enabled;
  keyStoreAuthentication=KeyVaultClientSecret;
  keyStorePrincipalId=<client-id>;keyStoreSecret=<client-secret>
```

```java
// Cột đã mã hóa BẮT BUỘC dùng tham số; literal không mã hóa được
try (PreparedStatement ps = conn.prepareStatement(
        "SELECT EmployeeID, FullName FROM HR.Employees WHERE NationalID = ?")) {
    ps.setString(1, nationalId);       // driver mã hóa trước khi gửi
    // Chỉ hoạt động nếu cột là DETERMINISTIC
}
```

Giới hạn phải thiết kế xung quanh ([security.md](../administration/security.md) mục 8): không `LIKE`, không so sánh dải, không `SUM`/`AVG` trên cột đã mã hóa. Điều này thường có nghĩa là logic tìm kiếm/tổng hợp trên cột đó phải chuyển lên tầng Java, hoặc thiết kế lại để không cần.

---

## 12. Quan sát từ hai phía

```yaml
# Micrometer: metric của pool và của JDBC
management:
  endpoints.web.exposure.include: health,metrics,prometheus
  metrics.enable.hikaricp: true
```

Ghép metric hai phía để chẩn đoán nhanh — đây là bảng đọc chéo hữu ích nhất khi có sự cố:

| Triệu chứng phía Java | Kiểm tra phía SQL Server | Kết luận thường gặp |
|---|---|---|
| `hikaricp.connections.pending` cao | `sys.dm_exec_requests` có blocking? | Nếu có blocking → sửa database; nếu không → pool nhỏ hoặc query chậm |
| Latency cao, DB CPU thấp | Wait `ASYNC_NETWORK_IO` cao | Ứng dụng xử lý chậm hoặc fetch size sai (mục 5) |
| `SQLServerException` 1205 | `xml_deadlock_report` | Deadlock: cần retry + xem thứ tự truy cập |
| `SQLTimeoutException` | `sys.dm_exec_requests` wait gì | Blocking hay query thật sự chậm |
| Latency đột biến sau deploy | Query Store "Regressed Queries" | Query mới hoặc plan hồi quy |
| Leak detection cảnh báo | Session `sleeping` có transaction mở | Transaction vượt ranh giới request |
| Connection reset ngẫu nhiên | – | `max-lifetime` > timeout của firewall (mục 6.2) |

```sql
-- Truy query đến từ service nào (nhờ applicationName)
SELECT s.program_name, s.login_name, s.host_name,
       COUNT(*) AS Sessions,
       SUM(r.cpu_time) AS CpuMs,
       SUM(r.logical_reads) AS Reads
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
WHERE s.is_user_process = 1
GROUP BY s.program_name, s.login_name, s.host_name
ORDER BY CpuMs DESC;
```

---

## 13. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| `sendStringParametersAsUnicode=false` | Index seek trên cột `VARCHAR` | Sai nếu schema dùng `NVARCHAR` | Schema chủ yếu `VARCHAR` |
| `encrypt=true` + verify certificate | Chống MITM | Phải quản lý truststore | Luôn, trên production |
| Pool lớn | Nhiều request song song | Cạnh tranh CPU/lock ở DB, latency tệ hơn | Tăng chỉ khi đo được connection-wait và DB chưa nghẽn |
| `SEQUENCE` thay `IDENTITY` | Hibernate batch insert được | Id có khoảng trống, cần tạo sequence | Ứng dụng insert theo lô |
| `open-in-view: false` | Không giữ connection suốt request | Phải xử lý lazy loading tường minh | Luôn |
| JPA | Năng suất, mapping tự động | Ít kiểm soát SQL/plan | CRUD theo aggregate |
| JdbcTemplate/native | Kiểm soát hoàn toàn | Viết nhiều hơn | Query phức tạp, báo cáo |
| `SQLServerBulkCopy` | Nhanh hơn nhiều lần | API riêng của driver | Nạp hàng trăm nghìn row |
| Query Store hints | Áp hint không sửa code | Ẩn với developer, phải tài liệu hóa | ORM sinh SQL không thêm hint được |
| Datasource read-only riêng | Giảm tải primary | Dữ liệu tụt hậu; thêm phức tạp | Có Always On và nghiệp vụ chấp nhận |

---

## 14. Checklist

```text
Connection
□ encrypt=true, trustServerCertificate=false, certificate trong truststore
□ applicationName đặt tên service (để DBA truy được nguồn query)
□ sendStringParametersAsUnicode khớp với schema
□ socketTimeout, loginTimeout, cancelQueryTimeout đặt tường minh
□ multiSubnetFailover=true nếu dùng Always On listener
□ Mật khẩu từ Vault/K8s secret, không trong file cấu hình commit vào repo

Pool
□ maximum-pool-size dựa trên đo lường, không dựa trên phỏng đoán
□ max-lifetime < timeout ngắn nhất của firewall/NLB
□ leak-detection-threshold bật ở môi trường test
□ Metric pool được export và có dashboard

Query
□ Mọi query tham số hóa (không nối chuỗi)
□ IN clause dùng TVP/JSON hoặc bật in_clause_parameter_padding
□ fetch size đặt cho query trả về tập lớn
□ Không kéo dữ liệu về Java để làm việc SQL làm tốt hơn

Transaction
□ Transaction không bao trọn lời gọi bên ngoài
□ @Transactional(timeout = n) trên nghiệp vụ có SLA
□ Retry cho 1205/1222/3960 với backoff CÓ jitter
□ @Version + ROWVERSION cho optimistic locking nơi cần
□ open-in-view = false

ORM
□ SEQUENCE (không IDENTITY) nếu cần batch insert
□ Không có N+1 (kiểm tra bằng execution_count ở mục 8.3)
□ order_inserts / order_updates bật cùng batch_size

Kiểm thử
□ Integration test dùng Testcontainers với image SQL Server thật, không H2
□ Test có kịch bản concurrency (deadlock, optimistic conflict)
```

---

## 15. Ghi chú – chủ đề tiếp theo

- [data_movement.md](data_movement.md): `SQLServerBulkCopy`, CDC từ Java.
- [sqlserver_2025.md](../modern/sqlserver_2025.md): kiểu `json`, `vector` và cách dùng từ Java.
- [query_optimization.md](../performance/query_optimization.md): Query Store hints cho SQL do ORM sinh.
- [linux_containers.md](../platform/linux_containers.md): Testcontainers, chạy DB trong CI.
- [springboot package](../../springboot/roadmap.md): `springboot_data.md`, `springboot_testing.md` cho phía framework.

Từ khóa mở rộng: `SQLServerXADataSource` (distributed transaction), `SQLServerDataSource` với Managed Identity, `useBulkCopyForBatchInsert=true` (driver 9.2+), `sendTemporalDataTypesAsStringForBulkCopy`, R2DBC cho reactive, `sp_execute_external_script` gọi Python/R.

Một tham số driver đáng biết cho ETL viết bằng Spring Data:

```properties
# Chuyển batch INSERT của JDBC sang giao thức bulk copy: nhanh hơn nhiều lần
useBulkCopyForBatchInsert=true
```

Nó có giới hạn (không dùng được với `IDENTITY` sinh phía server trong một số cấu hình, và có yêu cầu riêng về kiểu dữ liệu), nên cần kiểm thử — nhưng khi áp dụng được thì đây là một trong những thay đổi một dòng có tác động lớn nhất cho tác vụ nạp dữ liệu.

---

*Cập nhật lần cuối: 2026-07-30*
