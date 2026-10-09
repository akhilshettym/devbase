## Sharding

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a fast-growing global bank opening physical locations:

- **Vertical Scaling (Building a Bigger Vault)**: You construct a single giant 100-story skyscraper bank headquarters downtown. Every customer in the world must travel to this single building to deposit or withdraw money. Eventually, the line wraps around the city, elevator traffic stalls, and the building runs out of floor space.

- **Sharding (Opening Independent Regional Branches)**: You open 50 independent regional bank branches across the country. Customers in California use Branch #1, customers in Texas use Branch #2, and customers in New York use Branch #3. Each branch has its own vault, tellers, and computing hardware. If overall customer volume triples, you simply open 100 more regional branches without modifying existing ones.

#### The Core Problem Solved:

- Single-node databases eventually hit hardware ceilings: physical RAM socket limits, storage controller I/O queue exhaustion, and CPU core lock contention under concurrent writes.

- Sharding is the practice of horizontally partitioning a database's rows across multiple independent physical server nodes (shards). Unlike standard single-node partitioning, each shard runs its own isolated database instance with dedicated hardware resources. Sharding enables near-linear scale-out capacity, allowing applications to process hundreds of thousands of write operations per second and store multi-terabyte or petabyte-scale datasets.

---

### 2. The Basics (Scratch Level):

#### Key Terminology & Architectural Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│                      DISTRIBUTED CLUSTER                        │
│                                                                 │
│  ┌───────────────────┐  ┌───────────────────┐  ┌─────────────┐  │
│  │  Shard Node 1     │  │  Shard Node 2     │  │ Shard Node N│  │
│  │ ┌───────────────┐ │  │ ┌───────────────┐ │  │ ┌─────────┐ │  │
│  │ │ Rows: A - G   │ │  │ │ Rows: H - N   │ │  │ │Rows: O-Z│ │  │
│  │ └───────────────┘ │  │ └───────────────┘ │  │ └─────────┘ │  │
│  │ (Independent DB)  │  │ (Independent DB)  │  │ (Indep. DB) │  │
│  └───────────────────┘  └───────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

- **Shard**: An individual physical server (or replica set) that holds a discrete subset of the total dataset.
- **Shard Key**: The column (or combination of columns) present in every write query that determines which physical shard stores that row.

#### Sharding vs. Partitioning vs. Federation:

- **Partitioning**: Splitting a table logically inside a single database instance.
- **Sharding**: Distributing table rows horizontally across multiple physical network nodes.
- **Federation**: Splitting a database by functional domain (e.g., placing Users on Database A and Products on Database B).

#### Sharding Strategies Matrix:

| Strategy                      | `Routing Mechanics`                                                                   | `Strengths`                                                                              | `Weaknesses`                                                                | `Best Use Cases`                                                |
| ----------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------- |
| **Hash-Based / Key-Based**    | Apply hash function to key: $\text{Shard} = \text{hash}(\text{key}) \pmod N$          | Uniform data and write distribution; eliminates monotonic sequence hotspots.             | Range queries (BETWEEN, >, <) require scanning all shards (Scatter-Gather). | High-throughput OLTP user profile stores, session tokens.       |
| **Range-Based**               | Route by key value ranges (e.g., IDs $1 - 1,000,000 \to \text{Shard 1}$)              | Fast, localized range scans on adjacent keys.                                            | Severe write hotspots on sequential or timestamp keys.                      | Time-series metrics, historical audit logs, order histories.    |
| **Directory-Based (Lookup)**  | Query a centralized lookup table/service to retrieve key-to-shard mapping             | Highly flexible; allows moving individual records dynamically between shards.            | Centralized lookup service becomes a performance bottleneck and SPOF.       | Enterprise multi-tenant applications with custom tenant sizing. |
| **Geographic (Geo-Sharding)** | Map shard keys to geographic locations (e.g., Country = 'JP' \to \text{Tokyo Shard}). | Low network latency for local users; strict regulatory data residency compliance (GDPR). | Data volume and access rates are heavily skewed by regional population.     | Global payment rails, localized social media feeds.             |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Query Routing Architecture Topologies:

When an application issues a query, the system must direct it to the target shard. Modern systems use one of three primary routing patterns:

```
1. PROXY-BASED ROUTING                     2. CLIENT-SIDE ROUTING                  3. COORDINATOR-NODE ROUTING
[ App ] ──► [ Routing Proxy ]              [ Smart Client Driver ]                 [ App ] ──► [ Any Shard Node ]
                │                                   │                                                │
        ┌───────┴───────┐                   ┌───────┴───────┐                                ┌───────┴───────┐
        ▼               ▼                   ▼               ▼                                ▼               ▼
    [Shard 1]       [Shard 2]           [Shard 1]       [Shard 2]                            [Shard 1] ◄────► [Shard 2]
(e.g., Vitess / Mongo Router)       (e.g., Cassandra Client Driver)                     (e.g., CockroachDB / YugabyteDB)
```

#### Proxy-Based Routing (e.g., Vitess, Mongos, ProxySQL):

- Applications connect to a stateless proxy layer that acts as a standard single database interface.
- The proxy parses the SQL syntax tree (AST), extracts the shard key, looks up cluster topology, and forwards requests.
- **Advantage**: Decouples database topology from application code; easy to manage connection pools.

#### Client-Side Routing (Smart Drivers):

- The application embeds a driver that maintains an in-memory routing map updated via cluster discovery.
- **Advantage**: Zero proxy network hop latency; queries go directly from application memory to the destination server node.

#### Coordinator-Node / Peer-to-Peer Routing:

- Every node in the cluster can accept any query. If Node A receives a query meant for Node B, Node A acts as a coordinator, fetches data from Node B over internal network links, and returns it to the client.

#### Cross-Shard Operations & The Scatter-Gather Penalty:

- Queries that do not include the shard key cannot be routed to a single node. The router must execute a Scatter-Gather operation:

```
Query: SELECT * FROM users WHERE email = 'alice@example.com'; (Sharded by user_id)

          [ Router / Coordinator ]
            /        │        \
  (Broadcast)     (Broadcast)  (Broadcast)
          ▼          ▼          ▼
     [Shard 1]   [Shard 2]   [Shard 3]
          │          │          │
       (Empty)   (1 Match)   (Empty)
          \          │          /
           └─────────┼─────────┘
                     ▼
           [ Merge & Return ]
```

#### The Latency Amplification Equation:

- The response latency of a scatter-gather query is determined by the slowest responding node in the broadcast set (the $p99$ tail latency penalty):

$$\text{Latency}_{\text{Scatter-Gather}} = \max(\text{Latency}_{\text{Shard}_1}, \text{Latency}_{\text{Shard}_2}, \dots, \text{Latency}_{\text{Shard}_N})$$

- As cluster size $N$ increases, the probability that at least one shard experiences a disk I/O stall or garbage collection pause approaches $100\%$, causing high tail latencies across scatter-gather queries.

#### Table Co-location (Entity Groups):

To execute high-speed relational joins (JOIN) in a sharded environment without triggering cross-network data shuffling, related tables must be co-located on the same physical shard using a shared shard key.

```
CO-LOCATED SHARDING (Shared Shard Key: user_id)

Shard Node 1 (user_id: 1..100)           Shard Node 2 (user_id: 101..200)
┌──────────────────────────────────────┐  ┌──────────────────────────────────────┐
│ Users Table (id: 42, "Alice")        │  │ Users Table (id: 105, "Bob")         │
│ Orders Table (user_id: 42, Order #1) │  │ Orders Table (user_id: 105, Order #2)│
└──────────────────────────────────────┘  └──────────────────────────────────────┘
```

- **Query**: SELECT \* FROM users JOIN orders ON users.id = orders.user_id WHERE users.id = 42;
- Executes completely locally inside Shard 1 without network traversals!

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Live Resharding & Rebalancing Strategies:

As data volume grows, individual shards fill up, requiring cluster expansion (e.g., expanding from 8 shards to 16 shards) without taking application writes offline.

##### The 4-Phase Online Resharding Pipeline:

```
================================================================================
PHASE 1: DUAL-WRITE/CDC REPLICATION ──► PHASE 2: HISTORICAL CATCHUP
                    │                          │
PHASE 4: CLEANUP OLD SHARD DATA     ◄── PHASE 3: ROUTER TOPOLOGY CUTOVER
================================================================================
```

- **Phase 1**: Target Provisioning & CDC Setup: Provision new target Shards 9–16. Attach Change Data Capture (CDC) streams to tail the transaction logs of existing Shards 1–8.
- **Phase 2**: Historical Snapshot Backfill: Copy static data snapshots from source shards to target shards. CDC streams replay updates to bridge incremental state gaps.
- **Phase 3**: Router Cutover: Verify zero replication lag ($\Delta t \to 0$). Atomic configuration flags update the routing proxy's hash map. New writes for affected key ranges switch instantly to Target Shards 9–16.
- **Phase 4**: Source Cleanup: Asynchronously delete migrated rows from old source shards to reclaim disk space.

