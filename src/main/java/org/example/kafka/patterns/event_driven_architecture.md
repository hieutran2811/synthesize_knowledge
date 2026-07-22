# Event-Driven Architecture & Data Modeling (Kafka-native) – Deep Dive

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world (Production) – Ghi chú
> Bổ trợ góc **Kafka-native** cho các pattern khái niệm ở [../../java/patterns/patterns_enterprise.md](../../java/patterns/patterns_enterprise.md) (CQRS/Saga/Outbox/Event Sourcing) và [../../java/core/messaging.md](../../java/core/messaging.md) (Spring Kafka DLT/Outbox).
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – EDA với Kafka

**Event-Driven Architecture (EDA)** *(kiến trúc hướng sự kiện)* dùng **event** *(sự kiện đã xảy ra)* làm phương tiện giao tiếp giữa các service. Kafka đóng vai trò **log trung tâm bền vững** *(nhật ký có thể đọc lại trong retention/replication đã cấu hình)* — "hệ thần kinh" của hệ thống: producer *(dịch vụ phát sự kiện)* phát event, nhiều consumer *(dịch vụ nhận sự kiện)* độc lập tiêu thụ, có thể replay *(phát lại)*.

```
Service A ──(OrderCreated)──► Kafka topic ──┬──► Service B (gửi email)
                                            ├──► Service C (cập nhật kho)
                                            └──► Service D (analytics)   ← decouple, mỗi consumer độc lập
```

EDA không đồng nghĩa mọi giao tiếp đều phải qua Kafka. Kafka phù hợp khi muốn tách producer khỏi nhiều consumer, hấp thụ tải đột biến và lưu lịch sử để xử lý lại; các yêu cầu trả lời đồng bộ, ngắn hạn vẫn thường dùng REST/gRPC.

> 💡 **Giải thích dễ hiểu — Kafka là băng chuyền có sổ lưu kho:**
> Service A đặt một kiện hàng lên băng chuyền một lần. B, C và D có quầy riêng nên lấy hàng độc lập, có thể đọc lại sổ khi quầy bị gián đoạn mà không bắt A gọi từng nơi.

---

## Why – Tại sao dùng EDA với Kafka?

EDA giúp một sự kiện nghiệp vụ được fan-out *(phân phối đến nhiều bên nhận)* mà producer không biết chi tiết từng consumer. Consumer có thể triển khai, mở rộng hoặc replay độc lập; Kafka giữ lại log theo retention để hỗ trợ audit và rebuild read model. Đổi lại, dữ liệu giữa các service thường **eventual consistency** *(nhất quán cuối cùng)*, nên UI và nghiệp vụ phải chấp nhận trạng thái cập nhật trễ hoặc có cơ chế theo dõi.

> 💡 **Giải thích dễ hiểu — gửi thông báo thay vì đi gõ cửa từng phòng:**
> Người gửi chỉ dán thông báo lên bảng chung; các phòng tự đọc khi sẵn sàng. Cách này không làm mọi phòng cập nhật cùng một tích tắc, nhưng một phòng hỏng tạm thời cũng không chặn người gửi.

---

## How – Topic Design & Naming

**Topic** *(luồng log có tên trong Kafka)* là ranh giới lưu trữ và phân phối event. Chọn granularity *(mức độ gom nhóm)* dựa trên cách consumer đăng ký, yêu cầu ordering *(thứ tự)* và vòng đời schema *(lược đồ dữ liệu)*; đừng gom mọi event vào một topic chỉ vì tiện lúc đầu.

### Granularity: một topic cho cái gì?
| Chiến lược | Mô tả | Khi dùng |
|-----------|-------|----------|
| **1 topic / event type** | `orders.created`, `orders.shipped` riêng | Phổ biến; consumer chọn lọc loại event |
| **1 topic / entity (nhiều event type)** | Mọi event của `order` vào `orders` | Cần **giữ thứ tự** mọi event của 1 entity (cùng key) → cần Record/TopicRecordNameStrategy ([../ecosystem/schema_registry.md](../ecosystem/schema_registry.md)) |
| **1 topic / aggregate domain** | `payments`, `inventory` | Bounded context *(ranh giới mô hình nghiệp vụ trong DDD)* |

