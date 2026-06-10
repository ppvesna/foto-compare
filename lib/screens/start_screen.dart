import 'package:flutter/material.dart';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _remember = false;
  late AnimationController _ctrl;
  late Animation<double> _fade;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(children: [
      XpMenuBar(
        icon: '🔭',
        menus: [
          XpMenu(label: 'Файл', items: [
            XpMenuItem(
                label: 'Войти',
                icon: '🔐',
                onTap: () => setState(() => _isLogin = true)),
            XpMenuItem(
                label: 'Зарегистрироваться',
                icon: '📝',
                onTap: () => setState(() => _isLogin = false)),
            XpMenuItem.sep,
            XpMenuItem(
                label: 'Забыли пароль?',
                icon: '🔑',
                onTap: () => xpDlg(context, 'Восстановление пароля',
                    'Введите email для сброса пароля')),
          ]),
          XpMenu(label: 'Справка', items: [
            XpMenuItem(
                label: 'О программе',
                icon: 'ℹ️',
                onTap: () => xpDlg(context, 'О программе',
                    'Photo Compare v1.0\nИнструмент сравнения изображений.\n© 2026 Photo Compare')),
            XpMenuItem(
                label: 'Поддержка',
                icon: '💬',
                onTap: () =>
                    xpDlg(context, 'Поддержка', 'support@photocompare.app')),
          ]),
        ],
      ),
      Expanded(
        child: SingleChildScrollView(
          child: FadeTransition(
            opacity: _fade,
            child: Stack(
              children: [
                Container(
                  color: Colors.black,
                  constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height),
                ),
                const Positioned.fill(child: _KanjiBg()),
                Center(
                  child: Column(children: [
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 340,
                      height: 190,
                      child: CustomPaint(painter: _PrismPainter()),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Мы видим то, что вы НЕ увидите',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text("WE SEE WHAT YOU CAN'T SEE",
                        style: TextStyle(
                            color: Color(0xAAFFFFFF),
                            fontSize: 11,
                            letterSpacing: 3,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    const Text('PHOTO COMPARE — COLOR ANALYSIS SYSTEM',
                        style: TextStyle(
                            color: Color(0x44FFFFFF),
                            fontSize: 9,
                            letterSpacing: 2)),
                    const SizedBox(height: 24),
                    Container(
                      width: 320,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(children: [
                        Row(children: [
                          _tab('Вход', _isLogin,
                              () => setState(() => _isLogin = true)),
                          _tab('Регистрация', !_isLogin,
                              () => setState(() => _isLogin = false)),
                        ]),
                        Container(
                          color: AppTheme.silver,
                          padding: const EdgeInsets.all(12),
                          child: _isLogin ? _loginForm() : _registerForm(),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
      ]),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppTheme.silver : AppTheme.silverDark,
          border: Border(
            top:
                BorderSide(color: active ? AppTheme.blue : AppTheme.silverDark),
            left:
                BorderSide(color: active ? AppTheme.blue : AppTheme.silverDark),
            right:
                BorderSide(color: active ? AppTheme.blue : AppTheme.silverDark),
            bottom: BorderSide(
                color: active ? AppTheme.silver : AppTheme.silverDark),
          ),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3), topRight: Radius.circular(3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? Colors.black : Colors.black54)),
      ),
    );
  }

  Widget _loginForm() {
    return Column(children: [
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Email:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'user@example.com',
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Пароль:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(placeholder: '••••••••', obscure: true, controller: _passCtrl),
      const SizedBox(height: 8),
      Row(children: [
        Checkbox(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        const Text('Запомнить меня', style: TextStyle(fontSize: 11)),
      ]),
      const Divider(),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        GestureDetector(
          onTap: () => xpDlg(context, 'Восстановление пароля',
              'Введите email для сброса пароля'),
          child: const Text('Забыли пароль?',
              style: TextStyle(fontSize: 10, color: AppTheme.blue)),
        ),
        XpBtn(label: 'Войти →', primary: true, onPressed: _doLogin),
      ]),
    ]);
  }

  Widget _registerForm() {
    return Column(children: [
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Имя:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(placeholder: 'Иван Иванов', controller: _nameCtrl),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Email:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'user@example.com',
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Пароль:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'Минимум 8 символов',
          obscure: true,
          controller: _passCtrl),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Подтвердите пароль:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'Повторите пароль',
          obscure: true,
          controller: _pass2Ctrl),
      const Divider(),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        XpBtn(
            label: 'Создать аккаунт →', primary: true, onPressed: _doRegister),
      ]),
    ]);
  }

  void _doLogin() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      xpDlg(context, 'Ошибка', 'Введите email и пароль');
      return;
    }
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Вход выполнен!'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка входа', e.toString());
    }
  }

  void _doRegister() async {
    if (_passCtrl.text != _pass2Ctrl.text) {
      xpDlg(context, 'Ошибка', 'Пароли не совпадают');
      return;
    }
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      xpDlg(context, 'Ошибка', 'Заполните все поля');
      return;
    }
    try {
      await Supabase.instance.client.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        data: {'display_name': _nameCtrl.text.trim()},
      );
      if (mounted) {
        xpDlg(context, 'Готово',
            'Аккаунт создан!\nПроверьте email для подтверждения.');
      }
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка регистрации', e.toString());
    }
  }
}

