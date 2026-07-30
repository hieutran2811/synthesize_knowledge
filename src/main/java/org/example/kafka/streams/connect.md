# Kafka Connect & CDC – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)
>
> Phạm vi phiên bản: Apache Kafka Connect 4.3 và Debezium stable tại thời điểm cập nhật. Cấu hình riêng của connector/vendor vẫn phải đối chiếu đúng version đang triển khai.

---

## What – Kafka Connect là gì?

**Kafka Connect** là framework *(bộ khung phần mềm)* tích hợp dữ liệu trong/ngoài Kafka — không cần tự viết toàn bộ producer/consumer code. Có nhiều connector *(thành phần kết nối một hệ thống)* do Apache, vendor và cộng đồng cung cấp (JDBC, object storage, Elasticsearch, MongoDB, PostgreSQL CDC...), nhưng số lượng, tính năng và chất lượng phụ thuộc plugin/version.

**CDC (Change Data Capture)** *(thu thập thay đổi dữ liệu)* là một nhóm source connector đọc thay đổi đã commit từ database log/WAL/binlog thay vì polling toàn bộ bảng.

```
Data integration patterns:
  Source connector *(đọc từ hệ thống ngoài)*: external system → Kafka topic
  Sink connector *(ghi ra hệ thống ngoài)*:   Kafka topic → external system

Without Connect: custom producer/consumer code (brittle, maintenance)
With Connect:    declarative config, distributed execution, monitoring

Architecture:
  External DB → Source Connector → Kafka Topic → Sink Connector → Elasticsearch

  Kafka Connect cluster (Workers):
  Worker *(tiến trình thực thi)*: JVM (Java Virtual Machine) process chạy connector/task và tham gia worker group
  Connector *(công việc logic)*: logical job (config + task management)
  Task *(đơn vị công việc)*: work unit do connector tạo; số task phụ thuộc connector/source partitions,
        tables, Kafka partitions và tasks.max — không mặc định 1 task = 1 partition
```

Source connector đọc từ hệ thống ngoài rồi ghi Kafka; sink connector đọc Kafka rồi ghi hệ thống ngoài. Connector quyết định cách chia work và có thể tạo ít task hơn `tasks.max` nếu nguồn/đích không hỗ trợ song song.

> 💡 **Giải thích dễ hiểu — connector là quản đốc, task là nhân viên:**
> Quản đốc giữ cấu hình và phân ca; worker là tòa nhà chứa nhân viên. Một nhân viên có thể phụ trách nhiều bàn, một bàn có thể cần nhiều nhân viên tùy connector. `tasks.max` là số người tối đa được cấp, không phải lời hứa rằng từng partition sẽ có đúng một người.

---

## Components – Connect Architecture

```
Standalone mode:
  Single worker, config in file, source offsets thường ở file
  Use: development/test hoặc workload nhỏ chấp nhận single point of failure

Distributed mode (production):
  Multiple workers, config via REST API
  Workers tham gia group và tự rebalance task
  Worker failure → task được khởi động lại trên worker khác

Internal topics:
  connect-configs:   connector configurations (thường 1 partition, compacted)
  connect-offsets:   source connector offsets (nhiều partition, compacted)
  connect-status:    connector/task status (replicated, thường compacted)
```

Distributed mode dựa trên Kafka group management và ba internal topics. Mất các topic này có thể làm cluster mất cấu hình, vị trí nguồn hoặc trạng thái; hãy tạo chúng với partition/replication/cleanup policy phù hợp thay vì để broker auto-create theo default không kiểm soát.

> 💡 **Giải thích dễ hiểu — internal topics là sổ điều hành của cả đội:**
> `connect-configs` là sổ giao ca, `connect-offsets` là bookmark từng nguồn, còn `connect-status` là bảng chấm công. Worker có thể đổi ca vì sổ nằm trong Kafka, nhưng nếu sổ cấu hình hoặc bookmark bị mất thì đội không biết phải làm gì tiếp.

---

## How – Distributed Mode Setup

