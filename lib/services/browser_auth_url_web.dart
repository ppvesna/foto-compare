import 'package:web/web.dart' as web;

import '../features/auth/domain/password_recovery_service.dart';

String passwordRecoveryRedirectUrl() {
  return buildPasswordRecoveryRedirectUrl(Uri.base);
}

void clearAuthCallbackUrl() {
  final path = Uri.base.path.isEmpty ? '/' : Uri.base.path;
  web.window.history.replaceState(null, '', path);
}
