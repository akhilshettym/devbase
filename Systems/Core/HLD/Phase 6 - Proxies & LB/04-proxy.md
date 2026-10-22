## Proxy & Reverse Proxy

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Proxies act as intermediaries between client applications and server destinations. The core distinction between a Forward Proxy and a Reverse Proxy lies in whom they represent and protect.

```
+-----------------------------------------------------------------------------------+
|                        Real-World Analogy: Representation                         |
+-----------------------------------------------------------------------------------+
| Forward Proxy: Personal Executive Assistant (Protects the Client)                 |
| - An assistant places calls on behalf of an executive. The vendor only sees and   |
|   talks to the assistant, never knowing the true identity or internal location    |
|   of the executive.                                                               |
|                                                                                   |
| Reverse Proxy: Hotel Front Desk / Receptionist (Protects the Server)              |
| - Guests talk exclusively to the receptionist. The receptionist coordinates key   |
|   cards, delegates requests to housekeeping or kitchen staff, and blocks          |
|   unauthorized access to private hotel suites. Guests never interact with the     |
|   cooks or cleaners directly.                                                     |
+-----------------------------------------------------------------------------------+
```

- **Forward Proxy (Client-Side Proxy)**: Sits in front of client devices (inside a corporate network or private client boundary). It intercepts outbound internet requests, evaluates egress security policies, masks client IP addresses, and caches external content. Use a forward proxy for corporate internet access control, client identity masking (VPNs), external content filtering, and egress data loss prevention (DLP).

- **Reverse Proxy (Server-Side Proxy)**: Sits in front of backend origin servers (at the edge of a cloud datacenters or VPC). It intercepts incoming public internet traffic before it hits application infrastructure.Use a reverse proxy for backend origin shielding, TLS/SSL termination, centralized rate limiting, load balancing, web application firewall (WAF) security, and response caching.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Origin Server**: The actual backend compute node (e.g., Node.js app, Go microservice, database engine) executing application logic and serving primary data.
- **Transparent Proxy**: A proxy that intercepts network traffic at the router/network layer without requiring any software or network configuration changes on the client device.
- **Explicit / Configured Proxy**: A proxy where client applications or operating systems must explicitly specify the proxy IP and port in network settings.
- **HTTP CONNECT Method (Tunneling)**: A standard HTTP verb used by forward proxies to establish raw,uninspected TCP tunnels for HTTPS endpoints without terminating TLS encryption.
- **SSL/TLS Bumping (Inspection)**: A forward proxy security technique where the proxy decrypts client-to-internet HTTPS traffic by impersonating external domains using a enterprise-trusted custom Root CA certificate.

#### Comparison Matrix:

| Feature                 | `Forward Proxy`                          | `Reverse Proxy`                               |
| ----------------------- | ---------------------------------------- | --------------------------------------------- |
| **Primary Beneficiary** | Client / User Internal Network           | Server / Backend Infrastructure               |
| **Network Location**    | Client Edge (Corporate Network Boundary) | Server Edge (Cloud Ingress / VPC Ingress)     |
| **IP Masking Target**   | Hides Client IP from external servers    | Hides Backend Server IPs from public internet |
| **Client Awareness**    | Usually known (Configured in OS/Browser) | Completely invisible to external clients      |
| **Popular Engines**     | Squid, HAProxy, Charles, Zscaler         | NGINX, Envoy, Traefik, Cloudflare, HAProxy    |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Interception Workflows:

#### 1. Forward Proxy Mechanics: HTTP Plaintext vs. HTTPS Tunneling:

Forward proxies handle HTTP and HTTPS traffic using two completely different transport models:

```
===================================================================================
1. PLAINTEXT HTTP FORWARD PROXY (Proxy Reads Payload)
===================================================================================

Client                                 Forward Proxy                         Origin Server
  |                                          |                                     |
  | --- GET http://example.com/file -------->|                                     |
  |                                          | [Inspects URL, Headers & Cookies]   |
  |                                          | [Applies Egress Security Rules]     |
  |                                          | --- GET /file (Host: example.com) ->|
  |                                          | <-- HTTP 200 OK (Payload) --------- |
  | <-- HTTP 200 OK (Payload) ---------------|                                     |

===================================================================================
2. ENCRYPTED HTTPS TUNNELING via HTTP CONNECT (Blind TCP Pipe)
===================================================================================

Client                                 Forward Proxy                         Origin Server
  |                                          |                                     |
  | --- CONNECT example.com:443 HTTP/1.1 --->|                                     |
  |                                          | [Validates IP / Domain ACLs]        |
  |                                          | === Opens TCP Socket to 443 ======> |
  | <-- HTTP/1.1 200 Connection Established -|                                     |
  |                                          |                                     |
  |=== [ TLS Handshake & Encrypted Data Pipe Direct Client <---> Origin ] =========|
  | <=============================================================================>|
  | (Proxy CANNOT read or modify encrypted payload unless TLS Bumping is enabled)  |
```

