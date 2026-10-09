## In-memory DBs

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine working at an executive desk:

- **On-Disk Database (PostgreSQL / MySQL)**: To answer every single customer question, you must open a heavy metal desk drawer, locate a paper folder, unfold it, read the line, and fold it back up. Even with fast drives (NVMe SSDs), you still spend time navigating drawer slides and mechanical boundaries.

- **In-Memory Database (Redis / Memcached / VoltDB)**: Every piece of information is written on neon sticky notes spread out directly on top of your glass desk right in front of you. You look down, read, and write instantly without opening a single drawer.

#### The Core Problem Solved:

- Traditional databases spend up to 80% of their query execution cycle managing disk I/O abstractions: translating disk pages ($8\text{ KB} - 16\text{ KB}$) into RAM buffer pools, handling OS kernel page faults, acquiring B-Tree page locks, and serializing binary data across bus controllers.

- In-Memory Databases (IMDBs) eliminate disk I/O from the primary read/write execution path. Data structures are laid out directly in volatile main memory (DRAM), reducing access latencies from milliseconds ($1\text{ms} - 10\text{ms}$) or microseconds ($100\mu\text{s}$) down to nanoseconds ($10\text{ns} - 100\text{ns}$).

---

### 2. The Basics (Scratch Level):

- **Taxonomy**: Cache vs. In-Memory Database vs. On-Disk Database

```
                   [ APPLICATION LAYER ]
                 /           │           \
                /            │            \
                ▼            ▼             ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Transient Cache │ │ In-Memory DB    │ │ On-Disk RDBMS   │
│ (Memcached)     │ │ (Redis / KeyDB) │ │ (PostgreSQL)    │
├─────────────────┤ ├─────────────────┤ ├─────────────────┤
│ • RAM Only      │ │ • RAM Primary   │ │ • Disk Primary  │
│ • Volatile      │ │ • Persistence   │ │ • RAM Cache     │
│ • Key-Value     │ │ • Complex Types │ │ • B+Tree Pages  │
│ • No Durability │ │ • Async WAL/RDB │ │ • Strict ACID   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

| Feature                   | `Transient Cache (e.g., Memcached)`  | `In-Memory Database (e.g., Redis, Dragonfly)`                 | `On-Disk Database (e.g., PostgreSQL, MySQL)`               |
| ------------------------- | ------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------------------- |
| **Primary Data Location** | RAM                                  | RAM                                                           | Disk (NVMe / SSD / HDD)                                    |
| **Data Structures**       | Strings / Raw Bytes                  | Hashes, Lists, Sets, Sorted Sets, Streams, Bitmaps, Graphs    | Tables (Rows & Columns), B+Trees, Documents                |
| **Persistence Options**   | None (Data lost on restart)          | Snapshots (RDB), Append Logs (AOF), Replication               | Write-Ahead Log (WAL) + Disk Data Pages                    |
| **Latency Profile**       | Sub-millisecond ($< 500\mu\text{s}$) | Sub-millisecond ($100\mu\text{s} - 500\mu\text{s}$)           | Millisecond ($1\text{ms} - 50\text{ms}$)                   |
| **Primary System Role**   | Read acceleration buffer             | Primary store for real-time counters, sessions, leaderboards. | Canonical system of record for billing and business state. |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Memory Access Latency Hierarchy:

The underlying reason in-memory architectures outperform disk-backed stores comes down to physics and hardware bus architecture:

$$\text{L1 Cache } (1\text{ ns}) \ll \text{Main Memory DRAM } (100\text{ ns}) \ll \text{NVMe PCIe SSD } (100,000\text{ ns}) \ll \text{SATA HDD } (10,000,000\text{ ns})$$

```
HARDWARE BUS LATENCY COMPARISON
┌─────────────────────────┬───────────────────────────┬─────────────────────────┐
│ Storage Layer           │ Physical Access Time      │ Relative Scale          │
├─────────────────────────┼───────────────────────────┼─────────────────────────┤
│ L1 CPU Cache            │ ~1 ns                     │ 1 Second                │
│ Main RAM (DRAM)         │ ~100 ns                   │ ~1.6 Minutes            │
│ NVMe SSD (Flash Memory) │ ~100,000 ns (100 μs)      │ ~1.1 Days               │
│ Standard Mechanical HDD │ ~10,000,000 ns (10 ms)    │ ~3.8 Months             │
└─────────────────────────┴───────────────────────────┴─────────────────────────┘
```

Because RAM allows uniform direct byte-addressable access through CPU memory channels without device controller protocol handshakes (SATA/NVMe), hardware bottlenecks shift entirely from disk bandwidth to CPU cache locality and memory bus bandwidth.

#### Persistence Mechanics: How IMDBs Survive Power Loss:

Because RAM is volatile, an in-memory database must implement explicit persistence mechanisms to survive hardware reboots:

```
                         [ Incoming Mutating Query ]
                                      │
                                      ▼
                        [ Active In-Memory Engine (RAM) ]
                                      │
        ┌─────────────────────────────┴─────────────────────────────┐
        ▼                                                           ▼
