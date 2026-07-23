enum AssetStorageLocation {
  device,
  supabaseStorage,
  googleDrive,
  organizationDrive,
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