```properties
# worker.properties
bootstrap.servers=broker1:9092,broker2:9092,broker3:9092
group.id=connect-cluster                        # all workers with same group = same cluster

# Internal topics
config.storage.topic=connect-configs
offset.storage.topic=connect-offsets
status.storage.topic=connect-status
config.storage.replication.factor=3
offset.storage.replication.factor=3
status.storage.replication.factor=3
# Create internal topics explicitly with the desired partitions and:
# cleanup.policy=compact, replication.factor >= 3 (depending on cluster)

# Converters *(bộ chuyển đổi Connect data ↔ bytes Kafka)*
# Schema Registry *(kho lưu schema dùng chung cho các converter)* nếu dùng Avro/Protobuf
key.converter=io.confluent.connect.avro.AvroConverter
value.converter=io.confluent.connect.avro.AvroConverter
key.converter.schema.registry.url=http://schema-registry:8081
value.converter.schema.registry.url=http://schema-registry:8081
# Or JSON:
# key.converter=org.apache.kafka.connect.json.JsonConverter
# value.converter=org.apache.kafka.connect.json.JsonConverter
# key.converter.schemas.enable=false
# value.converter.schemas.enable=false

# Offset flush: crash before this commit point may replay source records
offset.flush.interval.ms=60000
offset.flush.timeout.ms=5000

# Optional worker-level exactly-once *(mỗi bản ghi đúng một lần theo semantics Kafka)* source support
# (only compatible connectors)
# exactly.once.source.support=enabled

# REST API (rest.advertised.* must be reachable by other workers)
rest.host.name=0.0.0.0
rest.port=8083
rest.advertised.host.name=connect-worker-1    # for inter-worker routing
rest.advertised.port=8083
# For HTTP/HTTPS listener-based deployments, configure listeners and
# rest.advertised.listener according to the Kafka Connect version.

# Plugin path
plugin.path=/opt/kafka/plugins
# Mặc định tương thích rộng; kiểm tra plugin trước khi chuyển sang service_load
plugin.discovery=hybrid_warn

# Start worker
bin/connect-distributed.sh config/worker.properties
```

`key.converter` và `value.converter` quyết định cách record connector được serialize, độc lập với connector class. Avro/Protobuf thường đi cùng Schema Registry; JSON có thể không mang schema nhưng dễ mất contract type/evolution nếu không quản lý version. Converter không phải serializer Kafka producer thuần túy: nó chuyển giữa Connect data model và bytes trên Kafka.

`offset.flush.interval.ms` là checkpoint, không phải transaction boundary. Source task có thể đã ghi record vào Kafka nhưng chưa flush source offset khi worker crash, dẫn tới replay; sink task cũng phụ thuộc connector để commit offset sau khi đích xác nhận.

`exactly.once.source.support=enabled` phù hợp khi tạo Connect cluster mới. Với cluster đang chạy, Kafka yêu cầu hai vòng rolling update: trước hết đặt `preparing` trên mọi worker, sau đó mới chuyển mọi worker sang `enabled`. Ngay cả khi worker đã bật, connector vẫn phải hỗ trợ; có thể đặt `exactly.once.support=required` trong source connector để yêu cầu bước kiểm tra trước khi chạy.

> 💡 **Giải thích dễ hiểu — converter là nhân viên phiên dịch, Schema Registry là từ điển chung:**
> Connector nói bằng `Struct` của Connect, còn Kafka lưu bytes. Converter dịch qua lại; Avro/Protobuf kèm mã schema giúp các đội khác hiểu cùng một hợp đồng. Nếu worker ngã trước khi ghi bookmark, lần làm ca sau sẽ đọc lại phần chưa được đánh dấu — đó là lý do cần idempotent sink.

---

## How – Plugin isolation, discovery và upgrade

Connect nạp connector, converter và SMT từ `plugin.path`. Nên đặt mỗi plugin cùng toàn bộ dependency của nó trong một thư mục con riêng, không chép dependency tùy tiện vào classpath của worker. Classloader isolation giúp hai connector có thể dùng dependency khác version, nhưng không chữa được plugin đóng gói thiếu hoặc xung đột thư viện nằm ngoài vùng cô lập.

`plugin.discovery=hybrid_warn` là mặc định của Kafka 4.3 và tương thích với plugin cũ; worker vừa scan vừa dùng `ServiceLoader`, đồng thời cảnh báo plugin chưa tương thích. `service_load` khởi động nhanh hơn nhưng chỉ nên bật sau khi CI hoặc môi trường thử nghiệm xác nhận toàn bộ plugin hỗ trợ cơ chế này; `hybrid_fail` hữu ích để biến plugin không tương thích thành lỗi kiểm tra rõ ràng.

Quy trình nâng cấp plugin an toàn:

1. Pin artifact, checksum và version; thử với đúng Kafka/Java và hệ thống nguồn/đích.
2. Cài cùng bộ plugin vào **mọi worker** rồi rolling restart từng worker.
3. Kiểm tra startup log và gọi `GET /connector-plugins` trực tiếp trên từng worker.
4. Xác nhận connector/task trở lại `RUNNING`, record rate và error rate bình thường trước khi sang worker tiếp theo.
5. Chỉ xóa version cũ sau khi đã qua cửa sổ rollback.

`GET /connector-plugins` chỉ quét worker xử lý request, không chứng minh cả cluster có cùng artifact. Nếu load balancer chuyển request giữa các worker trong lúc rolling upgrade, kết quả có thể lúc có lúc không; vì vậy inventory plugin phải được kiểm tra theo từng node.

> 💡 **Giải thích dễ hiểu — mỗi plugin là một hộp dụng cụ niêm phong:**
> Mỗi thợ cần nhận đúng cùng một hộp. Nếu worker A có driver mới còn worker B không có, task chuyển ca sang B sẽ thất bại dù API qua load balancer từng báo rằng plugin “đã cài”.

---

## How – JDBC Source Connector

