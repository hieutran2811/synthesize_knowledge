---
title: "PostgreSQL Advanced SQL"
topic: postgresql
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "PostgreSQL 18"
source_count: 13
---
# PostgreSQL Advanced SQL

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này tập trung vào tư duy set-based:
> diễn đạt “một tập biến thành một tập” bằng join, aggregate, window, CTE,
> recursion và DML thay vì vòng lặp/N+1 ở application.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Data Modeling & Types](data_modeling_types.md) ·
[Transactions, MVCC & Locking](transactions_mvcc.md) ·
[Indexing & Query Planner](indexing_planner.md).

---

## 1. Set-based không có nghĩa “nhét mọi thứ vào một query”

Set-based SQL mô tả kết quả cần có:

```text
input relations
    ↓ join/filter/transform
intermediate sets
    ↓ group/window/set operation
result relation hoặc changed rows
```

Lợi ích:

- planner có thể đổi join order/access path;
- giảm round trip và N+1;
- constraint/transaction bảo vệ cùng một snapshot;
- batch work dễ đo bằng `EXPLAIN`.

Nhưng một query khổng lồ, lặp logic hoặc tạo Cartesian product vẫn tệ. Tách bằng
CTE/view khi làm rõ semantics, rồi kiểm tra materialization và plan.

---

## 2. Logical processing order giải thích nhiều lỗi SQL

Mental model đơn giản:

```text
WITH
FROM / JOIN
WHERE
GROUP BY / aggregate
HAVING
window functions
SELECT
DISTINCT
set operations
ORDER BY
LIMIT / OFFSET
locking clause
```

Planner có thể thực thi vật lý khác thứ tự nhưng phải giữ semantics.

Hệ quả:

- alias ở `SELECT` thường chưa dùng được trong `WHERE` cùng level;
- `WHERE` lọc row trước group, `HAVING` lọc group sau aggregate;
- window không dùng trực tiếp trong `WHERE`; cần subquery/CTE;
- `ORDER BY` cuối cùng mới bảo đảm output order.

---

## 3. Join condition và filter của outer join không hoán đổi tự do

Giữ mọi customer, chỉ ghép order PAID:

```sql
SELECT
    c.customer_id,
    o.order_id
FROM app.customers AS c
LEFT JOIN app.orders AS o
    ON o.customer_id = c.customer_id
   AND o.status = 'PAID';
```

Nếu chuyển predicate sang `WHERE`:

```sql
SELECT
    c.customer_id,
    o.order_id
FROM app.customers AS c
LEFT JOIN app.orders AS o
    ON o.customer_id = c.customer_id
WHERE o.status = 'PAID';
```

unmatched row có `o.status = NULL`, bị `WHERE` loại; kết quả giống inner join cho
điều kiện đó.

Tránh `NATURAL JOIN`: schema thêm column trùng tên có thể âm thầm đổi join
condition. Dùng `ON` hoặc `USING` explicit.

---

## 4. Semi join bằng `EXISTS`

Tìm customer có ít nhất một order PAID:

```sql
SELECT c.customer_id, c.email
FROM app.customers AS c
WHERE EXISTS (
    SELECT 1
    FROM app.orders AS o
    WHERE o.customer_id = c.customer_id
      AND o.status = 'PAID'
);
```

`EXISTS` quan tâm có row hay không, không nhân customer theo số order. Planner có
thể dừng khi tìm được match và chuyển thành semi join.

Anti join:

```sql
SELECT c.customer_id, c.email
FROM app.customers AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM app.orders AS o
    WHERE o.customer_id = c.customer_id
);
```

---

## 5. Bẫy `NOT IN` với `NULL`

```sql
SELECT c.customer_id
FROM app.customers AS c
WHERE c.customer_id NOT IN (
    SELECT o.customer_id
    FROM app.orders AS o
);
```

Nếu subquery có một `NULL`, phép so sánh không match có thể thành `UNKNOWN`, làm
query không trả kết quả mong đợi. Dù schema hiện tại `customer_id NOT NULL`, query
sau refactor/view có thể khác.

Cho anti join nullable-safe, ưu tiên `NOT EXISTS` với correlation rõ. Không sửa mù
bằng `WHERE customer_id IS NOT NULL` nếu null mang semantics cần xử lý.

---

## 6. Conditional aggregation với `FILTER`

Một scan, nhiều metric:

```sql
SELECT
    customer_id,
    count(*) AS total_orders,
    count(*) FILTER (WHERE status = 'PAID') AS paid_orders,
    count(*) FILTER (WHERE status = 'CANCELLED') AS cancelled_orders,
    sum(total) FILTER (WHERE status = 'PAID') AS paid_amount
FROM app.orders
GROUP BY customer_id;
```

