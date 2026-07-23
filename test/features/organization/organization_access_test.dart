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

  test('administrator cannot manage billing or organization ownership', () {
    final access = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.admin,
    );

    expect(access.allows(OrganizationPermission.runInspection), isTrue);
    expect(access.allows(OrganizationPermission.manageMembers), isTrue);
    expect(access.allows(OrganizationPermission.manageBilling), isFalse);
    expect(
      access.allows(OrganizationPermission.manageOrganization),
      isFalse,
    );
  });

  test('employee may inspect but may not manage members or billing', () {
    final access = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.employee,
    );

    expect(access.allows(OrganizationPermission.runInspection), isTrue);
    expect(access.allows(OrganizationPermission.viewProtocols), isTrue);
    expect(access.allows(OrganizationPermission.manageMembers), isFalse);
    expect(access.allows(OrganizationPermission.manageBilling), isFalse);
  });

  test('customer cannot run an inspection', () {
    final access = OrganizationAccess.forRole(
      organizationId: 'organization-1',
      role: OrganizationRole.customer,
    );

    expect(access.allows(OrganizationPermission.runInspection), isFalse);
    expect(access.allows(OrganizationPermission.viewProtocols), isTrue);
    expect(access.allows(OrganizationPermission.addComments), isTrue);
  });

  test('legacy organization roles map to the new role model', () {
    expect(
      OrganizationRoleCodec.fromStoredName('technologist'),
      OrganizationRole.employee,
    );
    expect(
      OrganizationRoleCodec.fromStoredName('operator'),
      OrganizationRole.employee,
    );
    expect(
      OrganizationRoleCodec.fromStoredName('member'),
      OrganizationRole.employee,
    );
    expect(
      OrganizationRoleCodec.fromStoredName('viewer'),
      OrganizationRole.customer,
    );
    expect(
      OrganizationRoleCodec.fromStoredName(
        'unexpected-server-role',
        fallback: OrganizationRole.customer,
      ),
      OrganizationRole.customer,
    );
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
      role: OrganizationRole.employee,
    );
    final service = MockOrganizationAccessService(expected);

    expect(await service.load(), same(expected));
  });

  test('owner and administrator have different assignment boundaries', () {
    expect(
      OrganizationAdministrationPolicy.canAssign(
        actorRole: OrganizationRole.owner,
        currentRole: null,
        requestedRole: OrganizationRole.admin,
      ),
      isTrue,
    );
    expect(
      OrganizationAdministrationPolicy.canAssign(
        actorRole: OrganizationRole.admin,
        currentRole: null,
        requestedRole: OrganizationRole.admin,
      ),
      isFalse,
    );
    expect(
      OrganizationAdministrationPolicy.canAssign(
        actorRole: OrganizationRole.admin,
        currentRole: OrganizationRole.admin,
        requestedRole: OrganizationRole.employee,
      ),
      isFalse,
    );
    expect(
      OrganizationAdministrationPolicy.canAssign(
        actorRole: OrganizationRole.employee,
        currentRole: null,
        requestedRole: OrganizationRole.customer,
      ),
      isFalse,
    );
  });

  test('mock administration service records server operations', () async {
    final service = MockOrganizationAdministrationService(
      profilesByNickname: const {
        'printer_ivan': OrganizationUserProfile(
          userId: 'user-2',
          nickname: 'printer_ivan',
          displayName: 'Иван',
          organizationName: 'Тестовая типография',
        ),
      },
    );

    final profile = await service.findUserByNickname('Printer_Ivan');
    await service.assignMember(
      organizationId: 'organization-1',
      userId: profile!.userId,
      role: OrganizationRole.employee,
    );

    expect(profile.nickname, 'printer_ivan');
    expect(service.lastAssignment?.userId, 'user-2');
    expect(service.lastAssignment?.role, OrganizationRole.employee);
  });
}
