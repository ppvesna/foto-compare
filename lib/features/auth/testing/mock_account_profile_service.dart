import '../domain/account_profile.dart';
import '../domain/account_profile_service.dart';

class MockAccountProfileService implements AccountProfileService {
  AccountProfile profile;
  int saveCount = 0;

  MockAccountProfileService({
    this.profile = const AccountProfile(
      userId: 'user-1',
      email: 'user@example.com',
      nickname: '',
    ),
  });

  @override
  Future<AccountProfile> loadCurrentProfile() async => profile;

  @override
  Future<AccountProfile> saveCurrentProfile({
    required String nickname,
    String displayName = '',
  }) async {
    saveCount++;
    profile = AccountProfile(
      userId: profile.userId,
      email: profile.email,
      nickname: nickname.trim().toLowerCase(),
      displayName: displayName.trim(),
    );
    return profile;
  }
}
