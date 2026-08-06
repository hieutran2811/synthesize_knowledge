# Frontend & Real User Monitoring – Từ Core Web Vitals đến Business Journey

> Mục tiêu của bài này là đo trải nghiệm thật trong browser: tải trang, tương tác, layout,
> JavaScript error, API, release và business journey; sau đó nối chúng với CDN, gateway và
> backend trace mà không thu thập quá mức dữ liệu người dùng.
>
> Baseline tham chiếu: Core Web Vitals hiện hành (**LCP, INP, CLS**), W3C Web Performance APIs,
> W3C Trace Context và OpenTelemetry JavaScript. Browser instrumentation của OpenTelemetry vẫn
> được tài liệu chính thức đánh dấu experimental/mostly unspecified; phải pin version.
>
> Không ghi DOM text, form value, URL/query thô, cookie, token, email, session replay hoặc
> screenshot trên production nếu chưa có consent, redaction, retention và security review.
>
> Nên đọc trước:
> [API & HTTP Observability](api_http_observability.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Telemetry Governance](telemetry_governance_finops.md) và
> [Incident Response](incident_response_observability.md).

---

## 1. Vì sao frontend observability khác backend?

Code chạy trên thiết bị người dùng mà ta không kiểm soát:

- browser/version khác nhau;
- CPU, memory và battery khác nhau;
- mạng di động/Wi-Fi/proxy;
- extension/content blocker;
- tab background;
- cache/service worker;
- third-party script;
- người dùng đóng trang trước khi telemetry gửi.

Backend xanh không chứng minh frontend dùng được.

---

## 2. Field data và lab data

| Loại | Nguồn | Điểm mạnh |
|---|---|---|
| RUM/field | người dùng thật | phản ánh device, mạng và hành vi thật |
| synthetic/lab | môi trường kiểm soát | tái lập, so sánh release |

RUM có nhiễu và privacy constraints; synthetic không đại diện đầy đủ population. Dùng cả hai.

---

## 3. Vòng đời trải nghiệm web

```text
navigation
  → DNS/TCP/TLS
  → HTML
  → CSS/JS/font/image
  → parse/render/hydrate
  → user interaction
  → API call
  → route transition
  → business outcome
```

Page load chỉ là giai đoạn đầu của SPA sống nhiều phút hoặc nhiều giờ.

---

## 4. SLI frontend

Các nhóm:

- page/screen usable time;
- Core Web Vitals;
- JavaScript/resource error;
- API success/latency từ browser;
- user journey success;
- abandonment;
- release regression;
- telemetry delivery.

Không lấy page-view count làm denominator cho mọi journey.

---

## 5. Core Web Vitals hiện hành

| Metric | Trải nghiệm | “Good” |
|---|---|---|
| LCP | loading | ≤ 2,5 giây |
| INP | responsiveness | ≤ 200 ms |
| CLS | visual stability | ≤ 0,1 |

Đánh giá thường ở percentile 75, tách mobile và desktop. Đây là threshold chung, không thay SLO
nghiệp vụ riêng.

---

## 6. Percentile và segmentation

Một p75 toàn site có thể che:

- route quan trọng;
- mobile;
- quốc gia/mạng chậm;
- browser;
- release mới;
- logged-in journey;
- device memory thấp.

Segment theo dimension hữu hạn và đủ sample. Không tạo tổ hợp mọi chiều.

---

## 7. Navigation Timing

`PerformanceNavigationTiming` cung cấp các mốc navigation như:

- redirect;
- DNS;
- connect/TLS;
- request/response;
- DOM processing;
- load event;
- transfer/body sizes;
- protocol.

Đọc timing qua Performance Timeline; không trừ timestamp từ các clock khác.

---

## 8. Resource Timing

Giúp phân tích CSS, JS, image, font, fetch và resource khác:

- start/duration;
- DNS/connect/TLS;
- request/response;
- transfer/encoded/decoded size;
- protocol;
- initiator type.

