---
title: "SQL Server Indexing & Execution Plans"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 0
---
# SQL Server Indexing & Execution Plans

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Architecture](architecture.md), [T-SQL Advanced](tsql_advanced.md). Đọc tiếp: [Transactions](transactions.md).

---

## 1. Index giải quyết vấn đề gì, và giá phải trả

Không có index phù hợp, SQL Server phải đọc mọi page của bảng để tìm ra vài row. Index là một cấu trúc B-tree lưu key đã sắp xếp, cho phép engine:

- seek tới đúng một khoảng hẹp thay vì đọc tất cả;
- đọc dữ liệu **đã theo đúng thứ tự** cần cho `ORDER BY`, `GROUP BY`, window function, merge join;
- trả kết quả trực tiếp từ index mà không cần quay lại bảng (*covering*);
- thực thi ràng buộc `UNIQUE` và khóa ngoại hiệu quả;
- giới hạn số row bị lock, nhờ đó giảm blocking.

Điểm cuối cùng thường bị bỏ qua nhưng cực kỳ quan trọng: **index tốt không chỉ làm query nhanh, nó còn làm hệ thống ít blocking hơn**, vì `UPDATE ... WHERE` chỉ lock những row nó thật sự chạm tới thay vì lock cả dải đã scan.

Mỗi index thêm vào làm tăng:

| Chi phí | Vì sao |
|---|---|
| Dung lượng disk và RAM | Index cũng là page, cũng chiếm buffer pool |
| Chi phí ghi | Mỗi `INSERT` phải ghi vào mọi index; `UPDATE` phải ghi vào index chứa cột bị đổi |
| Log và replication | Nhiều index = nhiều log record = nhiều việc cho secondary |
| Thời gian bảo trì | Rebuild/reorganize, update statistics |
| Rủi ro plan | Nhiều lựa chọn hơn cho optimizer, đôi khi chọn sai |

Mục tiêu không phải "index mọi cột hay dùng", mà là **bộ index nhỏ nhất phục vụ được các query shape quan trọng trong SLA**.

---

## 2. Bắt đầu từ query shape, không bắt đầu từ danh sách cột

Giả sử API có query:

```sql
SELECT OrderID, CustomerID, OrderDate, TotalAmount
FROM Sales.Orders
WHERE TenantID = @tenant
  AND Status = 'PAID'
  AND OrderDate >= @from AND OrderDate < @to
ORDER BY OrderDate DESC
OFFSET 0 ROWS FETCH NEXT 50 ROWS ONLY;
```

Phân tích query shape:

| Thành phần | Trong ví dụ | Ảnh hưởng thiết kế index |
|---|---|---|
| Equality | `TenantID`, `Status` | Thường đứng đầu key |
| Sort | `OrderDate DESC` | Đứng ngay sau equality để tránh Sort operator |
| Range | khoảng `OrderDate` | Scan một đoạn index |
| Projection | 4 cột | Có thể `INCLUDE` để covering |
| Paging | 50 row | Có thể dừng scan sớm nếu thứ tự đã đúng |
| Selectivity | bao nhiêu tenant, `PAID` chiếm mấy % | Quyết định index có đáng không |

Index khởi đầu hợp lý:

```sql
CREATE NONCLUSTERED INDEX IX_Orders_Tenant_Status_Date
    ON Sales.Orders (TenantID, Status, OrderDate DESC)
    INCLUDE (CustomerID, TotalAmount);
```

Nhưng chưa thể kết luận nó tốt chỉ từ cú pháp. Phải trả lời được: query chạy bao nhiêu lần/giây, mỗi tenant bao nhiêu order, `PAID` chiếm 1% hay 95%, bảng ghi bao nhiêu row/giây, và `SET STATISTICS IO` trước/sau chênh bao nhiêu.

### 2.1 Quy tắc ESR

**Equality → Sort → Range** là thứ tự cột mặc định nên thử trước:

```text
WHERE TenantID = @t AND Status = @s AND OrderDate >= @from   ORDER BY OrderDate DESC
      └── Equality ────────────────┘  └── Range ──────────┘  └── Sort ─────────────┘

Index: (TenantID, Status, OrderDate)
   Equality thu hẹp B-tree về đúng nhánh
   → OrderDate vừa phục vụ Sort vừa phục vụ Range trên phần còn lại
```

Tại sao Sort đứng trước Range: nếu đặt range trước, dữ liệu trong khoảng range **không còn sắp theo cột sort**, engine phải Sort lại. Còn nếu Sort đứng trước, khoảng range chỉ là việc dừng scan đúng lúc.

Về hướng `ASC/DESC`: SQL Server đọc index được theo cả hai chiều, nên một index `(A, B ASC)` vẫn phục vụ `ORDER BY B DESC`. Hướng chỉ thực sự quan trọng khi sort **nhiều cột với hướng khác nhau** (`ORDER BY A ASC, B DESC`) — lúc đó thứ tự khai báo phải khớp hoặc đảo ngược hoàn toàn.