**JDBC Source Connector** *(connector đọc database qua JDBC)* thường polling query theo mode `incrementing`, `timestamp` hoặc `timestamp+incrementing`. Đây là at-least-once source: crash trước khi ghi source offset có thể phát lại record; nó không tự phát hiện mọi delete như CDC log.

Ví dụ JSON dưới đây là cấu hình minh họa; các dòng comment `#` cần bỏ khi gửi request JSON thật.

```bash
# Create JDBC source connector
POST http://localhost:8083/connectors
Content-Type: application/json

{
  "name": "orders-jdbc-source",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "connection.url": "jdbc:postgresql://db:5432/mydb",
    "connection.user": "kafka_connect",
    "connection.password": "${file:/opt/secrets/db.properties:password}",  # externalize secrets

    "mode": "timestamp+incrementing",    # bulk | incrementing | timestamp | timestamp+incrementing
    "incrementing.column.name": "id",
    "timestamp.column.name": "updated_at",
    "timestamp.delay.interval.ms": 5000, # wait 5s before processing (for in-flight transactions)

    "table.whitelist": "orders,payments",
    "query": "",                         # or custom query instead of table.whitelist

    "topic.prefix": "db.",               # → topics: db.orders, db.payments
    "poll.interval.ms": 5000,
    "batch.max.rows": 1000,

    "numeric.mapping": "best_fit",       # map numeric types to specific Java types

    "transforms": "addTimestamp,maskPII",
    "transforms.addTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
    "transforms.addTimestamp.timestamp.field": "kafka_ingested_at",
    "transforms.maskPII.type": "org.apache.kafka.connect.transforms.MaskField$Value",
    "transforms.maskPII.fields": "credit_card,ssn",
    "transforms.maskPII.replacement": "***MASKED***"
  }
}
```

`incrementing` chỉ phát hiện row mới; `timestamp` có thể bỏ sót khi timestamp trùng hoặc commit out-of-order; `timestamp+incrementing` thường an toàn hơn khi cột timestamp đủ chính xác và ID tăng nghiêm ngặt. `timestamp.delay.interval.ms` làm trễ truy vấn để transaction có timestamp cũ kịp commit, nhưng không biến polling thành CDC và không tự phát hiện hard delete.

> 💡 **Giải thích dễ hiểu — JDBC polling là nhân viên đi kiểm kê, CDC là camera kho:**
> Polling định kỳ nhìn các hàng có “số ID/thời gian mới”, nên có thể bỏ sót thay đổi không khớp cột theo dõi hoặc thấy lại cùng hàng. CDC đọc nhật ký giao dịch nên biết insert/update/delete theo thứ tự commit, đổi lại cần quyền và cấu hình database chuyên biệt.

---

## How – Elasticsearch Sink Connector

**Sink connector** *(connector đẩy record ra hệ thống đích)* đọc topic bằng consumer group, batch record và ghi Elasticsearch. `tasks.max` là trần số task; connector chỉ dùng được số task mà topic partition, connector và đích cho phép.

Ví dụ JSON minh họa; bỏ comment trước khi gửi request thật và kiểm tra compatibility của Elasticsearch/connector version (ví dụ `type.name` có thể không còn dùng trong Elasticsearch hiện đại).

```bash
POST http://localhost:8083/connectors
{
  "name": "orders-elasticsearch-sink",
  "config": {
    "connector.class": "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
    "tasks.max": "3",

    "topics": "db.orders,db.payments",
    "connection.url": "https://elasticsearch:9200",
    "connection.username": "elastic",
    "connection.password": "${file:/opt/secrets/es.properties:password}",

    "type.name": "_doc",
    "key.ignore": false,                 # use Kafka key as document ID
    "schema.ignore": false,

    "index.name": "${topic}",            # use topic name as index name
    # Or: custom index per topic:
    # "topic.index.map": "db.orders:orders,db.payments:payments",

    "batch.size": 1000,
    "linger.ms": 1000,                   # wait 1s to batch
    "max.retries": 10,
    "retry.backoff.ms": 100,

    "behavior.on.null.values": "delete", # null value → delete document (tombstone)
    "behavior.on.malformed.documents": "warn",

    "transforms": "routeToIndex",
    "transforms.routeToIndex.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
    "transforms.routeToIndex.exclude": "internal_field,debug_data"
  }
}
```

Sink thường có at-least-once: worker có thể retry batch sau khi đích đã ghi nhưng offset chưa commit. Dùng Kafka key làm document ID (`key.ignore=false`) giúp Elasticsearch update cùng ID có tính idempotent hơn; đây là guarantee của cấu hình đích, không phải exactly-once chung cho mọi sink.

> 💡 **Giải thích dễ hiểu — sink là quầy giao hàng có thể giao lại:**
> Nhân viên phải ghi bookmark sau khi kho đích xác nhận. Nếu mất điện ngay giữa “đã nhận hàng” và “đã ghi bookmark”, ca sau giao lại kiện. Dùng mã đơn ổn định làm document ID biến lần giao lại thành cập nhật cùng hồ sơ thay vì tạo bản sao.

---

## How – SMT (Single Message Transforms)