// ── Фон из иероглифов ────────────────────────────────
class _KanjiBg extends StatelessWidget {
  const _KanjiBg();

  @override
  Widget build(BuildContext context) {
    final text = '色光比較視覚認識赤緑青黄黒白紫橙色彩鮮明対比分析画像写真比較認識処理視覚光学' * 30;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text,
          style: const TextStyle(
              color: Color(0x08FFFFFF),
              fontSize: 12,
              fontFamily: 'serif',
              height: 1.8),
          softWrap: true),
    );
  }
}

// ── Призма Ньютона ───────────────────────────────────
class _PrismPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final apex = Offset(w * 0.5, h * 0.05);
    final baseL = Offset(w * 0.28, h * 0.95);
    final baseR = Offset(w * 0.72, h * 0.95);

    final prism = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..close();

    canvas.drawPath(
        prism,
        Paint()
          ..color = const Color(0x10B4D2FF)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        prism,
        Paint()
          ..color = const Color(0xBBC8E1FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    final entry = Offset((apex.dx + baseL.dx) / 2, (apex.dy + baseL.dy) / 2);
    final exit = Offset((apex.dx + baseR.dx) / 2, (apex.dy + baseR.dy) / 2);

    _ray(canvas, Offset(0, entry.dy - 14), entry, const Color(0xFFFF2200));
    _ray(canvas, Offset(0, entry.dy), entry, const Color(0xFF00EE00));
    _ray(canvas, Offset(0, entry.dy + 14), entry, const Color(0xFF2266FF));

    final colors = [
      const Color(0xFF00FFFF),
      const Color(0xFFFF00FF),
      const Color(0xFFFFEE00),
      const Color(0xFF999999),
    ];
    for (int i = 0; i < 4; i++) {
      final dy = (i - 1.5) * 24.0;
      _ray(canvas, exit, Offset(w, exit.dy + dy), colors[i], reverse: true);
    }

    canvas.drawCircle(
        entry,
        3,
        Paint()
          ..color = Colors.white.withOpacity(0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(
        exit,
        4,
        Paint()
          ..color = Colors.white.withOpacity(0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  void _ray(Canvas canvas, Offset from, Offset to, Color color,
      {bool reverse = false}) {
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    final perp = Offset(-sin(angle) * 3, cos(angle) * 3);
    final path = Path()
      ..moveTo(from.dx + perp.dx, from.dy + perp.dy)
      ..lineTo(to.dx + perp.dx, to.dy + perp.dy)
      ..lineTo(to.dx - perp.dx, to.dy - perp.dy)
      ..lineTo(from.dx - perp.dx, from.dy - perp.dy)
      ..close();
    final grad = LinearGradient(
      colors: reverse
          ? [color.withOpacity(0.9), color.withOpacity(0.05)]
          : [color.withOpacity(0.05), color.withOpacity(0.9)],
    );
    canvas.drawPath(
        path,
        Paint()
          ..shader = grad.createShader(Rect.fromPoints(from, to))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
