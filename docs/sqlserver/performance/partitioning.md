---
title: "Table Partitioning & Quản lý bảng rất lớn"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 0
---
# Table Partitioning & Quản lý bảng rất lớn

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Từ SQL Server 2016 SP1, partitioning có ở **mọi edition** kể cả Standard/Express.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Indexing](../fundamentals/indexing.md), [Query Optimization](query_optimization.md). Đọc tiếp: [Backup & Recovery](../administration/backup_recovery.md).

---

## 1. Partitioning giải quyết vấn đề vận hành, không phải vấn đề hiệu năng

Đây là điều cần nói trước tiên vì nó bị hiểu sai thường xuyên nhất: **partition một bảng không tự làm query nhanh hơn**. Một `SELECT` có index tốt trên bảng 500 triệu row không partition thường nhanh bằng, đôi khi nhanh hơn, so với cùng bảng đã partition.

Lợi ích thật của partitioning:

| Lợi ích | Chi tiết |
|---|---|
| **Xóa dữ liệu cũ tức thời** | `SWITCH` một partition ra bảng khác là thao tác metadata — mili giây, thay cho `DELETE` hàng giờ |
| **Nạp dữ liệu không ảnh hưởng bảng chính** | Load vào bảng staging, `SWITCH` vào — không có cửa sổ blocking dài |
| **Bảo trì theo phần** | Rebuild/reorganize/nén từng partition thay vì cả bảng |
| **Lock escalation phạm vi partition** | `LOCK_ESCALATION = AUTO` → escalation chỉ chạm một partition |
| **Tách vòng đời dữ liệu theo storage** | Dữ liệu nóng trên NVMe, dữ liệu lạnh trên storage rẻ, nén archive |
| **Backup theo filegroup** | Piecemeal restore: đưa phần dữ liệu nóng online trước |
| **Statistics mịn hơn** | Incremental statistics theo partition |

Lợi ích về đọc — **partition elimination** — là có thật nhưng thứ yếu: nó chỉ giúp khi query lọc theo partition key, và trong hầu hết trường hợp một index tốt đã cho kết quả tương đương.

Vậy khi nào nên partition? Câu trả lời thực dụng: **khi bạn có nhu cầu vận hành theo dải dữ liệu** — thường là "giữ 13 tháng, mỗi tháng xóa tháng cũ nhất". Nếu không có nhu cầu đó, partitioning chỉ thêm độ phức tạp.

---

## 2. Ba thành phần

```text
Partition function : chia miền giá trị thành các khoảng (biên)
Partition scheme   : map từng khoảng vào filegroup
Bảng/index         : tạo ON <scheme>(<cột partition>)
```

```sql
-- 1. Filegroup (có thể dùng chung một filegroup nếu không cần tách storage)
ALTER DATABASE SalesDB ADD FILEGROUP FG_2026Q1;
ALTER DATABASE SalesDB ADD FILE (NAME='Sales_2026Q1',
    FILENAME='/var/opt/mssql/data/Sales_2026Q1.ndf', SIZE=8GB, FILEGROWTH=1GB) TO FILEGROUP FG_2026Q1;
-- ... tương tự cho các quý khác

-- 2. Partition function: RANGE RIGHT theo tháng
CREATE PARTITION FUNCTION PF_OrderMonth (DATETIME2(3))
AS RANGE RIGHT FOR VALUES (
    '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01',
    '2026-05-01', '2026-06-01', '2026-07-01', '2026-08-01'
);

-- 3. Partition scheme
CREATE PARTITION SCHEME PS_OrderMonth
AS PARTITION PF_OrderMonth
ALL TO ([PRIMARY]);       -- hoặc liệt kê từng filegroup: TO (FG_Old, FG_2026Q1, ...)

-- 4. Bảng partitioned
CREATE TABLE Sales.Orders (
    OrderID     BIGINT       IDENTITY NOT NULL,
    OrderDate   DATETIME2(3) NOT NULL,
    TenantID    INT          NOT NULL,
    CustomerID  INT          NOT NULL,
    Status      VARCHAR(20)  NOT NULL,
    TotalAmount DECIMAL(19,4) NOT NULL,
    -- Cột partition PHẢI nằm trong khóa unique/primary key
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderDate, OrderID)
) ON PS_OrderMonth (OrderDate);
```

### 2.1 RANGE LEFT vs RANGE RIGHT — chọn sai là nguồn lỗi off-by-one

