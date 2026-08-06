# PostgreSQL Indexing & Query Planner

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này nối ba mảnh thường bị học
> rời nhau: query shape, statistics/cardinality estimate và index/access path.
> Mục tiêu không phải “ép dùng index”, mà là giúp planner chọn plan ít work nhất.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Architecture & Storage](architecture_storage.md) ·
[Data Modeling & Types](data_modeling_types.md) ·
[Transactions, MVCC & Locking](transactions_mvcc.md).

---

## 1. Index là bản sao có tổ chức, không phải phép tăng tốc miễn phí

PostgreSQL lưu heap và index tách nhau:

```text
query predicate
      │
      ▼
index access method
      │ candidate TID
      ▼
heap page + MVCC visibility
```

Index giúp giảm số row/page phải xét hoặc cung cấp thứ tự sẵn có. Đổi lại:

- INSERT/DELETE và nhiều UPDATE phải bảo trì thêm cấu trúc;
- index chiếm disk, cache và WAL;
- nhiều index giảm cơ hội HOT update;
- planner có thêm candidate plan phải ước lượng;
- index sai có thể không được dùng hoặc làm write chậm hơn.

Câu hỏi đúng không phải “column này có index chưa?”, mà là:

```text
query nào + predicate nào + trả bao nhiêu row + order nào + workload đọc/ghi nào?
```

---

## 2. Planner là cost-based optimizer

Pipeline rút gọn:

```text
SQL
 ↓ parse/rewrite
query tree
 ↓ enumerate scan/join/order/aggregate alternatives
candidate paths
 ↓ estimate rows × cost
cheapest estimated plan
 ↓ executor
actual work
```

Planner không chạy thử mọi plan. Nó dùng:

- table/index metadata và constraint;
- statistics từ `ANALYZE`;
- predicate, join condition, ordering và limit;
- cost constants, memory/parallel settings;
- parameter value nếu lập custom plan.

Khi plan sai, thường cần tìm **estimate đầu tiên lệch mạnh**, không vội tắt
sequential scan hay ép một join method.

---

## 3. Query shape dẫn dắt index design

Giả sử query nóng:

```sql
SELECT
    order_id,
    created_at,
    total,
    currency
FROM app.orders
WHERE customer_id = :customer_id
  AND status = 'PAID'
ORDER BY created_at DESC
LIMIT 50;
```

Candidate index:

```sql
CREATE INDEX orders_customer_status_created_idx
    ON app.orders (customer_id, status, created_at DESC)
    INCLUDE (order_id, total, currency);
```

Lý do:

- equality theo `customer_id`, `status` thu hẹp vùng index;
- `created_at DESC` cung cấp order cho `LIMIT`;
- payload có thể hỗ trợ index-only scan;
- primary key **không tự được nhúng vào mọi secondary index**, nên `order_id`
  được liệt kê rõ trong `INCLUDE`.

Không copy index trên mà chưa đo distribution và write rate.

---

## 4. Selectivity và cardinality quyết định access path

```text
selectivity = matching rows / total rows
cardinality = số row ước lượng ở một plan node
```

Predicate trả 10 row trong 100 triệu row thường hợp index. Predicate trả 60 triệu
row có thể hợp sequential scan vì đọc heap tuần tự rẻ hơn hàng triệu random heap
fetch.

Planner còn cần ước lượng row sau từng bước:

```text
scan  → filter → join → group → sort → limit
```

Một estimate sai ở scan có thể nhân lên thành:

- chọn nested loop chạy inner scan hàng triệu lần;
- hash table/sort spill;
- join order sai;
- parallelism sai;
- index tưởng rẻ nhưng heap I/O rất lớn.

---

## 5. Các scan node chính

| Node | Cách đọc | Phù hợp |
|---|---|---|
| `Seq Scan` | đọc heap tuần tự | phần lớn table hoặc table nhỏ |
| `Index Scan` | index rồi heap theo TID | ít row, cần order |
| `Index Only Scan` | trả từ index nếu visibility cho phép | covering + page all-visible |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | gom TID rồi đọc heap theo page | số row trung bình, kết hợp index |

Không có node nào luôn tốt. Cùng query có thể đổi plan khi:

- parameter chọn common value thay rare value;
- table lớn lên;
- cache/cost setting đổi;
- statistics mới;
- `LIMIT`/projection/order đổi.

---

## 6. Sequential scan không phải dấu hiệu lỗi

Seq scan có lợi khi:

- query cần phần lớn row;
- table nhỏ hơn vài page;
- predicate không selective;
- index dẫn tới nhiều random heap access;
- statistics dự đoán scan+filter rẻ hơn;
- parallel sequential scan giảm elapsed time.

```sql
EXPLAIN
SELECT *
FROM app.orders
WHERE status IN ('PAID', 'CANCELLED');
```

Nếu gần mọi order thuộc hai trạng thái này, index trên `status` khó giúp. Tắt
`enable_seqscan` chỉ để thấy index plan là thí nghiệm chẩn đoán, không phải fix
production.

---

## 7. B-tree là lựa chọn mặc định

B-tree hỗ trợ dữ liệu có linear order:

```text
=, <, <=, >, >=, BETWEEN, IN, IS NULL, IS NOT NULL
```

Nó còn hỗ trợ:

