# Kubernetes Autoscaling Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. HPA Advanced (Horizontal Pod Autoscaler)

### What – HPA là gì?
HPA tự động scale số replicas của Deployment/StatefulSet/ReplicaSet dựa trên observed metrics (CPU, memory, custom metrics, external metrics).

### How – HPA v2 với Multiple Metrics

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 3
  maxReplicas: 50
  metrics:
  # 1. CPU utilization
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70    # 70% của requests.cpu
  # 2. Memory utilization
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  # 3. Custom metric: requests per second per pod
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "100"       # 100 RPS per pod
  # 4. External metric: SQS queue depth
  - type: External
    external:
      metric:
        name: sqs_queue_messages_visible
        selector:
          matchLabels:
            queue-name: my-task-queue
      target:
        type: AverageValue
        averageValue: "50"        # 50 messages per pod
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60      # chờ 60s ổn định trước khi scale up thêm
      policies:
      - type: Percent
        value: 100                # tối đa tăng 100% replicas mỗi lần
        periodSeconds: 30
      - type: Pods
        value: 10                 # hoặc tối đa 10 pods
        periodSeconds: 30
      selectPolicy: Max           # chọn policy cho phép scale nhiều nhất
    scaleDown:
      stabilizationWindowSeconds: 300     # đợi 5 phút trước khi scale down
      policies:
      - type: Percent
        value: 20                 # chỉ giảm 20% mỗi lần
        periodSeconds: 60
      selectPolicy: Min           # chọn policy scale down ít nhất (conservative)
```

### How – Custom Metrics với Prometheus Adapter

```yaml
# Prometheus Adapter: expose custom metrics cho HPA
helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring \
  --set prometheus.url=http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local

# Cấu hình custom metrics rules
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-adapter
  namespace: monitoring
data:
  config.yaml: |
    rules:
    # HTTP requests per second per pod
    - seriesQuery: 'http_requests_total{namespace!="",pod!=""}'
      resources:
        overrides:
          namespace: {resource: "namespace"}
          pod: {resource: "pod"}
      name:
        matches: "^(.*)_total$"
        as: "${1}_per_second"
      metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)'

    # Queue depth per pod
    - seriesQuery: 'sqs_queue_messages_visible{queue_name!=""}'
      resources:
        template: "<<.Resource>>"
      name:
        matches: "sqs_queue_messages_visible"
        as: "sqs_queue_messages_visible"
      metricsQuery: 'avg(<<.Series>>{<<.LabelMatchers>>})'