Cross-origin detail phụ thuộc `Timing-Allow-Origin`. Không dùng full resource URL làm label.

---

## 9. User Timing

`performance.mark()` và `performance.measure()` đo milestone riêng:

```text
app_shell_ready
product_data_ready
checkout_interactive
route_transition
```

Tên mark phải được quản trị, low-cardinality và cùng semantics giữa release.

---

## 10. PerformanceObserver

Observer nhận performance entries bất đồng bộ. Thực hành:

- kiểm tra `supportedEntryTypes`;
- dùng buffered entries khi phù hợp;
- xử lý nhiều entry;
- disconnect khi không cần;
- giới hạn CPU/memory;
- chịu được browser không hỗ trợ.

Instrumentation không được làm chậm chính trải nghiệm đang đo.

---

## 11. Time origin và clock

Browser performance timestamps thường tương đối với time origin và có độ phân giải/giới hạn
privacy. Không ghép trực tiếp với server wall-clock.

Để correlation:

- dùng trace/request ID;
- duration từ cùng monotonic timeline;
- server timing;
- clock-skew-aware analysis.

---

## 12. Navigation types

Tách:

- navigate;
- reload;
- back/forward;
- prerender nếu browser expose;
- SPA soft navigation do ứng dụng định nghĩa.

Cache và lifecycle khác nhau làm timing distribution khác nhau.

---

## 13. Time to First Byte

TTFB chứa:

```text
redirect + DNS/connect/TLS + request
+ server/CDN wait + first response byte
```

TTFB cao không đồng nghĩa backend handler chậm. Correlate CDN cache status, Server-Timing,
backend trace và geography.

---

## 14. First Contentful Paint

FCP đánh dấu nội dung đầu tiên được paint, hữu ích để biết trang bắt đầu phản hồi thị giác.
Nhưng skeleton hoặc logo sớm không chứng minh nội dung chính usable.

Đọc cùng LCP, API/data-ready và journey milestone.

---

## 15. Largest Contentful Paint

Điều tra LCP theo:

- TTFB;
- resource discovery delay;
- resource load duration;
- render delay;
- LCP element type;
- image/font priority;
- client rendering/hydration.

Không gửi selector/DOM text nhạy cảm; chỉ dùng element class/category đã chuẩn hóa.

---

## 16. Interaction to Next Paint

INP phản ánh responsiveness qua các interaction trong page lifetime. Phân tích:

```text
input delay + event processing + presentation delay
```

Long task, main-thread contention, synchronous work và rendering đều có thể góp phần.

---

## 17. Cumulative Layout Shift

CLS đo layout shift ngoài mong đợi. Nguồn thường gặp:

- image/ad không reserve kích thước;
- font swap;
- content chèn phía trên;
- animation/layout;
- component hydrate khác server.

Không “fix” bằng che nội dung; xác định shift source và user impact.

---

## 18. Long tasks

Main-thread task dài làm interaction bị trì hoãn. Theo dõi:

- count/duration;
- route/release;
- script owner first-party/third-party;
- thời điểm gần interaction;
- total blocking;
- attribution khi API hỗ trợ.

Không thu raw script URL có query/hash vào label.

---

## 19. Event Timing

Event Timing giúp phân rã interaction latency. Tên interaction target cần privacy-safe:

- component type;
- action;
- route;
- release.

Không ghi text người dùng nhấn hoặc DOM path động.

---

## 20. JavaScript errors

Thu thập:

- error type;
- normalized message/fingerprint;
- stack đã symbolicate;
- route/release;
- handled/unhandled;
- user impact;
- occurrence và affected sessions.

Không dùng raw message làm metric label.

---

## 21. Unhandled promise rejection

Promise rejection không được xử lý có thể:

- làm dữ liệu không tải;
- bỏ qua UI update;
- chỉ xuất hiện trong console;
- gây state không nhất quán.

Capture reason an toàn, stack, release và journey; phân biệt cancellation hợp lệ.

