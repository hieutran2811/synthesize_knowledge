---
title: "Continuous Profiling – CPU, Memory, Flame Graph, Pyroscope và Parca"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 27
---
# Continuous Profiling – CPU, Memory, Flame Graph, Pyroscope và Parca

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là hiểu profiling như một signal observability trong production: đo đúng loại tài nguyên, đọc đúng flame graph, chọn collector phù hợp và correlation với metrics/traces. Baseline tham chiếu: **Grafana Pyroscope 2.2.x**, **async-profiler 4.5**, **Parca 0.28.x** và **OpenTelemetry Profiles public Alpha**.

---

## 1. Profiling trả lời câu hỏi gì?

Metrics thường nói:

```text
checkout CPU tăng từ 40% lên 85%
```

Trace nói:

```text
request checkout chậm ở span calculatePrice
```

Profile đi sâu thêm:

```text
calculatePrice
  └── PromotionEngine.evaluate
      └── RegexMatcher.match
          └── Pattern.compile
```

Nói ngắn gọn:

- metric cho biết **có vấn đề gì và khi nào**;
- trace cho biết **request đi qua đâu**;
- profile cho biết **dòng code hoặc call stack nào tiêu tài nguyên**;
- log cung cấp **sự kiện và context chi tiết**.

Profiling không thay metric, trace hoặc log. Nó bổ sung chiều nhìn ở cấp code.

---

## 2. Traditional profiling và continuous profiling

Profiling truyền thống thường là:

```text
thấy sự cố
  → attach profiler
  → ghi 30–60 giây
  → phân tích file
```

Vấn đề là sự cố có thể đã biến mất trước khi profiler được bật.

Continuous profiling:

```text
application chạy
  → lấy stack sample liên tục
  → gắn timestamp + metadata
  → gửi về profile backend
  → query lại bất kỳ khoảng thời gian nào còn retention
```

Hai chiều bổ sung quan trọng:

- **time**: xem profile tại thời điểm sự cố trong quá khứ;
- **metadata**: lọc theo service, version, environment, pod hoặc region.

---

## 3. Profiling không phải tracing

Trace quan sát một request logic:

```text
request A
  → span server
  → span database
```

Profiler thường lấy sample của toàn process:

```text
10:00:00.010 thread-1 stack X
10:00:00.020 thread-7 stack Y
10:00:00.030 GC thread stack Z
```

Profiler không tự biết sample thuộc request nào nếu không có cơ chế correlation.

Vì thế:

- continuous profile cho bức tranh thống kê của process;
- span profile cố gắng gắn sample với trace/span context;
- span quá ngắn có thể không được profiler sample lần nào.

---

## 4. Mental model: profiler là máy ảnh chụp stack

Sampling profiler định kỳ nhìn vào call stack:

```text
Sample 1:
main → handle → calculate → regex

Sample 2:
main → handle → calculate → regex

Sample 3:
main → handle → databaseWait
```

Sau khi aggregate:

```text
regex        2 samples
databaseWait 1 sample
```

Nếu sample rate là 100 Hz thì profiler cố lấy khoảng 100 sample mỗi giây, tương đương interval xấp xỉ 10 ms.

Đây là ước lượng thống kê, không phải đồng hồ đo chính xác từng nanosecond của từng method.

---

## 5. Sampling và instrumentation-based profiling

### Sampling-based

Profiler định kỳ lấy stack:

- overhead thường thấp;
- phù hợp chạy liên tục;
- operation rất ngắn có thể bị bỏ lỡ;
- kết quả mang tính thống kê.

### Instrumentation-based

Runtime hook hoặc bytecode/native instrumentation ghi event:

- allocation;
- lock acquisition;
- exception;
- GC event.

Nó có thể cung cấp sự kiện chi tiết hơn nhưng overhead phụ thuộc:

- event frequency;
- stack depth;
- threshold;
- số thread;
- cách buffer/export.

Một hệ thống profiling production thường kết hợp cả hai.

---

## 6. Sample rate và độ phân giải

Sample rate cao:

- bắt được code path ngắn hơn;
- nhiều sample hơn;
- profile chi tiết hơn;
- CPU, memory và network overhead cao hơn.

Sample rate thấp:

- rẻ hơn;
- phù hợp toàn fleet;
- dễ bỏ lỡ short-lived operation;
- cần window dài hơn để đủ statistical confidence.

Quan hệ gần đúng:

```text
samples ≈ sample_rate × duration × số target đang chạy
```

Không tăng sample rate chỉ vì flame graph “chưa đẹp”. Trước tiên hãy tăng time window và kiểm tra symbolization.

---

## 7. Observer effect

Profiler cũng tiêu tài nguyên:

- interrupt/timer;
- stack walking;
- symbol lookup;
- aggregation;
- buffer;
- compression;
- upload.

Do đó profiler có thể ảnh hưởng chính application đang đo.

Production rollout phải đo:

```text
CPU before/after
memory before/after
p50/p95/p99 latency before/after
GC before/after
network egress
profile drop/error
```

Không dùng một con số overhead quảng cáo làm SLO cho mọi workload. Overhead thật phụ thuộc application và cấu hình.

---

## 8. Các loại profile chính

| Profile type | Đo gì? | Câu hỏi chính |
|---|---|---|
| CPU | Thời gian thực thi trên CPU | Code nào đốt CPU? |
| Wall | Thời gian trôi qua, gồm cả chờ | Thread chậm vì chạy hay vì đợi? |
| Allocation | Object/byte được cấp phát | Code nào tạo nhiều rác? |
| In-use/heap | Object/byte còn sống | Memory đang được giữ ở đâu? |
| Lock | Contention và thời gian chờ lock | Thread tranh lock ở đâu? |
| Block | Thời gian block | Goroutine/thread bị chặn ở đâu? |
| Native memory | Native allocation | Off-heap/native memory đi đâu? |
| Exception | Exception event | Exception nào phát sinh nhiều? |

