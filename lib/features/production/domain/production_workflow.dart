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
  blocked,
  completed,
  archived;

  String get wireValue => name;

  String get label => switch (this) {
        ProductionWorkView.active => 'Активные',
        ProductionWorkView.blocked => 'Заблокированные',
        ProductionWorkView.completed => 'Завершённые',
        ProductionWorkView.archived => 'Архив',
      };
}

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
  });
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

  const ProductionWorkDetail({
    required this.summary,
    required this.blocks,
    required this.history,
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
