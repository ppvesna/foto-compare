import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

bool get isWebCompareWorkerSupported =>
    globalContext.has('Worker') && globalContext.has('OffscreenCanvas');

Future<Map<String, dynamic>> runWebCompareWorker({
  required Uint8List reference,
  required Uint8List sample,
  required int pixelStep,
  required int edgeTolerance,
  required String deltaEFormula,
  required bool includeGeometry,
  required bool includeCanonical,
  ValueChanged<String>? onProgress,
}) async {
  final worker = web.Worker('compare_worker.js'.toJS);
  final completer = Completer<Map<String, dynamic>>();

  void close() => worker.terminate();

  worker.onmessage = ((JSObject rawEvent) {
    final event = rawEvent as web.MessageEvent;
    final data = event.data as JSObject;
    final type = _string(data, 'type');
    if (type == 'progress') {
      onProgress?.call(_string(data, 'message') ?? 'Обработка...');
      return;
    }
    if (type == 'error') {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(_string(data, 'message') ?? 'Ошибка Worker'),
        );
      }
      close();
      return;
    }
    if (type != 'compareResult') return;
    if (!completer.isCompleted) {
      completer.complete({
        'similarity': _number(data, 'similarity'),
        'diffPixels': _integer(data, 'diffPixels'),
        'totalPixels': _integer(data, 'totalPixels'),
        'refWidth': _integer(data, 'refWidth'),
        'refHeight': _integer(data, 'refHeight'),
        'sampleWidth': _integer(data, 'sampleWidth'),
        'sampleHeight': _integer(data, 'sampleHeight'),
        'meanDeltaE': _number(data, 'meanDeltaE'),
        'maxDeltaE': _number(data, 'maxDeltaE'),
        'defectZoneCount': _integer(data, 'defectZoneCount'),
        'defectAreaPercent': _number(data, 'defectAreaPercent'),
        'diffPng': _bytes(data, 'diffPng'),
        'geometryScore': _nullableNumber(data, 'geometryScore'),
        'geometryShiftPx': _nullableNumber(data, 'geometryShiftPx'),
        'geometryMissingPercent':
            _nullableNumber(data, 'geometryMissingPercent'),
        'geometryExtraPercent': _nullableNumber(data, 'geometryExtraPercent'),
        'geometryOverlapPixels':
            _nullableInteger(data, 'geometryOverlapPixels'),
        'geometryMissingPixels':
            _nullableInteger(data, 'geometryMissingPixels'),
        'geometryExtraPixels': _nullableInteger(data, 'geometryExtraPixels'),
        'geometryPng': _nullableBytes(data, 'geometryPng'),
        'refCanonical': _nullableBytes(data, 'refCanonical'),
        'cmpCanonical': _nullableBytes(data, 'cmpCanonical'),
      });
    }
    close();
  }).toJS;
  worker.onerror = ((JSObject rawEvent) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Web Worker не запустился'));
    }
    close();
  }).toJS;

  final message = JSObject();
  message['type'] = 'compare'.toJS;
  message['reference'] = reference.toJS;
  message['sample'] = sample.toJS;
  message['pixelStep'] = pixelStep.toJS;
  message['edgeTolerance'] = edgeTolerance.toJS;
  message['deltaEFormula'] = deltaEFormula.toJS;
  message['includeGeometry'] = includeGeometry.toJS;
  message['includeCanonical'] = includeCanonical.toJS;
  worker.postMessage(message);
  return completer.future;
}

Future<({Uint8List bytes, int width, int height})> runWebCropWorker({
  required Uint8List image,
  required int x,
  required int y,
  required int width,
  required int height,
  ValueChanged<String>? onProgress,
}) async {
  final worker = web.Worker('compare_worker.js'.toJS);
  final completer = Completer<({Uint8List bytes, int width, int height})>();

  void close() => worker.terminate();

  worker.onmessage = ((JSObject rawEvent) {
    final event = rawEvent as web.MessageEvent;
    final data = event.data as JSObject;
    final type = _string(data, 'type');
    if (type == 'progress') {
      onProgress?.call(_string(data, 'message') ?? 'Обрезка...');
      return;
    }
    if (type == 'error') {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(_string(data, 'message') ?? 'Ошибка Worker'),
        );
      }
      close();
      return;
    }
    if (type != 'cropResult') return;
    if (!completer.isCompleted) {
      completer.complete((
        bytes: _bytes(data, 'bytes'),
        width: _integer(data, 'width'),
        height: _integer(data, 'height'),
      ));
    }
    close();
  }).toJS;
  worker.onerror = ((JSObject rawEvent) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Web Worker не запустился'));
    }
    close();
  }).toJS;

  final message = JSObject();
  message['type'] = 'crop'.toJS;
  message['image'] = image.toJS;
  message['x'] = x.toJS;
  message['y'] = y.toJS;
  message['width'] = width.toJS;
  message['height'] = height.toJS;
  worker.postMessage(message);
  return completer.future;
}

String? _string(JSObject data, String name) =>
    (data[name] as JSString?)?.toDart;

double _number(JSObject data, String name) =>
    (data[name] as JSNumber).toDartDouble;

double? _nullableNumber(JSObject data, String name) =>
    (data[name] as JSNumber?)?.toDartDouble;

int _integer(JSObject data, String name) => (data[name] as JSNumber).toDartInt;

int? _nullableInteger(JSObject data, String name) =>
    (data[name] as JSNumber?)?.toDartInt;

Uint8List _bytes(JSObject data, String name) =>
    (data[name] as JSArrayBuffer).toDart.asUint8List();

Uint8List? _nullableBytes(JSObject data, String name) =>
    (data[name] as JSArrayBuffer?)?.toDart.asUint8List();
