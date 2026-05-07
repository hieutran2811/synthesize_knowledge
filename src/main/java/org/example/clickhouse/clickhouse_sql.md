# ClickHouse SQL & Data Types

## Mục lục
1. [Data Types Đặc Trưng](#1-data-types-đặc-trưng)
2. [Arrays – Mảng](#2-arrays--mảng)
3. [Maps & Tuples & Nested](#3-maps--tuples--nested)
4. [JSON Handling](#4-json-handling)
5. [Window Functions](#5-window-functions)
6. [CTEs & Subqueries](#6-ctes--subqueries)
7. [JOIN Types & Algorithms](#7-join-types--algorithms)
8. [Advanced GROUP BY](#8-advanced-group-by)
9. [SAMPLE – Approximate Queries](#9-sample--approximate-queries)
10. [Useful Functions](#10-useful-functions)

---

## 1. Data Types Đặc Trưng

### 1.1 LowCardinality – Dictionary Encoding

```sql
-- LowCardinality: ideal for columns với < 10,000 unique values
-- Internally: dictionary + index array → 3-10x better compression
-- Query speed: faster comparisons (integer vs string)

CREATE TABLE events (
    -- Good candidates for LowCardinality:
    event_type    LowCardinality(String),    -- 'page_view', 'click', etc.
    country       LowCardinality(String),    -- 200 countries
    browser       LowCardinality(String),    -- 20 browsers
    status        LowCardinality(FixedString(10)),
    
    -- NOT good (high cardinality):
    user_id       UInt64,        -- millions of users → overhead
    session_id    String,        -- unique per session → wasteful
    email         String         -- unique → use String
)
ENGINE = MergeTree()
ORDER BY event_type;

-- Check cardinality before deciding:
SELECT uniq(event_type) FROM events;  -- if < 10000 → LowCardinality good
```

### 1.2 Nullable – Use Sparingly

```sql
-- Nullable wraps every value with an extra bit for NULL tracking
-- 2 files on disk: .bin (values) + .null.bin (null mask)
-- ~30% performance overhead → avoid when possible

-- Prefer default values over Nullable:
CREATE TABLE metrics (
    metric_name  LowCardinality(String),
    value        Float64,
    tags         Map(String, String),
    -- BAD:
    description  Nullable(String),          -- overhead
    -- GOOD:
    description  String DEFAULT '',         -- empty string instead of NULL
    optional_val Float64 DEFAULT 0,
    -- Only use Nullable when NULL has semantic meaning:
    deleted_at   Nullable(DateTime)         -- NULL = not deleted (meaningful)
)
ENGINE = MergeTree()
ORDER BY metric_name;

-- Check if NULL exists:
SELECT count() FROM metrics WHERE isNull(deleted_at);
SELECT count() FROM metrics WHERE isNotNull(deleted_at);
SELECT ifNull(description, 'N/A') FROM metrics;
SELECT coalesce(deleted_at, now()) FROM metrics;
```

### 1.3 Numeric Types

```sql
-- Integer: UInt8/16/32/64/128/256, Int8/16/32/64/128/256
-- Float:   Float32 (4B), Float64 (8B) — imprecise for money!
-- Decimal: Decimal(precision, scale) — for money, exact
-- Special: UInt8 for boolean (0/1), UInt16 for year, UInt32 for IPv4

-- Decimal for financial data:
CREATE TABLE transactions (
    tx_id    UInt64,
    amount   Decimal(18, 4),   -- up to 99999999999999.9999
    fee      Decimal(10, 8),   -- high precision for crypto
    rate     Decimal(8, 6)
)
ENGINE = MergeTree() ORDER BY tx_id;

-- IPv4 / IPv6 native types:
CREATE TABLE access_log (
    ts       DateTime,
    ip       IPv4,             -- stored as UInt32
    ip6      IPv6,             -- stored as FixedString(16)
    domain   String
)
ENGINE = MergeTree() ORDER BY ts;

INSERT INTO access_log VALUES (now(), '192.168.1.1', '::1', 'example.com');
SELECT IPv4NumToString(ip), ip6 FROM access_log;
```

### 1.4 Date/Time Types

```sql
-- Date:      16-bit days since 1970-01-01 (up to 2149-06-06)
-- Date32:    32-bit days (wider range)
-- DateTime:  32-bit unix timestamp, 1-second resolution
-- DateTime64(3):  milliseconds; (6): microseconds; (9): nanoseconds

CREATE TABLE time_events (
    day         Date,
    ts          DateTime('Asia/Ho_Chi_Minh'),    -- timezone-aware
    ts_ms       DateTime64(3, 'UTC'),             -- millisecond precision
    ts_us       DateTime64(6)                     -- microsecond
)
ENGINE = MergeTree() ORDER BY ts;

-- Time functions:
SELECT
    now(),
    today(),
    yesterday(),
    toStartOfHour(ts),
    toStartOfDay(ts),
    toStartOfWeek(ts, 1),    -- 1=Monday as first day
    toStartOfMonth(ts),
    toStartOfQuarter(ts),
    toStartOfYear(ts),
    dateDiff('hour', ts1, ts2),
    toUnixTimestamp(ts),
    toDateTime(1704067200),
    formatDateTime(ts, '%Y-%m-%d %H:%M:%S'),
    -- DateTime64 only:
    toDateTime64(ts_ms, 3),
    toUnixTimestamp64Milli(ts_ms);
```

---

## 2. Arrays – Mảng

```sql
-- Arrays: variable-length, same-type elements
CREATE TABLE product_events (
    user_id    UInt64,
    event_time DateTime,
    product_ids Array(UInt32),        -- array of IDs
    tags        Array(LowCardinality(String)),
    scores      Array(Float32)
)
ENGINE = MergeTree() ORDER BY (user_id, event_time);

INSERT INTO product_events VALUES
    (1, now(), [101, 102, 103], ['sale', 'featured'], [4.5, 3.8, 5.0]),
    (2, now(), [101, 200],      ['new'],               [4.0, 4.2]);

-- ── Array creation ────────────────────────────────────────────────────────
SELECT
    [1, 2, 3]                              AS literal,
    array(1, 2, 3)                         AS fn,
    arrayWithConstant(5, 0)                AS zeros,    -- [0,0,0,0,0]
    range(1, 6)                            AS range_arr; -- [1,2,3,4,5]

-- ── Array access ──────────────────────────────────────────────────────────
SELECT
    product_ids[1]                         AS first,    -- 1-indexed!
    length(product_ids)                    AS cnt,
    has(product_ids, 101)                  AS has_101,
    hasAll(product_ids, [101, 102])        AS has_both,
    hasAny(product_ids, [101, 999])        AS has_any,
    indexOf(product_ids, 102)              AS idx,      -- 0 if not found
    arrayElement(product_ids, 2)           AS second
FROM product_events;

-- ── Array transformations ─────────────────────────────────────────────────
SELECT
    arrayMap(x -> x * 2, scores)          AS doubled,
    arrayFilter(x -> x > 4.0, scores)     AS high_scores,
    arraySort(scores)                      AS sorted,
    arraySortBy(x -> -x, scores)           AS sorted_desc,
    arrayReverse(product_ids)              AS reversed,
    arraySlice(product_ids, 1, 2)          AS first_two,
    arrayPushBack(tags, 'hot')             AS with_hot,
    arrayConcat([1,2], [3,4])              AS merged,
    arrayDistinct(product_ids)             AS unique,
    arrayIntersect([1,2,3], [2,3,4])       AS intersect, -- [2,3]
    arrayPopBack(scores)                   AS without_last;

-- ── Array aggregation ─────────────────────────────────────────────────────
SELECT
    user_id,
    groupArray(product_ids[1])             AS first_products,   -- aggregate into array
    groupArraySample(5, user_id)(product_ids[1]) AS sample_5,
    arrayFlatten([product_ids])            AS flat              -- flatten nested
FROM product_events
GROUP BY user_id;

-- ── arrayJoin – unnest / explode ─────────────────────────────────────────
SELECT
    user_id,
    arrayJoin(product_ids) AS product_id   -- one row per element
FROM product_events;

-- arrayJoin equivalent with ARRAY JOIN syntax (more readable):
SELECT user_id, product_id
FROM product_events
ARRAY JOIN product_ids AS product_id;

-- ARRAY JOIN with multiple arrays (must be same length):
SELECT user_id, product_id, score
FROM product_events
ARRAY JOIN
    product_ids AS product_id,
    scores AS score;

-- LEFT ARRAY JOIN: keep rows even if array is empty:
SELECT user_id, product_id
FROM product_events
LEFT ARRAY JOIN product_ids AS product_id;

-- ── Array reduce ─────────────────────────────────────────────────────────
SELECT
    arraySum(scores)                        AS total,
    arrayMin(scores)                        AS min_score,
    arrayMax(scores)                        AS max_score,
    arrayAvg(scores)                        AS avg_score,
    arrayReduce('sum', scores)              AS reduce_sum,
    arrayFold(s, x -> s + x, 0, scores)    AS manual_fold;
```

---

## 3. Maps & Tuples & Nested

### 3.1 Map

```sql
CREATE TABLE user_props (
    user_id    UInt64,
    attributes Map(String, String),     -- key-value pairs
    counters   Map(String, UInt64)
)
ENGINE = MergeTree() ORDER BY user_id;

INSERT INTO user_props VALUES
    (1, {'country': 'VN', 'tier': 'gold', 'language': 'vi'}, {'logins': 150, 'orders': 23}),
    (2, {'country': 'US', 'tier': 'silver'},                  {'logins': 45});

-- Map access:
SELECT
    user_id,
    attributes['country']                    AS country,       -- '' if missing
    attributes['tier']                        AS tier,
    mapKeys(attributes)                       AS keys,
    mapValues(attributes)                     AS values,
    mapContains(attributes, 'language')       AS has_lang,
    mapAdd(counters, map('sessions', 1))      AS updated_counters
FROM user_props;

-- Map aggregation (collect into map):
SELECT
    groupByKey([(event_type, count())])  -- aggregate events into map
FROM events_raw
GROUP BY user_id;
```

### 3.2 Tuple

```sql
-- Tuple: fixed structure, can have different types
CREATE TABLE geo_events (
    user_id   UInt64,
    location  Tuple(lat Float64, lng Float64),  -- named tuple
    bounds    Tuple(Float64, Float64, Float64, Float64)  -- unnamed
)
ENGINE = MergeTree() ORDER BY user_id;

INSERT INTO geo_events VALUES
    (1, (10.762622, 106.660172), (10.0, 106.0, 11.0, 107.0));

SELECT
    user_id,
    location.lat,           -- named field access
    location.lng,
    tupleElement(bounds, 1) AS min_lat,
    tupleToNameValuePairs(location) AS pairs,
    untuple(location)       AS (lat, lng)  -- destructure
FROM geo_events;
```

### 3.3 Nested

```sql
-- Nested: array of structs (stored as separate arrays per column)
CREATE TABLE orders (
    order_id UInt64,
    customer_id UInt64,
    items Nested(
        product_id  UInt32,
        quantity    UInt16,
        price       Decimal(10, 2),
        category    LowCardinality(String)
    )
)
ENGINE = MergeTree() ORDER BY order_id;

-- Insert with arrays of same length:
INSERT INTO orders VALUES
    (1, 100, [101, 102, 103], [2, 1, 3], [29.99, 49.99, 9.99], ['electronics', 'clothing', 'food']);

-- Access as separate arrays:
SELECT
    order_id,
    items.product_id,       -- Array(UInt32)
    items.price,            -- Array(Decimal)
    length(items.product_id) AS item_count
FROM orders;

-- ARRAY JOIN Nested:
SELECT order_id, product_id, quantity, price
FROM orders
ARRAY JOIN items;
```

---

## 4. JSON Handling

### 4.1 JSONExtract Functions

```sql
-- Raw JSON stored as String
CREATE TABLE raw_events (
    id          UInt64,
    event_time  DateTime,
    payload     String   -- '{"user_id": 123, "action": "click", "meta": {...}}'
)
ENGINE = MergeTree() ORDER BY (event_time, id);

-- Extract individual fields:
SELECT
    JSONExtractUInt(payload, 'user_id')              AS user_id,
    JSONExtractString(payload, 'action')             AS action,
    JSONExtractFloat(payload, 'revenue')             AS revenue,
    JSONExtractBool(payload, 'is_mobile')            AS is_mobile,
    JSONExtractRaw(payload, 'meta')                  AS meta_json,   -- raw JSON string
    JSONExtractString(payload, 'meta', 'browser')    AS browser,     -- nested path
    JSONExtractKeys(payload)                         AS keys,        -- all keys
    JSON_VALUE(payload, '$.meta.browser')            AS browser_alt; -- JSONPath

-- Extract into typed value:
SELECT JSONExtractInt(payload, 'score') * 2 AS doubled_score
FROM raw_events;

-- Check JSON validity:
SELECT isValidJSON('{"key": "value"}');      -- 1
SELECT isValidJSON('{bad json}');             -- 0
```

### 4.2 JSON Data Type (v22.6+)

```sql
-- Native JSON type: stores as column tree internally
-- No need to parse at query time → MUCH faster

CREATE TABLE events_json (
    id         UInt64,
    ts         DateTime,
    data       JSON   -- native JSON column (experimental)
)
ENGINE = MergeTree() ORDER BY (ts, id)
SETTINGS allow_experimental_object_type = 1;

INSERT INTO events_json FORMAT JSONEachRow
{"id": 1, "ts": "2024-01-01 10:00:00", "data": {"user_id": 123, "action": "click", "meta": {"browser": "Chrome"}}}
{"id": 2, "ts": "2024-01-01 10:01:00", "data": {"user_id": 456, "action": "view",  "meta": {"browser": "Firefox", "mobile": true}}}

-- Access like struct:
SELECT
    data.user_id,
    data.action,
    data.meta.browser,
    data.meta.mobile    -- NULL if not in all rows
FROM events_json;
```

---

## 5. Window Functions

```sql
-- Window functions: available since ClickHouse 21.1
-- Syntax same as standard SQL

CREATE TABLE daily_revenue (
    tenant_id   UInt32,
    date        Date,
    category    String,
    revenue     Decimal(18, 2)
)
ENGINE = MergeTree() ORDER BY (tenant_id, date, category);

-- ── Ranking ───────────────────────────────────────────────────────────────
SELECT
    tenant_id,
    date,
    category,
    revenue,
    row_number() OVER w                           AS row_num,
    rank()        OVER w                           AS rank,
    dense_rank()  OVER w                           AS dense_rank,
    ntile(4)      OVER w                           AS quartile,
    -- % from top:
    percent_rank() OVER w                          AS pct_rank
FROM daily_revenue
WINDOW w AS (PARTITION BY tenant_id, date ORDER BY revenue DESC);

-- ── Running totals & Moving averages ─────────────────────────────────────
SELECT
    date,
    category,
    revenue,
    sum(revenue) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total,
    avg(revenue) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moving_avg_7d,
    -- Lag/Lead:
    lagInFrame(revenue, 1, 0) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
    ) AS prev_day_revenue,
    leadInFrame(revenue, 1, 0) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
    ) AS next_day_revenue,
    -- Day-over-day growth:
    revenue / lagInFrame(revenue, 1, revenue) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
    ) - 1 AS dod_growth
FROM daily_revenue
WHERE tenant_id = 1;

-- ── First/Last value ──────────────────────────────────────────────────────
SELECT
    tenant_id,
    date,
    category,
    revenue,
    firstValueOrNull(revenue) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_day_revenue,
    lastValueOrNull(revenue) OVER (
        PARTITION BY tenant_id, category
        ORDER BY date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_day_revenue
FROM daily_revenue;
```

---

## 6. CTEs & Subqueries

```sql
-- CTEs: WITH clause (standard SQL compatible)
WITH
    -- Simple CTE
    daily_totals AS (
        SELECT
            tenant_id,
            date,
            sum(revenue) AS total_revenue,
            count()      AS events
        FROM daily_revenue
        WHERE date >= today() - 30
        GROUP BY tenant_id, date
    ),
    -- CTE referencing previous CTE
    tenant_stats AS (
        SELECT
            tenant_id,
            avg(total_revenue) AS avg_daily_revenue,
            max(total_revenue) AS peak_revenue
        FROM daily_totals
        GROUP BY tenant_id
    )
SELECT
    d.tenant_id,
    d.date,
    d.total_revenue,
    t.avg_daily_revenue,
    d.total_revenue / t.avg_daily_revenue AS relative_performance
FROM daily_totals d
JOIN tenant_stats t USING (tenant_id)
ORDER BY d.tenant_id, d.date;

-- Recursive CTE (v23.1+):
WITH RECURSIVE
    numbers AS (
        SELECT 1 AS n
        UNION ALL
        SELECT n + 1 FROM numbers WHERE n < 10
    )
SELECT n FROM numbers;
```

---

## 7. JOIN Types & Algorithms

### 7.1 JOIN Types

```sql
-- INNER JOIN (default)
SELECT e.user_id, u.name, count() AS events
FROM events_raw e
INNER JOIN users u ON e.user_id = u.user_id
GROUP BY e.user_id, u.name;

-- LEFT JOIN (keep all left rows)
SELECT u.user_id, u.name, count(e.event_id) AS events
FROM users u
LEFT JOIN events_raw e ON u.user_id = e.user_id AND e.event_time >= today() - 7
GROUP BY u.user_id, u.name;

-- CROSS JOIN (Cartesian)
SELECT a.tenant_id, b.date
FROM tenants a, dates b;

-- SEMI JOIN / ANTI JOIN
SELECT user_id FROM users
WHERE user_id IN (SELECT user_id FROM vip_users);  -- semi join

SELECT user_id FROM users
WHERE user_id NOT IN (SELECT user_id FROM banned_users);  -- anti join

-- ASOF JOIN: join on nearest row (time-series!)
-- Match each event to the most recent user_state that occurred BEFORE event
CREATE TABLE user_state_history (
    user_id    UInt64,
    state_time DateTime,
    tier       LowCardinality(String),
    score      UInt32
)
ENGINE = MergeTree()
ORDER BY (user_id, state_time);

SELECT
    e.user_id,
    e.event_time,
    e.event_type,
    u.tier,     -- tier AT TIME OF EVENT
    u.score
FROM events_raw e
ASOF JOIN user_state_history u
    ON e.user_id = u.user_id
    AND e.event_time >= u.state_time;  -- must have >= or <=

-- PASTE JOIN: zip two tables row by row (no key)
SELECT a.metric, b.value
FROM metrics_names a
PASTE JOIN metrics_values b;
```

### 7.2 JOIN Algorithms

```sql
-- ClickHouse join algorithms:
-- hash:        build hash table from right table (default for small right)
-- parallel_hash: parallel hash build (large right table)
-- sort_merge:  sort both sides then merge (good when both sorted)
-- full_sorting_merge: external sort for huge tables
-- direct:      O(1) lookup using dictionary (fastest when possible)

SELECT ...
FROM big_table
JOIN small_table ON ... USING (id)
SETTINGS join_algorithm = 'hash';

-- For large JOINs:
SET join_algorithm = 'parallel_hash';
SET max_memory_usage = 10000000000;  -- 10GB for hash table

-- Global JOIN (distributed queries): broadcast right table to all shards
SELECT ...
FROM distributed_events e
GLOBAL JOIN users u ON e.user_id = u.user_id;
-- Without GLOBAL: each shard joins with local data only → wrong results
-- With GLOBAL: right table sent to all shards → correct but more network
```

---

## 8. Advanced GROUP BY

```sql
-- ── ROLLUP – hierarchical subtotals ──────────────────────────────────────
SELECT
    tenant_id,
    category,
    sum(revenue) AS revenue
FROM daily_revenue
GROUP BY ROLLUP(tenant_id, category)
ORDER BY tenant_id NULLS LAST, category NULLS LAST;
-- Result:
-- tenant 1 | electronics | 500
-- tenant 1 | clothing    | 300
-- tenant 1 | NULL        | 800  ← subtotal for tenant 1
-- tenant 2 | electronics | 400
-- tenant 2 | NULL        | 400
-- NULL     | NULL        | 1200 ← grand total

-- ── CUBE – all combinations ───────────────────────────────────────────────
SELECT
    tenant_id,
    category,
    toYear(date) AS year,
    sum(revenue) AS revenue
FROM daily_revenue
GROUP BY CUBE(tenant_id, category, year);
-- Generates all 2^3 = 8 combinations of grouping

-- ── GROUPING SETS – explicit combinations ────────────────────────────────
SELECT
    tenant_id,
    category,
    date,
    sum(revenue) AS revenue
FROM daily_revenue
GROUP BY GROUPING SETS (
    (tenant_id, category, date),  -- most granular
    (tenant_id, category),        -- subtotal per tenant+category
    (tenant_id),                  -- subtotal per tenant
    ()                            -- grand total
);

-- GROUPING() to identify NULL rows:
SELECT
    grouping(tenant_id) AS is_total_tenant,
    grouping(category)  AS is_total_category,
    tenant_id,
    category,
    sum(revenue)
FROM daily_revenue
GROUP BY ROLLUP(tenant_id, category);

-- ── WITH TOTALS ───────────────────────────────────────────────────────────
SELECT category, sum(revenue)
FROM daily_revenue
GROUP BY category
WITH TOTALS;  -- extra row at end with grand total
-- Result:
-- electronics | 900
-- clothing    | 300
-- ─────────────────
-- (total row) | 1200
```

---

## 9. SAMPLE – Approximate Queries

```sql
-- SAMPLE: read a fraction of data → fast approximate queries
-- Requires SAMPLE BY in table definition

CREATE TABLE events_sampled (
    event_id   UInt64,
    user_id    UInt64,
    event_time DateTime
)
ENGINE = MergeTree()
ORDER BY (user_id, event_time)
SAMPLE BY intHash32(user_id);   -- sampling key

-- Sample 1% of data (consistent per user_id due to hash):
SELECT count() * 100 AS approx_total    -- multiply by 1/sample_rate
FROM events_sampled
SAMPLE 0.01;

-- Sample exactly 100,000 rows:
SELECT count()
FROM events_sampled
SAMPLE 100000;

-- Sample with offset (for reproducible splits):
SELECT count() FROM events_sampled SAMPLE 1/10 OFFSET 3/10;
-- Read 10% starting from 30th percentile

-- Approximate distinct count (hyperloglog):
SELECT uniqApprox(user_id) FROM events_sampled;  -- faster than uniq()

-- Quantile estimation:
SELECT quantileTDigest(0.95)(response_time) FROM events_sampled;
```

---

## 10. Useful Functions

```sql
-- ── Conditional ──────────────────────────────────────────────────────────
SELECT
    if(revenue > 0, 'paid', 'free')              AS tier,
    multiIf(
        revenue > 1000, 'enterprise',
        revenue > 100,  'pro',
        'free'
    )                                             AS plan,
    ifNull(nullable_col, 'default')              AS safe_col,
    nullIf(status, 'unknown')                    AS nullable_status,
    coalesce(first_name, last_name, 'Anonymous') AS display_name;

-- ── String ────────────────────────────────────────────────────────────────
SELECT
    lower('Hello World'),
    upper('hello'),
    trim('  hello  '),
    trimLeft('  hi'),
    concat('a', '-', 'b'),
    substring('hello world', 7, 5),    -- 'world'
    splitByChar(',', 'a,b,c'),         -- ['a','b','c']
    arrayStringConcat(['a','b','c'], '-'),  -- 'a-b-c'
    replaceAll('foo bar', ' ', '_'),
    match('hello@email.com', '^[^@]+@[^@]+$'),  -- regex match
    extract('version: 2.1.3', '(\\d+\\.\\d+)'), -- regex extract
    like('user-123', 'user-%'),
    ilike('User-123', 'user-%'),        -- case insensitive
    base64Encode('hello'),
    base64Decode('aGVsbG8='),
    length('hello'),                    -- bytes
    lengthUTF8('xin chào'),            -- unicode chars
    leftPad('5', 3, '0');              -- '005'

-- ── Math ──────────────────────────────────────────────────────────────────
SELECT
    round(3.14159, 2),
    floor(3.7),
    ceil(3.2),
    abs(-5),
    sqrt(16),
    pow(2, 10),
    log(100),
    log2(1024),
    greatest(1, 2, 3),
    least(1, 2, 3),
    intDiv(10, 3),           -- integer division = 3
    modulo(10, 3);           -- 10 % 3 = 1

-- ── Hash & ID ─────────────────────────────────────────────────────────────
SELECT
    generateUUIDv4(),
    toUUID('550e8400-e29b-41d4-a716-446655440000'),
    cityHash64('hello'),
    sipHash64('hello'),
    MD5('hello'),
    SHA256('hello'),
    xxHash64('hello'),
    farmFingerprint64('hello');

-- ── Aggregate specialties ─────────────────────────────────────────────────
SELECT
    -- Approximate:
    uniq(user_id),              -- fast HyperLogLog (~1% error)
    uniqExact(user_id),         -- exact (slower, more memory)
    uniqHLL12(user_id),         -- HLL with 12 bits
    quantile(0.95)(latency),    -- approximate quantile
    quantileExact(0.95)(latency), -- exact (sorts all data)
    quantileTDigest(0.99)(latency), -- t-digest algorithm
    topK(10)(event_type),       -- top-K approximate
    topKWeighted(10)(event_type, revenue),  -- weighted top-K

    -- Conditional:
    countIf(status = 'error')                AS error_count,
    sumIf(revenue, is_paid = 1)              AS paid_revenue,
    avgIf(latency, success = 1)              AS avg_success_latency,
    groupArrayIf(10)(user_id, vip = 1)       AS sample_vip_users,

    -- Statistical:
    corr(x, y),
    covarPop(x, y),
    varPop(x),
    stddevPop(x),
    skewPop(x),
    kurtPop(x)
FROM events_raw;

-- ── Type conversion ───────────────────────────────────────────────────────
SELECT
    toInt32('42'),
    toFloat64('3.14'),
    toString(now()),
    toDate('2024-01-01'),
    toDateTime('2024-01-01 10:00:00'),
    toDateTime64('2024-01-01 10:00:00.123', 3),
    -- Safe (returns default on error instead of exception):
    toInt32OrDefault('abc', 0),
    toInt32OrNull('abc'),
    toInt32OrZero('abc'),
    -- Type checking:
    toTypeName(now()),           -- 'DateTime'
    toTypeName([1,2,3]);         -- 'Array(UInt8)'
```

---

## Ghi chú – Keywords tiếp theo

- **clickhouse_performance.md**: Primary index sparse mechanism, Skip indexes (bloom_filter/minmax/set/tokenbf_v1/ngrambf_v1), Partition pruning, Materialized Views for incremental aggregation, Projections (alternative ORDER BY), Query profiling (EXPLAIN PIPELINE, system.query_log)
- **Keywords**: LowCardinality compression, ARRAY JOIN unnest, arrayJoin, argMax dedup, ASOF JOIN time-series, GLOBAL JOIN distributed, WITH TOTALS, ROLLUP/CUBE, SAMPLE BY, uniqExact vs uniq, quantileTDigest, AggregateFunction state/-Merge
