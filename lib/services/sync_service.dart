import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../database/local_database.dart';
import 'supabase_service.dart';

/// Сервис синхронизации локальной БД с Supabase.
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
    if (kIsWeb) return; // sqflite недоступен в браузере
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
    final localDb = LocalDatabase();
    final sb = SupabaseService();
    final client = Supabase.instance.client;

    switch (table) {
      case 'check_results':
        final rows = await localDb.getCheckResults();
        final row = rows.firstWhere((r) => r['id'] == id, orElse: () => {});
        if (row.isNotEmpty) {
          final data = _deserializeJsonFields(row, ['details']);
          await client.from('check_results').upsert(data);
        }

      case 'layout_profiles':
        final rows = await localDb.getLayoutProfiles();
        final row = rows.firstWhere((r) => r['id'] == id, orElse: () => {});
        if (row.isNotEmpty) {
          final data = _deserializeJsonFields(row, ['ref_anchors','homography','crop_region','alignment']);
          await client.from('layout_profiles').upsert(data);
        }

      case 'layouts':
        final rows = await localDb.getLayouts();
        final row = rows.firstWhere((r) => r['id'] == id, orElse: () => {});
        if (row.isNotEmpty) await client.from('layouts').upsert(row);

      case 'production_orders':
        final rows = await localDb.getOrders();
        final row = rows.firstWhere((r) => r['id'] == id, orElse: () => {});
        if (row.isNotEmpty) await client.from('production_orders').upsert(row);
    }

    await localDb.markSynced(syncId);
  }

  // JSON-строки из SQLite → объекты для Supabase JSONB
  Map<String, dynamic> _deserializeJsonFields(
      Map<String, dynamic> row, List<String> fields) {
    final result = Map<String, dynamic>.from(row);
    for (final f in fields) {
      final v = result[f];
      if (v is String) {
        try { result[f] = jsonDecode(v); } catch (_) {}
      }
    }
    return result;
  }

  // ── Pull: Supabase → локальная БД ────────────────

  Future<void> _pullUpdates() async {
    final localDb = LocalDatabase();
    final client  = Supabase.instance.client;

    try {
      // Layouts
      final layouts = await client.from('layouts')
          .select().eq('is_deleted', false).order('updated_at');
      for (final row in layouts as List) {
        final r = Map<String, dynamic>.from(row as Map);
        r['created_at'] ??= DateTime.now().toIso8601String();
        r['updated_at'] ??= DateTime.now().toIso8601String();
        await localDb.saveLayout(r);
      }

      // Layout Profiles
      final profiles = await client.from('layout_profiles')
          .select().order('updated_at');
      for (final row in profiles as List) {
        final r = _serializeJsonFields(
            Map<String, dynamic>.from(row as Map),
            ['ref_anchors','homography','crop_region','alignment']);
        r['created_at'] ??= DateTime.now().toIso8601String();
        r['updated_at'] ??= DateTime.now().toIso8601String();
        await localDb.saveLayoutProfile(r);
      }

      // Production Orders
      final orders = await client.from('production_orders')
          .select().order('updated_at');
      for (final row in orders as List) {
        final r = Map<String, dynamic>.from(row as Map);
        r['created_at'] ??= DateTime.now().toIso8601String();
        r['updated_at'] ??= DateTime.now().toIso8601String();
        await localDb.saveOrder(r);
      }
    } catch (_) {
      // Сервер недоступен — работаем офлайн
    }
  }

  // Объекты → JSON-строки для SQLite
  Map<String, dynamic> _serializeJsonFields(
      Map<String, dynamic> row, List<String> fields) {
    final result = Map<String, dynamic>.from(row);
    for (final f in fields) {
      final v = result[f];
      if (v != null && v is! String) {
        result[f] = jsonEncode(v);
      }
    }
    return result;
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
