---
title: "Security Metrics, Measurement & Executive Reporting – Đo để ra quyết định"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 8
---
# Security Metrics, Measurement & Executive Reporting – Đo để ra quyết định

> Thuật ngữ: [Glossary](../glossary.md).

Security metric có giá trị khi làm thay đổi một quyết định: ưu tiên exposure, điều chỉnh control, phân bổ nguồn lực, chấp nhận risk
hoặc dừng một xu hướng xấu. Dashboard nhiều màu nhưng không có definition, denominator, uncertainty và action chỉ tạo ra cảm giác kiểm soát.

```text
business / risk decision
    → question + measurable concept
        → measure specification + trustworthy data
            → analysis + uncertainty + context
                → threshold / decision / action
                    → outcome feedback + metric retirement
```

Chương này mở rộng [Security Governance & Risk Engineering](../governance/security_governance_risk_engineering.md),
[Security Architecture Review](../architecture/security_architecture_review_design_governance.md),
[Vulnerability Management](../vulnerability/vulnerability_management_exposure_prioritization.md) và
[Security Testing & Validation](../validation/security_testing_validation_engineering.md).

---

## 1. Vì sao đo security khó?

Security quan sát một hệ thống đối kháng, thay đổi và có nhiều sự kiện hiếm. “Không có incident” có thể do control tốt, threat thấp,
visibility kém hoặc may mắn. Một số outcome chỉ xuất hiện sau thời gian dài; proxy dễ đo lại bị tối ưu thay cho mục tiêu thật.

Vì vậy measurement cần:

- liên kết rõ với objective/decision;
- định nghĩa population và unknown;
- kiểm data quality/provenance;
- diễn đạt uncertainty/assumption;
- kết hợp nhiều loại evidence;
- tránh suy luận causal quá mức;
- có vòng đời review/retire.

## 2. Measure, metric, indicator và assessment

Trong thực tế thuật ngữ có thể khác, nhưng nên thống nhất nội bộ:

- **base measure:** quan sát trực tiếp, ví dụ thời gian revoke từng grant;
- **derived measure/metric:** tính từ nhiều giá trị, ví dụ p95 revoke-to-deny;
- **indicator:** measure được diễn giải theo threshold/decision context;
- **assessment:** đánh giá đối tượng theo criteria/evidence, có thể qualitative;
- **target:** mức mong muốn;
- **threshold/tolerance:** ranh giới kích hoạt hành động/escalation.

Đừng tranh nhãn; cần làm rõ công thức, ý nghĩa, giới hạn và decision owner.

## 3. Bắt đầu từ quyết định, không từ dữ liệu có sẵn

Câu hỏi đúng:

- Ta có đang vượt risk tolerance nào?
- Control nào không đủ hiệu lực và cần đầu tư?
- Critical exposure đang giảm hay chỉ ticket giảm?
- Capability nào là bottleneck của recovery?
- Supplier nào tạo concentration vượt appetite?

Câu hỏi yếu: “Có thể vẽ dashboard từ log này không?”. Dữ liệu dễ lấy thường đo activity của tool, không đo outcome business/security.

## 4. Goal–Question–Measure

Một cấu trúc đơn giản:

```text
Goal: giảm cửa sổ exposed privileged access
Question: grant nguy hiểm tồn tại bao lâu sau khi nhu cầu kết thúc?
Measures:
  - p50 / p95 revoke-to-deny theo access tier
  - % grant không có expiry hoặc owner
  - % revoke test thất bại
Decision: sửa provisioning, session revoke hay policy enforcement?
```

Một goal cần nhiều measure bổ trợ để tránh proxy đơn lẻ bị game hoặc che failure mode.

## 5. Audience và decision horizon

