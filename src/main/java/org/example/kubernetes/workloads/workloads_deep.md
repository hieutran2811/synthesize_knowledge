# Kubernetes Workloads Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Deployment Strategies

### What – Deployment Strategies là gì?
Deployment Strategies kiểm soát cách Kubernetes thay thế pods cũ bằng pods mới, đảm bảo zero-downtime và risk mitigation khi release.

### How – RollingUpdate (mặc định)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2          # tối đa 8 pods cùng tồn tại (6 + 2)
      maxUnavailable: 1    # tối thiểu 5 pods available trong suốt update
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        version: v2
    spec:
      containers:
      - name: app
        image: myapp:v2
        readinessProbe:           # QUAN TRỌNG: phải có để rolling update an toàn
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 3
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 5"]  # drain inflight requests
      terminationGracePeriodSeconds: 30
```

```bash
# Monitor rolling update progress
kubectl rollout status deployment/myapp --watch
# Waiting for deployment "myapp" rollout to finish: 2 out of 6 new replicas updated...

# History
kubectl rollout history deployment/myapp
# REVISION  CHANGE-CAUSE
# 1         kubectl apply --record
# 2         Update image to v2

# Rollback
kubectl rollout undo deployment/myapp                  # về revision trước
kubectl rollout undo deployment/myapp --to-revision=1  # về revision cụ thể

# Pause/Resume (manual canary)
kubectl rollout pause deployment/myapp   # dừng lại sau N replicas updated
kubectl rollout resume deployment/myapp  # tiếp tục
```

### How – Blue-Green Deployment

```
Blue-Green Architecture:
┌─────────────────────────────────────────────┐
│  Service (selector: version: blue)          │
│       ↓                                     │
│  Blue Deployment (current, v1)              │  ← production traffic
│  Green Deployment (new, v2)                 │  ← test & verify
└─────────────────────────────────────────────┘

Khi switch: thay selector Service → version: green
Rollback: thay lại selector → version: blue (instant)
```

```yaml
# Blue Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
      - name: app
        image: myapp:v1
---
# Green Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
      - name: app
        image: myapp:v2
---
# Service: switch bằng cách thay đổi selector
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp
    version: blue    # ← thay thành green để switch
  ports:
  - port: 80
    targetPort: 8080
```

```bash
# Switch traffic: Blue → Green
kubectl patch service myapp -p '{"spec":{"selector":{"version":"green"}}}'

# Verify
kubectl get endpoints myapp   # phải thấy green pods

# Rollback instant
kubectl patch service myapp -p '{"spec":{"selector":{"version":"blue"}}}'

# Cleanup sau khi stable
kubectl delete deployment myapp-blue
```

### How – Canary Deployment (Native K8s)

```yaml
# Stable Deployment: 9 replicas
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
      - name: app
        image: myapp:v1
---
# Canary Deployment: 1 replica = 10% traffic
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-canary
spec:
  replicas: 1    # 1/(9+1) = 10%
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
      - name: app
        image: myapp:v2
---
# Service: select both (chỉ match app: myapp)
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  selector:
    app: myapp    # match cả stable và canary
  ports:
  - port: 80
    targetPort: 8080
```

```bash
# Tăng canary dần dần
# 20%: stable=8, canary=2
kubectl scale deployment myapp-stable --replicas=8
kubectl scale deployment myapp-canary --replicas=2

# 50%: stable=5, canary=5
kubectl scale deployment myapp-stable --replicas=5
kubectl scale deployment myapp-canary --replicas=5

# Full rollout:
kubectl scale deployment myapp-stable --replicas=0
kubectl scale deployment myapp-canary --replicas=10
# Rename canary → stable (hoặc dùng new deployment)
```

### How – Argo Rollouts (Progressive Delivery)

```yaml
# Cài Argo Rollouts
# kubectl create namespace argo-rollouts
# kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 10
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:v2
        ports:
        - containerPort: 8080
  strategy:
    canary:
      canaryService: myapp-canary      # service riêng cho canary traffic
      stableService: myapp-stable      # service cho stable traffic
      trafficRouting:
        nginx:
          stableIngress: myapp-ingress  # Nginx Ingress để weight traffic
      steps:
      - setWeight: 10        # 10% traffic
      - pause: {duration: 5m}
      - analysis:            # automatic analysis sau mỗi step
          templates:
          - templateName: success-rate
      - setWeight: 30
      - pause: {duration: 10m}
      - analysis:
          templates:
          - templateName: success-rate
          - templateName: latency-p99
      - setWeight: 50
      - pause: {}            # manual pause (human approval)
      - setWeight: 100