```text
Biên: '2026-02-01'

RANGE LEFT  : giá trị = biên thuộc partition BÊN TRÁI
              → partition kết thúc bằng ... <= '2026-02-01'
              → '2026-02-01 00:00:00.000' nằm ở partition THÁNG 1

RANGE RIGHT : giá trị = biên thuộc partition BÊN PHẢI
              → partition bắt đầu từ >= '2026-02-01'
              → '2026-02-01 00:00:00.000' nằm ở partition THÁNG 2   ← trực giác đúng
```

**Với partition theo thời gian, luôn dùng `RANGE RIGHT` và biên là mốc đầu kỳ.** `RANGE LEFT` buộc bạn viết biên kiểu `'2026-01-31 23:59:59.997'` — vừa khó đọc, vừa sai khi đổi precision của kiểu datetime.

Số partition luôn bằng số biên + 1: n biên tạo n+1 partition, gồm một partition "trước biên đầu" và một partition "sau biên cuối".

### 2.2 Xem bố cục hiện tại

```sql
SELECT
    p.partition_number,
    fg.name                                   AS FileGroup,
    prv.value                                 AS BoundaryValue,
    CASE pf.boundary_value_on_right WHEN 1 THEN 'RIGHT' ELSE 'LEFT' END AS RangeType,
    p.rows,
    p.data_compression_desc,
    SUM(au.total_pages) * 8 / 1024            AS SizeMB
FROM sys.partitions p
JOIN sys.indexes i          ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.partition_schemes ps ON i.data_space_id = ps.data_space_id
JOIN sys.partition_functions pf ON ps.function_id = pf.function_id
JOIN sys.destination_data_spaces dds
     ON dds.partition_scheme_id = ps.data_space_id AND dds.destination_id = p.partition_number
JOIN sys.filegroups fg      ON dds.data_space_id = fg.data_space_id
LEFT JOIN sys.partition_range_values prv
     ON prv.function_id = pf.function_id AND prv.boundary_id = p.partition_number
        - CASE pf.boundary_value_on_right WHEN 1 THEN 1 ELSE 0 END
JOIN sys.allocation_units au ON au.container_id = p.partition_id
WHERE p.object_id = OBJECT_ID('Sales.Orders') AND i.index_id IN (0,1)
GROUP BY p.partition_number, fg.name, prv.value, pf.boundary_value_on_right,
         p.rows, p.data_compression_desc
ORDER BY p.partition_number;
```

---

## 3. Chọn cột partition

Cột partition quyết định mọi thứ và **không đổi được** mà không rebuild cả bảng. Bốn tiêu chí:

| Tiêu chí | Vì sao |
|---|---|
| Xuất hiện trong **mọi** query lọc quan trọng | Không có nó thì không có partition elimination |
| Là trục của **vòng đời dữ liệu** | Để SWITCH-out dữ liệu cũ hoạt động |
| Phải nằm trong mọi unique index/PK | Yêu cầu của engine |
| Không bao giờ bị `UPDATE` sang partition khác | `UPDATE` vượt biên = xóa + chèn, rất đắt |

Trong ~90% ca thực tế, câu trả lời là **một cột thời gian** (`OrderDate`, `EventTime`, `CreatedAt`). Đây cũng là ca duy nhất mà lợi ích vận hành rõ ràng.

Cạm bẫy về multi-tenant: partition theo `TenantID` nghe hợp lý nhưng thường sai — số tenant tăng liên tục (phải thêm partition mãi), phân bố lệch (một tenant lớn chiếm một partition khổng lồ), và không giúp gì cho việc xóa dữ liệu cũ. Multi-tenant nên xử lý bằng index có `TenantID` đứng đầu, không bằng partition.

---

## 4. Partition elimination

```sql
-- ✓ Elimination hoạt động: predicate trực tiếp trên cột partition
SELECT COUNT(*) FROM Sales.Orders
WHERE OrderDate >= '2026-07-01' AND OrderDate < '2026-08-01';

-- ✗ Không elimination: hàm bọc quanh cột partition
SELECT COUNT(*) FROM Sales.Orders WHERE YEAR(OrderDate) = 2026;

-- ✗ Không elimination (hoặc rất hạn chế): predicate là biến mà optimizer chưa biết giá trị
--   → plan phải bao mọi partition; dùng OPTION (RECOMPILE) nếu cần

-- Kiểm tra partition nào bị chạm
SELECT $PARTITION.PF_OrderMonth(OrderDate) AS PartitionNo, COUNT(*) AS Rows
FROM Sales.Orders
WHERE OrderDate >= '2026-07-01' AND OrderDate < '2026-08-01'
GROUP BY $PARTITION.PF_OrderMonth(OrderDate);
```

