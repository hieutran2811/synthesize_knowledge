# Event-Driven Architecture – thiết kế hệ thống xoay quanh sự kiện

> Event-Driven Architecture (EDA) giúp producer và consumer không phải chạy cùng
> lúc hoặc biết trực tiếp về nhau. Đổi lại, tính đúng đắn chuyển từ một call stack
> dễ nhìn sang bài toán duplicate, ordering, eventual consistency và vận hành broker.

---

## 1. Mô hình tư duy

**Event** là bản ghi bất biến mô tả một sự thật đã xảy ra:

```text
OrderPlaced, PaymentCaptured, InventoryReservationExpired
```

Producer publish event vào broker/log; consumer nhận và cập nhật state riêng:

```text
Order Service ──OrderPlaced──▶ Event Broker
                               ├─▶ Inventory
                               ├─▶ Notification
                               └─▶ Analytics
```

EDA tạo coupling lỏng hơn về **thời gian** và **địa chỉ**:

- producer không cần consumer đang online;
- consumer không cần endpoint của producer;
- thêm consumer mới không buộc producer thay đổi.

Nhưng vẫn còn coupling qua **ý nghĩa, schema, ordering và kỳ vọng delivery**.
“Không gọi trực tiếp nhau” không có nghĩa “không phụ thuộc nhau”.

---

## 2. Event, command và message không giống nhau

| Loại | Cách đặt tên | Ý nghĩa | Số bên xử lý mong đợi |
|---|---|---|---|
| **Event** | Quá khứ: `OrderPlaced` | Một sự thật đã xảy ra | 0..N |
| **Command** | Mệnh lệnh: `ReserveInventory` | Yêu cầu một capability thực hiện việc | Thường 1 |
| **Query** | Câu hỏi: `GetOrderStatus` | Đọc dữ liệu, không đổi state | Thường 1 |
| **Message** | Khái niệm vận chuyển chung | Envelope chứa event/command/query | Tùy loại |

Sai lầm phổ biến:

```text
❌ Event giả command: SendEmailRequestedToNotificationService
✅ Command          : SendOrderConfirmation
✅ Domain event     : OrderConfirmed
```

Event nên mô tả domain, không gắn tên consumer. Nếu cần một bên chịu trách nhiệm
và biết thành công/thất bại, đó thường là command hoặc workflow orchestration.

---

## 3. Ba kiểu event integration

### 3.1 Event Notification

Payload tối thiểu, consumer gọi lại owner để lấy dữ liệu:

```json
{"type": "OrderChanged", "orderId": "ord-123"}
```

Ưu: event nhỏ, owner giữ source of truth. Nhược: tạo call ngược, tăng tải và có
race — khi consumer gọi lại, state có thể đã đổi lần nữa.

### 3.2 Event-Carried State Transfer

Event mang đủ dữ liệu consumer cần:

```json
{
  "type": "OrderPlaced",
  "orderId": "ord-123",
  "customerId": "cus-7",
  "total": {"amount": "590000", "currency": "VND"}
}
```

Ưu: consumer độc lập và có thể dựng read model. Nhược: sao chép dữ liệu, payload
lớn hơn và phải quản lý PII/schema.

### 3.3 Event Sourcing

Event là **nguồn sự thật** để dựng lại aggregate, không chỉ là thông báo tích hợp.
Đây là lựa chọn sâu hơn nhiều; không mặc định mọi hệ EDA đều dùng event sourcing.

---

## 4. Broker kiểu queue và log

| Đặc tính | Queue/message broker | Distributed log/stream |
|---|---|---|
| Mục tiêu chính | Giao việc cho worker | Lưu luồng sự kiện có thứ tự theo partition |
| Sau consume | Thường xóa/ack khỏi queue | Giữ theo retention, consumer giữ offset |
| Replay | Hạn chế hoặc phải thiết kế thêm | Tự nhiên hơn |
| Fan-out | Exchange/topic/subscription | Nhiều consumer group đọc cùng log |
| Phù hợp | Task queue, routing linh hoạt | Event stream, CDC, replay, analytics |

