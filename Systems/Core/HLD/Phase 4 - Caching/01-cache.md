## What is Cache? (Redis vs. Memcached)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a master chef running an ultra-busy Michelin-star kitchen:

- **Database (The Walk-in Deep Freezer)**: Located in the basement. It holds every raw ingredient the restaurant owns across thousands of boxes. Walking downstairs, searching for a specific box, unsealing it, and bringing it back to the line takes 10 minutes per request.

- **Cache (The Chef's Countertop Line Prep Station)**: Located directly at the chef's fingertips. It holds pre-chopped, pre-portioned, frequently ordered ingredients (e.g., chopped garlic, sliced butter, stocks). Grabbing an ingredient takes 2 seconds.

- If the prep station runs out of garlic, the kitchen pauses momentarily while a runner fetches a fresh batch from the basement freezer (a Cache Miss), places it on the countertop (a Cache Populate), and serves all subsequent orders instantly from the countertop (a Cache Hit).

#### The Core Problem Solved:

- Persistent disk storage (even modern NVMe SSDs) and complex relational database engines hit fundamental physical bounds:

- **Disk I/O and Network Boundedness**: Disk operations and B-Tree indexing traverses disk pages, taking milliseconds.

- **CPU Computational Cost**: Relational joins, aggregation functions (GROUP BY), and JSON parsing consume significant CPU cycles on every database query.

- Caching stores volatile, pre-computed, or frequently accessed data in high-speed physical Random Access Memory (RAM). By bypassing disk I/O and expensive database query execution paths, caching drops read latencies from tens of milliseconds ($10 - 100\text{ ms}$) down to sub-milliseconds ($< 1\text{ ms}$), enabling systems to scale from thousands to millions of operations per second per node.

---

### 2. The Basics (Scratch Level):

#### The Hardware Latency Spectrum:

To design scalable architectures, every systems engineer must understand the physical latency scale across storage tiers:

$$\text{Latency}_{\text{L1 Cache}} \ll \text{Latency}_{\text{RAM}} \ll \text{Latency}_{\text{NVMe SSD}} \ll \text{Latency}_{\text{RDBMS Query}}$$

```
┌───────────────────────────┬───────────────────────────┬───────────────────────────┐
│ Storage Hierarchy Tier    │ Typical Access Latency    │ Speed Relative to RAM     │
├───────────────────────────┼───────────────────────────┼───────────────────────────┤
│ L1 / L2 CPU Cache         │ 0.5 ns - 7 ns             │ ~100x Faster              │
│ Main Memory (RAM)         │ 100 ns                    │ Baseline (1x)             │
│ NVMe SSD Read             │ 50 μs - 100 μs            │ ~500x Slower              │
│ Same-DC Network Hop       │ 500 μs                    │ ~5,000x Slower            │
│ Complex RDBMS SQL Query   │ 5 ms - 50 ms              │ ~50,000x - 500,000x Slower│
└───────────────────────────┴───────────────────────────┴───────────────────────────┘
```

#### Core Comparison: Redis vs. Memcached:

Both Redis and Memcached are open-source, in-memory, key-value data stores. However, their internal execution architectures and intended use cases differ fundamentally:

| Dimension                       | `Redis`                                                                                                                             | `Memcached`                                                                                                                |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Architecture & Threading**    | Single-threaded Event Loop (I/O multiplexing via epoll/kqueue). Redis 6.0+ uses worker threads for socket network I/O parsing only. | Multi-threaded (Uses libevent with worker threads and coarse/fine-grained locks per slab/bucket).                          |
| **Data Structures**             | Rich native types: Strings, Hashes, Lists, Sets, Sorted Sets (ZSET / SkipLists), Bitmaps, HyperLogLogs, Geospatial, Streams.        | Simple Key-Value: Plain strings, raw binary payloads, or serialized blobs up to 1 MB.                                      |
| **Persistence**                 | Full Support: RDB point-in-time snapshots, AOF append-only logs, and Hybrid modes.                                                  | None: In-memory only. If the process crashes or restarts, all data vanishes instantly.                                     |
| **Memory Allocation Engine**    | Custom memory allocator (jemalloc or tcmalloc). Dynamic allocation per object.                                                      | Slab Allocator: Pre-allocates memory into fixed-size chunks to completely eliminate external memory fragmentation.         |
| **Cluster & High Availability** | Built-in: Redis Sentinel (automatic master failover) and Redis Cluster (native hash-slot sharding across 16,384 slots).             | External / Client-Side: No built-in clustering. Clients handle distribution using Consistent Hashing (e.g., libmemcached). |
| **Pub/Sub & Messaging**         | Supported natively: Pub/Sub channels, blocking list pops (BLPOP), Streams with Consumer Groups.                                     | Not Supported.                                                                                                             |
| **Extensibility & Scripting**   | Supported: Atomically executed Lua scripts, Redis Functions, and C/Rust Modules (RedisBloom, RedisJSON).                            | Not Supported.                                                                                                             |

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. Redis Internal Architecture:

```
   REDIS EVENT LOOP ENGINE

[ Socket Client 1 ] ──┐
[ Socket Client 2 ] ──┼─► [ I/O Multiplexer (epoll) ] ──► [ Event Queue ] ──► [ Single-Threaded Execution Engine ]
[ Socket Client N ] ──┘ │
                        ├─► In-Memory Hashtable
                        ├─► SDS / SkipList / ZipList
                        └─► AOF Buffer / RDB Fork
```

- The Single-Threaded Event Loop (Reactor Pattern)
- Redis executes all data manipulation commands inside a single main thread.

#### Why Single-Threaded?

- **Zero Mutex/Lock Overhead**: No race conditions, deadlocks, or CPU thread context-switching overhead on internal data structures.
- **Memory Bandwidth Bound**: Redis performance is bounded by CPU memory bus bandwidth and network throughput, not raw CPU processing power.
- **Atomic Operations**: Every command execution (e.g., INCR, HSET, ZADD) is inherently atomic without requiring explicit database locks.
- **I/O Multiplexing (epoll / kqueue)**: The single thread monitors thousands of open client sockets simultaneously using non-blocking OS system calls. It fetches incoming command packets, queues them, executes them sequentially in memory, and writes responses back to socket buffers.

#### Redis Data Structure Internals:

- **Simple Dynamic String (SDS)**: Replaces standard C char\* arrays. Tracks string length in $O(1)$ time, prevents buffer overflows, and guarantees binary safety (can store images, Protobufs, or serialized objects containing \0 bytes).
- **Hashtable (dict)**: Uses incremental rehashing. When a hashtable resizes, Redis allocates two tables (ht[0] and ht[1]) and gradually migrates keys over subsequent client operations to avoid blocking the main thread.
- **Sorted Set (ZSET)**: Combines a HashTable (for $O(1)$ element-to-score lookups) with a SkipList (for $O(\log N)$ insertions, removals, and range queries like ZRANGEBYSCORE).

#### Redis Persistence Mechanics:

- **RDB (Redis Database File)**: Point-in-time binary snapshot saved to disk at configured intervals.
- **Under the Hood**: Uses the OS fork() system call to create a child process. The child inherits the memory space via OS Copy-On-Write (COW), allowing it to stream data to disk while the main parent process continues serving live client traffic uninterrupted.
- **AOF (Append-Only File)**: Logs every state-modifying command received by the server to an append-only log file.
- **Fsync Policies**: fsync=always (slowest, zero data loss), fsync=everysec (recommended balance: max 1 second of lost writes on crash), fsync=no (delegates flushing to the OS kernel).
- **Hybrid Persistence (Redis 4.0+)**: Produces AOF files that combine a full RDB snapshot base with an incremental AOF log tail for fast server boot recovery.

#### 2. Memcached Internal Architecture:

```
   MEMCACHED SLAB ALLOCATOR ENGINE

[ 1 MB Page 1 ] [ 1 MB Page 2 ] [ 1 MB Page N ]
┌─────────────────────────┐ ┌─────────────────────────┐ ┌─────────────────────────┐
│ Slab Class 1 (64 Bytes) │ │ Slab Class 2 (128 Bytes)│ │ Slab Class 3 (256 Bytes)│
│ ┌────┬────┬────┬────┐   │ │ ┌──────┬──────┬──────┐  │ │ ┌─────────┬─────────┐   │
│ │ 64 │ 64 │ 64 │ 64 │...│ │ │ 128 │ 128 │ 128    │..│ │ │ 256     │ 256     │...│
│ └────┴────┴────┴────┘   │ │ └──────┴──────┴──────┘  │ │ └─────────┴─────────┘   │
└─────────────────────────┘ └─────────────────────────┘ └─────────────────────────┘
```

#### Multi-Threaded Execution Model:

Memcached uses a master thread that listens for incoming TCP/UDP connections via libevent and dispatches new socket file descriptors to worker threads in a round-robin fashion. Each worker thread processes commands for its assigned connections independently using thread-safe locking mechanisms.

#### The Slab Allocator (Eliminating Memory Fragmentation):

Standard memory allocators (malloc/free) cause severe external memory fragmentation when millions of key-value pairs of varying sizes are allocated and freed continuously, eventually causing the OS kernel to run out of contiguous RAM pages.

Memcached solves this by pre-allocating large $1\text{ MB}$ pages from the OS and subdividing them into fixed-size Slab Classes:

1. **Slab Class 1**: Contains chunks of size $64\text{ Bytes}$.
2. **Slab Class 2**: Chunks of size $80\text{ Bytes}$ (scaled by a growth factor, e.g., $1.25$).
3. **Slab Class 3**: Chunks of size $100\text{ Bytes}$.

- When a key-value item of size $72\text{ Bytes}$ is stored:
- Memcached locates the smallest slab class that can hold the item (Slab Class 2: $80\text{ Bytes}$).
- It places the item into an open $80\text{-Byte}$ chunk slot.

- **Trade-off**: Accepts minor internal fragmentation ($8\text{ Bytes}$ wasted inside the chunk) to completely guarantee zero external memory fragmentation and instantaneous $O(1)$ memory allocation times.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Memory Eviction Algorithms:

When cache memory fills to capacity (maxmemory), the system must execute an eviction policy to free space for incoming keys:

```
                           EVICITON POLICIES COMPARISON

Policy Mechanics Best Used For
────────────────────────────────────────────────────────────────────────────────────────────
noeviction Returns OOM error on writes. Strict state data / DB usage
allkeys-lru Evicts Least Recently Used key. Standard web session caching
allkeys-lfu Evicts Least Frequently Used key. Frequency-skewed read workloads
volatile-lru/lfu Evicts LRU/LFU among keys with TTL. Hybrid cache/persistent stores
allkeys-random Evicts a random key. Flat uniform access distributions
```

#### Redis Approximated LRU:

Standard LRU requires maintaining a doubly-linked list of all keys in memory, updating pointers on every single read operation. This consumes significant RAM metadata overhead ($16 - 24\text{ Bytes}$ per key) and degrades throughput.

#### Redis uses an Approximated LRU Algorithm:

Every Redis object contains a 24-bit idle timestamp field in its header.

When memory limits are hit, Redis does not sort all keys. Instead, it randomly samples $N$ keys (e.g., $N = 5$ or $10$).

It evaluates the idle timestamps of the sampled keys and evicts the oldest key among the sample set.

At $N = 10$, Approximated LRU performance is virtually indistinguishable from true exact LRU, while using zero extra memory pointer overhead.

#### LFU (Least Frequently Used) & The Morris Counter:

Redis LFU uses an 8-bit logarithmic access counter combined with a time decay period:

$$\text{Counter Increment Probability} \propto \frac{1}{\text{Current Counter} \times \text{lfu\_log\_factor} + 1}$$
Because the counter is logarithmic, a single 8-bit field can track up to 1 million access operations per key without overflowing RAM headers.

#### Memory Fragmentation & Operations:

Over time, Redis allocations managed by jemalloc can fragment memory across OS pages.

#### Memory Fragmentation Ratio:

$$\text{Fragmentation Ratio} = \frac{\text{used\_memory\_rss}}{\text{used\_memory}}$$
Ratio $> 1.5$: High memory fragmentation. The OS has allocated $50\%$ more physical memory (RSS) than the actual data inside Redis.

- **Remedy**: Enable active defragmentation (activedefrag yes), allowing Redis to copy fragmented memory payloads into contiguous allocations on the fly during idle event loop cycles.
- **Ratio $< 1.0$**: Physical RAM is exhausted, and the OS has begun swapping Redis memory pages to disk.
- **Consequence**: Latencies explode from microseconds to milliseconds ($1000\times$ slowdown). Immediate operational intervention required.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
         REDIS SINGLE-THREADED vs MEMCACHED MULTI-THREADED
================================================================================

1. REDIS ARCHITECTURE (Single-Threaded Multiplexed Event Loop)
--------------------------------------------------------------------------------
[ Client A ] ──┐
[ Client B ] ──┼──► [ epoll / kqueue Multiplexer ]
[ Client C ] ──┘                │
                               ▼
                  [ Non-Blocking Event Queue ]
                               │
                               ▼
                [ Single Thread Execution Engine ]
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
    [ Hashtable ]         [ SkipList ]         [ SDS Strings ]
         │
         └──► (Optional Background Threads for AOF fsync / Lazy Freeing)


2. MEMCACHED ARCHITECTURE (Multi-Threaded Slab Allocation)
--------------------------------------------------------------------------------
[ Client A ] ──┐
[ Client B ] ──┼──► [ Master Listener Thread (libevent) ]
[ Client C ] ──┘                │
              ┌────────────────┼────────────────┐ (Dispatches Sockets)
              ▼                ▼                ▼
       [ Worker 1 ]      [ Worker 2 ]      [ Worker 3 ]
              │                │                │
              └────────────────┼────────────────┘
                               ▼
                   [ Slab Allocation Engine ]
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
    [ 64B Chunks ]       [ 128B Chunks ]      [ 256B Chunks ]
================================================================================
```

---

### 6. Interview Checklist:

- **Quantify Speed Gains**: State clearly that caching moves operations from disk/database execution ($5\text{ ms} - 50\text{ ms}$) to physical RAM ($< 1\text{ ms}$), providing $100\times$ latency reductions.

- **Explain the Redis Single-Threaded Choice**: Articulate why Redis uses a single-threaded event loop (eliminates lock contention, thread context-switching, and race conditions; operations are CPU memory bus bound). Mention that Redis 6.0+ uses worker threads exclusively for multi-threaded socket network I/O parsing.

- **Detail Memcached's Slab Allocator**: Explain how Memcached uses fixed-size slab class chunk pre-allocation to eliminate external memory fragmentation at the cost of minor internal fragmentation.

- **Differentiate Redis Persistence Options**: Contrast RDB (fast point-in-time snapshotting via OS fork()Copy-On-Write) with AOF (append-only log with configurable fsync durability).

- **Explain Approximated LRU**: Stand out by explaining that Redis avoids true LRU linked lists to save memory, instead randomly sampling $N$ keys and evicting the oldest candidate in the sample set.

#### Formulate a Concrete Architectural Choice Framework:

- **Select Memcached for**: Simple, high-throughput, multi-threaded key-value string caching where items exceed $1\text{ MB}$, zero persistence is required, and client-side horizontal sharding is sufficient.

- **Select Redis for**: Complex data structures (ZSET, Hashes, Lists), geospatial queries, atomic operations, built-in high availability (Sentinel/Cluster), Pub/Sub messaging, or persistent state stores.
