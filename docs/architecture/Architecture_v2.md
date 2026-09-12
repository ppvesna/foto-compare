# Architecture v2

Status: accepted; incremental implementation in progress

Project: `foto-compare` / Trimatrix

Scope: long-term architecture without rewriting the working application

## 1. Purpose

Architecture v2 prepares the application for Free, Pro, and Enterprise editions,
authentication, subscriptions, payments, cloud synchronization, AI, OCR,
barcode recognition, reports, analytics, licensing, local and remote storage,
and offline work.

This is an evolutionary architecture. The current application remains operational.
Existing screens and services are migrated only when a product change requires it.
In particular, Architecture v2 does not require an immediate refactor of
`CompareScreen`.

The implemented boundaries include `lib/features/auth`, `lib/features/protocols`,
`lib/features/references`, the first `billing`, `organization`, customer-directory,
and production workflow contracts, plus the initial `capabilities/storage` contract
and local settings adapter. The auth boundary currently owns editable current-profile
data; sign-in, registration, and invitation completion now share an adaptive form UI
with explicit password visibility controls.
Entitlements and organization permissions now reach the current application shell as
typed snapshots. Existing storage keys, file names, JSON, and current user access remain
compatible. The current test environment supports organization access, invitations,
personal/working entitlement separation, customer and job data, private Storage,
cloud protocols, secure chat, and test billing. The exact applied-migration ledger
must still be audited before production.

## 2. Architectural decision

The target is a **modular monolith with vertical feature modules**, ports and
adapters at external boundaries, and a local-first data model.

This choice is preferred over a full rewrite, microservices, or separate Flutter
applications for each commercial edition because it:

- preserves the current product and delivery speed;
- keeps deployment and debugging simple;
- allows modules to be separated later if a real scaling need appears;
- prevents Flutter, Supabase, SQLite, or a payment provider from becoming domain
  dependencies;
- supports gradual migration through adapters around the existing code.

## 3. Core principles

1. One Flutter codebase serves all editions.
2. Free, Pro, and Enterprise are defined by entitlements, not scattered plan checks.
3. Domain rules do not depend on Flutter widgets or infrastructure SDKs.
4. External systems are accessed through abstract ports.
5. Every external port has a mock or in-memory implementation.
6. Local storage supports the working offline state; cloud storage synchronizes it.
7. Completed inspection protocols are immutable and reproducible.
8. Images, metadata, and derived analysis artifacts have separate storage policies.
9. New modules do not import the internals of legacy screens or services.
10. Complexity is added only when a real feature needs it.

## 4. High-level structure

The future structure is divided into five areas:

- `app`: startup, navigation, dependency composition, session, and application shell;
- `core`: stable technical primitives shared by all modules;
- `shared`: reusable presentation components with no business ownership;
- `features`: user-facing business capabilities, led by the inspection workflow;
- `capabilities`: replaceable technical engines used by features;
- `infrastructure`: concrete SDK, database, platform, and network adapters;
- `legacy`: a logical boundary around existing code during migration.

The detailed folder and module catalog is defined in
[Module_Guide.md](Module_Guide.md).

## 5. Dependency direction

Within a mature feature, the allowed direction is:

`presentation -> application -> domain`

Infrastructure implements domain or application ports and points inward. The domain
never imports infrastructure. The `app` composition root is the only location that
selects real, mock, or in-memory implementations.

Feature-to-feature communication uses published contracts. A feature may not import
another feature's widgets, database tables, private models, or internal services.
Technical capabilities such as OCR or color analysis do not depend on user-facing
features.

## 6. Commercial editions

Free, Pro, and Enterprise must not become separate source trees. Access is controlled
by `EntitlementService`, which answers capability questions such as:

- whether exact full-resolution Delta E is available;
- how many references, users, or checks are allowed;
- whether PDF reports, cloud images, AI, or organization features are enabled;
- whether an offline license remains valid.

`SubscriptionService` describes plan state. `PaymentService` handles transactions and is
used only by billing presentation/application code. Compare, OCR, reports, and other
product modules ask only for entitlements. This also supports Enterprise contracts that
do not use the same payment flow as individual subscriptions.

Current implementation note: `EntitlementService`, plan presets, limits, `PaymentService`,
mocks, and Supabase adapters exist. Migration `019` adds server-owned prices, safe billing
profiles, test activation records, and assignment-backed `current_entitlement_v4`.
Accounts without that function continue to use the older snapshots during rollout. Card
numbers and security codes are never accepted or stored by the Flutter application.
Migration `025` separates plan definition from measured usage through
`CheckUsageService`. The server records only completed checks, uses one UTC-day counter
per organization or personal account, and performs the final quota check under an
advisory transaction lock. Re-saving the same protocol ID does not consume quota again.

