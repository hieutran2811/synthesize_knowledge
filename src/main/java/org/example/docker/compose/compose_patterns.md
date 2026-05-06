# Docker Compose – Patterns Thực Tế

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Local Development Pattern

### What – Dev Pattern là gì?
Pattern setup môi trường development với Docker Compose, đảm bảo **hot reload**, **debug support**, và **dependency services** chạy tự động.

### How – Dev Compose Structure

```yaml
# compose.yaml (shared base)
services:
  app:
    build:
      context: .
      target: development          # multi-stage: dev stage

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: devpassword
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    command: redis-server --loglevel verbose

volumes:
  pgdata:
```

```yaml
# compose.override.yaml (auto-merged với compose.yaml khi dev)
services:
  app:
    volumes:
      - .:/app                     # mount source code → hot reload
      - /app/node_modules          # anonymous volume: giữ node_modules của container
    environment:
      - NODE_ENV=development
      - DEBUG=app:*
    ports:
      - "3000:3000"
      - "9229:9229"                # Node.js debugger port
    command: ["node", "--inspect=0.0.0.0:9229", "src/index.js"]

  db:
    ports:
      - "5432:5432"                # expose DB cho tools local (DBeaver, pgAdmin)
    volumes:
      - ./db/seed.sql:/docker-entrypoint-initdb.d/seed.sql  # seed data

  redis:
    ports:
      - "6379:6379"                # expose Redis cho local debug

  # Dev-only services
  mailhog:
    image: mailhog/mailhog
    ports:
      - "1025:1025"                # SMTP
      - "8025:8025"                # Web UI
    profiles: ["tools"]

  adminer:
    image: adminer:latest
    ports:
      - "8080:8080"
    profiles: ["tools"]
```

### How – Dockerfile với Dev/Prod Stages

```dockerfile
# syntax=docker/dockerfile:1.6

# ── Base ──────────────────────────────────────────────────────
FROM node:20-alpine AS base
WORKDIR /app
RUN apk add --no-cache dumb-init

# ── Dependencies ──────────────────────────────────────────────
FROM base AS deps
COPY package*.json ./
RUN npm ci

# ── Development ───────────────────────────────────────────────
FROM base AS development
COPY --from=deps /app/node_modules ./node_modules
# Source code mounted via bind mount, không COPY
ENV NODE_ENV=development
EXPOSE 3000 9229
ENTRYPOINT ["dumb-init", "--"]
CMD ["npx", "nodemon", "--inspect=0.0.0.0:9229", "src/index.js"]

# ── Builder ───────────────────────────────────────────────────
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build
RUN npm prune --production

# ── Production ────────────────────────────────────────────────
FROM base AS production
ENV NODE_ENV=production
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
RUN adduser -D -u 1001 appuser && chown -R appuser /app
USER 1001
EXPOSE 3000
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/index.js"]
```

---

## 2. Multi-Environment Pattern

### How – File Override Strategy

```bash
# File hierarchy
compose.yaml               # base: shared config (images, volumes, networks)
compose.override.yaml      # dev: auto-applied locally (bind mounts, debug ports)
compose.test.yaml          # test: test-specific config
compose.staging.yaml       # staging: staging-specific
compose.prod.yaml          # prod: production config

# Commands
docker compose up                               # dev (base + override)
docker compose -f compose.yaml -f compose.test.yaml up   # testing
docker compose -f compose.yaml -f compose.prod.yaml up   # prod
```

```yaml
# compose.test.yaml
services:
  app:
    build:
      target: builder                # build stage để chạy tests
    command: ["npm", "test", "--", "--ci", "--coverage"]
    environment:
      - NODE_ENV=test
      - DB_HOST=db-test
    depends_on:
      db-test:
        condition: service_healthy

  db-test:
    image: postgres:16-alpine
    tmpfs:
      - /var/lib/postgresql/data     # in-memory DB → nhanh hơn, clean mỗi run
    environment:
      POSTGRES_DB: testdb
      POSTGRES_USER: testuser
      POSTGRES_PASSWORD: testpass
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U testuser -d testdb"]
      interval: 3s
      retries: 10
```