---

## 3. Clustered index – quyết định thiết kế đắt nhất

### 3.1 Clustered index là chính cái bảng

```sql
CREATE TABLE Sales.Orders (
    OrderID    BIGINT IDENTITY NOT NULL,
    TenantID   INT           NOT NULL,
    CustomerID INT           NOT NULL,
    OrderDate  DATETIME2(3)  NOT NULL,
    Status     VARCHAR(20)   NOT NULL,
    TotalAmount DECIMAL(19,4) NOT NULL,
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID)
);
```

Leaf level của clustered index **chứa toàn bộ row**. Vì thế:

- Một bảng có tối đa một clustered index (không thể sắp dữ liệu theo hai thứ tự cùng lúc).
- Bảng không có clustered index gọi là **heap**, row nằm không thứ tự, định vị bằng RID `(file:page:slot)`.
- Clustered key được **nhân bản vào mọi nonclustered index** làm row locator. Key rộng → tất cả index khác đều phình theo.

### 3.2 Bốn tiêu chí cho clustered key

| Tiêu chí | Vì sao |
|---|---|
| **Hẹp** | Xuất hiện trong mọi nonclustered index |
| **Tăng dần** | Insert vào cuối, tránh page split ở giữa |
| **Bất biến** | Đổi giá trị = xóa & chèn lại row, và cập nhật mọi nonclustered index |
| **Duy nhất** | Nếu không unique, engine tự thêm 4-byte uniquifier ẩn |

Đây là lý do `INT`/`BIGINT IDENTITY` là mặc định tốt, và tại sao `UNIQUEIDENTIFIER` với `NEWID()` là clustered key tệ: giá trị random khiến insert rơi vào giữa B-tree, gây page split liên tục, fragmentation cao và log nhiều hơn. Nếu buộc phải dùng GUID:

- dùng `NEWSEQUENTIALID()` làm default (tăng dần trong phạm vi một lần khởi động OS), hoặc
- giữ GUID làm khóa nghiệp vụ với unique nonclustered index, và clustered theo một `BIGINT IDENTITY` riêng.

### 3.3 Khi clustered key nên là cột khác PK

Với bảng dạng log/telemetry mà mọi query đều lọc theo thời gian và tenant:

```sql
-- Truy vấn luôn có dạng: WHERE TenantID = ? AND EventTime BETWEEN ? AND ?
CREATE CLUSTERED INDEX CIX_Events_Tenant_Time ON Telemetry.Events (TenantID, EventTime, EventID);
ALTER TABLE Telemetry.Events ADD CONSTRAINT PK_Events PRIMARY KEY NONCLUSTERED (EventID);
```

Lợi ích: dữ liệu của cùng tenant trong cùng khoảng thời gian nằm cạnh nhau về mặt vật lý → một range scan đọc rất ít page. Đây cũng là tiền đề để partition theo thời gian ([partitioning.md](../performance/partitioning.md)).

Rủi ro phải cân: nếu nhiều tenant ghi đồng thời, insert phân tán vào nhiều điểm trong B-tree → page split. Đánh đổi này chỉ đáng khi tỷ lệ đọc theo dải lớn hơn nhiều so với tốc độ ghi.

### 3.4 Heap – khi nào chấp nhận được

Heap chỉ hợp lý cho bảng staging ghi-một-lần-đọc-một-lần (bulk load rồi đọc tuần tự rồi truncate). Với mọi bảng còn lại, thiếu clustered index gây forwarded record (khi row lớn ra và phải chuyển chỗ) và làm nonclustered index phải lookup qua RID.

```sql
-- Phát hiện heap và forwarded record
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + '.' + OBJECT_NAME(ps.object_id) AS TableName,
       ps.forwarded_record_count, ps.record_count, ps.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, 0, NULL, 'DETAILED') ps
WHERE ps.index_id = 0 AND ps.page_count > 100;
```

---

## 4. Nonclustered index

### 4.1 Cấu trúc và Key Lookup

```text
Nonclustered index (TenantID, Status, OrderDate) INCLUDE (TotalAmount)

Leaf entry = [TenantID][Status][OrderDate] [TotalAmount] [OrderID ← clustered key]
                └── key, sắp xếp ──────┘  └ include ┘  └ row locator ┘

Query cần cột không có trong index
   → Index Seek trên nonclustered
   → Key Lookup vào clustered index cho từng row tìm được
```

**Key Lookup là chi phí ẩn lớn nhất trong OLTP.** Mỗi row khớp là một lần random I/O vào clustered index. Với 10 row thì không sao; với 50.000 row thì optimizer thường quyết định thà scan cả bảng còn hơn — và đó chính là lúc bạn thấy plan "vô lý" chọn Clustered Index Scan dù có index đẹp.

Cách khử: đưa các cột còn thiếu vào `INCLUDE`.

