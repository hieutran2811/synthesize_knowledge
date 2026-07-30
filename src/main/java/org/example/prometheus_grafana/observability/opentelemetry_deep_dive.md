# OpenTelemetry Deep Dive – Instrumentation, Context, Signals và Collector Pipeline

> Mục tiêu của bài này là hiểu cách **tạo telemetry đúng ngay từ application**, truyền đúng context qua hệ thống phân tán và vận hành pipeline OpenTelemetry có kiểm soát. Baseline tham chiếu: **OpenTelemetry Java API/SDK 1.64.x**, **Semantic Conventions 1.43.x** và **OpenTelemetry Collector 0.157.x**.

---

## 1. OpenTelemetry giải quyết bài toán gì?

OpenTelemetry, thường viết tắt là **OTel**, cung cấp:

- API để application và library tạo telemetry;
- SDK để xử lý, sample và export telemetry;
- semantic conventions để nhiều hệ thống dùng chung ngôn ngữ dữ liệu;
- OTLP để truyền telemetry theo một giao thức chuẩn;
- Collector để nhận, xử lý và chuyển telemetry đến backend.

Nó không phải là:

- database lưu metric;
- hệ thống tìm kiếm log;
- trace backend;
- dashboard;
- alert manager.

Mô hình đơn giản:

```text
Application
  │
  │ API / auto-instrumentation tạo telemetry
  ▼
OpenTelemetry SDK
  │
  │ OTLP
  ▼
OpenTelemetry Collector
  │
  ├── metrics ──▶ Prometheus-compatible backend
  ├── logs ─────▶ Loki hoặc log backend
  └── traces ───▶ Tempo hoặc trace backend
```

OpenTelemetry chuẩn hóa đường đi của dữ liệu. Backend vẫn chịu trách nhiệm lưu trữ, truy vấn, trực quan hóa và retention.

---

## 2. Mental model: telemetry là một distributed API

Một field telemetry không chỉ phục vụ người đang viết code. Nó có thể được dùng bởi:

- dashboard;
- alert rule;
- SLO;
- query điều tra sự cố;
- pipeline redaction;
- cost report;
- automation;
- một team khác.

Vì vậy, thay đổi:

```text
http.method → http.request.method
```

không đơn thuần là đổi tên field. Nó có thể làm hỏng dashboard và alert đang phụ thuộc vào tên cũ.

Hãy xem telemetry như một API phân tán:

```text
producer telemetry
        │
        ▼
schema + semantic contract
        │
        ▼
collector / backend / dashboard / alert / operator
```

Nguyên tắc:

> Instrumentation thay đổi shape của telemetry cũng cần review, rollout và migration giống thay đổi API.

---

## 3. Phân biệt API, SDK, instrumentation và Collector

| Thành phần | Trách nhiệm | Không nên làm thay |
|---|---|---|
| OTel API | Tạo span, measurement, context và log record | Export hoặc lưu dữ liệu |
| OTel SDK | Sampling, processing, aggregation, batching, export | Hiểu business semantics thay application |
| Auto-instrumentation | Quan sát framework/library phổ biến | Đo đầy đủ business outcome |
| Manual instrumentation | Bổ sung operation và business context | Thay thế toàn bộ auto-instrumentation |
| Collector | Receive, process, route và export | Sửa mọi telemetry sai từ source |
| Backend | Lưu, query, visualize và alert | Tạo context bị thiếu trong application |

Ví dụ:

- Java agent biết một HTTP request mất 320 ms;
- application mới biết request đó là thao tác `reserveInventory`;
- Collector có thể xóa `user.email`;
- Collector không thể đoán chính xác `order.outcome=insufficient_stock`.

Thiết kế tốt thường kết hợp:

```text
auto-instrumentation cho technical edges
              +
manual instrumentation cho business semantics
```

---

## 4. Signal và mức ổn định

OpenTelemetry hỗ trợ các signal chính:

- traces;
- metrics;
- logs;
- baggage để truyền context bổ sung.

Profiles đã xuất hiện trong hệ sinh thái nhưng còn phát triển nhanh. Không nên giả định mọi SDK, Collector distribution và backend đã hỗ trợ profiles giống nhau.

Với Java hiện tại:

- traces: stable;
- metrics: stable;
- logs: stable.

Tuy nhiên, “signal stable” không có nghĩa mọi instrumentation và mọi semantic convention đều stable. Cần kiểm tra riêng:

- API/SDK stability;
- semantic convention group stability;
- Collector component stability;
- backend compatibility.

---

## 5. Resource: “ai” tạo ra telemetry?

**Resource** mô tả entity tạo telemetry.

Ví dụ:

```text
service.namespace = commerce
service.name = checkout
service.version = 2026.07.29-8f2c1a
service.instance.id = 3ab5...
deployment.environment.name = production
k8s.cluster.name = prod-bkk
k8s.namespace.name = commerce
```

Phân biệt:

- resource attribute: tương đối ổn định cho entity;
- span/log/metric attribute: mô tả một operation hoặc measurement cụ thể.

Không nên đặt `order.id` vào Resource vì mỗi request có order khác nhau.

Nếu không cấu hình `service.name`, SDK có thể dùng `unknown_service` hoặc tên tương tự. Kết quả:

- service graph khó đọc;
- query phải đoán service;
- dữ liệu nhiều application có thể bị trộn;
- ownership không rõ.

---

## 6. Bộ nhận diện service chuẩn

Ba field quan trọng:

| Attribute | Ý nghĩa | Tính ổn định |
|---|---|---|
| `service.namespace` | Nhóm service, ví dụ domain hoặc product | Ổn định |
| `service.name` | Tên logic của service | Giống nhau giữa các replica |
| `service.instance.id` | Một instance cụ thể | Duy nhất giữa các instance đồng thời |

Ví dụ:

```text
commerce / checkout / pod-a
commerce / checkout / pod-b
```

Hai pod có:

- cùng `service.namespace`;
- cùng `service.name`;
- khác `service.instance.id`.

`deployment.environment.name` là môi trường như `production` hoặc `staging`. Nó không thay thế namespace và không tham gia quy tắc định danh service.

Tên cũ:

```text
deployment.environment
```

đã deprecated; dùng:

```text
deployment.environment.name
```

---

## 7. Cấu hình Resource bằng environment variable

Ví dụ Linux:

```bash
export OTEL_SERVICE_NAME=checkout
export OTEL_RESOURCE_ATTRIBUTES="service.namespace=commerce,service.version=2026.07.29,deployment.environment.name=production"
```

