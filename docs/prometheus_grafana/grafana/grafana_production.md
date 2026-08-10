---
title: "Grafana Production – HA, IAM, security và operations"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 25
---
# Grafana Production – HA, IAM, security và operations

> Thuật ngữ: [Glossary](../glossary.md).

> Phiên bản mục tiêu: **Grafana OSS 13.1.x**.
>
> Điều kiện đầu vào: đã đọc
> [Grafana Fundamentals](grafana_fundamentals.md) và
> [Grafana Advanced](grafana_advanced.md).
>
> Các ví dụ là baseline để thảo luận và kiểm thử. Không copy nguyên giá trị
> connection pool, timeout, resource limit hoặc topology vào production.

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- giải thích Grafana HA thực sự cần những thành phần nào;
- phân biệt HA của web tier, database, Grafana Alerting và Grafana Live;
- triển khai nhiều Grafana instance mà không phụ thuộc sticky session;
- thiết kế authentication, authorization và break-glass access;
- bảo vệ secret, cookie, plugin, renderer và data source proxy;
- quan sát Grafana bằng metrics, logs, traces và synthetic checks;
- lập kế hoạch backup, restore, upgrade và disaster recovery;
- nhận ra giới hạn giữa Grafana OSS, Enterprise và Cloud.

Production-ready không có nghĩa là “chạy được hai Pod”. Nó có nghĩa là hệ
thống có failure model, owner, SLO, backup đã restore thử và quy trình thay đổi
có thể rollback.

---

## 2. Mental model: Grafana là control plane và query proxy

Grafana không lưu metrics của Prometheus, logs của Loki hoặc traces của Tempo.
Nhưng nó vẫn giữ nhiều state quan trọng:

```text
Browser
   │ HTTPS
   ▼
Load balancer / Ingress
   │
   ├── Grafana A ──┐
   ├── Grafana B ──┼──▶ PostgreSQL/MySQL dùng chung
   └── Grafana C ──┘       users, auth tokens, dashboards,
           │               data sources, alert rules, silences...
           │
           ├──▶ Prometheus / Loki / Tempo / SQL / cloud APIs
           ├──▶ IdP: Keycloak, Entra ID, Okta...
           ├──▶ SMTP / Slack / PagerDuty / webhook
           └──▶ image renderer
```

Grafana có hai vai trò dễ bị đánh giá thấp:

1. **Control plane**: quản lý dashboard, datasource, user, permission và alert.
2. **Query proxy**: nhận query từ người dùng rồi gọi tới backend bằng credential
   đã cấu hình.

Vì vậy một Viewer không chỉ “xem ảnh dashboard”; họ có thể tạo query trực tiếp
tới datasource nếu quyền và edition cho phép.

---

## 3. Xác định failure domain trước khi nói về HA

| Failure | Nếu không chuẩn bị | Biện pháp chính |
|---|---|---|
| Một Grafana process chết | UI/API gián đoạn | Nhiều instance + load balancer |
| Một node/AZ chết | Mất nhiều replica cùng lúc | Anti-affinity/topology spread |
| Database chết | Tất cả instance mất state | PostgreSQL/MySQL HA + backup |
| IdP chết | Người dùng không đăng nhập mới | Session lifetime phù hợp + break glass |
| Alert gossip đứt | Trùng notification/silence lệch | Alerting HA network/Redis + monitoring |
| Datasource chậm | Panel và alert timeout | Timeout, limit, recording rule, capacity |
| Plugin/renderer lỗi | Panel/report/screenshot lỗi | Pin version, isolation, health checks |
| Cấu hình sai | Toàn cluster lỗi giống nhau | Canary, staged rollout, rollback |
| Operator xóa nhầm | State hợp lệ bị mất | As-code, version history, backup/restore |

Nhiều replica chỉ xử lý failure của process/node. Nó không sửa:

- database single point of failure;
- cấu hình sai được rollout tới mọi Pod;
- datasource outage;
- IdP outage;
- credential bị lộ;
- alert notification route bị cấu hình sai.

---

## 4. Grafana HA cơ bản

Grafana self-managed HA dùng kiến trúc **active-active**:

```text
                    ┌── Grafana A
Client ── LB ───────┼── Grafana B
                    └── Grafana C
                          │
                          ▼
                 Shared PostgreSQL/MySQL
```

Các điều kiện bắt buộc:

1. ít nhất hai Grafana instance;
2. cùng phiên bản và cùng cấu hình có ý nghĩa cluster-wide;
3. cùng một PostgreSQL hoặc MySQL database;
4. load balancer loại node không healthy;
5. cùng `root_url`, encryption secret và provisioning contract;
6. database tự nó cũng phải HA.

SQLite phù hợp cho local development, không phù hợp cho production HA.

### Có cần sticky session hoặc Redis session không?

Grafana mặc định dùng auth token strategy và lưu user session trong database
chính. Load balancer có thể chuyển request sang instance khác mà người dùng
không cần đăng nhập lại.

```text
Request 1 → Grafana A ─┐
                       ├── session/auth state trong shared DB
Request 2 → Grafana B ─┘
```

`[remote_cache]` có thể cache authentication token và dữ liệu auth tạm thời
trong database, Redis hoặc Memcached, nhưng **không điều khiển nơi lưu user
session**. User session vẫn nằm trong `[database]`.

Redis có thể xuất hiện trong một Grafana architecture vì mục đích khác:

- Alerting HA khi Memberlist không dùng được;
- Grafana Live HA;
- remote auth cache;
- query caching của Enterprise là một tính năng khác.

Không nên gom tất cả thành khái niệm mơ hồ “Redis session store”.

---

## 5. Shared database

### Baseline PostgreSQL

```ini
[database]
type = postgres
host = postgres-grafana-rw.monitoring.svc:5432
name = grafana
user = grafana
password = $__file{/etc/grafana/secrets/db-password}

ssl_mode = verify-full
ca_cert_path = /etc/grafana/certs/postgres-ca.pem

max_idle_conn = 20
max_open_conn = 100
conn_max_lifetime = 14400

migration_locking = true
log_queries = false
instrument_queries = true
```

Ý nghĩa:

- `verify-full` mã hóa kết nối và xác minh hostname/certificate;
- `max_open_conn` là trần của **mỗi Grafana instance**;
- `conn_max_lifetime` dùng giây, mặc định 14.400 giây;
- `migration_locking=true` giúp serialize database migration;
- `instrument_queries=true` thêm metrics/tracing cho database query nhưng cần
  đánh giá overhead và cardinality.

