## Data Consistency & its levels

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Think of data consistency levels like different ways of editing a shared document across a global company:

- **Linearizability (Strong Consistency - Real-Time Collaborative Doc)**: Imagine editing a Google Doc in real-time. The exact millisecond Author A types the letter "X" in New York, Author B in Tokyo sees "X" on their screen. No matter who looks at the document or from where, everyone sees the exact same state at the exact same physical instant.

- **Eventual Consistency (Mailing Printed Manuscripts)**: Imagine mailing physical paper drafts of a book to 10 global editors via international post. Some editors receive the draft on Tuesday, others on Friday. During the week, different editors are looking at different versions of the manuscript. However, once all mail arrives and no new edits are made, everyone eventually holds the identical final draft.

#### The Core Problem Solved:

- In a distributed database, data is replicated across multiple physical servers to ensure high availability and low latency. However, because information cannot travel faster than the speed of light, updating Node A takes time to propagate across the network to Node B.

- Data Consistency Levels define a formal contract between the database and the application. This contract dictates what value a read operation is guaranteed to return when concurrent writes and network replication delays occur. Choosing a consistency level is a deliberate trade-off between absolute data accuracy, system availability, and query latency.

---

### 2. The Basics (Scratch Level):

#### The Consistency Spectrum:

Data consistency is not a binary choice between "Strong" and "Weak." It exists on a continuous spectrum of guarantees:

```
STRONGEST GUARANTEES WEAKEST GUARANTEES
(High Latency / Low Availability) (Low Latency / High Availability)

┌───────────────┬────────────────┬──────────────┬───────────────────┬────────────────┐
│ Linearizable  │ Sequential     │ Causal       │ Client-Centric    │ Eventual       │
│ (Strict)      │ Consistency    │ Consistency  │ (Read-Your-Writes)│ Consistency    │
└───────────────┴────────────────┴──────────────┴───────────────────┴────────────────┘
```

#### Core Terminology:

- **Replication Lag ($\Delta t$)**: The time delay between a write committing on a primary node and that change being applied to a secondary replica node.

- **Stale Read**: A read operation that returns an outdated version of data because the target replica has not yet processed recent writes.

- **Global Clock / Wall Clock Time**: Physical time measured by real-world clocks (e.g., UTC). Hard to synchronize perfectly across distributed hardware.

- **Logical Clock**: An abstraction (e.g., Lamport Timestamps, Vector Clocks) that tracks the relative ordering of events based on cause and effect rather than physical time.

---

### 3. Deep Dive & Architecture (Mid Level):

#### Detailed Breakdown of Consistency Models:

#### 1. Linearizability (Strong Consistency / External Consistency):