Trong execution plan, xem thuộc tính `Actual Partition Count` và `Partitions Accessed` của operator scan/seek. Nếu `Partitions Accessed` là toàn bộ trong khi query chỉ cần một tháng, elimination không xảy ra.

### 4.1 Aligned vs non-aligned index

```sql
-- Aligned: index dùng cùng partition scheme (mặc định khi tạo trên bảng partitioned)
CREATE INDEX IX_Orders_Tenant_Status
    ON Sales.Orders (TenantID, Status)
    INCLUDE (TotalAmount)
    ON PS_OrderMonth (OrderDate);       -- cột partition được thêm ngầm vào index

-- Non-aligned: index nằm trên một filegroup đơn
CREATE INDEX IX_Orders_CustomerID
    ON Sales.Orders (CustomerID)
    ON [PRIMARY];
```

| | Aligned | Non-aligned |
|---|---|---|
| `SWITCH` partition | Được | **Không được** |
| Bảo trì theo partition | Được | Không |
| Query không lọc theo cột partition | Phải quét mọi partition của index | Một B-tree duy nhất, hiệu quả hơn |

Đây là đánh đổi cốt lõi của partitioning: **muốn `SWITCH` thì mọi index phải aligned**, nhưng aligned index kém hơn cho query không lọc theo cột partition. Nếu ứng dụng có query kiểu `WHERE CustomerID = ?` không kèm thời gian, nó sẽ phải seek vào từng partition — với 60 partition là 60 lần seek.

Cách xử lý thực tế:

1. Giữ mọi index aligned (bắt buộc nếu cần SWITCH).
2. Với query không có cột partition, thêm cột thời gian vào điều kiện nếu nghiệp vụ cho phép ("đơn hàng trong 12 tháng gần nhất").
3. Nếu bắt buộc có query toàn thời gian, cân nhắc một bảng tổng hợp/index riêng cho ca đó thay vì bỏ aligned.

---

## 5. Sliding window – mẫu vận hành quan trọng nhất

Mục tiêu: giữ 13 tháng dữ liệu, mỗi đầu tháng thêm partition mới và bỏ tháng cũ nhất.

### 5.1 Điều kiện cho `SWITCH`

`ALTER TABLE ... SWITCH PARTITION` chỉ đổi metadata, nên engine yêu cầu hai bảng "giống nhau đủ để tráo được":

| Điều kiện | Chi tiết |
|---|---|
| Cùng cấu trúc cột | Kiểu, nullability, thứ tự, collation |
| Cùng filegroup | Partition đích và bảng staging phải cùng filegroup |
| Mọi index aligned | Bảng staging phải có đúng bộ index tương ứng |
| Bảng đích trống (khi SWITCH IN) | Partition/bảng nhận phải rỗng |
| CHECK constraint chặn dải | Bảng staging cần constraint đảm bảo dữ liệu thuộc đúng dải |
| Không có FK trỏ tới | Foreign key tham chiếu tới bảng sẽ chặn SWITCH |
| Cùng thiết lập nén | `DATA_COMPRESSION` phải khớp |

### 5.2 SWITCH OUT: bỏ tháng cũ nhất

```sql
-- Bảng staging giống hệt cấu trúc + index, nằm trên đúng filegroup của partition 1
CREATE TABLE Sales.Orders_Out (
    OrderID     BIGINT        NOT NULL,
    OrderDate   DATETIME2(3)  NOT NULL,
    TenantID    INT           NOT NULL,
    CustomerID  INT           NOT NULL,
    Status      VARCHAR(20)   NOT NULL,
    TotalAmount DECIMAL(19,4) NOT NULL,
    CONSTRAINT PK_Orders_Out PRIMARY KEY CLUSTERED (OrderDate, OrderID)
) ON [PRIMARY];

CREATE INDEX IX_Orders_Out_Tenant_Status ON Sales.Orders_Out (TenantID, Status) INCLUDE (TotalAmount);

-- Tráo partition 1 ra ngoài: metadata-only
ALTER TABLE Sales.Orders SWITCH PARTITION 1 TO Sales.Orders_Out;

-- Giờ mới xử lý dữ liệu cũ: archive hoặc drop, không ảnh hưởng bảng chính
-- INSERT INTO Archive.Orders SELECT * FROM Sales.Orders_Out;   -- nếu cần giữ
DROP TABLE Sales.Orders_Out;

-- Gộp biên đã trống
ALTER PARTITION FUNCTION PF_OrderMonth() MERGE RANGE ('2026-01-01');
```

