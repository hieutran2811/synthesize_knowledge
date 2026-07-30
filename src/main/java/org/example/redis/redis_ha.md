# Redis High Availability

> Mục tiêu của bài này không phải là “có thêm một Redis dự phòng”, mà là hiểu hệ thống sẽ làm gì khi node, mạng hoặc cả một availability zone gặp sự cố. Nội dung được chuẩn hóa theo Redis Open Source 8.8.

## 1. Bắt đầu từ failure mode

High Availability (HA) chỉ có nghĩa khi ta trả lời được bốn câu hỏi:

1. Thành phần nào có thể hỏng: process, máy, ổ đĩa, mạng hay cả zone?
2. Trong bao lâu dịch vụ phải hoạt động lại, tức **RTO** là bao nhiêu?
3. Có thể mất bao nhiêu write đã xác nhận, tức **RPO** là bao nhiêu?
4. Client sẽ tìm primary mới và xử lý request đang dở như thế nào?

Ba khái niệm thường bị trộn lẫn:

| Khái niệm | Giải quyết câu hỏi | Redis thường dùng |
|---|---|---|
| Replication | Có bản sao đang theo kịp primary không? | Primary và replica |
| Automatic failover | Ai phát hiện lỗi và chọn primary mới? | Sentinel hoặc Redis Cluster |
| Persistence/backup | Có phục hồi được sau khi toàn bộ node mất không? | RDB, AOF và backup độc lập |

Replica không phải backup: lỗi ứng dụng như `FLUSHALL`, ghi nhầm hoặc xóa nhầm cũng được replicate sang replica.

### 1.1 Chọn topology nào?

| Nhu cầu | Topology phù hợp | Đổi lại |
|---|---|---|
| Lab hoặc chấp nhận chuyển đổi thủ công | Standalone + replica | Application/operator tự phát hiện và failover |
| Một primary ghi, không cần sharding | Sentinel | Client phải hiểu Sentinel; write vẫn chỉ vào một primary |
| Dataset hoặc write throughput cần nhiều shard | Redis Cluster | Key design và client phức tạp hơn; multi-key bị giới hạn theo slot |
| Disaster recovery khác region | Replication/backup theo thiết kế DR hoặc dịch vụ managed | Redis OSS Cluster không nên bị kéo giãn tùy tiện qua WAN |

Không nên chọn Cluster chỉ vì “nghe HA hơn”. Nếu một node đủ chứa dataset và đủ throughput, Sentinel thường đơn giản hơn đáng kể.

---

## 2. Replication: bản sao không đồng nghĩa zero data loss

### 2.1 Luồng replication

Redis replication mặc định là bất đồng bộ:

```text
Client --SET--> Primary --replication stream--> Replica
          |
          +-- response có thể về trước khi replica nhận được write
```

Primary và replica theo dõi:

- replication ID: nhận diện lịch sử replication;
- replication offset: vị trí đã xử lý trong stream;
- replication backlog: vùng nhớ giữ một đoạn lịch sử gần nhất.

Khi replica kết nối lần đầu hoặc không thể tiếp tục từ backlog, Redis thực hiện **full synchronization**:

```text
1. Replica gửi PSYNC.
2. Primary tạo/stream RDB snapshot.
3. Replica nạp snapshot.
4. Primary gửi các write phát sinh trong lúc đồng bộ.
5. Hai bên tiếp tục bằng replication stream.
```

Khi mất kết nối ngắn và offset vẫn còn trong backlog, Redis thực hiện **partial synchronization**, chỉ gửi phần còn thiếu. Backlog quá nhỏ so với tốc độ ghi và thời gian gián đoạn sẽ khiến full sync lặp lại, tăng CPU, network và memory pressure.

### 2.2 Cấu hình replica

Ví dụ tối thiểu:

```conf
# redis-replica.conf
replicaof redis-primary.internal 6379
replica-read-only yes

# Dùng ACL user riêng cho replication thay vì default user dùng chung.
masteruser replication-user
masterauth <secret-from-secret-manager>

# Giảm nhu cầu full sync sau gián đoạn ngắn; phải sizing theo write rate.
repl-backlog-size 256mb
repl-backlog-ttl 3600

# Có thể stream snapshot trực tiếp thay vì ghi file trung gian.
repl-diskless-sync yes
repl-diskless-sync-delay 5

# Khi dùng TLS cho replication.
tls-replication yes
```

