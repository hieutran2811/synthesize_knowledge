# Microservices – chia hệ thống theo ranh giới nghiệp vụ

> Microservices không phải mục tiêu của một hệ thống trưởng thành. Nó là một cách
> đổi **độ phức tạp trong code** lấy **độ phức tạp vận hành hệ phân tán**, nhằm giúp
> các nhóm phát triển và triển khai độc lập.

---

## 1. Mô hình tư duy

Một microservice nên:

- sở hữu một năng lực nghiệp vụ rõ ràng trong một **bounded context**;
- che giấu dữ liệu và chi tiết triển khai sau API hoặc event;
- được một nhóm chịu trách nhiệm từ phát triển đến vận hành;
- có thể build, deploy, rollback và scale mà không buộc service khác deploy cùng;
- chấp nhận rằng network, dependency và message đều có thể chậm, lỗi hoặc lặp.

```text
Modular monolith
┌──────────────────────────────────────────────────┐
│ Orders module │ Payments module │ Inventory     │
│ API nội bộ rõ │ API nội bộ rõ   │ API nội bộ rõ │
├──────────────────────────────────────────────────┤
│             một process, một lần deploy          │
└──────────────────────────────────────────────────┘

Microservices
┌──────────┐ HTTP/event ┌──────────┐ event ┌───────────┐
│ Orders  │────────────▶│ Payments │──────▶│ Accounting│
│ DB riêng│             │ DB riêng │       │ DB riêng  │
└──────────┘             └──────────┘       └───────────┘
```

Điểm phân biệt không phải “code nhỏ” hay “chạy trong container”, mà là **ranh giới
thay đổi độc lập**. Một service 500 dòng nhưng phải deploy cùng năm service khác
vẫn là distributed monolith.

---

## 2. Khi nào chưa nên dùng microservices

Nên bắt đầu bằng **modular monolith** nếu:

- domain còn thay đổi nhanh, chưa biết ranh giới đúng;
- chỉ có một hoặc hai nhóm nhỏ cùng phát triển;
- quy trình build, test, deploy và quan sát sự cố chưa tự động;
- tải có thể xử lý bằng cách scale một ứng dụng và một database;
- tổ chức chưa sẵn sàng sở hữu service 24/7.

Microservices đáng cân nhắc khi có ít nhất một áp lực thật:

| Áp lực | Microservices có thể giúp |
|---|---|
| Nhiều nhóm giẫm lên nhau khi release | Tách quyền sở hữu và chu kỳ deploy |
| Một domain cần scale khác hẳn phần còn lại | Scale riêng theo workload |
| Một lỗi cục bộ thường kéo sập toàn ứng dụng | Tạo ranh giới cô lập lỗi |
| Một phần có yêu cầu bảo mật/compliance riêng | Cô lập dữ liệu và quyền truy cập |
| Monolith đã có module rõ nhưng build/deploy quá chậm | Tách dần module có giá trị cao |

Không nên tách chỉ vì “công ty lớn cũng làm vậy”. Ở quy mô nhỏ, network call,
eventual consistency, CI/CD cho nhiều service và on-call thường đắt hơn lợi ích.

---

## 3. Ranh giới service: business trước, bảng dữ liệu sau

### 3.1 Business capability và bounded context

Ví dụ cùng từ “customer” nhưng các context có mô hình khác nhau:

```text
Sales context       : Customer(id, leadScore, accountOwner)
Shipping context    : Recipient(id, address, deliveryNote)
Billing context     : Payer(id, taxCode, creditLimit)
```

Ép ba mô hình thành một `CustomerService` dùng chung tạo một “god service”.
Ngược lại, tách mỗi entity hoặc mỗi bảng thành một service tạo quá nhiều lời gọi
chatty. Điểm bắt đầu thực dụng:

1. Vẽ business capability và luồng nghiệp vụ.
2. Tìm dữ liệu và luật nghiệp vụ cần thay đổi cùng nhau.
3. Đặt invariant cần transaction mạnh trong cùng một ranh giới.
4. Xác định nhóm sở hữu và nhịp thay đổi.
5. Sau đó mới xem yêu cầu scale, bảo mật và công nghệ.

Một heuristic hữu ích: service thường **không nhỏ hơn một aggregate** và **không
lớn hơn một bounded context**. Đây là điểm khởi đầu, không phải công thức.

### 3.2 Dấu hiệu ranh giới sai

