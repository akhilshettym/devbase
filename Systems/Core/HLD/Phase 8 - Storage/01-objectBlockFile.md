## Object Storage vs Block Storage vs File Storage

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Storage systems in software architecture dictate how bits are organized, accessed, and persisted on physical media. Selecting the wrong storage abstraction forces fundamental trade-offs in latency, access protocols,concurrency, cost, and horizontal scalability.

```
+-----------------------------------------------------------------------------------+
|                     Real-World Analogy: Physical Storage Models                   |
+-----------------------------------------------------------------------------------+
| Block Storage: Raw Parking Garage Spaces                                          |
| - Fixed-size, numbered parking slots (e.g., Slot 1024).                           |
| - The garage owner doesn't care what kind of vehicle parks there or how you pack  |
|   it. Highly efficient, ultra-fast access, but you must bring your own valet      |
|   system (Filesystem) to manage the interior space.                               |
|                                                                                   |
| File Storage: Office Filing Cabinet System                                        |
| - Hierarchical folders nested inside folders (`/documents/2026/invoices/001.pdf`).|
| - Shared access where multiple employees open the same folder simultaneously.     |
| - Easy to navigate for humans, but searching across millions of deep folders      |
|   creates massive management overhead.                                            |
|                                                                                   |
| Object Storage: Automated Warehouse Coat Check with Claim Ticket                  |
| - You hand over a coat (Data) + custom tags (Metadata: Owner, Color, Size).       |
| - The warehouse gives you a unique ticket ID (Key). There are no folders.         |
| - To retrieve it, you present the ticket ID. Infinite capacity, flat namespace,   |
|   accessible via a counter window (HTTP REST API).                                |
+-----------------------------------------------------------------------------------+
```

- **Block Storage**: Solves the problem of high-performance, low-latency, raw storage required by operating systems and databases. Data is split into fixed-size chunks (blocks) without metadata. Use Block storage for relational/NoSQL databases, virtual machine disks (SAN/EBS), and boot volumes.

- **File Storage**: Solves the problem of shared, multi-node access to hierarchical file structures over a local network. Uses POSIX-compliant file lock interfaces. Use File storage for shared application media assets,legacy enterprise apps, content management systems (CMS), and shared developer workspaces.

- **Object Storage**: Solves the problem of storing massive volumes of unstructured media files (blobs) at scale with metadata. Accessible over HTTP/S REST APIs (GET/PUT). Use Object storage for static web assets, video/audio streaming sources, data lake analytics, backups, and machine learning training datasets.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

#### Block Storage:

- **Logical Unit Number (LUN) / Volume**: An abstraction presented to an OS as a raw disk.
- **Block**: The smallest atomic unit of raw storage (typically 4 KB to 64 KB).
- **Protocols**: NVMe-oF (NVMe over Fabrics), iSCSI, Fibre Channel.

#### File Storage:

- **POSIX Compliance**: Portable Operating System Interface standard governing file operations (open,read, write, seek, lock).
- **Inode**: A file system data structure storing metadata (permissions, ownership, file size, block pointers) separately from file content.
- **Protocols**: NFS (Network File System - Linux), SMB/CIFS (Server Message Block - Windows).

#### Object Storage:

- **Bucket & Key**: A bucket is a flat logical namespace container; a key is the unique string identifier mapping to a stored object (bucket/user-avatars/102.png).
- **Metadata**: Arbitrary key-value pairs stored alongside object data (e.g., Content-Type: image/png,Author: Alice).
- **Protocols**: HTTP/HTTPS REST APIs (AWS S3 API, OpenStack Swift).

#### Architectural Comparison Matrix:

| Vector              | `Block Storage (e.g., AWS EBS, SAN)` | `File Storage (e.g., AWS EFS, NFS)`  | `Object Storage (e.g., AWS S3, Ceph RGW)` |
| ------------------- | ------------------------------------ | ------------------------------------ | ----------------------------------------- |
| **Data Structure**  | Unstructured fixed-size raw blocks   | Hierarchical directory tree (/a/b/c) | Flat key-value namespace (bucket/key)     |
| **Access Protocol** | Direct block-level I/O (SCSI, NVMe)  | Network Filesystem (NFS, SMB)        | Application HTTP/HTTPS REST APIs          |
| **I/O Latency**     | Sub-millisecond to low ms            | Low to Moderate (1–10 ms)            | High (10–100 ms)                          |
| **Throughput**      | High per volume                      | Moderate (Scales with client count)  | Ultra-High Aggregate(Parallel streams)    |
| **Mutability**      | Random In-Place Writes(Byte-level)   | In-Place Modifications               | Immutable (Write-Once, Replace Entirely)  |
| **Scaling Limit**   | Capped per volume (e.g., 16–64 TB)   | PetaScale (Bounded by lock index)    | Virtually Infinite (Exabytes+)            |
| **Cost / GB**       | High                                 | Moderate–High                        | Ultra-Low                                 |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Storage Engines:

#### 1. Block Storage Mechanics: Direct Controller I/O:

Block storage exposes raw sector ranges directly to an operating system file system (e.g., ext4, xfs) or database engine (e.g., InnoDB, RocksDB).

```
[ Application / DB Engine ] ──► [ Local File System (ext4) ] ──► [ OS Block Device Driver ]
                                                                       │
                                                     (Raw SCSI / NVMe Commands over SAN)
                                                                       │
                                                                       ▼
                                                       [ Storage Array Controller ]
                                                       [ Sector 0x8F012 - Block 4KB ]
```

- **In-Place Mutation**: The operating system overwrites individual bytes/blocks directly at specific physical or logical offset locations without rewriting the surrounding data file.
- **Network Fabrics**: Cloud block storage (e.g., AWS EBS) translates local hypervisor block commands into distributed network calls to replicated storage nodes over high-speed networks using custom NVMe-oF variants.

#### 2. File Storage Mechanics: Hierarchical Inode Traversal & Lock Managers

File storage engines map user-friendly paths (/var/data/app/config.json) to physical storage using Inodes and directory entries.

```
Client App Node 1 \                                      +----------------------------------+
                  == (NFS v4 RPC over TCP) ==> [ NAS ] | Distributed Inode Lock Manager     |
Client App Node 2 /                                      | Directories -> Inodes -> Blocks  |
                                                        +-----------------------------------+
```

- **Path Resolution Overhead**: To open /a/b/c.txt, the storage engine must traverse and parse the directory structure top-down: read root Inode $\to$ lookup a $\to$ read Inode a $\to$ lookup b $\to$ read Inode b$\to$ lookup c.txt $\to$ lock Inode c.txt.
- **POSIX Locking**: When multiple compute nodes mount the same NFS export, file access requires a centralized Distributed Lock Manager (DLM). If Client 1 writes to a file, the DLM issues lock invalidation messages across all mounted clients, causing severe latency degradation under high concurrent write workloads.

#### 3. Object Storage Mechanics: Disaggregated Metadata & Erasure Coding:

Object storage systems decouple Metadata Indexing from Raw Data Chunk Storage.

```
 HTTP PUT /bucket/video.mp4 ──► [ REST API Gateway ]
                                        │
              ┌─────────────────────────┴─────────────────────────┐
              ▼                                                   ▼
 [ Metadata Key-Value Store ]                       [ Immutable Chunk Store ]
 (e.g., RocksDB / Distributed Index)               (Splits Payload into Data & Parity Chunks)
 - Key: "bucket/video.mp4"                                        │
 - Custom Attributes, Size, ACLs                                  ▼
 - Chunk ID Map: [C1, C2, C3]                      [ Disk Node 1 ] [ Disk Node 2 ] [ Disk Node 3 ]
```

- **Ingest & Partitioning**: The API Gateway receives an HTTP PUT request payload and generates a unique object ID. Large files are chopped into fixed chunks (e.g., 8 MB–64 MB).
- **Metadata Storage**: Object key strings, custom metadata tags, access control lists (ACLs), and chunk mappings are persisted in an ultra-fast, distributed Key-Value index (e.g., RocksDB, Cassandra, or LSM-tree databases).
- **Data Chunk Persistence**: Chunks are written to raw storage nodes using Erasure Coding instead of simple triple replication.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Performance Engineering, Edge Cases & System Optimizations:

#### 1. Storage Efficiency: Replication ($3\times$) vs. Erasure Coding ($k+m$):

$3\times$ Replication: Writes 3 identical copies of every payload block across distinct failure domains.

- **Trade-off**: $200\%$ storage overhead ($300\%$ raw storage consumption). High cost at exabyte scale.
- **Erasure Coding ($k + m$)**: Splits an object into $k$ data chunks and generates $m$ parity chunks using Reed-Solomon algebraic coding algorithms. The system tolerates the simultaneous loss of any $m$storage drives.

$$\text{Storage Overhead Ratio} = \frac{k + m}{k}$$
Erasure Coding 8+4 Config (k = 8 Data Chunks, m = 4 Parity Chunks):
Storage Overhead = (8 + 4) / 8 = 1.5x (ONLY 50% Overhead vs 200% for 3x Replication!)
Can lose ANY 4 drives concurrently without losing data!

- **Trade-off**: Erasure coding significantly reduces raw storage hardware costs, but incurs heavy CPU encoding overhead on writes and introduces reconstructive read latency when reading data from degraded nodes undergoing disk repairs.

