## 1. Storage Architecture & Indexing:

- **Index Data Structures**: How B-Trees / B+Trees (read-heavy, range queries) differ from LSM-Trees(write-heavy append-only logs).

- **Index Types & Selection**: Differences between Clustered vs. Non-Clustered indexes, primary vs. secondary indexes, composite indexes, and the Leftmost Prefix Rule.

- **Indexing Overhead**: Trade-offs between faster SELECT queries and the write amplification and storage bloat caused by maintaining indexes during writes.

---

Under the hood, a database engine manages data in memory and on physical disk through four primary layers: page storage, index structures, row referencing, and indexing trade-offs.

### 1. <u>Physical Storage Foundation: Pages, Slots & Buffer Pools</u>:

Databases never read or write data row-by-row on disk. Because operating systems and storage hardware operate on block devices, database storage engines read and write data in fixed-size chunks called Pages(typically 4KB, 8KB, or 16KB).

```
+-----------------------------------------------------------------------+
|                              PAGE HEADER                              |
|  Page ID | LSN (Transaction Log) | Free Space Pointer | Slot Count    |
+-----------------------------------------------------------------------+
| SLOT ARRAY (Line Pointers growing DOWNWARDS)                          |
|  Slot 0: [Offset: 8100, Len: 90] | Slot 1: [Offset: 7980, Len: 120] ..|
+-----------------------------------------------------------------------+
|                          <--- FREE SPACE --->                         |
+-----------------------------------------------------------------------+
| TUPLE / ROW DATA (Growing UPWARDS)                                    |
|                                     [Row 1 Data] [Row 0 Data]         |
+-----------------------------------------------------------------------+
```

#### Slotted-Page Architecture:

A page must handle variable-length rows (VARCHAR, JSON, BLOB) and frequent updates without fragmenting storage. To achieve this, engines split a page into three regions:

- **Page Header**: Stores metadata such as Page ID, transaction log sequence numbers (LSN), slot counts, and the boundary offsets of free space.
- **Slot Array (Line Pointers)**: Located at the top of the page growing downwards. Each slot entry is a tiny fixed-size tuple holding (Byte Offset, Byte Length) pointing to the actual row location within that page.
- **Tuple Data**: Located at the bottom of the page growing upwards into the free space in the middle.

#### Why this design matters:

Every row in a database has a physical location called a Tuple ID (TID) or Row ID (RID), formatted as (Page ID, Slot Index). If a row is updated and expands, the storage engine can shift the row's bytes inside that page and update its byte offset in Slot 0. Because external indexes point to (Page ID, Slot 0), the index reference remains valid—preventing expensive cascade updates across secondary indexes.

#### The Buffer Pool:

Reading from disk is orders of magnitude slower than reading from RAM. Databases allocate a massive block of memory called the Buffer Pool (or Page Cache).

When a query requests a row, the engine converts the request to a Page ID, hashes it, and checks if that page is in the Buffer Pool.

- **Cache Hit**: Read directly from RAM.
- **Cache Mis**s: Load page from disk into a free Buffer Pool slot (frame).

**Eviction**: If RAM is full, policies like LRU-K or 2Q evict unpinned pages. Modified pages in RAM are marked as Dirty Pages and written to disk asynchronously via background flushes.

---

### 2. <u>Index Data Structures: B+ Trees vs. LSM-Trees</u>:

Database engines organize disk pages into specific tree structures based on whether the workload prioritizes high read performance or high write throughput.

```
                 B+ TREE ARCHITECTURE (In-Place Updates)
                            [ Root Node ]
                           /             \
                  [ Internal ]         [ Internal ]  <-- Keys + Child Page IDs
                 /            \       /            \
            [ Leaf ] <-----> [ Leaf ] <-----> [ Leaf ] <-- Keys + Row Data / RIDs
                                                    (Sequential Doubly-Linked List)
```

#### B+ Tree (Read-Optimized / In-Place Updates):

The B+ Tree is the default storage engine structure for traditional relational systems. It is a self-balancing $M$-way search tree optimized for disk block reads.

- **Internal Nodes**: Contain only routing keys and child page pointers. No actual row data exists in internal nodes.

- **Leaf Nodes**: Contain the actual keys paired with full row data or row pointers. All leaf nodes are linked horizontally as a doubly linked list.

- **High Fan-Out**: Because internal nodes only store small keys and page pointers, a single 8KB page can store hundreds of child references. This high fan-out keeps the tree height extremely shallow ($\le 3$ or $4$ levels), meaning looking up any key in a billion-row table requires at most 3 or 4 disk I/O reads.

- **Range Query Efficiency**: To execute WHERE age BETWEEN 25 AND 35, the engine traverses down to the leaf node holding 25 in $O(\log_B N)$ time, then traverses horizontally across the linked leaf nodes until it hits 35. It does not need to traverse back up to parent nodes.

- **Page Splits**: When an INSERT hits a full leaf page, the engine splits the page 50/50, creates a new page, and pushes the median key up into the parent node.

```
                LSM-TREE ARCHITECTURE (Append-Only Writes)
Write Operations ──> [ Write-Ahead Log (Disk) ] + [ MemTable (RAM) ]
                                                         │ (Flush when full)
                                                         ▼
                                                 [ Level 0 SSTables ]
                                                         │ (Compaction)
                                                         ▼
                                                 [ Level 1 SSTables ]
```

#### LSM-Tree (Log-Structured Merge-Tree / Write-Optimized):

When write throughput outpaces what B+ Trees can handle (due to random disk page writes and page splits), databases use LSM-Trees. LSM-Trees convert random writes into fast sequential writes.

- **MemTable**: An in-memory data structure (usually a Red-Black Tree or SkipList). Every INSERT, UPDATE, or DELETE is appended sequentially to an on-disk Write-Ahead Log (WAL) for durability and written to the MemTable in memory.

