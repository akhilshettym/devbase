## Parampara — Product Vision & FeatureBlueprint

`Version 1.0` · Draft for client review · `Scope`: features, business rules and user journeys (technical architecture follows in the next stage)

### 1. Vision at a Glance:

Parampara is an online gallery and marketplace for traditional Indian paintings. It brings four experiences together under one brand:

- **Shop** – browse and buy original paintings across Madhubani, Warli, Pattachitra, Kalamkari and other folk and classical art forms.

- **Sell** – verified artists list their work through a curated marketplace where every painting is reviewed before it goes live.

- **Commission** – collectors request a painting made for them and begin the work with an advance.

- **Learn** – hobby classes in painting and sketching, with limited seats booked through an advance.

**Design principle**: _familiar to shop, graceful to look at_. We borrow the ease people expect from the best marketplaces – strong search, filters, a clear buy box, delivery checks, recommendations – and wrap it in a calm gallery look: cream backgrounds, muted redaccents, a classical serif typeface, and the artwork always at centre stage. The patternsare proven; the visual identity is entirely Parampara’s own.

#### What sets Parampara apart:

- **Curated**: no painting is listed without review.

- **Story-led**: every piece comes with its art form, region, artist and meaning.

- **Trustworthy**: certificate of authenticity, verified artists, secure payments, insured shipping.

- **Beyond buying**: commissions and classes keep people connected to the art itself.

---

### 2. Who Uses Parampara:

- **Visitor** – browses, searches and reads about art forms; signs in to buy, save or enquire. Guest checkout is available for ready-to-ship paintings.

- **Collector (customer)** – buys paintings, customises, commissions, keeps a wishlist, writes reviews and books classes.

- **Artist Partner (seller)** – everything a Collector can do, plus lists paintings, fulfils orders, receives payouts and can take commissions. **“Artist Partner”** is a suggested name; alternatives are “Kalakaar Partner” or “Creator”.

- **Instructor (Phase 3)** – an approved teacher who runs hobby classes.

- **Parampara team** – Super Admin, Catalogue Reviewer, Support Executive, Finance and Content Editor, each with limited permissions.
 
**One account, multiple roles**. A person signs up once and roles are added to the sameaccount: a Collector can later apply to become an Artist Partner, and an Artist Partner can still buy art.

---

### 3. Registration & Sign-in [Phase 1]:

- Sign up or log in with **Google**, **email + password**, or **mobile OTP** (the most familiar option for many Indian users).

- Right after first sign-in, one simple screen asks **“How would you like to use Parampara?”** – I want to buy art (Collector, the default) or I want to sell my art (ArtistPartner). Skipping it defaults to Collector.

- Choosing Artist Partner starts the onboarding journey in Section 7; until approval the person has full Collector access.
  Email is verified at signup; phone is verified before the first order.

- Sensible security: sensible password rules, forgot-password, login alerts, session timeout, plus account deletion and data download on request.

- Cart and wishlist survive sign-in; a guest cart merges into the account.

---

### 4. Storefront Experience:

#### 4.1 Welcome loader:

- Shown once per visit for 3–5 seconds with a visible **Skip** button. The site loads behind it, so nothing is delayed.

- **“Welcome”** cycles through major Indian languages over faint mandala and textile motifson cream, with **“Parampara”** at the bottom centre.

- **Greetings** (to be verified by native speakers before launch): `स्वावागत है` (Hindi), `স্বাস্বাগতম` (Bengali), `நல்வரவு` (Tamil), `સ્વાવાગત છે` (Gujarati), `స్వాగతం` (Telugu), `ಸ್ವಾಗತ` (Kannada), `സ്വാഗതം` (Malayalam), `स्वावागत आहेहे` (Marathi), `ਜੀ ਆਇਆਂ ਨੂੰ` (Punjabi).

- **Respects** “reduce motion” device settings and does not replay within the same session.

#### 4.2 Header & navigation:

- Sticky header with logo, **Art Forms** mega-menu, search, **Deliver to [PIN code]**, account, wishlist and a cart with item badge.

- **Mega-menu**: Shop by Art Form · Shop by Room or Occasion · Shop by Price · Artists ·Commission a Painting · Classes
  (Phase 3).

