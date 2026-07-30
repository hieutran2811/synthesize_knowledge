# RabbitMQ Production & Operations

> Bài này dùng RabbitMQ 4.3 làm mốc. Mục tiêu không phải tìm một file cấu hình “chuẩn cho mọi hệ thống”, mà là hiểu các failure mode, chọn mức an toàn phù hợp và có runbook trước khi sự cố xảy ra.
>
> Nên đọc trước: [Fundamentals](rabbitmq_fundamentals.md), [Messaging Patterns](rabbitmq_patterns.md) và [Reliability & Guarantees](rabbitmq_reliability.md).

## 1. Mental model khi đưa RabbitMQ lên production

Một cluster chạy được chưa có nghĩa là hệ thống đã sẵn sàng cho production. Cần phân biệt bốn lớp:

| Lớp | Câu hỏi cần trả lời |
|---|---|
| **Node** | Process, disk, memory, network và certificate của từng node có khỏe không? |
| **Cluster** | Các node có nhìn thấy nhau và metadata có quorum không? |
| **Queue/stream** | Resource quan trọng có đủ replica, leader và quorum không? |
| **Ứng dụng** | Publisher có confirm/return? Consumer có ack, idempotency và backpressure? |

Ví dụ: cluster ba node vẫn “xanh” nhưng một quorum queue ba replica đã mất hai thành viên thì queue đó không thể tiếp tục phục vụ. Ngược lại, một node bị mất không nhất thiết gây outage nếu các queue quan trọng vẫn còn đa số replica và client tự kết nối lại.

### 1.1 Cluster không tự động nhân bản mọi message

RabbitMQ 4.3 dùng **Khepri** làm metadata store duy nhất. Khepri nhân bản metadata như vhost, user, queue, exchange, binding và policy giữa các node.

Message được nhân bản hay không phụ thuộc loại queue:

- **Classic queue** trong RabbitMQ 4.x không replicated.
- **Quorum queue** nhân bản log bằng Raft.
- **Stream** là log replicated có retention và khả năng replay.

Vì vậy, thêm node vào cluster không biến classic queue thành HA và cũng không tự tăng một quorum queue từ ba lên năm replica.

### 1.2 Chọn failure domain trước khi chọn cấu hình

Hãy liệt kê những gì hệ thống phải chịu được:

- restart một process;
- mất một VM hoặc Kubernetes node;
- mất một Availability Zone;
- disk đầy hoặc disk có latency cao;
- network chập chờn giữa client và broker;
- deploy nhầm topology/policy;
- hỏng cả region;
- publisher hoặc consumer gửi/xử lý trùng.

Mỗi failure mode cần một biện pháp khác nhau. Quorum queue giúp chịu lỗi node, nhưng không thay thế backup, không sửa được deploy sai và không cung cấp exactly-once end-to-end.

---

## 2. Thiết kế cluster RabbitMQ 4.3

### 2.1 Số node

| Quy mô | Khả năng chịu lỗi | Khi nào dùng |
|---|---:|---|
| 1 node | 0 node | Local, test hoặc workload chấp nhận downtime/mất dữ liệu |
| 3 node | 1 node với nhóm replica 3 | Mốc production phổ biến |
| 5 node | Tùy kích thước nhóm replica | Nhiều connection, nhiều queue hoặc cần nhóm replica 5 |

Ưu tiên số node lẻ: 1, 3, 5. Hai node không đem lại đa số tốt hơn một node; bốn node không đem lại lợi ích quorum tốt hơn ba node nhưng tăng chi phí metadata.

Không mặc định rằng cluster càng lớn càng tốt. Metadata thay đổi đồng bộ và mọi node đều giữ metadata; cluster lên tới hàng chục node thường là dấu hiệu nên tách workload thành nhiều cluster độc lập.

### 2.2 Chỉ cluster trong mạng LAN ổn định

RabbitMQ cluster được thiết kế cho các node có độ trễ thấp, băng thông tốt và kết nối ổn định. Không kéo một cluster qua nhiều region/WAN.

Mô hình phù hợp:

```text
Region A: RabbitMQ cluster A  ── Federation/Shovel ──>  RabbitMQ cluster B: Region B
```

Federation hoặc Shovel dùng connection như client, có retry và phù hợp với liên kết không ổn định hơn. Đây là replication bất đồng bộ ở tầng messaging, không phải một cluster đồng thuận trải dài qua WAN.

### 2.3 Danh tính node phải ổn định

Node name là một phần danh tính của dữ liệu RabbitMQ, ví dụ:

```text
rabbit@rabbit-0.rabbitmq-nodes
```

