---
title: "Billing & Metering – đo usage và tính tiền có thể kiểm chứng"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "unspecified"
source_count: 6
---
# Billing & Metering – đo usage và tính tiền có thể kiểm chứng

> Thuật ngữ: [Glossary](../glossary.md).

> Billing là correctness domain: sai một event có thể thành sai hóa đơn, mất tiền
> hoặc mất niềm tin. Thiết kế tốt phải trả lời được “đơn vị này đến từ đâu, áp giá
> phiên bản nào, vì sao thành line item này và đã thu/hoàn tiền ra sao?”.

---

## 1. Tách năm khái niệm

```text
Product usage
  → Metering       : ghi nhận đơn vị đã tiêu thụ
  → Rating         : áp bảng giá thành số tiền
  → Invoicing      : phát hành khoản phải thu
  → Payment        : thu tiền/hoàn tiền
  → Accounting     : ghi nhận doanh thu, thuế, sổ cái
```

Không dùng một bảng `billing` cho tất cả.

| Khái niệm | Source of truth |
|---|---|
| Usage | Immutable usage ledger |
| Price/contract | Versioned product catalog |
| Charge calculation | Rating result/snapshot |
| Amount customer nợ | Invoice + adjustments |
| Tiền đã chuyển | Payment/refund/provider reconciliation |
| Revenue recognized | Accounting ledger/policy |

Invoice `PAID` không có nghĩa usage đúng; usage đúng không có nghĩa payment đã settle.

---

## 2. Bắt đầu từ billable metric

Billable metric phải:

- gắn với giá trị khách hàng hiểu;
- đo được nhất quán;
- khó bị thao túng;
- giải thích được trên invoice;
- reconcile được với nguồn nghiệp vụ;
- không thay semantics tùy ý giữa kỳ.

Ví dụ:

| Metric | Đơn vị | Điểm ghi nhận |
|---|---|---|
| API thành công | request | Sau khi business operation commit |
| Dữ liệu lưu | GB-hour | Snapshot/gauge định kỳ |
| Email gửi | message accepted/delivered | Chọn một semantics trong contract |
| Compute | vCPU-second | Runtime authoritative scheduler |
| AI | input/output token | Sau provider/model trả usage |
| Active seat | seat-day hoặc max seat | Membership state theo kỳ |

“API call” mơ hồ: request lỗi validation có tính không? Retry cùng idempotency key?
Cache hit? Internal call? Phải định nghĩa trước khi code.

---

## 3. Pricing model

### Flat, per-seat, usage và hybrid

```text
Flat      : 99 USD/tháng
Per-seat  : 15 USD/active seat/tháng
Usage     : 0,001 USD/1K events
Hybrid    : 99 USD + 100K included + overage
Commit    : trả trước 1M units, overage sau đó
```

### Volume khác graduated tier

Giả sử dùng 120 units:

```text
0–100  : 1,00/unit
101+   : 0,80/unit
```

- **Volume pricing**: toàn bộ 120 × 0,80 = 96.
- **Graduated pricing**: 100 × 1,00 + 20 × 0,80 = 116.

Đây là khác biệt hợp đồng, không phải chi tiết UI.

Các mô hình khác: package/block, stairstep, minimum spend, credit/prepaid, percentile
hoặc max gauge. Mỗi mô hình cần test boundary.

---

## 4. Kiến trúc tham chiếu

```text
Authoritative product action
      │
      ├─ local transaction + Outbox
      ▼
Usage event stream ──▶ Validation/Dedup ──▶ Raw Usage Ledger
                                                │
                                     Aggregate/Correction
                                                ▼
Product Catalog ──▶ Rating Engine ──▶ Draft Invoice
                                          │ finalize
                                          ▼
                                   Invoice / Payment Provider
                                          │ webhook
                                          ▼
                               Reconciliation + Customer Portal
```

Raw usage ledger phải tồn tại đủ lâu để rerate/rebuild. Redis counter chỉ phù hợp
preview/limit nhanh, không nên là source of truth hóa đơn.

---

## 5. Usage event contract

