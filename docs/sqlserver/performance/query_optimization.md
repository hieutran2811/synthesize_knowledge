---
title: "SQL Server Query Optimization"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 0
---
# SQL Server Query Optimization

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Các tính năng Intelligent Query Processing được ghi rõ version và compatibility level yêu cầu.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Indexing](../fundamentals/indexing.md), [Transactions](../fundamentals/transactions.md). Đọc tiếp: [Monitoring & Troubleshooting](monitoring_troubleshooting.md).

---

## 1. Tuning là quản lý plan, không phải viết lại SQL cho đẹp

Sau khi index đã hợp lý ([indexing.md](../fundamentals/indexing.md)), phần lớn sự cố hiệu năng còn lại không phải "query viết dở" mà là **plan không khớp với dữ liệu hiện tại**. Ba nguồn chính:

| Nguồn | Biểu hiện điển hình |
|---|---|
| Plan được cache cho tham số khác | Cùng procedure, tham số này nhanh, tham số kia chậm hàng trăm lần |
| Cardinality estimate sai | Plan chọn nested loop cho 2 triệu row, hoặc hash spill xuống tempdb |
| Plan thay đổi sau khi thống kê/version đổi | "Hôm qua chạy 2 giây, hôm nay 3 phút, không ai deploy gì" |

Vì vậy công cụ trung tâm của chương này là **Query Store** (nhìn được plan nào chạy khi nào, nhanh hay chậm) và các cơ chế can thiệp vào plan.

---

## 2. Plan cache và tái sử dụng plan

### 2.1 Query hash và plan reuse

```sql
-- Xem plan cache: cái gì đang chiếm chỗ
SELECT
    cp.objtype,                         -- Proc / Adhoc / Prepared / Trigger
    COUNT(*)                            AS PlanCount,
    SUM(cp.size_in_bytes) / 1024 / 1024 AS SizeMB,
    SUM(cp.usecounts)                   AS TotalUse
FROM sys.dm_exec_cached_plans cp
GROUP BY cp.objtype
ORDER BY SizeMB DESC;

-- Plan chỉ dùng 1 lần (single-use ad-hoc) — dấu hiệu SQL không tham số hóa
SELECT COUNT(*) AS SingleUsePlans,
       SUM(size_in_bytes) / 1024 / 1024 AS WastedMB
FROM sys.dm_exec_cached_plans
WHERE usecounts = 1 AND objtype = 'Adhoc';
```

Nếu `WastedMB` lớn (hàng GB trên hệ có nhiều ad-hoc SQL), plan cache đang lấy RAM của buffer pool. Hai biện pháp:

```sql
EXEC sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE;  -- lưu stub thay vì plan đầy đủ lần đầu
ALTER DATABASE SalesDB SET PARAMETERIZATION FORCED;                 -- cẩn thận: có thể gây sniffing mới
```

`PARAMETERIZATION FORCED` là con dao hai lưỡi: nó giảm số plan nhưng biến literal thành tham số, kéo theo đúng vấn đề parameter sniffing ở mục 3. Biện pháp bền vững vẫn là **ứng dụng tham số hóa query** — với JDBC nghĩa là `PreparedStatement` với `?`, không nối chuỗi ([jdbc_java.md](../integration/jdbc_java.md)).

### 2.2 Nguyên nhân recompile

```sql
-- Query bị recompile nhiều
SELECT TOP 20
    OBJECT_NAME(ps.object_id) AS ProcName,
    ps.execution_count, ps.plan_generation_num,
    ps.total_worker_time / ps.execution_count AS AvgCpuUs
FROM sys.dm_exec_procedure_stats ps
WHERE ps.plan_generation_num > 1
ORDER BY ps.plan_generation_num DESC;
```

`plan_generation_num` cao nghĩa là plan bị bỏ và tạo lại nhiều lần. Nguyên nhân thường gặp: statistics được auto-update, schema đổi, `SET` option khác nhau giữa các session, `WITH RECOMPILE`, hoặc dùng bảng tạm theo cách gây recompile.

Một chi tiết dễ bỏ sót: **`SET` option khác nhau tạo plan khác nhau**. Nếu app A dùng `ARITHABORT ON` và SSMS dùng `ARITHABORT OFF`, hai bên có hai plan riêng cho cùng câu SQL — đây là lời giải thích cho hiện tượng kinh điển "chạy trong SSMS thì nhanh, từ app thì chậm".

