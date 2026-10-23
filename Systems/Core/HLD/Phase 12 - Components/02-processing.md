## Batch Processing vs Stream Processing (Hadoop, Spark, Flink)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

- **Batch Processing is like a daily newspaper printing press**: Articles, reports, and classified ads accumulate all day long. Once every 24 hours at midnight, the press runs, processes all gathered data in bulk, and delivers a complete, highly structured paper by morning. It provides a comprehensive, high-throughput view of the whole day's events, but the information is hours out of date.

- **Stream Processing is like a live breaking news feed**: As individual news events happen anywhere in the world, reporters publish line-by-line updates directly to a digital ticker in real time. Readers receive instant visibility into unfolding events, but managing this unpredictable, continuous stream requires specialized infrastructure to handle out-of-order updates and continuous state calculations.

#### The Problem It Solves:

- Data in the real world is created as a continuous, unbounded stream (e.g., clickstreams, IoT sensor readings,financial transactions).

- Batch Processing Systems (Hadoop MapReduce, Spark Batch) process finite, bounded datasets collected over a fixed window of time. They maximize resource efficiency and overall throughput when calculating deep analytical aggregations across terabytes or petabytes of historical data, but introduce high latency (minutes to hours).

- Stream Processing Systems (Apache Flink, Spark Streaming) process unbounded data in motion as events occur. They trade off raw bulk execution efficiency for sub-second processing latency, enabling automated fraud detection, real-time alerting, dynamic pricing, and continuous analytics.

---

### 2. The Basics (Scratch Level):

#### Bounded vs. Unbounded Datasets:

```
BOUNDED DATASET (Batch)
[ Data Start ] ──► [ Fixed Volume of Static Files ] ──► [ Data End ] (Processed as a single job)

UNBOUNDED DATASET (Stream)
[ Data Start ] ──► [ Infinite Continuous Event Stream ] ──► ??? (Runs indefinitely)
```

- **Bounded Data**: Data with a distinct beginning and end stored on immutable media (e.g., a daily log file on S3 or a SQL table partition).
- **Unbounded Data**: Data that flows continuously with no defined ending boundary (e.g., a Kafka topic stream of user clicks).

#### Processing Engine Evolution Matrix:

| Feature / Dimension      | `Apache Hadoop (MapReduce)`                          | `Apache Spark`                                    | `Apache Flink`                                             |
| ------------------------ | ---------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------- |
| **Primary Paradigm**     | Batch (1st Gen)                                      | Micro-batch & Native Batch (2nd Gen)              | True Stateful Stream Processing (3rd Gen)                  |
| **Data Execution Model** | Multi-pass Disk Storage (HDFS read/write per phase). | In-Memory Directed Acyclic Graph (DAG) with RDDs. | Continuous Pipelined Event-driven Dataflow.                |
| **Latency Target**       | Hours to Days                                        | Sub-second to Minutes (Micro-batch: ~100ms)       | Low Milliseconds                                           |
| **State Management**     | External (Writes state back to disk/HDFS).           | In-Memory RDD / Checkpointed Disks.               | Embedded Local State (RocksDB / In-Memory) with ABS.       |
| **Unified Execution**    | No (Batch only).                                     | Yes (Treats Streams as fast mini-batches).        | Yes (Treats Batch as a bounded special case of streaming). |

#### Time Semantics in Streaming:

In stream processing, the physical clock time when an event is processed rarely matches when the event actually occurred:

- **Event Time**: The exact timestamp embedded in the event data payload when it was created on the client device (e.g., user tapped a button at 12:00:00.104).
- **Ingestion Time**: The timestamp assigned when the event entered the central messaging queue (e.g.,appended to Apache Kafka topic at 12:00:02.000).
- **Processing Time**: The local clock time of the stream processing node running the transformation code (e.g., worker node executes code at 12:00:05.300).

---

### 3. Deep Dive & Architecture (Mid Level):

#### Architectural Paradigm Shift: Micro-Batch vs. True Continuous Processing:

