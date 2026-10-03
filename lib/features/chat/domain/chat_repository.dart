import 'dart:typed_data';

import 'chat_attachment.dart';
import 'chat_contact.dart';
import 'chat_message.dart';
import 'chat_thread.dart';
import 'customer_share_candidate.dart';

abstract interface class ChatRepository {
  Future<void> ensureDefaultThreads();

  Future<List<ChatThread>> listThreads();

  Stream<void> watchThreadChanges();

  Future<void> markThreadRead(String threadId);

  Future<List<ChatContact>> searchContacts(
    String query, {
    int limit = 30,
  });

  Future<String> openDirectThread(String userId);

  Future<List<ChatTeamMember>> listTeamMembers(String threadId);

  Future<String> createTeam({
    required String name,
    required List<String> memberUserIds,
  });

  Future<void> updateTeam({
    required String threadId,
    required String name,
    required List<String> memberUserIds,
  });

  Future<void> archiveTeam(String threadId);

  Future<void> restoreTeam(String threadId);

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
