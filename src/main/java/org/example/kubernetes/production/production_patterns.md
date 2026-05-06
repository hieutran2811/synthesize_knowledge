# Kubernetes Production Patterns Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Zero-Downtime Deployment Checklist

### What – Zero-Downtime Deployment
Zero-downtime đòi hỏi tất cả các layer hoạt động đúng: Pod lifecycle, Service routing, health probes, và graceful shutdown.

### How – Pod Lifecycle Configuration

```yaml
spec:
  template:
    spec:
      # 1. Termination Grace Period: thời gian cho phép pod shutdown gracefully
      terminationGracePeriodSeconds: 60    # >= thời gian shutdown app thực sự

      containers:
      - name: app
        image: myapp:v2

        # 2. Readiness Probe: pod chỉ nhận traffic khi READY
        readinessProbe:
          httpGet:
            path: /health/readiness
            port: 8080
          initialDelaySeconds: 10     # đợi 10s trước khi check
          periodSeconds: 5            # check mỗi 5s
          failureThreshold: 3         # 3 lần fail → not ready
          successThreshold: 1         # 1 lần pass → ready

        # 3. Liveness Probe: pod bị restart khi DEAD
        livenessProbe:
          httpGet:
            path: /health/liveness
            port: 8080
          initialDelaySeconds: 30     # sau startup probe
          periodSeconds: 10
          failureThreshold: 3
          timeoutSeconds: 5

        # 4. Startup Probe: cho apps chậm start (Java, etc.)
        startupProbe:
          httpGet:
            path: /health/startup
            port: 8080
          failureThreshold: 30        # max 30 * 10s = 5 phút để start
          periodSeconds: 10

        # 5. PreStop Hook: drain inflight requests trước khi container stop
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/sh
              - -c
              - |
                # Signal app để stop accepting new requests
                kill -SIGTERM 1
                # Đợi inflight requests hoàn thành
                sleep 15
        # Tổng thời gian: preStop(15s) + app shutdown + SIGKILL buffer

        # 6. Resources: phải set để CA/VPA/scheduler hoạt động đúng
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 1Gi
            cpu: "1"
```

### How – Spring Boot Graceful Shutdown Example

```yaml
# application.yaml (Spring Boot)
server:
  shutdown: graceful        # Spring Boot 2.3+: wait for active requests
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s   # tối đa 30s để complete requests

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      probes:
        enabled: true       # /actuator/health/liveness, /actuator/health/readiness
  health:
    livenessState:
      enabled: true
    readinessState:
      enabled: true
```

```yaml
# Kubernetes probes cho Spring Boot
livenessProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
startupProbe:
  httpGet:
    path: /actuator/health/liveness
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 10"]   # đợi LB drain connections
```

### How – Deployment Rolling Update Zero-Downtime

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # 1 extra pod trong khi update
      maxUnavailable: 0    # KHÔNG cho phép bất kỳ pod nào unavailable
                           # → zero-downtime guaranteed
                           # Tuy nhiên: cần đủ resources cho extra pod
  # Nếu không đủ resource: dùng maxUnavailable: 1 và maxSurge: 1
```

---

## 2. PodDisruptionBudget (PDB)

### What – PDB là gì?
PDB đảm bảo số lượng minimum pods available trong khi có disruptions (node drain, Cluster Autoscaler, voluntary disruptions). Bảo vệ availability khi cluster bảo trì.

### How – PDB Configuration

```yaml
# minAvailable: ít nhất N pods phải available
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: production
spec:
  minAvailable: 2           # hoặc "50%" (ít nhất 50%)
  selector:
    matchLabels:
      app: myapp

---
# maxUnavailable: tối đa N pods có thể unavailable
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
  namespace: production
spec:
  maxUnavailable: 1         # hoặc "25%"
  selector:
    matchLabels:
      app: myapp
```

```bash
# Xem PDB status
kubectl get pdb -n production
# NAME       MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# myapp-pdb  2               N/A               1                     2d
# → 3 replicas - 2 minAvailable = 1 allowed disruption

# Node drain: CA/admin drain node, PDB prevents evicting too many pods
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data

