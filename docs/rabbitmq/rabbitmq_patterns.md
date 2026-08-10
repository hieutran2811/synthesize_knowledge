---
title: "RabbitMQ Messaging Patterns"
topic: rabbitmq
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "RabbitMQ 4"
source_count: 10
---
# RabbitMQ Messaging Patterns

> Thuật ngữ: [Glossary](glossary.md).

> Phạm vi chính: RabbitMQ 4.3, AMQP 0-9-1 và Java client.
>
> Mục tiêu: chọn đúng topology theo yêu cầu giao việc, broadcast, routing, retry, ordering và request/reply; đồng thời hiểu message sẽ đi đâu khi một thành phần gặp lỗi.

## 1. Bản đồ chọn pattern

| Bài toán | Pattern phù hợp | Điểm cần quyết định |
|---|---|---|
| N worker chia nhau công việc | Work Queue / Competing Consumers | Prefetch, idempotency, retry |
| Mỗi service nhận một bản sao event | Publish/Subscribe | Queue tạm hay durable theo từng service |
| Chọn subscriber theo loại event | Topic/Direct Routing | Quy ước routing key và version |
| Chỉ một consumer xử lý nhưng có standby | Single Active Consumer | Ordering, failover, prefetch |
| Lỗi tạm thời cần chờ rồi thử lại | Quorum Delayed Retry | Backoff, delivery limit, DLQ |
| Giao cùng entity vào cùng shard | Modulus/Consistent Hash | Số shard, rebalance, ordering |
| Cần kết quả phản hồi qua broker | Request/Reply (RPC) | Timeout, duplicate, reply durability |
| Bắt message không có route | Alternate Exchange hoặc `mandatory` | Xử lý tại broker hay publisher |

> 💡 **Giải thích dễ hiểu**
>
> Exchange quyết định **message được nhân bản hay phân loại**. Queue quyết định **những consumer nào cạnh tranh cùng một bản message**.
>
> - Hai consumer cùng đọc **một queue**: chia việc, mỗi message thường chỉ tới một consumer.
> - Hai consumer đọc **hai queue khác nhau** cùng bind vào exchange: mỗi queue nhận một bản, tạo pub/sub.

---

## 2. Work Queue – nhiều worker chia việc

### 2.1 Luồng cơ bản

```text
Publisher ──► [orders.process]
                    ├──► Worker A
                    ├──► Worker B
                    └──► Worker C
```

Các worker là **competing consumers**: RabbitMQ giao mỗi delivery cho một consumer. Khi một worker ack, message đó hoàn tất; các worker còn lại không nhận lại cùng delivery.

```java
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.DeliverCallback;

Channel channel = connection.createChannel();

channel.queueDeclare(
    "orders.process",
    true,
    false,
    false,
    Map.of("x-queue-type", "quorum")
);

// RabbitMQ áp giới hạn này riêng cho mỗi consumer mới trên channel.
channel.basicQos(16);

DeliverCallback callback = (consumerTag, delivery) -> {
    long tag = delivery.getEnvelope().getDeliveryTag();
    String body = new String(
        delivery.getBody(),
        java.nio.charset.StandardCharsets.UTF_8
    );

    try {
        orderHandler.processIdempotently(body);
        channel.basicAck(tag, false);
    } catch (NonRetryableException e) {
        channel.basicReject(tag, false);
    } catch (Exception e) {
        channel.basicReject(tag, true);
    }
};

channel.basicConsume(
    "orders.process",
    false,
    callback,
    consumerTag -> System.err.println("Consumer bị hủy: " + consumerTag)
);
```

### 2.2 Prefetch không đồng nghĩa với số thread

Prefetch là số delivery chưa ack tối đa broker có thể đẩy trước cho **mỗi consumer**.

```text
prefetch = 1
Worker A: [đang xử lý 1]
Worker B: [đang xử lý 1]

prefetch = 16
Worker A: [1 đang xử lý + tối đa 15 đang chờ trong client]
Worker B: [1 đang xử lý + tối đa 15 đang chờ trong client]
```

- `1` thường công bằng hơn với task có thời gian chênh lệch lớn, nhưng có thể giảm throughput.
- Giá trị gần mức concurrency thực tế cộng một cửa sổ nhỏ thường là điểm bắt đầu tốt.
- `0` nghĩa là không giới hạn, dễ làm client tích backlog trong memory.
- Prefetch cao làm message rời trạng thái `ready` để sang `unacknowledged`, nên broker khó chuyển chúng cho worker khác.

