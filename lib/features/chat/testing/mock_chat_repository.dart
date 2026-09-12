import 'dart:async';
import 'dart:typed_data';

import '../domain/chat_attachment.dart';
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
  final Map<String, StreamController<List<ChatMessage>>> _controllers = {};
  final Map<String, Uint8List> _attachmentBytes = {};
  int _messageSequence = 0;

  MockChatRepository({
    this.currentUserId = 'mock-user',
    this.currentNickname = 'mock_user',
    this.currentDisplayName = 'Mock User',
    List<ChatThread>? threads,
    Map<String, List<ChatMessage>>? messages,
    List<CustomerShareCandidate>? customerShareCandidates,
  })  : threads = threads ?? [],
        messages = messages ?? {},
        customerShareCandidates = customerShareCandidates ?? [];

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

    final threadIndex = threads.indexWhere((thread) => thread.jobId == jobId);
    if (threadIndex >= 0) {
      final thread = threads[threadIndex];
      threads[threadIndex] = ChatThread(
        id: thread.id,
        title: thread.title,
        kind: thread.kind,
        organizationId: thread.organizationId,
        jobId: thread.jobId,
        updatedAt: DateTime.now().toUtc(),
        customerShared: shared,
        canManageCustomerAccess: true,
      );
      return;
    }
    if (!shared) return;

    final thread = ChatThread(
      id: 'mock-job-thread-$jobId',
      title: 'Работа № ${candidate.jobNumber}',
      kind: ChatThreadKind.job,
      jobId: jobId,
      updatedAt: DateTime.now().toUtc(),
      customerShared: true,
      canManageCustomerAccess: true,
    );
    threads.add(thread);
    messages.putIfAbsent(thread.id, () => []);
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
      threads[index] = ChatThread(
        id: thread.id,
        title: thread.title,
        kind: thread.kind,
        organizationId: thread.organizationId,
        jobId: thread.jobId,
        updatedAt: message.createdAt,
        customerShared: thread.customerShared,
        canManageCustomerAccess: thread.canManageCustomerAccess,
      );
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
    if (thread == null ||
        thread.kind != ChatThreadKind.job ||
        thread.organizationId == null ||
        thread.jobId == null) {
      throw StateError('Attachments are available only in job chats');
    }
    final assetId = 'mock-attachment-${++_messageSequence}';
    final attachment = ChatAttachment(
      assetId: assetId,
      fileName: upload.fileName,
      mimeType: upload.mimeType,
      sizeBytes: upload.bytes.length,
      organizationId: thread.organizationId!,
      jobId: thread.jobId!,
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
    return message;
  }

  @override
  Future<Uint8List> loadAttachment(ChatAttachment attachment) async {
    final bytes = _attachmentBytes[attachment.assetId];
    if (bytes == null) throw StateError('Attachment not found');
    return Uint8List.fromList(bytes);
  }
}
