# Roadmap Tổng Hợp Kiến Thức Kubernetes

## Cấu trúc thư mục
```
kubernetes/
├── roadmap.md                          ← file này
├── kubernetes_knowledge.md             ← overview tổng quan (10 topics)
├── workloads/                          ← Workloads deep dive
│   └── workloads_deep.md              ← Deployment strategies, StatefulSet patterns, Job/CronJob
├── networking/                         ← Networking deep dive
│   └── networking_deep.md             ← CNI (Calico/Cilium/eBPF), Gateway API, Service Mesh
├── storage/                            ← Storage deep dive
│   └── storage_deep.md               ← CSI drivers, Velero backup, Volume Snapshots
├── security/                           ← Security deep dive
│   └── rbac_deep.md                  ← RBAC audit, OPA Gatekeeper, Kyverno policies
├── observability/                      ← Observability deep dive
│   └── monitoring_deep.md            ← Prometheus stack, Grafana, OpenTelemetry
├── helm/                               ← Helm deep dive
│   └── helm_deep.md                  ← Chart authoring, Helm hooks, OCI registries
├── gitops/                             ← GitOps deep dive
│   └── argocd_gitops.md              ← ApplicationSet, multi-cluster, Flux, image updater
├── scaling/                            ← Autoscaling deep dive
│   └── autoscaling_deep.md           ← VPA, Cluster Autoscaler, Karpenter
└── production/                         ← Production patterns deep dive
    └── production_patterns.md         ← Canary deployments, zero-downtime, multi-tenancy
```

---

## Mục lục đã hoàn thành ✅

### Tổng quan (Overview)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | K8s Architecture – control plane, worker nodes, etcd, scheduler, controller-manager | kubernetes_knowledge.md | ✅ |
| 2 | Workloads – Deployment, StatefulSet, DaemonSet, Job, CronJob lifecycle | kubernetes_knowledge.md | ✅ |
| 3 | Services & Networking – ClusterIP, NodePort, LoadBalancer, Headless, Ingress | kubernetes_knowledge.md | ✅ |
| 4 | Storage – PV/PVC/StorageClass, CSI drivers, dynamic provisioning | kubernetes_knowledge.md | ✅ |
| 5 | RBAC & Security – Role/ClusterRole, ServiceAccount, Pod Security Standards | kubernetes_knowledge.md | ✅ |
| 6 | Helm – chart structure, values, templating, release management | kubernetes_knowledge.md | ✅ |
| 7 | GitOps & ArgoCD – ApplicationSet, sync policies, multi-cluster | kubernetes_knowledge.md | ✅ |
| 8 | Autoscaling – HPA, VPA, KEDA, Cluster Autoscaler | kubernetes_knowledge.md | ✅ |
| 9 | Observability – kube-state-metrics, Prometheus, alerting, OpenTelemetry | kubernetes_knowledge.md | ✅ |
| 10 | Production Patterns – PDB, TopologySpread, ResourceQuota, LimitRange | kubernetes_knowledge.md | ✅ |

---

## Đã hoàn thành ✅

### Workloads Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 11.1 | Workloads Deep – blue-green/canary strategies, StatefulSet ordering, Job parallelism patterns | workloads/workloads_deep.md | ✅ |

### Networking Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 12.1 | Networking Deep – CNI (Calico/Cilium), eBPF dataplane, Gateway API, NetworkPolicy advanced | networking/networking_deep.md | ✅ |

### Storage Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | Storage Deep – CSI driver internals, Velero backup/restore, Volume Snapshots, ReadWriteMany | storage/storage_deep.md | ✅ |

### Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14.1 | RBAC & Policy Deep – RBAC audit (rbac-tool), OPA Gatekeeper, Kyverno admission policies | security/rbac_deep.md | ✅ |

### Observability Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 15.1 | Monitoring Deep – kube-prometheus-stack, Grafana dashboards, OpenTelemetry Collector, tracing | observability/monitoring_deep.md | ✅ |

### Helm Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 16.1 | Helm Deep – Chart authoring best practices, Helm hooks, library charts, OCI registry, helmfile | helm/helm_deep.md | ✅ |

### GitOps Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 17.1 | ArgoCD & GitOps Deep – ApplicationSet generators, multi-cluster, Flux comparison, image updater | gitops/argocd_gitops.md | ✅ |

### Autoscaling Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 18.1 | Autoscaling Deep – VPA admission controller, Cluster Autoscaler tuning, Karpenter NodePool | scaling/autoscaling_deep.md | ✅ |

### Production Patterns Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 19.1 | Production Patterns – canary với Argo Rollouts, zero-downtime deploy, multi-tenancy (namespace isolation) | production/production_patterns.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã có nội dung
- 🔄 Đang làm
- ⬜ Chưa làm