Ví dụ Kubernetes:

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: checkout
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: >-
      service.namespace=commerce,
      service.version=$(APP_VERSION),
      deployment.environment.name=production
```

Trong manifest thật, cần kiểm tra cơ chế expansion của platform. Kubernetes không tự mở rộng mọi kiểu biến theo cách shell làm.

Quy tắc vận hành:

- `service.name` do owner service quyết định;
- `service.version` lấy từ artifact hoặc commit đã deploy;
- environment name dùng vocabulary thống nhất;
- không để agent, sidecar và gateway ghi đè identity theo ba cách khác nhau.

---

## 8. Instrumentation Scope: “đoạn code nào” tạo telemetry?

Resource trả lời “entity nào tạo telemetry”.

Instrumentation Scope trả lời “instrumentation nào tạo record này”.

Scope được nhận diện bởi:

```text
(name, version, schemaUrl)
```

Ví dụ:

```text
name      = com.acme.checkout.payment
version   = 2.4.1
schemaUrl = https://opentelemetry.io/schemas/1.43.0
```

Scope hữu ích để:

- phân biệt auto và manual instrumentation;
- tìm library đang phát field sai;
- rollout instrumentation version;
- áp dụng view hoặc processor theo scope;
- debug duplicate telemetry.

Không tạo một `Tracer` mới cho từng request. Hãy tạo theo module hoặc instrumentation library rồi tái sử dụng.

---

## 9. Context: chiếc phong bì đi cùng execution

`Context` chứa state gắn với một execution logic, ví dụ:

- current span;
- trace context;
- baggage.

Mental model:

```text
request vào
  └── Context A
        ├── current span
        ├── trace flags
        └── baggage
```

Context là immutable: thao tác thêm giá trị tạo ra Context mới thay vì sửa object cũ.

Trong Java, current context mặc định thường được lưu bằng `ThreadLocal`.

Điều này dẫn đến lỗi phổ biến:

```text
Thread request tạo span
        │ submit task
        ▼
Thread worker không tự nhiên thấy ThreadLocal của request
```

Qua thread, executor, callback hoặc reactive boundary, context phải được framework instrumentation hoặc code truyền đúng.

---

## 10. Scope trong Java phải được đóng đúng

Mẫu an toàn:

```java
Context context = Context.current().with(span);

try (Scope ignored = context.makeCurrent()) {
    executeBusinessLogic();
}
```

Khi `Scope` đóng, current context trước đó được phục hồi.

Sai:

```java
span.makeCurrent();
executeBusinessLogic();
```

Đoạn sai không giữ và đóng `Scope`. Hậu quả có thể là:

- context leak sang operation sau;
- span cha sai;
- log correlation sai;
- memory/resource leak tùy implementation;
- trace trở nên khó tin cậy.

Quy tắc:

> `makeCurrent()` và `Scope.close()` phải tạo thành một cặp, tốt nhất bằng try-with-resources.

---

## 11. Context propagation trong cùng process

Ba cách phổ biến:

### Truyền explicit

```java
void process(Context parentContext) {
    Span span = tracer.spanBuilder("process")
        .setParent(parentContext)
        .startSpan();
}
```

### Dùng current context

```java
try (Scope ignored = span.makeCurrent()) {
    repository.save();
}
```

Span mới trong `repository.save()` sẽ dùng current span làm parent nếu instrumentation tuân thủ API.

### Wrap task

```java
Context captured = Context.current();
executor.submit(captured.wrap(() -> doAsyncWork()));
```

Không capture context quá sớm rồi tái sử dụng vô hạn. Context phải gắn với đúng logical operation.

---

## 12. Reactive và asynchronous boundary

Trong reactive system, một request có thể chạy qua nhiều thread:

```text
event-loop-1
  → worker-7
  → scheduler-2
  → event-loop-3
```

`ThreadLocal` thuần túy không đủ.

Cần ưu tiên:

1. instrumentation chính thức của Reactor, CompletableFuture, executor hoặc framework;
2. hook/context bridge do framework hỗ trợ;
3. truyền context explicit khi boundary tự viết;
4. integration test kiểm tra trace tree.

Dấu hiệu context propagation hỏng:

- nhiều root span cho cùng request;
- client span không nằm dưới server span;
- log có trace ID ở đầu nhưng mất ở callback;
- trace bị đứt tại queue hoặc executor;
- service graph tạo edge bất thường.

---

## 13. Propagator: đưa Context qua process boundary

Trong process, Context có thể nằm trong memory.

Qua HTTP, Kafka hoặc RPC, context phải được serialize vào carrier:

```text
Context
  │ inject
  ▼
HTTP headers / message headers / RPC metadata
  │ network
  ▼
extract
  │
  ▼
Context mới ở service nhận
```

Hai operation:

- **inject** trước khi gửi;
- **extract** khi nhận.

Instrumentation library nên dùng propagator đã cấu hình, không hard-code format riêng.

Default SDK configuration thường là:

```text
OTEL_PROPAGATORS=tracecontext,baggage
```

---

## 14. W3C Trace Context

Header chính:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
```

Cấu trúc:

```text
version-trace_id-parent_id-trace_flags
```

Trong đó:

- `trace_id`: nhận diện toàn trace;
- `parent_id`: span của bên gửi;
- bit sampled trong `trace_flags`: truyền quyết định sampling;
- `tracestate`: metadata bổ sung cho nhiều vendor.

Không tự parse hoặc nối chuỗi nếu propagator chính thức đã làm việc đó.

Incoming header là dữ liệu không tin cậy. Propagator phải validate; header invalid không được phép làm application crash.

---

## 15. Baggage không phải span attributes

Baggage là key-value đi cùng distributed context.

Ví dụ hợp lý:

```text
tenant.tier = premium
request.origin = mobile
```

Nhưng baggage:

- được truyền qua network header;
- có thể đi đến downstream ngoài dự kiến;
- không có integrity protection mặc định;
- không tự động trở thành span/log/metric attribute;
- làm tăng kích thước mỗi request.

Không nên đưa vào baggage:

- password;
- access token;
- số thẻ;
- nội dung email;
- payload lớn;
- dữ liệu PII không có policy rõ ràng.

Nếu cần chuyển baggage thành attribute, phải làm explicit và theo allowlist.

---

## 16. Span là gì?

Span mô tả một operation có:

- name;
- start time và end time;
- trace ID và span ID;
- parent;
- kind;
- status;
- attributes;
- events;
- links;
- resource và instrumentation scope.

Ví dụ:

```text
POST /checkout                         SERVER
├── validate cart                     INTERNAL
├── reserve inventory                 CLIENT
└── publish order.created              PRODUCER
```

Trace là tập hợp span có cùng trace ID, không phải một record khổng lồ duy nhất.

---

## 17. Span name phải ổn định và cardinality thấp

Tốt:

```text
GET /users/{userId}
POST /orders
reserveInventory
```

Không tốt:

```text
GET /users/893472
POST /orders/8fca1...
SQL SELECT ... toàn bộ câu lệnh
```

Nếu raw ID nằm trong span name:

- nhóm operation bị phân mảnh;
- latency distribution khó tổng hợp;
- storage index phình;
- service map khó đọc.

Span name nên mô tả **operation class**, còn instance data đặt ở attribute nếu thật sự cần và được phép.

---

## 18. SpanKind nói về vai trò

| SpanKind | Khi dùng |
|---|---|
| `SERVER` | Nhận remote request |
| `CLIENT` | Gửi remote request |
| `PRODUCER` | Gửi message đến broker |
| `CONSUMER` | Nhận hoặc xử lý message |
| `INTERNAL` | Operation nội bộ process |

Kind không phải severity.

Ví dụ database call từ checkout:

```text
checkout query database = CLIENT
```

Một method Java bình thường:

```text
calculateDiscount = INTERNAL
```

Đừng đặt mọi span thành `INTERNAL`; backend dựa vào kind để dựng topology và tính client/server latency.

---

## 19. Attributes, events và links khác nhau thế nào?

### Attributes

Mô tả span:

```text
order.type = express
payment.provider = acme_pay
```

### Events

Một thời điểm đáng chú ý bên trong span:

```text
inventory.retry
fraud.rule.matched
```

Event có timestamp và attributes riêng.

### Links

Quan hệ nhân quả không phù hợp với một parent duy nhất:

```text
batch process span
  ├── link message A context
  ├── link message B context
  └── link message C context
```

Không tạo hàng trăm nested span chỉ để thay event. Không dùng attribute để giả lập timestamp của event.

---

## 20. Span lifecycle đúng trong Java

Mẫu manual instrumentation:

```java
private final Tracer tracer;

public Receipt checkout(Order order) {
    Span span = tracer.spanBuilder("checkout")
        .setSpanKind(SpanKind.INTERNAL)
        .setAttribute("com.acme.order.type", order.type())
        .startSpan();

    try (Scope ignored = span.makeCurrent()) {
        Receipt receipt = checkoutService.execute(order);
        span.setAttribute("com.acme.order.outcome", "accepted");
        return receipt;
    } catch (RuntimeException exception) {
        span.recordException(exception);
        span.setStatus(StatusCode.ERROR, "checkout failed");
        span.setAttribute("error.type", exception.getClass().getName());
        throw exception;
    } finally {
        span.end();
    }
}
```

Ba điểm quan trọng:

1. `Scope` luôn đóng;
2. exception được record một lần ở đúng layer;
3. span luôn `end()` trong `finally`.

`recordException()` không nên được hiểu là tự động áp mọi error semantics. Khi operation thất bại, cần set status và `error.type` phù hợp.

---

## 21. Status và error semantics

Span status thường có:

- `UNSET`: mặc định, operation không có lỗi theo semantics;
- `ERROR`: operation thất bại;
- `OK`: xác nhận thành công explicit, thường không cần dùng tràn lan.

Không phải mọi HTTP 4xx đều là lỗi của server span.

Ví dụ:

- client gọi URL sai và nhận 404: có thể là lỗi ở client operation;
- server trả 404 đúng theo nghiệp vụ “không tìm thấy”: không nhất thiết là server failure;
- server trả 500: thường là error;
- retry đầu thất bại nhưng operation cuối thành công: span tổng có thể thành công, attempt span thất bại.

Error classification phụ thuộc operation được đo, không chỉ phụ thuộc exception hoặc status code.

---

## 22. Không ghi một exception nhiều lần

Anti-pattern:

```text
repository record exception
  → service record lại
    → controller record lại
      → logging framework log lần nữa
```

Kết quả là một lỗi tạo nhiều event và log, làm sai error count.

Quy tắc:

- layer xử lý được exception thì thường không record như unhandled failure;
- layer để exception thoát ra nên record nếu instrumentation của framework chưa làm;
- không manual record nếu auto-instrumentation đã record đúng;
- exception message có thể chứa dữ liệu nhạy cảm, không dùng bừa làm status description.

---

## 23. Attribute cardinality và privacy budget

Mỗi attribute cần trả lời:

1. Dùng cho câu hỏi vận hành nào?
2. Cardinality tối đa là bao nhiêu?
3. Có chứa PII/secret không?
4. Có cần ở mọi signal không?
5. Ai sở hữu schema?

| Field | Span | Metric | Log |
|---|---|---|---|
| route template | Thường có ích | Có ích | Có ích |
| user ID | Chỉ khi policy cho phép | Tránh | Cân nhắc/redact |
| order ID | Có thể opt-in | Không | Có thể có |
| raw request body | Hầu như không | Không | Hầu như không |
| error type | Có ích | Có ích | Có ích |

Metric attribute đặc biệt nguy hiểm vì SDK giữ aggregation state cho mỗi tổ hợp attribute.

---

## 24. Semantic Conventions

Semantic Conventions, hay SemConv, chuẩn hóa:

- span name;
- span kind;
- metric name, unit và instrument;
- attribute name, type và meaning;
- resource identity;
- log/event fields.

Ví dụ hiện tại:

```text
http.request.method
http.response.status_code
http.route
server.address
error.type
```

Nếu chưa có convention phù hợp, dùng namespace riêng:

```text
com.acme.order.channel
com.acme.checkout.outcome
```

Không chiếm namespace chuẩn như:

```text
http.acme_custom_field
otel.my_field
```

vì có thể xung đột với convention tương lai.

---

## 25. Stability và migration của SemConv

Semantic convention group có thể ở mức:

- development;
- alpha;
- beta;
- release candidate;
- stable;
- deprecated.

Không pin dashboard production vào field experimental mà không có kế hoạch migration.

Khi nâng instrumentation:

```text
1. đọc release notes và SemConv version
2. so sánh telemetry trước/sau
3. thử ở canary
4. cập nhật query/dashboard/alert
5. dual-read hoặc dual-emit nếu được hỗ trợ
6. xóa field cũ sau cửa sổ migration
```

