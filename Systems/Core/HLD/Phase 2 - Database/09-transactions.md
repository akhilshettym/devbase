## Distributed Transactions (2-Phase Commit, Saga Pattern)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine booking an all-inclusive vacation package across three separate companies: a flight with an airline, a room with a hotel, and a car with a rental agency.

- **Two-Phase Commit / 2PC (Synchronous Multi-Agent Locking)**: You call the airline, hotel, and rental car agency simultaneously on a 3-way call. You ask all three to place a temporary hold on your tickets and lock the inventory. All three agents stay on the phone holding their breath. Once everyone replies "Yes, locked!", you instruct all three to charge your card simultaneously. If any single agency says "No availability," everyone releases their hold. Nobody else can book those resources while you are on hold. It guarantees absolute consistency, but if your phone line drops mid-call, all three agents remain blocked, holding locks indefinitely.

- **Saga Pattern (Asynchronous Multi-Step Execution with Rollbacks)**: You book the flight first on an app. Once the flight is confirmed, an automated workflow moves to step two and books the hotel. If the hotel booking fails (e.g., hotel sold out), the system triggers a compensating transaction: it automatically cancels the flight and issues a full refund. You don't lock all systems simultaneously; instead, you execute sequential local transactions and clean up backwards if a step fails. It trades immediate isolation for high speed and system availability.

#### The Core Problem Solved:

- When transitioning from a monolithic database to distributed microservices or sharded databases, you lose single-node database ACID transactions (BEGIN TRANSACTION ... COMMIT). A single business action (e.g., "Checkout Shopping Cart") now spans multiple independent databases across network boundaries.

- Distributed transaction patterns solve the challenge of maintaining system-wide data integrity across independent storage engines without leaving services in partial, corrupted, or zombie states during system crashes, network partitions, or business logic failures.

---

### 2. The Basics (Scratch Level):

#### Structural Comparison Matrix:

| Dimension               | `Two-Phase Commit (2PC)`                                   | `Saga Pattern`                                                |
| ----------------------- | ---------------------------------------------------------- | ------------------------------------------------------------- |
| **Transaction Model**   | Distributed ACID (Strong Consistency)                      | Distributed BASE (Eventual Consistency)                       |
| **Execution Mechanics** | Synchronous, Blocking, Distributed Locks                   | Asynchronous, Non-Blocking, Local Transactions                |
| **Isolation Level**     | High (Holds database locks across nodes until commit)      | None (ACD: Atomicity, Consistency, Durability — No Isolation) |
| **System Coupling**     | Tight Coupling (All systems must be online simultaneously) | Loose Coupling (Event-driven / Asynchronous message streams)  |
| **Performance Profile** | Low Throughput, High Latency, Tail Latency Spikes          | High Throughput, Low Latency, Scalable                        |
| **Failure Handling**    | Synchronous Abort & Global Lock Release                    | Asynchronous Compensating Transactions ($C_i$)                |
| **Best Tech Stack**     | Database Clusters, CockroachDB, Two-Phase XA Drivers       | Temporal, AWS Step Functions, Apache Kafka, RabbitMQ          |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Two-Phase Commit (2PC) Protocol Mechanics:

2PC relies on a centralized Transaction Coordinator managing multiple distributed Participant Nodes.

```
PHASE 1: PREPARE PHASE                         PHASE 2: COMMIT PHASE
======================                         ====================

[ Coordinator ]                                [ Coordinator ]
  │  │                                           │  │
  │  ├─────── 1. PREPARE? ───────► [ Node A ]    │  ├─────── 3. COMMIT! ────────► [ Node A ]
  │  └─────── 1. PREPARE? ───────► [ Node B ]    │  └─────── 3. COMMIT! ────────► [ Node B ]
  │                                              │
  ├─── 2. VOTE: YES / NO ────────◄ [ Node A ]    ├─── 4. ACK COMPLETE ──────────◄ [ Node A ]
  └─── 2. VOTE: YES / NO ────────◄ [ Node B ]    └─── 4. ACK COMPLETE ──────────◄ [ Node B ]
```

#### Phase 1: Prepare:

- The Coordinator logs a Prepare intent to its local log and sends a PREPARE request over the network to all Participant nodes.
- Each Participant executes the transaction locally up to the commit point: it writes updates to its local Write-Ahead Log (WAL), locks affected table rows, and returns a vote:

- **VOTE_COMMIT**: Ready to commit; local locks held.
- **VOTE_ABORT**: Failed to prepare (e.g., constraint failure or lock conflict).

#### Phase 2: Commit / Abort:

- **Global Commit**: If ALL Participants vote VOTE_COMMIT, the Coordinator writes a Commit record to its log and broadcasts COMMIT to all nodes. Participants apply local writes, release their locks, and send an ACK.
- **Global Abort**: If ANY Participant votes VOTE_ABORT (or times out), the Coordinator writes an Abortrecord and broadcasts ABORT. All Participants roll back local changes using WAL records and release locks.

#### The Fundamental Flaw of 2PC: Blocking Architecture:

If the Coordinator crashes after Participants vote VOTE_COMMIT in Phase 1, but before broadcasting COMMIT in Phase 2: Participants are left in an In-Doubt State. They must hold row locks indefinitely to prevent dirty reads.

Incoming transactions requesting those locked rows stall, causing cascading thread pool exhaustion across the entire cluster.

#### Saga Pattern Architectural Approaches:

A Saga decomposes a global transaction into a sequence of $n$ local transactions:

$$T_1, T_2, T_3, \dots, T_n$$

Every local transaction $T_i$ updates data inside a single service. If step $T_k$ fails ($1 \le k \le n$), the Saga engine invokes a reverse sequence of Compensating Transactions:

$$C_{k-1}, \dots, C_2, C_1$$

Compensating transactions $C_i$ explicitly undo the semantic changes executed by $T_i$ (e.g., executing a refund for a previous credit card charge).

```
SUCCESSFUL SAGA:      [ T1: Create Order ] ──► [ T2: Reserve Stock ] ──► [ T3: Charge Card ] (COMPLETE)

FAILED SAGA & ROLLBACK: [ T1: Create Order ] ──► [ T2: Reserve Stock ] ──► [ T3: Charge Card (FAILS!) ]
                            │                        │                         │
                            ▼                        ▼                         │
                    [ C1: Cancel Order ] ◄─── [ C2: Unreserve Stock ] ◄────────┘
```

- **Approach 1**: Choreography-Based Saga (Decentralized / Event-Driven)
  Services communicate asynchronously by emitting domain events over a message broker (e.g., Apache Kafka).

```
[ Order Service ] ──(OrderCreated Event)──► [ Kafka Topic ] ──► [ Inventory Service ]
       ▲                                                               │
       │                                                     (StockReserved Event)
       │                                                               ▼
[ Order Service ] ◄──(PaymentFailed Event)─── [ Kafka Topic ] ◄─── [ Payment Service ]
```

- **Pros**: Simple for small workflows; highly decoupled; no single point of coordination.
- **Cons**: Hard to reason about as workflow complexity grows; risks cyclical dependencies; tracking global system state requires complex distributed tracing.

- **Approach 2**: Orchestration-Based Saga (Centralized State Machine)
  A central Saga Orchestrator (e.g., Temporal, Camunda, AWS Step Functions) explicitly directs service calls and tracks execution state in a durable state machine.

```
                        [ Saga Orchestrator ]
                       (Durable State Machine)
                       /          │          \
      (1. Process Order)   (2. Reserve Stock) (3. Charge Card - FAILS!)
             │                    │                    │
             ▼                    ▼                    ▼
      [ Order Service ]   [ Inventory Service ]   [ Payment Service ]
             │                    │
             └─────────◄──────────┴─ (Triggers C2 & C1 Compensations)
```

- **Pros**: Clear business logic visibility; easy to monitor and audit; explicit error handling and retries.
- **Cons**: Requires managing dedicated orchestrator infrastructure; potential central point of coupling if business logic bleeds into orchestration scripts.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Isolation Anomalies in Sagas (The Lack of "I" in BASE):

Because Saga local transactions commit immediately to their respective databases, intermediate uncommitted states are visible to concurrent requests. This exposes Sagas to three classic concurrency anomalies:

- **Dirty Reads**: Service A executes $T_1$ (creates a pending order). Service B reads the order state and ships a package. Service C fails $T_3$, triggering $C_1$ (cancels order). Service B has acted on data that was subsequently rolled bak.
- **Lost Updates**: Service A reads balance $\$100$, adds $\$50$ ($T_1$). Concurrently, Service B reads balance $\$100$, adds $\$20$ ($T_2$). Service A's transaction completes, but a rollback on Service A overwrites the state, losing Service B's write.
- **Non-Repeatable Reads**: Service A reads a customer record in $T_1$. Service B updates the customer record in $T_2$ before Service A executes $T_3$.

##### Countermeasures for Saga Isolation Loss:

To achieve Semantic Isolation inside Sagas without distributed locks, software architects use design countermeasures:

- **Semantic Lock (Pessimistic Flag)**: Local transactions mark records as PENDING_APPROVAL or IN_PROGRESS. Foreign transactions reading the record know not to alter or act on it until the status flag shifts to APPROVED or CANCELLED.
- **Commutative Operations**: Design local updates so execution order does not affect the final state (e.g., $10 \text{ credit}$ then $5 \text{ debit}$ yields the same net state regardless of sequence), eliminating rollback conflicts.
- **Pessimistic View Reordering**: Reorder Saga steps to place high-risk, non-compensable actions (e.g., sending an irrevocable physical dispatch email) at the very end of the Saga chain.
- **Reread-Proof Structure (Value Checks)**: Before executing a mutating step $T_k$, re-read the primary record state to verify it hasn't been altered by a concurrent process, executing compensating logic if state drift is detected.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
         DISTRIBUTED TRANSACTIONS: 2PC vs SAGA ORCHESTRATION
================================================================================

1. TWO-PHASE COMMIT (2PC - Blocking Synchronous ACID)
--------------------------------------------------------------------------------
[ Client ] ──► [ Coordinator ] ────(1. PREPARE)───► [ Order DB (Locks Row) ]
                              ────(1. PREPARE)───► [ Payment DB (Locks Row) ]

              [ Coordinator ] ◄───(VOTE_COMMIT)─── [ Order DB ]
                              ◄───(VOTE_COMMIT)─── [ Payment DB ]

              [ Coordinator ] ────(2. COMMIT)────► [ Order DB (Unlocks) ]
                              ────(2. COMMIT)────► [ Payment DB (Unlocks) ]


2. SAGA ORCHESTRATION (Non-Blocking Asynchronous BASE)
--------------------------------------------------------------------------------
[ Client ] ──► [ Orchestrator ]
                    │
                    ├───► [ Order Service ] ──────► (T1: Create Order) [COMMITTED]
                    │
                    ├───► [ Payment Service ] ────► (T2: Charge Card) [COMMITTED]
                    │
                    └───► [ Inventory Service ] ──► (T3: Reserve Stock) [FAILS!]
                                │
                    ┌───────────┘
                    ▼
        [ Trigger Compensations ]
                    │
                    ├───► [ Payment Service ] ────► (C2: Refund Card) [COMMITTED]
                    │
                    └───► [ Order Service ] ──────► (C1: Cancel Order) [COMMITTED]
================================================================================
```

---

### 6. Interview Checklist:

- **Frame the Core Distinction Immediately**: Define 2PC as a synchronous, lock-holding distributed ACID protocol optimized for consistency, and Sagas as an asynchronous sequence of local BASE transactions with compensating actions optimized for availability and scale.

- **Explain the 2PC Blocking Flaw**: Highlight how a coordinator crash during Phase 2 leaves participant nodes holding locks in an "In-Doubt" state, causing thread pool starvation across dependent services.

- **Detail Saga Implementation Approaches**: Contrast Choreography (decentralized, event-driven via Kafka; great for simple workflows) with Orchestration (central state machine via Temporal/AWS Step Functions; great for complex business logic).

- **Address the Lack of Isolation in Sagas**: Senior candidates MUST call out that Sagas lack the "I" (Isolation) of ACID. Explain countermeasures like Semantic Locks (PENDING flags) and Pessimistic View Reordering to prevent dirty reads and lost updates.

#### Provide Concrete System Design Choices:

- **Choose 2PC for**: Distributed relational databases (e.g., CockroachDB, Spanner), financial ledger updates within a tight boundary, and low-latency internal database clusters.

- **Choose Saga for**: Microservices operating across network boundaries, long-running business processes, e-commerce checkout flows, and third-party API integrations (e.g., Stripe, FedEx API).
