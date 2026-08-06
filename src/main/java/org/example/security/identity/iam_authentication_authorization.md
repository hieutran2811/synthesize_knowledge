# Identity & Access Management – Authentication, Session và Authorization

> Mục tiêu: thiết kế identity end-to-end cho người dùng, quản trị viên và workload.
> Chương này đi từ vòng đời tài khoản, password/passkey/MFA đến session, OAuth/OIDC,
> token, RBAC–ABAC–ReBAC, machine identity, provisioning, access review và incident runbook.

---

## 1. Identity là control plane của gần như mọi hệ thống

```text
Nguồn danh tính / HR / customer account
              │
              ▼
Identity proofing + account lifecycle
              │
              ▼
Authenticator: password / passkey / MFA / certificate
              │
              ▼
Session hoặc token: duy trì trạng thái đã xác thực
              │
              ▼
Authorization: subject nào được action gì trên resource nào?
              │
              ▼
Audit + detection + review + revoke + recovery
```

Một hệ thống có login “mạnh” vẫn không an toàn nếu nhân viên nghỉ việc còn quyền, API
không kiểm tra ownership hoặc refresh token không thể thu hồi. Ngược lại, policy RBAC đẹp
không giúp gì nếu password reset cho phép chiếm tài khoản.

**Mental model:** IAM không chỉ là màn hình đăng nhập. Nó là vòng đời của danh tính,
credential, session, quyền và bằng chứng kiểm toán.

---

## 2. AuthN, AuthZ, identity proofing và accounting khác nhau

| Khái niệm | Câu hỏi | Ví dụ |
|---|---|---|
| Identification | Bạn tự nhận là ai? | username, email, client ID |
| Identity proofing | Danh tính số có gắn đúng người/tổ chức thật không? | KYC, HR verification |
| Authentication – AuthN | Bạn chứng minh quyền kiểm soát danh tính thế nào? | passkey, password + MFA |
| Authorization – AuthZ | Danh tính này được làm gì với resource cụ thể? | sửa invoice của tenant A |
| Accounting/Audit | Ai đã làm gì, khi nào và qua policy nào? | grant change, data export |

Authentication thành công không ngầm cho phép truy cập mọi object. Authorization phải chạy
trên từng request/action nhạy cảm và fail closed khi thiếu thông tin.

Identity proofing cũng không phải authentication: một tài khoản đã KYC vẫn có thể bị đánh
cắp credential; một nickname không KYC vẫn có thể dùng authenticator mạnh trong dịch vụ
không cần danh tính đời thực.

---

## 3. Ba loại subject cần lifecycle khác nhau

```text
Human workforce    nhân viên, contractor, admin
Human customer     người dùng bên ngoài, tenant member
Non-human identity service, job, device, CI/CD, integration
```

Sai lầm phổ biến là dùng cùng một mô hình cho cả ba:

- workforce nên được provision từ HR/IdP, group và ngày kết thúc hợp đồng;
- customer cần signup, verification, account recovery, abuse protection và tenant membership;
- workload cần attestation và credential ngắn hạn, không cần password “để người nhớ”;
- shared admin account làm mất attribution;
- một API key dùng chung cho nhiều service làm blast radius và rotation không kiểm soát được.

Mỗi subject phải có stable internal ID, owner, trạng thái, authentication method, quyền,
expiry và cách thu hồi.

---

## 4. Threat model cho identity plane

Ít nhất phải xét:

1. Credential stuffing từ password đã lộ ở dịch vụ khác.
2. Phishing real-time đánh cắp password + OTP.
3. Session cookie/access token/refresh token bị lấy qua XSS, malware hoặc log.
4. OAuth redirect, code injection, token substitution và mix-up.
5. Account recovery hoặc đổi email/MFA bị lạm dụng.
6. BOLA/IDOR: user hợp lệ truy cập object của người khác.
7. Admin bị chiếm quyền hoặc tự cấp quyền vượt quá phê duyệt.
8. Service account key nằm lâu trong Git/image/CI log.
9. Leaver/mover còn group, local account hoặc active session cũ.
10. IdP, MFA provider, email/SMS hoặc policy engine bị lỗi/compromise.

Từ threat model, xác định assurance theo hành động. Xem catalog không nhất thiết cần cùng
mức xác thực như đổi payout account, cấp admin hoặc xuất toàn bộ dữ liệu.

---

## 5. Identity lifecycle: joiner, mover, leaver

```text
Joiner                   Mover                    Leaver
verify source            recompute quyền          disable sign-in
create stable ID         remove quyền cũ          revoke session/token
assign baseline          grant quyền mới          disable downstream account
enroll authenticator     review SoD               rotate shared secret
set owner/expiry         record approval           preserve audit/evidence
```

Quyền nên được **tính lại** từ role/attribute hiện tại, không chỉ cộng thêm. Người chuyển
từ Finance sang Engineering cần mất quyền Finance trước hoặc đồng thời nhận quyền mới.

Offboarding không kết thúc ở `disabled=true` trong IdP:

- active application session có bị revoke không?
- refresh token, API key, SSH key, certificate còn sống bao lâu?
- SaaS/local account không nối SCIM có bị bỏ sót không?
- dữ liệu, dashboard, scheduled job và ownership được chuyển cho ai?
- shared secret người đó biết có cần rotate không?

Đặt SLA deprovision theo rủi ro và đo thời gian từ source event tới mọi enforcement point.

---

## 6. Stable internal ID, không dùng email làm primary identity

Email, username, display name và department có thể thay đổi hoặc tái sử dụng. Dùng một
opaque immutable subject ID làm khóa nội bộ:

```text
subject_id = 7fbc...               ổn định trong hệ thống
issuer + subject = (iss, sub)      ổn định trong federation contract
email = alice@example.com          attribute có thể đổi
```

Với OIDC, `sub` chỉ có nghĩa trong namespace của `iss`; khóa đúng thường là cặp `(iss, sub)`.
Không tự động link hai tài khoản chỉ vì email trùng, đặc biệt giữa hai issuer. Cần flow link
account có re-authentication và thông báo.

Tách displayable identifier khỏi authorization key giúp đổi email/rename tenant mà không
đổi ownership hoặc tạo account takeover do recycled address.

---

## 7. Factor phải độc lập

Ba nhóm chính:

- **Something you know:** password, PIN.
- **Something you have:** security key, authenticator/device giữ private key.
- **Something you are:** biometric, thường dùng cục bộ để mở authenticator.

Password + security question vẫn là hai “knowledge”, không thành MFA. Password + PIN gửi
tới cùng server cũng không tạo hai factor độc lập.

Biometric thường không được gửi lên application như một secret có thể reset. Điện thoại/
security key xác minh biometric hoặc PIN cục bộ, rồi dùng private key ký challenge. Server
nhận cryptographic proof và user-verification flag.

Assurance phụ thuộc toàn ceremony: enrollment, recovery, device binding, key protection và
verifier validation, không chỉ tên “MFA”.

---

## 8. NIST assurance: IAL, AAL và FAL

NIST SP 800-63 Revision 4 tách:

- **IAL:** mức đảm bảo identity proofing;
- **AAL:** mức đảm bảo authentication;
- **FAL:** mức đảm bảo federation assertion.

Đừng gắn “AAL2 compliant” chỉ vì có OTP. Cần đánh giá toàn bộ authenticator lifecycle,
protected channel, replay resistance, reauthentication và verifier behavior theo profile.

Phishing resistance đòi hỏi cryptographic authentication gắn với verifier/channel; OTP
được người dùng nhập thủ công không được xem là phishing-resistant vì attacker có thể relay
theo thời gian thực.

Chọn assurance theo impact và regulatory context; không bắt mọi hành động friction cao
như nhau, nhưng admin/high-value transaction nên ưu tiên phishing-resistant authentication.

---

## 9. Password policy hiện đại

Theo NIST SP 800-63B-4:

- single-factor password tối thiểu 15 ký tự;
- password chỉ dùng trong multi-factor có thể ngắn hơn nhưng tối thiểu 8 ký tự;
- cho phép passphrase dài, Unicode và khoảng trắng;
- không ép quy tắc “1 hoa + 1 số + 1 ký tự đặc biệt”;
- không bắt đổi định kỳ tùy tiện; đổi khi có bằng chứng compromise hoặc thay authenticator;
- chặn password phổ biến, expected và đã bị lộ;
- không silently truncate;
- cho phép password manager và paste;
- rate-limit online guessing.

Password dài vẫn bị phishing/keylogger. Password policy là fallback/layer, không thay
passkey/MFA và không nên làm user tạo pattern dễ đoán như `Summer2026!`.

---

## 10. Password phải hash, không encrypt để “giải mã khi cần”

Baseline OWASP hiện hành:

```text
Argon2id: ít nhất m=19 MiB, t=2, p=1
```

Đây là minimum, không phải optimum cho mọi máy. Benchmark login peak, memory concurrency
và DoS budget rồi chọn cost cao nhất vẫn đáp ứng SLO. Lưu algorithm + version + parameter +
salt trong encoded hash để nâng cấp khi user login.

```text
password ──Argon2id(password, unique salt, cost)──► verifier
```

- salt riêng mỗi password và có thể lưu cùng hash;
- pepper là secret dùng chung, phải ở vault/HSM ngoài password DB;
- pepper compromise thường buộc reset/rehash vì không thể đổi offline nếu không biết password;
- bcrypt chỉ là fallback legacy, có giới hạn input 72 byte và work factor phù hợp;
- so sánh qua API thư viện, không tự viết crypto.

Không log password, verifier, reset token hoặc pepper.

---

## 11. Login defense chống brute force, stuffing và spraying

Kết hợp nhiều tín hiệu:

- rate limit theo account + IP/network + device + ASN/risk;
- exponential backoff hoặc progressive delay;
- breached-password blocklist;
- MFA/passkey;
- bot detection/CAPTCHA khi có risk, không là control duy nhất;
- alert distributed spraying và impossible travel có baseline;
- generic response để giảm user enumeration;
- credential-stuffing detection theo password reuse campaign.

Hard lockout dài theo account cho phép attacker DoS nạn nhân. Ưu tiên throttling/risk-based
challenge và recovery an toàn. Nếu khóa, phải có threshold/window/unlock contract rõ.

Giữ thời gian phản hồi tương tự cho “user không tồn tại” và “password sai”; response body,
status code và password-reset flow cũng không được làm lộ khác biệt dễ tự động hóa.

---

## 12. Account recovery thường là authenticator yếu nhất

Password reset baseline:

1. Trả response generic dù account tồn tại hay không.
2. Tạo token CSPRNG đủ mạnh, single-use, short-lived và gắn đúng purpose/account.
3. Chỉ lưu hash của token nếu database bị đọc.
4. Link dùng HTTPS, exact trusted host; không lấy host tùy ý từ request header.
5. Không tự login user chỉ vì reset link đã dùng, trừ khi threat model chấp nhận.
6. Sau reset, hỏi revoke mọi session/refresh token hoặc áp policy bắt buộc theo rủi ro.
7. Gửi notification out-of-band nhưng không chứa password mới.
8. Rate limit cả yêu cầu và consume token.

Security question là knowledge dễ đoán/OSINT và không nên là recovery factor mạnh.

Đổi email, thêm passkey, tắt MFA hoặc tạo recovery code mới cũng là recovery-equivalent
operation: cần recent re-authentication và thông báo.

---

## 13. MFA strength không đồng đều

| Method | Ưu điểm | Hạn chế chính |
|---|---|---|
| SMS/voice OTP | triển khai rộng | SIM swap, SS7, relay/phishing |
| Email OTP | dễ dùng | phụ thuộc security của mailbox |
| TOTP | offline, phổ biến | vẫn phishable/replay trong window |
| Push approve | UX tốt | push fatigue, number matching vẫn cần vigilance |
| FIDO2/WebAuthn/passkey | verifier-bound, phishing-resistant | enrollment/recovery/device ecosystem |
| Client certificate/smart card | mạnh trong enterprise | issuance, UX, revocation |

Nếu chỉ có SMS tốt hơn password-only trong nhiều threat model, nhưng admin/high-value flow
nên có phishing-resistant option và lộ trình bắt buộc.

MFA change/recovery phải mạnh ít nhất tương đương enrollment. Cho user đăng ký nhiều
authenticator, recovery code one-time, và cảnh báo khi factor được thêm/xóa.

---

## 14. Passkey/WebAuthn chống phishing bằng verifier binding

