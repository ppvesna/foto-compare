import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/camera_calibration.dart';

class CameraCalibrationProfileService {
  const CameraCalibrationProfileService._();

  static const _profilesKey = 'camera.calibration.profiles.v1';
  static const _activeProfileKey = 'camera.calibration.activeProfile';

  static final ValueNotifier<List<CameraCalibrationProfile>> profilesNotifier =
      ValueNotifier<List<CameraCalibrationProfile>>(const []);
  static final ValueNotifier<CameraCalibrationProfile?> activeProfileNotifier =
      ValueNotifier<CameraCalibrationProfile?>(null);

  static Future<List<CameraCalibrationProfile>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    final activeId = prefs.getString(_activeProfileKey);
    if (raw == null || raw.isEmpty) {
      profilesNotifier.value = const [];
      activeProfileNotifier.value = null;
      return const [];
    }
    try {
      final profiles = (jsonDecode(raw) as List)
          .map(
            (value) => CameraCalibrationProfile.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList(growable: false);
      profilesNotifier.value = profiles;
      activeProfileNotifier.value = _byId(profiles, activeId);
      return profiles;
    } catch (_) {
      profilesNotifier.value = const [];
      activeProfileNotifier.value = null;
      return const [];
    }
  }

  static Future<CameraCalibrationProfile?> loadActive() async {
    await loadAll();
    return activeProfileNotifier.value;
  }

  static Future<void> save(
    CameraCalibrationProfile profile, {
    bool makeActive = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (await loadAll()).toList();
    final index = current.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      current.add(profile);
    } else {
      current[index] = profile;
    }
    await prefs.setString(
      _profilesKey,
      jsonEncode(current.map((item) => item.toJson()).toList()),
    );
    if (makeActive) {
      await prefs.setString(_activeProfileKey, profile.id);
    }
    profilesNotifier.value = List.unmodifiable(current);
    activeProfileNotifier.value = makeActive
        ? profile
        : _byId(current, prefs.getString(_activeProfileKey));
  }

  static Future<void> setActive(String? profileId) async {
    final prefs = await SharedPreferences.getInstance();
    if (profileId == null) {
      await prefs.remove(_activeProfileKey);
    } else {
      await prefs.setString(_activeProfileKey, profileId);
    }
    final profiles = await loadAll();
    activeProfileNotifier.value = _byId(profiles, profileId);
  }

  static Future<void> delete(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = (await loadAll())
        .where((profile) => profile.id != profileId)
        .toList(growable: false);
    await prefs.setString(
      _profilesKey,
      jsonEncode(current.map((item) => item.toJson()).toList()),
    );
    if (prefs.getString(_activeProfileKey) == profileId) {
      await prefs.remove(_activeProfileKey);
    }
    profilesNotifier.value = current;
    activeProfileNotifier.value = _byId(
      current,
      prefs.getString(_activeProfileKey),
    );
  }

  static CameraCalibrationProfile? _byId(
    List<CameraCalibrationProfile> profiles,
    String? id,
  ) {
    if (id == null) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }
}