- `ORDER BY` forward/backward;
- unique constraint/index;
- prefix `LIKE 'abc%'` trong điều kiện collation/operator class phù hợp;
- multicolumn và PostgreSQL 18 skip scan;
- index-only scan;
- deduplication trong trường hợp phù hợp.

```sql
CREATE INDEX orders_created_at_idx
    ON app.orders (created_at);
```

B-tree entry quá rộng có giới hạn liên quan page; không index/`INCLUDE` payload lớn
theo thói quen.

---

## 8. B-tree có thể trả thứ tự sẵn có

```sql
CREATE INDEX orders_customer_created_idx
    ON app.orders (customer_id, created_at DESC);
```

Query:

```sql
SELECT order_id, created_at
FROM app.orders
WHERE customer_id = :customer_id
ORDER BY created_at DESC
LIMIT 20;
```

có thể dừng sau 20 entry thay vì tìm mọi row rồi sort.

Thứ tự cần xét đầy đủ:

- ASC/DESC từng column;
- `NULLS FIRST`/`NULLS LAST`;
- equality trên prefix;
- mixed direction trong multicolumn index;
- collation/operator class.

B-tree scan ngược xử lý nhiều trường hợp, nhưng mixed ordering như
`ORDER BY a ASC, b DESC` có thể cần index khai báo đúng direction.

---

## 9. Multicolumn B-tree và quy tắc prefix

Index:

```sql
CREATE INDEX orders_customer_status_created_range_idx
    ON app.orders (customer_id, status, created_at DESC);
```

Hiệu quả nhất khi query có equality trên leading columns rồi inequality/order ở
column kế:

```sql
WHERE customer_id = :customer_id
  AND status = 'PAID'
  AND created_at >= :from_time
```

Mental model:

```text
(customer_id = ?) → một vùng
  (status = ?) → vùng nhỏ hơn
    (created_at >= ?) → range liên tục
```

Condition ở column sau vẫn có thể được kiểm tra trong index nhưng không luôn giảm
phần index phải scan.

---

## 10. PostgreSQL 18 B-tree skip scan

Với index `(x, y)` và chỉ có:

```sql
WHERE y = 7700
```

PostgreSQL 18 có thể tạo dynamic equality cho từng giá trị `x`, thực hiện nhiều
lần tìm kiếm `(x = N, y = 7700)` và bỏ qua phần lớn leaf page.

Skip scan có lợi khi leading column có ít distinct values. Nếu `x` có hàng triệu
giá trị, lặp tìm kiếm thường đắt hơn scan khác.

Hệ quả:

- quy tắc leftmost prefix vẫn là baseline tốt;
- không tạo index thiếu leading predicate chỉ vì “skip scan sẽ cứu”;
- xem `EXPLAIN (ANALYZE, BUFFERS)` trên distribution thật;
- plan có thể đổi khi `n_distinct`/table size thay đổi.

---

## 11. Chọn thứ tự column từ workload

Không áp dụng mù quáng “column selective nhất đứng trước”. Xét:

1. equality predicate phổ biến;
2. range predicate;
3. `ORDER BY` + `LIMIT`;
4. tenant/business boundary;
5. query khác cần prefix nào;
6. update frequency và index width.

Ví dụ:

```text
WHERE customer_id = ? AND status = ? ORDER BY created_at DESC LIMIT 50
```

thường gợi ý `(customer_id, status, created_at DESC)`, dù `created_at` có nhiều giá
trị nhất. Mục tiêu là vùng scan và order, không phải uniqueness thống kê đơn lẻ.

---

## 12. Covering index và `INCLUDE`

```sql
CREATE INDEX orders_customer_created_cover_idx
    ON app.orders (customer_id, created_at DESC)
    INCLUDE (order_id, status, total, currency);
```

Key columns tham gia search/order. `INCLUDE` columns là payload:

- không tham gia search key;
- không ảnh hưởng uniqueness của unique key;
- làm index rộng và tăng write/cache cost;
- giúp query chỉ tham chiếu column trong index có khả năng index-only scan.

Không biến index thành bản sao toàn table. Chỉ cover query nóng, ổn định và đủ lợi
ích I/O.

---

## 13. Index-only scan vẫn có thể đọc heap

MVCC visibility không nằm trong secondary index. Executor kiểm tra visibility map:

```text
all-visible bit = 1 → trả từ index
all-visible bit = 0 → Heap Fetch để kiểm tra tuple
```

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, created_at, total
FROM app.orders
WHERE customer_id = :customer_id
ORDER BY created_at DESC
LIMIT 50;
```

Đọc `Heap Fetches` ở `Index Only Scan`:

- table ít đổi + vacuum tốt: thường thấp;
- table nóng: visibility bit bị clear, heap fetch tăng;
- thêm `INCLUDE` không ép index-only plan;
- GIN không hỗ trợ index-only scan vì entry không giữ toàn original value;
- GiST/SP-GiST chỉ hỗ trợ với một số operator class.

---

## 14. Expression index phải khớp biểu thức

```sql
CREATE UNIQUE INDEX customers_email_lower_uk
    ON app.customers (lower(email));
