import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalibrationPointSettings {
  final bool loupeEnabled;
  final double loupeZoom;
  final double magnetMaxShiftPx;

  const CalibrationPointSettings({
    required this.loupeEnabled,
    required this.loupeZoom,
    required this.magnetMaxShiftPx,
  });

  static const defaults = CalibrationPointSettings(
    loupeEnabled: true,
    loupeZoom: 8.0,
    magnetMaxShiftPx: 2.0,
  );

  CalibrationPointSettings copyWith({
    bool? loupeEnabled,
    double? loupeZoom,
    double? magnetMaxShiftPx,
  }) {
    return CalibrationPointSettings(
      loupeEnabled: loupeEnabled ?? this.loupeEnabled,
      loupeZoom: loupeZoom ?? this.loupeZoom,
      magnetMaxShiftPx: magnetMaxShiftPx ?? this.magnetMaxShiftPx,
    );
  }
}

class CalibrationSettingsService {
  static const _loupeEnabledKey = 'calibration.loupeEnabled';
  static const _loupeZoomKey = 'calibration.loupeZoom';
  static const _magnetMaxShiftKey = 'calibration.magnetMaxShiftPx';

  static final ValueNotifier<CalibrationPointSettings> notifier =
      ValueNotifier<CalibrationPointSettings>(
          CalibrationPointSettings.defaults);

  static Future<CalibrationPointSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = CalibrationPointSettings(
      loupeEnabled: prefs.getBool(_loupeEnabledKey) ??
          CalibrationPointSettings.defaults.loupeEnabled,
      loupeZoom: _normalizeZoom(
        prefs.getDouble(_loupeZoomKey) ??
            CalibrationPointSettings.defaults.loupeZoom,
      ),
      magnetMaxShiftPx: (prefs.getDouble(_magnetMaxShiftKey) ??
              CalibrationPointSettings.defaults.magnetMaxShiftPx)
          .clamp(0.0, 8.0)
          .toDouble(),
    );
    notifier.value = settings;
    return settings;
  }

  static Future<void> save(CalibrationPointSettings settings) async {
    final normalized = CalibrationPointSettings(
      loupeEnabled: settings.loupeEnabled,
      loupeZoom: _normalizeZoom(settings.loupeZoom),
      magnetMaxShiftPx: settings.magnetMaxShiftPx.clamp(0.0, 8.0).toDouble(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loupeEnabledKey, normalized.loupeEnabled);
    await prefs.setDouble(_loupeZoomKey, normalized.loupeZoom);
    await prefs.setDouble(_magnetMaxShiftKey, normalized.magnetMaxShiftPx);
    notifier.value = normalized;
  }

  static Future<void> reset() => save(CalibrationPointSettings.defaults);

  static double _normalizeZoom(double value) {
    if (value <= 5) return 4.0;
    if (value >= 10) return 12.0;
    return 8.0;
  }
}