### 5.3 SWITCH IN và thêm partition mới

```sql
-- Thêm partition tương lai (làm TRƯỚC khi có dữ liệu tới)
ALTER PARTITION SCHEME PS_OrderMonth NEXT USED [PRIMARY];
ALTER PARTITION FUNCTION PF_OrderMonth() SPLIT RANGE ('2026-09-01');

-- Nạp dữ liệu vào bảng staging rồi tráo vào
CREATE TABLE Sales.Orders_In ( /* cấu trúc y hệt */ ) ON [PRIMARY];
ALTER TABLE Sales.Orders_In ADD CONSTRAINT CK_Orders_In_Range
    CHECK (OrderDate >= '2026-09-01' AND OrderDate < '2026-10-01');   -- bắt buộc để SWITCH IN

BULK INSERT Sales.Orders_In FROM '/data/orders_202609.csv' WITH (TABLOCK, FORMAT='CSV');
CREATE INDEX IX_Orders_In_Tenant_Status ON Sales.Orders_In (TenantID, Status) INCLUDE (TotalAmount);

ALTER TABLE Sales.Orders_In SWITCH TO Sales.Orders PARTITION 9;
DROP TABLE Sales.Orders_In;
```

### 5.4 Quy tắc SPLIT/MERGE

`SPLIT` và `MERGE` là những chỗ dễ gây sự cố nhất trong partitioning:

| Quy tắc | Vì sao |
|---|---|
| **Chỉ SPLIT partition rỗng** | SPLIT partition có dữ liệu = di chuyển toàn bộ dữ liệu, ghi log khổng lồ, lock lâu |
| **Chỉ MERGE khi một trong hai bên rỗng** | MERGE có dữ liệu hai bên = di chuyển dữ liệu |
| **Luôn giữ partition đầu và cuối rỗng** | Đây là đệm để SPLIT/MERGE luôn là thao tác metadata |
| **`NEXT USED` trước mỗi SPLIT** | Không có nó, SPLIT lỗi vì scheme không biết đặt partition mới ở đâu |
| Tạo partition tương lai **trước** | Nếu dữ liệu của tháng mới rơi vào partition cuối rồi mới SPLIT, bạn đang SPLIT partition có dữ liệu |

Điểm cuối là lỗi vận hành phổ biến nhất: job thêm partition chạy trễ một ngày, dữ liệu đã vào partition cuối, và lệnh `SPLIT` biến thành một thao tác 4 tiếng giữa giờ làm việc.

### 5.5 Job bảo trì sliding window

```sql
CREATE OR ALTER PROCEDURE Ops.usp_MaintainOrderPartitions
    @MonthsToKeep INT = 13,
    @MonthsAhead  INT = 3
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @thisMonth DATE = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1);
    DECLARE @target DATE, @i INT = 0;

    -- (a) Bảo đảm có đủ partition tương lai
    WHILE @i <= @MonthsAhead
    BEGIN
        SET @target = DATEADD(MONTH, @i, @thisMonth);

        IF NOT EXISTS (
            SELECT 1 FROM sys.partition_range_values prv
            JOIN sys.partition_functions pf ON prv.function_id = pf.function_id
            WHERE pf.name = 'PF_OrderMonth'
              AND CAST(prv.value AS DATE) = @target
        )
        BEGIN
            DECLARE @sql NVARCHAR(500) =
                N'ALTER PARTITION SCHEME PS_OrderMonth NEXT USED [PRIMARY];
                  ALTER PARTITION FUNCTION PF_OrderMonth() SPLIT RANGE (''' +
                  CONVERT(CHAR(10), @target, 23) + N''');';
            EXEC sys.sp_executesql @sql;
        END
        SET @i += 1;
    END

    -- (b) Bỏ partition quá hạn — chi tiết SWITCH OUT xem mục 5.2
    --     (giữ ở đây dạng khung để mỗi dự án tự quyết archive hay drop)
END
```

