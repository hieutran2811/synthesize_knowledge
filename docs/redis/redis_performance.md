---
title: "Redis Performance & Internals"
topic: redis
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# Redis Performance & Internals

> Thuật ngữ: [Glossary](glossary.md).

> Mục tiêu của tuning không phải là đạt một con số ops/s đẹp, mà là giữ latency và error rate trong SLO với workload thật. Nội dung được chuẩn hóa theo Redis Open Source 8.8.

## 1. Mental model: một request chậm ở đâu?

Latency người dùng nhìn thấy là tổng của nhiều đoạn:

```text
Application queue
    + lấy connection từ pool
    + encode request
    + network/TLS tới Redis
    + chờ trong Redis event loop
    + thực thi command
    + network/TLS trả về
    + decode response
```

Vì vậy “Redis xử lý command nhanh” không chứng minh API nhanh. Slow Log có thể trống trong khi application vẫn timeout do pool cạn, network jitter hoặc response quá lớn.

### 1.1 Latency và throughput

| Metric | Trả lời câu hỏi |
|---|---|
| p50 | Request điển hình mất bao lâu? |
| p95/p99/p99.9 | Nhóm request chậm nhất mà người dùng thực tế gặp phải? |
| Throughput | Hoàn thành bao nhiêu operation mỗi giây? |
| Error/timeout rate | Bao nhiêu request không hoàn thành đúng hạn? |
| Saturation | CPU, network, memory, connection pool hoặc shard đã gần giới hạn chưa? |

Tăng concurrency thường làm throughput tăng cho đến điểm bão hòa; sau đó queue dài hơn, tail latency tăng mạnh và timeout lan truyền. Chỉ tối ưu ops/s mà bỏ qua p99 và error rate thường tạo một hệ thống “benchmark nhanh, production chậm”.

### 1.2 Redis có single-threaded không?

Mô tả chính xác hơn là:

- command trên một shard phần lớn vẫn có semantics thực thi tuần tự;
- event loop giúp xử lý nhiều connection mà không cần một thread cho mỗi client;
- background thread/process xử lý một số I/O, lazy free, RDB và AOF;
- Redis 8 có implementation I/O threading mới để tận dụng nhiều core cho network I/O và parsing;
- Search, vector và một số Redis 8 workload có worker pool riêng.

I/O thread không làm command O(N) biến thành O(1), không làm script dài ngừng block các client khác và không sửa được hot key. Phải benchmark `io-threads` trên đúng CPU, network, payload, TLS và workload; không đặt bằng số core theo công thức máy móc.

---

## 2. Đo trước khi tuning

### 2.1 Viết workload profile

Trước khi chạy benchmark, ghi lại:

- tỷ lệ read/write và command mix;
- key/value size distribution, không chỉ average;
- số phần tử của List/Set/Hash/Sorted Set/Stream;
- số connection, concurrency và pipeline depth;
- hit/miss ratio;
- TTL distribution và eviction policy;
- persistence, replication, TLS và Cluster topology;
- traffic steady, burst và batch;
- SLO p50/p95/p99, error rate và throughput.

Hai workload cùng 100.000 GET/s nhưng value 100 byte và 100 KB là hai bài toán network/memory hoàn toàn khác nhau.

### 2.2 Benchmark có đối chứng

`redis-benchmark` hữu ích để kiểm tra nhanh server/hardware:

```bash
# Workload cơ bản: random keyspace, value 1 KiB, không pipeline.
redis-benchmark \
  -h redis.internal -p 6379 \
  -t get,set \
  -n 1000000 -c 50 \
  -d 1024 -r 1000000 \
  --threads 4

# Cùng workload nhưng pipeline 16 command.
redis-benchmark \
  -h redis.internal -p 6379 \
  -t get,set \
  -n 1000000 -c 50 \
  -d 1024 -r 1000000 \
  --threads 4 -P 16
```

Không đặt password trực tiếp trên command line nếu shell history/process list có thể lộ secret. Dùng cơ chế credential an toàn của môi trường.

Một benchmark đáng tin cần:

1. chạy từ host giống application, không chỉ localhost;
2. dùng cùng TLS, persistence, replication và Cluster mode với production;
3. warm up dataset/cache trước khi đo;
4. đủ dài để gặp GC, fork, fsync và traffic burst;
5. lặp lại nhiều lần, ghi variance;
6. đo cả client, Redis và OS;
7. thay đúng một biến giữa hai lần A/B;
8. không chạy workload phá hoại hoặc saturate trên production.

`redis-benchmark` mặc định không đại diện đầy đủ cho business workflow. Benchmark cuối cùng nên dùng application client, serialization, key distribution và response size thật.

### 2.3 Bộ kết quả tối thiểu

