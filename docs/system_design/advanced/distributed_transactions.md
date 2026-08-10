---
title: "Distributed Transactions – giữ đúng dữ liệu qua nhiều ranh giới"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "unspecified"
source_count: 5
---
# Distributed Transactions – giữ đúng dữ liệu qua nhiều ranh giới

> Thuật ngữ: [Glossary](../glossary.md).

> Transaction phân tán không chỉ là bài toán “commit hay rollback”. Khi network có
> thể mất phản hồi, service có thể crash và tác động ngoài không thể đảo ngược,
> mục tiêu thực tế là đưa workflow tới một **trạng thái nghiệp vụ hợp lệ, có thể
> giải thích và phục hồi**.

---

## 1. Bài toán thật: invariant vượt qua nhiều service

Ví dụ checkout:

```text
Order DB      : tạo đơn
Inventory DB  : giữ hàng
Payment API   : thu tiền
Shipping DB   : tạo vận đơn
```

Các invariant cần bảo vệ:

- order chỉ `CONFIRMED` khi đã giữ hàng và thu tiền;
- một order không bị thu tiền hai lần;
- một đơn bị hủy không giữ tồn kho mãi;
- mọi trạng thái “không biết kết quả” phải được đối soát.

Trong một database, ACID transaction có thể bảo vệ invariant. Qua nhiều database,
broker hoặc API bên ngoài, không có transaction local nào bao phủ toàn bộ.

```text
BEGIN
  INSERT order       ✅
  reserve inventory  ✅ ở service khác
  charge provider    ? mất response
COMMIT/ROLLBACK nào có thể đảo ngược cả ba?
```

Đây là bài toán **coordination + failure recovery**, không chỉ là cú pháp transaction.

---

## 2. Câu hỏi đầu tiên: có thể tránh transaction phân tán không?

Trước khi chọn 2PC hay Saga:

1. Có thể đặt các dữ liệu cần atomic vào cùng aggregate/service không?
2. Có thể đổi invariant mạnh thành reservation có thời hạn không?
3. Có thể xử lý một bước sau theo asynchronous workflow không?
4. Có thể dùng một source of truth rồi phát read model không?
5. Có thể chấp nhận trạng thái trung gian hiển thị rõ cho người dùng không?

```text
❌ Order Service và OrderLine Service tách DB
   nhưng mọi thay đổi order luôn cần atomic với order line

✅ Cùng Order aggregate/service
   transaction local bảo vệ invariant
```

Transaction local là primitive dễ hiểu và mạnh nhất. Đừng dùng pattern phân tán để
che một service boundary sai.

---

## 3. “Unknown outcome” – trạng thái nguy hiểm nhất

Timeout không có nghĩa thao tác thất bại:

```text
Payment Service ──charge──▶ Provider
                ◀── response bị mất

Payment Service thấy timeout
Provider có thể đã charge thành công
```

Ba kết quả quan trọng:

| Kết quả | Ý nghĩa |
|---|---|
| Success | Biết chắc tác động đã hoàn tất |
| Failure | Biết chắc tác động không xảy ra |
| Unknown | Không biết tác động có xảy ra hay không |

Retry mù trong trạng thái `UNKNOWN` có thể thu tiền hai lần. Cần idempotency key,
query trạng thái theo business reference và reconciliation.

---

## 4. Phổ giải pháp

| Cơ chế | Consistency | Availability | Độ phức tạp | Dùng khi |
|---|---|---|---|---|
| Một local transaction | Mạnh | Cao trong một DB | Thấp | Cùng boundary |
| Optimistic concurrency | Mạnh theo record/version | Cao | Thấp–vừa | Xung đột đồng thời |
| 2PC/XA | Atomic commit | Phụ thuộc mọi participant | Cao | Resource hỗ trợ, phạm vi kiểm soát |
| Saga | Eventual, business-level | Cao hơn 2PC | Cao | Workflow dài, có compensation |
| TCC/reservation | Eventual có giữ tài nguyên | Vừa | Cao | Booking, inventory, quota |
| Outbox + idempotent consumer | Reliable message handoff | Cao | Vừa | DB + broker |
| Reconciliation | Hội tụ sau sai lệch | Cao | Vừa | External side effect/payment |

