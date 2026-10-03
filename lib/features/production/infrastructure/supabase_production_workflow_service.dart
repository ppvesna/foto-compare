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
      'list_production_works_v1',
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
    final response = await client.rpc(
      'get_production_work_v1',
      params: {'target_job': jobId},
    );
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
    return ProductionWorkDetail(
      summary: _summary(row,
          activeBlockCount: blocks.where((b) => b.isActive).length),
      blocks: blocks,
      history: history,
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
    );
  }

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