- **HTTP Mode**: The client explicitly sends the absolute URL in the request line (GET [http://example.com/index.html](http://example.com/index.html)). The proxy parses the full request headers, applies domain blocklists, and forwards the request to the target origin.

- **HTTPS Tunneling Mode (CONNECT)**: The client requests an encrypted tunnel to example.com:443. The forward proxy opens a TCP socket to the destination IP and returns 200 Connection Established. From that moment on, the proxy blindly pipes raw byte streams back and forth without visibility into the underlying encrypted TLS application traffic.

#### 2. Reverse Proxy Mechanics: Complete Ingress Decoupling:

A reverse proxy breaks the end-to-end network path into two isolated connection boundaries: Client $\to$Reverse Proxy and Reverse Proxy $\to$ Origin Server.

```
Client (Public Internet)                 Reverse Proxy Node                   Backend Microservice Pool
 |                                              |                                       |
 | === 1. TCP Handshake (Port 443) ===========> |                                       |
 | === 2. TLS 1.3 Handshake (Public Cert) ===>  |                                       |
 | --- 3. HTTP POST /v1/orders ---------------> |                                       |
 |                                              | [Terminates TLS & Decrypts]           |
 |                                              | [Executes Rate Limit & WAF Check]     |
 |                                              | [Selects Backend via Load Balancing]  |
 |                                              | [Rewrites Headers: X-Forwarded-For]   |
 |                                              |                                       |
 |                                              | === 4. Reuse Keep-Alive TCP Socket => |
 |                                              | --- 5. Forward HTTP POST /v1/orders ->|
 |                                              | <-- 6. HTTP 201 Created --------------|
 | <-- 7. Return Encrypted HTTP 201 ---------- |                                        |
```

- Header Injection: Because the backend origin sees the reverse proxy's local VPC IP address as the source connection, the reverse proxy injects context headers before passing the request downstream:
- X-Forwarded-For: Original public IP address of the client.
- X-Forwarded-Proto: Protocol used by the client (http vs https).
- X-Forwarded-Host: Original Host header requested by the client.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### High-Scale Architecture, Security & Performance Trade-offs:

#### 1. Upstream TCP Connection Pooling & Keep-Alive Optimization:

- Establishing a new TCP and TLS session for every incoming user request to backend microservices incurs heavy CPU and latency overhead.

- **Optimization Pattern**: Reverse proxies maintain persistent, pre-warmed TCP Connection Pools to backend origin servers.
- **How It Works**: When 1,000 distinct internet clients connect to the reverse proxy, the reverse proxy terminates those 1,000 edge connections and multiplexes their application requests over a small,persistent pool of 10 to 20 long-lived backend TCP connections, cutting internal VPC latency and socket allocation overhead.

```
1,000 Public Clients                       Reverse Proxy Node                  Backend Server Pool
  [ Client 1 ] \                                      |
  [ Client 2 ]  == (1,000 Edge Connections) ==>  [ Envoy ] == (15 Pooled Persistent Sockets) ==> [ Backend Node ]
  [ Client N ] /                                      |
```

#### 2. Service Mesh Architecture: Transparent Sidecar Reverse Proxies:

In modern cloud-native Kubernetes environments, the traditional single reverse proxy at the edge is complemented by Sidecar Reverse Proxies (e.g., Envoy in Istio) deployed directly alongside application containers inside the same pod.

```
Kubernetes Pod Boundary (Node A)             Kubernetes Pod Boundary (Node B)
+---------------------------------------+    +---------------------------------------+
|  Application Container (Go / Java)    |    |  Application Container (Go / Java)    |
|  (Communicates strictly via localhost)|    |  (Communicates strictly via localhost)|
|                  ^                    |    |                  ^                    |
|                  | (Local TCP)        |    |                  | (Local TCP)        |
|                  v                    |    |                  v                    |
|  Sidecar Proxy Container (Envoy)      |    |  Sidecar Proxy Container (Envoy)      |
+---------------------------------------+    +---------------------------------------+
                  ^                                            ^
                  |                                            |
                  +==== mTLS Encrypted Inter-Pod Tunnel =======+
                        (Automatic Cert Rotation & Tracing)
```

- **iptables / eBPF Interception**: System traffic is transparently redirected to the local Envoy sidecar proxy using iptables PREROUTING rules or eBPF socket programs without modifying application code.

- **Benefits**: The sidecar reverse proxies handle mutual TLS (mTLS) encryption, distributed tracing propagation (traceparent headers), service discovery, and circuit breaking transparently across the microservice mesh.

#### 3. Response Buffering vs. Unbuffered Streaming Trade-off:

- **Buffered Responses (Default for Web APIs)**: The reverse proxy reads the entire backend response payload into memory/disk buffers before delivering it to the client.
- **Advantage**: Protects slow backend nodes from being tied up by slow internet clients (e.g., a mobile client on a weak 2G network).

- **Unbuffered Streaming (Mandatory for SSE, WebSockets & Large Downloads)**: The reverse proxy forwards response data chunks immediately to the client as they arrive from the backend.
- **Advantage**: Delivers real-time sub-second latency for AI LLM token streaming (e.g., ChatGPT responses) or Server-Sent Events.
- **Configuration**: In NGINX, explicitly disable buffering using proxy_buffering off; or inject the response header X-Accel-Buffering: no.

---

### 5. Text-Based Architecture Diagram:

```
End-to-End Edge-to-Backend Enterprise Proxy Topology
===================================================================================
                        CLIENT & CORPORATE EGRESS BOUNDARY
===================================================================================

 [ Corporate Employee Workstation ]        [ Internal Application Client ]
                |                                         |
                +--------------------+--------------------+
                                     |
                        Standard Egress HTTP/HTTPS Traffic
                                     |
                                     v
                +------------------------------------------+
                |          FORWARD PROXY EDGE              |
                |  (Squid / Zscaler Egress Gateway)        |
                |  - Enforces URL / Domain Whitelists      |
                |  - Scans outbound traffic for DLP        |
                |  - Masks internal client IP range        |
                +------------------------------------------+
                                     |
                                     v
===================================================================================
                               PUBLIC INTERNET
===================================================================================
                                     |
                                     v
===================================================================================
                       SERVER INGRESS EDGE BOUNDARY
===================================================================================
                +------------------------------------------+
                |          REVERSE PROXY EDGE              |
                |  (Cloudflare / NGINX / Envoy Gateway)    |
                |  - Hides backend origin server IPs       |
                |  - TLS 1.3 Termination & SNI Routing     |
                |  - WAF Inspection & Rate Limiting        |
                |  - Edge Static Content Caching           |
                +------------------------------------------+
                                     |
                                     v
===================================================================================
                      INTERNAL SECURE MICROSERVICE VPC
===================================================================================
                +------------------------------------------+
                |       Private Microservice Nodes         |
                |  - Listens ONLY on private VPC IPs       |
                |  - Receives pre-warmed pooled HTTP conns |
                +------------------------------------------+
```

---

### 6. Interview Checklist:

When pitching or evaluating Proxies during a system design interview:

- **State the Boundary Orientation Immediately**: Frame the distinction sharply: "Forward proxies act on behalf of client clients to enforce egress security and anonymity; Reverse proxies act on behalf of backend server origins to enforce ingress security, TLS termination, and load balancing."

- **Highlight Backend IP Obfuscation**: Emphasize that reverse proxies act as an origin shield, ensuring backend microservices remain on private VPC subnets without public IP addresses, protecting them from direct network attacks.

- **Demonstrate Header Handling Awareness**: Call out the necessity of injecting standard tracking headers (X-Forwarded-For, X-Forwarded-Proto) at the reverse proxy so downstream backend services retain visibility into real client IPs and request protocols.

- **Proactively Pitch Upstream Connection Pooling**: Mention that high-throughput reverse proxies optimize backend performance by terminating short-lived public client connections at the edge and multiplexing requests over persistent, long-lived TCP connection pools to internal application servers.
