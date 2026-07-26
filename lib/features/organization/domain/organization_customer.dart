class OrganizationCustomer {
  final String id;
  final String organizationId;
  final String code;
  final String name;
  final bool active;
  final String? primaryManagerUserId;
  final String primaryManagerNickname;
  final String? customerUserId;
  final String customerUserNickname;
  final String? createdByUserId;
  final String createdByNickname;
  final String? updatedByUserId;
  final String updatedByNickname;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OrganizationCustomer({
    required this.id,
    required this.organizationId,
    required this.code,
    required this.name,
    required this.active,
    this.primaryManagerUserId,
    this.primaryManagerNickname = '',
    this.customerUserId,
    this.customerUserNickname = '',
    this.createdByUserId,
    this.createdByNickname = '',
    this.updatedByUserId,
    this.updatedByNickname = '',
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayLabel => code.isEmpty ? name : '$code · $name';
}

class OrganizationCustomerRequest {
  final String id;
  final String organizationId;
  final String requestedName;
  final String workNumber;
  final String? requestedByUserId;
  final String requestedByNickname;
  final DateTime createdAt;

  const OrganizationCustomerRequest({
    required this.id,
    required this.organizationId,
    required this.requestedName,
    required this.workNumber,
    this.requestedByUserId,
    this.requestedByNickname = '',
    required this.createdAt,
  });
}
