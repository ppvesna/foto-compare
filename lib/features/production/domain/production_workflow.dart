enum ProductionStage {
  preparation,
  prepress,
  printing,
  qualityControl,
  completed;

  static ProductionStage fromWire(String? value) => switch (value) {
        'prepress' => ProductionStage.prepress,
        'printing' => ProductionStage.printing,
        'quality_control' => ProductionStage.qualityControl,
        'completed' => ProductionStage.completed,
        _ => ProductionStage.preparation,
      };

  String get wireValue => switch (this) {
        ProductionStage.preparation => 'preparation',
        ProductionStage.prepress => 'prepress',
        ProductionStage.printing => 'printing',
        ProductionStage.qualityControl => 'quality_control',
        ProductionStage.completed => 'completed',
      };

  String get label => switch (this) {
        ProductionStage.preparation => 'Подготовка',
        ProductionStage.prepress => 'Допечатная проверка',
        ProductionStage.printing => 'Печать',
        ProductionStage.qualityControl => 'Контроль качества',
        ProductionStage.completed => 'Завершено',
      };
}

enum ProductionFlowState {
  ready,
  blocked,
  completed;

  static ProductionFlowState fromWire(String? value) => switch (value) {
        'blocked' => ProductionFlowState.blocked,
        'completed' => ProductionFlowState.completed,
        _ => ProductionFlowState.ready,
      };

  String get label => switch (this) {
        ProductionFlowState.ready => 'Готова к следующему этапу',
        ProductionFlowState.blocked => 'Заблокирована',
        ProductionFlowState.completed => 'Завершена',
      };
}

enum ProductionWorkView {
  active,
  archived;

  String get wireValue => name;

  String get label => switch (this) {
        ProductionWorkView.active => 'В работе',
        ProductionWorkView.archived => 'Архив',
      };
}

enum ProductionUnitType {
  stack,
  roll;

  static ProductionUnitType fromWire(String? value) =>
      value == 'roll' ? ProductionUnitType.roll : ProductionUnitType.stack;

  String get wireValue => name;
  String get label => this == ProductionUnitType.stack ? 'Стопа' : 'Рулон';
}

enum ProductionUnitState {
  pending,
  checking,
  approved,
  blocked;

  static ProductionUnitState fromWire(String? value) => switch (value) {
        'checking' => ProductionUnitState.checking,
        'approved' => ProductionUnitState.approved,
        'blocked' => ProductionUnitState.blocked,
        _ => ProductionUnitState.pending,
      };

  String get label => switch (this) {
        ProductionUnitState.pending => 'Ожидает проверки',
        ProductionUnitState.checking => 'Проверяется',
        ProductionUnitState.approved => 'Допущено',
        ProductionUnitState.blocked => 'Заблокировано',
      };
}

enum ProductionInspectionDecision { approved, blocked }

class ProductionWorkSummary {
  final String jobId;
  final String jobNumber;
  final String? customerId;
  final String customerName;
  final String jobStatus;
  final ProductionStage stage;
  final ProductionFlowState flowState;
  final int activeBlockCount;
  final DateTime updatedAt;
  final bool canAdvance;
  final bool canAssignControllers;
  final bool canBlock;
  final bool canUnblock;
  final bool isCustomerView;
  final bool canCreateBatch;
  final bool canComplete;
  final bool canRestore;

  const ProductionWorkSummary({
    required this.jobId,
    required this.jobNumber,
    this.customerId,
    required this.customerName,
    required this.jobStatus,
    required this.stage,
    required this.flowState,
    required this.activeBlockCount,
    required this.updatedAt,
    required this.canAdvance,
    required this.canAssignControllers,
    required this.canBlock,
    required this.canUnblock,
    this.isCustomerView = false,
    this.canCreateBatch = false,
    this.canComplete = false,
    this.canRestore = false,
  });

  String get customerStatus =>
      jobStatus == 'completed' || jobStatus == 'archived'
          ? 'Выполнен'
          : 'В работе';
}

class ProductionWorkPage {
  final List<ProductionWorkSummary> items;
  final bool hasMore;

  const ProductionWorkPage({required this.items, required this.hasMore});
}

class ProductionJobBlock {
  final String id;
  final ProductionStage stage;
  final String scopeLabel;
  final String reason;
  final bool customerVisible;
  final String createdByName;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String resolutionNote;

  const ProductionJobBlock({
    required this.id,
    required this.stage,
    required this.scopeLabel,
    required this.reason,
    required this.customerVisible,
    required this.createdByName,
    required this.createdAt,
    this.resolvedAt,
    required this.resolutionNote,
  });

  bool get isActive => resolvedAt == null;
}

class ProductionStageEvent {
  final String id;
  final ProductionStage? fromStage;
  final ProductionStage toStage;
  final String eventType;
  final String note;
  final String actorName;
  final DateTime createdAt;

  const ProductionStageEvent({
    required this.id,
    this.fromStage,
    required this.toStage,
    required this.eventType,
    required this.note,
    required this.actorName,
    required this.createdAt,
  });
}

class ProductionWorkDetail {
  final ProductionWorkSummary summary;
  final List<ProductionJobBlock> blocks;
  final List<ProductionStageEvent> history;
  final List<ProductionBatch> batches;

  const ProductionWorkDetail({
    required this.summary,
    required this.blocks,
    required this.history,
    this.batches = const [],
  });
}

