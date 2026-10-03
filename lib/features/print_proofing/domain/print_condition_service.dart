import 'dart:typed_data';

import 'icc_profile_inspector.dart';
import 'print_condition.dart';

class PrintConditionDraft {
  final String displayName;
  final String machineName;
  final String materialName;
  final String inkSet;
  final String measurementCondition;

  const PrintConditionDraft({
    required this.displayName,
    required this.machineName,
    required this.materialName,
    required this.inkSet,
    this.measurementCondition = 'D50 · 2° · M1',
  });
}

abstract interface class PrintConditionService {
  Future<bool> canManageConditions(String organizationId);

  Future<bool> canAdministerConditions(String organizationId);

  Future<List<PrintCondition>> listConditions(
    String organizationId, {
    bool includeArchived = false,
  });

  Future<PrintCondition> createQuickDraft({
    required String organizationId,
    required PrintConditionDraft draft,
  });

  Future<PrintCondition> createIccDraft({
    required String organizationId,
    required PrintConditionDraft draft,
    required String fileName,
    required Uint8List bytes,
    required IccProfileInspection inspection,
  });

  Future<void> archiveCondition(String conditionId);

  Future<void> restoreCondition(String conditionId);

  Future<void> deleteConditionPermanently(String conditionId);
}
