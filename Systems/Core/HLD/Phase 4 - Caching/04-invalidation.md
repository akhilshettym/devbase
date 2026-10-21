## Cache Invalidation Strategies

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a daily printed morning newspaper delivered to your front porch:

- **The Invalidation Problem**: The newspaper prints that a baseball game is scheduled for 7:00 PM. At 12:00 PM, a torrential rainstorm cancels the game. Your printed paper on the kitchen table does not automatically rewrite itself—it now contains stale, incorrect information.

- **Time-To-Live / TTL (Subscription Expiration)**: You throw the newspaper in the recycling bin every night at midnight regardless of content, assuming tomorrow morning's paper will bring fresh news.

- **Active Invalidation (Breaking News Alert)**: The newspaper publisher pushes a digital push notification to your phone the exact second the game is canceled, telling you to immediately cross out the schedule in your printed paper.

#### The Core Problem Solved:

- **As Phil Karlton famously stated**: "There are only two hard things in Computer Science: cache invalidation and naming things."

- When underlying source-of-truth data mutates inside a primary storage engine (RDBMS/NoSQL), any cached copies of that data immediately become stale. Returning stale data breaks transactional integrity, displays outdated prices, and corrupts application state.

- Cache Invalidation defines the architectural rules and mechanisms used to evict, update, or declare cached data obsolete, ensuring application reads maintain an acceptable bound of data freshness without destroying database performance.

---

### 2. The Basics (Scratch Level):

#### Passive vs. Active Invalidation:

- **Passive Invalidation (Time-Based)**: The cache layer relies on a pre-set expiration timer (TTL). Data remains in cache until the timer expires, regardless of whether the primary database updated in the interim.

- **Active Invalidation (Event-Based)**: The application or an asynchronous database listener explicitly issues a delete/purge command to the cache the exact moment a write or update succeeds on the primary database.

#### Invalidation Strategies Comparison Matrix:

| Strategy                         | `Execution Mechanics`                                                 | `Data Freshness`                                    | `DB Load Impact`                          | `Implementation Complexity`            | `Primary Use Cases`                                                  |
| -------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------- | ----------------------------------------- | -------------------------------------- | -------------------------------------------------------------------- |
| **TTL Expiration(Time-To-Live)** | Key automatically expires after fixed duration $T$.                   | Bounded Inconsistency(Stale for up to $T$ duration) | Low                                       | Ultra-Low(Native cache engine feature) | News feeds, product catalogs, weather data, session tokens.          |
| **Explicit Direct Purge**        | Application issues DEL key upon DB write.                             | High(Immediate consistency)                         | Low                                       | Low                                    | User profile updates, shopping cart updates, order status changes.   |
| **Key Versioning / Tagging**     | Increments a version namespace token (v1 -> v2).                      | High(Immediate consistency)                         | Very Low                                  | Medium                                 | Bulk collection invalidation (e.g., clearing all posts by user_101). |
| **Stale-While-Revalidate (SWR)** | Serves stale data instantly while asynchronously fetching fresh data. | Eventual(Serves 1 stale read during update window)  | Ultra-Low(Eliminates read latency spikes) | ServMediumerless                       | High-traffic homepages, CDN edge caching, dashboard widgets.         |
| **CDC / Event-Driven**           | DB transaction log tailing (Debezium) emits purge events.             | High (Near-real-time)                               | Very Low                                  | High                                   | Decoupled microservice architectures, multi-region cache sync.       |

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. Explicit Direct Invalidation (Purge vs. Update):

When modifying a record in the database, application code can either update the cache (SET key = new_val) or invalidate the cache (DEL key).

```
RECOMMENDED: EXPLICIT PURGE / INVALIDATION FLOW

[ Application ] ───(1. UPDATE users SET name='Bob' WHERE id=42)───► [ Persistent DB ]
      │                                                                  │
      │                                                                  ▼
      │                                                          (DB Commit Success)
      │                                                                  │
      └───(2. DEL user:42)───────────────────────────────────────► [ Cache Layer ]
```

- **Engineering Best Practice**: Always Invalidate (DEL) rather than Update (SET). Updating a cache key directly introduces severe Dual-Write Race Conditions where concurrent out-of-order writes permanently corrupt the cache state.

