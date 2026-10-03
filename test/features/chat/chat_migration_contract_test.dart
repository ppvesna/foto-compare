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
    expect(sql, contains('mark_chat_thread_read_v1'));
    expect(sql, contains('job_status TEXT'));
    expect(sql, contains('customer_name TEXT'));
    expect(sql, contains('unread_count BIGINT'));
    expect(sql, contains('message.sender_id IS DISTINCT FROM auth.uid()'));
    expect(sql, contains('can_access_chat_group_v1(target_thread)'));
    expect(
      sql,
      contains('REVOKE ALL ON TABLE chat_thread_reads FROM authenticated'),
    );
  });
}