```sql
CREATE NONCLUSTERED INDEX IX_Orders_Tenant_Status_Date
    ON Sales.Orders (TenantID, Status, OrderDate DESC)     -- dùng cho seek, sort, range
    INCLUDE (CustomerID, TotalAmount)                       -- chỉ để tránh Key Lookup
    WITH (FILLFACTOR = 90, ONLINE = ON, DATA_COMPRESSION = PAGE);
```

Phân biệt key column và include column:

| | Key column | Include column |
|---|---|---|
| Nằm ở | Mọi tầng B-tree | Chỉ leaf level |
| Dùng cho seek/range | Có | Không |
| Dùng cho sort | Có | Không |
| Làm index to ra | Nhiều (mọi tầng) | Ít hơn (chỉ leaf) |
| Giới hạn kích thước key | 900B (clustered) / 1700B (nonclustered) | Không tính vào giới hạn key |

### 4.2 Filtered index

```sql
-- Chỉ index phần dữ liệu "đang hoạt động" — thường là vài % của bảng
CREATE NONCLUSTERED INDEX IX_Orders_Pending
    ON Sales.Orders (TenantID, OrderDate)
    INCLUDE (CustomerID, TotalAmount)
    WHERE Status = 'PENDING';
```

Filtered index nhỏ, rẻ để bảo trì, và có statistics chỉ mô tả tập con → estimate chính xác hơn. Nhưng nó có ba giới hạn khiến người ta dùng sai:

1. Query **phải** có predicate mà optimizer chứng minh được là nằm trong filter. `WHERE Status = @status` với biến tham số thường **không** dùng được filtered index (optimizer không biết giá trị lúc compile) trừ khi có `OPTION (RECOMPILE)`.
2. Không dùng được cho filter dạng `OR` phức tạp hay hàm không xác định.
3. Cần các `SET` option đúng (`ANSI_NULLS`, `QUOTED_IDENTIFIER`...) khi ghi vào bảng — mặc định của driver hiện đại thì ổn, nhưng code cũ dùng `SET ANSI_WARNINGS OFF` có thể gặp lỗi khi `INSERT`.

Trường hợp filtered index luôn thắng: **unique index bỏ qua NULL**.

```sql
-- Chỉ những dòng có TaxCode mới bị ràng buộc unique
CREATE UNIQUE NONCLUSTERED INDEX UX_Customers_TaxCode
    ON Sales.Customers (TaxCode) WHERE TaxCode IS NOT NULL;
```

### 4.3 Covering index và cách kiểm chứng

Index là covering cho một query khi **mọi cột query cần đều có trong index** (key hoặc include). Dấu hiệu trong plan: không có `Key Lookup`/`RID Lookup`.

```sql
SET STATISTICS IO ON;
SELECT CustomerID, TotalAmount FROM Sales.Orders
WHERE TenantID = 7 AND Status = 'PAID' AND OrderDate >= '2026-07-01';
-- Trước:  Table 'Orders'. logical reads 18422
-- Sau:    Table 'Orders'. logical reads 41
```

Đừng cố covering mọi query. Một index covering cho query 40 cột sẽ nhân đôi kích thước bảng. Ưu tiên covering cho query **chạy nhiều nhất** hoặc **nằm trên đường đi quan trọng nhất**.

### 4.4 Missing index DMV – gợi ý, không phải chỉ dẫn

```sql
SELECT TOP 20
    OBJECT_SCHEMA_NAME(d.object_id) + '.' + OBJECT_NAME(d.object_id) AS TableName,
    d.equality_columns, d.inequality_columns, d.included_columns,
    s.user_seeks, s.user_scans, s.last_user_seek,
    CAST(s.avg_total_user_cost * s.avg_user_impact * (s.user_seeks + s.user_scans) AS DECIMAL(18,2)) AS Score
FROM sys.dm_db_missing_index_details d
JOIN sys.dm_db_missing_index_groups g       ON d.index_handle = g.index_handle
JOIN sys.dm_db_missing_index_group_stats s  ON g.index_group_handle = s.group_handle
WHERE d.database_id = DB_ID()
ORDER BY Score DESC;
```

Bốn giới hạn phải nhớ trước khi tạo index theo DMV:

1. DMV **không đề xuất thứ tự cột đúng** — nó chỉ nhóm equality/inequality/include, không biết ESR hay selectivity.
2. Nó **không biết các index đã có**, nên thường đề xuất trùng lặp gần hết với index sẵn có (khi đó nên mở rộng index cũ, không tạo cái mới).
3. Nó bị **reset khi restart hoặc khi index của bảng thay đổi**, nên số liệu có thể chỉ đại diện cho vài giờ.
4. Nó chỉ tính lợi ích đọc, **không tính chi phí ghi**.

Cách dùng đúng: coi nó là danh sách nghi vấn, đối chiếu với các index hiện có, rồi thiết kế thủ công theo mục 2.

---

## 5. Columnstore index – cho phân tích

### 5.1 Cơ chế

