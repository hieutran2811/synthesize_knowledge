# Security Control Library & Common Control Inheritance

> Mục tiêu: xây một control library có semantics ổn định và biến common-control inheritance thành hợp đồng provider–consumer
> có scope, responsibility, evidence, failure mode và lifecycle rõ ràng—không phải tuyên bố “platform/cloud đã lo”.

---

## 1. Control library giải quyết vấn đề gì?

Control library là lớp trung gian nối risk/requirement với implementation và assurance:

```text
risk scenario / obligation / policy requirement
    → control objective
        → canonical control + parameter/profile
            → provider / system implementation
                → inherited responsibility + evidence
                    → assessment / finding / change / retirement
```

Nó giảm việc mỗi team tự diễn giải cùng outcome, triển khai cùng capability và gom cùng evidence. Giá trị không nằm ở số control
records mà ở khả năng dùng lại đúng phần, thấy gap và biết ai chịu trách nhiệm khi control thay đổi hoặc thất bại.

## 2. Library không phải bản sao framework

Framework/control catalog bên ngoài phục vụ scope và audience riêng. Internal library phải phản ánh:

- risk/business context của tổ chức;
- architecture và operating model thực tế;
- control owner/provider/consumer;
- implementation patterns đang được hỗ trợ;
- parameter/profile theo tier;
- evidence và assessment procedure;
- dependency, failure và exception lifecycle.

Copy từng dòng framework thành một “internal control” tạo duplication và mapping giả. Một internal control có thể hỗ trợ nhiều
requirements; một requirement có thể cần nhiều controls. Mapping không chứng minh equivalence hoặc effectiveness.

## 3. Vocabulary cốt lõi

| Khái niệm | Nghĩa |
|---|---|
| Control objective | Outcome kiểm soát cần đạt |
| Control | Biện pháp thay đổi likelihood/impact hoặc duy trì trạng thái |
| Implementation | Cách control tồn tại trong component/process cụ thể |
| Common control | Control được xác định, vận hành/đánh giá tập trung cho nhiều systems |
| Common-control provider | Đơn vị chịu trách nhiệm cung cấp common control |
| System-specific control | Control do một system chịu trách nhiệm hoàn toàn |
| Hybrid control | Trách nhiệm triển khai được chia giữa common và system-specific portions |
| Inheritance | System nhận một phần capability/assurance từ common control |
| Consumer | System/team dựa vào service/control được cung cấp |

Inheritance là quan hệ có điều kiện, không phải thuộc tính vĩnh viễn của control.

## 4. Operating model và decision rights

Tách vai trò:

- **Control library owner:** taxonomy, schema, quality và lifecycle của catalog.
- **Control objective/requirement owner:** semantics và intended outcome.
- **Common-control provider:** design, operation, evidence và service health.
- **Consumer/system owner:** eligibility, integration, tenant configuration và residual portion.
- **Risk owner/authorizing role:** chấp nhận residual risk trong authority.
- **Assessor:** đánh giá provider, consumer và interface với independence phù hợp.
- **Platform/service owner:** có thể là provider nhưng không mặc nhiên sở hữu business risk.

Một control record phải chỉ rõ decision nào thuộc vai trò nào; RACI chung chung không đủ cho exception, outage hoặc change khẩn cấp.

## 5. Canonical control record

Schema tối thiểu:

```yaml
id: CTRL-IAM-017
version: 3.2
title: Managed workload identity lifecycle
objective: Only authorized workloads hold valid, bounded identities
type: hybrid
owner: Identity Control Owner
provider: Platform Identity
applicability: production_workloads
parameters: [credential_ttl, approved_issuers]
dependencies: [CTRL-ASSET-003, CTRL-LOG-006]
assessment_objectives: [IAM-017.a, IAM-017.b, IAM-017.c]
status: effective
```

Thêm rationale, threat/risk links, requirement mappings, implementation statement, evidence contract, failure/exception path và
supersession. Tool IDs hoặc framework row không nên là canonical identity nội bộ.

## 6. Stable ID và versioning

ID đại diện semantics ổn định; version biểu diễn thay đổi:

- editorial: không đổi outcome/criteria;
- clarification: làm rõ scope hoặc responsibility;
- parameter/profile update;
- implementation-compatible change;
- breaking change về objective, scope hoặc consumer obligation;
- retirement/supersession.