```text
Relying Party                    Authenticator
  challenge + RP ID + origin ───────►
                                 verify user locally
                                 sign challenge + context
              ◄──────── assertion + credential ID
  verify challenge, origin, RP ID hash, signature, flags
```

Private key không rời authenticator; server lưu public key. Credential scoped theo RP ID,
nên trang phishing ở domain khác không lấy được assertion hợp lệ cho RP thật.

Passkey có thể sync giữa thiết bị qua platform ecosystem hoặc nằm trên roaming security key.
“Biometric login” trong flow này không có nghĩa application nhận ảnh vân tay; biometric chỉ
mở khóa private key cục bộ.

Phishing-resistant không nghĩa malware trên endpoint, session theft sau login hoặc account
recovery yếu đều biến mất.

---

## 15. WebAuthn registration ceremony

Server phải:

1. Xác thực hoặc proofing user theo enrollment policy.
2. Sinh challenge random, single-use, short-lived và gắn session/user/purpose.
3. Chọn đúng RP ID, allowed origin, user verification và authenticator policy.
4. Client tạo credential, trả attestation/credential public key.
5. Server kiểm tra challenge, origin, RP ID hash, flags và attestation policy.
6. Lưu credential ID, public key, user handle, transports/metadata cần thiết.
7. Audit enrollment và thông báo user.

Không yêu cầu attestation quá mức nếu không thật sự cần quản lý loại hardware; attestation
có privacy, supply-chain và trust-store cost. Consumer passkey thường ưu tiên usability,
enterprise có thể enforce managed authenticator theo risk.

Challenge không được tái sử dụng hoặc chỉ lưu ở client có thể sửa.

---

## 16. WebAuthn authentication và recovery

Authentication verification gồm:

- challenge đúng, chưa dùng, chưa hết hạn;
- origin và RP ID hash chính xác;
- credential thuộc user/RP mong đợi;
- signature đúng public key;
- user presence/user verification flag đúng policy;
- sign counter/anomaly được xử lý theo authenticator semantics, không hard-code mù.

Cho phép nhiều passkey để tránh một thiết bị thành single point of failure. Recovery có thể
dùng một passkey khác, recovery code hoặc flow hỗ trợ đã proofing; không hạ xuống email-only
âm thầm cho admin.

Khi xóa passkey cuối, thêm device mới hoặc đổi recovery channel, yêu cầu recent strong
authentication và gửi notification. User nên thấy danh sách credential/device, thời điểm
dùng cuối và có thể revoke.

---

## 17. Opaque server session và self-contained token

| | Opaque session ID | Self-contained JWT access token |
|---|---|---|
| State | server/session store | claims nằm trong token |
| Revoke | xóa/disable server-side nhanh | khó cho tới expiry nếu không introspection/denylist |
| Size | nhỏ | lớn hơn, gửi mỗi request |
| Claim freshness | đọc state hiện tại | stale tới khi token hết hạn |
| Hợp với | browser/BFF, monolith | distributed API/federation có contract |

JWT không “an toàn hơn session” chỉ vì có chữ ký. Chữ ký bảo vệ integrity/provenance,
không mã hóa payload và không ngăn token bị đánh cắp/replay.

Browser ứng dụng cùng origin thường hưởng lợi từ opaque HttpOnly session cookie. API phân
tán có thể cần access token ngắn hạn. Chọn theo revoke/freshness/deployment, không theo trend.

---

## 18. Cookie session baseline

```http
Set-Cookie: __Host-session=<opaque-random>;
  Path=/; Secure; HttpOnly; SameSite=Lax
```

- `Secure`: chỉ gửi qua HTTPS.
- `HttpOnly`: JavaScript không đọc cookie, giảm theft qua XSS nhưng XSS vẫn gửi request được.
- `SameSite`: giảm một số CSRF; chọn Lax/Strict/None theo flow và test browser.
- `__Host-`: yêu cầu Secure, Path `/` và không có Domain, giảm cookie tossing/scope rộng.
- không đặt session ID trong URL, local log, analytics hoặc Referer.
- Domain/Path hẹp; không chia cookie cho subdomain không cùng trust.

`SameSite=None` cần `Secure` và mở cross-site usage, nên phải có CSRF defense phù hợp.

Session ID nên random CSPRNG, meaningless; OWASP yêu cầu ít nhất 64 bit entropy và khuyên
custom ID ít nhất 128 bit. Dùng session implementation framework trưởng thành thay vì tự chế.

---

## 19. Session lifecycle và timeout

Mọi session cần:

- idle timeout enforced server-side;
- absolute timeout dù vẫn hoạt động;
- renewal/rotation policy;
- revocation khi logout, reset, compromise hoặc offboarding;
- danh sách active device/session cho user nếu phù hợp;
- recent-auth timestamp và authentication method/reference.

Timeout là risk decision: banking admin khác shopping cart. Client countdown chỉ là UX;
server mới là authority hết hạn.

Logout phải invalidate server-side, không chỉ xóa cookie. “Logout all devices” cần revoke
session family/refresh grant và tăng security epoch/version nếu dùng distributed validation.

Không log raw session ID; có thể log keyed/salted hash để correlate mà giảm khả năng replay.

---

## 20. Chống session fixation và privilege transition

Rotate session ID khi:

- anonymous → authenticated;
- MFA/step-up hoàn tất;
- role/privilege tăng hoặc impersonation bắt đầu/kết thúc;
- password/email/authenticator thay đổi;
- recovery hoàn tất.

ID cũ phải bị hủy sau transition. Không chấp nhận session ID chưa từng được server phát.

```text
anonymous SID A ──login──► authenticated SID B
SID A invalid ngay; data cart cần migrate server-side có kiểm soát
```

Nếu chỉ gắn user vào SID A do client đã chọn, attacker có thể “fix” SID trước rồi dùng lại
sau khi nạn nhân login.

---

## 21. Cookie chống token theft nhưng cần CSRF defense

Hai lựa chọn có trade-off:

```text
Token trong JavaScript-accessible storage
  + dễ gắn Authorization header
  - XSS có thể đọc và exfiltrate token

HttpOnly cookie
  + script không đọc secret
  - browser tự gửi cookie, cần CSRF protection
```

CSRF defense gồm SameSite, anti-CSRF token gắn session, Origin/Referer validation và custom
header cho API phù hợp. Không dùng GET cho state change.

