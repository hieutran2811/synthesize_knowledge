---
title: "T-SQL Advanced"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 0
---
# T-SQL Advanced

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Mỗi tính năng đều ghi version xuất hiện, vì T-SQL là nơi khác biệt version lộ ra rõ nhất.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Architecture](architecture.md). Đọc tiếp: [Indexing](indexing.md).

---

## 1. T-SQL nghĩ theo tập hợp, không theo vòng lặp

Điểm chuyển đổi tư duy lớn nhất khi từ Java sang T-SQL: **một câu lệnh mô tả kết quả mong muốn, không mô tả các bước lấy kết quả**. Optimizer tự chọn cách thực thi. Mỗi khi bạn viết `WHILE` hoặc `CURSOR` để xử lý từng row, bạn đang tước bỏ quyền đó của optimizer và tự nhận lấy chi phí O(n) round-trip nội bộ.

```sql
-- Cách tư duy vòng lặp: mỗi row một lần cập nhật
DECLARE @id INT;
DECLARE c CURSOR FOR SELECT OrderID FROM Sales.Orders WHERE Status = 'NEW';
OPEN c; FETCH NEXT FROM c INTO @id;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE Sales.Orders SET Status = 'PROCESSING' WHERE OrderID = @id;
    FETCH NEXT FROM c INTO @id;
END
CLOSE c; DEALLOCATE c;

-- Cách tư duy tập hợp: một câu lệnh, một plan, một lần ghi log theo batch
UPDATE Sales.Orders
SET Status = 'PROCESSING'
WHERE Status = 'NEW';
```

Cursor không phải luôn sai. Nó hợp lý khi mỗi row cần gọi ra ngoài (procedure không thể set-based, gửi message, thao tác file). Nhưng nó phải là quyết định có ý thức, kèm lý do viết ra được.

Một biến thể quan trọng trong production: khi tập cập nhật quá lớn, viết set-based nhưng **chia batch** để không giữ lock quá lâu và không làm phình log:

```sql
WHILE 1 = 1
BEGIN
    UPDATE TOP (5000) Sales.Orders
    SET Status = 'PROCESSING'
    WHERE Status = 'NEW';

    IF @@ROWCOUNT = 0 BREAK;
    -- Mỗi vòng là một transaction riêng: log truncate được, lock nhả sớm
END
```

---

## 2. CTE – công cụ đọc hiểu, không phải công cụ tối ưu

### 2.1 CTE thường

```sql
WITH CustomerRevenue AS (
    SELECT
        c.CustomerID,
        c.CompanyName,
        COUNT(o.OrderID)              AS OrderCount,
        SUM(o.TotalAmount)            AS TotalRevenue
    FROM Sales.Customers c
    LEFT JOIN Sales.Orders o ON c.CustomerID = o.CustomerID
    GROUP BY c.CustomerID, c.CompanyName
)
SELECT *
FROM CustomerRevenue
WHERE TotalRevenue > 1000000
ORDER BY TotalRevenue DESC;
```

Điều cần hiểu rõ: **CTE không tạo bảng tạm và không được materialize**. Nó là cách đặt tên cho một biểu thức; optimizer inline nó vào plan. Hệ quả trực tiếp:

- CTE được tham chiếu 3 lần → phần thân có thể được thực thi 3 lần.
- CTE không "chặn" optimizer đẩy predicate xuống trong — điều đó thường tốt, nhưng đôi khi làm plan xấu đi ngoài dự đoán.
- Nếu bạn *cần* materialize thật (kết quả tính một lần rồi dùng nhiều lần), dùng `#temp` table — đó là cách duy nhất đảm bảo, và nó còn cho statistics riêng.

| Muốn gì | Dùng gì |
|---|---|
| Chia câu SQL dài cho dễ đọc | CTE |
| Đệ quy trên cấu trúc cây | Recursive CTE |
| Tính một lần, dùng nhiều lần, có statistics | `#temp` table |
| Tập nhỏ, trong một scope, tránh recompile | table variable (biết rõ giới hạn của nó) |

### 2.2 Recursive CTE

```sql
WITH OrgChart AS (
    -- Anchor: các node gốc
    SELECT
        EmployeeID, FullName, ManagerID,
        CAST(FullName AS NVARCHAR(MAX)) AS Path,
        0 AS Depth
    FROM HR.Employees
    WHERE ManagerID IS NULL

    UNION ALL

    -- Recursive: con của những gì đã tìm được
    SELECT
        e.EmployeeID, e.FullName, e.ManagerID,
        CAST(oc.Path + N' > ' + e.FullName AS NVARCHAR(MAX)),
        oc.Depth + 1
    FROM HR.Employees e
    JOIN OrgChart oc ON e.ManagerID = oc.EmployeeID
)
SELECT EmployeeID, FullName, Depth, Path
FROM OrgChart
ORDER BY Path
OPTION (MAXRECURSION 100);   -- mặc định 100; 0 = không giới hạn (nguy hiểm nếu dữ liệu có cycle)
```

Hai rủi ro thực tế của recursive CTE:

