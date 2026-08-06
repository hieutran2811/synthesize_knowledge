# Data Security & Privacy Engineering – Bảo vệ dữ liệu xuyên suốt vòng đời

Data security trả lời “làm sao ngăn truy cập, sửa đổi hoặc phá hủy trái phép?”. Privacy engineering
còn hỏi “có nên xử lý dữ liệu này không, vì mục đích nào, cá nhân có thể hiểu và kiểm soát điều gì,
và việc xử lý có gây hậu quả ngoài mong đợi không?”. Một hệ thống có thể mã hóa rất tốt nhưng vẫn
xâm phạm privacy vì thu thập quá nhiều, giữ quá lâu hoặc dùng sai mục đích.

```text
discover → classify → define purpose → collect minimum → protect/use/share
   ↑                                                     ↓
   └──── inventory + lineage + audit ← retain/delete ────┘
```

Tài liệu này là hướng dẫn kỹ thuật, không phải tư vấn pháp lý. Định nghĩa dữ liệu cá nhân, lawful
basis, quyền của chủ thể, thời hạn và nghĩa vụ thông báo khác nhau theo quốc gia/ngành. Engineering
requirement phải được xác nhận với privacy/legal owner phù hợp.

---

## 1. Data security và privacy có phần giao nhưng không đồng nhất

| Tình huống | Security | Privacy |
|---|---|---|
| Attacker lấy hồ sơ khách hàng | Breach confidentiality | Gây hại cho cá nhân |
| Product thu location liên tục dù không cần | Có thể không có breach | Over-collection/purpose problem |
| User không thể sửa dữ liệu sai | Integrity có thể vẫn tốt | Thiếu manageability/accuracy |
| Dataset “ẩn tên” nhưng tái nhận dạng được | Access có thể đúng policy | De-identification thất bại |
| Log đầy đủ mọi request body | Hữu ích điều tra nhưng tăng attack surface | Minimization/retention problem |

Security bảo vệ dữ liệu khỏi action trái phép; privacy còn quản lý action được phép nhưng gây hậu
quả bất lợi hoặc vượt expectation hợp lý.

## 2. Ba privacy engineering objective của NIST

NIST IR 8062 đề xuất ba objective bổ sung cho CIA:

- **Predictability**: cá nhân, owner và operator có thể hình thành kỳ vọng đáng tin về dữ liệu được
  xử lý thế nào;
- **Manageability**: có khả năng quản trị granular việc alteration, deletion và selective disclosure;
- **Disassociability**: xử lý dữ liệu/sự kiện mà không gắn với cá nhân hoặc thiết bị ngoài mức cần
  cho operation.

Ví dụ privacy notice giúp predictability, subject-right workflow giúp manageability, scoped
pseudonym/differential privacy hỗ trợ disassociability. Không objective nào thay thế security.

## 3. Phân biệt các loại dữ liệu

| Loại | Ví dụ | Ghi chú |
|---|---|---|
| Personal data/PII | email, device ID, location, customer ID | Có thể nhận dạng trực tiếp hoặc gián tiếp tùy context/law |
| Sensitive personal data | health, biometric, government ID | Thường cần control/điều kiện xử lý cao hơn |
| Confidential business data | source code, pricing, strategy | Nhạy cảm nhưng không nhất thiết là personal data |
| Secret/credential | password, API key, private key | Dùng để chứng minh quyền hoặc thực hiện crypto operation |
| Public data | public documentation | Không cần secrecy nhưng cần integrity/licensing |
| Derived/inferred data | risk score, preference, segment | Có thể nhạy cảm dù không do cá nhân trực tiếp cung cấp |

Đừng chỉ scan field tên `email`. Free text, image, voice, IP, telemetry và tổ hợp quasi-identifier
cũng có thể nhận dạng con người.

## 4. Vòng đời dữ liệu thực tế

```text
source/subject
  → collect/import
  → validate/normalize/enrich/infer
  → transactional store/cache/search index
  → event/log/analytics/ML feature
  → share/export/processor
  → archive/backup
  → delete/anonymize
```

Mỗi nhánh tạo bản sao có owner, purpose, retention và control riêng. Xóa row trong primary database
không xóa search index, data lake, dead-letter queue, log, export đã tải hay backup.

## 5. Data inventory và record of processing

Inventory không nên là danh sách table đơn thuần. Record tối thiểu:

