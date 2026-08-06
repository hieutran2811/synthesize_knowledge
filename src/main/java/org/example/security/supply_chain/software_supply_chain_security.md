# Software Supply Chain Security – Bảo vệ chuỗi cung ứng phần mềm

Supply chain security không chỉ là quét thư viện có CVE. Mục tiêu thật sự là trả lời được:

> Artifact đang chạy được tạo từ source nào, bởi builder nào, với input nào, ai đã phê duyệt,
> bằng chứng có bị sửa không và policy nào đã cho phép nó đi vào production?

Chương này đi từ source, dependency, CI/CD, build, registry đến deployment và incident response.

---

## 1. Chuỗi cung ứng là một đồ thị tin cậy

Một bản phát hành thường phụ thuộc vào nhiều thứ hơn source code của ứng dụng:

```text
developer + Git + pull request
    + dependency + plugin + toolchain + base image
    + CI workflow + runner + cache + secret
        -> build -> artifact -> registry -> deployment
```

Mỗi nút có thể bị compromise; mỗi cạnh là nơi danh tính hoặc nội dung phải được xác minh. Vì vậy,
“pipeline đã chạy xanh” không tự chứng minh output đáng tin.

Ba câu hỏi cần theo artifact suốt vòng đời:

1. **Identity:** ai hoặc workload nào thực hiện hành động?
2. **Integrity:** byte nào đã được tạo, lưu và triển khai?
3. **Policy:** bằng chứng nào khiến hệ thống cho phép hành động đó?

## 2. Thuộc tính an toàn cần đạt

| Thuộc tính | Câu hỏi kiểm chứng |
|---|---|
| Authenticity | Artifact có thật sự đến từ producer/workflow được phép không? |
| Integrity | Nội dung có đổi sau khi build hoặc trong lúc phân phối không? |
| Traceability | Có lần ngược digest về source, dependency, builder và approval không? |
| Reproducibility | Cùng input đã khai báo có tạo output tương đương không? |
| Availability | Registry, key, mirror hoặc update system hỏng thì có phục hồi an toàn không? |
| Revocability | Khi compromise, có chặn signer, builder, package và digest cụ thể không? |

Security tốt không có nghĩa là “không bao giờ dùng third party”. Nó nghĩa là dependency được nhận diện,
đánh giá, cố định, giám sát và có đường thay thế hoặc cô lập khi niềm tin thay đổi.

## 3. Threat model theo từng giai đoạn

| Giai đoạn | Ví dụ tấn công | Control chính |
|---|---|---|
| Source | account takeover, branch/tag bị sửa | MFA/passkey, review, protected branch/tag |
| Resolve | dependency confusion, typosquatting | namespace policy, allowlist registry, lock + digest |
| Build | workflow injection, runner persistence | review workflow, isolated ephemeral runner, least privilege |
| Package | build output bị thay thế | provenance, signature, immutable digest |
| Store | tag overwrite, registry admin compromise | immutable repository, RBAC, audit, retention |
| Deploy | bỏ qua verifier, dùng artifact khác | admission policy, verify identity + claim + digest |
| Update | rollback/freeze/mix-and-match | signed versioned metadata, expiry, threshold roles |

Threat scenario nên viết cụ thể: actor, capability, entry point, target, expected impact và evidence có thể
quan sát. “Rủi ro supply chain” quá rộng để thiết kế control hoặc test.

## 4. Vai trò và ranh giới trách nhiệm

Tách tối thiểu các vai trò sau:

- maintainer thay source và dependency;
- reviewer phê duyệt code hoặc workflow nhạy cảm;
- builder tạo artifact;
- signer hoặc identity provider xác nhận nguồn gốc;
- registry lưu artifact và attestation;
- policy owner định nghĩa điều kiện promote/deploy;
- verifier thực thi policy;
- operator xử lý revoke, quarantine và rollback.

Không nên để một credential vừa sửa source, đổi workflow, build, ký, sửa policy, vừa triển khai production.
Separation of duties làm giảm blast radius và tạo bằng chứng độc lập.

## 5. Inventory toàn bộ input của build

Inventory không chỉ gồm thư viện runtime. Cần liệt kê:

- source repository, commit, submodule và generated source;
- dependency trực tiếp, bắc cầu, test, annotation processor;
- build plugin, action, script, wrapper và init script;
- compiler/JDK, OS package, container base image;
- mirror, cache, binary được tải trong lúc build;
- configuration ảnh hưởng output, kể cả feature flag build-time.

Mỗi input nên có ecosystem, tên chuẩn, version, nguồn, digest, owner, purpose và cách cập nhật. Nếu một
input không thể định danh ổn định, provenance và SBOM sẽ khó dùng khi incident xảy ra.

