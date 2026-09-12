import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/check_usage.dart';
import '../domain/check_usage_service.dart';

class SupabaseCheckUsageService implements CheckUsageService {
  final SupabaseClient client;

  const SupabaseCheckUsageService(this.client);

  @override
  Future<CheckUsageSnapshot> load() async {
    final response = await client.rpc('current_check_usage_v1');
    return _snapshotFromResponse(response);
  }

  @override
  Future<CheckUsageSnapshot> recordCompletedCheck({
    required String checkId,
    String? jobId,
  }) async {
    try {
      final response = await client.rpc(
        'record_completed_check_v1',
        params: {
          'target_check_id': checkId,
          'target_job_id': jobId,
        },
      );
      return _snapshotFromResponse(response);
    } on PostgrestException catch (error) {
      if (error.message.contains('daily_check_limit_reached')) {
        final snapshot = await load();
        throw DailyCheckLimitException(snapshot);
      }
      rethrow;
    }
  }

  CheckUsageSnapshot _snapshotFromResponse(Object? response) {
    Object? value = response;
    if (value is List && value.isNotEmpty) value = value.first;
    if (value is! Map) {
      throw const FormatException('Invalid check usage response');
    }
    final row = Map<String, dynamic>.from(value);
    final rawLimit = row['limit'];
    return CheckUsageSnapshot(
      usageDateUtc: DateTime.parse(row['usage_date'] as String).toUtc(),
      used: (row['used'] as num?)?.toInt() ?? 0,
      limit: rawLimit == null ? null : (rawLimit as num).toInt(),
      scope: row['scope'] as String? ?? 'personal',
    );
  }
}
