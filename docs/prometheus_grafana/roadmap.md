---
title: "Roadmap – Prometheus & Grafana Knowledge"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Roadmap – Prometheus & Grafana Knowledge

> Thuật ngữ: [Glossary](glossary.md).

> Đã chuẩn hóa **39/39 chủ đề**. Baseline hiện tại: **Prometheus 3.13.x**, **Grafana 13.1.x**, **Mimir 3.1.x**, **OpenTelemetry Java 1.64.x / Collector 0.157.x / Semantic Conventions 1.43.x**, **Pyroscope 2.2.x**, **PostgreSQL 18**, **MySQL 8.4 LTS**, **Redis Open Source 8.x**, **Apache Kafka 4.3.x**, **Apache Airflow 3.3.x**, **Apache Spark 4.2.x**, **OpenLineage 1.50.x**, **MLflow 3.x**, **Blackbox Exporter 0.28.x**, tài liệu **Kubernetes 1.36 stable/multi-tenancy/autoscaling/CSI**, **KEDA 2.20**, Elastic/OpenSearch/Ceph hiện hành, NIST CSF 2.0, NIST Privacy Framework, MITRE ATT&CK v18, OCSF, **SLSA 1.2**, **CDEvents 0.5.0**, **FOCUS 1.4**, **SCI 1.1 / ISO/IEC 21031:2024**, W3C Trace Context, FinOps Unit Economics/Sustainability, OpenFeature/OpenGitOps và OpenTelemetry FaaS/GenAI/CI-CD/feature-flag/session/object-store/Elasticsearch conventions hiện hành, Core Web Vitals, Android Vitals và Apple MetricKit hiện hành, **bpftrace 0.24**, **Cilium/Hubble 1.20.x** và **OBI 0.10**.

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
| 13 | eBPF Observability Deep Dive | [observability/ebpf_observability.md](observability/ebpf_observability.md) | ✅ bpftrace 0.24 / Cilium 1.20 / OBI 0.10 | Nâng cao |
| 14 | Grafana Mimir Deep Dive | [observability/grafana_mimir.md](observability/grafana_mimir.md) | ✅ Mimir 3.1 / ingest storage | Nâng cao |
| 15 | Telemetry Governance & FinOps | [observability/telemetry_governance_finops.md](observability/telemetry_governance_finops.md) | ✅ Data contracts / cost governance | Nâng cao |
| 16 | Chaos Engineering for Observability | [observability/chaos_engineering_observability.md](observability/chaos_engineering_observability.md) | ✅ Chaos experiments / pipeline resilience | Nâng cao |
| 17 | Observability Platform Engineering | [observability/observability_platform_engineering.md](observability/observability_platform_engineering.md) | ✅ Self-service / control plane / platform SLOs | Nâng cao |
| 18 | Incident Response with Observability | [observability/incident_response_observability.md](observability/incident_response_observability.md) | ✅ Incident command / evidence / postmortems | Nâng cao |
| 19 | Database Observability & Performance Engineering | [observability/database_observability_performance.md](observability/database_observability_performance.md) | ✅ PostgreSQL 18 / MySQL 8.4 / query performance | Nâng cao |
| 20 | Redis & Cache Observability | [observability/redis_cache_observability.md](observability/redis_cache_observability.md) | ✅ Redis 8.x / cache correctness / failure modes | Nâng cao |
| 21 | Kubernetes Observability Deep Dive | [observability/kubernetes_observability.md](observability/kubernetes_observability.md) | ✅ Control plane / workloads / signals | Nâng cao |
| 22 | Messaging & Kafka Observability | [observability/messaging_kafka_observability.md](observability/messaging_kafka_observability.md) | ✅ Kafka 4.3 / freshness / delivery semantics | Nâng cao |
| 23 | API & HTTP Observability | [observability/api_http_observability.md](observability/api_http_observability.md) | ✅ RED / latency / retries / tracing | Nâng cao |
| 24 | Frontend & Real User Monitoring | [observability/frontend_rum_observability.md](observability/frontend_rum_observability.md) | ✅ Core Web Vitals / browser / privacy | Nâng cao |
| 25 | Mobile App Observability | [observability/mobile_app_observability.md](observability/mobile_app_observability.md) | ✅ Android/iOS / crash / startup / network | Nâng cao |
| 26 | Serverless & Functions Observability | [observability/serverless_functions_observability.md](observability/serverless_functions_observability.md) | ✅ Lifecycle / cold start / retries / cost | Nâng cao |
| 27 | LLM & Generative AI Observability | [observability/llm_generative_ai_observability.md](observability/llm_generative_ai_observability.md) | ✅ Model / RAG / agents / evaluation / safety | Nâng cao |
| 28 | Data Pipeline & ETL Observability | [observability/data_pipeline_etl_observability.md](observability/data_pipeline_etl_observability.md) | ✅ Freshness / quality / lineage / backfill | Nâng cao |
| 29 | Machine Learning Model Observability | [observability/machine_learning_model_observability.md](observability/machine_learning_model_observability.md) | ✅ Serving / drift / ground truth / fairness | Nâng cao |
| 30 | Security Observability & Detection Engineering | [observability/security_observability_detection_engineering.md](observability/security_observability_detection_engineering.md) | ✅ Audit / detection-as-code / SIEM / evidence | Nâng cao |
| 31 | Network Observability & Traffic Analysis | [observability/network_observability_traffic_analysis.md](observability/network_observability_traffic_analysis.md) | ✅ DNS / TCP / TLS / flows / probes | Nâng cao |
| 32 | CI/CD & Software Delivery Observability | [observability/cicd_software_delivery_observability.md](observability/cicd_software_delivery_observability.md) | ✅ Value stream / DORA / provenance / rollout | Nâng cao |
| 33 | Change, Configuration & Feature Flag Observability | [observability/change_configuration_feature_flag_observability.md](observability/change_configuration_feature_flag_observability.md) | ✅ Drift / effective state / evaluation / exposure | Nâng cao |
| 34 | Business & Product Observability | [observability/business_product_observability.md](observability/business_product_observability.md) | ✅ Journey / outcome / business SLO / unit economics | Nâng cao |
| 35 | Multi-Tenant & SaaS Observability | [observability/multi_tenant_saas_observability.md](observability/multi_tenant_saas_observability.md) | ✅ Isolation / fairness / noisy neighbor / tenant experience | Nâng cao |
| 36 | Cloud Cost & Sustainability Observability | [observability/cloud_cost_sustainability_observability.md](observability/cloud_cost_sustainability_observability.md) | ✅ FOCUS / allocation / unit cost / SCI | Nâng cao |
| 37 | Capacity Planning & Performance Efficiency | [observability/capacity_planning_performance_efficiency.md](observability/capacity_planning_performance_efficiency.md) | ✅ Demand / headroom / load test / autoscaling | Nâng cao |
| 38 | Storage & Object Storage Observability | [observability/storage_object_storage_observability.md](observability/storage_object_storage_observability.md) | ✅ Durability / integrity / rebuild / restore | Nâng cao |
| 39 | Search & Indexing Observability | [observability/search_indexing_observability.md](observability/search_indexing_observability.md) | ✅ Freshness / shards / query / relevance | Nâng cao |