## 6. Quy trình tiếp nhận component bên thứ ba

Một dependency mới nên đi qua quy trình nhẹ nhưng có dấu vết:

```text
need -> candidate -> identity/source check -> security/license/support review
     -> approved version/source -> automated update -> continuous monitoring
```

Đánh giá gồm mức cần thiết, maintainer và release practice, lịch sử compromise, khả năng thay thế,
license, EOL, tốc độ vá, quyền mà component nhận khi chạy. Package có ít CVE chưa chắc ít rủi ro nếu
maintainer đã bỏ dự án hoặc install script có quyền cao.

## 7. Phân loại dependency để không bỏ sót

| Loại | Ví dụ | Vì sao quan trọng |
|---|---|---|
| Runtime | web framework, JDBC driver | đi vào production và xử lý dữ liệu thật |
| Transitive | logging library kéo gián tiếp | dễ không được team nhìn thấy |
| Build-time | Maven/Gradle plugin | chạy code trong môi trường build |
| Test/dev | test container, formatter | có thể chạy trên CI có token hoặc network |
| Toolchain | JDK, compiler, linker | có thể thay đổi hoặc cài payload vào output |
| Deployment | Helm chart, base image | quyết định thành phần và quyền lúc chạy |

Scope SCA, SBOM và policy cần nói rõ loại nào được bao phủ. “Đã scan dependencies” là tuyên bố vô nghĩa
nếu tool chỉ thấy dependency runtime của một module.

## 8. Dependency confusion và typosquatting

Dependency confusion xảy ra khi resolver chọn package cùng tên từ nguồn không đáng tin, thường do
public version cao hơn private version. Typosquatting dùng tên gần giống package phổ biến.

Phòng thủ:

- reserve namespace nội bộ và không trộn repository tùy tiện;
- route namespace nội bộ chỉ đến private registry;
- allowlist repository và chặn repository do project tự thêm;
- pin version/digest, kiểm tra publisher và nguồn;
- cảnh báo tên tương tự, package mới hoặc ownership vừa đổi;
- không đưa tên package private nhạy cảm vào log công khai.

Repository order không phải control đầy đủ nếu resolver vẫn có thể chọn artifact từ nguồn khác.

## 9. Danh tính package: coordinate chưa đủ

`group:name:version` mô tả logical component nhưng không luôn xác định byte duy nhất. Cùng coordinate có
thể bị republish ở hệ sinh thái cho phép nội dung thay đổi.

Một identity hữu ích nên kết hợp:

```text
ecosystem + namespace/name + version + repository origin + cryptographic digest
```

Package URL (purl) giúp chuẩn hóa tham chiếu giữa SBOM và scanner. Digest mới là neo cho nội dung cụ thể;
version phục vụ ý nghĩa release và truy vấn advisory. Cần lưu cả hai.

## 10. Version constraint, lockfile và digest

Version range như `1.+`, `latest`, snapshot hoặc image tag động làm input thay đổi mà source không đổi.
Release build nên:

- cố định dependency trực tiếp và bắc cầu qua lock/resolved graph;
- commit lockfile và review diff;
- xác minh checksum/signature của artifact;
- cập nhật qua pull request có test, scan và approval;
- không chấp nhận changing module cho release.

Lockfile bảo đảm resolver chọn lại cùng version, nhưng không bảo đảm repository trả về cùng byte. Vì vậy
dependency verification bằng digest/signature vẫn cần thiết.

## 11. Kiểm soát Maven và Gradle thực tế

### Gradle

```kotlin
dependencyLocking {
    lockAllConfigurations()
}
```

```bash
./gradlew dependencies --write-locks
./gradlew --write-verification-metadata sha256 help
```

Commit lock state và `gradle/verification-metadata.xml`; review thay đổi checksum như thay đổi source.
Wrapper cần cố định distribution URL và `distributionSha256Sum`.

### Maven

Maven không có lockfile native tương đương Gradle cho mọi dependency. Dùng `dependencyManagement`/BOM,
pin dependency và plugin version, Maven Enforcer để kiểm tra convergence/rule tổ chức, chặn snapshot cho
release, và kiểm soát mirror trong `settings.xml`. Maven Wrapper cũng phải được review và cố định bản
phân phối/checksum theo cơ chế mà phiên bản wrapper hỗ trợ.

## 12. Plugin, action và script là code thực thi

Build plugin, GitHub Action, `curl | sh`, package install hook, Gradle init script hoặc Maven extension đều
có thể đọc workspace, token và network. Chúng không chỉ là “cấu hình”.

Control cần có:

- pin action bên thứ ba bằng full commit SHA; tag có thể đổi;
- allowlist plugin/action và review publisher/source;
- pin wrapper, tool binary và checksum;
- tách job chạy code không tin cậy khỏi job có secret/quyền ghi;
- chặn download executable tùy ý trong release job;
- inventory cả reusable workflow và composite action.

## 13. Bảo vệ source repository

Repository là control plane của build. Baseline gồm phishing-resistant MFA cho maintainer quan trọng,
least privilege, protected default branch, review bắt buộc, status check, signed/auditable release và
audit log được giữ ngoài repository.

Các file cần xem là nhạy cảm:

- workflow CI/CD và reusable workflow;
- dependency manifest/lockfile;
- build script, containerfile, deployment manifest;
- CODEOWNERS, policy, action configuration;
- release/tag configuration.

Compromise workflow có thể nguy hiểm hơn một lỗi trong business code vì nó điều khiển token và signer.

## 14. Review, CODEOWNERS, branch và tag

CODEOWNERS giúp route review nhưng không tự cưỡng chế nếu branch rule không yêu cầu approval phù hợp.
Thiết kế tốt:

- owner riêng cho workflow, release, policy và dependency;
- không cho author tự là approval duy nhất ở thay đổi nhạy cảm;
- dismiss approval khi commit mới được đẩy;
- hạn chế force push, branch deletion và bypass;
- bảo vệ release tag hoặc tạo tag từ workflow đã phê duyệt;
- log mọi bypass/break-glass và review sau sự kiện.

Review cần xem diff generated/lockfile, không chỉ application code.

## 15. Workflow injection và pull request không tin cậy

PR từ fork hoặc contributor chưa tin cậy là input do attacker điều khiển: source, filename, branch name,
test output và đôi khi metadata. Không nội suy trực tiếp dữ liệu đó vào shell command.

Nguyên tắc:

- job test PR dùng token read-only, không có production secret;
- không checkout/chạy code PR trong workflow đặc quyền như `pull_request_target`;
- truyền input qua argument/env được quote đúng, không ghép command string;
- job publish chỉ chạy trên ref/event được phép sau approval;
- artifact từ job không tin cậy không được job đặc quyền tiêu thụ mà thiếu verification.

## 16. Runner isolation và tính dùng một lần

Runner self-hosted có thể giữ malware, process, file, credential hoặc cache sau job. Public repository gần
như không nên chạy PR không tin cậy trên runner nội bộ có network doanh nghiệp.

Release runner nên:

- ephemeral/JIT: một job, sau đó hủy;
- image nền được quản lý, patch và đo integrity;
- namespace/VM riêng, không mount socket đặc quyền;
- egress allowlist theo nhu cầu;
- không dùng chung với job untrusted;
- log control-plane gửi ra ngoài runner trước khi hủy.

“Dọn workspace” không tương đương tái tạo isolation boundary.

## 17. Credential build và workload identity

Ưu tiên OIDC/workload federation để CI đổi identity đã được attestation lấy credential ngắn hạn. Policy
cloud/registry cần ràng buộc issuer, audience, repository, workflow/ref/environment và action được phép.

Không nên:

- lưu cloud key dài hạn trong CI secret nếu federation khả dụng;
- cấp token ghi package cho mọi PR/job;
- dùng cùng credential cho build, sign và deploy;
- ghi token vào command line, artifact, cache hoặc debug log.

Credential ngắn hạn giảm cửa sổ lạm dụng nhưng claim binding và least privilege mới giới hạn danh tính
nào có thể nhận nó.

## 18. Network, mirror và build cache

Release build lý tưởng chỉ đọc từ mirror/registry đã kiểm soát. Egress tự do cho phép build script tải
payload hoặc exfiltrate credential.

Build cache cũng là input không tin cậy nếu attacker có thể ghi key mà privileged build sẽ đọc. Cần:

- namespace cache theo trust level và project;
- xác thực writer, content-addressed key và integrity check;
- không chia cache giữa PR untrusted và release nếu output có thể được tái sử dụng;
- lưu provenance của cache hit hoặc buộc rebuild bước nhạy cảm;
- có kill switch để vô hiệu hóa/purge cache khi incident.

Mirror cần RBAC, immutable artifact, upstream allowlist, malware scan và audit tương tự registry release.

## 19. Hermetic, repeatable và reproducible build

Ba khái niệm liên quan nhưng không đồng nghĩa:

- **Hermetic:** build chỉ truy cập input đã khai báo và cô lập khỏi môi trường ngoài.
- **Repeatable:** chạy lại trong cùng môi trường cho kết quả ổn định.
- **Reproducible:** bên độc lập với input tương đương có thể tạo output tương đương/bit-for-bit theo định nghĩa.

