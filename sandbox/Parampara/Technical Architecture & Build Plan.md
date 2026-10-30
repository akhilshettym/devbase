# Parampara — Technical Architecture & Build Plan

*Version 1.0 · Companion to the Feature Blueprint · Stack choices, architecture and build order*

## 1. Quick Answers to Your Doubts

1. **How many microservices?** None to start. Launch as a **modular monolith**: one backend application with ten strictly separated modules, plus one background worker and a separate CMS. The module boundaries are the same ones a microservice split would use, so services can be extracted later without a rewrite. If the client expects microservices, this is the honest and defensible path (Section 2).
2. **Frontend and Redux:** Next.js + TailwindCSS + Redux Toolkit, agreed. Use RTK Query alongside it for server data (Section 8).
3. **“Switch PostgreSQL to SQL”:** PostgreSQL *is* a SQL database, so I assume you meant **MySQL**. Either works. My recommendation is PostgreSQL, mainly because its JSON columns and built-in full-text search let us drop MongoDB entirely. If you are more comfortable with MySQL, use MySQL 8; nothing in this plan breaks.
4. **API gateway:** plain **REST** with an OpenAPI spec. GraphQL is not needed. A separate gateway product is unnecessary at launch; the CDN or load balancer plus the API’s own routing does that job.
5. **Express vs NestJS vs Next.js for the backend:** **NestJS** (TypeScript). It runs on Express underneath, so what you know carries over, and its modules, guards and validation fit a multi-role marketplace. Do not use Next.js as the main backend. Plain Express is fine only if you commit to the same folder and module discipline.
6. **Complete architecture:** Sections 3–10, with the system diagram shown in the chat.
7. **Where to start:** Section 11 — foundations, then the catalogue and storefront, then identity, then the first complete purchase.

## 2. Approach: Modular Monolith, Microservice-Ready

**Why not microservices on day one**

- Parampara’s core rules cross boundaries: a one-of-one painting, its 15-minute hold, its payment and its order status must change together. Across separate services this becomes distributed transactions, a hard problem with no business payoff at this scale.
- A catalogue of hundreds or a few thousand paintings does not need independent scaling.
- Every extra service adds deployment, monitoring, networking and debugging work, which slows both the demo and the launch.

**What we build instead**

- One **API** application (NestJS) split into modules, deployed as a single unit.
- One **worker** process (same codebase) that runs background jobs.
- One **CMS** (separate app) for banners and content.
- Managed data services: SQL database, Redis, search and object storage.

**Rules that keep it extractable**

1. Each module owns its tables; no other module reads or writes them directly.
2. Modules talk through public service interfaces or domain events, never by importing each other’s internals.
3. No cross-module database joins; fetch by ID and combine in code.
4. Events such as OrderPaid are published in-process now and can move to a message broker later.
5. Every module has its own controllers, DTOs and tests.

**When to extract a service:** when it needs to scale on its own, has a different release rhythm or team, or its failure should be isolated. Likely order: Notifications and Worker (already a separate process), media processing, search indexing, payments, classes.

**Mapping from the generic six services:** Identity → Identity & Access; Catalog & Inventory → Catalog; Cart & Checkout → Cart & Checkout; Order → Orders & Fulfilment; Payment & Billing → Payments & Billing; Notification → Notifications. We add Artist Marketplace, Commissions and Classes for Parampara’s own features.

## 3. Final Stack: What to Use for What

**Frontend**

- **Next.js (React, TypeScript, App Router)** – server rendering and incremental regeneration for SEO and speed.
- **TailwindCSS** with design tokens (cream, muted red, serif type) defined once in the theme.
- **Redux Toolkit + RTK Query**; React Hook Form + Zod for forms; next-intl for future languages.
- **Vercel** (or AWS Amplify) to host the web app.

**Backend**

