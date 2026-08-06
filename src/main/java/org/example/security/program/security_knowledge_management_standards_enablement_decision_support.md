# Security Knowledge Management, Standards Enablement & Decision Support

> Mục tiêu: biến policy, standard, pattern, runbook, decision record và kinh nghiệm chuyên gia thành một
> knowledge system có thẩm quyền, dễ tìm, đúng ngữ cảnh, có vòng đời và đo được khả năng giúp người dùng
> ra quyết định hoặc hoàn thành security task đúng—không chỉ tạo thêm trang tài liệu.

---

## 1. Security knowledge là decision infrastructure

Knowledge management không phải dự án “gom mọi tài liệu vào một portal”. Nó xây hạ tầng để người dùng:

- tìm đúng câu trả lời tại thời điểm cần;
- biết câu trả lời nào có thẩm quyền và còn hiệu lực;
- hiểu nó áp dụng cho context nào;
- thực hiện hoặc ra quyết định đúng;
- chuyển sang expert/authority khi tình huống vượt boundary;
- phản hồi learning về standard, pattern, product và service.

Page view là output. Quyết định và hành động đúng mới là outcome.

## 2. Ranh giới với policy, training và service management

| Hệ thống | Trả lời câu hỏi chính |
|---|---|
| Policy/standards | Điều gì bắt buộc, với authority và exception nào? |
| Knowledge management | Làm sao tìm, hiểu và áp dụng đúng tri thức đó? |
| Learning/training | Con người cần phát triển knowledge/skill nào để làm task? |
| Service management | Outcome/support nào được cung cấp và vận hành ra sao? |
| Product management | Problem/value/adoption nào cần tối ưu? |

FAQ hoặc hướng dẫn không được âm thầm thay đổi nghĩa của standard. Knowledge layer giải thích và enable, không tự tạo authority.

## 3. Explicit, tacit và embedded knowledge

- **Explicit:** policy, guide, ADR, checklist, runbook, code example.
- **Tacit:** kinh nghiệm nhận biết edge case, trade-off và failure signal của chuyên gia.
- **Embedded:** validation rule, template, safe default, workflow hoặc automated guardrail.

Mục tiêu không phải biến mọi tacit knowledge thành prose. Phần ổn định/lặp lại nên được codify; phần phụ thuộc judgment
nên có decision aid, examples và expert route; phần deterministic nên được nhúng vào product/platform.

## 4. Knowledge lifecycle

```text
need / signal
  → discover existing knowledge
    → author / synthesize
      → technical + authority review
        → publish / distribute / embed
          → use / feedback / measure
            → update / supersede / archive / dispose
```

Publication không phải đích cuối. Owner, review trigger, replacement và retirement path phải có ngay từ khi tạo artifact.

## 5. Knowledge domain map

Lập bản đồ theo decisions/tasks thay vì theo org chart:

- design và build an toàn;
- identity/access decisions;
- data handling;
- vulnerability/remediation;
- detection/incident/recovery;
- third-party/risk/exception;
- assurance/evidence;
- operational changes.

Với mỗi domain, map authoritative sources, owners, audiences, top tasks, high-risk decisions, knowledge gaps và duplicate/conflicting content.

## 6. Bắt đầu từ decision hoặc task

Knowledge need có thể viết như sau:

```text
Khi [trigger/context], [role] cần [decide/do]
để đạt [outcome], nhưng đang thiếu [information/judgment/tooling].
Sai lầm có thể gây [consequence]; tín hiệu hiện tại là [evidence].
```

“Cần viết trang encryption” quá rộng. “Developer cần chọn cách lưu Restricted Data cho batch job trước design review”
tạo được content boundary, audience và success test.

## 7. Segment audience theo context

Không dùng một bài dài cho tất cả:

- novice cần concept, guided path và examples;
- experienced practitioner cần reference, parameters và change notes;
- approver cần criteria, evidence và authority boundary;
- operator cần signal, steps, failure/recovery branch;
- auditor/assessor cần version, provenance và effective-state evidence;
- emergency responder cần compressed, offline-capable path.

Role title không đủ; segment thêm technology, risk tier, frequency và urgency.

## 8. Question inventory và top tasks

Thu thập câu hỏi từ:

- search queries có/không có result;
- support/request/exception records;
- architecture reviews và repeated comments;
- incident/near-miss/postmortem;
- onboarding observation;
- audit findings và evidence rework;
- community/office-hour questions;
- deprecated page traffic.

Chuẩn hóa câu hỏi theo job/context/outcome, rồi ưu tiên theo frequency × consequence × addressable share.

## 9. Canonical source và source of truth

Mỗi claim có authority phải trỏ tới canonical source. Canonical không có nghĩa mọi nội dung nằm trong một tool:

- standard có repository/version riêng;
- runbook có operational repository;
- code pattern có source repository và tests;
- decision record có register phù hợp;
- portal/search index chỉ tạo discovery layer.

Copy có thể dùng cho point-of-need nhưng phải có source ID/version, update mechanism và visible provenance.

## 10. Authority model

Tách trách nhiệm:

| Vai trò | Trách nhiệm |
|---|---|
| Domain/standard owner | Nghĩa chuẩn tắc, applicability, interpretation |
| Knowledge owner | Outcome, audience, coverage và lifecycle của knowledge set |
| Author/SME | Nội dung và technical accuracy |
| Content designer/editor | Structure, language, usability, accessibility |
| Repository custodian | Workflow, metadata, access, retention |
| Consumer representative | Validates task fit và comprehension |

SME review không thay user validation; editor cũng không tự quyết normative meaning.

## 11. Content states và trust signals

Một state model thực dụng:

```text
draft → in review → approved/published → under change
      → superseded → archived → disposed
```

Trang hiển thị rõ:

- status và authority level;
- owner/contact;
- applicable scope/version;
- effective/review/expiry dates;
- last verified evidence;
- replacement/change summary;
- classification.

“Last updated hôm qua” không chứng minh content đúng hoặc được authority phê duyệt.

## 12. Artifact taxonomy

| Artifact | Công dụng | Không dùng để |
|---|---|---|
| Policy/standard | Requirement có authority | Hướng dẫn mọi implementation detail |
| Explanation | Tạo mental model và rationale | Thêm requirement mới |
| How-to | Hoàn thành một goal cụ thể | Dạy toàn bộ domain |
| Reference | Tra chính xác parameter/API/criteria | Dẫn novice theo journey |
| Tutorial | Học có hướng dẫn trong safe context | Là production procedure |
| Pattern | Cách giải quyết lặp lại có limits | Ép mọi case dùng một vendor |
| Runbook/playbook | Vận hành/ứng phó theo trigger | Thay authority/risk decision |
| Decision aid | Route bounded choices | Tự xử lý ambiguity ngoài scope |
| FAQ | Trả câu hỏi lặp lại | Vá mâu thuẫn policy |

Một artifact có một primary job; link tới loại khác thay vì trộn thành “mega page”.

## 13. Content contract và metadata

Metadata tối thiểu có thể là:

```yaml
id: SEC-KNOW-IAM-027
title: Chọn workload identity pattern
artifact_type: decision-aid
audience: application-engineer
job: select-workload-authentication
authority: guidance
normative_sources: [SEC-IAM-STD-014@3.1]
applies_to: [managed-cloud, production]
owner: Identity Platform
status: effective
review_by: 2026-11-01
supersedes: SEC-KNOW-IAM-019@2
sensitivity: internal
```

Thêm prerequisites, expected outcome, limitations, related service, feedback route và machine-readable tags.

## 14. Atomicity và context

Content quá lớn khó tìm/update; fragment quá nhỏ mất rationale và applicability. Tách ở nơi có:

- một primary user need;
- owner/lifecycle riêng;
- khả năng reuse thật;
- stable meaning ngoài page cha.

Mỗi fragment vẫn cần context envelope: dành cho ai, dùng khi nào, không dùng khi nào, source và bước tiếp theo. Không trả
một đoạn search snippet có vẻ đúng nhưng thiếu boundary quyết định.

## 15. Taxonomy, ontology và glossary

- **Taxonomy:** phân loại theo controlled dimensions như domain, task, artifact, risk tier.
- **Ontology/relationship model:** biểu diễn `implements`, `explains`, `supersedes`, `applies-to`, `evidences`, `owned-by`.
- **Glossary:** định nghĩa canonical term, alias, deprecated term và scope.

