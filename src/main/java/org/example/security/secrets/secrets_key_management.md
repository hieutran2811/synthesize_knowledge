# Secrets & Key Management – Quản lý bí mật và khóa mật mã trong production

Secret không an toàn chỉ vì đã được chuyển từ `application.yml` sang một vault. Hệ thống chỉ
an toàn khi kiểm soát được toàn bộ vòng đời: ai tạo, ai được đọc hoặc sử dụng, secret nằm ở
đâu, consumer nào phụ thuộc, khi nào hết hạn, cách rotate không downtime và cách thu hồi khi
bị lộ.

Tài liệu này tập trung vào phòng thủ và vận hành. Kiến thức thuật toán nằm tại
[Crypto Fundamentals](../crypto/crypto_fundamentals.md), PKI/TLS nằm tại
[PKI & TLS](../crypto/pki_tls.md), còn workload identity nằm tại
[IAM §41](../identity/iam_authentication_authorization.md).

---

## 1. Secrets management là một control plane

Secret có mặt ở mọi đường đi quan trọng:

```text
source code → CI/CD → artifact → runtime → database/cloud/SaaS
                 ↘ secret store/KMS/HSM ↗
```

Nếu control plane này bị chiếm, attacker không cần khai thác từng application: họ có thể lấy
database password, signing key, cloud credential hoặc khóa giải mã của nhiều hệ thống. Vì vậy
secrets platform phải được xem là tier-0: identity mạnh, network boundary, audit độc lập, backup,
disaster recovery và break-glass được kiểm thử.

## 2. Phân biệt secret, credential và cryptographic key

| Loại | Ví dụ | Công dụng | Có cần bí mật? |
|---|---|---|---|
| Secret | webhook secret, database password | Giá trị nhạy cảm tổng quát | Có |
| Credential | API key, access token, client secret | Chứng minh identity/quyền | Có |
| Symmetric key | AES key, HMAC key | Encrypt/decrypt hoặc MAC | Có |
| Private key | TLS/signing private key | Decrypt, sign hoặc key agreement | Có |
| Public key/certificate | JWKS, TLS certificate | Verify/encrypt, gắn key với identity | Không, nhưng cần integrity |
| Salt/nonce/IV | password salt, GCM nonce | Tham số mật mã | Thường không; phải đúng tính chất |
| Config | URL, feature flag | Cấu hình không nhạy cảm | Không mặc định |

Không nên gắn nhãn mọi config là secret. Nếu dữ liệu không cần confidentiality nhưng cần chống
sửa đổi, bài toán chính là integrity/provenance chứ không phải che giấu.

## 3. Threat model: secret thường rò ở đâu?

```text
Create      Distribution      Runtime          Operations
  │              │               │                 │
weak RNG      CI log          env/process       backup/export
copy/paste    chat/ticket     crash dump        audit log
default       Git history     debug endpoint    admin session
```

Các đường tấn công phổ biến:

- hardcode trong source, image layer, mobile binary hoặc frontend bundle;
- quyền `list/watch/get` quá rộng với secret store;
- SSRF lấy workload credential hoặc metadata token;
- command line, environment, exception, tracing và support bundle làm lộ plaintext;
- compromised CI runner/action đọc toàn bộ repository secrets;
- secret dùng chung khiến không biết instance nào đã sử dụng;
- rotation thất bại khiến team giữ key cũ vô thời hạn;
- backup chứa key nhưng không có control tương đương production;
- admin của vault/KMS vừa đổi policy, vừa decrypt, vừa xóa audit.

## 4. Bắt đầu bằng inventory, không bắt đầu bằng công cụ

Mỗi secret/key cần một record quản trị, nhưng inventory không chứa plaintext:

| Metadata | Ví dụ |
|---|---|
| Stable ID/URI | `secret://payments/prod/db-writer` |
| Type/purpose | database credential, KEK, signing key |
| Owner và approver | Payments Platform, Security |
| Issuer/source | database engine, cloud KMS, external SaaS |
| Consumers | service, job, cluster, region |
| Environment/tenant | prod, tenant group A |
| Scope | read schema `payments`, sign access token |
| Created/activated/expires | timestamp và cryptoperiod |
| Current version | `v17`, key ID/alias chỉ để lookup |
| Last used | time, principal, region |
| Rotation/revoke method | automated job và runbook |
| Recovery class | recoverable encryption key hay non-recoverable token |

Không có inventory thì không thể biết blast radius, không thể xóa key an toàn và không thể
chứng minh rotation đã hoàn tất.

## 5. Phân loại theo blast radius và khả năng thay thế

Không nên đặt cùng chính sách cho mọi secret:

```text
Impact cao
  root/CA/KMS administration key
  token-signing key, production database owner
  cross-account deployment credential
  tenant-scoped application secret
  development/test credential
Impact thấp
```

Hai câu hỏi quan trọng:

1. Nếu lộ, attacker truy cập được bao nhiêu dữ liệu/hệ thống và trong bao lâu?
2. Nếu mất, dữ liệu hoặc dịch vụ có phục hồi được không?

