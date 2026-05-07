# Roadmap Tổng Hợp Kiến Thức WebSocket – Cơ Bản đến Nâng Cao

## Cấu trúc thư mục
```
websocket/
├── roadmap.md                      ← file này
├── websocket_fundamentals.md      ← Protocol, Handshake, Frames, vs HTTP/SSE/Polling, Browser API
├── websocket_server.md            ← Node.js (ws/Socket.IO), Spring WebSocket+STOMP, Go Gorilla
├── websocket_patterns.md          ← Chat, Live Dashboard, Collaborative Editing, Presence, Pub/Sub Rooms
├── websocket_reliability.md       ← Reconnection, Heartbeat, Message ordering, At-least-once, Backpressure
└── websocket_scaling_security.md  ← Horizontal scaling (Redis Adapter), Nginx, JWT auth, Rate limiting, Security
```

> **Prerequisite**: Hiểu HTTP, TCP/IP cơ bản, JavaScript/TypeScript, một backend framework

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Fundamentals – Giao thức WebSocket (RFC 6455), TCP persistent connection, Opening handshake (HTTP Upgrade), Frame format, Data types (text/binary), Ping/Pong, Close handshake, So sánh SSE/Long-polling/gRPC-stream | websocket_fundamentals.md | ✅ |
| 2 | Server Implementations – Browser WebSocket API, Node.js (ws library), Socket.IO (rooms/namespaces/events), Spring WebSocket + STOMP + SockJS, Go Gorilla WebSocket | websocket_server.md | ✅ |
| 3 | Real-world Patterns – Chat app (typing indicator, read receipts, optimistic UI), Live dashboard (metrics/stock ticker throttle), Collaborative editing (OT/CRDT), Presence system (grace period), Pub/Sub với rooms (hierarchical topics), Notification fan-out | websocket_patterns.md | ✅ |
| 4 | Reliability – Reconnection (exponential backoff + jitter, thundering herd), Heartbeat/Ping-Pong (protocol + app-level, latency monitor), Message ordering & deduplication (seq numbers, Redis dedup), At-least-once delivery (ack + retry), Backpressure (flow control, token bucket), Offline queue (IndexedDB), Session resumption | websocket_reliability.md | ✅ |
| 5 | Scaling & Security – Sticky sessions vs stateless, Redis Pub/Sub adapter (Socket.IO + custom ws), Nginx WebSocket proxy config, K8s (Deployment/Ingress/HPA/PDB), JWT auth (3 strategies + token refresh), Rate limiting (token bucket + Redis sliding window), Origin validation, DoS protection, Security checklist | websocket_scaling_security.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Quick Reference: WebSocket vs Alternatives

| | WebSocket | HTTP Long-Polling | Server-Sent Events | gRPC Streaming | MQTT |
|--|-----------|------------------|--------------------|----------------|------|
| Direction | **Full-duplex** | Pseudo-duplex | Server→Client only | Full-duplex | Full-duplex |
| Protocol | WS (TCP) | HTTP | HTTP | HTTP/2 | TCP |
| Connection | Persistent | Per-poll | Persistent | Persistent | Persistent |
| Overhead | Low (frames) | High (HTTP headers) | Low | Low (protobuf) | Very Low |
| Browser support | ✅ Native | ✅ Native | ✅ Native | ❌ (needs grpc-web) | ❌ (library) |
| Load balancer | Tricky (sticky) | Easy | Easy | Tricky | N/A |
| Best for | Chat, gaming, collab | Legacy compatibility | Notifications, feeds | Microservices | IoT devices |

---

## WebSocket Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     WebSocket Connection                         │
│                                                                  │
│  Browser/Client                      Server                      │
│  ┌─────────────┐    TCP (WS frames)  ┌──────────────────────┐  │
│  │ WebSocket   │◄──────────────────►│ WebSocket Server     │  │
│  │ API         │   ws:// or wss://  │ (Node/Spring/Go)     │  │
│  └─────────────┘                    └──────────┬───────────┘  │
│                                                 │               │
│  Upgrade Flow:                      ┌───────────▼───────────┐  │
│  HTTP GET /ws                       │  Connection Manager   │  │
│  Upgrade: websocket          ──────►│  (Session Store)      │  │
│  101 Switching Protocols            └───────────┬───────────┘  │
│                                                 │               │
│                                     ┌───────────▼───────────┐  │
│                                     │  Message Broker       │  │
│                                     │  (Redis Pub/Sub)      │  │
│                                     └───────────┬───────────┘  │
│                                                 │               │
│                                     ┌───────────▼───────────┐  │
│                                     │  Business Logic       │  │
│                                     │  (Rooms/Topics/Auth)  │  │
│                                     └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```
