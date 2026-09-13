import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account_profile.dart';
import '../domain/account_profile_service.dart';

class SupabaseAccountProfileService implements AccountProfileService {
  final SupabaseClient client;

  const SupabaseAccountProfileService(this.client);

  @override
  Future<AccountProfile> loadCurrentProfile() async {
    final user = client.auth.currentUser;
    final email = user?.email?.trim() ?? '';
    if (user == null || email.isEmpty) {
      throw const AccountProfileException(
        'not_authenticated',
        'Пользователь не вошёл в приложение.',
      );
    }

    final response = await client
        .from('user_profiles')
        .select('nickname, display_name')
        .eq('user_id', user.id)
        .maybeSingle();
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    return AccountProfile(
      userId: user.id,
      email: email,
      nickname: (response?['nickname'] as String?)?.trim() ??
          (metadata['nickname'] as String?)?.trim() ??
          '',
      displayName: (response?['display_name'] as String?)?.trim() ??
          (metadata['display_name'] as String?)?.trim() ??
          '',
    );
  }

  @override
  Future<AccountProfile> saveCurrentProfile({
    required String nickname,
    String displayName = '',
  }) async {
    final user = client.auth.currentUser;
    final email = user?.email?.trim() ?? '';
    if (user == null || email.isEmpty) {
      throw const AccountProfileException(
        'not_authenticated',
        'Пользователь не вошёл в приложение.',
      );
    }

    final normalizedNickname = nickname.trim().toLowerCase();
    final normalizedDisplayName = displayName.trim();
    try {
      await client.from('user_profiles').upsert({
        'user_id': user.id,
        'email': email,
        'nickname': normalizedNickname,
        'display_name': normalizedDisplayName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const AccountProfileException(
          'nickname_conflict',
          'Этот ник уже занят. Выберите другой.',
        );
      }
      rethrow;
    }

    await client.auth.updateUser(
      UserAttributes(
        data: {
          'nickname': normalizedNickname,
          'display_name': normalizedDisplayName,
        },
      ),
    );

    return AccountProfile(
      userId: user.id,
      email: email,
      nickname: normalizedNickname,
      displayName: normalizedDisplayName,
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = client.auth.currentUser;
    final email = user?.email?.trim() ?? '';
    if (user == null || email.isEmpty) {
      throw const AccountProfileException(
        'not_authenticated',
        'Пользователь не вошёл в приложение.',
      );
    }
    if (currentPassword.isEmpty) {
      throw const AccountProfileException(
        'invalid_current_password',
        'Введите текущий пароль.',
      );
    }
    if (newPassword.length < 8) {
      throw const AccountProfileException(
        'invalid_new_password',
        'Новый пароль должен содержать минимум 8 символов.',
      );
    }
    if (currentPassword == newPassword) {
      throw const AccountProfileException(
        'same_password',
        'Новый пароль должен отличаться от текущего.',
      );
    }

    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      if (response.user?.id != user.id) {
        throw const AccountProfileException(
          'invalid_current_password',
          'Текущий пароль указан неверно.',
        );
      }
      await client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials') ||
          message.contains('invalid credentials')) {
        throw const AccountProfileException(
          'invalid_current_password',
          'Текущий пароль указан неверно.',
        );
      }
      if (message.contains('different from the old') ||
          message.contains('same password')) {
        throw const AccountProfileException(
          'same_password',
          'Новый пароль должен отличаться от текущего.',
        );
      }
      if (message.contains('password') &&
          (message.contains('weak') || message.contains('characters'))) {
        throw const AccountProfileException(
          'invalid_new_password',
          'Сервер отклонил новый пароль. Используйте более сложный пароль.',
        );
      }
      throw AccountProfileException('password_change_failed', error.message);
    }
  }
}