Instrumentation method và language quyết định profile type nào thật sự khả dụng.

---

## 9. CPU profile

CPU profile quan sát code đang thực thi trên CPU.

Phù hợp khi:

- process CPU cao;
- throughput giảm vì compute;
- code regression sau deploy;
- serialization, compression, regex hoặc crypto tốn CPU;
- GC/JIT/native code chiếm CPU.

CPU profile không thể hiện đầy đủ:

- network wait;
- database wait;
- sleep;
- thread đợi lock;
- queue wait.

Nếu request chậm nhưng CPU profile gần trống, hãy xem wall profile hoặc trace.

---

## 10. Wall-clock profile

Wall profile quan sát elapsed time:

```text
on-CPU
  +
off-CPU: sleep, I/O wait, lock wait, scheduling
```

Phù hợp khi:

- latency cao nhưng CPU thấp;
- thread pool bị nghẽn;
- downstream/network chậm;
- lock contention;
- blocking call trong reactive application.

Wall profile có thể chứa rất nhiều idle/sleep stack. Cần:

- lọc thread;
- bật per-thread grouping khi phù hợp;
- kết hợp trace và metric;
- không mặc định thanh rộng là code cần tối ưu CPU.

---

## 11. Allocation profile

Allocation profile đo nơi object được tạo:

```text
JSON parser → new char[]
mapper      → new DTO
formatter   → new String
```

Nó giúp tìm:

- allocation rate cao;
- GC pressure;
- temporary object;
- boxing;
- copy buffer/string;
- collection resize.

Allocation nhiều không đồng nghĩa memory leak.

Object có thể:

```text
allocate rất nhiều
  → chết nhanh
  → tạo GC pressure
  → không làm heap retained tăng lâu dài
```

---

## 12. In-use, live và heap profile

Profile retained/live trả lời:

```text
object nào vẫn còn được giữ?
```

Nó gần bài toán memory leak hơn allocation profile.

Phân biệt:

- **allocated bytes**: tổng byte từng được cấp phát;
- **in-use bytes**: byte còn được xem là đang sống tại thời điểm quan sát;
- **live objects**: sample object chưa bị GC;
- **heap dump**: snapshot chi tiết object graph.

Continuous heap profile không thay heap dump khi cần:

- reference chain;
- dominator tree;
- GC root;
- exact object inventory.

Nó giúp thu hẹp service/version/time range trước khi lấy dump nặng hơn.

---

## 13. Lock contention profile

Lock profile cho biết:

- lock nào bị tranh chấp;
- call stack đi tới lock;
- số lần contention;
- thời gian chờ.

Ví dụ:

```text
CheckoutService.process
  → PriceCache.get
    → synchronized
```

Không tối ưu chỉ vì thấy `synchronized`.

Cần xác nhận:

- contention có nằm trên critical path không;
- lock duration có đáng kể không;
- thay lock có phá correctness không;
- vấn đề thật là critical section quá dài hay thread count quá lớn.

---

## 14. Native memory và hardware events

Một số profiler như async-profiler có thể đo:

- native allocation;
- page faults;
- context switches;
- cache misses;
- hardware/software counters.

Những profile này phụ thuộc:

- operating system;
- CPU;
- kernel;
- quyền `perf_event`;
- symbol/debug information;
- profiler version.

Không xem native memory profile như phép thay thế hoàn toàn cho:

- Native Memory Tracking;
- allocator statistics;
- `pmap`;
- cgroup memory;
- RSS/PSS;
- memory pressure metrics.

---

## 15. Chọn profile theo triệu chứng

| Triệu chứng | Bắt đầu với | Kết hợp |
|---|---|---|
| CPU cao | CPU profile | CPU metrics, throttling |
| Latency cao, CPU thấp | Wall profile | Trace, downstream metrics |
| GC cao | Allocation profile | GC log/JFR, heap metrics |
| RSS tăng nhưng heap ổn | Native memory | NMT, cgroup metrics |
| Thread pool nghẽn | Wall + lock | Queue/thread metrics |
| Sau deploy chậm | Diff CPU/wall | version label, trace |
| OOM | In-use/live + allocation | heap dump, OOM log |
| Một endpoint chậm | Span profile | Tempo trace |

Chọn đúng profile type quan trọng hơn tăng sample rate.

---

## 16. Stack trace và folded format

Một stack:

```text
main
  → checkout
    → calculate
      → regex
```

Folded/collapsed format có thể biểu diễn:

```text
main;checkout;calculate;regex 42
main;checkout;database 10
```

Con số cuối là sample/value aggregate của stack.

Folded format:

- đơn giản;
- dễ sinh flame graph;
- không mang đầy đủ metadata/event type như JFR hoặc pprof;
- có thể làm mất chi tiết cần cho multi-event analysis.

---

## 17. Đọc flame graph

Quy tắc quan trọng nhất:

- chiều ngang biểu diễn tỷ lệ resource;
- frame càng rộng thì càng nhiều sample/value;
- chiều dọc biểu diễn quan hệ call stack;
- frame cha gọi frame con;
- màu thường chỉ để phân biệt, trừ khi UI đang hiển thị diff/semantics riêng.

Tìm:

- “plateau” rộng ở gần leaf;
- function có self cao;
- call path mới xuất hiện sau deploy;
- library không mong đợi;
- runtime/native frame bất thường.

Đừng tối ưu function chỉ vì tên trông đáng ngờ. Hãy xem width và self/total.

---

## 18. Trục ngang không phải timeline

Trong flame graph aggregate:

```text
trái ─────────────── phải
```

thường không có nghĩa:

```text
sớm ─────────────── muộn
```

