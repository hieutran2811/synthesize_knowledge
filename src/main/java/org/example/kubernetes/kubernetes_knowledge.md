# Tổng Hợp Kiến Thức Kubernetes – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Kubernetes Architecture – Thực Chiến

### What – K8s Architecture là gì?
Kubernetes là **distributed system** với kiến trúc master-worker. **Control Plane** ra quyết định scheduling/scaling/healing. **Worker Nodes** chạy containers thực tế.

### How – Control Plane Components

```
Control Plane (thường chạy trên dedicated nodes):

kube-apiserver      → REST API gateway duy nhất; mọi thao tác đi qua đây
                      Stateless, horizontal scalable, xác thực authn/authz

etcd                → Distributed KV store – single source of truth
                      Lưu toàn bộ cluster state (objects, configs, secrets)
                      Raft consensus; backup quan trọng hàng đầu!

kube-scheduler      → Quyết định Pod chạy trên Node nào
                      Xét: resource requests, affinity, taints, topology

kube-controller-manager → Loop of controllers:
                      - Deployment Controller (manage ReplicaSets)
                      - ReplicaSet Controller (manage Pods)
                      - Node Controller (heartbeat, eviction)
                      - Job Controller, CronJob Controller...
                      - Endpoint Controller, Service Account Controller...

cloud-controller-manager → Interact với cloud provider API
                      - Node lifecycle (EC2/GCE instance)
                      - LoadBalancer (ELB/GLB)
                      - PersistentVolume (EBS/PD)
```

### How – Worker Node Components

```
Worker Node:

kubelet         → Node agent; nhận PodSpec từ apiserver, ensure containers running
                  Báo cáo node/pod status, chạy health checks
                  Không quản lý containers trực tiếp → delegate containerd

kube-proxy      → Network proxy; maintain iptables/ipvs rules cho Service
                  Mode: iptables (default) hoặc ipvs (performance)
                  Implement ClusterIP, NodePort, LoadBalancer routing

Container Runtime → containerd (default K8s 1.24+), CRI-O
                  Chạy containers; implement CRI (Container Runtime Interface)
```

### How – Request Flow Thực Tế

```
kubectl apply -f deployment.yaml
    ↓ HTTPS + TLS client cert / Bearer token
kube-apiserver (authenticate → authorize RBAC → admission controllers)
    ↓
etcd (persist object)
    ↓ Watch (long-polling)
Deployment Controller → tạo ReplicaSet
    ↓
ReplicaSet Controller → tạo Pods (status: Pending)
    ↓
kube-scheduler → watch Pending pods → assign Node
    ↓
kubelet (trên assigned node) → watch pods assigned to it
    ↓
containerd → pull image → create container
    ↓
kubelet → update pod status → Running
    ↓
kube-proxy → update iptables rules cho Service endpoints
```

### How – Useful Cluster Inspection

```bash
# Xem control plane components
kubectl get componentstatuses           # deprecated nhưng vẫn info
kubectl get pods -n kube-system         # control plane pods

# Xem events (debug scheduling, pod failures)
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -n mynamespace --field-selector reason=Failed

# etcd health
kubectl exec -it etcd-<node> -n kube-system -- \
  etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
          --cert=/etc/kubernetes/pki/etcd/peer.crt \
          --key=/etc/kubernetes/pki/etcd/peer.key \
          endpoint health

# API resources available
kubectl api-resources
kubectl api-versions

# Explain any resource
kubectl explain deployment.spec.strategy
kubectl explain pod.spec.containers.resources
```

### Compare – EKS vs GKE vs AKS vs Self-hosted

| | EKS | GKE | AKS | kubeadm |
|--|-----|-----|-----|---------|
| Control plane cost | $0.10/hr | Free | Free | Node cost only |
| Managed upgrades | Semi-auto | Auto | Auto | Manual |
| Default CNI | VPC CNI | Calico | Azure CNI | user's choice |
| Node autoscaling | Karpenter/CA | Node Auto Provisioner | VMSS | manual |
| Service mesh | App Mesh (opt) | Cloud Service Mesh | OSM (deprecated) | DIY |
| Best for | AWS ecosystem | Start here; best DX | Azure shops | Full control |

