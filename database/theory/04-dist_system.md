## 4. Distributed Systems & Scaling:

- **Partitioning & Sharding**: Strategies for splitting large datasets horizontally across nodes using Hash, Range, or Directory-based sharding.

- **Replication & High Availability**: Primary-Replica (Master-Slave) versus Multi-Primary setups, dealing with replication lag, and handling failovers.

- **Distributed Guarantees**: Balancing trade-offs using the CAP and PACELC theorems, understanding eventual consistency, and how Two-Phase Commit (2PC) handles multi-node transactions.

---

Scaling a database beyond a single machine requires distributing data across network nodes. This introduces trade-offs between system latency, data consistency, write availability, and fault tolerance.

### 1. <u>Partitioning & Sharding Mechanics</u>:

When a dataset outgrows the disk capacity or IOPS of a single large machine, the database must be partitioned across multiple independent nodes (shards).

```
                               HORIZONTAL SHARDING
                                  [ Router / Proxy ]
                                   /        |        \

    Key Range [A-G] / | \ Key Range [P-Z]
    ▼ / | \ ▼
    [ SHARD 1 (Node A) ] <─────┘ Key Range [H-O] └─────> [ SHARD 3 (Node C) ]
    Users A - G ▼
    [ SHARD 2 (Node B) ]
    Users H - O
```

#### Partitioning Strategies:

##### 1. Range-Based Partitioning:

Data is divided into contiguous ranges based on a key (e.g., user_id 1–10000 on Shard 1, 10001–20000 on Shard 2).

- **Pros**: Supports efficient range scans (WHERE age BETWEEN 20 AND 30) on the shard key within a single node.
- **Cons**: Prone to hotspots. If data is partitioned by timestamp (created_at), all new writes target the same single shard holding the latest date range, saturating its write buffer while other shards remain idle.

##### 2. Hash-Based Partitioning:

A hash function is applied to the key: $\text{Shard ID} = \text{hash}(\text{key}) \pmod N$.

- **Pros**: Uniformly distributes writes across all available nodes, preventing hotspots.
- **Cons**: Range queries become expensive. Searching for ranges requires executing a Scatter-Gatherquery (sending requests to every shard and merging results at the application layer).

##### 3. Consistent Hashing & Virtual Nodes:

Naive hash partitioning ($\pmod N$) breaks down when adding or removing nodes: changing $N$ forces almost $100\%$ of keys to remap and move across the network.

Consistent Hashing maps both physical nodes and data keys to a conceptual circular ring (typically $[0, 2^{32}-1]$) using a uniform hash function.

```
                         CONSISTENT HASHING RING
                                0 / 2^32
                           [ Node A (V1) ]
                          /               \
             [ Key 1 ]   /                 \   [ Node B (V1) ]
                        |                   |
                        |     HASH RING     |  ◄── Key 2 (Hashes here,
                        |                   |      stored on Node B)
             [ Node B (V2) ]               /
                         \               /
                           [ Node A (V2) ]
```

- **Key Assignment**: A key is routed to the first node encountered when moving clockwise around the ring.
- **Adding/Removing Nodes**: When Node $N_{new}$ joins the ring, it only takes over a fraction of keys from its immediate neighbor. All other nodes retain their data.
- **Virtual Nodes (Tokens)**: To prevent uneven data distribution, each physical node is assigned dozens of "Virtual Nodes" (vnodes) scattered across the ring. This ensures data distributes evenly across heterogeneous hardware.

#### Selecting a Shard Key:

Choosing the wrong Shard Key is difficult to fix in production. A poor shard key causes two major failures:

- **Hotspotting**: A power user (e.g., a celebrity account) receives millions of interactions, overloading the single shard holding their user_id.
- **Cross-Shard Transactions & Joins**: Joining tables stored on different physical shards requires fetching remote datasets over the network, drastically inflating latency.

---

### 2. <u>Replication Topologies & High Availability</u>:

Replication copies data across multiple physical machines to ensure high availability (if Node A dies, Node B takes over) and read scalability (scaling read throughput across multiple replicas).

```
                         PRIMARY-REPLICA (ASYNC vs SYNC)

          [ Client ] ─── UPDATE ───► [ Primary Node ]
                                      │         │
                      (Sync Flush)    │         │ (Async Stream)
                      ┌───────────────┘         └───────────────┐
                      ▼                                         ▼
            [ Synchronous Replica ]                 [ Asynchronous Replica ]
            (Blocks write response)                 (Lag: 10ms - 5s)
```

#### Replication Modes:

##### 1. Synchronous Replication:

The Primary waits for the replica to write the change to its WAL and confirm receipt before returning success to the client.

- **Trade-off**: Zero data loss on primary failover; high write latency (bound by network roundtrip) and reduced write availability (if the replica goes down, writes block).

##### 2. Asynchronous Replication:

The Primary commits locally and immediately returns success to the client. Replication messages stream to replicas asynchronously in the background.

- **Trade-off**: Low write latency; risk of data loss if the primary crashes before log records replicate to replicas.

##### 3. Semi-Synchronous Replication:

The Primary waits for confirmation from at least one synchronous replica, while streaming to remaining replicas asynchronously.

#### Replication Anomalies & Client Guarantees:

Under asynchronous replication, reading from a replica can expose timing anomalies due to Replication Lag:

##### 1. Read-After-Write Consistency (Monotonic Read-Your-Own-Writes):

A user updates their profile picture, refreshes the page, and sees their old profile picture because the read hit an asynchronous replica that hasn't processed the update yet.

- **Mitigation Strategy**: Route reads for a user's own profile to the Primary node for $X$ seconds following a write, or track client transaction IDs (vector clocks / sequence numbers) and require replicas to wait until their log state catches up before serving the read.

##### 2. Monotonic Reads:

