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
}
