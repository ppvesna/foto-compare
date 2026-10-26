import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/features/production/production.dart';
import 'package:photo_compare/features/protocols/protocols.dart';
import 'package:photo_compare/features/references/references.dart';
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

    final commandBar = find.byKey(const ValueKey('workspace-command-bar'));
    final primaryAction =
        find.byKey(const ValueKey('workspace-primary-action'));
    final status = find.byKey(const ValueKey('current-status-text'));
    expect(commandBar, findsOneWidget);
    expect(primaryAction, findsOneWidget);
    expect(status, findsOneWidget);
    expect(tester.getSize(commandBar).height, lessThanOrEqualTo(50));
    expect(
      tester.getTopLeft(status).dx,
      lessThan(300),
    );
    expect(
      tester.getTopLeft(status).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(commandBar).dy),
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
      find.byKey(const ValueKey('workspace-primary-action')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer sees chat handoff, not workflow', (tester) async {
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
      find.byKey(const ValueKey('workspace-primary-action')),
      findsNothing,
    );
    expect(find.text('Указать работу'), findsNothing);
    expect(
      find.textContaining('Заказчик не загружает эталоны'),
      findsOneWidget,
    );

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

  testWidgets('personal comparison starts directly with the reference',
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

    expect(find.text('Загрузить эталон'), findsOneWidget);
    expect(find.text('Нажмите на экран'), findsOneWidget);
    expect(find.textContaining('Следующий шаг:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty comparison keeps the main photo background',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(590, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.free),
            organizationAccess: OrganizationAccess.legacyPersonal(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final photo = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/images/start-hero-prism-lab.png',
    );
    expect(photo, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comparison header owns navigation without floating controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    int? destination;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.legacyPersonal(),
            onNavigate: (value) => destination = value,
            canOpenChat: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('comparison-open-chat-action')),
      findsNothing,
    );
    for (final key in const [
      'workspace-mode-reference',
      'workspace-mode-sample',
      'workspace-mode-comparison',
    ]) {
      final mode = find.byKey(ValueKey(key));
      expect(mode, findsOneWidget);
      expect(
        find.descendant(of: mode, matching: find.byType(Icon)),
        findsNothing,
      );
    }
    final settings =
        find.byKey(const ValueKey('comparison-open-settings-action'));
    expect(settings, findsOneWidget);
    await tester.tap(settings);
    await tester.pump();
    expect(destination, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace overflow shows useful preparation actions',
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

    expect(find.text('Все этапы'), findsOneWidget);
    expect(find.text('Данные и параметры'), findsOneWidget);
    expect(find.text('Выбрать сохранённый эталон'), findsOneWidget);
    expect(find.text('Начать заново'), findsOneWidget);
    expect(find.text('AI-анализ'), findsNothing);
    expect(find.text('Новая проверка'), findsNothing);
    expect(find.text('Сохранить результат'), findsNothing);
    expect(find.text('Экспорт…'), findsNothing);
    expect(find.text('Горячие клавиши'), findsNothing);
    expect(find.text('Краткий протокол'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference and sample own their replacement actions',
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

    await tester.tap(
      find.byKey(const ValueKey('workspace-mode-reference-menu')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Другой эталон'), findsOneWidget);
    expect(find.text('Изменить рамку'), findsOneWidget);
    expect(find.text('Сохранить эталон'), findsOneWidget);
    expect(find.text('Выбрать сохранённый'), findsOneWidget);
    await tester.tapAt(const Offset(580, 680));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('workspace-mode-sample-menu')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Другой образец'), findsOneWidget);
    expect(find.text('Изменить рамку'), findsOneWidget);
    expect(find.text('Сохранить эталон'), findsNothing);
    expect(find.text('Выбрать сохранённый'), findsNothing);
    expect(
      find.byKey(const ValueKey('workspace-mode-comparison-menu')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest inspector does not expose stored work history',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    CheckHistoryService.checks.value = [
      CheckProtocol(
        id: 'old-organization-check',
        createdAt: DateTime.utc(2026, 10, 8),
        jobId: 'job-secret',
        jobNumber: 'VESNA-SECRET-WORK',
        customerName: 'Скрытый заказчик',
        score: 92,
        verdict: 'Предварительно',
        refSize: '100×100',
        cmpSize: '100×100',
        labId: 'lab-secret',
        labMatch: 92,
        stages: const [],
      ),
    ];
    addTearDown(() => CheckHistoryService.checks.value = const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.free),
            organizationAccess: OrganizationAccess.legacyPersonal(),
            showStoredHistory: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Данные и параметры'));
    await tester.pumpAndSettle();

    expect(find.textContaining('VESNA-SECRET-WORK'), findsNothing);
    expect(find.textContaining('Скрытый заказчик'), findsNothing);
    expect(find.text('Протокол проверки'), findsNothing);
    expect(find.text('ID для базы'), findsNothing);
    expect(find.text('Работа'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal workspace does not expose organization work history',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    CheckHistoryService.checks.value = [
      CheckProtocol(
        id: 'organization-check',
        createdAt: DateTime.utc(2026, 10, 8),
        ownerUserId: 'user-1',
        organizationId: 'organization-1',
        jobId: 'job-secret',
        jobNumber: 'VESNA-SECRET-WORK',
        customerName: 'Скрытый заказчик',
        score: 92,
        verdict: 'Предварительно',
        refSize: '100×100',
        cmpSize: '100×100',
        labId: 'lab-secret',
        labMatch: 92,
        stages: const [],
      ),
    ];
    addTearDown(() => CheckHistoryService.checks.value = const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompareScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.personal(),
            historyOwnerId: 'user-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Данные и параметры'));
    await tester.pumpAndSettle();

    expect(find.textContaining('VESNA-SECRET-WORK'), findsNothing);
    expect(find.textContaining('Скрытый заказчик'), findsNothing);
    expect(find.text('Протокол проверки'), findsNothing);
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
    expect(find.text('Загрузить эталон'), findsAtLeastNWidgets(1));
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

    await tester.tap(find.byKey(const ValueKey('workspace-primary-action')));
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
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.admin,
            ),
            initialJob: const ProductionJobContext(
              jobId: 'job-1',
              jobNumber: jobNumber,
              customerId: 'customer-1',
              customerName: 'Заказчик',
              customerConfirmed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final jobValue = find.byKey(const ValueKey('active-status-value-РАБОТА'));
    expect(jobValue, findsOneWidget);
    expect(
      find.ancestor(of: jobValue, matching: find.byType(Tooltip)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('organization job restores only its assigned reference',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    SharedPreferences.setMockInitialValues({
      'reference_profiles_v2': jsonEncode([
        {
          'id': 'reference-job-1',
          'label': 'Эталон работы 1',
          'bytes': png,
          'layoutProfile': null,
          'createdAt': '2026-10-26T10:00:00.000Z',
        },
        {
          'id': 'reference-other',
          'label': 'Эталон другой работы',
          'bytes': png,
          'layoutProfile': null,
          'createdAt': '2026-10-26T11:00:00.000Z',
        },
      ]),
      'reference_profiles_active_id_v2': 'reference-other',
      'reference_profiles_job_bindings_v1': jsonEncode({
        'job-1': 'reference-job-1',
      }),
    });
    expect((await ReferenceStorage.loadForJob('job-1'))?.id, 'reference-job-1');

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
            initialJob: const ProductionJobContext(
              jobId: 'job-1',
              jobNumber: 'WORK-001',
              customerId: 'customer-1',
              customerName: 'Заказчик',
              customerConfirmed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('reference_profiles_active_id_v2'),
        'reference-job-1');

    final stageLabels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((widget) => widget.properties.label)
        .whereType<String>()
        .where((label) => label.startsWith('Эталон.'))
        .toList();
    expect(
      stageLabels,
      contains('Эталон. Сохранён: Эталон работы 1'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new organization job does not borrow global active reference',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    SharedPreferences.setMockInitialValues({
      'reference_profiles_v2': jsonEncode([
        {
          'id': 'reference-other',
          'label': 'Чужой эталон',
          'bytes': png,
          'layoutProfile': null,
          'createdAt': '2026-10-26T11:00:00.000Z',
        },
      ]),
      'reference_profiles_active_id_v2': 'reference-other',
    });

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
            initialJob: const ProductionJobContext(
              jobId: 'job-new',
              jobNumber: 'WORK-NEW',
              customerId: 'customer-1',
              customerName: 'Заказчик',
              customerConfirmed: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Эталон. Загрузите цифровой файл',
      ),
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
