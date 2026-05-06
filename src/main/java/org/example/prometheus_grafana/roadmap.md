# Roadmap – Prometheus & Grafana Knowledge

> Theo dõi tiến độ tổng hợp kiến thức Prometheus & Grafana

---

## Tiến Độ Tổng Quan

| # | Topic | File | Status | Level |
|---|-------|------|--------|-------|
| 1 | Prometheus Fundamentals | `prometheus/prometheus_fundamentals.md` | ✅ Done | Cơ bản |
| 2 | PromQL Advanced + Alerting Rules | `prometheus/prometheus_advanced.md` | ✅ Done | Trung cấp |
| 3 | Service Discovery & Relabeling | `prometheus/service_discovery.md` | ✅ Done | Trung cấp |
| 4 | Prometheus Production (Thanos/HA) | `prometheus/prometheus_production.md` | ✅ Done | Nâng cao |
| 5 | Grafana Fundamentals | `grafana/grafana_fundamentals.md` | ✅ Done | Cơ bản |
| 6 | Grafana Advanced (Alerting/Provisioning) | `grafana/grafana_advanced.md` | ✅ Done | Trung cấp |
| 7 | Grafana Production (HA/SSO/Security) | `grafana/grafana_production.md` | ✅ Done | Nâng cao |
| 8 | Metrics Design (RED/USE/4GS) | `observability/metrics_design.md` | ✅ Done | Trung cấp |
| 9 | Alerting Strategy & SLO | `observability/alerting_strategy.md` | ✅ Done | Nâng cao |
| 10 | Full Stack Integration (Loki/Tempo/OTel) | `observability/stack_integration.md` | ✅ Done | Nâng cao |

---

## Learning Path

```
Beginner:
  1 → 5 (Prometheus basics + Grafana basics)
  Goal: có thể setup Prometheus + Grafana, query metrics, tạo dashboard

Intermediate:
  2 → 3 → 6 → 8 (PromQL nâng cao + Service Discovery + Advanced Grafana + Metrics Design)
  Goal: viết alerting rules đúng, tạo dashboard chuyên nghiệp, instrument ứng dụng

Advanced:
  4 → 7 → 9 → 10 (Production HA + Security + SLO + Full Stack)
  Goal: vận hành production-grade observability stack
```

---

## Key Concepts Summary

| Concept | Tìm ở |
|---------|-------|
| Prometheus data model (4 types) | prometheus_fundamentals.md |
| PromQL rate(), histogram_quantile() | prometheus_fundamentals.md |
| Recording rules + Alerting rules | prometheus_advanced.md |
| Multi-burn-rate SLO alerts | prometheus_advanced.md |
| Kubernetes Service Discovery | service_discovery.md |
| Relabeling pipeline | service_discovery.md |
| Thanos architecture | prometheus_production.md |
| Grafana provisioning (as code) | grafana_fundamentals.md + grafana_advanced.md |
| Unified Alerting + Routing | grafana_advanced.md |
| Grafonnet / Jsonnet | grafana_advanced.md |
| Grafana HA + PostgreSQL | grafana_production.md |
| SSO (OAuth2/LDAP) | grafana_production.md |
| 4 Golden Signals / RED / USE | observability/metrics_design.md |
| SLI/SLO/Error Budget | observability/metrics_design.md |
| Alert noise reduction | observability/alerting_strategy.md |
| Loki + LogQL | observability/stack_integration.md |
| OpenTelemetry (OTel) | observability/stack_integration.md |
| Metrics → Logs → Traces correlation | observability/stack_integration.md |

---

*Cập nhật lần cuối: 2026-05-06*
