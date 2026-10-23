## Consistency vs Availability

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a hotel chain with two reservation desks (Desk A and Desk B) in different cities.

- **Consistency-First (CP)**: When a guest attempts to book the last available penthouse room at Desk A,Desk A pauses the customer while calling Desk B over the telephone to lock the room. If the telephone network line breaks (a network partition), Desk A refuses to take any new bookings for the penthouse to prevent double-booking. The system prioritizes accuracy over taking orders.

- **Availability-First (AP)**: If the telephone line breaks, Desk A keeps taking room bookings anyway. Desk A promises the room to the guest immediately. If Desk B simultaneously books the exact same room to another guest, the system accepts the risk of conflict, planning to resolve the double-booking later (e.g.,offering a free upgrade or voucher). The system prioritizes accepting requests over immediate accuracy.

#### The Problem It Solves:

In a distributed database spanning multiple physical servers or cloud availability zones, physical network partitions (fiber cuts, router crashes, transient latency spikes) are statistically guaranteed to occur.

When nodes cannot talk to each other, engineers face a fundamental architectural choice:

- Consistency guarantees that every read operation receives the most recent write or returns an error.
- Availability guarantees that every non-failing node returns a non-error response, without guaranteeing that it contains the most recent write.

---

### 2. The Basics (Scratch Level):

#### The CAP Theorem (Brewer's Theorem):

The CAP Theorem states that any distributed data store can simultaneously provide at most two of the following three guarantees:

- **Consistency ($C$)**: Equivalent to Linearizability. Every read operation returns the result of the most recent write, regardless of which node executes the read.
- **Availability ($A$)**: Every non-failing node returns a non-error response for every request (though the data may be stale).
- **Partition Tolerance ($P$)**: The system continues to operate despite arbitrary message loss or network communication failure between nodes.

```
            THE CAP THEOREM CHOICE
                     / \
                    /   \
                   /  C  \
                  /       \
                 /         \
                /  CP   CA  \  <-- (CA is impossible in distributed systems;
               /             \      Network Partitions cannot be opted out of!)
              /               \
             /                 \
            /  AP            P  \
           /_____________________\
```

- **Crucial Reality Check**: You cannot choose "CA". Physical networks will inevitably partition ($P$). Therefore, CAP is not a 3-way choice; it is a binary trade-off during a network partition: Choose CP or Choose AP.

#### The Spectrum of Consistency Models:

Consistency is not a binary switch; it lies on a spectrum of strictness:

| Model                     | `Classification` | `Description`                                                                                                                                          | `Typical Use Case`                                       |
| ------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| **Linearizable / Strict** | Strong (CP)      | Global real-time ordering. Reads reflect the exact latest state instantaneously across all nodes.                                                      | Financial ledgers, stock trading, inventory reservation. |
| **Sequential**            | Strong (CP)      | Program order is preserved per process, and all processes see operations in the same execution order.                                                  | Multi-threaded execution state syncing.                  |
| **Causal**                | Weak / Tunable   | Operations that are causally related must be seen in the same order by every node. Unrelated operations can be seen out of order.                      | Social media comments and thread replies.                |
| **Read-Your-Writes**      | Weak / Tunable   | A client will always see updates it submitted itself, even if other clients see stale state briefly.                                                   | User profile updates, user setting changes.              |
| **Eventual**              | Weak (AP)        | If no new updates occur, all replicas will eventually converge to identical state. Reads may return stale data indefinitely during network partitions. | DNS, video view counters, shopping cart additions.       |

#### ACID vs. BASE Paradigm:

- **ACID (Atomicity, Consistency, Isolation, Durability)**: The classical relational database paradigm (e.g.,PostgreSQL). Prefers CP—sacrifices availability during partitions to preserve strict invariants.
- **BASE (Basically Available, Soft state, Eventual consistency)**: The distributed NoSQL database paradigm (e.g., Apache Cassandra, DynamoDB). Prefers AP—sacrifices immediate consistency to guarantee high-throughput write and read availability.

---

### 3. Deep Dive & Architecture (Mid Level):

- `CAP in Action`: **What Happens During a Partition**
  Consider a two-node cluster ($\text{Node}_1$ and $\text{Node}_2$) storing a variable $X=0$.

```
PARTITIONED CLUSTER MECHANICS
[ Client A ] ───1. Write X=5 ───► [ Node 1 ] (X=5)
                                     x
                                     x NETWORK PARTITION (Broken Link)
                                     x
[ Client B ] ◄──2. Read X? ────── [ Node 2 ] (X=0)
Client A executes Write(X = 5) on $\text{Node}_1$.
```

