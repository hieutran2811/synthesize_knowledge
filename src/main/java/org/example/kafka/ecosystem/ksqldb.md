# ksqlDB & Stream Processing SQL – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – ksqlDB là gì?

**ksqlDB** là database stream processing cho phép xử lý dữ liệu Kafka bằng **SQL** thay vì viết code Java. Bên dưới, mỗi câu SQL được biên dịch thành một ứng dụng **Kafka Streams** (xem [../streams/kafka_streams.md](../streams/kafka_streams.md)).

```
SQL ──► ksqlDB Server ──► (sinh) Kafka Streams topology ──► Kafka topics
                                                          └─► materialized state store (RocksDB)
```

---

## Why – Tại sao dùng ksqlDB?

- **Declarative**: viết `SELECT ... EMIT CHANGES` thay vì code topology → tốc độ phát triển nhanh.
- **Không cần deploy app riêng**: chạy query trên ksqlDB cluster sẵn có.
- **Phù hợp người biết SQL** (data analyst/engineer) làm stream processing mà không cần Java.
- Tích hợp sẵn Connect + Schema Registry (đọc schema tự suy cột).

> Đánh đổi: ít linh hoạt hơn Kafka Streams thuần (logic phức tạp/đặc thù khó biểu diễn bằng SQL).

---

## Components – Streams vs Tables

Khái niệm nền tảng (giống Kafka Streams): **stream-table duality**.

| | STREAM | TABLE |
|--|--------|-------|
| Bản chất | Chuỗi sự kiện **append-only** (mọi event) | Trạng thái **mới nhất theo key** (changelog) |
| Ví dụ | Mỗi lần click, mỗi giao dịch | Số dư tài khoản hiện tại, trạng thái đơn |
| Insert cùng key | Thêm event mới | **Ghi đè** giá trị cũ |
| Tương ứng | Kafka topic (log) | Compacted topic / aggregation result |

```sql
-- STREAM: đọc topic như dòng sự kiện
CREATE STREAM clicks (user_id VARCHAR, url VARCHAR, ts BIGINT)
  WITH (KAFKA_TOPIC='clicks', VALUE_FORMAT='AVRO');     -- schema từ Schema Registry

-- TABLE: trạng thái mới nhất theo key (PRIMARY KEY)
CREATE TABLE users (user_id VARCHAR PRIMARY KEY, name VARCHAR, tier VARCHAR)
  WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
```
> `VALUE_FORMAT='AVRO'` → ksqlDB tự lấy schema từ Schema Registry, không cần khai cột. Liên hệ [./schema_registry.md](schema_registry.md).

---

## How – Push Query vs Pull Query

| | Push Query (`EMIT CHANGES`) | Pull Query |
|--|------------------------------|------------|
| Hành vi | Chạy **mãi mãi**, stream kết quả khi có dữ liệu mới | Trả kết quả tại 1 thời điểm rồi **kết thúc** |
| Trên | Stream hoặc Table | **Materialized Table** (lookup theo key) |
| Giống | "subscribe" liên tục | Query DB truyền thống (request/response) |
| Dùng | Pipeline, alert real-time | API tra cứu trạng thái hiện tại |

```sql
-- Push: liên tục (CLI hiển thị, hoặc app subscribe qua REST)
SELECT user_id, url FROM clicks WHERE url LIKE '/checkout%' EMIT CHANGES;

-- Pull: tra cứu điểm (materialized table) — trả về & dừng
SELECT total FROM clicks_per_user WHERE user_id = 'u123';
```

---

## How – Persistent Query (CSAS / CTAS)

Tạo stream/table **mới** từ query → chạy liên tục, ghi kết quả ra topic mới (đây là "job" thực sự).

```sql
-- CREATE STREAM AS SELECT: lọc/biến đổi → topic mới
CREATE STREAM checkout_clicks AS
  SELECT user_id, url, ts FROM clicks WHERE url LIKE '/checkout%' EMIT CHANGES;

-- CREATE TABLE AS SELECT: aggregation → materialized table
CREATE TABLE clicks_per_user AS
  SELECT user_id, COUNT(*) AS total
  FROM clicks GROUP BY user_id EMIT CHANGES;       -- GROUP BY → ra TABLE
```
> CSAS/CTAS chạy như một Kafka Streams app thường trú; xem các query đang chạy: `SHOW QUERIES;`, `TERMINATE <id>;`.

---

## How – Windowing & Aggregations

```sql
-- Tumbling window (cửa sổ cố định không chồng)
CREATE TABLE orders_per_min AS
  SELECT product_id, COUNT(*) AS cnt
  FROM orders WINDOW TUMBLING (SIZE 1 MINUTE)
  GROUP BY product_id EMIT CHANGES;

-- Hopping (chồng nhau), Session (theo khoảng nghỉ)
... WINDOW HOPPING (SIZE 5 MINUTE, ADVANCE BY 1 MINUTE) ...
... WINDOW SESSION (30 SECONDS) ...
```
> Windowing/aggregation giống Kafka Streams (xem [../streams/kafka_streams.md](../streams/kafka_streams.md)); ksqlDB phơi ra qua SQL.

---

## How – Joins