Production cần:

- hostname/DNS phân giải ổn định;
- node name không đổi sau restart;
- mỗi node có data directory/PVC riêng, không dùng chung;
- Erlang cookie giống nhau giữa các node và được giữ như secret;
- đồng bộ thời gian bằng NTP;
- inter-node ports chỉ mở cho node RabbitMQ và máy quản trị cần thiết.

Không tạo node mới bằng cách copy data directory của node đang chạy. Hai node dùng cùng dữ liệu hoặc cùng danh tính có thể làm hỏng cluster.

### 2.4 Join cluster là thao tác có tính phá hủy với node đích

Từ RabbitMQ 4.1, quy trình join thủ công đã gọn hơn:

```bash
rabbitmqctl join_cluster rabbit@rabbit-1
```

Không còn cần chuỗi `stop_app`, `reset`, `join_cluster`, `start_app` như hướng dẫn cũ. Tuy nhiên, node tham gia không được giữ tập dữ liệu độc lập trước đó; hãy xem join là thao tác destructive đối với dữ liệu hiện có của node đích.

Trong production nên dùng peer discovery hoặc RabbitMQ Cluster Operator thay vì ghép node thủ công. CLI phù hợp hơn cho lab, test và một số tình huống phục hồi có kiểm soát.

### 2.5 Client kết nối tới cluster

Client có thể kết nối vào bất kỳ node nào. RabbitMQ sẽ route thao tác nội bộ đến leader/replica phù hợp, nhưng client vẫn phải biết cách tìm node còn sống:

- danh sách nhiều endpoint trong client;
- DNS có nhiều record;
- hoặc load balancer có health check đúng.

Nguyên tắc:

- dùng connection sống lâu, không mở một connection cho mỗi message;
- bật heartbeat, nhưng tránh timeout quá thấp gây false positive;
- dùng automatic recovery của thư viện client khi phù hợp;
- tách connection publish và consume để resource alarm chặn publisher không làm ack của consumer bị ảnh hưởng;
- theo dõi connection churn và channel churn;
- recovery của connection không thay thế publisher confirm hoặc idempotency.

---

## 3. Quorum queue trong production

### 3.1 Cluster size và replication factor là hai khái niệm khác nhau

Giả sử cluster có năm node nhưng queue `orders.created` có ba thành viên:

```text
Cluster:  rabbit-1  rabbit-2  rabbit-3  rabbit-4  rabbit-5
Queue:       leader  follower  follower      -         -
```

Queue này cần hai trong ba thành viên để có quorum. Hai node còn lại vẫn phục vụ cluster nhưng không giữ message của queue đó.

| Số replica của queue | Quorum | Chịu mất đồng thời |
|---:|---:|---:|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |

Ba replica là lựa chọn phổ biến. Năm replica tăng khả năng chịu lỗi nhưng cũng tăng disk, network và chi phí ghi. Không dùng replication factor chẵn nếu không có lý do đặc biệt.

### 3.2 Khai báo queue type

Queue type được cố định lúc declare, không thể đổi bằng policy:

```java
Queue orders = QueueBuilder.durable("orders.created")
        .quorum()
        .build();
```

Nếu muốn một vhost mặc định tạo quorum queue khi client không truyền `x-queue-type`, cấu hình **default queue type** của vhost. Việc migrate classic queue sang quorum queue cần tạo queue mới rồi chuyển traffic/message có kiểm soát; không thể đổi tại chỗ.

### 3.3 Quản lý membership

Kiểm tra trước khi bảo trì:

```bash
rabbitmq-diagnostics cluster_status
rabbitmq-queues quorum_status --vhost orders orders.created
```

Thêm hoặc bỏ thành viên cho một queue:

```bash
rabbitmq-queues add_member --vhost orders orders.created rabbit@rabbit-4
rabbitmq-queues delete_member --vhost orders orders.created rabbit@rabbit-2
```

Sau khi thêm node, rebalance leader:

```bash
rabbitmq-queues rebalance quorum
```

RabbitMQ 4.3 có **Continuous Membership Reconciliation (CMR)** để tự đưa nhóm replica về target group size trong các trường hợp phù hợp. CMR giảm thao tác tay, nhưng operator vẫn phải xử lý node bị loại vĩnh viễn, theo dõi quá trình sync và kiểm tra dung lượng trước khi thay đổi hàng loạt.

### 3.4 Bảo trì node an toàn

Trước khi dừng một node, cần chắc rằng mỗi quorum queue/stream có replica trên node đó vẫn còn đủ thành viên online. Công cụ nâng cấp có lệnh chờ điều kiện “online quorum cộng thêm một”:

