## Database Indexing

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a $1,000$-page medical textbook without a table of contents or index.

- **Full Table Scan ($O(N)$)**: To find every mention of the word "Mitochondria", you must read every sentence on all $1,000$ pages from start to finish. If the book grows to $100,000$ pages, the task becomes exponentially slower.

- **Database Index ($O(\log N)$)**: At the back of the book, an alphabetically sorted Index maps terms directly to exact page numbers (Mitochondria -> Pages 42, 108, 312). Instead of reading the entire book, you jump directly to the index, look up the term, and turn directly to those specific pages.

#### The Core Problem Solved:

- Storage media (HDDs/SSDs) read data in physical blocks ($4\text{ KB} - 16\text{ KB}$ pages). Without an index, finding a single row among $100\text{ million}$ records forces the database engine to load every single page from disk into RAM (a Full Table Scan), consuming massive disk I/O and CPU time.

- A Database Index is a redundant, highly structured auxiliary data structure (typically a B+Tree or Hash Table) that keeps a subset of table columns sorted alongside pointers to their physical row locations. It trades disk space and write speed for sub-millisecond read queries.

---

### 2. The Basics (Scratch Level):

#### Clustered vs. Non-Clustered Indexes:

```
CLUSTERED INDEX (The Table IS the Index) NON-CLUSTERED INDEX (Secondary Lookup)
┌───────────────────────┐ ┌───────────────────────┐
│ Root / Internal Nodes │ │ Root / Internal Nodes │
└───────────┬───────────┘ └───────────┬───────────┘
            ▼                         ▼
┌───────────────────────┐ ┌───────────────────────┐
│ Leaf Pages (Data)     │ │ Leaf Pages (Keys +    │
│ ┌───────────────────┐ │ │ Row Pointers/PKs)     │
│ │ID:101|Alice|93.184│ │ └───────────┬───────────┘
│ │ID:102| Bob |10.0.0│ │             │ (Double Lookup)
│ └───────────────────┘ │             ▼
└───────────────────────┘ [ Clustered Index Page ]
```

#### 1. Clustered Index:

- Determines the physical storage order of data rows on disk.
- A table can have only ONE clustered index (usually the Primary Key).
- The leaf pages of a clustered index are the actual data rows.

#### 2. Non-Clustered Index (Secondary Index):

- A separate data structure stored away from the main table data.
- Contains sorted key values and row locators (either physical Tuple IDs/RIDs or the Clustered Primary Key value).

A table can have hundreds of non-clustered indexes.

Core Index Types & Use Cases

| Index Type         | `Underlying Data Structure`               | `Supported Operations`                                            | `Best Use Cases`                                               | `Weaknesses`                                                      |
| ------------------ | ----------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------- | ----------------------------------------------------------------- |
| **B+Tree**         | Balanced Multi-way Search Tree            | Range (<, >, BETWEEN), Equality (=), Sorting (ORDER BY), Prefixes | Primary Keys, Timestamps, Numeric Ranges, General OLTP         | High write amplification under random inserts                     |
| **Hash Index**     | Dynamic Hash Table                        | Direct Equality (=, IN)                                           | In-memory key-value point lookups                              | No range queries (<, >), cannot help with ORDER BY                |
| **Bitmap Index**   | Bit Array per distinct key value          | Bitwise boolean ops (AND, OR, NOT)                                | Low-cardinality columns (e.g., gender, status) in OLAP systems | Terrible write concurrency (locks entire bitmap blocks on insert) |
| **GIN / Inverted** | Inverted Index (Map of tokens to row IDs) | Containment (@>), Full-Text Search, Array Matching.               | JSONB fields, Array columns, Unstructured text                 | Slow updates; heavy maintenance CPU overhead                      |

---

### 3. Deep Dive & Architecture (Mid Level):

#### B+Tree Internal Structure & Lookup Mechanics:

Why do databases use B+Trees instead of standard Binary Search Trees or B-Trees?

```
                               [ Root Page (Level 2) ]
                               [   20   |   50   ]
                                 /      |      \
                        ┌───────┘       │       └──────┐
                        ▼               ▼              ▼
                [ Node (Level 1) ] [ Node (Level 1) ] [ Node (Level 1) ]
                [   5  |  12   ]   [  30  |  42   ]   [  65  |  80   ]
                   /   |   \          /   |   \          /   |   \
                 ┌─┘   │    └─┐     ┌─┘   │    └─┐     ┌─┘   │    └─┐
                 ▼     ▼      ▼     ▼     ▼      ▼     ▼     ▼      ▼

[Leaf 0] ◄──► [ Data Pages (Level 0) ] ◄──────────────────────────────► [Leaf N]
[ 20 | 25 | 28 ] ──► Pointers to Data Rows
```

- **High Fan-Out (Wide Trees)**: A B+Tree page is sized to match disk page blocks ($16\text{ KB}$). A single node can hold hundreds or thousands of child pointers. A 3-level B+Tree with a fan-out of 100 can store $100^3 = 1,000,000$ leaf pointers with only 3 disk I/O operations.

- **Data Only at Leaves**: Internal nodes store only routing keys and child page pointers, maximizing the fan-out per page.

- **Horizontal Leaf Linking**: All leaf pages are linked in a doubly linked list. Range queries (WHERE age BETWEEN 20 AND 50) perform a single tree traversal to find the start key (20) and then scan sequentially horizontally across leaf pages without traversing back up the tree.

#### Composite Indexes & The Leftmost Prefix Rule:

- A Composite Index indexes multiple columns together: CREATE INDEX idx_user_loc ON users(country, state, city);
- The database sorts data primary by country, then by state, then by city.

Index Tuple Order:

```
('CA', 'ON', 'Toronto')
('US', 'CA', 'Los Angeles')
('US', 'CA', 'San Francisco')
('US', 'NY', 'New York')
```

