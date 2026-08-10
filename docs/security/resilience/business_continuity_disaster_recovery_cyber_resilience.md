---
title: "Business Continuity, Disaster Recovery & Cyber Resilience – Duy trì mission khi hệ thống bị gián đoạn"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 7
---
# Business Continuity, Disaster Recovery & Cyber Resilience – Duy trì mission khi hệ thống bị gián đoạn

> Thuật ngữ: [Glossary](../glossary.md).

Business Continuity (BC) không chỉ là tài liệu gọi điện khi mất điện; Disaster Recovery (DR) không chỉ là bật region phụ;
backup cũng không có giá trị nếu không khôi phục được đúng service, đúng dữ liệu và đúng thời gian. Mục tiêu cuối cùng là duy
trì hoặc phục hồi **business outcome đáng tin cậy** trong điều kiện hạ tầng hỏng, con người không sẵn sàng hoặc hệ thống bị xâm nhập.

```text
business service + impact tolerance
    → BIA + dependency graph
        → continuity / recovery strategy
            → protected backup + recoverable platform + runbook
                → exercise + measured RTO/RPO + lessons learned
```

Chương này nối [Enterprise Security Architecture & Zero Trust](../architecture/enterprise_security_architecture_zero_trust.md),
[Incident Response](../malware/incident_response.md) và
[Security Testing & Validation Engineering](../validation/security_testing_validation_engineering.md). Nội dung tập trung ở
tầng enterprise; kỹ thuật backup riêng cho database nằm trong các chương PostgreSQL/SQL Server tương ứng.

---

## 1. Phân biệt BC, DR, backup, HA và cyber resilience

| Khái niệm | Câu hỏi chính | Phạm vi |
|---|---|---|
| Business Continuity | Business vẫn cung cấp outcome tối thiểu bằng cách nào? | Người, quy trình, cơ sở, supplier, công nghệ |
| Disaster Recovery | Hệ thống/dữ liệu được khôi phục ở đâu, theo thứ tự nào? | Technology recovery |
| Backup/restore | Có bản sao độc lập để quay lại state nào? | Data, config, code, key và artifact |
| High Availability | Một thành phần hỏng thì dịch vụ có tiếp tục gần như ngay lập tức? | Redundancy/failover |
| Cyber resilience | Làm sao anticipate, withstand, recover và adapt khi có compromise? | Mission + system trustworthiness |

Các năng lực bổ trợ nhau. Replica đồng bộ tạo HA nhưng cũng sao chép lệnh xóa; backup cho phép quay lại quá khứ nhưng không
tự giữ service online.

## 2. Hệ sinh thái kế hoạch và khi nào kích hoạt

Một tổ chức thường cần các artifact liên quan nhưng khác mục đích:

- Business Continuity Plan cho hoạt động nghiệp vụ;
- IT/System Contingency Plan cho từng hệ thống;
- Disaster Recovery Plan cho site/platform quy mô lớn;
- Incident Response Plan để detect, contain, eradicate;
- Crisis Management Plan cho quyết định và truyền thông cấp doanh nghiệp;
- Emergency/Occupant/Safety Plan cho con người và cơ sở;
- supplier continuity và communication plan.

Mỗi plan cần activation criterion, authority, handoff và điểm kết thúc. Không để IR, DR và crisis team cùng ra lệnh trái nhau.

## 3. Governance, owner và quyền quyết định

Vai trò điển hình:

- executive sponsor bảo trợ capability và giải quyết ưu tiên enterprise;
- business service owner sở hữu impact tolerance và minimum outcome;
- continuity manager điều phối BIA, plan và exercise;
- technology/service owner sở hữu recovery design/runbook;
- incident commander chỉ huy containment và technical response;
- crisis lead quản lý quyết định xuyên business, legal, communication;
- data owner quyết consistency, loss/reconciliation;
- risk owner chấp nhận residual risk;
- independent assurance đánh giá readiness/evidence.

Tên vai trò có thể khác, nhưng authority cho failover, shutdown, data-loss acceptance và public communication phải rõ trước sự cố.

## 4. Lập kế hoạch theo scenario, không theo một nhãn “disaster”

Các scenario tạo nhu cầu khác nhau:

- một process/zone/region cloud mất;
- database corruption hoặc operator xóa nhầm;
- ransomware đã chiếm identity/control plane;
- SaaS/supplier ngừng hoạt động;
- DNS, PKI, IdP hoặc KMS mất;
- mất văn phòng, điện, mạng hoặc nhân sự chủ chốt;
- data center vật lý không tiếp cận được;
- mất integrity nhưng service vẫn “green”.

Với mỗi scenario, ghi onset, duration, scope, warning time, affected trust boundary và assumption. “Region down” không đại diện
cho compromise toàn tenant cloud.

