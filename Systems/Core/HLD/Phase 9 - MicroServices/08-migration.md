## Migrating to Microservices

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Migrating a production application from a monolith to a microservices architecture is one of the most high-risk software engineering maneuvers an organization can undertake. Attempting a "Big Bang" rewrite—stopping all new feature development to rebuild the entire system from scratch in microservices—is a infamous anti-pattern that almost universally leads to missed deadlines, stale feature sets, and catastrophic production failures.

- The golden rule of microservices migration is incremental, zero-downtime evolution using the Strangler Fig Pattern (named after the Australian rainforest vine that seeds in the upper branches of a tree, gradually grows around the trunk, and eventually replaces the original tree entirely).

```
+-----------------------------------------------------------------------------------+
| Real-World Analogy: Replacing a Highway Bridge                                    |
+-----------------------------------------------------------------------------------+
| Big Bang Migration: Stopping All Traffic to Demolish and Rebuild                  |
| - Shutting down a 6-lane highway completely for 2 years to build a new bridge.    |
| - Traffic halts, commuters revolt, and if the new bridge fails on opening day,    |
| the entire city grid is paralyzed (Catastrophic Business Risk).                   |
|                                                                                   |
| Strangler Fig Migration: Building Parallel Lanes with Traffic Rerouting           |
| - Building a new modern lane next to the old bridge piece by piece.               |
| - Dynamically rerouting $10\%$ of cars (traffic) onto the new lane to test load.  |
| - Gradually shift $100\%$ of traffic and quietly dismantle the old bridge lane    |
| without a single commuter noticing a delay (Zero-Downtime Migration).             |
+-----------------------------------------------------------------------------------+
```

- **The Primary Objective**: Safely extract business domains out of a monolith into independent microservices while keeping the legacy system fully operational and serving live traffic throughout the transition.

- **Core Rule**: Deconstruct the system one bounded context at a time, beginning with low-risk/high-value edge domains before attempting to extract the core transactional heart of the monolith.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Strangler Fig Pattern**: An architectural strategy that incrementally replaces monolithic capabilities with new microservices by intercepting incoming requests at an API Gateway boundary and routing them to the new service.
- **Bounded Context**: A domain boundary (from Domain-Driven Design) that defines where a specific business model applies cleanly without overlapping with other domains.
- **Anti-Corruption Layer (ACL)**: A translation layer built between a legacy monolith and a new microservice to translate domain models and API contracts, preventing legacy data structures from polluting the clean domain design of the new service.
- **Change Data Capture (CDC)**: A database streaming pattern (e.g., using Debezium + Kafka) that reads transaction logs from the monolith's database to asynchronously stream state changes to the new service's database in real time.
- **Branch by Abstraction**: A technique used in codebase refactoring where an interface abstraction layer is introduced inside the monolithic code to allow swapping the internal in-memory execution path with a remote microservice network call via feature flags.

#### Strategy Comparison Matrix:

| Vector                  | `Big Bang Rewrite`                             | `Incremental Strangler Fig Migration`                     |
| ----------------------- | ---------------------------------------------- | --------------------------------------------------------- |
| **Execution Style**     | Complete parallel rebuild, single cutover date | Continuous, module-by-module extraction                   |
| **Business Risk**       | Catastrophic (Single failure point)            | Low (Reversible per extracted service)                    |
| **Feature Velocity**    | Frozen or severely delayed during rewrite      | Continuous delivery of business features                  |
| **Time-to-Value**       | Months or years before initial release         | Weeks (Value realized per extracted service)              |
| **Data Consistency**    | Cutover requires complex data dump/restore     | Synchronized over time (CDC / Dual Writes)                |
| **Rollback Capability** | Nearly impossible without full downtime        | Instant (Toggle traffic back to monolith via API Gateway) |

---

### 3. Deep Dive & Architecture (Mid Level):

#### The 4-Step Microservice Extraction Lifecycle:

Migrating a single domain capability (e.g., Payment Service) out of a monolith requires executing a structured 4-step sequence:

```
[ Step 1: Intercept ] ──► [ Step 2: Extract & Build ] ──► [ Step 3: Data Sync ] ──► [ Step 4: Shift & Cutover ]
```

#### Step 1: Intercept Traffic (API Gateway / Ingress Layer)

Before altering monolithic code, introduce an API Gateway or reverse proxy (e.g., NGINX, Envoy, Kong) in front of the application. The gateway acts as a dynamic router, directing all traffic to the monolith initially.

```
Client ──► [ API Gateway ] ──(100% Traffic)──► [ Monolith (Auth + Catalog + Payments) ]
```

#### Step 2: Extract Domain & Build the Microservice

Identify a clean Bounded Context via Event Storming exercises. Build the new Payment Service as an autonomous application implementing its own independent database (Database-per-Service Pattern).

```
                           +--------------------------+
                           | New Payment Service      |
                           | (Node.js / Go)           |
                           +--------------------------+
                                        │
                                        ▼
                           [ Isolated Payment DB ]
```

#### Step 3: Data Migration & Real-Time Synchronization (Breaking the Shared DB)

The hardest part of microservices migration is decoupling the shared database. You cannot simply detach the payments table if monolithic SQL queries perform JOIN operations across users, orders, and payments.

#### Zero-Downtime Data Sync Engine (Change Data Capture - CDC):

Instead of executing dual-writes inside application code (which introduces distributed transaction bugs), use Change Data Capture (CDC) at the database transaction log level:

```
[ Monolith RDBMS ] ──(Reads WAL / Binary Log)──► [ CDC Engine (Debezium) ]
                                                       │
                                                       ▼
                                            [ Kafka Event Stream ]
                                                       │
                                                       ▼
                                            [ Sync Consumer Service ]
                                                       │
                                                       ▼
                                            [ New Payment DB ]
```

- **Historical Backfill**: Bulk-copy historical payment records from the Monolith DB to the Payment DB.
- **CDC Streaming**: Debezium monitors the Monolith DB transaction log (WAL/Binlog). Every INSERT/UPDATE/DELETE on payments is published to Apache Kafka and consumed by the Payment DB sync engine.

- Both databases remain in sync with millisecond-level replication lag without modifying monolithic code execution.

#### Step 4: Canary Traffic Shift & Final Cutover

Configure the API Gateway to execute Canary Routing. Gradually ramp up live traffic to the new microservice while monitoring error rates, latency histograms, and system health.

```
                              ┌── (95% Traffic) ──► [ Monolith ]
                              │
Client ──► [ API Gateway ]────┤
                              │
                              └── (5% Traffic)  ──► [ New Payment Service ]
```

- **Traffic Progression**: $0\% \to 1\% \to 10\% \to 50\% \to 100\%$.
- **Rollback Action**: If error spikes occur, flip the API Gateway rule back to $0\%$ traffic to the microservice.Zero downtime, zero impact.
- **Decommission**: Once $100\%$ traffic runs on the microservice for a burn-in period (e.g., 2 weeks),remove the payment code path and database tables from the monolith.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Edge Cases, Data Coupling & System Failure Modes:

#### 1. Handling Monolithic Cross-Database JOINs:

When extracting a service, you will inevitably break monolithic SQL queries that JOIN tables across domain boundaries:

```SQL
-- MONOLITHIC JOIN (Broken when Payment DB is extracted!)
SELECT o.id, o.total, p.status, u.email
FROM orders o
JOIN payments p ON o.id = p.order_id
JOIN users u ON o.user_id = u.id;
```

- **Architectural Fix A (API Composation at Gateway / Aggregator)**: The API Gateway or a dedicated Composite Service calls Order Service, Payment Service, and User Service via parallel HTTP/gRPC calls and merges the JSON payloads in memory.

- **Architectural Fix B (CQRS / Read Views)**: The extracted microservices publish domain events (OrderCreated, PaymentCompleted) to Kafka. A read-optimized View Service consumes these events and updates a denormalized read database (e.g., Elasticsearch or PostgreSQL view) specifically designed for fast query fetches.

