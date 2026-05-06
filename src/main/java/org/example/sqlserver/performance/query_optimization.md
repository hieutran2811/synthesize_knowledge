# SQL Server Query Optimization – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Query Optimization là gì?

**Query Optimization** là quá trình đảm bảo SQL Server chọn **execution plan tối ưu nhất** cho query. Bao gồm: hiểu query optimizer, xử lý parameter sniffing, dùng Query Store, In-Memory OLTP, và các advanced tuning techniques.

---

## How – Parameter Sniffing

```sql
-- Parameter sniffing: optimizer compile plan dựa trên giá trị tham số lần đầu tiên
-- Plan tốt cho value đầu → có thể tệ cho value khác (skewed data)

-- Ví dụ:
CREATE PROCEDURE GetOrders @CustomerID INT AS
    SELECT * FROM Orders WHERE CustomerID = @CustomerID;
-- Lần đầu: @CustomerID = 1 (1 million orders) → plan: full scan
-- Lần sau: @CustomerID = 999 (5 orders) → dùng lại plan full scan → tệ!

-- Giải pháp 1: OPTION (RECOMPILE) - tạo plan mỗi lần
CREATE PROCEDURE GetOrders @CustomerID INT AS
    SELECT * FROM Orders WHERE CustomerID = @CustomerID
    OPTION (RECOMPILE);  -- compile fresh mỗi lần, tốn CPU

-- Giải pháp 2: OPTIMIZE FOR - compile cho value cụ thể
SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION (OPTIMIZE FOR (@CustomerID = 500));  -- giá trị representative

SELECT * FROM Orders WHERE CustomerID = @CustomerID
OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));  -- dùng average stats

-- Giải pháp 3: Tách stored procedure theo data segment
IF @CustomerID IN (SELECT TOP 10 CustomerID FROM LargeCustomers)
    EXEC GetOrdersLargeCustomer @CustomerID;
ELSE
    EXEC GetOrdersSmallCustomer @CustomerID;

-- Giải pháp 4: Local variables (prevent sniffing - dùng avg stats)
DECLARE @LocalCustID INT = @CustomerID;
SELECT * FROM Orders WHERE CustomerID = @LocalCustID;
-- Tệ hơn OPTION UNKNOWN vì luôn dùng avg stats (có thể không phù hợp)

-- Phát hiện parameter sniffing
SELECT
    qs.execution_count,
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_ms,
    qs.min_elapsed_time, qs.max_elapsed_time,
    SUBSTRING(st.text, 1, 200) AS QueryText,
    qp.query_plan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qs.max_elapsed_time > 10 * qs.min_elapsed_time  -- max >> min → sniffing suspect
ORDER BY qs.max_elapsed_time DESC;
```

---

## How – Query Store (SQL 2016+)

```sql
-- Query Store: track query plans + performance over time
-- "Flight recorder" cho queries

-- Enable Query Store
ALTER DATABASE SalesDB SET QUERY_STORE = ON;
ALTER DATABASE SalesDB SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO   -- AUTO: chỉ capture significant queries
);

-- Tìm regressed queries (plan thay đổi → performance tệ hơn)
SELECT TOP 10
    qsq.query_id,
    qsq.object_id,
    OBJECT_NAME(qsq.object_id) AS ProcName,
    SUBSTRING(qsqt.query_sql_text, 1, 200) AS QueryText,
    qsrs.avg_duration / 1000.0 AS AvgDurationMS,
    qsp.plan_id
FROM sys.query_store_query qsq
JOIN sys.query_store_query_text qsqt ON qsq.query_text_id = qsqt.query_text_id
JOIN sys.query_store_plan qsp ON qsq.query_id = qsp.query_id
JOIN sys.query_store_runtime_stats qsrs ON qsp.plan_id = qsrs.plan_id
JOIN sys.query_store_runtime_stats_interval qsrsi ON qsrs.runtime_stats_interval_id = qsrsi.runtime_stats_interval_id
WHERE qsrsi.start_time > DATEADD(HOUR, -24, GETDATE())
ORDER BY qsrs.avg_duration DESC;

-- Force a specific plan (khi regression xảy ra)
EXEC sp_query_store_force_plan @query_id = 42, @plan_id = 1;

-- Unforce plan
EXEC sp_query_store_unforce_plan @query_id = 42, @plan_id = 1;

-- SSMS: Query Store → Regressed Queries → Force Plan

-- Automatic Plan Correction (SQL 2017+)
ALTER DATABASE SalesDB SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);
-- Tự động force last good plan khi regression detected
```

---

## How – Plan Hints & Forcing

