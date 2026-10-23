## CORS (Cross-Origin Resource Sharing)

### 1. High-Level Overview (The "Why" & "What"):

#### Real-World Analogy:

Imagine a hotel guest staying at the Grand Hotel (Origin A). The guest orders room service, but asks for pizza from an independent pizzeria down the street (Pizza Express - Origin B).

- **The hotel’s front desk has a strict security policy**: by default, outside delivery drivers are blocked from entering hotel hallways to protect guest privacy (Same-Origin Policy). However, if the hotel calls Pizza Express and Pizza Express explicitly tells the front desk, "Yes, we authorize deliveries to guests staying at Grand Hotel"(CORS headers), the front desk allows the delivery driver up to the room.

- Crucially, the guest's browser is the front desk security guard—it enforces the rules on behalf of the user,requiring explicit permission from the external server before letting the user's application read the incoming payload.

### The Problem It Solves:

- To protect users from malicious websites, web browsers enforce the Same-Origin Policy (SOP). SOP prevents scripts running on [https://attacker.com](https://attacker.com) from reading sensitive data returned by [https://yourbank.com](https://yourbank.com).

- However, modern web architectures rely heavily on cross-origin resource fetching (e.g., a web app hosted on [https://app.company.com](https://app.company.com) querying an API hosted on [https://api.company.com](https://api.company.com) or a third-party microservice).

- CORS (Cross-Origin Resource Sharing) is a W3C standard HTTP-header-based mechanism that allows servers to selectively bypass browser SOP restrictions, explicitly declaring which external origins are permitted to access their protected data.

---

### 2. The Basics (Scratch Level):

#### What Defines an "Origin"?

An origin is defined strictly by the tuple: Protocol + Domain + Port. If any of these three components differ,the browser treats the request as Cross-Origin.

| URL A                                                      | `URL B`                                                | `Same Origin?` | `Reason`                         |
| ---------------------------------------------------------- | ------------------------------------------------------ | -------------- | -------------------------------- |
| **[https://example.com/page1](https://example.com/page1)** | [https://example.com/page2](https://example.com/page2) | Yes            | Protocol, Domain, Port match.    |
| **[http://example.com](http://example.com)**               | [https://example.com](https://example.com)             | No             | Scheme mismatch (http vs https). |
| **[https://example.com](https://example.com)**             | [https://api.example.com](https://api.example.com)     | No             | Subdomain mismatch.              |
| **[https://example.com:8080](https://example.com:8080)**   | [https://example.com:9000](https://example.com:9000)   | No             | Port mismatch (8080 vs 9000).    |

#### Core CORS Response Headers:

| HTTP Header                          | `Purpose`                                                                                      | `Example Value`                                          |
| ------------------------------------ | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| **Access-Control-Allow-Origin**      | Specifies which origin(s) are allowed to read the response.                                    | [https://app.company.com](https://app.company.com) or \* |
| **Access-Control-Allow-Methods**     | Lists HTTP methods allowed during cross-origin calls.                                          | GET, POST, PUT, DELETE, OPTIONS                          |
| **Access-Control-Allow-Headers**     | Lists allowed HTTP request headers sent by the client.                                         | Content-Type, Authorization, X-Api-Key                   |
| **Access-Control-Allow-Credentials** | Indicates whether cookies, Authorization headers, or TLS client certs can be exposed.          | true                                                     |
| **Access-Control-Max-Age**           | Defines how long (in seconds) the results of a preflight request can be cached by the browser. | 86400 (24 hours)                                         |

---

### 3. Deep Dive & Architecture (Mid Level):

#### 1. Simple Requests vs. Preflighted Requests:

Browsers split CORS requests into two distinct execution pathways based on the risk profile of the HTTP call:

```
                         [ Incoming Cross-Origin Fetch ]
                                        │
                ┌───────────────────────┴───────────────────────┐
                │                                               │
    Is it a "Simple Request"?                       NOT a Simple Request
   (GET/HEAD/POST, Standard Headers,                (JSON body, custom headers like
    form-urlencoded/multipart/text)                  Authorization, PUT/DELETE/PATCH)
                │                                               │
                v                                               v
   [ Direct HTTP Execution ]                      [ Preflight Check Required ]
 - Browser sends request immediately             - Browser fires OPTIONS request first
 - Server responds with data + CORS headers      - Server responds with 204 + Allowed Rules
 - Browser checks CORS -> Delivers or Blocks     - If allowed -> Browser fires actual request
```

- `Pathway A`: **Simple Requests**
- A request is classified as "Simple" if it meets all of the following criteria:
- **Uses method**: GET, HEAD, or POST.
- Contains only CORS-safelisted headers (Accept, Accept-Language, Content-Language, Content-Type).
- Content-Type is limited to: application/x-www-form-urlencoded, multipart/form-data, or text/plain.
- **Execution**: The browser sends the request immediately with an Origin: [https://app.com](https://app.com)header. The server processes the request and responds. The browser checks if Access-Control-Allow-Originmatches [https://app.com](https://app.com). If it matches, the browser passes the payload to JS code; otherwise, the browser throws a DOM error and hides the response payload.

- `Pathway B`: **Preflighted Requests (OPTIONS)**
- If a request uses methods like PUT, DELETE, PATCH, custom headers (e.g., Authorization, X-Transaction-ID),or sets Content-Type: application/json, the browser must perform a preflight check before making the actual request.

- **Preflight Step**: Browser issues an OPTIONS request to the server containing:
- **Origin**: [https://app.com](https://app.com)
- **Access-Control-Request-Method**: DELETE
- **Access-Control-Request-Headers**: authorization, content-type
- **Server Approval**: If approved, server returns 204 No Content with appropriate Access-Control-Allow-\*headers.
- **Actual Request**: Browser fires the real DELETE request.

#### 2. Credentialed Requests (Access-Control-Allow-Credentials):

When client JavaScript executes fetch(url, { credentials: 'include' }) or sets XMLHttpRequest.withCredentials = true, the browser includes cookies, HTTP basic authentication, and client TLS certificates in cross-origin requests.

- Strict CORS Rule: If Access-Control-Allow-Credentials: true is set, Access-Control-Allow-OriginCANNOT be set to wildcard (\*). The server must explicitly specify the exact requesting origin (e.g.,Access-Control-Allow-Origin: [https://app.company.com](https://app.company.com)).
- If \* is returned with credentials, the browser blocks the response automatically.

---

### 4. Advanced Strategies & Trade-offs (Pro Level):

#### Critical Misconfigurations & Security Vulnerabilities:

CORS misconfigurations are a leading cause of Cross-Origin Data Leakage.

#### 1. Blind Origin Reflection (The "Dynamic Wildcard" Anti-Pattern)

Developers attempting to handle multiple subdomains often write insecure code that dynamically mirrors the incoming Origin header in the server response:

```Python
# INSECURE SERVER CODE
origin = request.headers.get('Origin')
if origin:
   response.headers['Access-Control-Allow-Origin'] = origin  # Bypasses wildcard restrictions!
   response.headers['Access-Control-Allow-Credentials'] = 'true'
```

- **Security Exploit**: Any malicious site ([https://evil.com](https://evil.com)) can make a credentialed request to your API. The server blindly reflects [https://evil.com](https://evil.com) as an allowed origin, allowing the attacker to read authenticated user cookies, private data, and API responses.

#### 2. Trusting Origin: null

Requests initiated from sandboxed `<iframe>` elements, local HTML files (file://), or redirected requests omit origin details and send Origin: null.

- **Security Exploit**: If a server sets Access-Control-Allow-Origin: null, an attacker can host an exploit inside a sandboxed iframe on their malicious website, triggering requests with Origin: null to extract sensitive API data.

#### 3. Wildcard Subdomain Regex Flaws

Attempts to trust all internal subdomains using weak regex (e.g., matching .\*company.com) lead to vulnerabilities:

- An attacker registers [https://attackercompany.com](https://attackercompany.com) or [https://company.com.attacker.com](https://company.com.attacker.com). Weak regexes match these malicious domains, exposing corporate APIs.

#### Performance Optimization: Preflight Latency Mitigation:

Preflight OPTIONS requests double network round-trip time (RTT) for every API call, severely degrading user experience over high-latency networks (e.g., mobile networks).

```
WITHOUT PREFLIGHT CACHING (2-RTT per API call)
Client ─── OPTIONS ───► Gateway ───► 204 No Content
Client ─── POST ──────► Gateway ───► 200 OK Payload

WITH PREFLIGHT CACHING (1-RTT per API call during TTL)
Client ─── POST ──────► Gateway ───► 200 OK Payload
```

- **Mitigation**: Server must return Access-Control-Max-Age: 86400 in preflight responses to instruct the browser to cache the preflight decision locally.
- **Browser Quirk**: Modern browsers cap the maximum allowed Max-Age to prevent stale policies (e.g.,Chrome caps Access-Control-Max-Age at 2 hours / 7200s, while Firefox allows up to 24 hours / 86400s).

#### Architectural Placement: API Gateway Level CORS

- Handling CORS logic directly inside application microservices causes code duplication, maintenance friction,and inconsistent security policies.

- **Best Practice**: Offload CORS enforcement to the API Gateway / Edge Reverse Proxy Layer (e.g.,Kong, NGINX, AWS API Gateway, Envoy).
- The Gateway handles all incoming OPTIONS preflight requests statelessly at the edge without forwarding them to downstream microservices, reducing compute load and back-end latency.

---

### 5. Text-Based Architecture Diagram:

**Full Preflighted CORS Protocol Exchange Flow**

```
===================================================================================================
1. PREFLIGHT CHECK PHASE (OPTIONS Request)
===================================================================================================
[ Browser (App: https://app.domain.com) ]                     [ API Gateway / Server ]
 │                                                                 │
 │ HTTP OPTIONS /v1/orders                                         │
 │ Origin: https://app.domain.com                                  │
 │ Access-Control-Request-Method: DELETE                           │
 │ Access-Control-Request-Headers: authorization, content-type     │
 ├────────────────────────────────────────────────────────────────►│
 │                                                                 │ Evaluates Policy:
 │                                                                 │ - Is Origin allowed? YES
 │                                                                 │ - Is Method allowed? YES
 │                                                                 │ - Are Headers allowed? YES
 │                                                                 │
 │ HTTP 204 No Content                                             │
 │ Access-Control-Allow-Origin: https://app.domain.com             │
 │ Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS        │
 │ Access-Control-Allow-Headers: authorization, content-type       │
 │ Access-Control-Allow-Credentials: true                          │
 │ Access-Control-Max-Age: 7200                                    │
 │◄────────────────────────────────────────────────────────────────┤
 │                                                                 │
 │ (Caches Preflight Decision in Browser for 7200 seconds)         │

===================================================================================================
2. ACTUAL REQUEST PHASE (DELETE Request)
===================================================================================================
 │                                                                 │
 │ HTTP DELETE /v1/orders/10294                                    │
 │ Origin: https://app.domain.com                                  │
 │ Authorization: Bearer <JWT_TOKEN>                               │
 │ Cookie: session_id=xyz123                                       │
 ├────────────────────────────────────────────────────────────────►│
 │                                                                 │ Executes Business Logic
 │                                                                 │ Deletes Order Record
 │                                                                 │
 │ HTTP 200 OK                                                     │
 │ Access-Control-Allow-Origin: https://app.domain.com             │
 │ Access-Control-Allow-Credentials: true                          │
 │ Payload: {"status": "success", "deleted_id": 10294}             │
 │◄────────────────────────────────────────────────────────────────┤
 │                                                                 │
 │ (Browser verifies headers, passes JSON payload to JavaScript)   │
 v                                                                 v
```

---

### 6. Interview Checklist:

When pitching CORS mechanics in a system design interview:

- **Clarify Enforcement Boundary**: State clearly that CORS is enforced by the client browser, not the server. The server processes the request; the browser blocks the frontend code from reading the response if CORS headers fail.

- **Explain Simple vs. Preflighted Flows**: Detail why OPTIONS preflight checks occur—highlighting that custom headers (Authorization), methods (PUT/DELETE), or application/json bodies trigger preflight checks to prevent non-idempotent server state changes.

- **Identify Security Antipatterns**: Demonstrate security depth by warning against Blind Origin Reflection(reflecting the incoming Origin header dynamically alongside Access-Control-Allow-Credentials: true) and trusting Origin: null.

- **Propose Edge Gateway Offloading**: Recommend managing CORS policies at the API Gateway layer to handle preflights statelessly at the network edge while optimizing latency using Access-Control-Max-Agecaching.
