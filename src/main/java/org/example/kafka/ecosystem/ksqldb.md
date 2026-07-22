# ksqlDB & Stream Processing SQL – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – ksqlDB là gì?

**ksqlDB** là nền tảng **stream processing** *(xử lý luồng sự kiện)* cho phép xử lý dữ liệu Kafka bằng **SQL** thay vì viết code Java. Query persistent được biên dịch thành topology Kafka Streams và chạy trên ksqlDB cluster (xem [kafka_streams.md](../streams/kafka_streams.md)); không phải mọi câu lệnh tương tác đều tạo một job lâu dài.

ksqlDB quản lý topology, state store, repartition topic và task ở phía server. Vì vậy người dùng giảm code ứng dụng, nhưng vẫn phải thiết kế key, partition, SerDe/schema, retention và lifecycle như khi dùng Kafka Streams.

> 💡 **Giải thích dễ hiểu:**
> ksqlDB giống bảng điều khiển SQL đặt trên dây chuyền Kafka. Bạn ghi công thức, server dựng dây chuyền và vận hành liên tục; công thức ngắn hơn nhưng nguyên liệu (key/schema) và sức chứa (partition/state) vẫn phải được thiết kế đúng.

```text
SQL ──► ksqlDB Server ──► (sinh) Kafka Streams topology ──► Kafka topics
                                                          └─► materialized state store (RocksDB)
```

---

## Why – Tại sao dùng ksqlDB?

- **Declarative**: viết `SELECT ... EMIT CHANGES` thay vì code topology → tốc độ phát triển nhanh.
- **Không cần deploy app riêng**: chạy query trên ksqlDB cluster sẵn có.
- **Phù hợp người biết SQL** (data analyst/engineer) làm stream processing mà không cần Java.
- Tích hợp với Kafka Connect và Schema Registry; việc suy/kiểm tra schema vẫn phụ thuộc cấu hình SerDe và compatibility của từng subject.

> 💡 **Giải thích dễ hiểu:**
> ksqlDB giúp viết pipeline nhanh như SQL, nhưng không biến Kafka thành cơ sở dữ liệu OLAP. Bạn vẫn phải quản lý partition, key, schema, state và lifecycle của query chạy lâu dài.

Đánh đổi chính là ít linh hoạt hơn Kafka Streams thuần (logic phức tạp/đặc thù khó biểu diễn bằng SQL), đồng thời phải vận hành HA ksqlDB cluster.

---

## Components – Streams vs Tables

Khái niệm nền tảng (giống Kafka Streams): **stream-table duality** *(tính hai mặt stream–table)*.

| | STREAM | TABLE |
|--|--------|-------|
| Bản chất | Chuỗi sự kiện **append-only** *(chỉ thêm event)* | Trạng thái **mới nhất theo key** (changelog) |
| Ví dụ | Mỗi lần click, mỗi giao dịch | Số dư tài khoản hiện tại, trạng thái đơn |
| Insert cùng key | Thêm event mới | **Ghi đè** giá trị cũ |
| Tương ứng | Kafka topic (log) | Topic/aggregation được diễn giải theo key; thường dùng log compaction |

```sql
-- STREAM: đọc topic như dòng sự kiện
-- Có thể khai cột rõ ràng; VALUE_FORMAT chỉ định cách SerDe value.
CREATE STREAM clicks (user_id VARCHAR, url VARCHAR, ts BIGINT)
  WITH (KAFKA_TOPIC='clicks', VALUE_FORMAT='AVRO');

-- TABLE: trạng thái mới nhất theo key (PRIMARY KEY)
CREATE TABLE users (user_id VARCHAR PRIMARY KEY, name VARCHAR, tier VARCHAR)
  WITH (KAFKA_TOPIC='users', VALUE_FORMAT='AVRO');
```

`VALUE_FORMAT='AVRO'` yêu cầu Schema Registry được cấu hình và dùng schema để serialize/deserialize; trong nhiều câu lệnh ksqlDB có thể suy schema từ Registry, nhưng khai báo key/columns rõ ràng giúp kiểm soát contract. Avro key cần cấu hình `KEY_FORMAT`/schema phù hợp; không nên hiểu `VALUE_FORMAT` là tự động bảo đảm compatibility. Liên hệ [schema_registry.md](schema_registry.md).

