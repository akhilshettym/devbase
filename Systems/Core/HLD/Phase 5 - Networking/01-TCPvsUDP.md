## TCP vs UDP

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

At Layer 4 (Transport Layer) of the OSI model, IP (Internet Protocol) handles routing packets from host to host on a "best-effort" basis. IP makes no guarantees that packets will arrive, arrive in order, or remain uncorrupted.TCP and UDP are the two primary protocols built on top of IP to deliver data to specific application processes using port numbers.

```
+-------------------------------------------------------------------+
| Real-World Analogy: Mail Delivery                                 |
+-------------------------------------------------------------------+
| TCP: Certified Registered Mail with Return Receipts               |
| - Every page is numbered (Sequencing).                            |
| - Recipient signs for every batch received (ACK).                 |
| - Missing pages are re-sent before binder is handed over.         |
|                                                                   |
| UDP: Standard Postcard / Megaphone Broadcast                      |
| - Quick, zero setup, single-message broadcast.                    |
| - No signature, no tracking, no confirmation.                     |
| - If lost in transit, sender never knows.                         |
+-------------------------------------------------------------------+
```

- **TCP (Transmission Control Protocol)**: Solves the problem of network unreliability. It turns a lossy,unordered packet network into a reliable, in-order byte stream. Use TCP when data integrity and exact ordering are non-negotiable (e.g., financial transactions, database queries, file transfers, REST/GraphQL APIs).

- **UDP (User Datagram Protocol)**: Solves the problem of transport overhead and latency constraints. It provides a lightweight message wrapper around IP with port multiplexing and error-checking, but zero connection state or delivery guarantees. Use UDP when low latency, speed, or real-time delivery outweighs packet loss concerns (e.g., voice/video calls, live video streaming, multiplayer gaming, DNS lookups, IoT metrics).

---

### 2. The Basics (Scratch Level):

#### Core Terminology & Building Blocks:

- **Port Numbers**: 16-bit identifiers (0–65535) used by both protocols to route packets to the correct OS process socket (e.g., Port 80/443 for HTTP, Port 53 for DNS).

#### Segment vs. Datagram:

- **TCP Segment**: TCP views data as an uninterrupted stream of bytes. It slices data into chunk sizes governed by the Maximum Segment Size (MSS).
- **UDP Datagram**: UDP preserves application message boundaries. One socket send() call equals exactly one UDP packet sent over the wire.

#### Header Overhead:

- **TCP Header**: Dynamic length of 20 to 60 bytes due to options (timestamps, window scaling, SACK).
- **UDP Header**: Fixed length of 8 bytes (Source Port, Destination Port, Length, Checksum).

#### Protocol Comparison Matrix:

| Feature                   | `TCP`                                 | `UDP`                            |
| ------------------------- | ------------------------------------- | -------------------------------- |
| **Connection State**      | Connection-oriented (Stateful)        | Connectionless (Stateless)       |
| **Data Transfer Unit**    | Byte Stream                           | Independent Datagrams            |
| **Reliability**           | Guaranteed delivery (Retransmissions) | Best-effort (No retransmissions) |
| **Ordering**              | Guaranteed in-order delivery          | Unordered                        |
| **Flow Control**          | Yes (rwnd window size)                | None                             |
| **Congestion Control**    | Yes (cwnd algorithms like CUBIC/BBR)  | None                             |
| **Head-of-Line Blocking** | Subject to Transport HoL Blocking     | No Transport HoL Blocking        |

---

### 3. Deep Dive & Architecture (Mid Level):

#### TCP Internal Mechanics:

#### 1. Connection Lifecycle:

##### 3-Way Handshake (Establishment):

- **Client $\to$ Server (SYN)**: Client picks initial sequence number $ISN_c$ and sends SYN.
- **Server $\to$ Client (SYN-ACK)**: Server picks $ISN_s$, acknowledges $ISN_c + 1$, and sends SYN-ACK.
- **Client $\to$ Server (ACK)**: Client acknowledges $ISN_s + 1$. Connection state transitions to ESTABLISHED.

##### 4-Way Teardown (Termination):

- Active closer sends FIN.
- Passive closer returns ACK (enters CLOSE_WAIT).
- Passive closer sends its own FIN when application closes socket.
- Active closer returns ACK and enters TIME_WAIT state for $2 \times \text{MSL}$ (Maximum Segment Lifetime, typically 60s) to clear inflight packets.

