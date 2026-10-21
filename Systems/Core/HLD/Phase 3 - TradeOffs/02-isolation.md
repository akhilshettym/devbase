## Isolation & its levels

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a joint checking account shared between two spouses:

- **No Isolation (Chaos at the ATM)**: Spouse A checks the balance at an ATM and sees $\$100$. At the exact same second, Spouse B swipes a debit card at a grocery store for $\$100$. While Spouse B's transaction is mid-flight, Spouse A decides to withdraw $\$100$. Both transactions process simultaneously because neither knew the other was happening, causing the account balance to drop to $-\$100$(overdraft).

- **Perfect Isolation (Airtight Bank Teller)**: While Spouse B is swiping their card, the bank places an invisible, momentary lock on the account. Spouse A's ATM screen pauses for a fraction of a second until Spouse B's purchase finishes, showing Spouse A an accurate remaining balance of $\$0$.

#### The Core Problem Solved:

- In high-throughput databases, thousands of client transactions execute concurrently across shared CPU cores and memory. If transactions read and write shared rows without isolation constraints, they experience race conditions, data corruption, and read/write anomalies (e.g., lost updates, dirty reads, and phantom data).

- Transaction Isolation (the "I" in ACID) defines the degree to which concurrently executing transactions are hidden from one another. It ensures that even when thousands of operations run simultaneously, the final state of the database is identical to a state reached if those transactions had executed sequentially one after another.

---

### 2. The Basics (Scratch Level):

#### The Read/Write Anomalies (Data Corruptions):

- Isolation levels are defined by the specific concurrency anomalies they permit or prevent:

- **Dirty Read**: Transaction A modifies a row but hasn't committed yet. Transaction B reads that uncommitted modified row. Transaction A then rolls back. Transaction B has acted on "dirty" data that legally never existed.

- **Non-Repeatable Read (Fuzzy Read)**: Transaction A reads a row value (e.g., balance = $100). Transaction B updates that same row (balance = $50) and commits. Transaction A reads the exact same row again within its transaction and sees a different value ($50).

- **Phantom Read**: Transaction A executes a range query (e.g., SELECT COUNT(\*) WHERE age > 30$\rightarrow$ returns 10). Transaction B inserts a new row matching the condition (age = 35) and commits. Transaction A re-runs the range query and gets 11 rows (the "phantom" row appeared).

- **Write Skew**: Two concurrent transactions read overlapping data sets, make disjoint writes based on those reads, and violate a global business invariant.

- **Example**: A hospital requires at least 1 doctor on call. Doctors A and B are both on call. Doctor A checks: "Are doctors on call $> 1$?" (Yes, 2). Doctor B checks the exact same condition concurrently (Yes, 2). Both submit requests to take time off. Both commit. Now 0 doctors are on call.

#### The ANSI SQL Isolation Levels Matrix:

| Isolation Level      | `Dirty Read` | `Non-Repeatable Read` | `Phantom Read`                                     | `Write Skew` | `Primary Engine Mechanism`                                         |
| -------------------- | ------------ | --------------------- | -------------------------------------------------- | ------------ | ------------------------------------------------------------------ |
| **Read Uncommitted** | Allowed      | Allowed               | Allowed                                            | Allowed      | No locks for reads; dirty writes prevented via write locks.        |
| **Read Committed**   | Prevented    | Allowed               | Allowed                                            | Allowed      | MVCC statement-level snapshots OR short-lived read locks.          |
| **Repeatable Read**  | Prevented    | Prevented             | Allowed (SQL standard) / Prevented (Postgres MVCC) | Allowed      | MVCC transaction-level snapshots OR shared read locks held to end. |
| **Serializable**     | Prevented    | Prevented             | Prevented                                          | Prevented    | Two-Phase Locking (2PL) OR Serializable Snapshot Isolation (SSI).  |

---

### 3. Deep Dive & Architecture (Mid Level):

#### How Isolation Works Under the Hood:

Modern database engines enforce isolation using two primary architectural paradigms: Pessimistic Locking (2PL) or Optimistic Multi-Version Concurrency Control (MVCC).

1. TWO-PHASE LOCKING (Pessimistic 2PL)
2. MULTI-VERSION CONCURRENCY CONTROL (MVCC)

```
   [ Transaction A ]                                [ Transaction A (Start LSN: 100) ]
            │                                                           │
   (Acquires Shared/Exclusive Locks)                    (Reads Snapshot @ LSN 100)
            │                                                       │
   [ Holds Locks / Blocks Tx B ]                                     ▼
   │                                            ┌──────────────────────────────┐
   (Releases Locks at Commit) │ Row V1 (xmin: 90, xmax: 105) │
   │                                             │ Row V2 (xmin: 105, xmax: inf) │
   ▼                                                └──────────────────────────────┘
   [ Transaction B Resumes ]                     Readers NEVER block Writers!
                                                    Writers NEVER block Readers!
```

#### 1. Multi-Version Concurrency Control (MVCC - Used by PostgreSQL, MySQL InnoDB, Oracle)