Không tạo taxonomy chỉ từ cấu trúc folder. Dùng vocabulary của user làm synonyms nhưng giữ canonical semantics cho automation và assurance.

## 16. Naming và search vocabulary

Title nên dùng verb/task và object người dùng nhận biết:

- tốt: “Xoay credential production khi key bị lộ”;
- yếu: “KMS Operations Standard Annex B”;
- tốt: “Kiểm tra SaaS có được phép xử lý Restricted Data không”;
- yếu: “TPRM-DSA Knowledge Hub”.

Thu synonyms, acronyms, misspellings, legacy product names và câu hỏi tự nhiên. Không đổi canonical term chỉ để tăng search hit;
map alias và giải thích meaning.

## 17. Information architecture

Cho phép nhiều entry path nhưng một meaning:

```text
task / journey
  ├─ quick answer / decision aid
  ├─ implementation guide / pattern
  ├─ normative source
  ├─ evidence / verification
  └─ support / expert / exception route
```

Navigation theo task, topic và audience; tránh bắt user biết security team nào sở hữu câu hỏi. Breadcrumb và related links
phải phản ánh conceptual relationship, không chỉ folder lân cận.

## 18. Findability là một outcome

Đo ít nhất:

- search success và zero-result rate;
- reformulation rate;
- click position/time-to-first-useful-result;
- pogo-sticking/backtracking;
- task completion sau search;
- escalation sau khi đọc;
- outdated content được search/click;
- segment/query coverage.

Search click không chứng minh answer hữu ích. Test bằng realistic questions và quan sát người dùng chọn, hiểu, hành động.

## 19. Federated repositories, unified discovery

Ép mọi artifact vào một repository thường phá workflow của operator/developer. Mô hình federated phù hợp khi có:

- canonical identity/URL và ownership;
- common metadata/schema tối thiểu;
- index/search aggregation;
- access/classification enforcement;
- link/dependency validation;
- freshness/status propagation;
- archive/retention rules.

Portal là cửa vào, không nhất thiết là nơi sở hữu nội dung. Không index secret hoặc restricted incident data vượt audience.

## 20. Content supply chain

Xem knowledge như supply chain:

```text
authoritative inputs → synthesis → review → build/render
→ publish/index → cache/copy → consume/embed → feedback
```

Threats gồm source giả, unauthorized edit, stale cache, broken build, poisoned example, lost provenance và oversharing.
Áp access control, peer review, signed/tagged release khi phù hợp, dependency scan, link test, audit trail và rollback.

## 21. Authoring workflow

Workflow nhẹ nhưng explicit:

1. xác nhận user need và không có content phù hợp;
2. assign owner, authority level và source set;
3. chọn artifact type/template;
4. draft cùng SME và content designer;
5. test technical correctness, comprehension và task completion;
6. approve/publish/index/distribute;
7. theo dõi usage/outcome và review triggers;
8. update, merge hoặc retire.

Không yêu cầu committee approval cho typo; change class quyết định review depth.

## 22. Technical review và independent verification

Reviewer kiểm tra:

- source/provenance và version;
- applicability/boundary;
- command/code/config correctness;
- security failure modes;
- examples và non-examples;
- rollback/recovery;
- conflict với standard khác;
- sensitive information exposure.

Với high-risk runbook, người không phải author nên thực hành trên safe environment. “SME đã đọc” yếu hơn observed successful execution.

## 23. Interpretation boundary

Khi content chạm legal, regulatory, policy hoặc risk meaning:

- quote/reference exact authoritative source và version;
- tách fact, interpretation, recommendation và decision;
- nêu jurisdiction/scope/assumptions;
- route novel/material ambiguity tới đúng authority;
- ghi interpretation decision và precedent;
- không dùng chatbot/FAQ làm final authority.

Knowledge team tổ chức và truyền đạt interpretation đã được quyết; không tự tạo nghĩa mới.

## 24. Viết để hành động được

Nguyên tắc:

