import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/group_invitation.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/l10n/l10n.dart';
import 'package:govor_mobile/ui/group_invitation_dialog.dart';
import 'package:govor_mobile/ui/group_pages.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support/auth_fixtures.dart';

void main() {
  const group = '11111111-1111-1111-1111-111111111111';
  const image = '22222222-2222-2222-2222-222222222222';
  final photo = File(
    'assets/backgrounds/background_girls.jpg',
  ).readAsBytesSync();

  test(
    'group avatar uses its multipart file route, authentication and imageId response',
    () async {
      var requests = 0;
      final api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.path, '/api/groups/$group/avatar');
          expect(request.headers['Authorization'], startsWith('Bearer '));
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data;'),
          );
          expect(
            latin1.decode(request.bodyBytes),
            contains('name="file"; filename="avatar.png"'),
          );
          expect(request.bodyBytes.length, greaterThan(photo.length));
          return http.Response(
            jsonEncode({
              'imageId': image,
              'mediaUrl': '/api/media/download/$image',
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await api.accept(TokenPair.fromJson(tokenJson('group')));
      expect(await api.uploadGroupAvatar(group, photo), image);
      expect(requests, 1);
    },
  );

  test(
    'invalid group avatar files and ids fail before any upload; server permission errors propagate',
    () async {
      var requests = 0;
      final api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((_) async {
          requests++;
          return http.Response('Forbidden', 403);
        }),
      );
      addTearDown(api.close);
      await api.accept(TokenPair.fromJson(tokenJson('group')));
      for (final bytes in [
        Uint8List(0),
        Uint8List(2 * 1024 * 1024 + 1),
        Uint8List.fromList(utf8.encode('GIF89a invalid')),
        Uint8List.fromList(utf8.encode('<svg/>')),
      ]) {
        await expectLater(
          api.uploadGroupAvatar(group, bytes),
          throwsA(isA<Exception>()),
        );
      }
      await expectLater(
        api.uploadGroupAvatar('../other', photo),
        throwsA(isA<Exception>()),
      );
      final oversizedDimensions = Uint8List.fromList(photo);
      ByteData.sublistView(oversizedDimensions).setUint32(16, 2049);
      await expectLater(
        api.uploadGroupAvatar(group, oversizedDimensions),
        throwsA(isA<Exception>()),
      );
      expect(requests, 0);
      await expectLater(
        api.uploadGroupAvatar(group, photo),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)),
      );
      expect(requests, 1);
    },
  );

  test(
    'invitation options validate API boundaries and serialize selected values',
    () {
      expect(const GroupInvitationOptions().toJson(), {
        'validForDays': 7,
        'maxParticipants': 0,
        'description': '',
      });
      expect(
        const GroupInvitationOptions(
          validForDays: 365,
          maxParticipants: 1000000,
          description: ' Campaign ',
        ).toJson(),
        {
          'validForDays': 365,
          'maxParticipants': 1000000,
          'description': 'Campaign',
        },
      );
      for (final options in [
        const GroupInvitationOptions(validForDays: 0),
        const GroupInvitationOptions(validForDays: 366),
        const GroupInvitationOptions(maxParticipants: -1),
        const GroupInvitationOptions(maxParticipants: 1000001),
        GroupInvitationOptions(description: 'x' * 501),
      ]) {
        expect(options.toJson, throwsArgumentError);
      }
    },
  );

  test(
    'custom invitation options reach the API and group avatar can be removed',
    () async {
      final c = MessengerController(store: MemorySecretStore());
      addTearDown(c.dispose);
      final paths = <String>[];
      c.api = ApiClient(
        ServerAddress('https://test.example'),
        MemorySecretStore(),
        client: MockClient((request) async {
          paths.add('${request.method} ${request.url.path}');
          if (request.method == 'DELETE') return http.Response('', 204);
          expect(jsonDecode(request.body), {
            'validForDays': 30,
            'maxParticipants': 42,
            'description': 'Friends',
          });
          return http.Response('{"id":"created"}', 200);
        }),
      );
      await c.api!.accept(TokenPair.fromJson(tokenJson('group')));
      expect(
        await c.createGroupInvite(
          group,
          const GroupInvitationOptions(
            validForDays: 30,
            maxParticipants: 42,
            description: 'Friends',
          ),
        ),
        {'id': 'created'},
      );
      await c.removeGroupAvatar(group);
      expect(paths, [
        'POST /api/groups/$group/invitations',
        'DELETE /api/groups/$group/avatar',
      ]);
    },
  );

  Future<void> host(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'invitation form keeps custom options after errors and prevents duplicate creation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 24 / 14;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final values = <GroupInvitationOptions>[];
      final completion = Completer<Json>();
      Json? result;
      await host(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<Json>(
                context: context,
                builder: (_) => GroupInvitationDialog(
                  create: (options) async {
                    values.add(options);
                    if (values.length == 1) throw StateError('offline');
                    return completion.future;
                  },
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final submit = find.byKey(const Key('create-invitation-submit'));
      await tester.enterText(find.byKey(const Key('invite-days')), '0');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(values, isEmpty);
      expect(find.text('Введите от 1 до 365 дней'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('invite-days')), '365');
      await tester.enterText(
        find.byKey(const Key('invite-participants')),
        '1000000',
      );
      await tester.enterText(
        find.byKey(const Key('invite-description')),
        'Campaign',
      );
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(values.single.toJson(), {
        'validForDays': 365,
        'maxParticipants': 1000000,
        'description': 'Campaign',
      });
      expect(find.text('Campaign'), findsOneWidget);
      expect(find.textContaining('Не удалось создать ссылку'), findsOneWidget);
      await tester.tap(submit);
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(values, hasLength(2));
      completion.complete({'id': 'created'});
      await tester.pumpAndSettle();
      expect(result, {'id': 'created'});
      expect(find.byType(GroupInvitationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group owner can edit avatar; admin can create invitations; member sees neither',
    (tester) async {
      for (final role in [2, 1, 0]) {
        final c = MessengerController(store: MemorySecretStore())..startDemo();
        c.demo = false;
        c.api = _GroupProfileApi(role);
        await host(
          tester,
          GroupProfilePage(key: ValueKey(role), controller: c, groupId: group),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('change-group-avatar')),
          role == 2 ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Создать приглашение'),
          role >= 1 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    },
  );
}

class _GroupProfileApi extends ApiClient {
  _GroupProfileApi(this.role)
    : super(ServerAddress('https://test.example'), MemorySecretStore());
  final int role;
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/members') || path.endsWith('/invitations')) {
      return <Json>[];
    }
    return {
      'id': '11111111-1111-1111-1111-111111111111',
      'name': 'Community',
      'description': '',
      'memberCount': 1,
      'isPrivate': true,
      'myRole': role,
      'canLeave': false,
      'isChannel': false,
    };
  }
}
