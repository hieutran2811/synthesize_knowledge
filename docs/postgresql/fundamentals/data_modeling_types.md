---
title: "PostgreSQL Data Modeling & Types"
topic: postgresql
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "PostgreSQL 18"
source_count: 16
---
# PostgreSQL Data Modeling & Types

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này xem data model như một
> contract thực thi được: type biểu diễn đúng đại lượng, constraint chặn trạng
> thái vô nghĩa và migration làm contract tiến hóa mà không gây downtime.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Architecture & Storage](architecture_storage.md).

---

## 1. Data model là executable contract

Validation ở API giúp trả lỗi thân thiện, nhưng không thay thế constraint trong
database. Dữ liệu còn có thể đến từ:

- batch job, migration và script vận hành;
- một service khác hoặc phiên bản application cũ;
- retry, race condition và thao tác thủ công;
- logical replication/import không đi qua cùng code path.

Một model tốt trả lời bốn câu:

1. **Identity:** row nào đại diện cho cùng một thực thể?
2. **Validity:** giá trị và tổ hợp giá trị nào hợp lệ?
3. **Relationship:** thực thể nào được tham chiếu và vòng đời liên quan ra sao?
4. **Evolution:** thêm rule/type mới thế nào khi table đang có dữ liệu và traffic?

```text
business invariant
       │
       ├── type                 phạm vi biểu diễn
       ├── NOT NULL / CHECK     rule trên một row
       ├── UNIQUE / PK          identity, cross-row uniqueness
       ├── FK                   referential integrity
       └── EXCLUDE              cấm xung đột như khoảng thời gian chồng nhau
```

Nguyên tắc: đặt invariant ở tầng thấp nhất có thể diễn đạt đúng. Không dùng
`CHECK` gọi sang row khác khi `UNIQUE`, `FOREIGN KEY` hoặc `EXCLUDE` mới là
constraint phù hợp.

---

## 2. Cluster, database và schema là ba boundary khác nhau

```text
PostgreSQL cluster / instance
├── database: app_prod
│   ├── schema: app
│   ├── schema: billing
│   └── schema: audit
└── database: analytics
```

- một connection chỉ làm việc trực tiếp trong **một database**;
- schema là namespace bên trong database, không phải database thu nhỏ;
- role và tablespace thuộc phạm vi cluster, còn table/type/function thuộc database;
- PostgreSQL không hỗ trợ join xuyên database như join xuyên schema; FDW hoặc
  `dblink` là integration riêng, có transaction/failure semantics riêng.

Không tách database chỉ để đặt tên đẹp. Tách database khi thật sự cần boundary về
connection, extension, ownership, lifecycle hoặc backup/restore. Dùng schema khi
các object cần transaction và join trực tiếp với nhau.

Ví dụ ownership tách khỏi runtime:

```sql
CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_runtime LOGIN;

CREATE SCHEMA app AUTHORIZATION app_owner;
GRANT USAGE ON SCHEMA app TO app_runtime;
```

Migration chạy bằng owner hoặc role được ủy quyền; application runtime chỉ nhận
quyền cần thiết. Runtime không nên sở hữu table vì owner có thể thay đổi/drop
object và bỏ qua một số kiểm soát quyền.

---

## 3. `search_path` cũng là security boundary

Tên không ghi schema được PostgreSQL resolve theo `search_path`. Nếu một schema
trong path cho phép user không tin cậy `CREATE`, user đó có thể tạo object trùng
tên và thay đổi object mà câu SQL resolve tới.

Baseline cho database mới hoặc database đã upgrade:

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

ALTER ROLE app_runtime
    IN DATABASE app_prod
    SET search_path = pg_catalog, app;
```

Thực hành:

- migration và security-sensitive SQL dùng tên đầy đủ như `app.orders`;
- không đặt schema writable bởi user không tin cậy trong `search_path`;
- kiểm tra grant thực tế thay vì giả định default của bản cài mới;
- function `SECURITY DEFINER` phải tự đặt `search_path` an toàn;
- extension nên có schema và ownership được kiểm soát.

Kiểm tra:

```sql
SHOW search_path;

SELECT
    n.nspname,
    has_schema_privilege(current_user, n.oid, 'USAGE') AS can_use,
    has_schema_privilege(current_user, n.oid, 'CREATE') AS can_create
FROM pg_namespace AS n
ORDER BY n.nspname;
```

PostgreSQL 15+ thu hồi quyền tạo trong `public` khỏi `PUBLIC` ở database mới,
nhưng database upgrade có thể giữ grant cũ. Vì vậy vẫn phải audit.

---

## 4. Naming và ownership dễ vận hành hơn “thông minh”

Quy ước thực dụng:

- dùng `snake_case`, chữ thường và tránh quoted identifier;
- tên table số nhiều hay số ít đều được, miễn nhất quán;
- đặt tên constraint có ý nghĩa: `orders_total_nonnegative`;
- column mang đơn vị: `timeout_ms`, `amount_minor`, `weight_kg`;
- phân biệt `created_at` là instant với `business_date` là ngày nghiệp vụ;
- schema application không dùng tên `pg_*`;
- mỗi object có owner rõ, không để migration tool vô tình tạo nhiều owner.

PostgreSQL tự chuyển identifier không quote thành chữ thường:

```sql
CREATE TABLE app.order_items (
    order_id bigint NOT NULL,
    line_no integer NOT NULL,
    quantity integer NOT NULL,
    CONSTRAINT order_items_pk PRIMARY KEY (order_id, line_no),
    CONSTRAINT order_items_quantity_positive CHECK (quantity > 0)
);
```

Tránh `"OrderItems"` nếu không muốn mọi query sau đó đều phải quote đúng hoa/thường.

---

## 5. Một aggregate mẫu

Model dưới đây được dùng xuyên suốt bài:

```sql
CREATE TABLE app.customers (
    customer_id bigint GENERATED ALWAYS AS IDENTITY,
    public_id uuid NOT NULL DEFAULT uuidv7(),
    email text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT customers_pk PRIMARY KEY (customer_id),
    CONSTRAINT customers_public_id_uk UNIQUE (public_id),
    CONSTRAINT customers_email_nonempty
        CHECK (email = btrim(email) AND email <> '')
);

