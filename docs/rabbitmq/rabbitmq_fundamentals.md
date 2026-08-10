---
title: "RabbitMQ Fundamentals"
topic: rabbitmq
level: mixed
review_status: needs_review
content_updated: 2026-07-28
last_verified: null
version_scope: "unspecified"
source_count: 10
---
# RabbitMQ Fundamentals

> Thuật ngữ: [Glossary](glossary.md).

> Phạm vi: RabbitMQ 4.x với AMQP 0-9-1.
>
> Mục tiêu: hiểu đúng đường đi của một message, biết chọn exchange/queue phù hợp và tránh những cấu hình “chạy được nhưng dễ mất dữ liệu”.

## 1. RabbitMQ là gì?

RabbitMQ là một **message broker**: ứng dụng gửi message cho broker, broker định tuyến và giữ message trong queue cho đến khi consumer xử lý.

```text
Publisher
    │ publish(exchange, routing key, message)
    ▼
Exchange ── binding rules ──► Queue ── delivery ──► Consumer
                                  ▲                     │
                                  └──── ack / nack ─────┘
```

> 💡 **Giải thích dễ hiểu**
>
> Hãy hình dung RabbitMQ như trung tâm phân loại bưu kiện:
>
> - **Publisher** là người gửi.
> - **Exchange** là bàn phân loại, không phải kho lưu hàng.
> - **Binding** là quy tắc phân loại.
> - **Queue** là khu vực chờ giao.
> - **Consumer** là người nhận và xử lý.

Điểm quan trọng nhất: publisher thường gửi vào **exchange**, không cần biết consumer nào đang chạy. Nhờ đó hai phía có thể triển khai, scale và gặp sự cố độc lập hơn.

---

## 2. Khi nào nên dùng RabbitMQ?

RabbitMQ phù hợp khi hệ thống cần:

- **Task queue**: nhiều worker chia nhau xử lý email, ảnh, báo cáo.
- **Định tuyến linh hoạt**: chọn queue theo routing key hoặc headers.
- **Request/reply bất đồng bộ**: RPC qua `reply_to` và `correlation_id`.
- **Làm phẳng tải**: producer tăng đột biến nhưng consumer xử lý theo tốc độ ổn định.
- **Tách thời điểm hoạt động**: consumer tạm ngừng, message vẫn chờ trong queue nếu topology và durability được cấu hình đúng.

Không nên mặc định chọn RabbitMQ cho mọi bài toán:

| Nhu cầu chính | Lựa chọn thường phù hợp |
|---|---|
| Giao task, retry, routing phong phú | RabbitMQ queue |
| Event log giữ lâu và đọc lại nhiều lần | Kafka |
| Replay trong RabbitMQ, fan-out lớn, throughput cao | RabbitMQ Stream/Super Stream |
| Gọi đồng bộ cần phản hồi ngay | HTTP/gRPC |
| Chia sẻ trạng thái hoặc cache | Redis/database |

> RabbitMQ queue thiên về **giao việc rồi xóa sau khi xác nhận**. Kafka và RabbitMQ Stream thiên về **lưu log để consumer đọc theo vị trí**. Đây là khác biệt về mô hình, không chỉ là khác biệt tốc độ.

---

## 3. Mô hình AMQP 0-9-1

### 3.1 Message gồm những gì?

Broker xem phần body như mảng byte. Ứng dụng phải tự thống nhất cách mã hóa, schema và version.

```text
Message
├── Body: JSON, Protobuf, Avro, text, binary...
└── Properties
    ├── content_type       application/json
    ├── content_encoding   utf-8
    ├── delivery_mode      1 = transient, 2 = persistent
    ├── message_id         mã duy nhất để deduplicate
    ├── correlation_id     ghép request với response
    ├── reply_to           queue nhận response
    ├── expiration         TTL theo message, đơn vị millisecond
    ├── type               loại sự kiện
    └── headers            metadata do ứng dụng định nghĩa
```

Nên đặt schema có version rõ ràng:

```json
{
  "eventId": "8d946eaa-7db8-4c0b-b893-0a1505134449",
  "eventType": "order.created",
  "schemaVersion": 2,
  "occurredAt": "2026-07-28T08:30:00Z",
  "data": {
    "orderId": "ORD-123",
    "customerId": "CUS-9"
  }
}
```

