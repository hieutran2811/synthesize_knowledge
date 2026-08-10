---
title: "Network Observability & Traffic Analysis – Từ DNS đến Packet và Business Impact"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 9
---
# Network Observability & Traffic Analysis – Từ DNS đến Packet và Business Impact

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là phân rã một kết nối qua name resolution, routing, transport,
> encryption, proxy/load balancer và application; chọn đúng metric, flow, trace, probe hoặc
> packet evidence để khoanh vùng sự cố.
>
> Baseline tham chiếu: OpenTelemetry Semantic Conventions 1.43, Prometheus Blackbox Exporter
> 0.28, tài liệu Cilium/Hubble 1.20 hiện hành và các RFC chuẩn cho TCP, TLS 1.3, QUIC, HTTP/3.
> Metric/attribute ở trạng thái Development cần pin schema và migration plan.
>
> Network telemetry có thể lộ topology, IP, hostname, domain, SNI, URL, identity và traffic
> pattern. Không capture payload/PCAP rộng, giải mã TLS hoặc bật debug production khi chưa có
> authorization, minimization, encryption, retention và access audit.
>
> Nên đọc trước:
> [API & HTTP Observability](api_http_observability.md),
> [eBPF Observability](ebpf_observability.md),
> [Kubernetes Observability](kubernetes_observability.md) và
> [Security Observability](security_observability_detection_engineering.md).

---

## 1. Vì sao network observability khó?

“Network chậm” có thể là:

- DNS;
- route;
- packet loss/retransmission;
- SYN/accept queue;
- TLS;
- proxy/load balancer;
- connection pool;
- server processing;
- downstream.

Một request đi qua nhiều hop và mỗi phía nhìn thấy khác nhau. Không có một metric duy nhất
chứng minh network là root cause.

## 2. Mô hình nhiều lớp

```text
L7  HTTP/gRPC/DNS/application
L6  TLS/encryption
L4  TCP/UDP/QUIC
L3  IP/routing/ICMP
L2  Ethernet/VLAN/ARP-NDP
L1  link/physical
```

Cloud/Kubernetes thêm overlay, NAT, service, sidecar, gateway và managed load balancer. Luôn
ghi rõ layer và vantage point của tín hiệu.

## 3. Bốn câu hỏi điều tra

1. **Reachability**: có đường đi không?
2. **Correctness**: có đến đúng endpoint/protocol/certificate không?
3. **Performance**: delay/loss/saturation ở đâu?
4. **Security/policy**: traffic có được phép và có đáng tin không?

Ping thành công chỉ trả lời một phần reachability ICMP; không chứng minh TCP port, TLS hay
application hoạt động.

## 4. Nguồn telemetry

| Nguồn | Thế mạnh | Giới hạn |
|---|---|---|
| Interface/device metric | saturation/error | ít context request |
| Flow log | ai nói với ai, volume | không payload/latency đầy đủ |
| Trace | request critical path | cần instrumentation/context |
| Synthetic probe | outside-in | sample, không đại diện mọi user |
| Packet capture | evidence chi tiết | nhạy cảm, tốn chi phí |
| eBPF/socket | kernel/process context | privilege/overhead/coverage |
| App/proxy log | semantic L7 | chỉ thấy hop của nó |

Kết hợp, không chọn một nguồn cho mọi câu hỏi.

## 5. Identity contract

Network identity:

```text
environment/region/zone
cluster/node
namespace/workload/service
cloud resource
source/destination
direction
protocol
vantage point
```

IP và port không phải identity bền vững. NAT, autoscaling, pod churn và proxy làm cùng IP đại
diện nhiều actor hoặc một service có nhiều IP.

## 6. Vantage point

Một flow có thể được quan sát tại:

- client process/host;
- node NIC;
- CNI/overlay;
- sidecar;
- gateway/load balancer;
- firewall/NAT;
- server host/process.

Ghi `observer` và direction. “Source IP” ở load balancer có thể là proxy, còn app lấy client
address từ trusted forwarding metadata.

