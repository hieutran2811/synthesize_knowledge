# Data Movement, CDC & Integration

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Change Event Streaming và Fabric mirroring là tính năng của 2025; data virtualization qua `OPENROWSET` trên Parquet/Delta là 2022+.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [T-SQL Advanced](../fundamentals/tsql_advanced.md), [Partitioning](../performance/partitioning.md). Đọc tiếp: [JDBC & Java](jdbc_java.md).

---

## 1. Bốn bài toán khác nhau, thường bị gộp làm một

"Đưa dữ liệu từ A sang B" thực ra là bốn bài toán với ràng buộc khác nhau, và chọn sai công cụ là nguồn của phần lớn hệ thống tích hợp khó bảo trì:

| Bài toán | Câu hỏi đặc trưng | Công cụ phù hợp |
|---|---|---|
| **Nạp khối lượng lớn** | Đưa 500 triệu row vào bảng nhanh nhất bằng cách nào? | `BULK INSERT`, `bcp`, `SqlBulkCopy`, partition switch |
| **Theo dõi thay đổi** | Row nào đã đổi từ lần đồng bộ trước? | Change Tracking, CDC |
| **Phát sự kiện ra ngoài** | Làm sao ứng dụng khác biết ngay khi có thay đổi? | CDC + Debezium, Change Event Streaming (2025), Outbox |
| **Truy vấn dữ liệu ở nơi khác** | Đọc dữ liệu ngoài database mà không copy vào | Linked server, `OPENROWSET`, PolyBase, data virtualization |

Câu hỏi phân loại đầu tiên: **bạn cần biết "đã đổi" hay cần biết "đổi thế nào"?** Nếu chỉ cần đồng bộ trạng thái hiện tại, Change Tracking đủ và rẻ hơn nhiều. Nếu cần chuỗi sự kiện có giá trị trước/sau, phải dùng CDC.

---

## 2. Nạp khối lượng lớn

### 2.1 Minimal logging – điều kiện để bulk load nhanh

```sql
-- Điều kiện để BULK INSERT được ghi log tối thiểu:
--   1. Recovery model là SIMPLE hoặc BULK_LOGGED
--   2. Bảng đích không đang được replicate
--   3. TABLOCK được chỉ định (hoặc bảng là heap trống)
ALTER DATABASE SalesDB SET RECOVERY BULK_LOGGED;

BULK INSERT Staging.Orders
FROM '/data/orders_202607.csv'
WITH (
    FORMAT          = 'CSV',
    FIRSTROW        = 2,
    FIELDQUOTE      = '"',
    ROWTERMINATOR   = '0x0a',
    TABLOCK,                        -- điều kiện cho minimal logging + cho phép song song
    BATCHSIZE       = 100000,       -- mỗi batch là một transaction
    MAXERRORS       = 0,
    ERRORFILE       = '/data/errors/orders_202607.err',
    CHECK_CONSTRAINTS = OFF,        -- bỏ kiểm tra để nhanh; PHẢI kiểm tra lại sau
    FIRE_TRIGGERS     = OFF
);

ALTER DATABASE SalesDB SET RECOVERY FULL;
BACKUP LOG SalesDB TO DISK = '/backup/log/post_bulk.trn';
```

Chuỗi thao tác chuẩn cho nạp dữ liệu lớn vào bảng đã có index:

```text
1. Bảng staging heap, không index, cùng filegroup với đích
2. BULK INSERT vào staging với TABLOCK, BATCHSIZE hợp lý
3. Kiểm tra chất lượng dữ liệu trên staging (đây là lúc rẻ nhất để phát hiện lỗi)
4. Tạo index trên staging khớp với bảng đích
5. Thêm CHECK constraint chặn dải nếu sẽ partition switch
6. SWITCH vào bảng đích  → metadata-only, không blocking dài
```

So sánh với cách làm phổ biến nhưng chậm: `INSERT INTO đích SELECT FROM staging` phải ghi log từng row, cập nhật mọi index của bảng đích, và giữ lock trong suốt quá trình. Với 500 triệu row, chênh lệch là hàng giờ. Chi tiết SWITCH ở [partitioning.md](../performance/partitioning.md) mục 5.

