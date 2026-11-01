import 'avatar_preview.dart';
import 'font_size_selector.dart';
import 'profile_tag_editor.dart';
import '../core/user_benefits.dart';
import 'user_badge.dart';
import 'language_selector.dart';
import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../features/messenger_controller.dart';
import 'design.dart';
import 'wallpaper_picker.dart';
import 'govor_markdown.dart';

import 'feature_shared.dart';
import 'security_page.dart';
import 'reaction_packs_page.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/settings/settings_cubit.dart';
import '../features/profile/profile_description_cubit.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});
  final MessengerController controller;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with PageActions<ProfilePage> {
  @override
  MessengerController get controller => widget.controller;
  late final _description = TextEditingController(
    text:
        controller.profileDescriptionDraft ?? controller.me?.description ?? '',
  );
  final _descriptionFocus = FocusNode();
  late final description = ProfileDescriptionCubit(
    saved: controller.me?.description ?? '',
    draft: controller.profileDescriptionDraft,
    save: controller.updateDescription,
    onDraft: (value) => controller.profileDescriptionDraft = value,
    errorText: controller.safeError,
  );
  List<Json> _sessions = [];

  @override
  void initState() {
    super.initState();
    _description.addListener(_descriptionChanged);
    _descriptionFocus.addListener(_focusChanged);
    unawaited(
      run(() async {
        _sessions = await controller.sessions();
      }),
    );
  }

  void _descriptionChanged() => description.changed(_description.text);
  void _focusChanged() {
    if (!_descriptionFocus.hasFocus) unawaited(description.flush());
  }

  @override
  void dispose() {
    unawaited(description.close());
    _description.removeListener(_descriptionChanged);
    _description.dispose();
    _descriptionFocus.removeListener(_focusChanged);
    _descriptionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SettingsCubit, SettingsState>(
        bloc: controller.settings,
        builder: (context, settings) =>
            BlocBuilder<ProfileDescriptionCubit, ProfileDescriptionState>(
              bloc: description,
              builder: (context, profile) =>
                  _buildProfile(context, settings, profile),
            ),
      );

  Widget _buildProfile(
    BuildContext context,
    SettingsState settings,
    ProfileDescriptionState profile,
  ) {
    final c = controller;
    final identity = <Widget>[
      feedback,
      Center(
        child: SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            children: [
              PreviewAvatar(
                c.me?.name ?? context.l10n.govor,
                controller: c,
                imageId: c.me?.iconId,
                size: 112,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: IconButton.filled(
                  tooltip: context.l10n.changeAvatar,
                  onPressed: working || c.demo
                      ? null
                      : () => run(c.updateAvatar),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF94CA83),
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.photo_camera_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: Text(
          c.me?.name ?? '',
          style: const TextStyle(fontFamily: 'GovorDisplay', fontSize: 27),
        ),
      ),
      Center(
        child: UserBadge(
          controller: c,
          userId: c.userId,
          fallback: c.me?.benefits ?? const UserBenefits(),
        ),
      ),
      if ((c.benefits[c.userId] ?? c.me?.benefits)?.canCustomizeProfileTag ==
          true)
        Center(
          child: TextButton.icon(
            key: const Key('edit-profile-tag'),
            onPressed: () => showProfileTagEditor(context, c),
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: Text(context.l10n.profileTag),
          ),
        ),
      const SizedBox(height: 16),
      Glass(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: TextField(
          key: const Key('profile-description'),
          controller: _description,
          focusNode: _descriptionFocus,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          style: TextStyle(fontSize: 14, height: 1.5),
          decoration: InputDecoration(
            hintText: context.l10n.tellUsAboutYourself,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            counterStyle: TextStyle(fontSize: 10, color: muted),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 14),
        child: profile.error != null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      profile.error!,
                      style: const TextStyle(
                        color: Color(0xFFFFA3B3),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: description.flush,
                    child: Text(context.l10n.retry),
                  ),
                ],
              )
            : Text(
                profile.saving
                    ? context.l10n.saving
                    : context.l10n.yourDescriptionIsSavedAutomatically,
                style: const TextStyle(color: muted, fontSize: 10),
              ),
      ),
    ];
    final appearance = <Widget>[
      FontSizeSelector(settings: controller.settings),
      WallpaperPicker(controller: c, onAction: run, disabled: working),
      const SizedBox(height: 12),
    ];
    if (GovorMarkdown.hasFormatting(_description.text)) {
      identity.add(
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.preview,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              GovorMarkdown(_description.text),
            ],
          ),
        ),
      );
    }
    final account = <Widget>[
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: LanguageSelector(settings: controller.settings),
      ),
      if (settings.failed)
        ErrorNotice(context.l10n.couldNotSaveLanguagePleaseTryAgain),
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: ListTile(
          key: const Key('settings-appearance'),
          leading: const Icon(Icons.wallpaper_rounded),
          title: Text(context.l10n.appearance),
          subtitle: Text(context.l10n.backgroundAndTheme),
          trailing: const Icon(Icons.chevron_right_rounded),
          selected: settings.section == SettingsSection.appearance,
          onTap: () => controller.settings.select(SettingsSection.appearance),
        ),
      ),
      GlassCard(
        key: const Key('profile-theme-panel'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.darkTheme,
                style: TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: c.darkTheme,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: working
                  ? null
                  : (v) => run(() => c.setAppearance(dark: v)),
            ),
          ],
        ),
      ),
      Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          context.l10n.activeSessions,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      for (final session in _sessions)
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.devices_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session['deviceInfo'] as String? ?? context.l10n.device,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session['id'] == c.sessionId
                          ? context.l10n.currentSession
                          : context.l10n.sessionOpened(
                              (session['createdAt'] as String).split('T').first,
                            ),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (session['id'] != c.sessionId)
                IconButton(
                  tooltip: context.l10n.endSession,
                  onPressed: working
                      ? null
                      : () async {
                          if (await confirmAction(
                            context,
                            context.l10n.endThisSession,
                            context
                                .l10n
                                .thisDeviceWillStopReceivingNewMessagesAndPush,
                          )) {
                            await run(() async {
                              await c.revokeSession(session['id'] as String);
                              _sessions = await c.sessions();
                            });
                          }
                        },
                  icon: const Icon(Icons.logout_rounded, size: 20),
                ),
            ],
          ),
        ),
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: ListTile(
          dense: true,
          minVerticalPadding: 2,
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          titleTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontSize: 14),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.diamond_outlined),
          title: Text(context.l10n.messageSecurity),
          subtitle: Text(
            context.l10n.e2eeKeysAndHistoryTransfer,
            style: TextStyle(color: muted, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => MediaQuery.sizeOf(context).width >= 904
              ? controller.settings.select(SettingsSection.security)
              : openFeaturePage(context, c, SecurityPage(controller: c)),
        ),
      ),
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: ListTile(
          dense: true,
          minVerticalPadding: 2,
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          titleTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontSize: 14),
          contentPadding: EdgeInsets.zero,
          leading: const Text('😊', style: TextStyle(fontSize: 26)),
          title: Text(context.l10n.reactionPacks),
          subtitle: Text(
            context.l10n.emojiForYourMessages,
            style: TextStyle(color: muted, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => MediaQuery.sizeOf(context).width >= 904
              ? controller.settings.select(SettingsSection.reactions)
              : openFeaturePage(context, c, ReactionPacksPage(controller: c)),
        ),
      ),
      GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: ListTile(
          dense: true,
          minVerticalPadding: 2,
          minLeadingWidth: 24,
          horizontalTitleGap: 12,
          titleTextStyle: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontSize: 14),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.fingerprint_rounded),
          title: Text(context.l10n.accountId),
          subtitle: Text(
            c.userId,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          trailing: IconButton(
            tooltip: context.l10n.copyId,
            onPressed: () => Clipboard.setData(ClipboardData(text: c.userId)),
            icon: const Icon(Icons.copy_rounded, size: 19),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 38),
            textStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontSize: 13),
          ),
          onPressed: working
              ? null
              : () => run(() async {
                  await c.logout();
                  if (!c.ready && context.mounted) {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  } else if (c.error != null) {
                    throw Exception(c.error);
                  }
                }),
          icon: const Icon(Icons.logout_rounded),
          label: Text(context.l10n.signOut),
        ),
      ),

      const SizedBox(height: 16),
      Center(
        child: Text(
          c.versionLabel,
          style: const TextStyle(fontFamily: 'GovorDisplay', fontSize: 15),
        ),
      ),
      const SizedBox(height: 16),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: GlassPage(
        title: context.l10n.profile,
        compact: true,
        maxWidth: 1280,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 880) {
              return Row(
                key: const Key('profile-desktop'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: (constraints.maxWidth * .34).clamp(320.0, 400.0),
                    child: ListView(
                      key: const PageStorageKey('profile-identity'),
                      children: [...identity, ...account],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: switch (settings.section) {
                      SettingsSection.appearance => ListView(
                        key: const PageStorageKey('profile-appearance'),
                        children: appearance,
                      ),
                      SettingsSection.security => SecurityPage(
                        key: const Key('settings-security-content'),
                        controller: c,
                        embedded: true,
                      ),
                      SettingsSection.reactions => ReactionPacksPage(
                        key: const Key('settings-reactions-content'),
                        controller: c,
                        embedded: true,
                      ),
                    },
                  ),
                ],
              );
            }
            return ListView(
              key: const Key('profile-mobile'),
              children: [...identity, ...appearance, ...account],
            );
          },
        ),
      ),
    );
  }
}
