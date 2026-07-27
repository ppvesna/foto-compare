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
}
