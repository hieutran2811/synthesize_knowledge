---
title: "API & HTTP Observability – Từ Request đến Dependency"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# API & HTTP Observability – Từ Request đến Dependency

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát toàn bộ vòng đời HTTP request qua client, DNS/TCP/TLS,
> proxy/gateway, service, queue và dependency; từ đó phân biệt lỗi người dùng, lỗi contract,
> saturation và retry amplification.
>
> Baseline tham chiếu: HTTP Semantics hiện hành, **W3C Trace Context**, Prometheus 3.x và
> OpenTelemetry Semantic Conventions 1.43.x. HTTP semantic conventions đang stable nhưng vẫn
> cần pin instrumentation version và kiểm thử telemetry contract.
>
> Không log authorization header, cookie, token, request/response body hoặc URL query thô.
> Không bật body capture, debug logging hay traffic mirroring trên production khi chưa đánh giá
> privacy, cost và blast radius.
>
> Nên đọc trước:
> [Metrics Design](metrics_design.md),
> [Alerting & SLO](alerting_strategy.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Kubernetes Observability](kubernetes_observability.md) và
> [Incident Response](incident_response_observability.md).

---

## 1. Vì sao API observability không chỉ là status code?

Một request `200` vẫn có thể:

- trả dữ liệu sai hoặc rỗng;
- chậm hơn deadline của người dùng;
- được trả từ cache quá cũ;
- chỉ hoàn tất một phần;
- kích hoạt async job rồi job thất bại;
- bị client hủy nhưng server vẫn xử lý;
- tạo side effect trùng do retry.

Status code là một dimension, không phải toàn bộ outcome.

---

## 2. API contract trước telemetry

Ghi rõ:

- operation/route;
- request và response schema;
- authentication/authorization;
- success semantics;
- idempotency;
- timeout/deadline;
- rate limit;
- consistency/freshness;
- error taxonomy;
- version/deprecation.

Telemetry phải phản ánh contract thay vì ghi mọi dữ liệu có thể ghi.

---

## 3. Vòng đời request

```text
user/client
  → DNS
  → TCP/QUIC + TLS
  → CDN/WAF/load balancer
  → API gateway/ingress
  → application admission/queue
  → handler
  → cache/database/downstream
  → serialization
  → response transfer
```

Server handler latency không bao gồm mọi hop người dùng trải qua.

---

## 4. Client view và server view

Client thấy:

```text
DNS + connect + TLS + request upload
+ server/proxy time + response download + retry
```

Server thấy từ lúc request tới instrumentation boundary. So sánh hai phía để tìm network,
proxy hoặc client-side wait. Đồng bộ clock giúp timeline nhưng duration nên dùng monotonic clock.

---

## 5. SLI cốt lõi

- availability/success;
- request latency;
- throughput;
- correctness/freshness;
- dependency success/latency;
- saturation/concurrency;
- async completion nếu API chỉ nhận việc.

SLO nên theo user journey/operation, không chỉ toàn service.

---

## 6. Định nghĩa availability

Không mặc định mọi `4xx` là lỗi service hoặc mọi `2xx` là thành công.

Ví dụ:

- `401/403`: có thể là hành vi đúng hoặc auth outage;
- `404`: có thể đúng với lookup, sai với route vừa deploy;
- `429`: policy hoạt động nhưng người dùng bị từ chối;
- `202`: mới accepted, chưa hoàn tất business;
- `5xx`: thường server failure nhưng health endpoint có semantics khác.

Viết allowlist outcome theo route.

---

## 7. Latency SLO

Đo distribution, không chỉ average. Tách:

- server duration;
- client duration;
- time-to-first-byte;
- full response time;
- queue wait;
- dependency time;
- streaming duration.

Một endpoint tải file không nên dùng cùng latency objective với lookup JSON nhỏ.

---

## 8. Throughput

Theo dõi request/s và bytes/s theo:

- service;
- route template;
- method;
- status class/outcome;
- region/zone;
- client class hữu hạn.

Traffic giảm đột ngột có thể là outage upstream dù error rate bằng zero.

---

## 9. Correctness

Correctness SLI có thể là:

- expected field/result;
- freshness age;
- reconciliation;
- invariant;
- duplicate side effect;
- schema validation;
- business conversion.

