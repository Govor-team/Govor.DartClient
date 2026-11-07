import 'package:govor_mobile/core/group_invitation.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:http/http.dart' as http;
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/chat_hub.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'support/auth_fixtures.dart' show testUser;

import 'support/messenger_fixture.dart';

void main() {
  test(
    'group management, invitations and channel policies follow the documented HTTP contract',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      const code = 'abcdef0123456789abcdef0123456789';
      var mode = 2, removed = false;
      final pack = <String, dynamic>{
        'id': 'pack',
        'name': 'Emoji',
        'reactions': [
          {'id': 'a', 'name': 'A', 'isEnabled': true},
          {'id': 'b', 'name': 'B', 'isEnabled': true},
        ],
      };
      http.Response json(Object value) => http.Response(jsonEncode(value), 200);
      f.overrideResponse = (request) {
        final path = request.url.path;
        if (path == '/api/groups/mine' && removed) return json(<Json>[]);
        if (path == '/api/groups' && request.method == 'POST') {
          return json({'id': group});
        }
        if (path == '/api/groups/search') {
          return json([
            {'id': group, 'name': 'Group'},
          ]);
        }
        if (path == '/api/groups/$group') {
          return request.method == 'GET'
              ? json({'id': group, 'name': 'Group'})
              : http.Response('', 204);
        }
        if (path == '/api/groups/$group/members') {
          return json([
            {'userId': peer, 'username': 'Peer', 'role': 0},
          ]);
        }
        if (path == '/api/groups/$group/invitations') {
          return json(
            request.method == 'GET'
                ? <Json>[
                    {'id': 'invite', 'code': code},
                  ]
                : {'id': 'invite', 'code': code},
          );
        }
        if (path == '/api/group-invites/$code') {
          return json({'groupId': group, 'name': 'Group'});
        }
        if (path == '/api/reaction-packs/mine') return json([pack]);
        if (path == '/api/reaction-packs/shared/valid') return json(pack);
        if (path == '/api/reactions/a') {
          return json({'id': 'a', 'kind': 0, 'emoji': 'A'});
        }
        if (path == '/api/groups/$group/reactions') {
          if (request.method == 'PUT') {
            mode = object(jsonDecode(request.body))['mode'] as int;
          }
          return json({
            'groupId': group,
            'version': 1,
            'mode': mode,
            'reactionIds': mode == 2 ? ['a'] : <String>[],
          });
        }
        if (path == '/api/groups/$group/members/me') removed = true;
        if ((path.startsWith('/api/groups/') && request.method != 'GET') ||
            path.endsWith('/subscription') ||
            path.endsWith('/join')) {
          return http.Response('', 204);
        }
        return null;
      };
      await f.boot();
      await expectLater(
        f.controller.createGroup('', '', false, false),
        throwsA(isA<ApiFailure>()),
      );
      await f.controller.createGroup(
        ' Group ',
        '**Description**',
        false,
        false,
      );
      expect(f.controller.selected!.id, group);
      expect((await f.controller.searchGroups('G')).single['id'], group);
      expect((await f.controller.group(group))['name'], 'Group');
      expect((await f.controller.members(group)).single['userId'], peer);
      await f.controller.updateGroup(group, 'New', 'Description', true);
      await f.controller.memberAction(group, peer, 'administrator', true);
      await f.controller.memberAction(group, peer, 'ban', false);
      await f.controller.transferGroup(group, peer);
      expect(
        (await f.controller.createGroupInvite(
          group,
          const GroupInvitationOptions(),
        ))['code'],
        code,
      );
      expect(await f.controller.groupInvites(group), hasLength(1));
      await f.controller.revokeGroupInvite(group, 'invite');
      expect(
        f.controller.parseInvite('https://test.example/invite/$code'),
        code,
      );
      expect((await f.controller.previewInvite(code))['groupId'], group);
      await f.controller.joinInvite(code);
      await f.controller.open(
        const Conversation(
          id: group,
          title: 'Channel',
          type: 1,
          isChannel: true,
        ),
      );
      expect(
        objects(
          (await f.controller.reactionChoices()).single['reactions'],
        ).single['id'],
        'a',
      );
      await f.controller.updateChannelReactionPolicy(group, {
        'mode': 1,
        'reactionIds': <String>[],
      });
      expect(
        objects((await f.controller.reactionChoices()).single['reactions']),
        isEmpty,
      );
      expect((await f.controller.sharedPack('valid'))['id'], 'pack');
      await f.controller.subscribePack('pack', true);
      await f.controller.subscribePack('pack', false);
      await f.controller.reactionDefinition('a');
      await f.controller.reactionDefinition('a');
      expect(f.routes.where((r) => r == 'GET /api/reactions/a'), hasLength(1));
      await f.controller.leaveGroup(group);
      expect(f.controller.selected, isNull);
      expect(f.controller.conversations.every((c) => c.id != group), isTrue);
    },
  );
  test(
    'injected boot restores authenticated session and opens/decrypts HTTP history',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      f.history = [f.message('history')];
      await f.boot();
      expect(f.controller.ready, isTrue);
      expect(f.hubs.keys, hasLength(4));
      expect(f.encryption.initializations, 1);
      final conversation = f.controller.conversations.first;
      expect(conversation.id, chat);
      expect(conversation.peerId, peer);
      await f.controller.open(conversation);
      expect(f.controller.messages.single.text, 'hello');
      await f.controller.markRead();
      expect(f.controller.unread[conversation.key], 0);
    },
  );
  test(
    'login and registration use injected auth then activate the session',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.controller.signIn('Me', 'password');
      expect(f.controller.ready, isTrue);
      expect(f.controller.userId, testUser);
    },
  );
  test(
    'unacknowledged send retries the identical envelope and merges one message',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      await f.controller.open(f.controller.conversations.first);
      final hub = f.hubs['/hubs/chats']!;
      hub.failNextSend = true;
      expect(await f.controller.send('**hello**'), isFalse);
      final pending = f.controller.pending!;
      expect(await f.controller.send('changed'), isFalse);
      expect(hub.commands, hasLength(1));
      expect(await f.controller.send('**hello**'), isTrue);
      expect(f.encryption.encryptions, 1);
      expect(f.controller.pending, isNull);
      expect(f.controller.messages.single.id, pending.id);
      expect(f.controller.messages.single.text, '**hello**');
      expect(
        object(hub.commands.first.$2.single)['encryptedContent'],
        object(hub.commands.last.$2.single)['encryptedContent'],
      );
    },
  );
  test(
    'explicit pre-save rejection releases the draft for a newly encrypted send',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      final conversation = f.controller.conversations.first;
      await f.controller.open(conversation);
      final hub = f.hubs['/hubs/chats']!;
      f.controller.drafts[conversation.key] = 'reply';
      final quoted = f.message('original')['id'] as String;
      hub.nextSendRejection = HubCommandFailure.fromResult(
        'Send',
        400,
        'E2EE_DEVICES_CHANGED',
      );

      expect(await f.controller.send('reply', replyTo: quoted), isFalse);
      expect(f.controller.error, contains('актуальными ключами'));
      expect(f.controller.pending, isNull);
      expect(f.controller.drafts[conversation.key], 'reply');
      expect(await f.controller.send('reply', replyTo: quoted), isTrue);
      expect(f.encryption.encryptions, 2);
      final first = object(
        hub.commands.where((c) => c.$1 == 'Send').first.$2.single,
      );
      expect(
        f.controller.messages.single.id,
        isNot(object(jsonDecode(first['encryptedContent'] as String))['id']),
      );
      expect(f.controller.messages.single.replyTo, quoted);
    },
  );

  test(
    'rejection on a retry after lost acknowledgement cannot create a second ID',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      await f.controller.open(f.controller.conversations.first);
      final hub = f.hubs['/hubs/chats']!;
      hub.failNextSend = true;
      expect(await f.controller.send('reply'), isFalse);
      final pending = f.controller.pending!;
      hub.nextSendRejection = HubCommandFailure.fromResult(
        'Send',
        400,
        'E2EE_TIMESTAMP_OUT_OF_RANGE',
      );
      expect(await f.controller.send('reply'), isFalse);
      expect(f.controller.pending, same(pending));
      expect(f.controller.error, contains('5 минут'));
      expect(await f.controller.send('reply'), isTrue);
      expect(f.controller.messages.single.id, pending.id);
      expect(f.encryption.encryptions, 1);
    },
  );

  test(
    'history rejects wrong-chat data and preserves signature failures as unreadable',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      f.history = [f.message('bad', bad: true)];
      await f.controller.open(f.controller.conversations.first);
      expect(f.controller.messages.single.failure, isNotNull);
      expect(f.controller.messages.single.text, isNull);
      f.history = [f.message('wrong', conversation: group)];
      await f.controller.refresh();
      expect(f.controller.error, contains('другого чата'));
    },
  );
  test(
    'edit, remove, description, friend commands and logout traverse their services',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      await f.controller.open(f.controller.conversations.first);
      await f.controller.send('original');
      final message = f.controller.messages.single;
      await f.controller.edit(message, 'edited');
      await f.controller.remove(message);
      await f.controller.updateDescription('**Profile**');
      expect(f.controller.me!.description, '**Profile**');
      await f.controller.sendFriendRequest(peer);
      await f.controller.acceptRequest('request-id', accept: false);
      expect(
        f.hubs['/hubs/chats']!.commands.map((c) => c.$1),
        containsAll(['Send', 'Edit', 'Remove']),
      );
      expect(
        f.hubs['/hubs/friends']!.commands.map((c) => c.$1),
        containsAll(['SendRequest', 'RejectRequest']),
      );
      f.controller.drafts[chat] = 'draft';
      await f.controller.logout();
      expect(f.controller.ready, isFalse);
      expect(f.controller.me, isNull);
      expect(f.controller.drafts, isEmpty);
      expect(f.controller.media, isNull);
      expect(f.hubs.values.every((h) => h.stopped), isTrue);
    },
  );
  test(
    'read-only channels reject sends before encryption or network mutation',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      await f.controller.open(
        const Conversation(
          id: group,
          title: 'News',
          type: 1,
          isChannel: true,
          canPost: false,
        ),
      );
      expect(await f.controller.send('no'), isFalse);
      expect(f.encryption.encryptions, 0);
      expect(f.hubs['/hubs/chats']!.commands, isEmpty);
    },
  );
}