---

## 22. Resource load errors

Theo dõi lỗi:

- script;
- stylesheet;
- image/font;
- dynamic chunk;
- source map;
- service worker;
- third-party.

Normalize resource thành asset family/chunk/release, không full URL.

---

## 23. Fetch/XHR

Browser client metric cần:

- normalized API route;
- method/status/error;
- duration;
- transfer size;
- abort/timeout;
- retry;
- trace propagation success.

CORS hoặc network error thường không có HTTP status; giữ taxonomy riêng.

---

## 24. SPA navigation

History/API route change không tự tạo document navigation. Instrument:

- transition start;
- code/data fetch;
- render;
- route ready;
- error;
- abandonment;
- old/new route template.

Định nghĩa “ready” theo user task, không chỉ router callback.

---

## 25. SSR, hydration và islands

Tách:

```text
server render
→ HTML receive
→ JS load
→ hydration start/end
→ interactive
```

HTML nhìn thấy sớm nhưng hydration chậm có thể tạo “dead UI”. Đo hydration mismatch/error và
interaction trước hydration.

---

## 26. Microfrontends

Cần shared contract cho:

- application/shell identity;
- child module/version;
- route;
- error boundary;
- trace context;
- duplicate SDK;
- shared resource;
- ownership.

Không để mỗi microfrontend tạo session ID và exporter riêng không kiểm soát.

---

## 27. Third-party scripts

Third party có thể gây:

- long task;
- render-blocking;
- network contention;
- CSP error;
- privacy leakage;
- outage ngoài kiểm soát.

Đo owner/category, load/error/CPU impact và có kill switch/budget.

---

## 28. Bundle và resource waterfall

Theo dõi:

- JS/CSS bytes;
- compressed/decompressed size;
- chunks;
- cache;
- preload/preconnect;
- duplicate dependency;
- unused/late-loaded asset;
- critical path.

Bundle size budget cần liên kết với LCP/INP thực tế, không chỉ CI artifact bytes.

---

## 29. Cache và Service Worker

Phân biệt:

- memory/disk/HTTP cache;
- CDN;
- service-worker cache;
- network;
- stale fallback.

Quan sát service worker install/activate/update, fetch error, version mismatch và cache age.
Cache hit nhanh nhưng stale vẫn là correctness failure.

---

## 30. CDN và edge

RUM có thể thấy TTFB/transfer nhưng cần server-side CDN signals:

- cache hit/status;
- edge location;
- origin latency/error;
- purge/config;
- bytes;
- bot filtering;
- TLS/protocol.

Không tin client-provided region làm security boundary.

---

## 31. Server-Timing

Server có thể gửi metric timing hữu hạn cho browser:

```text
Server-Timing: cache;dur=12, app;dur=83
```

Không expose topology, tenant, query hoặc secret. Tên metric là public contract và header thêm
network bytes.

---

## 32. Trace context browser → backend

Inject `traceparent` vào request được allowlist. Cần:

- CORS cho header;
- trusted destination list;
- context validation;
- không inject vào third-party ngoài ý muốn;
- sampling policy;
- test proxy/gateway propagation.

Browser input là untrusted; backend không dùng trace context làm authorization.

---

## 33. CORS và preflight

Telemetry có thể thay đổi CORS/preflight vì thêm header. Theo dõi:

- preflight rate/latency/error;
- allowed origins/headers;
- credential mode;
- cache max-age;
- failed trace-header propagation.

Instrumentation không được làm API đang chạy thành lỗi CORS.

---

## 34. OpenTelemetry browser

OpenTelemetry JavaScript có document-load, user-interaction, XHR/fetch instrumentations, nhưng
tài liệu chính thức vẫn cảnh báo browser instrumentation experimental/mostly unspecified.

Do đó:

- pin package;
- canary;
- kiểm tra span schema;
- đo overhead;
- giới hạn destinations;
- có kill switch.

---

