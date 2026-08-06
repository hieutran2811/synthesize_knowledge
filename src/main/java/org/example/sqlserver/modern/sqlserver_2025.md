# SQL Server 2025: JSON gốc, Regex, Vector/AI & Optimized Locking

> Mục tiêu phiên bản: **SQL Server 2025 (17.x)**, compatibility level **170**. So sánh với **SQL Server 2022 (16.x, compat 160)**.
>
> ⚠️ Đây là ảnh chụp kiến thức tại **2026-07-30**. Các tính năng mới nhất có thay đổi cú pháp, tên tham số và điều kiện áp dụng giữa các CU. **Luôn đối chiếu tài liệu chính thức của bản build đang dùng** trước khi triển khai production; các đoạn code dưới đây là khung để hiểu ý tưởng, không phải bản sao tài liệu.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [T-SQL Advanced](../fundamentals/tsql_advanced.md), [Transactions](../fundamentals/transactions.md), [Query Optimization](../performance/query_optimization.md).

---

## 1. SQL Server 2025 thay đổi những gì

Có thể nhóm các bổ sung của 2025 thành bốn hướng, và chúng có mức độ "đáng đổi ngay" rất khác nhau:

| Hướng | Tính năng | Đáng chuyển ngay? |
|---|---|---|
| **Concurrency** | Optimized Locking (TID locking + LAQ) | Có, nếu đang bị blocking do `UPDATE` phạm vi rộng |
| **Kiểu dữ liệu & T-SQL** | Kiểu `json` gốc + JSON index, họ `REGEXP_*`, các hàm chuẩn mới | Có, cải thiện rõ và ít rủi ro |
| **AI / tìm kiếm** | Kiểu `vector`, `VECTOR_DISTANCE`, vector index (DiskANN), external model | Chỉ khi có nhu cầu thật về semantic search/RAG |
| **Tích hợp & vận hành** | Change Event Streaming, Fabric mirroring, tempdb resource governance, IQP mới (OPPO) | Tùy nhu cầu; OPPO thì gần như luôn hữu ích |

Điểm chung: phần lớn cần **compatibility level 170**, nên việc nâng cấp phải theo quy trình có Query Store làm bằng chứng — xem mục 8.

---

## 2. Optimized Locking

### 2.1 Vấn đề nó giải quyết

Trong SQL Server truyền thống, một `UPDATE` phạm vi rộng:

```sql
UPDATE Sales.Orders SET Status = 'ARCHIVED'
WHERE OrderDate < '2025-01-01' AND Status = 'CLOSED';
```

sẽ lấy X lock trên **mọi row nó phải đọc để đánh giá điều kiện**, và giữ chúng đến hết transaction. Với bảng lớn, điều đó nghĩa là: rất nhiều lock (tốn bộ nhớ), nguy cơ lock escalation lên cả bảng, và blocking lan rộng cho những row mà câu lệnh cuối cùng còn không sửa.

### 2.2 Hai cơ chế

| Cơ chế | Nghĩa |
|---|---|
| **TID locking** (Transaction ID locking) | Thay vì giữ lock trên từng row/key đến hết transaction, engine giữ lock trên **transaction ID**; mỗi row được sửa chỉ mang một con trỏ tới TID đó. Số lượng lock giảm mạnh. |
| **LAQ** (Lock After Qualification) | Đánh giá predicate trên **version mới nhất đã commit** trước; chỉ lock những row thực sự đủ điều kiện. Row không khớp không bị lock. |

Kết quả: câu `UPDATE` ở trên chỉ lock row nó thật sự đổi, không lock những row nó chỉ đi qua.

### 2.3 Bật

```sql
-- Điều kiện: ADR phải bật (Optimized Locking dùng persistent version store)
ALTER DATABASE SalesDB SET ACCELERATED_DATABASE_RECOVERY = ON;

-- RCSI được khuyến nghị mạnh để hưởng lợi đầy đủ
ALTER DATABASE SalesDB SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;

ALTER DATABASE SalesDB SET OPTIMIZED_LOCKING = ON;

-- Kiểm tra
SELECT name,
       is_accelerated_database_recovery_on,
       is_read_committed_snapshot_on,
       is_optimized_locking_on
FROM sys.databases WHERE database_id > 4;
```

