enum PlanTier { free, pro, enterprise }

enum EntitlementScope { personal, organization }

enum ProductCapability {
  runInspection,
  exactDeltaE,
  ocr,
  barcode,
  aiAnalysis,
  protocolHistory,
  multipleReferences,
  cloudSync,
  cloudAssets,
  pdfReports,
  collaboration,
}

enum UsageLimit { checksPerDay, savedReferences, organizationSeats }

class EntitlementSnapshot {
  final PlanTier plan;
  final PlanTier configuredPlan;
  final PlanTier personalPlan;
  final EntitlementScope scope;
  final String? organizationId;
  final Set<ProductCapability> capabilities;
  final Map<UsageLimit, int?> limits;
  final bool legacyFallback;
  final DateTime? validUntil;
  final String subscriptionStatus;

  const EntitlementSnapshot({
    required this.plan,
    PlanTier? configuredPlan,
    PlanTier? personalPlan,
    this.scope = EntitlementScope.personal,
    this.organizationId,
    required this.capabilities,
    required this.limits,
    this.legacyFallback = false,
    this.validUntil,
    this.subscriptionStatus = 'active',
  })  : configuredPlan = configuredPlan ?? plan,
        personalPlan = personalPlan ?? plan;

  factory EntitlementSnapshot.forPlan(PlanTier plan) {
    switch (plan) {
      case PlanTier.free:
        return const EntitlementSnapshot(
          plan: PlanTier.free,
          capabilities: {
            ProductCapability.runInspection,
            ProductCapability.barcode,
            ProductCapability.protocolHistory,
          },
          limits: {
            UsageLimit.checksPerDay: 10,
            UsageLimit.savedReferences: 3,
            UsageLimit.organizationSeats: 1,
          },
        );
      case PlanTier.pro:
        return const EntitlementSnapshot(
          plan: PlanTier.pro,
          capabilities: {
            ProductCapability.runInspection,
            ProductCapability.exactDeltaE,
            ProductCapability.ocr,
            ProductCapability.barcode,
            ProductCapability.aiAnalysis,
            ProductCapability.protocolHistory,
            ProductCapability.multipleReferences,
            ProductCapability.cloudSync,
            ProductCapability.cloudAssets,
            ProductCapability.pdfReports,
            ProductCapability.collaboration,
          },
          limits: {
            UsageLimit.checksPerDay: 500,
            UsageLimit.savedReferences: 50,
            UsageLimit.organizationSeats: 5,
          },
        );
      case PlanTier.enterprise:
        return const EntitlementSnapshot(
          plan: PlanTier.enterprise,
          capabilities: {
            ProductCapability.runInspection,
            ProductCapability.exactDeltaE,
            ProductCapability.ocr,
            ProductCapability.barcode,
            ProductCapability.aiAnalysis,
            ProductCapability.protocolHistory,
            ProductCapability.multipleReferences,
            ProductCapability.cloudSync,
            ProductCapability.cloudAssets,
            ProductCapability.pdfReports,
            ProductCapability.collaboration,
          },
          limits: {
            UsageLimit.checksPerDay: null,
            UsageLimit.savedReferences: null,
            UsageLimit.organizationSeats: null,
          },
        );
    }
  }

  factory EntitlementSnapshot.legacyCompatible() {
    return const EntitlementSnapshot(
      plan: PlanTier.free,
      capabilities: {
        ProductCapability.runInspection,
        ProductCapability.exactDeltaE,
        ProductCapability.ocr,
        ProductCapability.barcode,
        ProductCapability.aiAnalysis,
        ProductCapability.protocolHistory,
        ProductCapability.multipleReferences,
        ProductCapability.cloudSync,
        ProductCapability.cloudAssets,
        ProductCapability.pdfReports,
        ProductCapability.collaboration,
      },
      limits: {
        UsageLimit.checksPerDay: null,
        UsageLimit.savedReferences: null,
        UsageLimit.organizationSeats: null,
      },
      legacyFallback: true,
    );
  }

  bool allows(ProductCapability capability) =>
      capabilities.contains(capability);

  bool get usesOrganizationPlan => scope == EntitlementScope.organization;

  bool get subscriptionExpired =>
      validUntil != null && !validUntil!.isAfter(DateTime.now().toUtc());

  bool get usesFallbackPlan => configuredPlan != plan;

  int? limit(UsageLimit limit) => limits[limit];

  EntitlementSnapshot copyWith({
    PlanTier? plan,
    PlanTier? configuredPlan,
    PlanTier? personalPlan,
    EntitlementScope? scope,
    String? organizationId,
    Set<ProductCapability>? capabilities,
    Map<UsageLimit, int?>? limits,
    bool? legacyFallback,
    DateTime? validUntil,
    String? subscriptionStatus,
  }) {
    return EntitlementSnapshot(
      plan: plan ?? this.plan,
      configuredPlan: configuredPlan ?? this.configuredPlan,
      personalPlan: personalPlan ?? this.personalPlan,
      scope: scope ?? this.scope,
      organizationId: organizationId ?? this.organizationId,
      capabilities: capabilities ?? this.capabilities,
      limits: limits ?? this.limits,
      legacyFallback: legacyFallback ?? this.legacyFallback,
      validUntil: validUntil ?? this.validUntil,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
    );
  }
}

extension PlanTierLabel on PlanTier {
  String get label {
    switch (this) {
      case PlanTier.free:
        return 'Бесплатный';
      case PlanTier.pro:
        return 'Pro';
      case PlanTier.enterprise:
        return 'Enterprise';
    }
  }
}