Các stack giống nhau được gộp và sắp xếp để dễ đọc.

Muốn biết thời gian:

- chọn time range;
- dùng timeline/heatmap;
- zoom interval sự cố;
- so sánh before/after;
- correlation với metric/trace timestamp.

Nhầm trục ngang thành timeline là lỗi đọc flame graph phổ biến.

---

## 19. Self và Total

**Self**:

```text
resource tiêu trực tiếp trong function
```

**Total**:

```text
self của function + resource trong toàn bộ function con
```

Ví dụ:

```text
checkout             total 80%, self 2%
└── calculatePrice   total 60%, self 5%
    └── regex        total 55%, self 55%
```

Diễn giải:

- `checkout` bao phủ phần lớn workload nhưng bản thân không nóng;
- `regex` là nơi CPU trực tiếp bị tiêu;
- tối ưu wrapper `checkout` có thể không giúp.

---

## 20. Flame graph và top table

Flame graph tốt để thấy call hierarchy.

Top table tốt để:

- sort theo self;
- sort theo total;
- tìm function nóng xuyên nhiều call path;
- xem exact value;
- search symbol.

Workflow:

```text
top table tìm suspect
  → flame graph xem call path
  → source view xem line
  → diff xác nhận regression
```

Chỉ dùng top table có thể bỏ lỡ context cha gọi function.

---

## 21. Diff profile

Diff so sánh:

```text
baseline
    với
comparison
```

Ví dụ:

- version `1.4.2` và `1.4.3`;
- trước và sau incident;
- region A và B;
- canary và stable;
- tenant tier khác nhau.

Màu trong diff phụ thuộc UI. Luôn đọc legend.

Diff theo **tỷ lệ** có thể gây hiểu nhầm:

- function tăng tỷ lệ vì function khác giảm;
- tổng workload hai bên khác nhau;
- sample count quá ít;
- traffic mix khác.

Cần so cả absolute value, sample count và workload.

---

## 22. Icicle, call tree và sandwich view

Các UI có thể hiển thị:

- flame graph;
- icicle graph;
- call tree;
- callers/callees;
- sandwich view;
- table;
- heatmap.

Orientation có thể đảo:

```text
root ở dưới hoặc root ở trên
```

Không ghi nhớ máy móc “leaf luôn ở trên”. Hãy dựa vào:

- breadcrumb;
- parent/child;
- tooltip;
- self/total;
- legend.

---

## 23. Các pattern thường gặp

### Serialization nóng

```text
controller → mapper → JSON encode
```

### Regex compile lặp

```text
request → Pattern.compile
```

### Collection resize

```text
ArrayList.grow / HashMap.resize
```

### Lock contention

```text
cache → synchronized → park
```

### Blocking trong reactive

```text
event loop → blocking JDBC/file/network
```

### GC/JIT overhead

```text
GC thread / compiler thread / runtime stub
```

Pattern là điểm bắt đầu điều tra, không phải kết luận tự động.

---

## 24. Symbolization

Raw sample có thể chỉ chứa address:

```text
0x7f31a2...
```

Symbolizer chuyển thành:

```text
package.Class.method
file.java:123
```

Thiếu symbol dẫn đến:

- `[unknown]`;
- hex address;
- native frame khó hiểu;
- line number không có;
- diff không ổn định giữa build.

Symbolization cần:

- build ID;
- symbol table;
- debug info khi cần line-level;
- JIT metadata cho managed runtime;
- quyền đọc executable/map;
- cache đủ dung lượng.

---

## 25. Build ID và debug information

Native binary production thường strip debug info để giảm kích thước.

Giải pháp:

```text
production binary có build ID
        │
        ▼
debug artifact store / debuginfod
        │
        ▼
symbolizer tìm đúng symbol theo build ID
```

Pipeline build nên:

1. giữ build ID ổn định;
2. upload debug info cùng release;
3. gắn `service.version`/commit;
4. áp access control;
5. retention debug artifact dài ít nhất bằng profile retention cần điều tra.

Binary và debug info sai version tạo symbol sai còn nguy hiểm hơn không có symbol.

---

## 26. Identity trong container và Kubernetes

Profile cần được gắn đúng:

```text
service
namespace
pod
container
node
cluster
version
environment
```

PID không đủ vì:

- PID được tái sử dụng;
- host PID khác container PID;
- pod restart tạo process mới;
- nhiều container trong một pod.

Identity phải đồng bộ với metric/trace:

```text
OTel service.name      ↔ profile service_name
service.version        ↔ version label
deployment environment ↔ environment label
```

Nếu vocabulary lệch, correlation trở thành nối chuỗi thủ công.

---

## 27. Profile label contract

Một contract đơn giản:

| Label | Ví dụ | Cardinality |
|---|---|---|
| `service_name` | `checkout` | Thấp |
| `service_namespace` | `commerce` | Thấp |
| `environment` | `production` | Rất thấp |
| `region` | `ap-southeast-1` | Thấp |
| `cluster` | `prod-bkk` | Thấp |
| `version` | `2026.07.29-8f2c1a` | Có giới hạn |
| `pod` | `checkout-abc-1` | Trung bình |

Chỉ thêm label nếu có query/use case.

Tên profile service phải ổn định qua replica. Không dùng pod name làm service name.

---

## 28. Cardinality trong profiling

Profile series được chia theo label set.

Nếu thêm:

```text
user_id
trace_id
request_id
order_id
```

vào static series labels, số series có thể tăng theo số request.

Hậu quả:

- nhiều profile fragment nhỏ;
- compression kém;
- index lớn;
- query fan-out;
- storage và object operations tăng;
- UI khó sử dụng.

Trace/span correlation phải dùng cơ chế chuyên biệt, không biến trace ID thành label series phổ thông.

---

## 29. Privacy và security

Profile có thể lộ:

- package/class/function name;
- repository path;
- library/version;
- tenant naming;
- infrastructure topology;
- dynamic label;
- nội dung symbol tự đặt.

Không đưa vào label:

- token;
- password;
- email;
- raw URL có ID;
- SQL/payload;
- customer name nếu chưa có policy.

Profile backend cần:

- TLS;
- authentication;
- authorization;
- tenant isolation;
- network policy;
- encrypted object storage;
- access audit;
- retention/deletion policy.

---

## 30. Các cách thu thập profile

| Cách | Ưu điểm | Hạn chế |
|---|---|---|
| In-process SDK/agent | Runtime semantics tốt, nhiều profile type | Phải thêm/attach agent |
| Runtime endpoint, ví dụ pprof | Native với runtime | Cần expose/scrape endpoint |
| Host agent/eBPF | Không sửa app, toàn fleet | Linux/privilege/symbolization |
| On-demand profiler | Chi tiết khi cần | Dễ bỏ lỡ sự cố quá khứ |
| JFR continuous | JVM event phong phú | Cần quản lý file/export |

Một organization có thể dùng:

```text
eBPF CPU baseline toàn fleet
  +
language profiler cho service quan trọng
  +
on-demand deep profile khi incident
```

---

## 31. In-process profiler và eBPF profiler

### In-process

- hiểu runtime tốt;
- allocation/lock/exception phong phú;
- dynamic span labels dễ hơn;
- ảnh hưởng trực tiếp process;
- cần version compatibility.

### eBPF

- quan sát nhiều process từ host;
- không cần restart/instrument application;
- mixed user/kernel/native stack;
- cần Linux kernel và quyền mạnh;
- profile type thường thiên về CPU/off-CPU;
- HLL/JIT symbolization phức tạp.

Không có lựa chọn tuyệt đối tốt hơn. Chọn theo use case và security boundary.

---

## 32. Continuous và on-demand nên cùng tồn tại

Continuous profile:

- độ phân giải vừa phải;
- chi phí được budget;
- retention nhiều ngày;
- phù hợp incident history và regression.

On-demand profile:

- sample rate cao hơn;
- event chi tiết;
- duration ngắn;
- chỉ bật cho target cụ thể;
- phù hợp deep investigation.

Mô hình:

```text
continuous phát hiện hot path
  → canary/on-demand xác nhận chi tiết
  → benchmark fix
  → continuous diff xác nhận production
```

---

## 33. Java Flight Recorder

JFR là cơ chế event recording tích hợp trong JDK.

Nó có thể thu:

- CPU sample;
- allocation;
- GC;
- lock;
- thread;
- I/O;
- class loading;
- JIT;
- custom JFR event.

Hai cấu hình chuẩn:

- `default.jfc`: cân bằng dữ liệu/overhead, phù hợp continuous recording;
- `profile.jfc`: chi tiết hơn, dùng cho profiling ngắn hạn.

Không sửa trực tiếp file template trong JDK. Tạo custom copy nếu cần.

Xem thêm phần Java chuyên sâu tại [performance_tuning.md](../../java/core/performance_tuning.md).

---

## 34. JFR continuous recording

Khởi động cùng JVM:

```bash
java \
  -XX:StartFlightRecording=name=continuous,settings=default,disk=true,maxage=6h,maxsize=512m \
  -jar app.jar
```

Start trên process đang chạy:

```bash
jcmd <pid> JFR.start \
  name=continuous \
  settings=default \
  disk=true \
  maxage=6h \
  maxsize=512m
```

Dump 15 phút gần nhất:

```bash
jcmd <pid> JFR.dump \
  name=continuous \
  maxage=15m \
  filename=/tmp/incident.jfr
```

`jcmd` cần chạy cùng host và effective user/group phù hợp với JVM.

---

## 35. async-profiler

async-profiler là sampling profiler cho HotSpot JVM, có thể quan sát:

- CPU;
- Java heap allocation;
- native memory;
- contended locks;
- hardware/software counters;
- Java, native và kernel frames.

Baseline hiện tại là 4.5.

Nó được thiết kế để tránh safepoint bias của nhiều profiler Java truyền thống.

Điều đó không có nghĩa mọi môi trường đều cho stack hoàn hảo. Cần test:

- JDK distribution;
- glibc/musl;
- container privileges;
- kernel/perf configuration;
- optimized/inlined frames.

---

## 36. async-profiler commands

CPU:

```bash
asprof -d 30 -e cpu -f cpu.html <pid>
```

Wall:

```bash
asprof -d 30 -e wall -f wall.html <pid>
```

Allocation:

```bash
asprof -d 30 -e alloc -f alloc.html <pid>
```

Lock:

```bash
asprof -d 30 -e lock -f lock.html <pid>
```

Chạy `asprof --help` của đúng binary version trước khi automation vì option/output format có thể thay đổi.

Không ghi profile chứa thông tin nhạy cảm vào thư mục world-readable.

---

## 37. `DebugNonSafepoints`

Một số Java profiling setup khuyến nghị:

```text
-XX:+UnlockDiagnosticVMOptions
-XX:+DebugNonSafepoints
```

Mục tiêu là cải thiện thông tin debug cho optimized/inlined code ở các vị trí không phải safepoint.

Trade-off:

- tăng metadata/code cache footprint;
- cần đo overhead;
- behavior phụ thuộc JDK/profiler;
- không tự động sửa mọi unknown frame.

Với Alloy `pyroscope.java`, tài liệu hiện tại khuyến nghị hai flag này để tăng độ chính xác, đặc biệt với inlined methods.

---

## 38. Pyroscope Java agent

Pyroscope Java integration dùng async-profiler và có thể chạy:

- từ application code;
- dưới dạng `javaagent`.

Dependency example hiện tại:

```xml
<dependency>
    <groupId>io.pyroscope</groupId>
    <artifactId>agent</artifactId>
    <version>2.5.4</version>
</dependency>
```

Không copy version này mãi mãi. Quản lý bằng dependency policy và kiểm tra release/security compatibility.

Java agent:

```bash
java -javaagent:/opt/pyroscope/pyroscope.jar -jar app.jar
```

---

## 39. Cấu hình Pyroscope Java

Ví dụ:

```bash
export PYROSCOPE_APPLICATION_NAME=checkout
export PYROSCOPE_SERVER_ADDRESS=https://profiles.example.com
export PYROSCOPE_FORMAT=jfr
export PYROSCOPE_PROFILING_INTERVAL=10ms
export PYROSCOPE_PROFILER_EVENT=itimer
export PYROSCOPE_PROFILER_ALLOC=512k
export PYROSCOPE_PROFILER_LOCK=10ms
export PYROSCOPE_UPLOAD_INTERVAL=10s
export PYROSCOPE_LABELS="service_namespace=commerce,environment=production,version=2026.07.29"
```

Secret không hard-code trong image hoặc Git:

```text
PYROSCOPE_BASIC_AUTH_PASSWORD
```

phải đến từ secret manager/runtime secret.

---

## 40. Allocation và lock threshold

Sai nguy hiểm:

```bash
PYROSCOPE_PROFILER_ALLOC=0
PYROSCOPE_PROFILER_LOCK=0
```

Giá trị `0` có thể ghi mọi event, gây overhead CPU/network lớn và không phù hợp continuous production mặc định.

Điểm bắt đầu được tài liệu Java hiện tại gợi ý:

```text
allocation threshold = 512k
lock threshold       = 10ms
```

Sau đó tune theo:

- allocation rate;
- lock duration distribution;
- overhead;
- số sample;
- câu hỏi điều tra.

Threshold là sampling control, không phải “bỏ qua lỗi”.

---

## 41. Grafana Alloy profile Java

Alloy có component `pyroscope.java` để attach async-profiler vào Java process trên local Linux host.

Ví dụ khái niệm:

```alloy
discovery.process "all" {
}

discovery.relabel "java" {
  targets = discovery.process.all.targets

  rule {
    action        = "keep"
    source_labels = ["__meta_process_exe"]
    regex         = ".*/java$"
  }

  rule {
    action       = "replace"
    target_label = "service_name"
    replacement  = "checkout"
  }
}

pyroscope.java "java" {
  targets    = discovery.relabel.java.output
  forward_to = [pyroscope.write.backend.receiver]

  profiling_config {
    interval    = "60s"
    event       = "itimer"
    sample_rate = 100
    alloc       = "512k"
    lock        = "10ms"
  }
}

pyroscope.write "backend" {
  endpoint {
    url = "https://profiles.example.com"
  }
}
```

Production cần discovery/relabel theo Kubernetes/container metadata thay vì hard-code mọi target thành cùng service.

---

## 42. Grafana Alloy eBPF profiling

`pyroscope.ebpf` profile process trên current host.

Ví dụ tối giản:

```alloy
pyroscope.ebpf "local_pods" {
  targets    = discovery.relabel.local_pods.output
  forward_to = [pyroscope.write.backend.receiver]
  sample_rate = 19
}

pyroscope.write "backend" {
  endpoint {
    url = "https://profiles.example.com"
  }
}
```

Component hiện tại:

- hỗ trợ native code và nhiều high-level runtime;
- cần target chứa container ID hoặc process PID;
- yêu cầu `service_name`;
- mặc định sample rate 19 Hz;
- cần symbol cache tại `/tmp/symb-cache`.

---

## 43. eBPF privilege là security decision

Cách dễ nhất trong Kubernetes thường là:

```yaml
securityContext:
  privileged: true
```

Nhưng đây là quyền rất lớn.

Least-privilege setup có thể cần các capability như:

```text
BPF
PERFMON
SYS_PTRACE
CHECKPOINT_RESTORE
SYS_RESOURCE
DAC_READ_SEARCH
SYSLOG
```

và host PID namespace, kernel tracing filesystem mount.

Yêu cầu thay đổi theo:

- kernel;
- container runtime;
- distribution;
- profiler component.

Security team phải review. Không copy `privileged: true` như một chi tiết triển khai vô hại.

---

## 44. Parca

Parca là hệ thống continuous profiling open source.

Baseline hiện tại:

```text
Parca 0.28.x
```

Điểm mạnh:

- eBPF profiler toàn infrastructure;
- pprof format;
- label-based search;
- compare profile theo time/label;
- native symbolization và debuginfo workflow;
- CPU/memory analysis theo line khi symbol đầy đủ.

Parca phù hợp để đánh giá khi:

- ưu tiên eBPF;
- muốn open format;
- muốn profile native/mixed fleet;
- chấp nhận vận hành ecosystem Parca riêng.

---

## 45. Pyroscope và Parca

| Tiêu chí | Pyroscope | Parca |
|---|---|---|
| Backend | Pyroscope | Parca |
| Grafana integration | Native/mạnh | Có datasource/plugin ecosystem |
| SDK language | Nhiều SDK | Thường tận dụng pprof/eBPF |
| eBPF | Qua Alloy/OTel-derived profiler | Parca Agent/eBPF |
| Storage/query | Pyroscope v2 architecture | Parca storage/query engine |
| Trace-profile integration | Span Profiles/Tempo | Cần đánh giá theo stack |
| Format | pprof/JFR/ingest/OTLP đang phát triển | pprof và OTel profile support đang tiến triển |

Chọn bằng proof of concept:

- language coverage;
- symbol quality;
- overhead;
- query UX;
- retention/cost;
- HA;
- security;
- correlation.

Không chọn chỉ vì screenshot flame graph đẹp.

