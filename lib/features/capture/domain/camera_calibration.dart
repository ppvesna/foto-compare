import 'dart:math' as math;

enum CalibrationMeasurementCondition { m0, m1, m2, m3 }

extension CalibrationMeasurementConditionLabel
    on CalibrationMeasurementCondition {
  String get label => switch (this) {
        CalibrationMeasurementCondition.m0 => 'M0 · лампа A',
        CalibrationMeasurementCondition.m1 => 'M1 · D50, с UV',
        CalibrationMeasurementCondition.m2 => 'M2 · UV-cut',
        CalibrationMeasurementCondition.m3 => 'M3 · поляризация',
      };
}

class CameraCalibrationPatch {
  final String id;
  final String label;
  final double red;
  final double green;
  final double blue;
  final double labL;
  final double labA;
  final double labB;
  final double? densityC;
  final double? densityM;
  final double? densityY;
  final double? densityK;
  final bool validation;

  const CameraCalibrationPatch({
    required this.id,
    required this.label,
    required this.red,
    required this.green,
    required this.blue,
    required this.labL,
    required this.labA,
    required this.labB,
    this.densityC,
    this.densityM,
    this.densityY,
    this.densityK,
    this.validation = false,
  });

  bool get hasDensities =>
      densityC != null &&
      densityM != null &&
      densityY != null &&
      densityK != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'red': red,
        'green': green,
        'blue': blue,
        'labL': labL,
        'labA': labA,
        'labB': labB,
        'densityC': densityC,
        'densityM': densityM,
        'densityY': densityY,
        'densityK': densityK,
        'validation': validation,
      };

  factory CameraCalibrationPatch.fromJson(Map<String, dynamic> json) =>
      CameraCalibrationPatch(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        red: (json['red'] as num).toDouble(),
        green: (json['green'] as num).toDouble(),
        blue: (json['blue'] as num).toDouble(),
        labL: (json['labL'] as num).toDouble(),
        labA: (json['labA'] as num).toDouble(),
        labB: (json['labB'] as num).toDouble(),
        densityC: (json['densityC'] as num?)?.toDouble(),
        densityM: (json['densityM'] as num?)?.toDouble(),
        densityY: (json['densityY'] as num?)?.toDouble(),
        densityK: (json['densityK'] as num?)?.toDouble(),
        validation: json['validation'] as bool? ?? false,
      );
}

class CameraCalibrationModel {
  final List<double> labCoefficients;
  final List<double>? densityCoefficients;
  final double? validationMeanDeltaE;
  final double? validationMaxDeltaE;
  final double? validationDensityMae;
  final DateTime calculatedAt;

  const CameraCalibrationModel({
    required this.labCoefficients,
    required this.densityCoefficients,
    required this.validationMeanDeltaE,
    required this.validationMaxDeltaE,
    required this.validationDensityMae,
    required this.calculatedAt,
  });

  ({double l, double a, double b}) labForRgb(
    double red,
    double green,
    double blue,
  ) {
    final features = _features(red, green, blue);
    return (
      l: _predict(labCoefficients, 0, features),
      a: _predict(labCoefficients, 1, features),
      b: _predict(labCoefficients, 2, features),
    );
  }

  ({double c, double m, double y, double k})? densityForRgb(
    double red,
    double green,
    double blue,
  ) {
    final coefficients = densityCoefficients;
    if (coefficients == null) return null;
    final features = _features(red, green, blue);
    return (
      c: math.max(0, _predict(coefficients, 0, features)),
      m: math.max(0, _predict(coefficients, 1, features)),
      y: math.max(0, _predict(coefficients, 2, features)),
      k: math.max(0, _predict(coefficients, 3, features)),
    );
  }

  Map<String, dynamic> toJson() => {
        'labCoefficients': labCoefficients,
        'densityCoefficients': densityCoefficients,
        'validationMeanDeltaE': validationMeanDeltaE,
        'validationMaxDeltaE': validationMaxDeltaE,
        'validationDensityMae': validationDensityMae,
        'calculatedAt': calculatedAt.toIso8601String(),
      };

