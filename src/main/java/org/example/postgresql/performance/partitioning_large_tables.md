# PostgreSQL Partitioning & Large Tables

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này xem partitioning như một quyết định
> physical design và lifecycle: partition key phải giúp pruning, retention và maintenance,
> đồng thời không làm planning, constraint và migration phức tạp quá mức.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Data Modeling & Types](../fundamentals/data_modeling_types.md) ·
[Transactions, MVCC & Locking](../fundamentals/transactions_mvcc.md) ·
[Indexing & Query Planner](../fundamentals/indexing_planner.md) ·
[Performance & Autovacuum](tuning_autovacuum.md).

---

## 1. Partitioning không tự làm mọi query nhanh hơn

Partitioning chia một logical table thành nhiều physical table. Nó hữu ích khi query hoặc
lifecycle có thể bỏ qua phần lớn dữ liệu:

```text
logical table
    ├── old/cold partition       ← prune hoặc detach
    ├── recent partitions        ← phần lớn traffic
    └── future/default boundary  ← routing safety
```

Nếu query vẫn đọc mọi partition, tổng work có thể bằng hoặc lớn hơn table thường vì phải
plan nhiều relation, mở nhiều index và hợp nhất nhiều subplan. Partitioning không thay thế:

- index đúng query shape;
- statistics chính xác;
- query predicate chọn lọc;
- retention policy;
- capacity planning.

---

## 2. Parent là virtual table, leaf mới chứa dữ liệu

Declarative partitioned parent không có heap storage riêng. Row insert qua parent được route
đến một leaf partition theo partition bound.

```text
app.order_events               partitioned parent
├── order_events_2026_07       ordinary leaf table + indexes
├── order_events_2026_08       ordinary leaf table + indexes
└── order_events_default       ordinary/default partition
```

Mỗi leaf là table: có heap, index, statistics, vacuum state, storage parameters và có thể
được query trực tiếp. Partition cũng có thể là partitioned table để tạo nhiều tầng.

---

## 3. Khi partitioning thường có ROI

Các tín hiệu mạnh:

- retention xóa trọn một time range/tenant group;
- đa số query có predicate tương thích partition key và chỉ chạm ít partition;
- hot working set nhỏ hơn nhiều so với toàn bảng;
- bulk load có thể chuẩn bị riêng rồi attach;
- maintenance cần cô lập theo time range;
- một partition có thể sequential scan hiệu quả hơn random access toàn bảng;
- cold data cần tablespace/storage policy riêng.

Kích thước tuyệt đối không quyết định một mình. Table rất lớn nhưng lookup luôn qua một
global-style B-tree phù hợp có thể chưa cần partition; table nhỏ hơn nhưng retention theo
ngày có thể hưởng lợi vận hành.

---

## 4. Khi không nên partition

Không partition chỉ vì “table hơn 10 triệu row”. Dấu hiệu phản đối:

- query không filter theo candidate key;
- row thường đổi partition key;
- cần uniqueness toàn bảng nhưng key không thể chứa partition key;
- số tenant/time bucket sẽ tăng thành hàng chục nghìn relation;
- retention xóa row rải đều trong mọi partition;
- team chưa có automation tạo, kiểm tra và retire partition;
- bottleneck thật là lock, query shape, stale statistics hoặc storage.

Một table thường với index/BRIN phù hợp thường đơn giản hơn một partition tree không prune.

---

## 5. Chọn key từ query và lifecycle cùng lúc

Đánh giá candidate key bằng bốn câu hỏi:

| Câu hỏi | Mục tiêu |
|---|---|
| Predicate nào xuất hiện thường xuyên? | pruning phần lớn partition |
| Data nào bị xóa/archive cùng nhau? | detach/drop nguyên partition |
| Unique/PK/FK cần contract gì? | tránh mất global invariant |
| Cardinality sẽ tăng thế nào? | tránh partition-per-value vô hạn |

Time key thường hợp event/log/order history. Tenant key chỉ hợp khi số tenant lớn có giới
hạn hoặc dùng hash bucket ổn định; một partition cho mỗi tenant SaaS nhỏ thường không scale.

---

## 6. Chọn granularity bằng budget, không theo lịch đẹp

Một partition mỗi ngày, tháng hay quý là trade-off:

```text
partition quá lớn  → index/maintenance/retention unit lớn
partition quá nhỏ  → planning/catalog/session-memory/DDL overhead lớn
```

Ước lượng:

```text
partition size ≈ ingest bytes/day × days per partition
partition count ≈ retention days / days per partition + future headroom
```

Sau đó chạy workload thật: số partition còn lại sau pruning, planning time, execution time,
index size, vacuum duration và thời gian attach/detach. Không có một kích thước MB/GB đúng
cho mọi hệ thống.

---

## 7. RANGE phù hợp time và ordered domain

Schema xuyên suốt:

```sql
CREATE TABLE app.order_events (
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    tenant_id bigint NOT NULL,
    external_id text NOT NULL,
    event_type text NOT NULL,
    occurred_at timestamptz NOT NULL,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (occurred_at, event_id)
) PARTITION BY RANGE (occurred_at);
```

Tạo monthly leaf:

```sql
CREATE TABLE app.order_events_2026_07
PARTITION OF app.order_events
FOR VALUES FROM ('2026-07-01 00:00:00+00')
         TO   ('2026-08-01 00:00:00+00');
```

Parent primary key chứa partition key `occurred_at`; lý do nằm ở phần constraint.

---

## 8. Range bound là lower-inclusive, upper-exclusive

Với:

```sql
FOR VALUES FROM ('2026-07-01 00:00:00+00')
         TO   ('2026-08-01 00:00:00+00')
```