Tombstone *(record có value `NULL`)* thường biểu diễn xóa key trong table/changelog. Stream vẫn có thể chứa event `NULL` hoặc tombstone, nhưng semantics downstream phải được thiết kế rõ.

> 💡 **Giải thích dễ hiểu:**
> Stream là nhật ký “đã xảy ra gì”, còn table là bảng tra “hiện giờ ra sao”. Gửi cùng key lần nữa là thêm một dòng nhật ký; khi diễn giải thành table thì dòng mới cập nhật trạng thái, còn tombstone giống phiếu xóa hồ sơ.

---

## How – Push Query vs Pull Query

| | Push Query (`EMIT CHANGES`) | Pull Query |
|--|------------------------------|------------|
| Hành vi | Giữ kết nối, phát các bản cập nhật khi có dữ liệu mới | Trả kết quả hữu hạn rồi **kết thúc** |
| Trên | Stream hoặc Table | Materialized Table (thường lookup theo key) |
| Giống | "subscribe" liên tục | Query DB kiểu request/response |
| Dùng | Pipeline, alert real-time | API tra cứu trạng thái hiện tại |

```sql
-- Push: liên tục (CLI hiển thị, hoặc app subscribe qua REST)
SELECT user_id, url FROM clicks WHERE url LIKE '/checkout%' EMIT CHANGES;

-- Pull: tra cứu điểm (materialized table) — trả về & dừng
SELECT total FROM clicks_per_user WHERE user_id = 'u123';
```

Push query *(truy vấn đẩy)* giữ kết nối và phát các bản cập nhật của stream hoặc table; `EMIT CHANGES` chỉ mô tả việc phát liên tục, không tự lưu kết quả thành topic. Muốn lưu kết quả phải dùng CSAS/CTAS. Pull query *(truy vấn kéo)* đọc giá trị hiện có trong materialized table, thường là lookup theo primary key, trả response hữu hạn rồi kết thúc. Table scan cần cấu hình/phiên bản phù hợp và không nên xem là truy vấn OLAP tùy ý.

> 💡 **Giải thích dễ hiểu:**
> Push giống đăng ký nhận thông báo mỗi khi trạng thái đổi; pull giống hỏi “giá trị hiện giờ là bao nhiêu?” rồi đóng cuộc gọi. Giá trị pull phụ thuộc state store và mức nhất quán của cluster, không mặc định là snapshot tuyến tính tuyệt đối; standby HA có thể trả dữ liệu hơi cũ nếu cho phép độ trễ.

---

## How – Persistent Query (CSAS / CTAS)

Tạo stream/table **mới** từ query → chạy liên tục, ghi kết quả ra topic mới và state store (đây là persistent query *(truy vấn bền vững)*). CSAS tạo stream; CTAS tạo table/materialized view dựa trên key.

```sql
-- CREATE STREAM AS SELECT (CSAS): lọc/biến đổi → topic mới
CREATE STREAM checkout_clicks AS
  SELECT user_id, url, ts FROM clicks WHERE url LIKE '/checkout%' EMIT CHANGES;

-- CREATE TABLE AS SELECT (CTAS): aggregation → materialized table
CREATE TABLE clicks_per_user AS
  SELECT user_id, COUNT(*) AS total
  FROM clicks GROUP BY user_id EMIT CHANGES;       -- GROUP BY → ra TABLE
```

> 💡 **Giải thích dễ hiểu:**
> `SELECT` thường chỉ đọc để trả kết quả cho client; `CSAS`/`CTAS` là nút “bật máy”, tạo query chạy lâu dài. `SHOW QUERIES [EXTENDED];` giúp kiểm tra trạng thái; `TERMINATE <query_id>;` dừng query (và cần quy trình riêng nếu muốn xóa topic/state).

---

## How – Key, Partitioning & Repartition

Kafka phân phối record theo partition của key. Join và aggregation theo key chỉ đúng khi các nguồn được **co-partitioning** *(cùng số partition và cùng quy tắc key)*. `PARTITION BY` đổi key đầu ra; ksqlDB có thể tạo repartition topic cho stream, nhưng table không thể tùy ý repartition như stream.

```sql
CREATE STREAM orders_by_customer AS
  SELECT * FROM orders
  PARTITION BY customer_id
  EMIT CHANGES;
```

