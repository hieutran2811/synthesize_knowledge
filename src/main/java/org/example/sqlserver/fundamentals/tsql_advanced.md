# T-SQL Advanced – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – T-SQL Advanced là gì?

**T-SQL (Transact-SQL)** là dialect SQL của Microsoft với extensions: CTEs, window functions, MERGE, temporal tables, JSON/XML support, dynamic SQL, error handling... Đây là ngôn ngữ làm việc chủ yếu với SQL Server.

---

## How – CTE (Common Table Expression)

```sql
-- CTE cơ bản: readable + reusable trong query
WITH CustomerOrders AS (
    SELECT
        c.CustomerID,
        c.CompanyName,
        COUNT(o.OrderID)    AS OrderCount,
        SUM(o.TotalAmount)  AS TotalRevenue
    FROM Customers c
    LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
    GROUP BY c.CustomerID, c.CompanyName
)
SELECT * FROM CustomerOrders WHERE TotalRevenue > 1000000 ORDER BY TotalRevenue DESC;

-- Multiple CTEs
WITH
ActiveCustomers AS (
    SELECT CustomerID FROM Customers WHERE Status = 'Active'
),
RecentOrders AS (
    SELECT CustomerID, SUM(Amount) AS Total
    FROM Orders
    WHERE OrderDate >= DATEADD(MONTH, -3, GETDATE())
    GROUP BY CustomerID
)
SELECT ac.CustomerID, ro.Total
FROM ActiveCustomers ac
LEFT JOIN RecentOrders ro ON ac.CustomerID = ro.CustomerID;

-- Recursive CTE (hierarchy/tree traversal)
WITH OrgChart AS (
    -- Anchor member: root nodes
    SELECT
        EmployeeID, Name, ManagerID,
        CAST(Name AS NVARCHAR(MAX)) AS Hierarchy,
        0 AS Level
    FROM Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive member: children
    SELECT
        e.EmployeeID, e.Name, e.ManagerID,
        CAST(oc.Hierarchy + ' > ' + e.Name AS NVARCHAR(MAX)),
        oc.Level + 1
    FROM Employees e
    INNER JOIN OrgChart oc ON e.ManagerID = oc.EmployeeID
)
SELECT * FROM OrgChart ORDER BY Hierarchy OPTION (MAXRECURSION 100);

-- Recursive CTE: đệ quy tối đa 100 bước (default 100, max 32767, 0 = unlimited)
```

---

## How – Window Functions

```sql
-- Window functions: tính toán trên "window" (tập hàng liên quan) mà không GROUP BY

-- ROW_NUMBER: đánh số thứ tự
SELECT
    OrderID,
    CustomerID,
    Amount,
    ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC) AS RowNum
FROM Orders;
-- RowNum = 1 là order mới nhất của mỗi customer

-- Lấy row mới nhất per group (top-N per group)
WITH Ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC) AS rn
    FROM Orders
)
SELECT * FROM Ranked WHERE rn = 1;

-- RANK vs DENSE_RANK
SELECT
    Name, Score,
    RANK()       OVER (ORDER BY Score DESC) AS RankScore,       -- 1,2,2,4 (gap)
    DENSE_RANK() OVER (ORDER BY Score DESC) AS DenseRankScore,  -- 1,2,2,3 (no gap)
    ROW_NUMBER() OVER (ORDER BY Score DESC) AS RowNum           -- 1,2,3,4 (always unique)
FROM Students;

-- NTILE: chia thành N nhóm bằng nhau
SELECT Name, Score,
    NTILE(4) OVER (ORDER BY Score DESC) AS Quartile  -- 1=top 25%, 4=bottom 25%
FROM Students;

-- Aggregate Window Functions
SELECT
    OrderID, OrderDate, Amount,
    SUM(Amount)   OVER (PARTITION BY CustomerID)                    AS CustomerTotal,
    AVG(Amount)   OVER (PARTITION BY CustomerID)                    AS CustomerAvg,
    SUM(Amount)   OVER (PARTITION BY CustomerID ORDER BY OrderDate
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotal,
    COUNT(*)      OVER ()                                           AS TotalRows
FROM Orders;

-- LAG / LEAD: access rows trước/sau trong window
SELECT
    OrderDate,
    Amount,
    LAG(Amount, 1, 0)  OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount,
    LEAD(Amount, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextAmount,
    Amount - LAG(Amount, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS MoM_Change
FROM Orders;

-- FIRST_VALUE / LAST_VALUE
SELECT
    OrderDate, Amount,
    FIRST_VALUE(Amount) OVER (PARTITION BY CustomerID ORDER BY OrderDate
                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS FirstOrder,
    LAST_VALUE(Amount)  OVER (PARTITION BY CustomerID ORDER BY OrderDate
                               ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastOrder
FROM Orders;

-- Frame types:
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW  → running total
-- ROWS BETWEEN 2 PRECEDING AND CURRENT ROW           → 3-row moving avg
-- RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND ...   → time-based (SQL 2022+)
```

