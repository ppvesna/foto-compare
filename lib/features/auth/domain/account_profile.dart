class AccountProfile {
  final String userId;
  final String email;
  final String nickname;
  final String displayName;

  const AccountProfile({
    required this.userId,
    required this.email,
    required this.nickname,
    this.displayName = '',
  });
}

class AccountProfileException implements Exception {
  final String code;
  final String message;

  const AccountProfileException(this.code, this.message);

  @override
  String toString() => message;
}