| Audience | Horizon | Cần gì |
|---|---|---|
| Operator | phút/ngày | signal chẩn đoán và action cụ thể |
| Engineering owner | sprint/quý | bottleneck, coverage, durability, investment |
| Risk/business owner | tháng/quý | scenario, tolerance, treatment và residual risk |
| Executive | quý/năm | objective, trend, concentration, trade-off, ask |
| Board | chiến lược | exposure vượt appetite, resilience và governance oversight |

Không dùng một dashboard cho mọi audience. Aggregate càng cao càng phải giữ khả năng drill-down và uncertainty.

## 6. Governance của measurement program

Chương trình cần:

- executive/risk sponsor xác định information needs;
- metric owner chịu definition và interpretation;
- data owner chịu source/quality/access;
- domain owner chịu action/outcome;
- analyst kiểm phương pháp/uncertainty;
- privacy/legal review cho telemetry nhạy cảm;
- independent assurance kiểm metric trọng yếu;
- catalog, change control và retirement process.

Metric không có owner/action khi threshold breach sẽ thành reporting debt.

## 7. Measure specification như một data contract

Mỗi metric nên có:

```yaml
id: IAM-REV-01
name: privileged revoke-to-deny p95
purpose: monitor privileged-access tolerance
population: production privileged grants ended in period
formula: percentile(enforcement_deny_time - revoke_request_time, 95)
unit: minutes
dimensions: [business_service, access_tier, environment]
source: [grant_events, enforcement_tests]
freshness: daily
target: "<= 5m"
owner: iam-control-owner
action: "breach 2 periods -> corrective plan"
limitations: "systems without enforcement probe reported as unknown"
```

Version specification; thay definition không được nối trend như thể cùng metric.

## 8. Operational definition

Các từ “critical”, “patched”, “contained”, “MFA enabled”, “covered”, “incident resolved” phải có điều kiện quan sát được. Ví dụ
“vulnerability remediated” có thể yêu cầu source fixed, artifact rebuilt, production fleet replaced và verification pass—not ticket Closed.

Operational definition gồm event bắt đầu/kết thúc, state transition, scope, exclusions và evidence. Nếu hai analyst tính ra kết quả khác nhau từ cùng dữ liệu,
definition chưa đủ rõ hoặc pipeline không reproducible.

## 9. Numerator và denominator

Tỷ lệ chỉ có nghĩa khi cả hai cùng scope/time:

```text
effective coverage = verified protected critical paths
                     ---------------------------------
                     known critical paths in scope
```

Không dùng “agent installed / assets scanned” nếu câu hỏi là control có bảo vệ path không. Báo denominator size, unknown population và thay đổi inventory;
tỷ lệ tăng do denominator giảm không tự là cải thiện.

## 10. Population, scope và unit of analysis

Xác định đo trên user, identity, asset, deployment, artifact, finding, incident, service, data flow hay business transaction. Một CVE trên 10.000 Pod có thể là
một root cause nhưng 10.000 exposure instances; chọn unit theo decision.

Ghi environment, business unit, region, tenant, criticality và inclusion/exclusion. Không so sánh team có population/threat/technology khác mà chưa normalize hoặc contextualize.

## 11. Time window, event time và freshness

Phân biệt:

- event time khi điều thật xảy ra;
- observation/ingestion time;
- processing/report time;
- rolling/fixed/cohort window;
- snapshot so với flow measure;
- data freshness/late arrival.

“MTTR tháng 7” phải nói incident bắt đầu/kết thúc/cohort theo cách nào. Rolling window mượt nhưng che spike; fixed month dễ bị boundary effect. Hiển thị last complete period và data lag.

## 12. Provenance và reproducibility

Giữ:

- source system/query/schema/version;
- extraction/transform code và parameters;
- timestamp/timezone;
- raw-to-derived lineage;
- correction/backfill history;
- identity/access của pipeline;
- result snapshot/hash khi cần;
- metric definition version.

Executive number cũng phải drill được tới canonical records mà không lộ dữ liệu không cần thiết. Spreadsheet copy-paste không có lineage làm assurance yếu.

## 13. Data quality dimensions