Evidence, assessment, inheritance và exception phải reference exact version. Khi control đổi, chạy impact analysis tới consumers,
requirements, tests, findings và authorizations; không âm thầm khiến evidence cũ chứng minh control mới.

## 7. Objective trước mechanism

Ví dụ:

```text
Objective: security-relevant action attributable và reconstructable.
Control: centralized audit event collection, time normalization,
         integrity protection, retention và review/escalation.
Mechanism: agent, cloud audit API, event bus, storage tier và detection workflow.
```

Nếu đặt tên control là “cài Agent X”, library khóa vendor và bỏ qua source không dùng agent. Nếu objective quá rộng như “đảm bảo
logging an toàn”, assessor lại không có criteria. Viết outcome đủ cụ thể, đặt chi tiết thay đổi nhanh ở implementation/profile.

## 8. Implementation statement

Statement trả lời:

- component/process nào thực hiện phần nào;
- boundary, region, tenant và environment nào;
- input/precondition từ consumer;
- output/service level mà provider cam kết;
- configuration mặc định và tùy chọn;
- privileged roles và operating procedure;
- failure/degraded mode;
- evidence source và known limitation.

Không dùng “implemented by SIEM/IdP/cloud” làm statement. Tên sản phẩm không mô tả coverage, workflow hoặc hiệu quả.

## 9. Phân loại control

Control có thể được phân theo nhiều chiều:

| Chiều | Giá trị ví dụ |
|---|---|
| Responsibility | common, system-specific, hybrid |
| Function | preventive, detective, corrective, recovery |
| Layer | organization, process, platform, application, data |
| Automation | manual, automated, mixed |
| Timing | continuous, event-driven, periodic |
| Assurance | self-tested, second-line, independent |

Không suy “common = preventive” hoặc “automated = effective”. Classification giúp route ownership/assessment, không thay evaluation.

## 10. Quyết định common hay system-specific

Chọn common khi:

- outcome và implementation đủ giống giữa nhiều consumers;
- central team có authority/capability vận hành;
- service boundary và eligibility định nghĩa được;
- centralization giảm variance/cost và tăng assurance;
- failure/concentration risk có thể quản;
- evidence tái sử dụng hợp lệ.

Giữ system-specific khi context, architecture, legal boundary hoặc failure tolerance khác biệt đáng kể. Đừng centralize chỉ để dashboard
đẹp; common control kém sẽ khuếch đại lỗi tới toàn estate.

## 11. Điều kiện để gọi là common control

Một capability dùng chung chưa tự là common control. Cần:

- designated provider và accountable owner;
- documented scope/eligible population;
- control implementation/consumer obligations;
- approved operation/funding/support;
- assessment và evidence package;
- change/incident/exception process;
- dependency và service continuity;
- consumer inventory và inheritance records.

Nếu central team chỉ cung cấp library/template còn mỗi system tự triển khai/vận hành, phần lớn responsibility vẫn system-specific hoặc
hybrid—not fully inherited.

## 12. Provider service boundary

Provider mô tả boundary bằng component, data, identity, trust và operations:

```text
Provider controls:
  issuance service + signing keys + issuer policy + platform audit
Interface:
  identity request, workload metadata, token endpoint, trust bundle
Consumer controls:
  correct workload binding + audience validation + authorization + revocation response
Out of scope:
  application business authorization and unmanaged environments
```

Boundary phải khớp architecture/effective state, không chỉ org chart. Interface thường là nơi hybrid gap xuất hiện.

## 13. Consumer eligibility và applicability

Consumer chỉ inherit khi thỏa điều kiện:

- nằm trong supported environment/region/account;
- onboard đúng service/version/profile;
- dùng approved integration path;
- bật tenant-side setting bắt buộc;
- gửi inventory/metadata đầy đủ;
- không bypass provider control;
- chấp nhận support/change contract;
- evidence cho effective use còn mới.

Tách `eligible`, `onboarded`, `configured`, `effective` và `assured`. Có account trên platform không chứng minh workload đang thực sự
đi qua control path.

## 14. Inheritance contract

Record tối thiểu:

```yaml
consumer: payments-api
control: CTRL-IAM-017@3.2
provider: platform-identity
profile: tier-0-production
provider_portions: [a, b, d]
consumer_portions: [c, e]
effective_from: 2026-09-01
evidence_refs: [EV-IAM-017-P, EV-IAM-017-C]
exceptions: []
status: effective
```