### Tính connection budget

```text
Grafana connection ceiling
  = replica_count × max_open_conn

Tổng database budget
  >= Grafana ceiling
   + migration/admin jobs
   + monitoring
   + safety headroom
```

Ví dụ ba replica với `max_open_conn=100` có thể mở tối đa 300 connection. Không
được đặt 300 chỉ vì ví dụ trên mạng dùng 300; phải đối chiếu giới hạn của
database, PgBouncer/proxy và workload thực tế.

### Database là phần của availability SLO

Theo dõi ít nhất:

- connection usage và saturation;
- query latency/error;
- deadlock/lock wait;
- storage capacity và IOPS;
- replica lag/failover;
- backup age và restore test age;
- certificate expiration.

Một database endpoint “HA” nhưng failover chưa từng diễn tập vẫn chỉ là giả
định.

---

## 6. Database migration và startup

Grafana chạy schema migration khi khởi động phiên bản mới. Trong cluster:

```text
Pod mới start
  → lấy migration lock
  → migrate schema nếu cần
  → start Grafana

Các Pod khác
  → chờ/đọc schema theo hành vi của phiên bản
```

Nguyên tắc:

- không tắt `migration_locking` chỉ để rollout “nhanh hơn”;
- backup database trước upgrade;
- đọc upgrade guide cho từng version trung gian;
- canary một instance ngoài hoặc với lượng traffic nhỏ;
- xác minh plugin, login, dashboard, alert và database migration;
- sau đó mới rollout phần còn lại;
- không coi downgrade binary là rollback an toàn sau schema migration.

Rollback đáng tin cậy thường là:

```text
restore database backup tương thích
  + restore config/plugin manifest
  + deploy lại image cũ
```

---

## 7. Kubernetes HA reference

Ví dụ rút gọn sau minh họa contract quan trọng, không phải chart hoàn chỉnh:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: grafana
  template:
    metadata:
      labels:
        app.kubernetes.io/name: grafana
    spec:
      terminationGracePeriodSeconds: 60
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      containers:
        - name: grafana
          # Production nên pin patch version và digest đã kiểm thử.
          image: grafana/grafana:13.1.0
          ports:
            - name: http
              containerPort: 3000
            - name: gossip-tcp
              containerPort: 9094
              protocol: TCP
            - name: gossip-udp
              containerPort: 9094
              protocol: UDP
          env:
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: GF_DATABASE_TYPE
              value: postgres
            - name: GF_DATABASE_HOST
              value: postgres-grafana-rw.monitoring.svc:5432
            - name: GF_DATABASE_NAME
              value: grafana
            - name: GF_DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: grafana-database
                  key: username
            - name: GF_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-database
                  key: password
            - name: GF_SERVER_ROOT_URL
              value: https://grafana.example.com
          startupProbe:
            httpGet:
              path: /api/health
              port: http
            failureThreshold: 30
            periodSeconds: 5
          readinessProbe:
            httpGet:
              path: /api/health
              port: http
            periodSeconds: 10
            timeoutSeconds: 2
          livenessProbe:
            tcpSocket:
              port: http
            periodSeconds: 10
            timeoutSeconds: 1
          resources:
            requests:
              cpu: 500m
              memory: 1Gi
            limits:
              memory: 2Gi
          volumeMounts:
            - name: config
              mountPath: /etc/grafana/grafana.ini
              subPath: grafana.ini
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: grafana-config
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
spec:
  selector:
    app.kubernetes.io/name: grafana
  ports:
    - name: http
      port: 3000
      targetPort: http
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: grafana
  namespace: monitoring
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: grafana
```

### Probe semantics

- **startup** cho Grafana thời gian migrate/start trước khi liveness can thiệp;
- **readiness** loại Pod chưa sẵn sàng khỏi Service;
- **liveness** trả lời process còn nghe hay đã kẹt.

Không nên để liveness phụ thuộc sâu vào shared database. Khi database outage,
restart đồng thời mọi Grafana Pod thường làm sự cố tệ hơn. Probe phải được
kiểm tra với failure injection, không chỉ kiểm tra ở happy path.

### Deployment còn thiếu gì?

Manifest minh họa chưa bao gồm:

- Ingress/Gateway và TLS certificate;
- NetworkPolicy;
- secret/config delivery;
- alerting headless Service;
- ServiceMonitor/PodMonitor;
- autoscaling policy;
- renderer;
- securityContext, seccomp và read-only filesystem;
- database CA/client certificate;
- topology phù hợp cluster thực tế.

---

## 8. Alerting HA là một cluster riêng về mặt logic

Shared database giúp nhiều Grafana instance nhìn thấy rule/config. Nó không tự
động ngăn duplicate notification.

Mặc định trong Grafana Alerting HA:

1. mỗi Grafana instance evaluate toàn bộ Grafana-managed rules;
2. mỗi instance có embedded Alertmanager;
3. các Alertmanager gossip notification state và silence;
4. chúng cố gắng deduplicate notification theo best effort.

```text
Grafana A: scheduler + Alertmanager A ─┐
Grafana B: scheduler + Alertmanager B ─┼── gossip TCP/UDP 9094
Grafana C: scheduler + Alertmanager C ─┘
```

Thiết kế ưu tiên availability hơn consistency. Khi network partition, duplicate
hoặc notification lệch thứ tự có thể xảy ra; duplicate được xem là tốt hơn bỏ
sót notification.

### Memberlist trên Kubernetes

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana-alerting
  namespace: monitoring
spec:
  clusterIP: None
  selector:
    app.kubernetes.io/name: grafana
  ports:
    - name: gossip-tcp
      port: 9094
      targetPort: gossip-tcp
      protocol: TCP
    - name: gossip-udp
      port: 9094
      targetPort: gossip-udp
      protocol: UDP
```

```ini
[unified_alerting]
enabled = true
ha_listen_address = ${POD_IP}:9094
ha_advertise_address = ${POD_IP}:9094
ha_peers = grafana-alerting.monitoring.svc.cluster.local:9094
ha_peer_timeout = 15s
ha_reconnect_timeout = 2m
```

NetworkPolicy phải cho các Grafana Pod giao tiếp với nhau bằng cả TCP và UDP
9094.

