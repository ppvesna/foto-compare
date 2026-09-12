import '../domain/check_usage.dart';
import '../domain/check_usage_service.dart';

class MockCheckUsageService implements CheckUsageService {
  CheckUsageSnapshot snapshot;
  final Set<String> _recordedCheckIds = {};

  MockCheckUsageService(this.snapshot);

  @override
  Future<CheckUsageSnapshot> load() async => snapshot;

  @override
  Future<CheckUsageSnapshot> recordCompletedCheck({
    required String checkId,
    String? jobId,
  }) async {
    if (_recordedCheckIds.contains(checkId)) return snapshot;
    if (snapshot.limitReached) throw DailyCheckLimitException(snapshot);
    _recordedCheckIds.add(checkId);
    snapshot = CheckUsageSnapshot(
      usageDateUtc: snapshot.usageDateUtc,
      used: snapshot.used + 1,
      limit: snapshot.limit,
      scope: snapshot.scope,
    );
    return snapshot;
  }
}
