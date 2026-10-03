enum ChatThreadKind {
  personal,
  organization,
  team,
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
  final String jobStage;
  final String jobFlowState;
  final String customerName;
  final int unreadCount;
  final DateTime? archivedAt;
  final bool canManage;

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
    this.jobStage = '',
    this.jobFlowState = '',
    this.customerName = '',
    this.unreadCount = 0,
    this.archivedAt,
    this.canManage = false,
  });

  bool get isArchivedJob =>
      (kind == ChatThreadKind.jobCustomer ||
          kind == ChatThreadKind.jobInternal) &&
      (jobStatus == 'completed' || jobStatus == 'archived');

  bool get isArchivedTeam => kind == ChatThreadKind.team && archivedAt != null;

  ChatThread copyWith({
    DateTime? updatedAt,
    bool? customerShared,
    bool? canManageCustomerAccess,
    String? jobStatus,
    String? jobStage,
    String? jobFlowState,
    String? customerName,
    int? unreadCount,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    bool? canManage,
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
      jobStage: jobStage ?? this.jobStage,
      jobFlowState: jobFlowState ?? this.jobFlowState,
      customerName: customerName ?? this.customerName,
      unreadCount: unreadCount ?? this.unreadCount,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
      canManage: canManage ?? this.canManage,
    );
  }
}
