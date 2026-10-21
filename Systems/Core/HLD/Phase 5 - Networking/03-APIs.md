## REST vs GraphQL vs RPC (gRPC)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

At the Application Layer (OSI Layer 7), systems need standardized patterns to exchange data across network boundaries. While transport protocols like TCP and UDP handle bit delivery, REST, GraphQL, and gRPC define how application data is structured, requested, and processed.

```
+-----------------------------------------------------------------------------------+
|                   Real-World Analogy: Restaurant Services                         |
+-----------------------------------------------------------------------------------+
| REST: Fixed À La Carte Menu                                                       |
| - You order specific combo numbers (/burgers/1).                                  |
| - If a combo includes fries you don't want, you get them anyway (Over-fetching).  |
| - If you want dessert, you must place a separate second order (Under-fetching).   |
|                                                                                   |
| GraphQL: Custom Meal Order Form / Personal Chef                                   |
| - You hand the chef a single checklist specifying exact ingredients & amounts     |
|   (e.g., "Give me 2 patties, no lettuce, and 1 slice of cheese").                 |
| - The chef prepares and delivers precisely what you asked for in one tray.        |
|                                                                                   |
| gRPC: Pneumatic Tube to an Automated Kitchen                                      |
| - Pre-arranged, strict radio codes sent over a lightning-fast binary tube.        |
| - Machine-to-machine, zero human-readable text, hyper-optimized for throughput.   |
+-----------------------------------------------------------------------------------+
```

- **REST (Representational State Transfer)**: Solves client-server decoupling by leveraging standard HTTP verbs (GET, POST, PUT, DELETE) operating on uniform resource paths (/users/123/orders). Use REST for public APIs, web-based CRUD services, and systems requiring native HTTP caching at the CDN level.
- **GraphQL**: Solves over-fetching and under-fetching over client-facing networks by letting the client define the exact response shape in a single request. Use GraphQL for complex frontend applications, mobile apps with strict bandwidth limits, and Backend-for-Frontend (BFF) layers aggregating multiple downstream microservices.
- **gRPC (Remote Procedure Call)**: Solves network latency, heavy CPU serialization costs, and weak contract enforcement in high-scale East-West (service-to-service) traffic. It uses Protocol Buffers over HTTP/2 to execute typed, low-overhead remote method calls.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks

#### REST (Resource-Oriented):

- **Resource & URI**: Entities identified by paths (e.g., /api/v1/products).
- **HTTP Semantics**: Uses standard HTTP methods for operations (GET for read, POST for create, PUT/PATCH for update, DELETE for removal) and status codes (200 OK, 404 Not Found, 429 Too Many Requests).
- **Statelessness**: Every request contains all context needed to execute; no server-side HTTP session state is retained.

#### GraphQL (Graph-Oriented):

- **Schema Definition Language (SDL)**: A strictly typed file defining data types, relationships, Query(reads), Mutation (writes), and Subscription (real-time events).
- **Resolvers**: Server-side functions that fetch the data for each field defined in the GraphQL schema from underlying databases or microservices.
- **Single Endpoint**: All operations run via POST /graphql (or GET for simple queries).

#### gRPC (Contract-Oriented):

- **Protocol Buffers (.proto)**: A language-neutral, binary serialization format and Interface Definition Language (IDL).
- **Code Generation**: The protoc compiler automatically builds strongly typed client stubs and server interfaces across multiple languages (Go, Java, C++, Python, Node).
- **Unary & Streaming RPCs**: Supports traditional Request/Response, Server Streaming, Client Streaming, and Bi-directional Streaming natively.

#### Protocol Comparison Matrix:

| Feature                   | `REST`                        | `GraphQL`                         | `gRPC`                        |
| ------------------------- | ----------------------------- | --------------------------------- | ----------------------------- |
| **Data Paradigm**         | Resource-centric              | Graph / Client-shaped             | Function Call / RPC           |
| **Wire Format**           | JSON (typically) or XML       | JSON                              | Compact Binary (Protobuf)     |
| **Transport Layer**       | HTTP/1.1 or HTTP/2            | HTTP/1.1 or HTTP/2                | HTTP/2 (Mandatory)            |
| **Contract Enforcement**  | Optional (OpenAPI / Swagger)  | Mandatory (GraphQL Schema)        | Mandatory (.proto file)       |
| **Data Fetching Control** | Server-defined fixed payload  | Client-defined field selection    | Server-defined message schema |
| **Network Overhead**      | Medium–High (Verbose JSON)    | Medium (Text-based query string)  | Ultra-Low (Binary field tags) |
| **HTTP Caching**          | Native (Browser/CDN via URLs) | Complex (Application/Client-side) | None (Transport-level only)   |
| **Browser Support**       | Universal / Native            | Universal / Native                | Requires gRPC-Web or Proxy    |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Data Flow

