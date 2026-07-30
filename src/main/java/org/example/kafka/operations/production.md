# Kafka Production Operations – Performance, Monitoring & Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)
>
> Phạm vi phiên bản: Apache Kafka 4.3/KRaft. Tên metric sau khi qua JMX exporter và khả năng dynamic update của từng config phải được kiểm tra trên đúng binary đang chạy.

---

## What – Production Operations

**Production operations** *(vận hành hệ thống thực tế)* của Kafka bao gồm: điều chỉnh OS/JVM, cấu hình broker theo mục tiêu throughput *(thông lượng)* và latency *(độ trễ)*, monitoring *(giám sát)* bằng **JMX** *(giao diện metric của JVM)* và **Prometheus** *(hệ thống thu thập metric chuỗi thời gian)*, cảnh báo **consumer lag** *(khoảng cách consumer chưa theo kịp log)*, bảo mật bằng **SASL** *(xác thực)*, **TLS** *(mã hóa đường truyền)*, **ACL** *(phân quyền)* và disaster recovery – DR *(khôi phục sau thảm họa)*.

> 💡 **Giải thích dễ hiểu:**
> Vận hành Kafka giống quản lý một kho hàng 24/7: không chỉ làm băng chuyền chạy nhanh, mà còn phải biết khi nào hàng ùn, ai được mở cửa kho, một máy hỏng thì hàng đi đâu và mất cả trung tâm thì khôi phục thế nào.

```text
Operations pillars:
  Performance:  broker/OS/JVM tuning, producer/consumer config
  Monitoring:   JMX metrics, Prometheus, Grafana dashboards
  Security:     Authentication (SASL), Encryption (TLS), Authorization (ACLs)
  DR:           MirrorMaker2, backup strategies
```

---

## How – OS & JVM Tuning

Các giá trị dưới đây là **điểm bắt đầu để benchmark**, không phải preset dùng chung. Trước khi đổi kernel/JVM, ghi lại baseline về request latency, disk utilization, page cache, GC pause và recovery time; thay từng nhóm cấu hình và chuẩn bị rollback.

```bash
# OS settings (/etc/sysctl.conf)
net.core.wmem_default=131072
net.core.rmem_default=131072
net.core.wmem_max=2097152
net.core.rmem_max=2097152
net.ipv4.tcp_wmem=4096 65536 2048000
net.ipv4.tcp_rmem=4096 65536 2048000
vm.swappiness=1                          # giảm xu hướng swap, không phải tắt swap
# dirty_ratio/dirty_background_ratio ảnh hưởng writeback.
# Không sao chép một tỷ lệ cố định nếu chưa đo RAM, tốc độ disk và latency spike.

# Filesystem: XFS recommended (ext4 also fine)
# Mount options
/dev/sdb1 /data/kafka xfs defaults,noatime,nodiratime 0 2
# noatime: no access time updates (avoid extra writes)

# File descriptors (/etc/security/limits.conf)
kafka soft nofile 128000
kafka hard nofile 128000
kafka soft nproc 65536
kafka hard nproc 65536

# Transparent Huge Pages: chỉ thay đổi khi benchmark chứng minh gây latency spike.
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
```

```properties
# jvm.options (Kafka broker)
-Xms6g
-Xmx6g                                   # ví dụ; heap thực tế phụ thuộc metadata/request load
-XX:+UseG1GC
-XX:MaxGCPauseMillis=20                  # mục tiêu soft, JVM không bảo đảm pause <= 20ms
-XX:InitiatingHeapOccupancyPercent=35
-XX:+ExplicitGCInvokesConcurrent
# -XX:G1HeapRegionSize=16m               # chỉ pin sau khi phân tích GC; mặc định JVM tự chọn
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/var/lib/kafka/dumps/kafka-heap.hprof  # disk riêng, đủ chỗ và giới hạn quyền
-XX:+ExitOnOutOfMemoryError              # restart on OOM

# GC logging
-Xlog:gc*:file=/var/log/kafka/gc.log:time,tags:filecount=10,filesize=100m
```

> 💡 **Giải thích dễ hiểu:**
> Kafka tận dụng RAM còn lại làm page cache cho log. Dồn quá nhiều RAM vào heap giống chất kín đồ trong phòng làm việc, khiến kho đệm ngoài cửa không còn chỗ. Heap, page cache và disk phải được đo như một hệ thống; tuning GC chỉ đặt mục tiêu, không phải lời hứa độ trễ.

---

## How – Broker Configuration (Performance)

Broker config phải xuất phát từ SLO *(service-level objective – mục tiêu độ trễ/khả dụng)* và workload. Các số dưới đây là ví dụ để load test; một cluster có record 1 KB và một cluster có record 8 MB không thể dùng chung cấu hình.

