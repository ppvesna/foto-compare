enum AssetStorageLocation {
  device,
  supabaseStorage,
  googleDrive,
  organizationDrive,
}

enum StorageWorkspaceType { legacy, guest, personal, organization }

class StorageSettingsScope {
  final StorageWorkspaceType type;
  final String id;

  const StorageSettingsScope._(this.type, this.id);

  const StorageSettingsScope.legacy()
      : this._(StorageWorkspaceType.legacy, 'legacy');

  const StorageSettingsScope.guest()
      : this._(StorageWorkspaceType.guest, 'guest');

  factory StorageSettingsScope.personal(String userId) =>
      StorageSettingsScope._(StorageWorkspaceType.personal, userId.trim());

  factory StorageSettingsScope.organization(String organizationId) =>
      StorageSettingsScope._(
        StorageWorkspaceType.organization,
        organizationId.trim(),
      );

  String get preferencePrefix => switch (type) {
        StorageWorkspaceType.legacy => 'storage',
        StorageWorkspaceType.guest => 'storage.guest',
        StorageWorkspaceType.personal => 'storage.personal.$id',
        StorageWorkspaceType.organization => 'storage.organization.$id',
      };
}

class StorageSettings {
  final AssetStorageLocation primaryLocation;
  final bool syncProtocolMetadata;
  final bool syncPreviews;
  final bool syncOriginals;

  const StorageSettings({
    required this.primaryLocation,
    required this.syncProtocolMetadata,
    required this.syncPreviews,
    required this.syncOriginals,
  });

  static const defaults = StorageSettings(
    primaryLocation: AssetStorageLocation.device,
    syncProtocolMetadata: false,
    syncPreviews: false,
    syncOriginals: false,
  );

  static StorageSettings defaultsFor(StorageSettingsScope scope) {
    return switch (scope.type) {
      StorageWorkspaceType.organization => const StorageSettings(
          primaryLocation: AssetStorageLocation.supabaseStorage,
          syncProtocolMetadata: true,
          syncPreviews: true,
          syncOriginals: true,
        ),
      StorageWorkspaceType.legacy ||
      StorageWorkspaceType.guest ||
      StorageWorkspaceType.personal =>
        defaults,
    };
  }

  StorageSettings normalizedFor(StorageSettingsScope scope) {
    switch (scope.type) {
      case StorageWorkspaceType.guest:
        return defaults;
      case StorageWorkspaceType.personal:
        if (primaryLocation != AssetStorageLocation.device &&
            primaryLocation != AssetStorageLocation.googleDrive) {
          return defaults;
        }
        break;
      case StorageWorkspaceType.organization:
        if (primaryLocation != AssetStorageLocation.supabaseStorage &&
            primaryLocation != AssetStorageLocation.organizationDrive) {
          return defaultsFor(scope);
        }
        break;
      case StorageWorkspaceType.legacy:
        break;
    }
    return this;
  }

  StorageSettings copyWith({
    AssetStorageLocation? primaryLocation,
    bool? syncProtocolMetadata,
    bool? syncPreviews,
    bool? syncOriginals,
  }) {
    return StorageSettings(
      primaryLocation: primaryLocation ?? this.primaryLocation,
      syncProtocolMetadata: syncProtocolMetadata ?? this.syncProtocolMetadata,
      syncPreviews: syncPreviews ?? this.syncPreviews,
      syncOriginals: syncOriginals ?? this.syncOriginals,
    );
  }
}
