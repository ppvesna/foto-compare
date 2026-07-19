import 'dart:math' as math;

import 'package:image/image.dart' as img;

enum DeltaEFormula {
  cie76,
  cie94GraphicArts,
  ciede2000,
  cmc21,
}

extension DeltaEFormulaLabel on DeltaEFormula {
  String get label => switch (this) {
        DeltaEFormula.cie76 => 'CIE 1976',
        DeltaEFormula.cie94GraphicArts => 'CIE 1994 Graphic Arts',
        DeltaEFormula.ciede2000 => 'CIEDE2000',
        DeltaEFormula.cmc21 => 'CMC 2:1',
      };

  String get shortLabel => switch (this) {
        DeltaEFormula.cie76 => 'ΔE*76',
        DeltaEFormula.cie94GraphicArts => 'ΔE*94',
        DeltaEFormula.ciede2000 => 'ΔE00',
        DeltaEFormula.cmc21 => 'ΔE CMC 2:1',
      };
}

enum MeasurementAperture { mm2, mm5 }

extension MeasurementApertureLabel on MeasurementAperture {
  double get diameterMm => switch (this) {
        MeasurementAperture.mm2 => 2,
        MeasurementAperture.mm5 => 5,
      };

  String get label => '${diameterMm.toStringAsFixed(0)} мм';
}

class ColorMeasurementSettings {
  final DeltaEFormula deltaEFormula;
  final MeasurementAperture aperture;

  const ColorMeasurementSettings({
    required this.deltaEFormula,
    required this.aperture,
  });

  static const defaults = ColorMeasurementSettings(
    deltaEFormula: DeltaEFormula.cie76,
    aperture: MeasurementAperture.mm2,
  );

  ColorMeasurementSettings copyWith({
    DeltaEFormula? deltaEFormula,
    MeasurementAperture? aperture,
  }) {
    return ColorMeasurementSettings(
      deltaEFormula: deltaEFormula ?? this.deltaEFormula,
      aperture: aperture ?? this.aperture,
    );
  }
}

class LabColor {
  final double l;
  final double a;
  final double b;

  const LabColor(this.l, this.a, this.b);
}

class PointColorMeasurement {
  final LabColor lab;
  final double red;
  final double green;
  final double blue;
  final int sampledPixels;

  const PointColorMeasurement({
    required this.lab,
    required this.red,
    required this.green,
    required this.blue,
    required this.sampledPixels,
  });
}

class ColorMeasurementEngine {
  const ColorMeasurementEngine._();

  static LabColor pixelToLab(
    img.Pixel pixel,
  ) {
    return rgbToLab(
      pixel.r.toDouble(),
      pixel.g.toDouble(),
      pixel.b.toDouble(),
    );
  }

  static LabColor rgbToLab(
    double red,
    double green,
    double blue,
  ) {
    final r = _pivotRgb(red);
    final g = _pivotRgb(green);
    final b = _pivotRgb(blue);
    var x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375;
    var y = r * 0.2126729 + g * 0.7151522 + b * 0.0721750;
    var z = r * 0.0193339 + g * 0.1191920 + b * 0.9503041;

    const targetWhite = (0.95047, 1.0, 1.08883);
    final fx = _pivotXyz(x / targetWhite.$1);
    final fy = _pivotXyz(y / targetWhite.$2);
    final fz = _pivotXyz(z / targetWhite.$3);
    return LabColor(
      116 * fy - 16,
      500 * (fx - fy),
      200 * (fy - fz),
    );
  }

  static PointColorMeasurement measurePoint(
    img.Image image, {
    required int x,
    required int y,
    required ColorMeasurementSettings settings,
    required double pixelsPerMm,
  }) {
    final radius = math.max(
      0.5,
      settings.aperture.diameterMm * pixelsPerMm / 2,
    );
    final radiusSquared = radius * radius;
    final minX = math.max(0, (x - radius).floor());
    final maxX = math.min(image.width - 1, (x + radius).ceil());
    final minY = math.max(0, (y - radius).floor());
    final maxY = math.min(image.height - 1, (y + radius).ceil());
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var l = 0.0;
    var a = 0.0;
    var b = 0.0;
    var count = 0;

    for (var py = minY; py <= maxY; py++) {
      final dy = py - y;
      for (var px = minX; px <= maxX; px++) {
        final dx = px - x;
        if (dx * dx + dy * dy > radiusSquared) continue;
        final pixel = image.getPixel(px, py);
        if (pixel.a < 250) continue;
        final lab = pixelToLab(pixel);
        red += pixel.r;
        green += pixel.g;
        blue += pixel.b;
        l += lab.l;
        a += lab.a;
        b += lab.b;
        count++;
      }
    }

    if (count == 0) {
      final pixel = image.getPixel(
        x.clamp(0, image.width - 1),
        y.clamp(0, image.height - 1),
      );
      final lab = pixelToLab(pixel);
      return PointColorMeasurement(
        lab: lab,
        red: pixel.r.toDouble(),
        green: pixel.g.toDouble(),
        blue: pixel.b.toDouble(),
        sampledPixels: 1,
      );
    }

    return PointColorMeasurement(
      lab: LabColor(l / count, a / count, b / count),
      red: red / count,
      green: green / count,
      blue: blue / count,
      sampledPixels: count,
    );
  }

  static double _pivotRgb(double value) {
    final c = value / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _pivotXyz(double value) => value > 0.008856
      ? math.pow(value, 1 / 3).toDouble()
      : 7.787 * value + 16 / 116;
}

class ColorDifferenceCalculator {
  const ColorDifferenceCalculator._();

