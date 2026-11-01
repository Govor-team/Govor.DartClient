import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/chat_hub.dart';
import 'package:govor_mobile/core/media/attachment_repository.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/core/user_benefits.dart';
import 'package:govor_mobile/core/user_benefits_repository.dart';
import 'package:govor_mobile/core/user_profile_repository.dart';
import 'package:govor_mobile/features/profile/user_profile_cubit.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'support/messenger_fixture.dart' show FlowFixture, peer, chat, group;
import 'support/auth_fixtures.dart' show testToken, testUser;

http.Response json(Object value) => http.Response(jsonEncode(value), 200);
Json benefit(int revision, {bool enabled = true}) => {
  'revision': revision,
  'privileges': enabled ? 1 : 0,
  'isGovorPlus': enabled,
  'canCustomizeProfileTag': enabled,
  'tag': enabled ? {'text': 'Custom'} : null,
};
ChatMessage source({List<Json> files = const [], String? reply}) => ChatMessage(
  id: 'original',
  senderId: peer,
  conversationId: chat,
  type: 0,
  sentAt: DateTime.utc(2026),
  content: '',
  text: 'Original text',
  attachments: files,
  replyTo: reply,
);

class ReuploadingMedia implements AttachmentRepository {
  int uploads = 0, downloads = 0;
  bool fails = false;
  @override
  Future<Uint8List> load(Attachment attachment) async {
    downloads++;
    if (fails) throw StateError('unavailable');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Attachment> upload(Uint8List bytes, String name) async {
    uploads++;
    return Attachment(
      id: 'fresh-$uploads',
      key: 'new-secret-$uploads',
      name: name,
      mime: 'image/png',
    );
  }

  @override
  void clear() {}
}

void main() {
  test(
    'channel choices contain uninstalled reactions in one deduplicated set',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      f.overrideResponse = (r) {
        if (r.url.path.endsWith('/reactions') &&
            r.url.path.contains('/groups/')) {
          return json({
            'mode': 2,
            'reactionIds': ['a', 'b', 'a', 'disabled'],
          });
        }
        if (r.url.path.startsWith('/api/reactions/')) {
          final id = r.url.pathSegments.last;
          return json({
            'id': id,
            'name': id,
            'emoji': id,
            'kind': 0,
            'isEnabled': id != 'disabled',
          });
        }
        return null;
      };
      await f.boot();
      final packs = await f.controller.reactionChoices(
        conversation: const Conversation(
          id: group,
          title: 'Channel',
          type: 1,
          isChannel: true,
        ),
      );
      expect(packs.single['id'], 'channel-reactions');
      expect(objects(packs.single['reactions']).map((r) => r['id']), [
        'a',
        'b',
      ]);
      expect(f.routes.any((r) => r.contains('/reaction-packs/mine')), isFalse);
    },
  );

  test(
    'forwards reencrypt media, preserve destination drafts and retry one envelope',
    () async {
      final f = FlowFixture(), media = ReuploadingMedia();
      addTearDown(f.controller.dispose);
      await f.boot();
      await f.controller.open(f.controller.conversations.first);
      final selected = f.controller.selected;
      final target = f.controller.conversations.last;
      f.controller.media = media;
      f.controller.drafts[target.key] = 'Unsent draft';
      f.controller.attachments[target.key] = [
        {'MediaId': 'draft-file'},
      ];
      final message = source(
        files: [
          const Attachment(
            id: 'old',
            key: 'old-secret',
            name: 'photo.png',
            mime: 'image/png',
          ).toJson(),
        ],
      );
      final hub = f.hubs['/hubs/chats']!;
      hub.failNextSend = true;
      expect(await f.controller.forwardMessage(message, target), isFalse);
      expect(await f.controller.forwardMessage(message, target), isTrue);
      final sends = hub.commands
          .where((c) => c.$1 == 'Send')
          .map((c) => object(c.$2.single))
          .toList();
      expect(sends, hasLength(2));
      expect(sends[0]['encryptedContent'], sends[1]['encryptedContent']);
      expect(sends.last['forwardedFromMessageId'], message.id);
      expect(sends.last['replyToMessageId'], isNull);
      expect(sends.last['recipientId'], target.id);
      expect(
        objects(sends.last['mediaAttachments']).single['mediaId'],
        'fresh-1',
      );
      expect(
        jsonDecode(sends.last['encryptedContent'] as String)['files'][0]['Key'],
        'new-secret-1',
      );
      expect(media.uploads, 1);
      expect(media.downloads, 1);
      expect(f.controller.selected, selected);
      expect(f.controller.drafts[target.key], 'Unsent draft');
      expect(
        f.controller.attachments[target.key]!.single['MediaId'],
        'draft-file',
      );
    },
  );