Hermetic giúp biết input, reproducible giúp phát hiện khác biệt, nhưng một thuộc tính không tự chứng minh
thuộc tính kia. Timestamp, locale, file order, random seed và đường dẫn build thường phá reproducibility.

## 20. Cố định toolchain và output xác định

Pin JDK/compiler, build tool, plugin, OS/base image bằng version và digest. Chuẩn hóa timezone, locale,
archive ordering, timestamp policy, file permission và nguồn random nếu output cho phép.

Không nên nhúng secret hoặc thông tin runner vào artifact để “trace”. Dùng provenance ngoài artifact.
Sau build, tính digest một lần và dùng chính digest đó cho scan, sign, attest, promote và deploy.

Nếu bước sau sửa artifact—ví dụ repackage hoặc thêm file—đó là artifact mới, cần digest và bằng chứng mới.

## 21. SLSA 1.2 và mức bảo đảm build

SLSA là framework tăng dần assurance cho artifact. Bản đặc tả **SLSA 1.2** hiện ở trạng thái Approved, gồm
Build Track, Source Track và các định dạng attestation như provenance.

Điểm quan trọng:

- level áp dụng cho artifact/build cụ thể, không phải nhãn vĩnh viễn cho cả công ty;
- level build không tự truyền xuống dependency bắc cầu;
- claim phải được verifier kiểm tra, không chỉ được producer phát hành;
- assurance cao hơn đòi hỏi builder được kiểm soát và chống can thiệp mạnh hơn.

Chọn target level theo threat model, không dùng badge thay cho phân tích rủi ro.

## 22. Provenance phải ràng buộc điều gì

Provenance hữu ích cần liên kết:

```text
subject digest (output)
    <- source repository + commit/ref
    <- trusted builder identity
    <- build type/workflow
    <- declared parameters
    <- resolved materials/inputs
```

Verifier cần kiểm tra subject digest đúng artifact đang promote, builder ID nằm trong allowlist, source/ref
đúng repository/branch, build type được phép và parameter nhạy cảm không bị thay đổi.

Một JSON provenance “hợp lệ cú pháp” nhưng subject không khớp hoặc builder không được tin cậy không có giá trị.

## 23. Attestation và in-toto

Attestation là tuyên bố có chữ ký về một subject. Mô hình in-toto thường dùng statement bao gồm subject và
predicate; predicate type xác định schema của claim, ví dụ provenance, SBOM hoặc kết quả kiểm tra.

in-toto còn hỗ trợ mô tả layout: bước nào phải chạy, functionary nào được phép, material/product nào được
tạo và thứ tự nào được chấp nhận. Nó giúp phát hiện bước bị bỏ qua hoặc artifact bị thay giữa các bước.

Consumer luôn phải xác minh signature, identity, subject digest, predicate type/version và policy dành cho
claim đó. Không diễn giải field tùy tiện giữa các schema.

## 24. Phân biệt signature, provenance, SBOM và scan

| Bằng chứng | Trả lời tốt | Không tự chứng minh |
|---|---|---|
| Signature | ai/identity nào ký đúng byte này | byte đó an toàn hoặc build đúng quy trình |
| Provenance | output đến từ source/builder/input nào | source/dependency không có lỗ hổng |
| SBOM | artifact khai báo/chứa component nào | component đầy đủ, an toàn hay được phép |
| Scan report | tool thấy finding gì tại thời điểm scan | không có false negative hoặc runtime không bị đổi |
| VEX | supplier đánh giá exploitability ra sao | claim đúng mãi mãi hoặc áp dụng cho mọi deployment |

Các bằng chứng bổ trợ nhau. Policy mạnh thường cần nhiều claim cùng gắn vào một digest.

## 25. Sigstore keyless signing

Trong keyless flow, signer tạo key tạm thời; Fulcio cấp certificate ngắn hạn gắn public key với OIDC
identity; Rekor ghi sự kiện vào transparency log; trust root được phân phối qua TUF.

Verifier không được chỉ hỏi “signature Sigstore có hợp lệ không?”. Cần ràng buộc:

- certificate issuer được tin cậy;
- subject/SAN hoặc workflow identity đúng repository và workflow;
- artifact digest khớp;
- certificate/signature hợp lệ tại thời điểm ký;
- log inclusion và policy về integrated time nếu cần.

Keyless giảm quản lý private key dài hạn, không biến mọi OIDC identity thành signer được phép.

## 26. Signing key truyền thống

Khi dùng key dài hạn:

- generate và giữ private key trong KMS/HSM khi khả thi;
- tách key theo environment, product và purpose;
- signer service xác thực workload, không phát private key cho runner;
- dùng threshold/dual control cho root hoặc release quan trọng;
- rotation có overlap verifier rõ ràng;
- inventory certificate/key ID, owner, expiry, artifact lifetime và revoke procedure.

Backup key tăng availability nhưng cũng tăng attack surface. Mỗi bản sao phải có protection, access audit
và restore drill tương xứng.

## 27. Transparency log: giá trị và giới hạn

Transparency log cho phép phát hiện và kiểm toán sự kiện ký, hỗ trợ chứng minh inclusion và làm hành vi
khó bị che giấu hơn. Nó không phải scanner, approval system hoặc danh sách signer tốt.

Một chữ ký độc hại vẫn có thể được ghi công khai. Monitor nên cảnh báo signer/repository bất thường,
release ngoài giờ, volume đột biến hoặc artifact không tồn tại trong release catalog.

Khi log tạm thời không truy cập được, policy cần xác định fail-closed, cached checkpoint hay deferred
verification theo mức rủi ro; không âm thầm bỏ qua kiểm tra.

## 28. Hardening artifact registry

Registry production nên có:

- namespace/project ownership rõ ràng;
- quyền push/pull/delete tách biệt và token ngắn hạn;
- immutable release hoặc chống overwrite;
- retention bảo vệ artifact đang chạy và artifact rollback;
- replication/backup được kiểm thử;
- audit push, delete, policy change và admin action;
- quarantine area cho artifact nghi vấn;
- liên kết signature, SBOM, provenance với digest.

Không cho developer laptop push thẳng repository production nếu release workflow đã là nguồn tin cậy.

## 29. Tag có thể đổi, digest mới bất biến

`app:1.4` hoặc `app:latest` là con trỏ có thể bị đổi. `sha256:...` định danh nội dung cụ thể.

Quy trình an toàn:

```text
build once -> digest D -> scan/attest/sign D -> promote D -> deploy D
```

Tag vẫn hữu ích cho con người nhưng deployment manifest và evidence phải neo vào digest. Admission nên
resolve/verify có kiểm soát hoặc yêu cầu digest trực tiếp; tránh time-of-check/time-of-use khi tag đổi giữa
lúc kiểm tra và lúc pull.

## 30. SBOM là gì và không phải gì

SBOM là inventory có cấu trúc về component và quan hệ trong một sản phẩm/phần mềm. Nó hỗ trợ impact
analysis, vulnerability response, license review và trao đổi với khách hàng.

SBOM không tự chứng minh:

- component không độc hại;
- danh sách hoàn chỉnh;
- artifact được build từ source đã khai báo;
- license đã tuân thủ;
- vulnerability có thể hoặc không thể khai thác;
- artifact đang chạy đúng là artifact được mô tả.

SBOM phải gắn với artifact digest/version cụ thể và có source, timestamp, tool/schema version.

## 31. SBOM ở các điểm khác nhau

| Loại | Cách tạo | Ưu/nhược điểm |
|---|---|---|
| Source SBOM | từ manifest/lockfile | sớm, nhưng có thể thiếu file/runtime component |
| Build SBOM | builder ghi material/output | gần quy trình thật, cần builder đáng tin |
| Binary/analyzed SBOM | phân tích JAR/image/filesystem | thấy nội dung đóng gói, có thể khó nhận diện chính xác |
| Deployed BOM | inventory digest đang chạy + cấu hình liên quan | hữu ích cho incident, phải cập nhật liên tục |

So sánh nhiều nguồn giúp phát hiện component khai báo nhưng không đóng gói, hoặc component xuất hiện trong
binary nhưng không có trong manifest. Ghi rõ scope thay vì hợp nhất mù quáng.

## 32. SPDX và CycloneDX

SPDX và CycloneDX đều là chuẩn machine-readable phổ biến:

- **SPDX** mạnh về định danh package/file, relationship, license và trao đổi dữ liệu supply chain;
- **CycloneDX** mô hình hóa component, service, dependency graph, vulnerability/VEX và formulation.

Chọn theo consumer, toolchain và hợp đồng; không cần tạo hai format nếu không có người dùng. Luôn ghi
schema/version, validate document, bảo toàn identifier và test import/export. Mapping giữa format có thể
làm mất field; không giả định round-trip hoàn hảo.

## 33. Chất lượng và độ đầy đủ của SBOM

Một SBOM dùng được cần:

- product/artifact identity và digest;
- component name, version, ecosystem/purl và hash khi có;
- dependency relationship, không chỉ danh sách phẳng;
- scope: module, architecture, optional/dev/runtime;
- supplier/origin hợp lý;
- tool/generator, timestamp, schema version;
- composition/completeness hoặc giới hạn đã biết.

