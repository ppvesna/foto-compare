import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Offset;
import 'package:image/image.dart' as img;

const int _kMaxDim = 900;

/// Pure-Dart fallback for alignByAnchors (web / no OpenCV).
/// Computes homography via normalised DLT, then warps srcBytes → ref space.
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

  // Work at reduced resolution
  final refScale = _kMaxDim / math.max(refW, refH);
  final srcScale = _kMaxDim / math.max(srcW, srcH);

  final refResW = (refW * refScale).round();
  final refResH = (refH * refScale).round();

  // Scale anchor points to resized image coordinates
  final scaledRef = refPoints
      .map((p) => Offset(p.dx * refScale, p.dy * refScale))
      .toList();
  final scaledSrc = srcPoints
      .map((p) => Offset(p.dx * srcScale, p.dy * srcScale))
      .toList();

  // Homography maps src coords → ref coords
  final H = _computeHomography(scaledSrc, scaledRef);
  if (H == null) return null;

  // Resize source for warping
  final srcResized = img.copyResize(srcImg,
      width: (srcW * srcScale).round(),
      height: (srcH * srcScale).round());

  // Warp (RGBA — альфа=0 у пикселей, не покрытых исходником, чтобы дальше
  // их можно было исключить из сравнения, а не считать чёрным отличием)
  final warped = _warpPerspective(srcResized, H, refResW, refResH);
  final warpedBytes = Uint8List.fromList(img.encodePng(warped));

  final reproj = _reprojError(H, scaledSrc, scaledRef);

  return DartAlignResult(
    alignedBytes: warpedBytes,
    homography: H,
    reprojError: reproj,
  );
}

class DartAlignResult {
  final Uint8List alignedBytes;
  final List<double> homography; // 9-element row-major 3×3
  final double reprojError;
  const DartAlignResult({
    required this.alignedBytes,
    required this.homography,
    required this.reprojError,
  });
}

// ── DLT Homography ───────────────────────────────────

List<double>? _computeHomography(
    List<Offset> srcPts, List<Offset> dstPts) {
  if (srcPts.length < 4) return null;

  final sn = _normalizePoints(srcPts);
  final dn = _normalizePoints(dstPts);

  final n = srcPts.length;
  final rows = 2 * n;
  final A = List.generate(rows, (_) => List.filled(8, 0.0));
  final b = List.filled(rows, 0.0);

  for (int i = 0; i < n; i++) {
    final x = sn.pts[i].dx, y = sn.pts[i].dy;
    final u = dn.pts[i].dx, v = dn.pts[i].dy;
    final r1 = 2 * i, r2 = 2 * i + 1;
    A[r1] = [x, y, 1, 0, 0, 0, -u * x, -u * y];
    b[r1] = u;
    A[r2] = [0, 0, 0, x, y, 1, -v * x, -v * y];
    b[r2] = v;
  }

  // Normal equations: (A^T A) h = A^T b
  final AtA = List.generate(8, (_) => List.filled(8, 0.0));
  final Atb = List.filled(8, 0.0);
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < 8; j++) {
      Atb[j] += A[i][j] * b[i];
      for (int k = 0; k < 8; k++) {
        AtA[j][k] += A[i][j] * A[i][k];
      }
    }
  }

  final h = _solveLinear(AtA, Atb);
  if (h == null) return null;

  final Hn = [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0];
  return _denormalize(Hn, sn.T, dn.T);
}

class _Norm {
  final List<Offset> pts;
  final List<double> T; // 3×3 row-major normalization transform
  const _Norm(this.pts, this.T);
}

_Norm _normalizePoints(List<Offset> pts) {
  double cx = 0, cy = 0;
  for (final p in pts) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= pts.length;
  cy /= pts.length;

  double dist = 0;
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    dist += math.sqrt(dx * dx + dy * dy);
  }
  dist /= pts.length;
  final s = dist < 1e-10 ? 1.0 : math.sqrt(2) / dist;

  final norm = pts
      .map((p) => Offset((p.dx - cx) * s, (p.dy - cy) * s))
      .toList();

  return _Norm(norm, [s, 0.0, -cx * s, 0.0, s, -cy * s, 0.0, 0.0, 1.0]);
}

List<double> _denormalize(
    List<double> Hn, List<double> Tsrc, List<double> Tdst) {
  return _mm(_invertH(Tdst), _mm(Hn, Tsrc));
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
    for (int j = i + 1; j < n; j++) x[i] -= M[i][j] * x[j];
    x[i] /= M[i][i];
  }
  return x;
}

List<double> _mm(List<double> A, List<double> B) {
  final C = List.filled(9, 0.0);
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      for (int k = 0; k < 3; k++) {
        C[i * 3 + j] += A[i * 3 + k] * B[k * 3 + j];
      }
    }
  }
  return C;
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
  final Hv = -(a * f - c * d);
  final I = a * e - b * d;

  final det = a * A + b * B + c * C;
  if (det.abs() < 1e-12) return List.filled(9, 0.0);

  return [
    A / det, D / det, G / det,
    B / det, E / det, Hv / det,
    C / det, F / det, I / det,
  ];
}

// ── Perspective warp (inverse mapping + bilinear) ────

img.Image _warpPerspective(
    img.Image src, List<double> H, int dstW, int dstH) {
  final Hi = _invertH(H);
  // numChannels: 4 — непокрытые пиксели остаются alpha=0 (нет данных)
  final dst = img.Image(width: dstW, height: dstH, numChannels: 4);

  final h0 = Hi[0], h1 = Hi[1], h2 = Hi[2];
  final h3 = Hi[3], h4 = Hi[4], h5 = Hi[5];
  final h6 = Hi[6], h7 = Hi[7], h8 = Hi[8];

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

      dst.setPixel(dx, dy, img.ColorRgba8(r.round(), g.round(), b.round(), 255));
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

double _reprojError(
    List<double> H, List<Offset> src, List<Offset> dst) {
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
