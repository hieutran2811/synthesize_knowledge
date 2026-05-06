# Grafana Fundamentals – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Grafana là gì?

**Grafana** là open-source **analytics & visualization platform** cho time-series, logs, và traces. Grafana không lưu trữ data mà **kết nối với data sources** (Prometheus, Loki, InfluxDB, Elasticsearch, SQL...) và visualize.

```
Data Sources:
  Prometheus, Loki, Tempo, InfluxDB, Elasticsearch,
  PostgreSQL, MySQL, CloudWatch, Azure Monitor, Datadog...
    ↓
Grafana (Query + Visualize + Alert)
    ↓
Dashboards → Panels (Graph, Stat, Table, Heatmap, Gauge...)
    ↓
Alerts → Notification Channels (Slack, PagerDuty, Email...)
```

---

## Components

```
Grafana Core:
├── Data Sources      → connectors tới backend storage
├── Dashboards        → collection of panels
├── Panels            → visualization đơn lẻ (graph, stat, table...)
├── Variables         → dynamic filtering trong dashboards
├── Alerts            → rule-based alerting (Grafana-managed)
├── Explore           → ad-hoc query không cần dashboard
├── Annotations       → mark events trên graph (deploy, incidents)
└── Plugins           → extend data sources, panels, apps
```

---

## How – Cài Đặt & Cấu Hình

### Docker Compose

```yaml
services:
  grafana:
    image: grafana/grafana:10.2.0
    ports:
      - "3000:3000"
    environment:
      # Admin credentials
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=secret
      # Anonymous access (đọc)
      - GF_AUTH_ANONYMOUS_ENABLED=false
      # SMTP
      - GF_SMTP_ENABLED=true
      - GF_SMTP_HOST=smtp.gmail.com:587
      - GF_SMTP_USER=alerts@example.com
      - GF_SMTP_PASSWORD=xxxx
      # Plugins
      - GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel
      # Database (mặc định SQLite, production dùng PostgreSQL)
      - GF_DATABASE_TYPE=postgres
      - GF_DATABASE_HOST=postgres:5432
      - GF_DATABASE_NAME=grafana
      - GF_DATABASE_USER=grafana
      - GF_DATABASE_PASSWORD=grafana
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/var/lib/grafana/dashboards
    restart: unless-stopped

volumes:
  grafana_data:
```

### grafana.ini (quan trọng)

```ini
[server]
http_port = 3000
root_url = https://grafana.example.com
serve_from_sub_path = false

[database]
type = postgres
host = postgres:5432
name = grafana
user = grafana
password = secret
ssl_mode = require

[security]
admin_user = admin
admin_password = $__env{GRAFANA_ADMIN_PASSWORD}
secret_key = $__env{GRAFANA_SECRET_KEY}  # dùng cho signing cookies
cookie_secure = true
cookie_samesite = lax
allow_embedding = false  # bật nếu embed dashboards vào app khác

[auth.generic_oauth]   # SSO với Keycloak/Okta/Azure AD
enabled = true
name = SSO
client_id = grafana
client_secret = $__env{OAUTH_SECRET}
scopes = openid email profile
auth_url = https://sso.example.com/auth/realms/prod/protocol/openid-connect/auth
token_url = https://sso.example.com/auth/realms/prod/protocol/openid-connect/token
api_url = https://sso.example.com/auth/realms/prod/protocol/openid-connect/userinfo
role_attribute_path = contains(groups[*], 'grafana-admin') && 'Admin' || 'Viewer'

[users]
allow_sign_up = false
auto_assign_org = true
auto_assign_org_role = Viewer   # default role

[unified_alerting]
enabled = true

[alerting]
enabled = false   # legacy alerting (tắt khi dùng unified)
```

---

## How – Data Sources

### Prometheus Data Source (Provisioning)

