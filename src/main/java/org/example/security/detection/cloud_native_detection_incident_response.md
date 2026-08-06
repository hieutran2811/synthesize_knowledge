# Cloud-Native Detection & Incident Response – Phát hiện và ứng phó xuyên control plane

Trong cloud-native, một incident hiếm khi nằm gọn trong một máy. Một token từ Pod có thể gọi Kubernetes
API, đổi sang cloud identity, đọc object storage rồi tạo persistence bằng pipeline hoặc serverless trigger.

Mục tiêu của chương này là trả lời nhanh và có bằng chứng:

> Identity nào đã làm gì, trên resource nào, bằng credential/artifact nào, qua control plane nào; blast
> radius đến đâu và containment nào chặn attacker mà không phá evidence hoặc làm sự cố lan rộng?

---

## 1. Incident response là năng lực liên tục, không phải quy trình chỉ bật khi có báo động

NIST SP 800-61 Rev. 3 đặt incident response trong toàn bộ Cybersecurity Framework 2.0: Govern, Identify,
Protect và Detect tạo khả năng chuẩn bị; Respond và Recover xử lý hậu quả; bài học lại quay về quản trị rủi ro.

```text
prepare + prevent + instrument
    → detect + analyze
        → contain + eradicate
            → recover + improve
```

Cloud-native thay đổi liên tục, nên inventory, logging, quyền responder, playbook và clean recovery path phải
được kiểm thử trước incident. Không thể bắt đầu tìm owner hoặc xin quyền đọc log khi attacker đang hoạt động.

## 2. Đơn vị điều tra là đồ thị identity–resource–event

Host/IP/Pod name không còn là identity ổn định. Mô hình điều tra nên nối:

```text
human/workload identity
  → session/token/key/certificate
    → API action / process / network flow
      → resource immutable ID + version/digest
        → downstream identity/data/resource
```

Một principal có thể assume role; một Pod bị thay sau vài phút; một serverless instance không còn tồn tại.
Giữ stable ID và quan hệ delegation để truy được chuỗi hành động thay vì chỉ tìm một địa chỉ IP.

## 3. Vì sao cloud-native IR khác IR máy chủ truyền thống

| Đặc điểm | Hệ quả điều tra |
|---|---|
| Tài nguyên phù du/autoscale | bằng chứng local biến mất nhanh |
| Control plane API | attacker thay hạ tầng mà không SSH vào máy |
| Workload identity/token ngắn hạn | credential đổi liên tục, cần trace issuer/session |
| Managed service/serverless | không có disk/RAM để thu như VM |
| Multi-account/cluster/region | blast radius vượt một console |
| Declarative controller | xóa Pod/resource có thể được tạo lại ngay |
| Shared responsibility | một phần evidence/control thuộc provider |

Vì vậy, ưu tiên audit trail, configuration history, identity graph, artifact digest và externalized telemetry.

## 4. Taxonomy và severity theo tác động kinh doanh

Phân loại incident theo scenario, không theo tên tool phát hiện:

- identity/credential compromise;
- malicious deployment hoặc supply-chain compromise;
- workload/node/container escape;
- cloud control-plane/IAM change;
- data access/exfiltration/destruction;
- crypto mining/resource hijacking;
- logging/detection impairment;
- availability/ransomware.

Severity xét dữ liệu, privilege, external exposure, tenant, regulatory duty, active attacker, blast radius và
khả năng phục hồi. “Một Pod bị compromise” có thể P1 nếu token của nó quản trị nhiều account.

## 5. Chuẩn bị vai trò và quyền responder

Tối thiểu xác định Incident Commander, technical lead, cloud/Kubernetes owner, detection analyst, forensics,
application/data owner, communications, legal/privacy và vendor liaison.

Responder cần read-only cross-account/cluster access, khả năng cô lập/revoke có approval và break-glass tách
biệt. Không dùng account đang nghi compromise để điều tra hoặc containment.

Mọi quyền khẩn cấp phải short-lived, recorded, scoped theo case, tự hết hạn và được review sau sự cố. Runbook
cần chỉ rõ ai có quyền cordon node, disable identity, deny egress, khóa bucket và dừng pipeline.

## 6. Kiến trúc telemetry cho security

```text
identity/provider audit       cloud control-plane audit
Kubernetes API audit          registry/CI/deployment audit
runtime/process/syscall       DNS/network/load-balancer flow
application/access/data log   configuration/inventory history
                ↓ normalize + enrich
          durable security store
                ↓ detect + hunt + case
```

