# Kubernetes Storage Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. CSI (Container Storage Interface) Deep Dive

### What – CSI là gì?
CSI là standard interface giữa Kubernetes và storage vendors. CSI driver chạy như Pods trên cluster, thực hiện các operations: CreateVolume, DeleteVolume, ControllerPublishVolume (attach), NodeStageVolume (mount).

### How – CSI Architecture

```
CSI Architecture:
┌─────────────────────────────────────────────────────────┐
│ Kubernetes Control Plane                                │
│  ├── external-provisioner (sidecar)                    │
│  │   → Watch PVC → gọi CSI CreateVolume               │
│  ├── external-attacher (sidecar)                       │
│  │   → Watch VolumeAttachment → gọi CSI Attach        │
│  └── external-snapshotter (sidecar)                    │
│      → Watch VolumeSnapshot → gọi CSI CreateSnapshot  │
│                                                         │
│ CSI Driver (DaemonSet trên worker nodes):              │
│  ├── node-driver-registrar: register CSI với kubelet  │
│  └── CSI driver container (vendor code)               │
│      → NodeStageVolume: format & mount                │
│      → NodePublishVolume: bind mount vào pod          │
└─────────────────────────────────────────────────────────┘

Volume lifecycle:
Create PVC → Provision volume (CreateVolume) → Attach to node (ControllerPublish)
→ Stage (NodeStageVolume: format) → Publish (NodePublishVolume: bind mount into pod)
```

### How – StorageClass Configuration

```yaml
# AWS EBS CSI Driver StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"    # MB/s
  encrypted: "true"
  kmsKeyId: "arn:aws:kms:us-east-1:123456789:key/xxx"
volumeBindingMode: WaitForFirstConsumer    # chờ pod schedule xong rồi mới provision
reclaimPolicy: Delete
allowVolumeExpansion: true
allowedTopologies:
- matchLabelExpressions:
  - key: topology.ebs.csi.aws.com/zone
    values:
    - us-east-1a
    - us-east-1b

---
# GKE Persistent Disk StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: pd-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
  replication-type: regional-pd    # cross-zone replication
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain              # KHÔNG xóa PV khi xóa PVC
allowVolumeExpansion: true

---
# NFS StorageClass (dùng cho ReadWriteMany)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-client
provisioner: k8s-sigs.io/nfs-subdir-external-provisioner
parameters:
  server: nfs-server.example.com
  path: /shared/data
  archiveOnDelete: "false"    # false: xóa data khi PVC deleted; true: archive
reclaimPolicy: Delete
```

### How – PVC và StatefulSet

```yaml
# PVC manual
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc
  namespace: production
  annotations:
    volume.beta.kubernetes.io/storage-provisioner: ebs.csi.aws.com
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 50Gi
  selector:              # bind đến PV cụ thể (nếu pre-provisioned)
    matchLabels:
      app: mydb

---
# Pod dùng PVC
spec:
  containers:
  - name: postgres
    volumeMounts:
    - name: data
      mountPath: /var/lib/postgresql/data
      subPath: pgdata    # mount subpath (không mount toàn bộ volume)
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: database-pvc
```

### How – Volume Expansion

```bash
# 1. StorageClass phải có allowVolumeExpansion: true
# 2. Resize PVC
kubectl patch pvc database-pvc -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# 3. Xem status expansion
kubectl get pvc database-pvc
# → Nếu pod đang chạy: filesystem resize tự động (online expansion)
# → Nếu pod đang dừng: filesystem resize khi pod restart

kubectl describe pvc database-pvc | grep -A5 "Conditions:"
# Type:                      FileSystemResizePending
# Status:                    True
# → sau khi pod restart sẽ thành FileSystemResizeSuccess

# Verify trong pod
kubectl exec -it postgres-0 -- df -h /var/lib/postgresql/data
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/xvda       100G   50G   50G  50% /var/lib/postgresql/data
```

---

## 2. Volume Snapshots

### How – Volume Snapshot API

```yaml
# VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-vsc
  annotations:
    snapshot.storage.kubernetes.io/is-default-class: "true"
driver: ebs.csi.aws.com
deletionPolicy: Delete    # Delete: xóa snapshot khi object bị xóa
                          # Retain: giữ snapshot trong cloud

---
# VolumeSnapshot: tạo snapshot từ PVC
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-20260506
  namespace: production
spec:
  volumeSnapshotClassName: ebs-vsc
  source:
    persistentVolumeClaimName: database-pvc  # source PVC

---
# Restore: tạo PVC từ snapshot
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc-restored
  namespace: production
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 50Gi    # phải >= snapshot size
  dataSource:
    name: postgres-snapshot-20260506    # từ snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

```bash
# Tạo snapshot
kubectl apply -f snapshot.yaml

# Kiểm tra status
kubectl get volumesnapshot postgres-snapshot-20260506
# → ReadyToUse: true

