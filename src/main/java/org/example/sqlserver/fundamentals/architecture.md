# SQL Server Architecture & Storage Engine

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Chỗ nào một hành vi chỉ có ở một version line, bài viết ghi rõ.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Đọc tiếp: [T-SQL Advanced](tsql_advanced.md).

---

## 1. Vấn đề mà kiến trúc này giải quyết

Một RDBMS phải đồng thời làm được bốn việc nghe rất mâu thuẫn nhau:

1. Trả lời query nhanh trên dữ liệu lớn hơn RAM nhiều lần.
2. Cho hàng nghìn session ghi đồng thời mà không hỏng dữ liệu.
3. Không mất transaction đã commit, kể cả khi mất điện giữa lúc ghi.
4. Vẫn phục hồi được về một thời điểm trong quá khứ khi có người xóa nhầm.

Toàn bộ những thành phần bên dưới — buffer pool, transaction log, lock manager, tempdb, checkpoint — tồn tại vì bốn yêu cầu này, không phải vì "cho phức tạp". Khi debug một sự cố production, câu hỏi hữu ích nhất luôn là: *thành phần nào trong chuỗi này đang là điểm nghẽn?*

```text
Client (JDBC / ODBC / ADO.NET / sqlcmd)
   │  TDS (Tabular Data Stream) trên TCP 1433, có thể bọc TLS
   ▼
SQL Server Network Interface (SNI) → SQLOS scheduler
   │
   ├── Relational Engine (Query Processor)
   │      Parser → Algebrizer/Binder → Query Optimizer → Query Execution
   │
   └── Storage Engine
          Access Methods → Buffer Manager → Transaction Manager → Lock Manager
                                  │                    │
                                  ▼                    ▼
                       Data files (.mdf/.ndf)    Log file (.ldf)
                                  │
                                  └── tempdb (scratch space dùng chung)
```

Hai nửa của engine có phân vai rất rõ: **Relational Engine quyết định làm gì**, **Storage Engine chịu trách nhiệm dữ liệu đúng và bền**. Một plan tệ không bao giờ được Storage Engine "sửa hộ", và một disk chậm không bao giờ được Optimizer bù lại.

---

## 2. SQLOS – tầng bị bỏ qua nhiều nhất

Trước khi nói buffer pool hay optimizer, cần biết SQL Server **không dùng thread scheduler của OS để điều phối công việc của mình**. Nó có một lớp riêng gọi là SQLOS, dùng mô hình cooperative scheduling:

| Khái niệm | Nghĩa | Vì sao cần biết |
|---|---|---|
| **Scheduler** | Một đơn vị điều phối, thường map 1-1 với một logical CPU | `MAXDOP`, CPU affinity, NUMA tính theo scheduler |
| **Worker** | Thread/fiber thực thi một task | `max worker threads`; hết worker → `THREADPOOL` wait |
| **Task** | Một đơn vị công việc của request | Một query song song có nhiều task |
| **Yield** | Worker tự nhường scheduler khi phải chờ | Nếu code không yield → `SOS_SCHEDULER_YIELD` cao |

Ba trạng thái của worker giải thích gần như mọi biểu đồ wait stats:

```text
RUNNING   → đang chiếm scheduler
SUSPENDED → đang chờ một resource (I/O, lock, memory grant, network)
RUNNABLE  → resource đã có, đang xếp hàng chờ CPU
```

Diễn giải thực tế:

- Nhiều thời gian ở SUSPENDED với `PAGEIOLATCH_*` → nghẽn I/O hoặc thiếu RAM.
- Nhiều thời gian ở SUSPENDED với `LCK_M_*` → nghẽn concurrency, xem [transactions.md](transactions.md).
- Nhiều thời gian ở RUNNABLE (signal wait cao) → nghẽn CPU thật, không phải nghẽn resource.

Đây là lý do "tỉ lệ signal wait / resource wait" là chỉ số phân loại đầu tiên khi triage:

```sql
SELECT
    SUM(signal_wait_time_ms)                              AS SignalWaitMs,   -- chờ CPU
    SUM(wait_time_ms - signal_wait_time_ms)               AS ResourceWaitMs, -- chờ resource
    CAST(100.0 * SUM(signal_wait_time_ms) / NULLIF(SUM(wait_time_ms),0)
         AS DECIMAL(5,2))                                 AS SignalPct
FROM sys.dm_os_wait_stats;
```

`SignalPct` cao (thường > 20–25% trên hệ OLTP) là dấu hiệu CPU pressure; thấp nghĩa là hệ thống đang chờ thứ khác.

---

## 3. Relational Engine – đường đi của một query

### 3.1 Bốn bước, và bước nào có thể bỏ qua

```text
1. Parse       → kiểm tra cú pháp, tạo parse tree
2. Algebrize   → phân giải tên object, kiểm tra quyền, gắn kiểu dữ liệu, chuẩn hóa
3. Optimize    → sinh nhiều phương án, chọn plan theo cost model
4. Execute     → chạy plan, đọc/ghi qua Storage Engine
```

