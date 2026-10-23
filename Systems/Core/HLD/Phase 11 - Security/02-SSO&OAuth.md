## SSO & OAut

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

- **OAuth 2.0 (Delegated Authorization) is like a Valet Key**: When you give your car to a valet, you don't give them your master house key, credit card, or driver's license. You give them a restricted valet key that allows them to start the car and drive it to the parking spot, but prevents them from opening the trunk or glove box. You delegate limited access without giving away your core identity or full permissions.

- **SSO / OIDC (Single Sign-On / Authentication) is like a Government Passport**: When visiting an international resort complex containing a hotel, casino, and water park, you show your passport once at the central reception desk. Reception verifies your identity and issues a single digital room keycard. From that point on, every venue inside the resort trusts the keycard to let you in, without requiring you to re-verify your passport at every single door.

#### The Problem It Solves:

- OAuth 2.0 solves the security risk of sharing user credentials (passwords) with third-party applications.Instead of giving a third-party app your raw password to access your data, OAuth 2.0 provides delegated token-based access with explicit scope boundaries.

- SSO (Single Sign-On) solves credential fatigue and identity fragmentation across multiple enterprise applications. Instead of forcing users to manage separate passwords across dozens of distinct services,SSO centralizes identity management into a single Identity Provider (IdP).

---

### 2. The Basics (Scratch Level):

#### Authentication vs. Authorization:

A critical prerequisite for system design is isolating identity from access delegation:

```
[ Authentication (AuthN) ] ──► "Who are you?"       ──► Handled by SSO / OIDC / SAML
[ Authorization  (AuthZ) ] ──► "What can you do?"  ──► Handled by OAuth 2.0
Authentication (AuthN): Verifying the identity of a principal (e.g., proving Alice is Alice).
```

