import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
    expect(CheckHistoryService.checks.value, hasLength(1));
    expect(CheckHistoryService.checks.value.single.stages.single.name, 'Цвет');
  });
}

CheckProtocol _protocol() => CheckProtocol(
      id: 'protocol-1',
      createdAt: DateTime.utc(2026, 7, 18, 10, 30),
      jobId: 'job-1',
      jobNumber: '1001',
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
