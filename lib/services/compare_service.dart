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

// Применяет масштаб яркости к (уже уменьшенному) изображению
img.Image _applyLuminanceScale(img.Image src, double scale) {
  if ((scale - 1.0).abs() < 0.001) return src;
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

  // Эталон и сравниваемое — уменьшенные копии (быстро, не зависит от исходного разрешения)
  final refThumb = _fitCrop(imgRef, maxSize);
  final cmpThumbRaw = _fitCrop(imgCmp, maxSize);

  // Нормализация: приводим яркость сравниваемого к яркости эталона
  final refMean = _meanLuminance(refThumb);
  final cmpMean = _meanLuminance(cmpThumbRaw);
  final lumScale = cmpMean < 1 ? 1.0 : refMean / cmpMean;

  double totalSim = 0;
  for (final size in sizes) {
    final r = size == maxSize ? refThumb : _fitCrop(imgRef, size);
    final cRaw = size == maxSize ? cmpThumbRaw : _fitCrop(imgCmp, size);
    final c = _applyLuminanceScale(cRaw, lumScale);
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
  final c2 = _applyLuminanceScale(cmpThumbRaw, lumScale);
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
    diffL3:      _buildDiffImage(r2, c2),
  );
}

class CompareResult {
  final double    similarity;
  final double?   ssim;
  final double?   labScore;
  final List<double>? labLevel0;
  final List<double>? labLevel1;
  final List<double>? labLevel2;
  final List<double>? labLevel3;
  final double?   shiftDL;        // глобальный сдвиг L*
  final double?   shiftDA;        // глобальный сдвиг a*
  final double?   shiftDB;        // глобальный сдвиг b*
  final Uint8List? refCanonical;  // каноническое ref для наложения diff
  final int       diffPixels;
  final int       totalPixels;
  final String    refSize;
  final String    cmpSize;
  final Uint8List? diffL3;        // PNG карта L3 27×27 детали

  const CompareResult({
    required this.similarity,
    this.ssim,
    this.labScore,
    this.labLevel0,
    this.labLevel1,
    this.labLevel2,
    this.labLevel3,
    this.shiftDL,
    this.shiftDA,
    this.shiftDB,
    this.refCanonical,
    required this.diffPixels,
    required this.totalPixels,
    required this.refSize,
    required this.cmpSize,
    this.diffL3,
  });

  double get diffPercent => diffPixels / totalPixels * 100;

  // Приоритет: Lab > SSIM > MAE
  double get score => labScore ?? ssim ?? similarity;
}
