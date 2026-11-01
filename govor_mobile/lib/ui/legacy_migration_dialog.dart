import 'package:flutter/material.dart';

import 'design.dart';

/// Collects a *different* password for one-time bcrypt -> SRP enrollment.
/// The old password remains in the calling login flow, not in this widget.
class LegacyMigrationDialog extends StatefulWidget {
  const LegacyMigrationDialog({super.key});

  @override
  State<LegacyMigrationDialog> createState() => _LegacyMigrationDialogState();
}

class _LegacyMigrationDialogState extends State<LegacyMigrationDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield_outlined, color: accent, size: 38),
              const SizedBox(height: 14),
              Text('Обновление безопасности',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                'Этот аккаунт использует старый способ входа. '
                'Придумайте новый пароль, отличный от прежнего. '
                'Govor сохранит новые SRP-данные без передачи нового пароля серверу.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Новый пароль',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                validator: (value) => value == null || value.length < 8 || value.length > 256
                    ? 'Пароль должен содержать от 8 до 256 символов' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repeat,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Повторите новый пароль',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (value) => value != _password.text
                    ? 'Пароли не совпадают' : null,
              ),
              const SizedBox(height: 12),
              const Text(
                'SRP защищает вход, E2EE отдельно защищает переписку. '
                'Существующие ключи сообщений не будут автоматически сброшены.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.of(context).pop(_password.text);
                  }
                },
                child: const Text('Обновить аккаунт'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Позже'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
