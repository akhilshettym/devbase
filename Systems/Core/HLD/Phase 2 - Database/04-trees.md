## B-Trees vs LSM Trees

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine managing document updates in an enterprise filing office:

- **B-Tree (In-Place File Organizer)**: You maintain a rigid, perfectly ordered filing cabinet. When a updated page arrives for Employee #8,412, you walk directly to Cabinet 8, open Page Slot 412, erase the old text, and write the new data directly in place. Reading is instant because every document lives in exactly one predictable location, but every write requires walking to random drawers across the building (Random Disk I/O).

- **LSM-Tree (Log-Structured Merge-Tree - Inbox Aggregator)**: You drop every incoming page directly onto a fast desk tray sequentially as it arrives. When the desk tray gets full, you neatly sort those pages, staple them into a bound booklet, and place it on a storage shelf (Immutable SSTable). In the background, an assistant continuously merges older booklets on the shelf into master catalog binders (Compaction). Writes are lightning fast because you just drop pages on the desk, but reads might require checking the desk tray plus multiple booklets on the shelf to find the newest update.

#### The Core Problem Solved:

- Storage devices (HDDs and SSDs/NVMe) handle sequential I/O orders of magnitude faster than random I/O. On flash storage (SSDs), random in-place updates trigger heavy internal garbage collection, causing device wear and latency spikes.

- B-Trees prioritize read performance and immediate consistency through in-place updates, paying a heavy write penalty under random write workloads.

- LSM-Trees convert random writes into high-speed sequential batch appends, trading away cheap reads and extra disk space to achieve massive write throughput and optimal flash hardware longevity.

---

### 2. The Basics (Scratch Level):

Structural Comparison Matrix

| Dimension                         | `B/B+ Tree Engine`                                                                  | `LSM-Tree (Log-Structured Merge-Tree) Engine`                            |
| --------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Data Mutation Model**           | In-Place Updates (Overwrites existing disk pages)                                   | Append-Only / Immutable (Writes new versions sequentially)               |
| **Primary Workload Optimization** | Read-Heavy / Low Latency Point & Range Reads                                        | Write-Heavy / High-Throughput Ingestion & Time-Series                    |
| **Disk I/O Pattern**              | High Random Read & Write I/O                                                        | High Sequential Write I/O; Background Compaction I/O                     |
| **Space Amplification ($SA$)**    | Low (Minimal duplicate row versions)                                                | Medium to High (Holds old deleted/updated key versions until compaction) |
| **Write Amplification ($WA$)**    | High for random writes (Modifying $100\text{ bytes}$ rewrites a $16\text{ KB}$page) | Low for initial writes; Medium/High during background compaction         |
| **Read Amplification ($RA$)**     | Low ($O(\log_B N)$ page reads)                                                      | Higher (May check MemTable + multiple SSTable files on disk)             |
| **Hardware Alignment**            | Best on low-latency random access memory (RAM/Optane)                               | Optimized for NAND Flash SSDs, NVMe, and HDDs                            |
| **Production Examples**           | PostgreSQL, MySQL (InnoDB), SQLite, Oracle                                          | RocksDB, Apache Cassandra, ScyllaDB, LevelDB, CockroachDB                |

---

### 3. Deep Dive & Architecture (Mid Level):

#### B-Tree In-Place Storage Engine Mechanics:

A traditional B+Tree stores data in fixed-size blocks (typically $8\text{ KB} - 16\text{ KB}$ pages).

```
     [ Page 101 (Root) ]
           /      \
 [ Page 204 ]     [ Page 205 ]
  (Internal)      (Internal)
      /  \            /     \
[Leaf A] [Leaf B] [Leaf C] [Leaf D] <── Physical Disk Pages modified IN-PLACE
```

