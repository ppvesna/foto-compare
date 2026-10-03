import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../capabilities/storage/storage.dart';
import '../domain/chat_attachment.dart';
import '../domain/chat_contact.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repository.dart';
import '../domain/chat_thread.dart';
import '../domain/customer_share_candidate.dart';

class SupabaseChatRepository implements ChatRepository {
  static const maxAttachmentBytes = 10 * 1024 * 1024;

  final SupabaseClient client;
  final String currentUserId;
  final CloudStorage storage;

  SupabaseChatRepository(
    this.client, {
    required this.currentUserId,
    required this.storage,
  });

  @override
  Future<void> ensureDefaultThreads() async {
    await client.rpc('ensure_default_chat_threads_v1');
  }

  @override
  Future<List<ChatThread>> listThreads() async {
    final response = await client.rpc('list_accessible_chat_threads_v2');
    final rows = response is List ? response : const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => _threadFromRpcRow(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Stream<void> watchThreadChanges() {
    return client
        .from('chat_groups')
        .stream(primaryKey: ['id'])
        .skip(1)
        .map((_) {});
  }

  @override
  Future<void> markThreadRead(String threadId) async {
    await client.rpc(
      'mark_chat_thread_read_v1',
      params: {'target_thread': threadId},
    );
  }

  @override
  Future<List<ChatContact>> searchContacts(
    String query, {
    int limit = 30,
  }) async {
    final response = await client.rpc(
      'search_chat_contacts_v1',
      params: {
        'search_text': query.trim(),
        'result_limit': limit,
      },
    );
    return (response as List? ?? const []).whereType<Map>().map((item) {
      final row = Map<String, dynamic>.from(item);
      return ChatContact(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String? ?? '',
        nickname: row['nickname'] as String? ?? '',
        roleLabel: row['role_label'] as String? ?? 'Пользователь',
        canAddToTeam: row['can_add_to_team'] == true,
      );
    }).toList(growable: false);
  }

  @override
  Future<String> openDirectThread(String userId) async {
    final response = await client.rpc(
      'open_direct_chat_v1',
      params: {'target_user': userId},
    );
    return response as String;
  }

  @override
  Future<List<ChatTeamMember>> listTeamMembers(String threadId) async {
    final response = await client.rpc(
      'list_chat_team_members_v1',
      params: {'target_group': threadId},
    );
    return (response as List? ?? const []).whereType<Map>().map((item) {
      final row = Map<String, dynamic>.from(item);
      return ChatTeamMember(
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String? ?? '',
        nickname: row['nickname'] as String? ?? '',
      );
    }).toList(growable: false);
  }

  @override
  Future<String> createTeam({
    required String name,
    required List<String> memberUserIds,
  }) async {
    final response = await client.rpc(
      'create_chat_team_v1',
      params: {
        'team_name': name.trim(),
        'member_user_ids': memberUserIds,
      },
    );
    return response as String;
  }

  @override
  Future<void> updateTeam({
    required String threadId,
    required String name,
    required List<String> memberUserIds,
  }) async {
    await client.rpc(
      'update_chat_team_v1',
      params: {
        'target_group': threadId,
        'team_name': name.trim(),
        'member_user_ids': memberUserIds,
      },
    );
  }

  @override
  Future<void> archiveTeam(String threadId) async {
    await client.rpc(
      'archive_chat_team_v1',
      params: {'target_group': threadId},
    );
  }

  @override
  Future<void> restoreTeam(String threadId) async {
    await client.rpc(
      'restore_chat_team_v1',
      params: {'target_group': threadId},
    );
  }

  @override
  Future<List<CustomerShareCandidate>> listCustomerShareCandidates() async {
    final response = await client.rpc('list_customer_share_candidates_v1');
    final rows = response is List ? response : const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => _customerShareCandidateFromRow(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setCustomerAccess({
    required String jobId,
    required bool shared,
  }) async {
    await client.rpc(
      'set_production_job_customer_access_v1',
      params: {
        'target_job': jobId,
        'requested_shared': shared,
      },
    );
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String threadId, {
    int limit = 100,
  }) async {
    final rows = await client
        .from('chat_messages')
        .select(
          'id, group_id, sender_id, message_type, text, metadata, created_at',
        )
        .eq('group_id', threadId)
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .limit(limit);
    final normalizedRows = rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final profiles = await _loadProfiles(
      threadId,
      normalizedRows
          .map((row) => row['sender_id'] as String?)
          .whereType<String>()
          .toSet(),
    );
    return normalizedRows.reversed
        .map((row) => _messageFromRow(row, profiles))
        .toList(growable: false);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId) {
    return client
        .from('chat_messages')
        .stream(primaryKey: const ['id'])
        .eq('group_id', threadId)
        .order('created_at', ascending: true)
        .asyncMap((rows) async {
          final visibleRows = rows
              .where((row) => row['is_deleted'] != true)
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
          final profiles = await _loadProfiles(
            threadId,
            visibleRows
                .map((row) => row['sender_id'] as String?)
                .whereType<String>()
                .toSet(),
          );
          return visibleRows
              .map((row) => _messageFromRow(row, profiles))
              .toList(growable: false);
        });
  }

  @override
  Future<ChatMessage> sendText({
    required String threadId,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) throw ArgumentError.value(text, 'text');
    final thread = await client
        .from('chat_groups')
        .select('organization_id')
        .eq('id', threadId)
        .single();
    final row = await client
        .from('chat_messages')
        .insert({
          'organization_id': thread['organization_id'],
          'group_id': threadId,
          'sender_id': currentUserId,
          'message_type': 'text',
          'text': normalized,
          'metadata': const <String, dynamic>{},
        })
        .select(
          'id, group_id, sender_id, message_type, text, metadata, created_at',
        )
        .single();
    final profiles = await _loadProfiles(threadId, {currentUserId});
    return _messageFromRow(
      Map<String, dynamic>.from(row),
      profiles,
    );
  }

  @override
  Future<ChatMessage> sendAttachment({
    required String threadId,
    required ChatAttachmentUpload upload,
    String text = '',
  }) async {
    final fileName = upload.fileName.trim();
    if (fileName.isEmpty) {
      throw ArgumentError.value(upload.fileName, 'upload.fileName');
    }
    if (upload.bytes.isEmpty || upload.bytes.length > maxAttachmentBytes) {
      throw ArgumentError.value(upload.bytes.length, 'upload.bytes');
    }
    final thread = await client
        .from('chat_groups')
        .select('organization_id, job_id, kind')
        .eq('id', threadId)
        .single();
    final organizationId = thread['organization_id'] as String? ?? '';
    final jobId = thread['job_id'] as String? ?? '';
    final internal = thread['kind'] == 'job_internal';
    if ((thread['kind'] != 'job' && thread['kind'] != 'job_internal') ||
        organizationId.isEmpty ||
        jobId.isEmpty) {
      throw StateError(
          'Attachments are available only in production job chats');
    }

    final assetId = 'chat-${const Uuid().v4()}';
    final scope = internal
        ? CloudAssetScope.organizationJobInternalChat(
            organizationId: organizationId,
            jobId: jobId,
          )
        : CloudAssetScope.organizationJobChat(
            organizationId: organizationId,
            jobId: jobId,
          );
    final attachment = ChatAttachment(
      assetId: assetId,
      fileName: fileName,
      mimeType: upload.mimeType.trim().isEmpty
          ? 'application/octet-stream'
          : upload.mimeType.trim(),
      sizeBytes: upload.bytes.length,
      organizationId: organizationId,
      jobId: jobId,
      internal: internal,
    );
    await storage.upload(
      CloudAssetUpload(
        id: assetId,
        name: fileName,
        mimeType: attachment.mimeType,
        bytes: upload.bytes,
        scope: scope,
      ),
    );
    try {
      final row = await client
          .from('chat_messages')
          .insert({
            'organization_id': organizationId,
            'group_id': threadId,
            'sender_id': currentUserId,
            'message_type': attachment.isImage ? 'image' : 'asset',
            'text': text.trim(),
            'metadata': attachment.toMetadata(),
          })
          .select(
            'id, group_id, sender_id, message_type, text, metadata, created_at',
          )
          .single();
      final profiles = await _loadProfiles(threadId, {currentUserId});
      return _messageFromRow(Map<String, dynamic>.from(row), profiles);
    } catch (_) {
      try {
        await storage.delete(assetId, scope: scope);
      } catch (_) {
        // The message failed; cleanup is best effort and never hides the cause.
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> loadAttachment(ChatAttachment attachment) {
    return storage.download(
      attachment.assetId,
      scope: attachment.internal
          ? CloudAssetScope.organizationJobInternalChat(
              organizationId: attachment.organizationId,
              jobId: attachment.jobId,
            )
          : CloudAssetScope.organizationJobChat(
              organizationId: attachment.organizationId,
              jobId: attachment.jobId,
            ),
    );
  }

  Future<Map<String, _SenderProfile>> _loadProfiles(
    String threadId,
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    final response = await client.rpc(
      'list_chat_sender_profiles_v1',
      params: {'target_group': threadId},
    );
    final rows = response is List ? response : const [];
    return {
      for (final row in rows)
        if (row is Map && userIds.contains(row['user_id']))
          row['user_id'] as String: _SenderProfile(
            nickname: row['nickname'] as String? ?? '',
            displayName: row['display_name'] as String? ?? '',
          ),
    };
  }

  ChatThread _threadFromRpcRow(Map<String, dynamic> row) {
    return ChatThread(
      id: row['thread_id'] as String,
      title: row['thread_name'] as String? ?? 'Чат',
      kind: _threadKind(
        row['thread_kind'] as String?,
        organizationId: row['organization_id'] as String?,
        jobId: row['job_id'] as String?,
      ),
      organizationId: row['organization_id'] as String?,
      jobId: row['job_id'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
      customerShared: row['customer_shared'] as bool? ?? false,
      canManageCustomerAccess:
          row['can_manage_customer_access'] as bool? ?? false,
      jobStatus: row['job_status'] as String? ?? '',
      customerName: row['customer_name'] as String? ?? '',
      unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
      archivedAt: row['archived_at'] == null
          ? null
          : DateTime.parse(row['archived_at'] as String).toLocal(),
      canManage: row['can_manage'] == true,
    );
  }

  CustomerShareCandidate _customerShareCandidateFromRow(
    Map<String, dynamic> row,
  ) {
    return CustomerShareCandidate(
      jobId: row['job_id'] as String,
      jobNumber: row['job_number'] as String? ?? '',
      customerName: row['customer_name'] as String? ?? '',
      customerShared: row['customer_shared'] as bool? ?? false,
    );
  }

  ChatMessage _messageFromRow(
    Map<String, dynamic> row,
    Map<String, _SenderProfile> profiles,
  ) {
    final senderId = row['sender_id'] as String? ?? '';
    final profile = profiles[senderId];
    return ChatMessage(
      id: row['id'] as String,
      threadId: row['group_id'] as String,
      senderId: senderId,
      senderNickname: profile?.nickname ?? '',
      senderDisplayName: profile?.displayName ?? '',
      kind: _messageKind(row['message_type'] as String?),
      text: row['text'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      metadata: row['metadata'] is Map
          ? Map<String, dynamic>.from(row['metadata'] as Map)
          : const {},
    );
  }

  ChatThreadKind _threadKind(
    String? value, {
    required String? organizationId,
    required String? jobId,
  }) {
    if (organizationId == null && jobId == null && value == 'direct') {
      return ChatThreadKind.personal;
    }
    switch (value) {
      case 'organization':
        return ChatThreadKind.organization;
      case 'group':
        return ChatThreadKind.team;
      case 'job':
        return ChatThreadKind.jobCustomer;
      case 'job_internal':
        return ChatThreadKind.jobInternal;
      case 'direct':
        return ChatThreadKind.direct;
      case 'service':
        return ChatThreadKind.service;
      default:
        return ChatThreadKind.personal;
    }
  }

  ChatMessageKind _messageKind(String? value) {
    switch (value) {
      case 'protocol':
      case 'check_result':
        return ChatMessageKind.protocol;
      case 'image':
        return ChatMessageKind.image;
      case 'asset':
        return ChatMessageKind.attachment;
      case 'system':
        return ChatMessageKind.system;
      default:
        return ChatMessageKind.text;
    }
  }
}

class _SenderProfile {
  final String nickname;
  final String displayName;

  const _SenderProfile({
    required this.nickname,
    required this.displayName,
  });
}