Trên primary, `replication-user` chỉ nên có quyền tối thiểu phục vụ replication, ví dụ các command `PSYNC`, `REPLCONF` và `PING`. Secret không nên commit vào repository.

`replica-read-only yes` ngăn client ghi nhầm vào replica nhưng không phải cơ chế bảo mật. Vẫn cần ACL, network policy và TLS.

### 2.3 `WAIT` không biến Redis thành strongly consistent

`WAIT numreplicas timeout` chờ các replica xác nhận replication offset của những write trước đó **trên cùng connection**:

```redis
SET order:42:state PAID
WAIT 1 1000
```

Nếu `WAIT` trả `1`, ít nhất một replica đã xác nhận offset trong thời hạn. Nếu trả `0`:

- write có thể đã thành công trên primary;
- command không tự rollback;
- không được retry mù một operation không idempotent.

Ứng dụng phải kiểm tra kết quả và thiết kế trạng thái “chưa biết chắc”. `WAIT` giảm xác suất mất write nhưng không tạo strong consistency; failover vẫn có cửa sổ mất dữ liệu.

Redis 7.2+ có `WAITAOF` để chờ write trước đó trên cùng connection được fsync vào AOF:

```redis
WAITAOF 1 1 1000
```

Hai số đầu lần lượt là số local Redis server và số replica cần xác nhận fsync. Kết quả là `[local_count, replica_count]`. Lệnh này tăng mức bảo đảm durability nhưng cũng không biến failover thành zero-loss.

### 2.4 Chặn write khi replica không đủ khỏe

Primary có thể từ chối write nếu không còn đủ replica phản hồi gần đây:

```conf
min-replicas-to-write 1
min-replicas-max-lag 10
```

Đây là bảo vệ **best effort**, không chứng minh replica đã nhận đúng write vừa rồi. Nó làm nhỏ cửa sổ mất dữ liệu nhưng đánh đổi availability:

```text
Mất replica
    |
    +-- không cấu hình min-replicas --> primary tiếp tục ghi, RPO có thể tăng
    |
    +-- có min-replicas -----------> primary ngừng nhận write, availability giảm
```

Giá trị phù hợp phải xuất phát từ SLO, write rate và khả năng chịu mất dữ liệu, không nên sao chép máy móc.

### 2.5 Có nên đọc từ replica?

Replica read giúp chia tải đọc nhưng có thể trả dữ liệu cũ:

- vừa write primary rồi đọc replica chưa chắc thấy write đó;
- sau reconnect/full sync, độ trễ có thể tăng;
- khi partition, replica có thể tiếp tục phục vụ snapshot cũ;
- hai lần đọc liên tiếp có thể đi tới hai replica có offset khác nhau.

Chỉ route sang replica khi use case chấp nhận stale read, ví dụ dashboard gần real-time. Với read-after-write, kiểm tra quyền sở hữu, số dư hoặc trạng thái workflow, ưu tiên đọc primary hoặc dùng một cơ chế consistency ở tầng ứng dụng.

### 2.6 Quan sát replication

```bash
redis-cli INFO replication
redis-cli INFO persistence
redis-cli INFO stats
```

Các tín hiệu quan trọng:

| Tín hiệu | Điều cần phát hiện |
|---|---|
| `role`, `master_link_status` | Node có đúng vai trò và còn nối với upstream không? |
| `master_repl_offset`, replica offset | Replica đang trễ bao xa theo byte? |
| `master_last_io_seconds_ago` | Upstream im lặng bất thường không? |
| `sync_full`, `sync_partial_ok`, `sync_partial_err` | Full sync có lặp lại không? |
| `repl_backlog_size`, `repl_backlog_histlen` | Backlog có đủ cho gián đoạn thường gặp không? |
| RDB/AOF status và error | Failover xong có còn durability không? |

