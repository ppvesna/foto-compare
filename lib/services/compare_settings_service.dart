import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompareSettings {
  final int deltaEdgeTolerancePx;

  const CompareSettings({
    required this.deltaEdgeTolerancePx,
  });

  static const defaults = CompareSettings(deltaEdgeTolerancePx: 4);

  CompareSettings copyWith({
    int? deltaEdgeTolerancePx,
  }) {
    return CompareSettings(
      deltaEdgeTolerancePx: deltaEdgeTolerancePx ?? this.deltaEdgeTolerancePx,
    );
  }
}

class CompareSettingsService {
  static const _deltaEdgeToleranceKey = 'compare.deltaEdgeTolerancePx';

  static final ValueNotifier<CompareSettings> notifier =
      ValueNotifier<CompareSettings>(CompareSettings.defaults);

  static Future<CompareSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = CompareSettings(
      deltaEdgeTolerancePx: (prefs.getInt(_deltaEdgeToleranceKey) ??
              CompareSettings.defaults.deltaEdgeTolerancePx)
          .clamp(0, 6),
    );
    notifier.value = settings;
    return settings;
  }

  static Future<void> save(CompareSettings settings) async {
    final normalized = CompareSettings(
      deltaEdgeTolerancePx: settings.deltaEdgeTolerancePx.clamp(0, 6),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _deltaEdgeToleranceKey,
      normalized.deltaEdgeTolerancePx,
    );
    notifier.value = normalized;
  }

  static Future<void> reset() => save(CompareSettings.defaults);
}