### 3.2 Connection và Channel

```text
Application process
└── TCP Connection                 tạo tốn kém, nên sống lâu
    ├── Channel 1                  publish
    ├── Channel 2                  consumer A
    └── Channel 3                  consumer B
```

- **Connection** là kết nối TCP thật, có authentication, TLS và heartbeat.
- **Channel** là kết nối logic được multiplex trên một connection.
- Connection và channel đều nên được tái sử dụng lâu dài; không mở mới cho từng message.
- Không để nhiều thread publish đồng thời trên cùng một channel nếu client không bảo đảm tuần tự hóa. Cách đơn giản là mỗi thread/worker có channel riêng hoặc dùng channel pool có giới hạn.
- Delivery tag và consumer acknowledgement có phạm vi **theo channel**. Phải ack trên đúng channel đã nhận message.
- Lỗi protocol như khai báo lại queue với thuộc tính khác có thể đóng channel; ứng dụng phải quan sát shutdown signal và tạo channel thay thế.

Ví dụ khởi tạo Java client:

```java
import com.rabbitmq.client.Connection;
import com.rabbitmq.client.ConnectionFactory;

ConnectionFactory factory = new ConnectionFactory();
factory.setHost("rabbitmq.internal");
factory.setPort(5671);
factory.setVirtualHost("production");
factory.setUsername(System.getenv("RABBITMQ_USER"));
factory.setPassword(System.getenv("RABBITMQ_PASSWORD"));
factory.useSslProtocol();
factory.enableHostnameVerification();
factory.setRequestedHeartbeat(60);
factory.setConnectionTimeout(10_000);
factory.setAutomaticRecoveryEnabled(true);
factory.setTopologyRecoveryEnabled(true);

// Giữ connection này trong suốt vòng đời ứng dụng.
Connection connection = factory.newConnection("order-service");
```

> Automatic recovery giúp khôi phục connection, channel và topology trong nhiều lỗi mạng, nhưng không chứng minh mọi message đã publish thành công. Publisher vẫn cần confirms và chiến lược gửi lại.

---

## 4. Exchange và Binding

Exchange nhận message rồi áp dụng binding để tìm destination. Exchange thường không lưu message.

### 4.1 Chọn exchange type

| Exchange | Cách khớp | Ví dụ |
|---|---|---|
| **Direct** | Routing key bằng chính xác binding key | `payment.failed` |
| **Fanout** | Gửi đến mọi queue đã bind, bỏ qua routing key | Broadcast cấu hình mới |
| **Topic** | Khớp routing key theo `*` và `#` | `order.*`, `order.#` |
| **Headers** | Khớp header theo `x-match=all/any` | `format=pdf`, `region=apac` |
| **Default** | Direct exchange đặc biệt, tên rỗng; routing key bằng tên queue | Gửi thẳng tới queue đã biết |

Quy tắc của topic exchange:

- `*` khớp đúng **một** từ.
- `#` khớp **không, một hoặc nhiều** từ.
- Các từ được ngăn bằng dấu chấm.

```text
Routing key: order.payment.failed

order.*            ✗  chỉ cho phép một từ sau "order"
order.#            ✓
*.payment.failed   ✓
#                  ✓
```

### 4.2 Ví dụ topology bằng Java

```java
import com.rabbitmq.client.BuiltinExchangeType;
import com.rabbitmq.client.Channel;

final String exchange = "commerce.events";
final String queue = "billing.order-events";

try (Channel channel = connection.createChannel()) {
    channel.exchangeDeclare(
        exchange,
        BuiltinExchangeType.TOPIC,
        true
    );

    channel.queueDeclare(
        queue,
        true,   // durable
        false,  // exclusive
        false,  // auto-delete
        java.util.Map.of("x-queue-type", "quorum")
    );

    channel.queueBind(queue, exchange, "order.created");
    channel.queueBind(queue, exchange, "order.payment.#");
}
```

Khai báo topology là thao tác **idempotent khi thuộc tính giống nhau**. Nếu `billing.order-events` đã tồn tại là classic queue mà code khai báo lại thành quorum queue, broker trả `PRECONDITION_FAILED` và đóng channel. Muốn đổi thuộc tính bất biến, phải migrate sang queue mới.

