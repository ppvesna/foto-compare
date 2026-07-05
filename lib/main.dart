import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/start_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'services/check_history_service.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CheckHistoryService.load();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const PhotoCompareApp());
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
    if (session != null) {
      return const MainShell();
    }
    return const StartScreen();
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

  void _onTab(int i) {
    setState(() {
      _tab = i;
      if (i == 2) _chatBadge = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final metadata = user?.userMetadata ?? {};
    final displayName = (metadata['display_name'] as String?)?.trim() ?? '';
    final nickname = (metadata['nickname'] as String?)?.trim() ?? '';
    final organizationName =
        (metadata['organization_name'] as String?)?.trim() ?? '';
    final screens = [
      HomeScreen(
        email: email,
        displayName: displayName,
        nickname: nickname,
        organizationName: organizationName,
        onOpenSettings: () => _onTab(3),
        onSignOut: _signOut,
      ),
      const CompareScreen(),
      ChatScreen(
        email: email,
        displayName: displayName,
        nickname: nickname,
        organizationName: organizationName,
      ),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Полоска с email пользователя
          Container(
            color: AppTheme.blueDark,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(children: [
              const Icon(Icons.account_circle, size: 13, color: Colors.white54),
              const SizedBox(width: 5),
              Expanded(
                  child: Text(email,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white70))),
              GestureDetector(
                onTap: _signOut,
                child: const Text('Выйти',
                    style: TextStyle(fontSize: 10, color: Colors.white54)),
              ),
            ]),
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
