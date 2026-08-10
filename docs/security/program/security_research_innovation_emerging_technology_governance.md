---
title: "Security Research, Innovation & Emerging Technology Governance"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 9
---
# Security Research, Innovation & Emerging Technology Governance

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: biến tín hiệu công nghệ mới thành câu hỏi nghiên cứu rõ, thử nghiệm có giới hạn và bằng chứng đủ tin cậy
> để tổ chức quyết định tiếp tục, chuyển hướng, chuyển giao, tạm dừng hoặc loại bỏ; đồng thời quản lý security,
> privacy, safety, dual-use, research integrity và nghĩa vụ vận hành trong toàn vòng đời.

---

## 1. Quản trị research và innovation là gì?

Đây là operating system cho một **engagement tạm thời nhằm giảm bất định** trước khi tổ chức cam kết scale hoặc vận hành lâu dài.
Nó trả lời năm câu hỏi:

1. Vấn đề/cơ hội nào đáng nghiên cứu?
2. Điều gì chưa biết và bằng chứng nào có thể thay đổi quyết định?
3. Làm sao thử đủ thật nhưng vẫn có giới hạn an toàn?
4. Khi nào tiếp tục, đổi hướng, chuyển giao hoặc dừng?
5. Ai chịu trách nhiệm với tài sản, dữ liệu và rủi ro sau thử nghiệm?

Innovation governance tốt không bóp nghẹt khám phá; nó làm cho khám phá **nhanh hơn, có thể kiểm chứng và có đường thoát**.

## 2. Phân biệt research, prototype, experiment, pilot và production

| Khái niệm | Mục đích chính | Câu hỏi trung tâm |
|---|---|---|
| Research | Giảm bất định nhận thức | Điều gì đúng, sai hoặc chưa biết? |
| Prototype | Thể hiện một concept kỹ thuật/tương tác | Có thể tạo ra cơ chế này không? |
| Experiment | Kiểm tra giả thuyết theo protocol | Bằng chứng có ủng hộ dự đoán không? |
| Proof of Concept | Chứng minh một khả năng hẹp | Có thể hoạt động trong điều kiện đã chọn không? |
| Pilot | Kiểm tra viability/readiness trong phạm vi thực hạn chế | Có hoạt động an toàn và hữu ích trong context đại diện không? |
| Production | Cung cấp capability được sở hữu và hỗ trợ | Có thể vận hành đáng tin cậy với accountability lâu dài không? |

PoC chứng minh “có thể chạy” không chứng minh “an toàn, ổn định, hữu ích, hợp lệ, có thể support và scale”. Đổi tên repository
từ `prototype` thành `production` không tạo production readiness.

## 3. Ranh giới với các governance khác

- **Strategy/portfolio** quyết định allocation, sequencing và option value ở cấp đầu tư.
- **Product discovery/experiment** kiểm tra user value, adoption và product economics.
- **Architecture review** đánh giá design decision, dependency và conformance.
- **Authorization/risk acceptance** cấp quyền vận hành trong một boundary xác định.
- **Research governance** quản câu hỏi, protocol, evidence, integrity, exposure và transfer của một engagement khám phá.

Một initiative có thể đi qua tất cả các hệ thống trên. Research sandbox không phải đường vòng để né policy, architecture review,
privacy review hoặc production authorization.

## 4. Vòng đời end-to-end

```text
horizon signal
  → qualify problem / opportunity
    → research question + hypothesis + unknowns
      → risk / dual-use / integrity screen
        → protocol + sandbox + evidence plan
          → execute + record deviations + evaluate
            → continue / pivot / pause / stop / transfer
              → product or production readiness
                → monitor / retire / preserve learning
```

Mỗi chuyển tiếp là decision dựa trên evidence, không phải milestone theo lịch hay buổi demo gây ấn tượng.

## 5. Nguyên tắc cốt lõi

- bắt đầu từ decision và uncertainty, không bắt đầu từ công nghệ đang “hot”;
- giả thuyết phải có khả năng bị bác bỏ;
- tăng exposure và fidelity theo từng gate;
- quyền truy cập tối thiểu, dữ liệu tối thiểu và thời hạn mặc định;
- tách technical maturity khỏi security, safety và operational readiness;
- giữ nguyên provenance, method, deviation, limitation và negative result;
- xem foreseeable misuse và dual-use ngay từ đầu;
- có human accountability, stop authority và recovery path;
- chuyển giao cả bằng chứng lẫn giới hạn, không chỉ source code;
- dừng sớm là một kết quả tốt khi evidence không ủng hộ tiếp tục.

## 6. Charter của chương trình

Charter tối thiểu nêu:

