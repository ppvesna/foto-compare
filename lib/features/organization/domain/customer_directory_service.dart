import 'organization_customer.dart';

abstract interface class CustomerDirectoryService {
  Future<List<OrganizationCustomer>> listCustomers(
    String organizationId, {
    bool includeArchived = false,
  });

  Future<List<OrganizationCustomerRequest>> listPendingRequests(
    String organizationId,
  );

  Future<String> saveCustomer({
    required String organizationId,
    required String code,
    required String name,
    String? managerUserId,
    String? customerUserId,
    String? customerId,
  });

  Future<void> archiveCustomer(String customerId);

  Future<void> restoreCustomer(String customerId);

  Future<List<OrganizationCustomerJob>> listCustomerJobs(String customerId);

  Future<void> resolveRequest({
    required String requestId,
    required String customerId,
  });
}
