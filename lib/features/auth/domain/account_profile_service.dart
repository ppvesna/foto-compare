import 'account_profile.dart';

abstract interface class AccountProfileService {
  Future<AccountProfile> loadCurrentProfile();

  Future<AccountProfile> saveCurrentProfile({
    required String nickname,
    String displayName = '',
  });
}
