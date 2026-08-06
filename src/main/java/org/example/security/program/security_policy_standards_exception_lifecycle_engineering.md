# Security Policy, Standards & Exception Lifecycle Engineering

> Mục tiêu: biến policy system từ tập tài liệu “đã ký” thành cơ chế governance có thể hiểu, triển khai, kiểm chứng và thay đổi an toàn;
> đồng thời quản lý exception theo risk, có thời hạn và có đường quay về trạng thái chuẩn.

---

## 1. Policy engineering là gì?

**Policy engineering** thiết kế cả hệ thống nối ý định quản trị với hành vi vận hành:

```text
law / contract / risk appetite / business objective
    → policy outcome
        → measurable standard / baseline
            → control + implementation pattern
                → enforcement + evidence
                    → conformance / exception / improvement
```

Nó không chỉ là kỹ năng viết văn bản. Nó bao gồm kiến trúc tài liệu, decision rights, rollout, enforcement,
evidence, exception, version migration và retirement.

Một policy tốt chưa tạo ra trạng thái an toàn nếu người thực thi không biết mình thuộc scope nào, “phải làm gì”,
deadline nào áp dụng, dùng golden path nào và chứng minh bằng gì.

## 2. Policy không phải control

Phân biệt các lớp thường bị trộn:

- **Policy** đặt hướng bắt buộc và outcome tổ chức muốn bảo vệ.
- **Control objective** mô tả kết quả kiểm soát cần đạt.
- **Control** là biện pháp thay đổi likelihood/impact hoặc duy trì trạng thái mong muốn.
- **Implementation** là cách một môi trường cụ thể hiện thực control.
- **Evidence** là dữ liệu cho phép đánh giá implementation/control trong một thời điểm và scope.

Ví dụ, “workload phải xác thực bằng danh tính có vòng đời quản lý” là policy direction; cấp short-lived identity,
kiểm audience và tự động rotate là implementation; cấu hình issuer, test result và runtime event là evidence.

Policy không tự chặn request, và một setting “đúng” không tự chứng minh control luôn hiệu quả.

## 3. Hệ phân cấp artifact

Một taxonomy thực dụng:

| Artifact | Câu hỏi nó trả lời | Tính bắt buộc |
|---|---|---|
| Principle | Ta ưu tiên cách suy nghĩ nào? | Định hướng |
| Policy | Outcome/ràng buộc cấp tổ chức là gì? | Bắt buộc |
| Standard | Mức/điều kiện đo được nào phải đạt? | Bắt buộc |
| Baseline/profile | Bộ yêu cầu mặc định cho một lớp scope là gì? | Bắt buộc sau tailoring |
| Procedure/runbook | Ai làm từng bước, khi nào và bằng cách nào? | Bắt buộc trong workflow đã chỉ định |
| Guideline | Cách làm khuyến nghị nào hữu ích? | Không bắt buộc |
| Pattern | Thiết kế tái sử dụng nào đáp ứng requirement? | Approved hoặc recommended |
| Control | Biện pháp nào tạo outcome kiểm soát? | Theo control plan |

Tên gọi có thể khác giữa tổ chức, nhưng semantics phải duy nhất. Không gọi một checklist tùy chọn là “standard”
rồi kỳ vọng enforcement như yêu cầu bắt buộc.

## 4. Contract cho từng loại artifact

Mỗi artifact cần một “contract” tối thiểu:

- ai có authority ban hành, sửa và retire;
- artifact nào có thể tạo requirement bắt buộc;
- cấp nào được override cấp nào;
- approval nào cần cho exception;
- cadence review và trigger review đột xuất;
- cách version, supersede và lưu bản lịch sử;
- nguồn sự thật chuẩn và format máy có thể đọc nếu có.

Nếu policy và standard mâu thuẫn, policy owner không nên âm thầm sửa nghĩa qua FAQ. Phải mở decision,
ghi rationale, chọn artifact có thẩm quyền và phát hành version mới.

## 5. Chuỗi traceability hai chiều

Traceability tốt đi cả xuôi lẫn ngược:

```text
obligation / scenario / appetite
  ↕ policy outcome
  ↕ requirement ID + version
  ↕ control objective + control owner
  ↕ implementation / enforcement point
  ↕ test procedure + evidence
  ↕ finding / exception / residual risk
```

