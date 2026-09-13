import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_compare/features/auth/auth.dart';
import 'package:photo_compare/screens/start_screen.dart';
import 'package:photo_compare/widgets/auth_text_field.dart';

void main() {
  testWidgets('password field can show and hide its value', (tester) async {
    final controller = TextEditingController(text: 'secret-password');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthTextField(
            label: 'Пароль',
            hint: 'Введите пароль',
            controller: controller,
            icon: Icons.lock_outline,
            password: true,
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
    expect(find.byTooltip('Показать пароль'), findsOneWidget);

    await tester.tap(find.byTooltip('Показать пароль'));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, false);
    expect(find.byTooltip('Скрыть пароль'), findsOneWidget);
  });

  testWidgets('start screen uses modern login and registration forms',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: StartScreen()));
    await tester.pumpAndSettle();

    expect(find.text('С возвращением'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-identity')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);

    await tester.tap(find.text('Регистрация'));
    await tester.pumpAndSettle();

    expect(find.text('Создайте аккаунт'), findsOneWidget);
    expect(find.text('Организация (необязательно)'), findsOneWidget);
    expect(find.byKey(const ValueKey('register-password')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('register-password-confirmation')),
      findsOneWidget,
    );
    expect(find.byTooltip('Показать пароль'), findsNWidgets(2));
  });

  testWidgets('forgot password validates email and requests a reset link',
      (tester) async {
    final service = MockPasswordRecoveryService();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StartScreen(passwordRecoveryService: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Забыли пароль?'));
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();
    expect(find.text('Восстановление пароля'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-email')),
      'неверный-email',
    );
    await tester.tap(
      find.byKey(const ValueKey('password-recovery-request-submit')),
    );
    await tester.pump();
    expect(find.text('Введите корректный email.'), findsOneWidget);
    expect(service.requestCount, 0);

    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-email')),
      ' User@Example.com ',
    );
    await tester.tap(
      find.byKey(const ValueKey('password-recovery-request-submit')),
    );
    await tester.pumpAndSettle();

    expect(service.requestCount, 1);
    expect(service.requestedEmail, 'user@example.com');
    expect(
      find.text('Если аккаунт с таким email существует, письмо отправлено.'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password explains the temporary email limit',
      (tester) async {
    final service = MockPasswordRecoveryService()
      ..requestError = const PasswordRecoveryException(
        'rate_limited',
        'Лимит писем временно исчерпан. Повторите запрос позже.',
      );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: StartScreen(passwordRecoveryService: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Забыли пароль?'));
    await tester.tap(find.text('Забыли пароль?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('password-recovery-email')),
      'user@example.com',
    );
    await tester.tap(
      find.byKey(const ValueKey('password-recovery-request-submit')),
    );
    await tester.pump();

    expect(
      find.text('Лимит писем временно исчерпан. Повторите запрос позже.'),
      findsOneWidget,
    );
  });
}
