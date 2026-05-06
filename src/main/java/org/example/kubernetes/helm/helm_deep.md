# Kubernetes Helm Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Chart Authoring Best Practices

### What – Helm Chart Structure
Helm Chart là package format cho Kubernetes resources. Một chart đóng gói tất cả YAML templates, default values, và metadata cần thiết để deploy một application.

### How – Chart Structure và Templates

```
myapp/
├── Chart.yaml              ← metadata (name, version, dependencies)
├── values.yaml             ← default values
├── values-prod.yaml        ← production overrides (không phải chuẩn, thêm vào)
├── charts/                 ← dependencies (subcharts)
├── templates/
│   ├── _helpers.tpl        ← helper template functions
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── hpa.yaml
│   ├── serviceaccount.yaml
│   ├── NOTES.txt           ← post-install instructions
│   └── tests/
│       └── test-connection.yaml
└── .helmignore
```

```yaml
# Chart.yaml
apiVersion: v2
name: myapp
description: "MyApp Helm Chart"
type: application    # application | library
version: 1.2.3       # chart version (SemVer)
appVersion: "2.0.1"  # app version (informational)
keywords:
- myapp
- microservice
maintainers:
- name: Platform Team
  email: platform@company.com
dependencies:
- name: postgresql
  version: "13.x.x"
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled     # values.postgresql.enabled = false → skip
- name: redis
  version: "17.x.x"
  repository: https://charts.bitnami.com/bitnami
  condition: redis.enabled
  tags:
  - cache                           # helm install --set tags.cache=false
annotations:
  artifacthub.io/changes: |
    - kind: added
      description: Add HPA support
    - kind: fixed
      description: Fix readiness probe timeout
```

### How – values.yaml Design Pattern

```yaml
# values.yaml: document mọi field

# Global values (shared across subcharts)
global:
  imageRegistry: ""          # override all image registries
  storageClass: ""
  imagePullSecrets: []

# Image config
image:
  repository: myrepo/myapp
  tag: ""                    # default: Chart.appVersion
  pullPolicy: IfNotPresent
  pullSecrets: []

# Replica config
replicaCount: 1

# Autoscaling
autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

# Resources
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m

# Service
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
  annotations: {}

# Ingress
ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts: []
  tls: []

# Environment variables
env: {}
  # KEY: value

envFrom: []
  # - secretRef:
  #     name: mysecret

# Config (mounted as ConfigMap)
config:
  app.properties: |
    server.port=8080
    spring.profiles.active=prod

# Secrets
secrets: {}
  # DB_PASSWORD: base64encoded

# ServiceAccount
serviceAccount:
  create: true
  name: ""
  annotations: {}
    # eks.amazonaws.com/role-arn: arn:aws:iam::123:role/myapp

# Pod Security
podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]

# Probes
livenessProbe:
  httpGet:
    path: /health/liveness
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/readiness
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5

# Affinity/Tolerations
nodeSelector: {}
tolerations: []
affinity: {}
topologySpreadConstraints: []

# PodDisruptionBudget
podDisruptionBudget:
  enabled: false
  minAvailable: 1

# Persistence
persistence:
  enabled: false
  storageClass: ""
  accessMode: ReadWriteOnce
  size: 10Gi

# PostgreSQL subchart
postgresql:
  enabled: false
  auth:
    database: myapp
    username: myapp
    existingSecret: myapp-db-secret
```

### How – _helpers.tpl Best Practices

```
{{/*
helpers.tpl: common template functions để tái sử dụng
*/}}

{{/* Expand the name of the chart */}}
{{- define "myapp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Create a default fully qualified app name */}}
{{- define "myapp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Common labels */}}
{{- define "myapp.labels" -}}
helm.sh/chart: {{ include "myapp.chart" . }}
{{ include "myapp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels */}}
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* ServiceAccount name */}}
{{- define "myapp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "myapp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Image reference */}}
{{- define "myapp.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repository := .Values.image.repository }}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}
```

