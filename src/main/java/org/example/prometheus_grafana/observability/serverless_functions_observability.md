# Serverless & Functions Observability – Từ Event Source đến Business Outcome

> Mục tiêu của bài này là quan sát function qua toàn bộ vòng đời: event được nhận và chờ,
> platform cấp execution environment, runtime khởi tạo, handler chạy, retry/DLQ và business
> outcome. “Invocation thành công” không tự chứng minh event chỉ xử lý một lần hoặc workflow
> đã hoàn tất.
>
> Baseline tham chiếu: OpenTelemetry FaaS Semantic Conventions hiện hành và mô hình chung của
> AWS Lambda, Azure Functions, Google Cloud Functions/Cloud Run functions. Metric và billing
> semantics khác theo provider/plan; kiểm tra tài liệu đúng region, runtime và thời điểm.
>
> Không replay event, xóa queue/DLQ, tăng concurrency, đổi retry/timeout, bật payload logging
> hoặc cấp quyền rộng trên production chỉ để điều tra.
>
> Nên đọc trước:
> [API & HTTP Observability](api_http_observability.md),
> [Messaging & Kafka Observability](messaging_kafka_observability.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md) và
> [Telemetry Governance](telemetry_governance_finops.md).

---

## 1. Vì sao serverless observability khó?

Platform ẩn server nhưng không xóa failure mode:

- cold start;
- concurrency/quota;
- event queue;
- retry/duplicate;
- runtime freeze/reuse;
- timeout;
- dependency/network;
- telemetry chưa flush;
- cost theo invocation/duration/resource.

Ta ít nhìn thấy host nhưng vẫn chịu hậu quả của nó.

---

## 2. Xác định đúng phạm vi

“Serverless” có thể là:

- function per event;
- HTTP function;
- container scale-to-zero;
- durable/orchestrated function;
- edge function;
- managed workflow;
- managed event source.

Không dùng cùng cold-start, concurrency và timeout model cho mọi sản phẩm.

---

## 3. Invocation lifecycle

```text
event created
→ platform accepted/queued
→ environment allocated
→ runtime + extension init
→ handler
→ dependency/side effect
→ response/ack
→ extension shutdown/freeze
```

Đo riêng queue age, init, handler và post-runtime work.

---

## 4. Trigger taxonomy

Các trigger chính:

- HTTP/RPC;
- queue/pub-sub;
- stream;
- object/storage event;
- database change;
- schedule/timer;
- workflow/orchestrator;
- direct invocation.

Mỗi loại có acknowledgement, retry, ordering và batching khác nhau.

---

## 5. Synchronous và asynchronous

Synchronous caller chờ response và thường sở hữu deadline. Asynchronous platform nhận event
trước rồi invoke/retry sau.

Phân biệt:

```text
request accepted
function invoked
handler succeeded
event acknowledged
business outcome completed
```

---

## 6. SLO

SLI phù hợp:

- synchronous availability/latency;
- async end-to-end age;
- business completion;
- dropped/DLQ events;
- duplicate/reconciliation;
- timeout/throttle;
- recovery/catch-up;
- cost per outcome.

Invocation count/error là dependency indicators.

---

## 7. Mô hình nhiều lớp

```text
business workflow
→ event source/gateway
→ platform admission/queue
→ scheduler/scaler
→ execution environment/runtime
→ handler
→ dependencies
→ destination
```

Function logs chỉ nhìn được một phần.

---

## 8. Identity

Chuẩn hóa:

```text
cloud provider/account/project
region
function name
version/alias/revision
runtime
trigger type
environment
team
```

Không label theo invocation/event/request ID.

---

## 9. Platform và custom metrics

Platform metrics thấy invocation, duration, error, throttle, concurrency và queue tùy dịch vụ.
Application metrics biết:

- business result;
- dependency;
- idempotency;
- batch records;
- partial failure;
- freshness.

Cần cả hai, với timestamps và dimensions tương thích.

---

## 10. Metrics, logs và traces

- metrics: fleet/SLO/saturation;
- logs: exception/platform lifecycle;
- traces: trigger → function → dependency;
- business ledger/reconciliation: correctness.

Không dùng log count thay request/error counter nếu log sampling/drop có thể xảy ra.

---

## 11. Cold start

Cold start thường gồm platform/environment/runtime và application initialization trước handler.
Đo:

- cold-start rate;
- init duration;
- total caller latency;
- runtime/package size;
- version/region;
- burst/concurrency;
- dependency initialization.

Không suy ra cold start chỉ từ latency cao.

---