```json
{
  "eventId": "01JAG7...",
  "tenantId": "tenant-123",
  "customerAccountId": "acct-456",
  "meter": "ai.output_tokens",
  "meterVersion": 3,
  "quantity": "1842",
  "unit": "token",
  "occurredAt": "2026-07-31T08:15:31.123Z",
  "recordedAt": "2026-07-31T08:15:31.842Z",
  "source": "inference-service",
  "subject": "inference/req-789",
  "idempotencyKey": "inference-req-789-output",
  "dimensions": {
    "model": "model-family-a",
    "region": "ap-southeast"
  }
}
```

Quy tắc:

- `eventId` định danh bản ghi;
- `idempotencyKey` định danh cùng business consumption;
- quantity dùng decimal/integer chính xác, không `double`;
- `occurredAt` là event time; `recordedAt` dùng audit/lag;
- meter + version cố định semantics;
- dimension allowlist để tránh cardinality/PII;
- source và subject giúp reconcile;
- tenant/customer mapping do server tin cậy, không nhận mù từ client.

---

## 6. Ghi usage đúng điểm

Các anti-pattern:

```text
❌ Gateway đếm mọi HTTP request
   + service lại đếm business success
   → double charge

❌ Emit trước transaction
   → operation rollback nhưng usage vẫn tồn tại

❌ Fire-and-forget trong memory
   → process crash làm mất usage
```

Pattern:

```text
business state + usage outbox trong cùng local transaction
→ relay/CDC publish
→ metering dedup
```

Với external provider, record usage từ authoritative result/reference và có
reconciliation. Usage emission không được làm user request thất bại sau khi business
operation đã commit; Outbox tách reliability khỏi latency.

---

## 7. At-least-once và deduplication

Pipeline phải giả định event có thể lặp:

```sql
CREATE TABLE usage_event (
  event_id text PRIMARY KEY,
  tenant_id uuid NOT NULL,
  idempotency_key text NOT NULL,
  meter text NOT NULL,
  meter_version integer NOT NULL,
  quantity numeric(38, 9) NOT NULL,
  occurred_at timestamptz NOT NULL,
  payload jsonb NOT NULL,
  UNIQUE (tenant_id, meter, idempotency_key)
);
```

Dedup và insert phải atomic. Không:

```text
if (!exists(key)) insert(event)  // race
```

Cùng idempotency key nhưng quantity/dimensions khác phải vào conflict/quarantine,
không âm thầm giữ event đầu hoặc cộng cả hai.

---

## 8. Correction thay vì sửa lịch sử

Usage sai cần event điều chỉnh:

```json
{
  "eventId": "corr-002",
  "type": "USAGE_REVERSAL",
  "correctsEventId": "evt-001",
  "quantity": "-1842",
  "reasonCode": "PROVIDER_DUPLICATE"
}
```

Sau đó có thể phát usage đúng. Lợi ích:

- audit đầy đủ;
- aggregate rebuild được;
- biết ai/hệ thống nào sửa và vì sao;
- invoice adjustment có lineage.

Đừng `UPDATE quantity` hoặc xóa row đã dùng để tính invoice. Nếu kỳ đã finalize,
correction cần credit/debit adjustment theo policy, không rewrite hóa đơn cũ.

---

## 9. Raw ledger, aggregate và snapshot

Ba lớp:

```text
Raw events       : immutable, audit/rebuild
Time buckets     : tenant + meter + hour/day
Billing summary  : account + meter + billing period + catalog version
```

Aggregate:

- `SUM`: tokens, bytes transferred;
- `COUNT`: số event;
- `LAST`: gauge cuối kỳ;
- `MAX`: peak seats/concurrency;
- distinct/percentile: cần thuật toán và độ chính xác được công bố.

Không cộng aggregate lại nhiều lần. Upsert phải dựa trên version/checkpoint hoặc
rebuild deterministic từ raw event.

Approximate distinct (HLL) phù hợp analytics; dùng cho invoice chỉ khi hợp đồng cho
phép sai số và khách hàng hiểu. Billing thường cần exact hoặc source có thể audit.

---

## 10. Event time, late data và cutoff

Phân biệt:

| Time | Vai trò |
|---|---|
| `occurredAt` | Kỳ usage thuộc về |
| `recordedAt` | Khi platform nhận |
| `processedAt` | Khi aggregator xử lý |
| `invoiceFinalizedAt` | Khi không còn sửa draft |

Policy:

- timezone/cycle boundary rõ, thường lưu UTC;
- cho phép clock skew bao nhiêu;
- late event grace period;
- event quá muộn đưa kỳ hiện tại, adjustment kỳ sau hay credit note;
- future timestamp/quá cũ bị quarantine;
- watermark/checkpoint để biết kỳ đã đủ dữ liệu.

Không finalize đúng 00:00 nếu pipeline còn lag. Đóng kỳ là workflow có readiness
check, không chỉ cron.

---

## 11. Product catalog phải versioned

```text
product
  → price_version
      meter, currency, unit, tiers,
      included_quantity,
      effective_from, effective_to,
      tax_behavior, contract_id
```

Khi giá đổi, tạo version mới; không sửa row cũ:

```text
Usage occurred at T
→ tenant contract active at T
→ price version effective at T
→ deterministic rating
```

Customer có thể grandfathered price. Catalog phải phân biệt:

- public plan;
- tenant contract/override;
- promotional discount;
- credit;
- currency;
- effective time.

Config giá cần approval, audit, preview và four-eyes; typo giá là sự cố tài chính.

---

## 12. Tiền và số học

Không dùng `double`:

```java
record Money(String currency, BigInteger minorUnits) {}
```

Hoặc decimal với scale/rule rõ:

```text
quantity × unit price
→ intermediate precision
→ tier/discount/tax
→ round ở bước được định nghĩa
→ invoice minor units
```

Cần:

- currency đi cùng amount;
- zero-decimal/three-decimal currency được catalog hỗ trợ;
- rounding mode theo hợp đồng/pháp lý;
- phân bổ rounding remainder deterministic;
- không cộng hai currency;
- lưu input và calculation trace.

Ví dụ giá rất nhỏ/token cần precision cao trước khi round line item, không round mỗi
event về 0 rồi cộng.

---

## 13. Rating engine

Input:

```text
usage summary
tenant contract snapshot
price version
discount/credit eligibility
billing period
```

Output bất biến:

```json
{
  "ratingRunId": "rate-789",
  "accountId": "acct-456",
  "period": "[2026-07-01,2026-08-01)",
  "catalogVersion": "catalog-42",
  "lines": [{
    "meter": "ai.output_tokens",
    "quantity": "1200000",
    "included": "200000",
    "billable": "1000000",
    "amountMinor": 12500,
    "currency": "USD",
    "calculation": "graduated-v3"
  }]
}
```

Rating phải deterministic: cùng input/version → cùng output. Có dry-run, rerate,
golden tests và giải thích line item.

---

## 14. Proration và thay đổi plan

Các lựa chọn khi upgrade giữa kỳ:

- có hiệu lực ngay, prorate base fee;
- có hiệu lực kỳ sau;
- chia usage theo thời điểm/effective version;
- reset hay giữ included units;
- credit phần chưa dùng;
- không prorate usage đã tiêu thụ.

Đây là product contract. State machine plan:

```text
ACTIVE(v1)
 → CHANGE_SCHEDULED(v2 at next_cycle)
 → ACTIVE(v2)
```

Không chỉ cập nhật `tenant.plan = PRO`; phải snapshot contract và effective time để
invoice quá khứ không đổi khi tenant hiện tại đã sang plan khác.

---

## 15. Invoice lifecycle

```text
DRAFT
  → FINALIZED/OPEN
      → PAID
      → VOID
      → UNCOLLECTIBLE
```

`DRAFT` có thể nhận late usage/correction trong grace period. Sau finalize:

- số invoice và line item cần ổn định;
- sửa bằng credit note/debit adjustment/new invoice tùy policy;
- payment có thể retry nhiều lần;
- status nội bộ được cập nhật từ provider event + reconciliation.

Invoice generation idempotent theo:

```text
UNIQUE(account_id, billing_period, invoice_sequence/type)
```

Cron retry không được tạo hai invoice cho cùng kỳ.

---

## 16. Payment và invoice là hai state machine

```text
Invoice OPEN
  ├─ PaymentAttempt PROCESSING
  │    ├─ SUCCEEDED → Invoice PAID
  │    ├─ FAILED    → dunning
  │    └─ UNKNOWN   → query/reconcile
  └─ manual payment/credit có thể đóng invoice
```

Payment attempt:

- idempotency key;
- provider reference;
- amount/currency/request hash;
- `PROCESSING | SUCCEEDED | FAILED | UNKNOWN`;
- retry schedule;
- reconciliation outcome.