```text
Rowgroup ≈ 1.048.576 row
   └── mỗi cột trong rowgroup nén thành một column segment
        └── mỗi segment có min/max → bỏ qua segment không liên quan (segment elimination)

Ghi vào clustered columnstore:
   INSERT nhỏ  → delta store (rowstore tạm)
   Tuple mover → nén delta store đầy thành rowgroup (hoặc dùng REORGANIZE để ép ngay)
   Bulk insert ≥ 102.400 row → nén trực tiếp, bỏ qua delta store
```

Hai nguồn tốc độ của columnstore: **nén** (ít I/O hơn 5–10 lần) và **batch mode execution** (xử lý ~900 row mỗi lần thay vì từng row, tận dụng SIMD).

```sql
-- Data warehouse / fact table: clustered columnstore là bảng
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales ON Warehouse.FactSales;

-- HTAP: bảng OLTP rowstore + nonclustered columnstore cho báo cáo
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Orders
    ON Sales.Orders (OrderDate, TenantID, Status, TotalAmount)
    WHERE Status IN ('PAID','SHIPPED');    -- filtered NCCI: chỉ phần dữ liệu cần phân tích

-- Nén cao hơn nữa cho dữ liệu lạnh
ALTER INDEX CCI_FactSales ON Warehouse.FactSales
    REBUILD PARTITION = 3 WITH (DATA_COMPRESSION = COLUMNSTORE_ARCHIVE);
```

### 5.2 Sức khỏe columnstore

```sql
SELECT
    OBJECT_NAME(rg.object_id)                 AS TableName,
    rg.partition_number,
    rg.state_desc,                            -- COMPRESSED / OPEN / CLOSED / TOMBSTONE
    COUNT(*)                                  AS RowGroups,
    SUM(rg.total_rows)                        AS TotalRows,
    SUM(rg.deleted_rows)                      AS DeletedRows,
    AVG(rg.total_rows)                        AS AvgRowsPerGroup
FROM sys.dm_db_column_store_row_group_physical_stats rg
GROUP BY rg.object_id, rg.partition_number, rg.state_desc
ORDER BY TableName, rg.partition_number;
```

Hai triệu chứng cần can thiệp:

| Triệu chứng | Nguyên nhân | Xử lý |
|---|---|---|
| `AvgRowsPerGroup` thấp hơn nhiều 1 triệu | Insert theo batch nhỏ, hoặc memory grant thiếu lúc build | Load theo batch ≥ 102.400 row; `ALTER INDEX ... REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON)` |
| `DeletedRows` chiếm tỉ lệ lớn | Nhiều `UPDATE`/`DELETE` (columnstore xóa bằng cách đánh dấu) | Rebuild partition liên quan |

### 5.3 Khi nào columnstore là lựa chọn sai

- Point lookup theo khóa (`WHERE OrderID = 12345`) — rowstore B-tree nhanh hơn nhiều.
- Bảng nhỏ (dưới vài triệu row) — chưa đủ để nén và batch mode phát huy.
- Workload update từng row với tần suất cao — mỗi update là delete + insert logic.

Với SQL Server 2019+, **batch mode on rowstore** cho một phần lợi ích của batch mode mà không cần columnstore — hữu ích khi bảng vừa OLTP vừa có query phân tích lẻ.

---

## 6. Các loại index chuyên biệt

| Loại | Dùng cho | Ghi chú |
|---|---|---|
| **Unique** | Ràng buộc toàn vẹn + tăng chất lượng estimate | Optimizer dùng tính unique để đơn giản hóa plan |
| **Hash (memory-optimized)** | Point lookup trong In-Memory OLTP | Phải đặt `BUCKET_COUNT` ≈ số key duy nhất |
| **Range (memory-optimized)** | Range/sort trong In-Memory OLTP | Bkw-tree, không phải B-tree đĩa |
| **Full-text** | Tìm kiếm ngôn ngữ tự nhiên, `CONTAINS`, `FREETEXT` | Cần Full-Text Search feature |
| **XML** | Truy vấn XQuery trên cột XML | Primary + secondary XML index |
| **Spatial** | `geometry`/`geography` | Grid tessellation |
| **JSON index** (2025) | Truy vấn thuộc tính trong cột kiểu `json` | Xem [sqlserver_2025.md](../modern/sqlserver_2025.md) |
| **Vector / DiskANN** (2025) | Similarity search trên embedding | Xem [sqlserver_2025.md](../modern/sqlserver_2025.md) |

---

## 7. Đọc execution plan

### 7.1 Cách lấy plan

```sql
-- Ước lượng (không thực thi)
SET SHOWPLAN_XML ON; GO
SELECT ...; GO
SET SHOWPLAN_XML OFF; GO

-- Thực tế, kèm số đo runtime
SET STATISTICS XML ON;
SELECT ...;
SET STATISTICS XML OFF;

-- Lấy plan của query đang chạy (không cần chạy lại)
SELECT r.session_id, r.status, r.wait_type, qp.query_plan
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_query_plan(r.plan_handle) qp
WHERE r.session_id = 62;

-- Live query statistics: xem tiến độ từng operator khi query đang chạy
SET STATISTICS PROFILE ON;   -- hoặc bật Live Query Statistics trong SSMS
```