`OTEL_SEMCONV_STABILITY_OPT_IN` chỉ dùng cho những migration mà instrumentation cụ thể hỗ trợ. Không xem nó như công tắc toàn cục tự động nâng mọi convention.

---

## 26. Auto, native, library và manual instrumentation

### Zero-code Java agent

- sửa bytecode khi runtime;
- nhanh để có HTTP, JDBC, messaging, runtime telemetry;
- phù hợp onboarding diện rộng.

### Spring Boot starter

- dùng auto-configuration;
- phù hợp khi muốn quản lý dependency/config trong application;
- hành vi không hoàn toàn giống Java agent.

### Native instrumentation

- library tự gọi OTel API;
- không ép application dùng SDK cụ thể;
- library chỉ nên phụ thuộc API ổn định.

### Manual instrumentation

- do application owner viết;
- phù hợp business operation;
- cần review cardinality và error semantics.

Không bật nhiều cơ chế cho cùng một library mà không kiểm tra duplicate span/metric/log.

---

## 27. Chiến lược instrumentation cho Java service

Lộ trình an toàn:

```text
Bước 1: Java agent hoặc Spring starter
  ↓
Bước 2: chuẩn hóa resource identity
  ↓
Bước 3: kiểm tra HTTP/JDBC/messaging trace
  ↓
Bước 4: thêm manual span cho business operation
  ↓
Bước 5: thêm custom metrics cho SLI/business
  ↓
Bước 6: log correlation
  ↓
Bước 7: cardinality/privacy review
```

Đừng bắt đầu bằng hàng trăm manual span. Trước hết phải biết auto-instrumentation đã cung cấp gì.

Tiêu chí một manual span đáng tồn tại:

- operation có latency hoặc failure riêng cần điều tra;
- có ranh giới logic rõ;
- tên ổn định;
- không lặp span framework;
- giúp trả lời một câu hỏi production.

---

## 28. Messaging context và Span Links

Với queue:

```text
Producer
  │ inject trace context vào message headers
  ▼
Broker
  │
  ▼
Consumer
  │ extract
  ▼
process message
```

Khác HTTP, messaging có thể:

- delay lâu;
- redelivery;
- fan-out;
- batch;
- một message kích hoạt nhiều workflow;
- nhiều message hợp lại thành một operation.

Vì vậy, không phải lúc nào parent-child cũng diễn đạt đúng.

Batch consumer có thể tạo một processing span và link đến context của từng message. Cần theo semantic convention của messaging instrumentation đang dùng, không tự đặt cây trace chỉ để UI trông liền mạch.

---

## 29. Metrics API: chọn đúng instrument

| Instrument | Ý nghĩa | Ví dụ |
|---|---|---|
| Counter | Tổng chỉ tăng | số order accepted |
| Async Counter | Đọc một tổng monotonic có sẵn | số class JVM đã load |
| UpDownCounter | Tổng có thể tăng/giảm | active requests |
| Async UpDownCounter | Quan sát tổng hiện tại có thể tăng/giảm | queue size |
| Histogram | Phân phối giá trị | request duration |
| Gauge | Giá trị mới nhất | nhiệt độ |
| Async Gauge | Callback quan sát giá trị mới nhất | CPU utilization |

Sai phổ biến:

- dùng Gauge cho request count;
- dùng Counter cho queue depth;
- ghi `-1` vào Counter;
- tạo metric name chứa tenant;
- dùng user ID làm metric attribute.

---

## 30. Synchronous và asynchronous instruments

Synchronous:

```java
counter.add(1, attributes);
histogram.record(duration, attributes);
```

Application ghi measurement tại thời điểm event xảy ra.

Asynchronous:

```java
meter.gaugeBuilder("queue.size")
    .ofLongs()
    .buildWithCallback(measurement ->
        measurement.record(queue.size()));
```

Callback chạy lúc SDK collect.

Callback không nên:

- block network lâu;
- query database nặng;
- throw exception;
- tạo thread mới mỗi lần;
- có side effect business.

Observable callback chậm có thể làm chậm collection và tăng overhead application.

---

## 31. Ví dụ custom metrics Java

```java
private static final AttributeKey<String> OUTCOME =
    AttributeKey.stringKey("com.acme.order.outcome");

private final LongCounter orderCounter;
private final DoubleHistogram checkoutDuration;

public CheckoutTelemetry(Meter meter) {
    this.orderCounter = meter.counterBuilder("com.acme.order")
        .setDescription("Number of checkout outcomes")
        .setUnit("{order}")
        .build();

    this.checkoutDuration = meter.histogramBuilder("com.acme.checkout.duration")
        .setDescription("Checkout operation duration")
        .setUnit("s")
        .build();
}

public void record(String outcome, double durationSeconds) {
    Attributes attributes = Attributes.of(OUTCOME, outcome);
    orderCounter.add(1, attributes);
    checkoutDuration.record(durationSeconds, attributes);
}
```

Vocabulary của `outcome` phải hữu hạn:

```text
accepted
rejected
failed
```

Không dùng exception message làm label.

---

## 32. Views và aggregation

Instrument tạo measurement. **View** cho SDK biết cách tạo metric stream.

View có thể:

- đổi aggregation;
- chọn histogram buckets;
- giữ hoặc loại attributes;
- đổi tên stream;
- bỏ instrument không cần.

Ví dụ logic:

```text
instrument:
  http.server.request.duration

view:
  chỉ giữ http.request.method, http.route, http.response.status_code
  dùng buckets phù hợp latency SLO
```

View là lớp governance gần source, giúp giảm:

- cardinality;
- memory SDK;
- network traffic;
- backend cost.

Collector xóa attribute sau khi SDK đã aggregate không hoàn trả memory đã tiêu tốn ở application.

---

## 33. Cardinality limit của Metrics SDK

Một metric stream có state riêng cho mỗi tổ hợp attributes:

```text
method=GET, route=/orders
method=POST, route=/orders
method=GET, route=/users/{id}
...
```

Nếu thêm:

```text
user.id
```

số series có thể tăng theo số người dùng.

SDK có cardinality limit để tự bảo vệ, nhưng limit không biến thiết kế sai thành đúng. Khi vượt limit:

- measurements có thể bị gom vào overflow stream tùy implementation;
- dữ liệu mất độ chi tiết;
- alert/dashboard thay đổi hành vi;
- application vẫn chịu overhead tạo attribute.

Phòng ngừa tại thiết kế luôn tốt hơn chờ limit cứu hệ thống.

---

## 34. Temporality

Hai kiểu temporality thường gặp:

### Cumulative