### Ghi chú – Chủ đề tiếp theo
> Workloads: Deployment, StatefulSet, DaemonSet, Job/CronJob – advanced config

---

## 2. Workloads – Advanced

### What – Workload Resources là gì?
K8s cung cấp nhiều **workload types** phù hợp với đặc điểm khác nhau của ứng dụng: stateless, stateful, per-node, batch.

### How – Deployment Best Practices

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    kubernetes.io/change-cause: "Release v2.1.0 - add payment feature"  # rollout history
spec:
  replicas: 3
  revisionHistoryLimit: 5           # giữ 5 revision để rollback
  progressDeadlineSeconds: 600      # fail nếu không hoàn thành trong 10 phút
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0             # zero-downtime (luôn có đủ pods)
      maxSurge: 1                   # 1 pod thêm khi update

  selector:
    matchLabels:
      app: myapp

  template:
    metadata:
      labels:
        app: myapp
        version: "2.1.0"
    spec:
      # Graceful shutdown
      terminationGracePeriodSeconds: 60

      # Không schedule 2 pods trên cùng node
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: myapp
              topologyKey: kubernetes.io/hostname

      containers:
        - name: app
          image: myapp:2.1.0
          
          ports:
            - containerPort: 8080
              protocol: TCP

          # Resources (LUÔN set trong production)
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"

          # Probes
          startupProbe:             # cho app khởi động chậm (Java)
            httpGet:
              path: /actuator/health
              port: 8080
            failureThreshold: 30
            periodSeconds: 10

          readinessProbe:           # kiểm tra sẵn sàng nhận traffic
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            failureThreshold: 3

          livenessProbe:            # kiểm tra còn sống (restart nếu fail)
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            failureThreshold: 3

          # Graceful shutdown
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 5"]  # drain connections

          # Security context
          securityContext:
            runAsNonRoot: true
            runAsUser: 1001
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]

          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
```

### How – StatefulSet thực tế

```yaml
# StatefulSet: DB, Kafka, Redis Cluster, Elasticsearch
# Pods: mydb-0, mydb-1, mydb-2 (stable names)
# Headless service: mydb-0.mydb.default.svc.cluster.local

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres-headless
  replicas: 3
  podManagementPolicy: Parallel      # tạo all pods cùng lúc (thay vì tuần tự)
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0                    # chỉ update pods từ index >= partition
                                     # Canary: partition=2 → chỉ update pod-2 trước

  selector:
    matchLabels:
      app: postgres

  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          env:
            - name: POSTGRES_REPLICATION_MODE
              value: master           # mydb-0 = master
            - name: MY_POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            periodSeconds: 5

  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3-encrypted
        resources:
          requests:
            storage: 100Gi
```

### How – DaemonSet (Agent per Node)

```yaml
# DaemonSet: chạy 1 pod trên MỖI node (log agent, monitoring, network plugin)
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
spec:
  selector:
    matchLabels:
      app: fluent-bit
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1

  template:
    spec:
      tolerations:                    # cần tolerate node taints để chạy trên mọi node
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule          # chạy cả trên control plane nodes
        - key: "node.kubernetes.io/not-ready"
          effect: "NoExecute"
          tolerationSeconds: 300

      containers:
        - name: fluent-bit
          image: fluent/fluent-bit:2.2
          volumeMounts:
            - name: varlog
              mountPath: /var/log
            - name: containers
              mountPath: /var/lib/docker/containers
              readOnly: true

      volumes:
        - name: varlog
          hostPath:
            path: /var/log
        - name: containers
          hostPath:
            path: /var/lib/docker/containers
```

### How – Job & CronJob

```yaml
# Job: chạy task đến khi hoàn thành
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  completions: 1
  parallelism: 1
  backoffLimit: 3                     # retry 3 lần nếu fail
  ttlSecondsAfterFinished: 3600       # tự xóa sau 1h
  
  template:
    spec:
      restartPolicy: OnFailure        # Job pods: Never hoặc OnFailure
      containers:
        - name: migrate
          image: myapp:latest
          command: ["python", "manage.py", "migrate"]