- mission, phạm vi công nghệ và loại engagement;
- research principles và protected independence;
- loại rủi ro chương trình được phép giữ;
- decision rights và escalation route;
- review tiers, gate cadence và service-level expectations;
- cách xử lý data, IP, publication, supplier và conflict;
- nguồn capacity/funding và giới hạn portfolio;
- measurement, records, retention và auditability;
- transfer, retirement và incident route.

Không dùng charter chung chung kiểu “thúc đẩy đổi mới an toàn”; cần chỉ rõ ai có thể cho phép exposure nào và ai có thể dừng.

## 7. Vai trò và decision rights

| Vai trò | Trách nhiệm chính | Không mặc định có quyền |
|---|---|---|
| Research sponsor | Business/security outcome, funding, quyết định lớn | Bỏ qua gate chuyên môn |
| Research lead | Question, protocol, evidence và integrity | Tự phê duyệt mọi exposure |
| Experiment owner | Thực thi, record và teardown | Chuyển prototype sang production |
| Security/safety/privacy reviewer | Independent challenge theo tier | Sở hữu product outcome |
| Data/IP/legal authority | Rights, use, sharing, publication route | Xác nhận technical validity |
| Receiving owner | Nhận capability, vận hành và funding | Nhận artifact thiếu readiness |
| Decision authority | Continue/pivot/stop/transfer | Sửa kết quả nghiên cứu vì áp lực |
| Program steward | Registry, portfolio, quality và learning | Là approver duy nhất mọi topic |

Ghi recusal khi reviewer có lợi ích trực tiếp về funding, vendor, publication hoặc career outcome.

## 8. Portfolio taxonomy

Phân loại giúp không áp cùng một process cho mọi việc:

- **horizon inquiry:** hiểu signal và implication;
- **fundamental research:** tạo tri thức/cơ chế mới;
- **applied research:** giải một problem đã xác định;
- **prototype exploration:** test concept hoặc interaction;
- **assurance research:** phát triển phương pháp test/measurement/control;
- **technology transfer:** chuyển kết quả cho product/platform/operations;
- **retirement/archive:** đóng option và giữ learning cần thiết.

Thêm domain, risk tier, uncertainty type, expected decision date và receiving path; đừng chỉ gắn nhãn “AI”, “quantum” hoặc “blockchain”.

## 9. Horizon scanning

Nguồn signal có thể gồm:

- incident, near miss và threat intelligence;
- research paper, standard và measurement program;
- patent, open-source ecosystem và dependency trend;
- vendor/startup/academic collaboration;
- customer/user workflow và product friction;
- regulatory/contractual change;
- capability gap trong architecture, detection hoặc recovery;
- adversary capability và economic shift.

Mỗi signal cần nguồn, ngày, confidence, affected assets/outcomes, time horizon và người triage. Feed không có qualification chỉ tạo noise.

## 10. Qualification của signal

Triage theo:

1. relevance với objective và exposure hiện có;
2. novelty: mới thật hay đổi tên concept cũ;
3. plausibility và quality của nguồn;
4. potential upside/downside và reversibility;
5. urgency: window of opportunity hoặc threat lead time;
6. khả năng tạo evidence trong cost/risk hợp lý;
7. dependency với initiative khác;
8. owner và receiving path khả thi.

Kết quả có thể là monitor, desk research, small experiment, portfolio proposal, immediate risk response hoặc close-with-rationale.

## 11. Problem statement và research question

Problem statement tốt chứa:

```text
Trong context [ai/hệ thống/workflow], [constraint hoặc failure] làm [outcome] bị ảnh hưởng.
Ta chưa biết [uncertainty]. Quyết định cần đưa ra trước [date/event] là [decision].
```

Research question phải hẹp đủ để kiểm tra. “Nghiên cứu GenAI cho security” không phải câu hỏi; “trợ lý code read-only có giúp
reviewer phát hiện secret-handling defect nhanh hơn mà không tăng insecure acceptance trong repository loại X không?” thì có.

## 12. Giả thuyết và falsifiability

Một hypothesis record nêu:

- cơ chế dự kiến;
- population/context;
- intervention và comparator;
- outcome/counter-outcome;
- threshold và time window;
- bằng chứng nào sẽ bác bỏ;
- quyết định tương ứng nếu supported, mixed hoặc rejected.

```text
Nếu A trong context B thì C cải thiện ≥ X,
trong khi guardrail D không xấu hơn Y.
Nếu không, dừng hoặc pivot theo rule Z.
```

Không viết threshold sau khi đã nhìn kết quả; đó là thay goalpost.

## 13. Unknowns, assumptions và dependencies

Dùng register sống:

| Trường | Ví dụ |
|---|---|
| Unknown | Model có giữ dữ liệu prompt ngoài boundary không? |
| Assumption | Egress policy áp dụng cho mọi execution path |
| Dependency | Vendor API, identity broker, license |
| Consequence nếu sai | Data disclosure hoặc kết quả không tái lập |
| Evidence cần | Contract + test + telemetry |
| Owner/date | Named person và decision deadline |

Ưu tiên unknown có **decision leverage** lớn, không cố trả lời mọi câu hỏi trước khi bắt đầu.

## 14. Option value và timebox

Research tạo option: học đủ để trì hoãn cam kết không thể đảo ngược. Timebox theo:

- decision date;
- evidence milestone;
- burn/risk budget;
- expiry của data/access/vendor environment;
- stop condition;
- opportunity cost của capacity.

Không gia hạn chỉ vì “đã đầu tư nhiều”. Sunk cost không phải evidence. Gia hạn cần một unknown mới có giá trị quyết định và protocol sửa rõ.

## 15. Opportunity, risk và dual-use screen ban đầu

Screen ngắn trước khi cấp environment:

- intended benefit và affected stakeholders;
- foreseeable harm/misuse;
- capability uplift cho attacker hoặc unauthorized actor;
- sensitivity của code, data, model, exploit và output;
- autonomy, scale, speed và reversibility;
- affected critical services/people;
- legal, contract, license và export-routing triggers;
- publication/release implications;
- safe minimum experiment và stop authority.

Screen không phải risk acceptance; nó chọn tier, reviewer và boundary phù hợp.

## 16. Readiness là vector, không phải một điểm

Theo dõi riêng:

```text
readiness = {
  technical, security, privacy, safety, assurance,
  operational, supply_chain, legal_contract,
  adoption, economics, exit
}
```

Một capability có thể technical-ready nhưng chưa có provenance, recovery, operator skill hoặc quyền sử dụng data. Không lấy trung bình để
che một chiều critical đang đỏ; ghi threshold theo use case và dependency giữa các chiều.

## 17. Technology Readiness Level và giới hạn

NASA dùng chín Technology Readiness Levels từ quan sát nguyên lý đến hệ thống được chứng minh trong vận hành. TRL hữu ích để nói về
**maturity kỹ thuật**, nhưng không tự chứng minh:

- secure-by-design hoặc resistance trước abuse;
- privacy, safety hay ethical acceptability;
- quality của supply chain và quyền sở hữu;
- supportability, recoverability và cost;
- fit với user/context;
- authorization để chạy trong production.

Vì vậy ghi `TRL + readiness vector`, không thay toàn bộ governance bằng một con số.

## 18. Evidence Readiness Level

Có thể dùng scale nội bộ:

| Mức | Evidence |
|---|---|
| E0 | Ý tưởng/opinion, chưa có traceable evidence |
| E1 | Literature/analysis có nguồn và assumptions |
| E2 | Offline test với synthetic artifact |
| E3 | Controlled lab, lặp lại được |
| E4 | Representative environment/data/workflow |
| E5 | Limited real exposure với guardrails |
| E6 | Repeated operational evidence qua thời gian/cohort |

Mức cao hơn không tự động tốt hơn nếu protocol kém hoặc sample thiên lệch. Evidence level mô tả context, còn quality cần đánh giá riêng.

## 19. Experiment protocol

Protocol trước khi chạy gồm:

- question, hypothesis, assumptions và decision;
- unit/population/sample và selection method;
- baseline/comparator;
- intervention, variables và confounders;
- success, failure, guardrail và stop thresholds;
- collection, analysis và uncertainty method;
- environment/data/model/tool versions;
- access, safety, incident và teardown procedure;
- publication/IP route;
- deviations và approval rule.

Pre-register phần quyết định quan trọng khi stakes cao để giảm cherry-picking.

## 20. Evidence hierarchy và triangulation

Nguồn evidence có strength khác nhau:

- expert reasoning/literature;
- static analysis hoặc formal argument;
- simulation/synthetic test;
- controlled benchmark;
- representative task test;
- adversarial evaluation;
- limited field observation;
- repeated operational outcome.

Không có hierarchy tuyệt đối cho mọi question. Triangulate nhiều phương pháp có failure mode khác nhau và ghi rõ evidence nào trả lời câu hỏi nào.

## 21. Reproducibility và replicability

Để người khác tái tạo hoặc kiểm tra:

- pin code, dependency, model, dataset và configuration;
- giữ environment manifest và seed khi phù hợp;
- mô tả preprocessing và excluded observations;
- lưu protocol, raw/derived data lineage và analysis logic;
- record tool/version/time/location có thể ảnh hưởng;
- tách secret khỏi reproducibility package;
- định nghĩa tolerance khi hệ thống nondeterministic;
- chạy independent replication cho claim quan trọng.

