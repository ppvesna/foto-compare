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

  test('web worker owns point measurement without blocking Flutter UI', () {
    final worker = File('web/compare_worker.js').readAsStringSync();
    final screen = File('lib/screens/compare_screen.dart').readAsStringSync();

    expect(worker, contains("task.type === 'point'"));
    expect(worker, contains('measurePointPair(task)'));
    expect(worker, contains('await measurePointImage('));
    expect(worker, contains("type: 'pointResult'"));
    expect(screen, contains('runWebPointWorker('));
    expect(screen, contains('if (_pointProbeBusy) return;'));
  });

  test('point worker preserves the established aperture and Lab formulas', () {
    final worker = File('web/compare_worker.js').readAsStringSync();

    expect(
      worker,
      contains('Math.max(0.5, (diameterMm * pixelsPerMm) / 2)'),
    );
    expect(worker, contains('imageData.data[index + 3] < 250'));
    expect(worker, contains('r * 0.4124564 + g * 0.3575761'));
    expect(worker, contains('sampledPixels: count'));
  });
}