---

## How – PIVOT & UNPIVOT

```sql
-- PIVOT: rows → columns
SELECT *
FROM (
    SELECT Year, Quarter, Revenue
    FROM SalesData
) AS src
PIVOT (
    SUM(Revenue)
    FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS pvt;

-- Dynamic PIVOT (column names không biết trước)
DECLARE @Cols NVARCHAR(MAX), @SQL NVARCHAR(MAX);

SELECT @Cols = STRING_AGG(QUOTENAME(Quarter), ',')
               WITHIN GROUP (ORDER BY Quarter)
FROM (SELECT DISTINCT Quarter FROM SalesData) t;

SET @SQL = N'
SELECT Year, ' + @Cols + '
FROM (SELECT Year, Quarter, Revenue FROM SalesData) src
PIVOT (SUM(Revenue) FOR Quarter IN (' + @Cols + ')) pvt
ORDER BY Year';

EXEC sp_executesql @SQL;

-- UNPIVOT: columns → rows
SELECT Year, Quarter, Revenue
FROM SalesData
UNPIVOT (
    Revenue FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS unpvt;
```

---

## How – MERGE Statement

```sql
-- MERGE: Insert / Update / Delete trong 1 statement (upsert)
MERGE INTO Inventory AS target
USING (
    SELECT ProductID, Quantity FROM IncomingStock
) AS source
ON target.ProductID = source.ProductID

WHEN MATCHED AND target.Quantity + source.Quantity <= 0 THEN
    DELETE

WHEN MATCHED THEN
    UPDATE SET
        target.Quantity = target.Quantity + source.Quantity,
        target.LastUpdated = GETDATE()

WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, Quantity, LastUpdated)
    VALUES (source.ProductID, source.Quantity, GETDATE())

WHEN NOT MATCHED BY SOURCE THEN
    UPDATE SET target.Status = 'Discontinued'

OUTPUT
    $action AS Action,          -- INSERT/UPDATE/DELETE
    inserted.ProductID,
    deleted.Quantity AS OldQty,
    inserted.Quantity AS NewQty;

-- MERGE pitfall: không dùng MERGE khi source có duplicates → multiple matches
-- → dùng ROW_NUMBER trước hoặc INSERT + UPDATE riêng
```

---

## How – Error Handling

```sql
-- TRY...CATCH + Transaction
BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE Accounts SET Balance = Balance - 1000 WHERE AccountID = 1;
    UPDATE Accounts SET Balance = Balance + 1000 WHERE AccountID = 2;

    -- Simulated error
    IF (SELECT Balance FROM Accounts WHERE AccountID = 1) < 0
        THROW 50001, 'Insufficient balance', 1;

    COMMIT TRANSACTION;
    PRINT 'Transfer successful';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- Lấy thông tin lỗi
    DECLARE @ErrMsg  NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrSev  INT            = ERROR_SEVERITY();
    DECLARE @ErrStat INT            = ERROR_STATE();
    DECLARE @ErrNum  INT            = ERROR_NUMBER();
    DECLARE @ErrLine INT            = ERROR_LINE();
    DECLARE @ErrProc NVARCHAR(200)  = ERROR_PROCEDURE();

    -- Log lỗi
    INSERT INTO ErrorLog (ErrorNumber, Severity, State, Procedure, Line, Message, LoggedAt)
    VALUES (@ErrNum, @ErrSev, @ErrStat, @ErrProc, @ErrLine, @ErrMsg, GETDATE());

    -- Re-throw
    THROW;  -- SQL Server 2012+ (re-throw với original error number)
    -- hoặc: RAISERROR(@ErrMsg, @ErrSev, @ErrStat);
END CATCH;

-- User-defined error numbers: 50000-99999
-- Sys messages: SELECT * FROM sys.messages WHERE message_id = 50001;
```

---

## How – Dynamic SQL

