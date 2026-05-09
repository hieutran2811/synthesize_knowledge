# Service Mesh – Istio & Linkerd

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Service Mesh Overview

### What – Service Mesh là gì?
**Service Mesh** là infrastructure layer xử lý **service-to-service communication** trong microservices. Thay vì mỗi service tự implement retry/mTLS/circuit breaker/observability, service mesh inject **sidecar proxy** (Envoy) vào mỗi Pod để xử lý tất cả network concerns.

### How – Kiến trúc

```
Without Service Mesh:
  OrderService ──HTTP──→ PaymentService
  (retry logic in code, no mutual TLS, manual tracing)

With Service Mesh:
  OrderService → [Envoy sidecar] ──mTLS──→ [Envoy sidecar] → PaymentService
                       ↓                          ↓
                  Control Plane (Istiod)
                  (certificates, config, telemetry)
```

```
Service Mesh – Control Plane vs Data Plane:

Control Plane (Istiod):
  - Pilot:      traffic management config → Envoy xDS API
  - Citadel:    certificate management (SPIFFE/SPIRE)
  - Galley:     config validation

Data Plane (per-pod Envoy sidecars):
  - Intercept all inbound/outbound traffic (iptables rules)
  - mTLS termination
  - Metrics collection (L7: request count, duration, errors)
  - Distributed tracing span injection
  - Circuit breaker, retry, timeout enforcement
```

---

## 2. Istio Setup

### How – Installation

```bash
# Install Istio CLI
curl -L https://istio.io/downloadIstio | sh -
export PATH=$HOME/istio-1.20.0/bin:$PATH

# Install Istio to cluster (demo profile)
istioctl install --set profile=demo -y

# Verify
istioctl verify-install
kubectl get pods -n istio-system

# Enable sidecar injection for namespace
kubectl label namespace production istio-injection=enabled

# Manually inject (non-labeled namespace)
kubectl apply -f <(istioctl kube-inject -f deployment.yaml)
```

```yaml
# Istio config profile comparison:
# minimal    – control plane only, no gateways
# default    – production recommended
# demo       – all features (not for prod: high resource)
# ambient    – sidecar-less (ztunnel + waypoint proxies) - new in 1.22

# Helm install (production)
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm install istio-base istio/base -n istio-system --create-namespace
helm install istiod istio/istiod -n istio-system \
    --set defaults.global.proxy.resources.requests.cpu=100m \
    --set defaults.global.proxy.resources.requests.memory=128Mi
helm install istio-ingress istio/gateway -n istio-ingress --create-namespace
```

---

## 3. mTLS – Mutual TLS

### What – mTLS là gì?
**mTLS** (Mutual TLS): cả client lẫn server xác thực nhau bằng certificates. Với Istio, certificates tự động cấp phát theo **SPIFFE** standard (Secure Production Identity Framework).

```
SPIFFE Identity: spiffe://cluster.local/ns/production/sa/order-service
Certificate SAN: URI:spiffe://cluster.local/ns/production/sa/order-service
Rotation: automatic (mặc định 24h)
```

```yaml
# PeerAuthentication: enforce mTLS mode
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT    # reject plain-text connections
    # PERMISSIVE – accept both mTLS and plain-text (migration phase)
    # DISABLE    – plain-text only
---
# PeerAuthentication per workload
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: order-service-mtls
  namespace: production
spec:
  selector:
    matchLabels:
      app: order-service
  mtls:
    mode: STRICT
  portLevelMtls:
    8443:
      mode: DISABLE   # health check port: no mTLS (kubelet can't present cert)
```

```yaml
# AuthorizationPolicy: service-to-service access control
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: order-service-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: order-service
  action: ALLOW
  rules:
    # Allow từ ingress gateway
    - from:
        - source:
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingressgateway-service-account"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/orders*"]
    # Allow từ payment-service (internal)
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/payment-service-sa"]
      to:
        - operation:
            methods: ["GET"]
            paths: ["/api/orders/*/status"]
    # Deny all other traffic (implicit)
```