Synthetic và business metric thường phát hiện lỗi mà RED metrics không thấy.

---

## 10. Mô hình nhiều lớp

```text
business outcome
  → API operation
  → framework/middleware
  → queue/thread/event loop
  → runtime
  → proxy/network
  → dependency
  → infrastructure
```

Mỗi lớp cần signal và owner; tránh đổ mọi lỗi cho “network”.

---

## 11. Identity model

Attributes/labels hữu ích:

```text
service.name
service.version
deployment.environment
http.request.method
http.route
http.response.status_code
server.address
```

Chọn theo semantic conventions hiện hành. Không tự tạo alias trùng nghĩa nếu instrumentation
đã cung cấp attribute chuẩn.

---

## 12. Route template, không phải raw path

Đúng:

```text
/users/{id}/orders/{orderId}
```

Sai cho metric/span name:

```text
/users/847291/orders/a8f1...
```

Raw path, query string và ID tạo cardinality cao, có thể chứa PII. Nếu router không resolve
được route, dùng fallback hữu hạn thay vì ghi URL nguyên bản.

---

## 13. Method và status

HTTP method có tập hữu hạn tương đối; status code cũng có thể quản trị. Nhưng cần:

- chuẩn hóa method không hợp lệ;
- status class cho overview;
- status code ở drill-down;
- outcome business riêng;
- không dùng error message làm label.

`GET 500` và `POST 500` có idempotency/retry risk khác nhau.

---

## 14. Server metrics

Bộ RED tối thiểu:

```text
request rate
error/outcome rate
duration histogram
```

Bổ sung:

- active requests;
- request/response size;
- queue time;
- timeout/cancel;
- rejected/load-shed;
- connection state;
- dependency calls.

---

## 15. Client metrics

Client instrumentation cần:

- request duration;
- DNS/connect/TLS nếu library expose;
- status/error type;
- retry/redirect;
- pool wait;
- active/idle connections;
- request/response size;
- destination logic;
- timeout/cancel.

Server không biết request chưa bao giờ tới được nó.

---

## 16. Histogram cho latency

Classic histogram cho phép aggregate bucket giữa instance:

```promql
histogram_quantile(
  0.99,
  sum by (le, service, route) (
    rate(http_server_request_duration_seconds_bucket[5m])
  )
)
```

Tên metric chỉ minh họa; dùng metric thực tế của instrumentation. Bucket phải bao quanh SLO
threshold và workload distribution.

---

## 17. Native và classic histograms

Prometheus native histograms giảm nhu cầu định nghĩa bucket cố định và hỗ trợ aggregate tốt,
nhưng cần kiểm tra:

- client/server compatibility;
- storage/query path;
- schema/bucket growth;
- recording rules;
- dashboard/alert;
- migration song song;
- cost.

Không bật chỉ vì “mới hơn” mà chưa kiểm thử chuỗi end-to-end.

---

## 18. Percentile khác average

Average che tail. Percentile từ summary phía client thường không aggregate đúng giữa instance;
histogram phù hợp hơn cho fleet aggregation.

Percentile cũng không cho biết bao nhiêu request vượt SLO rõ bằng:

```promql
sum(rate(duration_bucket{le="0.3"}[5m]))
/
sum(rate(duration_count[5m]))
```

---

## 19. Apdex và threshold ratio

Apdex hữu ích để tóm tắt satisfied/tolerating/frustrated, nhưng:

- threshold phải theo user expectation;
- không thay percentile hoặc full distribution;
- cần tránh đếm trùng cumulative buckets;
- route khác nhau có threshold khác nhau.

Threshold ratio thường dễ nối trực tiếp với SLO.

---

## 20. Error taxonomy

Phân biệt:

- DNS/connect/TLS;
- timeout/deadline;
- reset/EOF;
- protocol;
- authentication/authorization;
- rate limit;
- validation;
- dependency;
- server exception;
- business rejection;
- client cancellation.

Giữ `error.type` hữu hạn; exception message/stack trace ở logs/traces, không ở metric label.

---

## 21. Timeout và cancellation

Client timeout có thể xảy ra trước khi server trả response. Server có thể:

- nhận cancellation và dừng;
- bỏ qua và tiếp tục dùng tài nguyên;
- hoàn tất side effect rồi client retry.

Đo client timeout, server cancellation, orphan work và side-effect reconciliation.

