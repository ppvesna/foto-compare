import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ProtocolPreviewService {
  const ProtocolPreviewService._();

  static const maxDimension = 1280;

  static Future<Uint8List?> create(Uint8List source) {
    return compute(_createProtocolPreview, source);
  }
}

Uint8List? _createProtocolPreview(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  final longestSide =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  final preview = longestSide <= ProtocolPreviewService.maxDimension
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height
              ? ProtocolPreviewService.maxDimension
              : null,
          height: decoded.height > decoded.width
              ? ProtocolPreviewService.maxDimension
              : null,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodePng(preview, level: 6));
}
