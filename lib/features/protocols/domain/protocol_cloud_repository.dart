import 'dart:typed_data';

import 'check_protocol.dart';

class CloudProtocolRecord {
  final CheckProtocol protocol;
  final String ownerUserId;
  final String? organizationId;
  final String? previewAssetId;
  final String? previewObjectPath;

  const CloudProtocolRecord({
    required this.protocol,
    required this.ownerUserId,
    this.organizationId,
    this.previewAssetId,
    this.previewObjectPath,
  });
}

abstract interface class ProtocolCloudRepository {
  Future<void> saveProtocol(
    CheckProtocol protocol, {
    Uint8List? previewPng,
  });

  Future<List<CloudProtocolRecord>> listAccessibleProtocols({int limit = 30});

  Future<Uint8List?> loadPreview(CloudProtocolRecord record);
}