- đặt outcome và applicability trước background;
- dùng câu ngắn, chủ thể và động từ rõ;
- một step chứa một action chính;
- nói chính xác input/output/evidence;
- giải thích acronym lần đầu;
- dùng từ nhất quán với UI/API/standard;
- đặt warning trước irreversible action;
- tách mandatory, recommended và example.

Plain language không có nghĩa xóa technical precision; nó loại bỏ complexity không cần thiết.

## 25. Progressive disclosure

Hiển thị theo nhu cầu:

1. quick answer và boundary;
2. decision/steps chính;
3. edge cases và failure handling;
4. rationale/deep reference;
5. normative source và evidence details.

Novice không bị nhấn chìm; expert vẫn tra cứu sâu. Safety-critical caveat không được giấu trong accordion cuối trang.

## 26. Example, non-example và boundary case

Một guidance mạnh có:

- example đúng với realistic context;
- non-example chỉ ra lỗi phổ biến;
- boundary case cần judgment;
- expected output/evidence;
- failure/recovery example;
- versioned/tested code nếu có.

Redact/tokenize dữ liệu nhạy cảm và dùng synthetic identifiers. Code snippet copy-paste được phải đi qua test/security review như code production.

## 27. Decision tables

Decision table phù hợp khi criteria bounded:

| Data | Exposure | Provider state | Kết quả |
|---|---|---|---|
| Public | Public | Approved | Standard path |
| Internal | Workforce-only | Approved | Standard path + access settings |
| Restricted | Any | Approved for Restricted | Enhanced path + evidence |
| Restricted | Any | Chưa được đánh giá | Specialist review; không tự approve |

Ghi priority khi rules overlap, unknown behavior và authority/source của mỗi kết quả.

## 28. Checklist và decision tree

Checklist hỗ trợ memory trong task đã hiểu; decision tree route nhánh theo answer. Cả hai cần:

- entry/exit criteria;
- observable questions;
- unknown/not-applicable branch;
- stop/escalate condition;
- evidence captured;
- version và source;
- usability test.

Checklist không thay skill hoặc judgment. Nếu user tick tất cả nhưng vẫn dễ đạt outcome sai, thiết kế lại artifact/workflow.

## 29. Executable decision support

Nhúng knowledge vào form, CLI, IDE, pipeline hoặc portal khi logic bounded:

- prefill authoritative context có provenance;
- hỏi progressive questions;
- validate input và incompatible choices;
- trả outcome + rationale + source/version;
- sinh evidence;
- cho review/appeal/exception;
- log rule path và unknown state;
- rollback khi rule/content lỗi.

Automation không biến guidance thành requirement. Authority của rule phải trace về policy/standard hoặc delegated decision.

## 30. Khi nào phải route tới expert

Escalate khi:

- context không nằm trong applicability;
- material ambiguity hoặc conflict;
- novel threat/technology;
- irreversible/high-impact action;
- exception hoặc risk acceptance;
- sensitive/legal/personnel matter;
- evidence không đủ hoặc data quality thấp;
- automated aid trả unknown.

Route nêu đúng service, required inputs, expected response và emergency alternative—không chỉ “contact security”.

## 31. Expert routing và office hours

Thiết kế mạng chuyên gia:

- domain/on-call directory theo decision type;
- consultation office hours cho exploratory questions;
- formal service cho accountable output;
- emergency escalation riêng;
- triage/routing và handoff contract;
- record/reuse recurring sanitized answers;
- workload, backup và succession visibility.

Office hours không nên trở thành hidden approval channel hoặc phụ thuộc một “hero”.

## 32. Community of practice

Community giúp lưu chuyển learning hai chiều:

- practitioners chia sẻ local patterns/failures;
- domain owners giải thích change và thu gaps;
- reviewers curate candidate knowledge;
- maintainers recruit contributors;
- product/platform teams nhận adoption feedback.

Community content mặc định là peer knowledge, chưa phải authoritative. Badge/status và moderation tránh lời khuyên phổ biến bị nhầm thành standard.

## 33. Capture tacit knowledge có chọn lọc

Dùng:

- paired execution/shadowing;
- expert walkthrough theo case thật;
- cognitive interview: tín hiệu nào làm chuyên gia đổi hướng;
- case library gồm context, options, decision, rationale, outcome;
- pre-mortem và failure rehearsal;
- succession/handover sessions có task demonstration.