Không chọn broker bằng bảng throughput trên Internet. Cần benchmark với:

- payload và compression thực;
- replication/durability;
- số partition/queue và consumer;
- retention, replay và backlog;
- latency p95/p99;
- failure/failover và chi phí vận hành.

Đôi khi một hệ thống dùng cả hai: queue cho job command, log cho domain event.

---

## 5. Event envelope và hợp đồng

Một envelope thực dụng:

```json
{
  "specversion": "1.0",
  "id": "01J9M3Y7R51R6B9R9KPK8F4ZP1",
  "source": "/commerce/orders",
  "type": "com.example.order.placed.v1",
  "subject": "orders/ord-123",
  "time": "2026-07-30T08:15:31Z",
  "datacontenttype": "application/json",
  "data": {
    "orderId": "ord-123",
    "customerId": "cus-7",
    "totalMinor": 590000,
    "currency": "VND"
  },
  "correlationid": "checkout-456",
  "causationid": "cmd-789"
}
```

CloudEvents chuẩn hóa metadata cốt lõi như `id`, `source`, `type`,
`specversion`; domain payload vẫn do tổ chức định nghĩa. `source + id` nên xác
định duy nhất một event.

| Field | Mục đích |
|---|---|
| `id` | Dedup và truy vết |
| `type` | Contract/routing; nên ổn định |
| `subject`/aggregate ID | Partition key và đối tượng nghiệp vụ |
| `time` | Thời điểm nghiệp vụ; không dùng một mình để ordering |
| `correlationid` | Nối cùng một user journey/workflow |
| `causationid` | Event/command nào trực tiếp gây ra message này |
| schema/version | Kiểm tra compatibility |

Không đặt secret, access token hoặc PII không cần thiết vào event: log có retention
dài và nhiều consumer hơn database giao dịch.

---

## 6. Delivery semantics: lời hứa thực tế

### 6.1 At-most-once

Message có thể mất nhưng không giao lại. Phù hợp telemetry/sample mà mất một ít
không ảnh hưởng nghiệp vụ.

### 6.2 At-least-once

Message không bị bỏ qua miễn hệ thống phục hồi đúng, nhưng có thể giao lặp. Đây là
mô hình phổ biến và yêu cầu consumer idempotent.

```text
1. Consumer xử lý side effect thành công
2. Consumer crash trước khi commit/ack offset
3. Broker giao lại message
4. Side effect có nguy cơ chạy lần hai
```

### 6.3 Exactly-once: phải hỏi “trong phạm vi nào?”

Một nền tảng có thể cung cấp exactly-once trong phạm vi log/transaction của nó.
Điều đó không tự động bao phủ email, HTTP API, database ngoài hoặc payment provider.

```text
Kafka read → transform → Kafka write
             có thể dùng transaction trong phạm vi Kafka

Kafka read → charge card qua provider
             vẫn cần idempotency key/reconciliation
```

Trong system design, phát biểu an toàn là: **giả định redelivery có thể xảy ra và
thiết kế side effect idempotent**, trừ khi đã chứng minh atomicity end-to-end.

---

## 7. Idempotency và deduplication

Consumer xử lý cùng message nhiều lần nhưng tạo cùng kết quả:

```sql
BEGIN;

WITH accepted AS (
  INSERT INTO processed_message(consumer_name, event_id)
  VALUES ('inventory-reserver', 'evt-123')
  ON CONFLICT DO NOTHING
  RETURNING 1
)
UPDATE inventory
SET reserved = reserved + 2
WHERE product_id = 'prod-9'
  AND EXISTS (SELECT 1 FROM accepted);

COMMIT;
```

Các kỹ thuật:

| Kỹ thuật | Dùng khi | Lưu ý |
|---|---|---|
| Unique key `consumer + event_id` | Dedup message tổng quát | Cùng transaction với side effect |
| Business idempotency key | Payment/order creation | Cùng key phải cùng request fingerprint |
| Upsert state cuối | Projection | Event cũ không được ghi đè event mới |
| Conditional write/version | Cần chống out-of-order | So sánh sequence/version |
| Set có TTL | Duplicate window hữu hạn | TTL quá ngắn sẽ lọt duplicate cũ |

Chỉ kiểm tra `exists` rồi mới `insert` không atomic; hai worker có thể cùng đi qua.
Dùng unique constraint hoặc compare-and-set.

---

## 8. Ordering: broker chỉ đảm bảo trong một phạm vi

Trong Kafka, record cùng key đi vào cùng partition và được đọc theo thứ tự trong
partition đó. Không có total order toàn topic khi có nhiều partition.

```text
partition key = orderId

P0: OrderPlaced(123) → PaymentCaptured(123) → OrderShipped(123)
P1: OrderPlaced(456) → PaymentFailed(456)
```

Chọn key theo invariant cần giữ thứ tự, không chỉ để phân phối đều. Một “celebrity
key” có thể tạo hot partition.

Để chống event đến sai thứ tự:

- thêm `aggregateVersion` tăng đơn điệu;
- consumer chỉ apply version kế tiếp hoặc giữ buffer hữu hạn;
- bỏ qua event cũ khi read model đã có version mới hơn;
- có luồng repair/rebuild nếu gap không được lấp;
- tránh dùng timestamp máy làm sequence tuyệt đối.

Ordering mạnh hơn làm giảm song song. Chỉ yêu cầu thứ tự theo entity nếu nghiệp vụ
không cần global order.

---

## 9. Consumer group, parallelism và backpressure

Trong một consumer group, mỗi partition tại một thời điểm được gán cho tối đa một
consumer. Vì vậy:

```text
parallelism hữu ích ≤ số partition có dữ liệu hoạt động
```

Thêm consumer vượt số partition không tăng throughput. Tăng partition có ảnh hưởng
đến ordering, key distribution, rebalance và tài nguyên broker nên cần capacity plan.

Khi producer nhanh hơn consumer:

1. Đo lag theo **tuổi message**, không chỉ số lượng record.
2. Scale consumer nếu partition và downstream còn headroom.
3. Batch/I/O song song nhưng vẫn giữ ordering cần thiết.
4. Áp quota hoặc backpressure ở producer.
5. Tách workload latency-sensitive khỏi bulk.
6. Load shed công việc có thể bỏ thay vì làm sập downstream.

Queue giúp hấp thụ burst, không tạo thêm công suất. Nếu tốc độ vào trung bình lớn
hơn tốc độ xử lý trung bình, backlog sẽ tăng vô hạn.

---

## 10. Retry, poison message và DLQ

Phân loại lỗi trước khi retry:

| Lỗi | Ví dụ | Hành động |
|---|---|---|
| Tạm thời | timeout, dependency 503 | Retry có backoff + jitter |
| Vĩnh viễn do dữ liệu | schema sai, field bắt buộc thiếu | Quarantine/DLQ |
| Nghiệp vụ | hết hàng, card bị từ chối | Phát outcome event, không retry mù |
| Bug | null pointer cho một payload | Dừng/isolated retry, sửa code |

Retry ngay trong main partition có thể chặn mọi event sau cùng partition. Hai mẫu:

```text
main topic → retry-1m → retry-10m → retry-1h → DLQ
```

hoặc lưu `next_attempt_at` trong retry store/queue phù hợp.

DLQ không phải nghĩa địa:

- lưu payload gốc, error, stack/version và số lần thử;
- alert theo rate và tuổi message;
- có UI/runbook để inspect, sửa, replay có kiểm soát;
- replay vẫn phải idempotent;
- giới hạn quyền vì DLQ có thể chứa dữ liệu nhạy cảm.

---

## 11. Transactional Outbox

### 11.1 Dual-write problem

