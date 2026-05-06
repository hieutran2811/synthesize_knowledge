# SQL Server Indexing & Execution Plans – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Index là gì?

**Index** là cấu trúc dữ liệu bổ sung giúp SQL Server tìm kiếm nhanh hơn mà không cần scan toàn bộ bảng. Trade-off: **read nhanh hơn, write chậm hơn** (phải maintain index).

```
Không có index:    Table Scan  → đọc tất cả pages → O(n)
Có clustered idx:  Clustered Index Seek → B-tree → O(log n)
Có non-clustered:  Index Seek + Key Lookup → O(log n) + fetch
```

---

## Components – Index Types

### Clustered Index

```sql
-- Mỗi table chỉ có 1 clustered index
-- Data rows được lưu theo thứ tự của clustered index key
-- Heap table (không có clustered index) → data không có thứ tự

-- Mặc định: PRIMARY KEY tạo clustered index
CREATE TABLE Orders (
    OrderID   INT IDENTITY NOT NULL,
    OrderDate DATE,
    Amount    DECIMAL(10,2),
    CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID)
);

-- Tạo clustered trên cột khác (không phải PK)
-- Ví dụ: table events, thường query theo thời gian
CREATE CLUSTERED INDEX CIX_Events_Date ON Events(EventDate, EventID);
-- Lưu ý: clustered key phải unique (thêm EventID để tránh duplicates)

-- Xem B-tree levels của index
SELECT
    i.name, i.type_desc,
    s.index_depth, s.index_level,
    s.record_count, s.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('Orders'), NULL, NULL, 'DETAILED') s
JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id;

-- Clustered index key = row locator cho tất cả non-clustered indexes
-- → Clustered key ngắn = non-clustered indexes nhỏ hơn
-- → Wide clustered key (many columns) = larger non-clustered pages
```

### Non-Clustered Index

```sql
-- Cấu trúc B-tree riêng, leaf nodes chứa: index key + row locator (clustered key)
-- Sau khi tìm key trong index → Key Lookup để fetch data từ clustered index

-- Tạo non-clustered
CREATE NONCLUSTERED INDEX IX_Orders_CustomerDate
    ON Orders(CustomerID, OrderDate DESC)
    INCLUDE (Amount, Status)      -- covering index: tránh Key Lookup
    WHERE Status = 'Active'       -- filtered index: partial index
    WITH (
        FILLFACTOR = 80,          -- 80% full khi tạo (20% cho inserts)
        ONLINE = ON,              -- build không block DML (Enterprise)
        DATA_COMPRESSION = PAGE
    );

-- INCLUDE: thêm columns vào leaf node nhưng không phải index key
-- Tránh Key Lookup cho queries cần các columns này
-- INCLUDE columns không được dùng cho WHERE/ORDER BY predicate

-- Filtered Index: chỉ index subset của rows
-- Tiết kiệm space + nhanh hơn full index cho specific queries
CREATE INDEX IX_Orders_Pending ON Orders(OrderDate)
    INCLUDE (CustomerID, Amount)
    WHERE Status = 'Pending';     -- chỉ index các order pending
-- Chỉ có ích khi query cũng có WHERE Status = 'Pending'
```

### Columnstore Index (OLAP)

```sql
-- Columnstore: lưu data theo cột (không phải hàng)
-- Compression cực tốt (5-10x), query analytics cực nhanh (10-100x vs rowstore)
-- Nhược điểm: update/insert/delete chậm → dùng cho data warehouse, reporting

-- Non-clustered Columnstore (HTAP: OLTP + OLAP trên cùng table)
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_Orders
    ON Orders(OrderDate, CustomerID, Amount, Status);

-- Clustered Columnstore (Data Warehouse table)
CREATE CLUSTERED COLUMNSTORE INDEX CCI_FactSales
    ON FactSales;   -- không cần specify columns (tất cả columns)

-- Delta store: row-based buffer cho inserts vào clustered columnstore
-- Tuple mover: async merge delta store vào column segments

-- Segment elimination: mỗi column segment có min/max
-- Query với WHERE Amount > 1000000 → skip segments với max < 1000000

-- Batch mode execution: columnstore xử lý 900 rows/batch vs row mode 1 row/time
-- → SIMD CPU instructions → massive throughput gain

-- Mixed workload (SQL 2016+):
CREATE TABLE Orders (...) WITH (SYSTEM_VERSIONING = ON);  -- temporal
CREATE NONCLUSTERED COLUMNSTORE INDEX ON Orders(...);       -- OLAP queries
-- Row-level locking vẫn hoạt động với NCCI
```

