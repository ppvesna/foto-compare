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
    _assets[upload.id] = upload;
    return CloudAsset(
      id: upload.id,
      name: upload.name,
      mimeType: upload.mimeType,
      sizeBytes: upload.bytes.length,
      checksum: upload.checksum,
    );
  }

  @override
  Future<Uint8List> download(String assetId) async {
    final asset = _assets[assetId];
    if (asset == null) throw StateError('Asset not found: $assetId');
    return Uint8List.fromList(asset.bytes);
  }

  @override
  Future<void> delete(String assetId) async {
    _assets.remove(assetId);
  }
}