| Metadata | Ví dụ |
|---|---|
| Dataset/field ID | `customer.email.v2` |
| Business/data owner | Customer Platform |
| Subject/category | customer contact data |
| Source/provenance | signup form, verified by user |
| Purpose | transactional notification |
| Applicable basis/policy | policy ID do privacy/legal xác nhận |
| Classification | confidential-personal |
| Systems/copies | OLTP, event, cache, warehouse |
| Recipients/processors | email provider |
| Region/residency | EU project/region |
| Access roles | notification service, support masked view |
| Retention/deletion | account lifetime + approved period |
| Protection | TLS, field encryption, masking |
| Subject rights | access, correct, delete rules |

Không lưu raw personal data trong catalog metadata nếu ID/reference đã đủ.

## 6. Ownership: owner, steward, custodian và processor

- Data owner quyết định purpose, classification, access và retention theo policy.
- Data steward duy trì definition, quality, lineage và usage rule.
- System custodian vận hành storage, backup, access control và deletion job.
- Privacy/legal owner giải thích obligation/policy theo jurisdiction.
- Security owner thiết kế protection/detection.
- Processor/third party xử lý theo contract/instruction và cần assurance riêng.

Một ticket “xóa dữ liệu” không thể hoàn tất nếu không rõ ai chịu trách nhiệm cho warehouse, backup
và SaaS downstream.

## 7. Data classification phải dẫn đến control

Ví dụ scheme đơn giản:

| Class | Ví dụ | Control baseline |
|---|---|---|
| Public | tài liệu công khai | Integrity, publishing approval |
| Internal | runbook không nhạy cảm | Workforce access, no public share |
| Confidential | contract, customer profile | Least privilege, encryption, audit, DLP |
| Restricted | health, payment, key material | Strong isolation, JIT, field protection, enhanced monitoring |

Classification label vô ích nếu CI, database, log pipeline và export gateway không thực thi. Tách
data sensitivity khỏi criticality/availability; một public status page vẫn có availability cao.

## 8. Context và tổ hợp làm thay đổi độ nhạy cảm

Một giá trị có thể không nhận dạng riêng lẻ nhưng tổ hợp lại có thể:

```text
postal code + birth date + gender + timestamp + rare event
```

Sensitivity còn phụ thuộc:

- số lượng record và thời gian lịch sử;
- khả năng join với public/commercial dataset;
- độ hiếm và granularity;
- subject là trẻ em/vulnerable group;
- use context và decision downstream;
- credential/lookup table tồn tại ở nơi khác;
- dữ liệu inferred có thể tiết lộ thuộc tính nhạy cảm.

Classify dataset/flow, không chỉ field độc lập.

## 9. Purpose catalog và lawful processing rule

Engineering nên dùng stable purpose ID thay vì free text:

```yaml
purpose: transactional_order_updates
data:
  - customer.contact.email
recipients:
  - notification-service
allowed_actions: [send_order_status]
prohibited_actions: [advertising_profile]
retention_policy: RET-CUSTOMER-CONTACT-03
policy_basis: PRIVACY-POLICY-17
```

Under GDPR, consent chỉ là một trong nhiều lawful basis; không hardcode “mọi xử lý cần consent”.
Rule engine/config cần phản ánh jurisdiction, subject, purpose và policy đã được phê duyệt.

## 10. Data minimization là control mạnh nhất

Thứ tự câu hỏi:

1. Có cần thu dữ liệu này để đạt purpose không?
2. Có thể derive tạm thời thay vì lưu không?
3. Có thể dùng coarse value, aggregate hoặc boolean không?
4. Có thể tách identity khỏi event không?
5. Có thể giảm sample rate, precision hoặc retention không?
6. Có thể xử lý client/on-device không?

Dữ liệu không thu thập thì không cần encrypt, respond trong breach hay tìm khắp backup để xóa.

## 11. Collection, notice và privacy-friendly default

Collection flow cần:

- notice đúng thời điểm, ngôn ngữ dễ hiểu và không che purpose quan trọng;
- required field tách optional field;
- privacy-protective default, không preselect chia sẻ không cần thiết;
- lựa chọn granular theo purpose khi policy yêu cầu;
- không dùng deceptive/dark pattern ép đồng ý;
- ghi version notice/policy và event thay đổi preference;
- validate source, accuracy, age/guardian rule khi áp dụng;
- fallback khi user không đồng ý optional processing.

UI là một phần của privacy architecture, không chỉ văn bản pháp lý.

## 12. Data contract phải mang metadata bảo vệ

Schema/event contract nên có:

```yaml
field: customerEmail
type: string
classification: confidential-personal
purpose: transactional_order_updates
retention: P30D-after-delivery
loggable: false
exportable: false
tenant_binding: required
owner: customer-platform
```

Registry/linter có thể chặn field restricted đi vào public topic/log sink. Metadata không thay
runtime control nhưng giúp propagation, review và automation.

