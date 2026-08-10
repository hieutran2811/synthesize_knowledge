---
title: "SQL Server Transactions, Locking & Isolation"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 0
---
# SQL Server Transactions, Locking & Isolation

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Optimized Locking là tính năng của 2025 và được đánh dấu rõ.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Architecture](architecture.md), [Indexing](indexing.md). Đọc tiếp: [Query Optimization](../performance/query_optimization.md).

---

## 1. Vấn đề thật: hai người ghi cùng lúc

Transaction tồn tại để trả lời một câu hỏi rất cụ thể: *khi nhiều session đọc và ghi cùng dữ liệu, điều gì được đảm bảo?* ACID là bốn phần của câu trả lời đó:

| Thuộc tính | Nghĩa | SQL Server đảm bảo bằng gì |
|---|---|---|
| **Atomicity** | Toàn bộ hoặc không gì cả | Transaction log + rollback (hoặc PVS nếu bật ADR) |
| **Consistency** | Chuyển từ trạng thái hợp lệ sang trạng thái hợp lệ | Constraint, trigger, và chính logic ứng dụng |
| **Isolation** | Transaction không thấy trạng thái nửa vời của nhau | Lock hoặc row versioning, tùy isolation level |
| **Durability** | Đã commit là không mất | WAL: log xuống disk trước khi commit trả về |

Trong bốn cái, **Isolation là cái duy nhất bạn được chọn mức độ** — và cũng là nguồn của gần như mọi sự cố concurrency trong thực tế. Ba mức còn lại engine tự lo.

Điểm quan trọng phải nói ngay: **Consistency ở đây không có nghĩa là "dữ liệu nghiệp vụ đúng"**. Nếu ứng dụng đọc số dư rồi ghi lại số dư mới mà không có bảo vệ phù hợp, SQL Server vẫn coi transaction là hợp lệ dù kết quả nghiệp vụ sai. Đó là lỗi *lost update* — xem mục 6.

---

## 2. Điều khiển transaction trong T-SQL

```sql
-- Autocommit: mặc định, mỗi statement là một transaction
UPDATE Sales.Orders SET Status = 'PAID' WHERE OrderID = 1;

-- Explicit
BEGIN TRANSACTION;
    UPDATE Finance.Accounts SET Balance = Balance - @amt WHERE AccountID = @from;
    UPDATE Finance.Accounts SET Balance = Balance + @amt WHERE AccountID = @to;
COMMIT TRANSACTION;

-- Kiểm tra trạng thái đúng cách
SELECT @@TRANCOUNT AS Depth, XACT_STATE() AS State;
-- XACT_STATE(): 1 = còn commit được, -1 = doomed (chỉ rollback được), 0 = không có transaction
```

### 2.1 `BEGIN TRAN` lồng nhau không phải nested transaction

```sql
BEGIN TRAN;              -- @@TRANCOUNT = 1, transaction thật bắt đầu
    BEGIN TRAN;          -- @@TRANCOUNT = 2, KHÔNG có transaction mới
        UPDATE ...;
    COMMIT;              -- @@TRANCOUNT = 1, KHÔNG commit gì cả
COMMIT;                  -- @@TRANCOUNT = 0, giờ mới thật sự commit

-- Nhưng:
BEGIN TRAN;
    BEGIN TRAN;
        ROLLBACK;        -- @@TRANCOUNT = 0 ngay: rollback TOÀN BỘ, kể cả tầng ngoài
    COMMIT;              -- lỗi 3902: không có transaction để commit
```

Hệ quả thiết kế: **đừng để procedure con tự quyết định commit**. Mẫu an toàn là procedure con chỉ tham gia transaction đã có, và điểm bắt đầu/kết thúc transaction nằm ở một tầng duy nhất — thường là tầng ứng dụng hoặc procedure ngoài cùng.

```sql
CREATE OR ALTER PROCEDURE Sales.usp_AddOrderItem @OrderID BIGINT, @Sku VARCHAR(50), @Qty INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @ownTran BIT = 0;
    IF @@TRANCOUNT = 0 BEGIN BEGIN TRAN; SET @ownTran = 1; END

    BEGIN TRY
        INSERT INTO Sales.OrderItems (OrderID, Sku, Qty) VALUES (@OrderID, @Sku, @Qty);
        IF @ownTran = 1 COMMIT;
    END TRY
    BEGIN CATCH
        IF @ownTran = 1 AND XACT_STATE() <> 0 ROLLBACK;
        THROW;
    END CATCH
END
```

### 2.2 Nguyên tắc "transaction ngắn"

