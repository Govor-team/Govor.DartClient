import 'package:govor_mobile/ui/markdown_image.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/chat_hub.dart';
import 'package:govor_mobile/core/external_links.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/core/user_profile_repository.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/features/profile/user_profile_cubit.dart';
import 'package:govor_mobile/ui/govor_markdown.dart';
import 'package:govor_mobile/ui/user_profile_dialog.dart';
import 'support/auth_fixtures.dart' show testToken;

const me = '11111111-1111-4111-8111-111111111111',
    peer = '22222222-2222-4222-8222-222222222222';

class FakeProfiles implements UserProfileRepository {
  FakeProfiles(this.relationship);
  Relationship relationship;
  int sends = 0, accepts = 0, rejects = 0;
  bool fails = false;
  @override
  Future<UserProfileSnapshot> load(String id) async {
    if (fails) throw StateError('offline');
    return UserProfileSnapshot(
      person: Person(
        id: id,
        name: 'Alice',
        description: '**About me**\n\nA friendly profile.',
      ),
      relationship: relationship,
      requestId: 'request-id',
    );
  }

  @override
  Future<void> removeFriend(String id) async {
    relationship = Relationship.rejected;
  }

  @override
  Future<void> block(String id, {required bool blocked}) async {
    relationship = blocked ? Relationship.blocked : Relationship.rejected;
  }

  @override
  Future<void> send(String id) async {
    sends++;
    relationship = Relationship.outgoing;
  }

  @override
  Future<void> respond(String id, {required bool accept}) async {
    if (accept) {
      accepts++;
      relationship = Relationship.friend;
    } else {
      rejects++;
      relationship = Relationship.rejected;
    }
  }
}

class RecordingFriendsHub extends ChatHub {
  RecordingFriendsHub(super.api);
  final commands = <(String, List<Object?>)>[];
  @override
  Future<dynamic> invoke(String method, List<Object?> args) async {
    commands.add((method, args));
    return null;
  }
}

