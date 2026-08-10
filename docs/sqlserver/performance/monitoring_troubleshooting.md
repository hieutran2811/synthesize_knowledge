---
title: "SQL Server Monitoring & Troubleshooting"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 0
---
# SQL Server Monitoring & Troubleshooting

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Architecture](../fundamentals/architecture.md), [Query Optimization](query_optimization.md). Đọc tiếp: [Partitioning](partitioning.md).

---

## 1. Vấn đề: không có baseline thì không có chẩn đoán

Câu hỏi "database có chậm không?" không trả lời được nếu không biết bình thường nó thế nào. Đây là lý do phần lớn sự cố database mất nhiều giờ để chẩn đoán: đội vận hành mở DMV đúng lúc sự cố, thấy vài con số, nhưng **không có gì để so sánh**.

Vì vậy monitoring SQL Server chia làm ba tầng, và cả ba đều cần:

| Tầng | Trả lời | Công cụ |
|---|---|---|
| **Baseline định kỳ** | Bình thường là thế nào? | Job thu DMV vào bảng, Query Store, Prometheus/Grafana |
| **Sự kiện có mục đích** | Chuyện gì xảy ra lúc đó? | Extended Events, blocked process report, deadlock graph |
| **Điều tra tại thời điểm** | Hiện tại đang gì? | `sys.dm_exec_requests`, `sp_WhoIsActive` |

Sai lầm thường gặp: chỉ có tầng thứ ba. Khi đó mọi sự cố đều phải chẩn đoán từ đầu, và các sự cố đã kết thúc thì không bao giờ tìm ra nguyên nhân.

---

## 2. Bản đồ DMV cần biết

```sql
-- Đang chạy gì (ảnh chụp hiện tại)
sys.dm_exec_requests            -- request đang thực thi: wait, blocking, cpu, reads
sys.dm_exec_sessions            -- session (kể cả đang sleeping)
sys.dm_exec_connections         -- kết nối, địa chỉ client, protocol
sys.dm_os_waiting_tasks         -- task đang chờ, kèm resource_description
sys.dm_exec_query_memory_grants -- ai đang giữ / chờ memory grant

-- Tích lũy (từ lần restart / reset)
sys.dm_os_wait_stats            -- wait theo loại
sys.dm_exec_query_stats         -- thống kê theo statement trong plan cache
sys.dm_exec_procedure_stats     -- theo procedure
sys.dm_io_virtual_file_stats    -- I/O theo file
sys.dm_db_index_usage_stats     -- index được dùng thế nào
sys.dm_db_missing_index_*       -- gợi ý index
sys.dm_os_performance_counters  -- các counter nội bộ

-- Lịch sử bền (không mất khi restart)
sys.query_store_*               -- plan + runtime + wait theo query
msdb.dbo.backupset              -- lịch sử backup
msdb.dbo.suspect_pages          -- page nghi ngờ hỏng
sys.dm_db_tuning_recommendations -- đề xuất của automatic tuning
```

Ba đặc điểm phải nhớ khi đọc DMV:

1. **DMV tích lũy reset khi restart instance** (và `sys.dm_db_index_usage_stats` còn reset khi index của bảng thay đổi). Số liệu "từ đầu" luôn phải kèm `sqlserver_start_time`.
2. **`sys.dm_exec_query_stats` chỉ có query còn trong plan cache.** Query bị evict là mất số liệu — đây chính là lý do Query Store tồn tại.
3. **Số liệu là của cả instance**, nên trên máy nhiều database phải lọc theo `database_id`.

```sql
SELECT sqlserver_start_time, DATEDIFF(HOUR, sqlserver_start_time, SYSDATETIME()) AS UptimeHours
FROM sys.dm_os_sys_info;
```

---

## 3. Wait stats theo cửa sổ thời gian

Wait stats tích lũy trộn lẫn giờ cao điểm và ban đêm. Để đo một cửa sổ cụ thể, chụp hai lần rồi lấy hiệu:

