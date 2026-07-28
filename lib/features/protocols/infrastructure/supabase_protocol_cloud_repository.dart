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
    String? previewObjectPath;
    final assetScope = _scopeFor(protocol);
    if (previewPng != null) {
      previewAssetId = 'protocol-${protocol.id}-preview.png';
      final asset = await storage.upload(
        CloudAssetUpload(
          id: previewAssetId,
          name: '${protocol.sampleLabel} — карта отличий.png',
          mimeType: 'image/png',
          bytes: previewPng,
          scope: assetScope,
        ),
      );
      previewObjectPath = asset.storageKey;
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
        'preview_object_path': previewObjectPath,
        'protocol_created_at': protocol.createdAt.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'owner_user_id,protocol_id',
    );
  }

  @override
  Future<List<CloudProtocolRecord>> listAccessibleProtocols({
    int limit = 30,
  }) async {
    final rows = await client
        .from('cloud_check_protocols')
        .select(
          'owner_user_id, organization_id, protocol_data, '
          'preview_asset_id, preview_object_path',
        )
        .order('protocol_created_at', ascending: false)
        .limit(limit);
    return rows.map((row) {
      final data = Map<String, dynamic>.from(row);
      return CloudProtocolRecord(
        protocol: CheckProtocol.fromJson(
          Map<String, dynamic>.from(data['protocol_data'] as Map),
        ),
        ownerUserId: data['owner_user_id'] as String,
        organizationId: data['organization_id'] as String?,
        previewAssetId: data['preview_asset_id'] as String?,
        previewObjectPath: data['preview_object_path'] as String?,
      );
    }).toList();
  }

  @override
  Future<Uint8List?> loadPreview(CloudProtocolRecord record) async {
    final assetId = record.previewAssetId;
    if (assetId == null || assetId.isEmpty) return null;
    final personalObject =
        record.previewObjectPath?.startsWith('users/') ?? false;
    final scope = personalObject
        ? const CloudAssetScope.personal()
        : _scopeFor(
            record.protocol,
            targetOrganizationId: record.organizationId,
          );
    if (scope.type == CloudAssetScopeType.personal &&
        record.ownerUserId != ownerUserId) {
      return null;
    }
    return storage.download(assetId, scope: scope);
  }

  CloudAssetScope _scopeFor(
    CheckProtocol protocol, {
    String? targetOrganizationId,
  }) {
    final targetOrganization = targetOrganizationId ?? organizationId;
    if (targetOrganization != null && _uuid.hasMatch(protocol.jobId)) {
      return CloudAssetScope.organizationJob(
        organizationId: targetOrganization,
        jobId: protocol.jobId,
      );
    }
    return const CloudAssetScope.personal();
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );
}
