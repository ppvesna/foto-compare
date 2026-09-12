# Architecture v2 Migration Roadmap

Status: accepted; migration in progress

Rule: every step must preserve the working application and be independently reversible

## Current checkpoint

- Architecture v2 is approved.
- The `protocols` and `references` feature boundaries are implemented.
- Protocol, reference, and calibration profile models are separated from the current
  local persistence adapters.
- Legacy SharedPreferences keys, file names, and JSON are preserved.
- Compatibility tests for legacy protocol and reference data are present.
- Organization role and entitlement snapshots are connected to the application shell.
- Organization roles are reduced to owner, admin, employee, and customer; manager,
  designer, and inspection specialist are separate per-job functions.
- Free, Pro, and Enterprise presets, mocks, client gates, and a Supabase snapshot adapter
  are implemented with a legacy-compatible fallback.
- Organization creation, owner/admin membership, invitations, personal/working plan
  separation, and server-side entitlement refresh are verified in the test environment.
- `005_access_control.sql` is an unapplied prototype based on the previous role set. It
  must not be applied.
- The `production` foundation now contains jobs, participants, functions, access policy,
  a server adapter, customer directory, and a narrow comparison-flow UI. Job-scoped
  server data is present; customer publication, revocation, preserved history, and two
  representatives on one work have passed an end-to-end manual test.
- The first `CloudStorage` port, mock, device-only settings adapter, and provider status
  UI are present. Supabase Storage, bounded protocol previews, and job-scoped access are
  connected; originals remain device-only and Google Drive remains disconnected.
- Secure organization/job chat and Supabase Realtime are connected. Owner/employee
  text messaging has passed a two-account test. Private ordinary attachments are
  implemented for job chats and await the final two-account manual exchange.
- Migration `019` provides server-owned test prices and assignment-backed entitlement
  snapshots. Real payment processing remains out of scope.
- Migration `023` separates internal team and customer-representative seat limits;
  the test Pro plan currently uses 20 seats for each category.
- Migration `024` adds owner-scoped writes under each accessible job's private
  `/chat/` Storage path without broadening protocol/original upload rights.
- Migration `025` replaces browser-local daily quota enforcement with an atomic,
  idempotent server counter shared by an organization plan. The live test workspace
  shows the migrated value `1/500`; one new completed-check increment remains to be
  confirmed manually across two accounts.
- The `vesna-test` employee and customer job sharing/revocation gate has passed. The
  next release task is to audit remote deployment state and stabilize the branch.

## Migration policy

- Do not start with a folder move or a `CompareScreen` refactor.
- Add contracts and adapters beside existing implementations.
- Keep old storage formats readable during every schema transition.
- Release and verify each step before beginning the next risky step.
- Do not combine architecture migration with unrelated visual redesign.
- Remove legacy code only after usage has reached zero.

## Phase 0: Baseline

### Step 1. Record current behavior

Document the operator flow, supported platforms, current persistence, and known
limitations. Capture representative reference/sample pairs for regression testing.

Safe result: documentation and fixtures only; runtime behavior is unchanged.

### Step 2. Establish performance baselines

Record crop, alignment, preliminary Delta E, exact Delta E, OCR, barcode, and total
inspection times for small, typical, and large images.

Safe result: future migrations can prove they did not silently reduce accuracy or
performance.

### Step 3. Adopt architectural decisions

Approve Architecture v2 and record major future decisions as short ADR documents.
No application structure changes are required.

## Phase 1: Stable contracts

### Step 4. Define identity rules

Specify stable UUIDs and relationships for organization, reference, reference version,
job, sample, check, protocol, and image asset. Keep legacy IDs as import aliases.

### Step 5. Define protocol reproducibility

Specify engine version, settings version, calibration data, thresholds, source asset
IDs, operator, device, and timestamps required by every new protocol.

### Step 6. Introduce the composition root

Create one application-level location for selecting implementations. Initially it
constructs the existing services, so behavior remains unchanged.

### Step 7. Add service ports and mocks

Add only the interfaces needed by the next migration step. Provide mock external
providers and in-memory repositories before changing callers.

## Phase 2: Accounts and editions

### Step 8. Wrap authentication

Expose the current Supabase authentication through `AuthService`. Existing screens may
continue to use their current UI while authentication details move behind the adapter.

