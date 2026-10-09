## System Performance Metrics (Latency, Throughput, Bandwidth)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Think of a highway system transporting commuters:

- **Bandwidth**: The total number of lanes on the highway. It defines the maximum capacity of vehicles that could travel side-by-side at any given instant.

- **Latency**: The total time (in minutes) it takes for a single car to travel from the on-ramp (client) to the off-ramp (server).

- **Throughput**: The actual number of cars passing through the toll booth per hour. High bandwidth doesn't guarantee high throughput if there is a severe bottleneck at the toll booth or traffic jam along the route.

#### The Core Problem Solved:

- System design is fundamentally an exercise in resource constraint management. Engineers must balance speed (how fast a single operation completes) against capacity (how many operations a system can complete concurrently) within physical hardware limits (speed of light in fiber, CPU clock speeds, network bus speeds).
- Failing to analyze these three metrics together leads to disastrous architectural choices—such as throwing bandwidth (larger network pipes) at a latency problem (slow database queries), or optimizing for low latency while causing microservice queue saturation under high throughput.

---

### 2. The Basics (Scratch Level):

#### Core Definitions & Units:

| Metric         | `Defination`                                                                                | `Standard Units`                                                                    | `Analogy Primitive` |
| -------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------- |
| **Latency**    | Time taken for a single request to travel from sender, be processed, and return a response. | Milliseconds ($\text{ms}$), Microseconds ($\mu\text{s}$)                            | Transit Duration    |
| **Throughput** | Rate of successfully processed work or requests delivered by the system per unit of time.   | Requests Per Second ($\text{RPS}$), Queries Per Second ($\text{QPS}$), $\text{TPS}$ | Flow Rate           |
| **Bandwidth**  | Theoretical maximum data transfer capacity of a hardware or network channel.                | Bits per second ($\text{bps}$, $\text{Gbps}$), Bytes per second ($\text{MB/s}$)     | Pipe Width          |

#### Key Terminology:

- **RTT (Round-Trip Time)**: Network-only propagation delay for a signal to go from client to server and back, excluding server processing time.
- **Concurrency**: The total number of active requests currently inside the system boundaries being processed simultaneously.
- **Saturation / Knee Point**: The operational threshold where throughput plateaus because system utilization approaches 100%, causing incoming requests to queue, which inflates latency exponentially.

---

### 3. Deep Dive & Architecture (Mid Level):

#### Little's Law & Concurrency Mechanics:

In queuing theory, Little's Law defines the mathematical relationship between Concurrency ($L$), Throughput ($\lambda$), and Latency ($W$):

$$L = \lambda \times W$$

- $L$ (Concurrency): Number of active requests currently in the system.
- $\lambda$ (Throughput): Requests completed per second ($\text{RPS}$).
- $W$ (Latency): Average duration a request stays in the system ($\text{seconds}$).

#### Practical Calculation Example:

- If an API service processes requests with an average latency of $50\text{ ms}$ ($0.05\text{ seconds}$) and needs to handle a target throughput of $20,000\text{ RPS}$, the system must maintain:

$$L = 20,000 \times 0.05 = 1,000 \text{ concurrent connections/threads}$$

- If your web server worker thread pool is capped at 500 threads, the system will hit queue saturation, doubling latency or dropping requests regardless of available network bandwidth.

#### Latency Distribution: Percentiles vs. Averages:

Average (mean) latency is a dangerous metric because latency distributions are heavily right-skewed with extreme long-tail outliers.

```
Request Count
│ P50 (Median)
│ │ P90 P99 P99.9 (Tail Latency)
│ ┌──┴──┐ │ │ │
│ ┌┘ └┐ │ │ │
│ ┌┘ └┐ │ │ │
└───┴─────────┴───┴──────┴───────┴──────── Latency (ms)
```

- **P50 (Median)**: $50\%$ of requests are faster than this duration. Represents the typical user experience.
- **P95 / P99**: $95\%$ or $99\%$ of requests are faster than this duration. Represents tail latency experienced during load spikes, GC pauses, or lock contention.

- **The Amplification Effect in Microservices**:
  If a single user request fans out to 100 downstream microservices in parallel, each with a P99 latency of $100\text{ ms}$, the probability $P$ that the overall request experiences a P99 delay is:

$$P(\text{Tail Latency}) = 1 - (0.99)^{100} = 1 - 0.366 = 63.4\%$$

- Over $63\%$ of user requests will experience tail latency delays.

#### Bandwidth-Delay Product (BDP):

The Bandwidth-Delay Product dictates how much unacknowledged data can be "in flight" across a network pipeline at any instant:

$$\text{BDP (bits)} = \text{Bandwidth (bits/sec)} \times \text{RTT (sec)}$$
If BDP is $10\text{ Gbps} \times 50\text{ ms} = 500\text{ Mb}$ ($62.5\text{ MB}$), but your TCP Receive Window (rwnd) size is capped at $2\text{ MB}$, the connection will stall waiting for ACK packets, utilizing less than $4\%$ of available line bandwidth.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Crucial Architectural Trade-offs:

#### 1. Latency vs. Throughput (The Batching Dilemma):

To maximize throughput, **systems aggregate multiple individual events into batches** (e.g., Kafka producers, SQL bulk inserts). Batching reduces CPU context switching and network header overhead per record. However, delaying execution until a batch fills directly increases latency for the first item added to the batch.

```
High Latency, High Throughput <=========> Low Latency, Low Throughput
(Large Batches / Async Queues) (Immediate RPC / Per-Request I/O)
```

#### 2. Bandwidth vs. Latency:

Increasing bandwidth (e.g., upgrading from $1\text{ Gbps}$ to $10\text{ Gbps}$ fiber) increases total payload throughput, but does not reduce latency bounded by physical distance (speed of light in glass $\approx 200\text{ km/ms}$) or application processing logic.

#### Failure Modes & Edge Cases:

**Queuing Delay Escalation (M/M/1 Queue Model)**:

As system utilization ($\rho = \frac{\text{Arrival Rate}}{\text{Service Rate}}$) approaches $1.0$ ($100\%$capacity), average wait time in the queue scales non-linearly:

$$W_{\text{queue}} = \frac{\rho}{\mu(1 - \rho)}$$

Operating a cluster at $90\%$ utilization causes $9\times$ higher queuing latency compared to running at $50\%$ utilization.

```
Queuing Delay
│ / (Approaches Infinity as Utilization -> 100%)
│ /
│ /
│ /
│ /
│******\*\*******\_\_\_******\*\*******/
0% 90% 100% System Utilization
```

**Coordinated Omission**:

A critical benchmarking bug where load-testing tools generate requests on a single thread sequentially. If the server stalls for 10 seconds (e.g., JVM Stop-The-World GC), the load generator halts sending new requests during those 10 seconds. This omits thousands of blocked requests from the measurement dataset, artificially deflating the reported P99 latency percentiles.

**Mitigation**: Use benchmarking frameworks that generate requests on a strict coordinate-time schedule independent of response delivery (e.g., wrk2, HDR Histogram).

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
           SYSTEM PERFORMANCE METRICS IN REQUEST FLOW PIPELINE
================================================================================

[ Client ]
   │
   │ 1. BANDWIDTH BOUNDARY (Physical Link Capacity - Gbps)
   │    Data in Flight = Bandwidth * RTT (TCP Window Size)
   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ [ Edge Load Balancer / API Gateway ]                                         │
│                                                                              │
│ 2. LATENCY BOUNDARY (Total Client RTT = T_network + T_queue + T_service)     │
│                                                                              │
│    │-- Network Transit (RTT/2) --│                                           │
│                                  ▼                                           │
│                       ┌─────────────────────┐                                │
│                       │ Request Queue       │ <── 3. QUEUING DELAY           │
│                       │ (M/M/1 Queue Model) │     (Scales near 100% CPU)    │
│                       └──────────┬──────────┘                                │
│                                  │                                           │
│                                  ▼                                           │
│                       ┌─────────────────────┐                                │
│                       │ Thread Pool Workers │ <── 4. CONCURRENCY (L)         │
│                       │ (Active Processing) │     (L = Throughput * Latency) │
│                       └──────────┬──────────┘                                │
│                                  │                                           │
│                                  ▼                                           │
│                        [ Database / Cache ]                                  │
└──────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
                  5. THROUGHPUT OUTFLOW (Realized RPS / QPS)
================================================================================
```

---

### 6. Interview Checklist:

- **Never Quote "Average Latency"**: Immediately frame performance discussions around tail latency percentiles (P95, P99, P99.9). Explain how fan-out microservice architectures compound tail latency risks across downstream calls.

- **Apply Little's Law for Sizing**: Calculate thread pool sizes, connection pool limits, or pod replica counts live in the interview using $L = \lambda \times W$. Prove how many concurrent connections are needed to sustain a target RPS before picking instance specs.

- **Proactively Discuss the Latency vs. Throughput Trade-off**: When designing high-volume stream ingestion (e.g., logging, metrics, chat streams), explicitly state where you choose to trade latency for throughput using batching, micro-batching, and asynchronous write rings (e.g., LMAX Disruptor pattern).

- **Identify Bottlenecks Before Re-architecting**: Distinguish between a system bounded by network bandwidth, CPU execution time, memory capacity, or queue starvation. Explicitly explain that expanding network bandwidth will fail to fix CPU-bound or database lock contention issues.