class ProductionInspectionHistoryItem {
  final String attemptId;
  final String jobId;
  final String jobNumber;
  final String customerName;
  final int batchNumber;
  final int unitNumber;
  final ProductionUnitType unitType;
  final int inspectionNumber;
  final int attemptNumber;
  final String protocolOwnerUserId;
  final String protocolId;
  final double score;
  final String attemptedByUserId;
  final String attemptedByName;
  final DateTime attemptedAt;
  final String decisionStatus;
  final String decisionNote;

  const ProductionInspectionHistoryItem({
    required this.attemptId,
    required this.jobId,
    required this.jobNumber,
    required this.customerName,
    required this.batchNumber,
    required this.unitNumber,
    required this.unitType,
    required this.inspectionNumber,
    required this.attemptNumber,
    required this.protocolOwnerUserId,
    required this.protocolId,
    required this.score,
    required this.attemptedByUserId,
    required this.attemptedByName,
    required this.attemptedAt,
    required this.decisionStatus,
    required this.decisionNote,
  });

  String get unitLabel => '${unitType.label} №$unitNumber';
}

class ProductionWorker {
  final String userId;
  final String displayName;
  final String nickname;

  const ProductionWorker({
    required this.userId,
    required this.displayName,
    required this.nickname,
  });

  String get label => displayName.trim().isNotEmpty
      ? displayName.trim()
      : nickname.trim().isNotEmpty
          ? nickname.trim()
          : 'Сотрудник';
}

class ProductionBatch {
  final String id;
  final int number;
  final String employeeUserId;
  final String employeeName;
  final String reason;
  final String machine;
  final String material;
  final String format;
  final String inks;
  final DateTime createdAt;
  final List<ProductionWorkUnit> units;

  const ProductionBatch({
    required this.id,
    required this.number,
    this.employeeUserId = '',
    required this.employeeName,
    required this.reason,
    required this.machine,
    required this.material,
    required this.format,
    required this.inks,
    required this.createdAt,
    this.units = const [],
  });

  String get label => 'Партия №$number';
}

class ProductionWorkUnit {
  final String id;
  final String batchId;
  final int batchNumber;
  final int number;
  final ProductionUnitType type;
  final ProductionUnitState state;
  final int inspectionCount;
  final int attemptCount;
  final double? latestScore;
  final DateTime createdAt;

  const ProductionWorkUnit({
    required this.id,
    required this.batchId,
    required this.batchNumber,
    required this.number,
    required this.type,
    required this.state,
    required this.inspectionCount,
    required this.attemptCount,
    required this.latestScore,
    required this.createdAt,
  });

  String get label => '${type.label} №$number';
  String get fullLabel => 'Партия №$batchNumber · $label';
}

class ProductionComparisonTarget {
  final ProductionWorkSummary work;
  final ProductionWorkUnit unit;

  const ProductionComparisonTarget({required this.work, required this.unit});
}

enum ProductionChatChannel { internal, customer }

class ProductionChatTarget {
  final ProductionWorkSummary work;
  final ProductionChatChannel channel;

  const ProductionChatTarget({
    required this.work,
    required this.channel,
  });
}

class ProductionControllerCandidate {
  final String userId;
  final String displayName;
  final String nickname;
  final bool canBlock;
  final bool canUnblock;

  const ProductionControllerCandidate({
    required this.userId,
    required this.displayName,
    required this.nickname,
    required this.canBlock,
    required this.canUnblock,
  });

  String get label => displayName.trim().isNotEmpty
      ? displayName.trim()
      : nickname.trim().isNotEmpty
          ? nickname.trim()
          : 'Сотрудник';

  ProductionControllerCandidate copyWith({
    bool? canBlock,
    bool? canUnblock,
  }) =>
      ProductionControllerCandidate(
        userId: userId,
        displayName: displayName,
        nickname: nickname,
        canBlock: canBlock ?? this.canBlock,
        canUnblock: canUnblock ?? this.canUnblock,
      );
}

abstract interface class ProductionWorkflowService {
  Stream<void> watchWorks(String organizationId);

  Future<ProductionWorkPage> listWorks({
    required String organizationId,
    String search = '',
    ProductionWorkView view = ProductionWorkView.active,
    DateTime? cursorUpdatedAt,
    String? cursorId,
    int pageSize = 50,
  });

  Future<ProductionWorkDetail> loadWork(String jobId);

  Future<ProductionStage> advanceStage(String jobId, {String note = ''});

  Future<List<ProductionWorker>> listWorkers(String jobId);

  Future<List<ProductionWorker>> listOrganizationWorkers(
    String organizationId,
  );

  Future<List<ProductionInspectionHistoryItem>> listInspectionHistory({
    required String organizationId,
    String search = '',
    int limit = 100,
  });

  Future<String> createBatch({
    required String jobId,
    String? employeeUserId,
    required String reason,
    String machine = '',
    String material = '',
    String format = '',
    String inks = '',
  });

  Future<String> createUnit({
    required String batchId,
    required ProductionUnitType type,
  });

  Future<String> recordInspectionAttempt({
    required String unitId,
    required String protocolId,
    required double score,
  });

  Future<void> decideInspection({
    required String unitId,
    required ProductionInspectionDecision decision,
    String note = '',
  });

  Future<void> blockUnit({
    required String unitId,
    required String reason,
  });

  Future<void> completeWork(String jobId);

  Future<void> restoreWork(String jobId);

  Future<String> blockWork({
    required String jobId,
    required String scopeLabel,
    required String reason,
    bool customerVisible = false,
  });

  Future<void> resolveBlock(String blockId, {String note = ''});

  Future<List<ProductionControllerCandidate>> listControllerCandidates(
    String jobId,
  );

  Future<void> setController({
    required String jobId,
    required String userId,
    required bool canBlock,
    required bool canUnblock,
  });
}