Trong thực tế, `PartitionManagement` của Ola Hallengren hoặc các script cộng đồng đã xử lý đủ các trường hợp biên; tự viết chỉ nên khi có yêu cầu đặc thù.

---

## 6. Nén theo partition và tách storage nóng/lạnh

```sql
-- Dữ liệu nóng: giữ rowstore, nén ROW (rẻ CPU khi update)
ALTER TABLE Sales.Orders REBUILD PARTITION = 13 WITH (DATA_COMPRESSION = ROW, ONLINE = ON);

-- Dữ liệu ấm: PAGE
ALTER TABLE Sales.Orders REBUILD PARTITION = 8  WITH (DATA_COMPRESSION = PAGE, ONLINE = ON);

-- Dữ liệu lạnh, chỉ để phân tích: columnstore archive
CREATE CLUSTERED COLUMNSTORE INDEX CCI_Orders ON Sales.Orders
    WITH (DROP_EXISTING = ON) ON PS_OrderMonth (OrderDate);
ALTER INDEX CCI_Orders ON Sales.Orders
    REBUILD PARTITION = 1 WITH (DATA_COMPRESSION = COLUMNSTORE_ARCHIVE);
```

Đây là một trong những kết hợp có giá trị nhất trong SQL Server: **cùng một bảng logic, nhiều chế độ lưu trữ theo tuổi dữ liệu**. Ứng dụng không cần biết; query cũ vẫn chạy.

Với storage tách biệt, đặt partition cũ vào filegroup nằm trên volume rẻ hơn, và đánh dấu filegroup đó `READ_ONLY` khi dữ liệu đã đóng băng:

```sql
ALTER DATABASE SalesDB MODIFY FILEGROUP FG_Archive READ_ONLY;
```

Filegroup read-only mang lại ba lợi ích: không cần backup lại (chỉ backup một lần), không bị corruption do ghi, và CHECKDB nhanh hơn.

---

## 7. Statistics theo partition

```sql
-- Incremental statistics: mỗi partition có stats riêng, hợp lại thành stats toàn bảng
CREATE INDEX IX_Orders_Tenant_Status ON Sales.Orders (TenantID, Status)
    WITH (STATISTICS_INCREMENTAL = ON) ON PS_OrderMonth (OrderDate);

ALTER DATABASE SalesDB SET AUTO_CREATE_STATISTICS ON (INCREMENTAL = ON);

-- Cập nhật chỉ partition vừa đổi
UPDATE STATISTICS Sales.Orders IX_Orders_Tenant_Status
    WITH RESAMPLE ON PARTITIONS (13);
```

Lợi ích: bảng 2 tỉ row không cần scan lại toàn bộ để cập nhật statistics khi chỉ partition mới nhất thay đổi. Đây là lý do incremental statistics gần như luôn nên bật cho bảng partitioned lớn.

Giới hạn cần biết: histogram toàn bảng vẫn giới hạn 200 bước, và optimizer vẫn dùng stats hợp nhất cho query không lọc theo cột partition — incremental giúp việc **cập nhật** rẻ hơn, không làm estimate mịn hơn.

---

## 8. Các cách quản lý bảng lớn không cần partitioning

Partitioning không phải công cụ duy nhất, và thường không phải công cụ đầu tiên nên thử.

| Nhu cầu | Giải pháp không cần partition |
|---|---|
| Xóa dữ liệu cũ | `DELETE TOP (5000)` theo vòng lặp, chạy ngoài giờ cao điểm |
| Chỉ query dữ liệu gần đây | Filtered index trên khoảng thời gian nóng |
| Tách nóng/lạnh | Hai bảng riêng + view `UNION ALL` (partitioned view kiểu cũ) |
| Giảm dung lượng | Nén PAGE hoặc columnstore trên cả bảng |
| Bảo trì bảng lớn | `REBUILD ... RESUMABLE = ON`, `WAIT_AT_LOW_PRIORITY` |
| Truy vấn dữ liệu archive ngoài database | `OPENROWSET` trên Parquet/CSV ở object storage (data virtualization) |

Cách xóa theo batch, viết đúng để không tự gây blocking:

```sql
DECLARE @cutoff DATETIME2(3) = DATEADD(MONTH, -13, SYSUTCDATETIME());

WHILE 1 = 1
BEGIN
    DELETE TOP (5000) FROM Sales.Orders WHERE OrderDate < @cutoff;
    IF @@ROWCOUNT = 0 BREAK;

    WAITFOR DELAY '00:00:00.050';   -- nhả nhịp cho workload khác
END
```

