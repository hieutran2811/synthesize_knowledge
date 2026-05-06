# Alerting Strategy – SLO, Alert Design & On-call

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Alerting Strategy là gì?

**Alerting Strategy** là framework để thiết kế alerts **đúng người, đúng lúc, đúng context**. Alert tệ gây alert fatigue → on-call team bỏ qua alerts → incidents không được xử lý.

```
Alert anti-patterns (thực tế phổ biến):
- Too many alerts: 100+ alerts/day → noise → ignored
- Alert on cause (CPU high) thay vì effect (user impact)
- No runbook → engineer không biết làm gì
- No severity → everything is "critical"
- Page at 3AM cho non-urgent issue
- Alert không actionable ("disk high" nhưng không có action)
```

---

## How – Alert Design Principles

### 1. Alert phải Actionable

```
BAD:  "CPU > 80%"         → không biết làm gì
GOOD: "CPU > 90% for 15m AND memory_pressure"
      → cần investigate, scale up, hoặc kill runaway process
      → runbook: https://wiki/cpu-high

BAD:  "Pod restarted"     → pods restart thường xuyên, không quan trọng
GOOD: "Pod crash looping (>3 restarts/15m for 15m)"
      → có vấn đề thực sự, cần investigate logs
```

### 2. Alert trên Symptoms, không phải Causes

```
Cause-based (tệ):
  "High CPU"
  "Memory > 80%"
  "Disk I/O high"
  "DB connections high"

Symptom-based (tốt):
  "User-facing error rate > 5%"  ← directly affects users
  "Payment success rate < 99%"
  "API p99 latency > 2s"
  "Service unavailable (0 pods running)"

Cause-based alerts → noise, chồng chéo, khó correlate
Symptom-based alerts → 1 alert = 1 user-facing problem
```

### 3. Multi-level Severity

```
CRITICAL: Page immediately, wake up on-call
  → Service down
  → Error rate > 5% for 5m
  → SLO burn rate > 14.4x

WARNING: Notify, next business hours OK
  → Disk > 80% (filling slowly)
  → Memory > 75%
  → p99 latency elevated but not breaching SLO

INFO: Dashboard only, no notification
  → Deployment happened
  → Certificate renewing in 30d
  → Background job completed
```

---

## How – SLO-Based Alerting (The Right Way)

### Error Budget Concept

```
SLO: 99.9% availability trong 30 ngày
Error budget: 0.1% of 30d = 43.2 minutes downtime allowed

Nếu error rate cao:
  - 100x error rate → burn 100x faster → budget hết trong 26 phút
  - 10x error rate → budget hết trong 4.3 giờ
  - 1x error rate → budget hết đúng 30 ngày
  - <1x → thoải mái

Vấn đề alert cơ bản: "error rate > 1%" fire lúc 3AM
→ Mất 43 phút budget → không critical, nhưng alert rồi
→ Alert fatigue!

SLO alerting: alert dựa trên TỐC ĐỘ tiêu budget, không phải threshold cứng
```

### Multi-Burn-Rate Alert Rules

```yaml
# Nguồn gốc: Google SRE Workbook Chapter 5
# SLO = 99.9% → error_budget = 0.001

groups:
  - name: slo-availability
    rules:
      # Recording rules
      - record: job:slo_errors:rate1h
        expr: sum(rate(http_requests_total{status=~"5.."}[1h])) by (job)
              / sum(rate(http_requests_total[1h])) by (job)

      - record: job:slo_errors:rate6h
        expr: sum(rate(http_requests_total{status=~"5.."}[6h])) by (job)
              / sum(rate(http_requests_total[6h])) by (job)

      - record: job:slo_errors:rate3d
        expr: sum(rate(http_requests_total{status=~"5.."}[3d])) by (job)
              / sum(rate(http_requests_total[3d])) by (job)

      # Burn rate thresholds:
      # 14.4x → budget hết trong 1 giờ → PAGE NOW
      # 6x    → budget hết trong 6 giờ → PAGE (biz hours OK if not critical)
      # 3x    → budget hết trong 5 ngày → Slack ticket
      # 1x    → on pace to exhaust in 30d → Review weekly

      - alert: SLO_HighBurnRate_Critical
        expr: |
          (job:slo_errors:rate1h > (14.4 * 0.001))
          and
          (job:slo_errors:rate5m > (14.4 * 0.001))
        for: 2m
        labels:
          severity: critical
          slo_window: "1h"
        annotations:
          summary: "CRITICAL: {{ $labels.job }} burning error budget at 14.4x"
          description: |
            Current 1h error rate: {{ $value | humanizePercentage }}
            At this rate, error budget exhausts in ~1 hour.
            Immediate action required.
          runbook: "https://wiki.example.com/runbooks/slo-breach"

      - alert: SLO_HighBurnRate_Warning
        expr: |
          (job:slo_errors:rate6h > (6 * 0.001))
          and
          (job:slo_errors:rate30m > (6 * 0.001))
        for: 15m
        labels:
          severity: warning
          slo_window: "6h"
        annotations:
          summary: "WARNING: {{ $labels.job }} burning error budget at 6x"
          description: |
            6h error rate: {{ $value | humanizePercentage }}
            Error budget exhausts in ~6 hours if trend continues.

      - alert: SLO_LowBurnRate_Ticket
        expr: |
          job:slo_errors:rate3d > (3 * 0.001)
        for: 1h
        labels:
          severity: info
          slo_window: "3d"
        annotations:
          summary: "INFO: {{ $labels.job }} burning error budget at 3x"
          description: "Error budget will exhaust in ~10 days. Create improvement ticket."
```

