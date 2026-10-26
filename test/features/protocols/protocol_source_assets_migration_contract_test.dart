import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protocol archive records exact reference and sample objects', () {
    final sql = File(
      'supabase/migrations/039_protocol_source_assets_v1.sql',
    ).readAsStringSync();

    expect(sql, contains('reference_asset_id TEXT'));
    expect(sql, contains('reference_object_path TEXT'));
    expect(sql, contains('sample_asset_id TEXT'));
    expect(sql, contains('sample_object_path TEXT'));
    expect(sql, isNot(contains('CREATE POLICY')));
    expect(sql, isNot(contains('public')));
  });
}