- **Mobile**: hamburger menu, large tap targets, search and cart always visible.

#### 4.3 Home page:

- Hero carousel of 3–5 slides (auto-play with manual controls), each with artwork, caption and a button; managed through the CMS.

- Tagline and a “Painting of the Week” highlight.

- Explore by Art Form tiles, New Arrivals, Trending, Featured Artists and curated Collections (Festive, Gifting, Living Room, Under ₹10,000).

- Commission call-to-action, a trust strip (Authentic · Hand-painted · Certified · Insured shipping · Secure payments), testimonials, promotional banners and “Recently viewed”.

- Classes teaser (Phase 3)

#### 4.4 Art form pages:

- Banner and tagline, then a story section: origin, region, techniques, materials, common themes, notable artists and GI-tag status where applicable.

- Product grid with filters and sorting, **“Explore other art forms”**, **FAQs** and a **promotionalbanner**.

- Each page carries unique, genuinely helpful copy rather than filler.

#### 4.5 Artist profiles:

- Photo, story, region, art forms, awards, verified badge and all their paintings, with a “Commission this artist” button when they accept commissions.

#### 4.6 Search, filters & sorting:

- Autocomplete across paintings, artists and art forms, tolerant of spelling mistakes, with a helpful “no results” page that suggests alternatives.

- **Filters**: art form, artist, price range, size, orientation, surface (canvas, handmade paper, wall), theme (deities, nature, folk life), colour, availability (Ready to ship / Made to order), on sale, framed.

- **Sorting**: relevance, newest, price, popularity.

- Painting cards show image, title, artist, price with struck-out original and discount label, availability and a wishlist heart.

#### 4.7 Product page:

- **Listing types**: Original (one of one), Made to order (the artist recreates the style, witha stated lead time) and
  Commission (Section 8).

- Gallery of 3–5 images with zoom, full-screen view and optional artist video; breadcrumbs.

- Title, artist (linked), art form, price and discount (shown as a text label as well ascolour), availability and lead time.

- **Buy box**: Add to Cart, Buy Now, Customize, Add to Wishlist, Share and a PIN-code delivery estimate.

- **Customisation**: size, frame, surface and special notes, with the price updating live andthe advance and lead time explained clearly.

- Certificate of Authenticity, the story of the painting, specifications (dimensions, medium, weight), shipping and returns summary, FAQs and verified reviews.

- “Similar paintings” and **“Customers also viewed”** (hand-curated until there is enough browsing data).

- **Unique-piece rules**: quantity is fixed at one; the painting is held for 15 minutes once someone starts checkout, then released; sold pieces show “Sold” with similar suggestions and a “Request something similar” link.

- **“Report this listing”** for buyers.

#### 4.8 Wishlist, sharing & reviews:

- Wishlist from any card or page, synced to the account, with “Add all to cart” and optional price-drop alerts.

- Share via WhatsApp, Facebook, Pinterest or copy-link, with rich previews.

- Ratings and reviews from verified buyers only, moderated, photos allowed, with replies from the artist.

---

### 5. Cart, Checkout & Payments:

#### 5.1 Cart:

- Each line shows thumbnail, title, artist, art form, chosen options, price and lead time, with **Remove** and **Move to Wishlist**.

- Quantity controls (typed number plus +/–) appear only where multiples make sense; unique originals stay at one.

- Promo code, PIN-code delivery estimate, order summary and a clear **“Proceed to Checkout”**.

- **Ready-to-ship** and **made-to-order** items are split into separate shipments automatically; items from different artists become separate sub-orders under a single payment.

- **Empty cart**: a friendly message and a **“Browse Paintings”** button.

#### 5.2 Checkout:

- Guest checkout for ready-to-ship paintings; an account is needed for commissions and classes so progress can be tracked.

- Address with PIN-code validation, saved addresses, phone and optional GSTIN for abusiness invoice.

- **A clear summary**: item total, delivery, taxes, amount payable now, and amount due later and when.

#### 5.3 Payment rules (configurable by admin):

- **Ready-to-ship originals**: full payment at checkout.

- **Made-to-order or customised**: advance at order (default 15%); balance when the painting is ready, before dispatch, through a secure payment link.