Không có pattern nào miễn phí. Quyết định phải bắt đầu từ invariant, thời gian cho
phép bất nhất và khả năng bù.

---

## 5. Two-Phase Commit (2PC)

### 5.1 Giao thức

```text
Phase 1 – PREPARE
Coordinator ─prepare(tx-7)─▶ DB A: ghi log, giữ lock, vote YES
            ─prepare(tx-7)─▶ DB B: ghi log, giữ lock, vote YES

Phase 2 – DECIDE
Nếu tất cả YES:
Coordinator ghi COMMIT decision bền vững
            ─commit(tx-7)──▶ DB A
            ─commit(tx-7)──▶ DB B
Nếu có NO: gửi ROLLBACK
```

Sau khi participant vote `YES`, nó đã hứa có thể commit và thường phải giữ lock/
resource cho tới khi biết quyết định cuối. Nếu mất liên lạc với coordinator, nó ở
trạng thái **in-doubt**, không được tự ý rollback nếu coordinator đã quyết commit.

### 5.2 Điều 2PC bảo đảm và không bảo đảm

2PC cung cấp atomic commit khi transaction manager và participants triển khai đúng,
log quyết định bền vững và recovery hoàn tất. Nó không:

- làm dependency luôn available;
- bao phủ email hoặc API không hỗ trợ prepare/commit;
- loại bỏ lock contention;
- tự giải quyết transaction bị bỏ quên;
- biến workflow dài thành lựa chọn tốt.

### 5.3 Failure modes

| Sự cố | Hậu quả |
|---|---|
| Participant không vote | Toàn transaction không thể commit |
| Coordinator mất sau prepare | Participant giữ prepared state/lock chờ recovery |
| Network partition | Availability giảm vì không thể biết quyết định |
| Transaction kéo dài | Lock, MVCC garbage, pool và throughput bị ảnh hưởng |
| Operator xóa sai prepared transaction | Phá atomicity toàn cục |

PostgreSQL cảnh báo prepared transaction giữ lock và cản trở `VACUUM`; tính năng
này dành cho external transaction manager, không nên gọi trực tiếp từ business code.

### 5.4 Khi 2PC hợp lý

- mọi resource thực sự hỗ trợ XA/prepare;
- transaction ngắn;
- cùng một tổ chức quản lý participant và transaction manager;
- atomicity mạnh quan trọng hơn availability;
- có monitoring/recovery cho transaction `PREPARED`.

2PC không “xấu”; nó là đánh đổi coordination mạnh. Nhưng trong microservices đa
database, cloud API và workflow dài, điều kiện trên thường không tồn tại.

---

## 6. Saga: transaction ở mức nghiệp vụ

Saga chia workflow thành local transaction:

```text
T1 CreateOrder
 → T2 ReserveInventory
   → T3 CapturePayment
     → T4 ConfirmOrder
```

Nếu T3 thất bại:

```text
C2 ReleaseInventory
 → C1 CancelOrder
```

Saga không khôi phục database về đúng byte như trước. Compensation tạo một trạng
thái nghiệp vụ mới: payment được `REFUNDED`, order được `CANCELLED`; lịch sử vẫn còn.

---

## 7. Ba loại bước trong Saga

| Loại | Ý nghĩa | Ví dụ |
|---|---|---|
| **Compensable** | Có hành động bù hợp lệ | Reserve → Release |
| **Pivot** | Điểm không thể/không nên quay lại | Vé đã phát hành, hàng đã bàn giao |
| **Retryable** | Sau pivot phải tiến tới thành công | Ghi ledger nội bộ, gửi trạng thái |

