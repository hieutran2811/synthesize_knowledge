# Load Balancing – Cân bằng tải

## What – Load Balancer là gì?

**Load Balancer (LB)** là component phân phối incoming traffic đến nhiều server (pool/backend), đảm bảo không server nào bị quá tải trong khi server khác nhàn rỗi.

```
Clients                Load Balancer              Backend Servers
──────                ──────────────              ───────────────
Client 1 ─────────→                 ──────────→  Server A (40%)
Client 2 ─────────→   LB (Virtual   ──────────→  Server B (35%)
Client 3 ─────────→   IP/DNS)        ──────────→  Server C (25%)
Client 4 ─────────→
```

---

## L4 vs L7 Load Balancing

### Layer 4 (Transport Layer)
- Hoạt động ở TCP/UDP level
- Không inspect nội dung HTTP
- Nhanh hơn, overhead thấp
- Forward packet dựa trên IP + Port

```
Client TCP: 203.0.113.10:52300 → LB:443
LB decides → Backend 10.0.0.5:8080 (NAT)
```

**Tools:** AWS NLB, HAProxy (TCP mode), Nginx (stream)

**Dùng khi:** Non-HTTP protocols (gRPC, WebSocket raw, DB connections)

### Layer 7 (Application Layer)
- Inspect HTTP headers, URL, cookies, body
- Content-based routing
- SSL termination
- More features but more overhead

```
GET /api/users → Route → Users Service
GET /api/orders → Route → Orders Service
GET /static/logo.png → Route → CDN / Static Server
```

**Tools:** AWS ALB, Nginx (http), Envoy, Traefik, HAProxy (HTTP mode)

**Dùng khi:** Microservices routing, A/B testing, auth offloading

---

## Load Balancing Algorithms

### 1. Round Robin
Request phân phối lần lượt: A → B → C → A → B → C...

```
✅ Simple, fair
❌ Không xét server capacity
❌ Long-lived connections lệch (WebSocket)
```

### 2. Weighted Round Robin
Mỗi server có weight, server mạnh hơn nhận nhiều request hơn.

```
Server A (weight=5): nhận 5/8 requests
Server B (weight=2): nhận 2/8 requests
Server C (weight=1): nhận 1/8 requests
```

**Dùng khi:** Servers có capacity khác nhau (heterogeneous fleet)

### 3. Least Connections
Request đến server đang có **ít active connections nhất**.

```
Server A: 150 connections
Server B: 80 connections  ← next request goes here
Server C: 200 connections
```

**Tốt cho:** Long-lived connections (WebSocket, gRPC streaming)

### 4. Least Response Time
Request đến server có response time thấp nhất + ít connections nhất.

```
Score = (active_connections * response_time_ms)
Chọn server có score thấp nhất
```

**Thực tế:** Nginx Plus, HAProxy Enterprise có feature này.

### 5. IP Hash (Sticky Sessions)
Hash IP client → luôn vào cùng một server.

```
Client 10.0.1.5 → hash → Server B (always)
Client 10.0.1.6 → hash → Server A (always)
```

**Dùng khi:** Stateful apps (cần giữ in-memory state per user)
**Vấn đề:** Server chết → tất cả session của server đó mất; không balance đều nếu IP skewed (corporate proxy)

### 6. Consistent Hashing
Hash key (user_id, tenant_id) → Ring → Server node.

```
Ring (0 to 2^32):
    0
   /|\
  / | \
 /  |  \
A   |   B
 \  |  /
  \ | /
   \|/
    C

Key "user123" → hash → position 47823 → maps to Server B
```

**Khi thêm/xóa server:** Chỉ ~1/N keys bị remapped (thay vì toàn bộ).
**Dùng khi:** Distributed cache (Redis cluster), CDN routing, Database sharding.

**Virtual Nodes:** Mỗi physical node có nhiều vpoints trên ring → cải thiện balance.

---

## Health Checks

LB phải biết server nào alive để không route traffic vào.

### Passive Health Check
Dựa trên response của actual requests:
- 5xx → đánh dấu server unhealthy
- Tự động sau N lần thất bại

### Active Health Check
LB chủ động gửi probe requests:

```
GET /health HTTP/1.1 → 200 OK → Healthy
                     → Timeout  → Unhealthy (after 3 attempts)
                     → 503      → Unhealthy
```

