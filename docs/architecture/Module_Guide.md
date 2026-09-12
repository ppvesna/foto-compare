# Architecture v2 Module Guide

Status: accepted; updated for the current migration checkpoint

Purpose: define ownership, public contracts, mocks, and dependency rules

## 1. Target layout

```text
lib/
  app/
  core/
  shared/
  features/
    auth/
    organization/
    capture/
    inspection/
    references/
    production/
    protocols/
    reports/
    billing/
    collaboration/
    settings/
  capabilities/
    alignment/
    color_analysis/
    geometry_analysis/
    ocr/
    barcode/
    ai/
    sync/
    storage/
    analytics/
    licensing/
  infrastructure/
    local/
    remote/
    platform/
  legacy/
```

This is a destination map, not an instruction to move current files. A folder is
created only when the first approved migration step needs it.

Currently implemented Architecture v2 modules:

```text
lib/features/auth/
  domain/account_profile.dart
  domain/account_profile_service.dart
  infrastructure/supabase_account_profile_service.dart
  testing/mock_account_profile_service.dart
  auth.dart

lib/features/protocols/
  domain/check_protocol.dart
  infrastructure/check_history_service.dart
  protocols.dart

lib/features/references/
  domain/layout_profile.dart
  domain/saved_reference.dart
  infrastructure/layout_profile_storage.dart
  infrastructure/reference_storage.dart
  references.dart

lib/features/billing/
  domain/entitlement.dart
  domain/entitlement_service.dart
  infrastructure/legacy_entitlement_service.dart
  infrastructure/supabase_entitlement_service.dart
  testing/mock_entitlement_service.dart
  billing.dart

lib/features/organization/
  domain/organization_access.dart
  domain/organization_access_service.dart
  domain/organization_administration_service.dart
  domain/customer_directory_service.dart
  domain/organization_customer.dart
  domain/organization_member.dart
  infrastructure/supabase_customer_directory_service.dart
  infrastructure/supabase_organization_administration_service.dart
  infrastructure/supabase_organization_access_service.dart
  testing/mock_customer_directory_service.dart
  testing/mock_organization_administration_service.dart
  testing/mock_organization_access_service.dart
  organization.dart

lib/features/production/
  domain/job_access.dart
  domain/production_job.dart
  domain/production_job_service.dart
  infrastructure/supabase_production_job_service.dart
  testing/mock_production_job_service.dart
  production.dart

lib/capabilities/storage/
  domain/cloud_storage.dart
  domain/storage_settings.dart
  infrastructure/storage_settings_service.dart
  testing/mock_cloud_storage.dart
  storage.dart
```

Other existing files remain in their legacy locations until their individual migration
step is approved and verified.

## 2. Internal module layout

A feature may use these internal areas:

- `domain`: entities, value objects, domain policies, and repository ports;
- `application`: use cases, commands, queries, and orchestration;
- `presentation`: screens, controllers, state, and view models;
- `infrastructure`: feature-specific adapters when a global adapter is not appropriate;
- `public`: the small contract intentionally exposed to other modules.

Small modules should stay small. Empty layers and generic base classes are not required.

## 3. Foundation modules

### app

Owns startup, routes, application session, current organization, dependency composition,
and top-level error handling. It may depend on all public module contracts. Business
rules do not belong here.

### core

Owns stable primitives: typed IDs, `Result`-style outcomes, application errors, clock,
ID generation, pagination, configuration contracts, and common policy types. It must
not contain feature-specific entities or vendor SDK types.

### shared

Owns reusable UI controls, formatting, and presentation helpers. It is not a dumping
ground for business services. A component used by only one feature stays in that
feature.

### legacy

Represents existing code during migration. It is a logical boundary first; existing
files do not need to move. New modules may call a documented legacy adapter, but they
must not import legacy screens or mutable screen state.

## 4. Feature modules

### auth

Responsibilities: sign-in, registration, recovery, session, and user profile.

Public contracts: `AuthService`, `AccountRepository`, `SessionReader`.

Dependencies: core, licensing/security contracts, and a remote authentication adapter.
It does not own payments or feature entitlements.

Current foundation: `AccountProfileService`, its Supabase adapter, and mock load and
update the current user's email, nickname, and optional display name. Nickname
uniqueness remains enforced by `user_profiles`; the adapter also refreshes Supabase Auth
metadata so the application shell reflects a saved profile without a new sign-in.

### organization

Responsibilities: organizations, memberships, the small owner/admin/employee/customer
role set, seats, and organization policy. Owner and admin remain distinct: only the
owner controls billing, ownership transfer, and organization deletion.

