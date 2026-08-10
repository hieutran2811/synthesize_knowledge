---
title: "RabbitMQ Reliability & Guarantees"
topic: rabbitmq
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "RabbitMQ 4"
source_count: 11
---
# RabbitMQ Reliability & Guarantees

> Thuật ngữ: [Glossary](glossary.md).

> Phạm vi chính: RabbitMQ 4.3, AMQP 0-9-1 và Java client.
>
> Mục tiêu: biết chính xác mỗi acknowledgement bảo vệ chặng nào, thiết kế at-least-once không mất message ngoài ý muốn và xử lý duplicate đúng cách.

## 1. Reliability là trách nhiệm của cả chuỗi

RabbitMQ không thể một mình bảo đảm nghiệp vụ đầu cuối. Mỗi lần dữ liệu chuyển quyền sở hữu cần một cơ chế xác nhận riêng:

```text
Business DB
    │ cùng DB transaction
    ▼
Outbox
    │ publish + mandatory + publisher confirm
    ▼
RabbitMQ queue
    │ durable/quorum replication
    ▼
Consumer
    │ business transaction commit rồi manual ack
    ▼
Target DB / external system
```

| Chặng | Cơ chế chính | Cửa sổ lỗi còn lại |
|---|---|---|
| Business DB → Outbox | Cùng một database transaction | Worker có thể publish lặp sau crash |
| Publisher → Exchange/Queue | `mandatory`, return handler, publisher confirms | Confirm có thể thất lạc, phải gửi lại |
| Broker → Storage/Replica | Durable topology, persistent message, quorum queue | Mất quorum làm queue tạm không khả dụng |
| Queue → Consumer | Manual acknowledgement, prefetch, timeout | Consumer có thể xử lý xong nhưng chưa ack |
| Consumer → Target DB | Inbox/idempotency trong cùng transaction | External side effect cần idempotency riêng |

> 💡 **Quy tắc cốt lõi**
>
> Khi sender chưa nhận được xác nhận, nó không thể phân biệt “receiver chưa làm” với “receiver đã làm nhưng xác nhận bị mất”. Muốn tránh mất dữ liệu, sender phải thử lại; thử lại đồng nghĩa receiver có thể thấy duplicate.

---

## 2. At-most-once, At-least-once và Exactly-once

### 2.1 Ba semantics

| Semantics | Khi gặp trạng thái không chắc chắn | Hệ quả |
|---|---|---|
| **At-most-once** | Không gửi/xử lý lại | Có thể mất, không chủ động tạo duplicate |
| **At-least-once** | Gửi/xử lý lại | Không mất nếu các giả định đúng, nhưng có thể duplicate |
| **Exactly-once** | Một business effect duy nhất | Cần phạm vi transaction/idempotency rõ ràng; RabbitMQ không cung cấp end-to-end tự động |

Ví dụ:

```text
Consumer cập nhật DB thành công
        │
        ├── ack tới broker thành công → xong
        │
        └── process chết trước ack
                    ↓
             broker redeliver
                    ↓
          cùng nghiệp vụ chạy lần hai
```

Manual ack tạo nền tảng **at-least-once delivery**, không tự tạo exactly-once business processing.

### 2.2 “Exactly-once” phải nói rõ phạm vi

Có thể đạt “mỗi message chỉ tạo một lần thay đổi trong database X” bằng:

- message có ID ổn định;
- bảng inbox có unique constraint;
- ghi inbox và thay đổi nghiệp vụ trong cùng database transaction.

Không thể suy rộng điều đó thành “email, payment, HTTP call và mọi database đều chạy đúng một lần” nếu các hệ thống không cùng transaction hoặc không hỗ trợ idempotency key.

---

## 3. Durability – message có sống qua restart không?

### 3.1 Bốn mảnh ghép

```text
1. Durable exchange
2. Durable queue/binding
3. Persistent message
4. Publisher confirm
```

| Mảnh ghép | Bảo vệ điều gì? | Không bảo vệ điều gì? |
|---|---|---|
| Durable exchange | Định nghĩa exchange qua restart | Message body |
| Durable queue | Định nghĩa queue qua restart | HA nếu đó là classic queue một replica |
| Persistent message (`delivery_mode=2`) | Yêu cầu lưu message bền vững | Publisher biết lúc nào broker đã hoàn tất |
| Publisher confirm | Broker báo đã nhận trách nhiệm | Consumer đã xử lý nghiệp vụ |