### Khi nào dùng Redis?

Memberlist là lựa chọn được ưu tiên. Dùng Alerting HA qua Redis nếu hạ tầng
không cho phép direct TCP/UDP giữa các Grafana instance.

```ini
[unified_alerting]
ha_redis_address = redis-alerting.monitoring.svc:6379
ha_redis_username = grafana
ha_redis_password = $__file{/etc/grafana/secrets/alerting-redis-password}
ha_redis_tls_enabled = true
ha_redis_tls_ca_path = /etc/grafana/certs/redis-ca.pem
```

Không cấu hình đồng thời một cách tùy tiện cả Memberlist và Redis. Chọn một HA
backend, ghi rõ owner và failure model của nó.

### Evaluation load

Ba Grafana replica mặc định có thể tạo xấp xỉ ba lần query evaluation tới
datasource:

```text
datasource alert load
  ≈ rule query load × Grafana evaluator count
```

`ha_single_node_evaluation=true` giảm về một evaluator nhưng ở Grafana 13.1
vẫn là **public preview**. Nó đổi trade-off:

| Default HA | Single-node evaluation |
|---|---|
| Mọi node evaluate | Một primary evaluate |
| Query load nhân N | Query load gần 1× |
| Không có gap do fail evaluator | Có gap ngắn khi bầu primary mới |

Không bật preview feature trong production nếu chưa có acceptance test và kế
hoạch quay lại.

---

## 9. Grafana Live HA

Grafana Live dùng WebSocket và mặc định giữ subscription/pub-sub trong memory
của từng process. Khi có nhiều Grafana instance:

- notification realtime có thể chỉ tới client cùng node;
- stream có thể không tới subscriber ở node khác;
- nhiều node có thể mở stream riêng tới backend.

Grafana có Live HA engine dùng Redis:

```ini
[live]
ha_engine = redis
ha_engine_address = redis-live.monitoring.svc:6379
ha_engine_password = $__file{/etc/grafana/secrets/live-redis-password}
```

Ở baseline hiện tại, Live HA engine vẫn được đánh dấu experimental và có các
giới hạn riêng. Nếu không dùng Grafana Live/streaming, không thêm Redis chỉ vì
“kiến trúc HA thường có Redis”.

---

## 10. Reverse proxy, TLS và `root_url`

`root_url` phải là URL người dùng thật sự truy cập:

```ini
[server]
domain = grafana.example.com
root_url = https://grafana.example.com/
enforce_domain = true
enable_gzip = true
```

Nó ảnh hưởng tới:

- OAuth/OIDC callback URL;
- link trong alert notification;
- redirect;
- asset URL;
- cookie và sub-path behavior.

Nếu phục vụ tại `/grafana/`:

```ini
[server]
root_url = https://observability.example.com/grafana/
serve_from_sub_path = true
```

TLS có thể terminate ở load balancer/Ingress hoặc tại Grafana. Dù chọn cách
nào, traffic từ client phải dùng HTTPS và đường nội bộ cần được đánh giá theo
threat model.

Chỉ tin `X-Forwarded-*` từ reverse proxy đáng tin cậy. Không expose trực tiếp
Grafana backend ra Internet song song với proxy.

---

## 11. Authentication strategy

Ưu tiên centralized identity:

```text
Employee → IdP → Grafana
             │
             ├── authentication: ai đang đăng nhập?
             └── claims/groups: nên có role nào?
```

Production checklist:

- OIDC/OAuth hoặc SAML/LDAP theo edition và IdP;
- callback URL chính xác;
- user identifier ổn định;
- giới hạn domain/group được phép đăng nhập;
- role mapping fail closed;
- refresh token/PKCE khi provider hỗ trợ;
- vô hiệu self-registration không chủ đích;
- có tài khoản break-glass được kiểm soát;
- test deprovisioning và group removal.

### Generic OAuth/OIDC baseline

```ini
[users]
allow_sign_up = false
auto_assign_org_role = Viewer

[auth]
disable_login_form = true

[auth.generic_oauth]
enabled = true
name = Company SSO
allow_sign_up = true
auto_login = false

client_id = grafana-production
client_secret = $__file{/etc/grafana/secrets/oauth-client-secret}

scopes = openid profile email groups offline_access
auth_url = https://sso.example.com/realms/production/protocol/openid-connect/auth
token_url = https://sso.example.com/realms/production/protocol/openid-connect/token
api_url = https://sso.example.com/realms/production/protocol/openid-connect/userinfo

use_pkce = true
use_refresh_token = true
login_attribute_path = sub
groups_attribute_path = groups
allowed_groups = /grafana/users /grafana/editors /grafana/admins

role_attribute_path = contains(groups[*], '/grafana/admins') && 'Admin' || contains(groups[*], '/grafana/editors') && 'Editor' || 'Viewer'
role_attribute_strict = true
allow_assign_grafana_admin = false
```

Hai `allow_sign_up` khác nhau:

- `[users].allow_sign_up=false`: không cho signup qua form;
- `[auth.generic_oauth].allow_sign_up=true`: cho Grafana tạo local user sau khi
  IdP xác thực và vượt qua allow-list.

`login_attribute_path=sub` dùng subject ổn định làm login, nhưng email vẫn cần
được IdP trả về cho signup/login.

### Không cấp Grafana server admin từ IdP mặc định

`Admin` trong biểu thức trên là **organization Admin**, không phải Grafana
server administrator.

Chỉ map `GrafanaAdmin` khi thật sự cần và khi:

```ini
allow_assign_grafana_admin = true
```

Server admin có phạm vi toàn instance. Tách nhóm, approval và audit cho quyền
này.

### Break-glass

Nếu tắt login form hoàn toàn, IdP outage có thể khóa cả operator. Thiết kế một
đường break-glass:

- account local riêng, credential trong secret manager;
- chỉ mở khi incident, có approval;
- network-restricted;
- rotation sau mỗi lần dùng;
- audit và diễn tập định kỳ.

Không để `admin/admin` hoặc admin password trong runbook/chat.

---

## 12. LDAP

LDAP OSS hỗ trợ login và map LDAP group sang organization role:

```ini
[auth.ldap]
enabled = true
config_file = /etc/grafana/ldap.toml
allow_sign_up = true
```

