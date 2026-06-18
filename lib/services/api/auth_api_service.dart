import 'api_service.dart';
import '../../database/local_database.dart';
import '../../config/app_config.dart';

/// Сервис авторизации.
/// Поддерживает: Email/Password, Google Sign-In (через Firebase).
class AuthApiService {
  static final AuthApiService _i = AuthApiService._();
  factory AuthApiService() => _i;
  AuthApiService._();

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  // ── Вход по Email ─────────────────────────────────

  Future<AuthResult> signInWithEmail(String email, String password) async {
    if (!AppConfig.featureAuth) return _guestResult();

    try {
      final res = await ApiService().post('/auth/login', {
        'email':    email,
        'password': password,
      });

      final token = res['token'] as String?;
      final user  = res['user']  as Map<String, dynamic>?;

      if (token == null || user == null) {
        return AuthResult.error('Неверный ответ сервера');
      }

      ApiService().setToken(token);
      _currentUser = user;
      await LocalDatabase().upsertUser(user);

      return AuthResult.success(user);
    } on ApiException catch (e) {
      if (e.isUnauthorized) return AuthResult.error('Неверный email или пароль');
      return AuthResult.error('Ошибка сервера: ${e.statusCode}');
    } catch (e) {
      return AuthResult.error('Нет соединения с сервером');
    }
  }

  // ── Регистрация ───────────────────────────────────

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    if (!AppConfig.featureAuth) return _guestResult();

    try {
      final res = await ApiService().post('/auth/register', {
        'email':        email,
        'password':     password,
        'display_name': name,
      });

      final token = res['token'] as String?;
      final user  = res['user']  as Map<String, dynamic>?;

      if (token == null || user == null) {
        return AuthResult.error('Неверный ответ сервера');
      }

      ApiService().setToken(token);
      _currentUser = user;
      await LocalDatabase().upsertUser(user);

      return AuthResult.success(user);
    } on ApiException catch (e) {
      if (e.statusCode == 409) return AuthResult.error('Email уже зарегистрирован');
      return AuthResult.error('Ошибка регистрации: ${e.statusCode}');
    } catch (e) {
      return AuthResult.error('Нет соединения с сервером');
    }
  }

  // ── Google Sign-In ────────────────────────────────

  Future<AuthResult> signInWithGoogle() async {
    if (!AppConfig.featureAuth) return _guestResult();

    // TODO: подключить google_sign_in пакет
    // final googleUser = await GoogleSignIn().signIn();
    // final googleAuth = await googleUser?.authentication;
    // final idToken = googleAuth?.idToken;
    // final res = await ApiService().post('/auth/google', {'id_token': idToken});

    throw UnimplementedError('Google Sign-In: добавить google_sign_in пакет');
  }

  // ── Сброс пароля ──────────────────────────────────

  Future<bool> resetPassword(String email) async {
    if (!AppConfig.featureAuth) return false;
    try {
      await ApiService().post('/auth/reset-password', {'email': email});
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Обновление токена ─────────────────────────────

  Future<bool> refreshToken() async {
    if (!AppConfig.featureAuth) return false;
    try {
      final res = await ApiService().post('/auth/refresh', {});
      final token = res['token'] as String?;
      if (token != null) { ApiService().setToken(token); return true; }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Выход ─────────────────────────────────────────

  Future<void> signOut() async {
    try {
      if (AppConfig.featureAuth) await ApiService().post('/auth/logout', {});
    } catch (_) {}
    ApiService().clearToken();
    _currentUser = null;
  }

  // ── Гостевой режим ────────────────────────────────

  AuthResult _guestResult() {
    _currentUser = {
      'id':           'guest_local',
      'email':        'guest@local',
      'display_name': 'Гость',
      'is_premium':   0,
      'plan':         'free',
      'created_at':   DateTime.now().toIso8601String(),
      'updated_at':   DateTime.now().toIso8601String(),
    };
    return AuthResult.success(_currentUser!);
  }
}

class AuthResult {
  final bool success;
  final Map<String, dynamic>? user;
  final String? error;

  const AuthResult._({required this.success, this.user, this.error});

  factory AuthResult.success(Map<String, dynamic> user) =>
      AuthResult._(success: true, user: user);

  factory AuthResult.error(String message) =>
      AuthResult._(success: false, error: message);
}
