import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/chat_hub.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';

import 'support/auth_fixtures.dart' show tokenJson;

void main() {
  test(
    'real WebSocket SignalR handshake, split frames, business status, reconnect and stop',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final commands = <Json>[];
      var connects = 0, resyncs = 0;
      ({int status, String error})? rejection;
      final event = Completer<String>(), reconnected = Completer<void>();
      final handler = server.listen((request) async {
        expect(request.headers.value('authorization'), startsWith('Bearer '));
        if (request.uri.path.endsWith('/negotiate')) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'negotiateVersion': 1,
              'connectionId': 'connection',
              'connectionToken': 'connection-token',
              'availableTransports': [
                {
                  'transport': 'WebSockets',
                  'transferFormats': ['Text'],
                },
              ],
            }),
          );
          await request.response.close();
          return;
        }
        expect(request.uri.queryParameters['id'], 'connection-token');
        expect(
          request.uri.queryParameters.containsKey('access_token'),
          isFalse,
        );
        final ws = await WebSocketTransformer.upgrade(request);
        sockets.add(ws);
        connects++;
        ws.listen((dynamic raw) {
          for (final frame
              in (raw as String).split('\x1e').where((s) => s.isNotEmpty)) {
            final message = object(jsonDecode(frame));
            if (message['protocol'] == 'json') {
              expect(message['version'], 1);
              ws.add('{}\x1e');
              if (connects == 1) {
                final notification =
                    '${jsonEncode({
                      'type': 1,
                      'target': 'ReceiveMessage',
                      'arguments': [
                        {'messageId': 'example'},
                      ],
                    })}\x1e';
                ws.add(notification.substring(0, 12));
                ws.add(notification.substring(12));
              }
            } else if (message['type'] == 1) {
              commands.add(message);
              ws.add(
                '${jsonEncode({
                  'type': 3,
                  'invocationId': message['invocationId'],
                  'result': {
                    'status': rejection?.status ?? (message['target'] == 'Denied' ? 403 : 201),
                    'result': {'sent': true},
                    'errorMessage': rejection?.error,
                  },
                })}\x1e',
              );
            }
          }
        });
      });
      final api = ApiClient(
        ServerAddress(
          'http://127.0.0.1:${server.port}',
          allowLoopbackHttp: true,
        ),
        MemorySecretStore(),
      );
      final hub = ChatHub(api)
        ..onEvent = (name, _) {
          if (!event.isCompleted) event.complete(name);
        }
        ..onReconnected = () async {
          resyncs++;
          if (!reconnected.isCompleted) reconnected.complete();
        };
      addTearDown(() async {
        await hub.stop();
        api.close();
        for (final ws in sockets) {
          await ws.close();
        }
        await handler.cancel();
        await server.close(force: true);
      });
      await api.accept(TokenPair.fromJson(tokenJson('test')));
      await hub.start();
      expect(hub.status, ConnectionStatus.connected);
      expect(
        await event.future.timeout(const Duration(seconds: 3)),
        'ReceiveMessage',
      );
      expect(
        object(
          await hub.invoke('Send', [
            {'encryptedContent': 'test-envelope'},
          ]),
        )['sent'],
        isTrue,
      );
      expect(commands.single['arguments'], [
        {'encryptedContent': 'test-envelope'},
      ]);
      await expectLater(hub.invoke('Denied', []), throwsA(isA<ApiFailure>()));
      rejection = (status: 400, error: 'E2EE_DEVICES_CHANGED');
      await expectLater(
        hub.invoke('Send', []),
        throwsA(
          isA<HubCommandFailure>()
              .having((e) => e.sendRejected, 'known pre-save rejection', true)
              .having(
                (e) => e.message,
                'guidance',
                contains('актуальными ключами'),
              ),
        ),
      );
      rejection = (status: 500, error: 'internal detail');
      await expectLater(
        hub.invoke('Send', []),
        throwsA(
          isA<HubCommandFailure>()
              .having(
                (e) => e.sendRejected,
                'unknown persistence outcome',
                false,
              )
              .having(
                (e) => e.message,
                'sanitized message',
                allOf(contains('500'), isNot(contains('internal detail'))),
              ),
        ),
      );
      rejection = null;
      await sockets.first.close();
      await reconnected.future.timeout(const Duration(seconds: 8));
      expect(resyncs, 1);
      await hub.stop();
      final stoppedAt = connects;
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      expect(connects, stoppedAt);
      expect(hub.status, ConnectionStatus.offline);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