Java:

```java
channel.exchangeDeclare(
    "orders.events",
    com.rabbitmq.client.BuiltinExchangeType.TOPIC,
    true
);

channel.queueDeclare(
    "billing.order-events",
    true,
    false,
    false,
    Map.of("x-queue-type", "quorum")
);

channel.queueBind(
    "billing.order-events",
    "orders.events",
    "order.#"
);

AMQP.BasicProperties properties = new AMQP.BasicProperties.Builder()
    .deliveryMode(2)
    .contentType("application/json")
    .messageId(eventId)
    .build();
```

### 3.2 Classic queue và Quorum queue

| Queue type | Replication | Confirm của persistent message |
|---|---|---|
| Classic | Không replicated trong RabbitMQ 4.x | Sau khi queue chấp nhận/persist theo semantics của queue |
| Quorum | Raft, nhiều replica | Sau khi đa số replica chấp nhận và xác nhận với leader |

Quorum queue là lựa chọn mặc định khi message quan trọng cần HA/data safety. Nếu queue mất đa số replica, nó dừng phục vụ thay vì chấp nhận state không an toàn.

RabbitMQ có thể gom nhiều disk write để giảm `fsync`; confirm latency vì vậy không cố định. Đừng suy ra throughput bằng một con số chung hoặc chờ confirm riêng từng message nếu cần lưu lượng cao.

---

## 4. Publisher Confirms

### 4.1 Confirm thực sự chứng minh gì?

Sau `confirmSelect()`, mỗi publish trên channel có sequence number. Broker trả:

- `basic.ack`: broker đã nhận trách nhiệm;
- `basic.nack`: broker gặp lỗi nội bộ và publisher phải xem publish đó chưa thành công.

Với message routable:

- broker chỉ confirm sau khi mọi target queue đã chấp nhận message;
- persistent message tới durable queue được confirm sau khi persistence condition hoàn tất;
- với quorum queue, đa số replica phải chấp nhận.

Với message **không route được**, broker vẫn có thể gửi confirm `ack`: exchange đã xử lý publish thành công nhưng tìm thấy zero queue. Vì vậy confirm không thay thế `mandatory`.

```text
Publisher ── publish mandatory=true ──► Exchange
                                            │
                                      không có route
                                            │
Publisher ◄── basic.return ─────────────────┤
Publisher ◄── confirm ack ──────────────────┘

return luôn được gửi trước confirm cho publish đó
```

### 4.2 Ba chiến lược confirm

| Cách | Ưu điểm | Nhược điểm |
|---|---|---|
| Publish rồi chờ từng confirm | Code đơn giản | Serialization round-trip, throughput thấp |
| Publish một batch rồi chờ | Đơn giản hơn async, throughput khá | Lỗi batch khó xác định từng message |
| Streaming async confirms | Throughput tốt, biết từng sequence | Cần quản lý pending state, timeout và concurrency |

Production publisher lưu lượng cao thường dùng streaming async confirms với số lượng pending bị giới hạn.

### 4.3 Java async confirms an toàn hơn