Bước 3 là bước đắt nhất và cũng là bước SQL Server cố tránh làm lại: plan được cache trong **plan cache**. Cùng một query shape, lần sau tái sử dụng plan. Đây là nguồn gốc của cả hiệu năng tốt (không phải optimize lại) và của lớp sự cố khó nhất (plan sai cho tham số hiện tại — xem [query_optimization.md](../performance/query_optimization.md)).

### 3.2 Optimizer là cost-based, không phải rule-based

Optimizer không tìm plan tốt nhất tuyệt đối. Nó tìm **plan đủ tốt trong thời gian hợp lý**, dựa trên:

| Đầu vào | Nguồn | Sai lệch điển hình |
|---|---|---|
| Cardinality estimate | statistics (histogram, density) | stats cũ, skew dữ liệu, biến local |
| Cost model | công thức nội bộ về CPU/IO | giả định phần cứng chung, không đo máy bạn |
| Index có sẵn | metadata | thiếu index → chọn scan |
| Compatibility level | database setting | đổi level đổi luôn cardinality estimator |

Hệ quả thực tế cần nhớ: **estimated cost là đơn vị nội bộ, không phải giây, và không dùng để so sánh giữa hai server**. Con số đáng tin duy nhất khi tuning là actual rows vs estimated rows và các số đo runtime.

```sql
-- Estimated plan (không chạy query)
SET SHOWPLAN_XML ON;
GO
SELECT * FROM Sales.Orders WHERE CustomerID = 1;
GO
SET SHOWPLAN_XML OFF;
GO

-- Actual plan + số đo runtime
SET STATISTICS IO, TIME, XML ON;
SELECT * FROM Sales.Orders WHERE CustomerID = 1;
SET STATISTICS IO, TIME, XML OFF;
-- logical reads = số page đọc từ buffer pool (chỉ số so sánh ổn định nhất giữa các lần chạy)
-- physical reads / read-ahead reads = phải xuống disk
```

`logical reads` là thước đo tuning tốt hơn thời gian chạy: nó không dao động theo cache nóng/lạnh và tải máy.

---

## 4. Storage Engine – page, extent, allocation

### 4.1 Page 8KB là đơn vị của mọi thứ

Mọi thao tác đọc/ghi của SQL Server đều theo page 8KB, không theo row. Đây là lý do row hẹp lại nhanh hơn: nhiều row hơn trên mỗi page → ít page hơn cho cùng số row → ít I/O và ít RAM.

```text
Page 8192 bytes
├── Page header  96 bytes   (page id, type, LSN, free space, m_slotCnt...)
├── Row data     ~8060 bytes khả dụng cho dữ liệu
└── Slot array   ở cuối page, đọc từ cuối lên (offset của từng row)

Giới hạn: một row (không tính LOB off-row) tối đa ~8060 bytes.
Vượt quá → cột variable-length bị đẩy off-row (ROW_OVERFLOW_DATA).
```

Các loại page cần biết tên vì chúng xuất hiện trong thông báo lỗi và wait:

| Loại | Chứa gì |
|---|---|
| Data | row của heap hoặc leaf của clustered index |
| Index | node của B-tree (non-clustered, hoặc non-leaf của clustered) |
| LOB / Row-overflow | `varchar(max)`, `nvarchar(max)`, `varbinary(max)`, phần tràn của row |
| GAM / SGAM | bản đồ extent đã cấp phát (global / mixed) |
| IAM | extent thuộc về một allocation unit cụ thể |
| PFS | phần trăm chỗ trống của từng page trong một dải page |
| BCM / DCM | bulk-changed map, differential-changed map (phục vụ backup) |

**DCM chính là cơ chế đằng sau differential backup**: SQL Server không so sánh dữ liệu, nó chỉ đọc bitmap "page nào đã đổi từ full backup gần nhất". Đó là lý do differential nhanh nhưng phình dần theo tuần (xem [backup_recovery.md](../administration/backup_recovery.md)).

### 4.2 Extent và tranh chấp allocation page

```text
Extent = 8 page liên tiếp = 64KB
  Uniform extent : cả 8 page thuộc một object
  Mixed extent   : chia cho tối đa 8 object nhỏ

Cấp phát một page mới cần cập nhật PFS/GAM/SGAM → các page này là điểm nóng tranh chấp.
Biểu hiện: PAGELATCH_UP/EX trên các page có id kiểu 2:1:1, 2:1:3 (tempdb).
```

Phân biệt hai wait dễ nhầm, vì cách xử lý hoàn toàn khác nhau:

| Wait | Nghĩa | Hướng xử lý |
|---|---|---|
| `PAGEIOLATCH_*` | Đang chờ **đọc page từ disk vào RAM** | Thêm RAM, disk nhanh hơn, giảm logical reads |
| `PAGELATCH_*` | Page **đã ở trong RAM**, chờ latch để truy cập | Giảm hot spot: thêm file tempdb, đổi thiết kế key, giảm concurrency lên cùng page |

