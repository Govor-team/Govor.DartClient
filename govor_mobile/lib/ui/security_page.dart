import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../features/messenger_controller.dart';
import 'design.dart';

import 'feature_shared.dart';

class SecurityPage extends StatefulWidget {
  const SecurityPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });
  final bool embedded;
  final MessengerController controller;
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage>
    with PageActions<SecurityPage> {
  @override
  MessengerController get controller => widget.controller;
  bool _fingerprint = false, _code = false;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final fingerprint = c.accountFingerprint;
    return GlassPage(
      embedded: widget.embedded,
      title: context.l10n.messageSecurity,
      subtitle: context.l10n.endToEndEncryptionE2Ee,
      child: ListView(
        children: [
          feedback,
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.accountKey,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.compareThePublicFingerprintWithYourContactOverA,
                  style: TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: fingerprint == null
                      ? null
                      : () => setState(() => _fingerprint = !_fingerprint),
                  child: Text(context.l10n.viewFingerprint),
                ),
                if (_fingerprint && fingerprint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SelectableText(
                      fingerprint,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.historyAndDevices,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.signingInWithYourPasswordUsuallyRestoresHistoryA,
                  style: TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: c.demo
                      ? null
                      : () => setState(() => _code = !_code),
                  child: Text(context.l10n.historyTransferRecoveryCode),
                ),
                if (_code && c.recoveryCode != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SelectableText(
                      c.recoveryCode!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: working ? null : () => run(c.syncKeys),
                  child: Text(context.l10n.syncHistory),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: working || c.demo
                      ? null
                      : () async {
                          final passwords = await passwordDialog(
                            context,
                            change: true,
                          );
                          if (passwords != null) {
                            await run(() async {
                              await c.changePassword(
                                passwords.$1,
                                passwords.$2!,
                              );
                              if (mounted) {
                                setState(
                                  () => problem = context
                                      .l10n
                                      .passwordChangedHistoryPreserved,
                                );
                              }
                            });
                          }
                        },
                  child: Text(context.l10n.changePassword),
                ),
                const SizedBox(height: 12),
                Text(
                  context
                      .l10n
                      .changingYourPasswordPreservesHistoryAndEndsOtherSessions,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.7),
                ),
              ],
            ),
          ),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.newKeys,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.useOnlyIfAllRecoveryMethodsAreLostOld,
                  style: TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: working || c.demo
                      ? null
                      : () async {
                          if (!await confirmAction(
                            context,
                            context.l10n.startWithNewKeys,
                            context
                                .l10n
                                .oldHistoryCannotBeRestoredOtherSessionsWillEnd,
                          )) {
                            return;
                          }
                          if (!context.mounted) return;
                          final passwords = await passwordDialog(
                            context,
                            change: false,
                          );
                          if (passwords != null) {
                            await run(() async {
                              await c.resetEncryption(passwords.$1);
                              if (mounted) {
                                setState(() {
                                  _code = false;
                                  problem = context
                                      .l10n
                                      .newKeysCreatedSaveTheNewRecoveryCode;
                                });
                              }
                            });
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFA3B3),
                  ),
                  child: Text(context.l10n.startChattingWithNewKeys),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(10),
            child: Text(
              context.l10n.initialKeyTrustAndGroupMembershipRelyOnThe,
              style: TextStyle(fontSize: 11, color: muted, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

Future<(String, String?)?> passwordDialog(
  BuildContext context, {
  required bool change,
}) async {
  final old = TextEditingController(),
      replacement = TextEditingController(),
      repeat = TextEditingController();
  final form = GlobalKey<FormState>();
  final result = await showDialog<(String, String?)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        change
            ? context.l10n.changePassword
            : context.l10n.confirmYourCurrentPassword,
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: old,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.currentPassword,
                  ),
                  validator: (v) => (v?.length ?? 0) < 8
                      ? context.l10n.enterYourCurrentPassword
                      : null,
                ),
                if (change) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: replacement,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: context.l10n.newPassword,
                    ),
                    validator: (v) =>
                        v == null || v.length < 8 || v.length > 256
                        ? context.l10n.between8And256Characters
                        : v == old.text
                        ? context.l10n.chooseADifferentPassword
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: repeat,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: context.l10n.repeatNewPassword,
                    ),
                    validator: (v) => v != replacement.text
                        ? context.l10n.passwordsDoNotMatch
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, (
                old.text,
                change ? replacement.text : null,
              ));
            }
          },
          child: Text(context.l10n.continueAction),
        ),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    old.dispose();
    replacement.dispose();
    repeat.dispose();
  });
  return result;
}
