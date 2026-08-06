# API Design – thiết kế hợp đồng khó dùng sai

> API tốt không chỉ “đẹp” ở URL. Nó giúp client hoàn thành một use case với ít
> round-trip, thể hiện đúng semantics, chịu được retry, tiến hóa không phá consumer
> và không làm lộ dữ liệu/quyền ngoài ý muốn.

---

## 1. API là hợp đồng, không phải lớp bọc database

Một API contract gồm:

- resource/operation và ý nghĩa nghiệp vụ;
- request/response schema;
- authentication và authorization;
- error, retry và idempotency semantics;
- consistency/freshness;
- pagination, filtering và ordering;
- quota/rate limit;
- compatibility và lifecycle;
- SLO: latency, availability, payload limit.

```text
Client intent
   ↓
API contract ──▶ domain capability
   ↑                   │
ổn định hơn       implementation có thể đổi
```

Nếu endpoint phản chiếu từng table/column, migration database sẽ thành breaking
change. API nên bám vào vocabulary của domain và use case của consumer.

---

## 2. Bắt đầu từ consumer journey

Trước khi đặt URL:

1. Consumer là browser, mobile, partner, service nội bộ hay batch job?
2. Họ muốn hoàn thành use case nào?
3. Cần phản hồi ngay hay chấp nhận job bất đồng bộ?
4. Tần suất, payload, fan-out và latency budget?
5. Dữ liệu nào consumer được phép nhìn/sửa?
6. Retry sau timeout có an toàn không?
7. Contract phải sống bao lâu và ai sở hữu?

Ví dụ “màn hình chi tiết đơn hàng” cần 12 API call thường là dấu hiệu API thiết kế
theo bảng/service nội bộ thay vì consumer journey. Có thể cần composition/BFF hoặc
read model, không nhất thiết thêm endpoint CRUD.

---

## 3. Chọn kiểu API theo bài toán

| Kiểu | Phù hợp | Đánh đổi |
|---|---|---|
| REST/HTTP | Public API, resource, cache, hệ sinh thái rộng | Over/under-fetch nếu use case phức tạp |
| gRPC | Internal typed RPC, low-latency, streaming | Browser/public tooling và debugging khó hơn |
| GraphQL | Client cần data shape linh hoạt, nhiều view | Query cost, auth field-level, cache/N+1 |
| Event/AsyncAPI | Fan-out, burst, temporal decoupling | Eventual consistency, duplicate, replay |
| Webhook | Server thông báo cho partner/client server | Delivery, signature, retry, endpoint của client |
| SSE/WebSocket | Server push/realtime session | Stateful connection và backpressure |

Một sản phẩm có thể dùng REST bên ngoài, gRPC nội bộ và event cho integration.
Không cần ép toàn hệ thống dùng một protocol.

---

## 4. REST: resource và URI

URI xác định resource; HTTP method mang ý nghĩa thao tác:

```http
GET    /orders
POST   /orders
GET    /orders/{orderId}
PUT    /orders/{orderId}
PATCH  /orders/{orderId}
DELETE /orders/{orderId}
```

Nguyên tắc:

- danh từ rõ nghĩa, nhất quán số ít/số nhiều;
- ID là opaque, client không suy diễn cấu trúc;
- không đưa action nguy hiểm vào `GET`;
- nesting chỉ khi resource thật sự phụ thuộc parent;
- tránh URL mô phỏng toàn bộ object graph.

```http
GET /orders/{orderId}/items

# Action có state/result riêng có thể model thành subresource
POST /orders/{orderId}/cancellations
POST /orders/{orderId}/payment-attempts
```

`POST /orders/{id}/cancel` đôi khi thực dụng, nhưng subresource thường giúp diễn đạt
idempotency, trạng thái và audit rõ hơn.

---

## 5. HTTP method: safe và idempotent

| Method | Safe theo HTTP | Idempotent theo HTTP | Dùng phổ biến |
|---|---|---|---|
| GET | Có | Có | Đọc representation |
| HEAD | Có | Có | Đọc metadata |
| POST | Không | Không mặc định | Tạo/process command |
| PUT | Không | Có | Tạo/thay thế state tại URI đã biết |
| PATCH | Không | Không mặc định | Cập nhật một phần |
| DELETE | Không | Có | Xóa mapping/resource |

