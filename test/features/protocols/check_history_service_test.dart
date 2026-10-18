import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_compare/features/protocols/protocols.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CheckHistoryService.lastCheck.value = null;
    CheckHistoryService.checks.value = const [];
  });

  test('loads a protocol saved with the legacy preference key', () async {
    final protocol = _protocol();
    SharedPreferences.setMockInitialValues({
      'last_check_protocol_v1': jsonEncode(protocol.toJson()),
    });

    await CheckHistoryService.load();

    expect(CheckHistoryService.lastCheck.value?.id, protocol.id);
    expect(CheckHistoryService.lastCheck.value?.jobNumber, protocol.jobNumber);
    expect(CheckHistoryService.lastCheck.value?.customerName, 'Весна');
    expect(CheckHistoryService.lastCheck.value?.customerConfirmed, isTrue);
    expect(CheckHistoryService.checks.value, hasLength(1));
    expect(CheckHistoryService.checks.value.single.stages.single.name, 'Цвет');
    expect(
      CheckHistoryService.forScope(ownerUserId: 'user-1'),
      isEmpty,
      reason: 'Старая общая история не должна приписываться '
          'вошедшему пользователю.',
    );
  });

  test('separates personal and organization history by user and workspace',
      () async {
    await CheckHistoryService.saveLast(
      _protocol(id: 'personal', ownerUserId: 'user-1'),
    );
    await CheckHistoryService.saveLast(
      _protocol(
        id: 'organization',
        ownerUserId: 'user-1',
        organizationId: 'organization-1',
      ),
    );
    await CheckHistoryService.saveLast(
      _protocol(id: 'other-user', ownerUserId: 'user-2'),
    );

    expect(
      CheckHistoryService.forScope(ownerUserId: 'user-1')
          .map((protocol) => protocol.id),
      ['personal'],
    );
    expect(
      CheckHistoryService.forScope(
        ownerUserId: 'user-1',
        organizationId: 'organization-1',
      ).map((protocol) => protocol.id),
      ['organization'],
    );
  });

  test('clearing one workspace preserves other workspace history', () async {
    await CheckHistoryService.saveLast(
      _protocol(id: 'personal', ownerUserId: 'user-1'),
    );
    await CheckHistoryService.saveLast(
      _protocol(
        id: 'organization',
        ownerUserId: 'user-1',
        organizationId: 'organization-1',
      ),
    );

    await CheckHistoryService.clearScope(ownerUserId: 'user-1');

    expect(CheckHistoryService.forScope(ownerUserId: 'user-1'), isEmpty);
    expect(
      CheckHistoryService.forScope(
        ownerUserId: 'user-1',
        organizationId: 'organization-1',
      ).single.id,
      'organization',
    );
  });

  test('cloud preview keeps detail within the 1280 pixel boundary', () async {
    final source = img.Image(width: 2000, height: 1000)
      ..setPixelRgb(100, 100, 255, 0, 0);

    final preview = await ProtocolPreviewService.create(
      Uint8List.fromList(img.encodePng(source)),
    );
    final decoded = img.decodePng(preview!);

    expect(decoded, isNotNull);
    expect(decoded!.width, ProtocolPreviewService.maxDimension);
    expect(decoded.height, 640);
  });

  test('mock cloud protocol repository records metadata and preview', () async {
    final repository = MockProtocolCloudRepository();
    final preview = Uint8List.fromList([1, 2, 3]);

    await repository.saveProtocol(_protocol(), previewPng: preview);

    expect(repository.saves.single.protocol.id, 'protocol-1');
    expect(repository.saves.single.previewPng, preview);
    final records = await repository.listAccessibleProtocols();
    expect(records.single.protocol.jobNumber, '1001');
    expect(await repository.loadPreview(records.single), preview);
  });
}

CheckProtocol _protocol({
  String id = 'protocol-1',
  String ownerUserId = '',
  String organizationId = '',
}) =>
    CheckProtocol(
      id: id,
      createdAt: DateTime.utc(2026, 7, 18, 10, 30),
      ownerUserId: ownerUserId,
      organizationId: organizationId,
      jobId: 'job-1',
      jobNumber: '1001',
      customerId: 'customer-1',
      customerName: 'Весна',
      customerConfirmed: true,
      score: 98.5,
      verdict: 'PASS',
      refSize: '100×100',
      cmpSize: '100×100',
      labId: 'abcd1234',
      referenceId: 'reference-1',
      referenceLabel: 'Эталон 1',
      sampleLabel: 'Отпечаток 1',
      sampleImageId: 'sample-1',
      sampleNo: 1,
      labMatch: 99.0,
      stages: const [
        CheckProtocolStage(
          name: 'Цвет',
          status: 'OK',
          metric: 'Delta E 1.2',
          comment: 'В норме',
        ),
      ],
    );