```yaml
# grafana/provisioning/datasources/prometheus.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    jsonData:
      timeInterval: "15s"         # scrape interval (cho chính xác hơn)
      queryTimeout: "60s"
      httpMethod: POST            # POST cho query dài
      exemplarTraceIdDestinations:
        - name: traceID
          datasourceUid: Tempo    # link exemplar → Tempo trace
    version: 1
    editable: true

  # Thanos Query thay Prometheus
  - name: Thanos
    type: prometheus
    access: proxy
    url: http://thanos-query:9090
    jsonData:
      timeInterval: "1m"          # Thanos data resolution
      customQueryParameters: "max_source_resolution=5m"
    version: 1

  # Loki
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    jsonData:
      derivedFields:
        - datasourceUid: Tempo
          matcherRegex: '"traceId":"(\w+)"'
          name: TraceID
          url: "$${__value.raw}"
    version: 1

  # Tempo (Tracing)
  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    jsonData:
      tracesToLogs:
        datasourceUid: Loki
        tags: ["job", "namespace", "pod"]
        mappedTags:
          - key: service.name
            value: app
      serviceMap:
        datasourceUid: Prometheus
    version: 1
```

---

## How – Dashboard & Panel

### Panel Types chính

```
Time Series    → line/bar chart (metrics over time) [phổ biến nhất]
Stat           → single value với trend sparkline
Gauge          → semicircle gauge (0-100%, threshold colors)
Bar Chart      → so sánh values (bar/horizontal bar)
Table          → tabular data, sortable, colored cells
Heatmap        → distribution theo thời gian (histogram buckets)
Histogram      → distribution của values
Pie Chart      → tỷ lệ phần trăm
State Timeline → state changes over time (on/off, up/down)
Status History → grid of status over time
Logs           → log viewer (dùng với Loki)
Traces         → trace viewer (dùng với Tempo/Jaeger)
Geomap         → geographical data
Canvas         → custom layout với shapes/text
Alert List     → list alerts hiện tại
Dashboard List → links tới dashboards khác
News           → RSS feed
```

### Time Series Panel (JSON Model)

```json
{
  "type": "timeseries",
  "title": "HTTP Request Rate",
  "datasource": "Prometheus",
  "targets": [
    {
      "expr": "sum(rate(http_requests_total{job=\"$job\"}[5m])) by (status)",
      "legendFormat": "{{status}}",
      "refId": "A"
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "reqps",
      "color": {"mode": "palette-classic"},
      "thresholds": {
        "mode": "absolute",
        "steps": [
          {"color": "green", "value": null},
          {"color": "yellow", "value": 1000},
          {"color": "red", "value": 5000}
        ]
      }
    },
    "overrides": [
      {
        "matcher": {"id": "byName", "options": "500"},
        "properties": [{"id": "color", "value": {"fixedColor": "red", "mode": "fixed"}}]
      }
    ]
  },
  "options": {
    "tooltip": {"mode": "multi", "sort": "desc"},
    "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "max", "last"]},
    "fillOpacity": 10,
    "gradientMode": "opacity"
  }
}
```

---

## How – Variables (Template Variables)

Variables cho phép dashboard **dynamic** – người dùng filter theo job, namespace, instance...

```json
// Provisioned dashboard JSON: templating section
{
  "templating": {
    "list": [
      {
        "name": "namespace",
        "label": "Namespace",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(kube_namespace_labels, namespace)",
        "refresh": 2,           // 2 = refresh on time range change
        "multi": true,          // allow select nhiều values
        "includeAll": true,     // option "All"
        "allValue": ".*",       // regex match all khi chọn All
        "sort": 1               // sort alphabetically
      },
      {
        "name": "pod",
        "label": "Pod",
        "type": "query",
        "datasource": "Prometheus",
        // Chained variable: pod options depend on namespace selection
        "query": "label_values(kube_pod_labels{namespace=~\"$namespace\"}, pod)",
        "refresh": 2,
        "multi": true,
        "includeAll": true
      },
      {
        "name": "interval",
        "label": "Interval",
        "type": "interval",
        "options": [
          {"text": "30s", "value": "30s"},
          {"text": "1m", "value": "1m"},
          {"text": "5m", "value": "5m"},
          {"text": "15m", "value": "15m"}
        ],
        "current": {"text": "1m", "value": "1m"}
      },
      {
        "name": "env",
        "label": "Environment",
        "type": "custom",
        "options": [
          {"text": "production", "value": "production"},
          {"text": "staging", "value": "staging"}
        ]
      }
    ]
  }
}
```