[ 1. Point-in-Time Snapshot (RDB) ]                [ 2. Append-Only Log (AOF) ]
- Triggers OS fork() (Copy-On-Write)               - Appends write commands to disk buffer
- Dumps compact binary state to disk               - fsync modes: always, everysec, or no
- Fast recovery boot times                         - Slow recovery boot times (Replay)
```

#### Point-in-Time Snapshotting (e.g., Redis RDB):

The engine calls the OS system function fork() to create a child process.

- **Uses Copy-On-Write (COW) kernel mechanics**: the child process reads a static point-in-time memory view and dumps a compressed binary payload to disk while the parent continues serving live traffic.

- **Trade-off**: Fast boot recovery times, but risks losing minutes of data inserted between snapshot intervals.

##### Append-Only File Logging (e.g., Redis AOF / Write-Ahead Log):

- Logs every single mutating write command (e.g., SET, HINCRBY) to a sequential disk log file.

- **Flush Strategie**s: fsync() on every single write (safest, lowest throughput), fsync() every 1 second (default balance), or managed by the OS buffer.
- **AOF Rewriting**: Periodically compresses the log file in the background by converting historical incremental mutations into minimal modern assignment state.

#### Threading & Concurrency Execution Models:

#### 1. Single-Threaded Event Loop (Classic Redis Architecture):

Executes all incoming commands sequentially on a single thread using non-blocking I/O multiplexing (epoll on Linux, kqueue on macOS).

- **Why it works**: Eliminates CPU thread context switching, race conditions, mutex contention, and lock overhead entirely.
- **Guarantee**: $O(1)$ operations execute with absolute Atomic Isolation without requiring multi-version concurrency control (MVCC) or two-phase locking (2PL).

#### 2. Multi-Threaded Shared-Nothing / Lock-Free (KeyDB, Dragonfly, Aerospike):

- Utilizes modern multi-core processors by assigning independent event loops per core (using Linux io_uring or thread-per-core architectures).
- Keyspace is partitioned (sharded) internally across CPU cores to avoid shared memory lock contention across L3 CPU caches.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Specialized Memory-Efficient Data Structures:

Because RAM costs significantly more per gigabyte than flash storage, IMDBs optimize internal structures to maximize data packing density:

#### SkipLists (Used for Sorted Sets):

A probabilistic alternative to balanced trees. Uses multi-level linked lists with $O(\log N)$ search and insertion costs, optimizing pointer traversals without requiring complex tree-rebalancing locks.

```
Level 3: [1] ───────────────────────────► [10] ──────────────────────► NULL
Level 2: [1] ─────────────► [5] ────────► [10] ─────────► [15] ───────► NULL
Level 1: [1] ──► [3] ─────► [5] ──► [7] ─► [10] ──► [12] ─► [15] ──► [20] ─► NULL
```

#### ZipLists / Listpacks (Memory Compression):

- When a Hash or List contains a small number of entries, the engine avoids overhead by allocating a single, contiguous memory buffer. Key-value pairs are encoded sequentially without pointers, converting random memory reads into hyper-fast CPU cache-line prefetching scans.

#### Adaptive Radix Trees (ART):

- Used for primary key lookups, adapting child node sizes dynamically based on key length density to minimize pointer overhead.

##### Memory Eviction Policies & Fragmentation:

- When memory fills up (maxmemory ceiling reached), IMDBs act as write-rejecting databases or automatic eviction caches using configured policies:

- **Approximated LRU (Least Recently Used)**: True LRU requires maintaining expensive double-linked list pointers across all keys. Redis instead samples $K$ random keys (e.g., $K=5$) and evicts the oldest key among the sample set, achieving near-perfect LRU accuracy with zero memory pointer overhead.

- **LFU (Least Frequently Used)**: Tracks key access frequency using a logarithmic decay counter embedded inside key header metadata.

- **Memory Fragmentation Management**: Deallocating dynamic keys can create "holes" in physical memory pages (external fragmentation). Modern IMDBs integrate custom allocators (jemalloc or tcmalloc) alongside active background defragmentation threads that copy scattered objects into contiguous memory blocks.

#### Hybrid In-Memory Architectures (Tiered Memory / Redis on Flash):

To bypass strict DRAM capacity limits, modern architectures combine fast RAM with high-speed NVMe flash arrays:

- **Hot Data (RAM)**: Active, high-frequency keys reside directly in DRAM.
- **Warm Data (NVMe/PMEM)**: Less frequently accessed keys or large payload values automatically page out to NVMe SSDs or Persistent Memory (Intel Optane / CXL memory expansion modules) using unified pointer space abstractions.

---

### 5. Text-Based Architecture Diagram:

```
===============================================================
        IN-MEMORY DATABASE ARCHITECTURE & I/O FLOW
