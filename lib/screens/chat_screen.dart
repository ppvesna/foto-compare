import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  int _activeRoom = 0;
  int _activeAsset = 0;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _rooms = const [
    _ChatRoom(
      icon: Icons.factory_outlined,
      name: 'TriMatrix / Печатный цех',
      subtitle: 'Организация · 8 участников',
      badge: 2,
      kind: 'org',
    ),
    _ChatRoom(
      icon: Icons.rule_folder_outlined,
      name: 'Проверки макетов',
      subtitle: 'Группа организации · результаты и замечания',
      badge: 4,
      kind: 'group',
    ),
    _ChatRoom(
      icon: Icons.color_lens_outlined,
      name: 'Цвет и геометрия',
      subtitle: 'Технологи · Delta E / ЧБ геометрия',
      badge: 0,
      kind: 'group',
    ),
    _ChatRoom(
      icon: Icons.person_outline,
      name: 'Олег',
      subtitle: 'личные сообщения',
      badge: 0,
      kind: 'direct',
    ),
  ];

  final _messages = <_ChatMessage>[
    _ChatMessage(
      author: 'Мария',
      role: 'технолог',
      time: '10:18',
      text:
          'Добавила замечание по белой краске. Нужен удалённый просмотр геометрии.',
      isMine: false,
    ),
    _ChatMessage(
      author: 'Олег',
      role: 'оператор',
      time: '10:24',
      text:
          'Отправил проверку в группу. Оригиналы пока локально, в облако уйдут только превью и карты.',
      isMine: true,
      checkCard: _SharedCheckCard(
        id: 'TRX-2026-0703-014',
        title: 'Проверка упаковки CMYK + белая краска',
        verdict: 'Геометрия требует проверки',
        score: 82.6,
        deltaE: 'max 7.4 · среднее 2.1',
        geometry: '91.8% · сдвиг 2.4 px',
        text: 'OCR 98.0%',
        storageMode: 'Гибрид: протокол + превью в облаке',
        assets: [
          _ChatAsset(
              'Образец', Icons.photo_outlined, 'remote_preview', 'доступно'),
          _ChatAsset(
              'ΔE карта', Icons.gradient_outlined, 'delta_map', 'доступно'),
          _ChatAsset('Геометрия ЧБ', Icons.line_axis_outlined, 'geometry_map',
              'доступно'),
          _ChatAsset('Оригинал эталона', Icons.lock_outline, 'reference',
              'запрос доступа'),
        ],
        comments: [
          _CheckComment(
              'Мария', 'Похоже, белый слой ушёл вниз на 2-3 px.', '10:27'),
          _CheckComment(
              'Иван', 'Цвет вторичен, смотрим контуры текста.', '10:31'),
        ],
      ),
    ),
    _ChatMessage(
      author: 'Иван',
      role: 'мастер смены',
      time: '10:36',
      text:
          'Открыл геометрию удалённо. Дайте доступ к оригиналу образца на 24 часа.',
      isMine: false,
    ),
  ];

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: 'CH', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
            label: 'Создать группу',
            icon: '+G',
            onTap: () => xpDlg(context, 'Новая группа',
                'Группа создаётся внутри организации.'),
          ),
          XpMenuItem(
            label: 'Поделиться проверкой',
            icon: 'SH',
            onTap: () => xpDlg(context, 'Поделиться проверкой',
                'Будет создана карточка результата и загружены выбранные превью.'),
          ),
          XpMenuItem.sep,
          XpMenuItem(
            label: 'Экспорт переписки',
            icon: 'EX',
            onTap: () => xpDlg(context, 'Экспорт', 'CSV / TXT / PDF позже'),
          ),
        ]),
        XpMenu(label: 'Управление', items: [
          XpMenuItem(
            label: 'Участники организации',
            icon: 'US',
            onTap: () => xpDlg(context, 'Участники',
                'Админ, технолог, оператор, наблюдатель.'),
          ),
          XpMenuItem(
            label: 'Доступ к картинкам',
            icon: 'LK',
            onTap: () => xpDlg(context, 'Доступ',
                'Локально / Гибрид / Облако. Оригиналы загружаются только по команде.'),
          ),
        ]),
      ]),
      Expanded(
        child: LayoutBuilder(builder: (_, constraints) {
          final compact = constraints.maxWidth < 980;
          if (compact) {
            return Column(children: [
              SizedBox(height: 154, child: _roomStrip()),
              Expanded(child: _messageColumn()),
              SizedBox(height: 260, child: _inspectorPanel()),
            ]);
          }
          return Row(children: [
            SizedBox(width: 250, child: _roomSidebar()),
            Expanded(child: _messageColumn()),
            SizedBox(width: 330, child: _inspectorPanel()),
          ]);
        }),
      ),
      XpStatusBar(
        left: _rooms[_activeRoom].name,
        right: 'Организация · удалённый просмотр по разрешению',
      ),
    ]);
  }

  Widget _roomSidebar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFE7E8E4),
        border: Border(right: BorderSide(color: AppTheme.silverDark)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _orgHeader(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: XpInput(placeholder: 'Поиск по чатам и проверкам...'),
        ),
        _sectionHeader('ОРГАНИЗАЦИЯ'),
        Expanded(
          child: ListView.builder(
            itemCount: _rooms.length,
            itemBuilder: (_, i) => _roomTile(i, _rooms[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: XpBtn(
            label: '+ Группа',
            onPressed: () => xpDlg(context, 'Группа',
                'Название, участники, права доступа к проверкам.'),
          ),
        ),
      ]),
    );
  }

  Widget _roomStrip() {
    return Container(
      color: const Color(0xFFE7E8E4),
      child: Column(children: [
        _orgHeader(),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: _rooms.length,
            itemBuilder: (_, i) =>
                SizedBox(width: 210, child: _roomTile(i, _rooms[i])),
          ),
        ),
      ]),
    );
  }

  Widget _orgHeader() {
    return Container(
      padding: const EdgeInsets.all(10),
      color: AppTheme.blueDark,
      child:
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'TriMatrix',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 2),
        Text(
          'Печатная организация · группы и проверки',
          style: TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ]),
    );
  }

  Widget _sectionHeader(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: const Color(0xFFD7DAD2),
        child: Text(text,
            style: const TextStyle(fontSize: 9, color: Colors.black54)),
      );

  Widget _roomTile(int index, _ChatRoom room) {
    final active = _activeRoom == index;
    return InkWell(
      onTap: () => setState(() => _activeRoom = index),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFF4F5F1),
          border: Border.all(color: active ? AppTheme.blue : AppTheme.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: active ? AppTheme.shadowSubtle : null,
        ),
        child: Row(children: [
          Icon(room.icon,
              size: 19, color: active ? AppTheme.blue : Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(room.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(room.subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ]),
          ),
          if (room.badge > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.blue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text('${room.badge}',
                  style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
        ]),
      ),
    );
  }

  Widget _messageColumn() {
    final room = _rooms[_activeRoom];
    return Container(
      color: const Color(0xFFF3F4F6),
      child: Column(children: [
        _chatHeader(room),
        _sharePolicyBar(),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _messageBubble(_messages[i]),
          ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _chatHeader(_ChatRoom room) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        Icon(room.icon, size: 22, color: AppTheme.blue),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(room.name,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text(room.subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ),
        XpBtn(
          label: 'Участники',
          onPressed: () => xpDlg(context, 'Участники группы',
              'Админ: Олег\nТехнолог: Мария\nОператор: Иван\nНаблюдатель: Алексей'),
        ),
        const SizedBox(width: 6),
        XpBtn(
          label: 'Поделиться',
          primary: true,
          onPressed: () => xpDlg(context, 'Поделиться проверкой',
              'Выберите: протокол, превью, ΔE, геометрию, оригиналы.'),
        ),
      ]),
    );
  }

  Widget _sharePolicyBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: const Color(0xFFEAF3FF),
      child: Row(children: const [
        Icon(Icons.privacy_tip_outlined, size: 15, color: AppTheme.blue),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Картинки остаются локально. В чат загружаются только выбранные превью или карты; оригиналы требуют отдельного доступа.',
            style: TextStyle(fontSize: 10, color: Colors.black87),
          ),
        ),
      ]),
    );
  }

  Widget _messageBubble(_ChatMessage message) {
    final align = message.isMine ? Alignment.centerRight : Alignment.centerLeft;
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: message.isMine ? const Color(0xFFE8FFE8) : Colors.white,
            border: Border.all(
              color: message.isMine ? const Color(0xFFB8DDB8) : AppTheme.border,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: AppTheme.shadowSubtle,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor:
                    message.isMine ? AppTheme.simHigh : AppTheme.blue,
                child: Text(
                  message.author.characters.first,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${message.author} · ${message.role}',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              Text(message.time,
                  style: const TextStyle(fontSize: 9, color: Colors.grey)),
            ]),
            const SizedBox(height: 7),
            Text(message.text,
                style: const TextStyle(fontSize: 11, height: 1.4)),
            if (message.checkCard != null) ...[
              const SizedBox(height: 10),
              _checkCard(message.checkCard!),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _checkCard(_SharedCheckCard card) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD8E1EA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 86,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [Color(0xFFECEFF4), Color(0xFFC9D7E8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Color(0xFFB8C5D6)),
              ),
              child:
                  const Icon(Icons.image_search_outlined, color: AppTheme.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.id,
                        style:
                            const TextStyle(fontSize: 9, color: Colors.grey)),
                    Text(card.title,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, runSpacing: 5, children: [
                      _metric('Итог', '${card.score.toStringAsFixed(1)}%'),
                      _metric('ΔE', card.deltaE),
                      _metric('Геометрия', card.geometry),
                      _metric('Текст', card.text),
                    ]),
                  ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _statusPill(card.verdict),
              const SizedBox(height: 8),
              XpBtn(
                label: 'Открыть',
                primary: true,
                onPressed: () => setState(() => _activeAsset = 0),
              ),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFD8E1EA))),
          ),
          child: Text(
            card.storageMode,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ),
      ]),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 9)),
    );
  }

  Widget _statusPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        border: Border.all(color: const Color(0xFFE8A000)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        XpBtn(
          label: 'Проверка',
          onPressed: () => xpDlg(context, 'Прикрепить проверку',
              'Берём последний локальный протокол, создаём карточку и выбираем изображения для облака.'),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Комментарий для группы организации...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 6),
        XpBtn(label: 'Отправить', primary: true, onPressed: _send),
      ]),
    );
  }

  Widget _inspectorPanel() {
    final card = _messages.firstWhere((m) => m.checkCard != null).checkCard!;
    final asset = card.assets[_activeAsset.clamp(0, card.assets.length - 1)];
    return Container(
      color: const Color(0xFFE7E8E4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: AppTheme.blueDark,
          child: const Text(
            'Просмотр проверки',
            style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _remotePreview(asset),
                  const SizedBox(height: 10),
                  _assetTabs(card),
                  const SizedBox(height: 10),
                  XpGroup(
                    label: 'Комментарии к проверке',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...card.comments.map(_commentTile),
                        const SizedBox(height: 8),
                        XpBtn(
                          label: '+ Комментарий',
                          onPressed: () => xpDlg(context, 'Комментарий',
                              'Комментарий будет привязан к check_result_id и asset kind.'),
                        ),
                      ],
                    ),
                  ),
                  XpGroup(
                    label: 'Архитектура',
                    child: const Text(
                      'chat_messages.type = check_result\n'
                      'chat_messages.check_result_id -> check_results.id\n'
                      'check_assets.kind = reference/sample/delta_map/geometry_map/preview\n'
                      'check_assets.storage_path -> Supabase Storage signed URL\n'
                      'comments привязаны к организации, группе и проверке.',
                      style: TextStyle(fontSize: 10, height: 1.45),
                    ),
                  ),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _remotePreview(_ChatAsset asset) {
    final locked = asset.status.contains('запрос');
    return Container(
      height: 210,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: AppTheme.silverDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                colors: locked
                    ? const [Color(0xFF2C3440), Color(0xFF111827)]
                    : const [Color(0xFFEBF1F7), Color(0xFFB8CADF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Icon(
              locked ? Icons.lock_outline : asset.icon,
              size: 54,
              color: locked ? Colors.white38 : AppTheme.blue,
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xDD000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${asset.name} · ${asset.status}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _assetTabs(_SharedCheckCard card) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: card.assets.asMap().entries.map((entry) {
        final i = entry.key;
        final asset = entry.value;
        final selected = i == _activeAsset;
        return InkWell(
          onTap: () => setState(() => _activeAsset = i),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppTheme.blue : Colors.white,
              border: Border.all(
                  color: selected ? AppTheme.blueDark : AppTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(asset.icon,
                  size: 14, color: selected ? Colors.white : AppTheme.blue),
              const SizedBox(width: 5),
              Text(
                asset.name,
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _commentTile(_CheckComment c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c.author} · ${c.time}',
            style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 3),
        Text(c.text, style: const TextStyle(fontSize: 10, height: 1.35)),
      ]),
    );
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _messages.add(
        _ChatMessage(
          author: 'Олег',
          role: 'оператор',
          time: '$time ✓',
          text: text,
          isMine: true,
        ),
      );
      _msgCtrl.clear();
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}

class _ChatRoom {
  final IconData icon;
  final String name;
  final String subtitle;
  final int badge;
  final String kind;

  const _ChatRoom({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.kind,
  });
}

class _ChatMessage {
  final String author;
  final String role;
  final String time;
  final String text;
  final bool isMine;
  final _SharedCheckCard? checkCard;

  const _ChatMessage({
    required this.author,
    required this.role,
    required this.time,
    required this.text,
    required this.isMine,
    this.checkCard,
  });
}

class _SharedCheckCard {
  final String id;
  final String title;
  final String verdict;
  final double score;
  final String deltaE;
  final String geometry;
  final String text;
  final String storageMode;
  final List<_ChatAsset> assets;
  final List<_CheckComment> comments;

  const _SharedCheckCard({
    required this.id,
    required this.title,
    required this.verdict,
    required this.score,
    required this.deltaE,
    required this.geometry,
    required this.text,
    required this.storageMode,
    required this.assets,
    required this.comments,
  });
}

class _ChatAsset {
  final String name;
  final IconData icon;
  final String kind;
  final String status;

  const _ChatAsset(this.name, this.icon, this.kind, this.status);
}

class _CheckComment {
  final String author;
  final String text;
  final String time;

  const _CheckComment(this.author, this.text, this.time);
}
