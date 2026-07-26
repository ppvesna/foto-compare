import 'organization_access.dart';

enum OrganizationMemberFunction {
  manager,
  designer,
  inspectionSpecialist,
}

extension OrganizationMemberFunctionLabel on OrganizationMemberFunction {
  String get label {
    switch (this) {
      case OrganizationMemberFunction.manager:
        return 'Менеджер';
      case OrganizationMemberFunction.designer:
        return 'Дизайнер';
      case OrganizationMemberFunction.inspectionSpecialist:
        return 'Специалист проверки';
    }
  }
}

enum OrganizationParticipantStatus { active, pending }

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
  final String email;
  final String nickname;
  final String displayName;
  final OrganizationRole role;
  final Set<OrganizationMemberFunction> functions;
  final DateTime joinedAt;

  const OrganizationMember({
    required this.userId,
    this.email = '',
    required this.nickname,
    required this.displayName,
    required this.role,
    this.functions = const {},
    required this.joinedAt,
  });
}

class OrganizationParticipant {
  final String id;
  final String? userId;
  final String email;
  final String nickname;
  final String displayName;
  final OrganizationRole role;
  final Set<OrganizationMemberFunction> functions;
  final OrganizationParticipantStatus status;
  final bool emailSent;
  final DateTime createdAt;

  const OrganizationParticipant({
    required this.id,
    this.userId,
    required this.email,
    required this.nickname,
    required this.displayName,
    required this.role,
    required this.functions,
    required this.status,
    required this.emailSent,
    required this.createdAt,
  });

  bool get isPending => status == OrganizationParticipantStatus.pending;
}

class OrganizationInvitationResult {
  final String invitationId;
  final String email;
  final String nickname;
  final bool existingAccount;
  final bool emailSent;

  const OrganizationInvitationResult({
    required this.invitationId,
    required this.email,
    required this.nickname,
    required this.existingAccount,
    required this.emailSent,
  });
}

class CurrentOrganizationInvitation {
  final String id;
  final String organizationId;
  final String organizationName;
  final String nickname;
  final String displayName;
  final OrganizationRole role;
  final Set<OrganizationMemberFunction> functions;

  const CurrentOrganizationInvitation({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.nickname,
    required this.displayName,
    required this.role,
    required this.functions,
  });
}

abstract final class OrganizationMemberFunctionCodec {
  static OrganizationMemberFunction? fromStoredName(String? value) {
    switch (value) {
      case 'manager':
        return OrganizationMemberFunction.manager;
      case 'designer':
        return OrganizationMemberFunction.designer;
      case 'inspectionSpecialist':
        return OrganizationMemberFunction.inspectionSpecialist;
      default:
        return null;
    }
  }
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
