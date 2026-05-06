# SQL Server Transactions, Locking & Isolation – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Transactions & Locking là gì?

**Transaction** là đơn vị công việc ACID (Atomicity, Consistency, Isolation, Durability). **Locking** là cơ chế SQL Server dùng để đảm bảo isolation giữa concurrent transactions.

```
ACID:
  Atomicity:    tất cả thành công hoặc tất cả rollback
  Consistency:  DB chuyển từ trạng thái hợp lệ này sang trạng thái hợp lệ khác
  Isolation:    transactions không "nhìn thấy" nhau's intermediate state
  Durability:   sau COMMIT, data persisted (ngay cả khi crash)
```

---

## How – Transaction Modes

```sql
-- Autocommit (default): mỗi statement là 1 transaction
INSERT INTO Orders VALUES (1, 100);  -- auto COMMIT

-- Explicit transaction
BEGIN TRANSACTION;  -- hoặc BEGIN TRAN
    UPDATE Accounts SET Balance = Balance - 500 WHERE AccountID = 1;
    UPDATE Accounts SET Balance = Balance + 500 WHERE AccountID = 2;

    IF @@ERROR <> 0
        ROLLBACK TRANSACTION;
    ELSE
        COMMIT TRANSACTION;

-- Savepoints (partial rollback)
BEGIN TRANSACTION;
    INSERT INTO Orders ...;
    SAVE TRANSACTION SavePoint1;   -- savepoint

    INSERT INTO OrderItems ...;

    IF @@ERROR <> 0
        ROLLBACK TRANSACTION SavePoint1;  -- rollback chỉ đến savepoint
        -- Transaction vẫn open!

    COMMIT TRANSACTION;

-- Implicit transactions (không khuyến khích)
SET IMPLICIT_TRANSACTIONS ON;
-- Mọi DML statement tự mở transaction
-- Phải explicit COMMIT/ROLLBACK

-- Nested transactions (chú ý: không true nested)
BEGIN TRAN;               -- @@TRANCOUNT = 1
    BEGIN TRAN;           -- @@TRANCOUNT = 2 (nested chỉ tăng counter)
        UPDATE ...;
    COMMIT TRAN;          -- @@TRANCOUNT = 1 (không thực sự commit)
COMMIT TRAN;              -- @@TRANCOUNT = 0 → thực sự commit
-- ROLLBACK ở bất kỳ level nào → rollback toàn bộ outer transaction!
```

---

## How – Lock Types & Hierarchy

```sql
-- Lock modes:
-- S  (Shared):     read lock, nhiều S locks cùng lúc
-- X  (Exclusive):  write lock, không compatible với S hoặc X khác
-- U  (Update):     dùng khi query sẽ update, tránh deadlock với S+X pattern
-- IS (Intent Shared):    intent để acquire S lock ở lower level
-- IX (Intent Exclusive): intent để acquire X lock ở lower level
-- SIX:             Shared + Intent Exclusive
-- Sch-S / Sch-M:  Schema stability/modification (ALTER TABLE)

-- Lock compatibility matrix (simplified):
--        S    X    U
--  S:   OK   No   OK
--  X:   No   No   No
--  U:   OK   No   No

-- Lock hierarchy: Database → Table → Page → Row
-- Intent locks: trước khi lock row, SQL acquires IX trên table + page

-- Xem current locks
SELECT
    tl.request_session_id AS SPID,
    tl.resource_type,
    tl.resource_description,
    tl.request_mode AS LockMode,
    tl.request_status,
    wt.wait_type,
    wt.wait_duration_ms,
    DB_NAME(tl.resource_database_id) AS DBName
FROM sys.dm_tran_locks tl
LEFT JOIN sys.dm_os_waiting_tasks wt
    ON tl.lock_owner_address = wt.resource_address
WHERE tl.resource_type <> 'DATABASE'
ORDER BY tl.request_session_id;
```

---

## How – Isolation Levels