### 4.3 Lệnh soi cấu trúc vật lý

```sql
-- Kích thước & mức sử dụng theo allocation unit
SELECT
    au.type_desc,
    SUM(au.total_pages) * 8 / 1024 AS TotalMB,
    SUM(au.used_pages)  * 8 / 1024 AS UsedMB
FROM sys.allocation_units au
JOIN sys.partitions p ON au.container_id = p.partition_id
JOIN sys.objects    o ON p.object_id = o.object_id
WHERE o.name = 'Orders'
GROUP BY au.type_desc;

-- Nội dung thô của một page (chỉ dùng khi điều tra, không dùng trong production script)
DBCC TRACEON(3604);
DBCC PAGE('SalesDB', 1, 104, 3);
```

`DBCC PAGE` là công cụ điều tra, không phải công cụ vận hành: nó không có contract ổn định giữa các version.

---

## 5. Buffer Pool và bộ nhớ

### 5.1 Buffer pool làm gì

Buffer pool là vùng RAM lớn nhất của instance, cache các data/index page. Mọi lần đọc đều đi qua nó:

```text
Query cần page P
   ├── P có trong buffer pool → logical read (nhanh, ~µs)
   └── P không có            → physical read: đọc từ disk vào pool (chậm, ~0.1–10ms)

Ghi:
   UPDATE sửa page trong RAM → page thành "dirty" → KHÔNG ghi disk ngay
   Log record của thay đổi thì PHẢI xuống disk trước khi commit trả về (WAL)
   Dirty page xuống disk sau, do checkpoint hoặc lazy writer
```

Đây là điểm mấu chốt về durability: **transaction bền vì log đã xuống disk, không phải vì data file đã cập nhật**. Data file có thể lạc hậu vài phút so với thực tế đã commit, và recovery lúc khởi động sẽ dùng log để bù.

| Thành phần | Vai trò |
|---|---|
| **Checkpoint** | Định kỳ đẩy dirty page xuống data file, giới hạn công việc recovery |
| **Lazy writer** | Giải phóng buffer khi thiếu memory, ghi dirty page nếu cần |
| **Read-ahead** | Đoán trước page sắp cần và nạp sẵn (rất quan trọng với scan lớn) |
| **Eviction** | Loại page ít dùng theo cơ chế xấp xỉ LRU |

### 5.2 Cấu hình memory

```sql
-- Thực tế đang dùng bao nhiêu
SELECT
    physical_memory_in_use_kb / 1024        AS MemoryUsedMB,
    large_page_allocations_kb / 1024        AS LargePagesMB,
    memory_utilization_percentage,
    process_physical_memory_low             AS OsSignalledLowMemory
FROM sys.dm_os_process_memory;

-- Cache theo database
SELECT
    DB_NAME(database_id)                              AS DatabaseName,
    COUNT(*) * 8 / 1024                               AS CachedMB,
    SUM(CASE WHEN is_modified = 1 THEN 1 ELSE 0 END) * 8 / 1024 AS DirtyMB
FROM sys.dm_os_buffer_descriptors
GROUP BY database_id
ORDER BY CachedMB DESC;

-- Giới hạn bộ nhớ cho instance
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 24576;   -- ví dụ 24GB
RECONFIGURE;
```

Nguyên tắc đặt `max server memory`: chừa cho OS và các thành phần ngoài buffer pool (SSIS, SSRS, backup buffer, CLR, linked server provider). Một điểm khởi đầu hay dùng là chừa ~10–15% RAM hoặc tối thiểu 4GB cho OS, rồi **kiểm chứng bằng `Page Life Expectancy` và `Memory Grants Pending`**, không tin công thức suông.

| Chỉ số | Ý nghĩa | Đọc thế nào |
|---|---|---|
| Page Life Expectancy (PLE) | Số giây một page kỳ vọng còn nằm trong pool | Giá trị tuyệt đối ít nghĩa; **xu hướng giảm mạnh** mới là tín hiệu |
| Memory Grants Pending | Số query đang chờ memory grant | > 0 kéo dài = nghẽn memory grant thật |
| Buffer cache hit ratio | Tỉ lệ đọc trúng cache | Gần như luôn > 99%, hầu như vô dụng để chẩn đoán |

Ngoài buffer pool, hai vùng bộ nhớ hay gây sự cố:

- **Plan cache**: nhiều ad-hoc SQL không tham số hóa → plan cache phình, đẩy data page ra khỏi pool.
- **Memory grant**: hash join và sort xin bộ nhớ trước khi chạy; grant quá lớn làm query khác xếp hàng (`RESOURCE_SEMAPHORE`), grant quá nhỏ gây spill xuống tempdb.

---

## 6. Data file, filegroup và cách bố trí