Sau `PARTITION BY`, khóa mới trở thành `ROWKEY`; nếu vẫn cần cột `customer_id` trong value, dùng `AS_VALUE(customer_id)`. Key `NULL` có thể bị gửi ngẫu nhiên, làm join/aggregation khó đoán; hãy lọc hoặc `COALESCE` trước khi partition. Repartition thêm network/IO và có thể thay đổi thứ tự quan sát, vì vậy nên tạo key ngay từ producer khi có thể.

> 💡 **Giải thích dễ hiểu:**
> Hãy coi partition như các quầy xử lý. Hai nguồn muốn join phải đưa cùng khách hàng vào cùng quầy; đổi key là chuyển hàng giữa quầy, có chi phí và không giữ thứ tự toàn cục.

---

## How – Windowing & Aggregations

```sql
-- Tumbling window (cửa sổ cố định không chồng)
CREATE TABLE orders_per_min AS
  SELECT product_id, COUNT(*) AS cnt
  FROM orders
  WINDOW TUMBLING (SIZE 1 MINUTE, RETENTION 2 HOURS, GRACE PERIOD 30 SECONDS)
  GROUP BY product_id
  EMIT CHANGES;

-- Chỉ phát kết quả cuối sau khi window đóng + hết grace
CREATE TABLE final_orders_per_min AS
  SELECT product_id, COUNT(*) AS cnt
  FROM orders
  WINDOW TUMBLING (SIZE 1 MINUTE, GRACE PERIOD 30 SECONDS)
  GROUP BY product_id
  EMIT FINAL;

-- Hopping (chồng nhau), Session (theo khoảng nghỉ)
... WINDOW HOPPING (SIZE 5 MINUTE, ADVANCE BY 1 MINUTE, GRACE PERIOD 1 MINUTE) ...
... WINDOW SESSION (30 SECONDS, GRACE PERIOD 1 MINUTE) ...
```

Window dùng `ROWTIME` *(timestamp sự kiện mà ksqlDB gán/đọc)* để quyết định event thuộc cửa sổ nào. Event đến trễ sau `GRACE PERIOD` bị bỏ khỏi cửa sổ đã đóng; retention nên lớn hơn kích thước window + grace để state còn đủ lâu. Nếu không khai báo grace, ksqlDB có giá trị mặc định theo phiên bản (thường 24 giờ), nên production hãy đặt rõ.

`EMIT CHANGES` phát các cập nhật trung gian, còn `EMIT FINAL` chỉ phát một lần sau khi window đóng và hết grace; chọn theo nhu cầu dashboard liên tục hay báo cáo chốt sổ. `GROUP BY` tạo bảng changelog: cùng key có thể phát nhiều phiên bản và tombstone khi key bị xóa.

> 💡 **Giải thích dễ hiểu:**
> Một cửa sổ giống khay nhận đơn: grace là thời gian chờ đơn đến muộn, retention là thời gian giữ khay. Chốt sổ (`EMIT FINAL`) chỉ nên dùng khi chấp nhận chờ hết grace.

> Windowing/aggregation giống Kafka Streams (xem [../streams/kafka_streams.md](../streams/kafka_streams.md)); ksqlDB phơi ra qua SQL.

---

## How – Joins

```sql
-- Stream-Table join (enrichment: lookup trạng thái hiện tại, không cần WITHIN)
CREATE STREAM enriched_clicks AS
  SELECT c.user_id, c.url, u.name, u.tier
  FROM clicks c JOIN users u ON c.user_id = u.user_id EMIT CHANGES;

-- Stream-Stream join (bắt buộc có WITHIN; grace xử lý event đến trễ)
SELECT *
  FROM orders o JOIN payments p
  WITHIN 1 HOUR
  ON o.id = p.order_id
  EMIT CHANGES;
```

| Join | Yêu cầu | Kết quả |
|------|---------|---------|
| Stream-Table | Cùng key/partition; lookup không theo window | Enrichment (trạng thái tại lúc xử lý) |
| Stream-Stream | Cùng key/partition + `WITHIN` window | Tương quan hai sự kiện trong khoảng thời gian |
| Table-Table | Primary/foreign key phù hợp, cùng partition khi cần | Trạng thái kết hợp; không phải many-to-many |

Join cần **co-partitioning** *(cùng số partition và cùng quy tắc key)*. `WITHIN` giới hạn thời gian ghép stream–stream; cấu hình grace/retention của window và khả năng đến trễ cần được cân nhắc riêng. ksqlDB có thể tự tạo repartition topic cho stream; table không thể tùy ý repartition, nên thiết kế primary key/partition từ đầu. Record có key `NULL`, sai kiểu key hoặc chưa kịp cập nhật bảng dimension có thể không match; kiểm tra `KEY_FORMAT`, partition count và thời điểm cập nhật.