- **Commissions**: advance as stated in the accepted quote.

- **Classes**: advance to hold a seat; balance before the class starts.

- **Methods**: UPI, cards, net banking, wallets, and EMI for higher-value pieces.

- Parampara never stores card details; saved methods exist only as secure tokens held by the payment provider.

- Payments confirm automatically, with no manual confirmation form. Failed, pending and duplicate payments are handled, and refunds go back to the original method.

- GST-compliant invoices and payment receipts (PDF and email) for every payment.

- Order confirmation page and message with order number, expected timeline and support contact.

---

### 6. Orders, Delivery & Customer Account:

- **Status flow, ready-to-ship**: `Placed → Paid → Packed → Shipped → Delivered`.

- **Status flow, made-to-order**: `Advance Paid → Accepted by Artist → In Production (withprogress photos) → Ready → Balance Paid → Quality Check → Shipped → Delivered`.

- Art-grade packaging (protective wrap, corner guards, rigid box or tube), insured shipping through logistics partners, live tracking and PIN-code serviceability. Hand delivery in select local areas can be offered.

- Quality check with photo verification before every dispatch.

- **Policies shown before purchase**: cancellation, refunds, returns (ready-to-ship originals get a short return window; made-to-order and custom pieces are returnable only for damage or not-as-described), transit-damage claims (reported within 48 hours with photos) and refund timelines.

- **Support**: help centre and FAQs, contact form, order-linked tickets, call and WhatsApp.

- **My Account**: order history with status and invoices, shipment tracking, reorder (made-to-order pieces only), saved addresses, wishlist, commissions, class bookings (Phase3), notification preferences and logout.

---

### 7. Artist Partner Marketplace [Phase 2]:

#### 7.1 Onboarding journey:

1. Choose Artist Partner at signup or later from the account menu.

2. Complete the profile: bio, region, art forms, experience and 3–5 portfolio samples.

3. KYC: PAN, government ID, verified bank account, and GSTIN where applicable.

4. Parampara reviews the application (target: 2–3 working days).

5. On approval, accept the e-signed Artist Agreement covering originality, copyright, commission and conduct.

6. Pay the registration fee and choose a plan; the seller dashboard activates.

**Why pay after approval?** Charging after review avoids refunds for rejected applicants. If you prefer payment first, the fee can be made refundable on rejection.

#### 7.2 Plans & listing limits:

- Starter: up to 10 active paintings. Pro: up to 20. Higher tiers can be added later.

- Fee, duration (one-time or annual) and limits are all set by admin.

- Drafts and rejected items do not count; sold or archived paintings free up a slot.

- A usage meter on the dashboard (for example “7 of 10 listings used”) with one-click upgrade.
  If a plan lapses: reminders, a grace period, then new listings are blocked and existing ones hidden. Open orders are still honoured.

#### 7.3 Painting submission:

- Fields: title, art form, theme, story, dimensions, surface and medium, year, price, availability type (original or made-to-order), customisation options, lead time, packed size and weight, and an originality declaration.

- At least 3 photos following simple guidelines (plain background, good light, one detail shot), with automatic checks for resolution and duplicates, plus optional video.

#### 7.4 Review workflow:

- `Draft → Submitted → In Review → Changes Requested` or `Approved → Live → Sold /Paused / Archived`. Rejections always include a reason.

- **Reviewer checklist**: originality and authenticity, art form accuracy, photo quality, description and pricing sanity, prohibited content.

- **Edits to live listings**: price and stock apply instantly; images, title and description go back for a quick re-review.

- Every decision is logged and the artist is notified.

#### 7.5 Artist dashboard:

- Listings and their status, orders to fulfil, commission requests, earnings, payouts, plan usage, profile, performance (views, wishlists), messages and notifications.

#### 7.6 Earnings & payouts:

- Parampara commission per sale, configurable by plan or art form, with itemised statements.

- Payouts released after delivery and the return window, on a fixed schedule (weekly or fort nightly) to the verified bank account.

- Refunds and disputes adjust payouts. TDS, TCS and GST treatment is to be confirmed with your chartered accountant.

#### 7.7 Fulfilment model (decision needed):

- **Option A – Parampara-managed (recommended)**: the artist sends the painting to Parampara, which handles quality check, packing and shipping. Best protection for fragile art and the most consistent customer experience.

