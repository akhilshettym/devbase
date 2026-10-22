## Alerting & Anomaly Detection

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a modern building equipped with a fire safety system.

- A Static Alert is like a standard smoke detector: if smoke density exceeds a fixed threshold, the alarm sounds. It is simple and predictable, but if someone burns toast in the breakroom, it triggers a full building evacuation (a false positive).

- Anomaly Detection is like a smart climate controller analyzing historical building patterns. It understands that temperature and humidity naturally rise every weekday at 9:00 AM when hundreds of workers enter the office. It won't sound an alarm for that expected spike. However, if temperature spikes by 10°C at 3:00 AM on a Sunday, it immediately flags a severe anomaly long before a static smoke threshold is ever breached.

#### The Problem It Solves:

- Raw operational telemetry (metrics, logs, traces) is useless if humans must manually watch dashboards to catch outages. Modern distributed systems generate millions of time-series signals per minute.

- Alerting converts metric streams into actionable operational signals. It automatically notifies engineers when predefined system invariants or Service Level Objectives (SLOs) are violated.

- Anomaly Detection eliminates rigid hardcoded thresholds by dynamically learning baseline behavioral patterns (seasonality, trends, variance). It detects subtle "unknown-unknown" failures (e.g., a silent 30% drop in checkout conversions) that static thresholds completely miss.

---

### 2. The Basics (Scratch Level):

#### Core Terminology:

- Alert Rule: A programmatic condition evaluated against metric streams (e.g., cpu_utilization > 85%).

#### Alert State Lifecycle:

- **OK**: Metric is within normal parameters.
- **Pending**: The alert condition is met, but waiting for a buffer duration (e.g., FOR 5m) to prevent transient noise from firing notifications.
- **Firing**: The alert condition persisted beyond the pending window; notifications are actively dispatched.
- **Resolved**: The metric returns to safe bounds.
- **Notification Routing**: The mechanism that routes firing alerts to channels (PagerDuty, Opsgenie, Slack,Webhooks) based on severity, service ownership, and time of day.
- **Alert Fatigue**The dangerous operational state where engineers are bombarded with non-actionable,duplicate, or low-severity alerts, causing them to ignore critical system notifications.

#### SLI, SLO, and Error Budget Alerting:

- Modern engineering teams avoid alerting on raw system metrics (e.g., CPU, Memory) in favor of Service Level Objectives:

| Concept                           | `Definition`                                                                | `Example`                                                                 |
| --------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **SLI (Service Level Indicator)** | A quantitative measure of service performance.                              | $\frac{\text{Successful Requests (HTTP 2xx/3xx)}}{\text{Total Requests}}$ |
| **SLO (Service Level Objective)** | A target reliability goal set for an SLI over a sliding window.             | 99.9% success rate over a 30-day rolling window.                          |
| **Error Budget**                  | The acceptable rate of failure derived from the SLO ($100\% - \text{SLO}$). | For a 99.9% SLO, the error budget is 0.1% failed requests.                |
| **Burn Rate Alerting**            | Alerts based on how fast a system is consuming its error budget.            | Alert if 2% of the total monthly error budget is burned in 1 hour.        |

---

### 3. Deep Dive & Architecture (Mid Level):

#### The End-to-End Alert Evaluation Engine:

```
[ TSDB / Metric Engine ]
       │
       │ Periodic Rule Evaluation (e.g., every 15s)
       v
+─────────────────────────────────────────────────────────+
| ALERT EVALUATOR ENGINE                                  |
|  - Queries time-series expressions                      |
|  - Evaluates boolean conditions                         |
|  - Manages State Transitions: OK -> Pending -> Firing   |
+───────────────────────────┬─────────────────────────────+
                           │ Alert Payload
                           v
+─────────────────────────────────────────────────────────+
| ALERT ROUTER & MANAGER (e.g., Alertmanager)             |
|  1. Deduplication: Hash fingerprinting of label sets    |
|  2. Inhibition: Mute downstream alerts if parent fires  |
|  3. Grouping: Aggregate matching alerts into one batch  |
|  4. Silencing: Check against active maintenance windows |
+───────────────────────────┬─────────────────────────────+
                           │ Aggregated Notification Batch
                           v
+─────────────────────────────────────────────────────────+
| DISPATCHERS (PagerDuty, Webhooks, Slack)                |
+─────────────────────────────────────────────────────────+
```

