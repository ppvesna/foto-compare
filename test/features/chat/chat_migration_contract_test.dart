import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat migration removes prototype access and uses job RLS', () async {
    final sql =
        await File('supabase/migrations/016_secure_chat_v1.sql').readAsString();

    expect(sql, contains('ADD COLUMN IF NOT EXISTS kind TEXT'));
    expect(sql, contains('DROP POLICY IF EXISTS "auth_read_chat_messages"'));
    expect(sql, contains('DROP POLICY IF EXISTS "auth_write_chat_messages"'));
    expect(sql, contains('can_view_production_job_v1(chat.job_id)'));
    expect(sql, contains("ARRAY['owner', 'admin', 'employee']"));
    expect(sql, contains('list_chat_sender_profiles_v1'));
    expect(sql, contains('ALTER PUBLICATION supabase_realtime'));
  });

  test('customer job access is explicit and manager controlled', () async {
    final sql = await File(
      'supabase/migrations/017_customer_job_chat_access_v1.sql',
    ).readAsString();

    expect(
      sql,
      contains(
        'REVOKE ALL ON FUNCTION ensure_job_chat_v1(UUID) FROM authenticated',
      ),
    );
    expect(sql, contains("customer_access_status IN ('internal', 'shared')"));
    expect(sql, contains("participant.participant_type = 'manager'"));
    expect(
      sql,
      contains(
        "participant.participant_type <> 'customer'\n"
        "              OR job.customer_access_status = 'shared'",
      ),
    );
    expect(sql, contains('list_customer_share_candidates_v1'));
    expect(sql, contains('set_production_job_customer_access_v1'));
    expect(sql, contains('list_accessible_chat_threads_v1'));
    expect(sql, contains('An assigned customer account is required'));
    expect(sql, contains("'job:' || selected_job.id::TEXT"));
  });

  test('ordinary chat attachments stay inside an accessible job', () async {
    final sql = await File(
      'supabase/migrations/024_job_chat_attachments_v1.sql',
    ).readAsString();

    expect(sql, contains("bucket_id = 'trimatrix-assets'"));
    expect(sql, contains("(storage.foldername(name))[5] = 'chat'"));
    expect(sql, contains('can_view_production_job_asset_v1'));
    expect(sql, contains('owner_id = auth.uid()::TEXT'));
  });

  test('chat navigation persists reads and returns searchable job metadata',
      () async {
    final sql = await File(
      'supabase/migrations/029_chat_navigation_v1.sql',
    ).readAsString();

    expect(sql, contains('CREATE TABLE IF NOT EXISTS chat_thread_reads'));
    expect(sql,
        contains('ALTER PUBLICATION supabase_realtime ADD TABLE chat_groups'));
    expect(sql, contains('mark_chat_thread_read_v1'));
    expect(sql, contains('job_status TEXT'));
    expect(sql, contains('customer_name TEXT'));
    expect(sql, contains('unread_count BIGINT'));
    expect(sql, contains('message.sender_id IS DISTINCT FROM auth.uid()'));
    expect(sql, contains('can_access_chat_group_v1(target_thread)'));
    expect(
      sql,
      contains('ON CONFLICT (group_id, user_id) DO NOTHING'),
    );
    expect(
      sql,
      contains('REVOKE ALL ON TABLE chat_thread_reads FROM authenticated'),
    );
  });

  test('chat directory and managed teams keep role boundaries', () async {
    final sql = await File(
      'supabase/migrations/032_chat_directory_and_teams_v1.sql',
    ).readAsString();

    expect(sql, contains('search_chat_contacts_v1'));
    expect(sql, contains('open_direct_chat_v1'));
    expect(sql, contains("current.role = 'customer'"));
    expect(sql, contains("participant_type IN ('operator', 'manager')"));
    expect(sql, contains('can_view_production_job_v1(job.id)'));
    expect(sql, contains("member.role = 'admin'"));
    expect(sql, contains('create_chat_team_v1'));
    expect(sql, contains('update_chat_team_v1'));
    expect(sql, contains('archive_chat_team_v1'));
    expect(sql, contains('restore_chat_team_v1'));
    expect(sql, contains('archived_at TIMESTAMPTZ'));
    expect(sql, contains('list_accessible_chat_threads_v2'));
    expect(
        sql,
        contains(
            'INSERT INTO chat_thread_reads(group_id, user_id, last_read_at)'));
    expect(sql, contains("chat.kind <> 'service'"));
    expect(sql, contains("chat.kind <> 'group' OR chat.archived_at IS NULL"));
  });

  test('unified work chat keeps audiences and administrator access separate',
      () async {
    final sql = await File(
      'supabase/migrations/033_unified_work_chat_v1.sql',
    ).readAsString();

    expect(
      sql,
      contains("has_organization_role_v2(job.organization_id, ARRAY['admin'])"),
    );
    expect(sql, isNot(contains("ARRAY['owner', 'admin']")));
    expect(sql, contains('production_job_participants AS participant'));
    expect(sql, contains('production_job_batches AS batch'));
    expect(sql, contains('production_inspection_attempts AS attempt'));
    expect(sql, contains('attempt.attempted_by = auth.uid()'));
    expect(sql, contains('production_job_blocks AS block'));
  });

  test('work hub exposes statuses and writable organization service chat',
      () async {
    final sql = await File(
      'supabase/migrations/034_work_hub_and_contextual_chat_v1.sql',
    ).readAsString();

    expect(sql, contains('list_accessible_chat_threads_v3'));
    expect(sql, contains('job_flow_state TEXT'));
    expect(sql, contains("chat.kind IN ('organization', 'service')"));
    expect(sql, contains('list_production_inspection_history_v1'));
    expect(sql, contains('open_production_job_v2'));
    expect(sql, contains('target_responsible_user'));
    expect(sql, contains('save_organization_customer_v2'));
    expect(sql, contains('list_organization_production_workers_v1'));
    expect(sql, contains("function_name = 'manager'"));
    expect(sql, contains("(storage.foldername(name))[3] = 'chats'"));
  });

  test('owner work creation and service chat defaults stay available',
      () async {
    final sql = await File(
      'supabase/migrations/035_owner_work_and_service_chat_v1.sql',
    ).readAsString();

    expect(sql, contains("ARRAY['owner', 'admin']"));
    expect(sql, contains('ensure_default_chat_threads_v1'));
    expect(sql, contains("'Служебные', 'service'"));
    expect(
      sql,
      contains(
        "'organization:' || membership.organization_id::TEXT || ':service'",
      ),
    );
    expect(sql, contains('is_deleted = FALSE'));
  });

  test('existing organizations receive a service chat backfill', () async {
    final sql = await File(
      'supabase/migrations/036_service_chat_backfill_v1.sql',
    ).readAsString();

    expect(sql, contains('FROM organizations AS organization'));
    expect(sql, contains("'Служебные'"));
    expect(sql, contains("':service'"));
    expect(sql, contains('is_deleted = FALSE'));
  });

  test('owner can be responsible for the first organization work', () async {
    final sql = await File(
      'supabase/migrations/037_owner_work_responsible_v1.sql',
    ).readAsString();

    expect(sql, contains('open_production_job_v2'));
    expect(sql, contains('list_organization_production_workers_v1'));
    expect(sql, contains("member.role IN ('owner', 'admin', 'employee')"));
    expect(sql, contains("ARRAY['owner', 'admin', 'employee']"));
  });
}