So sánh trực diện cho bài toán "bỏ một tháng dữ liệu khỏi bảng 500 triệu row":

| | `DELETE` theo batch | `SWITCH` partition |
|---|---|---|
| Thời gian | Hàng giờ | Mili giây |
| Log sinh ra | Rất lớn (mỗi row một log record) | Gần như không |
| Blocking | Có, kéo dài | Chỉ khoảnh khắc lấy schema lock |
| Cần chuẩn bị trước | Không | Có: partition, aligned index, staging |

Chênh lệch này là lý do chính đáng nhất để chấp nhận độ phức tạp của partitioning.

---

## 9. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Partition theo tháng | SWITCH gọn, bảo trì theo phần | Nhiều partition (13–60) cần job quản lý | Bảng log/giao dịch có vòng đời rõ |
| Partition theo ngày | Rất mịn, xóa hàng ngày | Hàng trăm–nghìn partition, plan phình, metadata lớn | Chỉ khi thật cần độ mịn ngày |
| Mọi index aligned | SWITCH được | Query không lọc theo cột partition chậm hơn | Ưu tiên nếu SWITCH là mục đích chính |
| Có index non-aligned | Query lookup nhanh | Mất khả năng SWITCH | Chỉ khi không cần SWITCH |
| Nhiều filegroup theo partition | Tách storage, piecemeal restore, read-only archive | Backup/restore phức tạp hơn | Bảng rất lớn, có tầng storage khác nhau |
| Columnstore cho partition cũ | Nén rất cao, phân tích nhanh | Không phù hợp point lookup | Dữ liệu đã đóng băng |
| Incremental statistics | Cập nhật stats rẻ | Không mịn hơn về estimate | Gần như luôn bật cho bảng partitioned lớn |
| Không partition, dùng DELETE batch | Đơn giản, không cần thiết kế trước | Chậm, log lớn, blocking | Bảng chưa quá lớn, chưa có nhu cầu vận hành |

---

## 10. Checklist triển khai partitioning

```text
Thiết kế
□ Xác định rõ NHU CẦU VẬN HÀNH cần partition (không partition "cho hiện đại")
□ Cột partition: có trong mọi query lọc quan trọng, là trục vòng đời, không bị UPDATE vượt biên
□ Cột partition nằm trong PK/unique index
□ RANGE RIGHT, biên là mốc đầu kỳ
□ Độ mịn: tháng cho phần lớn ca; ngày chỉ khi bắt buộc
□ Filegroup: một cái là đủ, trừ khi cần tách storage / piecemeal restore

Triển khai
□ Mọi index aligned nếu cần SWITCH
□ Có partition đệm ở đầu và cuối, luôn rỗng
□ LOCK_ESCALATION = AUTO
□ STATISTICS_INCREMENTAL = ON
□ Đo hiệu năng query quan trọng TRƯỚC và SAU (đặc biệt query không lọc theo cột partition)

Vận hành
□ Job thêm partition tương lai, chạy trước ít nhất 1–3 kỳ
□ Alert nếu partition cuối có dữ liệu (nghĩa là job thêm partition đã trễ)
□ Job SWITCH OUT + archive/drop dữ liệu quá hạn
□ Chỉ SPLIT/MERGE trên partition rỗng
□ Bảo trì (rebuild, nén) theo partition, không theo cả bảng
□ Ghi tài liệu: partition function, scheme, quy ước biên, và job liên quan
```

---

## 11. Ghi chú – chủ đề tiếp theo

- [backup_recovery.md](../administration/backup_recovery.md): backup theo filegroup, piecemeal restore, read-only filegroup.
- [monitoring_troubleshooting.md](monitoring_troubleshooting.md): giám sát kích thước partition và job bảo trì.
- [data_movement.md](../integration/data_movement.md): nạp dữ liệu vào bảng staging trước khi SWITCH.
- [indexing.md](../fundamentals/indexing.md): columnstore, aligned index.

Từ khóa mở rộng: `$PARTITION` function, `sys.dm_db_partition_stats`, partitioned view (mô hình cũ trước 2005), stretch/archive sang object storage, data virtualization với `OPENROWSET` trên Parquet, filegroup read-only backup strategy.

---

*Cập nhật lần cuối: 2026-07-30*
