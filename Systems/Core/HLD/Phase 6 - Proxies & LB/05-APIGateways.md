## API Gateways

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

In a microservices architecture, exposing dozens or hundreds of internal services directly to external clients creates massive complexity. Clients must manage dozens of individual service endpoints, implement complex authentication for each, and suffer high latency from making multiple cross-network calls to aggregate data.

```
+-----------------------------------------------------------------------------------+
|               Real-World Analogy: International Airport Terminal                  |
+-----------------------------------------------------------------------------------+
| Without an API Gateway: Direct Concourse Access                                   |
| - Passengers must find individual gate doors scattered across the city.           |
| - Every single gate runs its own passport control, bag check, and currency        |
|   exchange. Total chaos, duplicated effort, and massive security risks.           |
|                                                                                   |
| With an API Gateway: Central Concierge & Security Terminal                        |
| - All travelers enter through a single, highly optimized main terminal.           |
| - Central security validates tickets/passports (Authentication), enforces bag     |
|   limits (Rate Limiting), translates languages (Protocol Translation), and        |
|   directs travelers smoothly to their exact concourse (Routing).                  |
+-----------------------------------------------------------------------------------+
```

- **The Problem It Solves**: An API Gateway solves client-side operational clutter, security fragmentation,and backend tight-coupling. It acts as a single managed entry point sitting between external clients and internal microservices.

- **Primary Use Cases**: Edge security offloading (JWT/OAuth2 validation, WAF), centralized traffic management (rate limiting, canary routing), protocol translation (REST to gRPC/Kafka), response aggregation (Backend-For-Frontend), and unified API observability.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

#### Data Plane vs. Control Plane:

- **Data Plane**: The ultra-fast runtime proxy engine executing packet processing, plugin execution,header mutations, and request forwarding for every incoming call (e.g., Envoy, Kong/NGINX,APISIX).
- **Control Plane**: The management layer that stores API definitions, routes, security policies, and rate-limit configs, distributing updates asynchronously to Data Plane nodes (e.g., Konnect, Envoy xDS).
- **Cross-Cutting Concerns**: Non-functional requirements offloaded from business services to the gateway edge (e.g., AuthN verification, SSL termination, rate limiting, request logging, CORS, caching).
- **Backend-For-Frontend (BFF)**: An architectural variant where separate, tailored API Gateways are deployed for specific client types (e.g., Mobile BFF vs. Web BFF vs. Third-Party Partner Gateway) to deliver optimized payload shapes for each client platform.

#### Architectural Comparison Matrix:

| Feature                  | `L7 Reverse Proxy (e.g., NGINX)`           | `API Gateway (e.g., Kong, Envoy, AWS API GW)`      | `Backend-For-Frontend (BFF)`         |
| ------------------------ | ------------------------------------------ | -------------------------------------------------- | ------------------------------------ |
| **Primary Scope**        | Ingress network routing & static balancing | Enterprise cross-cutting policies & API governance | Client-specific payload aggregation  |
| **Extensibility Model**  | Static configs or Lua/C modules            | Dynamic Plugin Pipeline (Lua, Go, WASM, JS)        | Custom application code (Node.js/Go) |
| **Authentication**       | Basic Header pass-through / TLS            | OIDC, OAuth2, JWT Validation, API Keys             | Custom Client Session / Cookie logic |
| **Traffic Control**      | Simple Leaky Bucket IP limits              | Distributed Sliding Windows per tenant/API key     | Custom business-tier throttling      |
| **Protocol Translation** | Limited (HTTP/1 to HTTP/2)                 | Advanced (REST $\to$ gRPC, Kafka, GraphQL, AI)     | Programmatic client-tailored mapping |

---

### 3. Deep Dive & Architecture (Mid Level):

#### nternal Mechanics & Execution Pipeline:

When a request hits an API Gateway, it moves through a sequential Inbound Plugin Pipeline, executes Upstream Routing, and completes an Outbound Plugin Pipeline.