Mỗi transaction đang mở đều giữ ba thứ: lock, phần log không thể truncate, và (nếu có versioning) phần version store không thể dọn. Một transaction mở 10 phút vì đang chờ HTTP call bên ngoài có thể làm log phình hàng GB và block hàng chục session.

Quy tắc thực tế:

```text
✗ BEGIN TRAN → đọc dữ liệu → gọi API bên ngoài → ghi → COMMIT
✓ đọc dữ liệu → gọi API bên ngoài → BEGIN TRAN → kiểm tra lại + ghi → COMMIT
```

Nếu logic đòi hỏi "đọc rồi ghi phải nhất quán", giải pháp không phải là mở transaction dài, mà là **optimistic concurrency**: đọc kèm token version, ghi có điều kiện token chưa đổi (mục 6.2).

---

## 3. Lock – cơ chế mặc định của SQL Server

### 3.1 Lock mode

| Mode | Tên | Ai xin | Tương thích với |
|---|---|---|---|
| **S** | Shared | Reader dưới READ COMMITTED trở lên | S, IS |
| **X** | Exclusive | Writer | Không gì cả |
| **U** | Update | Bước tìm-để-sửa | S, IS (không tương thích U khác) |
| **IS / IX / SIX** | Intent | Trên các tầng cao hơn (page, table) | Theo ma trận intent |
| **Sch-S / Sch-M** | Schema stability / modification | Query đang chạy / DDL | Sch-S tương thích mọi thứ trừ Sch-M |
| **BU** | Bulk update | `BULK INSERT` với `TABLOCK` | BU khác |
| **RangeS / RangeX...** | Key-range | SERIALIZABLE | Theo ma trận range |

**U lock tồn tại để chống deadlock chuyển đổi.** Nếu hai session cùng xin S rồi cùng muốn nâng lên X, cả hai chờ nhau — deadlock. Với U lock, chỉ một session được vào bước "sẽ sửa", session kia chờ ngay từ đầu.

### 3.2 Hệ thống phân cấp và intent lock

```text
Database (S/X)
   └── Table (IS/IX/S/X/Sch-S/Sch-M)
         └── Page (IS/IX/S/X)
               └── Row (S/U/X) hoặc Key (+ key-range)
```

Intent lock cho phép engine biết "có ai đang lock cái gì bên dưới" mà không phải quét từng row. Đó là lý do một `ALTER TABLE` (cần Sch-M trên table) bị chặn bởi một `SELECT` đang chạy (giữ Sch-S) — điều gây bất ngờ trong nhiều lần deploy.

### 3.3 Lock escalation

Khi một statement lấy quá nhiều lock trên cùng một object (mốc thường được nhắc là ~5000 lock), engine cố **đổi nhiều row lock thành một table lock** để tiết kiệm bộ nhớ. Kết quả: từ blocking cục bộ thành blocking toàn bảng.

```sql
-- Kiểm soát ở mức bảng
ALTER TABLE Sales.Orders SET (LOCK_ESCALATION = AUTO);      -- partition-level nếu bảng đã partition
ALTER TABLE Sales.Orders SET (LOCK_ESCALATION = TABLE);     -- mặc định
ALTER TABLE Sales.Orders SET (LOCK_ESCALATION = DISABLE);   -- chỉ khi hiểu rõ rủi ro tốn bộ nhớ lock
```

Cách phòng tốt hơn cấu hình: **chia batch** như đã nói ở [tsql_advanced.md](tsql_advanced.md) mục 1. Một `DELETE` 5 triệu row nên là 1000 lần `DELETE TOP (5000)`.

Với bảng đã partition, `LOCK_ESCALATION = AUTO` biến escalation thành phạm vi một partition — rất giá trị cho pattern "xóa dữ liệu cũ trong khi vẫn ghi dữ liệu mới" ([partitioning.md](../performance/partitioning.md)).

### 3.4 Quan sát lock

```sql
-- Lock hiện tại, kèm object cụ thể
SELECT
    tl.request_session_id                          AS Spid,
    DB_NAME(tl.resource_database_id)               AS DbName,
    tl.resource_type,
    CASE tl.resource_type
        WHEN 'OBJECT' THEN OBJECT_NAME(tl.resource_associated_entity_id, tl.resource_database_id)
        WHEN 'KEY'    THEN (SELECT OBJECT_NAME(object_id) FROM sys.partitions
                            WHERE hobt_id = tl.resource_associated_entity_id)
        WHEN 'PAGE'   THEN (SELECT OBJECT_NAME(object_id) FROM sys.partitions
                            WHERE hobt_id = tl.resource_associated_entity_id)
    END                                            AS ObjectName,
    tl.request_mode, tl.request_status,
    wt.wait_duration_ms, wt.blocking_session_id
FROM sys.dm_tran_locks tl
LEFT JOIN sys.dm_os_waiting_tasks wt ON tl.lock_owner_address = wt.resource_address
WHERE tl.resource_type <> 'DATABASE'
ORDER BY tl.request_session_id;
```