- **Option B – Artist ships directly**: pickups arranged with Parampara-branded packaging. Faster for the artist, with less quality control.

#### 7.8 Conduct:

- Artist Agreement, originality warranty, a takedown process for copyright complaints, warnings and suspension.

---

### 8. Custom Painting Commissions [Phase 1: customise · Phase 2: fullcommissions]:

#### Two routes:

- **Customise an existing painting**: size, frame, surface and notes, priced instantly on the product page.

- **Commission a new painting**: fully bespoke.

#### Commission journey:

1. **Request**: art form, subject, size, reference images, occasion and deadline, budget range, preferred artist (optional).

2. **Quote**: Parampara matches an artist and sends price, timeline, advance %, revision rounds and a 7-day validity.

3. Accept and pay the advance to start the work.

4. Sketch approval, followed by progress photos.

5. `Final approval → balance payment → quality check → delivery → review`.

**Rules**: one or two revision rounds at sketch stage; clear cancellation terms (the advance is not refundable once painting begins); the artist keeps copyright and the collector owns the physical painting; no copying of living artists’ work; a private message thread per commission; admin-mediated disputes.

---

### 9. Hobby Classes [Phase 3]:

- **Class catalogue**: painting and sketching classes by type, level, mode (online live, in-person workshop or hybrid), city, price and date.

- **Class page**: what you will learn, syllabus, who it is for, requirements and materials, instructor bio, sample works, duration, batches, seats left and FAQs.

- **Enrolment**: sign in → choose batch → participant details (a child can be enrolled with guardian consent) → pay advance → confirmation with calendar invite.

- **Seat logic**: limited seats per batch; a seat is held for 10 minutes during payment; full batches offer a
  waitlist that notifies automatically when a seat opens.

- **Policies**: balance due before the first session, rescheduling and cancellation windows,and full refund or transfer if Parampara cancels a class.

- **Communication**: reminders, online meeting link, materials list or optional kit, post-class resources.

- **Instructor tools**: create classes (admin-approved), manage batches, roster and attendance, announcements.

- **After class**: reviews and an optional certificate of participation.

- **Who can enrol**: any registered user, Collectors and Artist Partners alike. Who can teach is a decision for Section 18.

---

### 10. Content Management (CMS) [Phase 1]:

Change the storefront’s look and words without a deployment

- **What it controls**: hero and promotional banners (image, text, button, link, placement), home-page section order, art form pages, collections, the announcement bar, FAQs, policy pages, About, stories and blog, and SEO titles and descriptions.

- **Workflow**: draft, preview on desktop and mobile, schedule (for example Diwali banners switching on and off automatically), publish, unpublish, version history and rollback.

- **Media library**: automatic resizing, mandatory alt text, usage tracking.

- **Roles**: Editors draft, Approvers publish, and an audit log records every change.

- **Boundary**: prices, stock, orders and payments live in the admin console, never the CMS, so a content edit can never break commerce.

- **Demo moment**: change a banner live in front of the client and watch it appear without a release.

---

### 11. Admin & Operations Console [Phases 1–3]:

- Dashboard with sales, orders, pending reviews and the support queue.

- Catalogue, listing-review queue, art forms and collections.

- Orders, shipments and refunds; commission requests and quotes.

- Artist applications, KYC, plans and suspensions; payouts and commission statements.

- Customers, review moderation, coupons and promotions.

- Classes, batches and enrolments (Phase 3).

- Reports: sales, GST, payouts, top art forms and artists, search terms, conversion.

- Roles and permissions, audit logs, and settings for deposit %, commission %, listinglimits, policy text and delivery rules.

---

### 12. Notifications:

Email, SMS and WhatsApp templates, plus an in-app notification centre.

- **Collectors**: welcome, OTP, order and payment receipts, balance reminder, shipped, delivered, commission quote and progress, class reminders, wishlist alerts, abandoned cart (opt-in).

- **Artists**: application status, listing approved or changes requested, new order,commission request, payout processed, plan expiry.

- **Team**: new application, listing to review, new commission, payment failure, support ticket. Transactional and marketing messages are kept separate, and every user can manage preferences and unsubscribe.