## 35. Sampling

Browser sampling phải cân bằng:

- network/battery;
- ingestion cost;
- rare error;
- low-end devices;
- regional representation;
- trace completeness.

Giữ aggregate Core Web Vitals với rate đủ lớn; traces/errors dùng adaptive sampling và weight
khi phân tích population.

---

## 36. Session model

Định nghĩa:

- session bắt đầu/kết thúc;
- inactivity timeout;
- nhiều tab;
- reload;
- authenticated transition;
- background/foreground.

Session là analytics construct, không phải user identity. Dùng ID ngẫu nhiên, rotation và
retention phù hợp.

---

## 37. Anonymous và pseudonymous IDs

Hash user ID vẫn có thể là personal data. Ưu tiên:

- không cần ID thì không thu;
- short-lived session ID;
- purpose limitation;
- consent;
- deletion;
- access control;
- không join dataset tùy tiện.

---

## 38. Release và source maps

Mỗi event cần release/build identity ổn định. Source maps:

- upload vào backend bảo vệ;
- khớp exact artifact;
- không public nếu chứa source nhạy cảm;
- kiểm tra symbolication;
- retention theo release;
- hỗ trợ rollback/canary.

Không group lỗi chỉ bằng line number đã minify.

---

## 39. Error grouping

Fingerprint dựa trên:

- exception type;
- normalized stack frames;
- module/function;
- cause chain;
- release context.

Đo occurrences và affected sessions/users riêng. Một loop có thể tạo triệu event nhưng chỉ ảnh
hưởng một session.

---

## 40. JavaScript execution và bundle CPU

Theo dõi:

- parse/compile/evaluate;
- long tasks;
- main-thread busy;
- worker usage;
- route-specific code;
- third-party;
- low-end device impact.

Bytes nhỏ không chắc CPU thấp; compressed code vẫn phải parse và chạy.

---

## 41. Memory và leak

Browser memory APIs có availability/privacy giới hạn. Dấu hiệu gián tiếp:

- heap growth trong long session;
- DOM node/listener tăng;
- tab crash;
- interaction chậm dần;
- route transition không giải phóng;
- device class.

Heap snapshot chỉ dùng trong lab/controlled diagnostics, không upload mặc định.

---

## 42. Rendering

Ngoài CWV, xem:

- animation/frame drops;
- style/layout cost;
- paint/composite;
- image decode;
- font;
- canvas/WebGL;
- main-thread scheduling.

RUM aggregate chỉ khoanh vùng; browser profiler tái lập trong lab để tìm code.

---

## 43. Device và network segmentation

Dimension hữu hạn:

- mobile/desktop/tablet;
- effective connection type nếu available;
- browser family/major;
- OS family/major;
- memory/CPU class thô;
- viewport bucket.

Không giữ full user-agent string làm label.

---

## 44. Geography

Region/country giúp phát hiện CDN/ISP/route issue nhưng có privacy và accuracy trade-off.

- derive server-side khi phù hợp;
- không lưu precise location;
- k-anonymity/minimum sample;
- retention;
- consent/legal basis;
- không dùng cho identity.

---

## 45. Page visibility

Background tab có timer throttling và không phản ánh active experience. Ghi visibility state
khi đo:

- page load;
- interaction;
- route;
- API;
- session end.

Không trộn foreground và background latency mà không ghi semantics.

---

## 46. Abandonment

Người dùng đóng/tab chuyển trước khi event hoàn tất. Đo:

- journey start;
- milestone;
- last visible state;
- navigation away;
- error/latency trước đó;
- telemetry send success.

Thiếu completion event có thể là abandonment hoặc telemetry loss; cần phân biệt.

---

## 47. Business journeys

Ví dụ:

```text
search → product view → add to cart → checkout → confirmation
```

Mỗi bước có success, duration, error code và release. Không gửi nội dung tìm kiếm, product/user
ID thô nếu không cần.

---

## 48. Form observability

Đo:

