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

  test('organization plan remains separate from the personal plan', () {
    final pro = EntitlementSnapshot.forPlan(PlanTier.pro);
    final access = EntitlementSnapshot(
      plan: PlanTier.pro,
      personalPlan: PlanTier.free,
      scope: EntitlementScope.organization,
      organizationId: 'organization-1',
      capabilities: pro.capabilities,
      limits: pro.limits,
    );

    expect(access.plan, PlanTier.pro);
    expect(access.personalPlan, PlanTier.free);
    expect(access.usesOrganizationPlan, isTrue);
    expect(access.allows(ProductCapability.exactDeltaE), isTrue);
  });

  test('enterprise limits are unlimited', () {
    final access = EntitlementSnapshot.forPlan(PlanTier.enterprise);

    expect(access.limit(UsageLimit.checksPerDay), isNull);
    expect(access.limit(UsageLimit.organizationSeats), isNull);
  });

  test('expired paid subscription records the fallback to Free', () {
    final access = EntitlementSnapshot.forPlan(PlanTier.free).copyWith(
      configuredPlan: PlanTier.pro,
      personalPlan: PlanTier.pro,
      scope: EntitlementScope.organization,
      organizationId: 'organization-1',
      validUntil: DateTime.utc(2026, 7, 30),
      subscriptionStatus: 'active',
    );

    expect(access.plan, PlanTier.free);
    expect(access.configuredPlan, PlanTier.pro);
    expect(access.usesFallbackPlan, isTrue);
    expect(access.subscriptionExpired, isTrue);
    expect(access.allows(ProductCapability.exactDeltaE), isFalse);
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