Không nhất thiết đưa mọi byte vào một hệ thống. Cần catalog nguồn, owner, schema, latency, retention, access,
cost, integrity và query path. Store điều tra phải nằm ngoài blast radius của workload/cluster được giám sát.

## 7. Canonical event schema và raw evidence

Chuẩn hóa các field chung:

- `event.id`, source, category, action, outcome, severity;
- event time, observed/ingest time và timezone;
- actor/subject, issuer, session, credential type;
- source/destination network và user agent;
- account/project/subscription, region, cluster/namespace;
- resource stable ID, object UID, image digest;
- request/correlation/trace ID;
- raw event pointer và parser/schema version.

Giữ raw event bất biến để re-parse khi schema/rule đổi. Normalized event giúp correlation nhưng có thể làm
mất field hoặc sai semantics; không dùng nó làm bằng chứng duy nhất.

## 8. Thời gian, thứ tự và eventual consistency

Lưu ít nhất:

- `event_time`: lúc source cho rằng hành động xảy ra;
- `observed_time`: collector nhận event;
- `ingested_time`: backend lưu event.

Cloud/Kubernetes log có thể đến trễ, trùng hoặc lệch thứ tự; retry tạo nhiều record. Đồng bộ clock cho node,
collector và service; giữ source event ID; deduplicate có cửa sổ nhưng không xóa raw record.

Timeline nên dùng khoảng tin cậy khi timestamp không chính xác. Không kết luận A gây B chỉ vì A đứng trước B
vài mili-giây trong SIEM.

## 9. Identity correlation: principal không chỉ là username

Một event identity cần phân biệt:

- human/workload/service principal;
- original identity và assumed/delegated identity;
- session ID, token issuer, audience, subject, auth method;
- role/policy tại **thời điểm event**;
- source workload/device/network;
- MFA/conditional-access context nếu có.

Email hoặc role display name có thể đổi. Lưu immutable principal ID và delegation chain. Khi token bị đánh
cắp, source IP khác nhưng principal giống; khi attacker assume role, principal hiển thị mới nhưng session
issuer dẫn về credential gốc.

## 10. Resource identity và configuration history

Tên resource có thể được xóa rồi tạo lại. Dùng cloud resource ID/ARN-equivalent, Kubernetes UID, image digest,
object generation/resourceVersion và account/region.

Snapshot configuration history cho IAM policy, network, bucket, key, function trigger, workload spec, RBAC,
admission và logging. Điều tra cần biết quyền **trước/sau** thay đổi, không chỉ state hiện tại.

Tag/label giúp enrichment nhưng attacker có thể sửa; giữ event ai đã đổi tag và không dùng tag tự quản lý làm
trust signal duy nhất.

## 11. Phân lớp signal theo control plane và data plane

| Plane | Ví dụ | Câu hỏi trả lời |
|---|---|---|
| Identity | login, token issue, role assumption | ai có session/quyền nào? |
| Cloud control plane | IAM/network/compute/storage API | hạ tầng nào bị thay? |
| Kubernetes control plane | create Pod, exec, RBAC, Secret | object/identity cluster nào bị dùng? |
| Runtime | process, syscall, file, socket | code thực sự làm gì? |
| Network | DNS, flow, proxy, LB/WAF | nói chuyện với ai và bao nhiêu? |
| Data plane | object/database/queue access | dữ liệu nào được đọc/sửa? |
| Delivery | source, CI, registry, deploy | artifact/config đi vào runtime bằng đường nào? |
| Application | auth/business event | hành động nghiệp vụ nào xảy ra? |

Một nguồn hiếm khi đủ. Control-plane success không chứng minh payload đã chạy; runtime event không luôn biết
ai đã tạo workload.

## 12. Cloud audit log: biết coverage trước khi cần

AWS CloudTrail, Google Cloud Audit Logs và Azure Activity Log đều ghi hoạt động quản trị/API, nhưng coverage,
retention mặc định và data-access logging khác nhau. Ví dụ, AWS Event history tập trung management events gần
đây; GCP Data Access logs thường cần bật rõ cho nhiều service; Azure Activity Log là subscription control-plane
và data-plane có log riêng.

Checklist:

- bật organization/tenant-wide, mọi region/account/subscription/project;
- bật data event cho kho dữ liệu critical theo risk/cost;
- centralize sang security account/project;
- bảo vệ cấu hình, sink, bucket và encryption key;
- alert khi trail/sink/category bị tắt hoặc exclusion thay đổi;
- định kỳ tạo canary API action và xác nhận event truy vấn được.

