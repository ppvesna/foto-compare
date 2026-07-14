import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Offset;
import 'package:image/image.dart' as img;
import '../config/app_config.dart';

// Источник на вход warp ограничиваем по перфомансу — само число не влияет
// на итоговый кадр (только на качество билинейной выборки).
const int _kMaxSrcDim = 1600;

// Каноническое разрешение печати: 70 л/см × 2 (Найквист) / 10 мм/см,
// округлённое до кратного 27 (см. OpenCvPlugin.kt canonicalRes — тот же
// стандарт применяется нативно). Используется как единая целевая рамка
// и для эталона, и для выровненного образца, иначе их размеры расходятся.
int canonicalDim(double mm) {
  const pxPerMm = 14.0;
  return ((mm * pxPerMm) / 27).ceil() * 27;
}

/// Pure-Dart fallback for alignByAnchors (web / no OpenCV).
/// Warps srcBytes → the rectangular reference plane.
Future<DartAlignResult?> dartAlignByAnchors(
  Uint8List refBytes,
  Uint8List srcBytes,
  List<Offset> refPoints,
  List<Offset> srcPoints,
) async {
  final refImg = img.decodeImage(refBytes);
  final srcImg = img.decodeImage(srcBytes);
  if (refImg == null || srcImg == null) return null;

  final refW = refImg.width, refH = refImg.height;
  final srcW = srcImg.width, srcH = srcImg.height;

  // Целевая плотность пикселей берётся из физического размера печати, но
  // рамка сохраняет родную пропорцию эталона — иначе непрямоугольный кадр
  // (типичное фото) сплющивается/растягивается в квадрат из AppConfig.
  final longPx =
      canonicalDim(math.max(AppConfig.printWidthMm, AppConfig.printHeightMm));
  int canonW, canonH;
  if (refW >= refH) {
    canonW = longPx;
    canonH = math.max(27, (((refH / refW) * longPx) / 27).round() * 27);
  } else {
    canonH = longPx;
    canonW = math.max(27, (((refW / refH) * longPx) / 27).round() * 27);
  }

  // Якоря эталона нормализованы относительно его собственных пикселей —
  // переводим их в каноническую рамку независимыми по осям масштабами.
  final refScaleX = canonW / refW;
  final refScaleY = canonH / refH;
  final srcScale = _kMaxSrcDim / math.max(srcW, srcH);

  final scaledRef =
      refPoints.map((p) => Offset(p.dx * refScaleX, p.dy * refScaleY)).toList();
  final scaledSrc =
      srcPoints.map((p) => Offset(p.dx * srcScale, p.dy * srcScale)).toList();

  // Начинаем с мягкого similarity, но для фото под углом этого мало:
  // правильно поставленные точки могут дать десятки пикселей ошибки.
  // Поэтому выбираем самый слабый transform, который реально снижает ошибку.
  final alignment = _chooseAlignmentHomography(
    scaledSrc,
    scaledRef,
    srcWidth: srcW * srcScale,
    srcHeight: srcH * srcScale,
    dstWidth: canonW.toDouble(),
    dstHeight: canonH.toDouble(),
  );
  if (alignment == null) return null;
  final H = alignment.h;

  // Resize source for warping
  final srcResized = img.copyResize(srcImg,
      width: (srcW * srcScale).round(), height: (srcH * srcScale).round());

  // Warp (RGBA — альфа=0 у пикселей, не покрытых исходником, чтобы дальше
  // их можно было исключить из сравнения, а не считать чёрным отличием)
  final warped = _warpPerspective(srcResized, H, canonW, canonH);
  final warpedBytes = Uint8List.fromList(img.encodePng(warped));

  // Эталон приводим к той же канонической рамке — иначе ref/cmp выходят
  // из этой функции разного размера и веб-сравнение (Dart MAE) получает
  // заведомо несопоставимые изображения.
  final refCanonical = img.copyResize(refImg, width: canonW, height: canonH);
  final refCanonicalBytes = Uint8List.fromList(img.encodePng(refCanonical));

  final reproj = _reprojError(H, scaledSrc, scaledRef);

  return DartAlignResult(
    alignedBytes: warpedBytes,
    refCanonicalBytes: refCanonicalBytes,
    homography: H,
    reprojError: reproj,
    usedProjective: alignment.projective,
    pointCount: srcPoints.length,
  );
}