Idempotent nghĩa là nhiều request giống nhau có **intended effect** như một request;
response và audit log vẫn có thể khác.

PATCH có thể được thiết kế idempotent:

```json
// Merge-patch kiểu “đặt giá trị” có thể idempotent
{"status": "CANCELLED"}

// Operation “tăng thêm 1” không idempotent
{"op": "increment", "path": "/retryCount", "value": 1}
```

Với concurrent update, dùng `ETag`/`If-Match`, không chỉ dựa vào method.

---

## 6. Status code: mô tả outcome cho client và proxy

| Code | Dùng khi |
|---|---|
| `200 OK` | Thành công, có representation |
| `201 Created` | Tạo resource; trả `Location` nếu có URI |
| `202 Accepted` | Đã nhận nhưng chưa hoàn tất; cung cấp status resource |
| `204 No Content` | Thành công, không có body |
| `304 Not Modified` | Conditional GET dùng cache |
| `400 Bad Request` | Request syntax/shape không hợp lệ |
| `401 Unauthorized` | Chưa có hoặc credential không hợp lệ |
| `403 Forbidden` | Đã nhận diện nhưng không được phép |
| `404 Not Found` | Không có resource hoặc cố ý che sự tồn tại |
| `409 Conflict` | Xung đột với state/idempotency/version |
| `412 Precondition Failed` | `If-Match`/precondition không thỏa |
| `422 Unprocessable Content` | Shape đúng nhưng semantic validation sai |
| `429 Too Many Requests` | Vượt rate/quota; có thể kèm `Retry-After` |
| `500 Internal Server Error` | Lỗi không mong đợi phía server |
| `502 Bad Gateway` | Gateway nhận response lỗi từ upstream |
| `503 Service Unavailable` | Tạm không phục vụ/quá tải/bảo trì |
| `504 Gateway Timeout` | Gateway hết thời gian chờ upstream |

Không trả `200` với body `{"success": false}` cho lỗi HTTP. Client, cache, proxy và
telemetry sẽ hiểu sai.

---

## 7. Error contract với Problem Details

RFC 9457 định nghĩa `application/problem+json`:

```http
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json

{
  "type": "https://api.example.com/problems/invalid-order",
  "title": "Order validation failed",
  "status": 422,
  "detail": "Two fields require correction.",
  "instance": "/problems/01J9Q2...",
  "errors": [
    {"field": "items[0].quantity", "code": "OUT_OF_RANGE"},
    {"field": "shippingAddress", "code": "REQUIRED"}
  ],
  "traceId": "4fd0..."
}
```

Quy tắc:

- client quyết định bằng stable `type`/`code`, không parse `detail`;
- `detail` giúp người dùng sửa request, không chứa stack trace/SQL/secret;
- `status` trong body phải khớp HTTP status;
- validation error có path/code machine-readable;
- `traceId` hỗ trợ tra cứu, không phơi thông tin nội bộ;
- document từng problem type và retry semantics.

---

## 8. Idempotency cho POST và side effect

HTTP `POST` không idempotent mặc định, nhưng business operation có thể hỗ trợ:

```http
POST /payments
Idempotency-Key: checkout-ord-123-capture-v1
Content-Type: application/json

{"orderId": "ord-123", "amountMinor": 590000, "currency": "VND"}
```

Server lưu:

```text
(tenant, operation, key)
  → request_hash, PROCESSING|COMPLETED|FAILED, response, expires_at
```

Hành vi:

- cùng key + cùng payload → trả kết quả cũ/trạng thái hiện tại;
- cùng key + payload khác → `409 Conflict`;
- hai request concurrent → chỉ một owner thực thi;
- crash ở `PROCESSING` → recovery/lease/query, không charge lại mù;
- TTL được công bố hoặc ít nhất dài hơn retry window.

Không dùng request ID ngẫu nhiên do gateway tạo làm idempotency key: retry của
client sẽ có request ID mới. Key phải đại diện cùng **business intent**.

Đọc [Distributed Transactions](distributed_transactions.md) mục 12 để triển khai
atomic và tránh race condition.

---

## 9. Optimistic concurrency với ETag

Ngăn lost update:

```http
GET /orders/123
ETag: "v7"

PATCH /orders/123
If-Match: "v7"
Content-Type: application/merge-patch+json

{"shippingAddress": "..."}
```

Nếu resource đã sang `v8`:

```http
HTTP/1.1 412 Precondition Failed
```

Client reread, hiển thị conflict hoặc merge. ETag phải thay đổi khi representation
liên quan thay đổi; strong ETag phù hợp concurrency, weak ETag chủ yếu cache
equivalence.

Đừng để API read-modify-write quan trọng chấp nhận update không có version/
precondition nếu nhiều actor có thể cùng sửa.

---

## 10. Pagination ổn định

### 10.1 Offset

```http
GET /orders?limit=50&offset=100
```

Ưu: nhảy trang dễ. Nhược: offset sâu có thể đắt; insert/delete giữa hai lần đọc gây
trùng hoặc bỏ sót.

### 10.2 Cursor/keyset

```http
GET /orders?limit=50&after=eyJjcmVhdGVkQXQiOiIuLi4iLCJpZCI6Ii4uLiJ9
```

Response:

```json
{
  "data": [],
  "page": {
    "next": "opaque-signed-cursor",
    "hasMore": true
  }
}
```

Cursor nên:

- opaque và có integrity/signature nếu chứa state;
- mã hóa toàn bộ sort tuple, ví dụ `(createdAt, id)`;
- có tie-breaker unique;
- gắn filter/sort hoặc reject khi client tái dùng sai;
- có expiry nếu snapshot/state không sống mãi.

Ordering phải deterministic:

```sql
ORDER BY created_at DESC, id DESC
```

Chỉ `ORDER BY created_at` sẽ không ổn định khi nhiều row cùng timestamp.

---

## 11. Filter, sort, field selection và expansion

```http
GET /orders?status=CONFIRMED&createdAfter=2026-07-01
GET /orders?sort=-createdAt,id
GET /orders?fields=id,status,total
GET /orders?include=items
```

Cần allowlist:

- field được filter/sort;
- operator và độ phức tạp;
- page size tối đa;
- include depth;
- field nhạy cảm không bao giờ được expose.

Không nối trực tiếp tên field/operator vào SQL. Query linh hoạt là bề mặt DoS:
sort không index, regex rộng, include graph sâu có thể làm cạn DB.

Field selection không thay authorization. Server phải loại field không được phép
dù client có yêu cầu hay không.

---

## 12. Async operation và long-running job

Không giữ HTTP connection cho job vài phút:

```http
POST /exports

HTTP/1.1 202 Accepted
Location: /operations/op-789
Retry-After: 3
```

Status resource:

```json
{
  "id": "op-789",
  "status": "RUNNING",
  "progress": 42,
  "createdAt": "...",
  "result": null,
  "error": null
}
```

State:

```text
PENDING → RUNNING → SUCCEEDED
                  → FAILED
                  → CANCELLED
```

API cần định nghĩa:

- idempotency khi tạo job;
- polling interval/backoff hoặc webhook;
- cancel semantics;
- result URL và expiry;
- retry/restart của worker;
- authorization trên operation/result;
- `FAILED` có retryable hay cần request mới.

`202` chỉ nói request được chấp nhận, không nói tác vụ cuối cùng thành công.

---

## 13. Webhook là API giao ngược

Provider gọi endpoint của consumer:

```text
Your system ─event──▶ Partner webhook endpoint
```

Thiết kế production:

- delivery at-least-once; event có ID để dedup;
- exponential backoff + jitter và thời hạn retry;
- ký **raw body + timestamp** bằng secret bất đối xứng hoặc HMAC;
- reject timestamp quá cũ để chống replay;
- endpoint trả nhanh sau khi persist, xử lý async;
- không theo redirect tùy ý;
- timeout và payload limit;
- portal xem delivery, rotate secret và replay có audit;
- thứ tự không được mặc định nếu không cam kết.

Consumer không nên thực hiện side effect trước khi verify signature và dedup.

SSRF là rủi ro khi cho người dùng đăng ký webhook URL: validate scheme/host, chặn
private/link-local/metadata IP cả sau DNS resolution và redirect.

---

## 14. Compatibility trước versioning

Deploy độc lập cần thay đổi additive:

| Thay đổi | Thường an toàn? |
|---|---|
| Thêm response field | Có nếu client bỏ qua field lạ |
| Thêm optional request field | Có |
| Thêm enum value | Có thể phá client `switch` đóng |
| Đổi field optional thành required | Không |
| Rename/xóa field | Không |
| Đổi type/format/unit | Không |
| Đổi default/sort/order semantics | Có thể breaking |
| Thắt validation | Có thể breaking |

