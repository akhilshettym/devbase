## Search Engines (Elasticsearch, Solr)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine walking into a massive public library with millions of books to find every book that mentions the word "quantum".

- A Traditional Database (SQL) is like reading every book from page 1 to the end, scanning for the word "quantum" line by line (a slow, sequential table scan).

- A Search Engine (Elasticsearch/Solr) is like skipping the books entirely and going straight to the Back-of-the-Book Index. There, you find an alphabetical list of every unique word across all books, followed by a list of exact page numbers where each word appears. Instead of scanning millions of pages, you flip directly to the letter Q, find "quantum", and immediately get the exact list of books and pages in milliseconds.

#### The Problem It Solves:

- Traditional relational databases (PostgreSQL, MySQL) excel at ACID transactions, exact-match lookups (WHERE user_id = 42), and relational joins. However, they struggle with text processing:

- **Full-Text Search at Scale**: SQL LIKE '%quantum%' queries cannot efficiently leverage standard B-Tree indices, leading to full table scans across millions of rows.

- **Relevance Scoring & Fuzzy Matching**: Relational DBs return strict binary results (True or False). They cannot naturally rank results by "how relevant" a document is, handle typos, support synonyms, or execute stem-matching (e.g., matching "running" with "run").

- Distributed Search Engines (Elasticsearch, Apache Solr)—both built on top of the low-level Apache Lucene search library—solve this by transforming unstructured/semi-structured data into Inverted Indices, enabling sub-second full-text queries, relevance ranking, and multidimensional analytical aggregations over billions of documents.

---

### 2. The Basics (Scratch Level):

#### Core Terminology Comparison (SQL vs. Search Engine):

To model data in search engines, developers map traditional relational DB concepts to document search primitives:

| Relational DB (SQL)   | `Search Engine (Elasticsearch / Solr)` | `Description`                                                                 |
| --------------------- | -------------------------------------- | ----------------------------------------------------------------------------- |
| **Database Instance** | Cluster                                | A collection of one or more connected physical or virtual nodes.              |
| **Table**             | Index / Collection                     | A logical partition or container holding related documents.                   |
| **Row**               | Document                               | A single JSON object containing typed key-value fields.                       |
| **Column**            | Field                                  | A specific property within a document (e.g., title, price, tags).             |
| **Index (B-Tree)**    | Inverted Index                         | The underlying data structure mapping terms to document IDs.                  |
| **Schema**            | Mapping / Schema.xml                   | Defines field types (Text, Keyword, Date, Geo-point) and text analysis rules. |

#### The Core Primitive: The Inverted Index:

A forward index maps a Document to the tokens it contains. An Inverted Index flips this relationship, mapping every unique Term across the entire corpus to a postings list of Document IDs containing that term:

```
FORWARD INDEX                           INVERTED INDEX
Doc 1: "Fast search engine"             "fast"   ──► [ Doc 1 ]
Doc 2: "Distributed search DB"          "search" ──► [ Doc 1, Doc 2 ]
                                       "engine" ──► [ Doc 1 ]
                                       "distr"  ──► [ Doc 2 ]
Text Analysis Pipeline
Before text is written to an inverted index, it passes through an Analyzer Pipeline:

[ Raw Text: "The 2 QUICK Foxes!" ]
             │
             ▼
   [ Character Filter ]  ──► Strip HTML tags (<p>)
             │
             ▼
      [ Tokenizer ]      ──► Split on whitespace/punctuation -> ["The", "2", "QUICK", "Foxes"]
             │
             ▼
   [ Token Filters ]     ──► Lowercase -> ["the", "2", "quick", "foxes"]
                         ──► Stopwords (remove "the") -> ["2", "quick", "foxes"]
                         ──► Stemming (Snowball) -> ["2", "quick", "fox"]
```

#### Field Types: text vs. keyword:

- **text (Analyzed)**: Passed through the analyzer pipeline (tokenized, lowercased, stemmed). Used for full-text search (e.g., article content, product descriptions).

- **keyword (Not Analyzed / Exact Match)**: Indexed as a raw string. Used for exact filtering, sorting, and aggregations (e.g., status: "PUBLISHED", user_id: "usr_99").

---

### 3. Deep Dive & Architecture (Mid Level):

#### Lucene Segment Architecture & Immutability:

Under the hood, an Elasticsearch or Solr Index is partitioned into Shards. A single Shard is an active Apache Lucene Instance, which itself is composed of multiple smaller, immutable Segments.