```sql
-- Snapshot 1
IF OBJECT_ID('tempdb..#w1') IS NOT NULL DROP TABLE #w1;
SELECT wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
INTO #w1 FROM sys.dm_os_wait_stats;

WAITFOR DELAY '00:05:00';    -- cửa sổ quan sát

-- Delta
SELECT TOP 20
    w2.wait_type,
    w2.waiting_tasks_count - w1.waiting_tasks_count                  AS Waits,
    (w2.wait_time_ms - w1.wait_time_ms) / 1000.0                     AS WaitSec,
    (w2.wait_time_ms - w1.wait_time_ms
     - (w2.signal_wait_time_ms - w1.signal_wait_time_ms)) / 1000.0   AS ResourceSec,
    (w2.signal_wait_time_ms - w1.signal_wait_time_ms) / 1000.0       AS SignalSec,
    CASE WHEN w2.waiting_tasks_count - w1.waiting_tasks_count > 0
         THEN (w2.wait_time_ms - w1.wait_time_ms) * 1.0
              / (w2.waiting_tasks_count - w1.waiting_tasks_count) END AS AvgMsPerWait
FROM sys.dm_os_wait_stats w2
JOIN #w1 w1 ON w1.wait_type = w2.wait_type
WHERE w2.wait_time_ms - w1.wait_time_ms > 0
  AND w2.wait_type NOT IN (
      'SLEEP_TASK','LAZYWRITER_SLEEP','LOGMGR_QUEUE','CHECKPOINT_QUEUE','XE_TIMER_EVENT',
      'XE_DISPATCHER_WAIT','REQUEST_FOR_DEADLOCK_SEARCH','SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
      'BROKER_TASK_STOP','BROKER_TO_FLUSH','DIRTY_PAGE_POLL','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
      'SP_SERVER_DIAGNOSTICS_SLEEP','WAITFOR','SLEEP_SYSTEMTASK','DISPATCHER_QUEUE_SEMAPHORE',
      'PARALLEL_REDO_WORKER_WAIT_WORK','HADR_WORK_QUEUE','FT_IFTS_SCHEDULER_IDLE_WAIT',
      'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP','QDS_ASYNC_QUEUE','WAIT_XTP_HOST_WAIT'
  )
ORDER BY WaitSec DESC;
```

Cột `AvgMsPerWait` thường hữu ích hơn tổng: 100.000 lần chờ 0.1ms là bình thường, 50 lần chờ 4 giây là sự cố — nhưng tổng thời gian của hai trường hợp giống nhau.

### 3.1 Bảng tra wait phổ biến

| Wait | Nghĩa | Hướng đi |
|---|---|---|
| `PAGEIOLATCH_SH/EX` | Chờ đọc page từ disk | Thiếu RAM hoặc storage chậm; giảm logical reads |
| `PAGELATCH_UP/EX` | Page đã trong RAM, tranh chấp latch | Hot page: tempdb allocation, last-page insert |
| `WRITELOG` | Chờ log xuống disk | Log storage; hoặc quá nhiều commit nhỏ |
| `LCK_M_*` | Chờ lock | Blocking — [transactions.md](../fundamentals/transactions.md) |
| `RESOURCE_SEMAPHORE` | Chờ memory grant | [query_optimization.md](query_optimization.md) mục 6 |
| `RESOURCE_SEMAPHORE_QUERY_COMPILE` | Chờ bộ nhớ để compile | Quá nhiều ad-hoc SQL cần compile |
| `SOS_SCHEDULER_YIELD` | Chờ CPU (đã có resource) | CPU pressure |
| `THREADPOOL` | Hết worker thread | Thường là hệ quả của blocking lan rộng |
| `CXPACKET` / `CXCONSUMER` | Trao đổi giữa thread song song | Triệu chứng; xem estimate và MAXDOP |
| `ASYNC_NETWORK_IO` | Chờ **client** nhận dữ liệu | Hầu như luôn là lỗi phía ứng dụng, không phải database |
| `HADR_SYNC_COMMIT` | Chờ secondary xác nhận (Always On sync) | Độ trễ mạng/secondary — [ha_dr.md](../administration/ha_dr.md) |
| `BACKUPIO` / `BACKUPBUFFER` | I/O của backup | Đích backup chậm |
| `IO_COMPLETION` | I/O không phải data page (sort, backup, log read) | Storage |
| `CMEMTHREAD` | Tranh chấp memory object | Thường do plan cache churn |

