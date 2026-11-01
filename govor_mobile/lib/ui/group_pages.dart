import 'group_invitation_dialog.dart';
import 'avatar_preview.dart';
import 'user_badge.dart';
import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../features/messenger_controller.dart';
import 'design.dart';
import 'feature_pages.dart';
import 'govor_markdown.dart';
import 'user_profile_dialog.dart';

class GroupExplorePage extends StatefulWidget {
  const GroupExplorePage({super.key, required this.controller});
  final MessengerController controller;
  @override
  State<GroupExplorePage> createState() => _GroupExplorePageState();
}

class _GroupExplorePageState extends State<GroupExplorePage>
    with PageActions<GroupExplorePage> {
  @override
  MessengerController get controller => widget.controller;
  final _search = TextEditingController(), _invite = TextEditingController();
  List<Json> _groups = [];
  Future<void> _load() => run(() async {
    _groups = await controller.searchGroups(_search.text);
  });
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    _invite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassPage(
    title: context.l10n.groupsAndChannels,
    child: ListView(
      children: [
        GlassCard(
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            maxLength: 100,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: context.l10n.findACommunity,
              counterText: '',
              suffixIcon: IconButton(
                tooltip: context.l10n.search,
                onPressed: working ? null : _load,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
        ),
        feedback,
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.byInvitation,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 19),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _invite,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: context.l10n.invitationLinkOrCode,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: controller.demo || working
                    ? null
                    : () => run(() async {
                        final preview = await controller.previewInvite(
                          _invite.text,
                        );
                        if (!context.mounted) return;
                        final name =
                            preview['name'] ??
                            preview['groupName'] ??
                            context.l10n.community;
                        if (await confirmAction(
                          context,
                          context.l10n.joinCommunityName(name.toString()),
                          context
                              .l10n
                              .youWillBeAbleToReadCommunityMessagesAfter,
                        )) {
                          await controller.joinInvite(_invite.text);
                        }
                      }),
                child: Text(context.l10n.previewInvitation),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: working
              ? null
              : () async {
                  final value = await groupForm(context);
                  if (value != null) {
                    await run(
                      () => controller.createGroup(
                        value['name'] as String,
                        value['description'] as String,
                        value['isPrivate'] as bool,
                        value['isChannel'] as bool,
                      ),
                    );
                  }
                },
          icon: const Icon(Icons.add_rounded),
          label: Text(context.l10n.createAGroupOrChannel),
        ),
        const SizedBox(height: 20),
        for (final group in _groups)
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  group['name'] as String,
                  style: const TextStyle(
                    fontFamily: 'GovorDisplay',
                    fontSize: 25,
                  ),
                ),
                const SizedBox(height: 8),
                GovorMarkdown(
                  group['description'] as String? ?? '',
                  style: const TextStyle(color: muted, height: 1.6),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.communitySummary(
                    group['memberCount'] as int,
                    group['isChannel'] == true
                        ? context.l10n.channel
                        : context.l10n.group,
                  ),
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: working
                      ? null
                      : () => run(() async {
                          if (group['myRole'] == null) {
                            await controller.joinGroup(group['id'] as String);
                          }
                          if (!context.mounted) return;
                          await openFeaturePage(
                            context,
                            controller,
                            GroupProfilePage(
                              controller: controller,
                              groupId: group['id'] as String,
                            ),
                          );
                        }),
                  child: Text(
                    group['myRole'] == null
                        ? context.l10n.join
                        : context.l10n.openProfile,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

Future<Json?> groupForm(BuildContext context, {Json? initial}) async {
  final name = TextEditingController(text: initial?['name'] as String? ?? ''),
      description = TextEditingController(
        text: initial?['description'] as String? ?? '',
      );
  final form = GlobalKey<FormState>();
  var private = initial?['isPrivate'] as bool? ?? true,
      channel = initial?['isChannel'] as bool? ?? false;
  final value = await showDialog<Json>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          initial == null
              ? context.l10n.createCommunity
              : context.l10n.editProfile,
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: context.l10n.title),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? context.l10n.enterATitle
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.l10n.description,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.private),
                    subtitle: Text(
                      context.l10n.joinByInvitation,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    value: private,
                    onChanged: (v) => update(() => private = v),
                  ),
                  if (initial == null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.channel),
                      subtitle: Text(
                        context.l10n.onlyAdministratorsCanPost,
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      value: channel,
                      onChanged: (v) => update(() => channel = v),
                    ),
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
                Navigator.pop(context, {
                  'name': name.text.trim(),
                  'description': description.text,
                  'isPrivate': private,
                  'isChannel': channel,
                });
              }
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    name.dispose();
    description.dispose();
  });
  return value;
}

class GroupProfilePage extends StatefulWidget {
  const GroupProfilePage({
    super.key,
    required this.controller,
    required this.groupId,
  });
  final MessengerController controller;
  final String groupId;
  @override
  State<GroupProfilePage> createState() => _GroupProfilePageState();
}