## 13. Kubernetes audit: policy phải cân bằng evidence và dữ liệu nhạy cảm

Kubernetes audit có các mức `Metadata`, `Request`, `RequestResponse`, `None` và stage của request. Thu đủ:

- authentication failure và denied action;
- create/patch/delete workload, RBAC, Secret metadata;
- `exec`, `attach`, `portforward`, `ephemeralcontainers`;
- Pod Security/admission, namespace security label;
- node, CSR, token request và audit-policy-related change.

Request body có thể chứa Secret/token/PII; dùng mức cao có chọn lọc, omit stage không cần và bảo vệ backend.
Audit log phải ra ngoài cluster, monitor event drop và giữ `auditID`, user, impersonation, source IP, userAgent,
object UID.

## 14. Runtime event: Falco/eBPF và giới hạn

Runtime sensor quan sát process, syscall, file, capability và network, hữu ích với shell lạ, write binary,
đọc token, container escape hoặc crypto miner. Falco rule kết hợp condition, macro/list và output metadata.

Nhưng sensor có thể:

- bỏ event khi tải cao;
- thiếu context control plane;
- bị evasion/kernel compatibility issue;
- có host privilege lớn;
- tạo noise khi app hợp lệ thay đổi.

Monitor sensor health/drop, pin và verify agent, tách quyền, enrich bằng Pod UID/image digest/ServiceAccount.
Runtime detection bổ sung chứ không thay audit, prevention hoặc EDR trên node.

## 15. Network, DNS và ingress signal

Network evidence gồm VPC/VNet flow, CNI/eBPF flow, firewall, DNS, NAT, proxy, load balancer, API gateway và WAF.
Mỗi nguồn nhìn một điểm khác nhau; NAT/service mesh có thể che client gốc.

Các field quan trọng: source workload/identity, destination IP/FQDN/service, port/protocol, bytes, direction,
decision, TLS identity/SNI khi hợp pháp, request ID và policy verdict.

DNS query giúp phát hiện discovery/tunneling nhưng DoH hoặc cache làm mất visibility. Flow log thường không có
payload và sampling có thể bỏ phiên ngắn; ghi rõ giới hạn trước khi kết luận “không có exfiltration”.

## 16. Application log và trace cho security

Application biết business subject/action mà hạ tầng không biết: user nào export report, tenant nào đổi payout,
object nào bị đọc. Log authorization decision, stable actor/resource ID, action, outcome, reason code, request ID
và data classification—không log password, token, secret hoặc raw PII.

OpenTelemetry log data model hỗ trợ gắn `TraceId`/`SpanId`, giúp nối request qua service. Trace context là input
không tin cậy từ client; không coi trace ID là bằng chứng identity và chống log injection/cardinality abuse.

Security log cần độc lập với debug toggle để attacker hoặc operator không vô hiệu hóa ngoài ý muốn.

## 17. Delivery và supply-chain signal

Theo dõi source/PR approval, CI workflow identity, artifact digest, signature/provenance, registry push/delete,
admission decision và deployment actor.

Correlation quan trọng:

```text
commit → build run → digest → registry event
       → admission → workload UID → runtime process/network
```

Cảnh báo artifact không có build/provenance hợp lệ, deploy ngoài pipeline, tag overwrite, registry delete,
signer lạ, workflow/ref bất thường hoặc digest chạy không có trong release catalog.

Chi tiết prevention xem [Software Supply Chain Security](../supply_chain/software_supply_chain_security.md).

## 18. Serverless, PaaS và SaaS cần evidence theo provider

Serverless instance, managed database và SaaS thường không cho memory/disk acquisition. Chuẩn bị:

- control-plane và invocation/access log;
- function/version/code digest, trigger và execution identity;
- configuration/environment change history;
- database/object/queue data-access audit;
- provider finding/case/export API;
- support escalation và evidence retention theo hợp đồng.

Scale-to-zero làm local log biến mất; instrumentation và external sink phải có từ trước. Snapshot/clone managed
data cần hiểu consistency, encryption key và legal/privacy scope.

## 19. Log integrity, access và retention

Security log nên gửi cross-account/project, append-only/immutable theo khả năng, encryption at rest/in transit,
least-privilege read/write, retention lock khi cần và audit mọi query/export/delete/config change.

Tách quyền:

- producer chỉ ghi;
- platform vận hành pipeline nhưng không sửa evidence lịch sử;
- analyst đọc theo case/need-to-know;
- retention admin và key admin tách biệt.

