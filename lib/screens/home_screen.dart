import 'package:flutter/material.dart';
import '../widgets/xp_widgets.dart';

class HomeScreen extends StatelessWidget {
  final String email;
  final String displayName;
  final String nickname;
  final String organizationName;
  final VoidCallback onOpenSettings;
  final VoidCallback onSignOut;

  const HomeScreen({
    super.key,
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.organizationName,
    required this.onOpenSettings,
    required this.onSignOut,
  });

  String get _shownNick =>
      nickname.trim().isEmpty ? 'не задан' : nickname.trim();
  String get _shownOrg =>
      organizationName.trim().isEmpty ? 'не указана' : organizationName.trim();
  String get _shownName =>
      displayName.trim().isEmpty ? 'профиль без имени' : displayName.trim();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: 'HM', menus: [
        XpMenu(label: 'Аккаунт', items: [
          XpMenuItem(
            label: 'Профиль',
            icon: 'ID',
            onTap: () => xpDlg(
              context,
              'Профиль',
              'Email: ${email.isEmpty ? 'не указан' : email}\nНик: $_shownNick\nОрганизация: $_shownOrg\nПлан: Бесплатный',
            ),
          ),
          XpMenuItem(
            label: 'Изменить план',
            icon: 'PL',
            onTap: onOpenSettings,
          ),
          XpMenuItem.sep,
          XpMenuItem(label: 'Выйти', icon: 'EX', onTap: onSignOut),
        ]),
      ]),
      Expanded(
        child: Stack(children: [
          const Positioned.fill(child: _HomePhotoBackground()),
          Positioned(
            left: 22,
            top: 18,
            child: _TriMatrixLogo(organizationName: _shownOrg),
          ),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 880;
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
                            _planPanel(context, width: 372),
                            const SizedBox(width: 42),
                            Expanded(child: _brandHero(wide: true)),
                          ],
                        )
                      : Column(
                          children: [
                            _brandHero(wide: false),
                            const SizedBox(height: 26),
                            _planPanel(context, width: double.infinity),
                          ],
                        ),
                ),
              ),
            );
          }),
        ]),
      ),
      XpStatusBar(left: 'Главная', right: 'План: Бесплатный'),
    ]);
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
        Text(
          'Помогаем вам\nразличить важное',
          textAlign: wide ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            color: const Color(0xFFF8FAFC),
            fontSize: wide ? 46 : 30,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
            shadows: const [
              Shadow(
                color: Color(0xCC000000),
                blurRadius: 18,
                offset: Offset(0, 5),
              ),
              Shadow(
                color: Color(0x5538BDF8),
                blurRadius: 20,
                offset: Offset(-2, -1),
              ),
            ],
          ),
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
            'Просмотровый стол, спектрофотометр, лупа печатника и цветовые различия - в одном спокойном рабочем пространстве.',
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

  Widget _planPanel(BuildContext context, {required double width}) {
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
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Рабочий профиль',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Photo Compare workspace',
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
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD6E7F0)),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _profileRow('Email', email.isEmpty ? 'не указан' : email),
              _profileRow('Ник', _shownNick),
              _profileRow('Имя', _shownName),
              _profileRow('Организация', _shownOrg),
              _profileRow('План', 'Бесплатный'),
              _profileRow('Лимит', '10 проверок в день'),
              _profileRow('Облако', 'протоколы и превью позже'),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(children: [
              Expanded(
                child: XpBtn(
                  label: 'Изменить план',
                  primary: true,
                  onPressed: onOpenSettings,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: XpBtn(label: 'Выйти', onPressed: onSignOut)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 74,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ]),
    );
  }
}

class _HomePhotoBackground extends StatelessWidget {
  const _HomePhotoBackground();

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

class _SoftChip extends StatelessWidget {
  final String text;
  const _SoftChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x40FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFF8FAFC),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TriMatrixLogo extends StatelessWidget {
  final String organizationName;

  const _TriMatrixLogo({required this.organizationName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF05070A), Color(0xFF20262C), Color(0xFF0A0D10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF46515A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 18,
            offset: Offset(0, 9),
          ),
          BoxShadow(
            color: Color(0x44A7F3FF),
            blurRadius: 12,
            offset: Offset(-2, -2),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF5E6A72), Color(0xFF171B20), Color(0xFF05070A)],
              stops: [0.0, 0.62, 1.0],
            ),
            border: Border.all(color: const Color(0xFF7C8A94)),
          ),
          child: const Center(
            child: Text(
              'TM',
              style: TextStyle(
                color: Color(0xFFE7EEF4),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
                shadows: [
                  Shadow(
                    color: Color(0xFF000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFF95A3AD),
                  Color(0xFFE8F7FF)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(rect),
              child: const Text(
                'TriMatrix',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  shadows: [
                    Shadow(
                      color: Color(0xFF000000),
                      blurRadius: 6,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              organizationName == 'не указана'
                  ? 'print inspection'
                  : organizationName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA8B3BC),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MiniPrismMark extends StatelessWidget {
  const _MiniPrismMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 38,
      child: CustomPaint(painter: _MiniPrismPainter()),
    );
  }
}

class _MiniPrismPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final prism = Path()
      ..moveTo(size.width * 0.50, size.height * 0.10)
      ..lineTo(size.width * 0.16, size.height * 0.86)
      ..lineTo(size.width * 0.88, size.height * 0.78)
      ..close();
    canvas.drawPath(
      prism,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xDDF8FAFC), Color(0x9967E8F9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      prism,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFF0F172A).withOpacity(0.28),
    );
    final colors = [
      const Color(0xFFE11D48),
      const Color(0xFF22C55E),
      const Color(0xFF2563EB),
    ];
    for (var i = 0; i < colors.length; i++) {
      final y = size.height * (0.28 + i * 0.14);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * 0.48, y + size.height * 0.08),
        Paint()
          ..color = colors[i].withOpacity(0.85)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
    final out = [
      const Color(0xFFFACC15),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
    ];
    for (var i = 0; i < out.length; i++) {
      final y = size.height * (0.34 + i * 0.13);
      canvas.drawLine(
        Offset(size.width * 0.62, y),
        Offset(size.width, y - size.height * (0.11 - i * 0.03)),
        Paint()
          ..color = out[i].withOpacity(0.9)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
