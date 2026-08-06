# Security Culture, Human Risk & Behavior Engineering

> Mục tiêu: tạo môi trường trong đó hành vi an toàn trở nên dễ, bình thường và có thể phục hồi — bằng cách kết hợp
> leadership, incentive, workflow, product design, learning và measurement thay vì đổ trách nhiệm cho cá nhân.

---

## 1. Từ awareness sang security outcome

Awareness chỉ là một điều kiện. Người biết điều đúng vẫn có thể làm khác vì:

- workflow gây áp lực thời gian;
- secure path khó tìm hoặc không hoạt động;
- incentive thưởng tốc độ nhưng phạt việc dừng kiểm tra;
- quyền hạn/reporting channel không rõ;
- attacker tạo urgency, authority hoặc social pressure;
- con người mệt mỏi, quá tải hoặc thiếu context;
- process/technology không chặn một lỗi có thể dự đoán.

```text
risk scenario + work context
    → target behavior
        → capability + opportunity + motivation
            → intervention across people / process / technology
                → behavior + security outcome + learning
```

Mục tiêu không phải “đã học xong”, mà là giảm exposure, tăng detection/reporting/recovery và duy trì trust.

## 2. Con người không phải “mắt xích yếu nhất”

Cách gọi này tạo ba lỗi:

1. che thiết kế sản phẩm/quy trình không an toàn;
2. khuyến khích blame và làm người dùng giấu sai sót;
3. xem con người chỉ là nguồn lỗi, bỏ qua khả năng phát hiện và thích nghi.