| Mùi thiết kế | Khả năng nguyên nhân |
|---|---|
| A gọi B rồi B gọi lại A trong cùng request | Hai service quá phụ thuộc |
| Mọi feature phải sửa và deploy 5 service | Chia theo tầng kỹ thuật, không theo capability |
| Service A đọc trực tiếp bảng của B | Ownership dữ liệu không thật |
| Hàng chục API call để dựng một màn hình | Ranh giới quá vụn hoặc thiếu read model/BFF |
| Cùng một field có nhiều “chủ sở hữu” | Chưa xác định source of truth |

Khi nghi ngờ, bắt đầu **coarse-grained**. Tách một service lớn có cohesion tốt
thường dễ hơn gom dữ liệu và transaction từ nhiều service đã tách sai.

---

## 4. Quyền sở hữu dữ liệu

“Database per service” nghĩa là service khác **không truy cập trực tiếp schema**
của owner; không nhất thiết mỗi service phải có một server database vật lý.

```text
✅ Cùng PostgreSQL cluster, schema/user tách biệt

Order Service  ─▶ orders schema
Payment Service ─▶ payments schema
                 quyền DB ngăn truy cập chéo

❌ Shared database như integration API

Order Service ─┐
Payment Service├─▶ cùng bảng orders, cùng sửa trạng thái
Shipping Service┘
```

Các cách đọc dữ liệu xuyên service:

| Cách | Dùng khi | Đánh đổi |
|---|---|---|
| API composition | Ít service, cần dữ liệu mới | Tăng latency và phép nhân availability |
| Materialized read model | Đọc nhiều, chấp nhận trễ | Phải đồng bộ, rebuild và theo dõi lag |
| Data warehouse/lake | Analytics, báo cáo | Không phù hợp transaction online |
| Sao chép có kiểm soát qua event | Consumer cần một phần dữ liệu | Schema event trở thành hợp đồng |

Không dùng distributed transaction để che một ranh giới domain sai. Nếu hai thay
đổi **luôn** phải atomic và không thể bù, hãy cân nhắc đặt chúng trong cùng service.

---

## 5. Giao tiếp đồng bộ hay bất đồng bộ

### 5.1 Đồng bộ: REST/gRPC

Dùng khi caller cần câu trả lời để hoàn thành request:

```text
Checkout ──reserve(orderId, items, deadline)──▶ Inventory
         ◀──────── reservationId ─────────────
```

- REST/HTTP phù hợp public API, CRUD/resource và hệ sinh thái rộng.
- gRPC phù hợp hợp đồng typed, internal RPC và streaming.
- Cả hai đều cần timeout, deadline propagation, connection pool và giới hạn payload.

Nhược điểm lớn nhất là coupling theo thời gian: B chậm thì A cũng chậm. Chuỗi
`Gateway → A → B → C` có availability xấp xỉ tích availability của từng hop.

### 5.2 Bất đồng bộ: command/event qua broker

Dùng khi producer không cần kết quả ngay, cần hấp thụ burst hoặc fan-out:

```text
Order Service ──OrderPlaced──▶ broker
                               ├─▶ Inventory consumer
                               ├─▶ Notification consumer
                               └─▶ Analytics consumer
```

Đổi lại phải xử lý duplicate, ordering, retry, poison message, lag và eventual
consistency. Xem chi tiết ở [Event-Driven Architecture](event_driven_architecture.md).

### 5.3 Quy tắc lựa chọn

| Câu hỏi | Có | Không |
|---|---|---|
| Người dùng cần kết quả ngay? | Đồng bộ | Có thể async |
| Công việc kéo dài hoặc tải burst? | Async + trả job ID | Đồng bộ có giới hạn |
| Một sự kiện có nhiều consumer độc lập? | Publish event | Gọi trực tiếp nếu chỉ một owner |
| Cần phản hồi lỗi nghiệp vụ tức thì? | Đồng bộ/command-response | Event |

Async không tự động làm hệ thống nhanh hơn; nó chuyển thời gian chờ sang queue và
giúp **điều tiết tải**.

---

## 6. Entry point: API Gateway và BFF

API Gateway là cửa vào cho client, thường chịu trách nhiệm:

- TLS termination, authentication cơ bản và rate limiting;
- route, cân bằng tải, canary và request size limit;
- correlation/trace ID và access log;
- đôi khi aggregate response đơn giản.

Không đặt business workflow phức tạp vào gateway; nếu không nó trở thành monolith
mới. Authorization theo nghiệp vụ vẫn phải được service kiểm tra.

**Backend for Frontend (BFF)** hữu ích khi mobile, web và partner có access pattern
rất khác nhau:

```text
Mobile ─▶ Mobile BFF ─┐
Web    ─▶ Web BFF    ─┼─▶ domain services
Partner─▶ Partner API ┘
```

Giá phải trả là nhiều API và logic composition hơn. Không tạo BFF riêng nếu các
client thực sự có cùng nhu cầu.

---

## 7. Service discovery và load balancing

Instance là tài nguyên tạm thời; client cần một tên ổn định.

```text
order-service.default.svc
            │ DNS/Service
            ▼
        EndpointSlice
       ├─ pod A
       ├─ pod B
       └─ pod C
```

Hai mô hình:

- **Client-side discovery**: client lấy danh sách endpoint và tự chọn; linh hoạt
  nhưng library phải đồng nhất giữa các ngôn ngữ.
- **Server-side discovery**: proxy/load balancer nhận endpoint; application đơn
  giản hơn nhưng thêm một hop.

Trong Kubernetes, `Service` cung cấp endpoint ổn định cho tập Pod thay đổi; Gateway
API hoặc Ingress đưa traffic từ ngoài cluster vào. Đừng xây một registry riêng nếu
runtime platform đã giải bài toán này.

Đọc thêm [Load Balancing](../fundamentals/load_balancing.md) về health check,
connection draining, P2C và bẫy cân bằng gRPC.

---

## 8. Service mesh: khả năng, không phải điều kiện bắt buộc

Service mesh chuyển một số chức năng network sang proxy/data plane:

```text
App A → proxy A ══ mTLS/traffic policy ══▶ proxy B → App B
                   ▲
              control plane
```

Có thể cung cấp workload identity, mTLS, traffic policy và telemetry thống nhất.
Nhưng nó thêm control plane, tài nguyên, latency, failure mode và kỹ năng vận hành.

Chỉ thêm mesh khi:

- có nhiều service/ngôn ngữ và khó chuẩn hóa client library;
- thật sự cần mTLS/identity hoặc traffic policy nhất quán;
- platform team có năng lực vận hành và debug cả application lẫn proxy.

Gateway xử lý traffic **north–south**; mesh chủ yếu xử lý **east–west**. Hai khái
niệm có thể cùng tồn tại nhưng không thay thế hoàn toàn cho nhau.

---

## 9. Thiết kế chịu lỗi cho mọi lời gọi ngoài

Mỗi dependency call cần một policy rõ:

1. **Deadline/timeout** ngắn hơn deadline còn lại của request.
2. **Retry** chỉ cho lỗi tạm thời và thao tác an toàn/idempotent; exponential
   backoff + jitter; chỉ retry ở một tầng.
3. **Circuit breaker** ngừng gửi khi dependency đang lỗi rõ ràng.
4. **Bulkhead** tách thread/connection/queue để một dependency không ăn hết tài nguyên.
5. **Load shedding** từ chối sớm khi quá tải.
6. **Fallback** chỉ dùng nếu dữ liệu cũ/giảm chức năng vẫn đúng nghiệp vụ.

```text
Client deadline: 1000 ms
  Gateway budget: 900 ms
    Order budget: 700 ms
      Payment budget: 400 ms
```

Không để mỗi hop dùng timeout 30 giây. Deadline phải giảm dần và được truyền xuống.
Đọc thêm [Availability & Reliability](../fundamentals/availability_reliability.md).

---

## 10. Consistency và workflow xuyên service

Một transaction ACID chỉ bảo vệ dữ liệu bên trong một service. Với workflow:

```text
Create order → reserve stock → charge payment → arrange shipping
```

các lựa chọn chính là:

- **Saga orchestration**: coordinator lưu state và phát command;
- **Saga choreography**: service phản ứng với event;
- **Transactional Outbox**: ghi business data và message vào cùng local transaction;
- **Compensation**: hoàn tiền/hủy giữ chỗ thay vì rollback thời gian.

Compensation là một hành động nghiệp vụ mới và cũng có thể thất bại; nó không phải
`ROLLBACK` phân tán. Thiết kế state machine, idempotency key và đường phục hồi thủ
công trước khi code happy path. Xem [Distributed Transactions](distributed_transactions.md).

---

## 11. Hợp đồng và khả năng tương thích

Deploy độc lập chỉ có thật nếu contract thay đổi độc lập:

- ưu tiên thay đổi **additive**: thêm field optional, thêm endpoint;
- producer mới phải chạy được với consumer cũ trong thời gian rollout;
- không tái sử dụng field với nghĩa khác;
- deprecate có deadline, telemetry và owner;
- dùng consumer-driven contract test cho interaction quan trọng;
- database migration theo **expand → migrate → contract**.