```yaml
# deployment.yaml sử dụng helpers
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
        # ↑ Force pod restart khi config/secret thay đổi
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "myapp.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
      - name: {{ .Chart.Name }}
        image: {{ include "myapp.image" . }}
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: {{ .Values.service.targetPort }}
        {{- if .Values.env }}
        env:
        {{- range $key, $value := .Values.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- end }}
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        {{- with .Values.containerSecurityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
```

---

## 2. Helm Hooks

### What – Helm Hooks là gì?
Hooks cho phép can thiệp vào release lifecycle: pre-install, post-install, pre-upgrade, post-upgrade, pre-delete, post-delete, pre-rollback, post-rollback.

### How – Hook Annotations

```yaml
# pre-upgrade hook: chạy database migration TRƯỚC khi upgrade app
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-db-migrate
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install    # chạy khi install và upgrade
    "helm.sh/hook-weight": "-5"                # thứ tự: nhỏ hơn chạy trước
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
    # before-hook-creation: xóa job cũ trước khi tạo job mới
    # hook-succeeded: xóa job sau khi thành công
    # hook-failed: xóa job sau khi thất bại (giữ lại để debug)
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: db-migrate
        image: {{ include "myapp.image" . }}
        command: ["python", "manage.py", "migrate", "--no-input"]
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: {{ include "myapp.fullname" . }}-secrets
              key: database-url
---
# post-install hook: smoke test sau khi deploy
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-smoke-test
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "5"
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: smoke-test
        image: curlimages/curl:latest
        command:
        - sh
        - -c
        - |
          sleep 10  # đợi app ready
          curl -f http://{{ include "myapp.fullname" . }}:{{ .Values.service.port }}/health || exit 1
          echo "Smoke test passed!"
```

---

## 3. Library Charts

### What – Library Charts là gì?
Library Charts là chart không thể install trực tiếp (type: library). Chứa các helper templates được share bởi nhiều application charts. Tránh lặp lại code.

### How – Library Chart Creation

```yaml
# Chart.yaml của library chart
apiVersion: v2
name: common-library
type: library    # ← không install được, chỉ import
version: 1.0.0
description: "Common Helm templates"
```

```
{{/* common-library/templates/_deployment.tpl */}}

{{- define "common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount | default 1 }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "common.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
{{- end }}
```

```yaml
# App chart sử dụng library
# Chart.yaml
dependencies:
- name: common-library
  version: "1.0.0"
  repository: "oci://registry.company.com/helm"

# templates/deployment.yaml
{{- include "common.deployment" . }}
```

---

## 4. Helmfile

### What – Helmfile là gì?
Helmfile là tool quản lý nhiều Helm releases declaratively trong một file, giống Terraform cho Helm. Hỗ trợ environments, diff, và sync.

### How – Helmfile Configuration

```yaml
# helmfile.yaml
repositories:
- name: prometheus-community
  url: https://prometheus-community.github.io/helm-charts
- name: bitnami
  url: https://charts.bitnami.com/bitnami
- name: ingress-nginx
  url: https://kubernetes.github.io/ingress-nginx

environments:
  staging:
    values:
    - environments/staging.yaml
  production:
    values:
    - environments/production.yaml
    secrets:
    - environments/production.secrets.yaml.enc    # SOPS encrypted

releases:
- name: ingress-nginx
  namespace: ingress-nginx
  chart: ingress-nginx/ingress-nginx
  version: "4.9.0"
  values:
  - charts/ingress-nginx/values.yaml
  - charts/ingress-nginx/values.{{ .Environment.Name }}.yaml

- name: cert-manager
  namespace: cert-manager
  chart: jetstack/cert-manager
  version: "v1.14.0"
  set:
  - name: installCRDs
    value: true

- name: kube-prometheus-stack
  namespace: monitoring
  chart: prometheus-community/kube-prometheus-stack
  version: "56.x.x"
  values:
  - charts/monitoring/values.yaml
  - charts/monitoring/values.{{ .Environment.Name }}.yaml

- name: myapp
  namespace: production
  chart: ./charts/myapp
  values:
  - charts/myapp/values.yaml
  - charts/myapp/values.{{ .Environment.Name }}.yaml
  needs:
  - ingress-nginx/ingress-nginx    # deploy sau ingress-nginx
  - cert-manager/cert-manager
```

