import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/organization/organization.dart';
import 'package:photo_compare/features/production/production.dart';
import 'package:photo_compare/screens/works_screen.dart';

void main() {
  testWidgets('work register opens status and selected comparison',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeWorkflowService();
    ProductionComparisonTarget? openedComparison;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorksScreen(
            organizationId: 'org-1',
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'org-1',
              role: OrganizationRole.admin,
            ),
            workflowService: service,
            onOpenComparison: (work) => openedComparison = work,
            onOpenChat: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VESNA-500'), findsOneWidget);
    expect(find.textContaining('Печать'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('work-row-job-500')));
    await tester.pumpAndSettle();

    expect(find.text('Заблокирована'), findsWidgets);
    expect(find.text('Листы 120–180'), findsOneWidget);
    expect(find.text('Полоса по краю'), findsWidgets);
    expect(find.byKey(const ValueKey('advance-work-stage')), findsOneWidget);
    final advance = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('advance-work-stage')),
    );
    expect(advance.onPressed, isNull);

    await tester.tap(find.text('Повторить'));
    expect(openedComparison?.work.jobId, 'job-500');
    expect(openedComparison?.unit.id, 'unit-1');
  });

  testWidgets('customer sees work status without comparison controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeWorkflowService(customerMode: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorksScreen(
            organizationId: 'org-1',
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'org-1',
              role: OrganizationRole.customer,
            ),
            workflowService: service,
            onOpenComparison: (_) {},
            onOpenChat: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('work-row-job-500')));
    await tester.pumpAndSettle();

    expect(find.text('В работе'), findsWidgets);
    expect(find.text('Партии и проверки'), findsNothing);
    expect(find.byKey(const ValueKey('block-work')), findsNothing);
    expect(find.text('Открыть чат'), findsOneWidget);
  });

  testWidgets('owner observes production details without working controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeWorkflowService(readOnlyMode: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorksScreen(
            organizationId: 'org-1',
            organizationAccess: OrganizationAccess.forRole(
              organizationId: 'org-1',
              role: OrganizationRole.owner,
            ),
            workflowService: service,
            onOpenComparison: (_) {},
            onOpenChat: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('work-row-job-500')));
    await tester.pumpAndSettle();

    expect(find.text('Партии и проверки'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('Добавить стопу или рулон'), findsNothing);
    expect(
        find.byKey(const ValueKey('complete-production-work')), findsNothing);
  });
}

class _FakeWorkflowService implements ProductionWorkflowService {
  final bool customerMode;
  final bool readOnlyMode;

  _FakeWorkflowService({
    this.customerMode = false,
    this.readOnlyMode = false,
  });

  ProductionWorkSummary get work => ProductionWorkSummary(
        jobId: 'job-500',
        jobNumber: 'VESNA-500',
        customerId: 'customer-1',
        customerName: 'Заказчик 500',
        jobStatus: 'active',
        stage: ProductionStage.printing,
        flowState: ProductionFlowState.blocked,
        activeBlockCount: 1,
        updatedAt: DateTime.utc(2026, 10, 3),
        canAdvance: !customerMode && !readOnlyMode,
        canAssignControllers: false,
        canBlock: !customerMode && !readOnlyMode,
        canUnblock: !customerMode && !readOnlyMode,
        isCustomerView: customerMode,
        canCreateBatch: !customerMode && !readOnlyMode,
        canComplete: !customerMode && !readOnlyMode,
        canRestore: false,
      );

  @override
  Stream<void> watchWorks(String organizationId) => const Stream.empty();

  @override
  Future<ProductionWorkPage> listWorks({
    required String organizationId,
    String search = '',
    ProductionWorkView view = ProductionWorkView.active,
    DateTime? cursorUpdatedAt,
    String? cursorId,
    int pageSize = 50,
  }) async =>
      ProductionWorkPage(items: [work], hasMore: false);

  @override
  Future<ProductionWorkDetail> loadWork(String jobId) async =>
      ProductionWorkDetail(
        summary: work,
        blocks: [
          ProductionJobBlock(
            id: 'block-1',
            stage: ProductionStage.printing,
            scopeLabel: 'Листы 120–180',
            reason: 'Полоса по краю',
            customerVisible: true,
            createdByName: 'Маша',
            createdAt: DateTime.utc(2026, 10, 3),
            resolutionNote: '',
          ),
        ],
        history: [
          ProductionStageEvent(
            id: 'event-1',
            toStage: ProductionStage.printing,
            eventType: 'blocked',
            note: 'Полоса по краю',
            actorName: 'Маша',
            createdAt: DateTime.utc(2026, 10, 3),
          ),
        ],
        batches: customerMode
            ? const []
            : [
                ProductionBatch(
                  id: 'batch-1',
                  number: 1,
                  employeeName: 'Маша',
                  reason: 'Работа создана',
                  machine: '',
                  material: 'Бумага',
                  format: '',
                  inks: '',
                  createdAt: DateTime.utc(2026, 10, 3),
                  units: [
                    ProductionWorkUnit(
                      id: 'unit-1',
                      batchId: 'batch-1',
                      batchNumber: 1,
                      number: 1,
                      type: ProductionUnitType.stack,
                      state: ProductionUnitState.blocked,
                      inspectionCount: 1,
                      attemptCount: 2,
                      latestScore: 82.4,
                      createdAt: DateTime.utc(2026, 10, 3),
                    ),
                  ],
                ),
              ],
      );

  @override
  Future<List<ProductionWorker>> listWorkers(String jobId) async => const [];

  @override
  Future<String> createBatch({
    required String jobId,
    String? employeeUserId,
    required String reason,
    String machine = '',
    String material = '',
    String format = '',
    String inks = '',
  }) async =>
      'batch-2';

  @override
  Future<String> createUnit({
    required String batchId,
    required ProductionUnitType type,
  }) async =>
      'unit-2';

  @override
  Future<String> recordInspectionAttempt({
    required String unitId,
    required String protocolId,
    required double score,
  }) async =>
      'inspection-1';

  @override
  Future<void> decideInspection({
    required String unitId,
    required ProductionInspectionDecision decision,
    String note = '',
  }) async {}

  @override
  Future<void> blockUnit({
    required String unitId,
    required String reason,
  }) async {}

  @override
  Future<void> completeWork(String jobId) async {}

  @override
  Future<void> restoreWork(String jobId) async {}

  @override
  Future<ProductionStage> advanceStage(String jobId,
          {String note = ''}) async =>
      ProductionStage.qualityControl;

  @override
  Future<String> blockWork({
    required String jobId,
    required String scopeLabel,
    required String reason,
    bool customerVisible = false,
  }) async =>
      'block-2';

  @override
  Future<void> resolveBlock(String blockId, {String note = ''}) async {}

  @override
  Future<List<ProductionControllerCandidate>> listControllerCandidates(
    String jobId,
  ) async =>
      const [];

  @override
  Future<void> setController({
    required String jobId,
    required String userId,
    required bool canBlock,
    required bool canUnblock,
  }) async {}
}