```text
1. Expand   : thêm field/cột mới, code đọc được cả cũ lẫn mới
2. Migrate  : backfill, dual-read/write nếu cần
3. Contract : bỏ field/cột cũ sau khi mọi consumer đã chuyển
```

Shared library chỉ nên chứa concern ổn định như auth client/telemetry. Chia sẻ
domain model giữa nhiều service tạo coupling và release đồng loạt.

---

## 12. Triển khai và ownership

Mỗi service production cần tối thiểu:

- owner/on-call, repository và runbook rõ;
- pipeline build, security scan, test, deploy, rollback;
- resource request/limit và autoscaling signal phù hợp;
- readiness, startup, shutdown/draining đúng;
- SLO và dashboard theo user journey, không chỉ CPU;
- backup/restore nếu sở hữu state;
- catalog ghi API/event, dependency và dữ liệu nhạy cảm.

**You build it, you run it** chỉ hiệu quả khi platform cung cấp paved road. Nếu mỗi
team phải tự dựng CI/CD, secret, telemetry và runtime từ đầu, autonomy biến thành
lãng phí và cấu hình không nhất quán.

---

## 13. Bảo mật theo ranh giới

Đừng xem mạng nội bộ là đáng tin:

- xác thực workload-to-workload bằng identity ngắn hạn; mTLS bảo vệ đường truyền;
- authorization đặt gần resource và kiểm tra tenant/role/action;
- token chỉ mang claim cần thiết, không truyền bí mật người dùng qua mọi service;
- dùng secret manager, rotation và quyền tối thiểu;
- NetworkPolicy/firewall giới hạn đường giao tiếp;
- log audit cho hành động nhạy cảm nhưng không ghi token/PII.

Gateway xác thực request không có nghĩa service phía sau được bỏ authorization.
Một service bị compromise vẫn có thể gọi ngang nếu mọi internal traffic được tin.

---

## 14. Kiểm thử theo kim tự tháp thực dụng

| Loại test | Mục tiêu |
|---|---|
| Unit/domain | Invariant và luật nghiệp vụ |
| Component | Service + database/broker thật hoặc gần thật |
| Contract | Producer/consumer có còn tương thích |
| Integration | Một số dependency quan trọng và failure path |
| End-to-end | Vài user journey sống còn, không kiểm mọi nhánh |
| Resilience | Timeout, duplicate, partial failure, broker/DB chậm |

E2E test cho mọi trường hợp sẽ chậm và flaky. Phần lớn logic nên được bảo vệ trong
service; contract test bảo vệ ranh giới; E2E chỉ xác nhận hệ thống ghép đúng.

---

## 15. Quan sát một request xuyên hệ thống

Cần liên kết ba loại tín hiệu bằng các ID ổn định:

```text
request_id / trace_id
  Gateway span
    Order span
      Inventory span
      Payment span

event_id + correlation_id + causation_id
  nối phần đồng bộ với phần xử lý bất đồng bộ
```

Theo dõi ít nhất:

- latency/error/rate của API theo service và dependency;
- saturation: thread, connection pool, queue;
- message lag, retry và DLQ;
- business outcome: checkout thành công, payment pending, order stuck.

Trace không thay thế log hay metric; mục tiêu là trả lời “request nào, qua đâu,
chậm/lỗi ở đâu và ảnh hưởng nghiệp vụ gì”.

---

## 16. Di chuyển từ monolith: Strangler Fig

Không big-bang rewrite. Tách một lát dọc có giá trị và đo được:

```text
Client → Router/Facade
          ├─ /legacy/* → Monolith
          └─ /catalog/* → Catalog Service
```

Quy trình:

1. Làm rõ module và ownership ngay trong monolith.
2. Chọn capability ít coupling, có áp lực scale/release hoặc pain rõ.
3. Đặt anti-corruption layer để model cũ không rò vào service mới.
4. Chuyển traffic dần, đối chiếu kết quả và chuẩn bị rollback.
5. Chuyển ownership dữ liệu; ngừng dual-write thiếu kiểm soát.
6. Xóa code/route cũ sau thời gian quan sát.

Nếu modular monolith chưa có ranh giới, việc tách process chỉ biến method call
thành network call mà không giảm coupling.

---

## 17. Ví dụ: checkout thương mại điện tử

### 17.1 Phân ranh giới