```text
Workload:       80% GET, 15% SET EX, 5% ZRANGE
Dataset:        20M keys, value p50=600B, p99=8KiB
Concurrency:    200, pool=100, pipeline=8
Topology:       3-shard Cluster, AOF everysec, TLS
Result:         throughput, p50/p95/p99/p99.9, timeout/error
Resources:      CPU/core, RSS, bandwidth, disk latency, evictions
Background:     BGSAVE/AOF rewrite/full sync xảy ra hay không
```

Không báo cáo chỉ một con số trung bình.

---

## 3. Quy trình chẩn đoán latency

Đi từ ngoài vào trong để tránh sửa sai tầng.

### 3.1 Tầng application

Kiểm tra:

- end-to-end latency theo command/use case;
- thời gian chờ connection pool;
- active/idle/pending connection;
- retry count và timeout theo loại;
- payload request/response;
- serialization/deserialization;
- cache hit, miss và fallback latency;
- topology refresh, `MOVED`/`ASK` nếu dùng Cluster.

Gắn command name, Redis endpoint/shard và operation type vào trace; không gắn key/value nhạy cảm có cardinality cao.

### 3.2 Network và intrinsic latency

```bash
# Đo round-trip từ máy client.
redis-cli -h redis.internal -p 6379 --latency
redis-cli -h redis.internal -p 6379 --latency-dist

# Chạy trên chính Redis host; CPU-intensive, chỉ dùng có kiểm soát.
redis-cli --intrinsic-latency 30
```

Intrinsic latency là khoảng thời gian OS/hypervisor không cấp CPU cho process. Redis không thể có tail latency tốt hơn nền tảng bên dưới. So sánh nhiều thời điểm để phát hiện noisy neighbor hoặc CPU throttling.

### 3.3 Slow Log

```conf
# Đơn vị microsecond; chọn theo SLO thay vì copy con số này.
slowlog-log-slower-than 5000
slowlog-max-len 1024

# Redis 8.8: giới hạn dữ liệu argument giữ trong mỗi entry.
slowlog-entry-max-argc 32
slowlog-entry-max-string-len 128
```

```bash
redis-cli SLOWLOG LEN
redis-cli SLOWLOG GET 20
redis-cli SLOWLOG RESET
```

Slow Log chỉ đo thời gian Redis thực thi command, không gồm network I/O với client. Vì vậy:

- Slow Log có entry: điều tra command complexity, data size, script hoặc CPU;
- client chậm nhưng Slow Log sạch: điều tra queue, pool, network, TLS, response size và event-loop wait.

Không log toàn bộ command lâu dài bằng threshold `0`; dữ liệu argument có thể nhạy cảm và chi phí quan sát có thể tăng.

### 3.4 Latency monitor và command statistics

```bash
# Đơn vị millisecond; 0 là tắt.
redis-cli CONFIG SET latency-monitor-threshold 10

redis-cli LATENCY LATEST
redis-cli LATENCY HISTORY command
redis-cli LATENCY GRAPH command
redis-cli LATENCY DOCTOR

# Histogram theo command và thống kê tích lũy.
redis-cli LATENCY HISTOGRAM GET SET
redis-cli INFO commandstats
redis-cli INFO latencystats
redis-cli INFO errorstats
```

`INFO commandstats` cho calls, CPU time và rejected/failed calls theo command. Tìm command có tổng CPU lớn, không chỉ command có một lần chậm nhất.

### 3.5 `MONITOR` là công cụ cuối, không phải dashboard

`MONITOR` stream mọi command và có thể ảnh hưởng đáng kể tới throughput/latency, đồng thời làm lộ dữ liệu. Chỉ dùng trong cửa sổ debug ngắn, có ACL phù hợp, lọc ở môi trường an toàn và dừng ngay sau khi thu đủ bằng chứng.

### 3.6 Ánh xạ triệu chứng

| Triệu chứng | Khả năng thường gặp | Bằng chứng cần tìm |
|---|---|---|
| p99 tăng, Slow Log có entry | Big key, O(N), script/function dài | Slow Log, commandstats, key size |
| p99 tăng, Slow Log sạch | Network, pool, queue, TLS, response lớn | Client metrics, trace, bandwidth |
| Spike cùng BGSAVE/rewrite | `fork()`, copy-on-write, disk I/O | `latest_fork_usec`, COW, disk latency |
| CPU một core cao | Command execution/hot key | commandstats, hotkeys, flame/profile nếu có |
| CPU nhiều core/network cao | I/O/parsing/TLS hoặc worker workload | per-thread stats, bandwidth, payload |
| Latency tăng khi memory gần đầy | Eviction, expire, allocator, swap | evicted keys, memory stats, vmstat |
| Chỉ một Cluster shard chậm | Hot key hoặc slot skew | per-node QPS, memory, latency |

