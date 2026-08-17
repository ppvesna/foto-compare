import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/organization_access.dart';
import '../domain/organization_administration_service.dart';
import '../domain/organization_invitation_exception.dart';
import '../domain/organization_member.dart';

class SupabaseOrganizationAdministrationService
    implements OrganizationAdministrationService {
  final SupabaseClient client;

  const SupabaseOrganizationAdministrationService(this.client);

  @override
  Future<String> createOrganization({required String name}) async {
    if (client.auth.currentSession != null) {
      await client.auth.refreshSession();
    }
    final response = await client.rpc(
      'create_organization_v2',
      params: {'requested_name': name.trim()},
    );
    if (response is String && response.isNotEmpty) return response;
    throw StateError('Supabase did not return the organization ID');
  }

  @override
  Future<OrganizationUserProfile?> findUserByNickname(String nickname) async {
    final response = await client.rpc(
      'find_user_profile_by_nickname_v2',
      params: {'target_nickname': nickname.trim().toLowerCase()},
    );
    final row = _firstRow(response);
    if (row == null) return null;
    return OrganizationUserProfile(
      userId: row['user_id'] as String,
      nickname: row['nickname'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      organizationName: row['organization_name'] as String? ?? '',
    );
  }

  @override
  Future<List<OrganizationMember>> listMembers(String organizationId) async {
    final response = await client.rpc(
      'list_organization_members_v2',
      params: {'target_organization': organizationId},
    );
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .map(
          (row) => OrganizationMember(
            userId: row['user_id'] as String,
            nickname: row['nickname'] as String? ?? '',
            displayName: row['display_name'] as String? ?? '',
            role: OrganizationRoleCodec.fromStoredName(
              row['role'] as String?,
              fallback: OrganizationRole.customer,
            ),
            joinedAt: DateTime.tryParse(row['joined_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        )
        .toList();
  }

  @override
  Future<List<OrganizationParticipant>> listParticipants(
    String organizationId,
  ) async {
    try {
      final response = await client.rpc(
        'list_organization_participants_v1',
        params: {'target_organization': organizationId},
      );
      if (response is! List) return const [];
      return response
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .map(_participantFromRow)
          .toList();
    } catch (_) {
      final members = await listMembers(organizationId);
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
  }

  @override
  Future<void> assignMember({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
  }) async {
    await client.rpc(
      'assign_organization_member_v2',
      params: {
        'target_organization': organizationId,
        'target_user': userId,
        'target_role': role.name,
      },
    );
  }

  @override
  Future<void> updateMember({
    required String organizationId,
    required String userId,
    required OrganizationRole role,
    required Set<OrganizationMemberFunction> functions,
  }) async {
    await client.rpc(
      'update_organization_member_v1',
      params: {
        'target_organization': organizationId,
        'target_user': userId,
        'target_role': role.name,
        'target_functions': functions.map((value) => value.name).toList(),
      },
    );
  }

  @override
  Future<void> removeMember({
    required String organizationId,
    required String userId,
  }) async {
    await client.rpc(
      'remove_organization_member_v1',
      params: {
        'target_organization': organizationId,
        'target_user': userId,
      },
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
    late final FunctionResponse response;
    try {
      response = await client.functions.invoke(
        'invite-organization-member',
        body: {
          'organizationId': organizationId,
          'email': email.trim().toLowerCase(),
          'nickname': nickname.trim().toLowerCase(),
          'displayName': displayName.trim(),
          'role': role.name,
          'functions': functions.map((value) => value.name).toList(),
          if (customerId != null) 'customerId': customerId,
          if (kIsWeb) 'redirectUrl': Uri.base.origin,
        },
      );
    } on FunctionException catch (error) {
      throw OrganizationInvitationException.fromResponse(
        details: error.details,
        status: error.status,
      );
    }
    final data = response.data;
    if (data is! Map) {
      throw const OrganizationInvitationException(
        code: 'invalid_response',
        message: 'Invitation server returned an invalid response',
      );
    }
    final result = Map<String, dynamic>.from(data);
    if (result['error'] != null) {
      throw OrganizationInvitationException.fromResponse(
        details: result,
        status: response.status,
      );
    }
    return OrganizationInvitationResult(
      invitationId: result['invitationId'] as String,
      email: result['email'] as String? ?? email.trim().toLowerCase(),
      nickname: result['nickname'] as String? ?? nickname.trim().toLowerCase(),
      existingAccount: result['isRegistered'] == true,
      emailSent: result['emailSent'] == true,
    );
  }

  @override
  Future<void> cancelInvitation(String invitationId) async {
    await client.rpc(
      'cancel_organization_invitation_v1',
      params: {'target_invitation': invitationId},
    );
  }

  @override
  Future<CurrentOrganizationInvitation?> currentInvitation() async {
    try {
      final response = await client.rpc(
        'current_organization_invitation_v1',
      );
      if (response is! Map) return null;
      final row = Map<String, dynamic>.from(response);
      final rawFunctions = row['employee_functions'];
      final functions = rawFunctions is List
          ? rawFunctions
              .map((value) =>
                  OrganizationMemberFunctionCodec.fromStoredName('$value'))
              .whereType<OrganizationMemberFunction>()
              .toSet()
          : <OrganizationMemberFunction>{};
      return CurrentOrganizationInvitation(
        id: row['invitation_id'] as String,
        organizationId: row['organization_id'] as String,
        organizationName: row['organization_name'] as String? ?? '',
        nickname: row['nickname'] as String? ?? '',
        displayName: row['display_name'] as String? ?? '',
        role: OrganizationRoleCodec.fromStoredName(
          row['role'] as String?,
          fallback: OrganizationRole.customer,
        ),
        functions: functions,
      );
    } catch (_) {
      // Migration 010 is optional during the staged rollout.
      return null;
    }
  }

  @override
  Future<bool> acceptCurrentInvitation() async {
    try {
      final response = await client.rpc(
        'accept_current_organization_invitation_v1',
      );
      return response != null;
    } catch (_) {
      // Migration 010 is optional during the staged rollout.
      return false;
    }
  }

  OrganizationParticipant _participantFromRow(Map<String, dynamic> row) {
    final rawFunctions = row['employee_functions'];
    final functions = rawFunctions is List
        ? rawFunctions
            .map((value) =>
                OrganizationMemberFunctionCodec.fromStoredName('$value'))
            .whereType<OrganizationMemberFunction>()
            .toSet()
        : <OrganizationMemberFunction>{};
    final status = row['status'] == 'pending'
        ? OrganizationParticipantStatus.pending
        : OrganizationParticipantStatus.active;
    return OrganizationParticipant(
      id: row['participant_id'] as String,
      userId: row['user_id'] as String?,
      email: row['email'] as String? ?? '',
      nickname: row['nickname'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      role: OrganizationRoleCodec.fromStoredName(
        row['role'] as String?,
        fallback: OrganizationRole.customer,
      ),
      functions: functions,
      status: status,
      emailSent: row['delivery_status'] == 'sent',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic>? _firstRow(Object? response) {
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    if (response is Map) return Map<String, dynamic>.from(response);
    return null;
  }
}