Không có một con số đúng cho mọi hệ thống. Hãy đo processing latency, message size, network round-trip và mức lệch tải giữa worker.

### 2.3 Khi cần giữ thứ tự: Single Active Consumer

Competing consumers làm tăng throughput nhưng không bảo đảm side effect hoàn tất theo đúng thứ tự. Nếu một queue chỉ được xử lý bởi một consumer tại một thời điểm và vẫn cần standby tự động:

```java
Map<String, Object> arguments = new HashMap<>();
arguments.put("x-queue-type", "quorum");
arguments.put("x-single-active-consumer", true);

channel.queueDeclare(
    "accounting.entries",
    true,
    false,
    false,
    arguments
);
```

Nhiều consumer vẫn đăng ký, nhưng broker chỉ giao cho một consumer active. Khi nó mất kết nối, một consumer chờ sẽ tiếp quản.

SAC giúp giữ thứ tự delivery trên một queue, nhưng không tự bảo đảm thứ tự nghiệp vụ nếu:

- consumer xử lý song song bên trong;
- message bị retry/redelivery;
- publisher gửi sai thứ tự;
- một transaction bên ngoài hoàn tất lệch thứ tự.

Nếu cần vừa scale vừa giữ thứ tự theo `orderId`, hãy hash theo entity vào nhiều queue shard và bật SAC trên từng shard.

---

## 3. Publish/Subscribe – mỗi subscriber một bản sao

### 3.1 Fanout exchange

```text
                             ┌──► [email.user-events] ──► Email Service
Publisher ──► (user.events) ─┼──► [crm.user-events] ───► CRM Service
                             └──► [audit.user-events] ──► Audit Service
```

Fanout exchange bỏ qua routing key và route message tới mọi queue đã bind.

```java
channel.exchangeDeclare(
    "user.events",
    com.rabbitmq.client.BuiltinExchangeType.FANOUT,
    true
);

for (String queue : List.of(
    "email.user-events",
    "crm.user-events",
    "audit.user-events"
)) {
    channel.queueDeclare(
        queue,
        true,
        false,
        false,
        Map.of("x-queue-type", "quorum")
    );
    channel.queueBind(queue, "user.events", "");
}
```

Ba queue tạo ba bản logic độc lập. Email Service ack message của nó không xóa bản trong queue CRM hoặc Audit.

### 3.2 Queue tạm hay queue durable?

| Loại subscription | Topology | Khi subscriber offline |
|---|---|---|
| Chỉ quan tâm event khi đang online | Server-named, exclusive queue | Queue biến mất; event mới không được giữ cho subscriber |
| Service phải xử lý mọi event | Durable queue riêng cho service | Message tiếp tục chờ trong queue |
| N instance cùng một service chia tải | Một durable queue, nhiều consumer | Các instance cạnh tranh message trong queue đó |

Queue tạm:

```java
String temporaryQueue = channel.queueDeclare(
    "",
    false,
    true,
    true,
    null
).getQueue();

channel.queueBind(temporaryQueue, "user.events", "");
```

> Durable exchange không tự giữ lịch sử. Nếu lúc publish không có queue nào được bind, fanout message không có nơi lưu và sẽ bị loại, trừ khi có alternate exchange phù hợp.

---

## 4. Routing – Direct, Topic và Headers

### 4.1 Direct hay Topic?

| Nhu cầu | Binding | Exchange |
|---|---|---|
| Khớp đúng một loại | `invoice.created` | Direct |
| Một service nhận cả nhóm event | `invoice.#` | Topic |
| Khớp đúng một segment | `invoice.*` | Topic |
| Lọc theo metadata không phù hợp routing key | `format=pdf`, `region=apac` | Headers |

```java
channel.exchangeDeclare(
    "commerce.events",
    com.rabbitmq.client.BuiltinExchangeType.TOPIC,
    true
);

channel.queueBind(
    "billing.events",
    "commerce.events",
    "order.payment.#"
);
channel.queueBind(
    "notification.events",
    "commerce.events",
    "*.critical"
);
channel.queueBind(
    "audit.events",
    "commerce.events",
    "#"
);
```

Ví dụ kết quả:

| Routing key | Billing | Notification | Audit |
|---|---:|---:|---:|
| `order.payment.completed` | ✓ |  | ✓ |
| `order.payment.failed` | ✓ |  | ✓ |
| `order.critical` |  | ✓ | ✓ |
| `user.registered` |  |  | ✓ |

### 4.2 Quy ước routing key

Một quy ước dễ mở rộng:

```text
<bounded-context>.<entity>.<event>

commerce.order.created
commerce.order.cancelled
billing.payment.failed
identity.user.registered
```

Khuyến nghị:

- dùng từ ổn định mang ý nghĩa nghiệp vụ, không dùng tên class Java;
- dùng lowercase và dấu chấm;
- đặt schema version trong payload/property thay vì thay routing key cho mọi thay đổi tương thích;
- không đưa PII hoặc secret vào routing key vì nó xuất hiện trong log/metric/topology;
- kiểm thử binding như kiểm thử API contract.

Headers exchange linh hoạt nhưng khó quan sát hơn topic routing. Chỉ dùng khi nhiều chiều lọc không thể biểu diễn rõ bằng một routing key.

---

## 5. Retry, Dead Letter và Poison Message

### 5.1 Phân loại lỗi trước khi retry

| Loại lỗi | Ví dụ | Hành động |
|---|---|---|
| Tạm thời theo message/entity | HTTP 429 cho một tenant, row lock | Trả message với delayed retry |
| Downstream hỏng toàn cục | Database ngừng hoạt động | Pause consumer/circuit breaker; không retry nóng từng message |
| Không thể sửa bằng retry | Schema sai, tài khoản không tồn tại | Reject không requeue → DLQ |
| Bug/poison message | Luôn làm consumer crash | Delivery limit → DLQ và alert |

> Retry không chữa được lỗi vĩnh viễn. Nó chỉ đổi **thời điểm thử lại** và luôn cần giới hạn.

### 5.2 RabbitMQ 4.3: delayed retry native cho quorum queue

RabbitMQ 4.3 có thể giữ message bị trả lại ngay bên trong quorum queue cho đến khi hết delay. Không cần publish sang wait queue rồi quay lại.

```text
                    temporary failure
Consumer ── reject(requeue=true) ──► Quorum Queue
                                         │
                                giữ riêng trong thời gian delay
                                         │
                                         └──► available for redelivery
```

Cấu hình bằng policy:

```bash
rabbitmqctl set_policy \
  --vhost production \
  order-retry \
  '^orders\.process$' \
  '{
    "delayed-retry-type": "all",
    "delayed-retry-min": 5000,
    "delayed-retry-max": 300000,
    "delivery-limit": 5,
    "dead-letter-exchange": "orders.dlx",
    "dead-letter-routing-key": "orders.failed"
  }' \
  --priority 10 \
  --apply-to quorum_queues
```

Backoff tuyến tính:

```text
delay = min(delayed-retry-min × delivery-count, delayed-retry-max)

Lần thất bại 1:   5 giây
Lần thất bại 2:  10 giây
Lần thất bại 3:  15 giây
...
Tối đa:          300 giây
```

Với AMQP 0-9-1 trên RabbitMQ 4.3:

- `basic.reject(requeue=true)` biểu thị delivery thất bại, tăng `x-delivery-count`; phù hợp khi muốn `delivery-limit` chặn poison message.
- `basic.nack(requeue=true)` trả message nhưng không đánh dấu lần xử lý là failed trong mô hình đếm mới; có thể không tiến tới delivery limit.
- `delayed-retry-type=all` áp delay cho cả hai kiểu return, nhưng ứng dụng vẫn phải chọn đúng semantics để giới hạn retry hoạt động như mong muốn.

Consumer:

```java
try {
    handler.processIdempotently(message);
    channel.basicAck(tag, false);
} catch (RetryableException e) {
    // Failed attempt: queue áp delayed retry; delivery limit bảo vệ vòng lặp.
    channel.basicReject(tag, true);
} catch (NonRetryableException e) {
    // Không thử lại: dead-letter ngay nếu DLX đã cấu hình.
    channel.basicReject(tag, false);
}
```

Khi số lần failed vượt `delivery-limit`, quorum queue dead-letter message nếu có DLX; nếu không, message bị loại. Vì vậy queue quan trọng nên có DLQ và alarm.

### 5.3 Khi nào một message trở thành dead letter?

Các nguyên nhân phổ biến:

- consumer `basic.reject` hoặc `basic.nack` với `requeue=false`;
- message hết TTL;
- queue vượt length limit theo cơ chế loại message;
- quorum queue vượt delivery limit.

```text
[orders.process] ── dead-letter ──► (orders.dlx)
                                          │ orders.failed
                                          ▼
                                  [orders.process.dlq]
```

Nên dùng policy thay vì hard-code DLX trong application:

```bash
rabbitmqctl set_policy \
  --vhost production \
  order-dlx \
  '^orders\.process$' \
  '{
    "dead-letter-exchange": "orders.dlx",
    "dead-letter-routing-key": "orders.failed"
  }' \
  --apply-to queues
```

RabbitMQ thêm lịch sử vào header `x-death`. Đây là một **mảng các record được nén theo cặp queue/reason**, không phải một số retry đơn giản do ứng dụng tự tăng.

Các bẫy quan trọng:

- DLX phải tồn tại lúc dead-letter; nếu không, message có thể bị loại âm thầm.
- Mặc định broker republish dead letter mà không bật publisher confirms nội bộ, nên transfer sang target queue không tuyệt đối an toàn.
- Quorum queue hỗ trợ cấu hình at-least-once dead-lettering; chi tiết thuộc bài reliability.
- Dead-letter cycle có thể hình thành nếu routing quay lại queue cũ. RabbitMQ phát hiện một số cycle, nhưng topology vẫn phải được thiết kế rõ ràng.

### 5.4 Retry kiểu cũ bằng TTL + DLX

Trước RabbitMQ 4.3, hoặc với classic queue, thường tạo các retry bucket:

```text
[orders.process]
       │ lỗi tạm thời
       ▼
[orders.retry.5s] ── TTL ──► exchange chính ──► [orders.process]

[orders.retry.30s] ─ TTL ──► exchange chính ──► [orders.process]

[orders.retry.5m] ── TTL ──► exchange chính ──► [orders.process]
```

Mỗi retry queue dùng queue-level TTL cố định và DLX quay về exchange chính. Cách này vẫn hữu ích cho version cũ nhưng có nhiều topology, ghi message nhiều lần và khó bảo đảm atomic giữa “publish bản retry” với “ack bản gốc”.

Nếu consumer tự republish:

1. Publish bản retry với publisher confirm.
2. Chỉ ack bản gốc sau khi nhận confirm.
3. Chấp nhận rằng connection có thể mất sau confirm nhưng trước ack, tạo duplicate.
4. Consumer bắt buộc idempotent.

Không làm như sau:

```text
nack(requeue=false) bản gốc sang DLX
             +
publish thêm một bản vào retry queue
             =
có thể tồn tại hai bản message
```

### 5.5 Retry không phải scheduling

Delayed retry của quorum queue 4.3 dành cho **message đã được giao rồi bị trả lại**, không phải API tổng quát để publisher lên lịch một message mới vào ngày mai.

Community plugin `rabbitmq_delayed_message_exchange` đã bị deprecate và repository bị archive; bản cuối nhắm RabbitMQ 4.2. Không nên chọn nó cho thiết kế RabbitMQ 4.3 mới.

Với lịch nghiệp vụ dài hạn như “gửi email sau 7 ngày”, dùng:

- database/outbox chứa `execute_at` cùng scheduler;
- Quartz/Spring Scheduler với persistent job store;
- dịch vụ scheduling chuyên dụng;
- tính năng thương mại phù hợp nếu tổ chức dùng Tanzu RabbitMQ.

---

## 6. Priority Queue

Priority chỉ có tác dụng với message còn **ready trong queue**. Message đã được prefetch vào client không bị “giành lại” khi message ưu tiên cao xuất hiện.

### 6.1 Classic queue

Classic queue phải khai báo `x-max-priority`; RabbitMQ khuyến nghị số mức nhỏ, thường 2–4:

```java
channel.queueDeclare(
    "tasks.priority.classic",
    true,
    false,
    false,
    Map.of("x-max-priority", 4)
);
```

Mỗi mức tạo thêm chi phí CPU/memory. Giá trị lớn hơn max sẽ bị clamp về max; message không có property priority được xem là `0`.

### 6.2 Quorum queue trong RabbitMQ 4.3

Quorum queue 4.3 luôn bật sẵn 32 mức strict priority từ `0` đến `31`; không cần và không dùng `x-max-priority`.
Giá trị ngoài khoảng này bị clamp; message không đặt priority được xem là mức `4`.

