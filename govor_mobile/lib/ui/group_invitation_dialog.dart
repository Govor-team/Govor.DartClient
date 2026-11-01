import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/group_invitation.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';

/// Keeps entered options on request failure; only a successful create closes it.
class GroupInvitationDialog extends StatefulWidget {
  const GroupInvitationDialog({super.key, required this.create});
  final Future<Json> Function(GroupInvitationOptions) create;
  @override
  State<GroupInvitationDialog> createState() => _GroupInvitationDialogState();
}

class _GroupInvitationDialogState extends State<GroupInvitationDialog> {
  final form = GlobalKey<FormState>();
  final days = TextEditingController(text: '7');
  final participants = TextEditingController(text: '0');
  final description = TextEditingController();
  bool saving = false, failed = false;

  @override
  void dispose() {
    days.dispose();
    participants.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      failed = false;
    });
    try {
      final result = await widget.create(
        GroupInvitationOptions(
          validForDays: int.parse(days.text),
          maxParticipants: int.parse(participants.text),
          description: description.text,
        ),
      );
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted) {
        setState(() {
          failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(context.l10n.createInvitation),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('invite-days'),
                  controller: days,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: InputDecoration(
                    labelText: context.l10n.invitationDays,
                    helperText: '1–365',
                    errorMaxLines: 3,
                  ),
                  validator: (value) =>
                      (int.tryParse(value ?? '') ?? 0) >= 1 &&
                          (int.tryParse(value ?? '') ?? 0) <= 365
                      ? null
                      : context.l10n.invalidInvitationDays,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('invite-participants'),
                  controller: participants,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  decoration: InputDecoration(
                    labelText: context.l10n.invitationLimit,
                    helperText: context.l10n.invitationUnlimitedHint,
                    helperMaxLines: 3,
                    errorMaxLines: 3,
                  ),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number != null && number >= 0 && number <= 1000000
                        ? null
                        : context.l10n.invalidInvitationLimit;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('invite-description'),
                  controller: description,
                  enabled: !saving,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: context.l10n.invitationDescription,
                  ),
                ),
                if (failed)
                  Text(
                    context.l10n.couldNotCreateInvitation,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
        FilledButton(
          key: const Key('create-invitation-submit'),
          onPressed: saving ? null : _create,
          child: Text(
            saving ? context.l10n.saving : context.l10n.createInvitation,
          ),
        ),
      ],
    ),
  );
}
