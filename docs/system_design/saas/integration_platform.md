---
title: "SaaS Integration Platform – APIs, Webhooks & Connectors"
topic: system_design
level: advanced
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "OpenAPI 3.2, AsyncAPI 3.1 và RFC 9457; đối chiếu ngày 2026-08-10"
source_count: 9
---

# SaaS Integration Platform – APIs, Webhooks & Connectors

> Thuật ngữ: [Glossary](../glossary.md).

Chương này tập trung vào product surface dành cho hệ thống bên ngoài: public API, webhook, bulk transfer, connector và marketplace app. HTTP/API semantics nền tảng nằm tại [API Design](../advanced/api_design.md).

## 1. Chọn integration primitive theo luồng

| Nhu cầu | Primitive khởi đầu |
|---|---|
| Client hỏi/ghi đồng bộ | REST/gRPC/GraphQL API |
| Provider báo thay đổi | Webhook |
| Consumer cần stream lớn | Event stream/CDC có contract |
| Import/export nhiều dữ liệu | Async bulk job + object storage |
| Đồng bộ với SaaS bên thứ ba | Managed connector |
| Cho đối tác mở rộng sản phẩm | OAuth app + marketplace |

Không ép mọi thứ qua synchronous API. Integration cần deadline, retry, ordering và recovery khác request người dùng.

## 2. Kiến trúc ba plane

```text
Management plane
  app registration, credential, webhook endpoint, connector config, quota
                         │ desired config/version
                         ▼
Delivery/runtime plane
  API gateway | webhook dispatcher | connector worker | bulk worker
                         │
                         ▼
Evidence plane
  delivery log, audit, replay, usage, SLO, customer diagnostics
```

Management plane hỏng không nên dừng delivery đang dùng last-known-good config. Runtime không được log raw secret/token vào evidence plane.

## 3. Integration identity và tenant boundary

Mỗi integration cần entity riêng:

```text
integration_id
tenant_id
type: API_CLIENT | WEBHOOK | CONNECTOR | MARKETPLACE_APP
owner
scopes/capabilities
credential_refs
status
config_revision
created_at / expires_at / last_used
```

Nguyên tắc:

- credential luôn tenant-scoped trừ provider control-plane credential có governance riêng;
- app identity khác user identity;
- delegated access lưu actor/grant/audience/scope;
- revoke tenant A không ảnh hưởng tenant B;
- resource lookup vẫn kiểm tenant, không chỉ tin client ID;
- mọi config change có audit và optimistic concurrency.

## 4. Public API là product contract

API production cần:

- stable resource identifier;
- consistent pagination/filter/sort;
- idempotency cho create/action retry được;
- optimistic concurrency bằng version/ETag khi phù hợp;
- standard error format;
- rate/quota headers có semantics rõ;
- changelog, deprecation và sunset policy;
- SDK/generated client compatibility test;
- tenant-aware authorization;
- inventory endpoint/version đang deploy.

OpenAPI mô tả interface, nhưng không tự giải quyết semantic compatibility, authorization hay operational recovery.

## 5. Versioning và compatibility

Ưu tiên additive evolution:

- thêm optional field;
- consumer bỏ qua field không biết;
- enum cần unknown behavior;
- không đổi unit/timezone/meaning của field cũ;
- không biến optional thành required;
- pagination cursor opaque;
- lỗi mới có stable machine code;
- default mới chỉ áp vào version/revision mới khi ảnh hưởng hành vi.

Breaking change cần version mới hoặc migration contract có telemetry biết consumer nào còn dùng cũ.

## 6. Idempotency cho command API

```http
POST /v1/exports
Idempotency-Key: 5c07...
```

Server persist:

```text
(tenant_id, operation, idempotency_key)
  → request_hash + response/status + expiry
```

- cùng key/cùng request trả kết quả cũ hoặc trạng thái operation;
- cùng key/khác request trả conflict;
- record được commit cùng business effect hoặc qua transaction/outbox phù hợp;
- TTL dài hơn retry window công bố;
- không dùng key global bỏ tenant scope;
- timeout sau unknown outcome dẫn client tới status resource.

## 7. Async job API

Với export/import/report lớn:

```http
POST /exports       → 202 Accepted + Location: /operations/op_123
GET  /operations/op_123
DELETE /operations/op_123  // request cancellation, không hứa đã dừng ngay
```

State machine:

```text
QUEUED → RUNNING → SUCCEEDED
              ├─→ FAILED
              └─→ CANCELLING → CANCELLED
```

Operation resource có progress, timestamps, result expiry, safe error code và correlation ID. Không trả stack trace hoặc internal bucket path.

## 8. Problem Details và machine-readable error

RFC 9457 định nghĩa `application/problem+json`. Ví dụ SaaS:

```json
{
  "type": "https://docs.example.com/problems/quota-exceeded",
  "title": "Quota exceeded",
  "status": 429,
  "detail": "Project creation limit reached.",
  "instance": "/problems/req_123",
  "code": "PROJECT_LIMIT_REACHED",
  "request_id": "req_123"
}
```

Client branch theo `type`/`code`, không parse `detail`. Error không lộ existence của resource tenant khác.