#### 2. Reliability & Sliding Window:

TCP uses sequence numbers assigned to every byte (not every packet). The receiver sends an Acknowledgment (ACK) indicating the next expected byte sequence number.

Sender Buffer:

```
[ ACKed & Sent ] [ Sent, UnACKed ] [ Usable Window ] [ Outside Window ]
^ ^ ^
SND.UNA SND.NXT SND.UNA + Window
```

- **Selective ACK (SACK - RFC 2018)**: Allows the receiver to inform the sender about non-contiguous blocks of received data so the sender retransmissions only lost segments, rather than re-sending from the last cumulative ACK.
- **Flow Control (rwnd)**: Receiver advertises its available socket receive buffer space in every TCP ACK header (rwnd). The sender restricts unacknowledged inflight bytes to $\le rwnd$ to avoid buffer overflow.
- **Congestion Control (cwnd)**: Prevents the sender from overwhelming intermediate network routers.Inflight data is bounded by $\min(cwnd, rwnd)$.
- **Slow Start**: $cwnd$ doubles every Round Trip Time (RTT) until reaching ssthresh.
- **Congestion Avoidance**: Linear additive increase ($+1\text{ MSS}$ per RTT).
- **Fast Retransmit & Recovery**: Triggered by 3 duplicate ACKs without waiting for Retransmission Timeout (RTO).

#### UDP Internal Mechanics:

UDP operates with minimal OS kernel state:

- Application passes a memory buffer to sendto().
- OS wraps it in an 8-byte UDP header and passes it down to Layer 3 (IP).
- Sender's NIC transmits packet immediately—no buffering for potential retransmission, no state machines.
- Receiver NIC processes IP header, routes to UDP port, pushes payload to socket buffer. If receiver socket buffer is full, kernel drops packet silently and increments error counter (udpInErrors).

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Transport Bottlenecks & Architectural Trade-offs

#### 1. Head-of-Line (HoL) Blocking:

If TCP packet sequence #2 is dropped in transit, packets #3, #4, and #5 sit in the receiver kernel buffer and cannot be delivered to the application layer until packet #2 is successfully retransmitted.

- **Impact**: High tail latency (p99) on lossy networks (e.g., mobile connections).

- **Modern Fix (HTTP/3 & QUIC)**: QUIC runs over UDP. It implements reliability and congestion control at the application layer while supporting independent multiplexed streams. A dropped packet on Stream A does not block data delivery on Stream B.

#### 2. Latency & Bandwidth-Delay Product (BDP):

Theoretical max TCP throughput is limited by $BDP = \text{Bandwidth} \times RTT$.

If TCP Window Scaling (RFC 1323) is disabled, rwnd is capped at 64 KB. On a 1 Gbps link with 100 ms RTT ($BDP = 12.5 \text{ MB}$), throughput collapses to $0.64 \text{ MB/s}$ (~5 Mbps).

#### Congestion Control Algorithms:

- **CUBIC (Loss-based)**: Interprets packet loss as congestion signal. Performs poorly on modern long-fat networks (LFNs) where random wireless loss occurs without queue congestion.
- **BBR (Bottleneck Bandwidth and RTT)**: Model-based congestion control developed by Google.Measures max bandwidth and minimum RTT directly instead of relying on loss, reducing bufferbloat and latency spikes.

#### 3. Low-Latency Performance Optimizations:

- **Nagle's Algorithm vs. Delayed ACKs**: Nagle's algorithm buffers small outgoing TCP writes until previous writes are ACKed. Combined with TCP Delayed ACKs (receiver delays ACK by 40–200ms expecting piggybacked data), this creates a catastrophic 40ms latency delay.
- **Fix**: Disable Nagle's algorithm on latency-critical RPC services (gRPC, Redis, DB clients) using the socket option TCP_NODELAY.
- **TCP Fast Open (TFO)**: Allows payload data to be sent inside the initial SYN packet using a cryptographic cookie, reducing handshake penalty from 1-RTT to 0-RTT for returning connections.

#### 4. High-Scale Failure Modes & System Mitigations:

- **SYN Flood Attack**: Attacker sends massive SYN packets from spoofed IPs to exhaust target server TCP connection connection tables (SYN_RECV queue).
- **Mitigation**: Enable TCP SYN Cookies (net.ipv4.tcp_syncookies = 1). Server encodes connection state inside sequence number returned in SYN-ACK, delaying socket memory allocation until client returns final ACK.
- **Ephemeral Port Exhaustion & TIME_WAIT Churn**: High-throughput reverse proxies (e.g., NGINX,HAProxy) initiating short-lived TCP connections to backend services exhaust available client ports ($65,535$).
- **Mitigation**: Enforce HTTP keep-alives/connection pooling, enable net.ipv4.tcp_tw_reuse, or allocate multiple outgoing IP addresses on outbound interfaces.

---

### 5. Text-Based Architecture Diagram:

```
   Comparison: TCP Reliability vs. UDP Multiplexed Streams (QUIC)
================================================================================
1. # TRADITIONAL TCP DATA FLOW (Subject to Transport Head-of-Line Blocking)

Client Application Network Server Application
|                                    |                                  |
|     [3-Way Handshake]              |                                  |
| --- SYN (Seq=100) ---------------> |                                  |
| <-- SYN-ACK (Seq=500, Ack=101) --  |                                  |
| --- ACK (Ack=501) ---------------> |                                  |
|                                    |                                  |
[Data Streams Multiplexed into single TCP Byte Stream]                  |
| --- Pkt 1 (Stream A) ------------> | -------------------------------> | Delivered
| --- Pkt 2 (Stream B) ------------> | --- [DROPPED IN TRANSIT] ------> X
| --- Pkt 3 (Stream C) ------------> | -------------------------------> | Buffered (Blocked)
|                                    |                                  | (Stream C waiting
| <-- Dup ACK (Next Expected = 2) -- |                                  | for Pkt 2)
| --- Retransmit Pkt 2 ------------> | -------------------------------> | Delivered
|                                    |                                  | Streams B & C released!

================================================================================
2. UDP / QUIC DATA FLOW (Independent Streams, Zero Transport HoL Blocking)
================================================================================

Client Application Network Server Application
|                                  | |
  [0-RTT / 1-RTT Handshake over UDP] |                                  |
| --- QUIC Initial + Crypto -------> | -------------------------------> | Processed
                                   | |                                  |
[Independent Streams Over UDP Datagrams] |                              |
| --- Datagram 1 (Stream A) -------> | -------------------------------> | Processed Stream A
| --- Datagram 2 (Stream B) -------> | --- [DROPPED IN TRANSIT] ------> X
| --- Datagram 3 (Stream C) -------> | -------------------------------> | Processed Stream C!
|                                    |                                  | (No waiting for Stream B)
| <-- SACK (Missing Stream B) ------ |                                  |
| --- Retransmit Datagram 2 -------> | -------------------------------> | Processed Stream B
```

---

### 6. Interview Checklist:

When discussing TCP vs. UDP during a high-level system design interview:

- **State the Right Default, then Justify**: Default to TCP (or HTTP/HTTPS over TCP) for core microservices, transactional workflows, and API design where data accuracy and order are mandatory.Justify UDP only when ultra-low latency, custom packet framing, or high-loss resilience is explicitly required.

- **Diagnose Tail Latency via HoL Blocking**: If designing real-time interactive systems (e.g., live video streaming, voice chat, multiplayer gaming, or IoT telemetry), explicitly bring up TCP Head-of-Line blocking and tail latency spikes as your justification for adopting UDP or HTTP/3 (QUIC).

- **Demonstrate OS/Kernel Awareness**: Mention production socket-tuning primitives to highlight backend engineering depth:

- Setting TCP_NODELAY to bypass Nagle's algorithm and reduce micro-service RPC latency.

- Tuning SO_REUSEPORT / tcp_tw_reuse to mitigate ephemeral port exhaustion on proxy nodes.

- Utilizing BBR congestion control over default CUBIC for high-bandwidth WAN connections.

- **Proactively Pitch QUIC/HTTP/3**: When designing modern web-scale clients (e.g., mobile apps on lossy cellular networks), propose UDP-based QUIC to combine TCP-grade reliability and security (TLS 1.3) with 0-RTT handshakes and stream-level multiplexing.
