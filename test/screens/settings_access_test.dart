import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/screens/settings_screen.dart';

void main() {
  testWidgets('shows effective plan, role, capabilities, and test controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              role: OrganizationRole.operator,
            ),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Текущий доступ'), findsOneWidget);
    expect(find.text('Pro'), findsWidgets);
    expect(find.text('Оператор'), findsWidgets);
    expect(find.text('Точная Delta E'), findsOneWidget);
    expect(find.text('Тестирование доступа'), findsOneWidget);
  });
}
