## System Dashboards (Prometheus, Grafana)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine an airport flight control tower.

- Prometheus is the radar telemetry array. It constantly reaches out and sweeps all incoming aircraft (microservices), recording their speed, altitude, and heading into a time-stamped radar log. It also monitors for critical danger thresholds (e.g., "Altitude dropping too fast") and fires alarms to the controllers.

- Grafana is the large glass display wall in the tower. It takes raw numeric streams from the radar logs—along with weather feeds, runway cameras, and scheduling systems—and transforms them into intuitive,real-time interactive graphs, heatmaps, and operational heat gauges for the flight controllers.

#### The Problem It Solves:

- Collecting metrics is useless if engineers cannot interpret them in real time during an active outage.

- Prometheus provides an open-source, pull-based time-series database (TSDB) and rule evaluation engine purpose-built for multi-dimensional metric scraping, storage, and querying via PromQL.

- Grafana serves as the universal visualization and dashboarding plane. It decouples display mechanics from metric storage, allowing engineers to construct unified, multi-source operational dashboards across Prometheus, Elasticsearch, Jaeger, SQL, and cloud providers in a single glass pane.

---

### 2. The Basics (Scratch Level):

#### Fundamental Components of the Prometheus + Grafana Ecosystem

```
+---------------------------------------------------------------------------------------+
| PROMETHEUS AGGREGATION & STORAGE                                                      |
|                                                                                       |
|  [ Microservice ] ──(exposes)──► /metrics (Prometheus Format)                         |
|                                      ▲                                                |
|                                      │ Scrape Interval (e.g. 15s)                     |
|                                      │                                                |
|  [ Prometheus Server ] ──────────────┴──────► Local TSDB (Head Block + WAL)           |
|         │                                          │                                  |
|         │ Evaluates Rules                          │ PromQL Queries                   |
|         v                                          v                                  |
|   [ Alertmanager ]                        [ Grafana Server ]                          |
+────────────────────────────────────────────────────┬──────────────────────────────────+
                                                    │ HTTP Dashboard Load
                                                    v
                                           [ Web Browser (User) ]
```

#### Core Architecture Terminology:

| Component                     | `Responsibility`                                                                        | `Key Characteristics`                                                                                                  |
| ----------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Exporter**                  | A lightweight sidecar or library converting application metrics into Prometheus format. | Examples: Node Exporter (OS metrics), JMX Exporter (Java JVM), kube-state-metrics(Kubernetes objects).                 |
| **Prometheus TSDB**           | Embedded append-only storage engine.                                                    | Stores metrics in 2-hour compressed blocks on local disk using Gorilla XOR encoding.                                   |
| **PromQL**                    | Prometheus Query Language.                                                              | Read-only functional query language designed for evaluating time-series operations (rates, aggregations, percentiles). |
| **Grafana Datasource**        | Abstraction layer connecting Grafana to backend databases.                              | Translates user dashboard interactions into raw API query languages (PromQL, LogQL, SQL).                              |
| **Grafana Panel & Dashboard** | Individual visual element (graph, gauge, table) grouped into a organized UI grid.       | Rendered client-side using WebGL/Canvas; auto-refreshes on a configured interval.                                      |

#### The Data Ingestion Lifecycle:

- **Target Discovery**: Prometheus queries a service discovery mechanism (e.g., Kubernetes API) to locate active pod IP addresses.
- **Scrape Execution**: At every configured scrape_interval (e.g., 15 seconds), Prometheus sends an HTTP GET /metrics request to all targets.
- **In-Memory Buffer & WAL**: Incoming samples are appended to an in-memory Head Block and written sequentially to an on-disk Write-Ahead Log (WAL) to guarantee crash durability.
- **Dashboard Query**: A user opens a Grafana dashboard. Grafana sends HTTP PromQL queries to Prometheus.
- **Panel Rendering**: Prometheus executes the PromQL query over its local TSDB indices and returns a JSON payload to Grafana, which renders the time-series vector on the user screen.

---

### 3. Deep Dive & Architecture (Mid Level):

#### Prometheus TSDB Storage Internals:

Prometheus organizes time-series data into 2-hour block directories on disk.

```
/data/prometheus
├── chunks_head/             # In-memory active sample chunks
├── wal/                     # Write-Ahead Log for head block (crash recovery)
├── 01BK6YA5PP3A1B300R38FA/  # Compacted 2-hour Block 1
│   ├── meta.json            # Block metadata & time boundaries
│   ├── index                # Inverted index (label key/value -> series ID)
│   └── chunks/              # Compressed raw metric samples
└── 01BK6YA5PP3A1B300R38FB/  # Compacted 2-hour Block 2
```

- **The Head Block**: Holds active, uncompacted samples in memory for the current 2-hour window.

- **Gorilla Compression**: Samples $(t_i, v_i)$ are compressed in memory:

