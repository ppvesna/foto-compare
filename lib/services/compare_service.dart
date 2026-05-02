import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../config/app_config.dart';

class CompareService {
  static Future<CompareResult> compare(Uint8List ref, Uint8List cmp) {
    return compute(_run, [ref, cmp]);
  }
}

CompareResult _run(List<Uint8List> args) {
  final imgRef = img.decodeImage(args[0]);
  final imgCmp = img.decodeImage(args[1]);

  if (imgRef == null || imgCmp == null) {
    throw Exception('Не удалось декодировать изображение');
  }

  // На вебе используем меньший размер — JS медленнее нативного
  final maxSize = kIsWeb ? 128 : 256;
  final iters = kIsWeb ? 1 : AppConfig.comparisonIter;
  final sizes = [64, 128, maxSize].take(iters).toList();

  double totalSim = 0;
  for (final size in sizes) {
    final r = img.copyResize(imgRef, width: size, height: size,
        interpolation: img.Interpolation.average);
    final c = img.copyResize(imgCmp, width: size, height: size,
        interpolation: img.Interpolation.average);

    double diff = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final pr = r.getPixel(x, y);
        final pc = c.getPixel(x, y);
        diff += ((pr.r - pc.r).abs() +
                 (pr.g - pc.g).abs() +
                 (pr.b - pc.b).abs()) /
                (3 * 255);
      }
    }
    totalSim += (1 - diff / (size * size)) * 100;
  }

  final similarity = (totalSim / iters).clamp(0.0, 100.0);

  // Диффпиксели на рабочем масштабе
  final ds = maxSize;
  final r2 = img.copyResize(imgRef, width: ds, height: ds);
  final c2 = img.copyResize(imgCmp, width: ds, height: ds);
  int diffPx = 0;
  for (int y = 0; y < ds; y++) {
    for (int x = 0; x < ds; x++) {
      final pr = r2.getPixel(x, y);
      final pc = c2.getPixel(x, y);
      final d = ((pr.r - pc.r).abs() + (pr.g - pc.g).abs() +
                 (pr.b - pc.b).abs()) / (3 * 255);
      if (d > 0.08) diffPx++;
    }
  }

  return CompareResult(
    similarity: similarity,
    diffPixels: diffPx,
    totalPixels: ds * ds,
    refSize: '${imgRef.width}×${imgRef.height}',
    cmpSize: '${imgCmp.width}×${imgCmp.height}',
  );
}

class CompareResult {
  final double similarity;
  final int diffPixels;
  final int totalPixels;
  final String refSize;
  final String cmpSize;

  const CompareResult({
    required this.similarity,
    required this.diffPixels,
    required this.totalPixels,
    required this.refSize,
    required this.cmpSize,
  });

  double get diffPercent => diffPixels / totalPixels * 100;
}
