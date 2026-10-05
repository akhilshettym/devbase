## 2. Transactions, Concurrency & Recovery:

- **ACID & Isolation Levels**: Understanding read anomalies (Dirty Reads, Non-Repeatable Reads, Phantom Reads) and how isolation levels mitigate them.

- **Concurrency Control**: How MVCC (Multi-Version Concurrency Control) works alongside shared/exclusive locks, and when to use Optimistic vs. Pessimistic Locking.

- **Crash Recovery**: How Write-Ahead Logging (WAL) guarantees durability by logging changes before committing them to main storage.

---

Concurrency control and recovery ensure that when hundreds of database transactions run simultaneously or when a power failure occurs mid-write, data remains correct, consistent, and durable.

### 1. <u>ACID Guarantees & Read/Write Anomalies</u>:

While developers know the ACID acronym, interviewers evaluate how you map these guarantees to real-world database mechanics:

- **Atomicity**: All operations in a transaction succeed or all fail. Implemented via the Write-Ahead Log (WAL) and Undo Logs, allowing the database to roll back half-finished writes during an abort or crash.

- **Consistency**: Domain invariants (e.g., foreign keys, unique constraints, check constraints) hold true. Consistency is a combined responsibility of transaction isolation and application design.

- **Isolation**: Concurrent transactions execute as if they were running sequentially. Achieved through Locking or MVCC.

- **Durability**: Once committed, changes survive system crashes. Achieved by ensuring log records are synchronously flushed to non-volatile disk before returning a COMMIT success to the client.

#### Concurrent Read & Write Anomalies:

When databases relax full isolation for performance, specific concurrency anomalies occur:

##### 1. Dirty Read:

Transaction A reads data modified by Transaction B that has not yet been committed. If Transaction B aborts, Transaction A has acted on uncommitted, nonexistent state.

- Tx 1: BEGIN; UPDATE accounts SET balance = balance - 100 WHERE id = 1; (Uncommitted)
- Tx 2: BEGIN; SELECT balance FROM accounts WHERE id = 1; <-- Reads dirty balance!
- Tx 1: ROLLBACK; <-- Tx 2 has invalid data

##### 2. Non-Repeatable Read (Fuzzy Read):

Transaction A reads a row value. Transaction B updates or deletes that row and commits. Transaction A re-reads the same row within the same transaction and sees different column values.

- Tx 1: BEGIN; SELECT balance FROM accounts WHERE id = 1; <-- Returns $500
- Tx 2: BEGIN; UPDATE accounts SET balance = 1000 WHERE id = 1; COMMIT;
- Tx 1: SELECT balance FROM accounts WHERE id = 1; <-- Returns $1000!

##### 3. Phantom Read:

Transaction A executes a range query (e.g., WHERE status = 'PENDING'). Transaction B inserts or deletes a row matching the filter criteria and commits. Transaction A re-executes the range query and sees a different set of matching rows (a "phantom" row appeared or vanished).

- Tx 1: BEGIN; SELECT COUNT(\*) FROM orders WHERE status = 'PENDING'; <-- Returns 5
- Tx 2: BEGIN; INSERT INTO orders (status) VALUES ('PENDING'); COMMIT;
- Tx 1: SELECT COUNT(\*) FROM orders WHERE status = 'PENDING'; <-- Returns 6!

##### 4. Write Skew (Serialization Anomaly):

Write Skew occurs under Snapshot Isolation. Two concurrent transactions read overlapping data sets, make independent decisions based on local invariants, and write to disjoint rows. Neither transaction sees the other's uncommitted write, violating global invariants.

**Classic Example**: A hospital rule requires at least one doctor on call. Doctors Alice and Bob are currently on call. Both try to take leave simultaneously:

- Tx 1 (Alice): SELECT COUNT(\*) WHERE on_call = true; (Returns 2, OK) -> UPDATE doctors SET on_call = false WHERE name = 'Alice';
- Tx 2 (Bob): SELECT COUNT(\*) WHERE on_call = true; (Returns 2, OK) -> UPDATE doctors SET on_call = false WHERE name = 'Bob';
- Both Tx 1 & Tx 2 COMMIT concurrently under Snapshot Isolation.
- Result: 0 doctors on call! (Violates domain invariant).

##### Isolation Levels & Anomaly Matrix:

| Isolation Level        | `Dirty Read` | `Non-Repeatable Read` | `Phantom Read`      | `Write Skew` | `Mitigation Strategy`                                                                        |
| ---------------------- | ------------ | --------------------- | ------------------- | ------------ | -------------------------------------------------------------------------------------------- |
| **Read Uncommitted**   | Allowed      | Allowed               | Allowed             | Allowed      | Dirty reads allowed; no read locks                                                           |
| **Read Committed**     | Prevented    | Allowed               | Allowed             | Allowed      | Reads latest committed snapshot                                                              |
| **Repeatable Read**    | Prevented    | Prevented             | Allowed/Prevented\* | Allowed      | Reads snapshot captured at transaction start.(\*Prevented in engines using MVCC range locks) |
| **Snapshot Isolation** | Prevented    | Prevented             | Prevented           | Allowed      | Version-based snapshot; fails on write-write conflict                                        |
| **Serializable**       | Prevented    | Prevented             | Prevented           | Prevented    | Strict 2PL or SSL (Serializable Snapshot Isolation)                                          |

