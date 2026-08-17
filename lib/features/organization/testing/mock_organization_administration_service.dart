import '../domain/organization_access.dart';
import '../domain/organization_administration_service.dart';
import '../domain/organization_member.dart';

class MockOrganizationAdministrationService
    implements OrganizationAdministrationService {
  final Map<String, OrganizationUserProfile> profilesByNickname;
  final List<OrganizationMember> members;
  final List<OrganizationParticipant> participants;
  String createdOrganizationId;
  String? lastCreatedOrganizationName;
  ({
    String organizationId,
    String userId,
    OrganizationRole role
  })? lastAssignment;
  ({
    String organizationId,
    String userId,
    OrganizationRole role,
    Set<OrganizationMemberFunction> functions,
  })? lastMemberUpdate;
  ({String organizationId, String userId})? lastMemberRemoval;
  ({
    String organizationId,
    String email,
    String nickname,
    String displayName,
    OrganizationRole role,
    Set<OrganizationMemberFunction> functions,
    String? customerId,
  })? lastInvitation;
  String? lastCancelledInvitationId;
  CurrentOrganizationInvitation? pendingCurrentInvitation;
  bool invitationAccepted;

  MockOrganizationAdministrationService({
    Map<String, OrganizationUserProfile>? profilesByNickname,
    List<OrganizationMember>? members,
    List<OrganizationParticipant>? participants,
    this.createdOrganizationId = 'mock-organization-1',
    this.pendingCurrentInvitation,
    this.invitationAccepted = false,
  })  : profilesByNickname = profilesByNickname ?? {},
        members = members ?? [],
        participants = participants ?? [];

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
  Future<List<OrganizationParticipant>> listParticipants(
    String organizationId,
  ) async {
    if (participants.isNotEmpty) return List.unmodifiable(participants);
    return members
        .map(
          (member) => OrganizationParticipant(
            id: member.userId,
            userId: member.userId,
            email: member.email,
            nickname: member.nickname,
            displayName: member.displayName,
            role: member.role,
            functions: member.functions,
            status: OrganizationParticipantStatus.active,
            emailSent: true,
            createdAt: member.joinedAt,
          ),
        )
        .toList();
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

  @override
  Future<void> updateMember({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
    required Set<OrganizationMemberFunction> functions,
  }) async {
    lastMemberUpdate = (
      organizationId: organizationId,
      userId: userId,
      role: role,
      functions: functions,
    );
  }

  @override
  Future<void> removeMember({
    required String organizationId,
    required String userId,
  }) async {
    lastMemberRemoval = (
      organizationId: organizationId,
      userId: userId,
    );
  }

  @override
  Future<OrganizationInvitationResult> inviteMember({
    required String organizationId,
    required String email,
    required String nickname,
    required String displayName,
    required OrganizationRole role,
    required Set<OrganizationMemberFunction> functions,
    String? customerId,
  }) async {
    lastInvitation = (
      organizationId: organizationId,
      email: email,
      nickname: nickname,
      displayName: displayName,
      role: role,
      functions: functions,
      customerId: customerId,
    );
    return OrganizationInvitationResult(
      invitationId: 'mock-invitation-1',
      email: email,
      nickname: nickname,
      existingAccount: false,
      emailSent: true,
    );
  }

  @override
  Future<void> cancelInvitation(String invitationId) async {
    lastCancelledInvitationId = invitationId;
  }

  @override
  Future<CurrentOrganizationInvitation?> currentInvitation() async =>
      pendingCurrentInvitation;

  @override
  Future<bool> acceptCurrentInvitation() async => invitationAccepted;
}