---

## 22. Deadline budget

```text
user deadline
  > gateway
  + service queue/compute
  + downstream calls
  + retry margin
  + response transfer
```

Propagate deadline còn lại thay vì mỗi hop dùng timeout đầy đủ. Downstream timeout phải nhỏ
hơn upstream deadline đủ để trả lỗi/fallback có kiểm soát.

---

## 23. Retry amplification

Ba tầng mỗi tầng retry 3 lần có thể tạo tối đa:

```text
3 × 3 × 3 = 27 attempts
```

Theo dõi logical request và attempts riêng. Retry cần:

- idempotency;
- retryable taxonomy;
- exponential backoff;
- jitter;
- retry budget;
- remaining deadline.

---

## 24. Hedging

Hedged request gửi thêm attempt khi request đầu chậm để giảm tail latency. Nó tăng traffic và
có thể nhân side effect.

Chỉ dùng khi:

- operation an toàn/idempotent;
- downstream còn capacity;
- delay/budget được kiểm soát;
- cancel loser hoạt động;
- đo hedge win và added load.

---

## 25. Circuit breaker

Quan sát:

- state closed/open/half-open;
- calls accepted/rejected;
- failure/slow-call rate;
- transition;
- open duration;
- fallback success;
- downstream recovery.

Circuit breaker bảo vệ tài nguyên, không chữa dependency. Alert theo user impact và thời gian
open, không page mọi transition ngắn.

---

## 26. Concurrency

Little’s Law gợi ý:

```text
concurrency ≈ arrival_rate × average_time_in_system
```

Latency tăng làm concurrency tăng ngay cả khi QPS không đổi. Đo active requests theo route hoặc
class hữu hạn, worker/thread/event-loop saturation và configured limit.

---

## 27. Queueing

Tách:

- admission queue;
- thread-pool queue;
- connection-pool wait;
- downstream queue;
- async work queue.

Queue depth không có age/arrival/service rate khó diễn giải. Oldest age thường gần user impact
hơn.

---

## 28. Load shedding

Khi quá tải, từ chối sớm có kiểm soát có thể tốt hơn để mọi request timeout.

Đo:

- shed/reject rate và reason;
- affected priority/tenant;
- queue/concurrency;
- latency của request được nhận;
- retry amplification;
- recovery.

Client phải hiểu `429`/`503` và `Retry-After` khi contract dùng chúng.

---

## 29. Rate limiting

Phân biệt:

- global, tenant, user, token hoặc endpoint limit;
- allowed/denied;
- remaining/reset nếu expose;
- limiter dependency latency/error;
- fail-open/fail-closed;
- configuration change.

Không dùng raw user/token làm label.

---

## 30. Connection pool

Client pool metrics:

- active/idle/max;
- pending acquire;
- acquire duration/timeout;
- connection creation;
- max lifetime/idle close;
- validation failure;
- destination.

Pool exhausted làm request chờ trước network; server downstream có thể vẫn nhàn.

---

## 31. DNS, TCP và TLS

Đo khi có thể:

- DNS lookup/cache/error;
- connect duration/error;
- TCP retransmit/reset;
- TLS handshake/error;
- certificate expiry;
- connection reuse.

Connection churn làm tăng cả latency lẫn CPU. Correlate với deploy, DNS change, load balancer và
certificate rotation.

---

## 32. HTTP/1.1

Các failure mode:

- connection reuse sai;
- keep-alive mismatch;
- head-of-line theo connection/pipeline;
- connection count lớn;
- chunked/body không đọc hết;
- proxy timeout.

Theo dõi connections, requests/connection, response size và close/reset reason.

---

## 33. HTTP/2

Multiplexing giảm số connection nhưng có:

- stream concurrency limit;
- connection-level failure ảnh hưởng nhiều stream;
- flow control;
- reset/goaway;
- header compression;
- proxy downgrade.

Đo theo connection và stream; một connection “up” không chứng minh stream mới được nhận.

---

## 34. HTTP/3 và QUIC

HTTP/3 dùng QUIC/UDP, thay đổi handshake, migration và loss behavior. Quan sát:

- protocol negotiated;
- handshake;
- fallback sang HTTP/2;
- QUIC errors;
- packet loss;
- network/provider support;
- client population.

Không gộp mọi protocol khi so latency nếu rollout chưa đồng đều.

