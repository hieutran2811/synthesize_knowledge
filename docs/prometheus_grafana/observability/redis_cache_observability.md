---
title: "Redis & Cache Observability – Từ Hit Ratio đến Tính đúng đắn"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 13
---
# Redis & Cache Observability – Từ Hit Ratio đến Tính đúng đắn

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát cache như một thành phần phân tán có ảnh hưởng trực tiếp
> đến latency, tải database và tính đúng đắn; không chỉ dựng một biểu đồ hit ratio.
>
> Baseline tham chiếu: **Redis Open Source 8.x**, Prometheus/Grafana và OpenTelemetry.
> Tên metric của exporter có thể thay đổi theo phiên bản; luôn kiểm tra `/metrics` trước khi
> sao chép PromQL.
>
> Không chạy `KEYS *`, `MONITOR`, `DEBUG`, `SAVE`, quét keyspace không giới hạn, xóa key hàng
> loạt hoặc đổi eviction/persistence trên production chỉ để điều tra.
>
> Nên đọc trước:
> [Metrics Design](metrics_design.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Database Observability](database_observability_performance.md) và
> [Incident Response](incident_response_observability.md).

---

## 1. Vì sao cache observability khó?

Cache nằm giữa application và nguồn dữ liệu:

```text
request
  → client pool
  → network
  → Redis
  → hit: trả dữ liệu
  → miss: database/API → compute → populate cache
```

Một cache rất nhanh vẫn có thể làm hệ thống sai vì trả dữ liệu cũ. Một hit ratio cao vẫn có
thể vô nghĩa nếu những key tốn kém nhất luôn miss. Vì vậy phải quan sát đồng thời:

- trải nghiệm người dùng;
- tính đúng đắn và độ mới dữ liệu;
- hiệu quả giảm tải nguồn;
- sức khỏe client, Redis, OS và topology;
- durability nếu Redis còn giữ state quan trọng.

---

## 2. Cache không mặc nhiên là source of truth

Viết rõ contract cho từng workload:

| Vai trò | Khi Redis mất dữ liệu | Ưu tiên |
|---|---|---|
| cache tái tạo được | warm lại từ database | availability, latency |
| session/token | user có thể bị logout | correctness, security |
| rate limit | có thể vượt/chặn nhầm quota | consistency |
| queue/stream | có thể mất công việc | durability |
| distributed lock | có thể chạy trùng | safety |

Không áp dụng cùng một SLO, persistence và alert cho mọi Redis instance.

---

## 3. Bắt đầu từ user journey

Ví dụ với trang sản phẩm:

```text
SLI người dùng: request thành công dưới 300 ms
Cache contract: giá không cũ quá 60 s
Dependency objective: Redis GET p99 dưới 5 ms
Fallback: đọc database có giới hạn concurrency
```

Dashboard Redis chỉ hữu ích khi nối được tới user journey và fallback tương ứng.

---

## 4. Mô hình quan sát nhiều lớp

```text
business outcome
  → endpoint/use case
  → cache policy
  → Redis client
  → TCP/TLS/DNS
  → Redis command/event loop
  → memory/persistence/replication
  → kernel/CPU/disk/network
```

Mỗi lớp cần owner, SLI, giới hạn và runbook riêng.

---

## 5. SLO nên đo điều gì?

Một bộ mục tiêu thực tế có thể gồm:

- tỷ lệ request ứng dụng thành công và đúng freshness;
- latency của cache operation ở phía client;
- tỷ lệ fallback thành công;
- replica lag hoặc failover time;
- headroom memory;
- durability gap cho workload có dữ liệu quan trọng.

Hit ratio là diagnostic indicator, không phải SLO người dùng.

---

## 6. Vẽ workload model trước dashboard

Ghi lại:

- lệnh chính: `GET`, `MGET`, `SET`, Lua, Streams;
- request rate và kích thước value;
- key distribution;
- TTL và invalidation;
- cache-aside hay write-through;
- standalone, Sentinel hay Cluster;
- persistence và replica;
- hành vi khi Redis chậm hoặc unavailable.

Không có workload model, cùng một con số memory hoặc latency có thể bị diễn giải ngược.

---

## 7. Hit ratio đúng công thức, chưa chắc đúng ý nghĩa

PromQL minh họa:

