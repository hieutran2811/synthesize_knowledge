# WebSocket Scaling & Security

## Mục lục
1. [Horizontal Scaling – Sticky Sessions vs Stateless](#1-horizontal-scaling--sticky-sessions-vs-stateless)
2. [Redis Pub/Sub Adapter](#2-redis-pubsub-adapter)
3. [Nginx WebSocket Proxy](#3-nginx-websocket-proxy)
4. [Kubernetes WebSocket](#4-kubernetes-websocket)
5. [Authentication & Authorization](#5-authentication--authorization)
6. [Rate Limiting & DoS Protection](#6-rate-limiting--dos-protection)
7. [Origin Validation & Security Headers](#7-origin-validation--security-headers)

---

## 1. Horizontal Scaling – Sticky Sessions vs Stateless

### 1.1 Vấn đề

```
WebSocket is stateful: each connection is tied to ONE server instance.
Load balancer distributes connections across N servers.

Problem:
  Client A connected to Server 1 (room "general")
  Client B connected to Server 2 (room "general")
  Server 1 broadcasts to "general" → Client A gets it ✅
                                   → Client B does NOT ✅ (on Server 2!)

Solutions:
  1. Sticky Sessions (session affinity): LB always routes Client B to Server 2
     → simpler, but: session lost if Server 2 dies
  2. Shared Message Bus: publish to Redis → all servers broadcast to local clients
     → truly stateless, survives server restarts
```

### 1.2 Sticky Sessions

```nginx
# nginx.conf — IP hash (simple but not load-balanced evenly)
upstream websocket_backend {
    ip_hash;                          # same IP → same server
    server ws1.internal:8080;
    server ws2.internal:8080;
    server ws3.internal:8080;
}

# Cookie-based sticky (better distribution)
upstream websocket_backend {
    server ws1.internal:8080;
    server ws2.internal:8080;
    server ws3.internal:8080;
    sticky cookie srv_id expires=1h domain=.example.com path=/;
    # Requires: nginx-sticky-module or nginx plus
}
```

```yaml
# AWS ALB — stickiness via cookie
Type: AWS::ElasticLoadBalancingV2::TargetGroup
Properties:
  TargetType: instance
  TargetGroupAttributes:
    - Key: stickiness.enabled
      Value: "true"
    - Key: stickiness.type
      Value: app_cookie       # or lb_cookie
    - Key: stickiness.app_cookie.cookie_name
      Value: AWSALB
    - Key: stickiness.app_cookie.duration_seconds
      Value: "86400"          # 24 hours
```

### 1.3 Stateless Architecture với Redis

```
                    ┌─────────────┐
                    │ Load Balancer│
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
    ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
    │  WS Server 1 │ │  WS Server 2 │ │  WS Server 3 │
    │  Clients A,B │ │  Clients C,D │ │  Clients E,F │
    └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
           └───────────────┼───────────────┘
                    ┌──────▼──────┐
                    │  Redis      │
                    │  Pub/Sub    │  ← shared message bus
                    └─────────────┘
```

---

## 2. Redis Pub/Sub Adapter

### 2.1 Socket.IO Redis Adapter

```javascript
// socket-server-scaled.js
const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');
const { createClient } = require('redis');

async function createSocketServer(httpServer) {
  const io = new Server(httpServer, {
    transports: ['websocket'],
    // Socket.IO clustering: each server knows about all rooms via Redis
  });

  // Two Redis clients required: one for pub, one for sub
  const pubClient = createClient({
    url: process.env.REDIS_URL,
    socket: { reconnectStrategy: (retries) => Math.min(retries * 50, 3000) },
  });
  const subClient = pubClient.duplicate();

  pubClient.on('error', (err) => console.error('Redis pub error:', err));
  subClient.on('error', (err) => console.error('Redis sub error:', err));

  await Promise.all([pubClient.connect(), subClient.connect()]);
  
  io.adapter(createAdapter(pubClient, subClient, {
    key: 'socket.io',         // Redis key prefix
    requestsTimeout: 5_000,   // timeout for inter-server requests
  }));

  return io;
}

// With Redis adapter, these work across all servers:
io.to('room:general').emit('message', data);           // ✅ reaches all servers
io.in(`user:${userId}`).disconnectSockets(true);       // ✅ disconnect from any server
const count = await io.in('room:general').fetchSockets(); // ✅ list sockets across servers
```

### 2.2 Custom Redis Pub/Sub (ws library)

```javascript
// redis-hub.js — manual Redis Pub/Sub for ws library
const redis = require('redis');
const { WebSocket } = require('ws');

class RedisHub {
  #localClients = new Map();  // clientId → WebSocket (local only)
  #localRooms = new Map();    // roomId → Set<clientId> (local only)
  #pub;
  #sub;
  #serverId;

  async init() {
    this.#serverId = process.env.SERVER_ID ?? `server-${Math.random().toString(36).slice(2)}`;
    
    this.#pub = redis.createClient({ url: process.env.REDIS_URL });
    this.#sub = this.#pub.duplicate();
    
    await Promise.all([this.#pub.connect(), this.#sub.connect()]);

    // Subscribe to cross-server events
    await this.#sub.subscribe('ws:broadcast', (rawMsg) => {
      const event = JSON.parse(rawMsg);
      if (event.sourceServerId === this.#serverId) return; // skip own messages

      this.#broadcastLocal(event.roomId, event.payload, null);
    });

    await this.#sub.subscribe('ws:to-user', (rawMsg) => {
      const event = JSON.parse(rawMsg);
      if (event.sourceServerId === this.#serverId) return;

      const ws = this.#localClients.get(event.clientId);
      if (ws?.readyState === WebSocket.OPEN) {
        ws.send(event.payload);
      }
    });
  }

  registerClient(clientId, ws) {
    this.#localClients.set(clientId, ws);
  }

  removeClient(clientId) {
    this.#localClients.delete(clientId);
    this.#localRooms.forEach((clients, roomId) => {
      clients.delete(clientId);
      if (clients.size === 0) this.#localRooms.delete(roomId);
    });
  }

  joinRoom(clientId, roomId) {
    if (!this.#localRooms.has(roomId)) this.#localRooms.set(roomId, new Set());
    this.#localRooms.get(roomId).add(clientId);
  }

  async broadcastToRoom(roomId, payload, excludeClientId = null) {
    // Send to local clients
    this.#broadcastLocal(roomId, payload, excludeClientId);

    // Publish to Redis for other servers
    await this.#pub.publish('ws:broadcast', JSON.stringify({
      sourceServerId: this.#serverId,
      roomId,
      payload: typeof payload === 'string' ? payload : JSON.stringify(payload),
      excludeClientId,
    }));
  }

  #broadcastLocal(roomId, payload, excludeClientId) {
    const room = this.#localRooms.get(roomId);
    if (!room) return;

    const msg = typeof payload === 'string' ? payload : JSON.stringify(payload);
    room.forEach(clientId => {
      if (clientId === excludeClientId) return;
      const ws = this.#localClients.get(clientId);
      if (ws?.readyState === WebSocket.OPEN) ws.send(msg);
    });
  }

  // Track online users in Redis (for presence across servers)
  async setOnline(userId, clientId) {
    await this.#pub.hset('ws:online', userId, JSON.stringify({
      clientId,
      serverId: this.#serverId,
      since: Date.now(),
    }));
  }

  async setOffline(userId) {
    await this.#pub.hdel('ws:online', userId);
  }

  async isOnline(userId) {
    return (await this.#pub.hexists('ws:online', userId)) === 1;
  }
}
```

---

## 3. Nginx WebSocket Proxy

### 3.1 Basic WebSocket Proxy

```nginx
# /etc/nginx/nginx.conf

# Required: WebSocket upgrade map
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream ws_backend {
    # Round-robin (stateless with Redis adapter)
    server ws1.internal:8080;
    server ws2.internal:8080;
    server ws3.internal:8080;
    
    keepalive 32; # Keep upstream connections alive
}

server {
    listen 443 ssl http2;
    server_name api.example.com;

    ssl_certificate     /etc/ssl/certs/example.com.crt;
    ssl_certificate_key /etc/ssl/private/example.com.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # WebSocket endpoint
    location /ws {
        proxy_pass http://ws_backend;

        # Critical: WebSocket upgrade headers
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Pass real IP to backend
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeout settings
        proxy_connect_timeout    10s;
        proxy_send_timeout       3600s;  # 1 hour — keep long-lived connections
        proxy_read_timeout       3600s;  # must be > heartbeat interval
        
        # Buffer settings — disable for real-time (reduces latency)
        proxy_buffering          off;
        proxy_cache              off;
        
        # Rate limiting for WebSocket connections
        limit_conn ws_connections 10;    # max 10 WS connections per IP
    }

    # REST API endpoint (separate location)
    location /api {
        proxy_pass http://api_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";  # HTTP/1.1 keep-alive (not upgrade)
        # ... normal API proxy config
    }
}

# Connection limits
limit_conn_zone $binary_remote_addr zone=ws_connections:10m;
```

### 3.2 SockJS Path Handling

```nginx
# SockJS uses multiple paths: /ws, /ws/{server}/{session}/websocket, /ws/{server}/{session}/xhr
location ~ ^/ws(/.*)?$ {
    proxy_pass http://ws_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_buffering off;
    proxy_read_timeout 3600s;
}
```

---

## 4. Kubernetes WebSocket

### 4.1 Service & Ingress

```yaml
# websocket-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: websocket-server
spec:
  replicas: 3
  selector:
    matchLabels:
      app: websocket-server
  template:
    metadata:
      labels:
        app: websocket-server
    spec:
      containers:
      - name: ws-server
        image: my-registry/ws-server:latest
        ports:
        - containerPort: 8080
        env:
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: url
        - name: SERVER_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name  # use pod name as server ID
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        lifecycle:
          preStop:
            exec:
              # Graceful shutdown: drain connections before pod removal
              command: ["/bin/sh", "-c", "sleep 15"]
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"

---
apiVersion: v1
kind: Service
metadata:
  name: websocket-service
spec:
  selector:
    app: websocket-server
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
  # sessionAffinity: ClientIP  # K8s sticky sessions (less robust than cookie-based)

---
# nginx-ingress with WebSocket support
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: websocket-ingress
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    # Sticky sessions using cookie (if not using Redis adapter)
    # nginx.ingress.kubernetes.io/affinity: "cookie"
    # nginx.ingress.kubernetes.io/session-cookie-name: "route"
    # nginx.ingress.kubernetes.io/session-cookie-expires: "3600"
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /ws
        pathType: Prefix
        backend:
          service:
            name: websocket-service
            port:
              number: 80
```

### 4.2 HPA & Pod Disruption Budget

```yaml
# Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: websocket-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: websocket-server
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Pods
    pods:
      metric:
        name: websocket_connections  # custom metric from Prometheus
      target:
        type: AverageValue
        averageValue: "1000"  # scale up when avg > 1000 connections/pod

---
# Pod Disruption Budget — ensure rolling updates don't drop all connections
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: websocket-pdb
spec:
  minAvailable: 2          # always keep 2 pods running during updates
  selector:
    matchLabels:
      app: websocket-server
```

---

## 5. Authentication & Authorization

### 5.1 JWT Authentication Patterns

```javascript
// auth-strategies.js

// ── Strategy 1: Token in URL query param (simpler, logs warn) ─────────────
// Client: new WebSocket('wss://api.example.com/ws?token=eyJ...')
// Risk: token appears in server access logs and proxy logs
// Mitigate: use short-lived tokens (1-5 minutes) just for WS handshake

// ── Strategy 2: Cookie (most secure) ─────────────────────────────────────
// Client: credentials automatically included if SameSite allows
// Server:
const wss = new WebSocketServer({
  verifyClient: ({ req }, callback) => {
    const cookies = parseCookies(req.headers.cookie);
    const token = cookies['access_token'];
    verifyAndCallback(token, req, callback);
  },
});

// ── Strategy 3: First message authentication ──────────────────────────────
// Client: connect first, then send auth message immediately
// Server: hold all other messages until auth message received
const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  let authenticated = false;
  const AUTH_TIMEOUT = 5_000; // must auth within 5s

  const authTimeout = setTimeout(() => {
    if (!authenticated) {
      ws.close(4001, 'Authentication timeout');
    }
  }, AUTH_TIMEOUT);

  ws.on('message', (data) => {
    const msg = JSON.parse(data);

    if (!authenticated) {
      if (msg.type !== 'auth') {
        ws.close(4001, 'First message must be auth');
        return;
      }

      verifyToken(msg.token)
        .then(user => {
          authenticated = true;
          clearTimeout(authTimeout);
          ws.user = user;
          ws.send(JSON.stringify({ type: 'auth:success', userId: user.id }));
        })
        .catch(() => {
          ws.close(4003, 'Invalid token');
        });
      return;
    }

    // Normal message handling after authentication
    handleMessage(ws, msg);
  });
});

// ── Token Verification ────────────────────────────────────────────────────
const jwt = require('jsonwebtoken');

function verifyToken(token) {
  return new Promise((resolve, reject) => {
    jwt.verify(token, process.env.JWT_PUBLIC_KEY, {
      algorithms: ['RS256'],  // asymmetric — public key on WS server, private key on auth server
      issuer: 'https://auth.example.com',
      audience: 'wss://api.example.com',
    }, (err, payload) => {
      if (err) reject(err);
      else resolve(payload);
    });
  });
}

function verifyAndCallback(token, req, callback) {
  if (!token) { callback(false, 401, 'Unauthorized'); return; }

  verifyToken(token)
    .then(user => {
      req.user = user;
      callback(true);
    })
    .catch(() => callback(false, 403, 'Invalid token'));
}
```

### 5.2 Token Refresh for Long-lived Connections

```typescript
// token-refresh-ws.ts
// Problem: JWT expires (e.g., 15min), but WS connection lasts hours
// Solution: client sends token refresh before expiry

class AuthAwareClient {
  private tokenExpiresAt = 0;
  private refreshTimer: ReturnType<typeof setTimeout> | null = null;

  setToken(token: string): void {
    const payload = JSON.parse(atob(token.split('.')[1]));
    this.tokenExpiresAt = payload.exp * 1000;

    // Schedule refresh 60s before expiry
    const refreshIn = this.tokenExpiresAt - Date.now() - 60_000;
    if (refreshIn > 0) {
      this.refreshTimer = setTimeout(() => this.refreshToken(), refreshIn);
    }
  }

  private async refreshToken(): Promise<void> {
    try {
      const response = await fetch('/api/auth/refresh', {
        method: 'POST',
        credentials: 'include', // send HttpOnly refresh token cookie
      });
      const { accessToken } = await response.json();
      this.setToken(accessToken);

      // Notify server of new token (some impls require this)
      this.ws.send(JSON.stringify({ type: 'auth:refresh', token: accessToken }));
    } catch (err) {
      console.error('Token refresh failed, disconnecting');
      this.ws.close(4401, 'Token refresh failed');
    }
  }
}

// Server: handle token refresh message
socket.on('auth:refresh', async ({ token }) => {
  try {
    const user = await verifyToken(token);
    socket.data.user = user; // update user info
    socket.emit('auth:refresh:ack', { ok: true });
  } catch {
    socket.disconnect(true);
  }
});
```

### 5.3 Authorization — per-message and per-room

```javascript
// authorization.js
class WebSocketAuthorizer {
  // Check if user can perform action in context
  async canJoinRoom(userId, roomId) {
    // Cache room membership in Redis to avoid DB hit on every message
    const cacheKey = `room:members:${roomId}`;
    let members = await redis.smembers(cacheKey);
    if (members.length === 0) {
      members = await roomRepo.getMembers(roomId);
      await redis.sadd(cacheKey, ...members);
      await redis.expire(cacheKey, 300); // 5 min TTL
    }
    return members.includes(userId);
  }

  async canSendMessage(userId, roomId) {
    const user = await userRepo.findById(userId);
    if (user.banned) return false;
    if (user.mutedUntil && user.mutedUntil > new Date()) return false;
    return this.canJoinRoom(userId, roomId);
  }

  checkRateLimit(userId, action) {
    // See rate limiting section
  }
}

// Use in message handler:
socket.on('room:message', async ({ roomId, content }, ack) => {
  if (!await authorizer.canSendMessage(socket.data.user.id, roomId)) {
    ack?.({ error: 'Forbidden' });
    return;
  }
  // proceed...
});
```

---

## 6. Rate Limiting & DoS Protection

### 6.1 Connection Rate Limiting

```javascript
// rate-limiter.js — per-IP connection limit
const connectionCounts = new Map(); // IP → { count, windowStart }
const MAX_CONNECTIONS_PER_IP = 10;
const MAX_CONNECTIONS_PER_USER = 5;
const WINDOW_MS = 60_000; // 1 minute

const wss = new WebSocketServer({
  verifyClient: ({ req }, callback) => {
    const ip = req.headers['x-forwarded-for']?.split(',')[0] ?? req.socket.remoteAddress;
    const now = Date.now();

    const entry = connectionCounts.get(ip) ?? { count: 0, windowStart: now };
    
    // Reset window if expired
    if (now - entry.windowStart > WINDOW_MS) {
      entry.count = 0;
      entry.windowStart = now;
    }

    if (entry.count >= MAX_CONNECTIONS_PER_IP) {
      callback(false, 429, 'Too Many Requests');
      return;
    }

    entry.count++;
    connectionCounts.set(ip, entry);
    callback(true);
  },
});

// Clean up expired entries periodically
setInterval(() => {
  const now = Date.now();
  connectionCounts.forEach((entry, ip) => {
    if (now - entry.windowStart > WINDOW_MS) connectionCounts.delete(ip);
  });
}, 60_000);
```

### 6.2 Message Rate Limiting (Token Bucket)

```javascript
// token-bucket.js — smooth rate limiting per client
class TokenBucket {
  #tokens;
  #capacity;
  #refillRate; // tokens per ms
  #lastRefill;

  constructor({ capacity, refillPerSecond }) {
    this.#capacity = capacity;
    this.#tokens = capacity;
    this.#refillRate = refillPerSecond / 1000;
    this.#lastRefill = Date.now();
  }

  consume(tokens = 1) {
    this.#refill();
    if (this.#tokens < tokens) return false;
    this.#tokens -= tokens;
    return true;
  }

  #refill() {
    const now = Date.now();
    const elapsed = now - this.#lastRefill;
    this.#tokens = Math.min(this.#capacity, this.#tokens + elapsed * this.#refillRate);
    this.#lastRefill = now;
  }
}

// Per-client rate limiters
const rateLimiters = new Map(); // clientId → TokenBucket

wss.on('connection', (ws) => {
  rateLimiters.set(ws.clientId, new TokenBucket({
    capacity: 30,           // burst: 30 messages
    refillPerSecond: 5,     // sustained: 5 messages/second
  }));

  ws.on('message', (data) => {
    const bucket = rateLimiters.get(ws.clientId);
    if (!bucket.consume()) {
      ws.send(JSON.stringify({ type: 'error', code: 'RATE_LIMITED', retryAfter: 1000 }));
      return; // drop message
    }
    handleMessage(ws, JSON.parse(data));
  });

  ws.on('close', () => rateLimiters.delete(ws.clientId));
});
```

### 6.3 Redis Rate Limiting (distributed, across servers)

```javascript
// redis-rate-limiter.js — sliding window rate limit in Redis
class DistributedRateLimiter {
  constructor(redis) {
    this.redis = redis;
  }

  // Sliding window log algorithm
  async isAllowed(key, limit, windowSec) {
    const now = Date.now();
    const windowStart = now - windowSec * 1000;
    const redisKey = `ratelimit:${key}`;

    const pipeline = this.redis.multi();
    pipeline.zRemRangeByScore(redisKey, '-inf', windowStart);  // remove old entries
    pipeline.zCard(redisKey);                                    // count remaining
    pipeline.zAdd(redisKey, { score: now, value: `${now}` });  // add current request
    pipeline.expire(redisKey, windowSec + 1);                   // TTL cleanup

    const results = await pipeline.exec();
    const count = results[1]; // count before adding current request

    return count < limit;
  }

  // Fixed window (simpler, slightly less accurate)
  async isAllowedFixed(key, limit, windowSec) {
    const windowKey = Math.floor(Date.now() / (windowSec * 1000));
    const redisKey = `ratelimit:${key}:${windowKey}`;

    const count = await this.redis.incr(redisKey);
    if (count === 1) await this.redis.expire(redisKey, windowSec);
    return count <= limit;
  }
}

// Usage in Socket.IO middleware:
io.use(async (socket, next) => {
  const ip = socket.handshake.address;
  const allowed = await rateLimiter.isAllowed(`conn:${ip}`, 10, 60);
  if (!allowed) return next(new Error('Rate limit exceeded'));
  next();
});

socket.on('chat:message', async (data, ack) => {
  const userId = socket.data.user.id;
  const allowed = await rateLimiter.isAllowed(`msg:${userId}`, 20, 10); // 20 msgs/10s
  if (!allowed) {
    ack?.({ error: 'Rate limited', retryAfter: 10 });
    return;
  }
  // proceed...
});
```

### 6.4 Message Size & Flood Protection

```javascript
// flood-protection.js
const wss = new WebSocketServer({
  server,
  maxPayload: 256 * 1024, // 256KB max frame size — reject larger at protocol level
});

// Application-level size limits
function validateMessage(msg) {
  if (typeof msg.content === 'string' && msg.content.length > 4096) {
    throw new Error('Message too long');
  }
  if (JSON.stringify(msg).length > 64 * 1024) {
    throw new Error('Payload too large');
  }
  return true;
}

// Slowloris protection: abort connection if handshake takes too long
const wss = new WebSocketServer({
  server,
  handleProtocols: (protocols) => protocols[0] ?? false,
});

// Connection timeout for idle unauthenticated connections
wss.on('connection', (ws, req) => {
  const AUTH_DEADLINE = setTimeout(() => {
    if (!ws.authenticated) ws.close(4401, 'Authentication required');
  }, 10_000);

  ws.on('close', () => clearTimeout(AUTH_DEADLINE));
});
```

---

## 7. Origin Validation & Security Headers

### 7.1 Origin Validation

```javascript
// origin-validation.js
const ALLOWED_ORIGINS = new Set([
  'https://example.com',
  'https://www.example.com',
  'https://app.example.com',
  // Development
  ...(process.env.NODE_ENV === 'development' ? ['http://localhost:4200', 'http://localhost:3000'] : []),
]);

// For ws library
const wss = new WebSocketServer({
  verifyClient: ({ origin, req }, callback) => {
    // origin is undefined for non-browser clients (server-to-server)
    if (!origin) {
      // Allow server-to-server connections with API key
      const apiKey = req.headers['x-api-key'];
      if (apiKey === process.env.SERVER_API_KEY) {
        callback(true);
        return;
      }
      callback(false, 403, 'Origin required for browser clients');
      return;
    }

    if (ALLOWED_ORIGINS.has(origin)) {
      callback(true);
    } else {
      console.warn(`Rejected connection from origin: ${origin}`);
      callback(false, 403, 'Origin not allowed');
    }
  },
});

// For Socket.IO
const io = new Server(httpServer, {
  cors: {
    origin: (origin, callback) => {
      if (!origin || ALLOWED_ORIGINS.has(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Origin not allowed'));
      }
    },
    methods: ['GET', 'POST'],
    credentials: true,
  },
});
```

### 7.2 Security Checklist Implementation

```javascript
// security-hardening.js

// 1. Force WSS in production
if (process.env.NODE_ENV === 'production') {
  app.use((req, res, next) => {
    if (req.headers['x-forwarded-proto'] !== 'https') {
      return res.redirect(301, `https://${req.headers.host}${req.url}`);
    }
    next();
  });
}

// 2. Security headers for HTTP upgrade response
app.use((req, res, next) => {
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  next();
});

// 3. Input sanitization — prevent XSS via WebSocket messages
const createDOMPurify = require('dompurify');
const { JSDOM } = require('jsdom');
const window = new JSDOM('').window;
const DOMPurify = createDOMPurify(window);

function sanitizeMessage(content) {
  if (typeof content !== 'string') return content;
  return DOMPurify.sanitize(content, { ALLOWED_TAGS: [] }); // strip all HTML
}

// 4. Protect against JSON injection and prototype pollution
function safeParse(data) {
  try {
    const parsed = JSON.parse(data.toString());
    // Prevent prototype pollution
    if (parsed.__proto__ || parsed.constructor || parsed.prototype) {
      throw new Error('Prototype pollution attempt');
    }
    return parsed;
  } catch (err) {
    return null;
  }
}

// 5. Log suspicious activity
const suspiciousActivity = [];
function logSuspicious(event, ws, details) {
  const entry = {
    event,
    ip: ws._socket?.remoteAddress,
    userId: ws.user?.id,
    details,
    timestamp: new Date().toISOString(),
  };
  suspiciousActivity.push(entry);
  console.warn('Suspicious activity:', entry);
  // Send to security monitoring (e.g., SIEM, Datadog)
  securityMonitor.alert(entry);
}
```

---

## Security Checklist

```
Authentication:
  ✅ Verify JWT on WebSocket CONNECT (not just HTTP handshake)
  ✅ Use RS256 (asymmetric) for JWT — public key on WS server
  ✅ Short-lived tokens (15min) + refresh mechanism for long sessions
  ✅ Invalidate tokens on logout (Redis blacklist or short expiry)
  ✅ Rate limit authentication attempts

Authorization:
  ✅ Check room/channel membership on join
  ✅ Validate sender identity on every message (not just at connect)
  ✅ Server-side authorization — never trust client claims
  ✅ Audit log sensitive operations (admin broadcasts, kicks)

Transport:
  ✅ WSS (WebSocket over TLS) in production — never WS
  ✅ Validate Origin header against allowlist
  ✅ HSTS header on HTTP upgrade response
  ✅ Disable old TLS versions (only TLS 1.2+)

Input Validation:
  ✅ maxPayload limit at protocol level (256KB–1MB)
  ✅ Application-level content length limits
  ✅ Sanitize content before storage/broadcast (prevent stored XSS)
  ✅ Validate message type/structure (schema validation)
  ✅ Prevent prototype pollution in JSON parsing

Rate Limiting:
  ✅ Connection rate limit per IP (e.g., 10/min)
  ✅ Message rate limit per user (token bucket: 5/s sustained, 30 burst)
  ✅ Distributed rate limiting with Redis (multi-server)
  ✅ Slow down / ban repeat offenders

Infrastructure:
  ✅ Nginx/ALB with proper proxy_read_timeout
  ✅ Non-root process user in Docker/K8s
  ✅ Pod security contexts (readOnlyRootFilesystem)
  ✅ Network policies restricting inter-pod traffic
  ✅ Monitor connection counts and message rates
```

---

## Trade-offs Summary

| Strategy | Complexity | Scalability | Latency | Cost |
|----------|-----------|------------|---------|------|
| Sticky sessions | Low | Limited (stateful) | Low | Low |
| Redis Pub/Sub | Medium | High (horizontal) | +1 Redis RTT | Redis infra |
| Redis Streams | High | Very high | +1 Redis RTT | More complex |
| Single-server | None | None | Lowest | Simple |
| K8s + HPA | High | Elastic | Pod startup time | K8s complexity |

---

## Ghi chú – Keywords

- **WebTransport**: HTTP/3 (QUIC) based, lower latency than WebSocket, unreliable datagrams support — future alternative
- **WebSocket over HTTP/2**: không phổ biến, RFC 8441 (bootstrapping WS with HTTP/2)
- **QUIC**: UDP-based, connection migration (mobile networks), no head-of-line blocking
- **Envoy Proxy**: WebSocket support, better than Nginx for microservices (health check, circuit breaker)
- **Keywords**: Redis Cluster Pub/Sub (gossip protocol limitation), socket.io-redis-adapter, socket.io-sticky (nginx cookie), sticky bit, graceful shutdown drain, PROXY protocol (preserve real IP through LB), AWS API Gateway WebSocket ($connect/$disconnect/$default routes)