```sql
-- Dùng khi: tên object (table/column) là variable, conditional logic phức tạp

-- EXECUTE (không safe - SQL injection risk)
DECLARE @TableName NVARCHAR(128) = 'Orders';
EXEC('SELECT * FROM ' + @TableName);  -- NGUY HIỂM nếu input từ user

-- sp_executesql (safe - parameterized)
DECLARE @SQL NVARCHAR(MAX);
DECLARE @CustomerID INT = 5;

SET @SQL = N'SELECT * FROM Orders WHERE CustomerID = @CustID AND Status = @Status';
EXEC sp_executesql @SQL,
    N'@CustID INT, @Status NVARCHAR(20)',  -- parameter declaration
    @CustID = @CustomerID,
    @Status = N'Active';

-- Dynamic table name (QUOTENAME để prevent injection)
DECLARE @Schema NVARCHAR(128) = 'dbo';
DECLARE @Table  NVARCHAR(128) = 'Orders';

SET @SQL = N'SELECT COUNT(*) FROM ' + QUOTENAME(@Schema) + '.' + QUOTENAME(@Table);
EXEC sp_executesql @SQL;
-- QUOTENAME thêm brackets: [dbo].[Orders]

-- Dynamic column list
DECLARE @Columns NVARCHAR(MAX);
SELECT @Columns = STRING_AGG(QUOTENAME(COLUMN_NAME), ', ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Orders' AND TABLE_SCHEMA = 'dbo';

SET @SQL = N'SELECT ' + @Columns + ' FROM dbo.Orders WHERE OrderDate >= @StartDate';
EXEC sp_executesql @SQL, N'@StartDate DATE', @StartDate = '2026-01-01';
```

---

## How – Temporal Tables (System-Versioned)

```sql
-- Temporal tables: tự động track full history của mọi row

CREATE TABLE Products (
    ProductID   INT            NOT NULL PRIMARY KEY,
    Name        NVARCHAR(100)  NOT NULL,
    Price       DECIMAL(10,2)  NOT NULL,
    -- System time columns (auto-managed)
    ValidFrom   DATETIME2(0) GENERATED ALWAYS AS ROW START NOT NULL,
    ValidTo     DATETIME2(0) GENERATED ALWAYS AS ROW END   NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
) WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.ProductsHistory));

-- CRUD bình thường, SQL Server tự lưu history
UPDATE Products SET Price = 99000 WHERE ProductID = 1;
-- SQL Server auto-insert old row vào ProductsHistory với ValidTo = now

-- Query lịch sử
-- Trạng thái tại thời điểm cụ thể
SELECT * FROM Products
FOR SYSTEM_TIME AS OF '2025-12-01 10:00:00';

-- Tất cả versions trong khoảng thời gian
SELECT * FROM Products
FOR SYSTEM_TIME BETWEEN '2025-01-01' AND '2026-01-01'
WHERE ProductID = 1
ORDER BY ValidFrom;

-- Từ thời điểm bắt đầu đến hiện tại
SELECT * FROM Products
FOR SYSTEM_TIME FROM '2025-01-01' TO SYSUTCDATETIME()
WHERE ProductID = 1;

-- Xóa history cũ
ALTER TABLE Products SET (SYSTEM_VERSIONING = OFF);
DELETE FROM ProductsHistory WHERE ValidTo < DATEADD(YEAR, -2, GETDATE());
ALTER TABLE Products SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.ProductsHistory));
```

---

## How – JSON Support (SQL Server 2016+)

```sql
-- Parse JSON
DECLARE @json NVARCHAR(MAX) = '{"name":"Nguyen Van A","age":30,"orders":[{"id":1},{"id":2}]}';

-- JSON_VALUE: scalar value
SELECT JSON_VALUE(@json, '$.name')              AS Name;        -- 'Nguyen Van A'
SELECT JSON_VALUE(@json, '$.orders[0].id')      AS FirstOrderId; -- '1'

-- JSON_QUERY: object/array
SELECT JSON_QUERY(@json, '$.orders')            AS OrdersArray;

-- OPENJSON: convert JSON array to rowset
SELECT * FROM OPENJSON(@json, '$.orders')
WITH (id INT '$.id');

-- OPENJSON default (key, value, type)
SELECT [key], [value], [type] FROM OPENJSON(@json);

-- FOR JSON: convert result to JSON
SELECT TOP 5 OrderID, CustomerID, Amount
FROM Orders
FOR JSON AUTO;   -- auto detect structure

-- FOR JSON PATH (control output)
SELECT
    c.CustomerID     AS [customer.id],
    c.CompanyName    AS [customer.name],
    o.OrderID        AS [orders.id],
    o.Amount         AS [orders.amount]
FROM Customers c
JOIN Orders o ON c.CustomerID = o.CustomerID
FOR JSON PATH, ROOT('data');

-- Store JSON in column
CREATE TABLE EventStore (
    EventID    INT IDENTITY PRIMARY KEY,
    EventType  NVARCHAR(50),
    Payload    NVARCHAR(MAX),
    CreatedAt  DATETIME2 DEFAULT SYSUTCDATETIME(),
    CHECK (ISJSON(Payload) = 1)  -- validate JSON
);

-- Index on JSON property (computed column)
ALTER TABLE EventStore ADD UserID AS JSON_VALUE(Payload, '$.userId');
CREATE INDEX IX_EventStore_UserID ON EventStore(UserID);
```