---
# AnalysisTemplate: check success rate
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
  - name: success-rate
    successCondition: result[0] >= 0.95      # 95% success rate
    failureLimit: 3
    interval: 60s
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          sum(rate(http_requests_total{job="myapp",status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total{job="myapp"}[5m]))
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency-p99
spec:
  metrics:
  - name: latency-p99
    successCondition: result[0] <= 0.5       # p99 latency <= 500ms
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          histogram_quantile(0.99,
            rate(http_request_duration_seconds_bucket{job="myapp"}[5m]))
```

```bash
# Kubectl plugin
kubectl argo rollouts get rollout myapp --watch

# Manual promote (ở pause step)
kubectl argo rollouts promote myapp

# Abort (rollback)
kubectl argo rollouts abort myapp

# Retry sau abort
kubectl argo rollouts retry rollout myapp
```

---

## 2. StatefulSet Patterns

### What – StatefulSet Patterns
StatefulSet dành cho stateful apps cần identity ổn định (hostname, storage), ordered startup/shutdown, và sticky storage.

### How – StatefulSet Fundamentals

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres-headless       # headless service cho DNS
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0    # chỉ update pods có index >= partition
                      # partition=2: chỉ update pod-2, giữ nguyên pod-0, pod-1
  podManagementPolicy: OrderedReady    # hoặc Parallel
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
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        readinessProbe:
          exec:
            command: ["pg_isready", "-U", "postgres"]
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            memory: 256Mi
            cpu: 250m
          limits:
            memory: 1Gi
            cpu: "1"
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 10Gi
---
# Headless Service cho DNS (postgres-0.postgres-headless.default.svc.cluster.local)
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None     # headless
  selector:
    app: postgres
  ports:
  - port: 5432
---
# Regular Service cho reads (load balanced)
apiVersion: v1
kind: Service
metadata:
  name: postgres-read
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
```

### How – StatefulSet Canary Update với Partition

```bash
# Canary update StatefulSet: chỉ update pod-2 trước
kubectl patch statefulset postgres -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
kubectl set image statefulset/postgres postgres=postgres:17

# Kiểm tra
kubectl get pods -l app=postgres
# postgres-0   Running   (version 16 – không được update)
# postgres-1   Running   (version 16 – không được update)
# postgres-2   Running   (version 17 – được update)

# Nếu ok, giảm partition để update thêm
kubectl patch statefulset postgres -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
# → postgres-1 được update

kubectl patch statefulset postgres -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
# → postgres-0 được update (tất cả updated)
```

### How – StatefulSet với Init Container cho Bootstrapping

```yaml
# Pattern: PostgreSQL primary/replica setup
spec:
  initContainers:
  - name: init-replication
    image: postgres:16
    command:
    - bash
    - -c
    - |
      set -ex
      # Lấy ordinal từ hostname (postgres-0, postgres-1, ...)
      [[ $HOSTNAME =~ -([0-9]+)$ ]] || exit 1
      ordinal=${BASH_REMATCH[1]}

      if [[ $ordinal -eq 0 ]]; then
        # Primary: init nếu chưa có data
        if [ ! -d "$PGDATA/base" ]; then
          initdb
          # Tạo replication user
          pg_ctl start -w
          psql -c "CREATE USER replicator REPLICATION LOGIN ENCRYPTED PASSWORD 'replpass';"
          pg_ctl stop
        fi
      else
        # Replica: sync từ primary
        if [ ! -d "$PGDATA/base" ]; then
          until pg_isready -h postgres-0.postgres-headless -p 5432; do sleep 1; done
          pg_basebackup -h postgres-0.postgres-headless \
            -D "$PGDATA" -U replicator -P -Xs -R
        fi
      fi
    env:
    - name: PGDATA
      value: /var/lib/postgresql/data/pgdata
    volumeMounts:
    - name: data
      mountPath: /var/lib/postgresql/data
```

### How – StatefulSet Scaling Concerns

```bash
# Scale up: thêm replicas theo thứ tự (pod-3, pod-4, ...)
kubectl scale statefulset postgres --replicas=5
# Pods được tạo tuần tự: pod-3 phải Running trước khi tạo pod-4

# Scale down: xóa theo thứ tự ngược (pod-4, pod-3, ...)
kubectl scale statefulset postgres --replicas=3

# PVC KHÔNG bị xóa khi scale down (data safety)
# Để xóa PVC thủ công:
kubectl delete pvc data-postgres-3
kubectl delete pvc data-postgres-4

# podManagementPolicy: Parallel (không ordered, dùng khi không cần ordering)
# - scale up: tất cả pods tạo cùng lúc
# - scale down: tất cả pods xóa cùng lúc
```

---

## 3. DaemonSet Patterns

### How – DaemonSet Use Cases

```yaml
# Log collector DaemonSet (chạy trên mọi node)
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
  namespace: logging
spec:
  selector:
    matchLabels:
      app: fluentd
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1          # 1 node tại một thời điểm
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule        # chạy cả trên master nodes
      - key: node.kubernetes.io/not-ready
        operator: Exists
        effect: NoExecute
        tolerationSeconds: 300    # giữ 300s khi node not-ready (để drain logs)
      containers:
      - name: fluentd
        image: fluent/fluentd-kubernetes-daemonset:v1-debian-elasticsearch
        env:
        - name: FLUENT_ELASTICSEARCH_HOST
          value: elasticsearch.logging.svc.cluster.local
        resources:
          requests:
            memory: 200Mi
            cpu: 100m
          limits:
            memory: 500Mi
            cpu: 500m
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      terminationGracePeriodSeconds: 30
```

---

## 4. Job và CronJob Patterns

### How – Job Parallelism

```yaml
# Indexed Job: xử lý tasks song song với index
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processor
spec:
  completions: 20           # 20 tasks tổng
  parallelism: 5            # 5 pods chạy đồng thời
  completionMode: Indexed   # mỗi pod có JOB_COMPLETION_INDEX env
  backoffLimit: 3           # retry tối đa 3 lần per task
  ttlSecondsAfterFinished: 3600  # dọn dẹp sau 1 giờ
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: processor
        image: myprocessor:latest
        command:
        - python
        - process.py
        - --index=$(JOB_COMPLETION_INDEX)    # mỗi pod xử lý chunk khác nhau
        - --total=20
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        resources:
          requests:
            memory: 512Mi
            cpu: 500m
```

```yaml
# Work Queue Job: pods tự lấy tasks từ queue
apiVersion: batch/v1
kind: Job
metadata:
  name: queue-processor
spec:
  completions: null         # không biết trước số tasks
  parallelism: 10           # 10 workers
  completionMode: NonIndexed
  backoffLimit: 6
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: worker
        image: myworker:latest
        env:
        - name: QUEUE_URL
          value: sqs://my-queue.amazonaws.com/123/tasks
        # Worker tự detect khi queue empty → exit 0 → job complete
```

### How – CronJob Production Pattern

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-report
spec:
  schedule: "0 2 * * *"      # 2:00 AM hàng ngày (UTC)
  timeZone: "Asia/Ho_Chi_Minh"  # K8s 1.27+
  concurrencyPolicy: Forbid  # không chạy nếu job trước chưa xong
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  startingDeadlineSeconds: 300  # nếu miss schedule > 5 phút thì bỏ qua
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 86400  # dọn sau 24h
      template:
        spec:
          restartPolicy: OnFailure
          serviceAccountName: report-generator
          containers:
          - name: reporter
            image: myreporter:latest
            command: ["python", "generate_report.py"]
            env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: host
            resources:
              requests:
                memory: 256Mi
                cpu: 100m
              limits:
                memory: 512Mi
                cpu: 500m
```

```bash
# Manual trigger CronJob
kubectl create job --from=cronjob/daily-report manual-run-$(date +%s)

# Xem job history
kubectl get jobs -l job-name=daily-report

# Suspend CronJob tạm thời
kubectl patch cronjob daily-report -p '{"spec":{"suspend":true}}'
kubectl patch cronjob daily-report -p '{"spec":{"suspend":false}}'
```

---

## 5. Init Containers & Sidecar Patterns

### How – Init Container Patterns

```yaml
spec:
  initContainers:
  # 1. Wait for dependencies
  - name: wait-for-db
    image: busybox:1.35
    command:
    - sh
    - -c
    - |
      until nc -z postgres-svc 5432; do
        echo "Waiting for postgres..."
        sleep 2
      done
      echo "Postgres is up!"

  # 2. Database migration
  - name: db-migrate
    image: myapp:latest
    command: ["python", "manage.py", "migrate"]
    env:
    - name: DATABASE_URL
      valueFrom:
        secretKeyRef:
          name: app-secrets
          key: database-url

  # 3. Config injection từ external source
  - name: config-init
    image: vault:1.15
    command:
    - sh
    - -c
    - |
      vault agent -config=/vault/config/agent.hcl
    volumeMounts:
    - name: vault-config
      mountPath: /vault/config
    - name: app-config
      mountPath: /etc/app

  containers:
  - name: app
    image: myapp:latest
    volumeMounts:
    - name: app-config
      mountPath: /etc/app  # config đã được inject bởi init container
```

### How – Sidecar Pattern (K8s 1.29+ native sidecar)

```yaml
# Native Sidecar (K8s 1.29+): restartPolicy: Always trong initContainers
spec:
  initContainers:
  - name: log-forwarder           # sidecar: chạy suốt lifecycle của pod
    image: fluent-bit:latest
    restartPolicy: Always         # ← đây là native sidecar
    # Lifecycle: start trước app container, stop sau app container
    resources:
      requests:
        memory: 50Mi
        cpu: 50m
    volumeMounts:
    - name: log-volume
      mountPath: /var/log/app

  containers:
  - name: app
    image: myapp:latest
    volumeMounts:
    - name: log-volume
      mountPath: /var/log/app
```

---

### Compare – Deployment Strategies

| Strategy | Traffic Switch | Rollback Time | Resource Cost | Risk |
|----------|---------------|---------------|---------------|------|
| RollingUpdate | Gradual | Minutes (rollout) | Low (maxSurge) | Medium |
| Blue-Green | Instant | Instant | 2x resources | Low |
| Canary (Native) | Weight by replica count | Minutes | Low | Very Low |
| Canary (Argo Rollouts) | Weight by % (Nginx/Istio) | Instant (abort) | Medium | Very Low |
| Recreate | Hard cutover | Minutes (redeploy) | None | High |

### Trade-offs
- Blue-Green: cần 2x resources nhưng rollback instant; phù hợp critical services
- Canary native: traffic splitting không chính xác (phụ thuộc replica count); dùng Argo Rollouts nếu cần exact %
- StatefulSet partition: canary cho stateful apps nhưng phải test compatibility giữa versions
- Parallel podManagement: nhanh hơn nhưng app phải tolerate multiple pods starting simultaneously

### Real-world Usage
```bash
# Deployment annotation history
kubectl annotate deployment myapp kubernetes.io/change-cause="Deploy v2.1.0: Add payment feature"

# Phát hiện failed rollout sớm
kubectl rollout status deployment/myapp --timeout=5m || {
  echo "Rollout failed, rolling back!"
  kubectl rollout undo deployment/myapp
  exit 1
}

# Xem events khi deployment có vấn đề
kubectl describe deployment myapp | tail -20
kubectl get events --field-selector involvedObject.name=myapp --sort-by='.lastTimestamp'

# Scale về 0 để maintenance (thay vì delete)
kubectl scale deployment myapp --replicas=0
```

### Ghi chú – Chủ đề tiếp theo
> Networking Deep – CNI plugins (Calico/Cilium), eBPF dataplane, Gateway API vs Ingress, NetworkPolicy advanced patterns

---

*Cập nhật lần cuối: 2026-05-06*
