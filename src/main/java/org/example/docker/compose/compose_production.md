# Docker Compose – Production Patterns

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Production Compose Overview

### What – Production Compose là gì?
Docker Compose trong production không phải chỉ là `docker-compose up`. Production patterns bao gồm: **health checks**, **rolling/blue-green deploys**, **secrets management**, **resource limits**, **logging drivers**, và **reverse proxy integration**.

### When – Khi nào dùng Compose ở production?
- Single-host deployments (VPS, bare metal) không cần Kubernetes overhead
- Small teams với 1-5 services
- Staging environments cần mirror production
- Khi Docker Swarm là overkill nhưng cần hơn docker run

---

## 2. Health Checks

### How – Service Health Checks

```yaml
# docker-compose.prod.yml
services:
  order-service:
    image: order-service:${VERSION:-latest}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s       # how often to run check
      timeout: 10s        # max time for check to complete
      retries: 3          # consecutive failures to mark unhealthy
      start_period: 60s   # grace period during startup (don't count failures)
    depends_on:
      postgres:
        condition: service_healthy   # wait until DB is healthy
      redis:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3

  nginx:
    image: nginx:alpine
    healthcheck:
      test: ["CMD", "nginx", "-t"]   # config syntax check
      interval: 30s
      timeout: 5s
      retries: 3
```

```bash
# Check health status
docker compose ps
# NAME              STATUS                   PORTS
# order-service     Up (healthy)             0.0.0.0:8080->8080/tcp
# postgres          Up (healthy)             5432/tcp
# redis             Up (healthy)             6379/tcp

# Wait for healthy in scripts
docker compose up -d
docker compose exec order-service \
  sh -c 'until curl -sf http://localhost:8080/actuator/health; do sleep 2; done'
```

---

## 3. Blue-Green Deployment

### How – Blue-Green với Traefik

```yaml
# docker-compose.traefik.yml
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedByDefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - letsencrypt:/letsencrypt
    networks:
      - proxy

  # Blue deployment (active)
  order-blue:
    image: order-service:${BLUE_VERSION}
    deploy:
      replicas: 2
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.order.rule=Host(`api.example.com`) && PathPrefix(`/orders`)"
      - "traefik.http.routers.order.entrypoints=websecure"
      - "traefik.http.routers.order.tls.certresolver=letsencrypt"
      - "traefik.http.services.order.loadbalancer.server.port=8080"
      - "traefik.http.services.order.loadbalancer.healthcheck.path=/actuator/health"
      - "traefik.http.services.order.loadbalancer.healthcheck.interval=10s"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - proxy
      - backend

  # Green deployment (standby/new version)
  order-green:
    image: order-service:${GREEN_VERSION}
    profiles: ["green"]   # only started when explicitly activated
    deploy:
      replicas: 2
    labels:
      - "traefik.enable=false"   # disabled by default
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    networks:
      - proxy
      - backend

networks:
  proxy:
    external: true
  backend:
    driver: bridge

volumes:
  letsencrypt:
```

```bash
# deploy.sh – Blue-Green switch script
#!/usr/bin/env bash
set -euo pipefail

NEW_VERSION="${1:?Usage: deploy.sh <version>}"
COMPOSE_FILE="docker-compose.traefik.yml"

# Determine current active color
CURRENT=$(docker compose ps --format json | jq -r '.[].Name' | grep -oP 'order-(blue|green)' | head -1 | grep -oP 'blue|green')
if [[ "$CURRENT" == "blue" ]]; then
    NEW_COLOR="green"; OLD_COLOR="blue"
else
    NEW_COLOR="blue"; OLD_COLOR="green"
fi

echo "Deploying version $NEW_VERSION as $NEW_COLOR (replacing $OLD_COLOR)"

# 1. Pull new image
export GREEN_VERSION="$NEW_VERSION"
export BLUE_VERSION="$NEW_VERSION"
docker compose pull "order-${NEW_COLOR}"

# 2. Start new color (with health check)
docker compose --profile "$NEW_COLOR" up -d "order-${NEW_COLOR}"
echo "Waiting for $NEW_COLOR to be healthy..."
timeout 120 bash -c "until docker inspect order-${NEW_COLOR} --format='{{.State.Health.Status}}' | grep -q healthy; do sleep 3; done"

# 3. Switch Traefik to new color
docker compose exec traefik \
    sh -c "traefik healthcheck"  # verify traefik is responsive

# Enable new, disable old via label update
docker label add "traefik.enable=true" "order-${NEW_COLOR}"
docker label add "traefik.enable=false" "order-${OLD_COLOR}"

# 4. Wait and verify
sleep 10
echo "Verifying new deployment..."
curl -sf "https://api.example.com/orders/health" || { echo "Health check failed!"; exit 1; }

# 5. Stop old color
docker compose stop "order-${OLD_COLOR}"
echo "Deployment complete: $NEW_COLOR is now active"
```

