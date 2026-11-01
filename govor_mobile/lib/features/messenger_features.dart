part of 'messenger_controller.dart';

extension MessengerFeatures on MessengerController {
  Future<ChatMessage?> replyPreview(ChatMessage message) async {
    if (message.replyTo == null) return null;
    final key = '${message.type}/${message.conversationId}';
    final cached = (_cache[key] ?? messages)
        .where(
          (m) =>
              m.id == message.replyTo &&
              m.conversationId == message.conversationId &&
              m.type == message.type,
        )
        .firstOrNull;
    if (cached != null) return cached;
    if (demo) return null;
    final generation = _generation;
    try {
      final raw = object(
        await api!.request('GET', '/api/messages/${message.replyTo}'),
      );
      final original = ChatMessage.fromJson(raw);
      requireCrypto(
        original.id == message.replyTo &&
            original.conversationId == message.conversationId &&
            original.type == message.type,
        'Ответ относится к другому чату.',
      );
      final decoded = await encryption!.decrypt(original);
      return generation == _generation ? decoded : null;
    } on ApiFailure catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  Future<bool> forwardMessage(ChatMessage source, Conversation target) async {
    if (sending ||
        uploading ||
        !target.canPost ||
        source.text == null ||
        source.failure != null) {
      return false;
    }
    final generation = _generation;
    final pending = _pending[target.key];
    if (pending != null) {
      if (pending.forwardedFrom != source.id) {
        error = 'Сначала подтвердите предыдущее сообщение в этом чате.';
        _notify();
        return false;
      }
      return _sendTo(
        target,
        pending.text,
        forwardedFrom: pending.forwardedFrom,
      );
    }
    uploading = true;
    _notify();
    final files = <Json>[];
    try {
      for (final json in source.attachments) {
        final old = Attachment.fromJson(json);
        // Never reuse source IDs or encryption keys in another chat.
        final bytes = await media!.load(old);
        if (generation != _generation) return false;
        files.add((await media!.upload(bytes, old.name)).toJson());
        if (generation != _generation) return false;
      }
    } catch (e) {
      if (generation == _generation) error = safeError(e);
      return false;
    } finally {
      if (generation == _generation) {
        uploading = false;
        _notify();
      }
    }
    if (generation != _generation) return false;
    return _sendTo(
      target,
      source.text!,
      forwardedFrom: source.id,
      files: files,
    );
  }

  bool get isAdmin {
    final claims = api?.tokens?.claims;
    final roles =
        claims?['role'] ??
        claims?['roles'] ??
        claims?['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'];
    return roles == 'Admin' || roles is List && roles.contains('Admin');
  }

  void watchBenefits(String id) {
    _visibleBenefits[id] = (_visibleBenefits[id] ?? 0) + 1;
    if (_visibleBenefits[id] == 1) unawaited(loadBenefits(id));
  }

  void unwatchBenefits(String id) {
    final count = (_visibleBenefits[id] ?? 1) - 1;
    if (count <= 0) {
      _visibleBenefits.remove(id);
    } else {
      _visibleBenefits[id] = count;
    }
  }

  Future<void> loadBenefits(String id) async {
    if (demo || api == null || !validId(id) || !_benefitsLoading.add(id)) {
      return;
    }
    final generation = _generation;
    try {
      final value = await UserBenefitsRepository(api!).load(id);
      if (generation == _generation) benefits.apply(id, value);
    } catch (_) {
      /* A failed badge fetch does not disrupt the conversation. */
    } finally {
      if (generation == _generation) _benefitsLoading.remove(id);
    }
  }

  Future<void> refreshVisibleBenefits() async {
    final ids = _visibleBenefits.keys.toList();
    for (var i = 0; i < ids.length; i += 8) {
      await Future.wait(ids.skip(i).take(8).map(loadBenefits));
    }
  }

  Future<void> saveProfileTag(ProfileTag? tag) async {
    if (!(benefits[userId] ?? me?.benefits ?? const UserBenefits())
        .canCustomizeProfileTag) {
      throw const ApiFailure(403, 'Недостаточно прав для изменения тега.');
    }
    final generation = _generation, id = userId;
    final value = await UserBenefitsRepository(api!).saveTag(tag);
    if (generation == _generation) benefits.apply(id, value);
  }

  Future<void> setUserPrivileges(String id, int privileges) async {
    if (!isAdmin) throw const ApiFailure(403, 'Недостаточно прав.');
    final generation = _generation;
    final value = await UserBenefitsRepository(
      api!,
    ).setPrivileges(id, privileges);
    if (generation == _generation) benefits.apply(id, value);
  }

  Future<void> loadAvatar(String id) async {
    if (demo ||
        !validId(id) ||
        avatarBytes.containsKey(id) ||
        !_avatarDownloads.add(id)) {
      return;
    }
    final generation = _generation;
    try {
      final data = await api!.downloadAttachment(id, maxBytes: 4000000);
      if (generation != _generation) return;
      if (avatarBytes.length >= 64) avatarBytes.remove(avatarBytes.keys.first);
      avatarBytes[id] = data;
      _notify();
    } catch (_) {
      /* Keep initials when an avatar is unavailable. */
    } finally {
      _avatarDownloads.remove(id);
    }
  }

  Future<Person> person(String id) async {
    if (id == userId) return me!;
    for (final p in friends) {
      if (p.id == id) return p;
    }
    if (demo) return Person(id: id, name: 'Говор');
    if (_people.length >= 128) _people.remove(_people.keys.first);
    final generation = _generation;
    return _people.putIfAbsent(id, () async {
      try {
        final p = Person.fromJson(
          object(await api!.request('GET', '/api/profile/download/$id')),
        );
        if (generation != _generation) {
          throw const ApiFailure(0, 'Сессия завершена.');
        }
        benefits.apply(p.id, p.benefits);
        if (validId(p.iconId)) unawaited(loadAvatar(p.iconId!));
        return p;
      } catch (_) {
        if (generation == _generation) _people.remove(id);
        rethrow;
      }
    });
  }

  Future<void> updateAvatar() async {
    if (demo) return;
    final file = await pickAttachment();
    if (file == null) return;
    final id = await api!.uploadProfileAvatar(file.data, fileMime(file.data));
    if (profileHub?.status == ConnectionStatus.connected) {
      await profileHub!.invoke('SetAvatar', [id]);
    }
    me = Person(
      id: me!.id,
      name: me!.name,
      description: me!.description,
      iconId: id,
      online: me!.online,
      benefits: benefits[me!.id] ?? me!.benefits,
    );
    await loadAvatar(id);
    _notify();
  }

  Future<void> revokeSession(String id) async {
    if (id == api?.tokens?.session) {
      await logout();
      return;
    }
    await api!.request('DELETE', '/api/session/close/$id');
  }

  void applyReactions(Json state) {
    final id = state['messageId'] as String;
    final old = reactionStates[id];
    final version = state['version'] as int;
    if (old != null && (old['version'] as int) > version) return;
    final mine = state['actorId'] == userId
        ? state['actorReaction']
        : old?['mine'];
    reactionStates[id] = {...state, 'mine': mine};
    _notify();
  }

  void applyHistoryReactions(Json message) {
    final reactions = objects(message['reactions'] ?? []);
    final counts = <String, Json>{};
    Json? mine;
    for (final r in reactions) {
      final key = r['reactionId'] as String? ?? r['reactionCode'] as String;
      counts.putIfAbsent(
        key,
        () => {
          'reactionId': r['reactionId'],
          'reactionCode': r['reactionCode'],
          'count': 0,
        },
      );
      counts[key]!['count'] = (counts[key]!['count'] as int) + 1;
      if (r['userId'] == userId) mine = r;
    }
    applyReactions({
      'messageId': message['id'] ?? message['messageId'],
      'recipientId': message['recipientId'],
      'recipientType': message['recipientType'],
      'version': message['reactionsVersion'] ?? 0,
      'actorId': userId,
      'actorReaction': mine,
      'counts': counts.values.toList(),
    });
  }

  Future<void> react(ChatMessage message, String? reactionId) async {
    if (!_reacting.add(message.id)) return;
    final generation = _generation;
    try {
      final mine = reactionStates[message.id]?['mine'];
      if (mine is Map && mine['reactionId'] == reactionId) reactionId = null;
      if (demo) {
        final emoji = reactionId == null
            ? null
            : demoEmoji[int.parse(reactionId.split('-').last)];
        applyReactions({
          'messageId': message.id,
          'recipientId': message.conversationId,
          'recipientType': message.type,
          'version': (reactionStates[message.id]?['version'] as int? ?? 0) + 1,
          'actorId': userId,
          'actorReaction': reactionId == null
              ? null
              : {'reactionId': reactionId, 'reactionCode': emoji},
          'counts': reactionId == null
              ? <Json>[]
              : [
                  {'reactionId': reactionId, 'reactionCode': emoji, 'count': 1},
                ],
        });
        return;
      }
      final result = object(
        await api!.request(
          reactionId == null ? 'DELETE' : 'PUT',
          '/api/messages/${message.id}/reactions/me',
          body: reactionId == null ? null : {'reactionId': reactionId},
        ),
      );
      if (generation == _generation) applyReactions(result);
    } finally {
      if (generation == _generation) _reacting.remove(message.id);
    }
  }

  Future<Json> reactionDefinition(String id) {
    if (_reactionDefinitions.length >= 128) {
      _reactionDefinitions.remove(_reactionDefinitions.keys.first);
    }
    return _reactionDefinitions.putIfAbsent(
      id,
      () => dependencies.createReactions(api!).definition(id).catchError((
        Object e,
      ) {
        _reactionDefinitions.remove(id);
        throw e;
      }),
    );
  }

  Future<Uint8List> reactionImage(String id) {
    if (_reactionImages.length >= 32) {
      _reactionImages.remove(_reactionImages.keys.first);
    }
    return _reactionImages.putIfAbsent(
      id,
      () =>
          api!.downloadAttachment(id, maxBytes: 600000).catchError((Object e) {
            _reactionImages.remove(id);
            throw e;
          }),
    );
  }

  static const demoEmoji = [
    '👍',
    '👎',
    '❤️',
    '🔥',
    '🥰',
    '👏',
    '😁',
    '🤔',
    '😢',
    '🎉',
    '🤯',
    '🙏',
  ];
  Future<List<Json>> reactionPacks({bool mine = true}) async {
    if (demo) {
      return [
        {
          'id': 'demo-emoji',
          'name': 'Emoji',
          'description': 'Базовый пак реакций',
          'isDefault': true,
          'shareCode': 'demo',
          'reactions': [
            for (final (i, emoji) in demoEmoji.indexed)
              {
                'id': 'demo-reaction-$i',
                'name': emoji,
                'emoji': emoji,
                'code': emoji,
                'kind': 0,
                'isEnabled': true,
              },
          ],
        },
      ];
    }
    return dependencies.createReactions(api!).packs(mine: mine);
  }

  Future<Json> channelReactionPolicy(String id) =>
      dependencies.createReactions(api!).policy(id);
  Future<Json> updateChannelReactionPolicy(String id, Json policy) =>
      dependencies.createReactions(api!).updatePolicy(id, policy);

  Future<List<Json>> reactionChoices({Conversation? conversation}) async {
    final chat = conversation ?? selected;
    if (demo || chat?.isChannel != true) return reactionPacks();
    final policy = await dependencies.createReactions(api!).policy(chat!.id);
    final mode = policy['mode'] as int;
    if (mode == 0) return reactionPacks();
    final allowed = (policy['reactionIds'] as List).cast<String>().toSet();
    final reactions = <Json>[];
    if (mode == 2) {
      // A public reaction may be used without installing its pack. Resolve only
      // the allowed IDs instead of downloading the user's entire catalog.
      final ids = allowed.toList();
      for (var i = 0; i < ids.length; i += 8) {
        final definitions = await Future.wait(
          ids.skip(i).take(8).map(reactionDefinition),
        );
        reactions.addAll(definitions.where((r) => r['isEnabled'] != false));
      }
    }
    return [
      {'id': 'channel-reactions', 'name': 'channel', 'reactions': reactions},
    ];
  }

  Future<Json> sharedPack(String code) =>
      dependencies.createReactions(api!).shared(code);
  Future<void> subscribePack(String id, bool subscribe) async {
    if (!demo) {
      await dependencies.createReactions(api!).subscribe(id, subscribe);
    }
  }

  Future<List<Json>> searchGroups(String query) async {
    if (demo) {
      return [
        for (final c in conversations.where((c) => c.type == 1))
          {
            'id': c.id,
            'name': c.title,
            'description': c.subtitle,
            'isChannel': c.isChannel,
            'myRole': c.role ?? 0,
            'memberCount': 3,
            'canLeave': c.canLeave,
            'isPrivate': false,
          },
      ];
    }
    return loadApiPages(api!, '/api/groups/search', query: {'q': query.trim()});
  }

  Future<Json> group(String id) async {
    if (demo) return (await searchGroups('')).firstWhere((g) => g['id'] == id);
    return object(await api!.request('GET', '/api/groups/$id'));
  }

  Future<void> joinGroup(String id) async {
    if (!demo) await api!.request('POST', '/api/groups/$id/join');
    await refresh();
  }

  Future<void> createGroup(
    String name,
    String description,
    bool private,
    bool channel,
  ) async {
    if (name.trim().isEmpty ||
        name.trim().length > 100 ||
        description.length > 500) {
      throw const ApiFailure(0, 'Проверьте название и описание.');
    }
    if (demo) {
      conversations = [
        ...conversations,
        Conversation(
          id: newId(),
          title: name.trim(),
          type: 1,
          subtitle: description,
          isChannel: channel,
          role: 2,
          canLeave: false,
        ),
      ];
      _notify();
      return;
    }
    final created = object(
      await api!.request(
        'POST',
        '/api/groups',
        body: {
          'name': name.trim(),
          'description': description,
          'isPrivate': private,
          'isChannel': channel,
        },
      ),
    );
    await refresh();
    await open(conversations.firstWhere((c) => c.id == created['id']));
  }

  Future<void> updateGroup(
    String id,
    String name,
    String description,
    bool private,
  ) async {
    await api!.request(
      'PUT',
      '/api/groups/$id',
      body: {
        'name': name.trim(),
        'description': description,
        'isPrivate': private,
      },
    );
    await refresh();
  }

  Future<void> leaveGroup(String id) async {
    await api!.request('DELETE', '/api/groups/$id/members/me');
    await refresh();
  }

  Future<List<Json>> members(String id, {bool banned = false}) async {
    if (demo) {
      return [
        {'userId': userId, 'username': me!.name, 'role': 2, 'isBanned': false},
        for (final f in friends)
          {'userId': f.id, 'username': f.name, 'role': 0, 'isBanned': false},
      ];
    }
    return loadApiPages(
      api!,
      '/api/groups/$id/members',
      query: {'bannedOnly': '$banned'},
    );
  }

  Future<void> memberAction(
    String groupId,
    String user,
    String action,
    bool enable,
  ) async {
    await api!.request(
      enable ? 'PUT' : 'DELETE',
      '/api/groups/$groupId/members/$user/$action',
    );
    await refresh();
  }

  Future<void> transferGroup(String groupId, String user) async {
    await api!.request('POST', '/api/groups/$groupId/ownership/$user');
    await refresh();
  }

  Future<void> updateGroupAvatar(String id) async {
    final revision = _generation;
    final file = await pickAttachment(
      maxBytes: 2 * 1024 * 1024,
      title: 'Аватарка сообщества — PNG, JPEG, WebP',
    );
    if (file == null || revision != _generation) return;
    await api!.uploadGroupAvatar(id, file.data);
    if (revision != _generation) return;
    await refresh();
  }

  Future<void> removeGroupAvatar(String id) async {
    final revision = _generation;
    await api!.request('DELETE', '/api/groups/$id/avatar');
    if (revision == _generation) await refresh();
  }

  Future<Json> createGroupInvite(
    String id,
    GroupInvitationOptions options,
  ) async => object(
    await api!.request(
      'POST',
      '/api/groups/$id/invitations',
      body: options.toJson(),
    ),
  );
  Future<List<Json>> groupInvites(String id) async =>
      objects(await api!.request('GET', '/api/groups/$id/invitations'));
  Future<void> revokeGroupInvite(String id, String invitation) async {
    await api!.request('DELETE', '/api/groups/$id/invitations/$invitation');
  }

  String parseInvite(String input) {
    final uri = Uri.tryParse(input.trim());
    final code = uri != null && uri.hasScheme
        ? uri.pathSegments.lastOrNull ?? ''
        : input.trim();
    if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(code)) {
      throw const ApiFailure(0, 'Введите код или ссылку приглашения Govor.');
    }
    return code.toLowerCase();
  }

  Future<Json> previewInvite(String input) async => object(
    await api!.request('GET', '/api/group-invites/${parseInvite(input)}'),
  );
  Future<void> joinInvite(String input) async {
    await api!.request('POST', '/api/group-invites/${parseInvite(input)}/join');
    await refresh();
  }
}
