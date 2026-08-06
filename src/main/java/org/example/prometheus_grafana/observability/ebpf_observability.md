# eBPF Observability Deep Dive – Kernel Hooks, Network Tracing và Production Safety

> Mục tiêu của bài này là xây mental model đủ chắc để chọn đúng hook, hiểu dữ liệu đi
> từ kernel tới observability backend như thế nào, đánh giá privilege/overhead và vận
> hành eBPF an toàn trong production.
>
> Baseline tham chiếu ngày 2026-07-30: tài liệu Linux eBPF hiện hành,
> **bpftrace 0.24**, **Cilium/Hubble 1.20** và
> **OpenTelemetry eBPF Instrumentation – OBI 0.10**.
>
> Bài này không thay thế kiến thức Linux performance, Kubernetes networking hoặc
> profiling. Đọc thêm:
> [Linux Performance Tuning](../../linux/admin/performance_tuning.md),
> [Kubernetes Networking Deep Dive](../../kubernetes/networking/networking_deep.md),
> [Continuous Profiling](continuous_profiling.md) và
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md).

---

## 1. eBPF observability giải quyết bài toán gì?

Instrumentation truyền thống thường cần một trong các cách:

- sửa source code;
- nạp language agent vào process;
- đọc log mà ứng dụng chủ động ghi;
- poll file hoặc API do kernel/application cung cấp.

eBPF mở thêm một hướng:

```text
sự kiện xảy ra trong kernel hoặc user process
  → chạy chương trình eBPF tại hook đã chọn
  → lọc/aggregate ngay gần nguồn
  → chuyển record cần thiết sang user space
  → enrich rồi xuất metrics, traces, events hoặc profiles
```

Nhờ vậy có thể trả lời những câu như:

- process nào đang gọi syscall nhiều bất thường;
- kết nối TCP chậm ở bước connect hay chậm sau khi đã kết nối;
- packet bị drop ở lớp nào;
- service nào đang giao tiếp với service nào;
- binary hoặc call stack nào tiêu CPU;
- request HTTP/gRPC nào chậm dù ứng dụng chưa cài SDK.

Giá trị chính là **khả năng quan sát xuyên process và xuyên ngôn ngữ từ hệ điều
hành**. Đổi lại, dữ liệu thường ít business context hơn instrumentation trong code
và agent cần quyền rất nhạy cảm.

---

## 2. Mental model: camera gắn vào các điểm móc

Hãy hình dung kernel và process có nhiều “điểm móc”:

```text
User process
  function entry/return ── uprobe/uretprobe, USDT
             │
             ▼ syscall boundary
Kernel
  syscall tracepoint ───── tracepoint/raw tracepoint
  kernel function ──────── kprobe/kretprobe, fentry/fexit
  network stack ────────── socket, cgroup, tc, XDP
  security decision ────── LSM
```

Chương trình eBPF nhỏ được attach vào một điểm móc. Mỗi khi sự kiện đi qua đó,
chương trình có thể:

- đọc context được kernel cho phép;
- lấy PID/TID, UID, cgroup, timestamp;
- cập nhật counter/histogram trong map;
- gửi một record sang user space;
- trong một số program type, cho phép/drop hoặc biến đổi packet.

Ba quyết định quan trọng nhất luôn là:

1. **hook nào** gần câu hỏi nhất;
2. **lọc/aggregate gì trong kernel**;
3. **xuất dữ liệu nào** mà vẫn có budget.

---

## 3. eBPF là cơ chế, không phải một observability product

eBPF không tự cung cấp dashboard, retention, service name hay alert.

```text
eBPF mechanism
  ├── program + hook
  ├── map/buffer
  └── kernel verifier/JIT

Observability product
  ├── loader và lifecycle
  ├── process/container discovery
  ├── protocol parser
  ├── symbolization
  ├── metadata enrichment
  ├── exporter
  └── storage/query/UI
```

Ví dụ:

- bpftrace giúp viết script điều tra ad-hoc;
- BCC cung cấp tool và runtime compilation;
- libbpf phù hợp xây agent CO-RE có lifecycle rõ;
- Cilium/Hubble tập trung network datapath và flow visibility;
- OBI tập trung zero-code application/network telemetry;
- eBPF profiler tập trung stack sampling.

Nói “dùng eBPF” chưa đủ. Phải chỉ rõ **dùng sản phẩm nào, hook nào, signal nào và
vận hành ra sao**.

---

## 4. Vòng đời một ứng dụng eBPF

Một đường đi điển hình:

```text
C/Rust source
  → clang/LLVM biên dịch BPF bytecode
  → ELF chứa program, maps, BTF và relocation
  → loader mở object
  → libbpf áp dụng CO-RE relocation
  → bpf() syscall yêu cầu kernel load
  → verifier kiểm tra
  → interpreter hoặc JIT chuẩn bị thực thi
  → attach bằng bpf_link/perf event/netlink
  → sự kiện kích hoạt program
  → map/ring buffer đưa dữ liệu tới user space
```

Khi debug cần xác định lỗi ở pha nào:

| Pha | Lỗi thường gặp |
|---|---|
| Compile | header/type không đúng, instruction quá phức tạp |
| Relocate | thiếu BTF, field không tồn tại |
| Load/verify | memory access không chứng minh được an toàn |
| Attach | symbol/hook không tồn tại, thiếu capability |
| Runtime | map đầy, buffer mất event, CPU tăng |
| Export | queue đầy, backend chậm, metadata sai |

Không gom tất cả thành lỗi chung “eBPF không chạy”.

---

## 5. Bytecode, interpreter và JIT

eBPF dùng instruction set riêng. Kernel có thể:

- diễn giải bytecode bằng interpreter;
- JIT compile sang machine code của CPU;
- từ chối program nếu platform/config không hỗ trợ.

JIT giúp giảm overhead trên hot path, nhưng không biến program đắt thành rẻ.

Ví dụ, hook chạy 1 triệu lần/giây:

```text
80 ns/event  ≈ 80 ms CPU/giây ≈ 8% của một CPU
500 ns/event ≈ 500 ms CPU/giây ≈ 50% của một CPU
```

Đây chỉ là phép ước lượng để thấy rằng:

```text
chi phí mỗi event nhỏ × tần suất event rất lớn = chi phí production đáng kể
```

Đừng benchmark bằng số “CPU trung bình của agent” duy nhất. Cần đo cả latency ở
hook, số event, cache pressure, memory maps và chi phí user-space/export.

---

## 6. Verifier bảo vệ điều gì?

Trước khi load, verifier phân tích program. Tùy program type và kernel, nó kiểm tra
những thuộc tính như:

- đường thực thi kết thúc trong giới hạn có thể chứng minh;
- pointer thuộc loại nào và có thể trỏ tới vùng nào;
- packet access đã kiểm tra `data_end`;
- stack/map/context access hợp lệ;
- helper hoặc kfunc được phép với program type đó;
- reference đã reserve/acquire được release đúng cách.

Ví dụ logic packet:

```c
void *data = (void *)(long)ctx->data;
void *data_end = (void *)(long)ctx->data_end;

if (data + sizeof(struct ethhdr) > data_end)
    return XDP_PASS;
```

