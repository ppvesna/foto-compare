import 'dart:io';
import 'dart:typed_data';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

// Номинальная ширина каждого формата при 100% масштабе, в мм (GS1 / ISO стандарты)
// X-dimension (ширина тонкого штриха) при 100%:
//   EAN-13 / UPC-A: X = 0.330mm, итого ширина = 37.29mm
//   EAN-8:           X = 0.330mm, итого ширина = 26.73mm
//   Code 128:        X = 0.250mm (типовой), минимальная высота = 15% длины
//   QR Code v1:      21 модулей × 0.350mm = 7.35mm (с тихой зоной ~10mm)
//
// При разрешении 300 DPI: 1mm = 11.81px
// Храним номинальную ширину в пикселях при 300 DPI (стандартная печать)
class _FormatSpec {
  final double nominalWidthMm;  // ширина при 100% в мм
  final double minPct;          // минимальный допустимый % (GS1)
  final double maxPct;          // максимальный допустимый % (GS1)
  const _FormatSpec(this.nominalWidthMm, this.minPct, this.maxPct);
}

const _specs = {
  'EAN-13':    _FormatSpec(37.29, 80, 200),
  'EAN-8':     _FormatSpec(26.73, 80, 200),
  'UPC-A':     _FormatSpec(37.29, 80, 200),
  'UPC-E':     _FormatSpec(22.11, 80, 200),
  'Code 128':  _FormatSpec(30.00, 80, 200),
  'Code 39':   _FormatSpec(30.00, 75, 200),
  'Code 93':   _FormatSpec(25.00, 75, 200),
  'ITF':       _FormatSpec(32.00, 62, 200),
  'Codabar':   _FormatSpec(28.00, 80, 200),
  'QR Code':   _FormatSpec(10.00, 80, 400),  // минимальный QR v1
  'DataMatrix': _FormatSpec(8.00, 80, 400),
  'PDF417':    _FormatSpec(28.00, 75, 200),
  'Aztec':     _FormatSpec(8.00,  80, 400),
};

const _dpi300px = 11.811; // px на мм при 300 DPI

class BarcodeResult {
  final String value;
  final String displayFormat;
  final int    widthPx;       // реальная ширина в пикселях на фото
  final int    heightPx;
  final double scalePct;      // % от номинала 100% (при 300 DPI)
  final double minPct;        // минимальный допустимый %
  final double maxPct;

  const BarcodeResult({
    required this.value,
    required this.displayFormat,
    required this.widthPx,
    required this.heightPx,
    required this.scalePct,
    required this.minPct,
    required this.maxPct,
  });

  // Оценка: в норме ли масштаб
  String get scaleVerdict {
    if (scalePct < minPct)  return 'мелкий — трудно сканировать';
    if (scalePct > maxPct)  return 'слишком крупный';
    if (scalePct < minPct + 10) return 'на пределе минимума';
    return 'норма';
  }

  int get verdictColor {
    if (scalePct < minPct)       return 0xFFC82020; // красный
    if (scalePct < minPct + 10)  return 0xFFC8A020; // жёлтый
    if (scalePct > maxPct)       return 0xFFC8A020; // жёлтый
    return 0xFF3A8C2F;                               // зелёный
  }
}

class BarcodeService {
  static final _formatNames = {
    BarcodeFormat.qrCode:     'QR Code',
    BarcodeFormat.ean13:      'EAN-13',
    BarcodeFormat.ean8:       'EAN-8',
    BarcodeFormat.code128:    'Code 128',
    BarcodeFormat.code39:     'Code 39',
    BarcodeFormat.code93:     'Code 93',
    BarcodeFormat.dataMatrix: 'DataMatrix',
    BarcodeFormat.pdf417:     'PDF417',
    BarcodeFormat.aztec:      'Aztec',
    BarcodeFormat.itf:        'ITF',
    BarcodeFormat.upcA:       'UPC-A',
    BarcodeFormat.upcE:       'UPC-E',
    BarcodeFormat.codabar:    'Codabar',
  };

  static Future<List<BarcodeResult>> scanImage(Uint8List bytes) async {
    File? tmp;
    MobileScannerController? controller;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(bytes);

      controller = MobileScannerController(formats: BarcodeFormat.all);
      final result = await controller.analyzeImage(tmp.path);
      if (result == null || result.barcodes.isEmpty) return [];

      final imgW = result.image?.width.toDouble()  ?? 1;
      final imgH = result.image?.height.toDouble() ?? 1;

      return result.barcodes
          .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
          .map((b) {
            final fmt = _formatNames[b.format] ?? b.format.name;
            int w = 0, h = 0;

            final corners = b.corners;
            if (corners != null && corners.length >= 4) {
              final xs = corners.map((c) => c.dx);
              final ys = corners.map((c) => c.dy);
              w = (xs.reduce((a, b) => a > b ? a : b) -
                   xs.reduce((a, b) => a < b ? a : b)).round().abs();
              h = (ys.reduce((a, b) => a > b ? a : b) -
                   ys.reduce((a, b) => a < b ? a : b)).round().abs();
            }

            // Рассчитываем масштаб относительно 100% при 300 DPI
            // Предполагаем, что фото сделано так, что штрихкод занимает
            // пропорциональную часть кадра — нормируем по ширине изображения
            final spec = _specs[fmt];
            double scalePct = 0;
            if (spec != null && w > 0) {
              // номинальная ширина в пикселях при 300 DPI
              final nominalPx = spec.nominalWidthMm * _dpi300px;
              // Если изображение шире 2000px — это полноразмерное фото,
              // масштаб считаем напрямую
              // Иначе нормируем к стандартной ширине фото (3000px ≈ 10")
              final refWidth = imgW > 1000 ? imgW : 3000.0;
              final scaleFactor = refWidth / 3000.0;
              scalePct = (w / (nominalPx * scaleFactor)) * 100;
            }

            return BarcodeResult(
              value: b.rawValue!,
              displayFormat: fmt,
              widthPx: w,
              heightPx: h,
              scalePct: scalePct.clamp(0, 999),
              minPct: spec?.minPct ?? 80,
              maxPct: spec?.maxPct ?? 200,
            );
          })
          .toList();
    } catch (_) {
      return [];
    } finally {
      await controller?.dispose();
      await tmp?.delete().catchError((_) {});
    }
  }
}
