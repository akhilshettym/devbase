## Consensus Algorithms (Paxos, Raft)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a board of five executives sitting in different countries holding an urgent, binding vote over noisy, unstable phone lines:

- **The Unreliable Network Problem**: Phone calls frequently drop, static cuts out voices, and messages are delayed. If Executive A yells, "Sell the asset for $\$10\text{ million}$!", but Executive B's phone disconnects, Executive B doesn't know if a decision was made.

- **The Consensus Solution (Paxos / Raft)**: To ensure everyone agrees on the exact same action without two conflicting decisions being made simultaneously:

- A single Leader is elected by receiving votes from a majority of executives ($3$ out of $5$).

- Any proposed decision must be written down, distributed, and acknowledged by at least $3$executives before it becomes legally binding (Committed).

- Even if $2$ executives drop offline permanently, the remaining $3$ can safely continue making binding decisions without risking data corruption.

#### The Core Problem Solved:

- In a distributed database or state machine cluster, individual server nodes can crash, restart, or experience network partitions at any time.

- Consensus Algorithms (such as Paxos and Raft) solve the fundamental problem of reaching agreement on a single data value or a sequence of state machine updates across a cluster of untrusted, failure-prone network nodes. They guarantee that as long as a strict majority of nodes remain healthy, the cluster acts as a single, perfectly consistent, fault-tolerant unified system.

---

### 2. The Basics (Scratch Level):

#### Crash Fault Tolerance (CFT) vs. Byzantine Fault Tolerance (BFT)

#### Consensus protocols fall into two distinct security models:

- **Crash Fault Tolerant (CFT - Paxos, Raft)**: Assumes network nodes may crash, restart, or drop/delay network packets, but nodes are honest (i.e., they follow protocol rules and do not lie, forge messages, or act maliciously). Used in trusted infrastructure (e.g., Etcd, Google Chubby, Consul, CockroachDB).

- **Byzantine Fault Tolerant (BFT - PBFT, Tendermint)**: Assumes nodes can be actively malicious or compromised, actively sending conflicting messages to different peers. Used in untrusted peer-to-peer networks (e.g., Blockchains).

#### The Quorum Math of Fault Tolerance:

To tolerate up to $f$ physical node crashes in a CFT consensus cluster, the total cluster size $N$ must satisfy:

$$N = 2f + 1$$
A valid decision requires a Quorum (Majority) of active nodes:

$$\text{Quorum Size} = \lfloor \frac{N}{2} \rfloor + 1 = f + 1$$

| Total Nodes (N) | `Max Tolerable Failures (f)` | `Majority Quorum Required` | `Why Even Node Counts (e.g., N=4) Add No Value`                                                 |
| --------------- | ---------------------------- | -------------------------- | ----------------------------------------------------------------------------------------------- |
| **3**           | 1                            | 2                          | Can survive $1$ node crash.                                                                     |
| **4**           | 1                            | 3                          | Requires $3$ nodes for quorum; still tolerates only $1$failure, but increases network overhead! |
| **5**           | 2                            | 3                          | Can survive $2$ simultaneous node crashes. Ideal production setup.                              |
| **7**           | 3                            | 4                          | High fault tolerance for cross-datacenter deployments.                                          |

**Key Rule**: Always deploy CFT consensus clusters with an odd number of nodes ($3, 5, 7$). An even number increases split-brain risks during network partitions without increasing the cluster's failure tolerance.

#### Core Consensus Properties:

Every correct consensus algorithm must guarantee two properties despite network failures:

- **Safety (Nothing Bad Happens)**: No two non-faulty nodes ever commit different values for the same log position.

- **Liveness (Something Good Eventually Happens)**: As long as a majority of nodes are operational ($f+1$), the cluster eventually accepts new updates and recovers from node failures.

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. Basic Paxos vs. Multi-Paxos Mechanics:

Formulated by Leslie Lamport, Paxos is the foundational consensus protocol.

#### BASIC PAXOS (Two-Phase Protocol for a Single Consensus Value)