Đi xuôi giúp đội triển khai hiểu “vì sao”; đi ngược giúp assessor biết evidence đang chứng minh yêu cầu nào.
Mỗi mapping cần scope, hiệu lực, version và mức coverage—not chỉ một hyperlink mơ hồ.

Đừng ép quan hệ thành 1:1: một obligation có thể cần nhiều controls; một common control có thể hỗ trợ nhiều requirements.

## 6. Scope và applicability

Policy phải định nghĩa rõ:

- tổ chức, pháp nhân, geography và workforce nào thuộc phạm vi;
- asset, data, service, supplier và environment nào áp dụng;
- lifecycle stage nào chịu yêu cầu;
- tiêu chí phân loại như criticality, sensitivity, exposure hoặc impact;
- ngày hiệu lực cho new build và legacy estate;
- ai quyết định applicability khi scope không rõ.

“Áp dụng cho mọi hệ thống” thường che giấu ngoại lệ thực tế. Scope rộng nhưng không có inventory và owner sẽ tạo
compliance ảo: không biết denominator nên cũng không biết coverage.

## 7. Authority, accountability và ownership

Tách các vai trò:

| Vai trò | Accountability chính |
|---|---|
| Governing body/executive | phê chuẩn direction và delegated authority |
| Policy owner | meaning, scope, lifecycle và exception rule |
| Standard owner | requirement kỹ thuật đo được và version migration |
| Control owner | design/effectiveness của control dùng chung |
| Implementation owner | trạng thái của system/process cụ thể |
| Risk owner | quyết định residual risk trong thẩm quyền |
| Assessor/assurance | đánh giá độc lập theo criteria |
| Document custodian | repository, metadata, publication—không thay policy owner |

Người viết văn bản không mặc nhiên là risk owner; người vận hành tool cũng không tự phê chuẩn ngoại lệ cho chính mình.

## 8. Lifecycle và state model

Quản policy như managed product:

```text
idea → draft → consultation → approved → published
     → transition → effective → monitored → revised/superseded → retired/archive
```

State cần machine-readable. “Approved” chưa đồng nghĩa “effective”; khoảng transition cho phép consumer migrate.
Một bản superseded không dùng cho thiết kế mới nhưng có thể vẫn chi phối exception/legacy scope trong thời gian chuyển tiếp.

Trigger review ngoài cadence gồm law mới, incident, threat thay đổi, platform migration, acquisition, control failure,
exception concentration hoặc requirement gây harm ngoài dự kiến.

## 9. Metadata tối thiểu

Mỗi policy/standard nên có:

```yaml
id: SEC-IAM-STD-014
version: 3.1
status: effective
owner: Identity Governance
approved_by: Security Governance Council
approved_at: 2026-06-15
effective_at: 2026-09-01
review_by: 2027-06-15
supersedes: SEC-IAM-STD-014@3.0
scope_profile: internet-facing-production
exception_process: EXC-001
```

Thêm classification, contact, change summary, normative references và canonical URL. Không dùng ngày “last updated”
thay cho semantic version và effective date.

## 10. Ngôn ngữ chuẩn tắc

Dùng từ có semantics thống nhất:

- **MUST / SHALL**: bắt buộc; vi phạm cần remediation hoặc exception hợp lệ.
- **MUST NOT**: bị cấm.
- **SHOULD**: kỳ vọng mặc định; nếu không theo cần rationale được ghi nhận theo quy ước.
- **MAY**: được phép, không phải requirement.
- **RECOMMENDED**: guidance, không âm thầm biến thành audit finding.

Không trộn “nên”, “cần”, “phải cố gắng” tùy người viết. Glossary phải nói rõ bản dịch tiếng Việt và cách assessor
xử lý từng từ.

## 11. Công thức requirement kiểm chứng được

Một requirement tốt thường có:

```text
subject + normative action + protected object
  + condition / scope + threshold + timing
  + allowed mechanism / prohibited state
  + expected evidence + exception route
```

Ví dụ yếu: “Dữ liệu nhạy cảm phải được mã hóa phù hợp.”

Ví dụ tốt hơn: “Storage chứa Restricted Data trong production MUST mã hóa data at rest bằng approved cryptographic
profile; key MUST do managed key service kiểm soát, tách quyền quản trị dữ liệu/key; conformance được đánh giá liên tục
từ inventory, effective configuration và key-policy evidence.”

## 12. Loại bỏ từ mơ hồ

Các cụm cần định nghĩa hoặc thay thế:

- “periodically” → mỗi 90 ngày hoặc theo event nào;
- “where appropriate” → decision criteria và người quyết định;
- “industry best practice” → standard/profile/version cụ thể;
- “strong encryption” → approved algorithm/key/protocol profile;
- “timely” → SLA theo severity/criticality;
- “securely” → trạng thái bị cấm, control và test;
- “all systems” → inventory class và exclusions.

Nếu flexibility thật sự cần thiết, biểu diễn bằng parameter hoặc risk-based profile; đừng giấu nó trong tính từ.

## 13. Outcome-based và implementation-specific

Policy nên bền hơn technology; standard có thể cụ thể hơn:

```text
Policy: privileged access phải time-bound, attributable và reviewable.
Standard: production admin elevation tối đa 4 giờ, MFA phishing-resistant,
          approval độc lập cho tier critical, session/action log giữ 365 ngày.
Pattern: dùng broker X hoặc cloud-native role Y theo cấu hình đã phê duyệt.
```

Quá outcome-based khiến không test được; quá product-specific ở policy khiến văn bản lỗi thời và khóa vendor.
Đặt chi tiết tại tầng có lifecycle phù hợp.

## 14. Control objective, control và parameter

Tách ba thứ:

- objective: “chỉ workload được ủy quyền mới truy cập service”;
- control: workload identity, authorization policy và credential lifecycle;
- parameter: TTL, accepted issuer, audience, re-authentication threshold.

Parameter nên có owner, source, range và profile. Một con số copy từ template không tự phù hợp với mọi risk tier.
Thay đổi parameter quan trọng cần impact analysis, test và version—even nếu không sửa câu policy.

## 15. Baseline và profile

Baseline là điểm khởi đầu có chủ ý, không phải minimum áp cho mọi nơi. Có thể tạo profile theo:

- data sensitivity;
- service criticality/impact;
- internet exposure;
- regulated workload;
- development, test, production;
- endpoint, server, SaaS, OT hoặc cloud workload.

Profile phải có tiêu chí chọn rõ và tránh tổ hợp vô hạn. Khi nhiều profile cùng áp dụng, định nghĩa precedence hoặc phép hợp
nhất—thường lấy requirement nghiêm hơn, trừ khi conflict được quyết định chính thức.

## 16. Tailoring đúng nghĩa

Tailoring điều chỉnh baseline theo context và risk bằng quy trình có kỷ luật:

1. xác định applicability;
2. parameterize theo context;
3. loại control không áp dụng với rationale;
4. bổ sung control vì scenario đặc thù;
5. thay bằng control tương đương khi cần;
6. đánh giá gap và residual risk;
7. phê chuẩn, ghi version và revalidate.

Tailoring không phải xóa requirement để dashboard xanh. Kết quả là **tailored baseline** có authority và traceability,
không phải exception bí mật của từng system.

## 17. Not applicable không phải compliant

`not_applicable` là một kết luận scope, cần:

- requirement ID/version;
- asset/process và boundary;
- predicate applicability không thỏa;
- evidence chứng minh predicate;
- owner, reviewer, decision date;
- trigger/cadence revalidation.

Ví dụ “không lưu card data” chỉ đúng khi data discovery, architecture và contract cùng hỗ trợ. Nếu system bắt đầu nhận loại
dữ liệu mới, decision phải tự hết hiệu lực hoặc được re-evaluate.

Không gộp `not_applicable`, `not_tested`, `unknown` và `passed` vào một trạng thái xanh.

## 18. Alternative và compensating control

Alternative control là thiết kế khác vẫn đạt outcome; compensating control thường giảm risk khi requirement gốc chưa đạt.
Đánh giá bằng:

| Câu hỏi | Nội dung |
|---|---|
| Coverage | cùng asset, actor, path và lifecycle không? |
| Strength | ngăn/phát hiện/phục hồi mạnh đến đâu? |
| Timing | preventive hay chỉ phát hiện muộn? |
| Independence | có cùng common failure không? |
| Operability | owner, capacity, alert/action có thật không? |
| Evidence | test nào chứng minh hoạt động? |
| Residual gap | pathway nào còn mở? |

Không gọi “monitoring tăng cường” là bù đắp nếu không có signal, threshold, responder, SLA và test.

## 19. Xử lý requirement xung đột

Conflict có thể đến từ security, privacy, safety, availability, legal hold hoặc local law. Quy trình nên:

1. ghi chính xác hai requirement và authority;
2. kiểm tra scope/version/interpretation trước;
3. mô hình hóa harm của từng option;
4. mời đúng policy/legal/privacy/safety owner;
5. chọn resolution có thẩm quyền;
6. lưu decision, residual risk và review trigger;
7. sửa artifact gốc nếu conflict mang tính hệ thống.

Không để delivery team tự chọn requirement “dễ hơn”. Exception nội bộ cũng không làm mất nghĩa vụ pháp lý bên ngoài.

## 20. Obligation mapping

Một law/contract/framework statement không nên copy nguyên văn thành hàng trăm policy clauses. Lập obligation record:

```text
source + citation + jurisdiction + applicability + effective date
  → interpreted obligation + legal owner
  → policy outcome / requirement IDs
  → control coverage + evidence
  → gaps / decisions / change history
```

Mapping là many-to-many và cần confidence. `mapped` không đồng nghĩa `compliant`; nó chỉ nói quan hệ đã được thiết lập.
Legal interpretation cần người có thẩm quyền, không do scanner hoặc language model tự quyết.

## 21. Kiến trúc policy domain

Tổ chức domain theo capability/risk ổn định: identity, data, resilience, secure development, supplier, incident, workforce…
Mỗi domain có parent policy, standards cần thiết và control/pattern liên quan.

Giữ graph dependency thay vì nhân bản câu chữ. Một định nghĩa “Restricted Data” nên có canonical owner; artifact khác reference
đúng version thay vì tự định nghĩa lại.

Policy architecture review tìm duplicate, conflict, orphan requirement, circular reference và policy explosion. Ít artifact rõ
nghĩa thường tốt hơn nhiều tài liệu che phủ giả.

## 22. Intake và drafting workflow

Mọi đề xuất policy mới cần problem statement:

- risk/obligation/business outcome nào thúc đẩy;
- population và current state;
- harm nếu không thay đổi;
- vì sao policy là intervention phù hợp;
- platform/process/control nào sẽ giúp thực thi;
- cost, dependency và transition dự kiến;
- cách đo intended và unintended outcome.

Sau đó mới draft requirement IDs. Không tạo policy để “chứng minh đã xử lý” một incident khi root cause nằm ở design,
capacity hoặc incentive.

## 23. Consultation có cấu trúc

Review không chỉ gửi email “xin ý kiến”. Cần review matrix:

| Reviewer | Câu hỏi chính |
|---|---|
| Consumer/operations | hiểu, làm được, workload/friction nào phát sinh? |
| Architecture/platform | golden path và enforcement point có sẵn? |
| Assurance/audit | criteria và evidence có đủ? |
| Legal/compliance | authority, obligation, jurisdiction? |
| Privacy/HR | data/people impact, transparency, fairness? |
| Resilience/safety | failure mode và availability harm? |
| Finance/procurement | funding, supplier/contract dependency? |

Ghi comment, disposition và rationale; disagreement quan trọng phải tới decision forum, không bị “resolved” bằng im lặng.

## 24. Feasibility và impact assessment

Trước approval, đo:

- inventory/denominator và current conformance;
- kỹ thuật nào chưa hỗ trợ requirement;
- effort/cost cho consumer và control provider;
- legacy, supplier, regional và accessibility constraints;
- transition risk, outage/failure mode;
- exception volume dự báo;
- ngày khả thi cho new build và existing estate.

Policy không có funded implementation path sẽ tạo paper compliance hoặc exception flood. Nếu platform gap là common,
fund common capability thay vì buộc từng team tự chế.

## 25. Approval và delegated authority

Approval matrix dựa trên loại quyết định và materiality:

- governing body: policy direction và risk appetite boundary;
- domain authority: standard, baseline/profile và interpretation;
- control owner: implementation pattern/test procedure;
- risk owner: residual risk trong giới hạn;
- legal/privacy/safety authority: ràng buộc thuộc chuyên môn;
- emergency delegate: exception ngắn hạn theo condition định trước.

Delegation cần scope, monetary/risk threshold, prohibited decisions, escalation và expiry. Một chữ ký không bù cho thiếu
evidence; nhưng automation cũng không được vượt authority đã giao.

## 26. Publication và source of truth

Canonical repository phải cung cấp:

- bản human-readable và machine-readable nhất quán;
- stable ID, version, status và effective date;
- diff/change summary;
- owner/contact và interpretation log;
- dependency/backlink;
- archive immutable cho bản cũ;
- notification/subscription theo affected scope.