```

Query phù hợp:

```sql
SELECT customer_id
FROM app.customers
WHERE lower(email) = lower(:email);
```

Expression phải dùng immutable function để index value không tự đổi ngoài write.
Query cần biểu diễn tương thích để planner nhận ra index.

Trade-off:

- expression được tính khi insert/non-HOT update;
- tăng write cost;
- có statistics riêng sau `ANALYZE`;
- normalization/collation semantics phải là contract, không chỉ optimization.

Nếu application luôn query raw `email = ?`, expression index `lower(email)` không
tự giúp.

---

## 15. Partial index chỉ index subset

```sql
CREATE INDEX orders_pending_customer_idx
    ON app.orders (customer_id, created_at)
    WHERE status = 'PENDING';
```

Hữu ích khi active/unprocessed rows là phần nhỏ nhưng được query nhiều:

```sql
SELECT *
FROM app.orders
WHERE status = 'PENDING'
  AND customer_id = :customer_id;
```

Planner chỉ dùng partial index khi chứng minh query predicate kéo theo index
predicate tại planning time. PostgreSQL không có theorem prover tổng quát; biểu
thức tương đương viết khác có thể không match.

Generic parameter như `status = $1` thường không chứng minh được
`status = 'PENDING'` cho mọi value. Kiểm tra cả custom và generic plan.

---

## 16. Partial unique index cho conditional invariant

Một customer chỉ có một cart đang mở:

```sql
CREATE UNIQUE INDEX carts_one_open_per_customer_uk
    ON app.carts (customer_id)
    WHERE state = 'OPEN';
```

Đây vừa là index vừa đóng concurrency race. Lưu ý:

- partial unique index không phải regular unique constraint;
- không dùng làm referenced key FK thông thường;
- predicate/state transition phải được test;
- nhiều partial index theo từng category không thay partitioning;
- distribution thay đổi có thể làm lợi ích biến mất.

---

## 17. Hash index có phạm vi hẹp

```sql
CREATE INDEX api_requests_token_hash_idx
    ON app.api_requests USING hash (request_token);
```

Hash index PostgreSQL 18:

- chỉ hỗ trợ `=`;
- chỉ một key column;
- không enforce unique;
- không hỗ trợ range/order;
- lưu hash 4 byte nên có thể nhỏ hơn B-tree cho value dài;
- là on-disk, WAL-logged và crash-recoverable.

B-tree cũng xử lý equality và linh hoạt hơn. Chọn hash chỉ sau benchmark cho
equality-only workload, index size/cache và collision-chain behavior.

---

## 18. GiST là framework cho domain search

GiST không phải một thuật toán duy nhất. Operator class quyết định semantics:

- range overlap/containment;
- geometry;
- nearest-neighbor `ORDER BY <-> LIMIT`;
- text similarity qua extension như `pg_trgm`;
- exclusion constraint.

```sql
CREATE INDEX room_bookings_occupied_gist_idx
    ON app.room_bookings USING gist (occupied_at);
```

Query:

```sql
SELECT *
FROM app.room_bookings
WHERE occupied_at && tstzrange(:from_time, :to_time, '[)');
```

GiST có thể trả candidate cần recheck tùy operator class. Đừng đánh giá chỉ bằng
tên index; xem operator, recheck rows và distribution.

---

## 19. SP-GiST cho không gian phân hoạch

SP-GiST hỗ trợ các cấu trúc không cân bằng như trie, quadtree và k-d tree. Use case
phụ thuộc operator class:

- prefix/radix partitioning;
- point/space partitioning;
- nearest-neighbor với class hỗ trợ.

```sql
CREATE INDEX network_prefix_spgist_idx
    ON app.network_rules USING spgist (network inet_ops);
```

Không chọn SP-GiST vì “nghe nhanh hơn GiST”. Kiểm tra type/operator class, data
distribution, build/write cost và query thật.

---

## 20. GIN là inverted index

GIN tách một value thành nhiều component:

```text
document/array → key₁, key₂, key₃ ... → posting lists của row TID
```

Phù hợp:

- JSONB containment/path;
- array membership/overlap;
- full-text `tsvector`;
- trigram search qua `pg_trgm`.

```sql
CREATE INDEX catalog_items_attributes_gin_idx
    ON app.catalog_items USING gin (attributes);
```

GIN read mạnh nhưng write/build có thể nặng. Pending list (`fastupdate`) giúp gom
insert rồi merge; burst cleanup có thể tạo latency/I/O. Đo write path và index
size, không chỉ query demo.

---

## 21. JSONB operator class phải khớp operator

Default:

```sql
CREATE INDEX catalog_attributes_ops_idx
    ON app.catalog_items USING gin (attributes);
```

`jsonb_ops` hỗ trợ `?`, `?|`, `?&`, `@>`, `@?`, `@@`.

Containment/path focused:

```sql
CREATE INDEX catalog_attributes_path_idx
    ON app.catalog_items
    USING gin (attributes jsonb_path_ops);
```

`jsonb_path_ops` hỗ trợ `@>`, `@?`, `@@`, thường nhỏ/specific hơn nhưng không hỗ
trợ key-exists.

Index toàn document linh hoạt nhưng rộng. Path nóng có thể dùng expression index:

```sql
CREATE INDEX catalog_brand_idx
    ON app.catalog_items ((attributes ->> 'brand'));