---

## 3. Parameter sniffing – vấn đề số một

### 3.1 Cơ chế

```sql
CREATE OR ALTER PROCEDURE Sales.usp_GetOrders @TenantID INT
AS
    SELECT OrderID, CustomerID, TotalAmount
    FROM Sales.Orders
    WHERE TenantID = @TenantID;
```

Lần đầu chạy với `@TenantID = 1` (tenant có 3 triệu order), optimizer "sniff" giá trị đó, thấy sẽ trả về rất nhiều row, và chọn Clustered Index Scan + hash aggregate. Plan này được cache. Lần sau chạy với `@TenantID = 8842` (12 order) vẫn dùng plan scan → đọc 3 triệu row để trả 12 row.

Chiều ngược lại tệ hơn: plan được compile cho tenant nhỏ (nested loop + key lookup) rồi áp cho tenant lớn → hàng triệu lần lookup.

### 3.2 Phát hiện

```sql
-- min/max lệch nhau nhiều lần = nghi vấn sniffing
SELECT TOP 20
    OBJECT_NAME(qs.object_id)                                        AS ProcName,
    qs.execution_count,
    qs.min_elapsed_time  / 1000                                      AS MinMs,
    qs.max_elapsed_time  / 1000                                      AS MaxMs,
    qs.total_elapsed_time / qs.execution_count / 1000                AS AvgMs,
    CAST(1.0 * qs.max_elapsed_time / NULLIF(qs.min_elapsed_time,0) AS DECIMAL(10,1)) AS MaxOverMin,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1, 300)         AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE qs.execution_count > 20 AND qs.min_elapsed_time > 0
ORDER BY MaxOverMin DESC;
```

Trong plan XML, hai giá trị cần so: `ParameterCompiledValue` (giá trị lúc compile) và `ParameterRuntimeValue` (giá trị lần chạy này). Lệch nhau nhiều về selectivity chính là bằng chứng.

### 3.3 Sáu cách xử lý, và khi nào dùng cái nào

| Cách | Cơ chế | Chi phí | Dùng khi |
|---|---|---|---|
| `OPTION (RECOMPILE)` | Compile mới mỗi lần, biết giá trị thật | CPU compile mỗi lần chạy | Query lệch mạnh, tần suất chạy vừa phải |
| `OPTIMIZE FOR (@p = <giá trị>)` | Luôn compile cho một giá trị đại diện | Sai với các giá trị khác | Có một giá trị chiếm đa số lưu lượng |
| `OPTIMIZE FOR UNKNOWN` | Dùng density trung bình, bỏ sniffing | Plan trung bình, không tối ưu cho ai | Phân bố tương đối đều, muốn ổn định |
| Tách procedure theo nhóm dữ liệu | Mỗi nhóm một plan riêng | Code nhiều hơn | Phân bố nhị phân rõ (tenant lớn vs nhỏ) |
| Dynamic SQL | Mỗi hình dạng query một plan | Phức tạp hơn | Optional parameter (xem [tsql_advanced.md](../fundamentals/tsql_advanced.md) mục 8.1) |
| **PSP optimization (2022+)** | Engine tự tạo nhiều plan theo dải cardinality | Tự động, không cần sửa code | Bật sẵn ở compat level 160+ |

```sql
-- Recompile: lựa chọn mặc định khi chưa rõ
SELECT ... WHERE TenantID = @TenantID OPTION (RECOMPILE);

-- Chọn giá trị đại diện
SELECT ... WHERE TenantID = @TenantID OPTION (OPTIMIZE FOR (@TenantID = 500));

-- Bỏ sniffing hoàn toàn
SELECT ... WHERE TenantID = @TenantID OPTION (OPTIMIZE FOR UNKNOWN);
```

Mẹo phổ biến "gán tham số vào biến local để chống sniffing" hoạt động, nhưng nó tương đương `OPTIMIZE FOR UNKNOWN` một cách ngầm ẩn và khó đọc hơn. Nếu muốn hành vi đó, hãy viết hint ra để người sau hiểu được ý định.