### 4.3 Message không route được

```text
Publisher → exchange tồn tại → không binding nào khớp
                                  │
                                  ├── mandatory=false: bị loại bỏ
                                  ├── mandatory=true: basic.return về publisher
                                  └── alternate exchange: route sang exchange dự phòng
```

`mandatory=true` và return callback trả lời câu hỏi “message có vào ít nhất một queue không?”. **Publisher confirm** trả lời câu hỏi khác: “broker đã nhận trách nhiệm cho lần publish chưa?”. Hệ thống cần độ tin cậy cao thường phải xem xét cả hai.

Publish vào exchange không tồn tại là protocol error và channel sẽ bị đóng.

---

## 5. Queue

### 5.1 Bốn thuộc tính cốt lõi

```java
channel.queueDeclare(
    "orders.process",
    true,   // durable
    false,  // exclusive
    false,  // autoDelete
    arguments
);
```

| Thuộc tính | Ý nghĩa chính | Lưu ý |
|---|---|---|
| `durable` | Định nghĩa queue sống qua lần restart broker | Không tự làm body của message thành persistent |
| `exclusive` | Queue chỉ thuộc connection khai báo nó | Bị xóa khi connection đóng; nên dùng tên do server sinh |
| `autoDelete` | Xóa sau khi queue từng có consumer và consumer cuối cùng rời đi | Queue chưa từng có consumer không bị xóa chỉ vì cờ này |
| `arguments` | Queue type, TTL, giới hạn độ dài, DLX... | Một số giá trị bất biến sau khi declare |

Để message chịu được sự cố broker, thường cần kết hợp:

1. Durable exchange.
2. Durable queue, thường là quorum queue nếu cần replication.
3. Message có `delivery_mode=2`.
4. Publisher confirms để biết broker đã nhận trách nhiệm.

Không có một cờ `durable=true` duy nhất bảo đảm toàn bộ chuỗi.

### 5.2 Queue type hiện đại

| Loại | Đặc điểm | Dùng khi |
|---|---|---|
| **Classic queue** | Một replica, linh hoạt, không có HA nội tại trong RabbitMQ 4.x | Queue tạm hoặc dữ liệu có thể tạo lại |
| **Quorum queue** | Durable, replicated, dùng Raft và cần đa số replica hoạt động | Task/message quan trọng cần data safety và HA |
| **Stream** | Log chỉ-ghi-thêm, giữ message theo retention và cho phép đọc lại | Replay, fan-out lớn, throughput cao |

Các điểm dễ nhầm:

- **Classic mirrored queue đã bị loại bỏ từ RabbitMQ 4.0**. Không dùng policy `ha-mode`; hãy chọn quorum queue hoặc stream.
- **Lazy queue mode không còn được hỗ trợ**. Classic queue hiện tự đẩy phần lớn dữ liệu xuống disk và chỉ giữ working set nhỏ trong memory.
- Một queue replica có hot path chủ yếu trên một CPU core. Đừng dồn toàn hệ thống vào duy nhất một queue khi cần scale throughput.
- Stream có semantics khác queue truyền thống: đọc không phá hủy dữ liệu, retention thay cho TTL từng message và dùng Stream Protocol client sẽ khai thác tốt nhất.

### 5.3 Policy hay `x-arguments`?

Queue type và số mức priority là thuộc tính phải biết lúc declare. Với TTL, DLX và length limit, ưu tiên **policy** vì operator có thể thay đổi mà không redeploy ứng dụng.

```bash
rabbitmqctl set_policy \
  --vhost production \
  queue-limits \
  '^orders\.' \
  '{"message-ttl":600000,"max-length":100000,"overflow":"reject-publish"}' \
  --apply-to queues
```

> 💡 `x-message-ttl` trong code giống việc mỗi ứng dụng tự gắn nội quy lên kho. Policy giống nội quy do đội vận hành quản lý tập trung. Operator policy còn có thể đặt guardrail để ứng dụng không vượt giới hạn tài nguyên.

Ví dụ những argument phải hoặc có thể đặt lúc khai báo:

```java
Map<String, Object> arguments = new HashMap<>();
arguments.put("x-queue-type", "quorum");
arguments.put("x-dead-letter-exchange", "commerce.dlx");
arguments.put("x-delivery-limit", 5);

channel.queueDeclare("orders.process", true, false, false, arguments);
```