Rõ hơn nhiều biểu thức `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`, nhất là với
aggregate phức tạp. `FILTER` chỉ đưa row thỏa điều kiện vào aggregate đó; `WHERE`
của query vẫn lọc input chung.

---

## 7. Aggregate và `NULL`

Quy tắc quan trọng:

- `count(*)` đếm row;
- `count(column)` bỏ qua null;
- phần lớn aggregate bỏ qua null input;
- `sum`/`array_agg` trên tập rỗng trả `NULL`, không tự trả 0/array rỗng;
- order của `array_agg`, `jsonb_agg`, `string_agg` không bảo đảm nếu không chỉ định.

```sql
SELECT
    customer_id,
    coalesce(sum(total), 0) AS total_amount,
    array_agg(order_id ORDER BY created_at, order_id) AS ordered_ids
FROM app.orders
GROUP BY customer_id;
```

Đặt `coalesce` theo domain, không giả định null luôn đồng nghĩa 0.

---

## 8. Window giữ nguyên identity của từng row

Aggregate thường gom nhiều row thành một row/group. Window tính qua tập liên quan
nhưng vẫn giữ từng row:

```sql
SELECT
    order_id,
    customer_id,
    total,
    avg(total) OVER (PARTITION BY customer_id) AS customer_avg
FROM app.orders;
```

Ba khái niệm:

```text
PARTITION BY → chia nhóm logic
ORDER BY     → thứ tự trong partition
frame        → subset quanh current row cho function dùng frame
```

Window chỉ xuất hiện ở `SELECT`/`ORDER BY` cùng query level vì chạy sau
`WHERE/GROUP BY/HAVING`.

---

## 9. Ranking và peer rows

```sql
SELECT
    order_id,
    customer_id,
    total,
    row_number() OVER w AS row_no,
    rank() OVER w AS rank_with_gap,
    dense_rank() OVER w AS rank_without_gap
FROM app.orders
WINDOW w AS (
    PARTITION BY customer_id
    ORDER BY total DESC
);
```

- `row_number`: luôn tăng từng row; tie cần tie-breaker để deterministic;
- `rank`: peers cùng rank, rank sau có gap;
- `dense_rank`: peers cùng rank, không gap.

Nếu business cần đúng một thứ tự, thêm key unique:

```sql
ORDER BY total DESC, order_id
```

---

## 10. Top N mỗi group bằng window

```sql
WITH ranked AS (
    SELECT
        o.*,
        row_number() OVER (
            PARTITION BY customer_id
            ORDER BY created_at DESC, order_id DESC
        ) AS rn
    FROM app.orders AS o
)
SELECT *
FROM ranked
WHERE rn <= 3;
```

Không thể đặt `row_number() ... <= 3` trực tiếp trong `WHERE` cùng level. Cần
subquery/CTE vì logical order.

Pattern window thường sort toàn candidate set. Với ít parent và index phù hợp,
`LATERAL ... LIMIT N` có thể ít work hơn; phải đo.

---

## 11. `DISTINCT ON` cho một row đầu mỗi group

PostgreSQL extension gọn cho top 1:

```sql
SELECT DISTINCT ON (customer_id)
    customer_id,
    order_id,
    created_at,
    total
FROM app.orders
ORDER BY customer_id, created_at DESC, order_id DESC;
```

Quy tắc:

- expression `DISTINCT ON` phải khớp phần trái của `ORDER BY`;
- các expression sau chọn row thắng trong group;
- không có `ORDER BY` đầy đủ thì “first” không dự đoán được;
- index `(customer_id, created_at DESC, order_id DESC)` có thể hỗ trợ.

Dùng window khi cần top N, rank/tie semantics hoặc thêm nhiều analytic columns.

---

## 12. Running total phải khai báo frame có chủ đích

```sql
SELECT
    order_id,
    customer_id,
    created_at,
    total,
    sum(total) OVER (
        PARTITION BY customer_id
        ORDER BY created_at, order_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM app.orders;
```

Khi có window `ORDER BY`, default frame kết thúc ở current row **và peers**. Với
tie, `RANGE`-like default có thể làm nhiều row cùng nhảy tổng.

`ROWS` đếm physical ordered rows; `RANGE` dựa trên value range/peers; `GROUPS`
đếm peer groups. Chọn theo nghĩa nghiệp vụ, không dựa default.

---

## 13. Bẫy `last_value`

```sql
last_value(total) OVER (
    PARTITION BY customer_id
    ORDER BY created_at, order_id
)
```

thường trả value ở cuối **frame hiện tại**, không phải cuối partition.

Muốn cuối partition:

```sql
last_value(total) OVER (
    PARTITION BY customer_id
    ORDER BY created_at, order_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
)
```

`first_value`, `last_value`, `nth_value` phụ thuộc frame; `lag/lead` dùng vị trí
trong partition theo order, không bị frame giới hạn theo cùng cách.