```promql
sum(rate(redis_keyspace_hits_total[5m]))
/
clamp_min(
  sum(rate(redis_keyspace_hits_total[5m]))
  + sum(rate(redis_keyspace_misses_total[5m])),
  1
)
```

Nhưng tỷ lệ toàn cluster che khuất:

- một tenant hoặc endpoint đang miss;
- key đắt tiền miss trong khi key rẻ hit;
- request không sử dụng lệnh lookup;
- cache trả dữ liệu stale;
- traffic giảm làm tỷ lệ dao động.

Nên bổ sung hit ratio ở application theo `cache`, `operation`, `result` với cardinality hữu hạn.

---

## 8. Phân loại cache miss

| Loại miss | Ý nghĩa | Hành động |
|---|---|---|
| compulsory | key chưa từng được cache | pre-warm nếu cần |
| expiration | TTL vừa hết | điều chỉnh TTL/jitter |
| eviction | thiếu memory | capacity/policy |
| invalidation | chủ động xóa | kiểm tra correctness |
| key mismatch | producer/consumer tạo key khác nhau | sửa contract |
| outage/bypass | client bỏ qua cache | điều tra dependency |

Một counter `miss` duy nhất không chỉ ra nguyên nhân.

---

## 9. Đo latency ở cả client và server

Client latency bao gồm:

```text
pool wait + DNS/TCP/TLS + network queue
+ Redis execution + response transfer + decode
```

Redis latency monitor và SLOWLOG chủ yếu giúp nhìn phía server. Nếu server báo nhanh nhưng
application báo chậm, hãy kiểm tra pool, network, retry, TLS và event loop của client.

---

## 10. Traffic và throughput

Theo dõi ít nhất:

- operations/second theo loại lệnh;
- bytes vào/ra;
- số connection và connection churn;
- request/value size ở application;
- pipeline batch size;
- traffic theo shard/instance.

Đừng dùng tổng OPS để suy ra tải CPU: một `GET` nhỏ và một Lua script dài có chi phí khác xa.

---

## 11. Error phải có taxonomy

Phân biệt:

- timeout;
- connection refused/reset;
- pool exhausted;
- authentication/TLS;
- `MOVED`/`ASK`;
- `READONLY`;
- OOM do `maxmemory`;
- command rejected;
- deserialize/schema;
- fallback failed.

Gộp tất cả thành `error=true` làm mất đường điều tra.

---

## 12. Command taxonomy

Nhóm lệnh theo hành vi:

| Nhóm | Ví dụ | Rủi ro |
|---|---|---|
| point lookup | `GET`, `HGET` | hot key |
| batch | `MGET`, pipeline | response lớn |
| write | `SET`, `HSET` | memory/replication |
| scan | `SCAN`, `HSCAN` | CPU kéo dài |
| blocking | `BLPOP`, Streams read | blocked clients |
| script/function | Lua/functions | giữ event loop |
| admin | persistence/config | blast radius lớn |

Không gắn raw command arguments vào metric hoặc span.

---

## 13. Instrument application trước

Application biết những điều Redis không biết:

- endpoint/use case;
- cache hit, miss, stale hay bypass;
- fallback latency;
- refresh kết quả gì;
- object schema/version;
- freshness thực tế;
- business cost của miss.

Counter gợi ý:

```text
cache_requests_total{
  cache="product",
  operation="read",
  result="hit|miss|stale|error|bypass"
}
```

Không dùng `key`, `user_id` hay URL đầy đủ làm label.

---

## 14. Trace cache operation

Span nên trả lời:

```text
request nào → cache operation nào → instance logic nào
→ mất bao lâu → hit/miss/error → có fallback không
```

Chỉ ghi thuộc tính theo OpenTelemetry Semantic Conventions mà thư viện đang dùng. Semantic
conventions có thể tiến hóa; pin version và kiểm thử telemetry contract khi nâng cấp.

---

## 15. Bảo vệ key và dữ liệu nhạy cảm

Key có thể chứa email, token, customer ID hoặc business secret. Quy tắc:

- không ghi raw key vào metric;
- không ghi command đầy đủ nếu chứa value;
- span/log chỉ chứa key pattern đã chuẩn hóa;
- hash không mặc nhiên là ẩn danh;
- áp dụng allowlist, redaction và retention;
- giới hạn quyền truy cập SLOWLOG, logs và traces.

---

## 16. Client pool là một hàng đợi