Public contracts: `OrganizationRepository`, `MembershipRepository`,
`OrganizationContext`.

Dependencies: auth identity, sync, and licensing. A personal account may use a
single-member organization rather than a separate data model.

Manager, designer, and inspection specialist do not belong in this module as roles.
They are assignments inside a production job.

Current administration foundation: the owner/admin policy, public service contract,
Supabase RPC adapter, mock, and settings UI exist. Migration `006` provides organization
creation, exact nickname lookup, member listing, assignment, and current membership
snapshot. Migration `009` adds organization-plan inheritance while preserving the
member's personal plan.
Migration `010` adds invitations, seat limits, member function defaults, and a unified
active/pending participant list. The Edge Function adapter sends the email without
exposing service credentials to Flutter. Owner bootstrap, employee assignment, and plan
inheritance and invitation completion are verified.
Migration `011` makes a one-time email callback recoverable: the same Auth account and
seat are reused, and the owner may safely resend the invitation.

The participant UI also changes an active member's role through the same protected RPC.
Owner may appoint admin, employee, or customer. Admin may change only employee and
customer accounts; owner and peer-admin records are excluded from the admin editor.

Migration `012` and the customer-directory contract add approved customers, responsible
employee and customer-account links, and an owner/admin administration UI. Employees can
read active customers and submit an unconfirmed name from the technical specification;
they cannot create directory entries directly. The test environment supports this
workflow. Customer publication and revocation through migration `017` have passed the
dedicated multi-account manual test; the organization team chat remained hidden.
Migration `020` assigns sequential customer codes atomically per organization. The UI
uses the simpler terms “responsible employee” and allows any active non-customer member
to be selected without turning “manager” into an organization role.
Migration `021` exposes every active or pending representative of a customer. The
directory renders one row per representative while keeping the customer as a single
entity; customer-detail updates no longer replace existing representative links.
The existing-customer row exposes a direct add-representative action. In that mode the
customer identity is fixed, and pasted display labels are matched back to an existing
customer so that a representative invitation cannot create a duplicate directory entry.
Migration `022` synchronizes those links into active confirmed production jobs. Job
assignment and customer publication remain separate: a customer participant can read
the job only while its explicit customer-access state is `shared`.
Migration `023` gives Pro separate server-enforced pools of 20 internal team seats and
20 customer-representative seats. Enterprise keeps both pools unlimited. The client
uses these limits only for an early, non-authoritative UX check; server errors remain
authoritative and preserve the representative draft so the user does not re-enter it.

### inspection

Responsibilities: run an inspection, coordinate stages, expose progress, collect
findings, and produce a protocol draft.

Public contracts: `CompareEngine`, `RunInspection`, `InspectionProgress`,
`ComparisonResult`.

Dependencies: references, production, protocols, alignment, color analysis, geometry
analysis, OCR, barcode, AI, and entitlements through public interfaces. It must not
depend on payment SDKs, Supabase tables, or report rendering.

### capture

Responsibilities: camera source, lighting, optical filter, exposure metadata, white
balance, resolution, and future device control. Capture settings describe how an image
was obtained; they do not modify an already loaded sRGB image during comparison.

Public contracts: `CaptureDevice`, `CameraCaptureSettingsRepository`, `CaptureMetadata`.

Dependencies: platform camera adapter and settings. Inspection receives a capture
metadata snapshot for the protocol.

### references

Responsibilities: approved references, versions, image identity, calibration profiles,
selection, retention, and reference assets.

Public contracts: `ReferenceRepository`, `CalibrationProfileRepository`,
`ReferenceSelectionService`.

Dependencies: storage and sync ports. It does not own inspection history.

### production

Responsibilities: organization job number, order metadata, samples, batches, participant
assignment, job functions, and production status.

Public contracts: `JobRepository`, `SampleRepository`, `ProductionContext`.

Dependencies: auth organization context and sync. It does not run image comparison.

Current foundation: `ProductionJob`, `JobParticipant`, manager/designer/inspection
functions, and `JobAccessPolicy` define effective access. `ProductionJobService`, its
Supabase adapter and mock open a work by organization number, approved customer, or
unconfirmed customer request. Migration `012` persists jobs and participants. Owner and
admin can access all organization jobs; employees and customers require an explicit
participant record. Sample persistence and remote protocol synchronization remain
pending.

### protocols

Responsibilities: immutable completed protocols, stages, metrics, findings, verdicts,
history, and audit references.

Public contracts: `ProtocolRepository`, `ProtocolFactory`, `ProtocolReader`.

Dependencies: storage and sync. It accepts results from Inspection but does not import
Inspection presentation.