Đo coverage bằng cách đối chiếu manifest, lockfile, build material và binary scan. “SBOM generated = true”
không phải quality metric.

## 34. VEX và trạng thái exploitability

VEX truyền đạt một vulnerability đã biết có ảnh hưởng sản phẩm cụ thể hay không. Trạng thái như affected,
not affected, fixed hoặc under investigation phải kèm product/component/version chính xác.

Claim `not affected` cần justification và evidence, ví dụ vulnerable code không hiện diện hoặc không thể
được gọi trong cấu hình hỗ trợ. Claim cần issuer, thời gian, scope, expiry/review trigger và chữ ký khi trao
đổi qua trust boundary.

VEX không xóa CVE. Thay code, configuration, feature hoặc intelligence mới phải kích hoạt đánh giá lại.

## 35. Vulnerability intelligence và matching

Scanner cần map package identity/version vào advisory từ nguồn như OSV hoặc ecosystem database. Sai
ecosystem, version range hoặc package alias có thể tạo false positive/negative.

Pipeline nên lưu:

- advisory ID và nguồn/version dữ liệu;
- component identity và evidence matching;
- scan time, tool/rule version;
- affected fixed version nếu có;
- triage state, owner, expiry và suppression rationale.

Rescan inventory khi advisory mới xuất hiện; không cần rebuild để biết artifact cũ vừa có CVE mới.

## 36. Ưu tiên SCA theo khả năng khai thác

CVSS chỉ là một đầu vào. Priority production nên xét:

```text
known exploitation + reachability/exposure + runtime presence
    + asset/data criticality + privilege + blast radius
    + fix availability/compensating control + confidence
```

Một critical CVE trong test-only dependency có thể thấp hơn high CVE đang reachable từ Internet, nhưng
test dependency vẫn quan trọng nếu nó chạy trên privileged CI. Suppression phải có owner, rationale,
evidence, expiry và trigger mở lại.

## 37. License, EOL và sức khỏe maintainer

Supply-chain risk còn gồm:

- license không tương thích hoặc nghĩa vụ phân phối;
- component hết hỗ trợ, không có đường vá;
- bus factor thấp, ownership/publisher vừa thay;
- release process không ký hoặc không công bố advisory;
- binary blob không có source/provenance;
- dependency quá sâu hoặc khó thay thế.

Policy nên có approved/denied license, EOL deadline, exception workflow và owner. OpenSSF Scorecard cung
cấp tín hiệu tự động về practice của dự án, nhưng không phải điểm tin cậy tuyệt đối.

## 38. Phân phối update an toàn với TUF

The Update Framework (TUF) dùng metadata có chữ ký, phân vai và version/expiry để phòng nhiều lỗi update
system ngay cả khi một số key/repository bị compromise.

Các ý tưởng cốt lõi:

- root, targets, snapshot và timestamp có trách nhiệm khác nhau;
- threshold signature giảm rủi ro một key;
- version và hash ngăn rollback/mix-and-match;
- expiry giúp phát hiện freeze;
- root rotation có quy trình tin cậy.

Ký artifact đơn lẻ không thay thế một update protocol có chống rollback và metadata consistency.

## 39. Verification tại promotion và deployment

Tạo evidence mà không có consumer kiểm tra chỉ tăng chi phí lưu trữ. Policy ở promotion/admission nên xác
minh theo digest:

- signature hợp lệ và signer/workflow identity được phép;
- provenance từ builder/source/ref đúng policy;
- SBOM tồn tại, đúng schema và quality tối thiểu;
- scan/VEX đủ mới, không có finding vượt ngưỡng;
- artifact chưa bị revoke/quarantine;
- exception còn hạn và đúng scope.

Policy change cũng là supply-chain change: review, test, version, audit và rollback như code.

## 40. Build once, promote cùng artifact

Không rebuild cùng source riêng cho dev, staging và production. Mỗi lần rebuild tạo byte và provenance mới,
làm staging không còn kiểm thử đúng thứ production sẽ chạy.

Thay vào đó:

```text
build D -> test D -> stage D -> approve -> promote D -> production D
```

Configuration môi trường nên được inject bên ngoài artifact, có validation và audit riêng. Nếu bắt buộc
biến đổi artifact, coi đó là build mới và chạy lại verification phù hợp.

## 41. Inventory artifact đang chạy

Incident response cần biết **digest nào đang chạy ở đâu**, không chỉ version dự kiến trong Git.

Deployed inventory nên nối:

- cluster/host/workload/environment;
- artifact digest và runtime component;
- deployment time và controller/identity;
- provenance, SBOM, scan/VEX tương ứng;
- owner, criticality và external exposure.