- **SSTables (Sorted String Tables)**: When the MemTable fills up (e.g., 64MB), it is flushed to disk as an immutable SSTable file. Keys inside an SSTable are strictly sorted.

- **Bloom Filters**: Because a key could exist across multiple SSTable files on disk, point lookups would be slow. LSM engines store a Bloom Filter (a space-efficient probabilistic structure) for each SSTable in memory to instantly check if a key is definitely not inside an SSTable without reading disk.

- **Compaction**: A background process constantly reads overlapping SSTables, merges them together, discards old key versions or DELETE tombstones, and writes consolidated SSTables to deeper levels (Level 0 $\to$ Level 1 $\to$ Level 2).

#### Architectural Trade-off Summary:

| Metric                  | `B+ Tree`                               | `LSM-Tree`                                      |
| ----------------------- | --------------------------------------- | ----------------------------------------------- |
| **Primary Workload**    | Read-Heavy (70% + Reads)                | Write-Heavy (70% + Writes)                      |
| **Write Pattern**       | Random I/O (In-place updates)           | Sequential I/O (Append-only)                    |
| **Read Latency**        | Fast & Deterministic (O(logN))          | Slower (May check MemTable + multiple SSTables) |
| **Write Amplification** | High (Entire page reqritten for 1 byte) | Moderate to High (Due to Compaction cycles)     |
| **Range Queries**       | Exceptional (Linked leaf nodes)         | Slower (Requires merging streams from SSTables) |

---

### 3. <u>Clustered vs. Secondary (Non-Clustered) Indexes</u>:

```
                 CLUSTERED INDEX                       SECONDARY INDEX
              [ Primary Key: ID ]                   [ Secondary Key: Email ]
                /            \                          /            \
          [ Leaf Page ]  [ Leaf Page ]            [ Leaf Page ]  [ Leaf Page ]
        +---------------+---------------+        +---------------+---------------+
        | ID | Name     | ID | Name     |        | Email | PK ID | Email | PK ID |
        | 1  | Alice    | 2  | Bob      |        +-------+-------+-------+-------+
        +---------------+---------------+                │ (Bookmark Lookup)
          (Actual Physical Row Data)                     └─────────► Look up in
                                                                     Clustered Index
```

#### Clustered Index:

A clustered index determines the physical order of data pages on disk.

- **One Per Table**: Because physical rows on disk can only be stored in one sorted order, a table can have only one clustered index.
- **Leaf Nodes = Data**: The leaf nodes of a clustered B+ Tree contain the actual full row tuples.
- **Lookup Cost**: Point queries matching the clustered index key resolve in a single B+ Tree traversal directly to the underlying data page.

#### Secondary (Non-Clustered) Index:

A secondary index is a separate B+ Tree structure created to speed up queries on non-primary columns (e.g., searching by email).

- **Leaf Nodes = Indirect Keys**: The leaf nodes of a secondary index do not contain full row data. They store the indexed secondary key alongside a pointer to the main row.

#### Secondary Pointer Mechanics:

- **Clustered Key Pointer (Primary Key)**: The secondary index leaf stores the Primary Key value. A lookup on a secondary index requires traversing the secondary B+ Tree first, obtaining the Primary Key, and performing a second traversal down the Clustered B+ Tree to read the row data. This process is called a Double Lookup or Bookmark Lookup.

- **Tuple ID / RID Pointer**: Stores the direct physical (Page ID, Slot Index). Faster, but if page splits move the physical row, every secondary index entry must be updated.

#### Covering Indexes & Index-Only Scans:

- Bookmark lookups degrade performance when retrieving many rows. A Covering Index includes all columns requested by a query directly inside the secondary index tree structure.

If an index exists on (email, status), and you execute:

```SQL
SELECT email, status FROM users WHERE email = 'dev@example.com';
```

The query engine detects that every required column (email and status) exists within the secondary index leaf node. It skips the second traversal to the primary clustered index entirely. This execution path is called an Index-Only Scan.

---

### 4. <u>Execution Rules & Write Amplification Trade-offs</u>:

#### The Leftmost Prefix Rule:

When building a Composite Index on multiple columns—such as (Country, State, City)—the database orders keys in compound lexicographical order: sorted by Country first, then State within each Country, and finally City within each State.

Index: (Country, State, City)

Supported Lookups (Index Seek):

- WHERE Country = 'USA'
- WHERE Country = 'USA' AND State = 'CA'
- WHERE Country = 'USA' AND State = 'CA' AND City = 'SF'

Unsupported Lookups (Full Index/Table Scan):

- WHERE State = 'CA' <-- Violates Leftmost Prefix
- WHERE City = 'SF' <-- Violates Leftmost Prefix
- WHERE State = 'CA' AND City = 'SF' <-- Violates Leftmost Prefix

If a query omits the leading column (Country), the engine cannot use the B+ Tree structure to skip pages because State = 'CA' entries are scattered across completely different Country subtrees.

##### Write Amplification & Index Overhead:

While indexes dramatically accelerate SELECT statements, every additional index imposes a cost on write operations (INSERT, UPDATE, DELETE):

- **Write Amplification**: Inserting a single row into a table with $1$ clustered index and $4$ secondary indexes requires modifying $5$ distinct B+ Trees on disk.
- **Page Splits & Latency Spikes**: If an INSERT lands on a full leaf page in any of those 5 index trees, the engine must execute a page split, allocate new disk pages, and adjust parent pointers—turning a quick write into multiple disk I/O operations.
- **Buffer Pool Pollution**: Frequent updates across multiple indexes cause dirty pages to flood the buffer pool, forcing the engine to flush pages to disk more frequently and reducing overall system throughput.
