enum OrganizationRole {
  owner,
  admin,
  employee,
  customer,
  personal,
}

enum OrganizationPermission {
  runInspection,
  manageReferences,
  viewProtocols,
  addComments,
  manageJobs,
  manageSettings,
  manageMembers,
  manageBilling,
  manageOrganization,
}

class OrganizationAccess {
  final String? organizationId;
  final String? organizationName;
  final OrganizationRole role;
  final Set<OrganizationPermission> permissions;
  final bool legacyFallback;

  const OrganizationAccess({
    required this.organizationId,
    this.organizationName,
    required this.role,
    required this.permissions,
    this.legacyFallback = false,
  });

  factory OrganizationAccess.forRole({
    required String? organizationId,
    String? organizationName,
    required OrganizationRole role,
  }) {
    return OrganizationAccess(
      organizationId: organizationId,
      organizationName: organizationName,
      role: role,
      permissions: _permissionsForRole(role),
    );
  }

  factory OrganizationAccess.legacyPersonal() {
    return const OrganizationAccess(
      organizationId: null,
      organizationName: null,
      role: OrganizationRole.personal,
      permissions: {
        OrganizationPermission.runInspection,
        OrganizationPermission.manageReferences,
        OrganizationPermission.viewProtocols,
        OrganizationPermission.addComments,
        OrganizationPermission.manageJobs,
        OrganizationPermission.manageSettings,
        OrganizationPermission.manageMembers,
        OrganizationPermission.manageBilling,
        OrganizationPermission.manageOrganization,
      },
      legacyFallback: true,
    );
  }

  bool allows(OrganizationPermission permission) =>
      permissions.contains(permission);

  static Set<OrganizationPermission> _permissionsForRole(
    OrganizationRole role,
  ) {
    switch (role) {
      case OrganizationRole.owner:
      case OrganizationRole.personal:
        return OrganizationPermission.values.toSet();
      case OrganizationRole.admin:
        return OrganizationPermission.values
            .where(
              (permission) =>
                  permission != OrganizationPermission.manageBilling &&
                  permission != OrganizationPermission.manageOrganization,
            )
            .toSet();
      case OrganizationRole.employee:
        return {
          OrganizationPermission.runInspection,
          OrganizationPermission.manageReferences,
          OrganizationPermission.viewProtocols,
          OrganizationPermission.addComments,
        };
      case OrganizationRole.customer:
        return {
          OrganizationPermission.viewProtocols,
          OrganizationPermission.addComments,
        };
    }
  }
}

abstract final class OrganizationRoleCodec {
  static OrganizationRole fromStoredName(
    String? value, {
    OrganizationRole fallback = OrganizationRole.personal,
  }) {
    switch (value?.trim().toLowerCase()) {
      case 'owner':
        return OrganizationRole.owner;
      case 'admin':
        return OrganizationRole.admin;
      case 'employee':
      case 'technologist':
      case 'operator':
      case 'member':
        return OrganizationRole.employee;
      case 'customer':
      case 'viewer':
        return OrganizationRole.customer;
      case 'personal':
        return OrganizationRole.personal;
      default:
        return fallback;
    }
  }
}

extension OrganizationRoleLabel on OrganizationRole {
  String get label {
    switch (this) {
      case OrganizationRole.owner:
        return 'Владелец';
      case OrganizationRole.admin:
        return 'Администратор';
      case OrganizationRole.employee:
        return 'Сотрудник';
      case OrganizationRole.customer:
        return 'Представитель заказчика';
      case OrganizationRole.personal:
        return 'Личный профиль';
    }
  }

  String get scopeLabel {
    switch (this) {
      case OrganizationRole.owner:
        return 'вся организация, тариф и владение';
      case OrganizationRole.admin:
        return 'все работы и участники без тарифа и владения';
      case OrganizationRole.employee:
        return 'только назначенные работы, права зависят от функции';
      case OrganizationRole.customer:
        return 'только свои работы, просмотр, согласование и чат';
      case OrganizationRole.personal:
        return 'все личные работы в пределах плана';
    }
  }
}