```toml
[[servers]]
host = "ldap.example.com"
port = 636
use_ssl = true
start_tls = false
ssl_skip_verify = false
root_ca_cert = "/etc/grafana/certs/ldap-ca.pem"

bind_dn = "cn=grafana,ou=service-accounts,dc=example,dc=com"
bind_password = "${LDAP_BIND_PASSWORD}"

search_filter = "(uid=%s)"
search_base_dns = ["ou=people,dc=example,dc=com"]

[servers.attributes]
name = "givenName"
surname = "sn"
username = "uid"
member_of = "memberOf"
email = "mail"

[[servers.group_mappings]]
group_dn = "cn=grafana-admins,ou=groups,dc=example,dc=com"
org_role = "Admin"

[[servers.group_mappings]]
group_dn = "cn=grafana-editors,ou=groups,dc=example,dc=com"
org_role = "Editor"

[[servers.group_mappings]]
group_dn = "*"
org_role = "Viewer"
```

Thứ tự mapping quan trọng: **mapping đầu tiên match sẽ được dùng**. Nhóm cụ thể
phải đứng trước wildcard.

Enhanced LDAP và Team Sync có capability khác nhau theo Enterprise/Cloud. Luôn
đối chiếu edition trước khi thiết kế lifecycle tự động.

---

## 13. Authorization model

Ba tầng quyền thường bị nhầm:

```text
Grafana server administrator
  └── quản lý toàn instance, users, organizations, settings

Organization role
  ├── Admin
  ├── Editor
  └── Viewer

Folder/dashboard permission
  ├── Admin
  ├── Edit
  └── View
```

Server Admin khác Organization Admin.

### Folder là permission boundary chính

Trong Grafana 13.1, folder permission áp dụng cho các resource bên trong như:

- dashboards;
- alert rules;
- silences;
- annotations;
- library panels.

Permission kế thừa từ parent xuống child. Không thể cấp quyền thấp hơn ở child
để “gỡ” quyền cao đã kế thừa từ parent.

Thiết kế khuyến nghị:

```text
Production/
├── Checkout/      owner: team-checkout
├── Payments/      owner: team-payments
└── Platform/      owner: team-platform
```

Cấp quyền cho team, không cấp lẻ từng user nếu có thể.

### Hạn chế quan trọng của Grafana OSS

Trong OSS, Viewer có thể query datasource của organization. Folder permission
không tự động biến thành datasource permission.

```text
Không thấy dashboard Payments
        ≠
Không thể query datasource chứa dữ liệu Payments
```

Data source permissions và fine-grained RBAC là capability của
Grafana Enterprise/Cloud.

Nếu cần tenant isolation mạnh:

- tách datasource/credential;
- enforce tenant ở query backend;
- dùng Enterprise data source permissions nếu phù hợp;
- hoặc tách Grafana instance.

Không coi organization/folder là security boundary duy nhất cho dữ liệu nhạy
cảm.

---

## 14. Organizations, teams và service accounts

### Organization

Organization tách users, dashboards, datasources và một số resource theo phạm
vi logic. Một user có thể thuộc nhiều organization với role khác nhau.

Multi-org hữu ích cho quản trị, nhưng nhiều instance riêng thường rõ hơn khi:

- tenant có yêu cầu compliance khác nhau;
- cần release cadence/plugin khác nhau;
- cần encryption key, IdP hoặc network boundary riêng;
- blast radius phải tách biệt.

### Team

Team là đơn vị cấp permission và ownership trong một organization:

```text
IdP group → Grafana team → folder permission
```

Team Sync tự động với external group là tính năng Enterprise/Cloud. Với OSS,
cần xác định workflow quản lý membership khác và kiểm tra deprovisioning.

### Service account

Automation dùng service account token, không dùng admin basic auth:

```bash
curl --fail-with-body \
  --header "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_URL}/apis/dashboard.grafana.app/v1/namespaces/default/dashboards"
```

Mỗi pipeline/integration nên có:

- service account riêng;
- scope/quyền tối thiểu;
- token có expiry nếu workflow cho phép;
- owner và rotation policy;
- không log token;
- revoke khi pipeline bị loại bỏ.

Grafana 13 đang chuyển dần từ legacy `/api` sang `/apis`. Không tự đổi endpoint
chỉ bằng tìm-thay thế; kiểm tra API migration guide và schema từng resource.

---

## 15. Secret management và encryption key

Grafana hỗ trợ variable provider:

```ini
# Environment
password = $__env{GRAFANA_DB_PASSWORD}

# File; whitespace đầu/cuối được trim
password = $__file{/etc/grafana/secrets/db-password}

# Vault provider: chỉ Grafana Enterprise
password = $__vault{kv:secret/grafana/database:password}
```

Trong Kubernetes, file-mounted secret thường tốt hơn nhúng secret vào
ConfigMap hoặc manifest:

```yaml
volumeMounts:
  - name: grafana-secrets
    mountPath: /etc/grafana/secrets
    readOnly: true
volumes:
  - name: grafana-secrets
    secret:
      secretName: grafana-runtime-secrets
```

### `secret_key`

Grafana database chứa encrypted datasource credentials, alert contact secrets
và dữ liệu nhạy cảm khác. Mọi HA node phải dùng cùng encryption secret.

```ini
[security]
secret_key = $__file{/etc/grafana/secrets/secret-key}
```

Yêu cầu vận hành:

- tạo key bằng CSPRNG;
- không commit vào Git;
- backup key tách biệt nhưng khôi phục được;
- kiểm soát quyền đọc;
- rotation theo quy trình database encryption chính thức;
- không đổi key tùy tiện trong một rolling deployment.

Backup database mà mất encryption key có thể không khôi phục được các secret
đã mã hóa.

---

## 16. Security hardening baseline

```ini
[auth.anonymous]
enabled = false
hide_version = true

[users]
allow_sign_up = false
allow_org_create = false

[security]
cookie_secure = true
cookie_samesite = lax
strict_transport_security = true
strict_transport_security_max_age_seconds = 86400
strict_transport_security_subdomains = true
x_content_type_options = true
content_security_policy = true
allow_embedding = false

[server]
enforce_domain = true

[snapshots]
external_enabled = false

[panels]
disable_sanitize_html = false

[plugins]
plugin_admin_enabled = false
allow_loading_unsigned_plugins =
```

Lưu ý:

- OAuth/SAML cần `cookie_samesite=lax`; `strict` có thể làm callback login lỗi;
- chỉ bật HSTS khi HTTPS được đảm bảo tại Grafana hoặc upstream;
- CSP có thể ảnh hưởng plugin/custom content, nên test ở staging;
- `allow_embedding=false` giúp giảm rủi ro clickjacking nhưng có thể xung đột
  use case embed;
- không bật `disable_sanitize_html=true`;
- không allow unsigned plugin trong production nếu không có review ngoại lệ.

Security header không thay thế:

- patching;
- authentication/authorization;
- egress firewall;
- secret management;
- audit;
- backup/restore.

---

## 17. Data source proxy và SSRF/egress

Grafana server có thể gửi request tới datasource thay người dùng. Nếu URL đích
không được kiểm soát, tính năng này có thể thành đường truy cập service nội bộ.

Threat flow:

```text
User có quyền cấu hình/query
  → Grafana data proxy
  → metadata endpoint / internal admin API / private service
```

Biện pháp:

- chỉ cho Grafana egress tới datasource, IdP, notification endpoint cần thiết;
- chặn cloud metadata IP và control-plane endpoint;
- dùng `data_source_proxy_whitelist` khi phù hợp;
- giới hạn ai được tạo/sửa datasource;
- không truyền user header nếu không có thiết kế tin cậy;
- đặt timeout, response limit và row limit;
- theo dõi destination, error và latency của data proxy.

Ví dụ:

```ini
[security]
data_source_proxy_whitelist = prometheus.monitoring.svc:9090 loki.monitoring.svc:3100

[dataproxy]
timeout = 30
max_conns_per_host = 100
max_idle_connections = 100
idle_conn_timeout_seconds = 90
response_limit = 104857600
row_limit = 100000
send_user_header = false
```

Các limit phải dựa trên dashboard/query thực tế. Đặt quá thấp gây lỗi hợp lệ;
đặt vô hạn làm tăng blast radius.

---

## 18. Plugin supply chain

Plugin chạy trong trust boundary của Grafana frontend/backend. Production cần:

1. allow-list plugin ID;
2. pin version trong image/build manifest;
3. chỉ dùng plugin có signature hợp lệ;
4. scan image/SBOM/CVE;
5. test tương thích trước Grafana upgrade;
6. không cho cài plugin tùy ý qua UI;
7. có owner và kế hoạch loại bỏ plugin không còn duy trì.

```ini
[plugins]
plugin_admin_enabled = false
allow_loading_unsigned_plugins =
enable_alpha = false
```

Không dùng tag `latest` cho Grafana hoặc plugin. “Rollback image” chỉ đáng tin
khi image chứa đúng plugin versions đã kiểm thử.

Grafana 13 chuyển frontend sang React 19. Plugin cũ phải được kiểm tra tương
thích trước upgrade.

---

## 19. Image renderer

Image rendering dùng headless browser, tiêu thụ memory đáng kể và có attack
surface riêng. Với production:

- chạy renderer thành service/container riêng;
- giới hạn concurrency và resource;
- không expose renderer công khai;
- đặt token giống nhau ở Grafana và renderer;
- theo dõi render latency/error/queue;
- test screenshot trong alert/report sau upgrade.

Grafana 13 bật JWT renderer authentication mặc định. `renderer_token` không
được để trống hoặc giữ giá trị mặc định:

```ini
[rendering]
server_url = http://grafana-image-renderer:8081/render
callback_url = https://grafana.example.com/
renderer_token = $__file{/etc/grafana/secrets/renderer-token}
```

Token phía renderer phải khớp. Không vô hiệu cơ chế mới chỉ để “sửa nhanh” mà
không hiểu rủi ro.

---

## 20. Meta-monitoring Grafana

Grafana expose internal metrics tại `/metrics` khi `[metrics].enabled=true`:

```ini
[metrics]
enabled = true
disable_total_stats = false
basic_auth_username = prometheus
basic_auth_password = $__file{/etc/grafana/secrets/metrics-password}
```

Credential scrape phải là credential riêng, không phải Grafana admin.

```yaml
- job_name: grafana
  scheme: https
  metrics_path: /metrics
  basic_auth:
    username: prometheus
    password_file: /etc/prometheus/secrets/grafana-metrics-password
  static_configs:
    - targets:
        - grafana-a.internal:3000
        - grafana-b.internal:3000
```

Scrape từng instance thay vì chỉ load balancer để thấy node nào lỗi.

### Bốn nhóm signal

**Availability**

```promql
up{job="grafana"}
```

**HTTP traffic/error/latency**

```promql
sum(rate(grafana_http_request_duration_seconds_count[5m]))
```

```promql
sum(rate(grafana_http_request_duration_seconds_count{status_code=~"5.."}[5m]))
/
clamp_min(
  sum(rate(grafana_http_request_duration_seconds_count[5m])),
  1
)
```

Tên label/metric có thể đổi theo version. Luôn kiểm tra `/metrics` của đúng
build trước khi copy PromQL.

**Runtime**

```promql
process_resident_memory_bytes{job="grafana"}
```

```promql
rate(process_cpu_seconds_total{job="grafana"}[5m])
```

```promql
go_goroutines{job="grafana"}
```

**Alerting HA**

```promql
grafana_alertmanager_cluster_members
```

```promql
grafana_alertmanager_peer_position
```

```promql
rate(grafana_alertmanager_cluster_pings_failures_total[5m])
```

Từ Grafana 12.4, Alertmanager HA metrics có prefix `grafana_`. Dashboard cũ
không prefix sẽ âm thầm không còn data sau upgrade.

---

## 21. Logs, traces và synthetic checks

### Logs

Log cần có:

- timestamp;
- level;
- logger/component;
- instance/pod;
- request ID hoặc trace ID;
- status/error class;
- deployment version.

Không bật query/data-proxy verbose logging thường trực nếu nó có thể ghi URL,
query hoặc dữ liệu nhạy cảm.

### Traces

Grafana có thể phát Jaeger hoặc OTLP traces cho HTTP API và propagate W3C Trace
Context tới datasource tương thích. Trace giúp phân biệt:

```text
Browser chậm
  → Grafana handler chậm?
  → data proxy chậm?
  → datasource chậm?
  → database Grafana chậm?
```

Sampling phải đủ để debug nhưng không tạo chi phí/cardinality mất kiểm soát.

### Synthetic checks

