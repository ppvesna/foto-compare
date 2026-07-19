import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';

void main() {
  test('free plan has daily limit and no exact Delta E', () {
    final access = EntitlementSnapshot.forPlan(PlanTier.free);

    expect(access.allows(ProductCapability.runInspection), isTrue);
    expect(access.allows(ProductCapability.exactDeltaE), isFalse);
    expect(access.allows(ProductCapability.ocr), isFalse);
    expect(access.limit(UsageLimit.checksPerDay), 10);
  });

  test('pro plan enables professional inspection capabilities', () {
    final access = EntitlementSnapshot.forPlan(PlanTier.pro);

    expect(access.allows(ProductCapability.exactDeltaE), isTrue);
    expect(access.allows(ProductCapability.ocr), isTrue);
    expect(access.allows(ProductCapability.cloudSync), isTrue);
    expect(access.limit(UsageLimit.savedReferences), 50);
  });

  test('enterprise limits are unlimited', () {
    final access = EntitlementSnapshot.forPlan(PlanTier.enterprise);

    expect(access.limit(UsageLimit.checksPerDay), isNull);
    expect(access.limit(UsageLimit.organizationSeats), isNull);
  });

  test('legacy fallback preserves all current application behavior', () {
    final access = EntitlementSnapshot.legacyCompatible();

    expect(access.legacyFallback, isTrue);
    expect(
      ProductCapability.values.every(access.allows),
      isTrue,
    );
    expect(access.limit(UsageLimit.checksPerDay), isNull);
  });

  test('mock service returns configured access', () async {
    final expected = EntitlementSnapshot.forPlan(PlanTier.pro);
    final service = MockEntitlementService(expected);

    expect(await service.load(), same(expected));
  });
}