Reconcile desired state với observed state. Khi advisory hoặc signer revoke mới xuất hiện, truy vấn inventory
để tìm blast radius và kích hoạt policy/redeploy.

## 42. Yêu cầu với vendor và procurement

Không chỉ hỏi vendor “có SBOM không?”. Yêu cầu cần đo được:

- format/schema, delivery channel và artifact binding;
- provenance/signing identity và verification instruction;
- vulnerability disclosure, notification SLA và patch window;
- support/EOL, dependency/update policy;
- incident cooperation và cách công bố key/build compromise;
- quyền kiểm chứng, retention evidence và exception process.

Evidence từ vendor phải được verify và thử dùng trong tabletop; PDF tuyên bố chung không giúp truy vết
một digest cụ thể khi incident.

## 43. OpenSSF Scorecard là tín hiệu, không phải phán quyết

Scorecard tự động kiểm tra một số practice của project nguồn mở như branch protection, pinned dependency,
token permission hoặc release practice. Dùng nó để ưu tiên review và phát hiện regression.

Không đặt policy kiểu “điểm < X thì cấm” mà không xét context: metric có thể không quan sát được repository
private, project có mô hình release khác, hoặc attacker tối ưu theo checklist. Kết hợp Scorecard với
maintainer review, provenance, dependency need, runtime privilege và khả năng thay thế.

## 44. Runbook: package hoặc dependency độc hại

1. Xác minh advisory/evidence; giữ package, lockfile, log và digest liên quan.
2. Chặn version/digest/publisher ở mirror và resolver; không xóa evidence.
3. Truy vấn SBOM + deployed inventory để xác định build và environment bị ảnh hưởng.
4. Cô lập workload, rotate credential mà malicious code có thể đọc.
5. Chọn fixed version hoặc loại dependency; rebuild trên runner sạch với input đã kiểm chứng.
6. Tạo provenance/signature/SBOM mới, verify và redeploy theo ưu tiên.
7. Hunt hành vi hậu compromise, không chỉ thay package.
8. Cập nhật intake policy, detection và retrospective.

Chỉ bump version là chưa đủ nếu payload đã lấy token hoặc persistence đã tồn tại.

## 45. Runbook: builder hoặc signing identity bị compromise

1. Đóng băng release/promotion liên quan và bảo toàn audit, attestation, runner snapshot nếu phù hợp.
2. Revoke/disable credential, workload trust hoặc certificate; chặn builder/signer identity trong policy.
3. Liệt kê mọi artifact ký/build trong cửa sổ nghi vấn từ transparency/audit log.
4. Quarantine digest; so sánh provenance với source, approval và independent reproduction nếu có.
5. Tái tạo runner/builder từ root tin cậy, rotate downstream secret và kiểm tra policy tampering.
6. Rebuild artifact sạch, phát hành evidence mới và redeploy.
7. Thông báo consumer/vendor theo impact và cập nhật root/trust policy có kiểm soát.

Không revoke toàn bộ artifact lịch sử nếu có thể scope chính xác, nhưng cũng không tin artifact chỉ vì source
commit trông đúng: compromised builder có thể tạo output khác.

## 46. Revoke, quarantine và rollback

Revocation có nhiều lớp:

- signer/certificate/workload identity;
- builder/workflow/source ref;
- package version hoặc publisher;
- artifact digest;
- attestation/VEX cụ thể.

Verifier cần nhận và áp dụng trạng thái đủ nhanh. Rollback phải dùng artifact bất biến đã từng được verify,
vẫn nằm trong support window và không bị revoke; không rebuild vội một tag cũ.

Quarantine giữ artifact/evidence chỉ cho điều tra, chặn promotion/deploy. Test kill switch và break-glass,
bao gồm cách hết hạn quyền khẩn cấp sau incident.

## 47. Kiểm thử control supply chain

Đừng chỉ test happy path. Tạo negative test cho:

- signature đúng nhưng signer sai;
- provenance đúng schema nhưng subject digest sai;
- source repository đúng nhưng branch/workflow sai;
- SBOM thiếu dependency graph hoặc sai artifact;
- tag bị đổi sau khi verify;
- expired certificate/metadata/exception;
- revoked digest hoặc VEX quá hạn;
- registry/transparency log không truy cập được;
- cache bị ghi bởi job không tin cậy;
- policy engine fail-open.

Tabletop định kỳ package compromise và builder compromise để đo inventory completeness, revoke latency và
khả năng rebuild sạch.

## 48. Metrics và SLO hữu ích