```
MICRO-BATCH MODEL (Apache Spark Streaming)
[ Continuous Stream ] ──► [ Buffer 500ms ] ──► [ Batch Job 1 ] ──► Output
                     ──► [ Buffer 500ms ] ──► [ Batch Job 2 ] ──► Output
* High throughput, easy fault-recovery, but latency is artificially bounded by batch size.

TRUE STREAM PROCESSING (Apache Flink)
[ Continuous Stream ] ──► Event 1 ──► [ Processor ] ──► Instant Output
                     ──► Event 2 ──► [ Processor ] ──► Instant Output
* Pipelined execution: Each record is processed individually or in micro-buffers immediately.
```

#### 1. Micro-Batching (Spark Streaming):

Spark discretizes incoming continuous data streams into small temporal chunks called Discretized Streams (DStreams) or Structured Streaming batches.

- **Internal Mechanics**: Every $N$ milliseconds (e.g., 500ms), Spark closes the current window, wraps the collected records into an immutable RDD (Resilient Distributed Dataset), and schedules a mini-batch execution DAG across the cluster.
- **Trade-off**: Maximizes throughput and leverages optimized batch vectorization engines, but enforces an artificial lower-bound on processing latency (~100ms+).

#### 2. Native Continuous Streaming (Apache Flink):

Flink processes events item-by-item as long-running, continuous operators connected by long-lived network channels.

- **Internal Mechanics**: Events pass through an operator thread instantly without waiting for intermediate buffer accumulation. Network buffers flush based on low-level timeouts (e.g., 10ms).
- **Trade-off**: Achieves ultra-low sub-millisecond latency and natural event-driven processing, but requires sophisticated distributed state management to survive failures.

#### Windowing Mechanics:

Because streaming datasets are unbounded, analytical operations like aggregations (COUNT, SUM, AVG) must be constrained within temporal boundaries called Windows:

```
TUMBLING WINDOW (Fixed size, non-overlapping)
|--- 00:00 to 00:05 ---|--- 00:05 to 00:10 ---|--- 00:10 to 00:15 ---|

SLIDING WINDOW (Fixed size, overlapping)
|--- 00:00 to 00:05 ---|
     |--- 00:01 to 00:06 ---|
           |--- 00:02 to 00:07 ---|

SESSION WINDOW (Dynamic size based on idle gap)
|-- Activity --| [15m Idle] |-- Activity --|
```

- **Tumbling Windows**: Non-overlapping time frames of equal length (e.g., calculate total page views every 5 minutes). Every event belongs to exactly one window instance.

- **Sliding Windows**: Overlapping time frames defined by duration and slide interval (e.g., calculate 5-minute rolling average updated every 1 minute).

- **Session Windows**: Dynamically bounded windows defined by periods of inactivity (e.g., group user activity into a session until the user goes idle for 15 minutes).

#### Late Data Handling: Watermarks:

- Mobile networks drop connections, causing events generated at 12:00:00 to arrive out of order at 12:05:00.How does a stream engine know when to stop waiting for late events and close a window?
- Watermarks are special control metrics injected directly into the data stream that measure progress in Event Time.
- **A watermark $W(t) = t - \Delta t$ asserts**: "The system promises that no further events with an Event Time earlier than $t$ will arrive."

```
[ Stream Event: t=10s ] ──► [ Stream Event: t=12s ] ──► [ WATERMARK: W(t=10s) ] ──► [ Engine ]
                                                             │
                                                             v
                                             Triggers closing of 0-10s Window!
                                             Any subsequent t=8s event is marked LATE.
```

If an event arrives with an event time $t_{event} < W(t)$, it is classified as Late Data. The engine can be configured to:

- Drop the late record silently.
- Direct the late record to a separate Side Output log for manual reconciliation.
- Re-evaluate and update the previously emitted window result.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Stateful Stream Processing & State Backends:

Simple transformations (FILTER, MAP) are stateless. However, aggregations, joins, and windowing operations are stateful—they require the engine to remember historical data across incoming events.

In Apache Flink, state is a first-class citizen managed locally:

- **Memory State Backend**: Stores active operator state as raw objects on the JVM Heap. Extremely fast,but constrained by memory size and susceptible to Garbage Collection (GC) pauses.
- **Embedded Key-Value State Backend (RocksDB)**: Writes state out-of-core to an embedded local RocksDB key-value engine running on local worker NVMe SSDs. Allows state sizes to scale far beyond available RAM to terabytes per node.