#### 2. The Anti-Corruption Layer (ACL) Pattern:

Legacy monoliths often contain messy, non-standard domain models developed over years. If your new microservice directly adopts these legacy terms, its domain model becomes corrupted from day one.

```
[ Legacy Monolith ] ◄──► [ Anti-Corruption Layer (ACL) ] ◄──► [ New Domain Microservice ]
(e.g., `tbl_usr_pAY_v2`)   - Translates DTOs              (Clean Domain Model: `Payment`)
                          - Maps Data Enums
                          - Handles Legacy Auth Keys
```

- **Implementation**: The ACL sits as a translation interface inside the new microservice or as a sidecar proxy, converting legacy payloads into clean, domain-driven REST/gRPC objects before hitting the microservice logic.

#### 3. Managing "Dual Writes" and Transactional Outbox:

If the system must write to both the Monolith and the new Microservice during the transition period without CDC, naive double-writing leads to data drift when write 2 fails after write 1 succeeds.

- **Mitigation (Transactional Outbox Pattern)**: Write the business state change and an outbox event into the same local database transaction. A background worker reads the outbox table and publishes events to Kafka, guaranteeing At-Least-Once event delivery without distributed 2PC lock overhead.

---

### 5. Text-Based Architecture Diagram:

**End-to-End Strangler Fig Migration Evolution**

```
===================================================================================
STAGE 1: INITIAL STATE (Pure Monolithic Architecture)
===================================================================================

 [ Users / Clients ] ──► [ Monolith (All Domains) ] ──► [ Single Shared RDBMS ]

===================================================================================
STAGE 2: STRANGLER IN FLIGHT (Intermediate Coexistence State)
===================================================================================

 [ Users / Clients ]
          │
          ▼
 +-------------------------------------------------------------------------------+
 | API GATEWAY / CANARY ROUTER                                                   |
 +-------------------------------------------------------------------------------+
        │                                                       │
        │ (90% Legacy Traffic)                                  │ (10% Canary Traffic)
        ▼                                                       ▼
 +---------------------------+       Anti-Corruption    +------------------------+
 | MONOLITH                  | ◄───── Layer (ACL) ────► | Extracted Service      |
 | (Orders, Users, Shipping) |                          | (Payment Microservice) |
 +---------------------------+                          +------------------------+
        │                                                       │
        ▼                                                       ▼
 [ Monolith Database ] ──(CDC Engine: Debezium/Kafka)──► [ Payment Database ]

===================================================================================
STAGE 3: FINAL TARGET STATE (Monolith Fully Strangled)
===================================================================================

 [ Users / Clients ] ──► [ API Gateway ]
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
 [ User Service ]    [ Order Service ]    [ Payment Service ]
        │                     │                     │
        ▼                     ▼                     ▼
 [ User DB ]          [ Order DB ]          [ Payment DB ]
```

---

### 6. Interview Checklist:

When discussing Microservices Migration during system design interviews:

- **Reject "Big Bang" Rewrites Immediately**: Start by stating that production systems should always be migrated incrementally using the Strangler Fig Pattern to minimize operational risk and preserve business continuity.

#### Explain the Step-by-Step Lifecycle: Walk through the 4 core phases:

- API Gateway traffic interception.

- Bounded Context domain identification.

- Change Data Capture (CDC) database synchronization.

- Canary traffic routing and ultimate monolith code decommissioning.

#### Proactively Address the Database Splitting Problem: Demonstrate senior architectural insight by explaining how to split a shared database without downtime:

- Using CDC (Debezium + Kafka) instead of dual-writes.

- Resolving broken SQL joins using API Aggregation or CQRS Denormalized Read Views.

- **Detail the Anti-Corruption Layer (ACL)**: Highlight using an ACL to isolate the new microservice's domain model from legacy technical debt and schema flaws.

- **Pick the Right First Domain to Extract**: Recommend starting with low-risk, loosely coupled edge services (e.g., Notification Service, Image Transcoder) rather than the complex, highly coupled transactional core (e.g., Ledger / Billing Engine) to establish migration tooling and team confidence first.