Thiết kế thường đặt bước compensable trước, pivot càng muộn càng tốt, rồi các bước
retryable sau pivot.

Email, SMS, notification không thực sự rollback được. Nếu gửi sớm rồi workflow
thất bại, cần gửi thông báo sửa sai chứ không thể “unsend”.

---

## 8. Saga không có isolation như ACID

Hai Saga có thể thấy state trung gian của nhau:

```text
Saga A reserve 7/10 sản phẩm
Saga B đọc còn 3 và bị từ chối
Saga A sau đó payment fail rồi release 7
```

Các anomaly:

- lost update;
- dirty/stale read;
- non-repeatable read;
- write skew;
- overselling do check-then-act.

Biện pháp:

- optimistic version/compare-and-set;
- semantic lock: trạng thái `PENDING`, `RESERVED`;
- reservation có TTL;
- commutative update như `available >= quantity`;
- single-writer theo aggregate key;
- reread trước pivot;
- escrow/quota partitioning.

Saga bảo vệ **atomicity nghiệp vụ theo thời gian**, không tự cung cấp isolation.

---

## 9. Choreography hay orchestration

### 9.1 Choreography

```text
OrderPlaced
  → InventoryReserved
    → PaymentCaptured
      → OrderConfirmed
```

Ưu: không có coordinator riêng, subscriber độc lập. Nhược: flow nằm rải trong
nhiều service, khó thấy timeout/compensation và dễ tạo event cycle.

Phù hợp workflow ngắn, ít nhánh và mỗi reaction có ý nghĩa domain tự nhiên.

### 9.2 Orchestration

```text
CheckoutWorkflow
  ├─ ReserveInventory command
  ├─ CapturePayment command
  ├─ ConfirmOrder command
  └─ khi lỗi: Refund / Release / Cancel
```

Orchestrator lưu durable state và quyết định bước tiếp theo. Nó không nên thực hiện
thay domain logic của participant.

Phù hợp workflow nhiều bước, timeout, parallel branch, compensation hoặc manual
approval. Orchestrator phải chạy HA và state phải phục hồi được; một object trong
memory không phải workflow engine.

Đọc [Event-Driven Architecture](event_driven_architecture.md) mục 13–14 để so sánh
chi tiết.

---

## 10. State machine bền vững

Không biểu diễn Saga bằng chuỗi callback không lưu trạng thái. Dùng state machine:

```text
CREATED
  → INVENTORY_PENDING
      → PAYMENT_PENDING
          → CONFIRMED
          → PAYMENT_UNKNOWN
      → RELEASING
  → CANCELLED
  → MANUAL_REVIEW
```

Mỗi transition cần:

- `workflow_id`/business key ổn định;
- current state + version;
- command/event ID;
- deadline và retry count;
- kết quả/exception đã chuẩn hóa;
- audit lịch sử transition;
- expected-version để một state chỉ chuyển một lần.

```sql
UPDATE checkout_workflow
SET state = 'PAYMENT_PENDING', version = version + 1
WHERE id = :id
  AND state = 'INVENTORY_RESERVED'
  AND version = :expected_version;
```

`updated_rows = 0` nghĩa là command trùng hoặc state đã thay đổi; không được tiếp
tục mù.

---

## 11. Thiết kế compensation

Một compensation tốt:

- idempotent;
- có business key liên kết forward action;
- xử lý được forward action có kết quả `UNKNOWN`;
- không phụ thuộc payload tạm trong memory;
- có retry riêng và timeout;
- có đường manual recovery;
- ghi audit, không xóa lịch sử gốc.

```text
Forward: CapturePayment(orderId, paymentAttemptId)
Compensation: RefundPayment(paymentAttemptId, refundId)
```

Không dùng `RefundPayment(orderId)` nếu một order có thể có nhiều payment attempt;
compensation phải trỏ đúng tác động đã xảy ra.

