# SQL Server Architecture & Storage Engine – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – SQL Server Architecture là gì?

**SQL Server** là relational database engine của Microsoft với kiến trúc client-server. Engine gồm 2 phần chính: **Relational Engine** (xử lý query) và **Storage Engine** (đọc/ghi data).

```
Client App (JDBC/ODBC/ADO.NET)
    ↓ TDS (Tabular Data Stream) protocol
SQL Server Network Interface (SNI)
    ↓
Relational Engine:
    Parser → Algebrizer → Query Optimizer → Execution Engine
                                 ↕
Storage Engine:
    Buffer Manager → Access Methods → Transaction Manager → Lock Manager
                          ↕
    Data Files (.mdf/.ndf)    Log File (.ldf)    TempDB
```

---

## Components – Relational Engine

### Parser & Algebrizer

```sql
-- Flow của 1 query:
-- 1. Parser: kiểm tra cú pháp → parse tree
-- 2. Algebrizer: resolve objects, check permissions, bind → query tree
-- 3. Optimizer: tạo execution plan (cost-based)
-- 4. Execution Engine: thực thi plan

-- Xem parsed query tree (trace flag)
DBCC TRACEON(3604);
DBCC SHOWCONTIG;
```

### Query Optimizer

```sql
-- Cost-based optimizer: tính toán nhiều execution plans → chọn plan có estimated cost thấp nhất
-- Dựa trên: statistics, cardinality estimates, index availability

-- Xem execution plan
SET SHOWPLAN_XML ON;
SELECT * FROM Orders WHERE CustomerID = 1;
SET SHOWPLAN_XML OFF;

-- Xem actual execution plan (chạy thực tế)
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT * FROM Orders WHERE CustomerID = 1;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- Output:
-- Table 'Orders'. Scan count 1, logical reads 5, physical reads 0
-- SQL Server Execution Times: CPU time = 0 ms, elapsed time = 1 ms
```

---

## Components – Storage Engine

### Buffer Pool (Memory Management)

```
Buffer Pool: vùng RAM lớn nhất, cache data pages

Data Pages (8KB mỗi page):
  ├── Page Header (96 bytes): page ID, type, free space, checksum
  ├── Row Offsets (cuối page)
  └── Row Data

Page Types:
  Data page     → row data
  Index page    → B-tree nodes
  LOB page      → varchar(max), varbinary(max), text, image
  Allocation    → GAM, SGAM, IAM, PFS pages
  Log page      → transaction log records (trong .ldf)

Buffer Pool Manager:
  - Cache "hot" pages trong RAM
  - Lazy writer: flush "dirty" pages to disk khi low memory
  - Checkpoint: flush all dirty pages định kỳ
  - Read-ahead: prefetch pages dự đoán sẽ cần
```

```sql
-- Xem buffer pool usage
SELECT
    DB_NAME(database_id)          AS DatabaseName,
    COUNT(*) * 8 / 1024           AS CachedMB,
    SUM(CASE WHEN is_modified = 1 THEN 1 ELSE 0 END) * 8 / 1024 AS DirtyMB
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id
ORDER BY CachedMB DESC;

-- Xem memory configuration
SELECT
    physical_memory_in_use_kb / 1024 AS MemoryUsedMB,
    page_fault_count
FROM sys.dm_os_process_memory;

-- Max server memory
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory', 16384;  -- 16GB
RECONFIGURE;
```

### Data Files & Filegroups

```sql
-- Cấu trúc files:
-- .mdf  = Primary data file (1 per DB)
-- .ndf  = Secondary data file (0 or more)
-- .ldf  = Transaction log file

-- Xem files của DB
SELECT
    name, physical_name, type_desc,
    size * 8 / 1024 AS SizeMB,
    max_size,
    growth
FROM sys.database_files;

-- Tạo DB với multiple filegroups (performance)
CREATE DATABASE SalesDB
ON PRIMARY (
    NAME = 'SalesDB_Primary',
    FILENAME = 'C:\Data\SalesDB.mdf',
    SIZE = 1GB,
    FILEGROWTH = 256MB
),
FILEGROUP SalesData (
    NAME = 'SalesDB_Data',
    FILENAME = 'D:\Data\SalesDB_Data.ndf',
    SIZE = 10GB,
    FILEGROWTH = 1GB
),
FILEGROUP SalesIndex (
    NAME = 'SalesDB_Index',
    FILENAME = 'E:\Data\SalesDB_Index.ndf',
    SIZE = 5GB,
    FILEGROWTH = 512MB
)
LOG ON (
    NAME = 'SalesDB_Log',
    FILENAME = 'F:\Logs\SalesDB.ldf',
    SIZE = 2GB,
    FILEGROWTH = 512MB
);

-- Đặt filegroup mặc định
ALTER DATABASE SalesDB MODIFY FILEGROUP SalesData DEFAULT;

-- Tạo table trong filegroup cụ thể
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    OrderDate DATE,
    Amount DECIMAL(10,2)
) ON SalesData;  -- data trên SalesData FG

-- Index trên filegroup khác
CREATE INDEX IX_Orders_Date ON Orders(OrderDate) ON SalesIndex;
```

