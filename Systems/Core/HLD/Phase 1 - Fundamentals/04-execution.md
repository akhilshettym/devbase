## Concurrency vs Parallelism

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Think of a busy coffee shop with customers ordering espresso and pastries:

- **Concurrency (Dealing with many things at once)**: A single barista taking an order, starting the espresso machine, pulling a pastry while the espresso brews, and hand-crafting milk foam while the pastry toasts. The single barista switches context between tasks rapidly. At any given millisecond, the barista is doing only one physical action, but multiple orders are in progress simultaneously.

- **Parallelism (Doing many things at once)**: Hiring four baristas working at four separate espresso machines side-by-side. At the exact same millisecond, Barista 1 pulls an espresso, Barista 2 steams milk, Barista 3 warms a croissant, and Barista 4 handles payment.

#### The Core Problem Solved:

- Hardware design has hit physical thermal limits (the "power wall"), meaning single-threaded CPU clock speeds can no longer scale exponentially. To achieve higher performance, hardware shifted to multi-core architectures.

#### Concurrency and parallelism solve the efficiency challenge by ensuring:

- CPU cores are never left idle during I/O operations (network requests, disk access, database queries).
- Large computational workloads are decomposed into independent tasks that execute across physical CPU cores simultaneously.

---

### 2. The Basics (Scratch Level):

#### Core Definitions:

- **Concurrency**: A structural property of software architecture. It is the ability to break a program into independent units of execution that can be handled out-of-order without affecting the final outcome. Concurrency is about dealing with many things at once.
- **Parallelism**: An execution property of the underlying hardware. It is the ability to execute multiple computations at the exact same physical instant on separate hardware resources (multi-core CPUs, GPUs). Parallelism is about doing many things at once.

#### Key Terminology:

- **Process**: An isolated execution environment created by the Operating System, containing its own virtual address space, file descriptors, and memory permissions.
- **Thread**: The smallest unit of execution that an OS kernel can schedule. Threads belonging to the same process share that process’s virtual memory space (heap, global variables), but maintain their own stack and register states.
- **Context Switch**: The process of the CPU storing the execution state (registers, stack pointer, program counter) of an active thread and loading the state of a queued thread.
- **I/O-Bound Workload**: Tasks spent waiting for external resources (databases, network sockets, disk files). Optimal for Concurrency.
- **CPU-Bound Workload**: Tasks spent performing heavy computation (video encoding, cryptographic hashing, matrix multiplication). Optimal for Parallelism.

---

### 3. Deep Dive & Architecture (Mid Level):

#### Execution Models Under the Hood:

#### 1. Single-Core Time Slicing (Concurrent, Not Parallel):

On a single physical CPU core, the OS Kernel's scheduler uses Preemptive Time Slicing. The CPU allocates a "time quantum" (typically $1\text{ ms}$–$10\text{ ms}$) to Thread $A$, pauses it via a hardware interrupt, performs a context switch, and runs Thread $B$.

```
Single Core CPU Timeline:
[ Thread A ] ──> (Context Switch) ──> [ Thread B ] ──> (Context Switch) ──> [ Thread A ]
```

#### Cost of Context Switching:

- **Direct Cost**: Saving and restoring CPU registers and updating the OS task state.
- **Indirect Cost**: CPU Cache pollution. Context switching flushes or invalidates L1/L2 CPU caches and Translation Look aside Buffer (TLB) entries, causing cache misses when the old thread resumes.

#### 2. Multi-Core Simultaneous Execution (Concurrent & Parallel):

On a multi-core processor, multiple execution pipelines execute machine instructions on separate silicon cores on the exact same clock tick.

```
Core 1: [ Thread A ] ───────────────────────────────────────────>
Core 2: [ Thread B ] ───────────────────────────────────────────>
```

#### Threading & Runtime Architecture Models:

```
  1:1 (Kernel Threads)           N:1 (User-Space / Green)           M:N (Hybrid / Work-Stealing)
┌───────────────────────┐       ┌───────────────────────┐         ┌───────────────────────┐
│ User Thread 1, 2, 3   │       │ User Thread 1, 2, 3   │         │ User Thread 1...M     │
└───────────┬───────────┘       └───────────┬───────────┘         └───────────┬───────────┘
           │ 1:1                           │ N:1                             │ M:N
┌───────────▼───────────┐       ┌───────────▼───────────┐         ┌───────────▼───────────┐
│ Kernel Threads 1, 2, 3│       │    1 Kernel Thread    │         │ Kernel Threads 1...N  │
└───────────────────────┘       └───────────────────────┘         └───────────────────────┘
```

- **1:1 Model (Native OS Threads - C++, Java, Rust)**: Every application thread maps directly to an OS kernel thread. High memory footprint ($\sim 1\text{MB}$ stack per thread) and high context switch overhead, but utilizes all CPU cores natively.
- **N:1 Model (User-Space / Green Threads / Classic Event Loops - Node.js, Python asyncio)**: Multiple application-level threads map to a single OS kernel thread. Fast context switching in user space, but cannot execute across multiple CPU cores in parallel without spawning separate OS processes.
- **M:N Model (Work-Stealing Scheduler - Go Goroutines, Java Virtual Threads, Erlang Schedulers)**: Maps $M$ lightweight user threads onto $N$ OS kernel threads. Lightweight stack allocation (starting at $\sim 2\text{KB}$), supporting millions of concurrent routines scheduled across all CPU cores with work-stealing algorithms.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Theoretical Limits: Amdahl’s Law vs. Gustafson’s Law