```sql
-- Xem file của database hiện tại
SELECT
    name, physical_name, type_desc,
    size * 8 / 1024                          AS SizeMB,
    CASE max_size WHEN -1 THEN NULL ELSE max_size * 8 / 1024 END AS MaxMB,
    CASE WHEN is_percent_growth = 1 THEN NULL ELSE growth * 8 / 1024 END AS GrowthMB,
    is_percent_growth
FROM sys.database_files;
```

Ba loại file, ba mục đích:

| Đuôi | Là gì | Số lượng |
|---|---|---|
| `.mdf` | Primary data file | Đúng 1 |
| `.ndf` | Secondary data file | 0..n |
| `.ldf` | Transaction log | 1 là đủ; nhiều file log **không** tăng throughput vì log ghi tuần tự |

Filegroup là nhóm data file, và là đơn vị mà bảng/index/partition được đặt vào:

```sql
CREATE DATABASE SalesDB
ON PRIMARY (
    NAME = 'SalesDB_Primary', FILENAME = '/var/opt/mssql/data/SalesDB.mdf',
    SIZE = 1GB, FILEGROWTH = 256MB
),
FILEGROUP FG_Data (
    NAME = 'SalesDB_Data1', FILENAME = '/var/opt/mssql/data/SalesDB_Data1.ndf',
    SIZE = 16GB, FILEGROWTH = 1GB
),
FILEGROUP FG_Archive (
    NAME = 'SalesDB_Arch1', FILENAME = '/var/opt/mssql/data/SalesDB_Arch1.ndf',
    SIZE = 32GB, FILEGROWTH = 2GB
)
LOG ON (
    NAME = 'SalesDB_Log', FILENAME = '/var/opt/mssql/log/SalesDB.ldf',
    SIZE = 4GB, FILEGROWTH = 512MB
);

ALTER DATABASE SalesDB MODIFY FILEGROUP FG_Data DEFAULT;
```

Lý do thật để dùng nhiều filegroup, xếp theo giá trị thực tế:

1. **Piecemeal restore**: restore filegroup quan trọng trước, đưa DB online sớm (xem [backup_recovery.md](../administration/backup_recovery.md)).
2. **Partition theo vòng đời dữ liệu**: dữ liệu nóng và dữ liệu lạnh trên storage khác nhau (xem [partitioning.md](../performance/partitioning.md)).
3. **Parallel I/O trên nhiều volume** — lợi ích này nhỏ dần khi dùng NVMe/SAN hiện đại; đừng chia file chỉ vì "nghe nói nhanh hơn".

Việc "tách index sang filegroup khác cho nhanh" là lời khuyên cũ từ thời đĩa cơ; trên storage hiện đại nó thường chỉ tăng độ phức tạp vận hành.

### 6.1 Autogrowth: cấu hình mặc định luôn cần sửa

```sql
ALTER DATABASE SalesDB
MODIFY FILE (NAME = 'SalesDB_Data1', FILEGROWTH = 1GB);   -- MB tuyệt đối, không phần trăm
```

Hai lỗi kinh điển:

- **Growth theo phần trăm**: file càng lớn, mỗi lần grow càng lâu, thời điểm grow càng khó đoán.
- **Growth quá nhỏ (mặc định vài MB)**: hàng nghìn lần grow, log sinh ra vô số VLF, và mỗi lần grow là một lần dừng ngắn.

Với data file, **Instant File Initialization** (quyền `Perform Volume Maintenance Tasks` trên Windows, mặc định có sẵn trên Linux) làm việc grow gần như tức thời. Log file thì **không** hưởng lợi: log luôn phải zero-out, nên grow log lớn = dừng thật.

---

## 7. Transaction Log – trái tim của durability

### 7.1 Write-Ahead Logging

```text
Nguyên tắc WAL: log record của một thay đổi phải nằm trên disk
                trước khi trang dữ liệu tương ứng được cho phép xuống disk,
                và trước khi COMMIT trả về cho client.

Mỗi log record có LSN (Log Sequence Number) tăng đơn điệu.
LSN cho phép: recovery, differential/log backup, replication, CDC, Always On.
```

Vì mọi commit đều phải chờ log xuống disk, **độ trễ ghi của volume log quyết định trần throughput của workload OLTP**. Wait `WRITELOG` cao gần như luôn là câu chuyện về log storage hoặc về việc commit quá nhiều lần (mỗi row một transaction).

### 7.2 VLF – cấu trúc bên trong log

Log không phải một khối liền: nó chia thành **Virtual Log File (VLF)**. Số VLF sinh ra phụ thuộc kích thước mỗi lần grow. Hàng nghìn VLF nhỏ làm chậm khởi động database, log backup, và recovery.

