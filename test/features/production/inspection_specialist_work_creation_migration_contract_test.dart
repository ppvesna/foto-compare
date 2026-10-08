import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only an inspection specialist enters a new work', () async {
    final sql = await File(
      'supabase/migrations/038_inspection_specialist_work_creation_v1.sql',
    ).readAsString();

    expect(sql, contains("ARRAY['employee']"));
    expect(sql, contains("function_name = 'inspectionSpecialist'"));
    expect(sql, isNot(contains("ARRAY['owner', 'admin']")));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION'));
  });
}