`ASYNC_NETWORK_IO` đáng nói riêng vì nó bị hiểu sai nhiều nhất: nó **không** nghĩa là mạng chậm, mà là SQL Server đã có dữ liệu và đang chờ client đọc hết. Nguyên nhân điển hình: ứng dụng `SELECT` cả triệu row rồi xử lý từng row trong vòng lặp Java, hoặc fetch size quá nhỏ. Cách chữa nằm ở phía ứng dụng ([jdbc_java.md](../integration/jdbc_java.md)).

---

## 4. Extended Events – thay thế cho SQL Trace

Extended Events (XEvents) là cơ chế tracing hiện tại; SQL Profiler/SQL Trace đã deprecated. Ưu điểm: overhead thấp hơn nhiều, cấu hình linh hoạt, có thể ghi ra file để phân tích sau.

### 4.1 Cấu trúc một session

```text
Event      : cái gì xảy ra (sql_batch_completed, rpc_completed, lock_deadlock...)
Predicate  : lọc — QUAN TRỌNG NHẤT, quyết định overhead
Action     : thông tin thêm kèm mỗi event (sql_text, session_id, plan_handle...)
Target     : nơi ghi (event_file, ring_buffer, histogram, event_counter)
```

### 4.2 Các session dùng thường xuyên

```sql
-- (1) Query chậm: chỉ ghi query vượt ngưỡng
CREATE EVENT SESSION [SlowQueries] ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    ACTION (sqlserver.sql_text, sqlserver.database_name, sqlserver.username,
            sqlserver.client_hostname, sqlserver.session_id)
    WHERE duration > 3000000        -- micro giây → 3 giây
),
ADD EVENT sqlserver.rpc_completed (
    ACTION (sqlserver.sql_text, sqlserver.database_name, sqlserver.username)
    WHERE duration > 3000000
)
ADD TARGET package0.event_file (
    SET filename = N'slow_queries.xel', max_file_size = 128, max_rollover_files = 5
)
WITH (MAX_MEMORY = 8MB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
      MAX_DISPATCH_LATENCY = 30 SECONDS, STARTUP_STATE = ON);

ALTER EVENT SESSION [SlowQueries] ON SERVER STATE = START;

-- (2) Deadlock ra file (system_health là ring buffer, sẽ bị cuốn mất)
CREATE EVENT SESSION [Deadlocks] ON SERVER
ADD EVENT sqlserver.xml_deadlock_report
ADD TARGET package0.event_file (SET filename = N'deadlocks.xel', max_file_size = 32)
WITH (STARTUP_STATE = ON);
ALTER EVENT SESSION [Deadlocks] ON SERVER STATE = START;

-- (3) Blocked process report (cần bật threshold ở sp_configure trước)
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'blocked process threshold (s)', 20; RECONFIGURE;

CREATE EVENT SESSION [BlockedProcess] ON SERVER
ADD EVENT sqlserver.blocked_process_report
ADD TARGET package0.event_file (SET filename = N'blocked_process.xel', max_file_size = 64)
WITH (STARTUP_STATE = ON);
ALTER EVENT SESSION [BlockedProcess] ON SERVER STATE = START;

-- (4) Đếm lỗi theo error number (histogram: rất nhẹ)
CREATE EVENT SESSION [ErrorHistogram] ON SERVER
ADD EVENT sqlserver.error_reported (WHERE severity >= 11)
ADD TARGET package0.histogram (SET filtering_event_name = N'sqlserver.error_reported',
                               source = N'error_number', source_type = 0)
WITH (STARTUP_STATE = ON);
ALTER EVENT SESSION [ErrorHistogram] ON SERVER STATE = START;
```

