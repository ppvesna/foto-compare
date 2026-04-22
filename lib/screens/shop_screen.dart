import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _cat = 0;
  final _cats = ['Все', '⭐ Подписки', '🤖 AI', '📢 Реклама', '🔌 API'];

  final _items = [
    {
      'icon': '⭐',
      'name': 'Premium Pro',
      'desc': 'Полный доступ. AI анализ, без ограничений.',
      'price': '€9.99/мес',
      'badge': 'Топ',
      'featured': true,
      'features': [
        'Неограниченные сравнения',
        'AI анализ отличий',
        'Серверная обработка'
      ]
    },
    {
      'icon': '🤖',
      'name': 'AI Анализ',
      'desc': '50 AI анализов в месяц на русском.',
      'price': '€4.99/мес',
      'badge': 'Pro',
      'featured': false,
      'features': ['50 анализов/мес', 'Русский язык']
    },
    {
      'icon': '📢',
      'name': 'Рекламное место',
      'desc': 'Баннер в магазине. До 10,000 показов/мес.',
      'price': '€49/мес',
      'badge': 'Новинка',
      'featured': false,
      'features': ['Баннер 30 дней', 'Аналитика']
    },
    {
      'icon': '🔌',
      'name': 'API Доступ',
      'desc': 'REST API. 10,000 запросов/мес.',
      'price': '€19.99/мес',
      'badge': 'Dev',
      'featured': false,
      'features': ['10,000 запросов', 'SDK Python/JS']
    },
    {
      'icon': '🎁',
      'name': 'Бесплатный план',
      'desc': 'Базовые функции. Уже активен.',
      'price': 'Бесплатно',
      'badge': 'Активен ✓',
      'featured': false,
      'features': ['10 сравнений/день', '3 режима просмотра']
    },
    {
      'icon': '📦',
      'name': 'Пакет 100 сравн.',
      'desc': 'Разовая покупка. Не истекают.',
      'price': '€2.99',
      'badge': 'Разово',
      'featured': false,
      'features': ['100 сравнений', 'Все режимы']
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '🛒', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
              label: 'Мои покупки',
              icon: '🛍️',
              onTap: () =>
                  xpDlg(context, 'Мои покупки', 'Активный план: Бесплатный')),
          XpMenuItem(
              label: 'Восстановить покупки',
              icon: '🔄',
              onTap: () =>
                  xpDlg(context, 'Восстановить', 'Поиск активных подписок...')),
        ]),
        XpMenu(label: 'Вид', items: [
          ..._cats.asMap().entries.map((e) => XpMenuItem(
                label: e.value,
                onTap: () => setState(() => _cat = e.key),
              )),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(
              label: 'О магазине',
              icon: '❓',
              onTap: () => xpDlg(context, 'О магазине',
                  'Оплата в EUR через Stripe.\nВозврат в течение 14 дней.\nsupport@photocompare.app')),
        ]),
      ]),

      // Поиск
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Expanded(child: XpInput(placeholder: '🔍 Поиск...')),
          const SizedBox(width: 6),
          XpBtn(label: 'Найти', onPressed: () {}),
        ]),
      ),

      // Категории
      SizedBox(
        height: 32,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _cats.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => setState(() => _cat = i),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _cat == i ? AppTheme.blue : null,
                gradient: _cat == i ? null : AppTheme.btnGrad,
                border: Border.all(
                    color: _cat == i ? AppTheme.blueDark : AppTheme.border),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(_cats[i],
                  style: TextStyle(
                      fontSize: 11,
                      color: _cat == i ? Colors.white : Colors.black)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),

      // Карточки
      Expanded(
          child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => _card(_items[i]),
      )),

      XpStatusBar(
          left: '${_items.length} предложений · EUR', right: '👤 Бесплатный'),
    ]);
  }

  Widget _card(Map<String, dynamic> item) {
    final isFree = item['price'] == 'Бесплатно';
    return GestureDetector(
      onTap: isFree
          ? null
          : () => _buy(item['name'] as String, item['price'] as String),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (item['featured'] as bool)
              ? const Color(0xFFEEF3FF)
              : Colors.white,
          border: Border.all(
            color: (item['featured'] as bool)
                ? AppTheme.blue
                : AppTheme.silverDark,
            width: (item['featured'] as bool) ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['icon'] as String,
              style: TextStyle(fontSize: (item['featured'] as bool) ? 36 : 26)),
          const SizedBox(height: 4),
          Text(item['name'] as String,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(item['desc'] as String,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ...((item['features'] as List).map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Row(children: [
                  const Text('✓ ',
                      style: TextStyle(color: AppTheme.simHigh, fontSize: 10)),
                  Expanded(
                      child: Text(f,
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis)),
                ]),
              ))),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(item['price'] as String,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isFree ? AppTheme.simHigh : AppTheme.blue)),
            if (!isFree)
              XpBtn(
                  label: 'Купить',
                  primary: true,
                  onPressed: () =>
                      _buy(item['name'] as String, item['price'] as String))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FFE8),
                  border: Border.all(color: AppTheme.simHigh),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(item['badge'] as String,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.simHigh,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
        ]),
      ),
    );
  }

  void _buy(String name, String price) {
    xpDlg(context, 'Покупка: $name',
        'Цена: $price\n\nОплата через Stripe:\n• Visa / Mastercard\n• Apple Pay / Google Pay\n\nВалюта: EUR. Возврат 14 дней.');
  }
}


// ════════════════════════════════════════════════════
// SETTINGS SCREEN
// ════════════════════════════════════════════════════