Không requeue vô hạn một poison message. Hãy giới hạn số lần giao lại, đưa sang dead-letter queue và lưu đủ metadata để điều tra.

---

## 6. Consumer, acknowledgement và prefetch

### 6.1 Trạng thái message

```text
Ready
  │ broker deliver
  ▼
Unacknowledged
  ├── basic.ack              → hoàn tất, broker có thể xóa
  ├── basic.nack(requeue)    → quay lại queue
  ├── basic.nack(no requeue) → dead-letter hoặc bị loại bỏ
  └── channel/connection mất → tự động requeue
```

`autoAck=true` có nghĩa broker coi message hoàn tất ngay khi gửi cho client. Nếu process chết trước khi business logic xong, message có thể mất. Với công việc quan trọng, dùng manual ack và chỉ ack **sau khi side effect bền vững đã hoàn tất**.

### 6.2 Prefetch là cửa sổ công việc đang xử lý

```java
channel.basicQos(20);
```

Prefetch `20` cho phép consumer có tối đa 20 delivery chưa ack. Chọn giá trị theo:

- thời gian xử lý một message;
- số thread xử lý song song;
- kích thước message và giới hạn memory;
- độ công bằng giữa các consumer.

Prefetch quá thấp làm consumer rảnh trong lúc chờ mạng. Prefetch quá cao khiến một consumer ôm quá nhiều việc, tăng memory và kéo dài thời gian redelivery khi nó chết.

### 6.3 Consumer Java tối giản nhưng an toàn

```java
import com.rabbitmq.client.CancelCallback;
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.DeliverCallback;

Channel consumerChannel = connection.createChannel();
consumerChannel.basicQos(20);

DeliverCallback onDelivery = (consumerTag, delivery) -> {
    long tag = delivery.getEnvelope().getDeliveryTag();
    String message = new String(
        delivery.getBody(),
        java.nio.charset.StandardCharsets.UTF_8
    );

    try {
        processIdempotently(message);
        consumerChannel.basicAck(tag, false);
    } catch (NonRetryableException e) {
        consumerChannel.basicNack(tag, false, false);
    } catch (Exception e) {
        consumerChannel.basicNack(tag, false, true);
    }
};

CancelCallback onCancel = consumerTag ->
    System.err.println("Consumer bị broker hủy: " + consumerTag);

consumerChannel.basicConsume(
    "orders.process",
    false, // manual acknowledgement
    onDelivery,
    onCancel
);
```

Mẫu này vẫn cần bổ sung trong production:

- giới hạn retry/backoff để tránh vòng lặp nóng;
- idempotency theo `message_id` hoặc business key;
- graceful shutdown để ngừng nhận việc mới và hoàn tất việc đang xử lý;
- metric cho ready, unacked, redelivery, processing latency và failure;
- timeout cho xử lý phụ thuộc bên ngoài.

---

## 7. Publisher Java và xác nhận hai lớp

```java
import com.rabbitmq.client.AMQP;
import com.rabbitmq.client.Channel;

try (Channel publisherChannel = connection.createChannel()) {
    publisherChannel.confirmSelect();

    publisherChannel.addReturnListener(returned ->
        System.err.printf(
            "Không route được message: exchange=%s key=%s code=%d%n",
            returned.getExchange(),
            returned.getRoutingKey(),
            returned.getReplyCode()
        )
    );

    byte[] body = eventJson.getBytes(java.nio.charset.StandardCharsets.UTF_8);
    AMQP.BasicProperties properties = new AMQP.BasicProperties.Builder()
        .contentType("application/json")
        .contentEncoding("utf-8")
        .deliveryMode(2)
        .messageId(eventId)
        .type("order.created.v2")
        .timestamp(new java.util.Date())
        .build();

    publisherChannel.basicPublish(
        "commerce.events",
        "order.created",
        true, // mandatory
        properties,
        body
    );

    // Dễ hiểu cho demo; production throughput cao nên dùng confirms bất đồng bộ.
    publisherChannel.waitForConfirmsOrDie(5_000);
}
```

Hai tín hiệu không thay thế nhau:

