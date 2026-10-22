## Consistent Hashing

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

In distributed systems, data (or client requests) must be partitioned across multiple storage or compute nodes (e.g., Redis cache clusters, Cassandra database nodes, load balancer pools). Standard hash partitioning relies on modulo arithmetic:

$$\text{server\_index} = \text{hash}(\text{key}) \pmod N$$
While this distributes keys uniformly when $N$ (the number of servers) is fixed, it fails during cluster topology changes. If a server crashes or a new server is added to scale out ($N \to N+1$), nearly 100% of all keys remap to different nodes. In caching systems, this triggers a catastrophic cache stampede, driving backend database utilization to 100% and causing cascading outages.

+-----------------------------------------------------------------------------------+
| Real-World Analogy: Circular Conveyor Belt with Buckets |
+-----------------------------------------------------------------------------------+
| Traditional Modulo Hashing: Fixed Room Grid |
| - Items are assigned to rooms based on room count (Item ID % Total Rooms). |
| - Adding or removing 1 room shifts the numbering of every room, forcing almost |
| every single item in the entire warehouse to be moved to a new room. |
| |
| Consistent Hashing: Circular Conveyor Belt |
| - A circular belt has buckets placed along its edge at fixed positions. |
| - Items dropped onto the belt travel clockwise until they hit the first bucket. |
| - Adding or removing a bucket ONLY affects items destined for THAT specific |
| bucket location. All other items drop into their existing buckets untouched. |
+-----------------------------------------------------------------------------------+

- **The Problem It Solves**: Consistent Hashing minimizes key remapping during cluster resizing. When a cluster scales up or down, only $K/N$ keys are reassigned on average (where $K$ is total keys, $N$ is total nodes), compared to $\approx 100\%$ with modulo hashing.

- **Primary Use Cases**: Distributed caches (Memcached Ketama, Redis Cluster), NoSQL databases (Apache Cassandra, Amazon DynamoDB), network proxies (Envoy ring-hash load balancing), and P2P networks (Chord DHT).

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Hash Ring Space**: A fixed, continuous 32-bit integer continuum ranging from $0$ to $2^{32}-1$. The max value wraps around seamlessly back to $0$, forming a logical circle.
- **Ring Mapping**: Both backend server identifiers (e.g., IP address 10.0.0.1:8080) and request/data keys (e.g., user_session_9921) are hashed using the same hash function (e.g., MurmurHash3, MD5) to produce points on the ring.
- **Clockwise Lookup**: To locate the server responsible for a key, compute $\text{hash}(\text{key})$, locate that integer on the ring, and traverse clockwise until encountering the first server node whose ring position is $\ge \text{hash}(\text{key})$.
- **Virtual Nodes (VNodes)**: To prevent uneven key distribution ( hot-spots) caused by sparse physical node placement, each physical machine is assigned multiple pseudo-random positions across the ring space (e.g., 100–250 VNodes per server).

#### Hashing Approaches Matrix:

| Strategy                        | `Key Remap Rate on Scale`             | `Uniformity`             | `Memory Overhead` | `Lookup Time Complexity` |
| ------------------------------- | ------------------------------------- | ------------------------ | ----------------- | ------------------------ |
| **Modulo Hashing(key % N)**     | $\approx 100\%$ ($1 - \frac{1}{N+1}$) | High                     | $O(1)$            | $O(1)$                   |
| **Simple Consistent Hashing**   | $O(K/N)$ (Only adjacent keys)         | Poor (Prone to Hotspots) | $O(N)$            | $O(\log N)$              |
| **Consistent Hashing + VNodes** | $O(K/N)$ (Uniformly spread)           | Optimal                  | $O(N \cdot V)$    | $O(\log(N \cdot V))$     |
| **Google Bounded Loads**        | $O(K/N)$ (Bounded by $1+\epsilon$)    | Strictly Capped          | $O(N \cdot V)$    | $O(\log(N \cdot V))$     |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Execution Logic:

#### 1. Ring Construction & Binary Search Lookup Data Structure:

In memory, the hash ring is represented as a sorted array or a self-balancing Binary Search Tree (Red-Black Tree, e.g., TreeMap in Java or std::map in C++).