---
# CronJob: schedule task
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 2 * * *"              # 2:00 AM hàng ngày (UTC)
  timeZone: "Asia/Ho_Chi_Minh"       # K8s 1.27+
  concurrencyPolicy: Forbid           # không chạy nếu job trước chưa xong
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  startingDeadlineSeconds: 300        # skip nếu quá 5 phút sau schedule time

  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: backup-tool:latest
              command: ["./backup.sh"]
```

### Ghi chú – Chủ đề tiếp theo
> Networking: Services, Ingress, Gateway API, NetworkPolicy, DNS

---

## 3. Networking – Thực Chiến

### What – K8s Networking Model
Mọi Pod có IP riêng, mọi Pod giao tiếp với Pod khác **không qua NAT** (flat network). Services cung cấp stable endpoint. CNI plugin implement networking.

### How – Service Types

```yaml
# ClusterIP (default): chỉ trong cluster
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  selector:
    app: backend
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP

---
# NodePort: expose ra ngoài qua node IP:port (30000-32767)
# Dùng cho dev/staging; không dùng production

---
# LoadBalancer: cloud load balancer tự động
apiVersion: v1
kind: Service
metadata:
  name: frontend
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb  # AWS NLB
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
spec:
  selector:
    app: frontend
  ports:
    - port: 443
      targetPort: 8443
  type: LoadBalancer

---
# ExternalName: DNS alias cho external service
apiVersion: v1
kind: Service
metadata:
  name: database
spec:
  type: ExternalName
  externalName: prod-db.us-east-1.rds.amazonaws.com
  # → database.default.svc.cluster.local → RDS endpoint

---
# Headless: DNS trả về Pod IPs, không có ClusterIP
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
    - port: 5432
# → postgres-0.postgres-headless.default.svc.cluster.local
```

### How – Ingress (L7 Routing)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    # nginx-ingress annotations
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
    nginx.ingress.kubernetes.io/rate-limit: "10"             # 10 req/s per IP
    nginx.ingress.kubernetes.io/rate-limit-burst: "20"
    # TLS cert từ cert-manager
    cert-manager.io/cluster-issuer: letsencrypt-prod

spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
        - api.example.com
      secretName: myapp-tls

  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /api/v1
            pathType: Prefix
            backend:
              service:
                name: api-v1
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80

    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
```

### How – NetworkPolicy (Firewall cho Pods)

```yaml
# Default deny all ingress cho namespace production
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}               # áp dụng cho tất cả pods
  policyTypes:
    - Ingress

---
# Chỉ cho phép app → db
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgres             # target: postgres pods
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: myapp        # chỉ cho phép từ myapp pods
          namespaceSelector:    # AND: trong cùng namespace production
            matchLabels:
              kubernetes.io/metadata.name: production
      ports:
        - protocol: TCP
          port: 5432

---
# Allow monitoring namespace scrape metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: production
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app: prometheus
      ports:
        - port: 9090
        - port: 8080
```

### How – DNS trong K8s

```
DNS pattern: <service>.<namespace>.svc.cluster.local
             <pod-ip-dashes>.<namespace>.pod.cluster.local

Ví dụ:
  Service "backend" trong namespace "production":
  → backend.production.svc.cluster.local
  → backend.production (short form, nếu cùng namespace)
  → backend (short form, nếu cùng namespace)

StatefulSet headless:
  → postgres-0.postgres-headless.production.svc.cluster.local
  → postgres-1.postgres-headless.production.svc.cluster.local

CoreDNS: kube-dns service tại kube-system
  → mọi Pod dùng 10.96.0.10 (hoặc configured DNS)
  → /etc/resolv.conf trong Pod:
     nameserver 10.96.0.10
     search default.svc.cluster.local svc.cluster.local cluster.local
```

### Ghi chú – Chủ đề tiếp theo
> Storage: PV/PVC/StorageClass, CSI drivers, backup với Velero

---

## 4. Storage – Thực Chiến

### How – Storage Classes