### 2.2 `OPENROWSET(BULK ...)` – linh hoạt hơn `BULK INSERT`

```sql
-- Đọc file như một bảng, cho phép biến đổi ngay trong SELECT
INSERT INTO Sales.Orders (OrderNo, OrderDate, TenantID, TotalAmount)
SELECT
    src.OrderNo,
    TRY_CONVERT(DATETIME2(3), src.OrderDate) AS OrderDate,
    src.TenantID,
    TRY_CONVERT(DECIMAL(19,4), src.TotalAmount)
FROM OPENROWSET(
        BULK '/data/orders_202607.csv',
        FORMAT = 'CSV', FIRSTROW = 2,
        FORMATFILE = '/data/format/orders.xml'
     ) AS src
WHERE TRY_CONVERT(DATETIME2(3), src.OrderDate) IS NOT NULL;   -- bỏ dòng lỗi thay vì fail cả batch
```

Ưu điểm so với `BULK INSERT`: cho phép `WHERE`, `JOIN`, biến đổi kiểu, và `TRY_CONVERT` để loại dòng lỗi thay vì dừng toàn bộ. Đánh đổi: thường không đạt được tốc độ của `BULK INSERT ... TABLOCK` thuần.

### 2.3 `bcp` cho export/import từ dòng lệnh

```bash
# Export
bcp "SELECT * FROM SalesDB.Sales.Orders WHERE OrderDate >= '2026-07-01'" queryout \
    /data/orders.dat -S sql1 -U sa -P "$PW" -n -b 100000

# Import
bcp SalesDB.Staging.Orders in /data/orders.dat \
    -S sql1 -U sa -P "$PW" -n -b 100000 -h "TABLOCK" -e /data/orders.err
```

Cờ `-n` (native format) nhanh nhất và giữ nguyên kiểu dữ liệu, nhưng chỉ đọc được bởi SQL Server. Dùng `-c`/`-w` khi cần trao đổi với hệ khác.

### 2.4 Từ Java: `SQLServerBulkCopy`

```java
// Nhanh hơn nhiều lần so với batch INSERT thông thường
try (Connection conn = dataSource.getConnection();
     SQLServerBulkCopy bulk = new SQLServerBulkCopy(conn)) {

    SQLServerBulkCopyOptions opts = new SQLServerBulkCopyOptions();
    opts.setBulkCopyTimeout(600);
    opts.setBatchSize(100_000);
    opts.setTableLock(true);           // TABLOCK: điều kiện cho minimal logging
    opts.setUseInternalTransaction(true);
    bulk.setBulkCopyOptions(opts);

    bulk.setDestinationTableName("Staging.Orders");
    bulk.addColumnMapping("orderNo",    "OrderNo");
    bulk.addColumnMapping("orderDate",  "OrderDate");
    bulk.addColumnMapping("totalAmount","TotalAmount");

    bulk.writeToServer(new MyRecordBulkData(records));   // implement ISQLServerBulkData
}
```

Đây là công cụ đúng cho ETL viết bằng Java: nó dùng cùng giao thức TDS bulk như `bcp`, không đi qua đường `INSERT` thông thường. Xem thêm [jdbc_java.md](jdbc_java.md).

---

## 3. Change Tracking – nhẹ, chỉ cho biết "cái gì đã đổi"

```sql
ALTER DATABASE SalesDB SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 3 DAYS, AUTO_CLEANUP = ON);

ALTER TABLE Sales.Orders ENABLE CHANGE_TRACKING
    WITH (TRACK_COLUMNS_UPDATED = ON);
```

Cách dùng: client giữ một `version` và hỏi "có gì đổi từ version đó?".