```java
import com.rabbitmq.client.ConfirmCallback;
import com.rabbitmq.client.Return;
import java.util.List;
import java.util.Map;
import java.util.NavigableMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentNavigableMap;
import java.util.concurrent.ConcurrentSkipListMap;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.atomic.AtomicBoolean;

enum PublishStatus {
    CONFIRMED,
    NACKED,
    UNROUTABLE
}

record PublishOutcome(
    String messageId,
    PublishStatus status,
    String reason
) {
    static PublishOutcome confirmed(String id) {
        return new PublishOutcome(id, PublishStatus.CONFIRMED, null);
    }

    static PublishOutcome nacked(String id) {
        return new PublishOutcome(id, PublishStatus.NACKED, null);
    }

    static PublishOutcome unroutable(String id, String reason) {
        return new PublishOutcome(id, PublishStatus.UNROUTABLE, reason);
    }
}

final class PendingMessage {
    final String messageId;
    final String routingKey;
    final byte[] body;
    final AtomicBoolean returned = new AtomicBoolean(false);

    PendingMessage(String messageId, String routingKey, byte[] body) {
        this.messageId = messageId;
        this.routingKey = routingKey;
        this.body = body;
    }
}

ConcurrentNavigableMap<Long, PendingMessage> pendingBySequence =
    new ConcurrentSkipListMap<>();
Map<String, PendingMessage> pendingById =
    new ConcurrentHashMap<>();
BlockingQueue<PublishOutcome> outcomes =
    new LinkedBlockingQueue<>();

channel.confirmSelect();

ConfirmCallback onAck = (sequence, multiple) -> {
    NavigableMap<Long, PendingMessage> confirmed =
        multiple
            ? pendingBySequence.headMap(sequence, true)
            : pendingBySequence.subMap(sequence, true, sequence, true);

    List<PendingMessage> completed = List.copyOf(confirmed.values());
    confirmed.clear();

    for (PendingMessage message : completed) {
        pendingById.remove(message.messageId);
        if (!message.returned.get()) {
            outcomes.offer(PublishOutcome.confirmed(message.messageId));
        }
    }
};

ConfirmCallback onNack = (sequence, multiple) -> {
    NavigableMap<Long, PendingMessage> failed =
        multiple
            ? pendingBySequence.headMap(sequence, true)
            : pendingBySequence.subMap(sequence, true, sequence, true);

    List<PendingMessage> messages = List.copyOf(failed.values());
    failed.clear();

    for (PendingMessage message : messages) {
        pendingById.remove(message.messageId);
        outcomes.offer(PublishOutcome.nacked(message.messageId));
    }
};

channel.addConfirmListener(onAck, onNack);

channel.addReturnListener((Return returned) -> {
    String messageId = returned.getProperties().getMessageId();
    PendingMessage message = pendingById.get(messageId);
    if (message != null) {
        message.returned.set(true);
        outcomes.offer(PublishOutcome.unroutable(
            messageId,
            returned.getReplyText()
        ));
    }
});
```

Publishing phải do một thread sở hữu channel hoặc được tuần tự hóa:

```java
long sequence = channel.getNextPublishSeqNo();
PendingMessage pending = new PendingMessage(
    eventId,
    "order.created",
    body
);

pendingBySequence.put(sequence, pending);
pendingById.put(eventId, pending);

try {
    channel.basicPublish(
        "orders.events",
        pending.routingKey,
        true,
        new AMQP.BasicProperties.Builder()
            .deliveryMode(2)
            .messageId(eventId)
            .contentType("application/json")
            .build(),
        body
    );
} catch (Exception publishFailure) {
    pendingBySequence.remove(sequence);
    pendingById.remove(eventId);
    throw publishFailure;
}
```

Các callback chỉ cập nhật state/enqueue outcome nhanh; không query database, chờ network hoặc republish trực tiếp trong callback thread.

### 4.4 Pending window và confirm timeout

Publisher phải đặt giới hạn:

```text
max pending messages
max pending bytes
max confirm age
```

Nếu connection mất hoặc confirm quá hạn:

1. Xem mọi publish chưa confirm là **unknown**, không phải chắc chắn thất bại.
2. Retry từ nguồn bền vững như Outbox.
3. Giữ nguyên `message_id`.
4. Consumer xử lý idempotent vì broker có thể đã giữ bản đầu.

Không buffer vô hạn message chưa confirm trong heap; khi broker chậm, hãy backpressure upstream hoặc để backlog nằm trong database/outbox.

---

## 5. `mandatory`, Return và Alternate Exchange

| Tình huống | Confirm | Return khi `mandatory=true` |
|---|---|---|
| Route vào queue thành công | Ack sau khi queue chấp nhận | Không |
| Không binding nào khớp | Vẫn có thể Ack | Có |
| Exchange không tồn tại | Channel error | Không phải cơ chế xử lý |
| Broker internal error | Nack hoặc channel/connection failure | Tùy giai đoạn |

Một publish chỉ được xem thành công nghiệp vụ khi:

```text
confirmed == true
AND returned == false
```

Nếu dùng alternate exchange và nó route được message, publisher không nhận return. Khi đó đội vận hành phải theo dõi queue “unrouted” như một error channel.

---

## 6. Transactional Outbox

### 6.1 Vấn đề dual write

```java
orderRepository.save(order);   // commit thành công
rabbitPublisher.publish(event); // process chết ở đây
```