Tên một số field trong `INFO` vẫn chứa từ `master`/`slave` vì lý do tương thích giao thức.

---

## 3. Sentinel: HA cho một writable primary

Sentinel phù hợp khi không cần sharding nhưng cần:

- monitor primary và replica;
- phát hiện primary không còn khả dụng;
- bầu một Sentinel leader để điều phối failover;
- promote replica thành primary;
- cung cấp địa chỉ primary hiện tại cho client.

Topology production thường dùng:

```text
Zone A                 Zone B                 Zone C
Primary                Replica 1             Replica 2
Sentinel 1             Sentinel 2            Sentinel 3

Application hỏi nhiều Sentinel để tìm primary hiện tại.
```

Ba Sentinel nên nằm trên ba failure domain độc lập. Đặt ba process Sentinel trên cùng một máy chỉ tăng số process, không tăng khả năng chịu lỗi máy.

### 3.1 Quorum khác majority authorization

Đây là điểm dễ hiểu nhầm nhất:

| Điều kiện | Ý nghĩa |
|---|---|
| Một Sentinel đánh dấu SDOWN | Chính Sentinel đó không liên lạc được primary |
| Đủ `quorum` Sentinel đồng ý | Primary bị đánh dấu ODOWN |
| Sentinel leader được majority của toàn bộ Sentinel authorize | Failover mới được tiến hành |

Với ba Sentinel và `quorum 2`, cần hai Sentinel đồng ý primary down; việc authorize failover cũng cần majority, tức hai trên ba. Với năm Sentinel và quorum hai, vẫn cần ít nhất ba Sentinel reachable để authorize failover.

Quorum vì vậy không đơn giản luôn là “một nửa cộng một”; nó là ngưỡng phát hiện ODOWN, còn majority là hàng rào cho hành động failover.

### 3.2 Cấu hình Sentinel

```conf
# sentinel.conf
port 26379

# <logical-name> <primary-host> <primary-port> <quorum>
sentinel monitor orders-cache redis-a.internal 6379 2

sentinel down-after-milliseconds orders-cache 10000
sentinel failover-timeout orders-cache 180000
sentinel parallel-syncs orders-cache 1

# Credential Sentinel dùng để kết nối tới Redis.
sentinel auth-user orders-cache sentinel-user
sentinel auth-pass orders-cache <secret-from-secret-manager>
```

Lưu ý vận hành:

- `sentinel.conf` phải tồn tại và writable vì Sentinel tự rewrite topology/state;
- mọi Sentinel phải dùng cùng logical name và credential phù hợp;
- hostname/DNS phải resolve nhất quán nếu bật hỗ trợ hostname;
- network phải cho Sentinel giao tiếp với nhau, với mọi Redis node và với client;
- ACL user của Sentinel cần quyền monitor, reconfigure replication và failover theo tài liệu chính thức;
- bật TLS cho client, replication và Sentinel nếu traffic đi qua mạng không tin cậy.

`down-after-milliseconds` quá thấp gây failover giả khi có pause hoặc network jitter; quá cao kéo dài RTO. Không có một con số đúng cho mọi hệ thống.

### 3.3 Failover thực sự diễn ra thế nào?

```text
1. Sentinel riêng lẻ không ping được primary -> SDOWN.
2. Đủ quorum cùng xác nhận                -> ODOWN.
3. Các Sentinel bầu leader và authorize bằng majority.
4. Leader chọn replica phù hợp.
5. Replica được promote.
6. Các replica khác theo primary mới.
7. Sentinel công bố topology mới.
8. Client khám phá lại và kết nối primary mới.
9. Primary cũ trở lại sẽ được cấu hình thành replica.
```

Việc chọn replica xem xét trạng thái kết nối, `replica-priority`, replication offset và tiêu chí tie-break. Không nên ghi một timeline cố định kiểu “failover luôn xong sau 33 giây”; thời gian phụ thuộc timeout, election, network, backlog, tốc độ sync và khả năng của client.

Vì replication bất đồng bộ, write đã trả thành công ngay trước sự cố vẫn có thể chưa tới replica được promote. Sentinel tự động hóa đổi vai trò, không bảo đảm không mất write.