| Tín hiệu | Chứng minh điều gì? | Không chứng minh điều gì? |
|---|---|---|
| `basic.return` | Message không route được tới queue nào khi `mandatory=true` | Message đã được lưu bền vững |
| Publisher confirm | Broker nhận trách nhiệm cho publish | Consumer đã xử lý nghiệp vụ |
| Consumer ack | Consumer xác nhận delivery đã xử lý | Producer ban đầu đã nhận phản hồi |

Nếu connection mất trước khi confirm tới publisher, publisher không thể biết chắc broker đã giữ message hay chưa. Gửi lại có thể tạo duplicate; vì vậy consumer phải **idempotent**.

---

## 8. Virtual host và quyền truy cập

Virtual host là namespace cô lập cho exchanges, queues, bindings, policies và permissions.

```text
RabbitMQ cluster
├── vhost: production
│   ├── commerce.events
│   └── orders.process
└── vhost: staging
    ├── commerce.events
    └── orders.process
```

Hai resource cùng tên ở hai vhost là hai resource khác nhau. Vhost không phải ranh giới phần cứng: các vhost vẫn chia sẻ node, CPU, memory và disk của cluster.

```bash
rabbitmqctl add_vhost production
rabbitmqctl add_user order-service "$RABBITMQ_ORDER_PASSWORD"

# Ba regex lần lượt là configure, write và read.
rabbitmqctl set_permissions \
  --vhost production \
  order-service \
  '^(orders\..*|commerce\.events)$' \
  '^(commerce\.events|amq\.default)$' \
  '^orders\..*$'
```

Mỗi service nên có user và quyền tối thiểu riêng. Tài khoản mặc định `guest/guest` chỉ được kết nối từ localhost theo mặc định; không dùng nó cho production.

---

## 9. Quan sát và thao tác cơ bản

Management plugin cung cấp UI và HTTP API, thường ở cổng `15672`. AMQP không TLS thường ở `5672`, AMQP qua TLS thường ở `5671`.

```bash
rabbitmq-plugins enable rabbitmq_management

# Node có phản hồi và ứng dụng RabbitMQ đang chạy?
rabbitmq-diagnostics -q ping
rabbitmq-diagnostics check_running

# Listener và resource alarm.
rabbitmq-diagnostics check_port_connectivity
rabbitmq-diagnostics check_local_alarms

# Xem backlog và consumer.
rabbitmqctl list_queues \
  --vhost production \
  name type state messages_ready messages_unacknowledged consumers

rabbitmqctl list_exchanges --vhost production name type durable
rabbitmqctl list_bindings --vhost production
rabbitmqctl list_connections name user vhost channels state
```

Không dùng `rabbitmqctl node_health_check` làm readiness check: lệnh cũ này đã bị deprecate và trở thành no-op trong RabbitMQ 4.x. Health check nên trả lời một câu hỏi cụ thể như node có chạy, listener có mở, có resource alarm hay node có quorum-critical hay không.

Dashboard tối thiểu nên theo dõi:

| Metric/tín hiệu | Câu hỏi vận hành |
|---|---|
| `messages_ready` | Backlog có đang tăng không? |
| `messages_unacknowledged` | Consumer đang chậm, treo hay prefetch quá cao? |
| Publish/deliver/ack rate | Luồng vào và ra có cân bằng không? |
| Redelivery rate | Có retry loop hoặc consumer crash không? |
| Consumer count | Queue quan trọng có mất consumer không? |
| Connection/channel count | Ứng dụng có leak connection/channel không? |
| Memory/disk alarm | Broker có đang block publisher để tự bảo vệ không? |
| Unroutable/returned messages | Topology hoặc routing key có sai không? |

---

## 10. Luồng lỗi: message sẽ đi đâu?