## 5. Business Impact Analysis (BIA) là gì?

BIA xác định hoạt động nào thật sự quan trọng, tác động tăng theo thời gian ra sao và cần resource nào để phục hồi. Một record tốt có:

- business service/outcome và owner;
- customer/regulated/safety obligation;
- peak/season/cut-off time;
- impact theo thời gian;
- minimum acceptable service level;
- dependency và manual workaround;
- recovery priority, RTO/RPO và giả định;
- căn cứ/evidence và ngày review.

BIA không phải asset inventory gắn nhãn Critical tùy ý. Nó bắt đầu từ outcome rồi đi xuống process, people, data và technology.

## 6. Business service map thay cho danh sách application

Ví dụ “thanh toán lương” có thể cần:

```text
HR master data + timekeeping + payroll rules
    → payroll calculation
        → approval + bank file/API
            → employee communication + reconciliation
```

Một application có thể phục vụ nhiều service với criticality khác nhau; một service lại phụ thuộc nhiều application và thao tác thủ công.
Service map cần stable ID, owner, consumer, data flow và môi trường thực thi, không chỉ CMDB server name.

## 7. Impact theo thời gian và các chiều tác động

Đánh giá impact tại nhiều mốc, chẳng hạn 1 giờ, 4 giờ, 24 giờ, 3 ngày:

| Chiều | Ví dụ |
|---|---|
| Safety | ảnh hưởng người, môi trường, thiết bị vật lý |
| Customer/mission | giao dịch không xử lý, dịch vụ công gián đoạn |
| Financial | doanh thu mất, penalty, liquidity/cash-flow |
| Legal/regulatory | deadline báo cáo, dữ liệu bắt buộc lưu |
| Operational | backlog, capacity và lỗi thủ công |
| Reputation | mất niềm tin, churn, truyền thông tiêu cực |

Không cộng các ordinal label thành một “BIA score” giả chính xác. Ghi threshold và decision consequence rõ hơn màu đỏ/vàng/xanh.

## 8. MTPD/MAO và Minimum Business Continuity Objective

- **MTPD/MAO** là khoảng gián đoạn tối đa có thể chịu trước khi tác động trở nên không chấp nhận được.
- **MBCO** mô tả mức dịch vụ tối thiểu cần duy trì/phục hồi trong disruption.

Ví dụ: service đầy đủ xử lý 10.000 giao dịch/giờ, nhưng trong 8 giờ đầu business chấp nhận MBCO 2.000 giao dịch ưu tiên/giờ,
không cho export/report. Kiến trúc degraded mode từ MBCO thường rẻ và thực tế hơn nhân đôi toàn bộ production.

## 9. Hiểu đúng RTO và RPO

- **RTO (Recovery Time Objective):** thời gian mục tiêu từ disruption tới business service được phục hồi ở mức đã định.
- **RPO (Recovery Point Objective):** khoảng mất dữ liệu theo thời gian tối đa business chấp nhận.

```text
last recoverable point          incident                 service recovered
        |<------ actual data loss ------>|<---- actual recovery time ---->|
```

RTO/RPO là objective, không phải kết quả đo. “Replica lag 5 giây” không chứng minh RPO 5 giây nếu failover sai timeline hoặc dữ liệu
đã corruption. “VM boot trong 2 phút” không chứng minh RTO nếu user chưa hoàn thành transaction.

## 10. Recovery Time Capability và Work Recovery Time

Technology restoration chỉ là một phần:

```text
detection + decision + provisioning + data restore/replay
  + security validation + application validation
    + DNS/client reconnection + backlog/reconciliation = actual recovery
```

Work Recovery Time là thời gian business cần để kiểm tra, xử lý backlog và trở lại mức vận hành yêu cầu. Nếu MTPD là 8 giờ và
business cần 2 giờ reconcile, technology RTO không thể đặt bằng 8 giờ. Dành buffer cho detection/decision và uncertainty.

## 11. Service tier và recovery class

Xây tier từ business outcome, không sao chép theo môi trường:

| Tier ví dụ | MBCO | Strategy gợi ý | Validation |
|---|---|---|---|
| T0 safety/control | gần liên tục | fault-tolerant + independent recovery | frequent end-to-end exercise |
| T1 critical transaction | degraded ngắn | warm/hot standby + PITR | failover/restore định kỳ |
| T2 important internal | manual/read-only tạm | pilot light + backup | restore sampling |
| T3 deferrable | dừng nhiều ngày | rebuild/backup | annual verification |

Tier phải mang requirement và funding khác nhau. Nếu mọi hệ thống đều T0 thì BIA chưa tạo quyết định.

## 12. Dependency graph quyết định recovery sequence

Mỗi service cần map:

- identity, DNS, PKI, time, network và endpoint management;
- compute, storage, queue, database, cache và object store;
- code, artifact registry, IaC/config và CI/CD;
- key, secret, license và certificate;
- telemetry/security controls cần để xác minh sạch;
- supplier, SaaS, telecom, facility và con người;
- downstream consumer và batch/cut-off dependency.

Một topological order kỹ thuật chưa đủ; có dependency vòng và business cut-off. Ghi bootstrap path, alternate source và recovery owner.

## 13. Tìm dependency ẩn và concentration risk

Dependency thường bị bỏ sót: một shared IdP, một cloud organization, một DNS registrar, một KMS key, một admin team, một CI signer
hoặc một MSP phục vụ cả primary lẫn DR. Các cách phát hiện:

- trace transaction và data lineage;
- quan sát network/API/identity use;
- phỏng vấn operator bằng scenario mất dependency;
- game day và restore vào environment mới;
- map supplier subprocessor/fourth party;
- kiểm administrative và recovery dependency.

Hai region không độc lập nếu cùng credential/control plane có thể xóa cả hai.

## 14. Data dependency, consistency và recovery point

Một business transaction có thể ghi database, publish event, cập nhật search index và gọi partner. Recovery từng store tới timestamp
khác nhau tạo state không hợp lệ. Cần xác định:

- system of record và derived/rebuildable data;
- consistency boundary và ordering/idempotency;
- point-in-time/cross-system recovery marker;
- duplicate/missing/ambiguous transaction handling;
- reconciliation source, rule và owner;
- legal/audit evidence không được sửa mất.

RPO cần diễn đạt theo business event, không chỉ bytes/WAL/object timestamp.

## 15. Chọn recovery strategy

Các lựa chọn từ ít đến nhiều capability:

| Strategy | Đặc điểm | Trade-off |
|---|---|---|
| Backup and rebuild | hạ tầng tạo lại, data restore | RTO dài, chi phí standby thấp |
| Pilot light | core data/control tối thiểu luôn tồn tại | cần automate scale-up/test |
| Warm standby | bản thu nhỏ chạy sẵn | capacity/currency cần kiểm chứng |
| Hot active-passive | gần production, nhận replication | nhanh nhưng risk lỗi/compromise lan |
| Active-active | hai nơi phục vụ | routing, consistency, split-brain phức tạp |
| Manual workaround | process thay thế có giới hạn | lỗi người, capacity, privacy và backlog |

Chọn theo scenario và BIA; không mặc định active-active là trưởng thành nhất.

## 16. HA, DR và backup giải các failure khác nhau

| Failure | HA/replica | DR site | Backup/PITR |
|---|---:|---:|---:|
| process/node chết | mạnh | thường không cần | chậm |
| zone/region mất | tùy boundary | mạnh | có thể phục hồi |
| operator xóa dữ liệu | lỗi có thể replicate | lỗi có thể replicate | quay lại trước lỗi |
| ransomware/control-plane compromise | có thể cùng bị chiếm | có thể cùng bị chiếm | tốt nếu isolated/clean |
| latent corruption | lan trước khi phát hiện | có thể lan | cần retention đủ dài |

Defense cần nhiều recovery path không cùng failure/administrative domain.

## 17. Failure domain và redundancy thật

Đánh giá độc lập ở các lớp: nguồn điện, rack/AZ/region, network carrier, cloud account/org, control plane, identity, key, operator,
supplier và jurisdiction. Redundancy chỉ có giá trị khi:

- failure không đồng thời phá cả bản sao;
- capacity dự phòng đủ;
- state đủ mới/nhất quán;
- routing/fencing hoạt động;
- team có quyền và runbook kích hoạt;
- đã test dưới failure tương ứng.

Ba bản sao trong cùng account với cùng delete credential là ba copy, không phải ba trust boundary.

## 18. Graceful degradation và fail-safe business mode

Thay vì toàn bộ service up/down, thiết kế capability giảm cấp:

- read-only thay vì write;
- giới hạn amount/rate/region/customer tier;
- queue durable để xử lý sau;
- cached reference data có TTL và provenance;
- disable export/report/optional integration;
- manual approval cho transaction rủi ro;
- local operation rồi reconcile khi kết nối lại.

Degraded mode cần security invariant. Không bỏ authentication, tenant isolation hoặc safety limit chỉ để đạt availability.

## 19. Manual workaround cũng là một hệ thống

Spreadsheet, giấy, điện thoại hoặc email trong disruption tạo rủi ro mới. Plan cần:

- trigger bật/tắt và capacity thực tế;
- identity/approval/separation of duties;
- mẫu biểu, version và secure distribution;
- bảo vệ personal/sensitive data;
- unique transaction ID và duplicate prevention;
- lưu evidence/audit;
- cách nhập lại và reconcile;
- huấn luyện người thay thế.

