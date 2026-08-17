import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/screens/compare_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('comparison workflow fits a short desktop viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 430));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.legacyPersonal(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Порядок действий'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
