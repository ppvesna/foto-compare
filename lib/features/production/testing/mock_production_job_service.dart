import '../domain/production_job_service.dart';

class MockProductionJobService implements ProductionJobService {
  ProductionJobContext? result;
  ({
    String organizationId,
    String jobNumber,
    String? customerId,
    String? requestedCustomerName,
  })? lastOpenJob;

  MockProductionJobService({this.result});

  @override
  Future<ProductionJobContext> openJob({
    required String organizationId,
    required String jobNumber,
    String? customerId,
    String? requestedCustomerName,
  }) async {
    lastOpenJob = (
      organizationId: organizationId,
      jobNumber: jobNumber,
      customerId: customerId,
      requestedCustomerName: requestedCustomerName,
    );
    return result ??
        ProductionJobContext(
          jobId: 'mock-job-1',
          jobNumber: jobNumber,
          customerId: customerId,
          customerName: requestedCustomerName ?? 'Mock customer',
          customerConfirmed: customerId != null,
        );
  }
}