```properties
# server.properties – performance tuning

# --- Network ---
num.network.threads=8              # ví dụ; tune theo CPU + network request queue/idle
num.io.threads=16                  # ví dụ; tune theo disk latency + request handler saturation
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600  # 100MB

# --- Log storage ---
log.dirs=/data/kafka1,/data/kafka2   # chỉ tăng I/O khi nằm trên disk/device phù hợp
num.recovery.threads.per.data.dir=2

# --- Replication ---
default.replication.factor=3
min.insync.replicas=2
unclean.leader.election.enable=false
controlled.shutdown.enable=true
auto.leader.rebalance.enable=true
leader.imbalance.check.interval.seconds=300
leader.imbalance.per.broker.percentage=10

# --- Topic defaults ---
num.partitions=6                   # chỉ là default; partition thật phải theo capacity/parallelism
auto.create.topics.enable=false    # disable auto-creation (explicit control)
delete.topic.enable=true

# --- Retention ---
log.retention.hours=168            # 7 days
log.segment.bytes=1073741824       # 1GB segments
log.retention.check.interval.ms=300000

# --- Throughput optimization ---
# Thường giữ mặc định flush để Kafka dựa vào OS page cache + replication.
# Nếu buộc cấu hình, giá trị phải là số hợp lệ và cần benchmark fsync/latency.
replica.fetch.max.bytes=10485760   # phải đủ cho record batch lớn nhất
message.max.bytes=10485760         # đồng bộ thêm topic max.message.bytes và client limits

# --- Request handling ---
queued.max.requests=500
max.connections.per.ip=1000

# --- Compression ---
compression.type=producer          # keep producer compression (don't recompress)

# --- KRaft controller ---
controller.quorum.election.timeout.ms=1000
controller.quorum.election.backoff.max.ms=1000
controller.quorum.fetch.timeout.ms=2000
```

`replica.fetch.max.bytes` phải đủ lớn để follower sao chép record batch được broker chấp nhận. Producer `max.request.size`, consumer `max.partition.fetch.bytes`/`fetch.max.bytes` và topic `max.message.bytes` cũng cần tương thích. Ba timeout KRaft ở cuối là giá trị minh họa gần mặc định; chỉ đổi sau khi đo controller quorum latency, không dùng để “tăng tốc” tùy ý.

> 💡 **Giải thích dễ hiểu:**
> Cấu hình kích thước giống giới hạn chiều cao ở các cửa kho: xe qua được cửa producer nhưng mắc ở cửa broker hoặc follower thì pipeline vẫn hỏng. `RF=3`, `min.insync.replicas=2` chỉ bảo vệ write khi producer dùng `acks=all`; từng tham số riêng lẻ không tạo durability.

---

## How – Monitoring (JMX + Prometheus)

```yaml
# docker-compose.yml – Prometheus JMX Exporter
kafka:
  image: confluentinc/cp-kafka:<approved-version>  # pin bản đang được tổ chức hỗ trợ
  environment:
    KAFKA_OPTS: "-javaagent:/opt/prometheus/jmx_prometheus_javaagent.jar=9090:/opt/prometheus/kafka.yml"

# kafka.yml (JMX Exporter config)
lowercaseOutputName: true
rules:
  - pattern: 'kafka.server<type=BrokerTopicMetrics, name=MessagesInPerSec, topic=(.+)><>OneMinuteRate'
    name: kafka_server_brokertopicmetrics_messagesin_rate
    labels:
      topic: "$1"
```

Java agent ở ví dụ đọc JMX ngay trong broker rồi mở HTTP metrics; endpoint đó chỉ nên nằm trong mạng quản trị. Nếu dùng remote JMX thay thế, không mở công khai: giới hạn bind/firewall và bật authentication/TLS. Tên metric sau khi export phụ thuộc rule và phiên bản exporter; kiểm tra `/metrics` thực tế trước khi viết alert.

### Critical Broker Metrics

```text
JMX Metrics (kafka.server domain):

CLUSTER HEALTH:
  kafka.controller:type=KafkaController,name=ActiveControllerCount
    → Mỗi controller node có 0 hoặc 1; tổng theo đúng một cluster phải là 1
    → 0 kéo dài: không có active controller; >1 thường cần kiểm tra label/scrape/stale data

  kafka.controller:type=KafkaController,name=OfflinePartitionsCount
    → 0: all good
    → > 0: partitions unavailable (CRITICAL ALERT)

  kafka.controller:type=KafkaController,name=ActiveBrokerCount
  kafka.controller:type=KafkaController,name=FencedBrokerCount
    → So sánh với inventory mong đợi; broker bị fenced không phục vụ leadership/client traffic

  kafka.controller:type=ControllerEventManager,name=EventQueueTimeMs
  kafka.controller:type=ControllerEventManager,name=EventQueueProcessingTimeMs
    → Queue cao: controller chờ xử lý; processing cao: bản thân operation/metadata xử lý chậm

  kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions
    → 0: all replicas in sync
    → > 0: replica lag or failure (WARNING → investigate)

  kafka.server:type=ReplicaManager,name=UnderMinIsrPartitionCount
    → > 0: writes may fail with NotEnoughReplicas (WARNING)

  kafka.log:type=LogManager,name=OfflineLogDirectoryCount
    → > 0: broker có log directory/disk offline (CRITICAL)

THROUGHPUT:
  kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec
  kafka.server:type=BrokerTopicMetrics,name=BytesOutPerSec
  kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec
  kafka.server:type=BrokerTopicMetrics,name=TotalProduceRequestsPerSec
  kafka.server:type=BrokerTopicMetrics,name=TotalFetchRequestsPerSec

LATENCY:
  kafka.network:type=RequestMetrics,name=RequestsPerSec,request=Produce
  kafka.network:type=RequestMetrics,name=TotalTimeMs,request=Produce
  kafka.network:type=RequestMetrics,name=TotalTimeMs,request=FetchConsumer
  kafka.network:type=RequestMetrics,name=RequestQueueTimeMs,request=Produce
  kafka.network:type=RequestMetrics,name=LocalTimeMs,request=Produce
  kafka.network:type=RequestMetrics,name=RemoteTimeMs,request=Produce
  kafka.network:type=RequestMetrics,name=ResponseQueueTimeMs,request=Produce
  kafka.network:type=RequestMetrics,name=ResponseSendTimeMs,request=Produce

RESOURCE:
  kafka.network:type=SocketServer,name=NetworkProcessorAvgIdlePercent
  kafka.server:type=KafkaRequestHandlerPool,name=RequestHandlerAvgIdlePercent
    → thấp kéo dài: network/request handler bão hòa; ngưỡng phải theo baseline/SLO
  java.lang:type=Memory,HeapMemoryUsage (used/max)
  kafka.log:type=LogFlushStats,name=LogFlushRateAndTimeMs
```