| Dimension | Câu hỏi |
|---|---|
| Completeness | Population nào không được quan sát? |
| Accuracy | Value có phản ánh state thật? |
| Timeliness | Đủ mới cho decision không? |
| Consistency | Source/team/time có cùng semantics? |
| Uniqueness | Duplicate có làm inflate count? |
| Validity | Value/schema/range có hợp lệ? |
| Lineage | Có truy được source/transform? |

Đặt quality threshold và hiển thị quality cùng metric; metric chất lượng thấp không nên tự động điều khiển action lớn.

## 14. Missing, unknown và not applicable

Không gộp:

- **zero:** đã quan sát và không có event/state;
- **unknown:** thiếu inventory/evidence/telemetry;
- **not applicable:** requirement không áp dụng với rationale;
- **not assessed:** chưa kiểm trong window;
- **failed collection:** pipeline/source lỗi;
- **suppressed/excluded:** có decision riêng.

“Không có finding” khi 30% fleet chưa scan là unknown exposure, không phải clean. Báo coverage/unknown rate như metric cấp một.

## 15. Validity và reliability

- **Validity:** measure có thật sự phản ánh concept/decision cần đo?
- **Reliability:** đo lại cùng điều kiện có cho kết quả ổn định?

Tool count rất reliable nhưng validity thấp cho security outcome. Manual architecture assessment có thể valid nhưng reviewer consistency thấp. Cải thiện bằng definition, calibration,
sampling, inter-rater agreement, test fixture và triangulation với evidence khác.

## 16. Uncertainty và confidence

Nguồn uncertainty:

- incomplete/biased population;
- sensor false positive/negative;
- model/assumption;
- threat/likelihood thay đổi;
- sample size nhỏ;
- delayed/duplicate event;
- attribution/correlation;
- human classification.

Báo range, confidence band/category, sample size, data-quality note và sensitivity khi phù hợp. “12,37% risk reduction” không chính xác chỉ vì có hai chữ số thập phân.

## 17. Quantitative và qualitative measure

Quantitative hữu ích khi unit/data/model đủ tốt: time, rate, count, loss distribution. Qualitative hữu ích cho novelty, control design, stakeholder judgment hoặc dữ liệu hiếm.

Qualitative vẫn cần anchored criteria và evidence:

| Mức | Anchor ví dụ |
|---|---|
| High confidence | inventory >95%, independent test gần đây, source nhất quán |
| Medium | coverage 70–95%, một số assumption chưa test |
| Low | self-attestation, unknown population lớn, evidence cũ |

Không biến label thành số rồi thực hiện toán không có ý nghĩa.

## 18. Ordinal scale và phép toán hợp lệ

Low/Medium/High hoặc maturity 1–5 thường chỉ có thứ tự; khoảng cách giữa 1 và 2 không chắc bằng 4 và 5. Vì vậy:

- không lấy average maturity tùy ý;
- không trừ control score khỏi inherent risk;
- không nhân likelihood label với impact label rồi gọi quantitative;
- không coi chênh 0,2 là cải thiện thực.

Dùng distribution theo level, transition count, anchored criteria và narrative; nếu cần định lượng, xây model/unit/assumption riêng.

## 19. Mean, median và percentile

- mean nhạy với tail/outlier;
- median mô tả phần giữa nhưng che case chậm nhất;
- percentile mô tả distribution tail nếu sample đủ;
- max dễ bị anomaly nhưng quan trọng với safety/critical case.

Ví dụ MTTR median 4 giờ, p95 21 ngày cho thấy “trung bình nhanh” không bảo vệ tail. Báo count/sample, severity/tier cohort và censoring; đừng percentile hóa dataset quá nhỏ.

## 20. Distribution, cohort và age bucket

Thay một số tổng hợp bằng:

- age buckets 0–7, 8–30, 31–90, >90 ngày;
- severity/exposure/business tier cohort;
- open vs closed cohort;
- first-observed và recurring;
- region/team/product distribution;
- tail ownership/root cause.