Boundary check không chỉ để tránh crash runtime; nó giúp verifier chứng minh access
an toàn.

---

## 7. Verifier không bảo đảm điều gì?

Program được verifier chấp nhận vẫn có thể:

- đếm sai;
- gán nhầm service;
- tạo cardinality quá cao;
- tiêu CPU đáng kể;
- làm đầy map;
- mất event khi ring buffer đầy;
- làm lộ path, query string hoặc payload nhạy cảm;
- drop packet hợp lệ nếu program có quyền thay đổi datapath.

Mental model đúng:

```text
verifier accepted
  = đủ an toàn theo model của kernel để được chạy
  ≠ business logic đúng
  ≠ overhead thấp
  ≠ production ready
```

Vì vậy eBPF agent vẫn cần code review, test, canary, SLO và rollback giống một
thành phần privileged khác.

---

## 8. Program type và attach type

Hai khái niệm dễ bị trộn:

- **program type** quyết định context, helpers/kfuncs và luật verifier;
- **attach type/target** quyết định program gắn vào đâu.

Ví dụ khái niệm:

```text
BPF_PROG_TYPE_TRACEPOINT
  attach → tracepoint syscalls:sys_enter_execve

BPF_PROG_TYPE_KPROBE
  attach → entry của một kernel function

BPF_PROG_TYPE_XDP
  attach → network interface ingress

BPF_PROG_TYPE_CGROUP_SKB
  attach → cgroup ingress/egress
```

Không phải helper nào cũng gọi được từ mọi program type. Không phải kernel nào có
program type, helper và attach feature giống nhau. Feature detection phải là một
phần của startup, không chỉ kiểm tra version string.

---

## 9. BPF maps: bộ nhớ trạng thái dùng chung

Map là storage có kiểu do kernel quản lý, được truy cập từ BPF program và/hoặc
user space. Một số loại phổ biến:

| Map | Dùng khi |
|---|---|
| Array | index cố định, config/counter nhỏ |
| Per-CPU array | counter hot path, giảm contention |
| Hash | key động |
| LRU hash | cần eviction có giới hạn |
| Per-CPU hash | aggregate theo CPU trước khi merge |
| Stack trace | lưu stack ID/call chain |
| Ring buffer | stream record sang user space |
| Map-in-map | shard hoặc đổi tập map |

Ví dụ latency pairing:

```text
entry hook:
  start[tid] = now

return hook:
  duration = now - start[tid]
  delete start[tid]
```

Map không phải database miễn phí. Cần đặt `max_entries`, xử lý lookup/update fail,
cleanup key và theo dõi memory.

---

## 10. Chọn map theo contention và vòng đời key

Trước khi chọn map, trả lời:

1. Key có bounded không?
2. Ai xóa key?
3. Nhiều CPU có update cùng value không?
4. Chấp nhận eviction không?
5. Cần user space đọc theo interval hay cần từng event?

Ví dụ:

| Nhu cầu | Lựa chọn thường hợp lý |
|---|---|
| Counter toàn node | per-CPU array rồi cộng ở user space |
| Start time theo TID | hash/LRU hash có cleanup |
| Histogram bounded | per-CPU array buckets |
| Config do agent đẩy xuống | array/hash |
| Event chi tiết | ring buffer |

LRU tránh tăng vô hạn nhưng eviction có thể làm mất entry đang chờ return hook.
Khi đó duration không tính được. Agent phải có metric cho orphan/miss, không âm
thầm coi chúng là duration bằng 0.

---

## 11. Perf buffer và BPF ring buffer

Hai cơ chế thường dùng để gửi record ra user space:

| Đặc điểm | Perf buffer | BPF ring buffer |
|---|---|---|
| Bố trí phổ biến | per-CPU | một buffer có thể dùng chung CPU |
| Cross-CPU ordering | phải xử lý thêm | giữ thứ tự reservation chung |
| Memory | cấp theo CPU | chia sẻ linh hoạt hơn |
| Kernel cũ | hỗ trợ rộng hơn | cần kernel có ringbuf |
| API | perf event output | output hoặc reserve/submit/discard |

Ring buffer không block khi hết chỗ. Reservation thất bại và event bị mất nếu
producer nhanh hơn consumer.

Do đó record nên:

- nhỏ và có schema cố định;
- không chứa payload không cần thiết;
- có counter `events_attempted`, `events_submitted`, `events_dropped`;
- được batch/enrich ở user space.

“Không thấy event” có thể là không có sự kiện, filter loại bỏ, attach fail hoặc
buffer loss. Phải phân biệt được bốn trường hợp.

---

## 12. BTF: type metadata cho hệ sinh thái BPF

BTF – BPF Type Format – mô tả type, function và line information theo định dạng
gọn. Kernel thường expose BTF tại:

```text
/sys/kernel/btf/vmlinux
```

BTF giúp:

- libbpf biết layout type của kernel đích;
- CO-RE relocate field offset;
- fentry/fexit có function prototype;
- bpftool pretty-print key/value;
- dump program có source line/function rõ hơn.

Kiểm tra nhanh:

```bash
test -r /sys/kernel/btf/vmlinux && echo "kernel BTF available"
bpftool btf show
```

Có BTF không có nghĩa mọi hook đều tồn tại. Nó giải quyết metadata/type portability,
không giải quyết feature availability hay semantic change.

---

## 13. CO-RE: Compile Once – Run Everywhere

CO-RE kết hợp:

- compiler ghi relocation;
- BTF trong object mô tả type program mong đợi;
- BTF của kernel đích mô tả type thực tế;
- libbpf sửa offset/immediate trước khi load.

```text
build host                    target host
vmlinux.h + source
  → object có BTF/CO-RE ─────→ libbpf + target BTF
                                → relocate
                                → verify/load
```

CO-RE giúp một binary chạy trên nhiều kernel compatible mà không compile C tại
node đích.

CO-RE không phải “run everywhere” theo nghĩa tuyệt đối. Program vẫn có thể không
chạy vì:

- kernel thiếu program type/helper/kfunc;
- config kernel tắt subsystem;
- target function bị đổi/xóa;
- distribution backport tạo behavior khác;
- architecture chưa được build/test;
- security policy chặn load/attach.

Production cần compatibility matrix và feature probe thực tế.

---

## 14. libbpf, BCC và bpftrace khác nhau thế nào?

| Công cụ | Mạnh ở đâu | Trade-off |
|---|---|---|
| libbpf/CO-RE | agent production nhỏ, lifecycle rõ | cần build pipeline và C/Rust user space |
| BCC | phát triển/tooling nhanh, nhiều ví dụ | thường cần compiler/header ở runtime |
| bpftrace | điều tra ad-hoc, cú pháp ngắn | script dễ gây volume lớn, không phải backend |
| bpftool | introspection/load/dump | không thay agent/product |

Quy tắc thực tế:

- dùng bpftrace để kiểm chứng giả thuyết ngắn hạn;
- dùng tool BCC có sẵn nếu đúng câu hỏi;
- xây hoặc chọn agent libbpf/CO-RE cho rollout fleet;
- dùng bpftool để nhìn object thật trong kernel.