[NIST Human-Centered Cybersecurity](https://csrc.nist.gov/Projects/human-centered-cybersecurity/about) hướng tới giải pháp
an toàn trong thực tế, tính đến nhu cầu/hành vi và làm cách đúng dễ hơn, cách sai khó hơn, phục hồi dễ hơn.

Hỏi “điều kiện nào khiến hành vi này hợp lý tại thời điểm đó?” hữu ích hơn “ai đã click?”. Accountability vẫn cần,
nhưng phải phân biệt human error, at-risk behavior, reckless/malicious action và system design failure.

## 3. Security culture là gì?

Security culture là các giá trị, chuẩn mực và hành vi được lặp lại để trả lời:

- điều gì được coi là quan trọng khi security xung đột deadline;
- ai có quyền dừng hoặc challenge một yêu cầu đáng ngờ;
- bad news được đón nhận hay trừng phạt;
- leader thật sự làm gì, không chỉ nói gì;
- shortcut nào được ngầm chấp nhận;
- team học và sửa system sau sai sót thế nào;
- security có phải phần của quality/customer trust hay “việc của đội security”.

Culture không phải điểm survey, poster hoặc tháng awareness. Các tín hiệu đó chỉ phản ánh một phần; culture hiện ra qua
decision, resource allocation, reward, workflow và phản ứng khi có áp lực.

## 4. Human risk không phải một loại người

Phân loại theo scenario và trạng thái, không gắn nhãn con người:

| Trạng thái/hành vi | Ví dụ | Response chính |
|---|---|---|
| Unintentional error | gửi nhầm, cấu hình nhầm | design, guardrail, recovery |
| Knowledge/skill gap | không biết xác minh payment change | learning + performance support |
| At-risk shortcut | share credential để kịp deadline | incentive, friction, workflow |
| Compromised person/account | session bị chiếm | technical detection/containment |
| Coerced/manipulated | social engineering, pressure | verification + escalation |
| Reckless violation | bỏ qua boundary đã hiểu | accountability + root cause |
| Malicious insider | chủ ý lạm dụng | deterrence, access control, investigation |

Cùng một observable event có thể thuộc nhiều nguyên nhân. Không suy động cơ chỉ từ log hoặc simulation result.

## 5. Mô hình socio-technical

Hành vi hình thành từ tương tác:

- **people:** knowledge, skill, attention, fatigue, beliefs;
- **task:** complexity, frequency, ambiguity, time pressure;
- **technology:** defaults, affordance, warning, latency, failure mode;
- **process:** handoff, approval, exception, recovery;
- **organization:** leadership, incentive, staffing, norms;
- **environment:** customer, threat, regulation, remote work, language.

Ví dụ payment fraud không được xử lý chỉ bằng “dạy nhân viên cẩn thận”. Cần authenticated change channel, dual control,
call-back độc lập, limit, anomaly detection, stop authority và rapid recall bên cạnh practice.

## 6. Governance và ownership

Human risk program cần shared ownership:

| Vai trò | Accountability minh họa |
|---|---|
| Executive sponsor | tone, resources, cross-functional conflict |
| Human risk/culture lead | program outcomes, portfolio, ethics, measurement |
| Security/risk | scenarios, controls, incident learning |
| HR/People | lifecycle, policy, learning, employee relations |
| Privacy/legal | lawful/fair data use, investigation boundary |
| Product/IT | secure defaults, workflow, reporting/recovery UX |
| Managers | local norm, time, reinforcement, escalation |
| Business owner | process risk và control operation |
| Workforce | perform, report, learn và give feedback |

Không giao “mọi lỗi con người” cho awareness team. Nhiều response thuộc product/process owner và leadership.

## 7. Nguyên tắc đạo đức

Chương trình phải:

- dùng data tối thiểu cho mục đích đã công bố;
- tránh humiliation, deception không cần thiết và public ranking;
- phân biệt learning với investigation/discipline;
- cung cấp due process và review cho quyết định ảnh hưởng cá nhân;
- kiểm bias theo vai trò, ngôn ngữ, disability, geography và access;
- giới hạn retention/access/secondary use;
- không dùng dark pattern để “bẫy” người học;
- ưu tiên upstream design trước khi yêu cầu vigilance vô hạn;
- minh bạch điều gì được đo và vì sao.

Trust là control: workforce sẽ báo sớm hơn khi tin rằng báo cáo dẫn tới hỗ trợ công bằng, không phải trừng phạt tự động.

## 8. Định nghĩa target behavior

“Cẩn thận hơn” không thể thiết kế hoặc đo. Behavior statement tốt có:

```text
actor + action + context/trigger + channel/tool + time/quality boundary
```

Ví dụ:

- AP analyst xác minh thay đổi tài khoản ngân hàng bằng contact channel đã đăng ký trước khi release payment;
- engineer báo secret lộ qua one-click channel ngay khi phát hiện, không tự xóa evidence trước;
- manager dùng delegated exception flow khi deadline xung đột control;
- support agent dừng account recovery và escalate khi identity proof không nhất quán.

Nối target behavior với risk scenario, control objective và recovery action.

## 9. Capability, opportunity và motivation

Chẩn đoán ba điều kiện:

- **Capability:** người đó có knowledge, skill, memory và practice cần thiết không?
- **Opportunity:** workflow, tool, time, authority và social norm có cho phép hành vi không?
- **Motivation:** incentive, belief, trust, habit và perceived consequence có hỗ trợ không?

Nếu report button không có trên mobile, thêm khóa học khó sửa **opportunity**. Nếu manager thưởng người bypass review để kịp
launch, poster không sửa **motivation/social norm**. Intervention phải khớp nguyên nhân chứ không mặc định training.

## 10. Segment theo context và risk

Không chia audience chỉ theo chức danh. Segment theo:

- task và decision thực tế;
- privilege/data/payment/customer impact;
- exposure với external communication;
- work environment/device/channel;
- frequency và novelty;
- language/accessibility;
- employment/partner relationship;
- lifecycle event: join, role change, leave;
- incident/simulation pattern ở cấp cohort.

Một executive assistant, payroll analyst và cloud administrator có risk context khác dù cùng “employee”. Giữ minimum
baseline toàn tổ chức, sau đó role/task-based learning và system controls theo risk.

## 11. Journey map hành vi

Map hành trình thay vì chỉ điểm lỗi:

```text
trigger → perceive → interpret → decide → act → receive feedback → recover / learn
```

Với phishing report:

- email có được nhìn là bất thường không;
- cue có hiểu được trong context không;
- report button có dễ thấy trên device không;
- người dùng có sợ báo nhầm không;
- SOC có acknowledge và phản hồi không;
- click nhầm có channel containment nhanh không;
- learning có đến đúng lúc và không shame không.

Mỗi failure point có thể cần design, process, communication hoặc learning khác nhau.

## 12. Friction budget

Mọi control thêm friction tiêu hao attention và time. Quản “friction budget” theo risk:

- high-impact, infrequent action có thể cần step-up/dual control;
- low-risk, frequent action nên tự động hoặc mặc định an toàn;
- lặp cảnh báo làm warning fatigue;
- queue/approval dài tạo shadow process;
- workaround là data về service design, không chỉ violation.

Đo time-to-safe-completion, abandonment, bypass, support và error recovery. Không tối ưu convenience bằng cách bỏ control;
thiết kế để secure path nhanh, rõ, reliable và tương xứng risk.

## 13. Secure defaults và mistake-proofing

[CISA Secure by Design](https://www.cisa.gov/news-events/news/applying-secure-design-thinking-events-news) nhấn mạnh không
đẩy toàn bộ gánh nặng an toàn xuống customer/user. Upstream controls gồm:

- least privilege/default deny;
- MFA/passkey được bật và recovery an toàn;
- external sender/verified identity cues;
- sensitive data warning có context;
- safe sharing scope/expiry mặc định;
- payment/account change verification workflow;
- destructive action preview/delay/dual approval;
- reversible action, undo và rapid revoke;
- risky configuration bị loại hoặc tách rõ.

Training không bù được một product liên tục mời người dùng chọn insecure default.

## 14. Incentive và local optimization

Kiểm tra tổ chức đang thưởng gì:

- sales chỉ theo tốc độ ký deal có bypass due diligence không;
- engineering chỉ theo deployment count có che control debt không;
- SOC chỉ theo đóng ticket nhanh có discourage reporting không;
- manager có bị phạt khi team báo incident sớm không;
- employee có mất giờ vì secure process nhưng không được ghi nhận không.

Thêm guardrail/outcome vào performance system, nhưng tránh thưởng cá nhân theo proxy dễ game như “không click phishing”.
Recognition nên khuyến khích early reporting, improvement và responsible challenge, không tạo cạnh tranh che lỗi.

## 15. Leadership behavior

Tone at the top chỉ đáng tin khi leader:

- tuân thủ cùng authentication/exception rules;
- không yêu cầu bypass qua kênh riêng;
- cấp funding/time để sửa upstream issue;
- công khai trade-off và residual risk;
- phản ứng bình tĩnh với early bad news;
- tham gia exercise và học từ failure;
- giữ accountable owner, không blame người cuối chuỗi;
- dừng launch/payment khi boundary bị vi phạm;
- báo lại action đã thực hiện từ workforce feedback.

Một email “security is everyone’s responsibility” bị vô hiệu nếu executive thường xuyên đòi special exception không evidence.

## 16. Manager là điểm khuếch đại culture

Nhân viên quan sát manager gần hơn policy. Manager enablement cần:

- talking points theo work context;
- scenario discussion ngắn trong team cadence;
- cách xử lý report/error công bằng;
- authority/delegation và escalation path;
- protected time cho role-based practice;
- dashboard cohort không dùng để shame;
- playbook khi performance/discipline và security giao nhau;
- feedback channel tới program owner.

Đo manager reinforcement và system action, không chỉ completion của cấp dưới.

## 17. Security champions và advocates

Champion giúp dịch security vào local context và phản hồi friction. Chương trình cần:

- charter, scope và manager-supported time;
- selection đa dạng, không chỉ người đã mê security;
- training, office hours và escalation;
- reusable artifact/scenario;
- boundary authority rõ;
- community và recognition;
- succession/rotation;
- outcome/adoption measures.

[NIST Human-Centered Cybersecurity](https://csrc.nist.gov/projects/human-centered-cybersecurity/research-areas/cybersecurity-adoption)
nghiên cứu vai trò cybersecurity advocates trong hỗ trợ adoption. Champion không thay control owner, specialist hoặc risk owner.

## 18. Speak-up và psychological safety

Workforce cần tin rằng có thể:

- hỏi khi không chắc;
- báo click/gửi nhầm/secret leak ngay;
- challenge yêu cầu từ người có authority;
- nói workload/control không khả thi;
- đề xuất sửa policy/tool;
- báo near miss mà không bị gắn nhãn bất cẩn.

Thiết kế reporting channel nhanh, confidential khi phù hợp, acknowledgement và status feedback. Psychological safety
không xóa accountability; nó giúp evidence xuất hiện sớm để containment và learning tốt hơn.

## 19. Just culture: học và chịu trách nhiệm công bằng

Phân biệt response:

| Tình huống | Response |
|---|---|
| Human error hợp lý | console, restore, sửa system, học |
| At-risk shortcut được normalize | coaching + bỏ incentive/friction |
| Knowledge/skill gap | practice/performance support |
| Reckless disregard có evidence | proportionate accountability |
| Malicious action | investigation/containment/due process |

Không gọi mọi retrospective “blameless” rồi bỏ qua decision quality; cũng không dùng outcome xấu để suy ngược negligence.
Xem context, foreseeability, available safe path, training/practice, authority và organizational contribution.

## 20. Learning program là một vòng đời

[NIST SP 800-50 Rev.1](https://csrc.nist.gov/pubs/sp/800/50/r1/final) hướng dẫn xây Cybersecurity and Privacy
Learning Program theo vòng đời, hướng tới behavior change và culture. Một vòng thực dụng:

```text
govern + assess needs
    → design outcomes / audience / intervention
        → develop / acquire / test
            → deliver + support transfer to work
                → evaluate + improve / retire
```

Learning portfolio phải nối risk và work, có owner, accessibility, version/freshness và evaluation; annual module chỉ là
một delivery channel.

## 21. Learning needs assessment

Nguồn nhu cầu gồm:

- risk scenarios và target behaviors;
- incident/near-miss/root cause;
- role/task/technology change;
- policy/control rollout;
- audit/assurance gap;
- user research, support và friction;
- threat/social engineering trend;
- survey/interview/observation;
- manager/champion feedback;
- performance data có privacy guardrail.

Tách knowledge gap khỏi tool/process/incentive gap. Nếu root cause không phải learning, chuyển backlog tới đúng product,
process hoặc management owner thay vì sản xuất thêm khóa học.

## 22. Awareness, training, education và performance support

| Hình thức | Mục tiêu | Ví dụ |
|---|---|---|
| Awareness | nhận biết/ưu tiên/chung ngôn ngữ | campaign, story, reminder |
| Training | thực hiện task/decision | scenario practice, lab |
| Education | mental model sâu, transfer rộng | course, workshop, apprenticeship |
| Performance support | làm đúng tại thời điểm làm việc | checklist, inline cue, template |
| Exercise | phối hợp dưới điều kiện gần thật | tabletop, simulation, drill |

Chọn dựa trên performance need. Người thực hiện quy trình hiếm mỗi năm thường cần checklist/just-in-time support hơn
việc nhớ nội dung từ khóa học 11 tháng trước.

## 23. Role- và task-based learning

Map theo chuỗi:

```text
risk scenario → role / task / decision
    → required knowledge + skill + attitude
        → practice + feedback + performance support
            → observed work outcome
```

Ví dụ developer cần secret handling, authorization, dependency và incident handoff trong toolchain; AP cần business email
compromise/payment verification; executive cần crisis/risk decision. Không chỉ đổi tên cùng một slide deck cho từng role.

Có thể dùng [NICE Framework](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center)
để mô tả cybersecurity work/knowledge/skills, nhưng tailor theo local task và responsibility.

## 24. Just-in-time learning và microlearning

Đưa hướng dẫn gần trigger:

- khi tạo public share link;
- trước đổi bank account/payment release;
- khi cấp privileged role;
- trong pull request có security-sensitive change;
- khi chuẩn bị travel hoặc M&A onboarding;
- sau report/simulation với feedback phù hợp;
- trước recovery/incident exercise.

Microlearning phải có một behavior/outcome rõ, không phải cắt khóa dài thành video nhỏ. Tránh notification fatigue; dùng
context, frequency cap, priority và khả năng dismiss khi không liên quan.

## 25. Scenario practice và feedback

Practice tốt có:

- realistic task/context nhưng safe;
- clear objective và success criteria;
- decision point, không chỉ recall câu chữ;
- immediate explanatory feedback;
- increasing difficulty;
- opportunity retry;
- link tới job aid/reporting channel;
- debrief về cues, trade-off và recovery;
- data use minh bạch.

Đánh giá transfer bằng work sample/exercise hoặc behavior outcome khi hợp lý. Quiz completion chủ yếu chứng minh người học
đã đi qua nội dung, không tự chứng minh hành vi trong production.

## 26. Accessibility, inclusion và local context

Thiết kế cho:

- ngôn ngữ và mức literacy khác nhau;
- screen reader, keyboard, caption, contrast;
- neurodiversity và cognitive load;
- mobile/frontline/shift/offline work;
- culture/authority norm theo geography;
- contractor/partner không có full tool access;
- người mới hoặc dùng assistive technology;
- scenario không stereotype nhóm người.

Một warning chỉ dựa màu hoặc một reporting flow chỉ dùng desktop tạo risk không đồng đều. Test với audience thật,
không suy đoán từ nhóm thiết kế.

## 27. Communication architecture

Message hiệu quả trả lời:

- audience đang làm job gì;
- behavior nào, trong context nào;
- vì sao có ý nghĩa với customer/team;
- làm bằng channel/tool nào;
- nếu không chắc hoặc sai thì report/recover ra sao;
- owner/support ở đâu.

Dùng trusted local sender, timing và channel phù hợp. Tránh fear-only, jargon, message conflict và campaign dày đặc. Lặp
nhất quán qua leader, manager, tool, policy và peer norm; nếu product UI nói khác training, UI thường thắng.

## 28. Phishing simulation dùng để học, không để bẫy

Mục tiêu có thể là:

- practice nhận biết và reporting;
- test reporting/detection/containment workflow;
- hiểu cohort/context gap;
- đánh giá một intervention;
- rehearse business process verification.

Simulation không nên là cuộc thi tạo email khó nhất hoặc KPI để phạt người. Chỉ click rate không cho biết difficulty,
exposure, reporting quality, technical controls hoặc consequence. Có charter, legal/HR/privacy review, safe payload,
support và learning response.

## 29. Dùng NIST Phish Scale để thêm context

[NIST Phish Scale User Guide](https://www.nist.gov/publications/nist-phish-scale-user-guide) cung cấp cách đánh giá độ khó
phát hiện phishing của email để đặt click/report rate trong context.

Khi phân tích campaign, giữ:

- difficulty/cue context;
- delivered/opened population;
- device/channel/role;
- click, credential submission, report và time-to-report;
- technical detection/blocking;
- prior exposure/learning;
- repeat measurement và uncertainty.

Không so hai cohort/campaign như nhau khi độ khó khác. Scale hỗ trợ interpretation, không biến kết quả thành phán quyết
về phẩm chất cá nhân.

## 30. Ethics và safety của simulation

Không dùng chủ đề có khả năng gây hại không cần thiết như sa thải, bệnh nặng hoặc trauma để tăng click. Thiết kế:

- purpose và acceptable deception được phê duyệt;
- exclude/support nhóm có risk đặc biệt;
- không thu real password/token;
- landing feedback không shame;
- data access/retention tối thiểu;
- manager response công bằng;
- appeal/correction process;
- no public leaderboard;
- emergency stop và incident coordination;
- debrief đủ nhanh để tránh misinformation kéo dài.

Simulation làm mất trust có thể gây human risk lớn hơn lợi ích đo được.

## 31. Reporting UX và recovery

Reporting là một security control. Nó cần:

- one-click/low-friction trên desktop/mobile;
- tự đính kèm metadata cần thiết, không đòi người dùng phân tích;
- acknowledge ngay;
- hướng dẫn nếu đã click/submit/send;
- fast path cho payment/credential/data exposure;
- no-fault early report;
- status/closure feedback khi phù hợp;
- integration với triage/containment;
- fallback channel khi tool hỏng.

Đo time-to-report và time-to-contain cùng false-report handling. Báo nhầm hợp lý là chi phí của sensitivity, không phải lý
do discourage reporting.

## 32. Social engineering vượt ngoài email

Scenario còn gồm:

- voice/video deepfake và callback fraud;
- SMS/chat/collaboration platform;
- support/help-desk recovery;
- OAuth consent/QR code;
- physical access/tailgating;
- supplier/customer channel compromise;
- executive impersonation;
- recruitment/payroll change;
- AI-generated multilingual persuasion.

Tập trung invariant: verified identity, independent channel, least privilege, dual control, stop/escalate và rapid revoke.
Dạy “tìm lỗi chính tả” không đủ trước nội dung được tạo tốt hoặc account hợp lệ đã bị compromise.

## 33. High-risk roles và moments

Ưu tiên theo task/consequence:

- payment/treasury/procurement;
- help desk/account recovery;
- executive và assistant;
- privileged admin/cloud/platform;
- developer/release/CI/CD;
- HR/payroll/recruiting;
- legal/M&A/data room;
- customer support;
- frontline/OT operations;
- traveler và public-facing personnel.

Thiết kế role-specific controls, practice và escalation. “High risk” không phải nhãn permanent về người; risk thay đổi theo
role, privilege, campaign và business event.

## 34. Privileged, developer và operator behavior

Với technical roles, lecture chung ít hiệu quả hơn controls trong workflow:

- JIT privilege và separation of duties;
- code/template/golden path;
- peer review cho sensitive change;
- safe sandbox/lab;
- pre-commit/CI feedback actionable;
- break-glass drill;
- runbook và decision checklist;
- blameless evidence-based incident review;
- community of practice;
- time cho debt/remediation.

Đo safe completion và escaped systemic issue, không thưởng việc “không tạo finding” khiến team che discovery.

## 35. Joiner, mover, leaver và returner

Human risk controls gắn lifecycle:

| Event | Trọng tâm |
|---|---|
| Joiner | norms, report/recovery channel, role baseline, manager reinforcement |
| Mover | privilege/data/task delta, new scenario practice, revoke quyền cũ |
| Temporary assignment | expiry, sponsor, task-specific briefing |
| Leave/absence | handoff, access, data/equipment, support |
| Leaver | timely revoke, return asset, confidentiality, respectful process |
| Returner | identity/access revalidation và policy/tool delta |

Không coi training completion là lifecycle control duy nhất; identity, access, manager và HR workflow phải đồng bộ.

## 36. Contractor, supplier và contingent workforce

Đối tượng ngoài payroll vẫn có thể truy cập resource. Cần:

- contractual responsibility và minimum behavior;
- sponsor/owner;
- role/task-based onboarding;
- access/tool/reporting channel tương xứng;
- language/time-zone/support;
- incident notification/escalation;
- privacy/fairness khi đo;
- periodic revalidation;
- offboarding và downstream revoke;
- shared exercises cho critical workflow.

Không gửi khóa học nội bộ mà contractor không truy cập được rồi đánh dấu non-compliant. Shared responsibility cần khả thi
trong operating context.

## 37. Insider risk theo continuum

Insider risk có thể xuất phát từ error, compromised account, coercion, negligence hoặc malicious intent. Program nên kết hợp:

- least privilege/JIT và segregation;
- data/process guardrail;
- anomaly signal có context;
- supportive reporting và wellbeing path;
- conflict/change indicators theo lawful policy;
- manager/HR/legal/security coordination;
- rapid access adjustment;
- investigation threshold và due process;
- recovery/lessons.

Không biến mọi employee thành suspect. Technical signal thường không chứng minh intent; cần corroboration, proportionality
và independent oversight.

## 38. Malicious insider: containment và fairness

Với credible malicious scenario:

- bảo toàn evidence và chain of custody;
- giới hạn need-to-know;
- phối hợp legal/HR/privacy/law enforcement theo authority;
- tránh tipping-off khi có căn cứ;
- revoke/contain theo risk và safety;
- bảo vệ whistleblower/legitimate activity;
- kiểm alternative explanation;
- document decision/rationale;
- giữ business continuity;
- review control/systemic gap sau case.

Không dùng learning team làm covert investigation. Tách program data, investigation authority và employment decision.

## 39. Governance dữ liệu hành vi

Behavioral telemetry có thể nhạy cảm. Data contract cần:

- specific purpose và lawful basis;
- population/fields/source;
- collection transparency;
- access/role segregation;
- retention/deletion;
- quality và false-positive handling;
- individual correction/appeal khi applicable;
- aggregation/minimum cohort size;
- prohibited secondary uses;
- vendor/subprocessor/region;
- model/score logic và human review;
- breach/incident response.

Không xây “human risk score” bí mật từ mọi click, message và productivity signal. Surveillance quá mức phá trust và tạo bias.

## 40. Measurement hierarchy

Đo theo chuỗi, không dừng ở completion:

| Lớp | Ví dụ |
|---|---|
| Reach/exposure | eligible, delivered, participated, unknown |
| Learning | knowledge/skill qua assessment thực hành |
| Behavior | verify, report, revoke, use safe path |
| Environment | friction, secure default, manager support, channel availability |
| Control | prevention/detection/containment effectiveness |
| Outcome | loss, impact, duration, near miss, trust |
| Sustainability | fatigue, fairness, repeat behavior, cost |

Mỗi metric có decision, denominator, context, data quality và action threshold. Completion có thể cần cho obligation nhưng
không tự chứng minh risk reduction.

## 41. Denominator, context và cohort

Ví dụ phishing:

- delivered khác opened;
- clicked khác submitted credential;
- reports cần denominator và quality;
- campaign difficulty khác nhau;
- technical block thay exposure;
- role/device/language khác context;
- repeat tester bias kết quả;
- unknown/failed telemetry không phải zero.

Theo dõi distribution và time-to-report, không chỉ average/click rate. So cohort ổn định hoặc điều chỉnh context; không xếp
hạng team khi sample nhỏ hoặc job exposure khác nhau.

## 42. Đánh giá effectiveness

Có thể dùng bốn mức:

1. **Reaction:** nội dung usable/relevant không?
2. **Learning:** knowledge/skill thay đổi không?
3. **Transfer:** hành vi có xuất hiện trong work context không?
4. **Outcome:** exposure/control/incident consequence thay đổi không?

Giữ baseline, time window và concurrent interventions. Training cùng lúc bật email filtering và report button thì không thể
gán toàn bộ thay đổi cho training. Dùng triangulation: telemetry, exercise, interview, observation, incident và support data.

## 43. Đo culture mà không biến thành một điểm

Culture là latent, đa chiều. Kết hợp:

- anonymous survey về norms, trust, leader/manager action;
- interview/focus group;
- early reporting/near miss;
- exception/bypass và friction;
- incident response/retrospective behavior;
- resource/allocation decisions;
- manager/champion activity;
- workforce sentiment/turnover theo privacy boundary;
- observed decision trong exercise.

Không average thành “culture score 83” rồi so vô nghĩa. Giữ dimension, uncertainty, qualitative context và group size;
survey nói về perception, không tự chứng minh control effectiveness.

## 44. Experiment và intervention portfolio

Xem intervention như hypothesis:

```text
because root cause X,
if we change Y for population Z,
behavior/outcome M should change within T,
without disbenefit D.
```

Có thể pilot warning wording, reporting UX, manager reinforcement, default hoặc practice sequence. Predefine primary/guardrail
metrics, sample/time, privacy và stop rule. Không A/B test control có thể gây material harm nếu variant yếu; dùng lab,
simulation hoặc staged rollout an toàn.

## 45. Goodhart, gaming và unintended behavior

Khi metric thành target:

- người dùng report mọi email để tối ưu report rate;
- manager nhắc trước simulation;
- team che incident để giữ “zero error”;
- completion được click-through;
- security tạo phish ngày càng khó để chứng minh program cần thiết;
- người dùng tránh channel chính vì sợ bị đo.

Dùng metric pairs, qualitative review, stable definitions và outcome checks. Không thưởng/phạt cá nhân tự động theo proxy.
Retire metric khi mất validity hoặc gây hành vi không mong muốn.

## 46. Incident và near-miss learning

Sau sự kiện, hỏi:

- work goal và context tại thời điểm đó;
- cues/information nào có hoặc thiếu;
- safe path có khả dụng và được tin không;
- authority/incentive/time pressure nào tác động;
- control nào dự kiến chặn/phát hiện/giới hạn;
- reporting/recovery diễn ra thế nào;
- cùng điều kiện tồn tại ở đâu;
- upstream change nào có leverage cao nhất.

Action trải trên product/process/access/detection/learning/leadership. Đóng khi outcome/control được kiểm chứng, không khi
email reminder đã gửi.

## 47. AI và human risk

AI thay đổi cả attacker và workplace behavior:

- social engineering cá nhân hóa/deepfake;
- over-trust/automation bias;
- sensitive data đưa vào unsanctioned tool;
- hallucinated code/advice;
- unclear accountability giữa human và agent;
- approval fatigue cho automated actions;
- deskilling và khó detect anomaly;
- surveillance/bias từ employee analytics.

Thiết kế approved use cases, data boundary, provenance, verification theo impact, human authority, abstention/escalation,
audit, rollback và incident reporting. Không chỉ dạy “đừng dùng AI”; cung cấp safe path đáp ứng job need.

## 48. Ví dụ end-to-end: Business Email Compromise

**Scenario:** attacker compromise supplier email, yêu cầu đổi bank account trước payment lớn.

| Lớp | Intervention |
|---|---|
| Process | master-data change tách payment release; callback tới contact đăng ký trước |
| Technology | verified workflow, dual control, anomaly/limit, delay/recall |
| Behavior | analyst stop, verify, report; manager không override qua chat |
| Learning | realistic role scenario + just-in-time checklist |
| Culture | leader công khai ủng hộ delay khi verification fail |
| Recovery | freeze/recall, bank/legal/IR coordination, evidence |
| Measures | verified-change coverage, bypass/unknown, report/contain time, loss/near miss, friction |

Simulation chỉ là một test. Outcome đến từ defense-in-depth và khả năng dừng/phục hồi, không từ vigilance hoàn hảo.

## 49. Lộ trình triển khai 90 ngày

**Ngày 1–30 — Diagnose**

- chọn 3–5 scenario/task có consequence cao;
- map target behavior, journey, friction và existing controls;
- baseline reporting, learning, behavior, outcome và trust;
- thống nhất governance/ethics/data boundary.

**Ngày 31–60 — Design và pilot**

- chọn intervention across people/process/technology;
- sửa một upstream friction/default;
- pilot role-based practice/reporting flow;
- đặt hypothesis, guardrail metrics và feedback.

**Ngày 61–90 — Learn và scale**

- đánh giá transfer/outcome, fairness và disbenefit;
- sửa hoặc dừng intervention yếu;
- assign product/process/manager actions;
- scale theo cohort và lập quarterly learning review.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist production

- [ ] Human risk được mô tả bằng scenario/context, không gắn nhãn con người.
- [ ] Target behavior có actor, action, trigger, channel và quality/time boundary.
- [ ] Root cause phân biệt capability, opportunity, motivation và system design.
- [ ] Intervention kết hợp people/process/technology, ưu tiên secure default.
- [ ] Learning portfolio role/task-based, accessible và có performance support.
- [ ] Simulation có purpose, difficulty context, ethics, support và safe data use.
- [ ] Reporting/recovery path nhanh, no-fault và integrated containment.
- [ ] Behavioral data có purpose, minimization, access, retention và due process.
- [ ] Measures giữ denominator/cohort/context và nối transfer/outcome.
- [ ] Incident/near miss thay đổi upstream system, không chỉ gửi reminder.

### Anti-pattern cần tránh

- Gọi người dùng là mắt xích yếu nhất hoặc nguyên nhân gốc mặc định.
- Annual completion/click rate được báo như risk reduction.
- Phishing simulation tối ưu độ khó, shame hoặc discipline tự động.
- Training dùng để bù insecure default và broken workflow.
- Human risk score bí mật dựa trên surveillance thiếu context.
- Manager/leader bypass nhưng workforce bị yêu cầu “cẩn thận hơn”.
- Champion chịu trách nhiệm vô hạn mà không time/authority/support.
- Incident action chỉ là “retrain user”, không sửa system.

### Nguồn chính thức

- [NIST SP 800-50 Rev.1](https://csrc.nist.gov/pubs/sp/800/50/r1/final) — vòng đời Cybersecurity and Privacy Learning Program, behavior change và culture.
- [NIST Human-Centered Cybersecurity](https://csrc.nist.gov/Projects/human-centered-cybersecurity/about) — security trong thực tế dựa trên nhu cầu, hành vi và khả năng con người.
- [NIST User Perceptions & Behaviors](https://csrc.nist.gov/Projects/human-centered-cybersecurity/research-areas/user-perceptions-behaviors) — nghiên cứu perception, attitude và behavior.
- [NIST Cybersecurity Adoption, Awareness & Training](https://csrc.nist.gov/projects/human-centered-cybersecurity/research-areas/cybersecurity-adoption) — adoption, training professional và security advocates.
- [NIST Phish Scale User Guide](https://www.nist.gov/publications/nist-phish-scale-user-guide) — đặt phishing result trong độ khó phát hiện.
- [NIST CSF 2.0](https://www.nist.gov/cyberframework) — outcomes về governance, roles, awareness và training.
- [NICE Framework Resource Center](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center) — work, knowledge và skills.
- [CISA Secure by Design](https://www.cisa.gov/news-events/news/applying-secure-design-thinking-events-news) — ownership của nhà sản xuất và giảm gánh nặng security cho user.

### Học tiếp

1. [Security Transformation & Change Management](security_transformation_change_management.md) — stakeholder change, adoption waves,
   transition risk, communication, resistance và institutionalization.
2. [Insider Risk Program & Trusted Workforce Operations](insider_risk_trusted_workforce_operations.md) — prevention, detection, privacy,
   investigation, response và cross-functional governance.

---

*Cập nhật lần cuối: 2026-08-03.*