- **Guarantee**: Real-world time ordering for individual objects. If a write operation $W$ completes at physical time $t_1$, any read operation $R$ that begins after $t_1$ (on any node in the system) must return value $W$ or a later value.
- **How it Works**: Gives the illusion that there is only a single copy of the data in the entire world, and all operations execute atomically.
- **Implementation**: Requires distributed consensus algorithms (Paxos, Raft) or hardware-synchronized physical clocks (Google Spanner's TrueTime API using atomic clocks and GPS receivers).

#### 2. Sequential Consistency:

- **Guarantee**: Operations execute in a single, global sequence agreed upon by all nodes, and operations from each individual process appear in that sequence in the order specified by its program.
- **Difference from Linearizability**: It removes the constraint of physical "wall clock" time. Operations can be reordered globally as long as no client sees its own operations run out of program order and all nodes see the same global execution sequence.

#### 3. Causal Consistency:

- **Guarantee**: Operations that are causally related must be seen by every node in the exact same order. Operations that are concurrent (unrelated) can be seen in different orders by different nodes.
- **Example**: If User A posts a question ($Op_1$) and User B posts an answer ($Op_2$), $Op_2$ depends causally on $Op_1$. Every node must show the question before the answer. However, if User C posts an unrelated comment about the weather ($Op_3$), $Op_3$ can appear before or after $Op_1$/$Op_2$ on different nodes.
- **Implementation**: Tracked using Vector Clocks or causal dependency graphs attached to write payloads.

#### 4. Client-Centric Consistency Models:

These models guarantee consistency for an individual client session, even if different clients see data in different orders:

- **Read-Your-Writes Consistency**: A client will always see its own previous writes. Example: If you update your profile picture and refresh the page, you are guaranteed to see the new picture, even if other users see the old picture for a few seconds.
- **Monotonic Reads**: If a client reads value $V_1$ at time $t_1$, that client will never subsequently read an older value $V_0$ at a later time $t_2$. (Prevents time-travel anomalies where refreshing a page alternately shows new and old comments).
- **Monotonic Writes**: Guarantees that a single client's writes are processed in the order they were submitted.

#### 5. Eventual Consistency:

- **Guarantee**: Weakest model. Offers no ordering or freshness guarantees during active reads and writes. It guarantees only that if no new updates are made to an item, all replicas will eventually converge to hold identical data.
- **Implementation**: Background anti-entropy mechanisms, Read Repair, or Gossip Protocols (e.g., Apache Cassandra, Amazon DynamoDB defaults).

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### The CAP & PACELC Trade-Off Matrix:

Consistency levels directly control how a distributed system behaves during network failures and normal operation:

- **CAP Theorem**: During a Network Partition (P), you must choose between Consistency (C - Linearizability) or Availability (A).

- **PACELC Theorem**:

$$\text{If } \mathbf{P} \text{ (Partition): Choose } \mathbf{A} \text{ or } \mathbf{C} \quad \mathbf{E} \text{lse: Choose } \mathbf{L} \text{ (Latency) or } \mathbf{C} \text{ (Consistency)}$$

```
                  PACELC CLASSIFICATION OF CONSISTENCY MODELS

┌───────────────────────────┬──────────────────────────────┬──────────────────────────────┐
│ Database System           │ PACELC Classification        │ Behavior During Normal State │
├───────────────────────────┼──────────────────────────────┼──────────────────────────────┤
│ Google Spanner / Cockroach│ PC / EC                      │ High Latency for Strong C    │
│ MongoDB (Default)         │ PC / EC                      │ Prioritizes Consistency      │
│ Apache Cassandra          │ PA / EL                      │ Low Latency / Eventual C     │
│ Amazon DynamoDB (Default) │ PA / EL                      │ Low Latency / Eventual C     │
└───────────────────────────┴──────────────────────────────┴──────────────────────────────┘
```

#### Implementing Client-Centric Consistency Over Eventual Stores:

- System architects frequently build Read-Your-Writes consistency on top of eventually consistent databases to balance speed with user experience:

- **Sticky Sessions (Session Affinity)**: Route all HTTP/gRPC requests from a specific User_ID to the exact same database primary or replica node for $N$ minutes following a write.
- **Timestamp / Monotonic Version Pins**: When Client A writes data, the database returns a version token (e.g., LSN: 10492). On subsequent reads, Client A sends LSN: 10492 in the request header. If the assigned replica node is behind LSN 10492, the query router either waits for the replica to catch up or redirects the read to the primary node.

---

### 5. Text-Based Architecture Diagram

```
                       CONSISTENCY SPECTRUM & REPLICATION DYNAMICS

    ================================================================================

1.  LINEARIZABLE CONSISTENCY (Synchronous / Consensus - Raft/Paxos)

---

[ Client A ] ───(Write X=5)───► [ Leader Node ] ───(Sync Replication)───► [ Follower 1 ]
│ [ Follower 2 ]
▼ (Wait for Consensus Quorum)
[ Client B ] ◄───(Read X -> 5)── [ Return Success ]

- Guarantee: Client B reads '5' immediately after Client A's write completes.

2. EVENTUAL CONSISTENCY (Asynchronous Replication - Background Convergence)

---

[ Client A ] ───(Write X=5)───► [ Primary Node ] ──(Return Success Immediately!)
│
▼ (Async Replication Lag Δt = 2.5s)
[ Client B ] ───(Read X -> 0)─► [ Replica 2 ] (Stale Read during Δt window!)
│
▼ (2.5s later: Replication Completes)
[ Client C ] ───(Read X -> 5)─► [ Replica 2 ] (Data Eventually Converged)
================================================================================

```

---

### 6. Interview Checklist:

- **Define Linearizability vs. Serializability**: Interviewers love testing this distinction. State clearly: Linearizability is a real-time ordering guarantee on a single object, whereas Serializability is a multi-operation, multi-object transaction isolation guarantee. (Combine both for External Consistency / Strict Serializability).

- **Use the PACELC Framework**: When discussing consistency trade-offs, move beyond the basic CAP theorem. Frame systems using PACELC to explain how choosing strong consistency increases normal-state read/write latencies ($\text{E} \to \text{C}$) even when no network partitions exist.

- **Propose Client-Centric Mitigations for User-Facing Apps**: Demonstrate senior architecture skills by explaining how to deliver a fast, eventually consistent backend while implementing Read-Your-Writes at the edge using sticky routing or version tokens to avoid user confusion.

#### Pair Business Domains to Consistency Levels:

- **Linearizable / Strong**: Account balance transfers, inventory checkout locks, seat reservations.

- **Causal / Read-Your-Writes**: Social media comment threads, user profile settings, direct messaging.

- **Eventual**: Video view counters, social media like counts, product review metrics, analytics logging.
