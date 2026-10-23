## Access Control Lists (ACL, RBAC, ABAC) & Rule Engines

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine securing a massive corporate headquarters building.

- **ACL (Access Control List)**: A paper list taped to the door of Room 302 listing 5 specific employee names. It is simple to read, but if 10,000 employees join the company, updating paper lists taped to thousands of individual doors becomes an administrative nightmare.

- **RBAC (Role-Based Access Control)**: Color-coded security badges. "Red Badges" (Engineers) unlock all Server Rooms; "Green Badges" (Sales) unlock Conference Rooms. It is easy to manage because security gives an employee a badge color once, and the doors grant access based solely on that badge color.

- **ABAC (Attribute-Based Access Control)**: A smart automated security guard at every door that evaluates context: "You can enter Server Room 3 ONLY IF you hold an Engineer badge, AND you belong to the Infrastructure Team, AND it is between 9 AM and 5 PM, AND you are physically tapping in from an encrypted device."

- **Rule Engine (Policy Engine)**: The centralized brain that holds the master company policy handbook and evaluates these complex, multi-factor rules in milliseconds whenever someone taps their badge.

#### The Problem It Solves:

- In modern applications, hardcoding authorization logic directly into application business logic (e.g., if (user.role == 'admin' && user.dept == resource.dept)) causes severe architectural risks:

- **Coupling & Drift**: Access control logic becomes scattered across hundreds of microservice repositories,making security audits nearly impossible and creating inconsistent enforcement.

- **Inflexibility**: Changing a access rule requires modifying source code, passing code reviews, and re-deploying production microservices.

- Decoupling authorization using Rule/Policy Engines separates Policy Enforcement (intercepting requests) from Policy Decisioning (evaluating logic), allowing enterprise access policies to be centrally managed,dynamically updated, and audited without changing a single line of application code.

---

### 2. The Basics (Scratch Level):

#### Access Control Models Comparison

| Model     | `Core Concept`                                      | `Granting Mechanism`                                                  | `Pros`                                                                                  | `Cons / Bottlenecks`                                                                                                                                                        |
| --------- | --------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ACL**   | Access attached directly to the Resource.           | Resource X -> User A: Read, User B: Write                             | Simple to understand for small systems; fine-grained per resource.                      | Severe administrative overhead; impossible to scale across millions of resources and users.                                                                                 |
| **RBAC**  | Access mapped to Roles, roles assigned to Subjects. | Subject -> Role -> Permission -> Resource                             | Scales exceptionally well; clean governance and auditing structure.                     | Role Explosion: Cannot handle dynamic logic (e.g., "allow edit only if user owns the document") without creating thousands of hyper-specific roles (Editor_DepartmentA_US). |
| **ABAC**  | Access evaluated dynamically via Attributes.        | IF (Subject.Attr AND Resource.Attr AND Env.Attr) THEN Allow           | Infinite flexibility; fine-grained; context-aware (time, location, device status).      | Complex logic configuration; higher runtime CPU/IO evaluation overhead.                                                                                                     |
| **ReBAC** | Access evaluated via Relationships(Graph-based).    | Subject -(member_of)-> Group -(owner_of)-> Folder -(parent_of)-> File | Perfect for social graphs, shared folders, multi-tenant hierarchy (e.g., Google Drive). | Requires high-performance graph database or specialized indexing engine (e.g., Google Zanzibar).                                                                            |

#### Core Terminology:

- **Subject**: The entity requesting access (e.g., User ID, Service Account, IP Address).
- **Object / Resource**: The target entity being accessed (e.g., Database record, File, API Endpoint).
- **Action**: The operation attempted (e.g., READ, WRITE, DELETE, APPROVE).
- **Environment / Context**: Operational metadata surrounding the request (e.g., CurrentTime, ClientIP,DeviceHealthScore).

---

### 3. Deep Dive & Architecture (Mid Level):

#### The Decoupled Policy Evaluation Standard (XACML / OPA Pattern):

To achieve scalable authorization across microservices, systems use the standardized Policy Decision/Enforcement architecture (pioneered by XACML and modernized by engines like Open Policy Agent - OPA):

