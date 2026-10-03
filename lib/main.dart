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
import 'screens/home_screen.dart';
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
    return const StartScreen();
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

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  int _settingsAccessRequest = 0;
  int _settingsInitialSection = 1;
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
      if (i == 1) _showComparison = false;
      _tab = i;
    });
  }

  void _openWorkComparison(ProductionComparisonTarget target) {
    setState(() {
      _comparisonWork = target.work;
      _comparisonUnit = target.unit;
      _showComparison = true;
      _tab = 1;
    });
  }

  void _backToWorks() {
    setState(() => _showComparison = false);
  }

  void _openWorkChat(ProductionChatTarget target) {
    setState(() {
      _requestedChatJobId = target.work.jobId;
      _requestedChatKind = target.channel == ProductionChatChannel.internal
          ? ChatThreadKind.jobInternal
          : ChatThreadKind.jobCustomer;
      _tab = 2;
    });
  }

  void _openAccessSettings() {
    setState(() {
      _settingsAccessRequest++;
      _settingsInitialSection = 2;
      _tab = 3;
    });
  }

  String _workspaceScopeLabel() {
    switch (_organizationAccess.role) {
      case OrganizationRole.owner:
      case OrganizationRole.admin:
        return 'Все работы';
      case OrganizationRole.employee:
        return 'Назначенные работы';
      case OrganizationRole.customer:
        return 'Свои работы';
      case OrganizationRole.personal:
        return 'Личные работы';
    }
  }

  List<String> _workspaceCapabilityLabels() {
    final access = _organizationAccess;
    final labels = <String>[_workspaceScopeLabel()];
    if (access.allows(OrganizationPermission.runInspection) &&
        _entitlements.allows(ProductCapability.runInspection)) {
      labels.add('Проверки');
    }
    if (access.allows(OrganizationPermission.manageReferences)) {
      labels.add('Эталоны');
    }
    if (access.allows(OrganizationPermission.viewProtocols)) {
      labels.add('Протоколы');
    }
    if (access.allows(OrganizationPermission.addComments) &&
        _entitlements.allows(ProductCapability.collaboration)) {
      labels.add('Чат');
    }
    if (access.allows(OrganizationPermission.manageMembers)) {
      labels.add('Участники');
    }
    if (access.allows(OrganizationPermission.manageBilling)) {
      labels.add('Тариф');
    }
    return labels;
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
    final capabilities = _workspaceCapabilityLabels().join(' · ');
    final screens = [
      HomeScreen(
        email: email,
        displayName: displayName,
        nickname: nickname,
        organizationName: organizationName,
        entitlements: _entitlements,
        organizationAccess: _organizationAccess,
        onOpenSettings: _openAccessSettings,
        onSignOut: _signOut,
      ),
      if (_showComparison && _comparisonWork != null)
        CompareScreen(
          key: ValueKey('comparison-${_comparisonWork!.jobId}'),
          entitlements: _entitlements,
          organizationAccess: _organizationAccess,
          initialJob: ProductionJobContext(
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
          onCheckUsageChanged: () {
            if (mounted) setState(() => _checkUsageRevision++);
          },
        )
      else
        WorksScreen(
          organizationId: _organizationAccess.organizationId,
          organizationAccess: _organizationAccess,
          workflowService: _workflowService,
          customerDirectoryService: SupabaseCustomerDirectoryService(
            Supabase.instance.client,
          ),
          productionJobService: SupabaseProductionJobService(
            Supabase.instance.client,
          ),
          onOpenComparison: _openWorkComparison,
          onOpenChat: _openWorkChat,
        ),
      ChatScreen(
        currentUserId: user?.id ?? '',
        email: email,
        displayName: displayName,
        nickname: nickname,
        organizationName: organizationName,
        initialJobId: _requestedChatJobId,
        initialThreadKind: _requestedChatKind,
        canManageTeams: _organizationAccess.role == OrganizationRole.admin,
        protocolCloudRepository: _protocolCloudRepository,
        chatRepository: _chatRepository,
      ),
      SettingsScreen(
        key: ValueKey('settings-access-$_settingsAccessRequest'),
        entitlements: _entitlements,
        organizationAccess: _organizationAccess,
        initialSection: _settingsInitialSection,
        cloudStorage: _cloudStorage,
        printConditionService: SupabasePrintConditionService(
          Supabase.instance.client,
        ),
        checkUsageService: _checkUsageService,
        checkUsageRevision: _checkUsageRevision,
        onAccessChanged: _loadAccess,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                bottom: BorderSide(color: AppTheme.line),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x160E2A31),
                  blurRadius: 7,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle,
                  size: 15,
                  color: AppTheme.blue,
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 2,
                  child: Text(
                    userLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.graphite,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: Text(
                    _organizationAccess.role.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.graphiteSoft,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  key: const ValueKey('top-plan-status'),
                  constraints: const BoxConstraints(maxWidth: 170),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _entitlements.usesFallbackPlan
                        ? const Color(0xFFFFE4B8)
                        : const Color(0xFFD7E9EA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _entitlements.usesFallbackPlan
                          ? const Color(0xFFE2A247)
                          : const Color(0xFF9BC8CB),
                    ),
                  ),
                  child: Text(
                    _topPlanLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _entitlements.usesFallbackPlan
                          ? const Color(0xFF8A4B00)
                          : const Color(0xFF195F64),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: Tooltip(
                    message: capabilities,
                    child: Text(
                      capabilities,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF708087),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(index: _tab, children: screens),
          ),
        ]),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.line)),
          boxShadow: [
            BoxShadow(
              color: Color(0x160E2A31),
              blurRadius: 7,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: Center(
            heightFactor: 1,
            child: Row(
              children: [
                _navBtn(0, 'Главная', Icons.home_outlined),
                _navBtn(1, 'Работа', Icons.work_outline_rounded),
                _navBtn(2, 'Чат', Icons.chat_bubble_outline),
                _navBtn(3, 'Настройки', Icons.tune_outlined),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Выйти?'),
        content: const Text('Вы будете отключены от аккаунта.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  Widget _navBtn(int idx, String label, IconData icon) {
    final active = _tab == idx;
    return Expanded(
      child: SizedBox(
        height: 36,
        child: InkWell(
          onTap: () => _onTab(idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? const Color(0xFF238C94) : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color:
                      active ? const Color(0xFF1F747A) : AppTheme.graphiteSoft,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.8,
                    height: 1.05,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active
                        ? const Color(0xFF195F64)
                        : AppTheme.graphiteSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