---

### 13. Trust, Legal & Compliance (India):

- **Authenticity**: Certificate of Authenticity for every original, verified-artist badge, GI-tag information where applicable.

- **Legal pages**: Terms of Use, Privacy Policy, Shipping & Delivery, Cancellation & Refunds, Artist Agreement, Commission Terms, Class Terms, Grievance Redressal.

- **E-commerce rules**: seller details, grievance officer, and clear pricing and return information in line with the Consumer Protection (E-Commerce) Rules, 2020.

- **Data protection**: consent, privacy notice, access and deletion aligned with the Digital Personal Data Protection Act, 2023, plus cookie consent.

- **Tax**: GST invoicing, HSN codes and GSTIN capture; marketplace tax duties to be confirmed with a chartered accountant.

- **Payments**: card data handled only by a PCI-compliant payment provider.

- **Intellectual property**: ownership terms, take down process and a subtle watermark on images.

- **Risk controls**: fraud checks, rate limiting, bot protection and report-a-listing.

---

### 14. SEO, Marketing & Analytics:

- **SEO**: unique, useful copy on art form, artist and painting pages (quality over word count); descriptive alt text with artist, art form and subject; clean URLs; sitemap; structured data for products, breadcrumbs, FAQs and classes; rich share previews for WhatsApp and social.

- **Marketing**: coupons, festival campaigns, email and WhatsApp campaigns, newsletter signup, with referral and gift options available later.

**Analytics**: the funnel from view to purchase, searches with no results, artist and artform performance, with consent-aware tracking.

---

### 15. Production-Readiness Standards:

- **Accessibility**: WCAG 2.1 AA – contrast-checked red on cream, keyboard navigation, screen-reader labels, visible focus, skip link, and meaning never conveyed by colouralone.

- **Performance**: mobile-first; main content visible in under 2.5 seconds on a typical 4Gconnection; optimised, lazy-loaded images.

- **Security**: HTTPS everywhere, role-based access, secure sessions, validated and virus-scanned uploads, audit logs, encrypted backups.

- **Reliability**: monitoring and alerts, error tracking, tested backup restores, a staging environment, safe releases with rollback.

- **Quality assurance**: user acceptance testing, payment and refund testing, load testing and content review before launch.

- **Scalability**: modular features so new capabilities plug in without rework.

---

### 16. Delivery Roadmap:

- **Phase 1 – Gallery & Store (launch)**: welcome loader, storefront and navigation, art form pages, search and filters, product pages with customisation, cart and checkout with advance payments, accounts with role selection and Google sign-in, wishlist, reviews, notifications, CMS, core admin console, legal pages.

- **Phase 2 – Artist Marketplace & Commissions**: artist onboarding, KYC, plans and limits,listing submission and review, artist dashboard, payouts, full commission workflow.

- **Phase 3 – Hobby Classes**: class catalogue, batches, seat limits and waitlist, enrolment with advance payment, instructor tools, reminders and certificates.

- **Phase 4 – Growth**: items from the extension backlog, chosen from early results. The account, role and payment foundations are built in Phase 1, so later phases connect without redoing earlier work.

---

### 17. Extension Backlog:

Ready to add on request: gift cards, “see it on your wall” AR preview, auctions or limited drops, international shipping and multi-currency, Hindi and regional-language site, loyalty and referral rewards, corporate and bulk orders, virtual exhibitions and live artist sessions, artist stories and video content, art subscription boxes, print reproductions, a mobile app and WhatsApp ordering.

---

### 18. Decisions We Need:

1. **Business model**: curated marketplace or Parampara’s own inventory; Parampara-managed fulfilment or artists ship directly.

2. **Artist economics**: registration fee amount and duration, commission %, listing-limittiers.

3. **Payment rules**: advance % by product type; balance before dispatch or at hand delivery.

4. **Returns**: return window for ready-to-ship originals and the transit-damage process.

5. **Delivery coverage**: India-wide or select cities at launch.

6. **Classes**: online, in-person or both; who may teach; which cities.

7. **Business setup**: legal entity, GST status, payment provider preference.

8. **Support**: channels and working hours.

9. **Languages and brand assets**: launch languages; logo, brand guidelines and image rights.