```
FLINK WORKER NODE
+─────────────────────────────────────────────────────────────────────────+
| JVM TaskManager                                                         |
|  [ Stream Operator ]                                                    |
|         │                                                               |
|         │ Fast Inter-Process Reads/Writes                               |
|         v                                                               |
|  [ Local Embedded RocksDB ] ──(Spills to Local Disk)──► [ Local NVMe ]  |
+─────────────────────────────────────────────────────────────────────────+
         │
         │ Asynchronous Snapshotting (ABS)
         v
  [ Remote Durable Store: S3 / HDFS ]
```

#### Distributed Fault Tolerance: Asynchronous Barrier Snapshotting (ABS):

To recover from node crashes without replaying a 6-month-old stream from the beginning, stream engines must snapshot state periodically.

Flink uses a variant of the Chandy-Lamport Algorithm called Asynchronous Barrier Snapshotting (ABS):

Barrier Injection: The JobManager periodically injects Checkpoint Barriers into the input stream sources alongside data records.

Barrier Flow: Barriers flow down the execution DAG alongside events in strict alignment.

Local Snapshot: When an operator receives a barrier from all incoming channels, it freezes its state pointer, writes a copy of its local state asynchronously to durable storage (S3/HDFS), and forwards the barrier downstream.

Non-blocking Execution: The main stream processing pipeline continues processing real-time events while the state snapshot is written to disk in the background.

#### Achieving End-to-End Exactly-Once Semantics:

"Exactly-once" processing means that every event affects the final state exactly once, even during hardware failures, network partitions, or process restarts.

Achieving end-to-end exactly-once processing requires coordination across three distinct layers:

$$\text{End-to-End Exactly-Once} = \text{Replayable Source} + \text{Stateful Engine} + \text{Transactional Sink}$$

- **Replayable Source**: The message broker must allow rewinding and replaying historical data offsets (e.g.,Apache Kafka offset reset).
- **Stateful Processing Engine**: The stream engine must support state snapshotting and deterministic recovery (e.g., Flink ABS Checkpointing).

`Transactional / Idempotent Sink`: **The target destination must accept writes via**:

- **Two-Phase Commit (2PC)**: Flink's TwoPhaseCommitSinkFunction opens a transaction on the sink,writes data during checkpointing, and commits the transaction only when the JobManager confirms the global checkpoint succeeded.
- **Idempotent Writes**: Using unique deterministic keys (UPSERT in Cassandra/Redis) so re-writing the same output multiple times yields identical final state.

`Architectural Blueprint Comparison`: **Lambda vs. Kappa Architecture**

```
LAMBDA ARCHITECTURE (Dual Path - Legacy)
                          ┌──► Batch Layer (Hadoop/Spark) ──► Batch Views  ──┐
[ Incoming Event Stream ] ─┤                                                  ├──► [ Unified Serving ]
                          └──► Speed Layer (Flink/Storm)  ──► Realtime Views ┘
* Trade-off: High operational complexity; forces developers to maintain two separate codebases!

KAPPA ARCHITECTURE (Single Path - Modern Standard)
[ Incoming Event Stream ] ──► [ Log Buffer: Kafka ] ──► [ Stream Engine: Flink ] ──► [ Serving Engine ]
* Trade-off: Single codebase; historical backfills executed by rewinding Kafka offsets through Flink.
```

- **Lambda Architecture**: Combines a traditional batch pipeline (for accurate historical views) with a fast real-time streaming pipeline (for recent low-latency views).
- **Critical Flaw**: High operational overhead. Developers must implement and maintain identical business logic in two separate codebases (e.g., Java for Spark Batch and Scala for Flink Streaming).
- **Kappa Architecture**: Eliminates the batch layer entirely. All data is processed as a stream.
- **Historical Reprocessing**: To update historical metrics or re-run business logic across past data, the engineer rewinds the offset on a long-retention log store (e.g., Apache Kafka or Apache Pulsar) and streams historical records through the exact same stream processing codebase.

---

### 5. Text-Based Architecture Diagram:

**Scalable Stateful Stream Processing Pipeline with Watermarking & Fault Tolerance**