```text
t0 → hiện tại
```

Giá trị tích lũy từ thời điểm bắt đầu.

### Delta

```text
lần export trước → lần export này
```

Chỉ chứa thay đổi trong interval.

Backend và exporter có thể ưu tiên temporality khác nhau. Đổi cumulative/delta giữa chừng có thể gây:

- reset giả;
- double count;
- rate sai;
- gap sau restart;
- khó tuân thủ single-writer.

Temporality là một phần của data contract, không phải tuning flag vô hại.

---

## 35. Exemplars: từ metric sang trace

Exemplar gắn một measurement đại diện với trace/span context.

Ví dụ:

```text
histogram bucket latency cao
        │ exemplar
        ▼
trace_id = 4bf92...
```

Exemplar giúp từ biểu đồ latency mở trace cụ thể.

Nó không:

- chứa mọi request;
- thay thế trace search;
- đảm bảo trace vẫn còn khi metric retention dài hơn;
- hoạt động nếu context bị mất hoặc trace đã bị sampling bỏ.

Khi record metric trong current context đúng, SDK có thể dùng context đó cho exemplar theo cấu hình.

---

## 36. Logs API và logging bridge

Với Java application, OTel Logs API hiện chủ yếu phục vụ bridge/appender và instrumentation author. Nó không nhằm thay SLF4J, Logback hoặc Log4j trong mọi application.

Luồng phổ biến:

```text
application
  │ SLF4J
  ▼
Logback / Log4j
  │ OTel appender / bridge
  ▼
OTel LogRecord
  │ OTLP
  ▼
Collector
```

Một LogRecord có thể chứa:

- timestamp;
- observed timestamp;
- severity text/number;
- body;
- attributes;
- resource;
- instrumentation scope;
- trace ID, span ID và trace flags.

Tránh vừa export log trực tiếp qua appender vừa tail cùng file nếu điều đó tạo duplicate.

---

## 37. Log correlation

Khi log được tạo trong current span:

```text
trace_id = ...
span_id  = ...
```

có thể được bridge vào LogRecord.

Điều kiện:

- context propagation đúng;
- logging instrumentation đúng;
- log xảy ra khi span đang current;
- backend lưu và index/query field tương ứng.

Test cần kiểm tra:

```text
HTTP request
  → server span
    → application log có cùng trace_id
      → từ log mở đúng trace
```

Chỉ nhìn thấy field `trace_id` trong stdout chưa chứng minh correlation end-to-end hoạt động.

---

## 38. SDK pipeline

Trace SDK:

```text
Tracer
  → Span
  → SpanProcessor
  → SpanExporter
```

Metric SDK:

```text
Meter
  → Instrument
  → View/Aggregation
  → MetricReader
  → MetricExporter
```

Log SDK:

```text
Logger bridge
  → LogRecordProcessor
  → LogRecordExporter
```

Application library chỉ nên phụ thuộc OTel API. Application owner quyết định SDK, exporter và lifecycle.

Nếu SDK không được cài, API có thể hoạt động no-op. Đây là lý do library instrumentation không nên tự ép một exporter/backend vào application.

---

## 39. Batch, flush và shutdown

Trong production, batch processor thường tốt hơn export đồng bộ từng record:

```text
telemetry event
  → buffer
  → batch
  → export
```

Lợi ích:

- ít request mạng;
- giảm overhead;
- throughput tốt hơn.

Trade-off:

- cần memory;
- có delay;
- process crash có thể mất phần buffer chưa export.

Quy tắc:

- `forceFlush()` không gọi sau mỗi business request;
- cấu hình graceful shutdown;
- SDK shutdown trước khi process bị kill hoàn toàn;
- termination grace period phải đủ;
- không hứa “zero loss” nếu buffer chỉ ở memory.

---

## 40. OTLP/gRPC và OTLP/HTTP

Default thường gặp:

| Protocol | Port | Endpoint |
|---|---:|---|
| OTLP/gRPC | 4317 | base gRPC endpoint |
| OTLP/HTTP | 4318 | `/v1/traces`, `/v1/metrics`, `/v1/logs` |

Ví dụ:

```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
```

Với base endpoint OTLP/HTTP, SDK thường nối signal path:

```text
/v1/traces
/v1/metrics
/v1/logs
```

Nếu dùng signal-specific endpoint:

```bash
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces
```

thì path cần được cấu hình đúng theo SDK.

Lỗi phổ biến:

- nói gRPC nhưng trỏ port 4318;
- nói HTTP nhưng thiếu/sai signal path;
- dùng `https` khi receiver chỉ nghe plaintext;
- bật `tls.insecure` trong production;
- Java agent và Spring starter có default protocol khác tài liệu generic cũ.

---

## 41. Head sampling

Head sampling quyết định sớm, thường khi root span bắt đầu.

Ví dụ:

```bash
export OTEL_TRACES_SAMPLER=parentbased_traceidratio
export OTEL_TRACES_SAMPLER_ARG=0.10
```

Ý nghĩa:

- root trace mới được chọn khoảng 10% theo Trace ID;
- child tôn trọng quyết định parent.

Ưu điểm:

- giảm CPU, memory và network sớm;
- đơn giản;
- dễ scale.

Nhược điểm:

- chưa biết request cuối cùng có error hay chậm;
- có thể bỏ trace quan trọng.

Parent-based giúp tránh trace bị gãy do mỗi service tự tung đồng xu độc lập.

---

## 42. Tail sampling

Tail sampling đợi nhận nhiều span rồi quyết định.

Có thể giữ:

- trace có status error;
- trace chậm hơn threshold;
- trace của service/version mới;
- một tỷ lệ trace bình thường.

Ví dụ khái niệm:

```yaml
processors:
  tail_sampling:
    decision_wait: 15s
    num_traces: 100000
    policies:
      - name: keep-errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: keep-slow
        type: latency
        latency:
          threshold_ms: 2000
      - name: baseline
        type: probabilistic
        probabilistic:
          sampling_percentage: 5
```

Cấu hình cụ thể phải validate với version/distribution đang chạy.

---

## 43. Tail sampling không miễn phí

Để ra quyết định, Collector phải giữ trace trong memory:

```text
new traces per second
× decision wait
× average spans per trace
× average span size
```

Các rủi ro:

- `num_traces` không đủ;
- late span đến sau quyết định;
- trace cực lớn;
- Collector restart mất state;
- policy evaluation tốn CPU;
- backend chậm làm pressure lan ngược.

Tail sampling không thể phục hồi span đã bị head sampler bỏ ở SDK.