### Transaction Log

```sql
-- Transaction Log: write-ahead logging (WAL)
-- Mọi change ghi vào log TRƯỚC khi ghi vào data files
-- Log sequence number (LSN): monotonically increasing

-- Log records:
-- BEGIN TRAN, DML operations, COMMIT/ROLLBACK
-- Used for: recovery, replication, CDC, AlwaysOn

-- Xem log space usage
DBCC SQLPERF(LOGSPACE);

-- Log virtual log files (VLFs) - nhiều VLF = slow log ops
DBCC LOGINFO('SalesDB');

-- Kiểm tra log growth gây nhiều VLFs → shrink + grow lại đúng size
-- Anti-pattern: autogrowth nhỏ (10MB) → hàng ngàn VLFs

-- Recovery models
ALTER DATABASE SalesDB SET RECOVERY FULL;    -- default, full log, point-in-time recovery
ALTER DATABASE SalesDB SET RECOVERY BULK_LOGGED;  -- minimal log cho bulk ops
ALTER DATABASE SalesDB SET RECOVERY SIMPLE;  -- no log backup needed, log auto-truncate

-- Shrink log (chỉ sau BACKUP LOG)
BACKUP LOG SalesDB TO DISK = 'NUL';  -- backup to NUL để test
DBCC SHRINKFILE('SalesDB_Log', 512);  -- shrink về 512MB
```

---

## How – Extent & Page Allocation

```sql
-- Extent = 8 pages = 64KB
-- Mixed extent: tối đa 8 objects
-- Uniform extent: 1 object

-- Allocation pages:
-- GAM  (Global Allocation Map): track free extents
-- SGAM (Shared GAM): track mixed extents
-- IAM  (Index Allocation Map): extents of 1 object
-- PFS  (Page Free Space): free space per page

-- Xem page structure (debug)
DBCC PAGE('SalesDB', 1, 104, 3);  -- DB, file, page, printopt

-- Xem table extents
SELECT
    au.type_desc,
    SUM(au.total_pages) * 8 / 1024 AS TotalMB,
    SUM(au.used_pages) * 8 / 1024  AS UsedMB
FROM sys.allocation_units au
JOIN sys.partitions p ON au.container_id = p.partition_id
JOIN sys.objects o ON p.object_id = o.object_id
WHERE o.name = 'Orders'
GROUP BY au.type_desc;
```

---

## How – TempDB

```sql
-- TempDB: shared scratch space
-- Dùng cho: temp tables, table variables, sorts, hash joins, row versioning (snapshot isolation)
-- Reset mỗi khi SQL Server restart

-- TempDB contention → performance bottleneck (latch contention trên allocation pages)

-- Best practices:
-- 1. Multiple data files = số CPU cores (tối đa 8)
-- 2. Files cùng size, equal autogrowth
-- 3. Để trên fast SSD riêng

-- Xem TempDB usage
SELECT
    SUM(unallocated_extent_page_count) * 8 / 1024       AS FreeSpaceMB,
    SUM(user_object_reserved_page_count) * 8 / 1024      AS UserObjectsMB,
    SUM(internal_object_reserved_page_count) * 8 / 1024  AS InternalMB,
    SUM(version_store_reserved_page_count) * 8 / 1024    AS VersionStoreMB
FROM sys.dm_db_file_space_usage;

-- Xem session dùng nhiều TempDB
SELECT
    s.session_id,
    s.login_name,
    t.user_objects_alloc_page_count * 8 / 1024 AS UserObjectsMB,
    t.internal_objects_alloc_page_count * 8 / 1024 AS InternalMB
FROM sys.dm_db_session_space_usage t
JOIN sys.dm_exec_sessions s ON t.session_id = s.session_id
ORDER BY (t.user_objects_alloc_page_count + t.internal_objects_alloc_page_count) DESC;
```

---

## How – Row Storage Format

