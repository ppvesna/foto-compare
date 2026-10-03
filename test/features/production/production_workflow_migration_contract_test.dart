import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production workflow blocks stage advancement until defects resolve',
      () async {
    final sql = await File(
      'supabase/migrations/030_production_workflow_v1.sql',
    ).readAsString();

    expect(sql, contains('stage_code TEXT NOT NULL'));
    expect(sql, contains("flow_state IN ('ready', 'blocked', 'completed')"));
    expect(sql, contains('CREATE TABLE IF NOT EXISTS production_job_blocks'));
    expect(sql,
        contains('CREATE TABLE IF NOT EXISTS production_job_stage_history'));
    expect(sql, contains('resolve_production_job_block_v1'));
    expect(
        sql, contains('Resolve all defect blocks before advancing the work'));
    expect(sql, contains("WHEN 'quality_control' THEN 'completed'"));
  });

  test('only assigned inspection specialists control defect blocks', () async {
    final sql = await File(
      'supabase/migrations/030_production_workflow_v1.sql',
    ).readAsString();

    expect(
        sql, contains('CREATE TABLE IF NOT EXISTS production_job_controllers'));
    expect(sql, contains("function.function_name = 'inspectionSpecialist'"));
    expect(sql, contains("member.role = 'employee'"));
    expect(
        sql, contains("requested_action = 'block' AND controller.can_block"));
    expect(sql,
        contains("requested_action = 'unblock' AND controller.can_unblock"));
    expect(sql, contains("ARRAY['admin']"));
    expect(
      sql,
      contains(
          "is_customer AND history.event_type IN ('blocked', 'unblocked')"),
    );
    expect(sql, isNot(contains("ARRAY['owner', 'admin']\n        OR EXISTS")));
  });

  test('work register uses server search and cursor pagination', () async {
    final sql = await File(
      'supabase/migrations/030_production_workflow_v1.sql',
    ).readAsString();

    expect(sql, contains('list_production_works_v1'));
    expect(sql, contains('cursor_updated_at TIMESTAMPTZ'));
    expect(sql,
        contains('(job.updated_at, job.id) < (cursor_updated_at, cursor_id)'));
    expect(sql, contains("lower(job.number) LIKE '%' || clean_search || '%'"));
    expect(sql, contains('LIMIT safe_size'));
    expect(
      sql,
      contains('ALTER PUBLICATION supabase_realtime ADD TABLE production_jobs'),
    );
  });
}
