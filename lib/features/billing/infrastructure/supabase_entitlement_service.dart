import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entitlement.dart';
import '../domain/entitlement_service.dart';

class SupabaseEntitlementService implements EntitlementService {
  final SupabaseClient client;

  const SupabaseEntitlementService(this.client);

  @override
  Future<EntitlementSnapshot> load() async {
    final user = client.auth.currentUser;
    if (user == null) return EntitlementSnapshot.forPlan(PlanTier.free);

    try {
      final remote = await client.rpc('current_access_snapshot');
      if (remote is Map) {
        return _fromMetadata(Map<String, dynamic>.from(remote));
      }
    } catch (_) {
      // The migration may not be installed yet. Fall back without blocking work.
    }

    // app_metadata is issued by the backend and cannot be edited by the user.
    // user_metadata must never be trusted for paid or privileged access.
    final metadata = user.appMetadata;
    final planName = metadata['plan'] as String?;
    if (planName == null) return EntitlementSnapshot.legacyCompatible();

    return _fromMetadata(metadata);
  }

  EntitlementSnapshot _fromMetadata(Map<String, dynamic> metadata) {
    final planName = metadata['plan'] as String? ?? 'free';
    final plan = _parsePlan(planName);
    if (!_isActive(metadata, plan)) {
      return EntitlementSnapshot.forPlan(PlanTier.free);
    }

    final defaults = EntitlementSnapshot.forPlan(plan);
    final capabilityNames = metadata['entitlements'];
    final capabilities = _parseCapabilities(capabilityNames) ??
        Set<ProductCapability>.from(defaults.capabilities);
    final limits = Map<UsageLimit, int?>.from(defaults.limits);
    final rawLimits = metadata['limits'];
    if (rawLimits is Map) {
      for (final entry in rawLimits.entries) {
        final key = _parseLimit(entry.key.toString());
        if (key == null) continue;
        limits[key] = entry.value == null
            ? null
            : (entry.value as num?)?.toInt() ?? limits[key];
      }
    }

    return EntitlementSnapshot(
      plan: plan,
      capabilities: capabilities,
      limits: limits,
      validUntil: _parseDate(metadata['access_valid_until']),
    );
  }

  Set<ProductCapability>? _parseCapabilities(Object? value) {
    if (value is List) {
      return value
          .whereType<String>()
          .map(_parseCapability)
          .whereType<ProductCapability>()
          .toSet();
    }
    if (value is Map) {
      return value.entries
          .where((entry) => entry.value == true)
          .map((entry) => _parseCapability(entry.key.toString()))
          .whereType<ProductCapability>()
          .toSet();
    }
    return null;
  }

  PlanTier _parsePlan(String value) {
    switch (value.toLowerCase()) {
      case 'pro':
        return PlanTier.pro;
      case 'enterprise':
        return PlanTier.enterprise;
      default:
        return PlanTier.free;
    }
  }

  bool _isActive(Map<String, dynamic> metadata, PlanTier plan) {
    if (plan == PlanTier.free) return true;
    final status = (metadata['subscription_status'] as String?)?.toLowerCase();
    if (status != 'active' && status != 'trialing' && status != 'grace') {
      return false;
    }
    final validUntil = _parseDate(metadata['access_valid_until']);
    return validUntil == null || validUntil.isAfter(DateTime.now().toUtc());
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  ProductCapability? _parseCapability(String value) {
    for (final capability in ProductCapability.values) {
      if (capability.name == value) return capability;
    }
    return null;
  }

  UsageLimit? _parseLimit(String value) {
    for (final limit in UsageLimit.values) {
      if (limit.name == value) return limit;
    }
    return null;
  }
}