Nếu chưa diễn tập với volume thật, manual workaround chỉ là assumption.

## 20. Capacity và thời gian phục hồi

DR capacity phải xét traffic peak, backlog tích lũy, restore throughput và shared dependency. Ví dụ service phục hồi 50% capacity sau
4 giờ nhưng backlog tăng 100% mỗi giờ có thể không bao giờ bắt kịp. Mô hình:

```text
time to usable service + time to drain backlog + reconciliation = time to normal outcome
```

Kiểm quota, IP/DNS, license, storage IOPS, API rate limit, staffing và supplier capacity. Reservation tốn phí nhưng provisioning on-demand
có thể thất bại trong regional disaster khi mọi customer cùng yêu cầu resource.

## 21. Backup scope phải vượt ra ngoài database

Inventory recovery set gồm:

- business data, file/object, event history và metadata;
- schema, migration và compatibility information;
- application source/binary/container artifact cùng provenance;
- IaC, policy, network/DNS config và platform desired state;
- identity directory/config, PKI, certificate và key material phù hợp;
- secret metadata/recovery mechanism, không tùy tiện copy plaintext;
- license, escrow, supplier contact và offline runbook;
- log/audit/evidence cần điều tra và validate clean point.

Backup data mà thiếu key, version tương thích hoặc restore instruction vẫn không tạo recovery capability.

## 22. Thiết kế backup theo failure và threat

Quy tắc 3-2-1 hoặc biến thể 3-2-1-1-0 là heuristic hữu ích, không phải mục tiêu tự thân. Quan trọng hơn là:

- nhiều copy với media/location/failure domain phù hợp;
- ít nhất một copy inaccessible từ production compromise path;
- immutable/offline copy trong retention cần thiết;
- zero unverified error qua integrity và restore test;
- frequency đáp ứng RPO;
- retention bao phủ latent corruption/detection delay;
- catalog biết dependency chain và expiry an toàn.

Snapshot nhanh nhưng nếu nằm cùng account/key/admin boundary thì không chống được mọi scenario.

## 23. Immutability, air gap và delayed deletion

- **Immutable/WORM:** object không sửa/xóa trong retention; vẫn cần bảo vệ policy, tenant và key.
- **Logical air gap:** credential/network/control path tách, chỉ mở workflow hẹp.
- **Physical/offline:** media không kết nối; RTO và logistics thường dài hơn.
- **Delayed deletion/two-person rule:** tạo cửa sổ phát hiện và chặn destructive action.

Immutability không chứng minh dữ liệu sạch: malware, encrypted/corrupt data có thể được ghi bất biến. Cần version history, clean-point analysis
và retention dài hơn attacker dwell time hợp lý.

## 24. Tách identity và control plane của backup

Backup writer chỉ ghi; không nên được xóa lịch sử. Restore reader chỉ được cấp JIT trong recovery environment. Backup admin, key admin,
production admin và retention-policy admin nên tách nhiệm vụ theo risk. Bảo vệ bằng:

- account/tenant/trust domain riêng khi cần;
- phishing-resistant MFA và privileged workstation;
- delete/retention change approval;
- alert độc lập cho policy/coverage/failure;
- break-glass được niêm phong, rotate và test;
- audit copy ngoài blast radius production.

Không để ransomware dùng cùng domain admin xóa production, snapshot và backup catalog.

## 25. Encryption và khả năng khôi phục key

Backup cần mã hóa in transit/at rest, nhưng DR sẽ thất bại nếu key chỉ nằm trong KMS/region/account đã mất. Thiết kế:

- key hierarchy/purpose và owner;
- backup của key material hoặc recovery escrow theo chính sách;
- multi-region/HSM recovery khi phù hợp;
- quorum/dual control cho key recovery;
- certificate, passphrase và tool version cần thiết;
- rotate/revoke mà vẫn giải mã retention hợp lệ;
- test restore bằng identity recovery thật.

Key escrow làm tăng sensitivity; bảo vệ và audit mạnh, không biến thành master-secret ai cũng dùng.

## 26. Application-consistent backup

Crash-consistent snapshot chỉ tương đương mất điện tại một thời điểm; application-consistent backup phối hợp flush/quiesce hoặc transaction
boundary. Với distributed system cần xem:

- database log/checkpoint và transaction đang mở;
- queue offset/message retention;
- object/file ghi dở;
- search/cache/derived state có rebuild được không;
- schema/config/version tại recovery point;
- nhiều datastore có marker hoặc reconciliation plan nào.

Không freeze quá lâu làm production outage. Dùng native backup/PITR và thiết kế idempotent/rebuildable khi atomic snapshot toàn hệ thống không khả thi.