```sql
-- Lấy version hiện tại (lưu lại cho lần đồng bộ sau)
SELECT CHANGE_TRACKING_CURRENT_VERSION() AS CurrentVersion;

-- Lấy thay đổi từ version đã lưu, join để lấy dữ liệu hiện tại
DECLARE @lastVersion BIGINT = 10427;

-- Kiểm tra version còn hợp lệ (chưa bị cleanup) — BƯỚC KHÔNG ĐƯỢC BỎ
IF @lastVersion < CHANGE_TRACKING_MIN_VALID_VERSION(OBJECT_ID('Sales.Orders'))
    THROW 50050, 'Version quá cũ, phải làm full reload', 1;

SELECT
    ct.OrderID,
    ct.SYS_CHANGE_OPERATION      AS Op,          -- I / U / D
    ct.SYS_CHANGE_VERSION,
    ct.SYS_CHANGE_COLUMNS,                       -- bitmask cột nào đổi
    o.TenantID, o.Status, o.TotalAmount          -- NULL nếu row đã bị DELETE
FROM CHANGETABLE(CHANGES Sales.Orders, @lastVersion) AS ct
LEFT JOIN Sales.Orders o ON o.OrderID = ct.OrderID
ORDER BY ct.SYS_CHANGE_VERSION;
```

Đặc điểm định hình cách dùng Change Tracking:

| Đặc điểm | Hệ quả |
|---|---|
| Chỉ lưu **khóa chính** đã đổi, không lưu giá trị | Phải join về bảng gốc → chỉ lấy được **trạng thái hiện tại** |
| Nhiều lần đổi cùng row bị gộp | Không có chuỗi lịch sử; row đổi 5 lần cũng chỉ báo một lần |
| Row đã `DELETE` không lấy lại được giá trị | Chỉ biết là đã bị xóa |
| Đồng bộ, ghi trong cùng transaction | Overhead thấp nhưng có, không cần agent |
| `CHANGE_RETENTION` hết → version không hợp lệ | Client offline quá lâu phải full reload |

Vì vậy Change Tracking đúng cho: **đồng bộ một chiều trạng thái hiện tại** (cache invalidation, đẩy dữ liệu sang Elasticsearch, mobile sync). Không đúng cho: audit, event sourcing, hay bất cứ thứ gì cần biết giá trị trước.

Bước kiểm tra `CHANGE_TRACKING_MIN_VALID_VERSION` ở trên là chỗ hay bị bỏ và gây lỗi im lặng: nếu version đã bị cleanup, `CHANGETABLE` trả về kết quả **không đầy đủ** mà không báo lỗi, khiến dữ liệu đích lệch dần mà không ai biết.

---

## 4. Change Data Capture (CDC) – "đổi thế nào"

```sql
-- 1. Bật ở mức database (tạo schema cdc và các job capture/cleanup)
USE SalesDB;
EXEC sys.sp_cdc_enable_db;

-- 2. Bật cho từng bảng
EXEC sys.sp_cdc_enable_table
    @source_schema        = N'Sales',
    @source_name          = N'Orders',
    @role_name            = N'role_cdc_reader',      -- NULL = ai có quyền SELECT bảng gốc đều đọc được
    @capture_instance     = N'Sales_Orders',
    @supports_net_changes = 1,                        -- cần PK; cho phép hàm net_changes
    @captured_column_list = N'OrderID, TenantID, Status, TotalAmount, OrderDate';

-- 3. Kiểm tra
SELECT s.name AS SchemaName, t.name AS TableName, t.is_tracked_by_cdc
FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.is_tracked_by_cdc = 1;
```

### 4.1 Đọc thay đổi

```sql
-- Chuyển khoảng thời gian thành khoảng LSN
DECLARE @from BINARY(10) = sys.fn_cdc_map_time_to_lsn('smallest greater than or equal',
                                                      DATEADD(MINUTE, -15, SYSDATETIME()));
DECLARE @to   BINARY(10) = sys.fn_cdc_get_max_lsn();

-- Tất cả thay đổi, theo thứ tự (event stream)
SELECT
    __$start_lsn, __$seqval,
    __$operation,          -- 1 = delete, 2 = insert, 3 = update (before), 4 = update (after)
    __$update_mask,
    OrderID, TenantID, Status, TotalAmount
FROM cdc.fn_cdc_get_all_changes_Sales_Orders(@from, @to, N'all update old')
ORDER BY __$start_lsn, __$seqval;

-- Chỉ trạng thái ròng (gộp nhiều lần đổi của cùng row)
SELECT __$operation, OrderID, TenantID, Status, TotalAmount
FROM cdc.fn_cdc_get_net_changes_Sales_Orders(@from, @to, N'all');
```

