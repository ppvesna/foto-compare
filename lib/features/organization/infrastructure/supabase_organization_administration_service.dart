import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/organization_access.dart';
import '../domain/organization_administration_service.dart';
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

  Map<String, dynamic>? _firstRow(Object? response) {
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    if (response is Map) return Map<String, dynamic>.from(response);
    return null;
  }
}