---

## 4. Isolation level – bảng quyết định quan trọng nhất

### 4.1 Ba hiện tượng cần ngăn

| Hiện tượng | Nghĩa | Ví dụ hậu quả |
|---|---|---|
| **Dirty read** | Đọc dữ liệu chưa commit | Báo cáo dựa trên transaction sau đó bị rollback |
| **Non-repeatable read** | Đọc cùng row hai lần, hai giá trị | Kiểm tra tồn kho rồi trừ kho, số liệu đã đổi giữa hai bước |
| **Phantom read** | Đọc cùng điều kiện hai lần, số row khác | Tính tổng rồi kiểm tra tổng, có row mới chen vào |

### 4.2 Sáu mức trong SQL Server

```sql
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;   -- không xin S lock
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;     -- mặc định
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;    -- giữ S lock tới cuối transaction
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;       -- thêm key-range lock
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;           -- cần ALLOW_SNAPSHOT_ISOLATION ON

-- RCSI không phải một SET; nó thay đổi hành vi của READ COMMITTED ở mức database
ALTER DATABASE SalesDB SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
```

| Level | Dirty | Non-repeatable | Phantom | Reader block writer? | Cơ chế |
|---|---|---|---|---|---|
| READ UNCOMMITTED | Có | Có | Có | Không | Không xin S lock |
| READ COMMITTED (mặc định) | Không | Có | Có | Có (ngắn) | S lock, nhả ngay sau khi đọc |
| **READ COMMITTED SNAPSHOT (RCSI)** | Không | Có | Có | **Không** | Version store, snapshot theo **statement** |
| REPEATABLE READ | Không | Không | Có | Có (đến hết tran) | Giữ S lock |
| SNAPSHOT | Không | Không | Không | **Không** | Version store, snapshot theo **transaction** |
| SERIALIZABLE | Không | Không | Không | Có (mạnh nhất) | Key-range lock |

### 4.3 RCSI – thay đổi cấu hình có giá trị nhất

Bật RCSI thường là thay đổi một dòng đem lại nhiều lợi ích nhất cho một hệ OLTP đang bị blocking:

- Reader không còn block writer và ngược lại.
- Không có dirty read (khác hoàn toàn `NOLOCK`).
- **Ứng dụng không cần sửa dòng code nào** — `READ COMMITTED` vẫn là mức đang dùng, chỉ đổi cách thực hiện.

Chi phí và rủi ro cần biết trước:

| Chi phí | Chi tiết |
|---|---|
| tempdb version store | Mỗi row bị sửa sinh version; transaction đọc dài giữ version lâu |
| +14 byte mỗi row | Version pointer được thêm khi row lần đầu bị sửa sau khi bật |
| Thay đổi ngữ nghĩa tinh vi | Reader thấy snapshot lúc statement bắt đầu, có thể "cũ" vài chục ms so với hiện tại |
| Câu `UPDATE ... WHERE` vẫn đọc bản mới nhất | Writer luôn đọc bản hiện tại, nên logic ghi không bị nới lỏng |

Điểm cuối là chi tiết quan trọng nhất và hay bị hiểu sai: **RCSI chỉ đổi hành vi của phần đọc; phần ghi vẫn lock như cũ**. Vì vậy bật RCSI không loại bỏ lost update, và không loại bỏ deadlock giữa hai writer.

Câu lệnh `WITH ROLLBACK IMMEDIATE` sẽ **hủy mọi transaction đang mở** để lấy được database lock cần thiết — chỉ chạy trong cửa sổ bảo trì, không chạy giữa giờ cao điểm.

### 4.4 SNAPSHOT – và xung đột ghi

```sql
ALTER DATABASE SalesDB SET ALLOW_SNAPSHOT_ISOLATION ON;

-- Session A
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
    SELECT Balance FROM Finance.Accounts WHERE AccountID = 1;  -- thấy version tại thời điểm BEGIN

    -- Session B ở giữa: UPDATE cùng row rồi COMMIT

    UPDATE Finance.Accounts SET Balance = Balance - 100 WHERE AccountID = 1;
    -- → Error 3960: Snapshot isolation transaction aborted due to update conflict
COMMIT;
```

SNAPSHOT cho consistent view xuyên suốt transaction (không phantom), nhưng đổi lại **ứng dụng phải xử lý lỗi 3960** bằng retry. Đây là optimistic concurrency ở mức engine: engine không chặn trước, nó phát hiện xung đột lúc ghi.