1. **Cycle trong dữ liệu** (A quản lý B, B quản lý A) → chạy tới `MAXRECURSION` rồi lỗi. Cách phòng: mang theo `Path` và thêm điều kiện `WHERE oc.Path NOT LIKE '%' + e.FullName + '%'`, hoặc giữ ràng buộc dữ liệu ở tầng ghi.
2. **Plan là nested loop trên anchor** → với cây rộng và sâu, chi phí tăng nhanh. Với cây đọc nhiều/ghi ít, thiết kế **materialized path** hoặc `hierarchyid` thường thắng recursive CTE về hiệu năng đọc.

---

## 3. Window function – phần T-SQL đáng đầu tư nhất

Window function tính giá trị trên một "cửa sổ" các row liên quan mà **không gộp row lại** như `GROUP BY`. Đây là công cụ xóa bỏ phần lớn self-join và cursor trong code báo cáo.

### 3.1 Ba họ hàm

```sql
-- (a) Ranking
SELECT
    OrderID, CustomerID, TotalAmount,
    ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC) AS rn,        -- 1,2,3,4 luôn duy nhất
    RANK()       OVER (PARTITION BY CustomerID ORDER BY TotalAmount DESC) AS rnk,     -- 1,2,2,4 có khoảng trống
    DENSE_RANK() OVER (PARTITION BY CustomerID ORDER BY TotalAmount DESC) AS drnk,    -- 1,2,2,3 không khoảng trống
    NTILE(4)     OVER (ORDER BY TotalAmount DESC) AS Quartile
FROM Sales.Orders;

-- (b) Aggregate window
SELECT
    OrderID, CustomerID, OrderDate, TotalAmount,
    SUM(TotalAmount) OVER (PARTITION BY CustomerID)                      AS CustomerTotal,
    SUM(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotal,
    AVG(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate
                           ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)     AS MovingAvg3,
    COUNT(*)         OVER ()                                             AS TotalRowsInResult
FROM Sales.Orders;

-- (c) Offset / value
SELECT
    CustomerID, OrderDate, TotalAmount,
    LAG(TotalAmount)  OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevAmount,
    LEAD(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextAmount,
    TotalAmount - LAG(TotalAmount, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS DeltaVsPrev,
    FIRST_VALUE(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS FirstEver,
    LAST_VALUE(TotalAmount)  OVER (PARTITION BY CustomerID ORDER BY OrderDate
                                   ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastEver
FROM Sales.Orders;
```

### 3.2 ROWS vs RANGE – cái bẫy phổ biến nhất

Nếu bạn viết `ORDER BY` trong `OVER()` mà **không** viết frame, mặc định là `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Khác biệt:

| Frame | Định nghĩa "cửa sổ" | Hệ quả |
|---|---|---|
| `ROWS` | Theo **số row** vật lý | Nhanh, và các row có giá trị `ORDER BY` bằng nhau vẫn tính riêng |
| `RANGE` | Theo **giá trị** của biểu thức `ORDER BY` | Các row trùng giá trị được gộp làm một "peer group"; hay gây spool tốn kém |

```sql
-- Cùng ý định, hai kết quả khác nhau khi OrderDate có trùng
SUM(Amount) OVER (ORDER BY OrderDate ROWS  BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  -- theo row
SUM(Amount) OVER (ORDER BY OrderDate RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)  -- theo ngày
```

Quy tắc thực dụng: **luôn viết frame ra tường minh**, và mặc định chọn `ROWS` trừ khi bạn thực sự muốn semantics theo giá trị.

`LAST_VALUE` cũng vướng đúng cái bẫy này: không có frame, nó trả về chính row hiện tại — đây là lý do hầu hết ví dụ đúng đều phải viết `ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING`.

### 3.3 `WINDOW` clause (SQL Server 2022+)

Khi nhiều cột dùng chung một định nghĩa window, 2022 cho phép đặt tên nó:

```sql
SELECT
    CustomerID, OrderDate, TotalAmount,
    SUM(TotalAmount) OVER w  AS RunningTotal,
    AVG(TotalAmount) OVER w  AS RunningAvg,
    COUNT(*)         OVER w  AS RunningCount
FROM Sales.Orders
WINDOW w AS (PARTITION BY CustomerID ORDER BY OrderDate
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
```

Đây là cải thiện về tính đọc được, không phải về hiệu năng — nhưng nó loại bỏ nguyên một lớp lỗi copy-paste khi sửa frame ở chỗ này mà quên chỗ kia.

### 3.4 Mẫu dùng thật hay gặp

```sql
-- (1) Lấy bản ghi mới nhất mỗi nhóm (thay cho self-join theo MAX)
WITH Ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC, OrderID DESC) AS rn
    FROM Sales.Orders
)
SELECT * FROM Ranked WHERE rn = 1;

-- (2) Khử trùng lặp có kiểm soát (giữ 1 bản, xóa phần còn lại)
WITH Dupes AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY Email ORDER BY CreatedAt) AS rn
    FROM Sales.Customers
)
DELETE FROM Dupes WHERE rn > 1;      -- DELETE trực tiếp trên CTE là hợp lệ