```

---

## 22. BRIN tóm tắt block range

BRIN không chứa entry cho từng row. Nó lưu summary cho nhóm physical heap pages:

```text
block range 0..127   → min/max created_at
block range 128..255 → min/max created_at
```

```sql
CREATE INDEX orders_created_brin_idx
    ON app.orders USING brin (created_at)
    WITH (pages_per_range = 64);
```

Tốt khi:

- table rất lớn;
- column tương quan với physical order, như append-only timestamp;
- query range loại được nhiều block range;
- chấp nhận lossy recheck.

BRIN rất nhỏ nhưng không thay B-tree cho point lookup. UPDATE/backfill phá
correlation làm hiệu quả giảm; `pages_per_range` đổi size so với precision.

---

## 23. Operator class và collation là một phần index contract

Index method không tự hỗ trợ mọi operator/type. Operator class ánh xạ operator vào
search strategy.

Prefix search trong non-`C` locale có thể cần:

```sql
CREATE INDEX customers_email_pattern_idx
    ON app.customers (email text_pattern_ops);
```

cho query như:

```sql
WHERE email LIKE 'admin%'
```

`LIKE '%admin%'` không trở thành B-tree prefix lookup; có thể cần trigram GIN/GiST
nếu workload biện minh.

Collation quyết định equality/order. Index với collation khác query có thể không
được dùng; collation version upgrade có thể yêu cầu kiểm tra/reindex.

---

## 24. Bitmap scan kết hợp nhiều index

```sql
CREATE INDEX orders_customer_idx ON app.orders (customer_id);
CREATE INDEX orders_status_idx ON app.orders (status);
```

Planner có thể tạo bitmap từ mỗi index rồi `AND`/`OR`:

```text
Bitmap Index Scan customer
        AND
Bitmap Index Scan status
        ↓
Bitmap Heap Scan theo heap page order
```

Ưu điểm: giảm random heap access, kết hợp index đơn. Đổi lại:

- mất index ordering nên có thể cần sort;
- bitmap lossy khi memory hạn chế, cần recheck;
- composite index đúng query thường tốt hơn cho selective `AND + ORDER BY`;
- `work_mem` ảnh hưởng bitmap precision.

---

## 25. Một composite hay nhiều index đơn?

Chọn composite khi query ổn định cần:

```text
WHERE a = ? AND b = ? ORDER BY c LIMIT n
```

Chọn index đơn/bitmap khi workload cần nhiều tổ hợp độc lập của `a`, `b` và số row
trung bình.

So sánh:

| Thiết kế | Điểm mạnh | Điểm yếu |
|---|---|---|
| `(a,b,c)` | filter/order rất tốt cho shape đích | ít hữu ích nếu bỏ leading prefix |
| index `a`, index `b` | linh hoạt bitmap | mất order, nhiều heap/recheck hơn |
| cả hai | nhiều lựa chọn | write/disk/cache/planning cost |

Giữ tối thiểu tập index phục vụ workload, không tối đa số candidate.

---

## 26. Index trùng và overlap

PK/UNIQUE đã tạo unique B-tree index. Đừng thêm bản sao:

```sql
-- Thừa nếu order_id đã là PRIMARY KEY:
CREATE INDEX orders_order_id_idx ON app.orders (order_id);
```

Index `(a,b)` có thể phục vụ nhiều query chỉ theo `a`, nhưng không mặc nhiên thay
mọi index `(a)`: khác width, partial predicate, ordering, INCLUDE và workload.

Trước khi xóa overlap index, kiểm tra:

- constraint ownership;
- query trên primary và replica;
- statistics reset/failover window;
- prepared/generic plan;
- lock/build rollback plan;
- peak/seasonal jobs.

---

## 27. Index làm write amplification và cản HOT

Mỗi index liên quan column bị đổi có thể cần entry mới:

```text
UPDATE heap
├── WAL heap
├── index A maintenance
├── index B maintenance
└── index C maintenance
```

HOT update chỉ có cơ hội khi indexed columns không đổi và page còn chỗ. Thêm index
cho column thường đổi có thể biến HOT thành non-HOT, tăng index bloat/WAL.

Đo:

```sql
SELECT
    relname,
    n_tup_upd,
    n_tup_hot_upd,
    CASE
        WHEN n_tup_upd = 0 THEN 0
        ELSE round(100.0 * n_tup_hot_upd / n_tup_upd, 2)
    END AS hot_update_pct
FROM pg_stat_user_tables
ORDER BY n_tup_upd DESC;
```

---

## 28. Tạo index thường và concurrently

```sql
CREATE INDEX orders_customer_idx
    ON app.orders (customer_id);
```

Build thường nhanh hơn nhưng chặn write trên table trong lúc build.

Production OLTP thường cân nhắc:

```sql
CREATE INDEX CONCURRENTLY orders_customer_idx
    ON app.orders (customer_id);
```

Concurrent build:

- không chạy trong transaction block;
- scan table nhiều phase và chờ transaction cũ;
- lâu hơn, dùng CPU/I/O/WAL;
- chỉ một concurrent index build trên cùng table tại một thời điểm;
- fail có thể để invalid index vẫn tăng write overhead;
- unique concurrent build có caveat enforcement trong phase build.

`IF NOT EXISTS` chỉ kiểm tra tên, không chứng minh definition tương đương.

---

## 29. Theo dõi build và invalid index

```sql
SELECT
    pid,
    datname,
    relid::regclass AS table_name,
    index_relid::regclass AS index_name,
    phase,
    blocks_done,
    blocks_total,
    tuples_done,
    tuples_total