- **Random Write Overhead**: To update key 8412, the engine traverses the tree to locate Leaf C, loads Page 302 into RAM, modifies the memory block, and writes the entire $16\text{ KB}$ page back to disk. Updating a single $50\text{ byte}$ column forces a full $16\text{ KB}$ disk write, resulting in severe Write Amplification.

- **Page Splits & Locking**: If Page 302 is full, inserting a key triggers a Page Split, allocating a new disk page, rebalancing parent nodes, and acquiring heavy exclusive latch locks across index branches.

#### LSM-Tree Write and Read Pipeline:

An LSM-Tree architecture decouples incoming write operations from persistent disk organization across three main layers:

```
                 [ Incoming Write Query ]
                            │
           ┌────────────────┴────────────────┐
           ▼                                 ▼
    [ Write-Ahead Log (WAL) ]       [ MemTable (RAM) ]
    (Sequential Disk Recovery)    (SkipList / Concurrent Red-Black Tree)
                        │
            (Flush when MemTable Full)
                        │
                        ▼
        ┌────────────────────────────────┐
        │ Level 0 SSTables (Disk)        │
        │ [SST 1] [SST 2] [SST 3]        │ (Keys can overlap across L0 files)
        └───────────────┬────────────────┘
                        │
            (Background Compaction)
                        │
                        ▼
        ┌────────────────────────────────┐
        │ Level 1 SSTables (Disk)        │
        │ [SST A] [SST B] [SST C]        │ (Strictly non-overlapping keys)
        └────────────────────────────────┘
```

#### Write Path (Sequential Append):

The write is logged to an append-only Write-Ahead Log (WAL) on disk for crash durability.

- The payload is simultaneously inserted into an in-memory sorted structure called the MemTable(typically implemented as a Concurrent SkipList).
- The write returns immediately ($O(1)$ RAM insertion + sequential disk append). No disk seeks or in-place reads take place.

##### SSTable Flushes:

- When the MemTable reaches a threshold (e.g., $64\text{ MB}$), it becomes immutable and is flushed to disk as a Sorted String Table (SSTable) file at Level 0 ($L_0$).
- Data inside an SSTable is strictly sorted by key.

#### Compaction Strategies (Cleaning Up Old Data):

Because updates and deletions simply append newer key versions or Tombstones (deletion markers), disk space bloats and read speeds decay. LSM engines execute continuous background Compaction to merge SSTables, discard overwritten/deleted keys, and push data down to deeper levels:

- **Size-Tiered Compaction Strategy (STCS)**: Merges SSTables of similar sizes once a file-count threshold is reached.
- **Pros**: Low write amplification during compaction; ultra-fast write throughput.
- **Cons**: High space amplification (requires up to 50% free disk headroom for temporary merge operations); bad for range reads.

- **Leveled Compaction Strategy (LCS - RocksDB Default)** Disk storage is divided into levels ($L_0, L_1, L_2, \dots$), where each level's total capacity is $10\times$ larger than the previous (e.g., $L_1 = 10\text{ MB}, L_2 = 100\text{ MB}, L_3 = 1\text{ GB}$).

Keys in $L_1$ and beyond are guaranteed strictly non-overlapping across SSTables within that level.

- **Pros**: Low read amplification ($O(1)$ file check per level); low space amplification.
- **Cons**: High write amplification during multi-level merge operations.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### The RUM Conjecture (Read, Update, Memory/Space Trade-offs):

The RUM Conjecture states that a database storage engine can optimize at most two of the following three overheads:

```
                          Read Amplification (RA)
                                /\
                               /  \
                              /    \
                             /  B+  \
                            /  TREE  \
                           /          \
                          /  LSM-TREE  \
                         /              \
Space Amplification (SA) ────────────────── Write Amplification (WA)
```

$$\text{Read Amplification } (RA) = \frac{\text{Bytes Read from Disk}}{\text{Bytes Requested by Application}}$$
$$\text{Write Amplification } (WA) = \frac{\text{Bytes Written to Disk Hardware}}{\text{Bytes Written by Application}}$$
$$\text{Space Amplification } (SA) = \frac{\text{Total Disk Space Allocated}}{\text{Uncompressed User Data Payload}}$$

