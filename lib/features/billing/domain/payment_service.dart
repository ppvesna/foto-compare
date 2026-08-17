import 'billing.dart';
import 'entitlement.dart';

abstract interface class PaymentService {
  Future<BillingQuote> quote({
    required PlanTier plan,
    required BillingPeriod period,
  });

  Future<BillingProfile> loadProfile({
    required BillingScope scope,
    String? organizationId,
  });

  Future<void> saveProfile({
    required BillingScope scope,
    String? organizationId,
    required BillingProfile profile,
  });

  Future<BillingActivation> activateTestSubscription({
    required BillingScope scope,
    String? organizationId,
    required BillingQuote quote,
  });
}
