import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web worker owns the complete point-alignment pipeline', () {
    final worker = File('web/compare_worker.js').readAsStringSync();

    expect(worker, contains("task.type === 'align'"));
    expect(worker, contains('chooseAlignmentHomography('));
    expect(worker, contains('warpPerspective('));
    expect(worker, contains("type: 'alignResult'"));
    expect(worker, contains('alignedPng'));
    expect(worker, contains('referencePng'));
    expect(worker, contains('homography'));
  });

  test('web alignment keeps the established transform thresholds', () {
    final worker = File('web/compare_worker.js').readAsStringSync();

    expect(worker, contains('bestError <= 3'));
    expect(worker, contains('affineError < bestError * 0.70'));
    expect(worker, contains('perspectiveError < bestError * 0.55'));
    expect(worker, contains("reprojError < 18 ? 'warning' : 'fail'"));
  });
}