- **Node.js + NestJS (TypeScript)** on the Express adapter.
- **Prisma** as ORM and migration tool (works with both PostgreSQL and MySQL).
- Validation with class-validator or Zod; API docs with Swagger/OpenAPI.
- **BullMQ** (on Redis) for background jobs and scheduled tasks.

**Data**

- **PostgreSQL** (managed) for users, roles, catalogue, orders, payments, payouts, commissions and classes.
- **Redis** for guest carts, painting and seat holds with expiry, caching, rate limiting, job queues and idempotency keys.
- **Meilisearch** (or Typesense) for search: typo tolerance, autocomplete and facet filters at this catalogue size without the weight of Elasticsearch. Algolia if you prefer fully managed and accept the cost.
- **Object storage** (AWS S3 or Cloudflare R2) behind a CDN, with a public bucket for images and a private bucket for KYC documents.

**Identity**

- A managed provider (Firebase Authentication or Auth0) for Google, email and mobile OTP, with roles and permissions stored in our own database. Cognito is heavier to work with; choose it only if you are fully on AWS. Check OTP SMS costs for India before deciding.

**Payments and shipping**

- **Razorpay** (or Cashfree) for UPI, cards, net banking, wallets, EMI, payment links (ideal for balance payments) and split transfers for seller payouts. Confirm marketplace eligibility and fees with the provider. Stripe and PayPal in the generic stack are not the natural choice for UPI-first Indian checkout.
- A shipping aggregator (Shiprocket, Delhivery or similar) for rates, labels and tracking; verify how they handle fragile art and insurance.

**Communication**

- Email: Amazon SES, Resend or Postmark. SMS and OTP: an Indian provider such as MSG91 (DLT registration is required, so start early). WhatsApp: Business API through a provider such as Gupshup, Interakt or Twilio.

**CMS**

- **Strapi** (self-hosted, Node) or Payload CMS; Sanity is the quickest hosted option for a demo. Publishing triggers a webhook so Next.js refreshes the affected pages with no deployment. Check that scheduled publishing exists on the plan you choose.

**Hosting**

- Web on Vercel. API, worker, managed PostgreSQL, Redis and storage in AWS Mumbai (ap-south-1) for lower latency to Indian users. Docker containers on ECS Fargate, or a single well-sized VM at the start. Cloudflare or CloudFront for CDN and WAF.

**Delivery and quality**

- GitHub Actions, Docker, dev/staging/production environments, Sentry for errors, structured logs (Pino), uptime monitoring, Playwright for end-to-end tests and Jest or Vitest for unit tests.

**Dropped from the generic stack, and why**

- **MongoDB:** painting attributes are uniform (size, surface, art form, theme); the few flexible extras fit in a JSON column. A single SQL database is not a bottleneck at this scale.
- **Pinecone or any vector DB:** “similar paintings” works from art form, artist, theme and price band; pgvector can be added later.
- **Kafka or RabbitMQ:** overkill now; BullMQ plus in-process events cover launch.
- **Elasticsearch:** heavy to operate; Meilisearch covers our needs.
- **GraphQL, Go, a standalone API gateway:** added complexity without a present need.

## 4. Backend Modules

1. **Identity & Access** – sign-in via the provider, profile, roles (Collector, Artist Partner, Instructor, staff roles), permissions, addresses, consent records. *Owns:* users, user\_roles, addresses.
2. **Catalog** – art forms, artists, paintings, media, listing status workflow, collections, reviews and ratings. *Owns:* art\_forms, artists, paintings, painting\_media, collections, reviews.
3. **Search** – index and query adapter, kept in sync by Catalog events. *Owns:* the search index only.
4. **Cart & Checkout** – carts, painting holds, promo codes, tax and delivery calculation, checkout session. *Owns:* carts, cart\_items, promotions.
5. **Orders & Fulfilment** – orders and sub-orders per artist, status flows, shipments, returns and damage claims. *Owns:* orders, order\_items, shipments, claims.
6. **Payments & Billing** – gateway integration, advance and balance payments, refunds, invoices, payout ledger. *Owns:* payments, refunds, invoices, ledger\_entries.
7. **Artist Marketplace** *(Phase 2)* – applications, KYC, plans and limits, commission rules, payouts, dashboard data. *Owns:* artist\_applications, kyc\_documents, plans, subscriptions, payouts.
8. **Commissions** *(Phase 2)* – requests, quotes, milestones, sketch approvals, message threads. *Owns:* commission\_requests, quotes, milestones, messages.
9. **Classes** *(Phase 3)* – classes, batches, seats, waitlist, enrolments, attendance. *Owns:* classes, batches, enrolments, waitlist.
10. **Notifications** – templates, channel routing (email, SMS, WhatsApp, in-app), preferences, delivery log. *Owns:* notifications, templates, preferences.