## 12. Init khác handler

```text
total invocation path
  = queue/admission
  + init nếu cold
  + handler
  + platform/extension overhead
```

Provider metric `Duration` có thể không bao gồm mọi phần. Ghi công thức trên dashboard.

---

## 13. Warm environment reuse

Warm environment có thể giữ:

- SDK client/connection;
- cache;
- static state;
- temporary files;
- stale credential/config;
- memory leak.

Không dựa vào reuse để bảo đảm correctness vì platform có thể thay environment bất kỳ lúc nào.

---

## 14. Provisioned/minimum instances

Pre-initialization giảm cold start nhưng tăng cost và không bảo đảm mọi invocation warm khi
traffic vượt provisioned capacity.

Theo dõi:

- configured capacity;
- utilization;
- spillover;
- cold starts;
- idle cost;
- alias/revision routing;
- scale lag.

---

## 15. Concurrency

Concurrency là số invocation đang chạy, nhưng giới hạn có thể ở:

- function;
- version/alias;
- account/project/region;
- instance;
- downstream;
- event source.

Shared quota tạo noisy-neighbor giữa functions.

---

## 16. Throttling

Throttled request/event không luôn xuất hiện trong invocation/error metric. Phân biệt:

- concurrency;
- scaling rate;
- CPU/memory/disk nếu platform expose;
- rate quota;
- downstream quota;
- event-source poller.

Alert theo user/event age và remaining quota.

---

## 17. Scaling behavior

Auto-scaling có tốc độ và trần. Burst có thể:

```text
queue tăng
→ environments khởi tạo
→ dependency bị fan-out
→ throttle/retry
```

Theo dõi arrival rate, concurrency, cold starts, scale lag và downstream capacity.

---

## 18. Queue/event age

Với async workload, oldest age gần SLO hơn queue depth:

```text
age = now - event_created_or_accepted_time
```

Phân biệt source age, platform async age và handler application queue age.

---

## 19. Timeout

Timeout có thể xảy ra ở:

- gateway/caller;
- platform function limit;
- event-source visibility/lease;
- handler dependency;
- workflow.

Propagate remaining deadline; giữ thời gian cleanup/ack. Timeout sau side effect có thể gây
duplicate khi retry.

---

## 20. Memory và CPU

Một số platform gắn CPU với memory tier. Đo:

- configured memory;
- peak/used memory;
- OOM;
- CPU duration/throttle nếu có;
- GC;
- duration/cost theo tier;
- architecture/runtime.

Memory cao hơn đôi khi chạy nhanh và rẻ hơn; benchmark workload thật.

---

## 21. Ephemeral storage

Theo dõi:

- configured/used/free;
- write/read latency;
- file count;
- cleanup;
- download/unzip;
- cache reuse;
- disk-full error.

Temporary filesystem không phải durable storage và có thể tồn tại trong warm reuse.

---

## 22. Network và private connectivity

VPC/VNet attachment, NAT, DNS, TLS và private endpoint có thể tăng init/request latency.
Quan sát:

- DNS/connect/TLS;
- ENI/private connector nếu provider expose;
- NAT/SNAT exhaustion;
- cross-zone/region;
- egress;
- security policy.

---

## 23. Connection reuse

Khởi tạo database/HTTP client ngoài handler có thể tái sử dụng khi warm, nhưng cần:

- max lifetime;
- stale connection detection;
- credential rotation;
- pool/concurrency sizing;
- retry;
- server connection limit.

Auto-scale hàng nghìn environment có thể tạo connection storm.

---

## 24. Dependencies

Instrument database, cache, API, queue và storage với:

- latency/error/timeout;
- pool;
- retry;
- quota/throttle;
- request size;
- idempotency;
- remaining deadline.

Function duration thường chỉ là tổng của nhiều dependency waits.

---

## 25. Error taxonomy

Tách:

- platform admission/throttle;
- init/import/config;
- handler exception;
- timeout/OOM;
- permission/auth;
- serialization/schema;
- dependency;
- destination delivery;
- event expired/dropped;
- telemetry export.

“Errors > 0” không chỉ ra owner.

---

## 26. Retry semantics

Retry có thể do caller, platform, event source, SDK và application cùng thực hiện. Ghi:

- attempt;
- source;
- backoff/jitter;
- max attempts;
- event age/expiry;
- final outcome;
- duplicate.

Giới hạn retry budget qua toàn workflow.

---

## 27. Idempotency

At-least-once trigger yêu cầu side effect idempotent. Quan sát:

