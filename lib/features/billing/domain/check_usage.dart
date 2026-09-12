class CheckUsageSnapshot {
  final DateTime usageDateUtc;
  final int used;
  final int? limit;
  final String scope;

  const CheckUsageSnapshot({
    required this.usageDateUtc,
    required this.used,
    required this.limit,
    required this.scope,
  });

  int? get remaining {
    if (limit == null) return null;
    final value = limit! - used;
    if (value <= 0) return 0;
    return value > limit! ? limit : value;
  }

  bool get limitReached => limit != null && used >= limit!;
}

class DailyCheckLimitException implements Exception {
  final CheckUsageSnapshot snapshot;

  const DailyCheckLimitException(this.snapshot);

  @override
  String toString() =>
      'Daily check limit reached: ${snapshot.used}/${snapshot.limit}';
}
