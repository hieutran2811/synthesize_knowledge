---
title: "SQL Server trên Linux, Docker & Kubernetes"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 2
---
# SQL Server trên Linux, Docker & Kubernetes

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)** trên Linux. SQL Server chạy trên Linux từ 2017; 2022/2025 hỗ trợ RHEL, Ubuntu LTS, SLES và container.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Architecture](../fundamentals/architecture.md), [Security](../administration/security.md). Đọc tiếp: [Data Movement](../integration/data_movement.md).

---

## 1. SQL Server trên Linux hoạt động thế nào

SQL Server trên Linux **không phải bản viết lại**. Nó dùng cùng engine với Windows, qua một lớp gọi là **SQLPAL (SQL Platform Abstraction Layer)** — Windows API mà engine cần được ánh xạ xuống syscall Linux.

```text
SQL Server engine (cùng codebase với Windows)
        │
    SQLPAL  ── ánh xạ Win32/NT API → syscall Linux
        │
    Host extension (mssql-server process)
        │
    Linux kernel
```

Hệ quả rất thực dụng: **T-SQL, plan, index, transaction, Query Store, Always On đều giống hệt Windows**. Những gì khác biệt nằm ở tầng OS: đường dẫn file, quản lý service, tài khoản, cluster manager, và một số tính năng phụ thuộc Windows.

| Giống Windows | Khác trên Linux |
|---|---|
| Engine, optimizer, T-SQL, DMV | Đường dẫn `/var/opt/mssql/...`, dùng `/` |
| Backup/restore, Query Store, IQP | Cấu hình qua `mssql-conf` thay vì SQL Server Configuration Manager |
| Always On AG, TDE, In-Memory OLTP | Cluster dùng **Pacemaker/Corosync**, không phải WSFC |
| Compatibility level, edition | Không có Windows Authentication mặc định (cần join AD/realmd) |
| SQL Agent (bật riêng) | Không có SSAS/SSRS; SSIS có bản Linux hạn chế |
| Collation, Unicode | Không có FILESTREAM, không có Distributed Transaction Coordinator (MSDTC) đầy đủ |

Với người làm DevOps, đây là điểm quan trọng nhất: **kiến thức SQL Server không phải học lại**, chỉ có tầng vận hành thay đổi.

---

## 2. Cài đặt và cấu hình trên Linux

### 2.1 Cài đặt (Ubuntu)

```bash
# Thêm repo Microsoft
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list \
  | sudo tee /etc/apt/sources.list.d/mssql-server.list

sudo apt-get update && sudo apt-get install -y mssql-server

# Cấu hình lần đầu: chọn edition, đặt mật khẩu sa
sudo /opt/mssql/bin/mssql-conf setup

# Công cụ dòng lệnh
sudo apt-get install -y mssql-tools18 unixodbc-dev
echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc
```

### 2.2 `mssql-conf` – nơi cấu hình mọi thứ ngoài T-SQL

```bash
# Xem toàn bộ cấu hình hiện tại
sudo cat /var/opt/mssql/mssql.conf

# Bộ nhớ: giới hạn RAM cho engine (tương đương max server memory nhưng ở tầng process)
sudo /opt/mssql/bin/mssql-conf set memory.memorylimitmb 24576

# Đường dẫn mặc định
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultdatadir      /data/mssql
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultlogdir       /log/mssql
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultbackupdir    /backup/mssql
sudo /opt/mssql/bin/mssql-conf set filelocation.defaultdumpdir      /var/opt/mssql/log

# TLS
sudo /opt/mssql/bin/mssql-conf set network.tlscert       /etc/ssl/certs/mssql.pem
sudo /opt/mssql/bin/mssql-conf set network.tlskey        /etc/ssl/private/mssql.key
sudo /opt/mssql/bin/mssql-conf set network.tlsprotocols  1.2,1.3
sudo /opt/mssql/bin/mssql-conf set network.forceencryption 1

# Bật SQL Agent
sudo /opt/mssql/bin/mssql-conf set sqlagent.enabled true

# Traceflag khi cần
sudo /opt/mssql/bin/mssql-conf traceflag 3226 on     # bỏ log "backup successful" khỏi error log

sudo systemctl restart mssql-server
sudo systemctl status  mssql-server
```

