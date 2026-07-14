import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import 'homography_dart.dart';

/// Сервис для обработки изображений через OpenCV (нативный Android)
/// Fallback: если OpenCV недоступен — возвращает исходные байты
class OpenCvService {
  static const _channel = MethodChannel('com.example.photo_compare/opencv');

  static bool _available = true;

  // ── Коррекция перспективы ─────────────────────────
  // Автоматически находит прямоугольник распечатки и выравнивает перспективу
  static Future<Uint8List> perspectiveCorrect(Uint8List bytes) async {
    if (!_available) return bytes;
    try {
      final result = await _channel
          .invokeMethod<Uint8List>('perspectiveCorrect', {'bytes': bytes});
      return result ?? bytes;
    } on MissingPluginException {
      _available = false;
      return bytes;
    } catch (_) {
      return bytes;
    }
  }

  // ── Выравнивание через ORB ────────────────────────
  // Находит совпадающие точки между двумя фото и совмещает их
  static Future<Uint8List> alignImages(
      Uint8List reference, Uint8List source) async {
    if (!_available) return source;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
          'alignImages', {'reference': reference, 'source': source});
      return result ?? source;
    } on MissingPluginException {
      _available = false;
      return source;
    } catch (_) {
      return source;
    }
  }

  // ── Пирамидное выравнивание (L3→L2→L1→L0) ────────
  // После ручного совмещения — машинное уточнение по пикселям.
  static Future<Uint8List> alignPyramid(
      Uint8List reference, Uint8List source) async {
    if (!_available) return source;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
          'alignPyramid', {'reference': reference, 'source': source});
      return result ?? source;
    } on MissingPluginException {
      _available = false;
      return source;
    } catch (_) {
      return source;
    }
  }

  // ── SSIM сравнение ────────────────────────────────
  // Structural Similarity Index — точнее чем MAE для восприятия качества печати
  static Future<double?> ssim(Uint8List ref, Uint8List cmp) async {
    if (!_available) return null;
    try {
      final result = await _channel
          .invokeMethod<double>('ssim', {'reference': ref, 'compare': cmp});
      return result;
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Обнаружение углов документа ──────────────────
  // Возвращает 4 точки контура распечатки (или null если не найдено)
  static Future<List<Map<String, double>>?> detectDocumentCorners(
      Uint8List bytes) async {
    if (!_available) return null;
    try {
      final result =
          await _channel.invokeMethod<List>('detectCorners', {'bytes': bytes});
      if (result == null) return null;
      return result.map((e) => Map<String, double>.from(e as Map)).toList();
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Слияние двух снимков одного объекта ──────────────────────────────────
  // AKAZE + homography + sharpness-weighted fusion
  static Future<Uint8List> fuseImages(
      Uint8List reference, Uint8List source) async {
    if (!_available) return reference;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
          'fuseImages', {'reference': reference, 'source': source});
      return result ?? reference;
    } on MissingPluginException {
      _available = false;
      return reference;
    } catch (_) {
      return reference;
    }
  }

  // ── Нарезка на модули 100×100 мм ─────────────────
  // Возвращает список модулей 1404×1404 пкс каждый.
  // Крайние модули дополняются белым если размер не кратен 100 мм.
  static Future<List<Uint8List>> splitModules(
      Uint8List bytes, double widthMm, double heightMm) async {
    if (!_available) return [bytes];
    try {
      final result = await _channel.invokeMethod<List>('splitModules', {
        'bytes': bytes,
        'widthMm': widthMm,
        'heightMm': heightMm,
      });
      if (result == null) return [bytes];
      return result.map((e) => e as Uint8List).toList();
    } on MissingPluginException {
      _available = false;
      return [bytes];
    } catch (_) {
      return [bytes];
    }
  }

  // ── Сшивка двух кадров с перекрытием ─────────────
  // Каскадный поиск перекрытия через Lab-пирамиду, затем пиксельная склейка.
  // Возвращает склеенное изображение или null если OpenCV недоступен.
  static Future<Uint8List?> stitchImages(
      Uint8List imageA, Uint8List imageB) async {
    if (!_available) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('stitchImages', {
        'imageA': imageA,
        'imageB': imageB,
        'wL': AppConfig.compareWL,
      });
      return result;
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Lab-пирамида ─────────────────────────────────
  // Иерархическое CIELab-сравнение: 4 уровня (1/9/81/729 зон), взвешенный ΔE.
  // Оба изображения приводятся к каноническому разрешению (70 л/см × 2 / формат).
  // Зоны letterbox исключаются из итогового счёта.
  static Future<LabCompareResult?> compareImages(
    Uint8List ref,
    Uint8List cmp, {
    double widthMm = AppConfig.printWidthMm,
    double heightMm = AppConfig.printHeightMm,
  }) async {
    if (!_available) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('compareImages', {
        'reference': ref,
        'compare': cmp,
        'wL': AppConfig.compareWL,
        'wLayer0': AppConfig.compareWLayer0,
        'wLayer1': AppConfig.compareWLayer1,
        'wLayer2': AppConfig.compareWLayer2,
        'wLayer3': AppConfig.compareWLayer3,
        'deScale': AppConfig.compareDeScale,
        'widthMm': widthMm,
        'heightMm': heightMm,
      });
      if (raw == null) return null;
      return LabCompareResult(
        score: (raw['score'] as num).toDouble(),
        activeZones: (raw['activeZones'] as num).toInt(),
        totalZones: (raw['totalZones'] as num).toInt(),
        level0: _toDoubleList(raw['level0']),
        level1: _toDoubleList(raw['level1']),
        level2: _toDoubleList(raw['level2']),
        level3: _toDoubleList(raw['level3']),
        shiftDL: (raw['shiftDL'] as num).toDouble(),
        shiftDA: (raw['shiftDA'] as num).toDouble(),
        shiftDB: (raw['shiftDB'] as num).toDouble(),
        refCanonical: raw['refCanonical'] as Uint8List,
        cmpCanonical: raw['cmpCanonical'] as Uint8List?,
        diffL3: raw['diffL3'] as Uint8List,
      );
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<double> _toDoubleList(dynamic v) {
    if (v is Float64List) return v.toList();
    if (v is List) return v.map((e) => (e as num).toDouble()).toList();
    return [];
  }

  // ── Выравнивание по якорным точкам (калибровка) ──────────────────────────
  // refPts, srcPts — точки в пикселях оригинальных изображений
  static Future<AlignByAnchorsResult?> alignByAnchors(
    Uint8List refBytes,
    Uint8List srcBytes,
    List<Offset> refPoints,
    List<Offset> srcPoints,
  ) async {
    if (_bytesEqual(refBytes, srcBytes)) {
      return AlignByAnchorsResult(
        alignedBytes: srcBytes,
        refCanonicalBytes: refBytes,
        homography: const [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
        reprojError: 0.0,
        eccScore: 1.0,
        confidence: 1.0,
        quality: 'excellent',
        refinedSrcPoints: List<Offset>.from(srcPoints),
      );
    }

    if (!_available) {
      return _dartAlignFallback(refBytes, srcBytes, refPoints, srcPoints);
    }
    try {
      final raw = await _channel.invokeMethod<Map>('alignByAnchors', {
        'refBytes': refBytes,
        'srcBytes': srcBytes,
        'refPoints': refPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'srcPoints': srcPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      });
      if (raw == null) return null;
      final hList = (raw['homography'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      final srcRaw = raw['refinedSrcPoints'] as List;
      final refinedSrc = srcRaw.map((e) {
        final m = e as Map;
        return Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
      }).toList();
      return AlignByAnchorsResult(
        alignedBytes: raw['alignedBytes'] as Uint8List,
        homography: hList,
        reprojError: (raw['reprojError'] as num).toDouble(),
        eccScore: (raw['eccScore'] as num?)?.toDouble() ?? 0.0,
        confidence: (raw['confidence'] as num?)?.toDouble() ?? 0.0,
        quality: raw['quality'] as String? ?? 'unknown',
        refinedSrcPoints: refinedSrc,
      );
    } on MissingPluginException {
      _available = false;
      return _dartAlignFallback(refBytes, srcBytes, refPoints, srcPoints);
    } catch (_) {
      return _dartAlignFallback(refBytes, srcBytes, refPoints, srcPoints);
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.lengthInBytes != b.lengthInBytes) return false;
    for (var i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<AlignByAnchorsResult?> _dartAlignFallback(
    Uint8List refBytes,
    Uint8List srcBytes,
    List<Offset> refPoints,
    List<Offset> srcPoints,
  ) async {
    final r =
        await dartAlignByAnchors(refBytes, srcBytes, refPoints, srcPoints);
    if (r == null) return null;
    final q = r.reprojError < 3
        ? 'excellent'
        : r.reprojError < 6
            ? 'good'
            : r.reprojError < 18
                ? 'warning'
                : 'fail';
    return AlignByAnchorsResult(
      alignedBytes: r.alignedBytes,
      refCanonicalBytes: r.refCanonicalBytes,
      homography: r.homography,
      reprojError: r.reprojError,
      eccScore: 0.0,
      confidence: r.reprojError < 6
          ? 0.75
          : r.reprojError < 18
              ? 0.5
              : 0.25,
      quality: q,
      refinedSrcPoints: srcPoints,
    );
  }

  static bool get isAvailable => _available;
}

class AlignByAnchorsResult {
  final Uint8List alignedBytes;
  // Канонизированный эталон (только web-фолбэк; null на нативном пути,
  // где компенсация разрешений делается внутри compareImages).
  final Uint8List? refCanonicalBytes;
  final List<double> homography; // 3×3 row-major, 9 values
  final double reprojError; // средняя ошибка репроекции в пикселях
  final double eccScore; // ECC correlation 0..1
  final double confidence; // итоговая уверенность 0..1
  final String quality; // "excellent" | "good" | "warning" | "fail"
  final List<Offset> refinedSrcPoints; // уточнённые точки src (cornerSubPix)

  const AlignByAnchorsResult({
    required this.alignedBytes,
    this.refCanonicalBytes,
    required this.homography,
    required this.reprojError,
    required this.eccScore,
    required this.confidence,
    required this.quality,
    required this.refinedSrcPoints,
  });

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

class LabCompareResult {
  final double score; // итоговый балл 0–100 (только активные зоны)
  final int activeZones; // зон участвовало в счёте (не letterbox)
  final int totalZones; // всего зон L3 (всегда 729)
  final List<double> level0; //   1 зона: [ΔE]
  final List<double> level1; //   9 зон:  [ΔE × 9]
  final List<double> level2; //  81 зона: [ΔE × 81]
  final List<double> level3; // 729 зон:  [ΔE × 729]
  final double shiftDL; // глобальный сдвиг яркости L* (ref − cmp)
  final double shiftDA; // глобальный сдвиг a* (+ красный, − зелёный)
  final double shiftDB; // глобальный сдвиг b* (+ жёлтый, − синий)
  final Uint8List
      refCanonical; // каноническое ref-изображение для наложения diff
  final Uint8List?
      cmpCanonical; // каноническое cmp-изображение, та же система координат
  final Uint8List diffL3; // PNG карта L3 27×27 детали

  const LabCompareResult({
    required this.score,
    required this.activeZones,
    required this.totalZones,
    required this.level0,
    required this.level1,
    required this.level2,
    required this.level3,
    required this.shiftDL,
    required this.shiftDA,
    required this.shiftDB,
    required this.refCanonical,
    this.cmpCanonical,
    required this.diffL3,
  });
}