- **Authorization (AuthZ)**: Granting an authenticated principal permission to access specific resources (e.g.,granting App X read-only access to Alice's photos).

#### OAuth 2.0 Core Roles

RFC 6749 defines four distinct roles in an OAuth 2.0 framework:

| Role                     | `Definition`                                                      | `Real-World Example`                    |
| ------------------------ | ----------------------------------------------------------------- | --------------------------------------- |
| **Resource Owner**       | The end-user who owns the data and grants access to it.           | You (Alice).                            |
| **Client**               | The third-party application requesting access to the user's data. | A photo-printing app.                   |
| **Authorization Server** | The central server issuing tokens after authenticating the user.  | Okta, Auth0, Google Identity, Keycloak. |
| **Resource Server**      | The API host holding the protected user data.                     | Google Drive API, GitHub API.           |

`Key Protocols`: **OAuth 2.0 vs. OIDC vs. SAML 2.0**

- OAuth 2.0: Purely an authorization framework. It issues Access Tokens, but intentionally provides no standardized information about who the user is.

- **OpenID Connect (OIDC)**: An identity layer built on top of OAuth 2.0. It introduces a standardized ID Token (a JWT) containing authenticated user profile claims (sub, email, name). OIDC is the modern standard for SSO.

- **SAML 2.0 (Security Assertion Markup Language)**: An older, XML-based enterprise SSO standard. It uses HTTP POST redirects to exchange signed XML assertions between an Identity Provider (IdP) and Service Provider (SP). Heavily used in legacy corporate enterprise systems.

---

### 3. Deep Dive & Architecture (Mid Level):

`Modern Gold Standard`: **Authorization Code Flow with PKCE**
For SPA (Single Page Apps), mobile apps, and backend services, the Authorization Code Flow with PKCE(Proof Key for Code Exchange - RFC 7636) is mandatory to prevent authorization code interception attacks.

```
[ User Browser / App ]      [ Client Backend ]         [ Auth Server (IdP) ]      [ Resource Server (API) ]
         │                         │                            │                           │
         │ 1. User clicks "Login"  │                            │                           │
         ├────────────────────────►│                            │                           │
         │                         │ Generate PKCE Pair:        │                           │
         │                         │ - verifier = random_bytes  │                           │
         │                         │ - challenge = SHA256(ver)  │                           │
         │                         │                            │                           │
         │ 2. Redirect to /authorize?client_id=X&code_challenge=challenge&scope=openid profile│
         ├─────────────────────────────────────────────────────►│                           │
         │                                                      │                           │
         │ 3. User enters credentials & approves consent        │                           │
         │──────────────────────────────────────────────────────┤                           │
         │                                                      │                           │
         │ 4. Redirect to callback URI with Authorization Code  │                           │
         │◄─────────────────────────────────────────────────────┤                           │
         │    (?code=AUTH_CODE_123)                             │                           │
         │                                                      │                           │
         │ 5. POST /oauth/token                                 │                           │
         │   (code=AUTH_CODE_123 & code_verifier=verifier)      │                           │
         ├─────────────────────────►│                           │                           │
         │                          ├──────────────────────────►│                           │
         │                          │ 6. Validates SHA256(ver)  │                           │
         │                          │    matches code_challenge │                           │
         │                          │                           │                           │
         │                          │ 7. Issue Tokens           │                           │
         │                          │◄──────────────────────────┤                           │
         │                          │    (ID Token + Access Token + Refresh Token)          │
         │                          │                           │                           │
         │ 8. Login Complete        │                           │                           │
         │◄─────────────────────────┤                           │                           │
         │                          │ 9. GET /api/v1/user/orders                            │
         │                          │    Header: Authorization: Bearer <Access_Token>       │
         │                          ├──────────────────────────────────────────────────────►│
```

#### Flow Breakdown & Mechanics:

- **PKCE Key Generation**: The Client generates a cryptographically random string (code_verifier) and computes its SHA-256 hash (code_challenge).
- **Authorization Request**: The client redirects the user to the Auth Server's /authorize endpoint, passing:
- **client_id**: Unique identifier for the client app.
- **redirect_uri**: Whitelisted callback URL.
- **scope**: Permissions requested (e.g., openid profile read:orders). openid triggers OIDC mode.
- **state**: Anti-CSRF token generated by the client.
- **code_challenge & code_challenge_method=S256**: PKCE protection parameters.
- **Authentication & Consent**: The Auth Server authenticates the user (via credentials, MFA, or session cookie) and displays the scope consent screen.
- **Code Authorization**: Upon approval, the Auth Server redirects the user's browser back to redirect_uriwith a temporary, short-lived code (lifespan ~60 seconds).
- **Token Exchange**: The client sends a server-to-server POST request to the Auth Server's /token endpoint containing code and the unhashed code_verifier.
- **PKCE Verification**: The Auth Server hashes the received code_verifier and verifies it matches the code_challenge supplied in step 2. This proves the party requesting tokens is the exact same party that initiated the flow.

#### Token Delivery: The Auth Server issues:

- **ID Token (JWT)**: Contains authenticated identity claims for client UI rendering.
- **Access Token (JWT or Opaque)**: Used to authorize requests to Resource Servers.
- **Refresh Token**: Used to obtain new access tokens without requiring user re-authentication.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Critical Security Vulnerabilities & Hardening:

#### 1. CSRF on Redirects & The state Parameter

- **Threat**: An attacker intercepts the redirect flow and trick a victim's authenticated browser session into redeeming an authorization code linked to the attacker's account.
- **Mitigation**: The client must generate a cryptographically strong, unguessable state token bound to the user's local browser session, send it in step 2, and verify that the state parameter returned in step 4 matches the original value before exchanging the code.

#### 2. Replay Attacks & The nonce Parameter

- **Threat**: An attacker intercepts a valid ID Token and replays it to impersonate a user on another client app.
- **Mitigation**: In OIDC flows, the client generates a cryptographic nonce passed in the initial request. The Auth Server embeds the nonce directly into the signed ID Token payload. The client verifies that the ID Token's nonce matches the locally saved request state before trusting identity claims.

#### 3. Token Theft Prevention: Refresh Token Rotation (RTR) & Sender-Constrained Tokens

In public client applications (SPAs, mobile apps), tokens stored client-side are vulnerable to theft via XSS or malicious device software.

```
REFRESH TOKEN ROTATION (RTR)
[ Client ]                                     [ Auth Server ]
   │                                                 │
   │ 1. POST /token (Refresh_Token_A)                │
   ├────────────────────────────────────────────────►│
   │                                                 │ Validates Token_A
   │ 2. Returns Token_B + Access_Token_2             │ Invalidates Token_A
   │◄────────────────────────────────────────────────┤ Issues Token_B
   │                                                 │
   │ ... Time Passes ...                             │
   │                                                 │
   │ 3. Attacker replays stolen Token_A              │
   ├────────────────────────────────────────────────►│
   │                                                 │ REUSE DETECTED! Token_A was already redeemed!
   │ 4. HTTP 401 Unauthorized                        │ ACTION: Instantly revokes ENTIRE token family
   │◄────────────────────────────────────────────────┤ (Tokens A, B, and active user session)
```

- **Refresh Token Rotation (RTR)**: Every time a Refresh Token is redeemed, the Auth Server invalidates it and issues a brand-new Refresh Token. If an old, already-redeemed Refresh Token is ever presented again, the Auth Server flags a Token Reuse Breach and instantly revokes all tokens descended from that family tree.

- **Demonstrating Proof-of-Possession (DPoP - RFC 9449)**: Cryptographically binds Access and Refresh Tokens to a private key held locally by the client. The client signs an ephemeral HTTP header for every API request using its private key. An attacker who steals the Access Token cannot use it without possessing the client's underlying private key.

#### SSO Single Logout (SLO) Architectures:

- Managing session termination across federated microservice networks is a complex design challenge:

- **Front-Channel Logout**: The Auth Server loads invisible `<iframe>` elements or HTTP redirects in the user's browser for every logged-in app. Drawback: Unreliable; blocked by modern browser third-party cookie restrictions and ad-blockers.
- **Back-Channel Logout**: The Auth Server sends direct server-to-server HTTP POST requests containing a signed Logout Token to every registered application service. Advantage: Highly reliable, secure, and independent of client-side browser quirks.

---

### 5. Text-Based Architecture Diagram:

**Federated SSO & OAuth 2.0 Integration Architecture**

```
===================================================================================================
1. FEDERATED IDENTITY PROVIDER (SSO TRUST BOUNDARY)
===================================================================================================
               +──────────────────────────────────────────────+
               | Central Identity Provider (IdP)              |
               | (e.g., Okta / Auth0 / PingIdentity)          |
               |                                              |
               | - User Identity Directory (LDAP / DB)        |
               | - OIDC Discovery Endpoint (.well-known)      |
               | - Private Key Management (JWKS Endpoint)     |
               | - Session Store (Redis Cluster)              |
               +──────────────────────┬───────────────────────+
                                      ▲
                                      │ Standardized OpenID Connect (OIDC / OAuth 2.0)
                                      │ (Token Exchange / PKCE / Verification)
                                      ▼
===================================================================================================
2. APPLICATION LAYER (RELYING PARTIES / CLIENTS)
===================================================================================================
      ┌───────────────────────────────┼───────────────────────────────┐
      │                               │                               │
      v                               v                               v
+──────────────────────────+    +──────────────────────────+    +──────────────────────────+
| Web App A (E-Commerce)   |    | Web App B (Internal HR)  |    | Native Mobile App (iOS)  |
| - Confidential Client    |    | - Confidential Client    |    | - Public Client (PKCE)   |
| - Stores Session Cookie  |    | - Stores Session Cookie  |    | - Secure Keyring Store   |
+─────────────┬────────────+    +─────────────┬────────────+    +─────────────┬────────────+
              │                               │                               │
              │ Bearer Access Token (JWT)     │ Bearer Access Token (JWT)     │ Bearer Access Token (JWT)
              v                               v                               v
===================================================================================================
3. PROTECTED RESOURCE LAYER (MICROSERVICES / API GATEWAY)
===================================================================================================
+─────────────────────────────────────────────────────────────────────────────────────────────────+
| API GATEWAY LAYER                                                                               |
|                                                                                                 |
|  1. Extract Bearer Access Token from HTTP Authorization Header                                  |
|  2. Validate Signature against cached IdP Public Keys (JWKS)                                    |
|  3. Validate Claims (`iss`, `aud`, `exp`, `scope`)                                              |
|  4. Enforce Rate Limits & Forward Sanitized Context (`X-User-Id`, `X-Scopes`)                   |
+──────────────────────────────────────────────┬──────────────────────────────────────────────────+
                                               │
                                               │ Internal Service Mesh Execution
                                               v
                        ┌──────────────────────┴──────────────────────┐
                        │                                             │
                        v                                             v
            [ Order Microservice ]                       [ HR Data Microservice ]
```

---

### 6. Interview Checklist:

When pitching SSO and OAuth 2.0 in a system design interview:

- **Isolate AuthN vs. AuthZ Mechanics**: Clarify immediately that OAuth 2.0 handles delegated authorization(Access Tokens), while OIDC adds an identity layer on top to handle authentication and SSO (ID Tokens).

- **Default to PKCE Everywhere**: Always specify the Authorization Code Flow with PKCE for modern authentication flows, explaining how it eliminates code interception attacks for both public (SPA/mobile) and confidential (server-side) clients.

- **Proactively Explain Token Theft Defenses**: Demonstrate senior security depth by discussing Refresh Token Rotation (RTR) to mitigate compromised refresh tokens, and DPoP (Demonstrating Proof-of-Possession) or mTLS to prevent access token replay attacks.

- **Highlight Validation Efficiency**: Explain that resource servers validate incoming JWT Access Tokens statelessly using cached public keys from the IdP’s JWKS endpoint, avoiding high-latency network round-trips to the Auth Server on every API invocation.
