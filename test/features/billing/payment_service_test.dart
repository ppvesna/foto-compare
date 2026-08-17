import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';

void main() {
  test('mock billing returns server-style quotes and activates selected plan',
      () async {
    final service = MockPaymentService();

    final quote = await service.quote(
      plan: PlanTier.enterprise,
      period: BillingPeriod.year,
    );
    final activation = await service.activateTestSubscription(
      scope: BillingScope.organization,
      organizationId: 'organization-1',
      quote: quote,
    );

    expect(quote.amountMinor, 99000);
    expect(quote.formattedAmount, '990 €');
    expect(quote.testMode, isTrue);
    expect(activation.plan, PlanTier.enterprise);
    expect(service.lastScope, BillingScope.organization);
    expect(service.lastOrganizationId, 'organization-1');
  });

  test('mock billing profile stays separate from payment credentials',
      () async {
    final service = MockPaymentService();
    const profile = BillingProfile(
      billingEmail: 'billing@example.com',
      legalName: 'Vesna GmbH',
      countryCode: 'DE',
      taxId: 'DE123',
      billingAddress: 'Berlin',
    );

    await service.saveProfile(
      scope: BillingScope.personal,
      profile: profile,
    );

    expect(await service.loadProfile(scope: BillingScope.personal), profile);
    expect(service.saveProfileCount, 1);
  });
}
