# Roadmap Tổng Hợp Kiến Thức Bảo Mật & Tấn Công

## Cấu trúc thư mục
```
security/
├── roadmap.md                          ← file này
├── security_knowledge.md              ← overview tổng quan (10 topics)
├── network/                            ← Network Security deep dive
│   ├── network_attacks.md             ← ARP/DNS spoofing, Wireshark, MITM lab
│   └── network_defense.md            ← Firewall rules, IDS/IPS, network hardening
├── web/                                ← Web Security deep dive
│   ├── owasp_top10.md                 ← OWASP Top 10 chi tiết từng loại
│   ├── web_testing.md                 ← Burp Suite, manual testing methodology
│   └── api_security.md               ← REST API, GraphQL, JWT, OAuth 2.0 attacks
├── crypto/                             ← Cryptography deep dive
│   ├── crypto_fundamentals.md        ← Symmetric, Asymmetric, Hashing, TLS
│   └── pki_tls.md                    ← PKI, Certificate Authority, TLS handshake
├── active_directory/                   ← Active Directory Security
│   └── ad_attacks.md                 ← Kerberoasting, Pass-the-Hash, BloodHound
├── cloud/                              ← Cloud Security deep dive
│   ├── aws_security.md               ← IAM, S3, EC2, Lambda security
│   └── cloud_misconfig.md            ← Common misconfigurations, tools
├── malware/                            ← Malware & Forensics
│   ├── malware_analysis.md           ← Static/Dynamic analysis, sandbox
│   └── incident_response.md         ← IR playbook, forensics, DFIR
├── devsecops/                          ← DevSecOps
│   └── devsecops_pipeline.md        ← SAST, DAST, SCA, secret scanning
└── ctf/                                ← CTF Techniques
    └── ctf_techniques.md             ← CTF categories, common patterns, tools
```

---

## Mục lục đã hoàn thành ✅

### Tổng quan (Overview)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Security Fundamentals – CIA Triad, STRIDE, Threat Modeling, Hacker Taxonomy, Pentest Phases | security_knowledge.md | ✅ |
| 2 | Network Attacks – Nmap recon, ARP poisoning MITM, DNS attacks, DoS/DDoS | security_knowledge.md | ✅ |
| 3 | Web Attacks (OWASP Top 10) – SQLi, XSS, IDOR, SSRF, Auth failures, Injection | security_knowledge.md | ✅ |
| 4 | Authentication & Session Security – JWT attacks, OAuth 2.0 attacks, brute force | security_knowledge.md | ✅ |
| 5 | Cryptography – Symmetric/Asymmetric, Hashing, TLS vulnerabilities, Certificate Pinning | security_knowledge.md | ✅ |
| 6 | Privilege Escalation – Linux (SUID, sudo, cron), Windows (service, token impersonation) | security_knowledge.md | ✅ |
| 7 | Web Application Pentesting – Burp Suite workflow, Command Injection, LFI/RFI, directory brute force | security_knowledge.md | ✅ |
| 8 | Infrastructure & Cloud Security – Linux hardening, AWS IAM, S3, GuardDuty | security_knowledge.md | ✅ |
| 9 | Defensive Security – SOC/SIEM, MITRE ATT&CK, Incident Response, Forensics | security_knowledge.md | ✅ |
| 10 | DevSecOps Pipeline – SAST/DAST/SCA, secret scanning, container scanning | security_knowledge.md | ✅ |

---

## Chủ đề tiếp theo ⬜

### Network Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 11.1 | Network Attacks Deep – Wireshark analysis, Responder (LLMNR), WPA2 cracking, Metasploit, port scan evasion | network/network_attacks.md | ✅ |
| 11.2 | Network Defense Deep – iptables/nftables rules, Snort/Suricata IDS, network segmentation, Zero Trust | network/network_defense.md | ✅ |

### Web Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 12.1 | OWASP Top 10 Deep – SQLi types, NoSQL injection, SSTI, Race Condition, Mass Assignment, deserialization | web/owasp_top10.md | ✅ |
| 12.2 | Web Pentesting Deep – Burp Suite advanced, CSRF deep, deserialization, SSTI, WebSockets | web/web_testing.md | ✅ |
| 12.3 | API Security – REST API attacks, GraphQL introspection/injection, JWT/OAuth2 deep, API rate limiting | web/api_security.md | ✅ |

### Cryptography Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | Crypto Fundamentals – Block/stream ciphers, padding oracle, ECB mode attacks, Diffie-Hellman | crypto/crypto_fundamentals.md | ✅ |
| 13.2 | PKI & TLS – Certificate chain, CA attacks, HSTS, certificate transparency, mutual TLS | crypto/pki_tls.md | ✅ |

### Active Directory Security
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14.1 | AD Attacks – Kerberoasting, AS-REP Roasting, Pass-the-Hash, DCSync, Golden/Silver Ticket, BloodHound | active_directory/ad_attacks.md | ✅ |

### Cloud Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 15.1 | AWS Security Deep – IAM privilege escalation, IMDS attack, Lambda security, GuardDuty, ScoutSuite | cloud/aws_security.md | ✅ |
| 15.2 | Cloud Misconfigurations – S3 public buckets, exposed metadata service, insecure SGs, GCP/Azure | cloud/cloud_misconfig.md | ✅ |

### Malware & Forensics
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 16.1 | Malware Analysis – Static (strings, PE headers), Dynamic (sandbox), Reverse engineering basics | malware/malware_analysis.md | ✅ |
| 16.2 | Incident Response – IR playbook, memory forensics (Volatility), disk forensics, log analysis | malware/incident_response.md | ✅ |

### DevSecOps Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 17.1 | DevSecOps Pipeline – Semgrep custom rules, OWASP ZAP, SBOM, secret scanning, IaC security | devsecops/devsecops_pipeline.md | ✅ |

### CTF Techniques
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 18.1 | CTF Techniques – Web, Crypto, Forensics, Pwn (Buffer Overflow), Reverse Engineering patterns | ctf/ctf_techniques.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã có nội dung
- 🔄 Đang làm
- ⬜ Chưa làm

## Certifications Reference
| Cert | Level | Focus |
|------|-------|-------|
| CompTIA Security+ | Entry | General security fundamentals |
| CEH (Certified Ethical Hacker) | Intermediate | Hacking methodology |
| OSCP (Offensive Security) | Advanced | Hands-on penetration testing |
| GPEN / GWAPT | Advanced | GIAC pentest / web app |
| CISSP | Management | Security management, governance |
| AWS Security Specialty | Cloud | AWS-specific security |