Tham số `'all update old'` là điều làm CDC khác Change Tracking: nó trả về **cả giá trị trước và sau** của mỗi `UPDATE` (`__$operation` 3 và 4).

### 4.2 Cơ chế và vận hành

```text
Transaction ghi vào bảng
   → log record vào transaction log
   → CDC capture job đọc log (log reader), ghi vào bảng cdc.<capture_instance>_CT
   → client đọc từ bảng CT qua các hàm cdc.fn_*

Bất đồng bộ: có độ trễ giữa commit và lúc thay đổi xuất hiện trong CDC.
Log KHÔNG truncate được cho tới khi capture job đã đọc tới
  → log_reuse_wait_desc = 'REPLICATION' khi job dừng.
```

| Vấn đề vận hành | Dấu hiệu | Xử lý |
|---|---|---|
| Capture job dừng | Log phình, `log_reuse_wait_desc = 'REPLICATION'` | Khởi động lại job; alert trên tình trạng job |
| Độ trễ capture cao | Thay đổi xuất hiện muộn | Tăng `maxtrans`/`maxscans`, kiểm tra tải log reader |
| Bảng CT phình | Dung lượng tăng | `retention` của cleanup job; mặc định 3 ngày |
| Schema đổi | CDC không tự bắt cột mới | Tạo capture instance thứ hai, chuyển consumer, xóa instance cũ |

```sql
-- Cấu hình job
EXEC sys.sp_cdc_change_job @job_type = N'capture',
     @maxtrans = 500, @maxscans = 10, @pollinginterval = 5;
EXEC sys.sp_cdc_change_job @job_type = N'cleanup', @retention = 4320;   -- phút (3 ngày)

-- Trạng thái và độ trễ
EXEC sys.sp_cdc_help_jobs;
SELECT * FROM sys.dm_cdc_log_scan_sessions ORDER BY session_id DESC;
SELECT tran_begin_time, tran_end_time, tran_id, tran_begin_lsn
FROM cdc.lsn_time_mapping ORDER BY tran_end_time DESC;
```

Xử lý thay đổi schema — quy trình "hai capture instance" là cách duy nhất không mất dữ liệu:

```sql
-- Một bảng được phép có tối đa 2 capture instance
EXEC sys.sp_cdc_enable_table
    @source_schema = N'Sales', @source_name = N'Orders',
    @capture_instance = N'Sales_Orders_v2',
    @captured_column_list = N'OrderID, TenantID, Status, TotalAmount, OrderDate, Channel';

-- Consumer chuyển dần sang v2, sau đó bỏ v1
EXEC sys.sp_cdc_disable_table
    @source_schema = N'Sales', @source_name = N'Orders', @capture_instance = N'Sales_Orders';
```

### 4.3 CDC vs Change Tracking

| | Change Tracking | CDC |
|---|---|---|
| Lưu gì | Chỉ khóa chính đã đổi | Toàn bộ giá trị, trước và sau |
| Cơ chế | Đồng bộ, trong transaction | Bất đồng bộ, job đọc log |
| Cần SQL Agent | Không | **Có** |
| Overhead ghi | Thấp | Thấp trên đường ghi, nhưng job tiêu CPU/IO |
| Dung lượng | Rất nhỏ | Đáng kể (bảng CT) |
| Nhiều lần đổi cùng row | Gộp | Giữ từng lần |
| Ảnh hưởng truncate log | Không | **Có** — job dừng là log phình |
| Dùng cho | Đồng bộ trạng thái, cache invalidation | ETL, event stream, audit thay đổi, Debezium |

---

## 5. CDC ra Kafka: Debezium

