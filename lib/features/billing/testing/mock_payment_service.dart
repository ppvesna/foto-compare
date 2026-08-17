import '../domain/billing.dart';
import '../domain/entitlement.dart';
import '../domain/payment_service.dart';

class MockPaymentService implements PaymentService {
  BillingProfile profile;
  BillingQuote? lastQuote;
  BillingActivation? lastActivation;
  BillingScope? lastScope;
  String? lastOrganizationId;
  int quoteCount = 0;
  int saveProfileCount = 0;

  MockPaymentService({this.profile = const BillingProfile()});

  @override
  Future<BillingQuote> quote({
    required PlanTier plan,
    required BillingPeriod period,
  }) async {
    quoteCount++;
    final value = BillingQuote(
      plan: plan,
      period: period,
      amountMinor: switch ((plan, period)) {
        (PlanTier.pro, BillingPeriod.month) => 2900,
        (PlanTier.pro, BillingPeriod.year) => 29000,
        (PlanTier.enterprise, BillingPeriod.month) => 9900,
        (PlanTier.enterprise, BillingPeriod.year) => 99000,
        _ => 0,
      },
      currency: 'EUR',
      testMode: true,
    );
    lastQuote = value;
    return value;
  }

  @override
  Future<BillingProfile> loadProfile({
    required BillingScope scope,
    String? organizationId,
  }) async {
    lastScope = scope;
    lastOrganizationId = organizationId;
    return profile;
  }

  @override
  Future<void> saveProfile({
    required BillingScope scope,
    String? organizationId,
    required BillingProfile profile,
  }) async {
    saveProfileCount++;
    lastScope = scope;
    lastOrganizationId = organizationId;
    this.profile = profile;
  }

  @override
  Future<BillingActivation> activateTestSubscription({
    required BillingScope scope,
    String? organizationId,
    required BillingQuote quote,
  }) async {
    lastScope = scope;
    lastOrganizationId = organizationId;
    final value = BillingActivation(
      paymentId: 'test-payment-1',
      plan: quote.plan,
      period: quote.period,
      amountMinor: quote.amountMinor,
      currency: quote.currency,
      validUntil: DateTime.utc(2027, 8, 4),
      testMode: true,
    );
    lastActivation = value;
    return value;
  }
}
