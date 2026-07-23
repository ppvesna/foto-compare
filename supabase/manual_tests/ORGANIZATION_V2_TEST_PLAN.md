# Organization v2 test plan

This plan validates registration, owner bootstrap, role assignment, and access refresh.
It does not validate job chat isolation, because the remote job/chat repository is the
next migration step.

## Safety boundary

- Use a staging Supabase project first.
- Back up `organizations`, `organization_members`, and `user_profiles`.
- Apply migration `002` if `user_profiles` is absent, then apply
  `006_organization_access_v2.sql`, `007_organization_plan_authority.sql`, and
  `008_current_entitlement_v2.sql` in order. Migration `004` is not required for
  organization roles; its chat schema will be replaced in a later job-scoped migration.
- Do not apply `005_access_control.sql`; it contains the previous role model.
- Use dedicated test email addresses and non-production organization names.
- Run `organization_v2_preflight.sql` first. Missing organization tables are expected
  on a first installation; resolve only a missing `user_profiles` table, duplicate
  owners, or missing-profile warnings before applying `006`.

## Test 1: registration creates a discoverable profile

1. Register `owner-test` through Trimatrix and fill name, nickname, organization hint,
   email, and password.
2. Confirm the email if Supabase confirmation is enabled.
3. Sign in once so the authenticated profile upsert can complete.
4. Verify one row in `auth.users` and one matching row in `user_profiles`.
5. Verify that the nickname is normalized to lowercase and remains unique.

Expected: the account exists, but it has personal access and no organization role.
The registration organization field is only a profile hint.

## Test 2: personal Pro user becomes owner

1. Give the dedicated account a temporary plan using `pro_plan_smoke_test.sql`. Do not
   use the role smoke-test here: the future owner must remain a personal user.
2. With migration `008` installed, press `Refresh rights from server`. A full sign-out
   is only a compatibility check for older builds.
3. Open `Settings -> Organization` and create `Trimatrix Test Print`.
4. Open `Settings -> Access` and press `Refresh rights from server`.

Expected database state:

- one `organizations` row;
- one `organization_members` row for the current user;
- role `owner`;
- the profile organization name updated to the created name.

Expected application state: role `Owner`, billing and ownership permissions allowed.

## Test 3: owner discovers and assigns a user

1. Register a second account with nickname `employee_test` and sign in once.
2. Return to the owner account.
3. Search for the exact nickname in `Settings -> Organization`.
4. Assign `Employee`.
5. Sign in as `employee_test` and press `Refresh rights from server`.

Expected: the owner sees the registered name and profile organization hint. Supabase
contains one employee membership. The employee may inspect and view protocols but may
not manage members, billing, or ownership.

## Test 4: changing Employee to Customer changes effective access

1. As owner, find `employee_test` again and assign `Customer`.
2. In the second account press `Refresh rights from server`.

Expected: the role changes without editing registration data. Comparison and reference
management become unavailable; protocol viewing and comments remain available.

## Test 5: administrator boundaries

1. Register a third account and assign `Administrator` as owner.
2. Sign in as that administrator.
3. Verify it can assign `Employee` and `Customer`.
4. Verify the UI does not offer `Administrator` or `Owner` as assignable roles.
5. Call the RPC manually with `target_role = admin` under the administrator session.

Expected: the server rejects administrator elevation. An administrator also cannot
change an existing administrator or owner.

## Test 6: negative and recovery cases

- Unknown nickname returns no user and changes no rows.
- A user who has not completed the first sign-in/profile upsert cannot be assigned.
- A Free personal account cannot create an organization.
- A user already linked to another organization is rejected until organization
  switching is implemented.
- After temporary metadata cleanup and a new login, the test plan returns to Free.

## Verified checkpoint

- Migrations `006–008` installed successfully in the configured test environment.
- Active Pro entitlement loaded from server-managed metadata.
- Organization creation, owner membership, member count, and organization name verified.
- Employee, customer, and administrator account tests remain pending.

## Test 7: next chat tests

After remote production jobs and chat are connected:

1. create one test job;
2. assign employee and customer participants;
3. create a job chat;
4. send a message as owner;
5. verify assigned users receive it through Realtime;
6. verify an unassigned user cannot list the chat, read messages, or open assets;
7. verify the customer cannot see other jobs in the same organization.