Breaking change không chỉ là schema. Từ `amount` đơn vị đồng sang xu, đổi ordering,
giảm page size hoặc thay authorization đều có thể phá consumer.

Contract test và telemetry usage quan trọng hơn việc chỉ so sánh OpenAPI diff.

---

## 15. Chiến lược version

Các lựa chọn:

```text
Path   : /v2/orders
Header : Accept: application/vnd.example.orders.v2+json
Date   : API-Version: 2026-07-31
```

Không có cách thắng tuyệt đối:

| Cách | Ưu | Nhược |
|---|---|---|
| Path | Dễ nhìn, route và document | URI chứa version, dễ duplicate API |
| Media type/header | URI ổn định | Debug/cache/gateway khó hơn |
| Date/account pinning | Consumer upgrade có kiểm soát | Server duy trì nhiều behavior |

Nguyên tắc:

- chỉ tạo version mới khi có breaking change đáng giá;
- version contract, không version deployment;
- không áp Semantic Versioning máy móc lên từng endpoint;
- hỗ trợ version cũ có thời hạn và owner;
- cung cấp migration guide, sandbox và usage telemetry;
- deprecation không đồng nghĩa shutdown ngay.

Tránh chạy `/v1` và `/v2` như hai codebase copy-paste. Dùng adapter/compatibility
layer quanh domain core nếu có thể.

---

## 16. Deprecation và sunset

Lifecycle:

```text
PROPOSED → BETA → STABLE → DEPRECATED → SUNSET → RETIRED
```

Khi deprecate:

- công bố ngày và lý do;
- chỉ ra replacement/migration;
- xác định consumer còn dùng bằng API key/client ID;
- gửi cảnh báo có chủ đích;
- dùng header `Deprecation`/`Sunset` nếu ecosystem hỗ trợ;
- dashboard usage và error của migration;
- không tắt khi vẫn còn consumer quan trọng chưa có đường chuyển.

API inventory phải biết owner, version, exposure (public/internal), data class và
consumer. “Shadow API” không ai sở hữu là rủi ro bảo mật lẫn vận hành.

---

## 17. gRPC: typed contract và deadline

```protobuf
syntax = "proto3";

service OrderService {
  rpc GetOrder(GetOrderRequest) returns (Order);
  rpc ListOrderEvents(ListOrderEventsRequest)
      returns (stream OrderEvent);
}

message GetOrderRequest {
  string order_id = 1;
}
```

### 17.1 Compatibility Protobuf

- không đổi nghĩa hoặc type không tương thích của field;
- không tái sử dụng field number đã xóa; dùng `reserved`;
- thêm field mới với default semantics rõ;
- enum thêm value có thể làm client cũ gặp `UNRECOGNIZED`;
- package/service/method là contract;
- rollout server/consumer lệch phiên bản phải được test.

```protobuf
message Order {
  string id = 1;
  reserved 2;          // field cũ không tái sử dụng
  OrderStatus status = 3;
}
```

### 17.2 Deadline và cancellation

gRPC không mặc định đặt deadline; client phải đặt deadline thực tế. Server cần:

- propagate deadline xuống dependency;
- dừng công việc khi call bị cancel/deadline;
- không retry non-idempotent RPC mù;
- phân biệt `INVALID_ARGUMENT`, `FAILED_PRECONDITION`, `ABORTED`,
  `UNAVAILABLE`, `DEADLINE_EXCEEDED`.

`DEADLINE_EXCEEDED` vẫn có thể xảy ra dù server đã hoàn tất state change; operation
thay đổi state vẫn cần idempotency.

---

## 18. REST và gRPC không chỉ khác serialization

| | REST/JSON | gRPC/Protobuf |
|---|---|---|
| Contract | OpenAPI/JSON Schema tùy mức kỷ luật | `.proto` là trung tâm |
| Browser/public | Thuận lợi | Thường cần gateway/gRPC-Web |
| Human debug | Dễ | Cần tooling |
| Streaming | SSE/WebSocket/chunked tùy use case | 4 kiểu RPC streaming |
| Compatibility | Convention + schema/test | Field-number rules chặt |
| Cache HTTP/CDN | Tự nhiên hơn cho GET | Không tự nhiên |
| Internal typed clients | Codegen tùy chọn | Codegen phổ biến |

