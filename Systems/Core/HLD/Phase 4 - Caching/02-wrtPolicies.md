## Write Policies: Write-back, Write-through, Write-around

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine an executive managing sensitive contracts with the help of an assistant:

- **Write-Through (Synchronous Filing)**: The executive signs a contract and holds the client on line 1 while handing the document to the assistant. The assistant walks to the basement filing cabinet, files the paper,and returns to give a thumbs-up. Only then does the executive tell the client "Done!" It is slow, but guarantees the basement file and the desk match instantly.

- **Write-Back / Write-Behind (Asynchronous Filing)**: The executive signs the contract, drops it into an "Outbox" tray on the desk, and instantly tells the client "Done!" Every hour, a clerk collects the tray,batches the contracts, and updates the basement filing cabinet in the background. It is blazing fast for the executive, but if the office catches fire before the clerk runs downstairs, unfiled documents are destroyed.

- **Write-Around (Direct Archiving)**: The executive bypasses their desk entirely, mailing new contracts directly to the basement storage room. If the executive needs that contract later, they fetch it from the basement and place a working copy on their desk.

#### The Core Problem Solved:

- Caching read-heavy workloads is straightforward, but mutating state introduces synchronization challenges.When an application writes or updates a record, it must decide when and how to update both the in-memory cache and the persistent underlying database.

- Choosing the wrong cache write policy leads to stale data reads, write latency bottlenecks, database write queue overload, or catastrophic data loss during system crashes.

---

### 2. The Basics (Scratch Level):

#### Write Policy Comparison Matrix:

| Policy                       | `Primary Write Target`    | `DB Update Mechanics`                  | `Write Latency`                          | `Risk of Data Loss`                       | `Cache Pollution Risk`                             | `Primary Use Cases`                                                            |
| ---------------------------- | ------------------------- | -------------------------------------- | ---------------------------------------- | ----------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------ |
| **Write-Through**            | Cache + DB simultaneously | Synchronous inline write               | High($T_{\text{Cache}} + T_{\text{DB}}$) | Zero (Data persisted immediately)         | Medium (Caches items that may never be read again) | Financial ledgers, user authentication profiles, strict consistency domains.   |
| **Write-Back(Write-Behind)** | Cache first               | Asynchronous background batch/flush    | Ultra-Low($T_{\text{Cache}}$only)        | High (If cache node crashes before flush) | Medium                                             | High-frequency counters, IoT telemetry, game state updates, clickstream logs.  |
| **Write-Around**             | Database directly         | Direct database write (Cache bypassed) | Low to Medium($T_{\text{DB}}$only)       | Zero                                      | None(Cache remains lean and clean)                 | Write-heavy / read-rarely data, historical log archiving, large media uploads. |

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. Write-Through Policy Mechanics:

In a Write-Through pattern, the cache acts as the main write facade. The application writes data directly to the cache, and the cache layer synchronously writes the update to the persistent database before acknowledging success to the caller.

```
                                  WRITE-THROUGH EXECUTION FLOW

[ Client ] ───(1. Write Key="u1", Val="A")───► [ Cache Layer ]
                                                    │
                                                    ├───(2. Synchronous Write)───► [ Persistent DB ]
                                                    │                                    │
                                                    │◄──(3. Write ACK)───────────────────┘
                                                    │
[ Client ] ◄──(4. Return Success)───────────────────┘
```

#### Key Characteristics & Trade-offs:

Guaranteed Data Consistency: The cache and persistent database are updated inside the same transaction context, eliminating stale reads on subsequent operations.

Latency Penalty: The write path latency is additive:

$$\text{Latency}_{\text{Write-Through}} = \text{Latency}_{\text{Cache}} + \text{Latency}_{\text{DB}}$$

**Pairing with Read-Through**: Write-Through is almost universally paired with a Read-Through strategy,creating a clean abstraction layer where application code never interacts directly with the database.

#### 2. Write-Back (Write-Behind) Policy Mechanics:

In a Write-Back pattern, writes are executed synchronously against the in-memory cache and acknowledged to the client sub-millisecond. A background worker or daemon process periodically drains the modified cache keys (dirty keys) and flushes them to the persistent database in batches.

```
                                 WRITE-BACK (WRITE-BEHIND) FLOW

[ Client ] ───(1. Write Key="c1", Val=100)───► [ Cache Layer ] ──► Stores in "Dirty Keys Queue"
                                                     │
[ Client ] ◄──(2. Instant ACK < 1ms)─────────────────┘
    │
    ▼ (Async Background Flush)
[ Worker Thread / Queue ]
    │
    └───(3. Batch Write / Coalesce)──► [ Persistent DB ]
```

#### Key Characteristics & Trade-offs:

- **Write Performance & Throughput**: Write operations complete at memory bus speeds ($< 1\text{ ms}$),completely isolating application write paths from database disk I/O bottlenecks.
- **Write Coalescing (Collapsing)**: If key counter_101 is incremented 1,000 times in 1 second in the cache:
- **Without Write-Back**: Executes 1,000 individual SQL UPDATE queries against the database.
- **With Write-Back**: The background worker collapses the 1,000 updates into a single consolidated database operation (UPDATE counters SET val = val + 1000 WHERE id = 101), reducing database disk write I/O by $99.9\%$.
- **The Volatility Danger**: If the cache instance crashes, undergoes a hard reboot, or experiences an out-of-memory (OOM) kill before dirty keys are flushed to disk, all unpersisted writes are permanently lost.

#### 3. Write-Around Policy Mechanics:

In a Write-Around pattern, the application completely bypasses the cache layer during write operations,writing data directly to the persistent database. The cache is updated only when a subsequent read operation experiences a Cache Miss (commonly paired with Cache-Aside / Read-Aside).

```
                                   WRITE-AROUND EXECUTION FLOW

1.  WRITE PATH (Bypasses Cache)
    [ Client ] ────────────────────(Write Key="msg_9", Val="Text")───────────────────► [ Persistent DB ]
        │
    (Cache is UNTOUCHED or INVALIDATED)

1.  SUBSEQUENT READ PATH (Cache-Aside / Read-Aside)
    [ Client ] ───(Read Key="msg_9")───► [ Cache Layer ]
                                               │
                                               ├───► (Cache Miss!)
                                               │
    [ Client ] ◄──(Fetch & Populate)───────────┴───────────────────────────────────── [ Persistent DB ]
```

#### Key Characteristics & Trade-offs:

- **Zero Cache Pollution**: Prevents flooding the cache with "write-once, read-never" records (e.g., raw audit logs, user registration emails, streaming video segment uploads), ensuring valuable RAM remains reserved for hot read keys.
- **Higher Read Latency Post-Write**: The first read request following a write incurs a Cache Miss, requiring a database read hop ($10 - 50\text{ ms}$) to fetch and populate the key back into the cache layer.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Preventing Race Conditions in Dual-Writes (Cache Invalidation vs. Cache Update)

In distributed architectures using Cache-Aside or Write-Around, developers frequently attempt to write to the database and then manually update the cache (SET cache key = val). This naive approach suffers from severe Concurrent Dual-Write Race Conditions:

```
THE DUAL-WRITE RACE CONDITION (Data Corruption)

Client 1 (Set X = 1) Client 2 (Set X = 2) Cache State DB State
─────────────────────────────────────────────────────────────────────────────────────────────────────────

1. Write DB (X = 1) 2. Write DB (X = 2) 3. Update Cache (X = 2) Cache: X = 2 DB: X = 2
2. Update Cache (X = 1) [STALE!] Cache: X = 1 DB: X = 2

RESULT: Permanent Data Divergence! Cache holds "1", Database holds "2"!
```

#### Architectural Countermeasures:

- **Cache Invalidation Over Cache Update**: Never update a cache value on write (SET). Always invalidatethe key (DEL).
- Why? Deleting the key forces subsequent readers to safely fetch the latest committed value from the database and populate the cache atomically.