---

## 14. `lag`/`lead` cho thay đổi theo thời gian

```sql
WITH ordered AS (
    SELECT
        order_id,
        customer_id,
        created_at,
        total,
        lag(total) OVER (
            PARTITION BY customer_id
            ORDER BY created_at, order_id
        ) AS previous_total
    FROM app.orders
)
SELECT
    *,
    total - previous_total AS delta
FROM ordered;
```

Thêm deterministic tie-breaker. `lag` đầu partition trả default `NULL` nếu không
truyền default; đừng coalesce nếu null mang nghĩa “không có row trước”.

---

## 15. Named window giảm lặp nhưng frame có thể khác

```sql
SELECT
    order_id,
    sum(total) OVER w AS running_total,
    avg(total) OVER w AS running_avg
FROM app.orders
WINDOW w AS (
    PARTITION BY customer_id
    ORDER BY created_at, order_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
);
```

Named window giúp các function dùng chính xác cùng partition/order/frame. Nếu một
metric cần toàn partition và metric khác cần running frame, định nghĩa hai window
rõ thay vì giả định function tự chọn.

---

## 16. Gaps and islands bằng window

Nhóm các ngày liên tiếp có order:

```sql
WITH days AS (
    SELECT DISTINCT customer_id, business_date
    FROM app.orders
), numbered AS (
    SELECT
        customer_id,
        business_date,
        business_date
            - (row_number() OVER (
                PARTITION BY customer_id
                ORDER BY business_date
              ))::integer AS island_key
    FROM days
)
SELECT
    customer_id,
    min(business_date) AS start_date,
    max(business_date) AS end_date,
    count(*) AS day_count
FROM numbered
GROUP BY customer_id, island_key;
```

Trừ row number khỏi ngày làm các ngày liên tiếp có cùng key. Production query cần
định nghĩa rõ timezone/business date và điều gì tạo “gap”.

---

## 17. `LATERAL` là correlated relation trong `FROM`

Subquery `LATERAL` có thể tham chiếu row ở bên trái:

```sql
SELECT
    c.customer_id,
    latest.order_id,
    latest.created_at
FROM app.customers AS c
LEFT JOIN LATERAL (
    SELECT o.order_id, o.created_at
    FROM app.orders AS o
    WHERE o.customer_id = c.customer_id
    ORDER BY o.created_at DESC, o.order_id DESC
    LIMIT 1
) AS latest ON true;
```

`LEFT JOIN LATERAL ... ON true` giữ customer không có order. Với index
`(customer_id, created_at DESC, order_id DESC)`, mỗi lookup có thể dừng sớm.

Nhưng LATERAL được đánh giá theo row/set bên trái; outer quá lớn có thể thành nhiều
inner probes. Xem `loops` trong `EXPLAIN ANALYZE`.

---

## 18. Top N mỗi parent: window hay LATERAL?

| Pattern | Thường phù hợp |
|---|---|
| window + `row_number` | xử lý phần lớn/all parent và child |
| `LATERAL` + index + `LIMIT N` | số parent nhỏ, N nhỏ, lookup selective |

LATERAL top 3:

```sql
SELECT c.customer_id, recent.*
FROM app.customers AS c
CROSS JOIN LATERAL (
    SELECT o.order_id, o.created_at, o.total
    FROM app.orders AS o
    WHERE o.customer_id = c.customer_id
    ORDER BY o.created_at DESC, o.order_id DESC
    LIMIT 3
) AS recent;
```

Không chọn theo độ ngắn SQL. So buffer/work/latency trên cardinality thật.

---

## 19. Set-returning function trong `FROM`

Sinh calendar:

```sql
SELECT day::date
FROM generate_series(
    DATE '2026-07-01',
    DATE '2026-07-31',
    interval '1 day'
) AS g(day);
```

Giữ vị trí array:

```sql
SELECT tag, position
FROM unnest(ARRAY['postgresql', 'java', 'kafka'])
    WITH ORDINALITY AS u(tag, position);
```

Đặt SRF ở `FROM` giúp row shape rõ hơn đặt trong select list. `WITH ORDINALITY`
đánh số từ 1; array subscript gốc có thể có lower bound khác, nên không luôn thay
subscript metadata.

---

## 20. CTE làm rõ pipeline

```sql
WITH paid_orders AS (
    SELECT customer_id, total
    FROM app.orders
    WHERE status = 'PAID'
), totals AS (
    SELECT customer_id, sum(total) AS lifetime_value
    FROM paid_orders
    GROUP BY customer_id
)
SELECT c.customer_id, c.email, t.lifetime_value
FROM totals AS t
JOIN app.customers AS c USING (customer_id)
WHERE t.lifetime_value >= 1000;
```