```sql
-- Fixed-length vs Variable-length columns
-- Row structure:
--   Status bits (2 bytes)
--   Fixed-length data
--   Null bitmap
--   Variable-length column count
--   Variable-length column offsets
--   Variable-length data

-- Data types and storage:
-- INT          : 4 bytes fixed
-- BIGINT       : 8 bytes fixed
-- CHAR(n)      : n bytes fixed (right-padded)
-- VARCHAR(n)   : variable (up to n bytes + 2 overhead)
-- NCHAR(n)     : 2n bytes fixed (Unicode)
-- NVARCHAR(n)  : variable (up to 2n + 2 overhead)
-- DATETIME2    : 6-8 bytes
-- DECIMAL(p,s) : 5-17 bytes depending on precision
-- UNIQUEIDENTIFIER : 16 bytes (GUID)

-- Row compression: eliminates trailing spaces, stores fixed as variable
ALTER TABLE Orders REBUILD WITH (DATA_COMPRESSION = ROW);

-- Page compression: row + prefix + dictionary compression
ALTER TABLE Orders REBUILD WITH (DATA_COMPRESSION = PAGE);

-- Xem compression savings
EXEC sp_estimate_data_compression_savings 'dbo', 'Orders', NULL, NULL, 'PAGE';
```

---

## Why – Hiểu Architecture Để Làm Gì?

```
1. Sizing: biết buffer pool → set max server memory đúng
2. Performance: biết data pages, logical/physical reads → optimize queries
3. Filegroups: đặt data/index trên disk khác → parallel I/O
4. TempDB tuning: tránh latch contention → scale OLTP
5. Log management: chọn recovery model đúng → backup strategy
6. Compression: giảm I/O, tăng cache hit ratio
```

---

## Compare – SQL Server vs PostgreSQL vs Oracle (Storage)

| | SQL Server | PostgreSQL | Oracle |
|--|-----------|-----------|--------|
| Page size | 8KB | 8KB (default) | 8KB (default) |
| Buffer cache | Buffer Pool | Shared Buffers | SGA Buffer Cache |
| Redo log | Transaction Log (LDF) | WAL | Redo Log |
| Temp storage | TempDB | pg_temp | TEMP tablespace |
| Compression | Row/Page/Columnstore | TOAST | Advanced Compression |
| Filegroups | Yes | Tablespaces | Tablespaces |

---

## Trade-offs

```
Buffer Pool lớn:
✅ Nhiều hot pages trong RAM → ít I/O
❌ Tốn RAM, OS có thể bị thiếu memory
→ Rule: để lại 10-15% RAM cho OS

Multiple TempDB files:
✅ Giảm allocation page latch contention
❌ Phức tạp hơn khi manage
→ Rule: = min(số CPU cores, 8) files, cùng size

Page Compression:
✅ Giảm 40-60% storage, tăng I/O throughput
❌ CPU overhead khi compress/decompress
→ Dùng cho read-heavy, ít update tables
```

---

## Real-world – Sizing & Config

```sql
-- Kiểm tra wait stats (top waits = bottleneck)
SELECT TOP 20
    wait_type,
    wait_time_ms / 1000.0 AS WaitSeconds,
    (wait_time_ms - signal_wait_time_ms) / 1000.0 AS ResourceWaitS,
    waiting_tasks_count,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) AS Pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT',
    'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
    'HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE',
    'LAZYWRITER_SLEEP','LOGMGR_QUEUE','ONDEMAND_TASK_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
    'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY',
    'SLEEP_MASTERMDREADY','SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP',
    'SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT',
    'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH',
    'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','WAITFOR','XE_DISPATCHER_WAIT',
    'XE_TIMER_EVENT','BROKER_EVENTHANDLER','CHECKPOINT_QUEUE',
    'DBMIRROR_EVENTS_QUEUE','SQLTRACE_WAIT_ENTRIES'
)
ORDER BY wait_time_ms DESC;

-- Common waits và ý nghĩa:
-- PAGEIOLATCH_SH/EX: physical I/O chậm → add RAM hoặc faster disk
-- LCK_*:            blocking/deadlock → optimize transactions
-- CXPACKET:         parallelism → tune MAXDOP
-- RESOURCE_SEMAPHORE: memory grant waits → optimize queries
-- WRITELOG:         log I/O → faster log disk, batch commits
```

---

## Ghi chú – Chủ đề tiếp theo
> `tsql_advanced.md`: CTE, Window Functions, PIVOT/UNPIVOT, Dynamic SQL, Merge, JSON/XML, Temporal Tables

---

*Cập nhật lần cuối: 2026-05-06*