---

## 4. Traffic Management

### How – VirtualService & DestinationRule

```yaml
# DestinationRule: load balancing, connection pool, circuit breaker
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: order-service
  namespace: production
spec:
  host: order-service   # K8s Service name
  trafficPolicy:
    loadBalancer:
      simple: LEAST_CONN   # ROUND_ROBIN | RANDOM | LEAST_CONN
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http2MaxRequests: 1000
        pendingRequests: 100
        maxRequestsPerConnection: 10
    outlierDetection:              # circuit breaker
      consecutive5xxErrors: 5      # eject after 5 consecutive errors
      interval: 10s                # analysis window
      baseEjectionTime: 30s        # minimum ejection duration
      maxEjectionPercent: 50       # max % of hosts ejected
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
      trafficPolicy:
        loadBalancer:
          simple: ROUND_ROBIN
```

```yaml
# VirtualService: routing rules
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: order-service
  namespace: production
spec:
  hosts:
    - order-service
  http:
    # Canary: 10% to v2, 90% to v1
    - match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: order-service
            subset: v2
    - route:
        - destination:
            host: order-service
            subset: v1
          weight: 90
        - destination:
            host: order-service
            subset: v2
          weight: 10
      # Retry policy
      retries:
        attempts: 3
        perTryTimeout: 5s
        retryOn: "5xx,reset,connect-failure,retriable-4xx"
      # Timeout
      timeout: 30s
      # Fault injection (for testing)
      # fault:
      #   delay:
      #     percentage:
      #       value: 10
      #     fixedDelay: 5s
      #   abort:
      #     percentage:
      #       value: 5
      #     httpStatus: 503
```

### How – Ingress Gateway

```yaml
# Gateway: expose services externally
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: production-gateway
  namespace: production
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: api-example-com-tls   # K8s Secret với TLS cert
      hosts:
        - api.example.com
    - port:
        number: 80
        name: http
        protocol: HTTP
      tls:
        httpsRedirect: true   # 301 redirect to HTTPS
      hosts:
        - api.example.com
---
# VirtualService attached to Gateway
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-routes
  namespace: production
spec:
  hosts:
    - api.example.com
  gateways:
    - production-gateway
  http:
    - match:
        - uri:
            prefix: /api/orders
      route:
        - destination:
            host: order-service
            port:
              number: 80
    - match:
        - uri:
            prefix: /api/payments
      route:
        - destination:
            host: payment-service
            port:
              number: 80
```

---

## 5. Observability với Istio

### How – Metrics, Traces, Logs

```bash
# Istio tự động inject vào Envoy sidecar:
# - RED metrics: Rate, Errors, Duration (Prometheus)
# - Distributed traces (Zipkin/Jaeger/Datadog headers)
# - Access logs

# Install addons
kubectl apply -f samples/addons/prometheus.yaml
kubectl apply -f samples/addons/grafana.yaml
kubectl apply -f samples/addons/jaeger.yaml
kubectl apply -f samples/addons/kiali.yaml   # service mesh observability UI

# Access dashboards
istioctl dashboard grafana      # Istio dashboards pre-built
istioctl dashboard jaeger
istioctl dashboard kiali        # topology graph + health
```

```yaml
# Telemetry API: customize metrics/tracing/logging
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: mesh-default
  namespace: istio-system
spec:
  # Distributed tracing
  tracing:
    - providers:
        - name: jaeger
      randomSamplingPercentage: 10.0   # 10% sampling in prod
  # Access logging
  accessLogging:
    - providers:
        - name: envoy
  # Metrics
  metrics:
    - providers:
        - name: prometheus
      overrides:
        - match:
            metric: REQUEST_COUNT
          tagOverrides:
            destination_service:
              operation: UPSERT
              value: "destination.service.name"
```