CTE tạo tên cho intermediate relation, không phải temp table có index. Độ dễ đọc
không bảo đảm nhanh/chậm; planner có thể fold hoặc materialize tùy điều kiện.

---

## 21. `MATERIALIZED` và `NOT MATERIALIZED`

Non-recursive, side-effect-free CTE thường được fold nếu reference một lần. Nhiều
reference mặc định thường materialize.

Ép pushdown/joint optimization:

```sql
WITH paid AS NOT MATERIALIZED (
    SELECT *
    FROM app.orders
    WHERE status = 'PAID'
)
SELECT *
FROM paid
WHERE customer_id = :customer_id;
```

Ép tính một lần:

```sql
WITH calculated AS MATERIALIZED (
    SELECT order_id, length(metadata::text) AS metadata_size
    FROM app.orders
)
SELECT *
FROM calculated
WHERE metadata_size > 100;
```

`NOT MATERIALIZED` có thể lặp computation; `MATERIALIZED` có thể chặn predicate
pushdown/index usage. Quyết định bằng plan, không theo phiên bản cũ trước PostgreSQL
12 nơi CTE luôn là optimization fence.

---

## 22. Data-modifying CTE để chuyển row

```sql
WITH moved AS (
    DELETE FROM app.orders
    WHERE status = 'CANCELLED'
      AND created_at < :cutoff
    RETURNING *
)
INSERT INTO app.orders_archive
SELECT *
FROM moved;
```

Các DML CTE chạy tới completion, cùng snapshot; thứ tự thực thi giữa sibling DML
không dự đoán được. Chúng không thấy thay đổi của nhau qua table scan; `RETURNING`
là kênh truyền dữ liệu rõ.

Không để hai sibling statement sửa cùng row: kết quả statement nào thắng không dự
đoán được. Parent command nên dùng output `RETURNING`, không đọc lại target và giả
định đã thấy write sibling.

---

## 23. Recursive CTE: anchor + recursive term

```sql
WITH RECURSIVE numbers(n) AS (
    VALUES (1)
    UNION ALL
    SELECT n + 1
    FROM numbers
    WHERE n < 10
)
SELECT *
FROM numbers;
```

Evaluation lặp qua working table, dù syntax tự tham chiếu có tính recursive.

Ưu tiên `UNION ALL`; `UNION` còn phải loại duplicate và đôi khi vô tình che cycle
thay vì mô hình hóa cycle đúng.

---

## 24. Duyệt hierarchy

```sql
CREATE TABLE app.categories (
    category_id bigint PRIMARY KEY,
    parent_id bigint REFERENCES app.categories (category_id),
    name text NOT NULL
);
```

Lấy subtree:

```sql
WITH RECURSIVE category_tree AS (
    SELECT
        category_id,
        parent_id,
        name,
        0 AS depth
    FROM app.categories
    WHERE category_id = :root_id

    UNION ALL

    SELECT
        c.category_id,
        c.parent_id,
        c.name,
        t.depth + 1
    FROM app.categories AS c
    JOIN category_tree AS t
      ON c.parent_id = t.category_id
)
SELECT *
FROM category_tree;
```

Index `categories(parent_id)` cần cho recursive child lookup.

---

## 25. `SEARCH` tính thứ tự duyệt, không đổi evaluation guarantee

```sql
WITH RECURSIVE category_tree(category_id, parent_id, name, depth) AS (
    SELECT category_id, parent_id, name, 0
    FROM app.categories
    WHERE category_id = :root_id

    UNION ALL

    SELECT c.category_id, c.parent_id, c.name, t.depth + 1
    FROM app.categories AS c
    JOIN category_tree AS t ON c.parent_id = t.category_id
)
SEARCH DEPTH FIRST BY category_id SET traversal_order
SELECT *
FROM category_tree
ORDER BY traversal_order;
```

Có thể dùng `SEARCH BREADTH FIRST`. Clause tạo ordering column; muốn output theo
thứ tự vẫn phải `ORDER BY`. Thêm tie columns khi business order cần deterministic.

---

## 26. `CYCLE` ngăn graph loop

```sql
WITH RECURSIVE category_tree(category_id, parent_id, name) AS (
    SELECT category_id, parent_id, name
    FROM app.categories
    WHERE category_id = :root_id

    UNION ALL

    SELECT c.category_id, c.parent_id, c.name
    FROM app.categories AS c
    JOIN category_tree AS t ON c.parent_id = t.category_id
)
CYCLE category_id SET is_cycle USING path
SELECT category_id, parent_id, name, is_cycle, path
FROM category_tree;
```

`is_cycle` và `path` được thêm ngầm. Nếu path của `CYCLE` đã cung cấp depth-first
ordering cần dùng, thêm `SEARCH DEPTH FIRST` có thể tính trùng; sort theo path.

