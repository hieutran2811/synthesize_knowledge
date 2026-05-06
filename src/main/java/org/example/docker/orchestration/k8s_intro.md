# Kubernetes Introduction – Từ Docker đến K8s

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Kubernetes Overview

### What – Kubernetes là gì?
**Kubernetes (K8s)** là container orchestration platform mã nguồn mở (Google, 2014), tự động hóa **deployment**, **scaling**, **healing**, và **management** của containerized applications ở scale lớn.

### How – Kubernetes vs Docker Swarm (Mapping Concepts)

```
Docker Concept          →  Kubernetes Concept
───────────────────────────────────────────────
docker run              →  Pod
docker service          →  Deployment / StatefulSet / DaemonSet
docker stack            →  Helm Chart / Kustomize
docker network          →  Service (ClusterIP/NodePort/LoadBalancer)
docker volume           →  PersistentVolumeClaim
docker-compose.yaml     →  Kubernetes YAML manifests
docker secret           →  Secret
docker config           →  ConfigMap
swarm node labels       →  Node labels / Node selectors
service constraints     →  nodeSelector / affinity / taints
healthcheck             →  livenessProbe + readinessProbe + startupProbe
rolling update          →  RollingUpdate Deployment strategy
```

### How – K8s Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Control Plane                           │
│                                                              │
│  ┌───────────────┐  ┌───────────┐  ┌───────────────────┐   │
│  │  API Server   │  │ Scheduler │  │ Controller Manager│   │
│  │ (kube-apiserver│  │           │  │ (Deployment Ctrl, │   │
│  │  REST API)    │  │           │  │  ReplicaSet Ctrl..)│  │
│  └───────┬───────┘  └─────┬─────┘  └───────────────────┘   │
│          │                │                                  │
│  ┌───────▼────────────────▼──────────────────────────────┐  │
│  │                       etcd                            │  │
│  │              (distributed key-value store)            │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │ kubectl / API
        ┌──────────────▼──────────────────┐
        │           Worker Nodes           │
        │  ┌──────────────────────────┐   │
        │  │ kubelet    kube-proxy    │   │
        │  │ (node agent) (iptables)  │   │
        │  │                          │   │
        │  │ ┌──────┐ ┌──────────┐  │   │
        │  │ │ Pod  │ │  Pod     │  │   │
        │  │ │[cont]│ │ [cont]   │  │   │
        │  │ └──────┘ └──────────┘  │   │
        │  └──────────────────────────┘   │
        └─────────────────────────────────┘
```

---

## 2. Core Objects – Từ Docker đến K8s

### How – Pod (≈ docker run)

```yaml
# Pod = smallest deployable unit = 1+ containers sharing network+storage
# Tương đương: docker run --network container:... (shared network namespace)

apiVersion: v1
kind: Pod
metadata:
  name: myapp
  labels:
    app: myapp
    version: "1.0"
spec:
  containers:
    - name: app
      image: myapp:1.0
      ports:
        - containerPort: 8080
      env:
        - name: DB_HOST
          value: postgres-service
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password

      # Tương đương docker HEALTHCHECK
      livenessProbe:           # container sống không? (restart nếu fail)
        httpGet:
          path: /health
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 10
        failureThreshold: 3

      readinessProbe:          # container sẵn sàng nhận traffic? (remove từ LB nếu fail)
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5

      startupProbe:            # slow startup apps (Java) – disable liveness trong startup
        httpGet:
          path: /health
          port: 8080
        failureThreshold: 30   # 30 * 10s = 5 phút grace period
        periodSeconds: 10

      resources:               # tương đương --memory --cpus
        requests:
          memory: "256Mi"
          cpu: "250m"          # 0.25 CPU
        limits:
          memory: "512Mi"
          cpu: "1000m"         # 1 CPU

      volumeMounts:
        - name: app-data
          mountPath: /data

  # Init container (chạy trước main containers)
  initContainers:
    - name: migrate
      image: myapp:1.0
      command: ["python", "manage.py", "migrate"]

  volumes:
    - name: app-data
      persistentVolumeClaim:
        claimName: app-data-pvc
```

### How – Deployment (≈ docker service)

```yaml
# Deployment = managed ReplicaSet + rolling updates
# Tương đương: docker service create --replicas 3

apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp                       # phải match với pod labels
  
  # Rolling update strategy (tương đương docker service update config)
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1               # tối đa 1 pod unavailable
      maxSurge: 1                     # tối đa 1 pod thêm khi update

  template:                          # Pod template
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: app
          image: myapp:1.0
          # ... (giống Pod spec ở trên)