FROM pg_stat_progress_create_index;
```

Audit validity:

```sql
SELECT
    n.nspname AS schema_name,
    c.relname AS index_name,
    i.indisvalid,
    i.indisready,
    pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index AS i
JOIN pg_class AS c ON c.oid = i.indexrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE NOT i.indisvalid OR NOT i.indisready
ORDER BY n.nspname, c.relname;
```

Không drop invalid index tự động chỉ theo tên. Xác định operation, constraint và
runbook; `REINDEX INDEX CONCURRENTLY` có thể sửa một số trường hợp.

---

## 30. REINDEX không phải routine theo lịch mù

```sql
REINDEX INDEX CONCURRENTLY app.orders_customer_idx;
```

Dùng khi có evidence:

- corruption;
- bloat đáng kể và rebuild có ROI;
- storage parameter/collation change cần rebuild;
- failed concurrent build để lại invalid index phù hợp xử lý.

Concurrent reindex vẫn scan, chờ transaction và tốn disk cho copy mới. Chuẩn bị
headroom, replica lag/WAL và cancellation cleanup. Bloat root cause có thể là long
transaction, update pattern hoặc autovacuum; rebuild mà không sửa cause chỉ reset
đồng hồ.

---

## 31. Statistics là input, không phải dữ liệu chính xác tuyệt đối

`ANALYZE` sample dữ liệu và tạo thống kê như:

- `null_frac`;
- `n_distinct`;
- most common values/frequencies;
- histogram bounds;
- physical correlation;
- average width.

Xem view an toàn hơn catalog raw:

```sql
SELECT
    schemaname,
    tablename,
    attname,
    null_frac,
    n_distinct,
    most_common_vals,
    most_common_freqs,
    histogram_bounds,
    correlation
FROM pg_stats
WHERE schemaname = 'app'
  AND tablename = 'orders';
```

Sample ngẫu nhiên nghĩa là estimate có thể thay nhẹ sau `ANALYZE` dù data gần như
không đổi.

---

## 32. `ANALYZE` sau bulk load hoặc distribution shift

Autovacuum thường tự analyze, nhưng sau bulk load/backfill lớn:

```sql
ANALYZE app.orders;
```

Hoặc column quan trọng:

```sql
ANALYZE app.orders (customer_id, status, created_at);
```

`ANALYZE` không tạo index và không sửa query. Nó giúp planner biết hiện trạng.

Kiểm tra freshness:

```sql
SELECT
    relname,
    n_live_tup,
    n_mod_since_analyze,
    last_analyze,
    last_autoanalyze,
    analyze_count,
    autoanalyze_count
FROM pg_stat_user_tables
ORDER BY n_mod_since_analyze DESC;
```

---

## 33. Statistics target cho column skew cao

Default target là compromise. Tăng riêng column khi MCV/histogram quá thô:

```sql
ALTER TABLE app.orders
    ALTER COLUMN customer_id SET STATISTICS 500;

ANALYZE app.orders (customer_id);
```

Target cao:

- sample lớn và statistics chi tiết hơn;
- `ANALYZE`/planning/storage metadata tốn hơn;
- không đảm bảo sửa correlation xuyên column;
- không nên tăng global vì một query.

Dùng khi `EXPLAIN ANALYZE` chứng minh row estimate sai do distribution một column.

---

## 34. Extended statistics cho column phụ thuộc nhau

Planner mặc định có thể giả định predicate độc lập. Ví dụ một số customer chỉ có
một vài trạng thái order thường gặp:

```text
P(customer_id=42 AND status='PAID')
≈ P(customer_id=42) × P(status='PAID')
```

Hai column thực tế có thể tương quan. Tạo:

```sql
CREATE STATISTICS orders_customer_status_stats
    (dependencies, mcv, ndistinct)
    ON customer_id, status
    FROM app.orders;

