## Load Balancing Algorithms (Stateless & Stateful)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Load balancing algorithms dictate the core logic a load balancer uses to pick which backend node receives the next connection or request. Selecting the wrong algorithm can lead to severe resource imbalances, hot-spotting, latency spikes, or broken application sessions—even when total system capacity seems sufficient on paper.

```
+-----------------------------------------------------------------------------------+
|                   Real-World Analogy: Supermarket Checkout Lines                  |
+-----------------------------------------------------------------------------------+
| Stateless Routing: Blind Station Rotation                                         |
| - A ticket manager hands customers numbered tickets (1, 2, 3, 1, 2, 3...) to      |
|   counters in exact sequence, without looking at how many items are in each       |
|   customer's shopping cart.                                                       |
|                                                                                   |
| Stateful / Dynamic Routing: Smart Line Coordinator                                |
| - A coordinator checks line lengths, item counts, and cashier processing speeds   |
|   before routing the next customer. Alternatively, if a customer left a receipt   |
|   on a specific counter, they are routed back to that exact cashier.              |
+-----------------------------------------------------------------------------------+
```

- **Stateless Algorithms**: Make routing decisions strictly from fixed rules, static weights, or request metadata (e.g., client IP address) without querying real-time backend state or connection tracking tables. They are ultra-fast, require near-zero CPU/memory overhead, but can accidentally overload slower backends handling long-lived requests.

- **Stateful & Dynamic Algorithms**: Make routing decisions by tracking active real-time health metrics(e.g., open TCP connections, request latency, CPU load) or by maintaining session mapping tables(e.g., sticky cookie affinity, hash rings). They distribute load more evenly across heterogeneous,fluctuating traffic, but require more CPU memory and metric synchronization overhead.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Node Weight**: A static integer assigned to a server reflecting its hardware capacity relative to other servers (e.g., a server with 32 cores gets weight 4; a server with 8 cores gets weight 1).
- **Session Affinity (Sticky Sessions)**: A routing constraint forcing all subsequent requests from a specific client session to route to the exact same backend instance that handled the initial request.
- **Hash Ring**: A conceptual 32-bit circular space ($0$ to $2^{32}-1$) used in consistent hashing to evenly distribute keys across servers while minimizing key re-mappings when servers scale up or down.
- **Virtual Nodes (VNodes)**: Multiple pseudo-random points on a hash ring assigned to a single physical server to prevent uneven key distribution (hotspots).

#### Algorithms Comparison Matrix:

| Algorithm               | `Category`    | `Routing Basis`                    | `Overhead` | `Primary Use Case`                            | `Key Weakness`                            |
| ----------------------- | ------------- | ---------------------------------- | ---------- | --------------------------------------------- | ----------------------------------------- |
| **Round Robin (RR)**    | Stateless     | Sequential index rotation          | Zero       | Equal capacity, short stateless requests      | Ignores backend load & request duration   |
| **Weighted RR (WRR)**   | Stateless     | Static capacity weight ratio       | Near-Zero  | Heterogeneous server hardware specs           | Burst traffic overloads high-weight nodes |
| **Source IP Hash**      | Stateless     | Hash(Client_IP) % N                | Low        | Simple session persistence without cookies    | Breaks behind NAT proxies / CGNAT         |
| **Least Connections**   | Stateful      | Min active connection count        | Low        | Long-lived TCP/HTTP streams (e.g., WebSocket) | Slow-start servers get flooded instantly  |
| **Least Response Time** | Dynamic       | Active connections $\times$Latency | Medium     | Latency-sensitive microservice meshes         | Requires continuous health metric probing |
| **Consistent Hashing**  | Stateful/Ring | Key placement on hash ring         | Low–Medium | Stateful caches (Redis/Memcached), Storage    | Ring reassignment can cause cache dips    |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Execution Logic:

#### 1. Stateless Algorithms: Mechanics & The Smooth Weighted Round Robin:

A basic Round Robin uses an atomic integer incremented mod $N$: $i = (i + 1) \pmod N$.

However, standard Weighted Round Robin suffers from burstiness. If Server A has weight 5, Server B has weight 1, and Server C has weight 1, standard WRR routes 5 consecutive requests to A (AAAAABC). Server A gets hit with a sudden queue burst.

To solve this, engines like NGINX use the Smooth Weighted Round Robin algorithm:

$$\text{current\_weight} = \text{current\_weight} + \text{effective\_weight}$$
$$\text{selected\_node} = \max(\text{current\_weight})$$
$$\text{selected\_node.current\_weight} = \text{selected\_node.current\_weight} - \sum \text{effective\_weights}$$