```bash
rabbitmq-upgrade -t 300 await_online_quorum_plus_one
```

Điều này tránh dừng node khi queue chỉ vừa đủ quorum. Nó không thay thế kiểm tra alarm, disk capacity và sync lag.

---

## 4. Policy và operator policy

### 4.1 Khi nào dùng policy

Policy phù hợp với thuộc tính có thể thay đổi lúc runtime:

- message TTL;
- dead-letter exchange/routing key;
- giới hạn length/bytes;
- delivery limit;
- federation;
- một số thiết lập stream và quorum queue.

Không dùng policy để đặt:

- queue type;
- số priority tối đa của classic queue;
- thuộc tính bất biến từ lúc declare.

Ví dụ áp TTL và DLX cho nhóm quorum queue:

```bash
rabbitmqctl set_policy \
  -p orders \
  orders-lifecycle \
  '^orders\.' \
  '{"message-ttl":86400000,"dead-letter-exchange":"orders.dlx"}' \
  --apply-to quorum_queues \
  --priority 10
```

Trong JSON của CLI policy dùng `message-ttl`, không dùng tiền tố `x-`. Client declaration tương ứng mới dùng `x-message-ttl`.

### 4.2 Operator policy là guardrail

Application policy mô tả nhu cầu nghiệp vụ. Operator policy bảo vệ cluster khỏi resource bị dùng không giới hạn, ví dụ giới hạn bytes của queue.

```bash
rabbitmqctl set_operator_policy \
  -p orders \
  queue-guardrails \
  '.*' \
  '{"max-length-bytes":10737418240}' \
  --apply-to queues
```

Khi cùng một key xuất hiện ở nhiều nơi, operator policy có quyền ưu tiên cao nhất trong phạm vi RabbitMQ cho phép. Với nhiều giới hạn số học, RabbitMQ chọn giá trị hạn chế hơn. Vì điều này có thể thay đổi semantics của ứng dụng, hãy version-control policy, review như code và rollout theo từng nhóm queue.

### 4.3 Topology as Code

Có ba cách phổ biến:

1. Application declare resource nó sở hữu.
2. Import definitions khi deploy.
3. Kubernetes Messaging Topology Operator quản lý resource.

Chọn một owner rõ ràng cho mỗi resource. Nếu cả application, script và operator cùng sửa một policy, sự cố drift gần như chắc chắn sẽ xảy ra.

---

## 5. Chạy RabbitMQ trên Kubernetes

### 5.1 Dùng RabbitMQ Cluster Operator

Không nên tự viết StatefulSet và script clustering nếu không có yêu cầu đặc biệt. Cluster Operator quản lý:

- StatefulSet, Service và peer discovery;
- PVC;
- rolling update;
- TLS và plugin;
- trạng thái quorum;
- cấu hình RabbitMQ qua custom resource.

Baseline tối giản:

```yaml
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: production-rabbit
spec:
  replicas: 3
  image: rabbitmq:4.3.4-management
  persistence:
    storageClassName: fast-durable
    storage: 200Gi
  resources:
    requests:
      cpu: "2"
      memory: 4Gi
    limits:
      memory: 6Gi
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: production-rabbit
          topologyKey: kubernetes.io/hostname
  rabbitmq:
    additionalConfig: |
      disk_free_limit.absolute = 8GB
```

Đây là điểm bắt đầu để thảo luận, không phải cấu hình copy-paste cho mọi workload. Trong production:

- pin patch version hoặc image digest đã kiểm thử;
- phân tán Pod qua node và Availability Zone;
- dùng PVC riêng, durable, latency thấp;
- đặt PodDisruptionBudget phù hợp;
- đủ spare capacity để reschedule một Pod và sync replica;
- cấu hình NetworkPolicy cho client, management và inter-node traffic;
- không sửa trực tiếp StatefulSet do Operator sinh ra;
- kiểm tra `status.quorumStatus` trước rolling maintenance.

CPU limit quá chặt có thể tạo latency spike do throttling. Memory limit phải chừa khoảng trống so với RabbitMQ memory watermark và nhu cầu của OS/page cache; nếu đặt hai ngưỡng sát nhau, container có thể bị OOM kill trước khi flow control bảo vệ hệ thống.

### 5.2 Liveness không phải business readiness

Một liveness probe chỉ nên trả lời: “process này có bị kẹt đến mức phải restart không?”. Không dùng alarm toàn cluster làm liveness, vì một disk alarm có thể khiến Kubernetes restart đồng loạt những node vẫn còn hoạt động và làm sự cố nặng hơn.

Gợi ý phân lớp:

| Probe/check | Mục đích |
|---|---|
| `rabbitmq-diagnostics -q ping` | Erlang runtime sống và CLI xác thực được |
| `rabbitmq-diagnostics -q check_running` | RabbitMQ application đang chạy |
| `rabbitmq-diagnostics -q check_port_connectivity` | Listener cục bộ nhận TCP connection |
| `rabbitmq-diagnostics -q check_local_alarms` | Node có memory/disk alarm hay không |
| Synthetic publish/consume | Kiểm tra đường đi nghiệp vụ end-to-end |

Startup probe cần đủ rộng cho lúc node đồng bộ dữ liệu lớn. Readiness có thể chặt hơn liveness, nhưng hãy hiểu hậu quả của việc loại một node khỏi Service khi client vẫn có thể dùng nó.

Không dùng `rabbitmq-diagnostics node_health_check`; health check này đã deprecated và ở phiên bản hiện đại là no-op.

---

## 6. Monitoring, SLI và alert

RabbitMQ khuyến nghị Prometheus và Grafana cho production. Management UI hữu ích để điều tra tương tác, không phải kho metrics dài hạn.

### 6.1 Endpoint Prometheus

Plugin `rabbitmq_prometheus` mặc định mở metrics ở port `15692`:

```bash
rabbitmq-plugins enable rabbitmq_prometheus
```

- `/metrics`: metrics tổng hợp, phù hợp scrape thường xuyên.
- `/metrics/detailed`: chỉ trả các metric family/vhost được yêu cầu.
- `/metrics/memory-breakdown`: phân tích thành phần dùng memory.

Ví dụ lấy đủ thông tin backlog và consumer mà không scrape mọi object:

```text
/metrics/detailed?family=queue_coarse_metrics&family=queue_consumer_count
```

Tránh bật per-object metrics toàn cục khi có hàng chục nghìn queue/connection. Cardinality và thời gian scrape có thể tự trở thành tải đáng kể.

### 6.2 Dashboard nên trả lời được gì?

| Nhóm | Tín hiệu quan trọng | Câu hỏi |
|---|---|---|
| Node | CPU, memory, disk free, disk latency, file descriptors, alarms | Node sắp cạn tài nguyên hay bị throttling? |
| Cluster | node online, inter-node connectivity, metadata health | Có node rời cluster hoặc mất quorum? |
| Queue | ready, unacked, ingress/deliver/ack rate, consumer count | Backlog đang tăng hay đang được drain? |
| Quorum | leader, members online, replica/sync state | Queue có còn chịu thêm một lỗi node không? |
| Publisher | confirm latency, nack, return, blocked time | Publish thật sự thành công và route đúng không? |
| Consumer | processing latency, redelivery, nack/reject, DLQ rate | Consumer chậm, treo hay gặp poison message? |
| Client | connection/channel count và churn | Ứng dụng có leak hoặc reconnect storm? |

### 6.3 Alert theo tác động, không chỉ theo con số

`messages_ready > 10_000` chưa chắc là lỗi: queue batch ban đêm có thể luôn như vậy. Tín hiệu tốt hơn:

- backlog age vượt SLO;
- ingress rate lớn hơn ack rate liên tục;
- ước tính drain time vượt giới hạn;
- consumer count về 0 trên queue bắt buộc có consumer;
- quorum queue chỉ còn đúng số thành viên tối thiểu;
- confirm latency hoặc returned message tăng đột biến;
- memory/disk alarm;
- disk free sẽ chạm watermark trước thời gian phản ứng của đội vận hành;
- DLQ/redelivery rate vượt baseline.

Ước tính đơn giản:

```text
drain_rate = ack_rate - ingress_rate
drain_time = messages_ready / drain_rate
```

Nếu `drain_rate <= 0`, backlog chưa thể giảm bằng công suất hiện tại.

---

## 7. Capacity planning và performance

### 7.1 Đầu vào cần đo

Không sizing chỉ bằng “message/second”. Tối thiểu phải biết:

- p50/p95/p99 message size;
- peak publish và ack rate;
- số queue, connection, channel và consumer;
- prefetch và số delivery unacked;
- tỷ lệ durable/persistent;
- queue type và replication factor;
- confirm strategy/batch size;
- backlog tối đa khi consumer ngừng;
- retention của stream;
- TLS, compression và plugin;
- disk latency/IOPS và network giữa node.

Một queue nóng có giới hạn riêng dù cluster còn nhiều CPU. Scale ngang bằng cách chia workload thành nhiều queue/shard với routing key ổn định, nhưng chỉ làm vậy khi consumer có thể xử lý semantics phân vùng.