ANALYZE app.orders;
```

Các loại:

- `dependencies`: functional dependency;
- `mcv`: common combinations;
- `ndistinct`: distinct combinations, hữu ích group estimate.

PostgreSQL 18 chưa dùng extended statistics cho selectivity estimate của table
join. Tạo đúng tổ hợp xuất hiện cùng nhau; không phủ mọi combination.

---

## 35. Cost unit không phải millisecond

Plan hiển thị:

```text
cost=startup..total rows=estimate width=bytes
```

- startup: cost trước row đầu;
- total: cost để trả toàn bộ output;
- `LIMIT`/`EXISTS` có thể ưu tiên startup cost;
- cost là đơn vị tương đối, không phải runtime dự báo.

Các setting quan trọng:

```sql
SHOW seq_page_cost;
SHOW random_page_cost;
SHOW cpu_tuple_cost;
SHOW effective_cache_size;
SHOW work_mem;
```

`effective_cache_size` chỉ là giả định planner về cache khả dụng, không cấp RAM.
Cost constants nên phản ánh workload trung bình; đổi vì một query là rủi ro.

---

## 36. Correlation và random heap fetch

Column correlation gần `1` hoặc `-1` nghĩa physical row order gần cùng/ngược value
order. Index range scan khi heap correlated có thể đọc page tuần tự hơn.

BRIN cũng hưởng lợi lớn từ correlation. Nhưng:

- heap không tự giữ thứ tự theo primary key;
- insert/update làm correlation đổi;
- `CLUSTER` là one-time physical rewrite, không duy trì tự động;
- correlation tốt cho một column có thể xấu cho column khác.

Đừng dùng `CLUSTER` như fix nhẹ: nó cần lock/rewrite/disk/WAL planning.

---

## 37. Ba join algorithm chính

| Join | Cơ chế | Thường tốt khi |
|---|---|---|
| Nested Loop | mỗi outer row tìm inner | outer nhỏ, inner lookup có index |
| Hash Join | build hash một input, scan/probe input kia | equality join, tập vừa/lớn |
| Merge Join | hai input có thứ tự rồi merge | equality/order, input đã sorted/indexed |

Nested loop không xấu; nó xấu khi planner nghĩ outer có 10 row nhưng thực tế 1
triệu row. Hash join có thể spill nếu hash vượt memory. Merge join có thể cần sort.

Index trên join key giúp nested loop và đôi khi order cho merge, nhưng hash join
có thể bỏ qua index vì sequential input rẻ hơn.

---

## 38. Sort, aggregate và `work_mem`

Plan có thể gồm:

- `Sort`, `Incremental Sort`;
- `HashAggregate`, `GroupAggregate`;
- hash join;
- materialize/memoize.

`work_mem` áp dụng cho từng operation/node/worker, không phải một lần mỗi query.
`EXPLAIN ANALYZE` cho biết sort method, memory và disk spill trong nhiều node.

Index order có thể bỏ sort, nhưng index rộng chỉ để tránh một sort nhỏ chưa chắc có
ROI. So sánh read latency với write/disk/cache cost.

---

## 39. `EXPLAIN` trước, `EXPLAIN ANALYZE` sau

Không thực thi:

```sql
EXPLAIN (COSTS, VERBOSE, SETTINGS)
SELECT ...;
```

Thực thi thật:

```sql
EXPLAIN (
    ANALYZE,
    BUFFERS,
    WAL,
    SETTINGS,
    SUMMARY,
    FORMAT TEXT
)
SELECT ...;
```

PostgreSQL 18 còn có `MEMORY` cho planner memory và `SERIALIZE` để đo output
conversion/serialization. Chỉ bật khi câu hỏi chẩn đoán cần.

`EXPLAIN ANALYZE` có profiling overhead; đo lặp, warm/cold cache và production-like
data thay vì coi một lần chạy là benchmark.

---

## 40. Đọc plan từ node có estimate lệch

Ở mỗi node so:

```text
estimated rows
actual rows × loops
```

Nếu:

```text
rows=10 (actual rows=100000 loops=1)
```

thì estimate lệch 10.000 lần. Tìm node thấp nhất bắt đầu lệch, kiểm tra:

- stale statistics;
- skew/MCV;
- correlated predicates;
- expression/cast;
- parameter value;
- join estimate limitation.

Đừng chỉ nhìn node top có runtime cao; nó có thể là nạn nhân của estimate sai bên
dưới.

---

## 41. `loops` và time dễ bị đọc sai

Text `EXPLAIN ANALYZE` thường hiển thị actual time/rows trung bình **mỗi loop**.
Tổng work gần:

```text
actual rows per loop × loops
```

Nested loop inner node:

```text
actual rows=1 loops=500000
```

không phải chỉ trả một row tổng cộng.

`actual time` của parent bao gồm thời gian child, nên không cộng mọi node time như
các số độc lập. Parallel worker output còn cần đọc worker detail khi `VERBOSE`.

---

## 42. Đọc BUFFERS, temp và WAL

Các chỉ số:

- `shared hit`: page tìm thấy trong PostgreSQL shared buffers;
- `shared read`: PostgreSQL yêu cầu read; OS cache vẫn có thể phục vụ, không đồng
  nghĩa physical disk chắc chắn;
- `dirtied`/`written`: buffer thay đổi/ghi trong execution context;
- `temp read/write`: spill sort/hash/materialize;
- `WAL records/bytes`: write amplification của DML.

I/O timing chỉ có khi tracking phù hợp được bật. Buffer count thường ổn định hơn
elapsed time để so work giữa hai plan.

---

## 43. Filter, recheck và heap fetch là evidence

Các field đáng đọc:

- `Rows Removed by Filter`: scan lấy nhiều rồi loại;
- `Rows Removed by Index Recheck`: lossy candidate;
- `Recheck Cond`: bitmap/GIN/GiST/BRIN cần xác nhận;
- `Heap Blocks: exact/lossy`: bitmap precision;
- `Heap Fetches`: index-only vẫn vào heap;
- `Sort Method`: memory hay external disk;
- `Batches`: hash có chia batch/spill;
- `Planning Time` và `Execution Time`.

Một index được dùng chưa có nghĩa plan tốt: index scan có thể đọc gần toàn index và
heap.

---

## 44. `EXPLAIN ANALYZE` DML thật sự ghi dữ liệu

An toàn tương đối trên môi trường test:

```sql
BEGIN;