Một số compensation có thể thất bại vĩnh viễn, ví dụ provider từ chối refund.
Workflow phải chuyển `REFUND_FAILED`/`MANUAL_REVIEW`, không giả vờ rollback xong.

---

## 12. Idempotency đúng cách

### 12.1 Idempotency key là hợp đồng

Client tạo key cho **một ý định nghiệp vụ**:

```http
POST /payments
Idempotency-Key: checkout-ord-123-capture-v1
```

Server lưu:

```text
(scope, key) → request_hash, state, status_code, response, expires_at
```

Quy tắc:

- cùng key + cùng request → trả kết quả cũ hoặc trạng thái đang xử lý;
- cùng key + payload khác → `409 Conflict`;
- insert key và business mutation phải atomic khi cùng DB;
- key có scope theo tenant/operation;
- TTL dài hơn retry window và thời gian client có thể reconnect;
- lưu cả kết quả thành công lẫn outcome cần replay theo policy.

### 12.2 Tránh race `exists → execute → insert`

```text
Worker A: exists? no ─┐
Worker B: exists? no ─┼─▶ cả hai charge
```

Dùng unique constraint và state machine:

```sql
INSERT INTO idempotency_record(scope, key, request_hash, state)
VALUES ('payment', :key, :hash, 'PROCESSING')
ON CONFLICT DO NOTHING;
```

Chỉ owner của record mới thực hiện. Nếu process crash ở `PROCESSING`, cần lease,
fencing/version hoặc recovery query — không tự động coi là chưa chạy.

### 12.3 Idempotent business update

```sql
UPDATE inventory
SET reserved = reserved + :qty
WHERE sku = :sku
  AND available - reserved >= :qty
  AND NOT EXISTS (
    SELECT 1 FROM reservation WHERE reservation_id = :reservation_id
  );
```

Thực tế nên thêm reservation và update stock trong cùng local transaction với
unique `reservation_id`.

---

## 13. Transactional Outbox

Outbox giải dual-write giữa database và broker:

```sql
BEGIN;

INSERT INTO orders(id, status) VALUES (:id, 'PLACED');
INSERT INTO outbox(event_id, aggregate_id, type, payload)
VALUES (:event_id, :id, 'OrderPlaced', :payload);

COMMIT;
```

Relay:

```text
orders + outbox ─same DB transaction─▶ polling relay hoặc CDC
                                         │
                                         ▼
                                       broker
```

Outbox bảo đảm: nếu business transaction commit thì **ý định publish** cũng tồn tại.
Nó không bảo đảm broker chỉ nhận đúng một lần:

```text
publish thành công → relay crash trước mark-published → publish lại
```

Consumer vẫn phải idempotent.

Theo dõi:

- tuổi record outbox chưa publish lâu nhất;
- publish error/retry;
- kích thước bảng và cleanup;
- ordering theo aggregate;
- schema serialization failure;
- relay ownership/partitioning.

---

## 14. Inbox và atomic consume

Consumer lưu message ID và business update trong cùng transaction:

```sql
BEGIN;

WITH accepted AS (
  INSERT INTO inbox(consumer, event_id)
  VALUES ('order-projector', :event_id)
  ON CONFLICT DO NOTHING
  RETURNING 1
)
UPDATE order_view
SET status = :status, version = :event_version
WHERE order_id = :order_id
  AND EXISTS (SELECT 1 FROM accepted);

COMMIT;
```

Sau commit mới ack/commit offset. Nếu crash trước ack, broker giao lại nhưng unique
key ngăn side effect lần hai.

Inbox không giải tác động ngoài database. Với email/payment API, truyền idempotency
key xuống provider hoặc lưu state + reconciliation.

---

## 15. CDC-based Outbox

Change Data Capture đọc database log/WAL thay vì polling table trực tiếp:

```text
DB transaction → WAL/binlog → CDC connector → broker
```

Ưu:

- ít polling query;
- gần realtime;
- thứ tự commit rõ hơn trong một log.

Đánh đổi:

- vận hành connector và schema mapping;
- snapshot/restart/offset;
- quyền đọc transaction log;
- DDL/schema evolution;
- vẫn có duplicate end-to-end.

Đừng publish raw database row như public domain event. Dùng Outbox record có
contract rõ để không rò schema lưu trữ.

---

## 16. Try–Confirm/Cancel (TCC)

TCC yêu cầu participant cung cấp ba operation:

```text
TRY     : giữ tài nguyên tạm thời
CONFIRM : chốt giữ chỗ
CANCEL  : giải phóng
```

Ví dụ booking:

```text
TrySeat(seat-7, hold-123, expires=10m)
TryCredit(user-9, 500k, hold-123)
  nếu tất cả thành công:
ConfirmSeat + ConfirmCredit
  nếu có lỗi:
CancelSeat + CancelCredit
```

TCC phù hợp tài nguyên có thể reservation và cần giảm oversell. Giá phải trả:

- API participant phức tạp hơn;
- giữ tài nguyên làm giảm availability cho người khác;
- cần TTL/reaper cho hold bị bỏ quên;
- confirm/cancel phải idempotent;
- vẫn cần xử lý coordinator mất liên lạc.

---

## 17. Reservation, escrow và TTL

Reservation chuyển invariant “trừ ngay” thành “giữ rồi quyết định”:

```text
available = on_hand - active_reservations
```

Mỗi reservation:

- có `reservation_id` unique;
- trạng thái `HELD | CONFIRMED | RELEASED | EXPIRED`;
- deadline dùng clock server;
- transition có compare-and-set;
- reaper hết hạn idempotent;
- confirm sau expiry có policy rõ.

TTL không tự đủ: job expiry có thể chậm. Read/write path phải coi reservation đã
hết hạn theo timestamp ngay cả khi record chưa được cleanup.

---

## 18. Kafka transaction và phạm vi exactly-once

Kafka hỗ trợ idempotent producer và transaction cho luồng:

```text
consume Kafka → xử lý → produce Kafka + commit offset
```

trong phạm vi Kafka transaction. Nó không biến:

```text
consume Kafka → charge REST provider → ghi database ngoài
```

thành exactly-once. Khi có external side effect, vẫn cần idempotency, Outbox/Inbox
hoặc reconciliation.

Luôn hỏi:

1. Exactly-once cho record nào?
2. Giữa những resource nào?
3. Khi process crash ở từng điểm thì sao?
4. Side effect ngoài transaction được phục hồi thế nào?

---

## 19. Retry, timeout và deadline

Retry chỉ dành cho lỗi tạm thời và operation idempotent:

```text
deadline tổng: 30s
attempt 1 → timeout 3s
backoff + jitter
attempt 2 → timeout 3s
không vượt deadline tổng
```

Không retry:

- validation/business rejection;
- payment `UNKNOWN` mà provider không có idempotency/query;
- compensation cần manual approval;
- conflict phải reread và tính lại.

Mỗi workflow cần timeout nghiệp vụ, không chỉ network timeout:

- inventory hold hết hạn;
- payment pending quá lâu;
- shipment chưa tạo;
- compensation stuck.

Timer phải durable; `Thread.sleep` hoặc scheduler trong một pod không đủ.

---

## 20. Reconciliation: lớp an toàn cuối cùng

Ngay cả thiết kế tốt vẫn có bug, operator mistake và provider mismatch.
Reconciliation so sánh hai source:

```text
Internal payment attempts
          ↕ compare by provider_reference
Provider settlement/report/API
          ↓
missing | duplicate | amount mismatch | unknown
```

Một reconciliation job cần:

- checkpoint và khoảng thời gian quét chồng lấn;
- idempotent repair;
- phân loại tự sửa vs manual review;
- audit trước/sau;
- alert theo giá trị tiền và tuổi sai lệch;
- không dùng một nguồn lỗi để tự xác nhận chính nó.