```java
channel.queueDeclare(
    "tasks.priority.quorum",
    true,
    false,
    false,
    Map.of("x-queue-type", "quorum")
);

AMQP.BasicProperties properties = new AMQP.BasicProperties.Builder()
    .deliveryMode(2)
    .priority(20)
    .build();

channel.basicPublish(
    "",
    "tasks.priority.quorum",
    properties,
    payload
);
```

Trước RabbitMQ 4.3, quorum queue chỉ có hai nhóm priority tương đối. Khi vận hành cluster hỗn hợp trong quá trình upgrade, không giả định semantics 32 mức cho đến khi hoàn tất nâng cấp theo hướng dẫn.

### 6.3 Khi nào không nên dùng priority?

Ba queue `tasks.high`, `tasks.normal`, `tasks.low` thường dễ:

- đặt consumer capacity và SLO riêng;
- quan sát backlog theo class;
- tránh low-priority starvation;
- scale độc lập;
- reasoning rõ hơn khi retry.

Priority queue phù hợp khi thực sự cần một queue chung và chấp nhận ordering không còn FIFO tuyệt đối.

---

## 7. Partition theo entity bằng Hash Exchange

### 7.1 Built-in Modulus Hash Exchange

RabbitMQ 4.3 có exchange type built-in `x-modulus-hash`, hash routing key rồi chọn một destination theo `hash mod N`.

```text
routing key = order-123 ─┐
routing key = order-123 ─┼──► [orders.shard.2]
routing key = order-987 ─┘                 khác hash ──► [orders.shard.0]
```

```java
channel.exchangeDeclare(
    "orders.partitioned",
    "x-modulus-hash",
    true
);

for (int i = 0; i < 8; i++) {
    String queue = "orders.shard." + i;
    Map<String, Object> args = new HashMap<>();
    args.put("x-queue-type", "quorum");
    args.put("x-single-active-consumer", true);

    channel.queueDeclare(queue, true, false, false, args);

    // Binding key không tham gia phép hash của modulus exchange.
    channel.queueBind(queue, "orders.partitioned", "shard-" + i);
}

channel.basicPublish(
    "orders.partitioned",
    "order-123",
    properties,
    body
);
```

Khi bindings không đổi, cùng routing key luôn tới cùng queue, kể cả sau restart. Nhưng khi thay số queue `N`, gần như toàn bộ key có thể bị remap.

### 7.2 Consistent Hash Exchange plugin

Plugin `rabbitmq_consistent_hash_exchange` dùng hash ring để giảm số key bị remap khi thêm/bớt destination:

```bash
rabbitmq-plugins enable rabbitmq_consistent_hash_exchange
```

```java
channel.exchangeDeclare(
    "orders.consistent",
    "x-consistent-hash",
    true
);

// Binding key là weight trong consistent-hash exchange.
channel.queueBind("orders.shard.0", "orders.consistent", "1");
channel.queueBind("orders.shard.1", "orders.consistent", "1");
channel.queueBind("orders.shard.2", "orders.consistent", "1");
```

| Tiêu chí | Modulus Hash | Consistent Hash |
|---|---|---|
| Cài đặt | Built-in | Cần plugin |
| Topology tĩnh | Đơn giản, ổn định | Dùng được |
| Thêm/bớt shard | Remap phần lớn key | Remap ít key hơn |
| Weight | Bind trùng queue với dummy keys | Binding key là weight |

Hash chỉ bảo đảm route cùng key vào cùng queue khi topology ổn định. Muốn giữ processing order còn cần SAC hoặc một processing lane tuần tự trên mỗi shard, idempotency và chiến lược retry phù hợp.

---

## 8. Request/Reply (RPC)

### 8.1 Luồng

```text
Requester                                      Responder
    │                                              │
    ├── request ──► [rpc.orders] ─────────────────►│
    │   reply_to=client.reply                      │ xử lý
    │   correlation_id=abc                         │
    │                                              │
    │◄──────────── [client.reply] ◄── response ────┤
    │              correlation_id=abc              │
```

- `reply_to` cho responder biết nơi gửi response.
- `correlation_id` giúp requester ghép response với request đang chờ.
- Một reply queue dùng lại cho nhiều request hiệu quả hơn tạo queue cho từng request.

