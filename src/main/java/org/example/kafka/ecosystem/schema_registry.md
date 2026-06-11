# Schema Registry & Schema Evolution – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Schema Registry là gì?

**Schema Registry (SR)** là dịch vụ lưu trữ tập trung các schema (Avro/Protobuf/JSON Schema) cho dữ liệu Kafka, thực thi **data contract** giữa producer và consumer. Bản ghi trên topic chỉ chứa **schema ID** (nhỏ gọn) thay vì nhúng cả schema.

```
Producer ──register/get schema──► Schema Registry ◄──get schema── Consumer
   │  (ghi magic byte + schema id + payload Avro)         │
   └──────────────► Kafka topic ──────────────────────────┘
```

Triển khai phổ biến: **Confluent Schema Registry**, **Apicurio Registry** (Red Hat, open), **AWS Glue Schema Registry**.

---

## Why – Tại sao cần Schema Registry?

- **Data contract**: producer không thể ghi dữ liệu sai schema → consumer không vỡ bất ngờ.
- **Schema evolution an toàn**: kiểm tra tương thích **trước khi** cho phép schema mới → producer/consumer tiến hóa độc lập.
- **Wire format nhỏ gọn**: payload chỉ mang schema ID (4 byte), không lặp lại tên field như JSON → tiết kiệm băng thông/lưu trữ.
- **Governance**: một nguồn sự thật cho mọi schema, versioning, audit.

> Không có SR + JSON tự do → producer đổi field âm thầm → consumer crash/parse sai. Đây là "schema-on-write" cho streaming.

---

## Components – Kiến trúc & Wire Format

### Lưu trữ
SR lưu chính schema trong topic Kafka **`_schemas`** (log compacted) → bản thân SR stateless, HA bằng cách chạy nhiều instance đọc cùng topic.

### Wire format (Confluent)
```
[Magic Byte: 0x00][Schema ID: 4 bytes][Serialized payload (Avro/Protobuf/JSON)]
 1 byte            int32 big-endian     phần dữ liệu thực
```
- Deserializer đọc 4 byte schema ID → hỏi SR lấy schema (cache lại) → giải mã payload.
- **Subject** = không gian tên chứa các **version** schema. Mỗi schema có **global ID** duy nhất.

```
Subject "orders-value"
  ├── version 1 (schema id 101)
  ├── version 2 (schema id 145)   ← phải tương thích version trước theo compatibility mode
  └── version 3 (schema id 203)
```

---

## How – Subject Naming Strategies

Cách map (topic, record) → subject, quyết định "đơn vị" kiểm tra tương thích.

| Strategy | Subject | Khi dùng |
|----------|---------|----------|
| **TopicNameStrategy** (mặc định) | `<topic>-key` / `<topic>-value` | 1 topic = 1 loại event (phổ biến nhất) |
| **RecordNameStrategy** | `<fully.qualified.record.name>` | Cùng record type qua nhiều topic; nhiều event type trong 1 topic |
| **TopicRecordNameStrategy** | `<topic>-<record.name>` | Nhiều event type/topic nhưng cô lập theo topic |

```properties
value.subject.name.strategy=io.confluent.kafka.serializers.subject.RecordNameStrategy
```
> Nhiều event type trong 1 topic (để giữ thứ tự theo entity) → cần Record/TopicRecordNameStrategy. Liên hệ event design ở [../patterns/event_driven_architecture.md](../patterns/event_driven_architecture.md).

---

## How – Compatibility Modes (cốt lõi)

SR từ chối schema mới nếu **không tương thích** với version theo mode. Chia theo chiều: ai nâng cấp trước.

| Mode | Cho phép thay đổi gì | Ai nâng trước | Ý nghĩa |
|------|----------------------|---------------|---------|
| **BACKWARD** (mặc định) | Xóa field, thêm field **có default** | **Consumer** trước | Consumer mới đọc được data cũ |
| **FORWARD** | Thêm field, xóa field **có default** | **Producer** trước | Consumer cũ đọc được data mới |
| **FULL** | Chỉ thêm/xóa field **có default** | Bất kỳ | Cả hai chiều |
| **\*_TRANSITIVE** | Như trên nhưng check với **TẤT CẢ** version trước (không chỉ version gần nhất) | – | Nghiêm ngặt hơn |
| **NONE** | Mọi thay đổi | – | Không kiểm tra (rủi ro) |

```
BACKWARD: schema mới đọc được dữ liệu GHI BỞI schema cũ
  → an toàn khi nâng cấp consumer trước, rồi producer
  → cho phép: xóa field, thêm field CÓ default

FORWARD: schema cũ đọc được dữ liệu GHI BỞI schema mới
  → an toàn khi nâng cấp producer trước, rồi consumer
  → cho phép: thêm field, xóa field CÓ default
```

### Bảng luật tiến hóa (Avro)
| Thay đổi | BACKWARD | FORWARD | FULL |
|----------|:--------:|:-------:|:----:|
| Thêm field **có default** | ✅ | ✅ | ✅ |
| Thêm field **không default** | ❌ | ✅ | ❌ |
| Xóa field **có default** | ✅ | ✅ | ✅ |
| Xóa field **không default** | ✅ | ❌ | ❌ |
| Đổi tên field | ❌ (dùng `aliases`) | ❌ | ❌ |
| Đổi kiểu (widening int→long) | tùy | tùy | tùy |

