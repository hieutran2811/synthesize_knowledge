# Docker Networking – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Bridge Network Internals

### What – Bridge Network là gì ở mức kernel?
Docker bridge network dùng **Linux bridge** (`docker0`) kết hợp với **veth pairs** và **iptables NAT** để cung cấp networking cho containers.

### How – Cấu trúc vật lý

```
Host Network Stack:
┌────────────────────────────────────────────────────────────┐
│  Physical NIC (eth0): 10.0.0.100                           │
│                                                            │
│  docker0 bridge: 172.17.0.1/16                            │
│  ├── veth3a4b5c  ←──────────────── Container 1: eth0      │
│  │               (virtual cable)    172.17.0.2            │
│  └── veth6d7e8f  ←──────────────── Container 2: eth0     │
│                                     172.17.0.3            │
│                                                            │
│  iptables NAT:                                            │
│  MASQUERADE: 172.17.0.0/16 → eth0 (outgoing)            │
│  DNAT: 0.0.0.0:8080 → 172.17.0.2:80 (port mapping)     │
└────────────────────────────────────────────────────────────┘
```

### How – Tạo container network từ đầu (thủ công)

```bash
# Hiểu cơ chế Docker làm gì khi tạo container

# 1. Tạo network namespace
ip netns add container1

# 2. Tạo veth pair
ip link add veth-host type veth peer name eth0 netns container1

# 3. Cấu hình veth trên host, đưa vào bridge
ip link set veth-host up
ip link set veth-host master docker0

# 4. Cấu hình eth0 trong container namespace
ip netns exec container1 ip addr add 172.17.0.100/16 dev eth0
ip netns exec container1 ip link set eth0 up
ip netns exec container1 ip link set lo up
ip netns exec container1 ip route add default via 172.17.0.1

# 5. Kiểm tra connectivity
ip netns exec container1 ping 172.17.0.1   # ping host
ip netns exec container1 ping 8.8.8.8      # ping internet (qua NAT)
```

### How – Kiểm tra Bridge Network trên host

```bash
# Xem docker bridges
brctl show                           # legacy tool
bridge link                          # modern (iproute2)

# bridge link output:
# 10: veth3a4b5c@if9: <BROADCAST,MULTICAST,UP,LOWER_UP>
#     master docker0 state forwarding priority 32 cost 2

# Xem tất cả veth pairs
ip link show type veth

# Map veth host → container
# veth trong container có ifindex, veth trên host có peer ifindex
docker exec myapp cat /sys/class/net/eth0/ifindex    # → 9
# Tìm interface có iflink=9 trên host
ip link show | awk -F': ' '$1 == "10" {print}'       # → veth3a4b5c
# hoặc
for f in /sys/class/net/veth*/ifindex; do
  echo "$f: $(cat $f)"
done
```

---

## 2. iptables – Docker Rules

### How – Docker iptables Chains

```bash
# Docker tạo custom chains trong iptables

# Xem tất cả docker rules
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v

# ── FILTER table ──────────────────────────────────────────────
iptables -L DOCKER -n -v
# Chain DOCKER (policy DROP):
# target  prot  in          out      source   dest
# ACCEPT  tcp   !docker0    docker0  0.0.0.0  172.17.0.2  tcp dpt:80

iptables -L DOCKER-ISOLATION-STAGE-1 -n
# Ngăn cross-bridge traffic (container trên network A không nói với network B)

iptables -L DOCKER-USER -n
# Empty by default – user có thể thêm rules vào đây (persist qua docker restart)

# ── NAT table ─────────────────────────────────────────────────
iptables -t nat -L DOCKER -n -v
# DNAT: port mapping rules
# tcp dpt:8080 → 172.17.0.2:80 (port -p 8080:80)

iptables -t nat -L POSTROUTING -n -v
# MASQUERADE: outgoing traffic từ 172.17.0.0/16 → eth0 (NAT ra internet)
```

### How – Port Mapping qua iptables

```bash
# docker run -p 8080:80 nginx → iptables rules:

# NAT PREROUTING: incoming → DNAT
iptables -t nat -L PREROUTING -n | grep DOCKER
# DOCKER  all -- * * 0.0.0.0/0 0.0.0.0/0 ADDRTYPE match dst-type LOCAL

iptables -t nat -L DOCKER -n
# DNAT tcp -- !docker0 * 0.0.0.0/0 0.0.0.0/0 tcp dpt:8080 to:172.17.0.2:80

# FILTER DOCKER: allow established connections
iptables -L DOCKER -n
# ACCEPT tcp -- !docker0 docker0 0.0.0.0/0 172.17.0.2 tcp dpt:80

# Add custom iptables rules (persist qua Docker restart)
iptables -I DOCKER-USER -i eth0 -j DROP                # block all external
iptables -I DOCKER-USER -i eth0 -p tcp --dport 80 -j ACCEPT  # allow HTTP only
```

