# Schema Registry & Schema Evolution – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ Kafka: xem [glossary.md](../glossary.md)

---

## What – Schema Registry là gì?

**Schema Registry (SR)** là dịch vụ đăng ký, đánh phiên bản và phân phối **schema** – bản mô tả cấu trúc, kiểu và ràng buộc của dữ liệu. Producer và consumer dùng schema như một **data contract** (hợp đồng dữ liệu) để thống nhất cách mã hóa, giải mã và tiến hóa event. Các implementation phổ biến hỗ trợ Avro, Protobuf và JSON Schema, nhưng tính năng cũng như wire format không hoàn toàn giống nhau.

```text
Producer ── đăng ký/tra schema ──► Schema Registry ◄── tra schema ── Consumer
   │                                                                  ▲
   └──────── serialize ──► Kafka topic ── deserialize ────────────────┘
```

> **Mental model – thư viện hợp đồng:** subject giống kệ sách, version là các lần tái bản, còn schema ID là mã tra cứu một nội dung schema. Event chỉ cần mang “mã tra cứu” khi serializer của hệ thống chọn cách đóng gói đó; không phải mọi registry đều dùng cùng loại mã hoặc cùng số byte.

Schema kiểm soát tốt các vấn đề như kiểu dữ liệu, field bắt buộc/default và quy tắc tiến hóa. Nó **không tự thay thế validation nghiệp vụ** như `amount > 0`, `currency` phải được hỗ trợ hay `customerId` phải tồn tại. Kafka broker cũng không tự hỏi SR trước khi nhận từng record: producer vẫn có thể gửi raw bytes hoặc dùng serializer khác.

---

## Why – Tại sao cần Schema Registry?

- **Data contract dùng chung:** giảm tình trạng producer đổi cấu trúc âm thầm làm consumer giải mã thất bại.
- **Schema evolution có kiểm soát:** kiểm tra compatibility trước khi đăng ký version mới, nhờ đó xác định thứ tự rollout producer/consumer.
- **Giảm lặp metadata:** với binary encoding như Avro/Protobuf, field name không phải lặp trong từng record; header thường chỉ mang định danh schema.
- **Governance:** tập trung subject, version, owner, compatibility policy, audit và quy trình phê duyệt.
- **Đa ngôn ngữ:** Java, Go, Python… cùng sinh code hoặc giải mã từ một contract.

> **Lưu ý:** SR là “cổng đăng ký contract”, không phải tường lửa chặn mọi dữ liệu sai. Muốn broker-side enforcement cần thêm cơ chế riêng; muốn kiểm tra nghiệp vụ cần validation trong ứng dụng hoặc data-quality rule.

---

## Components – Kiến trúc và ranh giới implementation

Một hệ thống registry thường có:

1. API để register, lookup, kiểm tra compatibility và quản lý lifecycle.
2. Kho metadata bền vững cho schema, subject, version, ID và cấu hình.
3. Compatibility engine theo từng schema type.
4. Serializer/deserializer phía client và cache schema.
5. Authentication, authorization, audit và công cụ CI/CD.

Với **Confluent Schema Registry tự quản lý**, metadata được ghi vào Kafka topic log-compacted **`_schemas`**. Có thể chạy nhiều instance; request ghi được chuyển đến instance primary. Vì vậy không nên mô tả mọi SR là “stateless”: API node có cache và cơ chế phối hợp, còn nguồn dữ liệu bền vững của triển khai Confluent là `_schemas`. Apicurio Registry, AWS Glue Schema Registry hoặc hệ thống khác có storage và protocol riêng.

### Subject, version và schema ID

- **Subject**: namespace và cũng là phạm vi mặc định để áp compatibility policy.
- **Version**: số thứ tự của schema trong một subject.
- **Schema ID**: định danh nội dung schema do registry cấp để serializer/deserializer lookup.

```text
Subject "orders-value"
  ├── version 1 ── schema ID 101
  ├── version 2 ── schema ID 145
  └── version 3 ── schema ID 203
```

Version và ID không đồng nghĩa. Version thuộc subject; cùng một nội dung schema có thể được dùng ở nhiều subject và registry có thể tái sử dụng ID. Đăng ký lại schema y hệt trong cùng subject thường không tạo version mới.

> **Mental model – số nhà và số lần sửa hợp đồng:** ID giúp tìm đúng “ngôi nhà schema”; version cho biết subject đã sửa contract bao nhiêu lần. Không suy ra version từ ID, cũng không dựa vào ID để so sánh schema nào mới hơn.

### Confluent wire format

