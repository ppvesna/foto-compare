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
}
