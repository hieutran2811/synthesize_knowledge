# Roadmap – Prometheus & Grafana Knowledge

> Đã chuẩn hóa **14/14 chủ đề**. Baseline hiện tại: **Prometheus 3.13.x**, **Grafana 13.1.x**, **Mimir 3.1.x**, **OpenTelemetry Java 1.64.x / Collector 0.157.x**, **Pyroscope 2.2.x**, **bpftrace 0.24**, **Cilium/Hubble 1.19.6** và **OBI 0.10**.

| # | Topic | File | Status | Level |
|---|---|---|---|---|
| 1 | Prometheus Fundamentals | [prometheus/prometheus_fundamentals.md](prometheus/prometheus_fundamentals.md) | ✅ Prometheus 3.13 | Cơ bản |
| 2 | PromQL Advanced + Alerting Rules | [prometheus/prometheus_advanced.md](prometheus/prometheus_advanced.md) | ✅ Prometheus 3.13 | Trung cấp |
| 3 | Service Discovery & Relabeling | [prometheus/service_discovery.md](prometheus/service_discovery.md) | ✅ Prometheus 3.13 | Trung cấp |
| 4 | Prometheus Production | [prometheus/prometheus_production.md](prometheus/prometheus_production.md) | ✅ Prometheus 3.13 | Nâng cao |
| 5 | Grafana Fundamentals | [grafana/grafana_fundamentals.md](grafana/grafana_fundamentals.md) | ✅ Grafana 13.1 | Cơ bản |
| 6 | Grafana Advanced | [grafana/grafana_advanced.md](grafana/grafana_advanced.md) | ✅ Grafana 13.1 | Trung cấp |
| 7 | Grafana Production | [grafana/grafana_production.md](grafana/grafana_production.md) | ✅ Grafana 13.1 | Nâng cao |
| 8 | Metrics Design | [observability/metrics_design.md](observability/metrics_design.md) | ✅ Prometheus 3.13 | Trung cấp |
| 9 | Alerting Strategy & SLO | [observability/alerting_strategy.md](observability/alerting_strategy.md) | ✅ Prometheus 3.13 | Nâng cao |
| 10 | Full Stack Integration | [observability/stack_integration.md](observability/stack_integration.md) | ✅ Loki 3.7 / Tempo 3.0 | Nâng cao |
| 11 | OpenTelemetry Deep Dive | [observability/opentelemetry_deep_dive.md](observability/opentelemetry_deep_dive.md) | ✅ OTel Java 1.64 / Collector 0.157 | Nâng cao |
| 12 | Continuous Profiling | [observability/continuous_profiling.md](observability/continuous_profiling.md) | ✅ Pyroscope 2.2 / async-profiler 4.5 | Nâng cao |
| 13 | eBPF Observability Deep Dive | [observability/ebpf_observability.md](observability/ebpf_observability.md) | ✅ bpftrace 0.24 / Cilium 1.19.6 / OBI 0.10 | Nâng cao |
| 14 | Grafana Mimir Deep Dive | [observability/grafana_mimir.md](observability/grafana_mimir.md) | ✅ Mimir 3.1 / ingest storage | Nâng cao |

## Learning Path

```text
Prometheus core:
  1 → 2 → 3 → 4

Visualization:
  5 → 6 → 7

Observability design:
  8 → 9 → 10

Observability engineering mở rộng:
  10 → 11 → 12 → 13 → 14
```

Không cần học cứng theo số thứ tự. Người mới nên đi:

```text
1 Prometheus Fundamentals
  → 5 Grafana Fundamentals
  → 8 Metrics Design
  → 2 PromQL/Rules
  → 3 Service Discovery
  → 9 Alerting/SLO
  → các bài production/integration
```

## Key Concepts

| Concept | File |
|---|---|
| Pull model, data model, cardinality, metric types, local TSDB | [prometheus_fundamentals.md](prometheus/prometheus_fundamentals.md) |
| PromQL, vector matching, recording/alerting rules | [prometheus_advanced.md](prometheus/prometheus_advanced.md) |
| Service discovery, target relabeling, metric relabeling | [service_discovery.md](prometheus/service_discovery.md) |
| HA, remote storage, capacity và production operations | [prometheus_production.md](prometheus/prometheus_production.md) |
| Datasource, panel, variable và dashboard | [grafana_fundamentals.md](grafana/grafana_fundamentals.md) |
| Provisioning, alerting và dashboard-as-code | [grafana_advanced.md](grafana/grafana_advanced.md) |
| HA, authentication, authorization và hardening | [grafana_production.md](grafana/grafana_production.md) |
| RED, USE, Golden Signals, SLI và metric contract | [metrics_design.md](observability/metrics_design.md) |
| SLO, error budget, burn rate và alert ownership | [alerting_strategy.md](observability/alerting_strategy.md) |
| Metrics, logs, traces, Loki, Tempo và OpenTelemetry | [stack_integration.md](observability/stack_integration.md) |
| OTel API/SDK, context propagation, SemConv, sampling và Collector pipeline | [opentelemetry_deep_dive.md](observability/opentelemetry_deep_dive.md) |
| CPU/wall/allocation profiles, flame graph, Pyroscope, Parca và trace correlation | [continuous_profiling.md](observability/continuous_profiling.md) |
| eBPF verifier, maps, BTF/CO-RE, kernel/user hooks, network tracing và production safety | [ebpf_observability.md](observability/ebpf_observability.md) |
| Mimir ingest storage, Kafka, distributed TSDB, multi-tenancy, query path và object storage | [grafana_mimir.md](observability/grafana_mimir.md) |

## Chú thích trạng thái

- ✅ Hoàn thành – đã refactor theo baseline mục tiêu
- 🟡 Đã có nội dung nhưng cần rà soát/version hóa
- 🔄 Đang làm
- ⬜ Chưa làm

*Cập nhật lần cuối: 2026-07-29*
