enum ChatThreadKind {
  personal,
  organization,
  job,
  direct,
}

class ChatThread {
  final String id;
  final String title;
  final ChatThreadKind kind;
  final String? organizationId;
  final String? jobId;
  final DateTime updatedAt;
  final bool customerShared;
  final bool canManageCustomerAccess;

  const ChatThread({
    required this.id,
    required this.title,
    required this.kind,
    required this.updatedAt,
    this.organizationId,
    this.jobId,
    this.customerShared = false,
    this.canManageCustomerAccess = false,
  });
}
