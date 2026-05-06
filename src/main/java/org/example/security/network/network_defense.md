# Network Defense Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Firewall – iptables / nftables

### What – Firewall là gì?
Firewall kiểm soát network traffic dựa trên rules, là tuyến phòng thủ đầu tiên của network security.

### How – iptables Architecture

```
iptables Tables & Chains:
┌─────────────────────────────────────────────────────────┐
│  Tables:                                                │
│  filter  → accept/drop/reject packets (default)        │
│  nat     → Network Address Translation                 │
│  mangle  → modify packet headers                       │
│  raw     → connection tracking bypass                  │
│                                                         │
│  Chains (packet flow):                                  │
│  PREROUTING → INPUT → (local process) → OUTPUT → POSTROUTING │
│               ↓                                         │
│            FORWARD                                      │
└─────────────────────────────────────────────────────────┘

Packet flow:
Incoming: PREROUTING → INPUT → Application
Forwarded: PREROUTING → FORWARD → POSTROUTING
Outgoing: Application → OUTPUT → POSTROUTING
```

```bash
# === Basic iptables Rules ===

# Mặc định: DROP all, chỉ ACCEPT những gì cần
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT        # cho phép outbound mặc định

# Allow established connections (không chặn responses)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow ICMP (ping) – giới hạn rate
iptables -A INPUT -p icmp --icmp-type echo-request \
  -m limit --limit 1/s --limit-burst 5 -j ACCEPT

# SSH: chỉ từ trusted networks
iptables -A INPUT -p tcp --dport 22 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 172.16.0.0/12 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP      # drop từ nơi khác

# Web services
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# === Rate Limiting (chống DoS / brute force) ===
# SSH brute force protection
iptables -A INPUT -p tcp --dport 22 \
  -m recent --name SSH --set --rsource
iptables -A INPUT -p tcp --dport 22 \
  -m recent --name SSH --update --rsource --seconds 60 --hitcount 10 \
  -j DROP
# → max 10 SSH connections trong 60 giây per IP

# SYN flood protection
iptables -A INPUT -p tcp --syn \
  -m limit --limit 25/s --limit-burst 50 \
  -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP

# === Port Knocking ===
iptables -N KNOCK_PHASE1
iptables -N KNOCK_PHASE2
iptables -N KNOCK_OPEN

# Phase 1: knock port 7000
iptables -A INPUT -p tcp --dport 7000 -m recent --set --name PHASE1
# Phase 2: knock port 8000 (sau phase 1)
iptables -A INPUT -p tcp --dport 8000 \
  -m recent --rcheck --name PHASE1 \
  -m recent --set --name PHASE2
# Phase 3: knock port 9000 (sau phase 2) → open SSH
iptables -A INPUT -p tcp --dport 9000 \
  -m recent --rcheck --name PHASE2 \
  -m recent --set --name PHASE3
iptables -A INPUT -p tcp --dport 22 \
  -m recent --rcheck --seconds 30 --name PHASE3 -j ACCEPT

# === Logging suspicious traffic ===
iptables -A INPUT -j LOG \
  --log-prefix "[IPTABLES DROP] " \
  --log-level 4 \
  --log-uid

# Save / Restore rules
iptables-save > /etc/iptables/rules.v4
iptables-restore < /etc/iptables/rules.v4
```

### How – nftables (Modern iptables)

```bash
# nftables: unified framework thay iptables/ip6tables/arptables/ebtables

# /etc/nftables.conf
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Established connections
        ct state established,related accept
        ct state invalid drop

        # Loopback
        iifname "lo" accept

        # ICMP (rate limited)
        ip protocol icmp limit rate 5/second accept
        ip6 nexthdr icmpv6 limit rate 5/second accept

        # SSH (trusted IPs only)
        ip saddr 10.0.0.0/8 tcp dport 22 accept
        ip saddr 172.16.0.0/12 tcp dport 22 accept

        # Web
        tcp dport { 80, 443 } accept

        # SSH brute force: max 10 connections/minute per IP
        tcp dport 22 \
            meter ssh-meter { ip saddr limit rate 10/minute } \
            accept

        # Log and drop rest
        log prefix "[NFT DROP] " level warn
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table inet nat {
    chain prerouting {
        type nat hook prerouting priority -100;
        # Port forwarding: external 8080 → internal 80
        tcp dport 8080 dnat to 192.168.1.10:80
    }

    chain postrouting {
        type nat hook postrouting priority 100;
        # Masquerade outbound traffic
        oifname "eth0" masquerade
    }
}

# Apply
nft -f /etc/nftables.conf

# Kiểm tra
nft list ruleset
nft list table inet filter
```

