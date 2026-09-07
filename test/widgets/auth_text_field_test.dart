import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.binding.setSurfaceSize(const Size(390, 844));
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
}