---

## 4. Command complexity, big key và hot key

### 4.1 Complexity phụ thuộc N nào?

O(N) chỉ hữu ích khi biết N là gì:

| Command/pattern | N thường là | Rủi ro |
|---|---|---|
| `KEYS *` | Toàn keyspace | Block shard lâu |
| `HGETALL` | Số field và tổng response | CPU + bandwidth + client decode |
| `SMEMBERS` | Số member | Response rất lớn |
| `LRANGE 0 -1` | Độ dài List | Block và tạo output buffer |
| `SUNION`/`ZINTER` | Tổng collection tham gia | CPU và temporary memory |
| Script/Function loop | Số lần lặp/data được chạm | Chặn event loop |

Command O(1) vẫn có thể chậm nếu value 50 MB vì copy, network và client decode.

### 4.2 Duyệt dữ liệu an toàn hơn

```redis
SCAN 0 MATCH user:* COUNT 1000
HSCAN user:42 0 COUNT 100
SSCAN feature:members 0 COUNT 100
ZSCAN leaderboard 0 COUNT 100
```

`SCAN`:

- incremental nên mỗi lần ít block hơn `KEYS`;
- không phải snapshot;
- có thể trả duplicate;
- `COUNT` chỉ là hint;
- quét hết keyspace vẫn tiêu tốn CPU/network.

Tool inventory cũng dùng scan, nên throttle và chạy ngoài peak:

```bash
redis-cli --keystats --top 20 -i 0.1
redis-cli --bigkeys -i 0.1
redis-cli --memkeys -i 0.1

# Chỉ hoạt động có ý nghĩa khi maxmemory policy dùng LFU.
redis-cli --hotkeys -i 0.1
```

### 4.3 Xử lý big key

Trước hết xác định “big” theo cả byte, số phần tử và cost command:

```redis
MEMORY USAGE orders:2026-07 SAMPLES 10
TYPE orders:2026-07
OBJECT ENCODING orders:2026-07
LLEN queue:email
HLEN customer:42
SCARD campaign:members
ZCARD leaderboard:global
XLEN events:orders
```

Các hướng sửa:

- chia collection theo tenant/time bucket;
- page/range thay vì đọc toàn bộ;
- trim Stream/List theo retention;
- lưu field cần dùng thay vì object thừa;
- dùng `UNLINK` thay `DEL` cho object tốn nhiều thời gian free;
- phân tán hot key hoặc cache kết quả ở application nếu consistency cho phép.

```redis
UNLINK obsolete:large-key
```

`UNLINK` gỡ key khỏi keyspace nhanh rồi free memory ở background. Công việc không biến mất; cần theo dõi backlog/CPU của lazy free.

---

## 5. Memory: `maxmemory` không phải giới hạn RSS

### 5.1 Redis dùng memory cho gì?

```text
Dataset
+ key/value metadata và encoding
+ allocator fragmentation
+ client input/output buffers
+ replication/AOF buffers
+ script/function, module/index
+ copy-on-write khi fork
+ Redis process và shared libraries
= RSS mà OS quan sát
```

`maxmemory` chủ yếu điều khiển vùng dữ liệu chịu eviction, không phải hard cap cho toàn bộ RSS. Một số buffer replication/AOF không được tính vào eviction để tránh vòng lặp “evict tạo write mới rồi buffer lại lớn hơn”.

Luôn chừa headroom cho:

- peak dataset và allocator;
- connection/output buffer;
- replication backlog/full sync;
- RDB/AOF fork và copy-on-write;
- Search/vector index, module và OS page cache;
- failover hoặc reshard tạm thời.

### 5.2 Đọc memory metrics

```bash
redis-cli INFO memory
redis-cli MEMORY STATS
redis-cli MEMORY DOCTOR
```

| Metric | Cách hiểu |
|---|---|
| `used_memory` | Bytes Redis đã yêu cầu allocator |
| `used_memory_dataset` | Phần dataset sau khi trừ overhead |
| `used_memory_overhead` | Metadata, client, replication và overhead khác |
| `used_memory_rss` | Resident memory OS nhìn thấy |
| `allocator_frag_ratio/bytes` | Fragmentation trong allocator |
| `rss_overhead_ratio/bytes` | Chênh lệch allocator resident và process RSS |
| `mem_not_counted_for_evict` | Memory không tham gia quyết định eviction |
| `used_memory_peak` | Peak đã từng cấp phát |
| `current_cow_peak` | Memory copy-on-write trong background operation |

Không dùng một luật kiểu “fragmentation ratio > 2 thì restart”. Ratio có thể rất cao khi dataset hiện tại nhỏ hơn peak. Phải nhìn thêm số byte, allocator, RSS, swap và xu hướng theo thời gian.

