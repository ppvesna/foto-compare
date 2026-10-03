import 'dart:async';
import 'dart:typed_data';

import '../domain/chat_attachment.dart';
import '../domain/chat_contact.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/chat_thread.dart';
import '../domain/customer_share_candidate.dart';

class MockChatRepository implements ChatRepository {
  final String currentUserId;
  final String currentNickname;
  final String currentDisplayName;
  final List<ChatThread> threads;
  final Map<String, List<ChatMessage>> messages;
  final List<CustomerShareCandidate> customerShareCandidates;
  final List<ChatContact> contacts;
  final Map<String, List<ChatTeamMember>> teamMembers;
  final Map<String, StreamController<List<ChatMessage>>> _controllers = {};
  final StreamController<void> _threadChangesController =
      StreamController<void>.broadcast();
  final Map<String, Uint8List> _attachmentBytes = {};
  int _messageSequence = 0;

  MockChatRepository({
    this.currentUserId = 'mock-user',
    this.currentNickname = 'mock_user',
    this.currentDisplayName = 'Mock User',
    List<ChatThread>? threads,
    Map<String, List<ChatMessage>>? messages,
    List<CustomerShareCandidate>? customerShareCandidates,
    List<ChatContact>? contacts,
    Map<String, List<ChatTeamMember>>? teamMembers,
  })  : threads = threads ?? [],
        messages = messages ?? {},
        customerShareCandidates = customerShareCandidates ?? [],
        contacts = contacts ?? [],
        teamMembers = teamMembers ?? {};

  @override
  Future<void> ensureDefaultThreads() async {
    if (threads.isNotEmpty) return;
    final now = DateTime.now().toUtc();
    threads.add(
      ChatThread(
        id: 'mock-personal-thread',
        title: 'Личные заметки',
        kind: ChatThreadKind.personal,
        updatedAt: now,
      ),
    );
    messages.putIfAbsent('mock-personal-thread', () => []);
  }

  @override
  Future<List<ChatThread>> listThreads() async {
    return List.unmodifiable(threads);
  }

  @override
  Stream<void> watchThreadChanges() => _threadChangesController.stream;

  void notifyThreadChanged() => _threadChangesController.add(null);

  @override
  Future<void> markThreadRead(String threadId) async {
    final index = threads.indexWhere((thread) => thread.id == threadId);
    if (index < 0) throw StateError('Chat thread not found');
    threads[index] = threads[index].copyWith(unreadCount: 0);
  }