---

## 46. pprof, JFR, folded và OTLP Profiles

| Format | Điểm mạnh | Hạn chế |
|---|---|---|
| pprof | Phổ biến, structured, nhiều tool | Semantics phụ thuộc producer |
| JFR | JVM multi-event phong phú | Java/JDK-specific |
| Folded | Đơn giản, dễ flame graph | Ít metadata |
| OTLP Profiles | Chuẩn cross-language hướng tới tương lai | Hiện còn Alpha/development |

Format không tự bảo đảm:

- symbol đúng;
- labels đúng;
- unit đúng;
- profile type tương thích;
- backend hiểu mọi field.

Luôn test producer → transport → backend → query.

---

## 47. OpenTelemetry Profiles đang ở đâu?

OpenTelemetry Profiles đã vào **public Alpha** trong năm 2026.

Hiện tại:

- data model và protocol đang phát triển;
- profile có thể correlation với trace/span;
- OTel eBPF profiler hỗ trợ whole-system Linux profiling;
- client/Collector/backend support chưa đồng đều;
- breaking change vẫn có thể xảy ra.

Không suy ra rằng Collector 0.157 bất kỳ đều có profiles pipeline đầy đủ. Phải kiểm tra:

```bash
otelcol components
```

và tài liệu distribution cụ thể.

Xem nền tảng tại [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md).

---

## 48. Correlation metrics → profiles

Workflow:

```text
CPU metric tăng lúc 14:32
  → mở profile cùng service/time range
  → lọc version/pod/region
  → xem CPU flame graph
  → compare với baseline
```

Điều kiện:

- cùng clock/timezone;
- cùng service identity;
- label vocabulary khớp;
- profile retention còn dữ liệu;
- metric time range đủ hẹp;
- pod/version metadata đúng.

Profile không cần chứa metric sample; Grafana có thể dùng metadata/time để liên kết trải nghiệm điều tra.

---

## 49. Correlation traces → profiles

Trace-to-profile cơ bản có thể map:

```text
service.name
service.namespace
pod
version
span start/end
```

Sau đó query profile quanh span time range.

Nhưng đây chưa chắc là profile riêng của span. Nó có thể là profile aggregate của process trong cùng window.

**Span Profiles** bổ sung bridge:

```text
profiling sample ↔ trace/span context
```

giúp query resource usage của execution scope cụ thể hơn.

---

## 50. Java Span Profiles

Java Span Profiles cần:

1. Pyroscope Java profiler;
2. OpenTelemetry Java tracing;
3. `otel-profiling-java` extension/bridge;
4. Tempo datasource cấu hình trace-to-profiles;
5. Pyroscope datasource.

Java hiện hỗ trợ correlation cho:

- CPU profile với `itimer` hoặc `cpu`;
- wall profile.

Bridge có thể thêm:

```text
pyroscope.profile.id
span_name
trace/span context
```

Nếu span không có `pyroscope.profile.id`, cần kiểm tra extension và agent loading.

---

## 51. Span ngắn và sampling probability

Nếu sample interval là 10 ms:

```text
span 2 ms
```

có thể kết thúc trước khi profiler chụp bất kỳ stack nào.

Vì vậy:

- “không có profile” không có nghĩa span không chạy code;
- span profile hiệu quả hơn với span đủ dài;
- tăng sample rate có overhead;
- có thể aggregate nhiều request cùng operation;
- wall profile hữu ích khi span chủ yếu chờ.

Không dùng span profile làm kế toán exact CPU cho từng request ngắn.

---

## 52. Grafana datasource và Profiles Drilldown

Grafana có thể:

- query Pyroscope datasource;
- hiển thị flame graph;
- diff profile;
- drill down theo service/profile type;
- mở source line khi integration đầy đủ;
- liên kết Tempo trace với profile;
- đặt profile panel cạnh metric/log.

Datasource phải cấu hình:

- URL;
- authentication;
- TLS;
- tenant header khi có;
- access mode;
- timeout.

Credential nên lưu trong secure datasource fields/provisioning secret, không commit plain text.

---

## 53. Pyroscope v2 architecture

Pyroscope 2.2 dùng kiến trúc v2 cho deployment mới.

Write path:

```text
client
  → distributor
  → segment-writer
  → object storage
       │
       └── metadata → metastore
```

Read path:

```text
Grafana/query
  → query-frontend
  → metastore tìm object
  → query-backend đọc object storage
  → merge result
```

Compaction:

```text
metastore điều phối
  → compaction-worker
  → merge segment thành block
```

Không thiết kế greenfield theo v1 ingester/store-gateway diagram cũ.

---

## 54. Pyroscope deployment modes

### Single-node

- một process;
- local filesystem có thể dùng;
- phù hợp lab/evaluation/small setup;
- không HA;
- không scale từng component;
- tài liệu v2 không khuyến nghị production.

### Microservices

- scale write/read/compaction riêng;
- object storage bắt buộc;
- metastore chạy Raft và cần persistent storage;
- vận hành phức tạp hơn;
- phù hợp production lớn.

Không nhảy vào microservices chỉ vì “production”. Cân workload, SLO và năng lực vận hành.

---

## 55. Object storage và metastore

Pyroscope v2 ghi profile trực tiếp vào object storage.

Lợi ích:

- durability dựa trên object storage;
- bỏ local disk ingester;
- read/write scale độc lập;
- query backend stateless.

Metastore:

- giữ metadata index;
- điều phối compaction;
- cung cấp object location cho query;
- áp retention;
- là component stateful chính;
- dùng Raft để replicate state.

Object storage sống nhưng metastore hỏng vẫn có thể làm query/ingestion không hoạt động đúng. Cần backup/recovery plan cho state quan trọng.

---

## 56. Capacity và retention

Profile volume phụ thuộc:

```text
targets
× sample rate
× profile types
× unique stacks
× label sets
× upload frequency
× retention
```

Allocation/lock event có thể lớn hơn nhiều CPU sample nếu threshold quá thấp.

Capacity plan gồm:

- ingestion bytes/s;
- profiles/s;
- object PUT/GET;
- compaction;
- query bytes fetched;
- symbol/debug storage;
- egress;
- retention;
- peak incident queries.

Không chỉ nhìn object storage GB. Request cost và query CPU cũng quan trọng.

---

## 57. Multi-tenancy và authentication

Pyroscope multi-tenancy dùng:

```text
X-Scope-OrgID
```

để nhận diện tenant.

Mặc định multi-tenancy có thể tắt và dữ liệu vào tenant `anonymous`.

Quan trọng:

> Tenant header không tự nó chứng minh caller được phép dùng tenant đó.

Production cần authenticating reverse proxy/gateway:

```text
client identity
  → authenticate
  → authorize tenant
  → inject trusted tenant header
  → Pyroscope
```

Không cho client tùy ý tự chọn `X-Scope-OrgID` qua public endpoint.

---

## 58. Quan sát chính profile pipeline

Theo dõi collector/agent:

- active targets;
- profiling sessions success/failure;
- profile upload errors;
- queue/drop;
- symbolization success/failure;
- CPU/memory;
- target discovery count.

Theo dõi Pyroscope:

- ingestion accepted/rejected;
- request latency/error;
- segment write;
- metastore Raft health;
- compaction lag;
- query latency;
- query bytes fetched;
- object storage errors;
- retention cleanup.

Profile backend cũng là production system cần SLO và alert.

---

## 59. Rollout continuous profiling

Lộ trình:

```text
local
  → staging
  → 1 canary pod/node
  → 5% fleet
  → 25%
  → 100%
```

Ở mỗi bước đo:

- profiler CPU/memory;
- application latency;
- GC;
- upload bandwidth;
- profile completeness;
- unknown symbols;
- backend ingestion;
- label cardinality;
- storage growth.

Rollback trigger ví dụ:

- p99 tăng vượt budget;
- CPU tăng hơn ngưỡng;
- profiler crash/attach lỗi;
- unknown frame quá cao;
- profile queue/drop tăng;
- backend ingestion bị quá tải.

---

## 60. Incident workflow

Ví dụ CPU spike:

```text
1. Metric xác nhận service/version/pod và time window.
2. Trace xác nhận endpoint hoặc workload bị ảnh hưởng.
3. Mở CPU profile đúng time range.
4. So sánh canary/stable hoặc before/after.
5. Xem self/total và call path.
6. Kiểm tra symbol/source đúng commit.
7. Tạo hypothesis.
8. Reproduce bằng benchmark/load test.
9. Implement fix.
10. Dùng diff profile xác nhận production.
```

Không sửa code ngay sau khi thấy một frame rộng. Phải nối frame với triệu chứng và hypothesis.

---

## 61. Performance improvement workflow

Định luật Amdahl trực quan:

```text
function chiếm 1% CPU
  tối ưu nhanh gấp 10
  → toàn hệ thống chỉ cải thiện tối đa khoảng 0.9%
```

Ưu tiên:

- self/total lớn;
- nằm trên workload quan trọng;
- có fix an toàn;
- không đổi correctness;
- có benchmark;
- có production validation.

Đánh giá cả trade-off:

```text
CPU giảm nhưng allocation tăng?
latency giảm nhưng memory tăng?
cache tăng hit nhưng stale data?
parallelism tăng throughput nhưng downstream quá tải?
```

---

## 62. Anti-patterns

### “Thanh rộng là bug”

Thanh rộng chỉ nói resource tập trung ở đó; có thể là công việc hợp lệ.

### “Allocation profile chứng minh leak”

Allocation rate và retained heap là hai câu hỏi khác nhau.

### “CPU thấp nên profiler vô dụng”

Wall/lock profile có thể chỉ ra thời gian chờ.

### “Tăng sample rate giải quyết mọi thứ”

Nó tăng cost và vẫn không sửa symbol/identity sai.

### “eBPF không ảnh hưởng application”

eBPF agent vẫn tiêu CPU/memory và cần privilege.

### “Profile label càng chi tiết càng tốt”

High cardinality làm storage/query đắt và tăng privacy risk.

### “X-Scope-OrgID là authentication”

Đó là tenant selector, cần trusted auth layer.

### “OTLP Profiles đã stable như traces”

Profiles hiện còn Alpha/development.

---

## 63. Production checklist

### Use case

- [ ] Đã xác định cần CPU, wall, alloc, lock hay heap.
- [ ] Có câu hỏi production cụ thể.
- [ ] Có metric/trace làm entry point.

### Collection

- [ ] Sample rate có overhead budget.
- [ ] Allocation/lock threshold không để `0` mặc định.
- [ ] Target discovery không profile nhầm process.
- [ ] Java/JDK/profiler compatibility đã test.
- [ ] eBPF privilege được security review.
- [ ] Symbol cache có capacity.

### Identity

- [ ] `service_name` ổn định.
- [ ] Namespace/environment/version thống nhất với OTel.
- [ ] Không có request/user/trace ID trong series labels.
- [ ] Pod/container/node labels có mục đích rõ.

### Backend

- [ ] Pyroscope dùng v2 architecture cho greenfield.
- [ ] Object storage và metastore có HA/recovery.
- [ ] Retention/capacity đã tính.
- [ ] Auth/TLS/tenant isolation hoạt động.
- [ ] Backend internal metrics được alert.

### Validation

- [ ] Có canary rollout.
- [ ] Đã đo application overhead.
- [ ] Unknown symbols ở mức chấp nhận được.
- [ ] Diff profile so đúng workload.
- [ ] Trace-to-profile đã test end-to-end.
- [ ] Có rollback trigger.