Chọn theo ecosystem và requirement. JSON chậm hay Protobuf nhanh không đủ để quyết
định nếu bottleneck thật là database hoặc downstream.

---

## 19. GraphQL: schema theo capability

```graphql
type Query {
  order(id: ID!): Order
}

type Mutation {
  cancelOrder(input: CancelOrderInput!): CancelOrderPayload!
}

type Order {
  id: ID!
  status: OrderStatus!
  total: Money!
  items(first: Int!, after: String): OrderItemConnection!
}
```

Ưu:

- client chọn field cần;
- schema typed và introspection;
- một request compose nhiều graph relationship;
- evolution additive tự nhiên.

Đánh đổi:

- mọi request thường vào một endpoint nên HTTP cache/rate per URL kém trực tiếp;
- query cost thay đổi mạnh;
- authorization phải kiểm tra object và field;
- resolver dễ N+1;
- error có thể partial trong response `200`.

GraphQL không phải database query mở cho client. Schema phải diễn đạt capability
được cho phép, không expose ORM tùy ý.

---

## 20. N+1, batching và query cost trong GraphQL

```text
query 100 orders
  resolver orders      : 1 query
  resolver customer/order: 100 queries  ← N+1
```

Dùng request-scoped batching/DataLoader:

```text
collect customerIds → SELECT ... WHERE id IN (...) → map result
```

Phòng vệ:

- depth/complexity/cost limit;
- page size và node count tối đa;
- timeout/deadline;
- persisted/allowlisted query cho client tin cậy;
- rate limit theo estimated cost, không chỉ request count;
- field-level authorization;
- disable/restrict introspection theo threat model, không xem đó là phòng thủ chính;
- observe resolver latency và downstream fan-out.

Batching GraphQL cũng có thể bypass rate limit theo request. Sensitive flow như
login/password reset phải giới hạn theo operation/account/IP và cost.

---

## 21. Authentication và authorization

Phân biệt:

- **Authentication**: caller là ai?
- **Authorization**: caller có được thực hiện action này trên object/field này?

```text
token hợp lệ
  ≠ được xem order bất kỳ
  ≠ được sửa mọi field của chính order
```

Checklist:

- OAuth 2.0 cho delegated API authorization; OpenID Connect cho identity/login;
- validate issuer, audience, signature, expiry và algorithm;
- access token ngắn hạn, scope tối thiểu;
- không nhận `tenantId` từ body rồi tin mù; derive/validate theo principal;
- object-level authorization trên mọi `{id}`;
- property-level allowlist để chống mass assignment;
- function-level authorization cho admin action;
- service-to-service dùng workload identity, không shared API key lâu dài;
- secret/token không nằm trong URL/log.

RFC 9700 là Best Current Practice cho bảo mật OAuth 2.0; các flow cũ không nên được
chọn chỉ vì ví dụ lịch sử còn tồn tại.

---

## 22. Input, output và resource limits

Validate theo nhiều lớp:

| Lớp | Ví dụ |
|---|---|
| Shape/type | JSON Schema, Protobuf |
| Size | body, header, string, array, upload |
| Semantic | `start < end`, currency hỗ trợ |
| Authorization | field/action/object |
| Resource cost | page size, query depth, regex, export range |

Output cũng phải allowlist. Trả thẳng ORM entity dễ lộ:

- password hash/internal flags;
- tenant ID;
- field vừa thêm vào database;
- lazy relationship tạo N+1;
- circular graph.

Mass assignment xảy ra khi client gửi field không nên sửa:

```json
{"displayName": "An", "role": "ADMIN", "creditLimit": 999999999}
```

Dùng request DTO/command riêng và allowlist field theo operation.

---

## 23. Rate limit, quota và overload

Phân biệt:

- **rate limit**: tốc độ trong khoảng ngắn;
- **quota**: tổng lượng theo ngày/tháng/gói;
- **concurrency limit**: số request/job đang chạy;
- **load shedding**: bảo vệ hệ thống khi saturation.

Key có thể là tenant + user + operation; IP chỉ là một tín hiệu.

