# Mobile App Observability – Từ Crash đến Trải nghiệm trên Thiết bị thật

> Mục tiêu của bài này là quan sát Android/iOS từ lúc cài đặt, khởi động, render, tương tác,
> gọi mạng, chạy background, offline/sync đến crash, ANR/hang và battery impact; sau đó nối
> mobile journey với backend mà vẫn tôn trọng consent và tài nguyên thiết bị.
>
> Baseline tham chiếu: Android Vitals, Android performance guidance, Apple MetricKit/Xcode
> performance guidance và OpenTelemetry client-app/Android hiện hành. API và report của hệ
> điều hành thay đổi theo OS/SDK; pin version, capability-detect và giữ fallback.
>
> Không thu screenshot, input, clipboard, contacts, precise location, token, database/file,
> full device fingerprint hoặc session replay nếu chưa có mục đích, consent, redaction,
> retention và security review rõ ràng.
>
> Nên đọc trước:
> [Frontend & RUM](frontend_rum_observability.md),
> [API & HTTP Observability](api_http_observability.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md) và
> [Telemetry Governance](telemetry_governance_finops.md).

---

## 1. Vì sao mobile observability khó?

Ứng dụng chạy trên:

- hàng nghìn model/chip/GPU;
- nhiều OS/API level;
- battery/thermal state;
- mạng đổi liên tục;
- foreground/background;
- process bị hệ điều hành kill;
- app version cũ tồn tại lâu;
- store rollout có độ trễ;
- người dùng offline hoặc không consent.

Backend deploy xong ngay; mobile release không thể thu hồi tức thời.

---

## 2. Android và Apple không cùng semantics

Crash, ANR, hang, launch, frame và session được platform/reporting tool định nghĩa khác nhau.
Không gộp thành một metric “mobile health” trước khi chuẩn hóa:

- numerator;
- denominator;
- eligibility;
- sampling;
- time window;
- foreground/background;
- device/app version.

---

## 3. Bắt đầu từ user journey

```text
install/update
→ launch
→ login
→ screen ready
→ interaction
→ network/offline operation
→ local persistence/sync
→ business outcome
```

Crash-free không chứng minh journey usable hoặc data sync đúng.

---

## 4. Các nhóm signal

- stability: crash, ANR, hang, termination;
- performance: startup, screen, frame, interaction;
- network: request, connectivity, radio;
- resource: CPU, memory, disk, battery, thermal;
- correctness: offline/sync/business;
- release/device/OS;
- logs, traces và breadcrumbs;
- store/platform vitals.

---

## 5. Mobile SLO

Ví dụ:

- crash-free active sessions;
- user-perceived crash/ANR rate;
- cold start p75;
- screen interactive p75;
- critical journey success/latency;
- sync freshness;
- network success;
- battery/thermal budget.

Chọn threshold theo sản phẩm; store bad-behavior threshold chỉ là guardrail bên ngoài.

---

## 6. Session semantics

Định nghĩa:

- foreground session;
- background period;
- inactivity timeout;
- process restart;
- multiple windows/scenes;
- crash kết thúc session;
- day/user denominator.

Android Vitals có thể tính theo daily active user trong khi SDK tính theo app session.

---

## 7. App/build identity

Mỗi signal cần:

- package/bundle ID;
- version name;
- build/version code;
- distribution channel;
- commit/release;
- feature flags/config;
- symbol/source-map set.

“v5.2” không đủ nếu nhiều build cùng marketing version.

---

## 8. Release distribution

Theo dõi:

- staged rollout percentage;
- active installs/sessions theo build;
- update adoption;
- store review/release state;
- crash/performance theo build;
- rollback/halt;
- minimum supported version.

So regression với traffic mix tương đương và sample đủ.

---

## 9. Device fragmentation

Segment hữu hạn theo:

- device model/family;
- SoC/CPU/GPU class;
- memory class;
- screen/refresh class;
- ABI;
- manufacturer;
- low-RAM mode.

