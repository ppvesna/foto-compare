import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer directory migration keeps invitations and archive reversible',
      () async {
    final migration = await File(
      'supabase/migrations/018_customer_directory_tables_v1.sql',
    ).readAsString();

    expect(migration, contains('ADD COLUMN IF NOT EXISTS customer_id UUID'));
    expect(migration, contains('link_accepted_customer_invitation_v1'));
    expect(migration, contains('list_organization_customers_v2'));
    expect(migration, contains('list_customer_jobs_v1'));
    expect(migration, contains('update_organization_member_v1'));
    expect(migration, contains('remove_organization_member_v1'));
    expect(migration, contains('restore_organization_customer_v1'));
    expect(migration, contains('GRANT EXECUTE'));
  });

  test('customer invitation function binds the invitation to a customer',
      () async {
    final function = await File(
      'supabase/functions/invite-organization-member/index.ts',
    ).readAsString();

    expect(function, contains('body.customerId'));
    expect(function, contains('attach_organization_invitation_customer_v1'));
    expect(function, contains('cancel_organization_invitation_v1'));
    expect(function, contains('customer_seat_limit'));
  });

  test('customer codes are generated atomically by the organization', () async {
    final migration = await File(
      'supabase/migrations/020_customer_auto_codes_v1.sql',
    ).readAsString();

    expect(migration, contains('next_customer_number'));
    expect(migration, contains("'C-' || lpad"));
    expect(migration, contains('next_customer_number + 1'));
    expect(migration, contains('save_organization_customer_v1'));
    expect(migration, contains('GRANT EXECUTE'));
  });

  test('customer directory returns every representative', () async {
    final migration = await File(
      'supabase/migrations/021_customer_representatives_v1.sql',
    ).readAsString();

    expect(migration, contains('list_organization_customers_v3'));
    expect(migration, contains('jsonb_agg'));
    expect(migration, contains('organization_customer_users'));
    expect(migration, contains('organization_invitations'));
    expect(
      migration,
      isNot(contains('DELETE FROM organization_customer_users')),
    );
    expect(migration, contains('GRANT EXECUTE'));
  });

  test('customer representatives follow active customer jobs', () async {
    final migration = await File(
      'supabase/migrations/022_customer_job_participant_sync_v1.sql',
    ).readAsString();

    expect(migration, contains('sync_customer_job_participants_v1'));
    expect(migration, contains('AFTER INSERT OR DELETE'));
    expect(migration, contains("'customer'"));
    expect(migration, contains("job.status = 'active'"));
    expect(migration, contains('job.customer_confirmed'));
    expect(migration, contains('ON CONFLICT'));
    expect(
      migration,
      contains("customer_access_status = 'shared'"),
      reason: 'The migration must document that assignment is not publication.',
    );
  });

  test('team and customer representatives have separate seat limits', () async {
    final migration = await File(
      'supabase/migrations/023_split_organization_seat_limits_v1.sql',
    ).readAsString();

    expect(migration, contains('"organizationSeats":20'));
    expect(migration, contains('"customerRepresentativeSeats":20'));
    expect(migration, contains('organization_role_seat_limit_v2'));
    expect(migration, contains('organization_invitation_seats_v2'));
    expect(migration, contains('organization_member_seats_v2'));
    expect(migration, contains('invitation_customer_seat_limit'));
  });
}
