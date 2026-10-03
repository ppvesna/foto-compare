import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/production_workflow.dart';

class SupabaseProductionWorkflowService implements ProductionWorkflowService {
  final SupabaseClient client;

  const SupabaseProductionWorkflowService(this.client);

  @override
  Stream<void> watchWorks(String organizationId) {
    return client
        .from('production_jobs')
        .stream(primaryKey: const ['id'])
        .eq('organization_id', organizationId)
        .skip(1)
        .map((_) {});
  }

  @override
  Future<ProductionWorkPage> listWorks({
    required String organizationId,
    String search = '',
    ProductionWorkView view = ProductionWorkView.active,
    DateTime? cursorUpdatedAt,
    String? cursorId,
    int pageSize = 50,
  }) async {
    final response = await client.rpc(
      'list_production_works_v2',
      params: {
        'target_organization': organizationId,
        'search_text': search.trim(),
        'requested_view': view.wireValue,
        'cursor_updated_at': cursorUpdatedAt?.toUtc().toIso8601String(),
        'cursor_id': cursorId,
        'page_size': pageSize + 1,
      },
    );
    final rows = (response as List? ?? const [])
        .map((row) => _summary(Map<String, dynamic>.from(row as Map)))
        .toList(growable: true);
    final hasMore = rows.length > pageSize;
    if (hasMore) rows.removeLast();
    return ProductionWorkPage(items: rows, hasMore: hasMore);
  }