---

## How – STRING_AGG, STRING_SPLIT, TRIM (Modern T-SQL)

```sql
-- STRING_AGG (SQL 2017+): aggregate strings
SELECT
    CustomerID,
    STRING_AGG(CAST(OrderID AS NVARCHAR), ',') WITHIN GROUP (ORDER BY OrderDate) AS OrderIDs
FROM Orders
GROUP BY CustomerID;

-- STRING_SPLIT (SQL 2016+): split delimited string
SELECT value AS Tag
FROM STRING_SPLIT('vip,active,premium', ',');

-- Filter table by comma-separated IDs from parameter
DECLARE @IDs NVARCHAR(MAX) = '1,2,3,4,5';
SELECT * FROM Orders
WHERE OrderID IN (SELECT CAST(value AS INT) FROM STRING_SPLIT(@IDs, ','));

-- TRIM, LTRIM, RTRIM
SELECT TRIM('  hello world  ')     -- 'hello world' (SQL 2017+)
SELECT TRIM('.,! ' FROM '.Hello!') -- 'Hello' (trim specific chars)

-- IIF: inline if
SELECT IIF(Amount > 1000, 'High', 'Low') AS Category FROM Orders;

-- CHOOSE: index into list
SELECT CHOOSE(MONTH(OrderDate), 'Jan','Feb','Mar','Apr','May','Jun',
                                'Jul','Aug','Sep','Oct','Nov','Dec') AS MonthName
FROM Orders;

-- FORMAT (chậm hơn CONVERT nhưng flexible)
SELECT FORMAT(Amount, 'C', 'vi-VN')  AS FormattedPrice;  -- 1.000.000 ₫
SELECT FORMAT(GETDATE(), 'dd/MM/yyyy HH:mm') AS FormattedDate;
```

---

## Compare – T-SQL vs ANSI SQL vs PL/pgSQL

| Feature | T-SQL | ANSI SQL | PL/pgSQL (PostgreSQL) |
|---------|-------|----------|----------------------|
| CTE | Yes | Yes (SQL:1999) | Yes |
| Window Functions | Yes | Yes | Yes |
| Recursive CTE | Yes | Yes | Yes |
| MERGE | Yes | Yes | Yes (INSERT ON CONFLICT) |
| PIVOT | Yes | No (vendor) | CROSSTAB extension |
| Temporal Tables | Yes (2016+) | SQL:2011 | No (extension) |
| JSON | Yes (2016+) | No | Yes (native jsonb) |
| Error Handling | TRY/CATCH | No | EXCEPTION |
| Dynamic SQL | sp_executesql | No | EXECUTE |

---

## Trade-offs

```
CTE vs Subquery:
  CTE: readable, reusable trong query, có thể recursive
  Subquery: inline, optimizer có thể optimize tốt hơn trong một số cases
  → CTE không tự tạo temp table (inline, materialized tùy optimizer)
  → Với SQL 2019+: CTE có thể được materialize nếu optimizer thấy fit

Dynamic SQL:
  ✅ Flexible, handle variable objects
  ❌ Harder to debug, potential security risk
  ❌ Execution plan cached per param values (plan bloat nếu không parameterized)
  → Luôn dùng sp_executesql + parameterize

MERGE:
  ✅ Atomic: insert + update + delete trong 1 statement
  ❌ Known bugs (concurrency issues) → Microsoft advises caution in high concurrency
  ❌ Harder to debug than separate statements
  → Cân nhắc INSERT + UPDATE riêng cho high-concurrency scenarios
```

---

## Ghi chú – Chủ đề tiếp theo
> `indexing.md`: Clustered/Non-clustered index, Columnstore, Index internals (B-tree), Execution Plan reading, Statistics

---

*Cập nhật lần cuối: 2026-05-06*