# Nếu PDB không cho evict: drain sẽ đợi hoặc lỗi
# PDB violations log:
kubectl get events -n production | grep "PodDisruptionBudget"
```

---

## 3. TopologySpreadConstraints

### What – TopologySpreadConstraints là gì?
Phân tán Pods đều giữa các topology zones (AZ, nodes, regions) để maximize availability khi 1 zone fail.

### How – Multi-AZ Spread

```yaml
spec:
  topologySpreadConstraints:
  # 1. Spread đều giữa availability zones
  - maxSkew: 1                          # tối đa lệch 1 pod giữa các zones
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule    # DoNotSchedule | ScheduleAnyway
    labelSelector:
      matchLabels:
        app: myapp
    # minDomains: 3  # K8s 1.24+: phải có ít nhất 3 domains (AZs)

  # 2. Spread đều giữa nodes
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway   # prefer spread, nhưng không block
    labelSelector:
      matchLabels:
        app: myapp

  # 3. Spread đều giữa nodes theo node type
  - maxSkew: 2
    topologyKey: node.kubernetes.io/instance-type
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: myapp
    # matchLabelKeys: ["pod-template-hash"]  # K8s 1.25+: ignore different versions
```

```yaml
# Kết hợp với podAntiAffinity (defense in depth)
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: myapp
      topologyKey: topology.kubernetes.io/zone
      # → hard rule: không 2 pods cùng AZ
      # Kết hợp với topologySpreadConstraints maxSkew: 1 để spread đều

    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: myapp
        topologyKey: kubernetes.io/hostname
        # → soft rule: prefer khác nodes
```

---

## 4. Multi-Tenancy Patterns

### What – Multi-Tenancy trong K8s
Multi-tenancy cho phép nhiều teams/customers dùng chung 1 cluster với isolation: namespace isolation, RBAC, ResourceQuota, NetworkPolicy.

### How – Namespace-based Multi-Tenancy

```yaml
# Namespace hierarchy:
# cluster → team namespaces → environment namespaces

# Team A namespace
apiVersion: v1
kind: Namespace
metadata:
  name: team-a-production
  labels:
    team: team-a
    env: production
    pod-security.kubernetes.io/enforce: restricted

---
# ResourceQuota: giới hạn tổng resources của namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a-production
spec:
  hard:
    # Compute
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    # Storage
    requests.storage: 500Gi
    persistentvolumeclaims: "20"
    # Object count
    pods: "100"
    services: "20"
    configmaps: "50"
    secrets: "30"
    deployments.apps: "20"
    replicasets.apps: "40"

---
# LimitRange: default limits và min/max per container
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-limits
  namespace: team-a-production
spec:
  limits:
  - type: Container
    default:              # mặc định nếu không set limits
      memory: 512Mi
      cpu: 500m
    defaultRequest:       # mặc định nếu không set requests
      memory: 256Mi
      cpu: 100m
    max:                  # giới hạn tối đa
      memory: 4Gi
      cpu: "4"
    min:                  # tối thiểu
      memory: 64Mi
      cpu: 10m
  - type: Pod
    max:
      memory: 8Gi         # tổng tất cả containers trong pod
      cpu: "8"
  - type: PersistentVolumeClaim
    max:
      storage: 50Gi
    min:
      storage: 1Gi

---
# NetworkPolicy: namespace isolation
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
  namespace: team-a-production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Chỉ nhận traffic từ cùng namespace
  - from:
    - podSelector: {}
  # Nhận từ monitoring namespace
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - port: 9090
  # Nhận từ ingress-nginx
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
  egress:
  # DNS
  - ports:
    - port: 53
      protocol: UDP
  # Cùng namespace
  - to:
    - podSelector: {}
  # External HTTPS
  - ports:
    - port: 443
```

### How – Namespace Provisioning với Kyverno

```yaml
# Auto-provision tất cả resources khi tạo namespace với label team=xxx
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: provision-team-namespace
spec:
  rules:
  - name: create-resource-quota
    match:
      any:
      - resources:
          kinds: ["Namespace"]
          selector:
            matchExpressions:
            - key: team
              operator: Exists
    generate:
      apiVersion: v1
      kind: ResourceQuota
      name: team-quota
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec:
          hard:
            requests.cpu: "10"
            requests.memory: 20Gi
            limits.cpu: "20"
            limits.memory: 40Gi
            pods: "50"

  - name: create-limit-range
    match:
      any:
      - resources:
          kinds: ["Namespace"]
          selector:
            matchExpressions:
            - key: team
              operator: Exists
    generate:
      apiVersion: v1
      kind: LimitRange
      name: default-limits
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec:
          limits:
          - type: Container
            default:
              memory: 512Mi
              cpu: 500m
            defaultRequest:
              memory: 128Mi
              cpu: 50m

  - name: create-network-policy
    match:
      any:
      - resources:
          kinds: ["Namespace"]
          selector:
            matchExpressions:
            - key: team
              operator: Exists
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: default-deny-ingress
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        spec:
          podSelector: {}
          policyTypes: ["Ingress"]
