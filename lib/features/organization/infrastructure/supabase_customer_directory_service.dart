import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/customer_directory_service.dart';
import '../domain/organization_customer.dart';

class SupabaseCustomerDirectoryService implements CustomerDirectoryService {
  final SupabaseClient client;

  const SupabaseCustomerDirectoryService(this.client);

  @override
  Future<List<OrganizationCustomer>> listCustomers(
    String organizationId, {
    bool includeArchived = false,
  }) async {
    final response = await client.rpc(
      'list_organization_customers_v1',
      params: {
        'target_organization': organizationId,
        'include_archived': includeArchived,
      },
    );
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .map(
          (row) => OrganizationCustomer(
            id: row['customer_id'] as String,
            organizationId: organizationId,
            code: row['code'] as String? ?? '',
            name: row['name'] as String? ?? '',
            active: row['active'] == true,
            primaryManagerUserId: row['primary_manager_user_id'] as String?,
            primaryManagerNickname:
                row['primary_manager_nickname'] as String? ?? '',
            customerUserId: row['customer_user_id'] as String?,
            customerUserNickname:
                row['customer_user_nickname'] as String? ?? '',
            createdByUserId: row['created_by_user_id'] as String?,
            createdByNickname: row['created_by_nickname'] as String? ?? '',
            updatedByUserId: row['updated_by_user_id'] as String?,
            updatedByNickname: row['updated_by_nickname'] as String? ?? '',
            createdAt: _date(row['created_at']),
            updatedAt: _date(row['updated_at']),
          ),
        )
        .toList();
  }

  @override
  Future<List<OrganizationCustomerRequest>> listPendingRequests(
    String organizationId,
  ) async {
    final response = await client.rpc(
      'list_customer_requests_v1',
      params: {'target_organization': organizationId},
    );
    if (response is! List) return const [];
    return response
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .map(
          (row) => OrganizationCustomerRequest(
            id: row['request_id'] as String,
            organizationId: organizationId,
            requestedName: row['requested_name'] as String? ?? '',
            workNumber: row['work_number'] as String? ?? '',
            requestedByUserId: row['requested_by_user_id'] as String?,
            requestedByNickname: row['requested_by_nickname'] as String? ?? '',
            createdAt: _date(row['created_at']),
          ),
        )
        .toList();
  }

  @override
  Future<String> saveCustomer({
    required String organizationId,
    required String code,
    required String name,
    String? managerUserId,
    String? customerUserId,
    String? customerId,
  }) async {
    final response = await client.rpc(
      'save_organization_customer_v1',
      params: {
        'target_organization': organizationId,
        'target_code': code.trim(),
        'target_name': name.trim(),
        'target_manager_user': managerUserId,
        'target_customer_user': customerUserId,
        'target_customer': customerId,
      },
    );
    if (response is String && response.isNotEmpty) return response;
    throw StateError('Supabase did not return the customer ID');
  }

  @override
  Future<void> archiveCustomer(String customerId) async {
    await client.rpc(
      'archive_organization_customer_v1',
      params: {'target_customer': customerId},
    );
  }

  @override
  Future<void> resolveRequest({
    required String requestId,
    required String customerId,
  }) async {
    await client.rpc(
      'resolve_customer_request_v1',
      params: {
        'target_request': requestId,
        'target_customer': customerId,
      },
    );
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