Signing key bị mất có thể tạo token giả; encryption key bị mất có thể làm dữ liệu không bao giờ
đọc lại được. Cả hai đều nghiêm trọng nhưng cần runbook khác nhau.

## 6. Vòng đời chuẩn

```text
plan → generate → register → distribute/use → rotate → deactivate
                                  ↑               │
                                  └── overlap ────┘
                     compromise → revoke → investigate
                     retention complete → destroy
```

`Delete` không phải toàn bộ lifecycle. Một hệ thống production cần trạng thái rõ: pre-active,
active, suspended/deactivated, compromised, archived và destroyed. State transition phải được
authorize, audit và có điều kiện rollback phù hợp.

## 7. Ownership và separation of duties

Tối thiểu nên tách:

- platform team vận hành availability của secret store/KMS;
- security/crypto owner định policy và thuật toán;
- application owner khai báo purpose, consumer và rotation test;
- approver cho thao tác high-impact;
- auditor đọc immutable audit trail nhưng không đọc secret;
- incident responder có đường revoke khẩn cấp.

Một người có thể giữ nhiều vai ở công ty nhỏ, nhưng hệ thống vẫn nên tách permission. Không để
một principal vừa sửa key policy, dùng key để decrypt, tắt log và schedule key deletion.

## 8. Tạo secret/key bằng CSPRNG đúng nơi

- Dùng CSPRNG của platform hoặc chức năng generate của KMS/HSM/secret provider.
- Không dùng timestamp, UUID có tính dự đoán, `Math.random()` hoặc password do con người nghĩ.
- Độ dài phụ thuộc loại credential, protocol và threat model; không sao chép một con số cho mọi
  trường hợp.
- Key mật mã phải theo chuẩn thuật toán/thư viện; không biến chuỗi password thành AES key bằng
  padding hoặc hash tùy ý.
- Nếu import key material, phải có ceremony, secure transport, integrity và provenance rõ.

Ví dụ Java cho opaque random token:

```java
import java.security.SecureRandom;
import java.util.Base64;

final class OpaqueSecret {
    private static final SecureRandom RNG = new SecureRandom();

    static String generate256Bits() {
        byte[] value = new byte[32];
        RNG.nextBytes(value);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }
}
```

Đây là cách tạo một opaque value, không thay thế key-generation API của KMS/HSM.

## 9. Một key chỉ nên có một purpose

Không dùng cùng key cho cả encryption, HMAC, signing và key wrapping. Tách purpose giúp:

- tránh tương tác nguy hiểm giữa protocol/algorithm;
- đặt permission riêng như `encrypt` nhưng không `decrypt`;
- đặt cryptoperiod và retention khác nhau;
- giới hạn blast radius;
- migrate thuật toán độc lập.

Key ID, algorithm, usage và application association là security metadata. Đổi nhầm association
có thể nghiêm trọng như lộ key.

## 10. TTL và cryptoperiod dựa trên rủi ro

Không có quy tắc “mọi key phải rotate mỗi 90 ngày”. Chọn lifetime dựa trên:

- độ mạnh thuật toán và lượng dữ liệu/operation được bảo vệ;
- thời gian dữ liệu cần confidentiality/integrity;
- khả năng key bị lộ và tốc độ phát hiện;
- số consumer, khả năng automation và downtime budget;
- yêu cầu pháp lý/contract;
- hậu quả khi key mất hoặc bị compromise.

Ưu tiên credential workload ngắn hạn tính bằng phút/giờ khi issuer hỗ trợ. User password không
phải machine secret để ép rotation định kỳ tùy tiện; đổi khi có bằng chứng/nghi ngờ compromise
và theo chính sách authentication.

## 11. Secret manager, KMS, HSM và TPM không giống nhau

| Thành phần | Vai trò chính | Plaintext thường xuất hiện ở đâu? |
|---|---|---|
| Secret manager/vault | Lưu arbitrary secret, version, policy, distribution | Được trả về consumer sau authorization |
| KMS | Quản lý key và cung cấp encrypt/decrypt/sign/wrap API | Key gốc thường không export; data/plaintext đi qua API hoặc client |
| HSM | Cryptographic module phần cứng, chống can thiệp, giữ key | Operation bên trong boundary; phụ thuộc mode/loại key |
| TPM/secure element | Root of trust cục bộ, sealing/attestation/device key | Thường giới hạn trong thiết bị |

Một managed KMS có thể dùng HSM bên dưới nhưng KMS không đồng nghĩa HSM. Dùng sản phẩm đạt FIPS
không tự làm toàn hệ thống compliant: configuration, key policy, application path và quy trình
vận hành vẫn nằm ngoài cryptographic module boundary.

## 12. HSM phù hợp khi nào?

HSM có giá trị khi cần key non-exportable, tamper resistance, high-assurance signing, payment/CA
requirement hoặc customer-controlled key ceremony. Đổi lại:

- chi phí, latency, quota và vendor-specific integration cao hơn;
- backup/cluster/quorum phức tạp;
- sai ceremony hoặc mất quorum có thể làm mất key;
- application vẫn có thể bị lợi dụng gọi `Sign`/`Decrypt` dù không lấy được raw key.

Vì vậy authorization theo operation, context, rate limit và audit quan trọng ngang việc giữ key
trong hardware.

## 13. Secret zero: vault lấy credential đầu tiên ở đâu?

Đừng giải bằng cách nhúng một vault token dài hạn vào image. Bootstrap tốt dựa trên identity có
thể chứng minh:

```text
workload starts
  → platform attestation / service account / instance identity
  → exchange proof với vault/STS
  → nhận token ngắn hạn, scope hẹp
  → lấy hoặc sinh secret cần thiết
```

Ví dụ: Kubernetes projected service-account token, cloud workload identity, SPIFFE SVID hoặc
machine certificate được provision bằng ceremony riêng. Luôn khóa issuer, audience, subject,
namespace/repository/environment và chống replay theo khả năng platform.

## 14. Ưu tiên identity-based access thay secret tĩnh

Thứ tự ưu tiên thường là:

1. workload identity + token ngắn hạn;
2. dynamic credential có lease;
3. static secret được vault quản lý và auto-rotate;
4. static secret phân phối thủ công chỉ như ngoại lệ có thời hạn.

Loại bỏ secret là biện pháp tốt hơn bảo vệ một secret không cần thiết. Ví dụ CI/CD có thể dùng
OIDC federation để đổi identity của workflow lấy cloud token cho đúng một job, thay vì lưu cloud
access key dài hạn trong CI.

## 15. Static secret và dynamic secret

| Thuộc tính | Static | Dynamic/leased |
|---|---|---|
| Tạo trước | Có | Theo request |
| Chia sẻ | Dễ bị chia sẻ | Có thể unique per workload/job |
| Lifetime | Thường dài | Ngắn, có TTL |
| Revocation | Phải phối hợp provider | Lease/token có thể revoke tự động |
| Audit attribution | Khó nếu dùng chung | Tốt hơn nhờ credential riêng |
| Availability dependency | Có thể cache lâu | Phụ thuộc issuer/renewal nhiều hơn |

Dynamic secret giảm cửa sổ khai thác nhưng không tự giải quyết privilege quá rộng. Role/template
dùng để sinh credential vẫn phải least privilege.

## 16. Lease, renew và revoke

Consumer của dynamic credential phải hiểu contract:

```text
issue(lease TTL=30m)
  → renew trước deadline nếu job còn chạy
  → thay credential atomically
  → revoke khi job kết thúc
  → issuer tự revoke khi lease hết hạn
```

Thiết kế cần xử lý clock skew, retry có jitter, issuer tạm lỗi, renewal bị từ chối và credential
cũ bị revoke. Không retry vô hạn bằng secret đã hết hạn. Phân biệt TTL hiển thị từ KV store với
lease thực sự có thể thu hồi tại hệ thống đích.

## 17. Storage: mã hóa đĩa chưa đủ

Full-disk/database encryption chống mất media, nhưng người có quyền đọc database hoặc process
vẫn có thể thấy plaintext. Defense in depth:

- secret/key mã hóa ở rest bằng KEK tách biệt;
- TLS/mTLS cho distribution;
- authorization theo workload và purpose;
- plaintext chỉ tồn tại ngắn trong memory;
- backup, snapshot, replica và export có control tương đương;
- không lưu plaintext vào temp file, swap, core dump, support bundle;
- audit mọi read/use nhưng không log value.

## 18. Envelope encryption

Envelope encryption dùng data encryption key (DEK) để mã hóa dữ liệu và key encryption key
(KEK) để wrap DEK:

```text
plaintext --AEAD(DEK, nonce, AAD)--> ciphertext + tag
    DEK   --Wrap/Encrypt(KEK)------> wrapped_DEK

store: ciphertext, tag, nonce, wrapped_DEK, KEK URI/version, algorithm, schema version
```

DEK plaintext chỉ tồn tại đủ lâu để encrypt/decrypt rồi được loại khỏi memory tốt nhất có thể.
KEK nên ở KMS/HSM và không export plaintext. Wrapped DEK có thể lưu cạnh ciphertext vì nó không
giải mã được nếu thiếu quyền dùng KEK.

## 19. Vì sao không gửi toàn bộ dữ liệu lớn vào KMS?

KMS thường tối ưu cho key operation, có giới hạn payload, quota, latency và chi phí. Envelope
encryption cho phép:

- mã hóa dữ liệu lớn cục bộ bằng symmetric AEAD nhanh;
- giảm số request KMS;
- dùng một DEK per object/chunk/tenant theo threat model;
- rotate KEK bằng rewrap DEK thay vì đọc và mã hóa lại toàn bộ payload;
- phân quyền decrypt theo key/context.

Không cache plaintext DEK vô hạn để tiết kiệm chi phí; cache policy phải có TTL, size bound và
blast-radius analysis.