### 7.2 Ước tính dung lượng disk

Ước tính thô cho phần backlog:

```text
disk toàn cluster
≈ ingress_bytes_per_second
× thời_gian_consumer_có_thể_dừng
× số_replica
× hệ_số_an_toàn
```

Ví dụ ingress 20 MiB/s, cần giữ 2 giờ, ba replica và headroom 1.5:

```text
20 MiB/s × 7.200 s × 3 × 1,5 ≈ 633 GiB
```

Đây chưa gồm metadata, segment chưa compact, WAL, stream retention, filesystem overhead và nhu cầu đồng bộ replica. Luôn đo trên workload thật và overprovision disk.

### 7.3 Storage và resource watermark

- Ưu tiên local SSD/NVMe có latency ổn định.
- Mỗi node dùng data directory riêng.
- Không chia sẻ filesystem giữa các node.
- Network-attached storage chỉ phù hợp khi đảm bảo semantics filesystem và latency ổn định.
- Đặt `disk_free_limit` production đủ lớn; mặc định dành cho development thường quá thấp.
- Không đẩy memory watermark quá cao; OS và page cache cũng cần RAM.
- Theo dõi disk latency, không chỉ phần trăm disk đã dùng.
- Tránh swap cho RabbitMQ node.

### 7.4 Benchmark giống production

Dùng PerfTest với:

- đúng queue type và replica count;
- payload distribution thật;
- publisher confirm;
- consumer ack và processing delay gần thật;
- TLS nếu production dùng TLS;
- test steady state, backlog build-up, drain và node failure;
- đo p95/p99 latency, confirm latency, disk I/O và recovery time.

Đừng bắt đầu bằng việc chỉnh Erlang scheduler, mailbox hoặc garbage collection flag. Giữ default, đo bottleneck rồi mới thay đổi từng biến có giả thuyết rõ ràng.

---

## 8. Security baseline

### 8.1 Identity và quyền

- Xóa hoặc vô hiệu hóa `guest` cho use case production; không mở remote access cho tài khoản mặc định.
- Mỗi application có user riêng.
- Tách vhost theo tenant hoặc boundary cần cô lập quyền.
- Cấp `configure`, `write`, `read` bằng regex tối thiểu cần thiết.
- Tách tài khoản quản trị khỏi tài khoản ứng dụng.
- Rotate credential và certificate, đồng thời theo dõi ngày hết hạn.
- Bảo vệ definitions export vì có thể chứa password hash và thông tin topology nhạy cảm.

Vhost là namespace và permission boundary, không phải resource isolation cứng. Một tenant tạo quá nhiều queue vẫn có thể ảnh hưởng node chung; cần per-vhost/per-user limits và operator policy.

### 8.2 Network và TLS

- Dùng TLS cho client traffic; cân nhắc mTLS/x.509 khi phù hợp.
- Không public Management UI/HTTP API ra Internet.
- Chỉ node/CLI host được truy cập EPMD và inter-node distribution ports.
- Dùng NetworkPolicy/firewall theo allow-list.
- Có thể bật TLS cho inter-node traffic.
- Lưu Erlang cookie và private key trong secret manager; không commit vào Git.
- Alert certificate sắp hết hạn bằng `check_certificate_expiration` hoặc metrics tương ứng.

TLS tốn CPU, vì vậy benchmark phải bật TLS giống production thay vì đo plaintext rồi suy ra.

---

## 9. Multi-cluster, Federation và Shovel

### 9.1 Chọn công cụ

| Công cụ | Phù hợp khi | Cần nhớ |
|---|---|---|
| **Federation** | Liên kết exchange/queue giữa cluster theo nhu cầu downstream | Tự quản lý link, phù hợp pub/sub và topology phân tán |
| **Shovel** | Chủ động chuyển message từ source queue tới destination | Giống một message pump; dynamic shovel dễ tự động hóa hơn |
| **Ứng dụng relay** | Cần transformation, audit hoặc rule nghiệp vụ phức tạp | Tự chịu trách nhiệm retry, idempotency và observability |

Federation/Shovel:

- dùng nhiều endpoint hoặc load balancer ở mỗi đầu;
- dùng TLS và secret riêng có quyền tối thiểu;
- giữ `ack-mode=on-confirm` khi ưu tiên data safety;
- theo dõi link state, reconnect, lag và destination rejection;
- giả định duplicate vẫn có thể xảy ra quanh failure/recovery;
- ngăn loop khi cấu hình hai chiều.