### Covering Index

```sql
-- Covering Index: index đủ columns để satisfy query mà không cần Key Lookup

-- Query:
SELECT CustomerID, Amount, Status
FROM Orders
WHERE CustomerID = 100 AND OrderDate BETWEEN '2026-01-01' AND '2026-12-31';

-- Optimal index:
CREATE INDEX IX_Orders_CustomerDate
    ON Orders(CustomerID, OrderDate)    -- WHERE columns (seek predicates)
    INCLUDE (Amount, Status);           -- SELECT columns

-- Kiểm tra: execution plan không có "Key Lookup" → index is covering

-- Missing index hint trong execution plan:
-- <MissingIndex>
--   <ColumnGroup Usage="EQUALITY"><Column Name="CustomerID"/></ColumnGroup>
--   <ColumnGroup Usage="RANGE"><Column Name="OrderDate"/></ColumnGroup>
--   <ColumnGroup Usage="INCLUDE"><Column Name="Amount"/><Column Name="Status"/></ColumnGroup>
-- </MissingIndex>

-- DMV cho missing indexes
SELECT TOP 20
    d.equality_columns,
    d.inequality_columns,
    d.included_columns,
    s.user_seeks, s.user_scans,
    s.avg_total_user_cost * s.user_seeks AS Impact,
    'CREATE INDEX IX_' + OBJECT_NAME(d.object_id) + ' ON ' +
    d.statement + ' (' + ISNULL(d.equality_columns,'') +
    CASE WHEN d.inequality_columns IS NOT NULL
         THEN CASE WHEN d.equality_columns IS NOT NULL THEN ',' ELSE '' END
              + d.inequality_columns ELSE '' END + ')' +
    CASE WHEN d.included_columns IS NOT NULL
         THEN ' INCLUDE (' + d.included_columns + ')' ELSE '' END AS CreateIndexSQL
FROM sys.dm_db_missing_index_details d
JOIN sys.dm_db_missing_index_groups g  ON d.index_handle = g.index_handle
JOIN sys.dm_db_missing_index_group_stats s ON g.index_group_handle = s.group_handle
WHERE d.database_id = DB_ID()
ORDER BY Impact DESC;
```

---

## How – Execution Plans

### Reading Execution Plans

```sql
-- Estimated plan (không chạy query)
SET SHOWPLAN_ALL ON;   -- text
SET SHOWPLAN_XML ON;   -- XML (copy vào SSMS để xem đồ họa)

-- Actual plan (chạy query xong mới có)
SET STATISTICS XML ON;

-- Thông qua SSMS: Ctrl+M → Include Actual Execution Plan

-- Các operators quan trọng:
-- Index Seek:        tốt, sử dụng index B-tree
-- Index Scan:        scan toàn index (có thể tốt với index covering)
-- Table Scan:        xấu, không có index hữu ích
-- Key Lookup:        expensive, cần Bookmark Lookup vào clustered index
-- Nested Loop:       tốt với small outer input
-- Hash Match:        dùng cho large joins/aggregations, cần memory grant
-- Merge Join:        tốt khi cả 2 inputs sorted theo join key
-- Sort:              expensive, có thể tránh với index
-- Parallelism:       gather/exchange streams (xem MAXDOP)
-- Compute Scalar:    tính expression
-- Filter:            lọc sau khi đọc (index không đủ selective)
-- Spool:             temporary spooling (lazily evaluated)
-- Stream Aggregate:  aggregate với sorted input
```

### Execution Plan Warnings