“Chạy được một lần trên laptop của tác giả” là anecdote, không phải transferable evidence.

## 22. Negative, null và inconclusive results

Negative result có thể loại option tốn kém và ngăn team khác lặp sai. Record:

- hypothesis không được ủng hộ;
- điều kiện, sample và power/coverage;
- instrumentation hoặc fidelity limitation;
- protocol deviation;
- alternative explanation;
- decision đã đưa ra;
- điều kiện nào cho phép mở lại.

Không ép mọi experiment tạo success story. Incentive chỉ thưởng “pilot thành công” làm hỏng research integrity.

## 23. Research integrity và conflict of interest

Giữ honesty, objectivity và traceability qua:

- protocol và research notebook/decision log;
- authorship/contribution rõ;
- không fabricate, falsify, omit hoặc plagiarize;
- công bố funding, vendor relationship và conflict;
- independent review/recusal theo stakes;
- báo deviation và adverse finding;
- phân biệt observation, inference và recommendation;
- sửa/retract artifact sai;
- route allegation an toàn và chống retaliation.

Honest error không đồng nghĩa misconduct, nhưng vẫn cần correction và learning.

## 24. Data governance cho research

Trước khi ingest data:

- purpose và lawful/authorized use;
- owner, provenance, rights/consent và classification;
- synthetic/minimized alternative;
- access scope, residency và transfer;
- labeling quality và representativeness;
- de-identification/re-identification risk;
- retention, archive và deletion proof;
- downstream training/reuse restriction;
- incident/contact route.

Dùng synthetic data trước khi tăng fidelity. “Publicly accessible” không tự động nghĩa là được phép scrape, train, publish hoặc deanonymize.

## 25. IP, license, open source và publication

Lập inventory cho code, model, data, paper, prompt, benchmark và artifact bên thứ ba. Trước khi release/chuyển giao, kiểm tra:

- ownership và contributor terms;
- open-source/data/model license compatibility;
- patent/trade-secret và contractual restriction;
- attribution và provenance;
- vulnerability/coordinated disclosure;
- dual-use/misuse amplification;
- export/sanction hoặc sector-specific routing khi áp dụng;
- redaction và reproducibility impact.

Không mặc định “mở tất cả” hoặc “giữ kín tất cả”. Chọn release boundary theo benefit, harm và authority có thẩm quyền; đây không phải tư vấn pháp lý.

## 26. Hợp tác với startup, vendor, học thuật và cộng đồng

Collaboration agreement nên nêu:

- question, deliverable và acceptance;
- background/foreground IP;
- data, access và approved environment;
- authorship/publication/review timeline;
- security incident và vulnerability disclosure;
- subcontractor/foreign collaboration route;
- model/service change notification;
- reproducibility và artifact handback;
- conflict và research independence;
- termination, deletion và continuity.

Vendor-funded benchmark không tự động vô giá trị, nhưng cần disclose funding, method, data và quyền review/publish kết quả bất lợi.

## 27. Threat modeling emerging technology

Bên cạnh asset/trust boundary, hỏi:

- capability mới trao quyền gì và cho ai;
- actor nào hưởng lợi khi tốc độ/scale/autonomy tăng;
- interface hoặc dependency mới;
- failure emergent, nondeterministic hoặc khó quan sát;
- provenance và update channel;
- training/control/data poisoning;
- prompt/input injection hoặc confused deputy;
- output được dùng làm advice, action hay authority;
- human override có thực sự hiệu lực;
- misuse sau publication/transfer;
- decommission có khả thi không.

Unknown quan trọng phải vào register, không bị ghi thành “accepted” chỉ vì chưa có dữ liệu.

## 28. Kiến trúc sandbox

Sandbox mặc định nên có:

- account/project/subscription riêng;
- identity riêng, short-lived và least privilege;
- không dùng production credential;
- network segmentation, egress allowlist và DNS logging;
- quota cho compute, storage, call và cost;
- approved artifact registry/dependency source;
- synthetic hoặc masked data;
- telemetry chống tamper phù hợp;
- expiration tự động;
- teardown script/procedure và destruction evidence.

Tên “sandbox” không tạo isolation. Boundary phải được test, kể cả route qua plugin, agent tool, browser, notebook và CI runner.

## 29. Fidelity paradox

Environment quá giả có thể cho evidence không hợp lệ; quá giống production lại tạo production-like exposure. Tăng fidelity theo gate:

```text
synthetic/offline
  → isolated lab
    → representative non-production
      → controlled real workflow
        → limited operational exposure
```

Mỗi bước ghi evidence mới cần lấy, risk tăng thêm, control, rollback và thời hạn. Không copy toàn bộ production data chỉ để demo “thật”.