## 20. AEAD, nonce và associated data

Ưu tiên authenticated encryption (AEAD) như AES-GCM theo library/platform approved. Các quy tắc:

- nonce/IV phải đáp ứng yêu cầu của algorithm; với GCM, không được reuse cùng key;
- authentication tag phải được verify trước khi dùng plaintext;
- AAD không bí mật nhưng được bảo vệ integrity;
- đưa immutable context như tenant ID, object ID, schema/version vào AAD để chống ciphertext bị
  tráo sang object/tenant khác;
- context khi decrypt phải khớp chính xác khi encrypt.

Không đặt secret/PII vào encryption context nếu provider ghi context vào audit log.

## 21. Ciphertext cần schema tự mô tả

Không chỉ lưu một blob base64. Envelope nên có metadata đủ để migrate:

```json
{
  "format": 2,
  "algorithm": "AES-256-GCM",
  "kekUri": "kms://payments/prod/customer-data",
  "kekVersion": "7",
  "wrappedDek": "<base64-ciphertext>",
  "nonce": "<base64-nonce>",
  "ciphertext": "<base64-ciphertext-and-tag>",
  "aadProfile": "customer-record-v2"
}
```

Đây là format minh họa, không phải protocol tự chế. Dùng SDK/encryption library đã review và
authenticate cả metadata cần thiết. Không để `algorithm` từ input tùy ý điều khiển decrypt; dùng
allowlist và versioned parser.

## 22. Rotation là protocol nhiều bước

Rotation không downtime thường cần:

```text
1. create version N+1
2. grant/publish N+1
3. consumer nhận và health-check N+1
4. new writes/signs dùng N+1
5. reads/verifies vẫn chấp nhận N và N+1 trong cửa sổ giới hạn
6. đo usage N giảm về 0
7. revoke/deactivate N
8. sau retention và dependency check mới destroy N
```

Mỗi bước cần idempotent, observable và rollback boundary. “Update secret rồi restart tất cả” dễ
gây partial rollout và outage.

## 23. Dual-read/single-write và overlap window

Pattern an toàn:

- writer/signing service chỉ tạo dữ liệu bằng version mới;
- reader/verifier tạm hỗ trợ version mới và version cũ;
- ciphertext/token mang non-secret key ID hoặc version để lookup;
- overlap dài hơn max lifetime của artifact đang lưu hành cộng clock skew/rollout margin;
- không thử lần lượt mọi key không giới hạn vì tạo oracle và DoS.

Với database password, có thể dùng hai account/credential trong khoảng chuyển tiếp thay vì đổi
một password khiến connection pool cũ chết đồng loạt.

## 24. Rewrap, re-encrypt và rotate khác nhau

| Thao tác | Thay đổi gì? | Khi dùng |
|---|---|---|
| Rotate KEK | Version KEK mới cho operation mới | Giảm lifetime key và chuẩn bị migration |
| Rewrap DEK | Unwrap rồi wrap DEK dưới KEK mới qua boundary an toàn | Đổi KEK mà không mã hóa lại payload |
| Re-encrypt data | Tạo DEK/nonce/ciphertext mới | Đổi algorithm, data format hoặc DEK bị nghi lộ |
| Revoke | Chặn use ngay | Compromise hoặc không còn nhu cầu |
| Destroy | Xóa key material không phục hồi | Sau retention/dependency/legal check |

Nếu attacker đã sao chép ciphertext, wrapped DEK và có khả năng dùng KEK cũ, rewrap hiện tại
không xóa exposure lịch sử. Incident analysis phải xác định dữ liệu nào có thể đã bị đọc.

## 25. Revocation không phải deletion

Revocation/deactivation chặn hoặc giới hạn use và có thể rollback theo policy. Destruction có thể
làm dữ liệu mất vĩnh viễn. Quy trình xóa encryption key cần:

- disable/quarantine trước;
- inventory tất cả ciphertext, backup, replica và legal hold;
- canary decrypt/read test;
- approval nhiều bên và waiting period;
- evidence rằng dữ liệu đã rewrap/re-encrypt hoặc không còn cần;
- audit record không chứa key material.

Với token/API key bị lộ, ưu tiên revoke ngay; đừng chờ xóa khỏi Git hay chờ rotation định kỳ.

## 26. Dependency graph là nền tảng của rotation

```text
secret/key
├── service A / deployment / region 1
├── batch job B / scheduler
├── database connection pool
├── backup restore job
├── verifier/JWKS cache
└── DR region đang tắt
```

Inventory cần ánh xạ producer, consumer, verifier, backup và environment. DR job chạy mỗi quý rất
dễ bị bỏ quên: rotation có vẻ thành công hôm nay nhưng restore thất bại lúc xảy ra sự cố.

## 27. Cache và hành vi khi secret provider lỗi

Chọn fail-open hay fail-closed theo loại operation:

- không cho workload mới lấy secret nếu authorization/provider không xác minh được;
- workload đang chạy có thể dùng credential cached còn hạn trong bounded grace period nếu rủi ro
  cho phép;
- không kéo dài credential đã revoked chỉ vì provider outage;
- cache key theo secret ID + version + subject/context, có TTL và giới hạn memory;
- exponential backoff + jitter để tránh thundering herd;
- readiness khác liveness: đừng restart loop toàn cluster khi vault tạm chậm.

Phải định nghĩa RTO/RPO và emergency mode trước, không quyết định giữa incident.

## 28. Ba pattern phân phối cho application

| Pattern | Ưu điểm | Rủi ro/điểm cần xử lý |
|---|---|---|
| SDK trực tiếp | Identity và version rõ, app chủ động refresh | Coupling, retry/cache nằm trong app |
| Agent/sidecar | Chuẩn hóa auth, renewal, template | Sidecar compromise, file permission, lifecycle |
| CSI/mounted file | Ít code, dễ tích hợp legacy | Reload semantics, node/path exposure, stale file |

Không có pattern luôn tốt nhất. Chọn theo runtime, threat model, rotation latency và khả năng app
reload. Dù dùng external store, plaintext cuối cùng vẫn đến process cần sử dụng.

## 29. Environment variable, command line hay file?

Environment variable tiện nhưng có thể xuất hiện trong diagnostic, child process, crash dump và
thường không tự refresh. Command-line argument dễ lộ qua process listing/history. File mount có
thể đặt permission, update atomically và watch version, nhưng vẫn có rủi ro filesystem/node.

Khuyến nghị:

- truyền secret qua API hoặc file descriptor/memory khi platform hỗ trợ;
- nếu dùng file, permission tối thiểu, filesystem tạm, atomic replace và app reload an toàn;
- nếu buộc dùng env, không dump environment, không expose actuator/debug endpoint và restart có
  kiểm soát khi rotate;
- không biến secret thành Java `String` lâu hơn cần thiết nếu API cho phép `char[]`/`byte[]`;
- hiểu rằng GC/JIT/copy có thể khiến zeroization trong managed runtime không tuyệt đối.

## 30. Kubernetes Secrets: base64 không phải encryption

Kubernetes Secret mặc định biểu diễn dữ liệu bằng base64, không cung cấp confidentiality. Cần:

- cấu hình encryption at rest cho dữ liệu API/etcd và bảo vệ key provider;
- RBAC tối thiểu; quyền `list`/`watch` cũng có thể lộ nội dung secret;
- chỉ mount vào container cần dùng, không chia cho mọi container trong Pod;
- hạn chế quyền tạo Pod/exec/debug vì các quyền này có thể gián tiếp đọc secret;
- tránh commit Secret manifest; sealed/external pattern vẫn cần quản lý decrypt key;
- bảo vệ node, swap, logs và application sau khi secret đã được mount;
- test việc volume/CSI cập nhật và ứng dụng reload, không giả định rotation tự hoàn tất.

## 31. CI/CD: dùng federation thay long-lived cloud key

Workflow identity qua OIDC:

```text
CI job → signed OIDC token (repo/workflow/ref/environment)
       → cloud STS validates issuer + audience + subject/claims
       → short-lived deployment credential
```

Trust policy phải khóa immutable repository/organization identity khi platform hỗ trợ, workflow,
environment, branch/tag và audience; không chỉ kiểm tra issuer. Giới hạn `id-token` permission,
pin dependency/action đáng tin, bảo vệ production environment và không truyền token sang step
không cần. Fork/untrusted pull request không được nhận production credential.

## 32. Secret scanning là detection, không phải vault

Scan ở nhiều điểm:

- pre-commit/IDE để phản hồi sớm;
- push protection để chặn trước khi vào remote;
- pull request và default branch;
- toàn bộ Git history và mọi branch/tag;
- issue, wiki, build log, artifact, container image, package và object storage;
- custom pattern cho credential nội bộ, kèm entropy/context để giảm false positive.

Không “validate” credential lạ bằng cách gọi production API từ laptop. Triage qua provider-safe
validity check hoặc owner/runbook được phê duyệt.

## 33. Secret đã vào Git: revoke trước, dọn history sau

Thứ tự phản ứng:

1. Xác định provider, owner, scope, môi trường và thời điểm lộ.
2. Coi secret có khả năng đã compromise; revoke/rotate ngay bằng kênh an toàn.
3. Cập nhật consumer và xác nhận credential mới hoạt động.
4. Tìm usage bất thường trong audit/provider log từ trước thời điểm lộ.
5. Tìm các bản sao: fork, clone, artifact, cache, chat, ticket, log.
6. Sau khi credential vô hiệu mới cân nhắc rewrite history để giảm accidental disclosure.
7. Ghi root cause và thêm prevention/detection.

Xóa dòng rồi commit tiếp không vô hiệu secret trong commit cũ, clone hay cache.

## 34. Log, trace và metric không được chứa secret

Redaction phải thực hiện gần nguồn, không chỉ ở dashboard:

- allowlist field được log thay vì blacklist tên `password`;
- không log Authorization/Cookie, connection string, request body nhạy cảm;
- log secret ID/version, principal, operation, outcome và correlation ID;
- tracing baggage/header có thể lan qua nhiều service, cần filter;
- metric label không chứa secret/token/user-controlled high cardinality;
- exception của SDK/HTTP client phải sanitize;
- test redaction bằng canary secret giả và scan log pipeline.

Hash secret để log cũng có thể tạo identifier ổn định hoặc oracle; thường chỉ log key ID/fingerprint
đã thiết kế riêng.

## 35. Database credentials

Tốt nhất cấp account riêng cho mỗi service/instance hoặc dynamic user có TTL:

- role/template chỉ có schema/table/action cần thiết;
- không dùng database owner cho application;
- connection pool biết refresh credential và drain connection cũ;
- revoke tại database thực, không chỉ xóa value khỏi vault;
- audit map username/lease về workload;
- root credential dùng để provision phải được rotate, hạn chế và monitor;
- restore/replica/migration tool cũng nằm trong dependency graph.

Rotation cần test transaction đang chạy, failover và pool behavior; TTL quá ngắn so với transaction
có thể gây lỗi giữa chừng.

## 36. API key và webhook secret

API key nên có:

- public prefix/key ID để lookup và secret random riêng;
- hash hoặc protected representation phía verifier khi protocol cho phép;
- scope, tenant, environment, owner, expiry và last-used;
- nhiều active key có giới hạn để rotate không downtime;
- rate limit/anomaly detection và revoke tức thời;
- không đặt trong URL/query vì dễ vào log/referrer;
- webhook signature gồm timestamp/nonce và chống replay, không chỉ `hash(body)`.

IP allowlist là lớp bổ sung, không thay authentication và không phù hợp mọi topology.

## 37. Signing key rotation khác encryption key rotation

Với token/artifact signing:

```text
publish public key N+1
→ verifier refresh thành công
→ signer chuyển sang private key N+1
→ vẫn verify N đến hết max artifact lifetime
→ remove/revoke N
```

Private key nên non-exportable nếu có thể; signer được quyền `Sign` nhưng không có quyền quản trị
key. `kid` chỉ là hint lookup, không phải authorization. Verifier phải allowlist issuer, algorithm,
key use và cache JWKS có giới hạn. Nếu signing key compromise, mọi artifact trong cửa sổ liên quan
có thể cần revoke/reissue; chỉ publish key mới là chưa đủ.

## 38. Backup, recovery và escrow

Encryption key mất có thể đồng nghĩa mất dữ liệu, nên:

- backup key material/metadata theo khả năng provider và policy;
- mã hóa backup bằng key có strength/control tương đương hoặc mạnh hơn;
- tách location, operator và credential khỏi production;
- test restore định kỳ trong môi trường cô lập;
- lưu inventory/version/context cần để decrypt dữ liệu cũ;
- kiểm soát legal retention và destruction.

Không escrow signing/authentication private key theo thói quen: bản sao tăng khả năng giả mạo.
Quyết định escrow phụ thuộc purpose; encryption recovery và non-repudiation cần chính sách khác.

## 39. Multi-region và disaster recovery

Trước khi chọn replicate key hay dùng key riêng mỗi region, trả lời:

- dữ liệu có cần move/decrypt cross-region không?
- region isolation hay portability quan trọng hơn?
- replication do provider bảo vệ và audit thế nào?
- khi primary KMS/vault unavailable, RTO là bao nhiêu?
- DR site nhận policy, trust bundle và secret version mới bằng cách nào?
- revoke ở một nơi có đồng bộ đủ nhanh không?

Drill phải khởi động workload ở DR bằng phiên bản key/secret hiện hành. Backup “thành công” nhưng
không decrypt được không phải backup hữu dụng.

## 40. Tenant và environment isolation

Không dùng một global secret/key cho mọi tenant nếu blast radius không chấp nhận được. Có thể tách:

- account/project/subscription và KMS policy theo environment;
- KEK per service, data class, region hoặc tenant tier;
- DEK per object/tenant;
- secret namespace/path và identity policy;
- audit partition và quota.

Tách quá nhỏ làm tăng cost/quota/operation. Chọn boundary dựa trên threat model và yêu cầu crypto-
shredding. AAD/encryption context phải bind tenant để chống ciphertext swapping.

## 41. Dual control, quorum và break-glass

Thao tác high-impact như export/import root key, sửa recovery policy, disable audit hoặc destroy key
nên cần nhiều người/role độc lập. Break-glass:

- credential mạnh, offline hoặc được bảo vệ bằng hardware;
- không phụ thuộc đúng hệ thống đang bị outage;
- chỉ cấp quyền/timing cần thiết;
- mọi use alert ngay qua kênh độc lập;
- post-use rotate/reseal và review;
- drill bằng quy trình không làm lộ giá trị thật.

Quorum không thay least privilege; năm người cùng có quyền thường trực vẫn tạo blast radius lớn.

