import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:path_provider/path_provider.dart';

class _FormatSpec {
  final double nominalWidthMm;
  final double minPct;
  final double maxPct;
  const _FormatSpec(this.nominalWidthMm, this.minPct, this.maxPct);
}

const _specs = {
  'EAN-13':     _FormatSpec(37.29, 80, 200),
  'EAN-8':      _FormatSpec(26.73, 80, 200),
  'UPC-A':      _FormatSpec(37.29, 80, 200),
  'UPC-E':      _FormatSpec(22.11, 80, 200),
  'Code 128':   _FormatSpec(30.00, 80, 200),
  'Code 39':    _FormatSpec(30.00, 75, 200),
  'Code 93':    _FormatSpec(25.00, 75, 200),
  'ITF':        _FormatSpec(32.00, 62, 200),
  'Codabar':    _FormatSpec(28.00, 80, 200),
  'QR Code':    _FormatSpec(10.00, 80, 400),
  'DataMatrix': _FormatSpec(8.00,  80, 400),
  'PDF417':     _FormatSpec(28.00, 75, 200),
  'Aztec':      _FormatSpec(8.00,  80, 400),
};

const _dpi300px = 11.811;

class BarcodeResult {
  final String value;
  final String displayFormat;
  final int    widthPx;
  final int    heightPx;
  final double scalePct;
  final double minPct;
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

  String get scaleVerdict {
    if (scalePct <= 0)           return 'масштаб не определён';
    if (scalePct < minPct)       return 'мелкий — трудно сканировать';
    if (scalePct > maxPct)       return 'слишком крупный';
    if (scalePct < minPct + 10)  return 'на пределе минимума';
    return 'норма';
  }

  int get verdictColor {
    if (scalePct <= 0)            return 0xFF808080;
    if (scalePct < minPct)        return 0xFFC82020;
    if (scalePct < minPct + 10)   return 0xFFC8A020;
    if (scalePct > maxPct)        return 0xFFC8A020;
    return 0xFF3A8C2F;
  }
}

class BarcodeService {
  static const _fmtNames = {
    BarcodeType.unknown:    'Unknown',
    BarcodeType.url:        'URL',
    BarcodeType.text:       'Text',
    BarcodeType.email:      'Email',
    BarcodeType.phone:      'Phone',
    BarcodeType.sms:        'SMS',
    BarcodeType.wifi:       'WiFi',
    BarcodeType.geoCoordinates: 'GeoPoint',
    BarcodeType.contactInfo:    'Contact',
    BarcodeType.calendarEvent:  'Calendar',
    BarcodeType.driverLicense:  'License',
    BarcodeType.isbn:       'ISBN',
    BarcodeType.product:    'Product',
  };

  static String _formatName(Barcode b) {
    // Определяем формат по rawFormat
    switch (b.format) {
      case BarcodeFormat.ean13:      return 'EAN-13';
      case BarcodeFormat.ean8:       return 'EAN-8';
      case BarcodeFormat.upca:       return 'UPC-A';
      case BarcodeFormat.upce:       return 'UPC-E';
      case BarcodeFormat.code128:    return 'Code 128';
      case BarcodeFormat.code39:     return 'Code 39';
      case BarcodeFormat.code93:     return 'Code 93';
      case BarcodeFormat.itf:        return 'ITF';
      case BarcodeFormat.codabar:    return 'Codabar';
      case BarcodeFormat.qrCode:     return 'QR Code';
      case BarcodeFormat.dataMatrix: return 'DataMatrix';
      case BarcodeFormat.pdf417:     return 'PDF417';
      case BarcodeFormat.aztec:      return 'Aztec';
      default:                       return b.format.name;
    }
  }

  static Future<List<BarcodeResult>> scanImage(Uint8List bytes) async {
    File? tmp;
    BarcodeScanner? scanner;
    try {
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/bc_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(bytes);

      scanner = BarcodeScanner(formats: [BarcodeFormat.all]);
      final input = InputImage.fromFile(tmp);
      final barcodes = await scanner.processImage(input);

      if (barcodes.isEmpty) return [];

      return barcodes
          .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
          .map((b) {
            final fmt = _formatName(b);
            int w = 0, h = 0;

            final box = b.boundingBox;
            if (box != null) {
              w = box.width.round();
              h = box.height.round();
            }

            final spec = _specs[fmt];
            double scalePct = 0;
            if (spec != null && w > 0) {
              final nominalPx = spec.nominalWidthMm * _dpi300px;
              scalePct = (w / nominalPx) * 100;
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
      await scanner?.close();
      await tmp?.delete().catchError((_) {});
    }
  }
}
