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
  final parameters = authCallbackParameters(uri);
  return parameters['type'] == 'recovery';
}

Map<String, String> authCallbackParameters(Uri uri) {
  final parameters = <String, String>{...uri.queryParameters};
  if (uri.fragment.isEmpty) return parameters;

  final fragment =
      uri.fragment.startsWith('?') ? uri.fragment.substring(1) : uri.fragment;
  try {
    parameters.addAll(Uri.splitQueryString(fragment));
  } on FormatException {
    // A regular application fragment is not an authentication callback.
  }
  return parameters;
}

bool hasAuthCallbackPayload(Uri uri) {
  final parameters = authCallbackParameters(uri);
  return parameters.containsKey('access_token') ||
      parameters.containsKey('code') ||
      parameters.containsKey('error') ||
      parameters.containsKey('error_code') ||
      parameters.containsKey('error_description');
}

String buildPasswordRecoveryRedirectUrl(Uri currentUri) {
  return Uri.parse('${currentUri.origin}/').replace(
    queryParameters: const {'type': 'recovery'},
  ).toString();
}
