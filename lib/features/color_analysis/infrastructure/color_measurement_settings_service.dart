import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/color_measurement.dart';

class ColorMeasurementSettingsService {
  const ColorMeasurementSettingsService._();

  static const _formulaKey = 'color.deltaEFormula';
  static const _apertureKey = 'color.measurementAperture';

  static final ValueNotifier<ColorMeasurementSettings> notifier =
      ValueNotifier<ColorMeasurementSettings>(
          ColorMeasurementSettings.defaults);

  static Future<ColorMeasurementSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = ColorMeasurementSettings(
      deltaEFormula: _readEnum(
        DeltaEFormula.values,
        prefs.getString(_formulaKey),
        ColorMeasurementSettings.defaults.deltaEFormula,
      ),
      aperture: _readEnum(
        MeasurementAperture.values,
        prefs.getString(_apertureKey),
        ColorMeasurementSettings.defaults.aperture,
      ),
    );
    notifier.value = settings;
    return settings;
  }

  static Future<void> save(ColorMeasurementSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_formulaKey, settings.deltaEFormula.name),
      prefs.setString(_apertureKey, settings.aperture.name),
    ]);
    notifier.value = settings;
  }

  static Future<void> reset() => save(ColorMeasurementSettings.defaults);

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
