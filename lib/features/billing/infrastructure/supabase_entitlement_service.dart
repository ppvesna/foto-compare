import 'dart:convert';

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
      final remote = await client.rpc('current_entitlement_v4');
      final metadata = _metadataFromResponse(remote);
      if (metadata != null) return _fromMetadata(metadata);
    } catch (_) {
      // Billing v4 is optional until migration 019 is installed.
    }

    try {
      final remote = await client.rpc('current_entitlement_v3');
      final metadata = _metadataFromResponse(remote);
      if (metadata != null) return _fromMetadata(metadata);
    } catch (_) {
      // Entitlement v3 is optional until migration 009 is installed.
    }

    try {
      final remote = await client.rpc('current_entitlement_v2');
      final metadata = _metadataFromResponse(remote);
      if (metadata != null) return _fromMetadata(metadata);
    } catch (_) {
      // Entitlement v2 is optional until migration 008 is installed.
    }

    try {
      final remote = await client.rpc('current_access_snapshot');
      final metadata = _metadataFromResponse(remote);
      if (metadata != null) return _fromMetadata(metadata);
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

  Map<String, dynamic>? _metadataFromResponse(Object? response) {
    Object? value = response;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    if (value is List && value.isNotEmpty) value = value.first;
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  EntitlementSnapshot _fromMetadata(Map<String, dynamic> metadata) {
    final planName = metadata['plan'] as String? ?? 'free';
    final plan = _parsePlan(planName);
    final personalPlan = _parsePlan(
      metadata['personal_plan'] as String? ?? planName,
    );
    final scope = metadata['entitlement_scope'] == 'organization'
        ? EntitlementScope.organization
        : EntitlementScope.personal;
    final organizationId = metadata['organization_id'] as String?;
    final subscriptionStatus =
        (metadata['subscription_status'] as String? ?? '').toLowerCase();
    final validUntil = _parseDate(metadata['access_valid_until']);
    if (!_isActive(metadata, plan)) {
      return EntitlementSnapshot.forPlan(PlanTier.free).copyWith(
        configuredPlan: plan,
        personalPlan: personalPlan,
        scope: scope,
        organizationId: organizationId,
        validUntil: validUntil,
        subscriptionStatus: subscriptionStatus,
      );
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
      configuredPlan: plan,
      personalPlan: personalPlan,
      scope: scope,
      organizationId: organizationId,
      capabilities: capabilities,
      limits: limits,
      validUntil: validUntil,
      subscriptionStatus: subscriptionStatus,
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