```sql
-- SQL Server 2016 SP2+ / 2017+: DMV thay cho DBCC LOGINFO
SELECT database_id, DB_NAME(database_id) AS DbName,
       COUNT(*) AS VlfCount,
       SUM(CASE WHEN vlf_active = 1 THEN 1 ELSE 0 END) AS ActiveVlf
FROM sys.dm_db_log_info(NULL)
GROUP BY database_id
ORDER BY VlfCount DESC;

-- Không gian log và lý do log không thể truncate
SELECT name, log_reuse_wait_desc, recovery_model_desc
FROM sys.databases
WHERE database_id > 4;
```

`log_reuse_wait_desc` là cột chẩn đoán quan trọng nhất khi log phình:

| Giá trị | Nghĩa | Xử lý |
|---|---|---|
| `LOG_BACKUP` | Đang ở FULL/BULK_LOGGED và chưa có log backup | Chạy `BACKUP LOG`, và lập job định kỳ |
| `ACTIVE_TRANSACTION` | Có transaction mở rất lâu | Tìm và xử lý transaction đó |
| `AVAILABILITY_REPLICA` | Secondary của Always On đang tụt hậu | Xem [ha_dr.md](../administration/ha_dr.md) |
| `REPLICATION` / `CDC` | Log reader chưa đọc tới | Kiểm tra agent/capture job |
| `NOTHING` | Log có thể tái sử dụng | Log lớn là do đã từng cần lớn |

Sửa số VLF quá nhiều là việc một lần, có chủ đích, làm trong cửa sổ bảo trì: `BACKUP LOG` → `DBCC SHRINKFILE` log về nhỏ → grow lại **một lần** tới kích thước mục tiêu. Shrink log định kỳ theo cron là anti-pattern: nó chỉ tạo vòng lặp shrink–grow và sinh thêm VLF.

### 7.3 Recovery model và ý nghĩa vận hành

```sql
ALTER DATABASE SalesDB SET RECOVERY FULL;          -- mặc định cho production
ALTER DATABASE SalesDB SET RECOVERY BULK_LOGGED;   -- cửa sổ ETL, log tối thiểu cho bulk
ALTER DATABASE SalesDB SET RECOVERY SIMPLE;        -- dev/test, không PITR
```

| Model | Log backup | Point-in-time restore | Log tự truncate |
|---|---|---|---|
| SIMPLE | Không được | Không | Có, sau checkpoint |
| FULL | Bắt buộc phải có job | Có | Chỉ sau log backup |
| BULK_LOGGED | Có | Không, cho khoảng chứa bulk operation | Chỉ sau log backup |

Cạm bẫy phổ biến nhất trong thực tế: đặt FULL nhưng **không** có job `BACKUP LOG`. Kết quả là log tăng đến khi hết đĩa, và khi đó database dừng nhận write — một sự cố hoàn toàn phòng được.

### 7.4 Accelerated Database Recovery (ADR)

Từ SQL Server 2019, ADR thay đổi cách rollback và recovery hoạt động: thay vì đọc lùi toàn bộ log của transaction dài, nó dùng **persistent version store (PVS)** để logical revert gần như tức thì.

```sql
ALTER DATABASE SalesDB SET ACCELERATED_DATABASE_RECOVERY = ON;
```

Ba lợi ích và một chi phí:

- Rollback của transaction lớn nhanh hơn nhiều.
- Thời gian recovery sau crash ổn định, ít phụ thuộc transaction đang mở.
- Log truncate được ngay cả khi có transaction dài (giải quyết đúng ca `ACTIVE_TRANSACTION` ở trên).
- Chi phí: PVS chiếm dung lượng trong chính database và thêm chút overhead khi ghi.

ADR còn là **điều kiện cho Optimized Locking của SQL Server 2025** — xem [transactions.md](transactions.md) và [sqlserver_2025.md](../modern/sqlserver_2025.md).

---

## 8. tempdb – tài nguyên dùng chung dễ thành điểm nghẽn

tempdb được tạo lại mỗi lần instance khởi động, và bị dùng bởi nhiều thứ hơn người ta tưởng:

| Người dùng tempdb | Ví dụ |
|---|---|
| User object | `#temp` table, table variable, table-valued parameter |
| Internal object | sort, hash join/aggregate spill, cursor, spool, LOB assembly |
| Version store | RCSI, snapshot isolation, online index rebuild, MARS, trigger |
| ADR PVS | (nằm trong user database, không phải tempdb — đừng nhầm) |

```sql
-- Ai đang chiếm tempdb, theo loại
SELECT
    SUM(unallocated_extent_page_count)        * 8 / 1024 AS FreeMB,
    SUM(user_object_reserved_page_count)      * 8 / 1024 AS UserObjectsMB,
    SUM(internal_object_reserved_page_count)  * 8 / 1024 AS InternalMB,
    SUM(version_store_reserved_page_count)    * 8 / 1024 AS VersionStoreMB
FROM tempdb.sys.dm_db_file_space_usage;

-- Theo session (tìm thủ phạm cụ thể)
SELECT
    s.session_id, s.login_name, s.program_name,
    su.user_objects_alloc_page_count     * 8 / 1024 AS UserObjMB,
    su.internal_objects_alloc_page_count * 8 / 1024 AS InternalMB
FROM tempdb.sys.dm_db_session_space_usage su
JOIN sys.dm_exec_sessions s ON su.session_id = s.session_id
WHERE su.user_objects_alloc_page_count + su.internal_objects_alloc_page_count > 0
ORDER BY UserObjMB + InternalMB DESC;
```

