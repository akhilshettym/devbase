## Throughput vs Latency

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

- **Latency is a Sports Car**: A sports car carries 2 passengers from City A to City B in 15 minutes. The individual transit time for a passenger is extremely fast (low latency), but the car moves only 8 passengers per hour (low throughput).

- **Throughput is a High-Speed Commuter Train**: A train carries 600 passengers from City A to City B in 45 minutes. Individual transit time is slower (higher latency), but the train moves 800 passengers per hour (high throughput).

- If you need to move a single VIP instantly, you send the sports car (Latency Optimization). If you need to move an entire stadium crowd during rush hour, you dispatch the train (Throughput Optimization).

#### The Problem It Solves:

- Engineers often assume that "high performance" means making a system as fast as possible for a single request. However, hardware resources (CPU cores, memory bandwidth, network sockets, disk I/O) are finite.

- Optimizing for Latency focuses on minimizing the round-trip execution time for an individual task. This often requires leaving hardware under-utilized or avoiding batching so that incoming requests execute instantly without waiting in queues.

- Optimizing for Throughput focuses on maximizing the total volume of work processed per unit of time. This requires saturating hardware queues, batching operations, and pipelining execution—which intentionally delays individual tasks to amortize system overhead.

- **System design requires balancing this fundamental architectural trade-off**: optimizing for maximum throughput almost always increases individual task latency, while driving latency to absolute minimums reduces overall system throughput capacity.

---

### 2. The Basics (Scratch Level):

#### Core Definitions

```
LATENCY
[ Request Initiated ] ─────── (Time Elapsed: e.g., 12ms) ───────► [ Response Received ]
* Measures speed per task. Units: Milliseconds (ms), Microseconds (μs).
```

```
THROUGHPUT
[ Unit of Time: 1 Second ] ──► [ Req 1 ][ Req 2 ][ Req 3 ] ... [ Req 10,000 ]
* Measures capacity over time. Units: Requests Per Second (RPS), Transactions Per Second (TPS), Bits Per Second (BPS).
```

#### Little's Law: The Fundamental Equivalence:

In queuing theory, Little's Law mathematically links latency, throughput, and system concurrency:

$$L = \lambda \cdot W$$

Where:

- $L$ = Concurrency (number of requests currently being processed in the system).
- $\lambda$ = Throughput (arrival rate of requests per unit time).
- $W$ = Latency (average time a request spends in the system).

- **Architectural Implication**: To increase throughput ($\lambda$) while keeping latency ($W$) low, system concurrency ($L$) must increase proportionally (e.g., adding worker threads or scaling out nodes). If concurrency reaches hardware saturation, any further increase in arrival rate increases $W$ (latency) as requests stack up in waiting queues.

#### Comparative Matrix:

| Dimension                | `Latency-Optimized System`                                                      | `Throughput-Optimized System`                                               |
| ------------------------ | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| **Primary Goal**         | Minimize $p95 / p99$ response time per user.                                    | Maximize total tasks/bytes processed per second.                            |
| **Batching Strategy**    | Disabled / Minimal. Process items immediately upon arrival.                     | Heavy Aggregation. Buffer requests into large batches before flush.         |
| **Hardware Utilization** | Kept intentionally low (~30% - 50% CPU) to handle burst spikes without queuing. | Kept near maximum (~80% - 90% CPU) to extract maximum work per clock cycle. |
| **Primary Bottleneck**   | Network hops, lock contention, context switching.                               | Memory bandwidth, disk I/O saturation, network link bandwidth.              |
| **Target Workloads**     | High-Frequency Trading, Interactive Search, Mobile APIs, Real-time Gaming.      | Video Encoding, Log Aggregation, ETL Pipelines, Data Lakehouse Ingestion.   |

---

### 3. Deep Dive & Architecture (Mid Level):

#### The Batching Trade-off Curve (batch.size vs linger.ms):

The most common architectural knob for tuning throughput versus latency is Batching (e.g., in Apache Kafka producers, database bulk inserts, or network packet framing).

```
         LATENCY & THROUGHPUT VS BATCH SIZE
  Latency (ms) ▲                                 ▲ Throughput (RPS)
               │                                /│
  High Latency │                      .--------' │ High Throughput
               │                 .---'           │
               │            .---'                │
               │       .---'                     │
   Low Latency │  .---'                          │ Low Throughput
               └─────────────────────────────────┴────────►
               Small (Immediate)            Large (Batched)
                              Batch Size
```

