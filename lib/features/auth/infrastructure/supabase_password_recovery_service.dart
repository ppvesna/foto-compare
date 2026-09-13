import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/password_recovery_service.dart';

class SupabasePasswordRecoveryService implements PasswordRecoveryService {
  final SupabaseClient client;

  const SupabasePasswordRecoveryService(this.client);

  @override
  Future<void> requestReset({
    required String email,
    String? redirectTo,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalizedEmail)) {
      throw const PasswordRecoveryException(
        'invalid_email',
        'Введите корректный email.',
      );
    }
    try {
      await client.auth.resetPasswordForEmail(
        normalizedEmail,
        redirectTo: redirectTo,
      );
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (error.statusCode == '429' ||
          message.contains('rate limit') ||
          message.contains('too many')) {
        throw const PasswordRecoveryException(
          'rate_limited',
          'Лимит писем временно исчерпан. Повторите запрос позже.',
        );
      }
      throw PasswordRecoveryException('request_failed', error.message);
    }
  }

  @override
  Future<void> completeReset({required String newPassword}) async {
    if (client.auth.currentSession == null) {
      throw const PasswordRecoveryException(
        'recovery_session_missing',
        'Ссылка недействительна или срок её действия закончился.',
      );
    }
    if (newPassword.length < 8) {
      throw const PasswordRecoveryException(
        'invalid_new_password',
        'Новый пароль должен содержать минимум 8 символов.',
      );
    }
    try {
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('password') &&
          (message.contains('weak') || message.contains('characters'))) {
        throw const PasswordRecoveryException(
          'invalid_new_password',
          'Сервер отклонил новый пароль. Используйте более сложный пароль.',
        );
      }
      throw PasswordRecoveryException('reset_failed', error.message);
    }
  }
}