## 30. Risk tier của experiment

| Tier | Exposure điển hình | Governance tối thiểu |
|---|---|---|
| T0 | Desk/offline, synthetic, reversible | Owner + protocol nhẹ |
| T1 | Sandbox, non-sensitive, không external action | Peer review + expiry |
| T2 | Representative data/user, controlled integration | Security/privacy/safety review theo trigger |
| T3 | Limited operational exposure hoặc sensitive asset | Formal gate, monitoring, rollback, authority |
| T4 | Critical/high-impact/autonomous/irreversible | Specialist review, explicit authorization, exercise và executive risk route |

Tier dựa trên consequence, autonomy, scale, sensitivity và reversibility; không dựa vào team gọi nó là “research”.

## 31. Safety, ethics và privacy review

Review theo trigger, không biến mọi experiment thành cùng một committee:

- có con người là subject/participant;
- ảnh hưởng quyền, cơ hội, sức khỏe hoặc safety;
- dùng sensitive/personal/biometric/behavioral data;
- tạo profiling, surveillance hoặc manipulation;
- nhóm dễ tổn thương hoặc power imbalance;
- deception hoặc lack of meaningful consent;
- automated decision/action có consequence lớn;
- harm khó đảo ngược hoặc phân bố không công bằng.

Review xác định mitigation, consent/notice, exclusion, appeal, monitoring và stop condition. Escalate đến authority chuyên môn/pháp lý phù hợp.

## 32. Dual-use và misuse case

Viết misuse cases song song với use cases:

- intended user dùng sai mục đích;
- outsider chiếm access;
- insider vượt scope;
- output làm tăng năng lực exploit/phishing/evasion;
- automation tăng speed/scale;
- research artifact bị recombine;
- publication tiết lộ control gap;
- model/tool drift sang capability mạnh hơn.

Treatment gồm restrict capability/audience, staged release, rate limit, monitoring, watermark/provenance khi hữu ích, coordinated disclosure,
delay/redact publication hoặc không release. Không coi disclaimer là control.

## 33. Human oversight, stop authority và kill path

Human-in-the-loop chỉ có ý nghĩa khi người đó:

- thấy context và uncertainty cần thiết;
- có thời gian và kỹ năng review;
- không bị automation bias hoặc throughput ép bỏ qua;
- có quyền từ chối/rollback;
- nhận alert đúng lúc;
- được ghi accountability rõ.

Kill path cần owner, trigger, technical mechanism, credential revocation, dependency isolation, communication và recovery. Rehearse trước T3/T4;
một nút chưa từng test không phải safety guarantee.

## 34. Adversarial evaluation và red teaming

Định nghĩa scope, authorization, target, prohibited action, data handling, safety observer, stop rule và finding route. Test có thể gồm:

- abuse/misuse cases;
- boundary escape và privilege escalation;
- prompt/input/data poisoning;
- secret/data exfiltration;
- evasion, overload và cost amplification;
- unsafe composition với tool khác;
- recovery/kill effectiveness;
- human decision under misleading output.

Red team là một nguồn evidence theo scope và thời điểm; “không tìm thấy” không chứng minh không có rủi ro.

## 35. Measurement, uncertainty và counter-metrics

Mỗi measure cần construct, unit, population, source, quality, uncertainty và decision threshold. Ghép value metric với guardrail:

| Value | Counter-metric |
|---|---|
| Task nhanh hơn | Error/insecure acceptance tăng |
| Findings nhiều hơn | False positive và review load |
| Coverage cao hơn | Blind spot hoặc representative gap |
| Automation nhiều hơn | Override/rollback thất bại |
| Cost giảm | Egress, lock-in hoặc recovery cost tăng |

Không so benchmark nếu version, prompt, dataset, hardware hoặc context khác mà không normalize/ghi limitation.

## 36. Experiment registry và provenance

Registry tối thiểu:

- ID, title, owner, sponsor, receiving candidate;
- question, hypothesis và expected decision;
- tier, reviewers và approvals;
- protocol/version/deviation;
- environment, data, code, model và supplier versions;
- start/expiry/status;
- evidence/result/uncertainty;
- incident/adverse event;
- gate decision và rationale;
- transfer/retirement/teardown proof;
- sensitivity, retention và access.

Registry là system of record cho traceability, không phải gallery marketing chỉ trưng demo thành công.

## 37. Evidence gates

Gate mẫu:

| Gate | Câu hỏi | Evidence tối thiểu |
|---|---|---|
| G0 Signal | Có đáng mở inquiry? | Source, relevance, owner |
| G1 Question | Có decision và uncertainty rõ? | Problem, hypothesis, unknowns |
| G2 Safe-to-test | Có protocol/boundary phù hợp? | Tier, sandbox, data, stop plan |
| G3 Evidence | Kết quả đủ tin cậy cho bước tiếp? | Result, limitation, deviation, counter-metrics |
| G4 Pilot | Có lý do tăng fidelity/exposure? | Readiness gaps, owner, rollback |
| G5 Transfer | Receiving system/team sẵn sàng? | Transfer package + authorization route |
| G6 Close | Đã đóng exposure và giữ learning? | Teardown, disposition, archive/decision |

Gate là quyết định có rationale. Số slide hoặc số người dự họp không phải evidence.

## 38. Continue, pivot, pause, stop và transfer

- **Continue:** question còn giá trị và evidence plan kế tiếp rõ.
- **Pivot:** evidence bác cơ chế/segment nhưng chỉ ra giả thuyết khác đáng kiểm tra.
- **Pause:** dependency/authority/data chưa sẵn sàng; có owner và revisit condition.
- **Stop:** value thấp, harm/cost cao, evidence bác bỏ hoặc không còn decision relevance.
- **Transfer:** evidence và readiness đủ để receiving owner nhận accountability.

Mỗi decision ghi rationale, dissent, conditions, expiry và residual unknowns. “Pause” không được là nghĩa địa prototype vô thời hạn.

## 39. Experiment khác pilot

Experiment ưu tiên causal learning theo protocol; pilot ưu tiên viability/readiness trong context thực hạn chế. Trước pilot cần:

- bounded user/system population;
- production-like dependency được phê duyệt;
- support và incident route;
- feature flag/ring/allowlist;
- baseline, success và abort threshold;
- informed participant/owner khi cần;
- rollback và data disposition;
- funding/timebox và receiving owner;
- quyết định scale/stop định trước.

Không gọi live customer exposure là “experiment nội bộ” để giảm governance.

## 40. Shadow, parallel và limited release

Các pattern tăng evidence mà giảm consequence:

- **shadow:** quan sát input nhưng output không tác động quyết định;
- **parallel:** capability mới chạy cạnh cơ chế cũ để so sánh;
- **recommend-only:** tạo đề xuất, con người quyết định;
- **read-only:** không sửa state;
- **canary/ring:** population nhỏ, tăng dần;
- **synthetic replay:** phát lại workload đã sanitize;
- **time-bound allowlist:** chỉ identity/workflow định trước.

Vẫn cần bảo vệ input/output, vì shadow system có thể làm rò data hoặc gây cost dù không thay production state.

## 41. Transition package

Không chuyển chỉ repository. Package gồm:

- problem, intended use/non-use và stakeholder;
- hypothesis, evidence, negative result và limitation;
- architecture, threat model và trust boundary;
- code/artifact/data/model/version/provenance;
- tests, benchmark và reproducibility instructions;
- controls, unresolved findings và residual unknowns;
- supplier, license, IP và contract dependencies;
- operating cost/capacity assumption;
- SLO, telemetry, support, incident, recovery và kill path;
- owner, funding, skill và maintenance plan;
- migration, compatibility, exit và data disposition;
- approvals/authorization còn cần.

Receiving owner ký nhận accountability và gaps, không chỉ xác nhận đã tải file.

## 42. Technology transfer và receiving-team readiness

Đánh giá đội nhận:

- có mandate, product/service fit và funded roadmap;
- hiểu mechanism và limitation;
- có maintainer/operator/security skill;
- tái tạo được result độc lập;
- biết monitor, troubleshoot và rollback;
- sở hữu dependency/vendor relationship;
- có authority để dùng data/capability;
- chấp nhận technical debt và residual risk theo đúng route;
- có timeline hardening hoặc productionization.

Researcher pair/coaching trong thời gian hữu hạn; không “ném prototype qua tường” rồi tiếp tục là hidden operator.

## 43. Operational, incident và recovery readiness

Trước operational exposure, xác nhận:

- service owner/on-call/support channel;
- inventory, ownership và dependency mapping;
- SLO/capacity/cost limit;
- logs, alerts, triage và evidence retention;
- incident classification và contact;
- isolation/revocation/kill procedure;
- backup/restore hoặc rebuild path;
- business fallback/manual mode;
- supplier outage/change response;
- exercise theo failure mode quan trọng.

Nếu recovery chỉ là “gọi researcher”, capability chưa được transfer.

## 44. Assurance và authorization boundary

Research evidence có thể hỗ trợ assurance nhưng không tự cấp quyền production. Decision package phải nói rõ:

- claim nào đã được kiểm tra;
- scope, environment và time của evidence;
- control nào chỉ tồn tại trong sandbox;
- inherited/shared control dependency;
- gap khi chuyển sang production;
- independent evidence và limitation;
- risk owner/authorizing authority;
- condition, expiry và re-evaluation trigger.