- **Small Batch Size (Low Latency / Low Throughput)**: Every record is wrapped in a network frame,acquires a lock, writes to a database log, and executes a system call independently. Amortized system overhead per byte is extremely high, choking total throughput, but each record is delivered immediately.

- **Large Batch Size (High Throughput / High Latency)**: Thousands of records share a single network frame, single lock acquisition, and single sequential disk write. System overhead per byte drops to near zero, driving throughput to hardware limits. However, the first record in the batch must wait in memory while the batch accumulates (Batch Ingress Delay).

#### Parameter Tuning Example (Kafka Producer)

- **linger.ms = 0**: Dispatches records instantly. Minimizes latency, severely limits max throughput.

- **linger.ms = 50, batch.size = 128KB**: Waits up to 50ms to fill a 128KB buffer. Increases latency by up to 50ms, but boosts throughput by 10x–50x.

#### Tail Latency Amplification in Microservices ($p99$ Problem)

When evaluating latency, averages (means) are misleading. System designers evaluate percentile metrics:

- `$p50$ (Median)`: 50% of requests are faster than this value.
- `$p99$`: 99% of requests are faster than this value; represents worst-case user experiences.

In fan-out microservice architectures, tail latency ($p99$) compounds exponentially across downstream service calls:

```
[ User App ] ──► [ Gateway ] ──┬──► [ Microservice 1 (p99 = 10ms) ]
                              ├──► [ Microservice 2 (p99 = 10ms) ]
                              ├──► ...
                              └──► [ Microservice 100 (p99 = 10ms) ]
```

If an API Gateway must scatter-gather requests across $N = 100$ parallel microservice calls to assemble a single response page, the probability $P$ that the overall request experiences a tail latency delay is:

$$P(\text{System Tail Delay}) = 1 - (1 - p)^N$$
Where $p = 0.01$ (for $p99$ latency):

$$P = 1 - (1 - 0.01)^{100} = 1 - (0.99)^{100} \approx 63.4\%$$
Despite every individual microservice performing at $p99 \le 10\text{ms}$ 99% of the time, over 63% of overall user request pages experience severe tail latency delays!

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### 1. Taming Tail Latency Without Sacrificing Throughput: Hedged Requests

Pioneered by Google in The Tail at Scale, Hedged Requests mitigate random tail-latency spikes (caused by GC pauses, background disk compaction, or transient network drops) without dropping system throughput capacity.

```
HEDGED REQUEST PROTOCOL
Client                     Server A                    Server B
 │                           │                           │
 │ 1. Send Request           │                           │
 ├──────────────────────────►│                           │
 │                           │ (Slow / GC Pause)         │
 │ ... Wait until p95 time...│                           │
 │                           │                           │
 │ 2. Send Hedged Duplicate  │                           │
 ├───────────────────────────┼──────────────────────────►│
 │                           │                           │
 │ 3. Returns Fast Response  │                           │ 4. Executes Fast
 │◄──────────────────────────┼───────────────────────────┤
 │                           │                           │
 │ 4. Cancel Request         │                           │
 ├──────────────────────────►│                           │
```

- Client sends a request to Server A.
- Client waits for the expected $p95$ latency window (e.g., 10ms).
- If Server A has not responded by 10ms, the client sends an identical Hedged Request to Server B.
- Client consumes whichever server responds first and sends a cancellation frame to the other.
- **Impact**: Drastically compresses the $p99$ tail latency down close to the $p95$ boundary. Because only ~5% of requests trigger a duplicate call, total system throughput overhead increases by only ~5%.

#### 2. Queuing Theory & Buffer Bloat: Controlled Delay (CoDel):

To maximize throughput, network engineers traditionally added massive RAM queues to routers and load balancers to cushion against packet drops during traffic bursts.

- **The Failure Mode (Buffer Bloat)**: When arrival rate temporarily exceeds capacity, huge queues buffer millions of packets. The system continues to report high throughput, but packets sit in memory queues for seconds before being processed, driving latency through the roof.

#### #Pro Mitigation (Load Shedding & CoDel):

- **Load Shedding**: When request queue depth exceeds an SLA threshold, immediately reject new incoming traffic (HTTP 539 / 429) to preserve low latency for already-accepted requests.
- **Controlled Delay (CoDel)**: Monitors the minimum queue standing delay. If packets sit in a queue for longer than a target window (e.g., 5ms), the queue proactively drops packets at the head of the line to force client backoff algorithms to slow down.

