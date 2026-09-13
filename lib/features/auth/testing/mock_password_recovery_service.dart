import '../domain/password_recovery_service.dart';

class MockPasswordRecoveryService implements PasswordRecoveryService {
  int requestCount = 0;
  int completeCount = 0;
  String? requestedEmail;
  String? requestedRedirectTo;
  String? completedPassword;
  Object? requestError;
  Object? completeError;

  @override
  Future<void> requestReset({
    required String email,
    String? redirectTo,
  }) async {
    requestCount++;
    requestedEmail = email;
    requestedRedirectTo = redirectTo;
    if (requestError != null) throw requestError!;
  }

  @override
  Future<void> completeReset({required String newPassword}) async {
    completeCount++;
    completedPassword = newPassword;
    if (completeError != null) throw completeError!;
  }
}
