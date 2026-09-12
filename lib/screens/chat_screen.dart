import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../features/chat/chat.dart';
import '../features/protocols/protocols.dart';
import '../widgets/xp_widgets.dart';

enum _ChatKind { internal, approval }

typedef ChatAttachmentPicker = Future<ChatAttachmentUpload?> Function();

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String email;
  final String displayName;
  final String nickname;
  final String organizationName;
  final ProtocolCloudRepository? protocolCloudRepository;
  final ChatRepository? chatRepository;
  final ChatAttachmentPicker? attachmentPicker;

  const ChatScreen({
    super.key,
    this.currentUserId = '',
    required this.email,
    required this.displayName,
    required this.nickname,
    required this.organizationName,
    this.protocolCloudRepository,
    this.chatRepository,
    this.attachmentPicker,
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
  Future<void>? _cloudProtocolsLoadFuture;
  List<ChatThread> _serverThreads = const [];
  List<ChatMessage> _serverMessages = const [];
  bool _serverChatsLoading = false;
  bool _serverMessagesLoading = false;
  bool _sendingMessage = false;
  bool _sendingAttachment = false;
  bool _customerAccessUpdating = false;
  String? _serverChatError;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;

  bool get _usesServerChat => widget.chatRepository != null;

  ChatThread? get _activeServerThread {
    if (_serverThreads.isEmpty || _activeChat >= _serverThreads.length) {
      return null;
    }
    return _serverThreads[_activeChat];
  }

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
    _loadServerChats();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protocolCloudRepository != widget.protocolCloudRepository) {
      _loadCloudProtocols();
    }
    if (oldWidget.chatRepository != widget.chatRepository) {
      _messageSubscription?.cancel();
      _loadServerChats();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCloudProtocols() {
    final repository = widget.protocolCloudRepository;
    if (repository == null) return Future.value();
    final activeLoad = _cloudProtocolsLoadFuture;
    if (activeLoad != null) return activeLoad;

    final load = _loadCloudProtocolsOnce(repository);
    _cloudProtocolsLoadFuture = load;
    return load.whenComplete(() {
      if (identical(_cloudProtocolsLoadFuture, load)) {
        _cloudProtocolsLoadFuture = null;
      }
    });
  }

  Future<void> _loadCloudProtocolsOnce(
    ProtocolCloudRepository repository,
  ) async {
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

  Future<void> _loadServerChats({String? preferredJobId}) async {
    final repository = widget.chatRepository;
    if (repository == null || _serverChatsLoading) return;
    final activeThreadId = _activeServerThread?.id;
    setState(() {
      _serverChatsLoading = true;
      _serverChatError = null;
    });
    try {
      await repository.ensureDefaultThreads();
      final threads = await repository.listThreads();
      if (!mounted) return;
      setState(() {
        _serverThreads = threads;
        final preferredIndex = preferredJobId == null
            ? -1
            : threads.indexWhere((thread) => thread.jobId == preferredJobId);
        final preservedIndex = activeThreadId == null
            ? -1
            : threads.indexWhere((thread) => thread.id == activeThreadId);
        _activeChat = preferredIndex >= 0
            ? preferredIndex
            : preservedIndex >= 0
                ? preservedIndex
                : 0;
      });
      await _loadServerMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _serverThreads = const [];
        _serverMessages = const [];
        _serverChatError =
            'Управление чатами пока недоступно. Примените миграцию 017.';
      });
    } finally {
      if (mounted) setState(() => _serverChatsLoading = false);
    }
  }

  Future<void> _loadServerMessages() async {
    final repository = widget.chatRepository;
    final thread = _activeServerThread;
    if (repository == null || thread == null || _serverMessagesLoading) return;
    setState(() => _serverMessagesLoading = true);
    try {
      final messages = await repository.listMessages(thread.id);
      if (!mounted || _activeServerThread?.id != thread.id) return;
      setState(() => _serverMessages = messages);
      await _watchServerMessages(thread.id);
      _scrollMessagesToEnd();
    } catch (_) {
      if (!mounted || _activeServerThread?.id != thread.id) return;
      setState(() {
        _serverMessages = const [];
        _serverChatError = 'Не удалось загрузить сообщения.';
      });
    } finally {
      if (mounted) setState(() => _serverMessagesLoading = false);
    }
  }

  Future<void> _watchServerMessages(String threadId) async {
    await _messageSubscription?.cancel();
    final repository = widget.chatRepository;
    if (repository == null || !mounted) return;
    _messageSubscription = repository.watchMessages(threadId).listen(
      (messages) {
        if (!mounted || _activeServerThread?.id != threadId) return;
        setState(() {
          _serverMessages = messages;
          _serverChatError = null;
        });
        _scrollMessagesToEnd();
      },
      onError: (_) {
        if (!mounted || _activeServerThread?.id != threadId) return;
        setState(() {
          _serverChatError =
              'Живое обновление недоступно. Сообщения обновятся при повторном входе.';
        });
      },
    );
  }

  Future<void> _selectChat(int index) async {
    if (index == _activeChat) return;
    setState(() {
      _activeChat = index;
      if (_usesServerChat) {
        _serverMessages = const [];
        _serverChatError = null;
      }
    });
    if (_usesServerChat) await _loadServerMessages();
  }

  void _scrollMessagesToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_usesServerChat && _serverThreads.isEmpty) {
      if (_serverChatsLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _serverChatEmptyState();
    }
    return LayoutBuilder(builder: (_, constraints) {
      final compact = constraints.maxWidth < 760;
      if (compact) {
        return Column(children: [
          SizedBox(height: 122, child: _chatStrip()),
          Expanded(child: _chatPane()),
        ]);
      }
      return Row(children: [
        SizedBox(width: 286, child: _chatList()),
        Expanded(child: _chatPane()),
      ]);
    });
  }

  Widget _serverChatEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(
              Icons.forum_outlined,
              size: 44,
              color: AppTheme.blue,
            ),
            const SizedBox(height: 12),
            Text(
              _serverChatError ?? 'Доступных чатов пока нет.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadServerChats,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ]),
        ),
      ),
    );
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
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: XpInput(placeholder: 'Поиск'),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: _usesServerChat ? _serverThreads.length : _chats.length,
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
            itemCount: _usesServerChat ? _serverThreads.length : _chats.length,
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
            const Text(
              'TriMatrix',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
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
      ]),
    );
  }

  Widget _chatTile(int index) {
    final serverThread = _usesServerChat ? _serverThreads[index] : null;
    final chat = serverThread == null ? _chats[index] : null;
    final active = index == _activeChat;
    final title = serverThread?.title ?? _chatTitle(chat!);
    final subtitle = serverThread == null
        ? _chatSubtitle(chat!)
        : _serverThreadSubtitle(serverThread);
    final time = serverThread == null
        ? chat!.time
        : _shortDateTime(serverThread.updatedAt);
    final unread = serverThread == null ? chat!.unread : 0;
    final color = serverThread == null
        ? chat!.color
        : _serverThreadColor(serverThread.kind);
    return InkWell(
      onTap: () => _selectChat(index),
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
          _avatar(title, color, size: 40),
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
                  time,
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
                if (unread > 0) _unread(unread),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  String _serverThreadSubtitle(ChatThread thread) {
    switch (thread.kind) {
      case ChatThreadKind.organization:
        return 'общий чат команды';
      case ChatThreadKind.job:
        return 'обсуждение работы и протоколов';
      case ChatThreadKind.direct:
        return 'личный диалог';
      case ChatThreadKind.personal:
        return 'видно только вам';
    }
  }

  Color _serverThreadColor(ChatThreadKind kind) {
    switch (kind) {
      case ChatThreadKind.organization:
        return AppTheme.blue;
      case ChatThreadKind.job:
        return const Color(0xFF0EA5A4);
      case ChatThreadKind.direct:
        return const Color(0xFF16A34A);
      case ChatThreadKind.personal:
        return const Color(0xFF64748B);
    }
  }

  String _shortDateTime(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}';
  }

  Widget _chatPane() {
    if (_usesServerChat) return _serverChatPane();
    final chat = _chats[_activeChat];
    return Container(
      color: const Color(0xFFF4FAFD),
      child: Column(children: [
        _chatHeader(chat),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            itemCount: _visibleMessages.length,
            itemBuilder: (_, i) => _messageBubble(_visibleMessages[i]),
          ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _serverChatPane() {
    final thread = _activeServerThread!;
    return Container(
      color: const Color(0xFFF4FAFD),
      child: Column(children: [
        _chatHeaderContent(
          title: thread.title,
          subtitle: _serverThreadSubtitle(thread),
          color: _serverThreadColor(thread.kind),
        ),
        if (thread.kind == ChatThreadKind.job) _customerAccessBar(thread),
        if (_serverChatError != null) _serverChatErrorBanner(),
        Expanded(
          child: _serverMessagesLoading
              ? const Center(child: CircularProgressIndicator())
              : _serverMessages.isEmpty
                  ? const Center(
                      child: Text(
                        'Сообщений пока нет',
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      itemCount: _serverMessages.length,
                      itemBuilder: (_, i) => _messageBubble(
                        _serverMessageView(_serverMessages[i]),
                      ),
                    ),
        ),
        _composer(),
      ]),
    );
  }

  Widget _serverChatErrorBanner() {
    return Container(
      color: const Color(0xFFFFF4D6),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(children: [
        const Icon(
          Icons.info_outline,
          size: 16,
          color: Color(0xFF8A4B00),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _serverChatError!,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6B3B00),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Обновить чат',
          visualDensity: VisualDensity.compact,
          onPressed: _loadServerMessages,
          icon: const Icon(Icons.refresh, size: 18),
        ),
      ]),
    );
  }

  Widget _customerAccessBar(ChatThread thread) {
    final shared = thread.customerShared;
    final color = shared ? const Color(0xFF137A45) : const Color(0xFF8A4B00);
    return Container(
      key: const ValueKey('customer-access-bar'),
      color: shared ? const Color(0xFFE8F7EE) : const Color(0xFFFFF4D6),
      padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
      child: Row(children: [
        Icon(
          shared ? Icons.visibility_outlined : Icons.lock_outline,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            shared
                ? 'Работа доступна назначенному заказчику'
                : 'Внутренняя работа: заказчик ее не видит',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (thread.canManageCustomerAccess)
          FilledButton.tonalIcon(
            key: const ValueKey('current-customer-access-toggle'),
            onPressed: _customerAccessUpdating
                ? null
                : () => _requestCustomerAccessChange(
                      jobId: thread.jobId!,
                      jobLabel: thread.title,
                      shared: !shared,
                    ),
            icon: Icon(
              shared
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 17,
            ),
            label: Text(
              shared ? 'Закрыть доступ' : 'Открыть заказчику',
              style: const TextStyle(fontSize: 11),
            ),
          ),
      ]),
    );
  }

  Widget _chatHeader(_ChatItem chat) {
    final title = _chatTitle(chat);
    return _chatHeaderContent(
      title: title,
      subtitle: chat.kind == _ChatKind.approval
          ? 'заказчик · согласование версии · доступ ограничен'
          : '3 участника · удаленный просмотр включен',
      color: chat.color,
    );
  }

  Widget _chatHeaderContent({
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(children: [
        _avatar(title, color, size: 38),
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
              subtitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ]),
        ),
      ]),
    );
  }

  _ChatMessage _serverMessageView(ChatMessage message) {
    final nickname = message.senderNickname.trim();
    return _ChatMessage(
      author: message.senderLabel,
      role: nickname.isEmpty ? 'участник' : '@$nickname',
      time: _shortDateTime(message.createdAt),
      text: message.text,
      isMine: message.senderId == widget.currentUserId,
      attachment: message.attachment,
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
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            if (message.attachment != null) ...[
              if (message.text.isNotEmpty) const SizedBox(height: 9),
              _attachmentCard(message.attachment!),
            ],
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
              onPressed: _showProtocolDetails,
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
    final isApproval =
        !_usesServerChat && _chats[_activeChat].kind == _ChatKind.approval;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton.filledTonal(
          key: const ValueKey('chat-attach-button'),
          tooltip: 'Прикрепить',
          onPressed: _sendingAttachment ? null : _showAttachmentMenu,
          icon: _sendingAttachment
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: const ValueKey('chat-message-input'),
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
        IconButton.filled(
          key: const ValueKey('chat-send-button'),
          tooltip: 'Отправить',
          onPressed: _sendingMessage ? null : _send,
          icon: _sendingMessage
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send),
        ),
      ]),
    );
  }

  Future<void> _showAttachmentMenu() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.78;
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 680, maxHeight: maxHeight),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                children: [
                  if (_usesServerChat)
                    _attachmentAction(
                      context: sheetContext,
                      icon: Icons.person_search_outlined,
                      title: 'Открыть работу заказчику',
                      subtitle: 'выбрать работу и управлять доступом заказчика',
                      key: const ValueKey('customer-access-menu-action'),
                      onTap: _showCustomerWorkDialog,
                    ),
                  _attachmentAction(
                    context: sheetContext,
                    icon: Icons.description_outlined,
                    title: 'Протокол проверки',
                    subtitle: 'результаты, этапы и параметры',
                    onTap: _showProtocolDetails,
                  ),
                  _attachmentAction(
                    context: sheetContext,
                    icon: Icons.image_outlined,
                    title: 'Превью',
                    subtitle:
                        'облегчённое изображение для удалённого просмотра',
                    onTap: _openCloudPreview,
                  ),
                  _attachmentAction(
                    context: sheetContext,
                    icon: Icons.difference_outlined,
                    title: 'Карта отличий',
                    subtitle: 'цветовая карта выбранной проверки',
                    onTap: _openCloudPreview,
                  ),
                  _attachmentAction(
                    context: sheetContext,
                    icon: Icons.fact_check_outlined,
                    title: 'Макет на согласование',
                    subtitle: 'версия макета и решение заказчика',
                    onTap: () => xpDlg(
                      context,
                      'Согласование макета',
                      'Выбор версии макета подключим следующим этапом чата.',
                    ),
                  ),
                  _attachmentAction(
                    context: sheetContext,
                    icon: Icons.lock_clock_outlined,
                    title: 'Запросить оригинал',
                    subtitle: 'временный доступ у владельца проверки',
                    onTap: () => xpDlg(
                      context,
                      'Доступ к оригиналу',
                      'Оригинал остаётся на устройстве. Запрос доступа будет отправлен владельцу проверки.',
                    ),
                  ),
                  _attachmentAction(
                    context: sheetContext,
                    icon: Icons.attach_file,
                    title: 'Файл или изображение',
                    subtitle: 'до 10 МБ · только для участников работы',
                    key: const ValueKey('chat-file-attachment-action'),
                    onTap: _pickAndSendAttachment,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendAttachment() async {
    final repository = widget.chatRepository;
    final thread = _activeServerThread;
    if (repository == null || thread == null) {
      await xpDlg(
        context,
        'Файл или изображение',
        'Обычные вложения доступны в облачном чате работы.',
      );
      return;
    }
    if (thread.kind != ChatThreadKind.job) {
      await xpDlg(
        context,
        'Файл или изображение',
        'Выберите чат конкретной работы. В командный чат и личные заметки вложения пока не отправляются.',
      );
      return;
    }

    try {
      final upload = await (widget.attachmentPicker ?? _pickAttachment)();
      if (upload == null || !mounted) return;
      if (upload.bytes.isEmpty) {
        throw const FormatException('empty_attachment');
      }
      if (upload.bytes.length > SupabaseChatRepository.maxAttachmentBytes) {
        throw const FormatException('attachment_too_large');
      }
      setState(() => _sendingAttachment = true);
      final message = await repository.sendAttachment(
        threadId: thread.id,
        upload: upload,
        text: _msgCtrl.text,
      );
      if (!mounted || _activeServerThread?.id != thread.id) return;
      setState(() {
        if (!_serverMessages.any((item) => item.id == message.id)) {
          _serverMessages = [..._serverMessages, message];
        }
        _msgCtrl.clear();
        _serverChatError = null;
      });
      _scrollMessagesToEnd();
    } on FormatException catch (error) {
      if (!mounted) return;
      final tooLarge = error.message == 'attachment_too_large';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tooLarge
                ? 'Файл больше 10 МБ. Выберите файл меньшего размера.'
                : 'Выбранный файл пустой и не может быть отправлен.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось отправить вложение. Проверьте доступ к работе и повторите.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<ChatAttachmentUpload?> _pickAttachment() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;
    final knownLength = file.lengthSync();
    final length = knownLength ?? await file.length();
    if (length > SupabaseChatRepository.maxAttachmentBytes) {
      throw const FormatException('attachment_too_large');
    }
    final bytes = await file.readAsBytes();
    return ChatAttachmentUpload(
      fileName: file.name,
      mimeType: _mimeTypeForFileName(file.name),
      bytes: bytes,
    );
  }

  String _mimeTypeForFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'zip' => 'application/zip',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };
  }

  Widget _attachmentCard(ChatAttachment attachment) {
    return Container(
      key: ValueKey('chat-attachment-${attachment.assetId}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFF),
        border: Border.all(color: const Color(0xFFC9E2F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6FC),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            attachment.isImage ? Icons.image_outlined : Icons.insert_drive_file,
            color: AppTheme.blue,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _fileSizeLabel(attachment.sizeBytes),
                style: const TextStyle(fontSize: 9, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: ValueKey('open-chat-attachment-${attachment.assetId}'),
          onPressed: () => _openAttachment(attachment),
          child: Text(attachment.isImage ? 'Открыть' : 'Скачать'),
        ),
      ]),
    );
  }

  String _fileSizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Future<void> _openAttachment(ChatAttachment attachment) async {
    final repository = widget.chatRepository;
    if (repository == null) return;
    try {
      final bytes = await repository.loadAttachment(attachment);
      if (!mounted) return;
      if (!attachment.isImage) {
        await FilePicker.saveFile(
          fileName: attachment.fileName,
          bytes: bytes,
          mimeType: attachment.mimeType,
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      attachment.fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => FilePicker.saveFile(
                      fileName: attachment.fileName,
                      bytes: bytes,
                      mimeType: attachment.mimeType,
                    ),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Скачать'),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть вложение.')),
      );
    }
  }

  Widget _attachmentAction({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Key? key,
  }) {
    return ListTile(
      key: key,
      leading: Icon(icon, color: AppTheme.blue),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Future<void> _showCustomerWorkDialog() async {
    final repository = widget.chatRepository;
    if (repository == null) return;

    late final List<CustomerShareCandidate> candidates;
    try {
      candidates = await repository.listCustomerShareCandidates();
    } catch (_) {
      if (!mounted) return;
      await xpDlg(
        context,
        'Доступ заказчика',
        'Не удалось получить работы. Проверьте миграцию 017 и права пользователя.',
      );
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      await xpDlg(
        context,
        'Доступ заказчика',
        'Нет активных работ с подтвержденным заказчиком, которыми вы можете управлять.',
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Доступ заказчика к работе',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final candidate = candidates[index];
                return ListTile(
                  key: ValueKey('customer-job-${candidate.jobId}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    candidate.customerShared
                        ? Icons.visibility_outlined
                        : Icons.lock_outline,
                    color: candidate.customerShared
                        ? const Color(0xFF137A45)
                        : const Color(0xFF8A4B00),
                  ),
                  title: Text(
                    'Работа № ${candidate.jobNumber}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    candidate.customerName.isEmpty
                        ? 'Заказчик подтвержден'
                        : candidate.customerName,
                    style: const TextStyle(fontSize: 10),
                  ),
                  trailing: FilledButton.tonal(
                    key: ValueKey(
                      'customer-access-toggle-${candidate.jobId}',
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _requestCustomerAccessChange(
                        jobId: candidate.jobId,
                        jobLabel: 'работу № ${candidate.jobNumber}',
                        shared: !candidate.customerShared,
                      );
                    },
                    child: Text(
                      candidate.customerShared ? 'Закрыть' : 'Открыть',
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestCustomerAccessChange({
    required String jobId,
    required String jobLabel,
    required bool shared,
  }) async {
    final repository = widget.chatRepository;
    if (repository == null || _customerAccessUpdating) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          shared ? 'Открыть заказчику?' : 'Закрыть доступ?',
        ),
        content: Text(
          shared
              ? 'Заказчик увидит $jobLabel, ее чат, протоколы и опубликованные материалы.'
              : 'Заказчик больше не увидит $jobLabel и ее материалы. Команда сохранит доступ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('confirm-customer-access-change'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(shared ? 'Открыть' : 'Закрыть'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _customerAccessUpdating = true);
    try {
      await repository.setCustomerAccess(jobId: jobId, shared: shared);
      await _loadServerChats(preferredJobId: jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shared
                ? 'Работа открыта назначенному заказчику'
                : 'Доступ заказчика закрыт',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await xpDlg(
        context,
        'Доступ заказчика',
        'Не удалось изменить доступ. Проверьте миграцию 017 и свои права на работу.',
      );
    } finally {
      if (mounted) setState(() => _customerAccessUpdating = false);
    }
  }

  Future<void> _showProtocolDetails() async {
    await _loadCloudProtocols();
    if (!mounted) return;
    final record = _selectedCloudProtocol;
    if (record == null) {
      xpDlg(
        context,
        'Протоколы',
        'Доступных облачных протоколов пока нет.',
      );
      return;
    }
    final card = _cloudCheckCard(record.protocol);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _cloudProtocolLabel(record.protocol),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _cloudProtocolSelector(),
                    const SizedBox(height: 10),
                    _previewBox(_selectedCloudPreview),
                    const SizedBox(height: 10),
                    _techRows(card),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _openCloudPreview() {
    if (_selectedCloudPreview == null || _selectedCloudProtocol == null) {
      xpDlg(
        context,
        'Превью',
        'Для выбранной проверки облачное превью пока недоступно.',
      );
      return;
    }
    _showCloudPreview();
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

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    if (_usesServerChat) {
      final repository = widget.chatRepository;
      final thread = _activeServerThread;
      if (repository == null || thread == null || _sendingMessage) return;
      setState(() => _sendingMessage = true);
      try {
        final message = await repository.sendText(
          threadId: thread.id,
          text: text,
        );
        if (!mounted || _activeServerThread?.id != thread.id) return;
        setState(() {
          if (!_serverMessages.any((item) => item.id == message.id)) {
            _serverMessages = [..._serverMessages, message];
          }
          _msgCtrl.clear();
          _serverChatError = null;
        });
        _scrollMessagesToEnd();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось отправить сообщение'),
          ),
        );
      } finally {
        if (mounted) setState(() => _sendingMessage = false);
      }
      return;
    }
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
    _scrollMessagesToEnd();
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
  final ChatAttachment? attachment;

  const _ChatMessage({
    required this.author,
    required this.role,
    required this.time,
    required this.text,
    required this.isMine,
    this.card,
    this.approvalCard,
    this.attachment,
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