Snapshot backlog có survivorship bias; closure metric loại item chưa kết thúc. Dùng cohort/survival-like view khi đo time-to-event và ghi item censored.

## 21. Count, rate và exposure time

Count chịu ảnh hưởng population và detection. Rate cần denominator ổn định. Exposure time thường gần risk hơn:

```text
exposure-hours = Σ (affected critical instances × hours exposed)
```

Nhưng trọng số “critical instance” vẫn cần semantics. Một critical path exposure không tương đương 100 dev sandbox findings. Báo cả volume, rate và duration theo decision.

## 22. Normalization và so sánh công bằng

Normalize theo relevant denominator: deploy, endpoint, identity, transaction, service-hour hoặc data volume. Trước khi benchmark team, xét:

- application age/architecture;
- criticality/exposure/threat;
- deployment frequency/population;
- control inheritance/platform adoption;
- assessment depth/coverage;
- data quality;
- organizational boundary.

Không tạo league table thúc đẩy under-report. So sánh cùng team theo trend và target thường hữu ích hơn ranking thiếu context.

## 23. Leading và lagging indicator

- **Lagging:** incident loss, confirmed breach, outage, fraud—outcome đã xảy ra.
- **Leading:** exposure window, control coverage, revoke latency, restore test, privileged standing access—tín hiệu gần rủi ro.

Leading indicator không tự dự báo causal. Kết hợp:

```text
threat/exposure + control performance + response capability + loss outcome
```

Nếu leading cải thiện nhưng loss không đổi, xem lag, threat mix, validity và unintended behavior—not kết luận ngay control vô dụng.

## 24. KPI, KRI và KCI

- **KPI:** performance capability/process, như time-to-verified-remediation.
- **KRI:** exposure/proximity tới tolerance, như % critical service phụ thuộc một IdP.
- **KCI:** control health/effectiveness, như % privileged revoke test đạt 5 phút.

Một measure có thể đóng vai trò khác theo decision. Đừng tranh taxonomy; ghi goal, owner, threshold và action. KPI tốt không bảo đảm risk thấp nếu threat/exposure tăng.

## 25. Target, threshold, tolerance và trigger

- target là mức mong muốn;
- threshold phân loại attention/action;
- tolerance là mức deviation/risk chấp nhận;
- limit là ranh không được vượt theo authority/obligation;
- trigger là event/condition mở decision workflow.

Mỗi ngưỡng cần rationale, horizon, owner, breach action và review date. Không tô đỏ nếu không ai có thẩm quyền/capacity xử lý; không tự đổi target để dashboard xanh.

## 26. Baseline, trend và seasonality

Baseline là trạng thái tham chiếu có scope/period, không mặc định là acceptable. Trend cần:

- cùng definition/population hoặc annotation khi đổi;
- đủ period cho seasonality/release cycle;
- confidence/data-quality context;
- event/change annotation;
- absolute và relative change;
- target/tolerance line;
- tránh chọn start date thuận lợi.

Một quý giảm 20% từ spike bất thường không chứng minh improvement bền. Dùng control chart/change-point khi dữ liệu phù hợp, nhưng không làm phức tạp hơn decision cần thiết.

## 27. Correlation không phải causation

Sau khi rollout training, phishing report tăng có thể do awareness tốt hơn, campaign nhiều hơn hoặc sensor đổi. Để đánh giá tác động:

- ghi intervention và theory of change;
- dùng comparison/cohort khi hợp lý;
- kiểm confounder và concurrent changes;
- đo intermediate control outcome;
- xem trước/sau đủ dài;
- dùng randomized/phased rollout khi an toàn;
- nêu giới hạn inference.

Không gán mọi trend tốt cho chương trình security vừa tài trợ.

## 28. Goodhart, gaming và unintended consequence

Khi metric thành target, hành vi có thể tối ưu metric:

- đóng ticket rồi reopen để giảm MTTR;
- hạ severity/loại asset khỏi scope;
- tăng alert để chứng minh detection coverage;
- ép MFA count nhưng bỏ recovery/session;
- chạy tabletop dễ để đạt pass rate;
- không báo near miss.

Giảm rủi ro bằng metric pair, audit sample, stable denominator, outcome check, no-blame learning và xem qualitative evidence. Không thưởng cá nhân theo proxy dễ game.

## 29. Sampling và selection bias

Nếu không đo toàn population, ghi sampling frame, method, size và non-response. Common bias:

- chỉ test hệ thống tự nguyện/trưởng thành;
- chỉ tính incident được detect;
- scanner chỉ thấy reachable asset;
- closed-ticket cohort bỏ finding khó;
- survey response từ nhóm quan tâm security;
- restore test chọn backup mới/dễ.

Risk-based sample hữu ích cho assurance nhưng không dùng để ước lượng prevalence toàn fleet nếu probability không biết.

## 30. Composite score và heatmap

Composite score có thể tóm tắt nhưng dễ che:

- unit/scale khác nhau;
- weighting tùy ý;
- compensation: control rất tệ bị metric tốt bù;
- threshold discontinuity;
- correlation/double counting;
- unknown biến thành zero;
- loss of drill-down.

Nếu dùng, publish formula/weight/sensitivity, giữ veto/floor cho critical condition, hiển thị components và không tuyên bố risk giảm chỉ vì score tăng.

## 31. Aggregation từ system tới enterprise

Giữ hierarchy:

```text
raw observation → control/service measure → risk scenario indicator
  → business objective impact → enterprise portfolio view
```

Aggregate theo common objective/scenario/dependency, không cộng CVE/alert/maturity score. Mỗi enterprise indicator cần drill-down tới owners/actions/evidence và tránh mất material tail trong average.

## 32. Correlation, concentration và double counting

30 services phụ thuộc cùng IdP không phải 30 independent risks. Portfolio analysis cần:

- shared root cause/control plane/supplier;
- simultaneous loss/cascading dependency;
- geographic/identity/key/admin concentration;
- duplicated finding/exposure;
- common compensating control;
- diversification thực hay chỉ nhiều label.

Báo scenario “IdP mất/compromise ảnh hưởng 72% critical services” rõ hơn tổng 30 risk scores. Không credit cùng control nhiều lần trong expected reduction.

## 33. Risk quantification và expected loss

Định lượng có thể hỗ trợ trade-off khi model đủ tốt:

```text
annualized loss distribution = event frequency distribution × loss magnitude distribution
```

Nhưng tránh một expected value che tail. Báo percentile/range, scenario, time horizon, dependency, control effect, data source và sensitivity. Monetary estimate không thay safety,
legal, ethical hoặc appetite constraint. Nếu input chủ yếu expert judgment, nói rõ và calibrate/update sau incident.

## 34. Đo control effectiveness

Tách:

- design adequacy: control có thể đạt objective trong scenario không;
- implementation coverage: đúng scope có deploy/config chưa;
- operating effectiveness: hoạt động theo thời gian không;
- outcome contribution: giảm path/impact/likelihood thế nào;
- resilience: fail/degraded/recovery ra sao;
- bypass/exception: effective uncovered path;
- evidence confidence/freshness.

“EDR installed 98%” chỉ đo deployment; cần sensor health, policy/tamper, detection/containment test và critical unknown 2%.

## 35. Coverage, exposure và outcome

Ba lớp bổ trợ:

| Lớp | Ví dụ |
|---|---|
| Coverage | % critical access paths có PEP được verify |
| Exposure | privileged grant-hours ngoài approved window |
| Outcome | unauthorized path bị deny trong negative test/incident |

Coverage không có chất lượng/effectiveness là vanity; outcome hiếm cần proxy. Dùng control-health + exposure + validation/incident evidence để triangulate.

## 36. Ví dụ metric Vulnerability Management

Hữu ích:

- asset/assessment coverage × depth × freshness;
- critical exposure-hours theo business tier;
- time-to-mitigate/fix/verify p50/p95;
- KEV/observed exploitation lane age;
- % fix source/fleet verified và recurrence;
- exception scope/age/expiry;
- root-cause campaign risk reduction;
- EOL/unknown ownership.

Tránh raw CVE count, average CVSS và closure volume. Scanner tốt hơn có thể làm finding tăng trong khi posture cải thiện vì unknown giảm.

## 37. Ví dụ metric Detection & Incident Response

- priority scenario telemetry/detection coverage;
- signal-to-triage/contain/revoke p50/p95 theo severity;
- true/false positive cùng missed/late detection sample;
- evidence completeness và time-to-scope confidence;
- containment efficacy/reinfection/reopen;
- dwell/exposure window với uncertainty;
- playbook action success và dependency failure;
- recurring root cause/corrective-action verification;
- customer/business impact/recovery time.

Alert count và analyst cases closed đo workload, không tự đo detection outcome.

## 38. Ví dụ metric IAM và Zero Trust

- authoritative identity/account reconciliation coverage;
- leaver-to-effective-deny p95;
- standing privileged access/grant-hours;
- JIT/JEA coverage và unused privilege;
- phishing-resistant auth coverage theo risk path;
- workload identity/static secret elimination;
- policy propagation/revoke-to-deny;
- critical PEP path/bypass negative test coverage;
- stale device/attribute/unknown rate;
- break-glass test/use/review.

MFA enrollment percentage che local/admin/recovery/session bypass nếu denominator là user thay vì access path.

## 39. Ví dụ metric third-party và supply-chain

- critical relationship owner/data/access/subprocessor completeness;
- evidence current/in-scope rate;
- effective SaaS tenant configuration conformance;
- high-risk finding/exception overdue;
- incident notification/customer containment latency;
- supplier/change reassessment latency;
- concentration theo critical service/shared provider;
- supported artifact/provenance/SBOM coverage;
- exit/export/delete/recovery drill success;
- shadow SaaS discovery-to-decision.

Không average vendor questionnaire score hoặc đếm certificate.

## 40. Ví dụ metric resilience và recovery

- critical service có approved BIA/dependency map;
- backup scope/integrity/restore-test coverage;
- actual RTO/RPO so objective theo scenario;
- time tới business-usable service và backlog clear;
- recovery data/business invariant pass;
- clean identity/key/bootstrap drill;
- manual/degraded mode capacity;
- recovery action/assumption overdue;
- shared recovery dependency/concentration;
- exercise realism và repeat finding.

Backup bytes/job success không chứng minh recoverability.

## 41. Ví dụ metric data security và privacy

- known/classified data store/flow coverage;
- purpose/owner/retention metadata completeness;
- data minimization và sensitive-field proliferation;
- access/export/share policy conformance;
- deletion request-to-verified-deletion time;
- backup/log/subprocessor deletion coverage;
- customer/subject request accuracy;
- policy exception age;
- unauthorized access/exfiltration path test;
- privacy harm/complaint/near miss theo context.

Không tối ưu “số GB xóa” vì volume không nói đúng record/purpose/obligation.

## 42. Engineering flow và program capability

- review intake-to-decision wait/active time;
- golden-path adoption/conformance;
- security requirement-to-test trace coverage;
- time từ recurring finding tới platform fix;
- action/retest age;
- exception recurrence/root cause;
- developer friction/support demand;
- escaped design/implementation issues;
- control service SLO/consumer satisfaction;
- portfolio investment outcome.

Velocity không phải security outcome nhưng bottleneck kéo dài khiến control bị bypass. Đo cả speed và quality.

## 43. Dashboard theo audience

Operator dashboard cần raw/drill/action; owner view cần cohort/root cause; risk view cần scenario/tolerance/treatment; executive view cần trend/concentration/decision.

Thiết kế:

- headline ít nhưng material;
- target/tolerance và status semantics;
- trend + absolute/denominator;
- data quality/unknown/freshness;
- segmentation/tail;
- annotation change/incident;
- owner/action/due date;
- drill-down provenance;
- accessible colors/text.

Màu đỏ/vàng/xanh không thay con số và narrative.

## 44. Executive và board reporting

Nên trả lời:

1. Objective/risk scenario nào material?
2. Exposure so appetite/tolerance và trend ra sao?
3. Vì sao thay đổi, confidence thế nào?
4. Treatment/control có đạt outcome không?
5. Concentration/systemic dependency nào cần oversight?
6. Quyết định/nguồn lực/acceptance nào cần executive?
7. Nếu không hành động, consequence/horizon là gì?

Không trình tool count, technical acronym hay 100 metric. Board oversight không đồng nghĩa board chọn firewall rule.

## 45. Narrative đi cùng số liệu

Mẫu concise:

```text
Signal: p95 privileged revoke-to-deny tăng 4m → 47m trong 2 tuần.
Scope/confidence: 92% T0/T1 paths; 3 legacy systems unknown.
Cause: session revoke queue bị rate-limit sau migration IdP.
Risk: 18 grant-hours vượt tolerance; chưa thấy misuse.
Action: rollback queue config; direct-deny fallback; owner/due 08-07.
Decision needed: tài trợ adapter cho 3 legacy systems trước Q4.
```

Nêu known/unknown, consequence và ask. Không dùng narrative để che dữ liệu xấu hoặc gán causal chưa chứng minh.

## 46. Incident và ad-hoc risk reporting

Trong crisis, speed quan trọng nhưng semantics vẫn cần:

- as-of time và authoritative source;
- confirmed/suspected/unknown;
- affected numerator/known denominator;
- business/customer/data scope;
- confidence và assumption;
- containment/recovery state;
- next decision/update time;
- correction history.

Không nối số ước lượng sớm vào trend “final” mà không label. Sau incident, reconcile timeline/data và cập nhật measure nào không cảnh báo trước.

## 47. Metric lifecycle và change control

```text
propose → design → test/validate → baseline → operate
  → review/calibrate → revise/version or retire
```

Review khi objective, source/schema, population, threat, control, target hoặc action thay đổi. Retire metric nếu không còn decision, validity thấp, cost > value, bị game hoặc đã được thay thế.
Không xóa lịch sử; ghi successor và cách trend bị break. Catalog metric là product, không phải nghĩa địa dashboard.

## 48. Maturity và roadmap

| Stage | Đặc điểm |
|---|---|
| 0 – Activity | count/tool/report thủ công, không owner |
| 1 – Defined | spec, denominator, owner, target/action |
| 2 – Trusted | lineage, quality, unknown, reproducible pipeline |
| 3 – Decision-linked | KPI/KRI/KCI nối scenario/tolerance/treatment |
| 4 – Adaptive | uncertainty, validation, causal learning, metric retirement |

Bắt đầu 5–10 decisions material và critical data contracts; không xây data lake/dashboard platform lớn trước khi definition đúng.

## 49. Ví dụ executive pack một trang

**Objective:** duy trì giao dịch critical và giảm credential-driven compromise.

| Signal | Status/trend | Context | Decision/action |
|---|---|---|---|
| Standing privileged access | 7,2% → 3,1%; target <2% | 96% critical paths; 2 legacy unknown | tài trợ legacy broker |
| Revoke-to-deny p95 | 47m, vượt 5m | IdP migration queue; confidence high | rollback + fallback 08-07 |
| Critical recovery exercise | 8/10 pass | 1 KMS bootstrap, 1 supplier fail | executive sponsor joint drill |
| Supplier concentration | 72% T0/T1 cùng IdP | scenario impact 14 services | alternate recovery identity roadmap |
| KEV exposure > SLA | 4 services, giảm từ 11 | all owner known; 1 exception 12 ngày | no new ask, track expiry |