-- (3) Gộp các khoảng thời gian liền nhau (gaps & islands)
WITH Marked AS (
    SELECT
        DeviceID, StatusValue, ChangedAt,
        CASE WHEN LAG(StatusValue) OVER (PARTITION BY DeviceID ORDER BY ChangedAt) = StatusValue
             THEN 0 ELSE 1 END AS IsNewIsland
    FROM Telemetry.DeviceStatus
),
Grouped AS (
    SELECT *, SUM(IsNewIsland) OVER (PARTITION BY DeviceID ORDER BY ChangedAt
                                     ROWS UNBOUNDED PRECEDING) AS IslandID
    FROM Marked
)
SELECT DeviceID, StatusValue, MIN(ChangedAt) AS FromTime, MAX(ChangedAt) AS ToTime
FROM Grouped
GROUP BY DeviceID, StatusValue, IslandID
ORDER BY DeviceID, FromTime;
```

Mẫu (3) — gaps & islands — là một trong những kỹ thuật giá trị nhất khi làm việc với dữ liệu trạng thái theo thời gian, và gần như không thể viết gọn nếu không có window function.

### 3.5 Index cho window function

Window function có `PARTITION BY a ORDER BY b` sẽ cần dữ liệu sắp theo `(a, b)`. Nếu không có index phù hợp, plan xuất hiện một `Sort` tốn kém (và có thể spill tempdb):

```sql
CREATE INDEX IX_Orders_Customer_Date
    ON Sales.Orders (CustomerID, OrderDate)
    INCLUDE (TotalAmount);
```

Đây là ví dụ rõ nhất cho việc thiết kế index phải xuất phát từ hình dạng query — chủ đề chính của [indexing.md](indexing.md).

---

## 4. APPLY – công cụ bị dùng ít hơn mức nó đáng

`CROSS APPLY` / `OUTER APPLY` cho phép một subquery **tham chiếu tới cột của bảng bên ngoài** — điều `JOIN` không làm được.

```sql
-- Top 3 đơn hàng của mỗi khách (correlated top-N)
SELECT c.CustomerID, c.CompanyName, o.OrderID, o.TotalAmount
FROM Sales.Customers c
CROSS APPLY (
    SELECT TOP 3 OrderID, TotalAmount
    FROM Sales.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY o.TotalAmount DESC
) o;

-- OUTER APPLY: giữ cả khách chưa có đơn (tương tự LEFT JOIN)
SELECT c.CustomerID, last.OrderID, last.OrderDate
FROM Sales.Customers c
OUTER APPLY (
    SELECT TOP 1 OrderID, OrderDate
    FROM Sales.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY o.OrderDate DESC
) last;

-- Gọi table-valued function theo từng row
SELECT o.OrderID, tax.TaxAmount
FROM Sales.Orders o
CROSS APPLY Sales.fn_CalculateTax(o.OrderID) tax;
```

So sánh với `ROW_NUMBER()` cho bài toán top-N mỗi nhóm:

| | `CROSS APPLY TOP (n)` | `ROW_NUMBER() ... WHERE rn <= n` |
|---|---|---|
| Cơ chế | Seek riêng cho từng nhóm | Thường phải scan/sort toàn bộ rồi lọc |
| Thắng khi | Ít nhóm, mỗi nhóm nhiều row, có index trên `(nhóm, sắp xếp)` | Nhiều nhóm, cần scan gần hết bảng dù sao |
| Rủi ro | Nhiều nhóm → nhiều lần seek | Sort lớn, có thể spill |

Không có câu trả lời mặc định; đo `logical reads` của cả hai trên dữ liệu thật.

---

## 5. MERGE và bài toán upsert

```sql
MERGE INTO Inventory.Stock WITH (HOLDLOCK) AS tgt
USING (
    SELECT ProductID, SUM(Quantity) AS Quantity   -- gộp trước: source PHẢI unique theo key
    FROM Staging.IncomingStock
    GROUP BY ProductID
) AS src
ON tgt.ProductID = src.ProductID

WHEN MATCHED AND tgt.Quantity + src.Quantity <= 0 THEN
    DELETE

WHEN MATCHED THEN
    UPDATE SET tgt.Quantity = tgt.Quantity + src.Quantity,
               tgt.UpdatedAt = SYSUTCDATETIME()

WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, Quantity, UpdatedAt)
    VALUES (src.ProductID, src.Quantity, SYSUTCDATETIME())