Đừng chỉ quay video dài. Trích decision cues, boundaries, failure patterns và tạo artifact có owner/lifecycle.

## 34. Incident và near-miss learning

Sau incident, phân loại learning thành:

- standard/control gap;
- product/default gap;
- detection/runbook gap;
- knowledge/findability/comprehension gap;
- skill/practice gap;
- authority/coordination gap.

Chuyển mỗi item tới đúng backlog/owner. Update runbook trước khi đóng action; rehearsal kiểm tra thay đổi. Không đổ mọi nguyên nhân
thành “nhắc lại awareness”.

## 35. Decision records là organizational memory

Knowledge layer giúp tìm precedent nhưng giữ context:

- decision, date, authority và status;
- scope và facts tại thời điểm đó;
- options/rationale/assumptions;
- conditions/expiry/revisit trigger;
- linked standard/exception/evidence;
- superseding decision.

Precedent không tự động áp dụng cho case mới. Decision aid phải hỏi liệu material facts và authority boundary còn tương đương.

## 36. Knowledge debt

Debt gồm:

- duplicate/conflicting answers;
- orphan content không owner;
- obsolete versions vẫn được search;
- broken links/examples;
- tacit dependency vào một người;
- missing edge/failure path;
- unreadable mega pages;
- content copy không update;
- rule/document drift.

Ưu tiên debt theo probability of use × consequence of wrong use × exposure duration, không chỉ theo số trang cũ.

## 37. Freshness và review triggers

Cadence review là fallback. Event triggers mạnh hơn:

- normative source/version đổi;
- product/API/UI đổi;
- incident, control failure hoặc near-miss;
- search/support/exception pattern mới;
- owner/team/supplier đổi;
- regulation/threat/context đổi;
- dependency bị deprecated;
- negative feedback hoặc task failure.

High-volatility artifact có review interval ngắn hơn. Review phải xác minh behavior thực tế, không chỉ bấm “still current”.

## 38. Version, supersession và retirement

Change note nói rõ:

- điều gì đổi và vì sao;
- ai bị ảnh hưởng;
- effective/transition dates;
- action/migration cần làm;
- compatibility và exception effect;
- replacement/source version.

Retired content nên redirect hoặc hiện banner rõ tùy record obligation. Xóa khỏi search/index/cache, sửa inbound links và giữ archive
theo retention. Old URL không được silently phục vụ answer mới với nghĩa khác.

## 39. Accessibility, localization và multi-channel

Thiết kế:

- heading/landmark/link text có nghĩa;
- keyboard và assistive technology;
- không dựa riêng vào màu/hover/image;
- language được khai báo, term nhất quán;
- plain text/offline/printable emergency path;
- translation có owner, source version và lag status;
- time-zone/low-bandwidth access;
- code/table có alternative dễ hiểu.

Bản dịch hết hạn phải visible; không để localized content trông authoritative hơn source đã đổi.

## 40. Sensitivity, privacy và records management

Không phải knowledge nào cũng nên searchable rộng. Phân loại:

- public/general guidance;
- internal implementation detail;
- restricted vulnerabilities, detections, incident/personnel/legal data;
- secrets không bao giờ nằm trong knowledge article.

Áp need-to-know, redaction, audit, retention/legal hold và secure disposal. Search index, snippets, analytics và AI embeddings đều có thể
làm lộ content dù repository gốc có ACL.

## 41. AI/RAG trong knowledge system

AI có thể hỗ trợ query expansion, summary, draft, translation và retrieval; không tự trở thành authority. Rủi ro gồm:

- confabulation và fabricated citation;
- trả đúng đoạn nhưng sai scope/version;
- prompt/content poisoning;
- leakage qua index/log/context;
- over-reliance và automation bias;
- non-deterministic answer;
- không hiểu exception hoặc authority boundary.

High-impact answer cần grounded source links, visible status/version, abstain/escalate behavior và human confirmation phù hợp.

## 42. Đánh giá retrieval và generated answers

Tạo evaluation set từ realistic questions, gồm:

- common task;
- ambiguous query;
- outdated terminology;
- restricted/unanswerable question;
- conflicting sources;
- edge case cần expert;
- recent change;
- adversarial/poisoned content.