Mô hình phổ biến nhất để đưa thay đổi từ SQL Server vào kiến trúc event-driven là **Debezium SQL Server connector** đọc bảng CDC và publish lên Kafka.

```json
{
  "name": "sqlserver-sales-connector",
  "config": {
    "connector.class": "io.debezium.connector.sqlserver.SqlServerConnector",
    "database.hostname": "sql1",
    "database.port": "1433",
    "database.user": "debezium",
    "database.password": "${file:/opt/secrets:debezium_pw}",
    "database.names": "SalesDB",
    "database.encrypt": "true",
    "database.trustServerCertificate": "false",
    "topic.prefix": "sqlserver.sales",
    "table.include.list": "Sales.Orders,Sales.OrderItems",
    "schema.history.internal.kafka.topic": "schema-history.sales",
    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "snapshot.mode": "initial",
    "snapshot.isolation.mode": "snapshot",
    "decimal.handling.mode": "string",
    "time.precision.mode": "adaptive_time_microseconds",
    "tombstones.on.delete": "true",
    "heartbeat.interval.ms": "10000"
  }
}
```

Bốn cấu hình cần cân nhắc kỹ:

| Cấu hình | Vì sao quan trọng |
|---|---|
| `snapshot.isolation.mode: snapshot` | Snapshot ban đầu không block workload (cần `ALLOW_SNAPSHOT_ISOLATION ON`) |
| `decimal.handling.mode: string` | Mặc định `precise` mã hóa Base64 và rất khó dùng ở phía consumer |
| `heartbeat.interval.ms` | Với bảng ít thay đổi, heartbeat giúp offset tiến lên → **log SQL Server truncate được** |
| `tombstones.on.delete` | Cần cho semantics compaction ở Kafka |

Cấu hình `heartbeat.interval.ms` là chi tiết vận hành quan trọng nhất: nếu bảng được CDC nhưng ít thay đổi, offset của connector không tiến, capture job không tiến, và **log của SQL Server không truncate được** — dẫn tới log phình mà nguyên nhân rất khó tìm.

Chi tiết về phía Kafka: [kafka/streams/connect.md](../../kafka/streams/connect.md) và [kafka/patterns/event_driven_architecture.md](../../kafka/patterns/event_driven_architecture.md).

---

## 6. Change Event Streaming (SQL Server 2025)

SQL Server 2025 bổ sung **Change Event Streaming (CES)**: engine tự publish sự kiện thay đổi ra một endpoint bên ngoài (Azure Event Hubs, và endpoint tương thích Kafka), không cần Debezium hay Kafka Connect ở giữa.

```sql
-- Khung cấu hình: bật ở database, tạo event stream group, thêm bảng
-- (cú pháp và tên procedure cần đối chiếu tài liệu chính thức của version đang dùng)
EXEC sys.sp_enable_event_stream;

-- Đăng ký đích và các bảng cần phát sự kiện, sau đó bật group
```

Điểm khác biệt so với CDC + Debezium:

| | CDC + Debezium | Change Event Streaming (2025) |
|---|---|---|
| Thành phần vận hành | SQL Agent job + Kafka Connect + connector | Chỉ engine + endpoint đích |
| Độ trễ | Hai chặng (log → CT table → Kafka) | Một chặng |
| Dung lượng trong database | Bảng CT | Ít hơn |
| Độ chín / hệ sinh thái | Rất chín, nhiều tài liệu và kinh nghiệm | Mới, cần đánh giá |
| Linh hoạt transform | SMT của Kafka Connect | Hạn chế hơn |

Đánh giá thực dụng cho thời điểm hiện tại: CES đáng thử nghiệm và có tiềm năng đơn giản hóa đáng kể kiến trúc, nhưng với hệ thống production đang chạy tốt trên CDC + Debezium thì chưa có lý do bắt buộc phải chuyển. Nếu xây mới trên SQL Server 2025 và đích là Event Hubs/Kafka, CES nên nằm trong danh sách cân nhắc đầu tiên. Xem thêm [sqlserver_2025.md](../modern/sqlserver_2025.md).

