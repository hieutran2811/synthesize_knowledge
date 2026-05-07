# WebSocket Reliability

## Mục lục
1. [Reconnection với Exponential Backoff](#1-reconnection-với-exponential-backoff)
2. [Heartbeat / Ping-Pong](#2-heartbeat--ping-pong)
3. [Message Ordering & Deduplication](#3-message-ordering--deduplication)
4. [At-least-once Delivery](#4-at-least-once-delivery)
5. [Backpressure](#5-backpressure)
6. [Offline Queue & Session Resumption](#6-offline-queue--session-resumption)

---

## 1. Reconnection với Exponential Backoff

### 1.1 Vì sao cần backoff?

```
Không backoff (retry ngay lập tức):
  Client 1 ─── connect ──► Server DIES
  Client 1 ─── retry immediately ──► fail
  Client 1 ─── retry immediately ──► fail
  ... 10,000 clients đồng loạt reconnect → "thundering herd" → server crash

Exponential backoff + jitter:
  attempt 0: wait 1s  ± random(0, 1)s
  attempt 1: wait 2s  ± random(0, 2)s
  attempt 2: wait 4s  ± random(0, 4)s
  attempt 3: wait 8s  ± ...
  ...capped at maxDelay (e.g., 30s)
  → clients spread out → server recovers gracefully
```

### 1.2 Robust WebSocket Client

```typescript
// reliable-ws-client.ts
type MessageHandler = (data: unknown) => void;
type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'closing';

interface ReconnectOptions {
  baseDelay?: number;      // ms, default 1000
  maxDelay?: number;       // ms, default 30000
  maxAttempts?: number;    // default Infinity
  jitterFactor?: number;   // 0-1, default 0.3
  backoffFactor?: number;  // default 2 (exponential)
}

class ReliableWebSocket {
  private ws: WebSocket | null = null;
  private state: ConnectionState = 'disconnected';
  private attemptCount = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private intentionalClose = false;
  private messageHandlers = new Map<string, MessageHandler[]>();

  constructor(
    private readonly url: string,
    private readonly options: ReconnectOptions = {},
  ) {
    this.options = {
      baseDelay: 1_000,
      maxDelay: 30_000,
      maxAttempts: Infinity,
      jitterFactor: 0.3,
      backoffFactor: 2,
      ...options,
    };
  }

  connect(): void {
    if (this.state === 'connecting' || this.state === 'connected') return;
    this.intentionalClose = false;
    this.doConnect();
  }

  private doConnect(): void {
    this.state = 'connecting';
    this.emit('stateChange', { state: 'connecting', attempt: this.attemptCount });

    try {
      this.ws = new WebSocket(this.url);
    } catch (err) {
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.state = 'connected';
      this.attemptCount = 0; // reset on success
      this.emit('stateChange', { state: 'connected' });
      this.emit('connected', {});
    };

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        this.emit('message', msg);
        if (msg.type) this.emit(`message:${msg.type}`, msg);
      } catch {
        this.emit('rawMessage', event.data);
      }
    };

    this.ws.onerror = () => {
      // Error event always precedes close event — handle reconnect in onclose
    };

    this.ws.onclose = (event) => {
      this.state = 'disconnected';
      this.emit('stateChange', { state: 'disconnected', code: event.code });

      if (this.intentionalClose) {
        this.emit('closed', { code: event.code, reason: event.reason });
        return;
      }

      this.scheduleReconnect();
    };
  }

  private scheduleReconnect(): void {
    const { baseDelay, maxDelay, maxAttempts, jitterFactor, backoffFactor } = this.options;

    if (this.attemptCount >= maxAttempts!) {
      this.emit('maxAttemptsReached', { attempts: this.attemptCount });
      return;
    }

    const exponentialDelay = Math.min(
      baseDelay! * Math.pow(backoffFactor!, this.attemptCount),
      maxDelay!,
    );
    const jitter = exponentialDelay * jitterFactor! * Math.random();
    const delay = exponentialDelay + jitter;

    this.attemptCount++;
    this.emit('reconnecting', { attempt: this.attemptCount, delay: Math.round(delay) });

    this.reconnectTimer = setTimeout(() => this.doConnect(), delay);
  }

  send(data: object): boolean {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
      return true;
    }
    return false;
  }

  close(code = 1000, reason = 'Normal closure'): void {
    this.intentionalClose = true;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.state = 'closing';
    this.ws?.close(code, reason);
  }

  // Simple event emitter
  private listeners = new Map<string, Function[]>();
  on(event: string, handler: Function): () => void {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event)!.push(handler);
    return () => this.off(event, handler);
  }
  off(event: string, handler: Function): void {
    const handlers = this.listeners.get(event) ?? [];
    this.listeners.set(event, handlers.filter(h => h !== handler));
  }
  private emit(event: string, data: unknown): void {
    this.listeners.get(event)?.forEach(h => h(data));
  }
}

// Usage
const client = new ReliableWebSocket('wss://api.example.com/ws', {
  maxAttempts: 20,
  baseDelay: 500,
  maxDelay: 60_000,
  jitterFactor: 0.5,
});

client.on('connected', () => console.log('Ready'));
client.on('reconnecting', ({ attempt, delay }) =>
  console.log(`Reconnecting in ${delay}ms (attempt ${attempt})`));
client.on('maxAttemptsReached', () => {
  console.error('Server unreachable — giving up');
  showOfflineUI();
});
client.on('message:chat', (msg) => renderChatMessage(msg));
client.connect();
```

### 1.3 Network detection

```typescript
// Pause reconnect when network is offline; resume when back online
window.addEventListener('offline', () => {
  client.close(1001, 'Network offline');
  showOfflineBanner();
});

window.addEventListener('online', () => {
  hideOfflineBanner();
  client.connect(); // attempt reconnect immediately (network restored)
});

// Page Visibility API: pause when tab hidden, resume when visible
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    if (client.state === 'disconnected') client.connect();
  }
});
```

---

## 2. Heartbeat / Ping-Pong

### 2.1 Vì sao cần heartbeat?

```
Problem: TCP connection "silently dead"
  - NAT/firewall tables timeout idle connections (typically 30s–5min)
  - Middleware proxies (Nginx, AWS ELB) also have idle timeouts
  - Connection appears OPEN on both sides, but no data flows
  
Detection without heartbeat:
  App waits 10 minutes to detect dead connection
  User sees "connected" indicator but messages don't arrive
  
With heartbeat:
  Detect dead connection in ~30s (ping interval + timeout)
  Trigger reconnect before user notices
```

### 2.2 WebSocket Protocol Ping/Pong (opcodes 0x9/0xA)

```javascript
// server.js — protocol-level ping (opcode 0x9)
// Browser WebSocket API does NOT expose ping/pong — server-initiated only
const { WebSocketServer } = require('ws');
const wss = new WebSocketServer({ server });

const PING_INTERVAL = 30_000;  // 30s
const PONG_TIMEOUT = 10_000;   // wait 10s for pong before terminating

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.pongTimer = null;

  ws.on('pong', () => {
    ws.isAlive = true;
    clearTimeout(ws.pongTimer); // received in time
  });
});

// Heartbeat loop
const heartbeat = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      // Never received pong — connection is dead
      console.log('Terminating dead connection');
      ws.terminate();
      return;
    }

    ws.isAlive = false; // reset; expect pong to set it back true
    ws.ping();          // send protocol-level ping frame

    // Timeout: if pong not received within 10s, terminate
    ws.pongTimer = setTimeout(() => {
      if (!ws.isAlive) {
        console.log('Pong timeout — terminating');
        ws.terminate();
      }
    }, PONG_TIMEOUT);
  });
}, PING_INTERVAL);

wss.on('close', () => clearInterval(heartbeat));
```

### 2.3 Application-level Heartbeat (for Spring STOMP, Socket.IO)

```typescript
// application-level ping (when protocol ping not accessible)
// Both sides track and respond to application messages

// Client
class HeartbeatManager {
  private pingInterval: ReturnType<typeof setInterval> | null = null;
  private pongTimeout: ReturnType<typeof setTimeout> | null = null;
  private missedPongs = 0;
  private readonly MAX_MISSED = 2;

  constructor(
    private readonly sendFn: (msg: object) => void,
    private readonly onDead: () => void,
    private readonly intervalMs = 30_000,
    private readonly timeoutMs = 10_000,
  ) {}

  start(): void {
    this.pingInterval = setInterval(() => this.sendPing(), this.intervalMs);
  }

  stop(): void {
    if (this.pingInterval) clearInterval(this.pingInterval);
    if (this.pongTimeout) clearTimeout(this.pongTimeout);
    this.missedPongs = 0;
  }

  onPong(): void {
    clearTimeout(this.pongTimeout!);
    this.missedPongs = 0;
  }

  private sendPing(): void {
    this.sendFn({ type: 'ping', ts: Date.now() });
    this.pongTimeout = setTimeout(() => {
      this.missedPongs++;
      if (this.missedPongs >= this.MAX_MISSED) {
        this.stop();
        this.onDead();
      }
    }, this.timeoutMs);
  }
}

// Server — respond to application-level pings
socket.on('message', (msg) => {
  if (msg.type === 'ping') {
    socket.send(JSON.stringify({ type: 'pong', ts: msg.ts, serverTs: Date.now() }));
  }
});

// Spring STOMP — built-in heartbeat
// In WebSocketConfig:
registry.enableSimpleBroker("/topic")
    .setHeartbeatValue(new long[]{10_000, 10_000}); // outgoing, incoming ms
```

### 2.4 Latency measurement

```typescript
// Measure round-trip latency using ping/pong timestamps
class LatencyMonitor {
  private pending = new Map<number, number>(); // pingTs → sentAt

  sendPing(ws: ReliableWebSocket): void {
    const ts = Date.now();
    this.pending.set(ts, performance.now());
    ws.send({ type: 'ping', ts });
  }

  onPong(pongData: { ts: number; serverTs: number }): void {
    const sentAt = this.pending.get(pongData.ts);
    if (sentAt == null) return;
    this.pending.delete(pongData.ts);

    const rtt = performance.now() - sentAt;
    const serverProcessing = pongData.serverTs - pongData.ts;
    const networkLatency = (rtt - serverProcessing) / 2;

    console.log(`RTT: ${rtt.toFixed(1)}ms, Network: ${networkLatency.toFixed(1)}ms`);
    // Report to metrics / update UI latency indicator
  }
}
```

---

## 3. Message Ordering & Deduplication

### 3.1 Sequence Numbers

```typescript
// Client: attach sequence number to every message
class SequencedSender {
  private seq = 0;
  private pendingAcks = new Map<number, { msg: object; sentAt: number; retries: number }>();
  private readonly ACK_TIMEOUT = 5_000;
  private readonly MAX_RETRIES = 3;

  send(ws: ReliableWebSocket, type: string, payload: object): void {
    const msg = { type, seq: ++this.seq, payload, ts: Date.now() };
    this.pendingAcks.set(msg.seq, { msg, sentAt: Date.now(), retries: 0 });
    ws.send(msg);

    // Schedule timeout for ack
    setTimeout(() => this.checkAck(ws, msg.seq), this.ACK_TIMEOUT);
  }

  onAck(ackSeq: number): void {
    this.pendingAcks.delete(ackSeq);
  }

  private checkAck(ws: ReliableWebSocket, seq: number): void {
    const pending = this.pendingAcks.get(seq);
    if (!pending) return; // already acked

    if (pending.retries >= this.MAX_RETRIES) {
      this.pendingAcks.delete(seq);
      console.error(`Message ${seq} failed after ${this.MAX_RETRIES} retries`);
      return;
    }

    pending.retries++;
    ws.send(pending.msg); // retransmit
    setTimeout(() => this.checkAck(ws, seq), this.ACK_TIMEOUT * (pending.retries + 1));
  }

  // On reconnect: resend all unacked messages in order
  resendPending(ws: ReliableWebSocket): void {
    const sorted = [...this.pendingAcks.entries()].sort(([a], [b]) => a - b);
    sorted.forEach(([, { msg }]) => ws.send(msg));
  }
}

// Server: track last processed seq per client to detect duplicates
class OrderedMessageProcessor {
  private lastSeq = new Map<string, number>(); // clientId → lastSeq
  private processedIds = new Set<string>(); // for larger dedup window

  process(clientId: string, message: { seq: number; type: string; payload: object }): boolean {
    const lastProcessed = this.lastSeq.get(clientId) ?? 0;

    if (message.seq <= lastProcessed) {
      // Duplicate (retransmit) — ack again but don't process
      console.log(`Duplicate message ${message.seq} from ${clientId}, ignoring`);
      return false; // signal: skip processing
    }

    if (message.seq > lastProcessed + 1) {
      // Gap: messages arrived out of order
      // Option 1: buffer and wait for missing
      // Option 2: process anyway and note gap (chat: acceptable)
      console.warn(`Gap detected: expected ${lastProcessed + 1}, got ${message.seq}`);
    }

    this.lastSeq.set(clientId, message.seq);
    return true; // signal: process this message
  }
}
```

### 3.2 Message ID Deduplication

```javascript
// server.js — idempotent message handling with Redis dedup
const DEDUP_WINDOW = 60; // seconds

async function processMessage(clientId, message) {
  const { clientMsgId, type, payload } = message;

  if (!clientMsgId) {
    await handleMessage(type, payload);
    return { ok: true };
  }

  // Check dedup window in Redis
  const key = `dedup:${clientId}:${clientMsgId}`;
  const existing = await redis.get(key);

  if (existing) {
    // Duplicate — return cached result
    return JSON.parse(existing);
  }

  // Process and cache result
  const result = await handleMessage(type, payload);
  
  // Store result for dedup window
  await redis.setEx(key, DEDUP_WINDOW, JSON.stringify(result));
  
  return result;
}
```

---

## 4. At-least-once Delivery

### 4.1 Acknowledgment Pattern

```
Delivery guarantees:
  At-most-once:  fire and forget (no ack), may lose messages
  At-least-once: ack required, may deliver duplicates → idempotent handlers needed
  Exactly-once:  at-least-once + deduplication = effectively exactly-once

Pattern:
  Sender → sends message with ID
  Receiver → processes + sends ack
  Sender → waits for ack, retransmits if timeout
  Receiver → checks dedup, skips if already processed
```

```typescript
// at-least-once-client.ts
class AtLeastOnceClient {
  private pendingMessages = new Map<string, PendingMessage>();
  private retryIntervals = new Map<string, ReturnType<typeof setInterval>>();

  constructor(private ws: ReliableWebSocket) {
    ws.on('message:ack', (ack: { msgId: string }) => this.onAck(ack.msgId));
    ws.on('connected', () => this.resendPending());
  }

  sendReliable(type: string, payload: object): Promise<void> {
    const msgId = crypto.randomUUID();
    
    return new Promise((resolve, reject) => {
      const message = { type, msgId, payload, ts: Date.now() };
      
      this.pendingMessages.set(msgId, { message, resolve, reject, attempts: 0 });
      this.sendWithRetry(msgId);
    });
  }

  private sendWithRetry(msgId: string): void {
    const pending = this.pendingMessages.get(msgId);
    if (!pending) return;

    if (pending.attempts >= 5) {
      this.cleanup(msgId);
      pending.reject(new Error(`Failed to deliver message ${msgId}`));
      return;
    }

    pending.attempts++;
    const sent = this.ws.send(pending.message);

    if (!sent) {
      // Not connected — message queued in pendingMessages, will resend on reconnect
      return;
    }

    // Schedule retry
    const delay = 1_000 * 2 ** (pending.attempts - 1); // 1s, 2s, 4s, 8s, 16s
    const timer = setTimeout(() => this.sendWithRetry(msgId), delay);
    this.retryIntervals.set(msgId, timer);
  }

  private onAck(msgId: string): void {
    const pending = this.pendingMessages.get(msgId);
    if (pending) {
      this.cleanup(msgId);
      pending.resolve();
    }
  }

  private cleanup(msgId: string): void {
    this.pendingMessages.delete(msgId);
    clearTimeout(this.retryIntervals.get(msgId)!);
    this.retryIntervals.delete(msgId);
  }

  private resendPending(): void {
    // On reconnect, resend all unacked messages
    this.pendingMessages.forEach((_, msgId) => {
      clearTimeout(this.retryIntervals.get(msgId)!);
      this.retryIntervals.delete(msgId);
      this.sendWithRetry(msgId);
    });
  }
}

// Server — idempotent handler
async function onMessage(socket, { type, msgId, payload }) {
  // 1. Check dedup
  const isDuplicate = await dedupService.check(socket.clientId, msgId);
  
  // 2. Always ack (even for duplicates — client needs to stop retrying)
  socket.send(JSON.stringify({ type: 'ack', msgId }));
  
  if (isDuplicate) return; // don't process again
  
  // 3. Process idempotently
  await handleMessage(type, payload);
  
  // 4. Mark as processed
  await dedupService.mark(socket.clientId, msgId);
}
```

---

## 5. Backpressure

### 5.1 Vấn đề

```
Slow consumer problem:
  Producer (server) sends 1000 msg/s
  Consumer (client) processes 100 msg/s
  → Server buffers grow → OOM / dropped connections
  
WebSocket.bufferedAmount = bytes queued but not yet sent by browser
  If growing → client cannot keep up
```

### 5.2 Client-side Backpressure

```typescript
// client-backpressure.ts
class BackpressureAwareClient {
  private readonly HIGH_WATERMARK = 64 * 1024;  // 64KB
  private readonly LOW_WATERMARK  = 16 * 1024;  // 16KB
  private paused = false;
  private onDrainCallbacks: Function[] = [];

  constructor(private ws: WebSocket) {
    setInterval(() => this.checkBackpressure(), 100);
  }

  send(data: object): boolean {
    if (this.ws.bufferedAmount > this.HIGH_WATERMARK) {
      console.warn('Backpressure: client buffer full, dropping message');
      return false;
    }
    this.ws.send(JSON.stringify(data));
    return true;
  }

  private checkBackpressure(): void {
    const buffered = this.ws.bufferedAmount;
    
    if (!this.paused && buffered > this.HIGH_WATERMARK) {
      this.paused = true;
      // Signal server to stop sending
      this.ws.send(JSON.stringify({ type: 'flow:pause' }));
    } else if (this.paused && buffered < this.LOW_WATERMARK) {
      this.paused = false;
      this.ws.send(JSON.stringify({ type: 'flow:resume' }));
      this.onDrainCallbacks.forEach(cb => cb());
      this.onDrainCallbacks = [];
    }
  }

  onDrain(callback: Function): void {
    if (!this.paused) {
      callback();
    } else {
      this.onDrainCallbacks.push(callback);
    }
  }
}
```

### 5.3 Server-side Flow Control

```javascript
// server-flow-control.js
class FlowControlledClient {
  #ws;
  #paused = false;
  #messageQueue = [];
  #MAX_QUEUE = 500;

  constructor(ws) {
    this.#ws = ws;
    ws.on('message', (data) => {
      const msg = JSON.parse(data);
      if (msg.type === 'flow:pause') this.pause();
      if (msg.type === 'flow:resume') this.resume();
    });
  }

  send(data) {
    if (this.#paused) {
      if (this.#messageQueue.length >= this.#MAX_QUEUE) {
        // Queue overflow — drop oldest (or disconnect client)
        this.#messageQueue.shift();
      }
      this.#messageQueue.push(data);
      return;
    }

    if (this.#ws.bufferedAmount > 1024 * 1024) { // 1MB server-side buffer
      this.#messageQueue.push(data);
      return;
    }

    this.#ws.send(typeof data === 'string' ? data : JSON.stringify(data));
  }

  pause() {
    this.#paused = true;
  }

  resume() {
    this.#paused = false;
    // Drain queue
    const batch = this.#messageQueue.splice(0, 50); // send 50 at a time
    batch.forEach(msg => this.send(msg));
    if (this.#messageQueue.length > 0) {
      setImmediate(() => this.drainQueue()); // non-blocking drain
    }
  }

  drainQueue() {
    if (this.#paused || this.#messageQueue.length === 0) return;
    const msg = this.#messageQueue.shift();
    this.send(msg);
    setImmediate(() => this.drainQueue());
  }
}
```

---

## 6. Offline Queue & Session Resumption

### 6.1 Client Offline Queue

```typescript
// offline-queue.ts
// Queue messages sent while disconnected; flush on reconnect

class OfflineQueue {
  private queue: QueuedMessage[] = [];
  private readonly MAX_SIZE = 100;
  private readonly MAX_AGE_MS = 5 * 60_000; // 5 minutes

  enqueue(message: object): void {
    this.pruneExpired();

    if (this.queue.length >= this.MAX_SIZE) {
      // Evict oldest non-critical messages
      const oldestNonCritical = this.queue.findIndex(m => !m.critical);
      if (oldestNonCritical >= 0) {
        this.queue.splice(oldestNonCritical, 1);
      } else {
        console.warn('Offline queue full, dropping critical message');
        return;
      }
    }

    this.queue.push({
      id: crypto.randomUUID(),
      message,
      enqueuedAt: Date.now(),
      critical: (message as any).priority === 'high',
    });

    // Persist to IndexedDB for offline-first PWAs
    this.persistToIndexedDB();
  }

  flush(sendFn: (msg: object) => void): void {
    this.pruneExpired();
    // Send in order
    const toFlush = [...this.queue];
    this.queue = [];
    toFlush.forEach(item => sendFn(item.message));
  }

  size(): number { return this.queue.length; }

  private pruneExpired(): void {
    const cutoff = Date.now() - this.MAX_AGE_MS;
    this.queue = this.queue.filter(m => m.enqueuedAt > cutoff);
  }

  private async persistToIndexedDB(): Promise<void> {
    // IndexedDB persistence for page refresh survival
    const db = await openDB('ws-queue', 1, {
      upgrade: (db) => db.createObjectStore('messages', { keyPath: 'id' }),
    });
    const tx = db.transaction('messages', 'readwrite');
    await Promise.all(this.queue.map(m => tx.store.put(m)));
    await tx.done;
  }

  static async loadFromIndexedDB(): Promise<OfflineQueue> {
    const queue = new OfflineQueue();
    try {
      const db = await openDB('ws-queue', 1);
      const stored = await db.getAll('messages');
      queue.queue = stored;
    } catch { /* IndexedDB not available */ }
    return queue;
  }
}
```

### 6.2 Session Resumption

```javascript
// session-resumption.js
// Concept: client reconnects and server replays missed messages

// Server: maintain per-session message log
class SessionStore {
  // sessionId → { userId, lastSeq, buffer: [{ seq, msg, ts }] }
  #sessions = new Map();
  #SESSION_TTL = 5 * 60_000; // 5 minutes — how long to buffer after disconnect

  createSession(userId) {
    const sessionId = generateSecureToken();
    this.#sessions.set(sessionId, {
      userId,
      lastSeq: 0,
      buffer: [],
      connectedAt: Date.now(),
      disconnectedAt: null,
    });
    return sessionId;
  }

  resumeSession(sessionId, clientLastSeq) {
    const session = this.#sessions.get(sessionId);
    if (!session) return null;

    // Check session not expired
    if (session.disconnectedAt &&
        Date.now() - session.disconnectedAt > this.#SESSION_TTL) {
      this.#sessions.delete(sessionId);
      return null;
    }

    // Return missed messages since clientLastSeq
    const missed = session.buffer.filter(m => m.seq > clientLastSeq);
    session.disconnectedAt = null; // reconnected
    return { session, missed };
  }

  bufferMessage(sessionId, message) {
    const session = this.#sessions.get(sessionId);
    if (!session) return;

    session.lastSeq++;
    session.buffer.push({ seq: session.lastSeq, msg: message, ts: Date.now() });

    // Keep only last 1000 messages in buffer
    if (session.buffer.length > 1000) {
      session.buffer = session.buffer.slice(-1000);
    }

    return session.lastSeq;
  }

  onDisconnect(sessionId) {
    const session = this.#sessions.get(sessionId);
    if (session) session.disconnectedAt = Date.now();
  }

  cleanup() {
    const now = Date.now();
    this.#sessions.forEach((session, id) => {
      if (session.disconnectedAt && now - session.disconnectedAt > this.#SESSION_TTL) {
        this.#sessions.delete(id);
      }
    });
  }
}

const sessionStore = new SessionStore();
setInterval(() => sessionStore.cleanup(), 60_000);

// WebSocket handler with session resumption
wss.on('connection', (ws, req) => {
  const { sessionId, lastSeq } = parseSessionFromReq(req);

  let session, missedMessages;

  if (sessionId) {
    // Attempt to resume
    const result = sessionStore.resumeSession(sessionId, lastSeq ?? 0);
    if (result) {
      ({ session, missedMessages } = result);
      // Replay missed messages
      missedMessages.forEach(({ seq, msg }) => {
        ws.send(JSON.stringify({ ...msg, _seq: seq, _replayed: true }));
      });
      ws.send(JSON.stringify({ type: 'session:resumed', sessionId, replayedCount: missedMessages.length }));
    }
  }

  if (!session) {
    // New session
    const newSessionId = sessionStore.createSession(ws.user.id);
    ws.sessionId = newSessionId;
    ws.send(JSON.stringify({ type: 'session:created', sessionId: newSessionId }));
  } else {
    ws.sessionId = sessionId;
  }

  ws.on('close', () => sessionStore.onDisconnect(ws.sessionId));
});

// Buffer all outgoing messages for session resumption
function sendToClient(ws, message) {
  const seq = sessionStore.bufferMessage(ws.sessionId, message);
  ws.send(JSON.stringify({ ...message, _seq: seq }));
}
```

### 6.3 Socket.IO Connection State Recovery (built-in, v4.6+)

```javascript
// Socket.IO handles session resumption automatically when enabled
const io = new Server(httpServer, {
  connectionStateRecovery: {
    maxDisconnectionDuration: 2 * 60_000, // buffer 2 minutes of events
    skipMiddlewares: true, // skip auth middleware on recovery (use stored session)
  },
});

io.on('connection', (socket) => {
  if (socket.recovered) {
    // Session was recovered: socket.id same, missed events replayed
    console.log('Session recovered for', socket.data.user?.id);
  } else {
    // New connection
    console.log('New connection:', socket.id);
  }
});
```

---

## Trade-offs Summary

| Mechanism | Latency Cost | Memory Cost | Complexity | When to use |
|-----------|-------------|-------------|-----------|-------------|
| Exponential backoff | Connection delay | Low | Low | Always (default) |
| Heartbeat (protocol) | ~1 frame/30s | Negligible | Low | Always |
| Heartbeat (app-level) | 1 RTT/30s | Low | Low | When protocol ping unavailable |
| Sequence numbers | Seq field overhead | Medium (pending map) | Medium | Ordered delivery needed |
| At-least-once + dedup | Ack RTT + Redis | Medium | Medium | Financial, critical data |
| Backpressure (flow) | Queuing delay | Medium (queue) | Medium | High-frequency streams |
| Offline queue | Flush delay | Medium | Medium | Mobile, poor connectivity |
| Session resumption | Replay delay | High (buffer) | High | Chat, collaborative tools |

---

## Ghi chú – Keywords tiếp theo

- **websocket_scaling_security.md**: Sticky sessions, Redis Pub/Sub adapter, Nginx proxy config, K8s WebSocket, JWT auth, Rate limiting, Origin validation, DoS protection
- **Keywords**: thundering herd, jitter, idempotency, exactly-once semantics, Connection State Recovery (Socket.IO), WebSocket over HTTP/2, QUIC/WebTransport (next-gen WebSocket alternative), Nagle's algorithm (TCP_NODELAY)
