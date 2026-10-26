import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../capabilities/storage/storage.dart';
import '../domain/job_reference_repository.dart';
import '../domain/layout_profile.dart';
import '../domain/saved_reference.dart';

class SupabaseJobReferenceRepository implements JobReferenceRepository {
  final SupabaseClient client;
  final CloudStorage storage;

  const SupabaseJobReferenceRepository(
    this.client, {
    required this.storage,
  });

  @override
  Future<SavedReferenceProfile?> loadActive({
    required String organizationId,
    required String jobId,
  }) async {
    final response = await client.rpc(
      'get_active_job_reference_v1',
      params: {'target_job': jobId},
    );
    if (response == null) return null;
    final row = Map<String, dynamic>.from(response as Map);
    final assetId = row['asset_id'] as String?;
    if (assetId == null || assetId.isEmpty) return null;
    final objectPath = row['object_path'] as String? ?? '';
    final bytes = await storage.download(
      assetId,
      scope: objectPath.contains('/references/')
          ? CloudAssetScope.organizationJobReference(
              organizationId: organizationId,
              jobId: jobId,
            )
          : CloudAssetScope.organizationJob(
              organizationId: organizationId,
              jobId: jobId,
            ),
    );
    final profileJson = row['layout_profile'];
    return SavedReferenceProfile(
      id: row['reference_key'] as String,
      label: row['label'] as String? ?? 'Эталон',
      bytes: bytes,
      layoutProfile: profileJson == null
          ? null
          : LayoutProfile.fromJson(
              Map<String, dynamic>.from(profileJson as Map),
            ),
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  Future<SavedReferenceProfile> saveActive({
    required String organizationId,
    required String jobId,
    required SavedReferenceProfile reference,
  }) async {
    final format = detectImageAssetFormat(reference.bytes);
    final assetId =
        'reference-${_safeAssetPart(reference.id)}.${format.extension}';
    final asset = await storage.upload(
      CloudAssetUpload(
        id: assetId,
        name: '${reference.label}.${format.extension}',
        mimeType: format.mimeType,
        bytes: reference.bytes,
        scope: CloudAssetScope.organizationJobReference(
          organizationId: organizationId,
          jobId: jobId,
        ),
      ),
    );
    await client.rpc(
      'set_active_job_reference_v1',
      params: {
        'target_job': jobId,
        'target_reference_key': reference.id,
        'target_label': reference.label,
        'target_asset_id': asset.id,
        'target_object_path': asset.storageKey,
        'target_layout_profile': reference.layoutProfile?.toJson(),
      },
    );
    return reference;
  }

  String _safeAssetPart(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
    return safe.length <= 80 ? safe : safe.substring(0, 80);
  }
}