Retention phải dài hơn maximum detection/notification/investigation window và có cost model. Hash/signature
hoặc provider integrity feature giúp phát hiện sửa đổi nhưng không chứng minh source đã log đầy đủ.

## 20. Telemetry pipeline cũng cần SLO và detection

Theo dõi từ source đến query:

- expected source/account/cluster coverage;
- last event time và ingest delay distribution;
- parser/schema failure, queue backlog, duplicate/drop;
- storage write/query error;
- sensor/collector health và version;
- audit trail/sink/exclusion/policy change;
- canary event end-to-end.

“Không có alert” trong lúc collector chết là failure nguy hiểm. Alert telemetry gap phải đi qua kênh độc lập
và có runbook: khôi phục visibility, tăng mức rủi ro, hạn chế change nhạy cảm trong blind window.

## 21. Detection engineering lifecycle

```text
threat scenario
  → observable behavior + required data
    → analytic/rule + test
      → deploy shadow/canary
        → triage + tune
          → measure coverage/gap
            → retire or improve
```

Mỗi detection có ID, owner, hypothesis, data dependency, ATT&CK reference, severity logic, expected false
positive, test fixture, runbook, version và review date.

Detection không có owner/runbook sẽ trở thành alert debt; rule không có test sẽ âm thầm hỏng khi schema đổi.

## 22. Bắt đầu bằng threat hypothesis và invariant

Ví dụ hypothesis:

> Nếu attacker chiếm workload Internet-facing, họ có thể đọc projected token rồi gọi API để discovery Secret.

Observable chain:

```text
unexpected token-file read/runtime event
  + new Kubernetes API caller from Pod identity
  + list/get Secret denied or succeeded
  + outbound destination/process anomaly
```

Invariant mạnh hơn blacklist: “release workload chỉ được tạo bởi deployer identity từ verified digest”; “break-
glass role không được dùng ngoài case đang mở”; “workload này không bao giờ gọi Kubernetes API”.

## 23. MITRE ATT&CK là bản đồ coverage, không phải checklist hoàn thành

MITRE ATT&CK có matrix Cloud và Containers, gồm valid accounts, deploy container, implant image, steal token,
escape to host, discovery, defense impairment, exfiltration và resource hijacking.

Dùng ATT&CK để:

- liên kết scenario với technique/data component;
- tìm lỗ hổng coverage và thiết kế simulation;
- chuẩn hóa báo cáo giữa team;
- theo dõi detection/prevention/response theo technique.

Không tạo một rule cho mỗi technique chỉ để phủ màu matrix. Một technique có nhiều implementation; một analytic
có thể thấy nhiều technique nhưng thiếu context của environment.

## 24. Behavior, IOC và reputation

IOC như IP/domain/hash giúp phản ứng nhanh nhưng dễ đổi, có false positive và expiry. Behavior/invariant bền
hơn nhưng cần context và tuning.

Mỗi IOC cần source/confidence, first/last seen, scope, TTL/expiry, sharing restriction và match semantics.
Hash image/file mạnh cho byte cụ thể; domain/IP có thể shared; user agent dễ giả.

Khi IOC match, pivot sang identity, session, resource và behavior để scope. Không tự động xóa workload hoặc
block shared cloud IP chỉ từ reputation thấp-confidence.

## 25. Correlation theo session, resource và causal chain

Ưu tiên exact join:

- cloud request/event ID;
- Kubernetes audit ID/object UID;
- trace/request ID;
- role session/token subject;
- image digest/build/deploy ID;
- network flow tuple trong time window.

Fallback time/IP/name correlation phải ghi confidence. Dùng graph để nối original identity → assumed role →
API change → workload → runtime event → data access.

Correlation window phải tính ingest delay và retry. Tránh query “cùng user trong 24h” tạo câu chuyện giả mà
không có session/resource link.

## 26. Baseline và phát hiện rarity có context

Useful baseline gồm identity thường dùng action nào, region nào, giờ nào, source nào; workload thường spawn
process và gọi destination nào; deployment thường qua pipeline nào.

Rare không đồng nghĩa malicious. New service, incident response, failover hoặc autoscaling có thể hiếm nhưng
hợp lệ. Enrich change calendar, owner, environment, privilege và asset criticality.

Không để attacker “train” baseline vô hạn. Dùng rolling window có guard, exclude confirmed incident và giữ
policy invariant cho hành vi không bao giờ được phép.

## 27. Detection-as-code và Sigma

