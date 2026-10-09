## Working of Internet (DNS, IP)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Think of the Internet as a global postal delivery service operating alongside an international telephone registry:

- **DNS (Domain Name System - The Contact List)**: If you want to call a friend, you tap their human-readable name (Alice) in your phone contacts rather than memorizing a 10-digit number. DNS translates human-friendly domain names (example.com) into numerical machine addresses (93.184.216.34).

- **IP (Internet Protocol - The Postal Routing Address)**: An IP address is like a complete physical mailing address (Country, State, City, Street, House Number). Every device connected to the Internet gets an IP address so that intermediate routing hubs (postal sorting facilities / network routers) know precisely which direction to forward data packets, hop by hop, across the world.

#### The Core Problem Solved:

- Computers and networking hardware (routers, switches) route binary packets using fixed-width numerical addresses (IPv4/IPv6) to maximize hardware processing speed. Humans, however, communicate through memorable text strings (google.com).

- The combination of DNS and IP bridges human usability with high-speed machine routing, enabling billions of heterogeneous devices to locate each other and exchange data in milliseconds without central coordination.

---

### 2. The Basics (Scratch Level):

#### Internet Protocol (IP): Addressing the Nodes:

Every packet sent over the Internet contains an IP Header specifying the Source IP and Destination IP.

- **IPv4 ($32$-bit addresses)**: Written in dotted decimal notation (e.g., `192.168.1.1`). Offers $2^{32} \approx 4.3 \text{ billion}$ unique addresses, which are now exhausted.

- **IPv6 ($128$-bit addresses)**: Written in hexadecimal blocks separated by colons (e.g., `2001:0db8:85a3::8a2e:0370:7334`). Offers $2^{128} \approx 3.4 \times 10^{38}$ unique addresses, eliminating the need for address translation hacks at scale.

- **Packets**: Data sent across the internet is chunked into small independent units (typically $\le 1500\text{ bytes}$, bounded by the Maximum Transmission Unit / MTU). Each packet carries metadata (IP headers, Time To Live / TTL, checksums) and payload data.

#### Domain Name System (DNS): The Distributed Hierarchy:

DNS is a hierarchical, distributed database structured like an inverted tree:

```
                     [ Root Zone (.) ]
                             │
        ┌────────────────────┴────────────────────┐
        ▼                                         ▼
  [ .com TLD ]                              [ .org TLD ]
        │                                         │
 [ example.com ]                           [ wikipedia.org ]
```

- **Recursive Resolver**: Public/ISP DNS server (e.g., 8.8.8.8, 1.1.1.1) that receives queries from clients and traverses the DNS hierarchy to find the answer.
- **Root Name Servers (.)**: 13 root server IP identities (operated by ICANN/IANA) that direct resolvers to the appropriate Top-Level Domain (TLD) servers.
- **TLD Name Servers**: Servers responsible for top-level domains (.com, .org, .io, .net).
- **Authoritative Name Servers**: The ultimate source of truth managed by domain owners or DNS providers (e.g., Cloudflare, Route53) holding the actual domain records.

#### Essential DNS Record Types:

- **`A` Record**: Maps a hostname to an IPv4 address (`example.com` $\rightarrow$ `93.184.216.34`).
- **`AAAA` Record**: Maps a hostname to an IPv6 address (`example.com` $\rightarrow$ `2001:db8::1`).
- **`CNAME` Record**: Canonical Name alias (`[www.example.com]``(https://www.example.com)` $\rightarrow$`example.com`).
- **`MX` Record**: Directs email traffic to mail servers.
- **`NS` Record**: Delegates a DNS zone to specific Authoritative Name Servers.
- **`TXT` Record**: Stores arbitrary text used for domain ownership verification, SPF, and DKIM security records.

---

### 3. Deep Dive & Architecture (Mid Level):

#### Complete Recursive DNS Resolution Lifecycle:

When a user types `[https://example.com]``(https://example.com)` into a web browser:

```
                           [ Browser Cache ] ──(Miss)──> [ OS Resolver Cache ] ──(Miss)──> [ Local Router Cache ]
                                                                     │
                                                               (Cache Miss)
                                                                     │
                                                                     ▼
                                                         [ Recursive Resolver ]
                                                         (e.g., ISP or 1.1.1.1)
                                                                     │
┌────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────┐
│ 1. Query Root Server (.)                                           │ 2. Returns IPv4 of .com TLD Server                                 │
│ 3. Query TLD Server (.com)                                         │ 4. Returns IPv4 of Authoritative Server (ns1.example.com)          │
│ 5. Query Authoritative Server (ns1.example.com)                    │ 6. Returns A Record: 93.184.216.34 (TTL: 300s)                     │
└────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────┘
                                                                     │
                                                                     ▼
                                                         [ Caches Record for TTL ]
                                                                     │
                                                                     ▼
                                                         [ Returns IP to Browser ]
```

1. **Local Cache Check**: The OS checks browser cache, local OS DNS cache, and the local `hosts` file.

2. **Recursive Query**: If uncached, the OS sends a UDP query on port 53 to the configured Recursive Resolver.

3. **Root Lookups**: The Recursive Resolver queries a Root Server (`.`). The Root server responds with the IP address of the TLD Server responsible for `.com`.

4. **TLD Lookups**: The Resolver queries the `.com` TLD server. The TLD server responds with the IP address of the Authoritative Name Server for `example.com`.

5. **Authoritative Lookup**: The Resolver queries the Authoritative Name Server, which returns the target `A` record (`93.184.216.34`) and its Time-To-Live (TTL).

6. **Caching & Response**: The Recursive Resolver stores the record in its local cache for the specified TTL duration and returns the IP address to the client.

#### IP Packet Routing & Border Gateway Protocol (BGP):

Once the client obtains the destination IP address (`93.184.216.34`), it initiates a TCP handshake. But how does the packet travel across thousands of physical miles?

```
[ Client ] ──> [ Home Gateway ] ──> [ ISP Edge Router ] ──(BGP Transit)──> [ Backbone Tier-1 ISP ] ──> [ Data Center Router ] ──> [ Server ]
```

- **Subnets & CIDR**: IP addresses are grouped into subnets using Classless Inter-Domain Routing (CIDR) notation (e.g., `192.168.1.0/24`). The `/24` prefix indicates that the first 24 bits represent the network ID, and the remaining 8 bits identify individual hosts.

- **Longest Prefix Match**: Routers forward packets by checking their internal routing table and choosing the route with the narrowest matching CIDR prefix (e.g., matching a `/28` route over a `/16` route).

- **Autonomous Systems (AS) & BGP**: The Internet is a "network of networks" composed of over 70,000 independent Autonomous Systems (AS) (ISPs, Tech Giants, Universities). BGP (Border Gateway Protocol) is the glue protocol that AS networks use to advertise IP prefix ownership to each other, computing paths based on hop counts, network policy, and peering agreements.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Performance Optimization: Anycast Routing:

How do public DNS providers (Cloudflare `1.1.1.1`, Google `8.8.8.8`) serve requests globally in under $10\text{ ms}$?

- **Unicast vs. Anycast**: In Unicast, one IP address maps to one physical server. In Anycast, the exact same IP address is announced via BGP simultaneously from hundreds of data centers globally.

- **BGP Routing to Edge**: When a client sends a packet to `1.1.1.1`, global internet routers automatically direct the packet to the topologically closest data center announcing that IP, distributing traffic geographically and mitigating DDoS attacks.

```
                  ┌──► [ London Data Center (Announcing 1.1.1.1) ]
                  |
[ Client (UK) ] ──┴──► (BGP routes packet to shortest network path: London)
```

#### The TTL Trade-off Matrix:

| Strategy                             | `Advantages`                                                                                     | `Disadvantages`                                                                                                  | `Ideal Use Case`                                                    |
| ------------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **High TTL (e.g., 86400s / 24 hrs)** | High cache hit ratio, ultra-low user latency, reduces Authoritative server query costs and load. | Slow propagation during IP changes or disaster recovery failover (changes take 24 hours to propagate worldwide). | Static assets, stable infrastructure, long-lived APIs.              |
| **Low TTL (e.g., 30s - 60s)**        | Instant failover capability; allows rapid blue-green deployments or IP migration.                | Increases resolution latency spikes for users; subjects Authoritative DNS servers to continuous query load.      | Active-passive disaster recovery, dynamic load balancing endpoints. |