CREATE TABLE app.orders (
    order_id bigint GENERATED ALWAYS AS IDENTITY,
    public_id uuid NOT NULL DEFAULT uuidv7(),
    customer_id bigint NOT NULL,
    status text NOT NULL DEFAULT 'PENDING',
    currency text NOT NULL,
    subtotal numeric(19, 4) NOT NULL,
    discount numeric(19, 4) NOT NULL DEFAULT 0,
    total numeric(19, 4)
        GENERATED ALWAYS AS (subtotal - discount) STORED,
    business_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT orders_pk PRIMARY KEY (order_id),
    CONSTRAINT orders_public_id_uk UNIQUE (public_id),
    CONSTRAINT orders_customer_fk
        FOREIGN KEY (customer_id) REFERENCES app.customers (customer_id),
    CONSTRAINT orders_status_ck
        CHECK (status IN ('PENDING', 'PAID', 'CANCELLED')),
    CONSTRAINT orders_currency_ck
        CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT orders_amount_ck
        CHECK (subtotal >= 0 AND discount >= 0 AND discount <= subtotal),
    CONSTRAINT orders_metadata_object_ck
        CHECK (jsonb_typeof(metadata) = 'object')
);

CREATE INDEX orders_customer_id_idx ON app.orders (customer_id);
```

Đây không phải universal schema. Điểm chính là:

- internal key và public identifier có mục đích khác nhau;
- tiền dùng exact numeric và currency riêng;
- event time, business date không bị trộn;
- state quan trọng là column có constraint, không bị giấu hết trong JSONB;
- FK ở child có index phục vụ join/delete/update phía parent.

---

## 6. Natural key hay surrogate key?

### Natural key

Natural key có nghĩa nghiệp vụ, ví dụ `(country_code, tax_number)`.

Ưu điểm:

- tự ngăn duplicate theo domain;
- query/debug dễ hiểu;
- có thể tránh thêm một lớp mapping.

Rủi ro:

- business rule có thể đổi;
- key dài làm mọi FK/index con rộng hơn;
- dữ liệu bên ngoài tưởng ổn định nhưng vẫn có correction/merge;
- PII trong key có thể lan sang log, URL và downstream.

### Surrogate key

`bigint identity` hoặc `uuid` không mang nghĩa nghiệp vụ.

Ưu điểm là ổn định, gọn và tách identity kỹ thuật khỏi thuộc tính thay đổi. Nhưng
surrogate key **không thay thế** unique constraint của business key:

```sql
CREATE TABLE app.accounts (
    account_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id bigint NOT NULL,
    external_account_no text NOT NULL,
    CONSTRAINT accounts_business_key_uk
        UNIQUE (tenant_id, external_account_no)
);
```

Nếu bỏ unique business key, retry có thể tạo hai row với hai surrogate ID hợp lệ.

---

## 7. Identity, sequence và `serial`

Modern DDL nên ưu tiên identity:

```sql
CREATE TABLE app.events (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payload jsonb NOT NULL
);
```

`GENERATED ALWAYS` bảo vệ tốt hơn trước explicit value; import đặc biệt phải dùng
`OVERRIDING SYSTEM VALUE`. `BY DEFAULT` cho phép explicit value thắng default,
phù hợp hơn với một số luồng restore/import.

Identity dùng sequence ngầm. Cần nhớ:

- identity tự thêm `NOT NULL`, nhưng **không tự bảo đảm unique**;
- sequence allocation không rollback như row insert;
- cache, rollback, crash, failover và manual reset đều có thể tạo gap;
- ID tăng không phải chứng cứ commit order;
- không dùng `max(id) + 1`;
- “số hóa đơn không được hở” là bài toán ledger/serialization riêng, không phải
  tùy chọn của primary key.

`serial`/`bigserial` là pseudo-type lịch sử, về cơ bản tạo sequence và default
`nextval(...)`. Nó vẫn hoạt động, nhưng identity thể hiện intent và dependency
trong DDL rõ hơn.

Xem sequence liên kết với identity:

```sql
SELECT pg_get_serial_sequence('app.events', 'event_id');
```

---

## 8. `bigint`, UUID v4 hay UUID v7?

| Chọn | Điểm mạnh | Đánh đổi |
|---|---|---|
| `bigint identity` | 8 byte, index gọn, locality tốt | cần database cấp ID; dễ đoán |
| UUID v4 | tạo phân tán, khó trùng, không lộ thứ tự thời gian | 16 byte, random insert làm locality kém hơn |
| UUID v7 | tạo phân tán, gần theo thời gian, index locality tốt hơn v4 | lộ timestamp gần đúng; không phải thứ tự commit |

PostgreSQL 18 có hàm built-in:

```sql
SELECT uuidv4(), uuidv7();

SELECT
    uuid_extract_version(uuidv7()) AS version,
    uuid_extract_timestamp(uuidv7()) AS embedded_time;
```

UUID là identifier, không phải secret. Không dùng UUID thay access token. UUID v7
có thành phần timestamp nên không phù hợp khi thời điểm tạo phải được che giấu.
Trong cùng khoảng thời gian rất nhỏ, phần random vẫn quyết định thứ tự; nó không
thay sequence nghiệp vụ.

Pattern phổ biến:

```text
bigint PK       → join/FK/index nội bộ gọn
uuid public_id  → API, event, đồng bộ giữa hệ thống
```

Đừng thêm cả hai nếu không có consumer/mục đích rõ ràng.

---

## 9. Integer: chọn theo miền giá trị

| Type | Kích thước | Khoảng gần đúng |
|---|---:|---|
| `smallint` | 2 byte | ±32 nghìn |
| `integer` | 4 byte | ±2,1 tỷ |
| `bigint` | 8 byte | ±9,22 × 10^18 |

Dùng:

- `integer` cho count/rank nhỏ có giới hạn rõ;
- `bigint` cho ID hoặc counter có vòng đời dài;
- `CHECK` để biểu diễn giới hạn nghiệp vụ, vì type chỉ giới hạn vật lý.

```sql
CREATE TABLE app.inventory (
    sku text PRIMARY KEY,
    quantity_on_hand bigint NOT NULL,
    reorder_level integer NOT NULL,
    CONSTRAINT inventory_quantity_ck CHECK (quantity_on_hand >= 0),
    CONSTRAINT inventory_reorder_level_ck CHECK (reorder_level >= 0)
);
```

Không dùng `smallint` chỉ để tiết kiệm vài byte khi rủi ro overflow và migration
cao hơn lợi ích.

---

## 10. `numeric` khác floating point

`numeric`/`decimal` là exact decimal; `real` và `double precision` là IEEE
floating point gần đúng.

```sql
SELECT
    0.1::numeric + 0.2::numeric AS exact_result,
    0.1::double precision + 0.2::double precision AS approximate_result;
