# Kubernetes Networking Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. CNI (Container Network Interface) Deep Dive

### What – CNI là gì?
CNI là plugin interface mà kubelet dùng để thiết lập networking cho Pods. CNI plugin chịu trách nhiệm: cấp IP, tạo veth pair, thiết lập routing giữa các nodes.

### How – CNI Flow

```
Pod creation sequence:
1. kubelet gọi CRI (containerd) tạo container
2. kubelet gọi CNI plugin với config từ /etc/cni/net.d/
3. CNI plugin:
   a. Cấp IP (từ IPAM - IP Address Management)
   b. Tạo veth pair: (eth0 trong pod, vethXXX trên host)
   c. Add vethXXX vào bridge/overlay network
   d. Setup routing rules
4. Pod có network connectivity

CNI Plugin files:
/etc/cni/net.d/       ← config files (10-calico.conflist, etc.)
/opt/cni/bin/         ← CNI binary executables
```

### How – Calico CNI

```yaml
# Calico modes:
# 1. BGP mode (default): distribute routes via BGP protocol
#    - Mỗi node là BGP router
#    - Routes được quảng bá cho nhau
#    - Không cần overlay (low overhead)
#    - Yêu cầu: L2 connectivity giữa nodes

# 2. VXLAN mode: overlay khi không có BGP support
#    - Đóng gói packets trong VXLAN frames
#    - Hoạt động qua L3 routers (cloud VPC)

# 3. WireGuard: encrypted overlay (production-grade encryption)
```

```bash
# Cài Calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26           # /26 per node = 64 IPs per node
      cidr: 10.244.0.0/16    # cluster pod CIDR
      encapsulation: VXLANCrossSubnet  # BGP trong subnet, VXLAN across subnets
      natOutgoing: Enabled
      nodeSelector: all()
EOF

# Xem Calico IP pools
calicoctl get ippool -o wide

# BGP peers
calicoctl get bgppeer

# Xem routes trên node
ip route show | grep cali   # Calico veth routes
bird -c /etc/calico/bird.cfg  # BGP daemon config (nếu dùng BGP mode)

# Felix: Calico agent trên mỗi node
kubectl logs -n calico-system -l app.kubernetes.io/name=calico-node -c calico-node | grep -i error
```

### How – Cilium CNI (eBPF-based)

```
Cilium Architecture:
┌─────────────────────────────────────────────────────────┐
│  eBPF Programs (loaded vào Linux kernel)                │
│  ├── XDP programs (L2, line-rate packet processing)    │
│  ├── TC programs (L3/L4 routing, load balancing)       │
│  └── kprobe/tracepoint programs (observability)        │
│                                                         │
│  Cilium Agent (per node):                              │
│  ├── Compile & load eBPF programs                     │
│  ├── Manage BPF maps (routing tables, policy)         │
│  └── Sync from K8s API                                │
└─────────────────────────────────────────────────────────┘

Advantages over iptables:
- O(1) lookup với BPF hash maps vs O(n) iptables rules
- Kernel bypass (XDP): process packets before OS stack
- Native pod-to-pod (no NAT): preserve source IPs
- L7 policy (HTTP/gRPC/Kafka-aware)
```

```bash
# Cài Cilium
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=true \       # thay kube-proxy bằng eBPF
  --set k8sServiceHost=10.0.0.1 \
  --set k8sServicePort=6443 \
  --set hubble.relay.enabled=true \       # observability
  --set hubble.ui.enabled=true \
  --set encryption.enabled=true \         # WireGuard encryption
  --set encryption.type=wireguard

# Cilium CLI
cilium status
cilium connectivity test    # chạy full connectivity tests

# Hubble: network observability
hubble observe --pod frontend/myapp
# → xem tất cả flows vào/ra pod

hubble observe --namespace production --verdict DROPPED
# → xem packets bị drop (NetworkPolicy violations)

# Xem eBPF maps
cilium bpf ct list global  # connection tracking table
cilium bpf lb list         # load balancer entries (thay kube-proxy)
cilium bpf policy get      # policy enforcement

# L7 policy với Cilium (iptables không làm được)
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: api-policy
spec:
  endpointSelector:
    matchLabels:
      app: api-server
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/v1/.*"    # chỉ cho GET requests đến /api/v1/
        - method: "POST"
          path: "/api/v1/orders"
```

---

## 2. NetworkPolicy Advanced Patterns

### How – Default Deny và Namespace Isolation

