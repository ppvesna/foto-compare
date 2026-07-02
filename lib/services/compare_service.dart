import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CompareService {
  static Future<CompareResult> compare(Uint8List ref, Uint8List cmp) {
    return compute(_run, [ref, cmp]);
  }
}

// Пиксель не покрыт исходником после warp, либо частично смешан с
// прозрачной кромкой при уменьшении (альфа размывается на границе) —
// исключаем, иначе на стыке остаётся ложная зелёная "тень"
bool _noData(img.Pixel p) => p.a < 250;

// Diff-карта: прозрачная → зелёная → жёлтая → красная
Uint8List _buildDiffImage(img.Image r, img.Image c) {
  final w = r.width;
  final h = r.height;
  final out = img.Image(width: w, height: h, numChannels: 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final pr = r.getPixel(x, y);
      final pc = c.getPixel(x, y);
      if (_noData(pc)) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      final d =
          ((pr.r - pc.r).abs() + (pr.g - pc.g).abs() + (pr.b - pc.b).abs()) /
              (3 * 255.0);
      if (d < 0.04) {
        out.setPixelRgba(x, y, 0, 0, 0, 0); // прозрачный
      } else if (d < 0.20) {
        final a = ((d - 0.04) / 0.16 * 210).toInt();
        out.setPixelRgba(x, y, 30, 210, 30, a); // зелёный
      } else if (d < 0.45) {
        final a = 180 + ((d - 0.20) / 0.25 * 50).toInt();
        out.setPixelRgba(x, y, 255, 170, 0, a.clamp(0, 230)); // жёлтый
      } else {
        out.setPixelRgba(x, y, 240, 20, 20, 230); // красный
      }
    }
  }
  return Uint8List.fromList(img.encodePng(out));
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

CompareResult _run(List<Uint8List> args) {
  final imgRef = img.decodeImage(args[0]);
  final imgCmp = img.decodeImage(args[1]);
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

  double diff = 0;
  int diffPx = 0;
  int validPx = 0;
  for (int y = 0; y < refCanonical.height; y++) {
    for (int x = 0; x < refCanonical.width; x++) {
      final pr = refCanonical.getPixel(x, y);
      final pc = cmpCanonical.getPixel(x, y);
      if (_noData(pc)) continue;
      validPx++;
      final d =
          ((pr.r - pc.r).abs() + (pr.g - pc.g).abs() + (pr.b - pc.b).abs()) /
              (3 * 255);
      diff += d;
      if (d > 0.08) diffPx++;
    }
  }
  final avgDiff = validPx == 0 ? 0.0 : diff / validPx;
  final scaled = (avgDiff * 3.5).clamp(0.0, 1.0);
  final similarity = ((1 - scaled) * 100).clamp(0.0, 100.0);

  return CompareResult(
    similarity: similarity,
    diffPixels: diffPx,
    totalPixels:
        validPx == 0 ? refCanonical.width * refCanonical.height : validPx,
    refSize: '${imgRef.width}×${imgRef.height}',
    cmpSize: '${imgCmp.width}×${imgCmp.height}',
    refCanonical: Uint8List.fromList(img.encodePng(refCanonical)),
    cmpCanonical: Uint8List.fromList(img.encodePng(cmpCanonical)),
    diffL3: _buildDiffImage(refCanonical, cmpCanonical),
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
  final Uint8List? refCanonical; // каноническое ref для наложения diff
  final Uint8List? cmpCanonical; // каноническое cmp, та же система координат
  final int diffPixels;
  final int totalPixels;
  final String refSize;
  final String cmpSize;
  final Uint8List? diffL3; // PNG карта L3 27×27 детали

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
    this.cmpCanonical,
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