### 8.1 Cấu hình tempdb

Điểm khởi đầu được chấp nhận rộng rãi:

1. Số data file = số logical CPU, tối đa 8; chỉ tăng thêm khi vẫn còn tranh chấp đo được.
2. Tất cả data file **cùng kích thước và cùng autogrowth tuyệt đối** — vì thuật toán cấp phát vòng tròn (proportional fill) chỉ cân bằng khi các file bằng nhau.
3. Đặt trên storage nhanh nhất, tách khỏi log của user database nếu được.
4. Pre-size đủ lớn để không phải grow trong giờ cao điểm.

Từ SQL Server 2019, **memory-optimized tempdb metadata** loại bỏ phần lớn tranh chấp latch trên system table của tempdb:

```sql
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;
-- Cần restart instance. Đọc kỹ giới hạn trước khi bật trên production.
```

SQL Server 2025 bổ sung **tempdb space resource governance**, cho phép chặn một workload đơn lẻ chiếm hết tempdb — hữu ích cho hệ multi-tenant. Chi tiết ở [sqlserver_2025.md](../modern/sqlserver_2025.md).

Phân biệt hai loại tranh chấp tempdb, vì cách chữa khác nhau:

| Triệu chứng | Nguyên nhân | Cách chữa |
|---|---|---|
| `PAGELATCH_UP` trên `2:1:1`, `2:1:3` | Tranh chấp PFS/SGAM khi tạo/hủy nhiều object tạm | Thêm/ cân bằng data file |
| `PAGELATCH_*` trên page hệ thống, kèm nhiều `#temp` ngắn | Tranh chấp metadata | Bật memory-optimized tempdb metadata |
| tempdb đầy do version store | Transaction đọc rất dài dưới RCSI/snapshot | Sửa transaction dài, tăng dung lượng |

---

## 9. Row format, kiểu dữ liệu và compression

### 9.1 Row nằm trên page như thế nào

```text
[status bits 2B][độ dài phần fixed][dữ liệu fixed-length]
[số cột][null bitmap][số cột variable][mảng offset][dữ liệu variable-length]
```

Suy ra mấy hệ quả rất thực dụng:

- Cột fixed-length luôn tốn đủ chỗ, dù NULL. `CHAR(50)` chứa `"a"` vẫn tốn 50 byte.
- Đổi `NULL` ↔ `NOT NULL` hay thêm cột có thể khiến row dài ra và gây page split.
- `NVARCHAR` tốn 2 byte/ký tự (trừ khi dùng collation có UTF-8), nên dùng `VARCHAR` với collation UTF-8 khi dữ liệu chủ yếu là ASCII và bạn đã cân nhắc kỹ.

| Kiểu | Kích thước | Ghi chú thực tế |
|---|---|---|
| `INT` / `BIGINT` | 4 / 8 B | Ưu tiên cho key |
| `CHAR(n)` / `NCHAR(n)` | n / 2n B | Chỉ dùng khi độ dài thật sự cố định |
| `VARCHAR(n)` / `NVARCHAR(n)` | dữ liệu + 2 B | Mặc định hợp lý cho chuỗi |
| `DATETIME2(p)` | 6–8 B | Thay cho `DATETIME` trong thiết kế mới; precision khai báo được |
| `DECIMAL(p,s)` | 5–17 B | Dùng cho tiền, không dùng `FLOAT` |
| `UNIQUEIDENTIFIER` | 16 B | Xem cảnh báo về clustered key ở [indexing.md](indexing.md) |
| `ROWVERSION` | 8 B | Token optimistic concurrency, không phải timestamp |
| `VARCHAR(MAX)` | off-row khi lớn | Có thể phá vỡ khả năng dùng một số tính năng |

### 9.2 Compression

```sql
-- ROW: lưu fixed-length như variable, bỏ padding
ALTER TABLE Sales.Orders REBUILD WITH (DATA_COMPRESSION = ROW);

-- PAGE: ROW + prefix + dictionary compression trong phạm vi page
ALTER TABLE Sales.Orders REBUILD WITH (DATA_COMPRESSION = PAGE);

-- Ước lượng trước khi làm
EXEC sp_estimate_data_compression_savings 'Sales', 'Orders', NULL, NULL, 'PAGE';
```