**Cross-cutting:** an Admin API (staff-only endpoints composed from the modules), audit log, Files (presigned uploads) and Settings (deposit %, commission %, listing limits).

## 5. Data Architecture

- **Conventions:** UUID identifiers; money stored as integers in paise; created and updated timestamps on every table; soft delete where history matters; every status field is an explicit state machine with allowed transitions only.
- **Painting status:** Draft → Submitted → In Review → Changes Requested or Approved → Live → Reserved → Sold, plus Paused, Archived and Rejected. “Reserved” is the checkout hold.
- **Redis keys and lifetimes:** painting hold 15 minutes (set-if-absent with expiry); class seat hold 10 minutes; guest cart 30 days; cached home, art form and product data; rate-limit counters; idempotency keys 24 hours; BullMQ queues. *Redis speeds things up but never decides the truth:* the final “is this painting still available?” check happens inside a database transaction at payment time.
- **Search index:** one document per live painting (title, artist, art form, themes, size, price, availability, image, popularity), updated by events on publish, edit, sold and pause, with a full-reindex command for recovery.
- **Object storage:** the public bucket holds processed images (WebP/AVIF at several sizes, watermarked variants) behind the CDN. The private bucket holds KYC and commission references, reachable only through short-lived signed URLs and encrypted at rest.
- **Sensitive data:** PAN and bank details encrypted at field level and never logged.
- **Backups:** automated daily backups with point-in-time recovery, and restores tested regularly.

## 6. Key Flows

**Browse and SEO.** Next.js pre-renders home, art form, artist and painting pages and refreshes them when content changes. Catalogue edits and CMS publishes trigger on-demand revalidation. Painting pages carry structured data.

**Search.** Browser → API `/search` → Meilisearch → results with facets. Autocomplete uses the same index.

**Add to cart.** Guests get a cart in Redis tied to a cookie token; signed-in users get a cart in SQL, with a merge at login. Adding a one-of-one painting creates a short hold, and a second buyer sees “Reserved”.

**Checkout and payment (webhook-driven)**

1. The customer confirms the address; the API creates the order as PENDING\_PAYMENT and a gateway order, with the amount computed server-side and an idempotency key.
2. The browser opens the gateway checkout. The browser’s “success” message is never trusted.
3. The gateway calls our webhook. We verify the signature, ignore duplicates and, in one database transaction, mark the payment captured, the order paid and the painting Sold (or advance-paid for made-to-order).
4. The OrderPaid event fires. Workers send the receipt and invoice, notify the artist and team, update the search index and clear caches.
5. Failed or abandoned payments expire and the hold is released.

**Balance payment.** When the artist marks the painting Ready and quality check passes, the system creates a payment link for the balance and sends it by email and WhatsApp. The shipment is created only after it is paid. Reminders run as scheduled jobs.

**Listing review.** Artist submits → Submitted → reviewer queue → decision logged → artist notified → on approval the painting is indexed and visible.

**Payout.** After delivery and the return window, a scheduled job moves earnings in the ledger to payable. Finance approves a batch, transfers go out through the gateway or a bank file, and statements are generated.

