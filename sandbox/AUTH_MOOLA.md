## Taanjika --- Moola Backend & Authentication Architecture

> **Document purpose:** Consolidated architecture review and
> implementation guide for the Taanjika authentication and backend
> foundation.
>
> **Scope:** This document captures the architecture review,
> current-state assessment, target design, security considerations,
> database direction, module responsibilities, workflows, and
> implementation roadmap discussed in the previous conversation.
>
> **Important:** The current-state assessment reflects the files and
> code previously shared for review. Items marked as not shown or not
> confirmed should be verified against the live repository before
> implementation.

------------------------------------------------------------------------

## Table of contents

1.  [Executive summary](#1-executive-summary)
2.  [Current backend structure](#2-current-backend-structure)
3.  [NestJS architecture
    fundamentals](#3-nestjs-architecture-fundamentals)
4.  [Current implementation review](#4-current-implementation-review)
    -   Database module
    -   Firebase module
    -   Authentication module
    -   Users module
    -   Admin bootstrap module
    -   Health module
5.  [Important gaps and architectural
    corrections](#5-important-gaps-and-architectural-corrections)
6.  [Target Moola architecture](#6-target-moola-architecture)
7.  [Authentication architecture and
    workflows](#7-authentication-architecture-and-workflows)
8.  [Authorization architecture](#8-authorization-architecture)
9.  [Database architecture and required
    evolution](#9-database-architecture-and-required-evolution)
10. [Module responsibilities and
    interactions](#10-module-responsibilities-and-interactions)
11. [Darshana and Moola
    responsibilities](#11-darshana-and-moola-responsibilities)
12. [File-by-file action plan](#12-file-by-file-action-plan)
13. [Testing strategy](#13-testing-strategy)
14. [Implementation roadmap](#14-implementation-roadmap)
15. [Immediate next steps](#15-immediate-next-steps)
16. [Architecture principles and
    decisions](#16-architecture-principles-and-decisions)

------------------------------------------------------------------------

# 1. Executive summary

The Moola backend already has a meaningful authentication foundation. It
is not an empty backend.

The current implementation includes:

-   PostgreSQL connectivity through a reusable connection pool.
-   A database service with query and transaction support.
-   Firebase Admin initialization.
-   Firebase ID-token verification.
-   Initial registration/profile provisioning.
-   Authentication-related guards and decorators.
-   User and role persistence.
-   An initial Admin bootstrap mechanism.
-   A health-check module.
-   Global request validation and basic HTTP security configuration in
    the application bootstrap.

The existing implementation is a good starting point, but it does not
yet provide the complete account lifecycle and authorization model
required by Taanjika.

The most important architectural direction is:

-   **Firebase Authentication establishes identity.**
-   **PostgreSQL stores Taanjika's account and business state.**
-   **Moola/NestJS is the authority for authorization and business
    rules.**
-   **Darshana/Next.js presents the user experience but does not decide
    privileges.**

The goal is to evolve the existing implementation rather than discard
it.

## 1.1 Current-state overview

  Area                                Assessment
  -----------------------------------------------------------------------
  `PostgreSQL integration`:              Implemented foundation

  `Firebase Admin integration`:          Implemented foundation

  `Firebase token verification`:         Implemented

  `User profile provisioning`:           Basic implementation

  `Registration endpoint `:              Basic implementation

  `Email verification enforcement`:      Partial; route application needs
                                      verification

  `Role-based authorization`:            Partial

  `Admin bootstrap`:                     Implemented; security and
                                      operational review required

  `Artist application lifecycle`:        Basic/placeholder implementation

  `Seller activation and subscriptions`: Not implemented in the reviewed
                                      structure

  `Permission-based authorization`:      Not implemented in the reviewed
                                      structure

  `Audit logging`:                       Not shown

  `Automated authentication tests`:      Not shown

  `Migration runner/history`:            Not shown
  -----------------------------------------------------------------------

These assessments are based on the material previously shared. "Not
shown" does not necessarily mean the capability does not exist elsewhere
in the repository.

------------------------------------------------------------------------

# 2. Current backend structure

The backend is located at `apps/moola`.

The structure shared for review was:

``` text
taanjika/
└── apps/
    └── moola/
        ├── database/
        │   └── migrations/
        │       └── 001_authentication_schema.sql
        │
        ├── dist/
        ├── src/
        │   ├── modules/
        │   │   ├── admin-bootstrap/
        │   │   │   ├── admin-bootstrap.module.ts
        │   │   │   └── admin-bootstrap.services.ts
        │   │   │
        │   │   ├── auth/
        │   │   │   ├── decorators/
        │   │   │   │   ├── current-user.decorator.ts
        │   │   │   │   └── roles.decorator.ts
        │   │   │   ├── dto/
        │   │   │   │   └── register-profile.dto.ts
        │   │   │   ├── guards/
        │   │   │   │   ├── email-verified.guard.ts
        │   │   │   │   ├── firebase-auth.guard.ts
        │   │   │   │   └── roles.guard.ts
        │   │   │   ├── auth.controller.ts
        │   │   │   ├── auth.module.ts
        │   │   │   └── auth.services.ts
        │   │   │
        │   │   ├── database/
        │   │   │   ├── database.constants.ts
        │   │   │   ├── database.module.ts
        │   │   │   └── database.services.ts
        │   │   │
        │   │   ├── firebase/
        │   │   │   ├── firebase-admin.service.ts
        │   │   │   └── firebase.module.ts
        │   │   │
        │   │   ├── health/
        │   │   │   ├── health.controller.ts
        │   │   │   └── health.module.ts
        │   │   │
        │   │   └── users/
        │   │       ├── users.module.ts
        │   │       ├── users.repository.ts
        │   │       └── users.services.ts
        │   │
        │   ├── app.module.ts
        │   └── main.ts
        │
        ├── .env
        ├── .env.example
        ├── Dockerfile
        ├── eslint.config.mjs
        ├── nest-cli.json
        ├── package.json
        ├── tsconfig.build.json
        └── tsconfig.json
```

The structure above is the one supplied in the discussion. The actual
repository should be checked for filename differences and any additional
files.

------------------------------------------------------------------------

# 3. NestJS architecture fundamentals

This section explains the NestJS concepts used in Moola and how they fit
together.

## 3.1 Modules

A NestJS module groups related backend functionality.

Examples:

-   `AuthModule`: authentication-related orchestration.
-   `UsersModule`: Taanjika user profile and account operations.
-   `FirebaseModule`: Firebase Admin integration.
-   `DatabaseModule`: PostgreSQL connectivity.
-   `AdminBootstrapModule`: controlled initial Admin provisioning.

A module declares:

-   Controllers that belong to it.
-   Providers/services it owns.
-   Imported modules it depends on.
-   Providers it exports for other modules.

Modules are comparable to departments in an organization. Each module
should have a clear responsibility and should avoid owning unrelated
business logic.

## 3.2 Controllers

A controller receives HTTP requests and returns HTTP responses.

For example, the authentication controller may expose:

-   `POST /api/v1/auth/register`
-   `POST /api/v1/auth/sync`
-   `GET /api/v1/auth/me`

The controller should:

1.  Receive the request.
2.  Validate input through DTOs and pipes.
3.  Delegate work to a service.
4.  Return the service result.

Controllers should not contain large amounts of business logic or raw
SQL.

## 3.3 Services

Services contain application and business logic.

For example, `AuthService` may coordinate registration profile
provisioning and current-account retrieval. `UsersService` owns
user-profile operations.

Services should not become oversized classes that contain every
feature's logic. Keep responsibilities within their domain.

## 3.4 Repositories

Repositories encapsulate database access.

For example, `UsersRepository` can:

-   Find a user by Firebase UID.
-   Create or update a user profile.
-   Assign or retrieve roles.
-   Persist consent history.
-   Retrieve account status.

The service decides what should happen. The repository knows how to read
and write the database.

## 3.5 DTOs

DTO means Data Transfer Object.

A DTO defines the shape of incoming API data and can validate it with
`class-validator`.

The global NestJS `ValidationPipe` configuration previously shown
includes:

-   `whitelist: true`: removes properties without validation decorators.
-   `forbidNonWhitelisted: true`: rejects unexpected properties.
-   `transform: true`: transforms incoming values into DTO instances
    where appropriate.

This is a useful foundation for API validation.

## 3.6 Guards

Guards determine whether a request may continue to a controller handler.

Examples:

-   `FirebaseAuthGuard`: validates the Firebase identity token.
-   `EmailVerifiedGuard`: requires a verified email for selected
    operations.
-   `RolesGuard`: checks required roles.

Guards run before the controller handler. They are a key part of the
authorization pipeline.

## 3.7 Dependency injection

NestJS creates and injects services rather than requiring classes to
instantiate their dependencies manually.

For example, a controller can receive `UsersService` through its
constructor.

Dependency injection helps with:

-   Sharing services.
-   Keeping modules loosely coupled.
-   Replacing dependencies in tests.
-   Managing database and external-service clients.

A typical dependency chain is:

``` text
AuthController
    -> AuthService
        -> UsersService
            -> UsersRepository
                -> DatabaseService
```

------------------------------------------------------------------------

# 4. Current implementation review

## 4.1 Database module

Files:

``` text
modules/database/
    database.constants.ts
    database.module.ts
    database.service.ts
```

The reviewed implementation uses the `pg` package, PostgreSQL's Node.js
client.

A connection pool keeps reusable database connections available instead
of creating a new connection for every request.

The current database service exposes functionality such as:

  Method                      Purpose
  --------------------------- -------------------------------------
  `ping()`                    Checks whether PostgreSQL responds
  `query()`                   Executes a parameterized query
  `connect()`                 Acquires a dedicated connection
  `transaction()`             Runs multiple operations atomically
  `onApplicationShutdown()`   Closes the pool during shutdown

### Transactions

Registration can involve several related writes:

1.  Create or retrieve the user.
2.  Assign the default role.
3.  Record required legal consents.
4.  Persist other initial account data.

These should be grouped in a PostgreSQL transaction.

If one database operation fails, the transaction should roll back so the
database does not retain a partially provisioned account.

Example conceptual flow:

``` text
BEGIN
  Create/retrieve user
  Assign default CUSTOMER role
  Record required consent
COMMIT
```

On failure:

``` text
ROLLBACK
```

### Recommended improvements

1.  **Review the global module choice.** `@Global()` makes exported
    providers available without explicit imports. This is convenient,
    but can hide dependencies. Prefer explicit module imports where
    practical, unless there is a clear reason to keep the database
    module global.
2.  **Add migration management.** The existence of SQL migration files
    is good, but the reviewed material did not show a migration runner,
    migration history table, or deployment process.
3.  **Improve observability.** Eventually monitor connection errors,
    query failures, slow queries, and pool saturation.
4.  **Preserve parameterized queries.** Avoid building SQL by
    concatenating user-supplied values.
5.  **Use transactions for related database writes.** Keep transactions
    focused and avoid holding them open while calling external services.

## 4.2 Firebase module

Files:

``` text
modules/firebase/
    firebase-admin.service.ts
    firebase.module.ts
```

The Firebase service initializes Firebase Admin using project
configuration and Application Default Credentials, then exposes Firebase
Auth to other modules.

This is the correct general direction.

### Firebase's responsibility

Firebase Authentication should manage:

-   Email/password registration.
-   Login.
-   Password hashing and storage.
-   Password reset.
-   Email verification.
-   ID token issuance.
-   Refresh-token management.
-   Identity-provider accounts.

Moola should not create its own password storage system.

### Moola's responsibility

Moola should manage:

-   Mapping Firebase UID to a Taanjika user.
-   Creating the Taanjika profile.
-   Account status.
-   Roles and permissions.
-   Artist application and seller state.
-   Business rules and resource ownership.

**Firebase establishes identity. Moola establishes Taanjika account
authority.**

### Service-account credentials

The implementation uses Application Default Credentials. For local
development, `GOOGLE_APPLICATION_CREDENTIALS` can point to a
service-account JSON file.

For production, prefer a managed identity or workload identity when
supported by the hosting platform.

Security requirements:

-   Never commit service-account JSON.
-   Never expose credentials through public frontend environment
    variables.
-   Keep credentials out of source control and logs.
-   Restrict service-account permissions.
-   Use a secret manager or managed identity in production.
-   Do not manually parse credentials unless there is a specific
    requirement.

## 4.3 Authentication module

Files:

``` text
modules/auth/
    decorators/
        current-user.decorator.ts
        roles.decorator.ts
    dto/
        register-profile.dto.ts
    guards/
        email-verified.guard.ts
        firebase-auth.guard.ts
        roles.guard.ts
    auth.controller.ts
    auth.module.ts
    auth.service.ts
```

### A. FirebaseAuthGuard

The guard extracts a Firebase Bearer token:

``` text
Authorization: Bearer <FIREBASE_ID_TOKEN>
```

It verifies the token through Firebase Admin. The reviewed code calls
`verifyIdToken(idToken, true)`, where the second argument enables
revocation checking.

The verified Firebase principal includes identity information such as:

-   Firebase UID.
-   Email.
-   Email verification status.
-   Display name.

This is a good starting point.

However, a valid Firebase identity is not necessarily an authorized
Taanjika account. A Firebase user may:

-   Have no Taanjika profile.
-   Have a suspended Taanjika account.
-   Have a pending Artist application.
-   Have no active seller plan.
-   Lack permission to access a particular resource.

Those are separate account and authorization checks.

### B. CurrentUser decorator

`@CurrentUser()` retrieves the authenticated principal from the request.

This is useful and should be retained.

The target design should distinguish:

**Firebase principal**

``` text
uid
email
emailVerified
```

**Taanjika account context**

``` text
userId
accountStatus
roles
artistStatus
sellerStatus
permissions
```

The Firebase principal proves identity. The Taanjika account context
represents the application's current account and access state.

### C. EmailVerifiedGuard

The guard checks the verified Firebase principal's `emailVerified`
value.

This is appropriate for operations that require a verified email.

The reviewed `AuthModule` provider list did not show this guard being
registered, and the reviewed material did not confirm which routes use
it. Its actual enforcement must therefore be verified.

Not every endpoint necessarily needs verified email. For example, a user
may need to complete initial profile provisioning before verification.
Verification should be required selectively for sensitive or
policy-defined operations.

### D. RolesGuard

The current guard:

1.  Reads required roles from the `@Roles()` decorator.
2.  Checks email verification.
3.  Retrieves the Taanjika profile.
4.  Checks account activity.
5.  Checks whether the profile contains a required role.

The concept is useful, but it has limitations:

-   It only understands broad roles.
-   It cannot express seller approval, subscription state, listing
    entitlements, or resource ownership.
-   It does not establish a reusable account context for later
    controllers and services.
-   The reviewed module provider list did not show the guard being
    registered; dependency-injection registration must be verified.
-   It must be applied consistently, or protected routes may bypass its
    checks.

The target architecture should evolve beyond a role-only guard.

### E. Roles decorator

The existing role type was:

``` ts
type AppRole = "CUSTOMER" | "ARTIST" | "ADMIN";
```

This should be reconsidered.

The agreed Taanjika model is:

-   CUSTOMER is the default general account role.
-   ADMIN is a privileged internal role.
-   Artist is an additional business capability, not an automatically
    assigned general role.

Artist application, approval, seller activation, subscription, and
listing entitlement should be represented separately.

## 4.4 Users module

Files:

``` text
modules/users/
    users.module.ts
    users.repository.ts
    users.service.ts
```

The module currently supports operations such as:

-   Registering/provisioning a profile.
-   Retrieving a profile by Firebase UID.
-   Synchronizing email verification.
-   Ensuring an Admin profile exists.
-   Recording consent.

This separation is good, but the responsibilities need refinement.

### Issue 1: Registration and Artist application are mixed

The current flow appears to create a pending Artist application when a
user registers with Artist intent.

That is not the agreed target design.

Selecting Artist during registration should not mean that a full Artist
application has been submitted.

The desired flow is:

``` text
User registers
    |
    v
Taanjika account created
    |
    v
Default CUSTOMER role and Collector access
    |
    v
User may start Artist onboarding separately
    |
    v
Artist application is completed and submitted
    |
    v
Admin review
    |
    v
Approval
    |
    v
Plan selection and payment
    |
    v
Seller account activation
```

Registration intent may be recorded for onboarding analytics or UX, but
it must not grant Artist privileges or create a submitted application.

### Issue 2: Email verification synchronization

The reviewed synchronization logic updates the database when Firebase
reports a verified email, but may not clear the stored verification
timestamp when the account's email changes and the new email is
unverified.

Verification must relate to the current email address.

The synchronization design should account for:

-   Current Firebase email.
-   Current email verification state.
-   Email changes.
-   Re-verification.
-   Consistency between Firebase and PostgreSQL.

### Issue 3: Consent history

Consent should be treated as historical evidence, not simply overwritten
on every profile synchronization.

Preserve:

-   Consent type.
-   Policy/document version.
-   Acceptance or withdrawal state, as applicable.
-   Timestamp.
-   Relevant source metadata, where appropriate.

Mandatory legal acceptance and optional marketing preferences should be
separate concepts.

### Issue 4: User roles

Assigning CUSTOMER to every new account is consistent with the target
architecture.

However, allowing ARTIST as a generic role risks treating Artist status
as a simple role assignment. Artist access should instead be derived
from the Artist/seller lifecycle and relevant permissions.

## 4.5 Admin bootstrap module

Files:

``` text
modules/admin-bootstrap/
    admin-bootstrap.module.ts
    admin-bootstrap.service.ts
```

The reviewed bootstrap service appears to:

1.  Check whether `ADMIN_BOOTSTRAP_ENABLED` is enabled.
2.  Read configured Admin identity information.
3.  Acquire a PostgreSQL advisory lock.
4.  Check whether bootstrap has already run.
5.  Create or update the Firebase Admin identity.
6.  Create or update the PostgreSQL user.
7.  Assign the ADMIN role.
8.  Update bootstrap state.
9.  Release the lock.

### Advisory locks

A PostgreSQL advisory lock coordinates processes that need exclusive
access to a logical operation.

For example, if two Moola instances start at the same time, both could
attempt to provision the initial Admin. The lock ensures only one
proceeds at a time.

This is a useful technique.

### Recommended changes

Initial Admin provisioning should be a deliberate, controlled
operational task.

Recommendations:

-   Prefer a controlled one-time command or deployment operation over
    silently mutating Admin credentials on every application startup.
-   Avoid keeping a permanent Admin password in ordinary application
    configuration.
-   Do not automatically reset an existing Admin password on every
    deployment.
-   Require MFA for Admin access.
-   Audit Admin creation and privilege changes.
-   Ensure bootstrap cannot unintentionally promote an existing customer
    account.
-   Keep the operation idempotent and protected by appropriate locking.

The current password-version mechanism should be reviewed carefully
because an environment change could trigger an unintended password
rotation.

## 4.6 Health module

The existing health module should be retained.

Health checks should distinguish application liveness from dependency
readiness where appropriate:

-   Liveness: is the process running?
-   Readiness: can the application serve requests, including required
    dependency checks?

Do not expose secrets or sensitive infrastructure details in public
health responses.

------------------------------------------------------------------------

# 5. Important gaps and architectural corrections

## 5.1 File naming consistency

The directory listing used plural names such as:

``` text
auth.services.ts
users.services.ts
database.services.ts
admin-bootstrap.services.ts
```

But imports in the reviewed code appeared to use singular names such as:

``` text
auth.service
users.service
database.service
admin-bootstrap.service
```

This may be a discrepancy in the supplied tree rather than the real
repository.

Verify the actual filenames and imports. Prefer a consistent singular
convention:

-   `auth.service.ts`
-   `users.service.ts`
-   `database.service.ts`
-   `admin-bootstrap.service.ts`

## 5.2 Registration and synchronization endpoint overlap

The current controller exposes registration and synchronization
endpoints that appear to call the same profile-provisioning
implementation.

If both endpoints can create profiles, update names, write consent, and
trigger application creation, their responsibilities overlap.

Recommended direction:

-   Keep one idempotent profile-provisioning/synchronization operation.
-   Handle ordinary profile edits through the Users module.
-   Keep Artist application submission in the Artist Applications
    module.
-   Avoid duplicating business side effects across endpoints.

The exact endpoint contract should be finalized before frontend
integration.

## 5.3 Email uniqueness conflicts

The database has a case-insensitive unique email index, which is useful.

However, an upsert that handles conflicts only on `firebase_uid` may
still fail if another Firebase identity already owns the same email.

Handle this as an explicit domain conflict rather than exposing an
unhandled database error.

The system should define how email changes and account-linking conflicts
are resolved.

## 5.4 Account suspension enforcement

A suspended Taanjika account must not be able to access protected
operations merely because its Firebase token is valid.

Account-status enforcement must apply consistently to protected routes.

Do not rely on a role guard being manually added to every endpoint if
that creates a risk of missed protection.

A global authentication guard with explicit public-route metadata is one
possible design. Alternatively, use explicit controller-level guards
consistently. Choose one policy and test it.

## 5.5 Role-only authorization is insufficient

A role cannot express all Taanjika business rules.

Example:

An Artist may be approved and have a plan, but may have exhausted all
listing slots. The Artist might still edit an existing listing while
being prohibited from creating another one.

That requires permission and entitlement checks, not just a role check.

## 5.6 Configuration validation

The reviewed code showed configuration loading, but not a complete
startup validation schema.

Validate required configuration such as:

-   `DATABASE_URL`
-   Firebase project configuration
-   Terms and Privacy policy versions
-   CORS origins
-   Database pool configuration
-   Environment-specific settings

Fail fast at startup when required configuration is missing or invalid.

Never log secrets.

## 5.7 Rate limiting and security controls

Helmet and CORS are useful foundations, but additional controls are
needed:

-   API rate limiting.
-   Strict DTO validation.
-   Safe and consistent error responses.
-   Audit logging for privileged actions.
-   Admin MFA.
-   Session and token revocation policy.
-   Resource ownership checks.
-   Security-focused automated tests.
-   Monitoring and alerting.

The current CORS `credentials: true` setting is not required for a
Bearer-token-only architecture. If the project later adopts HTTP-only
session cookies, configure credentials, cookie attributes and CSRF
protections deliberately.

------------------------------------------------------------------------

# 6. Target Moola architecture

The following is the recommended target direction. It is not a
requirement to create every module immediately.

``` text
apps/
└── moola/
    ├── database/
    │   └── migrations/
    │       ├── 001_authentication_schema.sql
    │       ├── 002_account_lifecycle.sql
    │       ├── 003_access_control.sql
    │       └── ...
    │
    └── src/
        ├── common/
        │   ├── decorators/
        │   │   ├── public.decorator.ts
        │   │   ├── permissions.decorator.ts
        │   │   └── current-account.decorator.ts
        │   ├── guards/
        │   │   ├── firebase-auth.guard.ts
        │   │   ├── account-context.guard.ts
        │   │   ├── email-verified.guard.ts
        │   │   └── permissions.guard.ts
        │   ├── interfaces/
        │   │   └── authenticated-request.interface.ts
        │   ├── filters/
        │   └── interceptors/
        │
        ├── config/
        │   └── configuration validation
        │
        ├── modules/
        │   ├── database/
        │   ├── firebase/
        │   ├── auth/
        │   ├── users/
        │   ├── access-control/
        │   ├── artist-applications/
        │   ├── artists/
        │   ├── admin/
        │   ├── admin-bootstrap/
        │   ├── audit/
        │   └── health/
        │
        ├── app.module.ts
        └── main.ts
```

## 6.1 Why a `common` area?

Some infrastructure is shared across feature modules.

For example, authentication and authorization guards may be used by:

-   Users.
-   Artist Applications.
-   Artists.
-   Admin.
-   Artwork management.
-   Orders.

Shared decorators, interfaces, filters and guards should not be
duplicated in every feature.

Keep `common` focused on genuinely cross-cutting infrastructure.
Domain-specific business logic should remain in its feature module.

## 6.2 Why an Access Control module?

Authentication and authorization are related but different.

-   Authentication establishes who the user is.
-   Authorization determines what the user can do.

An Access Control module can centralize role/permission evaluation and
provide reusable authorization services.

## 6.3 Why separate Artist Applications and Artists?

An application is a request for approval.

An Artist/seller account is a business capability that may become active
after approval and payment.

A user can have an approved application without having an activated
seller account. These lifecycles should not be represented by one role
flag.

------------------------------------------------------------------------

# 7. Authentication architecture and workflows

## 7.1 Registration

Recommended workflow:

1.  The user opens Darshana.
2.  The user chooses Collector or Artist as a registration intent, if
    that choice remains part of the UX.
3.  Firebase creates the authentication identity.
4.  Firebase returns an ID token.
5.  Darshana sends the token and profile data to Moola.
6.  `FirebaseAuthGuard` verifies the token.
7.  Moola provisions the Taanjika account.
8.  The account receives the default CUSTOMER role and Collector
    functionality.
9.  Required consent records are persisted.
10. PostgreSQL commits the profile transaction.
11. Moola returns the account context.
12. Darshana displays the appropriate onboarding experience.

### Distributed-system consideration

Firebase and PostgreSQL are separate systems. A Firebase account
creation and PostgreSQL transaction cannot be committed as one shared
atomic transaction.

Possible failure:

1.  Firebase identity creation succeeds.
2.  PostgreSQL is unavailable.
3.  Taanjika profile provisioning fails.

This can leave a Firebase identity without a Taanjika profile.

Therefore profile provisioning must be idempotent and safely retryable.

The existing `ON CONFLICT (firebase_uid)` approach is a useful starting
point. It needs deliberate handling of email conflicts and partial
provisioning.

## 7.2 Login

There should be one login process for all Taanjika users.

1.  Darshana uses Firebase Authentication for login.
2.  Firebase returns an ID token.
3.  Darshana sends the token to Moola for protected API calls.
4.  Moola verifies the token.
5.  Moola loads the Taanjika account.
6.  Moola checks account status and returns the current account context.

Moola does not need to implement its own password-based login system.

A separate NestJS `/auth/login` endpoint is not required if login is
handled directly through the Firebase client SDK.

## 7.3 Current-account endpoint

The current `GET /auth/me` endpoint is a useful starting point.

It should become the canonical way for Darshana to retrieve the Taanjika
account context.

The response should provide relevant information such as:

  Information                 Purpose
  --------------------------- --------------------------------------
  Internal user ID            Taanjika/PostgreSQL identity

  Email                       Current account email
  
  Email verification          Verification state
  
  First and last name         Profile information
  
  Account status              Active, suspended or deactivated
  
  Roles                       Broad account roles
  
  Artist application status   Onboarding progress
  
  Seller status               Whether selling capability is active
  
  Permissions                 Actions currently allowed

Avoid exposing internal-only identifiers or sensitive implementation
details unless the frontend genuinely needs them.

The frontend must not invent these values or treat its own cached state
as authoritative.

## 7.4 Email verification

Recommended flow:

1.  User registers through Firebase.
2.  Firebase sends the verification email.
3.  User opens the verification link.
4.  Firebase marks the current email as verified.
5.  Darshana refreshes the Firebase ID token.
6.  Darshana calls Moola.
7.  Moola verifies the updated token.
8.  Moola synchronizes the current email and verification state in
    PostgreSQL.

Email verification does not grant Artist approval, seller activation or
Admin privileges.

## 7.5 Logout and session strategy

For the initial architecture, use **Firebase client-managed
authentication**.

Darshana signs out through Firebase. Firebase manages the identity
session and refresh-token lifecycle.

Moola does not need to create a parallel refresh-token system.

A future server-managed HTTP-only cookie approach is possible,
especially if SSR requirements justify it. However, that approach
requires deliberate cookie security, CSRF protection, session revocation
and logout behavior.

Do not mix both session strategies without a clear design.

------------------------------------------------------------------------

# 8. Authorization architecture

## 8.1 Recommended request pipeline

A protected request should conceptually pass through these stages:

``` text
Incoming request
      |
      v
FirebaseAuthGuard
      |
      v
AccountContextGuard
      |
      v
Account status check
      |
      v
EmailVerifiedGuard (when required)
      |
      v
PermissionsGuard
      |
      v
Resource ownership and business-rule checks
      |
      v
Controller and service
```

Not every route needs every check.

Public art-form browsing, for example, should not require
authentication. Creating a seller listing requires considerably more
checks.

A `@Public()` decorator can mark endpoints that bypass a global
authentication guard. Alternatively, protected guards can be applied
explicitly to controllers. Choose one consistent policy.

## 8.2 Roles versus permissions

The general role model should initially be simple:

-   `CUSTOMER`
-   `ADMIN`

Artist selling access should be determined by the Artist/seller domain,
not by a generic `ARTIST` role alone.

Examples of customer capabilities:

-   Browse products.
-   Manage profile.
-   Place orders.
-   Manage wishlist.
-   Submit bespoke artwork requests.

Examples of Admin capabilities:

-   Review Artist applications.
-   Approve artworks.
-   Manage users.
-   Manage art forms.
-   Manage platform settings.

Examples of active seller capabilities:

-   Manage Artist profile.
-   Create artwork listings.
-   Submit artwork for review.
-   Manage inventory.
-   View seller-related information.

An expired seller plan should not remove the user's Collector
functionality.

## 8.3 Resource ownership

A role or permission is not sufficient to authorize access to a specific
resource.

For example, an Artist may have permission to edit artwork, but only
artwork belonging to that Artist's seller account should be editable,
subject to the artwork's review status.

Moola must determine ownership using the authenticated account's
database identity.

Never trust a `userId`, `artistId`, or owner identifier supplied by the
frontend as proof of ownership.

## 8.4 Account, role and capability are separate concepts

Keep these concepts separate:

-   **Identity:** Firebase UID and provider identity.
-   **Account:** the Taanjika user profile.
-   **Account status:** active, suspended or deactivated.
-   **Role:** broad platform classification, such as CUSTOMER or ADMIN.
-   **Artist application:** onboarding and review state.
-   **Seller capability:** whether selling operations are enabled.
-   **Subscription:** current plan and validity.
-   **Entitlement:** what the seller is allowed to do.
-   **Permission:** an action the account may perform.

This separation prevents a single role value from becoming overloaded
with business state.

------------------------------------------------------------------------

# 9. Database architecture and required evolution

The current authentication migration is a starting point. The database
should evolve through new migrations rather than rewriting
already-applied migration history.

## 9.1 Users table

The current `users` table includes fields such as:

-   `id`
-   `firebase_uid`
-   `email`
-   `first_name`
-   `last_name`
-   `display_name`
-   `email_verified_at`
-   `status`
-   timestamps

This is a reasonable initial user table.

Review and finalize:

-   Unique Firebase UID.
-   Case-insensitive email uniqueness.
-   Account status lifecycle.
-   Deactivation and suspension semantics.
-   Current-email verification consistency.
-   Email change handling.
-   Audit metadata for account-state changes.

## 9.2 User roles

The current role table permits:

-   CUSTOMER
-   ARTIST
-   ADMIN

Recommended initial generic role set:

``` text
CUSTOMER
ADMIN
```

Potential future Admin sub-roles:

-   SUPER_ADMIN
-   ARTIST_ADMIN
-   CONTENT_ADMIN
-   FINANCE_ADMIN
-   OPERATIONS_ADMIN

Do not add all future roles prematurely. The permission model should be
designed around actual Admin responsibilities.

Artist status should live in the Artist/seller domain.

## 9.3 Artist applications

The current application table appears to include:

-   Artist name.
-   Biography.
-   Art forms.
-   Portfolio URL.
-   Application status.
-   Reviewer information.
-   Review note.

The complete Taanjika application process needs more information:

-   Artist identity/profile details.
-   Location.
-   Art-form proficiency.
-   Degree/certificate information, where applicable.
-   Five available artworks.
-   Artwork details and image references.
-   Agreement acceptance.
-   Commission agreement.
-   Submission timestamp.
-   Admin review decisions.
-   Change requests.
-   Approval/rejection details.

Recommended application states:

``` text
DRAFT
SUBMITTED
UNDER_REVIEW
CHANGES_REQUESTED
APPROVED
REJECTED
WITHDRAWN
```

Maintain review history rather than storing only the latest review note.

## 9.4 Seller account and subscription

These areas were not present in the reviewed structure and need to be
designed.

The data model should represent:

-   Seller activation.
-   Subscription plan.
-   Subscription payment.
-   Subscription validity.
-   Listing allowance.
-   Listings consumed or reserved.
-   Subscription expiry.
-   Suspension or termination.

Initial plan information supplied for Taanjika:

  Plan         Annual price   Artwork allowance
  ---------- -------------- -------------------
  Base               ₹2,500                   5
  Pro                ₹5,000                  10
  Advanced          ₹10,000                  20

Moola must enforce entitlements. The frontend must never decide or grant
listing capacity.

Payment verification must be performed server-side through the payment
provider's trusted integration/webhook flow. A client-side success
screen is not proof of payment.

## 9.5 Consent history

Preserve:

-   Consent type.
-   Policy/document version.
-   Acceptance or withdrawal state, where applicable.
-   Timestamp.
-   Relevant source metadata.

Keep mandatory legal acceptance separate from optional marketing
preferences.

## 9.6 Audit log

Introduce an Audit module and persistent audit storage for important
security and business events.

Examples:

-   Admin creation.
-   Admin role/permission changes.
-   Account suspension and reinstatement.
-   Artist application decisions.
-   Seller activation.
-   Subscription-related administrative actions.
-   Sensitive account changes.

Audit records should identify:

-   Actor.
-   Action.
-   Affected entity.
-   Timestamp.
-   Relevant non-sensitive metadata.

Never log passwords, Firebase ID tokens, service-account credentials or
other secrets.

## 9.7 Sessions table

With Firebase client-managed sessions, Moola does not initially need to
store Firebase refresh tokens or build a duplicate refresh-token
mechanism.

A Taanjika session/device-tracking model can be introduced later if a
concrete requirement exists.

------------------------------------------------------------------------

# 10. Module responsibilities and interactions

  -----------------------------------------------------------------------
  Module                              Responsibility
  ----------------------------------- -----------------------------------
  Firebase                            Firebase Admin initialization and
                                      identity-provider operations

  Auth                                Authentication orchestration,
                                      profile provisioning and
                                      current-account resolution

  Users                               User profile and account management

  Access Control                      Roles, permissions and access
                                      decisions

  Artist Applications                 Artist onboarding and application
                                      review lifecycle

  Artists                             Approved Artist profiles and seller
                                      capabilities

  Admin                               Internal administrative operations

  Admin Bootstrap                     Initial privileged-account
                                      provisioning

  Audit                               Security and business activity
                                      history

  Database                            PostgreSQL connectivity and
                                      transactions

  Health                              Application and dependency health
                                      checks
  -----------------------------------------------------------------------

Example seller-listing request:

``` text
Darshana
   |
   v
FirebaseAuthGuard
   |
   v
AccountContextGuard
   |
   v
PermissionsGuard
   |
   v
ArtistsController
   |
   v
ArtistsService
   |
   +---- AccessControlService
   |
   +---- Subscription/entitlement checks
   |
   v
ArtistsRepository
   |
   v
PostgreSQL
```

Controllers should remain thin. Services should coordinate business
operations. Repositories should handle persistence.

------------------------------------------------------------------------

# 11. Darshana and Moola responsibilities

Authentication is one system spanning the frontend, Firebase and
backend.

  Responsibility                            Owner
  ----------------------------------------- ---------------------
  Registration UI                           Darshana
  Firebase registration                     Firebase client SDK
  Firebase login                            Firebase client SDK
  Password reset                            Firebase client SDK
  Verification email                        Firebase client SDK
  ID-token management                       Firebase client SDK
  Token verification                        Moola
  Taanjika profile creation                 Moola
  Account status                            Moola/PostgreSQL
  Roles and permissions                     Moola/PostgreSQL
  Artist application lifecycle              Moola
  Seller plan and entitlement enforcement   Moola
  Route experience and UI state             Darshana

Darshana can use Moola's account response to decide which interface to
show. It cannot grant itself Admin or seller privileges.

The backend must enforce every protected operation independently of
frontend visibility.

------------------------------------------------------------------------

# 12. File-by-file action plan

  --------------------------------------------------------------------------
  Existing file/area                     Recommended action
  -------------------------------------- -----------------------------------
  `database/database.module.ts`          Retain; review global dependency
                                         design

  `database/database.service.ts`         Retain; improve operational
                                         handling over time

  `database/database.constants.ts`       Retain

  `firebase/firebase-admin.service.ts`   Retain; review credential
                                         initialization

  `firebase/firebase.module.ts`          Retain

  `auth/auth.controller.ts`              Update endpoint responsibilities

  `auth/auth.service.ts`                 Update registration and
                                         current-account orchestration

  `auth/auth.module.ts`                  Register required providers and
                                         dependencies

  `auth/firebase-auth.guard.ts`          Retain and strengthen request
                                         identity handling

  `auth/email-verified.guard.ts`         Retain and apply selectively

  `auth/roles.guard.ts`                  Evolve into a complete
                                         authorization system

  `auth/roles.decorator.ts`              Reconsider Artist as a generic role

  `auth/current-user.decorator.ts`       Extend or complement with account
                                         context

  `auth/dto/register-profile.dto.ts`     Update registration intent and
                                         validation

  `users/users.repository.ts`            Update provisioning, verification
                                         and consent persistence

  `users/users.service.ts`               Separate account provisioning from
                                         Artist onboarding

  `admin-bootstrap/*`                    Retain with operational and
                                         security improvements

  `health/*`                             Retain
  --------------------------------------------------------------------------

New areas to introduce:

-   `common/decorators`
-   `common/guards`
-   `common/interfaces`
-   Configuration validation
-   `access-control`
-   `artist-applications`
-   `artists`
-   `admin`
-   `audit`
-   Migration management
-   Automated tests

------------------------------------------------------------------------

# 13. Testing strategy

Authentication is not complete merely because registration and login
work.

Test the full identity, account and authorization lifecycle.

  -----------------------------------------------------------------------
  Scenario                            Expected result
  ----------------------------------- -----------------------------------
  User registers successfully         Firebase identity and Taanjika
                                      profile created

  Same registration request is        No duplicate profile
  retried                             

  Invalid Firebase token              `401 Unauthorized`

  Expired or revoked Firebase token   `401 Unauthorized`

  Firebase user has no Taanjika       Explicit profile-not-found or
  profile                             provisioning response

  User has unverified email           Protected operation rejected where
                                      verification is required

  Suspended user requests protected   Access denied
  resource                            

  Collector requests seller-only      Access denied
  operation                           

  Approved Artist without active plan Access denied
  creates listing                     

  Active Artist exceeds listing       Creation rejected
  allowance                           

  Artist edits another Artist's       Access denied
  artwork                             

  Customer attempts Admin operation   Access denied

  Admin accesses a permitted          Request succeeds
  operation                           
  -----------------------------------------------------------------------

Build tests alongside each phase.

Recommended test layers:

1.  **Unit tests:** service logic, permission evaluation, state
    transitions.
2.  **Integration tests:** repository/database behavior and
    transactions.
3.  **End-to-end tests:** HTTP routes, guards and request lifecycle.
4.  **Security tests:** revoked tokens, suspended users, privilege
    escalation attempts, ownership violations and entitlement bypass
    attempts.

------------------------------------------------------------------------

# 14. Implementation roadmap

## Phase 1 --- Review and stabilize the foundation

-   Confirm actual filenames and imports.
-   Review package dependencies and scripts.
-   Review environment configuration.
-   Confirm database migrations run successfully.
-   Review Firebase credentials.
-   Verify database connectivity.
-   Fix TypeScript and architectural inconsistencies.

**Deliverable:** stable and verified backend foundation.

## Phase 2 --- Finalize the authentication data model

-   Finalize users and account status.
-   Finalize generic roles.
-   Separate Artist application from registration.
-   Finalize consent history.
-   Design seller account and subscription entities.
-   Define account lifecycle transitions.

**Deliverable:** approved database design and migration plan.

## Phase 3 --- Complete Firebase authentication integration

-   Firebase token verification.
-   Registration profile provisioning.
-   Idempotent synchronization.
-   Current-account endpoint.
-   Email verification synchronization.
-   Missing-profile and conflicting-identity handling.

**Deliverable:** reliable registration and authentication.

## Phase 4 --- Build account context and access control

-   Account-context resolution.
-   Account-status enforcement.
-   Role checks.
-   Permission checks.
-   Resource ownership checks.
-   Public and protected route handling.

**Deliverable:** centralized authorization system.

## Phase 5 --- Implement Admin identity and security

-   Controlled Admin provisioning.
-   Admin role assignment.
-   MFA policy.
-   Admin permissions.
-   Audit events.
-   Privileged-operation security.

**Deliverable:** secure internal administrative access.

## Phase 6 --- Implement Artist onboarding

-   Application creation.
-   Draft and submission.
-   Supporting information and uploads.
-   Admin review.
-   Approval, rejection and change requests.
-   Application history.

**Deliverable:** complete Artist application lifecycle.

## Phase 7 --- Seller activation and subscription

-   Plan selection.
-   Payment integration.
-   Payment verification.
-   Seller activation.
-   Listing entitlements.
-   Subscription expiry and suspension.

**Deliverable:** operational seller access control.

## Phase 8 --- Security, testing and production readiness

-   Unit tests.
-   Integration tests.
-   Authentication security tests.
-   Authorization tests.
-   Rate limiting.
-   Logging and monitoring.
-   Production configuration and deployment checks.

**Deliverable:** production-ready authentication and account
infrastructure.

------------------------------------------------------------------------

# 15. Immediate next steps

Do not begin by building every missing module. First stabilize the
foundation and finalize the domain model.

## Step 1 --- Stabilize current files

Verify:

-   Actual filenames and import paths.
-   Installed dependencies and scripts.
-   Environment configuration.
-   TypeScript and Nest CLI configuration.
-   Migration execution.
-   Firebase credential setup.
-   Database connectivity.

## Step 2 --- Finalize authentication domain decisions

The following decisions should be treated as the target architecture
unless a deliberate product decision changes them:

1.  CUSTOMER is the default role.
2.  ADMIN is a privileged internal role.
3.  Artist is an additional capability, not an automatically assigned
    role.
4.  Artist registration intent does not create a submitted application.
5.  Artist approval and seller activation are separate.
6.  Subscription expiry does not remove Collector access.
7.  Account suspension is independent of Artist status.
8.  Moola is the authority for account status and authorization.
9.  Firebase is the identity provider.
10. PostgreSQL is the source of truth for Taanjika business state.

## Step 3 --- Finalize database design

Agree on the entities and lifecycle transitions before adding more
services.

## Step 4 --- Complete authentication and account context

Then update guards, services, repositories and controllers.

## Additional files needed for the next review

To verify the actual backend foundation, inspect:

1.  `apps/moola/package.json` --- dependencies, scripts and versions.
2.  `apps/moola/.env.example` --- expected configuration variables.
3.  `apps/moola/tsconfig.json`.
4.  `apps/moola/tsconfig.build.json`.
5.  `apps/moola/nest-cli.json`.
6.  Migration execution setup, if one exists.
7.  Actual file tree and filenames.
8.  Firebase client configuration in Darshana when frontend integration
    begins.

**Do not share the real `.env` or `firebase-service-account.json`.**
Only the example environment file and non-secret configuration are
needed.

------------------------------------------------------------------------

# 16. Architecture principles and decisions

These principles should guide future implementation.

## 16.1 One person, one Taanjika account

A user should not need separate accounts to act as a Collector and an
Artist.

Artist is an additional capability attached to the same Taanjika
account.

## 16.2 Firebase owns identity authentication

Firebase manages passwords, login, verification, tokens and provider
identity.

Moola verifies Firebase tokens and maps the identity to a Taanjika
account.

## 16.3 PostgreSQL owns business state

PostgreSQL is authoritative for:

-   Taanjika profile.
-   Account status.
-   Roles.
-   Artist application state.
-   Seller activation.
-   Subscription and entitlements.
-   Audit history.

Firebase custom claims may be used selectively for lightweight identity
metadata, but should not replace PostgreSQL as the authority for
frequently changing business permissions.

## 16.4 Authentication is not authorization

A valid token proves identity. It does not automatically grant access to
every Taanjika operation.

## 16.5 Roles are not business lifecycle states

Do not encode application approval, subscription validity, seller
activation and listing capacity into one role.

## 16.6 The backend enforces permissions

Frontend route protection improves user experience, but it is not a
security boundary.

Every protected backend operation must enforce its own authorization and
ownership rules.

## 16.7 Admin is an internal privileged identity

Admin accounts must be provisioned through a controlled process,
protected with MFA, assigned least privilege and audited.

Admin must never be publicly registrable.

## 16.8 Account suspension is independent

Suspending an account must be modeled separately from Artist approval or
subscription state.

## 16.9 Provisioning must be retry-safe

Firebase and PostgreSQL are separate systems. Profile provisioning must
handle partial failure and retries without creating duplicate Taanjika
accounts.

## 16.10 Build incrementally and test each phase

Stabilize the foundation, finalize the data model, implement
authentication, then authorization, Admin, Artist onboarding and seller
activation.

------------------------------------------------------------------------

## Final recommendation

The current Moola implementation is a useful foundation. Retain the
PostgreSQL connection layer, Firebase Admin integration, token
verification approach, repository pattern, DTO validation and the
general separation between Auth and Users.

The most important next architectural work is to:

1.  Stabilize the existing code and configuration.
2.  Finalize the account, role and Artist capability model.
3.  Evolve the database schema through tracked migrations.
4.  Make profile provisioning idempotent and reliable.
5.  Introduce a reusable Taanjika account context.
6.  Replace role-only authorization with permission, ownership and
    business-rule enforcement.
7.  Build Artist application and seller activation as separate domains.
8.  Add Admin security, audit logging and automated tests.

**The intended outcome is a modular, secure Moola backend in which
Firebase establishes identity, PostgreSQL maintains Taanjika account
state, and NestJS consistently enforces authorization and business
rules.**