Thêm scope objects, parameter values, dependency, assurance period, change notification, outage/fallback và exit path. Boolean
`inherited: true` làm mất mọi thông tin cần cho assessment và incident.

## 15. Responsibility matrix theo control portion

Ví dụ hybrid identity control:

| Control portion | Provider | Consumer | Evidence |
|---|---|---|---|
| Issuer/key protection | vận hành KMS/HSM, rotation | không export trust key | key policy/rotation test |
| Workload registration | validate metadata/service | cung cấp owner và binding đúng | registration + inventory |
| Token validation | SDK/pattern | enforce issuer/audience/expiry | negative integration test |
| Authorization | engine/capability | định nghĩa business policy | effective permissions/test |
| Revocation/incident | publish revoke event | consume, contain, reconcile | exercise/event timing |

Mỗi row phải có một accountable party cho kết quả; “shared” không được dùng để né ownership.

## 16. Partial inheritance

Một system thường chỉ inherit vài assessment objectives. Ví dụ central backup provider có thể bảo vệ storage, encryption và job
scheduling; application vẫn chịu consistency, quiesce, restore order và business validation.

Ghi inheritance ở mức control portion/objective, không ở family hoặc control title quá rộng. Assessor kết hợp provider evidence với
consumer evidence để kết luận toàn objective.

Nếu provider package không bao phủ parameter/profile của consumer, phần thiếu vẫn là system-specific gap.

## 17. Hybrid control decomposition

Decompose sao cho các portions:

- có outcome/criteria cụ thể;
- có owner/operator rõ;
- interface/input/output quan sát được;
- test độc lập được khi có thể;
- kết hợp lại thành end-to-end objective;
- không duplicate hoặc để khoảng trống.

```text
provider service health × consumer integration correctness × workflow response
    → end-to-end control effectiveness
```

Một phần bằng zero có thể làm toàn control fail; không lấy trung bình pass rate để che critical gap.

## 18. System-specific control

System-specific không có nghĩa “tùy team”. Record vẫn cần objective, implementation owner, parameter, evidence, assessment và lifecycle.
Nó có thể reuse pattern/test từ library nhưng responsibility nằm tại system.

Khi nhiều systems triển khai giống nhau, phân tích cơ hội tạo platform/common control. Khi chỉ có vài ngoại lệ context đặc thù,
đừng ép chúng vào central provider rồi tạo workaround nguy hiểm.

Library nên chỉ ra approved system-specific pattern và tiêu chí chuyển sang common.

## 19. External/SaaS common control

Supplier assurance report có thể hỗ trợ reliance nhưng không thay internal inheritance contract. Cần map:

- supplier service/boundary và report period;
- control/criteria thực sự được kiểm;
- subservice organization/carve-out;
- customer/tenant responsibility;
- exceptions/qualifications và complementary controls;
- bridge letter/change/incident notification;
- internal integration/configuration evidence;
- exit/failure strategy.

“Vendor certified” không chứng minh tenant đang dùng đúng feature hoặc workload nằm trong assessed scope.

## 20. Multi-level inheritance

Inheritance có thể qua nhiều tầng:

```text
cloud provider physical / infrastructure controls
  → enterprise landing zone controls
      → application platform controls
          → product / workload controls
```

Mỗi edge cần contract và evidence. Product không nên reference thẳng cloud certificate cho outcome thực ra phụ thuộc landing-zone và
tenant configuration ở giữa.

Giữ ultimate source và transitive path để impact analysis; tránh copy evidence qua nhiều tầng rồi mất provenance.

## 21. Baseline và profile composition

Baseline chọn control set theo impact/risk; profile/overlay bổ sung hoặc parameterize theo context:

- system criticality;
- data sensitivity/privacy;
- internet exposure;
- regulated/customer scope;
- technology/environment;
- resilience/safety requirement.

Composition phải có precedence/conflict rule và result reproducible. Baseline không xác định ai cung cấp control; inheritance mapping
được làm sau khi chọn/tailor control cho system.

## 22. Tailoring và inheritance là hai decision khác nhau

- **Tailoring:** control nào/parameter nào cần để xử lý context/risk.
- **Inheritance:** ai triển khai phần nào và system dựa vào provider nào.

Không xóa control khỏi tailored baseline chỉ vì “common provider xử lý”. Control vẫn được chọn nhưng implementation/evidence có thể
được inherit. Ngược lại, provider có capability không nghĩa control áp dụng nếu requirement/risk không yêu cầu.

