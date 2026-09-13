import '../domain/customer_directory_service.dart';
import '../domain/organization_customer.dart';

class MockCustomerDirectoryService implements CustomerDirectoryService {
  final List<OrganizationCustomer> customers;
  final List<OrganizationCustomerRequest> requests;
  final List<OrganizationCustomerJob> jobs;
  final bool requireExplicitCode;
  String? archivedCustomerId;
  String? restoredCustomerId;
  ({String requestId, String customerId})? resolvedRequest;
  ({
    String customerId,
    String? userId,
    String? invitationId,
    String email,
    String nickname,
    String displayName,
  })? updatedRepresentative;
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
    List<OrganizationCustomerJob>? jobs,
    this.requireExplicitCode = false,
  })  : customers = customers ?? [],
        requests = requests ?? [],
        jobs = jobs ?? [];

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
    if (requireExplicitCode && code.isEmpty) {
      throw StateError('Customer code must contain 1-32 characters');
    }
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
  Future<void> restoreCustomer(String customerId) async {
    restoredCustomerId = customerId;
  }

  @override
  Future<void> updateRepresentative({
    required String customerId,
    String? userId,
    String? invitationId,
    required String email,
    required String nickname,
    required String displayName,
  }) async {
    updatedRepresentative = (
      customerId: customerId,
      userId: userId,
      invitationId: invitationId,
      email: email,
      nickname: nickname,
      displayName: displayName,
    );
  }

  @override
  Future<List<OrganizationCustomerJob>> listCustomerJobs(
    String customerId,
  ) async =>
      List.unmodifiable(jobs);

  @override
  Future<void> resolveRequest({
    required String requestId,
    required String customerId,
  }) async {
    resolvedRequest = (requestId: requestId, customerId: customerId);
    requests.removeWhere((request) => request.id == requestId);
  }
}
