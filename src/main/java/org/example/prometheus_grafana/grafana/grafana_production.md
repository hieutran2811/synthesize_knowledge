# Grafana Production – HA, SSO & Security

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Grafana Production Concerns

Production Grafana cần giải quyết: **HA** (không SPOF), **SSO** (quản lý users tập trung), **security** (HTTPS, RBAC, secrets), **performance** (connection pooling, caching), và **observability** (monitor Grafana itself).

---

## How – Grafana HA

```
Load Balancer (nginx/ALB)
  ├── Grafana-1 (stateless)
  └── Grafana-2 (stateless)
         ↓
  Shared PostgreSQL DB (sessions, dashboards, alerts)
         ↓
  Redis (session cache, optional)
```

```ini
# grafana.ini – HA config
[database]
type = postgres
host = postgres-ha:5432
name = grafana
user = grafana
password = $__env{DB_PASSWORD}
ssl_mode = require
max_idle_conn = 25
max_open_conn = 300
conn_max_lifetime = 14400     # 4h
log_queries = false

[remote_cache]
type = redis
connstr = addr=redis:6379,pool_size=100,db=0,ssl=false
# hoặc sentinel: addr=redis-sentinel:26379,mastername=mymaster

[session]
provider = redis
provider_config = addr=redis:6379,pool_size=10,db=1

[server]
root_url = https://grafana.example.com
enforce_domain = true

[security]
cookie_secure = true
cookie_samesite = lax
strict_transport_security = true
strict_transport_security_max_age_seconds = 86400
x_content_type_options = true
x_xss_protection = true
```

### K8s Deployment (HA)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: grafana
      containers:
        - name: grafana
          image: grafana/grafana:10.2.0
          ports:
            - containerPort: 3000
          envFrom:
            - secretRef:
                name: grafana-secrets
          env:
            - name: GF_DATABASE_TYPE
              value: postgres
            - name: GF_DATABASE_HOST
              value: postgres-grafana:5432
            - name: GF_REMOTE_CACHE_TYPE
              value: redis
          volumeMounts:
            - name: grafana-config
              mountPath: /etc/grafana
            - name: grafana-provisioning
              mountPath: /etc/grafana/provisioning
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /api/health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
      volumes:
        - name: grafana-config
          configMap:
            name: grafana-config
        - name: grafana-provisioning
          configMap:
            name: grafana-provisioning
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
spec:
  selector:
    app: grafana
  ports:
    - port: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [grafana.example.com]
      secretName: grafana-tls
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

---

## How – SSO Authentication

### OAuth2 với Keycloak

```ini
[auth.generic_oauth]
enabled = true
name = Keycloak
icon = signin
allow_sign_up = true
auto_login = false
client_id = grafana
client_secret = $__env{KEYCLOAK_CLIENT_SECRET}
scopes = openid email profile groups
empty_scopes = false

auth_url = https://sso.example.com/realms/prod/protocol/openid-connect/auth
token_url = https://sso.example.com/realms/prod/protocol/openid-connect/token
api_url = https://sso.example.com/realms/prod/protocol/openid-connect/userinfo

# Map Keycloak groups → Grafana roles
role_attribute_path = contains(groups[*], '/grafana/admins') && 'Admin' || contains(groups[*], '/grafana/editors') && 'Editor' || 'Viewer'
role_attribute_strict = false

# Map to Grafana organizations
org_mapping = ["Keycloak-Org-Name:1:Admin"]

# Team sync
groups_attribute_path = groups
team_ids_attribute_path = groups
```

### LDAP

```ini
[auth.ldap]
enabled = true
config_file = /etc/grafana/ldap.toml
allow_sign_up = true
```

```toml
# /etc/grafana/ldap.toml
[[servers]]
host = "ldap.example.com"
port = 636
use_ssl = true
start_tls = false
ssl_skip_verify = false
root_ca_cert = "/etc/ssl/certs/ca-cert.pem"

bind_dn = "cn=grafana-svc,ou=service-accounts,dc=example,dc=com"
bind_password = "password"
search_filter = "(uid=%s)"
search_base_dns = ["ou=people,dc=example,dc=com"]

[servers.attributes]
name = "givenName"
surname = "sn"
username = "uid"
member_of = "memberOf"
email = "mail"

# Admin group
[[servers.group_mappings]]
group_dn = "cn=grafana-admins,ou=groups,dc=example,dc=com"
org_role = "Admin"
grafana_admin = true

# Editor group
[[servers.group_mappings]]
group_dn = "cn=grafana-editors,ou=groups,dc=example,dc=com"
org_role = "Editor"

# Default: Viewer
[[servers.group_mappings]]
group_dn = "*"
org_role = "Viewer"
```

---

## How – Organizations & Teams (Multi-tenancy)

```
Grafana Multi-tenancy model:

Org 1: Production
  ├── Team: Backend (can view production dashboards)
  ├── Team: DBA (can view DB dashboards)
  └── Team: Platform (Admin)

Org 2: Staging
  └── All developers (Editor)

Users có thể thuộc nhiều Orgs với role khác nhau
```