```
  Physical Node A (IP: 10.0.0.1)  ──> Hash(10.0.0.1#vn1)  ──> Ring Position 1,000
                                  ──> Hash(10.0.0.1#vn2)  ──> Ring Position 2,500,000
  Physical Node B (IP: 10.0.0.2)  ──> Hash(10.0.0.2#vn1)  ──> Ring Position 1,200,000
Sorted Ring Array: [ 1000 (Node A), 1200000 (Node B), 2500000 (Node A), ... 4294967200 (Node B) ]
                      CLOCKWISE LOOKUP FLOW

                 Key Hash: 1,100,000
                         │
                         ▼
           [ Binary Search on Sorted Ring ]
                         │
        Find First Ring Token >= 1,100,000
                         │
                         ▼
            Match: Token 1,200,000
                         │
                         ▼
       Routes to Physical Node B (10.0.0.2)
```

- **Insertion**: When physical nodes join, their VNodes are hashed and inserted into the sorted structure.

- **Lookup ($O(\log M)$, where $M = N \times V$)**: To route key_99, compute $h = \text{MurmurHash3}(\text{"key\_99"})$. Perform a binary search (bisect_left or ceilingEntry) on the ring array to find the smallest token $\ge h$.

- **Wrap-Around**: If $h$ is greater than the highest token in the array, the search wraps around to index 0(the smallest token on the ring).

#### 2. Node Failure and Addition Workflow:

```
SCENARIO A: ADDING NODE C

Before: Node A (Token 1000) ─────────────────────────> Node B (Token 5000)
       [ Keys in range 1001 - 5000 belong to Node B ]

Action: Node C added at Token 3000.
After:  Node A (Token 1000) ──> Node C (Token 3000) ──> Node B (Token 5000)
       - Keys 1001 - 3000 now belong to Node C.
       - Keys 3001 - 5000 remain on Node B.
       - Result: ONLY keys in range 1001 - 3000 are migrated from B to C!
SCENARIO B: NODE C FAILS

Action: Node C (Token 3000) removed from ring.
After:  Node A (Token 1000) ─────────────────────────> Node B (Token 5000)
       - Keys in range 1001 - 3000 automatically fall forward to Node B.
       - All other ranges across the entire cluster remain 100% unaffected.
```

#### 3. High Availability & Data Replication:

For distributed databases (e.g., Apache Cassandra, DynamoDB), consistent hashing handles both partitioning and data replication:

- **Replication Factor ($R$)**: To store $R$ copies of a key (e.g., $R = 3$), find the primary node by traversing clockwise to the first VNode. Then, continue traversing clockwise along the ring, skipping VNodes that belong to physical machines already selected, until $R$ distinct physical nodes are identified.

Replication Traversal Path:

```
Key Hash ──> [ Node A (VNode 12) ] ──> [ Node B (VNode 4) ] ──> [ Node A (VNode 91) - SKIP ] ──> [ Node C (VNode 2) ]
            ▲                         ▲                                                            ▲
            Primary Replica           Replica 2                                                    Replica 3
```

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Performance Engineering, Edge Cases & Failure Modes

#### 1. Hotspots & The Hot-Key Problem:

- **The Failure Mode**: Consistent Hashing guarantees uniform key placement across ring segments assuming uniform distribution. However, it cannot solve Hot-Key Read Volatility. If key user_twitter_celebrity accounts for 80% of total read QPS, the single physical node owning that key's token range will experience memory/CPU saturation and crash, despite uniform token distribution across the ring.

#### Architectural Mitigations:

- **Key Salting / Multi-Hashing**: Append a random integer suffix ($0..M-1$) to hot keys on write:key_id#1, key_id#2. Reads query a randomly chosen salted key variant, scattering read load across $M$ distinct nodes on the ring.
- **Local In-Memory L1 Cache**: Edge proxy nodes (Envoy / API Gateway) hold short-lived in-memory L1 caches (e.g., 1-second TTL) for popular keys before forwarding requests to the consistent hash ring layer.

#### 2. VNode Count Tuning (Memory vs. Variance Trade-off):

##### The Trade-off:

- **Too Few VNodes ($V < 20$)**: High standard deviation in load distribution ($\approx 30\%$ variance between nodes). Physical servers experience disproportionate traffic shares.
- **Too Many VNodes ($V > 500$)**: Memory utilization for ring state topology metadata explodes across client SDKs. Binary search lookup latency degrades ($O(\log(N \cdot V))$), and cluster membership gossip network protocol overhead increases.
- **Production Sweet Spot**: Setting $V \approx 100\text{--}250$ Virtual Nodes per physical node yields a balance, keeping load variance between physical instances under $\le 5\%$.

