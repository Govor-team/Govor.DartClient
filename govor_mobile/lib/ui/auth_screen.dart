import '../l10n/l10n.dart';
import 'package:flutter/material.dart';

import '../features/messenger_controller.dart';
import 'design.dart';
import 'legacy_migration_dialog.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});
  final MessengerController controller;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _password = TextEditingController(),
      _repeat = TextEditingController(),
      _invite = TextEditingController(),
      _code = TextEditingController();
  bool _register = false, _hidden = true;
  @override
  void dispose() {
    for (final c in [_name, _password, _repeat, _invite, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final c = widget.controller;
    if (c.needsRecovery) {
      await c.recover(_code.text);
      _code.clear();
      return;
    }
    final password = _password.text;
    _password.clear();
    _repeat.clear();
    await c.signIn(
      _name.text,
      password,
      invitation: _register ? _invite.text : null,
    );
    if (!mounted || !c.legacyMigrationRequired) return;
    final newPassword = await showDialog<String>(
      context: context,
      builder: (_) => const LegacyMigrationDialog(),
    );
    c.dismissLegacyMigration();
    if (!mounted || newPassword == null) return;
    if (newPassword == password) {
      c.error = 'Новый пароль должен отличаться от прежнего.';
      c.notifyListeners();
      return;
    }
    await c.migrateLegacyAccount(_name.text, password, newPassword);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                const BrandMark(size: 76),
                const SizedBox(height: 22),
                Text(
                  context.l10n.govor,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.needsRecovery
                      ? context.l10n.restoreYourEncryptedHistory
                      : context.l10n.closerTogetherOnEveryScreen,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, height: 1.6),
                ),
                const SizedBox(height: 30),
                Glass(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          c.needsRecovery
                              ? context.l10n.keyRecovery
                              : _register
                              ? context.l10n.createAccount
                              : context.l10n.welcomeBack,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          c.needsRecovery
                              ? context
                                    .l10n
                                    .enterTheRecoveryCodeFromADeviceThatAlready
                              : _register
                              ? context.l10n.anInvitationIsRequiredToRegister
                              : context.l10n.signInToYourGovorAccount,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (c.needsRecovery)
                          TextFormField(
                            controller: _code,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: context.l10n.recoveryCode,
                              prefixIcon: Icon(Icons.key_rounded),
                            ),
                            validator: (s) => s == null || s.trim().length < 40
                                ? context.l10n.enterTheCompleteRecoveryCode
                                : null,
                            onFieldSubmitted: (_) => c.busy ? null : _submit(),
                          )
                        else ...[
                          TextFormField(
                            key: const Key('name-field'),
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: context.l10n.name,
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (s) => s == null || s.trim().isEmpty
                                ? context.l10n.enterYourName
                                : _register &&
                                      !RegExp(
                                        r'^[А-Яа-яЁё][А-Яа-яЁё0-9]{3,43}$',
                                      ).hasMatch(s.trim())
                                ? context.l10n.validUsername
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('password-field'),
                            controller: _password,
                            obscureText: _hidden,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: _register
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: context.l10n.password,
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _hidden
                                    ? context.l10n.showPassword
                                    : context.l10n.hidePassword,
                                onPressed: () =>
                                    setState(() => _hidden = !_hidden),
                                icon: Icon(
                                  _hidden
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (s) =>
                                s == null || s.length < 8 || s.length > 256
                                ? context.l10n.between8And256Characters
                                : null,
                            onFieldSubmitted: (_) {
                              if (!_register && !c.busy) _submit();
                            },
                          ),
                          if (_register) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _repeat,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: context.l10n.repeatPassword,
                              ),
                              validator: (s) => s != _password.text
                                  ? context.l10n.passwordsDoNotMatch
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _invite,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: context.l10n.invitationCode,
                                prefixIcon: Icon(
                                  Icons.confirmation_number_outlined,
                                ),
                              ),
                              validator: (s) =>
                                  !RegExp(
                                    r'^[0-9a-fA-F]{32}$',
                                  ).hasMatch(s?.trim() ?? '')
                                  ? context.l10n.invitationLength
                                  : null,
                            ),
                          ],
                        ],
                        if (c.error != null) ...[
                          const SizedBox(height: 18),
                          ErrorNotice(c.error!, onDismiss: c.clearError),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const Key('auth-submit'),
                          onPressed: c.busy ? null : _submit,
                          child: c.busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  c.needsRecovery
                                      ? context.l10n.restoreHistory
                                      : _register
                                      ? context.l10n.register
                                      : context.l10n.signIn,
                                ),
                        ),
                        if (!c.needsRecovery) ...[
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: c.busy
                                ? null
                                : () => setState(() {
                                    _register = !_register;
                                    c.clearError();
                                  }),
                            child: Text(
                              _register
                                  ? context.l10n.alreadyHaveAnAccountSignIn
                                  : context.l10n.noAccountRegister,
                            ),
                          ),
                        ],
                        if (c.hasSession && !c.needsRecovery)
                          TextButton(
                            onPressed: c.busy ? null : c.retryActivation,
                            child: Text(context.l10n.reconnectSession),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton.icon(
                  key: const Key('demo-button'),
                  onPressed: c.busy ? null : c.startDemo,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: Text(context.l10n.exploreTheDemo),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user_outlined, size: 14, color: muted),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        context.l10n.endToEndEncryptionExperimentalVersion,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