### How – Rolling Update với Nginx

```nginx
# nginx/conf.d/upstream.conf
upstream order_service {
    least_conn;
    server order-service-1:8080 max_fails=3 fail_timeout=30s;
    server order-service-2:8080 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

server {
    listen 80;
    server_name api.example.com;

    location /orders {
        proxy_pass http://order_service;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
        proxy_next_upstream error timeout http_503;  # retry on failure
    }
}
```

```yaml
# Rolling update: scale down/up one at a time
services:
  order-service:
    image: order-service:${VERSION}
    deploy:
      replicas: 3
      update_config:
        parallelism: 1          # update 1 at a time
        delay: 10s              # wait between updates
        failure_action: rollback
        order: start-first      # start new before stopping old
      rollback_config:
        parallelism: 1
        delay: 5s
```

---

## 4. Secrets Management

### How – Docker Secrets (Swarm mode)

```bash
# Create secrets
echo "mySecretPassword123" | docker secret create postgres_password -
echo "myJwtSecretKey" | docker secret create jwt_secret -
cat ssl.key | docker secret create ssl_private_key -
```

```yaml
# docker-compose.secrets.yml (requires Swarm mode)
services:
  order-service:
    image: order-service:latest
    secrets:
      - postgres_password
      - jwt_secret
    environment:
      # App reads from /run/secrets/<name>
      DB_PASSWORD_FILE: /run/secrets/postgres_password
      JWT_SECRET_FILE: /run/secrets/jwt_secret

  postgres:
    image: postgres:16-alpine
    secrets:
      - postgres_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password

secrets:
  postgres_password:
    external: true   # must already exist in Swarm
  jwt_secret:
    external: true
```

```java
// Spring Boot: read secret from file (Docker Secrets pattern)
@Configuration
public class SecretsConfig {
    @Bean
    @Primary
    public DataSource dataSource() throws IOException {
        String passwordFile = System.getenv("DB_PASSWORD_FILE");
        String password = passwordFile != null
            ? Files.readString(Path.of(passwordFile)).strip()
            : System.getenv("DB_PASSWORD");  // fallback for local dev

        return DataSourceBuilder.create()
            .url(System.getenv("DB_URL"))
            .username(System.getenv("DB_USER"))
            .password(password)
            .build();
    }
}
```

### How – .env Files (Non-Swarm)

```bash
# .env.prod (never commit to git!)
POSTGRES_PASSWORD=s3cur3P@ssw0rd
JWT_SECRET=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
STRIPE_API_KEY=sk_live_...
```

```yaml
# docker-compose.prod.yml
services:
  order-service:
    env_file:
      - .env.prod    # loads all vars from file
    environment:
      # Override specific vars from .env.prod
      SPRING_PROFILES_ACTIVE: prod
```

```bash
# In CI/CD: use vault or cloud secrets manager
# AWS SSM Parameter Store
aws ssm get-parameter --name /prod/postgres/password --with-decryption \
    --query 'Parameter.Value' --output text > /run/secrets/postgres_password

# HashiCorp Vault
vault kv get -field=password secret/prod/postgres > /run/secrets/postgres_password
```

### How – Docker BuildKit Secrets (Build time)

```dockerfile
# syntax=docker/dockerfile:1
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
# Mount secret at build time (không leak vào image layers)
RUN --mount=type=secret,id=maven_settings,target=/root/.m2/settings.xml \
    mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests
```

```bash
# Build với secret
docker build --secret id=maven_settings,src=~/.m2/settings.xml -t app .
```

---

## 5. Resource Limits & Logging

### How – Resource Constraints

```yaml
services:
  order-service:
    image: order-service:latest
    deploy:
      resources:
        limits:
          cpus: '1.0'       # max 1 CPU core
          memory: 512M      # max 512MB RAM
        reservations:
          cpus: '0.25'      # guaranteed 0.25 CPU
          memory: 256M      # guaranteed 256MB RAM

  # Native image: much lower limits possible
  order-service-native:
    image: order-service:native
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 128M    # native image needs far less
```