Không đánh dấu paid chỉ vì API `charge` trả 200 nếu settlement/business requirement
cần trạng thái khác. Không retry mù khi timeout.

Đọc [Distributed Transactions](../advanced/distributed_transactions.md).

---

## 17. Billing provider là adapter, không phải toàn bộ domain

Giữ mapping:

```text
tenant/account ↔ provider customer
contract       ↔ provider subscription/price
invoice        ↔ provider invoice
payment        ↔ provider payment reference
meter/version  ↔ provider meter
```

Provider có thể ingest meter events và tạo invoice, nhưng hệ thống vẫn cần:

- raw usage/audit riêng hoặc export có thể phục hồi;
- mapping/version;
- idempotency;
- customer-visible explanation;
- reconciliation;
- exit/migration strategy;
- xử lý provider downtime/rate limit.

Không gọi provider trên mọi product request nếu có thể buffer/aggregate an toàn.

---

## 18. Gửi usage tới provider

Hai mode:

### Raw events

Gửi từng usage event. Audit chi tiết nhưng volume/cost/rate-limit cao.

### Pre-aggregated

Gửi tổng theo hour/day:

```text
tenant + meter + UTC hour → quantity + aggregate_version
```

Cần semantics rõ:

- `increment`: retry dễ double count nếu provider không idempotent;
- `set/replace`: cần version và provider hỗ trợ;
- correction/reversal;
- late window;
- checkpoint;
- compare internal vs provider summary.

Stripe hiện hỗ trợ meter event và các công thức `sum`, `count`, `last`; summary được
xử lý bất đồng bộ. Không dùng preview tức thời làm enforcement source.

---

## 19. Webhook an toàn

Handler:

```text
1. Đọc raw body
2. Verify signature + timestamp
3. Insert provider_event_id với unique constraint
4. Persist/enqueue
5. Trả 2xx nhanh
6. Worker fetch object mới nhất nếu cần
7. Apply state transition idempotent
```

Không giả định ordering. Ví dụ `invoice.paid` có thể đến trước event subscription
liên quan. Dựa vào object/version/provider API và state machine.

Webhook có thể duplicate; event ID dedup. Một business change cũng có thể sinh nhiều
event khác nhau, nên transition vẫn phải idempotent.

Không log signature secret/payload nhạy cảm; rotate secret và tách test/live.

---

## 20. Dunning và entitlement

Dunning là xử lý thanh toán thất bại:

```text
payment failed
 → notify
 → retry theo schedule/provider signal
 → grace period
 → restrict/suspend hoặc manual collection
```

Không xóa dữ liệu ngay. Tách:

- invoice/payment status;
- subscription status;
- service entitlement;
- tenant access state.

Policy theo segment/region/payment method. Một payment retry có thể tốn phí và gây
khó chịu; dùng provider decline category, không retry permanent failure vô hạn.

Entitlement degradation nên có grace, communication và đường khôi phục. Sensitive
data/export có thể vẫn cần cho customer dù write bị khóa.

---

## 21. Usage limit khác billing meter

Rate limiter cần decision nhanh; billing cần chính xác/audit:

```text
Usage ledger ──▶ billing invoice
      └────────▶ near-real-time projection ─▶ quota/rate enforcement
```

Projection có thể trễ. Với hard budget:

- reservation/credit wallet;
- atomic decrement;
- safety margin;
- reconcile actual usage;
- xử lý job dài vượt estimate.

Không dùng Redis counter TTL làm invoice truth. Không dùng invoice summary cuối tháng
để bảo vệ realtime provider cost.

Đọc [Rate Limiting](rate_limiting.md).

---

## 22. Credit và prepaid balance

Credit ledger:

```text
GRANT +1000
RESERVE -100
SETTLE actual -80 / RELEASE +20
EXPIRE remaining theo contract
ADJUST correction
```

Không chỉ một mutable `balance`:

- immutable entries;
- idempotency/reference;
- currency/unit;
- grant lot và expiry;
- reservation cho job;
- available vs pending;
- negative balance policy;
- reconciliation.

Financial credit (money) và product credit (tokens) có accounting/tax khác nhau;
đừng trộn nếu chưa có policy từ finance/legal.

---

