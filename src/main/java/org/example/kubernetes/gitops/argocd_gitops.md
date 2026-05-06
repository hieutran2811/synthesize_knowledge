# ArgoCD & GitOps Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. GitOps Principles

### What – GitOps là gì?
GitOps là operational model dùng Git là source of truth cho declarative infrastructure và applications. Thay vì CI push deploy commands, một agent liên tục sync Git state → Cluster state.

```
GitOps Flow:
Developer → Git Push → PR → Merge (approved)
                              ↓
                         ArgoCD detects diff
                              ↓
                    ArgoCD syncs Git → Cluster
                              ↓
                    Drift detection (Cluster ≠ Git)
                              ↓
                    ArgoCD auto-heal hoặc alert
```

---

## 2. ArgoCD Architecture

### How – ArgoCD Components

```
ArgoCD Components:
├── argocd-server (API Server + Web UI)
├── argocd-repo-server (clone repos, render templates)
├── argocd-application-controller (sync + health)
├── argocd-dex-server (OIDC provider)
└── argocd-redis (caching)

Application sync process:
1. repo-server clone Git repo + render Helm/Kustomize/plain YAML
2. application-controller compare rendered YAML vs cluster state
3. If diff: sync (apply to cluster)
4. Health assessment: check resource health
```

### How – Cài đặt ArgoCD HA

```bash
# HA install
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml

# hoặc Helm (recommended)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values argocd-values.yaml
```

```yaml
# argocd-values.yaml
configs:
  params:
    server.insecure: false
    server.enable.gzip: true
  cm:
    # Timeout for sync operations
    timeout.reconciliation: 180s
    # Repository connection timeout
    repository.timeout: 120s
    # OIDC
    oidc.config: |
      name: Google
      issuer: https://accounts.google.com
      clientID: xxx.apps.googleusercontent.com
      clientSecret: $oidc-google-secret:clientSecret
      requestedScopes: ["openid", "profile", "email", "groups"]
    # App health checks (custom)
    resource.customizations.health.argoproj.io_Application: |
      hs = {}
      hs.status = "Progressing"
      hs.message = ""
      if obj.status ~= nil then
        if obj.status.health ~= nil then
          hs.status = obj.status.health.status
          if obj.status.health.message ~= nil then
            hs.message = obj.status.health.message
          end
        end
      end
      return hs
  rbac:
    policy.default: role:readonly    # default role
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, clusters, get, *, allow
      p, role:admin, repositories, *, *, allow
      g, platform-team, role:admin
      g, dev-team, role:readonly

server:
  replicas: 2
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi

applicationSet:
  replicas: 2

controller:
  replicas: 1    # stateful, chỉ 1 replica
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 2Gi
```

---

## 3. Application và AppProject

### How – Application Resource

```yaml
# Application: deploy 1 app từ Git
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-production
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io    # cascading delete
spec:
  project: production    # AppProject để phân quyền
  source:
    repoURL: https://github.com/myorg/myapp-gitops.git
    targetRevision: main
    path: apps/myapp/overlays/production    # Kustomize overlay
    # Helm source:
    # chart: myapp
    # repoURL: oci://123456789.dkr.ecr.us-east-1.amazonaws.com/helm-charts
    # targetRevision: 1.2.3
    # helm:
    #   valueFiles:
    #   - values-production.yaml
    #   parameters:
    #   - name: image.tag
    #     value: v2.0.1
    kustomize:
      images:
      - myrepo/myapp:v2.0.1    # override image tag
  destination:
    server: https://kubernetes.default.svc    # cluster URL (in-cluster)
    namespace: production
  syncPolicy:
    automated:
      prune: true         # xóa resources không còn trong Git
      selfHeal: true      # auto-sync khi cluster drift detected
      allowEmpty: false   # không xóa tất cả nếu source rỗng
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - RespectIgnoreDifferences=true
    - ApplyOutOfSyncOnly=true        # chỉ apply resources có diff (nhanh hơn)
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas    # ignore replicas (được manage bởi HPA)
  - group: ""
    kind: Secret
    name: myapp-tls     # ignore cert-manager managed secret
    jsonPointers:
    - /data
  revisionHistoryLimit: 10

---
# AppProject: phân quyền và giới hạn
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: "Production environment"
  # Source repositories allowed
  sourceRepos:
  - "https://github.com/myorg/*"
  - "oci://123456789.dkr.ecr.us-east-1.amazonaws.com/helm-charts"
  # Destination clusters và namespaces
  destinations:
  - server: https://kubernetes.default.svc
    namespace: production
  - server: https://kubernetes.default.svc
    namespace: monitoring
  # Cluster resources allowed (ClusterRole, Namespace, etc.)
  clusterResourceWhitelist:
  - group: ""
    kind: Namespace
  - group: rbac.authorization.k8s.io
    kind: ClusterRole
  # Namespace resources blacklist
  namespaceResourceBlacklist:
  - group: ""
    kind: ResourceQuota    # không cho deploy ResourceQuota
  # RBAC cho project
  roles:
  - name: dev-deploy
    description: Deploy permissions for dev team
    policies:
    - p, proj:production:dev-deploy, applications, sync, production/*, allow
    - p, proj:production:dev-deploy, applications, get, production/*, allow
    groups:
    - dev-team
  orphanedResources:
    warn: true    # warn khi có resources trong namespace không được manage bởi ArgoCD
```