- đúng 2026-07-01 00:00 UTC thuộc partition tháng 7;
- đúng 2026-08-01 00:00 UTC không thuộc tháng 7;
- partition tháng 8 bắt đầu chính tại bound đó.

Dùng half-open interval `[start, end)` ở query, retention và validation. Với `timestamptz`,
ghi offset rõ trong DDL để session timezone không làm boundary khó audit.

---

## 9. Business date khác instant timestamp

“Tháng 7 theo UTC” khác “ngày kinh doanh theo Asia/Bangkok”. Nếu lifecycle theo business
date, cân nhắc lưu một column domain rõ:

```sql
business_date date NOT NULL
```

rồi partition trực tiếp theo `business_date`. Tránh mỗi query tự chuyển timezone khác nhau.

Generated column không được dùng làm partition key trong PostgreSQL 18. Nếu cần derived key,
tính ở application/ingestion và bảo vệ consistency bằng workflow/constraint phù hợp; đừng
giả định một generated column sẽ giải quyết routing.

---

## 10. LIST phù hợp tập category nhỏ và ổn định

```sql
CREATE TABLE app.regional_orders (
    region_code text NOT NULL,
    order_id bigint NOT NULL,
    created_at timestamptz NOT NULL,
    PRIMARY KEY (region_code, order_id)
) PARTITION BY LIST (region_code);

CREATE TABLE app.regional_orders_apac
PARTITION OF app.regional_orders
FOR VALUES IN ('TH', 'SG', 'VN');
```

LIST tốt khi group có ý nghĩa vận hành và ít thay đổi. Nếu mỗi customer trở thành một value
và customer count tăng liên tục, catalog/DDL overhead sẽ tăng theo business growth.

LIST cho phép một partition nhận `NULL`; range không nhận `NULL` qua bound thông thường.

---

## 11. HASH phân phối đều nhưng không mang time locality

```sql
CREATE TABLE app.tenant_sessions (
    tenant_id bigint NOT NULL,
    session_id uuid NOT NULL,
    started_at timestamptz NOT NULL,
    PRIMARY KEY (tenant_id, session_id)
) PARTITION BY HASH (tenant_id);

CREATE TABLE app.tenant_sessions_h0
PARTITION OF app.tenant_sessions
FOR VALUES WITH (MODULUS 4, REMAINDER 0);
```

Tạo remainder 0–3 để phủ modulus 4. HASH giúp giới hạn số bucket và cân phân phối tốt hơn
partition-per-tenant, nhưng retention theo thời gian vẫn phải delete bên trong mọi bucket.

Thay số bucket cần data movement. PostgreSQL cho phép modulus theo quan hệ factor để chia
từng bucket dần, nhưng runbook vẫn phải detach, redistribute, validate và attach.

---

## 12. Expression partition key làm constraint phức tạp hơn

PostgreSQL hỗ trợ column hoặc expression trong partition key, nhưng expression có chi phí:

- query predicate phải tương thích để planner chứng minh pruning;
- unique/primary key trên parent không được tạo nếu partition key chứa expression;
- attach validation/check constraint khó viết giống hệt;
- schema/tooling và timezone/collation khó audit hơn.

Ưu tiên column domain rõ nếu có thể. Expression key chỉ nên dùng khi workload test chứng
minh benefit và constraint contract vẫn thỏa.

---

## 13. Multi-column RANGE dùng row comparison

Bound của `PARTITION BY RANGE (region, occurred_at)` không tạo một hình chữ nhật độc lập
cho từng region/time. Nó so tuple theo thứ tự lexicographic.

```text
(region, occurred_at) >= lower tuple
AND
(region, occurred_at) < upper tuple
```

Do đó bound `FROM ('A', date1) TO ('C', date2)` còn chứa region `B` với gần như toàn miền
date. Nếu mục tiêu là region rồi time, LIST(region) ở tầng một và RANGE(time) ở tầng hai
thường dễ hiểu hơn, nhưng phải giữ số leaf trong budget.

---

## 14. Sub-partitioning chỉ khi tầng thứ hai có lợi độc lập

```sql
CREATE TABLE app.order_events_2026_08
PARTITION OF app.order_events
FOR VALUES FROM ('2026-08-01 00:00:00+00')
         TO   ('2026-09-01 00:00:00+00')
PARTITION BY HASH (tenant_id);

CREATE TABLE app.order_events_2026_08_h0
PARTITION OF app.order_events_2026_08
FOR VALUES WITH (MODULUS 4, REMAINDER 0);
```

PostgreSQL không tự kiểm tra sub-partition bound có hợp logic business ngoài constraint của
từng tầng. Tạo đủ remainder; thiếu một leaf làm insert tương ứng lỗi.

Time × hash nhanh chóng nhân số relation, index, vacuum target và DDL lock. Chỉ dùng khi hot
partition thật sự cần chia thêm và query vẫn prune được cả hai tầng.

---

## 15. DEFAULT partition là safety net, không phải thùng rác

```sql
CREATE TABLE app.order_events_default
PARTITION OF app.order_events DEFAULT;
```

Nó ngăn insert lỗi khi scheduler chưa tạo future partition, nhưng có trade-off:

- dữ liệu có thể âm thầm nằm sai lifecycle bucket;
- query vẫn có thể phải xét default partition;
- thêm partition mới có thể scan và lock default để chứng minh không overlap;
- `DETACH PARTITION ... CONCURRENTLY` không dùng được khi parent có default partition.

Nếu dùng, alert khi default có row và có job chuyển row về đúng partition.

---

## 16. Không có partition khớp thì INSERT lỗi nguyên statement

```sql
INSERT INTO app.order_events (
    tenant_id, external_id, event_type, occurred_at, payload
) VALUES (
    42, 'evt-9001', 'PAID', '2026-09-10 03:00:00+00', '{}'::jsonb
);
```

