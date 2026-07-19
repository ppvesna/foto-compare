import 'organization_access.dart';

abstract interface class OrganizationAccessService {
  Future<OrganizationAccess> load();
}