```bash
# Tạo org via API
curl -X POST http://admin:pass@grafana:3000/api/orgs \
  -H "Content-Type: application/json" \
  -d '{"name": "Production"}'

# Tạo team
curl -X POST http://admin:pass@grafana:3000/api/teams \
  -H "Content-Type: application/json" \
  -d '{"name": "Backend", "orgId": 1}'

# Add user to team
curl -X POST http://admin:pass@grafana:3000/api/teams/1/members \
  -H "Content-Type: application/json" \
  -d '{"userId": 2}'

# Set team permissions trên folder
curl -X POST http://admin:pass@grafana:3000/api/folders/abc/permissions \
  -H "Content-Type: application/json" \
  -d '{"items": [{"teamId": 1, "permission": 2}]}'
  # permission: 1=View, 2=Edit, 4=Admin
```

---

## How – Secret Management

```ini
# Không lưu secrets plaintext trong grafana.ini
# Dùng environment variables
[database]
password = $__env{GF_DATABASE_PASSWORD}

# Hoặc Grafana Secret Manager (Vault)
[database]
password = $__vault{secret/grafana:db_password}
```

### K8s Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-secrets
  namespace: monitoring
type: Opaque
stringData:
  GF_SECURITY_ADMIN_PASSWORD: "$(openssl rand -base64 32)"
  GF_DATABASE_PASSWORD: "$(kubectl get secret postgres-grafana -o jsonpath='{.data.password}' | base64 -d)"
  GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: "keycloak-secret"
  GF_SMTP_PASSWORD: "smtp-password"
```

---

## How – Monitoring Grafana Itself

```promql
# Dashboard query performance
grafana_datasource_request_duration_seconds_bucket

# Request rate
rate(grafana_http_request_duration_seconds_count[5m])

# Active users
grafana_active_users

# Alert evaluation
grafana_alerting_rule_evaluation_duration_seconds_bucket

# DB connections
grafana_database_conn_in_use_calls_total
grafana_database_conn_idle_calls_total
```

```yaml
# Prometheus scrape config cho Grafana
- job_name: grafana
  static_configs:
    - targets: ["grafana:3000"]
  metrics_path: /metrics
  # Grafana expose /metrics với basic auth
  basic_auth:
    username: admin
    password: secret
```

---

## How – Grafana OnCall (Incident Management)

```
Grafana OnCall là alerting + on-call scheduling system
(acquired từ Amixr)

Flow:
Alert Rule (Grafana/Prometheus)
  → OnCall Integration
  → Escalation Chain
    → Notify: Slack/Phone/PagerDuty
    → Wait Xm → Escalate to next level
    → Acknowledge / Resolve

Tích hợp:
- Grafana Alerting (native)
- Prometheus Alertmanager (webhook)
- PagerDuty import
- Opsgenie import

On-call schedules:
- Calendar-based rotation
- Override
- Swap shifts

Tính năng:
- Mobile app (iOS/Android)
- Phone calls & SMS
- ChatOps (Slack/Telegram)
- Incident timeline
```

---

## Compare – Grafana OSS vs Grafana Enterprise vs Grafana Cloud

| | OSS | Enterprise | Cloud |
|--|-----|-----------|-------|
| Cost | Free | $$$$ | Free tier + pay-as-go |
| LDAP/SAML | Basic | Advanced (team sync) | Via SSO |
| Fine-grained RBAC | No | Yes | Yes |
| Data source permissions | No | Yes | Yes |
| Reporting (PDF) | No | Yes | Yes |
| SLA | No | Yes | 99.9% |
| Plugins | Community | Enterprise + | Same |
| Long-term metrics | Self-manage | Self-manage | Included |
| Loki/Tempo | Self-host | Self-host | Included |
| Support | Community | 24/7 | Tiered |

---

## Trade-offs

```
Self-hosted HA Grafana:
✅ Full control, no data leaves your infra
✅ Custom plugins, no vendor lock-in
❌ Phải manage database, Redis, SSL cert
❌ Upgrade phải cẩn thận (DB migration)
❌ No enterprise RBAC without license

Grafana Cloud:
✅ Zero ops, managed infrastructure
✅ Free tier khá generous (10k metrics, 50GB logs)
✅ Loki/Tempo included
❌ Data ra ngoài infra (compliance concern)
❌ Cost tăng nhanh khi scale
❌ Customization bị giới hạn
```

---

## Real-world – Security Hardening Checklist

```
Authentication:
□ Disable anonymous access (GF_AUTH_ANONYMOUS_ENABLED=false)
□ Enable SSO (OAuth2/SAML/LDAP)
□ Disable built-in user registration
□ Rotate admin password
□ API keys có expiry date

Network:
□ HTTPS only (cert-manager + Let's Encrypt)
□ HSTS enabled
□ Restrict /metrics endpoint (firewall rule)
□ No public access to admin API

Data:
□ External PostgreSQL (không dùng SQLite)
□ Encrypted DB connection (ssl_mode=require)
□ Backup DB regularly
□ Secret injection qua env vars / Vault

Plugins:
□ Only install trusted plugins
□ GF_PLUGIN_SIGNATURE_VERIFICATION=true
□ Review plugin permissions

Monitoring:
□ Alert on admin login failures
□ Alert on config changes
□ Audit log enabled (Enterprise)
```

---

## Ghi chú – Chủ đề tiếp theo
> `observability/metrics_design.md`: RED Method, USE Method, 4 Golden Signals, thiết kế metrics chuẩn SRE

---

*Cập nhật lần cuối: 2026-05-06*