Nếu chưa có September/default leaf, PostgreSQL báo không tìm thấy partition. Database không
tự tạo partition theo ngày/tháng.

Production cần pre-create trước boundary, thường nhiều kỳ tương lai, và alert max bound.
Retry insert không giúp nếu metadata chưa được sửa.

---

## 17. UPDATE partition key có thể biến thành DELETE + INSERT

```sql
UPDATE app.order_events
SET occurred_at = :new_time
WHERE occurred_at = :old_time
  AND event_id = :event_id;
```

Nếu row rời bound cũ, PostgreSQL route sang leaf mới dưới dạng delete khỏi source và insert
vào destination. Hệ quả:

- destination phải tồn tại;
- row-level trigger có semantics delete/insert đáng chú ý;
- index/WAL/bloat work tăng;
- concurrent update/delete có thể nhận SQLSTATE `40001` và phải retry transaction.

Partition key nên tương đối immutable. Sửa timezone/data-quality hàng loạt cần batch runbook.

---

## 18. Inspect tree thay vì đoán từ tên table

```sql
SELECT
    relid::regclass AS relation,
    parentrelid::regclass AS parent,
    isleaf,
    level
FROM pg_partition_tree('app.order_events'::regclass)
ORDER BY level, relid::regclass::text;
```

Xem key:

```sql
SELECT pg_get_partkeydef('app.order_events'::regclass);
```

Tên suffix chỉ là convention; catalog mới là source of truth. Automation không nên parse
month/range từ tên nếu có thể đọc partition bound.

---

## 19. Đọc partition bounds từ catalog

```sql
SELECT
    child.oid::regclass AS partition,
    pg_get_expr(child.relpartbound, child.oid) AS partition_bound
FROM pg_inherits AS i
JOIN pg_class AS child ON child.oid = i.inhrelid
WHERE i.inhparent = 'app.order_events'::regclass
ORDER BY child.oid::regclass::text;
```

Dùng catalog để phát hiện gap, overlap không thể xảy ra trong cùng parent, default partition
và future coverage. Multi-level tree cần recursive/`pg_partition_tree`, không chỉ direct
children từ một `pg_inherits` query.

---

## 20. Partition pruning và index giải quyết hai tầng khác nhau

```text
partition pruning → chọn leaf nào có thể chứa row
index/scan choice  → tìm row thế nào bên trong leaf còn lại
```

Pruning dựa vào partition bounds, không cần index trên partition key. Sau khi prune còn một
monthly leaf, query lấy 5 event của tenant vẫn có thể cần index `(tenant_id, occurred_at)`.

Ngược lại, có index trên mọi leaf không bù được việc query mở hàng nghìn partition vì thiếu
predicate tương thích.

---

## 21. Predicate trực tiếp theo half-open range dễ prune nhất

```sql
SELECT event_id, event_type, occurred_at
FROM app.order_events
WHERE occurred_at >= TIMESTAMPTZ '2026-07-10 00:00:00+00'
  AND occurred_at <  TIMESTAMPTZ '2026-07-11 00:00:00+00'
  AND tenant_id = 42;
```

Predicate phản chiếu partition key/bound cho planner bằng chứng rõ. Dùng cùng semantics ở
application API: `fromInclusive`, `toExclusive` tránh lỗi cuối ngày và microsecond.

---

## 22. Bọc function quanh partition key có thể phá pruning

Query khó chứng minh hơn:

```sql
WHERE date(occurred_at AT TIME ZONE 'UTC') = DATE '2026-07-10'
```

Query rõ bound:

```sql
WHERE occurred_at >= TIMESTAMPTZ '2026-07-10 00:00:00+00'
  AND occurred_at <  TIMESTAMPTZ '2026-07-11 00:00:00+00'
```

Cast/function/operator class/collation phải tương thích với partition key. Đừng sửa bằng
planner toggle; đổi query contract hoặc key design và kiểm tra `EXPLAIN`.

---

## 23. Pruning có thể xảy ra lúc plan

Với constant đã biết, planner bỏ partition không thể match:

```sql
EXPLAIN (COSTS OFF)
SELECT count(*)
FROM app.order_events
WHERE occurred_at >= TIMESTAMPTZ '2026-07-01 00:00:00+00'
  AND occurred_at <  TIMESTAMPTZ '2026-08-01 00:00:00+00';
```

Plan tốt chỉ còn July leaf hoặc sub-leaves cần thiết. `enable_partition_pruning` mặc định on:

```sql
SHOW enable_partition_pruning;
```

Tắt setting chỉ phục vụ thí nghiệm so sánh, không phải production tuning.

---

## 24. Execution-time pruning hỗ trợ parameter

Prepared parameter, subquery value hoặc parameterized nested loop có thể chưa biết ở plan
time. Executor có thể prune:

- lúc khởi tạo plan;
- mỗi khi execution parameter thay đổi trong khi chạy.

Trong `EXPLAIN`, đọc:

- `Subplans Removed`: subplan bỏ lúc initialization;
- `(never executed)`: leaf bị prune mọi lần;
- `loops`: leaf chạy bao nhiêu lần với parameter khác nhau.

Partition bỏ ở initialization vẫn có thể đã bị lock đầu execution, nên hàng nghìn leaf vẫn
có metadata/lock cost dù execution scan rất ít.

---

## 25. Đếm partition được scan bằng plan, không bằng mong muốn

```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT count(*)
FROM app.order_events
WHERE occurred_at >= :from_time
  AND occurred_at < :to_time;
```

Kiểm tra:

- planning time và execution time;
- bao nhiêu leaf trong `Append`/`Merge Append`;
- `Subplans Removed`, `(never executed)`, loops;
- rows/buffers mỗi leaf;
- temp spill và parallel workers;
- setting khác default.

