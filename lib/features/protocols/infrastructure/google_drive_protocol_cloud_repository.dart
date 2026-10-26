import 'dart:convert';
import 'dart:typed_data';

import '../../../capabilities/storage/storage.dart';
import '../domain/check_protocol.dart';
import '../domain/protocol_cloud_repository.dart';

class GoogleDriveProtocolCloudRepository implements ProtocolCloudRepository {
  static const _indexAssetId = 'trimatrix-personal-protocol-index-v1.json';

  final CloudStorage storage;
  final String ownerUserId;

  const GoogleDriveProtocolCloudRepository({
    required this.storage,
    required this.ownerUserId,
  });

  @override
  Future<void> saveProtocol(
    CheckProtocol protocol, {
    Uint8List? previewPng,
    Uint8List? referenceImage,
    Uint8List? sampleImage,
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

    final referenceAssetId = await _uploadImage(
      protocol: protocol,
      kind: 'reference',
      label: protocol.referenceLabel,
      bytes: referenceImage,
    );
    final sampleAssetId = await _uploadImage(
      protocol: protocol,
      kind: 'sample',
      label: protocol.sampleLabel,
      bytes: sampleImage,
    );

    final records = await _loadIndex();
    records.removeWhere(
      (record) =>
          (record['protocol'] as Map?)?['id']?.toString() == protocol.id,
    );
    records.insert(0, {
      'protocol': protocol.toJson(),
      'ownerUserId': ownerUserId,
      'previewAssetId': previewAssetId,
      'referenceAssetId': referenceAssetId,
      'sampleAssetId': sampleAssetId,
    });
    if (records.length > 500) records.removeRange(500, records.length);
    await storage.upload(
      CloudAssetUpload(
        id: _indexAssetId,
        name: 'Trimatrix — индекс протоколов.json',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(records))),
      ),
    );
  }

  @override
  Future<List<CloudProtocolRecord>> listAccessibleProtocols({
    int limit = 30,
  }) async {
    final records = await _loadIndex();
    return records.take(limit).map((record) {
      final protocol = CheckProtocol.fromJson(
        Map<String, dynamic>.from(record['protocol'] as Map),
      );
      return CloudProtocolRecord(
        protocol: protocol,
        ownerUserId: record['ownerUserId'] as String? ?? ownerUserId,
        previewAssetId: record['previewAssetId'] as String?,
        previewObjectPath: record['previewAssetId'] as String?,
        referenceAssetId: record['referenceAssetId'] as String?,
        referenceObjectPath: record['referenceAssetId'] as String?,
        sampleAssetId: record['sampleAssetId'] as String?,
        sampleObjectPath: record['sampleAssetId'] as String?,
      );
    }).toList();
  }

  @override
  Future<Uint8List?> loadPreview(CloudProtocolRecord record) async {
    final id = record.previewAssetId;
    if (id == null || id.isEmpty || record.ownerUserId != ownerUserId) {
      return null;
    }
    return storage.download(id);
  }

  Future<String?> _uploadImage({
    required CheckProtocol protocol,
    required String kind,
    required String label,
    required Uint8List? bytes,
  }) async {
    if (bytes == null) return null;
    final format = detectImageAssetFormat(bytes);
    final id = 'protocol-${protocol.id}-$kind.${format.extension}';
    await storage.upload(
      CloudAssetUpload(
        id: id,
        name: '$label.${format.extension}',
        mimeType: format.mimeType,
        bytes: bytes,
      ),
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> _loadIndex() async {
    try {
      final bytes = await storage.download(_indexAssetId);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
    } on StateError catch (error) {
      if (error.toString().toLowerCase().contains('not found')) return [];
      rethrow;
    }
  }
}
