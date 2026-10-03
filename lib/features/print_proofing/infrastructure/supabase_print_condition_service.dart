import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/icc_profile_inspector.dart';
import '../domain/print_condition.dart';
import '../domain/print_condition_service.dart';

class SupabasePrintConditionService implements PrintConditionService {
  static const _bucket = 'trimatrix-assets';

  final SupabaseClient client;

  const SupabasePrintConditionService(this.client);

  @override
  Future<bool> canManageConditions(String organizationId) async {
    final response = await client.rpc(
      'can_manage_print_conditions_v1',
      params: {'target_organization': organizationId},
    );
    return response == true;
  }

  @override
  Future<bool> canAdministerConditions(String organizationId) async {
    final response = await client.rpc(
      'can_administer_print_conditions_v1',
      params: {'target_organization': organizationId},
    );
    return response == true;
  }

  @override
  Future<List<PrintCondition>> listConditions(
    String organizationId, {
    bool includeArchived = false,
  }) async {
    final response = await client.rpc(
      'list_print_conditions_v1',
      params: {
        'target_organization': organizationId,
        'include_archived': includeArchived,
      },
    );
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((value) => _fromRow(Map<String, dynamic>.from(value)))
        .toList(growable: false);
  }

  @override
  Future<PrintCondition> createQuickDraft({
    required String organizationId,
    required PrintConditionDraft draft,
  }) async {
    final id = await _createDraft(
      organizationId: organizationId,
      draft: draft,
      source: PrintConditionSource.quickCamera,
    );
    return _findCreated(organizationId, id);
  }

  @override
  Future<PrintCondition> createIccDraft({
    required String organizationId,
    required PrintConditionDraft draft,
    required String fileName,
    required Uint8List bytes,
    required IccProfileInspection inspection,
  }) async {
    if (!inspection.accepted) {
      throw const FormatException('unsupported_print_icc');
    }
    final id = await _createDraft(
      organizationId: organizationId,
      draft: draft,
      source: PrintConditionSource.iccImport,
    );
    final storagePath =
        'organizations/$organizationId/print-profiles/$id/profile.icc';
    try {
      await client.storage.from(_bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: 'application/vnd.iccprofile',
              upsert: false,
              metadata: {'source_file_name': fileName},
            ),
          );
      final evidence = inspection.evidence;
      final white = inspection.mediaWhitePoint;
      await client.rpc(
        'attach_print_condition_icc_v1',
        params: {
          'target_condition': id,
          'target_file_name': fileName,
          'target_size_bytes': bytes.length,
          'target_profile_class': evidence.profileClass,
          'target_color_space': evidence.dataColorSpace,
          'target_connection_space': evidence.connectionSpace,
          'target_version': evidence.version,
          'target_storage_path': storagePath,
          'target_white_l': white?.l,
          'target_white_a': white?.a,
          'target_white_b': white?.b,
        },
      );
    } catch (_) {
      try {
        await client.storage.from(_bucket).remove([storagePath]);
      } catch (_) {
        // The draft remains visible and can be repaired without losing context.
      }
      rethrow;
    }
    return _findCreated(organizationId, id);
  }

  @override
  Future<void> archiveCondition(String conditionId) async {
    await client.rpc(
      'archive_print_condition_v1',
      params: {'target_condition': conditionId},
    );
  }

  @override
  Future<void> restoreCondition(String conditionId) async {
    await client.rpc(
      'restore_print_condition_v1',
      params: {'target_condition': conditionId},
    );
  }

  @override
  Future<void> deleteConditionPermanently(String conditionId) async {
    final storagePath = await client.rpc(
      'prepare_print_condition_permanent_delete_v1',
      params: {'target_condition': conditionId},
    );
    if (storagePath is String && storagePath.isNotEmpty) {
      await client.storage.from(_bucket).remove([storagePath]);
    }
    await client.rpc(
      'delete_print_condition_permanently_v1',
      params: {'target_condition': conditionId},
    );
  }

  Future<String> _createDraft({
    required String organizationId,
    required PrintConditionDraft draft,
    required PrintConditionSource source,
  }) async {
    final response = await client.rpc(
      'create_print_condition_draft_v1',
      params: {
        'target_organization': organizationId,
        'target_display_name': draft.displayName.trim(),
        'target_machine_name': draft.machineName.trim(),
        'target_material_name': draft.materialName.trim(),
        'target_ink_set': draft.inkSet.trim(),
        'target_source_method': source.name,
        'target_measurement_condition': draft.measurementCondition.trim(),
      },
    );
    if (response is String && response.isNotEmpty) return response;
    throw StateError('Supabase did not return the print condition ID');
  }

  Future<PrintCondition> _findCreated(
    String organizationId,
    String id,
  ) async {
    final conditions = await listConditions(organizationId);
    for (final condition in conditions) {
      if (condition.id == id) return condition;
    }
    throw StateError('The created print condition is unavailable');
  }

  static PrintCondition _fromRow(Map<String, dynamic> row) {
    final source = PrintConditionSource.values.firstWhere(
      (value) => value.name == row['source_method'],
      orElse: () => PrintConditionSource.quickCamera,
    );
    final status = PrintConditionStatus.values.firstWhere(
      (value) => value.name == row['status'],
      orElse: () => PrintConditionStatus.draft,
    );
    final whiteL = _double(row['media_white_l']);
    final whiteA = _double(row['media_white_a']);
    final whiteB = _double(row['media_white_b']);
    final white = whiteL == null || whiteA == null || whiteB == null
        ? null
        : PrintMediaWhitePoint(l: whiteL, a: whiteA, b: whiteB);
    final fileName = row['icc_file_name'] as String? ?? '';
    final cameraProfile = row['camera_calibration_profile'] as String? ?? '';
    return PrintCondition(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      displayName: row['display_name'] as String? ?? '',
      machineName: row['machine_name'] as String? ?? '',
      materialName: row['material_name'] as String? ?? '',
      inkSet: row['ink_set'] as String? ?? '',
      source: source,
      status: status,
      mediaWhitePoint: white,
      measurementCondition:
          row['measurement_condition'] as String? ?? 'D50 · 2° · M1',
      quickEvidence: cameraProfile.isEmpty
          ? null
          : QuickPrintProfileEvidence(
              cameraCalibrationProfileId: cameraProfile,
              trainingPatchCount: _integer(row['training_patch_count']),
              validationPatchCount: _integer(row['validation_patch_count']),
              averageDeltaE: _double(row['average_delta_e']),
              maximumDeltaE: _double(row['maximum_delta_e']),
            ),
      iccEvidence: fileName.isEmpty
          ? null
          : IccPrintProfileEvidence(
              fileName: fileName,
              sizeBytes: _integer(row['icc_size_bytes']),
              profileClass: row['icc_profile_class'] as String? ?? '',
              dataColorSpace: row['icc_color_space'] as String? ?? '',
              connectionSpace: row['icc_connection_space'] as String? ?? '',
              version: row['icc_version'] as String? ?? '',
              structurallyValid: true,
            ),
      customerVisible: row['customer_visible'] == true,
      usedInJobs: row['used_in_jobs'] == true,
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
    );
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');

  static int _integer(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