Compression đánh đổi CPU lấy I/O và RAM. Trên hệ thống nghẽn I/O, PAGE compression thường thắng rõ vì cùng lượng RAM chứa được nhiều row hơn. Trên hệ thống đã nghẽn CPU, nó có thể làm tệ hơn. Quy tắc thực dụng: bật PAGE cho bảng lớn ít update, ROW cho bảng OLTP update nhiều, và luôn đo trước/sau bằng `logical reads` và CPU time.

Với workload phân tích, columnstore cho tỉ lệ nén cao hơn hẳn hai mức trên — xem [indexing.md](indexing.md).

---

## 10. Compare – vị trí của SQL Server so với engine khác

| | SQL Server | PostgreSQL | Oracle | MySQL (InnoDB) |
|---|---|---|---|---|
| Page mặc định | 8KB | 8KB | 8KB | 16KB |
| Vùng cache chính | Buffer Pool | Shared Buffers | SGA Buffer Cache | Buffer Pool |
| Redo/WAL | Transaction log (`.ldf`) | WAL | Redo log | Redo log |
| Undo/version | tempdb version store, PVS (ADR) | Trong heap (MVCC) + vacuum | UNDO tablespace | Undo tablespace |
| Không gian tạm | tempdb (toàn instance) | temp file theo session | TEMP tablespace | tmpdir / ibtmp |
| MVCC mặc định | Không (locking); bật bằng RCSI | Có | Có | Có |
| Nhóm dung lượng | Filegroup | Tablespace | Tablespace | Tablespace |

Khác biệt quan trọng nhất về mặt tư duy: **PostgreSQL và Oracle mặc định là MVCC, SQL Server mặc định là locking**. Một ứng dụng port từ PostgreSQL sang SQL Server mà không bật RCSI sẽ gặp blocking mà nó chưa từng thấy ở nguồn. Chi tiết ở [transactions.md](transactions.md).

---

## 11. Trade-offs cần quyết định có ý thức

| Quyết định | Được | Mất | Cách chọn |
|---|---|---|---|
| `max server memory` cao | Ít physical read, PLE tốt | OS/thành phần khác thiếu RAM, có thể swap | Chừa cho OS rồi kiểm chứng bằng PLE & Memory Grants Pending |
| Nhiều data file tempdb | Giảm tranh chấp allocation | Nhiều file phải quản lý, phải giữ đồng đều | Bắt đầu = số core (max 8), tăng khi còn đo được tranh chấp |
| PAGE compression | Ít I/O, cache hiệu quả hơn | CPU cao hơn khi đọc/ghi | Bảng lớn, ít update, hệ nghẽn I/O |
| Nhiều filegroup | Piecemeal restore, tách vòng đời dữ liệu | Backup/restore phức tạp hơn | Chỉ khi có nhu cầu restore hoặc partition thật |
| ADR bật | Rollback/recovery nhanh, log truncate được | Tốn chỗ cho PVS, chút overhead ghi | Bật nếu có transaction dài hoặc cần RTO ổn định; bắt buộc nếu muốn Optimized Locking |
| BULK_LOGGED trong ETL | Log nhỏ hơn nhiều khi bulk load | Mất PITR trong khoảng đó | Chỉ trong cửa sổ ETL, và chụp log backup ngay trước/sau |

---

## 12. Real-world – triage 15 phút đầu

Khi có báo "database chậm", thứ tự dưới đây cho câu trả lời nhanh nhất về *loại* vấn đề:

```sql
-- 1. Đang có gì chạy và đang chờ gì
SELECT r.session_id, r.status, r.wait_type, r.wait_time, r.blocking_session_id,
       r.cpu_time, r.logical_reads, r.command,
       SUBSTRING(t.text, (r.statement_start_offset/2)+1, 200) AS Stmt
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID
ORDER BY r.cpu_time DESC;

-- 2. Wait tích lũy từ lần reset gần nhất
SELECT TOP 15
    wait_type,
    wait_time_ms / 1000.0                              AS WaitSec,
    (wait_time_ms - signal_wait_time_ms) / 1000.0       AS ResourceSec,
    signal_wait_time_ms / 1000.0                        AS SignalSec,
    waiting_tasks_count,
    CAST(100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) AS Pct
FROM sys.dm_os_wait_stats
WHERE waiting_tasks_count > 0
  AND wait_type NOT IN (
      'SLEEP_TASK','BROKER_TO_FLUSH','BROKER_TASK_STOP','CLR_AUTO_EVENT',
      'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
      'HADR_FILESTREAM_IOMGR_IOCOMPLETION','HADR_WORK_QUEUE','HADR_TIMER_TASK',
      'LAZYWRITER_SLEEP','LOGMGR_QUEUE','ONDEMAND_TASK_QUEUE','PARALLEL_REDO_WORKER_WAIT_WORK',
      'REQUEST_FOR_DEADLOCK_SEARCH','RESOURCE_QUEUE','SERVER_IDLE_CHECK',
      'SLEEP_DBSTARTUP','SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY',
      'SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP','SLEEP_SYSTEMTASK','SLEEP_TEMPDBSTARTUP',
      'SP_SERVER_DIAGNOSTICS_SLEEP','SQLTRACE_BUFFER_FLUSH','SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
      'SQLTRACE_WAIT_ENTRIES','WAITFOR','WAIT_XTP_HOST_WAIT','XE_DISPATCHER_WAIT',
      'XE_TIMER_EVENT','CHECKPOINT_QUEUE','DBMIRROR_EVENTS_QUEUE','BROKER_EVENTHANDLER'
  )
ORDER BY wait_time_ms DESC;

-- 3. Độ trễ I/O theo file (tách data vs log)
SELECT
    DB_NAME(vfs.database_id)                            AS DbName,
    mf.name, mf.type_desc,
    vfs.num_of_reads, vfs.num_of_writes,
    CASE WHEN vfs.num_of_reads  > 0 THEN vfs.io_stall_read_ms  / vfs.num_of_reads  END AS AvgReadMs,
    CASE WHEN vfs.num_of_writes > 0 THEN vfs.io_stall_write_ms / vfs.num_of_writes END AS AvgWriteMs
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
JOIN sys.master_files mf
  ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
ORDER BY vfs.io_stall_read_ms + vfs.io_stall_write_ms DESC;
```