#### Delayed Double Delete:

- Write update to Persistent Database.
- Delete Cache Key (DEL key).
- Sleep for $500\text{ ms}$ (allowing ongoing concurrent database read transactions to complete).
- Delete Cache Key (DEL key) a second time to purge any stale reads that were cached during the write window.

#### Designing Resilient Write-Back Architecture (Kafka / Redis Streams):

To eliminate the catastrophic data loss risk of Write-Back caching, modern enterprise architectures replace in-process RAM memory queues with Durable Event Streaming Buffers:

```
                    RESILIENT ENTERPRISE WRITE-BACK PIPELINE

[ App Pods ] ──(1. Write)──► [ Redis Cache (RAM) ]
    │
    └──(2. Stream Write Event)──► [ Apache Kafka / Pulsar (Durable WAL Disk) ]
                   │
                   ▼
    [ Write-Behind Consumer Workers ]
                   │
                   └──(3. Batch/Coalesce Flushes)──► [ Target RDBMS ]
```

- **Dual Write to Stream Buffer**: The application writes the update to the fast Redis cache AND emits a write event payload to an append-only, disk-backed stream buffer (Apache Kafka or Redis Streams).
- **Asynchronous Consumer Workers**: Decoupled background consumer workers read from Kafka consumer groups, perform write coalescing, and issue bulk upserts (INSERT INTO ... ON CONFLICT DO UPDATE) to the relational database.
- **Crash Recovery**: If a worker node or cache instance crashes, Kafka's durable commit log preserves uncommitted writes, allowing new workers to resume flushing without losing state.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
                   CACHE WRITE POLICIES EXECUTION FLOWS
================================================================================

1. WRITE-THROUGH (Synchronous Dual-Write)
--------------------------------------------------------------------------------
[ Client ] ───► [ Cache ] ───(Sync Write)───► [ DB ]
                   │                            │
[ Client ] ◄───(ACK)────────────────────────────┘


2. WRITE-BACK / WRITE-BEHIND (Asynchronous Batching)
--------------------------------------------------------------------------------
[ Client ] ───► [ Cache ] ──► (In-Memory Dirty Queue)
                   │
[ Client ] ◄───(ACK <1ms)
                   │
                   ▼ (Background Daemon Batching)
             [ Worker ] ───(Bulk Upsert)───► [ DB ]


3. WRITE-AROUND (Direct Database Write + Invalidation)
--------------------------------------------------------------------------------
[ Client ] ─────────────────────────────────► [ DB ]
   │                                           │
   └───(Invalidate / DEL Key)───► [ Cache ] ◄──┘
================================================================================
```

---

### 6. Interview Checklist:

- **Define Latency vs. Durability Trade-offs**: Frame the choice clearly: Write-Through prioritizes immediate data safety and zero staleness at the expense of write latency; Write-Back prioritizes sub-millisecond write latency and throughput at the expense of potential data loss during crashes; Write-Around keeps the cache lean and avoids cache pollution for write-heavy, read-rarely data.

- **Detail Write Coalescing**: Explain how Write-Back engines reduce database disk I/O by collapsing multiple sequential updates to the same key into a single consolidated database batch write.

- **Address Dual-Write Race Conditions**: Explain why updating a cache key directly during writes (SET) causes race conditions, and advocate for Cache Invalidation (DEL) or Delayed Double Delete instead.

- **Propose Resilient Write-Back Pipelines**: When asked how to make Write-Back safe against cache node crashes, describe pairing the cache with durable, stream-backed buffers like Apache Kafka or Redis Streams to guarantee write persistence.

#### Formulate a System Choice Matrix:

- **Use Write-Through for**: User account balances, authentication credentials, e-commerce inventory reservation limits.

- **Use Write-Back for**: Social media post like counters, real-time gaming leaderboards, IoT sensor data aggregation.

- **Use Write-Around for**: Video/image file upload processing, user activity log history, historical financial reports.