## 9. Webhook delivery là at-least-once

Pipeline tham chiếu:

```text
Domain transaction + Outbox
        │
        ▼
Event canonicalization
        │ select subscriptions/filter
        ▼
Delivery record ── queue ── signer ── HTTP endpoint
        │                              │
        └── attempt log ◄──────────────┘
                 │ retry/DLQ/replay
```

Không gọi endpoint khách hàng trực tiếp trong transaction nghiệp vụ.

## 10. Webhook event contract

```json
{
  "id": "evt_01J...",
  "type": "invoice.finalized.v1",
  "tenant_id": "tn_acme",
  "occurred_at": "2026-08-10T09:00:00Z",
  "resource": {"type": "invoice", "id": "inv_123"},
  "data": {"...": "versioned snapshot or minimal payload"},
  "api_version": "2026-08-01",
  "sequence": 1842
}
```

`sequence` chỉ có ý nghĩa nếu scope ordering được định nghĩa, ví dụ per resource hoặc per tenant partition. Không hứa global order nếu kiến trúc không cung cấp.

## 11. Webhook signing và replay protection

Header ví dụ:

```text
Webhook-Id: evt_01J...
Webhook-Timestamp: 1786352400
Webhook-Signature: v1=<HMAC(timestamp + "." + raw_body)>
```

Consumer cần:

- verify trên raw bytes;
- constant-time compare;
- timestamp tolerance;
- accept nhiều secret trong rotation window;
- dedupe event/delivery ID;
- chỉ trả 2xx sau khi đã persist an toàn;
- xử lý duplicate và out-of-order.

TLS cần thiết nhưng không thay message signature khi consumer cần xác minh payload/provider.

## 12. Retry, endpoint health và DLQ

Retry trên timeout, network error, 408, 429 và 5xx theo policy; phần lớn 4xx không retry mãi. Dùng exponential backoff + jitter.

Endpoint state:

```text
ACTIVE → DEGRADED → DISABLED
   ▲         │          │
   └─probe/recover──────┘ admin/customer action
```

Guardrail:

- attempt budget và max age;
- per-tenant/end-point concurrency;
- `Retry-After` có cap;
- circuit breaker tránh endpoint chết chiếm worker;
- DLQ có reason và replay tool;
- replay tạo attempt mới nhưng giữ event identity;
- customer xem được delivery status và response excerpt đã redact.

## 13. Snapshot hay thin event

### Snapshot payload

Consumer ít phải gọi lại API, nhưng payload chứa dữ liệu nhạy cảm và dễ stale.

### Thin event

Chỉ có resource ID/type; consumer gọi API lấy state mới. Ít dữ liệu trong webhook nhưng tăng load và cần quyền/token.

Chọn theo privacy, volume, offline processing và semantic: event “đã xảy ra” khác notification “hãy lấy state mới”.

## 14. Subscription và filter

Subscription config:

- endpoint URL;
- event type/version;
- tenant/app owner;
- filter được allowlist, không arbitrary code;
- secret version;
- status;
- delivery policy;
- created/updated actor;
- verification state.

Filter evaluation phải tenant-safe và có cost limit. Không cho biểu thức tùy ý dẫn tới DoS hoặc đọc field nhạy cảm.

## 15. Connector runtime

Connector chủ động gọi API bên thứ ba:

```text
Scheduler/event trigger
      ▼
Connector orchestrator
      ▼
tenant-scoped worker sandbox
  ├─ token vault reference
  ├─ egress policy
  ├─ checkpoint/cursor
  ├─ rate budget
  └─ transform/schema version
```

Mỗi run có operation ID, input checkpoint, output checkpoint, item counts, partial failure và retry policy.

## 16. Credential và OAuth grant

- token/secret lưu trong vault, database chỉ giữ reference/metadata;
- encryption key và access policy tenant-scoped;
- refresh đồng bộ để tránh nhiều worker cùng rotate token;
- refresh token rotation/reuse error được xử lý;
- scope tối thiểu;
- revoke/delete khi connector bị disable/offboard;
- never log Authorization header;
- test connection không được tạo side effect ngoài contract.

OAuth app cần exact redirect URI, state/PKCE theo flow và best practice hiện hành; không dùng implicit grant cho thiết kế mới.

## 17. Egress và SSRF defense

Connector/webhook URL là input nguy hiểm:

- chỉ HTTPS trừ môi trường test được cô lập;
- resolve DNS và chặn loopback, link-local, private/metadata range theo policy;
- chống DNS rebinding ở connect time;
- redirect được revalidate từng hop;
- port/protocol allowlist;
- outbound proxy/network policy;
- response size/time limit;
- không forward internal credential/header;
- customer-visible validation error không lộ topology.

## 18. Schema mapping và transformation

Transformation nên declarative, versioned và bounded:

- source schema/version;
- target schema/version;
- field mapping và type conversion;
- timezone/unit/null semantics;
- PII classification;
- validation/reject policy;
- sample/test fixture;
- migration/rollback.

Arbitrary customer code cần sandbox mạnh, CPU/memory/time/egress limit và supply-chain governance; đừng nhúng trực tiếp vào application worker.

