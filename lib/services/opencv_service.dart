import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../config/app_config.dart';

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
      final result = await _channel.invokeMethod<Uint8List>(
          'perspectiveCorrect', {'bytes': bytes});
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

  // ── SSIM сравнение ────────────────────────────────
  // Structural Similarity Index — точнее чем MAE для восприятия качества печати
  static Future<double?> ssim(Uint8List ref, Uint8List cmp) async {
    if (!_available) return null;
    try {
      final result = await _channel.invokeMethod<double>(
          'ssim', {'reference': ref, 'compare': cmp});
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
      final result = await _channel.invokeMethod<List>(
          'detectCorners', {'bytes': bytes});
      if (result == null) return null;
      return result
          .map((e) => Map<String, double>.from(e as Map))
          .toList();
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
        'wL':     AppConfig.compareWL,
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
      Uint8List ref, Uint8List cmp, {
      double widthMm  = AppConfig.printWidthMm,
      double heightMm = AppConfig.printHeightMm,
  }) async {
    if (!_available) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('compareImages', {
        'reference': ref,
        'compare':   cmp,
        'wL':        AppConfig.compareWL,
        'wLayer0':   AppConfig.compareWLayer0,
        'wLayer1':   AppConfig.compareWLayer1,
        'wLayer2':   AppConfig.compareWLayer2,
        'wLayer3':   AppConfig.compareWLayer3,
        'deScale':   AppConfig.compareDeScale,
        'widthMm':   widthMm,
        'heightMm':  heightMm,
      });
      if (raw == null) return null;
      return LabCompareResult(
        score:        (raw['score']       as num).toDouble(),
        activeZones:  (raw['activeZones'] as num).toInt(),
        totalZones:   (raw['totalZones']  as num).toInt(),
        level0:       _toDoubleList(raw['level0']),
        level1:       _toDoubleList(raw['level1']),
        level2:       _toDoubleList(raw['level2']),
        level3:       _toDoubleList(raw['level3']),
        diffL1:       raw['diffL1'] as Uint8List,
        diffL2:       raw['diffL2'] as Uint8List,
        diffL3:       raw['diffL3'] as Uint8List,
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

  static bool get isAvailable => _available;
}

class LabCompareResult {
  final double score;           // итоговый балл 0–100 (только активные зоны)
  final int activeZones;        // зон участвовало в счёте (не letterbox)
  final int totalZones;         // всего зон L3 (всегда 729)
  final List<double> level0;    //   1 зона: [ΔE]
  final List<double> level1;    //   9 зон:  [ΔE × 9]
  final List<double> level2;    //  81 зона: [ΔE × 81]
  final List<double> level3;    // 729 зон:  [ΔE × 729]
  final Uint8List diffL1;       // 270×270 PNG — L1 3×3  крупные зоны
  final Uint8List diffL2;       // 270×270 PNG — L2 9×9  средние зоны
  final Uint8List diffL3;       // 270×270 PNG — L3 27×27 детали (по запросу)

  const LabCompareResult({
    required this.score,
    required this.activeZones,
    required this.totalZones,
    required this.level0,
    required this.level1,
    required this.level2,
    required this.level3,
    required this.diffL1,
    required this.diffL2,
    required this.diffL3,
  });
}