Không chạy `EXPLAIN ANALYZE` cho DML production nếu chưa hiểu nó thực thi thật.

---

## 26. Runtime pruning trong join phụ thuộc join shape

Khi inner side của nested loop được parameterize bằng key từ outer row, PostgreSQL có thể
prune leaf khác nhau theo từng loop. Nhưng không phải mọi join algorithm/predicate đều biến
thành runtime pruning.

Nếu join lớn chạm mọi partition:

1. xác nhận join có toàn partition key tương thích;
2. xem cardinality estimate và chosen join;
3. xem query có filter time/tenant ở cả hai side;
4. cân nhắc partitionwise join sau khi đo memory/planning.

Không duplicate predicate sai semantics chỉ để ép pruning.

---

## 27. Constraint exclusion khác declarative pruning

Partition pruning dùng internal bounds và có plan-time/execution-time. Constraint exclusion
dùng `CHECK` constraints, chủ yếu cho legacy inheritance và chỉ ở plan time.

```sql
SHOW constraint_exclusion;  -- mặc định/recommended: partition
```

Additional CHECK đôi khi giúp loại thêm child, nhưng quá nhiều constraint làm planning tốn
hơn. Với declarative partitioning, sửa bounds/query trước; không bật
`constraint_exclusion=on` toàn hệ thống theo thói quen cũ.

---

## 28. Quá nhiều partition làm planning và session memory tăng

PostgreSQL 18 cải thiện planning cho nhiều partition, cost estimate và partitionwise join,
nhưng không xóa cost vật lý:

- catalog metadata cho mỗi relation/index;
- lock acquisition;
- plan nodes còn lại sau pruning;
- local memory mỗi session đã touch partition;
- autovacuum/statistics/DDL object count;
- backup/restore và schema migration time.

Vài nghìn partition có thể hoạt động tốt nếu typical query prune còn rất ít; cùng số đó có
thể tệ nếu mỗi query giữ hàng trăm leaf. Benchmark đúng query mix.

---

## 29. Theo dõi planning time như first-class metric

`pg_stat_statements.track_planning` có overhead nhưng có thể bật có kiểm soát khi nghi ngờ:

```sql
SELECT
    queryid,
    plans,
    calls,
    total_plan_time,
    total_exec_time,
    left(query, 160) AS query
FROM pg_stat_statements
WHERE total_plan_time > 0
ORDER BY total_plan_time DESC
LIMIT 20;
```

Một query execution 5 ms nhưng planning 30 ms vẫn là regression. So trước/sau tăng số leaf,
prepared-plan behavior và number of relations retained after pruning.

---

## 30. Parent index là partitioned index, leaf index mới có storage

```sql
CREATE INDEX order_events_tenant_time_idx
ON app.order_events (tenant_id, occurred_at DESC);
```

Lệnh mặc định recurse: tạo/attach matching index trên leaf hiện tại. Partition tạo sau bằng
`PARTITION OF` cũng nhận matching index.

Parent index là metadata tree, không phải một global B-tree chứa entry của mọi leaf. Vì vậy
unique enforcement toàn cây cần partition structure bảo đảm conflict nằm cùng leaf.

---

## 31. Index từng leaf vẫn phải theo query shape

Sau pruning một leaf, nguyên tắc B-tree/GIN/BRIN vẫn giữ nguyên. Ví dụ lookup tenant theo
thời gian:

```sql
CREATE INDEX order_events_tenant_time_idx
ON app.order_events (tenant_id, occurred_at DESC)
INCLUDE (event_type);
```

Không cần lặp partition key ở mọi index nếu query không cần nó, nhưng parent unique/PK có
rule riêng. Có thể thêm specialized index chỉ ở hot leaf, song automation và plan stability
phải hiểu sự khác biệt giữa partitions.

---

## 32. Không tạo index CONCURRENTLY trực tiếp trên parent

`CREATE INDEX CONCURRENTLY` không hỗ trợ trực tiếp partitioned parent. Online pattern:

```sql
CREATE INDEX order_events_type_idx
ON ONLY app.order_events (event_type, occurred_at);

CREATE INDEX CONCURRENTLY order_events_2026_07_type_idx
ON app.order_events_2026_07 (event_type, occurred_at);

ALTER INDEX app.order_events_type_idx
ATTACH PARTITION app.order_events_2026_07_type_idx;
```

Lặp cho mọi leaf. Parent index ban đầu invalid và tự valid khi tất cả matching leaf indexes
đã attach. Theo dõi invalid index/build progress; mỗi child build dùng disk/WAL riêng.

---

## 33. Primary/unique key phải chứa toàn partition key

Hợp lệ vì có `occurred_at`:

```sql
ALTER TABLE app.order_events
ADD CONSTRAINT order_events_external_unique
UNIQUE (occurred_at, tenant_id, external_id);
```

Không thể khai báo `UNIQUE(event_id)` trên parent range-partitioned theo `occurred_at`.
Mỗi leaf index chỉ thấy row trong leaf; nếu unique key chứa partition key, hai row cùng toàn
key bắt buộc route vào cùng leaf.

Partition key dùng expression cũng chặn parent unique/primary constraint theo giới hạn hiện
tại.

---

## 34. Identity/sequence không thay global uniqueness constraint

Một sequence dùng chung thường cấp `event_id` khác nhau, nhưng database contract trên parent
vẫn chỉ là composite primary key `(occurred_at, event_id)`. Manual insert, `OVERRIDING`,
sequence reset hoặc data import có thể phá giả định “event_id luôn duy nhất”.

Nếu API phải lookup/foreign-key bằng một global ID duy nhất, lựa chọn gồm:

- đưa partition key vào identity/reference contract;
- giữ registry table không partitioned với `event_id` unique;
- chọn partition key có chứa natural global key phù hợp;
- không partition table đó.