| Service | Sở hữu | Không sở hữu |
|---|---|---|
| Order | order state, item snapshot | số lượng tồn kho thật |
| Inventory | stock, reservation | trạng thái thanh toán |
| Payment | payment attempt, provider reference | order detail |
| Shipping | shipment, tracking | card/token thanh toán |

### 17.2 Luồng đề xuất

```text
Client ─POST /orders (idempotency-key)─▶ Order
Order  ─OrderPlaced─────────────────────▶ broker
Saga   ─ReserveInventory command────────▶ Inventory
       ◀InventoryReserved event─────────
Saga   ─ChargePayment command───────────▶ Payment
       ◀PaymentCaptured event───────────
Saga   ─ConfirmOrder────────────────────▶ Order
```

Nếu payment thất bại, saga phát `ReleaseInventory`. Nếu event lặp, consumer dùng
`event_id`/business key để bỏ qua. Nếu saga stuck, dashboard và thao tác vận hành
cho phép xem state, retry hoặc bù thủ công.

Điều quan trọng không phải broker nào, mà là invariant rõ: một order không được
`CONFIRMED` nếu chưa có reservation và payment hợp lệ.

---

## 18. Failure modes thường gặp

| Sự cố | Hậu quả | Phòng vệ |
|---|---|---|
| Dependency chậm nhưng chưa chết | Cạn thread/connection, lan truyền timeout | Deadline, bulkhead, load shedding |
| Retry storm | Dependency vừa hồi lại bị đánh sập | Backoff+jitter, retry budget, một tầng retry |
| Shared DB | Deploy/schema coupling, owner mơ hồ | API/event và quyền DB tách biệt |
| Chatty services | p99 cao, availability giảm | Gộp boundary, batch API, read model |
| Event/schema phá tương thích | Consumer cũ dừng | Additive change, schema/contract test |
| Deploy cùng lúc mới chạy | Distributed monolith | Backward compatibility, tách release |
| Không có owner | Alert không ai xử lý | Service catalog, on-call, SLO |
| Service mesh quá sớm | Debug thêm proxy/control plane | Chỉ thêm khi có nhu cầu và owner |

---

## 19. Decision checklist

Trước khi tách một service:

- [ ] Capability và source of truth được viết thành một câu rõ ràng.
- [ ] Lợi ích cần deploy/scale/secure độc lập là có thật và đo được.
- [ ] Invariant nào ở trong service, consistency nào chấp nhận eventual đã rõ.
- [ ] API/event contract có chiến lược compatibility.
- [ ] Mọi call ngoài có deadline, retry policy và idempotency phù hợp.
- [ ] Workflow partial failure có state machine và compensation.
- [ ] Có owner, pipeline, runbook, SLO, backup/restore.
- [ ] Đã tính thêm network hop, connection, broker và chi phí on-call.
- [ ] Có migration/rollback plan, không big-bang.

Nếu nhiều ô chưa đạt, cải thiện modular monolith và platform trước thường là quyết
định tốt hơn.

---

## 20. Câu hỏi phỏng vấn thường gặp

1. Vì sao microservices không đồng nghĩa với “service càng nhỏ càng tốt”?
2. Làm sao xác định bounded context và source of truth?
3. Shared database làm mất tính độc lập như thế nào?
4. Khi nào chọn RPC, khi nào chọn event?
5. Vì sao retry có thể làm sự cố nặng hơn?
6. Gateway khác service mesh ở đâu?
7. Làm sao deploy hai phiên bản API không phá nhau?
8. Saga compensation khác rollback ACID thế nào?
9. Distributed monolith có dấu hiệu gì?
10. Bạn sẽ tách module đầu tiên khỏi monolith bằng cách nào?

---

## 21. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [Microsoft Azure Architecture Center – Microservices architecture style](https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/microservices)
- [Microsoft Azure Architecture Center – Identify microservice boundaries](https://learn.microsoft.com/en-us/azure/architecture/microservices/model/microservice-boundaries)
- [Kubernetes – Services, Load Balancing, and Networking](https://kubernetes.io/docs/concepts/services-networking/)

Đọc tiếp:

- [Event-Driven Architecture](event_driven_architecture.md) – event, ordering,
  idempotency, replay và schema evolution.
- [Distributed Transactions](distributed_transactions.md) – Saga, Outbox và 2PC.
- [API Design](api_design.md) – thiết kế hợp đồng REST, GraphQL và gRPC.
- [Kafka roadmap](../../kafka/roadmap.md) – triển khai broker, producer và consumer.

---

*Cập nhật lần cuối: 2026-07-30*