PDF đính kèm email không phải source of truth. Search phải giúp consumer tìm requirement theo role, asset và profile—not bắt
họ đọc toàn bộ library để đoán applicability.

## 27. Communication, learning và attestation

Communication theo thay đổi hành vi:

- ai bị ảnh hưởng và task nào đổi;
- từ ngày nào, với system mới hay cả legacy;
- golden path/tool/support ở đâu;
- cách kiểm tra trước enforcement;
- cách xin exception;
- consequence và escalation công bằng.

Attestation chỉ xác nhận người dùng đã đọc/hiểu theo mục đích định trước; nó không chứng minh implementation. Với role quan
trọng, dùng scenario/practice và performance support gần workflow thay vì annual checkbox duy nhất.

## 28. Transition plan

Mỗi requirement material cần rollout:

```text
baseline current state → readiness → pilot/dry-run
  → new-build effective → migration waves
  → full enforcement → legacy path retirement
```

Đặt owner, dependency, capacity, entry/exit criteria, exception forecast, support channel, rollback và maximum coexistence.
Ngày ban hành, ngày hiệu lực và ngày enforcement có thể khác nhau nhưng phải minh bạch.

Nếu deadline không khả thi, sửa plan/authority sớm; đừng chờ tới ngày audit rồi hợp thức hóa hàng loạt.

## 29. Enforcement design

Chọn enforcement point gần nơi trạng thái được tạo:

- template/golden path;
- CI/pre-merge test;
- provisioning/IaC validation;
- admission/control plane;
- runtime authorization;
- periodic detective check;
- human workflow/approval;
- contract và supplier assurance.

Preventive không luôn tốt hơn detective: block sai có thể gây safety/availability harm. Chọn theo latency cần thiết,
reversibility, false-positive cost và khả năng recovery.

## 30. Policy as code và giới hạn

Policy as code mã hóa phần requirement có predicate quyết định được. Mỗi rule cần:

```yaml
rule_id: PA-SEC-IAM-014
requirement: SEC-IAM-STD-014@3.1#R7
scope: production-workload
mode: enforce
owner: Platform Identity
evidence_schema: identity-policy-result@2
```

Code không thay toàn bộ policy: judgment về proportionality, legal context, human due process hoặc risk ownership thường
không thể rút gọn thành boolean. Automation phải trả `pass`, `fail`, `not_applicable`, `unknown/error` riêng biệt.

## 31. Version và test policy code

Quản rule như production software:

- code review và separation of duties;
- unit test positive/negative/boundary;
- fixture cho mỗi profile/version;
- test `unknown`, timeout, dependency unavailable;
- integration test tại enforcement point;
- signed artifact/provenance nếu cần;
- changelog, backward compatibility và rollback;
- mapping cố định tới requirement version.

Một rule “pass” sau khi parser lỗi là fail-open nguy hiểm. Test phải chứng minh cả semantics của input, evaluation và output,
không chỉ coverage dòng code.

## 32. Advisory, dry-run, canary và block

Rollout enforcement theo confidence:

1. **observe** để hiểu data quality và denominator;
2. **advisory** trả feedback không chặn;
3. **dry-run** tính decision như enforce và đo impact;
4. **canary** chặn cohort đại diện nhỏ;
5. **enforce** theo wave;
6. **sustain** monitor drift, bypass và false decision.

Exit criteria gồm precision, coverage, consumer readiness, support capacity và rollback rehearsal. Đừng để advisory tồn tại vô
thời hạn; nhưng cũng đừng block chỉ vì deadline truyền thông đã đến.

## 33. Failure và degraded mode

Quyết định fail-open/fail-closed theo scenario:

| Tình huống | Câu hỏi |
|---|---|
| Policy engine unavailable | request nào có thể tiếp tục, trong bao lâu? |
| Stale bundle | maximum staleness và revocation path? |
| Evidence pipeline lỗi | trạng thái là unknown hay pass? |
| Emergency operation | break-glass scope và reconciliation? |
| False block hàng loạt | kill switch authority và audit? |

Degraded mode là policy decision có threat model, owner, telemetry, expiry và recovery—not hard-coded ngẫu nhiên trong client.

## 34. Evidence contract và provenance

Evidence contract nêu:

- requirement/control/test ID và version;
- object/scope/tenant/environment;
- observed/effective state, không chỉ desired state;
- collection method/tool/version;
- timestamp, freshness và validity window;
- identity/authority của producer;
- completeness/coverage và sampling;
- integrity/provenance, access và retention;
- result cùng limitation/uncertainty.

