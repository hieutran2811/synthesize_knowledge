# Docker Images – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. OCI Image Specification

### What – OCI Image Spec là gì?
**OCI (Open Container Initiative) Image Specification** là chuẩn mở định nghĩa format của container image, đảm bảo images tương thích giữa Docker, containerd, Podman và các runtime khác.

### How – Cấu trúc OCI Image

```
OCI Image = Image Index + Manifests + Configs + Layers

/var/lib/docker/image/overlay2/
├── imagedb/
│   ├── content/sha256/          ← Image configs (JSON)
│   └── metadata/sha256/         ← Metadata (parent, lastUpdated)
├── layerdb/
│   └── sha256/                  ← Layer chain IDs
└── repositories.json            ← Name → digest mapping

/var/lib/docker/overlay2/        ← Actual layer data
├── <layer-chain-id>/
│   ├── diff/                    ← Filesystem snapshot
│   ├── link                     ← Short ID
│   ├── lower                    ← Parent layers chain
│   └── work/                    ← OverlayFS work dir
```

### How – Image Manifest (JSON)

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:abc123...",
    "size": 7023
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:layer1...",
      "size": 2811600
    },
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:layer2...",
      "size": 1234567
    }
  ]
}
```

### How – Image Config (JSON)

```json
{
  "architecture": "amd64",
  "os": "linux",
  "config": {
    "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
    "Cmd": ["/bin/bash"],
    "ExposedPorts": {"8080/tcp": {}},
    "WorkingDir": "/app",
    "Labels": {"maintainer": "team@example.com"}
  },
  "rootfs": {
    "type": "layers",
    "diff_ids": [
      "sha256:layer1-uncompressed-digest...",
      "sha256:layer2-uncompressed-digest..."
    ]
  },
  "history": [
    {"created_by": "/bin/sh -c #(nop) FROM ubuntu:22.04", "empty_layer": true},
    {"created_by": "/bin/sh -c apt-get update && apt-get install -y curl"}
  ]
}
```

### How – Content-Addressable Storage

```
Mọi object (layer, config, manifest) được lưu theo SHA-256 digest của nội dung:
  digest = sha256(content)
  path   = /var/lib/docker/image/overlay2/imagedb/content/sha256/<digest>

Lợi ích:
├── Deduplication: 2 images dùng cùng layer → chỉ lưu 1 bản
├── Integrity: pull xong verify digest → phát hiện corruption/tampering
└── Immutability: digest không đổi → content không đổi (trustworthy)
```

```bash
# Xem digest của image
docker inspect nginx:alpine | jq '.[0].Id'
docker images --digests nginx

# Pull bằng digest (truly immutable – không bao giờ thay đổi)
docker pull nginx@sha256:abc123def456...

# Verify digest sau khi pull
docker inspect --format '{{.RepoDigests}}' nginx:alpine
```

---

## 2. Image Layers – Internals

### How – OverlayFS Layer Mechanics

```bash
# Xem layer structure của image
docker inspect nginx:alpine | jq '.[0].GraphDriver'
# Output:
# {
#   "Data": {
#     "LowerDir": "/var/lib/docker/overlay2/abc/diff:/var/lib/docker/overlay2/xyz/diff",
#     "MergedDir": "/var/lib/docker/overlay2/container-id/merged",
#     "UpperDir": "/var/lib/docker/overlay2/container-id/diff",
#     "WorkDir": "/var/lib/docker/overlay2/container-id/work"
#   },
#   "Name": "overlay2"
# }

# Xem layers của image
docker history nginx:alpine
# IMAGE         CREATED       CREATED BY                         SIZE
# abc123        2 days ago    /bin/sh -c #(nop) CMD ["nginx"...  0B
# def456        2 days ago    /bin/sh -c #(nop) EXPOSE 80        0B
# ghi789        2 days ago    /bin/sh -c #(nop) STOPSIGNAL SI...  0B
# ...