```text
BEGIN
  INSERT order          ✅
COMMIT
publish OrderPlaced     ❌ process/network lỗi
```

Database đã có order nhưng broker không có event. Đảo thứ tự chỉ tạo lỗi ngược:
event tồn tại nhưng transaction database rollback.

### 11.2 Outbox

Ghi business state và outbox record trong **cùng local transaction**:

```sql
BEGIN;

INSERT INTO orders(id, status)
VALUES ('ord-123', 'PLACED');

INSERT INTO outbox(event_id, aggregate_id, event_type, payload)
VALUES ('evt-789', 'ord-123', 'OrderPlaced', '{...}');

COMMIT;
```

Relay publish outbox qua polling hoặc Change Data Capture (CDC):

```text
orders + outbox ─same transaction─▶ DB log
                                      │
                               relay / CDC
                                      ▼
                                    broker
```

Outbox bảo đảm không mất ý định publish khi DB commit, nhưng relay vẫn có thể
publish lặp nếu crash trước khi đánh dấu. Consumer vẫn phải idempotent.

Các quyết định vận hành:

- thứ tự outbox theo aggregate;
- cleanup/retention và index bảng outbox;
- quan sát oldest unpublished event;
- payload/schema được tạo trong transaction;
- tránh nhiều relay publish cùng record nếu không có locking/partitioning đúng.

---

## 12. Inbox pattern

Inbox là phía nhận của Outbox:

```text
consume message
  └─ local transaction:
       1. insert inbox(event_id) với unique constraint
       2. cập nhật business state
       3. commit
  └─ sau đó ack/commit offset
```

Nếu crash trước bước ack, message được giao lại nhưng unique key ngăn side effect
lần hai. Inbox đặc biệt hữu ích khi business update và dedup cùng nằm trong một
database.

---

## 13. Choreography và orchestration

### 13.1 Choreography

Mỗi service phản ứng với event và phát event mới:

```text
OrderPlaced
  → InventoryReserved
    → PaymentCaptured
      → OrderConfirmed
```

Ưu: ít coordinator, thêm subscriber dễ. Nhược: flow ẩn trong nhiều service, khó
biết ai chịu trách nhiệm, dễ tạo event cycle/storm.

Phù hợp flow ngắn, ít nhánh, consumer thực sự độc lập.

### 13.2 Orchestration

Coordinator giữ state machine và gửi command:

```text
Checkout Saga
  ├─ command ReserveInventory
  ├─ command CapturePayment
  ├─ command ArrangeShipping
  └─ khi lỗi: ReleaseInventory / RefundPayment
```

Ưu: flow, timeout, compensation và audit tập trung. Nhược: coordinator phải bền,
scale được và không chứa toàn bộ domain logic của các service.

Orchestrator không nhất thiết là SPOF: chạy nhiều replica với durable state và
single-writer/optimistic concurrency theo workflow.

---

## 14. Saga và compensation

Saga là chuỗi local transaction; mỗi bước thành công có một bước bù nếu luồng sau
thất bại.

| Forward action | Compensation có thể có |
|---|---|
| Reserve inventory | Release reservation |
| Capture payment | Refund payment |
| Create shipment | Cancel shipment nếu chưa giao |

Không phải mọi hành động đảo ngược được: email đã gửi, hàng đã giao, giá thị trường
đã đổi. Do đó:

- chia bước thành **compensable**, **pivot** và **retryable**;
- trì hoãn hành động không đảo ngược tới sau pivot khi có thể;
- lưu state, deadline và lịch sử transition;
- compensation phải idempotent;
- có trạng thái `MANUAL_REVIEW` cho trường hợp không tự phục hồi được.

Chi tiết 2PC, Saga và recovery ở
[Distributed Transactions](distributed_transactions.md).

---

## 15. CQRS

CQRS tách model ghi (command) và model đọc (query), không bắt buộc tách service hay
database:

```text
Command → Write Model → events → Projection → Read Model
Query  ─────────────────────────────────────▶ Read Model
```

