import 'dart:typed_data';
import 'package:flutter/painting.dart' show Offset;

/// Результат операции alignByAnchors
class AlignmentResult {
  final bool success;
  final Uint8List alignedBytes;
  final double reprojectionError; // px
  final double eccScore; // 0..1
  final double confidence; // 0..1
  final List<double> homography; // 3×3 row-major, 9 значений
  final String quality; // "excellent" | "good" | "warning" | "fail"
  final List<Offset> refinedSrcPoints;

  const AlignmentResult({
    required this.success,
    required this.alignedBytes,
    required this.reprojectionError,
    required this.eccScore,
    required this.confidence,
    required this.homography,
    required this.quality,
    required this.refinedSrcPoints,
  });

  static String computeQuality(double reprojError, double eccScore) {
    if (eccScore >= 0.95 && reprojError < 1.5) return 'excellent';
    if (eccScore >= 0.90 && reprojError < 3.0) return 'good';
    if (reprojError < 18.0) return 'warning';
    return 'fail';
  }

  static double computeConfidence(double reprojError, double eccScore) {
    final reproj = (1.0 - (reprojError / 18.0)).clamp(0.0, 1.0);
    return (eccScore * 0.45 + reproj * 0.55).clamp(0.0, 1.0);
  }

  bool get isAcceptable =>
      quality == 'excellent' || quality == 'good' || quality == 'warning';

  String get qualityLabel {
    switch (quality) {
      case 'excellent':
        return 'Отлично';
      case 'good':
        return 'Хорошо';
      case 'warning':
        return 'Слабо';
      default:
        return 'Ошибка';
    }
  }
}