Ghi rõ invariant nào được database enforce, không dựa vào xác suất sequence.

---

## 35. Exclusion constraint cũng phải localizable

Exclusion constraint trên partitioned table phải:

- chứa toàn bộ partition key của mọi tầng liên quan;
- so sánh các partition-key columns bằng equality;
- có thể dùng operator khác cho non-partition columns.

Mục tiêu là mọi cặp row có khả năng conflict phải nằm trong cùng leaf index. Nếu business
rule chống overlap xuyên nhiều time partition mà partition key không equality, declarative
leaf constraints không thể tự enforce toàn cục; cần đổi model/coordination.

---

## 36. Foreign key làm partition contract lan sang bảng khác

Referenced key phải là PK/unique hợp lệ, nên child thường phải lưu cả partition key:

```sql
CREATE TABLE app.event_deliveries (
    occurred_at timestamptz NOT NULL,
    event_id bigint NOT NULL,
    destination text NOT NULL,
    FOREIGN KEY (occurred_at, event_id)
        REFERENCES app.order_events (occurred_at, event_id)
);
```

Index referencing columns nếu delete/update parent cần kiểm tra nhanh. Retention detach/drop
partition có thể bị FK dependency/lock ảnh hưởng; rehearsal trên schema thật, không chỉ table
đơn lẻ.

---

## 37. ATTACH cho phép load ngoài cây rồi publish

```sql
CREATE TABLE app.order_events_2026_09_stage
(LIKE app.order_events INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE);

ALTER TABLE app.order_events_2026_09_stage
ADD CONSTRAINT order_events_2026_09_bound
CHECK (
    occurred_at >= TIMESTAMPTZ '2026-09-01 00:00:00+00'
    AND occurred_at < TIMESTAMPTZ '2026-10-01 00:00:00+00'
);
```

Load/validate/index/analyze stage, rồi:

```sql
ALTER TABLE app.order_events
ATTACH PARTITION app.order_events_2026_09_stage
FOR VALUES FROM ('2026-09-01 00:00:00+00')
         TO   ('2026-10-01 00:00:00+00');
```

Attach lấy `SHARE UPDATE EXCLUSIVE` trên parent, nhẹ hơn `CREATE TABLE ... PARTITION OF`
(`ACCESS EXCLUSIVE` trên parent), nhưng child/default vẫn có lock/validation work.

---

## 38. CHECK tương đương giúp ATTACH bỏ full scan

Nếu staging table không có valid CHECK chứng minh bound, PostgreSQL scan table trong lúc giữ
`ACCESS EXCLUSIVE` trên table được attach.

CHECK phải tương đương rõ với partition bound, gồm cả nullability khi cần. Sau attach có thể
drop CHECK dư vì internal bound đã bảo vệ:

```sql
ALTER TABLE app.order_events_2026_09_stage
DROP CONSTRAINT order_events_2026_09_bound;
```

Đừng drop trước attach. Với multi-level partition, thiếu proof có thể làm PostgreSQL lock và
scan recursively đến leaf.

---

## 39. DEFAULT partition có thể làm ATTACH scan hai phía

Khi thêm September, default partition phải chứng minh không chứa September row. Quy trình:

1. tìm và chuyển row September khỏi default;
2. thêm CHECK loại trừ September trên default;
3. thêm CHECK đúng bound trên staging;
4. attach partition;
5. cập nhật/drop constraint tạm theo lifecycle.

Exclusion CHECK dạng:

```sql
ALTER TABLE app.order_events_default
ADD CONSTRAINT order_events_default_exclude_2026_09
CHECK (
    occurred_at < TIMESTAMPTZ '2026-09-01 00:00:00+00'
    OR occurred_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00'
) NOT VALID;

ALTER TABLE app.order_events_default
VALIDATE CONSTRAINT order_events_default_exclude_2026_09;
```

`NOT VALID` làm bước add nhanh hơn; `VALIDATE` scan với lock nhẹ hơn, sau đó ATTACH có proof.
Không có valid proof, PostgreSQL scan default dưới `ACCESS EXCLUSIVE` để tìm overlap.

---

## 40. DETACH giữ table để archive/validate trước drop

```sql
ALTER TABLE app.order_events
DETACH PARTITION app.order_events_2026_07;
```

Non-concurrent form cần `ACCESS EXCLUSIVE` trên parent. Sau detach, table độc lập; index gắn
với parent indexes cũng được detach khỏi metadata tree.

Đây là lifecycle boundary tốt:

- export/backup riêng;
- checksum/count/reconcile;
- aggregate cold data;
- move tablespace;
- drop sau grace period.

Detach không tự xóa dữ liệu hay bảo đảm bản archive dùng được.

---

## 41. DETACH CONCURRENTLY có giới hạn quan trọng

```sql
ALTER TABLE app.order_events
DETACH PARTITION app.order_events_2026_07 CONCURRENTLY;
```

Nó dùng hai transaction nội bộ, giảm parent lock xuống `SHARE UPDATE EXCLUSIVE`, nhưng:

- không chạy trong transaction block/procedure chứa transaction;
- không được phép nếu parent có default partition;
- vẫn chờ transaction cũ và cần lock mạnh trên leaf ở phase cuối;
- tại một thời điểm chỉ một child của parent có thể pending detach.

Nếu bị cancel/crash giữa chừng:

```sql
ALTER TABLE app.order_events
DETACH PARTITION app.order_events_2026_07 FINALIZE;
```

Chạy latest PostgreSQL 18 minor và rehearsal dependency/FK behavior.

---

## 42. Retention bằng DROP/DETACH tránh delete debt

Row-by-row delete tạo dead tuple, WAL, index cleanup và vacuum work. Nếu retention trùng
partition boundary:

```text
close partition → detach → archive/verify → drop after grace period
```

```sql
DROP TABLE app.order_events_2026_07;
```

Drop sau detach không khóa parent như drop partition trực tiếp, nhưng dependency và disk
release vẫn cần runbook. Đừng drop chỉ vì tên table “trông cũ”; đọc catalog bound và clock
source, bảo vệ legal hold.

---

## 43. Pre-create partition là production job bắt buộc

Automation nên:

- tạo trước N kỳ theo ingest clock/timezone;
- dùng advisory lock để tránh hai scheduler cùng DDL;
- kiểm tra bound/catalog idempotently;
- tạo/attach đầy đủ indexes, privileges, storage options;
- ANALYZE sau initial load;
- alert khi future coverage dưới threshold;
- không tự drop nếu archive/legal-hold chưa xác nhận.

Không dùng dynamic DDL trong insert trigger: concurrent insert tại boundary sẽ tranh DDL
lock và error handling rất khó.

---

## 44. ANALYZE leaf và parent có vai trò khác nhau

Autovacuum xử lý/analyze leaf vì leaf chứa tuple. Partitioned parent không chứa tuple nên
autovacuum không tự ANALYZE parent; query toàn hierarchy có thể cần parent/inherited stats.

Sau initial load hoặc distribution shift:

```sql
ANALYZE app.order_events_2026_09_stage;
ANALYZE app.order_events;
```

Theo dõi `pg_stat_user_tables` từng leaf. Parent statistics không thay statistics riêng của
leaf; skew giữa hot/cold partition vẫn ảnh hưởng plan.

---

## 45. Vacuum vẫn là per-leaf maintenance

Mỗi leaf có churn, dead tuple, freeze age và autovacuum threshold riêng. Monthly partition
đã đóng/immutable có thể nhanh đạt all-visible/all-frozen; current partition cần tune tích
cực hơn.

```sql
ALTER TABLE app.order_events_2026_08 SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_analyze_scale_factor = 0.005
);
```

Lifecycle automation nên apply policy đúng cho leaf mới. Không tắt autovacuum trên closed
partition nếu chưa bảo đảm freeze/wraparound và future corrections.

---

## 46. Partitionwise join mặc định tắt và có memory cost

```sql
SHOW enable_partitionwise_join;
```

Nó có thể join matching partitions riêng khi join chứa toàn partition keys, data types và
partition layout tương thích. PostgreSQL 18 hỗ trợ nhiều trường hợp hơn và giảm memory so
với trước, nhưng setting vẫn mặc định off.

Bật có thể tạo số plan node dùng `work_mem` tăng theo partition được scan, tăng planning CPU
và execution memory. Test per workload/session trước, không bật global chỉ vì hai table đều
partitioned.

---

## 47. Partitionwise aggregate cũng đánh đổi node và memory

```sql
SHOW enable_partitionwise_aggregate;
```

Nếu `GROUP BY` chứa partition key, aggregate có thể hoàn tất riêng per partition. Nếu không,
PostgreSQL chỉ partial aggregate ở leaf rồi finalize phía trên.

Lợi ích phụ thuộc số row giảm sớm so với số aggregate node/hash table. `work_mem` là per node,
nên plan nhiều partition có thể dùng nhiều memory. So `EXPLAIN (ANALYZE, BUFFERS)` cùng peak
concurrency.

---

## 48. Bulk load tốt nhất vào staging rồi attach

Runbook:

1. tạo staging table schema-compatible;
2. thêm exact bound CHECK;
3. `COPY`/load ngoài parent;
4. validate type, null, duplicate, count/checksum;
5. tạo matching indexes;
6. `ANALYZE` staging;
7. rehearsal lock timeout;
8. attach;
9. kiểm tra routing/query/replica/WAL.

Load thẳng parent đơn giản hơn và có automatic routing, nhưng không tạo atomic publish
boundary cho cả batch. Chọn theo failure semantics, không chỉ tốc độ.

---

## 49. Large DELETE nên hỏi có thể detach không

Nếu predicate đúng trọn partition, detach/drop thường rẻ hơn:

```sql
DELETE FROM app.order_events
WHERE occurred_at < TIMESTAMPTZ '2025-01-01 00:00:00+00';
```

Row DELETE vẫn cần nếu row cần xóa rải trong partition hoặc FK/business workflow yêu cầu.
Khi đó batch theo deterministic key, transaction ngắn, đo WAL/replica lag/dead tuple và để
autovacuum theo kịp.

Đừng đổi retention semantics để vừa partition boundary; legal/audit policy là contract.

---

## 50. Large UPDATE partition key là data migration

Sửa hàng triệu `occurred_at` không phải update nhẹ: row move giữa leaf tạo delete/insert,
trigger/index/WAL/vacuum work và concurrency retry.

An toàn hơn có thể là:

1. xác định source/destination range;
2. bảo đảm destination partitions;
3. batch theo primary key, lock order ổn định;
4. reconcile mỗi batch;
5. monitor `40001`, WAL, lag, dead tuple;
6. VACUUM/ANALYZE theo evidence.

Nếu sửa toàn partition, staging-transform-attach có thể rõ failure boundary hơn.

---

## 51. Regular table không ALTER trực tiếp thành partitioned table

PostgreSQL không đổi in-place ordinary table thành partitioned parent. Shadow migration phổ
biến:

```text
create new partitioned hierarchy
        ↓
backfill theo ranges + capture concurrent writes
        ↓
validate counts/checksums/invariants
        ↓
brief cutover application/dependencies
        ↓
observe, then retire old table
```

Capture có thể bằng application dual-write, change stream hoặc trigger, nhưng phải giải
quyết ordering, retry, delete và idempotency. “Copy xong rồi rename” làm mất write phát sinh
trong lúc copy.