  @override
  Future<ProductionWorkDetail> loadWork(String jobId) async {
    Object? response;
    try {
      response = await client.rpc(
        'get_production_work_v3',
        params: {'target_job': jobId},
      );
    } catch (_) {
      response = await client.rpc(
        'get_production_work_v2',
        params: {'target_job': jobId},
      );
    }
    if (response is! Map) {
      throw StateError('Данные работы не получены');
    }
    final row = Map<String, dynamic>.from(response);
    final blocks = (row['blocks'] as List? ?? const [])
        .map((item) => _block(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    final history = (row['history'] as List? ?? const [])
        .map((item) => _event(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    final batches = (row['batches'] as List? ?? const [])
        .map((item) => _batch(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    return ProductionWorkDetail(
      summary: _summary(row,
          activeBlockCount: blocks.where((b) => b.isActive).length),
      blocks: blocks,
      history: history,
      batches: batches,
    );
  }

  @override
  Future<ProductionStage> advanceStage(
    String jobId, {
    String note = '',
  }) async {
    final response = await client.rpc(
      'advance_production_job_stage_v1',
      params: {'target_job': jobId, 'target_note': note.trim()},
    );
    return ProductionStage.fromWire(response as String?);
  }

  @override
  Future<List<ProductionWorker>> listWorkers(String jobId) async {
    final response = await client.rpc(
      'list_production_workers_v1',
      params: {'target_job': jobId},
    );
    return (response as List? ?? const []).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return ProductionWorker(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String? ?? '',
        nickname: row['nickname'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  @override
  Future<List<ProductionWorker>> listOrganizationWorkers(
    String organizationId,
  ) async {
    final response = await client.rpc(
      'list_organization_production_workers_v1',
      params: {'target_organization': organizationId},
    );
    return (response as List? ?? const []).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return ProductionWorker(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String? ?? '',
        nickname: row['nickname'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  @override
  Future<List<ProductionInspectionHistoryItem>> listInspectionHistory({
    required String organizationId,
    String search = '',
    int limit = 100,
  }) async {
    final response = await client.rpc(
      'list_production_inspection_history_v1',
      params: {
        'target_organization': organizationId,
        'search_text': search.trim(),
        'result_limit': limit,
      },
    );
    return (response as List? ?? const []).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return ProductionInspectionHistoryItem(
        attemptId: row['attempt_id'] as String,
        jobId: row['job_id'] as String,
        jobNumber: row['job_number'] as String? ?? '',
        customerName: row['customer_name'] as String? ?? '',
        batchNumber: (row['batch_no'] as num?)?.toInt() ?? 1,
        unitNumber: (row['unit_no'] as num?)?.toInt() ?? 1,
        unitType: ProductionUnitType.fromWire(row['unit_type'] as String?),
        inspectionNumber: (row['inspection_no'] as num?)?.toInt() ?? 1,
        attemptNumber: (row['attempt_no'] as num?)?.toInt() ?? 1,
        protocolOwnerUserId: row['protocol_owner_user_id'] as String? ?? '',
        protocolId: row['protocol_id'] as String? ?? '',
        score: (row['score'] as num?)?.toDouble() ?? 0,
        attemptedByUserId: row['attempted_by_user_id'] as String? ?? '',
        attemptedByName: row['attempted_by_name'] as String? ?? '',
        attemptedAt: DateTime.parse(row['attempted_at'] as String),
        decisionStatus: row['decision_status'] as String? ?? 'checking',
        decisionNote: row['decision_note'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  @override
  Future<String> createBatch({
    required String jobId,
    String? employeeUserId,
    required String reason,
    String machine = '',
    String material = '',
    String format = '',
    String inks = '',
  }) async {
    final response = await client.rpc(
      'create_production_batch_v1',
      params: {
        'target_job': jobId,
        'target_employee': employeeUserId,
        'target_reason': reason.trim(),
        'target_machine': machine.trim(),
        'target_material': material.trim(),
        'target_format': format.trim(),
        'target_inks': inks.trim(),
      },
    );
    return response as String;
  }

  @override
  Future<String> createUnit({
    required String batchId,
    required ProductionUnitType type,
  }) async {
    final response = await client.rpc(
      'create_production_unit_v1',
      params: {
        'target_batch': batchId,
        'target_unit_type': type.wireValue,
      },
    );
    return response as String;
  }

  @override
  Future<String> recordInspectionAttempt({
    required String unitId,
    required String protocolId,
    required double score,
  }) async {
    final response = await client.rpc(
      'record_production_inspection_attempt_v1',
      params: {
        'target_unit': unitId,
        'target_protocol_id': protocolId,
        'target_score': score,
      },
    );
    return response as String;
  }

  @override
  Future<void> decideInspection({
    required String unitId,
    required ProductionInspectionDecision decision,
    String note = '',
  }) async {
    await client.rpc(
      'decide_production_inspection_v1',
      params: {
        'target_unit': unitId,
        'requested_decision': decision.name,
        'target_note': note.trim(),
      },
    );
  }

  @override
  Future<void> blockUnit({
    required String unitId,
    required String reason,
  }) async {
    await client.rpc(
      'block_production_unit_v1',
      params: {
        'target_unit': unitId,
        'target_reason': reason.trim(),
      },
    );
  }

  @override
  Future<void> completeWork(String jobId) async {
    await client.rpc(
      'complete_production_work_v1',
      params: {'target_job': jobId},
    );
  }

  @override
  Future<void> restoreWork(String jobId) async {
    await client.rpc(
      'restore_production_work_v1',
      params: {'target_job': jobId},
    );
  }

  @override
  Future<String> blockWork({
    required String jobId,
    required String scopeLabel,
    required String reason,
    bool customerVisible = false,
  }) async {
    final response = await client.rpc(
      'block_production_job_v1',
      params: {
        'target_job': jobId,
        'target_scope_label': scopeLabel.trim(),
        'target_reason': reason.trim(),
        'requested_customer_visible': customerVisible,
      },
    );
    return response as String;
  }

  @override
  Future<void> resolveBlock(String blockId, {String note = ''}) async {
    await client.rpc(
      'resolve_production_job_block_v1',
      params: {
        'target_block': blockId,
        'target_resolution_note': note.trim(),
      },
    );
  }

  @override
  Future<List<ProductionControllerCandidate>> listControllerCandidates(
    String jobId,
  ) async {
    final response = await client.rpc(
      'list_job_controller_candidates_v1',
      params: {'target_job': jobId},
    );
    return (response as List? ?? const []).map((item) {
      final row = Map<String, dynamic>.from(item as Map);
      return ProductionControllerCandidate(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String? ?? '',
        nickname: row['nickname'] as String? ?? '',
        canBlock: row['can_block'] == true,
        canUnblock: row['can_unblock'] == true,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> setController({
    required String jobId,
    required String userId,
    required bool canBlock,
    required bool canUnblock,
  }) async {
    await client.rpc(
      'set_job_controller_v1',
      params: {
        'target_job': jobId,
        'target_user': userId,
        'requested_can_block': canBlock,
        'requested_can_unblock': canUnblock,
      },
    );
  }

  ProductionWorkSummary _summary(
    Map<String, dynamic> row, {
    int? activeBlockCount,
  }) {
    return ProductionWorkSummary(
      jobId: row['job_id'] as String,
      jobNumber: row['job_number'] as String? ?? '',
      customerId: row['customer_id'] as String?,
      customerName: row['customer_name'] as String? ?? '',
      jobStatus: row['job_status'] as String? ?? 'active',
      stage: ProductionStage.fromWire(row['stage_code'] as String?),
      flowState: ProductionFlowState.fromWire(row['flow_state'] as String?),
      activeBlockCount:
          activeBlockCount ?? (row['active_block_count'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      canAdvance: row['can_advance'] == true,
      canAssignControllers: row['can_assign_controllers'] == true,
      canBlock: row['can_block'] == true,
      canUnblock: row['can_unblock'] == true,
      isCustomerView: row['is_customer'] == true,
      canCreateBatch: row['can_create_batch'] == true,
      canComplete: row['can_complete'] == true,
      canRestore: row['can_restore'] == true,
    );
  }

  ProductionBatch _batch(Map<String, dynamic> row) => ProductionBatch(
        id: row['id'] as String,
        number: (row['sequence_no'] as num?)?.toInt() ?? 1,
        employeeUserId: row['employee_user_id'] as String? ?? '',
        employeeName: row['employee_name'] as String? ?? '',
        reason: row['creation_reason'] as String? ?? '',
        machine: row['machine_label'] as String? ?? '',
        material: row['material_label'] as String? ?? '',
        format: row['format_label'] as String? ?? '',
        inks: row['inks_label'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        units: (row['units'] as List? ?? const [])
            .map((item) => _unit(Map<String, dynamic>.from(item as Map)))
            .toList(growable: false),
      );

  ProductionWorkUnit _unit(Map<String, dynamic> row) => ProductionWorkUnit(
        id: row['id'] as String,
        batchId: row['batch_id'] as String,
        batchNumber: (row['batch_number'] as num?)?.toInt() ?? 1,
        number: (row['sequence_no'] as num?)?.toInt() ?? 1,
        type: ProductionUnitType.fromWire(row['unit_type'] as String?),
        state: ProductionUnitState.fromWire(row['status'] as String?),
        inspectionCount: (row['inspection_count'] as num?)?.toInt() ?? 0,
        attemptCount: (row['attempt_count'] as num?)?.toInt() ?? 0,
        latestScore: (row['latest_score'] as num?)?.toDouble(),
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  ProductionJobBlock _block(Map<String, dynamic> row) => ProductionJobBlock(
        id: row['id'] as String,
        stage: ProductionStage.fromWire(row['stage_code'] as String?),
        scopeLabel: row['scope_label'] as String? ?? '',
        reason: row['reason'] as String? ?? '',
        customerVisible: row['customer_visible'] == true,
        createdByName: row['created_by_name'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
        resolvedAt: row['resolved_at'] == null
            ? null
            : DateTime.tryParse(row['resolved_at'] as String),
        resolutionNote: row['resolution_note'] as String? ?? '',
      );

  ProductionStageEvent _event(Map<String, dynamic> row) => ProductionStageEvent(
        id: row['id'] as String,
        fromStage: row['from_stage'] == null
            ? null
            : ProductionStage.fromWire(row['from_stage'] as String?),
        toStage: ProductionStage.fromWire(row['to_stage'] as String?),
        eventType: row['event_type'] as String? ?? '',
        note: row['note'] as String? ?? '',
        actorName: row['actor_name'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
