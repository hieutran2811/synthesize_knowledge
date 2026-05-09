# Kubernetes Advanced – RBAC, Helm, GitOps

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. RBAC – Role-Based Access Control

### What – RBAC là gì?
Kubernetes RBAC kiểm soát **ai** (Subject) có thể làm **gì** (Verb) với **tài nguyên nào** (Resource). Áp dụng cho cả humans (kubectl users) lẫn in-cluster workloads (ServiceAccounts).

### How – Core Objects

```
Subject:   User | Group | ServiceAccount
   ↓ bound via
RoleBinding (namespace-scoped) | ClusterRoleBinding (cluster-scoped)
   ↓ references
Role (namespace-scoped)        | ClusterRole (cluster-scoped)
   ↓ contains
PolicyRules: [apiGroups, resources, verbs]
```

### How – Role & RoleBinding

```yaml
# Role: permissions trong một namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: order-service-role
  namespace: production
rules:
  # Core API group (pods, services, configmaps, secrets)
  - apiGroups: [""]
    resources: ["pods", "services", "endpoints"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch", "create", "update"]
  # Apps API group (deployments, replicasets)
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  # Secrets: tách riêng (principle of least privilege)
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
    resourceNames: ["order-service-secret"]  # specific secret only!
---
# RoleBinding: gán Role cho ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: order-service-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: order-service-sa
    namespace: production
roleRef:
  kind: Role
  name: order-service-role
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# ServiceAccount cho order-service
apiVersion: v1
kind: ServiceAccount
metadata:
  name: order-service-sa
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/order-service-role  # IRSA
automountServiceAccountToken: false   # disable unless needed
```

```yaml
# ClusterRole: cross-namespace permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-reader
rules:
  - apiGroups: [""]
    resources: ["nodes", "pods", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes", "pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-monitoring
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
roleRef:
  kind: ClusterRole
  name: monitoring-reader
  apiGroup: rbac.authorization.k8s.io
```

### How – RBAC for Developers (kubeconfig)

```bash
# Create user certificate (kubeadm cluster)
openssl genrsa -out dev-user.key 2048
openssl req -new -key dev-user.key -out dev-user.csr -subj "/CN=alice/O=developers"
openssl x509 -req -in dev-user.csr \
    -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key \
    -CAcreateserial -out dev-user.crt -days 365

# kubeconfig entry
kubectl config set-credentials alice \
    --client-certificate=dev-user.crt --client-key=dev-user.key
kubectl config set-context alice-context \
    --cluster=my-cluster --namespace=staging --user=alice

# Grant alice read-only in staging
kubectl create rolebinding alice-view \
    --clusterrole=view --user=alice --namespace=staging
```

```bash
# Test RBAC permissions
kubectl auth can-i get pods --namespace=production --as=alice
kubectl auth can-i delete deployments --namespace=production --as=system:serviceaccount:production:order-service-sa

# List all permissions for a service account
kubectl auth can-i --list --namespace=production \
    --as=system:serviceaccount:production:order-service-sa
```

---

## 2. Network Policies

### What – Network Policies là gì?
Kiểm soát **traffic in/out** của Pods. Mặc định: tất cả pods có thể communicate với nhau. Network Policies cho phép whitelist theo namespace, pod labels, ports.

```yaml
# Default deny all ingress và egress (zero-trust baseline)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}   # applies to all pods in namespace
  policyTypes:
    - Ingress
    - Egress
```

```yaml
# Allow order-service ingress từ nginx-ingress, egress đến postgres + kafka
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-service-netpol
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: order-service
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Accept từ ingress controller
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
          podSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
    # Accept từ prometheus scrape
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # Allow to postgres
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    # Allow to kafka
    - to:
        - podSelector:
            matchLabels:
              app: kafka
      ports:
        - protocol: TCP
          port: 9092
    # Allow DNS resolution
    - to: []
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # Allow HTTPS to external (e.g., Stripe API)
    - to: []
      ports:
        - protocol: TCP
          port: 443
```

---

## 3. Helm – Kubernetes Package Manager

### What – Helm là gì?
**Helm** là package manager cho Kubernetes. Một **Chart** là tập hợp YAML templates với values. Giải quyết: DRY configs, versioning, rollbacks, parameterization.

### How – Chart Structure

```
order-service/              (chart directory)
├── Chart.yaml              (metadata: name, version, appVersion)
├── values.yaml             (default values)
├── values-staging.yaml     (staging overrides)
├── values-prod.yaml        (prod overrides)
├── templates/
│   ├── _helpers.tpl        (named templates / partials)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── hpa.yaml
│   └── NOTES.txt           (post-install instructions)
└── charts/                 (sub-charts / dependencies)
```

```yaml
# Chart.yaml
apiVersion: v2
name: order-service
description: Order service Helm chart
type: application
version: 1.3.0          # chart version
appVersion: "2.1.0"     # app version
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
```

```yaml
# values.yaml
replicaCount: 2

image:
  repository: myregistry/order-service
  tag: ""          # defaults to Chart.appVersion
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: api.example.com
      paths:
        - path: /api/orders
          pathType: Prefix
  tls:
    - secretName: api-tls
      hosts:
        - api.example.com

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70

postgresql:
  enabled: false   # use external DB in prod

env:
  SPRING_PROFILES_ACTIVE: prod
  JAVA_OPTS: "-XX:MaxRAMPercentage=75.0"

secrets:
  dbPassword: ""   # override in prod values
  jwtSecret: ""
```

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "order-service.fullname" . }}
  labels:
    {{- include "order-service.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "order-service.selectorLabels" . | nindent 6 }}
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "order-service.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "order-service.serviceAccountName" . }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          env:
            {{- range $key, $val := .Values.env }}
            - name: {{ $key }}
              value: {{ $val | quote }}
            {{- end }}
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "order-service.fullname" . }}-secret
                  key: dbPassword
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: {{ .Values.service.targetPort }}
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