`TotalTimeMs` được tách thành thời gian chờ request queue, xử lý local, chờ remote/follower, chờ response queue và gửi response. Với Produce `acks=all`, `RemoteTimeMs` tăng thường gợi ý follower/replication chậm; `RequestQueueTimeMs` tăng cùng idle percent giảm gợi ý thread pool đang bão hòa; `LocalTimeMs` tăng cần đối chiếu disk, conversion và broker CPU. Đây là hướng khoanh vùng, không phải kết luận từ một metric.

Đừng chỉ nhìn một ảnh chụp. Cảnh báo tốt kết hợp **symptom** *(triệu chứng người dùng thấy)* như request p99/timeout với **cause** *(nguyên nhân)* như disk saturation, ISR shrink hoặc network queue. Metric controller phải được lọc theo `cluster_id`; với histogram còn phải giữ đúng label node/quantile để không cộng percentile của nhiều instance thành một con số vô nghĩa.

> 💡 **Giải thích dễ hiểu:**
> Một đồng hồ đỏ chưa chắc là cháy nhà. Consumer lag tăng có thể do traffic vừa tăng, còn lag cao nhưng đang giảm có thể đang hồi phục. Hãy nhìn độ lớn, tốc độ thay đổi và thời gian kéo dài cùng nhau.

### Consumer Lag Monitoring

**Consumer lag** *(độ trễ consumer theo offset)* là chênh lệch giữa log end offset và committed offset. Nó không luôn bằng số record “chưa xử lý”: ứng dụng có thể xử lý xong nhưng chưa commit, hoặc commit sớm trước khi side effect hoàn tất. Với workload không đều, nên quy đổi thêm sang **lag time** *(độ trễ theo thời gian)* và đối chiếu processing latency/error rate.

```bash
# CLI: lag check; thêm --command-config khi cluster bật authentication
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group order-processor-group
# GROUP                 TOPIC  PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG
# order-processor-group orders 0          10000           10050           50
```

Exporter có thể cung cấp các gauge như:

```promql
kafka_consumergroup_lag{consumergroup="order-processor-group", topic="orders", partition="0"}
kafka_consumergroup_lag_sum{consumergroup="order-processor-group", topic="orders"}
```

Alert mẫu phải hiệu chỉnh theo traffic/SLO và đúng tên metric mà exporter thực sự sinh:

```yaml
groups:
  - name: kafka_alerts
    rules:
      - alert: KafkaConsumerGroupLagHigh
        expr: sum by (consumergroup, topic) (kafka_consumergroup_lag) > 10000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Consumer group {{ $labels.consumergroup }} lag is {{ $value }}"

      - alert: KafkaConsumerGroupLagGrowing
        # Lag là gauge: dùng deriv/delta và `for`, không dùng increase() như counter.
        expr: deriv(kafka_consumergroup_lag_sum[10m]) > 8
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Consumer lag is growing continuously"

      - alert: KafkaOfflinePartitions
        # Tên dưới đây giả định exporter chuyển OfflinePartitionsCount sang lowercase.
        expr: kafka_controller_kafkacontroller_offlinepartitionscount > 0
        for: 1m
        labels:
          severity: critical

      - alert: KafkaUnderReplicatedPartitions
        expr: kafka_server_replicamanager_underreplicatedpartitions > 0
        for: 5m
        labels:
          severity: warning
```

> 💡 **Giải thích dễ hiểu:**
> Lag giống số đơn chưa được xác nhận giao xong. Chỉ đếm số đơn có thể gây hiểu lầm khi đơn lớn nhỏ khác nhau; cần biết hàng đang ùn thêm hay đang rút xuống, đơn cũ nhất chờ bao lâu và consumer có lỗi hay không.