**Wire format** là bố cục byte thực tế trên Kafka. Với serializer chính thức của Confluent, phần đầu dùng magic byte và schema ID 4 byte big-endian:

```text
Avro / JSON Schema:
[magic byte: 1][schema ID: 4][serialized payload]

Protobuf:
[magic byte: 1][schema ID: 4][message indexes][protobuf payload]
```

**Magic byte** là byte phiên bản của format; giá trị hiện tại là `0x00`. Protobuf cần thêm `message indexes` để chỉ ra message type trong file `.proto`. Deserializer đọc header, lấy schema từ cache hoặc registry rồi mới giải mã payload.

Đây là **Confluent wire format**, không phải tiêu chuẩn chung cho mọi Schema Registry. AWS Glue/Apicurio hoặc serializer tùy biến có thể dùng header, độ dài ID và cách nhúng metadata khác.

> 💡 **Giải thích dễ hiểu – tem tra cứu trên kiện hàng:** payload là món hàng, còn magic byte và schema ID là tem giúp consumer biết phải lấy “bản hướng dẫn” nào để mở. Confluent dùng tem 1 + 4 byte như trên, nhưng hãng registry khác có thể thiết kế loại tem khác.

---

## How – Subject Naming Strategies

**Subject naming strategy** là quy tắc ánh xạ `(topic, key/value, record type)` thành subject; nó quyết định các schema nào phải tương thích với nhau.

| Strategy | Subject điển hình | Khi phù hợp |
|---|---|---|
| **TopicNameStrategy** (mặc định) | `<topic>-key` / `<topic>-value` | Mỗi key/value side của topic có một contract chính |
| **RecordNameStrategy** | `<fully.qualified.record.name>` | Cùng record type đi qua nhiều topic; compatibility dùng chung theo record name |
| **TopicRecordNameStrategy** | `<topic>-<fully.qualified.record.name>` | Nhiều record type trong topic nhưng muốn cô lập contract theo topic |

```properties
value.subject.name.strategy=io.confluent.kafka.serializers.subject.RecordNameStrategy
```

`TopicNameStrategy` kiểm tra compatibility trong một subject cho toàn bộ value hoặc key của topic. Muốn nhiều event type trong một topic, có thể dùng Record/TopicRecordNameStrategy hoặc schema tổng hợp bằng references, tùy yêu cầu thứ tự và quản trị. Xem thêm [Event-driven architecture](../patterns/event_driven_architecture.md).

> **Mental model – chọn phòng thi:** naming strategy quyết định schema nào “thi chung” một bộ luật compatibility. Đổi strategy giữa chừng có thể tạo subject mới và vô tình bỏ qua lịch sử kiểm tra của subject cũ; hãy coi đó là một migration có kế hoạch.

---

## How – Compatibility Modes

**Compatibility** là khả năng producer/consumer dùng các version schema khác nhau mà vẫn đọc được dữ liệu. Trong Confluent SR, policy có thể đặt global hoặc theo subject; mặc định là `BACKWARD`. Registry khác có thể có mặc định khác.

| Mode | Contract được bảo đảm | Thứ tự rollout thường dùng |
|---|---|---|
| **BACKWARD** | Consumer dùng schema mới đọc được data ghi bằng schema gần nhất | Consumer trước, producer sau |
| **FORWARD** | Consumer dùng schema gần nhất đọc được data ghi bằng schema mới | Producer trước; chỉ nâng consumer khi data cũ không còn là vấn đề |
| **FULL** | Cả backward và forward với schema gần nhất | Có thể nâng hai phía độc lập hơn |
| **`*_TRANSITIVE`** | Kiểm tra cùng chiều với **mọi** version trước | Dùng khi còn replay dữ liệu rất cũ hoặc có nhiều nhịp rollout |
| **NONE** | Không thực hiện compatibility check | Chỉ dùng khi có kiểm soát khác rõ ràng |

```text
BACKWARD: reader mới  ◄── đọc được ── writer cũ
FORWARD:  reader cũ  ◄── đọc được ── writer mới
FULL:     bảo đảm cả hai chiều
```

> 💡 **Giải thích dễ hiểu – ổ cắm và phích cắm:** backward hỏi “thiết bị mới có cắm được ổ cũ không?”, forward hỏi “thiết bị cũ có dùng được ổ mới không?”. Transitive là đem ra thử với tất cả ổ từng phát hành, không chỉ ổ ngay trước đó.

### Bảng tiến hóa Avro

Bảng sau dành cho **Avro**; Protobuf và JSON Schema có luật khác.