### How – Logging Drivers

```yaml
services:
  order-service:
    image: order-service:latest
    logging:
      driver: "json-file"   # default
      options:
        max-size: "100m"    # rotate at 100MB
        max-file: "5"       # keep 5 rotated files

  # Loki driver (send directly to Grafana Loki)
  order-service-loki:
    logging:
      driver: loki
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
        loki-pipeline-stages: |
          - json:
              expressions:
                level: level
                traceId: traceId
          - labels:
              level:
              traceId:
        labels: "com.docker.compose.service,com.docker.compose.project"

  # Fluentd aggregation
  order-service-fluentd:
    logging:
      driver: fluentd
      options:
        fluentd-address: localhost:24224
        tag: "docker.{{.Name}}"
```

---

## 6. Complete Production Compose

```yaml
# docker-compose.prod.yml – Full example
version: "3.9"

x-service-defaults: &service-defaults
  restart: unless-stopped
  networks:
    - backend

services:
  # Reverse proxy
  traefik:
    image: traefik:v3.0
    <<: *service-defaults
    command:
      - "--providers.docker.network=proxy"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.le.acme.tlschallenge=true"
      - "--certificatesresolvers.le.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/certs/acme.json"
      - "--accesslog=true"
      - "--metrics.prometheus=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - certs:/certs
    networks:
      - proxy
      - backend

  order-service:
    image: ${REGISTRY}/order-service:${VERSION}
    <<: *service-defaults
    deploy:
      replicas: 2
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          memory: 256M
    environment:
      SPRING_PROFILES_ACTIVE: prod
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB}
      SPRING_DATASOURCE_USERNAME: ${POSTGRES_USER}
    env_file:
      - .env.prod
    secrets:
      - db_password
      - jwt_secret
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health/readiness"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 60s
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.orders.rule=Host(`api.example.com`) && PathPrefix(`/api/orders`)"
      - "traefik.http.routers.orders.entrypoints=websecure"
      - "traefik.http.routers.orders.tls.certresolver=le"
      - "traefik.http.services.orders.loadbalancer.server.port=8080"
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
    networks:
      - proxy
      - backend

  postgres:
    image: postgres:16-alpine
    <<: *service-defaults
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    deploy:
      resources:
        limits:
          memory: 1G

  redis:
    image: redis:7-alpine
    <<: *service-defaults
    command: redis-server --requirepass ${REDIS_PASSWORD} --maxmemory 256mb --maxmemory-policy allkeys-lru
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    volumes:
      - redis_data:/data

networks:
  proxy:
    external: true  # created separately: docker network create proxy
  backend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  certs:
    driver: local

secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

---

## 7. Compare & Trade-offs

### Compare – Compose vs Swarm vs K8s

| | Compose (single-host) | Docker Swarm | Kubernetes |
|--|----------------------|-------------|-----------|
| Complexity | Low | Medium | High |
| Multi-host | ❌ (one machine) | ✅ | ✅ |
| Auto-scaling | ❌ | Manual replicas | HPA/KEDA |
| Rolling updates | Manual script | Built-in | Built-in |
| Service discovery | Container name DNS | VIP/DNS | CoreDNS |
| Load balancing | Nginx/Traefik | Built-in VIP | kube-proxy |
| Secret management | Files/env_file | Docker Secrets | K8s Secrets |
| Khi dùng | Dev/small prod | Medium prod | Large prod |

### Trade-offs
- **Health checks + depends_on**: đảm bảo startup order nhưng không handle service failure sau startup; cần retry logic trong app
- **Blue-green với Compose**: manual process, không built-in; CI/CD pipeline phải orchestrate
- **Docker Secrets**: chỉ work với Swarm mode; non-Swarm dùng env_file hoặc volume-mounted secret files
- **Resource limits**: quan trọng để tránh one container kill host; nhưng quá thấp gây OOMKilled
- **Logging driver loki/fluentd**: tốt cho aggregation nhưng nếu log server down → container blocked; dùng buffer/retry options

---

### Ghi chú – Chủ đề tiếp theo
> **Kubernetes Advanced**: RBAC, Network Policies, Helm packaging, GitOps với ArgoCD/Flux
