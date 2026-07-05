import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'compare_settings_service.dart';

class CompareService {
  static Future<CompareResult> compare(Uint8List ref, Uint8List cmp) async {
    final settings = await CompareSettingsService.load();
    return compute(_run, [ref, cmp, settings.deltaEdgeTolerancePx]);
  }
}

// Пиксель не покрыт исходником после warp, либо частично смешан с
// прозрачной кромкой при уменьшении (альфа размывается на границе) —
// исключаем, иначе на стыке остаётся ложная зелёная "тень"
bool _noData(img.Pixel p) => p.a < 250;

const int _tileSize = 512;
const int _defectZoneSize = 64;
const double _minorDeltaE = 3.0;
const double _strongDeltaE = 6.0;
const double _criticalDeltaE = 12.0;

double _pivotRgb(num v) {
  final c = v / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

double _pivotXyz(double v) {
  return v > 0.008856 ? math.pow(v, 1 / 3) as double : (7.787 * v) + 16 / 116;
}

({double l, double a, double b}) _rgbToLab(img.Pixel p) {
  final r = _pivotRgb(p.r);
  final g = _pivotRgb(p.g);
  final b = _pivotRgb(p.b);

  final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
  final y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750) / 1.00000;
  final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;

  final fx = _pivotXyz(x);
  final fy = _pivotXyz(y);
  final fz = _pivotXyz(z);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _deltaE76(img.Pixel ref, img.Pixel cmp) {
  final a = _rgbToLab(ref);
  final b = _rgbToLab(cmp);
  final dl = a.l - b.l;
  final da = a.a - b.a;
  final db = a.b - b.b;
  return math.sqrt(dl * dl + da * da + db * db);
}

_TileCompareData _compareTiles(
  img.Image r,
  img.Image c,
  int edgeToleranceRadius,
) {
  final residualShift = _estimateResidualShift(r, c);
  final refEdges = _edgeMask(r);
  final cmpEdges = _edgeMask(c);
  final w = r.width;
  final h = r.height;
  final zoneCols = (w + _defectZoneSize - 1) ~/ _defectZoneSize;
  final out = img.Image(width: w, height: h, numChannels: 4);
  double diff = 0;
  double maxDeltaE = 0;
  int diffPx = 0;
  int validPx = 0;
  final defectZones = <int>{};

  for (int y0 = 0; y0 < h; y0 += _tileSize) {
    final y1 = (y0 + _tileSize).clamp(0, h);
    for (int x0 = 0; x0 < w; x0 += _tileSize) {
      final x1 = (x0 + _tileSize).clamp(0, w);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          final pr = r.getPixel(x, y);
          final cx = x + residualShift.x;
          final cy = y + residualShift.y;
          if (cx < 0 || cy < 0 || cx >= w || cy >= h) {
            out.setPixelRgba(x, y, 0, 0, 0, 0);
            continue;
          }
          final pc = c.getPixel(cx, cy);
          if (_noData(pr) || _noData(pc)) {
            out.setPixelRgba(x, y, 0, 0, 0, 0);
            continue;
          }
          var deltaE = _deltaE76(pr, pc);
          if (edgeToleranceRadius > 0 &&
              deltaE >= _minorDeltaE &&
              (_isEdgeNear(refEdges, w, h, x, y, edgeToleranceRadius) ||
                  _isEdgeNear(cmpEdges, w, h, cx, cy, edgeToleranceRadius))) {
            deltaE = math.min(
              deltaE,
              _minLocalDeltaE(
                pr,
                c,
                cx,
                cy,
                edgeToleranceRadius,
              ),
            );
          }
          diff += deltaE;
          if (deltaE > maxDeltaE) maxDeltaE = deltaE;
          validPx++;
          if (deltaE >= _minorDeltaE) diffPx++;
          if (deltaE >= _strongDeltaE) {
            defectZones
                .add((y ~/ _defectZoneSize) * zoneCols + x ~/ _defectZoneSize);
          }
          if (deltaE < _minorDeltaE) {
            out.setPixelRgba(x, y, 0, 0, 0, 0); // прозрачный
          } else if (deltaE < _strongDeltaE) {
            final a =
                ((deltaE - _minorDeltaE) / (_strongDeltaE - _minorDeltaE) * 210)
                    .toInt();
            out.setPixelRgba(x, y, 30, 210, 30, a); // зелёный
          } else if (deltaE < _criticalDeltaE) {
            final a = 180 +
                ((deltaE - _strongDeltaE) /
                        (_criticalDeltaE - _strongDeltaE) *
                        50)
                    .toInt();
            out.setPixelRgba(x, y, 255, 170, 0, a.clamp(0, 230)); // жёлтый
          } else {
            out.setPixelRgba(x, y, 240, 20, 20, 230); // красный
          }
        }
      }
    }
  }

  return _TileCompareData(
    diff: diff,
    diffPixels: diffPx,
    totalPixels: validPx == 0 ? w * h : validPx,
    maxDeltaE: maxDeltaE,
    defectZoneCount: defectZones.length,
    diffPng: Uint8List.fromList(img.encodePng(out)),
  );
}