### 2.3 Cứng hóa OS cho SQL Server

Đây là phần mà mặc định Linux không tối ưu cho database và cần điều chỉnh:

```bash
# Transparent Huge Pages: khuyến nghị chuyển sang madvise (tránh always)
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled

# Swappiness thấp: tránh OS đẩy buffer pool ra swap
sudo sysctl -w vm.swappiness=10

# Cho phép SQL Server khóa trang trong bộ nhớ và mở nhiều file
cat <<'EOF' | sudo tee /etc/security/limits.d/99-mssql.conf
mssql soft nofile 1048576
mssql hard nofile 1048576
mssql soft memlock unlimited
mssql hard memlock unlimited
EOF

# Filesystem: XFS hoặc ext4; mount data volume với noatime
# /dev/nvme1n1  /data  xfs  defaults,noatime  0 0

# I/O scheduler cho NVMe: none/noop (không cần merge/sort của kernel)
echo none | sudo tee /sys/block/nvme1n1/queue/scheduler

# CPU governor: performance thay vì powersave
sudo cpupower frequency-set -g performance
```

Bốn thứ trên (THP, swappiness, ulimit, I/O scheduler) là những điều chỉnh có tác động đo được rõ nhất. Đặc biệt swappiness: nếu OS đẩy buffer pool ra swap, hiệu năng sụt hàng chục lần và triệu chứng trong SQL Server chỉ là `PAGEIOLATCH` cao — rất khó đoán ra nguyên nhân thật nếu không kiểm tra tầng OS.

### 2.4 Kết nối tới AD (nếu cần Windows Authentication)

```bash
sudo apt-get install -y realmd sssd sssd-tools adcli krb5-user packagekit
sudo realm join --user=admin CORP.LOCAL

# Tạo keytab cho SQL Server (theo tài liệu Microsoft: dùng adutil hoặc ktpass)
sudo /opt/mssql/bin/mssql-conf set network.kerberoskeytabfile /var/opt/mssql/secrets/mssql.keytab
sudo /opt/mssql/bin/mssql-conf set network.privilegedadaccount mssql
sudo systemctl restart mssql-server
```

```sql
CREATE LOGIN [CORP\svc-sales-app] FROM WINDOWS;
```

---

## 3. Docker

### 3.1 Chạy nhanh cho môi trường dev

```bash
docker run -d --name mssql-dev \
  -e 'ACCEPT_EULA=Y' \
  -e 'MSSQL_SA_PASSWORD=<StrongPassw0rd!>' \
  -e 'MSSQL_PID=Developer' \
  -e 'MSSQL_COLLATION=SQL_Latin1_General_CP1_CI_AS' \
  -p 1433:1433 \
  -v mssql-data:/var/opt/mssql \
  --memory 4g --cpus 2 \
  mcr.microsoft.com/mssql/server:2025-latest
```

Ba điểm dễ sai ở lệnh trên:

| Điểm | Chi tiết |
|---|---|
| Không có volume | Mất toàn bộ database khi container bị xóa |
| Không giới hạn memory | Container chiếm hết RAM host; hoặc bị OOM-kill khi host cần RAM |
| Mật khẩu trong lệnh | Nằm trong shell history và `docker inspect`; production phải dùng secret |

Biến môi trường hay dùng:

| Biến | Ý nghĩa |
|---|---|
| `ACCEPT_EULA` | Bắt buộc `Y` |
| `MSSQL_SA_PASSWORD` | Mật khẩu sa (tên cũ `SA_PASSWORD` đã deprecated) |
| `MSSQL_PID` | `Developer`, `Express`, `Standard`, `Enterprise`, hoặc product key |
| `MSSQL_COLLATION` | Collation lúc khởi tạo — **không đổi được sau đó** |
| `MSSQL_MEMORY_LIMIT_MB` | Giới hạn bộ nhớ engine (đặt thấp hơn limit của container) |
| `MSSQL_AGENT_ENABLED` | Bật SQL Agent |
| `MSSQL_LCID` | Locale |
| `MSSQL_TCP_PORT` | Đổi port |