Chúng không tự biến hai cluster thành bản sao đồng bộ giống nhau. Exchange federation chuyển message theo liên kết và nhu cầu; Shovel chỉ chuyển luồng đã chỉ định. RPO/RTO phải được kiểm thử theo topology thực.

---

## 10. Backup, restore và Disaster Recovery

### 10.1 Definitions không chứa message

Export definitions:

```bash
rabbitmqctl export_definitions /secure-backup/rabbitmq-definitions.json
```

File này chứa topology/metadata như:

- vhost, user và permission;
- queue, exchange và binding;
- policy và runtime parameter.

Nó **không chứa message body**. Import definitions sẽ tái tạo broker có cùng schema, không đưa backlog cũ trở lại.

Nên quản lý definitions dưới dạng IaC, backup định kỳ, mã hóa file và diễn tập import vào môi trường cô lập:

```bash
rabbitmqctl import_definitions /secure-backup/rabbitmq-definitions.json
```

### 10.2 Backup message store khó hơn

Snapshot data directory của node đang chạy có thể không nhất quán. Theo hướng dẫn RabbitMQ:

- dừng node trước khi backup message store;
- với replicated queue, nên dừng cả cluster trong cửa sổ backup nhất quán;
- backup data directory của từng node;
- restore về đúng node name ban đầu;
- dùng version/Erlang và đường nâng cấp tương thích;
- không kỳ vọng đổi node name khi có quorum queue hoặc stream.

Vì giới hạn này, file-system backup thường không phải cơ chế DR duy nhất cho hệ thống có RTO thấp.

### 10.3 Thiết kế DR theo RPO/RTO

| Khái niệm | Câu hỏi |
|---|---|
| **RPO** | Chấp nhận mất tối đa bao nhiêu phút message khi region hỏng? |
| **RTO** | Phải phục vụ lại trong bao lâu? |

Một kế hoạch DR thực tế có thể gồm:

1. Cluster dự phòng ở region khác.
2. Definitions/topology được deploy bằng IaC.
3. Luồng quan trọng được Federation/Shovel hoặc application relay bất đồng bộ.
4. Producer biết chuyển endpoint theo runbook.
5. Consumer idempotent khi message được phát lại.
6. Diễn tập failover và failback định kỳ.

Không gọi cluster dự phòng là “sẵn sàng” trước khi đo được replication lag, RPO thực tế, thời gian đổi traffic và cách xử lý split-brain ở tầng ứng dụng.

---

## 11. Nâng cấp RabbitMQ an toàn

### 11.1 Trước maintenance window

- Đọc release notes của phiên bản nguồn và đích.
- Kiểm tra bảng supported upgrade path; không tự ý bỏ qua minor series.
- Kiểm tra Erlang/OTP compatibility.
- Kiểm tra compatibility của community plugin.
- Backup definitions và lưu cấu hình hiện tại.
- Cluster không có alarm, node offline hoặc queue mất quorum.
- Đủ disk/network capacity cho replica catch-up.
- Enable mọi stable feature flag bắt buộc trên phiên bản hiện tại.
- Với đường nâng cấp lên 4.3 từ release còn Mnesia, hoàn tất chuyển metadata sang Khepri theo đúng tài liệu trước khi chạy 4.3.

Kiểm tra feature flag:

```bash
rabbitmqctl list_feature_flags name state stability
rabbitmqctl enable_feature_flag all
```

Feature flag enable thường không thể đảo ngược. Chỉ chạy sau khi đã đọc release notes và xác nhận mọi node trong cluster hỗ trợ.

### 11.2 Rolling upgrade

Quy trình tổng quát:

1. Chọn một node, chắc chắn các queue trên node đó còn “quorum + 1”.
2. Drain/loại node khỏi client traffic nếu kiến trúc yêu cầu.
3. Dừng node đúng cách.
4. Nâng RabbitMQ/Erlang hoặc đổi image.
5. Khởi động và chờ node join lại.
6. Kiểm tra alarm, log, listener, queue replica và catch-up.
7. Chỉ tiếp tục node kế tiếp khi node hiện tại ổn định.

Sau khi tất cả node đã nâng cấp:

```bash
rabbitmqctl list_feature_flags name state stability
rabbitmqctl enable_feature_flag all
rabbitmq-queues rebalance quorum
```

Sau đó chạy smoke test publish → route → consume → ack, kiểm tra confirm/return và theo dõi ít nhất một chu kỳ tải cao.

Rollback rolling upgrade không đơn giản như đổi image về bản cũ, nhất là sau khi bật feature flag hoặc thay metadata format. Kế hoạch rollback phải dựa trên upgrade guide của đúng cặp phiên bản và đã được diễn tập.

---

## 12. Spring AMQP trong production