**Health check endpoint nên check:**
```java
@GetMapping("/health")
public ResponseEntity<Health> health() {
    Health health = Health.builder()
        .withDetail("db", checkDatabase())      // DB connectivity
        .withDetail("cache", checkRedis())       // Redis
        .withDetail("disk", checkDiskSpace())    // Disk space
        .build();
    
    return health.getStatus().equals(Status.UP)
        ? ResponseEntity.ok(health)
        : ResponseEntity.status(503).body(health);
}
```

**Tránh:** Health check quá nặng (gọi external services) → làm chậm health check cycle.

---

## Global Load Balancing

### DNS-based Load Balancing
```
nslookup api.example.com → 203.0.113.1 (US)
                         → 203.0.113.2 (EU)
                         → 203.0.113.3 (APAC)

Route53 / Cloudflare → Geo-based routing
```

**Vấn đề:** DNS TTL → client cache → slow failover (TTL 60s minimum)

### Anycast
Cùng IP được announce từ nhiều location. BGP tự route đến gần nhất.

```
1.1.1.1 ← Cloudflare announce từ 250+ PoPs
User Vietnam → nearest PoP (Singapore) → 1.1.1.1
User US → nearest PoP (New York) → 1.1.1.1
```

**Dùng cho:** CDN, DNS resolvers (1.1.1.1, 8.8.8.8)

### AWS Global Accelerator
- Anycast IPs + AWS private backbone network
- Reduce latency 60% so với internet routing
- Instant failover (không phụ thuộc DNS TTL)

---

## SSL Termination

LB decrypt HTTPS → forward HTTP đến backend (giảm CPU backend).

```
Client ──HTTPS──→ Load Balancer ──HTTP──→ Backend
                  (terminate SSL)         (plaintext in internal network)
```

**Lưu ý:** Internal network phải trusted. Nếu cần E2E encryption → SSL passthrough hoặc re-encryption.

```
Passthrough: LB forward encrypted TCP → Backend decrypt SSL
Re-encrypt:  LB decrypt → re-encrypt → Backend decrypt (2x overhead)
```

---

## Connection Draining / Deregistration Delay

Khi remove server khỏi pool, đợi in-flight requests hoàn thành:

```
Server A removing → Stop new connections
                  → Wait 30s (draining)
                  → Force close sau timeout
                  → Deregister
```

**AWS ALB:** `deregistration_delay.timeout_seconds = 300` (default)

---

## Trade-offs

| Algorithm | Strength | Weakness |
|-----------|----------|----------|
| Round Robin | Simple | Ignores server load |
| Least Connections | Handles varying load | Overhead tracking connections |
| IP Hash | Session affinity | Uneven distribution |
| Consistent Hashing | Minimal redistribution | Complex to implement |

| LB Type | Strength | Weakness |
|---------|----------|----------|
| L4 | Fast, protocol agnostic | No content routing |
| L7 | Rich routing, visibility | Higher overhead |
| DNS | Simple, no SPOF | Slow failover |
| Anycast | Fast routing | Complex BGP |

---

## Real-world Production

### Nginx Config (L7 LB)
```nginx
upstream api_servers {
    least_conn;                    # Algorithm
    keepalive 32;                  # Connection pool
    
    server app1:8080 weight=3;
    server app2:8080 weight=3;
    server app3:8080 weight=1 backup;  # Backup khi 2 kia down
}

server {
    listen 443 ssl;
    ssl_certificate /etc/ssl/cert.pem;
    
    location /api/ {
        proxy_pass http://api_servers;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
    
    location /health {
        return 200 "OK";
    }
}
```

### AWS ALB với weighted routing (Blue-Green)
```
Listener rule:
  - 90% weight → Target Group Blue (v1.0)
  - 10% weight → Target Group Green (v1.1)  # Canary testing
```

---

## Ghi chú

**Sub-topic tiếp theo:**
- `caching.md` – Cache strategies, CDN, Redis, invalidation patterns
- `databases_design.md` – Sharding và cách LB liên quan đến DB routing
- **Keywords:** Service Mesh (Istio/Envoy), eBPF-based LB (Cilium), GSLB (Global Server Load Balancing), Rate limiting tại LB layer, mTLS, West-East traffic (service-to-service)
