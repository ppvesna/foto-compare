class ProductionJobContext {
  final String jobId;
  final String jobNumber;
  final String? customerId;
  final String customerName;
  final bool customerConfirmed;
  final String? customerRequestId;

  const ProductionJobContext({
    required this.jobId,
    required this.jobNumber,
    this.customerId,
    required this.customerName,
    required this.customerConfirmed,
    this.customerRequestId,
  });
}

abstract interface class ProductionJobService {
  Future<ProductionJobContext> openJob({
    required String organizationId,
    required String jobNumber,
    String? customerId,
    String? requestedCustomerName,
  });
}