### 3.4 Client phải Sentinel-aware

Client đúng không hard-code địa chỉ primary. Nó cần:

1. biết nhiều Sentinel endpoint;
2. hỏi logical name để lấy primary hiện tại;
3. kiểm tra node trả về thực sự là primary;
4. đóng/reconnect pool khi topology đổi;
5. retry có backoff và giới hạn;
6. xử lý kết quả write không xác định khi connection đứt giữa request/response.

Ví dụ kiểm tra discovery:

```bash
redis-cli -p 26379 SENTINEL GET-MASTER-ADDR-BY-NAME orders-cache
redis-cli -p 26379 SENTINEL MASTER orders-cache
redis-cli -p 26379 SENTINEL REPLICAS orders-cache
redis-cli -p 26379 SENTINEL SENTINELS orders-cache
redis-cli -p 26379 SENTINEL CKQUORUM orders-cache
```

Trong Spring Data Redis/Lettuce, cấu hình cần chứa logical master name và nhiều Sentinel endpoint. Chỉ bật `REPLICA_PREFERRED` cho luồng đọc chấp nhận stale data; đây là quyết định consistency, không phải tối ưu mặc định.

### 3.5 Planned failover

Khi bảo trì có Sentinel:

```bash
redis-cli -p 26379 SENTINEL FAILOVER orders-cache
```

Với replication không dùng Sentinel, `FAILOVER` phối hợp primary và replica, tạm dừng write rồi đợi replica bắt kịp trước khi đổi vai trò:

```bash
redis-cli FAILOVER TO redis-b.internal 6379 TIMEOUT 30000
```

Planned failover vẫn phải được test trên staging và quan sát client reconnect. Không dùng `FORCE`, `TAKEOVER` hoặc đổi `REPLICAOF NO ONE` tùy tiện khi chưa hiểu nguy cơ split brain.

### 3.6 Container, NAT và port mapping

Sentinel tự khám phá và công bố địa chỉ node. NAT hoặc map port không theo tỉ lệ 1:1 có thể khiến nó công bố địa chỉ mà client/peer không truy cập được.

Docker Compose gồm ba container trên một host chỉ phù hợp cho lab:

- host chết thì cả topology chết;
- port/hostname bên trong có thể khác thứ client bên ngoài nhìn thấy;
- volume Sentinel phải writable;
- cần cấu hình announce khi có NAT.

Production nên ưu tiên địa chỉ routable ổn định và tách node theo failure domain.

---

## 4. Redis Cluster: sharding kèm failover theo shard

Redis Cluster chia keyspace thành **16.384 hash slot**:

```text
slot = CRC16(key) mod 16384

Shard A: slots 0.....5460      Primary A -> Replica A1
Shard B: slots 5461..10922     Primary B -> Replica B1
Shard C: slots 10923.16383     Primary C -> Replica C1
```

Mỗi primary sở hữu một tập slot; replica của nó có thể được promote khi primary lỗi. Cụm thường bắt đầu với ba primary và ít nhất một replica cho mỗi primary, phân bố trên các host/zone khác nhau. Sáu node là baseline triển khai HA phổ biến, không phải một quy luật rằng mọi cluster luôn buộc đúng sáu node.

Redis Cluster chỉ hỗ trợ logical database 0.

### 4.1 Key, slot và hash tag

Hai key thông thường có thể nằm ở hai slot khác nhau:

```text
order:42         -> slot 9576
order:42:items   -> slot 1331
```

Hash tag ép phần nằm trong `{...}` tham gia tính slot:

```text
order:{42}         \
order:{42}:items    +--> cùng slot của "42"
order:{42}:payment /
```

Hash tag hữu ích cho transaction, script và multi-key command, nhưng gom quá nhiều key vào cùng tag sẽ tạo hot shard và phá mục tiêu phân tải.

Quy tắc thiết kế an toàn:

- operation cần atomic/multi-key thì các key phải cùng slot;
- pipeline không làm các command trở thành atomic;
- Lua/Function cũng không “vượt qua” ranh giới shard một cách tự do;
- aggregate trên nhiều shard nên được phối hợp ở application hoặc hệ thống phân tích khác.