Với query chạy rất lâu, `sys.dm_exec_query_profiles` cho biết operator nào đang xử lý và đã xong bao nhiêu row — đây là cách xác định điểm nghẽn mà không phải đoán.

### 7.2 Ba câu hỏi khi mở một plan

Đừng đọc plan từ trái sang phải. Thứ tự hữu ích:

1. **Operator nào tiêu thụ nhiều nhất?** Xem actual rows và số lần thực thi, không xem phần trăm cost (cost là ước lượng, và nếu estimate sai thì phần trăm cũng sai).
2. **Estimate lệch actual ở đâu?** Điểm lệch đầu tiên (đi từ phải sang) là gốc rễ; mọi lệch sau đó chỉ là hệ quả.
3. **Có warning nào không?** Tam giác vàng trên operator luôn đáng đọc.

### 7.3 Bảng tra operator

| Operator | Nghĩa | Đọc thế nào |
|---|---|---|
| `Index Seek` | Đi thẳng tới khoảng key | Tốt — nhưng kiểm tra Seek Predicate vs Predicate |
| `Index Scan` / `Clustered Index Scan` | Đọc toàn bộ index | Tốt nếu thực sự cần nhiều dữ liệu; xấu nếu chỉ cần vài row |
| `Table Scan` | Đọc heap | Gần như luôn là thiếu clustered index |
| `Key Lookup` / `RID Lookup` | Quay lại bảng lấy cột thiếu | Nhiều lần = cần `INCLUDE` |
| `Nested Loops` | Với mỗi row ngoài, tìm trong bảng trong | Tốt khi input ngoài nhỏ và có index bên trong |
| `Hash Match` | Dựng hash table rồi probe | Tốt cho tập lớn; cần memory grant, có thể spill |
| `Merge Join` | Ghép hai input đã sắp | Rất hiệu quả, nhưng cần cả hai input sắp đúng |
| `Sort` | Sắp xếp | Thường có thể loại bỏ bằng index đúng thứ tự |
| `Spool` (Table/Index/Lazy/Eager) | Cache trung gian trong tempdb | Thường là dấu hiệu query có thể viết lại tốt hơn |
| `Parallelism` (Gather/Repartition/Distribute Streams) | Trao đổi giữa thread | Xem MAXDOP; skew ở đây gây `CXPACKET` |
| `Filter` | Lọc sau khi đọc | Nếu ngay sau Seek → predicate không seekable |
| `Compute Scalar` | Tính biểu thức | Thường rẻ, nhưng để ý scalar UDF |
| `Adaptive Join` (2017+) | Chọn Hash hay Nested Loops lúc runtime | Dấu hiệu tốt: engine tự phòng ngừa estimate sai |

Phân biệt hai dòng trong tooltip của `Index Seek`, vì đây là chi tiết quyết định:

```text
Seek Predicates : TenantID = 7 AND Status = 'PAID'   ← dùng B-tree để định vị (rẻ)
Predicate       : TotalAmount > 1000000              ← lọc sau khi đã đọc row (đắt)
```

Nếu điều kiện lọc chính của bạn nằm ở dòng `Predicate` chứ không phải `Seek Predicates`, index chưa phục vụ đúng query.

### 7.4 Warning trong plan và cách xử lý

| Warning | Nghĩa | Xử lý |
|---|---|---|
| **Implicit conversion** | Kiểu cột và kiểu tham số lệch nhau | Sửa kiểu ở tầng ứng dụng/tham số; đây là nguyên nhân #1 của "có index mà vẫn scan" |
| **Sort/Hash spill to tempdb** | Memory grant không đủ | Sửa estimate, giảm dữ liệu, hoặc dùng memory grant hint |
| **No join predicate** | Thiếu điều kiện join → Cartesian | Sửa query |
| **Excessive grant** | Grant lớn hơn nhiều mức dùng thật | Memory grant feedback (2017+/2022+) hoặc hint |
| **Columnstore not used** | Query không đủ điều kiện batch mode | Kiểm tra kiểu dữ liệu và operator không hỗ trợ |
| **Unmatched indexes** | Filtered index không dùng được vì tham số | `OPTION (RECOMPILE)` hoặc bỏ filter |

Về implicit conversion — dạng phổ biến nhất trong ứng dụng Java là **`NVARCHAR` từ driver gặp cột `VARCHAR`**:

```sql
-- Cột: CustomerCode VARCHAR(20)
-- Driver gửi: N'ABC123'  → SQL Server phải CONVERT cột sang NVARCHAR → mất seek
```

Đây là lý do JDBC nên đặt `sendStringParametersAsUnicode=false` khi schema dùng `VARCHAR`. Chi tiết ở [jdbc_java.md](../integration/jdbc_java.md).

```sql
-- Truy tìm implicit conversion trong plan cache
SELECT TOP 20
    qs.execution_count,
    qs.total_worker_time / qs.execution_count AS AvgCpuUs,
    SUBSTRING(st.text, 1, 300)                AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%'
ORDER BY qs.total_worker_time DESC;
```

