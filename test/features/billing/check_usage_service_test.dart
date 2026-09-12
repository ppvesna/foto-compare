import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';

void main() {
  test('completed checks increment once and enforce the daily limit', () async {
    final service = MockCheckUsageService(
      CheckUsageSnapshot(
        usageDateUtc: DateTime.utc(2026, 9, 12),
        used: 1,
        limit: 2,
        scope: 'organization',
      ),
    );

    var usage = await service.recordCompletedCheck(
      checkId: 'check-2',
      jobId: 'job-1',
    );
    expect(usage.used, 2);
    expect(usage.remaining, 0);

    usage = await service.recordCompletedCheck(
      checkId: 'check-2',
      jobId: 'job-1',
    );
    expect(usage.used, 2);

    expect(
      () => service.recordCompletedCheck(
        checkId: 'check-3',
        jobId: 'job-1',
      ),
      throwsA(isA<DailyCheckLimitException>()),
    );
  });
}