Progress: current-profile loading and editing are behind `AccountProfileService`, with
a Supabase adapter and mock. Sign-in, registration, recovery, and session observation
still use the existing application shell and will move only when their workflow changes.

### Step 9. Introduce organization context

Add current organization, membership, and role to the application session. A personal
account can be represented as a one-member organization to avoid two data models.

Progress: typed roles, permission matrix, mocks, Supabase adapters, shell integration,
organization creation, administration UI, and the server schema are present. Legacy
remote role names are mapped in the client. Pending invitations, seat limits, owner
participant UI, and protected nickname login are implemented in migration `010` and
Edge Function adapters. The base server flow and invitation recovery are deployed and
manually verified. Switching between several organizations is intentionally deferred.

Interrupted-link recovery is implemented and deployed in migration `011`. The
transactional server check and full invitation browser callback pass manually.

The existing `005_access_control.sql` still contains the previous role set. It must not
be applied as the final production role model; revise it through a staged additive
migration and verify job-scoped RLS first.

Progress: client administration contracts and owner/admin settings UI are connected.
`006` reads roles from membership; `007–008` use authoritative personal plan data.
`009` adds separate personal and effective organization plans. The current test
environment has passed owner bootstrap, administrator invitation, organization-plan
inheritance, and invitation completion. The next exact check assigns
`vesna_employee_test` through `vesna_admin_test`, then validates customer job access.

Invitation progress: the owner can prepare email, nickname, role, and initial employee
functions. A new invitee completes their own password and profile; an existing account
sees the pending invitation after a confirmed login and must accept it. The three
employee functions are defaults only and do not replace per-job assignments.

Active-member role changes are connected to the protected assignment RPC. The owner can
appoint administrators; an administrator cannot change owner or administrator records.

### Step 10. Introduce entitlements

Add `EntitlementService` with a permissive implementation matching today's behavior.
Replace future plan checks with capability checks only.

Progress: implemented for inspection start, daily limits, barcode, OCR, AI, exact Delta
E, protocol history, and collaboration navigation. The server entitlement snapshot is
active in the current test environment. Migration `019` adds an assignment-backed v4
snapshot and a deliberately isolated test activation flow.

The settings UI displays the effective server snapshot. The former debug-only local plan
and role override is no longer applied, so the UI has one authoritative access source.

### Step 11. Add subscription and license mocks

Develop plan and license UI against `MockSubscriptionService` and
`MockLicenseService`. No payment provider is required at this stage.

## Phase 3: Repositories and data model

### Step 12. Wrap reference storage

Place existing reference files and calibration profile storage behind
`ReferenceRepository` and `AssetStorage`. Do not change the stored files yet.

### Step 13. Wrap protocol history

Place the current local check history behind `ProtocolRepository`. Preserve the current
last-check behavior as the first adapter implementation.

Progress: module boundary and local adapter are in place; repository port and dependency
injection are still pending.

### Step 14. Add jobs and samples

Introduce `ProductionJob` and `Sample` as metadata around the current comparison flow.
Existing checks without these fields remain valid.

Progress: `ProductionJob`, `JobParticipant`, three job functions, the effective access
policy, customer directory, unconfirmed customer requests, server job opening, current
work selection, and local protocol linkage are implemented. Sample metadata and remote
protocol synchronization remain pending.

### Step 15. Add schema migrations

Add new tables and fields through additive, versioned migrations. Read old and new
records; write new format only after migration verification.

Progress: additive migration `012` defines customers, customer links, requests, jobs,
participants, RPCs, and RLS and is available in the test environment. Customer release
and revocation have passed the multi-account manual test. Remaining production checks
include foreign-work isolation with a second fixture and the complete
`CUSTOMER_WORKFLOW_V1_TEST_PLAN.md`.

## Phase 4: Inspection boundary

### Step 16. Wrap the current engine

Implement a legacy `CompareEngine` adapter that delegates to the current comparison
services. Do not split or move the algorithm.

### Step 17. Separate orchestration from computation

Create an application use case that sequences alignment, preliminary comparison, OCR,
barcode, Lab ID, exact comparison, and protocol creation. Initially `CompareScreen`
may call it as one new facade.

### Step 18. Formalize capability adapters

