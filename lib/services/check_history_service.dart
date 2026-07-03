import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckHistoryService {
  static const _lastCheckKey = 'last_check_protocol_v1';
  static final ValueNotifier<CheckProtocol?> lastCheck =
      ValueNotifier<CheckProtocol?>(null);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastCheckKey);
    if (raw == null || raw.isEmpty) return;
    try {
      lastCheck.value = CheckProtocol.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      lastCheck.value = null;
    }
  }

  static Future<void> saveLast(CheckProtocol protocol) async {
    lastCheck.value = protocol;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckKey, jsonEncode(protocol.toJson()));
  }

  static Future<void> clearLast() async {
    lastCheck.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
  }
}

class CheckProtocol {
  final String id;
  final DateTime createdAt;
  final double score;
  final String verdict;
  final String refSize;
  final String cmpSize;
  final String labId;
  final double? labMatch;
  final List<CheckProtocolStage> stages;

  const CheckProtocol({
    required this.id,
    required this.createdAt,
    required this.score,
    required this.verdict,
    required this.refSize,
    required this.cmpSize,
    required this.labId,
    required this.labMatch,
    required this.stages,
  });

  factory CheckProtocol.fromJson(Map<String, dynamic> json) => CheckProtocol(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        score: (json['score'] as num).toDouble(),
        verdict: json['verdict'] as String,
        refSize: json['refSize'] as String,
        cmpSize: json['cmpSize'] as String,
        labId: json['labId'] as String? ?? '-',
        labMatch: (json['labMatch'] as num?)?.toDouble(),
        stages: (json['stages'] as List)
            .map((e) => CheckProtocolStage.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'score': score,
        'verdict': verdict,
        'refSize': refSize,
        'cmpSize': cmpSize,
        'labId': labId,
        'labMatch': labMatch,
        'stages': stages.map((e) => e.toJson()).toList(),
      };
}

class CheckProtocolStage {
  final String name;
  final String status;
  final String metric;
  final String comment;

  const CheckProtocolStage({
    required this.name,
    required this.status,
    required this.metric,
    required this.comment,
  });

  factory CheckProtocolStage.fromJson(Map<String, dynamic> json) =>
      CheckProtocolStage(
        name: json['name'] as String,
        status: json['status'] as String,
        metric: json['metric'] as String,
        comment: json['comment'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        'metric': metric,
        'comment': comment,
      };
}
