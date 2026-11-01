import 'avatar_preview.dart';
import 'user_badge.dart';
import '../l10n/l10n.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../features/messenger_controller.dart';
import 'design.dart';

import 'feature_shared.dart';
import 'user_profile_dialog.dart';

class ContactsPane extends StatefulWidget {
  const ContactsPane({super.key, required this.controller});
  final MessengerController controller;
  @override
  State<ContactsPane> createState() => _ContactsPaneState();
}

class _ContactsPaneState extends State<ContactsPane>
    with PageActions<ContactsPane> {
  @override
  MessengerController get controller => widget.controller;
  final _query = TextEditingController();
  int _tab = 2;
  List<Person> _results = [];
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() => run(() async {
    _results = await controller.searchPeople(_query.text);
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      GlassSegments(
        labels: [
          context.l10n.incoming,
          context.l10n.pending,
          context.l10n.search,
        ],
        selected: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      const SizedBox(height: 20),
      if (_tab == 2)
        Glass(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: muted),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: context.l10n.usernameOrUserId,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.pasteIdFromClipboard,
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (mounted) {
                    _query.text = data?.text ?? '';
                    _search();
                  }
                },
                icon: const Icon(Icons.content_paste_rounded, size: 20),
              ),
              IconButton(
                tooltip: context.l10n.find,
                onPressed: working ? null : _search,
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              ),
            ],
          ),
        ),
      const SizedBox(height: 12),
      feedback,
      Expanded(
        child: _tab == 2
            ? _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🔎', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 16),
                          Text(
                            _query.text.trim().isEmpty
                                ? context.l10n.enterAFriendSNameToSearch
                                : context.l10n.nothingFound,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      children: [
                        for (final p in _results.where(
                          (p) => p.id != controller.userId,
                        ))
                          _person(p),
                      ],
                    )
            : ListView(
                children: [
                  for (final request
                      in _tab == 0
                          ? controller.requests
                          : controller.outgoingRequests)
                    _request(request),
                  if ((_tab == 0
                          ? controller.requests
                          : controller.outgoingRequests)
                      .isEmpty)
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          context.l10n.noRequestsYet,
                          style: TextStyle(color: muted),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
  Widget _person(Person p) {
    final friend = controller.friends.any((f) => f.id == p.id);
    return GlassCard(
      child: Row(
        children: [
          PreviewAvatar(
            p.name,
            controller: controller,
            imageId: p.iconId,
            size: 42,
            online: p.online,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => showUserProfile(context, controller, p.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'GovorDisplay',
                        fontSize: 22,
                      ),
                    ),
                    UserBadge(
                      controller: controller,
                      userId: p.id,
                      fallback: p.benefits,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: friend ? context.l10n.openChat : context.l10n.openProfile,
            onPressed: working
                ? null
                : () => run(() async {
                    if (friend) {
                      await controller.chatWith(p);
                    } else {
                      await showUserProfile(context, controller, p.id);
                    }
                  }),
            icon: Icon(
              friend
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.person_add_alt_1_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _request(Json request) {
    final user =
        (_tab == 0 ? request['requesterId'] : request['addresseeId']) as String;
    return GlassCard(
      child: FutureBuilder<Person>(
        future: controller.person(user),
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => showUserProfile(context, controller, user),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  state.data?.name ?? context.l10n.user,
                  style: const TextStyle(
                    fontFamily: 'GovorDisplay',
                    fontSize: 22,
                  ),
                ),
              ),
            ),
            if (_tab == 0)
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: working
                          ? null
                          : () => run(
                              () => controller.acceptRequest(
                                request['id'] as String,
                              ),
                            ),
                      child: Text(context.l10n.accept),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: working
                          ? null
                          : () => run(
                              () => controller.acceptRequest(
                                request['id'] as String,
                                accept: false,
                              ),
                            ),
                      child: Text(context.l10n.decline),
                    ),
                  ),
                ],
              )
            else
              Text(switch (request['status']) {
                2 => context.l10n.requestDeclined,
                3 => context.l10n.requestUnavailable,
                _ => context.l10n.waitingForAReply,
              }, style: const TextStyle(color: muted)),
          ],
        ),
      ),
    );
  }
}

class ContactsPage extends StatelessWidget {
  const ContactsPage({super.key, required this.controller});
  final MessengerController controller;
  @override
  Widget build(BuildContext context) => GlassPage(
    title: context.l10n.contacts,
    child: ContactsPane(controller: controller),
  );
}
