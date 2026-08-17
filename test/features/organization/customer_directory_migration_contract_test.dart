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
  });
}