- idempotency key hit/conflict;
- dedup store latency/error;
- duplicate detected;
- replay window;
- final reconciliation;
- retention.

Không dùng invocation ID mới làm idempotency key của business event cũ.

---

## 28. DLQ và destinations

Theo dõi:

- delivery success/failure;
- DLQ depth/oldest age;
- error reason;
- retention;
- replay rate/outcome;
- owner;
- poison event.

Đẩy vào DLQ không phải business success.

---

## 29. Batch invocation

Một invocation có thể chứa nhiều records. Metric cần cả:

- invocation;
- batch size;
- records attempted/succeeded/failed;
- oldest record age;
- processing duration;
- bytes.

Invocation success có thể che record bị bỏ qua.

---

## 30. Partial batch failure

Nếu platform hỗ trợ partial response:

- trả đúng record identifiers;
- đo per-record outcome;
- không retry record đã thành công;
- kiểm tra ordering;
- giữ idempotency;
- xử lý poison record.

Sai contract có thể replay toàn batch.

---

## 31. Stream triggers

Theo dõi:

- iterator/record age;
- shard/partition lag;
- batch;
- parallelization;
- checkpoint;
- poison record;
- bisect/retry;
- ordering.

Một shard nóng không được giải quyết bằng tăng global concurrency đơn thuần.

---

## 32. Queue/pub-sub triggers

Cần:

- visible/ready depth;
- oldest age;
- in-flight;
- receive count;
- visibility/lease extension;
- redelivery;
- DLQ;
- consumer concurrency.

Visibility timeout phải lớn hơn processing hoặc được gia hạn an toàn.

---

## 33. HTTP triggers

Đo end-to-end:

```text
client → gateway → platform queue/init → handler → dependency
```

Thêm gateway status/latency, payload size, auth, cold start, client cancellation và streaming
semantics. Handler `200` không cứu caller đã timeout.

---

## 34. Scheduled functions

SLI:

- schedule delay;
- start/completion;
- duration;
- skipped/duplicate run;
- overlap;
- deadline;
- business rows/events processed;
- timezone/DST.

Scheduler fired không chứng minh job hoàn tất.

---

## 35. Storage/object events

Event có thể duplicate, reorder hoặc đến sau. Ghi:

- bucket/container logical class;
- event type;
- object version;
- age;
- size bucket;
- outcome;
- duplicate.

Không đưa object key/raw path vào metric.

---

## 36. Recursive invocation

Function tự kích hoạt qua output/event có thể tạo loop và bill storm. Guardrails:

- lineage/hop count;
- recursion detection;
- rate/concurrency limit;
- budget alert;
- destination separation;
- kill switch.

Theo dõi fan-out factor.

---

## 37. Event filtering

Filter tại source giảm invocation/cost nhưng có correctness risk. Đo:

- received/matched/dropped nếu platform cung cấp;
- filter version;
- schema mismatch;
- expected business count;
- change audit.

Reconciliation phát hiện event cần thiết bị lọc nhầm.

---

## 38. Trace-context propagation

HTTP dùng W3C Trace Context; messaging/event cần inject/extract qua metadata được hỗ trợ.
Batch/fan-out thường cần span links.

Không ghi full event payload. Test trigger adapter, retry, DLQ/replay và workflow propagation.

---

## 39. OpenTelemetry FaaS conventions

FaaS semantic conventions mô tả spans, metrics và exceptions nhưng hiện ở trạng thái
Development. Do đó:

- pin semconv/instrumentation;
- kiểm tra trigger mapping;
- version schema;
- canary;
- không hard-code dashboard vào experimental attribute không có migration plan.

---

## 40. Logs và invocation ID

Structured log:

- timestamp/severity;
- function/version;
- invocation/request ID;
- trace/span ID;
- trigger;
- attempt;
- stable error code;
- duration/outcome.

Invocation ID không làm metric label và không thay business event ID.

---

## 41. Telemetry export lifecycle

Function có thể freeze/terminate trước khi batch exporter flush. Chọn:

- provider integration/extension;
- bounded batch;
- synchronous flush chỉ khi cần;
- retry/buffer;
- shutdown hook không được bảo đảm tuyệt đối;
- export timeout ngắn hơn function deadline.

Đo accepted/dropped/export failure.

---

## 42. Layers, extensions và agents

Observability layer/extension thêm:

- init time;
- memory;
- CPU;
- post-runtime duration;
- network;
- package/version dependency.

Benchmark bật/tắt và pin version. Extension lỗi không nên chặn business handler nếu policy
không yêu cầu fail-closed.

---