| Sự kiện | Hành vi mặc định | Cách làm an toàn hơn |
|---|---|---|
| Exchange không tồn tại | Channel bị đóng | Khai báo topology trước và theo dõi shutdown signal |
| Không binding nào khớp | Message bị loại nếu `mandatory=false` | `mandatory=true`, return handler hoặc alternate exchange |
| Publisher mất mạng trước confirm | Không biết chắc message đã được nhận | Lưu message chờ confirm, gửi lại và consumer idempotent |
| Consumer chết trước ack | Message tự requeue | Manual ack, idempotency và giới hạn redelivery |
| Consumer `nack(requeue=true)` liên tục | Có thể tạo retry loop nóng | Retry queue có delay, delivery limit và DLQ |
| Queue đầy | Tùy overflow policy | Đặt max length, alarm và chọn reject/dead-letter rõ ràng |
| Một node giữ classic queue bị mất | Queue không khả dụng hoặc mất dữ liệu chưa replicate | Dùng quorum queue cho dữ liệu quan trọng |
| Quorum queue mất đa số replica | Queue không khả dụng | 3 hoặc 5 members, trải failure domain và giám sát quorum |

---

## 11. Những hiểu lầm thường gặp

### “Persistent message nghĩa là không bao giờ mất”

Sai. Persistence chỉ là một mảnh ghép. Cần durable topology, replicated queue khi cần HA, publisher confirms và xử lý duplicate.

### “Ack ngay khi nhận để tăng throughput”

Ack sớm chuyển trách nhiệm khỏi broker trước khi nghiệp vụ hoàn tất. Nếu process chết, công việc mất. Hãy ack sau transaction hoặc side effect bền vững.

### “Có retry là đủ”

Retry không giới hạn có thể biến một message lỗi thành vòng lặp chiếm toàn bộ consumer. Phân loại lỗi retryable/non-retryable, dùng backoff và DLQ.

### “Một connection và một channel dùng chung cho mọi thread”

Một connection dùng chung thường hợp lý. Một channel bị nhiều thread dùng đồng thời dễ gây interleaving frame và lỗi acknowledgement. Quản lý channel theo worker hoặc pool có giới hạn.

### “Queue là database”

Queue là buffer giao việc, không phải nguồn dữ liệu nghiệp vụ chuẩn. Hãy giữ source of truth trong database và dùng Outbox khi cần publish gắn với transaction.

---

## 12. Checklist trước khi sang production

- [ ] Exchange, queue và binding có owner, naming convention và version rõ ràng.
- [ ] Queue type được chọn theo yêu cầu data safety, HA và replay.
- [ ] Publisher dùng confirms; message quan trọng có xử lý unroutable.
- [ ] Consumer dùng manual ack, idempotency và retry có giới hạn.
- [ ] TTL, max length, DLX/DLQ được đặt bằng policy khi phù hợp.
- [ ] Connection/channel được tái sử dụng và có heartbeat/recovery.
- [ ] User/vhost áp dụng least privilege; TLS và secret rotation được cấu hình.
- [ ] Có dashboard backlog, unacked, redelivery, alarm và consumer count.
- [ ] Có runbook cho queue đầy, poison message, node mất và mất quorum.
- [ ] Payload có schema version, message ID và giới hạn kích thước.

---

## 13. Chủ đề tiếp theo

Tiếp theo: [RabbitMQ Messaging Patterns](rabbitmq_patterns.md)

- Work Queue và competing consumers.
- Pub/Sub với fanout exchange.
- Topic routing và headers routing.
- Dead Letter Exchange, retry queue và delayed messaging.
- RPC với `reply_to` và `correlation_id`.

Liên quan:

- [Reliability & Guarantees](rabbitmq_reliability.md)
- [Production & Operations](rabbitmq_production.md)
- [Kafka Architecture](../kafka/fundamentals/architecture.md)
- [Spring Boot Messaging](../springboot/springboot_messaging.md)

## Tài liệu chính thức

- [AMQP 0-9-1 Model Explained](https://www.rabbitmq.com/tutorials/amqp-concepts)
- [Exchanges and Bindings](https://www.rabbitmq.com/docs/exchanges)
- [Queues](https://www.rabbitmq.com/docs/queues)
- [Quorum Queues](https://www.rabbitmq.com/docs/quorum-queues)
- [Publishers and Unroutable Messages](https://www.rabbitmq.com/docs/publishers)
- [Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/docs/confirms)
- [Java Client API Guide](https://www.rabbitmq.com/client-libraries/java-api-guide)
- [Virtual Hosts](https://www.rabbitmq.com/docs/vhosts)
- [Access Control](https://www.rabbitmq.com/docs/access-control)
- [Monitoring](https://www.rabbitmq.com/docs/monitoring)

*Cập nhật lần cuối: 2026-07-28*