Bảng đọc kết quả:

| Wait nổi bật | Kết luận sơ bộ | Đi tiếp tới |
|---|---|---|
| `PAGEIOLATCH_SH/EX` | Thiếu RAM hoặc storage đọc chậm | Mục 5, và tuning query để giảm reads |
| `WRITELOG` | Log volume chậm hoặc commit quá nhiều | Mục 7 |
| `LCK_M_*` | Blocking do thiết kế transaction/isolation | [transactions.md](transactions.md) |
| `RESOURCE_SEMAPHORE` | Memory grant cạnh tranh | [query_optimization.md](../performance/query_optimization.md) |
| `CXPACKET` / `CXCONSUMER` | Song song hóa lệch, thường là hệ quả chứ không phải nguyên nhân | Kiểm tra MAXDOP, cost threshold, và cardinality estimate |
| `SOS_SCHEDULER_YIELD` | CPU pressure | Giảm CPU của top query |
| `PAGELATCH_UP` trên tempdb | Tranh chấp allocation tempdb | Mục 8 |
| `THREADPOOL` | Hết worker thread, thường do blocking lan rộng | Xử lý blocking trước, đừng tăng max worker threads |

`sys.dm_os_wait_stats` là số liệu **tích lũy từ lần khởi động/reset**, nên nó mô tả cả quá khứ xa. Khi cần đo một cửa sổ cụ thể, chụp hai lần rồi lấy hiệu — cách làm và script ở [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md).

---

## 13. Checklist cấu hình instance mới

```text
Bộ nhớ & CPU
□ max server memory đặt tường minh, chừa phần cho OS
□ MAXDOP đặt theo số core mỗi NUMA node (không để 0 trên máy nhiều core)
□ Cost threshold for parallelism nâng lên khỏi mặc định 5 (thường 30–50)
□ Optimize for ad hoc workloads = 1 nếu có nhiều ad-hoc SQL

Storage
□ Data / log / tempdb tách volume nếu hạ tầng cho phép
□ Instant File Initialization bật (Windows: Perform Volume Maintenance Tasks)
□ Autogrowth theo MB tuyệt đối, không theo phần trăm
□ tempdb: nhiều file bằng nhau, pre-size đủ lớn

Độ bền & phục hồi
□ Recovery model đúng ý định, và FULL thì phải có job BACKUP LOG
□ CHECKSUM bật cho page verify; backup dùng WITH CHECKSUM
□ DBCC CHECKDB có lịch chạy và có alert khi lỗi
□ Cân nhắc ADR nếu có transaction dài hoặc cần RTO ổn định

Quan sát
□ Query Store bật cho database production
□ Baseline wait stats / file I/O được thu định kỳ, không chỉ xem lúc có sự cố
□ Alert: log đầy, backup trễ, suspect_pages, failed login
```

---

## 14. Ghi chú – chủ đề tiếp theo

- [tsql_advanced.md](tsql_advanced.md): CTE, window function, MERGE, JSON, temporal table, error handling, dynamic SQL.
- [indexing.md](indexing.md): clustered/nonclustered, columnstore, covering, statistics, đọc execution plan.
- [transactions.md](transactions.md): isolation level, lock, deadlock, RCSI, Optimized Locking.
- [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md): DMV, Extended Events, baseline, runbook triage.
- [linux_containers.md](../platform/linux_containers.md): chạy engine này trên Linux, Docker, Kubernetes.

Từ khóa mở rộng: NUMA soft affinity, resource governor, buffer pool extension, In-Memory OLTP checkpoint file, ADR persistent version store, `sys.dm_exec_query_memory_grants`.

---

*Cập nhật lần cuối: 2026-07-30*
