import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('print conditions remain organization owned and specialist managed', () {
    final foundation = File('supabase/migrations/027_print_conditions_v1.sql')
        .readAsStringSync();
    final lifecycle = File(
      'supabase/migrations/028_print_condition_lifecycle_v1.sql',
    ).readAsStringSync();
    final sql = '$foundation\n$lifecycle';

    expect(sql, contains('CREATE TABLE IF NOT EXISTS print_conditions'));
    expect(
      sql,
      contains('CREATE TABLE IF NOT EXISTS production_job_print_conditions'),
    );
    expect(sql, contains("source_method IN ('quickCamera', 'iccImport')"));
    expect(
      sql,
      contains(
        "status IN ('draft', 'verified', 'published', 'archived')",
      ),
    );
    expect(lifecycle, contains("member.role = 'employee'"));
    expect(lifecycle, isNot(contains("member.role = 'owner'")));
    expect(
        lifecycle, contains("function.function_name = 'inspectionSpecialist'"));
    expect(sql, contains('target_profile_class <> \'prtr\''));
    expect(sql, contains("target_color_space <> 'CMYK'"));
    expect(sql, contains('can_view_production_job_v1(target_job)'));
    expect(
      sql,
      contains('Only a published print condition can be assigned'),
    );
    expect(
      sql,
      contains("(storage.foldername(name))[3] = 'print-profiles'"),
    );
    expect(
      sql,
      contains(
        'GRANT EXECUTE ON FUNCTION can_manage_print_conditions_v1(UUID) TO authenticated',
      ),
    );
    expect(lifecycle, contains('archive_print_condition_v1'));
    expect(lifecycle, contains('restore_print_condition_v1'));
    expect(
      lifecycle,
      contains('prepare_print_condition_permanent_delete_v1'),
    );
    expect(lifecycle, contains('delete_print_condition_permanently_v1'));
    expect(lifecycle, contains("ARRAY['admin']"));
    expect(lifecycle, contains("chat.kind = 'service'"));
    expect(
        lifecycle, contains('A used print condition must remain in history'));
    expect(lifecycle, isNot(contains('DELETE FROM storage.objects')));
  });
}
