abstract interface class PasswordRecoveryService {
  Future<void> requestReset({
    required String email,
    String? redirectTo,
  });

  Future<void> completeReset({required String newPassword});
}

class PasswordRecoveryException implements Exception {
  final String code;
  final String message;

  const PasswordRecoveryException(this.code, this.message);

  @override
  String toString() => message;
}

bool isPasswordRecoveryCallback(Uri uri) {
  final fragmentParameters = uri.fragment.isEmpty
      ? const <String, String>{}
      : Uri.splitQueryString(uri.fragment);
  return uri.queryParameters['type'] == 'recovery' ||
      fragmentParameters['type'] == 'recovery';
}