## 7. Network SLI và SLO

SLI:

```text
connect success ratio
DNS success/latency
TCP connect latency
TLS handshake latency
packet loss/retransmission
path availability
request end-to-end latency
```

SLO nên theo user journey/service path, không chỉ device uptime. Router up nhưng route tới
payment dependency mất vẫn gây impact.

## 8. Interface và link

Theo dõi:

- link up/down;
- speed/duplex;
- bytes/packets;
- utilization;
- errors;
- drops;
- discards;
- queue;
- carrier change.

```text
utilization = bits_per_second / interface_speed_bits
```

Counter reset khi reboot; dùng `rate()` và xử lý reset. Không cộng cả physical và virtual
interface rồi diễn giải như traffic độc lập.

## 9. Layer 2

Vấn đề:

- VLAN mismatch;
- MAC flap;
- ARP/NDP failure;
- broadcast/multicast storm;
- duplicate address;
- spanning-tree change;
- MTU mismatch.

Cloud thường che L2, nhưng node/on-prem vẫn cần switch telemetry. ARP cache “có entry” không
chứng minh route/application đúng.

## 10. IP và reachability

Quan sát:

- source/destination address family;
- route chosen;
- TTL/hop limit;
- fragmentation;
- unreachable;
- policy drop;
- asymmetric path;
- IPAM exhaustion/conflict.

Đừng reverse-DNS mọi IP để enrich metric: tốn thời gian, tạo traffic và có thể trả tên không
ổn định. OpenTelemetry cũng khuyến cáo không reverse lookup chỉ để điền `server.address`.

## 11. Routing

Control plane:

- route count/change;
- protocol session;
- convergence;
- rejected/withdrawn route;
- policy/config version.

Data plane:

- next hop;
- path;
- loss/latency;
- ECMP distribution;
- blackhole/loop.

Control plane healthy không chứng minh forwarding đúng. Synthetic/flow/packet evidence cần
xác nhận data plane.

## 12. BGP

Theo dõi:

- session state/uptime;
- prefix received/advertised;
- flap;
- update rate;
- route age;
- best-path change;
- RPKI/validation nếu dùng;
- convergence.

Alert prefix count cần baseline theo peer/address family; một con số cố định cho mọi peer dễ
false positive.

## 13. ICMP

ICMP không chỉ là ping; nó mang error và path information:

- destination unreachable;
- time exceeded;
- packet too big;
- echo.

Firewall chặn ICMP “cho an toàn” có thể phá Path MTU Discovery. Probe ICMP cần quyền phù hợp
nhưng không nên chạy exporter root nếu capability nhỏ hơn đủ dùng.

## 14. UDP

UDP không có connection/ACK ở transport, nên application phải cung cấp success/timeout.

Theo dõi:

- datagrams/bytes;
- socket drops;
- receive/send buffer error;
- application timeout;
- ICMP unreachable;
- request/response correlation khi protocol cho phép.

UDP “send success” chỉ nghĩa kernel nhận datagram, không chứng minh peer đã xử lý.

## 15. TCP lifecycle

```text
SYN → SYN-ACK → ACK
→ established/data
→ FIN/ACK hoặc RST
```

Tín hiệu:

- active/passive opens;
- failed connects;
- handshake time;
- established;
- reset;
- retransmit;
- state transitions;
- close reason.

Tách client connect failure và server accept failure.

## 16. TCP latency

Phân rã:

```text
DNS
+ TCP handshake
+ TLS handshake
+ request queue
+ server processing
+ response transfer
```

RTT từ kernel/flow khác request latency. Connection reuse làm nhiều request không trả TCP/TLS
cost mỗi lần; dashboard cần biết new vs reused connection.

## 17. Loss và retransmission

Retransmission có thể do:

- congestion/drop;
- reorder;
- wireless/link;
- MTU;
- receiver pressure;
- timeout tuning.

```text
retransmit ratio = retransmitted_segments / sent_segments
```

Tỷ lệ aggregate có thể che một path/zone. Nhưng label mọi source-destination pair vào
Prometheus gây cardinality nổ; dùng flow store cho chi tiết.

