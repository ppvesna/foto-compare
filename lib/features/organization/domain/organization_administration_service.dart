import 'organization_access.dart';
import 'organization_member.dart';

abstract interface class OrganizationAdministrationService {
  Future<String> createOrganization({required String name});

  Future<OrganizationUserProfile?> findUserByNickname(String nickname);

  Future<List<OrganizationMember>> listMembers(String organizationId);

  Future<void> assignMember({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  });
}
