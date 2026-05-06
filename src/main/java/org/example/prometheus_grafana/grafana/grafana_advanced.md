# Grafana Advanced – Alerting, Provisioning & Grafana as Code

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Grafana Advanced

Grafana nâng cao bao gồm: **Unified Alerting** (rule-based với routing), **Dashboard provisioning** (GitOps/IaC), **Grafonnet/Jsonnet** (dashboard as code), **Transformations** (data manipulation), và **advanced panel techniques**.

---

## How – Unified Alerting (Grafana 9+)

Grafana Unified Alerting thay thế cả legacy alerting lẫn tích hợp với Alertmanager, cung cấp single pane cho alert management.

```
Alert Rules → Evaluation Groups → Alert Instances
    ↓
Contact Points (Slack, PagerDuty, Email, Webhook...)
    ↓
Notification Policies (routing tree)
    ↓
Silences / Mute Timings
```

### Alert Rule via Provisioning

```yaml
# grafana/provisioning/alerting/rules.yml
apiVersion: 1

groups:
  - orgId: 1
    name: Application Alerts
    folder: Alerts
    interval: 1m

    rules:
      - uid: high-error-rate
        title: High Error Rate
        condition: C
        for: 2m
        labels:
          severity: warning
          team: backend
        annotations:
          summary: "High error rate: {{ $labels.job }}"
          description: "Error rate {{ $values.C | humanizePercentage }} exceeds 5%"
          runbook: "https://wiki.example.com/runbooks/high-error-rate"

        data:
          # A: error requests rate
          - refId: A
            relativeTimeRange: {from: 600, to: 0}
            datasourceUid: prometheus
            model:
              expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
              intervalMs: 1000
              maxDataPoints: 43200
              instant: false

          # B: total requests rate
          - refId: B
            relativeTimeRange: {from: 600, to: 0}
            datasourceUid: prometheus
            model:
              expr: sum(rate(http_requests_total[5m])) by (job)
              instant: false

          # C: ratio (reduce A/B to scalar)
          - refId: C
            datasourceUid: "-100"   # built-in expression datasource
            model:
              type: math
              expression: "$A / $B"

        noDataState: NoData
        execErrState: Alerting

      - uid: pod-crash-looping
        title: Pod CrashLooping
        condition: A
        for: 15m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} crash looping"
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: |
                rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0
              instant: true
              relativeTimeRange: {from: 300, to: 0}
```

### Contact Points (Provisioning)

```yaml
# grafana/provisioning/alerting/contact-points.yml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: Slack-Critical
    receivers:
      - uid: slack-critical-receiver
        type: slack
        settings:
          url: "$SLACK_WEBHOOK_CRITICAL"
          recipient: "#alerts-critical"
          title: |
            [{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}
          text: |
            {{ range .Alerts }}
            *Summary:* {{ .Annotations.summary }}
            *Description:* {{ .Annotations.description }}
            {{ end }}
          mentionChannel: "here"
          iconEmoji: ":fire:"

  - orgId: 1
    name: PagerDuty
    receivers:
      - uid: pagerduty-receiver
        type: pagerduty
        settings:
          integrationKey: "$PAGERDUTY_KEY"
          severity: critical
          summary: "{{ .GroupLabels.alertname }}: {{ .Annotations.summary }}"

  - orgId: 1
    name: Email-DBA
    receivers:
      - uid: email-dba
        type: email
        settings:
          addresses: "dba@example.com;senior-dba@example.com"
          subject: "[Grafana Alert] {{ .GroupLabels.alertname }}"
```

### Notification Policies (Routing)

```yaml
# grafana/provisioning/alerting/notification-policies.yml
apiVersion: 1

policies:
  - orgId: 1
    receiver: Slack-Default      # default
    group_by: [alertname, job]
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes:
      - receiver: PagerDuty
        matchers:
          - severity = critical
        group_wait: 10s
        repeat_interval: 1h

      - receiver: Email-DBA
        matchers:
          - job =~ "postgres|mysql|redis"

      - receiver: Slack-Critical
        matchers:
          - severity =~ "critical|warning"
        continue: true  # continue matching

mute_timings:
  - orgId: 1
    name: Business Hours Only
    time_intervals:
      - times:
          - start_time: "09:00"
            end_time: "18:00"
        weekdays: [monday:friday]
        location: Asia/Ho_Chi_Minh
```

---

## How – Transformations (Data Manipulation)

Transformations xử lý data **sau khi query**, trước khi render panel. Không cần PromQL phức tạp.