### Alert theo SLO và quy trình triage

**SLO** mô tả kết quả người dùng cần, ví dụ “99,9% Produce request hoàn tất dưới 100 ms trong 30 ngày”. **Error budget** *(ngân sách lỗi)* là phần không đạt được phép tiêu thụ; **burn rate** *(tốc độ đốt ngân sách lỗi)* cho biết hệ thống đang tiêu phần đó nhanh đến mức nào. Page nên dựa trên symptom/SLO burn nhanh; cause metric hỗ trợ chẩn đoán hoặc tạo ticket khi kéo dài.

| Tín hiệu | Điều nó thực sự nói | Đối chiếu trước khi hành động |
|----------|---------------------|-------------------------------|
| Produce/Fetch p99 hoặc error rate vượt SLO | Client đang thấy chậm/lỗi | Request-time breakdown, error code, broker/client nào, thay đổi gần nhất |
| `OfflinePartitionsCount > 0` | Có partition không phục vụ được | Active/fenced broker, leader/ISR/ELR, controller health; page ngay |
| `UnderMinIsrPartitionCount > 0` | Một số partition dưới ngưỡng durability | `acks=all` có thể bị từ chối; tìm broker/disk/network lỗi trước khi đổi `minISR` |
| `UnderReplicatedPartitions > 0` | Có follower chưa nằm trong ISR | Tốc độ tăng/giảm, replica lag, reassignment/restart đang diễn ra |
| Disk usage tăng và thời gian đầy ngắn | Broker có nguy cơ hết chỗ | Retention/segment, traffic growth, replica movement, offline log directory |
| Consumer lag age/growth vượt SLO | Dữ liệu nghiệp vụ đến chậm | Consumer error/rate, partition skew, broker fetch latency, downstream |
| Controller queue/processing time tăng | Metadata operation đang chờ hoặc xử lý chậm | Election, reassignment/topic churn, metadata error, controller CPU/disk |

Quy trình triage ngắn:

1. Xác nhận impact theo client/SLO và phạm vi cluster, topic, partition, broker.
2. Đóng băng change/reassignment không thiết yếu; ghi timeline và thay đổi gần nhất.
3. Phân loại bottleneck bằng request-time breakdown, replication, disk/network/CPU và controller metrics.
4. Chọn hành động làm giảm impact có rollback rõ ràng; không “chữa” bằng tắt durability hay nhảy offset nếu chưa duyệt mất dữ liệu.
5. Xác minh symptom đã hồi phục, backlog đang giảm và không tạo lỗi thứ cấp; sau đó lưu bằng chứng/postmortem.

> 💡 **Giải thích dễ hiểu — chuông báo cháy và bảng điện có vai trò khác nhau:**
> Khói trong phòng khách là lý do đánh thức đội trực; dòng điện tăng ở một máy là manh mối tìm nguyên nhân. Nếu mọi đồng hồ nội bộ đều gọi điện lúc nửa đêm, đội sẽ mệt và bỏ lỡ sự cố thật.

---

## How – Security (TLS + SASL)

### TLS Setup

**TLS** *(mã hóa đường truyền và có thể xác thực certificate)* cần certificate có SAN khớp hostname trong `advertised.listeners`, chuỗi CA đầy đủ, cơ chế rotation và secret store. Lệnh dưới đây chỉ minh họa lab; production nên dùng PKI/certificate manager của tổ chức, không để private key hoặc mật khẩu trong Git.

```bash
# Minh họa lab: production dùng PKI/certificate manager và secret store.
# 1. Generate CA
openssl req -new -x509 -keyout ca-key.pem -out ca-cert.pem \
  -days 3650 -subj "/CN=Kafka CA/O=MyOrg"

# 2. Generate broker keystore
keytool -keystore kafka.broker.keystore.jks -alias broker \
  -validity 365 -keyalg RSA -genkeypair \
  -ext SAN=dns:broker1.kafka.example.com \
  -dname "CN=broker1.kafka.example.com,O=MyOrg"

# 3. Sign with CA
keytool -keystore kafka.broker.keystore.jks -alias broker -certreq \
  -file broker-cert-request.pem -ext SAN=dns:broker1.kafka.example.com
openssl x509 -req -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -in broker-cert-request.pem -out broker-signed-cert.pem -days 365 \
  -extfile <(printf 'subjectAltName=DNS:broker1.kafka.example.com')

# 4. Import to keystore
keytool -keystore kafka.broker.keystore.jks -alias CARoot \
  -import -file ca-cert.pem
keytool -keystore kafka.broker.keystore.jks -alias broker \
  -import -file broker-signed-cert.pem

# 5. Create truststore
keytool -keystore kafka.broker.truststore.jks -alias CARoot \
  -import -file ca-cert.pem
```