> 💡 **Giải thích dễ hiểu:**
> Join chỉ gặp nhau khi hai bản ghi đi vào cùng quầy partition. Stream–table giống tra danh bạ tại thời điểm event chạy; stream–stream giống ghép hai chuyến xe trong một khoảng giờ (`WITHIN`), không phải ghép mọi bản ghi từng xuất hiện.

---

## How – UDF/UDAF & Connectors

```sql
-- ksqlDB có thể quản Connect: tạo connector bằng SQL
CREATE SOURCE CONNECTOR pg_source WITH (
  'connector.class'='io.debezium.connector.postgresql.PostgresConnector', ...);

-- UDF tự viết (Java, annotation @Udf) → dùng như hàm SQL
SELECT my_custom_score(amount, tier) FROM orders EMIT CHANGES;
```

**UDF** *(user-defined function – hàm tự định nghĩa)* xử lý từng record; **UDAF** *(user-defined aggregate – hàm gom nhóm tự định nghĩa)* giữ state theo key; **UDTF** *(user-defined table function)* có thể phát nhiều dòng. Chúng chạy bên trong task ksqlDB, nên hàm nên deterministic, thread-safe và không gọi API/DB bên ngoài theo cách blocking hoặc có side effect: task có thể retry/reprocess.

Kafka Connect tạo source/sink connector; cần cài plugin jar, cấu hình quyền truy cập, secret/TLS và kiểm tra Schema Registry compatibility. `CREATE SOURCE CONNECTOR` chỉ là khai báo tài nguyên, không thay thế việc vận hành connector (health, lag, DLQ). Xem [connect.md](../streams/connect.md).

> 💡 **Giải thích dễ hiểu:**
> UDF giống hàm tiện ích trong SQL nhưng chạy nhiều lần trên server; nếu hàm gửi email hoặc ghi DB ngoài, retry có thể tạo tác dụng phụ lặp lại. Connector là cửa vào/cửa ra Kafka, cần quản lý như một dịch vụ production.

---

## Compare – ksqlDB vs Kafka Streams vs Flink

| | ksqlDB | Kafka Streams | Apache Flink |
|--|--------|---------------|--------------|
| Giao diện | SQL | Java/Scala library | SQL + Java/Scala/Python |
| Deploy | ksqlDB cluster | Nhúng trong app của bạn | Cluster Flink riêng (JobManager/TaskManager) |
| Linh hoạt | Thấp–TB (SQL) | **Cao** (full code) | **Cao**, đổi lại vận hành phức tạp |
| State backend | State store dựa Kafka/RocksDB | State store/RocksDB, changelog Kafka | RocksDB/heap + checkpoint |
| Nguồn dữ liệu | Chủ yếu Kafka | Chủ yếu Kafka | Đa nguồn (Kafka, file, CDC, JDBC...) |
| Khi dùng | Stream SQL nhanh, ít code, dữ liệu đã ở Kafka | Logic phức tạp trong microservice JVM | Pipeline lớn, event-time/đa nguồn hoặc cần runtime riêng |

> 💡 **Giải thích dễ hiểu:**
> ksqlDB phù hợp khi dữ liệu đã ở Kafka và team muốn SQL; Kafka Streams phù hợp khi cần kiểm soát từng processor trong ứng dụng JVM; Flink phù hợp khi cần nhiều nguồn và runtime event-time rộng hơn. Không có công cụ “mạnh nhất” cho mọi workload; hãy benchmark latency, throughput và chi phí vận hành.

---

## Trade-offs

- (+) Phát triển nhanh bằng SQL, không cần app riêng, tích hợp Schema Registry/Connect, hợp data engineer.
- (−) Ít linh hoạt hơn Kafka Streams (logic đặc thù, control fine-grained khó); debug topology sinh tự động khó hơn.
- (−) ksqlDB cluster là thành phần phải vận hành/HA; state lớn → quản RocksDB, changelog và rebalance như Kafka Streams.
- (−) `processing.guarantee='exactly_once_v2'` chỉ bao phủ đọc–xử lý–ghi Kafka/state trong phạm vi hỗ trợ; DB/API/email bên ngoài vẫn cần idempotency hoặc outbox. Downstream cũng phải xử lý giao dịch phù hợp (`read_committed`).
- (−) Pull query chỉ trên materialized table, thường lookup theo key (không phải mọi truy vấn tùy ý như DB OLAP); HA standby có thể trả giá trị hơi cũ nếu bật đọc standby.
- (−) Bảo mật gồm REST/CLI authentication, Kafka ACL, TLS, Schema Registry compatibility, secret trong connector và kiểm soát supply chain của UDF jar.
- (−) Mỗi query cluster phải dùng cùng `ksql.service.id`; parallelism bị giới hạn bởi số partition. Repartition topic tăng network/IO và chi phí lưu trữ.