```json
// Panel transformations
"transformations": [
  // Merge: gộp nhiều query vào 1 table
  {"id": "merge", "options": {}},

  // Filter by value: chỉ giữ rows thỏa điều kiện
  {
    "id": "filterByValue",
    "options": {
      "filters": [{"fieldName": "Value", "config": {"id": "greater", "options": {"value": 0}}}],
      "type": "include",
      "match": "all"
    }
  },

  // Sort by field
  {"id": "sortBy", "options": {"fields": [{"displayName": "Value", "desc": true}]}},

  // Rename fields
  {
    "id": "organize",
    "options": {
      "renameByName": {
        "job": "Service",
        "Value": "Error Rate"
      },
      "excludeByName": {"Time": true}
    }
  },

  // Calculate (add computed column)
  {
    "id": "calculateField",
    "options": {
      "mode": "reduceRow",
      "reduce": {"reducer": "sum"},
      "alias": "Total"
    }
  },

  // Group by
  {
    "id": "groupBy",
    "options": {
      "fields": {
        "namespace": {"aggregations": [], "operation": "groupby"},
        "Value": {"aggregations": ["sum", "mean", "max"], "operation": "aggregate"}
      }
    }
  },

  // Convert field type
  {
    "id": "convertFieldType",
    "options": {
      "conversions": [{"targetField": "timestamp", "destinationType": "time"}]
    }
  }
]
```

---

## How – Dashboard Provisioning (GitOps)

```yaml
# grafana/provisioning/dashboards/default.yml
apiVersion: 1

providers:
  - name: Default
    orgId: 1
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10   # reload từ disk mỗi 10s
    allowUiUpdates: false       # prevent manual edits (enforce as-code)
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true  # folder = subfolder trong path
```

```
# Folder structure → Grafana folders
/var/lib/grafana/dashboards/
├── Infrastructure/
│   ├── node-exporter.json
│   ├── kubernetes.json
│   └── docker.json
├── Application/
│   ├── api-overview.json
│   └── spring-boot.json
└── Business/
    └── orders.json
```

---

## How – Grafonnet / Jsonnet (Dashboard as Code)

```jsonnet
// dashboards/api-overview.jsonnet
local grafana = import 'grafonnet/grafana.libsonnet';
local dashboard = grafana.dashboard;
local row = grafana.row;
local prometheus = grafana.prometheus;
local graphPanel = grafana.graphPanel;
local statPanel = grafana.statPanel;
local template = grafana.template;

// Variables
local jobVar = template.new(
  name='job',
  datasource='Prometheus',
  query='label_values(http_requests_total, job)',
  label='Service',
  refresh='time',
  multi=true,
  includeAll=true,
);

// Panels
local requestRatePanel = graphPanel.new(
  title='Request Rate',
  datasource='Prometheus',
  legend_show=true,
  legend_values=true,
  legend_current=true,
  legend_avg=true,
  fill=1,
  linewidth=2,
).addTarget(
  prometheus.target(
    expr='sum(rate(http_requests_total{job=~"$job"}[$__rate_interval])) by (job)',
    legendFormat='{{job}}',
  )
);

local errorRatePanel = statPanel.new(
  title='Error Rate',
  datasource='Prometheus',
  colorMode='background',
  graphMode='area',
  unit='percentunit',
).addTarget(
  prometheus.target(
    expr=|||
      sum(rate(http_requests_total{job=~"$job",status=~"5.."}[$__rate_interval]))
      / sum(rate(http_requests_total{job=~"$job"}[$__rate_interval]))
    |||,
    instant=true,
  )
).addThreshold(
  {color: 'green', value: null}
).addThreshold(
  {color: 'yellow', value: 0.01}
).addThreshold(
  {color: 'red', value: 0.05}
);

// Dashboard
dashboard.new(
  title='API Overview',
  uid='api-overview',
  tags=['api', 'production'],
  time_from='now-1h',
  refresh='30s',
  schemaVersion=36,
)
.addTemplate(jobVar)
.addRow(
  row.new(title='Request Metrics', collapse=false)
  .addPanel(requestRatePanel, gridPos={x: 0, y: 0, w: 12, h: 8})
  .addPanel(errorRatePanel, gridPos={x: 12, y: 0, w: 6, h: 8})
)
```

```bash
# Build dashboard JSON từ Jsonnet
jsonnet -J vendor dashboards/api-overview.jsonnet -o output/api-overview.json

# Dùng grafonnet-lib
jsonnet -J grafonnet-lib dashboards/api-overview.jsonnet
```

---

## How – Grafana API (Automation)

