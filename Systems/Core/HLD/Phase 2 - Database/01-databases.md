## SQL vs NoSQL DBs (Document, Key-Value, Graph, Columnar)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Think of data storage options like distinct logistics facilities:

- **SQL (Relational Databases)**: A rigid, meticulously organized safe-deposit vault with indexed steel drawers. Every item placed inside must fit an exact pre-measured template. If you want to link an item in Vault A to Vault B, the master catalog keeps strict track of relationships, preventing any missing or orphaned items.

- **NoSQL Key-Value**: A fast coat-check room. You trade a ticket (Key) and get your coat back (Value) instantly. You have no idea what is inside the coat pockets, nor do you care; you only care about immediate, constant-time retrieval.

- **NoSQL Document**: A modern filing cabinet filled with flexible JSON folders. Each folder can contain different documents, lists, and nested sub-folders. You can add new forms into a folder without re-architecting the entire filing cabinet.

- **NoSQL Wide-Column / Columnar**: A hyper-efficient accounting ledger where all transactions for a specific metric across millions of users (e.g., "Total Purchases") are stored sequentially on the same physical paper, making bulk calculations lighting fast without flipping through irrelevant pages.

- **NoSQL Graph**: An interactive pinboard with colored strings connecting people, locations, and events. Instead of searching through cabinet files to trace who knows whom, you simply follow the physical strings directly from one pin to the next.

#### The Core Problem Solved:

- Relational databases enforce strict schemas, foreign keys, and $ACID$ guarantees across normalized tables. While ideal for transactional integrity (e.g., banking), scaling SQL horizontally requires complex sharding and expensive multi-table joins.

- NoSQL datastores relax relational guarantees, strict schemas, or immediate consistency to optimize for specific access patterns: horizontal write/read scale, semi-structured document payloads, high-speed analytical aggregations, or deeply connected network queries.

---

### 2. The Basics (Scratch Level)

#### Core Classification Matrix:

| Database Type        | `Primary Data Model`                                             | `Core Access Pattern`                                                            | `Typical Latency Profile`                        | `Dominant Technologies`                |
| -------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------- |
| **Relational (SQL)** | Tables (Rows & Columns) with explicit Foreign Keys.              | Structured SQL queries with multi-table JOINs and $ACID$ transactions.           | Low/Medium ($1\text{ms} - 50\text{ms}$)          | PostgreSQL, MySQL, Oracle, CockroachDB |
| **Key-Value**        | Arbitrary byte arrays or JSON mapped to a unique Key string.     | Fast point lookups ($O(1)$) by exact Primary Key match (GET/PUT).                | Ultra-Low ($< 1\text{ms}$)                       | Redis, AWS DynamoDB, Memcached         |
| **Document**         | Nested JSON / BSON documents grouped into collections.           | Polymorphic schema queries, nested field filtering, document updates.            | Low ($1\text{ms} - 10\text{ms}$)                 | MongoDB, Couchbase, DocumentDB         |
| **Wide-Column**      | Row keys mapping to dynamic column families stored contiguously. | High-throughput sequential range scans and massive write streams.                | Low ($1\text{ms} - 5\text{ms}$writes)            | Apache Cassandra, ScyllaDB, HBase      |
| **Columnar (OLAP)**  | Data stored on disk column-by-column rather than row-by-row.     | Vectorized analytical aggregations (SUM, AVG, COUNT) across millions of records. | Variable ($100\text{ms} - \text{seconds}$)       | ClickHouse, Snowflake, Google BigQuery |
| **Graph**            | Nodes (entities), Edges (relationships), and Properties.         | Pointer-hopping relationship traversals ($N$-degree neighbor queries).           | Low for graph depth ($1\text{ms} - 15\text{ms}$) | Neo4j, AWS Neptune, Memgraph           |

---

### 3. Deep Dive & Architecture (Mid Level)

#### Storage Engine Mechanics: B+Trees vs. LSM-Trees:

The operational distinction between databases often boils down to their underlying disk storage engine.

#### 1. B+TREE STORAGE ENGINE (In-Place Updates - Typical in SQL/InnoDB):

