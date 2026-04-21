import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../config/app_config.dart';

/// Сервис AI анализа через Claude API.
class AiApiService {
  static final AiApiService _i = AiApiService._();
  factory AiApiService() => _i;
  AiApiService._();

  // ── Анализ двух фото ──────────────────────────────

  Future<AiResult> analyzeImages(File reference, File compare) async {
    if (!AppConfig.featureAI) {
      return AiResult.disabled();
    }
    if (AppConfig.aiApiKey.isEmpty) {
      return AiResult.error('API ключ не настроен');
    }

    try {
      final refB64 = base64Encode(await reference.readAsBytes());
      final cmpB64 = base64Encode(await compare.readAsBytes());

      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type':    'application/json',
          'x-api-key':       AppConfig.aiApiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model':      AppConfig.aiModel,
          'max_tokens': 1024,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type':   'image',
                  'source': {
                    'type':       'base64',
                    'media_type': 'image/jpeg',
                    'data':       refB64,
                  }
                },
                {
                  'type':   'image',
                  'source': {
                    'type':       'base64',
                    'media_type': 'image/jpeg',
                    'data':       cmpB64,
                  }
                },
                {
                  'type': 'text',
                  'text': '''Ты — эксперт по анализу изображений.
Первое изображение — ЭТАЛОН, второе — СРАВНИВАЕМОЕ.

Опиши:
1. Что изменилось (конкретно и по делу)
2. Где именно отличия (левая/правая/верхняя/нижняя часть)
3. Насколько существенны изменения

Ответ на русском языке, кратко (3-5 предложений).'''
                }
              ]
            }
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final text = (data['content'] as List?)
            ?.firstWhere((c) => c['type'] == 'text',
                orElse: () => {'text': ''})['text'] as String? ?? '';
        return AiResult.success(text);
      }

      if (res.statusCode == 401) return AiResult.error('Неверный API ключ');
      if (res.statusCode == 429) return AiResult.error('Превышен лимит запросов');
      return AiResult.error('Ошибка API: ${res.statusCode}');

    } catch (e) {
      return AiResult.error('Нет соединения: $e');
    }
  }

  // ── Описание одного фото ──────────────────────────

  Future<AiResult> describeImage(File image) async {
    if (!AppConfig.featureAI) return AiResult.disabled();
    if (AppConfig.aiApiKey.isEmpty) return AiResult.error('API ключ не настроен');

    try {
      final b64 = base64Encode(await image.readAsBytes());

      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type':    'application/json',
          'x-api-key':       AppConfig.aiApiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model':      AppConfig.aiModel,
          'max_tokens': 512,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type':   'image',
                  'source': {
                    'type':       'base64',
                    'media_type': 'image/jpeg',
                    'data':       b64,
                  }
                },
                {
                  'type': 'text',
                  'text': 'Опиши кратко что на фото. На русском языке, 2-3 предложения.'
                }
              ]
            }
          ],
        }),
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final text = (data['content'] as List?)
            ?.firstWhere((c) => c['type'] == 'text',
                orElse: () => {'text': ''})['text'] as String? ?? '';
        return AiResult.success(text);
      }
      return AiResult.error('Ошибка API: ${res.statusCode}');
    } catch (e) {
      return AiResult.error('Ошибка: $e');
    }
  }
}

class AiResult {
  final bool    success;
  final String? text;
  final String? error;
  final bool    isDisabled;

  const AiResult._({
    required this.success,
    this.text,
    this.error,
    this.isDisabled = false,
  });

  factory AiResult.success(String text) =>
      AiResult._(success: true, text: text);

  factory AiResult.error(String message) =>
      AiResult._(success: false, error: message);

  factory AiResult.disabled() =>
      AiResult._(success: false, isDisabled: true,
          error: 'AI анализ доступен в Pro версии');
}
