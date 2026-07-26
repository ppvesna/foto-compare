import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_theme.dart';
import '../widgets/xp_widgets.dart';

class InvitationSetupScreen extends StatefulWidget {
  final VoidCallback onCompleted;

  const InvitationSetupScreen({
    super.key,
    required this.onCompleted,
  });

  @override
  State<InvitationSetupScreen> createState() => _InvitationSetupScreenState();
}

class _InvitationSetupScreenState extends State<InvitationSetupScreen> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _displayNameController;
  final _passwordController = TextEditingController();
  final _passwordConfirmationController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final metadata =
        Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
    _nicknameController = TextEditingController(
      text: (metadata['nickname'] as String?) ?? '',
    );
    _displayNameController = TextEditingController(
      text: (metadata['display_name'] as String?) ?? '',
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _passwordConfirmationController.dispose();
    super.dispose();
  }

  Future<void> _completeInvitation() async {
    final nickname = _nicknameController.text.trim().toLowerCase();
    final displayName = _displayNameController.text.trim();
    final password = _passwordController.text;
    if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(nickname)) {
      setState(() {
        _error = 'Ник: 3-24 символа, латиница, цифры и подчёркивание.';
      });
      return;
    }
    if (displayName.isEmpty) {
      setState(() => _error = 'Введите имя пользователя.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Пароль должен содержать минимум 8 символов.');
      return;
    }
    if (password != _passwordConfirmationController.text) {
      setState(() => _error = 'Пароли не совпадают.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        throw StateError('Сессия приглашения не найдена');
      }

      await client.auth.updateUser(UserAttributes(password: password));
      await client.from('user_profiles').upsert({
        'user_id': user.id,
        'email': email,
        'nickname': nickname,
        'display_name': displayName,
        'organization_name': '',
      });
      final invitation = await client.rpc(
        'accept_current_organization_invitation_v1',
      );
      if (invitation is! Map) {
        throw StateError('Активное приглашение не найдено');
      }
      final result = Map<String, dynamic>.from(invitation);
      await client.auth.updateUser(
        UserAttributes(
          data: {
            'nickname': nickname,
            'display_name': displayName,
            'organization_name': result['organization_name'] as String? ?? '',
            'organization_invite_setup': false,
          },
        ),
      );
      widget.onCompleted();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.toLowerCase().contains('nickname') ||
        text.toLowerCase().contains('duplicate')) {
      return 'Этот ник уже занят. Выберите другой.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFEAF6FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFC9E2F0)),
                borderRadius: BorderRadius.circular(8),
                boxShadow: AppTheme.shadowSubtle,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Завершение регистрации',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Для вас подготовлена роль в рабочем пространстве.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 18),
                  _valueRow('Email', email),
                  const SizedBox(height: 12),
                  XpInput(
                    placeholder: 'Ник пользователя',
                    controller: _nicknameController,
                  ),
                  const SizedBox(height: 10),
                  XpInput(
                    placeholder: 'Имя пользователя',
                    controller: _displayNameController,
                  ),
                  const SizedBox(height: 10),
                  XpInput(
                    placeholder: 'Новый пароль',
                    controller: _passwordController,
                    obscure: true,
                  ),
                  const SizedBox(height: 10),
                  XpInput(
                    placeholder: 'Повторите пароль',
                    controller: _passwordConfirmationController,
                    obscure: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFB42318),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  XpBtn(
                    label: _busy ? 'Сохраняем...' : 'Войти в организацию',
                    primary: true,
                    onPressed: _busy ? null : _completeInvitation,
                  ),
                  const SizedBox(height: 8),
                  XpBtn(
                    label: 'Выйти',
                    onPressed: _busy
                        ? null
                        : () => Supabase.instance.client.auth.signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _valueRow(String label, String value) {
    return Row(children: [
      SizedBox(
        width: 86,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    ]);
  }
}