EXPLAIN (ANALYZE, BUFFERS, WAL)
UPDATE app.orders
SET status = 'CANCELLED'
WHERE order_id = :order_id;

ROLLBACK;
```

Rollback database changes nhưng sequence và external side effect của function/
trigger có thể không rollback. Statement vẫn lấy lock, tạo WAL/work và có thể gây
contention. Trên production, ưu tiên replica/clone hoặc `EXPLAIN` không `ANALYZE`
khi rủi ro cao.

---

## 45. Generic và custom prepared plan

Custom plan biết parameter value; generic plan dùng chung cho mọi value. Với skew:

```text
tenant nhỏ → index scan tốt
tenant cực lớn → seq/bitmap scan tốt
```

Một generic plan có thể là compromise tệ cho extreme tenant.

```sql
PREPARE recent_orders (bigint) AS
SELECT *
FROM app.orders
WHERE customer_id = $1
ORDER BY created_at DESC
LIMIT 50;

EXPLAIN (ANALYZE, BUFFERS)
EXECUTE recent_orders(42);
```

Quan sát session:

```sql
SELECT
    name,
    generic_plans,
    custom_plans,
    statement
FROM pg_prepared_statements;
```

`plan_cache_mode` là diagnostic/control sắc; không force global trước khi chứng
minh parameter-sensitive regression.

---

## 46. Quy trình xử lý plan regression

```text
1. Capture query + binds + schema/version/settings
2. Capture EXPLAIN ANALYZE BUFFERS/WAL khi an toàn
3. Tìm estimate đầu tiên lệch
4. Kiểm tra data distribution + stats freshness
5. Kiểm tra query semantics/casts/functions
6. So candidate index/statistics/query rewrite
7. Benchmark read và write trên data giống production
8. Deploy có rollback + theo dõi p95/p99/WAL/CPU/I/O
```

So sánh plan trước/sau dưới cùng parameter và cache condition. Plan text đổi chưa
chắc regression; outcome là latency, resource và correctness.

---

## 47. Planner toggle chỉ để thí nghiệm

```sql
SET LOCAL enable_seqscan = off;
SET LOCAL enable_hashjoin = off;
```

Các toggle không tuyệt đối loại bỏ mọi plan và không phải hint ổn định. Dùng để hỏi:

- “index alternative có nhanh hơn thật không?”;
- “hash join đang che estimate issue nào?”;
- “sort/index order trade-off ra sao?”.

Sau thí nghiệm, sửa root cause: statistics, index, query, data model hoặc cost model
đã được benchmark. Không ship session toggle rải rác trong application.

---

## 48. Audit usage nhưng không xóa index bằng một counter

```sql
SELECT
    s.schemaname,
    s.relname AS table_name,
    s.indexrelname AS index_name,
    s.idx_scan,
    s.idx_tup_read,
    s.idx_tup_fetch,
    pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size
