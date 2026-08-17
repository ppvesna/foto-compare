import 'entitlement.dart';

enum BillingScope { personal, organization }

extension BillingScopeValue on BillingScope {
  String get serverValue => name;

  String get label => switch (this) {
        BillingScope.personal => 'Личный тариф',
        BillingScope.organization => 'Тариф организации',
      };
}

enum BillingPeriod {
  month(1, 'Месяц'),
  year(12, 'Год');

  final int months;
  final String label;

  const BillingPeriod(this.months, this.label);
}

class BillingQuote {
  final PlanTier plan;
  final BillingPeriod period;
  final int amountMinor;
  final String currency;
  final bool testMode;

  const BillingQuote({
    required this.plan,
    required this.period,
    required this.amountMinor,
    required this.currency,
    required this.testMode,
  });

  String get formattedAmount {
    final amount = amountMinor / 100;
    final symbol = currency == 'EUR' ? '€' : currency;
    return '${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)} $symbol';
  }
}

class BillingProfile {
  final String billingEmail;
  final String legalName;
  final String countryCode;
  final String taxId;
  final String billingAddress;

  const BillingProfile({
    this.billingEmail = '',
    this.legalName = '',
    this.countryCode = '',
    this.taxId = '',
    this.billingAddress = '',
  });
}

class BillingActivation {
  final String paymentId;
  final PlanTier plan;
  final BillingPeriod period;
  final int amountMinor;
  final String currency;
  final DateTime validUntil;
  final bool testMode;

  const BillingActivation({
    required this.paymentId,
    required this.plan,
    required this.period,
    required this.amountMinor,
    required this.currency,
    required this.validUntil,
    required this.testMode,
  });
}
