import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../features/protocols/protocols.dart';
import '../widgets/xp_widgets.dart';

enum _ChatKind { internal, approval }

class ChatScreen extends StatefulWidget {
  final String email;
  final String displayName;
  final String nickname;
  final String organizationName;
  final ProtocolCloudRepository? protocolCloudRepository;

  const ChatScreen({
    super.key,
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.organizationName,
    this.protocolCloudRepository,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  int _activeChat = 0;
  String _approvalStatus = 'Ожидает согласования';
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<CloudProtocolRecord> _cloudProtocols = const [];
  CloudProtocolRecord? _selectedCloudProtocol;
  Uint8List? _selectedCloudPreview;
  bool _cloudProtocolsLoading = false;
  String? _cloudProtocolsError;

  String get _userName {
    if (widget.displayName.trim().isNotEmpty) return widget.displayName.trim();
    if (widget.nickname.trim().isNotEmpty) return widget.nickname.trim();
    if (widget.email.trim().isNotEmpty) return widget.email.split('@').first;
    return 'Олег';
  }

  String get _userNick =>
      widget.nickname.trim().isEmpty ? 'ник не задан' : widget.nickname.trim();

  String get _organizationName => widget.organizationName.trim().isEmpty
      ? 'TriMatrix'
      : widget.organizationName.trim();

  final _chats = const [
    _ChatItem(
      title: 'Согласование макета #154',
      subtitle: 'ООО Ромашка · упаковка 120x80 · v3',
      time: '11:08',
      unread: 2,
      color: Color(0xFF0EA5A4),
      kind: _ChatKind.approval,
    ),
    _ChatItem(
      title: 'Проверки макетов',
      subtitle: 'карты отличий, протоколы, замечания',
      time: '10:36',
      unread: 3,
      color: Color(0xFF2FA7E6),
    ),
    _ChatItem(
      title: 'Цвет и геометрия',
      subtitle: 'Delta E, ЧБ-контуры, смещения',
      time: '09:54',
      unread: 0,
      color: Color(0xFF16A34A),
    ),
    _ChatItem(
      title: 'Цех / смена',
      subtitle: 'мастер, печатник, технолог',
      time: 'Вчера',
      unread: 1,
      color: Color(0xFFF59E0B),
    ),
    _ChatItem(
      title: 'Олег',
      subtitle: 'личный чат',
      time: 'Пт',
      unread: 0,
      color: Color(0xFF64748B),
    ),
  ];

  final _approvalMessages = <_ChatMessage>[
    const _ChatMessage(
      author: 'Анна',
      role: 'заказчик',
      time: '10:52',
      text:
          'Посмотрели версию v3. По цвету упаковка подходит, надо только подтвердить читаемость мелкого текста.',
      isMine: false,
    ),
    const _ChatMessage(
      author: 'Олег',
      role: 'менеджер',
      time: '10:57',
      text:
          'Прикрепил макет, протокол проверки и превью. Оригиналы производства заказчику не показываем, только согласовательные файлы.',
      isMine: true,
      approvalCard: _ApprovalCard(
        orderId: 'ORD-154',
        customer: 'ООО Ромашка',
        layoutName: 'Упаковка 120x80',
        version: 'v3',
        fileName: 'romashka_pack_v3.pdf',
        status: 'Ожидает согласования',
        deadline: '05.07.2026 18:00',
        protocol: 'Проверка OK · Delta E max 3.2 · OCR 99%',
      ),
    ),
    const _ChatMessage(
      author: 'Анна',
      role: 'заказчик',
      time: '11:08',
      text:
          'Хорошо. Оставляю комментарий: проверьте, пожалуйста, срок годности в нижнем правом углу.',
      isMine: false,
    ),
  ];

  final _messages = <_ChatMessage>[
    const _ChatMessage(
      author: 'Мария',
      role: 'технолог',
      time: '10:18',
      text:
          'Посмотрела белую краску. Цвет можно принять, но геометрию текста надо проверить отдельно.',
      isMine: false,
    ),
    const _ChatMessage(
      author: 'Олег',
      role: 'оператор',
      time: '10:24',
      text: 'Отправил последнюю проверку в группу.',
      isMine: true,
      card: _SharedCheckCard(
        id: 'TRX-2026-0703-014',
        title: 'Упаковка CMYK + белая краска',
        verdict: 'Геометрия требует проверки',
        score: 82.6,
        deltaE: 'max 7.4 / avg 2.1',
        geometry: '91.8%, сдвиг 2.4 px',
        text: 'OCR 98%',
        storage: 'Гибрид: протокол и превью в облаке, оригиналы локально',
      ),
    ),
    const _ChatMessage(
      author: 'Иван',
      role: 'мастер смены',
      time: '10:36',
      text:
          'Открыл карту удаленно. Нужен доступ к оригиналу образца на 24 часа.',
      isMine: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCloudProtocols();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protocolCloudRepository != widget.protocolCloudRepository) {
      _loadCloudProtocols();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCloudProtocols() async {
    final repository = widget.protocolCloudRepository;
    if (repository == null || _cloudProtocolsLoading) return;
    setState(() {
      _cloudProtocolsLoading = true;
      _cloudProtocolsError = null;
    });
    try {
      final records = await repository.listAccessibleProtocols(limit: 20);
      if (!mounted) return;
      setState(() {
        _cloudProtocols = records;
        _selectedCloudProtocol = records.isEmpty ? null : records.first;
        _selectedCloudPreview = null;
      });
      if (records.isNotEmpty) {
        await _loadCloudPreview(records.first);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cloudProtocols = const [];
        _selectedCloudProtocol = null;
        _selectedCloudPreview = null;
        _cloudProtocolsError =
            'Облачные протоколы пока недоступны. Проверьте миграцию 015.';
      });
    } finally {
      if (mounted) setState(() => _cloudProtocolsLoading = false);
    }
  }

  Future<void> _loadCloudPreview(CloudProtocolRecord record) async {
    final repository = widget.protocolCloudRepository;
    if (repository == null) return;
    setState(() {
      _selectedCloudProtocol = record;
      _selectedCloudPreview = null;
    });
    try {
      final preview = await repository.loadPreview(record);
      if (!mounted || _selectedCloudProtocol != record) return;
      setState(() => _selectedCloudPreview = preview);
    } catch (_) {
      if (!mounted || _selectedCloudProtocol != record) return;
      setState(() => _selectedCloudPreview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      XpMenuBar(icon: 'CH', menus: [
        XpMenu(label: 'Файл', items: [
          XpMenuItem(
            label: 'Новая группа',
            icon: '+G',
            onTap: () => xpDlg(
              context,
              'Новая группа',
              'Группа будет привязана к организации и проверкам.',
            ),
          ),
          XpMenuItem(
            label: 'Поделиться проверкой',
            icon: 'SH',
            onTap: () => xpDlg(
              context,
              'Поделиться проверкой',
              'В чат попадет карточка результата, протокол и выбранные превью.',
            ),
          ),
        ]),
        XpMenu(label: 'Доступ', items: [
          XpMenuItem(
            label: 'Участники',
            icon: 'US',
            onTap: () => xpDlg(
              context,
              'Участники',
              '$_userName ($_userNick), Мария, Иван. Роли и права позже будут браться из Supabase.',
            ),
          ),
          XpMenuItem(
            label: 'Картинки',
            icon: 'IM',
            onTap: () => xpDlg(
              context,
              'Доступ к картинкам',
              'Оригиналы остаются на устройстве, а в чат можно отправлять превью, карты и временные ссылки.',
            ),
          ),
        ]),
      ]),
      Expanded(
        child: LayoutBuilder(builder: (_, constraints) {
          final compact = constraints.maxWidth < 920;
          if (compact) {
            return Column(children: [
              SizedBox(height: 122, child: _chatStrip()),
              Expanded(child: _chatPane()),
              SizedBox(height: 232, child: _techPanel()),
            ]);
          }
          return Row(children: [
            SizedBox(width: 276, child: _chatList()),
            Expanded(child: _chatPane()),
            SizedBox(width: 330, child: _techPanel()),
          ]);
        }),
      ),
      XpStatusBar(
        left: _chatTitle(_chats[_activeChat]),
        right: 'Чат организации · картинки по разрешению',
      ),
    ]);
  }

  String _chatTitle(_ChatItem chat) {
    return chat.title == 'Олег' ? _userName : chat.title;
  }

  String _chatSubtitle(_ChatItem chat) {
    if (chat.title != 'Олег') return chat.subtitle;
    final email =
        widget.email.trim().isEmpty ? 'email не указан' : widget.email;
    return '$email · $_userNick';
  }

  Widget _chatList() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFEAF6FC),
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _listHeader(),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: XpInput(placeholder: 'Поиск'),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: _chats.length,
            itemBuilder: (_, i) => _chatTile(i),
          ),
        ),
      ]),
    );
  }

  Widget _chatStrip() {
    return Container(
      color: const Color(0xFFEAF6FC),
      child: Column(children: [
        _listHeader(compact: true),
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: _chats.length,
            itemBuilder: (_, i) => SizedBox(width: 218, child: _chatTile(i)),
          ),
        ),
      ]),
    );
  }

  Widget _listHeader({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 8),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFBDEBFF), AppTheme.blue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(17),
            boxShadow: AppTheme.shadowSubtle,
          ),
          child: const Center(
            child: Text(
              'TM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'TriMatrix',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            Text(
              _organizationName == 'TriMatrix'
                  ? 'организация и группы'
                  : _organizationName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
        XpBtn(
          label: '+',
          width: 46,
          onPressed: () => xpDlg(
            context,
            'Новый чат',
            'Здесь появится создание группы, личного чата или обсуждения проверки.',
          ),
        ),
      ]),
    );
  }

  Widget _chatTile(int index) {
    final chat = _chats[index];
    final active = index == _activeChat;
    final title = _chatTitle(chat);
    final subtitle = _chatSubtitle(chat);
    return InkWell(
      onTap: () => setState(() => _activeChat = index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: active ? Colors.white : const Color(0xFFF7FCFF),
          border: Border.all(
            color: active ? AppTheme.blue : const Color(0xFFD6EAF5),
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: active ? AppTheme.shadowSubtle : null,
        ),
        child: Row(children: [
          _avatar(title, chat.color, size: 40),
          const SizedBox(width: 9),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  chat.time,
                  style: const TextStyle(fontSize: 9, color: Colors.black45),
                ),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(
                  child: Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ),
                if (chat.unread > 0) _unread(chat.unread),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chatPane() {
    final chat = _chats[_activeChat];
    final messages = _visibleMessages;
    return Container(
      color: const Color(0xFFF4FAFD),
      child: Column(children: [
        _chatHeader(chat),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            itemCount: messages.length,
            itemBuilder: (_, i) => _messageBubble(messages[i]),
          ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _chatHeader(_ChatItem chat) {
    final title = _chatTitle(chat);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        _avatar(title, chat.color, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
            Text(
              chat.kind == _ChatKind.approval
                  ? 'заказчик · согласование версии · доступ ограничен'
                  : '3 участника · удаленный просмотр включен',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
        XpBtn(
          label: 'Доступ',
          onPressed: () => xpDlg(
            context,
            'Доступ',
            chat.kind == _ChatKind.approval
                ? 'Заказчик видит только свой заказ, макет, превью, комментарии и решение по согласованию.'
                : 'Участники видят протокол, превью и карты. Оригиналы открываются отдельным разрешением.',
          ),
        ),
      ]),
    );
  }

  Widget _messageBubble(_ChatMessage message) {
    final align = message.isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = message.isMine ? const Color(0xFFDFF7D9) : Colors.white;
    final border = message.isMine ? const Color(0xFFA7D79D) : AppTheme.border;
    final author = message.isMine ? _userName : message.author;
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppTheme.shadowSubtle,
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _avatar(author, message.isMine ? AppTheme.simHigh : AppTheme.blue,
                  size: 26),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$author · ${message.role}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
              Text(
                message.time,
                style: const TextStyle(fontSize: 9, color: Colors.black45),
              ),
            ]),
            const SizedBox(height: 7),
            Text(
              message.text,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
            if (message.card != null) ...[
              const SizedBox(height: 9),
              _checkCard(message.card!),
            ],
            if (message.approvalCard != null) ...[
              const SizedBox(height: 9),
              _approvalCard(message.approvalCard!),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _checkCard(_SharedCheckCard card) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFF),
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 86,
              height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEAF7FD), Color(0xFFB8DFF3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFF9ECDE4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.image_search_outlined,
                  color: AppTheme.blue, size: 30),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.id,
                    style: const TextStyle(fontSize: 9, color: Colors.black45),
                  ),
                  Text(
                    card.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    _metric('Итог', '${card.score.toStringAsFixed(1)}%'),
                    _metric('Delta E', card.deltaE),
                    _metric('Геометрия', card.geometry),
                    _metric('Текст', card.text),
                  ]),
                ],
              ),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFC9E2F0))),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                card.verdict,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF8A4B00),
                ),
              ),
            ),
            XpBtn(
              label: 'Открыть',
              primary: true,
              onPressed: () => xpDlg(
                context,
                card.id,
                'Открываем протокол, карту Delta E и ЧБ-геометрию.',
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _approvalCard(_ApprovalCard card) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFF),
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 86,
              height: 62,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEAF7FD), Color(0xFFD8F4EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: const Color(0xFF9ECDE4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.fact_check_outlined,
                  color: AppTheme.blue, size: 30),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${card.orderId} · ${card.customer}',
                    style: const TextStyle(fontSize: 9, color: Colors.black45),
                  ),
                  Text(
                    '${card.layoutName} · ${card.version}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    _metric('Файл', card.fileName),
                    _metric('Статус', _approvalStatus),
                    _metric('Протокол', card.protocol),
                  ]),
                ],
              ),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFC9E2F0))),
          ),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            XpBtn(
              label: 'Принять',
              primary: true,
              onPressed: () => _setApprovalStatus('Согласовано заказчиком'),
            ),
            XpBtn(
              label: 'На доработку',
              onPressed: () => _setApprovalStatus('Нужна доработка'),
            ),
            XpBtn(
              label: 'Новая версия',
              onPressed: () => _setApprovalStatus('Ожидается новая версия'),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _composer() {
    final isApproval = _chats[_activeChat].kind == _ChatKind.approval;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        XpBtn(
          label: '+',
          width: 48,
          onPressed: () => xpDlg(
            context,
            'Прикрепить',
            isApproval
                ? 'К согласованию можно прикрепить PDF/JPG макета, новую версию, протокол проверки или превью.'
                : 'Можно будет прикрепить последнюю проверку, превью, карту отличий или оригинал по разрешению.',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _msgCtrl,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: isApproval
                  ? 'Комментарий по согласованию макета'
                  : 'Сообщение',
              filled: true,
              fillColor: const Color(0xFFF4FAFD),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: AppTheme.blue),
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        XpBtn(label: 'Отправить', primary: true, onPressed: _send),
      ]),
    );
  }

  Widget _techPanel() {
    if (_chats[_activeChat].kind == _ChatKind.approval) {
      return _approvalPanel();
    }
    final cloudRecord = _selectedCloudProtocol;
    final card = cloudRecord == null
        ? _messages.firstWhere((m) => m.card != null).card!
        : _cloudCheckCard(cloudRecord.protocol);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFEAF6FC),
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: AppTheme.blueDark,
          child: const Text(
            'Технические данные',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cloudProtocolSelector(),
                  const SizedBox(height: 10),
                  _previewBox(_selectedCloudPreview),
                  const SizedBox(height: 10),
                  _techRows(card),
                  const SizedBox(height: 10),
                  _commentsBox(),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: XpBtn(
                        label: 'Карта',
                        primary: _selectedCloudPreview != null,
                        onPressed: _selectedCloudPreview == null
                            ? null
                            : _showCloudPreview,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: XpBtn(
                        label: 'Оригинал',
                        onPressed: () => xpDlg(
                          context,
                          'Оригинал',
                          'Запрос доступа к локальному оригиналу у владельца проверки.',
                        ),
                      ),
                    ),
                  ]),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _cloudProtocolSelector() {
    if (_cloudProtocolsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Загружаю доступные протоколы...',
          style: TextStyle(fontSize: 10, color: Colors.black54),
        ),
      );
    }
    if (_cloudProtocolsError != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          _cloudProtocolsError!,
          style: const TextStyle(fontSize: 10, color: Color(0xFF9A3412)),
        ),
        const SizedBox(height: 7),
        XpBtn(label: 'Повторить', onPressed: _loadCloudProtocols),
      ]);
    }
    if (_cloudProtocols.isEmpty) {
      return Row(children: [
        const Expanded(
          child: Text(
            'Доступных облачных протоколов пока нет.',
            style: TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ),
        XpBtn(label: 'Обновить', onPressed: _loadCloudProtocols),
      ]);
    }
    return Row(children: [
      Expanded(
        child: DropdownButtonFormField<CloudProtocolRecord>(
          key: ValueKey(
            'cloud-protocol-${_selectedCloudProtocol?.ownerUserId}-'
            '${_selectedCloudProtocol?.protocol.id}-${_cloudProtocols.length}',
          ),
          initialValue: _selectedCloudProtocol,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Доступная проверка',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _cloudProtocols
              .map(
                (record) => DropdownMenuItem(
                  value: record,
                  child: Text(
                    _cloudProtocolLabel(record.protocol),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (record) {
            if (record != null) _loadCloudPreview(record);
          },
        ),
      ),
      const SizedBox(width: 7),
      IconButton(
        tooltip: 'Обновить протоколы',
        onPressed: _loadCloudProtocols,
        icon: const Icon(Icons.refresh),
        color: AppTheme.blue,
      ),
    ]);
  }

  String _cloudProtocolLabel(CheckProtocol protocol) {
    final job = protocol.jobNumber.trim().isEmpty
        ? 'личная работа'
        : '№ ${protocol.jobNumber}';
    return '$job · ${protocol.sampleLabel} · ${protocol.score.toStringAsFixed(1)}%';
  }

  _SharedCheckCard _cloudCheckCard(CheckProtocol protocol) {
    String metricFor(String fragment, String fallback) {
      for (final stage in protocol.stages) {
        if (stage.name.toLowerCase().contains(fragment)) return stage.metric;
      }
      return fallback;
    }

    return _SharedCheckCard(
      id: protocol.id,
      title: _cloudProtocolLabel(protocol),
      verdict: protocol.verdict,
      score: protocol.score,
      deltaE: metricFor('цветовая карта', protocol.deltaEFormula),
      geometry: metricFor('геометрия', 'нет данных'),
      text: metricFor('ocr', 'нет данных'),
      storage: 'Протокол и превью в облаке · оригиналы локально',
    );
  }

  void _showCloudPreview() {
    final preview = _selectedCloudPreview;
    final record = _selectedCloudProtocol;
    if (preview == null || record == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _cloudProtocolLabel(record.protocol),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 8,
                child: Image.memory(preview, fit: BoxFit.contain),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _approvalPanel() {
    const card = _ApprovalCard(
      orderId: 'ORD-154',
      customer: 'ООО Ромашка',
      layoutName: 'Упаковка 120x80',
      version: 'v3',
      fileName: 'romashka_pack_v3.pdf',
      status: 'Ожидает согласования',
      deadline: '05.07.2026 18:00',
      protocol: 'Проверка OK · Delta E max 3.2 · OCR 99%',
    );
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFEAF6FC),
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: AppTheme.blueDark,
          child: const Text(
            'Согласование макета',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cloudProtocolSelector(),
                  const SizedBox(height: 10),
                  if (_selectedCloudPreview != null)
                    _previewBox(_selectedCloudPreview)
                  else
                    _layoutPreviewBox(),
                  const SizedBox(height: 10),
                  _approvalRows(card),
                  const SizedBox(height: 10),
                  _approvalActions(),
                  const SizedBox(height: 10),
                  _versionBox(),
                  const SizedBox(height: 10),
                  _customerAccessBox(),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _layoutPreviewBox() {
    return Container(
      height: 172,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFBEB), Color(0xFFDDF7FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const Center(
          child: Icon(Icons.picture_as_pdf_outlined,
              size: 50, color: AppTheme.blue),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xDDFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Макет v3 · заказчик видит только согласовательный файл',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _approvalRows(_ApprovalCard card) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        _techRow('Заказ', card.orderId),
        _techRow('Заказчик', card.customer),
        _techRow('Макет', '${card.layoutName} · ${card.version}'),
        _techRow('Файл', card.fileName),
        _techRow('Статус', _approvalStatus),
        _techRow('Дедлайн', card.deadline),
        _techRow('Проверка', card.protocol),
      ]),
    );
  }

  Widget _approvalActions() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
          'Решение заказчика',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        XpBtn(
          label: 'Принять макет',
          primary: true,
          onPressed: () => _setApprovalStatus('Согласовано заказчиком'),
        ),
        const SizedBox(height: 7),
        XpBtn(
          label: 'Вернуть на доработку',
          onPressed: () => _setApprovalStatus('Нужна доработка'),
        ),
        const SizedBox(height: 7),
        XpBtn(
          label: 'Запросить новую версию',
          onPressed: () => _setApprovalStatus('Ожидается новая версия'),
        ),
      ]),
    );
  }

  Widget _versionBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('История версий',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          SizedBox(height: 7),
          Text('v1 · первичный макет · замечания по тексту',
              style: TextStyle(fontSize: 10, height: 1.35)),
          SizedBox(height: 4),
          Text('v2 · исправлены тексты · замечания по цвету',
              style: TextStyle(fontSize: 10, height: 1.35)),
          SizedBox(height: 4),
          Text('v3 · текущая версия · ожидает решения',
              style: TextStyle(fontSize: 10, height: 1.35)),
        ],
      ),
    );
  }

  Widget _customerAccessBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE6),
        border: Border.all(color: const Color(0xFFE8C65C)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'Доступ заказчика: только свой заказ, макет, комментарии, статус и согласовательный протокол. Производственные настройки, оригиналы и внутренние карты не показываются.',
        style: TextStyle(fontSize: 10, height: 1.35),
      ),
    );
  }

  Widget _previewBox(Uint8List? preview) {
    if (preview != null) {
      return Container(
        height: 172,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: const Color(0xFFC9E2F0)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppTheme.shadowSubtle,
        ),
        child: Image.memory(preview, fit: BoxFit.contain),
      );
    }
    return Container(
      height: 172,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE9F8FF), Color(0xFFFFF7D6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const Center(
          child:
              Icon(Icons.difference_outlined, size: 48, color: AppTheme.blue),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xDDFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Превью проверки · карта и протокол доступны',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _techRows(_SharedCheckCard card) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        _techRow('ID', card.id),
        _techRow('Статус', card.verdict),
        _techRow('Итог', '${card.score.toStringAsFixed(1)}%'),
        _techRow('Delta E', card.deltaE),
        _techRow('Геометрия', card.geometry),
        _techRow('Текст', card.text),
        _techRow('Хранение', card.storage),
      ]),
    );
  }

  Widget _commentsBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Комментарии',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 7),
          Text(
            'Мария: белый слой ушел вниз на 2-3 px.',
            style: TextStyle(fontSize: 10, height: 1.35),
          ),
          SizedBox(height: 5),
          Text(
            'Иван: цвет вторичен, смотрим контуры текста.',
            style: TextStyle(fontSize: 10, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 9)),
    );
  }

  Widget _techRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _avatar(String name, Color color, {required double size}) {
    final letter = name.trim().isEmpty ? '?' : name.trim().substring(0, 1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: AppTheme.shadowSubtle,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _unread(int count) {
    return Container(
      height: 19,
      constraints: const BoxConstraints(minWidth: 19),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppTheme.blue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  List<_ChatMessage> get _visibleMessages {
    return _chats[_activeChat].kind == _ChatKind.approval
        ? _approvalMessages
        : _messages;
  }

  void _setApprovalStatus(String status) {
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')} ✓';
    setState(() {
      _approvalStatus = status;
      _approvalMessages.add(
        _ChatMessage(
          author: _userName,
          role: 'менеджер',
          time: time,
          text: 'Статус согласования изменен: $status.',
          isMine: true,
        ),
      );
    });
  }

  void _send() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final time = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _visibleMessages.add(
        _ChatMessage(
          author: _userName,
          role: _chats[_activeChat].kind == _ChatKind.approval
              ? 'менеджер'
              : 'оператор',
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

class _ChatItem {
  final String title;
  final String subtitle;
  final String time;
  final int unread;
  final Color color;
  final _ChatKind kind;

  const _ChatItem({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.unread,
    required this.color,
    this.kind = _ChatKind.internal,
  });
}

class _ChatMessage {
  final String author;
  final String role;
  final String time;
  final String text;
  final bool isMine;
  final _SharedCheckCard? card;
  final _ApprovalCard? approvalCard;

  const _ChatMessage({
    required this.author,
    required this.role,
    required this.time,
    required this.text,
    required this.isMine,
    this.card,
    this.approvalCard,
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
  final String storage;

  const _SharedCheckCard({
    required this.id,
    required this.title,
    required this.verdict,
    required this.score,
    required this.deltaE,
    required this.geometry,
    required this.text,
    required this.storage,
  });
}

class _ApprovalCard {
  final String orderId;
  final String customer;
  final String layoutName;
  final String version;
  final String fileName;
  final String status;
  final String deadline;
  final String protocol;

  const _ApprovalCard({
    required this.orderId,
    required this.customer,
    required this.layoutName,
    required this.version,
    required this.fileName,
    required this.status,
    required this.deadline,
    required this.protocol,
  });
}
