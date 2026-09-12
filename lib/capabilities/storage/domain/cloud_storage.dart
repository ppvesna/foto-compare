import 'dart:typed_data';

import 'storage_settings.dart';

enum CloudConnectionState { disconnected, connected, error }

enum CloudAssetScopeType { personal, organizationJob, organizationJobChat }

class CloudAssetScope {
  final CloudAssetScopeType type;
  final String? organizationId;
  final String? jobId;

  const CloudAssetScope.personal()
      : type = CloudAssetScopeType.personal,
        organizationId = null,
        jobId = null;

  const CloudAssetScope.organizationJob({
    required this.organizationId,
    required this.jobId,
  }) : type = CloudAssetScopeType.organizationJob;

  const CloudAssetScope.organizationJobChat({
    required this.organizationId,
    required this.jobId,
  }) : type = CloudAssetScopeType.organizationJobChat;
}

class CloudConnection {
  final CloudConnectionState state;
  final String? accountLabel;
  final String? errorMessage;

  const CloudConnection({
    required this.state,
    this.accountLabel,
    this.errorMessage,
  });

  static const disconnected = CloudConnection(
    state: CloudConnectionState.disconnected,
  );
}

class CloudAsset {
  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? checksum;
  final String storageKey;
  final CloudAssetScope scope;

  const CloudAsset({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.storageKey,
    this.scope = const CloudAssetScope.personal(),
    this.checksum,
  });
}

class CloudAssetUpload {
  final String id;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String? checksum;
  final CloudAssetScope scope;

  const CloudAssetUpload({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.scope = const CloudAssetScope.personal(),
    this.checksum,
  });
}

abstract interface class CloudStorage {
  AssetStorageLocation get location;

  Future<CloudConnection> connection();

  Future<CloudConnection> connect();

  Future<void> disconnect();

  Future<CloudAsset> upload(CloudAssetUpload upload);

  Future<Uint8List> download(
    String assetId, {
    CloudAssetScope scope = const CloudAssetScope.personal(),
  });

  Future<void> delete(
    String assetId, {
    CloudAssetScope scope = const CloudAssetScope.personal(),
  });
}