Không biến một dòng bpftrace thử nghiệm thành daemon chạy vĩnh viễn mà chưa thêm
budget, telemetry, lifecycle và test compatibility.

---

## 15. Taxonomy của hook

Có thể chia hook theo lớp:

| Lớp | Hook tiêu biểu | Câu hỏi |
|---|---|---|
| Kernel event | tracepoint, raw tracepoint | syscall/scheduler/event ổn định |
| Kernel function | kprobe, fentry/fexit | chi tiết implementation |
| User function | uprobe, USDT | library/runtime/application |
| Sampling | perf event/profile | CPU/off-CPU stack |
| Packet | XDP, tc | ingress/egress, packet/action |
| Socket/cgroup | socket, sockops, cgroup | connection theo workload |
| Security | LSM | decision/audit/enforcement |

Chọn hook theo thứ tự ưu tiên:

```text
semantic đủ gần câu hỏi
  → interface ổn định nhất
  → tần suất thấp nhất vẫn đủ tín hiệu
  → privilege và blast radius nhỏ nhất
```

Không chọn hook chỉ vì ví dụ trên Internet dùng nó.

---

## 16. Tracepoint

Tracepoint là điểm sự kiện tĩnh do kernel định nghĩa. Có thể liệt kê:

```bash
bpftrace -l 'tracepoint:syscalls:*exec*'
```

Ưu điểm:

- event và field có tên;
- thường ổn định hơn việc gắn vào internal function;
- phù hợp syscall, scheduler, block I/O, networking events;
- dễ khám phá qua tracing filesystem/bpftrace.

Hạn chế:

- không phải mọi chi tiết đều có tracepoint;
- field vẫn cần kiểm tra trên kernel thực tế;
- tracepoint có tần suất cực cao vẫn gây overhead;
- “ổn định hơn” không có nghĩa ABI application vĩnh viễn.

Nếu tracepoint đủ dữ liệu, thường nên ưu tiên nó trước kprobe.

---

## 17. Raw tracepoint

Raw tracepoint đặt BPF gần raw arguments hơn:

- ít lớp chuyển đổi context hơn;
- có thể hiệu quả hơn ở hot path;
- argument ít thân thiện và phụ thuộc hiểu biết kernel;
- portability/maintainability thường khó hơn tracepoint thường.

Nên dùng khi:

- đã đo tracepoint overhead là vấn đề;
- cần raw context mà tracepoint format không cung cấp;
- có ownership và compatibility test.

Không chọn raw tracepoint chỉ vì chữ “raw” nghe nhanh. Chi phí toàn pipeline còn
phụ thuộc map, copy, symbolization và export.

---

## 18. kprobe và kretprobe

`kprobe` gắn vào entry của kernel function; `kretprobe` quan sát lúc function trả
về.

```text
kprobe:function
  → đọc arguments theo calling convention/BTF helper

kretprobe:function
  → đọc return value
```

Ưu điểm:

- rất linh hoạt;
- tiếp cận internal path chưa có tracepoint;
- hữu ích cho điều tra kernel behavior.

Rủi ro:

- tên, signature và implementation function thay đổi theo kernel;
- function có thể inline hoặc không còn attach được;
- return pairing phức tạp với recursion/missed entry;
- attach quá nhiều function bằng wildcard làm overhead khó đoán.

kprobe là kính hiển vi mạnh nhưng có coupling với implementation.

---

## 19. fentry và fexit

fentry/fexit là BPF trampoline dựa trên BTF để quan sát entry/exit của kernel
function.

So với kprobe, chúng thường có:

- typed arguments tốt hơn;
- attach trực tiếp qua trampoline;
- overhead thấp hơn trong nhiều tình huống;
- fexit truy cập arguments và return value thuận tiện hơn.

Đổi lại:

- cần BTF và kernel support phù hợp;
- vẫn phụ thuộc function tồn tại;
- không phải mọi target đều attach được;
- compatibility phải kiểm tra trên fleet.

Thứ tự cân nhắc thường là:

```text
tracepoint đủ semantic? → dùng tracepoint
không đủ, có fentry/fexit compatible? → cân nhắc trampoline
cần fallback/điều tra kernel khác? → kprobe/kretprobe
```

---

## 20. uprobe và uretprobe

Uprobe gắn vào instruction/function trong user-space executable hoặc shared
library.

Use case:

- TLS library trước encrypt/sau decrypt;
- runtime function của Go/JVM/Node;
- database/client library;
- application function không có source instrumentation.

Rủi ro:

- binary update đổi symbol/offset;
- stripped binary thiếu symbol;
- PIE/ASLR và shared library mapping cần loader xử lý đúng;
- nhiều container/mount namespace làm path discovery khó;
- function bị inline hoặc tối ưu;
- attaching probe có thể tương tác với integrity/checksum mechanism.

Uprobe quan sát được plaintext không có nghĩa nên thu plaintext. Privacy review vẫn
bắt buộc.

---

## 21. USDT: probe do application định nghĩa

USDT – User Statically Defined Tracing – là điểm probe do binary/runtime chủ động
đặt với provider/name và argument contract.

```text
application code
  └── USDT provider:operation:start
                     operation:done
```

So với uprobe vào arbitrary function:

- semantic rõ hơn;
- ít coupling với internal function;
- application owner có thể duy trì contract;
- vẫn cần binary build có probe và activation/attach đúng.

Nếu đội ứng dụng chấp nhận thêm USDT nhưng không muốn full telemetry SDK, đây có
thể là điểm cân bằng tốt cho sự kiện hiệu năng quan trọng. Tuy nhiên USDT vẫn không
tự tạo trace hierarchy, resource attributes hay export pipeline.

---

## 22. Perf events và sampling

Perf event có thể kích hoạt BPF theo:

- hardware counter;
- software event;
- timer/profile frequency;
- tracepoint/perf infrastructure.

Đây là nền tảng cho nhiều CPU profiler:

```text
N lần/giây trên mỗi CPU
  → lấy kernel/user stack
  → aggregate stack ID
  → symbolization ở user space/backend
```

Sampling có trade-off:

- frequency cao: thấy function ngắn tốt hơn nhưng tốn CPU;
- frequency thấp: rẻ hơn nhưng dễ bỏ lỡ path hiếm;
- stack depth cao: context tốt hơn nhưng record/map lớn;
- toàn node: coverage tốt nhưng privilege và volume lớn.

Chi tiết profile, frame pointer và symbolization nằm trong
[Continuous Profiling](continuous_profiling.md).

---

## 23. XDP: hook rất sớm trên ingress

XDP chạy rất sớm khi packet vào network device, trước khi tạo đầy đủ `sk_buff` ở
network stack thông thường.

Action điển hình:

```text
XDP_PASS
XDP_DROP
XDP_TX
XDP_REDIRECT
```

XDP phù hợp:

- DDoS filtering/load balancing tốc độ cao;
- packet counters ở ingress sớm;
- drop/redirect trước chi phí network stack.

Nhưng observability program tại XDP:

- thiếu process/socket context ở lớp cao;
- parser phải boundary-check nghiêm ngặt;
- action sai có thể làm mất traffic;
- offload/driver/generic mode khác nhau về capability và hiệu năng.

Nếu chỉ cần service latency HTTP, XDP thường ở lớp quá thấp.

---

## 24. Traffic Control – tc ingress/egress

tc BPF thường gắn tại `clsact` ingress/egress, nơi packet đã ở dạng `sk_buff`.

So với XDP:

- quan sát được cả ingress và egress thuận tiện;
- có nhiều network metadata hơn;
- phù hợp flow accounting, policy và context propagation;
- nằm muộn hơn nên chi phí/semantic khác.

Agent network có thể dùng tc để:

- đếm bytes/packets theo flow;
- parse header có giới hạn;
- gắn/đọc trace context trong trường hợp được hỗ trợ;
- xác định drop/route/action.

tc program có thể thay đổi datapath. Rollout observability-only nên xác nhận action
mặc định luôn pass/OK và có kill switch.

---

## 25. Cgroup, socket, sockops, sk_skb và sk_msg

Các hook này đặt quan sát gần socket/workload hơn:

| Họ hook | Ví dụ use case |
|---|---|
| cgroup connect/bind | ai mở outbound connection hoặc bind port |
| cgroup skb | ingress/egress theo cgroup |
| sockops | lifecycle/option của TCP socket |
| sk_skb | parser/verdict trên socket buffer |
| sk_msg | xử lý message qua sockmap |
| socket filter | lọc/capture packet qua socket |

Cgroup ID là cầu nối tốt từ task/network event sang container workload, nhưng cần
user-space resolver:

```text
cgroup id
  → container runtime metadata
  → pod/container
  → workload/service
```

Mapping có race khi pod ngắn hạn hoặc metadata cache trễ. Không nên coi mọi
`unknown cgroup` là traffic host.

---

## 26. BPF LSM

BPF LSM gắn vào Linux Security Module hooks để audit hoặc, tùy program, tham gia
enforcement.

Use case:

- quan sát file/process/security operation;
- policy theo cgroup/workload;
- runtime security.

Đây là vùng cần tách rõ:

```text
observability: record decision/event
enforcement:   cho phép hoặc từ chối operation
```

Một bug trong observability exporter không nên vô tình thành outage security
enforcement. Nếu sản phẩm dùng cả hai:

- review mode/action rõ;
- fail-open/fail-closed là quyết định có chủ đích;
- audit event loss riêng;
- rollout enforcement qua canary;
- có đường khôi phục ngoài agent.

---

## 27. Ma trận độ ổn định của hook

Đây là guideline, không phải luật tuyệt đối:

| Hook | Semantic | Coupling | Portability |
|---|---|---:|---:|
| Tracepoint | event do kernel đặt tên | thấp hơn | tốt |
| Raw tracepoint | raw event | trung bình | khá |
| fentry/fexit | kernel function typed | function-level | khá nếu BTF tốt |
| kprobe/kretprobe | internal kernel function | cao | dễ vỡ hơn |
| USDT | app-defined event | contract-level | tốt nếu app duy trì |
| uprobe/uretprobe | user function/offset | binary-level | dễ vỡ khi build đổi |
| XDP/tc | packet path | network/kernel feature | phụ thuộc fleet |

Chọn hook bằng semantic và compatibility test, không dựa duy nhất vào cột này.

---

## 28. Quan sát syscall đúng cách

Syscall tracing hữu ích để phát hiện:

- process spawn/exec;
- file open thất bại;
- network connect;
- latency I/O;
- behavior bất thường.

Nhưng “export mọi syscall” gần như luôn sai trong production.

Thiết kế tốt hơn:

```text
sys_enter
  → filter cgroup/PID/syscall
  → lưu start timestamp nếu cần latency

sys_exit
  → tính duration/result
  → aggregate histogram/counter
  → chỉ emit exemplar/event khi slow/error
```

Syscall boundary cho biết yêu cầu đi vào kernel, không luôn chỉ ra thiết bị,
filesystem hoặc network dependency cuối cùng. Cần kết hợp block/network/scheduler
signal nếu muốn root cause.

---

## 29. Pair entry/exit và tính latency

Pattern phổ biến:

```text
key = TID
entry[key] = {
  timestamp,
  operation context
}

exit:
  state = entry[key]
  duration = now - state.timestamp
  delete entry[key]
```

Các failure mode:

- entry bị filter nhưng exit không;
- map đầy hoặc LRU evict;
- thread exit trước return;
- nested/recursive call dùng cùng TID;
- missed event làm stale entry;
- clock/domain không nhất quán.

Với nesting, key có thể cần:

```text
(TID, depth) hoặc stack semantics
```

Luôn có counters cho `entry_saved`, `entry_update_failed`, `exit_without_entry` và
`stale_deleted`.

---

## 30. PID, TID, TGID, namespace và cgroup

Trong Linux tracing:

- TID nhận diện thread;
- TGID thường tương ứng process ID nhìn từ host namespace;
- PID nhìn trong container namespace có thể khác;
- cgroup thường ổn định hơn để gắn workload;
- executable/comm không đủ để định danh service.

Một identity pipeline tốt:

```text
kernel event
  → host PID/TID + cgroup ID
  → /proc và container runtime
  → container ID
  → pod UID + namespace + container name
  → workload owner
  → service.name theo resource contract
```

`comm` bị giới hạn độ dài và có thể trùng. Pod name chứa suffix rollout nên không
phải service name bền vững.

---

## 31. Network observability có nhiều lớp

Một request đi qua:

```text
application protocol
  → TLS
  → socket
  → TCP/UDP
  → IP
  → qdisc/interface
  → physical/virtual network
```

Mỗi lớp trả lời câu hỏi khác:

| Lớp | Quan sát được |
|---|---|
| L7 | method, route, status, request latency |
| TLS | handshake, library call; packet đã mã hóa |
| Socket | connect/accept, process/cgroup owner |
| TCP | retransmit, RTT, state transition |
| IP/flow | source/destination, bytes, drops |
| Interface | packet ingress/egress, queue/device |

Không kết luận “network chậm” chỉ từ một lớp. Ví dụ HTTP latency cao nhưng TCP RTT
thấp có thể do downstream xử lý chậm, không phải packet path.

---

## 32. DNS observability

DNS visibility thường cần:

- UDP/TCP port 53 flow;
- query/response parser có boundary;
- process/cgroup attribution;
- latency, response code và timeout;
- cache context nếu có ở user-space resolver.

Label an toàn:

```text
service.name
dns.response_code
server.address đã normalize/bucket nếu cần
```

Label nguy hiểm:

```text
dns.question.name cho mọi domain động
full query
client PID
```

Hubble có DNS-aware visibility khi datapath/policy phù hợp, nhưng coverage phụ
thuộc traffic đi qua Cilium và cấu hình L7. DNS cache hit trong application có thể
không tạo packet để quan sát.

---

## 33. TCP observability

Các signal hữu ích:

- connect latency và error;
- accept backlog;
- retransmission;
- reset;
- RTT/cwnd;
- socket state;
- bytes sent/received;
- drop reason nếu hook cung cấp.

