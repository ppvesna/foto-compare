import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'capabilities/storage/storage.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/start_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/invitation_setup_screen.dart';
import 'screens/password_recovery_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/works_screen.dart';
import 'features/auth/auth.dart';
import 'features/billing/billing.dart';
import 'features/chat/chat.dart';
import 'features/organization/organization.dart';
import 'features/print_proofing/print_proofing.dart';
import 'features/protocols/protocols.dart';
import 'features/production/production.dart';
import 'services/sync_service.dart';
import 'services/browser_auth_url.dart';
import 'widgets/auth_page_backdrop.dart';
import 'widgets/workspace_photo_background.dart';
import 'widgets/xp_widgets.dart';

String? _startupAuthError;
bool _startupPasswordRecovery = false;
const _passwordRecoveryPendingKey = 'password_recovery_pending';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CheckHistoryService.load();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // Organization invitations are issued by the server and may be opened
      // in another browser, so there is no client-side PKCE verifier.
      authFlowType: AuthFlowType.implicit,
      detectSessionInUri: !kIsWeb,
    ),
  );
  await _recoverWebAuthCallback();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const PhotoCompareApp());
}

Future<void> _recoverWebAuthCallback() async {
  if (!kIsWeb) return;
  final preferences = await SharedPreferences.getInstance();
  final uri = Uri.base;
  final fragment = uri.fragment;
  final isRecovery = isPasswordRecoveryCallback(uri);
  if (isRecovery) {
    _startupPasswordRecovery = true;
    await preferences.setBool(_passwordRecoveryPendingKey, true);
  } else if (Supabase.instance.client.auth.currentSession != null &&
      (preferences.getBool(_passwordRecoveryPendingKey) ?? false)) {
    _startupPasswordRecovery = true;
  } else if (Supabase.instance.client.auth.currentSession == null) {
    await preferences.remove(_passwordRecoveryPendingKey);
  }
  final isCallback = fragment.contains('access_token=') ||
      fragment.contains('error_description=');
  if (!isCallback ||
      (Supabase.instance.client.auth.currentSession != null && !isRecovery)) {
    return;
  }
  try {
    final response = await Supabase.instance.client.auth.getSessionFromUrl(uri);
    if (response.redirectType == 'recovery') {
      _startupPasswordRecovery = true;
    }
  } catch (error) {
    _startupAuthError = error.toString();
    _startupPasswordRecovery = false;
    await preferences.remove(_passwordRecoveryPendingKey);
  }
}

class PhotoCompareApp extends StatelessWidget {
  const PhotoCompareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photo Compare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AuthGate(),
    );
  }
}

// Проверяет сессию и показывает нужный экран
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late bool _passwordRecovery;
  bool _guestMode = false;

  @override
  void initState() {
    super.initState();
    _passwordRecovery = _startupPasswordRecovery;
    // Слушаем изменения авторизации
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecovery = true;
        _startupPasswordRecovery = true;
      }
      if (mounted) setState(() {});
      // Запускаем/останавливаем синхронизацию при входе/выходе
      if (data.session != null) {
        SyncService().start();
      } else {
        SyncService().stop();
      }
    });
    // Если уже авторизован при запуске
    if (Supabase.instance.client.auth.currentSession != null) {
      SyncService().start();
    }
  }

  Future<void> _finishPasswordRecovery() async {
    _passwordRecovery = false;
    _startupPasswordRecovery = false;
    _startupAuthError = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_passwordRecoveryPendingKey);
    clearAuthCallbackUrl();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    if (mounted) setState(() {});
  }

  Future<void> _dismissAuthLinkError() async {
    _startupAuthError = null;
    _startupPasswordRecovery = false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_passwordRecoveryPendingKey);
    clearAuthCallbackUrl();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null && _startupAuthError != null) {
      return _AuthLinkError(
        error: _startupAuthError!,
        onReturnToLogin: _dismissAuthLinkError,
      );
    }
    if (session != null) {
      if (_passwordRecovery) {
        return PasswordRecoveryScreen(
          service: SupabasePasswordRecoveryService(
            Supabase.instance.client,
          ),
          onCompleted: _finishPasswordRecovery,
        );
      }
      final setupFlag = Supabase.instance.client.auth.currentUser
          ?.userMetadata?['organization_invite_setup'];
      if (setupFlag == true || setupFlag == 'true') {
        return InvitationSetupScreen(
          onCompleted: () {
            if (mounted) setState(() {});
          },
        );
      }
      return const MainShell();
    }
    if (_guestMode) {
      return GuestComparisonShell(
        onExit: () => setState(() => _guestMode = false),
      );
    }
    return StartScreen(
      onStartGuest: () => setState(() => _guestMode = true),
    );
  }
}

