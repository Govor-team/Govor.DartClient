import 'package:flutter/material.dart';
import '../core/user_benefits.dart';
import '../features/messenger_controller.dart';
import '../l10n/l10n.dart';
import 'design.dart';
import 'user_badge.dart';

Future<void> showProfileTagEditor(
  BuildContext context,
  MessengerController c,
) => showDialog<void>(
  context: context,
  builder: (_) => ProfileTagEditor(controller: c),
);

class ProfileTagEditor extends StatefulWidget {
  const ProfileTagEditor({super.key, required this.controller});
  final MessengerController controller;
  @override
  State<ProfileTagEditor> createState() => _ProfileTagEditorState();
}

class _ProfileTagEditorState extends State<ProfileTagEditor> {
  final form = GlobalKey<FormState>();
  late final initial =
      widget.controller.benefits[widget.controller.userId]?.tag?.json ??
      ProfileTag.defaults;
  late final fields = <String, TextEditingController>{
    for (final key in ProfileTag.defaults.keys.where((k) => k != 'fontFamily'))
      key: TextEditingController(text: initial[key]?.toString() ?? ''),
  };
  late String font = initial['fontFamily'] as String;
  bool saving = false;
  String? error;
  ProfileTag? get tag {
    try {
      return ProfileTag({
        for (final entry in fields.entries)
          entry.key: ProfileTag.ranges.containsKey(entry.key)
              ? entry.key == 'fontWeight'
                    ? int.parse(entry.value.text)
                    : double.parse(entry.value.text)
              : entry.value.text.isEmpty && entry.key.endsWith('EndColor')
              ? null
              : entry.value.text,
        'fontFamily': font,
      });
    } on FormatException {
      return null;
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save({bool reset = false}) async {
    if (saving || !reset && (!form.currentState!.validate() || tag == null)) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveProfileTag(reset ? null : tag);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = widget.controller.safeError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = <String, String>{
      'text': l.tagText,
      'textColor': l.tagTextColor,
      'textGradientEndColor': l.tagTextGradient,
      'backgroundColor': l.tagBackground,
      'gradientEndColor': l.tagBackgroundGradient,
      'gradientAngle': l.tagAngle,
      'borderColor': l.tagBorder,
      'borderGradientEndColor': l.tagBorderGradient,
      'borderWidth': l.tagBorderWidth,
      'shadowColor': l.tagShadow,
      'shadowBlur': l.tagShadowBlur,
      'shadowOffsetX': l.tagShadowX,
      'shadowOffsetY': l.tagShadowY,
      'fontWeight': l.tagFontWeight,
      'fontSize': l.tagFontSize,
    };
    return AnimatedBuilder(
      animation: widget.controller.benefits,
      builder: (context, _) {
        final allowed =
            (widget.controller.benefits[widget.controller.userId] ??
                    widget.controller.me!.benefits)
                .canCustomizeProfileTag;
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * .86,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.profileTag,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: l.close,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: tag == null
                        ? Text(
                            l.invalidTag,
                            style: const TextStyle(color: muted),
                          )
                        : ProfileTagBadge(tag: tag!),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Form(
                        key: form,
                        child: Column(
                          children: [
                            for (final entry in fields.entries)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextFormField(
                                  key: ValueKey('tag-${entry.key}'),
                                  controller: entry.value,
                                  enabled: !saving && allowed,
                                  decoration: InputDecoration(
                                    labelText: labels[entry.key],
                                    helperText:
                                        ProfileTag.colors.contains(entry.key)
                                        ? '#RRGGBB / #RRGGBBAA'
                                        : null,
                                  ),
                                  maxLength: entry.key == 'text' ? 32 : null,
                                  keyboardType:
                                      ProfileTag.ranges.containsKey(entry.key)
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        )
                                      : TextInputType.text,
                                  onChanged: (_) => setState(() {}),
                                  validator: (value) {
                                    try {
                                      final single = {...ProfileTag.defaults};
                                      single[entry.key] =
                                          ProfileTag.ranges.containsKey(
                                            entry.key,
                                          )
                                          ? entry.key == 'fontWeight'
                                                ? int.parse(value!)
                                                : double.parse(value!)
                                          : value!.isEmpty &&
                                                entry.key.endsWith('EndColor')
                                          ? null
                                          : value;
                                      ProfileTag(single);
                                      return null;
                                    } on FormatException {
                                      return l.invalidTag;
                                    }
                                  },
                                ),
                              ),
                            DropdownButtonFormField<String>(
                              initialValue: font,
                              isExpanded: true,
                              decoration: InputDecoration(labelText: l.tagFont),
                              items: [
                                for (final font in ProfileTag.fonts)
                                  DropdownMenuItem(
                                    value: font,
                                    child: Text(font),
                                  ),
                              ],
                              onChanged: saving || !allowed
                                  ? null
                                  : (v) => setState(() => font = v!),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (error != null) ErrorNotice(error!),
                  if (!allowed) Text(l.tagPermissionRequired),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: saving || !allowed
                            ? null
                            : () => save(reset: true),
                        child: Text(l.resetTag),
                      ),
                      FilledButton(
                        onPressed: saving || !allowed ? null : save,
                        child: Text(saving ? l.saving : l.save),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> showPrivilegesEditor(
  BuildContext context,
  MessengerController c,
  String userId,
) async {
  await c.loadBenefits(userId);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _PrivilegesEditor(controller: c, userId: userId),
  );
}

class _PrivilegesEditor extends StatefulWidget {
  const _PrivilegesEditor({required this.controller, required this.userId});
  final MessengerController controller;
  final String userId;
  @override
  State<_PrivilegesEditor> createState() => _PrivilegesEditorState();
}

class _PrivilegesEditorState extends State<_PrivilegesEditor> {
  late int value = widget.controller.benefits[widget.userId]?.privileges ?? 0;
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.userPrivileges),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final bit in [1, 2])
          CheckboxListTile(
            title: Text(bit == 1 ? 'Govor+' : context.l10n.profileTag),
            value: value & bit != 0,
            onChanged: saving
                ? null
                : (selected) => setState(
                    () => value = selected! ? value | bit : value & ~bit,
                  ),
          ),
        if (error != null) ErrorNotice(error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(context.l10n.close),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                setState(() {
                  saving = true;
                  error = null;
                });
                try {
                  await widget.controller.setUserPrivileges(
                    widget.userId,
                    value,
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    setState(() => error = widget.controller.safeError(e));
                  }
                } finally {
                  if (mounted) setState(() => saving = false);
                }
              },
        child: Text(context.l10n.save),
      ),
    ],
  );
}