### 3.2 docker-compose cho môi trường phát triển

```yaml
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2025-latest
    container_name: mssql
    environment:
      ACCEPT_EULA: "Y"
      MSSQL_SA_PASSWORD_FILE: /run/secrets/sa_password
      MSSQL_PID: Developer
      MSSQL_MEMORY_LIMIT_MB: "3072"
      MSSQL_AGENT_ENABLED: "true"
    secrets: [sa_password]
    ports: ["1433:1433"]
    volumes:
      - mssql-data:/var/opt/mssql/data
      - mssql-log:/var/opt/mssql/log
      - mssql-backup:/var/opt/mssql/backup
      - ./init:/init:ro
    deploy:
      resources:
        limits: { memory: 4G, cpus: "2.0" }
    healthcheck:
      test: ["CMD-SHELL",
             "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P \"$$(cat /run/secrets/sa_password)\" -C -Q 'SELECT 1' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 60s

volumes:
  mssql-data:
  mssql-log:
  mssql-backup:

secrets:
  sa_password:
    file: ./secrets/sa_password.txt
```

Tách `data` / `log` / `backup` thành ba volume riêng ngay từ dev là thói quen tốt: nó khớp với cách production bố trí storage và giúp phát hiện sớm các giả định sai về đường dẫn.

`start_period: 60s` trong healthcheck là cần thiết — SQL Server mất khá lâu để khởi động lần đầu (tạo `master`, `msdb`, `tempdb`), và healthcheck quá sớm sẽ làm orchestrator restart container liên tục.

### 3.3 Khởi tạo schema tự động

```bash
#!/usr/bin/env bash
# init/entrypoint-init.sh — chờ engine sẵn sàng rồi chạy script
set -euo pipefail
SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${MSSQL_SA_PASSWORD} -C -b"

for i in $(seq 1 60); do
  if $SQLCMD -Q "SELECT 1" >/dev/null 2>&1; then break; fi
  echo "waiting for sql server ($i)…"; sleep 2
done

for f in /init/*.sql; do
  echo "applying $f"
  $SQLCMD -i "$f"
done
```

Cờ `-C` (trust server certificate) là bắt buộc với `mssql-tools18` vì bản 18 mặc định bật `Encrypt=Mandatory`; container dev dùng certificate tự sinh. Cờ `-b` khiến sqlcmd trả exit code khác 0 khi có lỗi — quan trọng để CI phát hiện script thất bại.

### 3.4 Testcontainers cho integration test Java

```java
@Testcontainers
class OrderRepositoryIT {

    @Container
    static final MSSQLServerContainer<?> MSSQL =
        new MSSQLServerContainer<>("mcr.microsoft.com/mssql/server:2025-latest")
            .acceptLicense()
            .withInitScript("db/schema.sql")
            .withUrlParam("encrypt", "true")
            .withUrlParam("trustServerCertificate", "true");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry r) {
        r.add("spring.datasource.url",      MSSQL::getJdbcUrl);
        r.add("spring.datasource.username", MSSQL::getUsername);
        r.add("spring.datasource.password", MSSQL::getPassword);
    }
}
```

Đây là cách kiểm thử đúng đắn nhất cho ứng dụng dùng SQL Server: test chạy trên **cùng engine như production**, thay vì H2 với chế độ tương thích. Rất nhiều lỗi chỉ xuất hiện trên SQL Server thật (collation, `IDENTITY`, `MERGE`, `ROWVERSION`, kiểu `DATETIME2`) sẽ bị bỏ sót nếu test trên H2. Xem thêm [springboot_testing](../../springboot/springboot_testing.md) và [jdbc_java.md](../integration/jdbc_java.md).

---

## 4. Kubernetes

### 4.1 StatefulSet cơ bản