```sql
-- 4 isolation levels (pessimistic locking):

-- 1. READ UNCOMMITTED: đọc dirty data (uncommitted changes)
-- Không acquire S locks khi đọc → không bị block
-- Dirty read, Non-repeatable read, Phantom read đều có thể xảy ra
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- NOLOCK hint = READ UNCOMMITTED cho table cụ thể
SELECT * FROM Orders WITH (NOLOCK);  -- thường xuyên dùng sai!

-- 2. READ COMMITTED (DEFAULT): chỉ đọc committed data
-- Acquire S lock khi đọc, release ngay sau khi đọc xong (không giữ đến end of tran)
-- Ngăn: Dirty read
-- Cho phép: Non-repeatable read, Phantom read
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 3. REPEATABLE READ: giữ S locks đến end of transaction
-- Ngăn: Dirty read, Non-repeatable read
-- Cho phép: Phantom read
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- 4. SERIALIZABLE: highest isolation, giữ range locks
-- Ngăn tất cả: Dirty read, Non-repeatable read, Phantom read
-- Nhưng: highest blocking, deadlock risk
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Optimistic isolation levels (row versioning, không dùng S locks):

-- 5. READ COMMITTED SNAPSHOT (RCSI): phiên bản row version của READ COMMITTED
-- Đọc phiên bản committed cuối cùng từ TempDB version store
-- Không block reads, không dirty reads
-- Khuyến khích: bật ở DB level
ALTER DATABASE SalesDB SET READ_COMMITTED_SNAPSHOT ON;

-- 6. SNAPSHOT ISOLATION: đọc snapshot của DB tại thời điểm BEGIN TRAN
-- Consistent view xuyên suốt transaction
-- Update conflict detection (optimistic)
ALTER DATABASE SalesDB SET ALLOW_SNAPSHOT_ISOLATION ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
```

### Isolation Level Comparison

```
Level                | Dirty | Non-repeatable | Phantom | Block reads
---------------------|-------|----------------|---------|------------
READ UNCOMMITTED     |  Yes  |      Yes       |   Yes   | No
READ COMMITTED       |  No   |      Yes       |   Yes   | Yes (momentary)
REPEATABLE READ      |  No   |      No        |   Yes   | Yes
SERIALIZABLE         |  No   |      No        |   No    | Yes (max)
READ COMMITTED SNAP  |  No   |      Yes       |   Yes   | No (optimistic)
SNAPSHOT             |  No   |      No        |   No    | No (optimistic)
```

---

## How – Blocking Detection & Resolution

```sql
-- Blocking: transaction A giữ lock, transaction B đang chờ

-- Tìm blocking chains
SELECT
    blocking.session_id  AS BlockingSession,
    blocked.session_id   AS BlockedSession,
    blocked.wait_type,
    blocked.wait_time    / 1000.0 AS WaitSeconds,
    SUBSTRING(blocking_sql.text, 1, 200) AS BlockingSQL,
    SUBSTRING(blocked_sql.text, 1, 200)  AS BlockedSQL
FROM sys.dm_exec_sessions blocking
JOIN sys.dm_exec_requests blocked  ON blocking.session_id = blocked.blocking_session_id
CROSS APPLY sys.dm_exec_sql_text(blocking.most_recent_sql_handle) AS blocking_sql
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle)              AS blocked_sql;

-- Xem full blocking chain
WITH BlockingChain AS (
    SELECT session_id, blocking_session_id, 0 AS Level,
           CAST(session_id AS VARCHAR(1000)) AS Chain
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0 AND session_id IN (
        SELECT DISTINCT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id > 0
    )
    UNION ALL
    SELECT r.session_id, r.blocking_session_id, bc.Level + 1,
           CAST(bc.Chain + ' → ' + CAST(r.session_id AS VARCHAR) AS VARCHAR(1000))
    FROM sys.dm_exec_requests r
    JOIN BlockingChain bc ON r.blocking_session_id = bc.session_id
)
SELECT * FROM BlockingChain ORDER BY Chain;

-- Kill blocking session (last resort)
KILL 55;  -- session_id

-- Lock timeout: tự raise error sau N ms
SET LOCK_TIMEOUT 5000;  -- 5 seconds, -1 = wait forever (default)
```