## 23. Tax, currency và revenue recognition

Đây là domain chuyên môn và thay đổi theo jurisdiction. Kiến trúc cần cung cấp:

- legal seller/entity;
- customer location và tax evidence;
- tax ID/exemption;
- currency/FX source và timestamp;
- invoice numbering/retention;
- refund/credit note;
- contract/service period;
- immutable audit.

Billing system tính khoản thu không đồng nghĩa đã “ghi nhận doanh thu”. Revenue
recognition có thể phân bổ theo thời gian/nghĩa vụ thực hiện và nên nằm trong hệ
thống accounting/double-entry với policy được finance/auditor phê duyệt.

Tài liệu này không thay tư vấn kế toán/thuế.

---

## 24. Reconciliation

Đối chiếu ít nhất:

```text
Product source ↔ Raw usage ledger
Raw ledger     ↔ Aggregates
Aggregates     ↔ Rating lines
Invoice        ↔ Provider invoice
Payment state  ↔ Provider/settlement/bank
Refund/credit  ↔ Ledger
```

Kiểm tra:

- missing/duplicate usage;
- quantity/period/catalog mismatch;
- invoice tổng không bằng line items;
- provider có object nội bộ thiếu hoặc ngược lại;
- paid nội bộ nhưng provider open;
- payment amount/currency mismatch;
- late/correction chưa phản ánh.

Repair phải idempotent, audit và phân biệt auto-fix/manual review.

---

## 25. Customer transparency và dispute

Customer portal nên hiển thị:

- usage hiện tại và độ trễ dữ liệu;
- unit/metric definition;
- breakdown theo ngày/project nếu contract cho phép;
- included/overage;
- price version/plan;
- invoice/credit/refund;
- export raw/summary phù hợp;
- threshold alert/budget.

Một line “1.234.567 units” không giải thích được sẽ tạo support ticket. Giữ lineage
từ line item tới aggregate và mẫu raw event.

Dispute workflow không được sửa DB tay; tạo case, freeze collection nếu policy,
rerate/correction/credit có approval.

---

## 26. Security và phân quyền

- tenant context phải được derive từ identity tin cậy;
- billing admin, support, finance và engineer có quyền khác nhau;
- thay giá/credit/refund/manual mark-paid cần approval và audit;
- webhook verify signature/raw body/replay window;
- provider secret trong secret manager và rotate;
- không lưu card data nếu provider tokenization đáp ứng nhu cầu;
- invoice/download signed URL scope tenant;
- usage event không chứa PII không cần thiết;
- export/accounting retention theo policy;
- test/live account và key tách biệt.

Refund/credit là hành động tài chính, không chỉ một nút feature.

---

## 27. Vận hành pipeline

Theo dõi:

- usage ingestion rate/error/duplicate/conflict;
- event-time lag và oldest unprocessed;
- outbox backlog;
- aggregate/rating checkpoint;
- kỳ sắp finalize nhưng chưa ready;
- correction/late-event rate;
- invoice generation failure/duplicate prevention;
- payment `UNKNOWN`, failure và dunning;
- webhook lag/duplicate/signature failure;
- reconciliation mismatch và giá trị tiền bị ảnh hưởng.

Metric kỹ thuật cần kết hợp invariant:

```text
invoice_total = sum(line_items)
paid_amount + outstanding = invoice_due ± adjustments
every finalized line has rating lineage
```

Không cần đưa tenant ID vào mọi metric label; dùng logs/audit và top-K.

---

## 28. Ví dụ: tính phí AI theo token

Contract:

```text
Base: 20 USD/tháng
Included: 1M tokens
Next 4M: 2 USD / 1M
Above 5M: 1,5 USD / 1M
```

Luồng:

1. Inference request có idempotency key.
2. Model/provider trả input/output token authoritative.
3. Inference transaction ghi result + usage Outbox.
4. Metering dedup theo request/model/meter.
5. Raw ledger lưu input và output thành meter riêng.
6. Aggregate theo billing period.
7. Rating dùng catalog/contract snapshot.
8. Draft invoice chờ grace period.
9. Finalize; correction muộn thành adjustment.
10. Provider charge; webhook + reconciliation cập nhật payment.

Case cần xử lý:

- streaming bị client cancel nhưng đã sinh token;
- provider timeout/usage unknown;
- retry request cùng idempotency key;
- model khác multiplier;
- free/internal request;
- tenant đổi plan giữa kỳ;
- token correction từ provider.

---

## 29. Failure modes thường gặp

| Sự cố | Hậu quả | Phòng vệ |
|---|---|---|
| Redis counter là source invoice | Mất/expire/sai không audit | Raw immutable ledger |
| Emit trước commit | Charge operation thất bại | Outbox tại commitment point |
| Event không idempotent | Double charge | Unique business key |
| Sửa/xóa usage cũ | Mất lineage | Correction/reversal |
| Sửa price row | Hóa đơn cũ thay đổi khi rerate | Version/effective time |
| Nhầm volume/graduated | Tính sai tier | Golden boundary tests |
| Dùng `double` cho tiền | Sai rounding | Minor units/decimal |
| Finalize khi pipeline lag | Thiếu usage | Cutoff + watermark + grace |
| Webhook theo thứ tự | State rollback/sai | Fetch latest + state machine |
| Payment timeout = failed | Charge lặp | `UNKNOWN` + idempotency/reconcile |
| Dùng billing ledger để limit realtime | Vượt ngân sách do lag | Projection/reservation |
| Invoice finalized bị update ngầm | Audit/compliance sai | Credit/debit adjustment |

---

## 30. Decision checklist

- [ ] Billable metric có semantics và commitment point rõ.
- [ ] Usage event immutable, versioned, tenant-scoped và idempotent.
- [ ] Delivery at-least-once không gây double count.
- [ ] Correction dùng reversal/adjustment, không rewrite lịch sử.
- [ ] Raw ledger rebuild được aggregate.
- [ ] Event time, cutoff, late usage và grace period được định nghĩa.
- [ ] Catalog/contract/price có version và effective time.
- [ ] Tier, proration, included unit và rounding có golden tests.
- [ ] Tiền dùng minor unit/decimal và currency rõ.
- [ ] Invoice/payment/subscription/entitlement là state machine tách biệt.
- [ ] Provider adapter có webhook dedup, signature và reconciliation.
- [ ] Hard quota không phụ thuộc projection trễ.
- [ ] Customer xem được usage breakdown và độ trễ.
- [ ] Tax/revenue policy do finance/legal phê duyệt.
- [ ] Manual correction/refund có approval và audit.

---

## 31. Câu hỏi phỏng vấn thường gặp

1. Metering, rating, invoicing và payment khác nhau thế nào?
2. Ghi usage ở gateway hay business service?
3. Làm sao tránh double count với at-least-once delivery?
4. Vì sao không update usage event sai?
5. Volume và graduated pricing khác nhau thế nào?
6. Vì sao price catalog phải versioned?
7. Late usage sau invoice finalize được xử lý ra sao?
8. Redis counter có thể dùng làm billing source of truth không?
9. Webhook duplicate/out-of-order được xử lý thế nào?
10. Payment timeout thì invoice chuyển state gì?
11. Hard usage budget khác monthly invoice counter ở đâu?
12. Bạn reconcile product usage tới tiền đã settle thế nào?

---

## 32. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [Stripe – How usage-based billing works](https://docs.stripe.com/billing/subscriptions/usage-based/how-it-works)
- [Stripe – Configure meters](https://docs.stripe.com/billing/subscriptions/usage-based/meters/configure)
- [Stripe – Record usage](https://docs.stripe.com/billing/subscriptions/usage-based/recording-usage)
- [Stripe – Invoice lifecycle](https://docs.stripe.com/invoicing/overview)
- [Stripe – Webhook best practices](https://docs.stripe.com/webhooks)
- [AWS SaaS Lens – Tenant activity and consumption](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-activity-and-consumption.html)

Đọc tiếp:

- [Multi-tenancy](multi_tenancy.md) – tenant/account và lifecycle.
- [Rate Limiting](rate_limiting.md) – quota realtime và cost control.
- [Feature Flags](feature_flags.md) – entitlement/rollout nhưng không thay billing.
- [Event-Driven Architecture](../advanced/event_driven_architecture.md) – Outbox,
  idempotency và event-time.
- [Payment/Ledger case study](../case_studies/platform_designs.md) – double-entry,
  payment và reconciliation.

---

*Cập nhật lần cuối: 2026-07-31*