Khi nào chọn SNAPSHOT thay vì RCSI: report/tính toán dài cần mọi số liệu thuộc cùng một thời điểm. Với đường đi OLTP thường ngày, RCSI hầu như luôn là lựa chọn đúng.

### 4.5 `NOLOCK` – vì sao đây là anti-pattern

`WITH (NOLOCK)` tương đương READ UNCOMMITTED cho bảng đó. Nó không chỉ "đọc dữ liệu chưa commit":

| Rủi ro | Chi tiết |
|---|---|
| Dirty read | Đọc dữ liệu sẽ bị rollback |
| **Đọc trùng hoặc mất row** | Nếu page split trong lúc scan, một row có thể xuất hiện hai lần hoặc bị bỏ qua hoàn toàn |
| Lỗi 601 | "Could not continue scan with NOLOCK due to data movement" — query đổ giữa đường |
| Đọc giá trị không tồn tại | Với row bị sửa dở, có thể đọc được tổ hợp giá trị chưa từng hợp lệ |

Điểm thứ hai là điều khiến `NOLOCK` không thể chấp nhận được cho bất cứ số liệu nào dùng để ra quyết định: nó không chỉ "hơi cũ", nó có thể **sai một cách không phát hiện được**.

Nếu vấn đề bạn đang cố giải bằng `NOLOCK` là "reader bị block", câu trả lời đúng gần như luôn là **bật RCSI**.

---

## 5. Blocking – chẩn đoán và xử lý

### 5.1 Tìm chuỗi blocking

```sql
-- Ai đang chặn ai, kèm câu lệnh của cả hai bên
SELECT
    blocked.session_id                              AS BlockedSpid,
    blocked.blocking_session_id                     AS BlockerSpid,
    blocked.wait_type, blocked.wait_time / 1000.0   AS WaitSec,
    blocked.resource_description,
    SUBSTRING(bt.text, (blocked.statement_start_offset/2)+1, 300) AS BlockedSql,
    SUBSTRING(kt.text, 1, 300)                      AS BlockerLastSql,
    ks.login_name, ks.host_name, ks.program_name
FROM sys.dm_exec_requests blocked
JOIN sys.dm_exec_sessions ks ON blocked.blocking_session_id = ks.session_id
CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) bt
OUTER APPLY sys.dm_exec_sql_text(ks.most_recent_sql_handle) kt
WHERE blocked.blocking_session_id <> 0;

-- Cây blocking đầy đủ (tìm root blocker)
WITH Chain AS (
    SELECT session_id, blocking_session_id, 0 AS Lvl,
           CAST(session_id AS VARCHAR(1000)) AS Path
    FROM sys.dm_exec_requests
    WHERE blocking_session_id = 0
      AND session_id IN (SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
    UNION ALL
    SELECT r.session_id, r.blocking_session_id, c.Lvl + 1,
           CAST(c.Path + ' -> ' + CAST(r.session_id AS VARCHAR(10)) AS VARCHAR(1000))
    FROM sys.dm_exec_requests r
    JOIN Chain c ON r.blocking_session_id = c.session_id
)
SELECT * FROM Chain ORDER BY Path;
```

**Root blocker** — session ở đầu chuỗi và bản thân không chờ ai — là session cần xử lý. Nó thường đang ở trạng thái `sleeping` với transaction mở: dấu hiệu ứng dụng mở transaction rồi đi làm việc khác (hoặc quên commit).

```sql
-- Transaction mở lâu, kèm lượng log đã dùng
SELECT
    s.session_id, s.login_name, s.host_name, s.program_name, s.status,
    DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) AS OpenSec,
    dt.database_transaction_log_bytes_used / 1024 AS LogKB,
    SUBSTRING(t.text, 1, 300) AS LastSql
FROM sys.dm_tran_active_transactions at
JOIN sys.dm_tran_session_transactions st ON at.transaction_id = st.transaction_id
JOIN sys.dm_exec_sessions s              ON st.session_id = s.session_id
LEFT JOIN sys.dm_tran_database_transactions dt ON at.transaction_id = dt.transaction_id
OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) t
WHERE DATEDIFF(SECOND, at.transaction_begin_time, SYSDATETIME()) > 30
ORDER BY OpenSec DESC;
```

### 5.2 Lock timeout thay vì chờ vô hạn

```sql
SET LOCK_TIMEOUT 5000;   -- ms; mặc định -1 = chờ mãi
-- Khi hết hạn: error 1222 "Lock request time out period exceeded"
```