### 3.4 Parameter Sensitive Plan optimization (SQL Server 2022+)

Từ compatibility level 160, engine có thể **giữ nhiều plan cho cùng một statement**, mỗi plan phục vụ một dải cardinality của tham số:

```sql
ALTER DATABASE SalesDB SET COMPATIBILITY_LEVEL = 160;   -- điều kiện cần

-- Tắt riêng PSP nếu nó gây hồi quy
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = OFF;
```

Giới hạn cần biết: PSP chỉ áp dụng cho một số hình dạng predicate (equality trên cột có statistics lệch rõ), tối đa một số ít "dispatcher" phân nhánh, và **không thay thế được thiết kế query tốt**. Nó giảm bớt số ca phải can thiệp thủ công, không xóa bỏ chương này.

---

## 4. Query Store – hộp đen của database

### 4.1 Bật và cấu hình

```sql
ALTER DATABASE SalesDB SET QUERY_STORE = ON;
ALTER DATABASE SalesDB SET QUERY_STORE (
    OPERATION_MODE              = READ_WRITE,
    QUERY_CAPTURE_MODE          = AUTO,          -- bỏ query không đáng kể
    MAX_STORAGE_SIZE_MB         = 2048,
    INTERVAL_LENGTH_MINUTES     = 15,            -- độ mịn của runtime stats
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    CLEANUP_POLICY              = (STALE_QUERY_THRESHOLD_DAYS = 30),
    SIZE_BASED_CLEANUP_MODE     = AUTO,          -- tự dọn khi gần đầy, tránh chuyển sang READ_ONLY
    MAX_PLANS_PER_QUERY         = 200,
    WAIT_STATS_CAPTURE_MODE     = ON             -- 2017+: wait stats theo từng query
);
```

`SIZE_BASED_CLEANUP_MODE = AUTO` là thiết lập hay bị bỏ quên nhưng quan trọng: không có nó, khi Query Store đầy nó chuyển sang `READ_ONLY` và âm thầm ngừng thu dữ liệu — đúng lúc bạn cần nó nhất.

`WAIT_STATS_CAPTURE_MODE = ON` cho phép trả lời câu hỏi "query này chậm vì CPU, vì I/O, hay vì bị block?" ngay trong Query Store, không cần dựng monitoring riêng.

### 4.2 Các truy vấn Query Store dùng thường xuyên

```sql
-- Top query theo tổng thời gian trong 24h
SELECT TOP 20
    q.query_id, p.plan_id,
    OBJECT_NAME(q.object_id)                                  AS ObjectName,
    SUBSTRING(t.query_sql_text, 1, 300)                       AS QueryText,
    SUM(rs.count_executions)                                  AS Execs,
    SUM(rs.avg_duration * rs.count_executions) / 1000000.0    AS TotalSec,
    AVG(rs.avg_duration) / 1000.0                             AS AvgMs,
    AVG(rs.avg_cpu_time) / 1000.0                             AS AvgCpuMs,
    AVG(rs.avg_logical_io_reads)                              AS AvgReads
FROM sys.query_store_query q
JOIN sys.query_store_query_text t ON q.query_text_id = t.query_text_id
JOIN sys.query_store_plan p       ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
JOIN sys.query_store_runtime_stats_interval i ON rs.runtime_stats_interval_id = i.runtime_stats_interval_id
WHERE i.start_time > DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY q.query_id, p.plan_id, q.object_id, t.query_sql_text
ORDER BY TotalSec DESC;

-- Query có nhiều plan và độ lệch lớn → nghi vấn hồi quy plan
SELECT
    q.query_id,
    SUBSTRING(t.query_sql_text, 1, 200)     AS QueryText,
    COUNT(DISTINCT p.plan_id)               AS PlanCount,
    MIN(rs.avg_duration) / 1000.0           AS BestAvgMs,
    MAX(rs.avg_duration) / 1000.0           AS WorstAvgMs
FROM sys.query_store_query q
JOIN sys.query_store_query_text t ON q.query_text_id = t.query_text_id
JOIN sys.query_store_plan p       ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
GROUP BY q.query_id, t.query_sql_text
HAVING COUNT(DISTINCT p.plan_id) > 1
   AND MAX(rs.avg_duration) > 5 * MIN(rs.avg_duration)
ORDER BY WorstAvgMs DESC;

-- Query chờ gì (2017+)
SELECT TOP 20
    ws.wait_category_desc, q.query_id,
    SUBSTRING(t.query_sql_text, 1, 200) AS QueryText,
    SUM(ws.total_query_wait_time_ms)    AS TotalWaitMs
FROM sys.query_store_wait_stats ws
JOIN sys.query_store_plan p       ON ws.plan_id = p.plan_id
JOIN sys.query_store_query q      ON p.query_id = q.query_id
JOIN sys.query_store_query_text t ON q.query_text_id = t.query_text_id
GROUP BY ws.wait_category_desc, q.query_id, t.query_sql_text
ORDER BY TotalWaitMs DESC;
```