```
PROPOSER                ACCEPTORS (Quorum = 2/3)
│                                  │ │
├─────── 1a. Prepare(n=101) ──────►│ │ (Phase 1: Leader Election / Proposal Lock)
│◄────── 1b. Promise(n=101) ───────┤ │ Promises not to accept proposals < 101
│                                  │ │
├─────── 2a. Accept(n=101, v="A")─►│ │ (Phase 2: Replication & Commit)
│◄────── 2b. Accepted(n=101, v="A")┤ │ Value "A" is officially Committed!
```

#### Roles:

- **Proposer**: Advocates for a client value.
- **Acceptor**: Acts as the consensus memory/voter.
- **Learner**: Reads committed values.

- **The Flaw of Basic Paxos**: Reaching agreement on a single value requires $2$ full network round-trips ($2\text{ RTTs}$). If two proposers concurrently send competing proposals with higher proposal numbers ($n$), they enter a Duel (Livelock) where neither value ever commits.

- Multi-Paxos Solution: Elects a single persistent Leader Proposer via Phase 1. Subsequent log entries skip Phase 1 entirely, streaming updates via Phase 2 in a single network round-trip ($1\text{ RTT}$).

#### 2. Raft Consensus Protocol (Designed for Understandability):

Created by Ongaro and Ousterhout, Raft decomposes Multi-Paxos into three explicit, independent sub-problems: Leader Election, Log Replication, and Safety.

```
                     RAFT NODE STATE TRANSITION MACHINE

                 [ Follower ] ──(Times out, starts election)──► [ Candidate ]
                      ▲                                               │
                      │                                     (Wins Majority Votes)
                      │                                               │
                      └─────────(Discovers new Leader)────────────────┴──► [ Leader ]
```

#### A. Leader Election Phase:

- All nodes start as Followers. Every node runs a randomized Election Timeout ($150\text{ms} - 300\text{ms}$).
- If a follower hears no heartbeat (AppendEntries RPC) before its timeout expires, it transitions to a Candidate, increments its Term ($T$), votes for itself, and broadcasts RequestVote RPCs.
- A candidate wins if it collects votes from a majority of cluster nodes. It immediately assumes the Leaderrole and begins sending heartbeats to prevent new elections.

#### B. Log Replication Phase:

```
Leader Log:     [ T1, x=5 ] [ T1, y=2 ] [ T2, z=9 ] (Commit Index = 3)
                      │           │           │
                      ▼           ▼           ▼
Follower 1 Log: [ T1, x=5 ] [ T1, y=2 ] [ T2, z=9 ] (In Sync)
Follower 2 Log: [ T1, x=5 ] [ T1, y=2 ] [ Uncommitted ] (Replication in Progress)
```

- Clients send commands exclusively to the Leader.

- The leader appends the command to its local log and broadcasts an AppendEntries RPC containing the log entry, its index, term, and the prevLogIndex/prevLogTerm.

- Followers verify log continuity. Once the entry is replicated on a majority of nodes, the leader marks the entry as Committed, applies it to its local state machine, and returns the result to the client.

#### C. Raft Safety Invariants:

- **Election Safety**: At most one leader can be elected per Term ($T$).
- **Leader Append-Only**: A leader never overwrites or truncates its own log entries; it only appends new ones.
- **Log Matching Property**: If two logs contain an entry with the exact same index and term, they are identical in all entries up through the given index.
- **Leader Completeness**: If a log entry is committed in a given term, that entry will be present in the logs of the leaders for all higher-numbered terms. (Enforced because voters reject candidates whose log is less up-to-date than their own).

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Read Optimizations: Bypassing Log Replication for Reads

Executing a full consensus log replication loop for a simple READ query severely degrades database read throughput. Raft engines use two advanced techniques to serve linearizable reads safely from local memory:

#### Read-Index Optimization:

- The leader records its current commitIndex as readIndex.
- To ensure it hasn't been deposed by a network partition without its knowledge, the leader sends a low-overhead heartbeat (AppendEntries) to a majority of nodes.
- Once the majority acknowledges its leadership, the leader waits until its state machine applies changes up to readIndex, then serves the read locally ($0$ log writes).