Rule-as-code cần review, version, lint, test, staged rollout và rollback. Sigma cung cấp format rule detection
tổng quát có metadata, logsource, detection và condition; backend conversion không đảm bảo semantics giống nhau.

Test ba lớp:

1. unit: event fixture match/non-match;
2. integration: query chạy đúng schema/backend;
3. end-to-end: simulation tạo event, pipeline ingest và alert/case xuất hiện.

Pin field mapping/parser version; query performance và cardinality cũng là production requirement.

## 28. Severity, confidence và priority là ba khái niệm khác nhau

- **Severity:** tác động nếu scenario đúng.
- **Confidence:** độ chắc analytic phản ánh hành vi thật.
- **Priority:** thứ tự xử lý sau khi xét active threat, asset, exposure, blast radius và workload của team.

Ví dụ: denied secret list có confidence cao rằng action xảy ra nhưng impact thấp hơn secret read thành công;
sign-in lạ có severity tiềm năng cao nhưng confidence thấp nếu thiếu device/session context.

Alert phải giải thích vì sao có score, không chỉ số magic. Analyst được phép điều chỉnh priority nhưng phải
ghi rationale.

## 29. Enrichment trước khi alert đến analyst

Alert hữu ích nên có:

- actor/original identity, session và current privilege;
- resource stable ID, owner, environment, criticality/data class;
- cluster/namespace/Pod UID/node/image digest;
- timeline ngắn trước/sau, related alerts và prior baseline;
- raw evidence links và query time range;
- ATT&CK/scenario, confidence, assumptions;
- containment options và tác động dự kiến;
- runbook/owner/escalation.

Enrichment phải snapshot theo event time nếu có; state hiện tại có thể đã bị attacker hoặc automation thay đổi.

## 30. Dedup, suppression và exception an toàn

Dedup theo analytic + actor/session + resource + time window, nhưng giữ occurrence count và first/last seen.
Một alert lặp 10.000 lần có thể là brute force hoặc automation lỗi—không nên biến thành một event vô nghĩa.

Suppression/allowlist cần owner, scope hẹp, reason, ticket, start/end và auto-expiry. Prefer condition như
approved pipeline identity + exact resource thay vì exclude account/namespace.

Alert khi suppression được tạo/sửa, nhất là bởi identity liên quan finding. Review exception khi workload
digest, role hoặc behavior đổi.

## 31. Triage: xác nhận trước nhưng không chờ chắc chắn tuyệt đối

Triage flow:

1. xác minh telemetry pipeline và raw event;
2. xác định analytic, confidence và expected legitimate cause;
3. tìm actor/session/resource/digest stable ID;
4. xem hành động trước/sau trên mọi plane;
5. xác định success/denied và business impact;
6. scope sơ bộ, severity, owner và incident declaration;
7. chọn evidence + containment song song theo urgency.

Nếu active exfiltration hoặc admin takeover, containment có thể đi trước full certainty. Ghi assumption và
reversibility để Incident Commander cân bằng evidence, availability và damage.

## 32. Blast radius bằng graph, không bằng danh sách alert

Pivot theo nhiều trục:

- cùng credential/session/issuer/original principal;
- mọi role/policy/token mà actor có thể nhận;
- cùng image digest/build/deployment;
- cùng node, volume, secret, network destination;
- resource downstream bị đọc/sửa;
- account/project/cluster/region/tenant khác;
- time window gồm trước first alert và sau containment.

Phân biệt **observed affected**, **potentially reachable** và **verified clean**. “Không thấy event” chỉ là sạch
khi nguồn log có coverage và health đã được chứng minh.

## 33. Timeline reconstruction có provenance

Mỗi timeline row nên có:

| Field | Ý nghĩa |
|---|---|
| Event/observed time | thời gian và độ tin cậy |
| Actor/session | ai/credential chain |
| Action/resource | việc gì trên object nào |
| Outcome | success, deny, unknown |
| Source | raw log/evidence ID |
| Interpretation | fact hay inference |
| Confidence | high/medium/low |

Không trộn fact với giả thuyết. Ghi timezone, query, parser version và gap. Update timeline có version/history;
một slide thủ công không phải source of truth điều tra.

## 34. Evidence handling và chain of custody

Mỗi collection có case ID, collector identity, source, command/API/query, time, scope, output hash, storage path,
access log và handoff. Dùng read-only API/role trước; tránh thu quá nhiều PII/secret không liên quan.