### 6.1 Organization and job access

Plan, organization role, and access to a production job are independent dimensions.
The organization role model is intentionally small:

- `owner`: exactly one organization owner; controls billing, ownership transfer, and
  critical organization settings;
- `admin`: manages the organization's jobs, members, and working settings, but cannot
  control ownership or billing;
- `employee`: sees assigned jobs and receives working actions from job functions;
- `customer`: sees only explicitly assigned jobs and may view, comment, and approve;
- `personal`: a user outside an organization, with full control of personal work within
  the selected plan.

Manager, designer, and inspection specialist are job functions, not organization
roles. One employee may have several functions in one job and different functions in
another. Owner and admin can see all jobs in their organization. Employee and customer
access requires a `JobParticipant` assignment. This same job boundary must later protect
chat messages, protocols, and image assets through server-side RLS.

Legacy role values remain readable during migration: `operator`, `technologist`, and
`member` map to employee; `viewer` maps to customer. The obsolete migration `005`
retains the old role model and must not be applied.

Current administration checkpoint: organization creation, exact nickname discovery,
member listing, and role assignment are exposed through a replaceable service contract.
The Supabase adapter uses security-definer RPCs prepared in migration `006`; direct
client writes are not the authority for role changes. Migrations `007–008` read
server-managed personal plan data directly so subscription changes do not depend on
JWT refresh. Migration `009` adds an organization-aware entitlement snapshot: personal
plan data remains visible, while capabilities and limits come from the effective
organization plan. Migration `019` makes an organization access assignment the direct
authority after its owner activates a subscription. Owner metadata remains only as a
compatibility fallback for organizations that have not yet received that assignment.

Migration `010` adds pending invitations keyed by normalized email, seat-limit
enforcement, initial employee functions, and atomic invitation acceptance for the
matching confirmed account. Owners never create or receive employee passwords.
Migration `011` adds recovery for an interrupted invite callback. It reuses the Auth
account identified by the same normalized email, reactivates an expired or cancelled
invitation, releases stale reservations, and keeps nickname ownership bound to the
same user identity.
Nickname authentication is isolated in an unauthenticated Edge Function that accepts
credentials and returns a Supabase session; the nickname-to-email mapping is no longer
publicly readable. Email delivery and nickname login must be deployed and rate-limited
as server functions, not implemented in the Flutter client.

Migration `012` introduces the first job-scoped server model: an organization customer
directory, customer-to-user and primary-manager links, unconfirmed customer requests,
production jobs, participants, and RLS. Operators select an approved customer; when the
customer is absent, they submit the name from the technical specification and continue
the inspection. Owner or admin later resolves the request. Job and participant RLS must
pass staged server tests before it becomes the security boundary for protocols, assets,
and chat. Migration `016` prepares chat isolation by reusing the existing chat tables,
removing prototype-wide policies, and applying organization membership or
`can_view_production_job_v1` to every visible thread and message. Owner-to-employee
Realtime messaging has passed a two-account server test. Migration `017` adds an
explicit customer release boundary: a job remains internal until an owner, admin, or
assigned manager shares it. Sharing exposes only that job thread and its job-scoped
protocols and assets; the organization team thread remains internal.
Migration `022` keeps representatives synchronized with active confirmed jobs of their
customer without changing that release state. Publication, revocation, preserved chat
history, and two representatives on one shared job have passed the manual role test.
Migration `024` adds ordinary job-chat attachments as private Storage objects below a
dedicated `chat` subpath. Messages keep typed metadata only; object reads continue to
use `can_view_production_job_v1`, and object mutation remains owner-scoped for customer
uploads.

## 7. Inspection domain

The professional inspection record is modeled around:

- `ProductionJob`: the operator's work or order number;
- `Reference`: a logical approved reference;
- `ReferenceVersion`: a concrete reference image and its revision;
- `CalibrationProfile`: anchors, crop, transform, and calibration settings;
- `Sample`: one photographed or loaded print sample;
- `Check`: an execution of the inspection pipeline;
- `CheckProtocol`: immutable stages, metrics, findings, and verdict;
- `ImageAsset`: source image, preview, difference map, or report attachment.

Every entity receives a client-generated stable UUID before synchronization. A check
protocol records the comparison engine version, thresholds, color settings,
calibration data, source asset IDs, device context, operator, and timestamps. This
makes old results interpretable after the algorithm evolves.

