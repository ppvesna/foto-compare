import 'entitlement.dart';

abstract interface class EntitlementService {
  Future<EntitlementSnapshot> load();
}
