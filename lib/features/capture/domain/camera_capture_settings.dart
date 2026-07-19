enum CameraLighting { d50, d65, tungstenA }

extension CameraLightingLabel on CameraLighting {
  String get label => switch (this) {
        CameraLighting.d50 => 'D50',
        CameraLighting.d65 => 'D65',
        CameraLighting.tungstenA => 'A · лампа накаливания',
      };
}

enum CameraOpticalFilter { none, uvCut, polarizer }

extension CameraOpticalFilterLabel on CameraOpticalFilter {
  String get label => switch (this) {
        CameraOpticalFilter.none => 'Без фильтра',
        CameraOpticalFilter.uvCut => 'UV-cut',
        CameraOpticalFilter.polarizer => 'Поляризатор',
      };
}

class CameraCaptureSettings {
  final CameraLighting lighting;
  final CameraOpticalFilter opticalFilter;

  const CameraCaptureSettings({
    required this.lighting,
    required this.opticalFilter,
  });

  static const defaults = CameraCaptureSettings(
    lighting: CameraLighting.d65,
    opticalFilter: CameraOpticalFilter.none,
  );

  CameraCaptureSettings copyWith({
    CameraLighting? lighting,
    CameraOpticalFilter? opticalFilter,
  }) {
    return CameraCaptureSettings(
      lighting: lighting ?? this.lighting,
      opticalFilter: opticalFilter ?? this.opticalFilter,
    );
  }
}