#### Failure Modes & Modern Protocols:

#### 1. DNS Cache Poisoning (Kaminsky Attack):

- **Failure Mode**: An attacker floods a Recursive Resolver with forged UDP DNS responses before the real Authoritative server replies, injecting malicious IP mappings into the resolver cache.
- **Mitigation**: DNSSEC (DNS Security Extensions) adds cryptographic digital signatures (RRSIG, DNSKEY) to DNS records, allowing resolvers to verify record authenticity.

#### 2. Eavesdropping & Privacy Leaks:

- **Failure Mode**: Traditional DNS uses unencrypted UDP port 53. ISPs and network eavesdroppers can log every domain a user queries.
- **Mitigation**: DoH (DNS-over-HTTPS / Port 443) and DoT (DNS-over-TLS / Port 853) encrypt DNS queries inside TLS tunnels, preventing tampering and snooping.

#### 3. BGP Hijacking:

- **Failure Mode**: A rogue or misconfigured Autonomous System announces an IP prefix it does not own, routing global traffic intended for a bank or cloud provider through the rogue network.
- **Mitigation**: RPKI (Resource Public Key Infrastructure) cryptographically verifies that an AS is authorized to announce specific IP address blocks.

---

### 5. Text-Based Architecture Diagram:

```
================================================================================
                   INTERNET LOOKUP & PACKET ROUTING PIPELINE
================================================================================

1. DOMAIN NAME RESOLUTION TIER (Control Plane)
--------------------------------------------------------------------------------
[ User Browser ]
      │
      │ (1. UDP 53 Request: "Where is api.example.com?")
      ▼
[ Recursive Resolver (Anycast 1.1.1.1) ]
      ├── (2. Check Local Cache) ──[ HIT ]──> Returns IP 93.184.216.34
      │
      ├── [ MISS ]
      │
      ├── (3. Query Root Server ".") ───────> Returns TLD NS IP
      ├── (4. Query TLD Server ".com") ─────> Returns Auth NS IP
      └── (5. Query Auth Server "ns1") ─────> Returns A Record (IP + TTL)


2. IP PACKET ROUTING TIER (Data Plane)
--------------------------------------------------------------------------------
[ Client Machine (IP: 192.168.1.50) ]
      │
      │ (Constructs TCP SYN Packet | Dest IP: 93.184.216.34 | Dest Port: 443)
      ▼
[ Local Gateway / NAT Router ]
      │ (Translates Private IP to Public WAN IP via NAT)
      ▼
[ ISP Edge Router ]
      │
      │ (BGP Route Table: Longest Prefix Match lookup for 93.184.216.34)
      ▼
[ Autonomous System (AS1234) ] ──(BGP Transit Peering)──> [ Autonomous System (AS5678) ]
                                                                 │
                                                                 ▼
                                                   [ Destination Data Center ]
                                                                 │
                                                                 ▼
                                                   [ Target Web Server (93.184.216.34) ]
================================================================================
```

---

### 6. Interview Checklist:

- **Explain the Separation of Control and Data Planes**: Clarify early that DNS is the control plane system mapping human identifiers to machine addresses, while IP/BGP is the data plane system handling physical packet delivery across networks.

- **Trace DNS Resolution Step-by-Step**: Walk through the complete resolution hierarchy: Client Cache $\rightarrow$ Recursive Resolver $\rightarrow$ Root Server $\rightarrow$ TLD Server $\rightarrow$Authoritative Server $\rightarrow$ Record Caching. Mention DNS record types (A, AAAA, CNAME, NS).

- **Detail Global Optimization Secrets (Anycast & BGP)**: Demonstrate senior architecture experience by explaining how Anycast BGP routing allows public DNS networks (Cloudflare, Google) to serve queries from the nearest edge POP, handling massive global scale and providing inherent DDoS mitigation.

- **Discuss Security & Failover Mechanics**: Address real-world production risks: how TTL choice affects disaster recovery failover speed versus cache performance, and how modern protocols (DNSSEC, DoH, RPKI) protect against DNS cache poisoning, eavesdropping, and BGP route hijacking.