### Dùng Variables trong Query

```promql
# Dùng $variable trong PromQL
rate(http_requests_total{namespace="$namespace", pod=~"$pod"}[$interval])

# $__rate_interval: smart interval cho rate() (tự tính dựa trên time range)
rate(http_requests_total[$__rate_interval])

# $__range: total time range hiện tại
increase(http_requests_total[$__range])

# $__from, $__to: start/end của time range (Unix ms)
# Dùng trong SQL queries
```

---

## How – Annotations

```json
// Thêm annotations tự động từ Prometheus query
{
  "annotations": {
    "list": [
      {
        "name": "Deployments",
        "datasource": "Prometheus",
        "expr": "changes(kube_deployment_status_observed_generation{namespace=\"production\"}[5m]) > 0",
        "step": "60s",
        "titleFormat": "Deployment: {{deployment}}",
        "textFormat": "New revision deployed",
        "tagKeys": "namespace,deployment",
        "iconColor": "blue",
        "hide": false
      },
      {
        "name": "Alerts",
        "datasource": "-- Grafana --",
        "type": "alert",
        "iconColor": "red"
      }
    ]
  }
}
```

---

## How – Explore (Ad-hoc Query)

```
Explore = Query editor không gắn với dashboard
Dùng để:
- Debug: query nhanh không tạo panel
- Correlate logs & metrics: split view
- Trace investigation
- Kiểm tra query trước khi add vào dashboard

Split Mode:
  LEFT: Prometheus metrics
  RIGHT: Loki logs
  → Correlate cùng time range
```

---

## Compare – Grafana vs Alternatives

| | Grafana | Kibana | DataDog | Dynatrace |
|--|---------|--------|---------|-----------|
| Data sources | 100+ | ELK stack | Datadog only | Dynatrace only |
| Cost | Free OSS | Free OSS | $$$$ | $$$$ |
| Alerting | Unified alerts | Basic | Advanced | Advanced |
| Ease of use | Medium | Medium | Easy | Easy |
| Customization | Very high | Medium | Low | Low |
| K8s native | Yes | Yes | Yes | Yes |
| Log integration | Loki/ELK | Native | Yes | Yes |
| Trace integration | Tempo/Jaeger | APM | Yes | Yes |

---

## Trade-offs

```
Grafana:
✅ Hỗ trợ rất nhiều data sources
✅ Dashboard as code (JSON export/import)
✅ Free và open source
✅ Community dashboards (grafana.com/grafana/dashboards)
✅ Plugin ecosystem phong phú

❌ Không lưu trữ data (phụ thuộc data sources)
❌ Alerting (Unified Alerting) còn đang phát triển
❌ Dashboard JSON config phức tạp để viết tay
❌ HA setup cần external database
❌ Permission model (org/team) đôi khi confusing
```

---

## Real-world

### Import Community Dashboards

```
https://grafana.com/grafana/dashboards/

Dashboards phổ biến:
- 1860: Node Exporter Full (server metrics)
- 315:  Kubernetes cluster monitoring
- 6417: Kubernetes Pods
- 13332: Spring Boot Statistics (Micrometer)
- 7589: PostgreSQL Database
- 763:  Redis Dashboard
- 10991: RabbitMQ Overview
- 12611: JVM (Micrometer)

Import: Dashboards → Import → paste ID → Load
```

### Best Practices

```
□ Sử dụng $__rate_interval thay vì hard-code [5m]
□ Thêm description cho mỗi panel (Alt+Enter hoặc panel info)
□ Group panels vào rows (collapsed by default)
□ Đặt meaningful dashboard tags: namespace, team, service
□ Link dashboards: drill-down từ overview → detail
□ Set default time range phù hợp (Last 1h cho ops, Last 24h cho overview)
□ Use repeating panels/rows cho multi-instance
□ Export dashboard JSON vào git (IaC)
□ Version dashboards với annotations
```

---

## Ghi chú – Chủ đề tiếp theo
> `grafana_advanced.md`: Templating nâng cao, Unified Alerting, Grafana as Code (Terraform/Jsonnet/Grafonnet), Provisioning

---

*Cập nhật lần cuối: 2026-05-06*
