enum ProductionJobStatus {
  draft,
  active,
  awaitingApproval,
  approved,
  completed,
  archived,
}

class ProductionJob {
  final String id;
  final String? organizationId;
  final String number;
  final String title;
  final String referenceId;
  final String createdBy;
  final ProductionJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductionJob({
    required this.id,
    required this.organizationId,
    required this.number,
    required this.title,
    required this.referenceId,
    required this.createdBy,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
}
