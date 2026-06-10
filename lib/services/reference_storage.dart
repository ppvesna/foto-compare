import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ReferenceStorage {
  static const _fileName = 'reference_image.bin';
  static const _metaFile = 'reference_meta.txt';

  static Future<String> _dir() async {
    final d = await getApplicationDocumentsDirectory();
    return d.path;
  }

  // Сохранить эталон на диск
  static Future<void> save(Uint8List bytes, {String? label}) async {
    if (kIsWeb) return;
    final dir = await _dir();
    await File('$dir/$_fileName').writeAsBytes(bytes);
    if (label != null) {
      await File('$dir/$_metaFile').writeAsString(label);
    }
  }

  // Загрузить сохранённый эталон
  static Future<Uint8List?> load() async {
    if (kIsWeb) return null;
    final dir = await _dir();
    final file = File('$dir/$_fileName');
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  }

  // Метка (имя/дата) сохранённого эталона
  static Future<String?> loadLabel() async {
    if (kIsWeb) return null;
    final dir = await _dir();
    final file = File('$dir/$_metaFile');
    if (!await file.exists()) return null;
    return await file.readAsString();
  }

  // Удалить сохранённый эталон
  static Future<void> clear() async {
    if (kIsWeb) return;
    final dir = await _dir();
    final f1 = File('$dir/$_fileName');
    final f2 = File('$dir/$_metaFile');
    if (await f1.exists()) await f1.delete();
    if (await f2.exists()) await f2.delete();
  }

  static Future<bool> exists() async {
    if (kIsWeb) return false;
    final dir = await _dir();
    return File('$dir/$_fileName').exists();
  }
}