Nếu mục tiêu là tail sample ở gateway, upstream phải gửi đủ dữ liệu cần cho quyết định.

---

## 44. Scale tail sampling đúng

Mọi span cùng trace phải đến cùng một tail-sampling Collector:

```text
SDK / agent Collectors
        │
        ▼
tier 1: load-balancing exporter
        │ route theo trace ID
        ▼
tier 2: tail-sampling Collectors
        │
        ▼
trace backend
```

Round-robin load balancer thông thường có thể đưa span cùng trace đến nhiều instance:

```text
span A → collector 1
span B → collector 2
span C → collector 3
```

Khi đó không instance nào thấy toàn trace.

Phải monitor ít nhất:

- traces dropped too early;
- late-span age;
- decision latency;
- memory;
- receiver refused spans;
- exporter queue và send failures.

---

## 45. Collector components

Collector có các loại component:

- **receiver**: nhận telemetry;
- **processor**: biến đổi, lọc, enrich;
- **exporter**: gửi đi;
- **connector**: nối hai pipeline;
- **extension**: health, auth, storage và chức năng hỗ trợ.

Định nghĩa component không đồng nghĩa enable:

```yaml
receivers:
  otlp:
```

Receiver chỉ chạy khi được tham chiếu:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
```

Đây là nguyên nhân phổ biến của lỗi “config có receiver nhưng Collector không nhận data”.

---

## 46. Distribution không giống nhau

Không phải binary Collector nào cũng chứa mọi component.

Kiểm tra:

```bash
otelcol components
```

Output cho biết:

- version;
- receivers;
- processors;
- exporters;
- connectors;
- extensions.

Tên component hiện tại có thể là:

```text
otlp_grpc
otlp_http
memory_limiter
debug
```

Đừng copy config dùng component không tồn tại trong distribution.

`logging` exporter cũ đã được thay bởi `debug` exporter trong các baseline hiện đại.

---

## 47. Collector pipeline tối thiểu

Ví dụ lab:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128

  resource/common:
    attributes:
      - key: telemetry.pipeline
        value: primary
        action: upsert

  batch:
    timeout: 5s
    send_batch_size: 1024

exporters:
  debug:
    verbosity: basic

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, resource/common, batch]
      exporters: [debug]

    metrics:
      receivers: [otlp]
      processors: [memory_limiter, resource/common, batch]
      exporters: [debug]

    logs:
      receivers: [otlp]
      processors: [memory_limiter, resource/common, batch]
      exporters: [debug]
```

`debug` chỉ phù hợp lab hoặc troubleshooting có kiểm soát. Detailed telemetry có thể lộ dữ liệu nhạy cảm và tạo lượng log lớn.

---

## 48. Thứ tự processor

Processor chạy theo đúng thứ tự trong pipeline:

```text
receive
  → memory protection
  → enrich identity/context
  → filter
  → redact/transform
  → sample
  → batch
  → export
```

Guideline:

- `memory_limiter` đứng sớm để bảo vệ process;
- enrich cần đứng trước rule dùng field đã enrich;
- filter trước transform nặng nếu có thể;
- privacy redaction trước khi gửi ra trust boundary;
- processor cần original context phải đứng trước tail sampling;
- `batch` thường đứng cuối processor chain.

Không có một thứ tự đúng cho mọi hệ thống, nhưng thứ tự luôn có semantics.

---

## 49. Filter, transform và redaction

Collector có thể dùng OTTL để lọc hoặc biến đổi telemetry.

Ví dụ lọc health-check span:

```yaml
processors:
  filter/drop-health:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'
        - 'attributes["http.route"] == "/ready"'
```

Ví dụ xóa field:

```yaml
processors:
  attributes/redact:
    actions:
      - key: user.email
        action: delete
      - key: http.request.header.authorization
        action: delete
```

Ưu tiên không tạo secret/PII tại source. Collector redaction là defense in depth, vì:

- data đã tồn tại trong memory/network trước Collector;
- debug exporter có thể chạy trước redaction nếu pipeline sai;
- pipeline khác có thể bỏ qua processor;
- hash không đồng nghĩa dữ liệu đã anonymous.

---

## 50. Agent, gateway và hybrid

### Agent

Chạy gần workload, ví dụ sidecar hoặc DaemonSet:

```text
application → local agent → backend
```

Tốt cho:

- node/pod metadata;
- file logs;
- giảm connection từ app ra ngoài;
- buffer gần source.

### Gateway

Collector tập trung:

```text
applications/agents → gateway fleet → backends
```

Tốt cho:

- central auth;
- routing;
- tail sampling;
- policy chung;
- che giấu backend credentials.

### Hybrid

```text
application → agent → gateway → backend
```

Mạnh nhưng nhiều failure point hơn. Mỗi tier phải có trách nhiệm rõ, tránh enrich/filter/batch lặp không cần thiết.

---

## 51. Single-writer principle cho metrics

Một OTLP metric stream phải có một writer logic.

Nếu hai Collector cùng xuất cùng series:

```text
resource identity + scope + metric + attributes
```

backend có thể thấy:

- out-of-order samples;
- reset/gap bất thường;
- double count;
- cumulative state xung đột.

Khi scale gateway:

- giữ resource identity duy nhất;
- route stateful conversion ổn định;
- không scrape cùng target ở nhiều replica nếu không có HA semantics phù hợp;
- hiểu cumulative-to-delta và delta-to-cumulative là stateful.

---

## 52. Backpressure và data loss

Pipeline hữu hạn:

```text
receiver
  → memory
  → queue
  → exporter
  → backend
```

Nếu backend chậm đủ lâu:

1. exporter retry;
2. queue tăng;
3. memory tăng;
4. memory limiter từ chối data;
5. SDK retry hoặc drop tùy implementation;
6. telemetry mất.

Queue chỉ hấp thụ burst trong giới hạn, không tạo durability vô hạn.

Capacity plan cần:

- peak ingress;
- average record size;
- backend outage duration mục tiêu;
- retry budget;
- queue capacity;
- Collector memory/CPU;
- acceptable loss.

---

## 53. Internal telemetry của Collector

Collector mặc định thường expose internal Prometheus metrics tại:

```text
http://127.0.0.1:8888/metrics
```

Production cần expose/scrape theo network policy phù hợp.

Các nhóm metric quan trọng:

```text
otelcol_receiver_accepted_*
otelcol_receiver_refused_*
otelcol_exporter_queue_size
otelcol_exporter_queue_capacity
otelcol_exporter_enqueue_failed_*
otelcol_exporter_send_failed_*
otelcol_processor_incoming_items
otelcol_processor_outgoing_items
```