- **Timestamps**: Encoded using Delta-of-Delta compression ($\Delta(\Delta t)$), reducing timestamp memory overhead to ~1.37 bytes per sample.

- **Float Values**: Encoded using XOR floating-point compression against the previous float value.

- **Compaction**: When the Head Block reaches 2 hours of data, a background thread flushes it to a new immutable disk block, creates an inverted index mapping metric labels to internal series IDs, and truncates old WAL logs.

- **PromQL Execution Mechanics**: Instant Vectors vs. Range Vectors
  Understanding how Prometheus evaluates data is critical for writing efficient Grafana queries:

- **Instant Vector**: A set of time-series where each series contains a single scalar value evaluated at a specific point in time (used for current status gauges).
- **Example**: http_requests_total{status="500"}

- **Range Vector**: A set of time-series where each series contains a range of data points going back in time from a given evaluation instant.
- **Example**: http_requests_total{status="500"}[5m] (looks back 5 minutes).

#### Handing Counter Resets with rate():

Counters continuously increase and reset to 0 on application restart. The rate() function in PromQL calculates the per-second average rate of increase over a range vector while automatically detecting and adjusting for counter resets:

$$\text{Rate} = \frac{V_{\text{last}} - V_{\text{first}} + \text{Reset Corrections}}{\Delta t}$$
Rule of Thumb: Always apply rate() or increase() on counters before aggregating with sum() or avg():

```Code snippet
# CORRECT: Calculates per-second rate per instance first, then sums them up
sum(rate(http_requests_total[5m])) by (job)

# INCORRECT: Summing raw counters hides instance-level counter resets
rate(sum(http_requests_total)[5m])
```

#### Grafana Execution Architecture & Variable Templating:

Grafana does not store time-series metrics. It operates as an orchestration layer:

```
[ Browser Client ]
      │
      │ 1. User selects dynamic variable dropdown (e.g., $namespace = "prod")
      v
[ Grafana Backend Proxy ]
      │
      │ 2. Replaces variables in panel query:
      │    "sum(rate(http_requests_total{namespace='$namespace'}[5m]))"
      │    --> "sum(rate(http_requests_total{namespace='prod'}[5m]))"
      v
[ Prometheus API Engine ]
      │
      │ 3. Returns Matrix/Vector JSON Payload
      v
[ Grafana Frontend Canvas Engine ]
      │ 4. Performs client-side transformations (e.g. Unit formatting, threshold coloring)
      v
[ Rendered SVG / WebGL Chart ]
```

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

`Scaling Prometheus`: **High Availability and Long-Term Storage (Thanos & Mimir)**
A standard Prometheus instance is single-node stateful by design and does not horizontally scale reads or writes. To achieve enterprise scale, architects combine Prometheus with distributed extension systems like Thanos or Grafana Mimir.

```
THANOS DISTRIBUTED STORAGE ARCHITECTURE

[ App Pods ]        [ App Pods ]
    │                   │
    │ (Scrape)          │ (Scrape)
    v                   v
[ Prom HA-1 ]       [ Prom HA-2 ]  <-- Dual identical Prometheus instances
 │ (Sidecar)         │ (Sidecar)
 │                   │
 ├── Writes Chunks ──┼───────────────► [ S3 / Object Storage ]
 │                   │                          ▲
 v                   v                          │
+──────────────────────────────────+             │
| Thanos Querier                   |             │ Reads Historic Data
| - Deduplicates HA-1 and HA-2     |             │
| - Merges Realtime + Object Store |─────────────┘
+─────────────────┬────────────────+
                 ▲
                 │ PromQL Query
           [ Grafana ]
```

#### 1. High Availability (HA) Scraping Pattern:

- Deploy two independent, identical Prometheus instances scraping the exact same targets.
- Both instances run a Thanos Sidecar process.
- Thanos Querier sits between Grafana and Prometheus. When Grafana issues a query, Thanos Querier fetches results from both Prometheus nodes and dynamically deduplicates matching samples using their timestamp and replica labels.

#### 2. Long-Term Storage (LTS) via Remote Write:

- Local Prometheus TSDB retention is set short (e.g., 2 hours to 2 days).
- Prometheus streams scraped samples out-of-band via Remote Write protocol (Protobuf over HTTP) to a distributed TSDB like Grafana Mimir or VictoriaMetrics.
- Historical metric chunks are compressed and stored cheaply in Object Storage (AWS S3 / GCS), allowing retention periods of years with minimal operational cost.

#### Dashboard Performance Optimization: Recording Rules:

- When a Grafana dashboard containing dozens of complex PromQL queries (e.g., evaluating rate() across millions of raw series over a 30-day window) opens, it can cause Prometheus query execution timeouts and crash the TSDB instance.

- **Solution**: Recording Rules Recording rules allow Prometheus to pre-compute heavy, frequently needed PromQL expressions in the background and save the result as a new, low-cardinality time-series metric.

