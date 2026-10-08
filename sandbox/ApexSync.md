## Apex Sync: High-concurrency ticketing with zero booking conflicts.

Description: A production-grade, high-concurrency event reservation system engineered to handle high-volume flash sales. It features real-time distributed seat locking, dynamic pricing, and strict role-based access control built on enterprise-standard cloud infrastructure.

## Project Overview:

The ideal project to showcase high-level full-stack mastery is FlashReserve: A High-Concurrency Event Ticketing & Dynamic Pricing Platform.

This project solves the classic "Flash Sale" problem: thousands of concurrent users trying to buy limited seats simultaneously. It forces you to implement complex system design patterns, atomic database operations, real-time calculations, and multi-tier security—all using 100% free-tier software and tools.

### 1. Core Concept & Mathematical Calculations:

The platform allows organizers to host limited-capacity events with dynamically priced seating tiers.

#### Complex Logic & Calculations:

Real-time Dynamic Pricing Engine: Seat prices update every 10 seconds using a dynamic demand curve:

$$\text{Price} = \text{BasePrice} \times \left(1 + \alpha \cdot \frac{\text{Velocity}_{5\text{m}}}{\text{Capacity}_{\text{total}}}\right) \times e^{\beta \cdot (1 - \frac{\text{Seats}_{\text{remaining}}}{\text{Seats}_{\text{total}}})}$$

Calculates real-time ticket purchase velocity ($\text{Velocity}_{5\text{m}}$) over rolling 5-minute windows using Redis Sliding Window logs.

- **Atomic Seat Hold Duration**: When a user selects a seat, it enters a HELD state for exactly 10 minutes. Redis key expiration (TTL) combined with pub/sub notifications releases unpurchased seats automatically.

- **Double-Entry Financial Ledger Engine**: Implements double-entry bookkeeping tables (accounts, journal_entries, postings) in PostgreSQL to calculate user refunds, platform fees, taxes, and organizer payouts cleanly without floating-point rounding errors (using BigDecimal).

---

### 2. Tech Stack & 100% Free Deployment Matrix:

- **Frontend**: `Next.js` (App Router), `React`, `TSX`, `Tailwind`, `Shadcn UI` - Vercel(Hobby Plan)
- SSR for event landing pages, Client Components with Optimistic UI for seat selection, WebSockets/SSE for live seat maps.

- **Backend API**: `Java 21`, `Spring Boot 3`, `Spring` `Security`, `JPA/Hibernate` - Render or Koyeb(Free Tier)
- RESTful API + WebSockets. JVM optimized with -Xmx350m -Xss256k flags to fit inside 512MB RAM limits.

- **Database**: `PostgreSQL 16` - Aiven or Neon (Free Tier)
- Relational SQL schema, database indexes, Flyway migration scripts, row-level locks (SELECT ... FOR UPDATE).

- **Cache & Queue**: `Redis 7` - Upstash Redis (10k req/day free)
- Distributed locking (Redisson/Lua), sliding-window rate limiting, seat-lock TTLs, event-driven queues.

- **Local Dev**: `Docker` & `Docker Compose` - Local Computer
- Entire environment (Spring Boot, Postgres, Redis, Mailpit) runs locally in a single docker-compose.yml.

---

### 3. Core System Design & Engineering Patterns:

#### A. High Throughput & Concurrency Control:

- **Distributed Locks (Redis + Redisson / Lua Scripts)**: Prevents double-booking when 1,000 users click the exact same seat at the same second. Locks are acquired in Redis at the seat level before hitting the SQL database.
- **Database Optimistic & Pessimistic Locking**: Uses @Version columns for optimistic inventory updates and Pessimistic Write Locks for financial transactions.
- **Transactional Outbox Pattern**: Guarantees that when a seat is reserved in PostgreSQL, an asynchronous confirmation event (email/push notification) is written to an outbox table in the same DB transaction before being processed asynchronously by a Redis worker.

#### B. Security, Authentication & Authorization:

- **Authentication**: Stateless JWT Access Tokens (15-min expiry) paired with Refresh Tokens stored in HttpOnly, SameSite, Secure Cookies to guard against XSS and CSRF.
- **Authorization (RBAC & ABAC)**: Spring Security method security (@PreAuthorize).
- **Roles**: ROLE_ADMIN, ROLE_ORGANIZER, ROLE_CUSTOMER.
- **Attribute-Based Access**: Organizers can only edit events where event.organizerId == authentication.principal.id.

