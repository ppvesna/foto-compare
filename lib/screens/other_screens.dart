import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

// ════════════════════════════════════════════════════
// CHAT SCREEN
// ════════════════════════════════════════════════════
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String _chatTitle   = 'Команда';
  String _chatStatus  = '● 4 онлайн';
  int    _activeChat  = 0;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _contacts = [
    {'av': '👥', 'name': 'Команда',      'last': 'Иван: новые результаты', 'type': 'g', 'badge': 3},
    {'av': '📸', 'name': 'Фотографы',    'last': 'Отличная работа!',        'type': 'g', 'badge': 0},
    {'av': '👨', 'name': 'Иван Петров',  'last': 'Спасибо!',                'type': 'u', 'badge': 1},
    {'av': '👩', 'name': 'Мария',        'last': 'Когда будет готово?',     'type': 'u', 'badge': 0},
    {'av': '🧑', 'name': 'Алексей',      'last': 'Ок, понял',               'type': 'u', 'badge': 0},
  ];

  final _messages = <Map<String, dynamic>>[
    {'av': '👨', 'name': 'Иван', 'text': 'Посмотрите новые результаты 📊', 'time': '10:24', 'out': false},
    {'av': '👩', 'name': 'Мария', 'text': 'Схожесть 87.4% — отлично!', 'time': '10:26', 'out': false},
    {'av': '👤', 'name': '', 'text': 'Отчёт готов, загружу в историю', 'time': '10:28 ✓✓', 'out': true},
    {'av': '🧑', 'name': 'Алексей', 'text': 'Проверьте новый алгоритм итераций', 'time': '10:31', 'out': false},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '💬', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(label: 'Новое сообщение', icon: '✉️',
              onTap: () => xpDlg(context, 'Новое сообщение', 'Выберите контакт или группу')),
          XpMenuItem(label: 'Создать группу', icon: '👥',
              onTap: () => xpDlg(context, 'Новая группа', 'Введите название группы')),
          XpMenuItem.sep,
          XpMenuItem(label: 'Экспорт истории', icon: '📤',
              onTap: () => xpDlg(context, 'Экспорт', 'История чата сохранена в TXT')),
        ]),
        XpMenu(label: 'Инструменты', items: [
          XpMenuItem(label: 'Поиск', icon: '🔍', shortcut: 'Ctrl+F',
              onTap: () => xpDlg(context, 'Поиск', 'Поиск по сообщениям')),
          XpMenuItem(label: 'Уведомления', icon: '🔔',
              onTap: () => xpDlg(context, 'Уведомления', 'Настройки уведомлений')),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(label: 'Горячие клавиши', icon: '⌨️',
              onTap: () => xpDlg(context, 'Горячие клавиши',
                  'Enter — отправить\nCtrl+N — новое сообщение')),
        ]),
      ]),

      Expanded(child: Row(children: [
        // Сайдбар контактов
        Container(
          width: 160,
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppTheme.silverDark))),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              color: AppTheme.blue,
              width: double.infinity,
              child: const Text('💬 Сообщения',
                  style: TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            // Поиск
            XpInput(placeholder: 'Поиск...', onChanged: (_) {}),
            // Список
            Expanded(child: ListView(children: [
              // Группы
              _sectionHeader('ГРУППЫ'),
              ..._contacts.where((c) => c['type'] == 'g').toList()
                  .asMap().entries.map((e) => _contact(e.key, e.value)),
              // Личные
              _sectionHeader('ЛИЧНЫЕ'),
              ..._contacts.where((c) => c['type'] == 'u').toList()
                  .asMap().entries.map((e) => _contact(e.key + 2, e.value)),
            ])),
            // Кнопка добавить
            Padding(
              padding: const EdgeInsets.all(6),
              child: SizedBox(width: double.infinity,
                child: XpBtn(label: '+ Добавить',
                    onPressed: () => xpDlg(context, 'Добавить контакт',
                        'Введите email пользователя'))),
            ),
          ]),
        ),

        // Основная область
        Expanded(child: Column(children: [
          // Шапка чата
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: AppTheme.silverDark,
            child: Row(children: [
              Text(_contacts[_activeChat]['av'] as String,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_chatTitle,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text(_chatStatus,
                    style: const TextStyle(fontSize: 10, color: AppTheme.simHigh)),
              ])),
              XpBtn(label: '👥', onPressed: () =>
                  xpDlg(context, 'Участники', 'Иван, Мария, Алексей, Анна')),
              const SizedBox(width: 4),
              XpBtn(label: '📎', onPressed: () =>
                  xpDlg(context, 'Прикрепить', 'Фото / Результат / Файл')),
            ]),
          ),
          // Панель инструментов
          Container(
            color: AppTheme.silver,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(children: [
              _toolBtn('Ж', bold: true),
              _toolBtn('К', italic: true),
              _toolBtn('🖼️'),
              _toolBtn('📎'),
              _toolBtn('🔍'),
              _toolBtn('😊'),
            ]),
          ),
          // Сообщения
          Expanded(child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _msgBubble(_messages[i]),
          )),
          // Ввод
          Container(
            padding: const EdgeInsets.all(6),
            color: AppTheme.silver,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: Container(
                constraints: const BoxConstraints(maxHeight: 80),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFF404040)),
                    left: BorderSide(color: Color(0xFF404040)),
                    right: BorderSide(color: Color(0xFFDFDFDF)),
                    bottom: BorderSide(color: Color(0xFFDFDFDF)),
                  ),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Введите сообщение... (Enter — отправить)',
                    hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                    contentPadding: EdgeInsets.all(6),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              )),
              const SizedBox(width: 6),
              Column(children: [
                XpBtn(label: 'Отправить', primary: true, onPressed: _send),
                const SizedBox(height: 4),
                XpBtn(label: '📎', onPressed: () =>
                    xpDlg(context, 'Файл', 'Выберите файл')),
              ]),
            ]),
          ),
        ])),
      ])),

      XpStatusBar(left: _chatTitle, right: '💬 ${_messages.length} сообщ.'),
    ]);
  }

  Widget _sectionHeader(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    color: const Color(0xFFF0ECE0),
    width: double.infinity,
    child: Text(text,
        style: const TextStyle(fontSize: 9, color: Colors.grey)),
  );

  Widget _contact(int idx, Map<String, dynamic> c) {
    final active = _activeChat == idx;
    final badge  = c['badge'] as int;
    return GestureDetector(
      onTap: () => setState(() {
        _activeChat = idx;
        _chatTitle  = c['name'] as String;
        _chatStatus = c['type'] == 'g'
            ? '${c['name']} — групповой чат'
            : '${c['name']} — в сети';
        _contacts[idx]['badge'] = 0;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: active ? AppTheme.blue : Colors.transparent,
        child: Row(children: [
          Text(c['av'] as String, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] as String,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: active ? Colors.white : Colors.black)),
              Text(c['last'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9,
                      color: active ? const Color(0xFFCCEEFF) : Colors.grey)),
            ],
          )),
          if (badge > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.red, borderRadius: BorderRadius.circular(8)),
            child: Text('$badge',
                style: const TextStyle(color: Colors.white, fontSize: 9)),
          ),
        ]),
      ),
    );
  }

  Widget _msgBubble(Map<String, dynamic> msg) {
    final isOut = msg['out'] as bool;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment:
            isOut ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isOut) ...[
            Text(msg['av'] as String, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
          ],
          Flexible(child: Column(
            crossAxisAlignment:
                isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isOut && (msg['name'] as String).isNotEmpty)
                Text(msg['name'] as String,
                    style: const TextStyle(fontSize: 9,
                        fontWeight: FontWeight.bold, color: AppTheme.blue)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isOut
                      ? const Color(0xFFE8FFE8)
                      : const Color(0xFFF0F4FF),
                  border: Border.all(
                    color: isOut
                        ? const Color(0xFFB8DDB8)
                        : const Color(0xFFC8D4FF)),
                  borderRadius: isOut
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(2),
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(2))
                      : const BorderRadius.only(
                          topLeft: Radius.circular(2),
                          topRight: Radius.circular(10),
                          bottomLeft: Radius.circular(2),
                          bottomRight: Radius.circular(10)),
                ),
                child: Text(msg['text'] as String,
                    style: const TextStyle(fontSize: 11, height: 1.4)),
              ),
              Text(msg['time'] as String,
                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ],
          )),
          if (isOut) ...[
            const SizedBox(width: 6),
            Text(msg['av'] as String, style: const TextStyle(fontSize: 16)),
          ],
        ],
      ),
    );
  }

  Widget _toolBtn(String label, {bool bold = false, bool italic = false}) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.transparent),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
      ),
    );
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _messages.add({'av': '👤', 'name': '', 'text': text, 'time': '$time ✓', 'out': true});
      _msgCtrl.clear();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
    // Авто-ответ
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final replies = ['Понял, спасибо!', 'Ок 👍', 'Проверю сейчас', 'Отлично!'];
      final avs  = ['👨', '👩', '🧑', '👩‍💼'];
      final nms  = ['Иван', 'Мария', 'Алексей', 'Анна'];
      final i = DateTime.now().millisecond % 4;
      final t2 = DateTime.now();
      final t2s = '${t2.hour}:${t2.minute.toString().padLeft(2, '0')}';
      setState(() {
        _messages.add({'av': avs[i], 'name': nms[i],
            'text': replies[i % replies.length], 'time': t2s, 'out': false});
      });
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }
}


