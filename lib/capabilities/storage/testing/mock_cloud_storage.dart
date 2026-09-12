import 'dart:typed_data';

import '../domain/cloud_storage.dart';
import '../domain/storage_settings.dart';

class MockCloudStorage implements CloudStorage {
  @override
  final AssetStorageLocation location;

  CloudConnection currentConnection;
  final Map<String, CloudAssetUpload> _assets = {};

  MockCloudStorage({
    this.location = AssetStorageLocation.supabaseStorage,
    this.currentConnection = CloudConnection.disconnected,
  });

  @override
  Future<CloudConnection> connection() async => currentConnection;

  @override
  Future<CloudConnection> connect() async {
    currentConnection = const CloudConnection(
      state: CloudConnectionState.connected,
      accountLabel: 'mock-account',
    );
    return currentConnection;
  }

  @override
  Future<void> disconnect() async {
    currentConnection = CloudConnection.disconnected;
  }

  @override
  Future<CloudAsset> upload(CloudAssetUpload upload) async {
    final key = _key(upload.id, upload.scope);
    _assets[key] = upload;
    return CloudAsset(
      id: upload.id,
      name: upload.name,
      mimeType: upload.mimeType,
      sizeBytes: upload.bytes.length,
      storageKey: key,
      scope: upload.scope,
      checksum: upload.checksum,
    );
  }

  @override
  Future<Uint8List> download(
    String assetId, {
    CloudAssetScope scope = const CloudAssetScope.personal(),
  }) async {
    final asset = _assets[_key(assetId, scope)];
    if (asset == null) throw StateError('Asset not found: $assetId');
    return Uint8List.fromList(asset.bytes);
  }

  @override
  Future<void> delete(
    String assetId, {
    CloudAssetScope scope = const CloudAssetScope.personal(),
  }) async {
    _assets.remove(_key(assetId, scope));
  }

  String _key(String assetId, CloudAssetScope scope) {
    switch (scope.type) {
      case CloudAssetScopeType.personal:
        return 'personal/$assetId';
      case CloudAssetScopeType.organizationJob:
        return 'organizations/${scope.organizationId}/jobs/${scope.jobId}/$assetId';
      case CloudAssetScopeType.organizationJobChat:
        return 'organizations/${scope.organizationId}/jobs/${scope.jobId}/chat/$assetId';
    }
  }
}
