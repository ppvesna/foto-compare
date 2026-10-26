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

  static Future<StorageSettings> load({
    StorageSettingsScope scope = const StorageSettingsScope.legacy(),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = StorageSettings.defaultsFor(scope);
    if (scope.type == StorageWorkspaceType.guest) {
      notifier.value = defaults;
      return defaults;
    }
    final settings = StorageSettings(
      primaryLocation: _readLocation(
        prefs.getString(_key(scope, _locationKey)),
        fallback: defaults.primaryLocation,
      ),
      syncProtocolMetadata: prefs.getBool(_key(scope, _protocolsKey)) ??
          defaults.syncProtocolMetadata,
      syncPreviews:
          prefs.getBool(_key(scope, _previewsKey)) ?? defaults.syncPreviews,
      syncOriginals:
          prefs.getBool(_key(scope, _originalsKey)) ?? defaults.syncOriginals,
    ).normalizedFor(scope);
    notifier.value = settings;
    return settings;
  }

  static Future<void> save(
    StorageSettings settings, {
    StorageSettingsScope scope = const StorageSettingsScope.legacy(),
  }) async {
    final normalized = settings.normalizedFor(scope);
    if (scope.type == StorageWorkspaceType.guest) {
      notifier.value = StorageSettings.defaults;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString(
        _key(scope, _locationKey),
        normalized.primaryLocation.name,
      ),
      prefs.setBool(
        _key(scope, _protocolsKey),
        normalized.syncProtocolMetadata,
      ),
      prefs.setBool(
        _key(scope, _previewsKey),
        normalized.syncPreviews,
      ),
      prefs.setBool(
        _key(scope, _originalsKey),
        normalized.syncOriginals,
      ),
    ]);
    notifier.value = normalized;
  }

  static Future<void> reset({
    StorageSettingsScope scope = const StorageSettingsScope.legacy(),
  }) =>
      save(StorageSettings.defaultsFor(scope), scope: scope);

  static AssetStorageLocation _readLocation(
    String? stored, {
    AssetStorageLocation fallback = AssetStorageLocation.device,
  }) {
    for (final value in AssetStorageLocation.values) {
      if (value.name == stored) return value;
    }
    return fallback;
  }

  static String _key(StorageSettingsScope scope, String legacyKey) {
    if (scope.type == StorageWorkspaceType.legacy) return legacyKey;
    final suffix = legacyKey.substring('storage.'.length);
    return '${scope.preferencePrefix}.$suffix';
  }
}
