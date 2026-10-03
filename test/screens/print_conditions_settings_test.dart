import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/billing/billing.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/features/print_proofing/print_proofing.dart';
import 'package:photo_compare/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('inspection specialist creates an honest quick condition draft',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakePrintConditionService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.employee,
            ),
            initialSection: 7,
            printConditionService: service,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('create-quick-print-condition')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('print-condition-machine')),
      'Машина 2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('print-condition-material')),
      'K-120',
    );
    await tester.tap(find.text('Создать черновик'));
    await tester.pumpAndSettle();

    expect(service.conditions, hasLength(1));
    expect(service.conditions.single.source, PrintConditionSource.quickCamera);
    expect(service.conditions.single.status, PrintConditionStatus.draft);
    expect(
      find.byKey(const ValueKey('print-condition-name')),
      findsNothing,
    );
    expect(find.text('Машина 2 · K-120 · CMYK'), findsOneWidget);
    expect(find.text('ожидает шкалу и фотографию'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer cannot create organization print conditions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.customer,
            ),
            initialSection: 7,
            printConditionService: _FakePrintConditionService(),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('create-quick-print-condition')),
      findsNothing,
    );
    expect(
      find.textContaining('Представитель использует только условия'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('administrator sees archive authority without create actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.admin,
            ),
            initialSection: 7,
            printConditionService: _FakePrintConditionService(
              canManage: false,
              canAdminister: true,
            ),
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('create-quick-print-condition')),
      findsNothing,
    );
    expect(
      find.textContaining('Администратор может окончательно удалить'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('specialist archives and restores a print condition',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakePrintConditionService(
      conditions: [_condition(id: 'condition-1')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.employee,
            ),
            initialSection: 7,
            printConditionService: service,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final archiveButton =
        find.byKey(const ValueKey('archive-print-condition-condition-1'));
    await tester.ensureVisible(archiveButton);
    await tester.tap(archiveButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('В архив'));
    await tester.pumpAndSettle();
    expect(service.conditions.single.status, PrintConditionStatus.archived);

    await tester.tap(
      find.byKey(const ValueKey('archived-print-conditions')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('restore-print-condition-condition-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('administrator permanently deletes only unused archive entry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakePrintConditionService(
      canManage: false,
      canAdminister: true,
      conditions: [
        _condition(
          id: 'unused',
          status: PrintConditionStatus.archived,
        ),
        _condition(
          id: 'used',
          status: PrintConditionStatus.archived,
          usedInJobs: true,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            entitlements: EntitlementSnapshot.forPlan(PlanTier.pro),
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'organization-1',
              organizationName: 'Vesna',
              role: OrganizationRole.admin,
            ),
            initialSection: 7,
            printConditionService: service,
            onAccessChanged: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('archived-print-conditions')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('delete-print-condition-unused')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('delete-print-condition-used')),
      findsNothing,
    );
    expect(find.textContaining('нельзя удалить из истории'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakePrintConditionService implements PrintConditionService {
  final bool canManage;
  final bool canAdminister;
  final List<PrintCondition> conditions;

  _FakePrintConditionService({
    this.canManage = true,
    this.canAdminister = false,
    List<PrintCondition>? conditions,
  }) : conditions = conditions ?? [];

  @override
  Future<bool> canManageConditions(String organizationId) async => canManage;

  @override
  Future<bool> canAdministerConditions(String organizationId) async =>
      canAdminister;

  @override
  Future<List<PrintCondition>> listConditions(
    String organizationId, {
    bool includeArchived = false,
  }) async =>
      List.unmodifiable(
        includeArchived
            ? conditions
            : conditions.where(
                (condition) =>
                    condition.status != PrintConditionStatus.archived,
              ),
      );

  @override
  Future<PrintCondition> createQuickDraft({
    required String organizationId,
    required PrintConditionDraft draft,
  }) async {
    final now = DateTime.utc(2026, 10, 3);
    final condition = PrintCondition(
      id: 'condition-${conditions.length + 1}',
      organizationId: organizationId,
      displayName: draft.displayName,
      machineName: draft.machineName,
      materialName: draft.materialName,
      inkSet: draft.inkSet,
      source: PrintConditionSource.quickCamera,
      status: PrintConditionStatus.draft,
      measurementCondition: draft.measurementCondition,
      customerVisible: false,
      createdAt: now,
      updatedAt: now,
    );
    conditions.add(condition);
    return condition;
  }

  @override
  Future<PrintCondition> createIccDraft({
    required String organizationId,
    required PrintConditionDraft draft,
    required String fileName,
    required Uint8List bytes,
    required IccProfileInspection inspection,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> archiveCondition(String conditionId) async {
    _replace(
      conditionId,
      (condition) => _condition(
        id: condition.id,
        displayName: condition.displayName,
        status: PrintConditionStatus.archived,
        usedInJobs: condition.usedInJobs,
      ),
    );
  }

  @override
  Future<void> restoreCondition(String conditionId) async {
    _replace(
      conditionId,
      (condition) => _condition(
        id: condition.id,
        displayName: condition.displayName,
      ),
    );
  }

  @override
  Future<void> deleteConditionPermanently(String conditionId) async {
    conditions.removeWhere((condition) => condition.id == conditionId);
  }

  void _replace(
    String id,
    PrintCondition Function(PrintCondition condition) replace,
  ) {
    final index = conditions.indexWhere((condition) => condition.id == id);
    conditions[index] = replace(conditions[index]);
  }
}

PrintCondition _condition({
  required String id,
  String displayName = 'Машина 2 · K-120 · CMYK',
  PrintConditionStatus status = PrintConditionStatus.draft,
  bool usedInJobs = false,
}) {
  final now = DateTime.utc(2026, 10, 3);
  return PrintCondition(
    id: id,
    organizationId: 'organization-1',
    displayName: displayName,
    machineName: 'Машина 2',
    materialName: 'K-120',
    inkSet: 'CMYK',
    source: PrintConditionSource.quickCamera,
    status: status,
    measurementCondition: 'D50 · 2° · M1',
    customerVisible: false,
    usedInJobs: usedInJobs,
    createdAt: now,
    updatedAt: now,
  );
}