```yaml
# StorageClass: template để tự động provision PV
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"  # default class
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  kmsKeyId: arn:aws:kms:ap-southeast-1:123:key/abc
  throughput: "250"
  iops: "3000"
reclaimPolicy: Retain               # Retain hoặc Delete
allowVolumeExpansion: true          # cho phép resize PVC
volumeBindingMode: WaitForFirstConsumer  # tạo volume cùng AZ với Pod
mountOptions:
  - debug

---
# PVC với StorageClass
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-encrypted
  resources:
    requests:
      storage: 50Gi
```

### How – Volume Types thực tế

```yaml
spec:
  volumes:
    # ConfigMap mount
    - name: config
      configMap:
        name: app-config
        items:
          - key: nginx.conf
            path: nginx.conf      # chỉ mount 1 key

    # Secret mount
    - name: secrets
      secret:
        secretName: db-secret
        defaultMode: 0400         # permissions

    # emptyDir (shared giữa containers trong Pod)
    - name: shared-tmp
      emptyDir:
        medium: Memory            # RAM (tmpfs) – nhanh hơn disk
        sizeLimit: 256Mi

    # hostPath (mount từ node filesystem – TRÁNH production)
    - name: node-logs
      hostPath:
        path: /var/log
        type: Directory           # DirectoryOrCreate, File, FileOrCreate

    # CSI volume (external storage)
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: aws-secrets
```

### Ghi chú – Chủ đề tiếp theo
> Security: RBAC, ServiceAccount, PodSecurity, OPA Gatekeeper, Kyverno

---

## 5. RBAC & Security – Thực Chiến

### How – RBAC (Role-Based Access Control)

```yaml
# Role: namespace-scoped permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
  - apiGroups: [""]               # "" = core API group
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "update", "patch"]

---
# ClusterRole: cluster-wide permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]

---
# RoleBinding: gắn Role với Subject
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-pod-reader
  namespace: production
subjects:
  - kind: User
    name: alice
    apiGroup: rbac.authorization.k8s.io
  - kind: Group
    name: dev-team
    apiGroup: rbac.authorization.k8s.io
  - kind: ServiceAccount
    name: my-service-account
    namespace: production
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io

---
# ServiceAccount cho Pod (ví dụ: app cần đọc Secrets)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123:role/myapp-role  # IRSA (EKS)
automountServiceAccountToken: false  # không auto-mount nếu không cần
```

### How – Pod Security Standards

```yaml
# Namespace-level policy (K8s 1.23+)
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted   # enforce policy
    pod-security.kubernetes.io/enforce-version: v1.28
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted

# Policies: privileged, baseline, restricted
# restricted = most secure:
# - runAsNonRoot: true
# - readOnlyRootFilesystem: true
# - allowPrivilegeEscalation: false
# - capabilities.drop: [ALL]
# - seccompProfile.type: RuntimeDefault hoặc Localhost
```

### Ghi chú – Chủ đề tiếp theo
> Helm, GitOps, Autoscaling, Observability, Production patterns

---

## 6. Helm – Package Manager

### What – Helm là gì?
**Helm** là package manager cho K8s – đóng gói YAML manifests thành **Charts**, hỗ trợ templating, versioning, và lifecycle management.

### How – Helm Chart Structure

```
mychart/
├── Chart.yaml          # metadata: name, version, appVersion
├── values.yaml         # default values
├── values-prod.yaml    # production overrides
├── templates/
│   ├── _helpers.tpl    # helper templates (reusable)
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── hpa.yaml
│   ├── configmap.yaml
│   └── NOTES.txt       # post-install messages
└── charts/             # sub-charts (dependencies)
```

### How – Commands thực tế

```bash
# Tìm kiếm charts
helm search hub nginx                    # Artifact Hub
helm search repo bitnami/postgresql      # local repos

# Thêm repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Cài đặt
helm install myapp ./mychart             # từ local chart
helm install myapp bitnami/postgresql \  # từ repo
  --namespace production \
  --create-namespace \
  --values values-prod.yaml \
  --set image.tag=16.2 \
  --set replicaCount=3

# Upgrade
helm upgrade myapp ./mychart \
  --namespace production \
  --values values-prod.yaml \
  --atomic \                             # rollback nếu fail
  --timeout 5m

# Rollback
helm rollback myapp 1                    # rollback về revision 1

# Kiểm tra
helm list -A                             # tất cả releases
helm status myapp -n production
helm history myapp -n production
helm get values myapp -n production      # values đang dùng

# Template render (debug)
helm template myapp ./mychart --values values-prod.yaml | kubectl apply --dry-run=client -f -
```