class DartAlignResult {
  final Uint8List alignedBytes;
  final Uint8List refCanonicalBytes;
  final List<double> homography; // 9-element row-major 3×3
  final double reprojError;
  final bool usedProjective;
  final int pointCount;
  const DartAlignResult({
    required this.alignedBytes,
    required this.refCanonicalBytes,
    required this.homography,
    required this.reprojError,
    required this.usedProjective,
    required this.pointCount,
  });
}

// ── Alignment models ─────────────────────────────────

({List<double> h, bool projective})? _chooseAlignmentHomography(
  List<Offset> srcPts,
  List<Offset> dstPts, {
  required double srcWidth,
  required double srcHeight,
  required double dstWidth,
  required double dstHeight,
}) {
  final similarity = _computeSimilarityHomography(srcPts, dstPts);
  if (similarity == null) return null;
  var best = similarity;
  var bestError = _reprojError(best, srcPts, dstPts);
  var bestProjective = false;
  if (bestError <= 3.0) return (h: best, projective: bestProjective);

  final affine = _computeAffineHomography(srcPts, dstPts);
  if (affine != null) {
    final affineError = _reprojError(affine, srcPts, dstPts);
    if (affineError <= 3.0 || affineError < bestError * 0.70) {
      best = affine;
      bestError = affineError;
      bestProjective = false;
    }
  }

  final perspective = _computeProjectiveHomography(
    srcPts,
    dstPts,
    srcWidth: srcWidth,
    srcHeight: srcHeight,
    dstWidth: dstWidth,
    dstHeight: dstHeight,
  );
  if (perspective != null) {
    final perspectiveError = _reprojError(perspective, srcPts, dstPts);
    final needsPerspective = bestError > 3.0 || perspectiveError > 0.5;
    if (needsPerspective && perspectiveError < bestError * 0.55) {
      return (h: perspective, projective: true);
    }
  }

  return (h: best, projective: bestProjective);
}

List<double>? _computeSimilarityHomography(
    List<Offset> srcPts, List<Offset> dstPts) {
  if (srcPts.length < 2 || srcPts.length != dstPts.length) return null;

  final rows = 2 * srcPts.length;
  final a = List.generate(rows, (_) => List.filled(4, 0.0));
  final b = List.filled(rows, 0.0);

  for (int i = 0; i < srcPts.length; i++) {
    final x = srcPts[i].dx;
    final y = srcPts[i].dy;
    final u = dstPts[i].dx;
    final v = dstPts[i].dy;
    // u = scale*cos*x - scale*sin*y + tx
    // v = scale*sin*x + scale*cos*y + ty
    a[2 * i] = [x, -y, 1, 0];
    b[2 * i] = u;
    a[2 * i + 1] = [y, x, 0, 1];
    b[2 * i + 1] = v;
  }

  final ata = List.generate(4, (_) => List.filled(4, 0.0));
  final atb = List.filled(4, 0.0);
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < 4; j++) {
      atb[j] += a[i][j] * b[i];
      for (int k = 0; k < 4; k++) {
        ata[j][k] += a[i][j] * a[i][k];
      }
    }
  }

  final p = _solveLinear(ata, atb);
  if (p == null) return null;
  return [p[0], -p[1], p[2], p[1], p[0], p[3], 0.0, 0.0, 1.0];
}

List<double>? _computeAffineHomography(
    List<Offset> srcPts, List<Offset> dstPts) {
  if (srcPts.length < 3 || srcPts.length != dstPts.length) return null;

  final rows = 2 * srcPts.length;
  final a = List.generate(rows, (_) => List.filled(6, 0.0));
  final b = List.filled(rows, 0.0);

  for (int i = 0; i < srcPts.length; i++) {
    final x = srcPts[i].dx;
    final y = srcPts[i].dy;
    final u = dstPts[i].dx;
    final v = dstPts[i].dy;
    a[2 * i] = [x, y, 1, 0, 0, 0];
    b[2 * i] = u;
    a[2 * i + 1] = [0, 0, 0, x, y, 1];
    b[2 * i + 1] = v;
  }

  final p = _solveLeastSquares(a, b, 6);
  if (p == null) return null;
  return [p[0], p[1], p[2], p[3], p[4], p[5], 0.0, 0.0, 1.0];
}