Dùng khi write model có invariant phức tạp nhưng read có access pattern rất khác,
hoặc cần nhiều projection:

- PostgreSQL view cho back-office;
- search index cho full-text;
- key-value/cache cho trang chi tiết;
- warehouse cho analytics.

Giá phải trả:

- projection lag và read-your-writes;
- rebuild/backfill;
- nhiều schema/storage và code đồng bộ;
- xử lý duplicate/out-of-order.

CRUD đơn giản không cần CQRS. Có thể bắt đầu bằng class/model tách riêng trong cùng
service rồi chỉ tách hạ tầng khi có áp lực thật.

---

## 16. Event Sourcing

### 16.1 State từ chuỗi event

```text
OrderCreated(v1)
PaymentCaptured(v2)
ShippingAddressChanged(v3)
OrderShipped(v4)
          │ replay
          ▼
Order hiện tại: SHIPPED, version=4
```

Event store cần:

- append-only theo stream/aggregate;
- optimistic concurrency: append chỉ khi expected version khớp;
- event bất biến;
- snapshot tùy chọn để giảm thời gian dựng aggregate;
- projection có thể reset/rebuild.

### 16.2 Khi nào đáng dùng

Phù hợp khi lịch sử và khả năng giải thích state là requirement cốt lõi: ledger,
workflow phức tạp, audit domain, temporal query. Không dùng chỉ để “có audit log”;
một audit table/change log có thể đơn giản hơn.

Khó khăn lớn:

- event cũ tồn tại rất lâu, migration không giống update row;
- bug trong event handler có thể làm projection sai;
- xóa/ẩn dữ liệu cá nhân khó hơn;
- replay side effect phải bị chặn;
- team phải hiểu modeling theo aggregate/version.

Event Sourcing, EDA và CQRS là ba khái niệm độc lập dù thường dùng cùng nhau.

---

## 17. Replay, rebuild và backfill

Replay là một tính năng production, không phải nút “chạy lại tất cả”:

```text
historical topic/event store
        │
        ├─▶ projection_v2 (shadow)
        │      validate count/hash/sample
        └─▶ atomic switch alias/read route
```

Checklist replay:

- chọn offset/time/aggregate range rõ;
- dùng consumer group hoặc output namespace mới;
- không gửi email/charge payment lại;
- throttle để không làm nghẽn broker/downstream;
- đo progress, error và estimated completion;
- kiểm tra tính đúng bằng count, checksum và sample nghiệp vụ;
- có thể dừng/resume;
- chỉ chuyển traffic sau validation.

Với event-carried state transfer, event lịch sử có thể không chứa field mới. Backfill
có thể cần snapshot từ source of truth thay vì giả định replay luôn đủ.

---

## 18. Schema evolution

Mục tiêu là producer và consumer có thể deploy lệch phiên bản.

Thay đổi thường an toàn hơn:

- thêm field optional với default rõ;
- consumer bỏ qua field chưa biết;
- giữ nghĩa field cũ;
- producer phát format mà consumer cũ vẫn đọc trong giai đoạn chuyển đổi.

Thay đổi nguy hiểm:

- đổi kiểu/đơn vị (`amount` từ đồng sang xu);
- rename/xóa field ngay;
- biến optional thành required;
- đổi partition key;
- tái sử dụng event type cho ý nghĩa khác.

Chiến lược:

1. **Additive evolution** trong cùng type/schema.
2. **New event type/version** khi semantics thay đổi.
3. **Upcaster/adapter** đổi event cũ sang model mới khi đọc.
4. **Dual publish có thời hạn** khi migration lớn, kèm metric và ngày xóa.

Schema Registry giúp enforce compatibility; nó không biết thay đổi **ngữ nghĩa**.
Contract review và consumer test vẫn cần. AsyncAPI có thể mô tả channel, operation
và message dưới dạng machine-readable.

---

## 19. Event time, processing time và late event

