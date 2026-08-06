# Tổng Hợp Kiến Thức Prometheus & Grafana – Thực Chiến

> Đã chuẩn hóa **39/39 chủ đề**. Baseline hiện tại: **Prometheus 3.13.x**, **Grafana 13.1.x**, **Mimir 3.1.x**, **OpenTelemetry Java 1.64.x / Collector 0.157.x / Semantic Conventions 1.43.x**, **Pyroscope 2.2.x**, **PostgreSQL 18**, **MySQL 8.4 LTS**, **Redis Open Source 8.x**, **Apache Kafka 4.3.x**, **Apache Airflow 3.3.x**, **Apache Spark 4.2.x**, **OpenLineage 1.50.x**, **MLflow 3.x**, **Blackbox Exporter 0.28.x**, tài liệu **Kubernetes 1.36 stable/multi-tenancy/autoscaling/CSI**, **KEDA 2.20**, Elastic/OpenSearch/Ceph hiện hành, NIST CSF 2.0, NIST Privacy Framework, MITRE ATT&CK v18, OCSF, **SLSA 1.2**, **CDEvents 0.5.0**, **FOCUS 1.4**, **SCI 1.1 / ISO/IEC 21031:2024**, W3C Trace Context, FinOps Unit Economics/Sustainability, OpenFeature/OpenGitOps và OpenTelemetry FaaS/GenAI/CI-CD/feature-flag/session/object-store/Elasticsearch conventions hiện hành, Core Web Vitals, Android Vitals và Apple MetricKit hiện hành, **bpftrace 0.24**, **Cilium/Hubble 1.20.x** và **OBI 0.10**. Xem [roadmap](roadmap.md) để theo dõi tiến độ.

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
| 13 | eBPF Observability Deep Dive | [observability/ebpf_observability.md](observability/ebpf_observability.md) | ✅ bpftrace 0.24 / Cilium 1.20 / OBI 0.10 |
| 14 | Grafana Mimir Deep Dive | [observability/grafana_mimir.md](observability/grafana_mimir.md) | ✅ Mimir 3.1 / ingest storage |
| 15 | Telemetry Governance & FinOps | [observability/telemetry_governance_finops.md](observability/telemetry_governance_finops.md) | ✅ Data contracts / cost governance |
| 16 | Chaos Engineering for Observability | [observability/chaos_engineering_observability.md](observability/chaos_engineering_observability.md) | ✅ Pipeline SLO / resilience / DR |
| 17 | Observability Platform Engineering | [observability/observability_platform_engineering.md](observability/observability_platform_engineering.md) | ✅ Self-service / platform product / SLO |
| 18 | Incident Response with Observability | [observability/incident_response_observability.md](observability/incident_response_observability.md) | ✅ Command / triage / evidence / learning |
| 19 | Database Observability & Performance Engineering | [observability/database_observability_performance.md](observability/database_observability_performance.md) | ✅ PostgreSQL / MySQL / query performance |
| 20 | Redis & Cache Observability | [observability/redis_cache_observability.md](observability/redis_cache_observability.md) | ✅ Redis 8.x / cache correctness / failure modes |
| 21 | Kubernetes Observability Deep Dive | [observability/kubernetes_observability.md](observability/kubernetes_observability.md) | ✅ Control plane / workloads / metrics, logs, traces |
| 22 | Messaging & Kafka Observability | [observability/messaging_kafka_observability.md](observability/messaging_kafka_observability.md) | ✅ Kafka 4.3 / lag / freshness / tracing |
| 23 | API & HTTP Observability | [observability/api_http_observability.md](observability/api_http_observability.md) | ✅ RED / latency / retries / tracing |
| 24 | Frontend & Real User Monitoring | [observability/frontend_rum_observability.md](observability/frontend_rum_observability.md) | ✅ Core Web Vitals / browser / privacy |
| 25 | Mobile App Observability | [observability/mobile_app_observability.md](observability/mobile_app_observability.md) | ✅ Android/iOS / crash / startup / network |
| 26 | Serverless & Functions Observability | [observability/serverless_functions_observability.md](observability/serverless_functions_observability.md) | ✅ Lifecycle / cold start / retries / cost |
| 27 | LLM & Generative AI Observability | [observability/llm_generative_ai_observability.md](observability/llm_generative_ai_observability.md) | ✅ Model / RAG / agents / evaluation / safety |
| 28 | Data Pipeline & ETL Observability | [observability/data_pipeline_etl_observability.md](observability/data_pipeline_etl_observability.md) | ✅ Freshness / quality / lineage / backfill |
| 29 | Machine Learning Model Observability | [observability/machine_learning_model_observability.md](observability/machine_learning_model_observability.md) | ✅ Serving / drift / ground truth / fairness |
| 30 | Security Observability & Detection Engineering | [observability/security_observability_detection_engineering.md](observability/security_observability_detection_engineering.md) | ✅ Audit / detection-as-code / SIEM / evidence |
| 31 | Network Observability & Traffic Analysis | [observability/network_observability_traffic_analysis.md](observability/network_observability_traffic_analysis.md) | ✅ DNS / TCP / TLS / flows / probes |
| 32 | CI/CD & Software Delivery Observability | [observability/cicd_software_delivery_observability.md](observability/cicd_software_delivery_observability.md) | ✅ Value stream / DORA / provenance / rollout |
| 33 | Change, Configuration & Feature Flag Observability | [observability/change_configuration_feature_flag_observability.md](observability/change_configuration_feature_flag_observability.md) | ✅ Drift / effective state / evaluation / exposure |
| 34 | Business & Product Observability | [observability/business_product_observability.md](observability/business_product_observability.md) | ✅ Journey / outcome / business SLO / unit economics |
| 35 | Multi-Tenant & SaaS Observability | [observability/multi_tenant_saas_observability.md](observability/multi_tenant_saas_observability.md) | ✅ Isolation / fairness / noisy neighbor / tenant experience |
| 36 | Cloud Cost & Sustainability Observability | [observability/cloud_cost_sustainability_observability.md](observability/cloud_cost_sustainability_observability.md) | ✅ FOCUS / allocation / unit cost / SCI |
| 37 | Capacity Planning & Performance Efficiency | [observability/capacity_planning_performance_efficiency.md](observability/capacity_planning_performance_efficiency.md) | ✅ Demand / headroom / load test / autoscaling |
| 38 | Storage & Object Storage Observability | [observability/storage_object_storage_observability.md](observability/storage_object_storage_observability.md) | ✅ Durability / integrity / rebuild / restore |
| 39 | Search & Indexing Observability | [observability/search_indexing_observability.md](observability/search_indexing_observability.md) | ✅ Freshness / shards / query / relevance |

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
  → telemetry_governance_finops
  → chaos_engineering_observability
  → observability_platform_engineering
  → incident_response_observability
  → database_observability_performance
  → redis_cache_observability
  → kubernetes_observability
  → messaging_kafka_observability
  → api_http_observability
  → frontend_rum_observability
  → mobile_app_observability
  → serverless_functions_observability
  → llm_generative_ai_observability
  → data_pipeline_etl_observability
  → machine_learning_model_observability
  → security_observability_detection_engineering
  → network_observability_traffic_analysis
  → cicd_software_delivery_observability
  → change_configuration_feature_flag_observability
  → business_product_observability
  → multi_tenant_saas_observability
  → cloud_cost_sustainability_observability
  → capacity_planning_performance_efficiency
  → storage_object_storage_observability
  → search_indexing_observability
```

---

*Cập nhật lần cuối: 2026-07-30*