Đặt `LOCK_TIMEOUT` ở tầng ứng dụng cho các đường đi có SLA là cách biến "treo vô hạn" thành "lỗi có thể xử lý được". Với Java, tương đương là kết hợp `queryTimeout` của JDBC và `LOCK_TIMEOUT` — xem [jdbc_java.md](../integration/jdbc_java.md).

### 5.3 Hàng đợi trong bảng: `READPAST`

```sql
-- Nhiều worker cùng lấy việc, mỗi việc chỉ một worker nhận
BEGIN TRAN;
    UPDATE TOP (10) q
    SET Status = 'PROCESSING', ClaimedBy = @worker, ClaimedAt = SYSUTCDATETIME()
    OUTPUT inserted.MessageID, inserted.Payload
    FROM Queue.Messages q WITH (ROWLOCK, UPDLOCK, READPAST)
    WHERE q.Status = 'READY';
COMMIT;
```

Ba hint phối hợp: `UPDLOCK` giữ quyền sửa, `ROWLOCK` tránh escalation, `READPAST` **bỏ qua row đang bị worker khác lock** thay vì chờ. Đây là mẫu hàng đợi chuẩn khi không muốn thêm một message broker riêng.

---

## 6. Lost update và optimistic concurrency

### 6.1 Lost update xảy ra thế nào

```text
Session A: SELECT Stock FROM Products WHERE Id=1   → 10
Session B: SELECT Stock FROM Products WHERE Id=1   → 10
Session A: UPDATE Products SET Stock = 10 - 3      → 7
Session B: UPDATE Products SET Stock = 10 - 5      → 5     ← mất luôn thay đổi của A
```

Không isolation level nào ở mức READ COMMITTED/RCSI ngăn được điều này, vì hai transaction không hề chồng lấn về mặt lock. Có ba cách chữa, và chúng khác nhau về bản chất:

```sql
-- (1) Ghi tương đối, để engine tự tính: đủ cho các ca đơn giản
UPDATE Catalog.Products SET Stock = Stock - @qty WHERE ProductID = @id AND Stock >= @qty;
IF @@ROWCOUNT = 0 THROW 50020, 'Insufficient stock', 1;

-- (2) Pessimistic: giữ quyền sửa ngay lúc đọc
BEGIN TRAN;
    SELECT Stock FROM Catalog.Products WITH (UPDLOCK, ROWLOCK) WHERE ProductID = @id;
    -- tính toán ở đây
    UPDATE Catalog.Products SET Stock = @newStock WHERE ProductID = @id;
COMMIT;

-- (3) Optimistic: phát hiện xung đột bằng version token
-- (xem 6.2)
```

Cách (1) là mặc định nên ưu tiên: không giữ lock giữa hai bước, và điều kiện `Stock >= @qty` biến kiểm tra nghiệp vụ thành phần của chính câu ghi.

### 6.2 `ROWVERSION` – optimistic concurrency đúng cách

```sql
CREATE TABLE Catalog.Products (
    ProductID INT PRIMARY KEY,
    Name      NVARCHAR(100) NOT NULL,
    Stock     INT           NOT NULL,
    RowVer    ROWVERSION            -- 8 byte, engine tự tăng mỗi lần row bị sửa
);

-- Đọc: mang RowVer về ứng dụng
SELECT ProductID, Name, Stock, RowVer FROM Catalog.Products WHERE ProductID = @id;

-- Ghi: chỉ thành công nếu chưa ai sửa
UPDATE Catalog.Products
SET Stock = @newStock
WHERE ProductID = @id AND RowVer = @rowVerFromRead;

IF @@ROWCOUNT = 0
    THROW 50021, 'Row was modified by another user', 1;   -- ứng dụng: reload + retry hoặc báo user
```

`ROWVERSION` là kiểu nhị phân tăng đơn điệu trong phạm vi database, **không phải timestamp** — đừng cố đọc nó ra ngày giờ. Trong JPA/Hibernate, map nó bằng `@Version` trên field `byte[]` và để provider sinh câu `UPDATE ... WHERE RowVer = ?`; chi tiết ở [jdbc_java.md](../integration/jdbc_java.md).

So sánh ba chiến lược:

| | Ghi tương đối | Pessimistic (`UPDLOCK`) | Optimistic (`ROWVERSION`) |
|---|---|---|---|
| Giữ lock giữa đọc và ghi | Không | Có | Không |
| Cần retry ở ứng dụng | Không | Không | Có |
| Phù hợp với web/stateless | Rất | Kém (transaction dài qua request) | Rất |
| Xử lý được logic phức tạp giữa đọc và ghi | Hạn chế | Có | Có |
| Rủi ro chính | Không diễn đạt được mọi logic | Blocking, deadlock | Xung đột nhiều → retry nhiều |