Correlation mẫu:

```text
HTTP p99 tăng
  ├── connect latency tăng?      → DNS/routing/SYN path
  ├── retransmit tăng?           → loss/congestion
  ├── RTT tăng?                  → network distance/congestion
  ├── reset tăng?                → peer/policy/timeout
  └── TCP bình thường?           → xem application/dependency
```

Kernel structure field và units có thể đổi. Dùng CO-RE/BTF và test semantic bằng
traffic có kiểm soát.

---

## 34. HTTP, HTTP/2 và gRPC

Để tạo request metrics/traces, agent phải nhận diện:

- request boundary;
- method/protocol;
- host/authority;
- route hoặc path;
- response status;
- start/end và direction;
- connection multiplexing.

HTTP/1.1 trên connection tuần tự dễ hơn HTTP/2 multiplex nhiều stream. gRPC chạy
trên HTTP/2 và method thường nằm trong pseudo-header/path.

Một parser bounded có thể chỉ đọc prefix payload. Vì vậy:

- protocol hiếm hoặc frame phân mảnh có thể không detect;
- connection reuse cần state;
- parser phải giới hạn bytes và state entries;
- `url.path` raw tạo cardinality, nên normalize thành route khi có thể.

Zero-code L7 telemetry là suy luận từ protocol, không phải business truth tuyệt
đối.

---

## 35. TLS: packet thấy ciphertext, hook đúng mới thấy plaintext

Sau encryption:

```text
packet/tc/XDP → chỉ thấy TLS record/ciphertext
```

Muốn thấy HTTP semantic có thể cần:

- uprobe vào TLS library trước encrypt/sau decrypt;
- runtime-specific hook;
- sidecar/proxy có L7 visibility;
- instrumentation trong application.

Thách thức:

- nhiều TLS library/version;
- static link;
- Go có TLS trong binary;
- symbol stripped/inlined;
- kernel/security policy chặn uprobes;
- plaintext có PII/token.

Không bật payload capture để “debug nhanh” trên toàn cluster. Ưu tiên metadata
bounded, redact tại nguồn và target theo service/port/thời gian.

---

## 36. Kubernetes metadata enrichment

BPF program không nên gọi Kubernetes API. Nó chỉ emit identifier gọn:

```text
cgroup_id, netns cookie, ifindex, host PID
```

User-space agent:

```text
identifier
  → local cache
  → pod UID/container ID
  → namespace/workload/node
  → resource attributes
```

Thiết kế cache cần:

- watch thay vì list liên tục;
- tombstone/TTL cho pod vừa kết thúc;
- bounded memory;
- metric cache miss và lookup latency;
- không block ring-buffer consumer vì API server chậm.

Enrichment nên diễn ra trước export nhưng sau hot kernel path.

---

## 37. Service identity contract

Mục tiêu là eBPF telemetry ghép được với OTel/Prometheus telemetry:

| Ý nghĩa | Attribute/label gợi ý |
|---|---|
| Tên logic | `service.name` |
| Namespace logic | `service.namespace` |
| Version | `service.version` |
| Deployment | `deployment.environment.name` |
| Pod | `k8s.pod.uid`, `k8s.pod.name` |
| Container | `container.id`, `k8s.container.name` |
| Node | `k8s.node.name` |

Không tự suy `service.name` từ pod name nếu tổ chức đã có resource contract.

Thứ tự ưu tiên:

```text
explicit config/annotation
  → workload metadata
  → executable/process heuristic
  → unknown có reason
```

Theo dõi tỷ lệ telemetry `service.name=unknown`.

---

## 38. Tạo metrics từ eBPF

Hai cách:

### Aggregate trong kernel

```text
event
  → update counter/histogram map
  → user space đọc định kỳ
  → Prometheus/OTLP metrics
```

Ưu: volume thấp. Nhược: map schema/buckets khó đổi và ít event detail.

### Stream event rồi aggregate ở user space

```text
event → ring buffer → processor → metric
```

Ưu: linh hoạt. Nhược: copy/queue/CPU/cardinality cao hơn.

Quy tắc:

- aggregate hot, frequent event gần kernel;
- stream slow/error/rare event;
- histogram bucket theo SLO/use case;
- không label bằng PID, raw path, socket tuple hoặc trace ID.

---

## 39. Tạo traces từ eBPF

Agent zero-code có thể suy ra span từ:

- server request start/end;
- client request start/end;
- database/protocol operation;
- process/socket ownership;
- trace context thấy trong protocol.

Khoảng trống thường gặp:

- không thấy internal business span;
- không biết user/cart/order semantics;
- async handoff trong process khó suy luận;
- protocol không hỗ trợ;
- TLS hook thiếu;
- context propagation bị sample/mã hóa/không inject được.

Vì vậy chiến lược tốt thường là hybrid:

```text
eBPF zero-code
  → coverage nền và discovery

OTel SDK/manual instrumentation
  → business spans, custom attributes, events và explicit context
```

Xem thêm [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md).

---

## 40. Context propagation không phải phép màu

Distributed trace cần trace context đi qua process/network boundary.

eBPF agent có thể:

- đọc header đã tồn tại;
- liên kết client/server trên cùng node bằng heuristic;
- trong một số mode, inject context vào packet;
- tạo root span mới nếu không có parent.

Nhưng injection có giới hạn:

- protocol/TLS/checksum;
- packet segmentation;
- quyền tc/network;
- service mesh/proxy;
- tương thích với existing SDK;
- nguy cơ tạo hai trace context.

Phải test topology thật:

```text
SDK → eBPF-only → proxy → eBPF-only → SDK
```

Kiểm tra trace không bị tách, parent sai hoặc duplicate span.

---

## 41. Events và logs từ eBPF

eBPF phù hợp tạo structured events như:

```json
{
  "event": "tcp_reset",
  "timestamp": "...",
  "service.name": "checkout",
  "direction": "outbound",
  "peer": "payment",
  "reason": "..."
}
```

Không nên `printf` từng event từ kernel trong production:

- debug output có throughput giới hạn;
- format string tốn chi phí;
- dễ flood log;
- thiếu delivery contract.

Thiết kế event pipeline:

- numeric enum trong kernel;
- resolve tên ở user space;
- bounded fields;
- rate limit/deduplicate;
- severity có nghĩa;
- retention và PII policy như logs khác.

---

## 42. Profiles từ eBPF

eBPF profiler thường:

```text
perf event sample
  → lấy user/kernel stack ID
  → aggregate count trong maps
  → symbolization
  → profile backend
```

Khác application/request tracer:

- profile lấy mẫu tài nguyên/call stack;
- tracer theo operation/request lifecycle;
- profile không tự biết trace/span;
- tracer không cho tỷ lệ CPU theo mọi function.

Đừng chạy hai whole-node profiler cùng frequency mà không đo:

- duplicate samples;
- perf event contention;
- map/memory;
- symbol download;
- CPU của agent/backend.

Phần profile type, flame graph và Pyroscope xem tại
[Continuous Profiling](continuous_profiling.md).

---