| Metric | Ý nghĩa |
|---|---|
| % production digest có provenance/signature/SBOM hợp lệ | coverage thật, không chỉ file được tạo |
| % deploy được admission verify | khả năng evidence được tiêu thụ |
| Dependency/SBOM completeness rate | chất lượng inventory |
| Unpinned/dynamic input count | build drift exposure |
| Mean time advisory -> impacted deployments identified | tốc độ impact analysis |
| Mean time revoke -> enforcement | cửa sổ artifact xấu còn chạy được |
| Ephemeral runner/restricted-egress coverage | isolation maturity |
| Exception age và expired exception count | security debt/policy bypass |
| Clean rebuild và rollback drill success | recoverability |

Không tối ưu số lượng SBOM, signature hoặc scan. Tối ưu khả năng đưa ra quyết định đúng trên artifact đang chạy.

## 49. Pipeline Java/Maven/Gradle end-to-end

Một pipeline tham chiếu:

```text
PR (untrusted, no secret)
  -> lint/test/SAST/SCA
  -> review source + workflow + lock/verification metadata
merge protected branch
  -> ephemeral restricted runner
  -> resolve only approved mirror; verify dependencies
  -> hermetic-ish build with pinned JDK/wrapper/toolchain
  -> test artifact; generate SBOM; scan exact artifact
  -> calculate digest once
  -> emit SLSA provenance + attest SBOM/results
  -> sign digest using workload identity
  -> push immutable artifact/evidence
  -> promotion verifies claims and approval
  -> admission verifies same digest and policy
  -> observe deployed digest; continuously re-evaluate advisories
```

Maven/Gradle lock, checksum và wrapper control bảo vệ resolution; provenance chứng minh build path; signature
bảo vệ identity/integrity; admission biến bằng chứng thành quyết định. Không control đơn lẻ nào thay thế tất cả.

## 50. Checklist production, anti-pattern và tài liệu chính thức

### Checklist tối thiểu

- [ ] Inventory source, dependency, plugin, action, toolchain, base image và mirror.
- [ ] Pin version/digest; commit lock/verification metadata; cấm changing input cho release.
- [ ] Bảo vệ branch, tag, workflow và policy bằng review độc lập.
- [ ] Tách PR untrusted khỏi job có secret/quyền ghi; dùng ephemeral runner.
- [ ] Dùng workload identity/credential ngắn hạn và least privilege.
- [ ] Build một lần; gắn digest với provenance, signature, SBOM và scan.
- [ ] Registry immutable; deploy theo digest; promotion/admission verify claim và identity.
- [ ] Theo dõi deployed inventory và re-evaluate khi advisory/revocation thay đổi.
- [ ] Có runbook package, builder, signer compromise; drill rollback/rebuild sạch.

### Anti-pattern thường gặp

- “Image đã ký nên chắc chắn an toàn.”
- “Có SBOM nghĩa là không còn dependency risk.”
- “CI xanh nên artifact đúng source.”
- “Tag version là immutable.”
- “Lockfile đủ để chống artifact bị republish.”
- “Sinh provenance nhưng deployment không kiểm tra.”
- “Self-hosted runner đã xóa workspace nên sạch.”
- “SLSA level của ứng dụng tự áp dụng cho mọi dependency.”

### Tài liệu chính thức

- [SLSA Specification v1.2](https://slsa.dev/spec/v1.2/)
- [NIST SP 800-218 – Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [NIST SP 800-161 Rev. 1 – Cybersecurity Supply Chain Risk Management](https://csrc.nist.gov/pubs/sp/800/161/r1/final)
- [Sigstore – Signing with Cosign](https://docs.sigstore.dev/cosign/signing/overview/)
- [in-toto Specifications](https://in-toto.io/docs/specs/)
- [The Update Framework](https://theupdateframework.io/)
- [SPDX Specifications](https://spdx.dev/use/specifications/)
- [CycloneDX Specification Overview](https://cyclonedx.org/specification/overview/)
- [OpenSSF Scorecard](https://scorecard.dev/)
- [GitHub Actions – Secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub Artifact Attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- [Gradle Dependency Locking](https://docs.gradle.org/current/userguide/dependency_locking.html)
- [Gradle Dependency Verification](https://docs.gradle.org/current/userguide/dependency_verification.html)
- [Apache Maven Wrapper](https://maven.apache.org/tools/wrapper/)
- [OSV Documentation](https://google.github.io/osv.dev/)

### Học tiếp

1. [Container & Kubernetes Runtime Security](../runtime/container_kubernetes_runtime_security.md) – admission, workload isolation, policy và runtime detection.
2. [Cloud-Native Detection & Incident Response](../detection/cloud_native_detection_incident_response.md) – kết nối artifact identity với telemetry, triage và containment.

---

*Cập nhật lần cuối: 2026-08-02.*
