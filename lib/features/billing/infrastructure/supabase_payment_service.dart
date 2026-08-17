import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/billing.dart';
import '../domain/entitlement.dart';
import '../domain/payment_service.dart';

class SupabasePaymentService implements PaymentService {
  final SupabaseClient client;

  const SupabasePaymentService(this.client);

  @override
  Future<BillingQuote> quote({
    required PlanTier plan,
    required BillingPeriod period,
  }) async {
    final row = _map(
      await client.rpc(
        'billing_quote_v1',
        params: {
          'target_plan': plan.name,
          'target_period_months': period.months,
          'target_currency': 'EUR',
        },
      ),
    );
    return BillingQuote(
      plan: _plan(row['plan']),
      period: _period(row['period_months']),
      amountMinor: (row['amount_minor'] as num).toInt(),
      currency: row['currency'] as String? ?? 'EUR',
      testMode: row['test_mode'] == true,
    );
  }

  @override
  Future<BillingProfile> loadProfile({
    required BillingScope scope,
    String? organizationId,
  }) async {
    final row = _map(
      await client.rpc(
        'current_billing_profile_v1',
        params: {
          'target_scope': scope.serverValue,
          'target_organization': organizationId,
        },
      ),
    );
    return BillingProfile(
      billingEmail: row['billing_email'] as String? ?? '',
      legalName: row['legal_name'] as String? ?? '',
      countryCode: row['country_code'] as String? ?? '',
      taxId: row['tax_id'] as String? ?? '',
      billingAddress: row['billing_address'] as String? ?? '',
    );
  }

  @override
  Future<void> saveProfile({
    required BillingScope scope,
    String? organizationId,
    required BillingProfile profile,
  }) async {
    await client.rpc(
      'save_billing_profile_v1',
      params: {
        'target_scope': scope.serverValue,
        'target_organization': organizationId,
        'target_billing_email': profile.billingEmail,
        'target_legal_name': profile.legalName,
        'target_country_code': profile.countryCode,
        'target_tax_id': profile.taxId,
        'target_billing_address': profile.billingAddress,
      },
    );
  }

  @override
  Future<BillingActivation> activateTestSubscription({
    required BillingScope scope,
    String? organizationId,
    required BillingQuote quote,
  }) async {
    final row = _map(
      await client.rpc(
        'activate_test_subscription_v1',
        params: {
          'target_scope': scope.serverValue,
          'target_organization': organizationId,
          'target_plan': quote.plan.name,
          'target_period_months': quote.period.months,
          'target_amount_minor': quote.amountMinor,
          'target_currency': quote.currency,
        },
      ),
    );
    return BillingActivation(
      paymentId: row['payment_id'] as String,
      plan: _plan(row['plan']),
      period: _period(row['period_months']),
      amountMinor: (row['amount_minor'] as num).toInt(),
      currency: row['currency'] as String? ?? 'EUR',
      validUntil: DateTime.parse(row['valid_until'] as String).toUtc(),
      testMode: row['test_mode'] == true,
    );
  }

  Map<String, dynamic> _map(Object? response) {
    Object? value = response;
    if (value is String) value = jsonDecode(value);
    if (value is List && value.isNotEmpty) value = value.first;
    if (value is! Map) throw StateError('Supabase returned no billing data');
    return Map<String, dynamic>.from(value);
  }

  PlanTier _plan(Object? value) => PlanTier.values.firstWhere(
        (plan) => plan.name == value,
        orElse: () => PlanTier.free,
      );

  BillingPeriod _period(Object? value) {
    final months = (value as num?)?.toInt();
    return BillingPeriod.values.firstWhere(
      (period) => period.months == months,
      orElse: () => BillingPeriod.month,
    );
  }
}