```
VNode Count vs. Load Variance Curve:
Load Variance (%)
 35% | *
 25% |   *
 15% |     *
  5% |       * * * * * * * * *  (Sweet Spot: 100 - 250 VNodes)
  0% +--------------------------
     0   25  50  100  250  500  VNodes per Machine
```

#### 3. Consistent Hashing with Bounded Loads (Google Algorithm):

- **The Problem**: In standard consistent hashing, if a subset of keys mapping to Node A gets sudden traffic bursts, Node A handles 100% of the burst load until it crashes, even if adjacent nodes are 99% idle.

- **The Algorithmic Solution**: Enforce a capacity ceiling on every node:

$$\text{Max\_Load} = (1 + \epsilon) \times \frac{\text{Total Current System Load}}{N}$$
If Node A's current load exceeds $\text{Max\_Load}$ (e.g., $\epsilon = 0.25$, or $125\%$ of average load), the router bypasses Node A and continues traversing clockwise along the hash ring to assign the request to the next available server under its capacity threshold.

#### 4. Cluster Membership Synchronization & Gossip Protocols:

In decentralized systems (e.g., Cassandra), there is no centralized load balancer managing the hash ring.Nodes use a Gossip Protocol to exchange token ownership maps asynchronously across peers.

- **Split-Brain Risk**: During network partitions, different nodes may operate on stale views of the hash ring state, leading to inconsistent key reads or data written to wrong nodes.

- **Mitigation**: Use hint handoff logs, active anti-entropy repair (Merkle Trees), and strict quorum read/write configurations ($R + W > N$) to ensure consistency despite temporary hash ring state desynchronization.

---

### 5. Text-Based Architecture Diagram:

```
Scalable Distributed Ring Topology with VNodes and Replication
===================================================================================
                            32-BIT CONTINUOUS HASH RING
===================================================================================

                                Token: 0 / 2^32
                                      |
                  (VN) Node_C_2 [Position: 3,900,000,000]
                                 /         \
                                /           \
 (VN) Node_A_3 [3,200,000,000] /             \  (VN) Node_A_1 [500,000,000]
                              |               |
                              |  HASH RING    |  <-- Key "user_812"
                              |  SPACE        |      Hash: 750,000,000
                              |               |      (Routes Clockwise to Node_B_1)
 (VN) Node_B_2 [2,500,000,000] \             /  (VN) Node_B_1 [1,100,000,000]
                                \           /
                                 \         /
                  (VN) Node_C_1 [Position: 1,800,000,000]

===================================================================================
                      DATA MAPPING & REPLICATION LOOKUP
===================================================================================

Target Key: "user_812"  ──> Hash("user_812") = 750,000,000

Step 1: Scan clockwise on ring for First Token >= 750,000,000
        ──> Matches: Token 1,100,000,000 (VNode: Node_B_1)
        ──> PRIMARY STORAGE: Physical Node B

Step 2: Continue clockwise to find distinct physical nodes for Replication (R = 2)
        ──> Next Token: 1,800,000,000 (VNode: Node_C_1)
        ──> REPLICA 2 STORAGE: Physical Node C
```

---

### 6. Interview Checklist:

When pitching or evaluating Consistent Hashing during system design interviews:

- **Define the Problem First**: Frame consistent hashing explicitly as the solution to mass key remapping ($O(1)$ vs $O(K/N)$) and cache stampedes caused by traditional modulo hashing during system scaling or node failures.

- **Always Proactively Introduce Virtual Nodes (VNodes)**: Do not stop at basic ring hashing. Mention that raw consistent hashing causes unbalanced key distribution (hotspots) and that Virtual Nodes (100–250 VNodes/server) are required to achieve uniform distribution ($\le 5\%$ variance).

#### Demonstrate Real-World Industrial Context: Mention actual systems utilizing this pattern:

- **Database Partitioning**: Apache Cassandra, Amazon DynamoDB.

- **Caching & Load Balancers**: Memcached Ketama, Redis Cluster, Envoy Ring-Hash Proxy Load Balancing.

- **Address Pro-Level Edge Cases**: Show high-level system engineering mastery by addressing Hot-Key Volatility (recommend key salting / L1 local proxy caching) and Google Bounded Loads Consistent Hashing (capping node load to prevent cascade failures).