### reports

Responsibilities: PDF generation, templates, export, digital signature metadata, and
report delivery.

Public contracts: `ReportService`, `ReportTemplateRepository`, `ReportExporter`.

Dependencies: protocols, storage, security, and entitlements. Reports never recalculate
inspection metrics.

### billing

Responsibilities: plans, limits, subscription state, trials, enterprise contracts,
checkout sessions, invoices, receipts, and refunds.

Public contracts: `SubscriptionService`, `EntitlementService`, `CheckUsageService`,
`PaymentService`, `BillingPortalService`, `PlanRepository`.

Dependencies: auth identity, organization, licensing, and remote subscription/payment
adapters. Other product features depend only on `EntitlementService`; a payment result
does not directly unlock functionality.

Current checkpoint: `PaymentService` and `MockPaymentService` support quotes, safe billing
profiles, and a test subscription activation. `SupabasePaymentService` calls protected
RPCs from migration `019`; prices and final access assignments are decided on the server.
No card number, CVV, or provider secret crosses this module boundary.
Migration `025` adds server-owned completed-check usage. `CheckUsageService` reads the
current UTC day and records a stable protocol ID atomically; organization plans share
one counter, while personal plans use the current user. Advisory locking prevents
concurrent overrun, and the stable ID makes exact-result updates idempotent.

### collaboration

Responsibilities: organization groups, messages, image/protocol references, comments,
read state, and remote collaboration permissions.

Public contracts: `ChatRepository`, `MessageService`, `AttachmentAccessService`.

Dependencies: auth, protocols, storage, sync, and security. Chat stores asset IDs and
signed access references, not unrestricted file paths.

Current foundation: `features/chat` contains thread/message domain models,
`ChatRepository`, `MockChatRepository`, and `SupabaseChatRepository`. The first
vertical slice loads personal and organization threads, sends text, and receives
updates through Supabase Realtime. Protocol attachments remain references to the
protocols module. Ordinary job-chat attachments use typed metadata in the message and
private bytes in storage; binaries are never duplicated in the chat table.

### settings

Responsibilities: camera, calibration, Delta E tolerances, color gamut, optical density,
barcode rules, report defaults, and organization policy overrides.

Public contracts: `SettingsRepository`, `EffectiveSettingsService`.

Dependencies: auth organization context and sync. Inspection receives an immutable
settings snapshot rather than reading UI controls during calculation.

## 5. Capability modules

### alignment

Defines `AlignmentEngine` for anchor refinement, transforms, reprojection metrics, and
canonical output. Dart and OpenCV are adapters.

### color_analysis

Defines `ColorAnalysisProvider` for Lab conversion, Delta E, color profiles, defect maps,
and layered analysis. Web Worker, Dart, native, or server execution are adapters.

Current foundation: `lib/features/color_analysis` owns the measurement profile and the
deterministic CIE76, CIE94 Graphic Arts, CIEDE2000, and CMC 2:1 formulas, plus the 2/5 mm
point aperture. `lib/features/capture` owns camera lighting and optical-filter metadata.
The legacy compare service and Web Worker consume the color-analysis model until the
provider boundary is introduced; capture metadata never changes ready-image pixels.

### geometry_analysis

Defines `GeometryAnalysisProvider` for black-and-white structure comparison, residual
shift, missing strokes, extra strokes, and geometry maps.

### ocr

Defines `OCRProvider` and normalized OCR results. ML Kit, browser, cloud, and mock engines
remain interchangeable.

### barcode

Defines `BarcodeProvider`, normalized symbols, geometry, value, and validation findings.

### ai

Defines `AIProvider` for optional advisory analysis. AI output is a finding with provider
and model version; it does not silently override deterministic inspection metrics.

### sync

Defines `SyncService`, outbox processing, remote acknowledgement, retries, conflicts,
and tombstones. It depends on repository synchronization contracts, not screens.

### storage

Defines `LocalStorage`, `CloudStorage`, asset metadata, cache, retention, checksums, and
upload policy.

Current foundation: the vendor-neutral `CloudStorage` port, deterministic
`MockCloudStorage`, device-only defaults, and persisted storage settings exist.
`SupabaseCloudStorage` now verifies and accesses the private per-user
`trimatrix-assets` path prepared by migration `013`. No workflow uploads reference or
sample originals. Google Drive and organization/job-scoped paths remain disconnected.

Migration `014` and `ProtocolCloudRepository` add the first narrow cloud workflow.
Completed checks remain local-first, then protocol JSON and a difference-map preview
limited to 1280 pixels are uploaded in the background. Reference and sample originals
are not accepted by this workflow. The initial RLS policy is owner-only; organization
sharing requires the later job-scoped policy.