## 18. TCP state và reset

Quan sát:

- SYN-SENT/SYN-RECV backlog;
- ESTABLISHED;
- CLOSE-WAIT;
- FIN-WAIT;
- TIME-WAIT;
- RST sent/received;
- orphan sockets.

CLOSE-WAIT tăng thường gợi ý application không close; TIME-WAIT nhiều không tự là lỗi.
Diễn giải theo connection rate, port range và reuse policy.

## 19. Socket và queue

Các queue:

- listen/SYN;
- accept;
- send;
- receive;
- qdisc/NIC;
- proxy upstream.

Queue delay có thể xảy ra khi CPU không 100%. Theo dõi backlog drops, buffer occupancy và
socket pressure. Tăng buffer mù quáng có thể tăng latency do bufferbloat.

## 20. DNS lifecycle

```text
application
→ local cache/stub
→ recursive resolver
→ authoritative chain
→ answer/cache
```

Ghi rõ đo ở hop nào. Client latency cao trong khi resolver latency thấp có thể do local
contention/search domain/retry.

## 21. DNS metrics

Theo dõi:

- query rate;
- success/timeout;
- response code;
- query type;
- latency;
- cache hit/miss;
- recursion;
- upstream failure;
- truncated/TCP fallback;
- stale answer;
- answer count.

Domain/query name có cardinality và privacy cao. Chỉ export aggregate bounded; chi tiết ở log
được kiểm soát.

## 22. DNS correctness và security

Kiểm tra:

- expected record;
- TTL;
- CNAME chain;
- split-horizon view;
- DNSSEC validation khi dùng;
- resolver path;
- NXDOMAIN hijack;
- stale/private answer.

Probe từ nhiều location vì cùng tên có thể trả answer khác theo region/network.

## 23. TLS lifecycle

```text
TCP/QUIC established
→ ClientHello/SNI/ALPN
→ ServerHello/certificate
→ key agreement/Finished
→ encrypted application data
```

Theo dõi version, cipher/ALPN theo bounded enum, handshake latency, failure class, session
resumption và certificate lifecycle. Không log session secret/private key.

## 24. Certificate observability

Theo dõi:

- expiry time;
- validity/not-before;
- hostname/SAN;
- issuer/chain;
- key/signature policy;
- revocation/status nếu áp dụng;
- rotation success;
- deployed fingerprint.

Alert expiry theo nhiều threshold và owner. Scanner thấy certificate ở một endpoint chưa chắc
mọi replica/region đã rotate.

## 25. mTLS

mTLS thêm:

- client certificate;
- trust domain;
- workload identity;
- authorization policy;
- rotation;
- clock dependency.

Phân biệt handshake authentication fail với policy authorization deny. Certificate subject
string không nên là metric label nếu cardinality không giới hạn.

## 26. QUIC

QUIC chạy trên UDP, tích hợp TLS và multiplex stream. Quan sát:

- handshake/connection success;
- version negotiation;
- 0-RTT use/reject;
- packet loss;
- migration;
- RTT;
- congestion;
- stream reset;
- fallback.

TCP dashboard không thấy đầy đủ QUIC. Firewall/NAT UDP timeout có thể tạo failure khác TCP.

## 27. HTTP/3

HTTP/3 chạy trên QUIC, tránh TCP head-of-line giữa stream nhưng vẫn có application/stream
queueing.

Theo dõi:

- negotiated protocol;
- success/error;
- handshake/TTFB;
- stream reset;
- QUIC loss;
- HTTP/2 or HTTP/1 fallback;
- network/provider cohort.

So sánh cùng client/region; traffic selection có thể làm benchmark sai.

## 28. Load balancer

Hai lớp:

```text
frontend: client → load balancer
backend:  load balancer → target
```

Metric:

- frontend connections/requests;
- backend health;
- target selection;
- queue/spillover;
- reset/error theo phía;
- TLS;
- bytes;
- zone/target saturation.

