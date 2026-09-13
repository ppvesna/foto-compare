import 'package:flutter/material.dart';

import '../features/auth/auth.dart';
import '../widgets/auth_text_field.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  final PasswordRecoveryService service;
  final Future<void> Function() onCompleted;

  const PasswordRecoveryScreen({
    super.key,
    required this.service,
    required this.onCompleted,
  });

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _saving = false;
  bool _completed = false;
  String? _errorText;

  bool get _confirmationStarted => _confirmationController.text.isNotEmpty;
  bool get _passwordsMatch =>
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmationController.text;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _passwordEdited(String _) {
    if (!mounted || _saving) return;
    setState(() => _errorText = null);
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirmation = _confirmationController.text;
    String? validationError;
    if (password.length < 8) {
      validationError = 'Новый пароль должен содержать минимум 8 символов.';
    } else if (password != confirmation) {
      validationError = 'Пароли не совпадают.';
    }
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.service.completeReset(newPassword: password);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _completed = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = error is PasswordRecoveryException
            ? error.message
            : 'Не удалось сохранить пароль. Повторите попытку.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: 460,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x55FFFFFF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x52000000),
                    blurRadius: 38,
                    offset: Offset(0, 22),
                  ),
                ],
              ),
              child: _completed ? _successContent() : _passwordForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordForm() {
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.lock_reset_rounded,
            size: 42,
            color: Color(0xFF2563EB),
          ),
          const SizedBox(height: 14),
          const Text(
            'Новый пароль',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Придумайте новый пароль длиной не менее 8 символов.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 22),
          AuthTextField(
            key: const ValueKey('password-recovery-new-password'),
            label: 'Новый пароль',
            hint: 'Минимум 8 символов',
            controller: _passwordController,
            icon: Icons.password_outlined,
            password: true,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: _passwordEdited,
          ),
          const SizedBox(height: 12),
          AuthTextField(
            key: const ValueKey('password-recovery-confirmation'),
            label: 'Повторите новый пароль',
            hint: 'Введите новый пароль ещё раз',
            controller: _confirmationController,
            icon: Icons.password_outlined,
            password: true,
            enabled: !_saving,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            onChanged: _passwordEdited,
            onSubmitted: (_) {
              if (!_saving) _submit();
            },
          ),
          if (_confirmationStarted && _errorText == null) ...[
            const SizedBox(height: 10),
            Text(
              _passwordsMatch
                  ? 'Пароли совпадают.'
                  : 'Пароли пока не совпадают.',
              key: const ValueKey('password-recovery-match-status'),
              style: TextStyle(
                color: _passwordsMatch
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB45309),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorText!,
              key: const ValueKey('password-recovery-complete-error'),
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const ValueKey('password-recovery-complete-submit'),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Сохраняем…' : 'Сохранить пароль'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successContent() {
    return Column(
      key: const ValueKey('password-recovery-success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 54,
          color: Color(0xFF15803D),
        ),
        const SizedBox(height: 14),
        const Text(
          'Пароль изменён',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Теперь можно войти с новым паролем.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 48,
          child: FilledButton(
            key: const ValueKey('password-recovery-return-to-login'),
            onPressed: widget.onCompleted,
            child: const Text('Перейти ко входу'),
          ),
        ),
      ],
    );
  }
}
