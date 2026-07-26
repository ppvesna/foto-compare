import 'organization_access.dart';
import 'organization_member.dart';

abstract interface class OrganizationAdministrationService {
  Future<String> createOrganization({required String name});

  Future<OrganizationUserProfile?> findUserByNickname(String nickname);

  Future<List<OrganizationMember>> listMembers(String organizationId);

  Future<List<OrganizationParticipant>> listParticipants(
    String organizationId,
  );

  Future<void> assignMember({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  });

  Future<OrganizationInvitationResult> inviteMember({
    required String organizationId,
    required String email,
    required String nickname,
    required String displayName,
    required OrganizationRole role,
    required Set<OrganizationMemberFunction> functions,
  });

  Future<void> cancelInvitation(String invitationId);

  Future<CurrentOrganizationInvitation?> currentInvitation();

  Future<bool> acceptCurrentInvitation();
}
