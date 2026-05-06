import 'dart:io';
import 'dart:typed_data';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

class BarcodeResult {
  final String value;
  final String displayFormat;
  final double confidence;
  final int widthPx;      // ширина кода в пикселях
  final int heightPx;     // высота кода в пикселях
  final double areaPct;   // % площади изображения

  const BarcodeResult({
    required this.value,
    required this.displayFormat,
    required this.confidence,
    required this.widthPx,
    required this.heightPx,
    required this.areaPct,
  });

  // Оценка считываемости камерой по размеру
  // EAN/UPC: минимум ~200px по ширине
  // QR: минимум ~100×100px
  // Code128: минимум ~150px по ширине
  String get readability {
    if (widthPx == 0 && heightPx == 0) return 'неизвестно';
    final minDim = widthPx < heightPx ? widthPx : heightPx;
    final maxDim = widthPx > heightPx ? widthPx : heightPx;
    if (displayFormat.contains('QR') || displayFormat.contains('DataMatrix') ||
        displayFormat.contains('Aztec') || displayFormat.contains('PDF')) {
      // Двумерные коды — оцениваем по минимальной стороне
      if (minDim >= 150) return 'отлично';
      if (minDim >= 80)  return 'хорошо';
      if (minDim >= 40)  return 'удовлетворительно';
      return 'плохо — слишком мелкий';
    } else {
      // Линейные коды — оцениваем по длинной стороне
      if (maxDim >= 300) return 'отлично';
      if (maxDim >= 180) return 'хорошо';
      if (maxDim >= 100) return 'удовлетворительно';
      return 'плохо — слишком мелкий';
    }
  }

  int get readabilityColor {
    switch (readability) {
      case 'отлично':             return 0xFF3A8C2F;
      case 'хорошо':              return 0xFF3A8C2F;
      case 'удовлетворительно':   return 0xFFC8A020;
      default:                    return 0xFFC82020;
    }
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
      tmp = File('${dir.path}/scan_tmp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(bytes);

      controller = MobileScannerController(formats: BarcodeFormat.all);
      final result = await controller.analyzeImage(tmp.path);

      if (result == null || result.barcodes.isEmpty) return [];

      // Получаем размер изображения для расчёта %
      final imgW = result.image?.width.toDouble()  ?? 0;
      final imgH = result.image?.height.toDouble() ?? 0;
      final imgArea = imgW * imgH;

      return result.barcodes
          .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
          .map((b) {
            // Размер кода из угловых точек
            int w = 0, h = 0;
            double areaPct = 0;
            final corners = b.corners;
            if (corners != null && corners.length >= 4) {
              final xs = corners.map((c) => c.dx);
              final ys = corners.map((c) => c.dy);
              w = (xs.reduce((a, b) => a > b ? a : b) -
                   xs.reduce((a, b) => a < b ? a : b)).round();
              h = (ys.reduce((a, b) => a > b ? a : b) -
                   ys.reduce((a, b) => a < b ? a : b)).round();
              if (imgArea > 0) areaPct = (w * h) / imgArea * 100;
            }

            return BarcodeResult(
              value: b.rawValue!,
              displayFormat: _formatNames[b.format] ?? b.format.name,
              confidence: _confidence(b.rawValue!.length),
              widthPx: w,
              heightPx: h,
              areaPct: areaPct,
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

  static double _confidence(int len) {
    if (len >= 8) return 0.98;
    if (len >= 4) return 0.90;
    return 0.75;
  }
}