---

## 7. Outbox pattern – khi cần bảo đảm nghiệp vụ

CDC/CES phát mọi thay đổi ở tầng vật lý. Nhưng nhiều khi ứng dụng cần phát **sự kiện nghiệp vụ** ("OrderPaid"), không phải "row trong bảng Orders có cột Status đổi từ PENDING sang PAID". Đó là lúc dùng Outbox.

```sql
CREATE TABLE Outbox.Messages (
    MessageID   BIGINT IDENTITY PRIMARY KEY,
    AggregateId NVARCHAR(100)  NOT NULL,
    EventType   NVARCHAR(100)  NOT NULL,
    Payload     NVARCHAR(MAX)  NOT NULL,
    CreatedAt   DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    ProcessedAt DATETIME2(3)   NULL,
    INDEX IX_Outbox_Pending (MessageID) WHERE ProcessedAt IS NULL   -- filtered: chỉ index phần chưa xử lý
);
GO

-- Ghi nghiệp vụ và ghi sự kiện trong CÙNG transaction: nguyên tử
BEGIN TRAN;
    UPDATE Sales.Orders SET Status = 'PAID', PaidAt = SYSUTCDATETIME() WHERE OrderID = @OrderID;

    INSERT INTO Outbox.Messages (AggregateId, EventType, Payload)
    VALUES (CAST(@OrderID AS NVARCHAR(100)), N'OrderPaid',
            (SELECT OrderID, TenantID, TotalAmount, PaidAt
             FROM Sales.Orders WHERE OrderID = @OrderID
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
COMMIT;
```

Publisher lấy message và đánh dấu đã xử lý, dùng `READPAST` để nhiều worker không tranh nhau ([transactions.md](../fundamentals/transactions.md) mục 5.3):

```sql
UPDATE TOP (100) m
SET ProcessedAt = SYSUTCDATETIME()
OUTPUT inserted.MessageID, inserted.EventType, inserted.Payload
FROM Outbox.Messages m WITH (ROWLOCK, UPDLOCK, READPAST)
WHERE m.ProcessedAt IS NULL;
```

Outbox giải bài toán **dual write**: nếu ghi database rồi publish Kafka bằng hai bước riêng, một trong hai có thể thất bại và hệ thống mất nhất quán. Với Outbox, chỉ có một transaction database — sự kiện chắc chắn được ghi cùng dữ liệu.

Ba lựa chọn cho tầng publisher, xếp theo độ mạnh:

| Cách publish | Đảm bảo | Ghi chú |
|---|---|---|
| Job/worker polling như trên | At-least-once | Đơn giản nhất; consumer phải idempotent |
| Debezium đọc CDC của **bảng Outbox** | At-least-once, độ trễ thấp | Kết hợp tốt nhất: outbox cho nghiệp vụ, CDC cho vận chuyển |
| CES trên bảng Outbox (2025) | At-least-once | Ít thành phần nhất |

Xem [springboot_messaging](../../springboot/springboot_messaging.md) cho phía Spring Boot và [kafka event-driven](../../kafka/patterns/event_driven_architecture.md) cho phía Kafka.

---

## 8. Truy vấn dữ liệu ở nơi khác

### 8.1 Linked server

```sql
EXEC sp_addlinkedserver   @server = N'PG_REPORT', @srvproduct = N'PostgreSQL',
                          @provider = N'MSDASQL', @datasrc = N'PgOdbcDsn';
EXEC sp_addlinkedsrvlogin @rmtsrvname = N'PG_REPORT', @useself = N'FALSE',
                          @rmtuser = N'reader', @rmtpassword = N'<...>';

-- Cách SAI: four-part name khiến SQL Server kéo cả bảng về rồi mới lọc
SELECT * FROM PG_REPORT.reportdb.public.large_table WHERE created_at > '2026-07-01';

-- Cách ĐÚNG: đẩy predicate sang server xa
SELECT * FROM OPENQUERY(PG_REPORT,
    'SELECT id, created_at, amount FROM public.large_table WHERE created_at > ''2026-07-01''');
```

