import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/cloud_storage.dart';
import '../domain/storage_settings.dart';

class SupabaseCloudStorage implements CloudStorage {
  static const defaultBucket = 'trimatrix-assets';

  final SupabaseClient client;
  final String ownerUserId;
  final String bucket;

  bool _disconnected = false;

  SupabaseCloudStorage(
    this.client, {
    required this.ownerUserId,
    this.bucket = defaultBucket,
  });

  @override
  AssetStorageLocation get location => AssetStorageLocation.supabaseStorage;

  String objectPath(String assetId) {
    final cleanId = assetId.trim();
    if (cleanId.isEmpty ||
        cleanId == '.' ||
        cleanId == '..' ||
        cleanId.contains('/') ||
        cleanId.contains(r'\')) {
      throw ArgumentError.value(assetId, 'assetId', 'Invalid cloud asset ID');
    }
    return 'users/$ownerUserId/$cleanId';
  }

  @override
  Future<CloudConnection> connection() => _probe();

  @override
  Future<CloudConnection> connect() async {
    _disconnected = false;
    return _probe();
  }

  @override
  Future<void> disconnect() async {
    _disconnected = true;
  }

  @override
  Future<CloudAsset> upload(CloudAssetUpload upload) async {
    _requireCurrentUser();
    await client.storage.from(bucket).uploadBinary(
          objectPath(upload.id),
          upload.bytes,
          fileOptions: FileOptions(
            contentType: upload.mimeType,
            upsert: true,
            metadata: {
              'asset_name': upload.name,
              if (upload.checksum != null) 'checksum': upload.checksum,
            },
          ),
        );
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
    _requireCurrentUser();
    return client.storage.from(bucket).download(objectPath(assetId));
  }

  @override
  Future<void> delete(String assetId) async {
    _requireCurrentUser();
    await client.storage.from(bucket).remove([objectPath(assetId)]);
  }

  Future<CloudConnection> _probe() async {
    if (_disconnected) return CloudConnection.disconnected;
    final user = client.auth.currentUser;
    if (user == null || user.id != ownerUserId) {
      return CloudConnection.disconnected;
    }
    try {
      await client.storage.from(bucket).list(path: 'users/$ownerUserId');
      return CloudConnection(
        state: CloudConnectionState.connected,
        accountLabel: user.email ?? ownerUserId,
      );
    } catch (error) {
      return CloudConnection(
        state: CloudConnectionState.error,
        accountLabel: user.email ?? ownerUserId,
        errorMessage: error.toString(),
      );
    }
  }

  void _requireCurrentUser() {
    if (_disconnected ||
        client.auth.currentUser == null ||
        client.auth.currentUser!.id != ownerUserId) {
      throw StateError('Supabase Storage is not connected for this user');
    }
  }
}