Screenshot phù hợp cho điều tra ngắn hạn nhưng yếu cho assurance quy mô lớn. Evidence tốt phải reproducible và giữ được
ngữ cảnh đủ để người khác diễn giải đúng.

## 35. Conformance và control effectiveness

Tách ba kết luận:

- **requirement conformance**: observed state đáp criteria tại scope/time;
- **control implementation**: control đã được triển khai như thiết kế;
- **control effectiveness**: control đạt objective trong điều kiện vận hành.

Configuration đúng không chứng minh responder xử lý alert; training hoàn thành không chứng minh hành vi; control chạy ở 60%
inventory không thể đại diện toàn estate.

Assessment plan quy định examine/interview/test, sample, independence, frequency và cách xử lý limitation. Không dùng audit pass
năm trước như assurance vĩnh viễn.

## 36. Taxonomy cho non-conformance và decision

| Khái niệm | Nghĩa |
|---|---|
| Finding | Evidence cho thấy criteria không đạt hoặc chưa chứng minh được |
| Deviation | Trạng thái thực tế khác baseline/approved design |
| Exception | Cho phép có điều kiện không đáp requirement trong scope/time cụ thể |
| Waiver | Từ bỏ một yêu cầu/quyền theo authority xác định; nhiều nơi dùng như exception |
| Alternative control | Cách khác được chấp thuận để đạt cùng objective |
| Risk acceptance | Risk owner chấp nhận residual risk trong thẩm quyền |
| Suppression | Ẩn/giảm signal của tool; không thay đổi requirement hay risk |
| False positive | Detector kết luận sai so với criteria/ground truth |

Tổ chức phải chọn semantics chính thức. Đổi label trong ticket không làm finding biến thành exception hợp lệ.

## 37. Exception intake

Request tối thiểu gồm:

```text
exact requirement ID + version
asset / process / population / environment
business need và reason không thể conform
requested start + hard expiry
threat/risk scenario + affected objective
current exposure + proposed compensating controls
evidence + accountable implementation owner
remediation / migration plan + milestones
dependencies và requested approvers
```

Reject hoặc trả lại request kiểu “xin miễn policy security cho project X”. Scope không định danh được thì không thể đánh giá,
enforce expiry hay xác nhận closure.

## 38. Exception assessment

Assessor kiểm:

1. requirement thực sự có áp dụng không;
2. có interpretation error hay false finding không;
3. approved pattern/parameter/tailoring có giải quyết được không;
4. scenario, likelihood, impact và uncertainty;
5. exposure window, blast radius, concentration;
6. alternative/compensating control và evidence;
7. legal/privacy/safety/customer constraints;
8. remediation feasibility và risk of change;
9. authority cần thiết.

Exception process không nên phạt team nêu gap sớm. Fast, transparent triage làm giảm shadow bypass và tăng chất lượng inventory.

## 39. Thiết kế compensating control

Compensation cần control statement cụ thể:

```text
Until workload identity migration completes,
legacy credential is restricted to service A,
stored in managed secret service, rotated every 24h,
egress-limited, usage alerted within 5 minutes,
and access reviewed weekly by owner B.
```

Gắn test/evidence, owner, operating cost và failure response cho từng control. Xác định gap nó không bù được; detective control
thường không khôi phục đầy đủ preventive strength.

Nếu compensation đắt hơn remediation nhưng exception vẫn renew, đó là tín hiệu governance hoặc prioritization hỏng.

## 40. Approval và risk acceptance

Hai decision riêng:

- **policy/standard owner** xác nhận exception route, interpretation và điều kiện;
- **risk owner** có business accountability chấp nhận residual risk trong delegated limit.

Control owner cung cấp feasibility/evidence nhưng không tự chấp nhận impact cho business. Cấp phê chuẩn tăng theo criticality,
data, external commitment, duration, blast radius và aggregate exposure.

Decision record phải nêu accepted scenario—not chỉ score—cùng assumptions, conditions, expiry và trigger thu hồi.

## 41. Expiry, review và renewal

Exception luôn time-bound. Hệ thống cần:

- nhắc trước milestone và expiry;
- owner attestation rằng scope/evidence còn đúng;
- kiểm compensating control liên tục;
- tự đưa trạng thái về non-compliant khi hết hạn;
- stop/limit renew liên tiếp;
- escalation khi owner rời tổ chức hoặc milestone trễ;
- closure evidence khi conform hoặc asset retire.

