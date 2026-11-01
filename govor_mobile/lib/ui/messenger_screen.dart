import 'avatar_preview.dart';
import 'user_badge.dart';
import 'attachment_gallery.dart';
import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/chat_hub.dart';
import '../core/models.dart';
import '../features/messenger_controller.dart';
import 'design.dart';
import 'message_bubble.dart';
import 'user_profile_dialog.dart';
import 'feature_pages.dart';
import 'group_pages.dart';
import 'message_actions.dart';

class MessengerScreen extends StatefulWidget {
  const MessengerScreen({
    super.key,
    required this.controller,
    required this.dark,
    required this.onThemeChanged,
  });
  final MessengerController controller;
  final bool dark;
  final ValueChanged<bool> onThemeChanged;
  @override
  State<MessengerScreen> createState() => _MessengerScreenState();
}

class _MessengerScreenState extends State<MessengerScreen> {
  final _search = TextEditingController(),
      _composer = TextEditingController(),
      _messageSearch = TextEditingController();
  final _scroll = ScrollController();
  final _composerFocus = FocusNode();
  String? _chatKey;
  String? _pendingId;
  final Set<String> _selectedIds = {};
  int _filter = 1;
  int _homeTab = 0;
  bool _searchingChats = false;
  bool _searchingMessages = false;
  bool _messageActionsOpen = false;
  ChatMessage? _reply;
  MessengerController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _composer.addListener(_saveDraft);
  }

  void _saveDraft() {
    if (_chatKey != null) c.drafts[_chatKey!] = _composer.text;
  }

  @override
  void dispose() {
    _search.dispose();
    _composer.dispose();
    _messageSearch.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(c.safeError(e))));
      }
    }
  }

  void _settings() => openFeaturePage(context, c, ProfilePage(controller: c));
  Future<void> _send() async {
    if (c.sending ||
        c.uploading ||
        (_composer.text.trim().isEmpty &&
            c.selectedAttachments.isEmpty &&
            c.pending == null)) {
      return;
    }
    final key = _chatKey;
    final success = await c.send(
      _composer.text,
      replyTo: c.pending?.reply ?? _reply?.id,
    );
    if (!mounted) return;
    if (success && key == _chatKey) {
      _composer.clear();
      setState(() => _reply = null);
      _composerFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (c.selected?.key != _chatKey) {
      _chatKey = c.selected?.key;
      _reply = null;
      _searchingMessages = false;
      _messageSearch.clear();
      _pendingId = null;
      _selectedIds.clear();
      _composer.text = _chatKey == null
          ? ''
          : c.drafts[_chatKey] ?? c.pending?.text ?? '';
    }
    if (_pendingId != null &&
        c.pending == null &&
        c.messages.any((m) => m.id == _pendingId)) {
      _composer.clear();
      _reply = null;
    }
    _pendingId = c.pending?.id;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(wide ? 16 : 8),
            child: Column(
              children: [
                if (c.demo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _demoBanner(),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wide) ...[_rail(), const SizedBox(width: 12)],
                      if (wide || c.selected == null)
                        SizedBox(
                          width: wide
                              ? (constraints.maxWidth >= 1100 ? 330 : 290)
                              : constraints.maxWidth - 16,
                          child: _home(wide),
                        ),
                      if (wide) const SizedBox(width: 12),
                      if (wide || c.selected != null)
                        Expanded(
                          child: c.selected == null
                              ? _emptyChat()
                              : _chat(wide),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _demoBanner() => Glass(
    radius: 14,
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    child: Row(
      children: [
        const Icon(Icons.science_outlined, color: accent, size: 17),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            context.l10n.demoMessagesStayInMemoryNoServerConnection,
            style: TextStyle(fontSize: 12),
          ),
        ),
        TextButton(
          onPressed: c.busy ? null : c.logout,
          child: Text(context.l10n.leave),
        ),
      ],
    ),
  );
  Widget _rail() => SizedBox(
    width: 72,
    child: Glass(
      radius: 26,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          const BrandMark(size: 42),
          const SizedBox(height: 32),
          IconButton.filledTonal(
            tooltip: context.l10n.chats,
            onPressed: () => setState(() => _homeTab = 0),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          const SizedBox(height: 12),
          IconButton(
            tooltip: context.l10n.friendsAndRequests,
            onPressed: () => setState(() => _homeTab = 1),
            icon: const Icon(Icons.people_outline_rounded),
          ),
          const Spacer(),
          IconButton(
            tooltip: context.l10n.settings,
            onPressed: _settings,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(height: 16),
          Tooltip(
            message: c.me?.name ?? context.l10n.profile,
            child: PreviewAvatar(
              c.me?.name ?? context.l10n.govor,
              controller: c,
              imageId: c.me?.iconId,
              size: 36,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _home(bool wide) {
    final body = _homeTab == 0 ? _chatList(wide) : ContactsPane(controller: c);
    return Column(
      children: [
        if (!wide && _homeTab == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 0, 22),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.me?.name ?? context.l10n.govor,
                    style: const TextStyle(
                      fontFamily: 'GovorDisplay',
                      fontSize: 31,
                    ),
                  ),
                ),
                Glass(
                  radius: 26,
                  child: IconButton(
                    tooltip: context.l10n.searchConversations,
                    onPressed: () =>
                        setState(() => _searchingChats = !_searchingChats),
                    icon: const Icon(Icons.search_rounded, size: 27),
                  ),
                ),
                const SizedBox(width: 8),
                Glass(
                  radius: 26,
                  child: IconButton(
                    tooltip: context.l10n.settings,
                    onPressed: _settings,
                    icon: const Icon(Icons.settings_outlined, size: 25),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: wide
              ? Glass(padding: const EdgeInsets.all(10), child: body)
              : body,
        ),
        if (!wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            child: Glass(
              radius: 28,
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  for (final (index, label) in [
                    context.l10n.chats,
                    context.l10n.contacts,
                  ].indexed)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(25),
                        onTap: () => setState(() => _homeTab = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: _homeTab == index
                                ? const Color(0xFF65558A).withValues(alpha: .85)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                index == 0
                                    ? Icons.forum_rounded
                                    : Icons.people_rounded,
                                size: 25,
                                color: _homeTab == index ? Colors.white : muted,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: _homeTab == index
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _homeTab == index
                                      ? Colors.white
                                      : muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _chatList(bool wide) {
    final query = _search.text.toLowerCase().trim();
    final chats = c.conversations
        .where(
          (chat) =>
              ((_filter == 1 && chat.type == 0) ||
                  (_filter == 2 && chat.type == 1)) &&
              (chat.title.toLowerCase().contains(query) ||
                  c.preview(chat).toLowerCase().contains(query)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 0, 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.me?.name ?? context.l10n.govor,
                    style: const TextStyle(
                      fontFamily: 'GovorDisplay',
                      fontSize: 29,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.searchConversations,
                  onPressed: () =>
                      setState(() => _searchingChats = !_searchingChats),
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
        GlassSegments(
          labels: [context.l10n.friends, context.l10n.groups],
          selected: _filter - 1,
          onChanged: (v) => setState(() => _filter = v + 1),
        ),
        if (_searchingChats)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Glass(
              child: TextField(
                key: const Key('chat-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.l10n.findAConversation,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.l10n.clearSearch,
                          onPressed: () => setState(_search.clear),
                          icon: const Icon(Icons.close_rounded, size: 17),
                        ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (_filter == 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              radius: 24,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => openFeaturePage(
                        context,
                        c,
                        GroupExplorePage(controller: c),
                      ),
                      child: Text(context.l10n.findOrCreate),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.refreshGroups,
                    onPressed: c.refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: chats.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.forum_outlined,
                          color: muted,
                          size: 36,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          query.isEmpty
                              ? context.l10n.yourConversationsWillAppearHere
                              : context.l10n.nothingFound,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: muted),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => setState(() => _homeTab = 1),
                          child: Text(context.l10n.findFriends),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: chats.length,
                  itemBuilder: (context, index) =>
                      _conversationTile(chats[index]),
                ),
        ),
        if (!c.demo && c.connection != ConnectionStatus.connected)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              c.connection == ConnectionStatus.reconnecting
                  ? context.l10n.reconnecting
                  : context.l10n.connecting,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ),
        if (c.error != null && c.selected == null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: ErrorNotice(c.error!, onDismiss: c.clearError),
          ),
      ],
    );
  }

  Widget _conversationTile(Conversation chat) {
    final active = c.selected?.key == chat.key;
    final unread = c.unread[chat.key] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? primary.withValues(alpha: .19) : Colors.transparent,
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: () => c.open(chat),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: active
                    ? accent.withValues(alpha: .16)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                PreviewAvatar(
                  chat.title,
                  controller: c,
                  imageId: chat.iconId,
                  size: 48,
                  online: chat.online,
                  group: chat.type == 1,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'GovorDisplay',
                                fontSize: 22,
                              ),
                            ),
                          ),
                          if (chat.isChannel)
                            const Icon(
                              Icons.campaign_outlined,
                              size: 14,
                              color: muted,
                            ),
                        ],
                      ),
                      if (chat.peerId != null)
                        UserBadge(controller: c, userId: chat.peerId!),
                      const SizedBox(height: 5),
                      Text(
                        c.preview(chat),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? const Color(0xFFBBB4ED) : muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyChat() => Glass(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 88),
            const SizedBox(height: 30),
            Text(
              context.l10n.aGoodConversationNstartsHere,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.25,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.chooseAChatToFeelCloserNprivateStaysPrivate,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 14, height: 1.8),
            ),
            const SizedBox(height: 28),
            _SecurityPill(label: context.l10n.endToEndEncryption),
            const SizedBox(height: 38),
            Text(
              'ANDROID  /  WINDOWS  /  LINUX  /  WEB',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.6,
                color: muted.withValues(alpha: .6),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _chat(bool wide) {
    final chat = c.selected!;
    final query = _messageSearch.text.toLowerCase().trim();
    final visible = query.isEmpty
        ? c.messages
        : c.messages
              .where((m) => m.text?.toLowerCase().contains(query) ?? false)
              .toList();
    final content = Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF181B27).withValues(alpha: .24),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: .14)),
          ),
          child: Row(
            children: [
              if (!wide)
                IconButton(
                  key: const Key('back-to-chats'),
                  tooltip: context.l10n.backToChats,
                  onPressed: c.closeChat,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              PreviewAvatar(
                chat.title,
                controller: c,
                imageId: chat.iconId,
                size: 42,
                online: chat.online,
                group: chat.type == 1,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: chat.type == 1
                          ? () => openFeaturePage(
                              context,
                              c,
                              GroupProfilePage(controller: c, groupId: chat.id),
                            )
                          : chat.peerId == null
                          ? null
                          : () => showUserProfile(context, c, chat.peerId!),
                      child: Text(
                        _selectedIds.isEmpty
                            ? chat.title
                            : context.l10n.selectedCount(_selectedIds.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'GovorDisplay',
                          fontSize: 23,
                        ),
                      ),
                    ),
                    if (chat.peerId != null)
                      UserBadge(controller: c, userId: chat.peerId!),
                    const SizedBox(height: 4),
                    Text(
                      chat.type == 1
                          ? (chat.isChannel
                                ? context.l10n.channel
                                : context.l10n.communityLabel)
                          : chat.online
                          ? context.l10n.online
                          : context.l10n.privateChat,
                      style: TextStyle(
                        color: chat.online ? const Color(0xFF89CEB2) : muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (_selectedIds.isNotEmpty) ...[
                IconButton(
                  tooltip: context.l10n.copySelected,
                  onPressed: _copySelected,
                  icon: const Icon(Icons.copy_outlined, size: 20),
                ),
                IconButton(
                  tooltip: context.l10n.forwardSelected,
                  onPressed: _forwardSelected,
                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 20),
                ),
                IconButton(
                  tooltip: context.l10n.clearSelection,
                  onPressed: () => setState(_selectedIds.clear),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                tooltip: context.l10n.searchLoadedHistory,
                onPressed: () =>
                    setState(() => _searchingMessages = !_searchingMessages),
                icon: const Icon(Icons.search_rounded, size: 21),
              ),
              PopupMenuButton<String>(
                tooltip: context.l10n.chatActions,
                onSelected: (value) {
                  if (value == 'read') {
                    _action(c.markRead);
                  }
                  if (value == 'refresh') {
                    _action(c.refresh);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'read',
                    child: Text(context.l10n.markAsRead),
                  ),
                  PopupMenuItem(
                    value: 'refresh',
                    child: Text(context.l10n.refreshHistory),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_searchingMessages)
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _messageSearch,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.l10n.searchLoadedMessages,
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: context.l10n.closeSearch,
                  onPressed: () => setState(() {
                    _searchingMessages = false;
                    _messageSearch.clear();
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ErrorNotice(c.error!, onDismiss: c.clearError),
          ),
        if (c.loadingMessages)
          const LinearProgressIndicator(
            minHeight: 2,
            color: accent,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    c.loadingMessages
                        ? context.l10n.openingHistory
                        : query.isNotEmpty
                        ? context.l10n.noMessagesFound
                        : context.l10n.sayHello,
                    style: const TextStyle(color: muted),
                  ),
                )
              : ListView.builder(
                  key: ValueKey(chat.key),
                  controller: _scroll,
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 28 : 14,
                    vertical: 18,
                  ),
                  itemCount: visible.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        children: [
                          if (!c.demo && c.hasOlder && query.isEmpty)
                            TextButton(
                              onPressed: c.loadingMessages ? null : c.loadOlder,
                              child: Text(context.l10n.loadEarlierMessages),
                            ),
                          const SizedBox(height: 10),
                        ],
                      );
                    }
                    final message = visible[index - 1];
                    final previous = index > 1 ? visible[index - 2] : null;
                    final local = message.sentAt.toLocal();
                    final dateBreak =
                        previous == null ||
                        DateUtils.dateOnly(previous.sentAt.toLocal()) !=
                            DateUtils.dateOnly(local);
                    return Column(
                      children: [
                        if (dateBreak)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18, top: 4),
                            child: Text(
                              '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                          ),
                        _bubble(message),
                      ],
                    );
                  },
                ),
        ),
        if (c.pending != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 15, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.pendingAcknowledgment,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ),
                TextButton(
                  onPressed:
                      c.sending ||
                          (!c.demo &&
                              c.connection != ConnectionStatus.connected)
                      ? null
                      : () {
                          _composer.text = c.pending!.text;
                          _send();
                        },
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        if (c.uploading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (c.selectedAttachments.isNotEmpty && c.media != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
            child: AttachmentPreview(
              attachments: c.selectedAttachments,
              repository: c.media!,
              onSave: c.downloadFile,
              onRemove: c.pending != null || c.sending
                  ? null
                  : c.removeAttachment,
            ),
          ),
        if (_reply != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.reply_rounded, size: 19, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _reply!.text ?? context.l10n.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.cancelReply,
                  onPressed: () => setState(() => _reply = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: chat.canPost
              ? Glass(
                  radius: 21,
                  padding: const EdgeInsets.fromLTRB(16, 3, 5, 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: IconButton(
                          tooltip: c.demo
                              ? context.l10n.connectToTheServerToAttachFiles
                              : context.l10n.attachAFileUpTo19Mb,
                          onPressed:
                              c.demo ||
                                  c.uploading ||
                                  c.sending ||
                                  c.pending != null
                              ? null
                              : () => _action(c.attachFile),
                          icon: const Icon(Icons.add_rounded, size: 27),
                        ),
                      ),
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              control: true,
                            ): _send,
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              meta: true,
                            ): _send,
                          },
                          child: TextField(
                            key: const Key('message-composer'),
                            style: TextStyle(fontSize: 14),
                            controller: _composer,
                            focusNode: _composerFocus,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 20000,
                            decoration: InputDecoration(
                              hintText: context.l10n.messageLabel,
                              filled: false,
                              counterText: '',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: IconButton.filled(
                          key: const Key('send-message'),
                          tooltip: context.l10n.sendCtrlEnter,
                          style: IconButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                          ),
                          onPressed:
                              c.sending ||
                                  c.uploading ||
                                  (!c.demo &&
                                      c.connection !=
                                          ConnectionStatus.connected)
                              ? null
                              : _send,
                          icon: c.sending
                              ? const SizedBox(
                                  width: 21,
                                  height: 21,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    context.l10n.onlyChannelAdministratorsCanPost,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
        ),
      ],
    );
    return wide
        ? Glass(
            tint: const Color(0xFF101521).withValues(alpha: .12),
            child: content,
          )
        : content;
  }

  Widget _bubble(ChatMessage message) => MessageBubble(
    message: message,
    controller: c,
    selectedIds: _selectedIds,
    onToggle: (id) => setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    }),
    onActions: _messageActions,
    onSave: (attachment) => _action(() => c.downloadFile(attachment)),
    onReact: (message, id) => _action(() => c.react(message, id)),
  );

  Future<void> _messageActions(ChatMessage m, {Offset? position}) async {
    if (_messageActionsOpen) return;
    _messageActionsOpen = true;
    String? action;
    try {
      action = await showMessageActions(context, c, m, position: position);
    } finally {
      _messageActionsOpen = false;
    }
    if (!mounted || action == null) return;
    if (action == 'removeReaction') await _action(() => c.react(m, null));
    if (action == 'select') {
      setState(() => _selectedIds.add(m.id));
    }
    if (action == 'forward') {
      await _forward([m]);
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text!));
    }
    if (action == 'reply') {
      setState(() => _reply = m);
      _composerFocus.requestFocus();
    }
    if (!mounted) return;
    if (action == 'edit') {
      final value = await _textDialog(
        context,
        context.l10n.editMessage,
        m.text ?? '',
      );
      if (value != null) await _action(() => c.edit(m, value));
    }
    if (action == 'delete') {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.deleteMessage),
          content: Text(context.l10n.theMessageWillBeDeletedForAllParticipants),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.delete),
            ),
          ],
        ),
      );
      if (confirm == true) await _action(() => c.remove(m));
    }
  }

  Future<void> _copySelected() async {
    await Clipboard.setData(
      ClipboardData(
        text: c.messages
            .where((m) => _selectedIds.contains(m.id) && m.text != null)
            .map((m) => m.text!)
            .join('\n\n'),
      ),
    );
  }

  Future<void> _forwardSelected() async =>
      _forward(c.messages.where((m) => _selectedIds.contains(m.id)).toList());
  Future<void> _forward(List<ChatMessage> messages) async {
    if (messages.any((m) => m.failure != null || m.text == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.selectTextMessagesToForward)),
      );
      return;
    }
    final target = await showDialog<Conversation>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.forwardToChat),
        content: SizedBox(
          width: 440,
          height: 360,
          child: ListView(
            children: [
              for (final chat in c.conversations.where((chat) => chat.canPost))
                ListTile(
                  title: Text(chat.title),
                  onTap: () => Navigator.pop(context, chat),
                ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    for (final message in messages) {
      if (!await c.forwardMessage(message, target)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(c.error ?? context.l10n.couldNotOpenChat)),
          );
        }
        return;
      }
      if (mounted) setState(() => _selectedIds.remove(message.id));
    }
    await c.open(target);
  }
}

class _SecurityPill extends StatelessWidget {
  const _SecurityPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .065),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: .1)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 11, color: accent),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label, style: const TextStyle(fontSize: 9, color: muted)),
        ),
      ],
    ),
  );
}

Future<String?> _textDialog(
  BuildContext context,
  String title,
  String initial,
) async {
  final input = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: input,
          autofocus: true,
          maxLines: 6,
          minLines: 2,
          maxLength: 20000,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (input.text.trim().isNotEmpty) {
              Navigator.pop(context, input.text.trim());
            }
          },
          child: Text(context.l10n.save),
        ),
      ],
    ),
  );
  // Dialog reverse transitions can still reference its controller in this frame.
  WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  return result;
}