## 13. Lineage và provenance

Lineage trả lời:

```text
field/source → transformation → dataset → dashboard/model/export → recipient
```

Cần biết:

- nguồn và thời điểm thu;
- schema/version/quality;
- transformation/inference;
- subject/tenant association;
- purpose và policy áp dụng;
- bản sao downstream;
- ai truy cập/chia sẻ;
- deletion/correction propagation;
- model/report nào bị ảnh hưởng khi data sai hoặc bị rút.

Không có lineage, impact assessment và subject-right response chỉ là phỏng đoán.

## 14. Data discovery và classification scanning

Scan database, object store, warehouse, file share, SaaS, image và log để tìm shadow data. Kết hợp:

- dictionary/pattern cho identifier đã biết;
- checksum/validation cho structured identifiers;
- entropy/context cho secret;
- schema/tag/catalog metadata;
- ML/entity recognition cho free text;
- sample có kiểm soát và human review;
- custom detector cho business-specific ID.

Scanner có false positive/negative và chính nó có quyền đọc dữ liệu lớn. Hạn chế sample/output,
redact finding, audit access và không copy raw value vào ticket.

## 15. Data-centric access control

Quyết định nên xét:

```text
subject + action + data class + purpose + tenant + environment + context
```

Ví dụ analyst được đọc aggregate cho fraud investigation nhưng không export raw contact data.
Áp least privilege, purpose-bound role/attribute, JIT cho restricted data, row/column policy và
approval cho bulk export. Database grant, application authorization và warehouse policy phải khớp;
read replica/debug tool không được trở thành bypass.

## 16. Multi-tenant isolation theo mọi bản sao

Tenant context phải đi qua:

- transaction/query và row-level policy;
- cache key, search filter và object path;
- message/topic/partition và dead-letter queue;
- data lake/warehouse/report;
- backup/restore/export;
- encryption context/DEK boundary;
- audit và subject request.

Không tin tenant ID do client gửi nếu server derive được từ verified identity/resource. Test cả
cross-tenant read, write, inference, count/timing và noisy-neighbor.

## 17. Bảo vệ data at rest, in transit và in use

| Trạng thái | Control ví dụ | Giới hạn |
|---|---|---|
| At rest | disk/db/object encryption | App/DB reader hợp lệ vẫn thấy plaintext |
| In transit | TLS/mTLS, message signature | Endpoint compromise vẫn đọc được |
| In use | process isolation, TEE/confidential compute | Side channel, attestation và app bug vẫn tồn tại |

Encryption phải đi cùng authorization, key separation, integrity, backup, logging và deletion.
Không gọi base64, hashing không key hoặc obfuscation là encryption.

## 18. Key management quyết định chất lượng encryption

Thiết kế cần xác định:

- key purpose và owner;
- KEK/DEK hierarchy, algorithm và authenticated context;
- scope per environment/service/tenant/data class;
- who can encrypt/decrypt và ai quản trị policy;
- rotation, rewrap/re-encrypt và compromise response;
- backup/recovery/destruction;
- audit không chứa plaintext/key.

Xem [Secrets & Key Management §18–25](../secrets/secrets_key_management.md). Encrypt data nhưng lưu
key cạnh database dưới cùng credential chỉ chuyển vị trí rủi ro.

## 19. Field-level encryption và searchable data

Field encryption hữu ích khi muốn tách DB operator/backup khỏi plaintext. Trade-off:

- query/index/sort/unique constraint khó hơn;
- application cần decrypt permission và cache;
- rotation/migration phức tạp;
- ciphertext length/metadata vẫn leak;
- deterministic encryption leak equality/frequency;
- blind index/HMAC trên low-entropy field có thể bị dictionary attack;
- tenant/context binding phải chống ciphertext swapping.

Dùng reviewed library/provider pattern, AEAD và versioned envelope. Không tự thiết kế searchable
encryption để “giữ nguyên mọi query”.

## 20. Pseudonymization

Pseudonym thay direct identifier bằng giá trị khác nhưng vẫn có thể liên kết lại bằng lookup/key
hoặc thông tin bổ sung:

```text
customer_id ── scoped keyed transform/token vault ──> analytics_subject_id
```

Nguyên tắc:

- mapping/key tách khỏi dataset và access khác nhau;
- pseudonym scope theo purpose/dataset để tránh cross-context linking;
- domain separation và key rotation có kế hoạch;
- low-entropy identifiers cần chống brute force, không dùng hash trần;
- delete/relink workflow và collision semantics rõ;
- pseudonymized data vẫn thường được xem là personal data, không phải anonymous.