Với payment/ledger, reconciliation không phải giải pháp phụ; nó là một phần của
correctness.

---

## 21. Ví dụ đầy đủ: checkout

### 21.1 Thành phần

| Thành phần | Source of truth |
|---|---|
| Order | trạng thái đơn |
| Inventory | stock và reservation |
| Payment | payment attempt + provider reference |
| Checkout orchestrator | workflow state |

### 21.2 Happy path

```text
1. CreateOrder(idempotency=checkout-123)
2. ReserveInventory(reservation=checkout-123, TTL=15m)
3. CapturePayment(attempt=checkout-123)
4. ConfirmInventory(reservation=checkout-123)
5. ConfirmOrder(order=123)
```

### 21.3 Payment timeout

```text
CAPTURE_REQUESTED
  → provider timeout
  → PAYMENT_UNKNOWN
  → query provider by idempotency/reference
       ├─ captured → continue confirm
       ├─ not found → retry capture cùng key
       └─ still unknown → MANUAL_REVIEW
```

Không release inventory ngay khi payment timeout nếu payment có thể đã thành công.
State machine quyết định theo outcome được đối soát.

### 21.4 Crash sau mỗi bước

| Điểm crash | Recovery |
|---|---|
| Sau DB update, trước publish | Outbox relay publish |
| Sau publish, trước mark | Có duplicate; consumer dedup |
| Sau provider charge, trước save | Query bằng idempotency/reference |
| Sau compensation, trước ack | Compensation idempotent |
| Orchestrator restart | Load durable state + resume timer/command |

---

## 22. Quan sát và vận hành workflow

Metric/kênh vận hành quan trọng:

- workflow started/completed/failed theo type;
- duration p95/p99 và tuổi workflow đang chạy;
- số workflow theo state;
- retry/compensation/manual-review rate;
- outbox oldest unpublished;
- inbox duplicate rate;
- provider unknown/mismatch;
- reservation expired;
- giá trị tiền đang `UNKNOWN`, không chỉ số lượng.

Metadata:

```text
workflow_id, order_id, event_id,
correlation_id, causation_id,
idempotency_key, participant, transition, version
```

Dashboard phải cho phép tìm một order và thấy timeline end-to-end. Alert kỹ thuật
không thay thế alert invariant, ví dụ “payment captured nhưng order chưa confirmed”.

---

## 23. Bảo mật

- Idempotency key không phải secret và không thay authentication.
- Scope key theo tenant/account để tránh collision hoặc đọc chéo response.
- Không log card token, access token hay payload PII.
- Orchestrator chỉ được gọi command cần thiết; participant vẫn authorization.
- Outbox/Inbox/DLQ có retention và quyền truy cập vì chứa dữ liệu nghiệp vụ.
- Manual repair cần approval, audit và nguyên tắc four-eyes với tiền.
- Webhook/provider callback phải verify signature, timestamp và chống replay.

---

## 24. So sánh nhanh

| Câu hỏi | 2PC | Saga | TCC | Outbox |
|---|---|---|---|---|
| Atomic commit kỹ thuật | Có | Không | Không | Chỉ DB + ý định publish |
| Giữ lock | Thường có | Không xuyên service | Giữ reservation | Không xuyên service |
| External API | Chỉ nếu hỗ trợ participant | Có, qua action/bù | Cần Try/Confirm/Cancel | Chỉ truyền message |
| Workflow dài | Không phù hợp | Phù hợp | Phù hợp có reservation | Là building block |
| Isolation | Theo resource/transaction | Phải tự thiết kế | Reservation giảm conflict | Không cung cấp |
| Duplicate | TM/protocol xử lý trong phạm vi | Participant idempotent | API idempotent | Consumer idempotent |

Các pattern thường kết hợp: Saga orchestration + Outbox + Inbox + idempotency +
reservation + reconciliation.