---

### 2. <u>Concurrency Control: Locking vs. MVCC</u>:

Databases use two primary paradigms to safely execute concurrent transactions: Lock-Based Concurrency Control and Multi-Version Concurrency Control (MVCC).

##### **Lock-Based Concurrency Control (2PL)**:

Under Two-Phase Locking (2PL), transactions acquire locks on rows/pages before reading or modifying them.

##### Lock Modes:

- **Shared (S) Lock**: Acquired for SELECT. Multiple transactions can hold S locks on the same resource concurrently.
- **Exclusive (X) Lock**: Acquired for UPDATE, INSERT, DELETE, or SELECT FOR UPDATE. Only one transaction can hold an X lock; blocks all other S and X locks.
- **Intent Locks (IS / IX)**: Acquired at higher levels (table/page) before locking a specific row to prevent coarse table locks from interfering with fine-grained row locks.

##### The Two Phases:

- **Growing Phase**: Transaction acquires locks as needed; cannot release any locks.
- **Shrinking Phase**: Transaction releases locks; cannot acquire any new locks.
- **Strict 2PL (SS2PL)**: All Exclusive locks held by a transaction are retained until COMMIT or ABORTto avoid cascading rollbacks.

##### Deadlocks:

When Tx 1 holds Lock A and waits for Lock B, while Tx 2 holds Lock B and waits for Lock A.

- **Detection**: Background thread maintains a Wait-For Graph (directed graph of transactions and requested locks). If a cycle is detected, the engine aborts a "victim" transaction.
- **Prevention**: Timestamps determine precedence via rules like Wait-Die (older waits, younger dies) or Wound-Wait (older preempts younger, younger waits).

##### MVCC (Multi-Version Concurrency Control):

Modern high-performance engines default to MVCC because readers never block writers, and writers never block readers.

Instead of overwriting rows in place, an UPDATE or DELETE creates a new version of the row marked with transaction visibility metadata.

```
                          ROW TUPLE VERSION CHAIN
+-------------------------------------------------------------------------+
| Tuple v1 | Data: {id: 1, balance: 500} | xmin: 100 | xmax: 105 (Pointer) |
+-------------------------------------------------------------------------+
                                                     │
                                                     ▼
+-------------------------------------------------------------------------+
| Tuple v2 | Data: {id: 1, balance: 800} | xmin: 105 | xmax: 0 (Active)    |
+-------------------------------------------------------------------------+
```

##### Row Header Visibility Metadata:

Every tuple header stores versioning timestamps or transaction IDs (TxIDs):

- **xmin**: The TxID of the transaction that created this row version.
- **xmax**: The TxID of the transaction that deleted or superseded this row version (set to 0 if active).

##### Read Views / Snapshots:

When Tx 200 executes a query, the engine builds a Read View snapshot consisting of:

- **m_ids**: List of active, uncommitted transaction IDs at the moment the view was created.
- **min_txid**: Smallest TxID in m_ids (all TxIDs below this are committed and visible).
- **max_txid**: Next TxID to be assigned (all TxIDs $\ge$ this are future and invisible).

##### Visibility Rules for Tx 200:

- A row version is VISIBLE if xmin is committed AND xmin < max_txid AND xmin is NOT in m_ids.
- A row version is INVISIBLE if xmax is set and committed prior to Tx 200's Read View.

##### Difference between Read Committed and Repeatable Read:

- **Read Committed**: Re-evaluates and recreates a fresh Read View at the start of every SQL statement.
- **Repeatable Read**: Creates a single Read View at the start of the first query in the transaction and reuses it for every subsequent statement.

MVCC Garbage Collection (Bloat Management)
Because UPDATEs leave old row versions behind, dead tuples accumulate.

- **Vacuuming / Purging**: Background tasks sweep pages to remove dead row versions whose xmax is older than the oldest active transaction's Read View. If a long-running transaction remains open for hours, it holds back garbage collection, causing database table bloat.

#### Optimistic vs. Pessimistic Locking:

When writing application logic, choose concurrency strategies based on contention levels:

