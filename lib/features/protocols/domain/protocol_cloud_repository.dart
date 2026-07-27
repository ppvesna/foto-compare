import 'dart:typed_data';

import 'check_protocol.dart';

abstract interface class ProtocolCloudRepository {
  Future<void> saveProtocol(
    CheckProtocol protocol, {
    Uint8List? previewPng,
  });
}