  test(
    'failed media decryption sends no forward and leaves drafts intact',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      f.controller.media = ReuploadingMedia()..fails = true;
      final target = f.controller.conversations.first;
      expect(
        await f.controller.forwardMessage(
          source(
            files: [
              const Attachment(
                id: 'old',
                key: 'secret',
                name: 'file',
                mime: 'image/png',
              ).toJson(),
            ],
          ),
          target,
        ),
        isFalse,
      );
      expect(
        f.hubs['/hubs/chats']!.commands.where((c) => c.$1 == 'Send'),
        isEmpty,
      );
      expect(f.controller.uploading, isFalse);
    },
  );

  test(
    'reply outside the loaded history is verified against its chat and handles deletion',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      var result = f.message('missing', content: 'Reply preview');
      var deleted = false;
      f.overrideResponse = (r) => r.url.path == '/api/messages/missing'
          ? deleted
                ? http.Response('', 404)
                : json(result)
          : null;
      final reply = source(reply: 'missing');
      expect((await f.controller.replyPreview(reply))!.text, 'Reply preview');
      result = f.message('missing', conversation: group);
      await expectLater(f.controller.replyPreview(reply), throwsA(anything));
      deleted = true;
      expect(await f.controller.replyPreview(reply), isNull);
    },
  );

  test('forward provenance survives decryption and rejected payloads', () {
    final message = ChatMessage.fromJson({
      'id': 'fwd',
      'senderId': testUser,
      'recipientId': chat,
      'recipientType': 0,
      'sentAt': '2026-10-31T00:00:00Z',
      'encryptedContent': 'encrypted',
      'forwardedFromMessageId': 'source',
      'forwardedFromUserId': peer,
      'forwardedFromSentAt': '2026-10-30T00:00:00Z',
    });
    for (final m in [message.decoded('text'), message.rejected('failure')]) {
      expect(m.forwardedFromMessageId, 'source');
      expect(m.forwardedFromUserId, peer);
      expect(m.forwardedFromSentAt, DateTime.utc(2026, 10, 30));
    }
  });

  test(
    'benefits events win over stale HTTP snapshots and are cleared at session change',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      f.overrideResponse = (r) =>
          r.url.path == '/api/profile/$peer/benefits' ? json(benefit(4)) : null;
      await f.controller.loadBenefits(peer);
      final hub = f.hubs['/hubs/profiles']!;
      hub.onEvent!('UserBenefitsUpdated', [
        {'userId': peer, 'benefits': benefit(5, enabled: false)},
      ]);
      await f.controller.loadBenefits(peer);
      hub.onEvent!('UserBenefitsUpdated', [
        {'userId': peer, 'benefits': benefit(4)},
      ]);
      expect(f.controller.benefits[peer]!.revision, 5);
      expect(f.controller.benefits[peer]!.tag, isNull);
      f.controller.startDemo();
      expect(f.controller.benefits[peer], isNull);
    },
  );

  test(
    'benefits reconnect refreshes watched profiles and discards late old-session responses',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      f.overrideResponse = (r) =>
          r.url.path == '/api/profile/$peer/benefits' ? json(benefit(2)) : null;
      f.controller.watchBenefits(peer);
      await Future<void>.delayed(Duration.zero);
      await f.hubs['/hubs/profiles']!.onReconnected!();
      expect(f.controller.benefits[peer]!.revision, 2);
      expect(
        f.routes.where((r) => r == 'GET /api/profile/$peer/benefits').length,
        greaterThanOrEqualTo(2),
      );
      final gate = Completer<http.Response>();
      final api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((_) => gate.future),
      );
      api.tokens = TokenPair.fromJson({
        'accessToken': testToken('late'),
        'refreshToken': 'refresh',
      });
      f.controller.api = api;
      final task = f.controller.loadBenefits(peer);
      await Future<void>.delayed(Duration.zero);
      f.controller.startDemo();
      gate.complete(json(benefit(100)));
      await task;
      expect(f.controller.benefits[peer], isNull);
      f.api.close();
    },
  );

  test(
    'benefits repository writes only the documented tag and privilege routes',
    () async {
      final requests = <http.Request>[];
      final api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((r) async {
          requests.add(r);
          return json(benefit(requests.length));
        }),
      );
      addTearDown(api.close);
      api.tokens = TokenPair.fromJson({
        'accessToken': testToken('benefits'),
        'refreshToken': 'refresh',
      });
      final repo = UserBenefitsRepository(api);
      await repo.saveTag(ProfileTag({'text': 'Tag'}));
      await repo.saveTag(null);
      await repo.setPrivileges(peer, 3);
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'PUT /api/profile/tag',
        'DELETE /api/profile/tag',
        'PUT /api/admin/users/$peer/privileges',
      ]);
      expect(object(jsonDecode(requests.first.body))['text'], 'Tag');
      await expectLater(
        repo.setPrivileges(peer, 4),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(repo.load('../me'), throwsA(isA<ApiFailure>()));
      expect(requests, hasLength(3));
    },
  );

  test(
    'tag validation accepts bounded styles and rejects executable or unbounded values',
    () {
      expect(
        ProfileTag({'text': '<b>plain text</b>'}).text,
        '<b>plain text</b>',
      );
      for (final invalid in <Json>[
        {'text': ' '},
        {'text': 'x' * 33},
        {'text': 'bad\nline'},
        {'textColor': 'url(https://x)'},
        {'fontFamily': 'https://font'},
        {'fontWeight': 650},
        {'fontSize': 25},
        {'shadowBlur': double.infinity},
        {'gradientAngle': -1},
        {'borderWidth': 5},
        {'shadowOffsetX': -11},
      ]) {
        expect(
          () => ProfileTag(invalid),
          throwsFormatException,
          reason: '$invalid',
        );
      }
      expect(
        UserBenefits.fromJson({
          'isGovorPlus': false,
          'canCustomizeProfileTag': false,
          'tag': {'text': 'Govor+'},
        }).tag,
        isNull,
      );
    },
  );

  test(
    'tag writes enforce current privileges and keep the last state on rejection',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      await f.boot();
      await expectLater(
        f.controller.saveProfileTag(ProfileTag({'text': 'Tag'})),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        f.controller.setUserPrivileges(peer, 1),
        throwsA(isA<ApiFailure>()),
      );
      f.controller.benefits.apply(testUser, UserBenefits.fromJson(benefit(1)));
      f.overrideResponse = (r) =>
          r.url.path == '/api/profile/tag' ? json(benefit(2)) : null;
      await f.controller.saveProfileTag(ProfileTag({'text': 'Tag'}));
      expect(f.controller.benefits[testUser]!.revision, 2);
      f.overrideResponse = (r) =>
          r.url.path == '/api/profile/tag' ? http.Response('', 403) : null;
      await expectLater(
        f.controller.saveProfileTag(null),
        throwsA(isA<ApiFailure>()),
      );
      expect(f.controller.benefits[testUser]!.revision, 2);
      f.controller.benefits.apply(
        testUser,
        UserBenefits.fromJson(benefit(3, enabled: false)),
      );
      final before = f.routes.length;
      await expectLater(
        f.controller.saveProfileTag(ProfileTag({'text': 'Tag'})),
        throwsA(isA<ApiFailure>()),
      );
      expect(f.routes.length, before);
    },
  );

  test(
    'friendship mutations use user IDs and only an owner can unblock',
    () async {
      final routes = <String>[];
      var status = 1;
      var owner = testUser;
      final api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((r) async {
          routes.add('${r.method} ${r.url.path}');
          if (r.method != 'GET') {
            status = r.method == 'PUT' ? 3 : 2;
            return http.Response('', 204);
          }
          if (r.url.path.startsWith('/api/profile')) {
            return json({'id': peer, 'username': 'Peer'});
          }
          if (r.url.path == '/api/friends') {
            return json(
              status == 1
                  ? [
                      {'id': peer, 'username': 'Peer'},
                    ]
                  : [],
            );
          }
          if (r.url.path.endsWith('/responses')) {
            return json([
              {
                'id': 'friendship',
                'requesterId': owner,
                'addresseeId': owner == testUser ? peer : testUser,
                'status': status,
              },
            ]);
          }
          return json([]);
        }),
      );
      addTearDown(api.close);
      api.tokens = TokenPair.fromJson({
        'accessToken': testToken('friends'),
        'refreshToken': 'refresh',
      });
      final repo = ApiUserProfileRepository(api, ChatHub(api), testUser);
      final cubit = UserProfileCubit(repo, peer);
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.removeFriend();
      expect(cubit.state.profile!.relationship, Relationship.rejected);
      await cubit.block(true);
      expect(cubit.state.profile!.blockedByMe, isTrue);
      await cubit.block(false);
      expect(cubit.state.profile!.relationship, Relationship.rejected);
      expect(routes.where((r) => !r.startsWith('GET')), [
        'DELETE /api/friends/$peer',
        'PUT /api/friends/$peer/block',
        'DELETE /api/friends/$peer/block',
      ]);
      status = 3;
      owner = peer;
      // Incoming records must be in the incoming list for the other participant.
      final foreign = UserProfileCubit(
        DemoUserProfileRepository(
          snapshot: (_) async => const UserProfileSnapshot(
            person: Person(id: peer, name: 'Peer'),
            relationship: Relationship.blocked,
          ),
          sendRequest: (_) async {},
          respondRequest: (_, _) async {},
          setBlocked: (_, _) async => fail('Foreign block mutation'),
        ),
        peer,
      );
      addTearDown(foreign.close);
      await foreign.load();
      await foreign.block(false);
      await expectLater(
        repo.block(testUser, blocked: true),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(repo.removeFriend('../x'), throwsA(isA<ApiFailure>()));
    },
  );
}
