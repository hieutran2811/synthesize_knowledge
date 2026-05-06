# Docker Image Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Container Image Security Model

### What – Image Security là gì?
**Image security** đảm bảo container images không chứa vulnerabilities, malware, hoặc misconfiguration, và image được build từ trusted sources, không bị tamper.

### How – Attack Surface của Container Image

```
Container Image Attack Surface:
├── Base OS layer      → outdated packages, known CVEs
├── Runtime layer      → JVM/Node/Python vulnerabilities
├── Dependencies       → npm/pip/maven packages (supply chain)
├── Application code   → hardcoded secrets, SQL injection
├── Dockerfile config  → root user, privileged ports, no health check
└── Registry           → unauthorized access, image tampering
```

---

## 2. Vulnerability Scanning

### What – CVE Scanning là gì?
**CVE (Common Vulnerabilities and Exposures) scanning** phân tích image layers để tìm packages có known security vulnerabilities trong databases (NVD, OSV, GitHub Advisory).

### How – Trivy (Aqua Security)

```bash
# Cài Trivy
brew install trivy                   # macOS
apt-get install trivy                # Ubuntu

# Scan Docker image
trivy image nginx:alpine
trivy image myapp:latest

# Chỉ HIGH và CRITICAL
trivy image --severity HIGH,CRITICAL myapp:latest

# JSON output (cho CI/CD)
trivy image --format json \
  --output scan-report.json \
  myapp:latest

# SARIF format (GitHub Security tab)
trivy image --format sarif \
  --output trivy-results.sarif \
  myapp:latest

# Exit code 1 nếu tìm thấy CRITICAL (CI gate)
trivy image --exit-code 1 \
  --severity CRITICAL \
  myapp:latest || {
    echo "Critical vulnerabilities found!"
    exit 1
  }

# Scan Dockerfile (config issues)
trivy config Dockerfile

# Scan filesystem (không cần build image)
trivy fs --scanners vuln,secret .

# Scan IaC files
trivy config ./k8s/
trivy config ./terraform/

# Ignore specific CVEs (có risk acceptance)
cat trivy-ignore.txt
# CVE-2023-1234  # Accepted risk: no fix available, not exploitable in our context
trivy image --ignorefile ./trivy-ignore.txt myapp:latest

# Scan với offline database (air-gapped environment)
trivy image --skip-update --offline-scan myapp:latest
```

### How – Grype (Anchore)

```bash
# Cài Grype
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh

# Scan image
grype myapp:latest

# Chỉ HIGH+ và fail
grype --fail-on high myapp:latest

# Scan SBOM (nhanh hơn, không cần pull image)
syft myapp:latest -o spdx-json > sbom.json
grype sbom:./sbom.json

# JSON output
grype -o json myapp:latest > grype-report.json
```

### How – Docker Scout

```bash
# Docker Scout (tích hợp Docker Desktop & Hub)
docker scout cves myapp:latest       # scan vulnerabilities
docker scout quickview myapp:latest  # overview nhanh
docker scout recommendations myapp:latest  # gợi ý base image tốt hơn

# Compare 2 images
docker scout compare myapp:v1 myapp:v2

# Trong CI/CD
docker scout cves \
  --format sarif \
  --output results.sarif \
  --exit-code \
  myapp:latest
```

---

## 3. Image Signing & Verification

### What – Image Signing là gì?
**Image signing** đảm bảo image không bị tamper giữa lúc build và deploy. Ai đó có thể verify rằng image đến từ trusted builder.

### How – Cosign (Sigstore)

```bash
# Cài cosign
brew install cosign

# ── Key-based signing ──────────────────────────────────────────
# Tạo key pair
cosign generate-key-pair
# → cosign.key (private, giữ bí mật)
# → cosign.pub (public, chia sẻ để verify)

# Ký image (sau khi push)
cosign sign --key cosign.key myrepo/myapp:1.0
# Signature lưu trong registry: myrepo/myapp:sha256-<digest>.sig

# Verify
cosign verify --key cosign.pub myrepo/myapp:1.0

# ── Keyless signing (Sigstore OIDC) ───────────────────────────
# Không cần manage keys! Dùng OIDC token từ CI/CD
# Identity gắn với CI job identity (GitHub Actions, GitLab CI, GCP...)

cosign sign --yes myrepo/myapp:1.0
# → Mở browser để authenticate (interactive)
# → Trong CI: tự động dùng OIDC token từ GITHUB_TOKEN

# Verify keyless (verify against GitHub Actions identity)
cosign verify \
  --certificate-identity "https://github.com/myorg/myrepo/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  myrepo/myapp:1.0

# ── GitHub Actions workflow ────────────────────────────────────
# .github/workflows/build.yml
# permissions:
#   id-token: write    # cần cho keyless signing
#   packages: write
#
# - uses: sigstore/cosign-installer@v3
# - name: Sign image
#   run: |
#     cosign sign --yes $IMAGE_URI
```