---

## 3. Wait-For Pattern

### What – Vấn đề
`depends_on` kiểm soát thứ tự **start**, không đảm bảo service **ready**. App start ngay khi DB container khởi động, nhưng DB chưa sẵn sàng nhận connections.

### How – Giải pháp 1: Built-in healthcheck + condition

```yaml
# Tốt nhất: dùng healthcheck + service_healthy
services:
  db:
    image: postgres:16-alpine
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s

  app:
    depends_on:
      db:
        condition: service_healthy     # chờ DB healthy
      redis:
        condition: service_healthy
```

### How – Giải pháp 2: wait-for-it script

```bash
# Download wait-for-it.sh vào image
# https://github.com/vishnubob/wait-for-it
```

```dockerfile
COPY wait-for-it.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/wait-for-it.sh
```

```yaml
services:
  app:
    command: >
      sh -c "
        wait-for-it.sh db:5432 --timeout=60 --strict &&
        wait-for-it.sh redis:6379 --timeout=30 &&
        node dist/index.js
      "
```

### How – Giải pháp 3: Retry trong app (Best for Production)

```javascript
// App tự retry kết nối DB (resilient hơn)
async function connectWithRetry(maxRetries = 10, delay = 2000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      await db.connect();
      console.log('DB connected');
      return;
    } catch (err) {
      if (i === maxRetries - 1) throw err;
      console.log(`DB connection failed, retry ${i + 1}/${maxRetries}...`);
      await sleep(delay);
    }
  }
}
```

---

## 4. Testing Patterns

### How – Integration Testing với Compose

```yaml
# compose.integration.yaml
services:
  app:
    image: ${APP_IMAGE:-myapp:latest}
    environment:
      - DB_URL=postgresql://test:test@db:5432/testdb
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    tmpfs: ["/var/lib/postgresql/data"]  # ephemeral
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: testdb
    healthcheck:
      test: ["CMD-SHELL", "pg_isready"]
      interval: 3s
      retries: 10

  # Test runner container
  tests:
    image: ${APP_IMAGE:-myapp:latest}
    command: ["npm", "run", "test:integration"]
    environment:
      - APP_URL=http://app:3000
      - DB_URL=postgresql://test:test@db:5432/testdb
    depends_on:
      app:
        condition: service_healthy
      db:
        condition: service_healthy
```

```bash
# CI: chạy integration tests
docker compose -f compose.integration.yaml up \
  --abort-on-container-exit \
  --exit-code-from tests \
  --no-color

# Lấy exit code
EXIT_CODE=$?
docker compose -f compose.integration.yaml down -v  # cleanup
exit $EXIT_CODE
```

### How – E2E Testing (với Playwright/Cypress)

```yaml
services:
  app:
    image: myapp:${VERSION:-latest}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 5s
      retries: 10

  e2e:
    image: mcr.microsoft.com/playwright:v1.42.0-jammy
    command: npx playwright test
    environment:
      - BASE_URL=http://app:3000
      - CI=true
    volumes:
      - ./e2e:/app/e2e:ro
      - ./playwright.config.ts:/app/playwright.config.ts:ro
      - ./test-results:/app/test-results    # screenshots, traces
    working_dir: /app
    depends_on:
      app:
        condition: service_healthy
```

---

## 5. Database Migration Pattern

### How – Migration như Init Container

```yaml
services:
  migrate:
    image: myapp:latest
    command: ["npm", "run", "db:migrate"]
    environment:
      - DATABASE_URL=postgresql://appuser:pass@db:5432/appdb
    depends_on:
      db:
        condition: service_healthy
    restart: "no"                    # không restart sau khi xong

  app:
    image: myapp:latest
    depends_on:
      migrate:
        condition: service_completed_successfully  # chờ migration xong
      db:
        condition: service_healthy
```

### How – Flyway/Liquibase Pattern

