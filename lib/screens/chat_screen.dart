import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../features/chat/chat.dart';
import '../features/protocols/protocols.dart';
import '../widgets/xp_widgets.dart';

enum _ChatKind { internal, approval }

enum _ChatListFilter { active, unread, archive }

enum _ChatSection { personal, teams, works, service }

typedef ChatAttachmentPicker = Future<ChatAttachmentUpload?> Function();

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String email;
  final String displayName;
  final String nickname;
  final String organizationName;
  final String? initialJobId;
  final ChatThreadKind? initialThreadKind;
  final bool canManageTeams;
  final bool canManageCustomerChatAccess;
  final bool showOrganizationService;
  final bool canShareInspectionAssets;
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
    this.initialJobId,
    this.initialThreadKind,
    this.canManageTeams = false,
    this.canManageCustomerChatAccess = false,
    this.showOrganizationService = false,
    this.canShareInspectionAssets = false,
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
  final _chatSearchCtrl = TextEditingController();
  Timer? _contactSearchDebounce;
  _ChatSection _chatSection = _ChatSection.personal;
  _ChatListFilter _chatListFilter = _ChatListFilter.active;
  bool _onlyUnreadWorks = false;
  String _chatSearchQuery = '';
  List<ChatContact> _contactResults = const [];
  bool _contactsLoading = false;
  bool _teamActionBusy = false;
  String? _openedUnreadThreadId;
  List<CloudProtocolRecord> _cloudProtocols = const [];
  CloudProtocolRecord? _selectedCloudProtocol;
  Uint8List? _selectedCloudPreview;
  bool _cloudProtocolsLoading = false;
  String? _cloudProtocolsError;
  Future<void>? _cloudProtocolsLoadFuture;
  List<ChatThread> _serverThreads = const [];
  List<ChatMessage> _serverMessages = const [];
  bool _serverChatsLoading = false;
  bool _serverThreadsRefreshing = false;
  bool _serverMessagesLoading = false;
  bool _sendingMessage = false;
  bool _sendingAttachment = false;
  bool _customerAccessUpdating = false;
  bool _sendWorkMessageToCustomer = false;
  String? _serverChatError;
  final List<StreamSubscription<List<ChatMessage>>> _messageSubscriptions = [];
  StreamSubscription<void>? _threadSubscription;
  final Map<String, List<ChatMessage>> _messagesByThread = {};

  bool get _usesServerChat => widget.chatRepository != null;

  ChatThread? get _activeServerThread {
    if (_serverThreads.isEmpty || _activeChat >= _serverThreads.length) {
      return null;
    }
    return _serverThreads[_activeChat];
  }

  _WorkThreadGroup? get _activeWorkGroup {
    final active = _activeServerThread;
    if (active?.jobId == null ||
        (active!.kind != ChatThreadKind.jobCustomer &&
            active.kind != ChatThreadKind.jobInternal)) {
      return null;
    }
    for (final group in _allWorkGroups) {
      if (group.jobId == active.jobId) return group;
    }
    return null;
  }

  List<_IndexedChatThread> get _activeMessageChannels {
    final group = _activeWorkGroup;
    if (group != null) return group.channels;
    final active = _activeServerThread;
    if (active == null) return const [];
    return [_IndexedChatThread(index: _activeChat, thread: active)];
  }

  String? get _activeMessageSelectionKey {
    final group = _activeWorkGroup;
    if (group != null) return 'job:${group.jobId}';
    final active = _activeServerThread;
    return active == null ? null : 'thread:${active.id}';
  }

  ChatThread? get _workMessageTarget {
    final group = _activeWorkGroup;
    if (group == null) return _activeServerThread;
    final preferredKind = _sendWorkMessageToCustomer
        ? ChatThreadKind.jobCustomer
        : ChatThreadKind.jobInternal;
    for (final entry in group.channels) {
      if (entry.thread.kind == preferredKind) return entry.thread;
    }
    return group.channels.first.thread;
  }

  bool get _canChooseWorkAudience {
    final group = _activeWorkGroup;
    if (group == null) return false;
    return group.channels.any(
          (entry) => entry.thread.kind == ChatThreadKind.jobInternal,
        ) &&
        group.channels.any(
          (entry) => entry.thread.kind == ChatThreadKind.jobCustomer,
        );
  }

  List<int> get _visibleChatIndexes {
    if (_usesServerChat && _chatSection == _ChatSection.works) {
      return _visibleWorkGroups
          .expand((group) => group.channels.map((entry) => entry.index))
          .toList(growable: false);
    }
    final itemCount = _usesServerChat ? _serverThreads.length : _chats.length;
    final indexes = [
      for (var index = 0; index < itemCount; index++)
        if (_chatMatchesNavigation(index)) index,
    ];
    if (_usesServerChat) {
      indexes.sort((left, right) {
        final leftThread = _serverThreads[left];
        final rightThread = _serverThreads[right];
        return rightThread.updatedAt.compareTo(leftThread.updatedAt);
      });
    }
    return indexes;
  }

  _ChatSection _sectionForKind(ChatThreadKind kind) => switch (kind) {
        ChatThreadKind.personal ||
        ChatThreadKind.direct =>
          _ChatSection.personal,
        ChatThreadKind.organization ||
        ChatThreadKind.team =>
          _ChatSection.teams,
        ChatThreadKind.jobCustomer ||
        ChatThreadKind.jobInternal =>
          _ChatSection.works,
        ChatThreadKind.service => _ChatSection.service,
      };

  bool _chatMatchesNavigation(int index) {
    final query = _chatSearchQuery.trim().toLowerCase();
    if (_usesServerChat) {
      final thread = _serverThreads[index];
      if (_sectionForKind(thread.kind) != _chatSection) return false;
      if (query.isNotEmpty) {
        if (_chatSection == _ChatSection.personal &&
            thread.kind == ChatThreadKind.direct) {
          return false;
        }
        return '${thread.title} ${thread.customerName} ${thread.jobId ?? ''}'
            .toLowerCase()
            .contains(query);
      }
      if (_chatSection == _ChatSection.teams) {
        return switch (_chatListFilter) {
          _ChatListFilter.active => !thread.isArchivedTeam,
          _ChatListFilter.unread => !thread.isArchivedTeam &&
              (thread.unreadCount > 0 || thread.id == _openedUnreadThreadId),
          _ChatListFilter.archive => thread.isArchivedTeam,
        };
      }
      return true;
    }

    final chat = _chats[index];
    if (query.isNotEmpty) {
      return '${_chatTitle(chat)} ${_chatSubtitle(chat)}'
          .toLowerCase()
          .contains(query);
    }
    return switch (_chatListFilter) {
      _ChatListFilter.active => true,
      _ChatListFilter.unread => chat.unread > 0,
      _ChatListFilter.archive => false,
    };
  }

  int get _activeThreadCount => _usesServerChat
      ? _chatSection == _ChatSection.works
          ? _allWorkGroups.where((group) => !group.isArchived).length
          : _serverThreads
              .where((thread) =>
                  _sectionForKind(thread.kind) == _chatSection &&
                  !thread.isArchivedTeam)
              .length
      : _chats.length;

  int get _unreadThreadCount => _usesServerChat
      ? _chatSection == _ChatSection.works
          ? _allWorkGroups.where((group) => group.unreadCount > 0).length
          : _serverThreads
              .where((thread) =>
                  _sectionForKind(thread.kind) == _chatSection &&
                  thread.unreadCount > 0 &&
                  !thread.isArchivedTeam)
              .length
      : _chats.where((chat) => chat.unread > 0).length;

  int get _archivedThreadCount => _usesServerChat
      ? _chatSection == _ChatSection.works
          ? _allWorkGroups.where((group) => group.isArchived).length
          : _serverThreads
              .where((thread) =>
                  _sectionForKind(thread.kind) == _chatSection &&
                  thread.isArchivedTeam)
              .length
      : 0;

  List<_WorkThreadGroup> get _allWorkGroups {
    final grouped = <String, List<_IndexedChatThread>>{};
    for (var index = 0; index < _serverThreads.length; index++) {
      final thread = _serverThreads[index];
      if (_sectionForKind(thread.kind) != _ChatSection.works) continue;
      final key = thread.jobId ?? thread.id;
      grouped.putIfAbsent(key, () => []).add(
            _IndexedChatThread(index: index, thread: thread),
          );
    }
    final result = grouped.entries.map((entry) {
      final channels = entry.value
        ..sort((left, right) => left.thread.kind == ChatThreadKind.jobInternal
            ? -1
            : right.thread.kind == ChatThreadKind.jobInternal
                ? 1
                : 0);
      return _WorkThreadGroup(jobId: entry.key, channels: channels);
    }).toList();
    result.sort(
      (left, right) =>
          (right.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        left.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    return result;
  }

  List<_WorkThreadGroup> get _visibleWorkGroups {
    final query = _chatSearchQuery.trim().toLowerCase();
    return _allWorkGroups.where((group) {
      if (query.isNotEmpty) {
        return '${group.title} ${group.customerName} ${group.jobId}'
            .toLowerCase()
            .contains(query);
      }
      final matchesStatus = switch (_chatListFilter) {
        _ChatListFilter.active =>
          !group.isArchived && group.jobFlowState != 'blocked',
        _ChatListFilter.unread =>
          !group.isArchived && group.jobFlowState == 'blocked',
        _ChatListFilter.archive => group.isArchived,
      };
      if (!matchesStatus) return false;
      return !_onlyUnreadWorks ||
          group.unreadCount > 0 ||
          group.channels.any(
            (entry) => entry.thread.id == _openedUnreadThreadId,
          );
    }).toList(growable: false);
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
      role: 'представитель заказчика',
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
    _loadServerChats(preferredJobId: widget.initialJobId);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.protocolCloudRepository != widget.protocolCloudRepository) {
      _loadCloudProtocols();
    }
    if (oldWidget.chatRepository != widget.chatRepository) {
      _cancelMessageSubscriptions();
      _threadSubscription?.cancel();
      _loadServerChats(preferredJobId: widget.initialJobId);
    } else if ((oldWidget.initialJobId != widget.initialJobId ||
            oldWidget.initialThreadKind != widget.initialThreadKind) &&
        widget.initialJobId != null) {
      _loadServerChats(preferredJobId: widget.initialJobId);
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _chatSearchCtrl.dispose();
    _contactSearchDebounce?.cancel();
    for (final subscription in _messageSubscriptions) {
      subscription.cancel();
    }
    _threadSubscription?.cancel();
    super.dispose();
  }

  Future<void> _cancelMessageSubscriptions() async {
    final subscriptions = List.of(_messageSubscriptions);
    _messageSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
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
        var preferredIndex = preferredJobId == null
            ? -1
            : threads.indexWhere((thread) =>
                thread.jobId == preferredJobId &&
                thread.kind ==
                    (widget.initialThreadKind ?? ChatThreadKind.jobInternal));
        if (preferredIndex < 0 && preferredJobId != null) {
          preferredIndex =
              threads.indexWhere((thread) => thread.jobId == preferredJobId);
        }
        final preservedIndex = activeThreadId == null
            ? -1
            : threads.indexWhere((thread) => thread.id == activeThreadId);
        final personalIndex = threads.indexWhere(
          (thread) => thread.kind == ChatThreadKind.personal,
        );
        _activeChat = preferredIndex >= 0
            ? preferredIndex
            : preservedIndex >= 0
                ? preservedIndex
                : personalIndex >= 0
                    ? personalIndex
                    : 0;
        _chatSection = threads.isEmpty
            ? _ChatSection.personal
            : preferredIndex >= 0
                ? _ChatSection.works
                : _sectionForKind(threads[_activeChat].kind);
        _sendWorkMessageToCustomer = false;
        _messagesByThread.clear();
      });
      await _watchServerThreads();
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

  Future<void> _watchServerThreads() async {
    await _threadSubscription?.cancel();
    final repository = widget.chatRepository;
    if (repository == null || !mounted) return;
    _threadSubscription = repository.watchThreadChanges().listen(
          (_) => unawaited(_refreshServerThreads()),
        );
  }

  Future<void> _refreshServerThreads() async {
    final repository = widget.chatRepository;
    if (repository == null || _serverChatsLoading || _serverThreadsRefreshing) {
      return;
    }
    _serverThreadsRefreshing = true;
    final activeThreadId = _activeServerThread?.id;
    try {
      final threads = await repository.listThreads();
      if (!mounted) return;
      final preservedIndex = activeThreadId == null
          ? -1
          : threads.indexWhere((thread) => thread.id == activeThreadId);
      final activeThreadChanged = preservedIndex < 0 && threads.isNotEmpty;
      setState(() {
        _serverThreads = threads;
        _activeChat = preservedIndex >= 0 ? preservedIndex : 0;
      });
      if (activeThreadChanged) {
        await _cancelMessageSubscriptions();
        await _loadServerMessages();
      }
    } catch (_) {
      // The open chat remains usable; the next Realtime event retries the list.
    } finally {
      _serverThreadsRefreshing = false;
    }
  }

  Future<void> _loadServerMessages() async {
    final repository = widget.chatRepository;
    final thread = _activeServerThread;
    if (repository == null || thread == null) return;
    final selectionKey = _activeMessageSelectionKey;
    final channels = List<_IndexedChatThread>.of(_activeMessageChannels);
    setState(() => _serverMessagesLoading = true);
    try {
      final loaded = await Future.wait(
        channels.map((entry) async => MapEntry(
              entry.thread.id,
              await repository.listMessages(entry.thread.id),
            )),
      );
      if (!mounted || _activeMessageSelectionKey != selectionKey) return;
      setState(() {
        _messagesByThread
          ..clear()
          ..addEntries(loaded);
        _serverMessages = _mergedMessages(channels);
      });
      await _watchServerMessages(channels, selectionKey);
      for (final entry in channels) {
        await _markServerThreadRead(entry.thread.id);
      }
      _scrollMessagesToEnd();
    } catch (_) {
      if (!mounted || _activeMessageSelectionKey != selectionKey) return;
      setState(() {
        _serverMessages = const [];
        _serverChatError = 'Не удалось загрузить сообщения.';
      });
    } finally {
      if (mounted && _activeMessageSelectionKey == selectionKey) {
        setState(() => _serverMessagesLoading = false);
      }
    }
  }

  List<ChatMessage> _mergedMessages(
    List<_IndexedChatThread> channels,
  ) {
    final merged = channels
        .expand<ChatMessage>(
          (entry) =>
              _messagesByThread[entry.thread.id] ?? const <ChatMessage>[],
        )
        .toList(growable: false);
    merged.sort((left, right) {
      final byDate = left.createdAt.compareTo(right.createdAt);
      return byDate != 0 ? byDate : left.id.compareTo(right.id);
    });
    return merged;
  }

  Future<void> _watchServerMessages(
    List<_IndexedChatThread> channels,
    String? selectionKey,
  ) async {
    await _cancelMessageSubscriptions();
    final repository = widget.chatRepository;
    if (repository == null || !mounted) return;
    for (final entry in channels) {
      final threadId = entry.thread.id;
      final subscription = repository.watchMessages(threadId).listen(
        (messages) {
          if (!mounted || _activeMessageSelectionKey != selectionKey) return;
          setState(() {
            _messagesByThread[threadId] = messages;
            _serverMessages = _mergedMessages(_activeMessageChannels);
            _serverChatError = null;
          });
          unawaited(_markServerThreadRead(threadId));
          _scrollMessagesToEnd();
        },
        onError: (_) {
          if (!mounted || _activeMessageSelectionKey != selectionKey) return;
          setState(() {
            _serverChatError =
                'Живое обновление недоступно. Сообщения обновятся при повторном входе.';
          });
        },
      );
      _messageSubscriptions.add(subscription);
    }
  }

  Future<void> _selectChat(int index) async {
    if (index == _activeChat) {
      if (_usesServerChat &&
          (_serverMessages.isEmpty || _serverMessagesLoading)) {
        await _loadServerMessages();
      }
      return;
    }
    setState(() {
      if (_usesServerChat &&
          _chatSearchQuery.isEmpty &&
          _chatListFilter == _ChatListFilter.unread) {
        _openedUnreadThreadId = _serverThreads[index].id;
      }
      _activeChat = index;
      _sendWorkMessageToCustomer = false;
      if (_usesServerChat) {
        _serverMessages = const [];
        _messagesByThread.clear();
        _serverChatError = null;
      }
    });
    if (_usesServerChat) await _loadServerMessages();
  }

  Future<void> _markServerThreadRead(String threadId) async {
    final repository = widget.chatRepository;
    if (repository == null) return;
    try {
      await repository.markThreadRead(threadId);
      if (!mounted) return;
      final index =
          _serverThreads.indexWhere((thread) => thread.id == threadId);
      if (index < 0 || _serverThreads[index].unreadCount == 0) return;
      setState(() {
        final updated = List<ChatThread>.of(_serverThreads);
        updated[index] = updated[index].copyWith(unreadCount: 0);
        _serverThreads = updated;
      });
    } catch (_) {
      // Old deployments without migration 029 still keep chat usable.
    }
  }

  Future<void> _setChatFilter(_ChatListFilter filter) async {
    if (_chatListFilter == filter && _chatSearchQuery.isEmpty) return;
    setState(() {
      _chatListFilter = filter;
      _chatSearchQuery = '';
      _openedUnreadThreadId = null;
      _chatSearchCtrl.clear();
    });
    await _selectFirstVisibleChatIfNeeded();
  }

  Future<void> _setChatSearch(String value) async {
    _contactSearchDebounce?.cancel();
    setState(() {
      _chatSearchQuery = value;
      _openedUnreadThreadId = null;
      if (_chatSection == _ChatSection.personal && value.trim().isEmpty) {
        _contactResults = const [];
        _contactsLoading = false;
      }
    });
    if (_chatSection == _ChatSection.personal && value.trim().isNotEmpty) {
      _contactSearchDebounce = Timer(
        const Duration(milliseconds: 280),
        () => _searchContacts(value),
      );
    }
    await _selectFirstVisibleChatIfNeeded();
  }

  Future<void> _setChatSection(_ChatSection section) async {
    if (_chatSection == section) return;
    _contactSearchDebounce?.cancel();
    setState(() {
      _chatSection = section;
      _chatListFilter = _ChatListFilter.active;
      _onlyUnreadWorks = false;
      _chatSearchQuery = '';
      _chatSearchCtrl.clear();
      _contactResults = const [];
      _contactsLoading = false;
      _openedUnreadThreadId = null;
    });
    await _selectFirstVisibleChatIfNeeded();
  }

  Future<void> _searchContacts(String query) async {
    final repository = widget.chatRepository;
    final normalized = query.trim();
    if (repository == null || normalized.isEmpty) return;
    setState(() => _contactsLoading = true);
    try {
      final contacts = await repository.searchContacts(normalized);
      if (!mounted || _chatSearchQuery.trim() != normalized) return;
      setState(() {
        _contactResults = contacts;
        _contactsLoading = false;
      });
    } catch (_) {
      if (!mounted || _chatSearchQuery.trim() != normalized) return;
      setState(() {
        _contactResults = const [];
        _contactsLoading = false;
        _serverChatError = 'Не удалось выполнить поиск людей.';
      });
    }
  }

  Future<void> _openDirectChat(ChatContact contact) async {
    final repository = widget.chatRepository;
    if (repository == null) return;
    setState(() => _contactsLoading = true);
    try {
      final threadId = await repository.openDirectThread(contact.userId);
      final threads = await repository.listThreads();
      if (!mounted) return;
      final index = threads.indexWhere((thread) => thread.id == threadId);
      if (index < 0) throw StateError('Созданный диалог не найден');
      setState(() {
        _serverThreads = threads;
        _activeChat = index;
        _chatSection = _ChatSection.personal;
        _chatSearchQuery = '';
        _chatSearchCtrl.clear();
        _contactResults = const [];
        _contactsLoading = false;
        _serverMessages = const [];
        _messagesByThread.clear();
        _sendWorkMessageToCustomer = false;
      });
      await _loadServerMessages();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contactsLoading = false;
        _serverChatError = 'Не удалось открыть личный диалог.';
      });
    }
  }

  Future<void> _selectFirstVisibleChatIfNeeded() async {
    final visible = _visibleChatIndexes;
    if (visible.isEmpty || visible.contains(_activeChat)) return;
    await _selectChat(visible.first);
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
      // A persistent vertical list remains usable with hundreds of works.
      // Keep the horizontal strip only for genuinely narrow phone layouts.
      final compact = constraints.maxWidth < 680;
      final visibleIndexes = _visibleChatIndexes;
      final hasVisibleSelection = visibleIndexes.contains(_activeChat);
      if (compact) {
        return Column(children: [
          SizedBox(height: 204, child: _chatStrip()),
          Expanded(
            child:
                hasVisibleSelection ? _chatPane() : _filteredChatsEmptyState(),
          ),
        ]);
      }
      return Row(children: [
        SizedBox(width: 286, child: _chatList()),
        Expanded(
          child: hasVisibleSelection ? _chatPane() : _filteredChatsEmptyState(),
        ),
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
        color: AppTheme.surfaceMuted,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _listHeader(),
        _chatNavigationControls(),
        Expanded(child: _chatNavigationBody()),
      ]),
    );
  }

  Widget _chatStrip() {
    return Container(
      color: AppTheme.surfaceMuted,
      child: Column(children: [
        _listHeader(compact: true),
        _chatNavigationControls(compact: true),
        Expanded(child: _chatNavigationBody(compact: true)),
      ]),
    );
  }

  Widget _chatNavigationBody({bool compact = false}) {
    if (_usesServerChat && _chatSection == _ChatSection.works) {
      final groups = _visibleWorkGroups;
      if (groups.isEmpty) return _emptyChatList(compact: compact);
      return ListView.builder(
        scrollDirection: compact ? Axis.horizontal : Axis.vertical,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        itemCount: groups.length,
        itemBuilder: (_, index) => SizedBox(
          width: compact ? 252 : null,
          child: _workChatTile(groups[index]),
        ),
      );
    }

    final indexes = _visibleChatIndexes;
    final showContacts = _usesServerChat &&
        _chatSection == _ChatSection.personal &&
        _chatSearchQuery.trim().isNotEmpty;
    if (indexes.isEmpty && !showContacts) {
      return _emptyChatList(compact: compact);
    }
    final contactCount = showContacts ? _contactResults.length : 0;
    final loadingCount = showContacts && _contactsLoading ? 1 : 0;
    final total = contactCount + loadingCount + indexes.length;
    if (total == 0) return _emptyChatList(compact: compact);
    return ListView.builder(
      scrollDirection: compact ? Axis.horizontal : Axis.vertical,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: total,
      itemBuilder: (_, position) {
        if (loadingCount == 1 && position == 0) {
          return SizedBox(
            width: compact ? 218 : null,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final adjusted = position - loadingCount;
        if (adjusted < contactCount) {
          return SizedBox(
            width: compact ? 218 : null,
            child: _contactTile(_contactResults[adjusted]),
          );
        }
        final threadIndex = indexes[adjusted - contactCount];
        return SizedBox(
          width: compact ? 218 : null,
          child: _chatTile(threadIndex),
        );
      },
    );
  }

  Widget _chatNavigationControls({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, compact ? 5 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _chatSectionTabs(),
        if (_chatSection != _ChatSection.service) ...[
          const SizedBox(height: 7),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  key: const ValueKey('chat-search'),
                  controller: _chatSearchCtrl,
                  onChanged: _setChatSearch,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: switch (_chatSection) {
                      _ChatSection.personal => 'Найти человека',
                      _ChatSection.teams => 'Найти команду',
                      _ChatSection.works => 'Код работы или заказчик',
                      _ChatSection.service => '',
                    },
                    hintStyle: const TextStyle(fontSize: 11),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _chatSearchQuery.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('chat-search-clear'),
                            tooltip: 'Очистить поиск',
                            onPressed: () {
                              _chatSearchCtrl.clear();
                              _setChatSearch('');
                            },
                            icon: const Icon(Icons.close, size: 17),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.blue),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
        if (_chatSection == _ChatSection.works ||
            _chatSection == _ChatSection.teams) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: _chatFilterChip(
                filter: _ChatListFilter.active,
                label: _chatSection == _ChatSection.works
                    ? 'В работе'
                    : 'Активные',
                count: _activeThreadCount,
                key: const ValueKey('chat-filter-active'),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: _chatFilterChip(
                filter: _ChatListFilter.unread,
                label: _chatSection == _ChatSection.works
                    ? 'Стоп'
                    : 'Непрочитанные',
                count: _chatSection == _ChatSection.works
                    ? _allWorkGroups
                        .where((group) =>
                            !group.isArchived &&
                            group.jobFlowState == 'blocked')
                        .length
                    : _unreadThreadCount,
                key: const ValueKey('chat-filter-unread'),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: _chatFilterChip(
                filter: _ChatListFilter.archive,
                label:
                    _chatSection == _ChatSection.works ? 'Выполнены' : 'Архив',
                count: _archivedThreadCount,
                key: const ValueKey('chat-filter-archive'),
              ),
            ),
            if (_chatSection == _ChatSection.works) ...[
              const SizedBox(width: 5),
              IconButton.filledTonal(
                key: const ValueKey('chat-only-unread'),
                tooltip: 'Только непрочитанные',
                onPressed: () =>
                    setState(() => _onlyUnreadWorks = !_onlyUnreadWorks),
                style: IconButton.styleFrom(
                  backgroundColor:
                      _onlyUnreadWorks ? AppTheme.blue : AppTheme.surfaceMuted,
                  foregroundColor:
                      _onlyUnreadWorks ? Colors.white : AppTheme.graphite,
                ),
                icon: Badge(
                  isLabelVisible: _unreadThreadCount > 0,
                  label: Text('$_unreadThreadCount'),
                  child: const Icon(Icons.mark_email_unread_outlined, size: 18),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _chatSectionTabs() {
    final sections = <_ChatSection>[
      _ChatSection.personal,
      _ChatSection.teams,
      _ChatSection.works,
      if (widget.showOrganizationService) _ChatSection.service,
    ];
    return Row(
      children: sections.map((section) {
        final selected = section == _chatSection;
        final label = switch (section) {
          _ChatSection.personal => 'Личные',
          _ChatSection.teams => 'Команды',
          _ChatSection.works => 'Работы',
          _ChatSection.service => 'Служебные',
        };
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: section == sections.last ? 0 : 4,
            ),
            child: Material(
              color: selected ? const Color(0xFFDDEFF0) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: selected ? AppTheme.blue : AppTheme.line,
                ),
              ),
              child: InkWell(
                key: ValueKey('chat-section-${section.name}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => _setChatSection(section),
                child: SizedBox(
                  height: 30,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600,
                            color:
                                selected ? AppTheme.blueDark : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _chatFilterChip({
    required _ChatListFilter filter,
    required String label,
    required int count,
    required Key key,
  }) {
    final selected = _chatSearchQuery.isEmpty && _chatListFilter == filter;
    return Material(
      key: key,
      color: selected ? const Color(0xFFDDEFF0) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppTheme.blue : AppTheme.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _setChatFilter(filter),
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$label · $count',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppTheme.blueDark : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyChatList({bool compact = false}) {
    final text = _chatSearchQuery.isNotEmpty
        ? 'Ничего не найдено'
        : switch (_chatSection) {
            _ChatSection.personal => 'Личных диалогов пока нет',
            _ChatSection.service => 'Служебных событий пока нет',
            _ChatSection.teams || _ChatSection.works => switch (
                  _chatListFilter) {
                _ChatListFilter.active => _chatSection == _ChatSection.teams
                    ? 'Нет активных команд'
                    : 'Нет активных работ',
                _ChatListFilter.unread => 'Нет непрочитанных',
                _ChatListFilter.archive => 'Архив пуст',
              },
          };
    return Center(
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 4 : 20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.black45),
        ),
      ),
    );
  }

  Widget _filteredChatsEmptyState() {
    final searching = _chatSearchQuery.isNotEmpty;
    return ColoredBox(
      color: AppTheme.appBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                searching ? Icons.search_off : Icons.mark_chat_read_outlined,
                size: 38,
                color: AppTheme.blue,
              ),
              const SizedBox(height: 10),
              Text(
                searching
                    ? switch (_chatSection) {
                        _ChatSection.personal =>
                          'Человек или диалог не найдены',
                        _ChatSection.teams => 'Команда не найдена',
                        _ChatSection.works => 'Работа или заказчик не найдены',
                        _ChatSection.service => 'Событие не найдено',
                      }
                    : switch (_chatListFilter) {
                        _ChatListFilter.active => 'Нет активных чатов',
                        _ChatListFilter.unread => 'Все сообщения прочитаны',
                        _ChatListFilter.archive => 'Архив пока пуст',
                      },
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                searching
                    ? switch (_chatSection) {
                        _ChatSection.personal =>
                          'Ищем по имени или нику среди доступных людей.',
                        _ChatSection.teams =>
                          'Поиск по названию команды, включая архив.',
                        _ChatSection.works =>
                          'Поиск по коду работы или заказчику, включая архив.',
                        _ChatSection.service => 'Поиск по служебным событиям.',
                      }
                    : 'Выберите другой раздел списка.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ]),
          ),
        ),
      ),
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
              colors: [Color(0xFF90C9CC), AppTheme.blue],
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

  Widget _contactTile(ChatContact contact) {
    return InkWell(
      key: ValueKey('chat-contact-${contact.userId}'),
      onTap: _contactsLoading ? null : () => _openDirectChat(contact),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          _avatar(contact.label, const Color(0xFF16A34A), size: 38),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  contact.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
          const Icon(Icons.chat_bubble_outline, size: 17),
        ]),
      ),
    );
  }

  Widget _workChatTile(_WorkThreadGroup group) {
    final selected = group.channels.any((entry) => entry.index == _activeChat);
    final primary = group.channels.first;
    return Material(
      key: ValueKey('work-chat-group-${group.jobId}'),
      color: selected ? AppTheme.surface : const Color(0xFFF0F4F5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppTheme.blue : AppTheme.line),
      ),
      child: InkWell(
        key: ValueKey('open-work-chat-${group.jobId}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectChat(primary.index),
        child: Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
          child: Row(children: [
            _avatar(group.title, const Color(0xFF0EA5A4), size: 36),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    (group.customerName ?? '').isEmpty
                        ? group.statusLabel
                        : '${group.statusLabel} · ${group.customerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 9.5, color: Colors.black54),
                  ),
                ],
              ),
            ),
            if (group.unreadCount > 0) ...[
              _unread(group.unreadCount),
              const SizedBox(width: 5),
            ],
            const Icon(
              Icons.chevron_right,
              size: 19,
              color: AppTheme.graphiteSoft,
            ),
          ]),
        ),
      ),
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
    final unread =
        serverThread == null ? chat!.unread : serverThread.unreadCount;
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
          color: active ? AppTheme.surface : const Color(0xFFF0F4F5),
          border: Border.all(
            color: active ? AppTheme.blue : AppTheme.line,
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
                if (serverThread?.kind == ChatThreadKind.team &&
                    serverThread!.canManage &&
                    widget.canManageTeams)
                  _teamMenu(serverThread),
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

  Widget _teamMenu(ChatThread thread) {
    return PopupMenuButton<String>(
      key: ValueKey('chat-team-menu-${thread.id}'),
      tooltip: 'Действия команды',
      padding: EdgeInsets.zero,
      iconSize: 18,
      onSelected: (value) {
        if (value == 'edit') _showTeamDialog(thread: thread);
        if (value == 'archive') _archiveTeam(thread);
        if (value == 'restore') _restoreTeam(thread);
      },
      itemBuilder: (_) => thread.isArchivedTeam
          ? const [
              PopupMenuItem(value: 'restore', child: Text('Восстановить')),
            ]
          : const [
              PopupMenuItem(value: 'edit', child: Text('Изменить')),
              PopupMenuItem(value: 'archive', child: Text('Удалить в архив')),
            ],
    );
  }

  String _serverThreadSubtitle(ChatThread thread) {
    switch (thread.kind) {
      case ChatThreadKind.organization:
        return 'общий чат команды';
      case ChatThreadKind.team:
        return thread.isArchivedTeam ? 'команда в архиве' : 'рабочая команда';
      case ChatThreadKind.jobCustomer:
        final customer = thread.customerName.trim();
        final prefix = thread.isArchivedJob ? 'архив' : 'работа';
        return customer.isEmpty
            ? '$prefix · канал заказчика'
            : '$prefix · $customer · заказчик';
      case ChatThreadKind.jobInternal:
        final customer = thread.customerName.trim();
        return customer.isEmpty
            ? 'внутреннее производство'
            : 'внутреннее производство · $customer';
      case ChatThreadKind.direct:
        return 'личный диалог';
      case ChatThreadKind.service:
        return 'служебный чат организации';
      case ChatThreadKind.personal:
        return 'видно только вам';
    }
  }

  Color _serverThreadColor(ChatThreadKind kind) {
    switch (kind) {
      case ChatThreadKind.organization:
        return AppTheme.blue;
      case ChatThreadKind.team:
        return const Color(0xFF657B83);
      case ChatThreadKind.jobCustomer:
        return const Color(0xFF0EA5A4);
      case ChatThreadKind.jobInternal:
        return const Color(0xFF536C78);
      case ChatThreadKind.direct:
        return const Color(0xFF16A34A);
      case ChatThreadKind.service:
        return const Color(0xFFC2410C);
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
      color: AppTheme.appBackground,
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
    final workGroup = _activeWorkGroup;
    return Container(
      color: AppTheme.appBackground,
      child: Column(children: [
        _chatHeaderContent(
          title: workGroup?.title ?? thread.title,
          subtitle: workGroup == null
              ? _serverThreadSubtitle(thread)
              : (workGroup.customerName ?? '').isEmpty
                  ? 'чат работы'
                  : workGroup.customerName!,
          color: _serverThreadColor(thread.kind),
        ),
        if (workGroup != null) _customerAccessBar(thread),
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
        if (thread.isArchivedTeam)
          Container(
            key: const ValueKey('archived-team-chat-read-only'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceMuted,
              border: Border(top: BorderSide(color: AppTheme.line)),
            ),
            child: Text(
              'Команда в архиве · переписка сохранена',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
          )
        else
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
            shared ? 'Заказчик подключён' : 'Заказчик не подключён',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (widget.canManageCustomerChatAccess &&
            thread.canManageCustomerAccess)
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
              shared ? 'Отключить' : 'Подключить',
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
    final messageThread = _serverThreads
        .where((thread) => thread.id == message.threadId)
        .firstOrNull;
    final customerAudience = _activeWorkGroup != null &&
        messageThread?.kind == ChatThreadKind.jobCustomer &&
        _canChooseWorkAudience;
    return _ChatMessage(
      author: message.senderLabel,
      role: nickname.isEmpty ? 'участник' : '@$nickname',
      time: _shortDateTime(message.createdAt),
      text: message.text,
      isMine: message.senderId == widget.currentUserId,
      attachment: message.attachment,
      audienceLabel: customerAudience ? 'Заказчику' : null,
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
            if (message.audienceLabel != null) ...[
              const SizedBox(height: 5),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F7EE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Text(
                    message.audienceLabel!,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF137A45),
                    ),
                  ),
                ),
              ),
            ],
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
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.line),
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
            border: Border(top: BorderSide(color: AppTheme.line)),
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
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.line),
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
            border: Border(top: BorderSide(color: AppTheme.line)),
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
    final attachmentTarget = _workMessageTarget;
    final showAttachmentButton = !_usesServerChat ||
        (attachmentTarget?.organizationId != null &&
            attachmentTarget!.kind != ChatThreadKind.personal);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_canChooseWorkAudience) ...[
          Row(children: [
            const Text(
              'Кому:',
              style: TextStyle(fontSize: 10, color: Colors.black54),
            ),
            const SizedBox(width: 7),
            _workAudienceChoice(
              customer: false,
              label: 'Внутри команды',
              icon: Icons.groups_2_outlined,
            ),
            const SizedBox(width: 5),
            _workAudienceChoice(
              customer: true,
              label: 'Заказчику',
              icon: Icons.handshake_outlined,
            ),
          ]),
          const SizedBox(height: 7),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (showAttachmentButton) ...[
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
          ],
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
                    : _sendWorkMessageToCustomer && _canChooseWorkAudience
                        ? 'Сообщение заказчику'
                        : 'Сообщение',
                filled: true,
                fillColor: AppTheme.surfaceMuted,
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
      ]),
    );
  }

  Widget _workAudienceChoice({
    required bool customer,
    required String label,
    required IconData icon,
  }) {
    final selected = _sendWorkMessageToCustomer == customer;
    return Material(
      color: selected ? const Color(0xFFDDEFF0) : AppTheme.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: selected ? AppTheme.blue : AppTheme.line),
      ),
      child: InkWell(
        key: ValueKey(
          customer ? 'work-audience-customer' : 'work-audience-internal',
        ),
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _sendWorkMessageToCustomer = customer),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: AppTheme.blueDark),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showTeamDialog({ChatThread? thread}) async {
    final repository = widget.chatRepository;
    if (repository == null || _teamActionBusy) return;
    setState(() => _teamActionBusy = true);
    try {
      final contacts = (await repository.searchContacts('', limit: 100))
          .where((contact) => contact.canAddToTeam)
          .toList(growable: false);
      final existingMembers = thread == null
          ? const <ChatTeamMember>[]
          : await repository.listTeamMembers(thread.id);
      if (!mounted) return;
      final nameController = TextEditingController(text: thread?.title ?? '');
      final selected = existingMembers.map((member) => member.userId).toSet();
      String? validation;
      final draft = await showDialog<_TeamDraft>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(thread == null ? 'Новая команда' : 'Изменить команду'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  key: const ValueKey('chat-team-name'),
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Название'),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Участники',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 5),
                Flexible(
                  child: contacts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Нет доступных сотрудников.'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: contacts.length,
                          itemBuilder: (_, index) {
                            final contact = contacts[index];
                            return CheckboxListTile(
                              key: ValueKey(
                                  'chat-team-member-${contact.userId}'),
                              dense: true,
                              value: selected.contains(contact.userId),
                              title: Text(contact.label),
                              subtitle: Text(contact.subtitle),
                              onChanged: (value) => setDialogState(() {
                                if (value == true) {
                                  selected.add(contact.userId);
                                } else {
                                  selected.remove(contact.userId);
                                }
                                validation = null;
                              }),
                            );
                          },
                        ),
                ),
                if (validation != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      validation!,
                      style: const TextStyle(color: Color(0xFFA82820)),
                    ),
                  ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const ValueKey('save-chat-team'),
                onPressed: () {
                  if (nameController.text.trim().length < 2) {
                    setDialogState(
                      () => validation = 'Введите название команды.',
                    );
                    return;
                  }
                  if (selected.isEmpty) {
                    setDialogState(
                      () => validation = 'Выберите хотя бы одного участника.',
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    _TeamDraft(
                      name: nameController.text.trim(),
                      memberUserIds: selected.toList(growable: false),
                    ),
                  );
                },
                child: Text(thread == null ? 'Создать' : 'Сохранить'),
              ),
            ],
          ),
        ),
      );
      // The dialog still paints during its reverse transition. Keep the
      // controller alive until that route is fully gone.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      nameController.dispose();
      if (draft == null) return;
      final threadId = thread == null
          ? await repository.createTeam(
              name: draft.name,
              memberUserIds: draft.memberUserIds,
            )
          : thread.id;
      if (thread != null) {
        await repository.updateTeam(
          threadId: thread.id,
          name: draft.name,
          memberUserIds: draft.memberUserIds,
        );
      }
      await _refreshAndSelectThread(threadId, _ChatSection.teams);
    } catch (_) {
      if (mounted) {
        setState(() => _serverChatError =
            'Не удалось сохранить команду. Проверьте участников и повторите.');
      }
    } finally {
      if (mounted) setState(() => _teamActionBusy = false);
    }
  }

  Future<void> _archiveTeam(ChatThread thread) async {
    final repository = widget.chatRepository;
    if (repository == null || _teamActionBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Убрать команду в архив?'),
        content: Text(
          'Переписка «${thread.title}» сохранится и команду можно будет восстановить.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('В архив'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _teamActionBusy = true);
    try {
      await repository.archiveTeam(thread.id);
      await _refreshServerThreads();
      if (mounted) await _selectFirstVisibleChatIfNeeded();
    } catch (_) {
      if (mounted) {
        setState(() => _serverChatError = 'Не удалось архивировать команду.');
      }
    } finally {
      if (mounted) setState(() => _teamActionBusy = false);
    }
  }

  Future<void> _restoreTeam(ChatThread thread) async {
    final repository = widget.chatRepository;
    if (repository == null || _teamActionBusy) return;
    setState(() => _teamActionBusy = true);
    try {
      await repository.restoreTeam(thread.id);
      setState(() => _chatListFilter = _ChatListFilter.active);
      await _refreshAndSelectThread(thread.id, _ChatSection.teams);
    } catch (_) {
      if (mounted) {
        setState(() => _serverChatError = 'Не удалось восстановить команду.');
      }
    } finally {
      if (mounted) setState(() => _teamActionBusy = false);
    }
  }

  Future<void> _refreshAndSelectThread(
    String threadId,
    _ChatSection section,
  ) async {
    final repository = widget.chatRepository;
    if (repository == null) return;
    final threads = await repository.listThreads();
    if (!mounted) return;
    final index = threads.indexWhere((thread) => thread.id == threadId);
    setState(() {
      _serverThreads = threads;
      _chatSection = section;
      _chatListFilter = _ChatListFilter.active;
      _onlyUnreadWorks = false;
      _chatSearchQuery = '';
      _chatSearchCtrl.clear();
      if (index >= 0) _activeChat = index;
      _serverMessages = const [];
      _messagesByThread.clear();
      _sendWorkMessageToCustomer = false;
    });
    if (index >= 0) await _loadServerMessages();
  }

  Future<void> _showAttachmentMenu() {
    final target = _workMessageTarget;
    final technicalWork = target?.jobId != null &&
        (target?.kind == ChatThreadKind.jobInternal ||
            target?.kind == ChatThreadKind.jobCustomer) &&
        widget.canShareInspectionAssets;
    final canAttachFile = target?.organizationId != null &&
        target!.kind != ChatThreadKind.personal;
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
                  if (technicalWork) ...[
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
                      subtitle: 'облегчённое изображение проверки',
                      onTap: _openCloudPreview,
                    ),
                    _attachmentAction(
                      context: sheetContext,
                      icon: Icons.difference_outlined,
                      title: 'Карта отличий',
                      subtitle: 'цветовая карта выбранной проверки',
                      onTap: _openCloudPreview,
                    ),
                  ],
                  if (canAttachFile)
                    _attachmentAction(
                      context: sheetContext,
                      icon: Icons.attach_file,
                      title: 'Файл или изображение',
                      subtitle: 'доступно участникам этого чата',
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
    final thread = _workMessageTarget;
    if (repository == null || thread == null) {
      await xpDlg(
        context,
        'Файл или изображение',
        'Обычные вложения доступны в облачном чате работы.',
      );
      return;
    }
    try {
      final upload = await (widget.attachmentPicker ?? _pickAttachment)();
      if (upload == null || !mounted) return;
      if (upload.bytes.isEmpty) {
        throw const FormatException('empty_attachment');
      }
      setState(() => _sendingAttachment = true);
      final message = await repository.sendAttachment(
        threadId: thread.id,
        upload: upload,
        text: _msgCtrl.text,
      );
      if (!mounted ||
          !_activeMessageChannels.any(
            (entry) => entry.thread.id == thread.id,
          )) {
        return;
      }
      setState(() {
        final messages = List<ChatMessage>.of(
          _messagesByThread[thread.id] ?? const [],
        );
        if (!messages.any((item) => item.id == message.id)) {
          messages.add(message);
          _messagesByThread[thread.id] = messages;
          _serverMessages = _mergedMessages(_activeMessageChannels);
        }
        _msgCtrl.clear();
        _serverChatError = null;
      });
      _scrollMessagesToEnd();
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выбранный файл пустой и не может быть отправлен.'),
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
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
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
              ? 'Заказчик увидит $jobLabel и только сообщения, адресованные ему. Внутренняя переписка останется скрытой.'
              : 'Заказчик больше не увидит $jobLabel и его чат. Переписка сохранится.',
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
                ? 'Заказчик подключён к работе'
                : 'Заказчик отключён от работы',
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
          count > 99 ? '99+' : '$count',
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
          role: 'представитель заказчика',
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
      final thread = _workMessageTarget;
      if (repository == null || thread == null || _sendingMessage) return;
      setState(() => _sendingMessage = true);
      try {
        final message = await repository.sendText(
          threadId: thread.id,
          text: text,
        );
        if (!mounted ||
            !_activeMessageChannels.any(
              (entry) => entry.thread.id == thread.id,
            )) {
          return;
        }
        setState(() {
          final messages = List<ChatMessage>.of(
            _messagesByThread[thread.id] ?? const [],
          );
          if (!messages.any((item) => item.id == message.id)) {
            messages.add(message);
            _messagesByThread[thread.id] = messages;
            _serverMessages = _mergedMessages(_activeMessageChannels);
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
              ? 'представитель заказчика'
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

class _IndexedChatThread {
  final int index;
  final ChatThread thread;

  const _IndexedChatThread({
    required this.index,
    required this.thread,
  });
}

class _WorkThreadGroup {
  final String jobId;
  final List<_IndexedChatThread> channels;

  const _WorkThreadGroup({
    required this.jobId,
    required this.channels,
  });

  ChatThread get _mainThread {
    for (final channel in channels) {
      if (channel.thread.kind == ChatThreadKind.jobCustomer) {
        return channel.thread;
      }
    }
    return channels.first.thread;
  }

  String get title => _mainThread.title
      .replaceFirst(RegExp(r' · производство$'), '')
      .replaceFirst(RegExp(r' · заказчик$'), '');

  String? get customerName {
    for (final channel in channels) {
      final name = channel.thread.customerName.trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  String get jobFlowState {
    for (final channel in channels) {
      if (channel.thread.jobFlowState.isNotEmpty) {
        return channel.thread.jobFlowState;
      }
    }
    return '';
  }

  String get jobStage {
    for (final channel in channels) {
      if (channel.thread.jobStage.isNotEmpty) return channel.thread.jobStage;
    }
    return '';
  }

  DateTime? get updatedAt {
    DateTime? latest;
    for (final channel in channels) {
      final value = channel.thread.updatedAt;
      if (latest == null || value.isAfter(latest)) {
        latest = value;
      }
    }
    return latest;
  }

  int get unreadCount => channels.fold<int>(
        0,
        (total, channel) => total + channel.thread.unreadCount,
      );

  bool get isArchived => channels.every(
        (channel) => channel.thread.isArchivedJob,
      );

  String get statusLabel {
    if (isArchived) return 'выполнена';
    if (jobFlowState == 'blocked') return 'стоп';
    return 'в работе';
  }
}

class _TeamDraft {
  final String name;
  final List<String> memberUserIds;

  const _TeamDraft({
    required this.name,
    required this.memberUserIds,
  });
}

class _ChatMessage {
  final String author;
  final String role;
  final String time;
  final String text;
  final bool isMine;
  final String? audienceLabel;
  final _SharedCheckCard? card;
  final _ApprovalCard? approvalCard;
  final ChatAttachment? attachment;

  const _ChatMessage({
    required this.author,
    required this.role,
    required this.time,
    required this.text,
    required this.isMine,
    this.audienceLabel,
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