### How – Notation (CNCF)

```bash
# Notation: CNCF project, tích hợp tốt với OCI registries
notation generate-test root.cert    # test certificate
notation sign myrepo/myapp:1.0

# Verify
notation verify myrepo/myapp:1.0

# Policy (enforce verification trước khi pull)
notation policy import policy.json
```

### How – Docker Content Trust (DCT)

```bash
# DCT: dùng Notary v1 để sign Docker Hub images
export DOCKER_CONTENT_TRUST=1
docker pull nginx:alpine             # verify signature khi pull
docker push myrepo/myapp:1.0        # tự động sign khi push

# Tạo keys lần đầu
docker trust key generate mykey
docker trust signer add --key cert.pem mykey myrepo/myapp

# Enforce DCT trên daemon (không pull unsigned)
# /etc/docker/daemon.json:
# { "content-trust": { "mode": "enforced" } }
```

---

## 4. SBOM – Software Bill of Materials

### What – SBOM là gì?
**SBOM** là inventory đầy đủ của tất cả components trong image: OS packages, language libraries, transitive dependencies, licenses. Required by US Executive Order 14028 cho federal software.

### How – Syft (Anchore)

```bash
# Cài syft
brew install syft

# Tạo SBOM từ image
syft myapp:latest                         # terminal output
syft myapp:latest -o spdx-json            # SPDX JSON
syft myapp:latest -o cyclonedx-json       # CycloneDX JSON
syft myapp:latest -o syft-json            # Syft native format

# Lưu vào file
syft myapp:latest -o spdx-json > sbom-spdx.json
syft myapp:latest -o cyclonedx-json > sbom-cdx.json

# Attach SBOM vào image (OCI artifact)
syft myapp:latest -o spdx-json > sbom.spdx.json
cosign attach sbom --sbom sbom.spdx.json myrepo/myapp:1.0

# Scan SBOM cho vulnerabilities
grype sbom:./sbom.spdx.json

# BuildKit tự động SBOM
docker buildx build --sbom=true --push -t myrepo/myapp:1.0 .
docker buildx imagetools inspect myrepo/myapp:1.0 | grep sbom
```

### How – SBOM Formats

| Format | Standard | Adoption |
|--------|----------|----------|
| **SPDX** | Linux Foundation | Government, enterprise |
| **CycloneDX** | OWASP | Security community |
| **SWID** | ISO/IEC | Government |

---

## 5. Supply Chain Security

### What – Supply Chain Attacks là gì?
Attacker compromise upstream dependencies, base images, hoặc build tools để inject malicious code vào images mà developer không biết.

### How – Pinning Strategies

```dockerfile
# ── Base image pinning ────────────────────────────────────────
# BAD: mutable tag
FROM node:20-alpine

# GOOD: pin digest (immutable)
FROM node:20-alpine@sha256:3c9e0df6b4b18a0a34e2b6feac9c5e4c14b5b4a1c7d3af9e12...

# Update digest: check thường xuyên với renovate/dependabot

# ── Dependency pinning ────────────────────────────────────────
# package-lock.json / yarn.lock → commit vào repo
# requirements.txt với version pins
Flask==3.0.2
requests==2.31.0
# KHÔNG dùng Flask>=3.0 (non-deterministic)

# npm: dùng npm ci thay npm install (tôn trọng lockfile)
RUN npm ci --omit=dev
```

### How – Renovate / Dependabot

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
    ignore:
      - dependency-name: "node"
        versions: ["21.x"]          # chỉ LTS

  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "daily"