class GuestComparisonShell extends StatefulWidget {
  final VoidCallback onExit;

  const GuestComparisonShell({
    super.key,
    required this.onExit,
  });

  @override
  State<GuestComparisonShell> createState() => _GuestComparisonShellState();
}

class _GuestComparisonShellState extends State<GuestComparisonShell> {
  bool _settingsOpen = false;

  @override
  Widget build(BuildContext context) {
    final entitlements = EntitlementSnapshot.forPlan(PlanTier.free);
    final access = OrganizationAccess.legacyPersonal();
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth =
                (constraints.maxWidth - 24).clamp(280.0, 520.0).toDouble();
            return Stack(
              children: [
                Positioned.fill(
                  child: CompareScreen(
                    entitlements: entitlements,
                    organizationAccess: access,
                    onBackToWorks: widget.onExit,
                    backTooltip: 'На стартовый экран',
                    canOpenChat: false,
                    showStoredHistory: false,
                    onNavigate: (index) {
                      if (index == 3) {
                        setState(() => _settingsOpen = true);
                      } else if (index == 0 || index == 1) {
                        widget.onExit();
                      }
                    },
                  ),
                ),
                if (_settingsOpen)
                  Positioned(
                    top: 12,
                    right: 12,
                    bottom: 12,
                    width: panelWidth,
                    child: _WorkspaceSidePanel(
                      title: 'Настройки',
                      onClose: () => setState(() => _settingsOpen = false),
                      child: SettingsScreen(
                        entitlements: entitlements,
                        organizationAccess: access,
                        initialSection: 4,
                        onAccessChanged: () async {},
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AuthLinkError extends StatelessWidget {
  final String error;
  final Future<void> Function() onReturnToLogin;

  const _AuthLinkError({
    required this.error,
    required this.onReturnToLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: AuthPageBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: 460,
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0x55FFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 42,
                      offset: Offset(0, 24),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: AuthBrandMark(light: false),
                    ),
                    const SizedBox(height: 20),
                    const Icon(
                      Icons.link_off_rounded,
                      size: 48,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Ссылка не сработала',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      'Ссылка могла устареть или уже использоваться. '
                      'Вернитесь ко входу и запросите новое письмо или приглашение.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SelectableText(
                          error,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: onReturnToLogin,
                        icon: const Icon(Icons.arrow_back_rounded, size: 19),
                        label: const Text('Вернуться ко входу'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

enum _WorkspaceSidePanelKind { chat, settings }

class _MainShellState extends State<MainShell> {
  _WorkspaceSidePanelKind? _sidePanel;
  final int _settingsAccessRequest = 0;
  final int _settingsInitialSection = 1;
  EntitlementSnapshot _entitlements = EntitlementSnapshot.legacyCompatible();
  OrganizationAccess _organizationAccess = OrganizationAccess.legacyPersonal();
  AccountProfile? _accountProfile;
  bool _accountProfileResolved = false;
  CloudStorage? _cloudStorage;
  ProtocolCloudRepository? _protocolCloudRepository;
  ChatRepository? _chatRepository;
  CheckUsageService? _checkUsageService;
  late final ProductionWorkflowService _workflowService;
  ProductionWorkSummary? _comparisonWork;
  ProductionWorkUnit? _comparisonUnit;
  bool _showComparison = false;
  ProductionWorkView? _workRegisterView;
  bool _openCreateWorkOnMount = false;
  int _workRegisterRevision = 0;
  String? _requestedChatJobId;
  ChatThreadKind? _requestedChatKind;
  int _checkUsageRevision = 0;
  String? _handledInvitationId;

  @override
  void initState() {
    super.initState();
    _workflowService = SupabaseProductionWorkflowService(
      Supabase.instance.client,
    );
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      try {
        await client.auth.refreshSession();
      } catch (_) {
        // Keep cached access available when the session cannot refresh offline.
      }
    }
    await _ensureCurrentUserProfile(client);
    AccountProfile? accountProfile;
    try {
      accountProfile =
          await SupabaseAccountProfileService(client).loadCurrentProfile();
    } catch (_) {
      // Auth metadata remains a compatibility fallback during staged rollout.
    }
    final organizationService =
        SupabaseOrganizationAdministrationService(client);
    final pendingInvitation = await organizationService.currentInvitation();
    final entitlements = await SupabaseEntitlementService(client).load();
    final organizationAccess =
        await SupabaseOrganizationAccessService(client).load();
    if (!mounted) return;
    final currentUser = client.auth.currentUser;
    final cloudStorage = currentUser == null
        ? null
        : SupabaseCloudStorage(
            client,
            ownerUserId: currentUser.id,
          );
    setState(() {
      _entitlements = entitlements;
      _organizationAccess = organizationAccess;
      _accountProfile = accountProfile;
      _accountProfileResolved = true;
      _cloudStorage = cloudStorage;
      _protocolCloudRepository = currentUser == null || cloudStorage == null
          ? null
          : SupabaseProtocolCloudRepository(
              client,
              storage: cloudStorage,
              ownerUserId: currentUser.id,
              organizationId: organizationAccess.organizationId,
            );
      _chatRepository = currentUser == null
          ? null
          : SupabaseChatRepository(
              client,
              currentUserId: currentUser.id,
              storage: cloudStorage!,
            );
      _checkUsageService =
          currentUser == null ? null : SupabaseCheckUsageService(client);
    });
    _scheduleInvitationDialog(pendingInvitation, organizationService);
  }

  void _scheduleInvitationDialog(
    CurrentOrganizationInvitation? invitation,
    OrganizationAdministrationService service,
  ) {
    if (invitation == null || invitation.id == _handledInvitationId) return;
    _handledInvitationId = invitation.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final functions = invitation.functions.isEmpty
          ? ''
          : '\nФункции: ${invitation.functions.map((value) => value.label).join(', ')}';
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Приглашение в организацию'),
          content: Text(
            '${invitation.organizationName}\n'
            'Роль: ${invitation.role.label}$functions',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Принять'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      final applied = await service.acceptCurrentInvitation();
      if (!mounted) return;
      if (!applied) {
        xpDlg(
          context,
          'Приглашение',
          'Приглашение уже недоступно или срок действия закончился.',
        );
        return;
      }
      await _loadAccess();
    });
  }

  Future<void> _ensureCurrentUserProfile(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return;
    final metadata = user.userMetadata ?? {};
    final nickname = (metadata['nickname'] as String?)?.trim().toLowerCase();
    if (nickname == null || nickname.isEmpty) return;
    try {
      final profile = await client
          .from('user_profiles')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (profile != null) return;
      await client.from('user_profiles').insert({
        'user_id': user.id,
        'email': user.email!,
        'nickname': nickname,
        'display_name': (metadata['display_name'] as String?)?.trim() ?? '',
        'organization_name':
            (metadata['organization_name'] as String?)?.trim() ?? '',
      });
    } catch (_) {
      // Profile migration is optional during the staged rollout.
    }
  }

  void _onTab(int i) {
    if (i == 2 && !_entitlements.allows(ProductCapability.collaboration)) {
      xpDlg(
        context,
        'Нет доступа',
        'Чат и совместная работа не входят в текущий план.',
      );
      return;
    }
    setState(() {
      if (i == 0 || i == 1) {
        _showComparison = false;
        _sidePanel = null;
      } else if (i == 2) {
        _sidePanel = _sidePanel == _WorkspaceSidePanelKind.chat
            ? null
            : _WorkspaceSidePanelKind.chat;
      } else if (i == 3) {
        _sidePanel = _sidePanel == _WorkspaceSidePanelKind.settings
            ? null
            : _WorkspaceSidePanelKind.settings;
      }
    });
  }

  void _openWorkComparison(ProductionComparisonTarget target) {
    setState(() {
      _comparisonWork = target.work;
      _comparisonUnit = target.unit;
      _showComparison = true;
      _workRegisterView = null;
      _sidePanel = null;
    });
  }

  void _backToWorks() {
    setState(() => _showComparison = false);
  }

  void _startPersonalComparison() {
    setState(() {
      _comparisonWork = null;
      _comparisonUnit = null;
      _showComparison = true;
      _workRegisterView = null;
      _sidePanel = null;
    });
  }

  void _openWorkRegister(
    ProductionWorkView view, {
    bool createWork = false,
  }) {
    setState(() {
      _showComparison = false;
      _sidePanel = null;
      _workRegisterView = view;
      _openCreateWorkOnMount = createWork;
      _workRegisterRevision++;
    });
  }

  void _closeWorkRegister() {
    setState(() {
      _workRegisterView = null;
      _openCreateWorkOnMount = false;
    });
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  }

  void _openWorkChat(ProductionChatTarget target) {
    setState(() {
      _requestedChatJobId = target.work.jobId;
      _requestedChatKind = target.channel == ProductionChatChannel.internal
          ? ChatThreadKind.jobInternal
          : ChatThreadKind.jobCustomer;
      _sidePanel = _WorkspaceSidePanelKind.chat;
    });
  }

  String _topPlanLabel() {
    String shortDate(DateTime value) {
      final local = value.toLocal();
      String two(int number) => number.toString().padLeft(2, '0');
      return '${two(local.day)}.${two(local.month)}.${local.year}';
    }

    if (_entitlements.usesFallbackPlan) {
      return '${_entitlements.configuredPlan.label} истёк · '
          '${_entitlements.plan.label}';
    }
    final validUntil = _entitlements.validUntil;
    return validUntil == null
        ? _entitlements.plan.label
        : '${_entitlements.plan.label} · до ${shortDate(validUntil)}';
  }

  Widget _workspaceIdentity(String userLabel) {
    const textShadow = [
      Shadow(
        color: Color(0xE6000000),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ];
    return IgnorePointer(
      child: Row(
        children: [
          const Icon(
            Icons.account_circle,
            size: 16,
            color: Color(0xFF7ED7DB),
            shadows: textShadow,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              userLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF5F9FA),
                shadows: textShadow,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              _topPlanLabel(),
              key: const ValueKey('top-plan-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: _entitlements.usesFallbackPlan
                    ? const Color(0xFFFFC96F)
                    : const Color(0xFF9DE2E5),
                shadows: textShadow,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final metadata = user?.userMetadata ?? {};
    final displayName = !_accountProfileResolved
        ? 'Загрузка…'
        : _accountProfile?.displayName.trim() ??
            (metadata['display_name'] as String?)?.trim() ??
            '';
    final nickname = !_accountProfileResolved
        ? ''
        : _accountProfile?.nickname.trim() ??
            (metadata['nickname'] as String?)?.trim() ??
            '';
    final profileOrganizationName =
        (metadata['organization_name'] as String?)?.trim() ?? '';
    final organizationName =
        _organizationAccess.organizationName ?? profileOrganizationName;
    final userLabel = !_accountProfileResolved
        ? 'Загрузка…'
        : nickname.isNotEmpty
            ? nickname
            : displayName.isNotEmpty
                ? displayName
                : 'Пользователь';
    final organizationId = _organizationAccess.organizationId;
    final canUseChat = _entitlements.allows(ProductCapability.collaboration) &&
        _chatRepository != null;
    final canCreateOrganizationWork =
        _organizationAccess.role == OrganizationRole.employee &&
            _organizationAccess.functions.contains(
              OrganizationMemberFunction.inspectionSpecialist,
            );
    final central = _showComparison
        ? CompareScreen(
            key: ValueKey(
              'comparison-${_comparisonWork?.jobId ?? 'personal'}',
            ),
            entitlements: _entitlements,
            organizationAccess: _organizationAccess,
            initialJob: _comparisonWork == null
                ? null
                : ProductionJobContext(
                    jobId: _comparisonWork!.jobId,
                    jobNumber: _comparisonWork!.jobNumber,
                    customerId: _comparisonWork!.customerId,
                    customerName: _comparisonWork!.customerName,
                    customerConfirmed: _comparisonWork!.customerId != null,
                  ),
            onBackToWorks: _backToWorks,
            protocolCloudRepository: _protocolCloudRepository,
            checkUsageService: _checkUsageService,
            productionWorkflowService: _workflowService,
            inspectionUnit: _comparisonUnit,
            onNavigate: _onTab,
            canOpenChat: canUseChat,
            onCheckUsageChanged: () {
              if (mounted) setState(() => _checkUsageRevision++);
            },
          )
        : _organizationAccess.role == OrganizationRole.customer
            ? _CustomerWorkspace(
                onOpenChat: canUseChat
                    ? () => setState(
                          () => _sidePanel = _WorkspaceSidePanelKind.chat,
                        )
                    : null,
              )
            : organizationId == null
                ? _PersonalWorkspace(
                    onStartComparison: _startPersonalComparison,
                  )
                : _OrganizationWorkspace(
                    canCreateWork: canCreateOrganizationWork,
                    onCreateWork: () => _openWorkRegister(
                      ProductionWorkView.active,
                      createWork: true,
                    ),
                    onContinue: () => _openWorkRegister(
                      ProductionWorkView.active,
                    ),
                    onArchive: () => _openWorkRegister(
                      ProductionWorkView.archived,
                    ),
                  );

    Widget? sidePanel;
    if (_sidePanel == _WorkspaceSidePanelKind.chat) {
      sidePanel = ChatScreen(
        key: ValueKey(
          'workspace-chat-${_requestedChatJobId ?? 'all'}-'
          '${_requestedChatKind?.name ?? 'all'}',
        ),
        currentUserId: user?.id ?? '',
        email: email,
        displayName: displayName,
        nickname: nickname,
        organizationName: organizationName,
        initialJobId: _requestedChatJobId,
        initialThreadKind: _requestedChatKind,
        canManageTeams: false,
        canManageCustomerChatAccess:
            _organizationAccess.role == OrganizationRole.admin,
        showOrganizationService: organizationId != null &&
            _organizationAccess.role != OrganizationRole.customer &&
            _organizationAccess.role != OrganizationRole.personal,
        canShareInspectionAssets:
            _organizationAccess.role == OrganizationRole.owner ||
                _organizationAccess.role == OrganizationRole.admin ||
                _organizationAccess.functions.contains(
                  OrganizationMemberFunction.inspectionSpecialist,
                ),
        protocolCloudRepository: _protocolCloudRepository,
        chatRepository: _chatRepository,
      );
    } else if (_sidePanel == _WorkspaceSidePanelKind.settings) {
      sidePanel = SettingsScreen(
        key: ValueKey('settings-access-$_settingsAccessRequest'),
        entitlements: _entitlements,
        organizationAccess: _organizationAccess,
        initialSection: _settingsInitialSection,
        cloudStorage: _cloudStorage,
        printConditionService: SupabasePrintConditionService(
          Supabase.instance.client,
        ),
        chatRepository: _chatRepository,
        checkUsageService: _checkUsageService,
        checkUsageRevision: _checkUsageRevision,
        onAccessChanged: _loadAccess,
        onSignOut: _signOut,
      );
    }

    final workRegisterView = _workRegisterView;
    final workRegister = organizationId == null || workRegisterView == null
        ? null
        : WorksScreen(
            key: ValueKey(
              'work-register-${workRegisterView.name}-'
              '$_workRegisterRevision',
            ),
            organizationId: organizationId,
            currentUserId: user?.id ?? '',
            organizationAccess: _organizationAccess,
            workflowService: _workflowService,
            customerDirectoryService: SupabaseCustomerDirectoryService(
              Supabase.instance.client,
            ),
            productionJobService: SupabaseProductionJobService(
              Supabase.instance.client,
            ),
            initialView: workRegisterView,
            openCreateOnMount: _openCreateWorkOnMount,
            overlayMode: true,
            onClose: _closeWorkRegister,
            onOpenComparison: _openWorkComparison,
            onOpenChat: _openWorkChat,
          );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth =
                (constraints.maxWidth - 24).clamp(280.0, 620.0).toDouble();
            final overlayInset = constraints.maxWidth < 760 ? 10.0 : 28.0;
            return Stack(
              children: [
                Positioned.fill(child: central),
                if (!_showComparison && workRegister == null)
                  Positioned(
                    top: 10,
                    left: 12,
                    right: 112,
                    child: _workspaceIdentity(userLabel),
                  ),
                if (workRegister != null)
                  Positioned(
                    top: overlayInset,
                    left: overlayInset,
                    right: overlayInset,
                    bottom: overlayInset,
                    child: workRegister,
                  ),
                if (sidePanel == null &&
                    workRegister == null &&
                    !_showComparison)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _WorkspaceFloatingActions(
                      chatEnabled: canUseChat,
                      chatSelected: false,
                      settingsSelected: false,
                      onChat: canUseChat ? () => _onTab(2) : null,
                      onSettings: () => _onTab(3),
                    ),
                  ),
                if (sidePanel != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    bottom: 12,
                    width: panelWidth,
                    child: _WorkspaceSidePanel(
                      title: _sidePanel == _WorkspaceSidePanelKind.chat
                          ? 'Чат'
                          : 'Настройки',
                      onClose: () => setState(() => _sidePanel = null),
                      child: sidePanel,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceFloatingActions extends StatelessWidget {
  final bool chatEnabled;
  final bool chatSelected;
  final bool settingsSelected;
  final VoidCallback? onChat;
  final VoidCallback onSettings;

  const _WorkspaceFloatingActions({
    required this.chatEnabled,
    required this.chatSelected,
    required this.settingsSelected,
    required this.onChat,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    Widget action({
      required String tooltip,
      required IconData icon,
      required bool selected,
      required VoidCallback? onPressed,
      required Key key,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? const Color(0xF2D7E9EA) : const Color(0xEAF8FAFC),
          elevation: 6,
          shadowColor: const Color(0x55000000),
          shape: const CircleBorder(),
          child: IconButton(
            key: key,
            tooltip: tooltip,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              foregroundColor:
                  selected ? const Color(0xFF195F64) : AppTheme.graphiteSoft,
              disabledForegroundColor: const Color(0xFFB7C0C4),
            ),
            icon: Icon(icon, size: 21),
          ),
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('workspace-floating-actions'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(
            key: const ValueKey('workspace-chat'),
            tooltip: chatEnabled ? 'Чат' : 'Чат доступен после входа',
            icon: Icons.chat_bubble_outline_rounded,
            selected: chatSelected,
            onPressed: chatEnabled ? onChat : null,
          ),
          action(
            key: const ValueKey('workspace-settings'),
            tooltip: 'Настройки',
            icon: Icons.tune_rounded,
            selected: settingsSelected,
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSidePanel extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final Widget child;

  const _WorkspaceSidePanel({
    required this.title,
    required this.onClose,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 18,
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.only(left: 16, right: 6),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.graphite,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('close-workspace-side-panel'),
                  tooltip: 'Закрыть',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _OrganizationWorkspace extends StatelessWidget {
  final bool canCreateWork;
  final VoidCallback onCreateWork;
  final VoidCallback onContinue;
  final VoidCallback onArchive;

  const _OrganizationWorkspace({
    required this.canCreateWork,
    required this.onCreateWork,
    required this.onContinue,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return _WorkspaceLaunchSurface(
      title: 'Проверка образцов',
      subtitle: 'Выберите работу и продолжайте сравнение.',
      actions: [
        if (canCreateWork)
          FilledButton.icon(
            key: const ValueKey('workspace-create-work'),
            onPressed: onCreateWork,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Новая работа'),
          ),
        FilledButton.tonalIcon(
          key: const ValueKey('workspace-continue-work'),
          onPressed: onContinue,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Проверка'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('workspace-open-archive'),
          onPressed: onArchive,
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Архив'),
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xEAF8FAFC),
            foregroundColor: AppTheme.graphite,
            side: const BorderSide(color: Color(0xCCFFFFFF)),
          ),
        ),
      ],
    );
  }
}

class _PersonalWorkspace extends StatelessWidget {
  final VoidCallback onStartComparison;

  const _PersonalWorkspace({required this.onStartComparison});

  @override
  Widget build(BuildContext context) {
    return _WorkspaceLaunchSurface(
      title: 'Сравните эталон и образец',
      subtitle: 'Базовая проверка без номера работы и заказчика.',
      actions: [
        FilledButton.icon(
          key: const ValueKey('start-personal-comparison'),
          onPressed: onStartComparison,
          icon: const Icon(Icons.compare_rounded),
          label: const Text('Начать сравнение'),
        ),
      ],
    );
  }
}

class _WorkspaceLaunchSurface extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const _WorkspaceLaunchSurface({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: WorkspacePhotoBackground()),
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: Color(0xCC000000),
                          blurRadius: 18,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFF1F5F9),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Color(0xCC000000), blurRadius: 12),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: actions,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomerWorkspace extends StatelessWidget {
  final VoidCallback? onOpenChat;

  const _CustomerWorkspace({this.onOpenChat});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: WorkspacePhotoBackground()),
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 620),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xEAF8FAFC),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xAAFFFFFF)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.forum_outlined,
                      size: 42,
                      color: AppTheme.blue,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Связь с исполнителем',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.graphite,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Вам видны только те файлы и результаты, '
                      'которые команда отправила в чат.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.graphiteSoft,
                        height: 1.4,
                      ),
                    ),
                    if (onOpenChat != null) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        key: const ValueKey('customer-open-chat'),
                        onPressed: onOpenChat,
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Открыть чат'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