Giữ raw export cùng query và result. Provider export có thể thay format hoặc paginate; lưu continuation/manifest
và verify completeness. Snapshot evidence trước hành động làm đổi state khi urgency cho phép.

Legal/privacy quyết định preservation hold, jurisdiction, employee/customer data và disclosure; kỹ thuật không
tự quyết notification deadline.

## 35. Forensics cho Pod/container phù du

Trước khi Pod biến mất, nếu an toàn và được phép, thu:

- full workload/controller spec, UID, events và status;
- image ID/digest, container/runtime ID và node;
- process tree, command, capability, mount, namespace, connection;
- writable-layer/file hash theo procedure;
- ServiceAccount, RBAC, secret/PVC references;
- Kubernetes audit và runtime event quanh cửa sổ;
- network/DNS/application request liên quan.

`kubectl exec` làm thay evidence. Dùng collector/debug procedure đã test và log mọi thao tác. Controller có thể
tạo Pod mới; Pod mới không phải evidence của process cũ dù cùng name prefix.

## 36. VM, volume, object và managed-data forensics

Với VM/node: isolate network, snapshot disk/volume và capture memory nếu nền tảng/procedure hỗ trợ, sau đó
rebuild thay vì đưa máy nghi compromise trở lại. Snapshot crash-consistent không luôn application-consistent.

Với object storage/database:

- preserve version, access log, metadata và retention/legal hold;
- clone/snapshot bằng identity điều tra tách biệt;
- ghi encryption key/version và restore point;
- không mở snapshot nhạy cảm ra account phân tích chung;
- test provider export completeness.

Managed service thường cần provider support; lưu case/escalation channel và SLA từ trước.

## 37. Containment theo objective và tính đảo ngược

Containment có thể nhằm dừng exfiltration, chặn persistence, bảo vệ tenant, giữ availability hoặc bảo toàn
evidence. Chọn control gần nguồn nhất và blast radius nhỏ nhất:

```text
revoke session/token → deny specific action/resource
→ isolate workload/network → freeze deployment/account changes
→ broader account/cluster isolation
```

Mỗi action cần owner, expected impact, validation signal, rollback và expiry. Không thêm một deny policy rộng
mà quên xóa; không rotate mọi key cùng lúc nếu làm mất quyền điều tra hoặc gây outage dây chuyền.

## 38. Identity containment

Tùy credential, containment gồm revoke session/refresh token, disable principal, remove role binding, revoke
certificate/key, thay workload federation trust hoặc explicit deny sensitive action.

Quy trình:

1. snapshot identity/policy/session evidence;
2. chặn issue session mới;
3. revoke credential còn hiệu lực và downstream token;
4. tìm mọi action trong credential lifetime;
5. rotate secret mà identity có thể đọc;
6. tạo clean replacement identity với privilege tối thiểu;
7. monitor retry/fallback credential.

Reset password không revoke mọi session, access key, OAuth grant hay workload token.

## 39. Workload containment

Các lựa chọn tăng dần:

- chặn egress/ingress cụ thể;
- remove ServiceAccount/cloud identity;
- scale controller về 0 hoặc pause rollout;
- quarantine namespace/node pool;
- deny image digest/admission;
- replace bằng clean digest.

Xóa Pod có thể làm controller tạo lại cùng image độc hại và phá local evidence. Chặn nguồn tái tạo trước:
Deployment/Job/GitOps/pipeline/admission. Xác nhận bằng observed workload và network/API event, không chỉ lệnh
containment trả về success.

## 40. Node và cluster containment

Node nghi compromise: cordon, cô lập network quản trị, preserve evidence, inventory mọi Pod/credential đã chạy,
drain theo risk rồi replace/reimage. Giả định token/secret accessible trên node có thể lộ.

Cluster/control plane nghi compromise:

- hạn chế change và break-glass identity;
- bảo vệ/export audit + etcd/config evidence;
- revoke kubeconfig/certificate/token theo scope;
- tìm RBAC, webhook, CRD/operator, static Pod và node persistence;
- dùng clean management plane để recovery.

Không dùng cluster nghi compromise làm nơi duy nhất chứa log, backup hoặc recovery tool.

## 41. Cloud account/control-plane containment

Contain đúng organizational layer: principal, role, resource policy, account/project/subscription, region hoặc
organization guardrail. Kiểm tra persistence như access key mới, federated trust, IdP app, role policy, event
trigger, function, VM, snapshot, image, secret version và logging exclusion.

Account shutdown rộng có thể làm mất logging, DNS, identity hoặc production của nhiều tenant. Chuẩn bị quarantine
OU/folder/subscription, deny policy, network isolation và billing/provider escalation được test.