### 2.4 Cần cân nhắc gì trước khi bật production

| Điểm | Chi tiết |
|---|---|
| Phụ thuộc ADR | PVS chiếm dung lượng trong chính user database; theo dõi kích thước |
| Ngữ nghĩa lock thay đổi ở mức tinh vi | Code dựa vào hành vi lock cụ thể (dùng `UPDLOCK` để tuần tự hóa, hoặc dựa vào blocking như một hàng đợi ngầm) phải được kiểm thử lại |
| Lợi ích phụ thuộc isolation | Với `READ COMMITTED` thuần (không RCSI), lợi ích ít hơn |
| Không thay thế index tốt | Nếu `UPDATE` đang scan cả bảng vì thiếu index, hãy sửa index trước |

Đánh giá thực dụng: đây là tính năng có giá trị cao nhất của 2025 cho hệ OLTP đang gặp blocking mà index đã hợp lý. Nhưng nó nên được bật sau khi đã làm hai việc rẻ hơn: bật RCSI và sửa các câu lệnh phạm vi quá rộng. Chi tiết nền tảng ở [transactions.md](../fundamentals/transactions.md) mục 9.

---

## 3. Kiểu `json` gốc và JSON index

### 3.1 Trước và sau

Trước 2025, JSON được lưu như `nvarchar(max)`: engine phải **parse lại chuỗi mỗi lần** đọc một thuộc tính, và để index thì phải tạo computed column persisted cho từng thuộc tính ([tsql_advanced.md](../fundamentals/tsql_advanced.md) mục 10.2).

```sql
-- 2025: kiểu json gốc, lưu dạng nhị phân đã parse
CREATE TABLE Events.Store (
    EventID   BIGINT IDENTITY PRIMARY KEY,
    EventType NVARCHAR(50) NOT NULL,
    Payload   JSON         NOT NULL,          -- kiểu gốc
    CreatedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);

INSERT INTO Events.Store (EventType, Payload)
VALUES (N'OrderPaid', N'{"orderId":1001,"tenantId":42,"amount":250000,"channel":"web"}');

-- Các hàm JSON quen thuộc hoạt động như cũ, nhưng không phải parse lại chuỗi
SELECT EventID, JSON_VALUE(Payload, '$.orderId') AS OrderId
FROM Events.Store
WHERE JSON_VALUE(Payload, '$.tenantId') = '42';
```

Lợi ích của kiểu gốc:

| Lợi ích | Chi tiết |
|---|---|
| Không parse lại | Dữ liệu đã ở dạng nhị phân có cấu trúc |
| Kiểm tra hợp lệ tự động | Không cần `CHECK (ISJSON(...) = 1)` |
| Lưu trữ hiệu quả hơn | Dạng nhị phân thường gọn hơn chuỗi |
| Index được trực tiếp | Không cần computed column cho từng thuộc tính |

### 3.2 JSON index

```sql
-- Khung: index cho các thuộc tính trong cột json
-- (đối chiếu cú pháp chính xác với tài liệu bản build đang dùng)
CREATE JSON INDEX IX_Events_Payload ON Events.Store (Payload)
    FOR ('$.tenantId', '$.orderId', '$.channel');
```

Đây là thay đổi thực chất: trước đó, muốn query hiệu quả theo N thuộc tính JSON cần N computed column + N index, và mỗi thuộc tính mới là một lần `ALTER TABLE`. Với JSON index, schema linh hoạt của JSON không còn phải trả giá bằng khả năng truy vấn.

### 3.3 Nguyên tắc thiết kế không đổi

Dù JSON gốc đã tốt hơn nhiều, nguyên tắc từ [tsql_advanced.md](../fundamentals/tsql_advanced.md) vẫn đúng: **cột nào là trục truy vấn chính, có ràng buộc, và tham gia join thì nên là cột thật**. JSON phù hợp cho:

- payload sự kiện có hình dạng thay đổi theo loại;
- thuộc tính mở rộng của sản phẩm (mỗi danh mục có tập thuộc tính riêng);
- dữ liệu nhận từ API bên ngoài mà bạn chưa muốn chuẩn hóa.

Không phù hợp cho: khóa, trạng thái, số tiền, thời gian — những thứ sẽ bị lọc/sắp xếp/tổng hợp trong mọi query.