kubectl describe volumesnapshot postgres-snapshot-20260506
# SnapshotHandle: snap-xxxxxxxxxxxxxxxxx (AWS snapshot ID)

# Scheduled snapshots với CronJob
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-snapshot
spec:
  schedule: "0 */6 * * *"    # mỗi 6 giờ
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: snapshot-creator
          containers:
          - name: snapshot
            image: bitnami/kubectl:latest
            command:
            - sh
            - -c
            - |
              SNAPSHOT_NAME="postgres-$(date +%Y%m%d-%H%M%S)"
              kubectl apply -f - <<EOF
              apiVersion: snapshot.storage.k8s.io/v1
              kind: VolumeSnapshot
              metadata:
                name: $SNAPSHOT_NAME
                namespace: production
              spec:
                volumeSnapshotClassName: ebs-vsc
                source:
                  persistentVolumeClaimName: database-pvc
              EOF
              # Cleanup snapshots cũ hơn 7 ngày
              kubectl get volumesnapshot -n production \
                --sort-by=.metadata.creationTimestamp \
                -o jsonpath='{range .items[?(@.status.readyToUse==true)]}{.metadata.name}{"\n"}{end}' | \
                head -n -4 | xargs -r kubectl delete volumesnapshot -n production
          restartPolicy: OnFailure
```

---

## 3. ReadWriteMany (RWX) Storage

### What – RWX Use Cases
RWX (ReadWriteMany) cho phép nhiều pods trên nhiều nodes đọc/ghi cùng một volume. Dùng cho: shared config, media files, ML model files, web assets.

### How – NFS cho RWX

```bash
# Cài NFS Subdir External Provisioner
helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=10.0.0.100 \
  --set nfs.path=/exports/k8s \
  --set storageClass.name=nfs-client \
  --set storageClass.reclaimPolicy=Retain
```

```yaml
# PVC với RWX
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-assets
spec:
  accessModes:
  - ReadWriteMany    # nhiều pods, nhiều nodes cùng đọc/ghi
  storageClassName: nfs-client
  resources:
    requests:
      storage: 100Gi
---
# Deployment dùng RWX PVC
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-server
spec:
  replicas: 5    # 5 replicas, tất cả mount cùng volume
  template:
    spec:
      containers:
      - name: nginx
        volumeMounts:
        - name: assets
          mountPath: /usr/share/nginx/html
          readOnly: true    # web servers chỉ cần đọc
      volumes:
      - name: assets
        persistentVolumeClaim:
          claimName: shared-assets
```

### How – AWS EFS (Elastic File System) cho RWX

```yaml
# EFS StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap        # EFS Access Point
  fileSystemId: fs-xxxxxxxxx      # EFS file system ID
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: /dynamic-provisioning

---
# PVC trên EFS
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-models
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi    # EFS: không giới hạn thực sự, đây chỉ là label
```

---

## 4. Velero – Backup & Restore

### What – Velero là gì?
Velero backup toàn bộ Kubernetes resources (YAML) + PersistentVolumes, lưu vào object storage (S3/GCS/Azure). Hỗ trợ DR (disaster recovery) và cluster migration.

### How – Cài Velero

```bash
# Cài Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xzf velero-v1.13.0-linux-amd64.tar.gz
mv velero /usr/local/bin/

# Cài Velero vào cluster (AWS S3)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket my-velero-backups \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1 \
  --secret-file ./credentials-velero \
  --use-node-agent \               # dùng node agent để backup PVs (file-level)
  --default-volumes-to-fs-backup   # mặc định backup PVs bằng file-system backup

# credentials-velero:
# [default]
# aws_access_key_id = AKIAIOSFODNN7EXAMPLE
# aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

### How – Backup Operations

```bash
# Backup toàn bộ cluster
velero backup create full-cluster-backup --include-namespaces='*'

# Backup namespace cụ thể
velero backup create production-backup \
  --include-namespaces production \
  --ttl 168h           # giữ 7 ngày

# Backup với label selector
velero backup create app-backup \
  --selector app=myapp \
  --include-namespaces production

# Backup exclude resources
velero backup create production-backup \
  --include-namespaces production \
  --exclude-resources events,endpoints

# Xem backup
velero backup get
# NAME                    STATUS     ERRORS  WARNINGS  CREATED                         EXPIRES  STORAGE LOCATION
# production-backup       Completed  0       0         2026-05-06 10:00:00 +0000 UTC   6d       default

# Describe backup chi tiết
velero backup describe production-backup --details

# Logs
velero backup logs production-backup
```

### How – Scheduled Backups