#### 3. Asynchronous Pipelining (Event-Driven Concurrency):

Traditional synchronous processing maps one thread per request. When a thread waits for disk or network I/O,it blocks, forcing the OS to perform expensive CPU thread context switches.

```
SYNCHRONOUS THREAD-PER-REQUEST (High Latency Overhead)
Thread 1: [ CPU ] ──► [ WAIT FOR I/O (Blocked) ] ──► [ CPU ]
Thread 2:             [ CPU ] ──► [ WAIT FOR I/O (Blocked) ] ──► [ CPU ]
* High context switching overhead degrades both Latency and Throughput under load.

ASYNCHRONOUS PIPELINING / NON-BLOCKING I/O (Netty / Event Loop)
Single Thread: [ Process Req 1 ] ──► [ Dispatches Async I/O ] ──► [ Process Req 2 ] ──► [ Handle Req 1 I/O Callback ]
* Maximizes Throughput via CPU cache locality while keeping Latency low.
```

---

### 5. Text-Based Architecture Diagram:

**Adaptive Throughput vs. Latency Pipeline (Dynamic Batching Engine)**

```
===================================================================================================
1. ADAPTIVE INGESTION ENGINE (Dynamic Balancing)
===================================================================================================

[ incoming Client Event Stream ]
              │
              v
 +─────────────────────────────────────────────────────────────────────────────────────────────+
 | DYNAMIC BATCHING PROXY                                                                      |
 |                                                                                             |
 |  Configuration Rules:                                                                       |
 |   - `max_batch_size` = 1000 records                                                         |
 |   - `max_delay_ms`   = 10ms                                                                 |
 |                                                                                             |
 |  Execution Logic:                                                                           |
 |   ├── IF 1000 records accumulate -> Flush IMMEDIATELY (Maximized Throughput Path)           |
 |   └── IF time > 10ms elapsed      -> Flush IMMEDIATELY (Bounded Latency Protection Path)    |
 +──────────────────────────────────────────────┬──────────────────────────────────────────────+
                                                │
                                                v
===================================================================================================
2. LOAD SHEDDING & TAIL PROTECTION LAYER
===================================================================================================

 +─────────────────────────────────────────────────────────────────────────────────────────────+
 | QUEUE HEALTH CONTROLLER                                                                     |
 |                                                                                             |
 |  1. Measure Active Queue Depth & Standing Delay                                             |
 |  2. IF Standing Delay > 50ms:                                                               |
 |     ├── SHED LOAD: Reject low-priority requests (`HTTP 429`)                                |
 |     └── Protect $p99$ Latency for high-priority requests                                    |
 +──────────────────────────────────────────────┬──────────────────────────────────────────────+
                                                │
                                                │ Healthy Batched Requests
                                                v
===================================================================================================
3. ASYNCHRONOUS HIGH-THROUGHPUT EXECUTION
===================================================================================================

 +─────────────────────────────────────────────────────────────────────────────────────────────+
 | STORAGE / ENGINE SINK                                                                       |
 |  - Executes single bulk sequential write to Disk/Database                                   |
 |  - Amortizes syscalls, locks, and network headers across 1000 records                       |
 +─────────────────────────────────────────────────────────────────────────────────────────────+
```

---

### 6. Interview Checklist:

When pitching Throughput vs. Latency in a system design interview:

- **Define Both Metrics Explicitly**: Clarify that Latency measures duration per task ($ms$) while Throughput measures capacity over time ($RPS$).

- **Apply Little’s Law ($L = \lambda \cdot W$)**: Demonstrate foundational queuing math to prove that to increase throughput without increasing latency, concurrency must scale.

- **Focus on Percentiles ($p99$) Over Averages**: Always reject "average latency" metrics. Explain how tail latency ($p99$) compounds exponentially across microservice scatter-gather calls.

- **Pitch Batching as the Primary Tuning Knob**: Detail how tuning parameters like linger.ms and batch.sizeallows shifting along the latency-throughput curve based on business needs.

- **Demonstrate Advanced Tail Mitigation**: Recommend Hedged Requests (speculative execution) to compress $p99$ tail latency without incurring massive throughput overhead, and Load Shedding to prevent buffer bloat during traffic spikes.
