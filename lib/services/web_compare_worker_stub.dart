import 'package:flutter/foundation.dart';

bool get isWebCompareWorkerSupported => false;

Future<Map<String, dynamic>> runWebCompareWorker({
  required Uint8List reference,
  required Uint8List sample,
  required int pixelStep,
  required int edgeTolerance,
  required String deltaEFormula,
  required bool includeGeometry,
  required bool includeCanonical,
  ValueChanged<String>? onProgress,
}) {
  throw UnsupportedError('Web Worker is available only in a browser');
}

Future<({Uint8List bytes, int width, int height})> runWebCropWorker({
  required Uint8List image,
  required int x,
  required int y,
  required int width,
  required int height,
  ValueChanged<String>? onProgress,
}) {
  throw UnsupportedError('Web Worker is available only in a browser');
}
