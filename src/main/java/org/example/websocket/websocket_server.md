# WebSocket Server Implementations

## Mục lục
1. [Browser WebSocket API (Client-side)](#1-browser-websocket-api-client-side)
2. [Node.js – ws library (Raw WebSocket)](#2-nodejs--ws-library-raw-websocket)
3. [Socket.IO – Rooms, Namespaces, Events](#3-socketio--rooms-namespaces-events)
4. [Spring WebSocket + STOMP + SockJS](#4-spring-websocket--stomp--sockjs)
5. [Go – Gorilla WebSocket](#5-go--gorilla-websocket)
6. [So sánh & Trade-offs](#6-so-sánh--trade-offs)

---

## 1. Browser WebSocket API (Client-side)

### 1.1 Kết nối và quản lý lifecycle

```typescript
// websocket-client.ts
class WebSocketClient {
  private ws: WebSocket | null = null;
  private reconnectAttempts = 0;
  private readonly maxReconnectAttempts = 10;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;

  connect(url: string): void {
    this.ws = new WebSocket(url, ['chat', 'notifications']); // subprotocols
    this.ws.binaryType = 'arraybuffer'; // or 'blob' for large files

    this.ws.onopen = (event) => {
      console.log('Connected, readyState:', this.ws!.readyState); // 1 = OPEN
      this.reconnectAttempts = 0;
      this.startHeartbeat();
    };

    this.ws.onmessage = (event) => {
      if (event.data instanceof ArrayBuffer) {
        this.handleBinary(event.data);
      } else {
        const msg = JSON.parse(event.data as string);
        this.handleMessage(msg);
      }
    };

    this.ws.onerror = (event) => {
      // event is a generic Event (no error details exposed for security)
      console.error('WebSocket error — check browser console for details');
    };

    this.ws.onclose = (event) => {
      // event.code: 1000 = normal, 1001 = going away, 1006 = abnormal
      // event.wasClean: false means connection dropped unexpectedly
      console.log(`Closed: code=${event.code}, clean=${event.wasClean}`);
      this.stopHeartbeat();

      if (!event.wasClean && event.code !== 1000) {
        this.scheduleReconnect();
      }
    };
  }

  send(data: object): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      // Backpressure check: don't flood the buffer
      if (this.ws.bufferedAmount > 1024 * 64) { // 64KB threshold
        console.warn('Buffer congested, dropping message');
        return;
      }
      this.ws.send(JSON.stringify(data));
    }
  }

  sendBinary(buffer: ArrayBuffer): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(buffer);
    }
  }

  close(code = 1000, reason = 'Normal closure'): void {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.ws?.close(code, reason);
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) return;
    const delay = Math.min(1000 * 2 ** this.reconnectAttempts, 30_000);
    const jitter = Math.random() * 1000;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.connect(this.ws!.url);
    }, delay + jitter);
  }

  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private startHeartbeat(): void {
    this.heartbeatTimer = setInterval(() => {
      this.send({ type: 'ping', timestamp: Date.now() });
    }, 30_000);
  }
  private stopHeartbeat(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
  }

  private handleBinary(buffer: ArrayBuffer): void {
    const view = new DataView(buffer);
    const messageType = view.getUint8(0);
    // custom binary protocol...
  }

  private handleMessage(msg: { type: string; [key: string]: unknown }): void {
    switch (msg.type) {
      case 'pong': break;
      case 'chat': /* ... */ break;
      default: console.warn('Unknown message type:', msg.type);
    }
  }
}

// readyState constants
// WebSocket.CONNECTING = 0
// WebSocket.OPEN       = 1
// WebSocket.CLOSING    = 2
// WebSocket.CLOSED     = 3
```

---

## 2. Node.js – ws library (Raw WebSocket)

### 2.1 WebSocket Server cơ bản

```javascript
// server.js
const { WebSocketServer, WebSocket } = require('ws');
const http = require('http');

const server = http.createServer();
const wss = new WebSocketServer({
  server,
  // path: '/ws',            // only accept connections at /ws
  // verifyClient: (info) => authCheck(info.req), // authentication hook
  maxPayload: 1024 * 1024,   // 1MB max message size
});

// Track all connections
const clients = new Map(); // clientId → WebSocket

wss.on('connection', (ws, req) => {
  const clientId = generateId();
  const ip = req.headers['x-forwarded-for'] ?? req.socket.remoteAddress;
  
  // Attach metadata to socket
  ws.clientId = clientId;
  ws.isAlive = true;
  clients.set(clientId, ws);

  console.log(`Client connected: ${clientId} from ${ip}`);

  ws.on('message', (data, isBinary) => {
    if (isBinary) {
      handleBinaryMessage(ws, data);
      return;
    }

    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      ws.send(JSON.stringify({ error: 'Invalid JSON' }));
      return;
    }

    handleMessage(ws, msg);
  });

  ws.on('pong', () => {
    ws.isAlive = true; // received pong → still alive
  });

  ws.on('close', (code, reason) => {
    clients.delete(clientId);
    console.log(`Client disconnected: ${clientId}, code=${code}`);
  });

  ws.on('error', (err) => {
    console.error(`Client error ${clientId}:`, err.message);
    clients.delete(clientId);
  });

  // Send welcome message
  ws.send(JSON.stringify({ type: 'welcome', clientId }));
});

// Heartbeat interval — detect dead connections (TCP keeps-alive insufficient)
const heartbeatInterval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      ws.terminate(); // force close (no close handshake)
      return;
    }
    ws.isAlive = false;
    ws.ping(); // send WebSocket ping frame
  });
}, 30_000);

wss.on('close', () => clearInterval(heartbeatInterval));

function handleMessage(ws, msg) {
  switch (msg.type) {
    case 'broadcast':
      broadcast(msg.data, ws);
      break;
    case 'echo':
      ws.send(JSON.stringify({ type: 'echo', data: msg.data }));
      break;
    default:
      ws.send(JSON.stringify({ error: `Unknown type: ${msg.type}` }));
  }
}

function broadcast(data, excludeWs = null) {
  const payload = JSON.stringify({ type: 'broadcast', data });
  wss.clients.forEach((client) => {
    if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  });
}

function handleBinaryMessage(ws, buffer) {
  // Echo binary back
  ws.send(buffer, { binary: true });
}

function generateId() {
  return Math.random().toString(36).slice(2, 10);
}

server.listen(8080, () => console.log('Server on :8080'));
```

### 2.2 Authentication với verifyClient

```javascript
const jwt = require('jsonwebtoken');
const url = require('url');

const wss = new WebSocketServer({
  server,
  verifyClient: ({ req }, callback) => {
    // Option 1: token in query string (ws://host?token=xxx)
    const { query } = url.parse(req.url, true);
    const token = query.token;

    // Option 2: token in headers (không phải standard nhưng một số client hỗ trợ)
    // const token = req.headers['authorization']?.split(' ')[1];

    if (!token) {
      callback(false, 401, 'Unauthorized');
      return;
    }

    try {
      const payload = jwt.verify(token, process.env.JWT_SECRET);
      req.user = payload; // attach to request for use in 'connection' handler
      callback(true);
    } catch {
      callback(false, 403, 'Forbidden');
    }
  },
});

wss.on('connection', (ws, req) => {
  ws.user = req.user; // { userId, roles, ... }
  // ...
});
```

### 2.3 Rooms (manual implementation)

```javascript
// rooms.js — manual room management (không có abstraction như Socket.IO)
class RoomManager {
  #rooms = new Map(); // roomId → Set<WebSocket>

  join(roomId, ws) {
    if (!this.#rooms.has(roomId)) this.#rooms.set(roomId, new Set());
    this.#rooms.get(roomId).add(ws);
    ws._rooms ??= new Set();
    ws._rooms.add(roomId);
  }

  leave(roomId, ws) {
    this.#rooms.get(roomId)?.delete(ws);
    ws._rooms?.delete(roomId);
    if (this.#rooms.get(roomId)?.size === 0) this.#rooms.delete(roomId);
  }

  leaveAll(ws) {
    ws._rooms?.forEach(roomId => this.leave(roomId, ws));
  }

  broadcast(roomId, data, excludeWs = null) {
    const room = this.#rooms.get(roomId);
    if (!room) return;
    const payload = typeof data === 'string' ? data : JSON.stringify(data);
    room.forEach(client => {
      if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
        client.send(payload);
      }
    });
  }

  getCount(roomId) {
    return this.#rooms.get(roomId)?.size ?? 0;
  }
}

const rooms = new RoomManager();
```

---

## 3. Socket.IO – Rooms, Namespaces, Events

### 3.1 Server setup

```javascript
// socket-server.js
const { createServer } = require('http');
const { Server } = require('socket.io');
const { createAdapter } = require('@socket.io/redis-adapter');
const { createClient } = require('redis');

const httpServer = createServer();
const io = new Server(httpServer, {
  cors: {
    origin: process.env.ALLOWED_ORIGINS?.split(',') ?? ['http://localhost:4200'],
    methods: ['GET', 'POST'],
    credentials: true,
  },
  transports: ['websocket', 'polling'], // try WebSocket first, fall back to polling
  connectionStateRecovery: {           // Socket.IO 4.6+: buffer missed events
    maxDisconnectionDuration: 2 * 60 * 1000, // 2 minutes
    skipMiddlewares: true,
  },
});

// Redis adapter for horizontal scaling (multiple Node instances)
async function setupRedisAdapter() {
  const pubClient = createClient({ url: process.env.REDIS_URL });
  const subClient = pubClient.duplicate();
  await Promise.all([pubClient.connect(), subClient.connect()]);
  io.adapter(createAdapter(pubClient, subClient));
}
setupRedisAdapter();

// Middleware — authentication
io.use(async (socket, next) => {
  const token = socket.handshake.auth.token  // { auth: { token: '...' } } from client
    ?? socket.handshake.headers.authorization?.split(' ')[1];
  
  if (!token) return next(new Error('Authentication error'));

  try {
    const user = await verifyJwt(token);
    socket.data.user = user; // attach to socket.data (typed in TypeScript)
    next();
  } catch {
    next(new Error('Invalid token'));
  }
});

// Default namespace '/'
io.on('connection', (socket) => {
  const user = socket.data.user;
  console.log(`Connected: ${socket.id}, user: ${user.id}`);

  // Join user's personal room (for targeted messages)
  socket.join(`user:${user.id}`);

  // ── Room events ──────────────────────────────────────────────────────────
  socket.on('room:join', async ({ roomId }) => {
    if (!await canAccessRoom(user.id, roomId)) {
      socket.emit('error', { message: 'Access denied' });
      return;
    }
    await socket.join(roomId);
    const count = io.sockets.adapter.rooms.get(roomId)?.size ?? 0;
    socket.to(roomId).emit('room:user_joined', { userId: user.id, count });
    socket.emit('room:joined', { roomId, count });
  });

  socket.on('room:leave', ({ roomId }) => {
    socket.leave(roomId);
    socket.to(roomId).emit('room:user_left', { userId: user.id });
  });

  socket.on('room:message', ({ roomId, content }) => {
    if (!socket.rooms.has(roomId)) {
      socket.emit('error', { message: 'Not in room' });
      return;
    }
    const message = { id: generateId(), userId: user.id, content, ts: Date.now() };
    // Broadcast to room (excluding sender)
    socket.to(roomId).emit('room:message', message);
    // Acknowledge to sender
    socket.emit('room:message:ack', { messageId: message.id });
  });

  // ── Acknowledgments (request/response over WebSocket) ────────────────────
  socket.on('ping', (data, callback) => {
    // callback is the ack function sent by client
    callback({ pong: true, timestamp: Date.now(), echo: data });
  });

  // ── Disconnect ────────────────────────────────────────────────────────────
  socket.on('disconnecting', () => {
    // socket.rooms still populated at this point (before leaving)
    socket.rooms.forEach(roomId => {
      if (roomId !== socket.id) {
        socket.to(roomId).emit('room:user_left', { userId: user.id });
      }
    });
  });

  socket.on('disconnect', (reason) => {
    // reason: 'transport close', 'ping timeout', 'server namespace disconnect'
    console.log(`Disconnected: ${socket.id}, reason: ${reason}`);
  });
});
```

### 3.2 Namespaces — isolating concerns

```javascript
// /admin namespace — only admin users
const adminNs = io.of('/admin');

adminNs.use((socket, next) => {
  if (socket.data.user?.roles?.includes('ADMIN')) {
    next();
  } else {
    next(new Error('Admin access required'));
  }
});

adminNs.on('connection', (socket) => {
  socket.on('broadcast:all', ({ message }) => {
    // emit to ALL clients in default namespace
    io.emit('admin:announcement', { message, from: 'admin' });
  });

  socket.on('kick:user', ({ userId }) => {
    // Disconnect a specific user
    io.in(`user:${userId}`).disconnectSockets(true);
  });

  socket.on('get:stats', (callback) => {
    callback({
      connections: io.engine.clientsCount,
      rooms: [...io.sockets.adapter.rooms.keys()].length,
    });
  });
});
```

### 3.3 Client (TypeScript)

```typescript
// socket-client.ts
import { io, Socket } from 'socket.io-client';

interface ServerToClientEvents {
  'room:message': (msg: { id: string; userId: string; content: string; ts: number }) => void;
  'room:user_joined': (data: { userId: string; count: number }) => void;
  'room:user_left': (data: { userId: string }) => void;
  'admin:announcement': (data: { message: string; from: string }) => void;
  error: (data: { message: string }) => void;
}

interface ClientToServerEvents {
  'room:join': (data: { roomId: string }) => void;
  'room:leave': (data: { roomId: string }) => void;
  'room:message': (data: { roomId: string; content: string }) => void;
  ping: (data: unknown, callback: (response: { pong: boolean; timestamp: number }) => void) => void;
}

const socket: Socket<ServerToClientEvents, ClientToServerEvents> = io('http://localhost:3000', {
  auth: { token: localStorage.getItem('access_token') },
  transports: ['websocket'],
  reconnectionAttempts: 10,
  reconnectionDelay: 1000,
  reconnectionDelayMax: 30_000,
  randomizationFactor: 0.5,
});

socket.on('connect', () => console.log('Connected:', socket.id));
socket.on('disconnect', (reason) => {
  if (reason === 'io server disconnect') {
    socket.connect(); // server kicked us, manually reconnect
  }
  // other reasons: Socket.IO auto-reconnects
});
socket.on('connect_error', (err) => {
  if (err.message === 'Authentication error') {
    // refresh token then reconnect
    refreshToken().then(token => {
      socket.auth = { token };
      socket.connect();
    });
  }
});

// Using acknowledgment (request/response)
socket.emit('ping', { hello: 'world' }, (response) => {
  console.log('Pong received:', response.timestamp);
});

// Join a room
socket.emit('room:join', { roomId: 'general' });
socket.on('room:message', (msg) => {
  console.log(`[${msg.userId}]: ${msg.content}`);
});
```

---

## 4. Spring WebSocket + STOMP + SockJS

### 4.1 Dependencies & Configuration

```xml
<!-- pom.xml -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-websocket</artifactId>
</dependency>
<!-- SockJS fallback + STOMP client testing -->
<dependency>
  <groupId>org.webjars</groupId>
  <artifactId>sockjs-client</artifactId>
  <version>1.5.1</version>
</dependency>
```

```java
// WebSocketConfig.java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

  @Override
  public void configureMessageBroker(MessageBrokerRegistry registry) {
    // Simple in-memory broker for topics and queues
    registry.enableSimpleBroker("/topic", "/queue")
        .setHeartbeatValue(new long[]{10_000, 10_000}) // server→client, client→server ms
        .setTaskScheduler(heartbeatScheduler());

    // Prefix for @MessageMapping methods
    registry.setApplicationDestinationPrefixes("/app");

    // Prefix for user-specific messages (to a single user)
    registry.setUserDestinationPrefix("/user");
  }

  @Override
  public void registerStompEndpoints(StompEndpointRegistry registry) {
    registry.addEndpoint("/ws")
        .setAllowedOriginPatterns("http://localhost:*", "https://*.example.com")
        .withSockJS() // SockJS fallback for browsers that block WebSocket
          .setStreamBytesLimit(512 * 1024)
          .setHttpMessageCacheSize(1000)
          .setDisconnectDelay(30_000);
  }

  @Override
  public void configureWebSocketTransport(WebSocketTransportRegistration registration) {
    registration
        .setMessageSizeLimit(128 * 1024) // 128KB max message
        .setSendBufferSizeLimit(512 * 1024)
        .setSendTimeLimit(20_000);        // drop slow client after 20s
  }

  @Bean
  public TaskScheduler heartbeatScheduler() {
    ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
    scheduler.setPoolSize(1);
    scheduler.setThreadNamePrefix("ws-heartbeat-");
    return scheduler;
  }
}
```

### 4.2 Controllers & Messaging

```java
// ChatController.java
@Controller
public class ChatController {

  private final SimpMessagingTemplate messagingTemplate;
  private final ChatService chatService;

  // ── Broadcast to topic ───────────────────────────────────────────────────
  @MessageMapping("/chat.send")           // client sends to /app/chat.send
  @SendTo("/topic/chat.general")          // server broadcasts to /topic/chat.general
  public ChatMessage sendMessage(@Payload ChatMessage message,
                                  Principal principal) {
    message.setSender(principal.getName());
    message.setTimestamp(Instant.now());
    chatService.saveMessage(message);
    return message;
  }

  // ── Send to specific user ────────────────────────────────────────────────
  @MessageMapping("/chat.private")
  public void sendPrivateMessage(@Payload PrivateMessage message,
                                  Principal principal) {
    message.setFrom(principal.getName());
    // Sends to /user/{targetUser}/queue/private
    messagingTemplate.convertAndSendToUser(
        message.getTo(),
        "/queue/private",
        message
    );
  }

  // ── Request-response (with @SendToUser for response to caller only) ──────
  @MessageMapping("/chat.history")
  @SendToUser("/queue/history")           // response only to caller
  public List<ChatMessage> getHistory(@Payload HistoryRequest request,
                                       Principal principal) {
    return chatService.getHistory(request.getRoomId(), request.getPage());
  }

  // ── Server-initiated push ────────────────────────────────────────────────
  @Scheduled(fixedDelay = 5000)
  public void pushLiveMetrics() {
    Metrics metrics = metricsService.getCurrent();
    messagingTemplate.convertAndSend("/topic/metrics", metrics);
  }
}
```

### 4.3 Security & Channel Interceptor

```java
// WebSocketSecurityConfig.java
@Configuration
public class WebSocketSecurityConfig extends AbstractSecurityWebSocketMessageBrokerConfigurer {

  @Override
  protected void configureInbound(MessageSecurityMetadataSourceRegistry messages) {
    messages
        .nullDestMatcher().authenticated()             // CONNECT frames
        .simpSubscribeDestMatchers("/user/**").authenticated()
        .simpDestMatchers("/app/**").authenticated()
        .simpDestMatchers("/topic/admin.*").hasRole("ADMIN")
        .anyMessage().authenticated();
  }

  @Override
  protected boolean sameOriginDisabled() {
    return true; // disable CSRF for WebSocket (use JWT instead)
  }
}

// JwtChannelInterceptor.java — validate JWT on CONNECT
@Component
public class JwtChannelInterceptor implements ChannelInterceptor {

  private final JwtService jwtService;
  private final UserDetailsService userDetailsService;

  @Override
  public Message<?> preSend(Message<?> message, MessageChannel channel) {
    StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(
        message, StompHeaderAccessor.class);

    if (StompCommand.CONNECT.equals(accessor.getCommand())) {
      String token = accessor.getFirstNativeHeader("Authorization");
      if (token == null || !token.startsWith("Bearer ")) {
        throw new MessageDeliveryException("Missing token");
      }

      try {
        String username = jwtService.extractUsername(token.substring(7));
        UserDetails user = userDetailsService.loadUserByUsername(username);
        UsernamePasswordAuthenticationToken auth =
            new UsernamePasswordAuthenticationToken(user, null, user.getAuthorities());
        accessor.setUser(auth); // set Principal
      } catch (JwtException e) {
        throw new MessageDeliveryException("Invalid token: " + e.getMessage());
      }
    }
    return message;
  }
}

// Register in WebSocketConfig:
@Override
public void configureClientInboundChannel(ChannelRegistration registration) {
  registration.interceptors(jwtChannelInterceptor);
}
```

### 4.4 Event Listeners

```java
// WebSocketEventListener.java
@Component
public class WebSocketEventListener {

  private final SimpMessagingTemplate messagingTemplate;
  private final PresenceService presenceService;

  @EventListener
  public void handleConnect(SessionConnectedEvent event) {
    StompHeaderAccessor accessor = StompHeaderAccessor.wrap(event.getMessage());
    String sessionId = accessor.getSessionId();
    String username = event.getUser().getName();
    presenceService.userConnected(username, sessionId);
    messagingTemplate.convertAndSend("/topic/presence", 
        new PresenceEvent(username, "ONLINE"));
  }

  @EventListener
  public void handleDisconnect(SessionDisconnectEvent event) {
    StompHeaderAccessor accessor = StompHeaderAccessor.wrap(event.getMessage());
    String username = event.getUser() != null ? event.getUser().getName() : "unknown";
    presenceService.userDisconnected(username, accessor.getSessionId());
    messagingTemplate.convertAndSend("/topic/presence",
        new PresenceEvent(username, "OFFLINE"));
  }

  @EventListener
  public void handleSubscribe(SessionSubscribeEvent event) {
    // Can track which topics users subscribe to
  }
}
```

### 4.5 Client (Angular + STOMP.js)

```typescript
// stomp.service.ts
import { Client, IMessage, StompSubscription } from '@stomp/stompjs';
import SockJS from 'sockjs-client';

@Injectable({ providedIn: 'root' })
export class StompService {
  private client: Client;
  private subscriptions = new Map<string, StompSubscription>();

  constructor(private authService: AuthService) {
    this.client = new Client({
      webSocketFactory: () => new SockJS('http://localhost:8080/ws'),
      connectHeaders: {
        Authorization: `Bearer ${authService.getToken()}`,
      },
      heartbeatIncoming: 10_000,
      heartbeatOutgoing: 10_000,
      reconnectDelay: 5_000,
      onConnect: () => this.onConnected(),
      onStompError: (frame) => console.error('STOMP error:', frame),
    });
  }

  activate(): void { this.client.activate(); }
  deactivate(): void { this.client.deactivate(); }

  subscribe<T>(destination: string, callback: (msg: T) => void): void {
    const sub = this.client.subscribe(destination, (message: IMessage) => {
      callback(JSON.parse(message.body) as T);
    });
    this.subscriptions.set(destination, sub);
  }

  publish(destination: string, body: object): void {
    this.client.publish({
      destination,
      body: JSON.stringify(body),
      headers: { 'content-type': 'application/json' },
    });
  }

  unsubscribe(destination: string): void {
    this.subscriptions.get(destination)?.unsubscribe();
    this.subscriptions.delete(destination);
  }

  private onConnected(): void {
    // Subscribe to personal queue
    this.subscribe(`/user/queue/private`, (msg) => {
      console.log('Private message:', msg);
    });
  }
}
```

---

## 5. Go – Gorilla WebSocket

### 5.1 Basic Server

```go
// main.go
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		origin := r.Header.Get("Origin")
		return isAllowedOrigin(origin) // validate origin
	},
	HandshakeTimeout: 10 * time.Second,
}

// Message types
type Message struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// Client represents a connected WebSocket client
type Client struct {
	id      string
	conn    *websocket.Conn
	send    chan []byte // buffered channel for outgoing messages
	hub     *Hub
	mu      sync.Mutex
	userID  string
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(512 * 1024) // 512KB
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, rawMsg, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err,
				websocket.CloseGoingAway,
				websocket.CloseAbnormalClosure) {
				log.Printf("unexpected close: %v", err)
			}
			break
		}

		var msg Message
		if err := json.Unmarshal(rawMsg, &msg); err != nil {
			c.sendJSON(Message{Type: "error", Payload: jsonRaw(`{"msg":"invalid JSON"}`)})
			continue
		}

		c.hub.handleMessage(c, msg)
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(54 * time.Second) // ping interval
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				// Hub closed the channel
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			c.mu.Lock()
			err := c.conn.WriteMessage(websocket.TextMessage, msg)
			c.mu.Unlock()
			if err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) sendJSON(v interface{}) {
	data, _ := json.Marshal(v)
	select {
	case c.send <- data:
	default:
		// Buffer full — client too slow, disconnect
		close(c.send)
	}
}
```

### 5.2 Hub — connection manager

```go
// hub.go
type Hub struct {
	clients    map[*Client]bool
	rooms      map[string]map[*Client]bool
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		rooms:      make(map[string]map[*Client]bool),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.send)
				// Remove from all rooms
				for roomID, room := range h.rooms {
					delete(room, client)
					if len(room) == 0 {
						delete(h.rooms, roomID)
					}
				}
			}
			h.mu.Unlock()
		}
	}
}

func (h *Hub) handleMessage(sender *Client, msg Message) {
	switch msg.Type {
	case "room.join":
		var data struct{ RoomID string `json:"roomId"` }
		json.Unmarshal(msg.Payload, &data)
		h.joinRoom(sender, data.RoomID)

	case "room.message":
		var data struct {
			RoomID  string `json:"roomId"`
			Content string `json:"content"`
		}
		json.Unmarshal(msg.Payload, &data)
		h.broadcastToRoom(data.RoomID, sender, Message{
			Type:    "room.message",
			Payload: jsonRaw(`{"userId":"` + sender.userID + `","content":"` + data.Content + `"}`),
		})
	}
}

func (h *Hub) joinRoom(client *Client, roomID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.rooms[roomID]; !ok {
		h.rooms[roomID] = make(map[*Client]bool)
	}
	h.rooms[roomID][client] = true
}

func (h *Hub) broadcastToRoom(roomID string, exclude *Client, msg Message) {
	data, _ := json.Marshal(msg)
	h.mu.RLock()
	defer h.mu.RUnlock()
	for client := range h.rooms[roomID] {
		if client != exclude {
			select {
			case client.send <- data:
			default:
				// Slow client — will be disconnected by writePump
			}
		}
	}
}

// WebSocket handler
func serveWs(hub *Hub, w http.ResponseWriter, r *http.Request) {
	// Auth check
	userID, err := validateToken(r.URL.Query().Get("token"))
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("upgrade error:", err)
		return
	}

	client := &Client{
		id:     generateID(),
		conn:   conn,
		send:   make(chan []byte, 256), // buffered
		hub:    hub,
		userID: userID,
	}
	hub.register <- client

	// Run pumps in goroutines
	go client.writePump()
	go client.readPump()
}

func main() {
	hub := NewHub()
	go hub.Run()
	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		serveWs(hub, w, r)
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

---

## 6. So sánh & Trade-offs

| | ws (Node.js) | Socket.IO | Spring STOMP | Gorilla (Go) |
|--|-------------|-----------|-------------|-------------|
| **Protocol** | Raw WebSocket | WS + polling fallback | STOMP over WS | Raw WebSocket |
| **Abstraction** | Low (manual rooms) | High (rooms/namespaces built-in) | High (topics/queues) | Low (manual Hub) |
| **Scaling** | Manual / Redis | Redis Adapter | Redis/RabbitMQ broker | Manual / Redis |
| **Performance** | ~100k connections/node | ~50k (more overhead) | JVM GC latency | ~1M goroutines |
| **Browser fallback** | ❌ WebSocket only | ✅ polling fallback | ✅ SockJS fallback | ❌ WebSocket only |
| **Spring ecosystem** | ❌ | ❌ | ✅ Spring Security integration | ❌ |
| **Best for** | Simple, custom protocol | Chat, gaming (JS ecosystem) | Enterprise Java, STOMP clients | High-concurrency, microservices |

### Khi nào dùng gì?

```
Node.js ws:
  ✅ Custom binary protocol
  ✅ Minimal overhead, full control
  ✅ Microservice WebSocket gateway
  ❌ Need rooms/events abstraction → use Socket.IO

Socket.IO:
  ✅ Rapid development (rooms, acks, reconnect built-in)
  ✅ Mixed client support (browser, mobile, legacy)
  ✅ Real-time gaming, chat apps
  ❌ Not interoperable with raw WebSocket clients

Spring STOMP:
  ✅ Java/Spring ecosystem, Spring Security
  ✅ STOMP clients (Java, JavaScript STOMP.js)
  ✅ Message broker integration (RabbitMQ, ActiveMQ)
  ❌ STOMP overhead if simple binary protocol needed

Gorilla (Go):
  ✅ Maximum concurrency (goroutines are cheap)
  ✅ Low memory: ~2KB per goroutine vs ~1MB per Java thread
  ✅ Real-time data pipelines, IoT gateways
  ❌ No built-in message broker
```

---

## Ghi chú – Keywords tiếp theo

- **websocket_patterns.md**: Chat app architecture, Live dashboard metrics pipeline, Collaborative editing (CRDT/OT), Presence system design, Notification fan-out
- **Keywords**: STOMP protocol, SockJS transport, Socket.IO namespace isolation, Gorilla Hub pattern, ws library, connection pooling, WebSocket load testing (artillery, k6), binary framing custom protocol
