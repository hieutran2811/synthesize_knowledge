# Networking Deep Dive – Linux

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. tcpdump – Packet Capture

### What – tcpdump là gì?
`tcpdump` là command-line packet analyzer, capture và phân tích **network packets** ở kernel level. Công cụ thiết yếu cho network debugging, security analysis.

### How – Cú pháp cơ bản

```bash
# Capture trên interface
tcpdump -i eth0                      # mặc định: verbose packets
tcpdump -i any                       # tất cả interfaces
tcpdump -i lo                        # loopback

# Output control
tcpdump -n                           # không resolve hostname
tcpdump -nn                          # không resolve hostname VÀ port names
tcpdump -v                           # verbose
tcpdump -vv                          # more verbose
tcpdump -q                           # quiet (ít output)
tcpdump -X                           # hex + ASCII dump
tcpdump -xx                          # ethernet header + hex + ASCII

# Giới hạn packets
tcpdump -c 100                       # chỉ capture 100 packets
tcpdump -A                           # ASCII only (useful cho HTTP)
```

### How – BPF Filters (Berkeley Packet Filter)

```bash
# Filter theo host
tcpdump host 192.168.1.100           # src hoặc dst
tcpdump src host 192.168.1.100       # chỉ src
tcpdump dst host 192.168.1.100       # chỉ dst

# Filter theo port
tcpdump port 80                      # HTTP
tcpdump port 80 or port 443         # HTTP + HTTPS
tcpdump portrange 8000-9000         # range
tcpdump not port 22                  # exclude SSH

# Filter theo protocol
tcpdump tcp                          # TCP only
tcpdump udp                          # UDP only
tcpdump icmp                         # ICMP (ping)
tcpdump arp                          # ARP

# Combinations
tcpdump host 192.168.1.100 and port 80
tcpdump '(tcp port 80 or tcp port 443) and host google.com'
tcpdump 'tcp[tcpflags] & (tcp-syn) != 0'  # chỉ SYN packets

# Filter theo network
tcpdump net 192.168.1.0/24
tcpdump src net 10.0.0.0/8

# Filter theo packet size
tcpdump greater 1000                 # packets > 1000 bytes
tcpdump less 100                     # packets < 100 bytes
```

### How – Save và Read Captures

```bash
# Ghi vào file (pcap format)
tcpdump -i eth0 -w capture.pcap
tcpdump -i eth0 -w capture.pcap -C 100  # rotate mỗi 100MB
tcpdump -i eth0 -w capture_%Y%m%d_%H%M%S.pcap  # timestamp filename

# Đọc từ file
tcpdump -r capture.pcap
tcpdump -r capture.pcap -n port 80   # read + filter

# Wireshark
wireshark capture.pcap               # GUI analysis
tshark -r capture.pcap               # command-line wireshark
```

### Real-world: Debug HTTP

```bash
# Xem HTTP requests/responses
tcpdump -i eth0 -A -s 0 'tcp port 80' | grep -A 20 'GET\|POST\|HTTP/1'

# Xem DNS queries
tcpdump -i eth0 -nn udp port 53

# Debug TLS handshake
tcpdump -i eth0 -nn 'tcp port 443 and (tcp[13] & 0x02 != 0)'  # SYN packets đến 443

# Capture và phân tích ngay
tcpdump -i eth0 -nn -q port 80 | awk '{print $3}' | sort | uniq -c | sort -rn
```

---

## 2. iptables – Packet Filtering (Legacy)

### What – iptables là gì?
`iptables` là userspace tool để cấu hình **Netfilter** – Linux kernel packet filtering framework. Dùng để firewall, NAT, packet marking.

### How – Kiến trúc Tables & Chains

```
Tables:
  filter  – packet filtering (ACCEPT/DROP) [DEFAULT]
  nat     – Network Address Translation
  mangle  – packet modification
  raw     – skip connection tracking
  security – SELinux/secmark

Chains (per table):
  filter:  INPUT (đến host), OUTPUT (từ host), FORWARD (qua host)
  nat:     PREROUTING, OUTPUT, POSTROUTING
  mangle:  PREROUTING, INPUT, FORWARD, OUTPUT, POSTROUTING

Packet flow:
  Incoming → PREROUTING → (route) → FORWARD → POSTROUTING → out
                        ↘ INPUT → local process → OUTPUT → POSTROUTING → out
```