Diễn giải:

- accepted tăng: Collector đang nhận;
- refused tăng: receiver/pipeline đang từ chối;
- queue gần capacity: downstream chậm hoặc thiếu capacity;
- enqueue failed tăng: data không vào được queue;
- send failed tăng: export lỗi, nhưng có thể còn retry;
- incoming khác outgoing bất ngờ: processor đang drop hoặc lỗi.

---

## 54. Security boundary

Telemetry có thể chứa:

- topology nội bộ;
- endpoint;
- tenant;
- query;
- exception;
- user data;
- token bị ghi nhầm.

Collector production cần:

- TLS hoặc mTLS;
- authentication/authorization;
- bind receiver vào interface cần thiết;
- network policy/firewall;
- least privilege;
- secret từ secret manager;
- giới hạn request/resource;
- redaction;
- audit cấu hình;
- cập nhật security release.

Không dùng:

```yaml
tls:
  insecure: true
```

ngoài lab hoặc mạng đã có control được đánh giá rõ ràng.

`X-Scope-OrgID` hay tenant header không tự động là authentication.

---

## 55. Test instrumentation

### Unit test

Kiểm tra:

- span name/kind;
- required attributes;
- error status;
- metric instrument/unit;
- không có forbidden field.

Dùng in-memory exporter hoặc SDK test utility nếu language cung cấp.

### Integration test

Kiểm tra:

- incoming context được extract;
- outgoing context được inject;
- async task vẫn cùng trace;
- log có trace/span ID;
- duplicate instrumentation không xảy ra.

### End-to-end test

```text
synthetic request
  → application
  → Collector
  → backend
  → query lại trace/log/metric
```

Health endpoint chỉ chứng minh process sống. Canary end-to-end mới chứng minh data plane hoạt động.

---

## 56. Validate Collector trước rollout

Checklist:

```text
1. kiểm tra binary version
2. chạy otelcol components
3. validate config bằng chính binary sẽ deploy
4. xem effective config ở chế độ redacted nếu cần
5. gửi synthetic telemetry
6. kiểm tra internal metrics
7. kiểm tra backend
8. canary một phần traffic
```

Lệnh hữu ích theo Collector hiện đại:

```bash
otelcol components
otelcol print-config --config=file:otel-collector.yaml
```

`print-config` vẫn có phần experimental. Không in unredacted config vào CI log vì có thể lộ secret.

---

## 57. Rollout strategy

Không bật 100% toàn fleet ngay.

```text
dev
  → staging
  → 1 canary instance
  → 5%
  → 25%
  → 100%
```

Mỗi bước quan sát:

- application CPU/memory;
- request latency;
- telemetry volume;
- metric cardinality;
- trace completeness;
- log duplication;
- Collector refused/send failed;
- backend ingestion;
- cost.

Rollback trigger phải định nghĩa trước, ví dụ:

- CPU tăng hơn 10%;
- p99 latency tăng vượt budget;
- queue trên 80% trong 15 phút;
- cardinality tăng gấp hai;
- error trace bị mất;
- PII xuất hiện.

---

## 58. Telemetry governance

Một organization nên có:

### Resource contract

```text
service.namespace
service.name
service.version
service.instance.id
deployment.environment.name
team/owner mapping
```

### Attribute registry nội bộ

```text
name
type
meaning
allowed values
cardinality budget
privacy class
owner
stability
```

### Instrumentation review

- có trùng auto-instrumentation không;
- operation có giá trị điều tra không;
- SemConv đã tồn tại chưa;
- metric có SLI/query cụ thể không;
- data retention và cost ra sao.

### Deprecation process

- thông báo;
- dual-read;
- migration dashboard/alert;
- deadline;
- xóa field cũ;
- kiểm tra consumer còn phụ thuộc.

---

## 59. Anti-patterns thường gặp

### “Bật agent là xong observability”

Agent thấy technical edges, không biết đầy đủ business outcome.

### “Collector sẽ sửa hết”

Collector không thể khôi phục context hoặc semantics chưa từng được tạo.

### “Mọi field đều hữu ích”

Field không có use case vẫn tiêu CPU, network, storage và tạo privacy risk.

### “Sampling là security”

Sampling giảm volume, không đảm bảo secret/PII bị loại.

### “Baggage là nơi chứa metadata tùy ý”

Baggage đi qua service boundary và có cost trên từng request.

### “Trace ID là metric label”

Trace ID có cardinality gần bằng số request.

### “Queue đảm bảo không mất”

Queue hữu hạn và có thể chỉ nằm trong memory.

### “Mỗi service tự chọn SemConv version”

Hệ thống tạo data contract phân mảnh, dashboard khó dùng chung.

---

## 60. Quy trình debug khi không thấy trace

Đi từ source đến sink:

```text
1. Span có được tạo không?
2. Span có end không?
3. SDK có exporter không hay đang no-op?
4. Sampler có drop không?
5. Protocol/port/path có đúng không?
6. Collector receiver có accepted tăng không?
7. Processor có drop không?
8. Exporter queue/send có lỗi không?
9. Backend có ingest không?
10. Query có đúng service/time range/tenant không?
```

Không bắt đầu bằng restart mọi component. Mỗi bước phải có evidence.

---

## 61. Quy trình debug trace bị gãy

Kiểm tra theo boundary:

```text
HTTP client inject?
HTTP server extract?
executor có propagate?
message producer inject?
message consumer extract?
sampler có parent-based?
tail sampler có nhận đủ span?
```

So sánh:

- trace ID của caller và callee;
- parent span ID phía nhận với span ID phía gửi;
- `trace_flags`;
- propagator configuration;
- header có bị proxy/broker xóa;
- duplicate agent/starter.

Nếu cùng business request có hai trace ID ở một boundary, lỗi thường nằm ở inject/extract hoặc context current.

---

## 62. Workshop đề xuất

### Bài 1 – Context

- tạo manual parent span;
- submit task vào executor;
- quan sát trace trước và sau khi wrap Context.

### Bài 2 – Error

- tạo một handled exception và một unhandled exception;
- bảo đảm chỉ unhandled failure được record đúng;
- kiểm tra `error.type` và status.

### Bài 3 – Metrics

- tạo Counter và Histogram;
- thêm bounded attribute;
- cố tình thêm user ID và quan sát cardinality.

### Bài 4 – Collector