## 43. Sampling

Cold/error/slow invocation hiếm cần được giữ nhưng tail sampling khó vì function ngắn và
Collector xa.

Kết hợp:

- metrics 100%;
- head sample budget;
- error/slow priority;
- exemplar;
- synthetic canary;
- platform trace sampling awareness.

---

## 44. Cardinality

Tránh labels:

- invocation/event ID;
- object key;
- raw route;
- tenant/user;
- exception message;
- queue message ID;
- dynamic function revision không chuẩn hóa.

Giữ function/version/trigger/region và business outcome hữu hạn.

---

## 45. Secrets và payload

Event/log/trace có thể chứa:

- credentials;
- payment/health data;
- object content;
- headers;
- environment variables;
- signed URLs.

Allowlist fields, redact tại source và bảo vệ DLQ/log backend. Không log toàn event khi lỗi.

---

## 46. IAM và least privilege

Function role cần quyền tối thiểu cho source, dependency, secret và telemetry. Quan sát:

- access denied;
- role/policy change;
- secret/KMS error;
- cross-account call;
- unusual resource access;
- expired credential.

Telemetry exporter không cần quyền business rộng.

---

## 47. Versions, aliases và revisions

Route traffic qua immutable version/alias/revision. Mọi signal cần exact version để:

- so canary;
- rollback;
- map artifact/config;
- tách cold start;
- biết provisioned capacity;
- group error.

`latest` là dimension điều tra kém.

---

## 48. Canary và weighted rollout

So:

- traffic share thực;
- cold-start bias;
- errors/latency;
- event source compatibility;
- business outcome;
- cost;
- sample size.

Async trigger không phải lúc nào hỗ trợ weighted routing giống HTTP.

---

## 49. Configuration observability

Theo dõi thay đổi:

- memory/timeout/concurrency;
- environment;
- runtime/architecture;
- layer/extension;
- trigger/filter;
- retry/DLQ;
- network/IAM;
- provisioned capacity.

Không export secret value; chỉ version/fingerprint an toàn.

---

## 50. Cost model

Chi phí có thể gồm:

- invocation;
- duration × resource;
- provisioned/min instances;
- requests/gateway;
- logs/traces/custom metrics;
- network egress;
- queue/storage/workflow;
- retries.

Cost spike là triệu chứng có thể do recursion, retry hoặc traffic hợp lệ.

---

## 51. Cost per outcome

```text
total workflow cost
/
successful business outcomes
```

Tính cả failed/retried invocations và shared services. Tối ưu duration không có ý nghĩa nếu làm
tăng failure hoặc duplicate.

---

## 52. Platform limits

Inventory:

- timeout;
- payload/batch;
- concurrency/scaling;
- memory/storage;
- deployment/package;
- environment variables;
- destinations;
- log/metric limits;
- API quotas.

Alert trước quota có thể quan sát; test failure cho limit cứng.

---

## 53. Multi-cloud portability

Chuẩn hóa business SLI và OTel resource identity, nhưng giữ provider-native detail riêng:

```text
portable: outcome, age, handler, dependency
native: concurrency, queue, cold-start/billing semantics
```

Đừng ép metric khác semantics thành cùng tên.

---

## 54. Durable functions

Workflow dài cần:

- execution state;
- checkpoint;
- replay;
- operation count;
- wall-clock duration;
- suspend/resume;
- timeout/cancel;
- persisted bytes;
- compensation.

Handler code có thể replay; telemetry phải tránh đếm business action trùng.

---

## 55. Orchestrator/state machine

Quan sát:

- workflow start/end;
- state transition;
- branch/fan-out;
- wait;
- retry;
- compensation;
- failed state;
- execution age;
- cost.

Nối span/log bằng workflow execution ID nhưng không dùng ID làm metric label.

---

## 56. Dashboard

```text
Business outcome/freshness
→ trigger/source queue
→ invocation/error/timeout
→ cold start/concurrency/throttle
→ handler/dependency
→ retry/DLQ
→ cost/version/change
```

Hiển thị platform metric delay và missing-data semantics.

---

## 57. Alerting

Page khi:

- synchronous SLO burn;
- async oldest age vượt objective;
- event dropped/DLQ chặn workflow;
- widespread throttle/timeout;
- recursion/cost runaway;
- dependency/platform outage.

Ticket cho cold-start/cost regression không khẩn cấp có owner.

---

## 58. Incident workflow

