import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/features/reactions/reaction_selection.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'support/auth_fixtures.dart' show testToken;

const user = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
Json snapshot(
  int version, {
  String actor = user,
  String? reaction = 'thumb',
  int count = 2,
}) => {
  'messageId': 'message',
  'recipientId': 'chat',
  'recipientType': 0,
  'version': version,
  'actorId': actor,
  'actorReaction': reaction == null
      ? null
      : {'reactionId': reaction, 'reactionCode': '👍'},
  'counts': count == 0
      ? <Json>[]
      : [
          {'reactionId': 'thumb', 'reactionCode': '👍', 'count': count},
        ],
};
ChatMessage message() => ChatMessage(
  id: 'message',
  senderId: other,
  conversationId: 'chat',
  type: 0,
  sentAt: DateTime.utc(2026),
  content: '',
  text: 'hello',
);
MessengerController controller(
  Future<http.Response> Function(http.Request) handler,
) {
  final api = ApiClient(
    ServerAddress('https://test.example'),
    MemorySecretStore(),
    client: MockClient(handler),
  );
  api.tokens = TokenPair.fromJson({
    'accessToken': testToken('reaction'),
    'refreshToken': 'refresh',
  });
  return MessengerController(store: MemorySecretStore())
    ..api = api
    ..me = const Person(id: user, name: 'User');
}

void main() {
  test('legacy reactions match by code without highlighting other users', () {
    expect(
      isOwnReaction(null, {'reactionId': null, 'reactionCode': '👍'}),
      isFalse,
    );
    expect(
      isOwnReaction(
        {'reactionId': null, 'reactionCode': '👍'},
        {'reactionId': null, 'reactionCode': '👍'},
      ),
      isTrue,
    );
    expect(
      isOwnReaction(
        {'reactionId': null, 'reactionCode': '👍'},
        {'reactionId': null, 'reactionCode': '❤️'},
      ),
      isFalse,
    );
  });
  test(
    'repeated own reaction issues DELETE and preserves other users counts',
    () async {
      final methods = <String>[];
      final c = controller((request) async {
        methods.add(request.method);
        return http.Response(
          jsonEncode(snapshot(3, reaction: null, count: 1)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(c.dispose);
      c.applyReactions(snapshot(2));
      await c.react(message(), 'thumb');
      expect(methods, ['DELETE']);
      expect(c.reactionStates['message']?['mine'], isNull);
      expect(
        (c.reactionStates['message']?['counts'] as List).single['count'],
        1,
      );
    },
  );
  test(
    'foreign actor and stale snapshots cannot replace my active reaction',
    () async {
      final c = controller((_) async => http.Response('', 500));
      addTearDown(c.dispose);
      c.applyReactions(snapshot(5));
      c.applyReactions(snapshot(4, reaction: null));
      c.applyReactions(snapshot(6, actor: other, reaction: 'heart'));
      expect(c.reactionStates['message']?['version'], 6);
      expect(c.reactionStates['message']?['mine']['reactionId'], 'thumb');
    },
  );
  test(
    'concurrent taps send one mutation and session changes discard old replies',
    () async {
      final gate = Completer<http.Response>();
      var requests = 0;
      final c = controller((_) {
        requests++;
        return gate.future;
      });
      addTearDown(c.dispose);
      c.applyReactions(snapshot(1));
      final first = c.react(message(), 'thumb');
      await c.react(message(), 'thumb');
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      c.startDemo();
      gate.complete(
        http.Response(
          jsonEncode(snapshot(2, reaction: null)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await first;
      expect(c.reactionStates, isEmpty);
    },
  );
}