Current implementation note: the first `production` domain foundation defines
`ProductionJob`, stable job IDs, `JobParticipant`, job functions, and the effective job
access policy. A narrow service now opens or updates the active server job from the
legacy comparison screen without refactoring that screen. Customer identity is stored
in new local protocols. Samples, remote protocol synchronization, and image assets
remain separate future steps.

## 8. Comparison pipeline

The `inspection` feature owns the operator workflow but not the image algorithms.
`CompareEngine` is the boundary of deterministic image comparison. It coordinates
alignment, geometry, color analysis, and map generation without depending on UI. OCR,
barcode recognition, AI analysis, and report generation remain separate providers
coordinated by the inspection application layer.

The current implementation can initially be exposed through a legacy adapter. Web
Worker, Dart, OpenCV, or future server engines are concrete adapters behind the same
capability interfaces. Exact and preliminary calculations must state their precision
and engine version in the result.

## 9. Local-first data and synchronization

The local database holds working metadata, protocols, pending commands, and asset
references. Binary images may remain device-only, be uploaded on demand, or follow an
organization policy.

Trimatrix is the inspection tool and control plane, not the automatic owner of source
images. An image is owned by a user or organization and may live on the device, in
Supabase Storage, in a personal Google Drive, or in an organization drive. Trimatrix
stores the stable asset ID, provider reference, protocol relationship, and access
policy. Application authentication and storage-provider authorization are separate:
signing in to Trimatrix never grants Google Drive access.

Effective access to an asset is the intersection of product entitlement, organization
role permission, access to the production job, and availability of the object in its
storage provider. Roles are presets of explicit permissions rather than a rigid
inheritance tree.

Cloud synchronization uses an Outbox pattern:

1. a local transaction saves the business change and an outbox item;
2. a background synchronizer uploads pending changes when connectivity permits;
3. successful remote acknowledgement marks the item complete;
4. retries are idempotent;
5. deletions use tombstones so they can synchronize safely.

Mutable records use versions and explicit conflict policy. Completed protocols are
append-only. The synchronization module exchanges contracts with repositories and
does not read feature UI state.

## 10. External services

Supabase remains a valid first implementation for authentication, database, and
object storage, but it is an adapter rather than the architecture itself. The same
rule applies to ML Kit, browser Worker APIs, payment SDKs, PDF libraries, and future AI
providers.

Provider-specific request and response objects are converted at the adapter boundary.
They must not leak into domain models or presentation state.

## 11. Security and privacy

- Secrets for AI and payment providers are never embedded in the Flutter client.
- Authentication tokens use platform-secure storage where available.
- Supabase data is protected by organization-aware row-level security.
- Cloud image access uses short-lived signed URLs.
- Enterprise roles and membership are verified server-side.
- License claims are signed and may include a controlled offline grace period.
- Sensitive operations create audit events without logging image content or secrets.
- Image retention, export, and deletion policies are configurable per organization.

Client-side checks improve UX but are not the final authority for paid or privileged
server operations.

## 12. Dependency composition

Architecture v2 uses constructor injection and a small composition root. A large
dependency-injection framework is not required initially. The current state management
approach can remain inside legacy code; new presentation modules should use one
consistent approach selected when the first module is implemented.

Tests compose features with mocks and in-memory repositories. Production composition
selects local, Supabase, platform, and licensed adapters.

## 13. Quality strategy

- Domain and application rules receive unit tests without Flutter bindings.
- Provider contracts receive adapter contract tests.
- Compare engines use fixed image fixtures and versioned expected metrics.
- Repository and sync tests cover retries, conflicts, tombstones, and migrations.
- Critical operator flows receive integration and browser tests.
- Performance budgets are recorded for crop, alignment, preliminary comparison, OCR,
  and exact Delta E.

## 14. Observability

Analytics and diagnostics are separate. Product analytics records consented business
events. Diagnostics records timing, engine version, failures, device class, and Worker
availability. Neither may upload source images or extracted text by default.

## 15. Explicit non-goals

Architecture v2 does not require:

- microservices;
- event sourcing for the entire application;
- separate Free, Pro, and Enterprise apps;
- immediate replacement of Supabase;
- immediate migration of existing screens;
- a universal base repository or generic service abstraction;
- mocks for pure deterministic domain functions.

## 16. Evolution rule

New functionality is implemented behind Architecture v2 boundaries. Existing code is
wrapped first and moved only when necessary. Old code is deleted only after all callers
use the new contract and equivalent behavior has been verified.

The safe migration sequence is defined in [Roadmap.md](Roadmap.md).