| Khái niệm | Nghĩa |
|---|---|
| Event time | Lúc sự kiện thực sự xảy ra ở nguồn |
| Ingestion time | Lúc broker nhận |
| Processing time | Lúc consumer xử lý |

Network/offline device/retry làm event tới muộn hoặc sai thứ tự. Với window
aggregation, cần:

- watermark/allowed lateness;
- quy tắc cập nhật kết quả đã phát;
- dedup;
- phân biệt dashboard realtime với số liệu finalized;
- theo dõi độ trễ theo event age.

Không dùng `now()` ở consumer để thay event time cho nghiệp vụ nếu event có thể trễ.

---

## 20. Khả năng quan sát và vận hành

Theo dõi theo từng topic/consumer group:

- publish rate/error/latency;
- consume rate và **lag theo thời gian**;
- retry/DLQ rate, oldest message;
- rebalance, partition skew/hot key;
- deserialize/schema error;
- processing latency và downstream error;
- business state stuck, ví dụ order `PAYMENT_PENDING` quá 15 phút.

Metadata để lần theo luồng:

```text
trace_id       : nối span kỹ thuật
correlation_id : cùng checkout/workflow
causation_id   : message nào sinh message này
event_id       : danh tính để dedup
```

Không tạo metric label trực tiếp từ `orderId`/`eventId`; cardinality sẽ bùng nổ.
ID chi tiết thuộc log/trace, metric dùng dimension hữu hạn.

---

## 21. Bảo mật và quản trị dữ liệu

- ACL theo producer/consumer và topic, quyền tối thiểu.
- TLS in transit, encryption at rest, key rotation.
- Không tin payload chỉ vì đến từ broker; validate schema và authorization context.
- Không đưa token/secret vào message.
- Phân loại PII, retention và nơi lưu theo data residency.
- Audit quyền đọc/replay; replay thường mở rộng phạm vi truy cập dữ liệu.
- Với “right to erasure”, cân nhắc tokenization, crypto-shredding hoặc tách PII
  khỏi immutable event thay vì nhét toàn bộ snapshot vào log.

EDA tăng số bản sao dữ liệu. Data governance phải được thiết kế cùng event, không
đợi tới khi có yêu cầu xóa dữ liệu.

---

## 22. Ví dụ: checkout có khả năng phục hồi

### 22.1 Invariant

- Một `orderId` chỉ có một kết quả payment cuối cùng.
- Không xác nhận order nếu inventory chưa reserve và payment chưa capture.
- Mọi command/event có ID ổn định.
- State transition dùng expected version.

### 22.2 State machine

```text
PLACED
  ├─ InventoryReserved → PAYMENT_PENDING
  │    ├─ PaymentCaptured → CONFIRMED
  │    └─ PaymentFailed   → RELEASING_INVENTORY → REJECTED
  └─ InventoryRejected   → REJECTED

timeout/unknown → MANUAL_REVIEW hoặc reconciliation
```

### 22.3 Failure walkthrough

Payment provider đã charge nhưng consumer crash trước khi lưu kết quả:

1. Broker giao lại `CapturePayment`.
2. Payment service gọi provider bằng cùng `idempotencyKey=orderId`.
3. Provider trả kết quả cũ thay vì charge lần hai.
4. Payment service lưu state + `PaymentCaptured` vào Outbox.
5. Relay có thể publish lặp; Saga dedup theo event ID.
6. Reconciliation định kỳ so sánh payment nội bộ với provider để bắt unknown state.

Đây là “effectively once” ở mức nghiệp vụ nhờ idempotency và reconciliation, không
phải vì transport không bao giờ giao lặp.

---

## 23. Failure modes thường gặp

