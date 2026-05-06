# Kubernetes RBAC & Policy Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. RBAC Advanced Patterns

### What – RBAC là gì?
RBAC (Role-Based Access Control) kiểm soát quyền truy cập vào Kubernetes API Server. Mọi request phải qua: Authentication → Authorization (RBAC) → Admission Control.

### How – Role vs ClusterRole

```yaml
# Role: namespace-scoped (chỉ trong 1 namespace)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
- apiGroups: [""]               # "" = core API group
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
  resourceNames: ["app-config", "feature-flags"]  # giới hạn resource cụ thể
---
# ClusterRole: cluster-scoped (áp dụng cho mọi namespace)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-monitor
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "namespaces", "pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["nodes", "pods"]
  verbs: ["get", "list"]
- nonResourceURLs: ["/metrics", "/healthz", "/readyz"]
  verbs: ["get"]    # cho phép access non-resource URLs
---
# RoleBinding: bind Role vào Subject trong namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-read-pods
  namespace: production
subjects:
- kind: User
  name: developer@company.com    # OIDC user email
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: dev-team                 # OIDC group
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: ci-cd-bot
  namespace: ci-cd               # ServiceAccount từ namespace khác
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
---
# ClusterRoleBinding: bind ClusterRole cho toàn cluster
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-global
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: cluster-monitor
  apiGroup: rbac.authorization.k8s.io
```

### How – Aggregated ClusterRoles

```yaml
# ClusterRole có thể aggregate nhiều roles tự động
# Kubernetes dùng aggregation cho view/edit/admin built-in roles

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: custom-app-viewer
  labels:
    rbac.authorization.k8s.io/aggregate-to-view: "true"    # auto-merge vào 'view' role
    rbac.authorization.k8s.io/aggregate-to-edit: "true"    # auto-merge vào 'edit' role
rules:
- apiGroups: ["myapp.example.com"]
  resources: ["myresources"]
  verbs: ["get", "list", "watch"]

# → Bất kỳ user nào có ClusterRoleBinding vào 'view' sẽ tự động thấy myresources
```

### How – ServiceAccount RBAC Pattern

```yaml
# Minimal ServiceAccount cho app
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: production
  annotations:
    # AWS: IRSA (IAM Roles for Service Accounts)
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/myapp-role
    # GCP: Workload Identity
    iam.gke.io/gcp-service-account: myapp@project.iam.gserviceaccount.com
automountServiceAccountToken: false    # không auto-mount token (secure)
---
# Chỉ cấp quyền tối thiểu cần thiết
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: myapp-role
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["myapp-config"]    # chỉ configmap cụ thể
  verbs: ["get", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["myapp-secrets"]
  verbs: ["get"]
---
# Pod spec
spec:
  serviceAccountName: myapp
  automountServiceAccountToken: true    # override SA level nếu cần
  volumes:
  - name: token
    projected:
      sources:
      - serviceAccountToken:
          audience: sts.amazonaws.com
          expirationSeconds: 3600        # short-lived token
          path: token
```

### How – RBAC Audit và Debug

```bash
# Kiểm tra quyền của user/service account
kubectl auth can-i get pods --as=developer@company.com
kubectl auth can-i get pods --as=developer@company.com -n production

# List tất cả quyền của user
kubectl auth can-i --list --as=developer@company.com -n production

# Kiểm tra ServiceAccount
kubectl auth can-i create deployments \
  --as=system:serviceaccount:production:myapp \
  -n production

# Dry run auth check
kubectl auth reconcile -f rbac-config.yaml --dry-run=client

# rbac-tool: audit tool
# Cài: kubectl krew install rbac-tool
kubectl rbac-tool whoami               # current user và roles
kubectl rbac-tool lookup developer     # tất cả bindings cho user
kubectl rbac-tool lookup -k ServiceAccount prometheus -n monitoring
kubectl rbac-tool who-can get pods -n production  # ai có quyền get pods?
kubectl rbac-tool visualize            # tạo graph visualization

# audit2rbac: tạo RBAC từ audit logs
# Từ audit logs của API server:
audit2rbac --filename audit.log --user ci-cd-bot > rbac-minimal.yaml
# → Tạo minimal RBAC dựa trên actual API calls
```

---

## 2. OPA Gatekeeper

### What – Gatekeeper là gì?
OPA Gatekeeper là Admission Controller webhook. Nó chặn và validate/mutate Kubernetes resources trước khi lưu vào etcd, dựa trên policies viết bằng Rego language.

### How – Gatekeeper Setup

```bash
# Cài Gatekeeper
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.15/deploy/gatekeeper.yaml

# Kiểm tra
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper
```

### How – ConstraintTemplate (define policy)