```sql
-- Stream-Table join (enrichment: gắn thông tin user vào mỗi click)
CREATE STREAM enriched_clicks AS
  SELECT c.user_id, c.url, u.name, u.tier
  FROM clicks c JOIN users u ON c.user_id = u.user_id EMIT CHANGES;

-- Stream-Stream join (cần WITHIN window)
SELECT * FROM orders o JOIN payments p WITHIN 1 HOUR ON o.id = p.order_id EMIT CHANGES;
```
| Join | Yêu cầu | Kết quả |
|------|---------|---------|
| Stream-Table | Co-partitioned | Enrichment (lookup trạng thái) |
| Stream-Stream | `WITHIN` window | Tương quan sự kiện theo thời gian |
| Table-Table | Co-partitioned | Trạng thái kết hợp |

---

## How – UDF/UDAF & Connectors

```sql
-- ksqlDB có thể quản Connect: tạo connector bằng SQL
CREATE SOURCE CONNECTOR pg_source WITH (
  'connector.class'='io.debezium.connector.postgresql.PostgresConnector', ...);

-- UDF tự viết (Java, annotation @Udf) → dùng như hàm SQL
SELECT my_custom_score(amount, tier) FROM orders EMIT CHANGES;
```
> UDF/UDAF/UDTF viết bằng Java, đóng gói jar nạp vào ksqlDB. Liên hệ Connect ở [../streams/connect.md](../streams/connect.md).

---

## Compare – ksqlDB vs Kafka Streams vs Flink

| | ksqlDB | Kafka Streams | Apache Flink |
|--|--------|---------------|--------------|
| Giao diện | SQL | Java/Scala library | SQL + Java/Scala/Python |
| Deploy | ksqlDB cluster | Nhúng trong app của bạn | Cluster Flink riêng (JobManager/TaskManager) |
| Linh hoạt | Thấp–TB (SQL) | **Cao** (full code) | **Rất cao** |
| State backend | RocksDB | RocksDB | RocksDB/heap, checkpoint |
| Nguồn dữ liệu | Chủ yếu Kafka | Chủ yếu Kafka | Đa nguồn (Kafka, file, CDC, JDBC...) |
| Khi dùng | Stream SQL nhanh, ít code | Logic phức tạp trong microservice JVM | Pipeline lớn, event-time mạnh, đa nguồn, exactly-once nâng cao |

> ksqlDB = SQL nhanh trên Kafka. Kafka Streams = nhúng library, kiểm soát hoàn toàn. Flink = engine xử lý mạnh nhất, độc lập Kafka. Chọn theo độ phức tạp & kỹ năng team.

---

## Trade-offs

- (+) Phát triển nhanh bằng SQL, không cần app riêng, tích hợp SR/Connect, hợp data engineer.
- (−) Ít linh hoạt hơn Kafka Streams (logic đặc thù, control fine-grained khó); debug topology sinh tự động khó hơn.
- (−) ksqlDB cluster là thành phần phải vận hành/HA; state lớn → quản RocksDB/rebalance như Kafka Streams.
- (−) Khóa vào hệ Confluent (ksqlDB là Confluent); cân nhắc Flink SQL nếu cần độc lập/đa nguồn.
- (−) Pull query chỉ trên materialized table (không phải mọi truy vấn tùy ý như DB OLAP).

---

## Real-world

```sql
-- Pipeline điển hình: làm giàu + tổng hợp + phơi qua pull query cho API
CREATE STREAM enriched AS SELECT ... JOIN users ... EMIT CHANGES;     -- enrichment
CREATE TABLE fraud_score AS                                          -- aggregation real-time
  SELECT user_id, COUNT(*) FILTER (WHERE amount > 1000) AS big_txns
  FROM enriched WINDOW TUMBLING (SIZE 10 MINUTE) GROUP BY user_id EMIT CHANGES;
-- App gọi pull query: SELECT big_txns FROM fraud_score WHERE user_id='u1';  → cảnh báo gian lận
```
- Use cases: real-time ETL/enrichment, alerting, materialized view cho dashboard, anomaly/fraud detection nhẹ.
- Nặng/phức tạp/đa nguồn → cân nhắc Flink. Logic nghiệp vụ sâu trong service → Kafka Streams.

---

## Ghi chú – Chủ đề tiếp theo
> `patterns/event_driven_architecture.md`: thiết kế topic/partition/key, event design (notification vs state transfer vs event sourcing), EDA patterns (CQRS, outbox, saga, DLQ), idempotent consumer, delivery semantics thực chiến.

> Liên quan: [../streams/kafka_streams.md](../streams/kafka_streams.md) (nền tảng bên dưới), [./schema_registry.md](schema_registry.md) (suy cột từ schema), [../streams/connect.md](../streams/connect.md) (connector qua ksqlDB).

> Keywords: `EMIT CHANGES`, `EMIT FINAL`, materialized view, `SHOW QUERIES`/`TERMINATE`, `PARTITION BY`/`GROUP BY`, `LATEST_BY_OFFSET`/`EARLIEST_BY_OFFSET`, `AS_VALUE`/`ROWKEY`/`ROWTIME`, headless mode (production), interactive vs headless, Flink SQL (alternative).

---

*Cập nhật lần cuối: 2026-06-04*
