import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/check_protocol.dart';

class CheckHistoryService {
  static const _lastCheckKey = 'last_check_protocol_v1';
  static const _checksKey = 'check_protocols_v2';
  static final ValueNotifier<CheckProtocol?> lastCheck =
      ValueNotifier<CheckProtocol?>(null);
  static final ValueNotifier<List<CheckProtocol>> checks =
      ValueNotifier<List<CheckProtocol>>(const []);

  static List<CheckProtocol> forScope({
    required String ownerUserId,
    String? organizationId,
  }) {
    final normalizedOrganizationId = organizationId?.trim() ?? '';
    return checks.value
        .where(
          (protocol) =>
              protocol.ownerUserId == ownerUserId &&
              protocol.organizationId == normalizedOrganizationId,
        )
        .toList(growable: false);
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastCheckKey);
    final listRaw = prefs.getString(_checksKey);
    if (listRaw != null && listRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(listRaw) as List)
            .map((e) => CheckProtocol.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        checks.value = list;
        if (list.isNotEmpty) lastCheck.value = list.first;
      } catch (_) {
        checks.value = const [];
      }
    }
    if (raw == null || raw.isEmpty || lastCheck.value != null) return;
    try {
      lastCheck.value = CheckProtocol.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      checks.value = [lastCheck.value!];
    } catch (_) {
      lastCheck.value = null;
    }
  }

  static Future<void> saveLast(CheckProtocol protocol) async {
    lastCheck.value = protocol;
    bool sameScope(CheckProtocol candidate) =>
        candidate.ownerUserId == protocol.ownerUserId &&
        candidate.organizationId == protocol.organizationId;
    final currentScope = checks.value
        .where(
          (candidate) => sameScope(candidate) && candidate.id != protocol.id,
        )
        .take(29);
    final otherScopes =
        checks.value.where((candidate) => !sameScope(candidate));
    final next = [protocol, ...currentScope, ...otherScopes];
    checks.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckKey, jsonEncode(protocol.toJson()));
    await prefs.setString(
      _checksKey,
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );
  }

  static Future<void> clearLast() async {
    lastCheck.value = null;
    checks.value = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await prefs.remove(_checksKey);
  }

  static Future<void> clearScope({
    required String ownerUserId,
    String? organizationId,
  }) async {
    final normalizedOrganizationId = organizationId?.trim() ?? '';
    final next = checks.value
        .where(
          (protocol) =>
              protocol.ownerUserId != ownerUserId ||
              protocol.organizationId != normalizedOrganizationId,
        )
        .toList(growable: false);
    checks.value = next;
    lastCheck.value = next.isEmpty ? null : next.first;
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(_lastCheckKey);
      await prefs.remove(_checksKey);
      return;
    }
    await prefs.setString(_lastCheckKey, jsonEncode(next.first.toJson()));
    await prefs.setString(
      _checksKey,
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );
  }
}