### Naming convention
```
<domain>.<entity>.<event-type>        vd: commerce.order.created
<environment>.<domain>.<entity>       vd: prod.billing.invoice
```
> Nhất quán naming → dễ governance/ACL/discovery. Tránh đổi tên topic (consumer phụ thuộc).

> 💡 **Giải thích dễ hiểu — topic giống kệ hàng có nhãn:**
> Kệ quá nhỏ thì nhân viên phải đi quá nhiều nơi; kệ “tất cả mọi thứ” thì khó tìm và khó phân quyền. Nhãn ổn định giúp người nhận biết lấy đúng hàng mà không cần hỏi người gửi.

---

## How – Partitioning & Key Strategy (quan trọng nhất)

**Partition** *(phân vùng độc lập trong topic)* và **record key** *(khóa định tuyến)* quyết định event đi đâu. Kafka chỉ đảm bảo thứ tự trong từng partition; vì vậy key phải phản ánh entity cần xử lý tuần tự, không phải chọn tùy ý cho đủ trường.

### Key quyết định partition → quyết định thứ tự
```
record key ──hash──► partition   (cùng key → cùng partition khi mapping ổn định → ĐẢM BẢO THỨ TỰ trong partition)
no key      ──► round-robin/sticky → KHÔNG đảm bảo thứ tự giữa các record
```
- **Thứ tự chỉ đảm bảo TRONG MỘT partition.** Cần giữ thứ tự event của 1 entity → dùng **entity id làm key** (vd `order_id`) → mọi event của order đó vào cùng partition, xử lý tuần tự.
- Global ordering = 1 partition duy nhất → **giết throughput** → hầu như không nên; thiết kế để chỉ cần ordering theo key.

### Chọn số partition
| Yếu tố | Hướng |
|--------|-------|
| Throughput mục tiêu | partition = max(throughput_target / per_partition_throughput) |
| Song song consumer | #consumer trong group ≤ #partition (thừa consumer sẽ idle) |
| Quá nhiều partition | tăng độ trễ end-to-end, tải metadata/controller, thời gian rebalance/recovery |
| Tăng partition | **phá vỡ key→partition mapping** → loạn thứ tự dữ liệu cũ; khó giảm |

> Chọn dư một chút (cho phép scale consumer tương lai) nhưng không "1000 partition cho topic nhỏ". Key skew → **hot partition** (1 key chiếm phần lớn traffic) → broker lệch tải. Liên hệ partitioning ở [../fundamentals/producers.md](../fundamentals/producers.md).

> 💡 **Giải thích dễ hiểu — key là số quầy cố định của một khách hàng:**
> Mọi đơn của cùng `order_id` vào một quầy nên nhân viên xử lý đúng thứ tự. Nếu một khách quá đông (hot key), quầy đó bị nghẽn dù các quầy khác còn trống; cần chọn key và số partition dựa trên tải thực tế.

## When – Khi nào nên dùng Kafka EDA?

Nên dùng khi một event cần nhiều consumer độc lập, các bước xử lý có thể bất đồng bộ, cần retry/replay hoặc muốn tách vòng đời của service. EDA đặc biệt hợp với workflow dài như đơn hàng, thanh toán, kho và analytics.

Không nên ép EDA cho request cần phản hồi ngay và nhất quán mạnh trong một transaction, hoặc CRUD nhỏ nơi một API/database đã đủ đơn giản. Có thể kết hợp: REST/gRPC cho command đồng bộ, Kafka cho event thông báo và xử lý hậu kỳ.

> 💡 **Giải thích dễ hiểu — chọn EDA như chọn chuyển phát:**
> Nếu người mua cần câu trả lời ngay tại quầy, giao tiếp trực tiếp nhanh hơn. Nếu nhiều bộ phận cùng phải xử lý một đơn và có thể làm sau, gửi một kiện có mã theo dõi sẽ linh hoạt hơn.