Per-model outlier quan trọng nhưng dễ cardinality cao; dùng top impacted và minimum sample.

---

## 10. OS fragmentation

Theo dõi OS major/minor hoặc API level cần thiết:

- crash/hang;
- permission behavior;
- background limits;
- networking/TLS;
- rendering;
- storage;
- telemetry API availability.

Không giữ full build fingerprint làm label.

---

## 11. Network conditions

Mobile chuyển giữa Wi-Fi/cellular/offline, NAT và captive portal. Ghi:

- connectivity class;
- metered/roaming nếu được phép;
- request error taxonomy;
- DNS/connect/TLS;
- bytes;
- retry;
- offline queue.

Network type là hint, không phải throughput guarantee.

---

## 12. Offline-first

Đo:

- offline operation success;
- queued mutations;
- oldest queue age;
- sync start/end/error;
- conflict;
- duplicate;
- local storage error;
- data freshness.

“API request không xảy ra” có thể là thiết kế đúng khi offline.

---

## 13. App/process lifecycle

Các state:

```text
not running → launch → foreground
↔ background/suspended
→ termination/crash/kill
```

Instrumentation phải flush có giới hạn, phục hồi context và không suy diễn mọi termination là
crash.

---

## 14. Cold, warm và hot start

Tách startup vì công việc khác nhau:

- cold: process/runtime/app khởi tạo;
- warm: process còn nhưng activity/scene cần dựng;
- hot: app còn state và quay foreground nhanh.

So sánh cùng start type; ưu tiên tối ưu cold-start critical path.

---

## 15. Android TTID và TTFD

- **TTID**: thời gian tới initial display;
- **TTFD**: thời gian tới fully drawn/usable theo app signal.

Đo:

- process/app initialization;
- first frame;
- data/auth;
- dependency injection;
- disk/network;
- reportFullyDrawn semantics.

Initial display có skeleton chưa chứng minh user thao tác được.

---

## 16. Apple app launch

Phân biệt cold/warm/resume và pre-main/post-main khi tooling cho phép. Quan sát:

- dynamic loading;
- static initialization;
- app/scene delegate;
- first frame;
- data restore;
- main-thread work;
- launch termination.

MetricKit/Xcode aggregate cần map đúng release/device.

---

## 17. Screen load

Định nghĩa:

```text
navigation/action
→ screen creation
→ initial content visible
→ required data ready
→ interactive
```

Tên screen là template hữu hạn, không chứa document/user ID.

---

## 18. Rendering và jank

Frame budget phụ thuộc refresh rate. Theo dõi:

- slow/frozen frames theo platform/tool;
- frame duration distribution;
- screen/action;
- UI/render thread;
- release/device/thermal;
- animation/scroll.

Không dùng một ngưỡng 16 ms cho mọi display và mọi metric semantics.

---

## 19. Responsiveness

Interaction latency gồm:

```text
input
→ main/UI thread scheduling
→ handler/state update
→ layout/render
→ visible frame
```

Instrument tap-to-result ở critical actions, không tạo span cho mọi touch coordinate.

---

## 20. Android ANR

ANR thường liên quan main thread hoặc component không đáp ứng đúng thời hạn. Điều tra:

- ANR type;
- main-thread stack;
- lock/contention;
- binder/I/O;
- startup;
- broadcast/service;
- device/OS;
- affected users.

Crash và ANR có denominator/impact riêng.

---

## 21. Apple hangs và hitches

Hang là khoảng app không phản hồi; hitch là gián đoạn chuyển động/render. Quan sát:

- hang/hitch rate/duration;
- main-thread/run-loop stack;
- screen/state;
- launch/interaction;
- device/OS/release;
- Xcode Organizer/MetricKit coverage.

Aggregated report khoanh vùng; Instruments dùng để tái lập sâu.

---

## 22. Crash

Thu:

- exception/signal;
- normalized stack;
- thread;
- app state;
- release;
- device/OS;
- breadcrumbs an toàn;
- affected users/sessions;
- previous OOM/memory warning nếu biết.

Không log toàn bộ object graph hoặc user data.

---

## 23. Symbolication và deobfuscation

Cần exact artifacts:

- Android mapping file;
- native debug symbols;
- Apple dSYM;
- source maps cho hybrid;
- build ID/UUID;
- upload validation;
- access control/retention.

Thiếu symbol làm grouping sai và runbook chậm.

---

## 24. OOM và low-memory termination

Process có thể bị kill do:

- app vượt memory;
- system pressure;
- foreground/background priority;
- native/graphics memory;
- memory leak;
- large allocation.

Không phải mọi kill có stack crash. Nối memory warning, last-known state, OS diagnostics và
next-launch marker có kiểm soát.

---

## 25. Memory

Theo dõi/lab-profile:

- Java/Kotlin/Swift/ObjC heap;
- native heap;
- graphics/image;
- cache;
- retained screens;
- allocation churn;
- GC/ARC pressure;
- memory warning.

Production sampling phải nhẹ; heap dump từ thiết bị người dùng có privacy risk lớn.

---

## 26. CPU

CPU cao gây:

- battery drain;
- thermal throttling;
- jank;
- slow startup;
- background limit.

Đo aggregate CPU time, hot state/journey và release; dùng profiler trong lab để tìm function,
không continuous profile mọi thiết bị mặc định.

---

## 27. Battery và energy

Nguồn:

- wake lock/wakeup;
- background task;
- network radio;
- location/sensor;
- CPU/GPU;
- animation;
- polling;
- disk.

Đo theo user journey/thời gian và platform reports. Không tối ưu battery bằng phá sync
freshness mà không đổi contract.

---

## 28. Thermal

Thermal pressure có thể giảm CPU/GPU và frame rate. Khi API cho phép:

- ghi thermal state bucket;
- correlate jank/startup/battery;
- giảm workload/quality;
- tránh fingerprinting;
- test trên real device.

Emulator không tái hiện đầy đủ thermal behavior.

---

## 29. Mobile HTTP metrics

Đo:

- normalized endpoint;
- method/status/error;
- duration;
- request/response bytes;
- retry;
- cache;
- cancellation;
- foreground/background;
- network class.

Không ghi URL/query/token thô.

---

## 30. DNS, connect và TLS

Nếu network stack expose, tách:

- DNS;
- TCP/QUIC connect;
- TLS;
- request upload;
- server wait;
- response download.

Connection reuse, proxy/VPN và network transition ảnh hưởng. Certificate pinning failure cần
taxonomy nhưng không log certificate/user secrets tùy tiện.

---

## 31. Nối mobile với backend trace

Client span → gateway/server span cần:

- W3C Trace Context hoặc contract tương thích;
- trusted destination allowlist;
- sampling;
- request deadline;
- app/build attributes;
- user privacy;
- validation ở server.

Trace context là correlation, không phải authentication.

---

## 32. Context qua async

Mobile có callback, coroutine, async/await, background task và process death. Context có thể:

- mất;
- giữ quá lâu;
- gắn nhầm session;
- truyền vào retry mới.

Test propagation qua network, local queue và background worker; không serialize toàn baggage.

---

## 33. OpenTelemetry Android

OpenTelemetry Android cung cấp auto/manual instrumentation và RUM trên nền Java ecosystem.
Trước rollout:

- pin SDK;
- kiểm tra supported API;
- đo startup/binary/network overhead;
- consent;
- offline buffer;
- exporter security;
- kill switch;
- schema compatibility.

---

## 34. Apple MetricKit

MetricKit cung cấp on-device performance/power metrics và diagnostics. Report có delivery,
aggregation và OS availability riêng; API mới có thể khác OS cũ.

Thiết kế:

- capability detection;
- exact Codable/schema version;
- dedup;
- secure upload;
- symbolication;
- daily/event-based expectations;
- simulated-report tests.

---

## 35. Logs

Mobile log cần:

- structured event/error code;
- release;
- screen/action template;
- trace/span ID;
- severity;
- lifecycle/network state bucket.

Không upload toàn logcat/device console, keyboard/input, token hoặc file path nhạy cảm.

---

## 36. Breadcrumbs

Breadcrumbs giúp timeline trước crash:

- screen transition;
- button/action category;
- network outcome;
- lifecycle;
- feature flag;
- memory warning.

Giới hạn ring buffer, redaction và event taxonomy. Không ghi text/value người dùng.

---

## 37. User actions

Instrument business action:

```text
action start
→ local validation
→ network/offline queue
→ UI result
→ eventual sync outcome
```

Tap count không đủ; cần result và time-to-feedback.

---

## 38. Screen transaction

Screen span/transaction cần:

- screen template;
- start/ready/end semantics;
- parent navigation;
- network/local dependencies;
- render/interaction;
- error.

Đóng span khi screen background/replace theo contract, tránh span kéo dài vô hạn.

---

## 39. Background work

Android WorkManager/service và Apple background execution có quota/lifecycle riêng. Theo dõi:

- scheduled/start delay;
- run duration;
- success/retry/cancel;
- constraint;
- expiration;
- queue age;
- process restart;
- business freshness.

Không giả định job sẽ chạy đúng thời điểm.

---

## 40. Push notification

Vòng đời:

```text
provider accepted
→ push service
→ device received
→ displayed
→ opened
→ journey/outcome
```

Không phải mọi platform cung cấp delivery receipt. Tách accepted, received và opened; bảo vệ
payload/token.

---

## 41. Deep links

Theo dõi:

- source category;
- route template;
- parse/validation;
- auth redirect;
- screen ready;
- unsupported version;
- fallback;
- journey success.

Không ghi full deep-link URL/query vì có thể chứa token/PII.

---

## 42. Local database

Đo:

- open/migration;
- read/write latency/error;
- transaction;
- corruption;
- disk full;
- encryption/key;
- database size;
- main-thread access.

Không ghi SQL bind values hoặc database contents.

---

## 43. Cache

Theo dõi:

- memory/disk hit/miss;
- stale/fresh;
- eviction;
- decode;
- size;
- version mismatch;
- invalidation;
- fallback.

Cache hit nhanh nhưng hiển thị dữ liệu cũ vẫn là correctness incident.

---

## 44. Synchronization

SLI:

- last successful sync age;
- pending changes;
- upload/download;
- conflict;
- server rejection;
- duplicate;
- partial sync;
- retry age;
- reconciliation.

Sync success transport không chứng minh local state và server state hội tụ đúng.

---

## 45. Retry

Mobile retry đặc biệt nguy hiểm do:

- network chuyển trạng thái;
- app background;
- process restart;
- offline queue;
- nhiều SDK layer;
- user nhấn lại.

Persist idempotency key/attempt phù hợp, exponential backoff+jitter và deadline/expiry.

---

## 46. Upload và download

Theo dõi:

- bytes/progress;
- resume;
- checksum/integrity;
- network class;
- background execution;
- cancellation;
- storage;
- retry;
- final business outcome.

Request duration đơn lẻ không đủ cho transfer dài.

---

## 47. Permissions

Đo:

- prompt shown;
- granted/denied/restricted;
- permanent denial;
- feature fallback;
- OS/version;
- journey impact.

Không dùng telemetry để gây áp lực xin lại quyền. Chỉ hỏi đúng lúc và giải thích mục đích.

---

## 48. Security

Theo dõi có kiểm soát:

- TLS/pinning failure;
- auth/session refresh;
- integrity/attestation result bucket;
- secure storage error;
- tamper/root/jailbreak signal nếu hợp pháp;
- credential rotation.