```bash
# Helm CLI usage
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Install chart
helm install order-service ./order-service \
    -f values-prod.yaml \
    --namespace production \
    --create-namespace \
    --set image.tag=2.1.0

# Upgrade
helm upgrade order-service ./order-service \
    -f values-prod.yaml \
    --set image.tag=2.2.0 \
    --atomic              # rollback automatically if fails
    --timeout 5m

# Rollback
helm rollback order-service 1   # roll back to revision 1
helm history order-service       # show revision history

# Diff before apply (helm-diff plugin)
helm diff upgrade order-service ./order-service -f values-prod.yaml
```

---

## 4. GitOps – ArgoCD

### What – GitOps là gì?
**GitOps** = Git là single source of truth cho cluster state. Mọi change đi qua Git (PR → review → merge). Operator (ArgoCD, Flux) sync cluster state với Git.

```
Developer → Git PR → Review → Merge → ArgoCD detects diff → Sync to cluster
                                              ↑
                                   Continuous reconciliation
```

### How – ArgoCD Setup

```yaml
# ArgoCD Application CRD
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: order-service
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io  # cleanup on delete
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/k8s-manifests.git
    targetRevision: main
    path: apps/order-service/overlays/production  # kustomize path
    # Helm alternative:
    # chart: order-service
    # helm:
    #   valueFiles:
    #     - values-prod.yaml
    #   parameters:
    #     - name: image.tag
    #       value: "2.1.0"
  destination:
    server: https://kubernetes.default.svc  # in-cluster
    namespace: production
  syncPolicy:
    automated:
      prune: true       # delete resources removed from git
      selfHeal: true    # revert manual cluster changes
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - RespectIgnoreDifferences=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas   # ignore HPA-managed replicas
```

```yaml
# Kustomize: base + overlays pattern
# base/deployment.yaml (shared config)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: order-service
          image: order-service:latest
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
---
# overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: production
bases:
  - ../../base
patchesStrategicMerge:
  - deployment-patch.yaml
images:
  - name: order-service
    newTag: "2.1.0"
---
# overlays/production/deployment-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: order-service
          resources:
            limits:
              cpu: "1"
              memory: 512Mi
```

### How – Image Updater (CI/CD to GitOps)

```yaml
# ArgoCD Image Updater: tự động update image tag trong git
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: order-service
  annotations:
    argocd-image-updater.argoproj.io/image-list: order=myregistry/order-service
    argocd-image-updater.argoproj.io/order.update-strategy: semver
    argocd-image-updater.argoproj.io/order.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main
```

```yaml
# Flux (alternative to ArgoCD)
# GitRepository source
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: k8s-manifests
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/myorg/k8s-manifests
  ref:
    branch: main
---
# Kustomization (Flux)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: order-service
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: k8s-manifests
  path: "./apps/order-service/production"
  prune: true
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: order-service
      namespace: production
```

---

## 5. Advanced Scheduling

```yaml
# Pod anti-affinity: spread across nodes
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: order-service
          topologyKey: kubernetes.io/hostname  # one pod per node
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: order-service
            topologyKey: topology.kubernetes.io/zone  # spread across AZs

# Topology spread (K8s 1.19+, preferred over anti-affinity)
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: order-service

# Taints & Tolerations: dedicated nodes
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "order-processing"
      effect: "NoSchedule"
  nodeSelector:
    node-type: order-processing
```

---

## 6. Compare & Trade-offs

### Compare – ArgoCD vs Flux

| | ArgoCD | Flux v2 |
|--|--------|---------|
| UI | Excellent web UI | CLI-focused (Weave GitOps UI plugin) |
| Multi-tenancy | AppProject, RBAC | Multiple controllers |
| Image automation | Image Updater (separate) | Built-in ImageUpdateAutomation |
| Notifications | Built-in | Separate Notification Controller |
| CRD approach | Application CRD | Multiple CRDs (GitRepo, Kustomization) |
| Multi-cluster | ApplicationSet | Cluster API integration |
| Learning curve | Moderate | Steeper |
| Khi dùng | Need UI, team adoption | K8s-native, pure GitOps purist |

### Compare – Kustomize vs Helm

| | Kustomize | Helm |
|--|-----------|------|
| Templating | Patch-based (YAML stays valid) | Go templates (hard to read) |
| Package distribution | None (use git) | Helm repo / OCI registry |
| Versioning | Git tags | Chart version |
| Dependencies | Not built-in | `dependencies` in Chart.yaml |
| Hooks | Limited | Pre/post hooks |
| Testing | kubectl validate | helm test, helm lint |
| Khi dùng | Internal apps, simple config | Third-party apps, complex packaging |

### Trade-offs
- **GitOps**: tăng auditability và traceability nhưng slow feedback loop (commit → sync delay); cần fast path cho hotfix
- **Helm**: giảm YAML duplication nhưng Go templates làm khó debug; dùng `helm template` để debug rendered YAML
- **RBAC**: least privilege giảm blast radius nhưng tốn effort setup; dùng `kubectl auth can-i --list` để audit
- **Network Policies**: tăng security nhưng misconfiguration block traffic; test trong staging trước

---

### Ghi chú – Chủ đề tiếp theo
> **Service Mesh**: Istio/Linkerd, mTLS, traffic management (VirtualService/DestinationRule), observability
