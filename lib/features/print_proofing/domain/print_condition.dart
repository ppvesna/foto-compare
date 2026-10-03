enum PrintConditionSource {
  quickCamera,
  iccImport,
}

extension PrintConditionSourceLabel on PrintConditionSource {
  String get label => switch (this) {
        PrintConditionSource.quickCamera => 'Быстрый профиль камеры',
        PrintConditionSource.iccImport => 'Профессиональный ICC',
      };
}

enum PrintConditionStatus {
  draft,
  verified,
  published,
  archived,
}

extension PrintConditionStatusLabel on PrintConditionStatus {
  String get label => switch (this) {
        PrintConditionStatus.draft => 'Черновик',
        PrintConditionStatus.verified => 'Проверен',
        PrintConditionStatus.published => 'Опубликован',
        PrintConditionStatus.archived => 'Архив',
      };
}

class PrintMediaWhitePoint {
  final double l;
  final double a;
  final double b;

  const PrintMediaWhitePoint({
    required this.l,
    required this.a,
    required this.b,
  });

  bool get isPlausible =>
      l.isFinite &&
      a.isFinite &&
      b.isFinite &&
      l >= 0 &&
      l <= 100 &&
      a >= -128 &&
      a <= 127 &&
      b >= -128 &&
      b <= 127;

  Map<String, dynamic> toJson() => {'l': l, 'a': a, 'b': b};

  factory PrintMediaWhitePoint.fromJson(Map<String, dynamic> json) =>
      PrintMediaWhitePoint(
        l: (json['l'] as num).toDouble(),
        a: (json['a'] as num).toDouble(),
        b: (json['b'] as num).toDouble(),
      );
}

class QuickPrintProfileEvidence {
  final String cameraCalibrationProfileId;
  final int trainingPatchCount;
  final int validationPatchCount;
  final double? averageDeltaE;
  final double? maximumDeltaE;

  const QuickPrintProfileEvidence({
    required this.cameraCalibrationProfileId,
    required this.trainingPatchCount,
    required this.validationPatchCount,
    this.averageDeltaE,
    this.maximumDeltaE,
  });

  bool get isVerified =>
      cameraCalibrationProfileId.trim().isNotEmpty &&
      trainingPatchCount >= 4 &&
      validationPatchCount > 0 &&
      averageDeltaE != null &&
      maximumDeltaE != null &&
      averageDeltaE!.isFinite &&
      maximumDeltaE!.isFinite;
}

class IccPrintProfileEvidence {
  final String fileName;
  final int sizeBytes;
  final String profileClass;
  final String dataColorSpace;
  final String connectionSpace;
  final String version;
  final bool structurallyValid;

  const IccPrintProfileEvidence({
    required this.fileName,
    required this.sizeBytes,
    required this.profileClass,
    required this.dataColorSpace,
    required this.connectionSpace,
    required this.version,
    required this.structurallyValid,
  });

  bool get isSupportedOutputProfile =>
      structurallyValid &&
      profileClass == 'prtr' &&
      dataColorSpace == 'CMYK' &&
      (connectionSpace == 'Lab ' || connectionSpace == 'XYZ ');
}

class PrintCondition {
  final String id;
  final String organizationId;
  final String displayName;
  final String machineName;
  final String materialName;
  final String inkSet;
  final PrintConditionSource source;
  final PrintConditionStatus status;
  final PrintMediaWhitePoint? mediaWhitePoint;
  final String measurementCondition;
  final QuickPrintProfileEvidence? quickEvidence;
  final IccPrintProfileEvidence? iccEvidence;
  final bool customerVisible;
  final bool usedInJobs;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PrintCondition({
    required this.id,
    required this.organizationId,
    required this.displayName,
    required this.machineName,
    required this.materialName,
    required this.inkSet,
    required this.source,
    required this.status,
    required this.measurementCondition,
    required this.customerVisible,
    this.usedInJobs = false,
    required this.createdAt,
    required this.updatedAt,
    this.mediaWhitePoint,
    this.quickEvidence,
    this.iccEvidence,
  });

  bool get hasIdentity =>
      displayName.trim().isNotEmpty &&
      machineName.trim().isNotEmpty &&
      materialName.trim().isNotEmpty &&
      inkSet.trim().isNotEmpty;

  bool get hasPublishableEvidence => switch (source) {
        PrintConditionSource.quickCamera => quickEvidence?.isVerified == true &&
            mediaWhitePoint?.isPlausible == true,
        PrintConditionSource.iccImport =>
          iccEvidence?.isSupportedOutputProfile == true,
      };

  bool get canPublish => hasIdentity && hasPublishableEvidence;

  bool get customerSelectable =>
      status == PrintConditionStatus.published && customerVisible && canPublish;
}
