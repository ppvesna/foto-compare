import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

class AiAnalysis {
  final String verdict;
  final double score;
  final String summary;
  final List<PrintIssue> issues;
  final List<String> recommendations;

  const AiAnalysis({
    required this.verdict,
    required this.score,
    required this.summary,
    required this.issues,
    required this.recommendations,
  });

  factory AiAnalysis.fromJson(Map<String, dynamic> j) => AiAnalysis(
        verdict: j['verdict'] ?? 'неизвестно',
        score: (j['score'] as num?)?.toDouble() ?? 0,
        summary: j['summary'] ?? '',
        issues: (j['issues'] as List? ?? [])
            .map((e) => PrintIssue.fromJson(e as Map<String, dynamic>))
            .toList(),
        recommendations: List<String>.from(j['recommendations'] ?? []),
      );

  bool get hasIssues => issues.isNotEmpty;
}

class PrintIssue {
  final String type;
  final String severity;
  final String location;
  final String description;

  const PrintIssue({
    required this.type,
    required this.severity,
    required this.location,
    required this.description,
  });

  factory PrintIssue.fromJson(Map<String, dynamic> j) => PrintIssue(
        type: j['type'] ?? '',
        severity: j['severity'] ?? 'низкая',
        location: j['location'] ?? '',
        description: j['description'] ?? '',
      );

  // Цвет по серьёзности
  static const _colors = {
    'низкая': 0xFF3A8C2F,
    'средняя': 0xFFC8A020,
    'высокая': 0xFFC82020,
  };
  int get severityColor => _colors[severity] ?? 0xFF808080;
}

class AiCompareService {
  static const _maxSide = 1024; // макс. сторона перед отправкой в AI

  // Ресайз + кодирование в JPEG для стабильной отправки
  static Uint8List _prepare(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    img.Image resized = decoded;
    if (decoded.width > _maxSide || decoded.height > _maxSide) {
      resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: _maxSide)
          : img.copyResize(decoded, height: _maxSide);
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
  }

  static Future<AiAnalysis> analyze(
      Uint8List ref, Uint8List cmp) async {
    final refData = _prepare(ref);
    final cmpData = _prepare(cmp);

    final response = await Supabase.instance.client.functions.invoke(
      'analyze-print',
      body: {
        'refImage':     base64Encode(refData),
        'cmpImage':     base64Encode(cmpData),
        'refMediaType': 'image/jpeg',
        'cmpMediaType': 'image/jpeg',
      },
    );

    if (response.status != 200) {
      throw Exception('Ошибка сервера: ${response.status}');
    }

    final data = response.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);

    return AiAnalysis.fromJson(data['analysis'] as Map<String, dynamic>);
  }

  // Анализ качества одного эталонного изображения
  static Future<AiAnalysis> analyzeReference(Uint8List ref) async {
    final refData = _prepare(ref);
    final response = await Supabase.instance.client.functions.invoke(
      'analyze-print',
      body: {
        'refImage':     base64Encode(refData),
        'cmpImage':     base64Encode(refData), // тот же снимок
        'refMediaType': 'image/jpeg',
        'cmpMediaType': 'image/jpeg',
        'mode':         'reference_quality',   // подсказка для prompt
      },
    );
    if (response.status != 200) {
      throw Exception('Ошибка сервера: ${response.status}');
    }
    final data = response.data as Map<String, dynamic>;
    if (data['error'] != null) throw Exception(data['error']);
    return AiAnalysis.fromJson(data['analysis'] as Map<String, dynamic>);
  }
}
