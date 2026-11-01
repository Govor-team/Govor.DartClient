import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govor_mobile/app.dart';
import 'package:govor_mobile/core/models.dart';
import 'package:govor_mobile/core/storage.dart';
import 'package:govor_mobile/features/messenger_controller.dart';
import 'package:govor_mobile/l10n/l10n.dart';
import 'package:govor_mobile/ui/avatar_preview.dart';

class AvatarController extends MessengerController {
  AvatarController() : super(store: MemorySecretStore()) {
    startDemo();
  }
}

void main() {
  final photo = File(
    'assets/backgrounds/background_girls.jpg',
  ).readAsBytesSync();

  Future<void> display(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'small preview saves the original bytes once and permits retry after a save failure',
    (tester) async {
      final c = AvatarController()..avatarBytes['photo'] = photo;
      addTearDown(c.dispose);
      final completion = Completer<void>();
      var calls = 0;
      await display(
        tester,
        AvatarPreviewDialog(
          controller: c,
          name: '../../CON.exe',
          imageId: 'photo',
          save: (name, bytes) async {
            calls++;
            expect(name, 'avatar.png');
            expect(bytes, photo);
            if (calls == 1) await completion.future;
          },
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('avatar-preview'))).width,
        lessThanOrEqualTo(360),
      );
      final download = find.byKey(const Key('download-avatar'));
      expect(tester.widget<FilledButton>(download).onPressed, isNotNull);
      await tester.tap(download);
      await tester.pump();
      expect(tester.widget<FilledButton>(download).onPressed, isNull);
      completion.completeError(StateError('disk full'));
      await tester.pumpAndSettle();
      expect(find.text('Не удалось сохранить файл'), findsOneWidget);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Не удалось сохранить файл'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing avatar can retry; invalid bytes cannot be downloaded', (
    tester,
  ) async {
    final c = AvatarController();
    addTearDown(c.dispose);
    await display(
      tester,
      AvatarPreviewDialog(
        controller: c,
        name: 'Group',
        imageId: 'photo',
        group: true,
      ),
    );
    final download = find.byKey(const Key('download-avatar'));
    expect(tester.widget<FilledButton>(download).onPressed, isNull);
    expect(find.text('Не удалось загрузить аватарку.'), findsOneWidget);
    c.avatarBytes['photo'] = Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
    ]);
    await tester.runAsync(() async {
      await tester.tap(find.text('Повторить загрузку'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(download).onPressed, isNull);
    c.avatarBytes['photo'] = photo;
    await tester.runAsync(() async {
      await tester.tap(find.text('Повторить загрузку'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(download).onPressed, isNotNull);

    await c.logout();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(download).onPressed, isNull);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'member preview resolves the user avatar and remains scrollable on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 340);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 24 / 14;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = AvatarController()..avatarBytes['photo'] = photo;
      c.avatarBytes['member-photo'] = photo;
      c.friends = [
        const Person(id: 'member', name: 'Member', iconId: 'member-photo'),
      ];
      addTearDown(c.dispose);
      await display(
        tester,
        AvatarPreviewDialog(controller: c, name: 'Member', userId: 'member'),
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('download-avatar')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('download-avatar')))
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chat and settings avatars open the preview without triggering their parent actions',
    (tester) async {
      final c = AvatarController();
      addTearDown(c.dispose);
      await tester.pumpWidget(GovorApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PreviewAvatar).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-preview')), findsOneWidget);
      expect(c.selected, isNull);
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PreviewAvatar).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