---

## How – Deadlock Detection & Prevention

```sql
-- Deadlock: A chờ B, B chờ A → SQL Server tự detect, chọn 1 victim, rollback

-- Xem deadlock graph (Extended Events)
-- Hoặc trace flag: DBCC TRACEON(1222, -1); -- detailed deadlock info in error log

-- Deadlock thông tin
SELECT
    xdr.value('@timestamp', 'datetime2') AS DeadlockTime,
    xdr.query('.') AS DeadlockGraph
FROM (
    SELECT CAST(target_data AS XML) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = 'system_health'
    AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(xdr);

-- Deadlock prevention best practices:
-- 1. Access objects trong cùng thứ tự (Transaction A và B đều: Table1 trước Table2)
-- 2. Giữ transaction ngắn nhất có thể
-- 3. Dùng RCSI/Snapshot isolation (read không lock write và ngược lại)
-- 4. Index tốt → lock ít rows hơn
-- 5. Tránh user interaction trong transaction
-- 6. Explicit deadlock priority
SET DEADLOCK_PRIORITY LOW;   -- session này là victim preferred
SET DEADLOCK_PRIORITY HIGH;  -- session này ít bị chọn làm victim

-- Retry logic cho deadlock (error 1205)
DECLARE @Retry INT = 3;
WHILE @Retry > 0
BEGIN
    BEGIN TRY
        BEGIN TRAN;
        -- ... your code ...
        COMMIT TRAN;
        SET @Retry = 0;  -- success
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        IF ERROR_NUMBER() = 1205  -- deadlock
        BEGIN
            SET @Retry -= 1;
            WAITFOR DELAY '00:00:00.100';  -- wait 100ms
        END
        ELSE
        BEGIN
            SET @Retry = 0;
            THROW;
        END
    END CATCH;
END;
```

---

## How – Row Versioning (RCSI & Snapshot)

```sql
-- Row versioning: khi row được update, old version stored in TempDB version store
-- Readers dùng old version → không block writers, writers không block readers

-- Bật RCSI (READ_COMMITTED_SNAPSHOT)
ALTER DATABASE SalesDB SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
-- ROLLBACK IMMEDIATE: rollback tất cả active transactions ngay lập tức (cẩn thận!)

-- RCSI vs Snapshot:
-- RCSI: mỗi statement thấy snapshot tại thời điểm statement bắt đầu
-- Snapshot: mỗi transaction thấy snapshot tại thời điểm transaction bắt đầu

-- Version store cleanup: SQL Agent job hoặc auto-cleanup
-- Xem version store usage
SELECT
    database_transaction_begin_time,
    database_transaction_type,
    database_transaction_log_bytes_used / 1024 / 1024 AS LogMB
FROM sys.dm_tran_active_transactions
JOIN sys.dm_tran_database_transactions ON ...;

-- TempDB version store size
SELECT
    SUM(version_store_reserved_page_count) * 8 / 1024 AS VersionStoreMB
FROM sys.dm_db_file_space_usage;

-- Snapshot write conflict (UPDATE CONFLICT)
-- T1: BEGIN SNAPSHOT TRAN, reads row version X
-- T2: updates same row, commits → version X+1
-- T1: tries to update same row → Error 3960: snapshot update conflict
-- → Application phải handle: retry hoặc re-read
```

---

## How – Optimistic vs Pessimistic Locking (Application Pattern)

