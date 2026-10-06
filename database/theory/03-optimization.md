## 3. Query Optimization & Data Modeling:

- **Data Modeling Trade-offs**: When to apply Normalization (1NF–3NF) for data integrity versus Denormalization / Document Embedding for read efficiency.

- **Execution Plans & Joins**: How database query planners execute operations using Nested Loops, Hash Joins, and Merge Joins, and how to interpret execution plans.

- **Application Bottlenecks**: Identifying and fixing common performance traps like the N+1 query problem, connection pool exhaustion, and missing query caches.

---

Query optimization and data modeling dictate how application code interacts with the underlying storage and transaction engines. Understanding these mechanics prevents performance anti-patterns and helps you master system design and database performance questions.

### 1. <u>Data Modeling: Normalization vs. Denormalization</u>:

Data modeling balances write integrity against read latency.

```
   NORMALIZED MODEL (3NF) DENORMALIZED / DOCUMENT MODEL
   +-----------------------+ +-------------------------------+
   | USERS | | ORDERS |
   | id | name | email | +-------------------------------+
   +-----------------------+ | id: 101 |
   │ (1:N) | order_date: "2026-10-05" |
   ▼ | total_amount: 150.00 |
   +-----------------------+ | customer: { |
   | ORDERS | | id: 1, |
   | id | user_id | amount | | name: "Alice", |
   | | (FK) | | | email: "alice@example.com" |
   +-----------------------+ | } |
   │ (1:N) | items: [ |
   ▼ | { item_id: 50, qty: 2 } |
   +-----------------------+ | ] |
   | ORDER_ITEMS | +-------------------------------+
   | id | order_id | qty | (Single read fetches all data;
   +-----------------------+ duplication requires write fanout)
```

#### Normalization (1NF to 3NF):

Normalization eliminates data redundancy and structural anomalies by decomposing large tables into smaller, linked entities.

- **First Normal Form (1NF)**: Every cell contains a single atomic value (no nested arrays or CSV strings), and every table has a unique primary key.
- **Second Normal Form (2NF)**: Satisfies 1NF and removes partial dependencies: every non-key column must depend on the entire primary key (relevant for composite keys).
- **Third Normal Form (3NF)**: Satisfies 2NF and removes transitive dependencies: non-key columns must not depend on other non-key columns. ("Every attribute must depend on the key, the whole key, and nothing but the key").

**Advantages**: Prevents insertion, update, and deletion anomalies. Updates execute in $O(1)$ time on a single row without leaving stale duplicates elsewhere.
**Disadvantages**: Reconstructing an entity requires joining multiple tables. As data volumes scale, join latency grows due to random memory and disk accesses across multiple B+ Trees.

#### Denormalization & Document Modeling:

Denormalization intentionally duplicates data or embeds nested relationships directly inside an entity to eliminate join overhead during reads.

Strategies:

- **Column Duplication**: Storing user_name directly in the orders table alongside user_id.
- **Pre-Calculated Aggregates**: Storing total_order_count on a users table instead of calculating COUNT(\*) at runtime.
- **Document Embedding**: Storing child arrays (e.g., order_items) directly inside an order document.

The Trade-Off Matrix:

| Metric                | `Normalized(3NF)`                               | `Denormalized/Document`                                         |
| --------------------- | ----------------------------------------------- | --------------------------------------------------------------- |
| **Read Latency**      | Higher (Requires multi-table `JOIN` operations) | Very Low (Single key-value/row scan reads full entity)          |
| **Write Latency**     | Fast & Atomic (Update 1 row in 1 table)         | Slower (Requires updating multiple duplicate records)           |
| **Data Integrity**    | Enforced by relational constraints & FKs        | Managed by application logic (Risk of stale/orphaned data)      |
| **Storage Footprint** | Minimal (Zero duplicated string data)           | Higher (Redundant strings & structures repeated across records) |

---

### 2. <u>Query Optimization & Join Mechanics</u>:

When you send a SQL statement to a database, it goes through a multi-stage pipeline before touching disk.

```
                 QUERY OPTIMIZATION PIPELINE

[ SQL String ] ──► ( 1. Parser ) ──► Abstract Syntax Tree (AST)
──► ( 2. Query Rewriter ) ──► Logical Execution Plan
──► ( 3. Cost-Based Opt. ) ──► Physical Execution Plan (Lowest Cost)
──► ( 4. Execution Engine ) ──► Streams Row Batches
```

#### The Cost-Based Optimizer (CBO):

The optimizer evaluates hundreds of theoretical physical execution plans and selects the one with the lowest estimated Cost (a weighted metric combining expected Disk I/O operations, CPU instructions, and Buffer Pool memory usage).

- **Cardinality Estimation**: The CBO estimates how many rows every step of a query will output using table Statistics and Histograms.

- **Stale Statistics Failure**: If statistics are outdated, the optimizer might estimate that a query filter returns $10$ rows when it actually returns $10,000,000$ rows. It will mistakenly choose a slow Index Scan or Nested Loop Join over a fast Table Scan or Hash Join.

#### Physical Join Algorithms:

Understanding how the database physically joins two tables ($Table\ A$ and $Table\ B$) is a core technical interview topic.

##### 1. Nested Loop Join:

The database iterates through every row of the outer table and searches for matching rows in the inner table.

