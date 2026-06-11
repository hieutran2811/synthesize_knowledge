# ClickHouse Functions & Aggregate Combinators

> Bổ trợ cho [clickhouse_sql.md](clickhouse_sql.md) (arrays/JSON/window) và [clickhouse_engines.md](clickhouse_engines.md) (AggregatingMergeTree dùng -State/-Merge). Theo phương pháp What/How/Why/Compare/Trade-offs.

## Mục lục
1. [Vì sao function quan trọng ở ClickHouse (What & Why)](#1-vì-sao-function-quan-trọng)
2. [Aggregate Combinators – hệ thống hậu tố](#2-aggregate-combinators)
3. [Mô hình -State / -Merge (AggregateFunction)](#3-mô-hình-state--merge)
4. [Catalog hàm aggregate quan trọng](#4-catalog-hàm-aggregate)
5. [Funnel & Sequence analytics](#5-funnel--sequence-analytics)
6. [Higher-order Array Functions (lambda)](#6-higher-order-array-functions)
7. [Date/Time functions](#7-datetime-functions)
8. [String, Conditional & Type conversion](#8-string-conditional--type-conversion)
9. [Trade-offs](#9-trade-offs)

---

## 1. Vì sao function quan trọng

ClickHouse có **hàng nghìn** hàm built-in, nhưng sức mạnh thật nằm ở **tính tổ hợp (composability)**:
- **Combinator**: hậu tố gắn vào hàm aggregate để biến đổi hành vi (vd `sumIf`, `uniqArray`, `avgState`).
- **Higher-order array functions**: áp dụng lambda lên array ngay trong SQL.
- **-State/-Merge**: nền tảng của **incremental aggregation** (AggregatingMergeTree, Materialized View).

Nắm vững phần này = viết được analytics phức tạp **trong một câu SQL** thay vì kéo dữ liệu ra ngoài xử lý.

---

## 2. Aggregate Combinators

Gắn **hậu tố** vào tên hàm aggregate để đổi hành vi. **Ghép chuỗi được** (vd `sumArrayIf`).

| Combinator | Tác dụng | Ví dụ |
|-----------|----------|-------|
| `-If` | Aggregate có điều kiện (thay cho `CASE`) | `sumIf(amount, status='paid')` |
| `-Array` | Áp dụng lên từng phần tử của cột array | `sumArray(scores)` → tổng mọi phần tử |
| `-Map` | Aggregate theo key của Map | `sumMap(keys, values)` |
| `-ForEach` | Aggregate song song theo vị trí array | `sumForEach(arr)` |
| `-Distinct` | Chỉ tính giá trị khác nhau | `countDistinct(x)` ≈ `uniqExact` |
| `-OrNull` | Trả NULL nếu không có dòng (thay vì 0) | `sumOrNull(x)` |
| `-OrDefault` | Trả default nếu rỗng | `avgOrDefault(x)` |
| `-Resample` | Chia theo khoảng → mảng kết quả | `countResample(0,100,10)(x, x)` |
| `-State` | Trả **trạng thái trung gian** (chưa finalize) | `uniqState(user_id)` |
| `-Merge` | Gộp các state lại thành kết quả cuối | `uniqMerge(state)` |
| `-SimpleState` | State cho SimpleAggregateFunction | `sumSimpleState(x)` |

```sql
-- -If thay cho nhiều CASE WHEN — chạy 1 lần quét, nhanh
SELECT
    countIf(status = 'error')                    AS errors,
    sumIf(bytes, status = 'success')             AS ok_bytes,
    avgIf(latency, region = 'EU')                AS eu_latency,
    uniqIf(user_id, event = 'purchase')          AS buyers
FROM events;

-- Ghép combinator: tổng có điều kiện trên array
SELECT sumArrayIf(values, tag = 'x') FROM t;
```

---

## 3. Mô hình -State / -Merge

### What – AggregateFunction
`-State` trả về một **trạng thái nhị phân trung gian** (kiểu `AggregateFunction(func, types)`) thay vì kết quả cuối. `-Merge` gộp nhiều state thành kết quả. Đây là cách ClickHouse **tiền tổng hợp tăng dần** mà vẫn cho phép re-aggregate ở mọi mức (giờ → ngày → tháng).

```
Raw rows ──uniqState()──► [state nhị phân] ──uniqMerge()──► kết quả uniq cuối
                          (lưu trong AggregatingMergeTree, gộp khi merge parts)
```

### How – kết hợp với Materialized View + AggregatingMergeTree
```sql
-- Bảng đích lưu STATE (không phải giá trị cuối)
CREATE TABLE mv_daily (
    day Date,
    uniq_users AggregateFunction(uniq, UInt64),     -- lưu state
    revenue    AggregateFunction(sum, Decimal(18,2))
) ENGINE = AggregatingMergeTree ORDER BY day;

-- MV ghi state khi có dữ liệu mới (incremental)
CREATE MATERIALIZED VIEW mv TO mv_daily AS
SELECT toDate(ts) AS day,
       uniqState(user_id)  AS uniq_users,
       sumState(amount)    AS revenue
FROM events GROUP BY day;

-- Đọc: PHẢI -Merge để finalize
SELECT day, uniqMerge(uniq_users) AS users, sumMerge(revenue) AS rev
FROM mv_daily GROUP BY day;
```
> Vì state có thể gộp ở mọi mức → query đọc cực nhanh trên dữ liệu đã tiền tổng hợp. Liên hệ Materialized View ở [clickhouse_performance.md](clickhouse_performance.md) và AggregatingMergeTree ở [clickhouse_engines.md](clickhouse_engines.md).
> `SimpleAggregateFunction` (nhẹ hơn) dùng cho hàm mà state = giá trị (sum/min/max/any) — không cần -Merge khi đọc nếu kết hợp đúng.

---

## 4. Catalog hàm aggregate

### Đếm distinct (cardinality) – chọn theo độ chính xác/tốc độ
| Hàm | Cơ chế | Độ chính xác | Khi dùng |
|-----|--------|--------------|----------|
| `uniqExact(x)` | Hash set đầy đủ | Chính xác 100% | Cần đúng tuyệt đối, tốn RAM |
| `uniq(x)` | Adaptive (HLL-ish) | ~xấp xỉ (lỗi ~0.5%) | **Mặc định**, nhanh, ít RAM |
| `uniqCombined(x)` | Array+hash+HLL | Xấp xỉ, ít RAM hơn `uniq` | Cardinality lớn |
| `uniqHLL12(x)` | HyperLogLog | Xấp xỉ, RAM cố định | Cực nhiều giá trị |
| `uniqTheta(x)` | Theta sketch | Xấp xỉ, hỗ trợ set ops | Giao/hợp các tập |

### Quantile / percentile
```sql
SELECT quantile(0.95)(latency)            AS p95,        -- xấp xỉ (reservoir)
       quantileExact(0.99)(latency)       AS p99_exact,  -- chính xác, tốn RAM
       quantileTDigest(0.999)(latency)    AS p999,       -- t-digest, tốt cho tail
       quantiles(0.5, 0.9, 0.99)(latency) AS multi       -- nhiều percentile 1 lần
FROM requests;
```

### Top-N, arg, group
```sql
topK(10)(page)                 -- 10 giá trị xuất hiện nhiều nhất (xấp xỉ)
topKWeighted(10)(page, views)  -- top theo trọng số
argMax(user_id, score)         -- user_id tại dòng có score lớn nhất
argMin(price, ts)              -- giá tại thời điểm sớm nhất
any(x) / anyLast(x)            -- 1 giá trị bất kỳ / cuối (rẻ)
groupArray(x) / groupArray(5)(x)   -- gom thành array (giới hạn 5)
groupUniqArray(x)              -- array các giá trị distinct
sumMap(keys, values)           -- tổng theo key (key-value aggregation)
avgWeighted(x, w)              -- trung bình có trọng số
```

---

## 5. Funnel & Sequence analytics

Điểm mạnh "killer" của ClickHouse cho product analytics — phân tích hành vi theo trình tự **trong SQL**.

```sql
-- windowFunnel: đếm user đi qua chuỗi bước trong cửa sổ thời gian
SELECT level, count() AS users FROM (
  SELECT user_id,
    windowFunnel(3600)(ts,                          -- trong 1 giờ
      event = 'view', event = 'add_cart', event = 'purchase') AS level
  FROM events GROUP BY user_id
) GROUP BY level ORDER BY level;                     -- level 0/1/2/3 = đi tới bước nào

-- retention: giữ chân theo điều kiện mốc
SELECT retention(date = '2026-06-01', date = '2026-06-02', date = '2026-06-03') AS r
FROM events GROUP BY user_id;

-- sequenceMatch / sequenceCount: khớp mẫu chuỗi sự kiện
SELECT sequenceMatch('(?1).*(?2)')(ts, event='login', event='purchase') FROM events;
```
> Đây là lý do nhiều công ty dùng ClickHouse cho **clickstream/funnel/retention** thay vì kéo ra Spark. Liên hệ use cases ở [clickhouse_production.md](clickhouse_production.md).

---

## 6. Higher-order Array Functions

Áp dụng **lambda** (`x -> expr`) lên array ngay trong SQL — không cần unnest.

```sql
arrayMap(x -> x * 2, [1,2,3])                    -- [2,4,6]
arrayFilter(x -> x > 1, [1,2,3])                 -- [2,3]
arrayReduce('sum', [1,2,3])                      -- 6 (áp dụng aggregate lên array)
arrayFold((acc, x) -> acc + x, [1,2,3], 0::Int64)-- fold/reduce có accumulator
arrayExists(x -> x = 0, arr)                     -- có phần tử thỏa? → 0/1
arrayAll(x -> x > 0, arr)                        -- mọi phần tử thỏa?
arrayFirst(x -> x > 5, arr)                      -- phần tử đầu thỏa
arrayCount(x -> x > 5, arr)                      -- đếm phần tử thỏa
arraySort(x -> -x, arr)                          -- sort theo key
arrayCumSum([1,2,3])                             -- [1,3,6] tích lũy
-- Lambda nhiều array (theo vị trí)
arrayMap((x, y) -> x + y, a, b)
```

### Array tiện ích
```sql
arrayJoin(arr)            -- "nổ" array thành nhiều dòng (xem sql.md)
has(arr, 5) / hasAll(a,b) / hasAny(a,b) / indexOf(arr, x)
arrayDistinct(arr) / arrayConcat(a, b) / arrayFlatten(nested)
arraySlice(arr, 2, 3) / arrayZip(a, b) / range(10)
arrayEnumerate(arr) / arrayEnumerateUniq(arr)    -- đánh số / đánh số lần xuất hiện
```
> Liên hệ Arrays & Nested ở [clickhouse_sql.md](clickhouse_sql.md).

---

## 7. Date/Time functions

```sql
-- Truncation (cốt lõi của time-series rollup)
toStartOfDay(ts) / toStartOfHour(ts) / toStartOfMonth(ts)
toStartOfInterval(ts, INTERVAL 15 MINUTE)        -- bucket 15 phút
dateTrunc('hour', ts)

-- Arithmetic & diff
addDays(d, 7) / subtractHours(ts, 3) / now() / today() / yesterday()
dateDiff('day', start, end) / age('month', a, b)
toUnixTimestamp(ts) / fromUnixTimestamp(1700000000)

-- Định dạng & trích
formatDateTime(ts, '%Y-%m-%d %H:%M')
toYYYYMM(d)            -- 202606 (hay dùng làm partition key)
toYear(d) / toMonth(d) / toDayOfWeek(d) / toHour(ts)

-- Timezone (lưu UTC, hiển thị theo tz)
toTimeZone(ts, 'Asia/Ho_Chi_Minh')
toDateTime('2026-06-04 10:00:00', 'Asia/Ho_Chi_Minh')
```
> Gap-filling cho time-series: `WITH FILL` trong ORDER BY (xem [clickhouse_sql.md](clickhouse_sql.md)). `toYYYYMM` thường làm PARTITION BY (xem [clickhouse_performance.md](clickhouse_performance.md)).

---

## 8. String, Conditional & Type conversion

### String
```sql
position(s, 'abc') / like(s, '%x%') / match(s, '^[0-9]+$')   -- regex (RE2)
splitByChar(',', s) / splitByString('::', s) / extractAll(s, '\\d+')
replaceRegexpAll(s, '\\d', '*') / concat(a, b) / format('{0}-{1}', a, b)
lowerUTF8(s) / upperUTF8(s) / lengthUTF8(s) / trim(s) / substring(s, 1, 3)
JSONExtractString(json, 'key') / JSONExtractInt(json, 'n')   -- xem sql.md
```

### Conditional
```sql
if(cond, a, b)
multiIf(c1, r1, c2, r2, default)        -- chuỗi if-else (nhanh hơn CASE lồng)
CASE WHEN ... THEN ... ELSE ... END
coalesce(a, b, c) / nullIf(a, b) / ifNull(x, 0) / assumeNotNull(x)
```

### Type conversion
```sql
CAST(x AS UInt32) / x::UInt32           -- cú pháp ::
toInt64(s) / toFloat64(s) / toString(x) / toDate(s) / toDecimal64(x, 2)
accurateCast(x, 'UInt8')                -- ném lỗi nếu tràn (an toàn)
accurateCastOrNull(x, 'UInt8')          -- NULL nếu không hợp lệ
toTypeName(x)                            -- debug: kiểu thực của biểu thức
reinterpretAsUInt64(x)                  -- diễn giải lại byte (không convert giá trị)
```
> ⚠️ `toInt*` mặc định **overflow im lặng** (wrap-around); dùng `accurateCast*` khi cần an toàn. LowCardinality/Nullable: xem [clickhouse_sql.md](clickhouse_sql.md).

---

## 9. Trade-offs

- (+) Combinator + higher-order + funnel functions → analytics phức tạp trong 1 SQL, không cần ETL ngoài → cực nhanh (vectorized, ngay trên dữ liệu cột).
- (+) -State/-Merge cho incremental aggregation: query đọc bảng tiền tổng hợp nhỏ thay vì quét raw.
- (−) **Không chuẩn SQL** → khó port sang DB khác; learning curve cao (nhiều hàm, hậu tố).
- (−) Hàm xấp xỉ (`uniq`, `quantile`, `topK`) nhanh nhưng **không chính xác tuyệt đối** → chọn Exact khi cần đúng (trả giá RAM/tốc độ).
- (−) `-Merge` quên gắn khi đọc AggregateFunction → kết quả vô nghĩa (state nhị phân); bẫy thường gặp.
- (−) Array functions mạnh nhưng array quá lớn/row → tốn RAM, cẩn thận `arrayJoin` nhân dòng.

---

## Ghi chú – Keywords tiếp theo

- Liên quan: [clickhouse_sql.md](clickhouse_sql.md) (arrays/JSON/window/WITH FILL), [clickhouse_engines.md](clickhouse_engines.md) (AggregatingMergeTree/SummingMergeTree), [clickhouse_performance.md](clickhouse_performance.md) (Materialized View incremental), [clickhouse_production.md](clickhouse_production.md) (funnel use cases).
- **Keywords**: `-State`/`-Merge`/`-MergeState`, `SimpleAggregateFunction`, `initializeAggregation`, `finalizeAggregation`, `arrayReduceInRanges`, `groupArrayMovingSum`, `quantileBFloat16`, `uniqUpTo`, `sumMapFiltered`, `sequenceNextNode`, `categoricalInformationValue`, `runningDifference`/`neighbor` (deprecated → window functions), `mapApply`/`mapFilter` (Map higher-order), `WITH FILL STEP`.

*Cập nhật lần cuối: 2026-06-04*