```

```bash
# Verify custom metrics available
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq '.resources[] | .name'
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/production/pods/*/http_requests_per_second"
kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/production/sqs_queue_messages_visible"
```

---

## 2. VPA (Vertical Pod Autoscaler)

### What – VPA là gì?
VPA tự động điều chỉnh CPU và memory requests/limits của Pods dựa trên actual usage. Khác HPA: scale "up/down" resources, không scale replicas.

### How – VPA Setup

```bash
# Cài VPA
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-up.sh

# Hoặc Helm
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm install vpa fairwinds-stable/vpa --namespace kube-system
```

```yaml
# VPA Resource
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Auto"    # Off | Initial | Recreate | Auto
    # Off: chỉ recommend, không apply
    # Initial: apply khi pod tạo mới (không restart existing)
    # Recreate: restart pods để apply recommendations
    # Auto: như Recreate hiện tại (future: in-place update)
  resourcePolicy:
    containerPolicies:
    - containerName: "app"
      minAllowed:
        cpu: 100m          # VPA không recommend xuống dưới 100m CPU
        memory: 128Mi
      maxAllowed:
        cpu: "4"           # VPA không recommend lên quá 4 CPU
        memory: 4Gi
      controlledResources: ["cpu", "memory"]
      controlledValues: RequestsAndLimits    # hoặc RequestsOnly
    - containerName: "sidecar"
      mode: "Off"          # disable VPA cho sidecar container
```

```bash
# Xem VPA recommendations
kubectl describe vpa myapp-vpa -n production
# Recommendation:
#   Container Recommendations:
#     Container Name: app
#     Target:
#       CPU: 250m
#       Memory: 512Mi
#     Lower Bound:
#       CPU: 100m
#       Memory: 256Mi
#     Upper Bound:
#       CPU: 1000m
#       Memory: 2Gi
#     Uncapped Target:
#       CPU: 200m
#       Memory: 400Mi
```

### How – VPA Best Practices

```yaml
# Pattern: VPA Off mode để gather data, rồi set requests manually
# 1. Deploy VPA với updateMode: Off
# 2. Chạy load test 1-2 tuần
# 3. Đọc recommendations
# 4. Update Deployment với recommended values
# 5. Optional: switch sang updateMode: Initial hoặc Auto

# KHÔNG dùng VPA + HPA cùng CPU/memory metric
# Dùng VPA + HPA với custom metrics (HPA scale replicas, VPA tune resources)
# Hoặc dùng KEDA thay HPA để tránh conflict

# HPA + VPA coexistence (safe):
# - HPA: scaleOn custom metric (requests per second)
# - VPA: tune CPU/memory requests
# KHÔNG dùng HPA với CPU/Memory nếu VPA cũng manage CPU/Memory
```

---

## 3. KEDA (Kubernetes Event-driven Autoscaling)

### What – KEDA là gì?
KEDA extends HPA để scale dựa trên event sources: message queues, databases, HTTP traffic, cron schedules. Hỗ trợ scale to zero.

### How – KEDA ScaledObject

```yaml
# SQS-based scaling
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: myapp-sqs-scaler
  namespace: production
spec:
  scaleTargetRef:
    name: myapp-worker
  pollingInterval: 15            # check mỗi 15s
  cooldownPeriod: 300            # đợi 5 phút sau khi scale down
  idleReplicaCount: 0            # scale to zero khi queue empty
  minReplicaCount: 0
  maxReplicaCount: 50
  fallback:
    failureThreshold: 3          # fallback sau 3 lần check lỗi
    replicas: 5                  # giữ 5 replicas khi scaler fails
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-east-1.amazonaws.com/123456789/my-tasks
      queueLength: "10"          # 10 messages per replica
      awsRegion: us-east-1
    authenticationRef:
      name: keda-aws-credentials

---
# Kafka scaling
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
spec:
  scaleTargetRef:
    name: kafka-consumer
  minReplicaCount: 1
  maxReplicaCount: 30
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.kafka.svc.cluster.local:9092
      consumerGroup: my-consumer-group
      topic: my-topic
      lagThreshold: "100"        # scale up khi lag > 100 messages per partition

---
# HTTP scaling (HTTP Add-on)
apiVersion: keda.sh/v1alpha1
kind: HTTPScaledObject
metadata:
  name: myapp-http-scaler
spec:
  hosts:
  - myapp.com
  targetPendingRequests: 100    # 100 pending requests per replica
  scaleTargetRef:
    deployment: myapp
    service: myapp-svc
    port: 80
  replicas:
    min: 0                      # scale to zero khi không có traffic
    max: 20

---
# Cron scaling
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: report-cron-scaler
spec:
  scaleTargetRef:
    name: report-generator
  minReplicaCount: 0
  maxReplicaCount: 5
  triggers:
  - type: cron
    metadata:
      timezone: Asia/Ho_Chi_Minh
      start: "0 8 * * 1-5"    # 8 AM Mon-Fri
      end: "0 18 * * 1-5"     # 6 PM Mon-Fri
      desiredReplicas: "3"    # 3 replicas trong giờ làm việc

---
# TriggerAuthentication (AWS IRSA)
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-aws-credentials
  namespace: production
spec:
  podIdentity:
    provider: aws    # dùng IRSA (IAM Role for Service Account)
    # KEDA sẽ assume IAM role từ annotation của ServiceAccount
```

---

## 4. Cluster Autoscaler

### What – Cluster Autoscaler là gì?
Cluster Autoscaler (CA) tự động thêm/xóa Nodes khi:
- **Scale up**: có Pods Pending vì không đủ resources
- **Scale down**: có Nodes underutilized (utilization < threshold) trong thời gian dài

### How – AWS EKS Cluster Autoscaler

```bash
# IAM Policy cho Cluster Autoscaler
# Permission cần: ec2:DescribeInstances, autoscaling:SetDesiredCapacity, etc.
aws iam create-policy \
  --policy-name ClusterAutoScalerPolicy \
  --policy-document file://ca-policy.json

# ca-policy.json (tóm tắt):
# {
#   "Statement": [
#     {
#       "Action": [
#         "autoscaling:DescribeAutoScalingGroups",
#         "autoscaling:SetDesiredCapacity",
#         "autoscaling:TerminateInstanceInAutoScalingGroup",
#         "ec2:DescribeInstanceTypes",
#         "ec2:DescribeLaunchTemplateVersions"
#       ],
#       "Effect": "Allow",
#       "Resource": "*"
#     }
#   ]
# }

# Cài Cluster Autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-cluster \
  --set awsRegion=us-east-1 \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123:role/ClusterAutoScalerRole \
  --set extraArgs.balance-similar-node-groups=true \
  --set extraArgs.skip-nodes-with-system-pods=false \
  --set extraArgs.scale-down-delay-after-add=5m \
  --set extraArgs.scale-down-unneeded-time=10m \
  --set extraArgs.scale-down-utilization-threshold=0.5
```

```yaml
# Node group annotations cho CA
# aws autoscaling group tags:
# k8s.io/cluster-autoscaler/enabled: "true"
# k8s.io/cluster-autoscaler/my-cluster: "owned"

# Priority Expander: prefer specific node groups
# /etc/kubernetes/cluster-autoscaler-priority-expander.yaml:
priorities:
  50:
  - .*spot.*       # prefer spot instances (cheaper)
  40:
  - .*m5.*         # fallback to m5
  10:
  - .*m5.xlarge.*  # last resort: larger instances
```

### How – CA Tuning

```bash
# Quan trọng: Pods cần requests để CA tính được capacity
# CA KHÔNG scale up nếu pods không có resource requests

# Pod Disruption Budget: CA sẽ không xóa node nếu vi phạm PDB
kubectl get pdb -n production   # xem PDBs

# Node Taint: ngăn CA xóa node quan trọng
kubectl taint node critical-node cluster-autoscaler.kubernetes.io/scale-down-disabled=true:NoSchedule

# Overprovisioning: luôn có node "trống" để deploy nhanh
# Tạo low-priority deployment chiếm resource trước
apiVersion: apps/v1
kind: Deployment
metadata:
  name: overprovisioning
spec:
  replicas: 3
  template:
    spec:
      priorityClassName: "overprovisioning"   # thấp nhất
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
        resources:
          requests:
            cpu: "1"
            memory: 2Gi
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: overprovisioning
value: -1        # negative priority → bị preempt khi pods thật cần resources
globalDefault: false
preemptionPolicy: Never
```

---

## 5. Karpenter (Next-gen Autoscaling)

### What – Karpenter là gì?
Karpenter là node provisioner từ AWS (CNCF). Khác Cluster Autoscaler: Karpenter tạo nodes trực tiếp từ cloud API (không cần pre-configured node groups), chọn instance type tối ưu cho workload.

### How – Karpenter NodePool

```yaml
# NodePool: define quy tắc provisioning nodes
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: general-purpose
spec:
  template:
    spec:
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand", "spot"]    # spot trước, fallback on-demand
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["c", "m", "r"]          # compute/memory/resource optimized
      - key: karpenter.k8s.aws/instance-generation
        operator: Gt
        values: ["2"]                     # chỉ gen 3+
      - key: kubernetes.io/arch
        operator: In
        values: ["amd64"]
      - key: kubernetes.io/os
        operator: In
        values: ["linux"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: general-purpose
      taints: []
      labels:
        node-group: general-purpose
  limits:
    cpu: "1000"                # max 1000 CPUs total trong NodePool
    memory: 4000Gi
  disruption:
    consolidationPolicy: WhenUnderutilized    # xóa nodes underutilized
    consolidateAfter: 30s                     # đợi 30s trước khi consolidate
    expireAfter: 720h                         # force-replace nodes sau 30 ngày

---
# EC2NodeClass: AWS-specific config
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: general-purpose
spec:
  amiFamily: AL2              # Amazon Linux 2
  role: KarpenterNodeRole     # IAM role cho nodes
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster    # auto-discover subnets by tag
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: my-cluster
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeSize: 50Gi
      volumeType: gp3
      encrypted: true
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2   # security: limit hops cho IMDS
    httpTokens: required          # IMDSv2 required (more secure)
```

```yaml
# NodePool cho GPU workloads
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: gpu-nodes
spec:
  template:
    spec:
      requirements:
      - key: karpenter.k8s.aws/instance-category
        operator: In
        values: ["g", "p"]    # GPU instances
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["on-demand"] # GPU spot ít available hơn
      taints:
      - key: nvidia.com/gpu
        effect: NoSchedule    # chỉ GPU workloads schedule lên đây
      nodeClassRef:
        name: gpu-nodes
  limits:
    cpu: "400"
  disruption:
    consolidationPolicy: WhenEmpty    # chỉ remove khi completely empty
    consolidateAfter: 1m
```

---

### Compare – Autoscaling Solutions

| | HPA | VPA | KEDA | Cluster Autoscaler | Karpenter |
|--|-----|-----|------|-------------------|-----------|
| **What scales** | Replicas | Resources (CPU/mem) | Replicas | Nodes | Nodes |
| **Trigger** | CPU/mem/custom | Historical usage | Events/queues | Pending pods | Pending pods |
| **Scale to zero** | No (min 1) | No | Yes | No | No |
| **Custom metrics** | Yes (adapter) | No | Yes (50+ sources) | No | No |
| **Node groups** | N/A | N/A | N/A | Pre-configured | Dynamic |
| **Best for** | Web services | Batch/variable load | Event-driven | GKE/EKS standard | AWS EKS optimal |

### Trade-offs
- HPA + CA: phổ biến nhất; HPA scale pods, CA scale nodes. Nhưng CA chậm hơn Karpenter
- VPA restart: updateMode Auto restart pods để apply resources → downtime nếu không có PDB
- KEDA scale-to-zero: tiết kiệm chi phí nhưng cold start latency khi traffic đến sau 0 replicas
- Karpenter consolidation: tiết kiệm chi phí nhưng có thể gây node churn; cần tune consolidateAfter

### Real-world Usage
```bash
# Xem HPA status
kubectl get hpa -n production
kubectl describe hpa myapp-hpa -n production
# Current Metrics:
#   Resource cpu on pods:  45% (target 70%)
#   Custom metric http_requests_per_second: 85 (target 100)

# Simulate load test rồi xem HPA hoạt động
kubectl run -n production load-test --rm -it --image=busybox -- \
  sh -c "while true; do wget -q -O- http://myapp-svc/api/test; done"
kubectl get hpa myapp-hpa -n production --watch

# VPA recommendations dry-run
kubectl get vpa -n production -o json | jq '
  .items[] |
  {
    name: .metadata.name,
    container: .status.recommendation.containerRecommendations[0].containerName,
    target: .status.recommendation.containerRecommendations[0].target
  }'

# KEDA: kiểm tra scaled objects
kubectl get scaledobject -n production
kubectl describe scaledobject myapp-sqs-scaler -n production

# Karpenter: xem provisioned nodes
kubectl get nodes -l karpenter.sh/nodepool=general-purpose
kubectl get nodeclaims    # Karpenter-managed nodes
```

### Ghi chú – Chủ đề tiếp theo
> Production Patterns – Canary deployments với Argo Rollouts, zero-downtime deploy checklist, multi-tenancy với namespace isolation, ResourceQuota enforcement

---

*Cập nhật lần cuối: 2026-05-06*