### Ghi chú – Chủ đề tiếp theo
> GitOps với ArgoCD, Autoscaling (HPA/VPA/KEDA), Production Patterns

---

## 7. GitOps – ArgoCD

### What – GitOps là gì?
**GitOps** là pattern dùng Git làm **single source of truth** cho infrastructure và application state. Thay đổi qua Pull Request, agent tự động sync cluster về trạng thái trong Git.

### How – ArgoCD Flow

```
Git Repository (desired state)
    ↓ ArgoCD sync (poll hoặc webhook)
ArgoCD
    ↓ compare actual vs desired
K8s Cluster (actual state)
    ↓ apply diff nếu OutOfSync
Sync complete → Healthy

Lợi ích:
├── Audit trail: Git history = deployment history
├── Rollback = git revert
├── Drift detection: cluster khác Git → alert
├── Multi-cluster: 1 ArgoCD manage nhiều clusters
└── PR-based deployments: review trước khi deploy
```

### How – ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-production
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/myorg/k8s-manifests
    targetRevision: main
    path: apps/myapp/production

    # Helm source
    # repoURL: https://charts.bitnami.com/bitnami
    # chart: postgresql
    # targetRevision: 12.x.x
    # helm:
    #   values: |
    #     replicaCount: 3

  destination:
    server: https://kubernetes.default.svc   # same cluster
    namespace: production

  syncPolicy:
    automated:
      prune: true           # xóa resources không còn trong Git
      selfHeal: true        # tự sửa khi có drift
      allowEmpty: false     # không xóa tất cả nếu folder rỗng
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - ApplyOutOfSyncOnly=true    # chỉ apply resources changed
    retry:
      limit: 3
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 3m
```

### Ghi chú – Chủ đề tiếp theo
> Autoscaling (HPA/VPA/KEDA/Cluster Autoscaler), Production Patterns (PDB, ResourceQuota)

---

## 8. Autoscaling

### What – K8s Autoscaling là gì?
K8s cung cấp nhiều layer autoscaling: **HPA** (pods số lượng), **VPA** (pod resources), **KEDA** (event-driven), **Cluster Autoscaler/Karpenter** (nodes).

### How – HPA với Custom Metrics

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 50
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30    # scale up nhanh
      policies:
        - type: Percent
          value: 100                     # double số replicas
          periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300   # scale down chậm (tránh flap)
      policies:
        - type: Pods
          value: 2                       # giảm tối đa 2 pods mỗi 60s
          periodSeconds: 60

  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60        # target 60% CPU

    # Custom metrics via Prometheus Adapter
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "500"           # 500 req/s per pod
```

### How – KEDA (Event-Driven Autoscaling)

```yaml
# KEDA: scale từ 0 đến N dựa trên external events
# Scale to zero khi không có events → tiết kiệm cost

apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: worker-scaledobject
spec:
  scaleTargetRef:
    name: queue-worker
  minReplicaCount: 0                  # scale to zero!
  maxReplicaCount: 100
  pollingInterval: 30
  cooldownPeriod: 300

  triggers:
    # SQS queue depth
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.ap-southeast-1.amazonaws.com/123/my-queue
        queueLength: "5"              # 1 pod per 5 messages
        awsRegion: ap-southeast-1

    # Kafka consumer lag
    - type: kafka
      metadata:
        bootstrapServers: kafka:9092
        consumerGroup: my-consumer-group
        topic: my-topic
        lagThreshold: "100"           # 1 pod per 100 messages lag

    # Cron schedule (scale up giờ cao điểm)
    - type: cron
      metadata:
        timezone: Asia/Ho_Chi_Minh
        start: 0 8 * * 1-5           # 8:00 AM thứ 2-6
        end: 0 18 * * 1-5            # 6:00 PM thứ 2-6
        desiredReplicas: "10"
```

### Ghi chú – Chủ đề tiếp theo
> Production Patterns: PDB, ResourceQuota, LimitRange, TopologySpreadConstraints, Observability