List<double>? _computeProjectiveHomography(
  List<Offset> srcPts,
  List<Offset> dstPts, {
  required double srcWidth,
  required double srcHeight,
  required double dstWidth,
  required double dstHeight,
}) {
  if (srcPts.length < 4 || srcPts.length != dstPts.length) return null;

  final rows = 2 * srcPts.length;
  final a = List.generate(rows, (_) => List.filled(8, 0.0));
  final b = List.filled(rows, 0.0);

  for (int i = 0; i < srcPts.length; i++) {
    final x = srcPts[i].dx;
    final y = srcPts[i].dy;
    final u = dstPts[i].dx;
    final v = dstPts[i].dy;
    a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y];
    b[2 * i] = u;
    a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y];
    b[2 * i + 1] = v;
  }

  final p = _solveLeastSquares(a, b, 8);
  if (p == null) return null;
  final H = [p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], 1.0];
  return _isUsableHomography(
    H,
    srcWidth: srcWidth,
    srcHeight: srcHeight,
    dstWidth: dstWidth,
    dstHeight: dstHeight,
  )
      ? H
      : null;
}

List<double>? _solveLeastSquares(
  List<List<double>> a,
  List<double> b,
  int cols,
) {
  final ata = List.generate(cols, (_) => List.filled(cols, 0.0));
  final atb = List.filled(cols, 0.0);
  for (int i = 0; i < a.length; i++) {
    for (int j = 0; j < cols; j++) {
      atb[j] += a[i][j] * b[i];
      for (int k = 0; k < cols; k++) {
        ata[j][k] += a[i][j] * a[i][k];
      }
    }
  }
  return _solveLinear(ata, atb);
}

bool _isUsableHomography(
  List<double> H, {
  required double srcWidth,
  required double srcHeight,
  required double dstWidth,
  required double dstHeight,
}) {
  final mapped = <Offset>[];
  final corners = [
    Offset.zero,
    Offset(srcWidth, 0),
    Offset(srcWidth, srcHeight),
    Offset(0, srcHeight),
  ];
  for (final p in corners) {
    final wz = H[6] * p.dx + H[7] * p.dy + H[8];
    if (wz.abs() < 1e-9) return false;
    final x = (H[0] * p.dx + H[1] * p.dy + H[2]) / wz;
    final y = (H[3] * p.dx + H[4] * p.dy + H[5]) / wz;
    if (!x.isFinite || !y.isFinite) return false;
    mapped.add(Offset(x, y));
  }

  final mappedBox = _pointBounds(mapped);
  final dstArea = math.max(1.0, dstWidth * dstHeight);
  final mappedArea = mappedBox.width * mappedBox.height;
  return mappedArea > dstArea * 0.05 && mappedArea < dstArea * 20;
}

({double width, double height}) _pointBounds(List<Offset> pts) {
  var minX = double.infinity;
  var maxX = double.negativeInfinity;
  var minY = double.infinity;
  var maxY = double.negativeInfinity;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  return (
    width: math.max(0.0, maxX - minX),
    height: math.max(0.0, maxY - minY)
  );
}

List<double>? _solveLinear(List<List<double>> A, List<double> b) {
  final n = b.length;
  final M = List.generate(n, (i) => [...A[i], b[i]]);

  for (int col = 0; col < n; col++) {
    int maxRow = col;
    double maxVal = M[col][col].abs();
    for (int row = col + 1; row < n; row++) {
      if (M[row][col].abs() > maxVal) {
        maxVal = M[row][col].abs();
        maxRow = row;
      }
    }
    if (maxVal < 1e-10) return null;
    final tmp = M[col];
    M[col] = M[maxRow];
    M[maxRow] = tmp;

    for (int row = col + 1; row < n; row++) {
      final f = M[row][col] / M[col][col];
      for (int k = col; k <= n; k++) {
        M[row][k] -= f * M[col][k];
      }
    }
  }

  final x = List.filled(n, 0.0);
  for (int i = n - 1; i >= 0; i--) {
    x[i] = M[i][n];
    for (int j = i + 1; j < n; j++) {
      x[i] -= M[i][j] * x[j];
    }
    x[i] /= M[i][i];
  }
  return x;
}

