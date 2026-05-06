import 'dart:io';
import 'dart:typed_data';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

class BarcodeResult {
  final String value;
  final String displayFormat;
  final double confidence;

  const BarcodeResult({
    required this.value,
    required this.displayFormat,
    required this.confidence,
  });
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

  /// Сканирует все коды из изображения (байты → временный файл → сканер)
  static Future<List<BarcodeResult>> scanImage(Uint8List bytes) async {
    File? tmp;
    MobileScannerController? controller;
    try {
      // Сохраняем во временный файл
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/scan_tmp.jpg');
      await tmp.writeAsBytes(bytes);

      controller = MobileScannerController(formats: BarcodeFormat.all);
      final result = await controller.analyzeImage(tmp.path);

      if (result == null || result.barcodes.isEmpty) return [];

      return result.barcodes
          .where((b) => b.rawValue != null && b.rawValue!.isNotEmpty)
          .map((b) => BarcodeResult(
                value: b.rawValue!,
                displayFormat: _formatNames[b.format] ?? b.format.name,
                confidence: _confidence(b.rawValue!.length),
              ))
          .toList();
    } catch (_) {
      return [];
    } finally {
      await controller?.dispose();
      await tmp?.delete().catchError((_) {});
    }
  }

  static double _confidence(int valueLength) {
    if (valueLength >= 8) return 0.98;
    if (valueLength >= 4) return 0.90;
    return 0.75;
  }
}