OUTPUT $action, inserted.ProductID, deleted.Quantity AS OldQty, inserted.Quantity AS NewQty;
```

Ba điều phải biết trước khi đưa `MERGE` vào production:

1. **Source phải unique theo khóa join.** Nếu một `ProductID` xuất hiện 2 lần trong source, `MERGE` báo lỗi 8672 chứ không âm thầm chọn một dòng. Vì vậy luôn gộp/khử trùng trước như ví dụ trên.
2. **`WITH (HOLDLOCK)` không phải trang trí.** Không có nó, `MERGE` có thể gặp race giữa lúc kiểm tra và lúc ghi dưới isolation mặc định, dẫn tới lỗi duplicate key khi có nhiều writer.
3. **`MERGE` có lịch sử bug và phức tạp hơn khi debug.** Với upsert đơn giản một-row từ ứng dụng, cặp `UPDATE ... IF @@ROWCOUNT = 0 INSERT` bọc trong transaction, hoặc `INSERT ... WHERE NOT EXISTS`, thường an toàn và dễ đọc hơn.

Mẫu upsert một-row an toàn, không dùng `MERGE`:

```sql
BEGIN TRAN;
    UPDATE Inventory.Stock WITH (UPDLOCK, SERIALIZABLE)
    SET Quantity = Quantity + @Qty, UpdatedAt = SYSUTCDATETIME()
    WHERE ProductID = @ProductID;

    IF @@ROWCOUNT = 0
        INSERT INTO Inventory.Stock (ProductID, Quantity, UpdatedAt)
        VALUES (@ProductID, @Qty, SYSUTCDATETIME());
COMMIT;
```

`UPDLOCK, SERIALIZABLE` ở đây giữ range lock trên khoảng khóa, đảm bảo hai session không cùng đi vào nhánh `INSERT`.

---

## 6. OUTPUT clause – lấy dữ liệu đã thay đổi ngay tại chỗ

```sql
-- Lấy id vừa sinh cho nhiều row (không dùng SCOPE_IDENTITY vì nó chỉ cho 1 row)
DECLARE @Inserted TABLE (OrderID INT, ClientRef NVARCHAR(50));

INSERT INTO Sales.Orders (CustomerID, OrderDate, TotalAmount, ClientRef)
OUTPUT inserted.OrderID, inserted.ClientRef INTO @Inserted
SELECT CustomerID, SYSUTCDATETIME(), TotalAmount, ClientRef
FROM Staging.NewOrders;

-- Audit thủ công khi cần: chụp cả trước và sau
UPDATE Sales.Orders
SET Status = 'CANCELLED'
OUTPUT deleted.OrderID, deleted.Status AS OldStatus, inserted.Status AS NewStatus,
       SYSUTCDATETIME(), SUSER_SNAME()
INTO Audit.OrderStatusChange (OrderID, OldStatus, NewStatus, ChangedAt, ChangedBy)
WHERE OrderID = @OrderID;

-- Xóa và lấy về cùng lúc: hàng đợi kiểu "claim một batch"
DELETE TOP (100) FROM Queue.Messages
OUTPUT deleted.MessageID, deleted.Payload
WHERE Status = 'READY';
```

`OUTPUT` giúp loại bỏ một round-trip và một cửa sổ race. Với hàng đợi trong SQL Server, mẫu chuẩn hơn nữa là `UPDATE ... WITH (READPAST, ROWLOCK, UPDLOCK) ... OUTPUT` — xem [transactions.md](transactions.md) mục về lock hint.

Lưu ý: `OUTPUT ... INTO` không hoạt động khi bảng đích có trigger hoặc một số ràng buộc foreign key nhất định; khi đó phải dùng bảng tạm trung gian.

---

## 7. Error handling và transaction đúng cách

```sql
SET XACT_ABORT ON;          -- lỗi runtime → transaction bị đánh dấu doomed, tránh trạng thái nửa vời
SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRANSACTION;

        UPDATE Finance.Accounts SET Balance = Balance - @Amount WHERE AccountID = @From;
        IF @@ROWCOUNT <> 1 THROW 50010, 'Source account not found', 1;

        UPDATE Finance.Accounts SET Balance = Balance + @Amount WHERE AccountID = @To;
        IF @@ROWCOUNT <> 1 THROW 50011, 'Target account not found', 1;

        IF EXISTS (SELECT 1 FROM Finance.Accounts WHERE AccountID = @From AND Balance < 0)
            THROW 50012, 'Insufficient balance', 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

    INSERT INTO Ops.ErrorLog (ErrorNumber, Severity, State, ProcName, ErrorLine, Message, LoggedAt)
    VALUES (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(),
            ERROR_PROCEDURE(), ERROR_LINE(), ERROR_MESSAGE(), SYSUTCDATETIME());

    THROW;   -- ném lại nguyên error number/message gốc (2012+); RAISERROR sẽ làm mất thông tin gốc
END CATCH;
```

Bốn điểm mà code T-SQL trong dự án thật hay sai:

| Vấn đề | Vì sao sai | Cách đúng |
|---|---|---|
| `IF @@TRANCOUNT > 0 ROLLBACK` | Không phân biệt được transaction còn commit được hay đã doomed | Dùng `XACT_STATE()`: `1` = committable, `-1` = doomed, `0` = không có |
| Không bật `XACT_ABORT` | Một số lỗi không nhảy vào CATCH và transaction vẫn tiếp tục | `SET XACT_ABORT ON` ở đầu procedure |
| `RAISERROR(@msg, ...)` để ném lại | Mất error number, mất severity gốc, log mất dấu | `THROW;` không tham số |
| Nghĩ `BEGIN TRAN` lồng nhau là nested transaction thật | Chỉ tăng `@@TRANCOUNT`; `ROLLBACK` ở bất kỳ tầng nào rollback tất cả | Thiết kế một điểm bắt đầu transaction, hoặc dùng savepoint có chủ đích |

Savepoint khi thực sự cần rollback từng phần:

```sql
BEGIN TRAN;
    INSERT INTO Sales.Orders (...) VALUES (...);
    SAVE TRANSACTION AfterOrder;

    BEGIN TRY
        INSERT INTO Sales.OrderItems (...) VALUES (...);
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION AfterOrder;   -- chỉ lùi tới savepoint, transaction vẫn mở
    END CATCH;
