import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/auth_text_field.dart';

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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEFF6FF), Color(0xFFF8FAFC), Color(0xFFE0F2FE)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: 500,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFAFFFFFF),
                  border: Border.all(color: const Color(0xFFFFFFFF)),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F0F172A),
                      blurRadius: 36,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.mark_email_read_outlined,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Завершение регистрации',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Для вас подготовлен доступ к рабочему пространству',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(children: [
                        const Icon(
                          Icons.mail_outline,
                          size: 19,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            email,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    AuthTextField(
                      label: 'Ник пользователя',
                      hint: 'printer_oleg',
                      controller: _nicknameController,
                      icon: Icons.alternate_email,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      label: 'Имя пользователя',
                      hint: 'Иван Иванов',
                      controller: _displayNameController,
                      icon: Icons.badge_outlined,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      key: const ValueKey('invitation-password'),
                      label: 'Новый пароль',
                      hint: 'Минимум 8 символов',
                      controller: _passwordController,
                      icon: Icons.lock_outline,
                      password: true,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    AuthTextField(
                      key: const ValueKey('invitation-password-confirmation'),
                      label: 'Подтвердите пароль',
                      hint: 'Повторите пароль',
                      controller: _passwordConfirmationController,
                      icon: Icons.lock_reset_outlined,
                      password: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_busy) _completeInvitation();
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 18,
                              color: Color(0xFFB42318),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFB42318),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        key: const ValueKey('invitation-submit'),
                        onPressed: _busy ? null : _completeInvitation,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_forward, size: 19),
                        label: Text(
                          _busy ? 'Сохраняем...' : 'Войти в организацию',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Выйти из этого аккаунта'),
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