Demo thành công không thay security assessment, privacy impact route hoặc authorization khi các cơ chế đó được yêu cầu.

## 45. Monitoring sau chuyển giao

Theo dõi drift của:

- use case, user và scale;
- data/source/distribution;
- model/firmware/library/vendor service;
- threat/misuse pattern;
- control và dependency;
- operator behavior/override;
- cost/latency/reliability;
- legal/license/contract condition;
- outcome và counter-metric.

Định nghĩa trigger quay lại research, product discovery, architecture review hoặc reauthorization. Evidence cũ không tự hợp lệ cho version/context mới.

## 46. Retirement và decommission

Close engagement cần **negative proof** rằng exposure đã biến mất:

- compute/project/account/resource bị hủy;
- credential/token/certificate/access bị revoke;
- data, copy, snapshot, log và backup được disposition;
- vendor/subscription/collaborator offboard;
- DNS/endpoint/integration/allowlist bị gỡ;
- artifact archive/quarantine/delete theo policy;
- vulnerability/disclosure/action được chuyển owner;
- decision, learning và reopen condition được giữ;
- owner xác nhận teardown evidence.

Prototype không owner nhưng còn credential, public endpoint hoặc sensitive data là attack surface, không phải “innovation backlog”.

## 47. Portfolio capacity, funding và economics

Giữ capacity theo horizon:

- small bets cho signal/desk research;
- bounded applied experiments;
- ít high-fidelity pilots hơn;
- reserved capacity cho replication, safety review và teardown;
- transfer funding từ trước, không xin sau demo;
- kill weak options để tái đầu tư vào evidence tốt hơn.

Xem expected learning, decision leverage, option value, downside exposure, reversibility và receiving capacity. Không tối ưu số PoC; quá nhiều
prototype không được transfer tạo inventory, dependency và trust debt.

## 48. Metrics và counter-metrics cấp chương trình

Nên đo:

- time từ signal đến qualified decision;
- hypothesis resolution và evidence quality;
- evidence gained trên cost/risk/time;
- tỷ lệ stop/pivot đúng lúc;
- replication/reuse của method/artifact;
- transfer readiness và outcome sau transfer;
- orphan prototype/aged pause;
- teardown đúng hạn;
- incident, data/IP leak và integrity issue;
- reviewer/receiving-team capacity;
- distribution của investment theo risk/horizon.

Tránh dùng số ý tưởng, paper, patent, demo, PoC hoặc budget spent như success metric độc lập. Ghép tốc độ với adverse event và evidence quality.

## 49. Ví dụ: thử nghiệm AI coding assistant hoặc security agent

**Decision:** có nên cho một cohort dùng agent để đề xuất bản vá security trong repository loại A không?

**Giả thuyết:** agent read-only giảm median time-to-first-valid-fix ít nhất 25%, trong khi tỷ lệ insecure suggestion được reviewer chấp nhận
không tăng quá threshold đã định.

**Bắt đầu có giới hạn:**

- repository synthetic hoặc nội bộ đã sanitize;
- không production secret, không customer data;
- agent read-only/recommend-only, không merge/deploy;
- tool/egress/repository allowlist và per-run identity;
- pin model, prompt, dependency và record provenance;
- human reviewer có checklist và quyền reject;
- quota, kill switch và expiry.

**Threat/misuse test:** prompt injection trong code/comment, secret exfiltration, malicious dependency, license/provenance ambiguity,
unsafe command, hallucinated API, review automation bias và vendor/model drift.

**Tăng fidelity theo gate:** offline benchmark → sandbox patch → human-reviewed pull request ở cohort nhỏ → limited operational workflow.
Mỗi bước phải giữ comparator, counter-metrics, rollback và data-use boundary.

**Quyết định:** transfer chỉ khi evidence lặp lại, receiving owner vận hành được, supply-chain/IP/data route rõ và kill/recovery đã test;
nếu productivity tăng nhưng insecure acceptance hoặc review load vượt guardrail thì pivot/stop, không che bằng điểm trung bình.

## 50. Kế hoạch 90 ngày, checklist, anti-pattern và nguồn

### Ngày 1–30: boundary và portfolio baseline

- inventory research, prototype, sandbox, data, credential và owner hiện có;
- chọn 1–2 decision quan trọng, không mở chương trình toàn công ty;
- viết charter, roles, tier, gate và integrity rules;
- thiết lập experiment registry và unknowns template;
- baseline time-to-decision, orphan prototype và teardown state;
- thiết kế sandbox tối thiểu với expiry và destruction evidence.

### Ngày 31–60: chạy bounded experiment