  static double deltaE(
    LabColor first,
    LabColor second,
    DeltaEFormula formula,
  ) {
    return switch (formula) {
      DeltaEFormula.cie76 => _cie76(first, second),
      DeltaEFormula.cie94GraphicArts => _cie94(first, second),
      DeltaEFormula.ciede2000 => _ciede2000(first, second),
      DeltaEFormula.cmc21 => _cmc(first, second),
    };
  }

  static double deltaEForPixels(
    img.Pixel first,
    img.Pixel second, {
    required DeltaEFormula formula,
  }) {
    return deltaE(
      ColorMeasurementEngine.pixelToLab(first),
      ColorMeasurementEngine.pixelToLab(second),
      formula,
    );
  }

  static double _cie76(LabColor x, LabColor y) {
    final dl = x.l - y.l;
    final da = x.a - y.a;
    final db = x.b - y.b;
    return math.sqrt(dl * dl + da * da + db * db);
  }

  static double _cie94(LabColor x, LabColor y) {
    final dl = x.l - y.l;
    final c1 = math.sqrt(x.a * x.a + x.b * x.b);
    final c2 = math.sqrt(y.a * y.a + y.b * y.b);
    final dc = c1 - c2;
    final da = x.a - y.a;
    final db = x.b - y.b;
    final dh2 = math.max(0.0, da * da + db * db - dc * dc);
    final sc = 1 + 0.045 * c1;
    final sh = 1 + 0.015 * c1;
    return math.sqrt(dl * dl + (dc / sc) * (dc / sc) + dh2 / (sh * sh));
  }

  static double _ciede2000(LabColor x, LabColor y) {
    final c1 = math.sqrt(x.a * x.a + x.b * x.b);
    final c2 = math.sqrt(y.a * y.a + y.b * y.b);
    final cBar = (c1 + c2) / 2;
    final cBar7 = math.pow(cBar, 7).toDouble();
    final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + 6103515625)));
    final a1p = (1 + g) * x.a;
    final a2p = (1 + g) * y.a;
    final c1p = math.sqrt(a1p * a1p + x.b * x.b);
    final c2p = math.sqrt(a2p * a2p + y.b * y.b);
    final h1p = _hueDegrees(x.b, a1p);
    final h2p = _hueDegrees(y.b, a2p);
    final dlp = y.l - x.l;
    final dcp = c2p - c1p;
    var dhp = h2p - h1p;
    if (c1p * c2p == 0) {
      dhp = 0;
    } else if (dhp > 180) {
      dhp -= 360;
    } else if (dhp < -180) {
      dhp += 360;
    }
    final dhTerm = 2 * math.sqrt(c1p * c2p) * _sinDegrees(dhp / 2);
    final lp = (x.l + y.l) / 2;
    final cp = (c1p + c2p) / 2;
    double hp;
    if (c1p * c2p == 0) {
      hp = h1p + h2p;
    } else if ((h1p - h2p).abs() <= 180) {
      hp = (h1p + h2p) / 2;
    } else if (h1p + h2p < 360) {
      hp = (h1p + h2p + 360) / 2;
    } else {
      hp = (h1p + h2p - 360) / 2;
    }
    final t = 1 -
        0.17 * _cosDegrees(hp - 30) +
        0.24 * _cosDegrees(2 * hp) +
        0.32 * _cosDegrees(3 * hp + 6) -
        0.20 * _cosDegrees(4 * hp - 63);
    final sl =
        1 + 0.015 * math.pow(lp - 50, 2) / math.sqrt(20 + math.pow(lp - 50, 2));
    final sc = 1 + 0.045 * cp;
    final sh = 1 + 0.015 * cp * t;
    final deltaTheta = 30 * math.exp(-math.pow((hp - 275) / 25, 2));
    final cp7 = math.pow(cp, 7).toDouble();
    final rc = 2 * math.sqrt(cp7 / (cp7 + 6103515625));
    final rt = -rc * _sinDegrees(2 * deltaTheta);
    final lTerm = dlp / sl;
    final cTerm = dcp / sc;
    final hTerm = dhTerm / sh;
    return math.sqrt(
      lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rt * cTerm * hTerm,
    );
  }

  static double _cmc(LabColor x, LabColor y) {
    final dl = x.l - y.l;
    final c1 = math.sqrt(x.a * x.a + x.b * x.b);
    final c2 = math.sqrt(y.a * y.a + y.b * y.b);
    final dc = c1 - c2;
    final da = x.a - y.a;
    final db = x.b - y.b;
    final dh2 = math.max(0.0, da * da + db * db - dc * dc);
    final h1 = _hueDegrees(x.b, x.a);
    final f = math.sqrt(math.pow(c1, 4) / (math.pow(c1, 4) + 1900));
    final t = h1 >= 164 && h1 <= 345
        ? 0.56 + (0.2 * _cosDegrees(h1 + 168)).abs()
        : 0.36 + (0.4 * _cosDegrees(h1 + 35)).abs();
    final sl = x.l < 16 ? 0.511 : 0.040975 * x.l / (1 + 0.01765 * x.l);
    final sc = 0.0638 * c1 / (1 + 0.0131 * c1) + 0.638;
    final sh = sc * (f * t + 1 - f);
    return math.sqrt(
      math.pow(dl / (2 * sl), 2) + math.pow(dc / sc, 2) + dh2 / (sh * sh),
    );
  }

  static double _hueDegrees(double b, double a) {
    final value = math.atan2(b, a) * 180 / math.pi;
    return value < 0 ? value + 360 : value;
  }

  static double _sinDegrees(double degrees) =>
      math.sin(degrees * math.pi / 180);

  static double _cosDegrees(double degrees) =>
      math.cos(degrees * math.pi / 180);
}
