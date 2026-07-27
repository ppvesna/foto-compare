import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../capabilities/storage/storage.dart';
import '../domain/check_protocol.dart';
import '../domain/protocol_cloud_repository.dart';

class SupabaseProtocolCloudRepository implements ProtocolCloudRepository {
  final SupabaseClient client;
  final CloudStorage storage;
  final String ownerUserId;
  final String? organizationId;

  const SupabaseProtocolCloudRepository(
    this.client, {
    required this.storage,
    required this.ownerUserId,
    this.organizationId,
  });

  @override
  Future<void> saveProtocol(
    CheckProtocol protocol, {
    Uint8List? previewPng,
  }) async {
    String? previewAssetId;
    if (previewPng != null) {
      previewAssetId = 'protocol-${protocol.id}-preview.png';
      await storage.upload(
        CloudAssetUpload(
          id: previewAssetId,
          name: '${protocol.sampleLabel} — карта отличий.png',
          mimeType: 'image/png',
          bytes: previewPng,
        ),
      );
    }

    await client.from('cloud_check_protocols').upsert(
      {
        'owner_user_id': ownerUserId,
        'protocol_id': protocol.id,
        'organization_id': organizationId,
        'job_id': protocol.jobId,
        'job_number': protocol.jobNumber,
        'protocol_data': protocol.toJson(),
        'preview_asset_id': previewAssetId,
        'protocol_created_at': protocol.createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'owner_user_id,protocol_id',
    );
  }
}