  @override
  Future<List<ChatContact>> searchContacts(
    String query, {
    int limit = 30,
  }) async {
    final normalized = query.trim().toLowerCase();
    return contacts
        .where((contact) =>
            normalized.isEmpty ||
            '${contact.displayName} ${contact.nickname} ${contact.roleLabel}'
                .toLowerCase()
                .contains(normalized))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<String> openDirectThread(String userId) async {
    final contact = contacts.where((item) => item.userId == userId).firstOrNull;
    if (contact == null) throw StateError('Chat contact not found');
    final existing = threads.where((thread) =>
        thread.kind == ChatThreadKind.direct && thread.id == 'direct-$userId');
    if (existing.isNotEmpty) return existing.first.id;
    final thread = ChatThread(
      id: 'direct-$userId',
      title: contact.label,
      kind: ChatThreadKind.direct,
      organizationId: 'mock-organization',
      updatedAt: DateTime.now().toUtc(),
    );
    threads.add(thread);
    messages.putIfAbsent(thread.id, () => []);
    notifyThreadChanged();
    return thread.id;
  }

  @override
  Future<List<ChatTeamMember>> listTeamMembers(String threadId) async =>
      List.unmodifiable(teamMembers[threadId] ?? const []);

  @override
  Future<String> createTeam({
    required String name,
    required List<String> memberUserIds,
  }) async {
    final id = 'mock-team-${threads.length + 1}';
    threads.add(ChatThread(
      id: id,
      title: name.trim(),
      kind: ChatThreadKind.team,
      organizationId: 'mock-organization',
      updatedAt: DateTime.now().toUtc(),
      canManage: true,
    ));
    teamMembers[id] = contacts
        .where((contact) => memberUserIds.contains(contact.userId))
        .map((contact) => ChatTeamMember(
              userId: contact.userId,
              displayName: contact.displayName,
              nickname: contact.nickname,
            ))
        .toList();
    messages[id] = [];
    notifyThreadChanged();
    return id;
  }

  @override
  Future<void> updateTeam({
    required String threadId,
    required String name,
    required List<String> memberUserIds,
  }) async {
    final index = threads.indexWhere((thread) => thread.id == threadId);
    if (index < 0 || threads[index].kind != ChatThreadKind.team) {
      throw StateError('Chat team not found');
    }
    final old = threads[index];
    threads[index] = ChatThread(
      id: old.id,
      title: name.trim(),
      kind: old.kind,
      organizationId: old.organizationId,
      updatedAt: DateTime.now().toUtc(),
      archivedAt: old.archivedAt,
      canManage: old.canManage,
      unreadCount: old.unreadCount,
    );
    teamMembers[threadId] = contacts
        .where((contact) => memberUserIds.contains(contact.userId))
        .map((contact) => ChatTeamMember(
              userId: contact.userId,
              displayName: contact.displayName,
              nickname: contact.nickname,
            ))
        .toList();
    notifyThreadChanged();
  }

  @override
  Future<void> archiveTeam(String threadId) async {
    final index = threads.indexWhere((thread) => thread.id == threadId);
    if (index < 0) throw StateError('Chat team not found');
    threads[index] = threads[index].copyWith(
      archivedAt: DateTime.now().toUtc(),
    );
    notifyThreadChanged();
  }

  @override
  Future<void> restoreTeam(String threadId) async {
    final index = threads.indexWhere((thread) => thread.id == threadId);
    if (index < 0) throw StateError('Chat team not found');
    threads[index] = threads[index].copyWith(clearArchivedAt: true);
    notifyThreadChanged();
  }

  @override
  Future<List<CustomerShareCandidate>> listCustomerShareCandidates() async {
    return List.unmodifiable(customerShareCandidates);
  }

  @override
  Future<void> setCustomerAccess({
    required String jobId,
    required bool shared,
  }) async {
    final candidateIndex = customerShareCandidates.indexWhere(
      (candidate) => candidate.jobId == jobId,
    );
    if (candidateIndex < 0) {
      throw StateError('Production job not found');
    }
    final candidate = customerShareCandidates[candidateIndex];
    customerShareCandidates[candidateIndex] = candidate.copyWith(
      customerShared: shared,
    );

    final threadIndexes = <int>[
      for (var index = 0; index < threads.length; index++)
        if (threads[index].jobId == jobId) index,
    ];
    if (threadIndexes.isNotEmpty) {
      final updatedAt = DateTime.now().toUtc();
      for (final threadIndex in threadIndexes) {
        final thread = threads[threadIndex];
        threads[threadIndex] = thread.copyWith(
          updatedAt: updatedAt,
          customerShared: shared,
          canManageCustomerAccess: true,
        );
      }
      notifyThreadChanged();
      return;
    }
    if (!shared) return;

    final thread = ChatThread(
      id: 'mock-job-thread-$jobId',
      title: 'Работа № ${candidate.jobNumber}',
      kind: ChatThreadKind.jobCustomer,
      jobId: jobId,
      updatedAt: DateTime.now().toUtc(),
      customerShared: true,
      canManageCustomerAccess: true,
    );
    threads.add(thread);
    messages.putIfAbsent(thread.id, () => []);
    notifyThreadChanged();
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String threadId, {
    int limit = 100,
  }) async {
    final source = messages[threadId] ?? const <ChatMessage>[];
    final start = source.length > limit ? source.length - limit : 0;
    return List.unmodifiable(source.sublist(start));
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId) async* {
    yield await listMessages(threadId);
    final controller = _controllers.putIfAbsent(
      threadId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
    yield* controller.stream;
  }

  @override
  Future<ChatMessage> sendText({
    required String threadId,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) throw ArgumentError.value(text, 'text');
    final message = ChatMessage(
      id: 'mock-message-${++_messageSequence}',
      threadId: threadId,
      senderId: currentUserId,
      senderNickname: currentNickname,
      senderDisplayName: currentDisplayName,
      kind: ChatMessageKind.text,
      text: normalized,
      createdAt: DateTime.now().toUtc(),
    );
    messages.putIfAbsent(threadId, () => []).add(message);
    _controllers[threadId]?.add(
      List.unmodifiable(messages[threadId]!),
    );
    final index = threads.indexWhere((thread) => thread.id == threadId);
    if (index >= 0) {
      final thread = threads[index];
      threads[index] = thread.copyWith(
        updatedAt: message.createdAt,
        unreadCount: 0,
      );
      notifyThreadChanged();
    }
    return message;
  }

  @override
  Future<ChatMessage> sendAttachment({
    required String threadId,
    required ChatAttachmentUpload upload,
    String text = '',
  }) async {
    final thread = threads.where((item) => item.id == threadId).firstOrNull;
    final jobChat = thread?.kind == ChatThreadKind.jobCustomer ||
        thread?.kind == ChatThreadKind.jobInternal;
    final organizationChat = thread?.kind == ChatThreadKind.direct ||
        thread?.kind == ChatThreadKind.team ||
        thread?.kind == ChatThreadKind.organization ||
        thread?.kind == ChatThreadKind.service;
    if (thread == null ||
        thread.organizationId == null ||
        (!jobChat && !organizationChat) ||
        (jobChat && thread.jobId == null)) {
      throw StateError('Attachments are unavailable in this conversation');
    }
    final assetId = 'mock-attachment-${++_messageSequence}';
    final attachment = ChatAttachment(
      assetId: assetId,
      fileName: upload.fileName,
      mimeType: upload.mimeType,
      sizeBytes: upload.bytes.length,
      organizationId: thread.organizationId!,
      jobId: thread.jobId ?? '',
      threadId: organizationChat ? thread.id : '',
      internal: thread.kind == ChatThreadKind.jobInternal,
    );
    _attachmentBytes[assetId] = Uint8List.fromList(upload.bytes);
    final message = ChatMessage(
      id: 'mock-message-$_messageSequence',
      threadId: threadId,
      senderId: currentUserId,
      senderNickname: currentNickname,
      senderDisplayName: currentDisplayName,
      kind: attachment.isImage
          ? ChatMessageKind.image
          : ChatMessageKind.attachment,
      text: text.trim(),
      createdAt: DateTime.now().toUtc(),
      metadata: attachment.toMetadata(),
    );
    messages.putIfAbsent(threadId, () => []).add(message);
    _controllers[threadId]?.add(List.unmodifiable(messages[threadId]!));
    final threadIndex = threads.indexWhere((item) => item.id == threadId);
    if (threadIndex >= 0) {
      threads[threadIndex] = threads[threadIndex].copyWith(
        updatedAt: message.createdAt,
        unreadCount: 0,
      );
      notifyThreadChanged();
    }
    return message;
  }

  @override
  Future<Uint8List> loadAttachment(ChatAttachment attachment) async {
    final bytes = _attachmentBytes[attachment.assetId];
    if (bytes == null) throw StateError('Attachment not found');
    return Uint8List.fromList(bytes);
  }
}
