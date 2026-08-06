# Cloud Cost & Sustainability Observability – Từ Usage đến Unit Cost và Carbon Intensity

> Mục tiêu của bài này là biến usage, billing, allocation, energy và carbon data thành quyết
> định kỹ thuật có thể kiểm chứng: workload nào tạo chi phí, phần nào idle, mỗi outcome tốn
> bao nhiêu, tối ưu nào thật sự giảm tài nguyên mà không làm xấu reliability.
>
> Baseline tham chiếu: FinOps Framework hiện hành, FOCUS 1.4, OpenCost Specification, FinOps
> Sustainability, Software Carbon Intensity 1.1/ISO/IEC 21031:2024 và GHG Protocol Scope 2
> Guidance hiện hành. Provider billing/carbon data luôn phải được kiểm tra theo tài khoản thực tế.
>
> Đây là hướng dẫn engineering observability, không phải báo cáo kế toán hoặc kiểm kê phát thải
> chính thức. Finance, procurement và sustainability team phải xác nhận boundary, allocation,
> currency, emission factor, Scope 1/2/3, contractual instrument và public claim.
>
> Nên đọc trước:
> [Telemetry Governance & FinOps](telemetry_governance_finops.md),
> [Business & Product Observability](business_product_observability.md),
> [Multi-Tenant & SaaS Observability](multi_tenant_saas_observability.md) và
> [Kubernetes Observability](kubernetes_observability.md).

---

## 1. Vì sao cost observability khác xem hóa đơn?

Hóa đơn trả lời đã bị tính bao nhiêu theo kỳ. Cost observability còn hỏi:

- workload/change nào tạo chi phí;
- cost tăng do usage, price hay allocation;
- resource nào idle hoặc bị over-request;
- mỗi successful outcome tốn bao nhiêu;
- tối ưu có làm tăng error, latency hoặc carbon không;
- dữ liệu đủ mới và đủ đầy để ra quyết định không.

## 2. Cost, price, usage và quantity

Phân biệt:

```text
usage quantity × price/rate ± discount/credit/adjustment = cost
```

`list cost`, `effective cost`, `billed cost` và `amortized cost` có thể khác nhau. Dashboard
phải ghi rõ đang dùng khái niệm nào; không trộn chúng trong cùng trend.

## 3. Boundary

Chọn phạm vi:

- account/sub-account;
- provider và on-prem;
- product/service/environment;
- direct/shared platform;
- support/license/labor nếu “fully loaded”;
- billing period;
- currency;
- carbon boundary.

Không so hai unit cost nếu boundary khác mà không disclosure.

## 4. Nguồn dữ liệu

| Nguồn | Vai trò |
|---|---|
| Billing export/invoice | amount tài chính |
| Price catalog/contract | rate, discount, commitment |
| Resource inventory | owner, placement, lifecycle |
| Metrics/traces/events | usage, demand, outcome |
| CMDB/catalog/tags | allocation |
| Energy/carbon source | kWh, intensity, factor |

Ghi lineage, freshness và quality cho từng nguồn.

## 5. Billing data có độ trễ và correction

Chi phí hiện tại thường là estimate; provider có thể cập nhật late charge, credit hoặc refund.
Mỗi dataset cần:

- generated/updated time;
- completeness/finality;
- billing/charge period;
- correction version;
- source;
- ingestion watermark.

Không page on-call từ một dòng charge chưa final nếu không có guard phù hợp.

## 6. FOCUS 1.4

FOCUS chuẩn hóa schema và thuật ngữ billing data đa nhà cung cấp. Bản 1.4 được ratify ngày
04/06/2026, bổ sung dataset phục vụ invoice/billing-period reconciliation và mở rộng contract
commitment.

Pin version theo dataset thực nhận: provider adoption có thể chậm hơn latest specification.
Validate schema và lưu custom-column semantics.

## 7. Allocation contract

Mỗi resource/cost line cần ánh xạ tới dimension có trách nhiệm:

- business unit;
- product/service;
- team/cost center;
- environment;
- region;
- tenant/cohort nếu hợp lệ;
- shared/idle/unallocated.

Contract có owner, source precedence, effective date và fallback.

## 8. Tag và label governance

Tag cloud/Kubernetes hữu ích nhưng mutable, thiếu hoặc bị giới hạn bởi provider. Quy định:

- key chuẩn;
- allowed value;
- ai được sửa;
- inheritance;
- effective-dated mapping;
- validation;
- exception expiry.

Không dùng customer name/PII. Backfill allocation sau kỳ phải có audit.

## 9. Direct, shared, overhead và idle

- **Direct:** truy rõ workload.
- **Shared:** phục vụ nhiều workload.
- **Overhead:** quản lý/platform chung.
- **Idle:** resource đã provision nhưng chưa phân cho workload/useful work.
- **Unallocated:** thiếu mapping, không đồng nghĩa idle.

Hiển thị riêng trước khi phân bổ để không che lãng phí.

## 10. OpenCost

OpenCost định nghĩa cách đo và phân bổ chi phí Kubernetes vendor-neutral. Mô hình tổng quát:

```text
cluster cost = workload cost + idle cost + overhead cost
```

Nó dùng allocation/usage như CPU, RAM, GPU, storage, network và load balancer. Kết quả cần
reconcile với billing export vì list/on-demand price có thể khác effective invoice.

## 11. List, net, effective và billed cost

| Khái niệm | Dùng khi |
|---|---|
| List cost | so giá công khai |
| Net/effective cost | tối ưu thực tế sau discount |
| Billed cost | đối soát invoice |
| Amortized cost | phân bổ commitment/upfront theo thời gian |

Tên panel và metric phải chứa semantic, không chỉ `cost_total`.

## 12. Amortization

Upfront commitment hoặc annual fee cần trải theo thời gian/use policy. Ghi:

- contract ID/version;
- start/end;
- amortization method;
- covered usage;
- unused commitment;
- allocation driver.

Đổi phương pháp tạo break trong trend; version hóa thay vì sửa lịch sử âm thầm.

## 13. Commitment và discount

Theo dõi coverage, utilization, expiry, break-even và stranded commitment. Discount cao không
có nghĩa tiết kiệm nếu mua quá nhiều.

```text
commitment utilization =
  eligible usage consumed / committed capacity
```

Forecast phải xét growth, architecture change và lock-in risk.

## 14. Currency và timezone

Không cộng currency trước conversion. Lưu original currency/cost, reporting currency, FX rate,
rate date/source và conversion policy.

Billing period theo provider timezone có thể không khớp UTC telemetry. Chuẩn hóa interval
`[start, end)` và ghi timezone rõ.

## 15. Allocation completeness

```text
allocation_coverage =
  allocated eligible cost / total eligible cost
```

Tách unallocated, unknown owner và mapping conflict. 100% coverage bằng cách đẩy mọi thứ vào
“platform” không phải allocation chất lượng.

## 16. Reconciliation

Đối soát:

```text
allocated + idle + shared + overhead + adjustment
≈ invoice/billed total
```

Sai số cần threshold, reason và owner. Kiểm tra duplicate line, late correction, tax/credit,
currency rounding và resource đã xóa.

## 17. Unit economics

Nối cost với functional/business unit:

```text
cost_per_outcome =
  effective allocated cost / successful outcomes
```

Chọn unit như order hoàn tất, GB xử lý hoặc model inference hữu ích. Request count chỉ tốt khi
phản ánh giá trị tương đương.

## 18. Cost-to-value

Outcome tree nối:

```text
resource → workload → service → journey → outcome → value
```

Cost giảm nhưng successful outcome giảm mạnh là tối ưu giả. Kèm correctness, latency,
availability, retention hoặc margin guardrail.

## 19. Budget và cost objective

Budget là ngưỡng kế hoạch tài chính; cost objective kỹ thuật có thể là:

- cost per successful transaction;
- max marginal cost;
- allocation coverage;
- idle ratio;
- forecast error;
- anomaly detection time.