Response nên ổn định:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 5
Content-Type: application/problem+json
```

Không chỉ giới hạn request count. Một export 10 năm, GraphQL query sâu hoặc upload
lớn có cost khác một `GET /health`.

Đọc [Rate Limiting](../saas/rate_limiting.md) để xem thuật toán và distributed
counter.

---

## 24. Cache và conditional request

REST GET có thể tận dụng HTTP cache:

```http
Cache-Control: private, max-age=60
ETag: "order-123-v7"
Vary: Accept-Encoding, Authorization
```

Client revalidate:

```http
If-None-Match: "order-123-v7"
→ 304 Not Modified
```

Cẩn thận:

- response cá nhân/tenant không được cache public;
- `Vary` thiếu có thể rò dữ liệu giữa representation;
- authorization và CDN cache key phải đúng;
- invalidation/TTL phù hợp freshness;
- `no-store` cho dữ liệu cực nhạy cảm;
- cache error/negative response có policy riêng.

Không thêm cache nếu API mutation/semantics chưa rõ.

---

## 25. OpenAPI và contract-as-code

OpenAPI mô tả:

- path, operation, parameter;
- request/response và schema;
- security scheme;
- status/error;
- example, callback/webhook;
- server và metadata lifecycle.

OpenAPI 3.2.0 là bản phát hành mới nhất tại thời điểm cập nhật tài liệu này.

Contract pipeline:

```text
proposal
  → lint/style
  → schema + breaking-change check
  → security review
  → mock/consumer feedback
  → server/client generation tùy chọn
  → contract/integration test
  → publish portal
```

Spec không tự bảo đảm implementation đúng. Test response thật với contract; tránh
generate domain code cứng vào tool nếu nó làm khó thiết kế.

---

## 26. Testing

| Test | Bắt lỗi |
|---|---|
| Schema/contract | Thiếu field, sai type/status |
| Consumer-driven contract | Provider thay đổi phá consumer thật |
| Compatibility diff | Breaking change trong OpenAPI/Proto/GraphQL |
| Authorization matrix | BOLA/BFLA/property access |
| Idempotency/concurrency | Duplicate và race |
| Fuzz/property | Parser/validation edge case |
| Load/cost | p99, query sâu, payload lớn |
| Resilience | timeout, retry, partial failure |
| E2E | Một số journey quan trọng |

Test cả negative path:

- token đúng nhưng object thuộc tenant khác;
- cùng idempotency key với payload khác;
- update với ETag cũ;
- cursor bị sửa hoặc dùng với filter khác;
- webhook signature sai/replay;
- request timeout sau khi mutation đã commit.

---

## 27. Observability theo contract

Metric:

- request rate, error, latency theo operation/status class;
- authn/authz denial;
- rate/quota rejection;
- payload size và response size;
- dependency latency;
- idempotency replay/conflict;
- API version/client usage;
- GraphQL cost/resolver hot spot;
- webhook delivery/retry/age.

Không dùng raw path `/orders/123` làm label; chuẩn hóa route
`/orders/{orderId}` để tránh cardinality.

Log:

```text
request_id, trace_id, client_id, tenant_id,
operation_id, api_version, status, latency,
idempotency_key_hash, error_type
```

Redact token, secret và PII. Business outcome như checkout success quan trọng hơn
chỉ đếm `200`.

---

## 28. Ví dụ: API checkout

### 28.1 Tạo order idempotent

```http
POST /orders
Idempotency-Key: cart-88-submit-v1

{
  "cartId": "cart-88",
  "shippingAddressId": "addr-7"
}
```

```http
HTTP/1.1 202 Accepted
Location: /operations/checkout-123

