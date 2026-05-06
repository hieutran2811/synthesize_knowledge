# Configuration & Secrets Management – Quản lý cấu hình Production

## What – Vấn đề cần giải quyết

```
❌ Anti-pattern:
application.properties:
  db.password=super_secret_prod_password  ← trong Git → security breach!
  stripe.key=sk_live_abc123

✅ Giải pháp:
- Environment variables (12-Factor App)
- HashiCorp Vault (dynamic secrets)
- Spring Cloud Config Server (centralized config)
- Kubernetes Secrets/ConfigMap
```

---

## Environment Variables – 12-Factor App Style

```yaml
# application.yml – không có secrets
spring:
  datasource:
    url: ${DATABASE_URL}           # từ env var
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD} # secret từ env/Vault
  data:
    redis:
      host: ${REDIS_HOST:localhost} # default = localhost nếu không set

app:
  jwt:
    secret: ${JWT_SECRET}           # required, không có default
  stripe:
    api-key: ${STRIPE_API_KEY}
  encryption-key: ${ENCRYPTION_KEY}
```

```bash
# Docker Compose
services:
  app:
    image: myapp:latest
    environment:
      DATABASE_URL: jdbc:postgresql://postgres:5432/mydb
      DATABASE_USERNAME: app
      DATABASE_PASSWORD: ${DB_PASSWORD}  # từ .env file (không commit)
      JWT_SECRET: ${JWT_SECRET}

# Kubernetes Deployment
env:
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
  - name: DATABASE_URL
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: database-url
```

---

## Spring Cloud Config Server – Centralized Configuration

### Server Setup

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-config-server</artifactId>
</dependency>
```

```java
@SpringBootApplication
@EnableConfigServer
public class ConfigServerApp {}
```

```yaml
# Config Server application.yml
server:
  port: 8888

spring:
  cloud:
    config:
      server:
        git:
          uri: git@github.com:myorg/config-repo.git
          default-label: main
          search-paths: '{application}'  # folder = application name
          clone-on-start: true
          # private repo
          private-key: ${GIT_PRIVATE_KEY}
        encrypt:
          enabled: true  # server-side encryption
```

### Client Setup

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-config</artifactId>
</dependency>
```

```yaml
# bootstrap.yml (load trước application.yml)
spring:
  application:
    name: order-service        # tên file config trong Git repo
  profiles:
    active: prod
  config:
    import: "configserver:http://config-server:8888"
```

```bash
# Git repo structure:
config-repo/
├── order-service.yml           # shared cho tất cả profiles
├── order-service-dev.yml       # profile dev
└── order-service-prod.yml      # profile prod

# URL pattern: http://config-server:8888/{application}/{profile}
curl http://config-server:8888/order-service/prod
```

### Refresh Config (không restart)

```java
@RestController
@RefreshScope  // Bean recreate khi config refresh
public class AppController {
    @Value("${feature.new-ui.enabled}")
    private boolean newUiEnabled;
}
```

```bash
# Trigger refresh (all instances via Spring Cloud Bus)
curl -X POST http://app:8080/actuator/refresh
# hoặc broadcast qua Kafka/RabbitMQ (Spring Cloud Bus)
curl -X POST http://config-server:8888/actuator/busrefresh
```

---

## HashiCorp Vault – Dynamic Secrets

Vault tạo **short-lived credentials** thay vì hardcode. DB credentials được rotate tự động.

### Setup

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-vault-config</artifactId>
</dependency>
```

```yaml
spring:
  cloud:
    vault:
      uri: https://vault.example.com
      authentication: KUBERNETES   # hoặc TOKEN, AWS_EC2, APPROLE
      kubernetes:
        role: order-service
        service-account-token-file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kv:
        enabled: true
        backend: secret
        default-context: order-service     # reads secret/data/order-service
        profiles:
          path: secret/data/{profile}      # profile-specific secrets
      database:
        enabled: true
        role: order-service-role           # dynamic DB credentials
        backend: database
```

### Vault Secret Structure

```bash
# Static secrets (KV v2)
vault kv put secret/order-service \
  stripe-api-key=sk_live_xxx \
  jwt-secret=super-secret-key \
  encryption-key=32-byte-key

# Dynamic DB credentials (auto-rotate)
vault write database/roles/order-service-role \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';" \
  default_ttl="1h" \
  max_ttl="24h"

# Vault generates fresh credentials per app instance
# DB password changes every 1 hour automatically
```

### Vault Transit (Encryption as a Service)

```java
@Service
public class EncryptionService {

