import 'dart:async';
import '../config/app_config.dart';
import '../database/local_database.dart';
import 'api/api_service.dart';

/// Сервис синхронизации локальной БД с сервером.
/// Стратегия: сначала пишем локально, потом фоново синхронизируем.
class SyncService {
  static final SyncService _i = SyncService._();
  factory SyncService() => _i;
  SyncService._();

  Timer? _timer;
  bool _running = false;

  // ── Запуск/остановка ──────────────────────────────

  void start() {
    if (!AppConfig.featureServerSync) return;
    _timer?.cancel();
    // Синхронизация каждые 30 секунд
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    sync(); // сразу при старте
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  // ── Основной цикл синхронизации ───────────────────

  Future<void> sync() async {
    if (!AppConfig.featureServerSync) return;
    if (_running) return;
    _running = true;

    try {
      await _pushPending();
      await _pullUpdates();
    } catch (e) {
      // Тихо — попробуем в следующий раз
    } finally {
      _running = false;
    }
  }

  // ── Push: локальные изменения → сервер ────────────

  Future<void> _pushPending() async {
    final pending = await LocalDatabase().getPendingSync();
    if (pending.isEmpty) return;

    for (final item in pending) {
      try {
        await _pushItem(
          table:  item['table_name'] as String,
          id:     item['record_id']  as String,
          op:     item['operation']  as String,
          syncId: item['id']         as String,
        );
      } catch (e) {
        await LocalDatabase().markSyncFailed(item['id'] as String, e.toString());
      }
    }
  }

  Future<void> _pushItem({
    required String table,
    required String id,
    required String op,
    required String syncId,
  }) async {
    final db = LocalDatabase();
    final api = ApiService();

    switch (table) {
      case 'comparison_results':
        final rows = await db.getResults();
        final row = rows.firstWhere((r) => r['id'] == id, orElse: () => {});
        if (row.isNotEmpty) await api.post('/results', row);

      case 'chat_messages':
        final msgs = await db.getMessages();
        final msg = msgs.firstWhere((m) => m['id'] == id, orElse: () => {});
        if (msg.isNotEmpty) await api.post('/messages', msg);

      case 'settings':
        final s = await db.getSettings(id);
        if (s != null) await api.post('/settings', s);

      case 'users':
        final u = await db.getUser(id);
        if (u != null) await api.post('/users', u);
    }

    await db.markSynced(syncId);
  }

  // ── Pull: сервер → локальные обновления ───────────

  Future<void> _pullUpdates() async {
    final api = ApiService();
    final db  = LocalDatabase();

    try {
      // Получаем изменения с сервера с момента последней синхронизации
      final updates = await api.get('/sync/updates');
      final items = updates['items'] as List? ?? [];

      for (final item in items) {
        final table = item['table'] as String?;
        final data  = item['data']  as Map<String, dynamic>?;
        if (table == null || data == null) continue;

        switch (table) {
          case 'comparison_results': await db.saveResult(data);
          case 'chat_messages':      await db.saveMessage(data);
          case 'chat_groups':        await db.saveGroup(data);
          case 'settings':           await db.saveSettings(data);
          case 'users':              await db.upsertUser(data);
          case 'purchases':          await db.savePurchase(data);
        }
      }
    } catch (_) {
      // Сервер недоступен — работаем офлайн
    }
  }

  // ── Принудительная полная синхронизация ───────────

  Future<SyncResult> fullSync(String userId) async {
    if (!AppConfig.featureServerSync) {
      return SyncResult(success: false, message: 'Синхронизация отключена');
    }
    try {
      await _pushPending();
      await _pullUpdates();
      return SyncResult(success: true, message: 'Синхронизация завершена');
    } catch (e) {
      return SyncResult(success: false, message: 'Ошибка: $e');
    }
  }
}

class SyncResult {
  final bool   success;
  final String message;
  final int    pushed;
  final int    pulled;

  const SyncResult({
    required this.success,
    required this.message,
    this.pushed = 0,
    this.pulled = 0,
  });
}