---

## Compare – 3 phong cách Event Design

| | Event Notification *(thông báo sự kiện)* | Event-Carried State Transfer *(sự kiện mang trạng thái)* | Event Sourcing *(lưu lịch sử làm nguồn sự thật)* |
|--|--------------------|-------------------------------|----------------|
| Nội dung event | "Đã xảy ra" + id (mỏng) | Toàn bộ/đủ state (dày) | Mọi thay đổi là event (nguồn sự thật) |
| Consumer | Gọi lại API lấy chi tiết | Tự đủ dữ liệu, không callback | Rebuild state từ replay event |
| Coupling | Cao hơn (callback runtime) | Thấp (decoupled) | Thấp nhất |
| Kích thước/lưu trữ | Nhỏ | Lớn hơn | Lớn (giữ toàn bộ lịch sử) |
| Khi dùng | Thông báo đơn giản | Decouple service, giảm callback | Audit, time-travel, rebuild, CQRS |

```json
// Notification (thin)
{"type":"OrderCreated","orderId":"123"}
// State transfer (fat)
{"type":"OrderCreated","orderId":"123","items":[...],"total":99.9,"customer":{...}}
```
> **Event-carried state transfer** *(sự kiện mang theo trạng thái)* thường phù hợp cho microservices (consumer không phải gọi ngược → bớt coupling, chịu lỗi tốt hơn). Event design + schema evolution đi chung: [../ecosystem/schema_registry.md](../ecosystem/schema_registry.md).

Notification nhẹ giúp payload nhỏ nhưng tạo runtime coupling vì consumer phải callback. State-transfer nặng hơn và có thể lộ nhiều dữ liệu, đổi lại consumer tự đủ để xử lý khi service nguồn tạm thời không sẵn sàng. Event Sourcing lưu toàn bộ lịch sử thay đổi, nên cần chính sách retention, snapshot và kiểm soát schema.

> 💡 **Giải thích dễ hiểu — ba kiểu giống ba loại phiếu giao hàng:**
> Phiếu notification chỉ ghi “có kiện hàng, xem mã này”; state-transfer kèm luôn nội dung kiện; event sourcing giữ mọi biên bản thay đổi để có thể dựng lại kho từ đầu. Phiếu càng đầy đủ càng ít phải gọi ngược, nhưng tốn chỗ và cần quản lý phiên bản kỹ hơn.

---

## How – Delivery Semantics *(cam kết giao nhận)* & Idempotent Consumer *(consumer xử lý lặp an toàn)*

| Semantic | Cơ chế | Đánh đổi |
|----------|--------|----------|
| At-most-once | Commit offset **trước** xử lý | Có thể mất message |
| **At-least-once** (mặc định phổ biến) | Commit offset **sau** xử lý | Có thể **lặp** message → cần idempotent |
| Exactly-once *(đúng một lần)* | Transactions (consume-process-produce) | Phức tạp, chỉ trong phạm vi Kafka |

### Idempotent Consumer (xử lý "at-least-once" an toàn)
Vì at-least-once có thể giao lặp, consumer phải **idempotent** (xử lý lại không gây tác dụng phụ kép):
```
- Dedup bằng business key / event id (lưu id đã xử lý → bỏ qua nếu trùng)
- UPSERT thay vì INSERT (ghi đè theo key)
- Dùng (topic, partition, offset) hoặc event_id làm khóa dedup trong DB
```
> EOS *(Exactly-Once Semantics)* transaction của Kafka chỉ "exactly-once" **trong Kafka** (consume→produce); tác dụng phụ ra ngoài (gửi email, ghi DB khác) vẫn cần idempotent. Liên hệ EOS ở [../fundamentals/producers.md](../fundamentals/producers.md) & [../fundamentals/consumers.md](../fundamentals/consumers.md).

Nếu dedup bằng `(topic, partition, offset)`, đó là vị trí giao nhận của Kafka chứ không phải mã nghiệp vụ ổn định khi replay hoặc migrate. Ưu tiên `event_id` duy nhất và idempotency key; chỉ dùng `order_id` khi mỗi order chỉ có đúng một lần xử lý cho nghiệp vụ đó.

