import 'dart:math' as math;

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class AnchorRefinementService {
  static Future<Offset> refine(Uint8List bytes, Offset roughPoint) async {
    final result = await compute(_refineAnchorPoint, {
      'bytes': bytes,
      'x': roughPoint.dx,
      'y': roughPoint.dy,
    });
    if (result == null) return roughPoint;
    return Offset(result['x']!, result['y']!);
  }
}

Map<String, double>? _refineAnchorPoint(Map<String, dynamic> args) {
  final decoded = img.decodeImage(args['bytes'] as Uint8List);
  if (decoded == null) return null;

  var center = (
    x: (args['x'] as double).clamp(0.0, decoded.width - 1.0),
    y: (args['y'] as double).clamp(0.0, decoded.height - 1.0),
  );

  // 1) Coarse 3x3 matrix around the user's click.
  // 2) Pixel-level refinement in a small local window.
  center = _refineByGrid3(decoded, center.x, center.y, 72.0);
  center =
      _refineInWindow(decoded, center.x, center.y, 14.0, maxJumpFactor: 0.32);

  return {'x': center.x, 'y': center.y};
}

({double x, double y}) _refineByGrid3(
  img.Image image,
  double centerX,
  double centerY,
  double window,
) {
  final half = window / 2;
  final left = math.max(1, (centerX - half).floor());
  final top = math.max(1, (centerY - half).floor());
  final right = math.min(image.width - 2, (centerX + half).ceil());
  final bottom = math.min(image.height - 2, (centerY + half).ceil());
  if (right <= left || bottom <= top) return (x: centerX, y: centerY);

  final cellW = (right - left + 1) / 3;
  final cellH = (bottom - top + 1) / 3;
  double bestScore = -1;
  var bestCell = (cx: centerX, cy: centerY);

  for (int gy = 0; gy < 3; gy++) {
    for (int gx = 0; gx < 3; gx++) {
      final x0 = (left + gx * cellW).round();
      final y0 = (top + gy * cellH).round();
      final x1 = (left + (gx + 1) * cellW).round().clamp(left + 1, right);
      final y1 = (top + (gy + 1) * cellH).round().clamp(top + 1, bottom);
      final score = _cellContrast(image, x0, y0, x1, y1);
      if (score > bestScore) {
        bestScore = score;
        bestCell = (cx: (x0 + x1) / 2, cy: (y0 + y1) / 2);
      }
    }
  }

  // Do not let a neighbouring high-contrast area steal the anchor.
  final maxJump = math.min(cellW, cellH) * 0.85;
  return (
    x: (centerX + (bestCell.cx - centerX).clamp(-maxJump, maxJump))
        .clamp(0.0, image.width - 1.0),
    y: (centerY + (bestCell.cy - centerY).clamp(-maxJump, maxJump))
        .clamp(0.0, image.height - 1.0),
  );
}

double _cellContrast(
    img.Image image, int left, int top, int right, int bottom) {
  double sum = 0;
  int count = 0;
  for (int y = top + 1; y < bottom - 1; y++) {
    for (int x = left + 1; x < right - 1; x++) {
      final gx =
          _luma(image.getPixel(x + 1, y)) - _luma(image.getPixel(x - 1, y));
      final gy =
          _luma(image.getPixel(x, y + 1)) - _luma(image.getPixel(x, y - 1));
      sum += gx.abs() + gy.abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}

({double x, double y}) _refineInWindow(
    img.Image image, double centerX, double centerY, double window,
    {double maxJumpFactor = 0.55}) {
  final half = window / 2;
  final left = math.max(1, (centerX - half).floor());
  final top = math.max(1, (centerY - half).floor());
  final right = math.min(image.width - 2, (centerX + half).ceil());
  final bottom = math.min(image.height - 2, (centerY + half).ceil());
  if (right <= left || bottom <= top) return (x: centerX, y: centerY);

  final gradients = <({int x, int y, double g})>[];
  double maxGradient = 0;

  for (int y = top; y <= bottom; y++) {
    for (int x = left; x <= right; x++) {
      final gx =
          _luma(image.getPixel(x + 1, y)) - _luma(image.getPixel(x - 1, y));
      final gy =
          _luma(image.getPixel(x, y + 1)) - _luma(image.getPixel(x, y - 1));
      final g = gx.abs() + gy.abs();
      if (g > maxGradient) maxGradient = g;
      gradients.add((x: x, y: y, g: g));
    }
  }

  if (maxGradient < 8) return (x: centerX, y: centerY);

  final threshold = maxGradient * 0.42;
  var minX = right;
  var maxX = left;
  var minY = bottom;
  var maxY = top;
  double weight = 0;
  double sumX = 0;
  double sumY = 0;

  for (final p in gradients) {
    if (p.g < threshold) continue;
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
    weight += p.g;
    sumX += p.x * p.g;
    sumY += p.y * p.g;
  }

  if (weight == 0) return (x: centerX, y: centerY);

  final boxCenterX = (minX + maxX) / 2;
  final boxCenterY = (minY + maxY) / 2;
  final gradientCenterX = sumX / weight;
  final gradientCenterY = sumY / weight;

  final nextX = boxCenterX * 0.65 + gradientCenterX * 0.35;
  final nextY = boxCenterY * 0.65 + gradientCenterY * 0.35;
  final maxJump = half * maxJumpFactor;

  return (
    x: (centerX + (nextX - centerX).clamp(-maxJump, maxJump))
        .clamp(0.0, image.width - 1.0),
    y: (centerY + (nextY - centerY).clamp(-maxJump, maxJump))
        .clamp(0.0, image.height - 1.0),
  );
}

double _luma(img.Pixel p) => p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