## 42. Audit và detection

Audit event nên có:

```text
timestamp, principal/workload, auth method
secret/key ID + version (không có value)
operation: read/generate/encrypt/decrypt/sign/rotate/revoke/policy-change
resource/context, source, region
decision/outcome, request/correlation ID
```

Alert cho:

- read/decrypt/sign spike hoặc region/source mới;
- admin dùng data-plane operation;
- policy/key state/audit sink thay đổi;
- secret version cũ vẫn được dùng sau deadline;
- repeated denied access hoặc enumeration;
- break-glass, export/import, backup restore và scheduled deletion;
- decrypt sai context/tag tăng bất thường.

Log cần immutable/centralized và có retention phù hợp incident window.

## 43. Runbook: static secret bị lộ

```text
contain → replace → revoke → hunt → eradicate copies → learn
```

1. Xác minh loại secret mà không phát lại plaintext trong ticket/chat.
2. Đánh giá scope, privilege, exposure time, public/private location và last use.
3. Nếu có thể, tạo credential mới và chuyển consumer khẩn cấp.
4. Revoke credential cũ tại provider; không chỉ xóa khỏi secret store.
5. Kiểm tra audit từ trước thời điểm leak, gồm downstream action.
6. Rotate secret mà credential có thể đọc hoặc dùng để pivot.
7. Xử lý Git/log/artifact/cache và thông báo stakeholder theo policy.
8. Thêm regression control: federation, push protection, least privilege hoặc TTL.

## 44. Runbook: encryption/KEK bị nghi compromise

1. Freeze destructive admin changes nhưng giữ evidence/audit.
2. Xác định key version, operation, ciphertext set, consumer và thời gian attacker có access.
3. Chặn principal/path compromise; disable key nếu impact availability chấp nhận được.
4. Tạo key sạch qua trusted control plane.
5. Rewrap hoặc re-encrypt theo loại exposure; ưu tiên dữ liệu nhạy cảm/đang hoạt động.
6. Update policy/consumer, verify data, rồi retire key cũ.
7. Giả định ciphertext đã copy có thể vẫn bị đọc nếu attacker từng có đủ key capability.
8. Review backup, replica, logs và plaintext exposure; đáp ứng notification/legal requirement.

Không destroy key cũ trước khi preservation và migration được xác nhận.

## 45. Runbook: secret platform/KMS outage

- Phân loại control-plane outage hay data-plane operation outage.
- Kiểm tra credential cached còn hợp lệ và bounded grace policy.
- Giảm restart/autoscale không cần thiết để tránh workload mới đồng loạt bootstrap.
- Dùng failover endpoint/region đã drill; không copy secret qua chat để “chữa cháy”.
- Break-glass chỉ theo runbook, có approval và audit độc lập.
- Bảo vệ consistency: tránh hai region cùng rotate thành version xung đột.
- Sau phục hồi, reconcile lease/version, revoke emergency credential và review log.

Availability là một phần của key management; thiết kế quá tập trung nhưng không có DR có thể biến
security control thành single point of failure.

## 46. Migration từ hardcoded secret sang managed secret

Lộ trình giảm rủi ro:

1. Inventory và owner; scan history/artifact để biết secret đã lan đâu.
2. Tạo identity cho workload và policy read đúng path/version.
3. Tạo credential mới trong provider; không nhập lại secret đã nằm trong Git.
4. Tích hợp SDK/agent/file mount và redaction.
5. Deploy canary, xác nhận read/use/audit/refresh.
6. Rollout; đo usage credential cũ về 0.
7. Revoke credential cũ và tìm unauthorized use.
8. Xóa reference khỏi code/config; rewrite history chỉ sau revoke nếu cần.
9. Thêm push protection và policy ngăn tái diễn.

## 47. Java/Spring: abstraction tránh phát tán plaintext

Giữ contract nhỏ, version-aware và không cho mọi component tùy ý đọc mọi path:

```java
public interface SecretProvider {
    SecretLease acquire(SecretRef ref);
}

public record SecretRef(String logicalName, String environment) {}

public interface SecretLease extends AutoCloseable {
    char[] value();
    String version();
    java.time.Instant expiresAt();
    @Override void close(); // best-effort zeroization/release
}
```

Các nguyên tắc triển khai:

- mapping logical name → provider URI nằm trong trusted config, không nhận path tùy ý từ request;
- authenticate bằng workload identity, không hardcode bootstrap token;
- timeout, retry có jitter, circuit breaker và bounded cache;
- refresh trước expiry và swap dependency atomically;
- metric/log chỉ chứa logical name/version/outcome;
- `close()` giảm lifetime plaintext nhưng không hứa zeroization tuyệt đối trên JVM;
- integration test dùng secret giả và fake provider, không dùng production secret.

## 48. Kiểm thử rotation và failure

Test tối thiểu:

- create → activate → use → rotate → revoke → destroy state transition;
- N/N+1 overlap, partial deployment và rollback;
- old credential thật sự bị provider từ chối;
- connection pool/session/cache không giữ credential quá hạn;
- KMS/vault timeout, throttling, DNS/network partition và regional failover;
- wrong tenant/AAD/tag/key version bị từ chối;
- backup restore và decrypt dữ liệu từ nhiều version;
- unknown version không làm fallback sang insecure default;
- audit/redaction không chứa canary secret;
- concurrent rotation idempotent, không tạo split-brain.

Chaos drill phải dùng credential/key test có blast radius giới hạn.

## 49. SLO và metric có ý nghĩa

Theo dõi:

- success/error/latency của issue/read/renew/decrypt/sign theo operation;
- secret sắp hết hạn nhưng chưa có version mới;
- consumer còn dùng old version;
- rotation duration và failure stage;
- lease renewal margin, expired credential failures;
- key/secret không owner, không expiry, không last-used;
- static/shared credential count và tuổi;
- secret scanning alert age đến revoke;
- provider availability, quota/throttling và cache hit có giới hạn;
- restore drill age.

Không gắn raw secret, token, tenant PII hoặc ciphertext lớn vào metric label.

## 50. Production checklist, anti-pattern và nguồn chính thức

### Checklist

- [ ] Có inventory: owner, purpose, consumer, scope, version, expiry, last-used, revoke/runbook.
- [ ] Workload identity/dynamic credential được ưu tiên hơn static secret.
- [ ] Secret store, KMS, HSM và encryption-at-rest được dùng đúng vai trò.
- [ ] Key tách theo purpose; KEK/DEK và envelope schema/version rõ ràng.
- [ ] Plaintext không ở source, image, URL, command line, log, trace, artifact hoặc backup hở.
- [ ] Rotation N/N+1 đã test với cache, pool, batch, DR và rollback.
- [ ] Revoke xảy ra tại provider; destroy có dependency/legal/recovery approval.
- [ ] Kubernetes etcd encryption và least-privilege RBAC được cấu hình/test.
- [ ] CI/CD dùng OIDC federation nếu có thể; trust policy khóa claim cụ thể.
- [ ] Push protection + full-history scanning + remediation SLA hoạt động.
- [ ] Audit không chứa value; alert admin/data-plane anomaly và old-version usage.
- [ ] Runbook leak, key compromise và provider outage đã drill.

### Anti-pattern cần nhớ

| Anti-pattern | Vì sao sai | Cách sửa |
|---|---|---|
| Base64 secret rồi gọi là encrypted | Ai đọc được đều decode được | Secret store + encryption + IAM |
| Một global secret cho mọi service | Không attribution, blast radius lớn | Identity/credential riêng, scope hẹp |
| Rotate bằng overwrite một lần | Partial rollout gây outage | Version N/N+1 và usage telemetry |
| Xóa secret khỏi Git là đủ | Commit/clone/cache vẫn còn; key vẫn valid | Revoke trước, dọn sau |
| Encrypt data và để key cạnh ciphertext | Cùng compromise path | Envelope encryption, KEK ở KMS/HSM |
| Auto-rotation nhưng app không reload | Provider mới, runtime vẫn dùng cũ | End-to-end rotation test |
| Admin vault đọc được mọi secret | Control-plane compromise thành data breach | Separation, JIT, audit, dual control |
| Disable KMS key ngay khi chưa inventory | Có thể gây mất dữ liệu/outage | Contain, preserve, migrate có kiểm soát |

### Nguồn chính thức

- [NIST SP 800-57 Part 1 Revision 5 – Recommendation for Key Management](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)
- [NIST FIPS 140-3 – Security Requirements for Cryptographic Modules](https://csrc.nist.gov/pubs/fips/140-3/final)
- [NIST SP 800-38F – Methods for Key Wrapping](https://csrc.nist.gov/pubs/sp/800/38/f/final)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [OWASP Key Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Key_Management_Cheat_Sheet.html)
- [AWS KMS Cryptography Essentials – Envelope Encryption](https://docs.aws.amazon.com/kms/latest/developerguide/kms-cryptography.html)
- [Google Cloud KMS – Envelope Encryption](https://cloud.google.com/kms/docs/envelope-encryption)
- [HashiCorp Vault – Lease, Renew and Revoke](https://developer.hashicorp.com/vault/docs/concepts/lease)
- [Kubernetes – Good Practices for Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [GitHub – OpenID Connect for Actions](https://docs.github.com/en/actions/concepts/security/openid-connect)
- [GitHub – Remediating a Leaked Secret](https://docs.github.com/en/code-security/tutorials/remediate-leaked-secrets/remediating-a-leaked-secret)

### Học tiếp

1. [Threat Modeling & Secure Architecture](../architecture/threat_modeling_secure_architecture.md) – asset, trust boundary, abuse case, STRIDE và security requirement.
2. [Data Security & Privacy Engineering](../data/data_security_privacy_engineering.md) – classification, retention, tokenization, masking và data lineage.

---

*Cập nhật lần cuối: 2026-08-02.*
