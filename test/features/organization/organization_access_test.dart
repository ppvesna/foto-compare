import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/organization/organization.dart';

void main() {
  test('owner may perform every organization action', () {
    final access = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.owner,
    );

    expect(
      OrganizationPermission.values.every(access.allows),
      isTrue,
    );
  });

  test('operator may inspect but may not manage members or billing', () {
    final access = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.operator,
    );

    expect(access.allows(OrganizationPermission.runInspection), isTrue);
    expect(access.allows(OrganizationPermission.manageMembers), isFalse);
    expect(access.allows(OrganizationPermission.manageBilling), isFalse);
  });

  test('viewer cannot run an inspection', () {
    final access = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.viewer,
    );

    expect(access.allows(OrganizationPermission.runInspection), isFalse);
    expect(access.allows(OrganizationPermission.viewProtocols), isTrue);
  });

  test('legacy personal access preserves current application behavior', () {
    final access = OrganizationAccess.legacyPersonal();

    expect(access.legacyFallback, isTrue);
    expect(
      OrganizationPermission.values.every(access.allows),
      isTrue,
    );
  });

  test('mock service returns configured organization role', () async {
    final expected = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.technologist,
    );
    final service = MockOrganizationAccessService(expected);

    expect(await service.load(), same(expected));
  });
}