```
ELASTICSEARCH INDEX
└── SHARD 0 (Lucene Index Instance)
   ├── Memory Buffer (Active Ingestion)
   ├── Translog / WAL (Write-Ahead Log)
   └── Disk Segments (Immutable)
       ├── Segment 1 (Inverted Index + Doc Values)
       ├── Segment 2 (Inverted Index + Doc Values)
       └── Segment 3 (Inverted Index + Doc Values)
```

- **In-Memory Indexing Buffer**: Incoming document writes enter an in-memory buffer and are simultaneously appended to a sequential disk Translog / WAL for crash recovery.
- **Refresh (In-Memory Flushes)**: Every second (configurable refresh_interval), the buffer flushes its contents into a new immutable Lucene Segment in memory. The data is now searchable before being committed to disk!
- **Flush & Commit**: Periodically (e.g., every 30 minutes or when Translog fills up), memory segments are committed to permanent disk storage, and the Translog is truncated.

`Segment Merging`: Because segments are immutable, updates and deletes do not overwrite data in place:

- **Deletes**: Mark the document ID as deleted in a .del bitset map. The document is still queried but filtered out of final search results.
- **Updates**: Mark the old document as deleted and append the updated document to a brand-new segment.
- **Background Merging**: A background Lucene process merges smaller segments into larger segments, permanently purging soft-deleted documents to reclaim disk space.

#### Relevance Scoring Engine: BM25 Algorithm:

Modern search engines rank matching documents using BM25 (Best Matching 25), a variant of TF-IDF (Term Frequency-Inverse Document Frequency):

$$\text{Score}(D, Q) = \sum_{i=1}^{n} \text{IDF}(q_i) \cdot \frac{f(q_i, D) \cdot (k_1 + 1)}{f(q_i, D) + k_1 \cdot \left(1 - b + b \cdot \frac{\vert{}D\vert{}}{\text{avgdl}}\right)}$$

- `Term Frequency ($f(q_i, D)$)`: How often does the search term appear in this document? (More occurrences = higher score).

- `Inverse Document Frequency ($\text{IDF}$)`: How rare is the search term across all documents in the index? Rare words (e.g., "Kafka") yield higher scores than common words (e.g., "system").

- `Field-Length Normalization ($\vert{}D\vert{}/\text{avgdl}$)`: Shorter fields (e.g., title matches) score higher than the same match inside a 50-page document.

- `Term Frequency Saturation ($k_1$)`: Prevents a document containing the term 100 times from completely overwhelming a document containing it 3 times.

#### Analytical Aggregations & doc_values:

Inverted indices excel at looking up Terms $\to$ Documents. However, calculating Aggregations / Facets(e.g., GROUP BY category, AVG(price)) requires looking up Documents $\to$ Term Values.

- Doing Document-to-Term lookups by traversing an inverted index requires uncompressing the entire index into JVM Heap memory (FieldData), causing severe out-of-memory crashes.
- **Doc Values (Columnar Storage)**: Search engines build an on-disk, column-oriented structure alongside the inverted index during document write time. When executing aggregations, sorting, or scripts, Lucene reads directly from doc_values via OS page cache memory maps (mmap), bypassing JVM heap limits entirely.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Query Execution Architecture: Scatter-Gather Pattern:

When a client executes a search query against a multi-shard distributed cluster, the node receiving the request acts as the Coordinator Node:

```
[ Client Request: GET /products/_search?q=laptop ]
                       │
                       v
       +───────────────────────────────+
       | COORDINATOR NODE              |
       +───────────────────────┬───────+
                               │
         ┌─────────────────────┼─────────────────────┐
         │ Scatter Query       │ Scatter Query       │ Scatter Query
         v                     v                     v
+───────────────────+ +───────────────────+ +───────────────────+
| SHARD 0 (Node A)  | | SHARD 1 (Node B)  | | SHARD 2 (Node C)  |
| - Matches Query   | | - Matches Query   | | - Matches Query   |
| - Computes Top 10 | | - Computes Top 10 | | - Computes Top 10 |
|   Local Results   | |   Local Results   | |   Local Results   |
+─────────┬─────────+ +─────────┬─────────+ +─────────┬─────────+
          │                     │                     │
          └─────────────────────┼─────────────────────┘
                                │ Return Local Document IDs + BM25 Scores
                                v
       +───────────────────────────────+
       | COORDINATOR NODE              |
       | - Priority Queue Sorts Scores |
       | - Identifies Global Top 10    |
       | - Fetches Full Docs (Phase 2) |
       +───────────────────────┬───────+
                               │
                               v
               [ Final JSON Response to Client ]
```

