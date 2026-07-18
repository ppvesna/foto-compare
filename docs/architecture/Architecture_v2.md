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

The first implemented boundary is `lib/features/protocols`. Protocol domain models
are separated from the current SharedPreferences adapter and exposed through one
public module entry. Existing storage keys and JSON remain compatible.

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

`SubscriptionService` describes plan state. `PaymentService` handles transactions.
Neither is called directly by Compare, OCR, reports, or settings. Those modules ask
only for entitlements. This also supports Enterprise contracts that do not use the
same payment flow as individual subscriptions.

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