# Renovate config (renovate.json)
{
  "extends": ["config:base"],
  "packageRules": [
    {
      "matchDepTypes": ["dependencies"],
      "automerge": false,            # security patches: require review
      "matchUpdateTypes": ["patch"],
      "automerge": true              # patch: auto merge
    }
  ]
}
```

### How – Hardened Build Pipeline

```yaml
# GitHub Actions: secure build pipeline
name: Secure Build

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write
  id-token: write           # keyless signing

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # Verify dependencies haven't been tampered
      - name: Audit npm packages
        run: npm audit --audit-level=high

      # Build với BuildKit
      - uses: docker/setup-buildx-action@v3

      - name: Build image
        uses: docker/build-push-action@v5
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
          sbom: true                 # generate SBOM
          provenance: true           # generate provenance

      # Scan for vulnerabilities
      - name: Scan with Trivy
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
          severity: CRITICAL,HIGH
          exit-code: 1
          format: sarif
          output: trivy-results.sarif

      # Upload to GitHub Security tab
      - uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif

      # Sign image (keyless)
      - uses: sigstore/cosign-installer@v3
      - name: Sign image
        run: cosign sign --yes ghcr.io/${{ github.repository }}:${{ github.sha }}
```

---

## 6. Registry Security

### How – Private Registry với Authentication

```bash
# Docker Hub: access tokens thay password
docker login -u myuser --password-stdin <<< "$DOCKER_TOKEN"

# GitHub Container Registry (ghcr.io)
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USER --password-stdin

# AWS ECR: IAM-based (không cần long-lived credentials)
aws ecr get-login-password | docker login \
  --username AWS \
  --password-stdin \
  123456789.dkr.ecr.ap-southeast-1.amazonaws.com

# Kubernetes imagePullSecrets
kubectl create secret docker-registry regcred \
  --docker-server=myregistry.example.com \
  --docker-username=myuser \
  --docker-password=$TOKEN
```

### How – Harbor (Enterprise Registry)

```
Harbor features:
├── Role-based access control (RBAC)
├── Vulnerability scanning (Trivy/Clair built-in)
├── Image signing (Notation/Cosign integration)
├── Replication (multi-registry sync)
├── Proxy cache (mirror Docker Hub)
├── Quota management
├── Audit logging
└── Policy enforcement (block images with CRITICAL CVEs)
```

### Compare – Scanning Tools

| | Trivy | Grype | Docker Scout | Snyk |
|--|-------|-------|-------------|------|
| Open source | ✅ | ✅ | Freemium | Commercial |
| DB update | ~6h | ~1h | Real-time | Real-time |
| Dockerfile scan | ✅ | ❌ | ❌ | ✅ |
| IaC scan | ✅ | ❌ | ❌ | ✅ |
| Secret detection | ✅ | ❌ | ❌ | ✅ |
| License check | ✅ | ✅ | ❌ | ✅ |
| CI integration | Excellent | Good | Good | Excellent |

### Trade-offs
- Digest pinning: secure nhưng phải update thường xuyên; dùng Renovate để automate
- Keyless signing: tiện CI/CD nhưng phụ thuộc Sigstore infrastructure
- Trivy exit-code trong CI: có thể block builds vì false positives hoặc CVEs chưa có fix
- SBOM size: sbom.json có thể lớn (>1MB cho complex apps); compress hoặc attach as OCI artifact

### Real-world Usage
```bash
# Weekly security scan cron job
#!/bin/bash
IMAGES=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>")
for image in $IMAGES; do
  echo "Scanning: $image"
  trivy image --severity HIGH,CRITICAL \
    --format json \
    --output "/reports/$(echo $image | tr '/:' '_').json" \
    "$image"
done

# Pre-deployment gate
trivy image --exit-code 1 --severity CRITICAL myapp:$VERSION || {
  echo "CRITICAL vulnerabilities found. Blocking deployment!"
  notify-slack "#security" "Critical CVE in $VERSION, deployment blocked"
  exit 1
}

# Verify image signature trước khi deploy
cosign verify \
  --certificate-identity-regexp "^https://github.com/myorg/myrepo/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  myrepo/myapp:$VERSION || {
  echo "Image signature verification failed!"
  exit 1
}
```

### Ghi chú – Chủ đề tiếp theo
> Runtime Security – seccomp profiles, AppArmor, capabilities deep dive, gVisor sandboxing

---

*Cập nhật lần cuối: 2026-05-06*
