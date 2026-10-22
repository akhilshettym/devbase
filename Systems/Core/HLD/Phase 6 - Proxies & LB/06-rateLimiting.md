## Rate Limiting (Token Bucket, Leaky Bucket, Sliding Window)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

In distributed software systems, rate limiting controls the rate of incoming or outgoing traffic consumed by clients. Unbounded API endpoints are vulnerable to denial-of-service (DoS/DDoS) attacks, brute-force security attempts, web scraping, cascading backend service failures, and unexpected cloud infrastructure bills.

```
+-----------------------------------------------------------------------------------+
|               Real-World Analogy: Highway On-Ramp Metering Light                  |
+-----------------------------------------------------------------------------------+
| Token Bucket: Amusement Park Fast-Pass Tokens                                     |
| - Guests get tokens at a fixed rate. If you accumulated 5 tokens during off-peak, |
|   you can use all 5 back-to-back immediately (Bursts allowed).                    |
|                                                                                   |
| Leaky Bucket: Highway Metering Light                                              |
| - No matter how many cars arrive at the highway ramp in a sudden rush (Burst),    |
|   the metering light lets cars enter the main highway at a strictly constant,     |
|   smooth rate of 1 car every 3 seconds (Traffic Shaping).                         |
+-----------------------------------------------------------------------------------+
```

- **The Problem It Solves**: Rate limiting protects services from being overwhelmed by excess traffic,guarantees fair multi-tenant resource sharing, enforces commercial API monetization tiers (e.g., Free Tier:100 req/min vs. Enterprise Tier: 10,000 req/min), and guards against runaway client bugs or malicious traffic spikes.

- **Primary Use Cases**: API Gateways, Login/Auth endpoints, Payment Gateway integrations, Public Web Search APIs, and Web Scraping Defense layers.

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Bucket / Window Capacity**: The maximum number of tokens or requests allowed within a defined timeframe.
- **Refill Rate**: The speed at which tokens are added back to the rate limit tracker over time.
- **HTTP 429 (Too Many Requests)**: The standard HTTP status code returned when a client breaches its allowed quota.

#### Standard Rate Limit Response Headers:

- **X-RateLimit-Limit**: Maximum requests permitted per window.
- **X-RateLimit-Remaining**: Remaining request quota for the current window.
- **X-RateLimit-Reset**: Unix epoch timestamp indicating when the current window resets.
- **Retry-After**: Seconds to wait before making a new request.

#### Algorithm Comparison Matrix:

| Algorithm                  | `Memory Usage`       | `Burst Handling`          | `Smoothness`      | `Accuracy`               | `Best For`                           |
| -------------------------- | -------------------- | ------------------------- | ----------------- | ------------------------ | ------------------------------------ |
| **Token Bucket**           | $O(1)$ (2 variables) | Supported(Up to capacity) | Variable          | High                     | General API Gateways, REST APIs      |
| **Leaky Bucket**           | $O(B)$(Queue size)   | Pushed to Queue           | Strictly Constant | High                     | Traffic Shaping, Egress Webhooks     |
| **Fixed Window**           | $O(1)$ (1 counter)   | Flawed(Boundary Spike)    | Poor              | Low                      | Simple basic protection              |
| **Sliding Window Log**     | $O(N)$(Every req ts) | Supported                 | High              | 100% Exact               | Strict compliance, low QPS endpoints |
| **Sliding Window Counter** | $O(1)$ (2 counters)  | Supported                 | High              | $\approx 99.5\%$Accurate | High-scale microservice gateways     |

---

### 3. Deep Dive & Architecture (Mid Level):

#### Internal Mechanics & Core Algorithms:

#### 1. Token Bucket Algorithm (Lazy Fill Mechanics):

- A bucket holds up to $Capacity$ tokens. Tokens are added at a rate of $FillRate$ per second. When a request arrives, $1$ token is consumed. If $0$ tokens remain, the request is rejected.

- **Production Optimization (No Background Threads)**: Instead of running a background cron thread that adds tokens to millions of user buckets every second (which destroys CPU at scale), production implementations use Lazy Fill Evaluation:

$$\text{Tokens}_{\text{new}} = \min(\text{Capacity}, \text{Tokens}_{\text{last}} + (t_{\text{now}} - t_{\text{last}}) \times \text{FillRate})$$

```
Request Arrives at Time t_now
          │
          ▼
Calculate elapsed = t_now - t_last
          │
          ▼
New Tokens = Min(Capacity, Current_Tokens + elapsed * FillRate)
          │
    ┌─────┴─────┐
    │ Tokens >= 1?
    └─────┬─────┘
   YES    │    NO
 ┌────────┴────────┐
 ▼                 ▼
Deduct 1 Token    Reject Request
Update t_last     Return 429
Forward Request
```