```sql
-- Implicit Conversion → cản trở index seek
-- BAD: lưu CustomerID là INT nhưng query với NVARCHAR
SELECT * FROM Orders WHERE CustomerID = '100';  -- implicit convert → scan

-- Check implicit conversion
SELECT * FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%ImplicitConvert%'
ORDER BY qs.total_elapsed_time DESC;

-- Spill to TempDB (hash/sort warnings)
-- Execution plan có yellow warning icon
-- Giải pháp: query memory hints hoặc optimize query

-- OPTION hints
SELECT * FROM Orders WHERE CustomerID = 100
OPTION (
    RECOMPILE,              -- tạo new plan mỗi lần (cho variable sniffing)
    MAXDOP 4,               -- giới hạn parallelism
    USE HINT('DISABLE_OPTIMIZED_NESTED_LOOP'),
    FORCE ORDER             -- join theo thứ tự trong query
);
```

---

## How – Statistics

```sql
-- Statistics: distribution data → optimizer ước tính cardinality

-- Xem statistics của index
DBCC SHOW_STATISTICS('Orders', 'IX_Orders_CustomerDate') WITH HISTOGRAM;
-- Histogram: RANGE_HI_KEY, EQ_ROWS, RANGE_ROWS, DISTINCT_RANGE_ROWS, AVG_RANGE_ROWS

-- Update statistics
UPDATE STATISTICS Orders;           -- tất cả statistics trên table
UPDATE STATISTICS Orders IX_Orders_CustomerDate WITH FULLSCAN;  -- specific, full scan
UPDATE STATISTICS Orders WITH FULLSCAN, ALL;

-- Auto-update statistics threshold:
-- SQL 2016+: dynamic threshold (sqrt(1000 * table_rows))
-- Cũ: 20% rows changed

-- Xem statistics staleness
SELECT
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatName,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    sp.modification_counter
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECTPROPERTY(s.object_id, 'IsUserTable') = 1
ORDER BY sp.modification_counter DESC;

-- Trace flag 2371: dynamic stats update threshold (SQL 2014-)
-- Không cần trên SQL 2016+
```

---

## How – Index Maintenance

```sql
-- Fragmentation check
SELECT
    OBJECT_NAME(ips.object_id) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.avg_fragmentation_in_percent > 10
  AND ips.page_count > 100
ORDER BY ips.avg_fragmentation_in_percent DESC;

-- Maintenance strategy:
-- < 5%  fragmentation  → nothing
-- 5-30% fragmentation  → REORGANIZE (online, minimal lock)
-- > 30% fragmentation  → REBUILD (can be ONLINE in Enterprise)

-- REORGANIZE: defragment leaf level, always online
ALTER INDEX IX_Orders_CustomerDate ON Orders REORGANIZE;

-- REBUILD: rebuild entire index (update statistics too)
ALTER INDEX IX_Orders_CustomerDate ON Orders
    REBUILD WITH (ONLINE = ON, DATA_COMPRESSION = PAGE);

-- Rebuild ALL indexes on table
ALTER INDEX ALL ON Orders REBUILD WITH (ONLINE = ON);

-- Ola Hallengren's maintenance scripts (industry standard)
-- https://ola.hallengren.com/sql-server-index-and-statistics-maintenance.html
EXEC dbo.IndexOptimize
    @Databases = 'SalesDB',
    @FragmentationLow = NULL,
    @FragmentationMedium = 'INDEX_REORGANIZE',
    @FragmentationHigh = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1 = 5,
    @FragmentationLevel2 = 30,
    @UpdateStatistics = 'ALL',
    @OnlyModifiedStatistics = 'Y';
```

---

## How – Index Design Rules (SARGable)

```sql
-- SARGable = Search ARGument able = có thể dùng index seek

-- NOT SARGable (full scan):
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2026;          -- function on column
SELECT * FROM Orders WHERE LEFT(ProductCode, 3) = 'ABC';    -- function on column
SELECT * FROM Orders WHERE Amount * 1.1 > 110000;           -- arithmetic on column
SELECT * FROM Orders WHERE Status <> 'Cancelled';           -- <> rarely sargable
SELECT * FROM Orders WHERE Notes LIKE '%urgent%';           -- leading wildcard

-- SARGable (index seek):
SELECT * FROM Orders WHERE OrderDate >= '2026-01-01' AND OrderDate < '2027-01-01';
SELECT * FROM Orders WHERE ProductCode LIKE 'ABC%';          -- no leading wildcard
SELECT * FROM Orders WHERE Amount > 100000 / 1.1;           -- move arithmetic to other side
SELECT * FROM Orders WHERE Status = 'Active' OR Status = 'Pending';  -- IN is fine

-- Column order in composite index: ESR Rule
-- E = Equality predicates first
-- S = Sort (ORDER BY) columns second
-- R = Range predicates last

-- Query: WHERE CustomerID = 5 AND Status = 'Active' ORDER BY OrderDate
-- Index: (CustomerID, Status, OrderDate) ← ESR order
-- NOT:   (OrderDate, CustomerID, Status)
```