FROM pg_stat_user_indexes AS s
ORDER BY s.idx_scan, pg_relation_size(s.indexrelid) DESC;
```

`idx_scan = 0` chưa đủ để drop:

- statistics có thể vừa reset/restart/failover;
- index enforce PK/UNIQUE/EXCLUDE;
- query chỉ chạy cuối tháng/sự cố;
- replica workload khác primary;
- index có thể hỗ trợ FK parent/maintenance;
- một số access method/bitmap execution làm counter cần hiểu đúng phiên bản.

Review qua full business cycle và dependency trước thay đổi.

---

## 49. Decision matrix

| Query/data shape | Candidate đầu tiên |
|---|---|
| equality/range/order | B-tree |
| equality-only, value dài, benchmark chứng minh | Hash |
| range overlap/nearest neighbor/domain opclass | GiST |
| trie/quadtree/k-d partition search | SP-GiST |
| JSONB/array/full-text components | GIN |
| table append-only cực lớn, correlated range | BRIN |
| conditional active subset | Partial index |
| normalized/computed predicate | Expression index |
| hot query cần chỉ index payload | B-tree + `INCLUDE`, nếu visibility phù hợp |
| nhiều predicates trung bình | Bitmap combine hoặc composite sau benchmark |

Đây là điểm bắt đầu, không phải đáp án không cần `EXPLAIN`.

---

## 50. Failure modes thường gặp

### “Có index thì query phải dùng”

Planner có thể đúng khi chọn seq scan vì query trả phần lớn table hoặc heap access
quá đắt.

### “Đặt column selective nhất trước”

Bỏ qua equality prefix, order/limit và query reuse. Column order phải theo workload.

### “Index-only scan nghĩa là không bao giờ đọc heap”

Visibility map quyết định `Heap Fetches`; table nóng vẫn vào heap.

### “Partial index nhỏ nên prepared query chắc dùng”

Planner phải chứng minh predicate implication tại plan time; generic parameter có
thể làm index không usable.

### “Mỗi filter một index rồi bitmap tự lo”

Bitmap mất ordering và có recheck/heap cost. Composite index có thể hợp query nóng
hơn, nhưng nhiều composite lại tăng write amplification.

### “Estimate sai thì tăng statistics target toàn server”

Sai có thể do correlation xuyên column, expression, join hoặc parameter skew. Chẩn
đoán node đầu tiên trước.

### “`EXPLAIN ANALYZE` chỉ đọc”

Nó thực thi DML và trigger thật; rollback không hoàn tác mọi external/sequence side
effect.

### “Index unused thì drop ngay”

Counter có window/reset và index có thể enforce constraint hay phục vụ rare job.

---

## 51. Checklist production

### Query shape

- [ ] Có query/bind/row count/order/limit thật?
- [ ] Selectivity khác nhau giữa tenant/status/parameter?
- [ ] Query cần first rows nhanh hay toàn bộ result?
- [ ] Cast/function/collation có khớp index expression/opclass?
- [ ] N+1 hoặc query semantics đã được sửa trước khi thêm index?

### Index design

- [ ] Method/operator class đúng operator?
- [ ] Multicolumn order theo equality → range/order và workload?
- [ ] `INCLUDE` chỉ chứa payload cần thiết?
- [ ] Partial predicate được query/generic plan chứng minh?
- [ ] Không trùng PK/UNIQUE hoặc overlap vô ích?

### Estimate và EXPLAIN

- [ ] Statistics mới sau bulk load/distribution shift?
- [ ] Đã tìm node thấp nhất estimate lệch?
- [ ] Correlated columns có extended statistics phù hợp?
- [ ] Đọc `loops`, filter/recheck, heap fetch, temp, buffers/WAL?
- [ ] Benchmark nhiều parameter và cache state?

### Write/operation

- [ ] Đo INSERT/UPDATE/WAL/HOT impact?
- [ ] Build/reindex có disk, I/O, replica lag và lock plan?
- [ ] Concurrent build chạy ngoài transaction và có invalid-index runbook?
- [ ] Không đổi cost constants/planner toggles vì một query?
- [ ] Drop index review đủ business cycle, constraint và replica usage?

---

## 52. Câu hỏi phỏng vấn

1. Vì sao PostgreSQL chọn sequential scan dù column có index?
2. Selectivity và cardinality estimate khác nhau thế nào?
3. Index Scan, Bitmap Heap Scan và Index Only Scan khác nhau gì?
4. B-tree hỗ trợ operator và ordering nào?
5. Quy tắc leading prefix của multicolumn B-tree là gì?
6. Skip scan PostgreSQL 18 hoạt động tốt khi nào?
7. Vì sao “column selective nhất trước” không luôn đúng?
8. `INCLUDE` khác key column thế nào?
9. Vì sao Index Only Scan vẫn có Heap Fetches?
10. Expression index ảnh hưởng HOT/write ra sao?
11. Vì sao partial index có thể không dùng với generic parameter?
12. Partial unique index khác unique constraint thế nào?
13. Hash index đánh đổi gì so với B-tree?
14. GiST, SP-GiST, GIN và BRIN phù hợp data shape nào?
15. `jsonb_ops` và `jsonb_path_ops` khác nhau ra sao?
16. Bitmap scan kết hợp index và mất ordering thế nào?
17. Index thừa làm write amplification và HOT giảm ra sao?
18. `CREATE INDEX CONCURRENTLY` có caveat nào?
19. `ANALYZE` thu thập statistics gì?
20. Extended statistics `dependencies`, `mcv`, `ndistinct` sửa estimate nào?
21. Vì sao extended statistics chưa sửa mọi join estimate?
22. Cost trong EXPLAIN có phải millisecond không?
23. Nested loop, hash join và merge join phù hợp trường hợp nào?
24. Đọc `actual rows` và `loops` thế nào?
25. Shared read có chắc là physical disk read không?
26. Cách tìm estimate đầu tiên gây plan regression?
27. Generic/custom prepared plan gây parameter-sensitive plan ra sao?
28. Vì sao không drop index chỉ vì `idx_scan = 0`?

---

## 53. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [Indexes](https://www.postgresql.org/docs/18/indexes.html)
- [Index types](https://www.postgresql.org/docs/18/indexes-types.html)
- [Multicolumn indexes và skip scan](https://www.postgresql.org/docs/18/indexes-multicolumn.html)
- [Combining indexes](https://www.postgresql.org/docs/18/indexes-bitmap-scans.html)
- [Expression indexes](https://www.postgresql.org/docs/18/indexes-expressional.html)
- [Partial indexes](https://www.postgresql.org/docs/18/indexes-partial.html)
- [Index-only scans và covering indexes](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)
- [Built-in index access methods](https://www.postgresql.org/docs/18/indextypes.html)
- [Planner statistics](https://www.postgresql.org/docs/18/planner-stats.html)
- [CREATE STATISTICS](https://www.postgresql.org/docs/18/sql-createstatistics.html)
- [ANALYZE](https://www.postgresql.org/docs/18/sql-analyze.html)
- [Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html)
- [EXPLAIN command](https://www.postgresql.org/docs/18/sql-explain.html)
- [Planner cost configuration](https://www.postgresql.org/docs/18/runtime-config-query.html)
- [CREATE INDEX](https://www.postgresql.org/docs/18/sql-createindex.html)
- [REINDEX](https://www.postgresql.org/docs/18/sql-reindex.html)

Học tiếp:

1. [Advanced SQL](advanced_sql.md).
2. [Performance & Autovacuum](../performance/tuning_autovacuum.md).
3. [PostgreSQL từ Java/Spring](../integration/jdbc_spring.md).

---

*Cập nhật lần cuối: 2026-07-31.*