**SMT (Single Message Transform)** *(biến đổi từng record)* là bước nhẹ, stateless *(không giữ state giữa các record)* trong pipeline của một connector. Source áp dụng trước khi ghi Kafka; sink áp dụng sau khi đọc Kafka.

```bash
# SMTs: lightweight, stateless record transformations in connector pipeline
# Applied BEFORE writing to Kafka (source) or AFTER reading from Kafka (sink)

# Built-in SMTs:
# InsertField:    add field (timestamp, offset, partition)
# ReplaceField:   include/exclude/rename fields
# MaskField:      mask sensitive fields
# ValueToKey:     promote value field to record key
# ExtractField:   extract nested field
# Cast:           type conversion
# TimestampConverter: convert timestamp formats
# Filter:         drop records matching condition
# RegexRouter: dynamic topic routing; TopicNameMatches: predicate matching

# Example: ValueToKey + ExtractField for proper Kafka keying
"transforms": "extractKey,addSource",
"transforms.extractKey.type": "org.apache.kafka.connect.transforms.ValueToKey",
"transforms.extractKey.fields": "order_id",
"transforms.addSource.type": "org.apache.kafka.connect.transforms.InsertField$Value",
"transforms.addSource.static.field": "source_system",
"transforms.addSource.static.value": "postgres-orders",

# TimestampConverter: ISO string → epoch millis
"transforms": "tsConvert",
"transforms.tsConvert.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
"transforms.tsConvert.field": "created_at",
"transforms.tsConvert.target.type": "unix",
"transforms.tsConvert.format": "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"

# Filter: dùng cùng Predicate để drop record theo điều kiện
"transforms": "filter",
"transforms.filter.type": "org.apache.kafka.connect.transforms.Filter",
"predicates": "internalTopic",
"predicates.internalTopic.type": "org.apache.kafka.connect.transforms.predicates.TopicNameMatches",
"predicates.internalTopic.pattern": "internal-test-.*",
"transforms.filter.predicate": "internalTopic"
```

SMT không thay thế Kafka Streams cho join/window/stateful processing. Filter cần Predicate cấu hình riêng; `Filter` xóa record khỏi pipeline nên phải kiểm soát kỹ để không biến lỗi dữ liệu thành mất dữ liệu im lặng.

> 💡 **Giải thích dễ hiểu — SMT là trạm đóng gói trên băng chuyền:**
> Trạm có thể đổi nhãn, che số thẻ hoặc lấy một trường làm mã kiện, nhưng không nhớ kiện trước đó và không biết tổng doanh số. Việc cần nhìn nhiều record, join hoặc giữ state nên đưa sang Streams/Flink, còn SMT chỉ xử lý biến đổi cục bộ.

---

## How – Debezium CDC (Change Data Capture)

**Debezium** *(nền tảng CDC)* đọc transaction log đã commit của database và phát change event. Với PostgreSQL, **WAL (Write-Ahead Log)** *(nhật ký ghi trước)* được đọc qua logical replication slot; **LSN (Log Sequence Number)** là vị trí nguồn dùng để resume.

```
Debezium: open-source CDC platform, reads database WAL/binlog
  Postgres:    reads replication slot (WAL)
  MySQL:       reads binlog (binary log)
  MongoDB:     reads oplog
  SQL Server:  reads CDC tables
  Oracle:      reads LogMiner

CDC events:
  c (create):  new row inserted
  u (update):  row updated (before + after image)
  d (delete):  row deleted (before image + null after)
  r (read):    snapshot event (initial load)
```

Một pipeline CDC thường có hai phase: snapshot nhất quán ban đầu rồi stream thay đổi từ đúng vị trí log của snapshot. Snapshot có thể phát lại sau crash hoặc chồng với event streaming; downstream nên dùng primary key + source metadata (LSN/transaction/sequence) để deduplicate và không giả định thứ tự toàn cục giữa nhiều table/topic.

> 💡 **Giải thích dễ hiểu — CDC là chụp ảnh kho rồi xem camera từ đúng khung hình:**
> Snapshot cho biết toàn bộ hàng đang có; WAL/binlog là camera ghi thay đổi sau đó. Nếu worker ngã khi chưa lưu bookmark, ca sau có thể chiếu lại vài khung hình. Đó là at-least-once và downstream cần xử lý event lặp idempotent.