`up=1` chỉ nói Prometheus scrape được `/metrics`. Thêm kiểm tra từ góc nhìn
người dùng:

- DNS/TLS;
- trang login;
- SSO redirect/callback;
- load một dashboard canary;
- query datasource canary;
- tạo alert synthetic tới contact point test.

Không dùng synthetic login quá thường xuyên đến mức gây lock account hoặc
noise audit.

---

## 22. SLO cho Grafana

Ví dụ service level indicators:

| User journey | SLI |
|---|---|
| Mở Grafana | tỷ lệ HTTP request thành công |
| Load dashboard chuẩn | tỷ lệ hoàn tất dưới ngưỡng |
| Query Explore | success rate/latency theo datasource |
| Evaluate alert | evaluation success và freshness |
| Gửi notification | delivery success/latency |
| Login SSO | login success rate |

Không gộp mọi thứ thành một SLO “Grafana up”:

```text
UI healthy + Prometheus down
  → Grafana up về process
  → dashboard vẫn không phục vụ mục đích người dùng
```

SLO nên phản ánh ownership:

- Platform team sở hữu Grafana web tier/database;
- Identity team sở hữu IdP;
- Observability/data team sở hữu datasource;
- Service team sở hữu query/dashboard/rule của họ.

---

## 23. Capacity và performance

### Thành phần tạo tải

- browser dashboard refresh;
- Explore ad-hoc query;
- Grafana-managed alert evaluation;
- provisioning/Git Sync/API automation;
- image rendering;
- reporting;
- database reads/writes;
- plugin backend;
- Live/WebSocket.

### Dashboard fan-out

```text
concurrent users
× panels per dashboard
× queries per panel
× refresh frequency
= approximate query pressure
```

Variable, repeated panels và auto-refresh 5 giây có thể khuếch đại tải rất
nhanh.

Giảm tải bằng:

- recording rules;
- query caching nếu edition hỗ trợ;
- refresh interval hợp lý;
- giới hạn time range;
- giảm panel/query trùng;
- datasource-specific limits;
- alert rules được thiết kế có ownership;
- tách renderer.

### Scale dọc hay ngang?

| Tình huống | Hướng xử lý |
|---|---|
| CPU/memory một process chạm trần | scale up hoặc thêm replica |
| Cần chịu lỗi node/AZ | scale out |
| Database saturated | tối ưu/scale database, không chỉ thêm Grafana |
| Alert query load nhân replica | đánh giá evaluator model/rules |
| Renderer ăn memory | tách renderer fleet |
| Datasource saturated | recording/cache/query governance |

Thêm Grafana replica có thể làm alert query load và database connection tăng.
Scale-out không phải lúc nào cũng giảm tải hệ thống.

---

## 24. Backup contract

Backup production phải bao phủ:

| Thành phần | Cách bảo vệ |
|---|---|
| PostgreSQL/MySQL | native snapshot/dump + PITR nếu cần |
| `grafana.ini`/env contract | Git/config management |
| provisioning files | Git |
| dashboards/alerts as code | Git |
| plugins | immutable image/plugin lock manifest |
| encryption `secret_key` | secret manager + protected backup |
| OAuth/SMTP/DB credentials | secret manager |
| custom cert/CA | PKI/secret store |

Database backup cần transaction consistency. Copy file database đang chạy
không phải cách backup PostgreSQL/MySQL.

### RPO và RTO

- **RPO**: chấp nhận mất bao nhiêu phút thay đổi?
- **RTO**: phải khôi phục dịch vụ trong bao lâu?

Backup schedule phải xuất phát từ hai mục tiêu này, không phải “nightly vì mọi
người vẫn làm vậy”.

### Restore test

```text
Backup thành công
  ≠
Restore thành công
```

Diễn tập:

1. tạo environment cô lập;
2. restore database;
3. restore đúng encryption key/config/plugin image;
4. start đúng Grafana version;
5. test login, datasource secret, dashboard, alert và notification;
6. đo thời gian;
7. ghi lại gap và cập nhật runbook.

Không gửi notification thật từ DR test environment.

---

## 25. Upgrade Grafana 13 an toàn

Workflow:

```text
release notes + upgrade guide
  → backup + restore rehearsal
  → plugin compatibility test
  → staging
  → canary
  → rolling deployment
  → smoke test + observation window
  → complete rollout
```

### Grafana 13 cần chú ý

- legacy `/api` bắt đầu deprecated để chuyển sang `/apis`;
- datasource APIs dựa trên numeric ID bị vô hiệu mặc định, dùng UID;
- frontend chuyển sang React 19, cần update/test plugin;
- image renderer dùng JWT auth mặc định và cần token;
- folders/dashboards được migrate sang unified storage;
- downgrade sau migration có thể đọc legacy tables cũ và làm mất tính nhất
  quán; rollback phải restore database backup;
- Grafana 13.0.0 từng có lỗi Git Sync migration và đã bị gỡ khỏi distribution;
  không dùng nó làm bước trung gian.

Luôn chọn patch release được tổ chức phê duyệt sau khi kiểm tra release
notes/CVE. Không tự động kéo `latest`.

### Smoke test sau upgrade

- `/api/health` và `/metrics`;
- SSO login/logout/role mapping;
- dashboard canary;
- datasource query;
- save/read dashboard;
- provisioning/Git Sync;
- Grafana-managed alert evaluation;
- contact point test;
- Alerting HA membership;
- renderer screenshot;
- plugin critical;
- database error/latency;
- browser console và API error rate.

---

## 26. Rollout và rollback

### Rolling rollout

1. xác nhận backup/restore point;
2. drain một node khỏi load balancer;
3. deploy canary;
4. chờ migration/startup;
5. chạy smoke test;
6. quan sát ít nhất một alert evaluation cycle;
7. rollout từng batch;
8. giữ capacity đáp ứng SLO;
9. xác nhận cluster membership;
10. đóng change khi observation window kết thúc.

### Cấu hình phải đồng nhất

Trong HA, các node không được lệch:

- Grafana version;
- plugin version;
- `root_url`;
- database;
- `secret_key`;
- authentication mapping;
- provisioning;
- alerting HA label/peers;
- feature toggles.

Tạm thời chạy mixed version khi rolling update không đồng nghĩa mixed version
là trạng thái vận hành lâu dài được hỗ trợ.

### Rollback trigger

Định nghĩa trước:

- 5xx vượt ngưỡng;
- login failure tăng;
- database migration/error;
- dashboard canary lỗi;
- alert evaluation/delivery lỗi;
- plugin critical không load;
- memory leak/restart loop.

Nếu không có trigger và người quyết định rollback, “có rollback plan” chỉ là
một câu nói.

---

## 27. Disaster recovery

Runbook cần trả lời:

1. Ai tuyên bố DR?
2. Backup nào được chọn và vì sao?
3. Grafana image/plugin manifest tương ứng ở đâu?
4. Encryption key/certificate/credentials lấy từ đâu?
5. DNS/load balancer chuyển thế nào?
6. Làm sao ngăn alert notification trùng?
7. Làm sao cô lập environment restore?
8. Khi nào mở traffic?
9. Làm sao reconcile thay đổi trong thời gian outage?
10. Ai xác nhận RPO/RTO?

### Warm standby hay rebuild?

| Phương án | Ưu điểm | Nhược điểm |
|---|---|---|
| Rebuild từ IaC + restore DB | ít drift, chi phí thấp | RTO dài hơn |
| Warm standby | failover nhanh | chi phí và drift cao hơn |
| Grafana Cloud | giảm self-hosted ops | data/cost/compliance/vendor trade-off |

Không chạy hai site cùng evaluate/send cùng một alert set nếu chưa thiết kế
deduplication và ownership rõ.

---

## 28. OSS, Enterprise và Cloud

| Capability | OSS | Enterprise | Cloud |
|---|---|---|---|
| HA web tier self-managed | Có | Có | Managed |
| Folder/dashboard permissions | Có | Có | Có |
| Generic OAuth/LDAP | Có | Có | Theo plan/provider |
| Fine-grained RBAC | Không | Có | Có theo plan |
| Data source permissions | Không | Có | Có theo plan |
| Team Sync | Không | Có | Có theo plan |
| Audit logging nâng cao | Không | Có | Có theo plan |
| Database/upgrade operations | Tự quản | Tự quản | Managed |

Pricing, quota và package Cloud/Enterprise thay đổi theo thời gian. Không copy
bảng giá hoặc SLA cũ vào architecture decision record; kiểm tra tài liệu/hợp
đồng hiện tại.

### Chọn mô hình

**OSS self-managed** khi:

- đội có năng lực database/Kubernetes/security;
- cần kiểm soát hạ tầng;
- folder-level access đáp ứng yêu cầu;
- chấp nhận tự vận hành.

**Enterprise self-managed** khi:

- cần RBAC/data source permissions/Team Sync/audit;
- vẫn cần giữ data/control plane trong hạ tầng riêng;
- có ngân sách license và operations.

**Cloud** khi:

- muốn giảm gánh nặng HA/upgrade/database;
- data residency/network/cost phù hợp;
- capability theo plan đáp ứng yêu cầu.

---

## 29. Grafana OnCall OSS sau 24/03/2026

Grafana OnCall OSS vào maintenance mode ngày 11/03/2025 và được archive ngày
24/03/2026; Cloud Connection cũng bị vô hiệu từ ngày đó.

Vì vậy không nên bắt đầu deployment production mới dựa trên OnCall OSS như một
thành phần đang được duy trì.

Nếu đang dùng:

- inventory integration, schedule, escalation và contact data;
- xác định feature nào phụ thuộc Cloud Connection;
- chọn đích migration như Grafana Cloud IRM hoặc incident platform khác;
- chạy song song và test delivery;
- lưu export/backup cần thiết;
- đóng đường notification cũ để tránh duplicate;
- cập nhật runbook và ownership.

Alert routing trong Grafana Alerting không thay thế toàn bộ on-call scheduling,
escalation, mobile push và incident workflow.

---

## 30. Anti-patterns

### “Có ba Pod nên đã HA”

Sai nếu cả ba dùng SQLite/PVC riêng hoặc database single-node.

### Redis được dùng làm “session provider”

Sai mental model hiện tại. User session nằm trong main database;
`[remote_cache]` không đổi điều đó.

### Alerting chỉ dùng shared database

Chưa đủ. Embedded Alertmanager cần Memberlist hoặc Redis HA để gossip
notification state/silence và giảm duplicate theo best effort.

### Liveness phụ thuộc toàn bộ downstream

Database outage làm mọi Pod restart loop, tăng blast radius.

### SSO role mapping mặc định Admin

Một claim thiếu/sai có thể cấp quyền quá mức. Default Viewer và strict mapping
khi use case yêu cầu fail closed.

### Folder permission được coi là datasource isolation

Viewer OSS vẫn có thể query datasource trong organization.

### API automation dùng `admin:password`

Khó scope, rotate, audit và dễ lộ qua shell history/log. Dùng service account.

### Secret nằm trong ConfigMap/Git

Base64 của Kubernetes Secret cũng không phải encryption strategy nếu không bảo
vệ etcd/RBAC.

### Plugin cài qua UI trên một node

HA nodes drift và rollout không tái lập được. Build immutable image.

### Backup chưa từng restore

Không biết encryption key, plugin hoặc schema có tương thích cho tới lúc sự cố.

### Upgrade bằng tag `latest`

Không biết binary/plugin/schema nào đã chạy và không rollback tái lập được.

---

## 31. Bài lab production readiness

### Phần A – HA

1. Chạy hai Grafana instance dùng cùng PostgreSQL.
2. Đặt reverse proxy phía trước.
3. Đăng nhập, tạo dashboard rồi chuyển request giữa hai instance.
4. Dừng một instance.
5. Xác nhận session và dashboard vẫn hoạt động.

### Phần B – Alerting HA

1. Cấu hình Memberlist TCP/UDP 9094.
2. Tạo Grafana-managed alert và contact point test.
3. Kiểm tra `grafana_alertmanager_cluster_members`.
4. Dừng một peer trong lúc alert firing.
5. Ghi nhận notification, state và thời gian recovery.
6. Network-partition một peer trong lab và quan sát duplicate behavior.

### Phần C – IAM/security

1. Tích hợp một OIDC test realm.
2. Gate login bằng allowed group.
3. Map Viewer/Editor/Admin.
4. Xóa user khỏi group và kiểm tra deprovisioning.
5. Kiểm tra cookie, HSTS, CSP và anonymous access.
6. Thử egress tới destination không allow-list và xác nhận bị chặn.