LB 5xx không tự nói backend hay LB tạo lỗi; dùng reason/source.

## 29. Proxy, NAT và address translation

Theo dõi:

- NAT table/port utilization;
- translation failure;
- idle timeout;
- connection reuse;
- proxy upstream;
- forwarding header trust;
- egress IP pool.

NAT port exhaustion thường trông như connect timeout ngẫu nhiên. Source IP ở server có thể là
NAT/proxy, không phải client identity.

## 30. CDN và edge

Metric:

- cache hit/miss;
- edge/origin latency;
- origin fetch error;
- status;
- bytes/egress;
- TLS;
- region/PoP;
- purge/config propagation;
- stale serve.

User success ở edge có thể che origin outage tạm thời; ngược lại cache miss surge làm origin
quá tải. Xem cả hai lớp.

## 31. Firewall và security policy

Theo dõi:

- allow/drop;
- rule/policy ID;
- direction;
- source/destination identity;
- protocol/port;
- change/version;
- default-deny hits;
- shadowed/unused rule.

Drop tăng sau deploy có thể là policy regression. Không page mọi scan Internet vào port đóng.

## 32. Kubernetes CNI

Quan sát:

- IPAM;
- endpoint programming;
- routes/tunnels;
- service load balancing;
- network policy;
- DNS;
- node-to-node;
- overlay MTU;
- agent/operator health.

Tách CNI control-plane health và workload flow outcome. Xem thêm
[Kubernetes Observability](kubernetes_observability.md).

## 33. Service mesh

Mesh thêm hop sidecar/ambient proxy và control plane.

Theo dõi:

- config/certificate propagation;
- proxy readiness;
- downstream/upstream requests;
- retry/outlier ejection;
- mTLS;
- connection pool;
- policy;
- control-plane push.

Proxy metric có thể double-count request ở source và destination; định nghĩa aggregation.

## 34. North–south và east–west

| Path | Ví dụ | Context |
|---|---|---|
| North–south | Internet ↔ service | edge, WAF, LB, ingress |
| East–west | service ↔ service | identity, mesh, CNI |
| Egress | workload → external | NAT, DNS, proxy, vendor |

Dashboard và SLO khác nhau. External dependency cần probe từ đúng egress path, không chỉ laptop.

## 35. Multi-region và multi-cluster

Quan sát:

- inter-region latency/loss;
- routing/failover;
- replication traffic;
- DNS/traffic policy;
- active/standby health;
- capacity;
- data egress cost;
- clock/config skew.

Test failover end-to-end. Route advertised không chứng minh application ở region dự phòng
sẵn sàng hoặc có dữ liệu mới.

## 36. VPN, private link và tunnel

Metric:

- tunnel/session state;
- negotiation/rekey;
- packet/byte;
- drop/replay;
- route;
- MTU/fragment;
- peer health;
- latency;
- capacity.

Tunnel up nhưng route/policy sai vẫn mất traffic. Probe xuyên tunnel tới service đích.

## 37. Blackbox probing

Blackbox Exporter hỗ trợ HTTP/HTTPS, DNS, TCP, ICMP, gRPC và ở phiên bản 0.28 có HTTP/3.

Thiết kế:

- target registry/owner;
- module/version;
- probe từ nhiều vantage point;
- timeout nhỏ hơn scrape timeout;
- TLS/auth bảo vệ exporter;
- exporter self-metrics;
- tránh cho người dùng tùy ý probe internal target.

`probe_success=1` không thay thế latency/correctness assertions.

## 38. Whitebox observability

Whitebox từ app/kernel/device thấy:

- queue;
- retry;
- pool;
- socket;
- route;
- reason code;
- resource.

Blackbox nói user path có hoạt động; whitebox giải thích tại sao. Cần cả hai cho critical path.

## 39. Flow logs, NetFlow và IPFIX

Flow record thường có:

```text
5-tuple
start/end
bytes/packets
direction
action
interface/vantage point
TCP flags
identity/enrichment
```

Sampling làm count ước lượng; exporter/template/version khác nhau. Flow không phải packet và
không chứng minh application success.