**CMS banner.** Editor publishes in the CMS → webhook → Next.js revalidates the affected pages → live within seconds, with no deployment.

## 7. API Design (REST)

- Versioned base path `/api/v1`, JSON, resource-based URLs, cursor pagination and a consistent error format with machine-readable codes.
- **Route groups:** public (catalogue, search, art forms), customer (cart, checkout, orders, wishlist, commissions), artist (listings, orders, payouts), admin (staff), and webhooks (payments, shipping, auth provider).
- **Auth:** short-lived access token with refresh in httpOnly secure cookies; role and ownership guards on every route.
- Money-moving endpoints require an `Idempotency-Key` header.
- The OpenAPI spec is generated automatically and used to produce a typed client for the frontend, giving one source of truth.
- Rate limits per route group, request size limits and validation on every input.
- A thin layer in Next.js route handlers is acceptable for cookie and session proxying only; business logic stays in the API.

## 8. Frontend Architecture

- **Rendering by page:** home, art form, artist and painting pages are static with regeneration; search is server-rendered with client-side filters; cart, checkout, account and the artist dashboard are dynamic and client-driven; legal pages and About come from the CMS and are static.
- **Redux Toolkit holds client state:** auth session, cart UI and mini-cart, wishlist, filters, checkout steps and toasts. **RTK Query** handles server data and caching. Do not copy server data into slices by hand.
- With the App Router, create the Redux store per request (provider pattern) so state never leaks between users.
- Tailwind theme with tokens for cream, red, spacing and type scale, and one shared component library for buttons, cards and modals.
- Accessibility built in: semantic HTML, visible focus, automated axe checks in CI.
- Performance: next/image with CDN, lazy loading, font subsetting for Indic scripts, bundle-size budgets in CI.
- One responsive codebase serves desktop and mobile; a PWA layer is optional later.

## 9. Security & Compliance

- RBAC plus ownership checks (an artist can only touch their own listings), least-privilege staff roles and an audit log for sensitive actions.
- HTTPS everywhere, security headers, CORS allow-list, CSRF protection for cookie auth, input validation and output encoding.
- **Payments:** card data never touches our servers; webhook signatures are verified; amounts are computed server-side; a daily reconciliation job compares gateway reports with our ledger.
- **Uploads:** type and size limits, virus scan, image re-encoding and EXIF stripped.
- Secrets in a managed secrets store, never in code; dependency scanning in CI.
- **Privacy:** consent records, data export and deletion flows (DPDP Act), minimal retention, and KYC retention rules to be confirmed with legal.
- **Abuse controls:** bot protection on signup and OTP, OTP attempt limits, order risk rules.

## 10. Environments, Delivery & Operations

- **Environments:** local (Docker Compose with database, Redis, search and S3-compatible storage), staging (mirrors production, test-mode payments) and production.
- **Monorepo** (pnpm + Turborepo): apps/web, apps/api, apps/cms; packages/ui, packages/types, packages/config.
- **CI/CD:** lint, type-check, tests and build on every pull request; auto-deploy to staging on merge; production by approval with one-click rollback.
- Versioned database migrations run in the pipeline, plus seed data for demos.
- **Observability:** Sentry for errors, structured logs, uptime and synthetic checks on the checkout path, and dashboards for latency, error rate, queue depth and payment success.
- Runbooks for payment failures and stuck jobs.

## 11. Build Order: Where to Start

Principle: build thin vertical slices so something demonstrable exists early.

**Step 0 – Foundations.** Monorepo, TypeScript, linting, Docker Compose, CI, environments, migrations, logging and error handling, Tailwind theme and base components, API skeleton with OpenAPI. *Done when* a test request works end to end on staging.

**Step 1 – Data model and seed data.** Design the schema for all Phase 1 modules, including user roles from day one so Artist Partner and Instructor slot in later. Seed real art forms, artists and 30–50 paintings with the client’s images.