```sql
-- INDEX hints
SELECT * FROM Orders WITH (INDEX(IX_Orders_CustomerDate))
WHERE CustomerID = 5;

SELECT * FROM Orders WITH (INDEX(0))  -- force heap scan (no index)
WHERE CustomerID = 5;

SELECT * FROM Orders WITH (INDEX(1))  -- force clustered index scan
WHERE CustomerID = 5;

-- JOIN hints
SELECT *
FROM Orders o
INNER HASH JOIN OrderItems oi ON o.OrderID = oi.OrderID;  -- force hash join

INNER LOOP JOIN   -- force nested loop
INNER MERGE JOIN  -- force merge join

-- QUERY hints
SELECT * FROM Orders WHERE CustomerID = 5
OPTION (
    MAXDOP 1,                     -- single thread
    RECOMPILE,                    -- fresh plan each time
    FAST 10,                      -- optimize for first 10 rows (OLTP)
    FORCE ORDER,                  -- join in FROM clause order
    EXPAND VIEWS,                 -- expand indexed views
    USE HINT('ENABLE_PARALLEL_PLAN_PREFERENCE'),
    USE HINT('DISABLE_BATCH_MODE_ADAPTIVE_JOINS'),
    OPTIMIZE FOR UNKNOWN,
    MIN_GRANT_PERCENT = 5,        -- minimum memory grant
    MAX_GRANT_PERCENT = 50        -- maximum memory grant
);

-- Plan Guide (force plan cho query không thể modify - 3rd party)
EXEC sp_create_plan_guide
    @name = N'PG_GetOrders',
    @stmt = N'SELECT * FROM Orders WHERE CustomerID = @CustomerID',
    @type = N'SQL',
    @module_or_batch = NULL,
    @params = N'@CustomerID INT',
    @hints = N'OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN))';

-- Xem plan guides
SELECT * FROM sys.plan_guides;

-- Validate
EXEC sp_control_plan_guide N'VALIDATE', N'PG_GetOrders';
```

---

## How – In-Memory OLTP (Hekaton)

```sql
-- In-Memory OLTP: lock-free, latch-free data structures
-- 10-30x faster cho OLTP workloads
-- Yêu cầu: SQL Server 2014+ Enterprise / Standard (giới hạn)

-- 1. Enable Memory-Optimized filegroup
ALTER DATABASE SalesDB ADD FILEGROUP MemOptFG CONTAINS MEMORY_OPTIMIZED_DATA;
ALTER DATABASE SalesDB ADD FILE (
    NAME = 'SalesDB_MemOpt',
    FILENAME = 'C:\Data\SalesDB_MemOpt'
) TO FILEGROUP MemOptFG;

-- 2. Tạo Memory-Optimized table
CREATE TABLE dbo.SessionCache (
    SessionID   UNIQUEIDENTIFIER NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1000000),
    UserID      INT NOT NULL,
    Data        NVARCHAR(MAX),
    ExpiresAt   DATETIME2 NOT NULL,
    INDEX IX_SessionCache_Expiry NONCLUSTERED (ExpiresAt)
) WITH (
    MEMORY_OPTIMIZED = ON,
    DURABILITY = SCHEMA_AND_DATA  -- hoặc SCHEMA_ONLY (no recovery)
);

-- Memory-Optimized table types:
-- DURABILITY = SCHEMA_AND_DATA:  dữ liệu survive restart (checkpoint)
-- DURABILITY = SCHEMA_ONLY:     dữ liệu mất khi restart (temp tables use case)

-- 3. Natively Compiled Stored Procedures
CREATE PROCEDURE dbo.GetSession
    @SessionID UNIQUEIDENTIFIER
WITH
    NATIVE_COMPILATION,  -- compile to machine code
    SCHEMABINDING,
    EXECUTE AS OWNER
AS
BEGIN ATOMIC WITH (
    TRANSACTION ISOLATION LEVEL = SNAPSHOT,
    LANGUAGE = N'us_english'
)
    SELECT UserID, Data, ExpiresAt
    FROM dbo.SessionCache
    WHERE SessionID = @SessionID
      AND ExpiresAt > SYSUTCDATETIME();
END;

-- Giới hạn In-Memory:
-- Không support: ALTER TABLE, foreign keys (cross-table), IDENTITY với replication
-- Không support: TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
-- Index types: HASH (point lookup) hoặc RANGE (range/sort)
-- HASH bucket_count: set ~= expected unique values (power of 2)
```

---

## How – Batch Mode Processing

```sql
-- Batch mode: xử lý 900 rows/batch (vs row mode 1 row/time)
-- Enabled: columnstore index hoặc SQL 2019 Batch Mode on Rowstore

-- SQL 2019: Batch Mode on Rowstore (không cần columnstore)
-- Tự động khi adaptive threshold hit (khối lượng data đủ lớn)

-- Kiểm tra batch vs row mode trong execution plan
-- <RunTimeInformation ActualExecutionMode="Batch" ...>

-- Adaptive Query Processing (SQL 2017+):
-- 1. Adaptive Joins: optimizer chọn Hash Join hoặc Nested Loop lúc run-time
-- 2. Memory Grant Feedback: điều chỉnh memory grant sau execution
-- 3. Interleaved Execution: multi-statement TVF statistics

-- Xem memory grant adjustments
SELECT
    qp.query_id,
    SUBSTRING(qt.query_sql_text, 1, 100) AS QueryText,
    qp.avg_query_max_used_memory / 128 AS AvgMemGrantMB,
    qp.last_query_max_used_memory / 128 AS LastMemGrantMB
FROM sys.query_store_plan qp
JOIN sys.query_store_query_text qt ON qp.query_text_id = qt.query_text_id
WHERE qp.avg_query_max_used_memory > 1000  -- > 8MB
ORDER BY qp.avg_query_max_used_memory DESC;
```

