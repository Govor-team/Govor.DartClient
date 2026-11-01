import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/api_client.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/core/wallpapers.dart';
import 'package:govor_mobile/features/messenger_controller.dart';

WallpaperRepository memoryAppearance() {
  String? settings;
  return WallpaperRepository(
    read: () async => settings,
    write: (value) async {
      settings = value;
    },
  );
}

class DelayedDescriptionController extends MessengerController {
  DelayedDescriptionController()
    : super(
        store: MemorySecretStore(),
        wallpaperRepository: memoryAppearance(),
      );
  final saves = <({String text, Completer<void> completion})>[];
  @override
  Future<void> updateDescription(String text) async {
    final completion = Completer<void>();
    saves.add((text: text, completion: completion));
    await completion.future;
    await super.updateDescription(text);
  }
}

void main() {
  Future<void> setup(
    WidgetTester tester,
    MessengerController c,
    Size size,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(c.dispose);
    c.startDemo();
    await tester.pumpWidget(GovorApp(controller: c));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'profile adapts live from desktop grid to mobile carousel and preserves editing',
    (tester) async {
      final c = MessengerController(
        store: MemorySecretStore(),
        wallpaperRepository: memoryAppearance(),
      );
      await setup(tester, c, const Size(1440, 900));
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-desktop')), findsOneWidget);
      expect(find.byKey(const Key('wallpaper-grid')), findsOneWidget);
      expect(find.byTooltip('Добавить свой фон'), findsOneWidget);
      expect(find.byKey(const Key('import-wallpaper-tile')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('profile-theme-panel'))).height,
        lessThan(76),
      );
      final security = find.ancestor(
        of: find.text('Защита переписки'),
        matching: find.byType(ListTile),
      );
      expect(tester.getSize(security).height, lessThan(80));
      expect(tester.getSize(security).width, greaterThan(350));
      expect(find.text('Сохранить описание'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('profile-description')),
        'Описание с ПК',
      );
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(c.me!.description, 'Описание с ПК');
      await tester.tap(
        find.byKey(
          ValueKey('wallpaper-${MessengerController.wallpapers.first}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.wallpaper, MessengerController.wallpapers.first);

      for (final size in [
        const Size(390, 844),
        const Size(920, 650),
        const Size(1920, 1080),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.text('Описание с ПК'), findsOneWidget);
        expect(
          find.byKey(
            Key(size.width < 904 ? 'profile-mobile' : 'profile-desktop'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('import-wallpaper-tile')),
          size.width < 904 ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-desktop')), findsNothing);
    },
  );

  testWidgets(
    'autosave serializes edits and retains draft after failure and reopening',
    (tester) async {
      final c = DelayedDescriptionController();
      await setup(tester, c, const Size(1440, 900));
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-description')),
        'Первая версия',
      );
      await tester.pump(const Duration(milliseconds: 850));
      expect(c.saves.length, 1);
      await tester.enterText(
        find.byKey(const Key('profile-description')),
        'Последняя версия',
      );
      await tester.pump(const Duration(milliseconds: 850));
      expect(c.saves.length, 1);
      c.saves.first.completion.complete();
      await tester.pump();
      expect(c.saves.length, 2);
      expect(c.saves.last.text, 'Последняя версия');
      c.saves.last.completion.completeError(
        const ApiFailure(503, 'Нет соединения'),
      );
      await tester.pumpAndSettle();
      expect(c.profileDescriptionDraft, 'Последняя версия');
      expect(find.text('Повторить'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      // Leaving starts one last save; it may finish after the route is disposed.
      if (c.saves.length == 3) c.saves.last.completion.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Последняя версия'), findsOneWidget);
      expect(c.me!.description, 'Последняя версия');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop chat keeps draft across resize, sends with Ctrl+Enter and offers mouse menu',
    (tester) async {
      final c = MessengerController(
        store: MemorySecretStore(),
        wallpaperRepository: memoryAppearance(),
      );
      await setup(tester, c, const Size(1920, 1080));
      await tester.tap(find.text('Анастасия'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('message-composer')),
        'Отправлено с клавиатуры',
      );
      tester.view.physicalSize = const Size(800, 650);
      await tester.pumpAndSettle();
      expect(find.text('Отправлено с клавиатуры'), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('message-composer')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.messages.last.text, 'Отправлено с клавиатуры');
      final message = find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data == 'Отправлено с клавиатуры',
      );
      await tester.ensureVisible(message);
      await tester.tap(message, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-action-copy')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'custom wallpaper survives restart, deduplicates and falls back safely on removal',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final repository = memoryAppearance();
      final c = MessengerController(
        store: MemorySecretStore(),
        wallpaperRepository: repository,
      );
      final restored = MessengerController(
        store: MemorySecretStore(),
        wallpaperRepository: repository,
      );
      addTearDown(c.dispose);
      addTearDown(restored.dispose);
      final image = await File(
        'assets/backgrounds/background_girls.jpg',
      ).readAsBytes();
      await c.addWallpaper(image, 'Мой фон.jpg');
      await c.addWallpaper(image, 'Копия.jpg');
      expect(c.customWallpapers.length, 1);
      await restored.loadAppearance();
      expect(restored.wallpaper, c.wallpaper);
      expect(restored.customWallpaperBytes, image);
      await restored.removeWallpaper(restored.wallpaper!);
      expect(restored.wallpaper, MessengerController.wallpapers[1]);
      expect(restored.customWallpapers, isEmpty);
    },
  );

  test(
    'storage failure preserves selected background and rejects non-image imports',
    () async {
      final c = MessengerController(
        store: MemorySecretStore(),
        wallpaperRepository: WallpaperRepository(
          read: () async => null,
          write: (_) async => throw FileSystemException('Full disk'),
        ),
      );
      addTearDown(c.dispose);
      final previous = c.wallpaper;
      await expectLater(
        c.setAppearance(background: MessengerController.wallpapers.first),
        throwsA(isA<FileSystemException>()),
      );
      expect(c.wallpaper, previous);
      await expectLater(
        c.addWallpaper(await File('pubspec.yaml').readAsBytes(), 'fake.png'),
        throwsException,
      );
      expect(c.customWallpapers, isEmpty);
    },
  );
}
