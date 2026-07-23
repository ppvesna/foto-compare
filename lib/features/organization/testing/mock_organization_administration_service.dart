import '../domain/organization_access.dart';
import '../domain/organization_administration_service.dart';
import '../domain/organization_member.dart';

class MockOrganizationAdministrationService
    implements OrganizationAdministrationService {
  final Map<String, OrganizationUserProfile> profilesByNickname;
  final List<OrganizationMember> members;
  String createdOrganizationId;
  String? lastCreatedOrganizationName;
  ({
    String organizationId,
    String userId,
    OrganizationRole role
  })? lastAssignment;

  MockOrganizationAdministrationService({
    Map<String, OrganizationUserProfile>? profilesByNickname,
    List<OrganizationMember>? members,
    this.createdOrganizationId = 'mock-organization-1',
  })  : profilesByNickname = profilesByNickname ?? {},
        members = members ?? [];

  @override
  Future<String> createOrganization({required String name}) async {
    lastCreatedOrganizationName = name;
    return createdOrganizationId;
  }

  @override
  Future<OrganizationUserProfile?> findUserByNickname(String nickname) async {
    return profilesByNickname[nickname.trim().toLowerCase()];
  }

  @override
  Future<List<OrganizationMember>> listMembers(String organizationId) async {
    return List.unmodifiable(members);
  }

  @override
  Future<void> assignMember({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  }) async {
    lastAssignment = (
      organizationId: organizationId,
      userId: userId,
      role: role,
    );
  }
}