Java client có lớp tiện ích; cấu hình timeout và `mandatory` ngay từ đầu:

```java
com.rabbitmq.client.RpcClientParams params =
    new com.rabbitmq.client.RpcClientParams()
        .channel(channel)
        .exchange("")
        .routingKey("rpc.orders")
        .timeout(5_000)
        .useMandatory();

try (com.rabbitmq.client.RpcClient rpc =
         new com.rabbitmq.client.RpcClient(params)) {
    String response = rpc.stringCall(requestJson);
}
```

Trong ứng dụng thực tế cần đặt timeout và giới hạn số request đang chờ. Không để thread chờ vô hạn.

### 8.2 Failure semantics thường bị che giấu

```text
Responder xử lý xong
    ├── publish response thành công
    └── chết trước khi ack request

Request được redeliver → xử lý lại → response có thể xuất hiện lần hai
```

Vì vậy:

- operation phía responder nên idempotent;
- requester phải chấp nhận response trùng và bỏ correlation ID không còn chờ;
- timeout chỉ có nghĩa “chưa thấy response đúng hạn”, không chứng minh request chưa chạy;
- retry request sau timeout có thể thực thi nghiệp vụ lần hai;
- nên có request ID nghiệp vụ, deadline và trạng thái lỗi rõ ràng.

RPC qua broker làm lời gọi từ xa trông giống hàm cục bộ nhưng latency và failure hoàn toàn khác. Nếu không thật sự cần phản hồi đồng bộ, pipeline event bất đồng bộ thường dễ vận hành hơn.

### 8.3 Reply queue hay Direct Reply-To?

| Cách nhận response | Đặc điểm | Dùng khi |
|---|---|---|
| Exclusive reply queue dùng lại | Có buffer trong lúc connection còn sống | RPC client thông thường |
| Durable/non-exclusive reply queue | Response có thể chờ khi client tạm mất kết nối | Tác vụ dài, mất reply không chấp nhận được |
| Direct Reply-To | Không tạo queue, zero-buffer, at-most-once | Nhiều client, reply mất có thể retry |

Direct Reply-To dùng pseudo-queue `amq.rabbitmq.reply-to`. Reply bị mất nếu requester disconnect và không được broker lưu. Nó tối ưu resource, không tăng durability.

---

## 9. Alternate Exchange và `mandatory`

Alternate exchange xử lý message mà exchange chính không route được:

```java
channel.exchangeDeclare(
    "commerce.commands",
    com.rabbitmq.client.BuiltinExchangeType.DIRECT,
    true,
    false,
    Map.of("alternate-exchange", "commerce.unrouted")
);

channel.exchangeDeclare(
    "commerce.unrouted",
    com.rabbitmq.client.BuiltinExchangeType.FANOUT,
    true
);

channel.queueDeclare(
    "commerce.unrouted.queue",
    true,
    false,
    false,
    Map.of("x-queue-type", "quorum")
);
channel.queueBind(
    "commerce.unrouted.queue",
    "commerce.unrouted",
    ""
);
```

| Cơ chế | Ai xử lý? | Phù hợp khi |
|---|---|---|
| `mandatory=true` + return callback | Publisher | Publisher cần biết ngay và tự quyết định |
| Alternate exchange | Broker topology | Muốn gom message unroutable để quan sát/xử lý tập trung |

Nếu alternate exchange route được message, publisher không nhận `basic.return`. Nếu alternate exchange cũng không route được, message vẫn có thể bị loại. Publish vào exchange **không tồn tại** là channel error, alternate exchange không cứu được trường hợp này.

---

## 10. Exchange-to-Exchange Binding

Một exchange có thể bind tới exchange khác để tái sử dụng routing:

```text
                         payment.#
(all.events / topic) ───────────────► (payment.events / fanout)
      │                                         ├──► payment-service
      │ #                                       └──► payment-audit
      └──────────────────────────────► audit-all
```

```java
channel.exchangeDeclare(
    "all.events",
    com.rabbitmq.client.BuiltinExchangeType.TOPIC,
    true
);
channel.exchangeDeclare(
    "payment.events",
    com.rabbitmq.client.BuiltinExchangeType.FANOUT,
    true
);

channel.exchangeBind(
    "payment.events", // destination
    "all.events",     // source
    "payment.#"
);
```

Exchange-to-exchange binding giúp tách routing chung và routing theo domain, nhưng topology nhiều tầng khó debug. Cần naming, sơ đồ, owner và kiểm thử route tự động.

