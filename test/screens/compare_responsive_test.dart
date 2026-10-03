import 'dart:convert';

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

    final workflow = find.byKey(const ValueKey('current-workflow-action'));
    final status = find.byKey(const ValueKey('current-status-text'));
    expect(workflow, findsOneWidget);
    expect(status, findsOneWidget);
    expect(
      tester.getTopLeft(status).dx,
      lessThan(300),
    );
    expect(
      tester.getTopLeft(status).dy,
      greaterThan(tester.getBottomLeft(workflow).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison HUD fits a narrow phone viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
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

    expect(
      find.byKey(const ValueKey('active-parameter-0')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('current-workflow-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer representative sees chat handoff, not workflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    int? destination;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.customer,
            ),
            onNavigate: (value) => destination = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('comparison-role-restricted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('current-workflow-action')),
      findsNothing,
    );
    expect(find.text('Указать работу'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('comparison-open-chat')));
    await tester.pump();

    expect(destination, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow menu opens the full inspector on demand',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(590, 700));
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

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Данные и параметры'));
    await tester.pumpAndSettle();

    expect(find.text('Данные и параметры'), findsOneWidget);
    expect(find.text('АКТИВНЫЕ ДАННЫЕ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace bar does not duplicate the app navigation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(590, 700));
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

    expect(
      find.byKey(const ValueKey('workspace-navigation-menu')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow menu opens the complete workflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(590, 700));
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

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Все этапы'));
    await tester.pumpAndSettle();

    expect(find.text('Все этапы'), findsOneWidget);
    expect(find.text('Загрузить эталон'), findsOneWidget);
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

    await tester.tap(find.byKey(const ValueKey('current-workflow-action')));
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

    await tester.tap(find.byKey(const ValueKey('current-workflow-action')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, jobNumber);
    await tester.tap(find.text('Продолжить'));
    await tester.pumpAndSettle();

    final jobValue = find.byKey(const ValueKey('active-status-value-РАБОТА'));
    expect(jobValue, findsOneWidget);
    expect(
      find.ancestor(of: jobValue, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference point helper fits, focuses and closes on narrow view',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ReferencePointHelperDialog(
                    bytes: png,
                    imageSize: const Size(100, 100),
                    points: const [Offset(12, 18), Offset(96, 94)],
                    activeIndex: 2,
                  ),
                ),
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Эталон · точка 2'), findsOneWidget);

    await tester.tap(find.byTooltip('К точке 2'));
    await tester.pump();
    await tester.tap(find.byTooltip('Увеличить'));
    await tester.pump();
    await tester.tap(find.byTooltip('Вся карта'));
    await tester.pump();
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    expect(find.text('Эталон · точка 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