> 💡 **Giải thích dễ hiểu — idempotent là nút “bấm lại không bị tính tiền hai lần”:**
> Nhân viên có thể nhận cùng một phiếu sau khi mạng chập chờn. Nếu phiếu có mã duy nhất và hệ thống đã ghi mã đó, lần sau chỉ xác nhận “đã làm rồi” thay vì gửi email, trừ tiền hoặc trừ kho lần nữa.

---

## Components – Các EDA pattern (góc Kafka)

### Transactional Outbox *(bảng sự kiện gửi đi trong cùng transaction)* (nhất quán DB ↔ Kafka)
Bài toán: ghi DB **và** publish Kafka phải nguyên tử (không có 2PC — two-phase commit). Giải: ghi event vào bảng `outbox` **trong cùng transaction DB**; một relay *(bộ chuyển tiếp)* như Debezium CDC *(Change Data Capture — thu thập thay đổi dữ liệu)* đọc outbox → publish Kafka.
```
Service: BEGIN; INSERT order; INSERT outbox(event); COMMIT;
Debezium CDC ──đọc outbox (binlog)──► Kafka topic   (thiết kế at-least-once; cần monitor/replay)
```
> Khái niệm/triển khai Spring: [../../java/core/messaging.md](../../java/core/messaging.md), [../../java/patterns/patterns_enterprise.md](../../java/patterns/patterns_enterprise.md). CDC: [../streams/connect.md](../streams/connect.md). Outbox thường cho at-least-once; cần `event_id`/idempotency và monitor CDC lag, không nên hiểu “không mất” là guarantee tuyệt đối.

> 💡 **Giải thích dễ hiểu — outbox là phiếu gửi kèm hóa đơn:**
> Cửa hàng ghi đơn và phiếu giao vào cùng một sổ nên không có chuyện đã bán hàng nhưng quên phiếu. Nhân viên vận chuyển có thể giao lại phiếu sau khi mất điện, vì vậy nơi nhận vẫn cần mã để không tạo đơn trùng.

### CQRS *(Command Query Responsibility Segregation — tách trách nhiệm đọc/ghi)*
Tách ghi (command *(yêu cầu thay đổi)* → event vào Kafka) khỏi đọc (consumer build **read model** *(mô hình đọc)* tối ưu cho query: Elasticsearch, materialized view, ksqlDB table).
```
Command → write model → emit events (Kafka) → consumers → read models (ES/CH/ksqlDB)
```
> Read model qua ksqlDB table + pull query: [../ecosystem/ksqldb.md](../ecosystem/ksqldb.md).

Read model có thể trễ so với write model; API đọc cần nêu rõ khả năng eventual consistency hoặc cung cấp read-your-writes khi nghiệp vụ cần. Mỗi read model có thể tối ưu cho một kiểu truy vấn thay vì ép một schema phục vụ mọi màn hình.

> 💡 **Giải thích dễ hiểu — CQRS là quầy thu ngân và quầy tra cứu riêng:**
> Quầy thu ngân ghi sổ giao dịch chuẩn; các quầy tra cứu dựng bảng chỉ mục nhanh từ những giao dịch đó. Bảng tra cứu cập nhật chậm hơn vài giây nhưng không làm hàng người thanh toán phải chờ.

### Saga *(chuỗi transaction phân tán qua event)*
Chuỗi giao dịch cục bộ + **compensating action** *(hành động bù/hoàn tác nghiệp vụ)* khi lỗi. Hai kiểu:
- **Choreography**: service tự lắng nghe event của nhau (decoupled, khó theo dõi khi nhiều bước).
- **Orchestration**: một orchestrator điều phối (dễ theo dõi, là điểm tập trung).

Saga không hoàn tác vật lý như rollback một transaction DB; hành động bù có thể thất bại và phải retry/monitor. Chọn choreography khi luồng ngắn và team chấp nhận khó quan sát; chọn orchestration khi cần trạng thái quy trình và timeout tập trung.