#### 2. Leaky Bucket Algorithm (Traffic Shaping):

Incoming requests enter a First-In, First-Out (FIFO) queue of fixed size $Capacity$. Requests leak out of the bucket at a strictly constant rate $LeakRate$ (e.g., 10 requests/sec). If a burst of requests arrives and the FIFO queue fills up, new incoming requests spill over the bucket and are immediately dropped.

```
Incoming Request Burst ───►  [ Request Queue / Bucket ]  (If queue full -> Drop / 429)
                                    │
                                    ▼ (Leaks at strictly constant rate: e.g., 1 req / 100ms)
                            [ Processing Backend ]
```

#### 3. Fixed Window Counter (The Boundary Flaw):

Divides time into fixed intervals (e.g., 1-minute blocks: 12:00–12:01, 12:01–12:02). A simple counter increments on every request.

```
                THE BOUNDARY BURST FLAW
 Allowed: 100 req/min

 Window 1 (12:00 - 12:01)              Window 2 (12:01 - 12:02)
 [ 12:00:00 ......... 12:00:50 | 12:01:00 .......... 12:02:00 ]
                          ▲         ▲
                          │         │
                  100 Reqs          100 Reqs
                  (12:00:55)        (12:01:05)

 Result: 200 Requests processed in a 20-second window (2x intended limit!)
```

#### 4. Sliding Window Counter (High-Scale Production Standard):

Combines the low $O(1)$ memory footprint of Fixed Window with the accuracy of Sliding Logs. It computes a weighted average of request counts across the current window and previous window based on current time position.

$$\text{Estimated Count} = \text{Count}_{\text{current}} + \text{Count}_{\text{previous}} \times \left(1 - \frac{t_{\text{elapsed}}}{\text{WindowSize}}\right)$$

```
Previous Window (Count: 100)           Current Window (Count: 30)
[12:00:00 ----------------- 12:01:00]  [12:01:00 ---- 12:01:15 ----------- 12:02:00]
                                                    ▲
                                                    │ (Elapsed: 15s / 60s = 25%)

Calculation at 12:01:15:
Estimated Count = 30 + 100 * (1 - 0.25)
               = 30 + 100 * 0.75 = 105 Requests
Since 105 > 100 (Limit), Request is REJECTED with HTTP 429!
```

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### High-Scale Architecture, Race Conditions & Distributed State:

#### 1. Distributed Race Conditions (Time-of-Check to Time-of-Use):

When scaling rate limiters across multiple API Gateway instances backed by a centralized cache (Redis), a naive Read-Then-Write implementation creates severe race conditions:

```
 Gateway Instance A                   Redis Cluster                   Gateway Instance B
         │                                  │                                  │
 1. GET rate:user_123 (Val=99) -----------> │                                  │
         │                                  │ <----------- 2. GET rate:user_123 (Val=99)
         │                                  │
 3. Val 99 < 100, Allow                     │                                  │
 4. INCR rate:user_123 (Val=100) ---------> │                                  │
         │                                  │ <----------- 5. Val 99 < 100, Allow!
         │                                  │ <----------- 6. INCR rate:user_123 (Val=101!)
 Result: Race condition allowed traffic to breach the maximum threshold!
```

#### 2. Atomic Redis Execution via Lua Scripting:

To eliminate race conditions, the rate-limiting check and counter update must execute atomically on the Redis server in a single thread using a Lua Script:

```Lua
-- Atomic Sliding Window Counter Lua Script
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local current_time = tonumber(ARGV[2])
local window_size = tonumber(ARGV[3])

-- Clean up expired requests older than current window
redis.call('ZREMRANGEBYSCORE', key, '-inf', current_time - window_size)

-- Count total requests remaining in current sliding window
local current_requests = redis.call('ZCARD', key)

if current_requests < limit then
   -- Add current request timestamp to sorted set
   redis.call('ZADD', key, current_time, current_time)
   redis.call('EXPIRE', key, math.ceil(window_size))
   return 1 -- Allowed
else
   return 0 -- Rejected (Rate Limited)
end
```

#### 3. Fault Tolerance & Fallback Policies: Fail-Open vs. Fail-Closed:

If the central Redis rate-limiting cluster experiences an outage or network partition:

- **Fail-Open (User-Experience First)**: The API Gateway bypasses rate limiting checks and allows all incoming traffic to pass through.
- **Risk**: Backend services risk getting crushed if a real DDoS attack coincides with a Redis outage.

- **Fail-Closed (Protection First)**: The API Gateway rejects all incoming requests or applies strict local in-memory fallback limits when Redis is unreachable.
- **Risk**: Legitimate users experience service outages during internal infrastructure hiccups.

- **Best-Practice Architecture (Hybrid Multi-Tier)**: Use local in-memory L1 rate limiting (Guava/Caffeine cache) on each API gateway instance as a primary fast filter, syncing state asynchronously to an L2 Redis Cluster.

#### 4. Multi-Dimensional Rate Limiting:

Modern enterprise systems apply rate limits across multiple overlapping operational layers:

- **Layer 1 (Network Security)**: Max $1,000\text{ req/sec}$ per Client IP (Defends against raw IP flood DoS).
- **Layer 2 (Identity / Tenant)**: Max $5,000\text{ req/min}$ per Tenant_ID (Enforces commercial SaaS subscription tiers).
- **Layer 3 (Costly Endpoint)**: Max $5\text{ req/min}$ on /api/v1/checkout/charge or /api/v1/ai/generate(Protects expensive DB operations and third-party LLM API costs).

---

### 5. Text-Based Architecture Diagram:

```
Scalable Distributed Enterprise Rate Limiter Infrastructure
===================================================================================
                                 PUBLIC INTERNET
===================================================================================
                                        │
                   Inbound Client Requests (HTTPS API Traffic)
                                        │
                                        ▼
===================================================================================
                          EDGE API GATEWAY CLUSTER
===================================================================================
 +-----------------------------------------------------------------------------+
 |  API Gateway Engine Node                                                    |
 |                                                                             |
 |  1. Local Memory L1 Cache (Fast-Path Check for Abusive Blacklisted IPs)     |
 |  2. Extracts Client Key (e.g., `rate:tenant_8821:v1_checkout`)              |
 |  3. Executes Atomic Lua Script over Redis Socket                            |
 +-----------------------------------------------------------------------------+
                 │                                             │
                 │ (Evaluation = Allowed)                      │ (Evaluation = Limit Exceeded)
                 ▼                                             ▼
=======================================       =====================================
   BACKEND MICROSERVICE VPC MESH                CLIENT ERROR EDGE RESPONSE
=======================================       =====================================
 +---------------------------------+           +---------------------------------+
 |  Order / Checkout Service       |           |  HTTP Status: 429               |
 |  - Processes Transaction        |           |  Headers:                       |
 |  - Returns 200 OK               |           |    X-RateLimit-Remaining: 0     |
 +---------------------------------+           |    Retry-After: 30              |
                                               +---------------------------------+
                 │
                 │ Read/Write Atomic Sliding Window State
                 v
===================================================================================
                     DISTRIBUTED REDIS RATE-LIMIT CLUSTER
===================================================================================
    +-----------------------------------------------------------------------+
    |  Redis Cluster Nodes (Primary / Secondary Replication)                |
    |  - Runs Atomic Lua Scripts in single-threaded event loop              |
    |  - Key: `rate:tenant_8821:v1_checkout`                                |
    |  - TTL Auto-expiry set to Window Size (e.g., 60 seconds)              |
    +-----------------------------------------------------------------------+
```

---

### 6. Interview Checklist:

When pitching or designing Rate Limiters in system design interviews:

Specify the Right Algorithm for the Requirement:

- **Token Bucket**: Pitch as the default for general API Gateways that must support bursty client traffic while guaranteeing average rate bounds.

- **Leaky Bucket**: Pitch specifically when traffic smoothing is mandatory (e.g., writing to a downstream third-party API that throws errors on sudden bursts).

- **Sliding Window Counter**: Pitch for high-scale distributed microservices to achieve high accuracy with minimal $O(1)$ memory usage.

- **Address Distributed Race Conditions Explicitly**: Always mention Redis + Lua Scripting to perform atomic read-modify-write operations, eliminating concurrency issues across distributed gateway instances.

- **Define the Client Identifier Strategy**: Explain how you construct the rate-limiting cache key (e.g.,User_ID for authenticated sessions, API Key for developer tiers, or Client IP as a fallback for unauthenticated routes while acknowledging NAT proxy challenges).

- **Discuss High-Availability Failover Strategy**: Explicitly state your system's behavior when the central caching tier fails (e.g., Fail-Open vs. Fail-Closed) and introduce L1 local memory caches to shield the distributed L2 Redis cluster from state synchronization bottlenecks.