```YAML
# prometheus.rules.yml
groups:
 - name: HTTPAggregatedRules
   interval: 15s
   rules:
     # Pre-computes 5-minute error rate grouped by service
     - record: job:http_requests_error:rate5m
       expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
```

- In Grafana, dashboards query the pre-computed metric job:http_requests_error:rate5m directly. Query execution times drop from seconds/minutes to milliseconds.

#### Architecture Trade-Off Matrix:

| Strategy                          | `Advantages`                                                                                         | `Disadvantages`                                                                                                 |
| --------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Local Prometheus TSDB Only**    | Zero complex dependencies; extremely fast local SSD reads.                                           | Limited retention capacity; single point of failure; no unified cross-cluster view.                             |
| **Thanos (Sidecar Architecture)** | Low write overhead on Prometheus; seamless S3 upload; easy add-on to existing Prometheus setups.     | Query latency depends on object store read performance for deep historical queries.                             |
| **Mimir / Remote Write**          | Complete decoupling of scraping from storage; central query processing layer; multi-tenancy support. | Higher network bandwidth usage from continuous Remote Write streaming; requires managing a large Mimir cluster. |

---

### 5. Text-Based Architecture Diagram:

**Enterprise Prometheus & Grafana Telemetry Ecosystem**

```
===================================================================================================
1. DATA EMISSION & TARGET DISCOVERY
===================================================================================================

 [ K8s API Server ] ──(Service Discovery)──► [ Prometheus Agent / Server Cluster ]
                                                     │
        ┌────────────────────────────────────────────┼────────────────────────────────────────────┐
        │ Pull Scrape (HTTP /metrics)                │ Pull Scrape                                │ Pull Scrape
        v                                            v                                            v
 [ Pod: Payment API ]                      [ Pod: Order API ]                      [ Node Exporter ]
 (Custom Client SDK)                       (Custom Client SDK)                     (System Infrastructure)

===================================================================================================
2. LOCAL STORAGE, PRE-COMPUTATION & LONG-TERM BACKEND
===================================================================================================

 [ Prometheus Server Node ]
  ├── In-Memory Head Block (Gorilla XOR Compression)
  ├── Disk WAL (Write-Ahead Log)
  ├── Background Engine: Evaluates Recording Rules & Alert Rules
  │                                  │
  │ Remote Write (OTLP/Protobuf)     │ Alerts Firing
  v                                  v
 +────────────────────────────+    +─────────────────────────────────────────────────────────────+
 | Long-Term Distributed TSDB |    | Alertmanager Cluster                                        |
 | (Grafana Mimir / Thanos)   |    | - Deduplicates & Groups Alerts                              |
 |                            |    | - Dispatches to PagerDuty / Slack                           |
 +──────────────┬─────────────+    +─────────────────────────────────────────────────────────────+
                │
                v
 +────────────────────────────+
 | Cloud Object Storage (S3)  |
 | (Compressed 2h Chunks)     |
 +──────────────┬─────────────+
                │
===================================================================================================
3. VISUALIZATION & UNIFIED DASHBOARDING
===================================================================================================
                │
                │ PromQL Queries (HTTP REST API)
                v
 +───────────────────────────────────────────────────────────────────────────────────────────────+
 | GRAFANA ENTERPRISE SERVER                                                                     |
 |                                                                                               |
 |  [ Query Caching Engine ]  ──► Checks Redis cache for pre-evaluated panel windows             |
 |  [ Backend Proxy ]        ──► Injects templated variables ($environment, $cluster)             |
 |  [ Multi-Tenant RBAC ]    ──► Restricts dashboard view permissions by team                    |
 +──────────────────────────────┬────────────────────────────────────────────────────────────────+
                                │ JSON Data Payloads
                                v
 +───────────────────────────────────────────────────────────────────────────────────────────────+
 | CLIENT GRAPHICAL UI                                                                           |
 | (Grafana Canvas / WebGL: Renders latency heatmaps, error gauges, and topology panels)         |
 +───────────────────────────────────────────────────────────────────────────────────────────────+
```

---

### 6. Interview Checklist:

When discussing systems dashboarding with Prometheus and Grafana in a system design interview:

- **Decouple Telemetry Storage from Visualization**: Clarify that Prometheus serves as the stateful time-series scraping and alerting backend, whereas Grafana acts as a stateless, multi-datasource presentation layer.

- **Address Scalability Bottlenecks**: Explain how standard Prometheus single-node limitations are solved using Remote Write to distributed TSDBs (Thanos, Grafana Mimir) backed by Object Storage (S3) for long-term retention.

- **Highlight Dashboard Performance Optimization**: Mention Recording Rules to pre-compute expensive aggregations out-of-band, preventing dashboard load spikes from exhausting TSDB memory/CPU.

- **Master PromQL Rules of Thumb**: Emphasize that rate calculations (rate(), increase()) must always be evaluated over range vectors on raw counters before applying mathematical spatial aggregations like sum().
