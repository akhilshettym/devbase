## HTTP (1/2/3) & HTTPS

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

The Hypertext Transfer Protocol (HTTP) is the application-layer foundation of the Web, defining how client applications request resources from web servers. Over time, HTTP evolved from simple text document retrieval into a high-performance transport system capable of driving complex web applications, real-time media, and microservice mesh architectures.

```
+-----------------------------------------------------------------------------------+
| Real-World Analogy: Logistics & Freight                                           |
+-----------------------------------------------------------------------------------+
| HTTP/1.1: Single-Lane Toll Bridge                                                 |
| - One item per truck. Each truck must wait for the truck ahead to clear the bridge|
| before crossing. A stuck truck blocks the entire line (App HoL Blocking).         |
|                                                                                   |
| HTTPS: Armored Escort                                                             |
| - Encloses every truck inside an uncrackable, tamper-evident container, verifying |
| the driver's identity before entry.                                               |
|                                                                                   |
| HTTP/2: Multi-Container Super-Truck on a Single Highway Lane                      |
| - Loads multiple labelled sub-containers (Streams) onto a single chassis (TCP).   |
| However, if a single tire pops on the highway (TCP Packet Loss), the whole        |
| truck halts until repaired (Transport HoL Blocking).                              |
|                                                                                   |
| HTTP/3: Independent Drone Swarm over UDP                                          |
| - Replaces the rigid highway with independent drones (QUIC over UDP).             |
| If one drone crashes, all other drones continue to fly to their destination.      |
+-----------------------------------------------------------------------------------+
```

- **HTTP/1.1**: Solved basic persistent connections (Keep-Alive), but suffered from Head-of-Line (HoL) blocking at the application level—requests had to complete in strict sequential order per connection.

- **HTTPS (HTTP Secure)**: Solved eavesdropping, tampering, and impersonation by executing HTTP inside an encrypted transport tunnel using TLS (Transport Layer Security).

- **HTTP/2**: Solved HTTP/1.1 concurrency limits by introducing binary framing and stream multiplexing over a single shared TCP connection.

- **HTTP/3**: Solved TCP-level Head-of-Line blocking and long connection setup latencies by replacing TCP+TLS with QUIC (a secure, multiplexed transport built on UDP).

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Headers & Payload**: Metadata key-value pairs (e.g., Content-Type, Authorization, Cache-Control) attached to the binary/text body of a request or response.
- **TLS (Transport Layer Security)**: The cryptographic layer providing Confidentiality (Symmetric Encryption), Integrity (HMAC/AEAD), and Authentication (X.509 Digital Certificates signed by Certificate Authorities).
- **SNI (Server Name Indication)**: A TLS extension where the client indicates the hostname it is trying to connect to during the handshake, allowing one IP address to serve multiple HTTPS certificates.
- **ALPN (Application-Layer Protocol Negotiation)**: A TLS extension that allows client and server to negotiate whether to use http/1.1, h2 (HTTP/2), or h3 (HTTP/3) during the initial TLS handshake without needing extra network round-trips.

#### Stream & Frame (HTTP/2 & HTTP/3):

- **Frame**: The smallest atomic unit of communication in HTTP/2 and HTTP/3 (e.g., HEADERS frame,DATA frame, SETTINGS frame).
- **Stream**: A bidirectional flow of frames sent within an established connection, identified by a unique Stream ID.

#### Protocol Generation Matrix:

| Feature                | `HTTP/1.1`                 | `HTTPS (Over HTTP/1.1 or H2)` | `HTTP/2`                                     | `HTTP/3`                                |
| ---------------------- | -------------------------- | ----------------------------- | -------------------------------------------- | --------------------------------------- |
| **Transport Layer**    | TCP                        | TCP                           | TCP                                          | UDP (via QUIC)                          |
| **Data Format**        | Plain Text                 | Encrypted Text / Binary       | Binary Frames                                | Binary Frames                           |
| **Encryption**         | None (Insecure)            | Mandated via TLS (1.2 / 1.3)  | Optional in Spec, Mandated by Browsers (TLS) | Built-in (TLS 1.3 integrated into QUIC) |
| **Multiplexing**       | No (Sequential / Pipeline) | Inherited from base protocol  | Yes (Single TCP Connection)                  | Yes (Independent UDP Streams)           |
| **Header Compression** | None (Gzip body only)      | None / HPACK (if H2)          | HPACK (Static + Dynamic Tables)              | QPACK (Out-of-order resilient)          |
| **HoL Blocking**       | Application Level          | Depends on base protocol      | TCP Transport Level                          | None (Stream-isolated loss)             |
| **Connection Setup**   | 1 RTT (TCP)                | 2–3 RTTs (TCP + TLS)          | 2–3 RTTs (TCP + TLS)                         | 0-RTT or 1-RTT(Combined Handshake)      |

---

### 3. Deep Dive & Architecture (Mid Level):

#### HTTPS / TLS 1.3 Handshake Mechanics:

Modern HTTPS mandates TLS 1.3, which drastically reduced connection setup latencies compared to TLS 1.2 by cutting the security handshake from 2 RTTs to 1 RTT.

```
Client Server
|                                                              |
| --- ClientHello -------------------------------------------> |
|                                 + Key Share (Diffie-Hellman) |
|                      + Cipher Suites, SNI, ALPN ("h2", "h3") |
|                                                              |
|  <--------------------------- ServerHello ------------------ |
|                                 + Key Share (Diffie-Hellman) |
|                                 + Encrypted Extensions       |
|                                 + Certificate & CertVerify   |
|                                 + Finished                   |
|                                                              |
|        [Client Derives Keys & Validates Cert]                |
| --- Finished + Encrypted HTTP Request ---------------------> |
|                                                              |
| <--------------------------- Encrypted HTTP Response ------  |
```

- **Key Exchange (ECDHE)**: TLS 1.3 generates ephemeral Elliptic Curve Diffie-Hellman keys upfront during the initial ClientHello, delivering Perfect Forward Secrecy (PFS)—meaning even if the server's private key is leaked later, historical recorded traffic cannot be decrypted.

- **Symmetric Payload Encryption**: Once the handshake completes, all application data is encrypted using authenticated fast symmetric ciphers like AES-GCM or ChaCha20-Poly1305.

- **HTTP/2 Internal Mechanics**: Binary Framing & HPACK

HTTP/2 transforms the HTTP protocol by removing human-readable text formatting on the wire and introducing an abstraction layer: Binary Frames over Streams.

```
TCP Connection
└── Stream 1 (e.g., index.html) ──> [HEADERS Frame] [DATA Frame] [DATA Frame]
└── Stream 3 (e.g., style.css) ──> [HEADERS Frame] [DATA Frame]
└── Stream 5 (e.g., script.js) ──> [HEADERS Frame] [DATA Frame] [DATA Frame]
```

- **Multiplexing over 1 TCP Connection**: Multiple requests and responses interleave concurrently on the same TCP connection using different Stream IDs (odd numbers for client-initiated, even for server-initiated).
- **HPACK Header Compression (RFC 7541)**: Headers like user-agent or cookie repeat heavily across requests. HPACK maintains two lookup tables:
- **Static Table**: Pre-defined index of 61 common headers (e.g., Index 2 = GET, Index 8 = https).
- **Dynamic Table** Stateful lookup table built dynamically during the connection session. Header strings are converted into small numeric index pointers or compressed via Huffman Coding.

#### HTTP/3 & QUIC Mechanics: Rebuilding Transport over UDP:

While HTTP/2 solved application-level HoL blocking, it introduced a new issue: TCP-level Head-of-Line Blocking. Because TCP enforces a single continuous sequence of bytes, if a single TCP segment carrying data for Stream 3 is lost, the kernel stops delivering bytes for Streams 1, 5, and 7 to the application until the lost segment is retransmitted.