Database có order nhưng event không tồn tại. Đổi thứ tự publish trước cũng không giải quyết: event có thể phát ra nhưng database rollback.

### 6.2 Ghi business data và outbox cùng transaction

```sql
BEGIN;

INSERT INTO orders(id, customer_id, status)
VALUES (:order_id, :customer_id, 'CREATED');

INSERT INTO outbox(
    id,
    aggregate_id,
    event_type,
    exchange_name,
    routing_key,
    payload,
    status,
    created_at
) VALUES (
    :event_id,
    :order_id,
    'order.created.v2',
    'orders.events',
    'order.created',
    :payload,
    'PENDING',
    CURRENT_TIMESTAMP
);

COMMIT;
```

Hoặc cả hai cùng tồn tại, hoặc không có cái nào.

### 6.3 Outbox relay đúng failure semantics

```text
1. Claim batch PENDING bằng lease/row lock
2. Publish với message_id = outbox.id
3. Theo dõi mandatory return + publisher confirm
4. Confirmed và không returned → đánh dấu SENT
5. Nack/return → PENDING hoặc FAILED theo policy
6. Timeout/relay crash → lease hết hạn, publish lại
```

Không đánh dấu `SENT` ngay sau `basicPublish()` vì lệnh này bất đồng bộ.

```text
publish tới broker thành công
        │
        ├── relay nhận confirm, chưa update DB rồi crash
        │
        └── row vẫn PENDING → publish lại → duplicate
```

Outbox bảo vệ khỏi mất event, nhưng không loại duplicate. Đó là trade-off đúng của at-least-once.

Các chi tiết production:

- claim bằng `SELECT ... FOR UPDATE SKIP LOCKED` hoặc lease có expiry;
- giới hạn batch và pending confirms;
- retry có backoff/jitter;
- index theo `(status, next_attempt_at)`;
- metric oldest pending age, retry count và failed rows;
- archive/delete row `SENT` theo retention;
- payload/schema version bất biến sau khi tạo.

---

## 7. Consumer Acknowledgements

### 7.1 Ack là chuyển quyền sở hữu

```text
Ready ── deliver ──► Unacknowledged
                         ├── ack ───────────────► broker có thể xóa
                         ├── reject no-requeue ─► DLX/drop
                         ├── reject requeue ────► queue/delayed retry
                         └── connection mất ────► tự requeue
```

Java:

```java
DeliverCallback callback = (consumerTag, delivery) -> {
    long tag = delivery.getEnvelope().getDeliveryTag();

    try {
        applicationService.handleInTransaction(
            delivery.getProperties().getMessageId(),
            delivery.getBody()
        );

        // Chỉ ack sau khi transaction nghiệp vụ commit.
        channel.basicAck(tag, false);
    } catch (NonRetryableException e) {
        channel.basicReject(tag, false);
    } catch (RetryableException e) {
        channel.basicReject(tag, true);
    }
};

channel.basicConsume(queueName, false, callback, cancelCallback);
```

### 7.2 Ack/Nack phải đúng channel

Delivery tag chỉ có ý nghĩa trong channel nhận delivery. Ack tag đó trên channel khác gây `unknown delivery tag` và đóng channel.

| Method | Phạm vi | Hành vi |
|---|---|---|
| `basicAck(tag, false)` | Một delivery | Thành công |
| `basicAck(tag, true)` | Mọi outstanding tag ≤ tag | Batch success |
| `basicReject(tag, true/false)` | Một delivery | Requeue hoặc dead-letter/drop |
| `basicNack(tag, multiple, requeue)` | Một hoặc nhiều delivery | RabbitMQ extension |

Batch ack chỉ an toàn khi application biết mọi delivery trước tag đó đã hoàn tất. Nếu callback chuyển việc sang thread pool và hoàn tất lệch thứ tự, `multiple=true` có thể ack nhầm task chưa xong. Khi xử lý song song, ack từng delivery hoặc có bộ điều phối contiguous completion cẩn thận.

### 7.3 Auto ack

`autoAck=true` làm broker coi delivery hoàn tất ngay khi gửi ra socket:

- process chết trước business logic → message mất;
- không có cửa sổ prefetch manual-ack để giới hạn unacked;
- client dễ bị quá tải nếu callback không theo kịp.