#### Lease Reads (Clock-Bound Optimization):

- The leader acquires a time-bound lease duration during which no other node can start an election (e.g., $500\text{ms}$).
- As long as physical clock drift across cluster nodes is strictly bounded within a drift margin ($\Delta t$), the leader serves linearizable reads locally with zero network communication during the lease window.

#### Dynamic Cluster Membership (Joint Consensus):

Changing cluster configuration (e.g., replacing a failed hardware node or scaling from $3 \to 5$ nodes) while the database is live creates a risk: if done naively, two separate majorities could form simultaneously (a Split-Brain condition).

```
DANGER: NAIVE MEMBERSHIP CHANGE (3 Nodes -> 5 Nodes)
Old Configuration (3 Nodes): Quorum = 2 ==> Nodes A & B form Majority
New Configuration (5 Nodes): Quorum = 3 ==> Nodes C, D, E form Majority
RESULT: Two independent majorities operate concurrently!
```

#### Joint Consensus Strategy:

During configuration transitions, Raft uses an intermediate two-phase configuration $C_{\text{old}, \text{new}}$. Any log entry or election decision must collect a majority from BOTH the old configuration $C_{\text{old}}$ AND the new configuration $C_{\text{new}}$ independently before switching permanently to $C_{\text{new}}$.

---

### 5. Text-Based Architecture Diagram:

```
             RAFT LOG REPLICATION & CONSENSUS COMMIT FLOW (N = 5 Nodes)
==================================================================================

[ Client ] ───(1. Write: "SET val=42")───► [ LEADER (Node 1) ]
                                         │
┌────────────────────────────────────────┼────────────────────────────────────────┐
│ (2. AppendEntries RPC)                 │ (2. AppendEntries RPC)                 │
▼                                        ▼                                        ▼
[ FOLLOWER (Node 2) ]            [ FOLLOWER (Node 3) ]                  [ FOLLOWER (Node 4) ]
(Writes to Log) (Writes to Log)                                         (Network Partitioned)
│                                        │                                        │
└───────────────────┬────────────────────┘                                        │
                    │      (3. Returns ACK: Log Appended)                         │
                    ▼                                                             ▼
         [ LEADER (Node 1) ]                                             [ FOLLOWER (Node 5) ]
      (Replicated on 3/5 Nodes)                                         (Offline / Unreachable)
          *QUORUM REACHED!*
                    │
                    ├───► 4. Advances commitIndex = 104
                    ├───► 5. Applies "val=42" to State Machine
                    ├───► 6. Returns "SUCCESS" to Client
                    │
                    └───► 7. Next Heartbeat notifies Followers to Apply commitIndex = 104
==================================================================================
```

---

### 6. Interview Checklist:

- **State the Quorum Formula Instantly**: Always cite $N = 2f + 1$ when asked about fault tolerance. Explicitly clarify that a 5-node cluster survives $2$ node failures because a majority of $3$ nodes remains operational.

- **Explain the Paxos vs. Raft Paradigm Shift**: Explain that while Paxos is mathematically foundational, its basic form suffers from livelocks and requires Multi-Paxos for practical use. Raft introduces formal state machines, randomized election timeouts, and strict leader invariants for implementable safety.

- **Detail the Raft Election Safety Invariant**: Explain why a candidate cannot win an election unless its log is at least as up-to-date as the voter's log. This prevents new leaders from overwriting committed historical logs.

- **Pitch Read Optimizations for Senior Architecture Questions**: When asked how to scale reads on consensus stores (like Etcd or Consul), explain Read-Index (heartbeat validation) and Lease Reads(time-bounded leader leases) to avoid log append overhead.

- **Differentiate CFT from BFT**: Note that CFT protocols (Raft/Paxos) assume honest non-malicious nodes, making them ideal for high-throughput private enterprise infrastructure, while BFT is required for untrusted public blockchain environments.