#### Phase 1: Query Phase (Scatter-Gather)

- Coordinator routes the query across all active shards (or a representative set of primary/replica shards).
- Each shard executes the search locally, builds a priority queue of matching Document IDs and their calculated BM25 scores (e.g., top 10 local matches), and returns only the IDs and scores back to the coordinator.
- Coordinator merges all local priority queues and sorts them to isolate the global top 10 matches.

#### Phase 2: Fetch Phase

- Coordinator sends targeted GET requests strictly to the specific shards holding the global top 10 Document IDs to retrieve full JSON document payloads.
- Coordinator compiles the final search response and returns it to the client.

- **Pro Latency Warning (Deep Pagination / High from + size)**: Requesting page 1,000 (from: 10000, size: 10) forces every single shard to compute and sort its top 10,010 local results and ship them to the coordinator node. The coordinator must then merge $N \times 10,010$ results in memory!
- **Mitigation**: Block deep pagination using index.max_result_window. Require stateless point-in-time cursors using search_after or the Scroll API.

#### Shard Sizing Strategy & The Primary Shard Anti-Pattern:

Primary shard counts in Elasticsearch cannot be changed after index creation without completely re-indexing the dataset into a new index via the \_reindex API.

- **Under-Sharding Risk**: A single primary shard exceeding 50GB degrades Lucene segment merge operations, slows recovery times during node crashes, and limits write parallelization.
- **Over-Sharding Risk**: Creating thousands of tiny shards (e.g., 500MB shards) causes massive JVM memory bloat. Every shard requires memory allocation for index metadata, segment headers, and file handles.

#### Rule of Thumb:

- Target optimal shard sizes between 10GB and 50GB per shard.
- Keep total shard count per node under 20 shards per GB of JVM heap.

#### Cluster Topology & Split-Brain Prevention:

In large enterprise topologies, separate node responsibilities to insulate cluster state management from query spikes:

```
                 [ Ingress Traffic / Load Balancer ]
                                  │
      ┌───────────────────────────┼───────────────────────────┐
      │ Routing                   │ Heavy Queries             │ Ingestion
      v                           v                           v
+──────────────+            +──────────────+            +──────────────+
| DEDICATED    |            | DEDICATED    |            | DEDICATED    |
| COORDINATOR  |            | DATA NODES   |            | INGEST NODES |
| NODES        |            | - Local SSD  |            | - Pre-processes|
| (Stateless)  |            | - Holds      |            |   Pipeline   |
+──────────────+            |   Shards     |            |   Pipeline   |
                           +──────────────+            +──────────────+
                                  ▲
                                  │ State Updates
                           +──────────────+
                           | DEDICATED    |
                           | MASTER NODES |
                           | (3 Nodes -   |
                           | Quorum Vote) |
                           +──────────────+
```

- **Dedicated Master Nodes (3 Nodes, Quorum Rules)**: Do not handle queries or store document shards.Their sole job is managing cluster state, shard routing tables, and node membership. Set discovery.zen.minimum_master_nodes = (master_eligible_nodes / 2) + 1 (handled natively in modern versions via Raft-based consensus) to eliminate split-brain cluster partitions.
- **Dedicated Data Nodes**: Store shards on high-speed NVMe SSDs and execute CPU-heavy search and aggregation operations.
- **Dedicated Ingest Nodes**: Execute preprocessing pipelines (Grok parsing, geo-ip enrichment) before document indexing, shielding data nodes from CPU spikes.

#### Architectural Comparison: Elasticsearch vs. Apache Solr:

| Architectural Dimension                                                                        | `Elasticsearch`                                                                                               | `Apache Solr`                                                                                                    |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Cluster Coordination**                                                                       | Built-in native consensus mechanism (historically Zen Discovery, modern Raft-based cluster state management). | Relies on external Apache ZooKeeperfor cluster state management, shard leader election, and config distribution. |
| **Primary Use Cases**                                                                          | Dominates real-time log analytics, APM monitoring (ELK Stack), and dynamic cloud microservice search.         | Deeply embedded in complex enterprise search, deep text retrieval, CMS platforms, and heavy static faceting.     |
| **API & Configuration**                                                                        | RESTful JSON-first native API; dynamic mapping capabilities.                                                  |
| Historical XML/HTTP API focus (modernized to JSON); strict schema.xmlconfiguration preference. |
| **Ecosystem**                                                                                  | Integrated natively into the Elastic Stack(Kibana, Logstash, Beats, Agent).                                   | Managed under the Apache Software Foundation ecosystem.                                                          |