### 4.3 Đọc file XEvents bằng T-SQL

```sql
WITH Raw AS (
    SELECT CAST(event_data AS XML) AS x
    FROM sys.fn_xe_file_target_read_file('slow_queries*.xel', NULL, NULL, NULL)
)
SELECT
    x.value('(event/@timestamp)[1]', 'datetime2')                                AS EventTime,
    x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000          AS DurationMs,
    x.value('(event/data[@name="cpu_time"]/value)[1]', 'bigint') / 1000          AS CpuMs,
    x.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint')            AS LogicalReads,
    x.value('(event/action[@name="database_name"]/value)[1]', 'nvarchar(128)')    AS DbName,
    x.value('(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(128)')  AS ClientHost,
    x.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)')        AS SqlText
FROM Raw
ORDER BY EventTime DESC;
```

### 4.4 Quy tắc tránh tự gây sự cố bằng XEvents

| Quy tắc | Vì sao |
|---|---|
| Luôn có predicate hẹp | Session không lọc trên hệ tải cao có thể sinh GB/phút và làm chậm chính instance |
| Dùng `event_file`, không dùng `ring_buffer` cho dữ liệu cần giữ | Ring buffer bị cuốn mất và khó đọc khi lớn |
| `ALLOW_SINGLE_EVENT_LOSS` | `NO_EVENT_LOSS` khiến engine **chờ** khi buffer đầy — có thể làm treo workload |
| Đặt `max_file_size` và `max_rollover_files` | Không giới hạn = có ngày đầy đĩa |
| Tránh action đắt cho event tần suất cao | `sql_text`, `plan_handle` không miễn phí |
| Bỏ `sql_statement_starting` trừ khi thật cần | Event *starting* nhiều gấp nhiều lần *completed* và không có duration |

---

## 5. Baseline: thu DMV vào bảng

Query Store lo phần query. Phần còn lại (wait, file I/O, cấu hình, kích thước) cần một job đơn giản.

```sql
CREATE SCHEMA Baseline;
GO

CREATE TABLE Baseline.WaitStats (
    CollectedAt         DATETIME2(0) NOT NULL,
    wait_type           NVARCHAR(60) NOT NULL,
    waiting_tasks_count BIGINT       NOT NULL,
    wait_time_ms        BIGINT       NOT NULL,
    signal_wait_time_ms BIGINT       NOT NULL,
    CONSTRAINT PK_WaitStats PRIMARY KEY CLUSTERED (CollectedAt, wait_type)
);

CREATE TABLE Baseline.FileStats (
    CollectedAt      DATETIME2(0) NOT NULL,
    database_name    SYSNAME      NOT NULL,
    file_name        SYSNAME      NOT NULL,
    type_desc        NVARCHAR(60) NOT NULL,
    num_of_reads     BIGINT       NOT NULL,
    num_of_writes    BIGINT       NOT NULL,
    io_stall_read_ms BIGINT       NOT NULL,
    io_stall_write_ms BIGINT      NOT NULL,
    size_mb          BIGINT       NOT NULL,
    CONSTRAINT PK_FileStats PRIMARY KEY CLUSTERED (CollectedAt, database_name, file_name)
);
GO

CREATE OR ALTER PROCEDURE Baseline.usp_Collect
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(0) = DATEADD(MINUTE, -DATEPART(MINUTE, SYSDATETIME()) % 5, SYSDATETIME());

    INSERT INTO Baseline.WaitStats (CollectedAt, wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms)
    SELECT @now, wait_type, waiting_tasks_count, wait_time_ms, signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE waiting_tasks_count > 0;

    INSERT INTO Baseline.FileStats (CollectedAt, database_name, file_name, type_desc,
                                    num_of_reads, num_of_writes, io_stall_read_ms, io_stall_write_ms, size_mb)
    SELECT @now, DB_NAME(vfs.database_id), mf.name, mf.type_desc,
           vfs.num_of_reads, vfs.num_of_writes, vfs.io_stall_read_ms, vfs.io_stall_write_ms,
           vfs.size_on_disk_bytes / 1048576
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id;

    DELETE FROM Baseline.WaitStats WHERE CollectedAt < DATEADD(DAY, -90, SYSDATETIME());
    DELETE FROM Baseline.FileStats WHERE CollectedAt < DATEADD(DAY, -90, SYSDATETIME());
END
GO
```