Với ứng dụng web, optimistic gần như luôn đúng, vì transaction database không nên kéo dài qua nhiều HTTP request.

---

## 7. Deadlock

### 7.1 Bản chất và cách engine xử lý

```text
Session A: lock Orders(1)  → xin Items(1)
Session B: lock Items(1)   → xin Orders(1)
→ chu trình chờ. Deadlock monitor (mặc định quét ~5s) chọn victim và rollback nó.
Victim nhận error 1205.
```

Victim được chọn theo `DEADLOCK_PRIORITY`, rồi theo lượng log đã dùng (transaction "rẻ" hơn bị hy sinh).

### 7.2 Đọc deadlock graph

```sql
-- Deadlock gần đây từ system_health (luôn bật sẵn)
SELECT
    xed.value('@timestamp', 'datetime2')      AS DeadlockTime,
    xed.query('.')                            AS DeadlockGraph
FROM (
    SELECT CAST(target_data AS XML) AS td
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON s.address = t.event_session_address
    WHERE s.name = 'system_health' AND t.target_name = 'ring_buffer'
) d
CROSS APPLY d.td.nodes('//RingBufferTarget/event[@name="xml_deadlock_report"]') AS x(xed)
ORDER BY DeadlockTime DESC;
```

Trong graph, ba thông tin quyết định:

1. `<resource-list>`: **object và index nào** đang bị tranh chấp. Nếu là index chứ không phải bảng, có thể chỉ cần sửa index.
2. `<inputbuf>` của từng process: câu lệnh thật.
3 . Thứ tự lock của hai bên: nếu đảo nhau → sửa thứ tự truy cập.

### 7.3 Phòng ngừa, theo thứ tự hiệu quả

| Biện pháp | Vì sao hiệu quả |
|---|---|
| **Truy cập object theo cùng một thứ tự** ở mọi code path | Phá vỡ điều kiện chu trình — đây là biện pháp gốc |
| **Transaction ngắn** | Ít cơ hội giao nhau |
| **Index tốt** | Lock ít row hơn; nhiều deadlock biến mất chỉ nhờ thêm một index |
| **RCSI** | Loại bỏ deadlock giữa reader và writer (không loại bỏ writer–writer) |
| **Ghi tương đối / một statement** | Không có khoảng trống giữa đọc và ghi |
| `UPDLOCK` khi đọc-để-ghi | Chuyển deadlock thành blocking (chờ được, không bị rollback) |
| `DEADLOCK_PRIORITY` | Chỉ chọn *ai* bị hy sinh, không giảm số deadlock |

### 7.4 Retry là bắt buộc, không phải tùy chọn

Deadlock không thể loại bỏ hoàn toàn trong hệ thống có concurrency thật. Mọi ứng dụng phải có retry cho error 1205 (và 1222 nếu dùng lock timeout, 3960 nếu dùng snapshot).

```sql
DECLARE @attempt INT = 0, @maxAttempt INT = 3;

WHILE 1 = 1
BEGIN
    BEGIN TRY
        BEGIN TRAN;
            -- ... công việc ...
        COMMIT;
        BREAK;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;

        SET @attempt += 1;
        IF ERROR_NUMBER() NOT IN (1205, 1222, 3960) OR @attempt >= @maxAttempt
            THROW;

        WAITFOR DELAY '00:00:00.100';   -- nên có jitter tăng dần ở tầng ứng dụng
    END CATCH
END
```

Ở tầng Java, đây chính là việc Spring `@Retryable` hoặc Resilience4j nên bao quanh, với backoff có jitter — retry đồng loạt không jitter sẽ tái tạo lại đúng deadlock vừa xảy ra.

---

## 8. Version store và tempdb

Khi bật RCSI/SNAPSHOT, mọi row bị sửa đều sinh version trong tempdb. Version chỉ được dọn khi **không còn transaction nào có thể cần tới nó** — nghĩa là một transaction đọc dài giữ toàn bộ version store lại.

```sql
-- Kích thước version store
SELECT SUM(version_store_reserved_page_count) * 8 / 1024 AS VersionStoreMB
FROM tempdb.sys.dm_db_file_space_usage;

-- Transaction lâu nhất đang giữ version (thủ phạm điển hình)
SELECT TOP 10
    s.session_id, s.login_name, s.program_name,
    DATEDIFF(SECOND, snap.transaction_sequence_num, 0) AS Ignore, -- xem elapsed_time_seconds bên dưới
    snap.elapsed_time_seconds,
    snap.is_snapshot
FROM sys.dm_tran_active_snapshot_database_transactions snap
JOIN sys.dm_exec_sessions s ON snap.session_id = s.session_id
ORDER BY snap.elapsed_time_seconds DESC;
```