    private final VaultOperations vaultOps;

    // Encrypt data at application level, keys managed by Vault
    public String encrypt(String plaintext) {
        VaultTransitContext context = VaultTransitContext.empty();
        return vaultOps.opsForTransit().encrypt("my-key",
            plaintext.getBytes(), context);
        // Returns: vault:v1:abc123...
    }

    public String decrypt(String ciphertext) {
        byte[] result = vaultOps.opsForTransit().decrypt("my-key", ciphertext,
            VaultTransitContext.empty());
        return new String(result);
    }
}
```

---

## Kubernetes ConfigMap & Secret

```yaml
# ConfigMap (non-sensitive config)
apiVersion: v1
kind: ConfigMap
metadata:
  name: order-service-config
data:
  REDIS_HOST: redis-service
  DATABASE_HOST: postgres-service
  KAFKA_BOOTSTRAP: kafka:9092
  application.yml: |
    spring:
      datasource:
        url: jdbc:postgresql://${DATABASE_HOST}:5432/orders

---
# Secret (sensitive data – base64 encoded)
apiVersion: v1
kind: Secret
metadata:
  name: order-service-secrets
type: Opaque
data:
  DATABASE_PASSWORD: cGFzc3dvcmQxMjM=  # base64(password123)
  JWT_SECRET: c2VjcmV0a2V5           # base64(secretkey)
stringData:                            # auto base64
  STRIPE_API_KEY: sk_live_xxx

---
# Deployment: mount ConfigMap and Secret
containers:
- name: order-service
  envFrom:
  - configMapRef:
      name: order-service-config
  - secretRef:
      name: order-service-secrets
  volumeMounts:
  - name: config-volume
    mountPath: /config
    readOnly: true

volumes:
- name: config-volume
  configMap:
    name: order-service-config
```

### External Secrets Operator (K8s → Vault/AWS/GCP)

```yaml
# ExternalSecret: tự động sync secret từ Vault vào K8s Secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: order-service-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: order-service-k8s-secret
  data:
  - secretKey: DATABASE_PASSWORD
    remoteRef:
      key: secret/order-service
      property: db-password
  - secretKey: JWT_SECRET
    remoteRef:
      key: secret/order-service
      property: jwt-secret
```

---

## Jasypt – Property Encryption tại config file

```xml
<dependency>
    <groupId>com.github.ulisesbocchio</groupId>
    <artifactId>jasypt-spring-boot-starter</artifactId>
</dependency>
```

```yaml
# application.yml
spring:
  datasource:
    password: ENC(encrypted_value_here)  # jasypt sẽ decrypt
    url: jdbc:postgresql://localhost:5432/db
    username: app

jasypt:
  encryptor:
    password: ${JASYPT_ENCRYPTOR_PASSWORD}  # key từ env var, không commit!
    algorithm: PBEWithMD5AndDES
    iv-generator-classname: org.jasypt.iv.NoIvGenerator
```

```bash
# Encrypt a value
mvn jasypt:encrypt-value -Djasypt.encryptor.password=my-key -Djasypt.plugin.value=my-secret
# Output: ENC(abc123encrypted)
```

---

## Configuration Priority (Security)

```
Ưu tiên cao nhất → thấp nhất:
1. Command-line args (--db.password=x) – chỉ dev/test
2. OS Environment Variables – production standard
3. Vault (dynamic, auto-rotate) – enterprise
4. Kubernetes Secrets (static but managed) – K8s apps
5. Spring Cloud Config Server – multi-service
6. application-{profile}.properties – profile-specific
7. application.properties – defaults (không có secrets)
```

---

## Trade-offs

| Approach | Security | Complexity | Rotation |
|----------|----------|------------|---------|
| Env vars | Medium | Low | Manual |
| K8s Secrets | Medium (need ESO) | Medium | Manual |
| Vault | High | High | Automatic |
| Config Server | Medium | Medium | Via refresh |
| Jasypt | Low (key risk) | Low | Manual |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `production/performance_tuning.md` – JVM, connection pool, GraalVM
- `production/production_patterns.md` – Graceful shutdown, health probes
- **Keywords:** Secret rotation, SOPS (Secrets OPerationS), AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, Spring Vault, Sealed Secrets (Bitnami), Environment variable injection, Secret sprawl, Least privilege, Secret scanning (git-secrets, TruffleHog), Config drift detection