### 4.2 Client cluster-aware và redirect

Client Cluster không gửi mọi request qua một proxy trung tâm. Nó lấy slot map, cache mapping rồi kết nối trực tiếp node sở hữu slot.

Hai redirect cần phân biệt:

| Response | Ý nghĩa | Client nên làm |
|---|---|---|
| `MOVED` | Slot đã thuộc node khác | Cập nhật slot map; có thể tải lại bằng `CLUSTER SHARDS` |
| `ASK` | Slot đang migrate, command này tạm chạy ở node đích | Gửi `ASKING`, chạy đúng một command; chưa thay ownership vĩnh viễn |

`CLUSTER SLOTS` đã deprecated; client mới nên dùng `CLUSTER SHARDS` khi có thể.

Client production cần:

- nhiều startup node, không chỉ một địa chỉ;
- giới hạn số redirect/retry;
- refresh topology khi gặp `MOVED`, reconnect hoặc node đổi vai trò;
- TLS và ACL tương thích trên mọi node;
- xử lý request có kết quả không xác định khi connection đứt.

### 4.3 Cluster availability và write safety

Cluster dùng gossip/failure reports trên cluster bus:

```text
Node không liên lạc được -> PFAIL
Đủ primary đồng ý       -> FAIL
Replica phù hợp         -> được bầu và promote
```

Cluster ưu tiên availability và hiệu năng, replication vẫn bất đồng bộ. Vì vậy acknowledged write có thể mất trong một cửa sổ failover.

Trong network partition:

- phía có majority primary và replica thay thế cho shard hỏng có thể tiếp tục;
- primary ở phía minority dừng nhận write sau `cluster-node-timeout`;
- nếu một shard mất cả primary lẫn replica có thể promote, toàn cluster có thể unavailable dù các shard khác còn sống;
- replica read có thể stale và chỉ nên bật khi nghiệp vụ chấp nhận.

Đây không phải consensus database cung cấp linearizable write. Nếu nghiệp vụ đòi zero data loss hoặc cross-shard transaction mạnh, cần đánh giá datastore khác hoặc thiết kế bổ sung.

### 4.4 Cấu hình node

Mỗi node cần file state riêng và writable:

```conf
port 7001
cluster-enabled yes
cluster-config-file nodes-7001.conf
cluster-node-timeout 15000

# Chỉ cần khi địa chỉ Redis tự phát hiện không phải địa chỉ routable.
cluster-announce-ip 10.10.1.11
cluster-announce-port 7001
cluster-announce-bus-port 17001

appendonly yes
appendfsync everysec
```

Cluster bus mặc định dùng data port + 10000, hoặc port được công bố rõ. Mọi node phải liên lạc được trên data port lẫn cluster bus. Khi bật TLS, cấu hình cả client traffic, replication và cluster bus theo tài liệu encryption.

Không copy cùng một `nodes.conf` sang nhiều node. Redis tự quản lý file này.

Tạo cluster lab:

```bash
redis-cli --cluster create \
  redis-a:7001 redis-b:7001 redis-c:7001 \
  redis-d:7001 redis-e:7001 redis-f:7001 \
  --cluster-replicas 1
```

Sau khi tạo:

```bash
redis-cli -h redis-a -p 7001 CLUSTER INFO
redis-cli -h redis-a -p 7001 CLUSTER SHARDS
redis-cli --cluster check redis-a:7001
```

Phải xác nhận đủ 16.384 slot ở trạng thái ổn định và replica nằm khác failure domain với primary của nó.

### 4.5 Scale và reshard

Thêm primary rỗng rồi phân lại slot:

```bash
redis-cli --cluster add-node redis-g:7001 redis-a:7001
redis-cli --cluster reshard redis-a:7001
redis-cli --cluster rebalance redis-a:7001 --cluster-use-empty-masters
```

Thêm replica:

```bash
redis-cli --cluster add-node redis-h:7001 redis-a:7001 \
  --cluster-slave \
  --cluster-master-id <primary-node-id>
```

Node primary phải hết slot trước khi xóa:

```bash
redis-cli --cluster del-node redis-a:7001 <node-id>
```