```bash
# Debezium PostgreSQL Source Connector
POST http://localhost:8083/connectors
{
  "name": "postgres-cdc-orders",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",                    # thường 1 task cho một PostgreSQL WAL stream

    "database.hostname": "postgres",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "${file:/opt/secrets/pg.properties:password}",
    "database.dbname": "mydb",
    "topic.prefix": "mydb",              # unique logical namespace (used in topic names)

    # Topic naming: {topic.prefix}.{schema}.{table}
    # → mydb.public.orders, mydb.public.payments

    "slot.name": "debezium_orders_slot", # unique replication slot per connector
    "plugin.name": "pgoutput",           # supported: pgoutput | decoderbufs
    "publication.name": "dbz_orders_publication",
    "publication.autocreate.mode": "filtered",

    # Tables to capture
    "table.include.list": "public.orders,public.payments,public.customers",

    # Initial snapshot
    "snapshot.mode": "initial",          # initial | initial_only | no_data | always | when_needed
    "snapshot.isolation.mode": "repeatable_read",

    # Output format
    "decimal.handling.mode": "precise",  # giữ chính xác DECIMAL/NUMERIC; double có thể làm tròn
    "time.precision.mode": "connect",
    "tombstones.on.delete": "true",      # send tombstone after delete for compaction

    # Transforms: extract just the after-state value
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.delete.tombstone.handling.mode": "rewrite",
    "transforms.unwrap.add.fields": "op,table,lsn,source.ts_ms",
    "transforms.unwrap.add.headers": "db,table"
  }
}
```

```
Debezium event structure (without ExtractNewRecordState):
{
  "before": { ... },     # row state before change (null for inserts)
  "after":  { ... },     # row state after change (null for deletes)
  "source": {
    "connector": "postgresql",
    "db": "mydb",
    "table": "orders",
    "lsn": 12345678,      # PostgreSQL WAL LSN
    "ts_ms": 1704067200000
  },
  "op": "c",             # c|u|d|r
  "ts_ms": 1704067200100
}

After ExtractNewRecordState (unwrap):
  → Just the "after" fields + added metadata (op, table, ts_ms)
  → Much simpler for downstream consumers
```

Debezium thường dùng primary key làm Kafka key, giúp các thay đổi của cùng row đi cùng partition và giữ thứ tự trong partition đó. Không có ordering toàn cục giữa các table/topic; transaction metadata/LSN cần được dùng nếu downstream cần tái dựng thứ tự commit.

Với `pgoutput`, mỗi connector cần `slot.name` riêng và nên có `publication.name` riêng. `publication.autocreate.mode=filtered` tạo/cập nhật publication theo include/exclude list nếu account đủ quyền; production thường để DBA tạo publication tối thiểu trước rồi dùng mode `disabled` để giảm quyền runtime. Thay đổi `table.include.list` không tự đảm bảo publication do DBA quản lý đã chứa bảng mới.

Replication slot giữ WAL cho tới khi connector xác nhận LSN đã xử lý. Connector dừng lâu hoặc database ít traffic có thể làm WAL phình lớn; phải theo dõi slot lag và không xóa slot tùy tiện. `slot.drop.on.stop` nên giữ mặc định `false` ở production: slot và source offset là một cặp checkpoint, tạo slot mới không phục hồi được WAL lịch sử đã bị database xóa. Khi source offset chưa flush, restart có thể phát duplicate nhưng không nên bỏ event để “tránh trùng”.

Các mode snapshot cần hiểu theo mục đích: `initial` chụp khi chưa có offset; `initial_only` chụp xong rồi dừng; `no_data` không chụp dữ liệu và chỉ an toàn khi WAL còn đủ lịch sử; `when_needed` chụp khi thiếu offset hoặc vị trí log không còn; `always` chụp mỗi lần khởi động. Giá trị cũ `never` không còn nằm trong tập mode stable hiện tại, nên tránh sao chép cấu hình từ tutorial cũ.

`decimal.handling.mode=precise` giữ `DECIMAL`/`NUMERIC` theo logical type và là lựa chọn an toàn cho tiền. `double` dễ dùng hơn nhưng có thể mất độ chính xác; chỉ đổi khi consumer contract chấp nhận rõ trade-off này.

Exactly-once của source chỉ khả thi khi worker bật `exactly.once.source.support=enabled`, connector tuyên bố hỗ trợ transaction boundaries và pipeline downstream đọc/ghi với semantics tương ứng. Debezium mặc định cần được thiết kế như at-least-once và idempotent; Kafka transaction không làm side effect ngoài Kafka exactly-once.

> 💡 **Giải thích dễ hiểu — LSN là số mét của cuộn phim, replication slot giữ cuộn phim chưa xem:**
> Nếu camera dừng, kho phải giữ cuộn phim từ số mét cuối cùng. Giữ quá lâu làm kho đầy; xóa cuộn trước khi nhân viên xem xong làm mất lịch sử. Khi xem lại từ số mét cũ, vài khung hình trùng là chấp nhận được nếu màn hình đích cập nhật theo khóa ổn định.

---

## How – MirrorMaker2 *(nhân bản giữa các cluster Kafka)* (Cross-Cluster Replication)

```
MirrorMaker2: replicate topics between Kafka clusters
  Uses Kafka Connect framework internally
  Supports: active-active, active-passive, hub-spoke topologies

Replicated topics naming:
  source.cluster.topic-name (namespaced to avoid conflicts)
  Can be remapped with custom rules
```