Client signal không đáng tin tuyệt đối; không expose anti-abuse logic trong telemetry.

---

## 49. Consent

Consent state ảnh hưởng signal được thu và gửi. Yêu cầu:

- default phù hợp luật/policy;
- granular purposes;
- version/timestamp;
- revocation;
- delete/export;
- offline handling;
- SDK không khởi tạo trước consent nếu bị cấm.

---

## 50. PII và device fingerprint

Kết hợp model, OS, locale, IP, carrier và IDs có thể fingerprint người dùng. Giảm:

- coarse buckets;
- short-lived random ID;
- minimum sample;
- no advertising ID mặc định;
- no hardware serial;
- retention ngắn;
- access control.

---

## 51. Crash-free metrics

Phân biệt:

```text
crash-free sessions
crash-free users
user-perceived crash rate
crash occurrences
```

Một user crash nhiều lần ảnh hưởng numerator khác tùy metric. Dashboard phải ghi công thức.

---

## 52. Denominator và coverage

Store vitals, SDK và first-party events khác:

- eligible devices;
- consent;
- distribution channel;
- active user/session;
- time zone/window;
- SDK initialized;
- offline upload.

Không so phần trăm nếu denominator khác.

---

## 53. Outlier theo model/OS

Một regression chỉ trên GPU/OS/model có thể bị global average che. Ưu tiên theo:

- affected users;
- severity;
- device market share;
- reproducibility;
- release;
- business journey.

Áp dụng minimum sample để tránh noise và privacy leak.

---

## 54. Startup SLO

Tách:

- cold/warm/hot;
- initial display;
- fully usable;
- first-run/migration;
- logged-in/out;
- device class.

Store excessive threshold không thay product SLO; dùng p50/p75/p95 và slow-session ratio.

---

## 55. Screen/journey SLO

Ví dụ:

- product screen usable dưới 1,5 giây;
- payment action phản hồi dưới 300 ms;
- checkout hoàn tất dưới 10 giây;
- offline mutation sync trong 5 phút sau reconnect.

Đo từ user action đến visible/eventual outcome.

---

## 56. Business funnel

```text
launch → login → browse → cart → checkout → confirmation
```

Tách drop-off do:

- user choice;
- validation;
- crash/hang;
- network;
- backend;
- permission;
- UX latency.

Không dùng funnel telemetry để thu nội dung nhạy cảm.

---

## 57. Dashboard

```text
Journey/release
  → crash/ANR/hang
  → startup/screen/render
  → network/offline/sync
  → device/OS/region
  → backend trace
  → battery/resource
```

Hiển thị denominator, sample rate, store/SDK source và adoption cạnh rate.

---

## 58. Alerting

Page/halt rollout khi:

- crash/ANR/hang regression có sample đủ;
- critical journey burn;
- auth/network widespread failure;
- data loss/sync corruption;
- startup/render regression nghiêm trọng;
- telemetry mất sau release.

Không page một crash occurrence; group theo fingerprint/release/impact.

---

## 59. Store/platform vitals

Android Vitals và Xcode/MetricKit thấy một số failure trước SDK init hoặc do OS quan sát. Chúng
có độ trễ và privacy thresholds riêng.

Ingest vào workflow:

- source timestamp;
- report window;
- build/device;
- dedup;
- ownership;
- ticket/alert;
- compare, không cưỡng ép bằng SDK metric.

---

## 60. Incident workflow

```text
1. Xác nhận release, platform, model/OS và journey
2. Kiểm tra denominator/coverage
3. Tách crash, hang, performance, network, sync
4. Symbolicate/group
5. Correlate rollout/feature/config/backend
6. Tái lập real device nếu có thể
7. Halt rollout/disable feature/server mitigation
8. Ghi evidence và phát hành fix
```

---

## 61. Feature flags và rollout

Mobile flag/config phải:

- có default an toàn;
- cache/expiry;
- target coarse và hợp pháp;
- audit;
- kill switch;
- không phá offline;
- tương thích app cũ;
- observable exposure/outcome.

Remote disable thường nhanh hơn store hotfix nhưng không thay fix bền vững.

---

## 62. Synthetic và device lab

Kết hợp:

- emulator/simulator;
- physical device matrix;
- startup benchmark;
- UI journey;
- network shaping;
- battery/thermal test;
- background/permission;
- upgrade/migration;
- offline/reconnect.

Lab không thay field data; field aggregate không thay profiler/reproduction.

---

## 63. Telemetry budget

SDK quan sát cũng tiêu:

- binary size;
- startup;
- CPU/memory;
- battery;
- network bytes;
- disk queue;
- privacy budget.

Đặt giới hạn event/span/session, offline buffer, retention và remote kill switch. Đo chính SDK
overhead trong canary.

---

## 64. Workshop, checklist và câu hỏi

### Workshop

1. Chọn một mobile journey.
2. Định nghĩa session, startup và screen-ready.
3. Nối crash/ANR/hang với exact build.
4. Instrument network + offline queue + sync outcome.
5. Test slow network, process death và low-memory.
6. Xác nhận symbolication, dashboard, alert và consent.

### Checklist

- [ ] Android/iOS metrics không bị gộp sai semantics.
- [ ] Exact build/symbol artifacts được giữ.
- [ ] Crash/ANR/hang có affected-user/session denominator.
- [ ] Cold/warm/hot và initial/fully-ready được tách.
- [ ] Rendering theo refresh/device context.
- [ ] Offline queue/sync có age và correctness signal.
- [ ] Network trace chỉ gửi tới allowlist.
- [ ] Device/OS dimension có cardinality/privacy guardrail.
- [ ] Store vitals và SDK coverage được ghi rõ.
- [ ] Telemetry overhead, consent và kill switch đã test.

### Câu hỏi

1. Vì sao crash-free session và user-perceived crash rate khác nhau?
2. Cold, warm và hot start khác gì?
3. TTID có chứng minh app usable không?
4. ANR khác crash thế nào?
5. OOM/LMK vì sao có thể không có crash stack?
6. Vì sao không dùng 16 ms cho mọi display?
7. MetricKit report có delivery semantics nào cần lưu ý?
8. Poll network retry qua process restart gây duplicate ra sao?
9. Sync transport success có chứng minh data hội tụ không?
10. Device dimensions có thể tạo fingerprint thế nào?
11. Store vitals và SDK rate vì sao không khớp?
12. Kill switch quan trọng với mobile release ra sao?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Android

- [Android Vitals](https://developer.android.com/topic/performance/vitals)
- [Android crashes](https://developer.android.com/topic/performance/vitals/crash)
- [Diagnose ANRs](https://developer.android.com/topic/performance/anrs/diagnose-and-fix-anrs)
- [App startup time](https://developer.android.com/topic/performance/vitals/launch-time)
- [Slow rendering](https://developer.android.com/topic/performance/vitals/render)
- [Measure app performance](https://developer.android.com/topic/performance/measuring-performance)

### Apple

- [MetricKit](https://developer.apple.com/documentation/metrickit)
- [Monitoring app performance with MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)
- [Performance and metrics](https://developer.apple.com/documentation/xcode/performance-and-metrics)
- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)

### OpenTelemetry

- [OpenTelemetry client-side apps](https://opentelemetry.io/docs/platforms/client-apps/)
- [OpenTelemetry Android](https://opentelemetry.io/docs/platforms/client-apps/android/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)

Chủ đề tiếp theo gợi ý:
[Serverless & Functions Observability](serverless_functions_observability.md) – cold starts,
invocation lifecycle, concurrency,
timeouts, retries, event sources, distributed traces, cost và platform limits.

---

*Cập nhật lần cuối: 2026-07-30*
