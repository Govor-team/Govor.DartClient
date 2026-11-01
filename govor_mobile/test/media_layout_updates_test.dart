import 'package:govor_mobile/ui/markdown_image.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'support/auth_fixtures.dart' show testToken, testUser;
import 'package:govor_mobile/ui/reply_preview.dart';
import 'support/messenger_fixture.dart' as fixture;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/app_dependencies.dart';
import 'package:govor_mobile/core/markdown_media.dart';
import 'package:govor_mobile/core/media/remote_image_repository.dart';
import 'package:govor_mobile/core/media/attachment_repository.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/preferences_repository.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/core/user_benefits.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/ui/attachment_gallery.dart';
import 'package:govor_mobile/ui/design.dart';
import 'package:govor_mobile/ui/language_selector.dart';
import 'package:govor_mobile/ui/message_actions.dart';
import 'package:govor_mobile/ui/message_bubble.dart';
import 'package:govor_mobile/ui/profile_tag_editor.dart';
import 'package:govor_mobile/ui/user_badge.dart';
import 'support/fake_attachments.dart';

void main() {
  test(
    'legacy media links render but code and normal links retain their meaning',
    () {
      expect(
        markdownMedia('https://example.com/a.gif?x=1'),
        '![](https://example.com/a.gif?x=1)',
      );
      expect(
        markdownMedia('[gif](https://example.com/a.gif)'),
        '![gif](https://example.com/a.gif)',
      );
      const code =
          '```md\nhttps://example.com/a.gif\n```\n    https://example.com/a.gif\n[website](https://example.com)';
      expect(markdownMedia(code), code);
    },
  );
  test(
    'remote images reject executable, credentialed and local destinations',
    () {
      for (final uri in [
        'file:///x',
        'data:image/png;base64,x',
        'javascript:alert(1)',
        'https://u:p@example.com/x',
        'http://localhost/x',
        'http://127.0.0.1/x',
        'http://10.1.2.3/x',
        'http://169.254.169.254/x',
        'http://192.168.1.1/x',
        'http://[::1]/x',
      ]) {
        expect(remoteImageUri(uri), isNull, reason: uri);
      }
      expect(remoteImageUri('https://example.com/a.gif'), isNotNull);
    },
  );
  testWidgets(
    'GIF download follows validated redirects without API credentials',
    (tester) async {
      final requests = <http.Request>[];
      final gif = base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      );
      final repo = RemoteImageRepository(
        client: MockClient((r) async {
          requests.add(r);
          return requests.length == 1
              ? http.Response(
                  '',
                  302,
                  headers: {'location': 'https://cdn.example/a.gif'},
                )
              : http.Response.bytes(gif, 200);
        }),
      );
      addTearDown(repo.close);
      final bytes = await tester.runAsync(
        () => repo.load(Uri.parse('https://example.com/a.gif')),
      );
      expect(bytes, gif);
      expect(requests.last.url.host, 'cdn.example');
      expect(
        requests.every(
          (r) =>
              !r.headers.containsKey('authorization') &&
              !r.headers.containsKey('cookie') &&
              !r.followRedirects,
        ),
        isTrue,
      );
    },
  );
  test(
    'image redirects cannot target local files and oversized downloads are rejected',
    () async {
      var calls = 0;
      final redirect = RemoteImageRepository(
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '',
            302,
            headers: {'location': 'http://127.0.0.1/secret'},
          );
        }),
      );
      addTearDown(redirect.close);
      await expectLater(
        redirect.load(Uri.parse('https://example.com/x')),
        throwsFormatException,
      );
      expect(calls, 1);
      final huge = RemoteImageRepository(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            const Stream.empty(),
            200,
            contentLength: RemoteImageRepository.maxBytes + 1,
          ),
        ),
      );
      addTearDown(huge.close);
      await expectLater(
        huge.load(Uri.parse('https://example.com/x')),
        throwsFormatException,
      );
      final html = RemoteImageRepository(
        client: MockClient(
          (_) async => http.Response('<script>alert(1)</script>', 200),
        ),
      );
      addTearDown(html.close);
      await expectLater(
        html.load(Uri.parse('https://example.com/x')),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'failed Markdown image can retry without a setState Future error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownImage(
              uri: Uri.parse('https://example.com/unavailable.gif'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test('albums preserve order, fill rows and have no single trailing hole', () {
    for (var count = 1; count <= 10; count++) {
      final rows = albumRows(count);
      expect(rows.expand((r) => r), List.generate(count, (i) => i));
      expect(rows.every((r) => r.isNotEmpty && r.length <= 3), isTrue);
      if (count > 1) expect(rows.last.length, greaterThanOrEqualTo(2));
    }
  });
  testWidgets(
    'media appears above the caption and all album cells receive taps',
    (tester) async {
      final c = MessengerController(store: MemorySecretStore())..startDemo();
      addTearDown(c.dispose);
      final bytes = File('assets/govor.png').readAsBytesSync();
      final files = [
        for (var i = 0; i < 3; i++)
          Attachment(
            id: 'image-$i',
            key: 'fixture',
            name: 'photo-$i.png',
            mime: 'image/png',
          ).toJson(),
      ];
      c.media = FakeAttachments(bytes);
      final m = ChatMessage(
        id: 'album',
        senderId: 'demo-friend',
        conversationId: 'demo-chat',
        type: 0,
        sentAt: DateTime.utc(2026),
        content: '',
        text: 'Album caption',
        attachments: files,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(
                message: m,
                controller: c,
                selectedIds: const {},
                onToggle: (_) {},
                onActions: (_, {position}) async {},
                onSave: (_) async {},
                onReact: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(AttachmentGallery)).dy,
        lessThan(tester.getTopLeft(find.text('Album caption')).dy),
      );
      final image = find.byType(Image).first;
      expect(tester.getSize(image).height, greaterThan(50));
      await tester.tap(image);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'composer previews can open a photo and remove it without touching other files',
    (tester) async {
      final bytes = File('assets/govor.png').readAsBytesSync();
      int? removed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentPreview(
              attachments: [
                const Attachment(
                  id: 'selected',
                  key: 'secret',
                  name: 'selected.png',
                  mime: 'image/png',
                ).toJson(),
              ],
              repository: FakeAttachments(bytes),
              onSave: (_) async {},
              onRemove: (i) => removed = i,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Удалить'));
      await tester.pumpAndSettle();
      expect(removed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reply preview shows the original, deletion and retry after a network error',
    (tester) async {
      final f = fixture.FlowFixture();
      addTearDown(f.controller.dispose);
      f.api.tokens = TokenPair.fromJson({
        'accessToken': testToken('reply-widget'),
        'refreshToken': 'refresh',
      });
      f.controller
        ..api = f.api
        ..encryption = f.encryption
        ..me = const Person(id: testUser, name: 'Me');
      var status = 200;
      f.overrideResponse = (r) => r.url.path == '/api/messages/original'
          ? status == 200
                ? http.Response(
                    jsonEncode(
                      f.message('original', content: 'Quoted original'),
                    ),
                    200,
                  )
                : http.Response('', status)
          : null;
      final message = ChatMessage(
        id: 'reply',
        senderId: fixture.peer,
        conversationId: fixture.chat,
        type: 0,
        sentAt: DateTime.utc(2026),
        content: '',
        text: 'Reply',
        replyTo: 'original',
      );
      Future<void> render() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReplyPreview(controller: f.controller, message: message),
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        });
        await tester.pumpAndSettle();
      }

      await render();
      expect(find.text('Quoted original'), findsOneWidget);
      status = 404;
      f.controller.replyRevision++;
      await render();
      expect(find.text('Сообщение удалено'), findsOneWidget);
      status = 500;
      f.controller.replyRevision++;
      await render();
      expect(find.text('Повторить'), findsOneWidget);
      status = 200;
      await tester.tap(find.text('Повторить'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pumpAndSettle();
      expect(find.text('Quoted original'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'auth uses system locale on login and registration without language controls',
    (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      final c = MessengerController(
        store: MemorySecretStore(),
        dependencies: AppDependencies(
          preferences: LocalPreferencesRepository(
            read: () async => null,
            write: (_) async {},
          ),
        ),
      )..booting = false;
      addTearDown(c.dispose);
      await c.settings.setLanguage('ru');
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byKey(const Key('auth-language')), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.ensureVisible(find.text('No account? Register'));
      await tester.tap(find.text('No account? Register'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byKey(const Key('auth-language')), findsNothing);
    },
  );
  testWidgets(
    'settings language menu uses glass and persists the selected locale',
    (tester) async {
      final c = MessengerController(
        store: MemorySecretStore(),
        dependencies: AppDependencies(
          preferences: LocalPreferencesRepository(
            read: () async => null,
            write: (_) async {},
          ),
        ),
      )..startDemo();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: govorTheme(Brightness.dark),
          home: Scaffold(body: LanguageSelector(settings: c.settings)),
        ),
      );
      await tester.tap(find.byKey(const Key('language-selector')));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsWidgets);
      await tester.tap(find.widgetWithText(MenuItemButton, 'English'));
      await tester.pumpAndSettle();
      expect(c.settings.state.language, 'en');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'expanded reaction picker has eight columns and search on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MessengerController(store: MemorySecretStore())..startDemo();
      addTearDown(c.dispose);
      await c.open(c.conversations.first);
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      final task = showMessageActions(
        tester.element(find.byKey(const Key('message-composer'))),
        c,
        c.messages.last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expand-reactions')));
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(
        find.byKey(const Key('reaction-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        8,
      );
      // Twelve reactions occupy two rows; the menu must not reserve a tall empty viewport.
      expect(
        tester.getSize(find.byKey(const Key('reaction-grid'))).height,
        lessThan(110),
      );
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.enterText(
        find.byKey(const Key('reaction-search')),
        'unavailable',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reaction-grid')), findsNothing);
      expect(tester.takeException(), isNull);
      Navigator.pop(tester.element(find.byKey(const Key('expand-reactions'))));
      await tester.pumpAndSettle();
      await task;
    },
  );
  testWidgets(
    'tag labels are plain text and revocation hides the label and official status',
    (tester) async {
      final c = MessengerController(store: MemorySecretStore())..startDemo();
      addTearDown(c.dispose);
      c.benefits.apply(
        c.userId,
        UserBenefits(
          revision: 1,
          isGovorPlus: false,
          canCustomizeProfileTag: true,
          tag: ProfileTag({'text': 'Govor+'}),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserBadge(controller: c, userId: c.userId),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Govor+'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      c.benefits.apply(c.userId, const UserBenefits(revision: 2));
      await tester.pumpAndSettle();
      expect(find.text('Govor+'), findsNothing);
    },
  );
  testWidgets(
    'tag editor validates and closes safely when privileges are revoked',
    (tester) async {
      final c = MessengerController(store: MemorySecretStore())..startDemo();
      addTearDown(c.dispose);
      c.benefits.apply(
        c.userId,
        const UserBenefits(revision: 1, canCustomizeProfileTag: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileTagEditor(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag-text')), 'New tag');
      await tester.pumpAndSettle();
      expect(find.text('New tag'), findsWidgets);
      c.benefits.apply(c.userId, const UserBenefits(revision: 2));
      await tester.pumpAndSettle();
      final save = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(save.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
