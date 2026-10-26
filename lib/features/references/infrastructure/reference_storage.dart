import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/layout_profile.dart';
import '../domain/saved_reference.dart';

class ReferenceStorage {
  static const _profilesKey = 'reference_profiles_v2';
  static const _activeIdKey = 'reference_profiles_active_id_v2';
  static const _jobBindingsKey = 'reference_profiles_job_bindings_v1';

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
    String? id,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadProfiles();
    final resolvedId = id ??
        layoutProfile?.id ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final item = SavedReferenceProfile(
      id: resolvedId,
      label: label.trim().isEmpty ? 'Эталон' : label.trim(),
      bytes: bytes,
      layoutProfile: layoutProfile,
      createdAt: DateTime.now(),
    );
    final next = [item, ...all.where((p) => p.id != resolvedId)];
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

  static Future<SavedReferenceProfile?> loadForJob(String jobId) async {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final bindings = _decodeJobBindings(prefs.getString(_jobBindingsKey));
    final referenceId = bindings[cleanJobId];
    if (referenceId == null || referenceId.isEmpty) return null;
    final all = await loadProfiles();
    for (final item in all) {
      if (item.id == referenceId) return item;
    }
    return null;
  }

  static Future<void> bindToJob({
    required String jobId,
    required String referenceId,
  }) async {
    final cleanJobId = jobId.trim();
    final cleanReferenceId = referenceId.trim();
    if (cleanJobId.isEmpty || cleanReferenceId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final bindings = _decodeJobBindings(prefs.getString(_jobBindingsKey));
    bindings[cleanJobId] = cleanReferenceId;
    await prefs.setString(_jobBindingsKey, jsonEncode(bindings));
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
    final bindings = _decodeJobBindings(prefs.getString(_jobBindingsKey));
    bindings.removeWhere((_, referenceId) => referenceId == id);
    await prefs.setString(_jobBindingsKey, jsonEncode(bindings));
    profiles.value = next;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profilesKey);
    await prefs.remove(_activeIdKey);
    await prefs.remove(_jobBindingsKey);
    profiles.value = const [];
  }

  static Future<bool> exists() async => (await loadProfiles()).isNotEmpty;

  static Map<String, String> _decodeJobBindings(String? raw) {
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return decoded.map(
        (jobId, referenceId) => MapEntry(jobId, referenceId.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }
}