---

## 35. CDN, proxy và load balancer

Cần signal theo hop:

- request/error/latency;
- upstream connect/response;
- retries;
- cache status/age;
- TLS;
- backend selection;
- health check;
- bytes;
- config version.

`502/504` tại proxy cần phân biệt không kết nối được upstream với upstream trả lỗi.

---

## 36. API gateway và ingress

Gateway còn thực hiện auth, rate limit, transformation, routing và policy. Theo dõi:

- policy latency/error;
- route match;
- upstream cluster;
- request/response transformation;
- rejected reason;
- config propagation;
- gateway saturation;
- per-tenant fairness.

Gateway success nhưng downstream business failure vẫn cần trace.

---

## 37. W3C Trace Context

`traceparent` mang trace ID, parent ID, flags và version; `tracestate` mang vendor-specific
context. Qua trust boundary:

- validate input;
- giới hạn header;
- không chứa PII;
- chống abuse;
- có thể restart trace theo policy;
- vẫn giữ request correlation phù hợp.

Sampling flag là gợi ý, không phải authorization.

---

## 38. HTTP client và server spans

Server span mô tả inbound request; client span mô tả outbound request. Span name nên dùng route
template hoặc operation low-cardinality theo semantic conventions.

Ghi:

- method;
- route;
- status;
- server/destination;
- duration;
- error type;
- network/protocol attributes cần thiết.

Không biến raw URL thành span name.

---

## 39. Sampling

Metrics đo 100% aggregate; traces giữ subset chi tiết. Chiến lược:

- probability/head sampling có budget;
- tail sampling ưu tiên error/slow;
- giữ synthetic;
- exemplar từ histogram;
- tránh quyết định khác nhau làm trace vỡ;
- đo effective sample rate/drop.

Tail sampling cần memory, routing và decision latency.

---

## 40. Baggage

Baggage propagation qua nhiều service có thể gây:

- header growth;
- PII leakage;
- trust-boundary abuse;
- cardinality khi biến thành attributes;
- CPU/network overhead.

Chỉ allowlist business context thực sự cần, giới hạn kích thước và không tự động log mọi
baggage.

---

## 41. Structured logs

Log nên có:

- timestamp;
- severity;
- service/version;
- trace/span ID khi sampled/có context;
- route/method/status;
- stable error code;
- event/action;
- duration nếu hữu ích.

Stack trace ghi một lần ở boundary phù hợp; tránh mỗi layer log cùng exception.

---

## 42. Request ID và trace ID

Request ID hữu ích cho support và log correlation; trace ID nối distributed spans. Chúng có thể
khác nhau.

Không dùng trace ID làm Prometheus label hoặc Loki indexed label. Validate ID từ external
client; không tin nó như security identity.

---

## 43. Request và response size

Payload lớn gây:

- upload/download latency;
- proxy buffering;
- memory pressure;
- serialization CPU;
- retry cost;
- log cost.

Dùng histogram bytes theo route/method/outcome. Không ghi payload để đo size.

---

## 44. Streaming và long-lived HTTP

SSE, WebSocket và streaming response cần metric khác request ngắn:

- active streams/connections;
- time-to-first-item;
- message/frame rate;
- stream duration;
- disconnect/reconnect;
- backpressure;
- oldest unflushed item;
- bytes.

Request-duration histogram kết thúc sau hàng giờ không đủ cho health tức thời.

---

## 45. gRPC

gRPC dùng HTTP/2 nhưng semantics dựa trên service/method và gRPC status. HTTP `200` có thể đi
kèm gRPC application error.

Đo:

- RPC method/type;
- gRPC status;
- message count/size;
- deadline/cancel;
- stream duration;
- client/server latency;
- retry theo gRPC policy.

---

## 46. REST và GraphQL

REST nên aggregate theo route template. GraphQL thường đi qua một HTTP route nên cần operation
type/name đã được kiểm soát:

- không dùng arbitrary query text;
- allowlist persisted operation;
- đo resolver/dependency;
- query complexity/depth;
- partial errors;
- response size.

HTTP status một mình che GraphQL partial failure.

---

## 47. Authentication và authorization

Theo dõi:

- authn/authz latency;
- success/failure theo reason hữu hạn;
- identity-provider dependency;
- token validation/cache;
- key/certificate rotation;
- policy version;
- unusual denial spike.