Giữ hai record riêng giúp thay provider mà không làm thay đổi risk requirement một cách vô ý.

## 23. Parameter ownership

Control parameter có thể do:

- policy/requirement owner đặt organization-wide;
- profile owner đặt theo risk tier;
- provider giới hạn supported range;
- consumer chọn trong allowed range;
- risk owner phê chuẩn deviation.

Ví dụ provider hỗ trợ log retention 30–400 ngày, profile regulated yêu cầu 365 ngày, consumer cấu hình 90 ngày: service “healthy” nhưng
inheritance không đáp profile. Evidence phải ghi **effective value**, không chỉ provider capability.

Version và validate parameter ở interface provider–consumer.

## 24. Dependency graph

Control thường dựa vào control khác:

```text
privileged access review
  → complete identity inventory
  → authoritative HR lifecycle
  → asset/service ownership
  → immutable audit records
```

Graph cần loại edge: hard/soft, runtime/assurance, provider/consumer, geographic. Nếu dependency unknown hoặc stale, assurance của
downstream control phải giảm theo rule rõ.

Không tạo control graph hoàn toàn acyclic giả tạo; phát hiện cycle và quyết định cách break/assess.

## 25. Transitive assurance

Assurance không tự truyền vô hạn. Consumer chỉ rely khi:

- upstream objective tương thích;
- scope/population/period chồng khớp;
- assessment depth và independence đủ;
- evidence còn fresh và provenance giữ nguyên;
- complementary obligations đã được làm;
- finding/exception material được disclose.

Mỗi tầng thêm uncertainty. Ghi reliance limit và khi nào cần direct test. Tier-0 consumer có thể reperform một phần dù provider đã được
đánh giá để giảm concentration/independence risk.

## 26. Cycle và circular assurance

Ví dụ lỗi:

```text
asset inventory relies on logging to discover systems
logging coverage relies on asset inventory to prove completeness
```

Hai control cùng pass vì reference evidence của nhau dù chưa có independent population. Break cycle bằng authoritative source thứ ba,
reconciliation hoặc explicit limitation/unknown state.

Catalog validation nên phát hiện cycle, self-reference và evidence loop. Không phải cycle nào cũng sai về architecture, nhưng assurance
case phải giải thích cách kiểm completeness độc lập.

## 27. Common-mode failure

Một provider dùng chung tạo efficiency và concentration. Model failure:

- identity/control plane outage;
- bad policy/rule rollout;
- compromised signing/admin key;
- telemetry/evidence blind spot;
- regional/provider dependency;
- schema/API breaking change;
- operator error/insider;
- funding/capacity/support failure.

Đừng nhân số consumers rồi coi mỗi control là độc lập. Risk aggregation phải giữ shared root cause và affected critical services.

## 28. Blast radius và concentration

Provider inventory cần biết:

- consumers và criticality;
- control portions được inherit;
- region/tenant/version/profile;
- business services/downstream dependencies;
- fallback/isolation capability;
- maximum tolerable outage/degradation;
- regulatory/customer concentration.

Một common-control finding có thể là enterprise material issue. Prioritization theo affected outcome/blast radius, không chỉ severity
của provider ticket.

## 29. Outage và degraded mode

Contract quy định:

| Tình huống | Decision cần có |
|---|---|
| Provider unavailable | consumer fail-open, fail-closed hay cached state? |
| Evidence unavailable | status unknown/stale sau bao lâu? |
| Revocation channel lỗi | containment/fallback nào? |
| Region mất kết nối | local authority và reconciliation? |
| False block diện rộng | kill switch ai sở hữu, duration nào? |

Degraded mode có threat model, telemetry, hard expiry và recovery test. Service SLO availability không đủ mô tả security outcome trong
failover.

## 30. Change và notification contract

Provider phải phân loại change:

- backward-compatible feature/maintenance;
- control semantics/parameter change;
- interface/schema/API change;
- assurance/evidence source change;
- region/supplier/subprocessor change;
- emergency security change;
- deprecation/retirement.

Định nghĩa lead time, affected-consumer discovery, test environment, migration, rollback, acknowledgement và escalation. Consumer phải
thông báo change làm mất eligibility hoặc bypass control. Không chờ audit mới phát hiện inheritance đã không còn đúng.

## 31. Exception không “inherit” mặc định

