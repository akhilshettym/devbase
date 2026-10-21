## Cache Replacement & Eviction Policies (LRU, LFU, Segmented LRU, 2Q, ARC, W-TinyLFU)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a scholar working at a small study desk that can only hold 4 books at a time:

- **LRU (Least Recently Used)**: The scholar keeps pushing books to the right as they consult them. When a 5th book arrives, the scholar sweeps the book sitting furthest on the left off the desk—assuming that if you haven't opened a book in a long time, you won't need it soon.

- **LFU (Least Frequently Used)**: The scholar puts a tally mark on the cover every time a book is opened.When the desk fills up, the scholar throws away the book with the fewest tally marks (e.g., discarding a novel read once, while keeping a dictionary with 500 tally marks).

- **Segmented LRU / 2Q (The Probationary Desk)**: The scholar places all newly delivered books on a small "Probation Desk." Only if a book is requested a second time does it earn a spot on the main study desk.This prevents a delivery worker who drops off 50 unrequested promotional catalogs from sweeping all the scholar's core research books onto the floor.

#### The Core Problem Solved:

- Physical RAM is finite and expensive. When a cache reaches its maximum memory allocation (maxmemory),incoming key-value writes will fail unless the system frees space.

- Cache Eviction Policies dictate the mathematical algorithm used to select which existing items to purge from memory. A naive eviction policy causes severe Cache Scan Pollution and drops the Cache Hit Ratio, forcing traffic down to the persistent database and triggering latency spikes across the entire system architecture.

---

### 2. The Basics (Scratch Level):

#### Core Eviction Metrics:

$$\text{Cache Hit Ratio} = \frac{\text{Total Cache Hits}}{\text{Total Cache Hits} + \text{Total Cache Misses}}$$

A high-performing eviction algorithm maximizes the Cache Hit Ratio by keeping high-value items in memory while minimizing RAM metadata overhead per key.

#### Eviction Policies Comparison Matrix:

| Algorithm                           | `Primary Decision Variable`            | `Time Complexity`     | `Memory Overhead`                | `Scan Resistance` | `Main Vulnerability / Flaw`                                                           | `Ideal Use Cases`                                                         |
| ----------------------------------- | -------------------------------------- | --------------------- | -------------------------------- | ----------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **FIFO (First-In, First-Out)**      | Arrival insertion order                | $O(1)$                | Ultra-Low (Queue pointer)        | None              | Evicts hot items simply because they are old (Belady's Anomaly).                      | Simple queue buffering, time-series windows.                              |
| **LRU (Least Recently Used)**       | Time since last access                 | $O(1)$                | Medium (2 pointers/node)         | Poor              | One-Hit Wonders: A single sequential table scan flushes all hot data.                 | General web session stores, basic key-value caching.                      |
| **LFU (Least Frequently Used)**     | Total access counter                   | $O(1)$ or $O(\log N)$ | High (Counter + Frequency lists) | Good              | Frequency Pollution: Old viral items accumulate high counts and sit in cache forever. | Heavily frequency-skewed workloads (e.g., Zipfian distribution).          |
| **SLRU(Segmented LRU)**             | Recency + Frequency threshold (2 hits) | $O(1)$                | Medium                           | High              | Requires tuning queue partition sizes (Probationary vs. Protected).                   | Database buffer pools (PostgreSQL), disk caches.                          |
| **2Q (Two Queue)**                  | FIFO Probation + LRU Main              | $O(1)$                | Medium                           | High              | Slightly higher pointer manipulation overhead than LRU.                               | High-throughput web servers, OS page caches.                              |
| **ARC(Adaptive Replacement Cache)** | Self-tuning Recency vs. Frequency      | $O(1)$                | High (Ghost caches metadata)     | High              | High metadata memory footprint; historical IBM patent restrictions.                   | ZFS file systems, enterprise storage arrays.                              |
| **W-TinyLFU**                       | Window LRU + Count-Min Sketch + SLRU   | $O(1)$                | Ultra-Low (~1 byte/key)          | Optimal           | Implementation complexity.                                                            | High-performance in-memory application caches (Caffeine, Redis 6+ ideas). |

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. LRU (Least Recently Used) Internals:

Standard LRU is implemented by combining a Hash Map with a Doubly Linked List:

```
                                  LRU INTERNAL DATA STRUCTURE

                          [ Hash Map ] (Key -> Doubly Linked List Node)
                            ├── "k1" ──► Node("k1", "v1")
                            ├── "k2" ──► Node("k2", "v2")
                            └── "k3" ──► Node("k3", "v3")

                            DOUBLY LINKED LIST (Recency Ordering)
           MRU (Most Recently Used)                          LRU (Least Recently Used)
          ┌────────────────────────┐    ┌──────────────────┐    ┌──────────────────┐
   HEAD ◄─┤ Node("k3")             ├◄───┤ Node("k1")       ├◄───┤ Node("k2")       ├─► TAIL
    ──►[Prev: null   | Next: k1] ├───►[Prev: k3                 | Next: k2]───►[Prev: k1           | Next: null]◄──
   └────────────────────────┘ └──────────────────┘ └──────────────────┘
    ▲
    (EVICTION TARGET!)
    Read Operation ($O(1)$):
```

- Look up key in Hash Map ($O(1)$).
- Unlink the matched node from its current position in the Doubly Linked List.
- Splice the node into the Head of the list (marking it as Most Recently Used).

#### Eviction Operation ($O(1)$):

- Remove the node sitting at the Tail of the Doubly Linked List (Least Recently Used).
- Delete its key entry from the Hash Map.
- **The Memory Overhead Problem**: Every key node requires two pointers (prev and next), adding $16\text{ Bytes}$ to $24\text{ Bytes}$ of overhead per key in 64-bit systems.

#### 2. LFU (Least Frequently Used) & Frequency Decay:

Standard LFU assigns an integer counter to every key. To keep operations at $O(1)$, the system uses a Hash Map of Keys pointing into a Doubly Linked List of Frequency Buckets, where each bucket contains a Doubly Linked List of keys sharing that exact frequency count:

```
                               LFU BUCKET ARCHITECTURE

Frequency Bucket [Count = 1] ──► Keys: [ Node("k3") ] ◄──► [ Node("k8") ]
       │
       ▼
Frequency Bucket [Count = 5] ──► Keys: [ Node("k1") ]
       │
       ▼
Frequency Bucket [Count = 99] ──► Keys: [ Node("k2") ]
```

#### The Stale Data Problem (Frequency Pollution):

If key viral_video receives $10,000$ hits at 9:00 AM, its counter jumps to $10,000$. At 10:00 AM, interest drops to zero. However, because its counter is $10,000$, LFU will retain viral_video in memory for days,evicting new, relevant keys that have counters of $1$ or $2$.

#### Solution: Decay Counter Mechanisms

To eliminate stale frequency inflation, engines periodically decay counter values:

- $$\text{Counter}_{\text{decayed}} = \text{Counter}_{\text{current}} \times e^{-\lambda \cdot \Delta t}$$
- Or in simplified implementations (e.g., Redis LFU): decrement all counters across the system when a configurable time window (lfu-decay-time) elapses without access.

#### 3. Segmented LRU (SLRU) & 2Q Mechanics:

Segmented LRU addresses the core vulnerability of LRU: One-Hit Wonders purging hot data. It divides the cache space into two distinct physical segments:

```
                               SEGMENTED LRU (SLRU) PIPELINE

Incoming Read/Write ──► [ Probationary Queue (A1) ] (e.g., 20% Capacity)
        │
(First Access: LRU Eviction)
        │
(Second Access: PROMOTION!)
        ▼
[ Protected Queue (Am) ] (e.g., 80% Capacity)
        │
(Full? Demote LRU Victim back to A1)
```

- **Probationary Queue ($A_1$)**: Holds keys that have been accessed only once. Managed using standard LRU.

- **Protected Queue ($A_m$)**: Holds keys that have been accessed two or more times. Managed using standard LRU.

#### Execution Lifecycle:

- New keys enter the Probationary Queue ($A_1$). If they are never accessed again, they gradually move to the tail of $A_1$ and are evicted.
- If a key in $A_1$ receives a second hit, it is promoted to the Protected Queue ($A_m$).
- If $A_m$ reaches capacity, its LRU victim is not deleted—it is demoted back down to the Probationary Queue ($A_1$).

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Adaptive Replacement Cache (ARC):

Developed by IBM, ARC dynamically balances between Recency (LRU) and Frequency (LFU) in real-time based on workload access patterns.

```
                             ARC DOUBLE-LIST & GHOST CACHE STRUCTURE

◄─ Recency Dominant (Expand p) Frequency Dominant (Shrink p) ─►
┌───────────────────────────────┬───────────────────────────────┐
│ List L1 (Recency)             │ List L2 (Frequency)           │
│ ┌─────────────┬─────────────┐ │ ┌─────────────┬─────────────┐ │
│ │ Top T1      │ Bottom B1   │ │ │ Top T2      │ Bottom B2   │ │
│ │ (In Memory) │ (Ghost KV)  │ │ │ (In Memory) │ (Ghost KV)  │ │
│ └─────────────┴─────────────┘ │ └─────────────┴─────────────┘ │
└───────────────────────────────┴───────────────────────────────┘
                                ▲
                   Target Partition Boundary (p)
```

#### Structure: Maintains two double-linked lists:

- **$L_1$**: Contains keys accessed once recently.
- **$L_2$**: Contains keys accessed at least twice (frequently).
- **Ghost Caches ($B_1$ and $B_2$)**: Both lists are split into an in-memory cached portion ($T_1, T_2$) and a metadata-only Ghost Cache ($B_1, B_2$). Ghost caches store key names/hashes but no values.

#### Dynamic Tuning ($p$):

- If a cache request misses $T_1/T_2$ but hits the Recency Ghost Cache ($B_1$), ARC realizes it evicted a recent item too quickly. It shifts parameter $p$ to expand $T_1$ (favoring Recency).
- If a request hits the Frequency Ghost Cache ($B_2$), ARC shifts $p$ to expand $T_2$ (favoring Frequency).

#### W-TinyLFU (Window TinyLFU):

Used by Java's Caffeine cache framework, W-TinyLFU achieves near-optimal hit ratios while consuming negligible memory.

```
                           W-TINYLFU ARCHITECTURE

     Incoming Key ──► [ Window LRU ] (1% RAM)
                             │
                             ▼
                   (Eviction Candidate)
                             │
                             ▼
                   ┌───────────────────┐
                   │ Count-Min Sketch  │ (4-bit Probabilistic Frequency Estimator)
                   └─────────┬─────────┘
                             │
                     (Admissibility Test)
Compare Frequency(Incoming) vs. Frequency(Probationary Victim)
                             │
             ┌───────────────┴───────────────┐
             ▼                               ▼
        (Incoming Winner)             (Victim Winner)
```

#### Admitted to Main SLRU Incoming Key Discarded:

#### 1. The Count-Min Sketch (Frequency Estimator):

Instead of storing 32-bit integer counters per key, TinyLFU uses a probabilistic Count-Min Sketch (similar to a Bloom Filter):

- Uses 4-bit logarithmic counters per bucket, capping count at $15$.
- Uses multiple hash functions to map key hashes to array indices.
- Keeps memory overhead down to ~8 bits (1 Byte) per key (compared to $24+$ bytes in standard LFU).
- **Reset / Aging**: Every time total additions reach sample size $W$, all counters in the sketch are halved ($\text{Counter} = \lfloor \frac{\text{Counter}}{2} \rfloor$), automatically decaying historical frequency.

#### 2. The Admissibility Window Test

When an item is evicted from the small Window LRU ($1\%$ of total capacity), TinyLFU executes an Admissibility Test before admitting it into the main Segmented LRU ($99\%$ of capacity):

$$\text{If } \text{Freq}(\text{Incoming}) > \text{Freq}(\text{Main SLRU Victim}) \implies \text{Admit Incoming, Evict Main Victim}$$
$$\text{Else } \implies \text{Discard Incoming Key Instantly!}$$
This prevents "one-hit-wonder" sequential scans from ever entering or polluting the main cache segments.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
                   EVICTION MECHANICS COMPARISON
================================================================================

1. STANDARD LRU (Vulnerable to Sequential Scans)
--------------------------------------------------------------------------------
Scan [A, B, C, D, E...] ──► [ Tail: Cold Key 3 ] ──► EVICTED!
                           [ Mid:  Hot Key 2  ] ──► Pushed to Tail -> EVICTED!
                           [ Head: Cold Scan  ] ──► Fills Cache with Garbage!


2. SEGMENTED LRU (SLRU / 2Q - Scan Resistant)
--------------------------------------------------------------------------------
Scan [A, B, C, D, E...] ──► [ Probation Queue (A1) ] ──► EVICTED AT TAIL
                           (Never reaches Protected Queue!)

                           [ Protected Queue (Am) ] ──► HOT KEYS REMAIN SAFE!


3. W-TINYLFU (Admission Controlled Eviction)
--------------------------------------------------------------------------------
Incoming Scan Key ──► [ Window LRU ]
                            │
                            ▼
                   [ Count-Min Sketch ]
                   Freq(Scan Key) = 1  vs  Freq(Main Victim Key) = 42
                            │
                            ▼
                   [ ADMISSION DENIED! ] ──► Scan Key Discarded Instantly!
================================================================================
```

---

### 6. Interview Checklist:

- **Define Cache Scan Pollution**: Explain how a single bulk query (e.g., SELECT \*) sweeps through standard LRU linked lists, evicting all hot, frequently accessed keys, and how SLRU, 2Q, or W-TinyLFUprevent this via probation queues or admission filters.

- **Explain LRU Data Structures ($O(1)$ Operations)**: State clearly that standard LRU uses a Hash Map(for $O(1)$ key lookups) paired with a Doubly Linked List (for $O(1)$ node promotion to head and eviction from tail).

- **Detail LFU Frequency Decay**: Explain that raw LFU suffers from Frequency Pollution (stale historical viral items staying in RAM forever) and explain how counter decay ($\text{Counter} \times e^{-\lambda t}$) solves it.

- **Explain W-TinyLFU / Caffeine Mechanics**: Stand out by describing how W-TinyLFU uses a Count-Min Sketch to track frequency in ~1 byte per key and performs an Admissibility Test comparing incoming item frequency against the probationary victim before permitting entry.

#### Match Production Engine Implementation Choice:

- **Redis**: Uses Approximated LRU/LFU (random sampling of $N$ keys) to avoid pointer overhead.

- **PostgreSQL Buffer Pool**: Uses 2Q / Clock-Sweep variants for disk page eviction.

- **Java Caffeine / Go Ristretto**: Uses W-TinyLFU for maximum hit ratio and near-zero memory metadata footprint.