```
   ┌─────────────────────────────────────────────────────────┐
   │ Root Page                                               │
   └───────────────┬─────────────────────────┬───────────────┘
                   ▼                         ▼
           ┌──────────────┐          ┌──────────────┐
           │ Internal Node│          │ Internal Node│
           └───────┬──────┘          └───────┬──────┘
                   ▼                         ▼
           ┌──────────────┐          ┌──────────────┐
           │ Leaf Page    │◄────────►│ Leaf Page    │ (Doubly Linked List for Range Scans)
           └──────────────┘          └──────────────┘
```

- Writes require random disk I/O to overwrite existing pages in-place.

#### 2. LSM-TREE STORAGE ENGINE (Append-Only - Typical in NoSQL Writes):

```
   [ Incoming Write ] ──> [ Write-Ahead Log (WAL) ] (Sequential Disk Append)
                                        │
                                        ▼
   [ In-Memory MemTable (Sorted Buffer) ] ── (Flush when full)──> [ SSTable L0 (Disk) ]
                                        │
                                  (Compaction)
                                        ▼
                                [ SSTable L1 (Disk) ]
```

- Converts random writes into fast sequential I/O appends; reads require Bloom Filters.

##### 1. B+Trees (Row-Oriented RDBMS):

- **Mechanics**: Tree structure where all data rows reside in Leaf Pages at equal depth, linked horizontally for range scans.
- **Write Flow**: In-place updates. Modifying a record requires reading a page into memory, updating it, and writing it back to disk.
- **Trade-off**: Optimized for random reads ($O(\log N)$) and transactional consistency, but suffers from high random write I/O and write amplification.

##### 2. Log-Structured Merge-Trees (LSM-Trees - Cassandra, RocksDB, MongoDB WiredTiger)

- **Mechanics**: Writes are appended sequentially to an in-memory MemTable and a Write-Ahead Log (WAL). When the MemTable reaches capacity, it flushes to disk as an immutable SSTable (Sorted String Table).
- **Read Flow**: Must check MemTable, then search across multiple SSTables on disk. Optimized using in-memory Bloom Filters to quickly confirm if a key is absent from an SSTable.
- **Trade-off**: Optimized for high write throughput and sequential storage, at the cost of higher read latency and background Compaction CPU overhead.

#### Columnar vs. Row-Oriented Storage Layout:

Consider a table with schema: (User_ID, Age, Purchase_Amount, Timestamp)

##### ROW-ORIENTED LAYOUT (PostgreSQL / MySQL):

```
Disk Address: [Row 1: 101, 28, $150, 10:00] [Row 2: 102, 45, $200, 10:01] [Row 3: 103, 31, $50, 10:02]
```

- Scans entire rows off disk into memory even if querying only "Purchase_Amount".

##### COLUMN-ORIENTED LAYOUT (ClickHouse / Snowflake):

```
Disk Block 1 (User_ID): [101, 102, 103]
Disk Block 2 (Age): [28, 45, 31]
Disk Block 3 (Amount): [$150, $200, $50]
Disk Block 4 (Timestamp): [10:00, 10:01, 10:02]
```

- Analytical query "SELECT SUM(Amount)" reads ONLY Disk Block 3.

- **Graph Storage Mechanics**: Index-Free Adjacency. Unlike SQL databases that resolve relationships using foreign key lookups or B-Tree index scans at runtime ($O(\log N)$ per join), native Graph databases use Index-Free Adjacency. Nodes store direct physical memory pointers to their adjacent Edge records. Traversing relationships is a $O(1)$ pointer dereference operation.

---

### 4. Advanced Strategies & Trade-offs (Pro Level)

#### ACID vs. BASE Paradigm:

#### 1. ACID (Traditional SQL):

- **Atomicity**: All operations in a transaction succeed or fail together.
- **Consistency**: Data transitions strictly from one valid schema state to another.
- **Isolation**: Concurrent transactions execute without interference (Read Committed, Repeatable Read, Serializable via 2PL/MVCC).
- **Durability**: Committed transactions persist across system power loss.

#### 2. BASE (Distributed NoSQL):

- **Basically Available**: System guarantees availability; partial node failures leave the rest of the cluster operational.
- **Soft State**: State may change over time without user interaction due to background replication.
- **Eventual Consistency**: Replicas converge to identity given sufficient time without new updates.

### PACELC Theorem (Beyond CAP):

The traditional CAP Theorem (Choose 2 of Consistency, Availability, Partition Tolerance) is incomplete because partitions are rare. The PACELC Theorem extends CAP to normal operating conditions:

$$\text{If } \mathbf{P} \text{ (Partition): Choose } \mathbf{A} \text{ or } \mathbf{C} \quad \mathbf{E} \text{lse: Choose } \mathbf{L} \text{ or } \mathbf{C}$$

```
┌──► Availability (A) [e.g., DynamoDB / Cassandra]
┌──► If Partition (P)
│ └──► Consistency (C) [e.g., HBase / MongoDB]
PACELC ─────┤
│ ┌──► Latency (L) [e.g., DynamoDB Eventual Read]
└──► Else (E) ─┤
└──► Consistency (C) [e.g., PostgreSQL / Spanner]
```

- **MongoDB**: $PC / EC$ — Prioritizes Consistency during partitions and lower latency over strong consistency for local reads.

- **Cassandra**: $PA / EL$ — Prioritizes Availability during partitions and ultra-low Latency during normal operations via tunable consistency (LOCAL_QUORUM, ONE).

#### Modeling Anti-Patterns & Structural Trade-offs:

##### Document Databases (Embedding vs. Referencing):

- **Embedding (Denormalization)**: Storing line items directly inside an Order document. Fast $O(1)$single-document read, but hits hard document size ceilings (e.g., MongoDB $16\text{MB}$ limit) and causes data duplication.

- **Referencing**: Storing Object IDs pointing to another collection. Restores normalization, but introduces client-side joins and multiple network round-trips.

##### Wide-Column Databases (Query-First Modeling):

- In Cassandra/ScyllaDB, you model tables around queries, not real-world entities. If you need to search users by Email AND by PhoneNumber, you create two separate tables containing duplicated data.

---

### 5. Text-Based Architecture Diagram

```
================================================================================
                   DATABASE ARCHITECTURE & DATA FLOW PATTERNS
================================================================================

1. RELATIONAL DATABASE (PostgreSQL - B+Tree / Shared-Disk / ACID)
--------------------------------------------------------------------------------
[ Client Query ] ──> [ Query Planner / Optimizer ] ──> [ Lock Manager (MVCC) ]
                                                            │
                                                            ▼
[ Physical Disk Pages ] <──(Random I/O)── [ Buffer Pool (Shared Memory Cache) ]


2. DISTRIBUTED NOSQL DOCUMENT (MongoDB - Sharded Architecture)
--------------------------------------------------------------------------------
[ Client Request ] ──> [ mongos Router ] ──(Hash Shard Key Mapping)
                              │
        ┌─────────────────────┴─────────────────────┐
        ▼                                           ▼
 [ Shard 1 (Primary) ]                       [ Shard 2 (Primary) ]
 (Executes Query / WiredTiger)               (Executes Query / WiredTiger)
        │                                           │
        ▼ (Async Replication)                       ▼ (Async Replication)
 [ Shard 1 (Secondary) ]                     [ Shard 2 (Secondary) ]


3. DISTRIBUTED WIDE-COLUMN (Cassandra - Shared-Nothing Peer Ring)
--------------------------------------------------------------------------------
[ Client Write ] ──> [ Any Coordinator Node ] ──(Consistent Hash of Partition Key)
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼ (Replication Factor = 3)                  ▼
 [ Node A (Write WAL + MemTable) ]          [ Node B (Write WAL + MemTable) ]
================================================================================
```

---

### 6. Interview Checklist:

- **Lead with the Access Pattern, Not Vendor Brand Names**: Frame your decision matrix around read/write ratios, latency SLAs, query flexibility, and consistency requirements. State: "I choose relational SQL when structural data integrity and multi-entity ACID transactions are paramount. I select NoSQL key-value/document for unstructured scale and simple lookup patterns."

- **Explain the Storage Engine Consequence**: Demonstrate deep technical authority by highlighting why a database behaves a certain way under load. Contrast B+Trees (random I/O overhead, fast reads) with LSM-Trees (append-only sequential writes, read compaction penalty).

- **Apply PACELC over CAP**: When evaluating distributed databases (DynamoDB, Cassandra, CockroachDB), frame consistency trade-offs using PACELC notation ($PA/EL$ vs $PC/EC$) to explain operational latency during normal non-partitioned runtime.

- **Pitch Polyglot Persistence**: In modern systems design, avoid forcing a single database engine to solve every problem. Propose Polyglot Persistence: PostgreSQL for primary transactional billing, Redis for session caching, Elasticsearch for full-text search, and ClickHouse for real-time analytical dashboards.
