import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../config/app_config.dart';
import 'db_schema.dart';

/// Локальная SQLite база данных.
/// Единственный источник правды на устройстве.
class LocalDatabase {
  static final LocalDatabase _i = LocalDatabase._();
  factory LocalDatabase() => _i;
  LocalDatabase._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  // ── Инициализация ─────────────────────────────────

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), AppConfig.dbName);
    return openDatabase(
      path,
      version: DbSchema.version,
      onCreate: (db, v) async {
        final batch = db.batch();
        for (final sql in DbSchema.all)    batch.execute(sql);
        for (final sql in DbSchema.indexes) batch.execute(sql);
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldV, newV) async {
        // TODO: миграции при обновлении версии
      },
    );
  }

  // ── Users ──────────────────────────────────────────

  Future<void> upsertUser(Map<String, dynamic> user) async {
    final d = await db;
    await d.insert('users', _stamp(user),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _logSync('users', user['id'], 'upsert');
  }

  Future<Map<String, dynamic>?> getUser(String id) async {
    final d = await db;
    final rows = await d.query('users', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  // ── Comparison Results ─────────────────────────────

  Future<void> saveResult(Map<String, dynamic> result) async {
    final d = await db;
    await d.insert('comparison_results', _stamp(result),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _logSync('comparison_results', result['id'], 'upsert');
  }

  Future<List<Map<String, dynamic>>> getResults({
    String? userId,
    int limit = 100,
    int offset = 0,
    String? search,
    double? minSimilarity,
    double? maxSimilarity,
  }) async {
    final d = await db;
    final where = <String>['is_deleted = 0'];
    final args  = <dynamic>[];

    if (userId != null)        { where.add('user_id = ?');         args.add(userId); }
    if (minSimilarity != null) { where.add('similarity >= ?');     args.add(minSimilarity); }
    if (maxSimilarity != null) { where.add('similarity <= ?');     args.add(maxSimilarity); }
    if (search != null)        { where.add('reference_path LIKE ?'); args.add('%$search%'); }

    return d.query(
      'comparison_results',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> deleteResult(String id) async {
    final d = await db;
    await d.update('comparison_results',
        {'is_deleted': 1, 'updated_at': _now()},
        where: 'id = ?', whereArgs: [id]);
    _logSync('comparison_results', id, 'delete');
  }

  Future<void> clearResults(String userId) async {
    final d = await db;
    await d.update('comparison_results',
        {'is_deleted': 1, 'updated_at': _now()},
        where: 'user_id = ? AND is_deleted = 0', whereArgs: [userId]);
  }

  // ── Chat Groups ────────────────────────────────────

  Future<void> saveGroup(Map<String, dynamic> group) async {
    final d = await db;
    await d.insert('chat_groups', _stamp(group),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _logSync('chat_groups', group['id'], 'upsert');
  }

  Future<List<Map<String, dynamic>>> getGroups(String userId) async {
    final d = await db;
    return d.rawQuery('''
      SELECT g.* FROM chat_groups g
      JOIN chat_group_members m ON m.group_id = g.id
      WHERE m.user_id = ? AND g.is_deleted = 0
      ORDER BY g.updated_at DESC
    ''', [userId]);
  }

  Future<void> addGroupMember(String groupId, String userId,
      {String role = 'member'}) async {
    final d = await db;
    await d.insert('chat_group_members', {
      'group_id':  groupId,
      'user_id':   userId,
      'role':      role,
      'joined_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ── Chat Messages ──────────────────────────────────

  Future<void> saveMessage(Map<String, dynamic> msg) async {
    final d = await db;
    await d.insert('chat_messages', _stamp(msg),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _logSync('chat_messages', msg['id'], 'upsert');
  }

  Future<List<Map<String, dynamic>>> getMessages({
    String? groupId,
    String? recipientId,
    String? senderId,
    int limit = 50,
    String? before, // created_at cursor
  }) async {
    final d = await db;
    final where = <String>['is_deleted = 0'];
    final args  = <dynamic>[];

    if (groupId != null)     { where.add('group_id = ?');     args.add(groupId); }
    if (recipientId != null) { where.add('recipient_id = ?'); args.add(recipientId); }
    if (senderId != null)    { where.add('sender_id = ?');    args.add(senderId); }
    if (before != null)      { where.add('created_at < ?');   args.add(before); }

    return d.query(
      'chat_messages',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  Future<void> markMessagesRead(String groupId, String userId) async {
    final d = await db;
    await d.update('chat_messages',
        {'is_read': 1, 'updated_at': _now()},
        where: 'group_id = ? AND sender_id != ? AND is_read = 0',
        whereArgs: [groupId, userId]);
  }

  Future<int> getUnreadCount(String userId) async {
    final d = await db;
    final result = await d.rawQuery('''
      SELECT COUNT(*) as cnt FROM chat_messages
      WHERE recipient_id = ? AND is_read = 0 AND is_deleted = 0
    ''', [userId]);
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ── Settings ───────────────────────────────────────

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final d = await db;
    await d.insert('settings', _stamp(settings),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _logSync('settings', settings['user_id'], 'upsert');
  }

  Future<Map<String, dynamic>?> getSettings(String userId) async {
    final d = await db;
    final rows = await d.query('settings',
        where: 'user_id = ?', whereArgs: [userId]);
    return rows.isEmpty ? null : rows.first;
  }

  // ── Purchases ──────────────────────────────────────

  Future<void> savePurchase(Map<String, dynamic> purchase) async {
    final d = await db;
    await d.insert('purchases', purchase,
        conflictAlgorithm: ConflictAlgorithm.replace);
    _logSync('purchases', purchase['id'], 'upsert');
  }

  Future<List<Map<String, dynamic>>> getPurchases(String userId) async {
    final d = await db;
    return d.query('purchases',
        where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'created_at DESC');
  }

  Future<bool> hasActivePremium(String userId) async {
    final d = await db;
    final now = _now();
    final rows = await d.query('purchases',
        where: "user_id = ? AND status = 'active' AND (expires_at IS NULL OR expires_at > ?)",
        whereArgs: [userId, now]);
    return rows.isNotEmpty;
  }

  // ── Sync Log ───────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPendingSync() async {
    final d = await db;
    return d.query('sync_log',
        where: "status = 'pending'",
        orderBy: 'created_at ASC',
        limit: 50);
  }

  Future<void> markSynced(String syncId) async {
    final d = await db;
    await d.update('sync_log',
        {'status': 'synced', 'synced_at': _now()},
        where: 'id = ?', whereArgs: [syncId]);
  }

  Future<void> markSyncFailed(String syncId, String error) async {
    final d = await db;
    await d.update('sync_log',
        {'status': 'failed', 'error': error},
        where: 'id = ?', whereArgs: [syncId]);
  }

  // ── Утилиты ───────────────────────────────────────

  String _now() => DateTime.now().toIso8601String();

  Map<String, dynamic> _stamp(Map<String, dynamic> data) {
    final now = _now();
    return {
      ...data,
      'updated_at': now,
      if (!data.containsKey('created_at')) 'created_at': now,
    };
  }

  Future<void> _logSync(String table, String id, String op) async {
    if (!AppConfig.featureServerSync) return;
    final d = await db;
    await d.insert('sync_log', {
      'id':         '${table}_${id}_${DateTime.now().millisecondsSinceEpoch}',
      'table_name': table,
      'record_id':  id,
      'operation':  op,
      'status':     'pending',
      'created_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> close() async {
    final d = _db;
    if (d != null) {
      await d.close();
      _db = null;
    }
  }
}