```yaml
services:
  flyway:
    image: flyway/flyway:10
    command: migrate
    volumes:
      - ./db/migrations:/flyway/sql:ro
    environment:
      - FLYWAY_URL=jdbc:postgresql://db:5432/appdb
      - FLYWAY_USER=appuser
      - FLYWAY_PASSWORD=pass
    depends_on:
      db:
        condition: service_healthy

  app:
    depends_on:
      flyway:
        condition: service_completed_successfully
```

---

## 6. Service Discovery & Networking Patterns

### How – Reverse Proxy Pattern (Traefik)

```yaml
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"    # Traefik dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro

  app:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.localhost`)"
      - "traefik.http.services.app.loadbalancer.server.port=3000"

  api:
    image: myapi:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`api.localhost`)"
      - "traefik.http.services.api.loadbalancer.server.port=8080"
    # Scale: docker compose up --scale api=3
    # Traefik tự động load balance!
```

### How – Scaling với Dynamic Ports

```yaml
services:
  app:
    image: myapp:latest
    # KHÔNG đặt port fixed → scaling được
    # Traefik/Nginx tự discover

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app
```

```bash
# Scale app lên 3 instances
docker compose up -d --scale app=3

# Nginx upstream tự động (cần nginx-proxy hoặc manual config)
# Traefik tự động detect và load balance
```

---

## 7. Secrets & Configuration Patterns

### How – .env Files Hierarchy

```bash
# Order of precedence (cao → thấp):
# 1. Shell environment variables
# 2. compose.yaml environment: section
# 3. .env file (cùng thư mục với compose.yaml)
# 4. ${VAR:-default} trong compose.yaml

# .env (dev defaults, KHÔNG commit)
DB_PASSWORD=devpassword
API_KEY=dev-api-key-not-real
LOG_LEVEL=debug

# .env.example (commit để reference)
DB_PASSWORD=
API_KEY=
LOG_LEVEL=info

# Multiple .env files
docker compose --env-file .env --env-file .env.local up
```

### How – Docker Secrets (Compose v2.x)

```yaml
# compose.yaml
services:
  app:
    secrets:
      - db_password
      - api_key
    environment:
      - DB_PASSWORD_FILE=/run/secrets/db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt  # dev: từ file
  api_key:
    environment: API_KEY             # từ env var trên host
```

```python
# App đọc secret từ file (không phải env var)
import os
def get_secret(name):
    secret_file = f"/run/secrets/{name}"
    if os.path.exists(secret_file):
        with open(secret_file) as f:
            return f.read().strip()
    return os.environ.get(name.upper())  # fallback

db_password = get_secret("db_password")
```

### Compare – Config Management Approaches

| | .env file | Docker secrets | External (Vault) |
|--|-----------|---------------|-----------------|
| Security | Thấp (file plain text) | Trung bình (tmpfs) | Cao (encrypted, audited) |
| Rotation | Manual | Manual | Automatic |
| Audit | ❌ | ❌ | ✅ |
| Complexity | Thấp | Thấp | Cao |
| Dev use | ✅ | ✅ | ❌ (overkill) |
| Prod use | ❌ | OK | ✅ |

### Trade-offs
- compose.override.yaml auto-merge: tiện dev nhưng dễ quên commit override khi prod
- tmpfs database cho test: nhanh nhưng mất data khi container stop (okay cho test)
- Healthcheck + condition: tốt nhưng tăng startup time; với K8s dùng readinessProbe

### Real-world Usage
```bash
# Makefile để wrap compose commands (tiện cho team)
# Makefile:
dev:
  docker compose up -d
  docker compose logs -f app

test:
  docker compose -f compose.yaml -f compose.test.yaml up \
    --abort-on-container-exit --exit-code-from tests
  docker compose -f compose.yaml -f compose.test.yaml down -v

clean:
  docker compose down -v --rmi local
  docker system prune -f
```

### Ghi chú – Chủ đề tiếp theo
> Compose Production – blue-green, Traefik TLS, centralized logging, monitoring

---

*Cập nhật lần cuối: 2026-05-06*