#### 2. The Object Storage "Small File Problem":

The Failure Mode: Storing millions of tiny files ($< 10\text{ KB}$) in Object Storage causes massive performance degradation. The metadata index explodes in size ($O(N)$ index lookup memory), and the network overhead of establishing HTTP/TLS TCP sessions for tiny $2\text{ KB}$ payloads dominates total throughput time.

- **Architectural Fix**: Batch tiny objects on the client side into larger aggregated archive files (e.g., Apache Parquet, SequenceFiles, TAR archives) before writing to Object Storage. Query sub-ranges of aggregated files using S3 Select or byte-range HTTP headers (Range: bytes=1024-4096).

#### 3. Consistency Models: Eventual vs. Strong Read-After-Write Consistency:

Historically, distributed object stores (like AWS S3) used Eventual Consistency for overwrite PUTs and DELETEs. Updating an object might cause a reader querying an adjacent edge node to receive stale data for several seconds.

- **Modern Standard (Strong Read-After-Write Consistency)**: Modern S3 and Ceph storage engines enforce synchronous metadata updates across quorum index nodes. Once an HTTP PUT 200 OKcompletes, any subsequent GET or LIST call globally immediately reflects the new object version.
- **Under the Hood**: Implemented by executing atomic consensus protocols (Raft/Paxos) on the metadata index layer before returning the HTTP write response to the client application.

#### 4. Shared POSIX Lock Contention in Cloud Distributed NAS:

Attempting to run high-concurrency transactional database engines (e.g., MySQL, PostgreSQL) over Network File Systems (NFS/AWS EFS) is a critical anti-pattern.

- **Why It Fails**: Databases manage their own page locking and buffer pools assuming microsecond-level direct block allocation. Running over distributed file storage causes NFS lock contention, metadata lookup serialization stalls, and risk of database page corruption during network partitions.

---

### 5. Text-Based Architecture Diagram:

Scalable Polyglot Enterprise Storage Topology

```
===================================================================================
                              APPLICATION COMPUTING LAYER
===================================================================================

[ Transactional Web App ]      [ Media Assets CMS Node ]      [ Analytics / AI Worker ]
           │                              │                               │
           │ Low-Latency                  │ Shared POSIX                  │ HTTP REST API
           │ Block Read/Write             │ File Mount Path               │ Mass Throughput
           v                              v                               v
===================================================================================
                            STORAGE SUBSYSTEM TYPING
===================================================================================

+---------------------------+  +---------------------------+  +---------------------------+
|   BLOCK STORAGE (EBS/SAN) |  |    FILE STORAGE (NFS/EFS) |  |  OBJECT STORAGE (S3/Ceph) |
|                           |  |                           |  |                           |
| - Raw Partition (ext4)    |  | - Hierarchical Paths      |  | - REST API Gateway        |
| - Sub-millisecond IOPS    |  | - Shared POSIX Locking    |  | - Metadata KV Index Engine|
| - In-place mutation       |  | - Multi-Node Mounts       |  | - Erasure Coded Disk Array|
+---------------------------+  +---------------------------+  +---------------------------+
           │                              │                               │
           v                              v                               v
+---------------------------+  +---------------------------+  +---------------------------+
| MySQL / PostgreSQL DBs    |  | Shared Static Images      |  | Analytics Data Lake,      |
| High-IOPS Write Logs      |  | Legacy Config Workspace   |  | Video Blobs, Backups      |
+---------------------------+  +---------------------------+  +---------------------------+
```

---

### 6. Interview Checklist:

When choosing or discussing Storage primitives during a system design interview:

#### Select Storage Types Based on Access Pattern & Latency Constraints:

- **Block**: Choose for databases, transactional engines, or VM boot drives requiring sub-millisecond,low-latency, in-place random byte modifications.

- **File**: Choose for shared compute workloads requiring standard POSIX directory structures, file locking, and multi-node concurrent network read/write access.

- **Object**: Choose for unstructured blobs, video/image media, data lakes, and backups requiring infinite exabyte scale, metadata indexing, and ultra-low cost per GB over HTTP REST APIs.

- **Address Object Storage Immutability Rules**: Always clarify that object storage is immutable (writing an update replaces the whole payload). Never recommend object storage for applications requiring high-frequency random in-place writes.

- **Proactively Pitch Erasure Coding vs. Replication**: Demonstrate deep storage engineering knowledge by explaining how Erasure Coding ($k+m$) cuts raw storage hardware footprint by over $50\%$compared to $3\times$ replication while preserving high fault tolerance at scale.

- **Avoid Storage Anti-Patterns**: Call out dangerous storage choices explicitly (e.g., placing transactional databases on shared NFS file storage, or storing millions of unaggregated sub-2KB micro-files in object storage).
