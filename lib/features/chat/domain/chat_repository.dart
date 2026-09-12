import 'dart:typed_data';

import 'chat_attachment.dart';
import 'chat_message.dart';
import 'chat_thread.dart';
import 'customer_share_candidate.dart';

abstract interface class ChatRepository {
  Future<void> ensureDefaultThreads();

  Future<List<ChatThread>> listThreads();

  Future<List<CustomerShareCandidate>> listCustomerShareCandidates();

  Future<void> setCustomerAccess({
    required String jobId,
    required bool shared,
  });

  Future<List<ChatMessage>> listMessages(
    String threadId, {
    int limit = 100,
  });

  Stream<List<ChatMessage>> watchMessages(String threadId);

  Future<ChatMessage> sendText({
    required String threadId,
    required String text,
  });

  Future<ChatMessage> sendAttachment({
    required String threadId,
    required ChatAttachmentUpload upload,
    String text = '',
  });

  Future<Uint8List> loadAttachment(ChatAttachment attachment);
}