Narrative nêu một cải thiện, một tolerance breach, một concentration risk và ba quyết định. Appendix giữ definition, quality, cohorts và technical drill-down.

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] Mỗi metric bắt đầu từ objective/question/decision và có action owner.
- [ ] Specification ghi operational definition, formula, unit, scope, source, cadence và limitations.
- [ ] Numerator/denominator/population/time window cùng semantics; unknown báo riêng.
- [ ] Provenance, transform/version/freshness và data-quality dimensions có thể kiểm.
- [ ] Zero, unknown, not-applicable, not-assessed, failed collection và suppressed không bị gộp.
- [ ] Validity/reliability/uncertainty/sample size được xem trước khi ra quyết định.
- [ ] Ordinal scale không bị cộng/trừ/average như interval/ratio data.
- [ ] Mean/median/percentile/distribution/cohort được chọn theo tail và censoring.
- [ ] Metric pairs giảm gaming và nối coverage–exposure–outcome.
- [ ] KPI/KRI/KCI có threshold/tolerance/trigger và breach workflow.
- [ ] Aggregation xử lý shared root cause, correlation, concentration và double counting.
- [ ] Dashboard theo audience, có denominator/quality/owner/action/drill-down.
- [ ] Executive report nối business objective, appetite, trend, confidence và decision ask.
- [ ] Definition/source/target change được version; trend break được annotation.
- [ ] Metric không còn giá trị được retire có chủ đích.

### Anti-pattern thường gặp

- “Có số thập phân nên metric chính xác.”
- “Không có incident nghĩa control hiệu quả.”
- “Không có finding nghĩa asset sạch.”
- “Tỷ lệ tăng luôn tốt” dù denominator giảm.
- “Average MTTR đại diện mọi case.”
- “Lấy trung bình maturity 1–5 để đo risk.”
- “Cộng risk score của mọi system thành enterprise risk.”
- “Dashboard xanh nghĩa trong appetite.”
- “External benchmark cho phép xếp hạng team công bằng.”
- “Correlation sau rollout chứng minh chương trình gây ra improvement.”
- “Board cần xem mọi technical metric.”
- “Metric đã báo nhiều năm thì phải tiếp tục giữ.”

### Tài liệu chính thức

- [NIST SP 800-55 Vol. 1 – Identifying and Selecting Measures](https://csrc.nist.gov/pubs/sp/800/55/v1/final)
- [NIST SP 800-55 Vol. 2 – Developing an Information Security Measurement Program](https://csrc.nist.gov/pubs/sp/800/55/v2/final)
- [NIST IR 8286 Rev. 1 – Integrating Cybersecurity and ERM](https://csrc.nist.gov/pubs/ir/8286/r1/final)
- [NIST IR 8286A Rev. 1 – Identifying and Estimating Cybersecurity Risk](https://csrc.nist.gov/pubs/ir/8286/a/r1/final)
- [NIST IR 8286B Update 1 – Prioritizing Cybersecurity Risk](https://csrc.nist.gov/pubs/ir/8286/b/upd1/final)
- [NIST IR 8286C Rev. 1 – Staging Cybersecurity Risks for Governance Oversight](https://csrc.nist.gov/pubs/ir/8286/c/r1/final)
- [NIST IR 8286D Update 1 – Business Impact Analysis for Risk Prioritization](https://csrc.nist.gov/pubs/ir/8286/d/upd1/final)
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)

### Học tiếp

1. [Security Program Operating Model & Capability Management](../program/security_program_operating_model_capability_management.md) – service catalog, ownership,
   funding, capacity, portfolio prioritization và capability maturity.
2. [Security Strategy, Investment & Portfolio Prioritization](../program/security_strategy_investment_portfolio_prioritization.md) – strategic themes, business case,
   dependency-aware roadmap, benefits realization và stop/continue decisions.

---

*Cập nhật lần cuối: 2026-08-03.*