### 5.3 Encoding của collection nhỏ

Redis dùng encoding compact như listpack/intset cho collection nhỏ, rồi chuyển encoding khi vượt threshold.

```redis
OBJECT ENCODING cart:42
MEMORY USAGE cart:42
```

Các setting như:

```conf
hash-max-listpack-entries <count>
hash-max-listpack-value <bytes>
zset-max-listpack-entries <count>
zset-max-listpack-value <bytes>
set-max-intset-entries <count>
set-max-listpack-entries <count>
```

là trade-off memory/CPU. Tăng threshold có thể tiết kiệm memory nhưng làm update/lookup tốn CPU hơn. Default thay đổi theo version; kiểm tra config đang chạy và benchmark trước khi sửa.

Key name ngắn giúp tiết kiệm memory trên hàng triệu key, nhưng vẫn phải đủ rõ để vận hành:

```text
Quá dài: authentication_service:user_session_token:123
Khó hiểu: a:u:s:123
Cân bằng: auth:session:123
```

### 5.4 Fragmentation, active defrag và purge

```conf
# Chỉ bật khi build/allocator hỗ trợ và đã đo CPU headroom.
activedefrag yes
```

Active defragmentation dùng CPU để di chuyển allocation và thu hồi page. `MEMORY PURGE` chỉ yêu cầu allocator trả page có thể trả về OS; nó có thể ít hoặc không có tác dụng nếu page vẫn chứa allocation đang dùng.

Quy trình:

1. xác nhận RSS cao có gây memory pressure không;
2. phân biệt dataset growth với allocator/RSS overhead;
3. xem peak lịch sử và delete/expire pattern;
4. benchmark active defrag với latency SLO;
5. chỉ restart/failover có kế hoạch nếu thực sự cần compact RSS.

---

## 6. Eviction: chọn theo vai trò dữ liệu

Khi `used_memory` chạm `maxmemory`, Redis áp dụng policy:

| Policy | Tập key ứng viên | Khi phù hợp |
|---|---|---|
| `noeviction` | Không xóa tự động; write phù hợp trả OOM | Redis giữ state không được phép mất tùy ý |
| `allkeys-lru` | Mọi key, ưu tiên key ít được dùng gần đây | Cache có locality theo thời gian |
| `allkeys-lfu` | Mọi key, ưu tiên key ít được truy cập | Cache có hot set ổn định |
| `allkeys-random` | Mọi key | Access gần uniform hoặc muốn cost chọn thấp |
| `volatile-lru` | Chỉ key có TTL | Dataset trộn cache và key không được evict |
| `volatile-lfu` | Chỉ key có TTL | Như trên, có hot set |
| `volatile-random` | Chỉ key có TTL | Trường hợp đơn giản |
| `volatile-ttl` | Key có TTL gần hết trước | Muốn ưu tiên dữ liệu sắp hết hạn |

```conf
maxmemory 8gb
maxmemory-policy allkeys-lfu
maxmemory-samples 5
```

LRU/LFU của Redis là xấp xỉ dựa trên sampling. `maxmemory-samples` cao hơn có thể chọn chính xác hơn nhưng tiêu tốn CPU hơn.

### 6.1 Các bẫy thường gặp

- `volatile-*` gần như `noeviction` nếu không còn key có TTL;
- eviction liên tục nghĩa là working set không vừa memory hoặc TTL/policy sai;
- cache hit rate cao toàn cục có thể che một endpoint miss liên tục;
- key lớn bị evict/free có thể gây latency;
- cùng expiry timestamp tạo “TTL avalanche” và load lớn về source of truth.

Với cache, thêm TTL jitter:

```text
ttl_thực = ttl_cơ_sở + random(0, jitter)
```

Theo dõi:

```bash
redis-cli INFO stats
redis-cli INFO keyspace
```

Tập trung vào `keyspace_hits`, `keyspace_misses`, `evicted_keys`, `expired_keys`, expired/evicted time và error/OOM phía application.

---

## 7. Network, connection và pipelining

### 7.1 Giảm round trip

Thứ tự ưu tiên:

1. dùng command built-in đúng semantics;
2. dùng command variadic/aggregate như `MGET`, `MSET`, multi-field `HSET`;
3. pipeline các command độc lập;
4. dùng transaction/script/function khi cần atomic conditional logic.

Không thay 100 request bằng một response 100 MB rồi gọi đó là tối ưu.

### 7.2 Pipeline có giới hạn

```text
Không pipeline:
request -> response -> request -> response

Pipeline 4:
request request request request -> response response response response
```

Pipeline giảm số round trip và syscall, nhưng:

- không tạo atomicity;
- server vẫn thực thi từng command;
- client/server phải buffer command và response;
- batch quá lớn tăng memory và head-of-line blocking;
- latency của phần tử đầu có thể phải chờ cả batch được application xử lý;
- trong Cluster, client phải nhóm/routing command theo node.