```
Weights: A=5, B=1, C=1 (Total Weight = 7)
Req # | Current Weights Before Selection | Selected Node | Current Weights After Penalty
------+----------------------------------+---------------+------------------------------
1    | [A:5, B:1, C:1]                 | A (max 5)     | [A:-2, B:1, C:1]
2    | [A:3, B:2, C:2]                 | A (max 3)     | [A:-4, B:2, C:2]
3    | [A:1, B:3, C:3]                 | B (max 3)     | [A:1,  B:-4, C:3]
4    | [A:6, B:-3, C:4]                | A (max 6)     | [A:-1, B:-3, C:4]
5    | [A:4, B:-2, C:5]                | C (max 5)     | [A:4,  B:-2, C:-2]
6    | [A:9, B:-1, C:-1]               | A (max 9)     | [A:2,  B:-1, C:-1]
7    | [A:7, B:0,  C:0]                | A (max 7)     | [A:0,  B:0,  C:0]

Resulting Sequence: A -> A -> B -> A -> C -> A -> A (Perfectly smoothed, zero burstiness!)
```

#### 2. Stateful Algorithms: Connection Tracking Tables:

The Least Connections algorithm maintains an in-memory hash table inside the load balancer's atomic kernel space tracking active concurrent sockets ($\text{active\_conns}[s]$).

```
         Incoming Request ──> [ Least Connections Router ]
                                      │
                        Reads Active Connection Counter
                                      │
                 ┌────────────────────┼────────────────────┐
                 ▼                    ▼                    ▼
         [ Server Node A ]    [ Server Node B ]    [ Server Node C ]
         Active Conns: 42     Active Conns: 12     Active Conns: 89
                                      │
                                      └─► Assigns request to Server B!
                                          (Increments Server B counter to 13)
```

- When a new connection arrives, the LB finds $\min(\text{active\_conns}[s])$. When a TCP FIN/RST frame or HTTP response finishes, the counter decrements.

#### 3. Consistent Hashing & Hash Ring Mechanics:

Traditional hashing uses modulo arithmetic: $\text{server\_index} = \text{hash}(\text{key}) \pmod N$.

If $N$ changes (a server crashes or scales out from 10 to 11 nodes), almost 100% of keys remap to new servers, causing massive cache misses (a cache stampede).

Consistent Hashing (Ketama Algorithm) maps both backend servers and request keys onto a $2^{32}-1$ring:

```
                         HASH RING (0 to 2^32 - 1)

                               Node_A_v1 (1000)
                                   /     \
               (Key 3 maps to C)  /       \   Node_B_v1 (10,000)
              Key_3 (3,800,000)  /         \
                                |           |
              Node_C_v1         |           |  Key_1 (15,000)
            (2,500,000)         |           |  (Key 1 maps to B)
                                 \         /
               (Key 2 maps to C)  \       /   Node_A_v2 (1,000,000)
              Key_2 (2,100,000)    \     /
                                    \   /
```

- **Mapping**: Servers are hashed by hostname/IP onto the ring. Keys (e.g., user_id or session_id) are hashed onto the same ring.
- **Lookup**: A key routes to the first server node encountered moving clockwise.
- **Adding/Removing Nodes**: If Node B fails, only keys mapping to Node B move to Node C. All other key mappings remain intact.
- **Virtual Nodes (VNodes)**: To prevent uneven ring distribution, each physical server is mapped to multiple pseudo-random points (e.g., 100–250 VNodes per server) on the ring.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Performance Engineering, Edge Cases & Failure Modes:

#### 1. The "Least Connections" Slow-Start Thundering Herd:

- **The Failure Mode**: When a new, cold server instance joins an existing pool under heavy load, its active connection count is 0. The Least Connections algorithm immediately routes every single incoming request to this new server. The cold instance, lacking warm caches or pre-allocated socket pools, gets overwhelmed and crashes.
- **Mitigation (Slow Start Weight Ramp-Up)**: Dynamically scale a new node's weight exponentially over time ($Weight(t) = Weight_{max} \times (1 - e^{-t/\tau})$) when it first passes health checks, slowly ramping its traffic share.

#### 2. The Power of Two Random Choices (P2C / Pick-Two):

- **The Problem with Global Least Connections**: At high throughput across distributed L7 proxy clusters (e.g., 50 Envoy nodes), reading global least-connection counters requires lock-contention or state synchronization delays. Out-of-date metrics cause all 50 proxies to route traffic to the same "least loaded" server simultaneously, instantly turning it into the most overloaded node.

#### The Algorithmic Fix (P2C): Instead of scanning all $N$ servers for the absolute minimum load:

- Randomly pick two nodes ($Node_X$, $Node_Y$) from the pool.
- Compare their current load/latency.
- Route the request to the less loaded of the two.

Mathematical Intuition: P2C cuts maximum queue length exponentially from $O\left(\frac{\log N}{\log \log N}\right)$ to $O(\log \log N)$ with zero global locking overhead and $O(1)$ lookup time!

Standard Least Conns (Requires scanning all N nodes):

```
[ Node 1 ] [ Node 2 ] [ Node 3 ] ... [ Node 1000 ]  --> High Metric Sync Overhead!
```

#### Power of Two Random Choices (P2C):

1. Sample Node 42 (Active Conns: 15)
2. Sample Node 881 (Active Conns: 4)
3. Direct request to Node 881! --> O(1) Speed, Zero Lock Contention!
4. Peak EWMA (Exponentially Weighted Moving Average)

Standard Least Latency uses simple arithmetic mean latency, which reacts too slowly to sudden queue build-ups. Modern Envoy / Finagle proxies use Peak EWMA:

$$\text{Cost} = \text{ActiveConns} \times \text{EWMA}(\text{ResponseTime})$$
$$\text{EWMA}_t = \alpha \cdot \text{RTT}_{current} + (1 - \alpha) \cdot \text{EWMA}_{t-1}$$

Peak EWMA heavily penalizes recent latency spikes while factoring in current queue depth, routing traffic away from degrading nodes before hard health-check timeouts trigger.

---

### 5. Text-Based Architecture Diagram:

```
Routing Decision Engine: Stateful Dynamic Proxy Architecture
===================================================================================
                                INCOMING REQUEST
===================================================================================
                                      │
                          HTTP Request / gRPC Stream
                                      │
                                      ▼
===================================================================================
                   LAYER 7 PROXY LOAD BALANCER ENGINE (Envoy)
===================================================================================
                                      │
           ┌──────────────────────────┴──────────────────────────┐
           │ Is Session Cookie or Hash Key Present in Request?   │
           └──────────────────────────┬──────────────────────────┘
                                      │
                     ┌────────────────┴────────────────┐
                YES  │                                 │ NO
                     ▼                                 ▼
  +------------------------------------+   +------------------------------------+
  |  CONSISTENT HASHING ROUTER         |   |  DYNAMIC METRIC ROUTER (P2C)       |
  |  1. Hash(Cookie Key)               |   |  1. Randomly Pick Node A & Node B  |
  |  2. Walk Clockwise on Hash Ring    |   |  2. Read ActiveConns * Peak EWMA   |
  |  3. Select Target VNode            |   |  3. Select Node with Lower Cost    |
  +------------------------------------+   +------------------------------------+
                     │                                 │
                     └────────────────┬────────────────┘
                                      │
                                      ▼
===================================================================================
                          HEALTH CHECK & CIRCUIT BREAKER
===================================================================================
                                      │
            ┌─────────────────────────┴─────────────────────────┐
            │ Is Selected Target Healthy & Under Concurrency Max│
            └─────────────────────────┬─────────────────────────┘
                                      │
                     ┌────────────────┴────────────────┐
                YES  │                                 │ NO (Panic Mode)
                     ▼                                 ▼
        [ Route Request to Target ]        [ Shed Load / Route to Fallback ]
```

---

### 6. Interview Checklist:

When discussing Load Balancing Algorithms in system design interviews:

Match Algorithms to Architecture Constraints:

- **Stateless Round Robin / WRR**: Use for simple stateless Web APIs with homogeneous hardware and short, uniform processing times.

- **Least Connections / Peak EWMA**: Use for long-lived streams (WebSockets, gRPC, DB connections) or services with highly variable request execution times.

- **Consistent Hashing**: Use strictly for stateful caches (Redis/Memcached), session affinity, or partitioned database storage nodes.

- **Proactively Offer P2C (Power of Two Random Choices)**: When designing high-throughput distributed microservice meshes (e.g., Envoy sidecars), explicitly recommend P2C with Peak EWMA over global Least Connections to eliminate proxy lock contention and thundering herd failures.

- **Address Cold-Start / Thundering Herd Edge Cases**: Demonstrate operational depth by pointing out that stateful algorithms (Least Connections) require Slow Start ramp-up weights to prevent newly spawned instances from getting overwhelmed.

- **Explain Virtual Nodes in Consistent Hashing**: Never just say "Consistent Hashing." Mention that Virtual Nodes (VNodes) are mandatory to ensure uniform key distribution across the ring and prevent hot-spotting physical nodes.
