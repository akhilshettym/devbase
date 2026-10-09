## Data Partitioning

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a massive e-commerce fulfillment center processing $100\text{ million}$ packages a day:

- **Single Unpartitioned Database**: Storing all $100\text{ million}$ packages in one giant warehouse room. Every time a worker needs to pick an item, they must navigate through miles of aisles, bumping into thousands of other workers. When the warehouse runs out of floor space, your only choice is to buy a single, ridiculously expensive hyper-mansion warehouse (Vertical Scaling / Scale-Up).

- **Partitioned / Sharded Database**: Dividing the inventory into $26$ separate, independent building units marked from A to Z based on the first letter of the destination city. Workers in Building NY only handle New York packages without interfering with workers in Building CA. If package volume doubles, you simply construct 10 more building units and distribute the workload horizontally (Horizontal Scaling / Scale-Out).

#### The Core Problem Solved:

- Single-node databases hit immutable hardware ceilings: total RAM capacity, maximum PCIe bus disk I/O throughput, and CPU core lock contention.

- Data Partitioning (often called Sharding when distributed across multiple physical network nodes) splits a single massive dataset into smaller, independent, manageably-sized logical subset tables called partitions. It enables horizontal scale-out across hundreds of commodity server nodes, allowing systems to process millions of concurrent transactions and petabytes of data with bounded latency.

---

### 2. The Basics (Scratch Level):

#### Horizontal vs. Vertical Partitioning:

```
ORIGINAL TABLE: Users(id, name, email, billing_address, bio_text, blob_avatar)

HORIZONTAL PARTITIONING (Sharding by Row)   VERTICAL PARTITIONING (Splitting by Column)
Node 1: Rows where id IN (1..1,000,000)      Table A (Core): Users(id, name, email)
Node 2: Rows where id IN (1,000,001..2M)   Table B (Profile): UserProfiles(id, bio_text, avatar)
```

- **Horizontal Partitioning (Sharding)**: Keeps table schema identical across partitions but splits rows across physical tables/nodes based on a Partition Key.

- **Vertical Partitioning**: Splits table columns into separate tables based on access patterns (e.g., moving large binary BLOB fields away from frequently queried lean columns to optimize CPU memory page caching).

#### Partitioning Strategies Matrix:

| Strategy             | `Mechanics`                                                                         | `Key Advantages`                                                                       | `Key Drawbacks`                                                                 | `Ideal Use Cases`                                              |
| -------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| **Range**            | Assigns contiguous key ranges to partitions (e.g., Date: 2026-01-01 to 2026-01-31). | High performance for range queries (BETWEEN, >, <).                                    | Severe write hotspots on monotonic keys (e.g., AUTO_INCREMENTor timestamp ids). | Time-series data, historical archive logs, financial quarters. |
| **Hash / Modulo**    | Applies hash function to key: $\text{Partition} = \text{hash}(\text{key}) \pmod N$. | Uniform, random data distribution across all nodes; eliminates monotonic hotspots.     | Terrible for range queries (forces full scatter-gather across all nodes).       | User profiles, account balance lookups, session tokens.        |
| **List / Directory** | Explicitly maps discreet values to nodes (e.g., Region: 'EU' $\rightarrow$Node 1).  | Precise geographic data locality and compliance alignment (e.g., GDPR data residency). | Risk of extreme data size imbalances across regional partitions.                | Multi-tenant SaaS applications, localized geographic datasets. |
| **Composite**        | Combines multiple methods (e.g., Hash by Tenant_ID, then Range by Created_At).      | Combines write isolation with localized range scanning within tenants.                 | Higher operational complexity and routing overhead.                             | Enterprise multi-tenant SaaS platforms, large log management.  |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Secondary Indexes in Partitioned Databases:

Partitioning primary keys is straightforward, but handling Secondary Indexes (e.g., finding a user by emailwhen the database is partitioned by user_id) introduces fundamental architectural trade-offs:

```
1. LOCAL SECONDARY INDEX (Document-Partitioned)    2. GLOBAL SECONDARY INDEX (Term-Partitioned)
Partition 1 (Users 1-100)                          Partition 1 (Users 1-100) | Secondary Index A-M
 ├── Data Rows (1-100)                              ├── Data Rows (1-100)   │ (Maps emails 'A'..'M'
 └── Index: Email -> Local Row ID                   └── Index (A-M Emails)  │  to ANY node ID)
                                                                              │
Partition 2 (Users 101-200)                        Partition 2 (Users 101-200)| Secondary Index N-Z
 ├── Data Rows (101-200)                            ├── Data Rows (101-200) │ (Maps emails 'N'..'Z'
 └── Index: Email -> Local Row ID                   └── Index (N-Z Emails)  │  to ANY node ID)
```

#### 1. Local Secondary Index (Document-Partitioned):

Each partition maintains an index exclusively for the data rows residing inside that single partition.

- **Write Path**: Ultra-fast $O(1)$. Modifying a row updates only the local index on that specific node.
- **Read Path**: Expensive Scatter-Gather. Searching by email forces the query router to broadcast requests to every single partition in the cluster and merge the results.

#### 2. Global Secondary Index (Term-Partitioned):

The secondary index is partitioned independently across nodes based on the index key values (e.g., Partition 1 stores emails starting with A-M, regardless of where the user row lives).

- **Read Path**: Fast $O(1)$ point read. The query router targets the single partition holding that specific email range.
- **Write Path**: Slow, complex, multi-node write. Updating a row requires an asynchronous or two-phase commit ($2\text{PC}$) update across both the data node and the global index node.

#### Request Routing Architectures:

How does a database client know which node holds key user_9412?

```
APPROACH A: ROUTING LAYER (Proxy Engine)     APPROACH B: CLIENT-SIDE ROUTING (Smart Client)
[ Client ] ──► [ Proxy (Vitess/Mongos) ]      [ Smart Client (Local Topology Cache) ]
                    │                                     │
        ┌───────────┴───────────┐                         ├─────────────────────────┐
        ▼                       ▼                         ▼                         ▼
  [ Partition 1 ]         [ Partition 2 ]           [ Partition 1 ]           [ Partition 2 ]
```

- **Routing Proxy (e.g., Vitess for MySQL, Mongos for MongoDB)**: Clients connect to a stateless proxy layer that inspects the query's AST, extracts the partition key, determines the destination partition from metadata, and forwards the command.

- **Smart Client (e.g., Cassandra Drivers)**: The client driver registers directly with cluster coordination services (e.g., Zookeeper, etcd, or Gossip protocols). It maintains an in-memory routing map locally, dispatching queries straight to the target physical node without intermediary proxy hops.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Consistent Hashing & Virtual Nodes (vnodes):

Standard hash partitioning ($\text{Node} = \text{hash}(k) \pmod N$) catastrophically fails when scaling out. If you add a single new node ($N \to N+1$), almost every key maps to a new node, triggering a full cluster data reshuffle ($100\%$ data migration).

Consistent Hashing solves this by mapping both nodes and keys onto an abstract $2^{32}-1$ integer Hash Ring:

```
                             [ Node A (vnode 1) ] (Position 0)
                                   /        \
                  [ Key X ] ──────►          ◄────── [ Node C (vnode 1) ]
                 (Hashes to 45)             /       (Position 2,147,483,648)
                                   \        /
                             [ Node B (vnode 1) ] (Position 1,073,741,824)
```

- **Ring Assignment**: A key is assigned to the first physical node encountered when walking clockwise around the ring.

- **Node Addition / Removal Impact**: Adding a new node takes ownership of keys only from its immediate clockwise neighbor. On average, adding a node requires moving only $\frac{1}{N}$ of the total keys:

$$\text{Data Migration Volume} = \frac{1}{N_{\text{new}}}$$

- **Virtual Nodes (vnodes)**: To avoid uneven data distribution (hotspots on physical ring gaps), each physical node is assigned hundreds of lightweight Virtual Nodes scattered pseudo-randomly across the ring. This ensures near-perfect balance and parallelizes rebalancing during scale-out events.