#### 2. Key Versioning & Namespacing (O(1) Bulk Invalidation):

Deleting thousands of individual keys matching a pattern (e.g., clearing all cached reviews for a product) using wildcard scans (KEYS \* or SCAN) blocks the single-threaded Redis event loop, causing severe latency spikes.

Key Versioning achieves instantaneous $O(1)$ bulk invalidation using key namespacing:

```
                           KEY VERSIONING ARCHITECTURE

Step 1: Read Global Version Pointer
[ App ] ───(GET user:101:version)───► Returns "v1"

Step 2: Read Composite Cache Key
[ App ] ───(GET user:101:v1:orders)───► Returns Cached Orders Payload

Step 3: BULK INVALIDATE ALL USER ORDERS (O(1) Operation!)
[ App ] ───(INCR user:101:version)───► Version Pointer updated to "v2"
```

- **result**: All old keys matching user:101:v1:\* are rendered instantly inaccessible (orphaned). They sit harmlessly in memory until standard LRU/LFU memory eviction or background TTL sweeps reclaim their memory, avoiding expensive bulk delete sweeps.

#### 3. Stale-While-Revalidate (SWR) / Soft Invalidation:

SWR decouples request latency from database fetch duration by serving cached content slightly past its freshness lifetime while triggering a background async refresh.

```
                            STALE-WHILE-REVALIDATE EXECUTION FLOW

[ Client Request ] ──► [ Cache Engine ]
        │
Is key age within Fresh Window (t < TTL)?
        ├── YES ──► Return Fresh Data Immediately!
        │
        └── NO ──► Is key age within Stale Grace Window (TTL < t < TTL + Grace)?
        │
        ├── YES ──► 1. Return Stale Data to Client Instantly (<1ms)!
        │           2. Spawn Background Worker Thread
        │                         │
        │                         ▼
        │ [ Worker fetches fresh data from DB & updates Cache ]
        │
        └── NO ──► Hard Miss: Block client, fetch from DB, update Cache.
```

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Preventing Race Conditions: Delayed Double Delete:

In a distributed environment using Read-Aside / Write-Around with active invalidation, concurrent read and write operations create a dangerous Read-Write Race Condition:

```
THE READ-WRITE INVALIDATION RACE CONDITION

Client 1 (Reader) Client 2 (Writer) DB State Cache State
────────────────────────────────────────────────────────────────────────────────────────────────────
1. Cache Miss for Key X
2. Read DB (Returns Old Val: "A") 3. Write DB (Set Val: "B") DB = "B" 4. Invalidate Cache (DEL X) Cache Empty
3. Write Cache (Set X = "A") [STALE!] Cache = "A"

RESULT: Permanent Data Corruption! Database holds "B", but Cache holds stale "A"!
Solution: Delayed Double Delete Protocol
```

To guarantee cache consistency without heavy distributed locks:

```
                 DELAYED DOUBLE DELETE EXECUTION PROTOCOL

1. Application writes update to Persistent Database (Val = "B").
2. Application issues FIRST delete to Cache (`DEL X`).
3. Application launches an asynchronous timer to SLEEP for $N$ milliseconds
   (e.g., $N = 500\text{ ms}$, exceeding max expected database read transaction latency).
4. After sleep interval expires, Application issues SECOND delete to Cache (`DEL X`).
   Why it Works: The second delete purges any stale data ("A") written to the cache by concurrent readers that were mid-flight during the primary database write.
```

#### Event-Driven Invalidation via Change Data Capture (CDC):

Application-level cache invalidation tightly couples business logic with caching infrastructure. If an application pod crashes after updating the database but before deleting the cache key, the cache remains permanently stale.

CDC Invalidation uses transaction log tailing to make cache invalidation completely reliable and application-agnostic:

```
                    CDC EVENT-DRIVEN INVALIDATION PIPELINE

[ App Pod ] ──(1. SQL UPDATE)──► [ MySQL / Postgres DB ]
      │
      ▼ (2. Tail Write-Ahead Log / Binlog)
[ Debezium Connector ]
      │
      ▼ (3. Publish Mutation Event)
[ Apache Kafka Topic ]
      │
      ▼ (4. Consume Event)
[ Invalidation Service ]
      │
      └──(5. Execute DEL key)──► [ Redis Cluster ]
```