- A network partition occurs. $\text{Node}_1$ attempts to replicate $X=5$ to $\text{Node}_2$, but the network packet is dropped.
- Client B executes Read(X) on $\text{Node}_2$.

#### CP Choice (Prioritizing Consistency):

$\text{Node}_2$ recognizes that it cannot verify if updates occurred on $\text{Node}_1$ due to the network partition. To prevent returning stale data ($X=0$), $\text{Node}_2$ rejects the read request or times out.

- Result: Consistency is preserved ($X=5$ or Error). Availability is violated.

#### AP Choice (Prioritizing Availability):

$\text{Node}_2$ responds immediately with its local, un-replicated state ($X=0$).

- Result: Availability is preserved (HTTP 200 OK returned). Consistency is violated ($X=0$ returned instead of $X=5$).

#### Beyond CAP: The PACELC Theorem:

The CAP theorem only describes system behavior during a network partition ($P$). What happens during the 99.99% of time when the network is functioning normally?

Abadi's PACELC Theorem extends CAP to model normal execution:

$$\text{If } \mathbf{P} \text{ (Partition), choose between } \mathbf{A} \text{ (Availability) vs. } \mathbf{C} \text{ (Consistency);}$$
$$\text{Else } (\mathbf{E}), \text{ choose between } \mathbf{L} \text{ (Latency) vs. } \mathbf{C} \text{ (Consistency).}$$

```
                         PACELC THEOREM
                                │
           ┌────────────────────┴────────────────────┐
           ▼                                         ▼
  IF PARTITION (P)?                         ELSE (E) NORMAL?
     ┌─────┴─────┐                             ┌─────┴─────┐
     ▼           ▼                             ▼           ▼
 Choose A     Choose C                     Choose L     Choose C
(Available) (Consistent)                   (Latency)   (Consistent)
```

#### Systems Classification under PACELC:

- **PC/EC (e.g., Google Spanner, CockroachDB, HBase)**: During partitions, chooses Consistency. Under normal operations, chooses Consistency over Latency (executes multi-phase consensus rounds before acknowledging writes).
- **PA/EL (e.g., Apache Cassandra, DynamoDB)**: During partitions, chooses Availability. Under normal operations, chooses Latency over Consistency (writes return immediately to local nodes without waiting for global replication).

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Tunable Consistency via Quorum Mathematics (Dynamo Model)

Databases inspired by Amazon’s Dynamo paper (e.g., Apache Cassandra) do not hardcode CP or AP behavior. They allow developers to tune consistency on a per-query basis using Quorum Mathematics:

- `$N$` = Replication Factor (total number of nodes storing a copy of the data).
- `$W$` = Write Quorum (number of replica nodes that must acknowledge a write before success).
- `$R$` = Read Quorum (number of replica nodes that must respond to a read before success).

#### 1. Strong Consistency Formula ($W + R > N$):

To achieve linearizable/strong consistency, the read set and write set must overlap by at least one node containing the latest version (by the Pigeonhole Principle).

```
$$W + R > N$$
STRONG CONSISTENCY QUORUM OVERLAP (N=3, W=2, R=2) -> W + R = 4 > 3

Write Set (W=2): [ Node 1 (v2) ] [ Node 2 (v2) ] [ Node 3 (v1) ]
Read Set  (R=2):                 [ Node 2 (v2) ] [ Node 3 (v1) ]
                                       ▲
                                       │ OVERLAP NODE: Holds latest v2!
```

Example: $N=3, W=2, R=2$. $2 + 2 = 4 > 3$. A read operation is guaranteed to fetch at least one node that acknowledged the latest write.

#### 2. High Availability / Low Latency Formula ($W + R \le N$):

If maximum availability and minimum write/read latency are required:
$$W + R \le N$$

- `Example`: $N=3, W=1, R=1$. $1 + 1 = 2 \le 3$. Writes and reads execute in milliseconds against local nodes, but reads may hit nodes that missed recent writes, returning stale data (AP behavior).

#### Data Conflict Resolution Strategies in AP Systems:

When an AP system allows concurrent writes to different nodes during a network partition, data diverges. Once the partition heals, the system must resolve the conflicting versions:

#### 1. Last-Write-Wins (LWW):

Assigns a physical microsecond timestamp to every write operation. The version with the latest timestamp overwrites older versions.

- **Failure Mode**: Physical server clocks drift due to NTP flaws. A node with a fast clock can permanently overwrite valid user updates made on other nodes ("Clock Drift Data Loss").

#### 2. Vector Clocks / Version Vectors:

Captures logical causality by tracking logical sequence numbers per node:

$$\text{Vector Clock} = \{\text{Node}_1: v_1, \text{Node}_2: v_2, \dots\}$$
If two version vectors are concurrent (neither dominates all counters), the system detects a write conflict and passes the raw conflicting branches down to the client application for manual resolution (e.g., Amazon’s original cart strategy: "Merge items from both carts").

#### 3. Conflict-Free Replicated Data Types (CRDTs):

Specialized mathematical data structures (e.g., PN-Counters, LWW-Element-Set) whose state transitions form a semi-lattice. Concurrently modified states merge deterministically using associative, commutative, and idempotent functions without requiring coordination nodes.

```
COMMUTATIVE MERGE IN CRDTs
State A (Node 1) ──┐
                   ├──► Merge Function f(A, B) = f(B, A) ──► Converged Identical State
State B (Node 2) ──┘
```

`Eliminating Distributed Transactions`: **Saga Pattern vs. 2PC**
Achieving strong consistency across multiple microservices using Two-Phase Commit (2PC) creates a severe availability bottleneck: if a single participant node or coordinator hangs during the prepare phase, all database locks remain held globally, blocking system execution (CP lock-in).

- The AP Alternative: Saga Pattern Executes a distributed business workflow as a chain of local, independent transactions.
- Each local transaction updates a service's local database and publishes an event/message.
- If a downstream step fails (e.g., payment fails after inventory reservation), the Saga orchestrator/bus fires explicit Compensating Transactions backwards to undo previous steps asynchronously.

---

### 5. Text-Based Architecture Diagram:

**Side-by-Side Architectural Dataflow (CP vs. AP System Execution)**

```
===================================================================================================
1. CP ARCHITECTURE (Strong Consistency / Consensus-Based: Raft / Paxos / Spanner)
===================================================================================================
[ Client Write ] ──► [ Leader Node ]
                         │
                         ├── 1. Proposes Write Entry to Followers
                         │
                         v
        ┌────────────────┴────────────────┐
        │ (Network Partition)             │
        x                                 v
 [ Follower Node A ]             [ Follower Node B ]
 (Network Unreachable)           (Acknowledges Write)
        │                                 │
        │ Failed Quorum Check             │
        └────────────────┬────────────────┘
                         │
                         v
                 [ Quorum Majority NOT Reached ]
                         │
                         v
                 [ Leader Rejects Write: HTTP 500 / Timeout ]
                 (Preserves Consistency by sacrificing Availability)

===================================================================================================
2. AP ARCHITECTURE (High Availability / Quorum Tuned: Cassandra / DynamoDB)
===================================================================================================
[ Client Write ] ──► [ Coordinator Node ]
                         │
                         ├── 1. Writes to Local Disk / Hinted Handoff
                         ├── 2. Asynchronous Replication Request
                         v
        ┌────────────────┴────────────────┐
        │ (Network Partition)             │
        x                                 v
 [ Replica Node A ]              [ Replica Node B ]
 (Network Unreachable)           (Acknowledges Write)
                                          │
                                          v
                                 [ Write Quorum W=1 Met ]
                                          │
                                          v
                                 [ Coordinator Returns HTTP 200 OK ]
                                 (Preserves Availability by sacrificing immediate Consistency)
                                          │
                                 ... Partition Heals Later ...
                                          │
                                 [ Background Anti-Entropy / Read Repair Syncs Replica A ]
```

---

### 6. Interview Checklist:

When pitching Consistency vs. Availability in a system design interview:

- **Frame the CAP Choice Correctly**: Never say "I choose CAP." State clearly that network partitions ($P$) are mandatory physical facts, so the decision is purely CP vs. AP during a partition.

- **Use the PACELC Framework for Normal Execution**: Demonstrate senior expertise by explaining PACELC: "During partitions I choose CP or AP, but during normal operations I trade off Latency vs. Consistency (PC/EC vs. PA/EL)."

- **Apply Quorum Math for NoSQL**: Explicitly state the formula $W + R > N$ to demonstrate how to configure strong consistency on eventually consistent stores like Cassandra or DynamoDB.

#### Match Business Domain to Consistency Needs:

- Recommend CP (Linearizable) for core financial ledgers, inventory reservation, authorization, and transactional state.

- Recommend AP (Eventual) for user feeds, analytics counters, messaging, recommendations, and shopping carts.

- **Proactively Solve AP Conflicts**: If you recommend an AP system, immediately explain how you will resolve data divergence (e.g., CRDTs, Vector Clocks, or Sagas with Compensating Transactions).