## 21. Tokenization

Tokenization thay dữ liệu nhạy cảm bằng token không mang ý nghĩa trực tiếp; token vault hoặc
provider giữ mapping. Phù hợp payment/reference workflow khi nhiều system chỉ cần opaque reference.

Rủi ro:

- tokenization service là high-value control plane;
- format-preserving token có thể bị dùng nhầm như giá trị thật;
- token ổn định cho phép correlation;
- detokenize permission quá rộng;
- backup/DR của mapping quyết định recoverability;
- log/export có thể chứa cả token và plaintext do lỗi integration.

Token không tự anonymous nếu hệ thống có thể relink hoặc dataset khác suy ra identity.

## 22. Masking và redaction

| Kỹ thuật | Mục tiêu | Ví dụ |
|---|---|---|
| Display masking | Giảm shoulder-surfing/support exposure | `jo***@example.com` |
| Dynamic masking | View theo role/context | analyst thấy partial value |
| Static masking | Tạo non-production copy | thay giá trị trước khi export |
| Redaction | Loại trường/đoạn khỏi output | bỏ request body khỏi log |

Masking presentation không bảo vệ original store. Static masking phải giữ semantic cần test mà
không bảo toàn identifier thật. Regex đơn lẻ không đủ cho nested JSON, free text, image hoặc stack
trace.

## 23. De-identification và anonymization không phải thao tác một lần

De-identification là quá trình giảm association với subject; mức đủ an toàn phụ thuộc release model,
attacker knowledge và khả năng join. Cần:

1. xác định use/release model;
2. nhận diện direct/quasi/sensitive attribute;
3. chọn transform/access environment;
4. đo utility và re-identification risk;
5. independent review/red-team khi impact cao;
6. contract/access/query control;
7. theo dõi dataset bên ngoài và risk thay đổi.

Xóa tên/email chưa làm dataset anonymous nếu location/timestamp/rare attributes vẫn nhận dạng.

## 24. K-anonymity và các giới hạn

K-anonymity yêu cầu mỗi tổ hợp quasi-identifier giống ít nhất `k` record trong release. Nó có thể
giảm singling-out nhưng:

- không đảm bảo sensitive value đa dạng trong group;
- background knowledge vẫn suy ra;
- high-dimensional/sparse data khó anonymize mà giữ utility;
- nhiều release có thể bị composition/linkage;
- không có universal `k` bảo đảm mọi context.

`l`-diversity/`t`-closeness giải một số vấn đề nhưng vẫn cần threat model và governance. Không tuyên
bố anonymous chỉ vì tool báo một chỉ số.

## 25. Differential privacy

Differential privacy (DP) định lượng mức thay đổi output khi dữ liệu của một cá nhân được thêm/bớt.
Triển khai đúng cần:

- adjacency definition và protected unit rõ;
- epsilon/delta có interpretation và policy;
- sensitivity/clipping/bounds trước khi thêm noise;
- privacy budget theo query, analyst, dataset và thời gian;
- composition accounting giữa nhiều release;
- secure randomness và implementation review;
- chống differencing/repeated-query/budget bypass;
- utility/error communication cho consumer.

“Thêm noise” không tự tạo DP. NIST SP 800-226 cung cấp cách đánh giá guarantee và hazard triển khai.

## 26. Synthetic data không mặc định riêng tư

Model có thể memorize hoặc tạo record gần training subject. Đánh giá:

- membership/inference/reconstruction risk;
- nearest-neighbor và rare record leakage;
- prompt/query extraction nếu generator được expose;
- bias và utility theo use case;
- provenance/license/consent của training data;
- release access và downstream combination;
- liệu training có DP guarantee được review hay không.

Không dùng synthetic data để né governance; nó là derived dataset có owner, purpose và retention.

## 27. Privacy-Enhancing Technologies và trade-off

| PET | Hữu ích khi | Giới hạn chính |
|---|---|---|
| Secure aggregation/MPC | nhiều bên tính toán không chia raw input | protocol, collusion, cost |
| Homomorphic encryption | tính toán hạn chế trên ciphertext | performance, operation support |
| TEE/confidential compute | cô lập data in use | attestation, side channel, provider trust |
| Federated learning | giữ raw training data phân tán | update leakage, poisoning, coordination |
| Differential privacy | statistical output/model | budget, utility và implementation |
| Tokenization/pseudonymization | tách identity khỏi processing | relink/control-plane risk |

Chọn PET sau khi xác định purpose, adversary và output; đừng chọn vì tên công nghệ.

## 28. Log, trace và metric là một data product

Thiết kế telemetry bằng allowlist:

- log event type, opaque actor/resource reference, outcome, reason code, correlation ID;
- không log password, token, session ID, key, request body hoặc restricted PII;
- strip query/fragment và sanitize header/error/stack trace;
- tracing baggage không mang personal data qua mọi service;
- metric label không chứa email, customer ID hoặc high-cardinality value;
- access/retention/export của log theo classification;
- test redaction trước collector, không chỉ ở dashboard;
- debug mode có expiry, approval và safe sampling.

Log centralization làm tăng cả detection value và breach blast radius.

## 29. Cache, index, queue và temporary data

Những bản sao thường bị quên:

- cache value/key và eviction/TTL;
- browser/CDN/proxy cache header;
- search index/highlight/suggestion;
- queue retry/dead-letter và message replay;
- temporary file/swap/core dump;
- notebook/extract/local developer copy;
- materialized view/CDC stream;
- email/support attachment.

Propagation correction/deletion cần stable subject/data ID. TTL chỉ tự xóa khi mọi layer thật sự
enforce và không có refresh vô hạn.

## 30. Data lake, warehouse và analytics

- Landing zone không phải vùng “tạm nên ít bảo vệ”.
- Raw, curated và serving zone cần purpose/classification/access khác nhau.
- Analyst không dùng shared account; query/export được audit.
- Row/column policy và tenant filtering áp cả view/materialization.
- Notebook/result/download có retention và egress control.
- Catalog/lineage nối dashboard/model về source.
- Aggregate nhỏ/rare segment có thể leak cá nhân; threshold/DP khi phù hợp.
- Test data không sao chép production PII mặc định.
- Schema-on-read không được trở thành classification-never.

## 31. Data sharing, API và export

Trước khi chia sẻ:

```text
recipient identity + approved purpose + minimum fields + policy/contract
  → transform/de-identify
  → authorize + rate/volume limit
  → secure delivery
  → receipt/audit + expiry/deletion obligation
```

Bulk export khác risk với single-record API. Dùng asynchronous approval/JIT, watermark/canary khi
phù hợp, signed URL ngắn hạn, download limit và anomaly detection. Không gửi attachment nhạy cảm
qua email/chat chỉ vì recipient “nội bộ”.

## 32. Third party và downstream processor

Inventory cần subprocessor và onward transfer. Trước/onboarding:

- purpose, fields, region, retention và deletion contract;
- security/privacy assurance và incident notification path;
- access identity, key ownership và support/admin model;
- API/log/backup/subprocessor behavior;
- subject-right/correction/deletion SLA;
- export/portability và termination plan;
- evidence xóa dữ liệu khi offboard;
- ongoing change/review, không chỉ questionnaire một lần.

Mã hóa trước khi gửi không giúp nếu processor cần plaintext để xử lý; minimization/tokenization có
thể giảm exposure.

## 33. Residency và cross-border processing

Data location gồm primary, replica, backup, log, support access, CDN và subprocessor—not chỉ region
của database. Thiết kế:

- policy matrix theo data class/subject/purpose/region;
- placement guardrail trong IaC;
- region-aware key/identity/access/log;
- egress/share approval;
- support/remote access location;
- failover không tự động vi phạm placement;
- lineage chứng minh nơi dữ liệu đã đi;
- legal owner xác nhận transfer mechanism/yêu cầu hiện hành.

Residency không đồng nghĩa sovereignty hay đủ compliance; đây là quyết định pháp lý–kiến trúc phối hợp.

## 34. Retention schedule phải executable

Policy tốt xác định:

```text
dataset/category + purpose + start event + duration
+ legal hold/exception + deletion/anonymization action + owner + evidence
```

Ví dụ “30 ngày sau delivery” cần event đáng tin, timezone, late event và retry semantics. Retention
job phải bao phủ partition cũ, index, lake, log và downstream. Không dùng `created_at + 7 years`
cho mọi record khi lifecycle khác nhau.

Giữ “để có thể cần sau này” không phải purpose cụ thể.

## 35. Deletion là distributed workflow

```text
request/policy trigger
  → verify scope + holds/exceptions
  → mark deletion workflow ID
  → delete/anonymize primary
  → propagate cache/index/event/warehouse/processor
  → verify + retry/DLQ
  → record evidence without retaining deleted value
```

Trạng thái có thể là requested, verified, blocked-by-hold, executing, partially-failed, completed.
Idempotency và reconciliation quan trọng hơn một transaction giả trên mọi hệ thống.

## 36. Backup và crypto-shredding

Backup immutable có thể không hỗ trợ xóa từng record ngay. Policy cần:

- backup retention ngắn nhất đáp ứng recovery/legal need;
- restore vào môi trường cô lập rồi reapply tombstone/deletion ledger trước khi mở service;
- access/key tách biệt và audit;
- không dùng backup như archive vô hạn;
- processor/replica có cùng deletion expectation;
- giải thích/document delayed erasure theo policy/pháp luật áp dụng.

Crypto-shredding chỉ hiệu quả nếu key scope đủ nhỏ, mọi bản sao dùng đúng key và không còn plaintext/
key backup. Xóa global key để xóa một user có thể phá dữ liệu của người khác.

## 37. Media sanitization

Khi retire/reuse thiết bị hoặc storage, chọn action theo media, sensitivity và threat:

- clear: logical technique chống khôi phục bằng interface thông thường;
- purge: technique mạnh hơn để việc phục hồi trở nên không khả thi theo state of practice;
- destroy: làm media không còn sử dụng được và khó phục hồi.

Cloud/SSD/thin provisioning khiến overwrite truyền thống không đơn giản. Dùng provider capability,
encryption/key destruction phù hợp, chain of custody và certificate/evidence. Tham chiếu NIST
SP 800-88 Revision 2 hiện hành thay vì sao chép command xóa chung cho mọi media.

## 38. Kiến trúc cho quyền của chủ thể dữ liệu

Các quyền và ngoại lệ phụ thuộc jurisdiction, nhưng platform thường cần:

- discover subject qua stable identity/linkage;
- access/export ở format đúng policy;
- correction và propagation tới derived system;
- deletion/restriction/objection state;
- portability khi áp dụng;
- preference/consent history;
- deadline, legal hold, exception và human review;
- processor orchestration;
- evidence và appeal/contact path.

Không trả internal secret, data của người khác, fraud signal nhạy cảm hoặc raw audit ngoài scope chỉ
vì match email; export phải có policy filtering.

## 39. Xác minh identity cho privacy request

DSAR/data-right endpoint là target cho data theft và account discovery:

- assurance tỷ lệ với sensitivity và action;
- dùng session/account proof hiện có khi phù hợp;
- recovery/manual proof không yếu hơn đến mức attacker bypass;
- generic response chống enumeration;
- rate limit và abuse/fraud review;
- separation maker/checker cho ngoại lệ;
- secure delivery, link ngắn hạn và download re-auth;
- không thu thêm excessive PII chỉ để xác minh;
- agent/guardian/authorized representative cần relationship proof theo policy.

Ghi audit request/status, không lưu document verification lâu hơn cần thiết.

## 40. Consent và preference lifecycle

Nếu consent là basis/policy được dùng, cần:

```text
grant: subject + purpose + scope + notice/version + timestamp + source
change/revoke: effective time + propagation + downstream action
```

- consent granular, informed và không bundled ngoài rule được phê duyệt;
- withdrawal dễ tương đương grant và không làm hỏng required core service một cách đánh lừa;
- preference cache có version/TTL;
- event out-of-order không khôi phục consent cũ;
- downstream suppression/deletion rõ;
- evidence không biến thành kho dữ liệu thừa;
- child/special category rule do legal owner cấu hình.

Consent không sửa được over-collection hoặc insecure processing.

## 41. Privacy threat modeling và DPIA

Dùng [Threat Modeling §25](../architecture/threat_modeling_secure_architecture.md) và LINDDUN để hỏi
linkability, identifiability, detectability, disclosure, unawareness và non-compliance. Privacy risk
phải xét problematic data action và consequence với cá nhân, kể cả action được authorize.

DPIA/assessment trigger có thể gồm processing mới rủi ro cao, monitoring quy mô lớn, sensitive data,
automated decision hoặc technology/context mới—definition chính thức tùy luật. Artifact nên nối:

```text
purpose → data/subject/flow → necessity/proportionality
→ threat/harm → control → residual risk → approval/consultation → review trigger
```

## 42. Incident response cho data breach

1. Contain access/exfiltration nhưng bảo toàn evidence.
2. Xác định dataset, field, subject, tenant, region, time window và bản sao.
3. Phân biệt accessed, exfiltrated, altered, unavailable và inferred.
4. Dùng lineage để tìm processor/downstream/backup ảnh hưởng.
5. Đánh giá harm cho cá nhân, business, safety và legal obligation.
6. Legal/privacy owner quyết định notification/regulator timeline theo luật áp dụng.
7. Revoke credential/key, đóng path và monitor reuse/fraud.
8. Ghi decision/evidence, hỗ trợ subject và cập nhật threat model/retention/minimization.

Không ghi trong thông báo rằng “dữ liệu đã encrypted” nếu key/access path cũng bị compromise.

