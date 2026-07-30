# Tổng Hợp Kiến Thức Prometheus & Grafana – Thực Chiến

> Đã chuẩn hóa **14/14 chủ đề**. Baseline hiện tại: **Prometheus 3.13.x**, **Grafana 13.1.x**, **Mimir 3.1.x**, **OpenTelemetry Java 1.64.x / Collector 0.157.x**, **Pyroscope 2.2.x**, **bpftrace 0.24**, **Cilium/Hubble 1.19.6** và **OBI 0.10**. Xem [roadmap](roadmap.md) để theo dõi tiến độ.

---

## Tổng quan

Prometheus và Grafana thường đi cùng nhau nhưng không cùng trách nhiệm:

```text
Application / Exporter
        │ expose metrics
        ▼
Prometheus ── store + PromQL + rules
    ▲                    │
    │ query              └──▶ Alertmanager ──▶ notifications
    │
Grafana ── dashboard / exploration
```

- Prometheus discover, scrape, lưu metric, chạy PromQL và evaluate rules.
- Grafana query datasource rồi trực quan hóa; nó không phải điều kiện để Prometheus thu thập metric.
- Alertmanager nhận alert từ Prometheus để group, deduplicate, route và notify.

---

## Danh sách chủ đề

### Prometheus

| # | Topic | File | Status |
|---|---|---|---|
| 1 | Prometheus Fundamentals | [prometheus/prometheus_fundamentals.md](prometheus/prometheus_fundamentals.md) | ✅ Prometheus 3.13 |
| 2 | PromQL Advanced + Alerting Rules | [prometheus/prometheus_advanced.md](prometheus/prometheus_advanced.md) | ✅ Prometheus 3.13 |
| 3 | Service Discovery | [prometheus/service_discovery.md](prometheus/service_discovery.md) | ✅ Prometheus 3.13 |
| 4 | Prometheus Production | [prometheus/prometheus_production.md](prometheus/prometheus_production.md) | ✅ Prometheus 3.13 |

### Grafana

| # | Topic | File | Status |
|---|---|---|---|
| 5 | Grafana Fundamentals | [grafana/grafana_fundamentals.md](grafana/grafana_fundamentals.md) | ✅ Grafana 13.1 |
| 6 | Grafana Advanced | [grafana/grafana_advanced.md](grafana/grafana_advanced.md) | ✅ Grafana 13.1 |
| 7 | Grafana Production | [grafana/grafana_production.md](grafana/grafana_production.md) | ✅ Grafana 13.1 |

### Observability Strategy

| # | Topic | File | Status |
|---|---|---|---|
| 8 | Metrics Design | [observability/metrics_design.md](observability/metrics_design.md) | ✅ Prometheus 3.13 |
| 9 | Alerting Strategy & SLO | [observability/alerting_strategy.md](observability/alerting_strategy.md) | ✅ Prometheus 3.13 |
| 10 | Full Observability Stack | [observability/stack_integration.md](observability/stack_integration.md) | ✅ Loki 3.7 / Tempo 3.0 |

### Observability Engineering mở rộng

| # | Topic | File | Status |
|---|---|---|---|
| 11 | OpenTelemetry Deep Dive | [observability/opentelemetry_deep_dive.md](observability/opentelemetry_deep_dive.md) | ✅ OTel Java 1.64 / Collector 0.157 |
| 12 | Continuous Profiling | [observability/continuous_profiling.md](observability/continuous_profiling.md) | ✅ Pyroscope 2.2 / async-profiler 4.5 |
| 13 | eBPF Observability Deep Dive | [observability/ebpf_observability.md](observability/ebpf_observability.md) | ✅ bpftrace 0.24 / Cilium 1.19.6 / OBI 0.10 |
| 14 | Grafana Mimir Deep Dive | [observability/grafana_mimir.md](observability/grafana_mimir.md) | ✅ Mimir 3.1 / ingest storage |

---

## Lộ trình gợi ý

```text
Nền tảng:
  prometheus_fundamentals → grafana_fundamentals → metrics_design

Xây hệ thống:
  prometheus_advanced → service_discovery → alerting_strategy

Production:
  prometheus_production → grafana_advanced
  → grafana_production → stack_integration
  → opentelemetry_deep_dive → continuous_profiling
  → ebpf_observability → grafana_mimir
```

---

*Cập nhật lần cuối: 2026-07-29*