Chọn batch theo cả **số command**, **tổng byte** và **thời gian flush**:

```text
flush khi:
  command_count >= 100
  OR buffered_bytes >= 256 KiB
  OR oldest_command_wait >= 2 ms
```

Các con số trên chỉ minh họa; phải benchmark theo SLO.

### 7.3 Java/Spring Data Redis

```java
List<Object> replies = redisTemplate.executePipelined(
    (RedisCallback<Object>) connection -> {
        for (Map.Entry<byte[], byte[]> entry : entries) {
            connection.stringCommands().set(
                entry.getKey(),
                entry.getValue()
            );
        }
        return null;
    }
);
```

Điểm cần kiểm tra:

- serializer có chạy một lần cho mỗi item không;
- batch có giới hạn byte/count không;
- timeout áp cho toàn batch hay từng command;
- lỗi một command được ánh xạ đúng response index không;
- driver Cluster có split pipeline theo node không;
- có backpressure khi producer nhanh hơn Redis không.

### 7.4 Connection pool

Pool quá nhỏ tạo queue; pool quá lớn tạo nhiều socket, memory và contention.

Theo dõi đồng thời:

- pending waiters và acquire latency;
- active/idle connection;
- Redis `connected_clients`, `blocked_clients`;
- reconnect/auth/TLS handshake rate;
- client output buffer và network bandwidth.

Tái sử dụng connection. Không connect/auth/disconnect cho từng request.

### 7.5 Client-side caching

Redis server-assisted client-side caching dùng `CLIENT TRACKING` để gửi invalidation:

```redis
CLIENT TRACKING ON OPTIN
CLIENT CACHING YES
GET product:42
```

RESP3 có thể nhận invalidation dạng push trên connection. Hai mode chính:

- default tracking: Redis nhớ key client đã đọc;
- `BCAST PREFIX ...`: broadcast invalidation theo prefix, ít state server hơn nhưng nhiều message hơn.

Chỉ dùng khi client library hỗ trợ đúng. Application phải:

- giới hạn local cache và TTL;
- xóa item khi nhận invalidation;
- invalidate/clear an toàn khi mất connection;
- đo local hit rate so với invalidation rate;
- không coi invalidation stream là durable event log.

Client-side caching có thể giảm latency/network rất mạnh cho dữ liệu đọc nhiều, đổi ít; với dữ liệu đổi liên tục, chi phí invalidation có thể lớn hơn lợi ích.

### 7.6 RESP2 và RESP3

RESP3 biểu diễn thêm map, set, boolean, double, attribute và push message. Nó giúp API/protocol rõ hơn và hỗ trợ tracking/Pub/Sub thuận tiện hơn, nhưng không phải “bật RESP3 là Redis nhanh hơn”.

```redis
HELLO 3
```

Phải kiểm tra client, proxy và tooling tương thích trước khi chuyển protocol.

---

## 8. Transaction, script và Redis Functions

### 8.1 `MULTI`/`EXEC`

```redis
MULTI
INCR account:42:attempts
EXPIRE account:42:attempts 60
EXEC
```

Redis bảo đảm các command trong transaction chạy tuần tự, không bị command client khác xen giữa. Nhưng:

- command chỉ được queue trước `EXEC`;
- lỗi queue/syntax có thể làm transaction bị từ chối;
- runtime error của một command không rollback các command khác;
- transaction dài block các client khác lâu hơn;
- connection đứt sau `EXEC` có thể tạo unknown outcome ở client.

`WATCH` cung cấp optimistic locking:

```redis
WATCH inventory:42
GET inventory:42
MULTI
SET inventory:42 9
EXEC
```

Nếu key thay đổi/expire/evict trước `EXEC`, transaction abort và client phải đọc lại rồi retry có giới hạn. Với String đơn giản, Redis 8.4+ có conditional `SET` và `DELEX`; ưu tiên một command built-in khi đáp ứng đúng semantics.

### 8.2 Lua script

```redis
EVALSHA <sha1> 1 rate:user:42 100 60
```

Script:

- chạy atomic;
- giảm round trip cho logic phụ thuộc kết quả trước;
- block server activity trong thời gian thực thi;
- phải khai báo key rõ ràng, đặc biệt trong Cluster;
- nên dùng `EVALSHA`/client script abstraction thay vì gửi source mỗi lần.

Không loop qua collection không giới hạn, gọi command có response khổng lồ hoặc đặt business workflow dài vào Lua.

### 8.3 Redis Functions

Redis Functions, có từ Redis 7, là artifact được quản lý cùng database:

- load/deploy library như một bước quản trị;
- gọi bằng tên qua `FCALL`/`FCALL_RO`;
- được persistence và replication cùng database;
- dễ version hóa API hơn ad-hoc `EVAL`.

```redis
FCALL reserve_inventory 1 inventory:{42} 1
```

Functions có atomic/blocking semantics tương tự script. “Được quản lý tốt hơn” không có nghĩa “được phép chạy lâu hơn”.

### 8.4 Chọn công cụ

| Nhu cầu | Ưu tiên |
|---|---|
| Redis đã có command atomic | Built-in command |
| Nhiều command độc lập, giảm RTT | Pipeline |
| Nhóm command không bị xen giữa | `MULTI`/`EXEC` |
| Read-modify-write ít conflict | Conditional command hoặc `WATCH` |
| Logic atomic ngắn, deploy cùng app | Script/EVALSHA |
| API server-side dùng chung, quản lý lifecycle | Redis Functions |

---

## 9. Hidden work: persistence, replication, expiration

### 9.1 RDB/AOF và copy-on-write

`BGSAVE`/AOF rewrite dùng `fork()` và copy-on-write:

```text
Parent tiếp tục nhận write
Child ghi snapshot/base AOF
Page parent sửa trong lúc child sống -> OS copy page
```

Workload write-heavy có thể làm COW memory và memory bandwidth tăng mạnh.

Theo dõi:

```bash
redis-cli INFO persistence
redis-cli INFO stats
```

Các tín hiệu:

- `latest_fork_usec`;
- `current_cow_peak`, `rdb_last_cow_size`, `aof_last_cow_size`;
- `rdb_bgsave_in_progress`, `aof_rewrite_in_progress`;
- `aof_delayed_fsync`;
- disk latency/throughput và available memory.

Đặt RDB/AOF trên storage chậm hoặc dùng chung bandwidth với replication có thể tạo spike. Mọi thay đổi fsync policy đều là trade-off durability, không chỉ performance.

### 9.2 Replication và reshard

Full synchronization tạo snapshot, truyền dataset và load trên replica. Cluster reshard/migration dùng CPU/network và có thể đổi redirect rate.

Khi capacity test, phải bao gồm:

- một replica full sync;
- planned failover;
- RDB/AOF rewrite;
- Cluster reshard;
- một node mất khiến traffic dồn sang node còn lại.

Peak bình thường chưa phải peak khi hệ thống degraded.

### 9.3 Expiration và keyspace notification

Redis expire key bằng cả passive và active expiration. Nhiều key hết hạn cùng lúc có thể gây:

- CPU cho expiration;
- miss burst;
- stampede tới database/API nguồn;
- network/write burst khi cache được nạp lại.

Keyspace notifications mặc định không phải durable queue:

- bật thêm event làm tăng CPU;
- subscriber disconnect có thể mất event;
- không dùng làm nguồn duy nhất cho workflow quan trọng.

Chỉ bật đúng event class/prefix cần thiết và đo overhead.

---

## 10. CPU, I/O threads và hệ điều hành

### 10.1 I/O threading trong Redis 8

```conf
# Ví dụ thử nghiệm, không phải default production.
io-threads 4
```

Quy trình chọn:

1. đo một thread với workload thật;
2. xác nhận CPU/network I/O là bottleneck;
3. thử nhiều giá trị nhỏ hơn số CPU khả dụng;
4. so throughput, p99, CPU và fairness;
5. test lại với TLS, persistence và replication;
6. giữ core/headroom cho background work và OS.

Nếu bottleneck là script/O(N)/hot shard, thêm I/O thread có thể không giúp.

### 10.2 OS và container

Các rủi ro thường gặp:

- swap/page fault: latency tăng theo bậc lớn;
- Transparent Huge Pages: có thể làm fork/COW latency xấu;
- `vm.overcommit_memory` không phù hợp: background save có thể thất bại;
- file descriptor/backlog thấp: reject connection;
- CPU throttling/noisy neighbor;
- NUMA placement và memory bandwidth;
- disk/network volume có latency biến động;
- container memory limit sát `maxmemory`, khiến OOM kill trước khi Redis tự bảo vệ.

Không chạy lệnh `sysctl`/tắt THP theo phản xạ. Kiểm tra khuyến nghị của Redis version, OS, container runtime và managed provider; rollout có đo lường và khả năng rollback.

---

## 11. Khi nào scale?

Scale up hoặc tune khi:

- dataset vừa một node với headroom;
- bottleneck là network/I/O có thể cải thiện;
- command/data model còn tối ưu được;
- cần giữ topology đơn giản.

Scale out bằng Cluster khi:

- dataset không vừa memory một node an toàn;
- write/CPU cần nhiều shard;
- có thể thiết kế key theo slot;
- application/client chịu được Cluster semantics.