---

## 2. IDS / IPS – Snort & Suricata

### What – IDS/IPS là gì?
- **IDS** (Intrusion Detection System): phát hiện tấn công, ghi log, alert
- **IPS** (Intrusion Prevention System): phát hiện + block traffic tấn công
- **NIDS** (Network-based): monitor network traffic
- **HIDS** (Host-based): monitor system calls, logs, file changes

### How – Suricata Setup

```yaml
# suricata.yaml (quan trọng nhất)
vars:
  address-groups:
    HOME_NET: "[192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12]"
    EXTERNAL_NET: "!$HOME_NET"
    HTTP_SERVERS: "$HOME_NET"
    SQL_SERVERS: "$HOME_NET"
    DNS_SERVERS: "$HOME_NET"

  port-groups:
    HTTP_PORTS: "80"
    SHELLCODE_PORTS: "!80"
    ORACLE_PORTS: 1521
    SSH_PORTS: 22

# Network interface
af-packet:
  - interface: eth0
    threads: 4
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

# Logging
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      types:
        - alert:
            payload: yes
            payload-printable: yes
            metadata: yes
        - http:
            extended: yes
        - dns:
            query: yes
            answer: yes
        - tls:
            extended: yes
        - ssh
        - smtp

# Rule sources
default-rule-path: /etc/suricata/rules
rule-files:
  - suricata.rules

# IPS mode (inline, thay vì tap)
# Dùng NFQUEUE:
# iptables -I FORWARD -j NFQUEUE
# suricata -c /etc/suricata/suricata.yaml -q 0
```

### How – Suricata Rules

```
# Suricata rule syntax:
# action proto src_ip src_port direction dst_ip dst_port (options)

# Detect SQL injection attempt
alert http $EXTERNAL_NET any -> $HTTP_SERVERS $HTTP_PORTS (
    msg:"SQL Injection Attempt - UNION SELECT";
    content:"UNION"; nocase;
    content:"SELECT"; nocase; distance:0;
    pcre:"/UNION\s+SELECT/i";
    classtype:web-application-attack;
    sid:1000001;
    rev:1;
)

# Detect XSS
alert http $EXTERNAL_NET any -> $HTTP_SERVERS $HTTP_PORTS (
    msg:"XSS Attempt - Script Tag";
    content:"<script";
    nocase;
    http_uri;
    classtype:web-application-attack;
    sid:1000002;
    rev:1;
)

# Detect reverse shell
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"Possible Reverse Shell - Bash";
    content:"bash -i";
    content:"/dev/tcp/";
    classtype:shellcode-detect;
    sid:1000003;
    rev:1;
)

# Detect port scan (nmap SYN scan)
alert tcp $EXTERNAL_NET any -> $HOME_NET any (
    msg:"Possible Port Scan";
    flags:S,12;
    threshold: type threshold, track by_src, count 20, seconds 1;
    classtype:attempted-recon;
    sid:1000004;
    rev:1;
)

# Detect DNS tunneling
alert dns any any -> any any (
    msg:"Possible DNS Tunneling - Long Query";
    dns.query; content:".";
    pcre:"/^[a-zA-Z0-9+\/=]{40,}\./";
    classtype:policy-violation;
    sid:1000005;
    rev:1;
)

# Detect crypto mining (stratum protocol)
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"Possible Crypto Mining - Stratum Protocol";
    content:"{\"method\": \"mining.subscribe\"";
    classtype:policy-violation;
    sid:1000006;
    rev:1;
)

# Block (IPS mode) brute force SSH
drop tcp $EXTERNAL_NET any -> $SSH_SERVERS $SSH_PORTS (
    msg:"SSH Brute Force Attempt";
    flow:to_server,established;
    content:"SSH";
    threshold: type threshold, track by_src, count 5, seconds 60;
    sid:1000007;
    rev:1;
)
```