```properties
# mm2.properties (MirrorMaker2 config)
clusters = us-east, eu-west

us-east.bootstrap.servers = us-east-broker:9092
eu-west.bootstrap.servers = eu-west-broker:9092

# What to replicate
us-east->eu-west.enabled = true
us-east->eu-west.topics = orders, payments, user-events
us-east->eu-west.topics.exclude = internal-*, .*_changelog

# Replication factor for mirrored topics in eu-west
us-east->eu-west.replication.factor = 3

# Offset sync: keep consumer group offsets in sync
us-east->eu-west.sync.group.offsets.enabled = true
us-east->eu-west.sync.group.offsets.interval.seconds = 60

# Heartbeat interval (check connector health)
us-east->eu-west.heartbeat.interval.seconds = 10

# Consumer group replication
us-east->eu-west.groups = order-processor, payment-processor
us-east->eu-west.groups.exclude = console-consumer-*

# Replication lag: alert from MM2 metrics/heartbeat, not an MM2 config key

# Start MirrorMaker2
bin/connect-mirror-maker.sh mm2.properties

# Monitor MirrorMaker2 via Connect REST API
GET http://localhost:8083/connectors
GET http://localhost:8083/connectors/MirrorSourceConnector/status
GET http://localhost:8083/connectors/MirrorCheckpointConnector/status
```

MirrorMaker2 (MM2) chạy bằng Kafka Connect và ghép các source, checkpoint, heartbeat connector. Tên topic thường được thêm tên cluster nguồn để tránh đụng độ, nhưng replication policy và quy tắc đổi tên có thể cấu hình; đừng hard-code rằng mọi môi trường đều dùng `source.cluster.topic-name`. Tên thuộc tính lọc topic có thể khác hoặc được alias giữa các phiên bản, vì vậy hãy kiểm tra `connect-mirror-maker` cùng version trước khi triển khai.

Offset sync giúp consumer tiếp tục gần vị trí cũ khi failover, không phải cơ chế giải quyết conflict cho active-active. Cần thiết kế key, hướng replicate một chiều/hai chiều, chống loop và thứ tự giữa topic; hãy đo replication lag thay vì chỉ dựa vào heartbeat.

> 💡 **Giải thích dễ hiểu — MM2 là đội chuyển kho giữa hai thành phố:**
> Source connector chở hàng, heartbeat là cuộc gọi báo “xe còn chạy”, còn checkpoint là sổ ghi xe đã giao đến đâu. Sổ đó giúp tiếp tục chuyến đi, nhưng không tự quyết định hai thành phố cùng sửa một đơn hàng thì ai thắng.

---

## How – Connect REST API *(giao diện HTTP điều khiển Connect)*

REST API là mặt điều khiển vòng đời connector: tạo, đọc, cập nhật, pause/stop/resume, restart task, quản lý offset và xóa. Trong distributed mode, request có thể được chuyển tới worker đang giữ connector; `rest.advertised.*`/listener phải truy cập được giữa các worker. REST mặc định không tự có authentication, trong khi plugin có thể chạy code tùy ý; chỉ mở endpoint cho principal tin cậy và bảo vệ bằng TLS, authentication/authorization hoặc gateway của môi trường. Các ví dụ dưới đây chỉ minh họa, không phải lệnh shell hoàn chỉnh.

```bash
# List connectors
GET http://localhost:8083/connectors
GET http://localhost:8083/connectors?expand=status&expand=info

# Get connector status
GET http://localhost:8083/connectors/orders-jdbc-source/status

# Pause giữ resource của task để resume nhanh; stop giải phóng task/resource
PUT http://localhost:8083/connectors/orders-jdbc-source/pause
PUT http://localhost:8083/connectors/orders-jdbc-source/stop
PUT http://localhost:8083/connectors/orders-jdbc-source/resume

# Restart connector or task
POST http://localhost:8083/connectors/orders-jdbc-source/restart?includeTasks=true&onlyFailed=true
POST http://localhost:8083/connectors/orders-jdbc-source/tasks/0/restart

# PUT thay toàn bộ config; PATCH chỉ cập nhật key gửi lên, null là xóa key
PUT http://localhost:8083/connectors/orders-jdbc-source/config
{ ... new config ... }
PATCH http://localhost:8083/connectors/orders-jdbc-source/config
{ "poll.interval.ms": "10000" }

# Read current connector offsets
GET http://localhost:8083/connectors/orders-jdbc-source/offsets

# Delete connector
DELETE http://localhost:8083/connectors/orders-jdbc-source

# List plugins
GET http://localhost:8083/connector-plugins

# Validate connector config
PUT http://localhost:8083/connector-plugins/JdbcSourceConnector/config/validate
{ ... config ... }

# Worker info
GET http://localhost:8083/
```

`PUT /config` thay toàn bộ cấu hình connector nên phải gửi đầy đủ thuộc tính cần giữ; `PATCH /config` phù hợp cho thay đổi nhỏ nhưng vẫn có thể làm connector/task restart. Restart riêng task chỉ xử lý task đó; restart connector có thể khởi tạo lại cả connector và các task. Endpoint validate chỉ kiểm tra plugin/worker nhận request, không thay thế kiểm thử quyền database, schema, throughput hay tương thích đích.

### Sửa hoặc reset offset an toàn

