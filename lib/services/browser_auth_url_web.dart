import 'package:web/web.dart' as web;

String passwordRecoveryRedirectUrl() {
  final uri = Uri.base;
  return uri.replace(path: '/', query: '', fragment: '').toString();
}

void clearAuthCallbackUrl() {
  final path = Uri.base.path.isEmpty ? '/' : Uri.base.path;
  web.window.history.replaceState(null, '', path);
}