**Step 2 – Catalogue storefront.** Catalog module plus the Next.js pages: loader, home, art form, painting and artist; Meilisearch search and filters; CMS with hero banners. *Done when* the client can browse and you can change a banner live. This is your first demo.

**Step 3 – Identity.** Google, email and mobile OTP sign-in; role selection screen; profile and addresses; protected routes.

**Step 4 – Cart, holds and checkout.** Redis carts, holds, promo codes, delivery check, checkout form and order creation.

**Step 5 – Payments and orders.** Gateway in test mode, webhooks, advance and balance logic, invoices, order tracking and notifications. *Done when* a test purchase of a unique painting and a made-to-order advance both complete correctly, including double-click and abandoned-payment cases.

**Step 6 – Core admin console.** Catalogue management, orders, refunds, coupons, customer list, audit log.

**Step 7 – Phase 1 hardening and launch.** Security review, load tests on search and checkout, SEO checks, accessibility audit, legal pages, backups and monitoring, and a user acceptance test with small real payments.

**Then** Phase 2 (artist onboarding, KYC, plans and limits, listing review, payouts, full commissions) and Phase 3 (classes). Because the roles, payment ledger and notification foundations already exist, these phases add modules rather than rewrites.

## 12. Scaling Path

1. **Launch:** one API instance, one worker, managed database with backups, Redis, search and CDN.
2. **Growing:** several API instances behind a load balancer, a database read replica, wider caching and an autoscaled worker.
3. **Pressure points:** extract Notifications and Worker, media processing and search indexing as independent services.
4. **Large scale:** extract Payments and the Catalog read API, and introduce a message broker (Kafka, RabbitMQ or a managed equivalent) when in-process events are no longer enough.

Each step is triggered by measured load, not guesswork.

## 13. Technical Decisions to Confirm

1. PostgreSQL or MySQL.
2. Managed auth provider (Firebase, Auth0 or similar) or building OTP and Google sign-in ourselves.
3. Payment gateway (Razorpay, Cashfree or similar) and the seller payout method.
4. CMS: Strapi, Payload or Sanity.
5. Hosting: AWS Mumbai for the backend or a simpler single VM.
6. Shipping aggregator.
7. WhatsApp and SMS providers, and the lead time for DLT registration.
8. Team size and timeline, which decide how much of the Step 0 tooling to adopt.

---

While your data footprint (200-300 images, 1,000 users) is incredibly lightweight and easily fits within the capacity limits of most free tiers, not everything on this list will be completely free.

For an Indian e-commerce marketplace like Parampara, there are commercial restrictions, geographic pricing quirks, and architectural bottlenecks you need to watch out for.

Here is the reality check on what is free, what isn't, and what will break if you try to force it into a free tier.

1. The "Absolutely Not Free" Zone
Mobile OTP (SMS) in India: You cannot do this for free. Indian telecom regulations require DLT registration for businesses to send SMS, which has an upfront cost (usually around ₹5,900).Furthermore, there is no true "free tier" for Indian SMS. Providers like MSG91 will charge per SMS.

Warning on Firebase Auth: If you use Firebase for Phone Auth, Google Cloud Identity Platform charges roughly ₹6 to ₹7 per SMS for Indian numbers. It is one of the most expensive ways to verify Indian phone numbers.

WhatsApp Notifications: The WhatsApp Business API (Gupshup, Interakt) does not have a free tier for outbound business-initiated messages. You will pay per conversation.

Payments & Shipping: Razorpay, Cashfree, and Shiprocket do not have fixed monthly server fees, but they charge per transaction (usually around 2% for payments) and per shipment.

2. The "Free, But Legally Risky" Zone
Vercel for Frontend: Vercel's "Hobby" plan is famously generous and perfectly handles Next.js, but its Terms of Service strictly prohibit commercial use. Because Parampara is a revenue-generating marketplace, deploying it on Vercel's free tier violates their terms. They can (and do) suspend e-commerce sites on Hobby plans.

