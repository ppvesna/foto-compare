import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inspection specialist may archive evidence without customer writes',
      () {
    final sql = File(
      'supabase/migrations/040_inspection_specialist_protocol_assets_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('can_write_production_job_asset_v1'));
    expect(sql, contains("ARRAY['employee']"));
    expect(sql, contains("function_name = 'inspectionSpecialist'"));
    expect(sql, contains('can_view_production_job_v1(job.id)'));
    expect(sql, isNot(contains("participant_type = 'customer'")));
  });
}
