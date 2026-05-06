# Tổng Hợp Kiến Thức Prometheus & Grafana – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## Tổng Quan

**Prometheus + Grafana** là bộ đôi monitoring tiêu chuẩn trong hệ sinh thái Cloud-Native / Kubernetes.

```
Thu thập Metrics → Lưu trữ → Query → Visualize → Alert

App/System → Prometheus (scrape/pull) → TSDB → PromQL
                                              ↓
                                         Grafana (dashboards)
                                              ↓
                                         AlertManager (notifications)
```

---

## Danh Sách Sub-Topics

### Prometheus
| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Prometheus Fundamentals | `prometheus/prometheus_fundamentals.md` | ✅ |
| 2 | PromQL Advanced + Alerting Rules | `prometheus/prometheus_advanced.md` | ✅ |
| 3 | Service Discovery | `prometheus/service_discovery.md` | ✅ |
| 4 | Prometheus Production (HA/Thanos) | `prometheus/prometheus_production.md` | ✅ |

### Grafana
| # | Topic | File | Status |
|---|-------|------|--------|
| 5 | Grafana Fundamentals | `grafana/grafana_fundamentals.md` | ✅ |
| 6 | Grafana Advanced (Templating/Alerting) | `grafana/grafana_advanced.md` | ✅ |
| 7 | Grafana Production | `grafana/grafana_production.md` | ✅ |

### Observability Strategy
| # | Topic | File | Status |
|---|-------|------|--------|
| 8 | Metrics Design (RED/USE/4 Golden Signals) | `observability/metrics_design.md` | ✅ |
| 9 | Alerting Strategy & SLO/SLI/SLA | `observability/alerting_strategy.md` | ✅ |
| 10 | Full Observability Stack (Loki/Tempo/OTel) | `observability/stack_integration.md` | ✅ |

---

## Learning Path

```
Cơ bản:
  prometheus_fundamentals → grafana_fundamentals → metrics_design

Trung cấp:
  prometheus_advanced → service_discovery → grafana_advanced → alerting_strategy

Nâng cao:
  prometheus_production → grafana_production → stack_integration
```

---

*Cập nhật lần cuối: 2026-05-06*