Budget burn không nên được gọi là error budget reliability.

## 20. Forecast

Forecast dựa trên demand driver, seasonality, growth, release, contract và price change:

```text
forecast cost =
  forecast usage × effective rate + shared/overhead
```

Hiển thị prediction interval và scenario base/high/low, không chỉ một đường chắc chắn giả.

## 21. Cost anomaly

Anomaly có thể do:

- usage spike;
- unit price/discount đổi;
- tag/allocation sai;
- duplicate/late charge;
- region/architecture shift;
- attack/abuse;
- data pipeline lỗi.

Detector cần seasonality, minimum materiality và billing-data quality guard.

## 22. Change correlation

Đặt marker cho deployment, autoscaling policy, instance family, retention, data backfill,
campaign và price/contract change.

So `usage`, `rate`, `cost`, `unit cost` và SLO trước/sau. Tương quan chưa chứng minh nguyên
nhân; workload mix có thể đổi cùng lúc.

## 23. Showback và chargeback

- **Showback:** minh bạch chi phí để học/hành động.
- **Chargeback:** chuyển chi phí vào đơn vị chịu trách nhiệm.

Chargeback cần audit, dispute, correction và finance approval cao hơn dashboard vận hành.
Không charge từ estimate chưa reconcile.

## 24. Kubernetes request, allocation và usage

CPU/RAM cost thường gắn với capacity provisioned/requested chứ không chỉ instantaneous usage.
Quan sát:

- node allocatable;
- pod request/limit;
- actual usage;
- scheduling waste;
- throttling/OOM;
- idle;
- unallocated capacity.

Right-sizing theo distribution và headroom, không theo average.

## 25. CPU cost

Đo core-hours requested/used, throttling, runnable/queue pressure và cost rate. CPU thấp có thể
do I/O wait hoặc workload bị throttled, không tự là waste.

Giảm request phải kiểm tra scheduling, HPA target, p99 latency và failover.

## 26. Memory cost

Memory không co giãn như CPU và OOM có hậu quả lớn. Phân biệt working set, cache có thể reclaim,
heap/native, request/limit và peak.

Right-size theo peak distribution, leak trend, rollout/failover headroom và restart cost.

## 27. GPU/accelerator

Theo dõi allocation, active compute, memory, batching, queue, fragmentation, power/energy
nếu có và successful output.

GPU utilization đơn lẻ không đủ: memory-bound, data loading hoặc serving latency có thể là
bottleneck. Cost per useful training/inference outcome tốt hơn cost per GPU-hour.

## 28. Storage

Phân rã capacity, IOPS/throughput provisioned, requests, snapshots, backup, replication,
retention và retrieval/operation fee.

Phát hiện orphan volume/snapshot, wrong class, stale replica và data lifecycle. Xóa cần owner,
retention/legal check và recoverability.

## 29. Network và egress

Egress cost phụ thuộc source/destination, zone/region/Internet, path và rate tier. Theo dõi
bytes, request, compression/cache, retry và topology.

Đừng tối ưu bằng cách bỏ redundancy hoặc dồn mọi thứ một region nếu làm xấu resilience,
residency hoặc latency.

## 30. Managed service

Database, queue, search, CDN và API có allocation + usage + tier/operation charge khác nhau.
Lưu pricing dimension và service-specific driver.

Một managed service đắt hơn VM có thể giảm labor, risk và time-to-market; so fully loaded value,
không chỉ invoice line.

## 31. Serverless

Phân rã invocation, duration, memory/CPU tier, provisioned concurrency, request/egress và retry.
Cold start, over-allocation và duplicate invocation ảnh hưởng cả cost lẫn reliability.

Theo dõi cost per successful logical event, không per attempt.

## 32. Data và AI workload

Cost driver:

- scan/compute time;
- shuffle/egress;
- storage/retention;
- GPU/accelerator;
- token/model call;
- experiment/retry;
- idle notebook/endpoint.

Nối với dataset/model/query version và quality outcome; cheaper run sai không có giá trị.

## 33. Observability cost