| Thay đổi | BACKWARD | FORWARD | FULL |
|---|:---:|:---:|:---:|
| Thêm field có default | ✅ | ✅ | ✅ |
| Thêm field không default | ❌ | ✅ | ❌ |
| Xóa field từng có default | ✅ | ✅ | ✅ |
| Xóa field không có default | ✅ | ❌ | ❌ |
| Đổi tên field | Thường breaking; alias có thể hỗ trợ theo một chiều | Thường breaking | Phải test cụ thể |
| Đổi kiểu | Phụ thuộc quy tắc type promotion và chiều đọc | Phụ thuộc | Phải thỏa cả hai chiều |

```bash
# Cấu hình subject trên Confluent SR
curl -X PUT http://sr:8081/config/orders-value \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"compatibility":"BACKWARD_TRANSITIVE"}'

# Kiểm tra schema trước khi đăng ký/deploy
curl -X POST \
  http://sr:8081/compatibility/subjects/orders-value/versions/latest?verbose=true \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  -d '{"schema":"...","schemaType":"AVRO"}'
```

Với Avro, thêm field có default là lựa chọn an toàn phổ biến, nhưng không biến mọi thay đổi thành tương thích. Với Protobuf, không tái sử dụng field number đã xóa và nên `reserved` number/name; Confluent khuyến nghị `BACKWARD_TRANSITIVE` cho nhiều use case Protobuf. Với JSON Schema, kết quả còn phụ thuộc open/closed content model (`additionalProperties`) và compatibility policy. Luôn test bằng đúng engine/schema type đang chạy.

---

## How – Serializer, deserializer và pipeline

**Serializer/deserializer (SerDes)** chuyển object thành bytes và ngược lại. Ví dụ cấu hình Avro dùng Confluent clients:

```properties
# Producer
value.serializer=io.confluent.kafka.serializers.KafkaAvroSerializer
schema.registry.url=https://sr.example:8081
auto.register.schemas=false
use.latest.version=false
normalize.schemas=true

# Consumer
value.deserializer=io.confluent.kafka.serializers.KafkaAvroDeserializer
specific.avro.reader=true
```

```java
Order order = Order.newBuilder()
    .setId(1L)
    .setAmount(99.9)
    .build();

producer.send(new ProducerRecord<>("orders", order.getId().toString(), order));
```

Khi `auto.register.schemas=false` và `use.latest.version=false`, serializer lookup schema suy ra từ object và fail nếu schema chưa được đăng ký. Cách vận hành kiểm soát thường là:

1. lint/validate schema trong pull request;
2. test compatibility với subject đích;
3. review owner và đăng ký schema qua pipeline;
4. deploy ứng dụng theo thứ tự của compatibility mode.

`auto.register.schemas=true` tiện cho local/dev nhưng cấp cho mỗi app quyền tạo version. `use.latest.version=true` khiến serializer dùng latest của subject; nên hiểu rõ race khi latest thay đổi và giữ `latest.compatibility.strict=true` nếu chọn cơ chế này. Không bật cả loạt option theo thói quen: mỗi tổ hợp có hành vi lookup/register khác nhau.

> **Mental model – bản hợp đồng đã ký:** production pipeline đăng ký contract trước, ứng dụng chỉ tra đúng bản đã duyệt. Dùng `latest` giống ký vào “bản mới nhất trên bàn” – thuận tiện nhưng dễ lấy nhầm nếu người khác vừa thay bản.

Client thường cache schema/ID, nên registry không nhất thiết bị gọi cho từng message. Khi cache miss, schema/subject mới hoặc app restart, registry unavailable vẫn có thể làm serialize/deserialize thất bại. Xem cấu hình Spring tại [Java messaging](../../java/core/messaging.md) và phần nền tảng tại [Producers](../fundamentals/producers.md).

### Schema normalization

**Normalization** chuẩn hóa cách biểu diễn schema trước khi lookup/register để các schema tương đương về mặt cú pháp không bị coi là khác chỉ vì thứ tự hoặc formatting được phép chuẩn hóa. Với Confluent clients có thể dùng `normalize.schemas=true`, hoặc bật ở API/config subject.

Normalization **không** sửa breaking change và không thay compatibility check. Nó chỉ làm định danh ổn định hơn theo quy tắc của từng schema type.

---

## How – Schema References

**Schema reference** cho phép schema cha tham chiếu schema con đã đăng ký, ví dụ `Order` dùng `Address` mà không copy toàn bộ định nghĩa. Một reference của Confluent chỉ rõ `name`, `subject` và `version`:

```json
{
  "schemaType": "AVRO",
  "references": [
    {
      "name": "com.example.Address",
      "subject": "address-value",
      "version": 2
    }
  ],
  "schema": "{\"type\":\"record\",\"name\":\"Order\",\"fields\":[...]}"
}
```

