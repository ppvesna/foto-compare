import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/local_access_testing_service.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/start_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/invitation_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'features/billing/billing.dart';
import 'features/organization/organization.dart';
import 'features/protocols/protocols.dart';
import 'services/sync_service.dart';
import 'widgets/xp_widgets.dart';

String? _startupAuthError;

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
  final uri = Uri.base;
  final fragment = uri.fragment;
  final isCallback = fragment.contains('access_token=') ||
      fragment.contains('error_description=');
  if (!isCallback || Supabase.instance.client.auth.currentSession != null) {
    return;
  }
  try {
    await Supabase.instance.client.auth.getSessionFromUrl(uri);
  } catch (error) {
    _startupAuthError = error.toString();
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
  @override
  void initState() {
    super.initState();
    // Слушаем изменения авторизации
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
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

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null && _startupAuthError != null) {
      return _AuthLinkError(error: _startupAuthError!);
    }
    if (session != null) {
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

  const _AuthLinkError({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FC),
      body: Center(
        child: Container(
          width: 480,
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFC9E2F0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ссылка приглашения не сработала',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ссылка могла устареть или уже использоваться. '
                'Попросите владельца повторно отправить приглашение.',
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 12),
                SelectableText(
                  error,
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ],
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
  int _chatBadge = 4;
  int _settingsAccessRequest = 0;
  EntitlementSnapshot _entitlements = EntitlementSnapshot.legacyCompatible();
  OrganizationAccess _organizationAccess = OrganizationAccess.legacyPersonal();
  String? _handledInvitationId;

  @override
  void initState() {
    super.initState();
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
    final organizationService =
        SupabaseOrganizationAdministrationService(client);
    final pendingInvitation = await organizationService.currentInvitation();
    var entitlements = await SupabaseEntitlementService(client).load();
    var organizationAccess =
        await SupabaseOrganizationAccessService(client).load();
    if (kDebugMode) {
      final testOverride = await const LocalAccessTestingService().load();
      if (testOverride.enabled) {
        entitlements = EntitlementSnapshot.forPlan(testOverride.plan);
        organizationAccess = OrganizationAccess.forRole(
          organizationId: organizationAccess.organizationId,
          organizationName: organizationAccess.organizationName,
          role: testOverride.role,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _entitlements = entitlements;
      _organizationAccess = organizationAccess;
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
      _tab = i;
      if (i == 2) _chatBadge = 0;
    });
  }

  void _openAccessSettings() {
    setState(() {
      _settingsAccessRequest++;
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

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final metadata = user?.userMetadata ?? {};
    final displayName = (metadata['display_name'] as String?)?.trim() ?? '';
    final nickname = (metadata['nickname'] as String?)?.trim() ?? '';
    final profileOrganizationName =
        (metadata['organization_name'] as String?)?.trim() ?? '';
    final organizationName =
        _organizationAccess.organizationName ?? profileOrganizationName;
    final userLabel = nickname.isNotEmpty
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
      CompareScreen(
        entitlements: _entitlements,
        organizationAccess: _organizationAccess,
      ),
      ChatScreen(
        email: email,
        displayName: displayName,
        nickname: nickname,
        organizationName: organizationName,
      ),
      SettingsScreen(
        key: ValueKey('settings-access-$_settingsAccessRequest'),
        entitlements: _entitlements,
        organizationAccess: _organizationAccess,
        onAccessChanged: _loadAccess,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            color: AppTheme.blueDark,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.account_circle,
                  size: 15,
                  color: Colors.white70,
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
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _organizationAccess.role.label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
                        color: Colors.white70,
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFE7F4FB),
          border: Border(
            top: BorderSide(color: AppTheme.blue, width: 2),
          ),
          boxShadow: [
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, -3)),
            BoxShadow(
                color: Color(0x99FFFFFF), blurRadius: 2, offset: Offset(0, -1)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(children: [
              Expanded(child: _navBtn(0, 'Главная')),
              Expanded(child: _navBtn(1, 'Сравнение')),
              _navBtnBadge(2, 'Чат', _chatBadge),
              Expanded(child: _navBtn(3, 'Настройки')),
            ]),
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

  Widget _navBtn(int idx, String label) {
    final active = _tab == idx;
    return GestureDetector(
      onTap: () => _onTab(idx),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? const [
                    Color(0xFFC8F0FF),
                    Color(0xFF5BC2F2),
                    Color(0xFF258FCD)
                  ]
                : const [
                    Color(0xFFFFFFFF),
                    Color(0xFFBDE7FA),
                    Color(0xFF6DBCE5)
                  ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? const Color(0xFF137FBC) : const Color(0xFF6CB9DE),
            width: active ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x44000000), blurRadius: 7, offset: Offset(0, 3)),
            BoxShadow(
                color: Color(0xAAFFFFFF), blurRadius: 2, offset: Offset(0, -1)),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: active ? 13 : 12,
              fontWeight: FontWeight.w800,
              color: active ? Colors.white : const Color(0xFF114765),
              shadows: active
                  ? const [
                      Shadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 1),
                          blurRadius: 1)
                    ]
                  : const [
                      Shadow(
                          color: Color(0x99FFFFFF),
                          offset: Offset(0, 1),
                          blurRadius: 1)
                    ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navBtnBadge(int idx, String label, int badge) {
    return Expanded(
      child: Stack(children: [
        SizedBox.expand(child: _navBtn(idx, label)),
        if (badge > 0)
          Positioned(
            top: 6,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(8)),
              child: Text('$badge',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }
}