### 4.3 Force plan

```sql
EXEC sp_query_store_force_plan   @query_id = 42, @plan_id = 7;
EXEC sp_query_store_unforce_plan @query_id = 42, @plan_id = 7;

-- Kiểm tra plan đã force và có bị force fail không
SELECT p.query_id, p.plan_id, p.is_forced_plan,
       p.force_failure_count, p.last_force_failure_reason_desc
FROM sys.query_store_plan p
WHERE p.is_forced_plan = 1;
```

Force plan là **biện pháp tạm thời có chủ đích**, không phải cách sửa. `force_failure_count` tăng nghĩa là plan bị force không còn hợp lệ (index bị xóa, schema đổi) và engine đã âm thầm bỏ qua — nên phải có alert trên cột này. Ghi lại lý do force và ngày dự kiến bỏ; nếu không, sau 2 năm sẽ không ai dám bỏ.

### 4.4 Automatic tuning

```sql
ALTER DATABASE SalesDB SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);

-- Xem engine đã đề xuất / tự làm gì
SELECT reason, score, JSON_VALUE(details,'$.implementationDetails.script') AS Script,
       state, is_revertable_action, execute_action_start_time
FROM sys.dm_db_tuning_recommendations
ORDER BY score DESC;
```

`FORCE_LAST_GOOD_PLAN` phát hiện hồi quy và tự force lại plan tốt trước đó, rồi tự bỏ force nếu không còn tốt. Đây là tính năng đáng bật cho hệ production ổn định: nó xử lý đúng lớp sự cố "3h sáng plan đổi".

### 4.5 Query Store hints (SQL Server 2022+)

Trước 2022, muốn áp hint cho query không sửa được code (ứng dụng đóng, ORM sinh SQL) phải dùng Plan Guide — cú pháp rườm rà và khó bảo trì. Từ 2022 có Query Store hints:

```sql
-- Áp hint theo query_id, không cần đổi câu SQL
EXEC sys.sp_query_store_set_hints
     @query_id = 42,
     @query_hints = N'OPTION (RECOMPILE, MAXDOP 1)';

-- Xem và bỏ
SELECT * FROM sys.query_store_query_hints;
EXEC sys.sp_query_store_clear_hints @query_id = 42;
```

Đây là công cụ giá trị nhất cho hệ thống dùng ORM: Hibernate/JPA sinh SQL mà bạn không thể thêm `OPTION (...)` vào, nhưng vẫn áp được hint từ phía database.

Plan Guide vẫn còn dùng được và cần khi phải khớp theo văn bản câu lệnh:

```sql
EXEC sp_create_plan_guide
    @name = N'PG_GetOrders',
    @stmt = N'SELECT OrderID, CustomerID, TotalAmount FROM Sales.Orders WHERE TenantID = @TenantID',
    @type = N'SQL',
    @module_or_batch = NULL,
    @params = N'@TenantID INT',
    @hints = N'OPTION (OPTIMIZE FOR UNKNOWN)';

SELECT * FROM sys.plan_guides;
EXEC sp_control_plan_guide N'VALIDATE', N'PG_GetOrders';   -- kiểm tra còn khớp sau khi schema đổi
```

---

## 5. Intelligent Query Processing (IQP)

IQP là tập tính năng engine tự sửa các lỗi kinh điển của optimizer. Bảng dưới ghi version và điều kiện — vì "tại sao bật rồi mà không thấy tác dụng" hầu hết là do compat level.