### 3.4 Từ Java

```java
// Driver map kiểu json về String; xử lý như JSON bình thường ở tầng ứng dụng
ps.setString(1, objectMapper.writeValueAsString(payload));
String json = rs.getString("Payload");
```

Với Hibernate 6+, dùng `@JdbcTypeCode(SqlTypes.JSON)` để mapping. Xem [jdbc_java.md](../integration/jdbc_java.md).

---

## 4. Regular expression trong T-SQL

Trước 2025, việc so khớp mẫu trong T-SQL chỉ có `LIKE` và `PATINDEX` — không đủ cho validation hay trích xuất, nên logic đó thường phải chuyển lên tầng ứng dụng hoặc dùng CLR.

```sql
-- Họ hàm REGEXP_* (2025)
SELECT REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') AS IsValidEmail
FROM Sales.Customers;

SELECT REGEXP_REPLACE(Phone, '[^0-9]', '')                     AS DigitsOnly
FROM Sales.Customers;

SELECT REGEXP_SUBSTR(Description, '[A-Z]{2,3}-[0-9]{4,6}')     AS TicketRef
FROM Ops.Notes;

SELECT REGEXP_COUNT(LogLine, 'ERROR')                          AS ErrorCount
FROM Ops.AppLog;

SELECT REGEXP_INSTR(Path, '/api/v[0-9]+/')                     AS ApiVersionPos
FROM Ops.HttpLog;

-- Tách chuỗi theo mẫu, trả về rowset
SELECT value FROM REGEXP_SPLIT_TO_TABLE('a1,b22;c333', '[,;]');
```

Ứng dụng thực tế đáng chú ý — validation ở tầng dữ liệu:

```sql
ALTER TABLE Sales.Customers
ADD CONSTRAINT CK_Customers_Email
    CHECK (Email IS NULL OR REGEXP_LIKE(Email, '^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$'));
```

Cảnh báo hiệu năng, giống mọi hàm khác: **regex trong `WHERE` không SARGable**. `WHERE REGEXP_LIKE(Code, '^ABC')` sẽ scan; nếu cần lọc theo tiền tố, dùng `WHERE Code LIKE 'ABC%'` để giữ index seek. Regex là công cụ cho validation, trích xuất, và làm sạch dữ liệu — không phải cho lọc trên đường đi nóng.

---

## 5. Vector, embedding và AI

### 5.1 Kiểu `vector`

```sql
-- Cột lưu embedding, số chiều khai báo cố định
CREATE TABLE Kb.Documents (
    DocID     BIGINT IDENTITY PRIMARY KEY,
    Title     NVARCHAR(400)  NOT NULL,
    Chunk     NVARCHAR(MAX)  NOT NULL,
    Embedding VECTOR(1536)   NULL          -- số chiều khớp model đang dùng
);
```

### 5.2 Similarity search

```sql
DECLARE @q VECTOR(1536) = CAST(@queryEmbeddingJson AS VECTOR(1536));

SELECT TOP 10
    DocID, Title, Chunk,
    VECTOR_DISTANCE('cosine', Embedding, @q) AS Distance
FROM Kb.Documents
WHERE Embedding IS NOT NULL
ORDER BY Distance;      -- càng nhỏ càng gần
```

`VECTOR_DISTANCE` hỗ trợ nhiều metric (`cosine`, `euclidean`, `dot`); chọn metric **khớp với model sinh embedding**, vì dùng sai metric cho ra thứ hạng vô nghĩa.

### 5.3 Vector index (DiskANN)

Không có index, mỗi query so sánh với **mọi** vector (exact nearest neighbor) — chấp nhận được với vài chục nghìn dòng, không chấp nhận được với hàng triệu.

```sql
-- Khung: index xấp xỉ (ANN) dựa trên DiskANN
CREATE VECTOR INDEX VIX_Documents_Embedding
    ON Kb.Documents (Embedding)
    WITH (METRIC = 'cosine', TYPE = 'diskann');
```

Đánh đổi cốt lõi của ANN index: **đổi độ chính xác lấy tốc độ**. Kết quả là "gần đúng" chứ không đảm bảo top-K tuyệt đối. Với semantic search điều đó gần như luôn chấp nhận được; với bài toán đòi hỏi chính xác tuyệt đối thì không.