Vòng lặp sự cố kinh điển: một report chạy 40 phút dưới snapshot isolation → version store phình → tempdb đầy → **mọi** transaction ghi bắt đầu lỗi. Phòng ngừa: giới hạn thời gian chạy report, đẩy report sang readable secondary của Always On ([ha_dr.md](../administration/ha_dr.md)), và alert trên `VersionStoreMB`.

---

## 9. Optimized Locking (SQL Server 2025)

SQL Server 2025 đưa **Optimized Locking** — trước đó chỉ có trên Azure SQL — vào sản phẩm on-premises. Ý tưởng gồm hai phần:

| Thành phần | Nghĩa | Lợi ích |
|---|---|---|
| **TID locking** | Thay vì giữ X lock trên từng row/key đến hết transaction, giữ lock trên **transaction ID**, còn row chỉ trỏ tới TID | Số lock giảm mạnh → ít escalation, ít bộ nhớ lock |
| **Lock After Qualification (LAQ)** | Đánh giá predicate trên **version mới nhất đã commit** trước, chỉ lock những row thực sự đủ điều kiện | Writer không lock những row nó sẽ không sửa |

```sql
-- Điều kiện: ADR phải bật (Optimized Locking dùng PVS), và RCSI được khuyến nghị
ALTER DATABASE SalesDB SET ACCELERATED_DATABASE_RECOVERY = ON;
ALTER DATABASE SalesDB SET OPTIMIZED_LOCKING = ON;

-- Kiểm tra trạng thái
SELECT name, is_optimized_locking_on, is_accelerated_database_recovery_on,
       is_read_committed_snapshot_on
FROM sys.databases WHERE database_id > 4;
```

Điều này thay đổi gì trong thực tế: `UPDATE ... WHERE <điều kiện lọc nhiều row>` trên bảng lớn trước đây giữ lock trên mọi row đã scan; với LAQ nó chỉ lock row khớp điều kiện. Đó là nguyên nhân của một lớp blocking rất khó chữa bằng index.

Cần lưu ý trước khi bật trên production:

- Nó cần PVS (ADR), nên có chi phí dung lượng trong user database.
- Ngữ nghĩa lock đổi ở mức tinh vi; nếu code phụ thuộc vào hành vi lock cụ thể (ví dụ dựa vào `UPDLOCK` để tuần tự hóa), phải kiểm thử lại.
- Kết hợp tốt nhất với RCSI; nếu vẫn dùng READ COMMITTED thuần thì lợi ích ít hơn.

Chi tiết và các tính năng 2025 khác: [sqlserver_2025.md](../modern/sqlserver_2025.md).

---

## 10. In-Memory OLTP – concurrency không có lock

Bảng memory-optimized dùng **MVCC hoàn toàn lock-free và latch-free**. Không có S/X lock; xung đột được phát hiện lúc validation và ném lỗi để ứng dụng retry.

```sql
CREATE TABLE Session.Cache (
    SessionID UNIQUEIDENTIFIER NOT NULL
        PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 1048576),
    UserID    INT NOT NULL,
    Payload   NVARCHAR(4000) NULL,
    ExpiresAt DATETIME2(0) NOT NULL,
    INDEX IX_Cache_Expiry NONCLUSTERED (ExpiresAt)
) WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
```

Các lỗi cần retry khi dùng In-Memory OLTP:

| Error | Nghĩa |
|---|---|
| 41302 | Update conflict: row đã bị transaction khác sửa sau khi transaction này bắt đầu |
| 41305 | Repeatable read validation failure |
| 41325 | Serializable validation failure |
| 41301 | Commit dependency failure (transaction phụ thuộc bị abort) |

Đây là đánh đổi rõ ràng: đổi blocking lấy nghĩa vụ retry. Với workload point-lookup tần suất rất cao (cache, session store, counter), lợi ích thường lớn; với workload phức tạp nhiều join, các giới hạn của In-Memory OLTP thường lấn át. Xem thêm [query_optimization.md](../performance/query_optimization.md).

---

## 11. Trade-offs