---
# Commands
kubectl apply -f deployment.yaml     # deploy
kubectl rollout status deployment/myapp   # theo dõi rollout
kubectl rollout undo deployment/myapp     # rollback
kubectl rollout history deployment/myapp  # history
kubectl scale deployment/myapp --replicas=5
kubectl set image deployment/myapp app=myapp:2.0  # update image
```

### How – Service (≈ docker network + port mapping)

```yaml
# Service = stable DNS name + load balancing cho pods
# Tương đương: docker network + published ports

# ClusterIP: chỉ accessible trong cluster
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp                       # target pods với label này
  ports:
    - protocol: TCP
      port: 80                       # service port
      targetPort: 8080               # pod port
  type: ClusterIP                    # default

---
# NodePort: expose ra ngoài qua node IP:port
apiVersion: v1
kind: Service
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080                # accessible: <node-ip>:30080

---
# LoadBalancer: tạo cloud load balancer (ELB, GLB)
apiVersion: v1
kind: Service
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 8080

---
# Headless: DNS round-robin, không có VIP (StatefulSet)
apiVersion: v1
kind: Service
spec:
  clusterIP: None                    # headless
  selector:
    app: mydb
  ports:
    - port: 5432
```

### How – ConfigMap & Secret (≈ docker config/secret)

```yaml
# ConfigMap (non-sensitive config)
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_LOG_LEVEL: "info"
  DB_MAX_CONNECTIONS: "20"
  nginx.conf: |
    server {
      listen 80;
      location / { proxy_pass http://app:8080; }
    }

---
# Secret (sensitive data – base64 encoded, NOT encrypted by default!)
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:                          # stringData: plain text, K8s tự base64
  password: "mysecretpassword"
  api_key: "sk-prod-abc123"

---
# Dùng trong Pod
spec:
  containers:
    - name: app
      envFrom:
        - configMapRef:
            name: app-config         # inject tất cả keys như env vars
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
      volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf        # mount 1 file cụ thể

  volumes:
    - name: nginx-config
      configMap:
        name: app-config
```

---

## 3. StatefulSet & PersistentVolumes

### How – StatefulSet (≈ docker service với sticky storage)

```yaml
# StatefulSet: cho stateful apps (DB, Kafka, Elasticsearch)
# Pods có tên ổ định: mydb-0, mydb-1, mydb-2
# Mỗi pod có PVC riêng (không share)

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres-headless     # cần Headless Service
  replicas: 3
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
          image: postgres:16
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data

  # PVC template: tạo PVC riêng cho mỗi pod
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: gp3
        resources:
          requests:
            storage: 50Gi
```

### How – PersistentVolume & PVC (≈ docker volume)

```yaml
# StorageClass: định nghĩa "loại" storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com         # AWS EBS CSI driver
parameters:
  type: gp3
  throughput: "125"
  iops: "3000"
reclaimPolicy: Retain                 # giữ PV sau khi PVC xóa (không mất data)
volumeBindingMode: WaitForFirstConsumer  # tạo volume cùng AZ với pod

---
# PVC (tương đương docker volume create)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce                   # chỉ 1 pod đọc/ghi cùng lúc
    # ReadWriteMany: NFS, EFS (nhiều pods)
    # ReadOnlyMany: shared read-only
  storageClassName: gp3
  resources:
    requests:
      storage: 20Gi
```

---

## 4. Scheduling & Placement

### How – Node Selection (≈ Swarm placement constraints)

```yaml
# nodeSelector: simple matching
spec:
  nodeSelector:
    disk: ssd
    region: ap-southeast-1

---
# Node Affinity: flexible rules
spec:
  affinity:
    nodeAffinity:
      # Required (hard constraint)
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node.kubernetes.io/instance-type
                operator: In
                values: ["m5.xlarge", "m5.2xlarge"]

      # Preferred (soft constraint – tương đương Swarm placement preference)
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          preference:
            matchExpressions:
              - key: zone
                operator: In
                values: ["ap-southeast-1a"]

    # Pod Affinity: schedule gần pods khác
    podAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: cache         # schedule gần cache pods (giảm latency)
            topologyKey: kubernetes.io/hostname

    # Pod Anti-Affinity: spread pods ra nhiều nodes
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: myapp           # không schedule 2 myapp pods trên cùng node
          topologyKey: kubernetes.io/hostname
```

### How – Taints & Tolerations (≈ Swarm drain)

```bash
# Taint node: ngăn pods thường schedule lên đây
kubectl taint nodes node1 dedicated=gpu:NoSchedule

# Toleration: pods "chịu đựng" taint, được schedule lên node đó
spec:
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "gpu"
      effect: "NoSchedule"

# Taint effects:
# NoSchedule: không schedule pods mới (pods cũ không bị evict)
# PreferNoSchedule: cố không schedule (soft)
# NoExecute: evict pods hiện tại không có toleration
```

---

## 5. Auto-scaling

### How – HPA (Horizontal Pod Autoscaler)

```yaml
# HPA: tự động thay đổi số replicas dựa trên metrics
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
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70     # scale khi CPU > 70%
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
    # Custom metrics (via Prometheus Adapter)
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "1000"
```

---

## 6. Ingress (≈ Nginx/Traefik Reverse Proxy)

```yaml
# Ingress: L7 routing (HTTP/HTTPS) vào cluster
# Cần Ingress Controller (nginx-ingress, Traefik, AWS ALB Controller...)

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: letsencrypt-prod  # TLS tự động
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls           # cert-manager tạo Secret này
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
```

---

## 7. Quick Reference: Docker → kubectl

```bash
# Docker → kubectl mapping

docker ps                            → kubectl get pods
docker ps -a                         → kubectl get pods -A (all namespaces)
docker run myapp                     → kubectl run myapp --image=myapp
docker exec -it myapp bash           → kubectl exec -it myapp -- bash
docker logs myapp                    → kubectl logs myapp
docker logs -f myapp                 → kubectl logs -f myapp
docker inspect myapp                 → kubectl describe pod myapp
docker stop myapp                    → kubectl delete pod myapp
docker rm myapp                      → kubectl delete pod myapp (same)
docker stats                         → kubectl top pods
docker pull myapp:latest             → (handled by kubelet)
docker build + push                  → CI/CD pipeline → kubectl apply

# Service management
docker service create                → kubectl create deployment
docker service scale app=5           → kubectl scale deployment/app --replicas=5
docker service update --image        → kubectl set image deployment/app app=myapp:v2
docker service rollback              → kubectl rollout undo deployment/app
docker service rm                    → kubectl delete deployment/app

# Config/Secrets
docker secret create                 → kubectl create secret generic
docker config create                 → kubectl create configmap

# Networking
docker network create                → kubectl create namespace (scope)
docker run -p 8080:80               → Service type=NodePort/LoadBalancer
```

### Compare – K8s Managed vs Self-hosted

| | EKS (AWS) | GKE (Google) | AKS (Azure) | Self-hosted (kubeadm) |
|--|----------|-------------|------------|----------------------|
| Control plane | AWS managed | Google managed | Azure managed | Tự quản lý |
| Cost | $0.10/hr cluster + nodes | Free control plane | Free control plane | Node cost only |
| Upgrades | Semi-auto | Auto | Auto | Manual |
| Complexity | Trung bình | Thấp | Trung bình | Cao |
| Flexibility | Trung bình | Trung bình | Trung bình | Cao |
| Best for | AWS ecosystem | Start here | Azure ecosystem | Air-gapped/custom |

### Trade-offs
- K8s: powerful nhưng operational overhead cao; cần dedicated DevOps/Platform team
- EKS/GKE/AKS: giảm overhead control plane nhưng vẫn cần manage worker nodes, networking, storage
- Swarm → K8s migration: Docker images tương thích 100%; YAML manifests cần viết lại
- K8s YAML verbose hơn Compose nhưng expressiveness cao hơn nhiều

### Real-world Usage
```bash
# Kubernetes quick start (minikube)
minikube start --cpus=4 --memory=8192

# Deploy sample app
kubectl create deployment myapp --image=myapp:1.0 --replicas=3
kubectl expose deployment myapp --port=80 --target-port=8080 --type=LoadBalancer
kubectl get service myapp   # lấy EXTERNAL-IP

# Scale
kubectl scale deployment myapp --replicas=5

# Rolling update
kubectl set image deployment/myapp myapp=myapp:2.0
kubectl rollout status deployment/myapp
kubectl rollout undo deployment/myapp   # rollback nếu cần

# Debug pod
kubectl exec -it $(kubectl get pod -l app=myapp -o name | head -1) -- sh
kubectl describe pod $(kubectl get pod -l app=myapp -o name | head -1)
kubectl logs -l app=myapp --tail=100 -f

# Port forward (dev)
kubectl port-forward service/myapp 8080:80
```

### Ghi chú – Chủ đề tiếp theo
> Kubernetes Advanced – RBAC, Network Policies, Helm, GitOps (ArgoCD/Flux), Service Mesh (Istio)

---

*Cập nhật lần cuối: 2026-05-06*