- viết hypothesis/protocol trước execution;
- hoàn tất risk, dual-use, data/IP và reviewer routing;
- chạy T0/T1 trước, tăng fidelity chỉ khi evidence cần;
- record provenance, deviations, negative result và uncertainty;
- tổ chức evidence gate với continue/pivot/pause/stop rõ;
- chọn receiving owner sớm và lập readiness vector.

### Ngày 61–90: chứng minh decision quality

- replicate claim material hoặc peer review độc lập;
- thử rollback/kill/teardown;
- tạo transfer package cho initiative đủ điều kiện;
- đóng/revoke/delete các prototype không còn giá trị;
- đo time-to-decision, evidence quality và counter-metrics;
- review incentive/capacity, rồi quyết định scale, sửa hoặc giữ hẹp.

### Checklist production

- [ ] Có decision, question, hypothesis, unknowns và falsification rule.
- [ ] Research/prototype/experiment/pilot/production được phân biệt rõ.
- [ ] Tier, sandbox, data, dual-use, safety và stop authority phù hợp.
- [ ] Technical maturity không bị dùng thay readiness vector.
- [ ] Protocol, version, provenance, deviation, uncertainty và negative result được giữ.
- [ ] Gate tạo continue/pivot/pause/stop/transfer decision có rationale.
- [ ] Pilot có support, monitoring, rollback và receiving owner.
- [ ] Transfer package chứa evidence lẫn limitation và operating obligations.
- [ ] Production exposure đi qua assurance/authorization cần thiết.
- [ ] Retirement revoke access, disposition data và chứng minh teardown.

### Anti-pattern cần tránh

- Innovation sandbox bị coi là governance-free zone.
- Bắt đầu bằng vendor/tool rồi đi tìm problem để biện minh.
- PoC chạy một lần được quảng bá là production-ready.
- TRL cao bị hiểu thành secure, safe hoặc operable.
- Chỉ công bố positive result; đổi threshold sau khi thấy data.
- Copy production data/credential để tăng realism quá sớm.
- “Human-in-the-loop” nhưng người review không có context, thời gian hoặc quyền dừng.
- Red team không thấy lỗi bị dùng như guarantee.
- Research team vận hành prototype vô thời hạn vì không có receiving owner.
- Pause không expiry; resource, access và vendor subscription không được đóng.
- Đo số demo/PoC/patent thay vì evidence và decision quality.

### Nguồn chính thức

- [NIST Securing Emerging Technologies](https://www.nist.gov/securing-emerging-technologies) — emerging technology tạo cả cơ hội
  và cybersecurity/privacy considerations mới; risk management cần context và collaboration.
- [NIST SP 800-160 Vol. 1 Rev. 1](https://csrc.nist.gov/pubs/sp/800/160/v1/r1/final) — systems security engineering,
  stakeholder protection needs, assurance và trustworthiness xuyên lifecycle.
- [NASA Technology Readiness Levels](https://www.nasa.gov/directorates/somd/space-communications-navigation-program/technology-readiness-levels/) —
  thang chín mức đánh giá technical maturity; chương này chủ động bổ sung các chiều readiness khác.
- [NIST Scientific Integrity Program](https://www.nist.gov/adlp/research-protections-office/nist-scientific-integrity-program) —
  honesty, objectivity, ethical conduct, reproducibility, quality và responsible communication of research.
- [NIST Research Security Office](https://www.nist.gov/adlp/research-security-office) — cách tiếp cận risk-based nhằm cân bằng
  open scientific collaboration với bảo vệ research và intellectual property.
- [NIST SP 800-218A](https://csrc.nist.gov/pubs/sp/800/218/a/final) — practices bổ sung cho generative AI và
  dual-use foundation models xuyên secure-development lifecycle.
- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework) và
  [NIST AI TEVV](https://www.nist.gov/ai-test-evaluation-validation-and-verification-tevv) — quản AI risk theo context,
  measurement và test/evaluation/verification/validation có thể lặp lại.
- [NIST SP 800-55 Vol. 1](https://csrc.nist.gov/pubs/sp/800/55/v1/final) — chọn, phát triển và đánh giá
  security measures cùng data quality và uncertainty.

### Học tiếp

1. [Security Capability Academies, Mentoring & Technical Career Development](security_capability_academies_mentoring_technical_career_development.md) — xây learning architecture,
   deliberate practice, mentoring, progression và capability pipeline bền vững.
2. [Security Talent Acquisition, Workforce Analytics & Succession Resilience](security_talent_acquisition_workforce_analytics_succession_resilience.md) — demand/capacity modeling,
   critical-role coverage, hiring signal, mobility và succession risk.

---

*Cập nhật lần cuối: 2026-08-03.*