Replica read chỉ scale luồng chấp nhận stale data. Hot key không tự hết khi thêm shard vì một key vẫn thuộc một slot; cần partition key, local caching, precomputation hoặc thay đổi data model.

Capacity plan theo trạng thái mất node:

```text
steady-state utilization < capacity còn lại sau failure
```

Nếu cluster chỉ vừa tải khi mọi node khỏe, failover sẽ biến sự cố nhỏ thành overload toàn hệ thống.

---

## 12. Dashboard và alert tối thiểu

### 12.1 Application/client

- operation latency p50/p95/p99/p99.9;
- timeout/error/retry;
- pool acquire latency và pending;
- request/response bytes;
- cache hit/miss/fallback;
- pipeline batch size/bytes/flush time;
- topology redirect/reconnect;
- local client-cache hit và invalidation.

### 12.2 Redis

```bash
redis-cli INFO server
redis-cli INFO clients
redis-cli INFO memory
redis-cli INFO persistence
redis-cli INFO stats
redis-cli INFO replication
redis-cli INFO cpu
redis-cli INFO commandstats
redis-cli INFO latencystats
redis-cli INFO errorstats
redis-cli INFO keyspace
```

Theo dõi:

- ops/s và network bytes;
- connected/blocked/rejected clients;
- command calls, CPU, rejected/failed;
- memory dataset/overhead/RSS/COW;
- hit, miss, expire, evict, OOM;
- fork, save, rewrite, fsync;
- replica lag/full sync;
- Cluster slot/node health;
- per-thread/I/O thread activity khi dùng Redis 8 I/O threading.

### 12.3 OS/platform

- CPU per core, steal/throttling;
- RSS, available memory, swap/page fault;
- disk latency/queue/throughput;
- network RTT, retransmit, bandwidth;
- file descriptor/socket backlog;
- container OOM/throttle events.

Alert cần gắn với SLO và xu hướng. Ví dụ `used_memory > 80%` tự nó chưa đủ; quan trọng hơn là tốc độ tăng, headroom cho COW, eviction rate và thời gian dự kiến chạm giới hạn.

---

## 13. Runbook performance

### 13.1 p99 tăng đột ngột

1. xác định phạm vi: mọi command, một endpoint hay một shard;
2. so application trace với Redis latency;
3. kiểm tra pool/network trước;
4. xem Slow Log, latency events và commandstats;
5. đối chiếu thời điểm BGSAVE/rewrite/full sync/reshard;
6. kiểm tra CPU throttling, swap, disk/network;
7. rollback thay đổi gần nhất nếu tương quan rõ.

### 13.2 Memory gần đầy

1. phân biệt dataset, overhead, RSS và COW;
2. xem growth rate, big key và TTL distribution;
3. kiểm tra policy/eviction/OOM có đúng vai trò dữ liệu;
4. giảm traffic hoặc scale trước khi chạy scan nặng;
5. xóa bằng `UNLINK`/batch có kiểm soát;
6. không dùng `FLUSHALL`, restart hoặc `MEMORY PURGE` như giải pháp mặc định.

### 13.3 CPU cao

1. tìm command có tổng CPU/call tăng;
2. tìm big key, hot key, script/function;
3. kiểm tra expire/evict/lazy free;
4. kiểm tra Search/vector worker workload;
5. xác định main execution hay I/O là bottleneck;
6. sửa data model/command trước khi tăng thread/core.

### 13.4 Network hoặc output buffer cao

1. xem response size và command trả toàn collection;
2. kiểm tra pipeline batch/concurrency;
3. xác định slow consumer;
4. page/range hoặc compress ở tầng phù hợp;
5. dùng client-side cache cho dữ liệu đọc nhiều, đổi ít;
6. scale bandwidth/shard nếu workload hợp lệ vẫn vượt capacity.

---

## 14. Thay đổi cấu hình an toàn

```bash
redis-cli CONFIG GET maxmemory
redis-cli CONFIG GET maxmemory-policy
redis-cli CONFIG GET io-threads
redis-cli CONFIG GET slowlog-log-slower-than
```

Trước mỗi thay đổi:

1. ghi hypothesis và metric kỳ vọng;
2. xác nhận parameter có runtime-configurable không;
3. thử trên staging/canary;
4. đổi một biến;
5. quan sát đủ steady state và background cycle;
6. có rollback;
7. lưu cấu hình bền vững theo cơ chế deployment.

`CONFIG SET` thay đổi runtime không tự động đồng nghĩa file/deployment source đã được cập nhật. `CONFIG REWRITE` cũng là mutation cần kiểm soát, đặc biệt trong container hoặc config do automation quản lý.

---

## 15. Những ngộ nhận cần tránh

