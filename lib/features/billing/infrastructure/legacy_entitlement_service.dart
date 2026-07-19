import '../domain/entitlement.dart';
import '../domain/entitlement_service.dart';

class LegacyEntitlementService implements EntitlementService {
  const LegacyEntitlementService();

  @override
  Future<EntitlementSnapshot> load() async =>
      EntitlementSnapshot.legacyCompatible();
}