---

## How – Alert Noise Reduction

### Inhibition Rules (Alertmanager)

```yaml
# Khi critical fire, suppress related warnings
inhibit_rules:
  # Service down → suppress all other alerts for same instance
  - source_matchers:
      - alertname = "ServiceDown"
    target_matchers:
      - alertname != "ServiceDown"
    equal: [instance, job]

  # Cluster-level alert → suppress individual node alerts
  - source_matchers:
      - alertname = "ClusterDown"
    target_matchers:
      - severity = "warning"
    equal: [cluster]

  # DB primary down → suppress replica lag alert
  - source_matchers:
      - alertname = "DatabasePrimaryDown"
    target_matchers:
      - alertname = "DatabaseReplicaLag"
    equal: [cluster]
```

### Deduplication

```yaml
# Group related alerts → 1 notification thay vì N
route:
  group_by: [alertname, job, namespace]   # nhóm theo service
  group_wait: 30s      # đợi nhóm thêm alerts trong 30s
  group_interval: 5m   # cập nhật nhóm mỗi 5m
  repeat_interval: 4h  # không spam, repeat sau 4h
```

### Time-based Routing (Business Hours)

```yaml
# alertmanager.yml
time_intervals:
  - name: business-hours
    time_intervals:
      - times:
          - start_time: "08:00"
            end_time: "19:00"
        weekdays: [monday:friday]
        location: Asia/Ho_Chi_Minh

  - name: non-business-hours
    time_intervals:
      - times:
          - start_time: "19:00"
            end_time: "23:59"
          - start_time: "00:00"
            end_time: "08:00"
        weekdays: [monday:friday]
      - weekdays: [saturday, sunday]
        location: Asia/Ho_Chi_Minh

route:
  routes:
    # Ngoài giờ hành chính: chỉ critical mới page
    - matchers:
        - severity = "warning"
      active_time_intervals:
        - non-business-hours
      receiver: "null"  # silence warnings off-hours

    - matchers:
        - severity = "critical"
      receiver: pagerduty
      active_time_intervals: []  # always

receivers:
  - name: "null"  # discard
```

---

## How – Runbook Template

```markdown
# Alert: [Alert Name]

## Severity
[Critical/Warning]

## Summary
[1-2 câu mô tả vấn đề]

## Impact
[Mô tả user impact nếu không xử lý]

## Diagnosis Steps
1. Check dashboard: [link]
2. Check logs: `kubectl logs -n {namespace} -l app={app} --tail=100`
3. Check recent deployments: `kubectl rollout history deployment/{app}`
4. Check dependencies: [list external services]

## Remediation

### Option 1: Rollback
kubectl rollout undo deployment/{app}

### Option 2: Scale up
kubectl scale deployment/{app} --replicas=5

### Option 3: [Other]
[steps]

## Escalation
- L1: @on-call-engineer
- L2: @senior-engineer (after 30 min)
- L3: @engineering-manager (after 1h)

## Post-mortem Template
After resolving, create post-mortem at [link]
```

---

## How – On-call Best Practices

```
Toil reduction:
□ Mỗi alert có runbook trước khi vào production
□ Auto-remediation cho các alert lặp lại
□ Regularly review + delete stale alerts
□ Alert coverage review sau mỗi incident ("why didn't we catch this?")

On-call rotation:
□ Follow-the-sun: team ở VN cover 8AM-10PM ICT, EU team covers rest
□ Primary + Secondary: primary handles, secondary escalation
□ Handoff notes: brief incoming on-call on active incidents
□ No 24/7 for 1 engineer → burnout

Alert metrics (track these):
  - MTTA: Mean Time To Acknowledge
  - MTTR: Mean Time To Resolve
  - Alert noise ratio: actionable / total alerts
  - Pages per week per engineer (target: <5)
  - % alerts acknowledged vs auto-resolved
```

---

## Compare – Alerting Approaches

| | Threshold-based | Anomaly Detection | SLO-based |
|--|----------------|-------------------|-----------|
| Implementation | Easy | Medium/Hard | Medium |
| False positive | High | Medium | Low |
| Context | No | Limited | Yes (budget) |
| User impact | Indirect | Maybe | Direct |
| Tuning effort | High | Very High | Medium |
| Good for | Simple infra | Unknown patterns | Services |

---

## Trade-offs

```
SLO-based alerting:
✅ Tương quan trực tiếp với user impact
✅ Ít false positives
✅ Error budget = shared language giữa dev/ops/product
❌ Cần implement SLI trước
❌ Khó explain cho non-technical stakeholders
❌ Cần chọn SLO window và burn rate thresholds cẩn thận

Threshold-based:
✅ Đơn giản, dễ hiểu
✅ Phù hợp cho infrastructure resources
❌ Alert fatigue cao
❌ Không có context (CPU 90% ok hay không?)
❌ Nhiều false positives
```

---

## Real-world – Alert Review Process

```
Monthly alert review:
1. Count alerts per week
2. Classify: Actionable / False positive / No action taken
3. Identify top noisy alerts
4. Fix or delete: tinh chỉnh threshold, thêm "for" clause, hoặc xóa
5. Check: any incident missed by current alerts?

Alert lifecycle:
  New alert → Staging test (1 week) → Production (with low severity)
  → Tune based on signal → Promote severity → Review quarterly

Rule: nếu alert không có action trong 3 months → delete nó
```

---

## Ghi chú – Chủ đề tiếp theo
> `stack_integration.md`: Full Observability Stack – Prometheus + Grafana + Loki + Tempo + OpenTelemetry

---

*Cập nhật lần cuối: 2026-05-06*