```bash
# Quản lý Suricata
systemctl start suricata
systemctl enable suricata

# Update rules (Emerging Threats)
suricata-update update-sources
suricata-update enable-source et/open
suricata-update
systemctl restart suricata

# Test rules
suricata -T -c /etc/suricata/suricata.yaml    # test config
suricata -r capture.pcap -c /etc/suricata/suricata.yaml  # test trên pcap

# Analyze EVE log
cat /var/log/suricata/eve.json | jq 'select(.event_type=="alert")' | \
  jq '{timestamp: .timestamp, alert: .alert.signature, src: .src_ip, dest: .dest_ip}'

# Top alerts
cat /var/log/suricata/eve.json | jq -r 'select(.event_type=="alert") | .alert.signature' | \
  sort | uniq -c | sort -rn | head -20
```

---

## 3. SIEM – Log Management & Correlation

### How – Wazuh (Open Source SIEM/XDR)

```yaml
# Wazuh Manager: /var/ossec/etc/ossec.conf
<ossec_config>
  <global>
    <email_notification>yes</email_notification>
    <email_to>security@company.com</email_to>
    <smtp_server>smtp.company.com</smtp_server>
  </global>

  <!-- Log analysis -->
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/apache2/access.log</location>
  </localfile>

  <!-- File Integrity Monitoring -->
  <syscheck>
    <frequency>3600</frequency>
    <directories realtime="yes" check_all="yes">/etc,/bin,/sbin</directories>
    <directories realtime="yes">/var/www/html</directories>
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/mnttab</ignore>
  </syscheck>

  <!-- Rootkit detection -->
  <rootcheck>
    <rootkit_files>/var/ossec/etc/shared/rootkit_files.txt</rootkit_files>
    <rootkit_trojans>/var/ossec/etc/shared/rootkit_trojans.txt</rootkit_trojans>
  </rootcheck>

  <!-- Active response: auto-block -->
  <active-response>
    <command>firewall-drop</command>
    <location>local</location>
    <rules_id>5712</rules_id>    <!-- SSH brute force rule -->
    <timeout>600</timeout>
  </active-response>
</ossec_config>
```

```xml
<!-- Custom Wazuh Rules -->
<!-- /var/ossec/etc/rules/custom_rules.xml -->
<group name="custom,web">
  <!-- SQL Injection in web logs -->
  <rule id="100001" level="10">
    <if_matched_sid>31103</if_matched_sid>    <!-- Apache access log -->
    <url_regex>UNION|SELECT|INSERT|UPDATE|DELETE|DROP|EXEC</url_regex>
    <description>SQL Injection attempt detected</description>
    <group>web,attack,sql_injection</group>
    <mitre>
      <id>T1190</id>
    </mitre>
  </rule>

  <!-- Multiple login failures then success (brute force) -->
  <rule id="100002" level="12">
    <if_matched_sid>5712</if_matched_sid>     <!-- SSH auth failure -->
    <same_source_ip/>
    <description>Possible SSH brute force success after failures</description>
    <group>authentication_success,pci_dss_10.2.4,pci_dss_10.2.5</group>
  </rule>

  <!-- New user created (persistence) -->
  <rule id="100003" level="8">
    <if_sid>5901</if_sid>                     <!-- useradd -->
    <description>New system user created</description>
    <group>account_management</group>
    <mitre>
      <id>T1136</id>
    </mitre>
  </rule>
</group>
```

---

## 4. Zero Trust Architecture

### What – Zero Trust là gì?
"Never trust, always verify." Mọi request đều phải được authenticate và authorize dù đến từ internal network. Không có "trusted perimeter."

### How – Zero Trust Principles