### Phần D – Backup/restore

1. Tạo dashboard, datasource secret và alert rule.
2. Backup database/config/plugin manifest/encryption key.
3. Restore sang environment cô lập.
4. Không cho environment này gửi notification thật.
5. Test login, datasource, dashboard và alert.
6. Ghi RPO/RTO thực đo.

### Acceptance criteria

- mất một Grafana instance không làm gián đoạn user flow vượt SLO;
- session không cần sticky load balancing;
- cluster alerting có đúng số member;
- secret không xuất hiện trong Git/log;
- Viewer không có quyền sửa resource;
- restore đọc được datasource credential đã mã hóa;
- upgrade/rollback có trigger và owner;
- dashboard meta-monitoring nhận diện từng instance.

---

## 32. Production checklist

### Architecture

- [ ] Ít nhất hai Grafana instance.
- [ ] PostgreSQL/MySQL HA dùng chung.
- [ ] Không dùng SQLite cho production HA.
- [ ] Load balancer health check và TLS.
- [ ] Replica phân tán node/AZ.
- [ ] PDB và graceful termination.
- [ ] Capacity tính cả database connection và alert query multiplication.

### Alerting

- [ ] Memberlist TCP/UDP 9094 hoặc Redis HA backend.
- [ ] Monitor cluster members/peer position/ping failures.
- [ ] Hiểu duplicate notification là có thể xảy ra.
- [ ] Test node failure và network partition.
- [ ] Preview single-node evaluation chỉ bật khi được chấp thuận.

### IAM

- [ ] Centralized IdP.
- [ ] Stable user identifier.
- [ ] Allowed group/domain.
- [ ] Default least privilege.
- [ ] Server Admin tách khỏi Org Admin.
- [ ] Break-glass được bảo vệ và diễn tập.
- [ ] Service account cho automation.
- [ ] Token owner, expiry và rotation.

### Authorization

- [ ] Folder theo ownership boundary.
- [ ] Permission cấp cho team.
- [ ] Kiểm tra inheritance.
- [ ] Không nhầm folder permission với datasource isolation.
- [ ] Xác nhận capability OSS/Enterprise/Cloud.

### Security

- [ ] HTTPS, secure cookie và HSTS.
- [ ] Anonymous access tắt.
- [ ] Signup/org creation được kiểm soát.
- [ ] Egress allow-list/firewall.
- [ ] Secret dùng env/file/secret manager.
- [ ] `secret_key` giống nhau trên mọi node và có backup.
- [ ] Signed/pinned plugins.
- [ ] Renderer tách riêng và dùng token.
- [ ] Không expose admin/backend trực tiếp.

### Operations

- [ ] Scrape từng Grafana instance.
- [ ] HTTP/runtime/database/alerting metrics.
- [ ] Central logs và trace khi cần.
- [ ] Synthetic dashboard/query/login/notification.
- [ ] SLO và error budget.
- [ ] Backup theo RPO.
- [ ] Restore test theo lịch.
- [ ] Staged upgrade và plugin compatibility test.
- [ ] DR runbook có owner.

---

## 33. Câu hỏi tự kiểm tra

1. Vì sao ba Grafana Pod dùng SQLite không phải HA?
2. Shared database lưu những state quan trọng nào?
3. Vì sao load balancer không cần sticky session theo HA model chuẩn?
4. `[remote_cache]` khác user session storage thế nào?
5. Memberlist của Alerting HA dùng những protocol/port nào?
6. Vì sao Alerting HA vẫn có thể gửi duplicate notification?
7. Thêm Grafana replica ảnh hưởng alert query load ra sao?
8. `ha_single_node_evaluation` đổi trade-off nào?
9. Grafana Live HA khác Alerting HA thế nào?
10. `root_url` ảnh hưởng SSO và alert link ra sao?
11. `Admin` khác `GrafanaAdmin` thế nào?
12. Tại sao cần break-glass khi dùng SSO?
13. LDAP group mapping dùng match nào khi user thuộc nhiều nhóm?
14. Vì sao folder permission không đủ để cô lập datasource trong OSS?
15. Những secret nào phải khôi phục cùng database?
16. Vì sao đổi `secret_key` tùy tiện gây lỗi?
17. Data source proxy tạo rủi ro SSRF thế nào?
18. Tại sao plugin phải nằm trong immutable image?
19. Grafana 13 thay đổi gì với image renderer?
20. `up=1` bỏ sót user journey nào?
21. Vì sao thêm replica có thể làm database/datasource tải cao hơn?
22. Backup thành công khác restore thành công thế nào?
23. Vì sao downgrade Grafana 13 không phải rollback đơn giản?
24. Khi nào nên tách Grafana instance thay vì dùng multi-org?
25. Vì sao không nên triển khai mới Grafana OnCall OSS?

---

## 34. Tài liệu chính thức

- [Set up Grafana for high availability](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-for-high-availability/)
- [Configure Grafana](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)
- [Configure Alerting high availability](https://grafana.com/docs/grafana/latest/alerting/set-up/configure-high-availability/)
- [Set up Grafana Live](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-grafana-live/)
- [Deploy Grafana on Kubernetes](https://grafana.com/docs/grafana/latest/setup-grafana/installation/kubernetes/)
- [Configure Generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/)
- [Configure LDAP](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/ldap/)
- [Roles and permissions](https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/)
- [Folder access control](https://grafana.com/docs/grafana/latest/administration/roles-and-permissions/folder-access-control/)
- [Configure security](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/)
- [Configure security hardening](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-security-hardening/)
- [Configure database encryption](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-database-encryption/)
- [Set up Grafana monitoring](https://grafana.com/docs/grafana/latest/setup-grafana/set-up-grafana-monitoring/)
- [Alerting meta-monitoring](https://grafana.com/docs/grafana/latest/alerting/set-up/meta-monitoring/)
- [Grafana HTTP API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/)
- [Upgrade to Grafana 13](https://grafana.com/docs/grafana/latest/upgrade-guide/upgrade-v13.0/)
- [Grafana OnCall OSS maintenance/archive notice](https://grafana.com/blog/grafana-oncall-maintenance-mode/)

---

## Chủ đề tiếp theo

[Metrics Design – RED, USE, Golden Signals và metric contract](../observability/metrics_design.md)

---

*Cập nhật lần cuối: 2026-07-29*