```bash
# Tạo data source
curl -X POST http://admin:secret@grafana:3000/api/datasources \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }'

# Import dashboard
curl -X POST http://admin:secret@grafana:3000/api/dashboards/import \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": '"$(cat dashboard.json)"',
    "overwrite": true,
    "folderId": 0
  }'

# Search dashboards
curl http://admin:secret@grafana:3000/api/search?type=dash-db | jq '.[].title'

# Get dashboard by UID
curl http://admin:secret@grafana:3000/api/dashboards/uid/api-overview

# Create annotation
curl -X POST http://admin:secret@grafana:3000/api/annotations \
  -H "Content-Type: application/json" \
  -d '{
    "dashboardId": 1,
    "time": '"$(date +%s000)"',
    "text": "v2.1.0 deployed",
    "tags": ["deploy", "production"]
  }'

# Snapshot (share readonly)
curl -X POST http://admin:secret@grafana:3000/api/snapshots \
  -H "Content-Type: application/json" \
  -d '{"dashboard": '"$(cat dashboard.json)"', "expires": 3600}'
```

### Terraform Provider

```hcl
# main.tf
terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 2.0"
    }
  }
}

provider "grafana" {
  url  = "https://grafana.example.com"
  auth = var.grafana_api_key
}

resource "grafana_data_source" "prometheus" {
  type       = "prometheus"
  name       = "Prometheus"
  url        = "http://prometheus:9090"
  is_default = true

  json_data_encoded = jsonencode({
    timeInterval = "15s"
    httpMethod   = "POST"
  })
}

resource "grafana_folder" "application" {
  title = "Application"
}

resource "grafana_dashboard" "api_overview" {
  folder    = grafana_folder.application.id
  config_json = file("${path.module}/dashboards/api-overview.json")
}

resource "grafana_alert_rule_group" "app_alerts" {
  name             = "Application Alerts"
  folder_uid       = grafana_folder.application.uid
  interval_seconds = 60

  rule {
    name      = "High Error Rate"
    condition = "C"
    for       = "2m"

    labels    = { severity = "warning" }
    annotations = { summary = "High error rate" }

    data {
      ref_id = "A"
      relative_time_range { from = 600; to = 0 }
      datasource_uid = grafana_data_source.prometheus.uid
      model = jsonencode({ expr = "sum(rate(http_requests_total{status=~\"5..\"}[5m]))" })
    }
  }
}
```

---

## How – Advanced Panel Techniques

### Repeating Panels (per-instance)

```json
{
  "repeat": "instance",           // variable name
  "repeatDirection": "h",         // h = horizontal, v = vertical
  "maxPerRow": 4,
  "gridPos": {"h": 8, "w": 6}     // width per panel
}
```

### Data Links (Drill-down)

```json
"links": [
  {
    "title": "View Pod Details",
    "url": "/d/pod-detail/pod-detail?var-pod=${__series.name}&${__url_time_range}",
    "targetBlank": false
  },
  {
    "title": "View Logs",
    "url": "/explore?orgId=1&left={\"datasource\":\"Loki\",\"queries\":[{\"expr\":\"{pod=\\\"${__series.name}\\\"}\"}],\"range\":{\"from\":\"${__from}\",\"to\":\"${__to}\"}}",
    "targetBlank": true
  }
]
```

### Value Mappings

```json
"mappings": [
  {"type": "value", "options": {"1": {"text": "Running", "color": "green"}}},
  {"type": "value", "options": {"0": {"text": "Stopped", "color": "red"}}},
  {"type": "range", "options": {"from": 0.9, "to": 1, "result": {"text": "Healthy", "color": "green"}}},
  {"type": "special", "options": {"match": "null", "result": {"text": "N/A"}}}
]
```

---

## Trade-offs

```
Unified Alerting:
✅ Single place quản lý alert rules + routing
✅ Hỗ trợ nhiều data sources (không chỉ Prometheus)
✅ Preview alert trực tiếp trong UI
❌ Phức tạp hơn Alertmanager đơn thuần
❌ State lưu trong Grafana DB (cần HA Grafana DB)

Grafonnet/Jsonnet:
✅ Dashboard as code, version control được
✅ Reuse components, DRY
✅ Tự động generate nhiều similar dashboards
❌ Learning curve cao
❌ Debugging khó hơn JSON trực tiếp
❌ Build pipeline phức tạp hơn

Provisioning:
✅ Dashboards không thể bị xóa/sửa từ UI
✅ Tích hợp CI/CD
❌ Không thể edit từ UI nếu allowUiUpdates=false
```

---

## Ghi chú – Chủ đề tiếp theo
> `grafana_production.md`: HA setup, LDAP/SAML SSO, multi-org, Grafana OnCall, Grafana Cloud, security hardening

---

*Cập nhật lần cuối: 2026-05-06*