Khác biệt giữa hai cách trên có thể là hàng chục phút với bảng lớn: four-part name để optimizer của SQL Server quyết định, và nó thường không đẩy được predicate qua provider.

Linked server nên coi là lựa chọn cuối, không phải mặc định:

| Vấn đề | Chi tiết |
|---|---|
| Hiệu năng khó đoán | Không có statistics của bên xa; plan thường xấu |
| Bảo mật | Credential lưu trong SQL Server; là bề mặt tấn công ([security.md](../administration/security.md) mục 11) |
| Ghép nối chặt | Bên xa đổi schema là query bên này lỗi |
| Distributed transaction | Cần MSDTC; không đầy đủ trên Linux |

Thay thế thường tốt hơn: đồng bộ dữ liệu cần thiết sang (CDC/ETL), hoặc gọi API ở tầng ứng dụng.

### 8.2 Data virtualization (2022+)

```sql
-- Đọc Parquet trên S3-compatible/Azure trực tiếp, không cần copy vào database
CREATE EXTERNAL DATA SOURCE lake
WITH (LOCATION = 's3://minio.corp.local:9000/datalake', CREDENTIAL = MinioCred);

SELECT TOP 100 *
FROM OPENROWSET(BULK 'orders/year=2026/*.parquet',
                DATA_SOURCE = 'lake', FORMAT = 'PARQUET') AS o;

-- External table cho truy vấn thường xuyên
CREATE EXTERNAL FILE FORMAT ParquetFmt WITH (FORMAT_TYPE = PARQUET);

CREATE EXTERNAL TABLE Lake.Orders (
    OrderID BIGINT, OrderDate DATE, TenantID INT, TotalAmount DECIMAL(19,4)
) WITH (LOCATION = 'orders/', DATA_SOURCE = lake, FILE_FORMAT = ParquetFmt);
```

Đây là cách rất hợp lý để xử lý dữ liệu archive: SWITCH partition cũ ra, export sang Parquet trên object storage, và query khi cần qua external table — trong khi database chỉ giữ dữ liệu nóng. Kết hợp với [partitioning.md](../performance/partitioning.md).

### 8.3 Transactional replication

Replication vẫn hữu ích cho một bài toán cụ thể: **phân phối một tập con dữ liệu tới nhiều đích, có thể biến đổi, gần thời gian thực**.

```text
Publisher (bảng gốc)
   → Log Reader Agent  (đọc log, ghi vào distribution database)
   → Distributor
   → Distribution Agent → Subscriber 1, Subscriber 2, ...
```

Khi nào chọn replication thay vì Always On readable secondary:

| Cần | Chọn |
|---|---|
| Toàn bộ database, HA + đọc | Always On ([ha_dr.md](../administration/ha_dr.md)) |
| Chỉ vài bảng/cột, tới nhiều đích, có thể khác schema | Transactional replication |
| Subscriber cần ghi được | Merge replication (chấp nhận phức tạp conflict) |
| Đưa thay đổi vào event stream | CDC/CES, không phải replication |

Replication cũng chặn log truncate như CDC (`log_reuse_wait_desc = 'REPLICATION'`) và cần giám sát agent.

---

## 9. Trade-offs