### How – nftables (Kernel 5.2+)

```bash
# Modern distros dùng nftables (docker vẫn chủ yếu dùng iptables-nft bridge)
nft list tables
nft list table ip filter
nft list ruleset | grep -A 5 "chain DOCKER"

# Daemon config để disable iptables (nếu tự quản lý)
# /etc/docker/daemon.json:
# { "iptables": false }
# Cảnh báo: khi tắt iptables, Docker không tự setup routing!
```

---

## 3. DNS Resolution Internals

### How – Embedded DNS Server

```bash
# Docker daemon chạy embedded DNS server tại 127.0.0.11:53
# Chỉ hoạt động trong user-defined networks (KHÔNG phải default bridge)

# Kiểm tra DNS trong container
docker run --rm --network mynet alpine sh -c "
  cat /etc/resolv.conf
  # nameserver 127.0.0.11
  # options ndots:0

  # Resolve service name
  nslookup web        # A record → IP của 'web' container
  nslookup tasks.web  # VIP → tất cả IPs của 'web' service (Swarm)
"

# DNS lookup flow:
# 1. Container query 127.0.0.11:53
# 2. Docker DNS check: is 'web' a known container/service?
# 3. YES: return container IP (hoặc VIP trong Swarm)
# 4. NO: forward đến upstream DNS (host's /etc/resolv.conf)

# Custom DNS
docker run --dns=8.8.8.8 --dns=8.8.4.4 myapp
docker run --dns-search=mycompany.internal myapp

# Compose
services:
  app:
    dns:
      - 8.8.8.8
    dns_search:
      - mycompany.internal
```

### How – Network Aliases & Round-Robin

```bash
# Multiple containers với cùng alias → DNS round-robin
docker run -d --name db1 --network mynet \
  --network-alias database postgres:16

docker run -d --name db2 --network mynet \
  --network-alias database postgres:16

# Lookup 'database' → trả về 2 IPs (round-robin order thay đổi)
docker run --rm --network mynet alpine sh -c "
  for i in 1 2 3 4; do
    nslookup database 2>/dev/null | grep Address | tail -n+2
  done
"
# Address: 172.20.0.3   (db1)
# Address: 172.20.0.4   (db2)
# Address: 172.20.0.4   (db2)
# Address: 172.20.0.3   (db1)
```

---

## 4. Overlay Network – VXLAN Internals

### What – Overlay Network là gì?
**Overlay network** cho phép containers trên các Docker hosts khác nhau giao tiếp như trong cùng 1 LAN, bằng cách đóng gói traffic trong **VXLAN tunnels**.

### How – VXLAN Architecture

```
Host 1 (10.0.0.1):              Host 2 (10.0.0.2):
┌──────────────────┐             ┌──────────────────┐
│ Container A      │             │ Container B       │
│ 10.0.0.100       │             │ 10.0.0.101        │
│     ↓ eth0       │             │     ↓ eth0        │
│ vxlan0 (VTEP)   │──UDP:4789──▶│ vxlan0 (VTEP)    │
│ 10.0.0.1        │  VXLAN ID   │ 10.0.0.2          │
│     ↓ eth0      │   (VNI)     │     ↓ eth0        │
└──────────────────┘             └──────────────────┘
     Outer packet:                    Outer packet:
     src: 10.0.0.1:random            dst: 10.0.0.2:4789
     Inner packet:
     src: 10.0.0.100                 dst: 10.0.0.101

VTEP = VXLAN Tunnel Endpoint (vxlan0 interface)
VNI  = VXLAN Network Identifier (24-bit = 16M networks)
```

### How – Overlay Network Setup

```bash
# Cần Swarm mode để dùng overlay
docker swarm init --advertise-addr 10.0.0.1   # Host 1
docker swarm join --token ... 10.0.0.1:2377   # Host 2

# Tạo overlay network
docker network create \
  --driver overlay \
  --subnet 10.10.0.0/16 \
  --gateway 10.10.0.1 \
  myoverlay

# Attachable: cho phép standalone containers join
docker network create --driver overlay --attachable myoverlay

# Inspect overlay network
docker network inspect myoverlay | jq '.[0].IPAM'

# Xem VXLAN interface trên host
ip link show type vxlan
# vx-000000009a: <BROADCAST,MULTICAST,UP,LOWER_UP> ...

# Xem FDB (Forwarding Database) – MAC → VTEP mapping
bridge fdb show dev vx-000000009a
# 02:42:0a:0a:00:03 dst 10.0.0.2 self permanent
# (MAC của container trên Host 2 → IP của Host 2 VTEP)
```