Theo dõi:

- active/idle/max connections;
- waiters và pool wait duration;
- acquire timeout;
- connection creation;
- broken/closed connections;
- event-loop/thread saturation.

Pool cạn làm client chậm trong khi Redis server vẫn nhàn.

---

## 17. Pipelining và batch

Pipeline giảm round trip nhưng tăng:

- burst CPU;
- response buffer;
- tail latency nếu batch lớn;
- blast radius khi timeout;
- khó attribution từng operation.

Đo batch size và tổng bytes. `MGET` 1.000 key không tương đương `GET` một key.

---

## 18. Timeout và retry budget

Thiết kế:

```text
user deadline
  > cache attempt
  + optional retry
  + fallback
  + response margin
```

Retry không giới hạn tạo retry storm. Với write, retry còn có thể lặp tác dụng nếu operation
không idempotent. Theo dõi `attempt`, `retry_reason` và remaining deadline ở application.

---

## 19. Cache stampede

Khi một key nóng hết TTL:

```text
10.000 request cùng miss
  → 10.000 query xuống database
  → database chậm
  → timeout/retry
  → toàn hệ thống quá tải
```

Biện pháp:

- request coalescing/single-flight;
- stale-while-revalidate;
- TTL jitter;
- refresh ahead;
- giới hạn fallback concurrency;
- circuit breaker và load shedding.

Quan sát miss spike cùng DB QPS, fallback concurrency và request latency.

---

## 20. Cache-aside

Luồng đọc:

```text
GET cache
  hit  → trả
  miss → đọc source → SET TTL → trả
```

Failure modes:

- database đọc thành công nhưng cache write thất bại;
- concurrent miss;
- source update và cache invalidation race;
- deserialize object phiên bản cũ.

Instrumentation phải bao phủ cả nhánh miss, không chỉ Redis span.

---

## 21. Write-through và write-behind

Write-through cập nhật source và cache trong một luồng logic nhưng không tự tạo atomicity.
Write-behind giảm latency write nhưng tăng durability và ordering risk.

Cần đo:

- queue depth/age;
- flush latency/error;
- retry/dead-letter;
- duplicate/out-of-order;
- data reconciliation gap.

Nếu mất Redis đồng nghĩa mất write chưa flush, đây không còn là cache thuần túy.

---

## 22. TTL là business decision

TTL cân bằng:

```text
TTL ngắn → dữ liệu mới hơn, miss/source load cao hơn
TTL dài  → hit cao hơn, stale lâu hơn, memory giữ lâu hơn
```

Ghi TTL theo data class, freshness contract và invalidation path. Không dùng một TTL mặc định
cho mọi đối tượng.

---

## 23. TTL jitter

Nếu hàng triệu key được tạo cùng lúc với TTL bằng nhau, chúng có thể hết hạn cùng lúc.

```text
effective_ttl = base_ttl ± bounded_random_jitter
```

Jitter phải nằm trong freshness contract. Theo dõi expiration rate và source-load spike để
chứng minh hiệu quả.

---

## 24. Negative caching

Cache “không tìm thấy” giúp giảm tải nguồn nhưng có thể che dữ liệu vừa được tạo.

Nên:

- dùng TTL ngắn hơn positive result;
- phân biệt `negative_hit`;
- invalidation khi create;
- không cache lỗi tạm thời như thể “không tồn tại”;
- theo dõi false-negative bằng reconciliation hoặc business signal.

---

## 25. Invalidation và correctness

Hai câu hỏi quan trọng:

1. Khi source thay đổi, cache biết bằng cách nào?
2. Trong bao lâu người dùng có thể thấy dữ liệu cũ?

Các pattern: delete-on-write, versioned key, CDC/event invalidation, write-through. Đo
invalidation delay, failure, consumer lag và freshness age; không chỉ đếm `DEL`.

---

## 26. `INFO` là điểm bắt đầu, không phải toàn bộ câu trả lời

`INFO` cung cấp các nhóm server, clients, memory, persistence, stats, replication, CPU,
command statistics, cluster và keyspace.

Lưu snapshot phục vụ điều tra nhưng:

- chọn section cần thiết;
- tránh scrape quá thường xuyên;
- hiểu counter reset khi process restart;
- không xem mọi field là SLI;
- so sánh với client/application telemetry.

---

## 27. Exporter contract

