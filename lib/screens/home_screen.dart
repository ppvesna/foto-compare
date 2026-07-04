import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

class HomeScreen extends StatelessWidget {
  final String email;
  final VoidCallback onOpenCompare;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenSettings;
  final VoidCallback onSignOut;

  const HomeScreen({
    super.key,
    required this.email,
    required this.onOpenCompare,
    required this.onOpenChat,
    required this.onOpenSettings,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: 'HM', menus: [
        XpMenu(label: 'Навигация', items: [
          XpMenuItem(label: 'Сравнение', icon: 'CP', onTap: onOpenCompare),
          XpMenuItem(label: 'Чат', icon: 'CH', onTap: onOpenChat),
          XpMenuItem(label: 'Настройки', icon: 'ST', onTap: onOpenSettings),
        ]),
        XpMenu(label: 'Аккаунт', items: [
          XpMenuItem(
            label: 'Профиль',
            icon: 'ID',
            onTap: () => xpDlg(
              context,
              'Профиль',
              'Email: ${email.isEmpty ? 'не указан' : email}\nНик и организация будут загружаться из профиля Supabase.',
            ),
          ),
          XpMenuItem(label: 'Выйти', icon: 'EX', onTap: onSignOut),
        ]),
      ]),
      Expanded(
        child: Stack(children: [
          const Positioned.fill(child: _HomeBackground()),
          Positioned.fill(
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: wide ? 28 : 14,
                  vertical: 18,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1220),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: _hero(context)),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 4,
                                child: Column(children: [
                                  _accountPanel(context),
                                  const SizedBox(height: 12),
                                  _shopPanel(context),
                                ]),
                              ),
                            ],
                          )
                        : Column(children: [
                            _hero(context),
                            const SizedBox(height: 12),
                            _accountPanel(context),
                            const SizedBox(height: 12),
                            _shopPanel(context),
                          ]),
                  ),
                ),
              );
            }),
          ),
        ]),
      ),
      XpStatusBar(left: 'Главная', right: 'Навигация · аккаунт · магазин'),
    ]);
  }

  Widget _hero(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xDDF8FCFF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x88FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 24,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Photo Compare',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F3F5A),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Помогаем вам различить важное',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1.05,
              color: Color(0xFF102A3A),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Главная страница остается внутри программы: отсюда можно перейти к сравнению, открыть чат организации, управлять профилем и выбрать тариф.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _bigAction('Начать сравнение', onOpenCompare, primary: true),
            _bigAction('Открыть чат', onOpenChat),
            _bigAction('Настройки', onOpenSettings),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      _siteNavPanel(),
    ]);
  }

  Widget _siteNavPanel() {
    final items = const [
      ('Сравнение', 'Эталон, образец, карта Delta E, ЧБ-геометрия'),
      ('Чат', 'Обсуждение проверки, удаленный просмотр картинок'),
      ('Протокол', 'Последняя проверка, метрики, история'),
      ('Магазин', 'Тарифы, AI, облако, API'),
    ];
    return _panel(
      title: 'Навигация по сайту',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          return Container(
            width: 260,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFC9E2F0)),
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.shadowSubtle,
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                item.$1,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                item.$2,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.35,
                  color: Colors.black54,
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _accountPanel(BuildContext context) {
    return _panel(
      title: 'Регистрация и профиль',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _profileRow('Email', email.isEmpty ? 'не указан' : email),
        _profileRow('Ник', 'будет храниться в профиле'),
        _profileRow('Организация', 'группа для чата и проверок'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: XpBtn(
              label: 'Профиль',
              primary: true,
              onPressed: () => xpDlg(
                context,
                'Профиль',
                'Здесь позже будет редактирование ника, организации и прав доступа.',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: XpBtn(label: 'Выйти', onPressed: onSignOut)),
        ]),
      ]),
    );
  }

  Widget _shopPanel(BuildContext context) {
    final offers = const [
      _Offer('Бесплатный', '10 проверок в день', 'Активен', true),
      _Offer('Pro', 'AI-анализ, облако, отчеты', '€9.99/мес', false),
      _Offer('AI анализ', '50 заключений в месяц', '€4.99/мес', false),
      _Offer('API', 'интеграция с сайтом', '€19.99/мес', false),
      _Offer('Пакет 100', 'разовые проверки', '€2.99', false),
    ];
    return _panel(
      title: 'Магазин',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
          'Пока это компактный витринный блок. Потом сюда подключим оплату, лимиты и историю покупок.',
          style: TextStyle(fontSize: 11, height: 1.35, color: Colors.black54),
        ),
        const SizedBox(height: 10),
        ...offers.map((offer) => _offerTile(context, offer)),
      ]),
    );
  }

  Widget _offerTile(BuildContext context, _Offer offer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: offer.active ? const Color(0xFFE8FFE8) : Colors.white,
        border: Border.all(
          color: offer.active ? AppTheme.simHigh : const Color(0xFFC9E2F0),
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              offer.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 3),
            Text(
              offer.desc,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text(
          offer.price,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: offer.active ? AppTheme.simHigh : AppTheme.blue,
          ),
        ),
        if (!offer.active) ...[
          const SizedBox(width: 8),
          XpBtn(
            label: 'Выбрать',
            onPressed: () => xpDlg(
              context,
              offer.name,
              '${offer.desc}\nЦена: ${offer.price}',
            ),
          ),
        ],
      ]),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEEF8FCFF),
        border: Border.all(color: const Color(0x88FFFFFF)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F3F5A),
          ),
        ),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _bigAction(String label, VoidCallback onTap, {bool primary = false}) {
    return SizedBox(
      width: 178,
      child: XpBtn(label: label, primary: primary, onPressed: onTap),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 92,
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

class _HomeBackground extends StatelessWidget {
  const _HomeBackground();

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
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [
                Color(0xBFEAF6FC),
                Color(0xDDF4FAFD),
                Color(0xEEF8FCFF),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Offer {
  final String name;
  final String desc;
  final String price;
  final bool active;

  const _Offer(this.name, this.desc, this.price, this.active);
}