XSS có thể thao tác dưới session hiện tại dù không đọc cookie, vì vậy CSP/output encoding/
dependency security vẫn cần. Không có storage trick nào biến XSS thành vô hại.

---

## 22. OAuth 2.0 và OpenID Connect giải quyết hai bài toán

- **OAuth 2.0:** ủy quyền client truy cập resource thay resource owner.
- **OpenID Connect:** identity layer trên OAuth, cung cấp authentication và ID Token.

Các vai:

```text
Resource Owner: user
Client: ứng dụng muốn quyền
Authorization Server / OIDC Provider: cấp code/token
Resource Server: API nhận access token
Relying Party: client dùng OIDC để đăng nhập
```

Access token dành cho resource server và audience cụ thể. ID Token nói với OIDC client về
authentication event; không gửi ID Token tùy tiện tới mọi API thay access token.

OAuth “login” tự chế chỉ dựa trên access token/email endpoint dễ sai issuer, audience,
nonce và account-linking. Dùng OIDC library/provider đã kiểm chứng.

---

## 23. Authorization Code + PKCE là baseline redirect flow

```text
Client tạo code_verifier + code_challenge=S256(verifier)
Browser → Authorization Endpoint: code_challenge, state, nonce...
User authenticate/consent
Browser ← exact registered redirect URI + authorization code
Client → Token Endpoint: code + code_verifier
Server chỉ đổi code nếu verifier khớp challenge
```

RFC 9700 yêu cầu public client dùng PKCE và khuyến nghị cả confidential client. Chỉ dùng
`S256`; challenge/verifier phải transaction-specific.

- redirect URI exact match, trừ ngoại lệ localhost port cho native app;
- không có open redirector;
- authorization code single-use, short-lived, gắn client + redirect URI;
- `state` gắn browser transaction chống CSRF; OIDC `nonce` gắn ID Token/auth event;
- xác minh issuer để chống mix-up khi làm việc với nhiều authorization server;
- client secret trong SPA/mobile không phải secret vì có thể extract.

Implicit flow và Resource Owner Password Credentials grant không còn là lựa chọn mới an toàn.

---

## 24. OAuth Security BCP quan trọng hơn nhãn “OAuth 2.1”

Áp dụng RFC 9700 trực tiếp:

- authorization code + PKCE;
- exact redirect matching;
- không token/code trong URL ngoài phần protocol bắt buộc;
- access token có audience/scope tối thiểu;
- refresh token rotation hoặc sender constraint cho public client;
- phát hiện replay và revoke grant/token family;
- client authentication mạnh hơn shared secret khi phù hợp;
- sender-constrained token bằng mTLS hoặc DPoP cho threat model cần chống replay;
- bảo vệ authorization server metadata/JWKS endpoint và issuer binding.

Đừng chờ một library property tên “oauth21=true”. Security phụ thuộc profile, flow, token
validation, redirect, browser storage, client type và vận hành key/revocation.

---

## 25. Phân biệt authorization code, ID token, access token và refresh token

| Artifact | Consumer | Mục đích | Lifetime |
|---|---|---|---|
| Authorization code | token endpoint/client | đổi lấy token, không gọi API | rất ngắn, single-use |
| ID Token | OIDC client | thông tin authentication event/subject | ngắn |
| Access token | resource server | quyền gọi API theo scope/audience | ngắn |
| Refresh token | authorization server | lấy access token mới | dài hơn, phải bảo vệ/rotate |
| Session cookie | application session endpoint | duy trì browser session | theo idle/absolute policy |

Không log artifact. Không gửi qua query parameter nếu có lựa chọn header/body/cookie phù hợp.
Không dùng refresh token gọi API. Không parse access token ở client rồi coi claim là quyền
chắc chắn nếu client không phải enforcement point.

Token format opaque hay JWT là quyết định giữa issuer/resource server; client không nên phụ
thuộc nội dung access token nếu contract không nói vậy.

---

## 26. JWT validation là allowlist, không chỉ verify signature

Resource server cần kiểm tra:

1. Token type/profile mong đợi; không dùng cùng validation rule cho ID/access/reset token.
2. Algorithm nằm trong allowlist cấu hình, không tin `alg` do token tự đề nghị.
3. Signature với key gắn đúng trusted issuer.
4. `iss` exact match.
5. `aud` chứa chính API này; kiểm tra `azp`/client binding nếu profile yêu cầu.
6. `exp`, `nbf`, `iat` với clock skew nhỏ có chủ đích.
7. `sub` hợp lệ trong namespace issuer.
8. Scope/permission đủ cho action, không chỉ token hợp lệ.
9. `nonce`, `auth_time`, `acr`/`amr` theo OIDC/step-up contract khi dùng.
10. Revocation/security epoch cho hành động cần freshness mạnh.

RFC 8725 khuyên explicit typing và validation rule loại trừ nhau giữa các loại JWT để ngăn
cross-JWT confusion. JWT payload chỉ Base64URL, ai có token đều đọc được; không đặt secret/PII
không cần thiết.

---

## 27. JWKS cache và key rotation

Validator không nên fetch URL từ `jku`/`x5u` tùy ý trong token. Lấy metadata/JWKS chỉ từ
issuer đã allowlist và qua HTTPS xác minh đầy đủ.

Rotation an toàn:

```text
publish new public key
        ↓
wait validator cache nhận key
        ↓
sign token mới bằng new key
        ↓
giữ old public key tới khi token cũ hết hạn + skew
        ↓
remove old key
```

Khi gặp unknown `kid`, refresh có rate limit/single-flight; attacker không được ép mỗi
request làm outbound JWKS fetch gây DoS. Cache tôn trọng rotation nhưng có stale-if-error
policy rõ cho IdP outage.

Không chọn key chỉ bằng `kid` mà bỏ issuer/algorithm/key-use. Monitor key age, publish/sign
phase và validation failure theo `kid` nhưng không log token.

---

## 28. Refresh token rotation và replay detection

Mỗi lần refresh:

```text
RT1 ──use once──► AT2 + RT2
RT1 invalid

RT1 xuất hiện lại → replay/clone
                   revoke token family hoặc grant theo policy
                   alert + require re-authentication
```

Store refresh token như high-value credential:

- browser public client ưu tiên BFF/server-side storage;
- native app dùng OS secure storage;
- hash opaque refresh token ở authorization server nếu kiến trúc cho phép;
- gắn client, subject, device/session family, issue/expiry và status;
- absolute lifetime, inactivity lifetime và rotation;
- sender constraint nếu threat model cần.

Race giữa hai legitimate refresh request phải được xử lý atomic; nếu không, client tự kích
hoạt reuse detection. Serialize refresh per session hoặc có grace cực hẹp được thiết kế rõ.

---

## 29. Logout và revoke trong hệ phân tán

Logout có nhiều scope:

- local application session;
- authorization-server/SSO session;
- access token hiện tại;
- refresh token/grant/token family;
- mọi device của user;
- downstream cached authorization.

Xóa cookie client không revoke JWT access token đã phát. Biện pháp:

- access token ngắn hạn;
- opaque token introspection cho revoke nhanh;
- denylist/security epoch cho sự kiện khẩn cấp;
- resource server cache có TTL và push invalidation khi cần;
- revoke refresh grant để không mint token mới.

Single Logout giữa nhiều app/protocol rất phức tạp và có availability trade-off. Ghi rõ
logout button thực sự hủy cái gì và thời gian quyền còn hiệu lực tối đa.

---

## 30. Browser-based app: BFF giảm token trong JavaScript

```text
Browser ──HttpOnly session cookie──► Backend for Frontend
                                      │ giữ OAuth token server-side
                                      └──Bearer/DPoP──► APIs
```

BFF giảm access/refresh token bị JavaScript đọc và tập trung refresh/revocation. Đổi lại:

- cần CSRF defense vì dùng cookie;
- BFF là stateful/security-critical component;
- scale session store và same-site/cross-origin flow;
- XSS vẫn có thể thực hiện action dưới session nếu authorization/CSRF/UI không đủ.

Nếu SPA giữ token, tránh persistent `localStorage` theo thói quen; memory storage giảm thời
gian tồn tại nhưng reload/SSO phức tạp. Đánh giá XSS, browser refresh, tab coordination và
IdP support; không có lựa chọn “một dòng config luôn an toàn”.

---

## 31. Authorization là quyết định trên subject–action–resource–context

```text
Can(subject, action, resource, context) → allow | deny

subject : user/workload + tenant + groups
action  : invoice.read, invoice.approve
resource: invoice 123 owned by tenant A
context : time, network, device assurance, transaction amount
```

Chỉ kiểm tra `role == ADMIN` thường bỏ mất resource scope và tenant. Enforcement cần:

- deny by default;
- validate trên mọi request, không chỉ ẩn nút UI;
- server-side authoritative data;
- kiểm tra object ownership/relationship sau khi load resource;
- policy change có review/test/audit;
- fail closed khi policy/context dependency lỗi, trừ exception availability đã threat-model.

Authentication middleware không thay object-level authorization.

---

## 32. RBAC: đơn giản nhưng dễ role explosion

```text
User ──member──► Role ──grants──► Permission

alice → billing-approver → invoice.read, invoice.approve
```

RBAC tốt khi job function ổn định. Tách:

- permission nhỏ, đặt theo action/resource;
- role business gom permission;
- group/assignment gắn subject với role;
- role scope theo tenant/environment;
- administrative role và runtime role.

Tránh role tên mơ hồ `super_user_2`, role per-user và wildcard permission. Mỗi role cần owner,
purpose, eligibility, approval, expiry và review cadence.

Separation of Duties: người tạo payment không đồng thời tự approve nếu risk yêu cầu. Kiểm tra
toxic combinations cả qua membership nested và temporary grant.

---

## 33. ABAC: policy theo attribute và context

```text
allow if
  subject.department == resource.department
  AND subject.clearance >= resource.classification
  AND context.device_trust == "managed"
```

ABAC giảm role explosion nhưng chuyển complexity sang attribute governance:

- nguồn attribute nào authoritative?
- freshness và default khi thiếu?
- ai sửa department/clearance?
- type, vocabulary và namespace có nhất quán?
- token claim cũ còn sống bao lâu?

Không tin attribute từ request header/client. Attribute phải đến từ verified issuer,
directory hoặc resource store. Policy cần simulation, explainability và test khi attribute
null/unknown.

---

## 34. ReBAC: quyền từ quan hệ

```text
document:quarterly#viewer  ← group:finance#member ← user:alice
folder:reports#parent      → document:quarterly
```

ReBAC hợp collaboration, sharing, organization hierarchy và “owner/editor/viewer”. Nó biểu
diễn graph relationship tốt hơn hàng nghìn role.

Rủi ro:

- traversal sâu/cycle và performance;
- inherited sharing khó giải thích;
- xóa relationship không invalidate cache kịp;
- tenant boundary bị bắc cầu qua group ngoài;
- graph store trở thành critical authorization data.

Giới hạn relation type/depth, tenant-aware namespace, consistent write và API “why allowed?”
để support/audit hiểu quyết định.

---

## 35. PDP, PEP và PIP

```text
Request
  │
  ▼
PEP – Policy Enforcement Point
  │ hỏi subject/action/resource/context
  ▼
PDP – Policy Decision Point ──đọc──► PIP – attributes/relationships
  │
  └── allow/deny + obligations/reason
```

PEP nằm ở API/service/resource boundary. PDP có thể embedded library hoặc central service.
Central PDP giúp policy nhất quán nhưng thêm latency/availability/cache problem.

Thiết kế rõ:

- decision input schema và version;
- cache key chứa đủ subject/resource/context;
- policy/data freshness và invalidation;
- timeout/failure behavior;
- audit decision ID/policy version;
- shadow evaluation trước rollout;
- không log sensitive attribute quá mức.

Gateway authorization chỉ là lớp đầu; service vẫn phải enforce object/domain rule mà gateway
không có đủ dữ liệu.

---

## 36. Object-level và tenant-level authorization

Sai:

```http
GET /api/invoices/8472
Authorization: valid-user-token
```

Nếu code chỉ xác thực token rồi `findById(8472)`, user tenant B có thể đọc invoice tenant A.

Đúng về mental model:

```sql
SELECT ...
FROM invoice
WHERE tenant_id = :authenticatedTenant
  AND invoice_id = :requestedId;
```

