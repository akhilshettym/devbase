## Quorums

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a corporate board of 5 directors holding a vote on a company acquisition:

- **100% Unanimous Rule ($W = 5$)**: Every single director must be present and vote "Yes." If director #5 is stuck on a plane without Wi-Fi, the entire company halts and cannot make decisions, despite 4 directors being present in the boardroom.

- **Quorum Rule ($W = 3$)**: As long as a majority of 3 directors ($3/5$) are present and agree, the vote passes and is legally binding. The absent director can catch up on the decision later when they land.

- **Read/Write Overlap ($W + R > N$)**: If any group of 3 directors authorizes a purchase ($W = 3$), and you later interview any random group of 3 directors ($R = 3$), at least one director in your interview group is guaranteed to have participated in the vote. You don't need to ask all 5 directors to find out what happened.

#### The Core Problem Solved:

- In a distributed storage system, replicating data across multiple physical nodes is necessary for durability and availability. However, requiring every single replica to confirm a write before returning success makes the system extremely fragile—a single slow disk or network hiccup on one replica stalls the entire database.

- Quorums solve this by replacing rigid "all-or-nothing" execution with flexible voting thresholds. They allow a cluster to guarantee data freshness and fault tolerance using overlapping subsets of replica nodes, enabling systems to operate smoothly even when individual nodes crash or experience network delays.

---

### 2. The Basics (Scratch Level):

#### The Core Formula: $N, W, R$:

Quorum systems are defined by three configurable parameters:

- **$N$ (Replication Factor)**: The total number of nodes assigned to store copies of a specific piece of data.
- **$W$ (Write Quorum)**: The minimum number of replica nodes that must successfully process and acknowledge a write operation before it is declared successful to the client.
- **$R$ (Read Quorum)**: The minimum number of replica nodes that must respond to a read operation before returning the data to the client.

```
                 THE PIGEONHOLE OVERLAP PRINCIPLE (W + R > N)

Replication Factor N = 5
Write Set (W = 3):    [ Node 1 ]  [ Node 2 ]  [ Node 3 ]  [        ]  [        ]
Read Set  (R = 3):    [        ]  [        ]  [ Node 3 ]  [ Node 4 ]  [ Node 5 ]
                                                 ▲
                                        OVERLAPPING NODE
                                Guaranteed to return the latest write!
```

#### The Consistency Equation:

#### Strong Consistency Guarantee ($W + R > N$):

When the sum of the write quorum and read quorum exceeds the total replication factor, the read set and write set are mathematically guaranteed to overlap by at least one physical node. That node acts as the bridge returning the latest versioned write.

#### Weak / Eventual Consistency ($W + R \le N$):

When the read and write sets do not overlap, reads can execute against nodes that missed recent writes, risking stale reads in exchange for faster responses and higher availability.

#### Common Quorum Configurations Matrix:

| Configuration              | `Parameters (N=3)` | `Read Latency`             | `Write Latency`            | `Failure Tolerance`        | `Best Use Cases`                                                  |
| -------------------------- | ------------------ | -------------------------- | -------------------------- | -------------------------- | ----------------------------------------------------------------- |
| **Fast Read / Slow Write** | $W = 3, R = 1$     | Sub-millisecond ($1$ node) | High ($3$nodes sync)       | $0$ write failures allowed | Read-heavy workloads with strict read consistency needs.          |
| **Fast Write / Slow Read** | $W = 1, R = 3$     | High ($3$nodes sync)       | Sub-millisecond ($1$ node) | $0$ read failures allowed  | High-throughput logging, IoT ingestion, write-heavy audit trails. |
| **Balanced Quorum**        | $W = 2, R = 2$     | Balanced                   | Balanced                   | Tolerates $1$ node failure | Standard production default for Cassandra, DynamoDB, Riak.        |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Quorum Read Mechanics & Read Repair:

When an application issues a quorum read ($R = 2$ on $N = 3$), the coordinator node does not need to pull full payloads from all nodes over the network. It uses a Digest Read strategy to optimize network bandwidth:

```
                                 QUORUM READ & READ REPAIR FLOW

[ Client ] ──(1. Read user_101 @ R=2)──► [ Coordinator Node ]
                                               │
      ┌────────────────────────────────────────┴────────────────────────────────────────┐
      │ (2a. Full Data Request)                                                         │ (2b. Hash/Digest Request)
      ▼                                                                                 ▼
[ Replica Node A ]                                                                [ Replica Node B ]
(Returns Payload: {v2, "Alice"})                                                 (Returns Hash: MD5(v1) = "x8f2...")
      │                                                                                 │
      └────────────────────────────────────────┬────────────────────────────────────────┘
                                               │
                                 (3. Hash Mismatch Detected!)
                                 Coordinator fetches full payload from Node B.
                                 Node B is STALE (holds v1).
                                               │
      ┌────────────────────────────────────────┴────────────────────────────────────────┐
      │ (4. Immediate Response)                                                         │ (5. Async Read Repair)
      ▼                                                                                 ▼
[ Client ] ◄──(Returns Newest Data: v2)                                           [ Replica Node B ]
                                                                                  (Overwrites v1 -> v2)
```

- **Full Payload Request**: The coordinator sends a request for the full data payload to the nearest replica (Node A).

- **Digest Request**: The coordinator sends a lightweight cryptographic checksum/hash request (MD5/SHA64) to the remaining $R-1$ replicas (Node B).

#### Digest Comparison:

- If all hashes match, the coordinator returns Node A's payload immediately.

