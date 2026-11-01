import 'avatar_preview.dart';
import 'profile_tag_editor.dart';
import 'user_badge.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/crypto/primitives.dart';
import '../core/user_profile_repository.dart';
import '../features/messenger_controller.dart';
import '../features/profile/user_profile_cubit.dart';
import '../l10n/l10n.dart';
import 'design.dart';
import 'govor_markdown.dart';

Future<void> showUserProfile(
  BuildContext context,
  MessengerController controller,
  String userId,
) => showDialog<void>(
  context: context,
  builder: (_) => UserProfileDialog(controller: controller, userId: userId),
);

class UserProfileDialog extends StatefulWidget {
  const UserProfileDialog({
    super.key,
    required this.controller,
    required this.userId,
    this.repository,
  });
  final MessengerController controller;
  final String userId;
  final UserProfileRepository? repository;
  @override
  State<UserProfileDialog> createState() => _UserProfileDialogState();
}

class _UserProfileDialogState extends State<UserProfileDialog> {
  late final profile = UserProfileCubit(
    widget.repository ?? widget.controller.profiles,
    widget.userId,
  );
  bool opening = false;
  String? openError;
  String _snapshot = '';
  String _snapshotKey() {
    final c = widget.controller;
    final person = c.friends.where((p) => p.id == widget.userId).firstOrNull;
    return jsonEncode([
      c.connection.index,
      c.userId,
      person?.name,
      person?.description,
      person?.iconId,
      person?.online,
      c.benefits[widget.userId]?.revision,
      ...[...c.requests, ...c.outgoingRequests].where(
        (r) =>
            r['requesterId'] == widget.userId ||
            r['addresseeId'] == widget.userId,
      ),
    ]);
  }

  void _changed() {
    final next = _snapshotKey();
    if (next != _snapshot) {
      _snapshot = next;
      unawaited(profile.load());
    }
  }

  @override
  void initState() {
    super.initState();
    _snapshot = _snapshotKey();
    widget.controller.addListener(_changed);
    unawaited(profile.load());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    unawaited(profile.close());
    super.dispose();
  }

  Future<void> _chat() async {
    if (opening || profile.state.profile?.relationship != Relationship.friend) {
      return;
    }
    setState(() {
      opening = true;
      openError = null;
    });
    try {
      await widget.controller.chatWith(profile.state.profile!.person);
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (_) {
      if (mounted) setState(() => openError = context.l10n.couldNotOpenChat);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<UserProfileCubit, UserProfileState>(
    bloc: profile,
    builder: (context, state) {
      final user = state.profile?.person,
          relation = state.profile?.relationship;
      if (user?.iconId != null && validId(user!.iconId)) {
        unawaited(widget.controller.loadAvatar(user.iconId!));
      }
      return Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * .88,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: context.l10n.close,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                        if (user != null) ...[
                          AnimatedBuilder(
                            animation: widget.controller,
                            builder: (context, _) => PreviewAvatar(
                              user.name,
                              controller: widget.controller,
                              imageId: user.iconId,
                              size: 86,
                              online: user.online,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            user.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          UserBadge(
                            controller: widget.controller,
                            userId: user.id,
                            fallback: user.benefits,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.online
                                ? context.l10n.online
                                : context.l10n.offline,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          if (widget.controller.isAdmin)
                            TextButton(
                              onPressed: () => showPrivilegesEditor(
                                context,
                                widget.controller,
                                user.id,
                              ),
                              child: Text(context.l10n.userPrivileges),
                            ),
                          const SizedBox(height: 20),
                          if (relation == Relationship.friend)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const Key('profile-open-chat'),
                                onPressed: state.working || opening
                                    ? null
                                    : _chat,
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                ),
                                label: Text(context.l10n.openChat),
                              ),
                            )
                          else if (relation == Relationship.stranger ||
                              relation == Relationship.rejected)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const Key('profile-send-request'),
                                onPressed: state.working || state.loading
                                    ? null
                                    : profile.send,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                ),
                                label: Text(context.l10n.sendFriendRequest),
                              ),
                            )
                          else if (relation == Relationship.incoming)
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton(
                                  key: const Key('profile-accept-request'),
                                  onPressed: state.working
                                      ? null
                                      : () => profile.respond(true),
                                  child: Text(context.l10n.accept),
                                ),
                                OutlinedButton(
                                  key: const Key('profile-reject-request'),
                                  onPressed: state.working
                                      ? null
                                      : () => profile.respond(false),
                                  child: Text(context.l10n.decline),
                                ),
                              ],
                            )
                          else if (relation == Relationship.outgoing)
                            Text(
                              context.l10n.waitingForAReply,
                              style: const TextStyle(color: muted),
                            )
                          else if (relation == Relationship.blocked)
                            Text(
                              context.l10n.requestUnavailable,
                              style: const TextStyle(color: muted),
                            ),
                          if (relation == Relationship.friend)
                            TextButton(
                              key: const Key('profile-remove-friend'),
                              onPressed: state.working || state.loading
                                  ? null
                                  : () async {
                                      await profile.removeFriend();
                                      await widget.controller.refresh();
                                    },
                              child: Text(context.l10n.removeFriend),
                            ),
                          if (relation != Relationship.self &&
                              relation != Relationship.blocked)
                            TextButton.icon(
                              key: const Key('profile-block-user'),
                              onPressed: state.working || state.loading
                                  ? null
                                  : () async {
                                      await profile.block(true);
                                      await widget.controller.refresh();
                                    },
                              icon: const Icon(Icons.block_rounded, size: 18),
                              label: Text(context.l10n.blockUser),
                            ),
                          if (relation == Relationship.blocked &&
                              state.profile!.blockedByMe)
                            TextButton(
                              key: const Key('profile-unblock-user'),
                              onPressed: state.working || state.loading
                                  ? null
                                  : () async {
                                      await profile.block(false);
                                      await widget.controller.refresh();
                                    },
                              child: Text(context.l10n.unblockUser),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (state.loading || state.working || opening)
                  const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.failed)
                        Row(
                          children: [
                            Expanded(
                              child: Text(context.l10n.couldNotLoadProfile),
                            ),
                            IconButton(
                              tooltip: context.l10n.retry,
                              onPressed: state.working ? null : profile.load,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                      if (openError != null) ErrorNotice(openError!),
                      if (user != null) ...[
                        if (user.description.isNotEmpty) ...[
                          Text(
                            context.l10n.about,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          GovorMarkdown(user.description),
                          const SizedBox(height: 20),
                        ],
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            context.l10n.accountId,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          subtitle: SelectableText(
                            user.id,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.copyId,
                            onPressed: () =>
                                Clipboard.setData(ClipboardData(text: user.id)),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
