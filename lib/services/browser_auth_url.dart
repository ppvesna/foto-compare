import 'browser_auth_url_stub.dart'
    if (dart.library.html) 'browser_auth_url_web.dart' as implementation;

String? passwordRecoveryRedirectUrl() =>
    implementation.passwordRecoveryRedirectUrl();

void clearAuthCallbackUrl() => implementation.clearAuthCallbackUrl();
