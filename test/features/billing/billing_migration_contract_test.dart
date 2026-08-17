import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('billing migration keeps pricing and activation on the server', () {
    final sql =
        File('supabase/migrations/019_test_billing_v1.sql').readAsStringSync();

    expect(sql, contains('CREATE TABLE IF NOT EXISTS access_plans'));
    expect(sql, contains('CREATE TABLE IF NOT EXISTS access_assignments'));
    expect(
      sql.indexOf('CREATE TABLE IF NOT EXISTS access_plans'),
      lessThan(sql.indexOf('CREATE TABLE IF NOT EXISTS billing_plan_prices')),
    );
    expect(sql, contains('CREATE TABLE IF NOT EXISTS billing_plan_prices'));
    expect(sql, contains('CREATE TABLE IF NOT EXISTS billing_profiles'));
    expect(
        sql, contains('CREATE TABLE IF NOT EXISTS billing_payment_attempts'));
    expect(sql, contains('CREATE OR REPLACE FUNCTION billing_quote_v1'));
    expect(
      sql,
      contains('CREATE OR REPLACE FUNCTION activate_test_subscription_v1'),
    );
    expect(sql, contains('selected_price.amount_minor <> target_amount_minor'));
    expect(sql, contains("ARRAY['owner']"));
    expect(sql, contains('CREATE OR REPLACE FUNCTION current_entitlement_v4'));
    expect(sql, isNot(contains('card_number')));
    expect(sql, isNot(contains('cvv')));
    expect(sql, isNot(contains("WHEN 'operator'")));
    expect(sql, isNot(contains("now() + INTERVAL '90 days'")));
  });
}