Chỉ dùng khi mất message chấp nhận được và consumer xử lý cực nhanh, ổn định.

### 7.4 `redelivered` là hint

RabbitMQ đặt `redelivered=true` khi biết delivery đã được giao lại. Đây là tín hiệu hữu ích để quan sát/deduplicate, nhưng không thay thế `message_id`:

- `true`: message có thể đã được consumer thấy;
- `false`: broker bảo đảm delivery chưa được thấy trước đó theo knowledge của broker.

Business idempotency vẫn nên dùng ID ổn định do publisher tạo.

---

## 8. Inbox Pattern và Idempotent Consumer

### 8.1 Cách làm sai phổ biến

```text
SET processed:<messageId> NX
        │
        └── process chết trước business update

Lần retry thấy key tồn tại → bỏ qua → nghiệp vụ bị mất
```

Một distributed cache flag tách khỏi business database không tạo atomicity.

### 8.2 Inbox và business update cùng transaction

```sql
CREATE TABLE consumed_message (
    subscriber_id VARCHAR(100) NOT NULL,
    message_id    VARCHAR(100) NOT NULL,
    consumed_at   TIMESTAMP NOT NULL,
    PRIMARY KEY (subscriber_id, message_id)
);
```

Luồng:

```text
BEGIN
  INSERT consumed_message(subscriber_id, message_id)
  nếu duplicate key:
      COMMIT/ROLLBACK và coi là đã xử lý
  nếu insert thành công:
      UPDATE business tables
COMMIT
ACK RabbitMQ
```

Nếu process chết:

| Thời điểm crash | Kết quả khi redelivery |
|---|---|
| Trước DB commit | Transaction rollback, xử lý lại |
| Sau DB commit nhưng trước ack | Inbox unique conflict, bỏ qua business update rồi ack |
| Sau ack | Message đã hoàn tất |

Ví dụ Spring:

```java
@Transactional
public ProcessingResult handleInTransaction(
    String messageId,
    byte[] payload
) {
    int inserted = inboxRepository.insertIfAbsent(
        "billing-service",
        messageId
    );

    if (inserted == 0) {
        return ProcessingResult.DUPLICATE;
    }

    InvoiceCreated event = decoder.decode(payload);
    invoiceRepository.apply(event);
    return ProcessingResult.APPLIED;
}
```

Ack phải xảy ra sau khi method transaction đã return/commit.

### 8.3 External side effects

Nếu consumer gọi payment/email/HTTP API:

- truyền `message_id` hoặc business operation ID làm idempotency key nếu downstream hỗ trợ;
- lưu state `PENDING/SUCCEEDED/FAILED` và response để retry;
- không giả định timeout nghĩa là downstream chưa thực thi;
- thiết kế compensation/manual reconciliation nếu không thể deduplicate.

---

## 9. Prefetch và số message in-flight

RabbitMQ áp prefetch riêng cho mỗi consumer theo mặc định:

```java
channel.basicQos(20);
```

Tổng số delivery tối đa đang giữ phía consumer:

```text
instances × consumers mỗi instance × prefetch

5 instances × 4 consumers × 20 = 400 unacknowledged
```

Prefetch ảnh hưởng đồng thời:

- throughput và network utilization;
- memory client/broker;
- độ công bằng giữa consumer;
- số message phải redeliver khi process chết;
- ordering và thời gian message priority cao phải chờ.

Quy trình tune:

1. Bắt đầu gần mức concurrency xử lý thực.
2. Đo consumer utilization và processing latency.
3. Tăng dần nếu worker rảnh do chờ delivery.
4. Giảm nếu unacked/memory/redelivery spike hoặc phân phối lệch.
5. Load test với message size và downstream latency giống production.

Không dùng các bảng “task nhanh = prefetch 500” như quy luật chung.

---

## 10. Consumer Timeout trong RabbitMQ 4.3

RabbitMQ 4.3 chuyển consumer timeout vào quorum queue. Classic queue và stream không còn đánh giá timeout này như cơ chế cũ.

```bash
rabbitmqctl set_policy \
  --vhost production \
  order-consumer-timeout \
  '^orders\.process$' \
  '{"consumer-timeout":300000}' \
  --apply-to quorum_queues
```

Thứ tự ưu tiên cấu hình:

1. Consumer argument `x-consumer-timeout`.
2. Queue argument `x-consumer-timeout`.
3. Policy `consumer-timeout`.
4. Global `consumer_timeout` trong `rabbitmq.conf` (mặc định 30 phút).

Khi quorum consumer giữ delivery quá hạn:

- outstanding message được trả về queue để redeliver;
- AMQP 0-9-1 client có `consumer_cancel_notify` nhận `basic.cancel` cho consumer đó;
- client cũ không hỗ trợ capability có thể bị đóng channel.

Timeout phải lớn hơn thời gian xử lý hợp lệ ở percentile cao, gồm cả pause GC/downstream tail latency. Nếu task có thể chạy hàng giờ, nên tách task thành checkpoint nhỏ hoặc dùng hệ thống workflow thay vì giữ delivery unacked quá lâu.

---

## 11. Poison Message và At-least-once Dead-lettering

Quorum queue RabbitMQ 4.x có delivery limit; mặc định từ 4.0 là 20 failed deliveries. RabbitMQ 4.3 phân biệt message được trả lại với delivery thực sự failed.

```bash
rabbitmqctl set_policy \
  --vhost production \
  order-safety \
  '^orders\.process$' \
  '{
    "delivery-limit":5,
    "dead-letter-exchange":"orders.dlx",
    "dead-letter-routing-key":"orders.failed"
  }' \
  --apply-to quorum_queues
```

Không tắt limit bằng `-1` nếu không có lý do migration rõ ràng; poison message có thể tạo vòng lặp và làm Raft log tăng.

### 11.1 DLX mặc định vẫn có failure window

Dead-lettering là một lần publish nội bộ. Mặc định RabbitMQ có thể xóa message khỏi source queue sau khi publish sang DLX mà không dùng publisher confirms nội bộ; nếu target queue không sẵn sàng, message có thể mất.

Quorum queue hỗ trợ **at-least-once dead-lettering**, dùng confirms nội bộ để chỉ xóa khỏi source sau khi target chấp nhận. Tính năng này tăng data safety nhưng cần cấu hình và capacity cho dead-letter worker/internal backlog.

```bash
rabbitmqctl set_policy \
  --vhost production \
  order-at-least-once-dlx \
  '^orders\.process$' \
  '{
    "dead-letter-strategy":"at-least-once",
    "overflow":"reject-publish",
    "dead-letter-exchange":"orders.dlx",
    "dead-letter-routing-key":"orders.failed",
    "max-length":100000
  }' \
  --priority 20 \
  --apply-to quorum_queues
```

Điều kiện quan trọng:

- source phải là quorum queue;
- `dead-letter-strategy=at-least-once`;
- overflow phải là `reject-publish`, không phải `drop-head`;
- DLX và ít nhất một target route hợp lệ phải tồn tại;
- feature flag `stream_queue` phải enabled nếu cluster cũ chưa bật;
- message gốc nên persistent và target queue durable nếu dead letter phải sống qua restart.

Internal worker có thể retry publish sang target và tạo duplicate nếu confirm thất lạc, nên DLQ consumer vẫn phải idempotent. Khi target không khả dụng lâu, dead-lettered message tiếp tục chiếm capacity ở source queue.

Luôn:

- khai báo DLX/target queue trước khi cần;
- theo dõi dead-lettered message rate và DLQ depth;
- giới hạn retry;
- kiểm thử khi target queue mất quorum hoặc đầy;
- có runbook replay DLQ idempotent.

---

## 12. AMQP Transactions

```java
channel.txSelect();
try {
    channel.basicPublish(
        "",
        "results",
        properties,
        body
    );
    channel.basicAck(deliveryTag, false);
    channel.txCommit();
} catch (Exception e) {
    channel.txRollback();
    throw e;
}
```

Transactions có thể nhóm AMQP operations trên **cùng channel**, nhưng:

- không bao gồm transaction của application database;
- không tạo end-to-end exactly-once;
- mỗi commit là synchronous coordination và giảm throughput;
- channel transaction mode và publisher confirm mode loại trừ nhau.

Phần lớn hệ thống nên dùng:

- publisher confirms cho publish safety;
- manual ack cho consume safety;
- Outbox cho DB → RabbitMQ;
- Inbox/idempotency cho RabbitMQ → DB.

Chỉ dùng AMQP transaction khi thật sự cần atomicity giữa AMQP operations trên cùng broker/channel và đã benchmark workload.