---

## 4. ApplicationSet (Multi-App, Multi-Cluster)

### What – ApplicationSet là gì?
ApplicationSet tự động tạo nhiều Applications dựa trên generators: Git files, clusters, pull requests, matrices, etc.

### How – Git Generator

```yaml
# Git Generator: tạo Application cho mỗi directory trong Git
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: all-apps
  namespace: argocd
spec:
  generators:
  - git:
      repoURL: https://github.com/myorg/gitops.git
      revision: main
      directories:
      - path: "apps/*/overlays/production"    # match pattern

  template:
    metadata:
      name: "{{path.basenameNormalized}}-production"    # tên từ path
    spec:
      project: production
      source:
        repoURL: https://github.com/myorg/gitops.git
        targetRevision: main
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path[1]}}"    # apps/<namespace>/overlays/production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### How – Cluster Generator (Multi-Cluster)

```yaml
# Cluster Generator: deploy lên nhiều clusters tự động
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-all-clusters
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          env: production    # chỉ clusters có label env=production
      values:
        region: "{{metadata.labels.region}}"    # từ cluster labels
        tier: "{{metadata.labels.tier}}"

  template:
    metadata:
      name: "myapp-{{name}}"    # myapp-cluster1, myapp-cluster2
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/gitops.git
        targetRevision: main
        path: apps/myapp
        helm:
          valueFiles:
          - values.yaml
          - values-{{values.region}}.yaml    # region-specific values
          parameters:
          - name: global.clusterName
            value: "{{name}}"
      destination:
        server: "{{server}}"
        namespace: myapp
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### How – Matrix Generator

```yaml
# Matrix: combine nhiều generators
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-matrix
  namespace: argocd
spec:
  generators:
  - matrix:
      generators:
      # Generator 1: clusters
      - clusters:
          selector:
            matchLabels:
              argocd.argoproj.io/secret-type: cluster
      # Generator 2: environments from Git
      - git:
          repoURL: https://github.com/myorg/gitops.git
          revision: main
          files:
          - path: "environments/*.yaml"
          # environments/staging.yaml:
          #   env: staging
          #   replicas: 2
          # environments/production.yaml:
          #   env: production
          #   replicas: 5

  template:
    metadata:
      name: "myapp-{{name}}-{{env}}"    # myapp-cluster1-staging
    spec:
      source:
        helm:
          parameters:
          - name: replicaCount
            value: "{{replicas}}"
          - name: environment
            value: "{{env}}"
```

### How – Pull Request Generator

```yaml
# PR Generator: tạo preview environment cho mỗi Pull Request
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-previews
  namespace: argocd
spec:
  generators:
  - pullRequest:
      github:
        owner: myorg
        repo: myapp
        tokenRef:
          secretName: github-token
          key: token
        labels:
        - preview    # chỉ PRs có label "preview"
      requeueAfterSeconds: 60    # check mỗi 60s
  template:
    metadata:
      name: "preview-pr-{{number}}"
    spec:
      source:
        helm:
          parameters:
          - name: image.tag
            value: "{{head_sha}}"
          - name: ingress.hosts[0].host
            value: "pr-{{number}}.preview.myapp.com"
      destination:
        namespace: "preview-{{number}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

---

## 5. Notifications và Webhooks

### How – ArgoCD Notifications

```yaml
# Notifications ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  template.app-deployed: |
    slack:
      attachments: |
        [{
          "title": "{{.app.metadata.name}} deployed",
          "color": "#18be52",
          "fields": [
            {
              "title": "Sync Status",
              "value": "{{.app.status.sync.status}}",
              "short": true
            },
            {
              "title": "Repository",
              "value": "{{.app.spec.source.repoURL}}",
              "short": true
            },
            {
              "title": "Revision",
              "value": "{{.app.status.sync.revision}}",
              "short": true
            }
          ]
        }]
  template.app-sync-failed: |
    slack:
      attachments: |
        [{
          "title": "{{.app.metadata.name}} sync FAILED",
          "color": "#E96D76",
          "fields": [
            {
              "title": "Error",
              "value": "{{.app.status.operationState.message}}",
              "short": false
            }
          ]
        }]
  trigger.on-deployed: |
    - when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
      send: [app-deployed]
  trigger.on-sync-failed: |
    - when: app.status.operationState.phase in ['Error', 'Failed']
      send: [app-sync-failed]