class _GroupProfilePageState extends State<GroupProfilePage>
    with PageActions<GroupProfilePage> {
  @override
  MessengerController get controller => widget.controller;
  Json? _group;
  List<Json> _members = [], _invites = [];
  bool _banned = false;
  int get _role => _group?['myRole'] as int? ?? -1;
  Future<void> _load() => run(() async {
    _group = await controller.group(widget.groupId);
    final imageId = _group?['imageId'] as String?;
    if (imageId != null) unawaited(controller.loadAvatar(imageId));
    _members = await controller.members(widget.groupId, banned: _banned);
    if (_role >= 1 && !controller.demo) {
      _invites = await controller.groupInvites(widget.groupId);
    }
  });
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, g = _group;
    return GlassPage(
      title: context.l10n.communityLabel,
      trailing: IconButton(
        tooltip: context.l10n.refresh,
        onPressed: working ? null : _load,
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: ListView(
        children: [
          feedback,
          if (g != null) ...[
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: PreviewAvatar(
                      g['name'] as String,
                      controller: c,
                      imageId: g['imageId'] as String?,
                      size: 92,
                      group: true,
                    ),
                  ),
                  if (_role == 2 && !c.demo) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          key: const Key('change-group-avatar'),
                          onPressed: working
                              ? null
                              : () async {
                                  await run(
                                    () => c.updateGroupAvatar(widget.groupId),
                                  );
                                  await _load();
                                },
                          icon: const Icon(
                            Icons.add_a_photo_outlined,
                            size: 18,
                          ),
                          label: Text(context.l10n.changeAvatar),
                        ),
                        if (g['imageId'] != null)
                          IconButton(
                            key: const Key('remove-group-avatar'),
                            tooltip: context.l10n.removeAvatar,
                            onPressed: working
                                ? null
                                : () async {
                                    await run(
                                      () => c.removeGroupAvatar(widget.groupId),
                                    );
                                    await _load();
                                  },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      context.l10n.groupAvatarHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    g['name'] as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'GovorDisplay',
                      fontSize: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GovorMarkdown(
                    g['description'] as String? ?? '',
                    style: const TextStyle(height: 1.6),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.communitySummary(
                      g['memberCount'] as int,
                      g['isPrivate'] == true
                          ? context.l10n.private
                          : context.l10n.public,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () async {
                      final chat = c.conversations
                          .where((chat) => chat.id == widget.groupId)
                          .firstOrNull;
                      if (chat != null) {
                        await c.open(chat);
                        if (context.mounted) {
                          Navigator.popUntil(context, (route) => route.isFirst);
                        }
                      }
                    },
                    child: Text(context.l10n.openConversation),
                  ),
                  if (_role == 2 && !c.demo) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: working
                          ? null
                          : () async {
                              final value = await groupForm(
                                context,
                                initial: g,
                              );
                              if (value != null) {
                                await run(
                                  () => c.updateGroup(
                                    widget.groupId,
                                    value['name'] as String,
                                    value['description'] as String,
                                    value['isPrivate'] as bool,
                                  ),
                                );
                                await _load();
                              }
                            },
                      child: Text(context.l10n.editProfile),
                    ),
                  ],
                  if (g['canLeave'] == true && !c.demo)
                    TextButton(
                      onPressed: working
                          ? null
                          : () async {
                              if (await confirmAction(
                                context,
                                context.l10n.leaveThisCommunity,
                                context
                                    .l10n
                                    .youWillLoseAccessToItsHistoryAndNew,
                              )) {
                                await run(() async {
                                  await c.leaveGroup(widget.groupId);
                                  if (context.mounted) {
                                    Navigator.popUntil(
                                      context,
                                      (r) => r.isFirst,
                                    );
                                  }
                                });
                              }
                            },
                      child: Text(context.l10n.leaveCommunity),
                    ),
                ],
              ),
            ),
            if (_role >= 1 && !c.demo)
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.l10n.invitations,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: working
                          ? null
                          : () async {
                              final revision = c.sessionRevision;
                              final created = await showDialog<Json>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => GroupInvitationDialog(
                                  create: (options) => c.createGroupInvite(
                                    widget.groupId,
                                    options,
                                  ),
                                ),
                              );
                              if (created != null &&
                                  mounted &&
                                  revision == c.sessionRevision) {
                                setState(() {
                                  _invites = [created, ..._invites];
                                });
                              }
                            },
                      child: Text(context.l10n.createInvitation),
                    ),
                    for (final invite in _invites.where(
                      (i) => i['isRevoked'] != true,
                    ))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          invite['description'] as String? ??
                              context.l10n.invitation,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          [
                            context.l10n.invitationUsed(
                              invite['usedCount'] as int,
                            ),
                            invite['maxParticipants'] == 0
                                ? context.l10n.unlimitedInvitations
                                : '${context.l10n.invitationLimit}: ${invite['maxParticipants']}',
                            if (DateTime.tryParse(
                                  invite['endDate'] as String? ?? '',
                                )
                                case final date?)
                              MaterialLocalizations.of(
                                context,
                              ).formatMediumDate(date.toLocal()),
                          ].join(' · '),
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: context.l10n.copyLink,
                              onPressed: () => Clipboard.setData(
                                ClipboardData(
                                  text: '${c.lastServer}${invite['sharePath']}',
                                ),
                              ),
                              icon: const Icon(Icons.copy_outlined, size: 18),
                            ),
                            IconButton(
                              tooltip: context.l10n.revokeInvitation,
                              onPressed: working
                                  ? null
                                  : () => run(() async {
                                      await c.revokeGroupInvite(
                                        widget.groupId,
                                        invite['id'] as String,
                                      );
                                      _invites = await c.groupInvites(
                                        widget.groupId,
                                      );
                                    }),
                              icon: const Icon(
                                Icons.link_off_rounded,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (_role >= 1 && g['isChannel'] == true && !c.demo)
              GlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.allowedReactions),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _channelPolicy(),
                ),
              ),
            if (_role >= 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GlassSegments(
                  labels: [context.l10n.members, context.l10n.banned],
                  selected: _banned ? 1 : 0,
                  onChanged: (v) {
                    setState(() => _banned = v == 1);
                    _load();
                  },
                ),
              ),
            for (final member in _members)
              GlassCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () =>
                      showUserProfile(context, c, member['userId'] as String),
                  leading: PreviewAvatar(
                    member['username'] as String,
                    controller: c,
                    userId: member['userId'] as String,
                    size: 38,
                  ),
                  title: Wrap(
                    spacing: 6,
                    children: [
                      Text(member['username'] as String),
                      UserBadge(
                        controller: c,
                        userId: member['userId'] as String,
                      ),
                    ],
                  ),
                  subtitle: Text(switch (member['role']) {
                    2 => context.l10n.owner,
                    1 => context.l10n.administrator,
                    _ => context.l10n.member,
                  }, style: const TextStyle(fontSize: 11, color: muted)),
                  trailing:
                      _role >= 1 &&
                          member['userId'] != c.userId &&
                          member['role'] != 2 &&
                          !c.demo
                      ? PopupMenuButton<String>(
                          tooltip: context.l10n.memberActions,
                          onSelected: (action) async {
                            if (!await confirmAction(
                              context,
                              context.l10n.applyThisAction,
                              context.l10n.changeMemberRights(
                                member['username'] as String,
                              ),
                            )) {
                              return;
                            }
                            await run(() async {
                              final user = member['userId'] as String;
                              if (action == 'owner') {
                                await c.transferGroup(widget.groupId, user);
                              } else {
                                await c.memberAction(
                                  widget.groupId,
                                  user,
                                  action == 'admin' ? 'administrator' : 'ban',
                                  action == 'admin'
                                      ? member['role'] != 1
                                      : !_banned,
                                );
                              }
                              _members = await c.members(
                                widget.groupId,
                                banned: _banned,
                              );
                              _group = await c.group(widget.groupId);
                            });
                          },
                          itemBuilder: (_) => [
                            if (_role == 2 && !_banned)
                              PopupMenuItem(
                                value: 'admin',
                                child: Text(
                                  member['role'] == 1
                                      ? context.l10n.removeAdministrator
                                      : context.l10n.makeAdministrator,
                                ),
                              ),
                            if (_role == 2 && !_banned)
                              PopupMenuItem(
                                value: 'owner',
                                child: Text(context.l10n.transferOwnership),
                              ),
                            if (_role == 2 || member['role'] == 0)
                              PopupMenuItem(
                                value: 'ban',
                                child: Text(
                                  _banned
                                      ? context.l10n.unban
                                      : context.l10n.ban,
                                ),
                              ),
                          ],
                        )
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _channelPolicy() async {
    await run(() async {
      final c = controller;
      final current = await c.channelReactionPolicy(widget.groupId);
      final packs = await c.reactionPacks();
      if (!mounted) return;
      var mode = current['mode'] as int;
      final selected = (current['reactionIds'] as List).cast<String>().toSet();
      final value = await showDialog<Json>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(context.l10n.channelReactions),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: mode,
                      items: [
                        DropdownMenuItem(
                          value: 0,
                          child: Text(context.l10n.all),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text(context.l10n.none),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text(context.l10n.selected),
                        ),
                      ],
                      onChanged: (v) => update(() => mode = v!),
                    ),
                    if (mode == 2)
                      Wrap(
                        children: [
                          for (final pack in packs)
                            for (final reaction in objects(pack['reactions']))
                              FilterChip(
                                label: ReactionGraphic(
                                  reaction: reaction,
                                  controller: c,
                                  size: 24,
                                ),
                                selected: selected.contains(reaction['id']),
                                onSelected: (v) => update(() {
                                  if (v) {
                                    selected.add(reaction['id'] as String);
                                  } else {
                                    selected.remove(reaction['id']);
                                  }
                                }),
                              ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, {
                  'mode': mode,
                  'reactionIds': mode == 2 ? selected.toList() : <String>[],
                }),
                child: Text(context.l10n.save),
              ),
            ],
          ),
        ),
      );
      if (value != null) {
        await c.updateChannelReactionPolicy(widget.groupId, value);
      }
    });
  }
}
