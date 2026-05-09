# Roadmap Tổng Hợp Kiến Thức Docker

## Cấu trúc thư mục
```
docker/
├── roadmap.md                      ← file này
├── docker_knowledge.md             ← overview tổng quan (12 topics)
├── basics/                         ← deep dive phần cơ bản
│   ├── images_deep.md              ← layer internals, BuildKit, buildx, image format
│   ├── containers_deep.md          ← lifecycle, cgroups, namespaces thực hành
│   └── networking_deep.md          ← iptables rules, DNS internals, overlay VXLAN
├── compose/                        ← Docker Compose deep dive
│   ├── compose_patterns.md         ← patterns thực tế, multi-env, profiles
│   └── compose_production.md       ← production compose, secrets, health, logging
├── security/                       ← Security deep dive
│   ├── image_security.md           ← scanning, signing, SBOM, supply chain
│   ├── runtime_security.md         ← seccomp, AppArmor, capabilities, rootless
│   └── secrets_management.md       ← Vault, AWS Secrets Manager, Docker secrets
├── production/                     ← Production patterns
│   ├── logging_monitoring.md       ← logging drivers, ELK/EFK, Prometheus, Grafana
│   ├── cicd_integration.md         ← GitHub Actions, Jenkins, GitLab CI patterns
│   └── performance_tuning.md       ← resource limits, JVM in containers, OOM tuning
└── orchestration/                  ← Orchestration
    ├── swarm_advanced.md           ← Swarm networking, secrets, HA setup
    ├── k8s_intro.md               ← Kubernetes so sánh, basic concepts từ Docker
    ├── k8s_advanced.md            ← RBAC, Network Policies, Helm, GitOps (ArgoCD/Flux)
    └── service_mesh.md            ← Istio/Linkerd, mTLS, traffic management, observability
```

---

## Mục lục đã hoàn thành ✅

### Cơ bản (Basic)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Docker Overview – architecture, daemon/client/registry, container vs VM, containerd | docker_knowledge.md | ✅ |
| 2 | Docker Images – Dockerfile, layers, CMD vs ENTRYPOINT, multi-stage, .dockerignore, build cache | docker_knowledge.md | ✅ |
| 3 | Docker Containers – lifecycle, docker run options, exec/logs/stats, health check, restart policies | docker_knowledge.md | ✅ |
| 4 | Volumes & Storage – named volumes, bind mounts, tmpfs, backup/restore strategies | docker_knowledge.md | ✅ |
| 5 | Docker Networking – bridge/host/overlay, DNS, port mapping, network security | docker_knowledge.md | ✅ |

### Trung cấp (Intermediate)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 6 | Docker Compose – YAML syntax đầy đủ, depends_on, profiles, secrets, overrides | docker_knowledge.md | ✅ |
| 7 | Dockerfile Best Practices – base image, layer optimization, security, multi-platform | docker_knowledge.md | ✅ |
| 8 | Registry & Image Management – Docker Hub, ECR, private registry, tagging strategy, signing | docker_knowledge.md | ✅ |

### Nâng cao (Advanced)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 9 | Docker Security – capabilities, seccomp, rootless, non-root user, secrets, scanning | docker_knowledge.md | ✅ |
| 10 | Docker Internals – namespaces, cgroups, OverlayFS, containerd/runc, BuildKit, DinD | docker_knowledge.md | ✅ |
| 11 | Docker trong Production – logging drivers, resource limits, zero-downtime deploy, CI/CD | docker_knowledge.md | ✅ |
| 12 | Docker Swarm – services, stacks, rolling updates, secrets, Swarm vs Kubernetes | docker_knowledge.md | ✅ |

---

### Basics Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | Images Deep Dive – OCI image spec, content-addressable storage, buildx multi-platform, SBOM | basics/images_deep.md | ✅ |
| 13.2 | Containers Deep Dive – cgroup v2 unified hierarchy, namespace manipulation, pivot_root | basics/containers_deep.md | ✅ |
| 13.3 | Networking Deep Dive – iptables DOCKER chains, veth pairs, VXLAN overlay, macvlan use cases | basics/networking_deep.md | ✅ |

### Compose Patterns
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14.1 | Compose Patterns – local dev, testing, staging environments, wait-for scripts | compose/compose_patterns.md | ✅ |
| 14.2 | Compose Production – health checks, blue-green với Traefik/Nginx, secrets management | compose/compose_production.md | ✅ |

### Security Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 15.1 | Image Security – Trivy/Grype scanning, cosign signing, SBOM generation, supply chain security | security/image_security.md | ✅ |
| 15.2 | Runtime Security – seccomp profiles, AppArmor policies, gVisor (sandboxed containers) | security/runtime_security.md | ✅ |
| 15.3 | Secrets Management – Vault Agent Injector, AWS Secrets Manager CSI, external-secrets-operator | security/secrets_management.md | ✅ |

### Production Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 16.1 | Logging & Monitoring – EFK stack, Loki + Promtail, cAdvisor + Prometheus + Grafana dashboards | production/logging_monitoring.md | ✅ |
| 16.2 | CI/CD Integration – GitHub Actions full pipeline, GitLab CI, Jenkins với Docker agent | production/cicd_integration.md | ✅ |
| 16.3 | Performance Tuning – JVM heap trong containers, OOM killer tuning, CPU pinning, I/O optimization | production/performance_tuning.md | ✅ |

### Orchestration
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 17.1 | Docker Swarm Advanced – HA managers, global services, config rotation, network mesh | orchestration/swarm_advanced.md | ✅ |
| 17.2 | Kubernetes Introduction – Pods/Deployments/Services so sánh với Docker concepts | orchestration/k8s_intro.md | ✅ |

---

### Kubernetes & Service Mesh
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 18.1 | Kubernetes Advanced – RBAC, Network Policies, Helm charts, GitOps (ArgoCD/Flux) | orchestration/k8s_advanced.md | ✅ |
| 18.2 | Service Mesh – Istio/Linkerd, mTLS, VirtualService/DestinationRule, Kiali observability | orchestration/service_mesh.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã có nội dung
- 🔄 Đang làm
- ⬜ Chưa làm
