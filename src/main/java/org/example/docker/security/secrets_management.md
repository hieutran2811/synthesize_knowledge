# Docker Secrets Management – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Secrets Anti-patterns

### What – Vấn đề với Secrets?
Secrets (passwords, API keys, certificates) bị lộ là nguyên nhân hàng đầu của data breaches. Docker có nhiều "bẫy" khiến secrets bị lộ vô tình.

### How – Các cách secrets bị lộ

```bash
# ❌ Anti-pattern 1: ENV trong Dockerfile
FROM node:20
ENV DB_PASSWORD=supersecret          # → lưu trong image layer
ENV API_KEY=sk-prod-abc123           # → docker history thấy rõ

docker history --no-trunc myapp:latest | grep -i password  # lộ!

# ❌ Anti-pattern 2: ARG trong Dockerfile
ARG DB_PASSWORD                       # → docker inspect build log
docker build --build-arg DB_PASSWORD=secret .
docker inspect myapp:latest | grep -i secret  # lộ trong metadata!

# ❌ Anti-pattern 3: COPY credentials files
COPY .aws /root/.aws/                 # credentials vào image layer
COPY id_rsa /root/.ssh/              # private key trong image!

# ❌ Anti-pattern 4: Environment variables (ít hại hơn nhưng vẫn risk)
docker run -e DB_PASSWORD=secret myapp
docker inspect myapp | grep DB_PASSWORD  # lộ trong inspect!
ps aux | grep DB_PASSWORD             # lộ trong process list!

# ❌ Anti-pattern 5: Commit .env files
git add .env                         # secrets trong git history mãi mãi!
```

---

## 2. Docker Secrets (Swarm Mode)

### What – Docker Secrets là gì?
**Docker Secrets** là cơ chế lưu trữ và phân phối secrets an toàn trong Docker Swarm. Secrets được **encrypt at rest** (AES-256) và **encrypt in transit** (TLS), mount vào container dưới dạng **tmpfs** (RAM, không ghi disk).

### How – Docker Secrets (Swarm)

```bash
# Tạo secret
echo "mysecretpassword" | docker secret create db_password -
docker secret create db_password ./secrets/db_pass.txt  # từ file
docker secret create ssl_cert ./certs/server.crt

# List / Inspect (chỉ xem metadata, không xem value)
docker secret ls
docker secret inspect db_password    # chỉ thấy ID, tên, timestamps

# Dùng trong service
docker service create \
  --name app \
  --secret db_password \
  --secret source=ssl_cert,target=/etc/ssl/app.crt,mode=0444 \
  myapp:latest

# App đọc secret từ /run/secrets/<name>
# Không bao giờ từ env var!
```

```python
# Đọc secret trong app (Python)
def read_secret(name: str) -> str:
    secret_path = f"/run/secrets/{name}"
    try:
        with open(secret_path, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        # Fallback cho local dev (env var)
        import os
        return os.environ.get(name.upper(), '')

DB_PASSWORD = read_secret("db_password")
```

```bash
# Rotate secret (zero-downtime trong Swarm)
# 1. Tạo secret mới với version
echo "newpassword" | docker secret create db_password_v2 -

# 2. Update service để dùng secret mới
docker service update \
  --secret-rm db_password \
  --secret-add source=db_password_v2,target=/run/secrets/db_password \
  myapp

# 3. Xóa secret cũ
docker secret rm db_password

# Remove secret
docker secret rm db_password
```

### How – Docker Secrets trong Compose (Standalone)

```yaml
# compose.yaml
services:
  app:
    image: myapp:latest
    secrets:
      - db_password
      - db_password_ro:
          target: /run/secrets/db_ro
          uid: '1001'
          gid: '1001'
          mode: 0400              # read-only, chỉ owner đọc

  db:
    image: postgres:16
    secrets:
      - db_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt      # dev: từ file local
    # external: true                      # prod Swarm: secret đã tạo trong Swarm
  api_key:
    environment: API_KEY                  # từ env var trên host
```

---

## 3. HashiCorp Vault

### What – HashiCorp Vault là gì?
**Vault** là enterprise-grade secrets management platform với dynamic secrets, fine-grained access control, secret rotation, và audit logging.

### How – Vault Setup với Docker

```yaml
# compose.vault.yaml
services:
  vault:
    image: vault:1.15
    ports:
      - "8200:8200"
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: myroot   # DEV mode only!
      VAULT_DEV_LISTEN_ADDRESS: "0.0.0.0:8200"
    cap_add:
      - IPC_LOCK                        # cần để lock memory (secrets không swap)
    volumes:
      - vault-data:/vault/data
      - ./vault/config:/vault/config:ro

volumes:
  vault-data:
```

```bash
# Setup Vault (dev mode)
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='myroot'

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Write secrets
vault kv put secret/myapp/production \
  db_password=supersecret \
  api_key=sk-prod-abc123

# Read secrets
vault kv get secret/myapp/production
vault kv get -field=db_password secret/myapp/production

# Policy (least privilege)
vault policy write myapp-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# AppRole authentication (cho CI/CD, containers)
vault auth enable approle
vault write auth/approle/role/myapp \
  secret_id_ttl=10m \
  token_num_uses=10 \
  token_ttl=20m \
  token_max_ttl=30m \
  policies=myapp-policy

ROLE_ID=$(vault read -field=role_id auth/approle/role/myapp/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/myapp/secret-id)

# Get token với AppRole
vault write auth/approle/login \
  role_id=$ROLE_ID \
  secret_id=$SECRET_ID
```

### How – Vault Agent (Sidecar Pattern)