---

## 25. Failure modes thường gặp

| Anti-pattern/sự cố | Hậu quả | Thay bằng |
|---|---|---|
| Shared DB gọi là “microservices” | Coupling schema/transaction | Sửa boundary hoặc ownership |
| Check-then-insert idempotency | Race, side effect lặp | Unique key + atomic state |
| Timeout = failed | Retry tạo duplicate | Trạng thái `UNKNOWN` + query/reconcile |
| Compensation như `DELETE` lịch sử | Mất audit, sai domain | State transition + action bù |
| Outbox = exactly-once | Consumer vẫn nhận duplicate | Inbox/idempotent consumer |
| Saga chỉ có happy path | Workflow stuck | Timeout, retry, bù, manual state |
| Choreography quá dài | Logic vòng và không owner | Durable orchestrator |
| Reservation chỉ dựa cleanup job | Giữ quá TTL | Check expiry trong read/write path |
| 2PC transaction kéo dài | Lock và availability thấp | Local tx/Saga hoặc rút ngắn |
| Không reconciliation | Sai lệch âm thầm | Đối soát độc lập |

---

## 26. Decision checklist

- [ ] Invariant và source of truth được viết rõ.
- [ ] Đã thử đặt thay đổi atomic vào cùng service/database.
- [ ] Đã định nghĩa `SUCCESS`, `FAILURE`, `UNKNOWN`.
- [ ] Chọn consistency window chấp nhận được.
- [ ] Mỗi action/compensation có idempotency key và scope.
- [ ] Không có race `exists → side effect → insert`.
- [ ] Dual-write dùng Outbox/CDC hoặc atomic mechanism.
- [ ] Consumer dùng Inbox/unique key khi cần.
- [ ] Saga có state machine bền vững, version và timer.
- [ ] Compensation trỏ đúng forward action và có manual fallback.
- [ ] Isolation anomaly được xử lý bằng reservation/version/semantic lock.
- [ ] Có reconciliation cho external side effect.
- [ ] Metric theo state, tuổi workflow và invariant.
- [ ] Runbook repair có audit và authorization.

---

## 27. Câu hỏi phỏng vấn thường gặp

1. Vì sao timeout không đồng nghĩa thất bại?
2. Participant 2PC vote `YES` rồi mất coordinator thì làm gì?
3. Saga khác rollback ACID như thế nào?
4. Saga thiếu isolation gây anomaly gì?
5. Choreography và orchestration phù hợp trường hợp nào?
6. Vì sao Outbox vẫn có thể publish duplicate?
7. Làm idempotency sao cho không có race condition?
8. TCC khác Saga compensation ở đâu?
9. Kafka exactly-once có bảo vệ payment API không?
10. Reconciliation bổ sung correctness thế nào?
11. Bạn phục hồi workflow crash sau khi provider đã charge ra sao?
12. Khi nào nên gộp service thay vì thêm distributed transaction?

---

## 28. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [PostgreSQL – PREPARE TRANSACTION](https://www.postgresql.org/docs/current/sql-prepare-transaction.html)
- [AWS Prescriptive Guidance – Saga patterns](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/saga-patterns.html)
- [AWS Prescriptive Guidance – Transactional Outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html)
- [Stripe – Idempotent requests](https://docs.stripe.com/api/idempotent_requests)
- [Apache Kafka – Message delivery semantics](https://kafka.apache.org/documentation/#semantics)

Đọc tiếp:

- [Event-Driven Architecture](event_driven_architecture.md) – delivery, ordering,
  retry, Outbox/Inbox và replay.
- [Microservices](microservices.md) – boundary và data ownership.
- [API Design](api_design.md) – idempotency contract, status code và webhook.
- [Payment/Ledger case study](../case_studies/platform_designs.md) – double-entry
  ledger và reconciliation.

---

*Cập nhật lần cuối: 2026-07-31*