### 5.4 Sinh embedding bên trong database

```sql
-- Khung: khai báo model bên ngoài rồi gọi từ T-SQL
CREATE EXTERNAL MODEL EmbeddingModel
WITH (
    LOCATION   = 'https://<endpoint>/openai/deployments/text-embedding-3-small/embeddings',
    API_FORMAT = 'Azure OpenAI',
    MODEL_TYPE = EMBEDDINGS,
    MODEL      = 'text-embedding-3-small',
    CREDENTIAL = [https://<endpoint>]
);

-- Sinh và lưu embedding cho các chunk chưa có
UPDATE Kb.Documents
SET Embedding = AI_GENERATE_EMBEDDINGS(Chunk USE MODEL EmbeddingModel)
WHERE Embedding IS NULL;
```

Và `sp_invoke_external_rest_endpoint` cho phép gọi REST API từ T-SQL:

```sql
DECLARE @response NVARCHAR(MAX);
EXEC sp_invoke_external_rest_endpoint
     @url     = N'https://api.internal.corp/v1/score',
     @method  = N'POST',
     @headers = N'{"Content-Type":"application/json"}',
     @payload = N'{"orderId":1001}',
     @response = @response OUTPUT;
```

### 5.5 Khi nào dùng SQL Server làm vector store — và khi nào không

| Nên | Không nên |
|---|---|
| Embedding gắn chặt với dữ liệu quan hệ đã ở SQL Server | Khối lượng vector rất lớn (hàng trăm triệu) |
| Cần **hybrid search**: lọc quan hệ + similarity trong cùng query | Cần các tính năng chuyên biệt của vector DB (nhiều loại index, quantization nâng cao) |
| Muốn giảm số hệ thống phải vận hành | Đã có vector store chuyên dụng chạy tốt |
| Cần transaction giữa dữ liệu và embedding | Workload embedding hoàn toàn tách biệt |

Lợi thế thật của SQL Server ở đây là **hybrid**: một câu query vừa lọc theo quyền/tenant/thời gian (index quan hệ), vừa xếp hạng theo độ tương đồng — thứ mà kiến trúc "vector DB riêng + database riêng" phải làm bằng hai lần truy vấn và ghép ở tầng ứng dụng.

```sql
-- Hybrid: chỉ tìm trong tài liệu mà tenant này được xem
SELECT TOP 10 d.DocID, d.Title, VECTOR_DISTANCE('cosine', d.Embedding, @q) AS Distance
FROM Kb.Documents d
JOIN Kb.DocumentAcl a ON a.DocID = d.DocID
WHERE a.TenantID = @tenantId AND d.UpdatedAt >= @since
ORDER BY Distance;
```

Về `sp_invoke_external_rest_endpoint` và `AI_GENERATE_EMBEDDINGS`: gọi HTTP từ trong transaction database là mẫu cần rất cẩn thận. Endpoint chậm sẽ giữ transaction mở, giữ lock, và chặn truncate log ([transactions.md](../fundamentals/transactions.md) mục 2.2). Với việc sinh embedding cho khối lượng lớn, nên làm theo batch nhỏ, ngoài transaction nghiệp vụ, và có timeout.

---

## 6. Change Event Streaming và Fabric mirroring

### 6.1 Change Event Streaming (CES)

Engine tự publish sự kiện thay đổi ra endpoint bên ngoài (Azure Event Hubs, endpoint tương thích Kafka), không cần CDC + Debezium ở giữa. So sánh chi tiết và khuyến nghị áp dụng ở [data_movement.md](../integration/data_movement.md) mục 6.

Tóm tắt quyết định: xây mới trên 2025 với đích Event Hubs/Kafka thì CES nên được cân nhắc đầu tiên; hệ đang chạy tốt trên CDC + Debezium thì chưa cần chuyển.

### 6.2 Fabric mirroring

Mirroring cho phép đồng bộ gần thời gian thực dữ liệu SQL Server sang Microsoft Fabric OneLake, để dùng cho phân tích mà không phải xây pipeline ETL riêng.

Giá trị: bỏ được một lớp pipeline cho bài toán "đưa dữ liệu OLTP sang lakehouse để BI". Ràng buộc: gắn với hệ sinh thái Fabric — nếu tổ chức dùng nền tảng phân tích khác, mô hình CDC/CES vẫn phù hợp hơn.