#### 1. Amdahl’s Law (Fixed Workload Size):

Calculates the maximum theoretical speedup $S$ of a program when utilizing $N$ parallel processor cores, bounded by the strictly serial (non-parallelizable) portion of code $P_{\text{serial}}$:

$$S(N) = \frac{1}{P_{\text{serial}} + \frac{1 - P_{\text{serial}}}{N}}$$

**Takeaway**: If $5\%$ of your application logic is strictly sequential (e.g., synchronized queue locks, single-threaded state updates), no matter how many CPU cores you add (even 10,000 cores), maximum speedup can never exceed $20\times$.

```
Speedup Factor (S)
 20x ────────────────────────────────────────────── Theoretical Ceiling (Amdahl's Limit)
     │                                    /
 15x │                                   /  (P_serial = 5%)
     │                                 /
 10x │                                /
  5x │                              /
  1x └─────────────────────────────┴────────────────
     1            10               50            100 CPU Cores (N)
```

#### Critical Hardware Bottlenecks & Failure Modes:

#### 1. Cache Coherency & False Sharing:

Multi-core CPUs keep local L1/L2 caches synchronized using protocols like MESI (Modified, Exclusive, Shared, Invalid).

- **False Sharing**: Occurs when Thread $A$ on Core 1 and Thread $B$ on Core 2 modify completely independent variables that happen to reside on the same 64-byte L1 Cache Line. Core 1's write invalidates Core 2's cache line, forcing continuous memory bus synchronization and destroying parallel performance.
- **Mitigation**: Padding data structures to 64-byte boundaries (e.g., Go cpu.CacheLinePad, Java @Contended).

#### 2. Synchronized Locks vs. Lock-Free CAS Primitives:

Coarse-grained Mutexes create thread contention and context-switching overhead under high concurrency.

| Synchronization Strategy                     | `Mechnism`                                                                                             | `Performance Impact`                                                                                                        |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| **Pessimistic Locking (Mutex/Lock)**         | Blocks competing threads; OS kernel puts thread to sleep until lock releases.                          | High context switch latency; vulnerable to Deadlocks and Priority Inversion.                                                |
| **Atomic Hardware Operations (CAS)**         | Uses CPU instruction CMPXCHG(Compare-And-Swap) in a non-blocking retry loop.                           | Zero context switches; ultra-fast under low/medium contention, but causes CPU spin-lock thrashing under extreme contention. |
| **Communicating Sequential Processes (CSP)** | Encapsulates state within isolated execution units; passes ownership via non-blocking channels/queues. | Avoids shared memory contention; eliminates explicit locking semantics.                                                     |

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
                    CONCURRENCY VS PARALLELISM EXECUTION
================================================================================

1. CONCURRENT EXECUTION (Single-Core Interleaving via Event Loop / Task Scheduler)
--------------------------------------------------------------------------------
[ OS Thread 1 (Single Core) ]
 ├── Task A (Execute 2ms) ──> [Wait for I/O]
 │                             │
 ├── Task B (Execute 3ms) <────┘ (Context switch while Task A waits)
 │                             │
 └── Task A Resumes (Execute 1ms) <─┘


2. PARALLEL EXECUTION (Multi-Core Independent Pipelines)
--------------------------------------------------------------------------------
[ CPU Core 1 ] ──> [ Task A: Matrix Chunk 1 (100% CPU Execution) ] ─────────>
[ CPU Core 2 ] ──> [ Task B: Matrix Chunk 2 (100% CPU Execution) ] ─────────>
[ CPU Core 3 ] ──> [ Task C: Matrix Chunk 3 (100% CPU Execution) ] ─────────>
[ CPU Core 4 ] ──> [ Task D: Matrix Chunk 4 (100% CPU Execution) ] ─────────>


3. HYBRID CONCURRENT + PARALLEL ENGINE (M:N Work-Stealing Scheduler)
--------------------------------------------------------------------------------
[ M User Routines / Goroutines ]
 (G1, G2, G3, G4, G5, G6, G7, G8...)
         │
         ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ WORK-STEALING RUNTIME SCHEDULER                                              │
│                                                                              │
│  [ Local Queue 1 ]             [ Local Queue 2 ]             [ Global Queue ]│
│    G1, G2, G3                    G4, G5, G6                    G7, G8        │
└─────────┬───────────────────────────────┬────────────────────────────────────┘
         │                               │
         ▼                               ▼
 [ Kernel Thread 1 ]             [ Kernel Thread 2 ]
         │                               │
         ▼                               ▼
   [ CPU Core 1 ]                  [ CPU Core 2 ]
================================================================================
```

---

### 6. Interview Checklist:

- **Anchor with the Rob Pike Principle**: State clearly that "Concurrency is about structure, while parallelism is about execution." Concurrency allows a program to be decomposed into independent tasks; parallelism executes those tasks concurrently on separate physical CPU cores.

- **Classify the Workload First**: When asked to design a high-throughput service, categorize whether operations are I/O-Bound (use asynchronous event loops, non-blocking I/O, or M:N virtual threads) or CPU-Bound (use a thread/worker pool scaled precisely to match physical CPU core counts).

- **Demonstrate Awareness of Amdahl's Law**: Explain why scaling out CPU cores yields diminishing returns if the application contains lock contention or sequential synchronization points.

- **Pitch Modern Concurrency Patterns**: Favor lock-free data structures (CAS atomic primitives), lock-free ring buffers (LMAX Disruptor), or message-passing primitives (CSP channels / Actor model) over classical mutexes to prevent deadlocks, priority inversion, and cache line invalidation.