| Ngộ nhận | Thực tế |
|---|---|
| Average latency thấp là đủ | Tail latency và timeout mới thường quyết định trải nghiệm |
| Redis là single-thread nên nhiều core vô ích | Redis 8 dùng I/O threads/worker cho một số việc, nhưng command/data model vẫn quyết định |
| Pipeline 1.000 command luôn nhanh hơn | Batch quá lớn tăng buffer, HOL blocking và tail latency |
| Transaction là all-or-nothing có rollback | Redis không rollback runtime error |
| Lua/Function luôn nhanh hơn nhiều command | Logic dài block event loop; built-in command thường tốt hơn |
| `maxmemory` là hard RSS limit | RSS còn allocator, buffer, COW, index và process overhead |
| Fragmentation ratio cao nghĩa là memory leak | Cần nhìn bytes, peak, allocator, RSS và swap |
| `MEMORY PURGE` chắc chắn trả RAM | Allocator chỉ trả page thực sự có thể release |
| `SCAN` miễn phí | Nó chỉ chia nhỏ công việc; full scan vẫn có cost |
| Thêm shard sửa hot key | Một key vẫn nằm trên một slot |
| Slow Log sạch nghĩa là Redis không liên quan | Queue/network/output buffer không nằm trong execution time của Slow Log |
| `MONITOR` là monitoring production | Nó có overhead và nguy cơ lộ dữ liệu |

---

## 16. Production checklist

### Đo lường

- [ ] Có SLO p50/p95/p99/error thay vì chỉ ops/s.
- [ ] Workload benchmark giống command mix, payload và topology thật.
- [ ] Có client, Redis và OS metrics cùng timestamp.
- [ ] Benchmark gồm persistence, replication và failure state.

### Data model

- [ ] Không có `KEYS` hoặc full-collection read trên request path.
- [ ] Có inventory big key/hot key và giới hạn collection.
- [ ] Command complexity được đánh giá theo data size production.
- [ ] TTL có jitter/retention phù hợp.

### Memory

- [ ] `maxmemory` và policy khớp cache/source-of-truth semantics.
- [ ] Có headroom cho RSS, COW, buffer, replication và index.
- [ ] Theo dõi eviction/OOM, allocator bytes và swap.
- [ ] Active defrag/listpack threshold chỉ đổi sau benchmark.

### Client/network

- [ ] Connection được tái sử dụng, pool có giới hạn và metric.
- [ ] Pipeline có giới hạn count/bytes/time và backpressure.
- [ ] Timeout/retry không khuếch đại overload.
- [ ] Client-side caching nếu dùng có invalidation và disconnect strategy.

### Server

- [ ] Slow Log/latency monitor threshold theo SLO.
- [ ] I/O threads được benchmark, không sao chép cấu hình.
- [ ] Quan sát fork, COW, fsync, full sync và reshard.
- [ ] Đã diễn tập runbook latency/memory/CPU/network.

---

## 17. Tóm tắt

- Bắt đầu từ SLO và workload profile, không bắt đầu từ `redis.conf`.
- Tách end-to-end latency khỏi command execution time.
- Big key, hot key và command complexity thường quan trọng hơn micro-tuning.
- Pipeline giảm RTT nhưng cần batch bounded và backpressure.
- `maxmemory` không giới hạn toàn bộ RSS; eviction phải khớp vai trò dữ liệu.
- Transaction không rollback; script/function atomic nhưng có thể block.
- Redis 8 I/O threading có thể tăng throughput khi I/O là bottleneck, nhưng phải benchmark.
- Mọi tuning cần hypothesis, A/B measurement và rollback.

## Tài liệu chính thức

- [Diagnosing latency issues](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency/)
- [Redis latency monitor](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency-monitor/)
- [Redis benchmark](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/benchmarks/)
- [Memory optimization](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/)
- [Key eviction](https://redis.io/docs/latest/develop/reference/eviction/)
- [Redis CLI: big keys and memory analysis](https://redis.io/docs/latest/develop/tools/cli/)
- [Transactions](https://redis.io/docs/latest/develop/using-commands/transactions/)
- [Redis programmability](https://redis.io/docs/latest/develop/programmability/)
- [Client-side caching](https://redis.io/docs/latest/develop/reference/client-side-caching/)
- [Redis Open Source 8.0 release notes](https://redis.io/docs/latest/operate/oss_and_stack/stack-with-enterprise/release-notes/redisce/redisos-8.0-release-notes/)
- [Redis Open Source 8.8](https://redis.io/docs/latest/develop/whats-new/8-8/)

## Đọc tiếp

- [Redis Fundamentals](redis_fundamentals.md)
- [Redis High Availability](redis_ha.md)
- [Redis Design Patterns](redis_patterns.md)
- [Redis Glossary](glossary.md)

*Cập nhật lần cuối: 2026-07-29*