  factory CameraCalibrationModel.fromJson(Map<String, dynamic> json) =>
      CameraCalibrationModel(
        labCoefficients: (json['labCoefficients'] as List)
            .map((value) => (value as num).toDouble())
            .toList(growable: false),
        densityCoefficients: (json['densityCoefficients'] as List?)
            ?.map((value) => (value as num).toDouble())
            .toList(growable: false),
        validationMeanDeltaE:
            (json['validationMeanDeltaE'] as num?)?.toDouble(),
        validationMaxDeltaE: (json['validationMaxDeltaE'] as num?)?.toDouble(),
        validationDensityMae:
            (json['validationDensityMae'] as num?)?.toDouble(),
        calculatedAt: DateTime.parse(json['calculatedAt'] as String),
      );

  static List<double> _features(double red, double green, double blue) => [
        1,
        red.clamp(0, 255) / 255,
        green.clamp(0, 255) / 255,
        blue.clamp(0, 255) / 255,
      ];

  static double _predict(
    List<double> coefficients,
    int output,
    List<double> features,
  ) {
    var value = 0.0;
    final offset = output * features.length;
    for (var index = 0; index < features.length; index++) {
      value += coefficients[offset + index] * features[index];
    }
    return value;
  }
}

class CameraCalibrationProfile {
  final String id;
  final String name;
  final String camera;
  final String lens;
  final String lighting;
  final String opticalFilter;
  final CalibrationMeasurementCondition measurementCondition;
  final List<CameraCalibrationPatch> patches;
  final CameraCalibrationModel? model;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CameraCalibrationProfile({
    required this.id,
    required this.name,
    required this.camera,
    required this.lens,
    required this.lighting,
    required this.opticalFilter,
    required this.measurementCondition,
    required this.patches,
    required this.model,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
  });

  int get trainingPatchCount =>
      patches.where((patch) => !patch.validation).length;
  int get validationPatchCount =>
      patches.where((patch) => patch.validation).length;
  bool get readyToCalculate => trainingPatchCount >= 4;