### How – Packet Flow (Overlay)

```
Container A (10.10.0.2) → ping → Container B (10.10.0.3):

1. Container A gửi ARP: "ai có 10.10.0.3?"
2. Docker VTEP trả lời (từ distributed store = gossip protocol)
3. Container A gửi Ethernet frame:
   [eth header: src=MAC-A, dst=MAC-B]
   [IP: src=10.10.0.2, dst=10.10.0.3]
4. VTEP trên Host 1 nhận frame:
   - Lookup MAC-B → Host 2's VTEP (10.0.0.2)
   - Đóng gói VXLAN: UDP packet
     [outer: src=10.0.0.1, dst=10.0.0.2, port=4789]
     [VXLAN header: VNI=xxx]
     [inner: original Ethernet frame]
5. Gửi qua physical network
6. VTEP trên Host 2 nhận UDP packet:
   - Decapsulate VXLAN
   - Deliver frame đến Container B
```

---

## 5. macvlan & ipvlan

### What – macvlan là gì?
**macvlan** cho phép container có **MAC address riêng**, xuất hiện như physical device trên network. Tốt cho legacy apps cần IP riêng trên subnet của host.

### How – macvlan Setup

```bash
# Chế độ bridge (phổ biến nhất)
docker network create \
  --driver macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  --opt parent=eth0 \              # physical interface
  macvlan-net

# Chạy container với IP cụ thể
docker run -d \
  --network macvlan-net \
  --ip 192.168.1.200 \
  nginx

# Container bây giờ có IP 192.168.1.200 trên subnet 192.168.1.0/24
# Accessible từ bất kỳ máy nào trên mạng LAN

# VẤN ĐỀ: host không nói chuyện được với container (macvlan limitation)
# GIẢI PHÁP: tạo macvlan interface trên host
ip link add macvlan-shim link eth0 type macvlan mode bridge
ip addr add 192.168.1.250/32 dev macvlan-shim    # IP cho host trên subnet này
ip link set macvlan-shim up
ip route add 192.168.1.200/32 dev macvlan-shim   # route đến container IP

# 802.1q VLAN trunk (nhiều VLANs)
docker network create \
  --driver macvlan \
  --subnet=192.168.10.0/24 \
  --gateway=192.168.10.1 \
  --opt parent=eth0.10 \           # VLAN 10
  macvlan-vlan10
```

### How – ipvlan

```bash
# ipvlan L2: tương tự macvlan nhưng share MAC của host
# Tốt khi switch không cho phép nhiều MACs per port
docker network create \
  --driver ipvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  --opt parent=eth0 \
  --opt ipvlan_mode=l2 \
  ipvlan-net

# ipvlan L3: routing mode (không cần gateway, host làm router)
docker network create \
  --driver ipvlan \
  --subnet=192.168.200.0/24 \
  --opt parent=eth0 \
  --opt ipvlan_mode=l3 \
  ipvlan-l3-net
```

### Compare – Network Drivers (Chi tiết)

| | bridge | host | overlay | macvlan | ipvlan |
|--|--------|------|---------|---------|--------|
| Multi-host | ❌ | ❌ | ✅ | ❌ | ❌ |
| Isolation | NAT | None | Network NS | None | None |
| Direct LAN IP | ❌ | ✅ | ❌ | ✅ | ✅ |
| Promiscuous mode | ❌ | ❌ | ❌ | Cần | ❌ |
| Multiple MACs | ❌ | ❌ | ❌ | ✅ | ❌ |
| Performance | Good | Best | VXLAN overhead | Best | Best |

---

## 6. Network Troubleshooting

### How – Công cụ debug network

