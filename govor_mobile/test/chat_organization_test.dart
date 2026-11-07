import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/chat_pins.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:http/http.dart' as http;
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/storage.dart';
import 'support/auth_fixtures.dart';
import 'support/messenger_fixture.dart';

http.Response json(Object value) => http.Response(jsonEncode(value), 200);

void main() {
  test(
    'pins are scoped per account and reject corrupt or foreign chat keys',
    () async {
      final data = <String, String>{};
      final pins = ChatPinsRepository(
        read: (key) async => data[key],
        write: (key, value) async => data[key] = value,
      );
      await pins.save('origin/a', {'0/$chat', '1/$group', 'invalid'});
      expect(await pins.load('origin/a'), {'0/$chat', '1/$group'});
      expect(await pins.load('origin/b'), isEmpty);
      data[data.keys.single] = '{broken';
      expect(await pins.load('origin/a'), isEmpty);
    },
  );

  test(
    'pins take precedence over activity and incoming events reorder chats immediately',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      f.overrideResponse = (request) {
        if (request.url.path.endsWith('/unread-count')) {
          return json({
            'unreadCount': 0,
            'lastMessageAt': request.url.path.contains(group)
                ? '2026-11-07T10:00:00Z'
                : '2026-11-07T09:00:00Z',
          });
        }
        return null;
      };
      await f.boot();
      final c = f.controller;
      expect(c.orderedConversations.map((e) => e.id), [group, chat]);
      final privateChat = c.conversations.first;
      await c.togglePin(privateChat);
      expect(c.orderedConversations.first.id, chat);
      await c.togglePin(privateChat);
      expect(c.orderedConversations.first.id, group);
      f.hubs['/hubs/chats']!.onEvent!('ReceiveMessage', [
        {
          'messageId': testSession,
          'recipientId': chat,
          'recipientType': 0,
          'sentAt': '2026-11-07T11:00:00Z',
        },
      ]);
      expect(c.orderedConversations.first.id, chat);
    },
  );

  test(
    'an old reading anchor loads a contiguous window and can page forward',
    () async {
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      const anchor = 'caaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final history = <Json>[
        {...f.message(anchor), 'senderId': testUser},
        for (var i = 1; i <= 45; i++)
          {
            ...f.message('unread-$i'),
            'sentAt': DateTime.utc(2026, 10, 1, 0, i).toIso8601String(),
          },
      ];
      final c = f.controller..startDemo();
      c.demo = false;
      c.me = const Person(id: testUser, name: 'Me');
      c.api = _ReadingApi(history, anchor, []);
      c.encryption = FlowEncryption(c.api!);
      const conversation = Conversation(id: chat, title: 'Peer');
      c.conversations = [conversation];
      c.unread[conversation.key] = 45;

      await c.open(conversation);
      expect(c.historyAnchorId, anchor);
      expect(c.messages.first.id, anchor);
      expect(c.messages.last.id, 'unread-40');
      expect(c.hasNewer, isTrue);
      await c.loadNewer();
      expect(c.messages.map((m) => m.id), history.map((m) => m['id']));
      expect(c.historyAnchorId, anchor);
      expect(c.hasNewer, isFalse);
    },
  );

  testWidgets(
    'opens at a read outgoing message, then sends a boundary only after scrolling',
    (tester) async {
      const outgoing = 'caaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final f = FlowFixture();
      addTearDown(f.controller.dispose);
      f.history = [
        {
          ...f.message(outgoing, content: 'Last read outgoing'),
          'senderId': testUser,
        },
        for (var i = 1; i <= 10; i++)
          {
            ...f.message('unread-$i', content: 'Incoming $i'),
            'sentAt': DateTime.utc(2026, 10, 1, 0, i).toIso8601String(),
          },
      ];
      final reads = <Json>[];
      final controller = f.controller..startDemo();
      controller.demo = false;
      controller.me = const Person(id: testUser, name: 'Me');
      controller.api = _ReadingApi(f.history, outgoing, reads);
      controller.encryption = FlowEncryption(controller.api!);
      const conversation = Conversation(id: chat, title: 'Peer');
      controller.conversations = [conversation];
      controller.unread[conversation.key] = 10;
      await controller.open(conversation);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(f.controller.historyAnchorId, outgoing);
      await tester.pumpWidget(GovorApp(controller: f.controller));
      await tester.pumpAndSettle();
      final view = find.byType(CustomScrollView);
      expect(view, findsOneWidget);
      final area = tester.getRect(view);
      expect(
        area.contains(tester.getCenter(find.text('Last read outgoing'))),
        isTrue,
      );
      expect(reads, isEmpty);
      final scroll = tester.widget<CustomScrollView>(view).controller!;
      final coveringRoute = showDialog<void>(
        context: tester.element(view),
        builder: (_) => const AlertDialog(content: Text('Cover history')),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.minScrollExtent);
      await tester.pumpAndSettle();
      expect(reads, isEmpty);
      Navigator.pop(tester.element(find.byType(AlertDialog)));
      await tester.pumpAndSettle();
      await coveringRoute;
      expect(reads, isNotEmpty);
      expect(reads.last['upToMessageId'], isNotNull);
      expect(reads.any((r) => r['upToMessageId'] == outgoing), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ReadingApi extends ApiClient {
  _ReadingApi(this.history, this.anchor, this.reads)
    : super(ServerAddress('https://reading.test'), MemorySecretStore());
  final List<Json> history;
  final String anchor;
  final List<Json> reads;

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/unread-count')) {
      expect(query?['includeReadPosition'], 'true');
      return {
        'unreadCount': 10,
        'lastMessageAt': null,
        'lastReadMessageId': anchor,
      };
    }
    if (path.endsWith('/messages')) {
      final index = history.indexWhere(
        (m) => m['id'] == query?['StartMessageId'],
      );
      expect(index, isNonNegative);
      final before = int.parse(query!['Before']!);
      final after = int.parse(query['After']!);
      return history.sublist(
        (index - before).clamp(0, history.length),
        (index + 1 + after).clamp(0, history.length),
      );
    }
    if (path.endsWith('/read')) {
      reads.add(object(body));
      return {
        'unreadCount': reads.last['upToMessageId'] == 'unread-10' ? 0 : 5,
      };
    }
    throw StateError('Unexpected request $method $path');
  }
}
