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
      backgroundColor: const Color(0xFF111827),
      body: Column(children: [
        XpMenuBar(
          icon: 'PR',
          menus: [
            XpMenu(label: 'Файл', items: [
              XpMenuItem(
                  label: 'Войти',
                  icon: 'IN',
                  onTap: () => setState(() => _isLogin = true)),
              XpMenuItem(
                  label: 'Зарегистрироваться',
                  icon: '+',
                  onTap: () => setState(() => _isLogin = false)),
              XpMenuItem.sep,
              XpMenuItem(
                  label: 'Забыли пароль?',
                  icon: '?',
                  onTap: () => xpDlg(context, 'Восстановление пароля',
                      'Введите email для сброса пароля')),
            ]),
            XpMenu(label: 'Справка', items: [
              XpMenuItem(
                  label: 'О программе',
                  icon: 'i',
                  onTap: () => xpDlg(context, 'О программе',
                      'Photo Compare v1.0\nИнструмент сравнения изображений.\n© 2026 Photo Compare')),
              XpMenuItem(
                  label: 'Поддержка',
                  icon: '@',
                  onTap: () =>
                      xpDlg(context, 'Поддержка', 'support@photocompare.app')),
            ]),
          ],
        ),
        Expanded(
          child: FadeTransition(
            opacity: _fade,
            child: Stack(children: [
              const Positioned.fill(child: _HeroPhotoBackground()),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 44 : 18,
                    vertical: wide ? 42 : 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (wide ? 84 : 48),
                    ),
                    child: Center(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: _brandHero(wide: true)),
                                const SizedBox(width: 34),
                                _authPanel(width: 360),
                              ],
                            )
                          : Column(
                              children: [
                                _brandHero(wide: false),
                                const SizedBox(height: 26),
                                _authPanel(width: double.infinity),
                              ],
                            ),
                    ),
                  ),
                );
              }),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _brandHero({required bool wide}) {
    return Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: wide ? 560 : 340,
          child: const Text(
            'Photo Compare',
            textAlign: TextAlign.left,
            style: TextStyle(
              color: Color(0xFFF8FAFC),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
              shadows: [
                Shadow(
                  color: Color(0xAA000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _DimensionalTitle(
          text: 'Помогаем вам\nразличить важное',
          align: wide ? TextAlign.left : TextAlign.center,
          fontSize: wide ? 46 : 30,
        ),
        const SizedBox(height: 18),
        Container(
          width: wide ? 540 : 330,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0x66111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Text(
            'Просмотровый стол, спектрофотометр, лупа печатника и цветовые различия — в одном спокойном рабочем пространстве.',
            textAlign: wide ? TextAlign.left : TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 15,
              height: 1.5,
              letterSpacing: 0,
              shadows: [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: const [
            _SoftChip('RGB'),
            _SoftChip('CMY'),
            _SoftChip('Delta E'),
            _SoftChip('Print inspection'),
          ],
        ),
      ],
    );
  }

  Widget _authPanel({required double width}) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xEEF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x55FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 26,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Photo Compare',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Color analysis workspace',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const _MiniPrismMark(),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              _tab('Вход', _isLogin, () => setState(() => _isLogin = true)),
              const SizedBox(width: 8),
              _tab('Регистрация', !_isLogin,
                  () => setState(() => _isLogin = false)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: _isLogin ? _loginForm() : _registerForm(),
          ),
        ]),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
          border: Border.all(
            color: active ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x332563EB),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : const Color(0xFF334155),
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return AutofillGroup(
        child: Column(children: [
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Email:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'user@example.com',
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email]),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Пароль:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: '••••••••',
          obscure: true,
          controller: _passCtrl,
          autofillHints: const [AutofillHints.password]),
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
    ]));
  }

  Widget _registerForm() {
    return AutofillGroup(
        child: Column(children: [
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Имя:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'Иван Иванов',
          controller: _nameCtrl,
          autofillHints: const [AutofillHints.name]),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Email:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'user@example.com',
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email]),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Пароль:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'Минимум 8 символов',
          obscure: true,
          controller: _passCtrl,
          autofillHints: const [AutofillHints.newPassword]),
      const SizedBox(height: 8),
      const Align(
          alignment: Alignment.centerLeft,
          child: Text('Подтвердите пароль:', style: TextStyle(fontSize: 11))),
      const SizedBox(height: 3),
      XpInput(
          placeholder: 'Повторите пароль',
          obscure: true,
          controller: _pass2Ctrl,
          autofillHints: const [AutofillHints.newPassword]),
      const Divider(),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        XpBtn(
            label: 'Создать аккаунт →', primary: true, onPressed: _doRegister),
      ]),
    ]));
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