Mọi containment control phải tạo audit ngoài blast radius và có second-person approval khi thời gian cho phép.

## 42. Runbook: nghi ngờ data exfiltration

1. Xác định dataset/object/table, classification, owner và data-access logging coverage.
2. Nối identity/session với read/list/export/snapshot và network transfer.
3. Phân biệt accessed, staged, transferred và confirmed received; ghi confidence.
4. Chặn credential, sharing/public access, export job và destination phù hợp.
5. Preserve object/database/access/proxy/DNS audit; kiểm tra version và encryption key access.
6. Scope tenant/subject/record/time, downstream copy và processor.
7. Phối hợp privacy/legal/comms về notification; không tự kết luận chỉ từ bytes flow.
8. Rotate data access, sửa root cause và tăng canary/detection.

Nén file hoặc đọc hàng loạt là signal, không tự chứng minh dữ liệu đã rời tổ chức.

## 43. Runbook: crypto mining hoặc resource hijacking

Signal: instance/Pod/function lạ, CPU/GPU tăng, image/process miner, outbound pool protocol, quota/region mới,
billing anomaly và API create compute từ principal hiếm.

1. Chặn principal/session và autoscaling/deployment source.
2. Preserve control-plane, user-data/image/digest, process/network và billing evidence.
3. Dừng/isolate resource sau khi cân bằng evidence và cost.
4. Hunt credential theft, metadata access, pipeline compromise và persistence ở region khác.
5. Kiểm tra quota, key, role, function trigger, scheduled job và image registry.
6. Rebuild sạch; đặt budget/quota/region guardrail và detection.

Chỉ xóa miner không xử lý access path đã tạo nó.

## 44. Runbook: malicious deployment hoặc artifact

1. Freeze promotion/deploy của digest, signer, builder hoặc workflow nghi vấn.
2. Nối source approval → build provenance → registry → cluster/serverless deployment.
3. Liệt kê mọi nơi digest/chung material đang chạy và identity/secret nó chạm tới.
4. Quarantine digest tại registry/admission; preserve image, attestation, SBOM, build/audit log.
5. Hunt runtime behavior, credential/data access và downstream persistence.
6. Revoke builder/signer/workload identity nếu compromise.
7. Rebuild trên trusted builder từ source/input verified; phát hành digest/evidence mới.
8. Redeploy và monitor enhanced rules.

Rollback dùng immutable verified artifact, không rebuild tag cũ tùy ý.

## 45. Runbook: cloud/workload credential bị compromise

1. Xác định loại credential, issuer, subject, audience, scopes, issue/expiry và session chain.
2. Chặn issuance mới và revoke đúng session/key/grant/certificate.
3. Query toàn bộ credential lifetime cộng phần clock/log delay; mở rộng sang assumed role/token exchange.
4. Inventory resource đọc/sửa, credential/secret mới tạo và policy/trust change.
5. Rotate downstream secret mà attacker có thể đọc; không rotate mù mọi secret.
6. Tạo replacement ngắn hạn/least privilege trên trust path sạch.
7. Monitor old credential retry, alternate credential và persistence.
8. Sửa phishing, SSRF/metadata, leak log/repo hoặc federation condition là root cause.

Credential hết hạn không có nghĩa impact đã hết.

## 46. Recovery từ trạng thái sạch có thể chứng minh

Recovery criteria:

- root cause đã được loại bỏ hoặc compensating control có owner/expiry;
- attacker session/persistence bị revoke;
- artifact/config/node từ source tin cậy và verify;
- data integrity/backup restore được kiểm tra;
- logging/detection healthy;
- enhanced monitoring và rollback sẵn sàng;
- business owner chấp nhận residual risk.

Phục hồi theo canary/wave, quan sát security + business signal rồi mở dần traffic/quyền. Không dùng snapshot
sau thời điểm compromise làm “clean backup” nếu chưa phân tích.

## 47. Post-incident: root cause, control gap và knowledge transfer

Retrospective blameless nhưng evidence-based:

- entry point và enabling condition;
- dwell time, first possible/first observed/first alert;
- prevention, detection, triage, containment, recovery nào thành công/thất bại;
- telemetry blind spot và decision delay;
- business/data/tenant impact và residual uncertainty;
- action có owner, priority, due date và verification.

Phân biệt root cause kỹ thuật, process và organizational. Cập nhật threat model, IAM, supply chain, runtime,
detection, runbook và training; đóng action chỉ khi control được test, không khi ticket được merge.