```properties
# server.properties – TLS configuration
listeners=SSL://0.0.0.0:9093,SASL_SSL://0.0.0.0:9094
advertised.listeners=SSL://broker1.kafka.example.com:9093,SASL_SSL://broker1.kafka.example.com:9094

# SSL/TLS
ssl.keystore.location=/etc/kafka/certs/kafka.broker.keystore.jks
ssl.keystore.password=keystore_password
ssl.key.password=key_password
ssl.truststore.location=/etc/kafka/certs/kafka.broker.truststore.jks
ssl.truststore.password=truststore_password
ssl.client.auth=required              # required | requested | none
ssl.protocol=TLSv1.3
ssl.enabled.protocols=TLSv1.3,TLSv1.2
# ssl.cipher.suites=...               # chỉ pin khi policy/compatibility yêu cầu và đã test JDK
```

> 💡 **Giải thích dễ hiểu:**
> TLS giống phong bì niêm phong kèm giấy tờ người giao. Mã hóa ngăn nghe lén; kiểm tra hostname/CA ngăn giao nhầm cho kẻ giả mạo. Chỉ bật TLS nhưng bỏ qua certificate validation vẫn chưa đủ an toàn.

### SASL Authentication

**SASL** *(khung xác thực client/broker)* hỗ trợ nhiều mechanism. Các đoạn PLAIN, SCRAM, GSSAPI và OAUTHBEARER là **phương án thay thế hoặc cấu hình nhiều mechanism có chủ đích**; không dán nối tiếp các dòng `sasl.enabled.mechanisms`, vì property sau sẽ ghi đè property trước.

Ví dụ ưu tiên SCRAM-SHA-512 trên TLS:

```properties
# server.properties
inter.broker.listener.name=SASL_SSL
sasl.enabled.mechanisms=SCRAM-SHA-512
sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
listener.name.sasl_ssl.scram-sha-512.sasl.jaas.config=\
  org.apache.kafka.common.security.scram.ScramLoginModule required \
  username="admin" password="<broker-secret-from-vault>";
```

Trong KRaft, SCRAM credential được lưu trong metadata log. Credential dùng cho inter-broker phải được bootstrap trước khi broker khởi động (ví dụ qua `kafka-storage.sh --add-scram`). Với user ứng dụng trên cluster đang chạy, tạo/rotate qua broker bảo mật như dưới đây; không dùng lệnh ZooKeeper cũ:

```bash
kafka-configs.sh --bootstrap-server broker1.kafka.example.com:9094 \
  --command-config admin.properties \
  --alter --entity-type users --entity-name app_service \
  --add-config 'SCRAM-SHA-512=[iterations=8192,password=<secret-from-vault>]'
```

| Mechanism | Khi phù hợp | Lưu ý |
|-----------|--------------|-------|
| PLAIN | Hệ thống đơn giản/legacy | Chỉ dùng qua TLS; broker JAAS chứa password nên cần secret management |
| SCRAM-SHA-256/512 | Username/password không cần Kerberos | Dùng TLS, password mạnh, rotation và bảo vệ KRaft controller/metadata log |
| GSSAPI | Tổ chức đã vận hành Kerberos/AD | FQDN, keytab và clock/DNS phải đúng; vận hành phức tạp hơn |
| OAUTHBEARER | Tích hợp IdP/OAuth 2.0 | Production cần callback handler/JWKS/audience/issuer đúng; unsecured token mặc định chỉ phù hợp dev |

> 💡 **Giải thích dễ hiểu:**
> TLS là đường hầm kín, SASL là cách kiểm tra thẻ nhân viên bên trong đường hầm. SCRAM không gửi password thô nhưng vẫn cần TLS; ACL ở bước tiếp theo mới quyết định người đã đăng nhập được phép làm gì.

### ACLs (Authorization)

**ACL – Access Control List** *(danh sách quyền truy cập)* ánh xạ principal đã xác thực với operation trên topic, consumer group, transactional ID hoặc cluster. Production nên deny-by-default, cấp least privilege *(đặc quyền tối thiểu)* và quản lý ACL bằng code/review thay vì thao tác tay.

```bash
# Enable ACLs
# server.properties
authorizer.class.name=org.apache.kafka.metadata.authorizer.StandardAuthorizer
allow.everyone.if.no.acl.found=false      # deny by default
super.users=User:admin;User:kafka_internal

# Create ACLs
# Với cluster bảo mật, mọi lệnh kafka-acls bên dưới cần --command-config admin.properties.
kafka-acls.sh --bootstrap-server localhost:9092 \
  --command-config admin.properties \
  --add \
  --allow-principal User:app_service \
  --operation Read \
  --operation Write \
  --topic orders

# Allow consumer group access
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add \
  --allow-principal User:app_service \
  --operation Read \
  --group order-processor-group

# Allow prefix pattern
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add \
  --allow-principal User:logs_service \
  --operation Write \
  --topic logs- \
  --resource-pattern-type prefixed

# Read-only access to topic
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add \
  --allow-principal User:analytics_user \
  --operation Describe \
  --operation Read \
  --topic orders \
  --group analytics-group

# List ACLs
kafka-acls.sh --bootstrap-server localhost:9092 --list --topic orders

# Remove ACL
kafka-acls.sh --bootstrap-server localhost:9092 \
  --remove --allow-principal User:old_service --operation Read --topic orders
```