- **B-Tree Optimization**: Optimizes for $RA$ and $SA$ at the expense of high $WA$ under random write pressure.
- **LSM-Tree Optimization**: Optimizes for $WA$ and write latency at the expense of higher $RA$ and $SA$.

#### How LSM Engines Mitigate Read Amplification:

Because a key can reside in the MemTable or any active SSTable across multiple levels, an unoptimized LSM point read would require scanning dozens of disk files. LSM engines apply two critical techniques:

##### 1. In-Memory Bloom Filters:

- Every SSTable carries an in-memory Bloom Filter (a space-efficient probabilistic data structure).
- Before opening an SSTable file on disk, the engine queries its Bloom Filter.
- If the Bloom Filter returns false, the key definitely does not exist in that SSTable, bypassing disk I/O entirely ($O(1)$ memory check).
- If it returns true, the key might exist, triggering a targeted disk block read.

##### 2. SSTable Block Indexes & Fence Pointers

- SSTables store key ranges in trailer metadata indexes. The engine reads the SSTable block index to jump straight to the exact $4\text{ KB}$ data block containing the key without scanning the entire file.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
                    B-TREE vs LSM-TREE MUTATION DYNAMICS
================================================================================

1. B-TREE: IN-PLACE MUTATION (Random Access)
--------------------------------------------------------------------------------
[ Write: Set Key "user_42" = "Active" ]
                │
                ▼
    [ Traverses B-Tree Index ]
                │
                ▼
┌─────────────────────────────────────────────────────────┐
│ Disk Page 804 (16 KB)                                   │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ [key: "user_41"] [key: "user_42" (OVERWRITTEN!)]    │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
* Forces immediate or dirty-buffered 16 KB Page write for a small value change.


2. LSM-TREE: APPEND-ONLY MUTATION (Sequential Access)
--------------------------------------------------------------------------------
[ Write: Set Key "user_42" = "Active" ]
                │
                ├───────────────────────────────┐
                ▼                               ▼
    [ Append to WAL (Disk) ]        [ Insert into MemTable (RAM) ]
    (Sequential I/O append)         (Sorted SkipList update)
                │                               │
                │                               ▼
                │                   [ MemTable Flushes to L0 ]
                │                               │
                ▼                               ▼
   [ WAL Truncated ]             ┌─────────────────────────────┐
                                 │ SSTable File 109 (Disk)     │
                                 │ ["user_42" = "Active"]      │
                                 └─────────────────────────────┘
* Write returns in sub-millisecond time. Compaction merges duplicate versions later.
================================================================================
```

---

### 6. Interview Checklist:

- **Lead with I/O Patterns**: State that B-Trees perform in-place updates via random page reads/writes, whereas LSM-Trees perform append-only writes via sequential I/O, converting random writes into sorted batch flushes.

- **Explain the LSM Write Path Components**: Walk through the complete sequence: incoming query $\rightarrow$ Write-Ahead Log (WAL) append + MemTable RAM insert $\rightarrow$ MemTable flush to Level 0 SSTable $\rightarrow$ background Level Compaction.

- **Explain How LSM Solves Read Penalties**: Mention that LSM point-read penalties are mitigated using in-memory Bloom Filters (to skip non-matching SSTables in $O(1)$ time) and SSTable Block Indexing.

#### Connect to System Design Use Cases:

- **Choose B-Tree (Postgres/MySQL) for**: General-purpose OLTP systems, relational financial databases, low-latency random point reads, and workloads where reads vastly outnumber writes.

- **Choose LSM-Tree (RocksDB/Cassandra/ScyllaDB) for**: High-throughput write pipelines, time-series data, event logging, messaging platforms, and workloads where write throughput is the primary bottleneck.