Renewal là quyết định mới với current evidence, không phải nút “extend”. Short expiry nhưng auto-renew vô hạn chỉ tạo cảm giác kiểm soát.

## 42. Emergency exception và break-glass

Emergency path dùng khi delay gây harm lớn hơn và thời gian không đủ cho flow thường. Guardrail:

- predefined eligible scenario;
- named emergency authority;
- minimum scope và duration;
- strong authentication, reason và immutable log;
- monitoring/containment tăng cường;
- notification ngay cho owner;
- retrospective review trong SLA;
- credential/config reconciliation và closure.

Break-glass là access/action tạm thời; không mặc nhiên là risk acceptance dài hạn. Mỗi lần dùng cần xác minh necessity và học để
cải thiện normal path.

## 43. Exception register và portfolio view

Central register cần query theo requirement, owner, asset, business unit, supplier, criticality, expiry và risk scenario.
Đo ít nhất:

- open/expired/renewed exceptions với denominator;
- age và time-to-decision/time-to-close;
- compensating-control health;
- concentration theo common dependency;
- repeated root cause và policy/pattern gap;
- exposure-weighted trend—not chỉ count.

Nhiều exception giống nhau thường là product signal: baseline không khả thi, golden path thiếu, migration không được fund hoặc
requirement viết sai. Sửa hệ thống gốc thay vì tuyển thêm người duyệt ticket.

## 44. Giới hạn của “chấp nhận risk”

Tổ chức chỉ chấp nhận phần risk nằm trong thẩm quyền. Một approval nội bộ không xóa:

- luật/quy định bắt buộc;
- quyền của data subject/employee;
- safety duty;
- contractual/customer commitment;
- regulator/court order;
- nghĩa vụ thông báo hoặc recordkeeping.

Legal/compliance owner phải xác định option hợp pháp: remediation, thay scope/process, xin approval bên có thẩm quyền, sửa contract
hoặc dừng hoạt động. Không ghi “risk accepted” để biến nghĩa vụ không thể waive thành màu xanh.

## 45. Version change và migration

Phân loại thay đổi:

- editorial: không đổi semantics;
- clarification: làm rõ interpretation;
- parameter/profile update;
- additive requirement;
- breaking/stricter requirement;
- emergency revocation.

Semantic change cần version mới, impact analysis, dependency diff, consumer notification, transition và test migration.
Exception phải gắn requirement version: khi version mới có hiệu lực, quyết định cũ được re-evaluate chứ không âm thầm chuyển theo.

Machine-readable schema cũng cần compatibility và migration như API contract.

## 46. Retirement và archive

Retire khi obligation mất, risk treatment thay đổi, artifact bị hợp nhất hoặc technology không còn. Checklist:

- xác định replacement/superseding version;
- tìm downstream references, rules, tests, contracts và training;
- quyết định fate của findings/exceptions;
- gỡ enforcement an toàn theo dependency;
- thông báo consumer và update catalog;
- lưu immutable archive, approvals và effective history;
- xác minh không còn orphan control/evidence job.

Xóa file không phải retirement. Ngược lại, giữ mọi policy “just in case” khiến người dùng không biết bản nào có hiệu lực.

## 47. Metrics cho policy system health

Metric phải hỗ trợ decision:

| Câu hỏi | Measure gợi ý |
|---|---|
| Requirement có triển khai được? | conformance theo eligible population, unknown coverage, time-to-conform |
| Policy có rõ? | interpretation requests, conflicting decisions, rework rate |
| Rollout có an toàn? | dry-run impact, false block, rollback, adoption funnel |
| Exception có kiểm soát? | exposure-weighted age, expiry breach, renewal, compensation health |
| Library có khỏe? | stale/orphan/duplicate artifact, overdue review, broken mapping |
| Outcome có đạt? | control effectiveness và risk outcome gắn scenario |

Không tối ưu “100% policy reviewed đúng hạn” nếu review chỉ đổi ngày. Luôn giữ denominator, data quality và uncertainty.

## 48. Ví dụ: workload identity standard và legacy exception

Requirement `WI-007@2.0`: production workload gọi payment API MUST dùng short-lived identity từ approved issuer, audience-bound,
TTL tối đa 15 phút; static credential bị cấm từ 2026-12-01.