| Lựa chọn | Được | Mất | Khi nào |
|---|---|---|---|
| `BULK INSERT ... TABLOCK` + BULK_LOGGED | Nạp nhanh nhất, log nhỏ | Mất PITR trong khoảng đó, cần TABLOCK | Cửa sổ ETL có kế hoạch |
| Staging + partition SWITCH | Không blocking dài, gần như tức thời | Cần thiết kế partition trước | Bảng lớn nạp theo kỳ |
| Change Tracking | Overhead rất thấp, không cần agent | Chỉ trạng thái hiện tại, không có giá trị cũ | Đồng bộ một chiều, cache invalidation |
| CDC | Có giá trị trước/sau, chuỗi thay đổi | Cần Agent, tốn dung lượng, chặn truncate log | ETL, event stream, audit thay đổi |
| CDC + Debezium | Hệ sinh thái chín, nhiều tùy biến | Nhiều thành phần phải vận hành | Kiến trúc event-driven trên Kafka |
| CES (2025) | Ít thành phần, độ trễ thấp | Mới, ít kinh nghiệm cộng đồng | Xây mới trên 2025, đích Event Hubs/Kafka |
| Outbox | Sự kiện nghiệp vụ, nguyên tử với dữ liệu | Bảng thêm, publisher phải viết | Khi tên và nội dung sự kiện quan trọng |
| Linked server | Truy vấn ngay, không copy | Hiệu năng khó đoán, ghép nối chặt, rủi ro bảo mật | Ad-hoc, khối lượng nhỏ |
| Data virtualization | Không copy dữ liệu, đọc data lake | Chậm hơn dữ liệu local | Dữ liệu archive, phân tích không thường xuyên |
| Transactional replication | Phân phối tập con, gần thời gian thực | Vận hành nặng, chặn truncate log | Nhiều đích cần tập con dữ liệu |

---

## 10. Checklist tích hợp dữ liệu

```text
Trước khi chọn công cụ
□ Cần "đã đổi" hay "đổi thế nào"? (Change Tracking vs CDC)
□ Cần sự kiện nghiệp vụ hay sự kiện vật lý? (Outbox vs CDC)
□ Độ trễ chấp nhận được là bao nhiêu?
□ Consumer có idempotent không? (mọi cơ chế trên đều là at-least-once)
□ Khối lượng thay đổi mỗi ngày là bao nhiêu?

Vận hành CDC/replication
□ Alert khi capture/log reader agent dừng
□ Alert khi log_reuse_wait_desc = 'REPLICATION' kéo dài
□ Alert khi độ trễ capture vượt ngưỡng
□ Heartbeat cho bảng ít thay đổi (nếu dùng Debezium)
□ Quy trình xử lý thay đổi schema (hai capture instance)
□ Retention của bảng CT phù hợp với khả năng offline của consumer
□ Dung lượng bảng cdc.* được giám sát

Vận hành bulk load
□ Recovery model được đưa về FULL sau ETL, và có BACKUP LOG ngay
□ CHECK constraint được kiểm tra lại nếu đã tắt lúc load
□ ERRORFILE được kiểm tra, không bỏ qua dòng lỗi trong im lặng
□ Batch size phù hợp để log không phình và lock không giữ lâu

Tổng quát
□ Không có credential nào nằm trong script hay repo
□ Có cách đo được độ lệch dữ liệu giữa nguồn và đích (row count, checksum theo kỳ)
□ Có quy trình full reload khi consumer lệch quá xa
```

Điểm cuối đáng nhấn mạnh: **mọi hệ thống đồng bộ dữ liệu đều sẽ lệch tại một thời điểm nào đó**. Có sẵn một quy trình reconcile (đếm row, so checksum theo dải) và một quy trình full reload là phần bắt buộc của thiết kế, không phải phần tùy chọn.

---

## 11. Ghi chú – chủ đề tiếp theo

- [jdbc_java.md](jdbc_java.md): bulk copy, batch, và gọi CDC từ Java.
- [sqlserver_2025.md](../modern/sqlserver_2025.md): Change Event Streaming, Fabric mirroring.
- [partitioning.md](../performance/partitioning.md): staging + SWITCH cho nạp dữ liệu lớn.
- [kafka/streams/connect.md](../../kafka/streams/connect.md): Debezium và Kafka Connect chi tiết.
- [springboot_messaging](../../springboot/springboot_messaging.md): Outbox và Saga ở tầng Spring.

Từ khóa mở rộng: `sys.sp_cdc_help_change_data_capture`, `sys.fn_cdc_increment_lsn`, `SqlBulkCopy` batch size tuning, SSIS trên Linux, Azure Data Factory / Fabric pipeline, `MERGE` cho slowly changing dimension, `BULK INSERT` với `ORDER` hint để tránh sort.

---

*Cập nhật lần cuối: 2026-07-30*
