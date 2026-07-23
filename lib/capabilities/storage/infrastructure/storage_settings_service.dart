import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/storage_settings.dart';

class StorageSettingsService {
  const StorageSettingsService._();

  static const _locationKey = 'storage.primaryLocation';
  static const _protocolsKey = 'storage.syncProtocolMetadata';
  static const _previewsKey = 'storage.syncPreviews';
  static const _originalsKey = 'storage.syncOriginals';

  static final ValueNotifier<StorageSettings> notifier =
      ValueNotifier<StorageSettings>(StorageSettings.defaults);

  static Future<StorageSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = StorageSettings(
      primaryLocation: _readLocation(prefs.getString(_locationKey)),
      syncProtocolMetadata: prefs.getBool(_protocolsKey) ?? false,
      syncPreviews: prefs.getBool(_previewsKey) ?? false,
      syncOriginals: prefs.getBool(_originalsKey) ?? false,
    );
    notifier.value = settings;
    return settings;
  }

  static Future<void> save(StorageSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(_locationKey, settings.primaryLocation.name),
      prefs.setBool(_protocolsKey, settings.syncProtocolMetadata),
      prefs.setBool(_previewsKey, settings.syncPreviews),
      prefs.setBool(_originalsKey, settings.syncOriginals),
    ]);
    notifier.value = settings;
  }

  static Future<void> reset() => save(StorageSettings.defaults);

  static AssetStorageLocation _readLocation(String? stored) {
    for (final value in AssetStorageLocation.values) {
      if (value.name == stored) return value;
    }
    return AssetStorageLocation.device;
  }
}