Sau đó vẫn kiểm tra action/relationship phù hợp. Tenant ID lấy từ trusted authentication
context, không lấy raw body/query rồi coi là authority.

List, count, export, search, bulk update và indirect object (attachment/comment) đều phải
scope; không chỉ GET by ID. Database RLS là defense-in-depth, không thay application AuthZ.

Test bằng ít nhất hai user × hai tenant × nhiều role và cả resource không tồn tại để tránh
enumeration/timing leak quá rõ.

---

## 37. Token claim có thể stale

Nếu access token 60 phút chứa `role=admin`, việc xóa role trong directory không có hiệu lực
ở resource server cho tới token hết hạn nếu không có revoke/freshness channel.

Chọn strategy theo risk:

- token ngắn hạn;
- dynamic lookup cho high-risk action;
- policy/security version trong token + server check;
- introspection;
- event push/cache invalidation;
- step-up/re-authentication cho sensitive operation.

Không nhét mọi permission/relationship biến động vào token vì token phình, rò dữ liệu và
khó revoke. Token nên mang identity và stable coarse claims; resource server/PDP quyết định
fine-grained quyền từ dữ liệu hiện tại khi cần.

---

## 38. Admin access: PAM, JIT và Just Enough Administration

Admin identity nên riêng khỏi daily account. Baseline:

- phishing-resistant MFA;
- privileged access workstation/device posture nếu cần;
- Just-in-Time elevation có approval, lý do và expiry;
- Just Enough Administration: chỉ action/resource cần thiết;
- session recording/audit cho thao tác đặc quyền phù hợp pháp lý;
- không shared password; dùng named identity;
- không permanent cloud/database admin nếu có thể;
- alert grant, policy, MFA và recovery change.

JIT không chỉ thêm expiry vào role; phải thu hồi active token/session hoặc đảm bảo token
lifetime không vượt grant. Reviewer không được tự approve yêu cầu của chính mình nếu SoD yêu
cầu độc lập.

---

## 39. Break-glass account

Break-glass dùng khi IdP/MFA/control plane bình thường không hoạt động. Nó cần:

- số lượng tối thiểu và purpose rõ;
- credential mạnh, lưu offline/vault với dual control;
- không dùng thường ngày, không phụ thuộc cùng failure domain;
- network/source restriction nếu có thể;
- alert tức thì mỗi lần access/attempt;
- runbook phê duyệt, thời gian tối đa và hành động cho phép;
- rotate/reseal và post-use review;
- drill định kỳ nhưng không làm lộ secret.

Break-glass không phải “admin chung để tiện”. Nếu không audit/rotate được sau mỗi lần dùng,
nó trở thành persistent backdoor.

---

## 40. Service account và API key

Mỗi workload/integration có identity riêng, owner và expiry. API key nên:

- random CSPRNG, entropy cao;
- có public prefix/ID để lookup và secret phần còn lại;
- chỉ lưu hash/HMAC verifier nếu không cần recover plaintext;
- scope theo API/action/tenant/environment;
- không đặt trong URL, Git, image hoặc log;
- hỗ trợ hai key active để rotate không downtime;
- last-used metadata và anomaly alert;
- disable khi owner/service mất.

API key chủ yếu xác thực client, không tự đại diện end-user và thường không có phishing
resistance. Đừng chuyển key qua browser public client.

Nếu platform hỗ trợ workload identity ngắn hạn, ưu tiên nó hơn static key sống nhiều năm.

---

## 41. Workload identity: attestation thay static secret

```text
Platform attests workload
        │
        ▼
Identity agent/issuer
        │ phát credential ngắn hạn
        ├── X.509 SVID → mTLS
        └── JWT SVID   → audience-bound token
```

SPIFFE định danh workload bằng URI như:

```text
spiffe://prod.example.com/ns/payments/sa/settlement
```

SVID có lifetime ngắn và Workload API cung cấp/rotate credential mà app không giữ static
private key trong config. X.509-SVID được ưu tiên khi có thể vì bearer JWT dễ replay nếu bị
lấy; JWT-SVID phải validate audience và trust-domain bundle.

Workload identity không tự cấp authorization. Service B vẫn quyết định SPIFFE ID nào được
action gì. Tách trust domain production/staging và federation chỉ khi đã định nghĩa semantics
của foreign identity.

---

## 42. End-user identity qua microservice và confused deputy

Không tin header như `X-User-Id` chỉ vì request đến từ internal network. Gateway hoặc service
phải xác minh signed assertion/token; downstream kiểm tra issuer, audience và scope riêng.

```text
User → Service A → Service B
         │            │
         │            ├─ authenticate Service A workload
         │            └─ authorize delegated user/action
         └─ không được tự nâng scope khi gọi B
```

Tách:

- **caller workload identity:** service nào đang kết nối;
- **end-user/delegated identity:** ai khởi tạo hành động;
- **delegation scope:** service A được làm gì thay user;
- **resource audience:** token chỉ dùng ở B.

Một backend có credential mạnh nhưng nhận resource ID tùy ý rồi gọi downstream bằng quyền
rộng là confused deputy. Bind request, subject, tenant, purpose và audience; dùng token
exchange/on-behalf-of flow chuẩn nếu cần, không copy token mọi nơi.

---

## 43. Provisioning với SCIM và event lifecycle

SCIM chuẩn hóa resource User/Group và protocol tạo, cập nhật, disable. Nó giúp IdP đẩy
joiner/mover/leaver tới SaaS/application.

Nhưng SSO và SCIM khác nhau:

- SSO quyết định login/federation;
- SCIM quản lý account/group lifecycle;
- tắt SSO không chắc xóa local API key/session;
- SCIM disable không tự revoke mọi artifact nếu application chưa nối lifecycle.

Consumer cần idempotent upsert, stable external ID, version/concurrency handling, audit và
dead-letter/retry. Deprovision event phải ưu tiên cao hơn cosmetic profile update.

Định kỳ reconcile source-of-truth với downstream để phát hiện missed webhook, manual local
account và group drift. “Event delivered” không bằng “mọi enforcement point đã thu hồi”.

---

## 44. Access review và entitlement governance

Inventory tối thiểu:

```text
subject → account → group/role → permission → resource scope
        → credential/session → owner → expiry → last used
```

Review nên ưu tiên:

- privileged và break-glass access;
- dormant account/credential;
- contractor quá end date;
- direct grant ngoài role chuẩn;
- toxic combination/SoD;
- cross-tenant/cross-environment access;
- service account không owner;
- group nested khó giải thích.

Manager bấm “approve all” mỗi quý không tạo assurance. Reviewer cần business context,
effective permission, last-used và khả năng revoke an toàn. Access certification phải tạo
action/expiry và kiểm tra action đã hoàn tất.

---

## 45. Credential rotation và dependency graph

Credential có consumer, issuer, verifier và distribution path. Rotation không downtime:

```text
publish/issue new credential
        ↓
deploy consumers chấp nhận/dùng new
        ↓
observe old usage về 0
        ↓
revoke old
        ↓
verify không còn dependency
```

Với signing key, cần overlap public verification keys. Với API key, hai active slot. Với
certificate, trust bundle phải nhận issuer/key mới trước khi leaf đổi.

Mỗi credential cần owner, issued/expiry, scope, last used, rotation mechanism và emergency
revoke. Rotation định kỳ không bù được secret đã public trong Git: phải revoke ngay, rewrite
history chỉ là cleanup, rồi điều tra usage.

---

## 46. Audit và detection cho IAM

Ghi event có cấu trúc:

- login success/failure/challenge và authentication method;
- passkey/MFA enroll, remove, recovery code use;
- password/email/recovery channel change;
- session create/renew/revoke/logout;
- OAuth consent, code/token error, refresh reuse;
- role/group/policy/direct grant change;
- SCIM create/update/disable và reconciliation drift;
- admin elevation, impersonation và break-glass;
- service credential issue/rotate/revoke.

Log subject ID, actor ID, target, tenant, action, result, reason, policy version, device/source
risk và correlation ID. Không log password, OTP, raw session/token, authorization code,
private key hoặc full recovery link.

Alert theo baseline: impossible privilege grant, MFA reset + payout change, refresh reuse,
leaver login, admin từ source mới, nhiều account bị spray và audit pipeline gap.

---

## 47. Runbook: credential stuffing campaign

1. Phân biệt brute force một account, spraying một password và stuffing nhiều cặp đã lộ.
2. Xác định issuer/app/tenant/source/ASN/device và success rate.
3. Tăng throttling/risk challenge có kiểm soát; tránh lockout DoS toàn bộ user.
4. Revoke session của account thành công bất thường; yêu cầu reset/strong re-auth.
5. Block breached password và kiểm tra credential reuse signal theo privacy policy.
6. Bảo vệ reset/MFA enrollment khỏi attacker đã có partial access.
7. Thông báo user bằng kênh đáng tin, không gửi login link dễ phishing.
8. Theo dõi attacker đổi IP/device và fallback endpoint/legacy protocol.
9. Sau incident, ưu tiên passkey/MFA, bot defense và detection gap.

Không chỉ block một IP; stuffing phân tán và NAT làm IP vừa yếu vừa có false positive.

---

## 48. Runbook: session/access/refresh token bị lộ

1. Xác định loại token, issuer, subject, audience, scope, expiry, session/grant family.
2. Không paste token vào ticket/chat/log để “nhờ kiểm tra”.
3. Revoke session/grant/refresh family; access token xử lý qua introspection/denylist/epoch
   hoặc chờ short expiry theo risk.
4. Rotate signing/encryption key chỉ khi key bị lộ, không rotate toàn issuer vì một bearer
   token đơn lẻ nếu không cần.
5. Điều tra nguồn: XSS, malware, proxy/log, browser storage, redirect, CI, support dump.
6. Kiểm tra replay theo audience/resource và downstream action.
7. Re-authenticate user, rotate recovery/MFA nếu compromise rộng.
8. Reconcile high-value transaction và thông báo stakeholder.

Nếu token xuất hiện trong public log/repository, giả định đã bị lấy dù chưa thấy usage.

---

## 49. Runbook: privileged/admin account bị compromise

1. Dùng break-glass độc lập để disable identity và chặn login mới.
2. Revoke mọi session/token/key/certificate, không chỉ đổi password.
3. Preserve IdP, cloud, directory, application và endpoint evidence.
4. Liệt kê grant/policy/group/MFA/recovery/signing key/SCIM change trong compromise window.
5. Tìm account/persistence mới, federated trust và backdoor API key.
6. Revert theo known-good policy-as-code/state; không chỉ xóa thay đổi nhìn thấy đầu tiên.
7. Rotate shared credential/admin secrets mà identity có thể đọc.
8. Kiểm tra data access/export/destructive action và backup integrity.
9. Khôi phục bằng named identity mới/phishing-resistant authenticator.
10. Review separation, JIT, device posture và alert gap.

Admin compromise là control-plane incident; blast radius có thể vượt một application.

---

## 50. Runbook: IdP hoặc policy engine outage

Thiết kế trước khi outage:

- ứng dụng giữ session hiện có bao lâu nếu IdP không truy cập được?
- JWKS cache stale trong giới hạn nào?
- login mới fail closed hay có local emergency path?
- authorization PDP timeout thì deny hay degraded read-only?
- break-glass nằm khác failure domain không?
- admin có thể revoke khẩn cấp khi control plane lỗi không?

Không chuyển sang “allow all” để giữ availability. Với một số read-only low-risk operation,
cached decision có bounded TTL có thể chấp nhận; write/admin nên fail closed.

Trong incident, phân biệt IdP availability với token signature validation: resource server
có cached key vẫn có thể xác minh access token ngắn hạn mà không gọi IdP mỗi request. Nhưng
revocation/freshness sẽ yếu hơn; quan sát và giới hạn cửa sổ.

---

## 51. Test authorization như ma trận, không chỉ happy path

| Subject | Action | Resource | Context | Kỳ vọng |
|---|---|---|---|---|
| tenant A viewer | read | A invoice | normal | allow |
| tenant A viewer | update | A invoice | normal | deny |
| tenant A admin | read | B invoice | normal | deny |
| expired contractor | read | old project | any | deny |
| JIT admin | approve | allowed scope | before expiry + MFA | allow |
| JIT admin | approve | other scope | before expiry | deny |
| workload A | call | API B | wrong audience | deny |

Thêm negative protocol tests:

- JWT sai issuer/audience/algorithm/type/expiry/nonce;
- unknown `kid` storm và JWKS outage;
- OAuth state/PKCE/redirect mismatch, code replay;
- session fixation, cookie scope, CSRF và logout;
- refresh token concurrent use/replay;
- mover/leaver + active session;
- missing/stale attribute và PDP timeout;
- two-user/two-tenant BOLA trên list/count/export/bulk endpoint.

Test bằng identity không phải owner/superuser và kiểm tra audit event tương ứng.

---

## 52. Production checklist

### Identity và authenticator

- [ ] Human, customer và workload identity tách lifecycle; không shared admin.
- [ ] Stable internal ID hoặc `(iss, sub)`; email không là authorization key.
- [ ] Joiner/mover/leaver có source-of-truth, SLA, reconciliation và session revoke.
- [ ] Password theo NIST Rev.4, breached blocklist, Argon2id và rate limit.
- [ ] Recovery/change email/MFA cần recent auth, single-use token và notification.
- [ ] Admin/high-value action có phishing-resistant MFA/passkey và nhiều recovery path an toàn.

### Session, OAuth/OIDC và token

- [ ] Cookie Secure, HttpOnly, SameSite, scope hẹp; CSRF/XSS defense đúng kiến trúc.
- [ ] Idle + absolute timeout, rotate khi privilege change, logout server-side.
- [ ] Authorization Code + PKCE S256, exact redirect, state/nonce/issuer validation.
- [ ] JWT allowlist algorithm, signature, type, issuer, audience, time, scope và token-use.
- [ ] JWKS rotation/cache/unknown-kid DoS được test.
- [ ] Refresh rotation/replay detection; access token ngắn hạn và revoke contract rõ.

### Authorization và operations

- [ ] Deny by default, enforce mọi request/action/resource; tenant scope nằm trong query/policy.
- [ ] Role/attribute/relation có owner, namespace, freshness, expiry và test.
- [ ] Admin dùng JIT/JEA/PAM; break-glass độc lập, alert và drill.
- [ ] Workload dùng short-lived identity thay static key khi có thể.
- [ ] SCIM/event provisioning idempotent; định kỳ reconcile downstream drift.
- [ ] Audit không chứa secret/token; alert stuffing, refresh reuse, grant/MFA/break-glass change.
- [ ] Incident runbook cho credential, token, admin và IdP outage đã drill.

---

## 53. Anti-pattern và cách sửa

### “Có MFA là chống phishing”

OTP/push vẫn có thể relay hoặc fatigue. Dùng WebAuthn/passkey/security key cho phishing
resistance, nhất là admin/high-value flow.

### “OAuth là đăng nhập”

OAuth là delegated authorization. Dùng OpenID Connect và validate ID Token/issuer/nonce cho
authentication.

### “JWT hợp lệ nghĩa được phép truy cập object”

JWT chỉ chứng minh claim/token theo issuer. Service vẫn kiểm tra action, resource ownership,
tenant, relationship và freshness.

### “Token ở localStorage vì cookie không an toàn”

LocalStorage dễ bị XSS đọc; HttpOnly cookie cần CSRF defense. Chọn BFF/session/token theo
threat model, không bằng khẩu hiệu.

### “Xóa user khỏi IdP là offboard xong”

Local session, refresh token, API key, SaaS account và downstream group có thể còn. Cần
revoke + SCIM/event + reconciliation.

### “Internal header `X-User-Id` đáng tin”

Network path không đủ làm identity. Verify signed assertion/token và audience; downstream
enforce quyền riêng.

### “Break-glass account không MFA để dễ dùng khi khẩn cấp”

Đó là backdoor lâu dài. Dùng credential mạnh/offline/dual control, independent path, alert,
expiry và rotate sau use.

---

## 54. Câu hỏi phỏng vấn và tự kiểm tra

### Authentication và authorization khác gì?

Authentication chứng minh subject là ai; authorization quyết định subject đó được action gì
trên resource/context cụ thể.

### Password + PIN có phải MFA không?

Không nếu cả hai đều là “something you know” và được verifier xử lý như hai knowledge secret.

### Vì sao TOTP không phishing-resistant?

User có thể nhập mã vào trang giả và attacker relay mã tới verifier thật trong thời gian hiệu lực.

### OAuth access token và OIDC ID Token khác gì?

Access token dành cho resource server để authorize API; ID Token dành cho OIDC client để
xác minh authentication event và subject.

### Vì sao phải kiểm tra `aud` của JWT?

Để token cấp cho API/client khác không bị token substitution và dùng tại recipient này.

### Xóa role có hiệu lực ngay với JWT 60 phút không?

Không nếu resource server chỉ tin claim self-contained và không có revocation/freshness
check; quyền có thể stale tới expiry.

### RBAC, ABAC và ReBAC khác nhau thế nào?

RBAC dựa role, ABAC dựa attribute/context, ReBAC dựa quan hệ graph giữa subject/resource.

### SSO có tự động offboard SaaS account không?

Không. SSO xử lý federation/login; provisioning/deprovision thường cần SCIM/event và revoke
session/credential riêng.

---

## 55. Nguồn chính thức và chủ đề tiếp theo

- [NIST SP 800-63 Revision 4](https://pages.nist.gov/800-63-4/)
- [NIST SP 800-63B-4 – Authentication](https://pages.nist.gov/800-63-4/sp800-63b.html)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
- [OWASP MFA Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Multifactor_Authentication_Cheat_Sheet.html)
- [OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)
- [OAuth 2.0 Security Best Current Practice – RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html)
- [JWT Best Current Practices – RFC 8725](https://www.rfc-editor.org/rfc/rfc8725.html)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0-final.html)
- [WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/)
- [SCIM Protocol – RFC 7644](https://www.rfc-editor.org/rfc/rfc7644.html)
- [NIST SP 800-207 – Zero Trust Architecture](https://csrc.nist.gov/pubs/sp/800/207/final)
- [SPIFFE specifications](https://spiffe.io/docs/latest/spiffe-specs/)

Học tiếp:

1. [Secrets & Key Management](../secrets/secrets_key_management.md) – secret lifecycle, envelope encryption, KMS/HSM, rotation và emergency revoke.
2. [Threat Modeling & Secure Architecture](../architecture/threat_modeling_secure_architecture.md) – assets, trust boundary, abuse case, STRIDE và security requirement.

---

*Cập nhật lần cuối: 2026-08-02.*
