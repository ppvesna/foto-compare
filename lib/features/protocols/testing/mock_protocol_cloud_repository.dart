import 'dart:typed_data';

import '../domain/check_protocol.dart';
import '../domain/protocol_cloud_repository.dart';

class MockCloudProtocolSave {
  final CheckProtocol protocol;
  final Uint8List? previewPng;

  const MockCloudProtocolSave({
    required this.protocol,
    required this.previewPng,
  });
}

class MockProtocolCloudRepository implements ProtocolCloudRepository {
  final List<MockCloudProtocolSave> saves = [];

  @override
  Future<void> saveProtocol(
    CheckProtocol protocol, {
    Uint8List? previewPng,
  }) async {
    saves.add(
      MockCloudProtocolSave(
        protocol: protocol,
        previewPng: previewPng == null ? null : Uint8List.fromList(previewPng),
      ),
    );
  }

  @override
  Future<List<CloudProtocolRecord>> listAccessibleProtocols({
    int limit = 30,
  }) async {
    return saves.reversed
        .take(limit)
        .map(
          (save) => CloudProtocolRecord(
            protocol: save.protocol,
            ownerUserId: 'mock-user',
            previewAssetId:
                save.previewPng == null ? null : 'mock-${save.protocol.id}',
          ),
        )
        .toList();
  }

  @override
  Future<Uint8List?> loadPreview(CloudProtocolRecord record) async {
    for (final save in saves.reversed) {
      if (save.protocol.id == record.protocol.id) {
        return save.previewPng == null
            ? null
            : Uint8List.fromList(save.previewPng!);
      }
    }
    return null;
  }
}