Exception thuộc exact requirement/control portion, scope, owner, risk decision và period. Provider exception không tự cho phép mọi
consumer tiếp tục; impact có thể khác theo data/criticality/contract.

Khi provider có deviation:

1. xác định affected portions/consumers;
2. gửi evidence và residual gap;
3. mỗi risk/authority lane đánh giá applicability;
4. áp central và/hoặc consumer compensation;
5. track expiry/remediation/retest;
6. cập nhật assurance state.

Không đổi provider control thành `pass` chỉ vì central risk owner chấp nhận một phần exposure.

## 32. Provider-side exception

Provider request cần:

- control/version/portion và exact service scope;
- consumer inventory/blast radius;
- cause và duration;
- provider compensation;
- consumer action bắt buộc;
- legal/contract/safety impact;
- notification và acknowledgement;
- remediation/rollback/exit;
- risk authorities theo consumer tier.

Nếu không biết consumer inventory, provider không biết ai phải được thông báo—đó tự nó là governance/control deficiency.

## 33. Consumer-side exception

Consumer có thể:

- chưa onboard;
- cấu hình ngoài supported profile;
- bypass một path;
- dùng local alternative;
- không hoàn thành complementary portion.

Exception phải do consumer/risk owner quản với provider review nếu ảnh hưởng service. Provider dashboard không được báo consumer
`covered` trong thời gian deviation. Exit criteria chứng minh effective integration, backlog reconciliation và removal của bypass.

## 34. Evidence contract của provider

Provider package nên có:

```text
control/version/portions + implementation statement
eligible/onboarded/effective consumer populations
assessment period/method/depth/independence
effective parameters + configuration coverage
service health + control outcome tests
findings/exceptions/limitations
evidence provenance/freshness/access
change/incident since assessment
```

Package phải phục vụ reliance nhưng vẫn giữ least privilege/privacy. Summary conclusion cần drill-down/reperformance path cho assessor
được ủy quyền.

## 35. Evidence reuse không phải evidence copy

Để reuse hợp lệ, consumer reference immutable provider evidence/package và thêm evidence của complementary portion. Không download,
đổi tên rồi tải lại vào hàng trăm folders.

Reference cần version, scope, period, integrity và access fallback. Nếu provider package bị supersede hoặc finding mở, downstream
assurance tự cập nhật trạng thái.

Evidence reuse giảm audit effort; nó không giảm responsibility kiểm eligibility, applicability và residual gap.

## 36. Assessment inheritance và reliance

Assessor consumer quyết định mức rely theo:

- provider assessor competence/independence;
- assessment criteria/method/depth;
- period/freshness;
- population/region/profile overlap;
- sample và exclusions;
- open findings/exceptions;
- provider change sau assessment;
- criticality/concentration.

Có thể rely hoàn toàn một portion, reperform sample hoặc không rely. Ghi rationale; không buộc assessor accept package chỉ vì provider
nội bộ đã gắn “certified”.

## 37. End-to-end assurance

Control conclusion cần kết hợp:

```text
provider portion result
  + consumer complementary result
  + interface/integration test
  + dependency health
  + applicable exceptions/findings
  → system control conclusion + limitation
```

Không average percentage giữa portions. Critical objective fail hoặc unknown có thể làm toàn conclusion fail/unknown. Report vẫn giữ
granularity để remediation đúng owner.

## 38. Continuous monitoring inheritance

Provider publish control-health signals theo contract:

- current service/control version;
- population coverage;
- parameter/profile conformance;
- evidence freshness/data quality;
- test/result transition;
- outage/degraded/bypass state;
- material change/finding/incident;
- upcoming deprecation.

Consumer subscribe và map signal vào risk/assurance. “No alert received” chỉ có nghĩa healthy nếu delivery, subscription và freshness
được kiểm; heartbeat im lặng phải thành unknown.

## 39. Finding propagation

Khi provider finding xuất hiện:

```text
validate provider scope
  → traverse active inheritance edges
    → classify affected / potentially affected / not affected
      → notify + set assurance state
        → contain / compensate / risk decision
          → provider remediation + consumer retest
```

Giữ một root finding và linked consumer impacts để tránh hàng nghìn duplicate tickets, nhưng mỗi consumer vẫn có action/risk context
nếu cần. Closure provider không tự đóng consumer issue khi backlog hoặc interface state chưa được reconcile.

## 40. Remediation coordination