```yaml
# 1. Default deny tất cả ingress trong namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}    # select tất cả pods trong namespace
  policyTypes:
  - Ingress

---
# 2. Default deny tất cả egress (strict mode)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 53       # cho phép DNS (bắt buộc)
      protocol: UDP
    - port: 53
      protocol: TCP
  # Không có to: → chỉ allow DNS, deny tất cả egress khác

---
# 3. Allow frontend → backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
      namespaceSelector:          # AND condition: pod phải trong namespace
        matchLabels:
          kubernetes.io/metadata.name: production
    ports:
    - protocol: TCP
      port: 8080

---
# 4. Allow backend → database (specific port)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432

---
# 5. Allow egress đến external APIs (IP-based)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-api
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8        # không đến private ranges
        - 172.16.0.0/12
        - 192.168.0.0/16
    ports:
    - protocol: TCP
      port: 443             # chỉ HTTPS

---
# 6. Cross-namespace: monitoring namespace → tất cả namespaces
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring-ingress
  namespace: production    # apply trong TỪNG namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9090            # metrics port
```

### How – NetworkPolicy Debugging

```bash
# Kiểm tra network policies trong namespace
kubectl get networkpolicy -n production

# Describe để xem rules
kubectl describe networkpolicy allow-frontend-to-backend -n production

# Test connectivity (debug pod)
kubectl run test-pod --rm -it --image=nicolaka/netshoot -- /bin/bash

# Từ debug pod: test connection
curl http://backend-svc.production.svc.cluster.local:8080/health

# Với Cilium: xem policy enforcement
hubble observe --namespace production --verdict DROPPED

# Với Calico: xem effective policy
calicoctl get networkpolicy -n production -o yaml
```

---

## 3. Service Discovery & DNS

### How – CoreDNS Configuration

```yaml
# CoreDNS ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {   # forward non-cluster DNS lên host
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
    # Custom: forward company internal DNS
    internal.company.com:53 {
        forward . 10.0.0.100  # internal DNS server
    }
```

```bash
# DNS resolution patterns trong K8s:
# Service DNS:      <service>.<namespace>.svc.cluster.local
# Pod DNS:          <pod-ip-dashes>.<namespace>.pod.cluster.local
# Headless pod:     <pod-name>.<service>.<namespace>.svc.cluster.local

# Debug DNS
kubectl run dnsutils --rm -it --image=tutum/dnsutils -- bash

# Từ trong pod
nslookup kubernetes.default.svc.cluster.local
nslookup myapp.production.svc.cluster.local

# Xem DNS config trong pod
cat /etc/resolv.conf
# nameserver 10.96.0.10     ← CoreDNS ClusterIP
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5

# ndots:5: nếu domain có < 5 dấu chấm → thử search domain trước
# → "myapp" → thử "myapp.default.svc.cluster.local" trước
# → "myapp.production" → thử full search path

# DNS caching: NodeLocal DNSCache (giảm CoreDNS load)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
# → Mỗi node có DNS cache daemon
# → Giảm latency (local), giảm CoreDNS overload
```

---

## 4. Ingress & Gateway API

### How – Nginx Ingress Controller (chi tiết)

```yaml
# Ingress Resource
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /           # rewrite URL path
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-connections: "100"
    nginx.ingress.kubernetes.io/limit-rps: "50"
    # CORS
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://myapp.com"
    # Custom headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "Strict-Transport-Security: max-age=31536000";
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.com
    - api.myapp.com
    secretName: myapp-tls     # cert-manager auto-managed secret
  rules:
  - host: myapp.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
  - host: api.myapp.com
    http:
      paths:
      - path: /api/v1(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: backend-svc
            port:
              number: 8080
      - path: /api/v2(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: backend-v2-svc
            port:
              number: 8080
```

```yaml
# cert-manager: auto TLS via Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@myapp.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
    - dns01:                    # wildcard certs
        cloudflare:
          email: admin@myapp.com
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
---
# Certificate (cert-manager auto-issue và renew)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: production
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - myapp.com
  - "*.myapp.com"    # wildcard
```

### How – Gateway API (thế hệ mới của Ingress)

```
Gateway API vs Ingress:
┌────────────────────────────────────────────────────────┐
│ Ingress: 1 resource, tất cả config trong annotations  │
│          Platform ops + dev config cùng chỗ           │
│                                                        │
│ Gateway API: role separation                          │
│   GatewayClass (ClusterScoped) ← Infra team          │
│   Gateway (Namespace) ← Platform team                │
│   HTTPRoute (Namespace) ← Dev team                   │
└────────────────────────────────────────────────────────┘
```

```yaml
# GatewayClass: define infra (1 lần, infra team)
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx
spec:
  controllerName: k8s.nginx.org/nginx-gateway-controller
---
# Gateway: create load balancer (platform team, per namespace/cluster)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: prod-gateway
  namespace: infra
spec:
  gatewayClassName: nginx
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: myapp-tls
        namespace: production
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            gateway-access: "true"    # chỉ namespaces được label
---
# HTTPRoute: routing rules (dev team, trong app namespace)
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp-route
  namespace: production    # namespace của app
spec:
  parentRefs:
  - name: prod-gateway
    namespace: infra       # reference Gateway
  hostnames:
  - myapp.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api
      headers:
      - name: x-version
        value: v2
    backendRefs:
    - name: backend-v2-svc
      port: 8080
      weight: 100
  - matches:
    - path:
        type: PathPrefix
        value: /api
    backendRefs:
    - name: backend-svc
      port: 8080
      weight: 90
    - name: backend-canary-svc
      port: 8080
      weight: 10         # 10% traffic canary
  - matches:
    - path:
        type: PathPrefix
        value: /
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: x-forwarded-host
          value: myapp.com
    backendRefs:
    - name: frontend-svc
      port: 80
```

