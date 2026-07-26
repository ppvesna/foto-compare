# Organization invitation v1 test plan

## Install

1. Apply migrations `009`, `010`, and `011` in order.
2. Add the local and production application URLs to Supabase Auth redirect URLs.
3. Authenticate the Supabase CLI, then deploy:

```bash
supabase functions deploy invite-organization-member --project-ref lwlsmtagdqqhudiibhwk
supabase functions deploy login-by-nickname --project-ref lwlsmtagdqqhudiibhwk
```

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to hosted functions. Never put the service-role key in
Flutter or Git.

## New employee

1. Sign in as the owner of `vesna`.
2. Open `Settings -> Organization`.
3. Enter a new email, reserved nickname, display name, role `Employee`, and one or
   more employee functions.
4. Send the invitation.
5. Verify that the participant table shows `Invitation sent`.
6. Open the email in a separate browser profile.
7. Set the employee nickname, name, and private password.

Expected: the invitation becomes active, the user receives role `Employee`,
organization `vesna`, personal Free, and working Pro. The owner never sees the
password.

## Interrupted invitation recovery

1. Send an invitation to a new email.
2. Open the one-time link while the local application is unavailable, then close
   the callback page.
3. Send the invitation again with the same email and nickname.
4. Open the new magic link in a separate browser profile.

Expected: the existing Auth account is reused, the pending invitation is restored,
the password setup screen opens, and no duplicate user or seat is created.

The owner participant table must include both active and pending rows. This also verifies
that the RPC returns normalized PostgreSQL `text` columns without falling back to the
legacy active-member list.

## Existing account

1. Invite the verified email of an existing personal account.
2. Open the magic-link email or sign in normally.

Expected: the pending invitation is claimed only by the same confirmed email.

## Boundaries

- Free organizations cannot reserve a second seat.
- Pro defaults to five total active and pending seats.
- Administrator cannot invite another administrator.
- Pending email and nickname are unique.
- A user already in another organization is rejected.
- Cancelling a pending invitation releases its seat.
- Nickname login succeeds through `login-by-nickname`; direct anonymous profile email
  reads are denied.