Cần test cả luồng startup, produce, consume, transaction và admin vì mỗi luồng dùng resource/operation khác nhau. Prefix ACL tiện quản lý nhưng dễ cấp rộng ngoài ý muốn; luôn kiểm tra `--list` và audit thay đổi.

> 💡 **Giải thích dễ hiểu:**
> Authentication là kiểm tra căn cước ở cổng; ACL là chìa khóa từng phòng. Được vào tòa nhà không đồng nghĩa được đọc topic, ghi topic hoặc dùng consumer group bất kỳ.

---

## How – Thay đổi cấu hình và xoay certificate an toàn

Kafka phân loại broker config theo khả năng cập nhật: `read-only` cần restart; `per-broker` có thể đổi riêng một broker; `cluster-wide` có thể đặt default động và đôi khi override theo broker. Giá trị hiệu lực có thứ tự:

```text
dynamic per-broker
  > dynamic cluster-wide default
    > server.properties
      > Kafka default
```

Vì vậy sửa `server.properties` nhưng thấy broker không đổi thường do dynamic override cũ đang thắng. Trước và sau change phải lưu cả static config, dynamic default và per-broker override.

```bash
# Inventory dynamic config trước khi đổi
kafka-configs.sh --bootstrap-server broker1:9094 \
  --command-config admin.properties \
  --entity-type brokers --entity-default --describe

kafka-configs.sh --bootstrap-server broker1:9094 \
  --command-config admin.properties \
  --entity-type brokers --entity-name 1 --describe

# Canary một config có Update Mode phù hợp trên broker 1
kafka-configs.sh --bootstrap-server broker1:9094 \
  --command-config admin.properties \
  --entity-type brokers --entity-name 1 --alter \
  --add-config 'log.cleaner.threads=2'

# Rollback override để trở về static/cluster default; không đặt bừa một giá trị cũ
kafka-configs.sh --bootstrap-server broker1:9094 \
  --command-config admin.properties \
  --entity-type brokers --entity-name 1 --alter \
  --delete-config 'log.cleaner.threads'
```

Kafka cho phép cập nhật động keystore/truststore theo từng listener bằng prefix `listener.name.<listener-lowercase>.`. Rotation cùng CA có thể thay keystore từng broker mà không restart; nếu đổi CA, phải có giai đoạn hai CA cùng được tin cậy:

1. Phân phối truststore chứa **CA cũ + CA mới**, cập nhật từng broker và client, rồi kiểm tra kết nối mới.
2. Xoay keystore/certificate từng broker; SAN, hostname, chain và `serverAuth`/`clientAuth` usage phải đúng.
3. Xoay client certificate và xác nhận không còn principal dùng CA cũ.
4. Chỉ sau cửa sổ quan sát mới loại CA cũ khỏi truststore; giữ rollback artifact có giới hạn quyền.

Với inter-broker listener, Kafka kiểm tra keystore mới có được truststore hiện tại tin cậy và truststore mới có tin keystore hiện tại hay không. Không tắt hostname verification để “sửa nhanh”; hãy sửa SAN/DNS/advertised listener. Đồng thời alert trước ngày hết hạn certificate, vì traffic đang giữ connection có thể vẫn chạy trong khi mọi connection mới đã bắt đầu thất bại.

> 💡 **Giải thích dễ hiểu — đổi CA giống thay mẫu hộ chiếu:**
> Trước hết cửa khẩu phải nhận cả mẫu cũ lẫn mới, sau đó mọi người đổi hộ chiếu, cuối cùng mới ngừng nhận mẫu cũ. Bỏ mẫu cũ trước khi đội cuối cùng đổi xong sẽ tự khóa một phần cluster.

---

## How – Operational Runbooks

Runbook *(quy trình xử lý vận hành)* phải ghi rõ precondition, người phê duyệt, lệnh quan sát, tiêu chí dừng/rollback và bằng chứng sau thay đổi. Luôn dùng `--command-config` trên cluster bảo mật và thử ở staging/canary trước.

