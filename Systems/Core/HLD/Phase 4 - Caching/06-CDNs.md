## Content Delivery Networks (CDNs)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a global book publishing company located exclusively in Seattle, Washington:

- **Single Origin Server (No CDN)**: Every reader in Tokyo, London, Sydney, and Buenos Aires must order physical books shipped directly from the central Seattle warehouse via ocean cargo. A reader in Tokyo waits 3 weeks for delivery (250 ms Latency), while the Seattle warehouse collapses under the weight of processing millions of individual international shipping packages simultaneously (Origin CPU/Bandwidth Overload).

- **Content Delivery Network (Regional Distribution Hubs)**: The publisher opens 200 micro-fulfillment centers (Points of Presence / POPs) in major cities around the world, pre-stocking copies of best-selling books in local Tokyo, London, and Sydney warehouses. When a reader in Tokyo orders a book, it is delivered from the local Tokyo hub in 30 minutes (10 ms Latency). The central Seattle warehouse only ships new book masters to the hubs once (Origin Load Reduction).

#### The Core Problem Solved:

- Information cannot travel faster than the speed of light in optical fiber ($c \approx 200,000\text{ km/s}$). A round-trip network packet traversing from London to a server in California and back takes approximately $150 - 200\text{ ms}$ over the public internet, excluding TCP 3-way handshakes and TLS 1.3 negotiations.

- Content Delivery Networks (CDNs) solve physical geographic latency and origin capacity limits by deploying a globally distributed network of edge proxy servers (Edge POPs). CDNs cache static assets (images, video chunks, JS/CSS bundles, fonts) and accelerate dynamic traffic close to end-users, reducing physical Network Round Trip Times (RTT), preventing origin server downtime, and absorbing massive DDoS attacks at the network edge.

---

### 2. The Basics (Scratch Level):

#### Key Architectural Concepts:

- **Origin Server**: The primary database-backed application server (e.g., AWS EC2, Kubernetes cluster) where source data and business logic reside.
- **Edge Server / POP (Point of Presence)**: A data center facility located at internet exchange points (IXPs) worldwide holding caching proxies close to end-users.
- **Origin Shield**: An intermediate centralized caching layer positioned between distributed Edge POPs and the Origin server to consolidate cache misses and prevent origin traffic spikes.
- **Anycast Routing**: A network addressing technique where multiple physical edge servers across the globe advertise the exact same IP address using BGP (Border Gateway Protocol), routing users automatically to the topologically closest edge server.

#### Integration Models: Pull CDN vs. Push CDN

| Dimension                 | `Pull CDN (Origin Pull)`                                                                     | `Push CDN (Origin Push)`                                                                                       |
| ------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Mechanics**             | The CDN edge requests and fetches assets from the origin on-demand when a Cache Miss occurs. | The application proactively uploads assets to CDN storage before users ever request them (e.g., via SFTP/API). |
| **Origin Storage Burden** | Low. Origin stores assets normally.                                                          | High. Assets must be mirrored and managed in CDN storage buckets.                                              |
| **Cache Freshness**       | Managed via HTTP expiration headers (Cache-Control, TTL).                                    | Managed via explicit application upload/deletion pipelines.                                                    |
| **Stale First Read?**     | Yes. The first user to request a cold asset incurs an origin fetch delay.                    | No. Content is pre-warmed and ready for the very first request.                                                |
| **Best Use Cases**        | High-traffic websites, web applications, news portals, REST APIs.                            | Large software installers, mobile app updates, massive video-on-demand files ($>100\text{ MB}$).               |

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. Anycast BGP Routing & Connection Termination:

```
ANYCAST NETWORK ROUTING FLOW
Client (Tokyo) ──────► [ IP: 192.0.2.1 ] ──► (BGP Routes to Nearest POP) ──► Tokyo Edge POP (10ms)
Client (London) ─────► [ IP: 192.0.2.1 ] ──► (BGP Routes to Nearest POP) ──► London Edge POP (12ms)
```

#### How Anycast Eliminates Latency:

- **Shared IP Address**: All CDN POPs globally share a single public IP block (e.g., 192.0.2.1).
- **Topological Routing**: Internet Service Provider (ISP) routers evaluate BGP path vectors and automatically direct the client's DNS and TCP packets to the physical POP with the fewest network hops.
- **Edge TLS Termination**: The client establishes TCP ($1\text{ RTT}$) and TLS 1.3 ($1\text{ RTT}$) connections directly with the local Edge POP. Because physical distance is short, handshake latency drops from $200\text{ ms}$ down to $10\text{ ms}$.
- **Persistent Origin Links**: The Edge POP maintains warm, pre-established, persistent TCP/HTTP/2 connections back to the Origin Server over optimized private tier-1 backbone fiber networks, eliminating handshake overhead for origin fetches.

#### 2. HTTP Cache Control Directives & Validation Headers:

CDNs determine whether to store, serve, or revalidate content based on HTTP/1.1 and HTTP/2 headers:

```
┌───────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────┐
│ HTTP Response Header Directive                │ Behavioral Function inside CDN Edge Proxy                                     │
├───────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────┤
│ `Cache-Control: public, max-age=3600`         │ Cachable by browsers AND public CDN edge proxies for 3,600 seconds.           │
│ `Cache-Control: private, max-age=600`         │ Cachable ONLY by the end-user's browser. CDN Edge proxies MUST NOT cache.     │
│ `Cache-Control: s-maxage=86400`               │ Overrides `max-age` specifically for shared caches (CDNs). Expire in 1 day.   │
│ `Cache-Control: no-cache`                     │ Edge MAY store content, but MUST revalidate with origin before serving reads. │
│ `Cache-Control: no-store`                     │ Never store or cache payload under any circumstances (e.g., banking responses)│
│ `Surrogate-Control: max-age=604800`           │ Edge-only directive (stripped before forwarding response to client browser).  │
│ `Vary: Accept-Encoding, User-Agent`           │ Tells CDN to create separate cache variants per encoding/device type.         │
└───────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────┘
```

#### Conditional Revalidation (304 Not Modified):

When a cached object's TTL expires, the CDN sends a conditional validation request to the origin containing revalidation tokens:

- **If-None-Match**: "e3b0c44298fc1c14" (Validates against ETag hash)
- **If-Modified-Since**: Wed, 21 Oct 2026 07:28:00 GMT

- If the data hasn't changed, the origin returns HTTP 304 Not Modified without a response body, saving $99\%$of network bandwidth while resetting the CDN TTL.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Edge Computing (Serverless at the Network Edge):

Modern CDNs (Cloudflare Workers, Fastly Compute@Edge, AWS Lambda@Edge) move executable application logic onto CDN edge nodes, running code inside lightweight V8 JavaScript Isolates or WebAssembly (Wasm) runtimes in sub-milliseconds ($<1\text{ ms}$ cold start).

```
                           EDGE COMPUTE ROUTING PIPELINE

[ Client Request ] ──► [ CDN Edge POP ]
         │
         ▼
[ Edge Compute Worker (V8/Wasm) ]
         │
         ├──► 1. Edge Auth Verification (JWT Validation)
         ├──► 2. A/B Testing Variant Routing
         ├──► 3. Geo-Blocking & Request Header Modification
         └──► 4. Dynamic HTML Personalization / Edge Rendering
```

#### Edge Compute Use Cases:

- **JWT Authentication at Edge**: Rejects unauthorized requests at the CDN border before they reach origin servers.
- **A/B Testing & Personalization**: Swaps HTML components or rewrites request paths without origin redirects.
- **Geo-IP Routing & Compliance**: Restricts access or redirects users based on country code compliance constraints (GDPR).

#### Dynamic Site Acceleration (DSA):

- Not all web traffic can be cached (e.g., personalized shopping carts, real-time financial trading APIs, user feeds). CDNs accelerate non-cachable dynamic POST/PUT requests using Dynamic Site Acceleration (DSA):