## 27. Backup catalog, chain và retention dependency

Catalog cần biết backup ID, source, time range, type, parent chain, checksum/manifest, encryption key reference, application/schema version,
location, retention/legal hold và restore test gần nhất. Incremental/differential/PITR tạo dependency graph; xóa parent hoặc log segment có thể
làm mọi child vô dụng dù file còn tồn tại.

Retention phải cân bằng recovery window, latent corruption, legal/privacy obligation và chi phí. Expiry là workflow có dependency validation,
không chỉ lifecycle rule theo tuổi object.

## 28. Recovery environment và clean room

Recovery environment nên được dựng từ nguồn tin cậy, cô lập khỏi production bị nghi compromise:

- clean identity/admin workstation;
- known-good DNS, time, PKI, key/secret bootstrap;
- signed IaC, image/artifact và policy baseline;
- network egress/ingress tối thiểu;
- forensic copy tách khỏi restore candidate;
- security telemetry trước khi mở traffic;
- staging zone để scan, validate và reconcile;
- promotion gate có business/security approval.

Không nối bản restore vào production quá sớm; credential cũ, callback, scheduler hoặc malware có thể tái kích hoạt.

## 29. Ransomware và destructive attack khác hardware failure

Trong hardware failure, source thường đáng tin và mục tiêu là nhanh. Trong ransomware:

- attacker có thể còn persistence/privilege;
- backup, hypervisor, IdP, EDR và log đều có thể bị tác động;
- latest copy có thể đã mã hóa/corrupt;
- data có thể bị exfiltrate dù restore thành công;
- containment, eradication và evidence cạnh tranh với RTO;
- recovery quá sớm có thể tái nhiễm.

CISA khuyến nghị offline/encrypted backup và kiểm availability/integrity qua DR scenario. Nhưng backup chỉ giải availability; breach, fraud và notification
vẫn cần incident/crisis workflow.

## 30. Xác định clean point và confidence

Không chọn “backup gần nhất” theo phản xạ. Xây timeline từ:

- first known malicious activity và earliest plausible access;
- identity/config/audit changes;
- malware/persistence/IOC observation;
- backup creation/replication log và integrity signal;
- application invariant và historical baseline;
- threat-hunt scope cùng confidence/unknown.

Có thể chọn restore point cũ hơn rồi replay transaction sạch có kiểm soát. Ghi loss window, excluded data, confidence và authority chấp nhận; clean point là
quyết định dựa trên evidence, không phải timestamp thần kỳ.

## 31. Rebuild, restore hay repair?

| Cách | Khi phù hợp | Rủi ro |
|---|---|---|
| Rebuild từ known-good source | OS/workload/config có IaC/artifact tin cậy | mất local state, dependency bootstrap |
| Restore data vào clean platform | data quan trọng, platform bị nghi ngờ | compatibility, credential/persistence trong data |
| In-place repair | compromise được giới hạn và evidence mạnh | khó chứng minh sạch, nhanh nhưng residual risk cao |
| Recreate + reconcile | derived/state phân tán | duplicate/missing/business invariant |

Sau cyber compromise, ưu tiên rebuild immutable infrastructure hơn “quét sạch” host. Nhưng data/application migration phải được rehearsal để RTO thực tế.

## 32. Bootstrap identity, DNS, PKI, secrets và time

Đây là “hệ thống phục hồi hệ thống” và thường tạo dependency vòng. Cần offline/independent procedure để:

1. xác minh recovery personnel;
2. tạo clean administrative identity;
3. khôi phục authoritative time/DNS tối thiểu;
4. thiết lập PKI/KMS/trust anchor;
5. truy cập signed IaC/artifact và backup catalog;
6. phát hành credential mới, không hồi sinh credential đã compromise;
7. rotate trust trước khi reconnect workload;
8. thu hồi temporary recovery access sau sự cố.

Break-glass phải được drill; phong bì hoặc secret chưa từng mở không phải capability đã kiểm chứng.

## 33. Cloud shared responsibility và tenant-level disaster

Cloud provider thường chịu trách nhiệm hạ tầng; customer vẫn sở hữu configuration, identity, data, backup policy và kiến trúc multi-region/account. Hỏi:

- service là zonal, regional hay global control plane;
- provider backup có bảo vệ customer deletion/ransomware không;
- snapshot/copy/key/account có cùng administrative boundary;
- quota và service availability ở recovery region;
- IaC/state/artifact nằm ngoài tenant bị mất chưa;
- support/escalation và account recovery đã test chưa;
- egress/restore throughput và cost có đáp ứng RTO không.

Multi-AZ không đồng nghĩa DR; multi-region cũng không chữa compromise toàn organization.

## 34. SaaS và supplier continuity