---

## 8. Statistics – nền tảng của mọi estimate

### 8.1 Cấu trúc

```sql
DBCC SHOW_STATISTICS('Sales.Orders', 'IX_Orders_Tenant_Status_Date');
-- Trả về 3 phần:
--   STAT_HEADER : số row, số row đã sample, ngày cập nhật, số bước histogram
--   DENSITY_VEC : độ dày (1/số giá trị phân biệt) cho từng prefix của key
--   HISTOGRAM   : tối đa 200 bước, chỉ trên cột ĐẦU TIÊN của key
```

Điểm quan trọng ít người biết: **histogram chỉ tồn tại cho cột đầu tiên**. Với cột thứ hai trở đi, optimizer chỉ có density vector (trung bình), không có phân bố. Đây là lý do cột có skew lớn nên được cân nhắc đặt đầu, hoặc cần statistics đa cột riêng.

### 8.2 Cập nhật statistics

```sql
-- Xem độ cũ và mức thay đổi
SELECT
    OBJECT_SCHEMA_NAME(s.object_id) + '.' + OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatName, sp.last_updated, sp.rows, sp.rows_sampled,
    CAST(100.0 * sp.rows_sampled / NULLIF(sp.rows,0) AS DECIMAL(5,2)) AS SamplePct,
    sp.modification_counter, sp.steps
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY sp.modification_counter DESC;

UPDATE STATISTICS Sales.Orders;                                    -- theo mặc định sampling
UPDATE STATISTICS Sales.Orders WITH FULLSCAN;                      -- chính xác nhất, đắt nhất
UPDATE STATISTICS Sales.Orders IX_Orders_Tenant_Status_Date WITH FULLSCAN;
UPDATE STATISTICS Sales.Orders WITH SAMPLE 30 PERCENT, PERSIST_SAMPLE_PERCENT = ON;  -- 2016 SP1+
```

`PERSIST_SAMPLE_PERCENT` giải một vấn đề thực tế khó chịu: bạn cập nhật `WITH FULLSCAN` thủ công, rồi auto-update chạy sau đó với sample rất nhỏ và làm estimate xấu lại. Bật persist thì auto-update giữ đúng tỉ lệ bạn chọn.

Ngưỡng auto-update từ SQL Server 2016 (compat level ≥ 130) là động, xấp xỉ `sqrt(1000 × số row)` thay vì 20% cũ — nghĩa là bảng lớn được cập nhật thường xuyên hơn nhiều so với trước.

### 8.3 Statistics không giải quyết được gì

Ba trường hợp mà statistics dù mới cũng cho estimate sai — và cách nhận ra:

| Tình huống | Vì sao sai | Cách chữa |
|---|---|---|
| Tham số là biến local / `OPTIMIZE FOR UNKNOWN` | Optimizer dùng density trung bình, không dùng histogram | Truyền tham số trực tiếp, hoặc `OPTION (RECOMPILE)` |
| Predicate trên biểu thức (`WHERE a + b > 10`) | Không có statistics cho biểu thức | Computed column persisted + statistics trên đó |
| Ascending key (dữ liệu mới nằm ngoài histogram) | Query "hôm nay" nằm ngoài bước cuối → estimate 1 row | Update stats thường xuyên hơn, hoặc trace flag 2371/2389 tùy version, hoặc partition |

Trường hợp thứ ba rất hay gặp với bảng log: query `WHERE EventTime >= DATEADD(hour,-1,SYSUTCDATETIME())` liên tục hỏi về vùng dữ liệu mà histogram chưa biết.

---

## 9. Bảo trì index

### 9.1 Fragmentation – và tại sao nó bị nói quá

```sql
SELECT
    OBJECT_SCHEMA_NAME(ips.object_id) + '.' + OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName, ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.avg_page_space_used_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.page_count > 1000
ORDER BY ips.avg_fragmentation_in_percent DESC;
```

Ngưỡng thường dùng: dưới 5% bỏ qua, 5–30% `REORGANIZE`, trên 30% `REBUILD`. Nhưng cần đặt vào bối cảnh:

- Trên SSD/NVMe, **fragmentation logic ít ảnh hưởng hiệu năng đọc hơn nhiều** so với thời đĩa cơ, vì không có chi phí seek vật lý.
- Cái thực sự quan trọng hơn là **page density** (`avg_page_space_used_in_percent`): page rỗng một nửa nghĩa là cần gấp đôi page và gấp đôi RAM cho cùng dữ liệu.
- Rebuild có tác dụng phụ hữu ích là **cập nhật statistics với FULLSCAN**. Nhiều đội thấy "rebuild giúp nhanh hơn" thực chất là đang hưởng lợi từ statistics mới, không phải từ việc sắp lại page — và statistics thì có cách cập nhật rẻ hơn nhiều.

