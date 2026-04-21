import 'dart:async';
import '../database/local_database.dart';
import 'api_service.dart';
import '../../config/app_config.dart';

/// Сервис чата.
/// Локальное хранение + синхронизация с сервером.
/// TODO: подключить WebSocket для real-time сообщений.
class ChatApiService {
  static final ChatApiService _i = ChatApiService._();
  factory ChatApiService() => _i;
  ChatApiService._();

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // ── Группы ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getGroups(String userId) async {
    // Сначала из локальной БД
    final local = await LocalDatabase().getGroups(userId);

    // Фоново обновляем с сервера
    if (AppConfig.featureServerSync) {
      _syncGroups(userId);
    }

    return local;
  }

  Future<Map<String, dynamic>> createGroup({
    required String name,
    required String creatorId,
    required List<String> memberIds,
  }) async {
    final group = {
      'id':         '${creatorId}_${DateTime.now().millisecondsSinceEpoch}',
      'name':       name,
      'created_by': creatorId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'is_deleted': 0,
    };

    await LocalDatabase().saveGroup(group);
    for (final uid in [creatorId, ...memberIds]) {
      await LocalDatabase().addGroupMember(group['id']!, uid,
          role: uid == creatorId ? 'admin' : 'member');
    }

    if (AppConfig.featureServerSync) {
      ApiService().post('/groups', group).catchError((_) {});
    }

    return group;
  }

  // ── Сообщения ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages({
    String? groupId,
    String? recipientId,
    int limit = 50,
  }) async {
    final msgs = await LocalDatabase().getMessages(
      groupId:     groupId,
      recipientId: recipientId,
      limit:       limit,
    );

    if (AppConfig.featureServerSync) {
      _syncMessages(groupId: groupId, recipientId: recipientId);
    }

    return msgs;
  }

  Future<Map<String, dynamic>> sendMessage({
    required String senderId,
    required String text,
    String? groupId,
    String? recipientId,
    String? attachmentId,
  }) async {
    assert(groupId != null || recipientId != null,
        'Нужен groupId или recipientId');

    final msg = {
      'id':            '${senderId}_${DateTime.now().millisecondsSinceEpoch}',
      'sender_id':     senderId,
      'group_id':      groupId,
      'recipient_id':  recipientId,
      'text':          text,
      'attachment_id': attachmentId,
      'is_read':       0,
      'created_at':    DateTime.now().toIso8601String(),
      'updated_at':    DateTime.now().toIso8601String(),
      'is_deleted':    0,
    };

    // Сохраняем локально сразу
    await LocalDatabase().saveMessage(msg);
    _messageController.add(msg);

    // Отправляем на сервер фоново
    if (AppConfig.featureServerSync) {
      ApiService().post('/messages', msg).catchError((_) {});
    }

    return msg;
  }

  Future<void> markRead(String groupId, String userId) async {
    await LocalDatabase().markMessagesRead(groupId, userId);
  }

  Future<int> getUnreadCount(String userId) async {
    return LocalDatabase().getUnreadCount(userId);
  }

  // ── Синхронизация ─────────────────────────────────

  Future<void> _syncGroups(String userId) async {
    try {
      final res = await ApiService().get('/groups',
          params: {'user_id': userId});
      final items = res['items'] as List? ?? [];
      for (final item in items) {
        await LocalDatabase().saveGroup(item as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _syncMessages({
    String? groupId,
    String? recipientId,
  }) async {
    try {
      final params = <String, String>{};
      if (groupId != null)     params['group_id']     = groupId;
      if (recipientId != null) params['recipient_id'] = recipientId;

      final res = await ApiService().get('/messages', params: params);
      final items = res['items'] as List? ?? [];
      for (final item in items) {
        await LocalDatabase().saveMessage(item as Map<String, dynamic>);
        _messageController.add(item as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  // ── WebSocket (TODO) ──────────────────────────────
  // Future<void> connectWebSocket(String userId) async {
  //   final ws = await WebSocket.connect('wss://api.yourserver.com/ws?user=$userId');
  //   ws.listen((data) {
  //     final msg = jsonDecode(data);
  //     LocalDatabase().saveMessage(msg);
  //     _messageController.add(msg);
  //   });
  // }

  void dispose() {
    _messageController.close();
  }
}