```

Dùng:

- `numeric(p, s)` cho tiền, tỷ lệ hoặc decimal có contract rõ;
- `double precision` cho đo lường/khoa học chấp nhận sai số;
- integer minor unit khi currency và scale cố định, volume rất lớn;
- `CHECK` cho miền nghiệp vụ, ví dụ tỷ lệ từ 0 đến 1.

```sql
CREATE TABLE app.tax_rules (
    tax_rule_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rate numeric(9, 8) NOT NULL,
    CONSTRAINT tax_rules_rate_ck CHECK (rate >= 0 AND rate <= 1)
);
```

`numeric(19,4)` không mặc nhiên đúng cho mọi ngành. Chọn precision/scale từ giá
trị lớn nhất, phép tính trung gian, rounding rule và contract downstream.

---

## 11. Mô hình hóa tiền

Ba phần không nên bị trộn:

```text
amount + currency + rounding rule
```

Mẫu exact decimal:

```sql
CREATE TABLE app.payments (
    payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    amount numeric(19, 4) NOT NULL,
    currency text NOT NULL,
    CONSTRAINT payments_amount_positive CHECK (amount > 0),
    CONSTRAINT payments_currency_ck CHECK (currency ~ '^[A-Z]{3}$')
);
```

Mẫu minor unit:

```sql
CREATE TABLE app.ledger_entries (
    entry_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    amount_minor bigint NOT NULL,
    currency text NOT NULL,
    scale smallint NOT NULL,
    CONSTRAINT ledger_currency_ck CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ledger_scale_ck CHECK (scale BETWEEN 0 AND 8)
);
```

Không dùng `real`/`double precision` cho tiền. Type `money` của PostgreSQL là
fixed fractional type phụ thuộc `lc_monetary`; output và dump/restore giữa locale
khác nhau có caveat, đồng thời một value không mang currency code. Vì vậy
`numeric` hoặc minor unit + currency thường rõ và portable hơn cho hệ thống
multi-currency.

Rounding nên có một owner và thời điểm rõ, ví dụ round từng line hay round tổng.
Hai chiến lược đều “đúng” về toán nhưng có thể cho kết quả nghiệp vụ khác.

---

## 12. `text`, `varchar`, `char` và collation

Trong PostgreSQL, `text` và `varchar` không giới hạn có đặc tính hiệu năng thực tế
tương đương cho phần lớn workload. `varchar(n)` hữu ích khi **n** là business
constraint thật; nếu không, `text` + constraint có tên thường dễ hiểu hơn.

```sql
CREATE TABLE app.products (
    product_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku text NOT NULL,
    display_name text NOT NULL,
    CONSTRAINT products_sku_length_ck
        CHECK (char_length(sku) BETWEEN 1 AND 64),
    CONSTRAINT products_sku_uk UNIQUE (sku)
);
```

`char(n)` blank-pad và có comparison semantics dễ gây bất ngờ; chỉ dùng khi
contract thực sự là fixed-width.

Collation quyết định equality/order/index behavior của text:

- deterministic collation chỉ coi chuỗi cùng byte là bằng nhau;
- nondeterministic ICU collation có thể case/accent-insensitive;
- nondeterministic collation có performance cost, B-tree không deduplicate và một
  số pattern matching không dùng được;
- đổi OS/ICU/collation version có thể cần kiểm tra và reindex.

Case-insensitive identity cần quyết định rõ:

1. lưu thêm normalized key như `lower(email)` và unique expression index;
2. dùng nondeterministic ICU collation được quản trị rõ;
3. dùng extension `citext` khi semantics của nó đúng với yêu cầu.

Không gọi `lower()` rải rác ở application rồi hy vọng mọi writer làm giống nhau.

---

## 13. Boolean, `NULL` và logic ba giá trị

`NULL` nghĩa là unknown/not present, không phải `false`, `0` hay chuỗi rỗng.

```sql
SELECT
    NULL = NULL AS equality_is_unknown,
    NULL IS NULL AS explicit_null_test,
    TRUE AND NULL AS three_valued_logic;
```

Trong `WHERE`, chỉ row có biểu thức `TRUE` được giữ; `FALSE` và `UNKNOWN` đều bị
loại. Dùng:

```sql
WHERE deleted_at IS NULL
WHERE flag IS TRUE
WHERE value IS DISTINCT FROM previous_value
```

`IS DISTINCT FROM` coi `NULL` như một giá trị so sánh được, hữu ích cho change
detection.

Nếu boolean chỉ có hai trạng thái, đặt `NOT NULL` và default có chủ đích:

```sql
is_active boolean NOT NULL DEFAULT true
```

Nếu `NULL` là trạng thái thứ ba có nghĩa nghiệp vụ, hãy đặt tên và document nghĩa
đó; nhiều trường hợp enum/state rõ hơn nullable boolean.

---

## 14. `date`, `timestamp` và `timestamptz`

| Ý nghĩa | Type thường phù hợp |
|---|---|
| ngày sinh/ngày kế toán | `date` |
| một instant toàn cầu | `timestamptz` |
| giờ địa phương chưa gắn múi giờ | `timestamp` |
| thời lượng/lịch như “1 month” | `interval` |

`timestamptz` là tên ngắn của `timestamp with time zone`. PostgreSQL normalize
instant, không giữ timezone gốc trong value; output được render theo timezone của
session.

```sql
SET TIME ZONE 'Asia/Ho_Chi_Minh';
SELECT '2026-07-31 09:00:00+07'::timestamptz;