**Leftmost Prefix Rule**: Queries can utilize the index only if filtering left-to-right without skipping leading columns:

```
WHERE country = 'US' $\rightarrow$ INDEX SCAN (Uses 1st column)

WHERE country = 'US' AND state = 'CA' $\rightarrow$ INDEX SCAN (Uses 1st & 2nd columns)

WHERE state = 'CA' AND city = 'Los Angeles' $\rightarrow$ FULL TABLE SCAN (Skips leading country column)
```

#### Covering Indexes & Index-Only Scans:

When a secondary index contains all the columns requested by a query, the database engine executes an Index-Only Scan.

```
QUERY: SELECT email FROM users WHERE status = 'ACTIVE';

INDEX: CREATE INDEX idx_status_email ON users(status, email);
```

- **Standard Secondary Scan**: Lookup status in Secondary Index $\rightarrow$ Retrieve Primary Key $\rightarrow$ Perform Bookmark Lookup in Clustered Index to fetch email column $\rightarrow$ Return row.

- **Covering Index Scan**: Lookup status in Secondary Index $\rightarrow$ Read email directly out of the Secondary Index leaf node $\rightarrow$ Return row. (Zero Clustered Index / Heap page access required!)

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

The Write Amplification Penalty ("Index Tax")

- Every index added to a table is a direct trade-off between read acceleration and write latency:

$$\text{Write Overhead} \propto \text{Number of Active Indexes}$$

When executing an INSERT, UPDATE, or DELETE:

- The row is modified in the Clustered Index / Heap table.
- EVERY non-clustered index referencing affected columns must be updated synchronously in memory/disk.
- Inserting 1 record into a table with 8 secondary indexes requires updating 9 separate B+Trees across different physical disk locations.

#### Index Fragmentation & Page Splits:

When inserting data into a B+Tree, keys must be stored in strict sorted order inside a page.

```
1. FULL PAGE (Capacity 100%)
   [ Page 10 ]: [ Key 10 | Key 20 | Key 30 | Key 40 ]

2. INSERT Key 25 (Page is full!) -> TRIGGER PAGE SPLIT
   [ Page 10 ]: [ Key 10 | Key 20 ] ───────► Allocates [ Page 11 ]: [ Key 25 | Key 30 | Key 40 ]
```

- **Random UUID v4 Primary Keys (The Anti-Pattern)**: Inserting non-sequential, randomly generated $128$-bit UUIDs forces random writes across arbitrary B+Tree leaf pages. This triggers continuous Page Splits, causing disk space bloat (50% page fill ratios), shattered CPU cache lines, and high write latency.

- **Monotonic Sequential Keys (The Solution)**: Auto-incrementing integers or UUID v7 (time-ordered UUIDs) always append to the rightmost leaf page of the B+Tree, achieving 90-99% page density and eliminating internal page splits.

#### Partial & Expression/Functional Indexes:

To minimize storage overhead and index size, modern databases support targeted indexing:

Partial Indexes (Filtered Indexes)

- Indexes only a subset of rows matching a constant predicate:

```SQL
-- Indexes ONLY unpaid orders (e.g., 1% of total table data)
CREATE INDEX idx_unpaid_orders ON orders(user_id)
WHERE status = 'UNPAID'; 2. Expression / Functional Indexes
```

- Indexes the output of a deterministic function applied to a column:

```SQL
-- Enables index usage for case-insensitive queries like WHERE LOWER(email) = 'user@test.com'
CREATE INDEX idx_lower_email ON users(LOWER(email));
```

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
         LOOKUP TRAVERSAL: SECONDARY INDEX TO CLUSTERED INDEX
================================================================================

Query: SELECT name, balance FROM accounts WHERE email = 'alice@example.com';

1. SECONDARY NON-CLUSTERED INDEX (idx_email)
--------------------------------------------------------------------------------
                        [ Root Page: email ]
                                 │
                                 ▼
                       [ Internal Node Page ]
                                 │
                                 ▼
[ Leaf Page ]: Key: 'alice@example.com'  | Pointer: Primary Key ID = 88412
                                                       │
                                                       │ (Bookmark Lookup)
                                                       ▼
2. CLUSTERED PRIMARY KEY INDEX (Accounts Table Heap)
--------------------------------------------------------------------------------
                        [ Root Page: ID ]
                                 │
                                 ▼
                       [ Internal Node Page ]
                                 │
                                 ▼
[ Leaf Page ]: ID: 88412  |  Name: "Alice"  |  Balance: $12,450.00  |  Created: ...
================================================================================
```

---

### 6. Interview Checklist:

- **Differentiate Clustered vs. Non-Clustered**: State clearly that a Clustered index is the data physically sorted on disk (1 per table), while a Non-Clustered index stores secondary keys pointing back to primary key values or physical row IDs.

- **Explain B+Tree Advantages Over Standard B-Trees**: Highlight two key points: high fan-out (wide trees reduce disk I/O depth) and doubly linked leaf nodes that enable $O(1)$ horizontal range scanning without re-traversing internal parent nodes.

- **Explain the Leftmost Prefix Rule**: Walk through composite index behavior (A, B, C), demonstrating why queries filtering on B and C alone fail to trigger an index range scan.

- **Explain Primary Key Choice Consequence (UUID v4 vs UUID v7)**: Show systems design experience by explaining how random UUID v4 values trigger non-sequential page splits, severe disk fragmentation, and high I/O overhead compared to time-sorted monotonically increasing keys (Auto-increment INT or UUID v7).

- **Mention Covering Indexes as an Optimization**: Pitch using covering indexes (INCLUDE clauses) to convert standard secondary lookups into Index-Only Scans, bypassing secondary-to-primary key bookmark lookups entirely.