### 12.1 Cấu hình nền

```yaml
spring:
  rabbitmq:
    addresses: rabbit-1:5672,rabbit-2:5672,rabbit-3:5672
    requested-heartbeat: 30s
    connection-timeout: 5s
    publisher-confirm-type: correlated
    publisher-returns: true
    template:
      mandatory: true
    listener:
      simple:
        acknowledge-mode: manual
        prefetch: 50
        default-requeue-rejected: false
```

Giá trị timeout, prefetch và concurrency phải đo theo workload; đây chỉ là ví dụ khởi đầu.

Publisher cần xử lý hai tín hiệu độc lập:

- **Return**: message không route được tới queue.
- **Confirm**: broker ack/nack việc nhận trách nhiệm cho publish.

Với Outbox, chỉ đánh dấu event đã gửi sau khi confirm ack và không có return. Gọi `convertAndSend()` thành công chỉ cho biết client đã thực hiện lệnh publish, chưa chứng minh broker đã lưu/route message.

### 12.2 Consumer ack đúng thời điểm

```java
@RabbitListener(queues = "orders.created")
public void handle(OrderCreated event, Message message, Channel channel)
        throws IOException {
    long tag = message.getMessageProperties().getDeliveryTag();

    try {
        orderInboxService.processOnce(event); // transaction DB + inbox
        channel.basicAck(tag, false);
    } catch (InvalidOrderException e) {
        channel.basicNack(tag, false, false); // dead-letter nếu đã cấu hình DLX
    }
}
```

Không dùng multi-ack cho một batch có delivery thất bại xen giữa; ack tới delivery tag cuối có thể vô tình xóa cả message lỗi. Không requeue vô hạn ngay lập tức: lỗi tạm thời cần delayed retry/backoff, lỗi vĩnh viễn cần DLQ.

Khi shutdown:

1. ngừng nhận traffic mới;
2. dừng listener nhận delivery mới;
3. chờ task đang xử lý trong giới hạn;
4. ack/nack những delivery đã có kết quả;
5. đóng channel/connection.

---

## 13. Runbook sự cố

### 13.1 Một node unavailable

1. Xác định process chết, VM chết hay network partition.
2. Kiểm tra `cluster_status` và queue quorum, không chỉ ping node.
3. Dừng automation restart liên tục nếu node không thể rejoin.
4. Kiểm tra disk, node name, cookie, DNS và log.
5. Nếu node mất vĩnh viễn, làm quy trình remove/replace member có kiểm soát.
6. Rebalance leader sau khi cluster ổn định.

### 13.2 Disk alarm

1. Xác định node và filesystem chạm watermark.
2. Dừng/bóp traffic publisher phía upstream; đừng tạo reconnect storm.
3. Giữ consumer hoạt động để drain nếu an toàn.
4. Tìm queue/stream tạo footprint và nguyên nhân consumer lag.
5. Mở rộng disk hoặc giảm retention/traffic bằng thay đổi đã review.
6. Không xóa data directory hoặc queue production chỉ để “hết đỏ”.

### 13.3 Backlog tăng

1. So sánh publish rate và ack rate.
2. Kiểm tra consumer count, processing latency, dependency downstream.
3. Kiểm tra unacked và prefetch.
4. Scale consumer nếu business side effect chịu được concurrency.
5. Nếu queue là bottleneck, đánh giá sharding thay vì chỉ thêm broker node.
6. Ước tính drain time và truyền đạt ETA.

### 13.4 Queue mất quorum

1. Xác định thành viên nào offline.
2. Ưu tiên khôi phục member cũ với data còn nguyên.
3. Không force recovery/xóa member khi chưa hiểu nguy cơ mất dữ liệu.
4. Nếu không thể phục hồi đa số, thực hiện disaster recovery theo runbook đã phê duyệt.
5. Sau sự cố, bổ sung alert “quorum critical”, không chỉ alert queue unavailable.

### 13.5 DLQ hoặc redelivery tăng

1. Dừng replay tự động.
2. Phân loại lỗi schema, poison data, dependency tạm thời hay bug code.
3. Giữ message ID, headers và `x-death` khi điều tra.
4. Fix consumer hoặc dữ liệu.
5. Replay theo batch nhỏ, có rate limit và idempotency.
6. Theo dõi queue chính lẫn DLQ trong suốt replay.

---

## 14. Production readiness checklist

### Kiến trúc

