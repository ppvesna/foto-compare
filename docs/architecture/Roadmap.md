# Architecture v2 Migration Roadmap

Status: accepted; migration in progress

Rule: every step must preserve the working application and be independently reversible

## Current checkpoint

- Architecture v2 is approved.
- The `protocols` feature boundary is the first implemented module.
- Protocol models and the current local persistence adapter are separated.
- Legacy SharedPreferences keys and JSON are preserved.
- A compatibility test for the legacy protocol key is present.
- The next module is `references`; a full `ProtocolRepository` abstraction remains a
  later small step and is not required for the initial safe move.

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

### Step 9. Introduce organization context

Add current organization, membership, and role to the application session. A personal
account can be represented as a one-member organization to avoid two data models.

### Step 10. Introduce entitlements

Add `EntitlementService` with a permissive implementation matching today's behavior.
Replace future plan checks with capability checks only.

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

### Step 15. Add schema migrations

Add new tables and fields through additive, versioned migrations. Read old and new
records; write new format only after migration verification.

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

### Step 25. Connect payments

Add a payment adapter and server-side webhook processing. The client must not mark a
subscription paid based only on a local payment callback.

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
