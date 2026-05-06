# Docker CI/CD Integration – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. CI/CD Pipeline Principles

### What – Docker trong CI/CD là gì?
Docker chuẩn hóa môi trường build/test/deploy, đảm bảo **"build once, deploy anywhere"**: image build 1 lần trong CI, deploy lên dev/staging/prod giống hệt nhau.

### How – Pipeline Stages

```
Code Push
    ↓
Lint & Static Analysis          ← docker run --rm linter:latest
    ↓
Unit Tests                      ← docker compose run --rm app npm test
    ↓
Build Image                     ← docker buildx build --push
    ↓
Vulnerability Scan              ← trivy image myapp:$SHA
    ↓
Integration Tests               ← docker compose -f compose.test.yaml up
    ↓
Push to Registry                ← docker push (ECR/GCR/GHCR)
    ↓
Sign Image                      ← cosign sign
    ↓
Deploy to Staging               ← update service / helm upgrade
    ↓
Smoke Tests                     ← curl /health
    ↓
Deploy to Production            ← manual approval + deploy
```

---

## 2. GitHub Actions

### How – Full Pipeline

```yaml
# .github/workflows/docker-pipeline.yml
name: Docker Build & Deploy

on:
  push:
    branches: [main, develop]
    tags: ['v*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read
  packages: write
  id-token: write          # keyless cosign signing
  security-events: write   # upload SARIF

jobs:
  # ── Test ──────────────────────────────────────────────────
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: testpass
          POSTGRES_DB: testdb
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm test
        env:
          DATABASE_URL: postgresql://postgres:testpass@localhost:5432/testdb

  # ── Build & Scan ───────────────────────────────────────────
  build:
    needs: test
    runs-on: ubuntu-latest
    outputs:
      image-digest: ${{ steps.build.outputs.digest }}
      image-tag: ${{ steps.meta.outputs.tags }}

    steps:
      - uses: actions/checkout@v4

      - name: Docker meta (tags & labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=sha-
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=raw,value=latest,enable={{is_default_branch}}

      - name: Set up QEMU (multi-platform)
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          sbom: true
          provenance: true
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}"
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH
          exit-code: '1'

      - name: Upload Trivy results
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif

      - name: Sign image with cosign
        if: github.event_name != 'pull_request'
        uses: sigstore/cosign-installer@v3
        env:
          COSIGN_EXPERIMENTAL: "true"
      - run: |
          cosign sign --yes \
            "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}"

  # ── Integration Tests ─────────────────────────────────────
  integration-test:
    needs: build
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Run integration tests
        run: |
          export APP_IMAGE="${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}"
          docker compose -f compose.yaml -f compose.test.yaml up \
            --abort-on-container-exit \
            --exit-code-from tests \
            --no-color
        env:
          APP_IMAGE: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}

      - name: Cleanup
        if: always()
        run: docker compose -f compose.yaml -f compose.test.yaml down -v

  # ── Deploy to Staging ──────────────────────────────────────
  deploy-staging:
    needs: integration-test
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to staging
        run: |
          # ECS update
          aws ecs update-service \
            --cluster staging \
            --service myapp \
            --force-new-deployment
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_DEFAULT_REGION: ap-southeast-1

  # ── Deploy to Production ───────────────────────────────────
  deploy-production:
    needs: integration-test
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://myapp.example.com
    steps:
      - name: Deploy to production
        run: |
          echo "Deploying ${{ needs.build.outputs.image-tag }}"
          # kubectl set image deployment/myapp app=$IMAGE
          # hoặc
          # helm upgrade myapp ./charts/myapp --set image.tag=$VERSION
```

---

## 3. GitLab CI

### How – GitLab CI Pipeline

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build
  - scan
  - deploy

variables:
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: "/certs"
  IMAGE_TAG: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

# ── Test ──────────────────────────────────────────────────
test:
  stage: test
  image: node:20-alpine
  services:
    - postgres:16-alpine
  variables:
    POSTGRES_DB: testdb
    POSTGRES_PASSWORD: testpass
    DATABASE_URL: postgresql://postgres:testpass@postgres/testdb
  cache:
    key: $CI_COMMIT_REF_SLUG
    paths:
      - node_modules/
  script:
    - npm ci
    - npm test
  coverage: '/Lines\s*:\s*(\d+\.?\d*)%/'
  artifacts:
    reports:
      junit: junit-report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml

# ── Build ─────────────────────────────────────────────────
build:
  stage: build
  image: docker:24-dind
  services:
    - name: docker:24-dind
      alias: docker
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_VERIFY: 1
    DOCKER_CERT_PATH: $DOCKER_TLS_CERTDIR/client
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker buildx create --use
    - docker buildx build
        --platform linux/amd64,linux/arm64
        --cache-from type=registry,ref=$CI_REGISTRY_IMAGE:cache
        --cache-to type=registry,ref=$CI_REGISTRY_IMAGE:cache,mode=max
        --push
        -t $IMAGE_TAG
        -t $CI_REGISTRY_IMAGE:latest
        .
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

# ── Scan ──────────────────────────────────────────────────
scan:
  stage: scan
  image: aquasec/trivy:latest
  script:
    - trivy image
        --exit-code 1
        --severity CRITICAL
        --format template
        --template "@/contrib/gitlab.tpl"
        --output gl-container-scanning-report.json
        $IMAGE_TAG
  artifacts:
    reports:
      container_scanning: gl-container-scanning-report.json
  allow_failure: false

# ── Deploy ────────────────────────────────────────────────
deploy:staging:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: staging
    url: https://staging.myapp.example.com
  script:
    - kubectl set image deployment/myapp app=$IMAGE_TAG -n staging
    - kubectl rollout status deployment/myapp -n staging
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

deploy:production:
  stage: deploy
  image: bitnami/kubectl:latest
  environment:
    name: production
    url: https://myapp.example.com
  script:
    - kubectl set image deployment/myapp app=$IMAGE_TAG -n production
    - kubectl rollout status deployment/myapp -n production
  when: manual
  rules:
    - if: $CI_COMMIT_TAG
