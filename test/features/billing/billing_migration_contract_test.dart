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

  test('daily usage is server owned, atomic, and idempotent', () {
    final sql = File('supabase/migrations/025_daily_check_usage_v1.sql')
        .readAsStringSync();

    expect(
        sql, contains('CREATE TABLE IF NOT EXISTS daily_check_usage_events'));
    expect(sql, contains('current_check_usage_v1'));
    expect(sql, contains('record_completed_check_v1'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('UNIQUE (usage_scope, subject_id, check_id)'));
    expect(sql, contains("member.role IN ('owner', 'admin', 'employee')"));
    expect(sql, contains('can_view_production_job_v1(job.id)'));
    expect(sql, contains('daily_check_limit_reached'));
    expect(sql, contains("AT TIME ZONE 'UTC'"));
    expect(sql, contains('FROM cloud_check_protocols AS protocol'));
    expect(
      sql,
      contains('ON CONFLICT (usage_scope, subject_id, check_id) DO NOTHING'),
    );
  });
}