Từ Redis 8.4, `CLUSTER MIGRATION` hỗ trợ migration và handoff slot nguyên tử hơn:

```redis
# Chạy trên destination node
CLUSTER MIGRATION IMPORT 0 1000 2000 3000
CLUSTER MIGRATION STATUS ALL
```

Trong lúc migration, các lệnh quan sát toàn keyspace như `SCAN`, `KEYS` hoặc `DBSIZE` có thể tạm thời không phản ánh các slot đang chuyển. Phải kiểm tra client/tooling tương thích và có kế hoạch cancel/rollback trước khi dùng production.

### 4.6 Planned failover và upgrade

Trên replica được chọn:

```bash
redis-cli -h redis-d -p 7001 CLUSTER FAILOVER
```

Quy trình rolling upgrade an toàn ở mức khái quát:

1. kiểm tra compatibility và backup từng node;
2. upgrade từng replica, mỗi lần một node;
3. đợi replica sync và `cluster_state:ok`;
4. planned failover shard cần đổi primary;
5. upgrade primary cũ sau khi nó trở thành replica;
6. chạy `CLUSTER INFO` và `redis-cli --cluster check` sau mỗi bước.

`CLUSTER FAILOVER FORCE` và đặc biệt `TAKEOVER` bỏ qua một phần hàng rào an toàn; chỉ dùng trong runbook sự cố đã được duyệt.

---

## 5. Sentinel hay Cluster?

| Tiêu chí | Sentinel | Redis Cluster |
|---|---|---|
| Bài toán chính | Failover cho một primary | Sharding và failover từng shard |
| Write scaling | Không | Có, qua nhiều primary |
| Dataset | Giới hạn bởi một primary | Phân bố trên nhiều shard |
| Multi-key/transaction | Không bị chia slot | Thường phải cùng slot |
| Client | Sentinel-aware | Cluster-aware |
| Failure unit | Cả dataset đổi primary | Từng shard đổi primary |
| Vận hành | Dễ hơn | Khó hơn: slot, reshard, redirect, nhiều node |
| Baseline phổ biến | 1 primary + 2 replica + 3 Sentinel | 3 primary + 3 replica |

Không dùng kích thước dataset kiểu “dưới 100 GB luôn Sentinel” làm luật cứng. Quyết định còn phụ thuộc working set, throughput, latency, growth, big key, hot key và thời gian reshard.

---

## 6. Placement, durability và bảo mật

### 6.1 Failure domain

- primary và replica của nó không cùng host;
- nếu cần chịu lỗi zone, chúng không cùng zone;
- Sentinel trải trên ít nhất ba failure domain độc lập;
- mỗi Cluster primary có replica ở domain khác;
- không đặt mọi dependency như DNS, load balancer và secret store vào cùng một điểm lỗi;
- đo network latency thực tế trước khi điều chỉnh timeout.

### 6.2 Persistence

HA và persistence phải được thiết kế cùng nhau:

```conf
appendonly yes
appendfsync everysec
aof-use-rdb-preamble yes
```

Nhưng cấu hình này chỉ là điểm bắt đầu. Cần:

- persistence trên node có thể trở thành primary;
- backup RDB/AOF độc lập khỏi host và cluster;
- kiểm thử restore định kỳ;
- memory/disk headroom cho fork, rewrite và full sync;
- tránh tự động khởi động một primary rỗng rồi để replica đồng bộ theo nó.

RPO của `appendfsync everysec`, replication và backup là ba cửa sổ khác nhau.

### 6.3 ACL và TLS

- tạo named user riêng cho application, replication, Sentinel và operator;
- cấp command category và key pattern tối thiểu;
- rotate secret qua secret manager;
- không expose Redis/Sentinel/cluster bus ra Internet;
- dùng TLS cho client, replication, Sentinel và cluster bus khi cần;
- kiểm tra certificate hostname trên mọi địa chỉ được topology công bố.

---

## 7. Thiết kế client để sống qua failover

Failover tốt ở server vẫn thất bại nếu client giữ connection cũ mãi hoặc retry sai.

### 7.1 Unknown outcome