Lập SQL Agent job chạy `Baseline.usp_Collect` mỗi 5 phút. Sau đó so sánh bất kỳ cửa sổ nào:

```sql
-- Top wait trong khoảng 09:00–10:00 hôm nay so với cùng giờ hôm qua
WITH Delta AS (
    SELECT wait_type, CAST(CollectedAt AS DATE) AS D,
           MAX(wait_time_ms) - MIN(wait_time_ms) AS WaitMs
    FROM Baseline.WaitStats
    WHERE DATEPART(HOUR, CollectedAt) = 9
      AND CAST(CollectedAt AS DATE) IN (CAST(SYSDATETIME() AS DATE),
                                        DATEADD(DAY,-1,CAST(SYSDATETIME() AS DATE)))
    GROUP BY wait_type, CAST(CollectedAt AS DATE)
)
SELECT wait_type,
       MAX(CASE WHEN D = CAST(SYSDATETIME() AS DATE) THEN WaitMs END) AS Today,
       MAX(CASE WHEN D <  CAST(SYSDATETIME() AS DATE) THEN WaitMs END) AS Yesterday
FROM Delta
GROUP BY wait_type
ORDER BY Today DESC;
```

Câu truy vấn này là thứ biến "cảm giác hôm nay chậm" thành bằng chứng trong hai phút.

---

## 6. Điều tra tại thời điểm sự cố

### 6.1 Ảnh chụp toàn cảnh

```sql
SELECT
    r.session_id, s.login_name, s.host_name, s.program_name,
    r.status, r.command,
    r.wait_type, r.wait_resource, r.wait_time / 1000.0 AS WaitSec,
    r.blocking_session_id,
    r.cpu_time, r.logical_reads, r.reads, r.writes,
    r.granted_query_memory * 8 / 1024                  AS GrantMB,
    r.percent_complete, r.estimated_completion_time / 60000.0 AS EstMinLeft,
    DB_NAME(r.database_id)                             AS DbName,
    r.open_transaction_count,
    SUBSTRING(t.text, (r.statement_start_offset/2)+1,
        CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
             ELSE (r.statement_end_offset - r.statement_start_offset)/2 + 1 END) AS CurrentStatement
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id <> @@SPID AND s.is_user_process = 1
ORDER BY r.cpu_time DESC;
```

`percent_complete` và `estimated_completion_time` chỉ có giá trị cho một số command (BACKUP, RESTORE, DBCC CHECKDB, index rebuild offline, rollback) — nhưng với đúng những command đó thì nó là thông tin quý nhất khi phải trả lời "còn bao lâu nữa".

Trong thực tế, `sp_WhoIsActive` của Adam Machanic gói gọn phần lớn thông tin này và nên có sẵn trên mọi instance:

```sql
EXEC sp_WhoIsActive @get_plans = 1, @get_transaction_info = 1,
                    @get_task_info = 2, @find_block_leaders = 1;
```

### 6.2 Tiến độ của một query đang chạy

```sql
-- Operator nào đang xử lý, đã ra bao nhiêu row (2014+)
SELECT
    p.session_id, p.physical_operator_name, p.node_id,
    p.row_count, p.estimate_row_count,
    CAST(100.0 * p.row_count / NULLIF(p.estimate_row_count,0) AS DECIMAL(6,2)) AS PctOfEstimate,
    p.elapsed_time_ms
FROM sys.dm_exec_query_profiles p
WHERE p.session_id = 62
ORDER BY p.node_id;
```