> 💡 **Giải thích dễ hiểu:**
> Exactly-once giống giao dịch giữa các kho Kafka, không phải “lá chắn” cho mọi hệ thống bên ngoài. Hãy giả định retry có thể xảy ra và thiết kế consumer/side effect cho an toàn.

---

## Real-world

```sql
-- Pipeline điển hình: làm giàu + tổng hợp + phơi qua pull query cho API
CREATE STREAM enriched AS SELECT ... JOIN users ... EMIT CHANGES;     -- enrichment
CREATE TABLE fraud_score AS                                          -- aggregation real-time
  SELECT user_id, COUNT(*) FILTER (WHERE amount > 1000) AS big_txns
  FROM enriched
  WINDOW TUMBLING (SIZE 10 MINUTE, GRACE PERIOD 2 MINUTE)
  GROUP BY user_id
  EMIT CHANGES;
-- App gọi pull query: SELECT big_txns FROM fraud_score WHERE user_id='u1';  → cảnh báo gian lận
```

- Use cases: real-time ETL/enrichment, alerting, materialized view cho dashboard, anomaly/fraud detection nhẹ.
- Nặng/phức tạp/đa nguồn → cân nhắc Flink. Logic nghiệp vụ sâu trong service → Kafka Streams.

Vận hành production: dùng `SHOW QUERIES [EXTENDED]`, `DESCRIBE <name> EXTENDED` và `EXPLAIN <query>` để kiểm tra topology/key/state; theo dõi trạng thái `RUNNING`, `ERROR`, `UNRESPONSIVE`, consumer lag, throughput và disk của state store. Tăng ksqlDB server giúp phân phối task, nhưng throughput vẫn cần đủ partition ở source/output; thay đổi key có thể tạo repartition topic mới.

> 💡 **Giải thích dễ hiểu:**
> Luồng trên chấp nhận phát điểm gian lận trung gian. Nếu chỉ muốn cảnh báo sau khi chốt 10 phút + grace, đổi sang `EMIT FINAL` và chấp nhận độ trễ đó. Bảo vệ REST endpoint, ACL/topic và secret connector trước khi mở cho ứng dụng.

---

## Ghi chú – Chủ đề tiếp theo
> Chủ đề tiếp theo: [event_driven_architecture.md](../patterns/event_driven_architecture.md) — thiết kế topic/partition/key, event design (notification vs state transfer vs event sourcing), EDA patterns (CQRS, outbox, saga, DLQ), idempotent consumer và delivery semantics thực chiến.

> Liên quan: [kafka_streams.md](../streams/kafka_streams.md) (nền tảng bên dưới), [schema_registry.md](schema_registry.md) (schema/compatibility), [connect.md](../streams/connect.md) (connector qua ksqlDB).

> Tài liệu chính thức: [Queries overview](https://docs.confluent.io/platform/current/ksqldb/concepts/queries.html), [Pull queries](https://docs.confluent.io/platform/current/ksqldb/developer-guide/ksqldb-reference/select-pull-query.html), [Windows & time](https://docs.confluent.io/platform/current/ksqldb/concepts/time-and-windows-in-ksqldb-queries.html), [Processing guarantees](https://docs.confluent.io/platform/current/ksqldb/operate-and-deploy/processing-guarantees.html).

> Keywords: `EMIT CHANGES`, `EMIT FINAL`, materialized view, `SHOW QUERIES`/`TERMINATE`, `PARTITION BY`/`GROUP BY`, `LATEST_BY_OFFSET`/`EARLIEST_BY_OFFSET`, `AS_VALUE`/`ROWKEY`/`ROWTIME`, grace/retention, headless mode (production), interactive vs headless, Flink SQL (alternative).

---

*Cập nhật lần cuối: 2026-07-22*