- nhận OTLP HTTP/gRPC;
- filter health checks;
- batch;
- export debug trong lab;
- theo dõi internal telemetry.

### Bài 5 – Correlation

- từ metric exemplar mở trace;
- từ trace mở log;
- từ log quay lại trace.

---

## 63. Production checklist

### Application

- [ ] `service.name` explicit và ổn định.
- [ ] `service.version` phản ánh artifact deploy.
- [ ] Không còn `unknown_service`.
- [ ] Auto-instrumentation không duplicate.
- [ ] Manual span có business value.
- [ ] Span name cardinality thấp.
- [ ] Scope luôn đóng và span luôn end.
- [ ] Async context propagation đã test.
- [ ] Metric attributes có budget.
- [ ] Graceful SDK shutdown hoạt động.

### Data contract

- [ ] SemConv version được ghi nhận.
- [ ] Custom attributes dùng namespace nội bộ.
- [ ] Experimental fields có owner/migration plan.
- [ ] PII/secret policy được áp dụng.
- [ ] Baggage có allowlist và size budget.

### Collector

- [ ] `otelcol components` khớp config.
- [ ] Component được enable trong pipeline.
- [ ] Processor order được review.
- [ ] `memory_limiter` và batching đã tune.
- [ ] TLS/auth/network policy đã bật.
- [ ] Internal telemetry được scrape và alert.
- [ ] Queue/refused/send-failed có dashboard.
- [ ] Tail sampling route theo trace ID.
- [ ] Metric pipeline tuân thủ single-writer.

### Validation

- [ ] Có canary end-to-end.
- [ ] Có test logs ↔ traces.
- [ ] Có test exemplar → trace.
- [ ] Có rollback trigger.
- [ ] Có capacity test khi backend chậm.

---

## 64. Câu hỏi tự kiểm tra

1. API, SDK, agent, Collector và backend khác trách nhiệm thế nào?
2. Vì sao Collector không thể sửa business semantics bị thiếu?
3. Resource khác span attributes ra sao?
4. `service.name` và `service.instance.id` khác nhau thế nào?
5. Instrumentation Scope giúp debug duplicate telemetry ra sao?
6. Vì sao Java `ThreadLocal` không tự đi qua executor?
7. `makeCurrent()` cần được dùng thế nào?
8. Inject và extract xảy ra ở đâu?
9. `traceparent` chứa những thành phần chính nào?
10. Vì sao baggage không phải span attribute?
11. Dữ liệu nào tuyệt đối không nên đưa vào baggage?
12. Span name có raw ID gây hậu quả gì?
13. `CLIENT` khác `INTERNAL` thế nào?
14. Khi nào dùng event và khi nào dùng link?
15. `recordException()` có thay mọi error handling không?
16. Vì sao không nên record cùng exception ở nhiều layer?
17. Semantic Conventions là contract với những consumer nào?
18. Custom attribute nên dùng namespace nào?
19. Counter và UpDownCounter khác nhau thế nào?
20. View giảm cost tại source ra sao?
21. Vì sao Collector xóa metric attribute là quá muộn đối với SDK memory?
22. Cumulative và delta khác nhau thế nào?
23. Exemplar có giữ mọi trace không?
24. Logs API có thay SLF4J không?
25. Head sampling và tail sampling trade-off ra sao?
26. Vì sao tail sampler cần tất cả span cùng trace?
27. `num_traces` và `decision_wait` ảnh hưởng memory thế nào?
28. Định nghĩa receiver trong YAML đã enable receiver chưa?
29. Vì sao phải chạy `otelcol components`?
30. `memory_limiter` nên đứng ở đâu?
31. Vì sao batch thường đứng cuối processor chain?
32. Queue có đảm bảo zero loss không?
33. Single-writer principle bảo vệ metric khỏi lỗi gì?
34. Internal metric nào cho biết Collector đang từ chối data?
35. Health check khác canary end-to-end thế nào?

---

## 65. Tài liệu chính thức

### OpenTelemetry core

- [OpenTelemetry concepts](https://opentelemetry.io/docs/concepts/)
- [Instrumentation](https://opentelemetry.io/docs/concepts/instrumentation/)
- [Resources](https://opentelemetry.io/docs/concepts/resources/)
- [Context specification](https://opentelemetry.io/docs/specs/otel/context/)
- [Propagators API](https://opentelemetry.io/docs/specs/otel/context/api-propagators/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [Baggage](https://opentelemetry.io/docs/concepts/signals/baggage/)
- [Sampling](https://opentelemetry.io/docs/concepts/sampling/)

### Java

- [OpenTelemetry Java](https://opentelemetry.io/docs/languages/java/)
- [Java API – Record telemetry](https://opentelemetry.io/docs/languages/java/api/)
- [Java instrumentation ecosystem](https://opentelemetry.io/docs/languages/java/instrumentation/)
- [Java agent](https://opentelemetry.io/docs/zero-code/java/agent/)
- [Java SDK configuration](https://opentelemetry.io/docs/languages/java/configuration/)
- [OTLP exporter configuration](https://opentelemetry.io/docs/languages/sdk-configuration/otlp-exporter/)

### Semantic Conventions

- [Semantic Conventions 1.43](https://opentelemetry.io/docs/specs/semconv/)
- [Service resource conventions](https://opentelemetry.io/docs/specs/semconv/resource/service/)
- [Deployment attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/deployment/)
- [Instrumentation Scope](https://opentelemetry.io/docs/specs/otel/common/instrumentation-scope/)
- [Recording errors](https://opentelemetry.io/docs/specs/semconv/general/recording-errors/)
- [Telemetry Schemas](https://opentelemetry.io/docs/specs/otel/schemas/)

### Collector

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Collector configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Collector deployment patterns](https://opentelemetry.io/docs/collector/deploy/)
- [Gateway deployment pattern](https://opentelemetry.io/docs/collector/deploy/gateway/)
- [Collector internal telemetry](https://opentelemetry.io/docs/collector/internal-telemetry/)
- [Transforming telemetry](https://opentelemetry.io/docs/collector/transforming-telemetry/)
- [Collector security](https://opentelemetry.io/docs/security/)
- [Tail Sampling Processor](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/processor/tailsamplingprocessor)

---

## Chủ đề tiếp theo

Sau khi hiểu cách tạo và vận chuyển telemetry, bước tiếp theo là:

> [**Continuous Profiling – CPU, allocation, wall time, flame graph, Pyroscope/Parca và correlation với metrics/traces.**](continuous_profiling.md)

---

*Cập nhật lần cuối: 2026-07-29*