## 43. DLP và egress control

DLP là lớp detection/prevention, không thay inventory/minimization. Coverage:

- endpoint/browser/email/chat/upload;
- API gateway/egress proxy;
- database/warehouse query và bulk export;
- cloud object public/share policy;
- CI log/artifact/source repository;
- SaaS connector và unmanaged device.

Kết hợp classification label, structured field, fingerprint và context. Thiết kế exception có owner/
expiry/audit; tránh chặn mù làm user chuyển sang shadow channel. Alert không chứa full matched value.

## 44. Java/Spring: structured event thay vì log object

Không gọi `toString()` trên request/entity có PII. Tạo event allowlist:

```java
public record SecurityEvent(
        String eventType,
        String actorRef,
        String resourceRef,
        String purpose,
        String outcome,
        String correlationId) {}

SecurityEvent event = new SecurityEvent(
        "customer_profile_viewed",
        actor.opaqueAuditId(),
        customer.opaqueAuditId(),
        "support_case_resolution",
        "allowed",
        correlationId);

log.info("security_event={}", event); // record không chứa email/token/profile
```

Thêm test bắt canary PII/secret không xuất hiện trong appender output. Filter ở source trước khi log
collector nhận; MDC cũng phải allowlist vì nó lan qua nhiều log line.

## 45. Kiểm thử data control

- schema/contract test bắt field thiếu classification/purpose/retention;
- negative test cho row/column/tenant/purpose authorization;
- log/trace/metric test với canary PII, token và nested exception;
- retention job test boundary time, legal hold, retry và late event;
- deletion reconciliation qua cache/index/lake/processor;
- restore backup rồi bảo đảm tombstone được áp lại;
- export/DSAR test loại data người khác và field ngoài scope;
- pseudonym collision, scope separation và low-entropy attack test;
- re-identification study cho dataset release;
- DP implementation/budget/composition review;
- DLP positive/negative và exception expiry test;
- chaos test khi downstream deletion/processor unavailable.

## 46. Monitoring và metric có ý nghĩa

Theo dõi:

- dataset/field chưa owner, class, purpose hoặc retention;
- copy/flow không có lineage;
- restricted data access/export spike và unusual principal/region;
- old data vượt retention, deletion backlog/failure age;
- subject request SLA, exception/hold và failed delivery;
- consent/preference propagation lag;
- DLP alert đến containment;
- pseudonym detokenize/relink event;
- DP privacy budget consumption;
- processor deletion/assurance overdue;
- backup restore/deletion drill age.

Metric label không được chứa personal data; dashboard access và retention cũng phải quản trị.

## 47. Governance và change management

Review data design khi:

- thêm field/source/inference hoặc reuse purpose;
- thêm integration/processor/region;
- đổi retention/export/access model;
- tạo analytics/model hoặc public dataset;
- identity/linkage/pseudonym scope thay đổi;
- incident/re-identification cho thấy assumption sai;
- luật, contract hoặc privacy notice thay đổi.

Data owner, privacy, security và engineering cùng ký decision theo risk. NIST Privacy Framework 1.0
là bản final hiện hành tại thời điểm tài liệu này; 1.1 vẫn là Initial Public Draft, nên nếu pilot
1.1 phải ghi rõ version/status thay vì gọi là final standard.

## 48. Ví dụ end-to-end: support analytics

### Thiết kế ban đầu có rủi ro

```text
Support DB (name, email, ticket free text)
  → nightly full export
  → shared analytics bucket
  → analyst notebook + external BI
```

Threat: over-collection, PII trong free text, shared credential, cross-region copy, notebook export,
retention vô hạn và không thể propagate deletion.

### Thiết kế lại

```text
approved purpose: support_quality_monthly
  → detect/redact free-text identifiers
  → scoped pseudonym per analytics purpose
  → minimize fields + coarse time/category
  → restricted curated dataset, row policy, no raw download
  → aggregate threshold/DP nếu release rộng
  → lineage + 90-day policy + deletion/tombstone reconcile
```

### Evidence

- contract test chặn email/name/raw body;
- pseudonym không join được với marketing scope;
- analyst role không detokenize/export;
- rare group bị suppress hoặc privacy mechanism phù hợp;
- deletion job và processor/BI cache được reconcile;
- re-identification review trước thay đổi release model.

## 49. Runbook: PII vô tình vào log hoặc analytics