Provider plan có root cause, central fix, milestones, validation và rollout. Consumer plan có containment, migration/config update,
validation và local exception closure.

Điều phối:

- một source of truth cho root issue;
- affected-consumer cohort/wave;
- prioritization theo criticality;
- central support/capacity;
- pause/rollback criteria;
- evidence của provider và consumer;
- final reconciliation.

Không bắt mỗi team tự sửa cùng platform defect; cũng không chờ provider fix nếu local containment cần ngay.

## 41. Authorization và risk decision

System/risk owner được cung cấp:

- controls/portions inherit và provider;
- assurance confidence/period;
- dependencies/concentration;
- complementary responsibilities;
- open findings/exceptions;
- failure/degraded behavior;
- residual system-specific gaps.

Provider authorization/approval hỗ trợ reliance nhưng không tự authorize mọi consumer mission/business use. Significant common-control
change/failure phải trigger reassessment theo impact, không chờ annual authorization.

## 42. Consumer onboarding

Onboarding flow:

1. xác định applicable control/profile;
2. kiểm eligibility và architecture interface;
3. chấp nhận provider/consumer responsibilities;
4. configure/integrate;
5. test positive, negative, failure và evidence;
6. register scope/version/parameter;
7. activate monitoring/notification;
8. approve inheritance effective state.

Account creation hoặc agent installation chỉ là input. Exit criteria là end-to-end objective đạt với evidence và owner rõ.

## 43. Offboarding, substitution và retirement

Khi consumer rời provider hoặc control retire:

- tìm control/requirement/risk dependencies;
- xác định replacement/system-specific alternative;
- giữ overlap cần thiết nhưng có expiry;
- migrate config/data/evidence/history;
- test target và failure/rollback;
- revoke provider access/identity;
- reconcile backlog/findings/exceptions;
- đóng inheritance edge và archive decision.

Xóa consumer khỏi dashboard trước khi replacement effective tạo assurance gap. Provider retirement cần biết toàn bộ active consumers.

## 44. Machine-readable library và OSCAL

Machine-readable model hỗ trợ:

- catalog/profile cho control selection và parameterization;
- component definition cho capability/implementation;
- system plan cho system/control responsibility;
- assessment plan/results;
- POA&M/findings/remediation;
- mappings và version diff.

OSCAL cung cấp JSON/XML/YAML models cho các lớp này, nhưng schema không tự sửa semantics hoặc data quality. Bắt đầu từ canonical IDs,
ownership và lifecycle; automation sau đó giúp exchange, validation và impact analysis.

## 45. Catalog governance và quality gates

Quality gate cho control mới/thay đổi:

- objective không trùng/không mơ hồ;
- risk/requirement mappings có rationale;
- owner/provider và funding tồn tại;
- applicability/parameter/profile rõ;
- implementation và failure mode khả thi;
- assessment/evidence contract đủ;
- dependencies/cycles được review;
- exception/change/retirement path;
- consumer impact và migration plan.

Review board không cần duyệt mọi editorial change; dùng delegated authority và automated schema/graph validation.

## 46. Metrics cho library và inheritance health

| Câu hỏi | Measure gợi ý |
|---|---|
| Catalog có dùng được? | orphan/duplicate/ambiguous controls, missing owner/test |
| Inheritance có thật? | eligible→onboarded→configured→effective→assured funnel |
| Interface có gap? | complementary portion fail/unknown, integration-test rate |
| Provider có đáng tin? | coverage, freshness, finding recurrence, SLO/control outcome |
| Concentration ra sao? | critical consumers theo provider/dependency/region |
| Change có an toàn? | acknowledgement/migration, outdated versions, failed rollout |
| Exception có bền? | provider/consumer exception age, renewal, expiry breach |

Không tối ưu tỷ lệ “controls inherited”; inheritance chỉ tốt khi end-to-end outcome và accountability tốt hơn.

## 47. Ví dụ: centralized audit logging

**Objective:** security-relevant actions của production services được attributable, protected và available cho investigation.

Provider portions:

- managed ingestion, time normalization, immutable storage, provider access audit và service monitoring.

Consumer portions:

- classify required events, instrument application, preserve actor/resource context, không log secrets, monitor drop và respond finding.

```text
Provider evidence: pipeline integrity, retention profile, service health, storage access test
Consumer evidence: event coverage, semantic quality, negative secret test, end-to-end query
Interface test: synthetic action → ingest ≤ 5m → searchable with correct actor
```

