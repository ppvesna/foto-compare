import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckHistoryService {
  static const _lastCheckKey = 'last_check_protocol_v1';
  static const _checksKey = 'check_protocols_v2';
  static final ValueNotifier<CheckProtocol?> lastCheck =
      ValueNotifier<CheckProtocol?>(null);
  static final ValueNotifier<List<CheckProtocol>> checks =
      ValueNotifier<List<CheckProtocol>>(const []);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastCheckKey);
    final listRaw = prefs.getString(_checksKey);
    if (listRaw != null && listRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(listRaw) as List)
            .map((e) => CheckProtocol.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        checks.value = list;
        if (list.isNotEmpty) lastCheck.value = list.first;
      } catch (_) {
        checks.value = const [];
      }
    }
    if (raw == null || raw.isEmpty || lastCheck.value != null) return;
    try {
      lastCheck.value = CheckProtocol.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      checks.value = [lastCheck.value!];
    } catch (_) {
      lastCheck.value = null;
    }
  }

  static Future<void> saveLast(CheckProtocol protocol) async {
    lastCheck.value = protocol;
    final next = [protocol, ...checks.value.where((p) => p.id != protocol.id)]
        .take(30)
        .toList();
    checks.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckKey, jsonEncode(protocol.toJson()));
    await prefs.setString(
      _checksKey,
      jsonEncode(next.map((p) => p.toJson()).toList()),
    );
  }

  static Future<void> clearLast() async {
    lastCheck.value = null;
    checks.value = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);
    await prefs.remove(_checksKey);
  }
}

class CheckProtocol {
  final String id;
  final DateTime createdAt;
  final String jobId;
  final String jobNumber;
  final double score;
  final String verdict;
  final String refSize;
  final String cmpSize;
  final String labId;
  final String referenceId;
  final String referenceLabel;
  final String sampleLabel;
  final String sampleImageId;
  final int sampleNo;
  final double? labMatch;
  final List<CheckProtocolStage> stages;

  const CheckProtocol({
    required this.id,
    required this.createdAt,
    this.jobId = '',
    this.jobNumber = '',
    required this.score,
    required this.verdict,
    required this.refSize,
    required this.cmpSize,
    required this.labId,
    this.referenceId = '',
    this.referenceLabel = 'Эталон',
    this.sampleLabel = 'Образец',
    this.sampleImageId = '',
    this.sampleNo = 1,
    required this.labMatch,
    required this.stages,
  });

  factory CheckProtocol.fromJson(Map<String, dynamic> json) => CheckProtocol(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        jobId: json['jobId'] as String? ?? '',
        jobNumber: json['jobNumber'] as String? ?? '',
        score: (json['score'] as num).toDouble(),
        verdict: json['verdict'] as String,
        refSize: json['refSize'] as String,
        cmpSize: json['cmpSize'] as String,
        labId: json['labId'] as String? ?? '-',
        referenceId: json['referenceId'] as String? ?? '',
        referenceLabel: json['referenceLabel'] as String? ?? 'Эталон',
        sampleLabel: json['sampleLabel'] as String? ?? 'Образец',
        sampleImageId: json['sampleImageId'] as String? ?? '',
        sampleNo: (json['sampleNo'] as num?)?.toInt() ?? 1,
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
        'jobId': jobId,
        'jobNumber': jobNumber,
        'score': score,
        'verdict': verdict,
        'refSize': refSize,
        'cmpSize': cmpSize,
        'labId': labId,
        'referenceId': referenceId,
        'referenceLabel': referenceLabel,
        'sampleLabel': sampleLabel,
        'sampleImageId': sampleImageId,
        'sampleNo': sampleNo,
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
