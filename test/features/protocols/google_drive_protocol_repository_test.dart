import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/capabilities/storage/storage.dart';
import 'package:photo_compare/features/protocols/protocols.dart';

void main() {
  test('personal Drive archive keeps protocol, sources, and preview', () async {
    final storage = MockCloudStorage(
      location: AssetStorageLocation.googleDrive,
      currentConnection: const CloudConnection(
        state: CloudConnectionState.connected,
      ),
    );
    final repository = GoogleDriveProtocolCloudRepository(
      storage: storage,
      ownerUserId: 'user-1',
    );
    final protocol = CheckProtocol(
      id: 'protocol-1',
      createdAt: DateTime.utc(2026, 10, 26),
      ownerUserId: 'user-1',
      score: 96,
      verdict: 'Проходит',
      refSize: '10x10',
      cmpSize: '10x10',
      labId: 'lab-1',
      labMatch: 97,
      stages: const [],
    );

    await repository.saveProtocol(
      protocol,
      previewPng: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
      referenceImage: Uint8List.fromList([0xff, 0xd8, 0xff, 1]),
      sampleImage: Uint8List.fromList([0xff, 0xd8, 0xff, 2]),
    );

    final records = await repository.listAccessibleProtocols();
    expect(records, hasLength(1));
    expect(records.single.protocol.id, 'protocol-1');
    expect(records.single.referenceAssetId, contains('reference.jpg'));
    expect(records.single.sampleAssetId, contains('sample.jpg'));
    expect(await repository.loadPreview(records.single), isNotEmpty);
  });
}