Cycle detection trong query không thay constraint/workflow ngăn hierarchy xấu lúc
write.

---

## 27. Recursive query cần termination và resource boundary

Đặt boundary theo domain:

- cycle detection;
- maximum depth hợp lý;
- anchor selective;
- index recursive join key;
- statement timeout;
- đo working rows/temp spill.

`LIMIT` ở parent có thể giúp test loop trong PostgreSQL vì executor đôi khi chỉ
fetch phần cần, nhưng không phải production safeguard: outer sort/join có thể yêu
cầu toàn bộ recursive result.

---

## 28. `GROUPING SETS` thay nhiều scan/UNION

```sql
SELECT
    business_date,
    status,
    sum(total) AS amount
FROM app.orders
GROUP BY GROUPING SETS (
    (business_date, status),
    (business_date),
    (status),
    ()
);
```

Một query tạo detail subtotal theo ngày/trạng thái, subtotal từng chiều và grand
total. Planner có thể chia sẻ scan/aggregate work tốt hơn các query rời, nhưng số
grouping sets lớn vẫn tạo output/work lớn.

---

## 29. `ROLLUP`, `CUBE` và `GROUPING()`

```sql
SELECT
    business_date,
    status,
    grouping(business_date, status) AS grouping_mask,
    sum(total) AS amount
FROM app.orders
GROUP BY ROLLUP (business_date, status)
ORDER BY business_date NULLS LAST, status NULLS LAST;
```

- `ROLLUP(a,b)` tạo `(a,b)`, `(a)`, `()`;
- `CUBE(a,b)` thêm `(b)`;
- rolled-up dimension hiển thị `NULL`, có thể lẫn null thật;
- `GROUPING()` phân biệt subtotal/grand total với dữ liệu null.

`CUBE` tăng tổ hợp theo số chiều; tránh cube nhiều dimension không có consumer.

---

## 30. `UNION ALL` trước, deduplicate khi thật sự cần

```sql
SELECT order_id, created_at, 'live' AS source
FROM app.orders
UNION ALL
SELECT order_id, created_at, 'archive' AS source
FROM app.orders_archive;
```

`UNION` loại duplicate bằng sort/hash; `UNION ALL` nối kết quả và thường rẻ hơn.
Chọn theo semantics, không dùng `UNION` để che duplicate do join sai.

`INTERSECT` lấy phần chung, `EXCEPT` lấy phần chỉ ở bên trái; mặc định đều distinct,
thêm `ALL` để giữ multiplicity. Dùng parentheses khi mỗi nhánh có `ORDER BY/LIMIT`.

---

## 31. `VALUES` là relation nhỏ typed

```sql
WITH requested_status(code, priority) AS (
    VALUES
        ('PENDING'::text, 1),
        ('PAID'::text, 2),
        ('CANCELLED'::text, 3)
)
SELECT o.order_id, r.priority
FROM app.orders AS o
JOIN requested_status AS r
  ON r.code = o.status;
```

Hữu ích cho batch input nhỏ, mapping tạm và test. Input lớn nên dùng staging temp/
unlogged table hoặc `COPY`, có type/constraint/index và analyze phù hợp.

Cast explicit khi type inference có thể mơ hồ.

---

## 32. Row comparison cho composite cursor

```sql
WHERE (created_at, order_id) < (:cursor_time, :cursor_id)
ORDER BY created_at DESC, order_id DESC
LIMIT 50
```

Row constructor comparison dùng lexicographic semantics, gọn hơn:

```text
created_at < cursor_time
OR (created_at = cursor_time AND order_id < cursor_id)
```

Columns/cursor cần compatible type, ordering và null policy rõ. Index cùng order
`(created_at DESC, order_id DESC)` có thể hỗ trợ.

---

## 33. Keyset pagination thay OFFSET sâu

Trang đầu:

```sql
SELECT order_id, created_at, total
FROM app.orders
ORDER BY created_at DESC, order_id DESC
LIMIT 50;
```

Trang sau dùng row cuối làm cursor:

```sql
SELECT order_id, created_at, total
FROM app.orders
WHERE (created_at, order_id) < (:last_created_at, :last_order_id)
ORDER BY created_at DESC, order_id DESC
LIMIT 50;
```

`OFFSET 100000` vẫn phải tìm/bỏ qua nhiều row và page drift khi concurrent writes.
Keyset ổn định hơn với total order, nhưng không nhảy tùy ý tới trang N và cursor
phải encode toàn sort key.

Snapshot semantics vẫn áp dụng: các request pagination khác transaction có thể
thấy commit mới; định nghĩa API consistency rõ.

---

## 34. Upsert bằng `ON CONFLICT`