COMMIT;
```

Cảnh báo: savepoint **không hoạt động** với distributed transaction, và không dùng được nếu `XACT_ABORT ON` khiến transaction thành doomed. Đó là lý do savepoint ít gặp trong code production.

---

## 8. Dynamic SQL an toàn

```sql
-- SAI: nối chuỗi từ input người dùng
EXEC('SELECT * FROM Sales.Orders WHERE CustomerID = ' + @Input);   -- SQL injection

-- ĐÚNG: tham số hóa bằng sp_executesql
DECLARE @sql NVARCHAR(MAX) = N'
    SELECT OrderID, TotalAmount
    FROM Sales.Orders
    WHERE CustomerID = @CustID AND Status = @Status;';

EXEC sys.sp_executesql
     @sql,
     N'@CustID INT, @Status NVARCHAR(20)',
     @CustID = @CustomerID, @Status = @Status;

-- Tên object là biến → QUOTENAME, không bao giờ nối trần
DECLARE @schema SYSNAME = N'Sales', @table SYSNAME = N'Orders';
SET @sql = N'SELECT COUNT(*) FROM ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N';';
EXEC sys.sp_executesql @sql;
```

Hai lý do dùng `sp_executesql` thay vì `EXEC(@sql)`, ngoài an toàn:

1. Query tham số hóa → **plan được tái sử dụng** thay vì mỗi giá trị một plan, tránh làm phình plan cache.
2. Tham số có kiểu rõ ràng → không có implicit conversion bất ngờ phá index seek.

### 8.1 Mẫu "optional parameter" — nơi dynamic SQL thắng rõ

```sql
-- Cách viết catch-all quen thuộc, nhưng plan thường tệ
SELECT * FROM Sales.Orders
WHERE (@CustomerID IS NULL OR CustomerID = @CustomerID)
  AND (@Status     IS NULL OR Status     = @Status)
  AND (@FromDate   IS NULL OR OrderDate >= @FromDate);
-- Một plan phải phục vụ mọi tổ hợp điều kiện → hầu như luôn chọn scan.
-- Cách chữa nhanh: OPTION (RECOMPILE), đổi CPU compile lấy plan đúng cho từng lần chạy.

-- Cách bền hơn: sinh đúng WHERE cần thiết, vẫn tham số hóa
DECLARE @sql NVARCHAR(MAX) = N'SELECT OrderID, CustomerID, Status, OrderDate, TotalAmount
                               FROM Sales.Orders WHERE 1 = 1';
IF @CustomerID IS NOT NULL SET @sql += N' AND CustomerID = @CustomerID';
IF @Status     IS NOT NULL SET @sql += N' AND Status     = @Status';
IF @FromDate   IS NOT NULL SET @sql += N' AND OrderDate >= @FromDate';

EXEC sys.sp_executesql @sql,
     N'@CustomerID INT, @Status NVARCHAR(20), @FromDate DATE',
     @CustomerID, @Status, @FromDate;