## Learning Path

```text
Prometheus core:
  1 → 2 → 3 → 4

Visualization:
  5 → 6 → 7

Observability design:
  8 → 9 → 10

Observability engineering mở rộng:
  10 → 11 → 12 → 13 → 14 → 15 → 16 → 17 → 18 → 19 → 20 → 21 → 22 → 23 → 24 → 25 → 26 → 27 → 28 → 29 → 30 → 31 → 32 → 33 → 34 → 35 → 36 → 37 → 38 → 39
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
| Telemetry contracts, ownership, privacy, cardinality budgets, showback/chargeback và unit economics | [telemetry_governance_finops.md](observability/telemetry_governance_finops.md) |
| Chaos experiments, pipeline SLO, synthetic canaries, data-loss detection, degraded modes và DR exercises | [chaos_engineering_observability.md](observability/chaos_engineering_observability.md) |
| Self-service onboarding, golden paths, catalog, control plane, multi-tenancy và platform SLOs | [observability_platform_engineering.md](observability/observability_platform_engineering.md) |
| Incident command, triage, evidence timeline, telemetry debugging, communication và postmortem learning | [incident_response_observability.md](observability/incident_response_observability.md) |
| Database workload, connection pools, query tracing, locks, plans, WAL/replication và capacity | [database_observability_performance.md](observability/database_observability_performance.md) |
| Cache correctness, client latency, hit/miss, eviction, memory, persistence, replication và Cluster | [redis_cache_observability.md](observability/redis_cache_observability.md) |
| Kubernetes control plane, workload state, node/runtime, metrics, Events, logs, traces và audit | [kubernetes_observability.md](observability/kubernetes_observability.md) |
| Kafka producer/broker/consumer, lag, freshness, delivery semantics, retry, DLQ và tracing | [messaging_kafka_observability.md](observability/messaging_kafka_observability.md) |
| HTTP request lifecycle, RED, histograms, deadlines, retries, gateways và trace propagation | [api_http_observability.md](observability/api_http_observability.md) |
| Core Web Vitals, browser performance, JavaScript errors, RUM, synthetic và privacy | [frontend_rum_observability.md](observability/frontend_rum_observability.md) |
| Android/iOS crash, ANR/hang, startup, rendering, network, offline sync và device fragmentation | [mobile_app_observability.md](observability/mobile_app_observability.md) |
| Function lifecycle, cold start, concurrency, throttling, retry, DLQ, tracing và cost | [serverless_functions_observability.md](observability/serverless_functions_observability.md) |
| Model calls, tokens, TTFT, RAG, agents, evaluations, safety, privacy và cost | [llm_generative_ai_observability.md](observability/llm_generative_ai_observability.md) |
| Data freshness, completeness, quality, lineage, orchestration, backfill và warehouse cost | [data_pipeline_etl_observability.md](observability/data_pipeline_etl_observability.md) |
| Model serving, feature health, drift, ground truth, quality, fairness và retraining | [machine_learning_model_observability.md](observability/machine_learning_model_observability.md) |
| Audit, identity, security schema, detection-as-code, SIEM, evidence và response automation | [security_observability_detection_engineering.md](observability/security_observability_detection_engineering.md) |
| DNS, routing, TCP/UDP/QUIC, TLS, load balancing, flows, probes và packet analysis | [network_observability_traffic_analysis.md](observability/network_observability_traffic_analysis.md) |
| Commit-to-production flow, pipeline, artifact, progressive delivery, DORA và supply-chain evidence | [cicd_software_delivery_observability.md](observability/cicd_software_delivery_observability.md) |
| Desired/observed/effective state, drift, config, feature flag, exposure và cleanup | [change_configuration_feature_flag_observability.md](observability/change_configuration_feature_flag_observability.md) |
| Critical user journey, funnel, outcome, business SLO, experiment, privacy và unit economics | [business_product_observability.md](observability/business_product_observability.md) |
| Tenant identity, telemetry isolation, fairness, noisy neighbor, metering và cost attribution | [multi_tenant_saas_observability.md](observability/multi_tenant_saas_observability.md) |
| Billing/usage allocation, FOCUS, OpenCost, unit cost, energy, carbon intensity và SCI | [cloud_cost_sustainability_observability.md](observability/cloud_cost_sustainability_observability.md) |
| Demand, queueing, saturation, safe headroom, load test, forecasting và autoscaling | [capacity_planning_performance_efficiency.md](observability/capacity_planning_performance_efficiency.md) |
| Block/file/object storage, durability, checksum, replication, rebuild, lifecycle và restore | [storage_object_storage_observability.md](observability/storage_object_storage_observability.md) |
| Indexing freshness, shard/segment/merge, query latency, relevance, vector search và cost | [search_indexing_observability.md](observability/search_indexing_observability.md) |

## Chú thích trạng thái

- ✅ Hoàn thành – đã refactor theo baseline mục tiêu
- 🟡 Đã có nội dung nhưng cần rà soát/version hóa
- 🔄 Đang làm
- ⬜ Chưa làm

*Cập nhật lần cuối: 2026-07-30*

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [Glossary Prometheus & Grafana](glossary.md)
- [Grafana Advanced – Alerting, transformations và observability-as-code](grafana/grafana_advanced.md)
- [Grafana Fundamentals – Từ PromQL đến dashboard điều tra sự cố](grafana/grafana_fundamentals.md)
- [Grafana Production – HA, IAM, security và operations](grafana/grafana_production.md)
- [Alerting Strategy – SLO, burn rate và on-call](observability/alerting_strategy.md)
- [API & HTTP Observability – Từ Request đến Dependency](observability/api_http_observability.md)
- [Business & Product Observability – Từ User Journey đến Business Outcome](observability/business_product_observability.md)
- [Capacity Planning & Performance Efficiency Observability – Từ Demand đến Safe Headroom](observability/capacity_planning_performance_efficiency.md)
- [Change, Configuration & Feature Flag Observability – Từ Desired State đến User Exposure](observability/change_configuration_feature_flag_observability.md)
- [Chaos Engineering for Observability – Kiểm Chứng Pipeline Khi Có Sự Cố](observability/chaos_engineering_observability.md)
- [CI/CD & Software Delivery Observability – Từ Commit đến Production Outcome](observability/cicd_software_delivery_observability.md)
- [Cloud Cost & Sustainability Observability – Từ Usage đến Unit Cost và Carbon Intensity](observability/cloud_cost_sustainability_observability.md)
- [Continuous Profiling – CPU, Memory, Flame Graph, Pyroscope và Parca](observability/continuous_profiling.md)
- [Data Pipeline & ETL Observability – Từ Dữ liệu nguồn đến Dataset đáng tin cậy](observability/data_pipeline_etl_observability.md)
- [Database Observability & Performance Engineering – Từ Workload đến Execution Plan](observability/database_observability_performance.md)
- [eBPF Observability Deep Dive – Kernel Hooks, Network Tracing và Production Safety](observability/ebpf_observability.md)
- [Frontend & Real User Monitoring – Từ Core Web Vitals đến Business Journey](observability/frontend_rum_observability.md)
- [Grafana Mimir Deep Dive – Distributed Metrics, Tenancy và Production Operations](observability/grafana_mimir.md)
- [Incident Response with Observability – Từ Detection đến Continuous Learning](observability/incident_response_observability.md)
- [Kubernetes Observability Deep Dive – Từ Cluster State đến User Impact](observability/kubernetes_observability.md)
- [LLM & Generative AI Observability – Từ Model Call đến Chất lượng và An toàn](observability/llm_generative_ai_observability.md)
- [Machine Learning Model Observability – Từ Training đến Quyết định Production](observability/machine_learning_model_observability.md)
- [Messaging & Kafka Observability – Từ Producer đến Business Outcome](observability/messaging_kafka_observability.md)
- [Metrics Design – RED, USE, Golden Signals và metric contract](observability/metrics_design.md)
- [Mobile App Observability – Từ Crash đến Trải nghiệm trên Thiết bị thật](observability/mobile_app_observability.md)
- [Multi-Tenant & SaaS Observability – Isolation, Fairness và Tenant Experience](observability/multi_tenant_saas_observability.md)
- [Network Observability & Traffic Analysis – Từ DNS đến Packet và Business Impact](observability/network_observability_traffic_analysis.md)
- [Observability Platform Engineering – Self-Service, Golden Paths và Platform SLOs](observability/observability_platform_engineering.md)
- [OpenTelemetry Deep Dive – Instrumentation, Context, Signals và Collector Pipeline](observability/opentelemetry_deep_dive.md)
- [Redis & Cache Observability – Từ Hit Ratio đến Tính đúng đắn](observability/redis_cache_observability.md)
- [Search & Indexing Observability – Từ Source Event đến Relevant Result](observability/search_indexing_observability.md)
- [Security Observability & Detection Engineering – Từ Audit Event đến Incident Evidence](observability/security_observability_detection_engineering.md)
- [Serverless & Functions Observability – Từ Event Source đến Business Outcome](observability/serverless_functions_observability.md)
- [Full Observability Stack – metrics, logs, traces và OpenTelemetry](observability/stack_integration.md)
- [Storage & Object Storage Observability – Durability, Integrity và Recoverability](observability/storage_object_storage_observability.md)
- [Telemetry Governance & FinOps – Data Contracts, Cost và Operational Control](observability/telemetry_governance_finops.md)
- [Prometheus Advanced – PromQL, Recording Rules và Alerting Rules](prometheus/prometheus_advanced.md)
- [Prometheus Fundamentals – Từ `/metrics` đến quyết định vận hành](prometheus/prometheus_fundamentals.md)
- [Prometheus Production – HA, capacity và long-term storage](prometheus/prometheus_production.md)
- [Prometheus Service Discovery và Relabeling – Từ metadata đến scrape target](prometheus/service_discovery.md)
- [Tổng Hợp Kiến Thức Prometheus & Grafana – Thực Chiến](prometheus_grafana_knowledge.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