===============================================================

            [ Client Application Connections ]
                            │
                            ▼
        ┌─────────────────────────────────────────┐
        │ I/O Multiplexer (epoll / io_uring)      │
        └───────────────────┬─────────────────────┘
                            │
                            ▼
        ┌─────────────────────────────────────────┐
        │ Single-Threaded Execution Engine        │
        │ (Atomic Command Execution)              │
        └───┬───────────────────────────┬─────────┘
            │                           │
            ▼                           ▼
┌───────────────────────┐   ┌────────────────────────────────┐
│ DRAM Data Structures  │   │ Command Logging Engine         │
│                       │   │                                │
│ • Dict (Hash Table)   │   │ [ AOF Buffer ]                 │
│ • SkipList (ZSet)     │   │       │                        │
│ • Listpack (Compact)  │   │       ▼ (fsync interval)       │
│ • Radix Tree          │   │ [ appendonly.aof (NVMe Disk) ] │
└───────────────────────┘   └────────────────────────────────┘
            │
            ▼ (Background Copy-On-Write / fork())
┌─────────────────────────────────────────────────────────────┐
│ Child Process Dump -> [ dump.rdb (Snapshot File) ]          │
===============================================================
```

---

### 6. Interview Checklist:

- **Clarify Cache vs. Database Intent**: Immediately state that IMDBs (e.g., Redis) can act as both transient caches and durable primary stores depending on snapshot/AOF configurations, data structures used, and eviction policy settings.

- **Explain the Single-Threaded Advantage**: When discussing classic Redis architecture, explain that its single-threaded event loop eliminates thread context-switching and locks, providing built-in atomic primitive commands (INCR, HSETNX, LPUSH) for concurrency management.

- **Detail Memory Management Trade-offs**: Show senior system design depth by explaining Memory Fragmentation and how engines mitigate memory overhead via ZipLists/Listpacks, approximated sampling LRU, and custom allocators (jemalloc).

- **Discuss Durability Trade-offs (RDB vs AOF)**: Frame persistence choice clearly: RDB snapshots yield ultra-fast boot recovery times but risk incremental data loss; AOF logs ensure near-zero data loss at the cost of disk I/O background pressure and longer restart replay times.