#### 1. REST: Standard HTTP Pipeline:

```
   Client CDN Cache Origin API Server
   |                                         | |
   | --- GET /users/42 HTTP/1.1 -----------> | |
   | | --- [Cache Miss] ---------------------> |
   | | | [Query Database]
   | | <--- 200 OK (JSON Payload + ETag) ----- | [Serialize JSON]
   | <--- 200 OK (JSON + Cache-Control) ---- | |
```

- **Serialization**: Text-based JSON parsing (JSON.parse()) requires string scanning, memory allocations,and UTF-8 processing, creating noticeable CPU overhead at high QPS.
- **Cacheability**: Highly cacheable at HTTP proxies and CDNs using standard HTTP headers (Cache-Control: max-age=3600, ETag, If-None-Match).

#### 2. GraphQL: Query Processing AST Engine:

```
   Client Request: GraphQL Engine (Server)
   POST /graphql        ┌─────────────────────────────────────────┐
   {                    │ 1. Lexical Analysis & Parsing -> AST    │
   user(id: "42") {     │ 2. Schema Validation                    │
   name                 │ 3. Parallel Execution via Resolvers:    │
   orders { id amount } │ - resolveUser(id: "42")                 │
     }                  │ - resolveOrders(userId: "42")           │
   }                    └─────────────────────────────────────────┘
```

- **AST Generation**: The server parses the incoming raw query string into an Abstract Syntax Tree (AST)to validate syntax and field existence against the schema.
- **Resolver Traversal**: The execution engine walks the AST top-down. Field resolvers execute concurrently or sequentially.
- **Shape Guarantee**: The output JSON mirrors the exact tree shape of the requested query.

#### 3. gRPC: Protobuf Binary Encoding & HTTP/2 Framing:

gRPC gains its massive speed advantage by dropping JSON strings in favor of Protobuf Tag-Length-Value (TLV) binary serialization over HTTP/2 multiplexed streams.

Protobuf (.proto) Definition: Binary Output on the Wire:

```
message UserRequest { +--------+--------+------------------+
int32 user_id = 1; // Field tag 1 | Field | Wire | Field Value |
string name = 2; // Field tag 2 | Tag 1 | Type | (e.g., Varint 42)|
} +--------+--------+------------------+
(Field names are NEVER sent over wire!)
```

- **Tag-Based Serialization**: Field names (e.g., "user_id") are omitted from the payload. Only the integer field tag number (e.g., 1) is encoded, cutting wire payload size by up to 60–80% compared to JSON.
- **HTTP/2 Transport Efficiency**: Multiple gRPC procedure calls run simultaneously over a single long-lived TCP connection using HTTP/2 binary streams, eliminating connection setup overhead and Head-of-Line blocking.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

Performance Engineering, Edge Cases & System Failure Modes

#### 1. The GraphQL N+1 Database Problem:

- **The Failure Mode**: If a GraphQL query requests 10 users and their recent orders, a naive resolver implementation executes 1 query to fetch the 10 users, followed by 10 separate database queries to fetch orders for each user ($1 + 10 = 11$ DB round-trips).

- **Architectural Fix (DataLoader / Batching)**: Implement a batching and request-scoped caching utility (e.g., DataLoader). DataLoader defers field resolution across a single tick of the event loop, coalesces individual IDs into a single bulk array query (SELECT \* FROM orders WHERE user_id IN (1, 2, ... 10)), and distributes results back to individual field resolvers.

```
Naive Resolvers: 10x [ SELECT * FROM orders WHERE user_id = ? ] --> High Latency!
With DataLoader: 1x [ SELECT * FROM orders WHERE user_id IN (1,2,3...10) ]
```

#### 2. GraphQL Denial of Service (Query Complexity Attacks):

- **The Failure Mode**: Because clients control the query structure, a malicious actor can craft a deeply nested recursive query (user { friends { friends { friends { friends } } } }). This causes explosive CPU usage and database connection pool exhaustion.

#### Mitigation:

- **Query Depth Limiting**: Reject queries with static nesting depth $> N$.
- **Query Complexity Analysis**: Assign point costs to fields (e.g., scalar = 1, relation = 10). Calculate total query cost before execution; reject if cost exceeds maximum threshold.
- **Persisted Queries (Automatic Persisted Queries - APQ)**: Clients register query hashes at build time. In production, clients pass only the SHA256 hash instead of raw query text.

#### 3. gRPC Client-Side Balancing & Deadlines Propagation:

- **Client-Side Load Balancing**: Because gRPC uses persistent HTTP/2 TCP connections, standard L4 network load balancers fail—all traffic routes to a single backend instance.
- **Fix**: Use client-side load balancing (e.g., gRPC dual-naming resolution with Envoy proxy sidecars in Kubernetes) to route individual HTTP/2 streams across backend nodes.

- **Deadline Propagation**: In deep microservice call chains ($A \to B \to C \to D$), if Service D hangs,upstream callers waste resources waiting.
- **Fix**: gRPC natively propagates deadlines down the call stack via the grpc-timeout header. If Service A sets a 500ms deadline, and 300ms elapse before Service C calls Service D, Service D receives a remaining deadline of 200ms. If breached, the entire downstream branch aborts immediately (DEADLINE_EXCEEDED).

#### 4. Browser Accessibility: The gRPC Edge Barrier:

- **Problem**: Browsers cannot send arbitrary HTTP/2 frames directly due to browser JS API restrictions (e.g.,lack of fine-grained control over trailers and binary frames).
- **Fix**: Expose gRPC to browsers via gRPC-Web (which uses a proxy like Envoy to translate browser-compatible HTTP/1.1 or HTTP/2 payloads) or adopt modern Connect RPC protocols that gracefully downgrade to standard HTTP/1.1 JSON when communicating with web clients.

---

### 5. Text-Based Architecture Diagram:

```
Production Pattern: Hybrid Polyglot Enterprise Architecture
===================================================================================
                                 EDGE BOUNDARY
===================================================================================
                                      |
   [ Web App / Third Parties ]        |       [ iOS / Android Mobile Apps ]
                |                     |                     |
  REST / HTTP/2 | (Public APIs)       |      GraphQL / HTTPS| (Dynamic Views)
                v                     |                     v
  +---------------------------+       |       +---------------------------+
  |    Public REST Gateway    |       |       |  GraphQL BFF / Federation |
  |  (Kong / NGINX Edge Node) |       |       |   (Apollo / Hasura Mesh)  |
  +---------------------------+       |       +---------------------------+
                |                     |                     |
                +---------------------+---------------------+
                                      |
===================================================================================
                        INTERNAL MICROSERVICE MESH (VPC)
===================================================================================
                                      |
                        gRPC over HTTP/2 (Protobuf)
                        [East-West High-Speed Traffic]
                                      |
       +------------------------------+------------------------------+
       |                              |                              |
       v                              v                              v
+------------------+         +------------------+         +------------------+
|   Auth Service   |         |   Order Engine   |         | Payment Processing|
|   (Go Micro)     | <-----> |   (Java / C++)   | <-----> |   (Rust Micro)   |
+------------------+         +------------------+         +------------------+
       |                              |                              |
 [User DB]                      [Order DB]                    [Payment DB]
```

---

### 6. Interview Checklist:

When pitching API architecture choices in a system design interview:

- **Lead with the Enterprise Hybrid Consensus**: Don't declare one protocol "better." Pitch the industry standard pattern: "I would adopt REST or GraphQL for the public edge/client boundary, while utilizing gRPC for internal East-West microservice communication."

#### Justify Protocol Choice by Boundary Constraint:

- **REST**: Use when building public-facing APIs, integration partner interfaces, or services heavily reliant on CDN edge caching.

- **GraphQL**: Use for client-facing aggregations (BFFs) where mobile apps suffer from network round-trips or need varying data shapes across diverse screens.

- **gRPC**: Use for internal microservices requiring ultra-low latency, strict compile-time type safety,streaming, and high throughput.

- **Demonstrate GraphQL Operational Depth**: Mention DataLoader (to prevent $N+1$ query issues) and Query Complexity/Persisted Queries (to block DoS query attacks).

- **Demonstrate gRPC Operational Depth**: Explicitly mention HTTP/2 multiplexing, Protobuf Tag-based binary serialization, Deadline Propagation across microservices, and client-side load balancing via Envoy sidecars.