## 48. Tabletop, purple team và continuous validation

Drill các scenario: stolen cloud admin session, compromised ServiceAccount, malicious image, node escape, disabled
audit sink, public storage/exfiltration và crypto mining multi-region.

Đo từ injection đến source event, ingestion, alert, analyst decision, containment và recovery. Chèn failure:
collector lag, webhook/SIEM outage, responder thiếu quyền, provider API rate limit, key service unavailable.

Purple team dùng emulation được phê duyệt, resource cô lập, stop condition và cleanup evidence. Không chạy kỹ
thuật phá hoại trên production chỉ để phủ ATT&CK.

## 49. Metrics đo outcome thay vì số alert

| Metric | Ý nghĩa |
|---|---|
| Critical telemetry coverage + canary success | có nhìn thấy plane/resource quan trọng không |
| Ingest delay/drop/parser failure | blind window thật |
| Detection coverage theo priority scenario | coverage gắn threat model |
| Precision/actionability theo analytic | analyst time có được dùng đúng không |
| MTTD/MTTA/contain/revoke/recover | cửa sổ attacker và tốc độ quyết định |
| Time to scope affected/reachable resources | năng lực graph/inventory |
| % alert có owner/runbook/test/review date | detection hygiene |
| Exception/suppression age | blind spot có chủ đích |
| Drill success và evidence completeness | readiness/recoverability |
| Repeat incident/control-gap closure | tổ chức có học được không |

Median che incident chậm nghiêm trọng; theo percentile, severity, tenant và scenario.

## 50. Checklist production, anti-pattern và tài liệu chính thức

### Checklist tối thiểu

- [ ] Inventory account/project/cluster/service, owner, identity, data và criticality.
- [ ] Centralize cloud/Kubernetes/data/runtime/delivery log ra ngoài blast radius; biết coverage/retention.
- [ ] Canonical schema giữ raw evidence, stable ID, session/delegation, digest và ba loại timestamp.
- [ ] Monitor pipeline health bằng canary; alert trail/sink/exclusion/sensor bị thay hoặc mất event.
- [ ] Detection bắt đầu từ threat hypothesis/invariant, có test, owner, runbook và expiry/review.
- [ ] Alert được enrich bằng identity, resource, current/historical privilege, digest và related timeline.
- [ ] Triage phân biệt fact/inference; scope affected, reachable và verified-clean.
- [ ] Break-glass/read-only investigation và containment quyền nhỏ, ngắn hạn, audit được.
- [ ] Evidence collection, retention hold và chain of custody đã drill cho ephemeral/managed resource.
- [ ] Recovery dùng identity/artifact/node/config sạch; post-incident action được verify.

### Anti-pattern thường gặp

- “Không có alert nghĩa là không có incident.”
- “Đưa mọi log vào SIEM là đã có detection.”
- “Pod/IP/name là identity đủ để điều tra.”
- “Denied event không cần quan tâm” hoặc “success event luôn độc hại.”
- “ATT&CK phủ xanh là detection hoàn chỉnh.”
- “Xóa Pod/VM là containment xong.”
- “Reset password đã revoke mọi session/token.”
- “Snapshot tạo sau incident chắc chắn sạch.”

### Tài liệu chính thức

- [NIST SP 800-61 Rev. 3 – Incident Response Recommendations](https://csrc.nist.gov/pubs/sp/800/61/r3/final)
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [MITRE ATT&CK – Containers Matrix](https://attack.mitre.org/matrices/enterprise/containers/)
- [MITRE ATT&CK – Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)
- [Kubernetes – Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Falco – Rules](https://falco.org/docs/concepts/rules/)
- [OpenTelemetry – Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [Sigma Detection Format – Rules](https://sigmahq.io/docs/basics/rules.html)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html)
- [Google Cloud Audit Logs](https://docs.cloud.google.com/logging/docs/audit)
- [Azure Activity Log](https://learn.microsoft.com/en-us/azure/azure-monitor/platform/activity-log)
- [NIST SP 800-86 – Integrating Forensic Techniques into Incident Response](https://csrc.nist.gov/pubs/sp/800/86/final)

### Học tiếp

1. [Platform Engineering Security](../platform/platform_engineering_security.md) – golden path, policy ownership, tenant guardrail và multi-cluster governance.
2. [Security Testing & Validation Engineering](../validation/security_testing_validation_engineering.md) – adversary emulation, control validation và security regression.

---

*Cập nhật lần cuối: 2026-08-02.*
