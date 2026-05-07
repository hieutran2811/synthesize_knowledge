# WebSocket Fundamentals – Giao thức & Nền tảng

## Mục lục
1. [WebSocket là gì? (What)](#1-websocket-là-gì-what)
2. [Tại sao cần WebSocket? (Why)](#2-tại-sao-cần-websocket-why)
3. [Giao thức WebSocket hoạt động như thế nào? (How)](#3-giao-thức-websocket-hoạt-động-như-thế-nào-how)
4. [Frame Format](#4-frame-format)
5. [Browser WebSocket API](#5-browser-websocket-api)
6. [So sánh với các giải pháp khác (Compare)](#6-so-sánh-với-các-giải-pháp-khác-compare)
7. [Trade-offs](#7-trade-offs)
8. [Khi nào nên dùng WebSocket? (When)](#8-khi-nào-nên-dùng-websocket-when)

---

## 1. WebSocket là gì? (What)

**WebSocket** là một giao thức truyền thông **full-duplex**, **persistent**, **low-latency** trên một TCP connection duy nhất — được chuẩn hoá trong **RFC 6455** (2011).

### Đặc điểm cốt lõi:
- **Full-duplex**: Client và Server có thể gửi message **bất kỳ lúc nào**, không cần request/response cycle
- **Persistent connection**: Một TCP connection duy trì suốt phiên làm việc (không reconnect mỗi lần)
- **Low overhead**: Headers chỉ **2–14 bytes** mỗi frame (so với ~500–2000 bytes HTTP headers)
- **Low latency**: Không có HTTP handshake cho mỗi message → latency giảm 50–100ms
- **Bi-directional**: Server có thể **push** data chủ động, không cần client poll

---

## 2. Tại sao cần WebSocket? (Why)

```
Vấn đề với HTTP truyền thống:
  HTTP: Client phải luôn request trước → Server mới được phép respond
  → Server không thể chủ động push data khi có event mới

Các giải pháp "cũ" và hạn chế:
  
  Short Polling:
    Client: GET /updates mỗi 1 giây
    → 90% request trả về "nothing new" → lãng phí bandwidth
    → Latency = polling interval (1-3s)
  
  Long Polling (Comet):
    Client: GET /updates → server giữ request cho đến khi có data
    → Có data mới thì respond → client lập tức gửi request mới
    → Cải thiện hơn nhưng vẫn tốn overhead reconnect mỗi message
    → Server giữ hàng nghìn open connections tốn tài nguyên
  
  Server-Sent Events (SSE):
    Server push one-way → Client không thể gửi message qua SSE connection
    → Tốt cho feeds/notifications nhưng không phải real-time collaboration

WebSocket giải quyết:
  ✓ Server push bất kỳ lúc nào
  ✓ Client gửi message bất kỳ lúc nào
  ✓ Overhead cực thấp (frames, không phải HTTP requests)
  ✓ Latency < 10ms (chỉ còn network RTT)
  ✓ 1 connection cho toàn bộ session
```

---

## 3. Giao thức WebSocket hoạt động như thế nào? (How)

### 3.1 Opening Handshake (HTTP → WebSocket Upgrade)

```
Step 1: Client gửi HTTP Upgrade request
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket                    ← yêu cầu upgrade
Connection: Upgrade                   ← yêu cầu upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==  ← base64(16 random bytes)
Sec-WebSocket-Version: 13             ← phiên bản WS
Sec-WebSocket-Protocol: chat, superchat  ← subprotocols muốn dùng (optional)
Sec-WebSocket-Extensions: permessage-deflate  ← compression (optional)
Origin: https://example.com           ← CORS check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 2: Server đồng ý, trả về 101 Switching Protocols
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=  ← base64(SHA1(key + GUID))
Sec-WebSocket-Protocol: chat           ← subprotocol server chọn
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Sau đó: HTTP connection được "upgrade" → WebSocket protocol
TCP connection GIỮ NGUYÊN, chỉ thay đổi application-layer protocol
```

**Tính toán Sec-WebSocket-Accept:**
```
key = "dGhlIHNhbXBsZSBub25jZQ=="
magic_guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
accept = base64(SHA1(key + magic_guid))
       = base64(SHA1("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
       = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
```

### 3.2 Data Transfer (WebSocket Frames)

```
Sau handshake: giao tiếp qua WebSocket frames (không phải HTTP)

Client → Server: Text frame "Hello"
Server → Client: Text frame "World"
Client → Server: Binary frame (file chunk)
Server → Client: Ping frame (heartbeat)
Client → Server: Pong frame (response)
Client → Server: Close frame (close handshake)
Server → Client: Close frame (acknowledge)
```

### 3.3 Close Handshake

```
Graceful close (RFC 6455):

Initiator: → Close frame (opcode 0x8)
           code: 1000 (Normal Closure)
           reason: "Work complete"

Responder: → Close frame (echo back)

TCP connection: closed after both sides send Close frame

Close codes:
  1000: Normal closure
  1001: Going Away (server restart, browser tab close)
  1002: Protocol Error
  1003: Unsupported Data (e.g., binary data sent to text-only endpoint)
  1006: Abnormal Closure (no close frame received — connection dropped)
  1007: Invalid Frame Payload Data
  1008: Policy Violation
  1009: Message Too Big
  1011: Internal Server Error
  1012: Service Restart
  1013: Try Again Later
  4000-4999: Application-defined codes (custom use)
```

---

## 4. Frame Format

```
WebSocket Frame Structure (RFC 6455):

  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 ┌─┬─┬─┬─┬───────┬─┬───────────────────────────────────────────────┐
 │F│R│R│R│opcode │M│  Payload len  │  Extended payload length      │
 │I│S│S│S│  (4)  │A│    (7 bits)  │  (if len=126: 16bit           │
 │N│V│V│V│       │S│               │   if len=127: 64bit)          │
 │ │1│2│3│       │K│               │                               │
 └─┴─┴─┴─┴───────┴─┴───────────────────────────────────────────────┘
 │          Masking Key (32 bits, only if MASK=1)                   │
 ├──────────────────────────────────────────────────────────────────┤
 │          Payload Data (masked if MASK=1)                         │
 └──────────────────────────────────────────────────────────────────┘

Opcodes:
  0x0: Continuation frame
  0x1: Text frame (UTF-8)
  0x2: Binary frame
  0x8: Close frame
  0x9: Ping frame
  0xA: Pong frame

Masking:
  Client → Server: MUST be masked (prevent cache poisoning attacks)
  Server → Client: MUST NOT be masked
  
Overhead:
  Small frames (0-125 bytes): 2 bytes header + 4 bytes mask = 6 bytes total
  Medium frames (126-65535 bytes): 4 bytes header + 4 bytes mask = 8 bytes
  Large frames (>65535 bytes): 10 bytes header + 4 bytes mask = 14 bytes
  
  vs HTTP: 200-2000 bytes headers per request (30-300x larger overhead)
```

---

## 5. Browser WebSocket API

### 5.1 Basic Connection

```javascript
// Create WebSocket connection
const ws = new WebSocket('wss://api.example.com/ws');
//          Protocol: ws:// (insecure) or wss:// (TLS — production only)

// Connection states:
// ws.readyState === 0: CONNECTING
// ws.readyState === 1: OPEN
// ws.readyState === 2: CLOSING
// ws.readyState === 3: CLOSED

// Event handlers
ws.onopen = (event) => {
  console.log('Connected!');
  ws.send('Hello Server');           // send text
  ws.send(JSON.stringify({ type: 'auth', token: localStorage.getItem('token') }));
};

ws.onmessage = (event) => {
  console.log('Received:', event.data);

  // event.data can be:
  //   string (text frame)
  //   Blob (binary frame, default)
  //   ArrayBuffer (binary frame if binaryType = 'arraybuffer')

  const message = JSON.parse(event.data);
  handleMessage(message);
};

ws.onerror = (event) => {
  // NOTE: event doesn't contain error details (security limitation)
  // Check onclose for more info
  console.error('WebSocket error:', event);
};

ws.onclose = (event) => {
  console.log('Closed:', event.code, event.reason, 'wasClean:', event.wasClean);
  // event.wasClean = true if close handshake completed properly
  if (!event.wasClean || event.code === 1006) {
    scheduleReconnect();  // abnormal close → reconnect
  }
};

// Close connection
ws.close(1000, 'Normal closure');  // code + reason (optional)
```

### 5.2 Binary Data

```javascript
// Receive binary as ArrayBuffer (default is Blob)
ws.binaryType = 'arraybuffer';

ws.onmessage = (event) => {
  if (event.data instanceof ArrayBuffer) {
    const view = new DataView(event.data);
    const messageType = view.getUint8(0);
    const payload = event.data.slice(1);
    // custom binary protocol
  }
};

// Send binary data
const buffer = new ArrayBuffer(8);
const view = new DataView(buffer);
view.setUint8(0, 0x01);          // message type
view.setFloat64(1, Date.now()); // timestamp
ws.send(buffer);

// Send File/Blob
const file = document.querySelector('input[type=file]').files[0];
ws.send(file);    // sends as binary frame
```

### 5.3 Buffered Sending & Backpressure

```javascript
// ws.bufferedAmount: bytes queued but not yet sent
// Monitor before sending to detect slow network

function sendWithBackpressure(ws, data) {
  const BUFFER_THRESHOLD = 1024 * 16;  // 16KB

  if (ws.bufferedAmount > BUFFER_THRESHOLD) {
    console.warn('WebSocket send buffer full, dropping message');
    return false;
  }

  ws.send(data);
  return true;
}

// Or: wait until buffer drains
function sendQueued(ws, messages) {
  function drain() {
    while (messages.length > 0) {
      if (ws.bufferedAmount > 0) {
        setTimeout(drain, 50);  // wait for buffer to drain
        return;
      }
      ws.send(messages.shift());
    }
  }
  drain();
}
```

### 5.4 Subprotocols & Extensions

```javascript
// Request specific subprotocols (application-level protocols)
const ws = new WebSocket('wss://api.example.com/ws', ['v2.chat.example.com', 'v1.chat.example.com']);

ws.onopen = () => {
  console.log('Negotiated protocol:', ws.protocol);  // 'v2.chat.example.com'
  console.log('Extensions:', ws.extensions);         // 'permessage-deflate'
};

// Common subprotocols:
// 'stomp' — Simple Text Oriented Message Protocol (Spring WebSocket)
// 'graphql-ws' — GraphQL subscriptions
// 'mqtt' — IoT messaging
// 'soap' — legacy web services
```

---

## 6. So sánh với các giải pháp khác (Compare)

### 6.1 WebSocket vs Server-Sent Events (SSE)

```
SSE (EventSource API):
  ─ Server → Client only (one-way push)
  ─ HTTP-based (regular HTTP/1.1 or HTTP/2)
  ─ Auto-reconnect built-in (browser handles it)
  ─ Text only (UTF-8)
  ─ Simple: just response with Content-Type: text/event-stream
  ─ Works through proxies/firewalls easily (standard HTTP)
  ─ HTTP/2 multiplexing: multiple SSE streams on one connection

data: {"type":"notification","message":"New order"}

id: 42                    ← event ID for resume
data: {"type":"message"}

event: price-update       ← custom event name
data: {"price":99.99}

WebSocket:
  ─ Full-duplex (both directions)
  ─ Custom protocol on TCP
  ─ Manual reconnect needed
  ─ Text + Binary
  ─ Complex: handshake, frames, masking
  ─ Firewall issues (non-standard port/protocol)
  ─ Per-server sticky sessions needed for scale

When to use SSE:
  ✓ Notifications, feeds, live scores (server push only)
  ✓ Simple implementation needed
  ✓ Need HTTP/2 multiplexing
  ✓ Behind corporate proxies/firewalls

When to use WebSocket:
  ✓ Chat, gaming, collaboration (bidirectional)
  ✓ Low-latency required
  ✓ Binary data needed
  ✓ Custom message protocols
```

### 6.2 WebSocket vs Long Polling

```
Long Polling:
  GET /events → server holds until event → respond → client re-sends GET
  
  Pros:
    ✓ Works everywhere (just HTTP)
    ✓ No special infrastructure
    ✓ Firewall friendly
  
  Cons:
    ✗ Header overhead per message (~1KB vs ~10 bytes WebSocket)
    ✗ TCP connection teardown/setup per message
    ✗ Server maintains many pending requests
    ✗ Latency: server response + client round-trip before next poll

WebSocket wins when:
  ✓ > 1 message per second
  ✓ Low latency required (< 100ms)
  ✓ Many concurrent connections
```

### 6.3 WebSocket vs gRPC Streaming

```
gRPC Bidirectional Streaming:
  ─ Runs over HTTP/2
  ─ Protobuf serialization (binary, schema-defined)
  ─ Strong typing, code generation
  ─ NOT natively supported in browsers (needs grpc-web proxy)
  ─ Excellent for microservice-to-microservice

WebSocket:
  ─ Native browser support
  ─ Any message format (JSON, binary, custom)
  ─ No schema required
  ─ Easier to debug (readable JSON)

When gRPC streaming wins:
  ✓ Backend-to-backend streaming
  ✓ Schema-enforced contracts needed
  ✓ High-performance binary protocol needed

When WebSocket wins:
  ✓ Browser clients
  ✓ Flexible message formats
  ✓ Simpler infrastructure
```

---

## 7. Trade-offs

| Aspect | Pro | Con |
|--------|-----|-----|
| Latency | < 10ms (vs 100-300ms HTTP) | — |
| Overhead | 2-14 bytes per frame | Initial handshake ~1KB |
| Connection | Persistent (no re-establish) | Server must maintain state per connection |
| Scalability | Efficient bandwidth | Horizontal scaling complex (sticky sessions) |
| Firewall | Port 80/443 (same as HTTP) | Some corporate proxies block WS upgrade |
| Error handling | Connection drop detection via ping/pong | No built-in retry — must implement |
| Debugging | — | Browser DevTools WS tab limited; harder than HTTP |
| Load balancing | Standard LBs work | Need sticky sessions OR shared state (Redis) |
| Security | wss:// (TLS) — same as HTTPS | Origin validation MUST be done manually |
| Browser support | ✅ 98%+ all browsers | IE < 10 (irrelevant today) |

---

## 8. Khi nào nên dùng WebSocket? (When)

```
✅ Dùng WebSocket khi:
  ─ Cần real-time bidirectional communication (chat, collaborative tools)
  ─ Server cần push nhiều events/giây
  ─ Latency < 100ms quan trọng (trading, gaming, live auctions)
  ─ Cần gửi binary data liên tục (file streaming, audio/video chunks)
  ─ Số lượng message > 10/giây (overhead WebSocket << overhead HTTP polling)

❌ Không nên dùng WebSocket khi:
  ─ Chỉ cần server push, không cần client-to-server messages → dùng SSE
  ─ Occasional updates (< 1/phút) → dùng HTTP polling đơn giản hơn
  ─ Request/Response pattern rõ ràng → dùng REST/GraphQL
  ─ Behind strict corporate proxy/firewall → SSE hoặc long-polling an toàn hơn
  ─ Stateless, cacheable data → HTTP với CDN tốt hơn

Real-world examples:
  ✓ Slack, Discord: chat messages, presence indicators
  ✓ Google Docs, Figma: collaborative editing
  ✓ Binance, Robinhood: live price feeds
  ✓ Multiplayer games: player positions, game state
  ✓ Live sports: score updates, commentary
  ✓ DevOps dashboards: live logs, metrics streams
  ✓ Customer support: live chat widgets
```

---

## Ghi chú – Topics tiếp theo

- **Server implementations**: Node.js ws, Socket.IO, Spring WebSocket → `websocket_server.md`
- **Real-world patterns**: chat rooms, presence, dashboard → `websocket_patterns.md`
- **Reliability**: reconnection, heartbeat, message ordering → `websocket_reliability.md`
- **Scaling & Security**: Redis adapter, Nginx, JWT, rate limiting → `websocket_scaling_security.md`
- **Keywords**: SockJS (WebSocket fallback), Socket.IO transport negotiation, HTTP/2 server push (different from WS), WebTransport (QUIC-based, future), WebRTC (peer-to-peer), permessage-deflate extension, per-message vs per-frame compression, continuation frames, message fragmentation