List<double> _invertH(List<double> H) {
  final a = H[0], b = H[1], c = H[2];
  final d = H[3], e = H[4], f = H[5];
  final g = H[6], h = H[7], ii = H[8];

  final A = e * ii - f * h;
  final B = -(d * ii - f * g);
  final C = d * h - e * g;
  final D = -(b * ii - c * h);
  final E = a * ii - c * g;
  final F = -(a * h - b * g);
  final G = b * f - c * e;
  final hValue = -(a * f - c * d);
  final I = a * e - b * d;

  final det = a * A + b * B + c * C;
  if (det.abs() < 1e-12) return List.filled(9, 0.0);

  return [
    A / det,
    D / det,
    G / det,
    B / det,
    E / det,
    hValue / det,
    C / det,
    F / det,
    I / det,
  ];
}

// ── Perspective warp (inverse mapping + bilinear) ────

img.Image _warpPerspective(img.Image src, List<double> H, int dstW, int dstH) {
  final inverseH = _invertH(H);
  // numChannels: 4 — непокрытые пиксели остаются alpha=0 (нет данных)
  final dst = img.Image(width: dstW, height: dstH, numChannels: 4);

  final h0 = inverseH[0], h1 = inverseH[1], h2 = inverseH[2];
  final h3 = inverseH[3], h4 = inverseH[4], h5 = inverseH[5];
  final h6 = inverseH[6], h7 = inverseH[7], h8 = inverseH[8];

  final maxSX = src.width - 1.0;
  final maxSY = src.height - 1.0;

  for (int dy = 0; dy < dstH; dy++) {
    for (int dx = 0; dx < dstW; dx++) {
      final wx = h0 * dx + h1 * dy + h2;
      final wy = h3 * dx + h4 * dy + h5;
      final wz = h6 * dx + h7 * dy + h8;
      final sx = wx / wz;
      final sy = wy / wz;

      if (sx < 0 || sy < 0 || sx > maxSX || sy > maxSY) continue;

      final x0 = sx.floor();
      final y0 = sy.floor();
      final x1 = math.min(x0 + 1, src.width - 1);
      final y1 = math.min(y0 + 1, src.height - 1);
      final fx = sx - x0;
      final fy = sy - y0;

      final p00 = src.getPixel(x0, y0);
      final p10 = src.getPixel(x1, y0);
      final p01 = src.getPixel(x0, y1);
      final p11 = src.getPixel(x1, y1);

      final r = _bl(p00.r, p10.r, p01.r, p11.r, fx, fy);
      final g = _bl(p00.g, p10.g, p01.g, p11.g, fx, fy);
      final b = _bl(p00.b, p10.b, p01.b, p11.b, fx, fy);

      dst.setPixel(
          dx, dy, img.ColorRgba8(r.round(), g.round(), b.round(), 255));
    }
  }
  return dst;
}

double _bl(num a, num b, num c, num d, double fx, double fy) =>
    a * (1 - fx) * (1 - fy) +
    b * fx * (1 - fy) +
    c * (1 - fx) * fy +
    d * fx * fy;

// ── Reprojection error ────────────────────────────────

double _reprojError(List<double> H, List<Offset> src, List<Offset> dst) {
  double total = 0;
  for (int i = 0; i < src.length; i++) {
    final x = src[i].dx, y = src[i].dy;
    final wz = H[6] * x + H[7] * y + H[8];
    final px = (H[0] * x + H[1] * y + H[2]) / wz;
    final py = (H[3] * x + H[4] * y + H[5]) / wz;
    final ex = px - dst[i].dx, ey = py - dst[i].dy;
    total += math.sqrt(ex * ex + ey * ey);
  }
  return total / src.length;
}