```yaml
# ConstraintTemplate: định nghĩa policy bằng Rego
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requireresourcelimits
spec:
  crd:
    spec:
      names:
        kind: RequireResourceLimits
      validation:
        openAPIV3Schema:
          type: object
          properties:
            cpu:
              type: string
              description: "Max CPU limit allowed"
            memory:
              type: string
              description: "Max memory limit allowed"
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requireresourcelimits

      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        not container.resources.limits.memory
        msg := sprintf("Container '%v' must have memory limit", [container.name])
      }

      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        not container.resources.limits.cpu
        msg := sprintf("Container '%v' must have CPU limit", [container.name])
      }

---
# ConstraintTemplate: require non-root user
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requirenonrootuser
spec:
  crd:
    spec:
      names:
        kind: RequireNonRootUser
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requirenonrootuser

      violation[{"msg": msg}] {
        input.review.object.kind == "Pod"
        container := input.review.object.spec.containers[_]
        # container chạy root (uid=0)
        container.securityContext.runAsUser == 0
        msg := sprintf("Container '%v' must not run as root", [container.name])
      }

      violation[{"msg": msg}] {
        input.review.object.kind == "Pod"
        container := input.review.object.spec.containers[_]
        # không set runAsNonRoot
        not container.securityContext.runAsNonRoot
        not input.review.object.spec.securityContext.runAsNonRoot
        msg := sprintf("Container '%v' must set runAsNonRoot: true", [container.name])
      }
```

### How – Constraint (apply policy)

```yaml
# Constraint: áp dụng policy cho resources
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireResourceLimits
metadata:
  name: require-resource-limits
spec:
  enforcementAction: deny    # deny | warn | dryrun
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    namespaces: ["production", "staging"]    # chỉ áp dụng cho namespaces này
    excludedNamespaces: ["kube-system", "gatekeeper-system"]
  parameters:
    cpu: "2000m"
    memory: "4Gi"

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireNonRootUser
metadata:
  name: require-non-root
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces: ["kube-system", "gatekeeper-system", "cert-manager"]

---
# Allowed registries policy
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: allowedregistries
spec:
  crd:
    spec:
      names:
        kind: AllowedRegistries
      validation:
        openAPIV3Schema:
          type: object
          properties:
            registries:
              type: array
              items:
                type: string
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package allowedregistries

      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        image := container.image
        not any_registry_matches(image)
        msg := sprintf("Container image '%v' is not from an allowed registry", [image])
      }

      any_registry_matches(image) {
        registry := input.parameters.registries[_]
        startswith(image, registry)
      }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: AllowedRegistries
metadata:
  name: allowed-registries
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    registries:
    - "123456789.dkr.ecr.us-east-1.amazonaws.com/"
    - "gcr.io/my-project/"
    - "ghcr.io/my-org/"
```

```bash
# Xem violations
kubectl get constraints
kubectl describe requireresourcelimits require-resource-limits
# Violations:
# - Message: Container 'app' must have memory limit
#   Kind: Pod, Name: myapp-xxx, Namespace: production

# Test policy (dry-run)
kubectl apply -f pod.yaml --dry-run=server

# Audit existing resources (không chỉ new ones)
kubectl get requireresourcelimits require-resource-limits -o json | \
  jq '.status.violations'
```

---

## 3. Kyverno

### What – Kyverno là gì?
Kyverno là Policy Engine native cho Kubernetes (không cần học Rego). Policies viết bằng YAML, hỗ trợ: validate, mutate, generate, verify image signatures.

### How – Kyverno Setup

```bash
# Cài Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3    # HA setup
```

### How – ClusterPolicy Examples

```yaml
# 1. Validate: require labels
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce    # Enforce | Audit
  background: true                    # audit existing resources
  rules:
  - name: require-app-label
    match:
      any:
      - resources:
          kinds: ["Pod", "Deployment", "StatefulSet"]
          namespaces: ["production", "staging"]
    validate:
      message: "Label 'app' is required"
      pattern:
        metadata:
          labels:
            app: "?*"    # ?* = non-empty string

  - name: require-owner-label
    match:
      any:
      - resources:
          kinds: ["Namespace"]
    validate:
      message: "Namespace must have 'owner' label"
      pattern:
        metadata:
          labels:
            owner: "?*"

---
# 2. Mutate: auto-add labels và resource limits
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-labels
spec:
  rules:
  - name: add-env-label
    match:
      any:
      - resources:
          kinds: ["Pod"]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            +(managed-by): kyverno    # + = add only if not present
        spec:
          containers:
          - (name): "*"               # match all containers
            resources:
              limits:
                +(memory): 512Mi      # default memory limit nếu không set
                +(cpu): 500m

  - name: add-security-context
    match:
      any:
      - resources:
          kinds: ["Pod"]
    mutate:
      patchStrategicMerge:
        spec:
          +(securityContext):
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          containers:
          - (name): "*"
            +(securityContext):
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop: ["ALL"]

---
# 3. Generate: auto-create NetworkPolicy khi tạo Namespace
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: generate-network-policy
spec:
  rules:
  - name: default-deny-ingress
    match:
      any:
      - resources:
          kinds: ["Namespace"]
          selector:
            matchLabels:
              environment: production
    generate:
      apiVersion: networking.k8s.io/v1
      kind: NetworkPolicy
      name: default-deny-ingress
      namespace: "{{request.object.metadata.name}}"
      synchronize: true    # update generated resource nếu policy thay đổi
      data:
        spec:
          podSelector: {}
          policyTypes:
          - Ingress

---
# 4. Verify Image: enforce image signing (cosign)
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
spec:
  validationFailureAction: Enforce
  background: false
  webhookTimeoutSeconds: 30
  rules:
  - name: verify-cosign-signature
    match:
      any:
      - resources:
          kinds: ["Pod"]
          namespaces: ["production"]
    verifyImages:
    - imageReferences:
      - "123456789.dkr.ecr.us-east-1.amazonaws.com/*"
      attestors:
      - count: 1
        entries:
        - keyless:
            subject: "https://github.com/my-org/my-repo/.github/workflows/*"
            issuer: "https://token.actions.githubusercontent.com"
      # Verify SBOM attestation
      attestations:
      - predicateType: https://spdx.dev/Document
        conditions:
        - all:
          - key: "{{ creationInfo.creators }}"
            operator: AllIn
            value: ["Tool: syft"]
```