{
  "operationId": "checkout-123",
  "status": "PENDING",
  "orderId": "ord-123"
}
```

### 28.2 Theo dõi

```http
GET /operations/checkout-123
```

```json
{
  "status": "ACTION_REQUIRED",
  "orderId": "ord-123",
  "action": {
    "type": "CONFIRM_PAYMENT",
    "expiresAt": "2026-07-31T10:15:00Z"
  }
}
```

### 28.3 Cancel có concurrency control

```http
POST /orders/ord-123/cancellations
Idempotency-Key: cancel-ord-123-user-7
If-Match: "order-v9"
```

Possible outcomes:

- `201`: cancellation resource đã tạo;
- replay cùng key: trả cùng cancellation;
- `409`: order đã shipped, business conflict;
- `412`: order version đổi, client cần reread;
- `401/403/404`: authn/authz/existence policy.

API thể hiện state machine và recovery của
[Distributed Transactions](distributed_transactions.md), không hứa request HTTP
duy nhất sẽ hoàn tất mọi service ngay lập tức.

---

## 29. Failure modes thường gặp

| Anti-pattern | Hậu quả | Thay bằng |
|---|---|---|
| API phản chiếu table | DB migration phá client | Contract theo domain/use case |
| Action nguy hiểm bằng GET | Crawler/prefetch kích hoạt | POST/DELETE đúng semantics |
| Mọi lỗi trả 200 | Client/proxy/metric hiểu sai | HTTP status + Problem Details |
| POST retry không key | Duplicate side effect | Business idempotency key |
| Offset sâu cho feed realtime | Chậm, trùng/bỏ item | Cursor/keyset |
| Cursor chỉ base64, client sửa được | Query sai/leak | Opaque + integrity + validation |
| Version cho mọi thay đổi | Nhiều API song song | Additive evolution trước |
| Auth ở gateway là đủ | BOLA/lateral movement | Authorization tại resource |
| Trả ORM entity | Lộ field/mass assignment | DTO/allowlist |
| GraphQL limit theo request count | Query đắt làm cạn DB | Cost/depth/node limit |
| Webhook xử lý trước verify | Forgery/replay | Verify raw body + timestamp + dedup |
| Không API inventory | Shadow/dead API | Owner, lifecycle, usage telemetry |

---

## 30. Decision checklist

- [ ] Consumer journey, SLO và owner rõ.
- [ ] Đã chọn REST/gRPC/GraphQL/event theo requirement.
- [ ] Resource/operation dùng vocabulary của domain.
- [ ] Method và status code đúng semantics.
- [ ] Error có stable machine-readable type/code.
- [ ] Mutation retry được hoặc có idempotency contract.
- [ ] Concurrent update có version/ETag khi cần.
- [ ] Pagination deterministic; cursor opaque và được validate.
- [ ] Async job có status, cancel, expiry và retry semantics.
- [ ] Compatibility rule và deprecation timeline rõ.
- [ ] Authn khác authz; kiểm object/property/function.
- [ ] Input/output/resource cost đều có allowlist/limit.
- [ ] Contract có spec, test và breaking-change check.
- [ ] Metric theo normalized operation, client và version.
- [ ] Không log secret/token/PII.

---

## 31. Câu hỏi phỏng vấn thường gặp

1. Safe khác idempotent thế nào?
2. PATCH có luôn non-idempotent không?
3. Khi nào dùng `409`, khi nào `412`?
4. Timeout sau POST payment thì client retry thế nào?
5. Cursor pagination tránh duplicate ra sao?
6. Một thay đổi additive schema có thể vẫn breaking khi nào?
7. Vì sao không cần tạo version mới cho mọi field?
8. gRPC deadline và idempotency liên quan thế nào?
9. GraphQL N+1 và query-cost attack được xử lý ra sao?
10. Token hợp lệ vì sao vẫn có thể bị BOLA?
11. Làm sao ký và chống replay webhook?
12. `202 Accepted` cần status resource gì?

---

## 32. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [RFC 9110 – HTTP Semantics](https://www.rfc-editor.org/rfc/rfc9110.html)
- [RFC 9457 – Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457.html)
- [OpenAPI Specification 3.2.0](https://spec.openapis.org/oas/v3.2.0.html)
- [GraphQL Specification – September 2025](https://spec.graphql.org/September2025/)
- [gRPC – Deadlines](https://grpc.io/docs/guides/deadlines/)
- [RFC 9700 – Best Current Practice for OAuth 2.0 Security](https://www.rfc-editor.org/rfc/rfc9700.html)
- [OWASP API Security Top 10 – 2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)

Đọc tiếp:

- [Microservices](microservices.md) – gateway, BFF và contract giữa service.
- [Distributed Transactions](distributed_transactions.md) – idempotency,
  unknown outcome và workflow.
- [Event-Driven Architecture](event_driven_architecture.md) – async contract,
  event schema và delivery.
- [Networking & Protocols](../fundamentals/networking_protocols.md) – HTTP,
  TLS, SSE và WebSocket.
- [Rate Limiting](../saas/rate_limiting.md) – thuật toán và distributed limit.

---

*Cập nhật lần cuối: 2026-07-31*
