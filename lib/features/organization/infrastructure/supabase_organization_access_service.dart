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
      final remote = await client.rpc('current_access_snapshot');
      if (remote is Map) {
        final snapshot = Map<String, dynamic>.from(remote);
        final organizationId = snapshot['organization_id'] as String?;
        final roleName = snapshot['organization_role'] as String?;
        if (organizationId != null && roleName != null) {
          return OrganizationAccess.forRole(
            organizationId: organizationId,
            role: _parseRole(roleName),
          );
        }
      }
    } catch (_) {
      // The access migration is optional during the compatibility stage.
    }

    final metadata = user.appMetadata;
    final organizationId = metadata['organization_id'] as String?;
    final roleName = metadata['organization_role'] as String?;
    if (organizationId == null || roleName == null) {
      return OrganizationAccess.legacyPersonal();
    }

    return OrganizationAccess.forRole(
      organizationId: organizationId,
      role: _parseRole(roleName),
    );
  }

  OrganizationRole _parseRole(String value) {
    for (final role in OrganizationRole.values) {
      if (role.name == value.toLowerCase()) return role;
    }
    return OrganizationRole.viewer;
  }
}
