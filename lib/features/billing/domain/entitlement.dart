enum PlanTier { free, pro, enterprise }

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
  final Set<ProductCapability> capabilities;
  final Map<UsageLimit, int?> limits;
  final bool legacyFallback;
  final DateTime? validUntil;

  const EntitlementSnapshot({
    required this.plan,
    required this.capabilities,
    required this.limits,
    this.legacyFallback = false,
    this.validUntil,
  });

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

  int? limit(UsageLimit limit) => limits[limit];

  EntitlementSnapshot copyWith({
    PlanTier? plan,
    Set<ProductCapability>? capabilities,
    Map<UsageLimit, int?>? limits,
    bool? legacyFallback,
    DateTime? validUntil,
  }) {
    return EntitlementSnapshot(
      plan: plan ?? this.plan,
      capabilities: capabilities ?? this.capabilities,
      limits: limits ?? this.limits,
      legacyFallback: legacyFallback ?? this.legacyFallback,
      validUntil: validUntil ?? this.validUntil,
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