```

SQL Server 2022 giảm bớt vấn đề này bằng **Parameter Sensitive Plan optimization** cho một số hình dạng query, và SQL Server 2025 mở rộng thêm — nhưng cả hai không thay thế được việc viết query có hình dạng rõ ràng. Chi tiết ở [query_optimization.md](../performance/query_optimization.md).

---

## 9. Temporal table – lịch sử tự động

```sql
CREATE TABLE Catalog.Products (
    ProductID   INT           NOT NULL PRIMARY KEY,
    Name        NVARCHAR(100) NOT NULL,
    Price       DECIMAL(19,4) NOT NULL,
    ValidFrom   DATETIME2(3) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    ValidTo     DATETIME2(3) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (
    HISTORY_TABLE = Catalog.ProductsHistory,
    HISTORY_RETENTION_PERIOD = 3 YEARS      -- SQL Server 2017+: engine tự dọn
));
```

Truy vấn lịch sử:

```sql
SELECT * FROM Catalog.Products FOR SYSTEM_TIME AS OF '2026-03-01T10:00:00';
SELECT * FROM Catalog.Products FOR SYSTEM_TIME BETWEEN '2026-01-01' AND '2026-07-01' WHERE ProductID = 1;
SELECT * FROM Catalog.Products FOR SYSTEM_TIME ALL WHERE ProductID = 1 ORDER BY ValidFrom;
```

Những gì cần biết trước khi bật trên bảng lớn:

- Thời gian ghi nhận là **UTC theo thời điểm transaction bắt đầu**, không phải theo từng statement. Nhiều `UPDATE` trong cùng transaction có cùng `ValidFrom`.
- `HIDDEN` giúp `SELECT *` của ứng dụng cũ không bị thêm cột — rất hữu ích khi retrofit.
- History table nên có **clustered columnstore index** nếu chỉ dùng để phân tích/audit: nén tốt hơn nhiều và truy vấn theo dải thời gian nhanh hơn.
- Muốn dọn history thủ công thì phải tắt versioning trước — nhưng khi đã có `HISTORY_RETENTION_PERIOD`, hầu như không cần:

```sql
ALTER TABLE Catalog.Products SET (SYSTEM_VERSIONING = OFF);
DELETE FROM Catalog.ProductsHistory WHERE ValidTo < DATEADD(YEAR, -3, SYSUTCDATETIME());
ALTER TABLE Catalog.Products SET (SYSTEM_VERSIONING = ON (HISTORY_TABLE = Catalog.ProductsHistory));
```

Temporal table trả lời "dữ liệu trông như thế nào lúc đó". Nó **không** trả lời "ai đã đổi và vì sao" — cho câu hỏi đó cần audit hoặc `OUTPUT` vào bảng audit riêng (xem [security.md](../administration/security.md)).

Bảng đối chiếu với các cơ chế theo dõi thay đổi khác:

| Cơ chế | Trả lời câu hỏi | Xem thêm |
|---|---|---|
| Temporal table | Trạng thái tại một thời điểm | mục này |
| Change Tracking | Row nào đã đổi từ version X (không có giá trị cũ) | [data_movement.md](../integration/data_movement.md) |
| CDC | Thay đổi nào, giá trị trước/sau, theo thứ tự | [data_movement.md](../integration/data_movement.md) |
| SQL Server Audit | Ai làm gì, khi nào | [security.md](../administration/security.md) |
| Ledger table (2022+) | Bằng chứng chống sửa lịch sử (cryptographic) | [security.md](../administration/security.md) |

---

## 10. JSON trong T-SQL

### 10.1 Nền tảng (2016+)

```sql
DECLARE @json NVARCHAR(MAX) = N'{
  "orderNo":"SO-1001",
  "customer":{"id":42,"name":"Công ty A"},
  "lines":[{"sku":"P-1","qty":2},{"sku":"P-2","qty":5}]
}';

SELECT JSON_VALUE(@json, '$.orderNo')            AS OrderNo;      -- scalar
SELECT JSON_VALUE(@json, '$.customer.name')      AS CustomerName;
SELECT JSON_QUERY(@json, '$.lines')              AS LinesJson;    -- object/array
SELECT JSON_PATH_EXISTS(@json, '$.customer.vat') AS HasVat;       -- 2022+

-- Mở array thành rowset
SELECT sku, qty
FROM OPENJSON(@json, '$.lines')
WITH (sku NVARCHAR(50) '$.sku', qty INT '$.qty');

-- Xuất kết quả query thành JSON
SELECT o.OrderID AS [order.id], o.TotalAmount AS [order.amount],
       c.CompanyName AS [customer.name]
FROM Sales.Orders o JOIN Sales.Customers c ON o.CustomerID = c.CustomerID
WHERE o.OrderID = @OrderID
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

-- Dựng JSON theo cấu trúc (2022+)
SELECT JSON_OBJECT(
    'orderNo': o.OrderNo,
    'lines':   JSON_QUERY((SELECT sku, qty FROM Sales.OrderItems
                           WHERE OrderID = o.OrderID FOR JSON PATH))
)
FROM Sales.Orders o WHERE o.OrderID = @OrderID;
```

### 10.2 Lưu JSON trong cột: `nvarchar(max)` hay kiểu `json`?

Trước SQL Server 2025, JSON được lưu như `nvarchar(max)` kèm `CHECK (ISJSON(col) = 1)`, và để index thì tạo computed column:

```sql
CREATE TABLE Events.Store (
    EventID   BIGINT IDENTITY PRIMARY KEY,
    EventType NVARCHAR(50)   NOT NULL,
    Payload   NVARCHAR(MAX)  NOT NULL CHECK (ISJSON(Payload) = 1),
    CreatedAt DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME()
);

-- Index trên một thuộc tính JSON: computed column persisted + index thường
ALTER TABLE Events.Store
  ADD UserID AS CAST(JSON_VALUE(Payload, '$.userId') AS INT) PERSISTED;