`Alert Pipeline Operations`: **Deduplication, Grouping, and Inhibition**

- **Fingerprinting & Deduplication**: When multiple instances of a microservice fire the exact same alert simultaneously, the Alert Manager hashes key label sets (e.g., alertname, service, cluster) into a unique fingerprint to prevent sending multiple identical notifications.
- **Grouping**: Instead of sending 50 individual alerts when a database rack fails, the pipeline buffers incoming alerts over a sliding window (e.g., group_wait = 30s) and merges them into a single consolidated payload: "50 pods in cluster-us-east-1 disconnected from Database."
- **Inhibition**: A rule-based suppression mechanism where a high-level alert mutes lower-level alerts.
- **Example**: If an alert NodeNetworkDown fires for Host-A, an inhibition rule suppresses all downstream InstanceDown, PodUnreachable, and DBConnectionFailed alerts associated with Host-A.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Anomaly Detection Algorithms:

Static thresholds fail on metrics with time-of-day or day-of-week seasonality (e.g., e-commerce traffic peaking at 8:00 PM and dropping at 3:00 AM). Statistical and ML-based models dynamically adapt thresholds.

```
STATISTICALLY DETECTED ANOMALY (STL / Seasonal Baseline)
  Metric Value
    ▲
    │       Actual Traffic Spike
    │              /\        /----\  <-- Upper Dynamic Bound
   ─┼─/\──/\──────/──\──────/──────\────── Dynamic Expected Baseline
    │/  \/  \    /    \    /        \    <-- Lower Dynamic Bound
    │        \--/      \--/          \
    └───────────────────────────────────► Time
                       ▲
                       │ Anomaly Detected: Traffic dropped below lower bound
                         relative to typical Tuesday 3 AM baseline!
```

#### 1. Z-Score (Standard Deviation Thresholding):

Measures how many standard deviations ($\sigma$) a current data point $x_t$ is away from the historical mean ($\mu$).

$$Z = \frac{x_t - \mu}{\sigma}$$

- **Anomaly Condition**: $\vert{}Z\vert{} > k$ (typically $k = 3$).
- **Trade-off**: Works well for stationary Gaussian distributions (e.g., server temperature). Fails completely on metrics with strong linear trends or daily cycles because $\mu$ and $\sigma$ become skewed.

#### 2. Exponentially Weighted Moving Average (EWMA):

Applies exponentially decreasing weights to older data points, making the model reactive to recent trend shifts while smoothing out transient spikes.

$$S_t = \alpha \cdot x_t + (1 - \alpha) \cdot S_{t-1}$$
Where $\alpha \in (0, 1)$ represents the memory decay factor.

#### 3. STL Decomposition (Seasonal and Trend decomposition using Loess):

Splits a time-series time signal $Y_t$ into three additive components:

$$Y_t = T_t + S_t + R_t$$

- Where $T_t$ is the overall Trend, $S_t$ is the Seasonal pattern, and $R_t$ is the Residual noise.

- **Anomaly Mechanism**: The system models $T_t + S_t$ as the expected baseline. If the residual $\vert{}R_t\vert{}$ exceeds dynamic statistical boundaries, an anomaly is flagged.
- **Use Case**: Critical business metrics (e.g., payment gateway transaction volume).

#### Multi-Window Multi-Burn-Rate Alerting:

Relying on single-window thresholds creates severe trade-offs between MTTD (Mean Time to Detect) and Alert Reset Lag:

- A short window (e.g., 5 mins) detects catastrophic outages immediately, but causes false alarms on short spikes.
- A long window (e.g., 1 hour) prevents false alarms, but takes hours to resolve after an incident is fixed.

`Pro Solution`: **SRE Multi-Burn-Rate Strategy using dual sliding windows**:

An alert fires only if both the short-term window and long-term window are burning budget simultaneously.This guarantees high precision, fast response times, and instant resolution when error spikes clear.

---

### 5. Text-Based Architecture Diagram:

**Scalable Alert Engine with Real-Time Anomaly Detection Pipeline**

```
===================================================================================================
1. INGESTION & ANOMALY ANALYSIS PIPELINE
===================================================================================================

[ Incoming Metric Stream ]
        │
        ├───► [ TSDB Storage Engine ] (Prometheus / ClickHouse)
        │
        └───► [ Stream Processor Engine (Flink / Spark) ]
                    │
                    ├── Component 1: STL Seasonal Model (Calculates Baseline: T_t + S_t)
                    ├── Component 2: EWMA / Residual Calculator
                    │
                    v
              [ Anomaly Score Computation ]
                    │ (Outputs: anomaly_score = |Residual| / StDev)
                    v
              [ Dynamic Metric Emitted to TSDB ] (e.g., metric_name:anomaly_score)

===================================================================================================
2. EVALUATION & ROUTING ENGINE
===================================================================================================

[ TSDB Query Engine ]
        │
        │ Periodic Rule Evaluation (15s Loop)
        v
+───────────────────────────────────────────────────────────────────────────────────────────────+
| ALERT RULE EVALUATOR                                                                          |
|  - Rule A (Static): rate(http_errors[5m]) > threshold                                         |
|  - Rule B (Dynamic): anomaly_score > 3.0 FOR 5m                                              |
|  - Rule C (Burn-Rate): burn_rate_1h > 14.4 AND burn_rate_5m > 14.4                           |
+──────────────────────────────────────────────┬────────────────────────────────────────────────+
                                               │ Pending -> Firing
                                               v
+───────────────────────────────────────────────────────────────────────────────────────────────+
| ALERTMANAGER ROUTING PIPELINE                                                                 |
|                                                                                               |
|  [ Deduplication ] ──► Hashes labels (alertname + service + cluster)                          |
|            │                                                                                  |
|            v                                                                                  |
|  [ Inhibition ]    ──► Matches rules: If "NodeDown" == True -> Suppress "PodUnreachable"      |
|            │                                                                                  |
|            v                                                                                  |
|  [ Grouping ]      ──► Buffers matching alerts over group_wait (30s) -> Bundles into 1 Payload |
+──────────────────────────────────────────────┬────────────────────────────────────────────────+
                                               │
                                               v
===================================================================================================
3. NOTIFICATION DISPATCH
===================================================================================================
                                               │
                    ┌──────────────────────────┼──────────────────────────┐
                    │ P1 Severity              │ P3 Severity              │ Webhook Engine
                    v                          v                          v
             [ PagerDuty API ]          [ Jira / Slack ]           [ Auto-Scaler / Lambda ]
```

---

### 6. Interview Checklist:

When pitching alerting and anomaly detection in a system design interview:

- **Distinguish Symptom vs. Cause Alerting**: State that high-value systems alert on symptoms that impact users (e.g., elevated error rates, latency spikes, SLO budget burn) rather than raw infrastructure causes (e.g., CPU high).

- **Explain Multi-Burn-Rate SLO Alerting**: Demonstrate seniority by explaining why dual-window burn-rate alerts eliminate false positives while guaranteeing rapid detection of critical SLO failures.

- **Outline Alert Noise Reduction Controls**: Mention the exact mechanisms used to battle alert fatigue:Deduplication (fingerprinting), Grouping (batching), and Inhibition (tree-based parent mutes child).

- **Frame Anomaly Detection Realistically**: Emphasize that dynamic/statistical anomaly detection (STL, Z-score) is best reserved for seasonal business metrics. Acknowledge its main flaw—baseline poisoningduring extended outages—and state why static alerts remain preferred for hard infrastructure boundaries.

- Would you like to move on to the next subtopic under Phase 10 (e.g., Health Checks, Readiness/Liveness Probes, and Heartbeats or Log Aggregation & Search Architectures)?