| Tính năng | Từ version | Compat level | Giải quyết vấn đề |
|---|---|---|---|
| Adaptive join | 2017 | 140 | Chọn Hash vs Nested Loops lúc runtime |
| Memory grant feedback (batch mode) | 2017 | 140 | Grant quá lớn/quá nhỏ |
| Interleaved execution (multi-statement TVF) | 2017 | 140 | Estimate cố định của MSTVF |
| Batch mode on rowstore | 2019 | 150 | Batch mode không cần columnstore |
| Scalar UDF inlining | 2019 | 150 | Scalar UDF gọi từng row |
| Table variable deferred compilation | 2019 | 150 | Table variable luôn estimate 1 row |
| Approximate count distinct | 2019 | – | `APPROX_COUNT_DISTINCT` |
| Row mode memory grant feedback | 2019 | 150 | Mở rộng feedback sang row mode |
| Memory grant feedback **persistence** | 2022 | 160 | Feedback không mất khi plan bị evict |
| Memory grant feedback percentile | 2022 | 160 | Dùng percentile thay vì lần chạy gần nhất |
| Cardinality estimation feedback | 2022 | 160 | Tự thử model estimate khác |
| DOP feedback | 2022 | 160 | Tự giảm MAXDOP nếu song song không giúp |
| Parameter sensitive plan optimization | 2022 | 160 | Nhiều plan theo dải tham số |
| Optional parameter plan optimization | 2025 | 170 | Query catch-all nhiều tham số tùy chọn |

```sql
-- Bật/tắt từng tính năng ở mức database khi cần điều tra hồi quy
ALTER DATABASE SCOPED CONFIGURATION SET DOP_FEEDBACK = ON;
ALTER DATABASE SCOPED CONFIGURATION SET CE_FEEDBACK = ON;
ALTER DATABASE SCOPED CONFIGURATION SET MEMORY_GRANT_FEEDBACK_PERSISTENCE = ON;
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;

-- Kiểm tra một scalar UDF có inline được không
SELECT name, is_inlineable, inline_type
FROM sys.sql_modules m JOIN sys.objects o ON m.object_id = o.object_id
WHERE o.type = 'FN';
```

Điểm quan trọng về vận hành: **nâng compatibility level là một thay đổi hiệu năng, không phải một thay đổi tương thích cú pháp**. Cách nâng an toàn:

```text
1. Bật Query Store, thu baseline ít nhất một tuần đủ chu kỳ nghiệp vụ
2. Nâng compat level
3. Theo dõi "Regressed Queries" trong Query Store
4. Query nào hồi quy → force plan cũ (biện pháp tạm) rồi điều tra nguyên nhân
5. Nếu cần: giữ compat level mới nhưng tắt riêng một IQP feature bằng database scoped configuration
```

Cách này tốt hơn hẳn việc lùi cả compat level, vì bạn giữ được các cải tiến khác.

**Optional Parameter Plan Optimization (2025)** đáng chú ý với ai viết nhiều query catch-all: nó xử lý đúng dạng `WHERE (@p IS NULL OR col = @p)` mà mục 3 phải chữa bằng dynamic SQL. Chi tiết ở [sqlserver_2025.md](../modern/sqlserver_2025.md).

---

## 6. Memory grant, spill và song song hóa

### 6.1 Memory grant

Hash join, hash aggregate và sort xin bộ nhớ **trước khi chạy**, dựa trên estimate. Estimate sai theo cả hai chiều đều gây vấn đề:

| Tình huống | Hậu quả | Wait/warning |
|---|---|---|
| Grant quá lớn | Query khác không xin được grant, phải xếp hàng | `RESOURCE_SEMAPHORE`, warning "excessive grant" |
| Grant quá nhỏ | Spill dữ liệu ra tempdb, chậm nhiều lần | warning "sort/hash spill" |

```sql
-- Ai đang giữ và ai đang chờ memory grant
SELECT
    mg.session_id, mg.requested_memory_kb / 1024 AS RequestedMB,
    mg.granted_memory_kb / 1024                  AS GrantedMB,
    mg.used_memory_kb / 1024                     AS UsedMB,
    mg.max_used_memory_kb / 1024                 AS MaxUsedMB,
    mg.wait_time_ms, mg.dop,
    SUBSTRING(t.text, 1, 300)                    AS QueryText
FROM sys.dm_exec_query_memory_grants mg
CROSS APPLY sys.dm_exec_sql_text(mg.sql_handle) t
ORDER BY mg.requested_memory_kb DESC;
```