- validation error category;
- submit attempts;
- API outcome;
- time to complete;
- abandonment;
- accessibility issue;
- autofill/browser compatibility.

Tuyệt đối không capture field values, password hoặc payment data.

---

## 49. Accessibility signals

Automated check không chứng minh accessible, nhưng có thể theo dõi:

- CI violations;
- keyboard/focus failure;
- semantic regression;
- contrast rule;
- assistive-technology test coverage;
- user-reported journey failure.

Giữ accessibility như quality objective, không chỉ telemetry dashboard.

---

## 50. Reporting API và CSP

Browser Reporting API có thể gửi CSP, permissions, deprecation, intervention và một số report
khác tùy hỗ trợ.

Cần:

- report-only rollout;
- endpoint authentication/abuse protection;
- schema/version;
- dedup/rate limit;
- URL redaction;
- browser-support awareness.

---

## 51. Synthetic monitoring

Synthetic nên bao phủ:

- DNS/TLS;
- document/resources;
- scripted journey;
- visual/functional assertion;
- multiple regions;
- mobile emulation;
- performance budget.

Giữ test account/data riêng và cleanup idempotent.

---

## 52. RUM khác synthetic

```text
Synthetic xanh + RUM đỏ
  → device/network/browser/population issue có thể xảy ra

Synthetic đỏ + RUM xanh
  → probe path/account/region hoặc sampling delay có thể xảy ra
```

Hai nguồn xác nhận và bổ sung nhau, không lấy một nguồn phủ định nguồn kia.

---

## 53. Public field datasets

Dataset như Chrome UX Report có aggregation, eligibility, privacy threshold và độ trễ riêng.
Nó hữu ích benchmark xu hướng nhưng không thay first-party RUM cho release/tenant/journey.

Ghi rõ nguồn và cửa sổ thời gian trên dashboard.

---

## 54. Dashboard

```text
Business journey
  → route/page type
  → Core Web Vitals
  → JS/resource/API errors
  → browser/device/network/region
  → release/CDN/backend trace
```

Hiển thị sample count, sampling rate và coverage cạnh percentile.

---

## 55. Frontend SLO

Ví dụ:

- 75% visits đạt good LCP/INP/CLS;
- 99,5% checkout frontend không có fatal error;
- 99% route transition usable dưới 2 giây;
- crash-free/healthy session objective.

Không trộn threshold Web Vitals với availability SLO thành một mẫu số mơ hồ.

---

## 56. Alerting

Page khi:

- critical journey burn;
- fatal JS/resource error tăng theo release;
- widespread API/network failure;
- Core Web Vital regression lớn, có sample đủ;
- telemetry mất diện rộng.

Alert theo release/browser/region khi có owner và hành động. Tránh page theo một event.

---

## 57. Incident workflow

```text
1. Xác nhận journey, route, release và population
2. Kiểm tra sample/telemetry health
3. Tách JS, resource, API và performance
4. So browser/device/network/region
5. Correlate deploy/CDN/third party
6. Drill trace/backend
7. Rollback/kill switch có kiểm soát
8. Ghi evidence và user communication
```

---

## 58. Privacy và consent

Thiết kế:

- data inventory;
- purpose và legal basis;
- consent state;
- minimization;
- redaction;
- regional routing;
- retention/deletion;
- subject access;
- vendor review.

Consent denied phải là trạng thái hợp lệ, không phải telemetry error.

---

## 59. Gửi telemetry đáng tin cậy

Trang có thể đóng trước export. Cân nhắc:

- small batches;
- bounded queue;
- `sendBeacon`/keepalive phù hợp;
- retry giới hạn;
- offline behavior;
- unload/pagehide;
- duplicate detection;
- endpoint rate limiting.

Không làm chậm navigation chỉ để đảm bảo gửi telemetry.

---

## 60. Cost và cardinality

Nguồn tăng cost:

- page/session event quá dày;
- raw URL;
- resource entries;
- stack traces;
- browser/device combinations;
- spans cho mọi interaction;
- source map processing.

Dùng aggregation, budgets, adaptive sampling và retention theo signal.

---

## 61. Sampling bias

Telemetry có thể thiếu:

- ad/tracker blocker;
- browser cũ;
- mạng yếu không gửi được;
- user không consent;
- tab crash;
- region bị chặn.

Dashboard phải hiển thị coverage và không suy rộng sample như population tuyệt đối.

---

## 62. Testing

Kiểm thử:

- instrumentation schema;
- route normalization;
- no-PII fixtures;
- source maps;
- trace propagation/CORS;
- browser matrix;
- network/offline;
- page hide/export;
- overhead;
- consent.

Telemetry là production code và cần regression tests.

---

## 63. Rollout

```text
development
→ internal users
→ canary %
→ selected routes
→ broader rollout
```

Theo dõi bundle bytes, main-thread cost, network bytes, errors và backend ingestion. Có remote
kill switch không phụ thuộc SDK đang lỗi.

---

## 64. Workshop, checklist và câu hỏi

### Workshop

1. Chọn một critical journey.
2. Định nghĩa page/route templates và milestone.
3. Thu LCP, INP, CLS cùng release.
4. Thêm JS/resource/API error taxonomy.
5. Nối một API call với backend trace.
6. Test slow network, third-party failure và consent denied.

### Checklist

- [ ] Có field và synthetic data.
- [ ] Core Web Vitals tách mobile/desktop và có sample count.
- [ ] SPA route/journey được instrument.
- [ ] Raw URL, DOM và form value không vào telemetry.
- [ ] Source maps khớp release và được bảo vệ.
- [ ] API trace chỉ inject tới destination allowlist.
- [ ] Browser SDK được pin/canary/kill switch.
- [ ] Sampling bias và coverage được hiển thị.
- [ ] Consent, retention và deletion được thực thi.
- [ ] Telemetry overhead có budget.

### Câu hỏi

1. RUM và synthetic bổ sung nhau thế nào?
2. Core Web Vitals hiện gồm những metric nào?
3. Vì sao cần p75 và segmentation?
4. TTFB chứa những phần nào?
5. SPA route khác navigation document ra sao?
6. Hydration chậm tạo “dead UI” thế nào?
7. Vì sao full URL/resource URL không nên làm label?
8. Trace header có thể làm phát sinh preflight ra sao?
9. Session ID có phải user identity không?
10. Source map cần bảo vệ vì sao?
11. Page close ảnh hưởng telemetry thế nào?
12. Sampling bias tạo false conclusion ra sao?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Web performance

- [Core Web Vitals](https://web.dev/articles/vitals)
- [Navigation Timing](https://www.w3.org/TR/navigation-timing/)
- [Resource Timing](https://www.w3.org/TR/resource-timing/)
- [Performance Timeline](https://www.w3.org/TR/performance-timeline/)
- [User Timing](https://www.w3.org/TR/user-timing/)
- [Server Timing](https://www.w3.org/TR/server-timing/)
- [Long Tasks](https://www.w3.org/TR/longtasks-1/)
- [Event Timing](https://www.w3.org/TR/event-timing/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)

### Instrumentation

- [OpenTelemetry JavaScript browser guide](https://opentelemetry.io/docs/languages/js/getting-started/browser/)
- [OpenTelemetry JavaScript status](https://opentelemetry.io/docs/languages/js/)
- [MDN PerformanceObserver](https://developer.mozilla.org/en-US/docs/Web/API/PerformanceObserver)
- [MDN Reporting API](https://developer.mozilla.org/en-US/docs/Web/API/Reporting_API)

Chủ đề tiếp theo:
[Mobile App Observability](mobile_app_observability.md) – crash, ANR/hang, startup, rendering,
network, battery, offline synchronization, releases và device fragmentation.

---

*Cập nhật lần cuối: 2026-07-30*