class _HeroPhotoBackground extends StatelessWidget {
  const _HeroPhotoBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: Image.asset(
          'assets/images/start-hero-prism-lab.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0xE60B111D),
                Color(0x9D111827),
                Color(0x33111827),
              ],
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.32, 0.10),
              radius: 1.15,
              colors: const [
                Color(0x00111827),
                Color(0x77111827),
                Color(0xC90B111D),
              ],
              stops: const [0.0, 0.58, 1.0],
            ),
          ),
        ),
      ),
    ]);
  }
}

class _DimensionalTitle extends StatelessWidget {
  final String text;
  final TextAlign align;
  final double fontSize;

  const _DimensionalTitle({
    required this.text,
    required this.align,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Transform.translate(
        offset: const Offset(0, 4),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            color: const Color(0x7A000000),
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            height: 1.03,
            letterSpacing: 0,
          ),
        ),
      ),
      Text(
        text,
        textAlign: align,
        style: TextStyle(
          foreground: Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFE7EEF8),
                Color(0xFFB8C7DB),
              ],
            ).createShader(const Rect.fromLTWH(0, 0, 700, 140)),
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1.03,
          letterSpacing: 0,
          shadows: const [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
            Shadow(
              color: Color(0x667DD3FC),
              blurRadius: 18,
              offset: Offset(0, -1),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _SoftChip extends StatelessWidget {
  final String label;
  const _SoftChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1CFFFFFF),
        border: Border.all(color: const Color(0x2EFFFFFF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD7E1F0),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _MiniPrismMark extends StatelessWidget {
  const _MiniPrismMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 34,
      child: CustomPaint(painter: _PrismPainter(mini: true)),
    );
  }
}

// ── Мягкая призма RGB → CMY ──────────────────────────
class _PrismPainter extends CustomPainter {
  final bool mini;
  const _PrismPainter({this.mini = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final apex = Offset(w * 0.50, h * 0.15);
    final baseL = Offset(w * 0.34, h * 0.78);
    final baseR = Offset(w * 0.66, h * 0.78);

    final prism = Path()
      ..moveTo(apex.dx, apex.dy)
      ..lineTo(baseL.dx, baseL.dy)
      ..lineTo(baseR.dx, baseR.dy)
      ..close();

    final glassFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x2DE0F2FE), Color(0x0FFFFFFF)],
      ).createShader(Rect.fromPoints(apex, baseR));
    canvas.drawPath(prism, glassFill);
    canvas.drawPath(
      prism,
      Paint()
        ..color = const Color(0x88D7E7F7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = mini ? 1.0 : 1.4,
    );

    final entry = Offset((apex.dx + baseL.dx) / 2, (apex.dy + baseL.dy) / 2);
    final exit = Offset((apex.dx + baseR.dx) / 2, (apex.dy + baseR.dy) / 2);
    final gap = mini ? h * 0.10 : h * 0.075;
    final leftPad = mini ? -w * 0.02 : 0.0;
    final rightPad = mini ? w * 1.02 : w;

    final incoming = [
      (Offset(leftPad, entry.dy - gap), const Color(0xFFFF7A6B)),
      (Offset(leftPad, entry.dy), const Color(0xFF7DD3A7)),
      (Offset(leftPad, entry.dy + gap), const Color(0xFF8AB4F8)),
    ];
    for (final ray in incoming) {
      _ray(canvas, ray.$1, entry, ray.$2);
    }

    final outgoing = [
      (Offset(rightPad, exit.dy - gap * 1.15), const Color(0xFF67E8F9)),
      (Offset(rightPad, exit.dy), const Color(0xFFF0A4D8)),
      (Offset(rightPad, exit.dy + gap * 1.15), const Color(0xFFF8D86B)),
    ];
    for (final ray in outgoing) {
      _ray(canvas, exit, ray.$1, ray.$2, reverse: true);
    }

    final pointPaint = Paint()
      ..color = const Color(0x88FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawCircle(entry, mini ? 1.6 : 2.5, pointPaint);
    canvas.drawCircle(exit, mini ? 1.8 : 2.8, pointPaint);
  }

  void _ray(Canvas canvas, Offset from, Offset to, Color color,
      {bool reverse = false}) {
    final angle = atan2(to.dy - from.dy, to.dx - from.dx);
    final width = mini ? 1.5 : 3.0;
    final perp = Offset(-sin(angle) * width, cos(angle) * width);
    final path = Path()
      ..moveTo(from.dx + perp.dx, from.dy + perp.dy)
      ..lineTo(to.dx + perp.dx, to.dy + perp.dy)
      ..lineTo(to.dx - perp.dx, to.dy - perp.dy)
      ..lineTo(from.dx - perp.dx, from.dy - perp.dy)
      ..close();
    final grad = LinearGradient(
      colors: reverse
          ? [color.withValues(alpha: 0.58), color.withValues(alpha: 0.08)]
          : [color.withValues(alpha: 0.08), color.withValues(alpha: 0.58)],
    );
    canvas.drawPath(
        path,
        Paint()
          ..shader = grad.createShader(Rect.fromPoints(from, to))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, mini ? 0.6 : 1.2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