1. Dừng nguồn phát sinh/sampling nguy hiểm; không copy raw finding vào chat/ticket.
2. Xác định field, subject count, time range, environment, sink/replica/export và reader.
3. Restrict access, preserve audit/evidence và kiểm tra exfiltration.
4. Privacy/legal owner đánh giá harm/notification obligation theo jurisdiction.
5. Purge theo approved log/data procedure; xử lý index, archive, dashboard cache và backup policy.
6. Nếu credential/secret đi kèm, revoke tại provider ngay.
7. Thay object logging bằng structured allowlist/redaction tại source.
8. Thêm canary regression test, DLP detector, schema classification và retention guardrail.
9. Cập nhật lineage, threat model và decision record.

## 50. Checklist, anti-pattern và nguồn chính thức

### Production checklist

- [ ] Có inventory/lineage cho primary, cache, index, event, log, lake, export, processor và backup.
- [ ] Mỗi dataset có owner, subject/category, purpose, class, region, retention và deletion rule.
- [ ] Collection/use/share được minimize và privacy-protective by default.
- [ ] Consent chỉ dùng khi policy/law xác định; preference có version và propagation.
- [ ] Authorization xét action, data class, purpose, tenant và context; bulk export có control riêng.
- [ ] Encryption/key lifecycle đúng; pseudonym/token/masking không bị gọi nhầm anonymous.
- [ ] De-identification có release model, re-identification review và measurable criteria.
- [ ] Log/trace/metric dùng allowlist và canary test, không chứa PII/secret ngoài necessity.
- [ ] Retention executable; deletion idempotent/reconciled qua downstream và processor.
- [ ] Backup restore áp deletion ledger; media sanitization theo NIST SP 800-88 Rev.2/provider.
- [ ] Subject request xác minh identity tỷ lệ rủi ro và không leak data người khác.
- [ ] Incident runbook dùng lineage để tính subject/dataset/recipient/region impact.
- [ ] DLP, access/export anomaly, deletion SLA và privacy budget được monitor.
- [ ] Change trigger cập nhật inventory, assessment, contract, notice và control.

### Anti-pattern

| Anti-pattern | Vì sao sai | Cách sửa |
|---|---|---|
| Mã hóa nghĩa là privacy đã xong | Không xử lý over-collection/purpose/rights | Minimize + governance + technical controls |
| Xóa tên là anonymous | Quasi-identifier vẫn tái nhận dạng | Release model + risk study/DP/access control |
| Hash email để anonymize | Low entropy, linkable, brute-force được | Scoped keyed pseudonym và vẫn coi là personal |
| Mask UI rồi cho analyst query raw DB | Original vẫn lộ | Policy/view/tokenization và least privilege |
| Consent cho mọi thứ | Consent có thể không phù hợp/không hợp lệ | Policy/lawful basis do privacy/legal xác nhận |
| Retention là text trong policy | Không tự xóa bản sao | Executable schedule + lineage + reconciliation |
| Xóa primary row là hoàn tất | Cache/index/lake/processor còn dữ liệu | Distributed deletion workflow |
| DP nghĩa là thêm noise | Không có guarantee/budget/composition | Formal definition + evaluated implementation |
| DLP sẽ tìm hết PII | False negative và shadow data | Inventory, contract, minimization, discovery |
| Production PII cho test để “thật” | Tạo thêm breach surface | Synthetic/minimized approved test data |

### Nguồn chính thức

- [NIST Privacy Framework](https://www.nist.gov/privacy-framework)
- [NIST IR 8062 – Privacy Engineering and Risk Management](https://csrc.nist.gov/pubs/ir/8062/final)
- [NIST SP 800-122 – Protecting the Confidentiality of PII](https://csrc.nist.gov/pubs/sp/800/122/final)
- [NIST SP 800-188 – De-Identifying Government Datasets](https://csrc.nist.gov/pubs/sp/800/188/final)
- [NIST SP 800-226 – Evaluating Differential Privacy Guarantees](https://csrc.nist.gov/pubs/sp/800/226/final)
- [NIST SP 800-88 Revision 2 – Media Sanitization](https://csrc.nist.gov/pubs/sp/800/88/r2/final)
- [GDPR official text – EUR-Lex](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)
- [EDPB – Privacy by Design and by Default](https://www.edpb.europa.eu/topics/ai-and-technology/privacy-by-design-and-by-default_en)
- [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)
- [LINDDUN Privacy Threat Modeling](https://linddun.org/)

### Học tiếp

1. [Software Supply Chain Security](../supply_chain/software_supply_chain_security.md) – provenance, signing, SBOM, build isolation và dependency policy.
2. [Container & Kubernetes Runtime Security](../runtime/container_kubernetes_runtime_security.md) – admission, workload isolation, policy và runtime detection.

---

*Cập nhật lần cuối: 2026-08-02.*