```

---

## 5. Production Deployment Checklist

### How – Pre-Deployment Checklist

```bash
#!/bin/bash
# pre-deploy-check.sh: chạy trước khi deploy lên production

set -euo pipefail
NAMESPACE="production"
APP="myapp"
IMAGE="$1"    # image tag được pass vào

echo "=== Pre-Deployment Checks ==="

# 1. Check cluster connectivity
kubectl cluster-info
echo "✓ Cluster accessible"

# 2. Check namespace exists
kubectl get namespace $NAMESPACE
echo "✓ Namespace $NAMESPACE exists"

# 3. Check image exists và đã được scan
IMAGE_DIGEST=$(docker manifest inspect $IMAGE | jq -r '.config.digest')
echo "✓ Image digest: $IMAGE_DIGEST"

# 4. Check current deployment health
READY=$(kubectl get deployment/$APP -n $NAMESPACE \
  -o jsonpath='{.status.readyReplicas}')
DESIRED=$(kubectl get deployment/$APP -n $NAMESPACE \
  -o jsonpath='{.spec.replicas}')
if [ "$READY" != "$DESIRED" ]; then
  echo "✗ Deployment not fully ready: $READY/$DESIRED"
  exit 1
fi
echo "✓ Current deployment healthy: $READY/$DESIRED"

# 5. Check PDB allows disruption
ALLOWED=$(kubectl get pdb ${APP}-pdb -n $NAMESPACE \
  -o jsonpath='{.status.disruptionsAllowed}' 2>/dev/null || echo "0")
if [ "$ALLOWED" -lt 1 ]; then
  echo "✗ PDB does not allow any disruptions"
  exit 1
fi
echo "✓ PDB allows $ALLOWED disruptions"

# 6. Check HPA không đang scale
HPA_STATUS=$(kubectl get hpa ${APP}-hpa -n $NAMESPACE \
  -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}' 2>/dev/null)
echo "✓ HPA status: $HPA_STATUS"

# 7. Check recent errors
RECENT_ERRORS=$(kubectl get events -n $NAMESPACE \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -5)
echo "Recent warnings:"
echo "$RECENT_ERRORS"

echo ""
echo "=== All checks passed, ready to deploy ==="
```

```bash
#!/bin/bash
# deploy.sh: full deployment với health monitoring

APP="myapp"
NAMESPACE="production"
NEW_IMAGE="$1"
TIMEOUT=600    # 10 phút

echo "Deploying $NEW_IMAGE..."

# Update image
kubectl set image deployment/$APP \
  app=$NEW_IMAGE \
  -n $NAMESPACE \
  --record

# Monitor rollout
if ! kubectl rollout status deployment/$APP \
  -n $NAMESPACE \
  --timeout=${TIMEOUT}s; then
  echo "❌ Rollout failed! Rolling back..."
  kubectl rollout undo deployment/$APP -n $NAMESPACE
  kubectl rollout status deployment/$APP -n $NAMESPACE --timeout=300s
  echo "✅ Rollback complete"
  exit 1
fi

echo "✅ Deployment successful"

# Post-deploy verification
echo "Running post-deploy checks..."
sleep 30    # đợi app fully ready

# Smoke test
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  https://myapp.company.com/health)
if [ "$HTTP_STATUS" != "200" ]; then
  echo "❌ Smoke test failed: HTTP $HTTP_STATUS"
  kubectl rollout undo deployment/$APP -n $NAMESPACE
  exit 1
fi

echo "✅ Post-deploy checks passed"
echo "Deployed: $NEW_IMAGE"
```

---

## 6. Cost Optimization

### How – Resource Rightsizing

```bash
# Xem actual vs requested resources
kubectl resource-capacity --sort cpu.util
# NODE       CPU REQUESTS    CPU LIMITS    CPU UTIL
# node1      45% (900m/2)    80% (1600m)   32% (640m)

# VPA recommendations cho tất cả namespaces
kubectl get vpa -A -o json | jq -r '
  .items[] |
  "\(.metadata.namespace)/\(.metadata.name): " +
  (
    .status.recommendation.containerRecommendations[]? |
    "cpu=\(.target.cpu), mem=\(.target.memory)"
  )'