Exporter chuyển thông tin Redis thành Prometheus metrics. Cần kiểm soát:

- metric names/types/help;
- scrape duration/error;
- Redis permissions;
- command timeout;
- số instance và discovery;
- label `cluster`, `environment`, `instance`, `role`;
- compatibility khi nâng Redis/exporter.

Exporter down và Redis down phải là hai trạng thái phân biệt.

---

## 28. Quan sát chính exporter

Dashboard phải có:

- `up`;
- scrape duration;
- scrape/sample errors;
- target changes;
- exporter CPU/memory/restarts;
- missing series.

Nếu exporter timeout khi Redis quá tải, telemetry bị mất đúng lúc cần nhất. Cần alert theo
absence và kiểm tra chéo từ client.

---

## 29. Command statistics

Theo lệnh, xem:

- calls/second;
- cumulative execution time;
- error/rejected nếu collector cung cấp;
- latency client tương ứng.

Average server time che tail và network. Dùng commandstats để tìm thay đổi workload, không
thay histogram client-side.

---

## 30. Keyspace statistics

Theo dõi:

- keys theo database;
- keys có expiry;
- average TTL nếu có;
- hits/misses;
- expired/evicted keys.

Key count tăng không luôn xấu; điều đáng hỏi là growth có đúng với traffic/retention và còn
memory headroom không.

---

## 31. Giải thích hit/miss theo rate

Counter phải dùng `rate()` hoặc `increase()`:

```promql
sum by (instance) (rate(redis_keyspace_misses_total[5m]))
```

Tránh:

- nhìn giá trị counter tuyệt đối;
- tính ratio khi mẫu số gần 0;
- gộp instance vừa restart;
- alert chỉ vì ratio thấp khi traffic rất nhỏ.

Kết hợp điều kiện volume tối thiểu.

---

## 32. Bộ nhớ cần nhiều góc nhìn

Theo dõi:

- logical used memory;
- RSS;
- dataset/overhead;
- allocator active/resident nếu có;
- peak memory;
- `maxmemory`;
- fragmentation ratio;
- fork copy-on-write;
- cgroup/container limit.

Redis biết allocator; kernel/cgroup biết áp lực máy. Cần cả hai.

---

## 33. `used_memory` khác RSS

Khi xóa nhiều key, logical memory có thể giảm nhưng RSS chưa trả ngay cho OS do allocator,
fragmentation hoặc page behavior.

Không kết luận memory leak chỉ từ RSS. So sánh:

```text
used_memory ↓, RSS ngang → allocator/fragmentation có thể xảy ra
used_memory ↑, key count ↑ → dataset growth
RSS sát cgroup limit      → OOM risk dù maxmemory còn xa
```

---

## 34. Fragmentation

Fragmentation ratio cao có thể do dataset nhỏ, allocator hoặc churn; ratio thấp bất thường
kèm swap cũng nguy hiểm.

Điều tra:

- absolute bytes, không chỉ ratio;
- active defrag state;
- allocation churn;
- value-size distribution;
- RSS/cgroup pressure;
- latency trong lúc defrag.

Không restart production chỉ để “làm đẹp” ratio.

---

## 35. `maxmemory` và headroom

Redis còn cần memory ngoài dataset:

- client/output buffers;
- replication backlog;
- AOF rewrite/RDB fork COW;
- allocator overhead;
- module;
- kernel/page cache.

Do đó không đặt `maxmemory` bằng container/VM limit. Capacity test phải bao gồm persistence,
replication và traffic burst.

---

## 36. Eviction policy là semantics

Policy quyết định key nào bị loại khi đạt `maxmemory`: no-eviction, LRU/LFU/random/TTL trên
toàn bộ key hoặc tập có expiry, tùy cấu hình.

Chọn theo contract:

- cache thuần: eviction có thể chấp nhận;
- session/lock/state: eviction có thể thành correctness incident;
- mixed workload: tách instance thường an toàn hơn dùng một policy chung.

---

## 37. Eviction rate

```promql
sum by (instance) (rate(redis_evicted_keys_total[5m]))
```

Eviction là dấu hiệu pressure, nhưng impact phụ thuộc key bị đuổi. Correlate với:

- miss/fallback rate;
- database load;
- user latency/error;
- memory utilization;
- deploy hoặc traffic change.