```
Client Request
     │
     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       API GATEWAY DATA PLANE                        │
│                                                                     │
│  1. Ingress & TLS 1.3 Termination                                   │
│                                                                     │
│  2. Inbound Plugin Execution Chain:                                 │
│     ├── CORS Check                                                  │
│     ├── Global WAF / IP Blocklist                                   │
│     ├── Authentication (JWT Signature Check via local JWKS)         │
│     └── Distributed Rate Limiting (Redis Sliding Window check)      │
│                                                                     │
│  3. Route Matching & Payload Mutation:                              │
│     ├── Match `/v2/orders/*` -> `order-service.internal:8080`       │
│     ├── Strip public `Authorization: Bearer <jwt>`                  │
│     └── Inject verified headers: `X-User-Id: 8172`, `X-Role: ADMIN` │
└─────────────────────────────────────────────────────────────────────┘
     │
     │ 4. Forward via Pre-warmed Connection Pool
     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   INTERNAL MICROSERVICES VIRTUAL PRIVATE CLOUD  │
│                                                                 │
│  [ Order Service ] / [ Payment Service ] / [ User Service ]     │
└─────────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. Outbound Plugin Execution Chain:                            │
│     ├── Response Body Sanitization / Transformation             │
│     ├── Metric Logging & OpenTelemetry Trace Generation         │
│     └── Return Response to Client                               │
└─────────────────────────────────────────────────────────────────┘
```

#### Step-by-Step Processing Lifecycle:

- **Ingress & TLS Termination**: Client establishes an HTTPS session. The Gateway terminates TLS 1.3 at the edge using SNI certificate matching.

#### Inbound Security & Token Verification:

The Gateway validates API Keys or JWT signatures. Rather than calling an identity provider on every request, the gateway caches JWKS (JSON Web Key Sets) in memory to verify RSA/ECDSA cryptographic signatures offline in sub-milliseconds.

#### Distributed Rate Limiting:

The Gateway executes an atomic sliding window rate-limit query against a local memory buffer or Redis cluster (INCRBY + time bucket check). If the consumer exceeds their quota, the Gateway short-circuits the pipeline immediately, returning HTTP 429 Too Many Requests with a Retry-Afterheader.

#### Header Stripping & Identity Context Injection:

To enforce absolute perimeter security, the Gateway strips raw public user tokens (Authorization: Bearer <jwt>) and injects trusted internal headers (X-User-Id, X-User-Roles) before routing the request downstream.

#### Upstream Forwarding & Circuit Breaking:

The request routes to the destination microservice via internal persistent connection pools. If the downstream service starts failing (e.g., returning 503s or timing out), the gateway's internal Circuit Breaker trips, shedding load and failing fast to protect backend health.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Critical Failure Modes, Architectural Risks & Modern Trade-offs:

#### 1. The "Monolithic Gateway" Anti-Pattern (Organizational Coupling):

- **The Failure Mode**: Engineering teams fall into the trap of embedding domain-specific business logic inside custom gateway plugins (e.g., writing Lua or JavaScript scripts inside the gateway to calculate order discounts or check if a user is allowed to refund a product).
- **Consequence**: The API Gateway becomes a brittle monolithic bottle-neck. Every single feature release across 20 backend teams requires deploying code to the central gateway, creating massive operational coupling and deployment dependency cycles.
- **Architectural Rule**: Gateway owns Boundary Policy; Microservices own Domain Policy.
- **Boundary Policy (Gateway)**: Is this a valid token? Is this IP rate-limited? Is this request payload structurally valid?
- **Domain Policy (Microservice)**: Can User 8172 modify Order 9918? Is this account eligible for a refund?

#### 2. The Synchronous Auth Service Call Trap:

- **The Problem**: If an API Gateway processes $50,000\text{ QPS}$ and executes a synchronous HTTP RPC call to an internal Identity/Auth service on every single incoming request, the Auth service becomes the latency and availability bottleneck for the entire enterprise. If Auth slows down by $100\text{ ms}$, allproduct APIs slow down by $100\text{ ms}$.
- **Mitigation (Self-Contained Asymmetric Tokens)**: Use asymmetric signed tokens (JWTs). The Gateway fetches the public verification key (JWKS) asynchronously once every $N$ hours and verifies signatures locally in zero network hops.

#### 3. Topology Choice: Edge-Deployed vs. Region-Pinned:

Every gateway topology decision forces a performance vs. data residency trade-off:

- **Edge-Deployed (Global CDN/Edge Gateway)**: Deployed across hundreds of global POPs (e.g.,Cloudflare Workers, Zuplo).
- **Pros**: Ultra-low TLS handshake latency; global DDoS blocking close to the attacker; instantaneous API key validation.
- **Cons**: Complicates compliance/GDPR data residency; validation requires syncing rate-limit states across global edge locations.

- **Region-Pinned (Cloud VPC Gateway)**: Deployed inside the exact cloud region (e.g., AWS us-east-1) alongside backend services.
- **Pros**: Simple data sovereignty; zero cross-region database latency for rate-limiting.
- **Cons**: Higher latency for distant international users.

#### 4. Modern AI / LLM Gateway Extensions:

Modern API gateways handle generative AI traffic natively alongside traditional REST APIs (e.g., Kong AI Gateway, APISIX ai-proxy, WSO2 AI Gateway):

- **Multi-Provider Fallback**: Automatically routes prompt requests across LLM providers (e.g., OpenAI $\to$Anthropic $\to$ Self-hosted vLLM) if a provider experiences rate limits or outages.
- **Token-Based Rate Limiting**: Measures and enforces limits on Tokens Per Minute (TPM) and Cost-per-Tenant instead of simple Requests Per Minute (RPM).
- **Semantic Prompt Caching**: Caches LLM embeddings at the gateway edge to instantly serve identical prompt queries without paying downstream model inference costs.

### 5. Text-Based Architecture Diagram:

```
Scalable Enterprise API Gateway System Architecture
===================================================================================
                               PUBLIC INTERNET
===================================================================================
                                      │
                     Inbound Client Traffic (HTTPS / WSS)
                                      │
                                      ▼
===================================================================================
                 EDGE API GATEWAY CLUSTER (Kong / Envoy Data Plane)
===================================================================================
 +-----------------------------------------------------------------------------+
 |  API Gateway Node (Data Plane)                                              |
 |                                                                             |
 |  [Inbound Pipeline]                                                         |
 |   ├── WAF & IP Threat Filter                                                |
 |   ├── JWT Asymmetric Validation (Using Local In-Memory JWKS)                |
 |   └── Rate-Limit Evaluator (Queries Redis Sliding Window)                   |
 |                                                                             |
 |  [Route Matching & Context Injection]                                       |
 |   ├── Resolves `/v1/payments` -> `payment-service.vpc.internal`             |
 |   └── Injects `X-User-ID`, `X-Tenant-ID`, `X-Correlation-ID`                |
 +-----------------------------------------------------------------------------+
              │                                                │
              │ Fetch/Sync Policy Metadata                     │ Read/Write Counters
              v                                                v
 +---------------------------+                   +-----------------------------+
 |   Control Plane           |                   | Redis Cluster               |
 |   (Admin Config / GitOps) |                   | (Rate Limit Sliding Windows)|
 +---------------------------+                   +-----------------------------+
              │
              │ Forward Cleaned Request over Private VPC
              v
===================================================================================
                    INTERNAL SECURE MICROSERVICE VPC MESH
===================================================================================
       │                                 │                                 │
       ▼                                 ▼                                 ▼
+-------------------+             +-------------------+             +-------------------+
|  Order Service    |             |  Payment Service  |             |  AI / LLM Service |
|  (gRPC / HTTP)    |             |  (REST API)       |             |  (vLLM Ingest)    |
+-------------------+             +-------------------+             +-------------------+
```

---

### 6. Interview Checklist:

When pitching or evaluating API Gateways during a system design interview:

- **Define the Functional Scope Immediately**: State clearly: "I am introducing an API Gateway at the edge to serve as the single entry point for cross-cutting operational concerns—specifically handling TLS termination, JWT authentication offloading, rate limiting, and request routing to decouple internal microservices from public clients."

- **Establish the Auth Boundary Rule**: Emphasize that the Gateway performs Authentication (verifying who the caller is via signed JWTs), while downstream domain microservices handle Fine-Grained Authorization (verifying whether user X owns resource Y).

- **Avoid Gateway Coupling Pitfalls**: Explicitly point out the danger of putting domain business rules or heavy database lookups inside custom gateway plugins, keeping the gateway focused strictly on boundary policy to prevent operational coupling.

- **Proactively Pitch Stateless JWT Verification**: Explain how to avoid making the gateway an availability bottleneck by using asymmetric JWT validation with cached JWKS public keys instead of making synchronous HTTP calls to an identity service on every request.