# Xem pods không có limits (sẽ bị capped bởi LimitRange)
kubectl get pods -A -o json | jq -r '
  .items[] |
  .metadata as $meta |
  .spec.containers[] |
  select(.resources.limits == null) |
  "\($meta.namespace)/\($meta.name): container=\(.name)"'

# Xem pods có resources quá lớn (over-provisioned)
kubectl top pods -n production --sort-by=cpu | head -20
```

### How – Spot Instances cho Non-Critical Workloads

```yaml
# Node selector cho spot instances
spec:
  template:
    spec:
      nodeSelector:
        karpenter.sh/capacity-type: spot    # prefer spot
      tolerations:
      - key: karpenter.sh/capacity-type
        value: spot
        effect: NoSchedule
      # Topological spread: không đặt tất cả pods trên spot
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: karpenter.sh/capacity-type
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: myapp
```

---

### Compare – Production Checklist

| Category | Must Have | Nice to Have |
|----------|-----------|--------------|
| **Availability** | PDB, readinessProbe, rolling update | TopologySpread, anti-affinity |
| **Reliability** | livenessProbe, startupProbe, graceful shutdown | Circuit breaker, retry policy |
| **Security** | Non-root, read-only FS, seccomp, NetworkPolicy | OPA/Kyverno, mTLS |
| **Observability** | Structured logs, metrics endpoint, alerts | Distributed tracing, SLOs |
| **Cost** | Resource requests/limits | VPA, spot instances, HPA |
| **Deployment** | Rolling update, health checks | Blue-green, canary, ArgoCD |

### Trade-offs
- maxUnavailable: 0: zero-downtime nhưng cần extra resources (maxSurge pods); có thể slow nếu resources tight
- TopologySpreadConstraints DoNotSchedule: đảm bảo spread nhưng có thể block scheduling nếu zone mất balance
- Multi-tenancy Namespace isolation: đơn giản nhưng không strong isolation như VMs; không phù hợp cho hostile tenants
- Kyverno auto-generate resources: giảm toil nhưng synchronize: true có thể override manual changes

### Real-world Usage
```bash
# Health check toàn cluster
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Top resource consumers
kubectl top pods -A --sort-by=memory | head -20
kubectl top nodes

# Xem recent events theo namespace
kubectl get events -n production \
  --sort-by='.lastTimestamp' \
  --field-selector type=Warning \
  | tail -20

# Check deployment health tất cả namespaces
kubectl get deployments -A | awk 'NR>1 && $3 != $4 {
  printf "%-20s %-30s %s/%s\n", $1, $2, $4, $3
}'

# Audit: pods chạy privileged
kubectl get pods -A -o json | jq -r '
  .items[] |
  select(
    .spec.containers[].securityContext.privileged == true or
    .spec.hostNetwork == true or
    .spec.hostPID == true
  ) |
  "\(.metadata.namespace)/\(.metadata.name)"'

# ResourceQuota utilization
kubectl get resourcequota -A -o json | jq -r '
  .items[] |
  "\(.metadata.namespace)/\(.metadata.name):",
  (
    .status.hard | to_entries[] |
    . as $h |
    .key as $k |
    "\(.key): used=\(($h | @base64d | fromjson?)).status.used[\($k)], hard=\($h.value)"
  )' 2>/dev/null

# Verify PDB cho tất cả production deployments
kubectl get pdb -n production
kubectl get deployment -n production -o name | \
  sed 's|deployment.apps/||' | \
  xargs -I{} kubectl get pdb | grep {}
```

### Ghi chú – Tổng kết
> Đã hoàn thành toàn bộ Kubernetes deep dive series:
> - Workloads (Deployment strategies, StatefulSet, Job patterns)
> - Networking (CNI: Calico/Cilium, NetworkPolicy, Gateway API, Istio)
> - Storage (CSI, Snapshots, Velero backup)
> - Security (RBAC, OPA Gatekeeper, Kyverno, Pod Security)
> - Observability (kube-prometheus-stack, OpenTelemetry, Grafana)
> - Helm (Chart authoring, Hooks, Library charts, Helmfile)
> - GitOps/ArgoCD (ApplicationSet, multi-cluster, Image Updater)
> - Autoscaling (HPA/VPA/KEDA, Cluster Autoscaler, Karpenter)
> - Production Patterns (zero-downtime, PDB, multi-tenancy, cost optimization)

---

*Cập nhật lần cuối: 2026-05-06*