```

---

## 4. Jenkins với Docker

### How – Jenkins Pipeline (Declarative)

```groovy
// Jenkinsfile
pipeline {
    agent {
        docker {
            image 'docker:24-dind'
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    environment {
        REGISTRY = 'myregistry.example.com'
        IMAGE_NAME = 'myapp'
        IMAGE_TAG = "${REGISTRY}/${IMAGE_NAME}:${env.BUILD_NUMBER}"
        DOCKER_CREDENTIALS = credentials('docker-registry-credentials')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test') {
            agent {
                docker {
                    image 'node:20-alpine'
                    reuseNode true
                }
            }
            steps {
                sh 'npm ci'
                sh 'npm test'
            }
            post {
                always {
                    junit 'junit-report.xml'
                }
            }
        }

        stage('Build Image') {
            steps {
                script {
                    docker.withRegistry("https://${REGISTRY}", 'docker-registry-credentials') {
                        def image = docker.build("${IMAGE_NAME}:${env.BUILD_NUMBER}")
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }

        stage('Scan') {
            steps {
                sh """
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest image \
                      --exit-code 1 \
                      --severity CRITICAL \
                      ${IMAGE_TAG}
                """
            }
        }

        stage('Integration Test') {
            steps {
                sh """
                    export APP_IMAGE=${IMAGE_TAG}
                    docker compose -f compose.test.yaml up \
                      --abort-on-container-exit \
                      --exit-code-from tests
                """
            }
            post {
                always {
                    sh 'docker compose -f compose.test.yaml down -v'
                }
            }
        }

        stage('Deploy Staging') {
            when {
                branch 'develop'
            }
            steps {
                withKubeConfig([credentialsId: 'kubeconfig-staging']) {
                    sh "kubectl set image deployment/myapp app=${IMAGE_TAG} -n staging"
                    sh "kubectl rollout status deployment/myapp -n staging"
                }
            }
        }

        stage('Deploy Production') {
            when {
                tag 'v*'
            }
            input {
                message "Deploy to production?"
                ok "Deploy"
                parameters {
                    string(name: 'APPROVER', defaultValue: '', description: 'Your name')
                }
            }
            steps {
                withKubeConfig([credentialsId: 'kubeconfig-prod']) {
                    sh "kubectl set image deployment/myapp app=${IMAGE_TAG} -n production"
                    sh "kubectl rollout status deployment/myapp -n production --timeout=5m"
                }
            }
        }
    }

    post {
        failure {
            slackSend(
                channel: '#alerts',
                color: 'danger',
                message: "Build ${env.BUILD_NUMBER} FAILED: ${env.JOB_NAME} - ${env.BUILD_URL}"
            )
        }
        success {
            slackSend(
                channel: '#deployments',
                color: 'good',
                message: "Deployed ${IMAGE_TAG} to ${env.BRANCH_NAME}"
            )
        }
        always {
            cleanWs()
        }
    }
}
```

---

## 5. Image Tagging Strategy trong CI/CD

### How – Semantic Versioning + Git SHA

```bash
# Strategy: dùng nhiều tags cho cùng 1 image

# Trong CI pipeline (bất kể tool nào)
GIT_SHA=$(git rev-parse --short HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
VERSION=$(cat VERSION || echo "0.0.0")

# Tags:
IMAGE_BASE="myrepo/myapp"

# Always tag với SHA (unique, traceable)
docker tag myapp $IMAGE_BASE:sha-$GIT_SHA

# Branch tag (mutable)
docker tag myapp $IMAGE_BASE:$BRANCH

# Version tags (chỉ khi có git tag)
if [[ "$CI_COMMIT_TAG" =~ ^v[0-9] ]]; then
    SEMVER="${CI_COMMIT_TAG#v}"
    MAJOR="${SEMVER%%.*}"
    MINOR="${SEMVER%.*}"; MINOR="${MINOR#*.}"
    
    docker tag myapp $IMAGE_BASE:$SEMVER
    docker tag myapp $IMAGE_BASE:$MAJOR.$MINOR
    docker tag myapp $IMAGE_BASE:$MAJOR
    docker tag myapp $IMAGE_BASE:latest
fi

# Push all tags
docker push --all-tags $IMAGE_BASE
```

### How – Rollback Strategy

```bash
# Deploy với version tracking
deploy() {
    local IMAGE_TAG=$1
    local ENVIRONMENT=$2

    echo "Deploying $IMAGE_TAG to $ENVIRONMENT..."
    
    # Save current version (for rollback)
    CURRENT=$(kubectl get deployment myapp -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "$CURRENT" > /tmp/previous-image.txt

    # Deploy
    kubectl set image deployment/myapp app=$IMAGE_TAG -n $ENVIRONMENT
    
    # Wait and verify
    if ! kubectl rollout status deployment/myapp -n $ENVIRONMENT --timeout=5m; then
        echo "Deployment failed! Rolling back..."
        kubectl rollout undo deployment/myapp -n $ENVIRONMENT
        exit 1
    fi
    
    echo "Deployment successful!"
}

# Rollback
rollback() {
    local ENVIRONMENT=$1
    kubectl rollout undo deployment/myapp -n $ENVIRONMENT
    # hoặc rollback về version cụ thể
    kubectl set image deployment/myapp app=$(cat /tmp/previous-image.txt) -n $ENVIRONMENT
}
```

---

## 6. Docker Build Optimization trong CI

### How – Cache Strategies

```yaml
# GitHub Actions: GHA Cache (nhanh nhất, miễn phí)
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max

# Registry Cache (portable, tốt cho self-hosted runners)
- uses: docker/build-push-action@v5
  with:
    cache-from: type=registry,ref=myrepo/myapp:buildcache
    cache-to: type=registry,ref=myrepo/myapp:buildcache,mode=max

# Local Cache (chỉ cho single runner)
- uses: docker/build-push-action@v5
  with:
    cache-from: type=local,src=/tmp/.buildx-cache
    cache-to: type=local,dest=/tmp/.buildx-cache-new,mode=max
# → sau đó move cache để tránh cache bloat
- name: Move cache
  run: |
    rm -rf /tmp/.buildx-cache
    mv /tmp/.buildx-cache-new /tmp/.buildx-cache
```

### Compare – CI/CD Platforms

| | GitHub Actions | GitLab CI | Jenkins | CircleCI |
|--|---------------|----------|---------|---------|
| Hosting | Cloud (free tier) | Cloud/Self | Self-hosted | Cloud |
| Docker support | Native | DinD / socket | Plugin | Executor |
| Cache | GHA cache | Registry | Custom | Layer cache |
| Secret management | GitHub Secrets | GitLab Secrets | Credentials | CircleCI ctx |
| Matrix builds | ✅ | ✅ | Parallel stages | ✅ |
| Price | Free 2000 min/mo | Free 400 min/mo | Free (self-host) | Free 6000 min/mo |

### Trade-offs
- Docker socket mounting trong CI: tiện nhưng security risk (privileged access)
- DinD: isolated nhưng chậm hơn, cần privileged container
- Kaniko: secure (no daemon) nhưng không cache local, chỉ registry cache
- GHA cache: fast hit rate nhưng size limit 10GB per repo

### Real-world Usage
```bash
# Cleanup registry (xóa images cũ)
# GitHub: bật "Delete old images" trong package settings
# ECR lifecycle policy:
aws ecr put-lifecycle-policy \
  --repository-name myapp \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 30 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["sha-"],
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": {"type": "expire"}
    }]
  }'

# Verify deployed image
kubectl get deployment myapp -o jsonpath='{.spec.template.spec.containers[0].image}'
cosign verify --certificate-oidc-issuer https://token.actions.githubusercontent.com myapp:$VERSION
```

### Ghi chú – Chủ đề tiếp theo
> Performance Tuning – JVM heap trong containers, OOM tuning, CPU pinning, I/O optimization

---

*Cập nhật lần cuối: 2026-05-06*
