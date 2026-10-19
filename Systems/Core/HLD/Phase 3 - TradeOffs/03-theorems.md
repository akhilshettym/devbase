## CAP Theorem & PACELC Theorem

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine two remote bank branches—one in New York and one in London—connected by a single undersea trans-Atlantic communications cable:

- **CAP Theorem (The Crisis Scenario)**: A storm cuts the undersea cable (Network Partition). A customer walks into the New York branch and deposits $\$500$. New York cannot communicate with London. New York must choose:

- **Option A (Consistency - CP)**: Refuse the deposit and turn the customer away because London cannot be updated simultaneously. The system remains strictly accurate, but unavailable.

- **Option B (Availability - AP)**: Accept the deposit and update New York’s local balance immediately. The system stays available, but London holds a stale balance ($inconsistent$).

- **PACELC Theorem (The Everyday Scenario)**: The cable is working perfectly ($99.9\%$ of the time). Now the customer deposits $\$500$ in New York. New York must choose how to operate normally:

- **Option A (Consistency - C)**: Force the New York teller to hold the customer at the window until London replies back over the network confirming it updated its copy ($Higher\ Latency$).

- **Option B (Latency - L)**: Accept the deposit instantly in New York, reply to the customer in sub-milliseconds, and send an asynchronous background message to London ($Low\ Latency$, brief inconsistency window).

#### The Core Problem Solved:

- Early distributed database marketing claimed systems could achieve high availability, real-time consistency, and global scale simultaneously.

- The CAP Theorem (formulated by Eric Brewer) mathematically proved that across an untrusted physical network, a system cannot simultaneously provide strong consistency and high availability during a network partition.

- The PACELC Theorem (formulated by Daniel Abadi) extended CAP by proving that even when the network operates normally with zero partitions, systems must still trade off Latency against Consistency. Together, they form the foundational framework for evaluating every distributed storage engine.

---

### 2. The Basics (Scratch Level):

#### CAP Theorem Definitions:

$$\mathbf{C} + \mathbf{A} + \mathbf{P} \implies \text{Pick Any Two? } \mathbf{NO.} \text{ You MUST Pick } \mathbf{P!}$$

In any real-world distributed system built on physical networks, Partition Tolerance ($\mathbf{P}$) is non-negotiable. Network cables get cut, switches drop packets, and hypervisors pause VMs. Therefore, CAP is really a choice between $\mathbf{CP}$ and $\mathbf{AP}$ when a partition occurs:

- **Consistency ($\mathbf{C}$ - Linearizability)**: Every read receives the most recent write or an error. All nodes see the exact same state at the exact same physical instant.
- **Availability ($\mathbf{A}$)**: Every non-failing node returns a non-error response for every request—without guaranteeing that it contains the most recent write.
- **Partition Tolerance ($\mathbf{P}$)**: The system continues to operate despite an arbitrary number of dropped or delayed messages between nodes.

#### PACELC Theorem Breakdown:

PACELC unifies failure behavior (CAP) and normal behavior into a single formula:

$$\text{If } \mathbf{P} \text{ (Partition) } \longrightarrow \text{Choose } \mathbf{A} \text{ or } \mathbf{C} \quad \mathbf{E} \text{lse } \longrightarrow \text{Choose } \mathbf{L} \text{ or } \mathbf{C}$$

```
                              ┌───────────────────────────┐
                              │   DISTRIBUTED DATABASE    │
                              └─────────────┬─────────────┘
                                            │
                      Is there a Network Partition? (P)
                               /             \
                             YES             NO (Else: E)
                             /                 \
           Trade-off Forced:                 Trade-off Forced:
      ┌───────────┴───────────┐           ┌───────────┴───────────┐
      ▼                       ▼           ▼                       ▼
Availability (A)      Consistency (C)  Latency (L)         Consistency (C)
 [AP System]             [CP System]   [Low Latency]      [Strong Sync]
```

---

### 3. Deep Dive & Architecture (Mid Level):

#### System Classification Matrix:

| System                     | `CAP Class` | `PACELC Class`     | `Trade-off Char`                                                                                                                                | `Primary Examples`                           |
| -------------------------- | ----------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| **Spanner / CockroachDB**  | CP          | PC / EC            | Preserves strong linearizability under partitions AND during normal operations. Higher commit latency ($2\text{PC} + \text{Consensus}$).        | Google Spanner, CockroachDB, YugabyteDB      |
| **MongoDB (Majority)**     | CP          | PC / EC            | Primary steps down if it loses network quorum. High consistency during normal operation when using w: majority.                                 | MongoDB, HBase                               |
| **Cassandra / DynamoDB**   | AP          | PA / EL            | High availability during partitions. Under normal operation, responds in sub-milliseconds by replicating asynchronously.                        | Apache Cassandra, Amazon DynamoDB, Couchbase |
| **PostgreSQL (Async Rep)** | CP/APs      | PA / EC or PC / EL | Depends on failover config. Standard async replication offers low normal write latency at the expense of potential lost writes during failover. | PostgreSQL, MySQL InnoDB Replica Clusters    |

#### Mechanics During Network Partitions:

Consider a 5-node cluster split into two isolated networks by a switch failure:

```
MAJORITY PARTITION (3 Nodes: A, B, C)       MINORITY PARTITION (2 Nodes: D, E)
┌───────────────────────────────────┐ ┌───────────────────────────────────┐
│ [ Node A ] [ Node B ] [ Node C ]  │ │ [ Node D ] [ Node E ]             │
└───────────────────────────────────┘ └───────────────────────────────────┘
(Quorum Maintained: 3/5)                 (Quorum Lost: 2/5)
```