Không ghi credential, token claim nhạy cảm hoặc subject ID vào metric.

---

## 48. Security và privacy

Telemetry policy phải xử lý:

- headers/cookies/query;
- IP/user agent;
- body;
- customer identifiers;
- error stack;
- geo;
- retention;
- cross-tenant access.

Sampling không phải privacy control: một request nhạy cảm bị sample vẫn là data exposure.

---

## 49. Versioning và deprecation

Quan sát adoption theo:

- API version;
- service version;
- client class/SDK version hữu hạn;
- deprecated route traffic;
- schema validation;
- compatibility error;
- sunset deadline.

Không label theo raw user agent. Parse thành family/version đã chuẩn hóa nếu thực sự cần.

---

## 50. Deploy correlation

Annotate:

- application version;
- feature flag;
- gateway route/policy;
- certificate/DNS;
- dependency release;
- autoscaling;
- config/schema.

So canary và baseline theo cùng traffic class; tránh kết luận từ sample size quá nhỏ.

---

## 51. Synthetic monitoring

Synthetic probe kiểm tra từ bên ngoài:

- DNS;
- TLS/certificate;
- routing;
- auth test account;
- critical API journey;
- response semantics;
- region.

Probe `/health` không thay business journey. Synthetic cần owner, secure secrets và không bị
sample/drop khỏi telemetry.

---

## 52. Real User Monitoring

RUM cho biết browser/mobile thực thấy:

- network/client latency;
- geography/device;
- frontend processing;
- API waterfall;
- cancellation;
- release impact.

RUM có consent/privacy/cardinality yêu cầu riêng. Nối frontend trace với backend qua trust
boundary, không expose internal metadata tùy tiện.

---

## 53. Error-budget burn

Multi-window, multi-burn-rate alert giúp bắt:

- outage nhanh;
- degradation kéo dài.

SLI query phải có:

- good/valid events;
- cùng aggregation;
- route/tenant scope rõ;
- low-traffic handling;
- missing-data policy;
- version-controlled test.

---

## 54. Dashboard hierarchy

```text
User journey/SLO
  → API operation/route
  → gateway/server version
  → queue/runtime
  → dependency
  → instance/node/zone
```

Overview: rate, success, latency distribution, saturation, changes. Drill-down: error taxonomy,
traces, logs, client/network và dependency.

---

## 55. Alert strategy

Page:

- SLO burn;
- widespread dependency/gateway failure;
- saturation/load shedding gây impact;
- certificate/DNS failure sắp hoặc đang xảy ra;
- telemetry mất ở phạm vi lớn.

Không page cho một instance `5xx` đơn lẻ nếu service vẫn đáp ứng SLO. Alert có owner, route,
region, version, runbook và dashboard link.

---

## 56. Dependency map

Service map từ traces hoặc metrics chỉ hữu ích khi:

- service identity chuẩn;
- client/server edges khớp;
- sampling bias được hiểu;
- async edge được mô hình đúng;
- external dependency không bị gộp sai;
- owner/catalog được nối.

Map đẹp không thay dependency SLO và runbook.

---

## 57. Capacity model

Bao gồm:

- QPS và burst;
- concurrency;
- latency/service time;
- request/response bytes;
- CPU/memory;
- connection/thread/event loop;
- dependency limits;
- retry/hedge;
- zone loss;
- rollout headroom.

Load balancer còn target không chứng minh downstream còn capacity.

---

## 58. Load test

Test cần giữ:

- route mix;
- payload distribution;
- auth/TLS;
- cache hit/miss;
- client think time;
- connection reuse;
- dependency behavior;
- retry/deadline;
- gradual ramp và spike.

Đầu ra là safe operating envelope và bottleneck, không chỉ max QPS.

---

## 59. Incident workflow

```text
1. Xác nhận user journey, region, route, version
2. Kiểm tra traffic/error/latency/SLO burn
3. So client, gateway và server view
4. Tách queue, handler và dependency
5. Kiểm tra retry, timeout, cancellation
6. Kiểm tra saturation/network/runtime
7. Correlate deploy/config
8. Mitigate có rollback và ghi evidence
```

Không query raw path/trace toàn bộ khi cardinality cao.

---

## 60. Partial failure

