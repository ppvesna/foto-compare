import 'package:flutter/material.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/auth_text_field.dart';
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
  bool _authBusy = false;
  late AnimationController _ctrl;
  late Animation<double> _fade;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();
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
    _nickCtrl.dispose();
    _orgCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: Stack(
        children: [
          const Positioned.fill(child: _HeroPhotoBackground()),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: LayoutBuilder(builder: (context, constraints) {
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
                                _authPanel(width: 420),
                                const SizedBox(width: 52),
                                Expanded(child: _brandHero(wide: true)),
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
            ),
          ),
        ],
      ),
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
        color: const Color(0xF7FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x55FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 38,
            offset: Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLogin ? 'С возвращением' : 'Создайте аккаунт',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _isLogin
                          ? 'Войдите в рабочее пространство'
                          : 'Заполните данные для нового профиля',
                      style: const TextStyle(
                        fontSize: 13,
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: [
              _tab('Вход', _isLogin, () => setState(() => _isLogin = true)),
              const SizedBox(width: 6),
              _tab('Регистрация', !_isLogin,
                  () => setState(() => _isLogin = false)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: _isLogin ? _loginForm() : _registerForm(),
          ),
        ]),
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
              border: Border.all(
                color:
                    active ? const Color(0xFF1D4ED8) : const Color(0xFFE2E8F0),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active ? Colors.white : const Color(0xFF475569),
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return AutofillGroup(
      child: Column(children: [
        AuthTextField(
          key: const ValueKey('login-identity'),
          label: 'Email или ник',
          hint: 'user@example.com или printer_oleg',
          controller: _emailCtrl,
          icon: Icons.person_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [
            AutofillHints.username,
            AutofillHints.email,
          ],
        ),
        const SizedBox(height: 12),
        AuthTextField(
          key: const ValueKey('login-password'),
          label: 'Пароль',
          hint: 'Введите пароль',
          controller: _passCtrl,
          icon: Icons.lock_outline,
          password: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) {
            if (!_authBusy) _doLogin();
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 0,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Text('Запомнить меня', style: TextStyle(fontSize: 12)),
            ]),
            TextButton(
              onPressed: () => xpDlg(
                context,
                'Восстановление пароля',
                'Введите email для сброса пароля',
              ),
              child: const Text('Забыли пароль?'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('login-submit'),
            onPressed: _authBusy ? null : _doLogin,
            icon: _authBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.login, size: 19),
            label: Text(_authBusy ? 'Входим...' : 'Войти'),
          ),
        ),
      ]),
    );
  }

  Widget _registerForm() {
    return AutofillGroup(
      child: Column(children: [
        AuthTextField(
          label: 'Имя',
          hint: 'Иван Иванов',
          controller: _nameCtrl,
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 12),
        AuthTextField(
          label: 'Ник пользователя',
          hint: 'printer_oleg',
          controller: _nickCtrl,
          icon: Icons.alternate_email,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 12),
        AuthTextField(
          label: 'Организация (необязательно)',
          hint: 'Типография или отдел',
          controller: _orgCtrl,
          icon: Icons.business_outlined,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.organizationName],
        ),
        const SizedBox(height: 12),
        AuthTextField(
          label: 'Email',
          hint: 'user@example.com',
          controller: _emailCtrl,
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 12),
        AuthTextField(
          key: const ValueKey('register-password'),
          label: 'Пароль',
          hint: 'Минимум 8 символов',
          controller: _passCtrl,
          icon: Icons.lock_outline,
          password: true,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 12),
        AuthTextField(
          key: const ValueKey('register-password-confirmation'),
          label: 'Подтвердите пароль',
          hint: 'Повторите пароль',
          controller: _pass2Ctrl,
          icon: Icons.lock_reset_outlined,
          password: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) {
            if (!_authBusy) _doRegister();
          },
        ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Пароль должен содержать не менее 8 символов.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('register-submit'),
            onPressed: _authBusy ? null : _doRegister,
            icon: _authBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_alt_1, size: 19),
            label: Text(_authBusy ? 'Создаём...' : 'Создать аккаунт'),
          ),
        ),
      ]),
    );
  }

  String _normalizeNick(String value) {
    return value.trim().toLowerCase();
  }

  bool _looksLikeEmail(String value) {
    return value.contains('@');
  }

  Future<void> _saveLocalNickEmail(String nickname, String email) async {
    final nick = _normalizeNick(nickname);
    final cleanEmail = email.trim();
    if (nick.isEmpty || cleanEmail.isEmpty || !_looksLikeEmail(cleanEmail)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nick_email_$nick', cleanEmail);
  }

  Future<bool> _isNickAvailable(String nickname) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'is_nickname_available_v1',
        params: {'target_nickname': _normalizeNick(nickname)},
      );
      if (response is bool) return response;
    } catch (_) {
      // Migration 010 is optional during rollout.
    }
    try {
      final row = await Supabase.instance.client
          .from('user_profiles')
          .select('user_id')
          .eq('nickname', _normalizeNick(nickname))
          .maybeSingle();
      return row == null;
    } catch (_) {
      return true;
    }
  }

  Future<void> _saveUserProfile({
    required String userId,
    required String email,
    required String nickname,
    required String displayName,
    String organizationName = '',
  }) async {
    await _saveLocalNickEmail(nickname, email);
    try {
      await Supabase.instance.client.from('user_profiles').upsert({
        'user_id': userId,
        'email': email,
        'nickname': _normalizeNick(nickname),
        'display_name': displayName,
        'organization_name': organizationName,
      });
    } catch (_) {
      // Таблица профилей может быть ещё не применена в Supabase.
      // Auth-аккаунт уже создан/выполнен, не блокируем пользователя.
    }
  }

  void _doLogin() async {
    final login = _emailCtrl.text.trim();
    if (login.isEmpty || _passCtrl.text.isEmpty) {
      xpDlg(context, 'Ошибка', 'Введите email или ник и пароль');
      return;
    }
    setState(() => _authBusy = true);
    try {
      if (_looksLikeEmail(login)) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: login,
          password: _passCtrl.text,
        );
      } else {
        final response = await Supabase.instance.client.functions.invoke(
          'login-by-nickname',
          body: {
            'nickname': _normalizeNick(login),
            'password': _passCtrl.text,
          },
        );
        final data = response.data;
        if (data is! Map || data['refreshToken'] is! String) {
          throw StateError('Invalid nickname or password');
        }
        await Supabase.instance.client.auth.setSession(
          data['refreshToken'] as String,
        );
      }
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final email = user.email ?? login;
        final metadata = user.userMetadata ?? {};
        final nickname = metadata['nickname'] as String?;
        final displayName = metadata['display_name'] as String?;
        if (nickname != null && nickname.isNotEmpty) {
          await _saveUserProfile(
            userId: user.id,
            email: user.email ?? email,
            nickname: nickname,
            displayName: displayName ?? '',
            organizationName: (metadata['organization_name'] as String?) ?? '',
          );
        } else if (_looksLikeEmail(email)) {
          await _saveLocalNickEmail(email.split('@').first, email);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Вход выполнен!'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка входа', _authErrorText(e));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  void _doRegister() async {
    if (_authBusy) return;
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      xpDlg(context, 'Ошибка', 'Введите корректный email.');
      return;
    }
    if (_passCtrl.text.length < 8) {
      xpDlg(context, 'Ошибка', 'Пароль должен содержать минимум 8 символов.');
      return;
    }
    if (_passCtrl.text != _pass2Ctrl.text) {
      xpDlg(context, 'Ошибка', 'Пароли не совпадают');
      return;
    }
    final nick = _normalizeNick(_nickCtrl.text);
    if (_nameCtrl.text.trim().isEmpty || nick.isEmpty) {
      xpDlg(context, 'Ошибка', 'Заполните имя и ник пользователя.');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(nick)) {
      xpDlg(context, 'Ошибка',
          'Ник: 3-24 символа, латиница, цифры и подчёркивание.');
      return;
    }
    setState(() => _authBusy = true);
    final nickAvailable = await _isNickAvailable(nick);
    if (!nickAvailable) {
      if (mounted) xpDlg(context, 'Ошибка', 'Такой ник уже занят.');
      if (mounted) setState(() => _authBusy = false);
      return;
    }
    try {
      final name = _nameCtrl.text.trim();
      final organization = _orgCtrl.text.trim();
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _passCtrl.text,
        data: {
          'display_name': name,
          'nickname': nick,
          'organization_name': organization,
        },
      );
      final user = response.user;
      if (user != null) {
        await _saveUserProfile(
          userId: user.id,
          email: email,
          nickname: nick,
          displayName: name,
          organizationName: organization,
        );
      }
      if (mounted) {
        xpDlg(
          context,
          'Готово',
          'Аккаунт создан.\nЕсли приложение не вошло автоматически, откройте вкладку "Вход" и войдите по email: $email',
        );
        setState(() => _isLogin = true);
      }
    } catch (e) {
      if (mounted) xpDlg(context, 'Ошибка регистрации', _authErrorText(e));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  String _authErrorText(Object e) {
    final text = e.toString();
    final lower = text.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'Неверный email/ник или пароль. Попробуйте войти по email аккаунта.';
    }
    if (lower.contains('invalid nickname or password')) {
      return 'Неверный ник или пароль.';
    }
    if (lower.contains('login-by-nickname')) {
      return 'Защищённый вход по нику ещё не подключён на сервере. Пока войдите по email.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Email ещё не подтверждён. Откройте письмо Supabase и подтвердите аккаунт.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'Нет соединения с сервером авторизации. Проверьте интернет и повторите вход.';
    }
    return text;
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
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xE60B111D),
                Color(0x9D111827),
                Color(0x33111827),
              ],
              stops: [0.0, 0.48, 1.0],
            ),
          ),
        ),
      ),
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.32, 0.10),
              radius: 1.15,
              colors: [
                Color(0x00111827),
                Color(0x77111827),
                Color(0xC90B111D),
              ],
              stops: [0.0, 0.58, 1.0],
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
    return const SizedBox(
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