“Vendor chịu trách nhiệm” không loại bỏ business impact. Due diligence/contract cần:

- availability, RTO/RPO và dữ liệu đo/credit;
- backup/restore, cyber recovery và test evidence;
- data export format/frequency và customer-managed copy;
- identity/admin/break-glass boundary;
- subprocessor/concentration/location;
- incident notification và coordination;
- insolvency/termination/exit, escrow khi phù hợp;
- manual/alternate provider strategy.

Vendor SLA 99,9% mô tả availability trung bình, không hứa phục hồi dữ liệu của riêng tenant sau xóa nhầm.

## 35. Multi-region, hybrid và data sovereignty

Chọn region/site dựa trên failure correlation, latency, data residency, legal restriction, workforce và supplier—not chỉ khoảng cách địa lý.
Kiến trúc cần:

- replication mode và actual lag;
- read/write ownership;
- routing/health semantics;
- key/log/backup residency;
- capacity/quota/reservation;
- cross-border approval;
- operation khi WAN/control plane mất;
- consistent security baseline và evidence.

Hybrid có thể tạo diversity nhưng cũng tăng skill/tool/dependency. Chỉ credit nếu team đã phục hồi workload thật trên target khác biệt.

## 36. Reconciliation sau phục hồi

Failover/PITR có thể tạo transaction ambiguous: client timeout nhưng write đã commit, event phát nhưng downstream chưa nhận hoặc partner xử lý khác timeline.
Reconciliation cần:

- stable business transaction ID và idempotency key;
- ledger/source-of-truth xác định;
- compare window theo RPO/failover time;
- duplicate/missing/conflict rule;
- customer/partner confirmation khi cần;
- approval cho financial/data correction;
- immutable audit của adjustment;
- backlog capacity và completion criterion.

Service “HTTP 200” chưa phục hồi nếu balance/order/payroll sai.

## 37. Failover, fencing và failback

Failover runbook phải ngăn hai writer cùng hoạt động:

1. xác định source state và quyền quyết định;
2. fence/disable old primary khi có thể;
3. ghi recovery point và potential data-loss window;
4. promote/restore target;
5. đổi route, credential và dependency;
6. validate technical + business synthetic transaction;
7. mở traffic theo wave;
8. theo dõi/reconcile.

Failback là một migration rủi ro riêng: đồng bộ delta, fence, chuyển route, xác minh và rollback. Không tự động quay về chỉ vì primary site sống lại.

## 38. Recovery runbook có thể thực thi

Runbook tốt có prerequisite, role/authority, input, lệnh/action, expected output, validation, timeout, branch, rollback và escalation. Nó phải truy cập được
khi wiki/SSO/VPN mất, nhưng offline copy vẫn được kiểm soát/versioned.

```text
Step 12: restore catalog version X
expected: manifest signature valid; chain complete
if invalid: STOP → evidence lead + recovery lead
evidence: recovery-case/<id>/catalog-validation.json
```

Tách orchestration khỏi decision: tự động hóa bước lặp lại, nhưng data-loss/failover/public-impact decision cần đúng authority.

## 39. Crisis command và nhịp vận hành

Thiết lập một command structure với:

- incident/crisis commander và deputy;
- operations, security, business, legal/privacy, communication và supplier leads;
- objective cho mỗi operational period;
- situation report từ single source of truth;
- decision log: thời gian, options, owner, rationale;
- meeting cadence không làm kỹ sư mất hết thời gian;
- handover giữa ca và fatigue management;
- criterion chuyển từ response sang recovery/normal operations.

Chat room không phải command system nếu không ai có quyền quyết và action không có owner.

## 40. Communication, legal và stakeholder

Chuẩn bị template/channel/approval cho employee, customer, regulator, law enforcement, insurer, supplier, board và media. Message phải phân biệt:

- điều đã biết, chưa biết và đang xác minh;
- service impact/workaround;
- data/confidentiality impact;
- action người nhận cần thực hiện;
- thời điểm cập nhật tiếp theo;
- contact/source chính thức.

Không hứa RTO chưa kiểm chứng hoặc nói “không có data breach” khi investigation chưa đủ. Out-of-band channel và contact list cần offline copy, privacy protection
và định kỳ test.

## 41. People, facility và workforce continuity

Technology phục hồi nhưng team không có người/quyền/thiết bị vẫn thất bại. Plan cần:

- role tối thiểu và cross-training/succession;
- alternate workspace, remote access và clean endpoint;
- health/safety, transport, utility và geographic concentration;
- shift/handover, nghỉ ngơi và mental-health support;
- contractor/MSP availability;
- physical access, badge, key và hardware logistics;
- payroll/HR/emergency contact continuity.

Không giả định cùng một chuyên gia có thể đồng thời điều tra incident, restore database và báo cáo executive suốt 24 giờ.

