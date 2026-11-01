import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/app_dependencies.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/preferences_repository.dart';
import 'package:govor_mobile/core/server_ip_provider.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/ui/attachment_gallery.dart';
import 'package:govor_mobile/ui/message_actions.dart';
import 'support/fake_attachments.dart';

LocalPreferencesRepository memoryPreferences() {
  String? value;
  return LocalPreferencesRepository(
    read: () async => value,
    write: (text) async => value = text,
  );
}

void main() {
  test('boot uses injected service factories and preferences', () async {
    var created = 0;
    final preferences = memoryPreferences();
    await preferences.saveLanguage('en');
    final c = MessengerController(
      store: MemorySecretStore(),
      serverProvider: const ServerIpProvider(address: 'https://test.example'),
      dependencies: AppDependencies(
        preferences: preferences,
        api: (address, store) {
          created++;
          return ApiClient(address, store);
        },
      ),
    );
    addTearDown(c.dispose);
    await c.boot();
    expect(created, 1);
    expect(c.settings.state.language, 'en');
    expect(c.booting, isFalse);
  });
  testWidgets('touch long-press on message text opens the same compact menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MessengerController(store: MemorySecretStore())..startDemo();
    addTearDown(c.dispose);
    await c.open(c.conversations.first);
    await tester.pumpWidget(GovorApp(controller: c));
    await tester.pumpAndSettle();
    final message = find.byType(SelectableText).first;
    await tester.ensureVisible(message);
    await tester.longPress(message);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-action-copy')), findsOneWidget);
    expect(find.byKey(const Key('message-action-reply')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'desktop settings replace the right panel and translate without navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MessengerController(
        store: MemorySecretStore(),
        dependencies: AppDependencies(preferences: memoryPreferences()),
      )..startDemo();
      addTearDown(c.dispose);
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      final security = find.widgetWithText(ListTile, 'Защита переписки');
      await tester.ensureVisible(security);
      await tester.tap(security);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-desktop')), findsOneWidget);
      expect(
        find.byKey(const Key('settings-security-content')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('wallpaper-grid')), findsNothing);
      final packs = find.widgetWithText(ListTile, 'Паки реакций');
      await tester.ensureVisible(packs);
      await tester.tap(packs);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-reactions-content')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-desktop')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('settings-appearance')));
      await tester.tap(find.byKey(const Key('settings-appearance')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wallpaper-grid')), findsOneWidget);
      await c.settings.setLanguage('en');
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Choose appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clicking the active reaction chip removes it; menu can toggle it too',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = MessengerController(store: MemorySecretStore())..startDemo();
      addTearDown(c.dispose);
      await c.open(c.conversations.first);
      final message = c.messages.last;
      await c.react(message, 'demo-reaction-0');
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      expect(c.reactionStates[message.id]?['mine'], isNotNull);
      await tester.ensureVisible(find.byType(ActionChip).last);
      await tester.tap(find.byType(ActionChip).last);
      await tester.pumpAndSettle();
      expect(c.reactionStates[message.id]?['mine'], isNull);
      expect(c.reactionStates[message.id]?['counts'], isEmpty);
      final context = tester.element(find.byKey(const Key('message-composer')));
      final first = showMessageActions(
        context,
        c,
        message,
        position: const Offset(1240, 870),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('👍'));
      await tester.pumpAndSettle();
      await first;
      expect(c.reactionStates[message.id]?['mine'], isNotNull);
      final second = showMessageActions(context, c, message);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('👍'));
      await tester.pumpAndSettle();
      await second;
      expect(c.reactionStates[message.id]?['mine'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'photo gallery previews locally verified images and opens zoom viewer',
    (tester) async {
      final bytes = File('assets/govor.png').readAsBytesSync();
      final repo = FakeAttachments(bytes);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: AttachmentGallery(
                attachments: const [
                  {
                    'MediaId': 'a',
                    'Key': 'secret',
                    'FileName': 'photo.png',
                    'MimeType': 'image/png',
                  },
                ],
                repository: repo,
                onSave: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byType(Image));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('photo.png'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