```sql
INSERT INTO app.inventory (sku, quantity_on_hand, reorder_level)
VALUES (:sku, :delta, 0)
ON CONFLICT (sku) DO UPDATE
SET quantity_on_hand =
    app.inventory.quantity_on_hand + EXCLUDED.quantity_on_hand
RETURNING sku, quantity_on_hand;
```

`EXCLUDED` là row đề xuất sau ảnh hưởng của `BEFORE INSERT` trigger. Arbiter là
unique index/constraint được suy luận hoặc chỉ định.

`ON CONFLICT DO UPDATE` bảo đảm atomic insert-or-update outcome khi không có lỗi
độc lập. Nó không tự bảo đảm business idempotency: retry delta cộng thêm có thể
cộng hai lần nếu thiếu request key.

---

## 35. Conditional upsert và row bị khóa nhưng không update

```sql
INSERT INTO app.documents (document_id, content, version)
VALUES (:id, :content, 1)
ON CONFLICT (document_id) DO UPDATE
SET
    content = EXCLUDED.content,
    version = app.documents.version + 1
WHERE app.documents.version = :expected_version
RETURNING document_id, version;
```

Nếu conflict row bị khóa nhưng `WHERE` của `DO UPDATE` false, row không được update
và không xuất hiện trong `RETURNING`. Application phải coi zero row là conflict,
không là success im lặng.

---

## 36. `MERGE` cho nhiều action theo source/target

```sql
MERGE INTO app.inventory AS target
USING (
    VALUES (:sku, :delta)
) AS source(sku, delta)
ON source.sku = target.sku
WHEN MATCHED
     AND target.quantity_on_hand + source.delta > 0 THEN
    UPDATE SET quantity_on_hand = target.quantity_on_hand + source.delta
WHEN MATCHED THEN
    DELETE
WHEN NOT MATCHED
     AND source.delta > 0 THEN
    INSERT (sku, quantity_on_hand, reorder_level)
    VALUES (source.sku, source.delta, 0)
RETURNING
    merge_action() AS action,
    old.quantity_on_hand AS old_quantity,
    new.quantity_on_hand AS new_quantity;
```

PostgreSQL 18 `MERGE` hỗ trợ `RETURNING` và `merge_action()`.

Source phải không tạo nhiều candidate rows sửa cùng target, nếu không có thể gặp
cardinality violation. Deduplicate/validate staging source trước.

---

## 37. `MERGE` và `ON CONFLICT` không thay thế hoàn toàn nhau

Chọn `ON CONFLICT` khi:

- một insert cần atomic insert-or-update theo unique arbiter;
- concurrency trên same key là trọng tâm;
- logic conflict đơn giản.

Chọn `MERGE` khi:

- source set cần nhiều nhánh matched/not matched by source/target;
- cần insert/update/delete trong một statement;
- đồng bộ staging với target.

Khi concurrent insert xảy ra, `MERGE` không có cùng guarantee “insert hoặc update”
như `ON CONFLICT`; isolation/unique violation/retry vẫn áp dụng. Source order cũng
không mặc định deterministic, có thể ảnh hưởng deadlock order.

---

## 38. PostgreSQL 18 `RETURNING OLD/NEW`

```sql
UPDATE app.orders
SET status = 'CANCELLED'
WHERE order_id = :order_id
  AND status = 'PENDING'
RETURNING
    old.status AS previous_status,
    new.status AS current_status,
    new.order_id;
```

PostgreSQL 18 cho `OLD`/`NEW` trong `INSERT`, `UPDATE`, `DELETE`, `MERGE`:

- simple INSERT: old values null;
- DELETE: new values null;
- upsert conflict-update: old và new đều hữu ích;
- trigger-modified final row được phản ánh theo DML semantics.

Giảm round trip và tránh query lại bằng snapshot khác.

---

## 39. `UPDATE ... FROM` phải có tối đa một source match mỗi target

```sql
UPDATE app.inventory AS i
SET quantity_on_hand = s.new_quantity
FROM app.inventory_stage AS s
WHERE s.sku = i.sku
RETURNING i.sku, old.quantity_on_hand, new.quantity_on_hand;
```

Nếu nhiều source row match một target, target chỉ được update một lần nhưng source
row nào được dùng không dễ dự đoán. Enforce unique staging key hoặc aggregate/
deduplicate source trước.

Tương tự, `DELETE ... USING` cho join-based delete nhưng cần kiểm tra multiplicity
và business predicate.

---

## 40. Tránh N+1 bằng join/aggregate batch

Anti-pattern application:

```text
SELECT 100 customers
for each customer:
    SELECT 3 recent orders
```

Thay bằng:

- window top N cho toàn batch;
- `LATERAL` cho parent set nhỏ;
- aggregate JSON/array khi API contract thật sự nested;
- query hai bước theo batch IDs nếu tránh row multiplication dễ hơn.

