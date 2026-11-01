import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1280, 860),
    const Size(820, 700),
  ]) {
    testWidgets(
      'adaptive demo at ${size.width.toInt()}px: open, send, search',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = MessengerController(store: MemorySecretStore())
          ..startDemo();
        addTearDown(controller.dispose);
        await tester.pumpWidget(GovorApp(controller: controller));
        await tester.pumpAndSettle();
        expect(find.text('Анастасия'), findsOneWidget);
        await tester.tap(find.text('Анастасия'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('message-composer')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('message-composer')),
          'Тестовое сообщение',
        );
        await tester.tap(find.byKey(const Key('send-message')));
        await tester.pumpAndSettle();
        expect(controller.messages.last.text, 'Тестовое сообщение');
        if (size.width < 820) {
          await tester.tap(find.byKey(const Key('back-to-chats')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Поиск разговоров'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('chat-search')), 'Михаил');
        await tester.pumpAndSettle();
        expect(
          find
              .text('Михаил', findRichText: false)
              .evaluate()
              .where((e) => e.widget is Text),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('sign-in validates before network; password stays obscured', (
    tester,
  ) async {
    final controller = MessengerController(store: MemorySecretStore())
      ..booting = false;
    addTearDown(controller.dispose);
    await tester.pumpWidget(GovorApp(controller: controller));
    await tester.pumpAndSettle();
    final password = tester.widget<TextFormField>(
      find.byKey(const Key('password-field')),
    );
    expect(password, isNotNull);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('password-field')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.byKey(const Key('server-field')), findsNothing);
    expect(controller.api, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('small screen with large text remains usable', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = MessengerController(store: MemorySecretStore())..startDemo();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: GovorApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Анастасия'));
    await tester.pumpAndSettle();
  });
  testWidgets('draft survives switching chats and logout clears demo memory', (
    tester,
  ) async {
    final c = MessengerController(store: MemorySecretStore())..startDemo();
    addTearDown(c.dispose);
    await tester.pumpWidget(GovorApp(controller: c));
    await c.open(c.conversations.first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('message-composer')),
      'Черновик',
    );
    c.closeChat();
    await tester.pumpAndSettle();
    await c.open(c.conversations.first);
    await tester.pumpAndSettle();
    expect(find.text('Черновик'), findsOneWidget);
    await c.logout();
    await tester.pumpAndSettle();
    expect(c.messages, isEmpty);
    expect(c.drafts, isEmpty);
    expect(c.ready, isFalse);
  });
}