GeometryCompareData _compareGeometry(img.Image r, img.Image c) {
  final residualShift = _estimateResidualShift(r, c);
  final refEdges = _edgeMask(r);
  final cmpEdges = _edgeMask(c);
  final out = img.Image(width: r.width, height: r.height, numChannels: 4);
  int refEdgeCount = 0;
  int cmpEdgeCount = 0;
  int overlap = 0;
  int missing = 0;
  int extra = 0;

  for (int y = 0; y < r.height; y++) {
    for (int x = 0; x < r.width; x++) {
      final i = y * r.width + x;
      final refHas = refEdges[i] == 1;
      if (refHas) refEdgeCount++;

      final cx = x + residualShift.x;
      final cy = y + residualShift.y;
      final cmpHas = cx >= 0 &&
          cy >= 0 &&
          cx < c.width &&
          cy < c.height &&
          cmpEdges[cy * c.width + cx] == 1;
      if (cmpHas) cmpEdgeCount++;

      if (refHas && cmpHas) {
        overlap++;
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      } else if (refHas) {
        missing++;
        out.setPixelRgba(x, y, 40, 90, 255, 210);
      } else if (cmpHas) {
        extra++;
        out.setPixelRgba(x, y, 230, 30, 120, 210);
      } else {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  final union = refEdgeCount + cmpEdgeCount - overlap;
  final score = union == 0 ? 100.0 : overlap / union * 100;
  final missingPercent = refEdgeCount == 0 ? 0.0 : missing / refEdgeCount * 100;
  final extraPercent = cmpEdgeCount == 0 ? 0.0 : extra / cmpEdgeCount * 100;
  final shiftPx = math.sqrt(
      residualShift.x * residualShift.x + residualShift.y * residualShift.y);

  return GeometryCompareData(
    score: score.clamp(0.0, 100.0),
    shiftPx: shiftPx,
    missingPercent: missingPercent,
    extraPercent: extraPercent,
    overlapPixels: overlap,
    missingPixels: missing,
    extraPixels: extra,
    diffPng: Uint8List.fromList(img.encodePng(out)),
  );
}

Uint8List _edgeMask(img.Image source) {
  final w = source.width;
  final h = source.height;
  final gradients = Float32List(w * h);
  double sum = 0;
  double maxGradient = 0;
  int count = 0;

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final gx =
          _luma(source.getPixel(x + 1, y)) - _luma(source.getPixel(x - 1, y));
      final gy =
          _luma(source.getPixel(x, y + 1)) - _luma(source.getPixel(x, y - 1));
      final g = gx.abs() + gy.abs();
      gradients[y * w + x] = g;
      sum += g;
      if (g > maxGradient) maxGradient = g;
      count++;
    }
  }

  final mean = count == 0 ? 0.0 : sum / count;
  final threshold = math.max(18.0, math.max(mean * 2.4, maxGradient * 0.16));
  final mask = Uint8List(w * h);

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final p = source.getPixel(x, y);
      if (_noData(p)) continue;
      if (gradients[y * w + x] >= threshold) mask[y * w + x] = 1;
    }
  }
  return mask;
}

bool _isEdgeNear(
  Uint8List mask,
  int width,
  int height,
  int cx,
  int cy,
  int radius,
) {
  for (int y = math.max(1, cy - radius);
      y <= math.min(height - 2, cy + radius);
      y++) {
    for (int x = math.max(1, cx - radius);
        x <= math.min(width - 2, cx + radius);
        x++) {
      if (mask[y * width + x] == 1) return true;
    }
  }
  return false;
}

double _minLocalDeltaE(
  img.Pixel ref,
  img.Image cmp,
  int cx,
  int cy,
  int radius,
) {
  var best = double.infinity;
  for (int y = math.max(0, cy - radius);
      y <= math.min(cmp.height - 1, cy + radius);
      y++) {
    for (int x = math.max(0, cx - radius);
        x <= math.min(cmp.width - 1, cx + radius);
        x++) {
      final p = cmp.getPixel(x, y);
      if (_noData(p)) continue;
      best = math.min(best, _deltaE76(ref, p));
    }
  }
  if (best.isFinite) return best;
  return _deltaE76(ref, cmp.getPixel(cx, cy));
}