Legacy batch chạy trên appliance chưa hỗ trợ federation:

```text
scope: appliance-17 → payment-api/read-only
exception: 2026-09-01 .. 2026-11-15
scenario: credential theft permits replay
compensation: managed secret, 24h rotation, source network allowlist,
              read-only scope, 5-minute anomaly response, weekly review
owner: Payment Operations
risk owner: Head of Payments
exit: replace connector; tests WI-007-P01..P05 pass
```

Nếu connector trễ, renewal phải dùng evidence mới và escalation; không đổi expiry trong spreadsheet cũ.

## 49. Lộ trình triển khai 90 ngày

**Ngày 1–30 — Inventory và semantics**

- lập catalog artifact/owner/status/version;
- thống nhất taxonomy và normative language;
- chọn một domain có pain rõ;
- map obligation→requirement→control→evidence;
- inventory exception hiện có và expired shadow decisions.

**Ngày 31–60 — Pilot lifecycle**

- viết lại 5–10 requirements kiểm chứng được;
- tạo baseline/profile, applicability và tailoring record;
- thiết kế evidence contract, test và policy-code dry-run;
- triển khai exception intake/assessment/expiry register;
- review legal/privacy/resilience và consumer feasibility.

**Ngày 61–90 — Enforce và học**

- pilot/canary một cohort đại diện;
- đo coverage, false decision, friction và exception forecast;
- diễn tập engine outage/emergency exception;
- sửa standard/pattern/platform gap;
- phê duyệt rollout waves, migration và retirement plan.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist production

- [ ] Artifact taxonomy có semantics, authority và precedence rõ.
- [ ] Mỗi requirement có stable ID/version, scope, threshold, timing và evidence.
- [ ] Obligation→outcome→control→implementation→test trace được hai chiều.
- [ ] Baseline/profile có applicability, tailoring và revalidation.
- [ ] Publication phân biệt approved, effective, superseded và retired.
- [ ] Enforcement có dry-run/canary, degraded mode, rollback và owner.
- [ ] Evidence phản ánh effective state, freshness, coverage và provenance.
- [ ] Finding, exception, waiver, suppression và risk acceptance không bị trộn.
- [ ] Exception có exact scope, compensation, risk owner, expiry và exit plan.
- [ ] Version migration và retirement xử lý mọi dependency/downstream consumer.

### Anti-pattern cần tránh

- Policy là câu khẩu hiệu, không có subject/scope/criteria.
- Copy framework/control catalog thành policy mà không interpret theo context.
- “Industry best practice”, “periodically” hoặc “where appropriate” không có definition.
- Approved document được coi là implemented/effective.
- Policy as code trả lỗi/unknown thành pass.
- `not applicable` được dùng để làm đẹp compliance score.
- Monitoring được gọi là compensating control nhưng không có response.
- Policy owner tự nhận business risk vượt authority.
- Exception không expiry hoặc renew chỉ vì chưa bị incident.
- Policy cũ bị xóa mà không supersede, migrate và archive.

### Nguồn chính thức

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — Govern, policy, roles, oversight và risk outcomes.
- [NIST SP 800-53 Rev.5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — catalog security/privacy controls tích hợp.
- [NIST SP 800-53B Release 5.2.0](https://csrc.nist.gov/pubs/sp/800/53/b/upd1/final) — control baselines, tailoring và overlays.
- [NIST SP 800-53A Rev.5 Release 5.2.0](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final) — assessment procedures và assessment plan có thể tailor.
- [NIST SP 800-37 Rev.2](https://csrc.nist.gov/pubs/sp/800/37/r2/final) — lifecycle risk management, selection, implementation, assessment, authorization và monitoring.
- [NIST SP 1301](https://csrc.nist.gov/pubs/sp/1301/final) — xây và dùng CSF Organizational Profiles.
- [NIST SP 800-128](https://csrc.nist.gov/pubs/sp/800/128/upd1/final) — security-focused configuration/change management.

### Học tiếp

1. [Security Compliance Engineering & Continuous Control Assurance](security_compliance_engineering_continuous_control_assurance.md) — obligation interpretation,
   control testing, evidence automation, issue lifecycle và audit readiness.
2. [Security Control Library & Common Control Inheritance](security_control_library_common_control_inheritance.md) — control semantics,
   common/hybrid/system-specific controls, inheritance, dependency và assurance boundary.

---

*Cập nhật lần cuối: 2026-08-03.*