- [ ] Failure domain, SLO, RPO và RTO được viết rõ.
- [ ] Cluster dùng số node lẻ và chỉ trải trong mạng có latency thấp.
- [ ] Queue quan trọng dùng quorum queue/stream với số replica đã tính.
- [ ] Client có nhiều endpoint và automatic recovery phù hợp.
- [ ] Publish/consume dùng connection sống lâu và được tách khi cần.

### Data safety

- [ ] Publisher confirm và mandatory return được xử lý.
- [ ] Consumer ack sau business transaction.
- [ ] Consumer idempotent; Outbox/Inbox dùng cho luồng quan trọng.
- [ ] Retry có backoff, delivery limit và DLQ.
- [ ] Definitions backup và DR failover đã diễn tập.

### Hạ tầng

- [ ] Node name, DNS, NTP và Erlang cookie ổn định.
- [ ] Mỗi node có storage riêng, durable, đủ nhanh và đủ headroom.
- [ ] Node/Pod phân tán qua failure domain.
- [ ] Memory/disk watermark và OS limits đã review.
- [ ] Có capacity để mất một node và sync replica trở lại.

### Observability và vận hành

- [ ] Prometheus/Grafana, log tập trung và application metrics đã bật.
- [ ] Alert cho alarm, quorum, backlog age, confirm/return, consumer và DLQ.
- [ ] Liveness dùng node-local check; synthetic test kiểm tra end-to-end.
- [ ] Có runbook node loss, disk alarm, backlog, quorum loss và poison message.
- [ ] Upgrade path, feature flag, plugin và rollback plan đã diễn tập.

### Security

- [ ] Không dùng `guest` làm tài khoản application production.
- [ ] Mỗi service có user/quyền tối thiểu và secret được rotate.
- [ ] TLS, firewall/NetworkPolicy và certificate alert đã cấu hình.
- [ ] Management/inter-node ports không public.
- [ ] Operator policy và resource limits bảo vệ cluster khỏi tenant lỗi.

---

## 15. Những anti-pattern cần tránh

- Kéo một RabbitMQ cluster qua nhiều region.
- Dùng classic queue rồi nghĩ cluster tự replicate message.
- Dùng RAM node, classic mirrored queue hoặc `cluster_partition_handling` từ hướng dẫn RabbitMQ 3.x.
- Cấu hình queue type bằng policy.
- Chỉ backup definitions rồi cho rằng đã backup message.
- Mở/đóng connection cho từng publish.
- Dùng `node_health_check` cũ làm liveness.
- Restart Pod khi có cluster-wide disk alarm.
- Đánh dấu Outbox `SENT` ngay sau `convertAndSend()`, trước confirm.
- Requeue poison message vô hạn.
- Nâng tất cả node cùng lúc hoặc bỏ qua minor series.
- Tuning Erlang bằng một bộ flag copy từ Internet mà chưa đo bottleneck.

---

## 16. Tài liệu tham khảo chính thức

- [RabbitMQ 4.3 Documentation](https://www.rabbitmq.com/docs)
- [Clustering Guide](https://www.rabbitmq.com/docs/clustering)
- [Quorum Queues](https://www.rabbitmq.com/docs/quorum-queues)
- [Policies](https://www.rabbitmq.com/docs/policies)
- [Production Deployment Guidelines](https://www.rabbitmq.com/docs/production-checklist)
- [Monitoring](https://www.rabbitmq.com/docs/monitoring)
- [Prometheus and Grafana](https://www.rabbitmq.com/docs/prometheus)
- [Backup and Restore](https://www.rabbitmq.com/docs/backup)
- [Rolling Upgrades](https://www.rabbitmq.com/docs/rolling-upgrade)
- [Federation](https://www.rabbitmq.com/docs/federation)
- [Shovel](https://www.rabbitmq.com/docs/shovel)
- [RabbitMQ Cluster Kubernetes Operator](https://www.rabbitmq.com/kubernetes/operator/using-operator)
- [Spring AMQP: RabbitTemplate](https://docs.spring.io/spring-amqp/reference/amqp/template.html)

---

## Tổng kết

Production RabbitMQ không nằm ở một vài tham số “tối ưu”. Một hệ thống vận hành tốt cần đồng thời:

1. cluster đặt đúng failure domain;
2. queue type và replication đúng nhu cầu;
3. publisher/consumer xử lý failure bằng confirm, ack và idempotency;
4. storage/capacity đủ cho backlog và recovery;
5. metrics, alert và runbook có thể hành động;
6. backup, DR và upgrade được diễn tập.

Khi sáu phần này rõ ràng, RabbitMQ mới là một thành phần có thể dự đoán được trong hệ thống, thay vì một “hộp đen” chỉ được chú ý lúc queue đầy.

*Cập nhật lần cuối: 2026-07-29*