```bash
# Backup hàng ngày lúc 2 AM
velero schedule create daily-production \
  --schedule="0 2 * * *" \
  --include-namespaces production \
  --ttl 168h \               # giữ 7 ngày
  --storage-location default

# Backup mỗi 6 giờ
velero schedule create frequent-backup \
  --schedule="0 */6 * * *" \
  --include-namespaces production \
  --ttl 24h

# Xem schedules
velero schedule get

# Manual trigger từ schedule
velero backup create --from-schedule daily-production
```

### How – Restore Operations

```bash
# Restore toàn bộ từ backup
velero restore create --from-backup production-backup

# Restore namespace cụ thể
velero restore create production-restore \
  --from-backup full-cluster-backup \
  --include-namespaces production

# Restore vào namespace khác (migration)
velero restore create \
  --from-backup production-backup \
  --namespace-mappings production:production-restored

# Restore chỉ specific resources
velero restore create \
  --from-backup production-backup \
  --include-resources deployments,services,configmaps,secrets

# Xem restore status
velero restore get
velero restore describe production-restore

# Restore logs
velero restore logs production-restore
```

### How – Velero Hooks (Pre/Post Backup)

```yaml
# Annotation trên Pod: chạy command trước/sau backup
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  template:
    metadata:
      annotations:
        # Pre-backup: flush buffers, tạo consistent snapshot
        pre.hook.backup.velero.io/command: '["/bin/bash", "-c", "psql -U postgres -c CHECKPOINT;"]'
        pre.hook.backup.velero.io/timeout: "60s"
        pre.hook.backup.velero.io/on-error: Fail
        # Post-backup: resume operations
        post.hook.backup.velero.io/command: '["/bin/bash", "-c", "echo backup done"]'
```

---

## 5. Storage Performance Patterns

### How – Storage Class Tiering

```yaml
# Tier 1: Ultra-fast (NVMe SSD, database primary)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ultra-fast
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-extreme       # GKE pd-extreme: NVMe SSD
  provisioned-iops-on-create: "10000"
  provisioned-throughput-on-create: "1200"  # MB/s
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer

---
# Tier 2: Fast (SSD, general workloads)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd

---
# Tier 3: Standard (HDD, cold storage)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-standard
```

### How – Node-local Storage (hostPath và local PV)

```yaml
# Local PV: performance tốt nhất (direct disk access)
# ⚠️ Node-bound: pod PHẢI schedule trên node có disk đó
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-node1
spec:
  capacity:
    storage: 500Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/nvme/disk1     # NVMe disk trên node1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - node1    # PV chỉ dùng được trên node1
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner   # không dynamic provisioning
volumeBindingMode: WaitForFirstConsumer      # QUAN TRỌNG: chờ pod schedule
```

---

### Compare – Storage Options

| | hostPath | Local PV | NFS/EFS | Cloud Block (EBS/PD) | Cloud Object (S3) |
|--|----------|----------|---------|---------------------|-------------------|
| **Access Mode** | RWO | RWO | RWX | RWO | N/A (app SDK) |
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Availability** | Node local | Node local | High | AZ | Region |
| **Use case** | Dev only | DB, cache | Shared files | General | Cold storage |
| **Multi-node** | ❌ | ❌ | ✅ | ❌ | ✅ |
| **Dynamic provision** | ❌ | ❌ | ✅ | ✅ | ✅ |

### Trade-offs
- WaitForFirstConsumer: tránh cross-AZ volume attachment (AZ của PV != AZ của Pod) → bắt buộc dùng
- ReclaimPolicy Retain: an toàn hơn Delete nhưng cần tay dọn dẹp PV cũ
- Velero fs-backup: chậm hơn snapshot backup nhưng portable (không tied to cloud provider)
- Local PV: hiệu năng cao nhất nhưng không có HA (node fail = data unavailable)

### Real-world Usage
```bash
# Kiểm tra storage health
kubectl get pv,pvc -A | grep -v Bound   # tìm PV/PVC không ở trạng thái Bound

# Tìm PVC có volume expansion pending
kubectl get pvc -A -o json | jq -r '
  .items[] |
  select(.status.conditions[]?.type == "FileSystemResizePending") |
  "\(.metadata.namespace)/\(.metadata.name)"'

# Velero backup verify
velero backup describe production-backup
# → Xem Phase: Completed, Errors: 0, Warnings: 0

# Test restore thường xuyên (backup không có nghĩa gì nếu không restore được)
velero restore create test-restore \
  --from-backup production-backup \
  --namespace-mappings production:restore-test

kubectl get all -n restore-test   # verify đủ resources

kubectl delete namespace restore-test  # cleanup

# Xem storage usage của PVCs
kubectl get pvc -A -o json | jq -r '
  .items[] |
  "\(.metadata.namespace)/\(.metadata.name): \(.spec.resources.requests.storage)"'
```

### Ghi chú – Chủ đề tiếp theo
> RBAC & Policy Deep – RBAC audit với rbac-tool, OPA Gatekeeper admission controller, Kyverno policy engine

---

*Cập nhật lần cuối: 2026-05-06*