```
===================================================================================================
1. DATA INGESTION & WATERMARK INJECTION
===================================================================================================

[ IoT Sensors / App Clients ]
            │
            │ Continuous Event Emission (JSON over HTTP/gRPC)
            v
+─────────────────────────────────────────────────────────────────────────────────────────────────+
| DISTRIBUTED STREAM BUFFER (Apache Kafka / Pulsar)                                               |
|  - Partition 0: [e_1(t=1s), e_2(t=3s), e_3(t=2s)]                                               |
|  - Partition 1: [e_4(t=4s), e_5(t=6s), e_6(t=5s)]                                               |
+──────────────────────────────────────────────┬──────────────────────────────────────────────────+
                                              │
                                              │ Continuous Fetch (OTLP/gRPC)
                                              v
===================================================================================================
2. STREAM ENGINE PROCESSING (Apache Flink Cluster)
===================================================================================================

+─────────────────────────────────────────────────────────────────────────────────────────────────+
| FLINK SOURCE OPERATOR                                                                           |
|  - Extracts Event Time timestamps                                                               |
|  - Generates & Injects Watermarks: W(t) = Max(EventTime) - 5 seconds                            |
+──────────────────────────────────────────────┬──────────────────────────────────────────────────+
                                              │
                                              │ Keyed Partitioning by `user_id` (Network Shuffle)
                                              v
+─────────────────────────────────────────────────────────────────────────────────────────────────+
| STATEFUL WINDOW AGGREGATOR OPERATOR (Worker TaskManager)                                        |
|                                                                                                 |
|   Active Record Flow: [ e_1, e_2, e_3 ] ──► Evaluates 5-Minute Tumbling Windows                 |
|                                                                                                 |
|   Local State Management:                                                                       |
|    ├── Fast In-Memory Cache (RAM)                                                               |
|    └── Local KV Store (Embedded RocksDB on SSD)                                                 |
|                                                                                                 |
|   Fault Tolerance Checkpointing (Asynchronous Barrier Snapshotting):                            |
|    ├── Receives Checkpoint Barrier #42                                                          |
|    └── Copies Local RocksDB State to S3 asynchronously ────────────────┐                        |
+──────────────────────────────────────────────┬───────────────────│──────────────────────────────+
                                               │                   │
                                               │ Watermark Trigger │ Asynchronous Backup
                                               v                   v
===============================================│===================│===============================
3. EXACTLY-ONCE TRANSACTIONAL SINK             │                   │
===============================================│===================│===============================
                                               │                   │
                                               │                   v
                                               │    +─────────────────────────────────────────────+
                                               │    | DURABLE STORAGE ENGINE                      |
                                               │    | (AWS S3 / HDFS State Checkpoint Store)      |
                                               │    +─────────────────────────────────────────────+
                                               v
+─────────────────────────────────────────────────────────────────────────────────────────────────+
| TRANSACTIONAL SINK (Two-Phase Commit / Idempotent Upsert)                                       |
|  - Pre-commits window results on Checkpoint Barrier arrival                                     |
|  - Commits transaction when JobManager acknowledges global checkpoint success                   |
+──────────────────────────────────────────────┬──────────────────────────────────────────────────+
                                               │
                                               v
                           [ Real-Time Analytics Dashboard / Redis / DB ]
```

---

### 6. Interview Checklist:

When pitching batch vs. stream processing in a high-level system design interview:

- **Frame Trade-offs by Data Bound & Latency**: Start by defining the core boundary: Batch processes bounded data at rest for maximum throughput; Streaming processes unbounded data in motion for minimum latency.

- **Distinguish Micro-Batch vs. Continuous Streaming**: Demonstrate technical depth by contrasting Spark’s micro-batch model (~100ms mini-batches) with Flink’s continuous event-at-a-time processing model (<10ms latency).

- **Master Time Semantics & Watermarking**: Explain the critical difference between Event Time and Processing Time. Show how Watermarks allow streaming engines to process out-of-order data and deterministically close time-based windows.

- **Pitch Kappa over Lambda Architecture**: Recommend the modern Kappa Architecture (using Kafka/Pulsar + Flink) to avoid maintaining two separate codebases for batch and streaming, replaying historical stream offsets when backfills are needed.

- **Explain End-to-End Exactly-Once**: Detail how to achieve end-to-end data integrity by pairing a replayable source (Kafka), a stateful checkpointed engine (Flink ABS), and a transactional/idempotent sink (2-Phase Commit).