```promql
# Istio Prometheus metrics
# Request rate
rate(istio_requests_total{reporter="source",destination_service="order-service.production.svc.cluster.local"}[5m])

# Error rate
sum(rate(istio_requests_total{response_code=~"5.*",reporter="destination"}[5m]))
/ sum(rate(istio_requests_total{reporter="destination"}[5m]))

# P99 latency
histogram_quantile(0.99,
  sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination"}[5m]))
  by (le, destination_service_name))
```

---

## 6. Linkerd – Lightweight Alternative

### What – Linkerd vs Istio?
**Linkerd** là service mesh nhẹ hơn, đơn giản hơn, dùng **Rust-based micro-proxy** (linkerd2-proxy) thay Envoy. Ít features hơn nhưng resource footprint thấp hơn đáng kể.

```bash
# Install Linkerd
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check

# Enable namespace
kubectl annotate namespace production linkerd.io/inject=enabled

# Inject manually
kubectl get deployment order-service -o yaml | linkerd inject - | kubectl apply -f -

# Viz extension (dashboard)
linkerd viz install | kubectl apply -f -
linkerd viz dashboard
```

```yaml
# Linkerd Service Profile: per-route metrics and retries
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: order-service.production.svc.cluster.local
  namespace: production
spec:
  routes:
    - name: GET /api/orders/{id}
      condition:
        method: GET
        pathRegex: /api/orders/[^/]*
      responseClasses:
        - condition:
            status:
              min: 500
              max: 599
          isFailure: true
      retryBudget:
        retryRatio: 0.2         # retry up to 20% of requests
        minRetriesPerSecond: 10
        ttl: 10s
      timeout: 5s
    - name: POST /api/orders
      condition:
        method: POST
        pathRegex: /api/orders
      # No retry for non-idempotent
      timeout: 10s
```

---

## 7. Compare & Trade-offs

### Compare – Istio vs Linkerd vs Consul Connect

| | Istio | Linkerd | Consul Connect |
|--|-------|---------|----------------|
| Proxy | Envoy (C++) | linkerd2-proxy (Rust) | Envoy |
| CPU overhead | ~0.5 vCPU/pod | ~0.05 vCPU/pod | ~0.3 vCPU/pod |
| Memory overhead | ~50-100MB/pod | ~10-20MB/pod | ~40MB/pod |
| Features | Excellent (most complete) | Good (focused) | Good + multi-DC |
| mTLS | ✅ SPIFFE/SPIRE | ✅ automatic | ✅ |
| Traffic mgmt | VirtualService/DestRule | ServiceProfile | Intentions |
| Multi-cluster | ✅ | ✅ | ✅ |
| Learning curve | High | Low-Medium | Medium |
| Ambient mesh | ✅ (1.22+, no sidecar) | ❌ | ❌ |
| Khi dùng | Full features, large scale | Simplicity, low overhead | HashiCorp stack |

### Trade-offs

- **Sidecar overhead**: mỗi Pod +1 container (Envoy) → +50-100MB RAM, latency +0.5-2ms; Istio Ambient mode giải quyết bằng node-level proxy
- **Complexity**: Istio có ~50+ CRDs; debug khó; `istioctl analyze` và `istioctl proxy-config` là essential tools
- **mTLS cert rotation**: automatic nhưng rotation failures cần monitoring (cert-manager alerts)
- **Traffic policy conflicts**: VirtualService + DestinationRule phải consistent; misconfig gây 503 loops
- **Observability cost**: tất cả L7 metrics shipped to Prometheus → storage cost tăng nhanh với nhiều services; dùng sampling
- **When NOT to use**: simple monolith hoặc < 5 services; overhead không justify; dùng Nginx/Traefik ingress thay thế

---

### Ghi chú – Kết thúc Docker/K8s roadmap
> Docker và Kubernetes roadmap đã hoàn thành. Tiếp theo có thể explore: eBPF networking, WASM/WASI workloads, hoặc deep dive vào Kafka internals.
