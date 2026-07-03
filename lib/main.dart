import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'screens/start_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/shop_screen.dart';
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

  final List<Widget> _screens = const [
    CompareScreen(),
    ChatScreen(),
    ShopScreen(),
    SettingsScreen(),
  ];

  void _onTab(int i) {
    setState(() {
      _tab = i;
      if (i == 1) _chatBadge = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';

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
            child: IndexedStack(index: _tab, children: _screens),
          ),
        ]),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.silverGrad,
          border: const Border(
            top: BorderSide(color: AppTheme.blue, width: 2),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, -3)),
            BoxShadow(
                color: Colors.white.withOpacity(0.6),
                blurRadius: 2,
                offset: const Offset(0, -1)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              Expanded(child: _navBtn(0, '🔍', 'Сравнение')),
              _navBtnBadge(1, '💬', 'Чат', _chatBadge),
              Expanded(child: _navBtn(2, '🛒', 'Магазин')),
              Expanded(child: _navBtn(3, '⚙️', 'Настройки')),
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

  Widget _navBtn(int idx, String icon, String label) {
    final active = _tab == idx;
    return GestureDetector(
      onTap: () => _onTab(idx),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(colors: [
                  AppTheme.blue.withOpacity(0.18),
                  AppTheme.blue.withOpacity(0.04)
                ], begin: Alignment.topCenter, end: Alignment.bottomCenter)
              : null,
          border: Border(
            top: BorderSide(
                color: active ? AppTheme.blue : Colors.transparent, width: 3),
            right: idx < 3
                ? const BorderSide(color: AppTheme.silverDark)
                : BorderSide.none,
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: active ? AppTheme.blue : Colors.black54)),
        ]),
      ),
    );
  }

  Widget _navBtnBadge(int idx, String icon, String label, int badge) {
    return Expanded(
      child: Stack(children: [
        SizedBox.expand(child: _navBtn(idx, icon, label)),
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