```text
1. Xác nhận trigger, version, region và business impact
2. Tách accepted/invoked/completed/outcome
3. Kiểm tra age, retry, DLQ
4. Kiểm tra cold start, concurrency, throttle
5. Tách init, handler, dependency
6. Correlate config/deploy/quota
7. Mitigate bằng traffic/concurrency/filter/rollback có kiểm soát
8. Theo dõi catch-up, duplicate và cost
```

---

## 59. Capacity và load test

Test:

- steady/burst;
- cold fleet;
- max concurrency;
- source backlog;
- batch size;
- dependency connection/quota;
- retries;
- payload;
- regional failure;
- telemetry overhead.

Kết quả phải có catch-up rate và downstream safe envelope.

---

## 60. Failure-mode tests

Mô phỏng có kiểm soát:

- cold start chậm;
- handler timeout/OOM;
- throttle;
- queue delay;
- partial batch;
- poison event;
- destination/DLQ failure;
- dependency/network;
- telemetry exporter;
- recursive loop guard.

---

## 61. Local/dev parity

Emulator/local runtime không tái hiện đầy đủ:

- platform queue/scaler;
- IAM;
- cold environment;
- network attachment;
- quota;
- freeze/reuse;
- billing;
- extensions.

Dùng dev account và integration test có budget ngoài unit/local tests.

---

## 62. Provider telemetry delay

Platform metrics/logs có aggregation và ingestion delay. Alert cần:

- correct period/statistic;
- missing data policy;
- high-resolution custom metric khi thật sự cần;
- cross-check synthetic/application;
- cost.

Không suy ra realtime từ metric publish theo phút.

---

## 63. Governance

Mỗi function cần:

- owner;
- trigger/data classification;
- SLO/RPO;
- timeout/retry/idempotency;
- concurrency quota;
- DLQ/runbook;
- cost budget;
- telemetry schema;
- lifecycle/deprecation.

Function nhỏ vẫn là production service.

---

## 64. Workshop, checklist và câu hỏi

### Workshop

1. Chọn một async function.
2. Vẽ event creation → source → invoke → outcome.
3. Tách queue age, init và handler.
4. Instrument per-record result/idempotency.
5. Mô phỏng throttle và partial batch.
6. Kiểm tra alert, DLQ replay, duplicate và cost.

### Checklist

- [ ] Sync/async và trigger semantics được ghi rõ.
- [ ] Business SLO không chỉ dùng invocation success.
- [ ] Cold start tách init/handler/total latency.
- [ ] Concurrency, scaling và quota có headroom.
- [ ] Event age, retry, duplicate và DLQ có signal.
- [ ] Batch có per-record outcome.
- [ ] Telemetry export chịu freeze/timeout.
- [ ] Payload/secret không vào logs/traces.
- [ ] Version/config/cost được correlate.
- [ ] Catch-up/failure đã được test.

### Câu hỏi

1. “Không quản server” có xóa capacity problem không?
2. Cold start và handler duration khác nhau thế nào?
3. Throttle có luôn nằm trong invocation error không?
4. Queue depth và oldest age trả lời khác gì?
5. Timeout sau side effect tạo duplicate ra sao?
6. Warm reuse có được dùng làm correctness guarantee không?
7. Batch success che partial failure thế nào?
8. Extension ảnh hưởng invocation ở đâu?
9. Vì sao FaaS semconv cần pin version?
10. Provisioned concurrency có bảo đảm mọi request warm không?
11. Cost per outcome khác cost per invocation thế nào?
12. Durable replay ảnh hưởng telemetry ra sao?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### OpenTelemetry

- [FaaS semantic conventions](https://opentelemetry.io/docs/specs/semconv/faas/)
- [FaaS spans](https://opentelemetry.io/docs/specs/semconv/faas/faas-spans/)
- [FaaS metrics](https://opentelemetry.io/docs/specs/semconv/faas/faas-metrics/)
- [AWS Lambda semantic conventions](https://opentelemetry.io/docs/specs/semconv/faas/aws-lambda/)

### Providers

- [AWS Lambda execution environment lifecycle](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html)
- [AWS Lambda metric types](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-metrics-types.html)
- [AWS Lambda concurrency](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-concurrency.html)
- [Azure Functions monitoring](https://learn.microsoft.com/azure/azure-functions/monitor-functions)
- [Google Cloud Run functions monitoring](https://cloud.google.com/functions/docs/monitoring)

Chủ đề tiếp theo:
[LLM & Generative AI Observability](llm_generative_ai_observability.md) – model calls, token
usage, TTFT, cost, RAG, agents, tools, evaluations, safety và privacy.

---

*Cập nhật lần cuối: 2026-07-30*
