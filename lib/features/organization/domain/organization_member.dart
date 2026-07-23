import 'organization_access.dart';

class OrganizationUserProfile {
  final String userId;
  final String nickname;
  final String displayName;
  final String organizationName;

  const OrganizationUserProfile({
    required this.userId,
    required this.nickname,
    required this.displayName,
    required this.organizationName,
  });
}

class OrganizationMember {
  final String userId;
  final String nickname;
  final String displayName;
  final OrganizationRole role;
  final DateTime joinedAt;

  const OrganizationMember({
    required this.userId,
    required this.nickname,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });
}

abstract final class OrganizationAdministrationPolicy {
  static Set<OrganizationRole> assignableRoles(OrganizationRole actorRole) {
    switch (actorRole) {
      case OrganizationRole.owner:
        return {
          OrganizationRole.admin,
          OrganizationRole.employee,
          OrganizationRole.customer,
        };
      case OrganizationRole.admin:
        return {
          OrganizationRole.employee,
          OrganizationRole.customer,
        };
      case OrganizationRole.employee:
      case OrganizationRole.customer:
      case OrganizationRole.personal:
        return const {};
    }
  }

  static bool canAssign({
    required OrganizationRole actorRole,
    required OrganizationRole? currentRole,
    required OrganizationRole requestedRole,
  }) {
    if (!assignableRoles(actorRole).contains(requestedRole)) return false;
    if (currentRole == OrganizationRole.owner) return false;
    if (actorRole == OrganizationRole.admin &&
        currentRole == OrganizationRole.admin) {
      return false;
    }
    return true;
  }
}