```sql
ALTER INDEX IX_Orders_Tenant_Status_Date ON Sales.Orders REORGANIZE;   -- luôn online, không cập nhật stats

ALTER INDEX IX_Orders_Tenant_Status_Date ON Sales.Orders
    REBUILD WITH (ONLINE = ON, RESUMABLE = ON, MAXDOP = 4, DATA_COMPRESSION = PAGE);
```

`RESUMABLE = ON` (2017+ cho rebuild, 2019+ cho create) là tính năng vận hành rất giá trị: có thể `PAUSE` giữa cửa sổ bảo trì và `RESUME` sau, không phải làm lại từ đầu.

```sql
ALTER INDEX IX_Orders_Tenant_Status_Date ON Sales.Orders PAUSE;
ALTER INDEX IX_Orders_Tenant_Status_Date ON Sales.Orders RESUME WITH (MAXDOP = 2);
ALTER INDEX IX_Orders_Tenant_Status_Date ON Sales.Orders ABORT;

-- Theo dõi tiến độ operation resumable
SELECT * FROM sys.index_resumable_operations;
```

`ONLINE = ON` cũng có một khoảng lock ngắn ở đầu và cuối. `WAIT_AT_LOW_PRIORITY` giúp khoảng đó không đánh sập workload:

```sql
ALTER INDEX ALL ON Sales.Orders REBUILD WITH (
    ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 5 MINUTES, ABORT_AFTER_WAIT = SELF))
);
```

### 9.2 FILLFACTOR

`FILLFACTOR` chừa chỗ trống trên leaf page để insert/update sau này không gây page split.

- Clustered key tăng dần, chỉ insert cuối: để 100 (mặc định) — chừa chỗ chỉ tốn RAM vô ích.
- Index trên cột random hoặc bị update nhiều: 80–90 là điểm khởi đầu hợp lý.

Đây là đánh đổi trực tiếp: fillfactor thấp = ít page split (ghi tốt hơn) nhưng nhiều page hơn (đọc và RAM tệ hơn).

### 9.3 Script bảo trì

Không nên viết lại từ đầu. `IndexOptimize` của Ola Hallengren là chuẩn thực tế trong ngành:

```sql
EXEC dbo.IndexOptimize
    @Databases              = 'USER_DATABASES',
    @FragmentationLow       = NULL,
    @FragmentationMedium    = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
    @FragmentationHigh      = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1    = 5,
    @FragmentationLevel2    = 30,
    @MinNumberOfPages       = 1000,
    @UpdateStatistics       = 'ALL',
    @OnlyModifiedStatistics = 'Y',
    @TimeLimit              = 7200,      -- dừng sau 2 giờ dù chưa xong
    @LogToTable             = 'Y';
```

`@TimeLimit` là tham số hay bị quên nhưng quan trọng nhất trong production: nó đảm bảo job bảo trì không tràn vào giờ làm việc.

---

## 10. Kiểm toán bộ index hiện có

```sql
-- Index ít dùng nhưng vẫn tốn chi phí ghi
SELECT
    OBJECT_SCHEMA_NAME(i.object_id) + '.' + OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName, i.type_desc,
    ISNULL(u.user_seeks,0)   AS Seeks,
    ISNULL(u.user_scans,0)   AS Scans,
    ISNULL(u.user_lookups,0) AS Lookups,
    ISNULL(u.user_updates,0) AS Updates,
    ISNULL(u.user_updates,0) - (ISNULL(u.user_seeks,0)+ISNULL(u.user_scans,0)+ISNULL(u.user_lookups,0)) AS NetCost,
    ps.used_page_count * 8 / 1024 AS SizeMB
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats u
       ON i.object_id = u.object_id AND i.index_id = u.index_id AND u.database_id = DB_ID()
LEFT JOIN sys.dm_db_partition_stats ps
       ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND i.type_desc = 'NONCLUSTERED' AND i.is_primary_key = 0 AND i.is_unique_constraint = 0
ORDER BY NetCost DESC;

-- Index trùng lặp / là prefix của index khác
WITH IndexCols AS (
    SELECT i.object_id, i.index_id, i.name,
           STRING_AGG(CASE WHEN ic.is_included_column = 0 THEN c.name END, ',')
               WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyCols,
           STRING_AGG(CASE WHEN ic.is_included_column = 1 THEN c.name END, ',')
               WITHIN GROUP (ORDER BY c.name) AS IncludeCols
    FROM sys.indexes i
    JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.type_desc = 'NONCLUSTERED'
    GROUP BY i.object_id, i.index_id, i.name
)
SELECT OBJECT_SCHEMA_NAME(a.object_id) + '.' + OBJECT_NAME(a.object_id) AS TableName,
       a.name AS IndexA, a.KeyCols AS KeysA,
       b.name AS IndexB, b.KeyCols AS KeysB
FROM IndexCols a
JOIN IndexCols b ON a.object_id = b.object_id AND a.index_id < b.index_id
WHERE b.KeyCols LIKE a.KeyCols + '%' OR a.KeyCols LIKE b.KeyCols + '%'
ORDER BY TableName;
```