---

## 13. Connection Recovery không phải Message Recovery

Java client có thể tự:

- reconnect;
- mở lại channel;
- restore QoS/confirm mode;
- redeclare exchanges, queues, bindings;
- register lại consumers.

Nhưng automatic recovery **không buffer hoặc gửi lại publish trong lúc connection down**.

```text
Topology recovery = khôi phục đường ống
Publisher state   = ứng dụng tự khôi phục hàng hóa chưa được xác nhận
```

Publisher phải giữ unconfirmed message trong Outbox/bộ nhớ có giới hạn và gửi lại sau recovery. Channel bị đóng vì protocol/application error như khai báo queue sai thuộc tính cũng không nên tự động phục hồi mù; cần sửa nguyên nhân.

Consumer cũng phải chấp nhận delivery đang xử lý bị requeue khi connection mất.

---

## 14. Flow Control và Resource Alarms

### 14.1 Hai loại tín hiệu

| Tín hiệu | Nguyên nhân | Quan sát |
|---|---|---|
| `flow` | Publisher nhanh hơn queue/storage/replication | Connection thường xuyên bị throttle |
| `blocked` / `blocking` | Memory hoặc disk alarm | Publisher bị dừng cho đến khi alarm clear |

Flow control là backpressure bình thường, không phải lỗi cần reconnect liên tục.

### 14.2 Alarm phạm vi cluster

Khi một node vượt memory watermark hoặc thiếu disk, alarm có thể block publishing connections trên toàn cluster. Consumer-only connection vẫn có thể drain queue.

Với AMQP 0-9-1, nên tách connection publish và consume nếu muốn consumer tiếp tục hoạt động ổn định khi publish connection bị block.

Java blocked listener:

```java
connection.addBlockedListener(
    reason -> metrics.publisherBlocked(reason),
    () -> metrics.publisherUnblocked()
);
```

Khi bị block:

- không đẩy message vô hạn vào heap của publisher;
- tăng outbox backlog có giới hạn và backpressure request ingress;
- alert theo blocked duration, disk/memory alarm;
- không coi I/O timeout là chắc chắn publish thất bại;
- tiếp tục giải phóng backlog qua consumer path.

---

## 15. Ordering Guarantees

RabbitMQ cố giữ thứ tự enqueue:

- publish trên một channel được enqueue theo publication order trong từng target queue;
- nhiều channel/connection publish đồng thời có thể interleave;
- queue deliver theo enqueue order trước các yếu tố làm thay đổi.

Thứ tự quan sát/hoàn tất có thể đổi do:

- nhiều active consumers;
- consumer xử lý song song;
- priority;
- reject/nack/requeue hoặc connection mất;
- delayed retry;
- message TTL/dead-letter;
- side effect có latency khác nhau.

Publisher confirms cũng bất đồng bộ và có thể xác nhận một hoặc nhiều sequence; application không nên dựa vào thứ tự confirm.

Nếu cần ordering theo entity:

1. Hash stable entity ID vào queue shard.
2. Single Active Consumer hoặc một processing lane mỗi shard.
3. Sequence number trong event.
4. Idempotency và xử lý gap/duplicate.
5. Không đổi shard count mà không có migration/repartition plan.

---

## 16. Observability cho Reliability

### Publisher

- pending confirm count/bytes;
- confirm latency p50/p95/p99;
- nack, return và confirm timeout rate;
- publish exception/recovery count;
- blocked/flow duration;
- outbox pending count và oldest age.

### Broker

- messages ready/unacknowledged;
- publish, confirm, deliver, ack, redelivery rate;
- quorum availability/leader election;
- disk/memory alarms;
- unroutable dropped/returned;
- DLQ depth và dead-letter rate.

### Consumer

- processing latency và error class;
- ack/reject/requeue rate;
- duplicate/inbox conflict rate;
- consumer cancellation/timeout;
- prefetch, concurrency và in-flight;
- downstream timeout/circuit state.

Alert theo xu hướng và SLO, không chỉ một threshold queue depth cố định. Ví dụ backlog 10.000 message có thể bình thường nếu drain trong 30 giây, nhưng nghiêm trọng nếu oldest message đã 20 phút.

---

## 17. Failure Matrix

