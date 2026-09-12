import 'check_usage.dart';

abstract interface class CheckUsageService {
  Future<CheckUsageSnapshot> load();

  Future<CheckUsageSnapshot> recordCompletedCheck({
    required String checkId,
    String? jobId,
  });
}