Cách can thiệp, theo thứ tự nên thử:

```sql
-- 1. Sửa gốc: estimate sai (statistics, kiểu dữ liệu, query shape)
-- 2. Để engine tự học: memory grant feedback (2019+/2022+ persistence)
-- 3. Cuối cùng mới hint
SELECT ... OPTION (MIN_GRANT_PERCENT = 5, MAX_GRANT_PERCENT = 25);
```

Một nguyên nhân "grant khổng lồ" rất hay gặp và dễ sửa: cột khai báo `NVARCHAR(MAX)` hoặc `VARCHAR(4000)` trong khi dữ liệu thật chỉ vài chục ký tự. Optimizer tính grant theo **kích thước khai báo**, không theo dữ liệu thực.

### 6.2 Song song hóa

```sql
-- Cấu hình mức instance
EXEC sp_configure 'max degree of parallelism', 8;      RECONFIGURE;
EXEC sp_configure 'cost threshold for parallelism', 40; RECONFIGURE;   -- mặc định 5 là quá thấp

-- Mức database (ưu tiên dùng cái này, linh hoạt hơn)
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 8;

-- Mức query
SELECT ... OPTION (MAXDOP 1);
```

Hướng dẫn thực dụng cho `MAXDOP`: đặt theo số core **trong một NUMA node**, tối đa 8 cho OLTP. Để `0` (không giới hạn) trên máy 64 core khiến một query đơn lẻ có thể chiếm toàn bộ CPU.

`cost threshold for parallelism` mặc định là 5 — con số từ thập niên 1990. Trên phần cứng hiện nay, để 5 nghĩa là rất nhiều query nhỏ bị song song hóa vô ích, sinh overhead và `CXPACKET`. Điểm khởi đầu hợp lý là 30–50, rồi kiểm chứng.

Về `CXPACKET`/`CXCONSUMER`: đây gần như luôn là **triệu chứng, không phải nguyên nhân**. Nó cho biết các thread trong một plan song song không nhận đều việc — nguyên nhân gốc thường là estimate sai hoặc dữ liệu skew. Đừng "chữa" bằng cách đặt `MAXDOP 1` toàn hệ.

---

## 7. In-Memory OLTP cho đường đi nóng

```sql
-- 1. Filegroup memory-optimized (một database chỉ có một, không xóa được)
ALTER DATABASE SalesDB ADD FILEGROUP MemOptFG CONTAINS MEMORY_OPTIMIZED_DATA;
ALTER DATABASE SalesDB ADD FILE (NAME = 'SalesDB_MemOpt',
    FILENAME = '/var/opt/mssql/data/SalesDB_MemOpt') TO FILEGROUP MemOptFG;

-- 2. Bảng memory-optimized
CREATE TABLE Session.Cache (
    SessionID UNIQUEIDENTIFIER NOT NULL
        PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 2097152),   -- ≈ 2× số key dự kiến, lũy thừa 2
    UserID    INT NOT NULL,
    Payload   NVARCHAR(4000) NULL,
    ExpiresAt DATETIME2(0) NOT NULL,
    INDEX IX_Cache_Expiry NONCLUSTERED (ExpiresAt)                     -- range index cho quét hết hạn
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);

-- 3. Natively compiled procedure
CREATE OR ALTER PROCEDURE Session.usp_GetCache @SessionID UNIQUEIDENTIFIER
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    SELECT UserID, Payload, ExpiresAt
    FROM Session.Cache
    WHERE SessionID = @SessionID AND ExpiresAt > SYSUTCDATETIME();
END;
```

Điều cần biết trước khi chọn In-Memory OLTP:

| Chủ đề | Chi tiết |
|---|---|
| Bộ nhớ | Toàn bộ dữ liệu phải nằm trong RAM; hết RAM là hết ghi |
| `DURABILITY` | `SCHEMA_AND_DATA` (bền) vs `SCHEMA_ONLY` (mất khi restart, nhanh hơn — hợp cho staging/session) |
| Hash index | `BUCKET_COUNT` quá nhỏ → chuỗi dài, quá lớn → tốn RAM; không range scan được |
| Range index | Dùng cho `>`/`<`/`ORDER BY`; là Bw-tree, không phải B-tree |
| Concurrency | MVCC lock-free, nhưng ứng dụng **phải** retry 41302/41305/41325/41301 ([transactions.md](../fundamentals/transactions.md) mục 10) |
| Giới hạn | Không phải mọi cú pháp T-SQL được hỗ trợ trong native procedure; `ALTER TABLE` có giới hạn |

In-Memory OLTP thắng rõ ở: session store, cache, counter/sequence tần suất rất cao, bảng staging của ETL (`SCHEMA_ONLY`), và bảng chịu tranh chấp latch nghiêm trọng. Nó không phải công cụ tổng quát để "tăng tốc database".

---

## 8. Anti-pattern query và cách sửa

```sql
-- 1. Non-SARGable: hàm bọc quanh cột
WHERE CONVERT(DATE, CreatedAt) = '2026-07-15'                            -- ✗
WHERE CreatedAt >= '2026-07-15' AND CreatedAt < '2026-07-16'             -- ✓

-- 2. Implicit conversion (nguyên nhân #1 của "có index mà vẫn scan")
WHERE CustomerCode = N'ABC'      -- ✗ nếu cột là VARCHAR: SQL Server convert CỘT sang NVARCHAR
WHERE CustomerCode = 'ABC'       -- ✓ và ở JDBC: sendStringParametersAsUnicode=false

-- 3. OR giữa các cột khác nhau
WHERE CustomerID = @c OR OrderNo = @o                                    -- ✗
SELECT ... WHERE CustomerID = @c UNION SELECT ... WHERE OrderNo = @o     -- ✓

-- 4. Catch-all optional parameter không có RECOMPILE
WHERE (@c IS NULL OR CustomerID = @c) AND (@s IS NULL OR Status = @s)    -- ✗ một plan cho mọi tổ hợp
-- ✓ OPTION (RECOMPILE), dynamic SQL, hoặc OPPO (2025)

-- 5. NOT IN với subquery có NULL → kết quả rỗng lặng lẽ
WHERE CustomerID NOT IN (SELECT CustomerID FROM Sales.Orders)            -- ✗
WHERE NOT EXISTS (SELECT 1 FROM Sales.Orders o WHERE o.CustomerID = c.CustomerID)  -- ✓

-- 6. Multi-statement TVF trong JOIN → hộp đen, estimate cố định
--    ✓ viết lại thành inline TVF (một câu RETURN SELECT)

-- 7. SELECT * qua nhiều tầng view
--    Đọc cột không cần, phá covering index, và làm memory grant phình

-- 8. DISTINCT để chữa join sai
SELECT DISTINCT c.CustomerID, c.Name FROM ... -- ✗ thường là dấu hiệu join nhân bản row
-- ✓ dùng EXISTS hoặc sửa điều kiện join

-- 9. Paging bằng OFFSET lớn
ORDER BY OrderDate OFFSET 500000 ROWS FETCH NEXT 50 ROWS ONLY            -- ✗ vẫn phải đọc 500.050 row
-- ✓ keyset pagination
WHERE (OrderDate, OrderID) < (@lastDate, @lastId) ORDER BY OrderDate DESC, OrderID DESC
-- (trong T-SQL viết tường minh: WHERE OrderDate < @lastDate
--                                  OR (OrderDate = @lastDate AND OrderID < @lastId))

-- 10. Cursor cho việc set-based được (xem tsql_advanced.md mục 1)
```

Mục 9 — keyset pagination — đáng nhấn mạnh vì nó là nguồn chậm phổ biến của API danh sách: `OFFSET` tăng dần khiến trang càng sâu càng chậm theo cấp số cộng, còn keyset thì mọi trang đều nhanh như trang đầu.

---

## 9. Trade-offs

