# WebSocket Real-world Patterns

## Mục lục
1. [Chat Application](#1-chat-application)
2. [Live Dashboard – Metrics & Stock Ticker](#2-live-dashboard--metrics--stock-ticker)
3. [Collaborative Editing – CRDT/OT Concepts](#3-collaborative-editing--crdtot-concepts)
4. [Presence System – Online Users](#4-presence-system--online-users)
5. [Pub/Sub với Rooms & Topics](#5-pubsub-với-rooms--topics)
6. [Notification System – Fan-out](#6-notification-system--fan-out)

---

## 1. Chat Application

### 1.1 Architecture

```
Client A                  Server                    Client B
  │    ─── CONNECT ──────►│                              │
  │    ◄── welcome ────────│                              │
  │    ─── join room ─────►│                              │
  │                        │◄── CONNECT ─────────────────│
  │                        │─── user_joined ────────────►│
  │    ─── send msg ──────►│                              │
  │    ◄── ack ────────────│                              │
  │                        │─── broadcast msg ──────────►│
  │                        │── save to DB ────► MongoDB   │
```

### 1.2 Server (Node.js + Socket.IO)

```javascript
// chat-server.js
const messageRepository = require('./repositories/message.repository');

io.on('connection', (socket) => {
  const user = socket.data.user;

  // ── Join/Leave Rooms ──────────────────────────────────────────────────────
  socket.on('chat:join', async ({ roomId }, ack) => {
    // Auth: check user has access to room
    const room = await roomService.findById(roomId);
    if (!room || !room.members.includes(user.id)) {
      ack?.({ error: 'Access denied' });
      return;
    }

    await socket.join(`room:${roomId}`);
    
    // Load and send message history
    const history = await messageRepository.findLast(roomId, 50);
    socket.emit('chat:history', { roomId, messages: history });

    // Notify others
    socket.to(`room:${roomId}`).emit('chat:presence', {
      userId: user.id,
      username: user.name,
      event: 'joined',
    });

    ack?.({ ok: true, memberCount: io.sockets.adapter.rooms.get(`room:${roomId}`)?.size });
  });

  socket.on('chat:leave', ({ roomId }) => {
    socket.leave(`room:${roomId}`);
    socket.to(`room:${roomId}`).emit('chat:presence', {
      userId: user.id,
      username: user.name,
      event: 'left',
    });
  });

  // ── Send Message ──────────────────────────────────────────────────────────
  socket.on('chat:message', async ({ roomId, content, clientMsgId }, ack) => {
    // Idempotency: reject duplicate messages
    const existing = await messageRepository.findByClientId(clientMsgId);
    if (existing) {
      ack?.({ ok: true, messageId: existing.id, duplicate: true });
      return;
    }

    // Validate
    if (!content?.trim() || content.length > 4096) {
      ack?.({ error: 'Invalid content' });
      return;
    }

    // Persist first, then broadcast
    const message = await messageRepository.create({
      roomId,
      senderId: user.id,
      senderName: user.name,
      content: sanitize(content), // strip HTML
      clientMsgId,
      createdAt: new Date(),
    });

    const payload = {
      id: message.id,
      roomId,
      senderId: user.id,
      senderName: user.name,
      content: message.content,
      createdAt: message.createdAt.toISOString(),
    };

    // Broadcast to room (excluding sender)
    socket.to(`room:${roomId}`).emit('chat:message', payload);

    // Acknowledge to sender with server-assigned message ID
    ack?.({ ok: true, messageId: message.id, createdAt: payload.createdAt });
  });

  // ── Typing Indicator ──────────────────────────────────────────────────────
  // Throttle on client-side; debounce stop on server
  const typingTimers = new Map(); // roomId → timeout

  socket.on('chat:typing:start', ({ roomId }) => {
    socket.to(`room:${roomId}`).emit('chat:typing', {
      userId: user.id,
      username: user.name,
      isTyping: true,
    });

    // Auto-stop after 5s if client doesn't send 'stop'
    if (typingTimers.has(roomId)) clearTimeout(typingTimers.get(roomId));
    typingTimers.set(roomId, setTimeout(() => {
      socket.to(`room:${roomId}`).emit('chat:typing', {
        userId: user.id,
        isTyping: false,
      });
      typingTimers.delete(roomId);
    }, 5000));
  });

  socket.on('chat:typing:stop', ({ roomId }) => {
    clearTimeout(typingTimers.get(roomId));
    typingTimers.delete(roomId);
    socket.to(`room:${roomId}`).emit('chat:typing', {
      userId: user.id,
      isTyping: false,
    });
  });

  // ── Read Receipts ─────────────────────────────────────────────────────────
  socket.on('chat:read', async ({ roomId, lastMessageId }) => {
    await messageRepository.markRead(roomId, user.id, lastMessageId);
    socket.to(`room:${roomId}`).emit('chat:read', {
      userId: user.id,
      roomId,
      lastMessageId,
    });
  });

  socket.on('disconnect', () => {
    typingTimers.forEach((timer, roomId) => {
      clearTimeout(timer);
      socket.to(`room:${roomId}`).emit('chat:typing', { userId: user.id, isTyping: false });
    });
    typingTimers.clear();
  });
});
```

### 1.3 Client (Angular Service)

```typescript
// chat.service.ts
@Injectable({ providedIn: 'root' })
export class ChatService {
  private messages$ = new Map<string, BehaviorSubject<ChatMessage[]>>();
  private typingUsers$ = new Map<string, BehaviorSubject<TypingUser[]>>();

  constructor(private socket: StompService) {}

  joinRoom(roomId: string): Observable<void> {
    return new Observable(observer => {
      this.socket.emit('chat:join', { roomId }, (response) => {
        if (response.error) {
          observer.error(new Error(response.error));
        } else {
          observer.next();
          observer.complete();
        }
      });
    });
  }

  sendMessage(roomId: string, content: string): Observable<{ messageId: string }> {
    const clientMsgId = crypto.randomUUID();
    
    // Optimistic update
    const tempMsg: ChatMessage = {
      id: `temp-${clientMsgId}`,
      roomId,
      content,
      senderId: this.currentUserId,
      senderName: this.currentUserName,
      createdAt: new Date().toISOString(),
      pending: true,
    };
    this.addMessage(roomId, tempMsg);

    return new Observable(observer => {
      this.socket.emit('chat:message', { roomId, content, clientMsgId }, (ack) => {
        if (ack.error) {
          // Remove optimistic message
          this.removeMessage(roomId, tempMsg.id);
          observer.error(new Error(ack.error));
        } else {
          // Replace temp with confirmed
          this.replaceMessage(roomId, tempMsg.id, {
            ...tempMsg,
            id: ack.messageId,
            createdAt: ack.createdAt,
            pending: false,
          });
          observer.next({ messageId: ack.messageId });
          observer.complete();
        }
      });
    });
  }

  getMessages(roomId: string): Observable<ChatMessage[]> {
    if (!this.messages$.has(roomId)) {
      this.messages$.set(roomId, new BehaviorSubject<ChatMessage[]>([]));
    }
    return this.messages$.get(roomId)!.asObservable();
  }
}
```

---

## 2. Live Dashboard – Metrics & Stock Ticker

### 2.1 Streaming Metrics Pipeline

```javascript
// metrics-server.js
// Architecture: Data source → Transform → Throttle → Broadcast

class MetricsStreamer {
  #subscribers = new Set(); // set of socket IDs subscribed to metrics
  #latestMetrics = {};
  #broadcastTimer = null;

  subscribe(socketId) {
    this.#subscribers.add(socketId);
    if (this.#subscribers.size === 1) {
      this.startPolling(); // start collecting only when someone is watching
    }
    // Send current snapshot immediately
    return this.#latestMetrics;
  }

  unsubscribe(socketId) {
    this.#subscribers.delete(socketId);
    if (this.#subscribers.size === 0) {
      this.stopPolling(); // stop collecting when nobody is watching
    }
  }

  startPolling() {
    // Collect from multiple sources in parallel
    this.#broadcastTimer = setInterval(async () => {
      const [cpu, memory, requests, errors] = await Promise.all([
        metricsCollector.getCpuUsage(),
        metricsCollector.getMemoryUsage(),
        metricsCollector.getRequestRate(),
        metricsCollector.getErrorRate(),
      ]);

      this.#latestMetrics = {
        timestamp: Date.now(),
        cpu,       // { usage: 45.2, cores: [40, 50, 45, 46] }
        memory,    // { used: 2048, total: 4096, percentage: 50 }
        requests,  // { rate: 1200, p50: 45, p95: 120, p99: 350 }
        errors,    // { rate: 2, count5m: 10 }
      };

      this.broadcast();
    }, 1000); // collect every 1s
  }

  stopPolling() {
    clearInterval(this.#broadcastTimer);
  }

  broadcast() {
    if (this.#subscribers.size === 0) return;
    const payload = JSON.stringify({
      type: 'metrics:update',
      data: this.#latestMetrics,
    });
    this.#subscribers.forEach(socketId => {
      const socket = io.sockets.sockets.get(socketId);
      if (socket?.connected) {
        socket.emit('metrics:update', this.#latestMetrics);
      } else {
        this.#subscribers.delete(socketId); // cleanup stale
      }
    });
  }
}

const streamer = new MetricsStreamer();

io.on('connection', (socket) => {
  socket.on('metrics:subscribe', () => {
    const snapshot = streamer.subscribe(socket.id);
    socket.emit('metrics:snapshot', snapshot); // immediate first paint
  });

  socket.on('metrics:unsubscribe', () => streamer.unsubscribe(socket.id));
  socket.on('disconnect', () => streamer.unsubscribe(socket.id));
});
```

### 2.2 Stock Ticker với Throttling

```javascript
// stock-ticker.js
// Problem: price updates too frequent (100ms) but client only needs 500ms

class StockTicker {
  #priceCache = new Map();      // symbol → latest price
  #dirtySymbols = new Set();    // changed since last broadcast
  #roomSubscriptions = new Map(); // symbol → Set<roomId>

  updatePrice(symbol, price, change, volume) {
    this.#priceCache.set(symbol, { symbol, price, change, changePercent: change/price*100, volume, ts: Date.now() });
    this.#dirtySymbols.add(symbol);
    // Don't broadcast immediately — batched below
  }

  startBroadcastLoop() {
    // Broadcast at fixed 500ms interval (smooth UX, reduce network load)
    setInterval(() => {
      if (this.#dirtySymbols.size === 0) return;

      const updates = [];
      this.#dirtySymbols.forEach(symbol => {
        updates.push(this.#priceCache.get(symbol));
        
        // Broadcast to rooms subscribed to this symbol
        const rooms = this.#roomSubscriptions.get(symbol) ?? new Set();
        rooms.forEach(roomId => {
          io.to(roomId).emit('stock:price', this.#priceCache.get(symbol));
        });
      });
      
      // Also broadcast all dirty to 'stock:all' room
      if (updates.length > 0) {
        io.to('stock:all').emit('stock:batch', updates);
      }
      
      this.#dirtySymbols.clear();
    }, 500);
  }

  subscribe(socketId, symbol) {
    const roomId = `stock:${symbol}`;
    if (!this.#roomSubscriptions.has(symbol)) {
      this.#roomSubscriptions.set(symbol, new Set());
    }
    this.#roomSubscriptions.get(symbol).add(roomId);
    
    const socket = io.sockets.sockets.get(socketId);
    socket?.join(roomId);
    
    // Send current price immediately
    return this.#priceCache.get(symbol);
  }
}
```

### 2.3 Angular Chart Component

```typescript
// live-chart.component.ts
@Component({
  template: `
    <div class="metrics-grid">
      <app-gauge label="CPU" [value]="metrics()?.cpu?.usage ?? 0" [max]="100" unit="%" />
      <app-gauge label="Memory" [value]="memoryPercent()" [max]="100" unit="%" />
      <app-sparkline label="Req/s" [data]="requestHistory()" />
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LiveChartComponent implements OnInit, OnDestroy {
  private metricsService = inject(MetricsWebSocketService);

  metrics = toSignal(this.metricsService.metrics$, { initialValue: null });
  memoryPercent = computed(() => {
    const m = this.metrics()?.memory;
    return m ? Math.round((m.used / m.total) * 100) : 0;
  });

  // Keep last 60 data points for sparkline
  private history = signal<number[]>([]);
  requestHistory = this.history.asReadonly();

  private historyEffect = effect(() => {
    const rate = this.metrics()?.requests?.rate;
    if (rate != null) {
      this.history.update(h => [...h.slice(-59), rate]);
    }
  });

  ngOnInit(): void { this.metricsService.subscribe(); }
  ngOnDestroy(): void { this.metricsService.unsubscribe(); }
}
```

---

## 3. Collaborative Editing – CRDT/OT Concepts

### 3.1 Operational Transformation (OT) cơ bản

```javascript
// ot-server.js
// OT: transform concurrent operations so they converge to same state

// Operation types
// { type: 'insert', pos: 5, text: 'hello', userId, revision }
// { type: 'delete', pos: 5, len: 3, userId, revision }

class OTDocument {
  #content = '';
  #revision = 0;
  #history = []; // array of committed operations

  apply(op) {
    if (op.type === 'insert') {
      this.#content = this.#content.slice(0, op.pos) + op.text + this.#content.slice(op.pos);
    } else if (op.type === 'delete') {
      this.#content = this.#content.slice(0, op.pos) + this.#content.slice(op.pos + op.len);
    }
    this.#revision++;
    this.#history.push({ ...op, revision: this.#revision });
    return this.#revision;
  }

  // Transform op against concurrent ops that happened since op.revision
  transform(op) {
    let transformed = { ...op };
    const concurrentOps = this.#history.filter(h => h.revision > op.revision);
    
    for (const concurrent of concurrentOps) {
      transformed = this.transformAgainst(transformed, concurrent);
    }
    return transformed;
  }

  transformAgainst(op, against) {
    if (op.type === 'insert' && against.type === 'insert') {
      // Both insert: if against is at same pos or earlier, shift op
      if (against.pos <= op.pos) {
        return { ...op, pos: op.pos + against.text.length };
      }
    } else if (op.type === 'insert' && against.type === 'delete') {
      if (against.pos < op.pos) {
        return { ...op, pos: Math.max(against.pos, op.pos - against.len) };
      }
    } else if (op.type === 'delete' && against.type === 'insert') {
      if (against.pos <= op.pos) {
        return { ...op, pos: op.pos + against.text.length };
      }
    } else if (op.type === 'delete' && against.type === 'delete') {
      if (against.pos < op.pos) {
        return { ...op, pos: Math.max(against.pos, op.pos - against.len) };
      }
    }
    return op;
  }

  getState() {
    return { content: this.#content, revision: this.#revision };
  }
}

// WebSocket handler
const documents = new Map(); // docId → OTDocument

io.on('connection', (socket) => {
  socket.on('doc:join', ({ docId }, ack) => {
    if (!documents.has(docId)) documents.set(docId, new OTDocument());
    socket.join(`doc:${docId}`);
    ack(documents.get(docId).getState());
  });

  socket.on('doc:op', ({ docId, op }) => {
    const doc = documents.get(docId);
    if (!doc) return;

    // Transform against concurrent operations
    const transformed = doc.transform(op);
    const newRevision = doc.apply(transformed);

    // Broadcast transformed op to other clients
    socket.to(`doc:${docId}`).emit('doc:op', {
      ...transformed,
      revision: newRevision,
      userId: socket.data.user.id,
    });

    // Ack to sender with new revision
    socket.emit('doc:op:ack', { clientRevision: op.revision, serverRevision: newRevision });
  });
});
```

### 3.2 CRDT – Conflict-free Replicated Data Type (concept)

```javascript
// crdt-list.js
// CRDT: operations commutative/idempotent → no coordination needed

// Last-Write-Wins Register (LWW-Register)
class LWWRegister {
  #value = null;
  #timestamp = 0;
  #nodeId;

  constructor(nodeId) { this.#nodeId = nodeId; }

  set(value) {
    const ts = Date.now();
    this.#value = value;
    this.#timestamp = ts;
    return { value, timestamp: ts, nodeId: this.#nodeId };
  }

  merge(remote) {
    // Last write wins (higher timestamp or higher nodeId for tie-breaking)
    if (remote.timestamp > this.#timestamp ||
        (remote.timestamp === this.#timestamp && remote.nodeId > this.#nodeId)) {
      this.#value = remote.value;
      this.#timestamp = remote.timestamp;
    }
  }

  get() { return this.#value; }
}

// Grow-only Counter (G-Counter)
class GCounter {
  #counts = {}; // nodeId → count

  constructor(nodeId) {
    this.#nodeId = nodeId;
    this.#counts[nodeId] = 0;
  }

  increment() {
    this.#counts[this.#nodeId]++;
    return this.state();
  }

  merge(remote) {
    // Take max of each node's count (monotonic → safe to merge anytime)
    for (const [node, count] of Object.entries(remote.counts)) {
      this.#counts[node] = Math.max(this.#counts[node] ?? 0, count);
    }
  }

  value() {
    return Object.values(this.#counts).reduce((a, b) => a + b, 0);
  }

  state() { return { counts: { ...this.#counts } }; }
}

// In practice: use Yjs or Automerge (battle-tested CRDT libraries)
// const Y = require('yjs');
// const ydoc = new Y.Doc();
// const ytext = ydoc.getText('content');
// ytext.insert(0, 'Hello'); // merge with Y.applyUpdate()
```

---

## 4. Presence System – Online Users

### 4.1 Architecture

```
Client connects → join presence channel → broadcast "online"
Client disconnects → broadcast "offline" + cleanup after grace period
Server track: userId → { socketIds: Set, lastSeen, metadata }

Problem: user opens 2 tabs → 2 sockets
  Only emit "offline" when ALL sockets for user disconnect
```

### 4.2 Implementation

```javascript
// presence.js
class PresenceManager {
  // userId → { sockets: Set<socketId>, metadata: object, lastSeen: Date }
  #userSessions = new Map();
  #disconnectTimers = new Map(); // userId → timer (grace period)
  #GRACE_PERIOD = 5000; // 5s — handle brief reconnects (refresh tab)

  async onConnect(socket) {
    const userId = socket.data.user.id;
    const metadata = {
      username: socket.data.user.name,
      avatar: socket.data.user.avatar,
      device: socket.handshake.headers['user-agent'],
    };

    // Cancel disconnect timer if user reconnected quickly
    if (this.#disconnectTimers.has(userId)) {
      clearTimeout(this.#disconnectTimers.get(userId));
      this.#disconnectTimers.delete(userId);
    }

    const wasOnline = this.#userSessions.has(userId);
    
    if (!wasOnline) {
      this.#userSessions.set(userId, { sockets: new Set(), metadata, lastSeen: new Date() });
      // Publish "online" event only on first socket
      await this.publishPresence(userId, 'online', metadata);
    }
    
    this.#userSessions.get(userId).sockets.add(socket.id);
    this.#userSessions.get(userId).lastSeen = new Date();
    
    return wasOnline ? null : 'online'; // null if already online (multi-tab)
  }

  async onDisconnect(socket) {
    const userId = socket.data.user.id;
    const session = this.#userSessions.get(userId);
    if (!session) return;

    session.sockets.delete(socket.id);

    if (session.sockets.size === 0) {
      // Start grace period — brief reconnect won't show as offline
      const timer = setTimeout(async () => {
        this.#userSessions.delete(userId);
        this.#disconnectTimers.delete(userId);
        await this.publishPresence(userId, 'offline', {
          ...session.metadata,
          lastSeen: new Date().toISOString(),
        });
      }, this.#GRACE_PERIOD);
      
      this.#disconnectTimers.set(userId, timer);
    }
  }

  async publishPresence(userId, status, metadata) {
    // Broadcast to all rooms user is a member of
    const userRooms = await roomService.getUserRooms(userId);
    userRooms.forEach(roomId => {
      io.to(`room:${roomId}`).emit('presence:update', { userId, status, ...metadata });
    });

    // Store in Redis for new joiners to get current presence
    if (status === 'online') {
      await redis.hset('presence', userId, JSON.stringify({ status, ...metadata, since: Date.now() }));
    } else {
      await redis.hdel('presence', userId);
    }
  }

  async getOnlineUsers(roomId) {
    const members = await roomService.getMembers(roomId);
    const onlineMembers = members.filter(m => this.#userSessions.has(m.id));
    
    // Also check Redis for presence from other server instances
    const redisPresence = await redis.hmget('presence', ...members.map(m => m.id));
    
    return members.map((member, i) => ({
      ...member,
      online: this.#userSessions.has(member.id) || redisPresence[i] !== null,
    }));
  }
}

const presenceManager = new PresenceManager();

io.on('connection', async (socket) => {
  await presenceManager.onConnect(socket);

  // When user joins a room, send them current presence list
  socket.on('room:join', async ({ roomId }) => {
    const users = await presenceManager.getOnlineUsers(roomId);
    socket.emit('presence:snapshot', { roomId, users });
  });

  socket.on('disconnect', () => presenceManager.onDisconnect(socket));
});
```

---

## 5. Pub/Sub với Rooms & Topics

### 5.1 Hierarchical Topics

```javascript
// topic-router.js
// Topic pattern: category:subcategory:id
// e.g., "orders:status:order-123", "inventory:sku:ABC"

class TopicRouter {
  // Wildcard subscriptions: "orders:*" matches "orders:status:order-123"
  #wildcardSubs = new Map(); // pattern → Set<socketId>
  #exactSubs = new Map();    // topic → Set<socketId>

  subscribe(socketId, topic) {
    const socket = io.sockets.sockets.get(socketId);
    if (!socket) return;

    if (topic.includes('*')) {
      if (!this.#wildcardSubs.has(topic)) this.#wildcardSubs.set(topic, new Set());
      this.#wildcardSubs.get(topic).add(socketId);
    } else {
      socket.join(`topic:${topic}`);
    }
  }

  publish(topic, data) {
    // Exact match via Socket.IO rooms
    io.to(`topic:${topic}`).emit('topic:message', { topic, data });

    // Wildcard matches
    this.#wildcardSubs.forEach((sockets, pattern) => {
      if (this.matchesPattern(topic, pattern)) {
        sockets.forEach(socketId => {
          io.sockets.sockets.get(socketId)?.emit('topic:message', { topic, data });
        });
      }
    });

    // Hierarchical: publish to parent topics too
    // "orders:status:order-123" also publishes to "orders:status" and "orders"
    const parts = topic.split(':');
    for (let i = parts.length - 1; i > 0; i--) {
      const parentTopic = parts.slice(0, i).join(':');
      io.to(`topic:${parentTopic}`).emit('topic:message', { topic, data, originalTopic: topic });
    }
  }

  matchesPattern(topic, pattern) {
    const regexStr = pattern.replace(/\*/g, '[^:]+').replace(/\*\*/g, '.+');
    return new RegExp(`^${regexStr}$`).test(topic);
  }
}

// Usage in event handlers:
const router = new TopicRouter();

// Order service publishes when order status changes
orderService.on('statusChange', (order) => {
  router.publish(`orders:status:${order.id}`, {
    orderId: order.id,
    status: order.status,
    updatedAt: new Date().toISOString(),
  });
});

// Client subscribes
socket.on('topic:subscribe', ({ topic }) => {
  router.subscribe(socket.id, topic);
});
```

### 5.2 Redis Pub/Sub cho Multi-server

```javascript
// redis-pubsub.js
const redis = require('redis');

const publisher = redis.createClient({ url: process.env.REDIS_URL });
const subscriber = publisher.duplicate();

await Promise.all([publisher.connect(), subscriber.connect()]);

// Subscribe to cross-server events
await subscriber.subscribe('ws:events', (message) => {
  const event = JSON.parse(message);
  
  switch (event.type) {
    case 'broadcast:room':
      // Forward to local clients in this room
      io.to(event.roomId).emit(event.event, event.data);
      break;
    case 'broadcast:user':
      io.to(`user:${event.userId}`).emit(event.event, event.data);
      break;
    case 'broadcast:all':
      io.emit(event.event, event.data);
      break;
  }
});

// Publish from any service
async function publishToRoom(roomId, event, data) {
  await publisher.publish('ws:events', JSON.stringify({
    type: 'broadcast:room',
    roomId,
    event,
    data,
  }));
}

// e.g., from a REST API handler when an order ships:
app.post('/api/orders/:id/ship', async (req, res) => {
  const order = await orderService.ship(req.params.id);
  // Notify the customer (who may be on a different WebSocket server)
  await publishToRoom(`user:${order.customerId}`, 'order:shipped', {
    orderId: order.id,
    trackingNumber: order.trackingNumber,
  });
  res.json(order);
});
```

---

## 6. Notification System – Fan-out

### 6.1 Fan-out Strategies

```
Fan-out on Write (Push):
  - When event occurs → immediately push to all subscribers
  - Pro: low read latency
  - Con: write amplification (1 event → N writes for N subscribers)
  - Use: real-time systems, ≤10k subscribers per event

Fan-out on Read (Pull):
  - Store event once → each subscriber fetches on connect/poll
  - Pro: write is cheap (1 write)
  - Con: read amplification at connection time
  - Use: large fan-out (millions of subscribers), news feeds
```

```javascript
// notification-server.js
class NotificationService {
  // Fan-out on write for real-time delivery
  async notify(userId, notification) {
    const payload = {
      id: generateId(),
      userId,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      data: notification.data,
      createdAt: new Date().toISOString(),
      read: false,
    };

    // Persist (fan-out on read for new connections)
    await notificationRepo.save(payload);

    // Fan-out on write for connected clients
    io.to(`user:${userId}`).emit('notification:new', payload);

    // Push notification if offline (via FCM/APNs)
    const isOnline = await presenceService.isOnline(userId);
    if (!isOnline) {
      await pushNotificationService.send(userId, {
        title: payload.title,
        body: payload.body,
        data: { notificationId: payload.id },
      });
    }

    return payload;
  }

  // Batch notification for events like "5 people liked your post"
  async notifyBatch(userIds, notification) {
    // Chunk to avoid overwhelming event loop
    const CHUNK_SIZE = 100;
    for (let i = 0; i < userIds.length; i += CHUNK_SIZE) {
      const chunk = userIds.slice(i, i + CHUNK_SIZE);
      await Promise.allSettled(chunk.map(userId => this.notify(userId, notification)));
    }
  }

  // Fan-out on read: load unread when user connects
  async loadUnread(userId, limit = 20) {
    return notificationRepo.findUnread(userId, limit);
  }
}

io.on('connection', async (socket) => {
  const userId = socket.data.user.id;
  
  // Send unread notifications on connect (fan-out on read)
  const unread = await notificationService.loadUnread(userId);
  if (unread.length > 0) {
    socket.emit('notification:unread', unread);
  }

  socket.on('notification:read', async ({ notificationId }) => {
    await notificationRepo.markRead(notificationId, userId);
    socket.emit('notification:read:ack', { notificationId });
  });

  socket.on('notification:read:all', async () => {
    const count = await notificationRepo.markAllRead(userId);
    socket.emit('notification:read:all:ack', { count });
  });
});
```

---

## Trade-offs Summary

| Pattern | Complexity | Scalability | Real-time Latency | Consistency |
|---------|-----------|------------|------------------|-------------|
| Chat | Medium | Medium (sticky/Redis) | Very low | At-least-once with ack |
| Live Dashboard | Low | High (broadcast) | ~500ms (batched) | Eventual (latest wins) |
| Collaborative Edit (OT) | High | Low (single server) | Very low | Strong (transform) |
| Collaborative Edit (CRDT) | Medium | High (no coord) | Very low | Eventual (convergent) |
| Presence | Medium | Medium (grace period) | ~5s (grace) | Eventual |
| Notification | Low | High (fan-out) | Immediate | At-least-once |

---

## Ghi chú – Keywords tiếp theo

- **websocket_reliability.md**: Reconnection exponential backoff, Heartbeat/Ping-Pong, Message ordering & deduplication, At-least-once delivery, Backpressure, Offline queue, Session resumption
- **Keywords**: Yjs CRDT, Automerge, operational transformation, ShareDB (OT library), Socket.IO connection state recovery, presence heartbeat, notification fan-out, Redis Sorted Set for message ordering, sequence numbers