Expose alignment, color analysis, OCR, barcode, and AI through their ports. Keep Dart,
Web Worker, OpenCV, and ML Kit as replaceable adapters.

### Step 19. Version comparison results

Store engine identity, precision level, thresholds, and algorithm version in new
protocols. Never reinterpret an old result using current thresholds without labeling
the recalculation.

## Phase 5: Offline synchronization

Implementation order before this phase: introduce a `CloudStorage` port with local and
Supabase adapters, then add a Google Drive adapter. User-supplied databases must connect
through a server-side `DatabaseConnector`; raw database credentials are never stored in
Flutter Web. AI integration follows through `AIProvider`, independently of the compare
engine and storage provider.

Progress: the port, mock, local settings persistence, and device-only default are
implemented. The first real Supabase adapter and private per-user bucket policy are
prepared by migration `013`; settings can verify the connection without uploading
files. Migration `014` implements the first explicit low-risk flow: local-first
protocol metadata and a bounded difference-map preview are copied to the private
user cloud in the background. Originals remain device-only. The next storage step is
organization/job-scoped reading and preview access. Migration `015` implements that
step using the existing production-job access function and exposes available protocols
through chat attachments. Migration `016` adds the first secure text-chat slice and
Realtime updates; owner/employee messaging has passed the first two-account test.
Migration `017` adds manager-controlled customer release for one job at a time.
Customer visibility, revocation, preserved history, Realtime messaging, and
job-scoped cloud-protocol isolation have passed the dedicated multi-account manual
test with two customers. The chat action now refreshes its protocol list before
opening, including protocols created after the screen was opened.
Migration `024` adds the next bounded storage slice: ordinary files and images up to
10 MB in job chats, backed by private Storage and the existing job-access boundary.
Google OAuth and Drive remain a separate provider connection.

### Step 20. Add an outbox

Write local changes and sync commands atomically. Start with one low-risk metadata type,
such as settings or reference labels.

### Step 21. Add idempotent metadata sync

Synchronize metadata without image binaries. Add retries, backoff, server acknowledgement,
versions, and tombstones.

### Step 22. Define conflict policies

Use explicit policies per entity. Completed protocols are append-only; mutable labels
and settings use versions; concurrent calibration edits require a visible resolution.

### Step 23. Add optional asset synchronization

Upload previews or source images only when allowed by plan and organization policy.
Support device-only, on-demand, and full-cloud modes.

## Phase 6: Commercial services

### Step 24. Connect subscriptions

Replace subscription mocks with a backend adapter. Entitlements remain the only API
used by product features.

Progress: test-stage adapter and server assignment flow implemented. Production provider,
renewal state, cancellation, and webhook reconciliation remain pending.

### Step 25. Connect payments

Add a payment adapter and server-side webhook processing. The client must not mark a
subscription paid based only on a local payment callback.

Progress: `PaymentService`, mock, Supabase test adapter, server prices, billing profiles,
and payment-attempt audit records are implemented. This is not real payment processing;
the test flag must be disabled before a production provider is connected.

### Step 26. Add enterprise licensing

Support organization contracts, signed license claims, seat limits, audit requirements,
and a controlled offline grace period.

## Phase 7: Reports and operations

### Step 27. Add reports

Generate PDF reports from immutable protocol data through `ReportService`. Report
templates and renderer choice remain replaceable.

### Step 28. Add analytics and diagnostics

Record consented product events separately from technical timings and failures. Do not
include images, OCR text, authentication data, or secrets by default.

### Step 29. Harden security

Verify RLS, signed URLs, secure token storage, organization isolation, retention,
deletion, export, and audit behavior.

## Phase 8: Controlled legacy reduction

### Step 30. Move only code being changed

When a legacy area receives substantial product work, migrate that area behind an
existing contract. Avoid repository-wide mechanical moves.

### Step 31. Remove obsolete paths

Delete an old service only when no imports remain, data compatibility is confirmed,
and regression tests cover its replacement.

### Step 32. Reassess architecture

Review module boundaries, build time, test speed, sync volume, and operational load.
Split deployment units only if measured constraints justify it.

## Completion criteria

Architecture v2 is established when new features enter through module contracts,
commercial access is entitlement-based, protocols are reproducible, local work survives
loss of connectivity, sync is retryable, and no domain module depends directly on a
vendor SDK.