Metrics/logs/traces/profiles cũng là workload. Theo dõi cost theo signal, producer, tenant,
retention, query và egress.

Tối ưu sampling/cardinality/retention kèm detection/SLO coverage. Xem chi tiết ở
[Telemetry Governance & FinOps](telemetry_governance_finops.md).

## 34. Idle và waste

Idle có thể là:

- intentional headroom;
- resilience reserve;
- warm capacity;
- unused commitment;
- orphan;
- over-request;
- off-hours waste.

Không gọi mọi utilization thấp là waste. Phân loại reason và owner trước hành động.

## 35. Orphan resource

Resource không owner/workload liên kết: unattached disk/IP, snapshot cũ, load balancer không
traffic, zombie cluster, stale environment.

Detection cần grace period, dependency evidence và deletion workflow recoverable. Tag thiếu
không đủ chứng minh orphan.

## 36. Right-sizing

Quy trình:

1. chọn window đại diện;
2. xem percentile/peak/seasonality;
3. xác định bottleneck;
4. giữ burst, rollout, failover headroom;
5. mô phỏng thay đổi;
6. canary;
7. đo SLO/cost;
8. rollback nếu guardrail xấu.

Không tự động giảm theo average tuần trước.

## 37. Scheduling

Di chuyển batch/offline workload sang giờ rẻ hoặc carbon intensity thấp khi deadline cho phép.
Theo dõi queue age, completion deadline, data freshness và dependency.

Tối ưu lịch không được tạo recovery storm hoặc tranh capacity với traffic online.

## 38. Architecture economics

So total cost/value của cache, compression, batching, data locality, serverless, managed
service, multi-region và buy-vs-build.

Gồm migration cost, operational labor, risk, lock-in, reliability và exit cost. Benchmark trên
workload thật, không chỉ calculator.

## 39. Reliability guardrail

Mỗi optimization phải theo dõi:

- availability/error;
- p95/p99 latency;
- correctness/durability;
- queue/freshness;
- recovery/failover;
- customer outcome;
- security/compliance.

Rollback criterion được định nghĩa trước khi tiết kiệm được tính là realized.

## 40. Sustainability khác cost thế nào?

Cost là giá tiền; sustainability xét environmental impact. Chúng thường cùng giảm khi bỏ waste
nhưng không luôn đồng hướng:

- region rẻ chưa chắc carbon intensity thấp;
- hardware mới hiệu quả nhưng có embodied emissions;
- redundancy tăng resource nhưng bảo vệ reliability;
- mua credit không làm software dùng ít năng lượng.

## 41. Scope phát thải

Scope 1/2/3 phụ thuộc reporting boundary và quan hệ sở hữu/mua dịch vụ. Cloud usage thường cần
mapping với provider data và corporate accounting policy; không tự gán mọi cloud emission vào
một scope trong dashboard kỹ thuật.

Ghi organizational/software boundary và nhờ sustainability/accounting xác nhận.

## 42. Energy

Energy đo kWh/Joule; CPU utilization không trực tiếp là energy. Nguồn:

- hardware/power meter;
- provider facility/workload data;
- telemetry estimator;
- lab benchmark/model.

Ghi measured/estimated, sampling, hardware, utilization range và uncertainty.

## 43. Carbon intensity

Carbon intensity điện thay đổi theo region và thời gian:

```text
gCO2e/kWh
```

Nguồn có resolution, publication delay, forecast/actual và coverage khác nhau. Không trộn factor
khác methodology trong một trend.

## 44. Operational emissions

SCI biểu diễn phần operational emissions:

```text
O = E × I
```

Trong đó `E` là energy và `I` là carbon intensity. Boundary/time alignment phải khớp; dùng
average tháng cho workload theo giờ làm mất tín hiệu carbon-aware scheduling.

## 45. Embodied emissions

Embodied emissions đến từ sản xuất, vận chuyển và vòng đời hardware. Phân bổ thường cần:

- total embodied estimate;
- expected lifetime;
- reserved/used capacity share;
- time;
- hardware boundary.