// ════════════════════════════════════════════════════
// SHOP SCREEN
// ════════════════════════════════════════════════════
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _cat = 0;
  final _cats = ['Все', '⭐ Подписки', '🤖 AI', '📢 Реклама', '🔌 API'];

  final _items = [
    {'icon':'⭐','name':'Premium Pro',      'desc':'Полный доступ. AI анализ, без ограничений.','price':'€9.99/мес', 'badge':'Топ',    'featured':true,  'features':['Неограниченные сравнения','AI анализ отличий','Серверная обработка']},
    {'icon':'🤖','name':'AI Анализ',        'desc':'50 AI анализов в месяц на русском.',         'price':'€4.99/мес', 'badge':'Pro',    'featured':false, 'features':['50 анализов/мес','Русский язык']},
    {'icon':'📢','name':'Рекламное место',  'desc':'Баннер в магазине. До 10,000 показов/мес.', 'price':'€49/мес',   'badge':'Новинка','featured':false, 'features':['Баннер 30 дней','Аналитика']},
    {'icon':'🔌','name':'API Доступ',       'desc':'REST API. 10,000 запросов/мес.',             'price':'€19.99/мес','badge':'Dev',    'featured':false, 'features':['10,000 запросов','SDK Python/JS']},
    {'icon':'🎁','name':'Бесплатный план',  'desc':'Базовые функции. Уже активен.',              'price':'Бесплатно', 'badge':'Активен ✓','featured':false,'features':['10 сравнений/день','3 режима просмотра']},
    {'icon':'📦','name':'Пакет 100 сравн.', 'desc':'Разовая покупка. Не истекают.',              'price':'€2.99',     'badge':'Разово', 'featured':false, 'features':['100 сравнений','Все режимы']},
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '🛒', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(label: 'Мои покупки', icon: '🛍️',
              onTap: () => xpDlg(context, 'Мои покупки', 'Активный план: Бесплатный')),
          XpMenuItem(label: 'Восстановить покупки', icon: '🔄',
              onTap: () => xpDlg(context, 'Восстановить', 'Поиск активных подписок...')),
        ]),
        XpMenu(label: 'Вид', items: [
          ..._cats.asMap().entries.map((e) => XpMenuItem(
            label: e.value,
            onTap: () => setState(() => _cat = e.key),
          )),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(label: 'О магазине', icon: '❓',
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
      Expanded(child: GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => _card(_items[i]),
      )),

      XpStatusBar(left: '${_items.length} предложений · EUR', right: '👤 Бесплатный'),
    ]);
  }

  Widget _card(Map<String, dynamic> item) {
    final isFree = item['price'] == 'Бесплатно';
    return GestureDetector(
      onTap: isFree ? null : () => _buy(item['name'] as String, item['price'] as String),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (item['featured'] as bool)
              ? const Color(0xFFEEF3FF)
              : Colors.white,
          border: Border.all(
            color: (item['featured'] as bool) ? AppTheme.blue : AppTheme.silverDark,
            width: (item['featured'] as bool) ? 2 : 1,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['icon'] as String,
              style: TextStyle(fontSize: (item['featured'] as bool) ? 36 : 26)),
          const SizedBox(height: 4),
          Text(item['name'] as String,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(item['desc'] as String,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          ...((item['features'] as List).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Row(children: [
              const Text('✓ ', style: TextStyle(color: AppTheme.simHigh, fontSize: 10)),
              Expanded(child: Text(f, style: const TextStyle(fontSize: 10),
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
              XpBtn(label: 'Купить', primary: true,
                  onPressed: () => _buy(item['name'] as String, item['price'] as String))
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FFE8),
                  border: Border.all(color: AppTheme.simHigh),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(item['badge'] as String,
                    style: const TextStyle(fontSize: 9, color: AppTheme.simHigh,
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
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _quality   = 92;
  bool   _aiEnabled = false;
  bool   _history   = true;
  bool   _sync      = false;
  bool   _darkTheme = false;
  bool   _notify    = true;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '⚙️', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(label: 'Сохранить', icon: '💾', shortcut: 'Ctrl+S',
              onTap: () => xpDlg(context, 'Сохранено', 'Настройки применены')),
          XpMenuItem.sep,
          XpMenuItem(label: 'Сбросить до заводских', icon: '🔄',
              onTap: () async {
            final ok = await xpConfirm(context, 'Сбросить?',
                'Сбросить все настройки до заводских?');
            if (ok && mounted) {
              setState(() {
                _quality = 92; _aiEnabled = false;
                _history = true; _sync = false;
                _darkTheme = false; _notify = true;
              });
              xpDlg(context, 'Готово', 'Настройки сброшены');
            }
          }),
          XpMenuItem(label: 'Очистить кэш', icon: '🗑️',
              onTap: () => xpDlg(context, 'Кэш очищен', 'Освобождено: 48 МБ')),
        ]),
        XpMenu(label: 'Правка', items: [
          XpMenuItem(label: 'Экспорт настроек', icon: '📤',
              onTap: () => xpDlg(context, 'Экспорт', 'Настройки сохранены в config.json')),
          XpMenuItem(label: 'Импорт настроек', icon: '📂',
              onTap: () => xpDlg(context, 'Импорт', 'Выберите файл config.json')),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(label: 'Версия', icon: '📋',
              onTap: () => xpDlg(context, 'Версия',
                  'Photo Compare v1.0.0\nFlutter + SQLite + PostgreSQL\n© 2026 Photo Compare')),
          XpMenuItem(label: 'Поддержка', icon: '💬',
              onTap: () => xpDlg(context, 'Поддержка', 'support@photocompare.app')),
        ]),
      ]),

      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(children: [

          // Аккаунт
          XpGroup(label: 'Аккаунт', child: Column(children: [
            Row(children: [
              const Text('👤', style: TextStyle(fontSize: 36)),
              const SizedBox(width: 10),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('user@example.com',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  Text('Бесплатный план',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              )),
              XpBtn(label: '⭐ Premium', primary: true, onPressed: () {}),
            ]),
            const Divider(),
            Row(children: [
              Expanded(child: XpBtn(label: '🔑 Пароль',
                  onPressed: () => xpDlg(context, 'Пароль',
                      'Введите текущий и новый пароль'))),
              const SizedBox(width: 4),
              Expanded(child: XpBtn(label: '🔄 Синхр.',
                  onPressed: () => xpDlg(context, 'Синхронизация',
                      'Последняя синхронизация: только что'))),
              const SizedBox(width: 4),
              Expanded(child: XpBtn(label: '🚪 Выйти', danger: true,
                  onPressed: () async {
                final ok = await xpConfirm(context, 'Выйти?',
                    'Вы будете отключены от аккаунта.');
                if (ok) {}
              })),
            ]),
          ])),

          // Обработка
          XpGroup(label: 'Обработка изображений', child: Column(children: [
            Row(children: [
              const SizedBox(width: 130,
                  child: Text('Качество JPEG:', style: TextStyle(fontSize: 11))),
              Expanded(child: Slider(
                value: _quality, min: 50, max: 100,
                activeColor: AppTheme.blue,
                onChanged: (v) => setState(() => _quality = v),
              )),
              Text('${_quality.round()}%',
                  style: const TextStyle(fontSize: 11)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 130,
                  child: Text('Итераций:', style: TextStyle(fontSize: 11))),
              SizedBox(width: 60, child: XpInput(placeholder: '3')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 130,
                  child: Text('Макс. размер (px):', style: TextStyle(fontSize: 11))),
              SizedBox(width: 80, child: XpInput(placeholder: '2048')),
            ]),
          ])),

          // Функции
          XpGroup(label: 'Функции', child: Column(children: [
            _sw('AI анализ (требует Pro)', _aiEnabled,
                (v) => setState(() => _aiEnabled = v)),
            _sw('Сохранять историю', _history,
                (v) => setState(() => _history = v)),
            _sw('Синхронизация с сервером', _sync,
                (v) => setState(() => _sync = v)),
            _sw('Тёмная тема', _darkTheme,
                (v) => setState(() => _darkTheme = v)),
            _sw('Уведомления мессенджера', _notify,
                (v) => setState(() => _notify = v)),
          ])),

          // Язык
          XpGroup(label: 'Язык', child: Row(children: [
            XpBtn(label: '🇷🇺 Русский ✓', onPressed: () {}),
            const SizedBox(width: 6),
            XpBtn(label: '🇬🇧 English', onPressed: () {}),
            const SizedBox(width: 6),
            XpBtn(label: '🇨🇳 中文', onPressed: () {}),
          ])),

          const SizedBox(height: 12),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            XpBtn(label: 'Отмена', onPressed: () {}),
            const SizedBox(width: 6),
            XpBtn(label: 'Сохранить', primary: true,
                onPressed: () => xpDlg(context, 'Сохранено', 'Настройки применены')),
          ]),
        ]),
      )),

      XpStatusBar(left: 'Версия 1.0.0', right: '🔄 Синхронизировано'),
    ]);
  }

  Widget _sw(String label, bool val, ValueChanged<bool> onChange) {
    return Row(children: [
      Switch(value: val, onChanged: onChange,
          activeColor: AppTheme.blue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      Text(label, style: const TextStyle(fontSize: 11)),
    ]);
  }
}