| Sự cố | Biểu hiện | Phòng vệ |
|---|---|---|
| Dual write | DB có state nhưng thiếu event | Transactional Outbox |
| Consumer xử lý lặp | Trừ tiền/gửi mail hai lần | Inbox, unique key, idempotency |
| Poison message | Partition đứng | Retry phân tầng, quarantine/DLQ |
| Hot partition | Một partition lag rất xa | Key tốt, split logical key, workload isolation |
| Event storm/cycle | Lưu lượng tăng theo cấp số | Ownership, causation graph, quota |
| Schema phá tương thích | Deserialize error hàng loạt | Registry, additive change, contract test |
| Replay gây side effect | Email/payment lặp | Tách projection và side-effect consumer |
| DLQ không ai xử lý | Dữ liệu âm thầm thiếu | SLO, alert, owner, replay tooling |
| Consumer lag vô hạn | Queue chỉ che thiếu công suất | Capacity, backpressure, load shedding |
| Choreography quá dài | Không ai hiểu toàn flow | Chuyển workflow phức tạp sang orchestration |

---

## 24. Decision checklist

Trước khi đưa một luồng lên broker:

- [ ] Đã nói rõ đây là event hay command và ai sở hữu contract.
- [ ] Lý do async là burst, fan-out, temporal decoupling hoặc workflow — không chỉ vì “scale”.
- [ ] Delivery semantics và phạm vi ordering được ghi rõ.
- [ ] Partition/routing key bám theo invariant, đã xem nguy cơ hot key.
- [ ] Consumer idempotent; dedup và side effect cùng transaction khi có thể.
- [ ] Dual write dùng Outbox/CDC hoặc cơ chế atomic tương đương.
- [ ] Retry phân biệt transient/permanent/business error; DLQ có owner/runbook.
- [ ] Schema compatibility, retention và PII policy rõ.
- [ ] Có lag/oldest-message/business-stuck alert.
- [ ] Replay/backfill được throttle, kiểm chứng và không kích hoạt side effect.
- [ ] Workflow có timeout, compensation và manual recovery.

---

## 25. Câu hỏi phỏng vấn thường gặp

1. Event khác command như thế nào?
2. EDA giảm loại coupling nào và vẫn giữ loại coupling nào?
3. At-least-once gây duplicate ở điểm nào?
4. Exactly-once của broker có bảo vệ một HTTP side effect không?
5. Vì sao Outbox vẫn cần consumer idempotent?
6. Chọn partition key theo tiêu chí gì?
7. Khi một poison message chặn partition, bạn xử lý thế nào?
8. Choreography và orchestration phù hợp với flow nào?
9. CQRS có bắt buộc dùng event sourcing không?
10. Làm sao replay projection mà không gửi lại email?
11. Schema Registry không phát hiện được loại breaking change nào?
12. Bạn đo consumer lag bằng record count hay thời gian, vì sao?

---

## 26. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [CloudEvents Specification](https://github.com/cloudevents/spec) – envelope
  trung lập nhà cung cấp; stable release hiện tại là 1.0.2.
- [AsyncAPI Specification](https://github.com/asyncapi/spec) – mô tả API bất
  đồng bộ dưới dạng machine-readable.
- [Apache Kafka Documentation – Introduction](https://kafka.apache.org/documentation/#intro_concepts_and_terms)
  – topic, partition, key và consumer.
- [Apache Kafka Design – Message Delivery Semantics](https://kafka.apache.org/documentation/#semantics)
  – at-most-once, at-least-once và phạm vi exactly-once.

Đọc tiếp:

- [Distributed Transactions](distributed_transactions.md) – Saga, Outbox, 2PC
  và idempotency chi tiết.
- [Microservices](microservices.md) – service boundary và giao tiếp.
- [Storage & Retrieval](../fundamentals/storage_retrieval.md) – WAL, log và
  schema evolution.
- [Kafka Architecture](../../kafka/fundamentals/architecture.md),
  [Producer](../../kafka/fundamentals/producers.md),
  [Consumer](../../kafka/fundamentals/consumers.md) và
  [Schema Registry](../../kafka/ecosystem/schema_registry.md).

---

*Cập nhật lần cuối: 2026-07-30*
