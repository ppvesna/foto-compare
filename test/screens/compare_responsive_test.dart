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

  testWidgets('job dialog refreshes customers created after screen opened',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final customerService = MockCustomerDirectoryService();
    final now = DateTime.utc(2026, 9, 12);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.admin,
            ),
            customerDirectoryService: customerService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    customerService.customers.add(
      OrganizationCustomer(
        id: 'customer-1',
        organizationId: 'organization-1',
        code: 'C-0001',
        name: 'Новый заказчик',
        active: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.tap(find.text('Работа и заказчик').first);
    await tester.pumpAndSettle();
    final customerField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Заказчик: код или название',
    );
    await tester.enterText(customerField, 'Новый');
    await tester.pumpAndSettle();

    expect(find.text('C-0001 · Новый заказчик'), findsOneWidget);
  });

  testWidgets('long job number uses the full inspector row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    const jobNumber = 'VESNA-ISOLATION-TEST-002';

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

    await tester.tap(find.text('Работа и заказчик').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, jobNumber);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    final jobValue = find.text(jobNumber);
    expect(jobValue, findsOneWidget);
    expect(
      find.ancestor(of: jobValue, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