### How – iptables Commands

```bash
# Xem rules
iptables -L                          # list filter table
iptables -L -n                       # không resolve
iptables -L -v                       # verbose (packet counts)
iptables -L INPUT -n --line-numbers  # show line numbers
iptables -t nat -L                   # NAT table
iptables -t nat -L -n -v

# Thêm rule
iptables -A INPUT -p tcp --dport 22 -j ACCEPT        # append (cuối chain)
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT      # insert (đầu chain)
iptables -A INPUT -s 192.168.1.0/24 -j ACCEPT        # allow subnet
iptables -A INPUT -i lo -j ACCEPT                     # allow loopback
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT  # stateful

# Xóa rule
iptables -D INPUT -p tcp --dport 22 -j ACCEPT        # delete by spec
iptables -D INPUT 3                                   # delete by line number
iptables -F INPUT                                     # flush chain
iptables -F                                           # flush tất cả chains

# Set default policy
iptables -P INPUT DROP               # default DROP (whitelist mode)
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

# Save & Restore
iptables-save > /etc/iptables/rules.v4   # save
iptables-restore < /etc/iptables/rules.v4  # restore
# Ubuntu: apt install iptables-persistent
```

### How – NAT Rules

```bash
# MASQUERADE (outbound NAT, dynamic IP)
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# SNAT (static source IP)
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -j SNAT --to-source 203.0.113.10

# DNAT (port forwarding)
# Forward port 8080 trên host đến 192.168.1.100:80
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.100:80
iptables -A FORWARD -p tcp -d 192.168.1.100 --dport 80 -j ACCEPT

# Enable IP forwarding (cần cho routing/NAT)
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1
```

---

## 3. nftables – Modern Firewall

### What – nftables là gì?
`nftables` thay thế iptables/ip6tables/arptables/ebtables với một framework thống nhất. Default trên Debian 10+, RHEL 8+, Ubuntu 20.04+.

### How – nftables Concepts

```
Tables → Families:
  ip    – IPv4
  ip6   – IPv6
  inet  – IPv4 + IPv6 (cùng rules)
  arp   – ARP
  bridge – bridge (layer 2)
  netdev – ingress/egress per device

Chains (types):
  filter  – packet filtering
  nat     – NAT
  route   – policy routing
```

### How – nftables Commands

```bash
# nft command
nft list ruleset                     # xem tất cả rules
nft list tables                      # list tables
nft list table inet filter           # xem table cụ thể

# Tạo table và chain
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
nft add chain inet filter forward { type filter hook forward priority 0 \; policy drop \; }

# Thêm rules
nft add rule inet filter input iif lo accept                          # loopback
nft add rule inet filter input ct state established,related accept    # stateful
nft add rule inet filter input tcp dport 22 accept                    # SSH
nft add rule inet filter input tcp dport { 80, 443 } accept          # HTTP/HTTPS
nft add rule inet filter input ip saddr 192.168.1.0/24 accept        # allow subnet
nft add rule inet filter input drop                                    # default drop

# Delete rule
nft delete rule inet filter input handle 5    # xóa bằng handle (từ nft list)

# Config file
cat /etc/nftables.conf
nft -f /etc/nftables.conf           # load từ file
systemctl enable nftables

# Flush
nft flush ruleset                   # xóa tất cả
```

### How – nftables Production Config

```nft
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Loopback
        iif "lo" accept

        # Established connections
        ct state { established, related } accept
        ct state invalid drop

        # ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH (rate-limit)
        tcp dport 22 ct state new limit rate 10/minute accept

        # Web
        tcp dport { 80, 443 } accept

        # Log dropped packets
        log prefix "nftables-drop: " flags all counter drop
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }
}

table inet nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
    }
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "eth0" masquerade
    }
}
```

---

## 4. Netfilter & Connection Tracking

### What – Netfilter là gì?
**Netfilter** là Linux kernel framework xử lý tất cả network operations. iptables/nftables chỉ là userspace interfaces để cấu hình Netfilter.

