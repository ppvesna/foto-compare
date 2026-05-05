import 'dart:typed_data';
import 'package:flutter/services.dart';

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

  static bool get isAvailable => _available;
}
