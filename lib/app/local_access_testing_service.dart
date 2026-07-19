import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/billing/billing.dart';
import '../features/organization/organization.dart';

class AccessTestOverride {
  final bool enabled;
  final PlanTier plan;
  final OrganizationRole role;

  const AccessTestOverride({
    required this.enabled,
    required this.plan,
    required this.role,
  });

  static const disabled = AccessTestOverride(
    enabled: false,
    plan: PlanTier.free,
    role: OrganizationRole.personal,
  );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'plan': plan.name,
        'role': role.name,
      };

  factory AccessTestOverride.fromJson(Map<String, dynamic> json) {
    return AccessTestOverride(
      enabled: json['enabled'] as bool? ?? false,
      plan: _planFromName(json['plan'] as String?),
      role: _roleFromName(json['role'] as String?),
    );
  }

  AccessTestOverride copyWith({
    bool? enabled,
    PlanTier? plan,
    OrganizationRole? role,
  }) {
    return AccessTestOverride(
      enabled: enabled ?? this.enabled,
      plan: plan ?? this.plan,
      role: role ?? this.role,
    );
  }

  static PlanTier _planFromName(String? name) {
    return PlanTier.values.firstWhere(
      (value) => value.name == name,
      orElse: () => PlanTier.free,
    );
  }

  static OrganizationRole _roleFromName(String? name) {
    return OrganizationRole.values.firstWhere(
      (value) => value.name == name,
      orElse: () => OrganizationRole.personal,
    );
  }
}

class LocalAccessTestingService {
  static const _key = 'access_test_override_v1';

  const LocalAccessTestingService();

  Future<AccessTestOverride> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AccessTestOverride.disabled;
    try {
      return AccessTestOverride.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return AccessTestOverride.disabled;
    }
  }

  Future<void> save(AccessTestOverride value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