```
                           PESSIMISTIC LOCKING
  App                          Database                             Disk
   │  SELECT ... FOR UPDATE       │                                   │
   ├─────────────────────────────►│ Acquire Exclusive Lock (X)        │
   │                              │ Block concurrent readers/writers  │
   │  UPDATE ...                  │                                   │
   ├─────────────────────────────►│ Modify Row                        │
   │  COMMIT                      │                                   │
   ├─────────────────────────────►│ Release Lock                      │
   ▼                              ▼                                   ▼

                           OPTIMISTIC LOCKING
  App                          Database                             Disk
   │  SELECT id, val, version     │                                   │
   ├─────────────────────────────►│ Read without locks                │
   │  (App logic in memory)       │                                   │
   │  UPDATE ... WHERE version=1  │                                   │
   ├─────────────────────────────►│ Evaluate condition:               │
   │                              │  If version matches: Update & Inc │
   │                              │  Else: Return 0 rows updated      │
   │  (If 0 rows: retry/abort)    │                                   │
   ▼                              ▼                                   ▼
Pessimistic Locking (SELECT ... FOR UPDATE):
```

Assumes conflicts will happen. Immediately places an exclusive row lock on read.

- **Use Case**: High contention (e.g., flash sales, ticketing systems with limited inventory).
- **Drawback**: Holds database locks across application network hops; increases deadlock probability.

#### Optimistic Concurrency Control (OCC):

Assumes conflicts are rare. Reads data without locks alongside a version column. Writes execute via atomic check-and-set:

```SQL
UPDATE accounts
SET balance = 400, version = version + 1
WHERE id = 1 AND version = 1;
```

If another transaction updated the row first (version became 2), zero rows are updated. The application detects this and retries.

- **Use Case**: Low contention (e.g., user profile updates, collaborative document editing).

- **Drawback**: High retry overhead if collision rates spike.

---

### 3. <u>Crash Recovery & Durability Mechanics (WAL & ARIES)</u>:

How does a database guarantee durability without forcing slow, synchronous random disk writes for every committed transaction?

##### **Buffer Pool Policies**: Steal / No-Force:

Storage engines optimize memory and disk performance using two policy decisions:

- **Steal Policy (STEAL)**: The engine is allowed to flush uncommitted dirty pages to disk to free up RAM in the Buffer Pool. (Requires UNDO logging to revert uncommitted disk changes if the transaction aborts).

- **No-Force Policy (NO-FORCE)**: The engine is NOT required to flush dirty pages to disk at the exact moment a transaction commits. (Requires REDO logging to replay committed changes sitting in RAM if power cuts out).

Production databases use STEAL / NO-FORCE because it delivers maximum performance.

##### Write-Ahead Logging (WAL) Protocol:

- The WAL Protocol enforces one invariant:
- Log records describing an update MUST be flushed to non-volatile disk BEFORE the corresponding dirty data page in memory is allowed to be written to disk.

```
      TRANSACTION COMMIT & WAL FLUSH SEQUENCE

1. Modify Page in Buffer Pool (RAM)  ──► [ Page Marked Dirty ]
2. Append Log Record to WAL Buffer   ──► [ "Tx 100: Set Val=50" ]
                                                │
                                                ▼ (Synchronous Flush)
3. Flush Log Record to Disk          ──► [ WAL File on Disk ]
4. Return COMMIT Success to Client   ──► Client receives success
                                                │
                                                ▼ (Asynchronous Background)
5. Lazy Flush Dirty Data Page        ──► [ Data File on Disk ]
```

When a transaction issues COMMIT, the database only performs a fast sequential flush of the small WAL log buffer to disk. The actual modified data pages (which are 8KB/16KB and scattered randomly across disk) remain dirty in RAM and are written to disk lazily in the background.

#### The ARIES Recovery Algorithm:

If the server crashes, the database restarts and executes the ARIES (Algorithms for Recovery and Isolation Exploiting Semantics) algorithm in three phases:

```
                         ARIES RECOVERY PHASES
  Crash Point
      │
      ▼
[ 1. ANALYSIS PHASE ]  ──► Scan WAL forward from last Checkpoint.
                           Reconstruct Active Tx Table & Dirty Page Table.
      │
      ▼
[ 2. REDO PHASE ]      ──► Repeat History.
                           Scan WAL forward to reapply ALL changes (committed & uncommitted).
                           Restores RAM/Disk to exact crash state.
      │
      ▼
[ 3. UNDO PHASE ]      ──► Scan WAL backward.
                           Roll back changes of transactions active at crash time.
                           Write Compensation Log Records (CLRs) to prevent infinite loops.
```

#### Analysis Phase:

Reads the WAL forward starting from the last Checkpoint (a periodic record saving system state). Reconstructs:

- **Active Transaction Table (ATT)**: Transactions that were running when the crash occurred.
- **Dirty Page Table (DPT)**: Pages in RAM that had uncommitted writes.

#### Redo Phase (Repeating History):

Scans the log forward from the oldest un-flushed change. It reapplies all logged operations—both committed and uncommitted transactions—bringing the database to the exact state it was in right before the power cut.

#### Undo Phase (Rolling back active transactions):

Scans the log backward from the crash point. It rolls back every change made by "loser" transactions (transactions active at the time of the crash). For every undone operation, ARIES writes a Compensation Log Record (CLR) to disk so that if the server crashes again during recovery, it will not attempt to undo the same change twice.
