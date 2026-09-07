# Customer workflow v1 manual test

Purpose: verify migration `012_customer_workflow_v1.sql` before customer and job data
is trusted as a server access boundary.

## Preconditions

1. Migrations `006–011` and both organization Edge Functions are installed.
2. One Pro organization has an owner, an admin, an employee, and a customer account.
3. Local access testing is disabled in Trimatrix.
4. Apply migration `012_customer_workflow_v1.sql` in a transaction.

## Scenario A: approved customer

1. Sign in as owner or admin.
2. Open `Settings -> Organization -> Customer directory`.
3. Create a customer with a name; migration `020` assigns the next unique code,
   such as `C-0001`, automatically.
4. In the first table row, select the responsible employee. Either leave the
   representative fields empty and choose `Save without representative`, or enter
   email, nickname, and name and choose `Invite representative` from the `⋮` menu.
5. Add a second row with the same customer and another representative. Confirm that
   both rows use the same customer ID and code after migration `021`.
6. Confirm that creator and updater nicknames are displayed.
7. Sign in as employee and open Comparison.
8. Enter the work number from the technical specification and select this customer.
9. Complete a small comparison and open the local protocol.
10. Add a representative after the job already exists. Confirm migration `022`
    adds the representative as a customer participant while the job remains internal.
11. Explicitly open the job to the customer and confirm that the representative can
    see it; close access and confirm that it disappears again.

Expected:

- the work receives a server UUID;
- the protocol contains the work number, customer ID, customer name, and confirmed state;
- the employee is attached as operator;
- the configured manager and customer are attached as participants;
- another unassigned employee cannot read the work directly.

## Scenario B: customer not found

1. Sign in as employee.
2. Enter a new work number.
3. Select `Customer not found` and enter the name exactly as written in the technical
   specification.
4. Continue the inspection without waiting for an administrator.
5. Sign in as owner or admin and open the pending customer queue.
6. Link the request to an existing customer or create a new directory entry.

Expected:

- one pending request exists for the same organization, work number, and normalized name;
- the protocol marks the customer as unconfirmed until resolution;
- resolution changes only jobs linked to that request;
- manager and customer participants are attached after resolution.

## Scenario C: updates and isolation

1. Add another representative to the same customer in the directory.
2. Reopen the same work number with another approved customer.
3. Archive one customer.
4. Sign in as employee and refresh the customer list.

Expected:

- both customer representatives remain linked to the same directory entry;
- old manager/customer participants are removed from the reopened work;
- the operator participant remains;
- archived customers are hidden from employees and remain visible to owner/admin when
  archived records are requested;
- customer accounts can read only works where they are participants.

## Release gate

The migration is accepted only when all scenarios pass with local access testing
disabled. Protocol and image synchronization must not rely on job RLS before this gate.

## Verified checkpoint — 2026-09-07

- two representatives are linked to one customer and see the same explicitly shared
  work;
- the organization team chat remains hidden from both representatives;
- representative-to-admin and admin-to-representative Realtime messages pass;
- revocation hides the work and reopening restores it with message history;
- a second foreign work and attachment isolation remain unverified manual fixtures.