`PctOfEstimate` vượt xa 100% là bằng chứng trực tiếp rằng estimate sai — thông tin cần cho bước tuning ở [query_optimization.md](query_optimization.md).

### 6.3 Rollback: chờ hay không chờ

Khi `KILL` một transaction lớn, nó rollback và không thể dừng lại. Kiểm tra tiến độ:

```sql
SELECT session_id, command, percent_complete,
       estimated_completion_time / 60000.0 AS EstMinLeft
FROM sys.dm_exec_requests
WHERE command IN ('KILLED/ROLLBACK', 'ROLLBACK');
```

Nếu ADR đã bật ([architecture.md](../fundamentals/architecture.md) mục 7.4), rollback nhanh hơn rất nhiều — đây là một trong những lý do vận hành mạnh nhất để bật ADR.

---

## 7. Kiểm tra tính toàn vẹn dữ liệu

Hiệu năng không có nghĩa nếu dữ liệu hỏng. `DBCC CHECKDB` là kiểm tra không thể thay thế.

```sql
-- Kiểm tra đầy đủ (nên chạy trên bản restore ở server khác nếu bảng quá lớn)
DBCC CHECKDB('SalesDB') WITH NO_INFOMSGS, ALL_ERRORMSGS, DATA_PURITY;

-- Nhanh hơn cho cửa sổ ngắn: bỏ kiểm tra non-clustered index
DBCC CHECKDB('SalesDB') WITH PHYSICAL_ONLY, NO_INFOMSGS;

-- Lần chạy CHECKDB sạch gần nhất của từng database
SELECT name,
       DATABASEPROPERTYEX(name, 'Updateability') AS Updateability,
       (SELECT last_known_good FROM sys.dm_db_page_info(DB_ID(name),1,9,'LIMITED')) AS Ignore
FROM sys.databases WHERE database_id > 4;
-- Cách thực tế hơn: đọc từ DBCC DBINFO hoặc lưu kết quả job vào bảng
```

```sql
-- Page nghi ngờ hỏng (823/824/829)
SELECT DB_NAME(database_id) AS DbName, file_id, page_id,
       event_type,      -- 1 = lỗi 823/824 ngoài bad checksum, 2 = bad checksum, 3 = torn page, ...
       error_count, last_update_date
FROM msdb.dbo.suspect_pages
ORDER BY last_update_date DESC;
```

Nguyên tắc vận hành:

| Nguyên tắc | Lý do |
|---|---|
| `PAGE_VERIFY CHECKSUM` bật trên mọi database | Không có nó, corruption âm thầm |
| `BACKUP ... WITH CHECKSUM` | Phát hiện corruption ngay lúc backup, không phải lúc restore |
| CHECKDB có lịch và có **alert khi lỗi** | Job chạy mà không ai đọc log = không có kiểm tra |
| Không dùng `REPAIR_ALLOW_DATA_LOSS` như phản xạ đầu tiên | Nó xóa dữ liệu để làm database consistent; restore từ backup gần như luôn tốt hơn |
| Kiểm tra `suspect_pages` định kỳ | Cho biết corruption đã bắt đầu trước khi CHECKDB tới kỳ |

```sql
ALTER DATABASE SalesDB SET PAGE_VERIFY CHECKSUM;
```

---

## 8. Giám sát ngoài instance: Prometheus & Grafana

Với hạ tầng container/K8s, cách tích hợp phổ biến là exporter Prometheus, rồi dashboard Grafana — trùng khớp với những gì đã mô tả trong package [prometheus_grafana](../../prometheus_grafana/roadmap.md).