```bash
# 1. Leader rebalance (after broker restart)
kafka-leader-election.sh --bootstrap-server localhost:9092 \
  --election-type preferred --all-topic-partitions

# 2. Increase topic partitions
kafka-topics.sh --bootstrap-server localhost:9092 \
  --alter --topic orders --partitions 24
# WARNING: record cũ không bị đảo; nhưng hash(key) có thể map sang partition mới.
# Ordering theo cùng key xuyên qua thời điểm tăng partition có thể bị phá.
# Nếu ordering lịch sử là bắt buộc, tạo topic mới và migrate có kiểm soát.

# 3. Move partition to specific broker (overloaded broker)
# Generate reassignment plan
cat > topics.json << EOF
{"topics": [{"topic": "orders"}], "version": 1}
EOF
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --topics-to-move-json-file topics.json --broker-list "1,2,3,4" --generate

# Output gồm Current + Proposed và lời mô tả.
# Lưu Current JSON để rollback; copy riêng Proposed JSON vào reassignment_plan.json rồi review.

# Execute with throttle
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment_plan.json \
  --execute --throttle 50000000  # 50MB/s

# Verify
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment_plan.json --verify

# --verify sẽ gỡ throttle khi reassignment hoàn tất.
# Kiểm tra lại broker- và topic-level throttled configs; không xóa entity-default mù quáng.

# 4. Drain broker before maintenance (Kafka 4.3)
# Cordon để broker không nhận thêm log directory assignment mới.
kafka-configs.sh --bootstrap-server localhost:9092 \
  --command-config admin.properties \
  --alter --add-config 'cordoned.log.dirs=*' \
  --entity-type brokers --entity-name 1

# Reassign replicas/leaders khỏi broker, lưu current assignment để rollback.
# Chờ --verify hoàn tất; OfflinePartitions=0, UnderMinISR=0 và replication lag ổn.
# Dừng broker bằng SIGTERM/controlled shutdown; làm từng broker, chờ cluster hồi phục.
# Cordon không tự di chuyển replica hiện có và không thay thế reassignment.
# Sau maintenance và khi broker đã khỏe, xóa cordon:
kafka-configs.sh --bootstrap-server localhost:9092 \
  --command-config admin.properties \
  --alter --delete-config 'cordoned.log.dirs' \
  --entity-type brokers --entity-name 1
```

> 💡 **Giải thích dễ hiểu:**
> Reassignment giống chuyển hàng giữa kho đang mở cửa. Throttle quá thấp khiến xe chuyển hàng không theo kịp hàng mới; quá cao làm khách hàng thường bị nghẽn. `--verify` vừa xác nhận chuyển xong vừa giúp tháo giới hạn đúng lúc.

---

## How – Disaster Recovery (MirrorMaker 2)

**RPO – Recovery Point Objective** *(mức dữ liệu tối đa chấp nhận mất)* và **RTO – Recovery Time Objective** *(thời gian tối đa để phục hồi)* phải được định nghĩa trước. MirrorMaker 2 (MM2) replicate bất đồng bộ, nên RPO không mặc định bằng 0; phải đo replication lag, checkpoint freshness và diễn tập failover.

```properties
# Active-passive: primary (us-east) → dr (us-west warm standby)
clusters = primary, dr

primary.bootstrap.servers = us-east-broker1:9092,us-east-broker2:9092
dr.bootstrap.servers = us-west-broker1:9092,us-west-broker2:9092
# Thêm primary./dr. security.protocol, SASL/SSL config và secret theo môi trường.

primary->dr.enabled = true
primary->dr.topics = orders,payments,user-events
primary->dr.replication.factor = 3

# Offset sync chỉ ghi vào target khi group tương ứng không active ở target.
primary->dr.emit.offset-syncs.enabled = true
primary->dr.emit.checkpoints.enabled = true
primary->dr.sync.group.offsets.enabled = true
primary->dr.sync.group.offsets.interval.seconds = 60

heartbeats.topic.replication.factor = 3
checkpoints.topic.replication.factor = 3
offset-syncs.topic.replication.factor = 3
```

```bash
bin/connect-mirror-maker.sh mm2.properties
```

Quy trình failover active-passive tối thiểu:

1. Fence/stop producer và consumer ở primary để tránh hai site cùng ghi hoặc group active ở target quá sớm.
2. Xác nhận MM2 khỏe; lag/checkpoint/offset-sync đạt RPO đã duyệt. Không giả định lag luôn về 0 khi primary đã hỏng.
3. Kiểm tra remote topic name theo replication policy (mặc định thường có alias như `primary.orders`), schema, ACL và translated group offsets ở DR.
4. Khởi động consumer bằng đúng group ID trên DR, rồi chuyển producer/DNS sau khi smoke test. Theo dõi duplicate/gap và side effect idempotent.
5. Ghi lại cutoff/failover point. Failback là một migration riêng: tránh replication loop và kiểm tra offset translation chiều ngược lại.

Không dùng `--reset-offsets --to-latest` thay cho offset translation: thao tác đó bỏ qua toàn bộ backlog chưa đọc và có thể gây mất xử lý nghiệp vụ. Nếu offset sync tự động không dùng được, phải lấy checkpoint/translation được kiểm chứng và dry-run trước khi execute.

> 💡 **Giải thích dễ hiểu:**
> MM2 giống xe chở hàng sang kho dự phòng; số kệ ở hai kho không nhất thiết trùng nhau nên offset cần “phiên dịch”. Nhảy thẳng đến kệ cuối (`--to-latest`) là tuyên bố mọi kiện đang chờ đã giao, dù thực tế chúng chưa được xử lý.

---

## Trade-offs