## 40. Packet capture

PCAP hữu ích cho:

- handshake;
- retransmission/reorder;
- protocol violation;
- MTU;
- TLS metadata;
- forensic evidence.

Quy trình:

1. authorization/scope;
2. capture filter;
3. thời gian ngắn;
4. encrypted restricted storage;
5. checksum/chain-of-custody nếu incident;
6. TTL/delete.

Không capture toàn cluster “để xem”.

## 41. eBPF và socket telemetry

eBPF có thể nối socket/kernel event với process/cgroup/workload mà không cần packet mirror.

Quan sát:

- connect/accept;
- retransmit;
- RTT;
- drop reason;
- DNS/HTTP metadata tùy hook;
- process/workload identity.

Privilege, kernel compatibility, buffer loss và overhead phải đo. Xem
[eBPF Observability](ebpf_observability.md) cho hook/verifier/production safety.

## 42. Cilium và Hubble

Hubble cung cấp flow visibility ở node, cluster hoặc multi-cluster qua Relay; có L3/L4 và L7
khi visibility tương ứng được bật.

Phân biệt:

- Cilium metrics: health của agent/operator/datapath;
- Hubble metrics/flows: hành vi connectivity/security của workload.

Label source/destination IP, pod và workload có cardinality cao. Chọn context theo use case,
không bật mọi label mặc định.

## 43. Cloud flow logs

Các cloud provider có semantics khác:

- capture point;
- aggregation interval;
- sampling;
- accepted/rejected;
- delayed delivery;
- unsupported traffic;
- field/version;
- cost.

Đọc tài liệu đúng resource/version. “Không có flow” có thể là zero traffic, unsupported path,
filter hoặc logging misconfiguration.

## 44. Synthetic network tests

Test:

- DNS expected answer;
- TCP port;
- TLS certificate/SNI/ALPN;
- HTTP status/body/header;
- gRPC health;
- path from region/network;
- download/upload;
- failover.

Synthetic phải có identity/rate limit và không tạo side effect business. Gắn traffic test để
lọc analytics nhưng vẫn quan sát server load.

## 45. Distributed traces

Trace cho thấy:

- client wait;
- DNS/connect/TLS nếu instrumentation có;
- proxy/service hops;
- retry;
- downstream critical path.

Trace không thấy packet loss trực tiếp nếu library chỉ báo timeout. Nối span với host/socket/
flow window bằng workload, peer, time và exemplar.

## 46. OpenTelemetry network attributes

Dùng semantic chuẩn:

- `server.address`, `server.port`;
- client/source/destination attributes theo context;
- `network.transport`;
- protocol-specific HTTP/RPC/DNS/TLS attributes.

Không reverse lookup để điền hostname. Theo dõi stability của attribute; SemConv 1.43 vẫn có
nhóm Development. Pin schema/version trong telemetry contract.

## 47. Metric contract

Ví dụ:

```text
network_connections_total{service,peer_service,outcome,transport}
network_connect_duration_seconds{service,peer_service}
network_bytes_total{service,peer_service,direction}
network_packets_dropped_total{observer,reason,direction}
network_tcp_retransmits_total{observer,direction}
network_dns_requests_total{resolver,outcome,record_type}
network_dns_duration_seconds{resolver}
network_tls_handshakes_total{service,outcome,version}
```

Không label theo raw IP pair/domain/connection ID trong Prometheus.

## 48. Logs và flow events

Structured flow:

```json
{
  "event": "network_flow",
  "observed_at": "2026-07-30T12:00:00Z",
  "observer": "cni-node-a",
  "source": {"workload": "checkout", "namespace": "shop"},
  "destination": {"service": "payment", "port": 443},
  "transport": "tcp",
  "direction": "egress",
  "verdict": "dropped",
  "reason": "policy_denied"
}
```

Giữ schema/provenance và sampling metadata.

## 49. Correlation và exemplars

Correlation keys:

- trace/span ID;
- workload/service;
- node/interface;
- peer;
- direction;
- time window;
- connection/socket ID ở store chi tiết.

Exemplar nối histogram với trace mà không biến trace ID thành label. Hubble OpenMetrics có thể
xuất exemplar khi cấu hình phù hợp.

## 50. Bandwidth và capacity

Theo dõi:

- average/peak/p95 throughput;
- link/contract capacity;
- burst;
- queue/drop;
- headroom;
- traffic class;
- cost.

Average 40% có thể che microburst làm drop. Kết hợp high-resolution device metric hoặc queue
telemetry cho path critical.

## 51. Queueing và bufferbloat

Khi load gần capacity, queue delay tăng trước khi drop rõ.

```text
latency = propagation + transmission + processing + queueing
```

Tăng buffer có thể giảm drop nhưng tăng tail latency. Theo dõi queue occupancy, sojourn time,
RTT dưới tải và active queue management nếu có.

## 52. Latency decomposition

Đo từ cùng vantage point:

```text
total
├─ name resolution
├─ connect
├─ TLS
├─ request write
├─ TTFB
└─ response transfer
```

Trừ các percentile độc lập là sai: p99(total) không bằng tổng p99 từng stage. Dùng trace/probe
trên cùng request cho decomposition.

## 53. MTU và fragmentation

Triệu chứng:

- request nhỏ được, lớn timeout;
- tunnel path lỗi;
- retransmission;
- ICMP packet-too-big bị chặn;
- TLS/gRPC bất ổn.

Theo dõi interface/tunnel MTU, fragmentation và PMTUD. Test packet size có kiểm soát; không
tăng MTU một phía.

## 54. IPv6 và dual stack

Quan sát riêng:

- address family;
- DNS A/AAAA;
- route;
- connect success/latency;
- Happy Eyeballs/fallback;
- policy parity;
- NAT64/DNS64;
- MTU/ICMPv6.

Aggregate IPv4+IPv6 có thể che IPv6 hỏng vì client fallback IPv4 thành công nhưng chậm.

## 55. QoS và traffic class

Theo dõi:

- DSCP/class;
- queue;
- policing/shaping;
- drops;
- latency/jitter;
- policy configuration.

Marking ở source có thể bị remark/strip qua hop. Xác minh tại nhiều điểm và tránh gắn traffic
class theo untrusted client input.

## 56. Failure mode matrix

| Triệu chứng | Nghi vấn đầu tiên | Evidence |
|---|---|---|
| DNS timeout | resolver/path | DNS probe/log/flow |
| Connect timeout | route/drop/SYN queue | flow/TCP/eBPF |
| Connect refused | listener/target | RST/socket/service |
| TLS fail | cert/SNI/ALPN/time | probe/proxy log |
| TTFB cao | queue/server/downstream | trace/proxy |
| Transfer chậm | loss/bandwidth/flow control | TCP/packet |
| Chỉ payload lớn lỗi | MTU/fragment | ICMP/PCAP |

Matrix định hướng, không thay evidence.

## 57. Dashboard

Theo thứ tự:

1. user/service path SLO;
2. DNS/connect/TLS/application decomposition;
3. loss/retransmit/reset/drop;
4. path/hop/region;
5. LB/proxy/backend;
6. interface/queue/capacity;
7. recent config/deploy;
8. probe/collector health.

Service map cần traffic/time filter; đường không xuất hiện không tự là dependency bị mất.

## 58. Alerting

Page theo symptom:

- critical path unreachable;
- connect/TLS success xuống;
- packet drop/loss gây SLO;
- DNS failure/latency;
- NAT/port exhaustion;
- route/session loss có impact;
- certificate sắp hết hạn theo response window;
- telemetry blind spot.

Không page interface utilization đơn lẻ nếu không có queue/drop/latency impact.

## 59. Troubleshooting workflow

```text
scope: ai/ở đâu/khi nào
→ compare good vs bad cohort
→ DNS
→ route/reachability
→ TCP/UDP/QUIC
→ TLS
→ proxy/LB
→ application/downstream
→ config/change
```