### How – Policy Reports

```bash
# Xem policy reports
kubectl get policyreport -A    # namespace-scoped results
kubectl get clusterpolicyreport  # cluster-scoped results

# Chi tiết
kubectl describe policyreport -n production

# Kyverno CLI: test policies trước khi apply
kyverno apply policy.yaml --resource pod.yaml
# Pass: 1, Fail: 0

# Test với các test cases
kyverno test .    # chạy tất cả tests trong thư mục
```

---

## 4. Pod Security Standards (Replacement cho PSP)

### How – Pod Security Admission

```yaml
# Enforce Pod Security Standards trên namespace
# Levels: privileged, baseline, restricted
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # enforce: block non-compliant pods
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    # audit: log violations nhưng không block
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
    # warn: return warning khi apply
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
```

```yaml
# Restricted level yêu cầu:
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault    # hoặc Localhost
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop: ["ALL"]         # drop ALL capabilities
        # add chỉ được: NET_BIND_SERVICE (nếu cần port < 1024)
```

```bash
# Check existing pods compliance
kubectl label --dry-run=server --overwrite ns production \
  pod-security.kubernetes.io/enforce=restricted
# → Hiện số pods sẽ bị block

# Apply dần dần: warn trước, sau đó enforce
# Step 1: warn mode (không block)
kubectl label ns production pod-security.kubernetes.io/warn=restricted

# Step 2: audit mode (log only)
kubectl label ns production pod-security.kubernetes.io/audit=restricted

# Step 3: sau khi fix tất cả violations
kubectl label ns production pod-security.kubernetes.io/enforce=restricted
```

---

### Compare – Policy Engines

| | OPA Gatekeeper | Kyverno | Pod Security Admission |
|--|----------------|---------|------------------------|
| **Language** | Rego (learn needed) | YAML (native K8s) | Built-in levels |
| **Validate** | ✅ | ✅ | ✅ |
| **Mutate** | Limited | ✅ | ❌ |
| **Generate** | ❌ | ✅ | ❌ |
| **Image verify** | ❌ | ✅ (cosign) | ❌ |
| **Learning curve** | High (Rego) | Low | Very Low |
| **Ecosystem** | Large (OPA ecosystem) | Growing | Built-in |
| **Best for** | Complex custom policies | Full lifecycle | Standard security baseline |

### Trade-offs
- Gatekeeper: powerful nhưng Rego khó debug; dùng khi cần policies phức tạp
- Kyverno: easier YAML syntax nhưng mutation có thể làm confuse developers
- Pod Security: built-in, zero overhead nhưng chỉ 3 levels (privileged/baseline/restricted)
- enforcementAction: warn → dryrun → deny (gradual rollout approach)

### Real-world Usage
```bash
# RBAC least-privilege checklist
# 1. Kiểm tra ServiceAccounts với quyền rộng
kubectl get clusterrolebindings -o json | jq '
  .items[] |
  select(.subjects[]?.kind == "ServiceAccount") |
  {
    name: .metadata.name,
    role: .roleRef.name,
    subjects: [.subjects[] | select(.kind == "ServiceAccount") | "\(.namespace)/\(.name)"]
  }'

# 2. Tìm Pods với automountServiceAccountToken: true và quyền cluster-admin
kubectl get pods -A -o json | jq '
  .items[] |
  select(.spec.automountServiceAccountToken != false) |
  "\(.metadata.namespace)/\(.metadata.name): \(.spec.serviceAccountName)"'

# 3. Kiểm tra ai có quyền exec vào pods (high-risk)
kubectl rbac-tool who-can create pods/exec -n production

# 4. Policy violations report
kubectl get policyreport -A -o json | jq '
  [.items[] |
   .results[] |
   select(.result == "fail") |
   {namespace: .resources[0].namespace, name: .resources[0].name, policy: .policy, message: .message}]'

# 5. Kyverno policy audit (không dừng violations, chỉ report)
kubectl get clusterpolicy -o json | jq '
  .items[] |
  "\(.metadata.name): enforce=\(.spec.validationFailureAction)"'
```

### Ghi chú – Chủ đề tiếp theo
> Observability Deep – kube-prometheus-stack chi tiết, custom Grafana dashboards, OpenTelemetry Collector, distributed tracing với Jaeger/Tempo

---

*Cập nhật lần cuối: 2026-05-06*