#### API Protection & OWASP Defenses:

- **Redis Token Bucket Rate Limiter**: Limits users to 10 requests/second per IP to mitigate bot attacks during flash sales.
- **Input Sanitization & Validation**: jakarta.validation annotations (@NotBlank, @Pattern, @Size) on all API requests.

#### C. Resilience & Observability:

- Circuit Breakers & Retries: Resilience4j integrated into Spring Boot for external service calls (e.g., payment webhooks).
- Idempotency Keys: Every checkout API request requires an X-Idempotency-Key stored in Redis to prevent duplicate charges from double-clicking or network retries.
- Structured Logging & Metrics: Actuator endpoints emitting Prometheus metrics parsed by Grafana in local Docker.

---

### 4. Database Schema Design (SQL)

Your PostgreSQL database must feature cleanly normalized schemas and spatial/composite indexes:

- users (id, email, password_hash, role, created_at)
- events (id, title, venue_id, base_price, start_time, status)
- seats (id, venue_id, section, row_num, seat_num) — Unique constraint on (venue_id, section, row_num, seat_num).
- reservations (id, user_id, event_id, seat_id, status, expires_at) — Statuses: HELD, CONFIRMED, EXPIRED, CANCELLED.
- ledger_entries (id, reservation_id, debit_account, credit_account, amount, created_at)

---

### 5. Step-by-Step Implementation Roadmap

#### Phase 1: Local Setup & Docker Compose

- Write docker-compose.yml with PostgreSQL, Redis, and Adminer.
- Initialize Spring Boot 3 with Java 21, Flyway migration scripts, and Spring Data JPA.

#### Phase 2: Authentication & RBAC Engine

- Build JWT authentication pipeline with Spring Security filter chain.
- Configure Next.js Middleware to guard public vs protected /dashboard and /admin routes.

#### Phase 3: Core Logic & Seat Reservation Engine

- Implement the Dynamic Price Calculation algorithm in Java.
- Write Lua scripts in Redis to handle atomic seat locking (GETSET / TTL).

#### Phase 4: Next.js Interactive Seat Map UI

- Create an interactive SVG seat layout in Next.js using React state.
- Integrate Server-Sent Events (SSE) from Spring Boot so seats turn red in real-time for all viewers when reserved by someone else.

#### Phase 5: Rate Limiting, Outbox & Failover

- Implement Spring Aspect (@Aspect) for custom @RateLimit annotations backed by Redis.
- Implement the Transactional Outbox worker using @Scheduled or Redis Streams.

#### Phase 6: Cloud Deployment (100% Free)

- Deploy PostgreSQL to Aiven/Neon and Redis to Upstash.
- Containerize Spring Boot with Docker, optimize JVM flags for low memory, and deploy to Render.
- Deploy Next.js to Vercel and map environment variables.

---

## Project Flow:

### 1. The End-to-End User Flow (How It Works):

#### The Organizer Flow (Setup):

- Login/Register: You (the developer acting as an admin/organizer) log into the platform.
- Create Event: You fill out a form: "Summer Music Fest", 500 capacity, Base Price: $50.
- Generate Venue: You define a seating layout (e.g., VIP section, General Admission). The backend generates 500 database rows in the seats table tied to this event.

#### The Customer Flow (The Flash Sale):

- **Discovery**: A user lands on the Next.js homepage and clicks "Summer Music Fest".
- **Real-Time Seat Map**: They see a grid of seats. Some are grey (sold), some are orange (held by others right now), and some are green (available).
- **The Lock (The Hard Part)**: The user clicks seat A12.
- \*\*The Next.js frontend calls your Java API.
- **Your Java API asks Redis**: "Is A12 available?"
- \*\*Redis says "Yes" and locks it for exactly 10 minutes.
- \*\*A WebSocket event fires, and seat A12 instantly turns orange for every other user looking at the screen.
- **Checkout**: The user has 10 minutes to complete a mock payment form.
- **If they pay**: The database updates the seat to SOLD.
- **If 10 minutes pass**: Redis automatically expires the lock. A WebSocket event fires, and the seat turns green again for everyone else.

---

### 2. What Your UI Will Look Like (Next.js):

