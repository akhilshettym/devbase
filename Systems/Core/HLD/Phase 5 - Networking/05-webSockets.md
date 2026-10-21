## Web Sockets

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

- WebSocket is an application-layer protocol (standardized in RFC 6455) that provides full-duplex, bi-directional,persistent communication channels over a single TCP connection.

- While HTTP/1.1 and SSE enforce client-initiated or server-push-only workflows, WebSocket enables both client and server to independently push raw data frames back and forth at any time with minimal header overhead.

```
+-----------------------------------------------------------------------------------+
|                        Real-World Analogy: Phone Call                             |
+-----------------------------------------------------------------------------------+
| HTTP / Polling: Exchanging Postcards                                              |
| - Every message requires writing an address, putting on a stamp (HTTP headers),   |
|   and waiting for a reply post card to arrive.                                    |
|                                                                                   |
| WebSocket: Open Telephone Line                                                    |
| - You dial once (HTTP Upgrade Handshake). Once the call connects (101 Switching), |
|   the line stays open indefinitely.                                               |
| - Either party can speak or listen simultaneously without redialing or re-adding  |
|   envelope metadata to every word.                                                |
+-----------------------------------------------------------------------------------+
```

- **The Problem It Solves**: Solves the latency, network overhead, and architectural constraints of HTTP for bi-directional, high-frequency, real-time interactivity.

- **Primary Use Cases**: Collaborative document editing (e.g., Figma, Notion), live multi-player gaming, chat applications, real-time financial trading order books, and collaborative whiteboards.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- ws:// and wss://: URI schemes for WebSocket.
- ws://: Unencrypted transport operating over default port 80.
- wss://: Encrypted transport running over TLS operating over default port 443 (industry standard for production).

- **HTTP Upgrade Handshake**: The initial connection setup starts as a standard HTTP/1.1 GET request containing specific Upgrade headers. If the server accepts, it responds with an HTTP 101 Switching Protocols status code, and the underlying TCP socket immediately switches from HTTP to the WebSocket protocol framing.

#### Frames vs. Messages:

- **Frame**: The smallest physical unit of data sent over the wire (containing a small header and partial payload).
- **Message**: A complete logical unit of application data, consisting of one or more sequential frames (Text or Binary).

#### Protocol Comparison Matrix:

| Feature                 | `Long Polling`                  | `Server-Sent Events (SSE)`           | `WebSocket`                                |
| ----------------------- | ------------------------------- | ------------------------------------ | ------------------------------------------ |
| **Directionality**      | Unidirectional (Simulated Push) | Unidirectional (Server $\to$ Client) | Full-Duplex (Bi-directional)               |
| **Connection Basis**    | Ephemeral Request/Response      | Long-lived Streaming HTTP            | Long-lived Persistent TCP                  |
| **Protocol Layer**      | HTTP                            | HTTP                                 | WebSocket Protocol (Post-handshake)        |
| **Header Overhead**     | ~500B – 2KB per message         | Sent once at handshake               | 2 to 14 bytes per frame                    |
| **Data Types**          | Text / JSON / Binary            | UTF-8 Text only                      | Text (UTF-8) & Binary (ArrayBuffer/Blob)   |
| **Native Reconnection** | Manual                          | Built-in (EventSource)               | Manual (Application-level backoff logic)   |
| **Proxy Compatibility** | Universal                       | High (Needs buffering disabled)      | Medium (Requires L7 WebSocket proxy setup) |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Connection Handshake:

#### 1. The HTTP Upgrade Handshake Mechanics:

To establish a WebSocket connection, the client sends an HTTP GET request with upgrade headers:

```HTTP
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
Origin: https://example.com
```

- **The Mathematical Handshake Challenge**: To prevent accidental or non-WebSocket connections from hanging open, the server MUST calculate a cryptographic response:
- Server takes the client's Sec-WebSocket-Key string (dGhlIHNhbXBsZSBub25jZQ==).
- Appends the globally unique RFC 6455 Magic String GUID: 258EAFA5-E914-47DA-95CA-C5AB0DC85B11.
- Computes the SHA-1 hash of the combined string and encodes the binary digest into Base64.

#### Sends the value back in the Sec-WebSocket-Accept header:

```HTTP
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

- Once this HTTP response completes, the connection transitions from HTTP to raw WebSocket protocol frames over the same established TCP socket.

#### 2. WebSocket Binary Framing Protocol Structure:

- WebSocket drops heavy HTTP text headers in favor of a hyper-compact binary frame format that adds as little as 2 bytes of overhead for small unmasked payloads.

```
0 1 2 3
0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len | Extended payload length       |
|I|S|S|S| (4b)  |A| (7b)        | (16/64b)                      |
|N|1|2|3|       |S|             |                               |
+-+-+-+-+-------+-+-------------+-------------------------------+
| Extended payload length continuation (if len == 127)          |
+-------------------------------+-------------------------------+
| Masking-key (0 or 4 bytes)                                    |
+---------------------------------------------------------------+
| Payload Data                                                  |
+---------------------------------------------------------------+
```

- **FIN (1 bit)**: Indicates if this frame is the final fragment of a message ($1 = \text{Final}$, $0 = \text{More fragments follow}$).

#### Opcode (4 bits): Defines payload interpretation:

- **0x1**: Text Data (UTF-8)
- **0x2**: Binary Data
- **0x8**: Connection Close
- **0x9**: Ping (Heartbeat)
- **0xA**: Pong (Heartbeat response)

- **MASK Bit (1 bit)**: Defines if the payload is XOR-masked. Mandatory for all client-to-server frames($1$). Must be 0 for server-to-client frames.

- Why Mask Client Frames? To prevent Cache Poisoning Attacks on intermediate web proxies that might misinterpret raw binary client requests as standard HTTP GET queries.

#### Payload Length (7 bits, 7+16 bits, or 7+64 bits):

- **$0\text{--}125$**: Actual payload length.
- **$126$**: Read the next 16 bits as an unsigned integer length.
- **$127$**: Read the next 64 bits as an unsigned integer length.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### High-Scale Architecture, Failure Modes & Edge Mitigations

#### 1. Horizontal Scaling & Statefulness (The Distributed Stateful Socket Problem):

Unlike stateless HTTP API nodes, WebSocket servers are stateful. Node A holds the physical TCP socket for User 1; Node B holds the physical TCP socket for User 2. If User 1 sends a message to User 2, Node A cannot directly write to User 2's socket.

```
+-----------------------------------------------------------------------------------+
| Distributed Pub/Sub Architecture                                                  |
+-----------------------------------------------------------------------------------+
[ Client 1 ] ---> (TCP Socket) ---> [ WS Gateway Node A ]
    |
    v (Publish Message)
+-------------------------------+
| Redis Pub/Sub / NATS Core     |
+-------------------------------+
    |
    v (Broadcast to Channel)
[ Client 2 ] <--- (TCP Socket) <--- [ WS Gateway Node B ]
+-----------------------------------------------------------------------------------+
```

- **Architectural Fix**: Decouple connection management from business logic using a central Pub/Sub Backplane (Redis Pub/Sub, NATS, or Apache Kafka).
- Each client registers its connection on a specific WebSocket Gateway node.
- The gateway node subscribes to a message queue channel specific to the connected user_id or room_id.
- When an event fires, the backend publishes the message to the Pub/Sub bus. The gateway node hosting that socket receives the event and writes it directly to the local socket.

#### 2. Reconnection Storms & "Thundering Herd":

If a WebSocket gateway node handling 50,000 active connections crashes or undergoes a deployment restart,50,000 clients simultaneously detect a socket drop and attempt to re-establish the connection and re-authenticate within seconds, crashing downstream Auth services and DBs.

#### Mitigations:

Truncated Exponential Backoff with Jitter: Clients must compute reconnection delays with random variance:

- $$\text{Delay} = \min(\text{MaxDelay}, \text{BaseDelay} \times 2^{\text{retry\_count}}) + \text{RandomJitter}$$

- Connection Throttling at Edge: Enforce strict rate limits on incoming HTTP Upgrade requests at the API Gateway / Load Balancer layer.

#### 3. Missed Message Recovery (State Synchronization):

WebSocket guarantees in-order message delivery over an active TCP socket. However, if the client loses mobile connectivity for 15 seconds, any messages published over the server bus during that window are lost.

- Architectural Solution: Sequence Tracking + WAL (Write-Ahead Log)
- Every message emitted in a channel/room is assigned a monotonically increasing sequence ID (msg_seq_id: 1001, 1002, 1003).
- Messages are buffered in a fast key-value store (e.g., Redis Streams) with a defined TTL (e.g., 24 hours).
- Upon reconnecting, the client sends its last acknowledged sequence ID: CONNECT /chat?last_seq_id=1002.

The server replays missed messages from the buffer (1003+) before transitioning the socket back to live streaming mode.

#### 4. Security & Authentication Pitfalls:

- **Cross-Site WebSocket Hijacking (CSWSH)**: Browsers send cookies automatically with the initial HTTP Upgrade request! An attacker website can execute a client-side JS script to initiate a wss://your-api.comconnection, and the browser will attach victim auth cookies.
- **Mitigation**: Strictly validate the Origin header during the HTTP Upgrade handshake. If the Origindoes not match an explicit whitelist, return HTTP 403 Forbidden.

#### Handshake Authentication Strategy:

- **Avoid**: Passing JWTs in the query parameter string (wss://api.com?token=eyJ...) because query parameters are logged in plain text in proxy logs, browser histories, and edge routing logs.
- **Recommended Pattern (Ticket Exchange)**: Client makes a short-lived HTTP POST request to obtain a single-use authorization ticket UUID. Client passes this ticket during the WS handshake wss://api.com?ticket=uuid-v4. Server validates, consumes, and destroys the ticket immediately.

---

### 5. Text-Based Architecture Diagram:

```
Scalable Enterprise Distributed WebSocket System Design
===================================================================================
                                CLIENT BOUNDARY