```yaml
services:
  vault-agent:
    image: vault:1.15
    command: vault agent -config=/vault/agent.hcl
    environment:
      VAULT_ADDR: http://vault:8200
    volumes:
      - ./vault/agent.hcl:/vault/agent.hcl:ro
      - secrets:/secrets              # shared volume với app
    depends_on:
      vault:
        condition: service_healthy

  app:
    image: myapp:latest
    volumes:
      - secrets:/run/secrets:ro       # secrets từ vault-agent
    depends_on:
      - vault-agent

volumes:
  secrets:                            # tmpfs shared volume
    driver_opts:
      type: tmpfs
      device: tmpfs
```

```hcl
# vault/agent.hcl
vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/role-id"
      secret_id_file_path = "/vault/secret-id"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/vault-token"
    }
  }
}

template {
  source      = "/vault/templates/db.ctmpl"
  destination = "/secrets/db_password"
  perms       = "0400"
}
```

```
# vault/templates/db.ctmpl
{{- with secret "secret/data/myapp/production" -}}
{{ .Data.data.db_password }}
{{- end -}}
```

### How – Dynamic Secrets (Database)

```bash
# Vault tạo DB credentials tạm thời (rotate tự động!)
vault secrets enable database

vault write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  allowed_roles="myapp-role" \
  connection_url="postgresql://{{username}}:{{password}}@db:5432/appdb" \
  username="vault_admin" \
  password="adminpass"

vault write database/roles/myapp-role \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

# App request credentials (TTL 1 hour, auto-revoked)
vault read database/creds/myapp-role
# Key                Value
# username           v-approle-myapp-XYZ
# password           A1B2C3D4E5F6...
# lease_duration     1h (auto-revoke sau 1h)
```

---

## 4. AWS Secrets Manager

### How – App Fetch Secrets từ AWS

```python
import boto3
import json
from functools import lru_cache

@lru_cache(maxsize=None)
def get_secret(secret_name: str, region: str = "ap-southeast-1") -> dict:
    client = boto3.client("secretsmanager", region_name=region)
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

# Dùng
secrets = get_secret("prod/myapp/database")
DB_PASSWORD = secrets["password"]
DB_USER = secrets["username"]
```

```bash
# Trong ECS Task Definition (IAM role, không cần hardcode)
{
  "containerDefinitions": [{
    "secrets": [
      {
        "name": "DB_PASSWORD",
        "valueFrom": "arn:aws:secretsmanager:ap-southeast-1:123:secret:prod/myapp/db-xxx:password::"
      }
    ]
  }]
}
# ECS inject secrets vào env var, fetched từ Secrets Manager
# Cần Task Role có quyền secretsmanager:GetSecretValue
```

### How – Rotation tự động

```bash
# Enable automatic rotation (Lambda function)
aws secretsmanager rotate-secret \
  --secret-id prod/myapp/database \
  --rotation-lambda-arn arn:aws:lambda:...:SecretsManagerRotation \
  --rotation-rules AutomaticallyAfterDays=30

# Test rotation
aws secretsmanager rotate-secret --secret-id prod/myapp/database
```

---

## 5. External Secrets Operator (Kubernetes)

### What – ESO là gì?
**External Secrets Operator** tự động sync secrets từ external stores (Vault, AWS, GCP, Azure) vào Kubernetes Secrets.

### How – ESO Setup

```yaml
# ExternalSecret resource
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
spec:
  refreshInterval: 1h              # sync mỗi 1 giờ
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: myapp-secret             # Kubernetes Secret được tạo
    creationPolicy: Owner
  data:
    - secretKey: db_password       # key trong K8s Secret
      remoteRef:
        key: secret/myapp/production  # path trong Vault
        property: db_password

---
# SecretStore (connection đến Vault)
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "myapp"
```

### Compare – Secrets Solutions

| | Docker Secrets | Vault | AWS SM | ESO (K8s) |
|--|--------------|-------|--------|----------|
| Encryption at rest | ✅ AES-256 | ✅ AES-256-GCM | ✅ AWS KMS | External store |
| Dynamic secrets | ❌ | ✅ | ❌ | Via store |
| Auto rotation | ❌ | ✅ | ✅ | Via store |
| Audit log | ❌ | ✅ | ✅ | Via store |
| Complexity | Thấp | Cao | Trung bình | Trung bình |
| Env | Docker/Swarm | Any | AWS | Kubernetes |
| Cost | Free | OSS/Enterprise | $0.40/secret/mo | Free + store cost |

### Trade-offs
- Docker Secrets: chỉ dùng được trong Swarm; Compose standalone mount as file (không encrypt at rest)
- Vault: mạnh nhất nhưng phải self-host, manage HA, backup
- AWS SM: managed, tích hợp IAM tốt, nhưng vendor lock-in và cost khi nhiều secrets
- Environment variables: không dùng cho sensitive data (visible qua inspect, ps)

### Real-world Usage
```bash
# Detect secrets bị leak trong images
docker history --no-trunc myapp:latest | grep -iE "password|secret|key|token"

# Scan git history cho secrets (trước khi commit)
# Cài pre-commit hook với detect-secrets
pip install detect-secrets
detect-secrets scan > .secrets.baseline
detect-secrets audit .secrets.baseline

# gitleaks: scan toàn bộ git repo
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect \
  --source=/repo \
  --verbose

# Rotate AWS credentials nếu bị lộ
aws iam create-access-key --user-name myuser
aws iam delete-access-key --user-name myuser --access-key-id OLD_KEY_ID
```

### Ghi chú – Chủ đề tiếp theo
> CI/CD Integration – GitHub Actions full pipeline, GitLab CI, Jenkins với Docker agent

---

*Cập nhật lần cuối: 2026-05-06*