---

## 64. Câu hỏi tự kiểm tra

1. Profiling bổ sung gì cho metrics và traces?
2. Continuous profiling khác attach profiler khi incident thế nào?
3. Sampling profiler tạo dữ liệu ra sao?
4. Vì sao profile là ước lượng thống kê?
5. Sample rate cao có trade-off gì?
6. CPU profile và wall profile khác nhau thế nào?
7. Khi CPU thấp nhưng latency cao nên xem profile nào?
8. Allocation nhiều có chứng minh memory leak không?
9. In-use profile khác heap dump thế nào?
10. Lock count và lock duration trả lời gì?
11. Trục ngang flame graph có phải timeline không?
12. Self và total khác nhau thế nào?
13. Vì sao cần xem cả top table và flame graph?
14. Diff profile có thể gây hiểu nhầm ra sao?
15. Symbolization cần build ID để làm gì?
16. Vì sao debug artifact retention quan trọng?
17. PID có đủ để nhận diện Kubernetes workload không?
18. Label nào phù hợp và label nào gây cardinality cao?
19. In-process và eBPF profiler khác trade-off thế nào?
20. Vì sao continuous và on-demand profiling nên cùng tồn tại?
21. `default.jfc` và `profile.jfc` khác nhau thế nào?
22. async-profiler quan sát được những loại resource nào?
23. `DebugNonSafepoints` dùng để làm gì?
24. Vì sao allocation/lock threshold bằng `0` nguy hiểm?
25. Alloy `pyroscope.java` cần target field nào?
26. eBPF profiler cần những quyền gì?
27. Pyroscope và Parca nên được so sánh bằng tiêu chí nào?
28. pprof, JFR và OTLP Profiles khác nhau ra sao?
29. Trạng thái hiện tại của OTel Profiles là gì?
30. Trace-to-profile theo time/label khác Span Profiles thế nào?
31. Vì sao span ngắn có thể không có sample?
32. Write path Pyroscope v2 gồm những component nào?
33. Metastore chịu trách nhiệm gì?
34. Vì sao microservices mode cần object storage?
35. `X-Scope-OrgID` có phải authentication không?
36. Profile pipeline cần monitor những chỉ số nào?
37. Làm sao xác nhận một optimization thật sự hiệu quả?

---

## 65. Tài liệu chính thức

### Grafana Pyroscope

- [Grafana Pyroscope](https://grafana.com/docs/pyroscope/latest/)
- [Pyroscope 2.2 release notes](https://grafana.com/docs/pyroscope/latest/release-notes/v2-2/)
- [Pyroscope v2 architecture](https://grafana.com/docs/pyroscope/latest/reference-pyroscope-v2-architecture/)
- [About Pyroscope v2 architecture](https://grafana.com/docs/pyroscope/latest/reference-pyroscope-v2-architecture/about-pyroscope-v2-architecture/)
- [Pyroscope deployment modes](https://grafana.com/docs/pyroscope/latest/reference-pyroscope-v2-architecture/deployment-modes/)
- [Profile types](https://grafana.com/docs/pyroscope/latest/configure-client/profile-types/)
- [Java profiling](https://grafana.com/docs/pyroscope/latest/configure-client/language-sdks/java/)
- [Java Span Profiles](https://grafana.com/docs/pyroscope/latest/configure-client/trace-span-profiles/java-span-profiles/)
- [Memory overhead](https://grafana.com/docs/pyroscope/latest/configure-client/memory-overhead/)
- [Self vs Total](https://grafana.com/docs/pyroscope/latest/view-and-analyze-profile-data/self-vs-total/)
- [Tenant IDs](https://grafana.com/docs/pyroscope/latest/configure-server/about-tenant-ids/)

### Grafana Alloy và Grafana

- [Alloy `pyroscope.java`](https://grafana.com/docs/alloy/latest/reference/components/pyroscope/pyroscope.java/)
- [Alloy `pyroscope.ebpf`](https://grafana.com/docs/alloy/latest/reference/components/pyroscope/pyroscope.ebpf/)
- [Pyroscope datasource](https://grafana.com/docs/grafana/latest/datasources/pyroscope/)
- [Configure traces to profiles](https://grafana.com/docs/grafana/latest/datasources/pyroscope/configure-traces-to-profiles/)
- [Flame graphs](https://grafana.com/docs/grafana/latest/visualizations/simplified-exploration/profiles/concepts/flame-graphs/)

### Java và async-profiler

- [async-profiler](https://github.com/async-profiler/async-profiler)
- [JDK Flight Recorder configurations](https://docs.oracle.com/en/java/javase/24/jfapi/flight-recorder-configurations.html)
- [`jcmd` JDK 25](https://docs.oracle.com/en/java/javase/25/docs/specs/man/jcmd.html)
- [JFR API JDK 25](https://docs.oracle.com/en/java/javase/25/docs/api/jdk.jfr/jdk/jfr/package-summary.html)

### Parca và OpenTelemetry

- [Parca](https://github.com/parca-dev/parca)
- [OpenTelemetry Profiles concepts](https://opentelemetry.io/docs/concepts/signals/profiles/)
- [OpenTelemetry Profiles Alpha](https://opentelemetry.io/blog/2026/profiles-alpha/)
- [OpenTelemetry eBPF profiler](https://github.com/open-telemetry/opentelemetry-ebpf-profiler)

---

## Chủ đề tiếp theo

Sau continuous profiling, chủ đề mở rộng tiếp theo là:

> [**eBPF Observability Deep Dive – kernel hooks, kprobe/uprobe/tracepoint,
> network tracing, security và production overhead.**](ebpf_observability.md)

---

*Cập nhật lần cuối: 2026-07-29*