```bash
# nicolaka/netshoot: Swiss army knife cho network debug
docker run -it --rm \
  --network container:myapp \
  nicolaka/netshoot

# Trong netshoot container (cùng network namespace với myapp):
# tcpdump, curl, dig, nmap, iperf3, ss, ip, netstat, traceroute, mtr...

# ── DNS Debug ─────────────────────────────────────────────────
docker exec myapp nslookup backend
docker exec myapp dig backend @127.0.0.11 +short

# ── Connectivity ──────────────────────────────────────────────
docker exec myapp curl -v http://backend:8080/health
docker exec myapp nc -zv backend 5432     # test TCP port
docker exec myapp timeout 3 bash -c 'cat < /dev/tcp/backend/5432 && echo open'

# ── Packet capture ────────────────────────────────────────────
# Capture trên veth (host side)
VETH=$(ip link show type veth | grep -B1 "$(docker inspect --format '{{.State.Pid}}' myapp)" | head -1 | cut -d: -f2 | tr -d ' ')
tcpdump -i $VETH -nn -w /tmp/cap.pcap

# Capture trong container
docker run --rm -it \
  --net container:myapp \
  --cap-add NET_ADMIN \
  kaazing/tcpdump tcpdump -i eth0 -nn port 80

# ── iptables debug ────────────────────────────────────────────
iptables -t nat -L -n -v | grep 8080     # xem port mapping rule
iptables -L DOCKER-USER -n -v            # custom rules

# Trace packet path (requires iptables-trace)
iptables -t raw -A PREROUTING -p tcp --dport 8080 -j TRACE
iptables -t raw -A OUTPUT -p tcp --sport 8080 -j TRACE
# Xem trong /var/log/kern.log hoặc dmesg

# ── Bandwidth test ────────────────────────────────────────────
# Server (trong container A)
docker exec -d app-a iperf3 -s
# Client (trong container B)
docker exec app-b iperf3 -c app-a -t 10
```

### How – Common Issues & Solutions

```bash
# Issue 1: Container không thể resolve DNS
# Kiểm tra: đang dùng default bridge network (không có DNS)
docker inspect myapp | jq '.[0].NetworkSettings.Networks'
# → "bridge": { ... }  ← default bridge, không có DNS!
# Giải pháp: tạo user-defined network
docker network create mynet
docker run --network mynet ...

# Issue 2: Container không ra được internet
# Kiểm tra iptables FORWARD
iptables -L FORWARD -n | grep DROP
# Giải pháp: đảm bảo ip_forward bật
cat /proc/sys/net/ipv4/ip_forward  # phải là 1
echo 1 > /proc/sys/net/ipv4/ip_forward  # tạm thời
sysctl -w net.ipv4.ip_forward=1    # persistent

# Kiểm tra NAT rule tồn tại
iptables -t nat -L POSTROUTING -n | grep MASQUERADE

# Issue 3: Port không accessible từ ngoài
# Kiểm tra container đang listen trên đúng interface
docker exec myapp ss -tlnp
# → 127.0.0.1:8080 ← chỉ localhost! cần 0.0.0.0:8080
# Fix trong app: bind to 0.0.0.0, không phải localhost

# Kiểm tra iptables DOCKER chain
iptables -L DOCKER -n

# Issue 4: Containers cùng network không nói chuyện được
docker exec app1 ping app2          # failed
# Kiểm tra cùng network không
docker inspect app1 | jq '.[0].NetworkSettings.Networks | keys'
docker inspect app2 | jq '.[0].NetworkSettings.Networks | keys'
# Giải pháp: connect cả 2 vào cùng network
docker network connect mynet app1
docker network connect mynet app2
```

### Trade-offs
- iptables-based networking: mature nhưng stateful, complex với nhiều rules
- VXLAN overlay: flexible multi-host nhưng MTU issues (cần MSS clamping), UDP overhead
- macvlan: direct LAN access nhưng cần promiscuous mode, host isolation issue
- Overlay vs Calico/Cilium (K8s): Docker overlay đơn giản nhưng ít tính năng (no NetworkPolicy, no eBPF)

### Real-world Usage
```bash
# Production: verify container network setup
docker network inspect $(docker inspect --format '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}' myapp) \
  | jq '.[0] | {name: .Name, subnet: .IPAM.Config[0].Subnet, containers: [.Containers[] | {name: .Name, ip: .IPv4Address}]}'

# Simulate network issues (chaos engineering)
docker exec myapp tc qdisc add dev eth0 root netem delay 100ms  # thêm 100ms latency
docker exec myapp tc qdisc add dev eth0 root netem loss 10%     # 10% packet loss
docker exec myapp tc qdisc del dev eth0 root                    # xóa

# MTU troubleshooting (thường gặp với overlay/VPN)
docker exec myapp ping -M do -s 1472 gateway  # test MTU 1500 (1472 + 28 header)
docker exec myapp ping -M do -s 1400 gateway  # overlay MTU thường ~1450
```

### Ghi chú – Chủ đề tiếp theo
> Compose Patterns – local dev, testing, staging environments, wait-for scripts

---

*Cập nhật lần cuối: 2026-05-06*