({int x, int y}) _estimateResidualShift(img.Image r, img.Image c) {
  if (r.width != c.width || r.height != c.height) return (x: 0, y: 0);
  final maxDim = math.max(r.width, r.height);
  final sampleStep = math.max(1, (maxDim / 420).round());
  final radius = math.max(4, math.min(24, (maxDim / 220).round()));
  final margin = radius + sampleStep * 2;
  double bestScore = double.infinity;
  var best = (x: 0, y: 0);

  for (int dy = -radius; dy <= radius; dy++) {
    for (int dx = -radius; dx <= radius; dx++) {
      double score = 0;
      int count = 0;
      for (int y = margin; y < r.height - margin; y += sampleStep) {
        final cy = y + dy;
        if (cy < 0 || cy >= c.height) continue;
        for (int x = margin; x < r.width - margin; x += sampleStep) {
          final cx = x + dx;
          if (cx < 0 || cx >= c.width) continue;
          final pr = r.getPixel(x, y);
          final pc = c.getPixel(cx, cy);
          if (_noData(pr) || _noData(pc)) continue;
          score += _lumaAbs(pr, pc);
          count++;
        }
      }
      if (count == 0) continue;
      final avg = score / count;
      if (avg < bestScore) {
        bestScore = avg;
        best = (x: dx, y: dy);
      }
    }
  }

  // A small translation residue is common after manual anchors and resampling.
  // A large one usually means the points/order are wrong, so do not hide it.
  final maxAccepted = math.max(4, (maxDim / 450).round());
  return best.x.abs() <= maxAccepted && best.y.abs() <= maxAccepted
      ? best
      : (x: 0, y: 0);
}

double _lumaAbs(img.Pixel a, img.Pixel b) {
  final la = a.r * 0.299 + a.g * 0.587 + a.b * 0.114;
  final lb = b.r * 0.299 + b.g * 0.587 + b.b * 0.114;
  return (la - lb).abs();
}

double _luma(img.Pixel p) => p.r * 0.299 + p.g * 0.587 + p.b * 0.114;

class GeometryCompareData {
  final double score;
  final double shiftPx;
  final double missingPercent;
  final double extraPercent;
  final int overlapPixels;
  final int missingPixels;
  final int extraPixels;
  final Uint8List diffPng;

  const GeometryCompareData({
    required this.score,
    required this.shiftPx,
    required this.missingPercent,
    required this.extraPercent,
    required this.overlapPixels,
    required this.missingPixels,
    required this.extraPixels,
    required this.diffPng,
  });
}

class _TileCompareData {
  final double diff;
  final int diffPixels;
  final int totalPixels;
  final double maxDeltaE;
  final int defectZoneCount;
  final Uint8List diffPng;

  const _TileCompareData({
    required this.diff,
    required this.diffPixels,
    required this.totalPixels,
    required this.maxDeltaE,
    required this.defectZoneCount,
    required this.diffPng,
  });
}

// Применяет масштаб яркости к (уже уменьшенному) изображению
img.Image _applyLuminanceScale(img.Image src, double scale) {
  if ((scale - 1.0).abs() < 0.001) return src;
  final out = img.Image(
      width: src.width, height: src.height, numChannels: src.numChannels);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      out.setPixelRgba(
        x,
        y,
        (p.r * scale).clamp(0, 255).toInt(),
        (p.g * scale).clamp(0, 255).toInt(),
        (p.b * scale).clamp(0, 255).toInt(),
        p.a.toInt(),
      );
    }
  }
  return out;
}