- **Route Optimization**: CDNs continuously measure public internet congestion and route dynamic traffic over private, uncongested tier-1 fiber backbones, bypassing public BGP peering bottlenecks.
- **Connection Pooling & Pre-Warming**: Edge POPs keep long-lived, pre-warmed TCP and TLS connections open to origin servers, avoiding $3\text{-way handshakes}$ on every dynamic API call.
- **TCP Window & Buffer Optimization**: Edge nodes tune TCP congestion window sizes ($initcwnd$) and enable TCP Fast Open (TFO) over high-speed backbone links.

#### Multi-CDN Architecture & DNS Steering:

To protect against global CDN vendor outages (e.g., Fastly/Cloudflare global outages) and optimize regional performance, enterprise platforms deploy a Multi-CDN Strategy:

```
                        MULTI-CDN DNS STEERING PIPELINE

        [ Client ] ───(1. DNS Query)───► [ Smart DNS Router (NS1 / RUM) ]
                                      │
        Evaluates Real-Time Performance & Availability Data
                                      │
            ┌─────────────────────────┴─────────────────────────┐
            ▼                                                   ▼
[ CDN Vendor A (Cloudflare) ]                        [ CDN Vendor B (Fastly) ]
(Selected for EU/US Users)                           (Selected for APAC Users)
```

- **RUM-Based Steering (Real User Monitoring)**: Client browsers run telemetry scripts measuring actual latency to multiple CDN vendors. A smart DNS router (e.g., NS1, Cedexis) dynamically directs client DNS requests to the fastest operational CDN vendor in that specific geographic region.
- **Unified Invalidation Layer**: Requires building abstraction scripts that translate cache purge events into vendor-specific API calls (Cache-Tags / Surrogate-Keys) across all active CDN providers simultaneously.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
           CDN EDGE ARCHITECTURE & ORIGIN SHIELD PIPELINE
================================================================================

[ User (Tokyo) ]             [ User (Seoul) ]             [ User (London) ]
      │                            │                            │
      ▼ (10ms Latency)             ▼ (12ms Latency)             ▼ (15ms Latency)
┌──────────────────────────┐ ┌──────────────────────────┐ ┌──────────────────────────┐
│ Tokyo Edge POP (Cache)   │ │ Seoul Edge POP (Cache)   │ │ London Edge POP (Cache)  │
└────────────┬─────────────┘ └────────────┬─────────────┘ └────────────┬─────────────┘
            │ (Cache Miss)               │ (Cache Miss)               │ (Cache Miss)
            └────────────────────────────┼────────────────────────────┘
                                         │
                                         ▼ (Consolidated Fetch via Backbone)
                            ┌──────────────────────────┐
                            │    ORIGIN SHIELD POP     │
                            │   (Centralized Cache)    │
                            └────────────┬─────────────┘
                                         │ (Single Consolidated Miss)
                                         ▼
                            ┌──────────────────────────┐
                            │    ORIGIN DB / CLUSTER   │
                            │    (Seattle, USA)        │
                            └──────────────────────────┘
================================================================================
```

---

### 6. Interview Checklist:

- **Quantify Physical Latency Limits**: Explain how the speed of light limits transatlantic packet travel ($150 - 200\text{ ms}$ RTT), and detail how CDNs reduce latency down to $10\text{ ms}$ by terminating TCP/TLS handshakes at local Anycast Edge POPs.

- **Explain Anycast Routing**: Detail how BGP Anycast advertises the exact same IP address across hundreds of global POPs, automatically routing users to the nearest physical edge node.

- **Differentiate max-age vs s-maxage vs Surrogate-Control**: Explain that max-age applies to browsers,s-maxage applies to shared CDN caches, and Surrogate-Control allows edge proxies to consume cache directives while stripping them before returning responses to browsers.

- **Explain Origin Shielding**: Show senior architectural insight by describing how an Origin Shield layer aggregates cache misses from hundreds of edge POPs down to a single request, protecting origin databases from traffic spikes.

- **Pitch Edge Compute & Multi-CDN for Resilience**: Recommend V8 Isolate / Wasm Edge Workers for running security checks and personalization at the edge, and Multi-CDN DNS Steering (via RUM metrics) to eliminate single-vendor CDN global outage risks.
