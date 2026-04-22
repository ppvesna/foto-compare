import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  String _chatTitle = 'Команда';
  String _chatStatus = '● 4 онлайн';
  int _activeChat = 0;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _contacts = [
    {
      'av': '👥',
      'name': 'Команда',
      'last': 'Иван: новые результаты',
      'type': 'g',
      'badge': 3
    },
    {
      'av': '📸',
      'name': 'Фотографы',
      'last': 'Отличная работа!',
      'type': 'g',
      'badge': 0
    },
    {
      'av': '👨',
      'name': 'Иван Петров',
      'last': 'Спасибо!',
      'type': 'u',
      'badge': 1
    },
    {
      'av': '👩',
      'name': 'Мария',
      'last': 'Когда будет готово?',
      'type': 'u',
      'badge': 0
    },
    {
      'av': '🧑',
      'name': 'Алексей',
      'last': 'Ок, понял',
      'type': 'u',
      'badge': 0
    },
  ];

  final _messages = <Map<String, dynamic>>[
    {
      'av': '👨',
      'name': 'Иван',
      'text': 'Посмотрите новые результаты 📊',
      'time': '10:24',
      'out': false
    },
    {
      'av': '👩',
      'name': 'Мария',
      'text': 'Схожесть 87.4% — отлично!',
      'time': '10:26',
      'out': false
    },
    {
      'av': '👤',
      'name': '',
      'text': 'Отчёт готов, загружу в историю',
      'time': '10:28 ✓✓',
      'out': true
    },
    {
      'av': '🧑',
      'name': 'Алексей',
      'text': 'Проверьте новый алгоритм итераций',
      'time': '10:31',
      'out': false
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: '💬', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
              label: 'Новое сообщение',
              icon: '✉️',
              onTap: () => xpDlg(
                  context, 'Новое сообщение', 'Выберите контакт или группу')),
          XpMenuItem(
              label: 'Создать группу',
              icon: '👥',
              onTap: () =>
                  xpDlg(context, 'Новая группа', 'Введите название группы')),
          XpMenuItem.sep,
          XpMenuItem(
              label: 'Экспорт истории',
              icon: '📤',
              onTap: () =>
                  xpDlg(context, 'Экспорт', 'История чата сохранена в TXT')),
        ]),
        XpMenu(label: 'Инструменты', items: [
          XpMenuItem(
              label: 'Поиск',
              icon: '🔍',
              shortcut: 'Ctrl+F',
              onTap: () => xpDlg(context, 'Поиск', 'Поиск по сообщениям')),
          XpMenuItem(
              label: 'Уведомления',
              icon: '🔔',
              onTap: () =>
                  xpDlg(context, 'Уведомления', 'Настройки уведомлений')),
        ]),
        XpMenu(label: 'Справка', items: [
          XpMenuItem(
              label: 'Горячие клавиши',
              icon: '⌨️',
              onTap: () => xpDlg(context, 'Горячие клавиши',
                  'Enter — отправить\nCtrl+N — новое сообщение')),
        ]),
      ]),
      Expanded(
          child: Row(children: [
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
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            // Поиск
            XpInput(placeholder: 'Поиск...', onChanged: (_) {}),
            // Список
            Expanded(
                child: ListView(children: [
              // Группы
              _sectionHeader('ГРУППЫ'),
              ..._contacts
                  .where((c) => c['type'] == 'g')
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => _contact(e.key, e.value)),
              // Личные
              _sectionHeader('ЛИЧНЫЕ'),
              ..._contacts
                  .where((c) => c['type'] == 'u')
                  .toList()
                  .asMap()
                  .entries
                  .map((e) => _contact(e.key + 2, e.value)),
            ])),
            // Кнопка добавить
            Padding(
              padding: const EdgeInsets.all(6),
              child: SizedBox(
                  width: double.infinity,
                  child: XpBtn(
                      label: '+ Добавить',
                      onPressed: () => xpDlg(context, 'Добавить контакт',
                          'Введите email пользователя'))),
            ),
          ]),
        ),

        // Основная область
        Expanded(
            child: Column(children: [
          // Шапка чата
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            color: AppTheme.silverDark,
            child: Row(children: [
              Text(_contacts[_activeChat]['av'] as String,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_chatTitle,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(_chatStatus,
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.simHigh)),
                  ])),
              XpBtn(
                  label: '👥',
                  onPressed: () => xpDlg(
                      context, 'Участники', 'Иван, Мария, Алексей, Анна')),
              const SizedBox(width: 4),
              XpBtn(
                  label: '📎',
                  onPressed: () =>
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
          Expanded(
              child: ListView.builder(
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
              Expanded(
                  child: Container(
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
                XpBtn(
                    label: '📎',
                    onPressed: () => xpDlg(context, 'Файл', 'Выберите файл')),
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
        child:
            Text(text, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      );

  Widget _contact(int idx, Map<String, dynamic> c) {
    final active = _activeChat == idx;
    final badge = c['badge'] as int;
    return GestureDetector(
      onTap: () => setState(() {
        _activeChat = idx;
        _chatTitle = c['name'] as String;
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
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['name'] as String,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: active ? Colors.white : Colors.black)),
              Text(c['last'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 9,
                      color: active ? const Color(0xFFCCEEFF) : Colors.grey)),
            ],
          )),
          if (badge > 0)
            Container(
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
          Flexible(
              child: Column(
            crossAxisAlignment:
                isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isOut && (msg['name'] as String).isNotEmpty)
                Text(msg['name'] as String,
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.blue)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      isOut ? const Color(0xFFE8FFE8) : const Color(0xFFF0F4FF),
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
        child: Text(label,
            style: TextStyle(
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
      _messages.add({
        'av': '👤',
        'name': '',
        'text': text,
        'time': '$time ✓',
        'out': true
      });
      _msgCtrl.clear();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
    // Авто-ответ
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final replies = [
        'Понял, спасибо!',
        'Ок 👍',
        'Проверю сейчас',
        'Отлично!'
      ];
      final avs = ['👨', '👩', '🧑', '👩‍💼'];
      final nms = ['Иван', 'Мария', 'Алексей', 'Анна'];
      final i = DateTime.now().millisecond % 4;
      final t2 = DateTime.now();
      final t2s = '${t2.hour}:${t2.minute.toString().padLeft(2, '0')}';
      setState(() {
        _messages.add({
          'av': avs[i],
          'name': nms[i],
          'text': replies[i % replies.length],
          'time': t2s,
          'out': false
        });
      });
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }
}

// ════════════════════════════════════════════════════
// SHOP SCREEN
// ════════════════════════════════════════════════════