Offset là checkpoint quyết định dữ liệu nào sẽ được đọc lại hoặc bỏ qua. Luôn lấy bản chụp `GET /offsets`, ghi rõ lý do/owner và kiểm tra retention của nguồn trước khi thay đổi.

```bash
# 1. Stop connector; PAUSED chưa đủ điều kiện để sửa offset
PUT http://localhost:8083/connectors/orders-jdbc-source/stop

# 2. Chờ connector và mọi task chuyển sang STOPPED, rồi lưu response để audit
GET http://localhost:8083/connectors/orders-jdbc-source/status
GET http://localhost:8083/connectors/orders-jdbc-source/offsets

# 3a. PATCH một source offset — partition/offset là contract riêng của connector
PATCH http://localhost:8083/connectors/orders-jdbc-source/offsets
{
  "offsets": [
    {
      "partition": { "... source partition fields ...": "..." },
      "offset": { "... source position fields ...": "..." }
    }
  ]
}

# 3b. Hoặc reset toàn bộ offset; đây là thao tác có blast radius lớn
DELETE http://localhost:8083/connectors/orders-jdbc-source/offsets

# 4. Đọc lại offset, rồi mới resume và theo dõi duplicate/gap/error
GET http://localhost:8083/connectors/orders-jdbc-source/offsets
PUT http://localhost:8083/connectors/orders-jdbc-source/resume
```

`PATCH` và `DELETE /offsets` yêu cầu connector tồn tại và ở trạng thái `STOPPED`. Với source connector, cấu trúc `partition`/`offset` do chính connector định nghĩa; không tự đoán LSN, timestamp hay ID từ connector khác. Đưa checkpoint lùi tạo replay/duplicate; đưa tiến có thể bỏ qua dữ liệu; reset toàn bộ có thể kích hoạt snapshot hoặc đọc lại từ đầu tùy connector. Với Debezium, còn phải xác nhận LSN tương ứng vẫn tồn tại trong replication slot/WAL trước khi resume.

> 💡 **Giải thích dễ hiểu — REST là bảng điều khiển của nhà máy:**
> Pause là giữ nguyên máy nhưng ngừng băng chuyền; stop là tắt máy và trả resource. Offset là số thứ tự kiện hàng: kéo số lùi sẽ giao lại, đẩy số tiến có thể bỏ kiện. Vì vậy phải chụp trạng thái và kiểm tra nguồn trước khi đổi.

---

## Why – Kafka Connect vs Custom Code

```
Custom producer/consumer:
  ✅ Full control
  ❌ Boilerplate: offset management, error handling, retries, schema evolution
  ❌ Each integration = new codebase to maintain
  ❌ You must build delivery semantics, DLQ and monitoring yourself

Kafka Connect:
  ✅ Declarative: JSON config, no code
  ✅ Many community/vendor connectors (quality and support vary)
  ✅ Common error handling, DLQ (dead-letter queue) and metrics hooks; semantics depend on connector/config
  ✅ Horizontal scaling: add workers, tasks auto-distributed
  ✅ Can integrate with Schema Registry through Avro/Protobuf converters
  ❌ Less flexible for complex transformations (use Kafka Streams for that)
  ❌ Connector quality varies (community vs enterprise)

Rule:
  Simple data movement: Kafka Connect
  Complex stream processing: Kafka Streams or Flink
  Both: Connect for ingestion, Streams for processing
```

Connect không tự biến mọi pipeline thành exactly-once: source EOS cần connector hỗ trợ và worker bật tính năng tương ứng; sink còn phụ thuộc transaction/idempotency của hệ thống đích. DLQ cũng là cấu hình xử lý lỗi, và `errors.tolerance=all` có thể bỏ qua record lỗi. Chọn Connect khi bài toán chủ yếu là di chuyển dữ liệu khai báo được; chọn Streams/Flink khi cần join, window, state hoặc logic nghiệp vụ nhiều bước.

> 💡 **Giải thích dễ hiểu — Connect là dây chuyền đóng gói, Streams/Flink là xưởng chế biến:**
> Dây chuyền rất tiện khi chỉ cần lấy hàng, dán nhãn và giao đi. Khi phải trộn nhiều nguyên liệu theo thời gian, nhớ trạng thái hoặc tính toán phức tạp, cần một xưởng có bộ nhớ và quy trình riêng.

---

## Trade-offs

```
JDBC polling vs CDC (Debezium):
  JDBC:   simple, no DB changes needed, poll interval latency (seconds)
          cannot detect deletes without soft-delete column
          higher DB load (full/incremental scan)
  CDC:    low latency when source/log/connector keep up; captures committed
          insert/update/delete events supported by the connector
          requires WAL/binlog access (replication slot), more complex setup
  → CDC for real-time sync, JDBC for batch/periodic sync

Standalone vs Distributed Connect:
  Standalone: simple, no fault tolerance (single point of failure)
  Distributed: fault tolerant, scalable, REST API management
  → Distributed is the default for HA production; standalone can suit a small,
    explicitly accepted single-worker deployment

Converter: JSON vs Avro:
  JSON:  human-readable, can carry schemas or omit them, usually larger
  Avro:  compact binary, schema/evolution support with Registry and compatibility rules
  → Choose by contract, tooling and compatibility needs; neither is universally best

tasks.max:
  Higher: more parallelism (multiple partitions or tables)
  CDC connectors: often 1 task per database log stream; connector-specific
  JDBC: current JDBC source commonly supports one task; other connectors may partition tables/work differently
```