---

## Compare – Index Types

| Index Type | Dùng cho | Đọc | Ghi | Size |
|------------|----------|-----|-----|------|
| Clustered | Primary access pattern | Tốt | Tốt | Bảng gốc |
| Non-clustered | Secondary access, lookups | Tốt | OK | Nhỏ hơn |
| Covering | Specific query (no lookup) | Tốt nhất | OK | Trung bình |
| Filtered | Subset of rows | Tốt | Tốt | Rất nhỏ |
| Columnstore | Analytics, aggregation | Rất tốt | Chậm | Nhỏ nhất |
| Full-text | Text search | Tốt | Chậm | Trung bình |

---

## Trade-offs

```
Nhiều index:
✅ Queries đa dạng đều nhanh
❌ INSERT/UPDATE/DELETE chậm (maintain all indexes)
❌ Tốn thêm storage + buffer pool pages
❌ Statistics cần update thường xuyên hơn

Columnstore:
✅ Analytics 10-100x faster
✅ Compression rất tốt
❌ DML chậm hơn rowstore
❌ Point lookup kém (không phù hợp OLTP)

Filtered Index:
✅ Nhỏ gọn, hiệu quả cho specific queries
❌ Chỉ được dùng khi query predicate khớp filter
❌ Statistics chỉ đại diện cho subset

Rule of thumb:
  - OLTP table: 5-10 indexes max
  - Data warehouse: ít indexes, favor columnstore
  - Xóa unused indexes (dm_db_index_usage_stats user_seeks = 0)
```

---

## Real-world – Index Usage Monitoring

```sql
-- Indexes ít được dùng (candidates for removal)
SELECT
    OBJECT_NAME(i.object_id) AS TableName,
    i.name AS IndexName,
    i.type_desc,
    u.user_seeks,
    u.user_scans,
    u.user_lookups,
    u.user_updates,  -- maintenance cost
    (u.user_updates - (u.user_seeks + u.user_scans + u.user_lookups)) AS NetCost
FROM sys.indexes i
LEFT JOIN sys.dm_db_index_usage_stats u
    ON i.object_id = u.object_id AND i.index_id = u.index_id
    AND u.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1
  AND i.type > 0  -- exclude heaps
  AND (u.user_seeks + u.user_scans + u.user_lookups) < 100  -- rarely used
ORDER BY u.user_updates DESC;

-- Duplicate indexes
SELECT
    OBJECT_NAME(i1.object_id) AS TableName,
    i1.name AS Index1,
    i2.name AS Index2,
    c1.IndexColumns
FROM sys.indexes i1
JOIN sys.indexes i2 ON i1.object_id = i2.object_id AND i1.index_id < i2.index_id
CROSS APPLY (
    SELECT STRING_AGG(col.name, ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS IndexColumns
    FROM sys.index_columns ic
    JOIN sys.columns col ON ic.object_id = col.object_id AND ic.column_id = col.column_id
    WHERE ic.object_id = i1.object_id AND ic.index_id = i1.index_id AND ic.is_included_column = 0
) c1
CROSS APPLY (
    SELECT STRING_AGG(col.name, ',') WITHIN GROUP (ORDER BY ic.key_ordinal) AS IndexColumns
    FROM sys.index_columns ic
    JOIN sys.columns col ON ic.object_id = col.object_id AND ic.column_id = col.column_id
    WHERE ic.object_id = i2.object_id AND ic.index_id = i2.index_id AND ic.is_included_column = 0
) c2
WHERE c1.IndexColumns = c2.IndexColumns;
```

---

## Ghi chú – Chủ đề tiếp theo
> `transactions.md`: Transactions, ACID, Isolation Levels, Locking (shared/exclusive/update/intent), Deadlocks, MVCC (snapshot isolation)

---

*Cập nhật lần cuối: 2026-05-06*