```yaml
# docker-compose: sql_exporter thu metric từ SQL Server
services:
  sql-exporter:
    image: burningalchemist/sql_exporter:latest
    environment:
      SQLEXPORTER_TARGET_DSN: "sqlserver://exporter:${PW}@mssql:1433"
    ports: ["9399:9399"]
    volumes:
      - ./sql_exporter.yml:/etc/sql_exporter/sql_exporter.yml:ro
```

Bộ metric tối thiểu nên có dashboard và alert:

| Metric | Nguồn | Alert khi |
|---|---|---|
| Batch requests/sec | `sys.dm_os_performance_counters` | Đột biến hoặc sụt về 0 |
| Page life expectancy | performance counters | Giảm mạnh so với baseline |
| Memory grants pending | performance counters | > 0 kéo dài |
| Wait time theo loại (delta) | `sys.dm_os_wait_stats` | Một loại tăng bất thường |
| Avg read/write latency theo file | `sys.dm_io_virtual_file_stats` | > 20ms (data), > 5ms (log) kéo dài |
| Blocked sessions | `sys.dm_exec_requests` | > 0 quá 30 giây |
| Longest open transaction (s) | `sys.dm_tran_active_transactions` | > 300 |
| Log space used % | `sys.dm_db_log_space_usage` | > 80% |
| Log reuse wait | `sys.databases` | `LOG_BACKUP` kéo dài |
| tempdb free MB | `dm_db_file_space_usage` | Dưới ngưỡng |
| Time since last backup (full/log) | `msdb.dbo.backupset` | Vượt RPO |
| Failed logins/min | XEvents hoặc error log | Đột biến (dò mật khẩu) |
| AG send/redo queue | `dm_hadr_database_replica_states` | Vượt ngưỡng RPO |
| Query Store: regressed query count | `sys.query_store_*` | Tăng sau deploy |

Ba alert quan trọng nhất — và cũng bị bỏ quên nhiều nhất — là ba dòng cuối phần trên cùng: **thời gian kể từ backup gần nhất**, **transaction mở lâu nhất**, và **log reuse wait**. Chúng bắt được các sự cố có hậu quả lớn nhất (mất dữ liệu, hết đĩa log) trước khi chúng thành sự cố.

---

## 9. Error log

```sql
-- Đọc error log bằng T-SQL
EXEC sys.sp_readerrorlog 0, 1, N'Error';      -- log hiện tại, SQL log, chứa 'Error'
EXEC sys.sp_readerrorlog 0, 1, N'Login failed';

-- Vòng log để file không quá lớn (đồng thời tăng số file giữ lại)
EXEC sys.sp_cycle_errorlog;
```

Những dòng trong error log luôn phải xử lý:

| Thông báo | Nghĩa |
|---|---|
| `SQL Server has encountered N occurrence(s) of I/O requests taking longer than 15 seconds` | Storage có vấn đề nghiêm trọng |
| `Error: 823/824/825` | Corruption (825 = đọc lại thành công sau khi retry — vẫn là cảnh báo sớm) |
| `The transaction log for database ... is full` | Sắp/đã dừng nhận write |
| `A significant part of sql server process memory has been paged out` | OS đang swap SQL Server ra đĩa |
| `Login failed for user ...` dồn dập | Có thể là dò mật khẩu, hoặc app cấu hình sai sau deploy |
| `New queries assigned to process on Node N have not been picked up` | Nghẽn scheduler/THREADPOOL |

---

## 10. Trade-offs của monitoring

