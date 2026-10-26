import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/auth/auth.dart';

void main() {
  test('recognizes recovery callbacks in query and fragment', () {
    expect(
      isPasswordRecoveryCallback(
        Uri.parse('https://app.example/#access_token=token&type=recovery'),
      ),
      true,
    );
    expect(
      isPasswordRecoveryCallback(
        Uri.parse('https://app.example/?type=recovery'),
      ),
      true,
    );
    expect(
      isPasswordRecoveryCallback(
        Uri.parse('https://app.example/#access_token=token&type=invite'),
      ),
      false,
    );
  });

  test('recognizes callback payloads in query and fragment', () {
    expect(
      hasAuthCallbackPayload(
        Uri.parse(
          'https://app.example/?type=recovery&error_code=otp_expired',
        ),
      ),
      true,
    );
    expect(
      hasAuthCallbackPayload(
        Uri.parse(
          'https://app.example/#access_token=token&refresh_token=refresh',
        ),
      ),
      true,
    );
    expect(
      hasAuthCallbackPayload(Uri.parse('https://app.example/?type=recovery')),
      false,
    );
  });

  test('recovery redirect keeps the current origin and adds a marker', () {
    expect(
      buildPasswordRecoveryRedirectUrl(
        Uri.parse('http://127.0.0.1:58216/current?old=1#section'),
      ),
      'http://127.0.0.1:58216/?type=recovery',
    );
  });
}