References giúp tái sử dụng type, tổ chức nhiều event type và tách ownership, nhưng tạo dependency graph. Pipeline cần register schema con trước schema cha, test compatibility cho từng subject và kiểm tra endpoint `referencedby` trước khi xóa.

> 💡 **Giải thích dễ hiểu – thư viện dùng chung:** `Order` chỉ ghi “dùng Address bản 2”. Nếu rút `Address` khỏi kho khi sách `Order` còn trỏ tới nó, người đọc không thể ráp đủ nội dung; lifecycle phải đi theo đồ thị phụ thuộc.

---

## Compare – Avro, Protobuf và JSON Schema

| Tiêu chí | Avro | Protobuf | JSON Schema |
|---|---|---|---|
| Encoding thường gặp | Binary, schema-driven | Binary, field number/tag | JSON text với Confluent JSON serializer |
| Evolution nổi bật | Default, alias, type promotion | Field number ổn định, `reserved` | Cấu trúc linh hoạt; chú ý `additionalProperties` |
| Code generation | Có (`.avsc`/IDL) | Có, đa ngôn ngữ mạnh (`.proto`) | Tùy tool/workflow |
| Đọc payload bằng mắt | Không trực tiếp | Không trực tiếp | Có thể sau khi bỏ wire header |
| Phù hợp khi | Data platform/Kafka cần schema evolution gọn | Hệ thống đã dùng Protobuf/gRPC | API/event cần giữ JSON |
| Điểm phải bảo vệ | Default và reader/writer resolution | Không đổi/tái dùng field number | Open/closed model và rule phức tạp |

Không có format nào luôn “nhỏ nhất”: kích thước còn phụ thuộc data shape, field value, framing, compression và batch. Hãy benchmark workload thật, đồng thời tính cả ecosystem, khả năng debug và quy tắc evolution. Xem thêm [Kafka Connect](../streams/connect.md).

---

## Trade-offs

- **Lợi ích:** contract rõ ràng, rollout có quy tắc, giảm metadata lặp lại, hỗ trợ đa ngôn ngữ và audit tập trung.
- **Chi phí vận hành:** thêm control-plane phải HA, bảo mật, theo dõi, backup và đồng bộ cùng Kafka data.
- **Độ phức tạp tổ chức:** subject ownership, naming strategy và compatibility policy sai có thể chặn thay đổi hợp lệ hoặc bỏ lọt breaking change.
- **Coupling mới:** client phụ thuộc serializer protocol và khả năng lookup ID; migration sang registry/format khác phải xử lý wire format và ID.
- **Khả năng quan sát:** binary payload khó đọc trực tiếp; cần console/tool có schema-aware deserializer.

Registry đáng dùng khi contract được quản trị như code: review, test, version và rollback có kế hoạch. Chỉ dựng một server rồi để ứng dụng tự đăng ký mọi thứ sẽ không tự tạo ra governance.

---

## Lifecycle – Soft delete, hard delete và lưu trữ lâu dài

Trong Confluent SR:

- **Soft delete** ẩn subject/version khỏi các API thông thường nhưng vẫn giữ metadata và schema ID để lookup; ID không được tái sử dụng.
- **Hard delete** dùng `?permanent=true`, chỉ thực hiện sau soft delete và xóa metadata/ID vĩnh viễn.
- Xóa một version có thể làm version cũ hơn trở thành `latest`, từ đó thay đổi baseline của mode không-transitive.

```bash
# Bước 1: soft delete
curl -X DELETE http://sr:8081/subjects/orders-value/versions/3

# Bước 2: chỉ khi đã xác minh dependency và dữ liệu lưu giữ
curl -X DELETE \
  'http://sr:8081/subjects/orders-value/versions/3?permanent=true'
```

> 💡 **Giải thích dễ hiểu – xé mục lục khi sách còn trên kệ:** soft delete giống cất một mục khỏi danh sách công khai nhưng vẫn tra cứu được bằng mã; hard delete là xé hẳn mục đó. Nếu Kafka record cũ còn giữ schema ID, lần replay sau có thể không giải mã được; cache hiện tại không phải backup.

Hard delete schema cũng không xóa payload khỏi Kafka và không tự đáp ứng yêu cầu xóa dữ liệu cá nhân. Muốn xử lý dữ liệu nhạy cảm phải thiết kế retention, compaction, tombstone hoặc crypto-shredding riêng.

---

## Operations – HA, DR và Security

### High availability và disaster recovery