Alert “eviction > 0” thường quá nhiễu cho cache được thiết kế để evict.

---

## 38. Expiration không phải eviction

- expiration: TTL đến hạn;
- eviction: Redis chủ động giải phóng memory theo policy.

Expiration spike có thể là thiết kế TTL đồng loạt. Eviction spike thường là capacity/policy.
Hai counter cần panel và runbook khác nhau.

---

## 39. Big keys

Big key gây:

- command latency dài;
- response/network burst;
- client buffer lớn;
- delete/frees tốn thời gian;
- shard imbalance.

Dò big key trên production phải incremental, có timeout/rate limit và theo replica phù hợp.
Ưu tiên telemetry value-size ngay lúc ghi thay vì quét toàn keyspace.

---

## 40. Hot keys

Hot key làm một shard, CPU hoặc network quá tải dù tổng cluster còn rảnh.

Dấu hiệu:

- OPS/CPU lệch giữa shard;
- latency chỉ ở một slot/instance;
- key pattern hoặc business entity chiếm traffic;
- replica/read distribution không đều.

Không đưa raw hot key vào label; ghi pattern/fingerprint được quản trị.

---

## 41. SLOWLOG

SLOWLOG ghi thời gian thực thi command phía Redis, không gồm network I/O tới client. Dùng để:

- nhận diện command tốn CPU;
- kiểm tra Lua/function;
- phát hiện batch/big key;
- nối thời điểm latency spike.

Giới hạn độ dài và ngưỡng phù hợp. Nội dung command có thể nhạy cảm; thu thập có kiểm soát.

---

## 42. Latency monitor và `LATENCY DOCTOR`

Latency monitor ghi các latency event nội bộ; `LATENCY DOCTOR` diễn giải và đưa gợi ý khi
monitor đã bật, có dữ liệu.

Nó là diagnostic assistant, không thay:

- client histogram;
- OS metrics;
- traces;
- kiểm chứng workload;
- capacity test.

---

## 43. Intrinsic latency

Máy ảo, hypervisor hoặc kernel scheduler tạo mức latency nền mà Redis không thể giảm.
So sánh intrinsic latency ở cùng host với observed latency để biết phần budget nằm ngoài
Redis command.

Đo cẩn thận: diagnostic CPU-intensive không nên chạy tùy tiện trên node production.

---

## 44. Event loop và lệnh chặn

Redis xử lý command theo mô hình khiến một công việc dài có thể trì hoãn công việc khác.
Nguồn thường gặp:

- big key;
- range quá rộng;
- Lua/function dài;
- cấu trúc dữ liệu khổng lồ;
- synchronous admin command;
- fork/OS stall.

P99 client tăng đồng loạt trong khi một command bất thường là tín hiệu head-of-line blocking.

---

## 45. CPU

Quan sát:

- process user/system CPU;
- CPU quota/throttling;
- host steal time;
- CPU theo shard;
- OPS và command mix;
- fork/child CPU.

CPU trung bình toàn máy che một Redis process hoặc một core bị bão hòa.

---

## 46. Network và client buffers

Theo dõi:

- bandwidth/packet/retransmit;
- connection backlog;
- input/output buffer;
- slow clients;
- response size;
- cross-zone latency;
- TLS handshake/churn.

Một consumer chậm có thể làm output buffer tăng và gây memory pressure.

---

## 47. Swap, THP, fork và copy-on-write

Các nguồn tail latency quan trọng:

- memory bị swap;
- Transparent Huge Pages;
- fork để RDB/AOF rewrite;
- copy-on-write khi write traffic cao;
- disk contention.

Correlate latency event với fork duration, child status, RSS, page faults và disk latency.
Thay kernel setting phải qua change management.

---

## 48. RDB persistence

RDB tạo snapshot theo thời điểm:

- compact và phù hợp backup/restore;
- có thể mất thay đổi sau snapshot gần nhất;
- fork/COW và I/O có thể ảnh hưởng latency;
- snapshot thành công không chứng minh restore được.

Theo dõi last save, save status/duration, fork và backup restore drill.

---

## 49. AOF persistence

AOF ghi lại write operations và có các policy fsync khác nhau. Quan sát:

- AOF enabled/status;
- fsync delay;
- rewrite in progress/duration;
- rewrite failures;
- file growth;
- disk space/latency;
- durability contract.

