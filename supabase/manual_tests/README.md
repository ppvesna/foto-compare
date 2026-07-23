# Supabase access smoke tests

`access_metadata_smoke_test.sql` is the legacy fallback test for protected Supabase
`app_metadata`. The primary organization flow now uses migrations `006–008` and the
steps in `ORGANIZATION_V2_TEST_PLAN.md`. Never apply `005_access_control.sql`; it
contains the obsolete role model.

## Preparation

1. Create a dedicated user in Supabase Authentication or register it through Trimatrix.
2. Confirm the user can sign in normally.
3. In Trimatrix `Settings -> Access`, disable `Local test mode`.
4. Open `access_metadata_smoke_test.sql` in Supabase SQL Editor.
5. Replace `CHANGE_ME@example.com` in the apply block and its verification query.

The script refuses to overwrite a user who already has access metadata.

## First scenario

Keep these values in the script:

```text
target_plan = pro
target_role = customer
```

Run the apply block and verification query. When migration `008` is installed, use
`Refresh rights from server`; old installations may still require a full sign-out and
sign-in to refresh JWT metadata.

Expected result in `Settings -> Access`:

| Field | Expected value |
| --- | --- |
| Plan | Pro |
| Role | Customer |
| Run inspections | Denied |
| View protocols | Allowed |
| Comment | Allowed |
| Manage members | Denied |
| Manage billing | Denied |

The plan may include the comparison capability, but the customer role must still block
the comparison workflow. Effective access is the intersection of plan and role.

## Additional scenarios

After cleanup, repeat the test with another dedicated account or a changed role:

| Role | Main expectation |
| --- | --- |
| `employee` | Inspection allowed; members and billing denied |
| `admin` | Jobs and members allowed; billing and ownership denied |
| `owner` | All organization permissions allowed |

Per-job employee/customer isolation is covered by domain tests only at this checkpoint.
It is not a remote security guarantee until job tables and RLS are installed.

## Current verified checkpoint

The configured test environment has migrations `006–008` installed. A dedicated
account was verified as an active Pro owner of a one-member organization. The next
manual checks are employee and customer assignment by exact nickname.

## Cleanup

Uncomment the cleanup block, replace its email, and run it. The block removes access
metadata only when the fixed smoke-test organization ID is still present. Sign out and
sign in again after cleanup.