- **Zero Application Overhead**: Applications simply write to the database.
- **Guaranteed Execution**: Database Write-Ahead Logs (WAL / Binlog) capture every committed state change. Debezium streams mutation events to Apache Kafka.
- **At-Least-Once Delivery**: Dedicated invalidator workers consume Kafka events and issue DELcommands to Redis, guaranteeing invalidation even if application servers crash.

#### Mitigating Cache Stampede (Thundering Herd):

When a ultra-hot cache key (e.g., homepage configuration) expires or is invalidated, thousands of concurrent client requests experience a Cache Miss simultaneously. All thousands of worker threads flood the persistent database at the exact same millisecond, causing database CPU spikes, thread pool starvation, and cascading system outages.

THUNDERING HERD (CACHE STAMPEDE)
Hot Key Expires ──► 10,000 Concurrent Misses ──► 10,000 Parallel DB Queries ──► DB Overload / Crash!
Architectural Solutions:

#### 1. Mutex Locking / Single Flight Pattern:

Only the first request that misses the cache acquires an in-memory distributed mutex lock to recompute the data from the database. All other $9,999$ concurrent requests block, wait for the lock to release, and read the newly populated cache value.

#### 2. Probabilistic Early Expiration (XFetch Algorithm):

Instead of waiting for a key to reach its hard expiration timestamp ($TTL$), readers probabilistically recompute and refresh the cached key before it officially expires based on read frequency and computation cost:

$$\text{Recompute Condition: } -\beta \cdot \delta \cdot \ln(\text{random}()) > \text{TTL} - \text{now}$$
Where:

- **$\delta$**: Time required to compute and fetch the value from the database.
- **$\beta$**: Constant multiplier ($> 0$) adjusting aggressiveness.
- **$\text{random}()$**: Uniform random variable $\in (0, 1]$.

As physical time approaches expiration ($\text{TTL} - \text{now} \to 0$), the probability of a reader triggering an early background refresh approaches $100\%$, guaranteeing the key is silently updated before a hard miss ever occurs.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
           CACHE INVALIDATION & STAMPEDE PROTECTION PIPELINES
================================================================================

1. DELAYED DOUBLE DELETE (Race Condition Protection)
--------------------------------------------------------------------------------
[ App Writer ] ───(1. Write DB: X="B")───► [ RDBMS ]
              ───(2. Delete Cache)──────► [ Redis ] (Key X Removed)
              │
              ├───(3. Sleep 500ms)
              │
              └───(4. Second Delete)────► [ Redis ] (Purges Mid-flight Stale Reads)

2. MUTEX LOCKING / SINGLE FLIGHT (Cache Stampede Protection)
--------------------------------------------------------------------------------
10,000 Concurrent Requests for Expired Key "home_banner"
      │
      ▼
[ Mutex Lock Check ]
      ├──► 1st Request: Acquires Lock ──► Fetches DB ──► Updates Redis ──► Releases Lock
      │
      └──► 9,999 Requests: Lock Denied ──► Pause 50ms ──► Re-read Redis (Hit Fresh Data!)
================================================================================
```

---

### 6. Interview Checklist:

- **Purge (DEL) vs. Update (SET)**: State clearly that active invalidation should always delete keys (DEL) rather than update them (SET) to prevent concurrent write race conditions.

- **Address Bulk Invalidation without Blocking**: Explain how Key Versioning (user:101:v2:orders) achieves $O(1)$ bulk invalidation without using blocking pattern sweeps like KEYS \*.

Explain the Delayed Double Delete Protocol\*\*: Demonstrate senior architecture depth by explaining how sleeping $N\text{ ms}$ and issuing a second DEL purges stale reads introduced by concurrent readers during database writes.

- **Detail CDC-Driven Invalidation**: Describe using database WAL tailing (Debezium + Kafka) to decouple invalidation logic from application code and guarantee at-least-once eviction delivery.

- **Mitigate Cache Stampede**: Present two distinct solutions for the Thundering Herd problem: Mutex Locking / Single Flight (blocking concurrent readers) and Probabilistic Early Expiration (XFetch)(refreshing keys before hard TTL expiration).