---

## 7. Các bổ sung khác

### 7.1 Optional Parameter Plan Optimization (OPPO)

Đây là bổ sung IQP đáng chú ý nhất của 2025 với người viết ứng dụng. Nó xử lý đúng mẫu catch-all mà [query_optimization.md](../performance/query_optimization.md) mục 3 phải chữa bằng `OPTION (RECOMPILE)` hoặc dynamic SQL:

```sql
-- Mẫu này trước đây gần như luôn cho plan tệ
SELECT OrderID, CustomerID, Status, TotalAmount
FROM Sales.Orders
WHERE (@tenantId IS NULL OR TenantID  = @tenantId)
  AND (@status   IS NULL OR Status    = @status)
  AND (@from     IS NULL OR OrderDate >= @from);
```

Với compat level 170, engine có thể sinh plan phù hợp theo tập tham số thực sự được cung cấp, thay vì một plan duy nhất bao mọi tổ hợp.

```sql
ALTER DATABASE SalesDB SET COMPATIBILITY_LEVEL = 170;
-- Tắt riêng nếu gây hồi quy:
-- ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_PLAN_OPTIMIZATION = OFF;
```

Điều này không có nghĩa là nên viết catch-all thoải mái. Query có hình dạng rõ ràng vẫn tốt hơn — OPPO là lưới an toàn cho code đã có, đặc biệt SQL do ORM hoặc công cụ báo cáo sinh ra.

### 7.2 tempdb space resource governance

```sql
-- Khung: giới hạn dung lượng tempdb mà một workload group được dùng
ALTER WORKLOAD GROUP ReportGroup
WITH (GROUP_MAX_TEMPDB_DATA_MB = 20480);
ALTER RESOURCE GOVERNOR RECONFIGURE;
```

Đây là câu trả lời cho một lớp sự cố rất thực: một query báo cáo tồi làm tempdb đầy và **mọi** workload khác dừng ([monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md) mục 3). Trước 2025, không có cách nào giới hạn tempdb theo workload; giờ có.

### 7.3 Bảng tổng hợp so sánh version

| Nhu cầu | 2022 (compat 160) | 2025 (compat 170) |
|---|---|---|
| Giảm blocking do `UPDATE` rộng | RCSI + index + chia batch | + **Optimized Locking** |
| JSON có index | `nvarchar(max)` + computed column | Kiểu **`json`** + **JSON index** |
| Regex trong SQL | Không (CLR hoặc tầng app) | **`REGEXP_*`** |
| Semantic search | Vector store riêng | Kiểu **`vector`** + **DiskANN index** |
| Sinh embedding | Ở tầng ứng dụng | `AI_GENERATE_EMBEDDINGS`, external model |
| Đưa thay đổi ra Kafka | CDC + Debezium | + **Change Event Streaming** |
| Query catch-all nhiều tham số | `OPTION (RECOMPILE)` / dynamic SQL | + **OPPO** |
| Chống một workload chiếm hết tempdb | Không có | **tempdb resource governance** |
| Query lệch theo tham số | **PSP optimization** | PSP + OPPO |
| Sao lưu ra object storage | **S3-compatible** (mới ở 2022) | Như 2022 |
| Bằng chứng chống sửa lịch sử | **Ledger table** (mới ở 2022) | Như 2022 |
| Login/job đi cùng AG | **Contained AG** (mới ở 2022) | Như 2022 |

---

## 8. Quy trình nâng cấp lên 2025

Nâng version binary và nâng compatibility level là **hai việc riêng biệt**, nên làm riêng biệt.

