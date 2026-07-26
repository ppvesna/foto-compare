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
3. Create a customer with a unique code and name.
4. Select one employee as primary manager and one member with the customer role.
5. Confirm that creator and updater nicknames are displayed.
6. Sign in as employee and open Comparison.
7. Enter the work number from the technical specification and select this customer.
8. Complete a small comparison and open the local protocol.

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

1. Change the linked customer account in the directory.
2. Reopen the same work number with another approved customer.
3. Archive one customer.
4. Sign in as employee and refresh the customer list.

Expected:

- only the newly selected customer account remains linked to the directory entry;
- old manager/customer participants are removed from the reopened work;
- the operator participant remains;
- archived customers are hidden from employees and remain visible to owner/admin when
  archived records are requested;
- customer accounts can read only works where they are participants.

## Release gate

The migration is accepted only when all scenarios pass with local access testing
disabled. Protocol and image synchronization must not rely on job RLS before this gate.