| Failure | Message có thể ở đâu? | Hành động |
|---|---|---|
| Publisher chết trước publish | Chỉ Outbox | Relay publish sau |
| Publisher chết sau publish, trước confirm | Broker có thể đã nhận | Retry cùng message ID |
| Confirm ack nhưng message unroutable | Return đã tới trước ack | Đánh dấu routing failure |
| Broker node chết trước quorum confirm | Chưa chắc được commit | Retry sau recovery |
| Consumer chết trước DB commit | Queue sẽ redeliver | Transaction rollback, xử lý lại |
| Consumer chết sau DB commit, trước ack | DB đã đổi, queue redeliver | Inbox nhận duplicate rồi ack |
| Downstream timeout | Có thể đã thực thi | Idempotency key/reconciliation |
| DLQ target không khả dụng | Default DLX có thể mất transfer | At-least-once DLX hoặc runbook/capacity |
| Memory/disk alarm | Publisher bị block | Drain, backpressure, xử lý resource |
| Consumer giữ message quá timeout | Quorum queue trả lại message | Xử lý cancel, tune timeout |

---

## 18. Checklist production

### Publisher

- [ ] Business write và Outbox cùng database transaction.
- [ ] Message ID ổn định, không tạo ID mới khi retry.
- [ ] Publisher confirms bật trước publish.
- [ ] `mandatory=true` hoặc alternate exchange có giám sát.
- [ ] Pending confirm bị giới hạn theo count, bytes và age.
- [ ] Nack/return/timeout đều có state transition rõ ràng.
- [ ] Không làm I/O chậm trong confirm callback.

### Broker/topology

- [ ] Exchange/queue/binding durable.
- [ ] Message quan trọng persistent.
- [ ] Quorum queue dùng khi cần replication/HA.
- [ ] Delivery limit, delayed retry và DLQ được cấu hình.
- [ ] Kiểm thử mất node, mất quorum, queue đầy và DLQ unavailable.
- [ ] Memory/disk alarm và blocked connection có alert.

### Consumer

- [ ] Manual ack sau business commit.
- [ ] Inbox unique constraint hoặc idempotency tương đương.
- [ ] Không dùng delivery tag làm business message ID.
- [ ] Retryable/non-retryable được phân loại.
- [ ] Prefetch/concurrency được load test.
- [ ] Consumer timeout phù hợp tail latency.
- [ ] External side effect dùng idempotency key/reconciliation.

---

## 19. Chủ đề tiếp theo

Tiếp theo: [RabbitMQ Production & Operations](rabbitmq_production.md)

- Cluster và quorum queue membership.
- Policies/operator policies.
- Monitoring với Prometheus/Grafana.
- Capacity, memory/disk alarm và flow control.
- Upgrade, backup/restore và disaster recovery.
- Federation/Shovel và Spring AMQP production.

Liên quan:

- [RabbitMQ Fundamentals](rabbitmq_fundamentals.md)
- [RabbitMQ Messaging Patterns](rabbitmq_patterns.md)
- [RabbitMQ Glossary](glossary.md)
- [Spring Boot Messaging](../springboot/springboot_messaging.md)
- [Kafka Delivery Semantics](../kafka/fundamentals/consumers.md)

## Tài liệu chính thức

- [RabbitMQ Reliability Guide](https://www.rabbitmq.com/docs/reliability)
- [Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/docs/confirms)
- [Reliable Publishing with Java Publisher Confirms](https://www.rabbitmq.com/tutorials/tutorial-seven-java)
- [Java Client API Guide](https://www.rabbitmq.com/client-libraries/java-api-guide)
- [Queues and Message Ordering](https://www.rabbitmq.com/docs/queues#message-ordering)
- [Quorum Queues](https://www.rabbitmq.com/docs/quorum-queues)
- [Dead Letter Exchanges](https://www.rabbitmq.com/docs/dlx)
- [Consumer Prefetch](https://www.rabbitmq.com/docs/consumer-prefetch)
- [Flow Control](https://www.rabbitmq.com/docs/flow-control)
- [Memory and Disk Alarms](https://www.rabbitmq.com/docs/alarms)
- [RabbitMQ 4.3 Release Highlights](https://www.rabbitmq.com/blog/2026/04/23/rabbitmq-4.3-release)

*Cập nhật lần cuối: 2026-07-29*
