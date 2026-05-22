import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../config/app_config.dart';

class CompareService {
  static Future<CompareResult> compare(Uint8List ref, Uint8List cmp) {
    return compute(_run, [ref, cmp]);
  }
}

// Ресайз с сохранением пропорций + центральный кроп до квадрата
img.Image _fitCrop(img.Image source, int size) {
  final w = source.width;
  final h = source.height;
  // Масштабируем по короткой стороне
  final img.Image resized;
  if (w < h) {
    resized = img.copyResize(source, width: size,
        interpolation: img.Interpolation.average);
  } else {
    resized = img.copyResize(source, height: size,
        interpolation: img.Interpolation.average);
  }
  // Центральный кроп до size×size
  final cx = ((resized.width - size) / 2).floor().clamp(0, resized.width - size);
  final cy = ((resized.height - size) / 2).floor().clamp(0, resized.height - size);
  return img.copyCrop(resized, x: cx, y: cy, width: size, height: size);
}

// Diff-карта: прозрачная → зелёная → жёлтая → красная
Uint8List _buildDiffImage(img.Image r, img.Image c) {
  final w = r.width;
  final h = r.height;
  final out = img.Image(width: w, height: h, numChannels: 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final pr = r.getPixel(x, y);
      final pc = c.getPixel(x, y);
      final d = ((pr.r - pc.r).abs() +
                 (pr.g - pc.g).abs() +
                 (pr.b - pc.b).abs()) / (3 * 255.0);
      if (d < 0.04) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);              // прозрачный
      } else if (d < 0.20) {
        final a = ((d - 0.04) / 0.16 * 210).toInt();
        out.setPixelRgba(x, y, 30, 210, 30, a);           // зелёный
      } else if (d < 0.45) {
        final a = 180 + ((d - 0.20) / 0.25 * 50).toInt();
        out.setPixelRgba(x, y, 255, 170, 0, a.clamp(0, 230)); // жёлтый
      } else {
        out.setPixelRgba(x, y, 240, 20, 20, 230);         // красный
      }
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

// Нормализация яркости: приводит среднюю яркость src к targetMean эталона
img.Image _normalizeLuminance(img.Image src, double targetMean) {
  if (targetMean < 1) return src;
  double sum = 0;
  final total = src.width * src.height;
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      sum += p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
    }
  }
  final srcMean = sum / total;
  if (srcMean < 1) return src;
  final scale = targetMean / srcMean;
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      out.setPixelRgb(x, y,
        (p.r * scale).clamp(0, 255).toInt(),
        (p.g * scale).clamp(0, 255).toInt(),
        (p.b * scale).clamp(0, 255).toInt(),
      );
    }
  }
  return out;
}

double _meanLuminance(img.Image src) {
  double sum = 0;
  final total = src.width * src.height;
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      sum += p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
    }
  }
  return sum / total;
}

CompareResult _run(List<Uint8List> args) {
  final imgRef = img.decodeImage(args[0]);
  final imgCmp = img.decodeImage(args[1]);
  if (imgRef == null || imgCmp == null) {
    throw Exception('Не удалось декодировать изображение');
  }

  final maxSize = kIsWeb ? 128 : 256;
  final iters   = kIsWeb ? 1   : AppConfig.comparisonIter;
  final sizes   = [64, 128, maxSize].take(iters).toList();

  // Нормализация: приводим яркость сравниваемого к яркости эталона
  final refThumb = _fitCrop(imgRef, maxSize);
  final refMean  = _meanLuminance(refThumb);
  final imgCmpNorm = _normalizeLuminance(imgCmp, refMean);

  double totalSim = 0;
  for (final size in sizes) {
    final r = _fitCrop(imgRef, size);
    final c = _fitCrop(imgCmpNorm, size);
    double diff = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final pr = r.getPixel(x, y);
        final pc = c.getPixel(x, y);
        diff += ((pr.r - pc.r).abs() +
                 (pr.g - pc.g).abs() +
                 (pr.b - pc.b).abs()) / (3 * 255);
      }
    }
    final avgDiff = diff / (size * size);
    final scaled  = (avgDiff * 3.5).clamp(0.0, 1.0);
    totalSim += (1 - scaled) * 100;
  }
  final similarity = (totalSim / iters).clamp(0.0, 100.0);

  // Диффпиксели + карта на рабочем масштабе (используем нормализованное)
  final r2 = refThumb;
  final c2 = _fitCrop(imgCmpNorm, maxSize);
  int diffPx = 0;
  for (int y = 0; y < maxSize; y++) {
    for (int x = 0; x < maxSize; x++) {
      final pr = r2.getPixel(x, y);
      final pc = c2.getPixel(x, y);
      final d = ((pr.r - pc.r).abs() +
                 (pr.g - pc.g).abs() +
                 (pr.b - pc.b).abs()) / (3 * 255);
      if (d > 0.08) diffPx++;
    }
  }

  return CompareResult(
    similarity:  similarity,
    diffPixels:  diffPx,
    totalPixels: maxSize * maxSize,
    refSize:     '${imgRef.width}×${imgRef.height}',
    cmpSize:     '${imgCmp.width}×${imgCmp.height}',
    diffL1:      null,
    diffL2:      _buildDiffImage(r2, c2),
    diffL3:      null,
  );
}

class CompareResult {
  final double    similarity;
  final double?   ssim;           // OpenCV SSIM (null если недоступен)
  final double?   labScore;       // Lab-пирамида итоговый балл
  final List<double>? labLevel0;  //   1 зона
  final List<double>? labLevel1;  //   9 зон
  final List<double>? labLevel2;  //  81 зона
  final List<double>? labLevel3;  // 729 зон
  final int       diffPixels;
  final int       totalPixels;
  final String    refSize;
  final String    cmpSize;
  final Uint8List? diffL1;        // PNG карта L1 3×3  крупные зоны
  final Uint8List? diffL2;        // PNG карта L2 9×9  средние зоны
  final Uint8List? diffL3;        // PNG карта L3 27×27 детали

  const CompareResult({
    required this.similarity,
    this.ssim,
    this.labScore,
    this.labLevel0,
    this.labLevel1,
    this.labLevel2,
    this.labLevel3,
    required this.diffPixels,
    required this.totalPixels,
    required this.refSize,
    required this.cmpSize,
    this.diffL1,
    this.diffL2,
    this.diffL3,
  });

  double get diffPercent => diffPixels / totalPixels * 100;

  // Приоритет: Lab > SSIM > MAE
  double get score => labScore ?? ssim ?? similarity;
}