```yaml
apiVersion: v1
kind: Secret
metadata: { name: mssql-secret }
type: Opaque
stringData:
  MSSQL_SA_PASSWORD: "<StrongPassw0rd!>"
---
apiVersion: v1
kind: Service
metadata: { name: mssql }
spec:
  clusterIP: None            # headless: DNS ổn định cho từng pod
  selector: { app: mssql }
  ports: [{ port: 1433, name: mssql }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: mssql }
spec:
  serviceName: mssql
  replicas: 1
  selector: { matchLabels: { app: mssql } }
  template:
    metadata: { labels: { app: mssql } }
    spec:
      terminationGracePeriodSeconds: 120     # cho engine shutdown sạch
      securityContext:
        fsGroup: 10001
      containers:
        - name: mssql
          image: mcr.microsoft.com/mssql/server:2025-latest
          env:
            - name: ACCEPT_EULA
              value: "Y"
            - name: MSSQL_PID
              value: "Developer"
            - name: MSSQL_SA_PASSWORD
              valueFrom: { secretKeyRef: { name: mssql-secret, key: MSSQL_SA_PASSWORD } }
            - name: MSSQL_MEMORY_LIMIT_MB
              value: "6144"                  # THẤP HƠN memory limit của container
          ports: [{ containerPort: 1433 }]
          resources:
            requests: { memory: "6Gi", cpu: "2" }
            limits:   { memory: "8Gi", cpu: "4" }
          securityContext:
            runAsUser: 10001
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
          volumeMounts:
            - { name: data,   mountPath: /var/opt/mssql/data }
            - { name: log,    mountPath: /var/opt/mssql/log }
            - { name: backup, mountPath: /var/opt/mssql/backup }
          readinessProbe:
            exec:
              command: ["/bin/sh","-c",
                "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P \"$MSSQL_SA_PASSWORD\" -C -Q 'SELECT 1'"]
            initialDelaySeconds: 45
            periodSeconds: 10
            failureThreshold: 6
          livenessProbe:
            tcpSocket: { port: 1433 }
            initialDelaySeconds: 120
            periodSeconds: 30
            failureThreshold: 5
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: fast-nvme
        resources: { requests: { storage: 200Gi } }
    - metadata: { name: log }
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: fast-nvme
        resources: { requests: { storage: 50Gi } }
    - metadata: { name: backup }
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: standard
        resources: { requests: { storage: 500Gi } }
```

### 4.2 Bốn điều dễ sai nhất khi chạy trên K8s

| Sai | Hậu quả | Cách đúng |
|---|---|---|
| `MSSQL_MEMORY_LIMIT_MB` ≈ memory limit của container | Engine dùng hết quota, kubelet OOM-kill pod | Đặt engine limit khoảng 70–80% container limit |
| `livenessProbe` quá gấp | Pod bị restart trong lúc recovery database dài | `initialDelaySeconds` lớn, dùng TCP cho liveness, sqlcmd cho readiness |
| Storage class chậm hoặc network storage cho log | `WRITELOG` cao, throughput ghi sụp | Log trên storage IOPS/latency tốt nhất |
| Dùng `Deployment` thay `StatefulSet` | Danh tính pod và PVC không ổn định | `StatefulSet` + `volumeClaimTemplates` |

Điểm đầu tiên là nguyên nhân phổ biến nhất của "pod SQL Server bị restart lúc tải cao": engine tin nó có 8GB, container chỉ được phép 8GB, và khi engine chạm gần trần thì kernel kill process thay vì engine tự nhường.

### 4.3 HA trong Kubernetes

Ba mức, chọn theo RTO:

| Mức | Cơ chế | RTO | Ghi chú |
|---|---|---|---|
| **Pod tự tái tạo** | StatefulSet + PVC; K8s tạo lại pod trên node khác | 30–120 giây | Đơn giản nhất, hợp phần lớn hệ thống nội bộ |
| **Always On AG với `CLUSTER_TYPE = NONE`** | Nhiều pod, mỗi pod một replica, failover thủ công/script | Giây (nếu tự động hóa) | Có readable secondary; không có cluster manager |
| **Operator hoặc AG + Pacemaker** | Tự động hóa failover | Giây | Phức tạp; đánh giá kỹ mức chín của operator đang dùng |

