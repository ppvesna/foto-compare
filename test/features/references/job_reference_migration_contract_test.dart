import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production jobs keep one explicit active reference', () {
    final sql = File(
      'supabase/migrations/041_job_active_references_v1.sql',
    ).readAsStringSync();

    expect(
        sql, contains('CREATE TABLE IF NOT EXISTS production_job_references'));
    expect(sql, contains('ADD COLUMN IF NOT EXISTS active_reference_id UUID'));
    expect(sql, contains('get_active_job_reference_v1'));
    expect(sql, contains('set_active_job_reference_v1'));
    expect(sql, contains('active_reference_id = selected_reference.id'));
  });

  test('existing jobs recover the latest archived source reference', () {
    final sql = File(
      'supabase/migrations/042_job_reference_backfill_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('JOIN cloud_check_protocols AS protocol'));
    expect(sql, contains('protocol.reference_asset_id'));
    expect(sql, contains('protocol.reference_object_path'));
    expect(sql, contains('job.active_reference_id IS NULL'));
    expect(sql, contains('ORDER BY job.id, protocol.protocol_created_at DESC'));
  });

  test('job references stay inside the organization', () {
    final sql = File(
      'supabase/migrations/043_secure_job_references_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('is_internal_production_user_v1(job_id)'));
    expect(sql, contains("'references'"));
    expect(sql, contains('can_view_internal_production_asset_v1'));
    expect(
      sql,
      contains('REVOKE ALL ON FUNCTION get_active_job_reference_v1(UUID)'),
    );
    expect(
      sql,
      contains('REVOKE ALL ON FUNCTION set_active_job_reference_v1'),
    );
  });
}
