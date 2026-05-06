# Tổng Hợp Kiến Thức Elasticsearch – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## Tổng Quan

**Elasticsearch** là distributed search & analytics engine dựa trên Apache Lucene. Sử dụng cho full-text search, log analytics (ELK stack), APM, và SIEM.

```
Data → Logstash/Beats/Ingest Pipeline → Elasticsearch Cluster → Kibana
                                              ↓
                                    Search API / Aggregations
```

---

## Danh Sách Sub-Topics

| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Architecture & Cluster | `fundamentals/architecture.md` | ✅ |
| 2 | Indexing, Mapping & Analyzers | `fundamentals/indexing_mapping.md` | ✅ |
| 3 | Query DSL – Search | `fundamentals/query_dsl.md` | ✅ |
| 4 | Aggregations | `advanced/aggregations.md` | ✅ |
| 5 | Performance & Optimization | `performance/optimization.md` | ✅ |
| 6 | Cluster Management & Operations | `operations/cluster_management.md` | ✅ |
| 7 | Security | `operations/security.md` | ✅ |

---

## Learning Path

```
Cơ bản:   architecture → indexing_mapping → query_dsl
Trung cấp: aggregations → optimization
Nâng cao:  cluster_management → security
```

---

*Cập nhật lần cuối: 2026-05-06*