```bash
# Set compatibility cho subject (hoặc global)
curl -X PUT http://sr:8081/config/orders-value -d '{"compatibility":"BACKWARD_TRANSITIVE"}'
```
> Quy tắc thực chiến: **luôn cho field mới một `default`** → giữ BACKWARD/FORWARD. Không bao giờ đổi tên (dùng alias) hay đổi kiểu không tương thích.

---

## How – Producer/Consumer config & code

```properties
# Producer
value.serializer=io.confluent.kafka.serializers.KafkaAvroSerializer
schema.registry.url=http://sr:8081
auto.register.schemas=true        # prod nên =false (đăng ký schema qua CI/CD, không cho app tự đăng ký)
use.latest.version=true

# Consumer
value.deserializer=io.confluent.kafka.serializers.KafkaAvroDeserializer
specific.avro.reader=true          # dùng class sinh từ .avsc (SpecificRecord) thay GenericRecord
```
```java
// Avro record (sinh từ .avsc bằng avro-maven-plugin)
Order order = Order.newBuilder().setId(1L).setAmount(99.9).build();
producer.send(new ProducerRecord<>("orders", order.getId().toString(), order));
// Serializer tự đăng ký/lookup schema, ghi magic+id+payload
```
> **Production**: `auto.register.schemas=false` + đăng ký schema qua pipeline (maven plugin/CI) → tránh app tùy tiện tạo schema. Liên hệ Spring serializer config ở [../../java/core/messaging.md](../../java/core/messaging.md).

---

## How – Schema References (composing)

Schema lớn tách thành nhiều schema con tái sử dụng (vd `Address` dùng trong `Customer` và `Order`).
```json
{ "name": "Order", "type": "record",
  "fields": [ { "name": "shipTo", "type": "com.example.Address" } ] }   // tham chiếu schema khác
```
> Tránh lặp định nghĩa; SR quản lý quan hệ reference giữa các subject.

---

## Compare – Avro vs Protobuf vs JSON Schema

| | Avro | Protobuf | JSON Schema |
|--|------|----------|-------------|
| Kích thước | Nhỏ (binary, schema-driven) | Nhỏ nhất (field number) | Lớn (text) |
| Schema evolution | Mạnh (default/alias) | Mạnh (field number ổn định) | Khá |
| Code gen | Có (.avsc) | Có (.proto, đa ngôn ngữ mạnh) | Tùy |
| Human-readable | Không | Không | **Có** |
| Hệ sinh thái Kafka | Gốc của SR, phổ biến nhất | Phổ biến (gRPC dùng chung) | Khi cần JSON |
| Quy tắc tương thích | Dựa default | Dựa **field number** (không tái dùng số!) | Dựa cấu trúc |

> Avro: mặc định phổ biến cho Kafka. Protobuf: hợp khi đã dùng gRPC/đa ngôn ngữ. JSON Schema: cần dễ đọc/đã có JSON. Liên hệ formats ở [../streams/connect.md](../streams/connect.md).

---

## Trade-offs

- (+) Data contract an toàn, evolution có kiểm soát, wire format nhỏ, governance tập trung, decouple producer/consumer.
- (−) Thêm một dịch vụ phải HA (SR down → không (de)serialize được nếu cache miss; nên cache + chạy cluster).
- (−) Learning curve compatibility modes; sai mode → hoặc chặn thay đổi hợp lệ, hoặc cho qua thay đổi phá vỡ.
- (−) Avro/Protobuf không human-readable → khó debug bằng mắt (cần tool giải mã).
- (−) `auto.register.schemas=true` ở prod → schema "rác" do app tạo; nên quản qua CI.

---

## Real-world

```bash
# REST API thao tác schema
curl http://sr:8081/subjects                              # list subjects
curl http://sr:8081/subjects/orders-value/versions/latest # schema mới nhất
curl -X POST http://sr:8081/compatibility/subjects/orders-value/versions/latest \
     -H "Content-Type: application/vnd.schemaregistry.v1+json" \
     -d '{"schema": "..."}'                                # test tương thích TRƯỚC khi deploy
```
- Pipeline CI: validate schema mới tương thích (compatibility check) trước khi merge → chặn breaking change sớm.
- Kết hợp Connect (Avro converter) + Debezium CDC → schema từ DB tự vào SR. Liên hệ [../streams/connect.md](../streams/connect.md).
- ksqlDB tự đọc schema từ SR để suy ra cột. Liên hệ [./ksqldb.md](ksqldb.md).

---

## Ghi chú – Chủ đề tiếp theo
> `ecosystem/ksqldb.md`: ksqlDB – stream processing bằng SQL, streams vs tables, push/pull query, materialized view, UDF/UDAF, tích hợp Schema Registry, so sánh Kafka Streams/Flink.

> Liên quan: [../streams/connect.md](../streams/connect.md) (Avro converter, CDC), [../fundamentals/producers.md](../fundamentals/producers.md) (serialization), [../patterns/event_driven_architecture.md](../patterns/event_driven_architecture.md) (event/schema design), [../../java/core/messaging.md](../../java/core/messaging.md) (Spring Kafka serializer).

> Keywords: `_schemas` topic, schema id vs version, KafkaAvroSerializer, `normalize.schemas`, `latest.compatibility.strict`, Avro logical types, Protobuf field number reuse, schema linking, Data Contracts (rules/migration - Confluent), `value.subject.name.strategy`.

---

*Cập nhật lần cuối: 2026-06-04*