CREATE INDEX IX_Events_UserID ON Events.Store (UserID) INCLUDE (EventType, CreatedAt);
```

SQL Server 2025 bổ sung **kiểu dữ liệu `json` gốc** (lưu dạng nhị phân đã parse) cùng **JSON index**, thay đổi hẳn cách làm này. Chi tiết và điều kiện áp dụng ở [sqlserver_2025.md](../modern/sqlserver_2025.md).

Nguyên tắc thiết kế không đổi theo version: **field nào được lọc/sắp xếp/join thường xuyên thì tách ra thành cột thật**. JSON tốt cho phần payload thay đổi hình dạng liên tục, không tốt khi trở thành trục truy vấn chính.

---

## 11. Hàm T-SQL hiện đại theo version

| Hàm / cú pháp | Từ version | Dùng để |
|---|---|---|
| `STRING_SPLIT(s, sep)` | 2016 | Tách chuỗi thành rowset |
| `STRING_SPLIT(s, sep, 1)` với cột `ordinal` | 2022 | Tách **và giữ thứ tự** |
| `STRING_AGG(x, sep) WITHIN GROUP (ORDER BY ...)` | 2017 | Gộp chuỗi có sắp xếp |
| `TRIM([chars FROM] s)` | 2017 / mở rộng 2022 | Cắt khoảng trắng hoặc ký tự chỉ định |
| `CONCAT_WS(sep, ...)` | 2017 | Nối chuỗi bỏ qua NULL |
| `GREATEST(...)` / `LEAST(...)` | 2022 | Max/min theo hàng, không cần CASE |
| `DATETRUNC(part, date)` | 2022 | Cắt về đầu tháng/tuần/giờ (SARGable hơn `CONVERT`) |
| `DATE_BUCKET(part, n, date)` | 2022 | Gom mốc thời gian theo bucket cố định |
| `GENERATE_SERIES(a, b, step)` | 2022 | Sinh dải số / dải thời gian không cần bảng tally |
| `IS [NOT] DISTINCT FROM` | 2022 | So sánh có NULL an toàn |
| `WINDOW` clause | 2022 | Đặt tên window dùng lại |
| `APPROX_PERCENTILE_CONT/DISC` | 2022 | Percentile xấp xỉ, nhanh trên dữ liệu lớn |
| `JSON_OBJECT` / `JSON_ARRAY` / `JSON_PATH_EXISTS` | 2022 | Dựng và kiểm tra JSON |
| Bit functions (`LEFT_SHIFT`, `BIT_COUNT`, ...) | 2022 | Xử lý bitmask |
| `REGEXP_LIKE` / `REGEXP_REPLACE` / `REGEXP_SUBSTR` ... | 2025 | Regex gốc trong T-SQL |
| Kiểu `json`, JSON index, `JSON_CONTAINS` | 2025 | JSON gốc, index được |
| Kiểu `vector`, `VECTOR_DISTANCE` | 2025 | Vector search / RAG |

Ví dụ vài hàm 2022 giải quyết đúng vấn đề cũ:

```sql
-- Trước 2022: nhóm theo tháng nhưng làm mất khả năng seek
SELECT CONVERT(CHAR(7), OrderDate, 126) AS Ym, SUM(TotalAmount) FROM Sales.Orders GROUP BY CONVERT(CHAR(7), OrderDate, 126);

-- 2022: rõ ràng hơn, và dùng được cho cả filter dạng khoảng
SELECT DATETRUNC(MONTH, OrderDate) AS MonthStart, SUM(TotalAmount)
FROM Sales.Orders
GROUP BY DATETRUNC(MONTH, OrderDate);

-- Sinh dải ngày không cần bảng tally
SELECT DATEADD(DAY, value, '2026-01-01') AS D
FROM GENERATE_SERIES(0, DATEDIFF(DAY, '2026-01-01', '2026-01-31'));

-- So sánh an toàn với NULL (thay cho ISNULL hai vế)
SELECT * FROM Staging.Customers s
JOIN Sales.Customers t ON t.CustomerID = s.CustomerID
WHERE s.Email IS DISTINCT FROM t.Email;   -- khác nhau, kể cả khi một bên NULL
```

Cảnh báo về `DATETRUNC` và họ hàng: dùng trong `SELECT`/`GROUP BY` thì tốt, nhưng đặt **quanh cột trong `WHERE`** vẫn phá index seek. Filter luôn nên viết dạng khoảng nửa mở: `WHERE OrderDate >= @from AND OrderDate < @toExclusive`.

---

## 12. Trade-offs

| Lựa chọn | Được | Mất | Khi nào chọn |
|---|---|---|---|
| CTE | Dễ đọc, hỗ trợ đệ quy | Không materialize, có thể chạy nhiều lần | Chia nhỏ query phức tạp |
| `#temp` table | Có statistics, materialize thật | Ghi tempdb, có thể gây recompile | Kết quả trung gian lớn, dùng nhiều lần |
| Table variable | Ít recompile, phạm vi rõ | Estimate kém (2019+ có deferred compilation giúp phần nào), không statistics đầy đủ | Tập rất nhỏ, biết trước |
| `MERGE` | Một statement, `$action` gọn | Yêu cầu source unique, cần HOLDLOCK, khó debug | Batch load từ staging đã được gộp |
| `UPDATE`+`INSERT` | Đơn giản, dễ suy luận | Nhiều statement | Upsert một-row từ ứng dụng |
| Dynamic SQL | Plan đúng cho từng hình dạng query | Khó đọc, dễ mở lỗ injection nếu cẩu thả | Optional parameter, tên object động |
| `OPTION (RECOMPILE)` | Plan luôn khớp tham số hiện tại | CPU compile mỗi lần, không tích lũy trong plan cache | Query chạy không quá thường xuyên nhưng rất lệch theo tham số |
| Temporal table | Lịch sử tự động, không sửa ứng dụng | Bảng history phình, chi phí ghi thêm | Cần audit trạng thái theo thời gian |
| JSON trong cột | Schema linh hoạt | Query/index kém hơn cột thật | Payload đa dạng, không phải trục truy vấn |