```sql
-- Pessimistic: lock row trước khi read
SELECT * FROM Products WITH (UPDLOCK, ROWLOCK) WHERE ProductID = 1;
-- UPDLOCK: acquire U lock (không bị block bởi readers, blocks other UPDLOCK)
-- ROWLOCK: hint to prefer row-level locks (không escalate to page/table)

UPDATE Products SET Stock = Stock - 1 WHERE ProductID = 1;
COMMIT;

-- Optimistic: dùng version column (không lock)
-- Application: check version trước khi update
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    Name NVARCHAR(100),
    Stock INT,
    RowVersion ROWVERSION  -- hoặc dùng TIMESTAMP (synonym)
);

-- Read
SELECT @OldVersion = RowVersion FROM Products WHERE ProductID = 1;

-- Update: chỉ thành công nếu version chưa thay đổi
UPDATE Products
SET Stock = Stock - 1
WHERE ProductID = 1 AND RowVersion = @OldVersion;

IF @@ROWCOUNT = 0
    -- Conflict: someone else updated → application handles (retry/error)
    THROW 50001, 'Optimistic concurrency conflict', 1;
```

---

## Compare – Isolation Levels

| Level | Read Perf | Write Block | Use Case |
|-------|-----------|-------------|----------|
| READ UNCOMMITTED | Tốt nhất | Không block | Approximate reporting, không quan trọng consistency |
| READ COMMITTED | Tốt | Block momentarily | Default, general purpose |
| REPEATABLE READ | OK | Block | Cần consistent re-read trong transaction |
| SERIALIZABLE | Kém | Block nhiều | Banking, financial, critical consistency |
| RCSI (snapshot) | Tốt nhất | Không block readers | OLTP production (recommended) |
| SNAPSHOT | Tốt | Không block readers | Complex read transactions |

---

## Trade-offs

```
RCSI:
✅ Reads không block writes và ngược lại
✅ Không dirty reads (unlike NOLOCK)
✅ Production recommended
❌ TempDB overhead (version store)
❌ Câu hỏi với long-running transactions: version store grows

NOLOCK / READ UNCOMMITTED:
✅ Nhanh nhất (không acquire S locks)
❌ Dirty reads (đọc uncommitted data)
❌ Non-repeatable reads, phantom reads
❌ Có thể đọc rows 2 lần hoặc bỏ qua rows (page splits)
→ Không bao giờ dùng cho financial data, chỉ approximate reporting

SERIALIZABLE:
✅ Maximum isolation
❌ Blocking cao nhất, deadlock risk cao nhất
❌ Range locks (key range locks) → lock cả gaps
→ Chỉ khi cực kỳ cần thiết
```

---

## Real-world – Transaction Monitoring

```sql
-- Long-running transactions (blocking suspects)
SELECT
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) AS ActiveSeconds,
    at.transaction_type,
    at.transaction_state,
    SUBSTRING(st.text, 1, 200) AS CurrentSQL
FROM sys.dm_tran_active_transactions at
JOIN sys.dm_tran_session_transactions ts ON at.transaction_id = ts.transaction_id
JOIN sys.dm_exec_sessions s ON ts.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) st
WHERE DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) > 30
ORDER BY ActiveSeconds DESC;

-- Transaction log usage per transaction
SELECT
    s.session_id,
    DATEDIFF(SECOND, at.transaction_begin_time, GETDATE()) AS DurationSeconds,
    dt.database_transaction_log_bytes_used / 1024 AS LogKB,
    dt.database_transaction_log_bytes_reserved / 1024 AS LogReservedKB
FROM sys.dm_tran_active_transactions at
JOIN sys.dm_tran_session_transactions st ON at.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
JOIN sys.dm_tran_database_transactions dt ON at.transaction_id = dt.transaction_id
ORDER BY dt.database_transaction_log_bytes_used DESC;
```

---

## Ghi chú – Chủ đề tiếp theo
> `performance/query_optimization.md`: Query hints, plan forcing, Parameter Sniffing, In-Memory OLTP, Query Store

---

*Cập nhật lần cuối: 2026-05-06*
