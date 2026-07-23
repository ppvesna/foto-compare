import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/organization_access.dart';
import '../domain/organization_access_service.dart';

class SupabaseOrganizationAccessService implements OrganizationAccessService {
  final SupabaseClient client;

  const SupabaseOrganizationAccessService(this.client);

  @override
  Future<OrganizationAccess> load() async {
    final user = client.auth.currentUser;
    if (user == null) return OrganizationAccess.legacyPersonal();

    try {
      final remote = await client.rpc('current_organization_access_v2');
      final access = _fromSnapshot(remote);
      if (access != null) return access;
    } catch (_) {
      // Organization v2 is optional until migration 006 is installed.
    }

    try {
      final membership = await client
          .from('organization_members')
          .select('organization_id, role, organizations(name)')
          .eq('user_id', user.id)
          .maybeSingle();
      if (membership != null) {
        final access = _fromSnapshot({
          'organization_id': membership['organization_id'],
          'organization_role': membership['role'],
          'organization_name': (membership['organizations'] as Map?)?['name'],
        });
        if (access != null) return access;
      }
    } catch (_) {
      // Direct membership lookup is a compatibility fallback protected by RLS.
    }

    try {
      final remote = await client.rpc('current_access_snapshot');
      final access = _fromSnapshot(remote);
      if (access != null) return access;
    } catch (_) {
      // The access migration is optional during the compatibility stage.
    }

    final metadata = user.appMetadata;
    final organizationId = metadata['organization_id'] as String?;
    final organizationName = metadata['organization_name'] as String?;
    final roleName = metadata['organization_role'] as String?;
    if (organizationId == null || roleName == null) {
      return OrganizationAccess.legacyPersonal();
    }

    return OrganizationAccess.forRole(
      organizationId: organizationId,
      organizationName: organizationName,
      role: OrganizationRoleCodec.fromStoredName(
        roleName,
        fallback: OrganizationRole.customer,
      ),
    );
  }

  OrganizationAccess? _fromSnapshot(Object? response) {
    Object? value = response;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    if (value is List && value.isNotEmpty) value = value.first;
    if (value is! Map) return null;

    final snapshot = Map<String, dynamic>.from(value);
    final organizationId = snapshot['organization_id'] as String?;
    final organizationName = snapshot['organization_name'] as String?;
    final roleName =
        (snapshot['organization_role'] ?? snapshot['role']) as String?;
    if (organizationId == null || roleName == null) return null;

    return OrganizationAccess.forRole(
      organizationId: organizationId,
      organizationName: organizationName,
      role: OrganizationRoleCodec.fromStoredName(
        roleName,
        fallback: OrganizationRole.customer,
      ),
    );
  }
}