```
Foreach row 'a' in Table_A (Outer):
Foreach row 'b' in Table_B (Inner):
if a.key == b.key:
emit (a, b)
```

- **Complexity**: $O(M \times N)$ without indexes. With an index on $Table\ B$'s join column (Index Nested Loop Join), complexity drops to $O(M \log N)$.
- **Optimal Use Case**: The outer table ($M$) is small (e.g., $< 100$ rows) and the inner table ($N$) has a highly selective index on the join key.

##### 2. Hash Join:

The database performs a two-pass hash calculation to join unsorted datasets without relying on indexes.

```
Phase 1 (Build): Read smaller Table_A into Memory Hash Table hashed by join key.
Phase 2 (Probe): Stream larger Table_B, hash its join key, and probe Hash Table for matches.
Complexity: $O(M + N)$ time complexity and $O(\min(M, N))$ memory space.
```

- **Spill to Disk (Grace Hash Join)**: If the Hash Table exceeds available RAM (work_mem), the engine partitions both tables onto disk using the same hash function and joins partitions iteratively.
- **Optimal Use Case**: Large, unsorted datasets joining on equality conditions (A.key = B.key).

##### 3. Sort-Merge Join:

Both datasets are sorted by the join key (if not already sorted by a B+ Tree index) and merged in a single coordinated pass.

```
Sort Phase: Sort Table_A by key. Sort Table_B by key.
Merge Phase: Maintain Pointer_A and Pointer_B. Advance pointers in parallel to match keys.
```

- **Complexity**: $O(M \log M + N \log N)$ if sorting is required; $O(M + N)$ if inputs are pre-sorted by an index.
- **Optimal Use Case**: Joining large tables where inputs are already pre-sorted, or for inequality range joins (A.key <= B.key).

---

### 3. <u>Application Bottlenecks & Real-World Anti-Patterns</u>:

#### The N+1 Query Problem:

The N+1 problem occurs when an application fetches $1$ parent entity and then executes $N$ separate database queries inside a loop to retrieve associated child records.

##### Query to fetch parents:

```SQL
SELECT \* FROM authors WHERE status = 'ACTIVE'; -- Returns 100 rows

-- N (100) additional queries executed in a loop:
SELECT _ FROM books WHERE author_id = 1;
SELECT _ FROM books WHERE author_id = 2;
...
SELECT \* FROM books WHERE author_id = 100;
```

- **Impact**: Introduces $N+1$ network roundtrips over the wire, saturating connection pools and inflating API latency.

##### Remedies:

- **SQL Join**: Fetch parent and children in a single query using JOIN.
- **Batch In-Query**: Collect parent IDs and fetch children in bulk: WHERE author_id IN (1, 2, ..., 100).
- **DataLoader Pattern**: In GraphQL/microservices, batch and deduplicate key requests within a single event-loop tick.

#### Connection Pool Exhaustion & Sizing Math:

Opening a raw database connection is expensive: it requires a TCP handshake, TLS negotiation, authentication, and allocating a server-side backend process or thread (often consuming 2–10 MB RAM per connection).

Applications use a Connection Pool (e.g., HikariCP) to reuse established database connections.

```
[ App Thread 1 ] ──┐
[ App Thread 2 ] ──┼──► [ CONNECTION POOL ] ──► ( 10 Active DB Connections ) ──► [ DB Server ]
[ App Thread N ] ──┘ (Requests wait here)
```

- **Sizing Myth**: "More Connections = Faster Performance"

Adding hundreds of connections to a database degrades performance. When active connections exceed physical hardware capacity, the OS CPU scheduler wastes cycles on context switching, and disk I/O thrashes under concurrent thread contention.

#### Empirical Sizing Formula:

Pioneered by PostgreSQL and HikariCP benchmarks:

$$\text{Optimal Pool Size} = (\text{CPU Cores} \times 2) + \text{Effective Spindle Count}$$

Example: A database server with 8 CPU cores and an SSD array (Spindle Count = 1) achieves maximum query throughput with a connection pool size of 17 to 20 connections. Higher connection counts increase latency under load.

#### Query Anti-Patterns & Buffer Pool Thrashing:

##### 1. Non-Sargable Predicates (Search Argument Able):

Applying functions or transformations to an indexed column inside a WHERE clause prevents the query planner from using a B+ Tree index seek, forcing a full table scan.

```SQL
-- BAD (Non-Sargable): Function wraps indexed column 'created_at'
SELECT \* FROM orders WHERE YEAR(created_at) = 2026;

-- GOOD (Sargable): Column is isolated, enabling B+ Tree Range Seek
SELECT \* FROM orders WHERE created_at >= '2026-01-01' AND created_at < '2027-01-01';
```

##### 2. Implicit Type Conversions:

If phone_number is indexed as a VARCHAR, but queried as an integer:

```SQL
SELECT \* FROM users WHERE phone_number = 9876543210;
```

The database implicitly rewrites the statement to CAST(phone_number AS BIGINT) = 9876543210. Applying CAST() to every row invalidates the index seek and forces a full sequential scan.

#### Buffer Pool Contention:

A poorly indexed query that performs a sequential scan on a 50 GB table sweeps millions of unindexed disk pages into RAM. This flushes warm index pages out of the Buffer Pool, degrading performance across unrelated queries application-wide.