---

## 52. Rename swap không tự chuyển dependency theo tên

View, FK, trigger/function dependency thường bám OID, không tra lại tên sau rename. Nếu:

```text
orders → orders_old
orders_new → orders
```

dependency cũ có thể vẫn trỏ `orders_old`. Cutover checklist phải inventory:

- foreign keys cả hai chiều;
- views/materialized views/functions;
- grants, owner, RLS, triggers;
- sequences/identity;
- publications/subscriptions;
- prepared statements và application metadata cache.

Rehearsal trên schema clone và kiểm tra catalog dependency, không chỉ chạy SELECT thủ công.

---

## 53. Attach old table làm DEFAULT có use case hẹp

Có thể tạo parent mới rồi attach old table làm DEFAULT để dần tách ranges, nhưng:

- schema phải match;
- dependency vẫn bám OID old table, không tự chuyển lên parent;
- mỗi partition mới có thể scan/lock default;
- phải move row khỏi default và duy trì exclusion CHECK;
- concurrent write/cutover vẫn cần thiết kế.

Pattern này không phải zero-downtime shortcut mặc định. Chỉ dùng sau proof-of-concept với
lock, FK, trigger, replication và rollback thật.

---

## 54. Schema change trên hierarchy nhân work và lock

`ALTER TABLE` parent thường recurse qua partitions. Với hàng nghìn leaf, catalog update,
lock acquisition, validation và rewrite có thể rất lớn.

Trước DDL:

- đếm leaf/index/constraint;
- kiểm tra long transaction và lock queue;
- đặt `lock_timeout` ngắn cho acquisition attempt;
- xác định metadata-only hay rewrite/scan;
- thử trên hierarchy cùng scale;
- có expand–migrate–contract và resume plan;
- theo dõi WAL/replica/backup impact.

PostgreSQL 18 cải thiện lock performance nhiều relation nhưng không biến recursive DDL thành
miễn phí.

---

## 55. Tablespace cho cold partition là placement, không phải backup

Sau detach hoặc trong maintenance window:

```sql
ALTER TABLE app.order_events_2025_01
SET TABLESPACE cold_tablespace;
```

Table move không tự bảo đảm mọi index đã chuyển; inventory relation/index tablespaces. Move
dùng I/O, lock, WAL/replication behavior tùy operation và cần đủ disk hai phía.

Tablespace chỉ đặt file trên storage path; không cung cấp durability, archive hay restore.
Backup phải chứa/khôi phục đúng tablespace mapping.

---

## 56. Partition lifecycle ảnh hưởng WAL, replica và backup

- bulk load/index build tạo WAL và replica lag;
- attach chủ yếu metadata nhưng existing rows có replication/publication semantics cần test;
- detach/drop làm catalog/storage change, không thay archive verification;
- nhiều relation làm backup/restore catalog/index creation lâu hơn;
- cold partition vẫn nằm trong backup scope nếu chưa có policy khác.

Đặc biệt với logical replication và `publish_via_partition_root`, attach table đã có dữ liệu
không có nghĩa existing contents tự được copy sang subscriber. Phần replication phải có
runbook riêng ở chương tiếp theo.

---

## 57. Monitor size và row estimate từng leaf

```sql
SELECT
    tree.relid::regclass AS relation,
    tree.level,
    tree.isleaf,
    pg_size_pretty(pg_total_relation_size(tree.relid)) AS total_size,
    c.reltuples::bigint AS estimated_rows
FROM pg_partition_tree('app.order_events'::regclass) AS tree
JOIN pg_class AS c ON c.oid = tree.relid
ORDER BY pg_total_relation_size(tree.relid) DESC;
```

Parent size gần như metadata; tổng hierarchy phải cộng leaf. Alert:

- partition bất thường quá lớn/nhỏ;
- default row > 0;
- future coverage thiếu;
- leaf thiếu expected index;
- planning time tăng theo partition count;
- old partition chưa detach theo policy;
- per-leaf vacuum/freeze age.

---

## 58. Failure modes thường gặp

### 58.1 Partition theo column không có trong WHERE

Không prune, vẫn scan nhiều leaf và planning tốn hơn.

### 58.2 Một partition cho mỗi tenant

Tenant growth biến business cardinality thành catalog explosion.

### 58.3 Bound dùng `BETWEEN`/end-of-day thủ công

Tạo gap/overlap logic ứng dụng; dùng `[start, end)`.

### 58.4 Dùng DEFAULT rồi không monitor

Default thành data lake sai bucket và attach tương lai bị scan/lock.

### 58.5 Tin rằng parent index là global index

Mất global uniqueness nếu constraint không chứa partition key.

### 58.6 Tạo parent index CONCURRENTLY

Không được hỗ trợ; cần child-concurrently + attach pattern.

### 58.7 Attach staging không có CHECK

Production gặp full scan dưới strong lock trên staging/default.

### 58.8 Detach concurrently trong transaction

Lệnh lỗi vì cần hai transaction nội bộ; default partition cũng chặn mode này.

### 58.9 Chỉ ANALYZE leaf, bỏ parent

Query hierarchy có thể dùng inherited stats cũ/thiếu.

### 58.10 Rename swap và nghĩ FK/view tự đổi target

Dependency theo OID vẫn bám old table.

---

## 59. Decision matrix