# Xem actual layer data
ls /var/lib/docker/overlay2/
du -sh /var/lib/docker/overlay2/*/diff | sort -rh | head -10
```

### How – Layer Sharing

```
Image A (node:18-alpine):          Image B (myapp based on node:18-alpine):
├── alpine base layer   ──────────► alpine base layer (SHARED)
├── node runtime layer  ──────────► node runtime layer (SHARED)
└── npm layer           ──────────► npm layer (SHARED)
                                   └── app source layer (UNIQUE to B)

Disk: 3 shared layers chỉ lưu 1 lần dù 2 images cùng dùng
Pull: chỉ download layers chưa có → nhanh hơn
```

```bash
# Xem layer IDs để confirm sharing
docker inspect node:18-alpine | jq '.[0].RootFS.Layers'
docker inspect myapp:latest | jq '.[0].RootFS.Layers'
# Các sha256 giống nhau = shared layers
```

### How – Whiteout Files (Xóa files trong layer)

```
Container xóa file từ layer bên dưới → tạo "whiteout file":
  .wh.<filename>                  ← whiteout: ẩn file
  .wh..wh..opq                    ← opaque whiteout: ẩn toàn bộ directory

Ví dụ: WORKDIR /app tạo directory
       Sau đó rm -rf /app: tạo .wh..wh..opq trong layer mới

Lưu ý: kể cả xóa file, data VẪN tồn tại trong layer cũ!
→ Luôn cleanup trong cùng RUN command để tránh layer bloat
```

---

## 3. BuildKit – Build Engine Nâng Cao

### What – BuildKit là gì?
**BuildKit** (moby/buildkit) là build backend thế hệ mới, thay thế Docker build cũ. Hỗ trợ parallel build, better caching, secret mounts, SSH forwarding và multi-platform.

### How – Kích hoạt BuildKit

```bash
# Phương pháp 1: environment variable
DOCKER_BUILDKIT=1 docker build -t myapp .

# Phương pháp 2: /etc/docker/daemon.json
{ "features": { "buildkit": true } }

# Phương pháp 3: docker buildx (luôn dùng BuildKit)
docker buildx build -t myapp .

# Phương pháp 4: compose (BuildKit mặc định trong Compose v2)
docker compose build
```

### How – BuildKit Features

```dockerfile
# syntax=docker/dockerfile:1.6    ← pin BuildKit frontend version

# ── 1. Secret mount (không để lại trong layers) ───────────────
FROM node:20-alpine
RUN --mount=type=secret,id=npmrc,dst=/root/.npmrc \
    npm install
# Build: docker build --secret id=npmrc,src=$HOME/.npmrc .

# ── 2. SSH forwarding (clone private git repos) ──────────────
FROM alpine
RUN apk add --no-cache git openssh-client
RUN --mount=type=ssh \
    git clone git@github.com:private/repo.git /app
# Build: docker build --ssh default .
# Setup: eval $(ssh-agent); ssh-add ~/.ssh/id_ed25519

# ── 3. Cache mount (package manager cache persistence) ────────
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci
# npm cache persist giữa các builds → rất nhanh

FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download
COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    go build -o /app/server .

# ── 4. Bind mount (không cần COPY để đọc files) ───────────────
RUN --mount=type=bind,source=requirements.txt,target=/requirements.txt \
    pip install --no-cache-dir -r /requirements.txt
```

### How – Parallel Build Stages

```dockerfile
# BuildKit phát hiện và chạy parallel các stages không phụ thuộc nhau

FROM node:20-alpine AS frontend-deps
COPY frontend/package*.json ./
RUN npm ci

FROM node:20-alpine AS backend-deps     # ← chạy SONG SONG với frontend-deps
COPY backend/package*.json ./
RUN npm ci

FROM node:20-alpine AS frontend-build
COPY --from=frontend-deps /node_modules ./node_modules
COPY frontend/ .
RUN npm run build

FROM node:20-alpine AS backend-build    # ← chạy SONG SONG với frontend-build
COPY --from=backend-deps /node_modules ./node_modules
COPY backend/ .
RUN npm run build

FROM nginx:alpine AS final
COPY --from=frontend-build /dist /var/www/html
COPY --from=backend-build /dist /app
```

```bash
# Xem build graph
docker buildx build --progress=plain -t myapp . 2>&1 | grep -E "^\[.*\]"
```

---

## 4. docker buildx – Multi-platform Builds

### What – buildx là gì?
**docker buildx** là CLI plugin cho BuildKit, hỗ trợ build images cho nhiều platforms (amd64, arm64, arm/v7...) từ 1 máy duy nhất qua **QEMU emulation** hoặc **cross-compilation**.

### How – Setup buildx

```bash
# Tạo builder với multi-platform support
docker buildx create --name mybuilder \
  --driver docker-container \
  --driver-opt network=host \
  --bootstrap \
  --use

docker buildx ls                     # list builders
docker buildx inspect mybuilder      # xem platforms hỗ trợ
docker buildx rm mybuilder           # xóa builder

# Kích hoạt QEMU emulation (cho ARM build trên x86)
docker run --privileged --rm tonistiigi/binfmt --install all
```

### How – Build Multi-platform

```bash
# Build + Push (phải push thì mới lưu manifest list được)
docker buildx build \
  --platform linux/amd64,linux/arm64,linux/arm/v7 \
  -t myrepo/myapp:latest \
  --push .

# Build local (chỉ 1 platform, load vào local docker)
docker buildx build \
  --platform linux/amd64 \
  -t myapp:latest \
  --load .

# Build và export ra tar
docker buildx build \
  --platform linux/arm64 \
  -o type=oci,dest=./myapp-arm64.tar .

# Xem manifest list
docker buildx imagetools inspect myrepo/myapp:latest
docker manifest inspect myrepo/myapp:latest | jq '.manifests[].platform'
```

### How – Platform-specific Dockerfile

```dockerfile
# syntax=docker/dockerfile:1.6
FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS builder
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

WORKDIR /app
COPY . .
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -o /app/server .

FROM alpine:3.19
COPY --from=builder /app/server /usr/local/bin/
CMD ["server"]

# $BUILDPLATFORM = platform của máy build (amd64)
# $TARGETPLATFORM = platform của image target (linux/arm64)
# $TARGETOS, $TARGETARCH = os/arch của target
```

### How – Registry Cache (CI/CD Optimization)

```bash
# Export cache lên registry (mode=max: cache tất cả stages)
docker buildx build \
  --cache-from type=registry,ref=myrepo/myapp:cache \
  --cache-to type=registry,ref=myrepo/myapp:cache,mode=max \
  --push \
  -t myrepo/myapp:$GIT_SHA .

# GitHub Actions cache
docker buildx build \
  --cache-from type=gha \
  --cache-to type=gha,mode=max \
  -t myapp:latest .

# Local cache
docker buildx build \
  --cache-from type=local,src=/tmp/buildcache \
  --cache-to type=local,dest=/tmp/buildcache,mode=max \
  -t myapp:latest .
```

---

## 5. SBOM & Attestations

### What – SBOM là gì?
**Software Bill of Materials (SBOM)** là danh sách đầy đủ các components, dependencies, và licenses trong một software artifact (image). Quan trọng cho compliance và supply chain security.

### How – Tạo SBOM với BuildKit

```bash
# Generate SBOM tự động khi build
docker buildx build \
  --sbom=true \
  --provenance=true \
  --push \
  -t myrepo/myapp:latest .

# Xem SBOM của image
docker buildx imagetools inspect \
  --format '{{json .SBOM}}' \
  myrepo/myapp:latest

# Dùng syft để tạo SBOM
syft myapp:latest -o spdx-json > sbom.spdx.json
syft myapp:latest -o cyclonedx-json > sbom.cyclonedx.json

# Grype: scan SBOM
grype sbom:./sbom.spdx.json
```

### How – Provenance Attestation

```bash
# Build với provenance (ghi lại quá trình build)
docker buildx build \
  --provenance=mode=max \
  --push \
  -t myrepo/myapp:latest .

# Verify provenance với cosign
cosign verify-attestation \
  --type slsaprovenance \
  myrepo/myapp:latest

# Xem provenance
docker buildx imagetools inspect \
  --format '{{json .Provenance}}' \
  myrepo/myapp:latest | jq .
```

---

## 6. Image Optimization – Advanced Techniques

### How – Distroless Images

```dockerfile
# Google Distroless: không có shell, package manager, hoặc unnecessary tools
# Chỉ có app + runtime dependencies → surface attack tối thiểu

# Java với Distroless
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY . .
RUN ./mvnw package -DskipTests

FROM gcr.io/distroless/java21-debian12
COPY --from=builder /app/target/app.jar /app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app.jar"]

# Go: static binary → FROM scratch (0MB base!)
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o server .

FROM scratch                         # hoàn toàn rỗng!
COPY --from=builder /app/server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8080
ENTRYPOINT ["/server"]
# Image size: ~5MB (chỉ binary + TLS certs)
```

### How – Layer Squashing

```bash
# Squash tất cả layers thành 1 (giảm size, mất cache granularity)
docker build --squash -t myapp:squashed .

# BuildKit: export flattened
docker buildx build \
  -o type=docker,dest=myapp-flat.tar \
  --no-cache \
  -t myapp:flat .

# Dùng docker-slim để tự động giảm image
docker-slim build \
  --http-probe \
  --show-clogs \
  myapp:latest
# → tạo myapp.slim: thường giảm 30x size
```

### How – Phân tích Image Size với dive

```bash
# dive: phân tích từng layer
dive myapp:latest

# dive output:
# Layer  Size    Command
# ●  0   5.6 MB  FROM alpine:3.19
# ●  1   12.3 MB RUN apk add --no-cache python3
# ●  2   45.2 MB RUN pip install -r requirements.txt
# ●  3   1.2 MB  COPY . /app

# Wasted space: files thêm vào rồi xóa trong layer khác
# Image efficiency score: < 70% = cần tối ưu

# CI check (fail nếu efficiency < 90%)
dive --ci myapp:latest
```

### Compare – Base Image Sizes

| Base Image | Size | Use case |
|-----------|------|---------|
| `ubuntu:22.04` | ~80MB | General purpose, familiar |
| `debian:slim` | ~75MB | Slim Debian |
| `alpine:3.19` | ~7MB | Minimal, musl libc |
| `distroless/java21` | ~200MB | Java production (no shell) |
| `scratch` | 0MB | Static binaries (Go, Rust) |
| `busybox` | ~4MB | Minimal với basic utils |

### Trade-offs
- Distroless: secure nhưng debug khó (không có shell); dùng ephemeral debug container
- Alpine + musl: nhỏ nhưng có thể gây compat issues với glibc-dependent packages
- --squash: giảm size nhưng mất layer sharing → không tiết kiệm khi pull
- BuildKit cache mounts: nhanh nhưng cache không portable giữa CI runners

### Real-world Usage
```bash
# Debug distroless container (K8s)
kubectl debug -it mypod \
  --image=gcr.io/distroless/base:debug \
  --copy-to=debug-pod \
  -- sh

# Phân tích image để tối ưu
docker history --no-trunc myapp:latest  # xem commands đầy đủ
docker inspect myapp:latest | jq '.[0].RootFS.Layers | length'  # số layers

# So sánh size trước/sau tối ưu
docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" | \
  grep myapp | sort
```

### Ghi chú – Chủ đề tiếp theo
> Containers Deep Dive – cgroup v2, namespace manipulation thực hành, pivot_root

---

*Cập nhật lần cuối: 2026-05-06*