```text
Giai đoạn 1 — nâng binary, giữ compat level cũ
□ Kiểm kê tính năng đang dùng có deprecated/removed không
□ Bật Query Store trên môi trường hiện tại, thu baseline ≥ 1 chu kỳ nghiệp vụ đầy đủ
□ Nâng instance lên 2025, GIỮ compatibility level 160
□ Chạy production; xác nhận không hồi quy (Query Store so với baseline)

Giai đoạn 2 — nâng compat level
□ Nâng lên 170 trên môi trường test có dữ liệu và tải giống production
□ Theo dõi "Regressed Queries" trong Query Store
□ Query nào hồi quy:
    - force plan cũ (biện pháp tạm, có ngày review), HOẶC
    - tắt riêng một IQP feature bằng ALTER DATABASE SCOPED CONFIGURATION
    - KHÔNG lùi cả compat level (sẽ mất mọi cải tiến khác)
□ Nâng compat level trên production trong cửa sổ có thể lùi

Giai đoạn 3 — áp dụng tính năng mới, từng cái một
□ Optimized Locking: cần ADR; kiểm thử lại code phụ thuộc hành vi lock
□ Kiểu json: chỉ chuyển các cột thực sự hưởng lợi, không chuyển hàng loạt
□ REGEXP_*: thay CLR/logic app; nhớ rằng regex không SARGable
□ Vector/AI: bắt đầu bằng một use case hẹp, đo chất lượng kết quả
□ CES: chạy song song với pipeline hiện có trước khi cắt chuyển
```

Nguyên tắc xuyên suốt: **mỗi tính năng mới là một thay đổi riêng, có thể lùi riêng**. Bật cả bốn thứ cùng lúc rồi thấy hiệu năng đổi thì không biết cái nào gây ra.

---

## 9. Trade-offs

| Tính năng | Được | Mất / rủi ro | Khi nào bật |
|---|---|---|---|
| Optimized Locking | Ít lock, ít escalation, ít blocking | Cần ADR (dung lượng PVS); ngữ nghĩa lock đổi tinh vi | Sau khi đã có RCSI và index hợp lý, mà vẫn blocking |
| Kiểu `json` + JSON index | Không parse lại, index được thuộc tính | Phải migrate cột; vẫn kém cột thật cho trục truy vấn chính | Cột JSON hiện đang bị query nhiều |
| `REGEXP_*` | Validation/trích xuất ngay trong SQL | Không SARGable; dễ bị lạm dụng trong `WHERE` | Validation, làm sạch dữ liệu, trích xuất |
| Kiểu `vector` + DiskANN | Hybrid search trong một hệ thống | ANN là xấp xỉ; khối lượng rất lớn thì vector DB chuyên dụng vẫn hơn | Embedding gắn với dữ liệu quan hệ |
| `AI_GENERATE_EMBEDDINGS` / REST endpoint | Không cần pipeline riêng | Gọi HTTP trong transaction là rủi ro; phụ thuộc dịch vụ ngoài | Batch nhỏ, ngoài transaction nghiệp vụ, có timeout |
| Change Event Streaming | Ít thành phần hơn CDC + Debezium | Mới, ít kinh nghiệm cộng đồng | Xây mới, đích Event Hubs/Kafka |
| Fabric mirroring | Bỏ được lớp ETL sang lakehouse | Gắn với hệ sinh thái Fabric | Tổ chức đã dùng Fabric |
| OPPO | Chữa query catch-all mà không sửa code | Không thay thế thiết kế query tốt | Có nhiều SQL do ORM/công cụ sinh |
| tempdb resource governance | Một workload không làm sập cả instance | Cần thiết lập Resource Governor | Hệ multi-tenant hoặc có workload báo cáo nặng |
| Compat level 170 | Mọi IQP mới | Có thể hồi quy vài query | Sau khi có Query Store baseline và quy trình lùi |

---

## 10. Ghi chú – chủ đề tiếp theo

- [transactions.md](../fundamentals/transactions.md): nền tảng của Optimized Locking (ADR, RCSI, lock mode).
- [query_optimization.md](../performance/query_optimization.md): IQP, Query Store, quy trình nâng compat level.
- [data_movement.md](../integration/data_movement.md): CES so với CDC + Debezium.
- [jdbc_java.md](../integration/jdbc_java.md): dùng kiểu `json` và `vector` từ Java.
- [tsql_advanced.md](../fundamentals/tsql_advanced.md): JSON trước 2025, và các hàm 2022.

Từ khóa mở rộng: DiskANN tham số build/query, quantization cho vector, `CREATE EXTERNAL MODEL` với các API format khác, secure enclave cho Always Encrypted, `sys.dm_db_persisted_version_store_stats` (theo dõi PVS), Fabric OneLake shortcut.

---

*Cập nhật lần cuối: 2026-07-30*
