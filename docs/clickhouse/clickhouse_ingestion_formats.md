---
title: "ClickHouse Data Ingestion & Formats"
topic: clickhouse
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 2
---
# ClickHouse Data Ingestion & Formats

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [clickhouse_engines.md](clickhouse_engines.md) (Kafka/S3/Buffer engine), [clickhouse_production.md](clickhouse_production.md) (Kafka pipeline) và [clickhouse_fundamentals.md](clickhouse_fundamentals.md) (write path). Theo phương pháp What/How/Why/Compare/Trade-offs.

## Mục lục
1. [Write path & vì sao batch quan trọng (What & Why)](#1-write-path--vì-sao-batch-quan-trọng)
2. [Batch insert – kích thước & chiến lược](#2-batch-insert)
3. [Async Insert – cho nhiều client nhỏ](#3-async-insert)
4. [Các cách INSERT (VALUES/SELECT/INFILE/function)](#4-các-cách-insert)
5. [Input/Output Formats](#5-inputoutput-formats)
6. [Format settings & error tolerance](#6-format-settings--error-tolerance)
7. [clickhouse-client & clickhouse-local](#7-clickhouse-client--clickhouse-local)
8. [Insert deduplication (idempotent)](#8-insert-deduplication)
9. [Schema inference & DEFAULT/MATERIALIZED columns](#9-schema-inference--default-columns)
10. [Trade-offs & Best Practices](#10-trade-offs--best-practices)

---

## 1. Write path & vì sao batch quan trọng

### How – mỗi INSERT tạo một "part"
Mỗi câu `INSERT` vào MergeTree tạo ra **một data part** (thư mục bất biến trên đĩa). Background process **merge** các part nhỏ thành part lớn dần. Liên hệ MergeTree internals ở [clickhouse_fundamentals.md](clickhouse_fundamentals.md).

```
INSERT (1000 dòng) → 1 part mới → ... → merge → part lớn hơn
INSERT (1 dòng) × 100000  → 100000 part nhỏ → "too many parts" → MERGE không kịp → lỗi/treo
```

### Why – "Too many parts" là anti-pattern #1
ClickHouse tối ưu cho **ít insert lớn**, KHÔNG phải nhiều insert nhỏ (ngược OLTP). Quá nhiều part nhỏ → merge không kịp → lỗi `Too many parts (300)` → ngừng nhận insert. **Quy tắc vàng: insert theo batch lớn, tần suất thấp.**

---

## 2. Batch insert

```sql
-- ✅ Một INSERT nhiều dòng (lý tưởng: 10K–1M dòng/batch, mỗi 1s+)
INSERT INTO events VALUES (...), (...), ... ;  -- hàng chục nghìn dòng
```
- **Kích thước batch khuyến nghị**: ≥ 1000 dòng, thường 10K–100K; hoặc ~1-10MB dữ liệu/batch.
- **Tần suất**: tối đa ~1 insert/giây/bảng cho mỗi client (không spam).
- Gom batch ở phía ứng dụng (in-memory buffer) HOẶC để ClickHouse gom (async insert / Buffer engine).
- `max_insert_block_size` (mặc định 1048576): server chia block khi insert qua SELECT.

> Nếu nguồn là stream nhỏ giọt (IoT, log từng dòng) → **không** insert trực tiếp từng dòng; dùng async insert (mục 3), Buffer engine, hoặc một message queue (Kafka) làm lớp đệm. Liên hệ [clickhouse_engines.md](clickhouse_engines.md), [clickhouse_production.md](clickhouse_production.md).

---

## 3. Async Insert

Cho phép **nhiều client gửi insert nhỏ**; server **gom (buffer) phía server** rồi flush thành part lớn → giải quyết "too many parts" mà client không phải tự batch.

```sql
-- Bật per-query hoặc per-user/profile
SET async_insert = 1;
SET wait_for_async_insert = 1;     -- 1: chờ flush mới trả OK (an toàn, chậm hơn);
                                   -- 0: trả OK ngay (nhanh, rủi ro mất nếu crash trước flush)
SET async_insert_max_data_size = 10000000;   -- flush khi buffer đạt ~10MB
SET async_insert_busy_timeout_ms = 1000;     -- hoặc flush sau 1s
```
```
Client A ─┐
Client B ─┼──► [server-side buffer per insert-shape] ──(đủ size HOẶC hết timeout)──► 1 part
Client C ─┘
```
| | `wait_for_async_insert=1` | `=0` |
|--|---------------------------|------|
| Độ bền | Cao (đã ghi mới OK) | Thấp (có thể mất khi crash) |
| Latency client | Cao hơn | Thấp nhất |
| Khi dùng | Mặc định an toàn | Throughput tối đa, chấp nhận mất ít |

> **Async insert vs Buffer engine**: async insert là cơ chế built-in (khuyến nghị hiện nay); Buffer engine là bảng đệm RAM cũ hơn (rủi ro mất khi restart). Xem Buffer ở [clickhouse_engines.md](clickhouse_engines.md).

---

## 4. Các cách INSERT

```sql
-- 1) VALUES
INSERT INTO t VALUES (1, 'a'), (2, 'b');

-- 2) Từ SELECT (ETL nội bộ, copy bảng)
INSERT INTO target SELECT * FROM source WHERE ts > now() - INTERVAL 1 DAY;

-- 3) Từ file (clickhouse-client)
INSERT INTO t FROM INFILE 'data.parquet' FORMAT Parquet;
INSERT INTO t FROM INFILE 'data.csv.gz' COMPRESSION 'gzip' FORMAT CSVWithNames;

-- 4) Từ table function (đọc trực tiếp nguồn ngoài, không cần engine table)
INSERT INTO t SELECT * FROM s3('https://bucket/path/*.parquet', 'Parquet');
INSERT INTO t SELECT * FROM url('https://api/data.json', JSONEachRow);
INSERT INTO t SELECT * FROM file('local.csv', CSV);
SELECT * FROM remote('host:9000', db.table);   -- đọc từ ClickHouse khác
```
> Table function (`s3`/`url`/`file`/`remote`/`postgresql`/`mysql`) = đọc nguồn ngoài **ad-hoc** không cần tạo engine table. Engine table (S3/Kafka) = tích hợp lâu dài. Xem [clickhouse_engines.md](clickhouse_engines.md).

---

## 5. Input/Output Formats

ClickHouse đọc/ghi hàng chục format. Chọn đúng format ảnh hưởng lớn tới tốc độ.

| Format | Loại | Tốc độ | Khi dùng |
|--------|------|--------|----------|
| **Native** | Binary (cột) | **Nhanh nhất** | ClickHouse↔ClickHouse, dump/restore |
| **RowBinary** | Binary (dòng) | Rất nhanh | Client driver hiệu năng cao |
| **Parquet** | Binary cột | Nhanh | Data lake, S3, Spark, dbt |
| **Arrow / ArrowStream** | Binary cột | Nhanh | Interop in-memory analytics |
| **Avro / Protobuf** | Binary có schema | Nhanh | Kafka, schema registry |
| **ORC** | Binary cột | Nhanh | Hadoop/Hive |
| **JSONEachRow** | Text (1 JSON/dòng) | Trung bình | API, log, dễ debug |
| **CSV / CSVWithNames** | Text | Trung bình–chậm | Export/import phổ thông |
| **TSV (TabSeparated)** | Text | Trung bình | Unix pipe |
| **Values** | Text | Chậm | `INSERT ... VALUES` |
| **Pretty / PrettyCompact** | Text | – | Hiển thị CLI (không dùng ingest) |

```sql
SELECT * FROM events FORMAT Parquet INTO OUTFILE 'out.parquet';
SELECT * FROM events FORMAT JSONEachRow;     -- {"a":1}\n{"a":2}
```
> Ingest hiệu năng cao: **Native/RowBinary** (driver) hoặc **Parquet** (file/S3). JSONEachRow tiện nhưng tốn parse. `WithNames`/`WithNamesAndTypes` cho phép map cột theo tên (an toàn khi đổi thứ tự).

---

## 6. Format settings & error tolerance

```sql
-- Bỏ qua dòng lỗi (đừng để 1 dòng hỏng làm fail cả batch)
SET input_format_allow_errors_num = 100;       -- cho phép tối đa 100 dòng lỗi
SET input_format_allow_errors_ratio = 0.01;    -- hoặc tối đa 1%

-- JSON linh hoạt
SET input_format_skip_unknown_fields = 1;      -- bỏ field JSON không có trong schema
SET input_format_null_as_default = 1;          -- null → giá trị default của cột
SET input_format_import_nested_json = 1;

-- Ngày/giờ
SET date_time_input_format = 'best_effort';    -- parse nhiều định dạng ngày
SET input_format_defaults_for_omitted_fields = 1;

-- CSV
SET format_csv_delimiter = ';';
SET input_format_csv_skip_first_lines = 1;     -- bỏ header
```
> `best_effort` parse ngày linh hoạt nhưng chậm hơn; `input_format_allow_errors_*` rất quan trọng cho dữ liệu bẩn (logs). Dòng lỗi có thể đẩy sang bảng "dead letter".

---

## 7. clickhouse-client & clickhouse-local

```bash
# clickhouse-client: kết nối server, batch & pipe
clickhouse-client --query "INSERT INTO t FORMAT CSV" < data.csv
cat huge.jsonl | clickhouse-client --query "INSERT INTO t FORMAT JSONEachRow"
clickhouse-client --multiquery --queries-file=migrate.sql
clickhouse-client -h host --secure --password --query "SELECT 1"   # TLS, xem security

# clickhouse-local: chạy SQL trên FILE mà KHÔNG cần server (ETL/khám phá nhanh)
clickhouse-local --query "
  SELECT count() FROM file('access.log.*', 'JSONEachRow')
  WHERE status >= 500"
# Chuyển đổi format: CSV → Parquet
clickhouse-local --query "SELECT * FROM file('in.csv', CSVWithNames) FORMAT Parquet" > out.parquet
```
> `clickhouse-local` = "DuckDB của ClickHouse": query file local/S3 không cần cài server → cực hợp ETL, kiểm tra dữ liệu, chuyển format. `clickhouse-client` cho ingest batch qua pipe.

---

## 8. Insert deduplication

ClickHouse hỗ trợ **idempotent insert** (gửi lại batch trùng không nhân đôi) — quan trọng cho pipeline at-least-once (Kafka retry).

```sql
-- ReplicatedMergeTree: tự dedup theo HASH của block (mặc định, trong 1 cửa sổ)
-- Cùng dữ liệu + cùng cấu trúc block → bị bỏ qua nếu trùng block gần đây

-- Dedup token tường minh (kiểm soát cửa sổ dedup)
INSERT INTO t SETTINGS insert_deduplication_token = 'batch-2026-06-04-001' VALUES ...;
-- Gửi lại cùng token → bỏ qua (idempotent), kể cả dữ liệu khác
```
- Replicated block dedup dựa trên `insert_deduplication` (mặc định bật cho Replicated). Cửa sổ: `*_deduplication_window`.
- Khác với **dedup logic nghiệp vụ** (ReplacingMergeTree gộp theo key khi merge) — xem [clickhouse_engines.md](clickhouse_engines.md) và chiến lược dedup ở [clickhouse_production.md](clickhouse_production.md).

---

## 9. Schema inference & DEFAULT columns

### Schema inference (tự đoán schema từ file)
```sql
DESCRIBE TABLE file('data.parquet', Parquet);     -- xem schema suy ra
CREATE TABLE t ENGINE=MergeTree ORDER BY tuple()
AS SELECT * FROM file('data.parquet', Parquet);   -- tạo bảng theo schema file
```

### Cột tính toán lúc insert
```sql
CREATE TABLE events (
    raw String,
    ts DateTime,
    day Date MATERIALIZED toDate(ts),         -- tính & lưu khi insert, không cần gửi
    host String DEFAULT 'unknown',            -- default nếu thiếu
    parsed String EPHEMERAL,                  -- chỉ tồn tại lúc insert, KHÔNG lưu
    user_id UInt64 DEFAULT JSONExtractUInt(parsed, 'uid')
) ENGINE = MergeTree ORDER BY ts;
```
| Loại | Lưu trên đĩa? | Gửi khi insert? |
|------|---------------|-----------------|
| `DEFAULT` | Có | Tùy chọn (thiếu → default) |
| `MATERIALIZED` | Có | Không (tính từ cột khác) |
| `ALIAS` | Không | Không (tính khi đọc) |
| `EPHEMERAL` | Không | Có (dùng để tính cột khác) |

---

## 10. Trade-offs & Best Practices

### Best practices
- **Batch lớn, tần suất thấp** (≥1000 dòng); KHÔNG insert từng dòng.
- Nguồn nhỏ giọt → **async_insert** hoặc Kafka làm đệm.
- Format ingest: **Native/RowBinary** (driver) hoặc **Parquet** (file/S3); JSONEachRow cho tiện/debug.
- Bật `input_format_allow_errors_*` cho dữ liệu bẩn; route dòng lỗi ra dead-letter.
- Idempotent: dùng `insert_deduplication_token` cho pipeline at-least-once.
- `MATERIALIZED`/`DEFAULT` để tính cột (day, parsed) ngay khi ghi → query nhanh.

### Trade-offs
- (+) Ingest throughput rất cao (hàng triệu dòng/s) khi batch đúng; nhiều format & nguồn (S3/Kafka/file/url).
- (−) Mô hình part → nhạy cảm với insert nhỏ ("too many parts"); cần kỷ luật batch.
- (−) `async_insert wait=0` nhanh nhưng rủi ro mất dữ liệu; cân bằng độ bền/latency.
- (−) Schema inference tiện nhưng có thể đoán sai kiểu → production nên khai báo schema tường minh.

---

## Ghi chú – Keywords tiếp theo

- Liên quan: [clickhouse_engines.md](clickhouse_engines.md) (Kafka/S3/Buffer engine, ReplacingMergeTree), [clickhouse_production.md](clickhouse_production.md) (Kafka→CH pipeline, dedup strategy, S3 cold), [clickhouse_fundamentals.md](clickhouse_fundamentals.md) (parts/merge), [clickhouse_query_execution.md](clickhouse_query_execution.md) (INSERT SELECT performance).
- **Keywords**: `parts_to_throw_insert`, `max_partitions_per_insert_block`, `async_insert_deduplicate`, `input_format_parallel_parsing`, `output_format_parquet_compression_method`, `min_insert_block_size_rows`, `clickhouse-client --progress`, `INFILE`/`OUTFILE` COMPRESSION, `s3Cluster()` table function, `Distributed` insert, `optimize_on_insert`, materialized view trigger on insert.

*Cập nhật lần cuối: 2026-06-04*