| Nhu cầu | Candidate | Rủi ro chính |
|---|---|---|
| Retention theo tháng | RANGE(time) | timezone/boundary/future partition |
| Ít region ổn định | LIST(region) | value mới và skew |
| Tenant rất nhiều | HASH(tenant) | rebalance và không giúp time retention |
| Time + hot bucket quá lớn | RANGE → HASH | số leaf nhân nhanh |
| Global unique ID | table thường/registry/composite key | leaf index không global |
| Bulk publish theo kỳ | staging + CHECK + ATTACH | validation/index/lock |
| Xóa trọn kỳ | DETACH → archive → DROP | FK/legal hold/backup |
| Query không có partition predicate | index/table thường | không pruning |
| Online thêm parent index | ONLY + child concurrent + attach | nhiều bước/resume |

---

## 60. Runbook partition rollover

### Trước boundary

1. Xác định UTC/business-calendar bounds.
2. Advisory lock cho một automation owner.
3. Kiểm tra catalog chưa có bound tương đương.
4. Tạo staging/partition cùng schema, options và indexes.
5. Rehearsal lock timeout và default exclusion.
6. Tạo trước hơn một kỳ để có headroom.

### Sau boundary

1. Xác nhận insert route vào new leaf.
2. Default partition không có row mới.
3. Query typical prune đúng.
4. Statistics/autovacuum policy đã áp dụng.
5. WAL/lag/error không tăng bất thường.

### Retire old leaf

1. Legal hold/retention cutoff được duyệt.
2. Detach với mode phù hợp dependency/default.
3. Export/checksum/restore verification.
4. Grace period.
5. Drop và xác nhận disk/backup catalog.

---

## 61. Checklist production

### Design

- [ ] Partition key xuất hiện trong typical WHERE?
- [ ] Retention/archive trùng boundary?
- [ ] Granularity được benchmark với future partition count?
- [ ] Unique/PK/FK/exclusion contract chứa partition key khi cần?
- [ ] Timezone và `[start, end)` được ghi thành API contract?
- [ ] Default partition có owner, alert và drain job?

### Query và planner

- [ ] EXPLAIN xác nhận số leaf còn lại sau pruning?
- [ ] Prepared query được kiểm tra execution-time pruning?
- [ ] Planning time được đo, không chỉ execution time?
- [ ] Index bên trong leaf khớp query shape?
- [ ] Partitionwise join/aggregate được benchmark memory/concurrency?

### Lifecycle

- [ ] Future partitions được pre-create idempotently?
- [ ] ATTACH staging/default có exact CHECK để tránh scan?
- [ ] DETACH concurrent restrictions và FINALIZE có trong runbook?
- [ ] Archive được restore/checksum trước drop?
- [ ] Legal hold có thể chặn automation drop?

### Maintenance và migration

- [ ] Parent và leaf statistics có workflow?
- [ ] Autovacuum/freeze theo dõi từng leaf?
- [ ] Online parent index build có child attach/resume plan?
- [ ] Recursive DDL được rehearsal đúng số relation?
- [ ] Shadow migration capture concurrent insert/update/delete?
- [ ] FK/view/grant/RLS/trigger/publication dependencies được inventory?
- [ ] WAL, replica lag, backup/restore và disk được capacity-test?

---

## 62. Câu hỏi phỏng vấn

1. Vì sao partitioning có thể làm query chậm hơn?
2. Parent và leaf partition lưu dữ liệu khác nhau thế nào?
3. Khi nào RANGE/LIST/HASH phù hợp?
4. Lower/upper bound của RANGE inclusive/exclusive ra sao?
5. Vì sao partition-per-tenant thường nguy hiểm?
6. Multi-column RANGE dùng semantics gì?
7. Default partition giúp và gây rủi ro gì?
8. UPDATE partition key được thực thi thế nào?
9. Partition pruning khác index scan thế nào?
10. Plan-time và execution-time pruning khác nhau gì?
11. `Subplans Removed` và `(never executed)` nói gì?
12. Vì sao function quanh partition key có thể cản pruning?
13. Too many partitions ảnh hưởng planning/session memory thế nào?
14. Parent partitioned index có chứa index entry không?
15. Cách build index online cho toàn partition tree?
16. Vì sao unique/PK phải chứa toàn partition key?
17. Sequence có thay global unique constraint không?
18. Exclusion constraint trên partitioned table có giới hạn gì?
19. CHECK giúp ATTACH tránh scan thế nào?
20. Default partition ảnh hưởng ATTACH ra sao?
21. DETACH CONCURRENTLY có lock và restriction nào?
22. Vì sao detach/drop tốt hơn mass delete cho retention?
23. Parent partitioned table cần manual ANALYZE vì sao?
24. Partitionwise join/aggregate có memory risk gì?
25. Vì sao ordinary table không thể ALTER trực tiếp thành partitioned parent?
26. Rename swap có vấn đề dependency OID gì?

---

## 63. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [Table partitioning](https://www.postgresql.org/docs/18/ddl-partitioning.html)
- [`CREATE TABLE`](https://www.postgresql.org/docs/18/sql-createtable.html)
- [`ALTER TABLE`](https://www.postgresql.org/docs/18/sql-altertable.html)
- [`CREATE INDEX`](https://www.postgresql.org/docs/18/sql-createindex.html)
- [`ALTER INDEX`](https://www.postgresql.org/docs/18/sql-alterindex.html)
- [Planner method settings](https://www.postgresql.org/docs/18/runtime-config-query.html)
- [System information functions](https://www.postgresql.org/docs/18/functions-info.html)
- [`UPDATE` và row movement](https://www.postgresql.org/docs/18/sql-update.html)
- [Trigger behavior](https://www.postgresql.org/docs/18/trigger-definition.html)
- [Routine vacuuming](https://www.postgresql.org/docs/18/routine-vacuuming.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

Học tiếp:

1. [Replication & High Availability](../operations/replication_ha.md).
2. [Backup, PITR & Upgrade](../operations/backup_pitr_upgrade.md).
3. [Security & Row-Level Security](../operations/security_rls.md).

---

*Cập nhật lần cuối: 2026-07-31.*