```
Traditional Security (Perimeter-based):
├── External: UNTRUSTED → block
└── Internal: TRUSTED → allow
→ Vấn đề: một khi vào được internal → lateral movement dễ dàng

Zero Trust:
├── Verify every user
├── Verify every device
├── Least privilege access
├── Assume breach
└── Encrypt everything (East-West traffic)

Pillars:
1. Identity     : MFA, SSO, adaptive auth
2. Device       : device health check, MDM, cert-based
3. Network      : micro-segmentation, SD-WAN
4. Application  : application-level auth, ZTNA
5. Data         : classify, encrypt, DLP
6. Visibility   : logs, SIEM, UEBA
```

### How – BeyondCorp / ZTNA Implementation

```
Google BeyondCorp Model:
┌─────────────────────────────────────────────────────┐
│  User + Device → Identity-Aware Proxy (IAP)        │
│  IAP checks:                                        │
│  ├── User identity (Google SSO / Okta)              │
│  ├── Device policy (cert, MDM status, OS version)  │
│  ├── Context (location, time, risk score)           │
│  └── Application permission                         │
│  If all pass → access granted to specific app only │
│  KHÔNG có VPN, không có network-level trust        │
└─────────────────────────────────────────────────────┘
```

```bash
# Nginx với mTLS (client certificates) + OIDC:
server {
    listen 443 ssl;
    ssl_certificate /etc/ssl/server.crt;
    ssl_certificate_key /etc/ssl/server.key;

    # Client certificate verification
    ssl_client_certificate /etc/ssl/ca.crt;
    ssl_verify_client on;
    ssl_verify_depth 2;

    location / {
        # Chỉ allow nếu client cert verified
        if ($ssl_client_verify != SUCCESS) {
            return 403;
        }

        # Pass cert info đến backend
        proxy_set_header X-Client-Cert-DN $ssl_client_s_dn;
        proxy_set_header X-Client-Cert-Fingerprint $ssl_client_fingerprint;

        proxy_pass http://backend;
    }
}

# Mikro-segmentation với Kubernetes NetworkPolicy:
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: zero-trust-default-deny
  namespace: production
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  # Không có ingress/egress rules → deny all
  # Mỗi service phải có explicit allow rule
```

---

## 5. Network Segmentation

### How – DMZ Architecture

```
Internet → [Firewall 1] → DMZ → [Firewall 2] → Internal Network

DMZ (Demilitarized Zone):
├── Web Server (nginx/Apache)
├── Reverse Proxy (Nginx/HAProxy)
├── Mail Server
└── DNS Server

Firewall 1 rules:
→ Internet → DMZ: allow 80, 443
→ DMZ → Internet: allow 80, 443 (outbound only)

Firewall 2 rules:
→ DMZ → Internal: allow only specific ports to specific servers
  (e.g., web server → DB: 5432)
→ Internal → DMZ: allow management ports (22 from jump host)
→ Internet → Internal: DENY ALL

Benefits:
→ Compromise của web server không = access internal network
→ Lateral movement bị giới hạn bởi Firewall 2
```

### How – VLAN Segmentation

```bash
# VLAN tagging với Linux
ip link add link eth0 name eth0.10 type vlan id 10   # VLAN 10
ip link add link eth0 name eth0.20 type vlan id 20   # VLAN 20
ip addr add 192.168.10.1/24 dev eth0.10
ip addr add 192.168.20.1/24 dev eth0.20
ip link set eth0.10 up
ip link set eth0.20 up

# Inter-VLAN routing qua iptables
# Cho phép VLAN 10 (user) đến VLAN 30 (server) chỉ port 443
iptables -A FORWARD -i eth0.10 -o eth0.30 -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i eth0.30 -o eth0.10 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i eth0.10 -o eth0.30 -j DROP   # deny rest

# VLAN Attack: Double-tagging (VLAN hopping)
# Attacker trên VLAN 10 gửi frame với 2 VLAN tags: outer=10, inner=20
# Switch strip outer tag → forward đến VLAN 20
# Phòng thủ:
# - Đặt native VLAN khác VLAN thực
# - Disable dynamic trunking (DTP)
# - Prune unused VLANs từ trunk ports
```

---