Quy trình xóa index an toàn — quan trọng vì `user_seeks = 0` có thể chỉ là "chưa tới kỳ báo cáo cuối tháng":

1. Thu số liệu usage **liên tục ít nhất một chu kỳ nghiệp vụ đầy đủ** (thường là một tháng), lưu ra bảng riêng vì DMV reset khi restart.
2. Kiểm tra index không phải để enforce unique constraint hay foreign key.
3. `ALTER INDEX ... DISABLE` trước (giữ định nghĩa, giải phóng dung lượng leaf) thay vì `DROP` ngay — nếu có sự cố thì `REBUILD` là quay lại được.
4. `DROP` sau một chu kỳ nữa không có vấn đề.

---

## 11. Trade-offs

| Quyết định | Được | Mất | Cách chọn |
|---|---|---|---|
| Thêm index | Query đích nhanh hơn nhiều | Ghi chậm hơn, tốn RAM/disk | Đo bằng `logical reads` trước/sau; ưu tiên query trên critical path |
| `INCLUDE` nhiều cột | Khử Key Lookup, covering | Index to ra ở leaf | Chỉ include cột query thực sự trả về |
| Filtered index | Rất nhỏ, estimate tốt | Chỉ dùng được khi predicate khớp | Trạng thái ít gặp; unique bỏ qua NULL |
| Columnstore | Phân tích nhanh 10–100× | DML chậm, point lookup kém | Fact table, hoặc NCCI filtered cho HTAP |
| Clustered theo GUID | Khóa toàn cục, dễ merge dữ liệu | Page split, fragmentation, index phình | Dùng `NEWSEQUENTIALID()` hoặc clustered theo IDENTITY riêng |
| FILLFACTOR thấp | Ít page split | Nhiều page hơn, nhiều RAM hơn | Chỉ cho index bị update/insert giữa |
| Rebuild thường xuyên | Page density tốt, stats mới | Log lớn, cửa sổ bảo trì dài | Ưu tiên update statistics; rebuild theo ngưỡng, có `@TimeLimit` |
| Nhiều index trên bảng OLTP | Nhiều query shape được phục vụ | Mỗi insert đắt hơn tuyến tính | Mốc tham chiếu: OLTP nóng thường ≤ 5–8 nonclustered |

---

## 12. Real-world – quy trình tuning một query chậm

```text
1. Lấy bằng chứng, không đoán
   → Query Store hoặc sys.dm_exec_query_stats: query nào tốn nhất (CPU, reads, duration)

2. Lấy actual plan + SET STATISTICS IO, TIME ON
   → Ghi lại logical reads và CPU time làm mốc so sánh

3. Tìm điểm lệch estimate ĐẦU TIÊN từ phải sang
   → Nếu lệch: statistics cũ? tham số local? biểu thức? ascending key?

4. Tìm operator đắt nhất theo actual rows × số lần thực thi
   → Key Lookup nhiều? → INCLUDE
   → Sort? → index theo đúng thứ tự
   → Table/Index Scan mà chỉ cần ít row? → index seek được
   → Hash spill? → sửa estimate hoặc giảm dữ liệu

5. Kiểm tra warning
   → Implicit conversion là nghi phạm số một, sửa ở tầng tham số

6. Sửa một thứ, đo lại bằng chính chỉ số ở bước 2
   → Không sửa nhiều thứ cùng lúc, sẽ không biết cái nào có tác dụng

7. Kiểm tra tác động phụ
   → Index mới làm chậm INSERT/UPDATE bao nhiêu? Có trùng index cũ không?
```

Ba con số nên ghi vào ticket: `logical reads`, `CPU time`, `elapsed time` trước và sau. Chỉ nói "nhanh hơn" là không kiểm chứng được.

---

## 13. Ghi chú – chủ đề tiếp theo

- [transactions.md](transactions.md): index ảnh hưởng lock và blocking như thế nào.
- [query_optimization.md](../performance/query_optimization.md): parameter sniffing, Query Store, plan forcing, IQP.
- [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md): thu baseline usage/stats để quyết định xóa index.
- [partitioning.md](../performance/partitioning.md): aligned index, partition elimination, switch.

Từ khóa mở rộng: `sys.dm_db_index_operational_stats`, page split đo bằng `sys.dm_db_index_operational_stats.leaf_allocation_count`, statistics đa cột, computed column persisted, indexed view, `hierarchyid`, `OPTIMIZE_FOR_SEQUENTIAL_KEY`.

Một tính năng đáng nhớ cho bảng có "hot last page" (clustered IDENTITY, ghi rất nhiều thread):

```sql
CREATE CLUSTERED INDEX CIX_Log_Id ON Ops.AppLog (LogID)
    WITH (OPTIMIZE_FOR_SEQUENTIAL_KEY = ON);   -- 2019+: giảm tranh chấp latch trên page cuối
```

---

*Cập nhật lần cuối: 2026-07-30*