- If hashes mismatch, a data conflict exists. The coordinator requests full data from all $R$ nodes, compares timestamps/versions, returns the latest version to the client, and issues an asynchronous Read Repair write to overwrite the stale replica.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Strict Quorums vs. Sloppy Quorums & Hinted Handoff:

What happens during a network partition when $W = 2$ on $N = 3$, but 2 out of the 3 designated primary replicas for a key go down?

```
1. STRICT QUORUM (Fails on Outage)                2. SLOPPY QUORUM + HINTED HANDOFF (High Availability)
Target Replicas: [ Node 1 (DOWN), Node 2 (DOWN), Node 3 (UP) ]

Write Request (W = 2) ──► Target Nodes           Write Request (W = 2) ──► Target Nodes
      │                                                │
      ▼                                                ▼
FAIL! Only 1/2 primary ACKs received.            Write accepted on Node 3 (Primary) AND Node 4 (Fallback)!
(Rejects write to maintain consistency)          Node 4 stores a "Hint" & replays to Node 1 when it recovers.
```

#### 1. Strict Quorums:

- Writes and reads must be processed by the specific physical nodes assigned to that key's range on the hash ring.
- If fewer than $W$ or $R$ primary nodes respond, the operation fails.
- Trade-off: Guarantees strong consistency ($W + R > N$), but sacrifices write availability during node outages.

#### 2. Sloppy Quorums & Hinted Handoff:

- If primary nodes are unreachable, the coordinator accepts writes on neighboring physical nodes outside the primary hash ring assignment.
- The fallback node writes the data to a temporary local storage space called a Hint. Once the primary node comes back online, the fallback node streams the hinted writes back to the primary node (Hinted Handoff).
- Trade-off: Keeps writes fully available during major outages, but temporarily breaks $W + R > N$ strong consistency guarantees. Subsequent reads from primary nodes will not see the hinted writes until handoff completes.

#### Background Anti-Entropy with Merkle Trees:

- Read Repair only fixes stale data on rows that are actively queried by users. Cold data that is rarely read can drift out of sync permanently if writes are missed.

- To fix cold data silently without scanning billions of rows over the network, engines like Apache Cassandra use Anti-Entropy Synchronization using Merkle Trees:

```
              MERKLE TREE COMPARISON FOR ANTI-ENTROPY SYNC

             Node A Root Hash [ H(1-4) ]           Node B Root Hash [ H(1-4) ]
                   /          \                          /          \
           H(1-2)            H(3-4)              H(1-2)            H(3-4)*  <-- Mismatch!
          /     \           /     \             /     \           /     \
        H(1)    H(2)      H(3)    H(4)        H(1)    H(2)      H(3)*   H(4)  <-- Stale Range!
```

- Each node builds a binary tree of hashes (Merkle Tree) over a specific key range, where parent nodes represent hashes of their children.
- During background maintenance, Node A and Node B exchange only their top-level Root Hashes($O(1)$ network transfer).
- If root hashes match, datasets are $100\%$ identical. If root hashes mismatch, nodes traverse down the tree branches to isolate the exact narrow key range containing stale data and sync only those specific missing keys.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
           QUORUM OVERLAP & SLOPPY FALLBACK EXECUTION PATHS
================================================================================

PATH A: STRICT QUORUM READ OVERLAP (W=2, R=2, N=3 => W + R > N)
--------------------------------------------------------------------------------
Key: "user_401"  | Primary Nodes: [ Node A (v2), Node B (v2), Node C (v1) ]

Read Request (R=2) ──► [ Coordinator ]
                           ├─── Read Node A ──► Returns Version 2
                           └─── Read Node C ──► Returns Version 1
                                      │
                        (Coordinator selects Version 2)
                                      │
                                      ├─► Returns Version 2 to Client
                                      └─► Triggers Async Read Repair to Node C


PATH B: SLOPPY QUORUM WRITE WITH HINTED HANDOFF
--------------------------------------------------------------------------------
Primary Nodes for "user_902": [ Node X (OFFLINE), Node Y (OFFLINE), Node Z (UP) ]

Write Request (W=2) ──► [ Coordinator ]
                           ├─── Write Node Z (Primary)  ──► ACK (1/2)
                           └─── Write Node K (Fallback) ──► ACK (2/2) + Stores HINT
                                      │
                       (Returns Success to Client!)
                                      │
                    (Node X Recovers 10 Minutes Later)
                                      │
                     Node K Streams Hinted Handoff ──► Node X
================================================================================
```

---

### 6. Interview Checklist:

- **State the Pigeonhole Overlap Rule**: Always lead with $W + R > N$ when asked how quorums guarantee strong consistency. Explain that overlapping at least $1$ node ensures read operations encounter the latest write.

- **Explain Digest Reads**: Show deep engineering insight by explaining that read quorums send $1$ full payload request and $R-1$ cryptographic hash/digest requests to save network bandwidth.

- **Contrast Read Repair vs. Anti-Entropy**: Clarify that Read Repair fixes stale data dynamically during active read queries, while Anti-Entropy uses Merkle Trees in the background to detect and fix cold stale data without scanning raw records.

- **Detail Sloppy Quorums and Hinted Handoff**: Explain that Sloppy Quorums preserve write availability during network partitions by writing hints to temporary fallback nodes, but temporarily compromise strong consistency until handoff completes.

#### Differentiate Cassandra/Dynamo Quorums from Paxos/Raft Quorums:

- **Cassandra/DynamoDB**: Uses client/coordinator-level tunable quorums ($W+R$) per query over eventual storage.

- **Paxos/Raft**: Requires a hard mathematical strict majority ($Q = \lfloor N/2 \rfloor + 1$) on every internal consensus log entry to maintain strict linearizability.
