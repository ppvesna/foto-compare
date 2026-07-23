import 'dart:typed_data';

import 'storage_settings.dart';

enum CloudConnectionState { disconnected, connected, error }

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

  const CloudAsset({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    this.checksum,
  });
}

class CloudAssetUpload {
  final String id;
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final String? checksum;

  const CloudAssetUpload({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.checksum,
  });
}

abstract interface class CloudStorage {
  AssetStorageLocation get location;

  Future<CloudConnection> connection();

  Future<CloudConnection> connect();

  Future<void> disconnect();

  Future<CloudAsset> upload(CloudAssetUpload upload);

  Future<Uint8List> download(String assetId);

  Future<void> delete(String assetId);
}