```bash
# Helmfile commands
helmfile diff                          # xem thay đổi sẽ được apply
helmfile apply                         # apply tất cả releases
helmfile apply --environment production

helmfile sync                          # force sync (kể cả không có thay đổi)
helmfile destroy                       # xóa tất cả releases

# Chỉ 1 release
helmfile apply --selector name=myapp
helmfile diff --selector name=kube-prometheus-stack

# List releases và status
helmfile list
```

---

## 5. OCI Registry cho Charts

### How – Push và Pull Charts via OCI

```bash
# Push chart lên OCI registry
helm package ./myapp                   # tạo myapp-1.2.3.tgz
helm push myapp-1.2.3.tgz oci://123456789.dkr.ecr.us-east-1.amazonaws.com/helm-charts

# Login
aws ecr get-login-password --region us-east-1 | \
  helm registry login --username AWS --password-stdin \
  123456789.dkr.ecr.us-east-1.amazonaws.com

# Pull và install
helm install myapp oci://123456789.dkr.ecr.us-east-1.amazonaws.com/helm-charts/myapp \
  --version 1.2.3

# Khi dùng OCI, không cần helm repo add
# Sử dụng trực tiếp OCI URL
```

### How – Chart Versioning Strategy

```bash
# Semantic versioning:
# MAJOR.MINOR.PATCH
# MAJOR: breaking changes trong values hoặc API
# MINOR: new features (backwards compatible)
# PATCH: bug fixes

# CI: auto-bump chart version
# Trong CI/CD:
CHART_VERSION=$(cat charts/myapp/Chart.yaml | grep '^version:' | awk '{print $2}')
NEW_VERSION=$(semver bump patch $CHART_VERSION)
sed -i "s/^version: .*/version: $NEW_VERSION/" charts/myapp/Chart.yaml

# Chart version != App version
# App: 2.0.1 (release của application)
# Chart: 1.5.3 (có thể update chart nhiều lần mà không đổi app version)
```

---

### Compare – Helm vs Alternatives

| | Helm | Kustomize | Raw YAML | Operator |
|--|------|-----------|----------|----------|
| **Templating** | Go templates | Patches/overlays | None | Code (Go) |
| **Release mgmt** | Built-in | External | Manual | Built-in |
| **Values** | values.yaml | Per-overlay | Hardcoded | CRD fields |
| **Dependencies** | Subcharts | External | Manual | Custom |
| **Learning** | Medium | Low | None | High |
| **Best for** | Packages, multi-env | K8s-native apps | Simple | Complex lifecycle |

### Trade-offs
- Helm templates: powerful nhưng Go template syntax khó debug; `helm template` để preview
- chart checksum annotation: force pod restart khi config thay đổi nhưng gây rolling restart ngay cả khi không cần
- Library charts: giảm duplication nhưng tạo coupling giữa charts; update library = update all consumers
- Helmfile needs: declare explicit order nhưng tăng complexity khi có nhiều dependencies

### Real-world Usage
```bash
# Debug template rendering
helm template myapp ./charts/myapp \
  --values values-prod.yaml \
  --set image.tag=v2.0.1 \
  --debug    # show computed values

# Dry run install
helm install myapp ./charts/myapp \
  --values values-prod.yaml \
  --dry-run --debug

# Lint chart
helm lint ./charts/myapp --values values-prod.yaml

# Diff trước khi upgrade (plugin)
helm plugin install https://github.com/databus23/helm-diff
helm diff upgrade myapp ./charts/myapp --values values-prod.yaml

# Rollback nếu upgrade failed
helm rollback myapp 2    # về revision 2
helm history myapp       # xem history

# Test chart sau install
helm test myapp           # chạy templates/tests/

# Export chart values (đang dùng)
helm get values myapp -n production

# Export all manifests (deployed)
helm get manifest myapp -n production
```

### Ghi chú – Chủ đề tiếp theo
> ArgoCD & GitOps Deep – ApplicationSet generators, multi-cluster management, Flux comparison, image updater

---

*Cập nhật lần cuối: 2026-05-06*