---
# Application annotation để enable notifications
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: deployments
    notifications.argoproj.io/subscribe.on-sync-failed.slack: alerts
```

---

## 6. ArgoCD Image Updater

### What – Image Updater là gì?
ArgoCD Image Updater tự động cập nhật image tags trong ArgoCD Applications khi image mới được push lên registry. Không cần CI pipeline thay đổi Git.

### How – Image Updater Setup

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

```yaml
# Application annotation cho Image Updater
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-staging
  annotations:
    # List images cần update
    argocd-image-updater.argoproj.io/image-list: myapp=myrepo/myapp

    # Update strategy: semver (latest matching semver tag)
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver

    # Constraint: chỉ update minor và patch (không major)
    argocd-image-updater.argoproj.io/myapp.allow-tags: regexp:^v1\.[0-9]+\.[0-9]+$

    # Write back method: git (commit lại vào Git repo)
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/git-branch: main

    # Helm parameter để update
    argocd-image-updater.argoproj.io/myapp.helm.image-name: image.repository
    argocd-image-updater.argoproj.io/myapp.helm.image-tag: image.tag
```

---

## 7. Flux vs ArgoCD

### Compare

```
ArgoCD:
├── Web UI (rất tốt cho visibility)
├── ApplicationSet (powerful generators)
├── Manual sync support (good for production)
├── Multi-tenancy với AppProject
└── Push model (server polls Git)

Flux:
├── GitOps Toolkit (modular controllers)
│   ├── source-controller (Git/Helm/OCI)
│   ├── kustomize-controller (apply manifests)
│   ├── helm-controller (manage Helm releases)
│   ├── notification-controller (alerts/webhooks)
│   └── image-automation-controller (image updates)
├── CLI-first (không có built-in UI, dùng Weave GitOps)
├── More cloud-native design (separate CRDs)
└── Multi-tenancy với Tenant CRD
```

```yaml
# Flux: HelmRelease (tương đương ArgoCD Application với Helm)
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: myapp
  namespace: production
spec:
  interval: 5m          # check updates mỗi 5 phút
  chart:
    spec:
      chart: myapp
      version: ">=1.0.0 <2.0.0"
      sourceRef:
        kind: HelmRepository
        name: myorg-charts
        namespace: flux-system
  values:
    replicaCount: 3
    image:
      tag: v2.0.1
  install:
    remediation:
      retries: 3
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true
```

---

### Trade-offs
- ArgoCD Web UI: dễ visibility và debugging nhưng thêm attack surface (API server cần expose)
- automated.prune: tiện nhưng nguy hiểm nếu có bug trong Git → xóa production resources
- ApplicationSet PR Generator: preview environments rất tiện nhưng tốn tài nguyên; cần cleanup policy
- Image Updater write-back: tự động commits vào Git là "noisy"; dùng `.argocd-source-*.yaml` file thay vì sửa trực tiếp values

### Real-world Usage
```bash
# ArgoCD CLI
argocd login argocd.company.com --sso

# Sync app
argocd app sync myapp-production

# Sync với dry-run
argocd app sync myapp-production --dry-run

# Xem diff
argocd app diff myapp-production

# App status
argocd app get myapp-production

# Rollback về revision trước
argocd app history myapp-production
argocd app rollback myapp-production 3    # về revision 3

# Hard refresh (invalidate cache)
argocd app get myapp-production --hard-refresh

# Terminate stuck operation
argocd app terminate-op myapp-production

# List tất cả apps
argocd app list

# Bulk sync (tất cả apps trong project)
argocd app list -p production -o name | xargs -I{} argocd app sync {}

# Debug sync failure
argocd app logs myapp-production --follow
```

### Ghi chú – Chủ đề tiếp theo
> Autoscaling Deep – VPA admission controller, Cluster Autoscaler, Karpenter NodePool provisioning

---

*Cập nhật lần cuối: 2026-05-06*