### How – Connection Tracking (conntrack)

```bash
# conntrack – theo dõi network connections
apt install conntrack

# Xem connections hiện tại
conntrack -L                          # list all tracked connections
conntrack -L -p tcp                   # chỉ TCP
conntrack -L | grep ESTABLISHED      # established connections
conntrack -L | wc -l                  # tổng số connections

# Count connections per state
conntrack -L -p tcp | awk '{print $4}' | sort | uniq -c | sort -rn

# Delete connection
conntrack -D -p tcp --src 192.168.1.100 --dport 80

# Stats
conntrack -S                          # connection tracking statistics
cat /proc/sys/net/netfilter/nf_conntrack_count   # current tracked connections
cat /proc/sys/net/netfilter/nf_conntrack_max     # max allowed

# Tuning
sysctl net.netfilter.nf_conntrack_max=524288
sysctl net.netfilter.nf_conntrack_tcp_timeout_established=86400
```

### How – Connection States

```
NEW         – packet không thuộc connection nào đã biết
ESTABLISHED – connection đã được thiết lập (cả 2 chiều đã giao tiếp)
RELATED     – connection liên quan (FTP data, ICMP error)
INVALID     – packet không match bất kỳ state nào (drop it!)
UNTRACKED   – marked bởi raw table (skip tracking)
```

---

## 5. Advanced Network Configuration

### How – ip command Deep Dive

```bash
# Network namespaces (xem cả namespace section)
ip netns add vnet1
ip netns exec vnet1 bash

# Virtual ethernet pairs (veth) – dùng bởi Docker
ip link add veth0 type veth peer name veth1
ip link set veth1 netns container_ns
ip addr add 10.0.0.1/24 dev veth0
ip link set veth0 up

# Bridge networking
ip link add br0 type bridge
ip link set eth0 master br0
ip link set br0 up

# VLAN
ip link add link eth0 name eth0.100 type vlan id 100
ip addr add 192.168.100.1/24 dev eth0.100
ip link set eth0.100 up

# Routing
ip route show
ip route add 10.0.0.0/8 via 192.168.1.1   # static route
ip route add default via 192.168.1.1        # default gateway
ip route del 10.0.0.0/8                    # delete route
ip route get 8.8.8.8                        # which route would be used

# Policy routing (multiple routing tables)
ip rule list                                # routing policy rules
ip rule add from 192.168.2.0/24 table 200  # use table 200 for subnet
ip route add default via 10.0.0.1 table 200
```

### How – ss – Socket Statistics

```bash
# ss – modern netstat replacement
ss -tlnp                             # TCP listening + process
ss -tulnp                            # TCP + UDP listening
ss -tnp                              # TCP established + process
ss -s                                # statistics summary
ss -i                                # internal TCP info (RTT, congestion window)
ss -e                                # extended socket info
ss -m                                # memory usage per socket

# Filter
ss -tnp state established            # chỉ ESTABLISHED
ss -tnp state listening              # chỉ LISTENING
ss dport = :80                       # destination port 80
ss sport = :22                       # source port 22
ss -tnp '( dport = :http or dport = :https )'

# Xem timer info
ss -to                               # timer info (retransmit, keepalive)

# TCP states
# ESTABLISHED  SYN-SENT  SYN-RECV  FIN-WAIT-1  FIN-WAIT-2
# TIME-WAIT    CLOSED    CLOSE-WAIT LAST-ACK    LISTEN  CLOSING
```

### How – Network Performance

```bash
# iperf3 – bandwidth testing
# Server mode:
iperf3 -s

# Client mode:
iperf3 -c server_ip                  # test TCP bandwidth
iperf3 -c server_ip -u -b 100M      # UDP test, 100Mbps
iperf3 -c server_ip -t 30            # 30 second test
iperf3 -c server_ip -P 4             # 4 parallel streams

# iftop – real-time bandwidth per connection
iftop -i eth0                         # interactive
iftop -i eth0 -n                      # no hostname resolution

# nethogs – bandwidth per process
nethogs eth0

# nload – bandwidth graphs per interface
nload eth0
```

---

## 6. VPN Basics – WireGuard