- Chạy nhiều SR instances sau load balancer; cấu hình chúng trỏ cùng Kafka cluster và cùng nhóm registry theo hướng dẫn của vendor.
- Đặt replication factor phù hợp cho `_schemas`; độ bền của metadata không thể cao hơn Kafka backing store.
- Theo dõi API latency/error, primary election/forwarding, cache miss, compatibility rejection và sức khỏe `_schemas`.
- Backup/replicate schema metadata cùng Kafka data. Khi di chuyển cluster, giữ hoặc translate schema ID; copy nguyên record sang registry cấp ID khác có thể giải mã sai hoặc thất bại.
- Test tình huống registry down: cache hit có thể tiếp tục, nhưng schema/ID chưa cache sẽ thất bại.

### Security

- Dùng TLS cho client-to-registry; cân nhắc mTLS, Basic/OAuth hoặc cơ chế cloud tương ứng.
- Phân quyền tối thiểu cho register, read, compatibility config và delete; tách quyền CI khỏi runtime app.
- Bảo vệ credentials của SR khi truy cập Kafka và cấp ACL cần thiết cho `_schemas`.
- Không public REST API không xác thực; bật audit cho thay đổi policy/schema và luân chuyển secret.
- Schema có thể tiết lộ tên field hoặc cấu trúc nghiệp vụ, nên coi metadata registry là tài sản cần bảo vệ.

> 💡 **Giải thích dễ hiểu – danh bạ dùng chung có khóa:** nhiều bản sao SR giúp tra cứu liên tục, nhưng tất cả vẫn phụ thuộc vào cuốn danh bạ gốc và quyền mở nó. HA mà `_schemas` chỉ có một replica, hoặc API production mở công khai, đều chưa phải vận hành an toàn.

---

## Real-world – Checklist triển khai

Ví dụ nâng `orders-value` từ v1 lên v2 bằng cách thêm `currency` có default:

1. Chốt subject naming strategy và `BACKWARD_TRANSITIVE` nếu consumer còn replay lịch sử dài.
2. CI normalize/lint schema, gọi compatibility API và đăng ký v2.
3. Nâng consumer trước; consumer mới dùng default khi đọc record v1.
4. Nâng producer để ghi record v2.
5. Theo dõi deserialize error, unknown schema ID và lag; rollback app không đồng nghĩa xóa schema.

```bash
curl http://sr:8081/subjects
curl http://sr:8081/subjects/orders-value/versions/latest
curl http://sr:8081/schemas/ids/145
```

- Kafka Connect/Debezium có thể dùng converter tích hợp SR; cần quản lý naming và compatibility như ứng dụng thường. Xem [Kafka Connect](../streams/connect.md).
- ksqlDB dùng schema metadata để suy ra cột và kiểu. Xem [ksqlDB](ksqldb.md).
- Với DLQ/replay dài hạn, lưu cả provenance như subject/schema ID và giữ registry lifecycle lâu ít nhất bằng dữ liệu cần đọc.

---

## Nguồn chính thức

- [Confluent – Formats, serializers, naming strategies và normalization](https://docs.confluent.io/platform/current/schema-registry/fundamentals/serdes-develop/overview.html)
- [Confluent – Schema evolution và compatibility](https://docs.confluent.io/platform/current/schema-registry/fundamentals/schema-evolution.html)
- [Confluent – Schema Registry API](https://docs.confluent.io/platform/current/schema-registry/develop/api.html)
- [Confluent – Hard/soft delete](https://docs.confluent.io/platform/current/schema-registry/schema-deletion-guidelines.html)
- [Confluent – Security](https://docs.confluent.io/platform/current/schema-registry/security/index.html)
- [Apache Avro – Specification](https://avro.apache.org/docs/current/specification/)
- [Protocol Buffers – Updating a message type](https://protobuf.dev/programming-guides/proto3/#updating)
- [JSON Schema – Specification](https://json-schema.org/specification)

---

## Ghi chú – Chủ đề tiếp theo

> [ksqlDB](ksqldb.md): stream processing bằng SQL, stream vs table, push/pull query, materialized view, UDF/UDAF, tích hợp Schema Registry và so sánh Kafka Streams/Flink.

> Liên quan: [Kafka Connect](../streams/connect.md), [Producers](../fundamentals/producers.md), [Event-driven architecture](../patterns/event_driven_architecture.md), [Java messaging](../../java/core/messaging.md).

> Keywords: `_schemas`, schema ID vs version, `KafkaAvroSerializer`, `normalize.schemas`, `latest.compatibility.strict`, Avro logical types, Protobuf field number reuse, schema references, schema linking, data contracts, `value.subject.name.strategy`.

---

*Cập nhật lần cuối: 2026-07-22*