## 42. Các cấp độ exercise

| Loại | Chứng minh điều gì | Không chứng minh |
|---|---|---|
| Document review/walkthrough | plan có đủ và người hiểu vai trò | hệ thống hoạt động |
| Tabletop | decision, coordination, assumption | restore/failover kỹ thuật |
| Functional drill | một capability chạy thật | toàn business service |
| Parallel test | DR chạy song song, hạn chế impact | production cutover đầy đủ |
| Full interruption | end-to-end chuyển thật | mọi scenario khác |
| Component/restore test | backup/dependency cụ thể | customer outcome toàn chuỗi |

Xây chương trình kết hợp nhiều loại theo criticality và safety, không dùng tabletop để tuyên bố RTO đạt.

## 43. Thiết kế exercise có học được

Mỗi exercise cần hypothesis, scope, scenario/inject, objective, safety guardrail, participant, observer, evidence và success criterion. Kịch bản nên tạo lựa chọn khó:

- backup mới nhất bị nghi compromise;
- IdP và primary region cùng mất;
- key holder không sẵn sàng;
- supplier không trả lời;
- customer data có thể đã exfiltrate;
- DR capacity chỉ đạt 40%;
- business cut-off sắp tới.

Không viết scenario để team chắc chắn “pass”. Mục tiêu là tìm assumption sai an toàn trước sự cố.

## 44. Fault injection và resilience engineering

Fault injection kiểm một hypothesis trong blast radius giới hạn: kill node, chặn dependency, làm credential hết hạn, tăng latency, làm restore catalog unavailable.
Cần steady-state metric, precondition, kill switch, rollback và stakeholder approval.

Cyber-resilience test còn giả định control hoặc identity bị compromise, không chỉ unavailable. Không chạy phá hoại production nếu chưa có containment và authority;
bắt đầu lab/staging, sau đó tăng realism. Chaos tool không thay business exercise hay clean-recovery drill.

## 45. Đo actual RTO/RPO và recovery quality

Ghi timeline bằng timestamp chung:

```text
incident start → detection → declaration → decision → restore start
→ data available → security validated → business validated
→ traffic opened → backlog cleared → normal operations
```

Actual RPO đo bằng business records/events mất hoặc cần reconcile, không chỉ storage timestamp. Ngoài tốc độ, đo integrity, security, capacity, customer outcome,
manual error và residual backlog. Báo objective, actual, scope, percentile/worst case và confidence; tránh một lần test đẹp thành cam kết chung.

## 46. Evidence và assurance cho recovery

Evidence hữu ích gồm:

- BIA/plan version, owner và approval;
- dependency/backup coverage với mẫu số;
- immutable/retention/config effective state;
- manifest/checksum/signature và restore log;
- key/identity recovery test;
- recovery environment provenance;
- business invariant/reconciliation result;
- actual RTO/RPO timeline;
- exercise finding, owner, due date và retest;
- supplier assurance và exception.

“Backup job succeeded” chỉ chứng minh một job báo success. Assurance cần design, implementation và operating effectiveness trong scenario phù hợp.

## 47. Plan maintenance và trigger thay đổi

Continuity artifacts phải đổi cùng hệ thống. Trigger review khi:

- service owner/tier/impact tolerance đổi;
- kiến trúc, region/account, data store hoặc identity/control plane đổi;
- supplier/subprocessor/contract đổi;
- schema, key, encryption, retention hoặc backup engine đổi;
- incident/exercise phát hiện assumption sai;
- M&A, office/workforce hoặc obligation đổi;
- runbook chưa chạy trong thời hạn quy định.

Plan-as-code giúp review/diff/test link nhưng không thay business approval. Tự động kiểm stale owner, broken dependency và overdue exercise.

## 48. Roadmap và maturity

Một lộ trình thực tế:

```text
Wave 0: service owner + BIA tối thiểu + critical dependency inventory
Wave 1: protected backup + identity/key bootstrap + restore drills
Wave 2: tiered recovery strategies + executable runbooks + crisis coordination
Wave 3: end-to-end failover/reconciliation + supplier/workforce continuity
Wave 4: clean-room automation + continuous evidence + resilience engineering
```

Ưu tiên theo mission impact, exposure, concentration và capability gap. Metric trưởng thành: % critical service có BIA được duyệt, dependency/backup coverage,
restore success, actual RTO/RPO, reconciliation time, overdue actions—not số trang plan hoặc số TB backup.

## 49. Ví dụ end-to-end: ransomware vào nền tảng đơn hàng

**Scenario:** attacker chiếm privileged identity, mã hóa database primary và xóa online snapshots; có dấu hiệu exfiltration.