| Lựa chọn | Được | Mất | Khi nào |
|---|---|---|---|
| XEvents chi tiết, ít lọc | Thấy mọi thứ | Overhead lớn, đầy đĩa | Chỉ trong cửa sổ điều tra ngắn |
| XEvents có predicate hẹp | Overhead thấp, chạy thường trực | Có thể bỏ sót ca ngoài ngưỡng | Mặc định cho production |
| Query Store `QUERY_CAPTURE_MODE = ALL` | Không bỏ sót query nào | Storage lớn, overhead cao hơn | Môi trường test / điều tra |
| Query Store `AUTO` | Cân bằng tốt | Bỏ query rất nhẹ | Mặc định cho production |
| Baseline mỗi 1 phút | Độ mịn cao | Nhiều dữ liệu | Hệ thống quan trọng |
| Baseline mỗi 5–15 phút | Vừa đủ để so sánh | Bỏ mất đột biến ngắn | Mặc định |
| CHECKDB đầy đủ trên production | An tâm nhất | Tốn I/O và CPU, cửa sổ dài | Database nhỏ/vừa |
| CHECKDB `PHYSICAL_ONLY` + full trên bản restore | Ít ảnh hưởng production, vẫn kiểm được | Phức tạp hơn về quy trình | Database lớn |

---

## 11. Runbook: "database chậm"

```text
[0–2 phút] Phân loại
□ sp_WhoIsActive (hoặc dm_exec_requests): có blocking không?
   → CÓ  : đi runbook blocking ở transactions.md mục 12
   → KHÔNG: tiếp
□ Wait nổi bật là gì (delta 1–2 phút)?
   → PAGEIOLATCH / IO_COMPLETION  → mục 3 + kiểm tra file latency
   → SOS_SCHEDULER_YIELD          → CPU: tìm top query theo cpu_time
   → RESOURCE_SEMAPHORE           → memory grant: query_optimization.md mục 6
   → WRITELOG                     → log storage hoặc commit quá nhiều
   → ASYNC_NETWORK_IO             → phía ứng dụng, không phải database
   → THREADPOOL                   → blocking lan rộng, xử lý root blocker

[2–10 phút] Khoanh vùng
□ Có phải chỉ một query/procedure? (Query Store 1 giờ gần nhất so với hôm qua)
□ Có deploy/thay đổi gì gần đây? (schema, index, compat level, patch, config)
□ Tài nguyên OS: CPU, RAM, disk latency có bất thường?
□ Có job nền đang chạy? (backup, CHECKDB, index rebuild, ETL)

[10–30 phút] Xử lý
□ Nguyên nhân là một query mới hồi quy → force plan tạm thời (query_optimization.md 4.3)
□ Nguyên nhân là job nền → hoãn/giới hạn job
□ Nguyên nhân là storage → làm việc với hạ tầng, giảm tải đọc tạm thời
□ Nguyên nhân là tempdb đầy → tìm session/transaction chiếm, xử lý

[Sau sự cố] Đóng vòng
□ Ghi timeline, bằng chứng, biện pháp, và biện pháp tạm cần bỏ khi nào
□ Thiếu alert nào để lần sau biết sớm hơn? Thêm ngay
□ Thiếu dữ liệu nào để chẩn đoán? Thêm vào baseline/XEvents
```

Nguyên tắc xuyên suốt: **thu bằng chứng trước khi can thiệp**. Một `KILL` giải quyết sự cố nhưng xóa luôn khả năng biết vì sao — nên chụp `sp_WhoIsActive`, plan, và wait vào bảng trước khi kill.

---

## 12. Ghi chú – chủ đề tiếp theo

- [partitioning.md](partitioning.md): quản lý bảng rất lớn, cửa sổ bảo trì.
- [backup_recovery.md](../administration/backup_recovery.md): alert backup, verify, `suspect_pages`.
- [ha_dr.md](../administration/ha_dr.md): giám sát Always On (send/redo queue).
- [linux_containers.md](../platform/linux_containers.md): giám sát khi engine chạy trong container/K8s.
- [prometheus_grafana](../../prometheus_grafana/roadmap.md): dựng dashboard và alert cho các metric ở mục 8.

Từ khóa mở rộng: `sys.dm_os_ring_buffers`, `sys.dm_os_memory_clerks`, Resource Governor, Data Collector/MDW, `sys.dm_db_page_info` (2019+), Query Store for secondary replicas, `sp_Blitz`/`sp_BlitzFirst` (First Responder Kit).

---

*Cập nhật lần cuối: 2026-07-30*