Tình huống nguy hiểm:

```text
Client gửi INCR
    -> Redis đã apply
    -> connection đứt trước response
    -> client không biết command đã chạy hay chưa
```

Retry ngay có thể tăng hai lần. Với operation nghiệp vụ quan trọng:

- dùng idempotency key/request ID;
- lưu state machine có thể kiểm tra lại;
- phân biệt connect timeout, command timeout và server error;
- retry có giới hạn, exponential backoff và jitter;
- không retry vô hạn khi topology đang partition.

### 7.2 Read/write routing

| Loại request | Route mặc định |
|---|---|
| Write | Current primary |
| Read-after-write hoặc authorization | Primary |
| Dashboard chấp nhận trễ | Có thể replica |
| Multi-key Cluster operation | Node sở hữu slot chung |

Connection pool phải được refresh khi primary đổi. Health check chỉ `PING` là chưa đủ; node có thể trả `PONG` nhưng đang là replica.

---

## 8. Monitoring và alert

### 8.1 Replication/Sentinel

Alert theo triệu chứng:

- replica link down hoặc lag tăng liên tục;
- full sync lặp lại;
- không đủ healthy replica so với SLO;
- Sentinel không đạt `CKQUORUM`;
- SDOWN/ODOWN, failover started/aborted/completed;
- role không đúng với topology kỳ vọng;
- AOF/RDB error, disk đầy hoặc fork latency cao.

### 8.2 Cluster

Theo dõi:

```bash
redis-cli CLUSTER INFO
redis-cli CLUSTER SHARDS
redis-cli --cluster check <host>:<port>
```

Các tín hiệu chính:

- `cluster_state`;
- số slot `assigned`, `ok`, `pfail`, `fail`;
- node PFAIL/FAIL và replica lag;
- slot không được cover hoặc stuck ở migrating/importing;
- tỷ lệ `MOVED`, `ASK`, `CROSSSLOT`;
- skew về memory, QPS, latency và hot key giữa shard.

Alert nên gắn với tác động người dùng, ví dụ “write error rate vượt SLO” hoặc “một shard không có promotable replica”, thay vì chỉ báo process restart.

---

## 9. Runbook sự cố tối thiểu

### 9.1 Replica mất kết nối

1. kiểm tra network/TLS/ACL và `master_link_status`;
2. so offset, backlog và write rate;
3. tìm full sync loop, disk/memory pressure;
4. không restart hàng loạt replica;
5. xác nhận còn đủ replica trước khi bảo trì node khác.

### 9.2 Sentinel không failover

1. chạy `SENTINEL CKQUORUM <name>`;
2. phân biệt primary thật sự down với network partition;
3. kiểm tra majority Sentinel có nhìn thấy nhau không;
4. kiểm tra có replica đủ điều kiện promote không;
5. kiểm tra ACL/TLS cho lệnh reconfigure;
6. chỉ manual failover sau khi loại trừ split brain.

### 9.3 Cluster một shard unavailable

1. chạy `CLUSTER INFO`, `CLUSTER SHARDS` và `--cluster check`;
2. xác định primary/replica của slot bị ảnh hưởng;
3. kiểm tra majority primary và network partition;
4. không dùng `--cluster fix`, `FORCE` hoặc `TAKEOVER` trước khi backup state và hiểu ownership;
5. sau phục hồi, kiểm tra đủ slot, role, offset và lỗi client.

### 9.4 Mất toàn bộ topology

Replication không cứu được khi mọi node hoặc dữ liệu logic cùng hỏng. Chuyển sang disaster-recovery runbook:

1. cô lập nguồn ghi;
2. chọn backup nhất quán;
3. restore vào môi trường sạch;
4. kiểm tra dữ liệu và application invariant;
5. công bố endpoint mới;
6. đối soát write phát sinh trong khoảng RPO.

---

## 10. Production checklist

### Kiến trúc

- [ ] Đã ghi rõ RTO, RPO và failure domain mục tiêu.
- [ ] Topology được chọn theo nhu cầu sharding, không chỉ theo số node.
- [ ] Primary/replica/Sentinel được trải trên host hoặc zone độc lập.
- [ ] Capacity vẫn đủ khi mất một node hoặc đang full sync.