  CameraCalibrationProfile copyWith({
    String? name,
    String? camera,
    String? lens,
    String? lighting,
    String? opticalFilter,
    CalibrationMeasurementCondition? measurementCondition,
    List<CameraCalibrationPatch>? patches,
    CameraCalibrationModel? model,
    bool clearModel = false,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return CameraCalibrationProfile(
      id: id,
      name: name ?? this.name,
      camera: camera ?? this.camera,
      lens: lens ?? this.lens,
      lighting: lighting ?? this.lighting,
      opticalFilter: opticalFilter ?? this.opticalFilter,
      measurementCondition: measurementCondition ?? this.measurementCondition,
      patches: patches ?? this.patches,
      model: clearModel ? null : model ?? this.model,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'camera': camera,
        'lens': lens,
        'lighting': lighting,
        'opticalFilter': opticalFilter,
        'measurementCondition': measurementCondition.name,
        'patches': patches.map((patch) => patch.toJson()).toList(),
        'model': model?.toJson(),
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CameraCalibrationProfile.fromJson(Map<String, dynamic> json) =>
      CameraCalibrationProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        camera: json['camera'] as String? ?? '',
        lens: json['lens'] as String? ?? '',
        lighting: json['lighting'] as String? ?? '',
        opticalFilter: json['opticalFilter'] as String? ?? '',
        measurementCondition: CalibrationMeasurementCondition.values.firstWhere(
          (value) => value.name == json['measurementCondition'],
          orElse: () => CalibrationMeasurementCondition.m1,
        ),
        patches: (json['patches'] as List? ?? const [])
            .map(
              (value) => CameraCalibrationPatch.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(growable: false),
        model: json['model'] == null
            ? null
            : CameraCalibrationModel.fromJson(
                Map<String, dynamic>.from(json['model'] as Map),
              ),
        enabled: json['enabled'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

class CameraCalibrationException implements Exception {
  final String message;

  const CameraCalibrationException(this.message);

  @override
  String toString() => message;
}

class CameraCalibrationFitter {
  const CameraCalibrationFitter._();

  static CameraCalibrationModel fit(CameraCalibrationProfile profile) {
    final training =
        profile.patches.where((patch) => !patch.validation).toList();
    if (training.length < 4) {
      throw const CameraCalibrationException(
        'Для расчёта нужно минимум 4 учебных поля.',
      );
    }

    final labCoefficients = _fitOutputs(
      training,
      (patch) => [patch.labL, patch.labA, patch.labB],
      3,
    );
    final densityTraining =
        training.where((patch) => patch.hasDensities).toList();
    final densityCoefficients = densityTraining.length < 4
        ? null
        : _fitOutputs(
            densityTraining,
            (patch) => [
              patch.densityC!,
              patch.densityM!,
              patch.densityY!,
              patch.densityK!,
            ],
            4,
          );

    final validation =
        profile.patches.where((patch) => patch.validation).toList();
    final labErrors = <double>[];
    final densityErrors = <double>[];
    for (final patch in validation) {
      final features = _features(patch);
      final l = _predict(labCoefficients, 0, features);
      final a = _predict(labCoefficients, 1, features);
      final b = _predict(labCoefficients, 2, features);
      final dl = l - patch.labL;
      final da = a - patch.labA;
      final db = b - patch.labB;
      labErrors.add(math.sqrt(dl * dl + da * da + db * db));

      if (densityCoefficients != null && patch.hasDensities) {
        final expected = [
          patch.densityC!,
          patch.densityM!,
          patch.densityY!,
          patch.densityK!,
        ];
        for (var output = 0; output < 4; output++) {
          densityErrors.add(
            (_predict(densityCoefficients, output, features) - expected[output])
                .abs(),
          );
        }
      }
    }

    return CameraCalibrationModel(
      labCoefficients: labCoefficients,
      densityCoefficients: densityCoefficients,
      validationMeanDeltaE: labErrors.isEmpty ? null : _mean(labErrors),
      validationMaxDeltaE:
          labErrors.isEmpty ? null : labErrors.reduce(math.max),
      validationDensityMae: densityErrors.isEmpty ? null : _mean(densityErrors),
      calculatedAt: DateTime.now().toUtc(),
    );
  }

  static List<double> _fitOutputs(
    List<CameraCalibrationPatch> patches,
    List<double> Function(CameraCalibrationPatch patch) values,
    int outputCount,
  ) {
    const featureCount = 4;
    final normal = List.generate(
      featureCount,
      (_) => List<double>.filled(featureCount, 0),
    );
    final rhs = List.generate(
      outputCount,
      (_) => List<double>.filled(featureCount, 0),
    );

    for (final patch in patches) {
      final features = _features(patch);
      final output = values(patch);
      for (var row = 0; row < featureCount; row++) {
        for (var column = 0; column < featureCount; column++) {
          normal[row][column] += features[row] * features[column];
        }
        for (var channel = 0; channel < outputCount; channel++) {
          rhs[channel][row] += features[row] * output[channel];
        }
      }
    }

    for (var index = 0; index < featureCount; index++) {
      normal[index][index] += 1e-8;
    }

    final coefficients = <double>[];
    for (var channel = 0; channel < outputCount; channel++) {
      coefficients.addAll(_solve(normal, rhs[channel]));
    }
    return coefficients;
  }

  static List<double> _solve(
    List<List<double>> matrix,
    List<double> values,
  ) {
    final size = values.length;
    final augmented = List.generate(
      size,
      (row) => [...matrix[row], values[row]],
    );
    for (var pivot = 0; pivot < size; pivot++) {
      var best = pivot;
      for (var row = pivot + 1; row < size; row++) {
        if (augmented[row][pivot].abs() > augmented[best][pivot].abs()) {
          best = row;
        }
      }
      if (augmented[best][pivot].abs() < 1e-10) {
        throw const CameraCalibrationException(
          'Поля слишком похожи. Добавьте белое, чёрное и насыщенные цветные поля.',
        );
      }
      final swap = augmented[pivot];
      augmented[pivot] = augmented[best];
      augmented[best] = swap;
      final divisor = augmented[pivot][pivot];
      for (var column = pivot; column <= size; column++) {
        augmented[pivot][column] /= divisor;
      }
      for (var row = 0; row < size; row++) {
        if (row == pivot) continue;
        final factor = augmented[row][pivot];
        for (var column = pivot; column <= size; column++) {
          augmented[row][column] -= factor * augmented[pivot][column];
        }
      }
    }
    return List.generate(size, (row) => augmented[row][size]);
  }

  static List<double> _features(CameraCalibrationPatch patch) => [
        1,
        patch.red.clamp(0, 255) / 255,
        patch.green.clamp(0, 255) / 255,
        patch.blue.clamp(0, 255) / 255,
      ];

  static double _predict(
    List<double> coefficients,
    int output,
    List<double> features,
  ) {
    var value = 0.0;
    final offset = output * features.length;
    for (var index = 0; index < features.length; index++) {
      value += coefficients[offset + index] * features[index];
    }
    return value;
  }

  static double _mean(List<double> values) =>
      values.reduce((first, second) => first + second) / values.length;
}
