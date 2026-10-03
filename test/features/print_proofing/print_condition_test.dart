import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/print_proofing/print_proofing.dart';

void main() {
  test('accepts a structurally valid CMYK output ICC header', () {
    final bytes = _iccHeader();
    final result = IccProfileInspector.inspect(
      bytes,
      fileName: 'press-material.icc',
    );

    expect(result.accepted, isTrue);
    expect(result.evidence.profileClass, 'prtr');
    expect(result.evidence.dataColorSpace, 'CMYK');
    expect(result.evidence.connectionSpace, 'Lab ');
    expect(result.evidence.version, '4.3.0');
  });

  test('rejects a display RGB profile for print proofing', () {
    final bytes = _iccHeader(profileClass: 'mntr', colorSpace: 'RGB ');
    final result = IccProfileInspector.inspect(
      bytes,
      fileName: 'monitor.icc',
    );

    expect(result.accepted, isFalse);
    expect(result.problems, hasLength(2));
  });

  test('published quick condition needs calibration and validation evidence',
      () {
    final now = DateTime.utc(2026, 10, 3);
    final condition = PrintCondition(
      id: 'condition-1',
      organizationId: 'organization-1',
      displayName: 'Машина 2 · материал K-120',
      machineName: 'Машина 2',
      materialName: 'K-120',
      inkSet: 'CMYK',
      source: PrintConditionSource.quickCamera,
      status: PrintConditionStatus.published,
      measurementCondition: 'D50 · 2° · M1',
      mediaWhitePoint: const PrintMediaWhitePoint(l: 82.4, a: 3.1, b: 18.7),
      quickEvidence: const QuickPrintProfileEvidence(
        cameraCalibrationProfileId: 'camera-profile-1',
        trainingPatchCount: 24,
        validationPatchCount: 6,
        averageDeltaE: 3.2,
        maximumDeltaE: 6.1,
      ),
      customerVisible: true,
      createdAt: now,
      updatedAt: now,
    );

    expect(condition.canPublish, isTrue);
    expect(condition.customerSelectable, isTrue);
  });
}

Uint8List _iccHeader({
  String profileClass = 'prtr',
  String colorSpace = 'CMYK',
}) {
  final bytes = Uint8List(132);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, bytes.length, Endian.big);
  bytes[8] = 4;
  bytes[9] = 0x30;
  _ascii(bytes, 12, profileClass);
  _ascii(bytes, 16, colorSpace);
  _ascii(bytes, 20, 'Lab ');
  _ascii(bytes, 36, 'acsp');
  data.setUint32(128, 0, Endian.big);
  return bytes;
}

void _ascii(Uint8List bytes, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    bytes[offset + index] = value.codeUnitAt(index);
  }
}
