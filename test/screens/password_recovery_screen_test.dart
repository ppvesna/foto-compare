import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/auth/auth.dart';
import 'package:photo_compare/screens/password_recovery_screen.dart';

void main() {
  testWidgets('new password must match before recovery completes',
      (tester) async {
    final service = MockPasswordRecoveryService();

    await tester.pumpWidget(
      MaterialApp(
        home: PasswordRecoveryScreen(
          service: service,
          onCompleted: () async {},
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-new-password')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-confirmation')),
      'another-password',
    );
    await tester.pump();
    expect(find.text('Пароли пока не совпадают.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('password-recovery-complete-submit')),
    );
    await tester.pump();
    expect(find.text('Пароли не совпадают.'), findsOneWidget);
    expect(service.completeCount, 0);
  });

  testWidgets('successful recovery returns to login on confirmation',
      (tester) async {
    final service = MockPasswordRecoveryService();
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PasswordRecoveryScreen(
          service: service,
          onCompleted: () async => completed = true,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-new-password')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-confirmation')),
      'new-password-123',
    );
    await tester.pump();
    expect(find.text('Пароли совпадают.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('password-recovery-complete-submit')),
    );
    await tester.pumpAndSettle();
    expect(service.completeCount, 1);
    expect(service.completedPassword, 'new-password-123');
    expect(find.text('Пароль изменён'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('password-recovery-return-to-login')),
    );
    await tester.pump();
    expect(completed, true);
  });
}