### What – VPN trong Linux
Linux hỗ trợ nhiều VPN protocols: OpenVPN, WireGuard, IPsec (strongSwan). WireGuard là modern, fast, minimal.

### How – WireGuard Setup

```bash
# Cài đặt
apt install wireguard

# Generate keys
wg genkey | tee privatekey | wg pubkey > publickey

# Server config (/etc/wireguard/wg0.conf)
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <server_private_key>
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <client_public_key>
AllowedIPs = 10.0.0.2/32
EOF

# Start WireGuard
wg-quick up wg0
systemctl enable wg-quick@wg0

# Client config
cat > /etc/wireguard/wg0.conf << 'EOF'
[Interface]
Address = 10.0.0.2/24
PrivateKey = <client_private_key>
DNS = 1.1.1.1

[Peer]
PublicKey = <server_public_key>
Endpoint = server.example.com:51820
AllowedIPs = 0.0.0.0/0   # route all traffic through VPN
PersistentKeepalive = 25
EOF

wg-quick up wg0

# Status
wg show                             # WireGuard status
```

---

## 7. Network Debugging Workflow

### How – Systematic Debug Approach

```bash
# 1. Kiểm tra interface
ip addr show                        # interface có up không? có IP không?
ip link show                        # link state (UP/DOWN)
ethtool eth0                        # NIC info, speed, duplex

# 2. Kiểm tra routing
ip route show                       # default gateway có không?
ip route get 8.8.8.8               # route đến target

# 3. Kiểm tra connectivity layer by layer
ping 192.168.1.1                    # gateway reachable?
ping 8.8.8.8                        # internet IP reachable?
ping google.com                     # DNS working?

# 4. DNS debugging
dig google.com                      # DNS query
dig @8.8.8.8 google.com            # bypass local DNS
systemd-resolve --status            # local resolver config
cat /etc/resolv.conf                # DNS configuration

# 5. Port connectivity
nc -zv target.host 80              # TCP port check
curl -v http://target.host         # full HTTP debug

# 6. Packet capture
tcpdump -i eth0 host target.host   # capture traffic to target
```

### Real-world: Production Network Issues

```bash
# High connection count
ss -tnp | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10

# TIME_WAIT buildup (common issue)
ss -s | grep -i time-wait
# Fix: tune kernel params
sysctl -w net.ipv4.tcp_fin_timeout=15
sysctl -w net.ipv4.tcp_tw_reuse=1

# Find process leaking connections
ss -tnp | grep myapp | wc -l
strace -e trace=network -p $(pgrep myapp)

# DDoS detection
tcpdump -i eth0 -nn -q 'tcp[tcpflags] = tcp-syn' | \
    awk '{print $3}' | cut -d. -f1-4 | sort | uniq -c | sort -rn | head -20

# Network latency analysis
ping -c 100 -i 0.2 8.8.8.8 | tail -2   # average, min, max latency
mtr --report google.com                 # hop-by-hop latency
```

---

## 8. Compare & Trade-offs

### Compare – iptables vs nftables vs ufw

| | iptables | nftables | ufw |
|--|----------|----------|-----|
| Status | Legacy (maintained) | Modern default | Frontend for iptables/nf |
| Syntax | Verbose, complex | Cleaner | Simplified |
| IPv6 | ip6tables riêng | Unified (inet family) | Auto handles |
| Performance | Good | Better (set operations) | Same as backend |
| Scripting | Trung bình | Tốt | Ít flexible |
| Khi dùng | Cũ, cần tương thích | Mới, complex rules | Simple server |

### Trade-offs

- **tcpdump**: cực mạnh nhưng cần quyền root; capture nhiều ảnh hưởng performance
- **conntrack**: cần thiết cho stateful firewall nhưng có limits (nf_conntrack overflow là vấn đề production phổ biến)
- **WireGuard vs OpenVPN**: WireGuard nhanh hơn, đơn giản hơn, nhưng ít audited hơn; OpenVPN mature hơn, feature-rich hơn

---

### Ghi chú – Chủ đề tiếp theo
> **11.5 Disk & Storage Deep Dive**: LVM (PV/VG/LV), RAID levels, NFS/CIFS mount, ZFS basics
