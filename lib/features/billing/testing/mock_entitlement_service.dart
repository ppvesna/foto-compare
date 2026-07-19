import '../domain/entitlement.dart';
import '../domain/entitlement_service.dart';

class MockEntitlementService implements EntitlementService {
  EntitlementSnapshot snapshot;

  MockEntitlementService(this.snapshot);

  @override
  Future<EntitlementSnapshot> load() async => snapshot;
}