```
                               +───────────────────────────────────────────+
                               | PAP (Policy Administration Point)         |
                               | (Git Repo / Central Policy Store)         |
                               +─────────────────────┬─────────────────────+
                                                     │ Pushes Policy Updates (Rego / Json)
                                                     v
[ Client Request ]             +───────────────────────────────────────────+
      │                        | PDP (Policy Decision Point)               |
      │ HTTP GET /invoice/42   | (Policy Engine: OPA / Custom Engine)      |
      v                        |                                           |
+──────────────────────────+   |  Evaluating Policy Rules Against Inputs   |
| PEP                      |──►|                                           |
| (Policy Enforcement Point|   +─────────────────────┬─────────────────────+
|  API Gateway / Service   |◄────────────────────────┼─────────────────────┤
|  Mesh Sidecar)           |   Returns ALLOW / DENY  │ Fetch Missing       │ Returns
+────────────┬─────────────+                         │ Attributes          │ Attributes
             │                                       v                     │
             │ Allowed                               +─────────────────────┴─────+
             v                                       | PIP (Policy Info Point)   |
+──────────────────────────+                         | (Redis / Database / User  |
| Target Microservice      |                         |  Directory / Auth Token)  |
+──────────────────────────+                         +───────────────────────────+
```

#### Component Breakdown & Execution Flow:

- **PEP (Policy Enforcement Point)**: The gatekeeper embedded in hot code paths (e.g., API Gateway,Envoy Proxy sidecar, or application middleware). It intercepts the incoming request, pauses execution,builds an evaluation context payload, and queries the PDP.

- **PDP (Policy Decision Point)**: The stateless authorization engine. It executes declarative policy rules (written in domain-specific languages like Rego or JSON policies) against the incoming context and returns a strict ALLOW or DENY decision.

- **PIP (Policy Information Point)**: The data retriever. If the PDP evaluates a rule requiring data not present in the initial PEP request (e.g., fetching user.department from Redis or resource.owner_id from PostgreSQL), the PDP queries the PIP to fetch contextual attributes dynamically.

- **PAP (Policy Administration Point)**: The control plane where security administrators write, version-control (via GitOps), and distribute policy definitions to distributed PDP instances.

#### How Rule Engines Work Under the Hood:

Modern rule engines avoid evaluating every rule linearly using brute force. Instead, they compile policies into optimized execution structures:

- **RETE Algorithm / Directed Acyclic Graphs (DAGs)**: Constructs a decision tree in memory that memoizes shared evaluation paths. If 50 rules check IF subject.status == 'ACTIVE', the RETE network checks that node once and branches the result downstream, reducing algorithmic complexity from $O(N)$(where $N$ is rule count) to $O(\log N)$.
- **Partial Query Evaluation**: Compiles dynamic rules down to localized SQL WHERE clauses that can be pushed directly down to database engines for bulk resource filtering.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Mitigating Hot-Path Evaluation Latency:

Querying a remote central Policy Engine (PDP) and fetching attributes from a database (PIP) over the network on every single internal microservice call introduces unacceptable 20ms–100ms latency overhead.

#### 1. The Sidecar PDP Pattern (Local In-Memory Evaluation):

- Deploy the Policy Engine (e.g., OPA) as a localhost sidecar container inside the exact same Kubernetes Pod as the application microservice.
- Communication occurs over ultra-fast local Unix Domain Sockets or localhost gRPC (~1ms overhead).
- Policies are asynchronously synchronized from the PAP to sidecar memory in the background.

```
+-------------------------------------------------------------------------------+
| KUBERNETES POD                                                                |
|                                                                               |
|  [ App Container ] ───(Unix Socket < 1ms)───► [ OPA PDP Sidecar Container ]   |
|                                                     ▲                         |
+─────────────────────────────────────────────────────│─────────────────────────+
                                                     │ Async Sync
                                       +─────────────┴─────────────+
                                       | Central Policy Repo (PAP) |
                                       +───────────────────────────+
```

#### 2. Token-Pushed Context (Attribute Pre-fetching):

- To avoid the PDP querying a PIP (Database) during rule evaluation, inject essential user attributes directly into the user's JWT Claims or W3C Baggage during initial authentication (e.g., roles, department_id,clearance_level). The PEP extracts these attributes from the incoming JWT and sends a complete input document to the PDP, achieving zero-IO evaluation.

#### Scaling Resource Lists: The "Filter" Problem:

- Evaluating ALLOW or DENY for a single resource (Can Alice read File 42?) is straightforward. But how do you handle list queries: "Show Alice all files she is allowed to read out of 10 million records?"

- **Anti-Pattern (Fetch then Filter)**: Query the database for all 10 million rows, loop over every row, and execute a PDP call for each. This causes memory exhaustion and catastrophic database I/O bottlenecks.