#### CP System Behavior:

- **Majority Partition (Nodes A, B, C)**: Retains quorum ($3/5 > 50\%$). Continues processing reads and writes normally.
- **Minority Partition (Nodes D, E)**: Detects lack of quorum. Rejects all write operations (and linearizable reads) to prevent split-brain data corruption. Availability is sacrificed to guarantee Consistency.

#### AP System Behavior:

- **Majority Partition (Nodes A, B, C)**: Accepts writes.
- **Minority Partition (Nodes D, E)**: Continues accepting writes! When the network heals, the system must resolve divergent data branches using Conflict-Free Replicated Data Types (CRDTs), Last-Write-Wins (LWW), or Vector Clocks. Consistency is sacrificed to guarantee Availability.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Tunable Consistency: Bridging the Gap:

Modern distributed stores (e.g., Apache Cassandra) do not strictly lock applications into fixed $AP$ or $CP$behavior. Instead, they expose Tunable Quorum Consistency at the query level:

$$N = \text{Replication Factor}, \quad W = \text{Write Quorum}, \quad R = \text{Read Quorum}$$
Strong Consistency (Linearizable / CP Mode):

#### $$W + R > N$$

- **Example**: $N=3, W=2, R=2$. Because $2 + 2 = 4 > 3$, the read set and write set are guaranteed to overlap on at least one node containing the latest timestamped write.

#### High Availability / Low Latency (AP / PA/EL Mode):

#### $$W + R \le N$$

- **Example**: $N=3, W=1, R=1$. Writes return as soon as a single local node accepts them ($W=1$). Reads return from the fastest responding replica ($R=1$). Latency is minimal, but stale reads are possible.

```
QUORUM OVERLAP GUARANTEE (W + R > N)
Replication Factor N = 3

Write Nodes (W = 2):  [ Node 1 ]  [ Node 2 ]  [        ]
Read Nodes  (R = 2):  [        ]  [ Node 2 ]  [ Node 3 ]
                                     ▲
                       Overlapping Node (Node 2)
                    Guarantees Fresh Data Return!
```

#### Brewer's Modern Re-evaluation ("CAP 12 Years Later"):

In 2012, Eric Brewer published a clarification on CAP to address widespread industry misunderstandings:

- **Partitions Are Rare & Localized**: Systems are not permanently "Partitioned" or "Non-Partitioned." A network partition is a temporary state.
- **Availability is a Continuum**: Systems rarely experience $0\%$ or $100\%$ availability. Availability is measured in decimal SLAs (e.g., $99.999\%$).
- **Fine-Grained Trade-offs**: A single database can process some transactions with $CP$ guarantees (e.g., monetary balance transfers) while processing others with $AP$ guarantees (e.g., social feed likes) within the exact same architecture.

---

5. Text-Based Architecture Diagram

```
================================================================================
                   CAP & PACELC DECISION MATRIX IN ACTION
================================================================================

SCENARIO 1: NETWORK PARTITION DETECTED (CAP RULE ENFORCED)
--------------------------------------------------------------------------------
Client Write Request -> [ Target Node ]
                            │
           Is Target Node in Majority Partition?
                            ├── YES ──► Write Executed Successfully
                            │
                            └── NO ───► Is System CP or AP?
                                          ├── CP ──► REJECT WRITE (Return Error)
                                          └── AP ──► ACCEPT WRITE (Saves Local)


SCENARIO 2: NORMAL OPERATION / NO PARTITION (PACELC RULE ENFORCED)
--------------------------------------------------------------------------------
Client Write Request -> [ Primary Node ]
                            │
            Does System Prioritize Latency or Consistency?
                            │
    ┌───────────────────────┴───────────────────────┐
    ▼                                               ▼
[ PA / EL Strategy ]                        [ PC / EC Strategy ]
1. Write to local memory.                   1. Block client thread.
2. Return '200 OK' immediately (<1ms).       2. Synchronously replicate to Quorum.
3. Asynchronously sync to replicas.         3. Return '200 OK' after ACKs (>25ms).
================================================================================
```

---

### 6. Interview Checklist:

- **Bust the "Pick Two" Myth**: Immediately clarify that you cannot "choose" Consistency and Availability while ignoring Partition Tolerance ($CA$ is impossible on distributed physical networks). Explain that CAP really means: When a partition occurs, do you choose $CP$ or $AP$?

- **State PACELC to Demonstrate Depth**: Stand out by introducing PACELC. Explain that CAP only addresses network partition failures ($<0.1\%$ of system lifetime), whereas PACELC explains the latency vs. consistency trade-off during normal operating conditions ($>99.9\%$ of system lifetime).

- **Explain Quorum Math ($W + R > N$)**: Show how tunable databases like Cassandra adjust consistency dynamically by altering Read ($R$) and Write ($W$) replication quorums relative to total replicas ($N$).

#### Categorize Real-World Systems Accurately:

- **Google Spanner / CockroachDB**: $CP$ and $PC/EC$ (uses Paxos/Raft + TrueTime/HLC).

- **Cassandra / DynamoDB**: $AP$ and $PA/EL$ (uses Gossip, Eventual Consistency, Anti-Entropy).

- **MongoDB**: $CP$ and $PC/EC$ (primary-driven quorum step-down).