- Your Next.js frontend will be broken down into these core screens:
- Public Landing Page (/): A list of upcoming events with their dynamic "Current Price" and "Tickets Remaining."
- Event Details & Seat Map (/event/[id]):
- A live, interactive grid of seats.
- A countdown timer at the top (e.g., "09:59 to complete purchase").
- Checkout Page (/checkout): A simple form to collect name/email and a "Pay Now" button (no real payment gateway needed, just a simulated success).
- Organizer Dashboard (/admin): A private route where you can add new events and view sales charts.

---

### 3. The API Design (Java & Spring Boot):

Your backend will expose these RESTful endpoints. Use Postman to test these before you even touch Next.js.

- `POST`: **/api/auth/login** - Authenticates users/admins and returns a JWT.
- `POST`: **/api/events** - (Admin Only) Creates a new event and generates seats.
- `GET`: **/api/events/{id}** - Returns event details and current dynamic price.
- `GET`: **/api/events/{id}/seats** - Returns the status of all seats for the UI grid.
- `POST`: **/api/seats/{id}/lock** - Tries to acquire a 10-minute Redis lock on a seat.
- `POST`: **/api/checkout** - Validates the Redis lock, marks seat SOLD in DB.

---

### 4. Your Developer Environment Setup:

You will use three main tools locally on your computer. All of them are 100% free.

- **IntelliJ IDEA Community Edition**: This is where you will write your Java/Spring Boot code. It has excellent support for Maven/Gradle and Java debugging.
- **VS Code**: This is where you will write your Next.js, React, and TypeScript code.

#### Docker Desktop & Docker Compose:

- What it is: Docker creates mini virtual machines (containers) on your laptop.
- Why you need it: Instead of manually downloading and installing PostgreSQL and Redis on your Windows/Mac (which is messy), you write one file called docker-compose.yml. You type docker-compose up, and magically, a Postgres database and a Redis server start running in the background, ready for your Java app to connect to them.

---

### 5. Execution Roadmap: Where to Start Today:

Do not try to build everything at once. Build strictly in this order:

- 1.Set up the Infrastructure:docker-compose.yml.
  Create a folder for your project. Write a docker-compose.yml file that pulls the official PostgreSQL and Redis images. Run `docker-compose up -d`. You now have a database and a cache running locally.

- 2.Initialize the Spring Boot Backend:IntelliJ IDEA.
  Go to start.spring.io. Generate a Java 21 / Spring Boot 3 project with Spring Web, Spring Data JPA, and PostgreSQL Driver. Open it in IntelliJ. Configure application.properties to connect to your local Docker Postgres.

- 3.Design the Database Schema:JPA Entities.
  Write your Java Entity classes (User, Event, Seat, Reservation). Let Spring Data JPA (Hibernate) auto-generate the tables in Postgres.

- 4.Build the Basic APIs:REST Controllers.
  Write the endpoints to create an event, list events, and list seats. Test them in Postman. At this point, you have a working traditional backend.

- 5.Implement Redis & Locking:The hard part.
  Add Spring Data Redis. When the /lock endpoint is hit, write logic to store a key in Redis with a 10-minute time-to-live (TTL). If the key already exists, return a 409 Conflict (seat is taken).

- 6.Build the Next.js Frontend:VS Code.
  Initialize a Next.js App Router project. Build the landing page to fetch events from your Java API. Build the seat map component. Connect clicking a seat to your /lock API.

---

## Updated Project Flow

#### The Three-Tier Actor Flow:

To build a true production system, you need Role-Based Access Control (RBAC). The application will behave completely differently depending on who logs in.

### 1. The Customer Flow (The Buyer)

- **Discovery**: Lands on the public homepage. Browses a paginated list of upcoming events.
- **Live Interaction**: Clicks an event and sees a real-time, color-coded seat map (Green = Available, Orange = Held, Grey = Sold).
- **The Flash Lock**: Clicks a green seat. The system instantly locks it in Redis for 10 minutes and broadcasts an event via WebSockets so the seat turns orange for everyone else.
- **Checkout & Fulfillment**: Completes a mock payment form within the 10-minute countdown. The database finalizes the transaction, writes a ledger entry, and issues a digital ticket. If the timer hits zero, the lock expires and the seat becomes available again.

---

### 2. The Organizer Flow (The Event Creator):

- **Onboarding**: Registers an account and applies for the ROLE_ORGANIZER permission.
- **Event Generation**: Uses the Organizer Dashboard to create a new event. They define the venue layout (e.g., 10 rows of 20 seats), base pricing, and the exact date/time the "Flash Sale" unlocks.
- **Siloed Analytics**: Views a live dashboard showing only their events. They can watch seats turn from available to sold in real-time, track their specific revenue, and manage ticket cancellations/refunds for their customers.