Instead of locking rows during reads, the database maintains multiple historical physical versions of each row.

- Every row header contains hidden system metadata fields:
- **xmin / created_by**: The Transaction ID (LSN) that inserted this row version.
- **xmax / deleted_by**: The Transaction ID that deleted or updated this row version.
- **Snapshot Creation**: When a transaction starts, the engine assigns it a Read Snapshot containing active transaction IDs.
- **Read Committed**: Generates a new Read Snapshot at the start of every SQL statement.
- **Repeatable Read**: Generates a single Read Snapshot at the start of the entire transaction and reuses it for all queries.

#### 2. Two-Phase Locking (2PL - Pessimistic Locking):

- Used when strict serializability is required without optimistic validation:

- **Phase 1 (Growing Phase)**: Transactions acquire locks as needed (Shared S locks for reads, Exclusive Xlocks for writes, Predicate Locks for ranges). No locks can be released until all locks are acquired.
- **Phase 2 (Shrinking Phase)**: Locks are released gradually or all at once upon COMMIT/ROLLBACK(Strict 2PL).

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Serializable Snapshot Isolation (SSI):

**Traditional 2PL serializability** destroys throughput because readers block writers and writers block readers. Modern engines (PostgreSQL 9.1+, CockroachDB) use Serializable Snapshot Isolation (SSI) to achieve full serializability with non-blocking MVCC reads.

```
SSI CONCURRENCY CONTROL ENGINE
1. Runs transactions optimistically on MVCC snapshots (Non-blocking reads).
2. Maintains an in-memory Dependency Graph of read-write anti-dependencies (siREAD locks).
3. Detects dependency cycles (e.g., Tx1 -> rw -> Tx2 -> rw -> Tx1) before commit.
4. Aborts one of the conflicting transactions ("First Committer Wins") to break the cycle.
```

#### Performance & Engine Footprint Trade-offs:

```
   Throughput (TPS)
   │ / Read Committed (Max Throughput)
   │ /
   │ / Repeatable Read / Snapshot Isolation
   │ /
   │ ──────────────────────────────/─── Serializable (High Lock Contention / Aborts)
   │ /
   │/
   └───────────────────────────────────────────────── Concurrency Contention
```

#### Undo Log / Space Bloat (Long-Running Transactions):

In **MVCC** engines (MySQL/Postgres), long-running transactions hold open old snapshots. This prevents background garbage collection routines (Vacuum in Postgres, Purge Threads in InnoDB) from reclaiming deleted row versions, causing severe table bloat and disk I/O degradation.

#### Explicit Locking Escape Hatches:

When running under lower isolation levels (e.g., Read Committed) but requiring Write Skew protection for specific queries, application developers use explicit row-level pessimistic locks:

```SQL
-- Locks matched rows with an Exclusive (X) lock, forcing concurrent transactions to block
SELECT \* FROM doctors WHERE on_call = true FOR UPDATE;
```

---

### 5. # Text-Based Architecture Diagram:

```
                       MVCC SNAPSHOT ISOLATION READ VISIBILITY
================================================================================

Target Row Physical Versions on Disk:
┌──────────────────────────────────────────────────────────────────────────────┐
│ Version 1: Value = "Alice" | xmin: 100 | xmax: 105 │
├──────────────────────────────────────────────────────────────────────────────┤
│ Version 2: Value = "Bob" | xmin: 105 | xmax: inf │
└──────────────────────────────────────────────────────────────────────────────┘

## SCENARIO A: Transaction 102 (Started at LSN 102 - Snapshot sees LSN <= 102)
----
1. Reads Row.
2. Checks V1: xmin (100) <= 102? YES. xmax (105) > 102? YES.
3. Result Returned: "Alice" (Ignores Version 2 because Tx 105 hasn't happened yet!)

## SCENARIO B: Transaction 108 (Started at LSN 108 - Snapshot sees LSN <= 108)
----
1. Reads Row.
2. Checks V1: xmin (100) <= 108? YES. xmax (105) <= 108? YES (Version 1 is dead!).
3. Checks V2: xmin (105) <= 108? YES. xmax (inf) > 108? YES.
4. # Result Returned: "Bob"
================================================================================
```

---

### 6. Interview Checklist:

**Differentiate Isolation vs. Consistency**: Clarify early that Isolation prevents concurrent execution anomalies, while Consistency guarantees that database invariants/schema constraints remain valid.

**Explain the MVCC Snapshot Mechanics**: Demonstrate deep engine understanding by contrasting Read Committed (new MVCC snapshot per SQL statement) with Repeatable Read (single MVCC snapshot per transaction).

**Explain Write Skew and How to Prevent It**: Identify Write Skew as the primary anomaly permitted under Repeatable Read/Snapshot Isolation, and explain how to mitigate it using Serializable isolation or explicit SELECT ... FOR UPDATE locks.

#### Match Production Engine Defaults:

**PostgreSQL / Oracle / SQL Server**: Default to Read Committed for optimal balance of throughput and safety.

**MySQL InnoDB**: Defaults to Repeatable Read (uses gap locks to prevent phantom reads).