---

## 5. Service Mesh Basics (Istio)

### What – Service Mesh là gì?
Service Mesh inject sidecar proxy (Envoy) vào mỗi Pod, intercept tất cả network traffic để provide: mTLS, traffic management, observability mà không cần thay đổi application code.

### How – Istio Core Concepts

```
Istio Architecture:
Control Plane:
  Istiod = Pilot (traffic management) + Citadel (mTLS certs) + Galley (config)

Data Plane:
  Envoy sidecar (inject tự động vào pods)
  ← intercept ALL traffic
  ← enforce mTLS
  ← collect metrics/traces
  ← apply traffic policies
```

```yaml
# Enable auto sidecar injection cho namespace
kubectl label namespace production istio-injection=enabled

# VirtualService: traffic routing rules
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: myapp
  namespace: production
spec:
  hosts:
  - myapp-svc
  http:
  # Header-based routing: X-Canary: true → canary version
  - match:
    - headers:
        x-canary:
          exact: "true"
    route:
    - destination:
        host: myapp-svc
        subset: canary
  # Weight-based routing: 90/10 split
  - route:
    - destination:
        host: myapp-svc
        subset: stable
      weight: 90
    - destination:
        host: myapp-svc
        subset: canary
      weight: 10
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
      retryOn: 5xx,reset,connect-failure
---
# DestinationRule: define subsets + load balancing
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: myapp
  namespace: production
spec:
  host: myapp-svc
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE     # upgrade to HTTP/2
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    outlierDetection:               # circuit breaker
      consecutiveGatewayErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
  subsets:
  - name: stable
    labels:
      version: stable
    trafficPolicy:
      loadBalancer:
        simple: LEAST_CONN
  - name: canary
    labels:
      version: canary
```

```yaml
# PeerAuthentication: enforce mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT     # STRICT: mTLS bắt buộc | PERMISSIVE: optional
---
# AuthorizationPolicy: L4/L7 access control
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  selector:
    matchLabels:
      app: backend
  action: ALLOW
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/production/sa/frontend"]  # service account
    to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
```

---

### Compare – CNI Plugins

| | Flannel | Calico | Cilium | Weave |
|--|---------|--------|--------|-------|
| **Performance** | Medium | High | Very High | Medium |
| **NetworkPolicy** | ❌ | ✅ | ✅ (L7) | ✅ |
| **Encryption** | ❌ | WireGuard | WireGuard | ✅ |
| **eBPF** | ❌ | ✅ (optional) | ✅ (native) | ❌ |
| **Observability** | Basic | Felix stats | Hubble UI | ❌ |
| **Complexity** | Simple | Medium | High | Medium |
| **Best for** | Learning | Production/BGP | High-perf/L7 | Simple prod |

### Compare – Ingress vs Gateway API

| | Ingress | Gateway API |
|--|---------|-------------|
| **Role separation** | ❌ (all in one) | ✅ (GatewayClass/Gateway/Route) |
| **Traffic splitting** | Via annotations | Native weight-based |
| **Protocol support** | HTTP/HTTPS | HTTP, gRPC, TCP, UDP, TLS |
| **Extensibility** | Annotations (non-portable) | Policy attachments |
| **Maturity** | GA | GA (v1.0 K8s 1.28+) |

### Trade-offs
- Cilium eBPF: hiệu suất cao nhưng kernel version requirements (5.10+); debug phức tạp hơn iptables
- Istio: mTLS và observability tuyệt vời nhưng overhead ~5ms latency, 10-20% CPU per sidecar
- Gateway API: more expressive nhưng cần controller support; Ingress vẫn được dùng rộng rãi hơn

### Real-world Usage
```bash
# Test NetworkPolicy hiệu quả
kubectl run test --rm -it --image=nicolaka/netshoot -n production -- \
  curl -v http://backend-svc:8080/health
# → Nếu NetworkPolicy đúng: kết nối thành công
# → Nếu sai: Connection refused hoặc timeout

# Cilium network performance test
cilium connectivity test --test=pod-to-pod-encryption

# Kiểm tra Envoy proxy config (Istio)
istioctl proxy-config cluster myapp-pod.production
istioctl proxy-config listener myapp-pod.production
istioctl analyze -n production    # validate Istio configs

# Verify mTLS
istioctl x describe pod myapp-pod-xxx -n production
# → Hiện effective policy, mTLS mode, etc.
```

### Ghi chú – Chủ đề tiếp theo
> Storage Deep – CSI driver internals, Velero backup/restore, Volume Snapshots, ReadWriteMany patterns

---

*Cập nhật lần cuối: 2026-05-06*
