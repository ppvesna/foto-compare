class CustomerShareCandidate {
  final String jobId;
  final String jobNumber;
  final String customerName;
  final bool customerShared;

  const CustomerShareCandidate({
    required this.jobId,
    required this.jobNumber,
    required this.customerName,
    required this.customerShared,
  });

  CustomerShareCandidate copyWith({
    bool? customerShared,
  }) {
    return CustomerShareCandidate(
      jobId: jobId,
      jobNumber: jobNumber,
      customerName: customerName,
      customerShared: customerShared ?? this.customerShared,
    );
  }
}