Delivery trade-off: Connect normally gives at-least-once behavior. A crash between writing a record and flushing/committing its offset can replay it, so consumers and sinks should use stable keys, idempotent upserts or deduplication. Source exactly-once is an opt-in capability for compatible connectors; it does not make external database or HTTP side effects transactional with Kafka.

> 💡 **Giải thích dễ hiểu — `tasks.max` là số ghế tối đa, không phải số người chắc chắn có mặt:**
> Connector chỉ xếp thêm task khi nguồn và đích chia được công việc. Tăng con số nhưng topic chỉ có một partition hoặc database chỉ có một log stream thì không tạo thêm năng lực thực tế.

---

## Real-world

Các lệnh dưới đây là checklist minh họa; hãy thay endpoint, group và tên connector theo môi trường. Đừng đưa password/PII vào log hoặc file cấu hình không được phân quyền.

```bash
# Monitor connector health (production checklist)
# 1. All connectors RUNNING (not FAILED/PAUSED)
for connector in $(curl -s localhost:8083/connectors | jq -r '.[]'); do
  status=$(curl -s localhost:8083/connectors/$connector/status | jq -r '.connector.state')
  echo "$connector: $status"
done

# 2. Debezium slot lag (PostgreSQL)
SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as lag_bytes
FROM pg_replication_slots;
# → Alert theo WAL retention/disk budget; 1GB chỉ là ví dụ, không phải ngưỡng chung

# 3. Consumer lag for connector group
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group connect-orders-jdbc-source

# Dead Letter Queue (DLQ): handle connector errors (properties minh họa)
"errors.tolerance": "all",              # skip errors (log + continue)
"errors.deadletterqueue.topic.name": "dlq-orders-jdbc-source",
"errors.deadletterqueue.topic.replication.factor": 3,
"errors.deadletterqueue.context.headers.enable": true,  # include error context in headers
"errors.log.enable": true,
"errors.log.include.messages": true      # có thể làm lộ PII; chỉ bật khi đã đánh giá rủi ro

# Secret management
# Option 1: FileConfigProvider (có sẵn trong Kafka; khóa file và thư mục bằng OS permissions)
"config.providers": "file",
"config.providers.file.class": "org.apache.kafka.common.config.provider.FileConfigProvider"
# Then use: "${file:/opt/secrets/passwords.properties:db.password}"

# Option 2: Vault Secret Provider (plugin/vendor-specific, cần cài và kiểm thử riêng)
"config.providers": "vault",
"config.providers.vault.class": "io.confluent.connect.secretregistry.rbac.config.provider.VaultConfigProvider"
```

Theo dõi tối thiểu: trạng thái connector/task và thời điểm chuyển `FAILED`, source/sink record rate, retry/error rate, offset commit, Kafka consumer lag, DLQ volume, cùng WAL/binlog/replication-slot lag của database. `errors.tolerance=all` có thể giúp pipeline không dừng nhưng đồng nghĩa record lỗi bị bỏ qua; DLQ phải được phân quyền, retry/replay và cảnh báo như một luồng dữ liệu quan trọng.

> 💡 **Giải thích dễ hiểu — production giống phòng máy bay:**
> Bảng điều khiển cần cả đèn “động cơ đang chạy” (task state), tốc độ (records/sec), nhiên liệu còn lại (WAL/disk) và danh sách hành lý bị giữ (DLQ). Chỉ nhìn một đèn xanh của connector chưa đủ để biết dữ liệu đã đến nơi an toàn.

---

## Nguồn tham khảo chính thức

- [Apache Kafka 4.3 – Kafka Connect User Guide](https://kafka.apache.org/43/kafka-connect/user-guide/): distributed mode, REST API, offset management, exactly-once source, plugin discovery và security.
- [Apache Kafka 4.3 – Kafka Connect Configs](https://kafka.apache.org/43/configuration/kafka-connect-configs/): worker/connector properties như `plugin.discovery`, `plugin.path` và `exactly.once.source.support`.
- [Debezium stable – PostgreSQL connector](https://debezium.io/documentation/reference/stable/connectors/postgresql.html): snapshot modes, WAL/LSN, replication slot, publication và kiểu dữ liệu.

---

## Ghi chú – Chủ đề tiếp theo
> Tiếp theo: [production.md](../operations/production.md) — Kafka production operations: JVM/OS tuning, broker configs for throughput/latency, JMX/Prometheus monitoring, consumer-lag alerting, security (SASL/TLS/ACL) và MirrorMaker2 DR.

---

*Cập nhật lần cuối: 2026-07-27*