===================================================================================

      [ Web Client ]             [ Mobile App ]          [ Desktop Client ]
             |                          |                        |
             +--------------------------+------------------------+
                                        |
                               WSS (TLS Encryption)
                                        |
                                        v
===================================================================================
                            EDGE LOAD BALANCING LAYER
===================================================================================
                    +---------------------------------------+
                    |    L7 Load Balancer (Envoy / ALB)     |
                    | - Validates Origin Header (Anti-CSWSH)|
                    | - TLS Termination                     |
                    | - Routes /ws path to Gateway Nodes    |
                    +---------------------------------------+
                                        |
              +-------------------------+-------------------------+
              |                                                   |
              v                                                   v
===================================================================================
                      STATEFUL WEBSOCKET GATEWAY CLUSTER
===================================================================================
+----------------------------------+             +----------------------------------+
|    WebSocket Gateway Node 1      |             |    WebSocket Gateway Node 2      |
|                                  |             |                                  |
| - Manages Active TCP Sockets     |             | - Manages Active TCP Sockets     |
| - Executes Ping/Pong Heartbeats  |             | - Executes Ping/Pong Heartbeats  |
| - Subscribed to Redis Channel A  |             | - Subscribed to Redis Channel B  |
+----------------------------------+             +----------------------------------+
              ^                                                   ^
              |                                                   |
===================================================================================
                      DISTRIBUTED PUB/SUB BACKPLANE & CACHE
===================================================================================
              |                                                   |
              +-------------------------+-------------------------+
                                        |
                        +-------------------------------+
                        |   Redis Cluster / NATS Core   |
                        |  - Pub/Sub Channel Routing    |
                        |  - Redis Stream (Message WAL) |
                        +-------------------------------+
                                        ^
                                        | Internal Event Publish
===================================================================================
                        INTERNAL MICROSERVICES MESH
===================================================================================
                                        |
                        +-------------------------------+
                        |    Chat / Event Microservice  |
                        |  - Business Logic Processing  |
                        |  - Writes to Main DB          |
                        +-------------------------------+
```

---

### 6. Interview Checklist:

When designing or answering questions about WebSockets in system design interviews:

- **State the Selection Justification**: Choose WebSockets only when the system requires bi-directional, full-duplex, high-frequency, low-latency interaction (e.g., collaborative canvas, chat rooms, multiplayer state). Default to SSE or HTTP Long Polling if interaction is strictly unidirectional (Server $\to$ Client).

- **Address Horizontal Scaling Explicitly**: Explain that because WebSocket nodes are stateful, you must decouple connection state from message distribution using a central Pub/Sub backplane (Redis Pub/Sub, NATS, or Kafka) to route messages between nodes.

#### Demonstrate Security Hardening:

- Mention checking the Origin header during the HTTP Upgrade handshake to prevent Cross-Site WebSocket Hijacking (CSWSH).

- Pitch the One-Time Token Ticket Exchange pattern for socket authentication instead of leaking JWTs in URL query strings.

#### Address System Fault Tolerance & Resiliency:

- Explain how to prevent thundering herd problems on reconnect via Exponential Backoff with Jitter.

- Address lost message recovery on reconnection by designing a Sequence Number tracking system backed by an append-only message log buffer (e.g., Redis Streams).