Một response có thể chứa dữ liệu từ nhiều dependency. Thiết kế telemetry cho:

- required/optional dependency;
- partial response;
- stale/cache fallback;
- degraded mode;
- field-level business outcome;
- fallback age;
- recovery.

`200 degraded=true` cần signal riêng nếu user contract bị giảm.

---

## 61. Multi-region

Quan sát:

- traffic split;
- per-region SLO;
- cross-region dependency;
- data freshness/consistency;
- DNS/global LB;
- failover decision;
- capacity sau failover;
- session/token behavior;
- RTO/RPO.

Global aggregate có thể xanh khi một region nhỏ hoàn toàn lỗi.

---

## 62. Telemetry pipeline health

Cần biết:

- metrics scrape/export;
- trace/log accepted/dropped;
- queue/retry;
- sampling;
- cardinality/sample limits;
- backend ingest/query;
- clock skew;
- missing service/version.

“Không thấy lỗi” không có nghĩa “không có lỗi” nếu instrumentation hoặc Collector vừa mất.

---

## 63. Governance và cardinality

Telemetry contract nên quy định:

- metric/span/log fields;
- route normalization;
- error taxonomy;
- PII classification;
- retention;
- ownership;
- budget series/bytes;
- semantic-convention version;
- compatibility tests.

Review instrumentation như API công khai: thay tên label phá dashboard, rule và SLO history.

---

## 64. Workshop, checklist và câu hỏi

### Workshop

1. Chọn một API journey quan trọng.
2. Vẽ mọi hop và deadline budget.
3. Tạo server/client RED metrics theo route template.
4. Propagate W3C Trace Context.
5. Mô phỏng downstream chậm và retry.
6. Kiểm tra dashboard, alert, trace/log correlation và PII.

### Checklist

- [ ] SLO theo user journey/operation.
- [ ] Raw path/query không làm label/span name.
- [ ] Client và server latency đều có.
- [ ] Histogram bucket bao quanh SLO.
- [ ] Timeout/deadline/retry budget được instrument.
- [ ] Queue/concurrency/pool có saturation signal.
- [ ] Gateway và dependency có coverage.
- [ ] Trace context qua trust boundary an toàn.
- [ ] Logs không chứa credential/body mặc định.
- [ ] Deploy/config được annotate.
- [ ] Telemetry pipeline có self-monitoring.

### Câu hỏi

1. Vì sao `200` chưa đủ chứng minh success?
2. Client duration dài hơn server duration vì đâu?
3. Vì sao raw path gây cardinality và privacy risk?
4. Summary percentile có aggregate giữa instance được không?
5. Retry ba tầng có thể khuếch đại thế nào?
6. Deadline downstream nên quan hệ với upstream ra sao?
7. Pool wait có xuất hiện trong server metric không?
8. HTTP `200` có chứng minh gRPC success không?
9. Sampling có phải privacy control không?
10. Streaming API cần SLI nào khác request ngắn?
11. Synthetic health khác business journey thế nào?
12. Telemetry mất có thể tạo false green ra sao?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### HTTP và tracing

- [RFC 9110 – HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110)
- [RFC 9112 – HTTP/1.1](https://www.rfc-editor.org/rfc/rfc9112)
- [RFC 9113 – HTTP/2](https://www.rfc-editor.org/rfc/rfc9113)
- [RFC 9114 – HTTP/3](https://www.rfc-editor.org/rfc/rfc9114)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [OpenTelemetry HTTP semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/)
- [OpenTelemetry HTTP spans](https://opentelemetry.io/docs/specs/semconv/http/http-spans/)
- [OpenTelemetry HTTP metrics](https://opentelemetry.io/docs/specs/semconv/http/http-metrics/)

### Prometheus

- [Prometheus histograms and summaries](https://prometheus.io/docs/practices/histograms/)
- [Prometheus instrumentation](https://prometheus.io/docs/practices/instrumentation/)
- [Prometheus alerting practices](https://prometheus.io/docs/practices/alerting/)

Chủ đề tiếp theo:
[**Frontend & Real User Monitoring**](frontend_rum_observability.md) – Core Web Vitals,
browser errors, sessions, releases, frontend traces, privacy, synthetic monitoring và nối
trải nghiệm người dùng với backend.

---

*Cập nhật lần cuối: 2026-07-30*
