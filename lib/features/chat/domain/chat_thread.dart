enum ChatThreadKind {
  personal,
  organization,
  jobCustomer,
  jobInternal,
  direct,
  service,
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
  final String jobStatus;
  final String customerName;
  final int unreadCount;

  const ChatThread({
    required this.id,
    required this.title,
    required this.kind,
    required this.updatedAt,
    this.organizationId,
    this.jobId,
    this.customerShared = false,
    this.canManageCustomerAccess = false,
    this.jobStatus = '',
    this.customerName = '',
    this.unreadCount = 0,
  });

  bool get isArchivedJob =>
      (kind == ChatThreadKind.jobCustomer ||
          kind == ChatThreadKind.jobInternal) &&
      (jobStatus == 'completed' || jobStatus == 'archived');

  ChatThread copyWith({
    DateTime? updatedAt,
    bool? customerShared,
    bool? canManageCustomerAccess,
    String? jobStatus,
    String? customerName,
    int? unreadCount,
  }) {
    return ChatThread(
      id: id,
      title: title,
      kind: kind,
      organizationId: organizationId,
      jobId: jobId,
      updatedAt: updatedAt ?? this.updatedAt,
      customerShared: customerShared ?? this.customerShared,
      canManageCustomerAccess:
          canManageCustomerAccess ?? this.canManageCustomerAccess,
      jobStatus: jobStatus ?? this.jobStatus,
      customerName: customerName ?? this.customerName,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