HTTP/3 runs over QUIC, which implements reliable transport and encryption natively on top of UDP.

```
+------------------------------------------------------------------+
| Protocol Stack Comparison                                        |
+------------------------------------------------------------------+
| HTTP/1.1 HTTPS / HTTP/2 HTTP/3                                   |
| +----------+ +---------------+ +--------------------+            |
| | HTTP     | | HTTP/1.1 or H2| | HTTP/3             |            |
| +----------+ +---------------+ +--------------------+            |
| | (None)   | | TLS 1.2/1.3   | | QUIC (TLS 1.3 +    |            |
| +----------+ +---------------+ | Congestion/Control)|            |
| | TCP      | | TCP           | +--------------------+            |
| +----------+ +---------------+ | UDP                |            |
| | IP       | | IP            | | IP                 |            |
+------------------------------------------------------------------+
```

#### QUIC Core Breakthroughs:

- **Stream-Isolated Packet Processing**: QUIC frames are mapped directly into UDP datagrams. Packet loss on Stream A pauses only Stream A; Streams B and C continue processing uninterrupted.
- **QPACK Header Compression**: Unlike HPACK (which relies on strict ordered byte delivery), QPACK allows out-of-order header decoding across streams using encoder/decoder control channels, preventing QPACK state blocking over lossy UDP links.
- **Connection Migration via Connection IDs (CIDs)**: TCP connections are defined by a 4-tuple (Source IP, Source Port, Dest IP, Dest Port). If a mobile device switches from Wi-Fi to 5G, its IP changes, breaking the TCP socket. QUIC uses an explicit 64-bit Connection ID in the header. The connection persists seamlessly even when the client's network interface and IP address change.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Performance Engineering & Edge Cases:

#### 1. UDP Blocking and Firewall Fallbacks (Happy Eyeballs for H3):

- Many enterprise firewalls, corporate VPNs, and legacy ISPs throttle or drop UDP traffic on port 443 under the assumption that it represents DNS amplification attacks or unauthorized traffic.
- Mitigation: Clients implement Happy Eyeballs for HTTP/3. The client sends an initial TLS request over TCP while concurrently probing HTTP/3 over UDP via the Alt-Svc (Alternative Services) header received in earlier HTTP responses. If UDP fails or times out, the client silently falls back to HTTP/2 over TCP without breaking the user experience.

#### 2. TLS 1.3 / QUIC 0-RTT Early Data Replay Attacks:

- TLS 1.3 and QUIC support 0-RTT connection resumption, enabling a client that has previously connected to a server to send encrypted HTTP payload data inside the very first packet using cached cryptographic keys.
- **Trade-off / Risk**: 0-RTT data is vulnerable to Replay Attacks. An attacker eavesdropping on the network can record the 0-RTT packet and re-transmit it to the server 1,000 times.
- **Architectural Rule**: Enforce that 0-RTT data must only be allowed for idempotent HTTP methods(GET, HEAD), and never for non-idempotent operations (POST, PUT, DELETE, or payment mutations).

#### 3. De-optimizing HTTP/2 & HTTP/3 Anti-Patterns:

- Legacy web optimizations engineered for HTTP/1.1 active systems turn into performance anti-patterns in HTTP/2 and HTTP/3:
- **Domain Sharding (Anti-Pattern)**: Splitting static assets across multiple domains (assets1.example.com,assets2.example.com) was used in HTTP/1.1 to bypass browser per-domain TCP connection limits (6 connections). In HTTP/2+, sharding forces multiple TCP/TLS handshakes, completely destroying single-connection multiplexing and HPACK compression efficiency.
- **Massive Asset Bundling (Anti-Pattern)**: Bundling all JS/CSS into one 5 MB file to avoid HTTP/1.1 request overhead creates massive cache invalidation costs. In HTTP/2+, send smaller, modular files,taking advantage of parallel stream multiplexing.

#### 4. Server Push vs. Early Hints (HTTP 103):