Đo retrieval recall/precision, source authority/freshness, groundedness, citation correctness, scope correctness, abstention và task outcome.
Test lại khi model, index, chunking, access policy hoặc source đổi.

## 43. Knowledge quality dimensions

| Dimension | Câu hỏi kiểm tra |
|---|---|
| Accuracy | Claim có đúng với source và behavior thật? |
| Authority | Ai có quyền xác nhận nghĩa/quyết định? |
| Applicability | Scope, audience, prerequisite và limits rõ? |
| Currency | Source/dependency/status còn hiệu lực? |
| Completeness | Happy, failure, recovery, escalation paths đủ? |
| Consistency | Term/rule/link không mâu thuẫn? |
| Usability | User tìm, hiểu và hoàn thành task được? |
| Accessibility | Nhiều khả năng/thiết bị/channel dùng được? |
| Traceability | Source/version/decision/evidence truy ngược được? |
| Safety | Không làm lộ dữ liệu hoặc tạo hành động nguy hiểm? |

Quality score tổng có thể che critical failure; giữ hard gates cho authority, safety và correctness.

## 44. Measurement hierarchy

```text
inventory health
  → find
    → understand
      → decide / execute correctly
        → retained behavior
          → security / service outcome
```

Ví dụ metric:

- inventory: owner/freshness/duplicate coverage;
- find: successful search/time/query reformulation;
- understand: comprehension test;
- execute: first-time task success/rework/error;
- decide: correct route/criteria/evidence;
- outcome: exception, failure demand, escaped control issue giảm.

Luôn định nghĩa population, source, uncertainty và action khi metric đổi.

## 45. Feedback loop và knowledge gaps

Feedback cần reason codes:

- không tìm thấy;
- không hiểu;
- không áp dụng cho context;
- steps sai/lỗi thời;
- thiếu permission/tool/dependency;
- conflict với source khác;
- cần judgment/authority;
- outcome vẫn thất bại.

Nút “helpful?” chỉ là signal yếu. Nối search, task observation, support resolution và product/control outcome để route root cause đúng nơi.

## 46. Reuse economics

Knowledge reuse tạo giá trị khi giảm duplicate work mà không truyền lỗi đồng loạt. Theo dõi:

- author/review/maintenance lifecycle cost;
- assisted contacts và rework tránh được;
- time-to-decision/task improvement;
- số contexts dùng đúng;
- marginal adaptation cost;
- incident/control failure do stale/shared content;
- concentration risk của common pattern.

Một article được link nhiều nhưng gây sai ở quy mô lớn có negative value. Tính quality-adjusted reuse, không chỉ lượt dùng.

## 47. Knowledge portfolio governance

Portfolio review theo decisions:

- user need nào chưa được đáp ứng?
- artifact nào duplicate/conflict/orphan/stale?
- knowledge nào nên embed vào product/platform?
- content nào cần split/merge/localize?
- topic nào cần expert capacity hoặc training?
- artifact nào cần retire vì risk lớn hơn value?
- common gaps nào cho thấy standard/product/service design có vấn đề?

Giữ WIP limit cho content mới và dành capacity bảo trì. “Publish more” không phải mặc định đúng.

## 48. Ví dụ: “SaaS này có được xử lý Restricted Data không?”

Knowledge package gồm:

1. quick decision aid hỏi data class, purpose, residency, identity/integration và supplier approval state;
2. kết quả `standard path`, `enhanced assessment`, `not permitted` hoặc `expert review`;
3. rationale và exact normative sources/version;
4. approved supplier/capability record từ authoritative system;
5. implementation pattern cho encryption, access, logging, retention;
6. evidence checklist và service/exception route;
7. change notification khi supplier/standard state đổi.

Đo eligible question resolution, correct routing, first-time evidence acceptance, time-to-decision và escaped data use—not page views.

## 49. Kế hoạch triển khai 90 ngày

### Ngày 1–30: inventory và top decisions

- chọn một domain có demand/consequence cao;
- inventory sources, owners, copies, search queries và support gaps;
- lập top questions/tasks/decisions theo segment;
- thống nhất artifact taxonomy, state, authority và metadata;
- baseline findability, freshness và task success;
- chọn 5–10 high-value knowledge products.