## 6. Honeypots & Deception

### How – Honeypot Setup

```bash
# OpenCanary: lightweight honeypot
pip install opencanary

# opencanary.conf
{
  "device.node_id": "opencanary-1",
  "git.enabled": true,
  "git.port": 9418,
  "ftp.enabled": true,
  "ftp.port": 21,
  "ssh.enabled": true,
  "ssh.port": 22,
  "telnet.enabled": true,
  "telnet.port": 23,
  "http.enabled": true,
  "http.port": 80,
  "smb.enabled": true,
  "mysql.enabled": true,
  "mysql.port": 3306,
  "redis.enabled": true,
  "redis.port": 6379,
  "logger": {
    "class": "PyLogger",
    "kwargs": {
      "formatters": {
        "plain": {"format": "%(message)s"}
      },
      "handlers": {
        "console": {
          "class": "logging.StreamHandler",
          "stream": "ext://sys.stdout",
          "formatter": "plain"
        },
        "file": {
          "class": "logging.FileHandler",
          "filename": "/var/log/opencanary/opencanary.log",
          "formatter": "plain"
        }
      }
    }
  }
}

opencanaryd --start

# Canary tokens: invisible tripwires
# canarytokens.org: tạo tokens trong files, emails, DNS
# - Word doc: nếu ai mở → alert kèm IP
# - DNS canary: trong /etc/hosts, nếu resolve → alert
# - AWS key canary: fake credentials, nếu ai dùng → alert
```

---

### Compare – Firewall Types

| | Packet Filter | Stateful | Next-Gen (NGFW) | WAF |
|--|---------------|----------|-----------------|-----|
| **Layer** | L3/L4 | L3/L4 | L3-L7 | L7 (HTTP) |
| **State** | No | Yes | Yes | Yes |
| **App aware** | No | Partial | Yes | Yes (HTTP) |
| **SSL Inspect** | No | No | Yes | Yes |
| **IPS** | No | No | Yes | Yes |
| **Ví dụ** | iptables | iptables stateful | Palo Alto, Fortinet | ModSecurity, Cloudflare |

### Compare – IDS vs IPS

| | IDS | IPS |
|--|-----|-----|
| **Position** | Out-of-band (tap) | Inline |
| **Action** | Alert only | Alert + Block |
| **Risk** | Miss attacks | False positives block legit |
| **Performance impact** | Low | Medium-High |
| **Deployment** | Easy | Careful tuning needed |

### Trade-offs
- Default-deny firewall: secure nhưng tiêu tốn thời gian viết rules; luôn có 1 admin SSH rule trước khi apply
- IPS inline: block attacks nhưng false positives = service disruption; chạy detect mode trước 2-4 tuần
- VLAN segmentation: tốt nhưng không thay được micro-segmentation cho cloud/container environments
- Honeypots: detect attackers nhưng nếu attacker biết → tránh, hoặc dùng để fingerprint defenders

### Real-world Usage
```bash
# Security baseline check
# 1. Kiểm tra listening ports
ss -tulpn | grep -v "127.0.0.1\|::1"     # chỉ external listening services
netstat -tulpn                             # alternative

# 2. Kiểm tra iptables rules hiện tại
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v

# 3. Kiểm tra open connections
ss -tulpn state established                # established connections
lsof -i -P -n                             # files → network connections per process

# 4. Test firewall từ outside
nmap -sV -sC target.com                   # từ external machine
nmap -sU -p 53,67,68,161 target.com      # UDP ports

# 5. Check ARP cache poisoning
arp -n | awk '{print $1, $3}' | sort | uniq -d  # duplicate MACs

# 6. Monitor Suricata alerts real-time
tail -f /var/log/suricata/eve.json | jq -c 'select(.event_type=="alert") | {ts: .timestamp, alert: .alert.signature, src: .src_ip}'
```

### Ghi chú – Chủ đề tiếp theo
> Web Pentesting Deep – Burp Suite advanced, CSRF sâu, WebSockets attacks, CORS misconfiguration, HTTP Request Smuggling

---

*Cập nhật lần cuối: 2026-05-06*