```sql
SELECT
    customer_id,
    jsonb_agg(
        jsonb_build_object(
            'orderId', order_id,
            'createdAt', created_at,
            'total', total
        )
        ORDER BY created_at DESC, order_id DESC
    ) AS orders
FROM app.orders
WHERE customer_id = ANY(:customer_ids)
GROUP BY customer_id;
```

Đừng trả JSON aggregate khổng lồ; pagination/size boundary vẫn cần.

---

## 41. `ANY(array)` cho batch key, temp table cho batch lớn

```sql
SELECT order_id, customer_id, status
FROM app.orders
WHERE customer_id = ANY(:customer_ids);
```

Phù hợp danh sách vừa/nhỏ. Với hàng chục nghìn key:

- parse/bind/plan selectivity khó hơn;
- request payload lớn;
- có thể dùng temp/staging table + `COPY` + `ANALYZE` rồi join;
- transaction pooling ảnh hưởng temp table/session state.

Không nối literal list vào SQL; dùng bind parameter hoặc staging relation.

---

## 42. Deterministic order là contract

Không có `ORDER BY`, PostgreSQL có thể trả row theo heap/index/parallel plan bất kỳ.
`LIMIT` không làm order ổn định.

```sql
ORDER BY created_at DESC, order_id DESC
```

Tie-breaker unique cần cho:

- pagination;
- top N;
- `row_number`;
- `DISTINCT ON`;
- repeatable test/output.

Collation và null ordering cũng thuộc contract. Sau upgrade/collation change, thứ
tự text có thể cần review/reindex.

---

## 43. Một statement vẫn cần transaction/isolation đúng

Set-based statement giảm race window và round trip, nhưng không xóa:

- write skew xuyên row;
- unique/FK/exclusion conflict;
- deadlock;
- serialization failure;
- external side effect;
- lock duration của statement lớn.

Upsert, MERGE và DML CTE vẫn chạy theo isolation level. Batch statement quá lớn có
thể giữ lock/WAL/undo-by-rollback lâu; chia batch theo key range với idempotent
progress khi cần.

---

## 44. Luôn đọc plan cùng semantics

Hai query trả cùng kết quả trên sample có thể khác khi:

- null xuất hiện;
- duplicate/source multiplicity xuất hiện;
- tie order xuất hiện;
- concurrent write xảy ra;
- empty set;
- cycle trong graph.

Quy trình:

```text
1. Chứng minh semantics bằng edge-case tests
2. EXPLAIN estimate
3. EXPLAIN ANALYZE BUFFERS khi an toàn
4. Thiết kế index/statistics
5. Test concurrency và retry
```

Không rewrite sang query “nhanh hơn” nếu đã đổi nghĩa outer join, null hay tie.

---

## 45. Failure modes thường gặp

### “CTE luôn materialize”

Không còn đúng từ PostgreSQL 12 cho CTE non-recursive side-effect-free phù hợp.
Kiểm tra fold, `MATERIALIZED` và `NOT MATERIALIZED` bằng plan.

### “Window `ORDER BY` là output order”

Nó chỉ định thứ tự tính window. Output cuối vẫn cần `ORDER BY`.

### “`last_value` luôn là row cuối partition”

Nó dùng frame; default thường kết thúc ở peer hiện tại.

### “`DISTINCT ON` tự chọn row mới nhất”

Không có `ORDER BY` đúng prefix và tie-breaker thì row giữ lại không dự đoán được.

### “`NOT IN` giống `NOT EXISTS`”

Null trong subquery có thể làm `NOT IN` thành unknown.

### “`UNION` chỉ nối kết quả”

Nó loại duplicate; `UNION ALL` mới nối giữ multiplicity.

### “MERGE là upsert concurrency-safe giống ON CONFLICT”

Hai statement có concurrency guarantees khác nhau; unique violation/retry vẫn có
thể xảy ra với MERGE.

### “Một statement luôn nhẹ hơn nhiều statement”

Một query có Cartesian explosion, sort/hash spill hoặc LATERAL loops lớn vẫn có
thể tệ hơn batch có thiết kế.

---

## 46. Checklist production

### Semantics

- [ ] Outer join predicate đặt ở `ON` hay `WHERE` đúng nghĩa?
- [ ] Null/empty set/duplicate/tie/cycle có test?
- [ ] Output/pagination có total deterministic order?
- [ ] Anti join dùng nullable-safe semantics?
- [ ] Source của UPDATE/MERGE unique theo target key?

### Window/aggregate

- [ ] Window có partition/order/tie-breaker đúng?
- [ ] Frame `ROWS/RANGE/GROUPS` được khai báo khi kết quả phụ thuộc?
- [ ] `last_value`/running aggregate không dựa default ngoài ý muốn?
- [ ] Aggregate collection có internal `ORDER BY` và size bound?
- [ ] `GROUPING()` phân biệt rolled-up null?