Rewrite có thể tăng memory và I/O; test với dataset và write rate thật.

---

## 50. Persistence là trade-off

```text
durability mạnh hơn
  ↔ nhiều fsync/I/O hơn
  ↔ latency và throughput có thể bị ảnh hưởng
```

Không tắt persistence chỉ để giảm latency nếu workload coi Redis là state. Nếu là cache tái
tạo được, chi phí warm-up và tải source sau restart vẫn phải được đo.

---

## 51. Replication lag

Redis replication mặc định bất đồng bộ. Theo dõi:

- link up/down;
- replica offset so với primary;
- seconds since interaction;
- replica apply/processing lag;
- backlog size;
- full/partial resync;
- read freshness ở application.

Một link “up” không chứng minh replica đã đủ mới cho read contract.

---

## 52. Partial và full resynchronization

Backlog còn đủ cho replica bắt kịp thì có thể partial resync. Nếu không, full resync tốn:

- primary fork/snapshot;
- network;
- replica load;
- thời gian;
- memory/disk.

Alert resync loop và capacity backlog dựa trên write rate × khoảng gián đoạn dự kiến.

---

## 53. Sentinel và failover

Quan sát:

- quorum/reachability;
- primary được nhận diện;
- failover start/end/failure;
- role change;
- client reconnect/discovery;
- write availability;
- duplicate/lost write theo contract.

Control-plane failover thành công nhưng client dùng endpoint cũ vẫn là user-visible incident.

---

## 54. Redis Cluster

Cluster chia keyspace thành hash slots. Dashboard cần:

- slot coverage/state;
- node role;
- shard memory/CPU/OPS;
- replica health;
- migration/import state;
- failover;
- cluster bus/network.

Aggregate toàn cluster dễ che một shard nóng hoặc thiếu replica.

---

## 55. Redirect và cluster-aware client

`MOVED` có thể xuất hiện khi topology thay đổi; `ASK` liên quan slot migration. Theo dõi:

- redirect rate;
- topology refresh;
- retry;
- connection per node;
- cross-slot error;
- request latency trong reshard/failover.

Redirect storm thường chỉ ra client discovery/cache topology không theo kịp.

---

## 56. Availability không đồng nghĩa zero data loss

Async replication có cửa sổ mất acknowledged write khi primary lỗi. Các cấu hình minimum
replicas có thể giới hạn rủi ro theo kiểu best effort nhưng không biến Redis thành hệ thống
strongly consistent.

Định nghĩa rõ:

- RPO/RTO;
- acknowledged nghĩa gì;
- stale read được phép bao lâu;
- khi partition chọn availability hay safety;
- cách reconcile sau failover.

---

## 57. Pub/Sub và Streams

Với Pub/Sub, quan sát subscriber count, publish rate, output buffer và disconnect; message
không được lưu như queue durable.

Với Streams, thêm:

- stream length/growth;
- consumer-group pending entries;
- oldest pending age;
- delivery/reclaim;
- lag;
- trim policy.

Đừng dùng hit ratio cho workload messaging.

---

## 58. ACL, TLS và security signals

Theo dõi có kiểm soát:

- authentication failures;
- denied commands/keys nếu audit source hỗ trợ;
- certificate expiry/handshake errors;
- ACL/config changes;
- public exposure;
- privileged/admin access.

Metric/log không được làm lộ password, token, command value hoặc raw key.

---

## 59. Dashboard theo câu hỏi

Một dashboard điều hành tốt:

```text
1. User impact: latency/error/freshness
2. Cache effectiveness: hit/miss/stale/fallback
3. Saturation: memory/CPU/network/pool
4. Redis internals: commands/latency/eviction
5. Topology: roles/lag/shards/failover
6. Persistence: RDB/AOF/disk
7. Changes: deploy/config/traffic
```

Có link từ overview xuống instance/shard/client và runbook.

---

## 60. Alert theo triệu chứng và rủi ro

Các alert đáng cân nhắc:

- user SLO burn rate;
- cache error/fallback làm source quá tải;
- memory headroom thấp;
- unexpected eviction cho workload không cho phép;
- replica link/lag vượt freshness;
- persistence failure theo durability contract;
- exporter/telemetry mất;
- shard imbalance kéo dài.

Alert phải có owner, severity, duration, dependency context và hành động.

---

## 61. Incident workflow