## 19. Checkpoint, incremental sync và reconciliation

```text
read page(cursor_in)
  → validate/transform
  → idempotent upsert or append
  → persist item evidence
  → commit cursor_out
```

Chỉ advance checkpoint sau khi effect cần thiết durable. Nếu source cursor không stable, dùng high-water mark + overlap window + dedupe.

Định kỳ full reconciliation để phát hiện delete/missing update mà incremental stream bỏ lỡ.

## 20. Bulk import/export

Pattern an toàn:

1. tạo operation;
2. cấp pre-signed upload/download URL ngắn hạn;
3. malware/content/type/size validation;
4. parse streaming, không load toàn file vào memory;
5. validate schema/version;
6. item-level result file;
7. idempotent apply hoặc dry-run;
8. retention/automatic deletion;
9. audit người tạo/tải;
10. tenant-scoped object key và encryption.

Import partial success cần contract rõ: atomic toàn file, per batch hay per row.

## 21. Marketplace app lifecycle

```text
DRAFT → REVIEW → PUBLISHED → INSTALLED → SUSPENDED/REVOKED
```

Review gồm:

- publisher identity;
- requested scope/capability;
- redirect/webhook domain;
- privacy/data handling;
- vulnerability/supply-chain evidence;
- support contact;
- version/update policy;
- uninstall cleanup;
- incident kill switch.

Tenant admin phải thấy app đang truy cập gì và revoke được.

## 22. Sandbox và developer experience

- test tenant/data không lẫn production;
- deterministic fixtures;
- webhook test event và replay;
- API explorer/SDK example không chứa real secret;
- test clock cho billing/time flow khi phù hợp;
- rate limit riêng;
- parity về contract nhưng không nhất thiết parity capacity;
- migration guide và changelog;
- request/delivery log self-service.

## 23. Observability và SLO

Theo dõi:

- API availability/latency/error theo operation/version;
- authz/rate-limit deny reason;
- webhook queue age, success, retry, DLQ và endpoint health;
- connector run duration, item throughput, checkpoint lag;
- credential expiry/refresh failure;
- third-party quota/time-to-exhaustion;
- import/export age và result expiry;
- cost per connector/event/tenant tier;
- deprecated version traffic và unknown client.

High-cardinality tenant/integration ID ở log/trace có access control; metric dùng cohort/type/result hợp lý.

## 24. Testing

- OpenAPI/AsyncAPI schema validation và breaking-change diff;
- consumer/provider contract test;
- idempotency cùng key và khác payload;
- webhook duplicate, out-of-order, timeout, 429, 5xx;
- signature rotation và replay window;
- connector token expiry/refresh race;
- checkpoint crash trước/sau commit;
- SSRF URL, redirect và DNS rebinding simulation;
- tenant A không xem/replay delivery tenant B;
- bulk file quá lớn/malformed/zip bomb;
- marketplace uninstall revoke mọi token/job/webhook.

## 25. Failure modes

| Failure mode | Hậu quả | Guardrail |
|---|---|---|
| Gọi webhook trong DB transaction | latency/rollback coupling | Outbox + async delivery |
| Hứa exactly-once webhook | consumer xử lý duplicate sai | at-least-once + event ID |
| Global ordering | bottleneck/ảo tưởng | ordering scope rõ |
| Retry mọi 4xx vô hạn | queue/cost tăng | classification + attempt/age budget |
| Log raw secret/response | credential/PII leak | vault + redaction |
| Connector advance cursor sớm | mất dữ liệu | effect durable rồi commit cursor |
| Chỉ incremental sync | drift/delete bị bỏ lỡ | reconciliation định kỳ |
| Customer URL gọi tự do | SSRF | egress validation/policy |
| Breaking API đổi âm thầm | integration outage | version/deprecation telemetry |

## 26. Checklist production

- [ ] Integration identity, credential, config và audit tenant-scoped.
- [ ] Public API có compatibility, idempotency và async-operation contract.
- [ ] Webhook dùng Outbox, signature, retry budget, DLQ và replay.
- [ ] Connector có vault, egress policy, checkpoint và reconciliation.
- [ ] Bulk transfer streaming, tenant-safe và có retention.
- [ ] Marketplace app có review, scope visibility, revoke và kill switch.
- [ ] Có sandbox, delivery diagnostics và deprecation telemetry.
- [ ] SLO đo cả provider-side success và end-to-end lag.

## 27. Nguồn và học tiếp

- [OpenAPI Specification](https://spec.openapis.org/oas/latest.html)
- [AsyncAPI Specification](https://www.asyncapi.com/docs/reference/specification/latest)
- [RFC 9457 – Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457)
- [RFC 9700 – OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700)
- [Stripe – Webhooks](https://docs.stripe.com/webhooks)
- [OWASP API Security Top 10 – 2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [OWASP SSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html)
- [CloudEvents Specification](https://github.com/cloudevents/spec)

Học tiếp: [API Design](../advanced/api_design.md), [Event-Driven Architecture](../advanced/event_driven_architecture.md) và [B2B Identity & Authorization](b2b_identity_authorization.md).