### Dữ liệu

- [ ] Đã quyết định cửa sổ mất write chấp nhận được.
- [ ] `WAIT`/`WAITAOF` nếu dùng đều kiểm tra return value.
- [ ] Read từ replica chỉ áp dụng cho luồng chấp nhận stale data.
- [ ] Persistence, backup và restore test độc lập với replication.

### Client

- [ ] Driver hỗ trợ Sentinel hoặc Cluster đúng topology.
- [ ] Có nhiều discovery/startup endpoint.
- [ ] Có retry budget, backoff, jitter và idempotency.
- [ ] Pool refresh sau role/topology change.
- [ ] Đã test failover khi đang có traffic thật giống production.

### Vận hành

- [ ] Có dashboard replication lag, role, failover và slot health.
- [ ] Có alert cho quorum/majority và shard mất replica.
- [ ] Planned failover và rolling upgrade đã được diễn tập.
- [ ] ACL, TLS, certificate và secret rotation đã được kiểm tra.
- [ ] Runbook tránh lệnh `FORCE`, `TAKEOVER`, `--cluster fix` theo phản xạ.

---

## 11. Những ngộ nhận cần tránh

| Ngộ nhận | Thực tế |
|---|---|
| Có replica là không mất dữ liệu | Replication bất đồng bộ vẫn có cửa sổ mất write |
| `WAIT` thành công là strong consistency | Nó tăng số replica đã ack offset, không cung cấp zero-loss failover |
| Sentinel quorum chính là số phiếu failover | Quorum phát hiện ODOWN; failover còn cần majority authorization |
| Ba Sentinel container trên một host là HA | Host đó vẫn là single point of failure |
| Replica read luôn là cách scale an toàn | Nó có thể stale và phá read-after-write |
| Cluster tự làm mọi multi-key operation | Key thường phải cùng hash slot |
| Sáu node luôn đủ cho mọi Cluster | Đây chỉ là baseline; capacity và failure domain mới quyết định |
| Replica thay thế backup | Lỗi logic cũng replicate; backup phải độc lập |

---

## 12. Tóm tắt

- Replication tạo bản sao nhưng mặc định bất đồng bộ.
- `WAIT`, `WAITAOF` và `min-replicas-*` giảm rủi ro theo các cách khác nhau, không tạo strong consistency.
- Sentinel tự động failover cho một writable primary; quorum phát hiện và majority authorize là hai điều kiện khác nhau.
- Redis Cluster chia 16.384 slot và failover theo shard; client phải hiểu slot, `MOVED` và `ASK`.
- HA phải đi cùng persistence, backup, placement, security, observability và client idempotency.
- Cách kiểm chứng tốt nhất là fault injection có kiểm soát: kill process, chặn mạng, làm chậm replica và đo RTO/RPO thực tế.

## Tài liệu chính thức

- [Redis replication](https://redis.io/docs/latest/operate/oss_and_stack/management/replication/)
- [`WAIT`](https://redis.io/docs/latest/commands/wait/) và [`WAITAOF`](https://redis.io/docs/latest/commands/waitaof/)
- [High availability with Redis Sentinel](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/)
- [Scale with Redis Cluster](https://redis.io/docs/latest/operate/oss_and_stack/management/scaling/)
- [Redis Cluster specification](https://redis.io/docs/latest/operate/oss_and_stack/reference/cluster-spec/)
- [`CLUSTER MIGRATION`](https://redis.io/docs/latest/commands/cluster-migration/)
- [Redis ACL](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/)
- [TLS and encryption](https://redis.io/docs/latest/operate/oss_and_stack/management/security/encryption/)
- [Upgrade a Redis Cluster](https://redis.io/docs/latest/operate/oss_and_stack/install/upgrade/cluster/)

## Đọc tiếp

- [Redis Fundamentals](redis_fundamentals.md)
- [Redis Performance & Internals](redis_performance.md)
- [Redis Design Patterns](redis_patterns.md)
- [Redis Glossary](glossary.md)

*Cập nhật lần cuối: 2026-07-29*