---

### 3. The Developer / Super Admin Flow (Your Bird's-Eye View):

- **System God-Mode**: You log in with ROLE_ADMIN. You bypass all standard user interfaces and enter the Admin Control Center.
- **Platform Observability**: You see the health of the entire system. Instead of just "tickets sold," you monitor technical metrics: active Redis locks, database query performance, and memory usage.
- **Global Management**: You can see every organizer, every event, and every user. You have the power to approve or ban organizers, force-cancel stuck reservations, and view an audit log of all system actions.
- **Financial Overview**: You view the total volume of money moving through the platform, tracking the "platform fees" VeloTix collects from the organizers.

#### Restructured API Design (By Role):

Your backend will use Spring Security to intercept requests and check the user's role before allowing access.

- `POST`: **/api/auth/login** - PUBLIC - Returns JWT with embedded roles.
- `GET`: **/api/events** - PUBLIC - Lists active, upcoming events.
- `GET`: **/api/events/{id}/seats** - PUBLIC - Returns the live availability of seats.
- `POST`: **/api/checkout/lock** - CUSTOMER - Acquires the 10-minute Redis distributed lock.
- `POST`: **/api/checkout/pay** - CUSTOMER - Validates lock and finalizes the DB transaction.
- `POST`: **/api/organizer/events** - ORGANIZER - Creates a new event and generates DB seat rows.
- `GET`: **/api/organizer/stats** - ORGANIZER - Returns revenue/sales data for their events only.
- `GET`: **/api/admin/system/health** - ADMIN - Returns Redis lock counts, active DB connections.
- `GET`: **/api/admin/users** - ADMIN - Lists all platform users with ban/suspend options.
- `GET`: **/api/admin/revenue** - ADMIN - Returns global platform transaction volume and fees.

---
 
## TimeLine

At ~100 total engineering hours of active development, debugging, and cloud deployment, here is how your timeline projects based on your weekend commitment:

### Phase 1: Environment & Foundation (Weekends 1–2 | ~16 Hours)
Weekend 1: Set up docker-compose.yml (PostgreSQL & Redis). Initialize Spring Boot 3 with Java 21, Flyway migrations, and JPA entities (User, Event, Seat, Reservation).

Weekend 2: Initialize Next.js 14 App Router (TSX, Tailwind, Shadcn UI). Configure Spring Security JWT authentication pipeline for CUSTOMER, ORGANIZER, and ADMIN.

### Phase 2: Core Backend & Organizer Engine (Weekends 3–4 | ~16 Hours)
Weekend 3: Build Organizer event creation APIs and seat generator service (populating row/seat layouts in PostgreSQL).

Weekend 4: Build the Dynamic Pricing algorithm engine and test event/seat list REST endpoints via Postman.

### Phase 3: High-Concurrency & Redis Locking (Weekends 5–6 | ~16 Hours)
Weekend 5: Implement Redis distributed locks (Redisson/Lua scripts) for the 10-minute seat lock with TTL. Write unit/integration tests simulating concurrent lock requests.

Weekend 6: Set up Server-Sent Events (SSE) / WebSockets in Spring Boot to broadcast seat status updates when a lock is acquired or expired.

### Phase 4: Customer Frontend & Interactive Map (Weekends 7–9 | ~24 Hours)
Weekend 7: Build Next.js landing page (/) and event detail views (/event/[id]).

Weekend 8: Build the SVG/Grid interactive seat map with real-time SSE updates (seats dynamically changing colors across browsers).

Weekend 9: Implement the checkout timer, mock payment endpoint, and transactional ledger update in Spring Boot.

### Phase 5: Admin / Developer Bird's-Eye Dashboard (Weekends 10–11 | ~16 Hours)
Weekend 10: Build the Admin Control Center API (/api/admin/system/health) exposing active Redis locks, DB metrics, and total platform revenue.

Weekend 11: Build the Admin UI in Next.js to monitor live platform traffic, manage users, and inspect system health.

### Phase 6: Cloud Deployment & Final Polish (Weekend 12–13 | ~12 Hours)
Weekend 12: Deploy PostgreSQL (Neon/Aiven), Redis (Upstash), Spring Boot API (Render/Koyeb), and Next.js (Vercel). Configure CORS and production environment variables.

Weekend 13: End-to-end testing on live URLs, README documentation writing, and architectural diagram creation for your portfolio.