| Quyết định | Lợi ích | Chi phí/rủi ro cần đo |
|------------|---------|------------------------|
| TLS | Mã hóa in transit, hỗ trợ mTLS/compliance | CPU, handshake và certificate rotation; overhead phụ thuộc JDK, cipher, connection reuse và phần cứng, không có % cố định |
| PLAIN qua TLS | Đơn giản, tương thích rộng | Password nằm ở broker/client config; cần vault/rotation và TLS bắt buộc |
| SCRAM qua TLS | Không gửi password thô, credential ở KRaft metadata log | Vẫn cần password policy, bảo vệ controller và quy trình rotation |
| GSSAPI/OAuth | Tích hợp identity platform của tổ chức | DNS/clock/keytab hoặc IdP/callback/JWKS phức tạp; không mặc định “an toàn nhất” cho mọi môi trường |
| ACL chi tiết | Least privilege, blast radius nhỏ | Nhiều rule, dễ drift; nên dùng prefix có quy ước và policy-as-code |
| MM2 active-passive | Replication liên tục, RTO thường tốt hơn restore thủ công | RPO khác 0, offset/topic naming/failback phức tạp; failover không hoàn toàn tự động |
| Backup/export | Hữu ích cho archive, audit hoặc rebuild dài hạn | Không thay thế ngay cluster DR/consumer offsets; RTO có thể dài |

> 💡 **Giải thích dễ hiểu:**
> Bảo mật và DR không phải công tắc bật/tắt. Chúng giống mua bảo hiểm kèm diễn tập thoát hiểm: chính sách đẹp trên giấy không có giá trị nếu certificate hết hạn, ACL drift hoặc đội vận hành chưa từng thử failover.

---

## Real-world Production Checklist

```text
Pre-production checklist:
  ✅ SLO/capacity: peak + growth, partition count, disk retention/recovery headroom, quota
  ✅ Failure domains: RF/minISR, rack/AZ placement, unclean election policy đã duyệt
  ✅ OS/JVM: supported JDK, page cache/heap/GC và kernel settings đã benchmark
  ✅ Client durability: producer acks/idempotence/retry; consumer commit/idempotency đã test
  ✅ Network/security: TLS hostname/CA/rotation, SASL mechanism, deny-default ACL
  ✅ Secret handling: không commit password/key; rotation và audit có owner
  ✅ Monitoring: broker/controller/client/MM2 metrics có cluster label và recording rules
  ✅ Alerts: offline partition/log dir, UnderMinISR, request p99/error, disk, lag time
  ✅ Runbook: broker drain, reassignment, disk failure, certificate expiry, rollback
  ✅ DR: RPO/RTO, offset translation, schema/ACL/topic config và failover/failback đã diễn tập
  ✅ Upgrade: compatibility matrix, canary/rolling plan và rollback constraint
  ✅ Testing: load/soak, broker/controller loss, network impairment và dependency outage

Monitoring dashboard must-haves:
  Broker/controller: throughput, request p95/p99/error, queue/idle, active/fenced brokers
  Storage: disk utilization/latency, OfflineLogDirectoryCount, retention growth
  Topics/replication: bytes/messages, UnderReplicated/UnderMinISR, ISR changes
  Consumers: lag offset + lag time + processing/error rate theo group/topic/partition
  JVM/host: heap, GC pause/time, CPU, page cache, network và file descriptors
  DR/MM2: replication lag, checkpoint age, heartbeat và connector/task health
```

> 💡 **Giải thích dễ hiểu:**
> Checklist tốt không chỉ hỏi “đã bật chưa?” mà hỏi “đã đo, đã thử hỏng và đã biết quay lui chưa?”. Một cấu hình RF=3 chưa chứng minh chịu được mất một AZ nếu cả ba replica nằm cùng failure domain.

---

## Nguồn tham khảo chính thức

- [Apache Kafka 4.3 – Monitoring](https://kafka.apache.org/43/operations/monitoring/): broker/client/KRaft metrics và request-time breakdown.
- [Apache Kafka 4.3 – Basic Kafka Operations](https://kafka.apache.org/43/operations/basic-kafka-operations/): graceful shutdown, leadership, rack awareness, cordon và reassignment.
- [Apache Kafka 4.3 – Broker Configs](https://kafka.apache.org/43/configuration/broker-configs/): update mode, precedence, dynamic keystore/truststore và listener config.
- [Apache Kafka 4.3 – SSL/TLS](https://kafka.apache.org/43/security/encryption-and-authentication-using-ssl/) và [SASL](https://kafka.apache.org/43/security/authentication-using-sasl/): certificate, hostname verification và authentication mechanisms.
- [Apache Kafka 4.3 – Authorization & ACLs](https://kafka.apache.org/43/security/authorization-and-acls/): principal, operation, resource pattern và authorizer.
- [Apache Kafka 4.3 – MirrorMaker 2](https://kafka.apache.org/43/operations/geo-replication-cross-cluster-data-mirroring/): replication flow, checkpoints và offset sync.

Khi chạy phiên bản khác, mở tài liệu đúng version vì metric, tên MBean và khả năng dynamic update có thể đổi.

---

## Ghi chú – Chủ đề tiếp theo

> Tiếp theo: [cluster_operations.md](cluster_operations.md) — Kafka Day-2 operations nâng cao: capacity planning, quota, cordon/drain, partition reassignment, rolling upgrade, Cruise Control và chiến lược multi-cluster.

---

*Cập nhật lần cuối: 2026-07-27*