Alternative: Host the Next.js frontend on Cloudflare Pages or Netlify, or deploy it alongside your backend on a virtual machine.

3. The "Technically Free, But Will Crash" Zone
AWS Free Tier (Backend & DB): AWS gives you 750 hours a month of a t2.micro or t3.micro EC2 instance (1 vCPU, 1GB RAM) and a similar micro RDS instance for 12 months only.

The Bottleneck: Running Node.js (NestJS), a background worker (BullMQ), an in-memory datastore (Redis), and a self-hosted CMS (Strapi) on a single 1GB RAM server will almost certainly result in Out-of-Memory (OOM) crashes. NestJS and Strapi are both memory-heavy.

The Fix: Use managed free tiers elsewhere so your AWS EC2 instance only has to run your core NestJS API.

4. The "Safe & Free" Zone (Will handle your scale easily)
Images & Documents: Cloudflare R2 gives you 10GB of storage and 10 million reads per month free forever (no 12-month expiry like AWS S3). 300 product images will take up less than 1GB.

Search: Algolia’s free tier allows up to 10,000 requests/month and 1 million records. Meilisearch Cloud also offers a solid free tier. With 300 products, you will barely make a dent in either.

Email: Resend offers 3,000 free emails per month, which is plenty for 1,000 users making occasional purchases.

Identity (Social/Email): Firebase Auth and Auth0 are completely free for Email, Password, and Google Sign-in at this scale (Auth0 gives you 7,500 active users free). Just avoid their SMS options.

How to optimize this stack for near-₹0 startup costs:
If you want to keep costs as close to zero as possible for year one, while keeping the application stable and legal, I recommend these adjustments:

Drop Vercel for Netlify or Cloudflare Pages: They have more lenient commercial-use policies on their entry tiers compared to Vercel.

Use managed Database & Redis free tiers: Instead of AWS RDS and self-hosted Redis, use Supabase or Neon.tech for a permanent managed PostgreSQL free tier, and Upstash for a permanent Serverless Redis free tier (10,000 commands/day). This offloads heavy databases from your backend server.

Use a hosted CMS: Instead of trying to cram self-hosted Strapi onto a 1GB server, use Sanity.io. Their free tier is incredibly generous, permanently free, and handles the CMS hosting for you.

Rethink Login: Push users toward Google Sign-In and Email OTPs first. Only enable Mobile SMS OTP if the business is willing to pay the DLT registration and per-message fees from day one.

---

- Let's use a modular monolith. Let me know how am I supposed to structure the repository. 
- How should I be initializing the NextJs with typescript for frontend and NodeJs + NestJs for backend.
- Let's use PostgreSQL for database, Redis foe caching, Meilisearch for search, Object Storage am still not sure what to do with this. 


- First let's start with login signin with Firebase the authentication part and google sign in. the OTP part is actually not required. 
- Let's leave out the payment gateway part as well.
- Let's finish the authentication part first and then side by side lets build the frontend as well. 
- So first let's start with the UI's Loader page, and sign-in/Register page.
- Once these three pages are created let's work on the Authentication part.
- Once Auth is completed, let's work on Home page. And in Home Page Lets build the headers, Footers, CMS configurations, Explore by and so on let it be on standBy. 
- These many things should done first and then we can continue with the rest of the wiring is what I feel. We can do this as Phase 1, Phase 2 will be the backend part where we will be wiring the products and its details.

- Note while prepping for the Sign-in and Register we will have to make up three parts. One is for Customer/Collector, Seller/Artist and the Admin who will be approving wtr the artist is legit the paintings are of good quality and so on.

- I should be able to add more and auth should be proper without any issues and later on I should be able to scale up cleanly. As in protected routes and protected pages and so on. A customer/collector should land on Customer page only, A Seller should land on a seller specific page only and me as Admin should be able to have a bulls eye view of what's happening throughout the site, monitoring, the inventory, orders and so on. 