| Biện pháp | Được | Mất | Khi nào |
|---|---|---|---|
| `OPTION (RECOMPILE)` | Plan luôn khớp tham số | CPU compile mỗi lần chạy, không có số liệu tích lũy trong plan cache | Query lệch mạnh, tần suất thấp–trung |
| Force plan (Query Store) | Chặn hồi quy ngay lập tức | Đóng băng plan, có thể lạc hậu | Xử lý sự cố; phải có ngày review |
| `FORCE_LAST_GOOD_PLAN` | Tự động chống hồi quy | Ít kiểm soát, cần theo dõi | Production ổn định |
| Query Store hints | Áp hint mà không sửa code app | Ẩn với developer, phải tài liệu hóa | Ứng dụng đóng / ORM sinh SQL |
| Nâng compat level | Được IQP mới | Có thể hồi quy vài query | Có Query Store làm bằng chứng và quy trình lùi |
| MAXDOP thấp | Ổn định, ít CXPACKET | Query lớn chậm hơn | OLTP; không dùng làm thuốc chữa mọi bệnh |
| Memory grant hint | Chặn grant phi lý | Cố định số, dữ liệu đổi thì sai | Sau khi feedback không giải quyết được |
| In-Memory OLTP | Throughput rất cao, không lock | Tốn RAM, nhiều giới hạn, phải retry | Đường đi nóng cụ thể, không phải toàn hệ |
| `PARAMETERIZATION FORCED` | Giảm plan cache bloat | Sinh sniffing mới | Hệ nhiều ad-hoc SQL không sửa được |

---

## 10. Real-world – quy trình tuning có kỷ luật

```text
Bước 1: Xác định query mục tiêu bằng số liệu
   → Query Store: sắp theo TotalSec (không phải AvgMs — query chạy 1 triệu lần với 5ms
     tốn nhiều hơn query chạy 1 lần với 60s)

Bước 2: Phân loại "chậm vì gì" bằng wait stats theo query
   → sys.query_store_wait_stats: CPU / Buffer IO / Lock / Memory / Parallelism

Bước 3: Lấy plan + số đo mốc
   → SET STATISTICS IO, TIME ON. Ghi logical reads, CPU, elapsed vào ticket

Bước 4: Chẩn đoán theo thứ tự
   a. Có implicit conversion? → sửa kiểu tham số (rẻ nhất, hiệu quả nhất)
   b. Estimate lệch ở đâu đầu tiên? → statistics / query shape / ascending key
   c. Key Lookup nhiều? → INCLUDE
   d. Sort/Hash spill? → estimate hoặc grant
   e. min/max elapsed lệch nhiều lần? → parameter sniffing
   f. Nhiều plan trong Query Store? → hồi quy plan

Bước 5: Sửa MỘT thứ, đo lại bằng đúng chỉ số bước 3

Bước 6: Kiểm tra tác động phụ
   → Index mới: INSERT/UPDATE chậm thêm bao nhiêu? Có trùng index cũ?
   → Hint mới: có được ghi lại ở đâu để người sau biết?

Bước 7: Ghi lại
   → Trước/sau, nguyên nhân, biện pháp, và điều kiện để bỏ biện pháp tạm
```

Điểm dễ sai nhất trong quy trình này là bước 1: tối ưu query có `AvgMs` lớn nhất thay vì `TotalSec` lớn nhất. Query báo cáo chạy một lần/ngày mất 60 giây thường không phải vấn đề; query 5ms chạy 2000 lần/giây mới là nơi CPU của server đang đi.

---

## 11. Ghi chú – chủ đề tiếp theo

- [monitoring_troubleshooting.md](monitoring_troubleshooting.md): Extended Events, baseline tự động, runbook.
- [partitioning.md](partitioning.md): partition elimination và ảnh hưởng tới plan.
- [sqlserver_2025.md](../modern/sqlserver_2025.md): OPPO, Optimized Locking, và các IQP mới.
- [jdbc_java.md](../integration/jdbc_java.md): tham số hóa, kiểu dữ liệu, và fetch size từ phía Java.

Từ khóa mở rộng: `sys.dm_exec_query_profiles`, `USE HINT` (`DISABLE_OPTIMIZED_NESTED_LOOP`, `ASSUME_JOIN_PREDICATE_DEPENDS_ON_FILTERS`, `QUERY_OPTIMIZER_COMPATIBILITY_LEVEL_n`), Resource Governor, `sp_whoisactive`, cardinality estimation model version, columnstore batch mode window aggregate.

---

*Cập nhật lần cuối: 2026-07-30*