1. IR cô lập account/network, bảo toàn evidence; crisis lead kích hoạt structure và communication cadence.
2. Business owner kích hoạt MBCO: nhận đơn ưu tiên qua channel hẹp, cấp unique ID, dừng export/refund tự động.
3. Identity team tạo clean admin domain; rotate trust, không dùng credential production cũ.
4. Recovery team dựng clean room từ signed IaC/artifact, bật telemetry trước connection.
5. Hunt/timeline chọn immutable backup trước earliest plausible compromise với confidence ghi rõ.
6. Restore database, replay clean event có provenance; scan và kiểm schema/invariant.
7. Khôi phục dependency theo order DNS/PKI/key/queue/application; partner callback vẫn bị chặn.
8. Business reconcile order/payment window, xử lý duplicate/ambiguous transaction và phê duyệt adjustment.
9. Mở traffic canary, theo dõi reinfection/fraud/capacity rồi tăng dần.
10. Ghi actual RPO/RTO, backlog-clear time, data-breach decision và residual unknown.
11. Failback chỉ sau khi primary trust boundary được rebuild; rotate temporary recovery access.
12. Corrective action sửa shared admin, snapshot isolation, detection gap và exercise coverage; retest có deadline.

Kết quả không chỉ là database online, mà là đơn hàng đúng, attacker bị loại, customer được thông tin và operation trở lại có kiểm chứng.

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] BC/DR/IR/crisis plan có scope, activation, authority, handoff và owner rõ.
- [ ] BIA bắt đầu từ business service/outcome và impact tăng theo thời gian.
- [ ] MBCO, MTPD/MAO, RTO/RPO có căn cứ, scope và business approval.
- [ ] Dependency graph gồm identity, DNS, PKI, KMS, artifact, people, facility và supplier.
- [ ] Recovery sequence giải dependency vòng và có bootstrap path độc lập.
- [ ] HA/replica, DR và backup được credit đúng failure scenario.
- [ ] Backup scope gồm data, config, code/artifact, key recovery và offline runbook.
- [ ] Có immutable/offline copy, retention đủ và control/identity tách blast radius.
- [ ] Restore kiểm integrity, compatibility, security và business invariant—not chỉ mount/start.
- [ ] Cyber recovery có clean point analysis, clean room và credential/trust rotation.
- [ ] Failover có fencing; failback/reconciliation được coi là operation riêng.
- [ ] Manual/degraded mode giữ security/safety invariant và đã capacity-test.
- [ ] Crisis communication có out-of-band channel, approval và known/unknown rõ.
- [ ] Exercise kết hợp tabletop, functional restore và end-to-end theo criticality.
- [ ] Actual RTO/RPO/backlog/reconciliation được đo; finding có owner và retest.

### Anti-pattern thường gặp

- “Backup job xanh nên recovery đã sẵn sàng.”
- “Replica hoặc multi-AZ thay thế backup.”
- “Multi-region chắc chắn độc lập” dù cùng identity/control plane.
- “RTO là thời gian VM/database khởi động.”
- “RPO bằng replication lag trung bình.”
- “Mọi hệ thống đều critical/Tier 0.”
- “Immutable backup chắc chắn sạch.”
- “Restore gần nhất luôn tốt nhất khi bị ransomware.”
- “Failover xong khi health check trả 200.”
- “Tabletop pass chứng minh restore kỹ thuật hoạt động.”
- “Manual workaround không cần authorization/audit.”
- “Vendor SLA chịu toàn bộ continuity risk.”

### Tài liệu chính thức

- [NIST SP 800-34 Rev. 1 – Contingency Planning Guide](https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final)
- [NIST SP 800-184 – Guide for Cybersecurity Event Recovery](https://csrc.nist.gov/pubs/sp/800/184/final)
- [NIST SP 800-160 Vol. 2 Rev. 1 – Developing Cyber-Resilient Systems](https://csrc.nist.gov/pubs/sp/800/160/v2/r1/final)
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [NIST IR 8374 Rev. 1 – Ransomware Risk Management: CSF 2.0 Community Profile](https://csrc.nist.gov/pubs/ir/8374/r1/final)
- [CISA #StopRansomware Guide](https://www.cisa.gov/stopransomware/ransomware-guide)
- [CISA Cross-Sector Cybersecurity Performance Goals](https://www.cisa.gov/cross-sector-cybersecurity-performance-goals)

### Học tiếp

1. [Third-Party & SaaS Security Assurance](../third_party/third_party_saas_security_assurance.md) – due diligence, continuous monitoring, shared responsibility,
   contract/evidence, concentration risk và exit planning.
2. [Security Architecture Review & Design Governance](../architecture/security_architecture_review_design_governance.md) – review gates, ADR, reference pattern,
   exception và architecture fitness functions.

---

*Cập nhật lần cuối: 2026-08-03.*