SET TIME ZONE 'UTC';
SELECT '2026-07-31 09:00:00+07'::timestamptz;
```

Hai output khác nhau nhưng là cùng instant.

Quy tắc:

- event/audit/API timestamp dùng `timestamptz`;
- lịch “mỗi ngày 09:00 theo giờ Việt Nam” cần local time **và** IANA zone;
- nếu cần nhớ zone người dùng chọn, lưu thêm `zone_id`, ví dụ
  `Asia/Ho_Chi_Minh`;
- không dùng abbreviation mơ hồ như `CST`;
- `time with time zone` hiếm khi diễn đạt đúng scheduling vì thiếu ngày và DST.

```sql
CREATE TABLE app.schedules (
    schedule_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    local_start timestamp NOT NULL,
    zone_id text NOT NULL,
    CONSTRAINT schedules_zone_nonempty CHECK (zone_id <> '')
);
```

Application phải validate `zone_id` theo IANA database. Một offset như `+07:00`
không thay thế timezone có lịch sử/DST.

---

## 15. `interval` và khoảng nửa mở

`interval '1 month'` không phải số giây cố định; tháng có độ dài khác nhau. Tách:

- duration vật lý như timeout: integer milliseconds hoặc interval có contract;
- calendar period như một tháng: `interval`;
- cặp start/end cho khoảng hiệu lực.

Khoảng thời gian thường dùng quy ước nửa mở:

```text
[start_at, end_at)
```

Nhờ đó hai khoảng liên tiếp `[09:00, 10:00)` và `[10:00, 11:00)` không overlap,
không cần trừ microsecond.

```sql
CREATE TABLE app.promotions (
    promotion_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    valid_from timestamptz NOT NULL,
    valid_until timestamptz NOT NULL,
    CONSTRAINT promotions_period_ck CHECK (valid_from < valid_until)
);
```

Nếu overlap là invariant quan trọng, dùng range + exclusion constraint thay vì
chỉ kiểm tra start/end ở application.

---

## 16. Default không phải backfill hay validation

Default chỉ được dùng khi column bị bỏ qua hoặc SQL ghi `DEFAULT`. Explicit `NULL`
vẫn là `NULL` nếu column cho phép:

```sql
CREATE TABLE app.tasks (
    task_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    state text NOT NULL DEFAULT 'PENDING',
    created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO app.tasks DEFAULT VALUES;
```

Phân biệt:

- default được tính khi insert;
- generated column được tính từ row và cập nhật khi dependency đổi;
- trigger có control flow mạnh hơn nhưng khó nhìn và test hơn;
- backfill sửa dữ liệu cũ; thêm default không luôn có nghĩa business value cho row
  cũ.

`now()` trả transaction start time, giúp các statement trong transaction nhất
quán. `clock_timestamp()` là wall-clock thay đổi trong statement. Chọn theo
semantics, không theo tên “có vẻ chính xác hơn”.

---

## 17. `CHECK` constraint và bẫy `NULL`

`CHECK` được thỏa khi biểu thức là `TRUE` **hoặc `UNKNOWN`**:

```sql
CREATE TABLE app.coupons (
    coupon_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    discount_percent numeric(5, 2),
    CONSTRAINT coupons_discount_ck
        CHECK (discount_percent > 0 AND discount_percent <= 100)
);
```

Constraint trên vẫn cho `NULL`. Nếu null không hợp lệ:

```sql
ALTER TABLE app.coupons
    ALTER COLUMN discount_percent SET NOT NULL;
```

Rule cho nhiều column trong cùng row phù hợp với `CHECK`:

```sql
ALTER TABLE app.promotions
    ADD CONSTRAINT promotions_window_ck
    CHECK (valid_until > valid_from);
```

Không dùng `CHECK` đọc table khác hoặc row khác. PostgreSQL giả định điều kiện
`CHECK` immutable và chỉ kiểm tra khi insert/update row. Function trong constraint
đổi hành vi có thể làm dữ liệu cũ vi phạm mà database không tự biết; cần drop/re-add
hoặc validate constraint sau thay đổi.

---

## 18. `PRIMARY KEY`, `UNIQUE` và `NULLS NOT DISTINCT`

Primary key = unique + not null + identity chính của row. Một table chỉ có một PK
nhưng có thể có nhiều unique constraint.

PostgreSQL tự tạo unique B-tree index cho PK/UNIQUE; không tạo thêm index trùng:

```sql
CREATE TABLE app.user_profiles (
    user_id bigint PRIMARY KEY,
    national_id text,
    handle text NOT NULL,
    deleted_at timestamptz,
    CONSTRAINT user_profiles_national_id_uk
        UNIQUE NULLS NOT DISTINCT (national_id)
);
```

Mặc định, các `NULL` được coi là khác nhau nên UNIQUE cho phép nhiều row null.
`NULLS NOT DISTINCT` coi chúng bằng nhau và chỉ cho tối đa một null.

Unique constraint toàn phần khác partial unique index:

```sql
CREATE UNIQUE INDEX user_profiles_active_handle_uk
    ON app.user_profiles (handle)
    WHERE deleted_at IS NULL;
```

Partial unique index rất hữu ích cho soft delete nhưng không phải unique
constraint chuẩn và không thể luôn được FK tham chiếu.

---

## 19. Foreign key là consistency và lifecycle contract

```sql
ALTER TABLE app.order_items
    ADD CONSTRAINT order_items_order_fk
    FOREIGN KEY (order_id)
    REFERENCES app.orders (order_id)
    ON DELETE CASCADE;
```

Chọn action theo domain:

| Action | Ý nghĩa |
|---|---|
| `NO ACTION` | mặc định; lỗi nếu vi phạm, có thể deferrable |
| `RESTRICT` | ngăn thao tác ngay, không deferrable theo cùng cách |
| `CASCADE` | propagate delete/update xuống child |
| `SET NULL` | giữ child nhưng bỏ liên kết |
| `SET DEFAULT` | đặt default, vẫn phải thỏa FK |

`CASCADE` không chỉ là tiện lợi: nó quyết định blast radius, lock và lượng WAL.
Đừng cascade qua một graph lớn nếu operator không thể dự đoán số row bị xóa.

PostgreSQL tạo index ở referenced side nhờ PK/UNIQUE, nhưng **không tự tạo index
cho referencing columns**. Index child FK thường cần cho join và để delete/update
parent không phải scan child:

```sql
CREATE INDEX order_items_order_id_idx
    ON app.order_items (order_id);
```

Composite FK nên gồm tenant key khi đó là boundary:

```sql
FOREIGN KEY (tenant_id, customer_id)
REFERENCES app.customers (tenant_id, customer_id)
```

Nếu chỉ FK `customer_id`, một bug có thể gắn row tenant A sang tenant B dù ID tồn
tại hợp lệ.

---

## 20. Deferrable constraint dùng có chủ đích

Constraint mặc định được kiểm tra ở cuối statement. `DEFERRABLE` cho phép hoãn
kiểm tra tới commit:

```sql
CREATE TABLE app.nodes (
    node_id bigint PRIMARY KEY,
    parent_id bigint,
    CONSTRAINT nodes_parent_fk
        FOREIGN KEY (parent_id)
        REFERENCES app.nodes (node_id)
        DEFERRABLE INITIALLY IMMEDIATE
);

BEGIN;
SET CONSTRAINTS nodes_parent_fk DEFERRED;
-- Thực hiện một nhóm thay đổi cần trạng thái trung gian chưa hợp lệ.
COMMIT;
```

Điều này hữu ích cho cyclic graph hoặc reorder phức tạp, nhưng:

- lỗi chuyển từ statement sang commit;
- transaction dài hơn và giữ nhiều work/lock hơn;
- application phải xử lý commit failure;
- không dùng để che một workflow sai.

---

## 21. Range, multirange và exclusion constraint

Built-in range gồm `int4range`, `int8range`, `numrange`, `daterange`, `tsrange`,
`tstzrange`; multirange biểu diễn hợp của nhiều range không chồng nhau.

```sql
SELECT
    daterange(DATE '2026-07-01', DATE '2026-08-01', '[)') AS billing_period,
    DATE '2026-07-15' <@ daterange(
        DATE '2026-07-01',
        DATE '2026-08-01',
        '[)'
    ) AS contains_date;
```

Operator quan trọng:

- `@>` chứa;
- `<@` nằm trong;
- `&&` overlap;
- `-|-` adjacent;
- `*` intersection, `+` union khi kết quả liền mạch.

Cấm hai booking cùng phòng overlap:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE app.room_bookings (
    booking_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id bigint NOT NULL,
    occupied_at tstzrange NOT NULL,
    CONSTRAINT room_bookings_nonempty_ck
        CHECK (NOT isempty(occupied_at)),
    CONSTRAINT room_bookings_no_overlap_excl
        EXCLUDE USING gist (
            room_id WITH =,
            occupied_at WITH &&
        )
);
```

`btree_gist` cung cấp GiST operator class cho scalar như `bigint`; extension phải
được DBA/owner phê duyệt. Exclusion constraint giải quyết race mà “SELECT trước,
INSERT sau” ở application không giải quyết được.

---

## 22. Enum: mạnh nhưng migration có giá

```sql
CREATE TYPE app.payment_state AS ENUM (
    'PENDING',
    'AUTHORIZED',
    'CAPTURED',
    'FAILED'
);
```

Enum phù hợp khi tập giá trị:

- nhỏ, ổn định và thuộc quyền kiểm soát của application;
- không cần metadata/translation/soft delete riêng;
- được dùng lặp lại và type safety đáng giá.

Giá trị enum có thể add/rename, nhưng xóa và reorder khó hơn; deployment nhiều
phiên bản phải hiểu giá trị mới. Với workflow thay đổi thường xuyên, lookup table
có thể phù hợp hơn:

```sql
CREATE TABLE app.payment_states (
    code text PRIMARY KEY,
    is_terminal boolean NOT NULL,
    display_order integer NOT NULL
);
```

`CHECK (state IN (...))` đơn giản hơn enum cho state chỉ thuộc một table, nhưng
việc thay constraint vẫn là schema migration. Không có lựa chọn “khỏi migration”:
chỉ có nơi đặt contract và trade-off khác nhau.

---

## 23. Domain: tái sử dụng type + constraint

Domain tạo type có rule dùng lại:

```sql
CREATE DOMAIN app.currency_code AS text
    CHECK (VALUE ~ '^[A-Z]{3}$');

CREATE DOMAIN app.positive_amount AS numeric(19, 4)
    CHECK (VALUE > 0);

CREATE TABLE app.refunds (
    refund_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    amount app.positive_amount NOT NULL,
    currency app.currency_code NOT NULL
);
```

Best practice là cho domain constraint chấp nhận null và đặt `NOT NULL` ở column.
Domain `NOT NULL` có corner case qua outer join/SQL expression và kém linh hoạt
hơn column not-null.

Domain phù hợp khi semantics thật sự giống nhau ở nhiều table. Không tạo domain
`generic_id` chỉ để đổi tên `bigint`; type đó không ngăn account ID bị gán vào
customer ID trong hầu hết SQL/application mapping.

Thay constraint/function của domain có thể cần kiểm tra mọi value và ảnh hưởng
deployment. Reuse contract cũng tạo coupling.

---

## 24. Composite type không thay table constraint

Mỗi table tự có row/composite type tương ứng; cũng có thể tạo:

```sql
CREATE TYPE app.postal_address AS (
    line1 text,
    city text,
    postal_code text,
    country_code text
);
```

Composite type hữu ích cho function parameter/result hoặc cấu trúc SQL. Nhưng
constraint của table không đi theo composite value ở ngoài table, và field bên
trong có thể null. Với dữ liệu cần query/index/FK/lifecycle độc lập, table riêng
thường rõ hơn.

Không biến mọi value object trong Java thành composite type. Đánh giá driver
mapping, migration coupling và query shape trước.

---

## 25. Array: tốt cho collection nhỏ, nguyên tử

```sql
CREATE TABLE app.articles (
    article_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tags text[] NOT NULL DEFAULT ARRAY[]::text[],
    CONSTRAINT articles_tags_count_ck
        CHECK (cardinality(tags) <= 20),
    CONSTRAINT articles_tags_no_null_ck
        CHECK (array_position(tags, NULL) IS NULL)
);

SELECT *
FROM app.articles
WHERE tags @> ARRAY['postgresql'];
```

Array hợp khi:

- collection nhỏ thuộc nguyên tử cùng row;
- không cần FK/metadata/quyền/vòng đời riêng cho từng phần tử;
- update cả collection là semantics chấp nhận được.

Dùng join table khi element cần uniqueness toàn cục, FK, query/aggregate thường
xuyên row hoặc update độc lập.

Khai báo `integer[3][3]` chỉ là documentation: PostgreSQL hiện không enforce kích
thước hay số chiều được khai báo. Nếu đó là invariant, thêm `CHECK` với
`array_length`/`array_ndims`.

Array giữ thứ tự và duplicate. Operator containment không phải set model hoàn
chỉnh; đừng dùng array để giấu many-to-many relationship quan trọng.

---

## 26. `json` và `jsonb`

| Đặc tính | `json` | `jsonb` |
|---|---|---|
| Lưu | nguyên text input | binary decomposition |
| Giữ whitespace/key order | có | không |
| Duplicate key | giữ input; xử lý thường lấy cuối | chỉ giữ key cuối |
| Xử lý/query | phải parse lại | hiệu quả hơn |
| GIN index | không | có |

Phần lớn application nên chọn `jsonb`. Chọn `json` khi cần bảo toàn biểu diễn gốc
như whitespace/key order vì contract legacy; nếu cần chữ ký byte-for-byte, cân
nhắc lưu payload gốc riêng.

SQL `NULL` khác JSON `null`:

```sql
SELECT
    NULL::jsonb IS NULL AS sql_null,
    'null'::jsonb IS NULL AS json_null_is_not_sql_null,
    jsonb_typeof('null'::jsonb) AS json_type;
```

JSONB không phải “schema-less”; nó chỉ chuyển schema enforcement sang application,
constraint hoặc consumer.

---

## 27. Relational + JSONB thay vì một cực

Pattern hybrid:

```sql
CREATE TABLE app.catalog_items (
    item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku text NOT NULL UNIQUE,
    price numeric(19, 4) NOT NULL,
    currency text NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT catalog_items_price_ck CHECK (price >= 0),
    CONSTRAINT catalog_items_currency_ck
        CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT catalog_items_attributes_ck
        CHECK (jsonb_typeof(attributes) = 'object'),
    CONSTRAINT catalog_items_no_duplicate_core_fields_ck
        CHECK (
            NOT attributes ? 'sku'
            AND NOT attributes ? 'price'
            AND NOT attributes ? 'currency'
        )
);
```

Đưa ra column typed khi field:

- là identity/FK/constraint quan trọng;
- xuất hiện thường xuyên trong filter/join/order/group;
- cần thống kê planner rõ;
- có lifecycle và migration contract ổn định.

Giữ trong JSONB khi field:

- sparse/variable theo product/source;
- được đọc như một document nguyên tử;
- chưa đủ ổn định để thành core contract;
- không cần referential integrity.

Một JSON document lớn vẫn là một row: update khóa row và tạo row version mới. Hai
writer sửa hai key khác nhau vẫn có thể tranh chấp/lost update nếu workflow không
được thiết kế.

---

## 28. JSONB operator và index phải theo query

```sql
SELECT item_id, sku
FROM app.catalog_items
WHERE attributes @> '{"color": "blue"}'::jsonb;
```

Default `jsonb_ops` hỗ trợ `?`, `?|`, `?&`, `@>`, `@?`, `@@`:

```sql
CREATE INDEX catalog_items_attributes_gin
    ON app.catalog_items
    USING gin (attributes);
```

`jsonb_path_ops` chỉ hỗ trợ `@>`, `@?`, `@@`, thường nhỏ và specific hơn cho
containment/path:

```sql
CREATE INDEX catalog_items_attributes_path_gin
    ON app.catalog_items
    USING gin (attributes jsonb_path_ops);
```

Không tạo cả hai theo thói quen. Chọn từ operator thật, cardinality, write cost và
`EXPLAIN`.

Nếu chỉ query một path nóng, expression index có thể gọn hơn:

```sql
CREATE INDEX catalog_items_brand_idx
    ON app.catalog_items ((attributes ->> 'brand'));
```

Extraction operator trả SQL `NULL` khi path/shape không khớp, nên query phải phân
biệt missing, JSON null và giá trị sai type khi domain cần.

---

## 29. Generated column trong PostgreSQL 18

Generated column luôn được tính từ column khác:

```sql
CREATE TABLE app.invoice_lines (
    invoice_line_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    quantity numeric(19, 4) NOT NULL,
    unit_price numeric(19, 4) NOT NULL,
    line_total numeric(19, 4)
        GENERATED ALWAYS AS (quantity * unit_price) STORED,
    CONSTRAINT invoice_lines_quantity_ck CHECK (quantity > 0),
    CONSTRAINT invoice_lines_unit_price_ck CHECK (unit_price >= 0)
);
```

PostgreSQL 18 có hai loại:

- `VIRTUAL`: tính khi đọc, không chiếm storage;
- `STORED`: tính khi insert/update và lưu như column.

Trong PostgreSQL 18, nếu không ghi rõ thì generated column mặc định là
`VIRTUAL`; đây là thay đổi quan trọng khi đọc DDL cũ/mới. Nên ghi explicit để
intent rõ.

Generation expression:

- chỉ dùng immutable function;
- không có subquery và chỉ tham chiếu current row;
- không tham chiếu generated column khác;
- không đồng thời có default/identity;
- virtual column còn bị giới hạn với user-defined type/function.

Default tính một lần khi insert và có thể override; generated value đổi theo base
column và không được ghi trực tiếp. Generated column không thay aggregate xuyên
row; dùng query/materialized view/summary design cho bài toán đó.

---

## 30. TOAST không biến row lớn thành miễn phí

`text`, `bytea`, JSONB và array lớn có thể được nén/đẩy sang TOAST như mô tả ở
[Architecture §11](architecture_storage.md). Nhưng:

- đọc field lớn có detoast/decompression cost;
- update row tạo version mới, có thể làm WAL/bloat tăng;
- JSONB update logic vẫn khóa toàn row;
- `SELECT *` vô tình kéo payload không cần;
- giới hạn row/document hợp lý vẫn cần ở domain/API.

File/object lớn thường phù hợp object storage, còn PostgreSQL giữ metadata, hash,
size, ownership và lifecycle state. `bytea` hợp khi transaction atomicity và kích
thước nhỏ/vừa quan trọng hơn streaming/CDN.

---

## 31. Schema evolution theo expand–migrate–contract

Không đổi producer và consumer cùng một khoảnh khắc. Mẫu an toàn:

```text
1. Expand   thêm cấu trúc tương thích ngược
2. Deploy   code đọc/ghi được cả cũ và mới
3. Migrate  backfill theo batch, đo progress và replication lag
4. Switch   chuyển read path, quan sát
5. Contract bỏ cấu trúc cũ khi không còn consumer
```

Ví dụ đổi `full_name` thành hai column:

```sql
ALTER TABLE app.customers
    ADD COLUMN given_name text,
    ADD COLUMN family_name text;
```

Sau đó application dual-read/dual-write có thời hạn, backfill bằng batch nhỏ,
đo row còn thiếu, rồi mới đặt constraint và xóa column cũ ở release sau.

Dual-write ở application có thể lệch khi một write fail. Nếu dùng trigger tạm để
đồng bộ, phải document owner, chiều dữ liệu chuẩn và ngày gỡ trigger.

---

## 32. Thêm column/default không downtime tuyệt đối

Từ PostgreSQL 11, thêm column với constant default thường không rewrite từng row;
giá trị được lưu trong catalog cho row cũ. Nhưng DDL vẫn cần lock và có thể chờ
sau transaction dài:

```sql
SET lock_timeout = '2s';

ALTER TABLE app.orders
    ADD COLUMN source text NOT NULL DEFAULT 'web';

RESET lock_timeout;
```

Lưu ý:

- lock acquisition fail nhanh tốt hơn chờ và tạo hàng dài blocking;
- volatile default có thể buộc tính cho từng row/rewrite;
- default đúng về kỹ thuật chưa chắc đúng cho dữ liệu lịch sử;
- table rewrite cần disk, WAL, replica capacity và maintenance plan;
- thử trên bản sao có volume/phân bố dữ liệu gần production.

Không tuyên bố “online DDL” chỉ vì câu lệnh chạy nhanh trên table dev.

---

## 33. Thêm constraint theo hai giai đoạn

Với table lớn, `NOT VALID` bỏ qua scan dữ liệu cũ nhưng vẫn chặn vi phạm mới:

```sql
ALTER TABLE app.orders
    ADD CONSTRAINT orders_source_ck
    CHECK (source IN ('web', 'mobile', 'partner'))
    NOT VALID;

ALTER TABLE app.orders
    VALIDATE CONSTRAINT orders_source_ck;
```

Trong PostgreSQL 18, `NOT VALID` dùng được cho foreign key, `CHECK` và not-null
constraint. `VALIDATE CONSTRAINT` scan row cũ với lock nhẹ hơn việc add và validate
ngay; nó không loại bỏ hoàn toàn I/O/load.

Pattern tương thích tốt để chuyển nullable thành not-null:

```sql
ALTER TABLE app.orders
    ADD CONSTRAINT orders_source_nn_ck
    CHECK (source IS NOT NULL)
    NOT VALID;

ALTER TABLE app.orders
    VALIDATE CONSTRAINT orders_source_nn_ck;

ALTER TABLE app.orders
    ALTER COLUMN source SET NOT NULL;

ALTER TABLE app.orders
    DROP CONSTRAINT orders_source_nn_ck;
```

Khi `CHECK` hợp lệ đã chứng minh không có null, PostgreSQL có thể bỏ qua table
scan cho `SET NOT NULL`. Vẫn cần cửa sổ lock acquisition và rehearsal.

Foreign key:

```sql
ALTER TABLE app.orders
    ADD CONSTRAINT orders_sales_channel_fk
    FOREIGN KEY (sales_channel_id)
    REFERENCES app.sales_channels (sales_channel_id)
    NOT VALID;

ALTER TABLE app.orders
    VALIDATE CONSTRAINT orders_sales_channel_fk;
```

Ví dụ giả định các column/table đã được expand trước.

---

## 34. Thêm unique constraint cho table lớn

`UNIQUE NOT VALID` không phải pattern tương ứng. Có thể xây unique index
concurrently rồi attach:

```sql
CREATE UNIQUE INDEX CONCURRENTLY orders_partner_reference_uidx
    ON app.orders (partner_id, partner_reference);
```

Lệnh `CREATE INDEX CONCURRENTLY`:

- không chạy trong transaction block;
- chạy lâu hơn và có nhiều phase;
- khi fail có thể để lại invalid index cần kiểm tra/xử lý;
- vẫn dùng CPU/I/O và chờ transaction cũ ở một số phase.

Khi index hợp lệ:

```sql
ALTER TABLE app.orders
    ADD CONSTRAINT orders_partner_reference_uk
    UNIQUE USING INDEX orders_partner_reference_uidx;
```

Ví dụ giả định column đã tồn tại và dữ liệu duplicate đã được xử lý. Với
partitioned table có restriction riêng; không copy pattern mà không kiểm tra
phiên bản/layout.

---

## 35. Đổi type có thể là table rewrite

Câu ngắn:

```sql
ALTER TABLE app.orders
    ALTER COLUMN external_id TYPE bigint
    USING external_id::bigint;
```

có thể scan/rewrite table, giữ lock lâu, tạo WAL và fail giữa chừng vì value bẩn.

Với table lớn:

1. thêm shadow column type mới;
2. code ghi được cả hai hoặc trigger tạm có kiểm soát;
3. backfill theo primary-key range/batch;
4. kiểm tra parse error, null, count và checksum business;
5. thêm/validate constraint và index mới;
6. chuyển read path;
7. contract column cũ ở release sau.

Trước migration, tìm dữ liệu không cast được:

```sql
SELECT external_id
FROM app.orders
WHERE external_id IS NOT NULL
  AND external_id !~ '^[0-9]+$'
LIMIT 100;
```

Regex chỉ là bước lọc ví dụ; vẫn phải kiểm tra overflow và domain. Không backfill
toàn table trong một transaction khổng lồ vì giữ snapshot/lock, tạo WAL burst và
làm replica lag.

---

## 36. Audit schema bằng catalog

Liệt kê column/default/identity/generated:

```sql
SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    data_type,
    is_nullable,
    column_default,
    is_identity,
    is_generated,
    generation_expression
FROM information_schema.columns
WHERE table_schema = 'app'
ORDER BY table_name, ordinal_position;
```

Liệt kê constraint bằng định nghĩa PostgreSQL:

```sql
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype,
    con.convalidated,
    pg_get_constraintdef(con.oid, true) AS definition
FROM pg_constraint AS con
JOIN pg_class AS c ON c.oid = con.conrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'app'
ORDER BY c.relname, con.conname;
```

Tìm constraint chưa validate:

```sql
SELECT
    conrelid::regclass AS table_name,
    conname,
    pg_get_constraintdef(oid, true) AS definition
FROM pg_constraint
WHERE NOT convalidated
ORDER BY conrelid::regclass::text, conname;
```

Catalog là implementation API của PostgreSQL; monitoring/tooling theo nhiều
version phải test compatibility. `information_schema` portable hơn nhưng không
phơi bày mọi feature PostgreSQL.

---

## 37. Decision matrix

| Nhu cầu | Chọn trước | Tránh mặc định |
|---|---|---|
| internal OLTP key | `bigint identity` | `max(id)+1` |
| distributed/public ID | UUID v7 hoặc v4 theo leakage/locality | UUID như secret |
| tiền | `numeric` hoặc minor unit + currency | float, implicit currency |
| event instant | `timestamptz` | local `timestamp` không zone |
| local schedule | local timestamp/time + IANA zone | chỉ UTC offset |
| variable attributes | JSONB hybrid | nhét core relation vào JSON |
| collection nhỏ nguyên tử | array | array thay many-to-many |
| khoảng hiệu lực | range `[)` | tự trừ microsecond |
| không overlap | `EXCLUDE` | check-then-insert không lock |
| state ổn định dùng lại | enum/domain tùy semantics | enum cho workflow đổi liên tục |
| reusable scalar rule | domain | domain cho mọi alias kỹ thuật |
| derived trong một row | generated column | trigger không cần thiết |
| cross-row identity | PK/UNIQUE | `CHECK` đọc table |

---

## 38. Failure modes thường gặp

### “Cứ để `text`, application validate”

Một writer bỏ validation sẽ tạo dữ liệu không sửa được dễ dàng. Dùng type và
constraint cho invariant ổn định; application vẫn validate để trả lỗi đẹp.

### “Cứ để JSONB cho linh hoạt”

Core field mất FK/statistics/type contract, query đầy cast/path và migration bị
đẩy sang runtime. Dùng relational + JSONB hybrid.

### “Có default rồi nên column không null”

Explicit null vẫn null nếu không có `NOT NULL`. Default và nullability là hai
contract khác nhau.

### “Unique email tự xử lý case”

Equality phụ thuộc collation/expression. Xác định normalization và enforce bằng
unique index/constraint tương ứng.

### “Sequence phải liên tục”

Rollback/cache/crash tạo gap. Nếu gap-free là luật, thiết kế ledger/allocator có
serialization, audit và throughput trade-off riêng.

### “FK tự có đủ index”

Referenced key có index; child referencing column không tự có. Delete/update
parent có thể scan child.

### “SELECT thấy trống rồi INSERT”

Hai transaction cùng thấy trống. Dùng UNIQUE/EXCLUDE hoặc transaction/lock phù
hợp, sau đó xử lý constraint violation.

### “Đổi type chỉ là metadata”

Nhiều conversion rewrite table, tạo WAL và giữ lock. Đo trên dữ liệu thật và dùng
expand–migrate–contract khi cần.

---

## 39. Checklist review data model

### Identity và relationship

- [ ] Mỗi table có identity/business key rõ?
- [ ] Surrogate key đi cùng unique business key khi cần?
- [ ] Tenant boundary có nằm trong PK/FK/UNIQUE phù hợp?
- [ ] Child FK có index theo query/delete path?
- [ ] `CASCADE` có blast radius và runbook rõ?

### Type và semantics

- [ ] Tiền có amount, currency và rounding contract?
- [ ] Event time dùng `timestamptz`; local schedule giữ IANA zone?
- [ ] `NULL` có nghĩa rõ, không dùng thay mọi trạng thái?
- [ ] Precision/scale/đơn vị nằm trong tên hoặc constraint?
- [ ] UUID/ID không bị dùng như credential?

### Constraint

- [ ] Core invariant nằm trong database?
- [ ] `CHECK` không đọc row/table khác và xử lý null đúng?
- [ ] Unique nullable có cần `NULLS NOT DISTINCT`?
- [ ] Không có index trùng với PK/UNIQUE?
- [ ] Constraint/domain function thực sự immutable?

### Flexible type

- [ ] Array/JSONB là collection/document nguyên tử, không che relation?
- [ ] JSONB core field đã được nâng thành typed column?
- [ ] JSONB index khớp operator thật?
- [ ] Document/array có size/cardinality boundary?
- [ ] Generated expression dùng immutable function và loại `VIRTUAL`/`STORED`
      được ghi explicit?

### Migration

- [ ] DDL có `lock_timeout`, rehearsal và rollback/roll-forward plan?
- [ ] Backfill theo batch và đo WAL/replica lag?
- [ ] Constraint lớn dùng add-not-valid rồi validate khi phù hợp?
- [ ] Unique index lớn dùng concurrent build và kiểm tra invalid index?
- [ ] Contract phase chỉ chạy sau khi mọi consumer cũ đã rời?

---

## 40. Câu hỏi phỏng vấn

1. Database và schema khác nhau thế nào trong PostgreSQL?
2. Vì sao schema writable trong `search_path` là rủi ro bảo mật?
3. Natural key và surrogate key nên phối hợp ra sao?
4. Identity khác `serial` thế nào và vì sao sequence có gap?
5. UUID v4/v7/`bigint` đánh đổi locality, size và information leakage ra sao?
6. Vì sao không dùng floating point cho tiền?
7. `timestamp` và `timestamptz` khác nhau về semantics gì?
8. Vì sao `CHECK (price > 0)` vẫn cho phép null?
9. UNIQUE xử lý null thế nào và `NULLS NOT DISTINCT` thay đổi gì?
10. Vì sao PostgreSQL không tự tạo index cho child FK?
11. Khi nào `ON DELETE CASCADE` nguy hiểm?
12. Exclusion constraint giải quyết booking overlap race ra sao?
13. Enum, lookup table, `CHECK` và domain phù hợp trường hợp nào?
14. Khi nào array tốt hơn join table?
15. `json` và `jsonb` khác nhau về lưu trữ/index ra sao?
16. `jsonb_ops` và `jsonb_path_ops` đánh đổi gì?
17. Generated column khác default thế nào trong PostgreSQL 18?
18. `NOT VALID` + `VALIDATE CONSTRAINT` giảm tác động deployment ra sao?
19. Vì sao add constant default nhanh vẫn không có nghĩa zero downtime?
20. Expand–migrate–contract dùng thế nào khi đổi type table lớn?

---

## 41. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [PostgreSQL 18 data types](https://www.postgresql.org/docs/18/datatype.html)
- [Numeric types](https://www.postgresql.org/docs/18/datatype-numeric.html)
- [Monetary type](https://www.postgresql.org/docs/18/datatype-money.html)
- [Date/time types](https://www.postgresql.org/docs/18/datatype-datetime.html)
- [UUID functions](https://www.postgresql.org/docs/18/functions-uuid.html)
- [Schemas và search path](https://www.postgresql.org/docs/18/ddl-schemas.html)
- [Identity columns](https://www.postgresql.org/docs/18/ddl-identity-columns.html)
- [Generated columns](https://www.postgresql.org/docs/18/ddl-generated-columns.html)
- [Constraints](https://www.postgresql.org/docs/18/ddl-constraints.html)
- [Arrays](https://www.postgresql.org/docs/18/arrays.html)
- [Range types](https://www.postgresql.org/docs/18/rangetypes.html)
- [Domain types](https://www.postgresql.org/docs/18/domains.html)
- [JSON types và GIN indexing](https://www.postgresql.org/docs/18/datatype-json.html)
- [Collation support](https://www.postgresql.org/docs/18/collation.html)
- [ALTER TABLE](https://www.postgresql.org/docs/18/sql-altertable.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

Học tiếp:

1. [Transactions, MVCC & Locking](transactions_mvcc.md).
2. [Indexing & Query Planner](indexing_planner.md).
3. [Advanced SQL](advanced_sql.md).

---

*Cập nhật lần cuối: 2026-07-31.*