// Среднее по пикселям, исключая непокрытые после warp (альфа=0)
double _meanLuminance(img.Image src) {
  double sum = 0;
  int count = 0;
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (_noData(p)) continue;
      sum += p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

CompareResult _run(List<dynamic> args) {
  final imgRef = img.decodeImage(args[0] as Uint8List);
  final imgCmp = img.decodeImage(args[1] as Uint8List);
  final edgeToleranceRadius =
      args.length > 2 ? (args[2] as int).clamp(0, 3) : 2;
  if (imgRef == null || imgCmp == null) {
    throw Exception('Не удалось декодировать изображение');
  }

  final refCanonical = imgRef;
  final cmpCanonicalRaw =
      imgCmp.width == imgRef.width && imgCmp.height == imgRef.height
          ? imgCmp
          : img.copyResize(
              imgCmp,
              width: imgRef.width,
              height: imgRef.height,
              interpolation: img.Interpolation.average,
            );

  // Нормализация: приводим яркость сравниваемого к яркости эталона
  final refMean = _meanLuminance(refCanonical);
  final cmpMean = _meanLuminance(cmpCanonicalRaw);
  final lumScale = cmpMean < 1 ? 1.0 : refMean / cmpMean;
  final cmpCanonical = _applyLuminanceScale(cmpCanonicalRaw, lumScale);

  final tileResult =
      _compareTiles(refCanonical, cmpCanonical, edgeToleranceRadius);
  final geometry = _compareGeometry(refCanonical, cmpCanonical);
  final avgDiff = tileResult.totalPixels == 0
      ? 0.0
      : tileResult.diff / tileResult.totalPixels;
  final scaled = (avgDiff / _criticalDeltaE).clamp(0.0, 1.0);
  final similarity = ((1 - scaled) * 100).clamp(0.0, 100.0);

  return CompareResult(
    similarity: similarity,
    diffPixels: tileResult.diffPixels,
    totalPixels: tileResult.totalPixels,
    refSize: '${imgRef.width}×${imgRef.height}',
    cmpSize: '${imgCmp.width}×${imgCmp.height}',
    meanDeltaE: avgDiff,
    maxDeltaE: tileResult.maxDeltaE,
    defectZoneCount: tileResult.defectZoneCount,
    defectAreaPercent: tileResult.diffPixels / tileResult.totalPixels * 100,
    refCanonical: Uint8List.fromList(img.encodePng(refCanonical)),
    cmpCanonical: Uint8List.fromList(img.encodePng(cmpCanonical)),
    diffL3: tileResult.diffPng,
    geometryScore: geometry.score,
    geometryShiftPx: geometry.shiftPx,
    geometryMissingPercent: geometry.missingPercent,
    geometryExtraPercent: geometry.extraPercent,
    geometryOverlapPixels: geometry.overlapPixels,
    geometryMissingPixels: geometry.missingPixels,
    geometryExtraPixels: geometry.extraPixels,
    geometryDiff: geometry.diffPng,
    geometryRefCanonical: Uint8List.fromList(img.encodePng(refCanonical)),
    geometryCmpCanonical: Uint8List.fromList(img.encodePng(cmpCanonical)),
  );
}

class CompareResult {
  final double similarity;
  final double? ssim;
  final double? labScore;
  final List<double>? labLevel0;
  final List<double>? labLevel1;
  final List<double>? labLevel2;
  final List<double>? labLevel3;
  final double? shiftDL; // глобальный сдвиг L*
  final double? shiftDA; // глобальный сдвиг a*
  final double? shiftDB; // глобальный сдвиг b*
  final double? meanDeltaE;
  final double? maxDeltaE;
  final int? defectZoneCount;
  final double? defectAreaPercent;
  final Uint8List? refCanonical; // каноническое ref для наложения diff
  final Uint8List? cmpCanonical; // каноническое cmp, та же система координат
  final int diffPixels;
  final int totalPixels;
  final String refSize;
  final String cmpSize;
  final Uint8List? diffL3; // PNG карта L3 27×27 детали
  final double? geometryScore;
  final double? geometryShiftPx;
  final double? geometryMissingPercent;
  final double? geometryExtraPercent;
  final int? geometryOverlapPixels;
  final int? geometryMissingPixels;
  final int? geometryExtraPixels;
  final Uint8List? geometryDiff;
  final Uint8List? geometryRefCanonical;
  final Uint8List? geometryCmpCanonical;

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
    this.meanDeltaE,
    this.maxDeltaE,
    this.defectZoneCount,
    this.defectAreaPercent,
    this.refCanonical,
    this.cmpCanonical,
    required this.diffPixels,
    required this.totalPixels,
    required this.refSize,
    required this.cmpSize,
    this.diffL3,
    this.geometryScore,
    this.geometryShiftPx,
    this.geometryMissingPercent,
    this.geometryExtraPercent,
    this.geometryOverlapPixels,
    this.geometryMissingPixels,
    this.geometryExtraPixels,
    this.geometryDiff,
    this.geometryRefCanonical,
    this.geometryCmpCanonical,
  });

  double get diffPercent => diffPixels / totalPixels * 100;

  // Приоритет: Lab > SSIM > MAE
  double get score => labScore ?? ssim ?? similarity;
}