#### Resolving the "Celebrity / Hotspot" Shard Problem:

- If a sharded social platform hosts a user with 100 million followers, using user_id as the shard key creates a severe read/write hot spot on the single node hosting that user's records.

#### Mitigation Tactics:

Key Salting (Compound Shard Keys): Append a pseudo-random numeric suffix to hot write keys:

$$\text{Shard Key} = \text{user\_id} + \text{"\_"} + (\text{random}(0, K))$$

This splits incoming writes across $K$ physical shards. Range reads then query all $K$ salted shards in parallel and merge the results.

Global Reference Tables (Broadcast Tables): Small, slowly changing lookup tables (e.g., Currencies, Countries, TaxRates) are fully replicated to every single shard node in the cluster, allowing local joins without cross-shard network requests.

#### Cross-Shard Transactions: Two-Phase Commit ($2\text{PC}$) vs. Saga Pattern:

Updating rows that reside on separate physical shards (e.g., transferring money from Account A on Shard 1 to Account B on Shard 2) loses single-node ACID atomicity guarantees.

**Two-Phase Commit ($2\text{PC}$ - Distributed ACID)**: A central coordinator locks records on both Shard 1 and Shard 2, executes a prepare step, and commits synchronously.

**Trade-off**: High network latency overhead; holds lock resources across network bounds, risking distributed deadlocks and system stalls.

**Saga Pattern (Distributed BASE)**: Breaks the transaction into asynchronous local transactions. Shard 1 decrements Account A and publishes an event; Shard 2 reads the event and increments Account B. If Shard 2 fails, a compensating transaction rolls back Shard 1 asynchronously.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
                SHARDED DATABASE QUERY ROUTING & EXECUTION FLOW
================================================================================

1. SINGLE-SHARD POINT LOOKUP (Optimal Path - O(1) Network Hop)
--------------------------------------------------------------------------------
Query: SELECT * FROM orders WHERE user_id = 8841 AND order_id = 901;

[ Client ] ──► [ Smart Router ] ──(hash(8841) -> Shard 3)──► [ Shard Node 3 ]
                                                              (Executes Locally)
                                                                      │
[ Client ] ◄─────────────────(Returns Data)───────────────────────────┘


2. CROSS-SHARD SCATTER-GATHER (Sub-Optimal Path - O(N) Fan-Out)
--------------------------------------------------------------------------------
Query: SELECT * FROM orders WHERE total_amount > 5000.00; (No user_id provided!)

                              [ Router Proxy ]
                               │   │   │   │
    ┌──────────────────────────┼───┼───┼─────────────────────────┐
    │ (Parallel Fan-Out)       │   │   │                         │
    ▼                          ▼   ▼   ▼                         ▼
[ Shard 1 ]                [ Shard 2 ] ... [ Shard N-1 ]     [ Shard N ]
(Scan Index)               (Scan Index)   (Scan Index)      (Scan Index)
    │                          │               │                 │
    └──────────────────────────┴───┬───────────┴─────────────────┘
                                   │ (Merge & Filter Results)
                                   ▼
[ Client ] ◄─────────────── [ Final Payload ]
================================================================================
```

### 6. Interview Checklist:

- **State the Shard Key Rule First**: Emphasize that choosing a shard key is an immutable decision. A high-cardinality key with uniform hash distribution prevents hotspots, while co-locating dependent entities (e.g., user_id on both Users and Orders) prevents cross-shard network joins.

- **Explain Scatter-Gather Latency Penalties**: Explicitly call out why queries missing the shard key trigger broadcast scans across all shards, causing $p99$ tail latency degradation due to the slowest node.

- **Detail Online Resharding Mechanics**: Walk through how live database clusters scale out using CDC streams, historical backfilling, and router topology updates to rebalance keys without application downtime.

- **Discuss Hotspot Mitigations**: Present concrete solutions for skewed data distributions: Key Salting (key + suffix) for high-write entities and Broadcast Tables for static reference datasets.

- **Differentiate 2PC and Sagas for Cross-Shard Writes**: Contrast synchronous, blocking Two-Phase Commit ($2\text{PC}$) locking with asynchronous, event-driven Saga compensating transactions.
