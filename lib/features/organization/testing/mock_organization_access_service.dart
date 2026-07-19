import '../domain/organization_access.dart';
import '../domain/organization_access_service.dart';

class MockOrganizationAccessService implements OrganizationAccessService {
  OrganizationAccess access;

  MockOrganizationAccessService(this.access);

  @override
  Future<OrganizationAccess> load() async => access;
}