Storage healthy nhưng application không emit authorization deny vẫn là hybrid-control gap.

## 48. Tình huống: provider key rotation làm hỏng consumers

Platform identity rotate trust key đúng lịch, nhưng một nhóm services cache key vô thời hạn và không xử lý key set mới:

1. provider health vẫn xanh ở issuer/key-protection portion;
2. end-to-end authentication fail ở interface/consumer portion;
3. dependency graph xác định affected version/cohort;
4. rollout pause và dual-key window có hard expiry;
5. consumer refresh behavior được fix/test;
6. library bổ sung compatibility/failure objective;
7. onboarding test mới ngăn recurrence.

Bài học: provider control pass không thể thay integration/failure-mode assurance.

## 49. Lộ trình triển khai 90 ngày

**Ngày 1–30 — Catalog và pilot provider**

- thống nhất taxonomy, schema, ID/version;
- chọn 10–20 controls quanh một common provider;
- inventory consumers, requirements và current evidence;
- decompose control portions/responsibilities;
- dựng dependency/concentration graph ban đầu.

**Ngày 31–60 — Inheritance contract**

- định nghĩa eligibility/profile/parameters;
- ký provider–consumer contract;
- test onboarding và end-to-end objectives;
- tạo provider evidence package và reliance criteria;
- nối finding/change/outage notification.

**Ngày 61–90 — Assurance và scale**

- publish health/freshness/version signals;
- diễn tập provider outage/finding/exception propagation;
- reconcile eligible→effective population;
- thiết lập quality/metrics/retirement gates;
- quyết định scale sang control/provider tiếp theo.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist production

- [ ] Internal control có stable ID/version, objective, owner, scope và parameters.
- [ ] Common control có designated provider, funding, operations và assurance package.
- [ ] Inheritance ghi exact portions, profile, consumer obligations và effective state.
- [ ] Hybrid control có interface và end-to-end test, không để “shared” mơ hồ.
- [ ] Baseline/tailoring tách biệt với provider/inheritance decision.
- [ ] Dependency graph giữ transitive path, cycle, concentration và failure mode.
- [ ] Evidence reuse bằng reference có provenance, không copy artifact hàng loạt.
- [ ] Finding/change/incident của provider propagate tới affected consumers.
- [ ] Exception provider và consumer không tự lan hoặc biến thành pass.
- [ ] Onboarding, substitution và retirement đều có reconciliation/closure evidence.

### Anti-pattern cần tránh

- Copy framework thành internal catalog không gắn risk/implementation.
- Gọi centralized tool hoặc template là common control khi chưa có provider contract.
- Boolean `inherited = true` cho toàn control/family.
- “Cloud/SaaS/platform đã lo” nhưng không kiểm tenant/complementary responsibility.
- Provider pass được dùng để bỏ integration/end-to-end test.
- Evidence bị copy qua nhiều systems đến mức mất version/provenance.
- Common-control exception được áp mặc định cho mọi consumer.
- Provider finding tạo hàng nghìn ticket rời không có root coordination.
- Availability SLO được dùng thay control-outcome/failure-mode evidence.
- Retire provider trước khi tìm và migrate hết active consumers.

### Nguồn chính thức

- [NIST SP 800-53 Rev.5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — integrated security/privacy control catalog, control functionality và assurance.
- [NIST SP 800-53B Release 5.2.0](https://csrc.nist.gov/pubs/sp/800/53/b/upd1/final) — control baselines, tailoring và overlays.
- [NIST SP 800-53A Rev.5](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final) — control assessment procedures và assessment-plan tailoring.
- [NIST SP 800-37 Rev.2](https://csrc.nist.gov/pubs/sp/800/37/r2/final) — system/common control responsibility, authorization, inheritance và continuous monitoring trong RMF.
- [NIST OSCAL](https://csrc.nist.gov/projects/open-security-controls-assessment-language) — machine-readable catalog/profile, component definition, SSP, assessment và POA&M models.

### Học tiếp

1. [Regulatory Change & Obligation Management](regulatory_change_obligation_management.md) — horizon scanning, applicability,
   interpretation governance, change impact và implementation tracking.
2. [Security Authorization & Ongoing Risk Decision Engineering](security_authorization_ongoing_risk_decision_engineering.md) — authorization boundary,
   decision package, residual risk, significant change và ongoing authorization.

---

*Cập nhật lần cuối: 2026-08-03.*