> 💡 **Giải thích dễ hiểu — Saga là đặt tour nhiều chặng:**
> Nếu đã đặt vé máy bay nhưng khách sạn hết phòng, hệ thống không thể quay ngược thời gian; nó phải hủy vé hoặc hoàn tiền bằng một hành động bù. Điều phối viên giúp biết chuyến đang ở chặng nào.

### Dead Letter Queue *(hàng đợi cách ly lỗi; DLQ)* & Retry Topics *(topic thử lại)* (non-blocking retry)
Message lỗi ("poison pill" — bản ghi luôn lỗi) không nên chặn cả partition:
```
main topic ──(xử lý lỗi)──► retry-5s ──► retry-30s ──► retry-5m ──► DLQ (xem xét thủ công)
            (consumer riêng cho mỗi retry topic với delay tăng dần — non-blocking)
```
> Spring Kafka có `@RetryableTopic`/`DeadLetterPublishingRecoverer` (DLT — dead-letter topic) — xem [../../java/core/messaging.md](../../java/core/messaging.md). Tránh retry tại chỗ (blocking) làm tắc partition. Retry topic có thể làm event cùng key hoàn tất không theo thứ tự ban đầu, nên consumer cần chịu được hoặc tách luồng nghiệp vụ.

> 💡 **Giải thích dễ hiểu — DLQ là quầy xử lý hàng lỗi:**
> Một kiện hỏng được chuyển sang quầy riêng để băng chuyền chính tiếp tục. Nhân viên có thể sửa và gửi lại theo lịch tăng dần; nếu không có người kiểm tra, quầy lỗi sẽ đầy mà không ai biết.

### Compacted topic *(topic được dọn để giữ bản ghi mới nhất theo key)* làm "table"/state
Topic log-compacted giữ **giá trị mới nhất theo key** sau quá trình compaction bất đồng bộ → dùng làm changelog/lookup table (KTable, GlobalKTable), không phải database query tùy ý. Tombstone *(value null)* dùng để đánh dấu xóa. Liên hệ compaction [../internals/storage.md](../internals/storage.md), KTable [../streams/kafka_streams.md](../streams/kafka_streams.md).

> 💡 **Giải thích dễ hiểu — compacted topic là sổ danh bạ chỉ giữ số mới nhất:**
> Khi đổi số điện thoại, sổ có thể tạm thời còn dòng cũ cho tới lúc dọn sổ. Đọc toàn bộ log vẫn có thể thấy lịch sử; đọc state sau compaction mới giống tra cứu bản ghi hiện tại.

---

## Trade-offs & Anti-patterns

### Trade-offs
- (+) Decoupling, khả năng mở rộng (thêm consumer không đụng producer), replay/audit, buffer chịu tải đột biến.
- (−) Eventual consistency *(nhất quán cuối cùng; consumer có thể trễ)*; debug luồng phân tán khó (cần distributed tracing); thiết kế topic/key sai → khó sửa về sau.
- (−) Schema evolution phải kỷ luật; ordering chỉ theo partition; "exactly-once toàn hệ thống" là ảo tưởng → thiết kế idempotent.

Độ bền của Kafka không thay thế retention, replication, backup và kế hoạch replay. Event càng nhiều consumer càng cần hợp đồng schema, ownership và observability rõ ràng; nếu không, một thay đổi nhỏ có thể lan thành sự cố dây chuyền.

> 💡 **Giải thích dễ hiểu — EDA giống mạng lưới đường sắt:**
> Thêm tuyến giúp chở nhiều hàng và nhiều ga cùng nhận, nhưng lịch chạy, biển báo và vé phải thống nhất. Một ga trễ không nhất thiết dừng cả mạng, song hành khách sẽ thấy trạng thái chưa đồng bộ trong một khoảng thời gian.