```text
1. Xác nhận user impact và phạm vi
2. Kiểm tra deploy/config/traffic gần nhất
3. So client latency với Redis/server latency
4. Kiểm tra pool, error, timeout, retry
5. Kiểm tra memory, eviction, CPU, network
6. Kiểm tra slowlog/latency event an toàn
7. Kiểm tra replication/persistence/topology
8. Giảm tải có giới hạn, ghi timeline và evidence
```

Không xóa cache toàn bộ như phản xạ đầu tiên: cold-cache storm có thể làm sự cố nặng hơn.

---

## 62. Capacity và load test

Test phải giữ được:

- key/value distribution;
- hot-key skew;
- read/write ratio;
- TTL/expiration waves;
- client count/pipeline;
- persistence/replication;
- failover và warm-up;
- source capacity khi miss.

Đầu ra là safe operating envelope, không chỉ “max OPS”.

---

## 63. Failure-mode và chaos test

Thử trong môi trường kiểm soát:

- Redis timeout/unavailable;
- packet loss/latency;
- replica disconnect;
- failover;
- memory pressure/eviction;
- disk chậm hoặc đầy;
- exporter mất;
- cache flush/cold start;
- hot key và TTL wave.

Đo xem fallback, load shedding, alert và runbook có hoạt động trước khi thử production.

---

## 64. Workshop, checklist và câu hỏi ôn tập

### Workshop

1. Chọn một endpoint dùng cache.
2. Vẽ hit/miss/fallback và correctness contract.
3. Tạo application metrics không có high-cardinality key.
4. Dựng dashboard theo section 59.
5. Mô phỏng TTL wave hoặc Redis latency.
6. Xác nhận alert chỉ ra user impact và nguyên nhân gần nhất.

### Checklist production

- [ ] Vai trò Redis và RPO/RTO được ghi rõ.
- [ ] Client latency, error, pool và retry được quan sát.
- [ ] Hit/miss có business context.
- [ ] Freshness/invalidation có SLI.
- [ ] Memory có headroom ngoài dataset.
- [ ] Eviction policy đúng workload.
- [ ] Replication/persistence có runbook.
- [ ] Raw key/value không vào telemetry.
- [ ] Dashboard có owner và change annotations.
- [ ] Restore/failover/cold-start đã được diễn tập.

### Câu hỏi

1. Vì sao hit ratio cao vẫn có thể là sự cố?
2. Client latency khác Redis execution time ở đâu?
3. Expiration khác eviction thế nào?
4. Vì sao `maxmemory` không nên bằng container limit?
5. Khi nào RSS cao không phải memory leak?
6. Cache stampede hình thành ra sao?
7. SLOWLOG không bao gồm phần latency nào?
8. Full resync ảnh hưởng primary thế nào?
9. Async replication tạo consistency risk gì?
10. Vì sao không đưa raw key vào metric?
11. Khi nào Redis đã trở thành source of truth?
12. Cold-cache storm cần được diễn tập thế nào?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Redis

- [Redis `INFO`](https://redis.io/docs/latest/commands/info/)
- [Redis SLOWLOG GET](https://redis.io/docs/latest/commands/slowlog-get/)
- [Redis LATENCY DOCTOR](https://redis.io/docs/latest/commands/latency-doctor/)
- [Redis latency diagnosis](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency/)
- [Redis memory optimization](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/memory-optimization/)
- [Redis key eviction](https://redis.io/docs/latest/develop/reference/eviction/)
- [Redis persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/)
- [Redis replication](https://redis.io/docs/latest/operate/oss_and_stack/management/replication/)
- [Redis Cluster scaling](https://redis.io/docs/latest/operate/oss_and_stack/management/scaling/)
- [Redis administration](https://redis.io/docs/latest/operate/oss_and_stack/management/admin/)

### Observability

- [Prometheus metric and label naming](https://prometheus.io/docs/practices/naming/)
- [Prometheus instrumentation](https://prometheus.io/docs/practices/instrumentation/)
- [OpenTelemetry database semantic conventions](https://opentelemetry.io/docs/specs/semconv/db/)

Chủ đề tiếp theo:
[Kubernetes Observability Deep Dive](kubernetes_observability.md) – control plane, node,
workload state, resource signals, Events, logs, traces, audit và multi-cluster operations.

---

*Cập nhật lần cuối: 2026-07-30*