#### Mitigating the Hotspot Problem (The "Celebrity" Issue):

When a single partition key experiences massive access volumes (e.g., a viral celebrity account with $100\text{ million}$ followers posting on Twitter/X), standard partitioning collapses node capacity regardless of cluster size.

#### Architectural Mitigation Techniques:

- **Key Salting / Randomization**: Append a random integer suffix ($0..K$) to the partition key during writes:

$$\text{Partition Key}_{\text{write}} = \text{user\_id} + \text{"\_"} + \text{random}(0, K)$$

This scatters the celebrity's incoming writes across $K$ distinct physical nodes. Range queries then read across all $K$ salted partitions in parallel and aggregate results.

- **Read-Replication / Multi-Region Caching**: Route hot partition reads to ephemeral, read-only cache layers (Redis) or dedicated read-replicas, isolating write nodes from read spikes.

#### Distributed Cross-Partition Operations:

Executing queries that cross partition boundaries introduces severe latency and consistency penalties:

- **Scatter-Gather Processing**: Searching without a partition key forces the coordinator node to execute parallel queries on $N$ nodes, waiting for the single slowest node (p99 tail-latency amplification) before stitching together response frames.
- **Two-Phase Commit (2PC)**: Executing atomic updates across rows living in Partition 1 and Partition 2 requires distributed locking, introducing network round-trip overhead and risk of distributed deadlocks.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
         CONSISTENT HASH RING WITH VIRTUAL NODES & ROUTING FLOW
================================================================================

Query: SELECT * FROM users WHERE user_id = 'usr_8412';

1. HASH EVALUATION
--------------------------------------------------------------------------------
hash('usr_8412')  ==>  Integer Position: 2,840,119,400 (Range: 0 .. 2^32 - 1)


2. CIRCULAR HASH RING TRAVERSAL (Clockwise Search)
--------------------------------------------------------------------------------
                   [ Ring Position 0 ]
                            │
      ┌─────────────────────┼─────────────────────┐
      │                                           │
[ Node A (vnode 12) ]                       [ Node B (vnode 3) ]
(Pos: 500,000,000)                          (Pos: 1,200,000,000)
      │                                           │
      │                                           │
      │           ★ Target Hash Position          │
      │            (Pos: 2,840,119,400)           │
      │                     │                     │
      ▼                     ▼                     ▼
[ Node C (vnode 8) ] ◄── [ Target Key ] ──► [ Node A (vnode 41) ]
(Pos: 2,500,000,000)                        (Pos: 3,100,000,000)
                                                   ▲
                                                   │
                                           (First Clockwise
                                             Node Hit!)

3. ROUTING DECISION
--------------------------------------------------------------------------------
Key maps to: Node A (Physical Machine 1)
Action: Smart Driver routes payload directly to IP 10.0.4.12:9042
================================================================================
```

---

### 6. Interview Checklist:

- **Differentiate Partitioning vs. Sharding**: Clarify that partitioning is the general logical division of data, while sharding specifically refers to horizontal partitioning across multiple isolated physical network nodes.

- **Explain Key Selection Trade-offs**: Emphasize that choosing a partition key is a permanent architectural choice. Frame Range Partitioning as ideal for range scans but prone to write hotspots, and Hash Partitioning as optimal for uniform write distribution at the cost of range queries.

- **Detail Local vs. Global Secondary Indexes**: Walk through why Local Secondary Indexes suffer from Scatter-Gather read penalties across all partitions, whereas Global Secondary Indexes suffer from complex multi-node write overheads.

- **Explain Consistent Hashing and Virtual Nodes**: Clearly articulate why standard modulo partitioning ($\pmod N$) breaks down during node additions, and detail how Consistent Hashing combined with Virtual Nodes (vnodes) minimizes data migration volume to $\frac{1}{N}$.

- **Propose Hotspot Solutions**: Pitch Key Salting (key + random_suffix) and dedicated caching/read-replication layers to handle extreme skew in partition access patterns.