---

### 5. Text-Based Architecture Diagram:

**Full Distributed Search Pipeline (Indexing & Query Paths)**

```
===================================================================================================
1. ASYNCHRONOUS DOCUMENT INGESTION PIPELINE (Write Path)
===================================================================================================

[ App / Log Agent ] ──► POST /orders/_doc/1001  (JSON Body)
                             │
                             v
                  +──────────────────────+
                  | COORDINATOR NODE     |
                  | - Hash Doc ID        |
                  | - Identifies Shard 0 |
                  +──────────┬───────────+
                             │
                             │ Forward Write Request
                             v
                  +─────────────────────────────────────────+
                  | PRIMARY SHARD 0 (Data Node 1)           |
                  |                                         |
                  | 1. Appends to Translog / WAL (Disk)     |
                  | 2. Appends to In-Memory Index Buffer    |
                  | 3. Refresh Interval (1s) -> Flushes to  |
                  |    new Immutable Lucene Segment         |
                  +──────────┬──────────────────────────────+
                             │
                             │ Asynchronous Parallel Replication
                             v
                  +─────────────────────────────────────────+
                  | REPLICA SHARD 0 (Data Node 2)           |
                  | - Appends to local Translog & Segment   |
                  +─────────────────────────────────────────+

===================================================================================================
2. SCATTER-GATHER FULL-TEXT SEARCH PIPELINE (Read Path)
===================================================================================================

[ Search Client ] ──► GET /orders/_search?q=description:laptop&size=10
                             │
                             v
                  +──────────────────────+
                  | COORDINATOR NODE     |
                  +──────────┬───────────+
                             │
      ┌──────────────────────┼──────────────────────┐
      │ Scatter Query        │ Scatter Query        │ Scatter Query
      v                      v                      v
+──────────────+       +──────────────+       +──────────────+
| PRIMARY      |       | REPLICA      |       | PRIMARY      |
| SHARD 0      |       | SHARD 1      |       | SHARD 2      |
| (Node 1)     |       | (Node 2)     |       | (Node 3)     |
|              |       |              |       |              |
| - Term Lookup|       | - Term Lookup|       | - Term Lookup|
| - BM25 Score |       | - BM25 Score |       | - BM25 Score |
| - Top 10 IDs |       | - Top 10 IDs |       | - Top 10 IDs |
+──────┬───────+       +──────┬───────+       +──────┬───────+
       │                      │                      │
       └──────────────────────┼──────────────────────┘
                              │ Gather Step 1: Return Top 10 IDs + BM25 Scores
                              v
                  +──────────────────────+
                  | COORDINATOR NODE     |
                  | - Merges Priority    |
                  |   Queues             |
                  | - Isolates Global    |
                  |   Top 10 Matches     |
                  +──────────┬───────────+
                             │
                             │ Gather Step 2: GET Document Payloads for Global Top 10
                             v
                  +──────────────────────+
                  | TARGET SHARD NODES   | ──► Fetch JSON Docs from `_source`
                  +──────────┬───────────+
                             │
                             v
[ Final Search Response Returned to Client ]
```

---

### 6. Interview Checklist:

When pitching search engines (Elasticsearch, Solr) in a high-level system design interview:

- **Justify Search Engine Choice**: Explain that search engines supplement relational DBs by providing Inverted Indices for fast full-text matching, BM25 relevance scoring, and fuzzy/synonym processing.

- **Explain Inverted Index & Lucene Immutability**: Detail how raw text passes through an Analyzer Pipeline (Tokenizer, Filters) to populate an inverted index. Mention that segments are immutable, which simplifies concurrency and caching but requires background merges for deletes/updates.

- **Detail Scatter-Gather Execution**: Demonstrate deep distributed knowledge by walking through the Scatter-Gather Query/Fetch phases. Proactively warn against Deep Pagination (from + size) performance bottlenecks.

- **Highlight Storage Optimization (doc_values)**: Differentiate between inverted indices (Terms $\to$ Docs for text search) and doc_values (Docs $\to$ Terms columnar disk format for fast aggregations and sortingwithout JVM heap OOMs).

- **Define Cluster Topology & Shard Guardrails**: Propose Dedicated Master Nodes (to prevent split-brain) alongside Dedicated Data and Ingest Nodes. Mention targeting 10GB–50GB shard sizes to prevent over/under-sharding.
