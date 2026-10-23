## Tokens for auth (JWT)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine an VIP wristband issued at a festival.

- Instead of checking a central guest list database every time you enter a new stage, security guards simply look at your wristband. The wristband has your name, granted permissions (e.g., "VIP Access"), an expiration time, and an anti-tamper stamp applied using specialized fluorescent ink by the event director.

- Guards only need to check the stamp using a UV flashlight to instantly verify its authenticity on the spot. They don't need to radio headquarters every time you walk into a restricted area.

#### The Problem It Solves:

- In traditional session-based authentication, a client receives a random session ID stored in a database or cache (e.g., Redis). On every single incoming HTTP request, microservices must execute a remote network call to the central session store to validate the session ID and fetch user details.

- In a distributed microservice architecture processing hundreds of thousands of requests per second, this central session store quickly becomes a critical scalability bottleneck, single point of failure, and latency overhead.

- JSON Web Tokens (JWT) solve this by introducing stateless self-contained authentication. The token carries the user's identity and permissions directly inside its payload, cryptographically signed by an Auth Server. Downstream services verify the authenticity of the token independently using fast, local CPU operations—completely eliminating central session database lookups.

---

### 2. The Basics (Scratch Level):

#### Anatomy of a JWT:

A JWT (RFC 7519) is an open, URL-safe standard represented as three distinct string segments separated by dots (.): `Header.Payload.Signature`.

```JWT
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFsaWNlIiwicm9sZXMiOlsiYWRtaW4iXSwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjE3MDAwMDM2MDB9.dHJ1c3RlZF9zaWduYXR1cmVfYnlfYXV0aF9zZXJ2ZXI
```

| Segment       | `Encoding / Format`         | `Purpose`                                                                                | `Key Contents`                                              |
| ------------- | --------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| **Header**    | Base64URL JSON              | Metadata about the token type and cryptographic algorithm used.                          | {"alg": "RS256", "typ": "JWT"}                              |
| **Payload**   | Base64URL JSON              | Contains "Claims"—statements about the entity (user) and additional operational context. | {"sub": "usr_123", "roles": ["admin"], "exp": 1700003600}   |
| **Signature** | Cryptographic Hash / Cipher | Proves token authenticity and integrity; ensures payload hasn't been tampered with.      | $HMACSHA256(\text{Header} . \text{Payload}, \text{Secret})$ |

- **Critical Distinction**: Base64URL encoding is NOT encryption. Anyone can decode the Payload of a standard JWT. Never place sensitive data (such as raw passwords, SSNs, or API secrets) in an unencrypted JWT payload.

#### Standard Claims Terminology:

- sub (Subject): The unique identifier of the user/principal (e.g., user_id).
- iss (Issuer): The identity of the Auth Server that minted the token (e.g., [https://auth.company.com](https://auth.company.com)).
- aud (Audience): The intended recipient service(s) of the token (e.g., [https://api.company.com/v1](https://api.company.com/v1)).
- exp (Expiration Time): Unix timestamp defining when the token becomes invalid.
- iat (Issued At): Unix timestamp marking token creation time.
- jti (JWT ID): A unique string identifier assigned to a specific token instance (used for anti-replay and single-token revocation).

---

### 3. Deep Dive & Architecture (Mid Level):

#### Symmetric vs. Asymmetric Signing Strategies:

```
SYMMETRIC SIGNING (HS256)
[ Auth Server ]  ──(Signs with Secret Key)──► [ JWT ]
                                              │
                                              ▼
[ Service A ]    ◄──(Verifies with SAME Secret Key)──┤
[ Service B ]    ◄──(Verifies with SAME Secret Key)──┘
* Issue: If Service B is compromised, attackers steal Secret Key & can MINT valid fake JWTs!

ASYMMETRIC SIGNING (RS256 / ES256)
[ Auth Server ]  ──(Signs with PRIVATE Key)──► [ JWT ]
                                               │
                                               ▼
[ Service A ]    ◄──(Verifies with PUBLIC Key)──┤
[ Service B ]    ◄──(Verifies with PUBLIC Key)──┘
* Secure: Services only hold PUBLIC Key. They can verify JWTs, but CANNOT mint new ones.
```

#### 1. Symmetric Key Signing (HS256 / HMAC-SHA256):

Uses a single shared secret key for both signing and verifying tokens.

- **Mechanics**: Fast computational execution; low CPU overhead.
- **Architectural Risk**: Every microservice that needs to verify JWTs must possess a copy of the shared secret. If a single low-security microservice is breached, the attacker extracts the shared secret and can mint arbitrary valid tokens for the entire ecosystem.

#### 2. Asymmetric Key Signing (RS256 or ES256):

Uses a Key Pair: The Auth Server holds a Private Key to sign tokens, while all downstream API Gateways and microservices hold the corresponding Public Key to verify signatures.

- **Mechanics**: Uses RSA or Elliptic Curve (ECDSA) algorithms.
- **Architecture**: Resource servers fetch the Public Key dynamically from the Auth Server via a standardized JWKS (JSON Web Key Set) endpoint ([https://auth.company.com/.well-known/jwks.json](https://auth.company.com/.well-known/jwks.json)).

- **Security Isolation**: Microservices cannot forge tokens even if their host environments are fully compromised.

```
End-to-End Authentication & Validation Lifecycle
[ Client App ]            [ Auth Server ]           [ API Gateway ]       [ Microservice ]
     │                          │                         │                     │
     │ 1. POST /login           │                         │                     │
     ├─────────────────────────►│                         │                     │
     │    (user/pass)           │                         │                     │
     │                          │                         │                     │
     │ 2. Return JWT            │                         │                     │
     │◄─────────────────────────┤                         │                     │
     │    (Access + Refresh)    │                         │                     │
     │                          │                         │                     │
     │ 3. GET /orders (Header: Authorization: Bearer <JWT>)                     │
     ├───────────────────────────────────────────────────►│                     │
     │                                                    │ 4. Fetch Public Key │
     │                                                    │    via JWKS (Cached)│
     │                                                    ├─────────┐           │
     │                                                    │         │           │
     │                                                    │◄────────┘           │
     │                                                    │                     │
     │                                                    │ 5. Local Sig Check  │
     │                                                    │    + exp Validation │
     │                                                    │                     │
     │                                                    │ 6. Forward Request  │
     │                                                    │    + User Context   │
     │                                                    ├────────────────────►│
     │                                                    │ (X-User-Id: 123)    │
```

- **Token Minting**: User authenticates against Auth Server. Auth Server signs a short-lived Access JWT and returns it to the client alongside a long-lived, opaque Refresh Token.

- **Key Distribution**: On startup, the API Gateway or microservice retrieves the public keys from the Auth Server’s JWKS endpoint and caches them locally in memory.

Stateless Verification: When an API request arrives, the Gateway/Service executes an in-memory validation chain:

- Decodes Header and Payload.
- Verifies the cryptographic signature using the cached Public Key.
- Checks current time against exp and nbf (Not Before) timestamps.
- Verifies that iss and aud match expected domain values.

- **Context Downstreaming**: The API Gateway strips or preserves the JWT, and forwards enriched internal request headers (e.g., X-User-Id: 123, X-User-Roles: admin) down to internal backend microservices.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### The JWT Invalidation Problem & Mitigation Patterns:

Because JWT validation is purely stateless, you cannot natively revoke a JWT before its exp time arrives. If a user logs out, gets fired, or has their account compromised, a leaked JWT remains valid until it expires.

Architects address this fundamental trade-off using three primary strategies:

#### Strategy A: Dual-Token Architecture (Short-Lived Access JWT + Long-Lived Refresh Token)

- Set Access JWT lifespan to a very short duration (e.g., 5 to 15 minutes).
- Issue a long-lived, cryptographically secure random string as a Refresh Token stored in a central database (Redis/PostgreSQL).
- When the Access JWT expires, the client uses the Refresh Token to request a new JWT from the Auth Server. If a user is revoked or banned, the Auth Server deletes the Refresh Token from the database—capping the window of exposure for a leaked JWT to a maximum of 15 minutes.

#### Strategy B: Distributed Deny-list / Blacklist (Redis Bloom Filters)

- When a user logs out or requires emergency revocation, record the token’s unique identifier (jti) in a distributed, high-speed cache (e.g., Redis) with a Time-To-Live (TTL) equal to the remaining lifespan of the JWT.
- The API Gateway checks Redis for jti existence on incoming calls.
- Trade-off: Re-introduces stateful centralized database lookups, but limits checks only to active revocation windows. Using a Bloom Filter in front of Redis reduces memory footprint and avoids network round-trips for non-revoked tokens.

#### Strategy C: Token Versioning / User Security Epoch

- Include a token_version integer in the JWT payload (e.g., {"sub": "usr_123", "ver": 3}).
- Cache a key-value mapping of user version numbers in memory/Redis (user:123:version = 3).
- To invalidate all issued tokens for a specific user instantly (e.g., upon password reset), increment the user's version counter in Redis (user:123:version = 4). Any JWT presented with ver < 4 is immediately rejected.

#### Known Vulnerabilities & Hardening Controls:

- **The alg**: none Exploit: Attackers modify the JWT header to {"alg": "none"} and strip the signature segment. Weak libraries parse the token as valid without verifying the signature.
- **Hardening**: Explicitly enforce allowed algorithms (e.g., require alg = RS256) at the verifier initialization level; reject none unconditionally.
- **Algorithm Confusion Attack (RS256 vs. HS256)**: Attackers take a service expecting RS256, change the token header to HS256, and sign the token using the server's publicly available RSA Public Key as the HMAC secret key.
- **Hardening**: Enforce strict typing between signature key types and cryptographic algorithms; never pass generic key material into validation functions without explicit algorithm verification.

#### Client-Side Storage Vulnerabilities (XSS vs. CSRF):

- Storing JWTs in browser localStorage or sessionStorage exposes tokens to theft via Cross-Site Scripting (XSS).
- Storing JWTs in raw Cookies exposes requests to Cross-Site Request Forgery (CSRF).
- **Best Practice**: Store tokens in HttpOnly, Secure, SameSite=Strict Cookies, or execute the BFF (Backend-For-Frontend) Pattern, where the browser holds an encrypted session cookie and an edge proxy manages the downstream JWT emissions.

---

### 5. Text-Based Architecture Diagram:

**Scalable Asymmetric JWT Ingestion & Revocation Ecosystem**

```
===================================================================================================
1. INITIAL AUTHENTICATION & KEY MANAGEMENT PIPELINE
===================================================================================================
 [ Auth Server Cluster ] ──(Generates RSA Key Pair)
       │
       ├── Holds: PRIVATE KEY (Used exclusively to sign new tokens)
       │
       └── Exposes JWKS Endpoint: GET https://auth.domain.com/.well-known/jwks.json
                 │
                 │ (HTTP GET - Public Keys Cached in Memory)
                 ▼
 [ API Gateway / Resource Servers ]

===================================================================================================
2. INCOMING REQUEST VERIFICATION & REVOCATION CHECK
===================================================================================================
 [ Client Browser / App ]
       │
       │ HTTP GET /v1/user/profile
       │ Header: Authorization: Bearer <JWT_Payload_And_Sig>
       v
 +───────────────────────────────────────────────────────────────────────────────────────────────+
 | API GATEWAY LAYER                                                                             |
 |                                                                                               |
 |  1. Parse Header -> Extract Header, Payload, Signature                                        |
 |  2. Signature Check -> Verify against cached JWKS Public Key                                  |
 |  3. Time Validation -> Confirm current_time < exp AND current_time > nbf                      |
 |                                                                                               |
 |  4. Revocation Validation (Fast Path):                                                        |
 |     ├── Check local Bloom Filter for `jti`                                                    |
 |     └── If match -> Query Central Redis Cluster (`EXISTS blacklist:{jti}`)                    |
 +──────────────────────────────────────────────┬────────────────────────────────────────────────+
                                                │
                                                │ Validation Passed (Stateless Execution)
                                                v
===================================================================================================
3. INTERNAL MICROSERVICE FORWARDING
===================================================================================================
 +───────────────────────────────────────────────────────────────────────────────────────────────+
 | INTERNAL HIGH-SPEED SERVICE MESH                                                              |
 | (Gateway injects verified user identity context into sanitized headers)                       |
 +──────────────────────────────────────────────┬────────────────────────────────────────────────+
                                                │
                         ┌──────────────────────┴──────────────────────┐
                         │ Header: X-User-ID: 10492                    │ Header: X-User-ID: 10492
                         │ Header: X-User-Roles: User,Seller           │ Header: X-User-Roles: User
                         v                                             v
              [ User Profile Service ]                      [ Order Processing Service ]
```

---

### 6. Interview Checklist:

When pitching JWT and token-based authentication in a system design interview:

- **Emphasize the Scalability Motivation**: Frame JWTs as a solution to scale stateless authentication, avoiding database IO bottlenecks on every API call compared to traditional session IDs.

- **Specify Asymmetric Signing (RS256/ES256)**: Never just say "JWT is signed." Explicitly recommend asymmetric key pairs with JWKS public key distribution to ensure microservices cannot forge tokens if compromised.

- **Address the Invalidation Trade-off Proactively**: Demonstrate senior engineering awareness by stating: "JWTs are stateless, which makes immediate revocation difficult." Immediately follow up with your solution: Short-lived Access JWTs (5-15 mins) + Long-lived Refresh Tokens stored in Redis.

- **Highlight Storage & Security Hardening**: Explicitly cover security edge cases—mention defending against alg: none exploits, preventing token leakage via HttpOnly/SameSite cookie flags or the Backend-for-Frontend (BFF) pattern, and enforcing token rotation.