Với mức đầu tiên, RTO gồm: phát hiện node chết (theo `node-monitor-grace-period`), detach/attach PV, khởi động container, và database recovery. Bật **ADR** ([architecture.md](../fundamentals/architecture.md) mục 7.4) làm phần cuối ổn định hơn nhiều.

```sql
-- AG không cần cluster manager: phù hợp K8s
CREATE AVAILABILITY GROUP [AG_K8S]
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE [SalesDB]
REPLICA ON
  N'mssql-0' WITH (ENDPOINT_URL = N'TCP://mssql-0.mssql:5022',
                   AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                   SEEDING_MODE = AUTOMATIC),
  N'mssql-1' WITH (ENDPOINT_URL = N'TCP://mssql-1.mssql:5022',
                   AVAILABILITY_MODE = SYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                   SEEDING_MODE = AUTOMATIC);
```

Tên DNS `mssql-0.mssql` là lý do headless service ở mục 4.1 quan trọng: endpoint của AG cần địa chỉ ổn định cho từng pod, thứ mà ClusterIP service thông thường không cung cấp.

Chi tiết về AG: [ha_dr.md](../administration/ha_dr.md).

### 4.4 Backup trong Kubernetes

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: mssql-backup-log }
spec:
  schedule: "*/15 * * * *"
  concurrencyPolicy: Forbid
  failedJobsHistoryLimit: 5
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: mcr.microsoft.com/mssql-tools18
              env:
                - name: SA_PW
                  valueFrom: { secretKeyRef: { name: mssql-secret, key: MSSQL_SA_PASSWORD } }
              command: ["/bin/bash","-c"]
              args:
                - |
                  set -euo pipefail
                  TS=$(date -u +%Y%m%d_%H%M%S)
                  /opt/mssql-tools18/bin/sqlcmd -S mssql-0.mssql -U sa -P "$SA_PW" -C -b -Q "
                    BACKUP LOG [SalesDB]
                    TO URL = 's3://minio.default.svc:9000/mssql-backup/SalesDB_${TS}.trn'
                    WITH COMPRESSION, CHECKSUM;"