### CTE/recursion

- [ ] CTE fold/materialize được kiểm tra bằng EXPLAIN?
- [ ] DML CTE truyền dữ liệu qua `RETURNING`, không dựa execution order?
- [ ] Recursive query có anchor selective, index, cycle và depth boundary?
- [ ] `SEARCH` output có `ORDER BY` explicit?
- [ ] Không dùng parent `LIMIT` như cycle protection production?

### DML/concurrency

- [ ] `ON CONFLICT` có đúng unique arbiter và idempotency contract?
- [ ] Conditional upsert xử lý zero returned rows?
- [ ] MERGE source được deduplicate và concurrency behavior được test?
- [ ] `RETURNING OLD/NEW` được dùng để tránh read-after-write thừa?
- [ ] Batch size, lock, WAL, retry và external side effect có boundary?

### Performance

- [ ] N+1 được thay bằng set/batch phù hợp?
- [ ] Window toàn tập và LATERAL per-parent đã được so bằng plan?
- [ ] Keyset index khớp cursor/order?
- [ ] Không dùng UNION/DISTINCT để che join duplicate?
- [ ] Đọc `actual rows × loops`, temp spill và buffers?

---

## 47. Câu hỏi phỏng vấn

1. Logical processing order giải thích vì sao window không nằm trong WHERE?
2. Predicate ở `ON` và `WHERE` khác nhau thế nào với LEFT JOIN?
3. Semi join/anti join bằng EXISTS có lợi gì?
4. Vì sao `NOT IN` có thể trả không row khi subquery chứa null?
5. `FILTER` khác WHERE trong aggregate thế nào?
6. `count(*)`, `count(col)` và `sum` trên tập rỗng khác gì?
7. Window partition, order và frame khác nhau ra sao?
8. `row_number`, `rank`, `dense_rank` xử lý tie thế nào?
9. Cách lấy top N mỗi group bằng window?
10. `DISTINCT ON` cần quan hệ gì với ORDER BY?
11. Default window frame gây bẫy `last_value` thế nào?
12. `ROWS`, `RANGE`, `GROUPS` khác nhau gì?
13. Khi nào top-N `LATERAL` tốt hơn window?
14. `WITH ORDINALITY` dùng để làm gì?
15. Khi nào CTE được fold/materialize?
16. DML CTE có execution order và snapshot semantics gì?
17. Recursive CTE được đánh giá bằng working table ra sao?
18. `SEARCH` và `CYCLE` giải quyết gì?
19. `ROLLUP`, `CUBE`, `GROUPING SETS` khác nhau gì?
20. Vì sao `UNION ALL` thường nhanh hơn `UNION`?
21. Row comparison hỗ trợ keyset pagination thế nào?
22. Keyset và OFFSET pagination đánh đổi gì?
23. `ON CONFLICT DO UPDATE` có guarantee concurrency gì?
24. Conditional upsert không RETURNING row nghĩa là gì?
25. MERGE khác ON CONFLICT ở use case và concurrency nào?
26. PostgreSQL 18 `RETURNING OLD/NEW` giúp gì?
27. Vì sao UPDATE FROM phải bảo đảm một source match mỗi target?
28. Các cách tránh N+1 mà không tạo JSON aggregate vô hạn?

---

## 48. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [SELECT](https://www.postgresql.org/docs/18/sql-select.html)
- [Table expressions, joins và LATERAL](https://www.postgresql.org/docs/18/queries-table-expressions.html)
- [Subquery expressions](https://www.postgresql.org/docs/18/functions-subquery.html)
- [Aggregate functions](https://www.postgresql.org/docs/18/functions-aggregate.html)
- [Window tutorial](https://www.postgresql.org/docs/18/tutorial-window.html)
- [Window functions](https://www.postgresql.org/docs/18/functions-window.html)
- [WITH queries, recursion, SEARCH/CYCLE](https://www.postgresql.org/docs/18/queries-with.html)
- [UNION, INTERSECT, EXCEPT](https://www.postgresql.org/docs/18/queries-union.html)
- [Set-returning functions](https://www.postgresql.org/docs/18/functions-srf.html)
- [INSERT và ON CONFLICT](https://www.postgresql.org/docs/18/sql-insert.html)
- [MERGE](https://www.postgresql.org/docs/18/sql-merge.html)
- [Returning modified rows](https://www.postgresql.org/docs/18/dml-returning.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

Học tiếp:

1. [Performance & Autovacuum](../performance/tuning_autovacuum.md).
2. [Partitioning & Large Tables](../performance/partitioning_large_tables.md).
3. [PostgreSQL từ Java/Spring](../integration/jdbc_spring.md).

---

*Cập nhật lần cuối: 2026-07-31.*