A user reads data from Replica 1 (up to date) and sees a comment. They refresh, hit Replica 2 (lagging behind), and the comment vanishes—making time appear to move backward.

- **Mitigation Strategy**: Ensure a user's session is pinned to the same replica (Sticky Sessions), or fetch reads strictly using monotonic transaction sequence numbers.

#### Leaderless Replication & Quorum Math (Dynamo-Style):

In leaderless systems (e.g., Cassandra, DynamoDB), any node can accept writes and reads. To maintain consistency without a single leader, systems use Quorum Consensus.

- $N$ = Replication Factor (Total nodes storing a copy of the data)
- $W$ = Write Quorum (Number of nodes that must acknowledge a write for it to succeed)
- $R$ = Read Quorum (Number of nodes that must respond to a read query)

```
                           QUORUM CONSENSUS (N=3, W=2, R=2)
```

- **Write (W=2)**: Acknowledged by Node 1 & Node 2.
- **Read (R=2)**: Reads from Node 2 & Node 3.
- **Overlap**: Node 2 is present in both sets, guaranteeing the read sees the latest version!

#### Strict Quorum Rule:

To guarantee that a read operation always encounters the latest written version:

$$W + R > N$$

If $W + R > N$, the set of nodes written to and the set of nodes read from are guaranteed to overlap by at least one node. The client uses version timestamps or Vector Clocks to resolve conflicts and return the latest version.

---

### 3. <u>Distributed Guarantees, CAP/PACELC & Distributed Transactions</u>:

#### CAP Theorem:

In a distributed data store experiencing a Network Partition ($P$), the system must choose between:

- **Consistency ($C$)**: Every read returns the most recent write or an error.
- **Availability ($A$)**: Every non-failing node returns a non-error response for every request (without guaranteeing it contains the most recent write).

#### System Design Reality:

Network partitions ($P$) are unavoidable in real-world infrastructure due to cable cuts, switch failures, or GC pauses. Therefore, a distributed database cannot "choose C and A". It must choose how to respond WHEN a partition occurs: CP (reject writes to preserve strict consistency) or AP(accept writes on both sides of the partition, allowing data divergence).

```
                           PACELC THEOREM
                        Is there a Partition (P)?
                               /        \
                             YES         NO
                             /            \
                      Choose (A) or (C)   Choose (L) or (C)
                      Availability vs     Latency vs
                      Consistency         Consistency
```

#### PACELC Theorem:

The CAP theorem only describes behavior during rare network failures. The PACELC Theorem extends CAP to describe everyday steady-state trade-offs:

$$\mathbf{I}\text{f }\mathbf{P}\text{artition, choose }\mathbf{A}\text{vailability or }\mathbf{C}\text{onsistency}; \quad \mathbf{E}\text{lse, choose }\mathbf{L}\text{atency or }\mathbf{C}\text{onsistency.}$$

- **MongoDB / HBase (PC/EC)**: Under partitions, sacrifice availability for consistency. In normal operations, wait for primary acknowledgments to maintain consistency over lower latency.
- **DynamoDB / Cassandra (PA/EL)**: Under partitions, remain available for writes. In normal operations, use asynchronous background replication to keep read/write latency low at the expense of immediate consistency.

#### Distributed Transactions: 2PC vs. Sagas:

Executing ACID transactions across multiple microservices or database shards requires specialized coordination protocols.

##### Two-Phase Commit (2PC):

A centralized Coordinator manages a multi-node transaction in two distinct network phases:

```
                 TWO-PHASE COMMIT (2PC) PROTOCOL

    [ Coordinator ]                       [ Participant Nodes ]
           │                                         │
           ├────── Phase 1: PREPARE ────────────────►│ (Lock resources, write to WAL)
           │◄───── "VOTE_COMMIT" / "ABORT" ──────────┤
           │                                         │
           ├────── Phase 2: GLOBAL COMMIT ──────────►│ (Commit changes, release locks)
           │◄───── "ACK" ────────────────────────────┤
```

- **Phase 1 (Prepare Phase)**: The coordinator sends a PREPARE command to all participating nodes. Each node executes the local transaction up to the point of committing, locks the target rows, writes to its local WAL, and votes VOTE_COMMIT or VOTE_ABORT.

- **Phase 2 (Commit Phase)**: If all nodes vote VOTE_COMMIT, the coordinator logs a commit decision to its log and sends GLOBAL_COMMIT to all nodes. If any node voted abort, it sends GLOBAL_ABORT.

**The Problem with 2PC**: It is a blocking protocol. If the coordinator crashes after nodes vote VOTE_COMMIT in Phase 1, participating nodes remain blocked, holding database row locks indefinitely until the coordinator recovers. This severely limits scale and throughput.

##### The Saga Pattern (Eventual Consistency for Microservices):

Instead of holding blocking locks across nodes, a Saga breaks a distributed transaction into a sequence of independent local transactions ($T_1, T_2, \dots, T_n$). Every local transaction updates a database and publishes an event to trigger the next local transaction.

If local transaction $T_3$ fails (e.g., payment declined), the Saga engine executes explicit Compensating Transactions ($C_2, C_1$) in reverse order to undo changes and restore data consistency.

```
                        SAGA PATTERN WITH COMPENSATION
```

Order Service Payment Service Inventory Service

```
(Tx 1: Create) ───► (Tx 2: Charge) ───► (Tx 3: Out of Stock! FAILS)
│
(Comp 1: Cancel) ◄── (Comp 2: Refund) ◄─────────────┘
```

- **Choreography**: Nodes listen to domain events over a message broker (e.g., Kafka) and independently trigger the next step or compensating action.
- **Orchestration**: A centralized Saga Orchestrator service tracks state and sends direct command messages to each participating service, executing compensating commands if a step fails.