---

## 11. Các anti-pattern thường gặp

### Một queue khổng lồ cho mọi loại việc

Task nhanh bị chặn sau task chậm, không scale/SLO riêng được. Tách queue theo workload và priority class có ý nghĩa.

### `requeue=true` ngay lập tức cho mọi exception

Tạo hot loop, tăng CPU/network và làm consumer không xử lý message khác. Phân loại lỗi, delayed retry và delivery limit.

### Một fanout subscriber dùng queue tạm nhưng kỳ vọng nhận event lúc offline

Queue exclusive biến mất cùng connection. Dùng durable queue riêng nếu cần catch up.

### Retry bằng cách nack sang DLX rồi publish thêm bản mới

Có thể tạo hai bản. Chọn một state machine retry rõ ràng và luôn idempotent.

### Dùng priority để chữa thiết kế queue kém

Nhiều queue với capacity riêng thường dễ hiểu và vận hành hơn hàng chục mức priority.

### Dùng RPC cho workflow dài

Requester giữ thread và timeout trong khi server vẫn chạy. Với workflow dài, trả task ID rồi publish completion event hoặc cho client polling trạng thái.

### Tin rằng cùng queue đồng nghĩa xử lý đúng thứ tự

Competing consumer, prefetch, retry và xử lý song song đều có thể làm thứ tự hoàn tất khác thứ tự enqueue.

---

## 12. Checklist thiết kế pattern

- [ ] Xác định rõ một message cần được chia việc hay nhân bản cho nhiều service.
- [ ] Mỗi durable subscriber có queue riêng và owner rõ ràng.
- [ ] Routing key có naming convention, contract test và không chứa dữ liệu nhạy cảm.
- [ ] Prefetch được chọn theo concurrency/latency thực tế, không copy máy móc.
- [ ] Consumer manual ack và idempotent.
- [ ] Lỗi được phân loại retryable/non-retryable/global outage.
- [ ] Retry có backoff, delivery limit, DLQ và metric.
- [ ] Không dùng community delayed-message plugin đã archive cho thiết kế 4.3 mới.
- [ ] Priority/hash/SAC được chọn sau khi xác định yêu cầu ordering thật sự.
- [ ] RPC có timeout, deadline, giới hạn in-flight và xử lý duplicate.
- [ ] Unroutable message được quan sát bằng `mandatory`, alternate exchange hoặc metric.
- [ ] Topology phức tạp có sơ đồ, owner, migration plan và automated routing test.

---

## 13. Chủ đề tiếp theo

Tiếp theo: [RabbitMQ Reliability & Guarantees](rabbitmq_reliability.md)

- Publisher confirms và chiến lược async confirm.
- Consumer acknowledgement, redelivery và idempotency.
- Durable topology, persistent message và quorum replication.
- At-least-once dead-lettering.
- Connection/topology recovery và xử lý duplicate.

Liên quan:

- [RabbitMQ Fundamentals](rabbitmq_fundamentals.md)
- [RabbitMQ Glossary](glossary.md)
- [Production & Operations](rabbitmq_production.md)
- [Spring Boot Messaging](../springboot/springboot_messaging.md)

## Tài liệu chính thức

- [RabbitMQ Tutorials – Work Queues, Pub/Sub, Routing và RPC](https://www.rabbitmq.com/tutorials)
- [Consumer Prefetch](https://www.rabbitmq.com/docs/consumer-prefetch)
- [Consumers và Single Active Consumer](https://www.rabbitmq.com/docs/consumers)
- [Dead Letter Exchanges](https://www.rabbitmq.com/docs/dlx)
- [Quorum Queue Delayed Retry](https://www.rabbitmq.com/docs/quorum-queues#delayed-retry)
- [Priority Support in Queues](https://www.rabbitmq.com/docs/priority)
- [Modulus Hash Exchange](https://www.rabbitmq.com/docs/modulus-hash-exchange)
- [Direct Reply-To](https://www.rabbitmq.com/docs/direct-reply-to)
- [Exchange-to-Exchange Bindings](https://www.rabbitmq.com/docs/e2e)
- [RabbitMQ 4.3 Release Highlights](https://www.rabbitmq.com/blog/2026/04/23/rabbitmq-4.3-release)

*Cập nhật lần cuối: 2026-07-29*