---

## How – Statistics & Cardinality Estimation

```sql
-- CE (Cardinality Estimation) version control
-- SQL 2014+: new CE (model = 120, 130, 140, 150, 160)
-- Backwards compat: dùng CE 70 cho old apps

ALTER DATABASE SalesDB SET COMPATIBILITY_LEVEL = 160;  -- SQL 2022

-- Force old CE for specific query
SELECT * FROM Orders WHERE CustomerID = 5
OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

-- Force new CE
OPTION (USE HINT('ENABLE_QUERY_OPTIMIZER_HOTFIXES'));

-- Create statistics manually
CREATE STATISTICS stat_Orders_Amount ON Orders(Amount)
WITH FULLSCAN, NORECOMPUTE;

-- Update statistics with sampling
UPDATE STATISTICS Orders WITH SAMPLE 30 PERCENT;

-- Column-level statistics
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatName,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    CAST(100.0 * sp.rows_sampled / NULLIF(sp.rows, 0) AS DECIMAL(5,2)) AS SamplePct,
    sp.steps AS HistogramSteps,
    sp.modification_counter
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('Orders')
ORDER BY sp.modification_counter DESC;
```

---

## How – Common Query Anti-patterns

```sql
-- 1. SELECT * (lấy nhiều data hơn cần)
SELECT * FROM Orders;             -- BAD: lấy tất cả columns
SELECT OrderID, Amount FROM Orders; -- GOOD: chỉ lấy cần

-- 2. NOLOCK abuse
SELECT * FROM Orders WITH (NOLOCK); -- đọc dirty data, bị page splits
-- Dùng RCSI thay thế

-- 3. Functions trên columns trong WHERE (non-SARGable)
SELECT * FROM Orders WHERE CONVERT(DATE, CreatedAt) = '2026-01-15';  -- BAD
SELECT * FROM Orders WHERE CreatedAt >= '2026-01-15' AND CreatedAt < '2026-01-16'; -- GOOD

-- 4. Implicit conversion
SELECT * FROM Orders WHERE CustomerID = '100';  -- CustomerID là INT
-- → implicit CONVERT(INT, '100') → index cannot be used on string side

-- 5. OR conditions (thường prevent index seek)
SELECT * FROM Orders WHERE CustomerID = 5 OR OrderDate = '2026-01-15';
-- Better: UNION ALL
SELECT * FROM Orders WHERE CustomerID = 5
UNION ALL
SELECT * FROM Orders WHERE OrderDate = '2026-01-15' AND CustomerID <> 5;

-- 6. NOT IN với NULLs
SELECT * FROM Customers WHERE CustomerID NOT IN (SELECT CustomerID FROM Orders);
-- Nếu Orders.CustomerID có NULL → kết quả rỗng!
-- Better: NOT EXISTS hoặc LEFT JOIN WHERE Orders.CustomerID IS NULL
SELECT c.* FROM Customers c
WHERE NOT EXISTS (SELECT 1 FROM Orders o WHERE o.CustomerID = c.CustomerID);

-- 7. CURSOR thay set-based operations
-- CURSOR: O(n) operations
-- Set-based: tận dụng optimizer

-- 8. Table-Valued Functions trong WHERE (blocking optimization)
SELECT * FROM Orders o
WHERE dbo.GetCustomerTier(o.CustomerID) = 'Gold';  -- TVF called per row
-- Inline TVF: ok (expanded by optimizer)
-- Multi-statement TVF: black box cho optimizer (row count estimate = 1 or 100)
```

---

## Real-world – Query Performance Checklist

```sql
-- Tìm top expensive queries (by CPU)
SELECT TOP 20
    qs.total_worker_time / qs.execution_count AS avg_cpu_us,
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_us,
    qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        (CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
         ELSE qs.statement_end_offset END - qs.statement_start_offset)/2+1) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY avg_cpu_us DESC;

-- Tìm queries dùng nhiều disk reads
SELECT TOP 10
    total_logical_reads / execution_count AS avg_reads,
    execution_count,
    SUBSTRING(st.text, 1, 200) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY avg_reads DESC;

-- Kiểm tra recompilations
SELECT
    object_name,
    recompile_cause,
    COUNT(*) AS RecompileCount
FROM sys.dm_exec_procedure_stats ps
CROSS APPLY sys.dm_exec_sql_text(ps.plan_handle) st
-- Trace: SQL:StmtRecompile events
GROUP BY object_name, recompile_cause;
```

---

## Ghi chú – Chủ đề tiếp theo
> `administration/backup_recovery.md`: Backup types, Recovery Models, RESTORE, Point-in-time recovery, Backup compression, Ola Hallengren

---

*Cập nhật lần cuối: 2026-05-06*
