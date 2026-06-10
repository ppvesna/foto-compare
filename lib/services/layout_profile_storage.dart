import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/layout_profile.dart';

class LayoutProfileStorage {
  static const _fileName = 'layout_profiles.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<LayoutProfile>> loadAll() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List;
      return list.map((e) => LayoutProfile.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(LayoutProfile profile) async {
    if (kIsWeb) return;
    final all = await loadAll();
    final idx = all.indexWhere((p) => p.id == profile.id);
    if (idx >= 0) {
      all[idx] = profile;
    } else {
      all.add(profile);
    }
    final f = await _file();
    await f.writeAsString(jsonEncode(all.map((p) => p.toJson()).toList()));
  }

  static Future<void> delete(String id) async {
    if (kIsWeb) return;
    final all = await loadAll();
    all.removeWhere((p) => p.id == id);
    final f = await _file();
    await f.writeAsString(jsonEncode(all.map((p) => p.toJson()).toList()));
  }
}
