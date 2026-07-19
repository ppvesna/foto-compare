enum OrganizationRole {
  owner,
  admin,
  technologist,
  operator,
  viewer,
  member,
  personal,
}

enum OrganizationPermission {
  runInspection,
  manageReferences,
  viewProtocols,
  addComments,
  manageSettings,
  manageMembers,
  manageBilling,
}

class OrganizationAccess {
  final String? organizationId;
  final OrganizationRole role;
  final Set<OrganizationPermission> permissions;
  final bool legacyFallback;

  const OrganizationAccess({
    required this.organizationId,
    required this.role,
    required this.permissions,
    this.legacyFallback = false,
  });

  factory OrganizationAccess.forRole({
    required String? organizationId,
    required OrganizationRole role,
  }) {
    return OrganizationAccess(
      organizationId: organizationId,
      role: role,
      permissions: _permissionsForRole(role),
    );
  }

  factory OrganizationAccess.legacyPersonal() {
    return const OrganizationAccess(
      organizationId: null,
      role: OrganizationRole.personal,
      permissions: {
        OrganizationPermission.runInspection,
        OrganizationPermission.manageReferences,
        OrganizationPermission.viewProtocols,
        OrganizationPermission.addComments,
        OrganizationPermission.manageSettings,
        OrganizationPermission.manageMembers,
        OrganizationPermission.manageBilling,
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
      case OrganizationRole.admin:
        return OrganizationPermission.values.toSet();
      case OrganizationRole.technologist:
        return {
          OrganizationPermission.runInspection,
          OrganizationPermission.manageReferences,
          OrganizationPermission.viewProtocols,
          OrganizationPermission.addComments,
          OrganizationPermission.manageSettings,
        };
      case OrganizationRole.operator:
        return {
          OrganizationPermission.runInspection,
          OrganizationPermission.viewProtocols,
          OrganizationPermission.addComments,
        };
      case OrganizationRole.viewer:
      case OrganizationRole.member:
        return {
          OrganizationPermission.viewProtocols,
          OrganizationPermission.addComments,
        };
      case OrganizationRole.personal:
        return OrganizationPermission.values.toSet();
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
      case OrganizationRole.technologist:
        return 'Технолог';
      case OrganizationRole.operator:
        return 'Оператор';
      case OrganizationRole.viewer:
        return 'Наблюдатель';
      case OrganizationRole.member:
        return 'Участник';
      case OrganizationRole.personal:
        return 'Личный профиль';
    }
  }
}
