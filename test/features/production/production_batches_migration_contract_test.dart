import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() async {
    sql = await File(
      'supabase/migrations/031_production_batches_inspections_v1.sql',
    ).readAsString();
  });

  test('work is divided into numbered batches and physical units', () {
    expect(sql, contains('CREATE TABLE IF NOT EXISTS production_job_batches'));
    expect(sql, contains('CREATE TABLE IF NOT EXISTS production_units'));
    expect(sql, contains("unit_type IN ('stack', 'roll')"));
    expect(sql, contains('ensure_initial_production_batch_v1'));
    expect(sql, contains('create_production_batch_v1'));
    expect(sql, contains('create_production_unit_v1'));
    expect(
      sql,
      contains('Only the current batch can receive a physical unit'),
    );
  });

  test('inspection keeps repeated attempts before a final decision', () {
    expect(sql, contains('CREATE TABLE IF NOT EXISTS production_inspections'));
    expect(
      sql,
      contains('CREATE TABLE IF NOT EXISTS production_inspection_attempts'),
    );
    expect(sql, contains('record_production_inspection_attempt_v1'));
    expect(sql, contains('decide_production_inspection_v1'));
    expect(sql, contains("requested_decision NOT IN ('approved', 'blocked')"));
  });

  test('customer receives only the two external work states', () {
    expect(sql, contains("member.role = 'customer'"));
    expect(sql, contains("THEN 0::BIGINT"));
    expect(sql, contains("customer_mode THEN '[]'::JSONB"));
    expect(sql, contains("job.status IN ('completed', 'archived')"));
  });

  test('internal job chat and its assets are isolated from customers', () {
    expect(sql, contains("'job_internal'"));
    expect(sql, contains('is_internal_production_user_v1(chat.job_id)'));
    expect(sql, contains("(storage.foldername(name))[5] = 'chat-internal'"));
    expect(sql, contains('can_view_internal_production_asset_v1'));
  });

  test('only an administrator removes a production block', () {
    expect(sql, contains('is_production_admin_v1(selected_block.job_id)'));
    expect(sql, contains('Only an administrator can remove a block'));
    expect(sql, contains('Resolve all blocks before completing the work'));
  });
}