---

## 13. Anti-pattern T-SQL và cách sửa

```sql
-- 1. Hàm bọc quanh cột trong WHERE (mất khả năng seek)
WHERE YEAR(OrderDate) = 2026                                  -- ✗
WHERE OrderDate >= '2026-01-01' AND OrderDate < '2027-01-01'   -- ✓

-- 2. Implicit conversion do lệch kiểu
WHERE CustomerID = '100'          -- ✗ CustomerID là INT; hoặc ngược lại NVARCHAR vs VARCHAR
WHERE CustomerID = 100            -- ✓ đúng kiểu ngay từ tham số

-- 3. NOT IN với subquery có NULL → trả về rỗng một cách lặng lẽ
WHERE CustomerID NOT IN (SELECT CustomerID FROM Sales.Orders)                        -- ✗
WHERE NOT EXISTS (SELECT 1 FROM Sales.Orders o WHERE o.CustomerID = c.CustomerID)    -- ✓

-- 4. SELECT * trong view/procedure production
--    → thay đổi schema làm đổi contract, và ngăn covering index phát huy tác dụng

-- 5. Scalar UDF gọi trong SELECT/WHERE
--    Trước 2019: gọi từng row, không song song hóa được, không hiện trong plan.
--    2019+: scalar UDF inlining giúp nhiều ca, nhưng không phải mọi ca (kiểm tra
--    sys.sql_modules.is_inlineable). An toàn nhất: viết lại thành inline TVF.
SELECT o.OrderID, t.TaxAmount
FROM Sales.Orders o CROSS APPLY Sales.fn_CalculateTax_Inline(o.OrderID) t;   -- ✓

-- 6. Multi-statement TVF làm hộp đen cho optimizer
--    Estimate cố định (1 hoặc 100 row) → plan sai hình dạng. Ưu tiên inline TVF.

-- 7. OR giữa các cột khác nhau
WHERE CustomerID = 5 OR OrderDate = '2026-01-15'              -- ✗ thường thành scan
-- ✓ tách rồi hợp, mỗi nhánh seek được index riêng
SELECT ... WHERE CustomerID = 5
UNION
SELECT ... WHERE OrderDate = '2026-01-15';

-- 8. Nhầm precision khi chia số nguyên
SELECT 1/3;                        -- ✗ = 0
SELECT 1.0/3;                      -- ✓ = 0.333333
SELECT CAST(a AS DECIMAL(19,4))/b; -- ✓ tường minh
```

---

## 14. Compare – T-SQL vs PL/pgSQL vs PL/SQL

| Chủ đề | T-SQL | PL/pgSQL (PostgreSQL) | PL/SQL (Oracle) |
|---|---|---|---|
| Upsert | `MERGE`, hoặc UPDATE/INSERT | `INSERT ... ON CONFLICT` | `MERGE` |
| Error handling | `TRY/CATCH` + `THROW` | `EXCEPTION WHEN` | `EXCEPTION WHEN` |
| Chuỗi kết quả trả về | Result set trả trực tiếp | Thường cần `REFCURSOR` / `RETURNS TABLE` | `SYS_REFCURSOR` |
| Biến bảng tạm | `#temp`, `@table` | `CREATE TEMP TABLE` | Global temporary table |
| Pivot | `PIVOT` (cú pháp riêng) | `crosstab` (extension) | `PIVOT` |
| Temporal | System-versioned table (SQL:2011) | Extension / trigger | Flashback Query |
| JSON | `JSON_VALUE`/`OPENJSON`; kiểu `json` từ 2025 | `json`/`jsonb` gốc, rất mạnh | `JSON` type |
| Regex | Từ 2025 (`REGEXP_*`) | `~`, `regexp_*` từ lâu | `REGEXP_*` từ lâu |
| Chuỗi nối | `+`, `CONCAT` | `||`, `concat` | `||` |

Điểm dễ vấp khi port code: `+` của T-SQL trả `NULL` nếu một toán hạng `NULL`, còn `CONCAT` thì coi `NULL` là chuỗi rỗng. Và `||` không tồn tại trong T-SQL.

---

## 15. Ghi chú – chủ đề tiếp theo

- [indexing.md](indexing.md): thiết kế index từ query shape, columnstore, statistics, đọc plan.
- [transactions.md](transactions.md): isolation level, lock hint, deadlock, retry.
- [query_optimization.md](../performance/query_optimization.md): parameter sniffing, Query Store, plan forcing, IQP.
- [sqlserver_2025.md](../modern/sqlserver_2025.md): kiểu `json`, `REGEXP_*`, `vector`, Optimized Locking.
- [jdbc_java.md](../integration/jdbc_java.md): các mẫu T-SQL này gọi từ Java/Spring Boot thế nào.

Từ khóa mở rộng: `hierarchyid`, `sequence` vs `IDENTITY`, `sp_prepare`, `PIVOT`/`UNPIVOT` động, `TRY_CONVERT`, `AT TIME ZONE`, `sys.dm_exec_describe_first_result_set`.

---

*Cập nhật lần cuối: 2026-07-30*