void main() {
  test(
    'relationship derives direction and status from authoritative snapshots',
    () {
      final incoming = <Json>[
        {'id': 'r', 'requesterId': peer, 'addresseeId': me, 'status': 0},
      ];
      final outgoing = <Json>[
        {'id': 'r', 'requesterId': me, 'addresseeId': peer, 'status': 0},
      ];
      expect(
        relationshipFor(me, peer, [], incoming, []),
        Relationship.incoming,
      );
      expect(
        relationshipFor(me, peer, [], [], outgoing),
        Relationship.outgoing,
      );
      expect(
        relationshipFor(
          me,
          peer,
          [const Person(id: peer, name: 'Alice')],
          incoming,
          [],
        ),
        Relationship.friend,
      );
      expect(relationshipFor(me, me, [], [], []), Relationship.self);
      outgoing.single['status'] = 3;
      expect(relationshipFor(me, peer, [], [], outgoing), Relationship.blocked);
    },
  );
  test(
    'profile repository reads HTTP and sends the friendship ID to FriendsHub',
    () async {
      final paths = <String>[];
      final api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((request) async {
          paths.add(request.url.path);
          final Object response = switch (request.url.path) {
            '/api/profile/download/$peer' => {
              'id': peer,
              'username': 'Alice',
              'description': '**About**',
              'isOnline': true,
            },
            '/api/friends/requests' => <Json>[
              {
                'id': 'request-id',
                'requesterId': peer,
                'addresseeId': me,
                'status': 0,
              },
            ],
            _ => <Json>[],
          };
          return http.Response(jsonEncode(response), 200);
        }),
      );
      addTearDown(api.close);
      api.tokens = TokenPair.fromJson({
        'accessToken': testToken('profile'),
        'refreshToken': 'refresh',
      });
      final hub = RecordingFriendsHub(api),
          repo = ApiUserProfileRepository(api, RecordingFriendsHub(api), me);
      final profile = await repo.load(peer);
      expect(profile.relationship, Relationship.incoming);
      expect(paths, hasLength(4));
      final commandRepo = ApiUserProfileRepository(api, hub, me);
      await commandRepo.send(peer);
      await commandRepo.respond('request-id', accept: true);
      await commandRepo.respond('request-id', accept: false);
      expect(hub.commands.map((command) => command.$1).toList(), [
        'SendRequest',
        'AcceptRequest',
        'RejectRequest',
      ]);
      expect(hub.commands.map((command) => command.$2).toList(), [
        [peer],
        ['request-id'],
        ['request-id'],
      ]);
    },
  );
  test(
    'profile cubit permits only legal actions and handles accepted response with failed refresh',
    () async {
      final repo = FakeProfiles(Relationship.stranger),
          cubit = UserProfileCubit(FakeProfiles(Relationship.self), me);
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.send();
      expect(cubit.state.profile!.relationship, Relationship.self);
      final other = UserProfileCubit(repo, peer);
      addTearDown(other.close);
      await other.load();
      await other.respond(true);
      expect(repo.accepts, 0);
      await other.send();
      await other.send();
      expect(repo.sends, 1);
      expect(other.state.profile!.relationship, Relationship.outgoing);
      repo.relationship = Relationship.incoming;
      await other.load();
      await other.respond(true);
      expect(repo.accepts, 1);
      expect(other.state.profile!.relationship, Relationship.friend);
    },
  );
  test(
    'acknowledged request is not sent again after snapshot refresh fails',
    () async {
      final repo = FakeProfiles(Relationship.stranger);
      final wrapped = DemoUserProfileRepository(
        snapshot: repo.load,
        sendRequest: (id) async {
          await repo.send(id);
          repo.fails = true;
        },
        respondRequest: (id, accept) => repo.respond(id, accept: accept),
      );
      final cubit = UserProfileCubit(wrapped, peer);
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.send();
      expect(cubit.state.failed, isTrue);
      expect(cubit.state.profile!.relationship, Relationship.outgoing);
      await cubit.send();
      expect(repo.sends, 1);
    },
  );
  test('Markdown detects lists, tables and basic formatting', () {
    for (final text in [
      '- first\n- second',
      '1. first\n2. second',
      '| header | value |',
      '**bold**',
      '## Title',
    ]) {
      expect(GovorMarkdown.hasFormatting(text), isTrue, reason: text);
    }
    expect(GovorMarkdown.hasFormatting('Hello there'), isFalse);
  });
  test('Markdown link allowlist rejects executable and local URLs', () {
    for (final href in [
      'javascript:alert(1)',
      'data:text/html,hi',
      'file:///C:/secret',
      'https://user:pass@example.com',
      'https://example.com/\nsecret',
      '/api/media/123',
    ]) {
      expect(externalUri(href), isNull, reason: href);
    }
    expect(externalUri('https://example.com/path?q=1')!.host, 'example.com');
  });
  testWidgets(
    'Markdown renders formatting and inline images with safe link navigation',
    (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: GovorMarkdown(
                '**Bold** and _italic_\n\n> Quote\n\n`code`\n\n[site](https://example.com)\n\n![Private image](https://example.com/track.png)',
                openLink: (uri) async {
                  opened.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.byType(MarkdownImage), findsOneWidget);
      expect(opened, isEmpty);
      final widget = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      widget.onTapLink!('bad', 'javascript:alert(1)', '');
      await tester.pump();
      expect(opened, isEmpty);
      widget.onTapLink!('site', 'https://example.com', '');
      await tester.pump();
      expect(opened.single.host, 'example.com');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Markdown code and tables fit a small screen with enlarged text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.8),
            ),
            child: SizedBox(
              width: 280,
              child: SingleChildScrollView(
                child: GovorMarkdown(
                  '## Heading\n\n```dart\n${'long_value_' * 50}\n```\n\n| Left | Right |\n| --- | --- |\n| value | another |',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final relationship in [
    Relationship.stranger,
    Relationship.friend,
    Relationship.incoming,
    Relationship.outgoing,
    Relationship.self,
    Relationship.blocked,
  ]) {
    testWidgets(
      'user profile exposes API-supported actions for $relationship',
      (tester) async {
        final c = MessengerController(store: MemorySecretStore())..startDemo();
        addTearDown(c.dispose);
        final repo = FakeProfiles(relationship);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UserProfileDialog(
                controller: c,
                userId: 'demo-friend',
                repository: repo,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(
          find.byKey(const Key('profile-open-chat')),
          relationship == Relationship.friend ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('profile-send-request')),
          relationship == Relationship.stranger ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('profile-accept-request')),
          relationship == Relationship.incoming ? findsOneWidget : findsNothing,
        );
        if (relationship == Relationship.stranger) {
          await tester.tap(find.byKey(const Key('profile-send-request')));
          await tester.pumpAndSettle();
          expect(repo.sends, 1);
          expect(find.byKey(const Key('profile-send-request')), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