Model có uncertainty lớn; disclosure quan trọng hơn độ chính xác giả.

## 46. Software Carbon Intensity

SCI:

```text
SCI = ((E × I) + M) per R
```

`M` là embodied emissions được phân bổ; `R` là functional unit. SCI là rate nhằm hỗ trợ giảm
phát thải thực qua energy efficiency, hardware efficiency và carbon awareness.

## 47. Functional unit

Chọn `R` phản ánh cách software tạo giá trị: transaction hoàn tất, user-hour, GB xử lý hoặc
inference hữu ích.

Đơn vị phải ổn định, đo được và không khuyến khích hành vi xấu. Công bố cả total và intensity:
intensity giảm nhưng traffic tăng có thể làm total tăng.

## 48. Software boundary và allocation

Boundary SCI liệt kê component gồm compute, storage, network, dependency và environment nào.
Shared platform cần driver allocation.

Không so SCI của hai hệ nếu một bên bỏ database/egress hoặc embodied emissions mà không nêu
khác biệt.

## 49. Measurement và uncertainty

Mỗi giá trị cần provenance:

- measured hay modeled;
- source/version;
- spatial/temporal resolution;
- coverage;
- allocation;
- uncertainty range;
- missing-data rule.

Dashboard nên hiển thị confidence/coverage; estimate vẫn hữu ích nếu directionally correct và
minh bạch.

## 50. Location-based và market-based Scope 2

GHG Protocol phân biệt:

- location-based: average emissions intensity của grid nơi dùng điện;
- market-based: phản ánh lựa chọn/contractual instrument đủ tiêu chí.

Khi áp dụng dual reporting, hiển thị hai kết quả riêng; không chọn số thấp hơn tùy ý. Guidance
đang được cập nhật nên pin policy/version.

## 51. Carbon-aware computing

Điều chỉnh thời gian hoặc địa điểm workload theo carbon intensity, nhưng phải giữ:

- deadline/freshness;
- residency;
- latency;
- reliability;
- capacity;
- cost;
- data movement emissions.

Carbon signal là input policy, không phải quyền override mọi constraint.

## 52. Time shifting

Phù hợp với batch, build, training, backup hoặc compaction có slack. Scheduler cần intensity
forecast, deadline, required capacity và recovery plan.

Đo emissions estimate baseline so actual, completion SLO và rebound. Trì hoãn rồi chạy dồn có
thể tạo peak kém hiệu quả.

## 53. Region shifting

Region khác nhau về carbon, price, latency, grid, capacity và regulation. Tính cả data transfer,
replication và warm capacity.

Không chuyển user data qua boundary không cho phép. Canary và kiểm tra failover trước khi
policy tự động.

## 54. Energy efficiency

Giảm năng lượng cho cùng outcome bằng algorithm tốt hơn, batching, cache, compression hợp lý,
giảm retry hoặc data scan.

Benchmark ở cùng workload/quality. Tăng CPU utilization đôi khi giảm total energy vì hoàn tất
nhanh; nhìn utilization đơn lẻ dễ kết luận sai.

## 55. Hardware efficiency

Tăng useful work trên resource/hardware đã provision:

- right-size;
- bin packing;
- accelerator phù hợp;
- autoscaling;
- hardware lifecycle;
- shared capacity an toàn.

Không chạy hardware tới saturation làm tail latency và failure tăng.

## 56. Rebound effect

Efficiency làm mỗi unit rẻ hơn có thể khuyến khích dùng nhiều hơn, khiến total cost/emissions
tăng. Theo dõi cả:

```text
total, per-unit intensity, demand volume, outcome
```

Đặt policy usage và product guardrail khi cần.

## 57. Dashboard

Các tầng:

1. total/effective cost và emissions;
2. allocation/coverage/data quality;
3. product/team/environment;
4. resource/usage/idle;
5. unit economics/SCI;
6. optimization action và realized saving.

Hiển thị currency, boundary, method và freshness ngay trên dashboard.

## 58. Alerting

Alert khi:

- material cost anomaly;
- allocation coverage giảm;
- billing ingestion stale/incomplete;
- commitment expiry/underuse;
- runaway egress/GPU;
- carbon-aware job có nguy cơ trễ;
- measurement coverage mất;
- optimization làm xấu SLO.

Alert gồm estimated impact, confidence, owner và safe action.

## 59. Optimization workflow

```text
detect → attribute → explain → propose → simulate
       → approve → canary → verify → realize → record
```

Ghi baseline, action, forecast saving, actual saving, SLO/carbon outcome và rollback. Recommendation
không thực hiện không phải saving.

## 60. Experiment

A/B hoặc canary architecture/resource setting trên workload đại diện. Đo cost/outcome,
energy/carbon estimate, performance và correctness cùng window.

Tránh simultaneous changes và kiểm tra warm-up/cache. Kết quả lab không tự áp dụng production
nếu workload/hardware khác.

## 61. Governance và public claim

Policy cần:

- owner và approval;
- cost/carbon definition catalog;
- factor/source version;
- claim boundary;
- evidence retention;
- conflict/dispute;
- correction;
- anti-greenwashing review.

Không gọi estimate engineering là audited carbon inventory hoặc “carbon neutral”.

## 62. Security, privacy và retention

Billing/tag data có thể lộ account, tenant, contract, architecture và margin. Áp dụng least
privilege, encryption, export audit và separation of duties.

Cost detail thường cần retention khác high-frequency resource metric; aggregate dài hạn và
xóa raw data khi không còn mục đích.

## 63. Triển khai theo giai đoạn

1. reconcile total bill;
2. allocation coverage;
3. top services/resources;
4. idle/right-sizing;
5. unit economics;
6. energy/carbon estimate có coverage;
7. optimization automation có guardrail;
8. formal reporting integration.

Không bắt đầu bằng dashboard carbon chính xác giả khi cost inventory còn sai.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: chọn một service Kubernetes, reconcile chi phí tháng, phân bổ direct/shared/idle,
tính cost và SCI estimate trên một successful outcome, rồi canary một right-sizing action.

- [ ] Cost semantic và currency rõ?
- [ ] FOCUS/provider dataset version được pin?
- [ ] Allocation + idle + overhead reconcile?
- [ ] Unit gắn với useful outcome?
- [ ] Billing/carbon freshness và uncertainty hiển thị?
- [ ] SCI boundary và functional unit rõ?
- [ ] Location/market-based không bị trộn?
- [ ] Reliability guardrail có rollback?
- [ ] Realized saving khác recommendation?

Câu hỏi:

1. List, effective, billed và amortized cost khác nhau thế nào?
2. Unallocated khác idle ra sao?
3. Vì sao utilization thấp chưa chắc waste?
4. SCI gồm những thành phần nào?
5. Khi nào time/region shifting không phù hợp?
6. Intensity giảm nhưng total tăng do đâu?
7. Vì sao public carbon claim cần review ngoài engineering?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Cost và FinOps

- [FOCUS Specification 1.4](https://focus.finops.org/focus-specification/)
- [FinOps Allocation](https://www.finops.org/framework/capabilities/allocation/)
- [FinOps Unit Economics](https://www.finops.org/framework/capabilities/unit-economics/)
- [OpenCost Specification](https://opencost.io/docs/specification/)
- [OpenCost API](https://opencost.io/docs/integrations/api/)

### Sustainability

- [FinOps Sustainability](https://www.finops.org/framework/capabilities/sustainability/)
- [Software Carbon Intensity](https://sci.greensoftware.foundation/)
- [Green Software Foundation SCI](https://greensoftware.foundation/standards/sci/)
- [GHG Protocol Scope 2 Guidance](https://ghgprotocol.org/scope-2-guidance)

Chủ đề tiếp theo:
[Capacity Planning & Performance Efficiency Observability](capacity_planning_performance_efficiency.md)
– demand, saturation, queueing, headroom, forecasting, load test, autoscaling và overload.

---

*Cập nhật lần cuối: 2026-07-30*
