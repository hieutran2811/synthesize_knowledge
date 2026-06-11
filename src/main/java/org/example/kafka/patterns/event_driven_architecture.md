# Event-Driven Architecture & Data Modeling (Kafka-native) – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
> Bổ trợ góc **Kafka-native** cho các pattern khái niệm ở [../../java/patterns/patterns_enterprise.md](../../java/patterns/patterns_enterprise.md) (CQRS/Saga/Outbox/Event Sourcing) và [../../java/core/messaging.md](../../java/core/messaging.md) (Spring Kafka DLT/Outbox).

---

## What – EDA với Kafka

**Event-Driven Architecture (EDA)** dùng **event** (sự kiện đã xảy ra) làm phương tiện giao tiếp giữa các service. Kafka đóng vai trò **log trung tâm bền vững** — "hệ thần kinh" của hệ thống: producer phát event, nhiều consumer độc lập tiêu thụ, có thể replay.

```
Service A ──(OrderCreated)──► Kafka topic ──┬──► Service B (gửi email)
                                            ├──► Service C (cập nhật kho)
                                            └──► Service D (analytics)   ← decouple, mỗi consumer độc lập
```

---

## How – Topic Design & Naming

### Granularity: một topic cho cái gì?
| Chiến lược | Mô tả | Khi dùng |
|-----------|-------|----------|
| **1 topic / event type** | `orders.created`, `orders.shipped` riêng | Phổ biến; consumer chọn lọc loại event |
| **1 topic / entity (nhiều event type)** | Mọi event của `order` vào `orders` | Cần **giữ thứ tự** mọi event của 1 entity (cùng key) → cần Record/TopicRecordNameStrategy ([../ecosystem/schema_registry.md](../ecosystem/schema_registry.md)) |
| **1 topic / aggregate domain** | `payments`, `inventory` | Bounded context (DDD) |

### Naming convention
```
<domain>.<entity>.<event-type>        vd: commerce.order.created
<environment>.<domain>.<entity>       vd: prod.billing.invoice
```
> Nhất quán naming → dễ governance/ACL/discovery. Tránh đổi tên topic (consumer phụ thuộc).

---

## How – Partitioning & Key Strategy (quan trọng nhất)

### Key quyết định partition → quyết định thứ tự
```
record key ──hash──► partition   (cùng key → cùng partition → ĐẢM BẢO THỨ TỰ)
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

---

## Compare – 3 phong cách Event Design

| | Event Notification | Event-Carried State Transfer | Event Sourcing |
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
> **Event-carried state transfer** thường được ưa chuộng cho microservices (consumer không phải gọi ngược → bớt coupling, chịu lỗi tốt hơn). Event design + schema evolution đi chung: [../ecosystem/schema_registry.md](../ecosystem/schema_registry.md).

---

## How – Delivery Semantics & Idempotent Consumer

| Semantic | Cơ chế | Đánh đổi |
|----------|--------|----------|
| At-most-once | Commit offset **trước** xử lý | Có thể mất message |
| **At-least-once** (mặc định phổ biến) | Commit offset **sau** xử lý | Có thể **lặp** message → cần idempotent |
| Exactly-once | Transactions (consume-process-produce) | Phức tạp, chỉ trong phạm vi Kafka |

### Idempotent Consumer (xử lý "at-least-once" an toàn)
Vì at-least-once có thể giao lặp, consumer phải **idempotent** (xử lý lại không gây tác dụng phụ kép):
```
- Dedup bằng business key / event id (lưu id đã xử lý → bỏ qua nếu trùng)
- UPSERT thay vì INSERT (ghi đè theo key)
- Dùng (topic, partition, offset) hoặc event_id làm khóa dedup trong DB
```
> EOS transaction của Kafka chỉ "exactly-once" **trong Kafka** (consume→produce); tác dụng phụ ra ngoài (gửi email, ghi DB khác) vẫn cần idempotent. Liên hệ EOS ở [../fundamentals/producers.md](../fundamentals/producers.md) & [../fundamentals/consumers.md](../fundamentals/consumers.md).

---

## Components – Các EDA pattern (góc Kafka)

### Transactional Outbox (nhất quán DB ↔ Kafka)
Bài toán: ghi DB **và** publish Kafka phải nguyên tử (không có 2PC). Giải: ghi event vào bảng `outbox` **trong cùng transaction DB**; một relay (Debezium CDC) đọc outbox → publish Kafka.
```
Service: BEGIN; INSERT order; INSERT outbox(event); COMMIT;
Debezium CDC ──đọc outbox (binlog)──► Kafka topic   (đảm bảo at-least-once, không mất)
```
> Khái niệm/triển khai Spring: [../../java/core/messaging.md](../../java/core/messaging.md), [../../java/patterns/patterns_enterprise.md](../../java/patterns/patterns_enterprise.md). CDC: [../streams/connect.md](../streams/connect.md).

### CQRS (Command Query Responsibility Segregation)
Tách ghi (command → event vào Kafka) khỏi đọc (consumer build **read model** tối ưu cho query: Elasticsearch, materialized view, ksqlDB table).
```
Command → write model → emit events (Kafka) → consumers → read models (ES/CH/ksqlDB)
```
> Read model qua ksqlDB table + pull query: [../ecosystem/ksqldb.md](../ecosystem/ksqldb.md).

### Saga (distributed transaction qua events)
Chuỗi giao dịch cục bộ + **compensating action** khi lỗi. Hai kiểu:
- **Choreography**: service tự lắng nghe event của nhau (decoupled, khó theo dõi khi nhiều bước).
- **Orchestration**: một orchestrator điều phối (dễ theo dõi, là điểm tập trung).

### Dead Letter Queue & Retry Topics (non-blocking retry)
Message lỗi ("poison pill") không nên chặn cả partition:
```
main topic ──(xử lý lỗi)──► retry-5s ──► retry-30s ──► retry-5m ──► DLQ (xem xét thủ công)
            (consumer riêng cho mỗi retry topic với delay tăng dần — non-blocking)
