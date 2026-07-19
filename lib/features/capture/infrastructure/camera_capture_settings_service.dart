import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/camera_capture_settings.dart';

class CameraCaptureSettingsService {
  const CameraCaptureSettingsService._();

  static const _lightingKey = 'camera.lighting';
  static const _filterKey = 'camera.opticalFilter';
  static const _legacyIlluminantKey = 'color.illuminant';
  static const _legacyConditionKey = 'color.measurementCondition';

  static final ValueNotifier<CameraCaptureSettings> notifier =
      ValueNotifier<CameraCaptureSettings>(CameraCaptureSettings.defaults);

  static Future<CameraCaptureSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final lightingName =
        prefs.getString(_lightingKey) ?? prefs.getString(_legacyIlluminantKey);
    final filterName = prefs.getString(_filterKey);
    final legacyCondition = prefs.getString(_legacyConditionKey);
    final settings = CameraCaptureSettings(
      lighting: _lightingFromName(lightingName),
      opticalFilter: filterName == null
          ? _filterFromLegacyCondition(legacyCondition)
          : _readEnum(
              CameraOpticalFilter.values,
              filterName,
              CameraCaptureSettings.defaults.opticalFilter,
            ),
    );
    notifier.value = settings;
    return settings;
  }

  static Future<void> save(CameraCaptureSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_lightingKey, settings.lighting.name),
      prefs.setString(_filterKey, settings.opticalFilter.name),
    ]);
    notifier.value = settings;
  }

  static Future<void> reset() => save(CameraCaptureSettings.defaults);

  static CameraLighting _lightingFromName(String? name) {
    if (name == 'a') return CameraLighting.tungstenA;
    return _readEnum(
      CameraLighting.values,
      name,
      CameraCaptureSettings.defaults.lighting,
    );
  }

  static CameraOpticalFilter _filterFromLegacyCondition(String? condition) {
    return switch (condition) {
      'm2' => CameraOpticalFilter.uvCut,
      'm3' => CameraOpticalFilter.polarizer,
      _ => CameraOpticalFilter.none,
    };
  }

  static T _readEnum<T extends Enum>(
    List<T> values,
    String? stored,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }
}
