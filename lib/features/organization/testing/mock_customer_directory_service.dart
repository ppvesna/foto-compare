import '../domain/customer_directory_service.dart';
import '../domain/organization_customer.dart';

class MockCustomerDirectoryService implements CustomerDirectoryService {
  final List<OrganizationCustomer> customers;
  final List<OrganizationCustomerRequest> requests;
  String? archivedCustomerId;
  ({String requestId, String customerId})? resolvedRequest;
  ({
    String organizationId,
    String code,
    String name,
    String? managerUserId,
    String? customerUserId,
    String? customerId,
  })? savedCustomer;

  MockCustomerDirectoryService({
    List<OrganizationCustomer>? customers,
    List<OrganizationCustomerRequest>? requests,
  })  : customers = customers ?? [],
        requests = requests ?? [];

  @override
  Future<List<OrganizationCustomer>> listCustomers(
    String organizationId, {
    bool includeArchived = false,
  }) async {
    return customers
        .where(
          (customer) =>
              customer.organizationId == organizationId &&
              (includeArchived || customer.active),
        )
        .toList();
  }

  @override
  Future<List<OrganizationCustomerRequest>> listPendingRequests(
    String organizationId,
  ) async {
    return requests
        .where((request) => request.organizationId == organizationId)
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
    savedCustomer = (
      organizationId: organizationId,
      code: code,
      name: name,
      managerUserId: managerUserId,
      customerUserId: customerUserId,
      customerId: customerId,
    );
    return customerId ?? 'mock-customer-${customers.length + 1}';
  }

  @override
  Future<void> archiveCustomer(String customerId) async {
    archivedCustomerId = customerId;
  }

  @override
  Future<void> resolveRequest({
    required String requestId,
    required String customerId,
  }) async {
    resolvedRequest = (requestId: requestId, customerId: customerId);
  }
}