---

## 9. Observability – Thực Chiến

### What – Observability trong K8s gồm 3 pillars
**Metrics** (Prometheus + Grafana), **Logs** (Loki + Grafana), **Traces** (Jaeger/Tempo + OpenTelemetry).

### How – kube-state-metrics (Cluster Metrics)

```yaml
# kube-state-metrics: expose K8s object metrics cho Prometheus
# Metrics quan trọng:
kube_deployment_status_replicas_available  # số replicas available
kube_pod_container_status_restarts_total   # restart count
kube_pod_status_phase                      # pod phase (Running/Pending/Failed)
kube_node_status_condition                 # node Ready/MemoryPressure/DiskPressure
kube_persistentvolumeclaim_status_phase    # PVC Bound/Pending/Lost
kube_job_status_succeeded                  # job completion
kube_cronjob_next_schedule_time            # next scheduled run
```

### How – Prometheus Alerting Rules

```yaml
groups:
  - name: kubernetes
    rules:
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} crash looping"

      - alert: DeploymentReplicasMismatch
        expr: |
          kube_deployment_spec_replicas != kube_deployment_status_replicas_available
        for: 5m
        labels:
          severity: warning

      - alert: PodNotReady
        expr: |
          sum by (namespace, pod) (
            max by (namespace, pod) (kube_pod_status_phase{phase=~"Pending|Unknown"})
          ) > 0
        for: 10m
        labels:
          severity: warning

      - alert: NodeNotReady
        expr: kube_node_status_condition{condition="Ready",status="true"} == 0
        for: 2m
        labels:
          severity: critical

      - alert: PVCPending
        expr: kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
        for: 5m
        labels:
          severity: warning
```

### Ghi chú – Chủ đề tiếp theo
> Production Patterns: PDB, Topology Spread, Resource Quotas, Canary deployments

---

## 10. Production Patterns

### How – PodDisruptionBudget (PDB)

```yaml
# PDB: đảm bảo tối thiểu N pods chạy khi node drain/upgrade
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: myapp-pdb
spec:
  minAvailable: 2                    # hoặc "50%"
  # maxUnavailable: 1               # hoặc dùng maxUnavailable
  selector:
    matchLabels:
      app: myapp
```

### How – TopologySpreadConstraints

```yaml
# Spread pods across zones (thay thế pod anti-affinity phức tạp)
spec:
  topologySpreadConstraints:
    # Spread evenly across zones
    - maxSkew: 1                     # tối đa 1 pod chênh lệch giữa zones
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule  # hard (hoặc ScheduleAnyway = soft)
      labelSelector:
        matchLabels:
          app: myapp

    # Spread evenly across nodes
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway  # soft (best effort)
      labelSelector:
        matchLabels:
          app: myapp
```

### How – ResourceQuota & LimitRange

```yaml
# ResourceQuota: giới hạn tổng resource của namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    pods: "100"
    services: "20"
    persistentvolumeclaims: "20"
    secrets: "50"
    configmaps: "50"

---
# LimitRange: default + max/min resource per container
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:                        # default limit nếu không khai báo
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:                 # default request
        cpu: "100m"
        memory: "128Mi"
      max:                            # max không được vượt
        cpu: "4"
        memory: "8Gi"
      min:
        cpu: "50m"
        memory: "64Mi"
    - type: PersistentVolumeClaim
      max:
        storage: "100Gi"
```

### Real-world Usage – Production Checklist

```bash
# Kiểm tra cluster health
kubectl get nodes -o wide
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Kiểm tra resource usage vs limits
kubectl describe nodes | grep -A 5 "Allocated resources"

# Tìm pods không có resource limits
kubectl get pods -A -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.limits == null) |
    "\(.metadata.namespace)/\(.metadata.name)"'

# Tìm pods đang restart nhiều
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'

# Tìm pending pods và lý do
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe pod <pending-pod>  # xem Events section

# Audit RBAC permissions
kubectl auth can-i --list --namespace production --as alice
kubectl auth can-i create pods --namespace production

# Check certificate expiry
kubeadm certs check-expiration     # self-hosted
```

---

*Cập nhật lần cuối: 2026-05-06*