## 43. Cilium và Hubble

Cilium dùng eBPF cho Kubernetes networking, policy và service handling. Hubble lấy
visibility từ Cilium datapath:

```text
node
  Cilium agent + Hubble server
       │ local flow events
       ▼
  Unix socket / gRPC

cluster
  Hubble Relay
       ├── node A Hubble
       ├── node B Hubble
       └── node C Hubble
```

Hubble mạnh ở:

- L3/L4 flow;
- identity/workload metadata;
- verdict/drop reason;
- DNS và một số L7 visibility;
- node, cluster hoặc ClusterMesh view;
- service map.

Coverage giới hạn ở traffic/workload mà Cilium quan sát và feature được bật.
Hubble không thay application business tracing.

---

## 44. Hubble flow, metrics và dữ liệu nhạy cảm

Hubble có thể cung cấp:

- flow stream qua API/CLI;
- Prometheus metrics;
- exporter ra flow logs;
- UI/service map.

Một flow buffer là cửa sổ gần hiện tại, không phải storage retention vô hạn.
Muốn audit dài hạn phải export có kiểm soát.

L7 flow có thể chứa:

- URL/query;
- headers;
- DNS name;
- identity nguồn/đích.

Cilium có cấu hình redaction cho L7 data, nhưng operator phải bật và kiểm thử.

Checklist:

- chỉ bật L7 visibility nơi cần;
- redact query/user info/header;
- filter trước export;
- bảo vệ Hubble Relay/API bằng mTLS/RBAC/network policy;
- đặt retention theo data classification.

---

## 45. OpenTelemetry eBPF Instrumentation – OBI

OBI là zero-code eBPF instrumentation của OpenTelemetry cho application và network
telemetry. Pipeline khái niệm:

```text
process discovery
  → eBPF probes
  → protocol/request events
  → transform + Kubernetes enrichment
  → OTLP metrics/traces hoặc Prometheus endpoint
```

Baseline 0.10 hỗ trợ chọn target theo executable, language, PID hoặc open port.

OBI phù hợp để:

- tạo coverage nhanh cho service chưa instrument;
- tạo RED metrics/traces generic;
- bổ sung network metrics;
- export theo OpenTelemetry conventions.

Giới hạn cốt lõi vẫn là zero-code:

- generic transaction visibility;
- không có custom business attributes/events;
- coverage phụ thuộc language/protocol/TLS/kernel/privilege.

---

## 46. Beyla và quá trình chuyển sang OBI

Grafana Beyla là nguồn gốc quan trọng của OBI. Trong hệ sinh thái hiện tại, cần đọc
release/migration docs của distribution đang dùng thay vì giả định tên binary và
biến môi trường luôn giống nhau.

Về kiến trúc, các khái niệm vẫn tương tự:

- application discovery;
- eBPF tracers;
- Kubernetes decorator;
- metrics/traces exporter;
- network flow mode;
- internal health metrics.

Khi đánh giá migration:

- so sánh config schema và environment variables;
- kiểm tra semantic conventions/metric names;
- kiểm tra span identity và sampling;
- so sánh capability;
- canary song song nhưng tránh export duplicate;
- dashboard/rule phải hỗ trợ giai đoạn chuyển đổi.

Tên dự án thay đổi không làm biến mất yêu cầu compatibility và security review.

---

## 47. Chọn Hubble, OBI, profiler hay bpftrace

| Câu hỏi chính | Công cụ phù hợp đầu tiên |
|---|---|
| Pod nào nói chuyện với pod nào, flow bị drop vì sao? | Cilium/Hubble |
| HTTP/gRPC RED telemetry không sửa app | OBI |
| Function/call stack nào tiêu CPU | eBPF continuous profiler |
| Giả thuyết kernel/syscall trong 10 phút | bpftrace/BCC tool |
| Business transaction và custom field | OTel SDK/manual |
| Packet filtering tốc độ cao | Cilium/XDP/tc product phù hợp |

Có thể dùng nhiều công cụ, nhưng phải lập **hook inventory**:

```text
node → hook/target → owner → purpose → frequency → privilege → exporter
```

Nếu không, các agent dễ trùng coverage, tranh tài nguyên và tạo telemetry duplicate.

---

## 48. Capability và least privilege

Linux hiện đại tách một số quyền khỏi `CAP_SYS_ADMIN`, nhưng capability cần thiết
phụ thuộc feature:

| Capability | Lý do thường gặp |
|---|---|
| `CAP_BPF` | privileged BPF operations |
| `CAP_PERFMON` | tracing/perf operations |
| `CAP_NET_ADMIN` | tc và network administration |
| `CAP_NET_RAW` | raw/packet socket |
| `CAP_SYS_PTRACE` | đọc process metadata/mapping |
| `CAP_CHECKPOINT_RESTORE` | một số `/proc/.../map_files` access |
| `CAP_DAC_READ_SEARCH` | vượt file read/search checks cần thiết |
| `CAP_SYS_RESOURCE` | locked-memory behavior trên kernel cũ |
| `CAP_SYS_ADMIN` | fallback hoặc một số uprobe/library paths |

Không copy danh sách capability từ blog cũ. Lấy danh sách của đúng version/mode,
bật fail-fast khi thiếu và loại bỏ quyền không dùng.

---

## 49. Root không đồng nghĩa với mọi quyền trong container

Container chạy UID 0 vẫn bị giới hạn bởi:

- capability bounding set;
- seccomp;
- AppArmor/SELinux;
- user namespace;
- host PID/network namespace;
- filesystem mounts;
- kernel lockdown;
- managed Kubernetes node policy.

Một pod eBPF thường cần một số access:

```text
hostPID: true
/proc host
/sys/kernel/btf
/sys/fs/bpf
debugfs/tracing nếu tool cần
network interface/host network tùy mode
```

Mỗi mount tăng khả năng quan sát host và blast radius. Đặt agent trong namespace
riêng, ServiceAccount tối thiểu, image ký/pin digest và admission policy rõ.

---

## 50. Unprivileged BPF, perf policy và kernel lockdown

Các control quan trọng:

```bash
sysctl kernel.unprivileged_bpf_disabled
sysctl kernel.perf_event_paranoid
cat /sys/kernel/security/lockdown 2>/dev/null
```

`kernel.unprivileged_bpf_disabled` có thể chặn `bpf()` đối với process không có
`CAP_BPF`/quyền tương ứng. Giá trị `1` là disable không thể bật lại cho tới reboot;
`2` có thể được admin đổi.

`kernel.perf_event_paranoid` điều khiển perf/tracing cho user không có
`CAP_PERFMON`; distribution có thể đặt policy chặt hơn upstream.

Kernel lockdown và secure boot policy có thể hạn chế tracing/kernel memory access.
Không hạ security control toàn fleet chỉ để agent khởi động. Xác định feature nào
cần, đánh giá risk rồi cấu hình có chủ đích.

---

## 51. bpffs, pinning và bpf_link

BPF objects thường sống theo file descriptor. Pinning đưa reference vào bpffs:

```text
/sys/fs/bpf/...
```

Nhờ pinning:

- map/program tồn tại khi loader process restart;
- process khác có thể mở lại object;
- state có thể được giữ qua upgrade có kiểm soát.

Rủi ro:

- stale pinned map giữ memory;
- schema map mới không compatible;
- object cũ vẫn attached;
- hai agent cùng nhận ownership.

`bpf_link` gom program-attachment lifecycle thành object quản lý tốt hơn ở hook
được hỗ trợ. Upgrade cần:

1. nhận diện owner/version;
2. kiểm tra map schema;
3. attach new;
4. chuyển traffic/event nếu cần;
5. detach/unpin old;
6. xác minh không còn orphan.

---

## 52. Kernel compatibility matrix

Không chỉ ghi “Linux 5.x+”. Matrix production nên có:

| Dimension | Ví dụ |
|---|---|
| Distribution | Ubuntu, RHEL, Bottlerocket |
| Kernel build | upstream/LTS/vendor backport |
| Architecture | x86_64, arm64 |
| BTF | có `/sys/kernel/btf/vmlinux` |
| Program type | tracing, tc, XDP, LSM |
| Attach mechanism | link, trampoline, kprobe/uprobe |
| Helper/kfunc | feature thực tế |
| Security | seccomp, lockdown, perf policy |
| Runtime | containerd, cgroup v1/v2 |

Startup nên chạy feature detection và report:

```bash
bpftool feature probe
bpftool btf show
bpftrace --info
```

Version comparison chỉ là bước lọc ban đầu vì vendor backport có thể thêm/bớt
feature.

---

## 53. Symbol, debug information và build identity

Raw stack/address cần symbolization:

```text
address
  + process memory map
  + executable/shared object
  + build ID
  + symbol/debug file
  → function/file/line
```

Failure mode:

- binary stripped;
- artifact đã bị xóa;
- build ID không khớp;
- JIT code;
- container image không còn local;
- kernel symbol bị hạn chế;
- frame pointer/unwind metadata thiếu.

Production pipeline nên:

- giữ symbol artifact theo build ID;
- không label profile bằng raw container path;
- cache có TTL/size;
- đo symbolization failure;
- bảo vệ source path/function nếu nhạy cảm.

Không gọi profile “unknown” là bằng chứng eBPF không lấy được sample; có thể chỉ là
symbol pipeline hỏng.

---

## 54. Mô hình overhead đầy đủ

Tổng chi phí:

```text
kernel hook execution
+ map lookup/update contention
+ event copy/buffer notification
+ user-space consume/parse
+ metadata discovery/enrichment
+ symbolization/protocol parsing
+ batching/compression/export
+ backend ingest/index/query
```

Các biến chi phối:

- event rate;
- số hook;
- số CPU;
- bytes mỗi record;
- map entries;
- stack depth;
- sampling frequency;
- cardinality;
- backend latency.

Đo trước/sau trên cùng workload:

- application throughput/p50/p99;
- node CPU/system CPU;
- agent CPU/RSS;
- softirq/network drop;
- buffer loss;
- export bytes;
- backend series/span/profile volume.

---

## 55. Filter sớm, aggregate sớm, enrich muộn

Pipeline tối ưu thường:

```text
kernel:
  filter target
  → extract tối thiểu
  → aggregate hoặc emit bounded record

user space:
  enrich metadata
  → redact
  → sample/rate limit
  → batch/export
```

Lý do:

- kernel hot path phải ngắn;
- Kubernetes lookup/string processing phù hợp user space;
- giảm event copy sớm giúp toàn pipeline;
- config map cho phép agent cập nhật filter mà không rebuild program.

Ví dụ filter:

- cgroup allowlist;
- target PID;
- port/protocol;
- duration threshold;
- error-only;
- probabilistic sampling với cap.

Filter phải có version/metric để operator biết dữ liệu biến mất do policy nào.

---

## 56. Map pressure và cardinality

Hai loại cardinality khác nhau:

### Kernel map cardinality

Quá nhiều key làm:

- update fail;
- LRU churn;
- memory tăng;
- latency lookup tăng;
- mất state pairing.

### Backend label/attribute cardinality

Raw key như:

- PID/TID;
- client IP/port;
- URL path;
- DNS name;
- container ID;
- trace ID;

có thể tạo series/index explosion.

Giải pháp:

- bounded key space;
- per-CPU counter;
- normalize route/status;
- event detail chỉ vào logs/traces có sampling;
- metric không mang ID độc nhất;
- budget riêng cho map entries và active time series.

---

## 57. Buffer loss và backpressure

Kernel ring buffer không chờ exporter. Khi downstream chậm:

```text
backend chậm
  → exporter queue tăng
  → event processor chậm
  → ring consumer chậm
  → reservation/output fail
  → mất event tại nguồn
```

Cần metric ở từng ranh giới:

- eBPF reserve/output failure;
- ring/perf lost events;
- internal channel utilization/drop;
- processor latency;
- exporter queue size/drop/retry;
- backend reject/throttle.

Không retry kernel event đã mất vì event không còn tồn tại. Giải pháp là giảm dữ
liệu, tăng/bố trí buffer hợp lý và sửa downstream.

Buffer lớn chỉ kéo dài thời gian trước khi mất dữ liệu và dùng thêm memory; nó
không chữa throughput mismatch kéo dài.

---

## 58. Privacy và data minimization

eBPF có vị trí quan sát rộng nên có thể thấy:

- process arguments;
- file paths;
- network endpoints;
- DNS names;
- HTTP headers/query;
- database statement;
- plaintext quanh TLS library;
- user/kernel stack/function.

Data policy cần định nghĩa:

| Field | Thu? | Redact/hash? | Retention | Ai được query? |
|---|---|---|---|---|
| URL route | có | normalize | trung bình | engineering |
| Query string | mặc định không | redact | ngắn | hạn chế |
| Header auth | không | drop tại nguồn | không lưu | không ai |
| Process args | allowlist | redact secret | ngắn | SRE/security |
| Stack | có chọn lọc | source path policy | profile retention | engineering |

Redact ở backend là quá muộn nếu secret đã đi qua agent/network/queue.

---

## 59. Security và supply-chain threat model

Một agent có quyền load BPF/đọc host process là mục tiêu giá trị cao.

Threat model:

- image bị thay thế;
- config độc hại mở rộng target/payload;
- exporter endpoint bị đổi;
- RBAC cho phép đọc secret không cần thiết;
- BPF object không đúng phiên bản;
- debug endpoint lộ raw event;
- stale privileged pod tồn tại sau migration.

Control:

- pin image digest và verify signature/SBOM;
- read-only root filesystem;
- drop capability không cần;
- signed/versioned config;
- mTLS cho export;
- network egress allowlist;
- audit config/upgrade;
- admission policy;
- secret không đặt trong argv;
- cleanup job cho orphan object có ownership check.

Verifier không bảo vệ khỏi loader user-space bị compromise.

---

## 60. Coexistence, conflict và duplicate telemetry

Nhiều program có thể cùng attach ở nhiều hook, nhưng không nên giả định mọi
combination vô hại.

Vấn đề:

- cùng uprobe target gây tương tác với binary/runtime;
- nhiều tc filter thay đổi priority/action;
- perf event sampling trùng;
- hai agent parse cùng request và xuất duplicate span;
- hai metadata resolver đặt service name khác nhau;
- map/bpffs path collision;
- upgrade cũ/mới cùng attach.

Inventory tối thiểu:

| Owner | Node set | Hook | Mode | Signal | Export destination |
|---|---|---|---|---|---|
| Cilium | all | XDP/tc/cgroup | datapath | flows | Hubble |
| OBI | canary | uprobe/tc | observe | metrics/traces | OTel |
| profiler | all | perf | sample | profiles | Pyroscope |

Mỗi signal phải có một ownership contract.

---

## 61. Debug bằng bpftool và công cụ hệ thống

Các lệnh read-only thường hữu ích:

```bash
bpftool feature probe
bpftool prog show
bpftool map show
bpftool link show
bpftool btf show
bpftool net show
```

Khi có ID:

```bash
bpftool prog show id <ID>
bpftool prog dump xlated id <ID> linum
bpftool map dump id <MAP_ID>
```

Kết hợp:

```bash
mount | grep bpf
ls -la /sys/fs/bpf
cat /proc/sys/kernel/unprivileged_bpf_disabled
cat /proc/sys/kernel/perf_event_paranoid
journalctl -u <agent>
```

Không xóa/unpin object chỉ vì “trông lạ”. Xác định owner, attachment và rollback
impact trước mọi thao tác destructive.

---

## 62. Lab bpftrace an toàn

Liệt kê trước khi attach:

```bash
sudo bpftrace -l 'tracepoint:syscalls:sys_enter_execve'
```

Đếm process `exec` theo command trong cửa sổ 10 giây:

```bash
sudo bpftrace -e '
tracepoint:syscalls:sys_enter_execve
{
  @[comm] = count();
}

interval:s:10
{
  print(@);
  clear(@);
  exit();
}'
```

Điểm an toàn của lab:

- dùng tracepoint thay internal kprobe;
- aggregate trong map thay `printf` từng event;
- tự dừng sau 10 giây;
- không đọc payload;
- không thay đổi network action.

Trước production vẫn phải test đúng kernel, load và event rate. `sudo` trong lab
không phải deployment security design.

---

## 63. Test và rollout production

Test pyramid:

```text
unit:
  parser, aggregation, metadata rules

BPF self/integration:
  verifier load, map behavior, synthetic event

kernel matrix:
  distro × kernel × arch × security config

workload:
  HTTP/TLS/gRPC/DNS/process lifecycle

performance:
  baseline vs enabled ở expected peak

canary:
  node pool/service nhỏ
```

Rollout:

1. deploy disabled hoặc discovery-only;
2. xác minh feature/capability;
3. bật một signal trên canary;
4. đo app/node/agent/backend;
5. kiểm tra semantic và duplicate;
6. mở rộng theo node pool;
7. giữ kill switch;
8. kiểm tra orphan sau upgrade/rollback.

Không rollout DaemonSet privileged toàn cluster chỉ vì lab một node chạy được.

---

## 64. Production checklist và câu hỏi tự kiểm tra

### Checklist

- [ ] Câu hỏi observability và hook được ghi rõ.
- [ ] Ưu tiên interface ổn định nhất đủ semantic.
- [ ] Có kernel/distro/architecture compatibility matrix.
- [ ] Startup feature probe và fail rõ theo node.
- [ ] Capability/mount/host namespace đã security review.
- [ ] Kernel program có filter, bounded maps và bounded records.
- [ ] Có metric map update failure, lost event và attach failure.
- [ ] Cardinality budget cho metrics/traces/events/profiles.
- [ ] Payload/PII redaction diễn ra trước export.
- [ ] Agent có CPU, memory, queue và export SLO.
- [ ] Có hook inventory, owner và duplicate policy.
- [ ] Image/config được pin, ký và audit.
- [ ] Canary đo application p99 và node overhead.
- [ ] Có kill switch, rollback và orphan cleanup.
- [ ] Runbook phân biệt no-event, filter, attach fail và data loss.

### Câu hỏi tự kiểm tra

1. Vì sao verifier accepted không đồng nghĩa overhead thấp?
2. Program type khác attach type ở đâu?
3. Khi nào per-CPU map tốt hơn shared hash?
4. Ring buffer đầy thì producer có block không?
5. BTF và CO-RE giải quyết phần nào của portability?
6. Vì sao tracepoint thường bền hơn kprobe?
7. fentry/fexit cần điều kiện gì?
8. Uprobe quan sát TLS có rủi ro privacy nào?
9. XDP và tc nằm ở đâu trong packet path?
10. Cgroup ID được enrich thành service name như thế nào?
11. Vì sao không export mọi syscall?
12. Hubble khác application tracing ở đâu?
13. OBI nên kết hợp manual OTel instrumentation thế nào?
14. Những capability nào phụ thuộc mode?
15. Làm sao phát hiện buffer loss?
16. Map cardinality khác backend cardinality thế nào?
17. Tại sao tăng buffer không sửa backpressure kéo dài?
18. Khi hai eBPF agent cùng chạy, inventory cần ghi gì?
19. Canary phải đo impact nào ngoài CPU agent?
20. Rollback làm sao tránh program/map bị orphan?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Linux kernel và tooling

- [Linux kernel BPF documentation](https://docs.kernel.org/bpf/)
- [BPF maps](https://docs.kernel.org/bpf/maps.html)
- [BPF ring buffer](https://docs.kernel.org/bpf/ringbuf.html)
- [BPF Type Format – BTF](https://docs.kernel.org/bpf/btf.html)
- [libbpf overview và CO-RE](https://docs.kernel.org/bpf/libbpf/libbpf_overview.html)
- [Program types và ELF sections](https://docs.kernel.org/bpf/libbpf/program_types.html)
- [Linux capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [`bpf(2)`](https://man7.org/linux/man-pages/man2/bpf.2.html)
- [bpftrace 0.24 language](https://bpftrace.org/docs/release_024/language)

### Cilium, Hubble và OpenTelemetry

- [Cilium network observability với Hubble](https://docs.cilium.io/en/stable/observability/hubble/)
- [Hubble internals](https://docs.cilium.io/en/stable/internals/hubble/)
- [Cilium L7 protocol visibility và redaction](https://docs.cilium.io/en/stable/observability/visibility/)
- [OpenTelemetry eBPF Instrumentation – OBI](https://opentelemetry.io/docs/zero-code/obi/)
- [OBI configuration](https://opentelemetry.io/docs/zero-code/obi/configure/options/)
- [OBI troubleshooting](https://opentelemetry.io/docs/zero-code/obi/troubleshooting/)
- [Grafana Beyla security và capabilities](https://grafana.com/docs/beyla/latest/security/)

### Chủ đề tiếp theo

Sau eBPF observability, chủ đề mở rộng tiếp theo là:

> [**Grafana Mimir Deep Dive – distributed metrics architecture, tenancy,
> object storage, query path, capacity và production
> operations.**](grafana_mimir.md)

---

*Cập nhật lần cuối: 2026-07-29*