Migration `015` applies the existing `can_view_production_job_v1` policy to cloud
protocol rows and preview objects. New organization previews use
`organizations/<organization>/jobs/<job>/...`; owner and admin can read every
organization job, while employees and customers receive only assigned jobs. Chat
attachments read through `ProtocolCloudRepository`, never around RLS.
The multi-account manual test confirmed this boundary: an administrator and a
representative of the assigned customer opened the first job's protocol and preview,
while a representative of another customer could see only his own second job. The
chat action refreshes the accessible protocol list before opening it, so a protocol
created after the chat screen opened no longer requires a full page reload.

Migration `016` secures the existing chat tables, creates default personal and team
threads, and provides job-scoped threads through `can_view_production_job_v1`.
Customers are excluded from the organization-wide team thread.

Migration `017` changes customer job access from automatic assignment to an explicit
release controlled by owner, admin, or the job's assigned manager. `ChatRepository`
lists manageable jobs and changes the release state only through server RPCs. A
customer sees the job chat, protocols, and assets only while the job is shared.

Migration `024` adds a dedicated `chat` subpath below each job's private Storage
scope. Any user who can view the job may insert a unique chat attachment there;
update and delete are restricted to the object's owner. `ChatRepository` enforces a
10 MB client limit, stores only attachment metadata in `chat_messages`, and downloads
through `CloudStorage`, so the existing job RLS remains the read boundary.

### analytics

Defines `AnalyticsService` and `DiagnosticsService`. Product events and technical logs
remain separate and privacy-filtered.

### licensing

Defines `SecurityService`, `LicenseService`, secure key/value storage, permission policy,
signed URL access, and audit contracts.

## 6. Infrastructure adapters

- `local`: SQLite, shared preferences, local files, browser persistence, and migrations;
- `remote`: Supabase Auth, Database, Storage, Edge Functions, payment backend, and AI
  gateways;
- `platform`: camera, image picker, ML Kit, OpenCV, browser Worker, secure storage, and
  connectivity.

Infrastructure types are converted into domain types at the boundary. Supabase rows,
ML Kit objects, and SDK exceptions must not cross into feature contracts.

## 7. Service interfaces and test doubles

| Contract | Production responsibility | Development double |
|---|---|---|
| `AuthService` | real account session | `MockAuthService` |
| `SubscriptionService` | plans and subscription state | `MockSubscriptionService` |
| `EntitlementService` | capability access and limits | `MockEntitlementService` |
| `PaymentService` | payment backend flow | `MockPaymentService` |
| `LicenseService` | signed and offline license checks | `MockLicenseService` |
| `CloudStorage` | remote binary objects | `MockCloudStorage` |
| `AIProvider` | external AI analysis | `MockAIProvider` |
| `OCRProvider` | OCR engine | `MockOCRProvider` |
| `BarcodeProvider` | barcode engine | `MockBarcodeProvider` |
| `AnalyticsService` | product event destination | `MockAnalyticsService` |
| `SecurityService` | secure storage and policies | `MockSecurityService` |
| `CompareEngine` | selected comparison engine | `MockCompareEngine` |
| repositories | persistent domain records | `InMemory...Repository` |

Mocks return deterministic configured outcomes. In-memory repositories implement real
repository behavior in memory. Neither performs network, billing, telemetry, or device
file access.

## 8. Dependency rules

Allowed:

- presentation depends on its own application layer;
- application depends on domain contracts and public contracts of required modules;
- infrastructure depends on contracts it implements;
- app depends on public contracts and infrastructure for composition;
- capabilities depend on core and their own contracts.

Forbidden:

- domain importing Flutter, Supabase, SQLite, HTTP, ML Kit, or payment SDKs;
- one feature importing another feature's presentation or infrastructure;
- direct database access from screens;
- Inspection calling PaymentService or inspecting plan names;
- Sync reading widget state;
- Reports recalculating comparison results;
- AI mutating deterministic results without an explicit finding and audit trail;
- circular feature dependencies;
- `shared` becoming the owner of business entities.

## 9. Public contract rule

Every module exposes the smallest useful public surface. Internal files are private by
convention. Cross-module models are stable value objects, not mutable screen models.
Breaking contract changes require a migration plan and, for stored data or protocols,
an explicit schema or algorithm version.

## 10. Module creation checklist

Before creating a module, confirm that it has clear ownership, at least one real use
case, a defined public contract, known dependencies, and an independent test boundary.
If those conditions are absent, keep the implementation in the owning module rather
than creating another abstraction.
