import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/references/references.dart';

/// Единая точка входа для всех операций с Supabase.
/// Покрывает: layouts, layout_profiles, check_results, production_orders.
class SupabaseService {
  static final SupabaseService _i = SupabaseService._();
  factory SupabaseService() => _i;
  SupabaseService._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  // ══════════════════════════════════════════════════
  // LAYOUTS
  // ══════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchLayouts() async {
    final rows = await _sb
        .from('layouts')
        .select()
        .eq('is_deleted', false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> createLayout({
    required String name,
    required double widthMm,
    required double heightMm,
    String? thumbnailUrl,
  }) async {
    final row = await _sb.from('layouts').insert({
      'name':       name,
      'width_mm':   widthMm,
      'height_mm':  heightMm,
      'thumbnail':  thumbnailUrl,
      'created_by': _uid,
    }).select().single();
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> deleteLayout(String id) async {
    await _sb.from('layouts').update({
      'is_deleted': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  // ── Загрузка thumbnail в Storage ──────────────────

  Future<String?> uploadLayoutThumbnail(String layoutId, Uint8List bytes) async {
    try {
      final path = '$layoutId/thumbnail.jpg';
      await _sb.storage.from('layouts').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
      );
      return _sb.storage.from('layouts').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════
  // LAYOUT PROFILES
  // ══════════════════════════════════════════════════

  Future<List<LayoutProfile>> fetchProfiles({String? layoutId}) async {
    var query = _sb.from('layout_profiles').select();
    if (layoutId != null) query = query.eq('layout_id', layoutId) as dynamic;
    final rows = await (query as PostgrestFilterBuilder).order('created_at', ascending: false);
    return (rows as List).map((r) => _rowToProfile(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<LayoutProfile?> fetchProfile(String id) async {
    final row = await _sb.from('layout_profiles').select().eq('id', id).maybeSingle();
    if (row == null) return null;
    return _rowToProfile(Map<String, dynamic>.from(row as Map));
  }

  Future<String> saveProfile(LayoutProfile profile, {String? layoutId}) async {
    final data = {
      'name':             profile.name,
      'ref_anchors':      profile.refAnchors.map((a) => a.toJson()).toList(),
      'homography':       profile.homography,
      'crop_region':      profile.cropRegion?.toJson(),
      'alignment':        profile.alignment?.toJson(),
      'ref_image_width':  profile.refImageWidth,
      'ref_image_height': profile.refImageHeight,
      'created_by':       _uid,
      if (layoutId != null) 'layout_id': layoutId,
    };

    // Если id выглядит как timestamp (локальный) — создаём новую запись
    final isLocal = int.tryParse(profile.id) != null;
    if (isLocal) {
      final row = await _sb.from('layout_profiles').insert(data).select().single();
      return (row as Map)['id'] as String;
    } else {
      await _sb.from('layout_profiles').update({
        ...data,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', profile.id);
      return profile.id;
    }
  }

  Future<void> deleteProfile(String id) async {
    await _sb.from('layout_profiles').delete().eq('id', id);
  }

  // ══════════════════════════════════════════════════
  // CHECK RESULTS
  // ══════════════════════════════════════════════════

  Future<String> saveCheckResult({
    required double score,
    required String status,          // 'pass' | 'warning' | 'fail'
    String? layoutId,
    String? layoutProfileId,
    double? alignmentConfidence,
    double? reprojError,
    double? eccScore,
    double? colorDeviation,
    double? shiftDl,
    double? shiftDa,
    double? shiftDb,
    String? heatmapUrl,
    Map<String, dynamic>? details,
  }) async {
    final row = await _sb.from('check_results').insert({
      'layout_id':            layoutId,
      'layout_profile_id':    layoutProfileId,
      'operator_id':          _uid,
      'score':                score,
      'status':               status,
      'alignment_confidence': alignmentConfidence,
      'reproj_error':         reprojError,
      'ecc_score':            eccScore,
      'color_deviation':      colorDeviation,
      'shift_dl':             shiftDl,
      'shift_da':             shiftDa,
      'shift_db':             shiftDb,
      'heatmap_url':          heatmapUrl,
      'details':              details,
    }).select().single();
    return (row as Map)['id'] as String;
  }

  Future<List<Map<String, dynamic>>> fetchResults({
    String? layoutId,
    String? status,
    int limit = 50,
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _sb
        .from('check_results')
        .select('*, layout_profiles(name), layouts(name)');
    if (layoutId != null) query = query.eq('layout_id', layoutId) as dynamic;
    if (status   != null) query = query.eq('status', status) as dynamic;
    if (from     != null) query = query.gte('created_at', from.toIso8601String()) as dynamic;
    if (to       != null) query = query.lte('created_at', to.toIso8601String()) as dynamic;
    final rows = await (query as PostgrestFilterBuilder)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  // ── Загрузка тепловой карты ────────────────────────

  Future<String?> uploadHeatmap(String resultId, Uint8List bytes) async {
    try {
      final path = 'heatmaps/$resultId.png';
      await _sb.storage.from('layouts').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/png'),
      );
      return _sb.storage.from('layouts').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════
  // PRODUCTION ORDERS
  // ══════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> fetchOrders({String? status}) async {
    var query = _sb.from('production_orders').select('*, layouts(name, width_mm, height_mm)');
    if (status != null) query = query.eq('status', status) as dynamic;
    final rows = await (query as PostgrestFilterBuilder).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> createOrder({
    required String name,
    required String layoutId,
  }) async {
    final row = await _sb.from('production_orders').insert({
      'name':       name,
      'layout_id':  layoutId,
      'created_by': _uid,
    }).select().single();
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> updateOrderStatus(String id, String status) async {
    await _sb.from('production_orders').update({
      'status':     status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  // ══════════════════════════════════════════════════
  // УТИЛИТЫ
  // ══════════════════════════════════════════════════

  LayoutProfile _rowToProfile(Map<String, dynamic> r) {
    final anchorsRaw = r['ref_anchors'] as List? ?? [];
    final cropRaw    = r['crop_region'] as Map?;
    final alignRaw   = r['alignment']   as Map?;

    return LayoutProfile(
      id:              r['id'] as String,
      name:            r['name'] as String,
      refAnchors:      anchorsRaw.map((e) =>
          AnchorPoint.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      homography:      (r['homography'] as List).map((e) => (e as num).toDouble()).toList(),
      cropRegion:      cropRaw == null ? null :
          CropRegion.fromJson(Map<String, dynamic>.from(cropRaw)),
      alignment:       alignRaw == null ? null :
          AlignmentInfo.fromJson(Map<String, dynamic>.from(alignRaw)),
      refImageWidth:   r['ref_image_width']  as int? ?? 0,
      refImageHeight:  r['ref_image_height'] as int? ?? 0,
      widthMm:         100.0,
      heightMm:        100.0,
      createdAt:       DateTime.parse(r['created_at'] as String),
    );
  }

  bool get isSignedIn => _uid != null;
}
