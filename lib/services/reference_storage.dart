import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/layout_profile.dart';

class SavedReferenceProfile {
  final String id;
  final String label;
  final Uint8List bytes;
  final LayoutProfile? layoutProfile;
  final DateTime createdAt;

  const SavedReferenceProfile({
    required this.id,
    required this.label,
    required this.bytes,
    required this.layoutProfile,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'bytes': base64Encode(bytes),
        'layoutProfile': layoutProfile?.toJson(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedReferenceProfile.fromJson(Map<String, dynamic> json) {
    return SavedReferenceProfile(
      id: json['id'] as String,
      label: json['label'] as String? ?? 'Эталон',
      bytes: base64Decode(json['bytes'] as String),
      layoutProfile: json['layoutProfile'] == null
          ? null
          : LayoutProfile.fromJson(
              Map<String, dynamic>.from(json['layoutProfile'] as Map),
            ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ReferenceStorage {
  static const _profilesKey = 'reference_profiles_v2';
  static const _activeIdKey = 'reference_profiles_active_id_v2';

  static final ValueNotifier<List<SavedReferenceProfile>> profiles =
      ValueNotifier<List<SavedReferenceProfile>>(const []);

  static Future<List<SavedReferenceProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) {
      profiles.value = const [];
      return const [];
    }
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => SavedReferenceProfile.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      profiles.value = list;
      return list;
    } catch (_) {
      profiles.value = const [];
      return const [];
    }
  }

  static Future<void> save(
    Uint8List bytes, {
    String? label,
    LayoutProfile? layoutProfile,
  }) async {
    await saveProfile(
      bytes: bytes,
      label: label ?? layoutProfile?.name ?? 'Эталон',
      layoutProfile: layoutProfile,
    );
  }

  static Future<SavedReferenceProfile> saveProfile({
    required Uint8List bytes,
    required String label,
    LayoutProfile? layoutProfile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadProfiles();
    final id =
        layoutProfile?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final item = SavedReferenceProfile(
      id: id,
      label: label.trim().isEmpty ? 'Эталон' : label.trim(),
      bytes: bytes,
      layoutProfile: layoutProfile,
      createdAt: DateTime.now(),
    );
    final next = [item, ...all.where((p) => p.id != id)];
    await prefs.setString(
        _profilesKey, jsonEncode(next.map((p) => p.toJson()).toList()));
    await prefs.setString(_activeIdKey, item.id);
    profiles.value = next;
    return item;
  }

  static Future<void> setActive(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeIdKey, id);
  }

  static Future<SavedReferenceProfile?> loadActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadProfiles();
    if (all.isEmpty) return null;
    final id = prefs.getString(_activeIdKey);
    return all.firstWhere(
      (p) => p.id == id,
      orElse: () => all.first,
    );
  }

  static Future<Uint8List?> load() async => (await loadActiveProfile())?.bytes;

  static Future<String?> loadLabel() async =>
      (await loadActiveProfile())?.label;

  static Future<LayoutProfile?> loadLayoutProfile() async =>
      (await loadActiveProfile())?.layoutProfile;

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final next = (await loadProfiles()).where((p) => p.id != id).toList();
    await prefs.setString(
        _profilesKey, jsonEncode(next.map((p) => p.toJson()).toList()));
    final activeId = prefs.getString(_activeIdKey);
    if (activeId == id) {
      if (next.isEmpty) {
        await prefs.remove(_activeIdKey);
      } else {
        await prefs.setString(_activeIdKey, next.first.id);
      }
    }
    profiles.value = next;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profilesKey);
    await prefs.remove(_activeIdKey);
    profiles.value = const [];
  }

  static Future<bool> exists() async => (await loadProfiles()).isNotEmpty;
}
