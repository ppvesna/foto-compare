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

  final original = center;

  // Мягкий магнит: работаем только по чёрно-белому контрасту рядом с кликом.
  // Дальние 3x3-прыжки отключены: они могли увести точку на соседнюю деталь.
  center =
      _refineInWindow(decoded, center.x, center.y, 24.0, maxJumpFactor: 0.46);
  center =
      _refineInWindow(decoded, center.x, center.y, 10.0, maxJumpFactor: 0.40);

  center = _limitShift(
    original.x,
    original.y,
    center.x,
    center.y,
    maxShift: 7.0,
  );

  return {'x': center.x, 'y': center.y};
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

({double x, double y}) _limitShift(
  double originalX,
  double originalY,
  double nextX,
  double nextY, {
  required double maxShift,
}) {
  final dx = nextX - originalX;
  final dy = nextY - originalY;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance <= maxShift || distance == 0) return (x: nextX, y: nextY);
  final k = maxShift / distance;
  return (x: originalX + dx * k, y: originalY + dy * k);
}

double _luma(img.Pixel p) => p.r * 0.299 + p.g * 0.587 + p.b * 0.114;
