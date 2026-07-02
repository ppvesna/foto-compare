import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class LabFingerprintService {
  static Future<LabFingerprint?> create(Uint8List bytes) async {
    final data = await compute(_buildLabFingerprint, bytes);
    if (data == null) return null;
    return LabFingerprint.fromJson(data);
  }

  static double matchScore(LabFingerprint? a, LabFingerprint? b) {
    if (a == null || b == null || a.signature.isEmpty || b.signature.isEmpty) {
      return 0;
    }
    final n = math.min(a.signature.length, b.signature.length);
    double diff = 0;
    for (int i = 0; i < n; i++) {
      diff += (a.signature[i] - b.signature[i]).abs();
    }
    final avg = diff / n;
    return (100 - avg * 2.2).clamp(0, 100).toDouble();
  }
}

class LabFingerprint {
  final String labId;
  final String globalHash;
  final String zoneHash;
  final String detailHash;
  final int width;
  final int height;
  final int grid;
  final List<double> signature;

  const LabFingerprint({
    required this.labId,
    required this.globalHash,
    required this.zoneHash,
    required this.detailHash,
    required this.width,
    required this.height,
    required this.grid,
    required this.signature,
  });

  factory LabFingerprint.fromJson(Map<String, dynamic> json) {
    return LabFingerprint(
      labId: json['labId'] as String,
      globalHash: json['globalHash'] as String,
      zoneHash: json['zoneHash'] as String,
      detailHash: json['detailHash'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      grid: (json['grid'] as num).toInt(),
      signature: (json['signature'] as List)
          .map((v) => (v as num).toDouble())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'labId': labId,
        'globalHash': globalHash,
        'zoneHash': zoneHash,
        'detailHash': detailHash,
        'width': width,
        'height': height,
        'grid': grid,
        'signature': signature,
      };
}

Map<String, dynamic>? _buildLabFingerprint(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  const grid = 9;
  const size = 216;
  final src = img.copyResize(
    decoded,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );

  final labs = List.generate(size * size, (i) {
    final p = src.getPixel(i % size, i ~/ size);
    return _rgbToLab(p);
  });

  double sumL = 0, sumA = 0, sumB = 0;
  for (final lab in labs) {
    sumL += lab.l;
    sumA += lab.a;
    sumB += lab.b;
  }
  final count = labs.length;
  final meanL = sumL / count;
  final meanA = sumA / count;
  final meanB = sumB / count;

  double varianceL = 0;
  for (final lab in labs) {
    final d = lab.l - meanL;
    varianceL += d * d;
  }
  final stdL = math.sqrt(varianceL / count);

  final signature = <double>[
    _q(meanL),
    _q(meanA),
    _q(meanB),
    _q(stdL),
  ];
  final zoneParts = <String>[];
  final detailParts = <String>[];
  const cell = size ~/ grid;
  for (int gy = 0; gy < grid; gy++) {
    for (int gx = 0; gx < grid; gx++) {
      double l = 0, a = 0, b = 0;
      int n = 0;
      for (int y = gy * cell; y < (gy + 1) * cell; y++) {
        for (int x = gx * cell; x < (gx + 1) * cell; x++) {
          final lab = labs[y * size + x];
          l += lab.l;
          a += lab.a;
          b += lab.b;
          n++;
        }
      }
      final zl = l / n;
      final za = a / n;
      final zb = b / n;
      signature.addAll([_q(zl), _q(za), _q(zb)]);
      zoneParts.add('${_qi(zl)}:${_qi(za)}:${_qi(zb)}');

      double edge = 0;
      for (int y = gy * cell + 1; y < (gy + 1) * cell; y++) {
        for (int x = gx * cell + 1; x < (gx + 1) * cell; x++) {
          final cur = labs[y * size + x];
          final left = labs[y * size + x - 1];
          final up = labs[(y - 1) * size + x];
          edge += (cur.l - left.l).abs() + (cur.l - up.l).abs();
        }
      }
      detailParts.add(_qi(edge / (cell * cell)).toString());
    }
  }

  final globalText = '${_qi(meanL)}:${_qi(meanA)}:${_qi(meanB)}:${_qi(stdL)}';
  final globalHash = _stableHash(globalText);
  final zoneHash = _stableHash(zoneParts.join('|'));
  final detailHash = _stableHash(detailParts.join('|'));
  final labId = _stableHash('$globalHash|$zoneHash|$detailHash|$grid|$size');

  return {
    'labId': labId,
    'globalHash': globalHash,
    'zoneHash': zoneHash,
    'detailHash': detailHash,
    'width': decoded.width,
    'height': decoded.height,
    'grid': grid,
    'signature': signature,
  };
}

({double l, double a, double b}) _rgbToLab(img.Pixel p) {
  final r = _pivotRgb(p.r);
  final g = _pivotRgb(p.g);
  final b = _pivotRgb(p.b);
  final x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
  final y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750);
  final z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;
  final fx = _pivotXyz(x);
  final fy = _pivotXyz(y);
  final fz = _pivotXyz(z);
  return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz));
}

double _pivotRgb(num v) {
  final c = v / 255.0;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

double _pivotXyz(double v) {
  return v > 0.008856 ? math.pow(v, 1 / 3) as double : (7.787 * v) + 16 / 116;
}

double _q(double value) => double.parse(value.toStringAsFixed(1));

int _qi(double value) => (value * 10).round();

String _stableHash(String text) {
  final a = _fnv32(text, 0x811c9dc5);
  final b = _fnv32(text, 0x01000193);
  return '${a.toRadixString(16).padLeft(8, '0')}'
      '${b.toRadixString(16).padLeft(8, '0')}';
}

int _fnv32(String text, int seed) {
  var hash = seed & 0xffffffff;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}