| Lựa chọn | Được | Mất | Khi nào |
|---|---|---|---|
| READ COMMITTED (mặc định) | Đơn giản, không tốn tempdb | Reader block writer | Hệ tải thấp, ít tranh chấp |
| **RCSI** | Reader/writer không block nhau, không sửa app | tempdb version store, +14B/row | Mặc định nên bật cho OLTP production |
| SNAPSHOT | Consistent view toàn transaction | Phải retry lỗi 3960, version store lớn | Report/tính toán dài cần nhất quán |
| SERIALIZABLE | Chống được phantom | Blocking và deadlock cao nhất | Bất biến nghiệp vụ chặt (ví dụ chống double-booking) |
| `NOLOCK` | Không chờ lock | Dirty read, đọc trùng/mất row, lỗi 601 | Gần như không bao giờ — dùng RCSI |
| Optimistic (`ROWVERSION`) | Không lock qua request, hợp web | Ứng dụng phải retry | Ứng dụng stateless, xung đột thưa |
| Pessimistic (`UPDLOCK`) | Không cần retry | Blocking, transaction dài hơn | Vùng tranh chấp nhỏ và ngắn |
| Optimized Locking (2025) | Ít lock, ít escalation, ít blocking | Cần ADR, phải kiểm thử lại | Bảng lớn có `UPDATE` phạm vi rộng |
| In-Memory OLTP | Không lock, throughput rất cao | Nhiều giới hạn T-SQL, phải retry | Cache/session/counter tần suất cực cao |

---

## 12. Real-world – runbook sự cố blocking

```text
Phút 0–2: Xác định phạm vi
□ Có bao nhiêu session bị block? (sys.dm_exec_requests WHERE blocking_session_id <> 0)
□ Root blocker là session nào, đang ở status gì?
   - sleeping + có transaction mở  → ứng dụng quên commit / đang chờ bên ngoài
   - running + query nặng          → vấn đề hiệu năng query
   - suspended chờ I/O             → nghẽn storage, xem architecture.md mục 12

Phút 2–5: Giảm thiệt hại
□ Nếu root blocker là job/ad-hoc không quan trọng → KILL <spid>
□ Nếu là ứng dụng quan trọng → đánh giá: chờ hay kill (kill sẽ rollback, có thể lâu)
□ Ghi lại bằng chứng TRƯỚC khi kill: câu lệnh, session, wait, thời điểm

Phút 5–30: Tìm nguyên nhân
□ Câu lệnh của root blocker chậm vì thiếu index? → xem plan
□ Transaction có bao trọn một lời gọi bên ngoài? → sửa ranh giới transaction
□ Có lock escalation? (sys.dm_tran_locks cho thấy OBJECT-level X lock)
□ Có phải batch quá lớn? → chia batch

Sau sự cố: phòng ngừa
□ Bật RCSI nếu đây là blocking reader–writer
□ Đặt LOCK_TIMEOUT ở đường đi có SLA
□ Thêm retry cho 1205/1222/3960 nếu chưa có
□ Alert: session bị block > 30s, transaction mở > 5 phút
□ Extended Events session ghi blocked_process_report vào file để điều tra sau
```

Bật `blocked process report` là bước chuẩn bị nên làm trước khi cần:

```sql
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'blocked process threshold (s)', 20; RECONFIGURE;

CREATE EVENT SESSION [BlockedProcess] ON SERVER
ADD EVENT sqlserver.blocked_process_report
ADD TARGET package0.event_file (SET filename = N'blocked_process.xel', max_file_size = 64)
WITH (STARTUP_STATE = ON);
ALTER EVENT SESSION [BlockedProcess] ON SERVER STATE = START;
```

---

## 13. Ghi chú – chủ đề tiếp theo

- [query_optimization.md](../performance/query_optimization.md): plan, parameter sniffing, Query Store, IQP.
- [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md): Extended Events, baseline, thu thập bằng chứng tự động.
- [sqlserver_2025.md](../modern/sqlserver_2025.md): Optimized Locking chi tiết.
- [jdbc_java.md](../integration/jdbc_java.md): isolation level, retry, `@Version`, timeout từ phía Java.

Từ khóa mở rộng: `sys.dm_tran_locks` theo `resource_description`, key-range lock và `SERIALIZABLE`, `sp_getapplock`/`sp_releaseapplock` (mutex cấp ứng dụng), distributed transaction (MSDTC) và `SET REMOTE_PROC_TRANSACTIONS`, delayed durability.

Một công cụ ít dùng nhưng rất hữu ích khi cần tuần tự hóa một tiến trình nghiệp vụ (ví dụ "chỉ một instance job chạy"):

```sql
BEGIN TRAN;
    DECLARE @rc INT;
    EXEC @rc = sp_getapplock @Resource = 'nightly-settlement', @LockMode = 'Exclusive',
                             @LockOwner = 'Transaction', @LockTimeout = 0;
    IF @rc < 0 BEGIN ROLLBACK; THROW 50030, 'Another instance is running', 1; END
    -- ... công việc ...
COMMIT;   -- lock tự nhả khi transaction kết thúc
```

---

*Cập nhật lần cuối: 2026-07-30*