- **Pro Solution 1 (Policy-to-SQL Compilation)**: The Policy Engine translates the active ABAC policy into an AST (Abstract Syntax Tree) and compiles it into a native SQL condition:
- **Policy**: `Subject.Dept == Resource.Dept AND Resource.IsConfidential == False`
- **Generated SQL**: `SELECT * FROM files WHERE dept = 'Engineering' AND is_confidential = false;`

- **Pro Solution 2 (ReBAC / Google Zanzibar Model)**: Store relationship tuples (document:42#viewer@group:engineering#member) in a globally distributed, highly indexed graph store.List evaluation is executed via fast graph traversal indices rather than evaluation rules.

#### Failure Modes & Reliability Guards:

- **Fail-Closed Default**: If a PDP sidecar crashes, network times out, or policy syntax errors occur, the PEP must unconditionally deny access.
- **Policy Versioning & Canary Rollouts**: Treat policies as production code. CI/CD pipelines must run automated unit tests against Rego/Rule files and deploy policies via progressive canary rings to avoid catastrophic global access lockouts.

---

### 5. Text-Based Architecture Diagram:

**Scalable Distributed ABAC / Rule Engine System Architecture**

```
===================================================================================================
1. CONTROL PLANE: POLICY ADMINISTRATION & DISTRIBUTION (GitOps)
===================================================================================================
[ Security Admin ] ──► [ Git Repository (Policy Rules) ] ──► [ CI/CD Pipeline (Unit Testing) ]
                                                                    │
                                                                    │ Push Verified Bundles
                                                                    v
                                                      [ Central Policy Storage (PAP) ]
                                                                    │
                                                                    │ Stream Updates (gRPC)
                                                                    v
===================================================================================================
2. DATA PLANE: LOCAL ENFORCEMENT & SIDECAR EVALUATION
===================================================================================================
[ Incoming HTTP/gRPC Request ]
             │
             v
 +─────────────────────────────────────────────────────────────────────────────────────────────+
 | API GATEWAY / ENVOY PROXY (PEP)                                                             |
 |  - Extracts Bearer JWT Token                                                                |
 |  - Builds JSON Context Document:                                                            |
 |    {                                                                                        |
 |      "subject": {"id": "usr_123", "dept": "finance"},                                       |
 |      "action": "READ",                                                                      |
 |      "resource": {"id": "report_99", "sensitivity": "HIGH"}                                 |
 |    }                                                                                        |
 +──────────────────────────────────────────────┬──────────────────────────────────────────────+
                                                │
                                                │ Local Inter-Process Call (< 1ms)
                                                v
 +─────────────────────────────────────────────────────────────────────────────────────────────+
 | LOCAL POLICY ENGINE SIDECAR (PDP - Open Policy Agent)                                       |
 |                                                                                             |
 |  - Reads In-Memory Compiled Policy Rules                                                    |
 |  - Executes Decision Tree (RETE / AST Algorithm)                                            |
 |                                                                                             |
 |  - If missing contextual attribute:                                                         |
 |    └── Queries PIP (Local Redis Cache) ──► Fetch User Risk Score                            |
 |                                                                                             |
 |  - Evaluates: `ALLOW = (subject.dept == resource.dept) AND (risk_score < 50)`               |
 +──────────────────────────────────────────────┬──────────────────────────────────────────────+
                                                │
                                                │ Returns JSON Response: {"allow": true}
                                                v
 +─────────────────────────────────────────────────────────────────────────────────────────────+
 | APPLICATION SERVICE                                                                         |
 | (Executes core business logic knowing request is cryptographically and logically validated) |
 +─────────────────────────────────────────────────────────────────────────────────────────────+
```

---

### 6. Interview Checklist:

When pitching access control architectures in a system design interview:

- **Distinguish Control Models**: Start by evaluating complexity needs: Recommend RBAC for simple coarse-grained role checks, ABAC when decisions require dynamic contextual attributes (time, IP,ownership), and ReBAC (Zanzibar) for graph-based document/folder hierarchies.

- **Proactively Decouple PEP and PDP**: Emphasize separating enforcement from decision-making.Highlight using a dedicated policy engine (e.g., OpenPolicyAgent / OPA) to eliminate hardcoded authorization spaghetti in application code.

- **Address Latency in the Hot Path**: Explicitly solve policy execution latency by placing the Policy Decision Point (PDP) as a localhost sidecar container, pre-loading context into JWT claims, and caching attribute lookups in Redis.

- **Solve the "Filter List" Problem**: Demonstrate senior depth by explaining how to avoid N+1 policy checks over large dataset queries through Policy-to-SQL AST compilation or pre-computed graph relationship indices.