### Anti-patterns
- **Dùng Kafka như RPC request/reply đồng bộ**: Kafka là async log *(nhật ký bất đồng bộ)*, không phải để chờ response tức thì → dùng REST/gRPC cho sync (xem [../../java/core/networking_http.md](../../java/core/networking_http.md)).
- **Không đặt key khi cần thứ tự** → loạn thứ tự event của entity.
- **Quá nhiều partition** cho topic nhỏ → overhead, rebalance chậm.
- **Message khổng lồ** (file/blob) trong Kafka → dùng claim-check pattern *(lưu blob ở object storage, gửi reference)*.
- **Retry blocking tại chỗ** → tắc partition; dùng retry topics/DLQ.
- **Topic "god"**: nhồi mọi loại event không liên quan vào 1 topic.
- **Đổi số partition** của topic đang chạy có key-based ordering → vỡ mapping.

> 💡 **Giải thích dễ hiểu — anti-pattern là đường tắt có phí ẩn:**
> Nhồi mọi hàng vào một kho hoặc bắt băng chuyền chờ từng kiện lỗi có vẻ đơn giản lúc đầu, nhưng sau này phân loại, mở rộng và truy vết sẽ tốn hơn thiết kế ranh giới ngay từ đầu.

---

## Real-world (Production)

```
E-commerce EDA điển hình:
  order-service ──OrderCreated (key=order_id, state-transfer)──► commerce.order.created
       │ (outbox + Debezium → giảm rủi ro mất event; cần monitor/replay)
       ├──► inventory-service  (reserve stock, idempotent theo order_id)
       ├──► payment-service    (charge; phát PaymentFailed → saga compensate: hủy reservation)
       ├──► notification-service (email; @RetryableTopic → DLQ nếu fail)
       └──► analytics (ksqlDB: funnel/fraud real-time; ClickHouse sink cho OLAP)
```
- Ordering theo `order_id` (key) → event của một đơn được xử lý tuần tự trong cùng topic/partition; không suy ra thứ tự toàn cục giữa nhiều topic.
- At-least-once + idempotent consumer (dedup theo `event_id`/idempotency key; chỉ dùng `order_id` khi mỗi nghiệp vụ chỉ được xử lý một lần).
- Read model: CQRS → Elasticsearch (search) / ClickHouse (analytics, xem [../../clickhouse/clickhouse_production.md](../../clickhouse/clickhouse_production.md)).

Checklist production nên có: schema compatibility và ownership; key/partition skew; consumer lag và retry/DLQ volume; outbox/CDC lag; duplicate rate; trace từ `event_id` qua producer, broker và consumer; retention/replication đủ cho thời gian replay. Khi chạy Saga, theo dõi timeout, trạng thái hành động bù và các workflow bị kẹt, không chỉ trạng thái process là RUNNING.

> 💡 **Giải thích dễ hiểu — production cần bảng theo dõi cả chuyến hàng:**
> Không chỉ kiểm tra xe đã rời kho; phải biết kiện đang ở ga nào, có giao trùng không, hàng lỗi nằm ở quầy nào và còn đủ sổ để chạy lại khi có sự cố.

---

## Ghi chú – Chủ đề tiếp theo
> Tiếp theo: [cluster_operations.md](../operations/cluster_operations.md) — vận hành cluster nâng cao: partition reassignment/scaling, Cruise Control, client quotas, rack awareness, rolling upgrade và capacity planning.

> Liên quan: [../../java/patterns/patterns_enterprise.md](../../java/patterns/patterns_enterprise.md) (CQRS/Saga/Outbox/Event Sourcing), [../../java/core/messaging.md](../../java/core/messaging.md) (Spring Kafka, DLT, Outbox), [../fundamentals/producers.md](../fundamentals/producers.md) (partitioning/EOS), [../fundamentals/consumers.md](../fundamentals/consumers.md) (offset/idempotent), [../ecosystem/schema_registry.md](../ecosystem/schema_registry.md) (event schema evolution).

> Keywords: claim-check pattern, event collaboration, bounded context (DDD), `@RetryableTopic`, tombstone (null value → xóa trong compacted topic), partition key skew, sticky partitioner, fan-out, dual-write problem, change data capture (CDC), read-your-writes.

---

*Cập nhật lần cuối: 2026-07-22*