### Ngày 31–60: thiết kế và kiểm chứng

- tạo canonical source map và unified discovery prototype;
- viết quick answers, decision aids, examples và expert routes;
- technical/authority/accessibility review;
- test search, comprehension và realistic task completion;
- thiết lập change triggers, link/dependency checks;
- merge/redirect duplicate content ưu tiên cao.

### Ngày 61–90: vận hành và mở rộng

- publish theo cohorts và đo end-to-end outcome;
- nối feedback/support/incident signals tới backlog;
- thiết lập domain owner/editor/community cadence;
- thử executable decision support cho một bounded use case;
- đánh giá AI/RAG bằng curated test set nếu sử dụng;
- review portfolio và quyết định scale, embed, revise hoặc retire.

## 50. Checklist, anti-pattern, nguồn và học tiếp

### Checklist production

- [ ] Mỗi knowledge product gắn với audience, decision/task và expected outcome.
- [ ] Normative source, authority, scope, version và provenance rõ.
- [ ] Artifact type, owner, state, review trigger và retirement path có.
- [ ] Canonical source tách khỏi portal/index/copy; copy có sync và status.
- [ ] Taxonomy, glossary, synonyms và relationships hỗ trợ findability.
- [ ] Content được test bằng realistic search/comprehension/task, không chỉ SME review.
- [ ] Decision aid có unknown, stop, expert, exception và evidence paths.
- [ ] Examples/code được test; sensitivity/accessibility/localization được quản.
- [ ] Metrics đi từ inventory/find tới correct execution và security outcome.
- [ ] AI/RAG grounded, permission-aware, evaluated và biết abstain/escalate.

### Anti-pattern cần tránh

- Xây portal trước khi biết top decisions/tasks.
- Copy tất cả content vào “single source of truth” nhưng không giữ provenance.
- FAQ thay đổi nghĩa standard mà không có authority.
- Đo page views hoặc ticket deflection dù user hành động sai.
- Một mega page trộn tutorial, reference, policy và runbook.
- Review date được gia hạn nhưng không kiểm tra behavior/dependency thật.
- Community answer được hiển thị như authoritative guidance.
- Checklist biến judgment phức tạp thành tick-box compliance.
- AI trả answer không source/version/scope hoặc không biết từ chối.
- Giữ content cũ trong search mà không banner/redirect/supersession.

### Nguồn chính thức

- [NIST NICE Framework](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center/getting-started) —
  tách Task, Knowledge và Skill; dùng common language để mô tả work và capability cần thiết.
- [NIST SP 800-53 Rev.5 và Release 5.2.0](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — control catalog,
  planning, awareness/training, procedures và organization-wide risk context; kiểm tra release/version hiện hành.
- [NIST SP 800-55 Vol.1](https://csrc.nist.gov/pubs/sp/800/55/v1/final) — chọn, ưu tiên và đánh giá
  security measures với semantics, data quality và decision use rõ.
- [NIST AI RMF: Generative AI Profile](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) — confabulation,
  information integrity, privacy và human/organizational risks cần xét khi dùng AI/RAG.
- [GOV.UK: Plan new content](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/plan-manage-content/plan-new-govuk-content/) —
  content theo user task, audience, current need, findability và tránh duplicate.
- [GOV.UK: Manage existing content](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/plan-manage-content/manage-existing-govuk-content/) —
  content audit, review date, usefulness/findability, update và retirement.
- [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/) — readable, understandable, predictable và assistive-technology-compatible content.
- [OWASP Cheat Sheet Series](https://owasp.org/www-project-cheat-sheets/) — ví dụ community-maintained,
  concise security guidance nối với requirements/use cases và public contribution workflow.

### Học tiếp

1. [Security Developer Relations, Champions & Community Enablement](security_developer_relations_champions_community_enablement.md) — developer advocacy, champions network,
   community programs, feedback loops và influence without authority.
2. [Security Engineering Enablement & Secure Delivery Coaching](security_engineering_enablement_secure_delivery_coaching.md) — embedded coaching, pairing, design clinics,
   capability transfer và measurable delivery outcomes.

---

*Cập nhật lần cuối: 2026-08-03.*