Thu evidence ít xâm lấn trước; PCAP/eBPF debug chỉ khi cần và có authorization.

## 60. Incident response

Trong incident:

- ghi vantage point/time;
- giữ flow/probe/trace;
- kiểm tra control và data plane;
- xác định blast radius;
- containment có rollback;
- theo dõi failover/recovery;
- xác nhận từ user path.

Không restart mọi network component cùng lúc; mất evidence và tạo thêm convergence/churn.

## 61. Security và privacy

Rủi ro:

- topology discovery;
- domain/SNI/URL nhạy cảm;
- IP/user re-identification;
- payload/credential;
- decryption key;
- packet forensic access.

Controls: aggregation, tokenization, field allowlist, encryption, RBAC, audited just-in-time
access, short TTL và jurisdiction boundary.

## 62. Cardinality và cost

Series tiềm năng:

```text
sources × destinations × ports × protocols × zones × outcomes
```

Giải pháp:

- service/workload roll-up;
- bounded peer groups;
- metrics cho aggregate;
- flows ở columnar store;
- sampled PCAP theo incident;
- top-k/offline analysis;
- retention tier;
- exclude health/noise traffic.

## 63. Test và chaos

Kiểm thử:

- DNS wrong/slow;
- packet loss/latency;
- port blocked;
- certificate expired/untrusted;
- LB target unhealthy;
- route withdrawal;
- NAT exhaustion;
- MTU;
- IPv6-only failure;
- telemetry collector loss.

Thực hiện trong phạm vi được phê duyệt, có abort condition và rollback. Xác minh cả alert lẫn
fallback/business outcome.

## 64. Workshop, checklist và câu hỏi

Workshop:

1. chọn client → payment path;
2. vẽ mọi hop/vantage point;
3. thêm DNS/connect/TLS/TTFB;
4. bật probe ngoài và trong cluster;
5. gây policy drop;
6. khoanh vùng bằng metric/flow/trace;
7. kiểm tra recovery từ client.

Checklist:

- [ ] Có path inventory và owner?
- [ ] Source/destination là identity, không chỉ IP?
- [ ] Ghi observer/direction?
- [ ] Blackbox và whitebox đều có?
- [ ] DNS/TCP/TLS được phân rã?
- [ ] Flow sampling/cardinality rõ?
- [ ] PCAP/debug có quy trình privacy?
- [ ] Telemetry pipeline có health SLO?
- [ ] Dual-stack/failover đã test?

Câu hỏi:

1. Ping success chứng minh được gì?
2. Flow khác packet và trace thế nào?
3. Vì sao TIME-WAIT cao chưa chắc lỗi?
4. Làm sao phát hiện NAT port exhaustion?
5. Tại sao p99 total không bằng tổng p99 stage?
6. Hubble flow và Cilium health metric khác nhau thế nào?
7. Khi nào được dùng PCAP production?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Telemetry và công cụ

- [OpenTelemetry general network attributes](https://opentelemetry.io/docs/specs/semconv/general/attributes/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Prometheus Blackbox Exporter](https://github.com/prometheus/blackbox_exporter)
- [Cilium network observability with Hubble](https://docs.cilium.io/en/stable/observability/hubble/)
- [Cilium and Hubble metrics](https://docs.cilium.io/en/stable/observability/metrics/)

### Protocol standards

- [TCP – RFC 9293](https://www.rfc-editor.org/rfc/rfc9293)
- [TLS 1.3 – RFC 9846](https://www.rfc-editor.org/rfc/rfc9846)
- [QUIC – RFC 9000](https://www.rfc-editor.org/rfc/rfc9000)
- [HTTP/3 – RFC 9114](https://www.rfc-editor.org/rfc/rfc9114)

Chủ đề tiếp theo:
[CI/CD & Software Delivery Observability](cicd_software_delivery_observability.md) – commit,
build, test, artifact, deployment, progressive delivery, rollback, DORA metrics và
supply-chain evidence.

---

*Cập nhật lần cuối: 2026-07-30*