```
> Spring Kafka có `@RetryableTopic`/`DeadLetterPublishingRecoverer` (DLT) — xem [../../java/core/messaging.md](../../java/core/messaging.md). Tránh retry tại chỗ (blocking) làm tắc partition.

### Compacted topic làm "table"/state
Topic log-compacted giữ **giá trị mới nhất theo key** → dùng làm changelog/lookup table (KTable, GlobalKTable). Liên hệ compaction [../internals/storage.md](../internals/storage.md), KTable [../streams/kafka_streams.md](../streams/kafka_streams.md).

---

## Trade-offs & Anti-patterns

### Trade-offs
- (+) Decoupling, khả năng mở rộng (thêm consumer không đụng producer), replay/audit, buffer chịu tải đột biến.
- (−) Eventual consistency (consumer trễ); debug luồng phân tán khó (cần tracing); thiết kế topic/key sai → khó sửa về sau.
- (−) Schema evolution phải kỷ luật; ordering chỉ theo partition; "exactly-once toàn hệ thống" là ảo tưởng → thiết kế idempotent.

### Anti-patterns
- **Dùng Kafka như RPC request/reply đồng bộ**: Kafka là async log, không phải để chờ response tức thì → dùng REST/gRPC cho sync (xem [../../java/core/networking_http.md](../../java/core/networking_http.md)).
- **Không đặt key khi cần thứ tự** → loạn thứ tự event của entity.
- **Quá nhiều partition** cho topic nhỏ → overhead, rebalance chậm.
- **Message khổng lồ** (file/blob) trong Kafka → dùng claim-check (lưu blob ở S3, gửi reference).
- **Retry blocking tại chỗ** → tắc partition; dùng retry topics/DLQ.
- **Topic "god"**: nhồi mọi loại event không liên quan vào 1 topic.
- **Đổi số partition** của topic đang chạy có key-based ordering → vỡ mapping.

---

## Real-world

```
E-commerce EDA điển hình:
  order-service ──OrderCreated (key=order_id, state-transfer)──► commerce.order.created
       │ (outbox + Debezium → không mất event)
       ├──► inventory-service  (reserve stock, idempotent theo order_id)
       ├──► payment-service    (charge; phát PaymentFailed → saga compensate: hủy reservation)
       ├──► notification-service (email; @RetryableTopic → DLQ nếu fail)
       └──► analytics (ksqlDB: funnel/fraud real-time; ClickHouse sink cho OLAP)
```
- Ordering theo `order_id` (key) → mọi event 1 đơn xử lý tuần tự.
- At-least-once + idempotent consumer (dedup theo order_id/event_id).
- Read model: CQRS → Elasticsearch (search) / ClickHouse (analytics, xem [../../clickhouse/clickhouse_production.md](../../clickhouse/clickhouse_production.md)).

---

## Ghi chú – Chủ đề tiếp theo
> `operations/cluster_operations.md`: vận hành cluster nâng cao – partition reassignment & scaling, Cruise Control, client quotas, rack awareness, rolling upgrade, capacity planning.

> Liên quan: [../../java/patterns/patterns_enterprise.md](../../java/patterns/patterns_enterprise.md) (CQRS/Saga/Outbox/Event Sourcing), [../../java/core/messaging.md](../../java/core/messaging.md) (Spring Kafka, DLT, Outbox), [../fundamentals/producers.md](../fundamentals/producers.md) (partitioning/EOS), [../fundamentals/consumers.md](../fundamentals/consumers.md) (offset/idempotent), [../ecosystem/schema_registry.md](../ecosystem/schema_registry.md) (event schema evolution).

> Keywords: claim-check pattern, event collaboration, bounded context (DDD), `@RetryableTopic`, tombstone (null value → xóa trong compacted topic), partition key skew, sticky partitioner, fan-out, dual-write problem, change data capture (CDC), read-your-writes.

---

*Cập nhật lần cuối: 2026-06-04*