- **HTTP/2 Server Push (Deprecated)**: Allowed servers to send unrequested push streams to the client (e.g., pushing app.css when index.html was requested). In production, it frequently wasted bandwidth by pushing assets the browser already had cached, leading to its deprecation in major browsers (e.g.,Chrome).
- **Modern Replacement (HTTP 103 Early Hints)**: The server immediately responds with an informational 103 Early Hints status code containing <Link rel="preload"> headers while still processing the main HTML database query. This lets the browser fetch critical CSS/JS during server idle execution time safely.

---

### 5. Text-Based Architecture Diagram:

```
End-to-End Handshake & Stream Interleaving Flow
===================================================================================
1. HTTP/2 CONNECTION ESTABLISHMENT (TCP + TLS 1.3)
===================================================================================

Client                                                                       Server
 | ----- [1. SYN] ---------------------------------------------------------> | (1 RTT TCP)
 | <---- [2. SYN-ACK] ------------------------------------------------------ |
 | ----- [3. ACK + TLS 1.3 ClientHello + ALPN="h2"] -----------------------> | (1 RTT TLS)
 | <---- [4. TLS ServerHello + Encrypted Cert + SETTINGS Frame] ------------ |
 |
 |=== CONNECTION ESTABLISHED (Single TCP Byte Stream) ========================|
 |
 | ----- [Stream 1: HEADERS (GET /)] + [Stream 3: HEADERS (GET /app.js)] ---> | Multiplexed
 | <---- [Stream 1: DATA (HTML)]     + [Stream 3: DATA (JS)] --------------   | In Interleaved
 |                                                                            | Frames

===================================================================================
2. HTTP/3 CONNECTION ESTABLISHMENT (QUIC over UDP)
===================================================================================

Client                                                                       Server
 | ----- [1. UDP Datagram: QUIC Initial + TLS 1.3 ClientHello + ALPN="h3"] -> |
 | <---- [2. UDP Datagram: QUIC Handshake + TLS ServerHello + Encrypted Cert] | (1-RTT Combined!)
 |
 |=== CONNECTION ESTABLISHED (Independent QUIC Streams over UDP) ============|
 |
 | ----- [QUIC Stream 4: GET /index.html] ---------------------------------> |
 | ----- [QUIC Stream 8: GET /style.css]  ---------------------------------> |
 |                                                                           |
 |  *PACKET LOSS OCCURS ON STREAM 4*                                         |
 | <---- [QUIC Stream 8: DATA (CSS Delivered & Rendered Immediately)] ------ | (No HoL Blocking!)
 | <---- [QUIC Retransmitting Stream 4 DATA] ------------------------------- |
```

---

### 6. Interview Checklist:

When pitching or evaluating HTTP/HTTPS protocols in system design interviews:

- **Always Specify Protocols at System Boundaries**: Don't just say "HTTP". Clarify: "We will terminate HTTPS (TLS 1.3) at the Edge/CDN using HTTP/3 or HTTP/2 for client connections to optimize latency over mobile networks, while using internal HTTP/2 or gRPC over persistent TCP connections within the VPC microservice mesh."

- **Address Connection Pooling & Termination**: Mention edge TLS termination at Cloud Load Balancers (ALBs) or CDNs to keep heavy cryptographic operations, certificates, and handshake negotiation close to users (reducing round-trip distance).

#### Explain Transport Selection Criteria:

- Choose HTTP/2 for standard microservices and high-density API proxies operating inside reliable datacenters where packet loss is near zero.

- Choose HTTP/3 for user-facing edge traffic on mobile, cross-border, or high-latency lossy networks where stream isolation and connection migration (Wi-Fi $\leftrightarrow$ Cellular switching) provide huge user-perceived performance gains.

- **Mention HTTP/3 Fallback Strategy**: Demonstrate operational maturity by stating that any system design deploying HTTP/3 must support automatic fallback to HTTP/2 over TCP via Alt-Svc headers to handle enterprise firewalls blocking UDP port 443.