```

Backup tới object storage (S3-compatible, SQL Server 2022+) là mô hình tự nhiên nhất trong K8s: không cần PV cho backup, và object storage có thể bật versioning/object lock để có immutability chống ransomware. Chi tiết ở [backup_recovery.md](../administration/backup_recovery.md) mục 3.6.

### 4.5 Bảo mật trong cluster

```yaml
# Chỉ cho phép pod của ứng dụng kết nối tới 1433
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: mssql-allow-app }
spec:
  podSelector: { matchLabels: { app: mssql } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: { matchLabels: { role: backend } }
        - podSelector: { matchLabels: { app: mssql } }     # cho AG endpoint giữa các replica
      ports:
        - { protocol: TCP, port: 1433 }
        - { protocol: TCP, port: 5022 }
```

Kèm theo:

- Mật khẩu/secret lấy từ External Secrets Operator hoặc Vault, không hardcode trong manifest.
- TLS certificate quản lý bằng cert-manager, mount vào pod, cấu hình qua `mssql-conf`.
- `runAsNonRoot`, drop toàn bộ capability, `readOnlyRootFilesystem` nếu image cho phép.
- TDE certificate phải có trên **mọi** replica — quản lý như secret, backup ra ngoài cluster.

Xem thêm [security.md](../administration/security.md) và [kubernetes package](../../kubernetes/roadmap.md).

---

## 5. Giám sát trong môi trường container

Trong K8s, cách tự nhiên là exporter + Prometheus + Grafana, khớp với [prometheus_grafana](../../prometheus_grafana/roadmap.md):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: sql-exporter }
spec:
  replicas: 1
  selector: { matchLabels: { app: sql-exporter } }
  template:
    metadata:
      labels: { app: sql-exporter }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9399"
    spec:
      containers:
        - name: exporter
          image: burningalchemist/sql_exporter:latest
          env:
            - name: SQLEXPORTER_TARGET_DSN
              valueFrom: { secretKeyRef: { name: mssql-exporter-dsn, key: dsn } }
          ports: [{ containerPort: 9399 }]
```

Tạo login riêng cho exporter với quyền tối thiểu:

```sql
CREATE LOGIN exporter WITH PASSWORD = '<...>';
GRANT VIEW SERVER STATE      TO exporter;
GRANT VIEW ANY DEFINITION    TO exporter;
GRANT VIEW SERVER PERFORMANCE STATE TO exporter;   -- 2022+ tách quyền chi tiết hơn
```

Metric cần thu khi chạy trong container, ngoài danh sách ở [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md) mục 8:

| Metric container | Vì sao quan trọng riêng |
|---|---|
| `container_memory_working_set_bytes` vs limit | Cảnh báo trước khi bị OOM-kill |
| Pod restart count | Restart âm thầm là dấu hiệu probe/memory sai cấu hình |
| PVC used % | Data/log volume đầy = database dừng |
| PV read/write latency | Storage class có thể chậm hơn nhiều so với kỳ vọng |
| Node pressure (memory/disk) | Pod database dễ bị evict nếu không có QoS Guaranteed |

Về QoS: đặt `requests == limits` cho pod SQL Server để có QoS class **Guaranteed** — nếu không, pod có thể bị evict khi node chịu memory pressure.

---

## 6. Azure Arc-enabled SQL Server

Arc cho phép quản lý instance SQL Server on-premises (kể cả trong K8s) từ Azure: kiểm kê, đánh giá best practice, Microsoft Defender for SQL, backup tập trung, và **Microsoft Entra ID authentication** cho instance on-prem (2022+).

```bash
# Agent Arc đã cài trên máy chủ; sau đó SQL Server extension được triển khai
az connectedmachine extension create \
  --machine-name sql-prod-01 --resource-group rg-data \
  --name WindowsAgent.SqlServer --publisher Microsoft.AzureData \
  --type WindowsAgent.SqlServer
```

Giá trị chính không phải "thêm một dashboard" mà là: một chỗ để kiểm kê **toàn bộ** instance SQL Server trong tổ chức (thường nhiều hơn con số đội DBA nắm được), kèm đánh giá bảo mật và bản vá.

---

## 7. Compare – các cách chạy SQL Server

| | Windows Server | Linux bare-metal/VM | Docker | Kubernetes | Azure SQL MI |
|---|---|---|---|---|---|
| Hiệu năng engine | Chuẩn | Tương đương | Tương đương (nếu storage tốt) | Phụ thuộc storage class | Phụ thuộc tier |
| Windows Authentication | Sẵn có | Cần join AD | Khó | Khó | Entra ID |
| Always On | WSFC | Pacemaker / `CLUSTER_TYPE=NONE` | Không thực tế | AG `CLUSTER_TYPE=NONE` hoặc pod restart | Sẵn có (PaaS) |
| SSIS / SSAS / SSRS | Đầy đủ | Hạn chế / không có | Không | Không | Hạn chế |
| Vá lỗi | Windows Update / CU | Package manager | Đổi image tag | Rolling image | Microsoft lo |
| Phù hợp cho | Hệ enterprise có sẵn AD | Production Linux-first | Dev/test, CI | Nội bộ, microservice, dev/test, một số production | Muốn giảm việc vận hành |

Khuyến nghị thực dụng:

- **Dev/test/CI**: Docker hoặc Testcontainers — không có lý do gì để cài thủ công.
- **Production nội bộ, đội có kinh nghiệm K8s**: K8s StatefulSet là khả thi, nhưng phải làm đúng bốn điểm ở mục 4.2 và có backup/DR nghiêm túc.
- **Production quan trọng nhất, RPO/RTO chặt**: VM/bare-metal với Always On vẫn là mô hình chín nhất, ít bất ngờ nhất.
- **Muốn giảm việc vận hành**: Azure SQL MI hoặc dịch vụ quản lý tương đương.

---

## 8. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Linux thay Windows | Chi phí license OS, quen với hệ Linux hiện có | Mất SSIS/SSAS/SSRS, Windows Auth phải cấu hình thêm | Đội DevOps Linux-first, không cần BI stack |
| Container thay cài đặt | Tái lập được, CI/CD dễ, cùng image mọi môi trường | Thêm một tầng phải hiểu (storage, memory, probe) | Dev/test luôn; production khi đội đủ chín |
| K8s StatefulSet | Tự phục hồi, khai báo hạ tầng bằng code | RTO 30–120 giây, phụ thuộc storage class | Hệ nội bộ, chấp nhận RTO đó |
| AG `CLUSTER_TYPE=NONE` trong K8s | Có replica đọc, RPO 0 | Failover phải tự động hóa | Cần RTO ngắn hơn pod restart |
| `requests == limits` | QoS Guaranteed, không bị evict | Giữ tài nguyên kể cả khi rảnh | Luôn, cho pod database |
| Backup ra object storage | Không cần PV, immutable được | Phụ thuộc mạng và object storage | 2022+, và nên là mặc định trong K8s |
| Azure Arc | Kiểm kê, bảo mật, quản lý tập trung | Phụ thuộc kết nối Azure, chi phí | Nhiều instance rải rác cần kiểm soát |

---

## 9. Checklist triển khai

```text
Linux host
□ memory.memorylimitmb đặt tường minh, chừa RAM cho OS
□ THP = madvise, vm.swappiness thấp
□ ulimit nofile / memlock cho user mssql
□ Data / log / backup trên volume riêng; noatime; log ở storage nhanh nhất
□ I/O scheduler phù hợp (none cho NVMe)
□ TLS certificate cấu hình qua mssql-conf, forceencryption = 1
□ SQL Agent bật nếu cần job

Container
□ Volume riêng cho data / log / backup
□ MSSQL_MEMORY_LIMIT_MB ≈ 70–80% memory limit container
□ Secret không nằm trong image, manifest, hay shell history
□ Healthcheck có start_period / initialDelaySeconds đủ dài
□ Image tag cố định, không dùng :latest trong production
□ Không chạy bằng root, drop capability

Kubernetes
□ StatefulSet + volumeClaimTemplates (không dùng Deployment)
□ Headless service cho DNS pod ổn định
□ requests == limits (QoS Guaranteed)
□ terminationGracePeriodSeconds đủ để shutdown sạch
□ liveness dùng TCP, readiness dùng sqlcmd
□ NetworkPolicy giới hạn 1433/5022
□ CronJob backup log + full, đích là object storage
□ Có kế hoạch DR: backup ở ngoài cluster, đã diễn tập restore
□ ADR bật để recovery sau restart nhanh và ổn định
□ Monitoring: metric SQL Server + metric container + alert PVC/memory
```

---

## 10. Ghi chú – chủ đề tiếp theo

- [data_movement.md](../integration/data_movement.md): nạp/đồng bộ dữ liệu, CDC, change event streaming.
- [jdbc_java.md](../integration/jdbc_java.md): kết nối từ ứng dụng Java trong cùng cluster.
- [ha_dr.md](../administration/ha_dr.md): AG chi tiết, Pacemaker, distributed AG.
- [docker package](../../docker/roadmap.md), [kubernetes package](../../kubernetes/roadmap.md): nền tảng container.
- [prometheus_grafana](../../prometheus_grafana/roadmap.md): dựng dashboard cho metric ở mục 5.

Từ khóa mở rộng: `mssql-conf` traceflag và `coredump`, SQL Server on Linux + `numactl`, huge pages cho buffer pool, `adutil` cho keytab, SQL Server Big Data Cluster (đã ngừng), Azure Arc data services, CSI snapshot cho backup nhất quán.

---

*Cập nhật lần cuối: 2026-07-30*
